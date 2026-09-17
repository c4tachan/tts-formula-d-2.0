"""Syntax-check every Lua file under src/.

TTS only reports script errors once the mod is loaded in game, which makes a
typo an expensive round trip. This catches them before Save & Play.

Run:  python tools/check_lua.py
"""
import pathlib
import sys

from luaparser import ast

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    files = sorted((ROOT / "src").rglob("*.lua")) + sorted((ROOT / "src").rglob("*.ttslua"))
    failed = 0
    for f in files:
        rel = f.relative_to(ROOT)
        try:
            ast.parse(f.read_text(encoding="utf-8", errors="replace"))
            print(f"  ok   {rel}")
        except Exception as e:
            failed += 1
            print(f"  FAIL {rel}\n       {str(e).splitlines()[0]}")
    print(f"\n{len(files)} file(s), {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
