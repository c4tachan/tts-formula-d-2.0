"""Give a track's spaces their codes again, from the track file alone.

A space's id is its code, <lane>.<sector>.<n> (docs/track-format.md). The
codes go wrong as a track is edited: a space added in the editor is named
after the space nearest it, often in another lane (m.c3.3+1 in the inside
lane), and a space moved to another lane keeps its old letter. This works
them out again as find_corners.py does, without the board image:

  - each lane is followed round from its space on the finish line, by the
    link that stays in the lane, and each space numbered within its sector
    (the sector it has, which find_corners.py read off the red lines);
  - the pit lane in its order, entry to exit, numbered within its sectors
    too, so it starts again at the finish line; each pit box after the pit
    lane space beside it.

Every place that names a space is renamed with it: links, the grid, the
finish line, the pit lane's lists and boxes, the arrow reading in
tracks/<id>.arrows.json and the pairs in tracks/<id>.adjacency.json.
Corners and sectors are left as they are.

Run:  python tools/extract/renumber.py            every track, what would change
      python tools/extract/renumber.py --write    and write it
      python tools/extract/renumber.py FDSotchi FDValencia --write
"""
import json
import math
import pathlib
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[2]
TRACKS = ROOT / "tracks"
LETTER = {1: "i", 2: "m", 3: "o"}


class RenumberError(ValueError):
    """The track's links do not say what order its spaces come in."""


def _lane_loop(lane, members, by_id, line):
    """The lane's spaces in running order from its finish-line space."""
    ids = {s["id"] for s in members}
    on = {}
    for s in members:
        same = [n for n in s.get("next", []) if n in ids]
        if same:
            on[s["id"]] = min(same, key=lambda n: math.dist(s["pos"], by_id[n]["pos"]))
    zero = next((i for i in line if i in ids), None)
    if zero is None:
        # No space of this lane on the finish line: the first of s1 that
        # follows one outside it.
        before = {v: k for k, v in on.items()}
        zero = next((s["id"] for s in members if s.get("sector") == "s1"
                     and by_id.get(before.get(s["id"]), {}).get("sector") != "s1"), None)
    if zero is None:
        raise RenumberError("lane %d has no space on the finish line" % lane)
    loop, seen, at = [], set(), zero
    while at is not None and at not in seen:
        loop.append(at)
        seen.add(at)
        at = on.get(at)
    if at != zero or len(loop) != len(members):
        raise RenumberError("lane %d is not one loop: following it from %s stops at %s after %d of %d spaces"
                            % (lane, zero, loop[-1], len(loop), len(members)))
    return loop


def pit_order(track):
    """The pit lane's spaces in order, entry to exit, as its links run: from
    the first space it lists (or one nothing in the pit lane leads to), on
    down the pit lane. A space added to it falls into place; any the walk
    cannot reach stay listed after, so nothing goes missing."""
    pit = track.get("pit") or {}
    by_id = {s["id"]: s for s in track["spaces"]}
    in_pit = {s["id"] for s in track["spaces"] if s.get("pit") and not s.get("box")}
    led_to = {n for i in in_pit for n in by_id[i].get("next", []) if n in in_pit}
    first = next((i for i in pit.get("spaces", []) if i in in_pit and i not in led_to), None)
    first = first or next((i for i in sorted(in_pit, key=str) if i not in led_to), None)
    lane, seen = [], set()
    while first is not None and first not in seen:
        lane.append(first)
        seen.add(first)
        first = next((n for n in by_id[first].get("next", []) if n in in_pit), None)
    return lane + [i for i in pit.get("spaces", []) if i in in_pit and i not in seen]


def codes(track):
    """{old id: code} for every space whose code is not what it should be."""
    spaces = track["spaces"]
    by_id = {s["id"]: s for s in spaces}
    line = list((track.get("finish") or {}).get("line") or [])
    new = {}
    lanes = sorted({s["lane"] for s in spaces if not s.get("pit") and not s.get("box")})
    for lane in lanes:
        members = [s for s in spaces if s["lane"] == lane and not s.get("pit") and not s.get("box")]
        count = Counter()
        for sid in _lane_loop(lane, members, by_id, line):
            sector = by_id[sid].get("sector") or "s1"
            new[sid] = "%s.%s.%d" % (LETTER.get(lane, str(lane)), sector, count[sector])
            count[sector] += 1
    pit = track.get("pit") or {}
    if pit:
        count = Counter()
        for sid in pit_order(track):
            if sid in by_id:
                sector = by_id[sid].get("sector") or "s1"
                new[sid] = "p.%s.%d" % (sector, count[sector])
                count[sector] += 1
        for b in pit.get("boxes", []):
            if b.get("space") in by_id and b.get("beside") in new:
                new[b["space"]] = "b." + new[b["beside"]].split(".", 1)[1]
    # Spaces nothing above reached (a pit space missing from the pit lane's
    # list, say) keep their ids.
    if len(set(new.values())) != len(new):
        dup = [c for c, k in Counter(new.values()).items() if k > 1]
        raise RenumberError("two spaces would get the same code: %s" % ", ".join(dup[:5]))
    taken = {s["id"] for s in spaces if s["id"] not in new}
    clash = taken & set(new.values())
    if clash:
        raise RenumberError("a code is taken by a space left as it was: %s" % ", ".join(sorted(clash)[:5]))
    return {old: c for old, c in new.items() if old != c}


def _sort_key(s):
    order = {"i": 0, "m": 1, "o": 2, "p": 3, "b": 4}
    parts = str(s["id"]).split(".")
    if len(parts) != 3 or not parts[2].isdigit():
        return (9, 0, str(s["id"]))
    sector = parts[1]
    return (order.get(parts[0], 9), int(sector[1:]) * 2 - (sector[0] == "s") if sector[1:].isdigit() else 0,
            int(parts[2]))


def rename(track, mapping):
    """Rename spaces in `track` by `mapping`, everywhere it names one."""
    if not mapping:
        return
    m = lambda i: mapping.get(i, i)
    pit = track.get("pit")
    if pit and "spaces" in pit:
        # In order before anything is renamed: the order is found by id.
        pit["spaces"] = pit_order(track)
    for s in track["spaces"]:
        s["id"] = m(s["id"])
        s["next"] = sorted((m(n) for n in s.get("next", [])), key=str)
    if track.get("start"):
        track["start"] = [m(i) for i in track["start"]]
    if (track.get("finish") or {}).get("line"):
        track["finish"]["line"] = [m(i) for i in track["finish"]["line"]]
    if pit:
        for k in ("entry", "exit", "spaces"):
            if k in pit:
                pit[k] = [m(i) for i in pit[k]]
        for b in pit.get("boxes", []):
            for k in ("space", "beside"):
                if k in b:
                    b[k] = m(b[k])
    track["spaces"].sort(key=_sort_key)


def rename_files(mapping, tid, folder=TRACKS):
    """Rename spaces in tracks/<tid>.arrows.json and .adjacency.json."""
    if not mapping:
        return
    m = lambda i: mapping.get(i, i)
    arrows = folder / f"{tid}.arrows.json"
    if arrows.exists():
        reading = json.loads(arrows.read_text(encoding="utf-8"))
        if "forks" in reading:
            reading["forks"] = {m(k): v for k, v in reading["forks"].items()}
        for k in ("approach", "blank"):
            if k in reading:
                reading[k] = [m(i) for i in reading[k]]
        arrows.write_text(json.dumps(reading, indent=1), encoding="utf-8")
    adjacency = folder / f"{tid}.adjacency.json"
    if adjacency.exists():
        adj = json.loads(adjacency.read_text(encoding="utf-8"))
        adj["pairs"] = [[m(a), m(b)] for a, b in adj.get("pairs", [])]
        adjacency.write_text(json.dumps(adj, indent=1), encoding="utf-8")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    files = [TRACKS / f"{a}.json" for a in args] if args else \
        sorted(f for f in TRACKS.glob("*.json") if f.stem.count(".") == 0)
    changed = False
    for f in files:
        track = json.loads(f.read_text(encoding="utf-8"))
        try:
            mapping = codes(track)
        except RenumberError as e:
            print("%-13s cannot renumber: %s" % (f.stem, e))
            continue
        if not mapping:
            print("%-13s codes all right" % f.stem)
            continue
        shown = ", ".join("%s -> %s" % kv for kv in list(mapping.items())[:6])
        print("%-13s %d to rename: %s%s" % (f.stem, len(mapping), shown, " ..." if len(mapping) > 6 else ""))
        if write:
            rename(track, mapping)
            f.write_text(json.dumps(track, indent=1), encoding="utf-8")
            rename_files(mapping, f.stem)
            changed = True
    if changed:
        sys.path.insert(0, str(ROOT / "tools" / "extract"))
        import gen_tracks
        gen_tracks.main()
    elif not write:
        print("(nothing written: pass --write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
