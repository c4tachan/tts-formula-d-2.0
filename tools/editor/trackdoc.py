"""A track being edited: its spaces, the edits made to it, and what looks wrong.

The browser editor and Claude's command line both change a track through
`TrackDoc.apply(ops)`, so the rules are the same whoever makes the edit, and
they are the in-game editor's rules (src/fd/tts/track_editor.lua): moving,
turning, adding, deleting a space or changing its lane relinks the track;
a link set by hand marks its space `fixed`, and relinking leaves it alone.
Links and problems come from fd.core.trackgraph itself, run under Lua 5.2
through lupa, so nothing here re-implements them.

An op is a dict with "op" and its fields:

  move    id, pos [x, y]            (rot too, optionally)
  rotate  id, rot                   degrees in image space, 0 = right, clockwise
  turn    id, by                    rot += by
  lane    id, lane                  1 = inside
  add     pos [x, y], like (id)     like the nearest space, or `like`
  delete  id
  link    from, to                  toggles the link; `from` becomes fixed
  unfix   id                        back to automatic links
  grid    id                        on the end of the grid, or off it
  grid_set ids                      the whole grid, pole first
  dice    pos [x, y]
  dice_side side                    up | right | down | left
  panel   pos [x, y], width
  set     id, fields {...}          corner, sector, lane, rot, pos, pit, box

Positions are image pixels, as in the track files (docs/track-format.md).
"""
import copy
import json
import math
import pathlib
import re

from lupa import lua52

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Ops that change where spaces are, and so their links.
GEOMETRY = {"move", "rotate", "turn", "lane", "add", "delete", "unfix", "set"}
SIDES = ["up", "right", "down", "left"]
PANEL_MIN, PANEL_MAX = 150, 1600
UNDO_DEPTH = 200
SETTABLE = {"corner", "sector", "lane", "rot", "pos", "pit", "box"}


class OpError(ValueError):
    """An op that cannot be applied: nothing is changed."""


class Graph:
    """fd.core.trackgraph, under real Lua 5.2."""

    def __init__(self):
        self.lua = lua52.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('package.path = "%s/?.lua;" .. package.path' % (ROOT / "src").as_posix())
        self.mod = self.lua.eval('require("fd.core.trackgraph")')

    def _table(self, spaces):
        return self.lua.table_from([{k: v for k, v in s.items() if v is not None} for s in spaces],
                                   recursive=True)

    def relink(self, spaces):
        """Relink `spaces` in place; returns the cell length it worked with."""
        t = self._table(spaces)
        cell = self.mod.relink(t)
        for i, s in enumerate(spaces):
            nxt = t[i + 1].next
            s["next"] = [nxt[j] for j in range(1, len(nxt) + 1)] if nxt else []
        return float(cell)

    def problems(self, spaces, cell=None):
        t = self._table(spaces)
        try:
            out = self.mod.problems(t, cell)
        except Exception as e:   # mixed id types in a fresh scan, say
            return [{"id": None, "text": "could not check the track: %s" % e}]
        return [{"id": out[i].id, "text": out[i].text} for i in range(1, len(out) + 1)]


GRAPH = None


def graph():
    global GRAPH
    if GRAPH is None:
        GRAPH = Graph()
    return GRAPH


def _num(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise OpError("not a number: %r" % (v,))
    return float(v)


def _point(v):
    if not isinstance(v, (list, tuple)) or len(v) != 2:
        raise OpError("a position is [x, y], not %r" % (v,))
    return [round(_num(v[0]), 1), round(_num(v[1]), 1)]


class TrackDoc:
    """One track's working copy, with undo."""

    def __init__(self, track, relink=True):
        self.track = track
        self.undo_stack = []
        self.redo_stack = []
        self.dirty = False
        # Whether any space has moved, come or gone since the last save:
        # the adjacency file is then out of date.
        self.moved = False
        self.cell = 0.0
        # How many spaces' links opening the track changed.
        self.relinked = 0
        if relink:
            # Start from links worked out the editor's way, as the in-game
            # editor does: the detector's are cruder.
            was = {str(s["id"]): sorted(map(str, s.get("next", []))) for s in self.spaces}
            self.cell = graph().relink(self.spaces)
            self.relinked = sum(1 for s in self.spaces if sorted(map(str, s["next"])) != was[str(s["id"])])
        else:
            self.cell = graph().mod.cellLength(graph()._table(self.spaces))
        self.problems = graph().problems(self.spaces, self.cell)

    @property
    def spaces(self):
        return self.track.setdefault("spaces", [])

    def index(self):
        return {s["id"]: s for s in self.spaces}

    def find(self, sid):
        for s in self.spaces:
            if s["id"] == sid:
                return s
        # Ids from a fresh scan are numbers; from the command line, strings.
        for s in self.spaces:
            if str(s["id"]) == str(sid):
                return s
        raise OpError("no space %r" % (sid,))

    def nearest(self, x, y):
        best, best_d = None, None
        for s in self.spaces:
            d = math.hypot(s["pos"][0] - x, s["pos"][1] - y)
            if best_d is None or d < best_d:
                best, best_d = s, d
        return best, best_d

    # Undo ---------------------------------------------------------------

    def _snapshot(self):
        keep = {k: self.track.get(k) for k in ("spaces", "start", "dice", "dice_side", "panel")}
        return json.dumps(keep), self.moved

    def _restore(self, snap):
        data, moved = snap
        for k, v in json.loads(data).items():
            if v is None:
                self.track.pop(k, None)
            else:
                self.track[k] = v
        self.moved = moved
        self._recheck(relink=False)
        self.dirty = True

    def undo(self):
        if not self.undo_stack:
            return False
        self.redo_stack.append(self._snapshot())
        self._restore(self.undo_stack.pop())
        return True

    def redo(self):
        if not self.redo_stack:
            return False
        self.undo_stack.append(self._snapshot())
        self._restore(self.redo_stack.pop())
        return True

    def _recheck(self, relink):
        if relink:
            self.cell = graph().relink(self.spaces)
        self.problems = graph().problems(self.spaces, self.cell)

    # Ops ----------------------------------------------------------------

    def apply(self, ops):
        """Apply a batch of ops as one undo step. All or nothing: an op that
        fails leaves the track as it was, and raises OpError."""
        if isinstance(ops, dict):
            ops = [ops]
        if not ops:
            return []
        snap = self._snapshot()
        before = copy.deepcopy(self.track)
        notes = []
        try:
            geometry = False
            for op in ops:
                if not isinstance(op, dict):
                    raise OpError("an op is an object with an \"op\" field, not %r" % (op,))
                notes.append(self._one(op))
                geometry = geometry or op.get("op") in GEOMETRY
        except (OpError, KeyError, TypeError, ValueError) as e:
            self.track.clear()
            self.track.update(before)
            self.moved = snap[1]
            if isinstance(e, OpError):
                raise
            raise OpError("bad op: %s %s" % (type(e).__name__, e))
        self.undo_stack.append(snap)
        del self.undo_stack[:-UNDO_DEPTH]
        self.redo_stack.clear()
        self.dirty = True
        self._recheck(relink=geometry)
        return notes

    def _one(self, op):
        kind = op.get("op")
        fn = getattr(self, "_op_" + str(kind), None)
        if not fn:
            raise OpError("unknown op %r" % (kind,))
        return fn(op)

    def _op_move(self, op):
        s = self.find(op["id"])
        s["pos"] = _point(op["pos"])
        if "rot" in op:
            s["rot"] = round(_num(op["rot"]) % 360, 1)
        self.moved = True
        return "moved %s to %s" % (s["id"], s["pos"])

    def _op_rotate(self, op):
        s = self.find(op["id"])
        s["rot"] = round(_num(op["rot"]) % 360, 1)
        return "turned %s to %s deg" % (s["id"], s["rot"])

    def _op_turn(self, op):
        s = self.find(op["id"])
        s["rot"] = round((s.get("rot", 0) + _num(op["by"])) % 360, 1)
        return "turned %s to %s deg" % (s["id"], s["rot"])

    def _op_lane(self, op):
        s = self.find(op["id"])
        lane = int(_num(op["lane"]))
        if lane < 0 or lane > 9:
            raise OpError("lane %d is off the track" % lane)
        s["lane"] = lane
        # The pit lane is lane 0 (docs/track-format.md): a space moved into
        # a lane of the track leaves it, and one moved to lane 0 joins it.
        if not s.get("box"):
            if lane == 0:
                s["pit"] = True
            else:
                s.pop("pit", None)
        return "%s is in lane %d%s" % (s["id"], lane, " (the pit lane)" if s.get("pit") else "")

    def _op_add(self, op):
        pos = _point(op["pos"])
        like = self.find(op["like"]) if op.get("like") is not None else self.nearest(*pos)[0]
        # Named after its neighbour, as in the game: m.c1.3+1, m.c1.3+2 --
        # beside an added space too, rather than m.c1.3+1+1.
        base = re.sub(r"\+\d+$", "", str(like["id"])) if like else "new"
        n = 1
        ids = {str(s["id"]) for s in self.spaces}
        while "%s+%d" % (base, n) in ids:
            n += 1
        s = {"id": op.get("new_id") or "%s+%d" % (base, n), "pos": pos, "next": [],
             "lane": like["lane"] if like else 1, "rot": like["rot"] if like else 0.0}
        if str(s["id"]) in ids:
            raise OpError("there is a space %s already" % s["id"])
        for k in ("corner", "sector", "pit"):
            if like and like.get(k) is not None:
                s[k] = like[k]
        self.spaces.append(s)
        self.moved = True
        return "added %s at %s" % (s["id"], pos)

    def _op_delete(self, op):
        s = self.find(op["id"])
        self.spaces.remove(s)
        for o in self.spaces:
            if s["id"] in o.get("next", []):
                o["next"] = [n for n in o["next"] if n != s["id"]]
        if s["id"] in (self.track.get("start") or []):
            self.track["start"] = [g for g in self.track["start"] if g != s["id"]]
        self.moved = True
        return "deleted %s" % s["id"]

    def _op_link(self, op):
        a, b = self.find(op["from"]), self.find(op["to"])
        if a is b:
            raise OpError("a space cannot lead to itself")
        nxt = list(a.get("next", []))
        if b["id"] in nxt:
            nxt.remove(b["id"])
            verb = "no longer leads to"
        else:
            nxt.append(b["id"])
            verb = "now leads to"
        a["next"] = sorted(nxt, key=str)
        a["fixed"] = True
        return "%s %s %s (links set by hand)" % (a["id"], verb, b["id"])

    def _op_unfix(self, op):
        s = self.find(op["id"])
        s.pop("fixed", None)
        return "%s is linked automatically again" % s["id"]

    def _op_grid(self, op):
        s = self.find(op["id"])
        start = self.track.setdefault("start", [])
        if s["id"] in start:
            start.remove(s["id"])
            return "%s is off the grid" % s["id"]
        start.append(s["id"])
        return "%s is grid place %d" % (s["id"], len(start))

    def _op_grid_set(self, op):
        ids = [self.find(i)["id"] for i in op["ids"]]
        if len(set(map(str, ids))) != len(ids):
            raise OpError("a space can be on the grid once")
        self.track["start"] = ids
        return "grid set: %d places" % len(ids)

    def _op_dice(self, op):
        self.track["dice"] = [round(v) for v in _point(op["pos"])]
        return "dice tray at %s" % self.track["dice"]

    def _op_dice_side(self, op):
        if op["side"] not in SIDES:
            raise OpError("a side is one of %s" % ", ".join(SIDES))
        self.track["dice_side"] = op["side"]
        return "dice line up along the %s side" % op["side"]

    def _op_panel(self, op):
        was = self.track.get("panel") or {}
        pos = _point(op["pos"]) if "pos" in op else was.get("pos")
        if not pos:
            raise OpError("the race panel has no place yet: give it a pos")
        width = _num(op.get("width", was.get("width", 400)))
        self.track["panel"] = {"pos": [round(v) for v in pos],
                               "width": round(max(PANEL_MIN, min(PANEL_MAX, width)))}
        return "race panel at %s, %d wide" % (self.track["panel"]["pos"], self.track["panel"]["width"])

    def _op_set(self, op):
        s = self.find(op["id"])
        fields = op["fields"]
        bad = set(fields) - SETTABLE
        if bad:
            raise OpError("cannot set %s; only %s" % (", ".join(sorted(bad)), ", ".join(sorted(SETTABLE))))
        for k, v in fields.items():
            if k == "pos":
                v = _point(v)
                self.moved = True
            elif k == "rot":
                v = round(_num(v) % 360, 1)
            elif k == "lane":
                v = int(_num(v))
            if v is None or v is False:
                s.pop(k, None)
            else:
                s[k] = v
        return "set %s on %s" % (", ".join(sorted(fields)), s["id"])

    # Output -------------------------------------------------------------

    def for_file(self, edited_from):
        """The track file as it should be written: the same shape
        tools/extract/import_track.py writes from an in-game edit."""
        track = copy.deepcopy(self.track)
        spaces = []
        for s in track["spaces"]:
            space = {
                "id": s["id"],
                "pos": [round(float(v), 1) for v in s["pos"]],
                "rot": round(float(s.get("rot", 0)) % 360, 1),
                "lane": int(s["lane"]),
                "next": sorted(s.get("next", []), key=str),
                "corner": s.get("corner"),
                "sector": s.get("sector", 0),
            }
            if s.get("fixed"):
                space["fixed"] = True
            if s.get("pit"):
                space["pit"] = True
            if s.get("box"):
                space["box"] = s["box"]
            spaces.append(space)
        spaces.sort(key=lambda s: str(s["id"]))
        track["spaces"] = spaces
        ids = {s["id"] for s in spaces}
        if "start" in track:
            track["start"] = [g for g in track["start"] if g in ids]
        if track.get("pit"):
            self._pit_ends(track, spaces)
        track["edited"] = True
        track["edited_from"] = edited_from
        return track

    @staticmethod
    def _pit_ends(track, spaces):
        """The pit lane's ways in and out, as its links now say: every track
        space that leads into the pit lane, and wherever its last space leads."""
        pit = track["pit"]
        by_id = {s["id"]: s for s in spaces}
        in_pit = {s["id"] for s in spaces if s.get("pit") and not s.get("box")}
        # The pit lane in order, entry to exit, as its links run: from the
        # first space it had (or one nothing in the pit lane leads to), on
        # down the pit lane. A space added to it falls into place.
        led_to = {n for i in in_pit for n in by_id[i]["next"] if n in in_pit}
        first = next((i for i in pit.get("spaces", []) if i in in_pit and i not in led_to), None)
        first = first or next((i for i in sorted(in_pit, key=str) if i not in led_to), None)
        lane, seen = [], set()
        while first is not None and first not in seen:
            lane.append(first)
            seen.add(first)
            first = next((n for n in by_id[first]["next"] if n in in_pit), None)
        # Any it could not reach stay listed after, so nothing goes missing.
        lane += [i for i in pit.get("spaces", []) if i in in_pit and i not in seen]
        pit["spaces"] = lane
        pit["entry"] = sorted((s["id"] for s in spaces if not s.get("pit") and not s.get("box")
                               and any(n in in_pit for n in s["next"])), key=str)
        if lane:
            pit["exit"] = sorted((n for n in by_id[lane[-1]]["next"]
                                  if n in by_id and not by_id[n].get("pit") and not by_id[n].get("box")), key=str)
        boxes = [b for b in pit.get("boxes", []) if b.get("space") in by_id]
        pit["boxes"] = boxes

    def summary(self):
        lanes = {}
        for s in self.spaces:
            k = "pit" if s.get("pit") else "box" if s.get("box") else s.get("lane")
            lanes[str(k)] = lanes.get(str(k), 0) + 1
        return {"spaces": len(self.spaces), "by_lane": lanes, "grid": len(self.track.get("start") or []),
                "problems": len(self.problems), "cell": round(self.cell, 1), "dirty": self.dirty,
                "undo": len(self.undo_stack), "redo": len(self.redo_stack)}
