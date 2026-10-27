# Working in this repo

Tabletop Simulator mod for Formula D / Formula Dé. Lua 5.2-ish (TTS's dialect),
plus Python tooling for data extraction.

## Rules of the road

- **`src/entry/` files are TTS objects.** The filename encodes the object GUID
  (`Game Board Tile.ebde54.lua`) and must not be renamed — the extension matches
  objects by it. `Global.-1.lua` is the global script.
- **`src/fd/` is never edited in game.** Entry scripts `require("fd.…")` and the
  extension inlines those modules on Save & Play.
- **Generated files carry a banner comment.** `src/fd/data/maps.lua` comes
  from `tools/extract/maps.json` — edit the JSON and rerun
  `tools/extract/gen_registry.py`, never the output.
  `src/fd/data/dice.lua` likewise comes from `tools/extract/dice_faces.json`
  via `gen_dice.py`.
- **The move icons are drawn by `tools/make_icons.py`** into `assets/icons/`
  and loaded in game from GitHub, at the commit that last changed them. After
  changing an icon: run it, commit and push the PNGs, then
  `python tools/make_icons.py --pin` rewrites `src/fd/data/icons.lua` with
  that commit. A pin to a commit that isn't pushed yet won't load.
- **Every other asset loads from the repo too.** Meshes, textures and UI
  images are in `assets/raw/` (`manifest.json` records the Steam URL each came
  from and what uses it), board images in `tracks/raw/`. Lua names an asset by
  its Steam URL and passes it through `Assets.url()` (`fd.data.assets`, made by
  `tools/pin_assets.py`); compare board images with `Assets.same()`, since older
  saves hold the Steam form. After adding or changing an asset: run
  `tools/extract/download_assets.py` (or `download_maps.py`), commit and push,
  then `python tools/pin_assets.py`; `--save` also writes a copy of the latest
  save with its objects pointing at the repo. Every player loads these URLs,
  so the repo stays public and keeps its name, and pinned commits must stay
  reachable: merge PRs with a merge commit, never squash, and never
  force-push `master`.
- **The save to publish is `Saves/Formula D - clean.json`** in the TTS folder
  (SaveName "Formula D"): at setup, no cars, hand zones at the table's rim.
  Save & Play saves whatever is on the table into the loaded save, so load
  it fresh before Save & Play, never with a race on the table.
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
python tools/test_lua.py --bench   # optional: UI updates / game calls per action
python tools/editor/test_editor.py # when tools/editor/ or fd.core.trackgraph changed
pwsh tools/sync.ps1 push
```

TTS reports script errors only after the mod loads, so the syntax check is worth
the two seconds.

## Editing tracks with the user in the browser editor

`tools/editor/server.py` serves a track editor at http://127.0.0.1:8765
(docs/track-editor.md). When the user asks you to join it or work on a track
with them there:

- Start the server in the background if it is not up
  (`python tools/editor/fdedit.py status` says), then arm a Monitor on
  `python tools/editor/fdedit.py listen` with the longest timeout, and re-arm
  it on expiry. Each line is a message from the user's chat panel, with their
  selection, hover and view. Answer with `fdedit.py say`, not only in the
  terminal: they are looking at the page.
- Look before you edit: `fdedit.py snapshot <scratchpad>/x.png --view user`
  (or `--around ID,..`, `--box`) and Read the PNG. Spaces are drawn as
  outlines so the printed arrows show; add `--no-labels --no-links` to read
  the print itself. `space ID`, `problems`, `spaces --box` give the data.
- Edit through `fdedit.py` (`move`, `link`, `lane`, `unfix`, `ops '[...]'`),
  never by writing the track file while the server has it open: the server's
  working copy would overwrite yours. Batch related changes into one `ops`
  call so they undo as one step. `select`/`focus` point the user at spaces,
  `note` pins a remark on the board.
- Saving is the user's call unless they ask you to (`fdedit.py save`).

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

- TTS runs MoonSharp, not real Lua. Inside a function, a bare `local x` is not
  reliably `nil` -- it can hold a leftover value from an earlier variable, which
  real Lua (and so our tests) never shows. Write `local x = nil`;
  `tools/check_lua.py` rejects the bare form.
- Every `UI.setAttribute`/`setValue` goes to every player's client, and calls
  into the game (`getObjects()`, object methods) are slow next to plain Lua.
  Send UI updates through `fd.tts.ui` (`Ui.set`/`Ui.value`), which drops
  repeats, and call `Ui.reset()` after any `UI.setXmlTable`. Keep lists of
  objects you need (see `Dashboard.all()`, `Dice.find`) rather than scanning
  the table. `python tools/test_lua.py --bench` counts these per action.
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
- The board tile is scaled unevenly (44 × 1 × 26). The icon decals are placed
  and sized in its local space and kept square to it (rotation `{90, 180, 0}`,
  scale divided per axis), since a child turned on an unevenly scaled parent
  comes out skewed. `setDecals` replaces every decal on the object, and a save
  keeps them, so `onLoad` sends the board's decals afresh.
