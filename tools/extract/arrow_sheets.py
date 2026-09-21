"""Close-ups of every space with an arrow, for reading the arrows by eye.

The detector in find_arrows.py finds arrows well but miscounts their heads
often enough to matter, and a head is what says whether a space forks. So the
forks are read by eye instead, from these sheets, into tracks/<id>.arrows.json.

Each tile is one space: a magenta dot on it, a red ring on the next space in
its lane and a blue ring on each space across a lane it could move to. Read
whether the arrow on the dot has one head (straight on) or two, and if two,
which blue ring the second points at -- the lane numbered one lower (-1) or
one higher (+1). Tiles run corner by corner, lane by lane.

Writes out/_work/<id>_sheet_NN.png, nine spaces to a sheet.

Run:  python tools/extract/arrow_sheets.py FDMonaco
"""
import json
import pathlib
import sys

import cv2
import numpy as np

from detect_track import OUT, board_image
import find_arrows as fa

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORK = OUT / "_work"

HALF = 62        # pixels of board either side of the space
ZOOM = 4
PER_SHEET = 9
COLS = 3


def tile(im, track, pos, cell, s):
    x, y = [int(v) for v in s["pos"]]
    c = cv2.resize(im[y - HALF:y + HALF, x - HALF:x + HALF].copy(), (HALF * 2 * ZOOM,) * 2,
                   interpolation=cv2.INTER_CUBIC)
    corner = np.array([x - HALF, y - HALF], float)
    for lane, n in fa.ahead_of(s, track["spaces"], pos, cell).items():
        p = tuple(((np.array(n["pos"], float) - corner) * ZOOM).astype(int))
        col = (0, 0, 230) if lane == s["lane"] else (230, 120, 0)
        cv2.circle(c, p, 9, col, 2)
        for width, colour in ((4, (255, 255, 255)), (2, col)):
            cv2.putText(c, str(n["id"]), (p[0] + 11, p[1] + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.55, colour, width)
    cv2.circle(c, (HALF * ZOOM, HALF * ZOOM), 6, (255, 0, 255), -1)
    for width, colour in ((5, (255, 255, 255)), (2, (0, 0, 0))):
        cv2.putText(c, "%d L%d" % (s["id"], s["lane"]), (8, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.85, colour, width)
    return c


def main():
    map_id = sys.argv[1] if len(sys.argv) > 1 else "FDMonaco"
    track = json.loads((ROOT / "tracks" / f"{map_id}.json").read_text(encoding="utf-8"))
    info, im = board_image(map_id)
    spaces = track["spaces"]
    pos = np.array([s["pos"] for s in spaces])
    cell = fa.cell_length(track)

    # Every corner space, and any other the detector saw an arrow on.
    lab, keep = fa.arrow_ink(im)
    arrows, _ = fa.read_arrows(lab, keep, spaces, cell)
    wanted = {s["id"] for s, _ in arrows} | {s["id"] for s in spaces if s["corner"]}
    order = sorted((s for s in spaces if s["id"] in wanted),
                   key=lambda s: (s["corner"] or 99, s["lane"], s["id"]))

    WORK.mkdir(parents=True, exist_ok=True)
    blank = np.full((HALF * 2 * ZOOM, HALF * 2 * ZOOM, 3), 255, np.uint8)
    for n, i in enumerate(range(0, len(order), PER_SHEET), 1):
        tiles = [tile(im, track, pos, cell, s) for s in order[i:i + PER_SHEET]]
        tiles += [blank] * (-len(tiles) % COLS)
        rows = [np.hstack(tiles[k:k + COLS]) for k in range(0, len(tiles), COLS)]
        path = WORK / f"{map_id}_sheet_{n:02d}.png"
        cv2.imwrite(str(path), np.vstack(rows))
    print("%d spaces on %d sheets -> %s" % (len(order), n, WORK.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
