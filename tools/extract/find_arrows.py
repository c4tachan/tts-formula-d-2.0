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

The links a whole corner makes obey rules of their own, which settle the
cases a single arrow leaves in doubt: a space forks to one side or the other
and never both, and within one lane's run through a corner the links across a
lane neither double up nor cross each other.

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
import functools
import json
import pathlib
import sys
from collections import Counter

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
# twice, not a fork; so are heads closer together than this share of a cell.
ONE_HEAD = 25
APART = 0.16
# How far from a space's centre an arrow may sit, in cells.
NEAR = 0.8
# How far ahead to look for the next space along, in cells: about one, but
# the lanes either side sit further off round a corner.
STEP = 1.6
# How far in front of a space another has to sit to be a move at all: one
# squarely alongside is not one, whichever way an arrow leans. Lanes are not
# in step, so the space across from one can be only just in front of it.
MIN_AHEAD = 0.12
# And how far away it may be and still be touching.
TOUCHING = 1.6


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


def one_head(heads, cell, spread=ONE_HEAD):
    """Heads taken as one where they are really the same arrowhead read twice:
    pointing much the same way, or sitting on top of each other. The two heads
    of a fork are drawn at opposite corners of a space, half a cell or more
    apart, while a barb mistaken for a head of its own is right beside the
    apex it belongs to."""
    out = []
    for p, d in heads:
        a = np.degrees(np.arctan2(d[1], d[0]))
        for g in out:
            m = np.mean([x[1] for x in g], axis=0)
            b = np.degrees(np.arctan2(m[1], m[0]))
            close = min(float(np.hypot(*(q - p))) for q, _ in g) <= APART * cell
            if close or abs((a - b + 180) % 360 - 180) <= spread:
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
                     if np.hypot(*d) > 1e-6 and np.dot(d, ahead) > 0], cell)


def facing(space):
    a = np.radians(space["rot"])
    return np.array([np.cos(a), np.sin(a)])


def read_arrows(lab, keep, spaces, cell):
    """Every blob as (source space, [(tip, direction)])."""
    pos = np.array([s["pos"] for s in spaces])
    out, misses = {}, []
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
        # A forked arrow is often printed as two separate strokes, so heads
        # are gathered per space rather than per blob.
        out.setdefault(src["id"], (src, []))[1].extend((p + corner, d) for p, d in heads)
    return [(src, one_head(heads, cell)) for src, heads in out.values()], misses


def ahead_of(src, spaces, pos, cell):
    """The three spaces a move can reach: the next one along in this lane and
    in the lane either side, each the nearest in its lane to a point one cell
    in front.

    A space has to be both touching this one and properly in front of it to
    count: one squarely alongside is not a move, however close it sits, and
    nor is one further off than its neighbours.
    """
    ahead = facing(src)
    front = np.array(src["pos"], float) + ahead * cell
    out = {}
    for lane in (src["lane"] - 1, src["lane"], src["lane"] + 1):
        best, best_d = None, None
        for j, s in enumerate(spaces):
            if s is src or s["lane"] != lane:
                continue
            v = pos[j] - src["pos"]
            if np.dot(v, ahead) < MIN_AHEAD * cell:
                continue                    # alongside or behind: not a move
            far = float(np.hypot(*v))
            if far > TOUCHING * cell:
                continue                    # not touching: not a move either
            # Straight on is whatever sits a cell in front; across a lane it is
            # simply the closest, since the lanes are not in step -- the space
            # after that one is a cell further off again.
            d = float(np.hypot(*(pos[j] - front))) if lane == src["lane"] else far
            if best_d is None or d < best_d:
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
        out.append((src["id"], on["id"], 0.0))  # always: straight on down the lane
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
                v = np.array(taken["pos"], float) - src["pos"]
                u = v / np.hypot(*v)
                off = abs(np.degrees(np.arctan2(side_of(u, d), float(np.dot(u, d)))))
                out.append((src["id"], taken["id"], off))
    return out, misses


def lane_order(track):
    """How far along its own lane each space sits, by walking the lane round.

    Counting starts halfway down the longest straight: begun anywhere near a
    corner it would wrap round from last to first partway through one.
    """
    sp = {s["id"]: s for s in track["spaces"]}
    on = {}
    for s in track["spaces"]:
        for n in s["next"]:
            if sp[n]["lane"] == s["lane"]:
                on[s["id"]] = n
    order = {}
    for lane in sorted({s["lane"] for s in track["spaces"]}):
        at = min(s["id"] for s in track["spaces"] if s["lane"] == lane)
        loop = []
        while at is not None and at not in loop:
            loop.append(at)
            at = on.get(at)
        best, run, start = (0, 0), 0, 0
        for k, i in enumerate(loop + loop):
            run = run + 1 if not sp[i]["corner"] else 0
            if run > best[0]:
                best = (run, k)
        if best[0]:
            start = (best[1] - best[0] // 2) % len(loop)
        for k, i in enumerate(loop[start:] + loop[:start]):
            order[i] = k
    return order


def matching(sources, targets, order, cost):
    """Pair each source with a target so that no two share one and the pairs
    never cross: a car moving across a lane keeps its place in the queue.

    Pairs as many as it can, then keeps them as short as possible.
    """
    src = sorted(sources, key=lambda i: order.get(i, 0))
    dst = sorted(targets, key=lambda i: order.get(i, 0))

    @functools.lru_cache(None)
    def best(i, j):
        if i == len(src):
            return 0.0, ()
        out = best(i + 1, j)                     # this one goes unpaired
        for k in range(j, len(dst)):
            c = cost.get((src[i], dst[k]))
            if c is None:
                continue
            score, pairs = best(i + 1, k + 1)
            here = (score - 1000 + c, ((src[i], dst[k]),) + pairs)
            if here[0] < out[0]:
                out = here
        return out

    pairs = dict(best(0, 0)[1])
    best.cache_clear()
    return pairs


def tidy(track, found, cell):
    """Make the links obey the rules a board's arrows always follow.

    A space forks to one side or the other, never both -- where two heads
    disagree, the one squarest to what it points at wins, the other being a
    barb misread as a head. And within one lane's run the links across a lane
    neither double up nor cross, which settles which space each lands on when
    the head alone leaves it in doubt.
    """
    sp = {s["id"]: s for s in track["spaces"]}
    order = lane_order(track)
    same = {(a, b) for a, b, _ in found if sp[a]["lane"] == sp[b]["lane"]}
    cross = [(a, b, off) for a, b, off in found if sp[a]["lane"] != sp[b]["lane"]]

    # One way or the other: where a space has heads both ways, the one that
    # sits squarest to the space it points at is the arrow, and the other is a
    # barb read as a head.
    best = {}
    dropped = []
    for a, b, off in sorted(cross, key=lambda x: x[2]):
        if a in best:
            dropped.append((a, b, "forks the other way as well"))
        else:
            best[a] = (b, off)
    runs = {}
    for a, (b, _) in best.items():
        runs.setdefault((sp[a]["corner"], sp[a]["lane"], int(np.sign(sp[b]["lane"] - sp[a]["lane"]))),
                        []).append(a)
    fixed = []
    for (corner, lane, want), sources in runs.items():
        sources = sorted(set(sources), key=lambda i: order.get(i, 0))
        targets, cost = set(), {}
        for a in sources:
            for s in track["spaces"]:
                if s["lane"] != lane + want:
                    continue
                v = np.array(s["pos"], float) - sp[a]["pos"]
                far = float(np.hypot(*v))
                if np.dot(v, facing(sp[a])) < MIN_AHEAD * cell or far > TOUCHING * cell:
                    continue
                targets.add(s["id"])
                cost[(a, s["id"])] = far / cell
        pairs = matching(sources, targets, order, cost)
        for a in sources:
            if a in pairs:
                fixed.append((a, pairs[a]))
            else:
                dropped.append((a, None, "no space left for it across the lane"))
    return sorted(same | set(fixed)), dropped


def from_reading(track, reading, cell):
    """Links from a reading of the board by eye (tracks/<id>.arrows.json).

    The reading says only which spaces fork and which way; the rules say
    where to. Every space goes on down its own lane, and the forks out of one
    lane's run through a corner are paired with the lane beside it so that
    none double up or cross -- which is exactly how the board is printed.
    """
    spaces = track["spaces"]
    sp = {s["id"]: s for s in spaces}
    pos = np.array([s["pos"] for s in spaces])
    order = lane_order(track)
    out, dropped = set(), []
    runs = {}
    arrowed = {(int(k) if k.isdigit() else k): v for k, v in reading["forks"].items()}
    arrowed.update({i: 0 for i in reading.get("approach", [])})
    for i, side in arrowed.items():
        src = sp[i]
        on = ahead_of(src, spaces, pos, cell).get(src["lane"])
        if on is not None:
            out.add((i, on["id"]))
        if side:
            runs.setdefault((src["corner"], src["lane"], side), []).append(i)
    for (corner, lane, side), sources in runs.items():
        targets, cost = set(), {}
        for a in sources:
            for s in spaces:
                if s["lane"] != lane + side:
                    continue
                v = np.array(s["pos"], float) - sp[a]["pos"]
                far = float(np.hypot(*v))
                if np.dot(v, facing(sp[a])) < MIN_AHEAD * cell or far > TOUCHING * cell:
                    continue
                targets.add(s["id"])
                cost[(a, s["id"])] = far / cell
        pairs = matching(sources, targets, order, cost)
        for a in sources:
            if a in pairs:
                out.add((a, pairs[a]))
            else:
                dropped.append((a, None, "read as a fork, but no space is free for it"))
    return sorted(out), dropped


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
    found, dropped = tidy(track, found, cell)

    # A reading by eye, where there is one, says which spaces fork: the
    # detector's count of heads is the weak part. The detector's links are
    # kept only to compare against.
    reading_path = ROOT / "tracks" / f"{map_id}.arrows.json"
    if reading_path.exists():
        reading = json.loads(reading_path.read_text(encoding="utf-8"))
        detected = found
        found, dropped = from_reading(track, reading, cell)
        misses = []
        seen = {}
        for a_, b_ in detected:
            seen.setdefault(a_, set()).add(b_)
        mine = {}
        for a_, b_ in found:
            mine.setdefault(a_, set()).add(b_)
        agree = sum(1 for i in mine if seen.get(i) == mine[i])
        print("   using the reading in %s: the detector agrees on %d of its %d spaces"
              % (reading_path.relative_to(ROOT), agree, len(mine)))
    for a_, b_, why in dropped:
        print("   space %s: %s%s" % (a_, why, "" if b_ is None else " (was %s)" % b_))
    by_space = {}
    for src, dst in found:
        by_space.setdefault(src, set()).add(dst)
    print("2. %d links on %d spaces%s" % (len(found), len(by_space),
          ("; %d arrows unread" % len(misses)) if misses else ""))
    for why, at, sid in misses[:10]:
        print("   %s at (%d, %d)%s" % (why, at[0], at[1],
              "" if sid is None else " near space %s" % sid))

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
        # Spaces the reading found no arrow on go back to the plain rule --
        # on, or a lane either side -- in case an earlier run fixed them.
        if reading_path.exists():
            pos = np.array([s["pos"] for s in track["spaces"]])
            for sid in reading.get("blank", []):
                s = spaces[sid]
                s.pop("fixed", None)
                s["next"] = sorted(o["id"] for o in ahead_of(s, track["spaces"], pos, cell).values())
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
