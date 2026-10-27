# The browser track editor

`tools/editor/` edits track files in a browser, runs the detector on a board
image while you watch, and lets Claude work on the same track at the same
time. It is the quick way to fix spaces, links, lanes, the grid and the
board layout; play-testing a track is still a job for TTS.

```powershell
python tools/editor/server.py              # opens http://127.0.0.1:8765
python tools/editor/server.py FDMonaco     # with a track open
python tools/editor/test_editor.py         # its tests
```

It needs what the extraction tools need (`tools/requirements-dev.txt`):
lupa, OpenCV, numpy, scipy, scikit-image.

## How it fits together

The server holds one editing session, shared by every page that is open on
it and by Claude's command line, `tools/editor/fdedit.py`. Neither the page
nor Claude changes a track itself: each edit goes to the server as an op
(`tools/editor/trackdoc.py` lists them), the server applies it and sends the
result to everyone. Relinking and the problem list come from
`fd.core.trackgraph`, run under Lua 5.2 through lupa, so the rules are the
in-game editor's exactly:

- moving, turning, adding or deleting a space, or changing its lane,
  relinks the track;
- a link made by hand marks its space `fixed`, and relinking leaves it
  alone until you hand it back (**U**, or **Auto** on the Space tab);
- opening a track relinks it, as the in-game editor does; when that changes
  links the file had, the chat panel says how many.

**Save** writes `tracks/<id>.json` in the shape `import_track.py` writes
from a game (`edited: true`, `edited_from: "web editor (…)"`) and
regenerates the Lua modules. It first gives the spaces their codes again
(`tools/extract/renumber.py`), so a space added as `m.c3.3+1` in the inside
lane comes out as `i.c3.1`, and the spaces after it in its lane move up one.
Undo starts afresh after a save that renamed spaces. If spaces moved, came or went it also reruns
`find_adjacency.py`. After that, `pwsh tools/sync.ps1 push` and Save & Play
as usual.

Unsaved edits are kept in `tools/extract/out/web/_session/`, so stopping
the server loses nothing. They come back the next time the track is opened,
until it is saved or reverted.

## Editing

| | |
|---|---|
| Drag a space | move it, with the rest of the selection |
| Wheel while dragging | turn what you carry, 15° a notch (Shift: 2°) |
| Drag the board, wheel | pan, zoom |
| Shift-click, shift-drag | add to the selection, select a box |
| Ctrl-click a space | toggle a link from the selected space to it |
| Q / E | turn 15° (Shift: 2°) |
| Arrow keys | nudge 1 px (Shift: 5) |
| 1 2 3 | lane |
| A, or double-click | add a space at the pointer |
| Delete | delete |
| U | links back to automatic |
| G | grid place on or off, pole first |
| F | fit the board, or the selection |
| Hold H | hide cars and links, to read the board under them |
| C | ask Claude |
| Ctrl+Z / Ctrl+Y / Ctrl+S | undo, redo, save |

The cars are drawn as **outlines** by default, so the arrows printed in
each cell stay visible. **dot** shows even more of the board, and **solid**
is easiest to read zoomed out. The style and the opacity slider beside it
are remembered per browser. Gold links are `fixed`; dashed ones change
lane. Red rings are problems; your selection is cyan, Claude's magenta.

The Space tab edits the selected space's lane, facing and position, and
lists its links in and out (✕ removes one). It also places the dice tray and
turns the dice. (It can still set a track's race panel spot, which the game
no longer uses: the panel is on the screen.)

## Detection

On the Detect tab, pick a mapped board, or choose an image (or drop one
anywhere on the board), and **Run**. The detector scripts
(`find_grid.py`, then `find_corners.py`, `find_arrows.py --write` and
`find_adjacency.py`) run in a scratch folder, `tools/extract/out/web/<id>/`,
pointed there with `FD_TRACKS_DIR`, `FD_OUT_DIR` and `FD_BOARD_IMAGE`. Each
step's picture appears on the board as soon as it is written. Once
`find_grid.py` has its spaces the draft opens, and the later steps fill it
in. Every step image stays on the Detect tab to lay under the track
(opacity slider in the bar).

A draft is a track like any other: edit it, save it (into the scratch
folder). For a board in `maps.json`, **Promote** writes it to
`tracks/<id>.json`. That refuses to replace a hand-edited track unless you
confirm. A draft from the detector alone is promoted unedited, so the
detector can still run over it later. Stop counts and the pit lane are read
by eye, as before (`find_corners.py --stops`, `find_pit.py`).

Read as *rungs* suits pale grids like Monaco's, *cells* crisp ones like
Austin's; tick *Lap runs the other way* if the facings come out backwards.

## Working with Claude

Ask Claude in the terminal to join the editor. It watches for your messages
and answers in the **Claude** tab. Each message carries your selection,
the space under your pointer and your view, so "is this fork right?" with
the spaces selected is enough. Claude can look at the board as edited,
select and point at spaces (a magenta ring, and your view follows if
*Follow Claude's pointer* is on), pin notes, and edit. Its edits appear as
they are made, flash in magenta, and go on the same undo stack as yours.
The dot in the top right is lit while Claude is listening.
