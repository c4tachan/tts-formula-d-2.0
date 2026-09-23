# Track data format

*Monaco is the first track through the pipeline; `start`, `finish` and `pit`
are still empty there, and will settle once they are filled in.*

Everything in objectives 3 and 5 (snapping, facings, movement limits,
highlighting) reduces to one problem: the mod has no idea where the spaces are.
A track file supplies that — one JSON file per track in `tracks/<mapId>.json`,
keyed by the `id` from `tools/extract/maps.json`.

## Coordinate model

Spaces are stored in **image pixel coordinates**, not TTS world coordinates.

The board image is swapped at runtime onto a single tile, and that tile can be
moved, rotated or rescaled by players. Pinning the data to pixels means a track
file stays valid however the tile is placed, and one calibration step converts
to world space at load:

```
world = tileCenter + rotate((pixel - imageCenter) * scale, tileRotation)
```

`scale` comes from the tile's world width divided by the image's pixel width, so
the only thing needing measurement in game is the tile itself — not each track.

## Schema

```jsonc
{
  "id": "FDMonaco",              // matches maps.json
  "name": "Formula D: Monaco",
  "ruleset": "formula_d",        // formula_d | formula_de
  "image": { "width": 4096, "height": 3072 },

  "lanes": 3,                    // widest point of the track
  "laps": 2,

  "edited": true,                // hand-edited in game: the detector leaves it alone
  "edited_from": "TS_Save_3.json (2026-09-18 15:27)",

  "spaces": [
    {
      "id": "m.c1.0",            // the space's code, <lane>.<sector>.<n> (below)
      "pos": [1204, 880],        // pixel centre of the space
      "rot": 47.5,               // degrees; car's facing when parked here
      "lane": 2,                 // 1 = innermost
      "next": ["m.c1.1", "i.c1.1"], // legal successors (lane changes included)
      "fixed": true,             // optional: `next` was set by hand; never recomputed
      "corner": 1,               // corner id when this space is inside one
      "sector": "c1"             // the corner or straight it lies in
    }
  ],

  "corners": [                   // in running order from the start
    {
      "id": 1,
      "stops": 2,                // mandatory stops, from the corner's flag
      "spaces": 15,              // how many spaces lie inside it
      "lanes": [3, 5, 7],        // by lane, innermost first
      "long": 7, "short": 3      // the ways through printed in green and red
    }
  ],

  "start": ["m.s11.4", "i.s11.3"], // grid positions, pole first (below)
  "finish": { "line": [1, 2, 3] },

  "pit": {                       // omitted on tracks without a pit lane
    "entry": 210,
    "exit": 224,
    "spaces": [211, 212]
  }
}
```

## Space codes

A space's id is its code, `<lane>.<sector>.<n>`, given by
`tools/extract/find_corners.py`:

- **lane**: `i`, `m` or `o`, the inside, middle and outside lane of the lap
  (lanes 1, 2 and 3). This is fixed round the lap, not per bend.
- **sector**: `c1`, `c2`, ... for the corners, in running order from the finish
  line; `s1`, `s2`, ... for the straights, `sK` being the one that leads into
  `cK`. The straight from the last corner round to the finish line is one more
  (`s11` on Monaco).
- **n**: `0` for the first cell of the lane that touches the sector's leading
  edge, counting up in running order. At the finish line that is the cell the
  checkered band crosses; where the band lies on a cell boundary, as in a lane
  staggered against the others, it is the cell just past it.

## The starting grid

`start` is marked by hand in the editor: bind **Track editor: mark grid
space** (Options > Game Keys), then point at each grid space in turn, pole
first. Each one is ringed on the board -- pole twice -- with a line through
them in order, and its marker's name gains its place (`- grid 3`). Pressing
the key on a space already on the grid takes it off; **Clear the grid** on
the board's right-click menu starts again. `import_track.py` brings the list
out with the rest of the edits.

A fresh scan from `find_grid.py` has plain numbers for ids until
`find_corners.py` runs; that step renames every link and the arrow reading in
`tracks/<id>.arrows.json` to match. A space added in the editor is named
after the space nearest it, with `+n` on the end, until the next run.

## Why pixels and not a hand-built graph

`next` is stored explicitly rather than derived from proximity because Formula D
legality is not symmetric — lane changes are restricted while cornering, the pit
lane is one-way, and some tracks have spaces that are adjacent on the image but
not connected in play. Deriving adjacency from distance alone gets these wrong,
and they are exactly the cases players notice.

## Extraction

`tools/extract/find_grid.py` reads the grid printed on the board: it removes
everything that is not track, paints out the direction arrows, redraws the red
corner lines as grid lines, and cuts the road along its printed lines so each
cell comes out as one piece. A cell's lane comes from where it sits on its own
chord across the road, which stays right through corners where a traced racing
line drifts.

`tools/extract/find_corners.py` then finds the corners: it cuts the road along
the red lines painted across it, which leaves a ring of pieces that are corners
and straights in turn, and the piece with the start/finish band is a straight.
Each space takes the corner of the piece it sits in. It only writes `corner`
and `corners`, so it can be rerun on a hand-edited file.

Stop counts are printed in each corner's flag, along with the longest and
shortest way through it. They are read by eye off the crops the script leaves
in `out/_work/` and passed back with `--stops` and `--paths`; the path lengths
are then checked against the spaces found, since no lane may be shorter than
the shortest way or longer than the longest.

`tools/extract/find_arrows.py` reads the arrows printed on the road, which
are the rules in the corners: an arrow shows the moves out of the space it is
printed in. Each is read at its head -- two barbs meeting at an apex, pointing
the way they bisect -- because an arrow that curves round a hairpin finishes
well round from where it started. Four things about the board pin the reading
down: a move only ever goes to the next space along in this lane or the lane
either side, and never to one squarely alongside or not touching; every space
leads on down its own lane whatever is printed on it; and a one-headed arrow
means exactly that move, so only a second or third head crosses a lane. Those links are written `fixed`.

Reading how many heads an arrow has is where the detector is weak -- a fork
printed as two strokes, or a barb that looks like a head -- and a head is what
says whether a space forks at all. So which spaces fork is read by eye instead,
from close-ups `tools/extract/arrow_sheets.py` makes, into
`tracks/<id>.arrows.json`. When that file is there, `find_arrows.py` takes the
forks from it and uses the detector only to compare against.

Where each fork lands is then settled by rules that held on every corner of
Monaco, and that the editor checks too:

- a space in a corner forks one way across the lanes or the other, never both;
- two spaces in one lane never lead to the same space in the next lane;
- and those links never cross each other: a car moving over a lane keeps its
  place along the track.

Within one lane's run through a corner, then, the forks pair off with the lane
beside them in order. Where the lanes have different numbers of spaces some
space has to go without a fork, and the board prints a single arrow on exactly
that one -- which is how a misread fork shows itself.

Elsewhere links are worked out from positions and facings
(`fd.core.trackgraph`), the same rules the in-game editor uses; a space whose
links were set by hand, or read off an arrow, keeps them (`fixed`).

Tracks are expected to need hand correction after extraction -- the editor in
TTS is for that, and `tools/extract/import_track.py` brings the result back
from a saved game. The advisory enforcement model means an imperfect track file
degrades gracefully rather than blocking play, which is why it was chosen.
