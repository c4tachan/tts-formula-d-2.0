"""Extract the map registry out of the original 2020 board script + XML.

The legacy mod stored the same map three times: a URL in one of three Lua
tables, a three-line `setupXxx()` click handler, and an XML button carrying the
display name and thumbnail asset. This joins them into one record per map.

Run:  python tools/extract/extract_maps.py
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "reference" / "original-2020"
LUA = SRC / "Custom Board.9e2fe8.lua"
XML = SRC / "Custom Board.9e2fe8.xml"
OUT = ROOT / "tools" / "extract" / "maps.json"

CATEGORY = {
    "maps_formula_d": "formula_d",
    "maps_formula_de": "formula_de",
    "maps_custom": "custom",
}
ORDER = ["formula_d", "formula_de", "custom"]

# maps_custom["Name"] = "https://..."
RE_ENTRY = re.compile(
    r'(maps_formula_de|maps_formula_d|maps_custom)\s*\[\s*"([^"]+)"\s*\]\s*=\s*"([^"]*)"'
)
# function setupFDMonaco(...) setMapImage(maps_formula_d["Formula D: Monaco"]) end
RE_SETUP = re.compile(
    r'function\s+(setup\w+)\s*\([^)]*\)\s*'
    r'setMapImage\(\s*(maps_formula_de|maps_formula_d|maps_custom)\s*\[\s*"([^"]+)"\s*\]\s*\)',
    re.S,
)
# Attribute order and `text = "x"` spacing both vary across the file, so pull the
# whole tag and read attributes generically rather than positionally.
RE_BUTTON = re.compile(r'<Button\b([^>]*)>(.*?)</Button>', re.S)
RE_ATTR = re.compile(r'(\w+)\s*=\s*"([^"]*)"')
RE_THUMB = re.compile(r'<Image\b[^>]*?\bimage\s*=\s*"([^"]+)"')

# The 2020 XML has one button whose onClick lost its `setup` prefix, leaving the
# map unclickable in game. Recover it by name instead of dropping the map.
ONCLICK_REPAIRS = {"Viamao": "setupViamao"}


def slug(setup_fn):
    """setupFDMonaco -> FDMonaco (stable, already unique, XML-arg safe)."""
    return setup_fn[len("setup"):]


def main():
    lua = LUA.read_text(encoding="utf-8", errors="replace")
    xml = XML.read_text(encoding="utf-8", errors="replace")

    urls = {}       # (category, lua key) -> url
    for table, name, url in RE_ENTRY.findall(lua):
        urls[(CATEGORY[table], name)] = url

    setups = {}     # setup_fn -> (category, lua key)
    for fn, table, name in RE_SETUP.findall(lua):
        setups[fn] = (CATEGORY[table], name)

    buttons, repaired = {}, []      # setup_fn -> (display text, thumb asset)
    for attrs, inner in RE_BUTTON.findall(xml):
        a = dict(RE_ATTR.findall(attrs))
        if a.get("class") != "mapButton":
            continue
        fn = a.get("onClick")
        if not fn:
            continue                # the <Defaults> class declaration
        fn = fn.split("(")[0].strip()
        if fn in ONCLICK_REPAIRS:
            repaired.append(f"{fn} -> {ONCLICK_REPAIRS[fn]}")
            fn = ONCLICK_REPAIRS[fn]
        thumb = RE_THUMB.search(inner)
        buttons[fn] = (a.get("text", "").strip(), thumb.group(1) if thumb else None)

    maps, problems, seen = [], [], set()

    for fn, (category, key) in setups.items():
        url = urls.get((category, key))
        if not url:
            problems.append(f"{fn}: no URL for {category}[{key!r}]")
            continue
        text, thumb = buttons.get(fn, (None, None))
        if text is None:
            problems.append(f"{fn}: no XML button (map unreachable in UI)")
        if not thumb:
            problems.append(f"{fn}: button has no thumbnail image")
        mid = slug(fn)
        if mid in seen:
            problems.append(f"{fn}: duplicate id {mid!r}")
        seen.add(mid)
        maps.append({
            "id": mid,
            "name": text or key,    # XML text is the display name; for the
            "key": key,             # PL_* packs it differs from the Lua key
            "category": category,
            "url": url,
            "thumb": thumb,
        })

    for fn in buttons:
        if fn not in setups:
            problems.append(f"{fn}: XML button has no Lua handler (dead button)")
    known = {(m["category"], m["key"]) for m in maps}
    for ck in urls:
        if ck not in known:
            problems.append(f"{ck[0]}[{ck[1]!r}]: URL never used by any handler")

    maps.sort(key=lambda m: (ORDER.index(m["category"]), m["id"]))
    OUT.write_text(json.dumps(maps, indent=2), encoding="utf-8")

    counts = {}
    for m in maps:
        counts[m["category"]] = counts.get(m["category"], 0) + 1
    print(f"extracted {len(maps)} maps -> {OUT.relative_to(ROOT)}")
    for c in ORDER:
        print(f"  {c:12} {counts.get(c, 0)}")
    if repaired:
        print("\nrepaired malformed onClick:")
        for r in repaired:
            print("  ~ " + r)
    print(f"\n{len(problems)} problem(s)")
    for p in problems[:40]:
        print("  ! " + p)
    if len(problems) > 40:
        print(f"  ... and {len(problems) - 40} more")
    return 0


if __name__ == "__main__":
    sys.exit(main())
