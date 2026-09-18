"""Find a track's racing line and cell divisions from its board image.

Turning a board image into the space graph docs/track-format.md describes.

The spaces are printed on the board as a grid of dark grey lines, right down
to the line inside the white track limit, so each cell is simply the asphalt
left over once those lines are taken away. Reading them straight off the
artwork gets the radial cells in corners right, and keeps the lanes in step
with one another, which offsetting from a racing line never managed.

The racing line is still traced, but only to say which lane a cell is in and
what order the cells come in.

What it does not know: which way round the track runs (pass --reverse if the
facings come out backwards), where the corners are and how many stops they
need, the start grid, the finish line and the pit lane.

The image is read from the local TTS cache, the same way extract_dice.py does
it, so load the mod in TTS once first.

Run:  python tools/extract/detect_track.py FDMonaco
"""
import json
import math
import os
import pathlib
import re
import sys

import cv2
import numpy as np
from scipy.ndimage import median_filter
from scipy.signal import find_peaks
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize

LANES = 3  # widest point of the track; per-track once more maps are done

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "extract" / "out"
def documents_dir():
    """The user's Documents folder, wherever Windows has put it.

    Often redirected (OneDrive), so ask the registry rather than assume
    ~/Documents.
    """
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                             r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")
        value, _ = winreg.QueryValueEx(key, "Personal")
        return pathlib.Path(os.path.expandvars(value))
    except (ImportError, OSError):
        return pathlib.Path(os.path.expanduser("~")) / "Documents"


TTS_DIR = documents_dir() / "My Games" / "Tabletop Simulator"
MODS = pathlib.Path(os.environ.get("TTS_MODS", TTS_DIR / "Mods"))


def board_image(map_id):
    maps = json.loads((ROOT / "tools" / "extract" / "maps.json").read_text(encoding="utf-8"))
    hit = next((m for m in maps if m["id"] == map_id), None)
    if not hit:
        sys.exit(f"unknown map id {map_id}")
    key = re.sub(r"[^A-Za-z0-9]", "", hit["url"].split("ugc/")[-1])
    for f in (MODS / "Images").iterdir():
        if key in f.name:
            im = cv2.imread(str(f))
            if im is not None:
                return hit, im
    sys.exit(f"{hit['name']} is not in the TTS cache -- open it in game once")




def road_mask(im):
    """The asphalt ribbon.

    Closing bridges the red corner lines drawn across the road, but it also
    welds together stretches that merely run alongside each other, which lets
    a path cut the corner later on. So the white kerb lines are cut back out
    afterwards to separate neighbouring passes again.

    That leaves real breaks where something is painted right across the road,
    such as the start/finish band; bridge_ends() repairs those later.
    """
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    S, V = hsv[..., 1], hsv[..., 2]
    grey = ((S < 50) & (V > 105) & (V < 205)).astype(np.uint8) * 255
    white = ((S < 60) & (V >= 205)).astype(np.uint8) * 255
    white = cv2.dilate(white, np.ones((3, 3), np.uint8))
    m = cv2.morphologyEx(grey, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    m[white > 0] = 0
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    _, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    return (lab == 1 + int(np.argmax(stats[1:, 4]))).astype(np.uint8)


def graph_of(points, radius=1.5, extra=()):
    tree = cKDTree(points)
    pairs = [p for p in sorted(tree.query_pairs(radius))]
    pairs += list(extra)
    pairs = np.array(pairs)
    w = np.hypot(*(points[pairs[:, 0]] - points[pairs[:, 1]]).T)
    n = len(points)
    g = coo_matrix((np.r_[w, w], (np.r_[pairs[:, 0], pairs[:, 1]],
                                 np.r_[pairs[:, 1], pairs[:, 0]])), shape=(n, n))
    return g.tocsr()


def bridge_ends(points, reach=170, straightness=0.8):
    """Join skeleton ends that point at each other across a gap.

    The road is broken wherever something is painted across it in a colour the
    mask rejects -- the start/finish band, a tunnel mouth. Both sides leave a
    loose end whose direction of travel lines up with the gap, which is what
    tells them apart from the ends of a genuine dead end.
    """
    tree = cKDTree(points)
    adj = {}
    for i, j in tree.query_pairs(1.5):
        adj.setdefault(i, []).append(j)
        adj.setdefault(j, []).append(i)
    ends = [i for i in range(len(points)) if len(adj.get(i, ())) <= 1]

    def heading(i):
        # Average direction over the nearest stretch of this end's own branch.
        seen, frontier = {i}, [i]
        for _ in range(12):
            nxt = []
            for a in frontier:
                for b in adj.get(a, ()):
                    if b not in seen:
                        seen.add(b)
                        nxt.append(b)
            frontier = nxt
        far = points[list(seen)].mean(axis=0)
        v = points[i] - far
        n = np.hypot(*v)
        return v / n if n > 1e-6 else None

    heads = {i: heading(i) for i in ends}
    bridges = []
    for a in ends:
        for b in tree.query_ball_point(points[a], reach):
            if b <= a or b not in heads or heads[a] is None or heads[b] is None:
                continue
            d = points[b] - points[a]
            n = np.hypot(*d)
            if n < 2:
                continue
            u = d / n
            if float(np.dot(heads[a], u)) > straightness and float(np.dot(heads[b], -u)) > straightness:
                bridges.append((a, b))
    return bridges


def path(pred, a, b):
    out, cur = [b], b
    while cur != a:
        cur = int(pred[cur])
        if cur < 0:
            return None
        out.append(cur)
    return out[::-1]


def find_cycle(points, extra=()):
    """The loop through `points`: two independent shortest paths between the
    two most distant points, which together close the ring."""
    g = graph_of(points, extra=extra)
    d0, p0 = dijkstra(g, indices=0, return_predecessors=True)
    finite = np.isfinite(d0)
    a = int(np.argmax(np.where(finite, d0, -1)))
    da, pa = dijkstra(g, indices=a, return_predecessors=True)
    b = int(np.argmax(np.where(np.isfinite(da), da, -1)))
    first = path(pa, a, b)

    # Block the first path (except its ends) and go round the other way.
    keep = np.ones(len(points), bool)
    keep[first[1:-1]] = False
    keep[a] = keep[b] = True
    idx = np.flatnonzero(keep)
    remap = -np.ones(len(points), int)
    remap[idx] = np.arange(len(idx))
    remapped = [(remap[a], remap[b]) for a, b in extra
                if remap[a] >= 0 and remap[b] >= 0]
    g2 = graph_of(points[idx], extra=remapped)
    d2, p2 = dijkstra(g2, indices=remap[a], return_predecessors=True)
    second = path(p2, remap[a], remap[b])
    if second is None:
        return points[first]
    second = idx[second]
    return points[first + list(second[::-1][1:-1])]


def resample(loop, step):
    pts = np.r_[loop, loop[:1]].astype(float)
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(pts, axis=0).T))]
    s = np.arange(0, d[-1], step)
    return np.c_[np.interp(s, d, pts[:, 1]), np.interp(s, d, pts[:, 0])], d[-1]


def smooth_closed(a, win):
    """Moving average around a closed loop."""
    k = np.ones(win) / win
    pad = np.r_[a[-win:], a, a[:win]]
    if pad.ndim == 1:
        return np.convolve(pad, k, "same")[win:-win]
    return np.stack([np.convolve(pad[:, i], k, "same")[win:-win] for i in range(a.shape[1])], 1)


def normals(line):
    t = np.gradient(line, axis=0)
    t /= np.linalg.norm(t, axis=1, keepdims=True) + 1e-9
    return np.c_[-t[:, 1], t[:, 0]]


def keep_long(binary, min_extent):
    """Only the components that run further than `min_extent` pixels."""
    n, lab, stats, _ = cv2.connectedComponentsWithStats(binary.astype(np.uint8), 8)
    out = np.zeros(binary.shape, np.uint8)
    for i in range(1, n):
        if max(stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT]) >= min_extent:
            out[lab == i] = 1
    return out


def interior_marks(grey, white_small, surround=0.85):
    """Small white marks that sit inside the road rather than along its edge.

    The grid boxes and the checkered band are printed on the asphalt and are
    road; the white dashes of a dashed kerb are the edge itself. They are told
    apart by what surrounds them -- a mark ringed by asphalt is road.
    """
    n, lab, stats, _ = cv2.connectedComponentsWithStats(white_small, 8)
    out = np.zeros(grey.shape, np.uint8)
    pad = 4
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1, y1 = min(grey.shape[1], x + w + pad), min(grey.shape[0], y + h + pad)
        sub = (lab[y0:y1, x0:x1] == i).astype(np.uint8)
        ring = cv2.dilate(sub, np.ones((2 * pad + 1, 2 * pad + 1), np.uint8)) - sub
        if ring.sum() and (grey[y0:y1, x0:x1][ring > 0] > 0).mean() >= surround:
            out[y0:y1, x0:x1][sub > 0] = 1
    return out


def surface_mask(im):
    """The road as a player sees it: asphalt, plus the marks printed on it.

    road_mask has to cut every white pixel to keep neighbouring stretches
    apart; here the marks that sit inside the road are put back, so the shape
    of the road is not full of holes.
    """
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    S, V = hsv[..., 1], hsv[..., 2]
    grey = ((S < 50) & (V > 105) & (V < 205)).astype(np.uint8)
    white = ((S < 60) & (V >= 205)).astype(np.uint8)
    kerbs = keep_long(white, 60)
    marks = interior_marks(grey, (white - kerbs).astype(np.uint8))
    m = ((grey | marks) > 0).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    # Closing can smear across a kerb into whatever lies beyond it, so put the
    # kerb lines back afterwards: they are the edge of the road.
    m[cv2.dilate(kerbs, np.ones((3, 3), np.uint8)) > 0] = 0
    return (m > 0).astype(np.uint8)


def inner_side(line, norm):
    """Which way the normals point: +1 if towards the inside of the loop."""
    poly = line.astype(np.float32)
    probe = line + norm * 12.0
    inside = sum(cv2.pointPolygonTest(poly, (float(x), float(y)), False) > 0
                 for x, y in probe[::7])
    return 1 if inside > len(probe[::7]) / 2 else -1



def printed_cells(im, surface, contrast=8, blur=21):
    """Segment the cells printed on the road.

    The grid is drawn in dark grey on lighter asphalt, so anything darker than
    its surroundings is a line; what is left over, cell by cell, is a space.
    The arrows inside corner cells are dark too, but they are islands within a
    cell and leave it in one piece.
    """
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    background = cv2.medianBlur(gray, blur).astype(np.float32)
    lines = ((background - gray.astype(np.float32)) > contrast) & (surface > 0)
    lines = cv2.morphologyEx(lines.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    cells = ((surface > 0) & (lines == 0)).astype(np.uint8)
    return cv2.morphologyEx(cells, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))


def on_track(labels, stats, centroids, line, reach, area=(250, 8000)):
    """Keep the blobs that are cells of the track itself.

    Rules out the buildings and crowds either side, and for now the pit road,
    which sits further from the racing line than any lane of the track.
    """
    rail = np.zeros(labels.shape, np.uint8)
    cv2.polylines(rail, [line.astype(np.int32).reshape(-1, 1, 2)], True, 255, 1)
    dist = cv2.distanceTransform(255 - rail, cv2.DIST_L2, 5)
    keep = []
    for i in range(1, len(stats)):
        if not area[0] <= stats[i, 4] <= area[1]:
            continue
        cx, cy = centroids[i]
        if dist[int(round(cy)), int(round(cx))] <= reach:
            keep.append(i)
    return keep, dist


def neighbours_of(labels, wanted, reach=3):
    """Which cells touch which, across the line drawn between them."""
    want = np.zeros(labels.max() + 2, bool)
    want[list(wanted)] = True
    pairs = set()
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = labels[reach:-reach, reach:-reach]
        b = labels[reach + dy * reach:labels.shape[0] - reach + dy * reach,
                   reach + dx * reach:labels.shape[1] - reach + dx * reach]
        m = (a > 0) & (b > 0) & (a != b) & want[a] & want[b]
        for u, v in zip(a[m], b[m]):
            pairs.add((int(min(u, v)), int(max(u, v))))
    adj = {}
    for u, v in pairs:
        adj.setdefault(u, set()).add(v)
        adj.setdefault(v, set()).add(u)
    return adj


def cell_points(labels, stats, centroids, keep, line, tangent, merge=1.6):
    """One point per printed cell.

    Where a division line is too faint to register, neighbouring cells come
    out as one blob -- two, three, even four cells long. A blob that is a clean
    multiple of the usual cell size is cut into that many pieces along the
    direction of travel.
    """
    typical = float(np.median([stats[i, 4] for i in keep]))
    tree = cKDTree(line)
    points, split = [], 0
    for i in keep:
        k = int(round(stats[i, 4] / typical)) if stats[i, 4] > merge * typical else 1
        if k <= 1:
            points.append(tuple(centroids[i]))
            continue
        ys, xs = np.nonzero(labels == i)
        _, at = tree.query(centroids[i])
        t = xs * tangent[at][0] + ys * tangent[at][1]
        cuts = np.quantile(t, np.linspace(0, 1, k + 1))
        for a, b in zip(cuts[:-1], cuts[1:]):
            part = (t >= a) & (t <= b)
            points.append((float(xs[part].mean()), float(ys[part].mean())))
        split += 1
    return points, typical, split


def place_cells(points, line, norm, side, tangent):
    """Where each cell sits: along the lap, across the road, and facing where."""
    tree = cKDTree(line)
    info = {}
    for i, (cx, cy) in enumerate(points):
        _, at = tree.query([cx, cy])
        off = np.array([cx, cy]) - line[at]
        info[i] = {
            "along": int(at),                                   # step along the lap
            "across": float(np.dot(off, norm[at]) * side),      # + is towards the inside
            "pos": (float(cx), float(cy)),
            "rot": float(math.degrees(math.atan2(tangent[at][1], tangent[at][0]))),
        }
    return info


def sort_lanes(keep, info, lanes, lane_width, n_steps, window=20):
    """Number the lanes from the inside out.

    Distance from the racing line alone will not do it: through a corner the
    traced line drifts off the middle, so a fixed threshold puts whole
    stretches in the wrong lane. Instead each cell is compared with the cells
    around it along the road: locally, the middle of those is the middle lane,
    and a cell's lane is how many lane widths it sits either side of that.
    """
    along = np.array([info[i]["along"] for i in keep])
    across = np.array([info[i]["across"] for i in keep])
    middle = (lanes + 1) / 2
    lane = {}
    for k, i in enumerate(keep):
        gap = np.abs(along - along[k])
        gap = np.minimum(gap, n_steps - gap)            # the lap wraps round
        near = across[gap <= window]
        centre = float(np.median(near))
        l = int(round(middle - (across[k] - centre) / lane_width))
        lane[i] = min(max(l, 1), lanes)
    return lane


def corner_lines(im, min_extent=40):
    """The red lines painted across the road where a corner starts and ends.

    They are road, and leaving them out cuts the track at every corner. The
    red dashes of a kerb are red too, but each is a short block; a corner line
    runs the width of the road.
    """
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    red = ((H <= 10) | (H >= 168)) & (S > 90) & (V > 80)
    return keep_long(red, min_extent)


def edge_line(im, surface, contrast=6):
    """The thin dark line printed along the track limit.

    It runs just inside the kerb all the way round, a pixel or two wide and
    close to one colour, broken only at the start/finish band. Found as dark
    pixels with kerb on one side and road on the other -- which leaves out the
    division lines between cells, and the red corner lines that run out onto
    the kerb and would otherwise drag the edge off the track.
    """
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    background = cv2.medianBlur(gray, 15).astype(np.float32)
    dark = (background - gray.astype(np.float32)) > contrast
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    # A kerb is a long white line, or the red blocks of a dashed one. The
    # white squares of the start/finish band and the outlines of the grid
    # boxes are short, and the dark squares and lines beside them are not
    # the track edge.
    white = keep_long((S < 60) & (V >= 205), 60) > 0
    red = ((H <= 10) | (H >= 168)) & (S > 90) & (V > 80)
    kerb = (white | (red & (corner_lines(im) == 0))).astype(np.uint8)
    beside = np.ones((5, 5), np.uint8)
    near_kerb = cv2.dilate(kerb, beside) > 0
    near_road = cv2.dilate(surface, beside) > 0
    return (dark & near_kerb & near_road).astype(np.uint8)


def outer_edge(edge_pixels, line, norm, side, width, reverse, step=6.0, jump=2.5, min_run=3):
    """The outside edge of the track, as one ordered loop.

    "Outside" means the same side of the road all the way round -- the
    driver's outer hand -- not the outside of the shape. Where the track folds
    into the infield, as Loews does, every edge of the fold faces inwards and
    an outline would cut straight across the pinch. So take every pixel of the
    printed edge line, keep those on the outer side of the racing line, and
    read them off in running order.
    """
    pts = np.argwhere(edge_pixels > 0)[:, ::-1].astype(float)
    _, at = cKDTree(line).query(pts)
    off = np.einsum("ij,ij->i", pts - line[at], norm[at]) * side   # + is inwards
    # The edge sits about half a road out. Much nearer is a hole inside the
    # road; much further is somebody else's road.
    ok = (off < -0.3 * width) & (off > -0.85 * width)
    pts, at, off = pts[ok], at[ok], off[ok]
    n = len(line)
    edge = np.full((n, 2), np.nan)
    offset = np.full(n, np.nan)
    for a in range(n):
        hit = at == a
        if hit.any():
            edge[a] = np.median(pts[hit], axis=0)
            offset[a] = np.median(off[hit])
    have = ~np.isnan(offset)
    idx = np.arange(n)

    # Where a corner line is painted over the edge line there is nothing to
    # find, and a dark fleck in the kerb can stand in for it. The edge's
    # distance from the racing line changes smoothly, so a step that jumps
    # away from its neighbours is thrown out and filled from either side.
    filled = np.interp(idx, idx[have], offset[have], period=n)
    expected = median_filter(filled, size=15, mode="wrap")
    have &= np.abs(filled - expected) <= jump

    # Only what was actually found: runs of steps where the edge line was
    # seen, left as separate pieces. Gaps stay gaps so they can be looked at.
    pieces, run = [], []
    order = range(n - 1, -1, -1) if reverse else range(n)
    for a in order:
        if have[a]:
            run.append(edge[a])
        elif run:
            pieces.append(run)
            run = []
    if run:
        # The lap wraps round: join the last run onto the first if they meet.
        if pieces and have[order[0]]:
            pieces[0] = run + pieces[0]
        else:
            pieces.append(run)
    thin = max(1, int(round(step / (np.hypot(*np.diff(line, axis=0).T).mean()))))
    pieces = [np.array(p)[::thin] for p in pieces if len(p) >= min_run]
    return pieces, have.mean()


def racing_line(im):
    """The middle of the road, as one closed loop, plus the road width."""
    mask = road_mask(im)
    dist = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    skel = skeletonize(mask > 0)
    # The pit road is one lane wide (~25 px on Monaco) and the track three
    # (~73); cut between them, low enough to keep the track in one piece.
    keep = skel & (dist * 2 > 35)
    lab = cv2.connectedComponents(keep.astype(np.uint8), 8)[1]
    sizes = np.bincount(lab[keep])
    pts = np.argwhere(lab == int(np.argmax(sizes[1:])) + 1)
    loop = find_cycle(pts, extra=bridge_ends(pts))
    line, length = resample(loop, 3.0)
    width = float(np.median([dist[int(round(y)), int(round(x))] * 2 for x, y in line]))
    return smooth_closed(line, 7), length, width


def link(keep, info, lane, reverse, n_steps, reach=45):
    """Order each lane round the lap and connect every cell to the ones ahead.

    A car moves to the next cell in its lane, or diagonally into a lane beside
    it. The diagonal target is the cell in that lane closest to where the
    straight-on move lands, looked for only ahead and only nearby -- touching
    blobs alone are too loose, since a split cell touches several.
    """
    direction = -1 if reverse else 1

    def ahead_by(a, b):
        return ((info[b]["along"] - info[a]["along"]) * direction) % n_steps

    order = {}
    for i in keep:
        order.setdefault(lane[i], []).append(i)
    for l in order:
        order[l].sort(key=lambda i: info[i]["along"], reverse=reverse)

    nxt = {}
    for l, cells in order.items():
        for k, i in enumerate(cells):
            straight = cells[(k + 1) % len(cells)]
            targets = {straight}
            for side_lane in (l - 1, l + 1):
                best, best_d = None, None
                for j in order.get(side_lane, ()):
                    g = ahead_by(i, j)
                    if not 2 <= g <= reach:
                        continue
                    d = abs(((info[j]["along"] - info[straight]["along"]) + n_steps / 2) % n_steps - n_steps / 2)
                    if best is None or d < best_d:
                        best, best_d = j, d
                if best is not None:
                    targets.add(best)
            nxt[i] = targets
    return order, nxt


def find_spaces(labels, stats, centroids, blobs, line, norm, side, tangent, width, reverse):
    """Spaces from the printed cells. Parked behind --spaces for now: the
    outer edge is being checked first."""
    points, typical, split = cell_points(labels, stats, centroids, blobs, line, tangent)
    print("cell size %.0f px; split %d merged blob(s)" % (typical, split))
    info = place_cells(points, line, norm, side, tangent)
    keep = list(info)
    lane = sort_lanes(keep, info, LANES, width / LANES, len(line))
    order, nxt = link(keep, info, lane, reverse, len(line))
    print("cells on the track: %d  -- per lane: %s"
          % (len(keep), ", ".join("%d: %d" % (l, len(order[l])) for l in sorted(order))))
    ids = {}
    for l in sorted(order):
        for i in order[l]:
            ids[i] = len(ids) + 1
    spaces = []
    for l in sorted(order):
        for k, i in enumerate(order[l]):
            spaces.append({
                "id": ids[i],
                "pos": [round(info[i]["pos"][0], 1), round(info[i]["pos"][1], 1)],
                "rot": round(info[i]["rot"], 1),
                "lane": l,
                "next": sorted(ids[j] for j in nxt[i]),
                "corner": None,
                "sector": k + 1,
            })
    return sorted(spaces, key=lambda sp: sp["id"])


def write_track(info, im, spaces, lanes, path, reverse, outer=()):
    track = {
        "detect": {"reverse": reverse},
        # The outside edge of the road, as the pieces where it was found.
        "outer": [[[round(float(x), 1), round(float(y), 1)] for x, y in piece] for piece in outer],
        "id": info["id"],
        "name": info["name"],
        "ruleset": "formula_d" if info["category"] == "formula_d" else "formula_de",
        "image": {"width": im.shape[1], "height": im.shape[0]},
        "lanes": lanes,
        "laps": 2,
        "spaces": spaces,
        "corners": [],
        "start": [],
        "finish": {"line": []},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(track, indent=1), encoding="utf-8")


def main():
    # The spaces now come from find_grid.py, which reads the printed grid
    # directly; this module keeps the pieces it builds on (the road mask, the
    # racing line) and no longer writes track files itself.
    sys.exit("Use tools/extract/find_grid.py to find a track's spaces.")


if __name__ == "__main__":
    sys.exit(main())
