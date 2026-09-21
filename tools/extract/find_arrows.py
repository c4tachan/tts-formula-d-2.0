"""Read the arrows printed on a track board: the legal moves out of a space.

An arrow shows which spaces a car may move to from the space it is printed
in, and a space can hold several, forking two or three ways. They are the
rules in the corners, where the plain "straight ahead or a lane either side"
does not hold.

Each arrow is found as a blob of bold dark ink on the road: the grid lines
are a pixel or two wide, arrows are drawn far heavier. Where it points is
read at its head rather than from end to end -- an arrow that curves, as at
the apex of a hairpin, finishes well round from where it started. A head is
two barbs meeting at an apex just ahead of them, and it points the way they
bisect; a blob with two heads is a fork and gives two links. No arrow points
backwards, which tells a head from the tail.

Two things about the board keep this honest. A move only ever goes to one of
three spaces: the next one along in this lane, or the next one along in the
lane either side. Every space leads on down its own lane whatever is printed
on it, and a single-headed arrow means exactly that move -- so only a second
or third head takes a car across a lane, and which way it leans says which
side it goes.

Links found this way are written as `fixed`, so the automatic relinking never
overrides them. Spaces with no arrow keep the links they have.

Writes out/<id>_8_arrows.png: every arrow with the link it was read as.

Run:  python tools/extract/find_arrows.py FDMonaco          what it finds
      python tools/extract/find_arrows.py FDMonaco --write   put it in the track file
"""
import json
import pathlib
import sys

import cv2
import numpy as np
from skimage.morphology import skeletonize

from detect_track import OUT, board_image, edge_line, racing_line, surface_mask
from find_grid import track_only, track_proper

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Ink darker than this share of the local asphalt, and at least this thick,
# is arrow rather than grid line.
DARK = 0.55
MIN_THICK = 2.0
MIN_AREA = 25
# How far back from an arrowhead to look for the junction where its barbs
# meet, as a share of a cell.
HEAD_REACH = 0.3
# Heads pointing within this many degrees of each other are one head read
# twice, not a fork.
ONE_HEAD = 25
# How far from a space's centre an arrow may sit, in cells.
NEAR = 0.8
# How far ahead to look for the next space along, in cells: about one, but
# the lanes either side sit further off round a corner.
STEP = 1.6


def arrow_ink(im):
    """Bold dark marks on the road: the arrows, and nothing much else."""
    track, road = track_only(im)
    line, _, width = racing_line(im)
    main = track_proper(road, line, width)
    gray = cv2.cvtColor(track, cv2.COLOR_BGR2GRAY)
    bg = cv2.medianBlur(gray, 21).astype(np.float32)
    ink = (((bg - gray.astype(np.float32)) > 5) & (road > 0)).astype(np.uint8)
    rel = gray.astype(np.float32) / np.maximum(bg, 1)
    thick = cv2.distanceTransform(ink, cv2.DIST_L2, 3)
    # The dark line along the track limit is as bold as an arrow, and where an
    # arrow reaches the kerb the two would join into one blob.
    limit = cv2.dilate(edge_line(im, surface_mask(im)).astype(np.uint8), np.ones((3, 3), np.uint8))
    core = ((rel < DARK) & (ink > 0) & (limit == 0)).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(core, 8)
    keep = [i for i in range(1, n)
            if st[i, cv2.CC_STAT_AREA] >= MIN_AREA and thick[lab == i].max() >= MIN_THICK
            and main[int(cen[i][1]), int(cen[i][0])] > 0]
    return lab, keep


def skeleton(mask):
    """The blob thinned to a line, with its ends and its junctions."""
    skel = skeletonize(mask > 0).astype(np.uint8)
    nb = cv2.filter2D(skel, -1, np.ones((3, 3), np.uint8), borderType=cv2.BORDER_CONSTANT) - skel
    ends = np.argwhere((skel > 0) & (nb == 1))[:, ::-1].astype(float)
    nodes = np.argwhere((skel > 0) & (nb >= 3))[:, ::-1].astype(float)
    return skel, ends, nodes


def walk(skel, start, nodes, limit):
    """The line inwards from one end, as far as `limit` pixels or the first
    junction. Returns the pixels walked and the junction, if it reached one."""
    h, w = skel.shape
    seen = {(int(start[0]), int(start[1]))}
    path, at = [start], start
    for _ in range(limit):
        step = None
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                q = (int(at[0]) + dx, int(at[1]) + dy)
                if (dx or dy) and 0 <= q[1] < h and 0 <= q[0] < w \
                        and skel[q[1], q[0]] and q not in seen:
                    step = q
                    break
            if step:
                break
        if not step:
            break
        seen.add(step)
        at = np.array(step, float)
        path.append(at)
        if len(nodes) and min(np.hypot(*(at - n)) for n in nodes) < 1.5:
            return path, at
    return path, None


def one_head(heads, spread=ONE_HEAD):
    """Heads pointing much the same way taken as one: an arrowhead read once
    per barb rather than a fork."""
    out = []
    for p, d in heads:
        a = np.degrees(np.arctan2(d[1], d[0]))
        for g in out:
            m = np.mean([x[1] for x in g], axis=0)
            b = np.degrees(np.arctan2(m[1], m[0]))
            if abs((a - b + 180) % 360 - 180) <= spread:
                g.append((p, d))
                break
        else:
            out.append([(p, d)])
    return [(np.mean([x[0] for x in g], axis=0), np.mean([x[1] for x in g], axis=0))
            for g in out]


def heads_of(mask, ahead, cell):
    """Where one arrow points, as (tip, direction) per head.

    A junction with two or more line ends running into it, sitting ahead of
    them, is an arrowhead: those ends are its barbs and it points the way
    they bisect. An end with no such junction is read from the last few
    pixels of the line itself. Either way the reading is local, so how the
    arrow curved on its way there does not come into it.
    """
    skel, ends, nodes = skeleton(mask)
    if not len(ends):
        return []
    mid = np.argwhere(mask)[:, ::-1].astype(float).mean(0)
    reach = max(int(HEAD_REACH * cell), 4)
    barbs, tangent = {}, {}
    for e in ends:
        path, node = walk(skel, e, nodes, reach)
        tangent[tuple(e)] = e - path[min(len(path) - 1, max(reach // 2, 2))]
        if node is not None:
            barbs.setdefault(tuple(node), []).append(e)

    heads, spoken = [], set()
    for node, ee in barbs.items():
        apex = np.array(node, float)
        if len(ee) >= 2 and np.dot(apex - np.mean(ee, axis=0), ahead) > 0:
            heads.append((apex, apex - np.mean(ee, axis=0)))
            spoken.update(tuple(e) for e in ee)
    for e in ends:
        if tuple(e) not in spoken and np.dot(e - mid, ahead) > 0:
            heads.append((e, tangent[tuple(e)]))
    return one_head([(p, d) for p, d in heads
                     if np.hypot(*d) > 1e-6 and np.dot(d, ahead) > 0])


def facing(space):
    a = np.radians(space["rot"])
    return np.array([np.cos(a), np.sin(a)])


def read_arrows(lab, keep, spaces, cell):
    """Every blob as (source space, [(tip, direction)])."""
    pos = np.array([s["pos"] for s in spaces])
    out, misses = [], []
    for i in keep:
        ys, xs = np.nonzero(lab == i)
        here = np.array([xs.mean(), ys.mean()])
        d = np.hypot(*(pos - here).T)
        src = spaces[int(np.argmin(d))]
        if d.min() > NEAR * cell:
            misses.append(("arrow on no space", here, None))
            continue
        box = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
        corner = np.array([box[1].start, box[0].start], float)
        heads = heads_of(lab[box] == i, facing(src), cell)
        if not heads:
            misses.append(("arrow too small to read", here, src["id"]))
            continue
        out.append((src, [(p + corner, d) for p, d in heads]))
    return out, misses


def ahead_of(src, spaces, pos, cell):
    """The three spaces a move can reach: the next one along in this lane and
    in the lane either side, each the nearest in its lane to a point one cell
    in front."""
    front = np.array(src["pos"], float) + facing(src) * cell
    out = {}
    for lane in (src["lane"] - 1, src["lane"], src["lane"] + 1):
        best, best_d = None, STEP * cell
        for j, s in enumerate(spaces):
            if s is src or s["lane"] != lane:
                continue
            if np.dot(pos[j] - src["pos"], facing(src)) <= 0:
                continue                    # behind: no move goes backwards
            d = float(np.hypot(*(pos[j] - front)))
            if d < best_d:
                best, best_d = s, d
        if best is not None:
            out[lane] = best
    return out


def side_of(a, b):
    """Which side of `a` the direction `b` lies: -1, 0 or 1. (NumPy 2 has no
    2-D cross product, so this is its z component.)"""
    z = a[0] * b[1] - a[1] * b[0]
    return 0 if abs(z) < 1e-9 else (1 if z > 0 else -1)


def links(track, arrows, cell):
    """Each arrow as the links it stands for: (source, target).

    An arrow with one head means the move it is printed on: on down the same
    lane. Only a second or third head takes a car across a lane, and which
    way it leans says which side, so a head is never matched against three
    spaces by angle alone.
    """
    spaces = track["spaces"]
    pos = np.array([s["pos"] for s in spaces])
    out, misses = [], []
    for src, heads in arrows:
        choices = ahead_of(src, spaces, pos, cell)
        on = choices.get(src["lane"])
        if on is None:
            misses.append(("nothing ahead in this lane", np.array(src["pos"], float), src["id"]))
            continue
        out.append((src["id"], on["id"]))       # always: straight on down the lane
        straight = np.array(on["pos"], float) - src["pos"]
        straight = straight / np.hypot(*straight)

        def turn(head):
            d = head[1] / np.hypot(*head[1])
            return abs(np.degrees(np.arctan2(side_of(straight, d), float(np.dot(straight, d)))))

        # The head most nearly in line with the lane is that same move again.
        for tip, point in sorted(heads, key=turn)[1:]:
            d = point / np.hypot(*point)
            want = side_of(straight, d)
            taken = None
            for lane, s in choices.items():
                if lane == src["lane"]:
                    continue
                v = np.array(s["pos"], float) - src["pos"]
                if side_of(straight, v / np.hypot(*v)) == want:
                    taken = s
            if taken is None:
                # Nothing that side: on the innermost or outermost lane this
                # is a barb read as a head of its own, not a move.
                misses.append(("a head leans off the track", tip, src["id"]))
            else:
                out.append((src["id"], taken["id"]))
    return sorted(set(out)), misses


def cell_length(track):
    """The step from one space to the next along a lane, in pixels."""
    pos = {s["id"]: np.array(s["pos"], float) for s in track["spaces"]}
    lane = {s["id"]: s["lane"] for s in track["spaces"]}
    steps = [np.hypot(*(pos[n] - pos[s["id"]])) for s in track["spaces"]
             for n in s["next"] if lane[n] == s["lane"]]
    return float(np.median(steps))


def draw(im, lab, keep, spaces, found, misses, path):
    """The board with every arrow shaded and the link read from it drawn on."""
    vis = cv2.addWeighted(im, 0.5, np.full_like(im, 255), 0.5, 0)
    for i in keep:
        vis[lab == i] = (150, 150, 150)
    for src, dst in found:
        a = np.array(spaces[src]["pos"], float)
        b = np.array(spaces[dst]["pos"], float)
        q = a + (b - a) * 0.55
        cv2.arrowedLine(vis, tuple(int(v) for v in a), tuple(int(v) for v in q),
                        (0, 0, 220), 1, tipLength=0.3)
    for _, at, _ in misses:
        cv2.circle(vis, tuple(int(v) for v in at), 6, (220, 0, 220), 2)
    cv2.imwrite(str(path), vis)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    map_id = args[0] if args else "FDMonaco"
    path = ROOT / "tracks" / f"{map_id}.json"
    track = json.loads(path.read_text(encoding="utf-8"))
    info, im = board_image(map_id)

    lab, keep = arrow_ink(im)
    cell = cell_length(track)
    arrows, misses = read_arrows(lab, keep, track["spaces"], cell)
    forks = sum(1 for _, heads in arrows if len(heads) > 1)
    print("1. %d arrows on the road, %d of them forking" % (len(arrows), forks))

    found, more = links(track, arrows, cell)
    misses += more
    by_space = {}
    for src, dst in found:
        by_space.setdefault(src, set()).add(dst)
    print("2. %d links on %d spaces%s" % (len(found), len(by_space),
          ("; %d arrows unread" % len(misses)) if misses else ""))
    for why, at, sid in misses[:10]:
        print("   %s at (%d, %d)%s" % (why, at[0], at[1],
              "" if sid is None else " near space %d" % sid))

    spaces = {s["id"]: s for s in track["spaces"]}
    corner = {s["id"] for s in track["spaces"] if s["corner"]}
    same = sum(1 for sid, dst in by_space.items() if set(spaces[sid]["next"]) == dst)
    print("3. %d spaces link as they already do, %d differ; %d corner space(s) have no arrow"
          % (same, len(by_space) - same, len(corner - set(by_space))))

    draw(im, lab, keep, spaces, found, misses, OUT / f"{map_id}_8_arrows.png")
    print("   -> tools/extract/out/%s_8_arrows.png" % map_id)

    if "--write" in sys.argv:
        for sid, dst in by_space.items():
            spaces[sid]["next"] = sorted(dst)
            spaces[sid]["fixed"] = True
        path.write_text(json.dumps(track, indent=1), encoding="utf-8")
        print("4. written to", path.relative_to(ROOT))
        sys.path.insert(0, str(ROOT / "tools" / "extract"))
        import gen_tracks
        gen_tracks.main()
    else:
        print("   nothing written; rerun with --write to put these links in the track file")
    return 0


if __name__ == "__main__":
    sys.exit(main())
