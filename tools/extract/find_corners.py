"""Find the corners on a track board: which spaces lie inside each one.

A corner is the stretch of road between two red lines painted across it (see
the rulebook: a car must stop "within the limits of the corner"). Cutting the
road along every red line leaves a ring of pieces, corners and straights in
turn; the piece holding the start/finish band is a straight, which settles
which of the two alternating sets are the corners. Each space then takes the
corner of the piece its centre lies in.

This only adds corner data -- positions, lanes and links are left as they are
-- so it runs on hand-edited track files too. Stop counts are kept from the
file where it already has them.

Stop counts are printed on the board in the corner flags, which is a job for
eyes rather than code: every corner is cropped to out/_work/<id>_flag_<n>.png
with its flag in view, and the counts read off them are passed back in.

Writes out/<id>_7_corners.png: each corner shaded, its spaces dotted and
numbered, straights left grey.

The flag also prints the longest and shortest way through the corner, in
green and red; passing those in as --paths checks the spaces found against
what the board says.

Run:  python tools/extract/find_corners.py FDMonaco
      python tools/extract/find_corners.py FDMonaco --stops 1,3,2 --paths 7/3,18/8,13/8
"""
import json
import pathlib
import sys
from collections import Counter

import cv2
import numpy as np

from detect_track import OUT, board_image, corner_lines, racing_line
from find_grid import track_only, track_proper

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORK = OUT / "_work"

# Red lines are two or three pixels wide with soft edges; cut this much either
# side so no piece of road leaks round the end of one.
CUT = 3
# Pieces smaller than this are scraps at a line's ragged ends, not road.
MIN_PIECE = 2000
# How far to shrink the road before cutting it, in pixels.
SHRINK = 7

SHADES = [(60, 60, 230), (40, 170, 250), (60, 200, 60), (230, 160, 40), (200, 70, 200),
          (40, 220, 220), (130, 90, 230), (90, 160, 120)]


def red_lines(im, main):
    """The red lines across the track proper. Red elsewhere -- the pit
    garages -- comes out as short scraps, far smaller than a line spanning
    the road."""
    red = corner_lines(im) & cv2.dilate(main, np.ones((9, 9), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(red, connectivity=8)
    sizes = st[1:, cv2.CC_STAT_AREA]
    keep = [i + 1 for i, a in enumerate(sizes) if a >= 0.5 * np.median(sizes)]
    return np.isin(lab, keep).astype(np.uint8), len(keep)


def pieces(im, main):
    """The road cut along its red lines: a label image and the lines.

    The road is shrunk a little first: where the track doubles back on
    itself, as at a hairpin, the two sides can touch through a gap in the
    kerb and would join round the end of a line."""
    red, n_lines = red_lines(im, main)
    cut = cv2.dilate(red, np.ones((2 * CUT + 1, 2 * CUT + 1), np.uint8))
    inner = cv2.erode(main, np.ones((2 * SHRINK + 1, 2 * SHRINK + 1), np.uint8))
    road = (inner > 0) & (cut == 0)
    n, lab, st, _ = cv2.connectedComponentsWithStats(road.astype(np.uint8), connectivity=4)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] < MIN_PIECE:
            lab[lab == i] = 0
    return lab, n_lines


def piece_at(lab, x, y, reach=12):
    """The piece under (x, y), or the nearest within `reach` pixels."""
    xi, yi = int(round(x)), int(round(y))
    if 0 <= yi < lab.shape[0] and 0 <= xi < lab.shape[1] and lab[yi, xi]:
        return int(lab[yi, xi])
    y0, x0 = max(yi - reach, 0), max(xi - reach, 0)
    win = lab[y0:yi + reach + 1, x0:xi + reach + 1]
    pts = np.argwhere(win > 0)
    if not len(pts):
        return 0
    d = ((pts[:, 0] + y0 - yi) ** 2 + (pts[:, 1] + x0 - xi) ** 2)
    py, px = pts[int(np.argmin(d))]
    return int(win[py, px])


def finish_piece(im, lab):
    """The piece with the start/finish band: the one with most bright white
    squares printed on the asphalt."""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)
    white = (hsv[..., 2] > 215) & (hsv[..., 1] < 35) & (lab > 0)
    counts = np.bincount(lab[white], minlength=lab.max() + 1)
    return int(np.argmax(counts[1:])) + 1


def running_order(spaces, where):
    """Pieces in the order a car meets them, following the links."""
    ahead = {}
    for s in spaces:
        a = where[s["id"]]
        for n in s["next"]:
            b = where.get(n, 0)
            if a and b and b != a:
                ahead.setdefault(a, Counter())[b] += 1
    return {a: c.most_common(1)[0][0] for a, c in ahead.items()}


def flag_crop(im, spaces, members, pad=170):
    """A corner and the ground around it, where its flag is printed."""
    pts = np.array([s["pos"] for s in spaces if s["id"] in members])
    x0, y0 = np.maximum(pts.min(0) - pad, 0).astype(int)
    x1, y1 = np.minimum(pts.max(0) + pad, [im.shape[1], im.shape[0]]).astype(int)
    return im[y0:y1, x0:x1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    map_id = args[0] if args else "FDMonaco"
    stops = []
    if "--stops" in sys.argv:
        stops = [int(v) for v in sys.argv[sys.argv.index("--stops") + 1].split(",")]
    paths = []
    if "--paths" in sys.argv:
        paths = [[int(v) for v in pair.split("/")]
                 for pair in sys.argv[sys.argv.index("--paths") + 1].split(",")]
    path = ROOT / "tracks" / f"{map_id}.json"
    track = json.loads(path.read_text(encoding="utf-8"))
    info, im = board_image(map_id)
    _, road = track_only(im)
    line, _, width = racing_line(im)
    main_road = track_proper(road, line, width)

    lab, n_lines = pieces(im, main_road)
    spaces = track["spaces"]
    where = {s["id"]: piece_at(lab, *s["pos"]) for s in spaces}
    used = sorted(set(where.values()) - {0})
    print("1. %d red lines cut the road into %d pieces holding spaces" % (n_lines, len(used)))
    lost = [s["id"] for s in spaces if not where[s["id"]]]
    if lost:
        print("   spaces on no piece (left out of every corner): %s" % lost)

    # Walk the ring from the start/finish straight.
    ahead = running_order(spaces, where)
    start = finish_piece(im, lab)
    ring, p = [start], ahead.get(start)
    while p and p != start and p not in ring:
        ring.append(p)
        p = ahead.get(p)
    if p != start or len(ring) != len(used) or len(ring) % 2:
        sys.exit("the pieces do not make one ring of corners and straights (%d in the ring, %d with "
                 "spaces, ring closes: %s) -- check out/%s_7_corners.png" % (len(ring), len(used), p == start, map_id))

    corner_of = {piece: i // 2 + 1 for i, piece in enumerate(ring) if i % 2 == 1}
    old = {c["id"]: c for c in track.get("corners", [])}
    corners = []
    for piece, cid in sorted(corner_of.items(), key=lambda kv: kv[1]):
        members = [s["id"] for s in spaces if where[s["id"]] == piece]
        was = old.get(cid, {})
        by_lane = Counter(s["lane"] for s in spaces if s["id"] in set(members))
        c = {"id": cid,
             "stops": stops[cid - 1] if cid <= len(stops) else was.get("stops"),
             "spaces": len(members),
             "lanes": [by_lane.get(l, 0) for l in sorted(by_lane)]}
        if cid <= len(paths):
            c["long"], c["short"] = paths[cid - 1]
        elif was.get("long"):
            c["long"], c["short"] = was["long"], was["short"]
        corners.append(c)
        cv2.imwrite(str(WORK / f"{map_id}_flag_{cid}.png"), flag_crop(im, spaces, set(members)))
    for s in spaces:
        s["corner"] = corner_of.get(where[s["id"]])
    print("2. %d corners, %d spaces inside them, %d on the straights"
          % (len(corners), sum(c["spaces"] for c in corners), sum(1 for s in spaces if s["corner"] is None)))
    for c in corners:
        # The board prints the shortest way through a corner, which is the
        # fewest spaces any one lane takes: a lane shorter than that, or
        # longer than the longest way, means spaces are missing or strayed.
        note = ""
        if c.get("short") and (min(c["lanes"]) < c["short"] or max(c["lanes"]) > c["long"]):
            note = "  <- lanes %s, but the flag says %d to %d" % (c["lanes"], c["short"], c["long"])
        print("   corner %d: %d spaces, %s stops%s" % (c["id"], c["spaces"],
              c["stops"] if c["stops"] is not None else "unread", note))
    if not stops:
        print("   flags cropped to out/_work/%s_flag_*.png -- read them and rerun with "
              "--stops a,b,c,..." % map_id)

    vis = cv2.addWeighted(im, 0.45, np.full_like(im, 255), 0.55, 0)
    for piece, cid in corner_of.items():
        tint = np.array(SHADES[(cid - 1) % len(SHADES)], np.uint8)
        vis[lab == piece] = (0.5 * vis[lab == piece] + 0.5 * tint).astype(np.uint8)
    vis[red_lines(im, main_road)[0] > 0] = (0, 0, 200)
    for s in spaces:
        c = tuple(int(round(v)) for v in s["pos"])
        cv2.circle(vis, c, 3, (0, 0, 0) if s["corner"] else (150, 150, 150), -1)
    for piece, cid in corner_of.items():
        ys, xs = np.nonzero(lab == piece)
        at = (int(xs.mean()) - 8, int(ys.mean()) + 8)
        cv2.putText(vis, str(cid), at, cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 4)
        cv2.putText(vis, str(cid), at, cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 0), 2)
    out = OUT / f"{map_id}_7_corners.png"
    cv2.imwrite(str(out), vis)
    print("   ->", out.relative_to(ROOT))

    track["corners"] = corners
    path.write_text(json.dumps(track, indent=1), encoding="utf-8")
    print("3. corners written to", path.relative_to(ROOT))
    import gen_tracks
    gen_tracks.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
