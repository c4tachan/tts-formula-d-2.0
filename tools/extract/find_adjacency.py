"""Which spaces touch which: every neighbour of a space, arrows or not.

The links in a track file are the legal moves, one way and ahead only. This
is the other question -- which spaces border one another, ahead, behind,
beside or diagonally -- for rules about cars next to each other, such as
collisions.

The spaces are taken from tracks/<id>.json as edited, not re-detected. Each
pixel of road goes to its nearest space, within a cell's reach, and two
spaces are neighbours when the areas they get share an edge -- a border a
corner-point touch never makes. Three things keep that honest:

  - Consecutive spaces in a lane always touch. In a staggered grid the
    spaces either side pinch the border between them down to nothing, so
    the next space along the lane (from the track's own links) is added
    whatever the border says.
  - A neighbour must be reachable without crossing a kerb or the white
    track limit, or the two legs of a hairpin come out joined. A kerb is a
    long run of white, or red stripes beside white -- the red corner lines
    on the asphalt have no white beside them, and the white paint on it
    (grid boxes, numbers) is too short.
  - The chequered flag is white too, and is not a kerb.

Writes tracks/<id>.adjacency.json, beside the track file, and
out/<id>_adjacency.png to check by eye: a dot per space coloured by lane
(orange inside, green middle, blue outside), a line per pair of neighbours,
and a magenta ring round any space left with none.

Run:  python tools/extract/find_adjacency.py FDMonaco
"""
import json
import sys

import cv2
import numpy as np
from scipy.spatial import cKDTree

from detect_track import OUT, ROOT, board_image, keep_long
from find_grid import paint_out_arrows, paint_out_flag, track_only

REACH = 40    # px: how far from its centre a space's area reaches
EDGE = 12     # px of shared border that make a real edge, not a corner touch
LANE_COLOURS = {1: (0, 140, 255), 2: (0, 170, 0), 3: (220, 90, 0)}


def space_areas(road, pos):
    """Each road pixel labelled with its nearest space (1-based), 0 elsewhere."""
    ys, xs = np.nonzero(road)
    d, nearest = cKDTree(pos).query(np.c_[xs, ys])
    ok = d <= REACH
    labels = np.zeros(road.shape, np.int32)
    labels[ys[ok], xs[ok]] = nearest[ok] + 1
    return labels


def borders(labels):
    """{(a, b): length} of the border between each pair of touching areas."""
    H, W = labels.shape
    out = {}
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = labels[1:-1, 1:-1]
        b = labels[1 + dy:H - 1 + dy, 1 + dx:W - 1 + dx]
        m = (a > 0) & (b > 0) & (a != b)
        pairs, counts = np.unique(np.stack([np.minimum(a[m], b[m]), np.maximum(a[m], b[m])], 1),
                                  axis=0, return_counts=True)
        for (p, q), c in zip(pairs.tolist(), counts.tolist()):
            out[(p, q)] = out.get((p, q), 0) + c
    return out


def kerbs(im, road, flag):
    """Where a car cannot cross: off the road, the white limit and the kerbs."""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV).astype(int)
    white = (hsv[..., 1] < 45) & (hsv[..., 2] >= 200)
    red = (hsv[..., 1] > 120) & ((hsv[..., 0] < 10) | (hsv[..., 0] > 170)) & (hsv[..., 2] > 120)
    k5 = np.ones((5, 5), np.uint8)
    striped = (cv2.dilate(red.astype(np.uint8), k5) > 0) & (cv2.dilate(white.astype(np.uint8), k5) > 0)
    white &= cv2.dilate(flag.astype(np.uint8), np.ones((9, 9), np.uint8)) == 0
    barrier = (road == 0) | (keep_long(white, 60) > 0) | striped
    return cv2.morphologyEx(barrier.astype(np.uint8), cv2.MORPH_OPEN, np.ones((2, 2), np.uint8)) > 0


def crosses(barrier, a, b):
    """Whether the straight line between two space centres crosses a barrier."""
    t = np.linspace(0, 1, int(np.hypot(*(b - a))) + 1)
    x = np.round(a[0] + (b[0] - a[0]) * t).astype(int)
    y = np.round(a[1] + (b[1] - a[1]) * t).astype(int)
    return barrier[y, x].sum() > 2


def neighbours(spaces, im):
    """The pairs of spaces that touch, as sorted (id, id) tuples."""
    pos = np.array([s["pos"] for s in spaces], float)
    track, road = track_only(im)
    clean, _ = paint_out_arrows(track, road)
    _, flag = paint_out_flag(clean, road)
    barrier = kerbs(im, road, flag)
    pairs, cut = set(), []
    for (p, q), length in borders(space_areas(road, pos)).items():
        if length < EDGE:
            continue
        a, b = spaces[p - 1]["id"], spaces[q - 1]["id"]
        if crosses(barrier, pos[p - 1], pos[q - 1]):
            cut.append((a, b))
        else:
            pairs.add(tuple(sorted((a, b))))
    lane = {s["id"]: s["lane"] for s in spaces}
    added = 0
    for s in spaces:
        for n in s["next"]:
            if lane.get(n) == s["lane"] and tuple(sorted((s["id"], n))) not in pairs:
                pairs.add(tuple(sorted((s["id"], n))))
                added += 1
    return pairs, cut, added


def draw(im, spaces, pairs, scale=2):
    """The board, faded, with a dot per space and a line per pair of neighbours."""
    H, W = im.shape[:2]
    vis = cv2.addWeighted(im, 0.55, np.full_like(im, 255), 0.45, 0)
    vis = cv2.resize(vis, (W * scale, H * scale), interpolation=cv2.INTER_CUBIC)
    at = {s["id"]: tuple(int(round(v * scale)) for v in s["pos"]) for s in spaces}
    linked = set()
    for a, b in sorted(pairs):
        cv2.line(vis, at[a], at[b], (30, 30, 200), 2, cv2.LINE_AA)
        linked.update((a, b))
    for s in spaces:
        c = at[s["id"]]
        cv2.circle(vis, c, 7, LANE_COLOURS.get(s["lane"], (0, 0, 0)), -1, cv2.LINE_AA)
        cv2.circle(vis, c, 7, (0, 0, 0), 1, cv2.LINE_AA)
        if s["id"] not in linked:
            cv2.circle(vis, c, 14, (255, 0, 255), 2, cv2.LINE_AA)
    return vis


def main():
    map_id = sys.argv[1] if len(sys.argv) > 1 else "FDMonaco"
    track_path = ROOT / "tracks" / f"{map_id}.json"
    if not track_path.exists():
        sys.exit(f"no track file {track_path.relative_to(ROOT)}")
    spaces = json.loads(track_path.read_text(encoding="utf-8"))["spaces"]
    _, im = board_image(map_id)

    pairs, cut, added = neighbours(spaces, im)
    degree = {s["id"]: 0 for s in spaces}
    for a, b in pairs:
        degree[a] += 1
        degree[b] += 1
    print("%d spaces, %d pairs of neighbours; %d across a kerb left out; %d lane steps added"
          % (len(spaces), len(pairs), len(cut), added))
    print("neighbours per space: %s" % {k: int(v) for k, v in enumerate(np.bincount(list(degree.values()))) if v})
    alone = [k for k, v in degree.items() if not v]
    if alone:
        print("no neighbours: " + ", ".join(alone))

    out = ROOT / "tracks" / f"{map_id}.adjacency.json"
    out.write_text(json.dumps({
        "about": "Which spaces touch which, ignoring the arrows: every pair that shares an edge "
                 "on the board, in any direction. Written by tools/extract/find_adjacency.py "
                 "from the spaces in %s.json -- rerun it after editing them." % map_id,
        "pairs": [list(p) for p in sorted(pairs)],
    }, indent=1), encoding="utf-8")
    print("-> " + str(out.relative_to(ROOT)))

    png = OUT / f"{map_id}_adjacency.png"
    cv2.imwrite(str(png), draw(im, spaces, pairs))
    print("-> " + str(png.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
