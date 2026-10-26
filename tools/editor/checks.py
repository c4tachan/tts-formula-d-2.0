"""The track tests (tests/test_tracks.lua), run on a track as it is being edited.

The editor's problem list is fd.core.trackgraph's, which looks at one space
and its neighbours. tests/test_tracks.lua checks the rest a track has to get
right before the mod can play it -- the pit lane's ways in and out, the grid,
the finish line, corners, every space touching another. This runs those
tests on the working copy, as the Lua module gen_tracks.py would write for
it, so a save is known to pass them before it reaches the game.
"""
import json
import pathlib
import re
import sys

from lupa import lua52

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "extract"))

import gen_tracks  # noqa: E402

# A failure reads "<id>: [string ...]:<line>: <why>": the why is what matters.
NOISE = re.compile(r'\[string "[^"]*"\]:\d+: ')


def run(track, adjacency_path=None):
    """[{test, text}] for each test in tests/test_tracks.lua the track fails."""
    near = None
    if adjacency_path and pathlib.Path(adjacency_path).exists():
        pairs = json.loads(pathlib.Path(adjacency_path).read_text(encoding="utf-8"))["pairs"]
        near = gen_tracks.neighbours(pairs)
    tid = track["id"]
    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = "%s/?.lua;%s/?.lua;" .. package.path'
                % ((ROOT / "src").as_posix(), (ROOT / "tests").as_posix()))
    source = gen_tracks.lua_track(track, near)
    lua.globals().MODULE_SOURCE = source
    lua.globals().MODULE_NAME = "fd.data.tracks." + tid
    lua.execute('package.loaded[MODULE_NAME] = assert(load(MODULE_SOURCE, "=" .. MODULE_NAME))()')
    lua.globals().ONLY_TRACKS = lua.table_from([tid])
    lua.globals().ROOT = ROOT.as_posix()
    suite = lua.execute((ROOT / "tests" / "test_tracks.lua").read_text(encoding="utf-8"))
    call = lua.eval("function(fn) local ok, err = pcall(fn) return ok, tostring(err) end")
    out = []
    for name in sorted(suite.keys()):
        ok, err = call(suite[name])
        if not ok:
            text = NOISE.sub("", err)
            text = text[len(tid) + 2:] if text.startswith(tid + ": ") else text
            out.append({"test": name.replace("_", " "), "text": text})
    return out


def failing_space(text, ids):
    """The space a failure names first, if it names one."""
    for word in re.findall(r"[\w.+]+", text):
        if word in ids:
            return word
    return None
