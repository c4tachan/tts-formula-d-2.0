"""Find a track's racing line and cell divisions from its board image.

Turning a board image into the space graph docs/track-format.md describes:
the racing line, the divisions between cells, and a space per lane per cell
with its facing and the cells it leads to.

What it does not know yet: which way round the track runs (pass --reverse if
the facings come out backwards), where the corners are and how many stops
they need, the start grid, the finish line and the pit lane. Those are read
off the board by eye and added to the track file afterwards.

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
from scipy.signal import find_peaks
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize

LANES = 3  # widest point of the track; per-track once more maps are done

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "extract" / "out"
MODS = pathlib.Path(os.environ.get(
    "TTS_MODS",
    pathlib.Path(os.path.expanduser("~")) / "Documents" / "My Games" / "Tabletop Simulator" / "Mods"))


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


def lane_darkness(gray, line, norm, widths, lanes):
    """Median grey within each lane band, at every step along the line."""
    out = np.zeros((len(line), lanes))
    for li in range(lanes):
        lo = -0.45 + 0.9 * li / lanes
        hi = -0.45 + 0.9 * (li + 1) / lanes
        cols = []
        for f in np.linspace(lo + 0.03, hi - 0.03, 9):
            xs = np.clip((line[:, 0] + norm[:, 0] * f * widths).astype(int), 0, gray.shape[1] - 1)
            ys = np.clip((line[:, 1] + norm[:, 1] * f * widths).astype(int), 0, gray.shape[0] - 1)
            cols.append(gray[ys, xs])
        out[:, li] = np.median(np.stack(cols, 1), axis=1)
    return out


def darker_than_neighbours(sig, half=1, gap=2, side=3):
    """How much darker the road is here than a little before and after."""
    def mean_over(lo, hi):
        return np.mean([np.roll(sig, -k) for k in range(lo, hi + 1)], axis=0)
    return np.minimum(mean_over(-(gap + side), -gap), mean_over(gap, gap + side)) - mean_over(-half, half)


def divisions(gray, line, norm, widths, lanes, step, min_gap=30, prominence=3.0):
    """Where the lines dividing one cell from the next cross the road.

    A division crosses every lane, while the arrows printed inside corner
    cells sit within one, so each lane votes and the weakest one wins.
    """
    per_lane = np.stack([darker_than_neighbours(d) for d in
                         lane_darkness(gray, line, norm, widths, lanes).T], 1)
    score = smooth_closed(per_lane.min(axis=1), 3)
    wrapped = np.r_[score, score[:int(min_gap / step) + 10]]
    pk, _ = find_peaks(wrapped, distance=min_gap / step, prominence=prominence)
    return np.unique(pk[pk < len(line)]), score


def fill_divisions(div, n, window=5):
    """Put back divisions the detector missed.

    Cells are near enough evenly spaced, so a gap that is a clean multiple of
    its neighbours is one the filter skipped rather than a longer cell.
    """
    gaps = np.diff(np.r_[div, div[0] + n]).astype(float)
    out, added = [], 0
    for i, g in enumerate(gaps):
        local = np.median(np.take(gaps, range(i - window, i + window + 1), mode="wrap"))
        k = max(1, int(round(g / local))) if local > 0 else 1
        out.append(float(div[i]))
        for j in range(1, k):
            out.append((div[i] + g * j / k) % n)
            added += 1
    return np.sort(np.array(out)), added


def at(arr, idx):
    """Sample a per-step array at fractional steps, wrapping round the loop."""
    n = len(arr)
    i0 = np.floor(idx).astype(int) % n
    i1 = (i0 + 1) % n
    f = (idx - np.floor(idx))[:, None] if arr.ndim > 1 else (idx - np.floor(idx))
    return arr[i0] * (1 - f) + arr[i1] * f


def inner_side(line, norm):
    """Which way the normals point: +1 if towards the inside of the loop."""
    poly = line.astype(np.float32)
    probe = line + norm * 12.0
    inside = sum(cv2.pointPolygonTest(poly, (float(x), float(y)), False) > 0
                 for x, y in probe[::7])
    return 1 if inside > len(probe[::7]) / 2 else -1


def build_spaces(line, norm, widths, div, lanes, reverse=False):
    """A space per lane per cell, in running order."""
    n = len(line)
    centres = []
    for i in range(len(div)):
        a, b = div[i], div[(i + 1) % len(div)]
        if b < a:
            b += n
        centres.append(((a + b) / 2) % n)
    centres = np.array(centres)
    if reverse:
        centres = centres[::-1]

    pos = at(line, centres)
    tan = at(line, (centres + 1) % n) - at(line, (centres - 1) % n)
    if reverse:
        tan = -tan
    tan /= np.linalg.norm(tan, axis=1, keepdims=True) + 1e-9
    nrm = at(norm, centres)
    wid = at(widths, centres)
    side = inner_side(line, norm)

    spaces = []
    for c in range(len(centres)):
        for lane in range(1, lanes + 1):
            # Lane 1 is the innermost, so step out from the inside edge.
            frac = (0.5 - (lane - 0.5) / lanes) * side
            p = pos[c] + nrm[c] * frac * wid[c] * 0.92
            heading = math.degrees(math.atan2(tan[c][1], tan[c][0]))
            nxt = []
            for other in (lane - 1, lane, lane + 1):
                if 1 <= other <= lanes:
                    nxt.append(((c + 1) % len(centres)) * lanes + other)
            spaces.append({
                "id": c * lanes + lane,
                "pos": [round(float(p[0]), 1), round(float(p[1]), 1)],
                "rot": round(heading, 1),
                "lane": lane,
                "next": nxt,
                "corner": None,
                "sector": c + 1,
            })
    return spaces


def write_track(info, im, spaces, lanes, path, reverse):
    track = {
        "detect": {"reverse": reverse},
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
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    map_id = args[0] if args else "FDMonaco"
    # Which way round the track runs cannot be read off the image, so it is
    # remembered in the track file once set.
    existing = ROOT / "tracks" / f"{map_id}.json"
    reverse = False
    if existing.exists():
        reverse = json.loads(existing.read_text(encoding="utf-8")).get("detect", {}).get("reverse", False)
    if "--reverse" in sys.argv:
        reverse = not reverse
    print("running direction:", "reversed" if reverse else "as traced")
    info, im = board_image(map_id)
    print(f"{info['name']}  {im.shape[1]}x{im.shape[0]}")

    mask = road_mask(im)
    dist = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    skel = skeletonize(mask > 0)
    # The pit road is one lane wide (~25 px here) and the track three (~73);
    # cut between them, low enough to keep the track itself in one piece.
    keep = skel & (dist * 2 > 35)
    lab = cv2.connectedComponents(keep.astype(np.uint8), 8)[1]
    sizes = np.bincount(lab[keep])
    pts = np.argwhere(lab == int(np.argmax(sizes[1:])) + 1)

    bridges = bridge_ends(pts)
    print("bridged %d gap(s) in the road" % len(bridges))
    loop = find_cycle(pts, extra=bridges)
    line, length = resample(loop, 3.0)
    widths = np.array([dist[int(round(y)), int(round(x))] * 2 for x, y in line])
    line = smooth_closed(line, 9)
    widths = smooth_closed(widths, 15)
    step = length / len(line)
    print("centreline: %d points, %.0f px round" % (len(line), length))
    print("road width: median %.1f  p10 %.1f  p90 %.1f"
          % (np.median(widths), np.percentile(widths, 10), np.percentile(widths, 90)))

    lanes = LANES
    norm = normals(line)
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY).astype(np.float32)
    div, score = divisions(gray, line, norm, widths, lanes, step)
    gaps = np.diff(np.r_[div, div[0] + len(line)]) * step
    print("divisions: %d, spacing median %.1f  p10 %.1f  p90 %.1f"
          % (len(div), np.median(gaps), np.percentile(gaps, 10), np.percentile(gaps, 90)))

    div, added = fill_divisions(div, len(line))
    print("filled in %d skipped division(s) -> %d cells" % (added, len(div)))

    spaces = build_spaces(line, norm, widths, div, lanes, reverse)
    track_path = ROOT / "tracks" / f"{map_id}.json"
    write_track(info, im, spaces, lanes, track_path, reverse)
    print("%d spaces -> %s" % (len(spaces), track_path.relative_to(ROOT)))

    OUT.mkdir(parents=True, exist_ok=True)
    np.savez(OUT / f"{map_id}_line.npz", line=line, widths=widths, mask=mask,
             divisions=div, score=score, step=step)
    vis = im.copy()
    for x, y in line.astype(int):
        cv2.circle(vis, (x, y), 1, (0, 0, 255), -1)
    for i in div.astype(int):
        p, nn, w = line[i], norm[i], widths[i] * 0.5
        cv2.line(vis, tuple((p - nn * w).astype(int)), tuple((p + nn * w).astype(int)), (255, 0, 0), 1)
    lane_colour = [(0, 220, 255), (0, 255, 120), (255, 120, 0)]
    for sp in spaces:
        x, y = int(sp["pos"][0]), int(sp["pos"][1])
        cv2.circle(vis, (x, y), 4, lane_colour[(sp["lane"] - 1) % 3], -1)
        if sp["lane"] == 1:
            a = math.radians(sp["rot"])
            cv2.arrowedLine(vis, (x, y),
                            (int(x + 26 * math.cos(a)), int(y + 26 * math.sin(a))),
                            (255, 255, 255), 2, tipLength=0.4)
    cv2.imwrite(str(OUT / f"{map_id}_spaces.png"), vis)
    print(f"  -> {(OUT / (map_id + '_spaces.png')).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
