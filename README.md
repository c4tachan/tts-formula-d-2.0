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
| Auto gear dice selection | done (shared dice set, results read automatically) |
| Rules automation | Formula D basic rules, except those needing track positions |
| Track data | Monaco done: 497 spaces (detected, then hand-edited in game) and its 10 corners with their stop counts |
| Space snapping + facings | next -- the data it needs now exists for Monaco |
| Damage tracking | done for the basic rules' single 18 WP pool |
| Movement limits + highlighting | next, on the same track data |

### What the basic rules cover today

- **Dashboards are the controls.** Each dashboard carries a row of buttons
  past its bottom edge: *Join race* when free; once claimed, a status line
  plus Brake, Overshoot, Collision?, WP −1/+1 (right-click to add), Pit stop
  and Leave.
- **Cars:** the **Car** button claims the nearest free car, or takes one from
  the bag and tints it your colour; dropping a car on your dashboard claims it
  too. Nothing uses the claim yet -- it is what movement and snapping will
  hang off.
- **Gears:** drop your gear stick on a slot to change gear. That die comes
  from the shared set to your dashboard; an off-gate drop snaps back.
- **A copy of your dashboard on screen**, bottom right, visible only to you:
  the real texture with your gear stick and WP marker drawn on it, and the
  same action buttons. Clicking a gear slot shifts and clicking a wear number
  sets it, so the table copy and the screen copy stay in step. TTS cannot
  render a camera view of an object, so this is redrawn from the same slot
  data as the physical dashboard rather than being a true picture-in-picture.
- **Dice:** the six gear dice now have face values (derived from their meshes
  and textures; see `tools/extract/gen_dice.py`), so a roll is read when the die
  settles. Skipped-gear wear is charged when the die is rolled, not when the
  gear is clicked.
- **Black die checks:** start (stall / great start), engine strain (queued
  automatically for every car in 5th/6th on a 20 or 30), collision (on request)
  and grid position (ties re-roll). Whoever rolls the black die resolves their
  own oldest check, or the table's oldest if they have none.
- **Moves:** a car put down after its roll is judged against the track (Monaco
  so far): braking and corner overshoots are charged, corner stops are
  counted from move to move, and missing two or more stops puts a car out.
  Putting the car down again re-judges the move; nothing is ever refused.
- **Wear:** pit stop and manual ±1 buttons; elimination at
  0 WP. The WP marker follows on the beginner side of the dashboard, and
  dropping it on a number sets WP to that number.
- **Rounds:** a round ends once every running car has moved (stalled cars sit
  it out).
- **Undo** on the race panel covers any of the above.

Not yet automated: collision adjacency, turn order, laps, and the pit lane
(see the GitHub issues). Collision and pit stop have buttons in the meantime,
and on a board without track data, braking and overshoots are the WP -1
button.

### Playing

1. Take a car and a dashboard from the Beginner Dashboard bag.
2. Click **Join race** under the dashboard. It gets a gear stick and WP
   marker in your colour.
3. Optionally **Grid roll** on the race panel (top left), then **Start**; each
   player rolls the black die for their start.
4. On your turn move the gear stick, roll the die that arrives, move your car.

### Track data: detect, then edit in game

A track's spaces start from `python tools/extract/find_grid.py <mapId>`, which
reads the grid printed on the board image and writes `tracks/<mapId>.json`;
`find_corners.py <mapId>` then marks which spaces lie inside each corner, and
`find_arrows.py <mapId> --write` turns the printed arrows into the links -- from
`tracks/<mapId>.arrows.json`, a reading of which spaces fork, where there is one
(`arrow_sheets.py` makes the close-ups to read it from).
Each numbered image it leaves in `tools/extract/out/` is one step, for
checking by eye. Detection is a starting point; the cleanup happens in TTS:

1. Put the map on the board and press **Edit track** on the race panel. Every
   space is drawn with a tick to the space ahead in its lane; red ones need a
   look.
2. **Right-click the board > Pick up spaces here** turns the nearby spaces
   into blocks. Drag them, turn them with Q/E, and right-click one for its
   lane, to delete it, or to link it by hand (*Start a link here*, then *Link
   to here* on the next space; *Automatic links* hands it back). **Add a space
   here** puts a new one down. **Apply** puts the blocks back and relinks.
3. Save the game (*Menu > Save*), then `python tools/extract/import_track.py`
   writes the edits to `tracks/<mapId>.json` and regenerates the Lua module.
   A hand-edited file is never overwritten by the detector.

The editor's keys can also be bound in *Options > Game Keys*, under "Track
editor".

## Design decisions

- **Rulesets:** Formula D (modern) and Formula Dé (classic), switchable at setup,
  with individual toggles for the optional rules each supports. Only the modern
  basic rules exist so far (`src/fd/rules/beginner.lua`). A ruleset states all
  wear as zone → points, so the advanced rules' six zones fit the same engine.
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
  core/           rules bookkeeping and the track graph -- no TTS calls, unit tested
  rules/          one module per ruleset (beginner so far)
  tts/            dice, dashboards, on-screen panels -- the TTS-facing side
  data/maps.lua   generated map registry (339 tracks)
  data/dice.lua   generated gear dice rotation values
  data/dashboard.lua  slot positions on the dashboard model
  data/tracks/    generated from tracks/*.json by gen_tracks.py
tests/          Lua tests, run under real Lua 5.2 with a fake TTS API
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

Use **TTSLua: Save And Play** from the command palette. If the TTS Editor
extension (`sebaestschjin.tts-editor`) is also installed, it shares the
Ctrl+Alt+S shortcut and fails here looking for a `.tts` folder. Disable it for
this workspace, or run the command by name.

An entry script can `require("fd.data.maps")` and the extension inlines it on
Save & Play. The junction from `setup-dev.ps1` is what makes that resolve, and it
works whatever VS Code has open — run it before anything else.

`TTSLua.includeOtherFilesPaths` can do the same job, but it is window-scoped, so
a folder-level `.vscode/settings.json` is ignored in a multi-root workspace. Open
`formula-d.code-workspace` to get it at workspace level where it applies.

Before pushing:

```powershell
pip install -r tools/requirements-dev.txt   # once
python tools/check_lua.py      # syntax-check everything under src/
python tools/test_lua.py       # rules and Global wiring tests
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

### Regenerating the dice data

`tools/extract/dice_faces.json` holds the number on every gear die face. To
turn it into `src/fd/data/dice.lua`:

```powershell
python tools/extract/gen_dice.py
```

`extract_dice.py` redraws the numbered face crops the values were read from
(it needs the mod in the local TTS cache; set `TTS_MODS` if Documents is
redirected).

## Note on the 2020 map selector

The original kept each track in three hand-maintained places: a URL in one of
three Lua tables, a three-line `setupXxx()` handler, and an XML button. Keeping
339 tracks × 3 in sync by hand had already drifted — the **Viamao** button's
`onClick` was missing its `setup` prefix, so that track could not be selected at
all. Both sides now generate from `maps.json`; the fix came along for free.
