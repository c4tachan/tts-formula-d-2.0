"""Run the Lua unit tests under tests/ with a real Lua 5.2 (via lupa).

Only modules that make no TTS calls can be tested this way -- which is the
point of keeping the rules in fd.core and fd.rules.

Each tests/test_*.lua file returns a table of name -> function. A test fails
by raising an error.

Run:  python tools/test_lua.py            (pip install lupa)
      python tools/test_lua.py --bench    call counts and timings, not tests
"""
import pathlib
import sys

try:
    from lupa import lua52
except ImportError:
    sys.exit("lupa is not installed: pip install -r tools/requirements-dev.txt")

ROOT = pathlib.Path(__file__).resolve().parents[1]


def bench():
    """Run tests/bench.lua: call counts and timings for common actions."""
    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{(ROOT / "src").as_posix()}/?.lua;{(ROOT / "tests").as_posix()}/?.lua;" .. package.path')
    lua.globals().ROOT = ROOT.as_posix()
    lua.execute((ROOT / "tests" / "bench.lua").read_text(encoding="utf-8"))
    return 0


def main():
    if "--bench" in sys.argv:
        return bench()
    failed = total = 0
    for f in sorted((ROOT / "tests").glob("test_*.lua")):
        lua = lua52.LuaRuntime(unpack_returned_tuples=True)
        src = (ROOT / "src").as_posix()
        tests = (ROOT / "tests").as_posix()
        lua.execute(f'package.path = "{src}/?.lua;{tests}/?.lua;" .. package.path')
        lua.globals().ROOT = ROOT.as_posix()
        suite = lua.execute(f.read_text(encoding="utf-8"))
        run = lua.eval("function(fn) local ok, err = pcall(fn) return ok, tostring(err) end")
        names = sorted(suite.keys())
        print(f.relative_to(ROOT))
        for name in names:
            total += 1
            ok, err = run(suite[name])
            if ok:
                print(f"  ok   {name}")
            else:
                failed += 1
                print(f"  FAIL {name}\n       {err}")
    print(f"\n{total} test(s), {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
