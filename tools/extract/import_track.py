"""Bring track edits made in TTS into the repo.

TTS scripts cannot write files, so the in-game track editor keeps its edits
in the Global script's saved state. Save the game (Menu > Save), then run
this: it reads the newest save, writes each edited track to tracks/<id>.json
marked as hand-edited -- so the detector never overwrites it again -- and
regenerates the Lua track modules, ready to push and commit.

Run:  python tools/extract/import_track.py              newest save
      python tools/extract/import_track.py <save.json>   a particular one
      python tools/extract/import_track.py --list        what the newest save holds
"""
import datetime
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TRACKS = ROOT / "tracks"


def saves_dir():
    """Where TTS keeps its saves; TTS_SAVES overrides."""
    if os.environ.get("TTS_SAVES"):
        return pathlib.Path(os.environ["TTS_SAVES"])
    sys.path.insert(0, str(ROOT / "tools" / "extract"))
    from tts_paths import TTS_DIR
    return TTS_DIR / "Saves"


def newest_save():
    folder = saves_dir()
    # Saves are TS_Save_N.json and TS_AutoSave.json; SaveFileInfos.json beside
    # them is TTS's index of saves, not a save.
    saves = [p for p in folder.glob("TS_*.json") if not p.name.endswith(".cloudinfo.json")]
    if not saves:
        sys.exit(f"No saves found in {folder}. Save the game in TTS first (Menu > Save), "
                 "or set TTS_SAVES to your Saves folder.")
    return max(saves, key=lambda p: p.stat().st_mtime)


def edits_in(save_path):
    save = json.loads(save_path.read_text(encoding="utf-8"))
    state = save.get("LuaScriptState") or ""
    if not state:
        return {}
    return json.loads(state).get("edits") or {}


def as_list(v):
    """Lua arrays can come through JSON as objects keyed "1", "2", ...; empty
    ones as {}. Normalise both to a list."""
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(v, key=lambda k: int(k))]
    return []


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    save_path = pathlib.Path(args[0]) if args else newest_save()
    edits = edits_in(save_path)
    when = datetime.datetime.fromtimestamp(save_path.stat().st_mtime)
    print(f"{save_path.name}  (saved {when:%Y-%m-%d %H:%M})")
    if not edits:
        print("  no track edits in this save")
        return 1
    for track_id, e in edits.items():
        print(f"  {track_id}: {len(as_list(e.get('spaces')))} spaces")
    if "--list" in sys.argv:
        return 0

    for track_id, e in edits.items():
        path = TRACKS / f"{track_id}.json"
        if not path.exists():
            print(f"  skipping {track_id}: no {path.relative_to(ROOT)} to update")
            continue
        track = json.loads(path.read_text(encoding="utf-8"))
        before = len(track["spaces"])
        old = {s["id"]: s for s in track["spaces"]}
        # Ids are space codes; a save from before them has numbers, which
        # come back from TTS's JSON as floats.
        sid = lambda v: int(v) if isinstance(v, float) and v.is_integer() else v
        spaces = []
        for s in as_list(e.get("spaces")):
            prev = old.get(sid(s["id"]), {})
            space = {
                "id": sid(s["id"]),
                "pos": [round(float(v), 1) for v in as_list(s["pos"])],
                "rot": round(float(s["rot"]) % 360, 1),
                "lane": int(s["lane"]),
                "next": sorted((sid(n) for n in as_list(s.get("next"))), key=str),
                "corner": prev.get("corner"),
                "sector": prev.get("sector", 0),
            }
            if s.get("fixed"):
                space["fixed"] = True        # links set by hand: never recomputed
            spaces.append(space)
        spaces.sort(key=lambda s: str(s["id"]))
        track["spaces"] = spaces
        track["edited"] = True
        track["edited_from"] = f"{save_path.name} ({when:%Y-%m-%d %H:%M})"
        path.write_text(json.dumps(track, indent=1), encoding="utf-8")
        print(f"  {path.relative_to(ROOT)}: {before} -> {len(spaces)} spaces, marked as hand-edited")

    sys.path.insert(0, str(ROOT / "tools" / "extract"))
    import gen_tracks
    gen_tracks.main()
    print("Next: pwsh tools/sync.ps1 push, Save & Play, check it, then commit tracks/ and src/fd/data/tracks/.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
