"""Find the printed space grid on a track board, step by step.

Each step writes an image to tools/extract/out/ so it can be checked by eye,
numbered so they sort in order:

  <id>_1_track_only.png      the road, everything else white
  <id>_2_no_arrows.png       the direction arrows painted out
  <id>_3_grey_corners.png    the red corner lines redrawn as thin grey lines
  <id>_4_lines.png           the grid lines sorted: along the road or across it
  <id>_5_rungs.png           the divisions, one per lane; guessed ones magenta
  <id>_6_spaces.png          the printed cells: one space each, by lane

and finally writes the spaces to tracks/<id>.json -- unless that file has been
edited by hand in TTS, in which case it is left alone.

Close-up crops of Monaco's tricky corners go to out/_work/.

Which way is across the road is taken from the road's own edges, and each
rung's place in the running order from where it sits along its edge, so the
hairpins -- where the racing line's nearest point is as likely to be on the
other leg -- come out as cleanly as the straights. A rung whose spacing is
well off its neighbours' is treated as a missed or stray division and marked
in the step images: what the detector guessed is always visible.

A board whose grid is printed dark and crisp, as Austin's is, reads better as
cells: the patches of asphalt the lines enclose, one per space. --cells does
that in place of steps 4-5, writing <id>_5_cells.png (each patch tinted, the
scraps left out in red). --reverse says the lap runs the other way round.
Both are kept in the track file's `detect`, so later runs read it the same way.

Run:  python tools/extract/find_grid.py FDMonaco
      python tools/extract/find_grid.py FDAustin --cells
"""
import sys

import cv2
import numpy as np
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize

from detect_track import (OUT, LANES, board_image, inner_side, normals, racing_line, road_surface,
                          smooth_closed)

WORK = OUT / "_work"

RING8 = [(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)]


# 1. The road ------------------------------------------------------------------

def track_only(im):
    """Asphalt and what is painted on it; kerbs, verges and scenery removed."""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    S, V = hsv[..., 1], hsv[..., 2]
    m = road_surface(im)
    # The road's own edge line is black, so the asphalt mask stops a few
    # pixels short of the printed limit, and with it every division that
    # reaches the limit. The mask itself is left alone -- grown, it closes
    # the gap between the legs of a hairpin -- but the image keeps a few
    # pixels of dark ink beyond it, so the divisions reach the limit.
    keep = cv2.dilate(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) & (S < 60) & (V < 205)
    return np.where((m | keep)[..., None] > 0, im, 255).astype(np.uint8), m


# 2. Arrows ----------------------------------------------------------------------

# An arrow lies within its cell: the longest, curving round a hairpin, run to
# about 50 px. Ink that runs further is grid -- on a board whose lines are
# printed as dark as its arrows (Austin's), the lane lines and divisions join
# up into one long net.
ARROW_EXTENT = 60


def paint_out_arrows(track, road):
    """Arrows are dark for where they are, and bold; grid lines are a pixel or
    two wide. Judging darkness against the local asphalt keeps the lines in
    the darker tunnel stretch, which a fixed cut-off takes for arrows. Where
    the lines are as dark and bold as the arrows, the arrows are the marks
    that stay inside a cell (ARROW_EXTENT)."""
    gray = cv2.cvtColor(track, cv2.COLOR_BGR2GRAY)
    bg = cv2.medianBlur(gray, 21).astype(np.float32)
    dark = bg - gray.astype(np.float32)
    ink = ((dark > 5) & (road > 0)).astype(np.uint8)
    rel = gray.astype(np.float32) / np.maximum(bg, 1)
    thick = cv2.distanceTransform(ink, cv2.DIST_L2, 3)
    core = ((rel < 0.55) & (ink > 0)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(core, 8)
    keep = [i for i in range(1, n) if st[i, 4] >= 25 and thick[lab == i].max() >= 2.0
            and max(st[i, 2], st[i, 3]) <= ARROW_EXTENT]
    arrows = np.isin(lab, keep).astype(np.uint8)
    halo = cv2.dilate(arrows, np.ones((5, 5), np.uint8))
    halo &= ((dark > 3) | (arrows > 0)).astype(np.uint8)
    halo = cv2.dilate(halo, np.ones((3, 3), np.uint8)) & road
    return cv2.inpaint(track, halo, 5, cv2.INPAINT_TELEA), len(keep)


def paint_out_flag(track, road):
    """The start/finish flag: a band of white squares on the asphalt (nothing
    else painted on the road is that bright) with black ones between them.
    Its edges would otherwise pass for divisions. Where a striped kerb is
    taken for road, as on Austin, its white blocks pass for squares too, but
    they alternate with red, and the flag has none."""
    gray = cv2.cvtColor(track, cv2.COLOR_BGR2GRAY)
    bg = cv2.medianBlur(gray, 21).astype(np.float32)
    bright = ((gray.astype(np.float32) - bg > 35) & (road > 0)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(bright, 8)
    squares = np.isin(lab, [i for i in range(1, n) if 12 <= st[i, 4] <= 400]).astype(np.uint8)
    band = cv2.morphologyEx(squares, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    hsv = cv2.cvtColor(track, cv2.COLOR_BGR2HSV).astype(int)
    red = (((hsv[..., 0] <= 10) | (hsv[..., 0] >= 170)) & (hsv[..., 1] > 90) & (hsv[..., 2] > 80))
    n, lab, st, _ = cv2.connectedComponentsWithStats(band, 8)
    band = np.isin(lab, [i for i in range(1, n) if st[i, 4] >= 600
                         and red[lab == i].mean() < 0.05]).astype(np.uint8)
    band = cv2.dilate(band, np.ones((7, 7), np.uint8)) & road
    return cv2.inpaint(track, band, 5, cv2.INPAINT_TELEA), band


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


def grey_corners(img, road, main, across_dir):
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
    # The red blocks of a kerb poke into the road mask too: only red well
    # inside a smoothed road edge is a corner line.
    disc = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (37, 37))
    smooth = cv2.morphologyEx(cv2.morphologyEx(main, cv2.MORPH_OPEN, disc), cv2.MORPH_CLOSE, disc)
    inside = cv2.distanceTransform(smooth, cv2.DIST_L2, 5) >= 5
    paint = ((red | fringe) & (main > 0) & inside).astype(np.uint8)
    colour = divider_colour(img, road)
    solid = cv2.morphologyEx(paint, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    core = cv2.distanceTransform(solid, cv2.DIST_L2, 3) >= 1.5
    # The line for one lane is joined to the next lane's by a piece running
    # along the lane line: that is no division, so only what runs across
    # the road is redrawn.
    cx, cy = line_orientation(core.astype(np.uint8), r=4)
    core &= np.abs(cx * across_dir[..., 0] + cy * across_dir[..., 1]) > 0.6
    out = cv2.inpaint(img, cv2.dilate(paint, np.ones((3, 3), np.uint8)), 3, cv2.INPAINT_TELEA)
    out[core] = colour
    return out, int(paint.sum())


# 4. Lines -----------------------------------------------------------------------

def grid_skeleton(img, road, blank):
    """The grid lines thinned to a pixel. Nothing is read under `blank`
    (the painted-out flag): the divisions crossing it are left to be put
    in from their neighbours rather than read from what the painting left."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    dark = cv2.medianBlur(gray, 15).astype(np.float32) - gray.astype(np.float32)
    reach = cv2.dilate(road, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    ink = ((dark > 5) & (reach > 0) & (cv2.dilate(blank, np.ones((9, 9), np.uint8)) == 0)).astype(np.uint8)
    ink = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(ink, 8)
    ink = np.isin(lab, [i for i in range(1, n) if st[i, 4] >= 20]).astype(np.uint8)
    return skeletonize(ink > 0).astype(np.uint8), ink


def road_sides(main, line):
    """Distance from every road pixel to the inside edge of the loop and to the
    outside edge, plus the inside mask.

    The board minus the road falls into the outside, the hole the loop
    encloses, and pockets the road wraps right round (between the legs of a
    hairpin); a pocket counts as inside or outside by which side of the
    racing line it lies. The nearest edge pixel is always on the road's own
    leg, which is what makes this hold up in the hairpins where the racing
    line's nearest point does not.
    """
    n, lab, st, cen = cv2.connectedComponentsWithStats((main == 0).astype(np.uint8), 4)
    order = np.argsort(-st[1:, 4]) + 1
    inside = order[1]                     # order[0] is the outside
    if st[inside, 4] < 0.03 * main.size:
        print("   warning: the road does not close into a loop; lanes will be unreliable")
    poly = line.astype(np.float32)
    is_in = np.zeros(n, bool)
    is_in[inside] = True
    for i in order[2:]:
        is_in[i] = cv2.pointPolygonTest(poly, (float(cen[i][0]), float(cen[i][1])), False) > 0
    is_in[0] = False
    inside_mask = is_in[lab]
    d_in = cv2.distanceTransform((~inside_mask).astype(np.uint8), cv2.DIST_L2, 5)
    d_out = cv2.distanceTransform((inside_mask | (main > 0)).astype(np.uint8), cv2.DIST_L2, 5)
    return d_in, d_out, inside_mask.astype(np.uint8)


def road_frame(main, line, outward, slack=6.0, window=50):
    """For every road pixel: which way is across the road (a unit vector
    towards the outside), how far it lies from the inside edge, and how wide
    the road is there.

    All three come from the road's own edges, which is what holds up in the
    hairpins. The road's width drifts round the lap, so what counts as too
    wide is judged against a running median along the racing line; where
    the road is wider than that -- the pit exit's funnel hangs off the
    inside of the start straight -- an edge has moved, and the position is
    taken from the racing line instead, which runs down the middle of the
    road proper there. The line is consulted nowhere else.
    """
    d_in, d_out, inside = road_sides(main, line)
    gx = cv2.Sobel(d_in, cv2.CV_64F, 1, 0, ksize=5)
    gy = cv2.Sobel(d_in, cv2.CV_64F, 0, 1, ksize=5)
    g = np.hypot(gx, gy) + 1e-9
    across = np.dstack([gx / g, gy / g])
    pos = d_in.copy()
    local_w = d_in + d_out
    ys, xs = np.nonzero(main)
    _, at = cKDTree(line).query(np.c_[xs, ys])
    n = len(line)
    per = np.full(n, np.nan)
    order = np.argsort(at)
    bounds = np.searchsorted(at[order], np.arange(n + 1))
    w_here = local_w[ys, xs][order]
    for i in range(n):
        if bounds[i + 1] > bounds[i]:
            per[i] = np.median(w_here[bounds[i]:bounds[i + 1]])
    per = np.where(np.isnan(per), np.nanmedian(per), per)
    expected = np.array([np.median(np.roll(per, -i)[np.r_[np.arange(0, window + 1), np.arange(n - window, n)]])
                         for i in range(n)])
    widened = local_w[ys, xs] > expected[at] + slack
    # Only a sizeable stretch is a widening: a sharp apex measures a little
    # wide on the diagonal, and there the edges are still the better guide.
    wmask = np.zeros(main.shape, np.uint8)
    wmask[ys[widened], xs[widened]] = 1
    nc, lab, st, _ = cv2.connectedComponentsWithStats(wmask, 8)
    big = np.isin(lab, [i for i in range(1, nc) if st[i, 4] >= 2500])
    widened &= big[ys, xs]
    if widened.any():
        # Cut the widened stretch back to the road proper, a band the
        # expected width about the racing line, and measure the edges again.
        w = np.nonzero(widened)[0]
        off = ((np.c_[xs[w], ys[w]] - line[at[w]]) * outward[at[w]]).sum(1)
        beyond = np.abs(off) > expected[at[w]] / 2 + 4
        trim = main.copy()
        trim[ys[w][beyond], xs[w][beyond]] = 0
        d_in, d_out, inside = road_sides(trim, line)
        pos = d_in.copy()
        local_w = d_in + d_out
        gx = cv2.Sobel(d_in, cv2.CV_64F, 1, 0, ksize=5)
        gy = cv2.Sobel(d_in, cv2.CV_64F, 0, 1, ksize=5)
        g = np.hypot(gx, gy) + 1e-9
        across = np.dstack([gx / g, gy / g])
        # Which way is across along that stretch: square to the racing
        # line's direction taken over a good length, which a wiggle into
        # the funnel cannot turn. Applied to the whole stretch, a little
        # either side, since the edges there are unreliable to the mouth.
        tan = smooth_closed(np.gradient(line, axis=0), 2 * window + 1)
        tan /= np.linalg.norm(tan, axis=1, keepdims=True) + 1e-9
        nrm = np.c_[-tan[:, 1], tan[:, 0]]
        stretch = np.zeros(n, bool)
        stretch[at[w]] = True
        for k in range(1, 11):
            stretch |= np.roll(stretch, k) | np.roll(stretch, -k)
        z = np.nonzero(stretch[at])[0]
        sign = np.sign((nrm[at[z]] * outward[at[z]]).sum(1))[:, None]
        across[ys[z], xs[z]] = nrm[at[z]] * sign
    return across, pos, np.maximum(local_w, 1e-6), inside, int(widened.sum())


def line_orientation(skel, r=4):
    """The direction each thinned line runs in, from the spread of the
    skeleton pixels around each one (a structure tensor)."""
    S = skel.astype(np.float64)
    H, W = S.shape
    X, Y = np.meshgrid(np.arange(W, dtype=np.float64), np.arange(H, dtype=np.float64))
    box = lambda a: cv2.boxFilter(a, -1, (2 * r + 1, 2 * r + 1), normalize=False)
    w = box(S) + 1e-9
    mx, my = box(S * X) / w, box(S * Y) / w
    sxx = box(S * X * X) / w - mx * mx
    syy = box(S * Y * Y) / w - my * my
    sxy = box(S * X * Y) / w - mx * my
    ang = 0.5 * np.arctan2(2 * sxy, sxx - syy)
    return np.cos(ang), np.sin(ang)


def split_lines(skel, across_dir):
    """Skeleton pixels running across the road (the cell divisions) and those
    running along it (the lane lines)."""
    cx, cy = line_orientation(skel)
    align = np.abs(cx * across_dir[..., 0] + cy * across_dir[..., 1])
    across = (skel > 0) & (align > 0.6)
    along = (skel > 0) & ~across
    return across.astype(np.uint8), along.astype(np.uint8)


# 5. Rungs -----------------------------------------------------------------------

def find_rungs(across, pos, local_w, lane_w, blank):
    """Every division as one rung per lane: its two ends (inner, outer), lane
    and size. A line drawn across several lanes, as the radial ones in the
    corners are, is cut where it crosses from one lane to the next. Ink too
    short to reach across a lane (digits, scraps) is left out.

    Lane 1 is the innermost lane of the loop.
    """
    strip = np.floor(LANES * pos / local_w).astype(np.int32).clip(0, LANES - 1)
    n, lab, st, _ = cv2.connectedComponentsWithStats(across, connectivity=8)
    pieces = []
    for i in range(1, n):
        x, y, w, h, a = st[i]
        if a < 4:
            continue
        sub = lab[y:y + h, x:x + w] == i
        sst = strip[y:y + h, x:x + w]
        for s in np.unique(sst[sub]):
            m = sub & (sst == s)
            if m.sum() < 0.35 * lane_w:
                continue
            ys, xs = np.nonzero(m)
            pieces.append((int(s), np.c_[xs + x, ys + y].astype(float)))
    pieces = merge_pieces(pieces, lane_w)
    cut = cv2.dilate(blank, np.ones((13, 13), np.uint8)) > 0
    out = []
    for s, pts in pieces:
        if cut[pts[:, 1].astype(int), pts[:, 0].astype(int)].any():
            continue                                    # cut short by the painted-out flag
        c = pts.mean(0)
        _, v = np.linalg.eigh((pts - c).T @ (pts - c))
        t = (pts - c) @ v[:, -1]
        a_end, b_end = pts[t.argmin()], pts[t.argmax()]
        length = t.max() - t.min()
        if not (0.6 * lane_w <= length <= 1.7 * lane_w):
            continue
        din = lambda q: pos[int(q[1]), int(q[0])]
        inner, outer = (a_end, b_end) if din(a_end) < din(b_end) else (b_end, a_end)
        cy, cx = int(round(c[1])), int(round(c[0]))
        centred = abs(LANES * pos[cy, cx] / local_w[cy, cx] - (s + 0.5))
        if centred > 0.3:
            continue                                    # half a rung, or a scrap at the kerb
        out.append({"lane": s + 1, "inner": inner, "outer": outer, "mid": c,
                    "size": int(len(pts)), "guessed": False, "centred": centred})
    return out


def merge_pieces(pieces, lane_w, reach=9.0):
    """A division broken by a spur or a gap comes as two pieces in the same
    lane, end to end: put them back together. Two different divisions of a
    lane are never end to end, so touching ends are proof enough, as long
    as the whole is no longer than a division."""
    def ends(pts):
        c = pts.mean(0)
        _, v = np.linalg.eigh((pts - c).T @ (pts - c))
        t = (pts - c) @ v[:, -1]
        return pts[t.argmin()], pts[t.argmax()], t.max() - t.min()
    info = [(s, pts, *ends(pts)) for s, pts in pieces]
    merged = True
    while merged:
        merged = False
        for i in range(len(info)):
            si, pi, ai, bi, _ = info[i]
            for j in range(i + 1, len(info)):
                sj, pj, aj, bj, _ = info[j]
                if sj != si or min(np.hypot(*(p - q)) for p in (ai, bi) for q in (aj, bj)) > reach:
                    continue
                pts = np.r_[pi, pj]
                e = ends(pts)
                if e[2] > 1.7 * lane_w:
                    continue
                info[i] = (si, pts, *e)
                del info[j]
                merged = True
                break
            if merged:
                break
    return [(s, pts) for s, pts, *_ in info]


def lap_sense(line, reverse):
    """+1 or -1: which way round the lap runs, from the racing line's
    orientation on the board, flipped by the track's `reverse` flag."""
    cw = cv2.contourArea(line.astype(np.float32), oriented=True) > 0
    return (1.0 if cw else -1.0) * (-1.0 if reverse else 1.0)


def lap_position(line, tangent, reverse, k=40):
    """A function giving how far round the lap a point lies, facing a given
    way, and the lap's length. The nearest point of the racing line is not
    enough in a hairpin, where it may be on the other leg: of the nearest
    points, the one taken is the first whose tangent runs the way the point
    faces -- the other leg runs the opposite way."""
    arc = np.r_[0, np.cumsum(np.hypot(*np.diff(line, axis=0).T))]
    L = arc[-1] + np.hypot(*(line[0] - line[-1]))
    travel = tangent * (-1.0 if reverse else 1.0)
    tree = cKDTree(line)

    def along(p, fwd):
        """For one point, or for many (an array of points, each facing its
        own way)."""
        p, fwd = np.asarray(p, float), np.asarray(fwd, float)
        many = p.ndim == 2
        ks = tree.query(p.reshape(-1, 2), k=min(k, len(line)))[1]
        f = np.broadcast_to(fwd.reshape(-1, 2), (len(ks), 2))
        ok = np.einsum("nkd,nd->nk", travel[ks], f) > 0.5
        j = ks[np.arange(len(ks)), np.where(ok.any(1), ok.argmax(1), 0)]
        out = (L - arc[j]) if reverse else arc[j]
        return out if many else float(out[0])
    return along, L


def order_rungs(rungs, line, tangent, reverse, sense):
    """Each lane's rungs in running order, by where each sits along the
    racing line, facing square to the rung in the sense the lap runs.
    Returns the rungs by lane, each in order with `along` its arc position."""
    along, L = lap_position(line, tangent, reverse)
    by_lane = {}
    for r in rungs:
        a = r["outer"] - r["inner"]
        a = a / (np.linalg.norm(a) + 1e-9)
        r["fwd"] = np.array([-a[1], a[0]]) * sense
        r["along"] = along(r["mid"], r["fwd"])
        r["loop_len"] = L
        by_lane.setdefault(r["lane"], []).append(r)
    for l in by_lane:
        by_lane[l].sort(key=lambda r: r["along"])
    return by_lane


def rung_between(a, b, t):
    """A rung made up between rungs a and b, t of the way from a to b."""
    g = {"lane": a["lane"], "size": 0, "guessed": True, "loop_len": a["loop_len"], "fwd": a["fwd"],
         "along": (a["along"] + t * ((b["along"] - a["along"]) % a["loop_len"])) % a["loop_len"]}
    for key in ("inner", "outer", "mid"):
        g[key] = a[key] + t * (b[key] - a[key])
    return g


def patch_gaps(by_lane, lane_w, max_fill=3):
    """Check the spacing of the rungs along each lane. A cell far shorter
    than its neighbours is a stray line, and the odder of its two rungs is
    dropped; one far longer hides up to `max_fill` undetected divisions,
    which are put in between its rungs and marked as guesses. Returns what
    changed, for the step image."""
    dropped, added = [], []
    # The cell's length along the road: its longer side, measured the way
    # the road runs (a wedge in a hairpin has one long side; a stray lying
    # beside a rung has none).
    def step(a, b):
        return max(abs((b[end] - a[end]) @ r["fwd"]) for end in ("inner", "outer") for r in (a, b))
    length = lambda r: np.hypot(*(r["outer"] - r["inner"]))
    for l, rs in list(by_lane.items()):
        if len(rs) < 4:
            continue
        local = lambda rs, i: np.median([step(rs[(i + k) % len(rs)], rs[(i + k + 1) % len(rs)])
                                         for k in range(-4, 5) if k != 0])
        keep = list(rs)
        i = 0
        while i < len(keep) and len(keep) > 3:
            a, b = keep[i], keep[(i + 1) % len(keep)]
            if step(a, b) < 0.45 * local(keep, i):
                # Of the two, the one that looks least like its neighbours
                # goes: off in length, or off centre in its lane.
                usual = np.median([length(keep[(i + k) % len(keep)]) for k in (-3, -2, 2, 3)])
                odd = lambda r: abs(length(r) - usual) + 20 * r.get("centred", 0)
                weak = b if odd(b) >= odd(a) else a
                dropped.append(weak)
                keep = [q for q in keep if q is not weak]
            else:
                i += 1
        out = []
        for i, r in enumerate(keep):
            out.append(r)
            nxt = keep[(i + 1) % len(keep)]
            mean = step(r, nxt)
            n = int(round(mean / local(keep, i)))
            if mean > 1.6 * local(keep, i) and 2 <= n <= max_fill + 1:
                for k in range(1, n):
                    g = rung_between(r, nxt, k / n)
                    out.append(g)
                    added.append(g)
        by_lane[l] = out
    return dropped, added


# 6. Spaces ------------------------------------------------------------------------

def spaces_from_rungs(by_lane, shape, origin):
    """A space per pair of neighbouring rungs in a lane: its centre from the
    four corners, its facing from one rung to the next, and the spaces it
    touches ahead. Each lane's order starts at the space nearest `origin`."""
    spaces, quads = {}, []
    for l, rs in by_lane.items():
        L = rs[0]["loop_len"]
        cells = []
        for a, b in zip(rs, rs[1:] + rs[:1]):
            corners = np.array([a["inner"], a["outer"], b["outer"], b["inner"]])
            flow = b["mid"] - a["mid"]
            flow = flow / (np.linalg.norm(flow) + 1e-9)
            i = len(spaces) + 1
            spaces[i] = {"pos": corners.mean(0), "flow": flow, "lane": l,
                         "rot": float(np.degrees(np.arctan2(flow[1], flow[0]))),
                         "along": (a["along"] + (b["along"] - a["along"]) % L / 2) % L,
                         "guessed": a["guessed"] or b["guessed"], "next": []}
            quads.append((i, corners))
            cells.append(i)
        start = min(cells, key=lambda i: np.hypot(*(spaces[i]["pos"] - origin)))
        s0 = spaces[start]["along"]
        for i in cells:
            spaces[i]["order"] = (spaces[i]["along"] - s0) % L
        for i, j in zip(cells, cells[1:] + cells[:1]):
            spaces[i]["next"].append(j)
    labels = np.zeros(shape, np.int32)
    for i, corners in quads:
        cv2.fillPoly(labels, [corners.round().astype(np.int32).reshape(-1, 1, 2)], int(i))
    link_across(spaces, labels)
    return spaces, labels


def link_across(spaces, labels):
    """Add to each space's `next` the spaces in the lanes either side that
    touch it, across the line between them, and lie ahead of it."""
    touch = {}
    for dy, dx in ((0, 3), (3, 0), (2, 2), (2, -2), (0, 6), (6, 0), (4, 4), (4, -4)):
        a = labels[6:-6, 6:-6]
        b = labels[6 + dy:labels.shape[0] - 6 + dy, 6 + dx:labels.shape[1] - 6 + dx]
        m = (a > 0) & (b > 0) & (a != b)
        for u, v in set(zip(a[m].tolist(), b[m].tolist())):
            touch.setdefault(u, set()).add(v)
            touch.setdefault(v, set()).add(u)
    for i, s in spaces.items():
        for j in touch.get(i, ()):
            d = spaces[j]["pos"] - s["pos"]
            if abs(spaces[j]["lane"] - s["lane"]) == 1 and d @ s["flow"] > 0.35 * np.hypot(*d):
                s["next"].append(j)
        s["next"] = sorted(set(s["next"]))


# 5-6, read as cells (--cells) ---------------------------------------------------------
#
# Where the grid is printed as dark as on Austin -- black lane lines, crisp
# divisions -- the cells come out cleaner read directly: the asphalt left over
# once every printed line is taken away, a patch per cell. On Monaco's paler
# grid the divisions are too faint for that, and the rungs above are better.

CELL_CONTRAST = 8   # grey levels a printed line sits below the asphalt around it
SCRAP = 0.35        # a patch smaller than this share of a cell is a scrap, not a cell
SIDE_BY_SIDE = 1.4  # a patch this many lanes across is cells side by side


def printed_cells(clean, im, main):
    """The patches of asphalt the printed lines enclose, as a label image
    with stats and centroids. `clean` has the arrows and the flag painted
    out; red corner lines and white paint count as lines."""
    gray = cv2.cvtColor(np.where(main[..., None] > 0, clean, im), cv2.COLOR_BGR2GRAY)
    bg = cv2.medianBlur(gray, 21).astype(np.float32)
    lines = (bg - gray.astype(np.float32)) > CELL_CONTRAST
    hsv = cv2.cvtColor(clean, cv2.COLOR_BGR2HSV).astype(int)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    red = ((H <= 12) | (H >= 165)) & (S > 60) & (V > 60)
    white = (S < 60) & (V >= 205)
    cells = ((main > 0) & ~lines & ~red & ~white).astype(np.uint8)
    cells = cv2.morphologyEx(cells, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    return cv2.connectedComponentsWithStats(cells, connectivity=4)


def middle(xs, ys):
    """The middle of a patch: its centroid, unless that falls off the patch
    or near its edge, as it does for a cell bent round a hairpin -- then the
    point well inside the patch nearest to it."""
    x0, y0 = xs.min() - 1, ys.min() - 1
    m = np.zeros((ys.max() - y0 + 2, xs.max() - x0 + 2), np.uint8)
    m[ys - y0, xs - x0] = 1
    d = cv2.distanceTransform(m, cv2.DIST_L2, 3)
    c = np.array([xs.mean(), ys.mean()])
    deep = d[ys - y0, xs - x0] >= 0.6 * d.max()
    if d[int(round(c[1])) - y0, int(round(c[0])) - x0] >= 0.6 * d.max():
        return c
    k = np.argmin(np.hypot(xs[deep] - c[0], ys[deep] - c[1]))
    return np.array([xs[deep][k], ys[deep][k]], float)


def spaces_from_cells(cells, across_dir, pos, local_w, lane_w, lap, sense, origin, pit=()):
    """A space per printed cell: its centre the middle of the patch, its lane
    where it sits across the road, its facing square to the way across there,
    and the spaces it touches ahead. `lap` is lap_position()'s pair.

    A patch that spans more than a lane across the road is cells whose lines
    did not show: under the painted-out flag the lane lines go, and the
    divisions with them. It is cut up by lane, and each lane's share into as
    many cells as it holds along the lap, all marked as guesses. A patch
    one lane wide is one cell however big -- the outside of a bend, and the
    inside of a hairpin, have cells twice the usual size.

    The patch at or nearest one of the points in `pit` (the track proper can
    stop short of it) is the pit road's -- one of its merge spaces, which
    find_pit.py adds -- and is left out. Each lane's order starts at the
    space nearest `origin`."""
    n, lab, st, _ = cells
    along, L = lap
    areas = st[:, cv2.CC_STAT_AREA]
    typical = float(np.median([areas[i] for i in range(1, n) if areas[i] >= 150]))
    strip = np.floor(LANES * pos / local_w).astype(np.int32).clip(0, LANES - 1)

    def facing(xs, ys, at):
        """The way along the road at `at`, from the way across around it."""
        near = np.hypot(xs - at[0], ys - at[1]) <= 8
        out = across_dir[ys[near], xs[near]].mean(0)
        out /= np.linalg.norm(out) + 1e-9
        return np.array([-out[1], out[0]]) * sense

    off_track = set()
    for x, y in pit:
        x, y, r = int(round(x)), int(round(y)), 10
        near = np.argwhere(lab[y - r:y + r + 1, x - r:x + r + 1] > 0)
        if len(near):
            dy, dx = near[np.argmin(np.hypot(*(near - r).T))]
            off_track.add(int(lab[y - r + dy, x - r + dx]))
    spaces, labels, scraps = {}, np.zeros(lab.shape, np.int32), []
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if i in off_track:
            continue
        if area < SCRAP * typical:
            if area >= 40:
                scraps.append(i)
            continue
        ys, xs = np.nonzero(lab[y:y + h, x:x + w] == i)
        ys, xs = ys + y, xs + x
        lanes = strip[ys, xs]
        across = np.percentile(pos[ys, xs], 90) - np.percentile(pos[ys, xs], 10)
        merged = across > SIDE_BY_SIDE * lane_w
        if merged:
            groups = [(l, np.flatnonzero(lanes == l)) for l in np.unique(lanes)]
            groups = [(l, g) for l, g in groups if len(g) >= SCRAP * typical]
        else:
            groups = [(np.bincount(lanes).argmax(), np.arange(len(xs)))]
        parts = []
        for l, g in groups:
            k = max(1, int(round(len(g) / typical))) if merged else 1
            if k == 1:
                parts.append((l, g))
                continue
            # Along the lap, each pixel facing its own way: a patch round a
            # hairpin bends through half a turn.
            a = across_dir[ys[g], xs[g]]
            t = along(np.c_[xs[g], ys[g]], np.c_[-a[:, 1], a[:, 0]] * sense)
            t = (t - np.median(t) + L / 2) % L      # in one piece, wherever the lap starts
            cuts = np.quantile(t, np.linspace(0, 1, k + 1))
            parts += [(l, g[(t >= c0) & (t <= c1)]) for c0, c1 in zip(cuts[:-1], cuts[1:])]
        for l, part in parts:
            sid = len(spaces) + 1
            mid = middle(xs[part], ys[part])
            fwd = facing(xs[part], ys[part], mid)
            spaces[sid] = {"pos": mid, "flow": fwd, "lane": int(l) + 1,
                           "rot": float(np.degrees(np.arctan2(fwd[1], fwd[0]))),
                           "along": along(mid, fwd), "guessed": merged, "next": []}
            labels[ys[part], xs[part]] = sid
    for l in range(1, LANES + 1):
        lane = sorted((i for i, s in spaces.items() if s["lane"] == l), key=lambda i: spaces[i]["along"])
        if not lane:
            continue
        start = min(lane, key=lambda i: np.hypot(*(spaces[i]["pos"] - origin)))
        for i in lane:
            spaces[i]["order"] = (spaces[i]["along"] - spaces[start]["along"]) % L
        for i, j in zip(lane, lane[1:] + lane[:1]):
            spaces[i]["next"].append(j)
    link_across(spaces, labels)
    return spaces, labels, typical, scraps


# 7. The track file ------------------------------------------------------------------

def write_track(info, im, spaces, line, reverse, read, path):
    """Spaces lane by lane, each lane in running order, with its links ahead.

    A track file that has been edited by hand is never overwritten: the
    detector's guess is only ever a starting point.
    """
    import json
    if path.exists() and json.loads(path.read_text(encoding="utf-8")).get("edited"):
        return False
    ids = {}
    for l in range(1, LANES + 1):
        lane_cells = sorted((i for i, s in spaces.items() if s["lane"] == l),
                            key=lambda i: spaces[i]["order"])
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
        "detect": {"reverse": bool(reverse), "tool": "find_grid.py", "read": read},
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
    clean, flag = paint_out_flag(clean, road)
    cv2.imwrite(str(name("2_no_arrows")), clean)
    print("1-2. road %.1f%% of the board; %d arrows painted out; flag %d px"
          % (100 * road.mean(), n_arrows, int(flag.sum())))

    # The track proper: near the racing line. Leaves out the pit road and
    # scraps of pavement that came along with the road.
    line, length, width = racing_line(im)
    norm = normals(line)
    side = inner_side(line, norm)
    tangent = np.c_[norm[:, 1], -norm[:, 0]]
    outward_line = -norm * side
    lane_w = width / LANES
    main = track_proper(road, line, width)

    across_dir, pos, local_w, inside, widened = road_frame(main, line, outward_line)
    grey, n_red = grey_corners(clean, road, main, across_dir)
    cv2.imwrite(str(name("3_grey_corners")), grey)
    print("3. %d red corner-line pixels redrawn as thin grey lines; road wider than usual on %d px"
          % (n_red, widened))

    # How this board is read, and which way round it runs: as passed, or as
    # the last run on it was.
    from detect_track import ROOT
    import json
    existing = ROOT / "tracks" / f"{map_id}.json"
    detect = {}
    if existing.exists():
        detect = json.loads(existing.read_text(encoding="utf-8")).get("detect", {})
    reverse = "--reverse" in sys.argv or detect.get("reverse", False)
    read = "cells" if "--cells" in sys.argv else detect.get("read", "rungs")
    if read == "cells":
        spaces, labels = cells_steps(map_id, im, clean, main, across_dir, pos, local_w, lane_w, line, tangent,
                                     reverse, name)
    else:
        spaces, labels = rungs_steps(map_id, grey, main, flag, across_dir, pos, local_w, lane_w, line, tangent,
                                     reverse, name)
    per = [sum(1 for s in spaces.values() if s["lane"] == l) for l in range(1, LANES + 1)]
    guessed = sum(1 for s in spaces.values() if s["guessed"])
    print("6. cells %d -- per lane %s; %d %s"
          % (len(spaces), per, guessed, "cut from a patch of several" if read == "cells"
             else "rest on a guessed division"))
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
        cv2.circle(vis, c, 3, (255, 0, 255) if s["guessed"] else (255, 255, 255), -1)
        a = np.radians(s["rot"])
        cv2.line(vis, c, (int(c[0] + 10 * np.cos(a)), int(c[1] + 10 * np.sin(a))), (255, 255, 255), 1)
    cv2.imwrite(str(name("6_spaces")), vis)

    # 7. The track file
    track_path = ROOT / "tracks" / f"{map_id}.json"
    if write_track(info, im, spaces, line, reverse, read, track_path):
        print("7. %d spaces -> %s" % (len(spaces), track_path.relative_to(ROOT)))
    else:
        print("7. %s has been edited by hand; left as it is" % track_path.relative_to(ROOT))
    if map_id == "FDMonaco":
        for label, box in MONACO_CROPS.items():
            cv2.imwrite(str(WORK / f"{map_id}_6_spaces_{label}.png"), crop(vis, box))
    return 0


# Close-ups of Monaco's trickiest corners, for the step images.
MONACO_CROPS = {"loews": (1850, 80, 2330, 520), "grid": (100, 480, 420, 1020),
                "chicane": (780, 480, 1250, 800), "rascasse": (250, 950, 650, 1350)}


def cells_steps(map_id, im, clean, main, across_dir, pos, local_w, lane_w, line, tangent, reverse, name):
    """Steps 4-6 read as cells (--cells): the patches the printed lines enclose."""
    from find_pit import READING        # find_pit builds on this module
    cells = printed_cells(clean, im, main)
    lap = lap_position(line, tangent, reverse)
    spaces, labels, typical, scraps = spaces_from_cells(cells, across_dir, pos, local_w, lane_w, lap,
                                                        lap_sense(line, reverse), line[0],
                                                        READING.get(map_id, {}).get("merges", ()))
    n, lab, st, _ = cells
    print("4-5. %d patches of asphalt between the printed lines; a cell is %.0f px; %d scraps left out"
          % (n - 1, typical, len(scraps)))
    vis = cv2.addWeighted(im, 0.4, np.full_like(im, 255), 0.6, 0)
    np.random.seed(1)
    tint = np.random.randint(40, 230, (n, 3)).astype(np.uint8)
    on = lab > 0
    vis[on] = tint[lab[on]]
    for i in scraps:
        vis[lab == i] = (0, 0, 255)
    cv2.imwrite(str(name("5_cells")), vis)
    return spaces, labels


def rungs_steps(map_id, grey, main, flag, across_dir, pos, local_w, lane_w, line, tangent, reverse, name):
    """Steps 4-6 read as rungs: the divisions across each lane."""
    skel, ink = grid_skeleton(grey, main, flag)
    across, along = split_lines(skel, across_dir)
    print("4. skeleton %d px: %d across the road, %d along it"
          % (int(skel.sum()), int(across.sum()), int(along.sum())))
    vis = grey.copy()
    vis[cv2.dilate(along, np.ones((2, 2), np.uint8)) > 0] = (255, 160, 0)
    vis[cv2.dilate(across, np.ones((2, 2), np.uint8)) > 0] = (0, 220, 0)
    cv2.imwrite(str(name("4_lines")), vis)

    rungs = find_rungs(across, pos, local_w, lane_w, flag)
    by_lane = order_rungs(rungs, line, tangent, reverse, lap_sense(line, reverse))
    found = {l: len(rs) for l, rs in by_lane.items()}
    dropped, added = patch_gaps(by_lane, lane_w)
    print("5. rungs per lane %s; %d stray dropped; %d missing put in by interpolation"
          % ([found.get(l, 0) for l in range(1, LANES + 1)], len(dropped), len(added)))
    np.savez(OUT / f"{map_id}_grid.npz",
             ends=np.array([[r["inner"], r["outer"]] for rs in by_lane.values() for r in rs]),
             lane=np.array([r["lane"] for rs in by_lane.values() for r in rs]),
             guessed=np.array([r["guessed"] for rs in by_lane.values() for r in rs]),
             along=np.array([r["along"] for rs in by_lane.values() for r in rs]),
             centred=np.array([r.get("centred", 0) for rs in by_lane.values() for r in rs]),
             dropped=np.array([[r["inner"], r["outer"]] for r in dropped]).reshape(-1, 2, 2),
             dropped_info=np.array([[r["along"], r.get("centred", 0), r["size"]] for r in dropped]).reshape(-1, 3))
    vis = grey.copy()
    lane_col = [(0, 200, 255), (0, 220, 90), (255, 140, 0)]
    for l, rs in by_lane.items():
        for r in rs:
            col = (255, 0, 255) if r["guessed"] else lane_col[(l - 1) % 3]
            cv2.line(vis, tuple(r["inner"].round().astype(int)), tuple(r["outer"].round().astype(int)), col, 2)
    for r in dropped:
        c = tuple(r["mid"].round().astype(int))
        cv2.line(vis, (c[0] - 5, c[1] - 5), (c[0] + 5, c[1] + 5), (0, 0, 255), 2)
        cv2.line(vis, (c[0] - 5, c[1] + 5), (c[0] + 5, c[1] - 5), (0, 0, 255), 2)
    cv2.imwrite(str(name("5_rungs")), vis)
    if map_id == "FDMonaco":
        for label, box in MONACO_CROPS.items():
            cv2.imwrite(str(WORK / f"{map_id}_5_rungs_{label}.png"), crop(vis, box))
    return spaces_from_rungs(by_lane, main.shape, line[0])


if __name__ == "__main__":
    sys.exit(main())
