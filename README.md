# Formula D — Tabletop Simulator (scripted)

Turning the Big Box Formula D / Formula Dé TTS mod from a map browser into a
fully scripted mod: automatic gear dice, rules automation, space snapping,
damage tracking, and movement highlighting.

## Where things stand

The 2020 mod shipped no game logic at all — it swapped a JPEG onto a board tile.
That original is preserved verbatim in [`reference/original-2020/`](reference/original-2020/).

| Objective | State |
|---|---|
| Project scaffold, build pipeline | done |
| Auto gear dice selection | not started |
| Rules automation | not started |
| Space snapping + facings | blocked on track data |
| Damage tracking | not started |
| Movement limits + highlighting | blocked on track data |

## Design decisions

- **Rulesets:** Formula D (modern) and Formula Dé (classic), switchable at setup,
  with individual toggles for the optional rules each supports.
- **Enforcement:** advisory. The mod highlights legal spaces, warns on illegal
  moves and applies damage automatically, but never blocks a player. Bad track
  data or a rules bug must not be able to wedge a game.
- **Track data:** extracted from the map images, calibrated against the board
  tile. See [`docs/track-format.md`](docs/track-format.md).

## Layout

```
src/entry/      one file per TTS object, named <Object>.<guid>.lua — these are
                what the TTS extension exchanges with the game
src/fd/         modules pulled in via require(); never edited in game
  data/maps.lua   generated map registry (339 tracks)
tracks/         per-track space graphs (see docs/track-format.md)
tools/          extraction, generation and sync scripts
reference/      verbatim snapshot of the 2020 mod
```

## Working on it

First time on a machine:

```powershell
pwsh tools/setup-dev.ps1     # junction src/fd into the folder the bundler always searches
```


The TTS extension (`rolandostar.tabletopsimulator-lua`) exchanges scripts through
a folder under `%TEMP%`, which Windows can clear at any time — so this repo is the
source of truth and `tools/sync.ps1` moves files in and out.

```powershell
pwsh tools/sync.ps1 status     # what differs between repo and TTS
pwsh tools/sync.ps1 push       # repo -> TTS, then "TTSLua: Save And Play"
pwsh tools/sync.ps1 pull       # TTS -> repo, after "Get Lua Scripts"
```

An entry script can `require("fd.data.maps")` and the extension inlines it on
Save & Play. `.vscode/settings.json` makes that resolve while the repo is open as
the VS Code workspace root; `setup-dev.ps1` adds a junction that resolves it
regardless, for when a script is opened from the temp folder in its own window.

The setting needs an **absolute** path (the extension does not expand
`${workspaceFolder}`), so `setup-dev.ps1` is the portable one — it derives the
path from the repo location.

Before pushing:

```powershell
python tools/check_lua.py      # syntax-check everything under src/
```

### Regenerating the map registry

`tools/extract/maps.json` is the source of truth for the 339 tracks. Editing it
and regenerating keeps the Lua registry and the selection UI in step:

```powershell
python tools/extract/gen_registry.py
```

Re-deriving `maps.json` from the 2020 originals (rarely needed):

```powershell
python tools/extract/extract_maps.py
```

## Note on the 2020 map selector

The original kept each track in three hand-maintained places: a URL in one of
three Lua tables, a three-line `setupXxx()` handler, and an XML button. Keeping
339 tracks × 3 in sync by hand had already drifted — the **Viamao** button's
`onClick` was missing its `setup` prefix, so that track could not be selected at
all. Both sides now generate from `maps.json`; the fix came along for free.
