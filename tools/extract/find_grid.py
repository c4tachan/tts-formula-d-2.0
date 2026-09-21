"""Find the printed space grid on a track board, step by step.

Each step writes an image to tools/extract/out/ so it can be checked by eye,
numbered so they sort in order:

  <id>_1_track_only.png      the road, everything else white
  <id>_2_no_arrows.png       the direction arrows painted out
  <id>_3_grey_corners.png    the red corner lines redrawn as thin grey lines
  <id>_4_junctions.png       every T (and cross) where grid lines meet
  <id>_5_pairs.png           T's paired across a lane: the cell divisions
  <id>_6_spaces.png          the printed cells: one space each, by lane

and finally writes the spaces to tracks/<id>.json -- unless that file has been
edited by hand in TTS, in which case it is left alone.

Close-up crops of the tricky corners go to out/_work/.

A cell division runs square across a lane and leaves a T at each end, so
junctions come in pairs. A T also carries the local direction of travel -- its
two straight-through branches run with the track -- which is steadier than a
traced racing line through tight corners.

Run:  python tools/extract/find_grid.py FDMonaco
"""
import sys
from collections import deque

import cv2
import numpy as np
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize

from detect_track import (OUT, LANES, board_image, corner_lines, inner_side, keep_long,
                          normals, racing_line, surface_mask)

WORK = OUT / "_work"

RING8 = [(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)]


# 1. The road ------------------------------------------------------------------

def track_only(im):
    """Asphalt and what is painted on it; kerbs, verges and scenery removed."""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    S, V = hsv[..., 1], hsv[..., 2]
    kerbs = cv2.dilate(keep_long((S < 60) & (V >= 205), 60), np.ones((3, 3), np.uint8))
    m = surface_mask(im) | corner_lines(im)
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    m[kerbs > 0] = 0
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
    m = (lab == 1 + int(np.argmax(st[1:, 4]))).astype(np.uint8)
    # Fill what is enclosed and small: arrows, grid boxes, the start band.
    n, lab, st, _ = cv2.connectedComponentsWithStats((1 - m).astype(np.uint8), 4)
    for i in range(1, n):
        if st[i, 4] < 3000:
            m[lab == i] = 1
    return np.where(m[..., None] > 0, im, 255).astype(np.uint8), m


# 2. Arrows ----------------------------------------------------------------------

def paint_out_arrows(track, road):
    """Arrows are dark for where they are, and bold; grid lines are a pixel or
    two wide. Judging darkness against the local asphalt keeps the lines in
    the darker tunnel stretch, which a fixed cut-off takes for arrows."""
    gray = cv2.cvtColor(track, cv2.COLOR_BGR2GRAY)
    bg = cv2.medianBlur(gray, 21).astype(np.float32)
    dark = bg - gray.astype(np.float32)
    ink = ((dark > 5) & (road > 0)).astype(np.uint8)
    rel = gray.astype(np.float32) / np.maximum(bg, 1)
    thick = cv2.distanceTransform(ink, cv2.DIST_L2, 3)
    core = ((rel < 0.55) & (ink > 0)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(core, 8)
    keep = [i for i in range(1, n) if st[i, 4] >= 25 and thick[lab == i].max() >= 2.0]
    arrows = np.isin(lab, keep).astype(np.uint8)
    halo = cv2.dilate(arrows, np.ones((5, 5), np.uint8))
    halo &= ((dark > 3) | (arrows > 0)).astype(np.uint8)
    halo = cv2.dilate(halo, np.ones((3, 3), np.uint8)) & road
    return cv2.inpaint(track, halo, 5, cv2.INPAINT_TELEA), len(keep)


def track_proper(road, line, width):
    """The road near the racing line: leaves out the pit road and scraps of
    pavement that came along with the road."""
    rail = np.zeros(road.shape, np.uint8)
    cv2.polylines(rail, [line.astype(np.int32).reshape(-1, 1, 2)], True, 255, 1)
    return ((cv2.distanceTransform(255 - rail, cv2.DIST_L2, 5) <= 0.62 * width) & (road > 0)).astype(np.uint8)


# 3. Corner lines ----------------------------------------------------------------

def divider_colour(img, road):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    S = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)[..., 1].astype(int)
    dark = cv2.medianBlur(gray, 15).astype(np.float32) - gray.astype(np.float32)
    return np.median(img[(dark > 12) & (road > 0) & (S < 40) & (gray > 60)], axis=0).astype(np.uint8)


def grey_corners(img, road, main):
    """Redraw the red corner lines as thin divider-grey lines.

    They mark cell boundaries, but painted twice as thick as the grid and in
    red. Only red on the track proper is touched -- the pit garages are red
    too. Each line keeps just its solid core, the part a couple of pixels in
    from its soft edge: a one-pixel skeleton of such a lumpy shape comes out
    broken and spiky, while the core is a smooth line about grid-line wide.
    """
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV).astype(int)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    red = ((H <= 12) | (H >= 165)) & (S > 60) & (V > 60)
    fringe = (cv2.dilate(red.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
    fringe &= ((H <= 15) | (H >= 160)) & (S > 25)
    paint = ((red | fringe) & (main > 0)).astype(np.uint8)
    colour = divider_colour(img, road)
    solid = cv2.morphologyEx(paint, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    core = cv2.distanceTransform(solid, cv2.DIST_L2, 3) >= 1.5
    out = cv2.inpaint(img, cv2.dilate(paint, np.ones((3, 3), np.uint8)), 3, cv2.INPAINT_TELEA)
    out[core] = colour
    return out, int(paint.sum())


# 4. Junctions -------------------------------------------------------------------

def grid_skeleton(img, road):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    dark = cv2.medianBlur(gray, 15).astype(np.float32) - gray.astype(np.float32)
    ink = ((dark > 5) & (road > 0)).astype(np.uint8)
    ink = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(ink, 8)
    ink = np.isin(lab, [i for i in range(1, n) if st[i, 4] >= 20]).astype(np.uint8)
    return skeletonize(ink > 0).astype(np.uint8), ink


def branch_points(skel, merge=6):
    """Where three or more thinned lines meet, one point per meeting."""
    H, W = skel.shape
    pad = np.pad(skel, 1)
    nb = np.stack([pad[1 + a:1 + a + H, 1 + b:1 + b + W] for a, b in RING8])
    crossings = ((nb == 0) & (np.roll(nb, -1, axis=0) == 1)).sum(axis=0)
    jy, jx = np.nonzero((skel == 1) & (crossings >= 3))
    jp = np.c_[jx, jy].astype(float)
    marks, used = [], np.zeros(len(jp), bool)
    tree = cKDTree(jp)
    for k in range(len(jp)):
        if used[k]:
            continue
        grp = tree.query_ball_point(jp[k], merge)
        used[grp] = True
        marks.append(jp[grp].mean(0))
    return np.array(marks)


def branches(skel, p, inner=4, reach=14):
    """Follow each line leaving p along the skeleton; direction and length.

    Following the thinned line rather than a straight ray lets a curved
    division count at its full length.
    """
    H, W = skel.shape
    cx, cy = p
    seeds = set()
    for y in range(int(max(0, cy - inner - 2)), int(min(H, cy + inner + 3))):
        for x in range(int(max(0, cx - inner - 2)), int(min(W, cx + inner + 3))):
            if skel[y, x] and inner <= np.hypot(x - cx, y - cy) < inner + 1.5:
                seeds.add((y, x))
    groups, seen = [], set()
    for s in seeds:
        if s in seen:
            continue
        g, q = [], [s]
        seen.add(s)
        while q:
            a = q.pop()
            g.append(a)
            for dy, dx in RING8:
                b = (a[0] + dy, a[1] + dx)
                if b in seeds and b not in seen:
                    seen.add(b)
                    q.append(b)
        groups.append(g)
    out = []
    for g in groups:
        far, far_pt = 0.0, g[0]
        q = deque((a, 0) for a in g)
        seen2 = set(g)
        while q:
            (y, x), steps = q.popleft()
            r = np.hypot(x - cx, y - cy)
            if r > far:
                far, far_pt = r, (y, x)
            if steps >= reach * 2 or r >= reach:
                continue
            for dy, dx in RING8:
                b = (y + dy, x + dx)
                if 0 <= b[0] < H and 0 <= b[1] < W and skel[b] and b not in seen2 \
                        and np.hypot(b[1] - cx, b[0] - cy) >= inner:
                    seen2.add(b)
                    q.append((b, steps + 1))
        out.append((np.arctan2(far_pt[0] - cy, far_pt[1] - cx), far))
    return out


def classify(br, flow_hint, tol=30, min_len=9):
    """A T: two branches straight through (the boundary, running with the
    track) and a stem square to them (the division). A cross: four at right
    angles. Returns (kind, flow direction, stem directions)."""
    br = [b for b in br if b[1] >= min_len]
    ang = np.sort(np.mod([b[0] for b in br], 2 * np.pi))
    if len(ang) not in (3, 4):
        return None
    gaps = np.degrees(np.diff(np.r_[ang, ang[0] + 2 * np.pi]))
    unit = lambda a: np.array([np.cos(a), np.sin(a)])
    if len(ang) == 3:
        order = np.argsort(gaps)
        g = gaps[order]
        if not (abs(g[0] - 90) <= tol and abs(g[1] - 90) <= tol and abs(g[2] - 180) <= tol):
            return None
        # The wide gap lies between the two straight-through branches; the stem
        # is the branch opposite it.
        wide = order[2]
        stem = ang[(wide + 2) % 3]
        through = unit(ang[wide])
        flow = through if through @ flow_hint >= 0 else -through
        return "T", flow, [unit(stem)]
    if all(abs(gaps - 90) <= tol):
        dirs = [unit(a) for a in ang]
        flow = max(dirs, key=lambda d: abs(d @ flow_hint))
        flow = flow if flow @ flow_hint >= 0 else -flow
        stems = [d for d in dirs if abs(d @ flow) < 0.5]
        return "+", flow, stems
    return None


# 5. Pairs -----------------------------------------------------------------------

def pair_across(points, flows, stems, outward, ink, lane_w):
    """Join each junction to the one at the other end of its division.

    Look along the stem, a lane's width across, square to the local flow,
    with the printed line solid in between.
    """
    def inked(a, b, frac=0.8):
        n = max(2, int(np.hypot(*(b - a))))
        ts = np.linspace(0.15, 0.85, n)
        q = (a[None] + (b - a)[None] * ts[:, None]).round().astype(int)
        return ink[q[:, 1], q[:, 0]].mean() >= frac

    tree = cKDTree(points)
    cands = []
    for j in range(len(points)):
        for k in tree.query_ball_point(points[j], 1.6 * lane_w):
            if k == j:
                continue
            d = points[k] - points[j]
            across = abs(d @ np.array([-flows[j][1], flows[j][0]]))
            along = abs(d @ flows[j])
            if not (0.55 * lane_w <= across <= 1.5 * lane_w) or along > 0.36 * across + 2:
                continue
            u = d / np.hypot(*d)
            if max(abs(u @ s) for s in stems[j]) < 0.85:     # not along a stem of j
                continue
            if not inked(points[j], points[k]):
                continue
            cands.append((along + abs(across - lane_w), j, k))
    # Orient every pair inner -> outer, and use each end once per side.
    cands.sort()
    as_inner, as_outer, pairs = set(), set(), []
    for _, j, k in cands:
        if (points[k] - points[j]) @ outward[j] < 0:
            j, k = k, j
        if j in as_inner or k in as_outer or (j, k) in pairs:
            continue
        as_inner.add(j)
        as_outer.add(k)
        pairs.append((j, k))
    return pairs


def complete(points, stems, pairs, ink, skel, lane_w):
    """Add the missing far end of a division that runs off a lone junction.

    Follow the stem across the lane until it meets a line running the other
    way: that meeting is the partner that went undetected.
    """
    paired = {i for pr in pairs for i in pr}
    H, W = ink.shape
    added, links = [], []
    for i in range(len(points)):
        if i in paired:
            continue
        for s in stems[i]:
            side = np.array([-s[1], s[0]])
            end = None
            for t in np.arange(0.55 * lane_w, 1.5 * lane_w, 1.0):
                q = points[i] + s * t
                x, y = int(round(q[0])), int(round(q[1]))
                if not (0 <= x < W and 0 <= y < H) or not ink[y, x]:
                    break
                # A line crossing here: ink either side, square to the stem.
                l = q + side * 5
                r = q - side * 5
                if all(0 <= int(round(v[0])) < W and 0 <= int(round(v[1])) < H and
                       ink[int(round(v[1])), int(round(v[0]))] for v in (l, r)):
                    end = q
                    break
            if end is not None:
                # Solid line from the junction to the end?
                n = int(np.hypot(*(end - points[i])))
                ts = np.linspace(0.15, 0.85, max(2, n))
                pts = (points[i][None] + (end - points[i])[None] * ts[:, None]).round().astype(int)
                if ink[pts[:, 1], pts[:, 0]].mean() >= 0.8:
                    added.append(end)
                    links.append((i, len(points) + len(added) - 1))
                    break
    return np.array(added).reshape(-1, 2), links


# 6. Spaces ------------------------------------------------------------------------

def segment_cells(main, skel, min_frac=0.35):
    """The road cut up along its printed lines: one blob per cell.

    Where a line has a small break, two cells run together through a narrow
    waist; a watershed on the distance to the lines cuts them apart there.
    """
    lines = cv2.dilate(skel, np.ones((2, 2), np.uint8))
    cells = (main & (lines == 0)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(cells, 4)
    areas = st[1:, 4]
    typical = float(np.median(areas[areas > 200]))
    dist = cv2.distanceTransform(cells, cv2.DIST_L2, 5)
    out = np.zeros(lab.shape, np.int32)
    nxt = 1
    for i in range(1, n):
        a = st[i, 4]
        if a < min_frac * typical:
            continue
        x, y, w, h, _ = st[i]
        sub = lab[y:y + h, x:x + w] == i
        k = int(round(a / typical))
        if k <= 1:
            out[y:y + h, x:x + w][sub] = nxt
            nxt += 1
            continue
        # Seeds: the k strongest peaks of the distance map, well apart.
        d = dist[y:y + h, x:x + w] * sub
        peaks = []
        order = np.dstack(np.unravel_index(np.argsort(-d.ravel()), d.shape))[0]
        for py, px in order:
            if d[py, px] <= 0 or len(peaks) >= k:
                break
            if all(np.hypot(py - qy, px - qx) > 14 for qy, qx in peaks):
                peaks.append((py, px))
        markers = np.zeros(sub.shape, np.int32)
        for m, (py, px) in enumerate(peaks, 1):
            markers[py, px] = m
        markers[~sub] = len(peaks) + 1                         # background
        ws = cv2.watershed(cv2.merge([(d * 10).clip(0, 255).astype(np.uint8)] * 3), markers)
        for m in range(1, len(peaks) + 1):
            part = (ws == m) & sub
            if part.sum() >= min_frac * typical:
                out[y:y + h, x:x + w][part] = nxt
                nxt += 1
    return out, typical


def cell_lane(main, centre, across, reach=120, gap=4):
    """Lane from where the cell sits on its own chord across the road."""
    H, W = main.shape
    ends = []
    for sgn in (-1, 1):
        last, off = 0.0, 0
        for t in np.arange(1.0, reach, 1.0):
            q = centre + sgn * across * t
            x, y = int(round(q[0])), int(round(q[1]))
            if not (0 <= x < W and 0 <= y < H):
                break
            if main[y, x]:
                last, off = t, 0
            else:
                off += 1
                if off > gap:
                    break
        ends.append(last)
    frac = ends[0] / max(sum(ends), 1e-6)
    return int(np.clip(np.floor(frac * LANES) + 1, 1, LANES))


def cells_to_spaces(labels, main, line, tangent, outward, reverse):
    """A space per cell: its centre, lane, facing, and the cells ahead of it."""
    tree = cKDTree(line)
    spaces = {}
    for i in range(1, labels.max() + 1):
        ys, xs = np.nonzero(labels == i)
        if not len(xs):
            continue
        c = np.array([xs.mean(), ys.mean()])
        _, at = tree.query(c)
        flow = tangent[at] * (-1 if reverse else 1)
        # The cell's own long axis gives the local flow better than the line.
        pts = np.c_[xs, ys] - c
        w, v = np.linalg.eigh(pts.T @ pts)
        axis = v[:, 1]
        if w[1] > 1.3 * w[0]:
            flow = axis if axis @ flow >= 0 else -axis
        # Chords are measured from the inside out.
        across = outward[at] - (outward[at] @ flow) * flow
        across = across / (np.linalg.norm(across) + 1e-9)   # outward; the walk back along it finds the inside edge
        spaces[i] = {"pos": c, "flow": flow, "lane": cell_lane(main, c, across),
                     "rot": float(np.degrees(np.arctan2(flow[1], flow[0])))}
    # Which cells touch, across the line drawn between them.
    touch = {}
    lab = labels
    for dy, dx in ((0, 3), (3, 0), (2, 2), (2, -2)):
        a = lab[3:-3, 3:-3]
        b = lab[3 + dy:lab.shape[0] - 3 + dy, 3 + dx:lab.shape[1] - 3 + dx]
        m = (a > 0) & (b > 0) & (a != b)
        for u, v in set(zip(a[m].tolist(), b[m].tolist())):
            touch.setdefault(u, set()).add(v)
            touch.setdefault(v, set()).add(u)
    for i, s in spaces.items():
        ahead = []
        for j in touch.get(i, ()):
            if j not in spaces:
                continue
            d = spaces[j]["pos"] - s["pos"]
            if d @ s["flow"] > 0.35 * np.hypot(*d) and abs(spaces[j]["lane"] - s["lane"]) <= 1:
                ahead.append(j)
        s["next"] = ahead
    return spaces



# 7. The track file ------------------------------------------------------------------

def write_track(info, im, spaces, line, reverse, path):
    """Spaces lane by lane, each lane in running order, with its links ahead.

    A track file that has been edited by hand is never overwritten: the
    detector's guess is only ever a starting point.
    """
    import json
    if path.exists() and json.loads(path.read_text(encoding="utf-8")).get("edited"):
        return False
    _, at = cKDTree(line).query(np.array([s["pos"] for s in spaces.values()]))
    along = dict(zip(spaces, at))
    ids = {}
    for l in range(1, LANES + 1):
        lane_cells = sorted((i for i, s in spaces.items() if s["lane"] == l),
                            key=lambda i: along[i], reverse=reverse)
        for i in lane_cells:
            ids[i] = len(ids) + 1
    out = []
    for i, s in spaces.items():
        out.append({
            "id": ids[i],
            "pos": [round(float(s["pos"][0]), 1), round(float(s["pos"][1]), 1)],
            "rot": round(s["rot"], 1),
            "lane": s["lane"],
            "next": sorted(ids[j] for j in s["next"] if j in ids),
            "corner": None,
            "sector": 0,
        })
    out.sort(key=lambda s: s["id"])
    sector = {}
    for s in out:
        sector[s["lane"]] = sector.get(s["lane"], 0) + 1
        s["sector"] = sector[s["lane"]]
    track = {
        "id": info["id"],
        "name": info["name"],
        "ruleset": "formula_d" if info["category"] == "formula_d" else "formula_de",
        "image": {"width": im.shape[1], "height": im.shape[0]},
        "lanes": LANES,
        "laps": 2,
        "detect": {"reverse": bool(reverse), "tool": "find_grid.py"},
        "edited": False,
        "spaces": out,
        "corners": [],
        "start": [],
        "finish": {"line": []},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(track, indent=1), encoding="utf-8")
    return True


# ------------------------------------------------------------------------------------

def crop(vis, box, scale=1.8):
    x0, y0, x1, y1 = box
    c = vis[y0:y1, x0:x1]
    return cv2.resize(c, (int(c.shape[1] * scale), int(c.shape[0] * scale)), interpolation=cv2.INTER_NEAREST)


def main():
    map_id = sys.argv[1] if len(sys.argv) > 1 else "FDMonaco"
    info, im = board_image(map_id)
    WORK.mkdir(parents=True, exist_ok=True)
    name = lambda s: OUT / f"{map_id}_{s}.png"

    track, road = track_only(im)
    cv2.imwrite(str(name("1_track_only")), track)

    clean, n_arrows = paint_out_arrows(track, road)
    cv2.imwrite(str(name("2_no_arrows")), clean)
    print("1-2. road %.1f%% of the board; %d arrows painted out" % (100 * road.mean(), n_arrows))

    # The track proper: near the racing line. Leaves out the pit road and
    # scraps of pavement that came along with the road.
    line, length, width = racing_line(im)
    norm = normals(line)
    side = inner_side(line, norm)
    tangent = np.c_[norm[:, 1], -norm[:, 0]]
    outward_line = -norm * side
    lane_w = width / LANES
    main = track_proper(road, line, width)

    grey, n_red = grey_corners(clean, road, main)
    cv2.imwrite(str(name("3_grey_corners")), grey)
    print("3. %d red corner-line pixels redrawn as thin grey lines" % n_red)

    skel, ink = grid_skeleton(grey, main)
    marks = branch_points(skel)
    _, at = cKDTree(line).query(marks)
    points, kinds, flows, stems = [], [], [], []
    for p, a in zip(marks, at):
        c = classify(branches(skel, p), tangent[a])
        if c:
            points.append(p)
            kinds.append(c[0])
            flows.append(c[1])
            stems.append(c[2])
    points = np.array(points)
    print("4. branch points %d; T's %d; crosses %d"
          % (len(marks), kinds.count("T"), kinds.count("+")))

    vis = grey.copy()
    for p in points:
        c = tuple(p.round().astype(int))
        cv2.circle(vis, c, 4, (0, 255, 255), -1)
        cv2.circle(vis, c, 4, (0, 0, 0), 1)
    cv2.imwrite(str(name("4_junctions")), vis)

    _, at = cKDTree(line).query(points)
    outward = outward_line[at]
    inkd = cv2.dilate(ink, np.ones((3, 3), np.uint8))
    pairs = pair_across(points, flows, stems, outward, inkd, lane_w)
    extra, links = complete(points, stems, pairs, inkd, skel, lane_w)
    paired = {i for pr in pairs for i in pr} | {a for a, _ in links}
    lone = [i for i in range(len(points)) if i not in paired]
    lengths = [np.hypot(*(points[k] - points[j])) for j, k in pairs]
    print("5. pairs %d (median %.1f px; lane %.1f); completed by following the line %d; still alone %d"
          % (len(pairs), np.median(lengths), lane_w, len(links), len(lone)))

    allp = np.r_[points, extra] if len(extra) else points
    np.savez(OUT / f"{map_id}_grid.npz", points=points, kinds=np.array(kinds),
             flows=np.array(flows), pairs=np.array(pairs), extra=extra, links=np.array(links))

    vis = grey.copy()
    for j, k in pairs + links:
        cv2.line(vis, tuple(allp[j].round().astype(int)), tuple(allp[k].round().astype(int)), (0, 190, 0), 2)
    for i, p in enumerate(points):
        c = tuple(p.round().astype(int))
        cv2.circle(vis, c, 4, (0, 255, 255) if i in paired else (0, 0, 255), -1)
        cv2.circle(vis, c, 4, (0, 0, 0), 1)
    for p in extra:
        c = tuple(p.round().astype(int))
        cv2.circle(vis, c, 4, (0, 150, 255), -1)
        cv2.circle(vis, c, 4, (0, 0, 0), 1)
    cv2.imwrite(str(name("5_pairs")), vis)
    for label, box in {"loews": (1850, 80, 2330, 520), "grid": (100, 480, 420, 1020),
                       "chicane": (780, 480, 1250, 800), "rascasse": (250, 950, 650, 1350)}.items():
        cv2.imwrite(str(WORK / f"{map_id}_5_pairs_{label}.png"), crop(vis, box))

    # 6. Spaces
    from detect_track import ROOT
    import json
    existing = ROOT / "tracks" / f"{map_id}.json"
    reverse = False
    if existing.exists():
        reverse = json.loads(existing.read_text(encoding="utf-8")).get("detect", {}).get("reverse", False)
    labels, typical = segment_cells(main, skel)
    spaces = cells_to_spaces(labels, main, line, tangent, outward_line, reverse)
    per = [sum(1 for s in spaces.values() if s["lane"] == l) for l in range(1, LANES + 1)]
    straight = sum(1 for s in spaces.values()
                   if any(spaces[j]["lane"] == s["lane"] for j in s["next"]))
    print("6. cells %d (typical %.0f px) -- per lane %s; %d have a cell straight ahead in their lane"
          % (len(spaces), typical, per, straight))
    np.savez(OUT / f"{map_id}_spaces.npz",
             ids=np.array(list(spaces)), pos=np.array([s["pos"] for s in spaces.values()]),
             rot=np.array([s["rot"] for s in spaces.values()]),
             lane=np.array([s["lane"] for s in spaces.values()]))

    colours = [(0, 200, 255), (0, 220, 90), (255, 140, 0)]
    overlay = np.zeros_like(grey)
    for i, s in spaces.items():
        overlay[labels == i] = colours[(s["lane"] - 1) % 3]
    vis = cv2.addWeighted(grey, 0.5, overlay, 0.5, 0)
    for i, s in spaces.items():
        c = tuple(s["pos"].round().astype(int))
        for j in s["next"]:
            cv2.line(vis, c, tuple(spaces[j]["pos"].round().astype(int)), (60, 60, 60), 1)
    for i, s in spaces.items():
        c = tuple(s["pos"].round().astype(int))
        cv2.circle(vis, c, 3, (255, 255, 255), -1)
        a = np.radians(s["rot"])
        cv2.line(vis, c, (int(c[0] + 10 * np.cos(a)), int(c[1] + 10 * np.sin(a))), (255, 255, 255), 1)
    cv2.imwrite(str(name("6_spaces")), vis)

    # 7. The track file
    track_path = ROOT / "tracks" / f"{map_id}.json"
    if write_track(info, im, spaces, line, reverse, track_path):
        print("7. %d spaces -> %s" % (len(spaces), track_path.relative_to(ROOT)))
    else:
        print("7. %s has been edited by hand; left as it is" % track_path.relative_to(ROOT))
    for label, box in {"loews": (1850, 80, 2330, 520), "grid": (100, 480, 420, 1020),
                       "chicane": (780, 480, 1250, 800), "rascasse": (250, 950, 650, 1350)}.items():
        cv2.imwrite(str(WORK / f"{map_id}_6_spaces_{label}.png"), crop(vis, box))
    return 0


if __name__ == "__main__":
    sys.exit(main())
