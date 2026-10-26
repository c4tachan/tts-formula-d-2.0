"""Find the pit lane on a track board and put it in the track file.

The pit lane is one lane of printed cells beside the track, the pit boxes
-- where a car stops to make its pit stop -- among them: find_grid.py
leaves it out, as it does everything off the racing line. This picks it up
from the pit road's outer wall -- one clean curve, unlike the side the
garages are on -- and follows it:

  1. the pit road is the road find_grid.py's mask has and the track proper
     does not; its wall is the far edge of that, row by row
  2. a line half a lane in from the wall runs down the middle of the cells,
     and the divisions across it show up as dips in its brightness
  3. each cell's centre is the middle of the asphalt across it, measured
     near its ends -- the car drawn in a pit box sits mid-cell, and would
     pull the middle towards the wall

The two ends are where the detector is no help: the last division at each
end is printed on the slant, and beyond it the pit road opens into a merge
with the track -- one space each, with no grid line inside. Those are read
by eye off the crops this writes to out/_work/ and kept in READING below,
as the stop counts are for find_corners.py. So is the colour of each pit
box.

Each team's garage is printed beside two cells of the pit lane, a car
drawn in each. There are ten seats at the table and ten of those cells, so
each seat gets one, and the half of the garage beside it is its pit box:
PLAYERS pairs each printed colour with the two seats nearest it in hue.
The garage halves are found here, as rectangles, for the mod to paint in
the seat's colour, and each is a space of its own, coded b.<sector>.<n>
after the cell beside it -- the way in and out, both ways.

Every track space touching a merge space is a way in or out: each one
touching the entry merge leads into it, and the exit merge leads to each
one touching it. Touching is read off the print -- the cells are the
patches of asphalt the printed lines enclose, and two touch where only a
grid line lies between them, never a wall.

The finish line is the checkered band carried on across the pit road: the
pit cell it crosses is the pit lane's space on the line (code n = 0 in s1),
so a car leaving the pits has crossed it like any other.

Writes the pit spaces into tracks/<id>.json -- lane 0, `pit`, with `fixed`
links, coded p.<sector>.<n> -- along with the track's links into them,
the `pit` block and the finish line; a rerun replaces what an earlier one
wrote. The check image goes to out/<id>_pit.png.

Run:  python tools/extract/find_pit.py FDMonaco
"""
import json
import sys

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d, median_filter

from detect_track import OUT, PALETTE, ROOT, TRACKS, asphalt, board_image, racing_line
from find_grid import paint_out_flag, track_only, track_proper

WORK = OUT / "_work"

# Read by eye, in image pixels. `ends` are the slanted divisions closing the
# printed cells, entry end first; `merges` the centres of the merge spaces
# beyond them; `boxes` the pit boxes' colours in running order, from the
# `first_box`-th pit space (0 being the entry merge); `rows` the image rows
# the pit road's wall runs through, or for one running across the board,
# `cols` the columns. The pit lane is found from the pit road's wall, its edge
# away from the track; `wall: "near"` takes its edge by the track instead,
# for a board where the far edge is broken by a garage as pale as the
# asphalt (Singapore's white one). `area`, where given, is the box (x0, y0,
# x1, y1) the pit road lies in, for a board where the track reaches into it,
# or a polygon of (x, y) points for one running on the slant.
READING = {
    "FDMonaco": {
        "ends": [[[202.5, 1272.5], [235.0, 1301.0]], [[352.5, 623.8], [395.0, 618.8]]],
        "merges": [[200.0, 1318.0], [375.0, 588.0]],
        "first_box": 3,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (570, 1356),  # image rows the pit road's wall runs through
    },
    "FDAustin": {
        "ends": [[[280.0, 959.5], [265.0, 979.5]], [[640.0, 1205.0], [627.0, 1225.0]]],
        "merges": [[222.0, 940.0], [665.0, 1245.0]],
        "first_box": 1,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (940, 1230),
    },
    "FDHockenheim": {
        "ends": [[[405.0, 1272.0], [438.0, 1257.0]], [[214.0, 872.0], [256.0, 880.0]]],
        "merges": [[428.0, 1302.0], [228.0, 850.0]],
        "first_box": 1,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (870, 1300),
    },
    "FDSebring": {
        "ends": [[[776.0, 1226.0], [776.0, 1250.0]], [[1300.0, 1226.0], [1300.0, 1250.0]]],
        "merges": [[740.0, 1236.0], [1336.0, 1236.0]],
        "first_box": 2,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "cols": (760, 1300),
    },
    "FDSingapore": {
        "ends": [[[2297.0, 1018.0], [2322.0, 1018.0]], [[2297.0, 515.0], [2322.0, 515.0]]],
        "merges": [[2310.0, 1045.0], [2312.0, 492.0]],
        "first_box": 2,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (515, 1018),
        "wall": "near",
    },
    "FDValencia": {
        "ends": [[[1128.0, 927.0], [1108.0, 952.0]], [[1005.0, 470.0], [1045.0, 470.0]]],
        "merges": [[1147.0, 1002.0], [1040.0, 440.0]],
        "first_box": 2,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (470, 1000),
    },
    "FDBuddh": {
        "ends": [[[1172.0, 1103.0], [1172.0, 1123.0]], [[1664.0, 1063.0], [1664.0, 1085.0]]],
        "merges": [[1115.0, 1110.0], [1690.0, 1072.0]],
        "first_box": 2,
        "boxes": ["blue", "blue", "red", "red", "green", "green", "yellow", "yellow", "white", "white"],
        "cols": (1172, 1664),
    },
    "FDSotchi": {
        "ends": [[[2128.0, 1442.0], [2128.0, 1466.0]], [[1662.0, 1438.0], [1662.0, 1460.0]]],
        "merges": [[2180.0, 1455.0], [1620.0, 1440.0]],
        "first_box": 1,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "cols": (1662, 2128),
        "area": (1645, 1436, 2200, 1467),
        "wall": "near",
    },
    "FDe01": {
        "ends": [[[177.0, 1228.0], [202.0, 1250.0]], [[330.0, 640.0], [360.0, 622.0]]],
        "merges": [[163.0, 1283.0], [360.0, 500.0]],
        "first_box": 3,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (500, 1290),
    },
    "FDe02": {
        "ends": [[[931.0, 1201.0], [931.0, 1231.0]], [[398.0, 1201.0], [398.0, 1231.0]]],
        "merges": [[975.0, 1222.0], [345.0, 1225.0]],
        "first_box": 2,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "cols": (398, 931),
        "area": (320, 1198, 1020, 1232),
        "wall": "near",
    },
    "FDe03": {
        "ends": [[[1843.0, 676.0], [1872.0, 673.0]], [[1995.0, 1152.0], [2022.0, 1148.0]]],
        "merges": [[1850.0, 620.0], [2025.0, 1195.0]],
        "first_box": 2,
        "boxes": ["white", "white", "yellow", "yellow", "green", "green", "red", "red", "blue", "blue"],
        "rows": (676, 1152),
        "area": [(1836, 640), (1873, 640), (2012, 1105), (2024, 1152), (1994, 1162), (1952, 1110)],
        "wall": "near",
    },
}

# The two seats sharing each printed team colour, in running order: the
# first pit box of that colour goes to the first seat.
PLAYERS = {
    "white": ("White", "Brown"),
    "yellow": ("Yellow", "Orange"),
    "green": ("Green", "Teal"),
    "red": ("Red", "Pink"),
    "blue": ("Blue", "Purple"),
}

LANE_W = 26     # px: the pit lane's width, wall to wall, where no pit box narrows it
DIP = 8         # grey levels a division sits below the asphalt around it
DARK = 10       # grey levels any printed line sits below the asphalt around it
SEAM = 4        # px: as far as a grid line runs across; a wall is wider
TOUCH = 30      # px of another cell within SEAM of a merge space's: a shared edge
GARAGE = (14, 62)   # px out from a pit box's centre that its garage lies within
ON_LINE = 8     # px: a division this near the middle of the finish band lies under it


def lavender(hsv):
    """The asphalt: a pale lavender. The grey of the white team's garage is
    as dull, but warm. On a Formula Dé board, its stronger blue-grey."""
    if PALETTE["palette"] == "formula_de":
        return asphalt(hsv)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return (s < 40) & ((h > 110) | (s < 12)) & (v > 100) & (v < 215)


REACH_END = 30  # px: how near each end read off the board the pit road must come


def near_both(lab, ends):
    """The labels in `lab` that come within REACH_END of the middle of both
    `ends`, nearest first."""
    seen = []
    for e in ends:
        x, y = np.round(np.mean(e, axis=0)).astype(int)
        y0, x0 = max(y - REACH_END, 0), max(x - REACH_END, 0)
        win = lab[y0:y + REACH_END + 1, x0:x + REACH_END + 1]
        d = {}
        for (py, px), k in zip(np.argwhere(win > 0), win[win > 0]):
            r = np.hypot(py + y0 - y, px + x0 - x)
            if r <= REACH_END and r < d.get(int(k), np.inf):
                d[int(k)] = r
        seen.append(d)
    both = set(seen[0]) & set(seen[1])
    return sorted(both, key=lambda k: max(seen[0][k], seen[1][k]))


def pit_road(im, ends, area=None):
    """The road off the track proper: the pit road's asphalt, the patch of it
    that runs between the two `ends` read off the board.

    Only the lavender: the road mask can take in the garages, and on Austin
    the crowd beyond them, which would pass for the wall. And where the road
    mask leaves the pit road out altogether -- on Hockenheim a white wall
    cuts it off from the track the whole way along, and the road mask keeps
    only the track's piece -- the lavender is looked for on its own."""
    _, road = track_only(im)
    asphalt = lavender(cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int))
    if area is not None:
        # Read off the board: the box the pit road lies in, its track side
        # just short of the wall, for where the track proper reaches into
        # the pit road (Sochi's exit).
        pit = np.zeros(asphalt.shape, np.uint8)
        if len(area) == 4 and not isinstance(area[0], (tuple, list)):
            x0, y0, x1, y1 = area
            pit[y0:y1, x0:x1] = asphalt[y0:y1, x0:x1]
        else:
            # A polygon, for a pit road running on the slant.
            cv2.fillPoly(pit, [np.array(area, np.int32)], 1)
            pit &= asphalt.astype(np.uint8)
        pit = cv2.morphologyEx(pit, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(pit, 8)
        return lab == 1 + int(np.argmax(st[1:, 4])), road
    line, _, width = racing_line(im)
    main = track_proper(road, line, width)
    off_track = ~(cv2.dilate(main, np.ones((9, 9), np.uint8)) > 0)
    pit = ((road > 0) & off_track).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(pit, 8)
    pit = (lab == 1 + int(np.argmax(st[1:, 4]))).astype(np.uint8) & asphalt
    pit = cv2.morphologyEx(pit, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(pit, 8)
    best = 1 + int(np.argmax(st[1:, 4]))
    if best not in near_both(lab, ends):
        pit = (asphalt & off_track).astype(np.uint8)
        pit = cv2.morphologyEx(pit, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        lab = cv2.connectedComponents(pit, connectivity=8)[1]
        found = near_both(lab, ends)
        if found:
            return lab == found[0], road
        # Broken in pieces along the way (Sochi's, by the pit box markers):
        # every piece lying across the line from one end to the other.
        a, b = [np.round(np.mean(e, axis=0)).astype(int) for e in ends]
        band = np.zeros(lab.shape, np.uint8)
        cv2.line(band, tuple(int(v) for v in a), tuple(int(v) for v in b), 1, 9)
        ks, counts = np.unique(lab[(band > 0) & (lab > 0)], return_counts=True)
        pieces = [k for k, c in zip(ks, counts) if c >= 30]
        if not pieces:
            sys.exit("no pit road runs between the ends in READING -- check them")
        joined = cv2.morphologyEx(np.isin(lab, pieces).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
        lab = cv2.connectedComponents(joined, connectivity=8)[1]
        found = near_both(lab, ends)
        if not found:
            sys.exit("no pit road runs between the ends in READING -- check them")
        best = found[0]
    return lab == best, road


def middle_line(pit, rows, toward, across=False):
    """The line half a lane in from the pit road's wall, at a pixel a step:
    points, and unit normals pointing in from the wall. The wall is the pit
    road's far edge from the track, `toward` +1 for its right side, -1 its
    left -- or, for a pit road running `across` the board (Sebring's), its
    lower side or its upper, and `rows` are then the columns it spans."""
    if across:
        pts, nrms = middle_line(pit.T, rows, toward)
        return pts[:, ::-1], nrms[:, ::-1]
    ys = np.arange(rows[0], rows[1], 4)
    keep, xs = [], []
    for y in ys:
        row = np.nonzero(pit[y])[0]
        if len(row):
            keep.append(y)
            xs.append(row.max() if toward > 0 else row.min())
    wall = np.c_[gaussian_filter1d(np.array(xs, float), 2), keep]
    d = np.gradient(wall, axis=0)
    d /= np.linalg.norm(d, axis=1)[:, None]
    nrm = np.c_[-d[:, 1], d[:, 0]]
    nrm *= np.sign(-toward * nrm[:, 0])[:, None]
    mid = wall + nrm * (LANE_W / 2)
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(mid, axis=0), axis=1))]
    t = np.arange(0, seg[-1], 1.0)
    pts = np.c_[np.interp(t, seg, mid[:, 0]), np.interp(t, seg, mid[:, 1])]
    nrms = np.c_[np.interp(t, seg, nrm[:, 0]), np.interp(t, seg, nrm[:, 1])]
    return pts, nrms / np.linalg.norm(nrms, axis=1)[:, None]


def divisions(im, pts, nrms):
    """Indices along the middle line where a division crosses it."""
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY).astype(float)
    sat = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)[..., 1]
    level = np.full(len(pts), np.nan)
    for i, (p, n) in enumerate(zip(pts, nrms)):
        vals = []
        for o in range(-9, 10):
            x, y = np.round(p + n * o).astype(int)
            if sat[y, x] < 70:      # leave out the cars drawn in the pit boxes
                vals.append(gray[y, x])
        if len(vals) > 6:
            level[i] = np.median(vals)
    dip = median_filter(np.nan_to_num(level, nan=150), 31) - level
    out = []
    for i in range(len(pts)):
        if dip[i] > DIP and dip[i] >= np.nanmax(dip[max(0, i - 5):i + 6]):
            if not out or i - out[-1] > 3:
                out.append(i)
    return out


def along(pts, p):
    """The index of the middle line's point nearest p."""
    return int(np.argmin(np.linalg.norm(pts - np.asarray(p, float), axis=1)))


def cell_centre(im, pts, nrms, i0, i1):
    """The middle of the asphalt across the cell between two divisions,
    measured a tenth of the way in from each end and averaged."""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    road = lavender(hsv) | ((gray < 125) & (hsv[..., 1] < 45))

    def asphalt(q):
        x, y = np.round(q).astype(int)
        return road[y, x]

    mids = []
    for frac in (0.1, 0.9):
        j = int(round(i0 + frac * (i1 - i0)))
        p, n = pts[j], nrms[j]
        o0 = 0
        while not asphalt(p + n * o0) and o0 > -15:
            o0 -= 1
        ends = []
        for sgn in (1, -1):
            o = o0
            while abs(o) < 40 and asphalt(p + n * (o + sgn)):
                o += sgn
            ends.append(o)
        mids.append(p + n * np.mean(ends))
    return np.mean(mids, axis=0)


def touching(im, at, spaces, window=150, seam=SEAM):
    """Of `spaces`, the ones whose printed cell shares an edge with the cell
    at `at`: their patches of asphalt lie within a grid line's width
    (`seam`) of each other along at least TOUCH px."""
    x0, y0 = (np.round(at).astype(int) - window).clip(0)
    sub = im[y0:y0 + 2 * window, x0:x0 + 2 * window]
    gray = cv2.cvtColor(sub, cv2.COLOR_BGR2GRAY)
    line = cv2.medianBlur(gray, 15).astype(int) - gray.astype(int) > DARK
    patch = (lavender(cv2.cvtColor(sub, cv2.COLOR_BGR2HSV).astype(int)) & ~line).astype(np.uint8)
    _, lab = cv2.connectedComponents(patch, connectivity=4)

    def label(p):
        x, y = int(round(p[0])) - x0, int(round(p[1])) - y0
        if not (0 <= x < lab.shape[1] and 0 <= y < lab.shape[0]):
            return 0
        for r in range(7):    # the centre may sit on a printed number
            near = lab[max(y - r, 0):y + r + 1, max(x - r, 0):x + r + 1]
            near = near[near > 0]
            if len(near):
                return int(np.bincount(near).argmax())
        return 0

    mine = label(at)
    if not mine:
        return []
    seam = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * seam + 1, 2 * seam + 1))
    reach = cv2.dilate((lab == mine).astype(np.uint8), seam) > 0
    out = []
    for s in spaces:
        k = label(s["pos"])
        if k and k != mine and np.count_nonzero(reach & (lab == k)) >= TOUCH:
            out.append(s)
    return out


def garage(im, cells):
    """The garage printed beside a team's pit boxes, split in half: one
    rectangle per box, as (centre, facing, (length, depth)) in pixels.

    `cells` are the boxes in running order, each (centre, forward, out):
    `out` points from the pit lane towards the garages. The garage is the
    largest patch of its colour within GARAGE of the boxes, and no more than
    a little past their ends along the lane -- the cars drawn in the boxes
    are its colour too, but nearer, and past its ends the white team's runs
    into pale ground on Hockenheim -- and the white team's,
    grey but warm, is told from the pavement by its hue and by being less
    saturated. (Austin's is paler than Monaco's.)"""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    seeds = [np.round(c + o * np.mean(GARAGE)).astype(int) for c, _, o in cells]
    seed = np.median([hsv[y, x] for x, y in seeds], axis=0)
    h, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    dh = np.minimum(abs(h - seed[0]), 180 - abs(h - seed[0]))
    if seed[1] > 100:
        colour = (dh < 10) & (sat > 110)
    elif seed[1] < 12 and seed[2] > 200:
        # Plain white (the Formula Dé boards' white team): no hue to go by.
        colour = (sat < 25) & (val > 200)
    elif seed[1] > 45:
        # A duller colour (the Formula Dé boards' dark green): its hue, and
        # about its own saturation and brightness.
        colour = (dh < 10) & (sat > 0.6 * seed[1]) & (abs(val - seed[2]) < 60)
    else:
        # The paler the grey, the less its hue says: Austin's spreads twice
        # as wide as Monaco's, though still short of the pavement's.
        colour = (dh <= (4 if seed[1] >= 25 else 8)) & (sat > min(25, seed[1] - 8)) & (sat < 52) & (val > 140)
    ys, xs = np.mgrid[0:im.shape[0], 0:im.shape[1]]
    band = np.zeros(colour.shape, bool)
    length = np.linalg.norm(cells[-1][0] - cells[0][0]) / max(len(cells) - 1, 1)
    for c, f, o in cells:
        dx, dy = xs - c[0], ys - c[1]
        a, b = dx * f[0] + dy * f[1], dx * o[0] + dy * o[1]
        band |= (abs(a) <= 0.6 * length) & (b >= GARAGE[0]) & (b <= GARAGE[1])
    mask = cv2.morphologyEx((colour & band).astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    # A garage printed as bays with dark lines between (Austin's white one)
    # comes apart in stripes: close them up into the one garage.
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)) & band
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask, 8)
    if n < 2:
        return None
    pts = np.argwhere(lab == 1 + int(np.argmax(st[1:, 4])))[:, ::-1].astype(np.float32)
    (cx, cy), (w, hgt), ang = cv2.minAreaRect(pts)
    a = np.radians(ang)
    axis = np.array([np.cos(a), np.sin(a)])
    long_, deep = w, hgt
    if hgt > w:
        axis, long_, deep = np.array([-np.sin(a), np.cos(a)]), hgt, w
    if axis @ cells[0][1] < 0:
        axis = -axis
    rot = float(np.degrees(np.arctan2(axis[1], axis[0])) % 360)
    k = len(cells)
    centre = np.array([cx, cy])
    return [(centre + axis * long_ * ((i + 0.5) / k - 0.5), rot, (long_ / k, deep)) for i in range(k)]


def mean_rot(spaces):
    """The spaces' average facing, in degrees."""
    a = np.radians([s["rot"] for s in spaces])
    return float(np.degrees(np.arctan2(np.sin(a).mean(), np.cos(a).mean())) % 360)


def heading(a, b):
    """Degrees from a to b, image space (0 = right, clockwise)."""
    return float(np.degrees(np.arctan2(b[1] - a[1], b[0] - a[0])) % 360)


def band_line(im, road, line):
    """The finish band as a point and a direction along it: through the middle
    of the checkered patch nearest the line's spaces, square to the way they
    face. (The patch's own long axis is no guide: its ends are cut on the
    slant along the lanes, and it is barely longer than it is wide.)"""
    track_img, _ = track_only(im)
    _, band = paint_out_flag(track_img, road)
    n, lab, _, cents = cv2.connectedComponentsWithStats(band.astype(np.uint8), 8)
    near = np.mean([s["pos"] for s in line], axis=0)
    k = 1 + int(np.argmin(np.linalg.norm(cents[1:] - near, axis=1)))
    a = np.radians(np.mean([s["rot"] for s in line]))
    return cents[k], np.array([-np.sin(a), np.cos(a)])


def main():
    map_id = sys.argv[1] if len(sys.argv) > 1 else "FDMonaco"
    if map_id not in READING:
        sys.exit(f"no reading of {map_id}'s pit lane in READING -- read its ends off the board first")
    rd = READING[map_id]
    path = TRACKS / f"{map_id}.json"
    track = json.loads(path.read_text(encoding="utf-8"))
    info, im = board_image(map_id)
    WORK.mkdir(parents=True, exist_ok=True)

    # What an earlier run wrote goes first.
    old = {s["id"] for s in track["spaces"] if s.get("pit")}
    track["spaces"] = [s for s in track["spaces"] if not s.get("pit")]
    for s in track["spaces"]:
        s["next"] = [n for n in s["next"] if n not in old]
    by_id = {s["id"]: s for s in track["spaces"]}
    # The ways in and out: the track spaces touching each merge.
    entries, exits = [touching(im, m, track["spaces"], seam=SEAM * info["upscale"]) for m in rd["merges"]]
    if not entries or not exits:
        sys.exit("no track space touches the %s merge -- check its centre in READING"
                 % ("entry" if not entries else "exit"))

    pit, road = pit_road(im, rd["ends"], rd.get("area"))
    # The wall is the side of the pit road away from the track.
    centre = np.argwhere(pit)[:, ::-1].mean(axis=0)
    across = "cols" in rd
    k = 1 if across else 0
    toward = 1 if centre[k] > np.mean([s["pos"][k] for s in entries]) else -1
    if rd.get("wall") == "near":
        toward = -toward
    pts, nrms = middle_line(pit, rd["cols"] if across else rd["rows"], toward, across)
    cuts = divisions(im, pts, nrms)
    print("1. pit road: middle line %d px long; %d divisions across it" % (len(pts), len(cuts)))

    # Running order: from the end nearer the entry.
    ends = [np.mean(e, axis=0) for e in rd["ends"]]
    first, last = along(pts, ends[0]), along(pts, ends[1])
    if first > last:
        pts, nrms = pts[::-1], nrms[::-1]
        cuts = sorted(len(pts) - 1 - i for i in cuts)
        first, last = len(pts) - 1 - first, len(pts) - 1 - last
    cuts = [first] + [i for i in cuts if first + 10 < i < last - 10] + [last]
    # A division too faint to dip (Sebring's, where a garage meets the next)
    # leaves a cell two or more long: cut it evenly.
    usual = np.median(np.diff(cuts))
    filled = [cuts[0]]
    for a, b in zip(cuts, cuts[1:]):
        k = int(round((b - a) / usual))
        filled += [int(round(a + (b - a) * j / k)) for j in range(1, k)] if k > 1 else []
        filled.append(b)
    added, cuts = len(filled) - len(cuts), filled
    gaps = np.diff(cuts)
    print("2. %d printed cells, %.0f-%.0f px long (median %.0f)%s"
          % (len(gaps), gaps.min(), gaps.max(), np.median(gaps),
             "; %d division(s) too faint to see put in" % added if added else ""))

    centres = [np.asarray(rd["merges"][0], float)]
    centres += [cell_centre(im, pts, nrms, a, b) for a, b in zip(cuts, cuts[1:])]
    centres.append(np.asarray(rd["merges"][1], float))
    # A merge space faces the way the track beside it runs.
    rots = [mean_rot(entries)]
    rots += [heading(pts[a], pts[b]) for a, b in zip(cuts, cuts[1:])]
    rots.append(mean_rot(exits))

    # The band, carried on across the pit road, crosses one cell: that one
    # is the pit lane's space on the line. Where it lies along a division
    # instead (Austin's), the space on the line is the cell just past it, as
    # on the track; and where it lies past the last division (Hockenheim's),
    # it is the exit merge. Space k ends at division k, the exit merge at
    # its centre.
    line_spaces = [by_id[v] for v in track.get("finish", {}).get("line", []) if v in by_id]
    if not line_spaces:
        sys.exit("no finish line in %s -- run find_corners.py first" % path.relative_to(ROOT))
    c, d = band_line(im, road, line_spaces)
    side = np.array([(p - c)[0] * d[1] - (p - c)[1] * d[0] for p in list(pts[cuts]) + [centres[-1]]])
    side *= np.sign(side[-1] - side[0])          # + is past the band, in running order
    on_line = next((k for k in range(1, len(side)) if side[0] < 0 < side[k] - ON_LINE), None)
    line_sector, before = exits[0]["sector"], entries[0]["sector"]

    spaces = []
    for k, (p, r) in enumerate(zip(centres, rots)):
        past = on_line is not None and k >= on_line
        sector = line_sector if past else before
        n = k - on_line if past else k
        spaces.append({"id": "p.%s.%d" % (sector, n), "pos": [round(float(v), 1) for v in p],
                       "rot": round(r, 1), "lane": 0, "next": [], "fixed": True,
                       "corner": None, "sector": sector, "pit": True})
    for a, b in zip(spaces, spaces[1:]):
        a["next"] = [b["id"]]
    spaces[-1]["next"] = sorted(s["id"] for s in exits)
    for s in entries:
        s["next"] = sorted(s["next"] + [spaces[0]["id"]])
    track["spaces"] += spaces
    ids = [s["id"] for s in spaces]
    entry_ids, exit_ids = sorted(s["id"] for s in entries), sorted(s["id"] for s in exits)
    print("3. %d pit spaces, %s to %s; in from %s, out to %s"
          % (len(spaces), ids[0], ids[-1], ", ".join(entry_ids), ", ".join(exit_ids)))

    boxes = [{"beside": ids[rd["first_box"] + i], "colour": col} for i, col in enumerate(rd["boxes"])]
    # Which side of the pit lane the garages are on: Monaco's lie between it
    # and the track, away from the wall; Austin's along the wall. It is the
    # side where the ground beside the pit boxes is coloured.
    sat = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)[..., 1]

    def beside(b, sign):
        """The pit box's cell centre, and the way out of it to the side `sign`."""
        k = ids.index(b["beside"])                    # printed cell k: cuts[k - 1] to cuts[k]
        mid = (cuts[k - 1] + cuts[k]) // 2
        return np.array(spaces[k]["pos"]), nrms[mid] * sign
    garage_side = max((1, -1), key=lambda sign: np.median([
        sat[tuple(np.round(p + o * np.mean(GARAGE)).astype(int)[::-1])] for p, o in (beside(b, sign) for b in boxes)]))
    # Each team's two boxes: a seat and half the garage each.
    teams = {}
    for b in boxes:
        teams.setdefault(b["colour"], []).append(b)
    for colour, team in teams.items():
        cells = []
        for b in team:
            a = np.radians(rots[ids.index(b["beside"])])
            at, out = beside(b, garage_side)
            cells.append((at, np.array([np.cos(a), np.sin(a)]), out))
        halves = garage(im, cells)
        if halves is None:
            sys.exit("no %s garage found beside %s" % (colour, ", ".join(b["beside"] for b in team)))
        for b, seat, (at, r, (ln, dp)) in zip(team, PLAYERS[colour], halves):
            b["player"] = seat
            b["garage"] = {"pos": [round(float(v), 1) for v in at], "rot": round(r, 1),
                           "size": [round(float(ln), 1), round(float(dp), 1)]}
    # Each pit box is a space of its own: the car of its seat goes in from
    # the pit lane space beside it, and comes back out the same way.
    lane_of = {s["id"]: s for s in spaces}
    for i, b in enumerate(boxes):
        beside, g = lane_of[b["beside"]], b["garage"]
        box = {"id": "b." + beside["id"].split(".", 1)[1], "pos": g["pos"], "rot": g["rot"], "lane": 0,
               "next": [beside["id"]], "fixed": True, "corner": None, "sector": beside["sector"],
               "pit": True, "box": b["player"]}
        beside["next"] = sorted(beside["next"] + [box["id"]])
        track["spaces"].append(box)
        boxes[i] = {"space": box["id"], **b}
    print("   pit boxes: %s" % ", ".join("%s %s" % (b["space"], b["player"]) for b in boxes))
    track["pit"] = {"entry": entry_ids, "exit": exit_ids, "spaces": ids, "boxes": boxes}
    line = [v for v in track.get("finish", {}).get("line", []) if v not in old]
    if on_line is not None:
        line.append(ids[on_line])
        print("4. the finish line crosses the pit lane at %s" % ids[on_line])
    else:
        print("4. the finish line does not cross the pit lane")
    track["finish"] = {**track.get("finish", {}), "line": line}
    path.write_text(json.dumps(track, indent=1), encoding="utf-8")
    print("   ->", path.relative_to(ROOT))

    vis = im.copy()
    for i in cuts:
        a, b = pts[i] - nrms[i] * 16, pts[i] + nrms[i] * 16
        cv2.line(vis, tuple(np.round(a).astype(int)), tuple(np.round(b).astype(int)), (0, 220, 0), 1)
    box_ids = {b["space"] for b in boxes}
    in_boxes = [s for s in track["spaces"] if s["id"] in box_ids]
    # The pit lane's links, and the track's into it.
    shown = {s["id"]: s["pos"] for s in spaces + exits + in_boxes}
    for s in spaces + entries + in_boxes:
        p = tuple(np.round(s["pos"]).astype(int))
        for nid in s["next"]:
            q = shown.get(nid) if s.get("pit") or nid in ids else None
            if q is not None:
                cv2.arrowedLine(vis, p, tuple(np.round(q).astype(int)), (255, 0, 255), 1, tipLength=0.2)
        cv2.circle(vis, p, 3, (0, 200, 255) if s["id"] in box_ids else (0, 0, 255), -1)
    for s in exits:
        cv2.circle(vis, tuple(np.round(s["pos"]).astype(int)), 3, (0, 0, 255), -1)
    q = c + d * 400
    cv2.line(vis, tuple(np.round(c - d * 400).astype(int)), tuple(np.round(q).astype(int)), (255, 255, 0), 1)
    for b in boxes:
        g = b["garage"]
        rect = ((g["pos"][0], g["pos"][1]), (g["size"][0], g["size"][1]), g["rot"])
        cv2.polylines(vis, [cv2.boxPoints(rect).astype(np.int32)], True, (255, 0, 255), 1)
    out = OUT / f"{map_id}_pit.png"
    cv2.imwrite(str(out), vis)
    x0, y0 = np.floor(pts.min(axis=0)).astype(int) - 60
    x1, y1 = np.ceil(pts.max(axis=0)).astype(int) + 60
    for label, k in (("entry", 0), ("exit", -1)):
        cx, cy = np.round(centres[k]).astype(int)
        crop = vis[max(cy - 60, 0):cy + 60, max(cx - 60, 0):cx + 60]
        cv2.imwrite(str(WORK / f"{map_id}_pit_{label}.png"), cv2.resize(crop, None, fx=4, fy=4))
    cv2.imwrite(str(WORK / f"{map_id}_pit_lane.png"), cv2.resize(vis[y0:y1, x0:x1], None, fx=2, fy=2))
    print("   ->", out.relative_to(ROOT), "and out/_work/%s_pit_*.png" % map_id)

    import gen_tracks
    gen_tracks.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
