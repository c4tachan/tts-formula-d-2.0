"""Syntax-check every Lua file under src/.

TTS only reports script errors once the mod is loaded in game, which makes a
typo an expensive round trip. This catches them before Save & Play.

Run:  python tools/check_lua.py
"""
import pathlib
import re
import sys

from luaparser import ast

ROOT = pathlib.Path(__file__).resolve().parents[1]


# TTS runs MoonSharp, which does not reliably start a bare `local x` as nil:
# inside a function it can pick up whatever an earlier variable left in that
# slot. It broke the track editor ("attempt to compare number with table")
# while passing every test under real Lua. Top-level declarations are safe.
BARE_LOCAL = re.compile(r"^\s+local [A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*\s*(--.*)?$")


def bare_locals(text):
    return [n for n, line in enumerate(text.splitlines(), 1) if BARE_LOCAL.match(line)]


def main():
    files = sorted((ROOT / "src").rglob("*.lua")) + sorted((ROOT / "src").rglob("*.ttslua"))
    failed = 0
    for f in files:
        rel = f.relative_to(ROOT)
        text = f.read_text(encoding="utf-8", errors="replace")
        try:
            ast.parse(text)
        except Exception as e:
            failed += 1
            print(f"  FAIL {rel}\n       {str(e).splitlines()[0]}")
            continue
        bare = bare_locals(text)
        if bare:
            failed += 1
            print(f"  FAIL {rel}\n       bare `local x` (write `local x = nil`) on line(s) "
                  + ", ".join(map(str, bare)))
            continue
        print(f"  ok   {rel}")
    print(f"\n{len(files)} file(s), {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
