"""Pick a spot on the board for the dice tray, and the side of it the dice
not in play line up along: over the board's own name logo, which is no use
in a race, and as clear of the track as it can be from there.

The tray and its row of parked dice (fd.tts.dice) are a fixed size in the
world, and the board tile a fixed 44 x 26 units, so on the image they are a
known rectangle for each of the four sides the row can be on. Every space
and pit garage is an obstacle; the spot is the one where that rectangle is
furthest from all of them, and once it is clear by CLEAR or more, the one
nearest the logo -- always with the logo's middle inside the tray.

The logos differ between the two games. Each Formula D board has a name
card of its own design, read off the board by eye into CARDS; every Formula
De board has the same checkered title box, found by title_box(). A board
with neither has the spot nearest its middle.

Writes `dice` and `dice_side` into tracks/<id>.json -- unless it has a spot
already, which is taken to be set by hand (Monaco's, on its name panel):
--force replaces it -- then regenerates the Lua modules. The spot is
easily moved in the game afterwards: the board's right-click menu has Put
the dice here and Turn the dice. A check image goes to out/<id>_dice.png.

Run:  python tools/extract/find_dice_spot.py                every track
      python tools/extract/find_dice_spot.py FDBuddh FDSotchi [--force]
"""
import json
import pathlib
import sys

import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
TRACKS = ROOT / "tracks"
OUT = ROOT / "tools" / "extract" / "out"

# The board tile, in world units (its scale; the mesh is one unit across).
BOARD = (44.0, 26.0)
# The tray and parked row, in world units, from fd.tts.dice.
TRAY_WIDTH, TRAY_DEPTH, WALL = 11.0, 7.0, 0.3
SPACING, PARK_GAP, DIE = 2.2, 1.5, 1.6
N_DICE = 7
# Room left round it all, in world units.
MARGIN = 0.4
# How near a space's centre, in cells, the road and its kerbs still reach.
ROAD = 0.95
# Clearance, in world units, past which nearer the middle wins.
CLEAR = 2.0
# Read at this fraction of the image's size: plenty for a spot.
SCALE = 0.25

SIDES = {"up": (0, -1), "right": (1, 0), "down": (0, 1), "left": (-1, 0)}

# The Formula D boards' name cards, read by eye: (x0, y0, x1, y1) in board
# pixels.
CARDS = {
    "FDAustin": (1809, 683, 2166, 916),
    "FDBuddh": (123, 803, 472, 1020),
    "FDHockenheim": (1892, 1249, 2263, 1489),
    "FDMonaco": (1324, 1348, 1695, 1583),
    "FDSebring": (2031, 62, 2398, 297),
    "FDSingapore": (804, 1336, 1176, 1572),
    "FDSotchi": (259, 1188, 643, 1435),
    "FDValencia": (1887, 1139, 2259, 1375),
}
# The checkered frame of a Formula De title box at a board's usual width
# (2480 px), in pixels.
TITLE_FRAME = (292, 248)


def title_box(im):
    """The checkered frame round a Formula De board's title, as (x0, y0, x1,
    y1), or None: a patch where black and white are finely mixed, the size
    the frame always is."""
    g = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    s = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)[..., 1]
    black = ((g < 90) & (s < 90)).astype(np.float32)
    white = ((g > 170) & (s < 60)).astype(np.float32)
    mix = cv2.blur(black, (21, 21)) * cv2.blur(white, (21, 21))
    checker = cv2.morphologyEx((mix > 0.09).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((31, 31), np.uint8))
    n, _, st, _ = cv2.connectedComponentsWithStats(checker, 8)
    want = np.array(TITLE_FRAME) * im.shape[1] / 2480
    best = None
    for i in range(1, n):
        x, y, w, h = (int(v) for v in st[i, :4])
        off = float(np.abs(np.array([w, h]) / want - 1).max())
        if off < 0.25 and (best is None or off < best[0]):
            best = (off, (x, y, x + w, y + h))
    return best and best[1]


def logo_of(track):
    """The board's name logo, (x0, y0, x1, y1) in board pixels, or None."""
    if track["id"] in CARDS:
        return CARDS[track["id"]]
    if track["ruleset"] != "formula_d":
        sys.path.insert(0, str(ROOT / "tools" / "extract"))
        from detect_track import board_image
        return title_box(board_image(track["id"])[1])
    return None


def footprint(side):
    """The tray and parked row as (left, top, right, bottom) world units from
    the tray's centre, image axes: x right, y down."""
    hw, hd = TRAY_WIDTH / 2 + WALL, TRAY_DEPTH / 2 + WALL
    row = (N_DICE - 1) * SPACING / 2 + DIE / 2
    dx, dy = SIDES[side]
    if dy:      # the row along x, beyond the tray's top or bottom wall
        out = hd + PARK_GAP + DIE
        box = [-max(hw, row), -hd, max(hw, row), hd]
        if dy < 0:
            box[1] = -out
        else:
            box[3] = out
    else:       # along y, beyond its left or right wall
        out = hw + PARK_GAP + DIE
        box = [-hw, -max(hd, row), hw, max(hd, row)]
        if dx < 0:
            box[0] = -out
        else:
            box[2] = out
    return [box[0] - MARGIN, box[1] - MARGIN, box[2] + MARGIN, box[3] + MARGIN]


def cell_length(track):
    pos = {s["id"]: np.array(s["pos"], float) for s in track["spaces"]}
    lane = {s["id"]: s["lane"] for s in track["spaces"]}
    steps = [np.hypot(*(pos[n] - pos[s["id"]])) for s in track["spaces"]
             for n in s["next"] if n in pos and lane[n] == s["lane"]]
    return float(np.median(steps)) if steps else 45.0


def find_spot(track, logo=None):
    """(score, x, y in image pixels, side, room, footprint, scale): room is
    the clearance in world units, or where none is clear, minus the share of
    the footprint over the track (the parked row's, if the tray is clear)."""
    W, H = track["image"]["width"], track["image"]["height"]
    w, h = int(W * SCALE), int(H * SCALE)
    unit = (w / BOARD[0], h / BOARD[1])      # small-image pixels per world unit, x and y
    blocked = np.zeros((h, w), np.uint8)
    r = int(round(ROAD * cell_length(track) * SCALE))
    for s in track["spaces"]:
        cv2.circle(blocked, (int(s["pos"][0] * SCALE), int(s["pos"][1] * SCALE)), r, 1, -1)
    for b in (track.get("pit") or {}).get("boxes", []):
        g = b.get("garage")
        if g:
            cv2.circle(blocked, (int(g["pos"][0] * SCALE), int(g["pos"][1] * SCALE)),
                       int(max(g["size"]) * SCALE), 1, -1)
    clear = cv2.distanceTransform((1 - blocked).astype(np.uint8), cv2.DIST_L2, 5)
    # Clearance in world units, the smaller of the two axes' scales.
    clear = clear / min(unit)
    ys, xs = np.mgrid[0:h, 0:w]
    # Near the logo's middle, if there is one, else the board's.
    cx, cy = (((logo[0] + logo[2]) / 2 * SCALE, (logo[1] + logo[3]) / 2 * SCALE) if logo
              else (w / 2, h / 2))
    to_middle = np.hypot((xs - cx) / unit[0], (ys - cy) / unit[1])
    # And with the logo's middle inside the tray.
    over_logo = ((np.abs(xs - cx) <= TRAY_WIDTH / 2 * unit[0]) & (np.abs(ys - cy) <= TRAY_DEPTH / 2 * unit[1])
                 if logo else np.ones((h, w), bool))
    # The tray alone, walls and all.
    tx0, ty0 = int(np.ceil((TRAY_WIDTH / 2 + WALL) * unit[0])), int(np.ceil((TRAY_DEPTH / 2 + WALL) * unit[1]))
    tkw, tkh = 2 * tx0 + 1, 2 * ty0 + 1
    best = None
    for side in SIDES:
        l, t, rt, b = footprint(side)
        x0, y0 = int(np.ceil(-l * unit[0])), int(np.ceil(-t * unit[1]))
        kw, kh = x0 + int(np.ceil(rt * unit[0])) + 1, y0 + int(np.ceil(b * unit[1])) + 1
        # The least clearance anywhere under the footprint, with its centre
        # at each pixel: an erosion by the footprint's own shape.
        under = cv2.erode(clear, np.ones((kh, kw), np.uint8), anchor=(x0, y0),
                          borderType=cv2.BORDER_CONSTANT, borderValue=0)
        # Where nothing is clear, the tray itself at least -- it is where
        # the dice are thrown -- and the least of the track under the parked
        # row: the share of the footprint over road. Failing even that, the
        # least covered. Each tier scores below the one before.
        covered = cv2.boxFilter(blocked.astype(np.float32), -1, (kw, kh), anchor=(x0, y0), normalize=True,
                                borderType=cv2.BORDER_CONSTANT)
        tray_ok = cv2.erode(clear, np.ones((tkh, tkw), np.uint8), anchor=(tx0, ty0),
                            borderType=cv2.BORDER_CONSTANT, borderValue=0) > 0
        score = np.where(under > 0, np.minimum(under, CLEAR) * 1000 - to_middle,
                         np.where(tray_ok, -1000 * covered - 1000, -1000 * covered - 3000))
        score[~over_logo] = -np.inf
        # Wholly on the board.
        score[:, :x0] = score[:y0, :] = -np.inf
        score[:, w - (kw - x0) + 1:] = score[h - (kh - y0) + 1:, :] = -np.inf
        i = np.unravel_index(int(np.argmax(score)), score.shape)
        if best is None or score[i] > best[0]:
            best = (score[i], i[1] / SCALE, i[0] / SCALE, side,
                    float(under[i]) if under[i] > 0 else -float(covered[i]), (l, t, rt, b), unit)
    return best


def draw(track, spot, logo, path):
    _, x, y, side, _, (l, t, r, b), unit = spot
    ux, uy = unit[0] / SCALE, unit[1] / SCALE
    sys.path.insert(0, str(ROOT / "tools" / "extract"))
    from detect_track import board_image
    _, im = board_image(track["id"])
    for s in track["spaces"]:
        cv2.circle(im, tuple(int(v) for v in s["pos"]), 4, (255, 0, 255), -1)
    p0 = (int(x + l * ux), int(y + t * uy))
    p1 = (int(x + r * ux), int(y + b * uy))
    cv2.rectangle(im, p0, p1, (0, 255, 255), 4)
    if logo:
        cv2.rectangle(im, tuple(int(v) for v in logo[:2]), tuple(int(v) for v in logo[2:]), (255, 160, 0), 4)
    hw, hd = (TRAY_WIDTH / 2 + WALL) * ux, (TRAY_DEPTH / 2 + WALL) * uy
    cv2.rectangle(im, (int(x - hw), int(y - hd)), (int(x + hw), int(y + hd)), (0, 0, 255), 3)
    dx, dy = SIDES[side]
    cv2.arrowedLine(im, (int(x), int(y)), (int(x + dx * 6 * ux), int(y + dy * 6 * uy)), (0, 0, 255), 3)
    f = 1200 / im.shape[1]
    cv2.imwrite(str(path), cv2.resize(im, None, fx=f, fy=f, interpolation=cv2.INTER_AREA))


def main():
    force = "--force" in sys.argv
    ids = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not ids:
        ids = sorted(p.stem for p in TRACKS.glob("*.json") if p.stem.count(".") == 0)
    OUT.mkdir(parents=True, exist_ok=True)
    changed = 0
    for mid in ids:
        path = TRACKS / f"{mid}.json"
        track = json.loads(path.read_text(encoding="utf-8"))
        logo = logo_of(track)
        spot = find_spot(track, logo)
        _, x, y, side, room, *_ = spot
        draw(track, spot, logo, OUT / f"{mid}_dice.png")
        keep = track.get("dice") and not force
        how = "%.1f units clear" % room if room > 0 else "%d%% over the track" % round(-100 * room)
        print("%-12s (%4d, %4d) %-5s  %s%s%s" % (
            mid, x, y, side, how, "" if logo else "  (no logo found: the board's middle)", "  -- has a spot already, left as it is (--force)" if keep else ""))
        if keep:
            continue
        track["dice"] = [int(round(x)), int(round(y))]
        track["dice_side"] = side
        # Kept beside `dice`, where the track format lists them.
        order = list(track)
        order.remove("dice_side")
        order.insert(order.index("dice") + 1, "dice_side")
        track = {k: track[k] for k in order}
        path.write_text(json.dumps(track, indent=1), encoding="utf-8")
        changed += 1
    if changed:
        import gen_tracks
        gen_tracks.main()
    print("-> out/<id>_dice.png; move one in the game with the board's right-click menu")
    return 0


if __name__ == "__main__":
    sys.exit(main())
