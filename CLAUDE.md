# Working in this repo

Tabletop Simulator mod for Formula D / Formula Dé. Lua 5.2-ish (TTS's dialect),
plus Python tooling for data extraction.

## Rules of the road

- **`src/entry/` files are TTS objects.** The filename encodes the object GUID
  (`Custom Board.9e2fe8.lua`) and must not be renamed — the extension matches
  objects by it. `Global.-1.lua` is the global script.
- **`src/fd/` is never edited in game.** Entry scripts `require("fd.…")` and the
  extension inlines those modules on Save & Play.
- **Generated files carry a banner comment.** `src/fd/data/maps.lua` and
  `src/entry/Custom Board.9e2fe8.xml` come from `tools/extract/maps.json` — edit
  the JSON and rerun `tools/extract/gen_registry.py`, never the output.
  `src/fd/data/dice.lua` likewise comes from `tools/extract/dice_faces.json`
  via `gen_dice.py`.
- **`fd.core` and `fd.rules` make no TTS calls.** They are tested under real
  Lua 5.2 (`tools/test_lua.py`). Anything touching objects, UI or `Wait` goes
  in `fd.tts` or the entry scripts. `tests/tts_stub.lua` fakes just enough of
  the TTS API to run `Global.-1.lua`; extend it when the Global script needs more.
- **Rulesets express wear as `{ zone = points }`.** The basic rules have one
  zone (`wp`); keep new rules in that shape so the advanced zones slot in.
- **`reference/original-2020/` is a read-only snapshot** of the mod as inherited.
  Useful for checking behaviour was preserved; not part of the build.

## Which extension

The pipeline here is built for **TTSLua** (`rolandostar.tabletopsimulator-lua`).
If **TTS Editor** (`sebaestschjin.tts-editor`) is also installed, both bind
Ctrl+Alt+S and Ctrl+Alt+L, and TTS Editor may take them. It keeps scripts in
`<workspace>/.tts/objects/` and fails with a missing `.tts` folder here. Use
"TTSLua: Save And Play" from the command palette, or disable TTS Editor for
this workspace.

TTSLua's Save & Play also refuses to run ("The workspace does not contain the
Tabletop Simulator folder") unless its temp folder is open as a workspace
folder. Open `formula-d.code-workspace`, which includes it. Running "Get Lua
Scripts" adds it too, but overwrites the temp folder with the in-game scripts,
so `sync.ps1 push` again afterwards.

## Module resolution

The extension searches, in order: `~/Documents/Tabletop Simulator/`, then
`TTSLua.includeOtherFilesPaths`, then each open workspace folder.

**The junction created by `tools/setup-dev.ps1` is what actually resolves
`require("fd.…")` here.** It puts `src/fd` under `~/Documents/Tabletop Simulator/`,
which is searched unconditionally. Do not remove it.

`.vscode/settings.json` does *not* help in the current setup. TTSLua's settings
are window-scoped (their `scope` is unset, which defaults to `window`), and
window-scoped settings are ignored in a folder-level `.vscode/settings.json` once
the workspace is multi-root — which this one is, since it holds both the repo and
the TTS temp folder. Opening `formula-d.code-workspace` puts the same settings at
workspace level, where they do apply; the file is kept in sync with
`.vscode/settings.json`, which covers the single-folder case.

Note the path must be **absolute** — the extension does not expand
`${workspaceFolder}` — which is why `setup-dev.ps1`, deriving it from the repo
location, is the portable one.

## Before pushing to the game

```powershell
python tools/check_lua.py      # luaparser syntax check over src/
python tools/test_lua.py       # lupa: rules + Global wiring tests
pwsh tools/sync.ps1 push
```

TTS reports script errors only after the mod loads, so the syntax check is worth
the two seconds.

## Design constraints to respect

- **Advisory, never blocking.** Highlight legal moves, warn on illegal ones,
  apply damage automatically — but always let a player put a car where they want.
  Track data is extracted from images and will be imperfect; a rules bug must
  never be able to wedge a game.
- **Both rulesets.** Formula D (modern) and Formula Dé (classic) share a core
  engine and are switched at setup, with per-rule toggles for optional modules.
  Do not bake modern-only concepts (gearbox/body/suspension wear) into the core.
- **Track data is pixel-space.** See `docs/track-format.md`. Do not store world
  coordinates in track files — the board tile is movable.

## TTS gotchas worth remembering

- UI handlers are called as `(player, value, elementId)`, where `value` is the
  argument in the attribute: `onClick="selectMap(FDMonaco)"`.
- `getObjectFromGUID` returns `nil` for objects inside containers or not yet
  spawned; guard it in `onLoad`.
- TTS imports OBJ meshes with X mirrored. Anything derived from a mesh file
  (die faces, dashboard slots) must negate X to match object local space.
- The dashboard is one model: advanced face on +Y, beginner face on −Y (the
  beginner bag spawns it flipped). `getTransformUp().y` tells them apart.
- Steam asset URLs saved as `cloud-3.steamusercontent.com/...` now answer 403.
  Objects still load from the local TTS cache, so a stale URL only shows up
  when something fetches it fresh (custom UI assets): use the
  `steamusercontent-a.akamaihd.net/ugc/<same path>` form instead.
- Changing a tile's image requires `setCustomObject` followed by `reload()`, and
  `reload()` invalidates the old object reference.
