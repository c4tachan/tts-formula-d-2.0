"""Build the save to publish from the repo, without the game.

save/Formula D.json is the clean save (at setup, no cars) with the scripts
that come from src/entry/ taken out. The build puts them back as TTSLua's
Save & Play would -- each entry script with the fd.* modules it requires
inlined, in luabundle's format -- and points every asset at the repo's pinned
copy (tools/pin_assets.py). The result is what Save & Play into a freshly
loaded clean save gives, so a release can be built by CI.

Run:  python tools/build_save.py [--out DIR]
          write DIR/Formula D.json and its thumbnail (default build/)
      python tools/build_save.py --take [SAVE]
          make SAVE the template (default: the TTS folder's
          "Formula D - clean.json"), its src/entry/ scripts taken out
      python tools/build_save.py --compare SAVE
          check the bundled scripts match those Save & Play put in SAVE

The asset pins must be on GitHub, as for pin_assets.py: CI checks out the
full history so `git branch -r --contains` can tell.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "extract"))
from pin_assets import point_at_repo, repo_urls, report  # noqa: E402
from tts_paths import TTS_DIR  # noqa: E402

SRC = ROOT / "src"
ENTRY = SRC / "entry"
TEMPLATE = ROOT / "save" / "Formula D.json"
CLEAN = TTS_DIR / "Saves" / "Formula D - clean.json"
OUT = ROOT / "build"

# luabundle 1.6.0, which TTSLua runs on Save & Play, verbatim.
BUNDLER = "1.6.0"
PRELUDE = """\
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\\"' .. name .. '\\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(nil)
"""

LONG = re.compile(r"\[(=*)\[")
REQUIRE = re.compile(r"""\brequire\s*\(?\s*(["'])([^"'\n]+)\1""")


def without_comments(text):
    """`text` with its comments dropped, strings kept, so a require in a
    comment is not taken for one."""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("--", i):
            m = LONG.match(text, i + 2)
            if m:
                end = text.find("]" + m.group(1) + "]", m.end())
                i = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = text.find("\n", i)
                i = n if end < 0 else end
            continue
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
            continue
        m = LONG.match(text, i) if c == "[" else None
        if m:
            end = text.find("]" + m.group(1) + "]", m.end())
            end = n if end < 0 else end + len(m.group(1)) + 2
            out.append(text[i:end])
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


def requires(text):
    if "require" not in text:
        return []
    return [m.group(2) for m in REQUIRE.finditer(without_comments(text))]


def module_path(name):
    for ext in (".lua", ".ttslua"):
        path = SRC / (name.replace(".", "/") + ext)
        if path.exists():
            return path
    sys.exit(f"no module {name} under {SRC.relative_to(ROOT)}")


def read(path):
    return path.read_text(encoding="utf-8")


def bundle(path):
    """The script TTSLua would send for entry script `path`: its own text if
    it requires nothing, else it and every module it needs, bundled."""
    text = read(path)
    if not requires(text):
        return text
    root = path.name
    # luabundle's order: depth first, the last require seen taken first.
    bodies = {root: text}
    stack = requires(text)
    while stack:
        name = stack.pop()
        if name in bodies:
            continue
        bodies[name] = read(module_path(name))
        stack += requires(bodies[name])
    out = ['-- Bundled by luabundle {"rootModuleName":"%s","version":"%s"}\n' % (root, BUNDLER), PRELUDE]
    for name, body in bodies.items():
        out.append(f'__bundle_register("{name}", function(require, _LOADED, __bundle_register, __bundle_modules)\n'
                   f"{body}\nend)\n")
    out.append(f'return __bundle_require("{root}")')
    return "".join(out)


def entries():
    """GUID -> {"LuaScript": text, "XmlUI": text} from src/entry/, "-1"
    being Global."""
    out = {}
    for path in sorted(ENTRY.iterdir()):
        if path.suffix in (".lua", ".ttslua"):
            key, text = "LuaScript", bundle(path)
        elif path.suffix == ".xml":
            key, text = "XmlUI", read(path)
        else:
            continue
        guid = path.name.rsplit(".", 2)[-2]
        out.setdefault(guid, {})[key] = text
    return out


def objects(data):
    """Every object in a save, bag contents and other states included."""
    def walk(objs):
        for o in objs:
            yield o
            yield from walk(o.get("ContainedObjects") or [])
            yield from walk((o.get("States") or {}).values())
    yield from walk(data.get("ObjectStates") or [])


def by_guid(data):
    """GUID -> the save's objects with it, "-1" being the save itself."""
    out = {"-1": [data]}
    for o in objects(data):
        out.setdefault(o.get("GUID"), []).append(o)
    return out


def scripted(data, scripts):
    """Set each entry's scripts on its objects in `data`, in place."""
    found = by_guid(data)
    missing = sorted(set(scripts) - set(found))
    if missing:
        sys.exit(f"src/entry/ has scripts for objects not in the save: {', '.join(missing)}")
    for guid, fields in scripts.items():
        for obj in found[guid]:
            # An entry script without XML leaves the object with none, as
            # Save & Play does.
            obj["LuaScript"] = fields.get("LuaScript", "")
            obj["XmlUI"] = fields.get("XmlUI", "")


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def take(path):
    """Make the save at `path` the template, if it is one to publish."""
    data = load(path)
    state = json.loads(data.get("LuaScriptState") or "{}")
    race = state.get("race") or {}
    if race.get("phase", "setup") != "setup" or race.get("cars"):
        sys.exit(f"{path.name} has a race on the table: load the clean save fresh and save that")
    scripted(data, {guid: {} for guid in entries()})
    TEMPLATE.parent.mkdir(exist_ok=True)
    write(TEMPLATE, data)
    thumb = path.with_suffix(".png")
    if thumb.exists():
        TEMPLATE.with_suffix(".png").write_bytes(thumb.read_bytes())
    print(f"{path.name} -> {TEMPLATE.relative_to(ROOT)}")


def compare(path):
    """Check each bundled entry script against the one in the save at `path`."""
    found = by_guid(load(path))
    bad = 0
    for guid, fields in entries().items():
        for key, text in fields.items():
            have = [o.get(key, "") for o in found.get(guid, [])]
            same = all(h.replace("\r\n", "\n") == text.replace("\r\n", "\n") for h in have)
            print(f"  {'same' if same and have else 'DIFF'}  {guid} {key}")
            bad += not (same and have)
    return 1 if bad else 0


def build(out):
    data = load(TEMPLATE)
    scripted(data, entries())
    urls, ui, _ = repo_urls()
    count, unknown, missing = point_at_repo(data, urls, ui)
    report(count, unknown, missing)
    out.mkdir(parents=True, exist_ok=True)
    dest = out / TEMPLATE.name
    write(dest, data)
    thumb = TEMPLATE.with_suffix(".png")
    if thumb.exists():
        dest.with_suffix(".png").write_bytes(thumb.read_bytes())
    print(f"built {dest} ({count} asset URLs pointed at the repo)")


def arg_after(flag, default):
    i = sys.argv.index(flag)
    return pathlib.Path(sys.argv[i + 1]) if i + 1 < len(sys.argv) else default


def main():
    if "--take" in sys.argv:
        return take(arg_after("--take", CLEAN))
    if "--compare" in sys.argv:
        return compare(arg_after("--compare", CLEAN))
    return build(arg_after("--out", OUT) if "--out" in sys.argv else OUT)


if __name__ == "__main__":
    sys.exit(main())
