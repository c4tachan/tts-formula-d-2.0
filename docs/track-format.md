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
      "id": 1,
      "pos": [1204, 880],        // pixel centre of the space
      "rot": 47.5,               // degrees; car's facing when parked here
      "lane": 1,                 // 1 = innermost
      "next": [2, 14],           // legal successors (lane changes included)
      "fixed": true,             // optional: `next` was set by hand; never recomputed
      "corner": null,            // corner id when this space is inside one
      "sector": 0                // ordinal along the lap, for lap counting
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

  "start": [101, 102, 103],      // grid positions, pole first
  "finish": { "line": [1, 2, 3] },

  "pit": {                       // omitted on tracks without a pit lane
    "entry": 210,
    "exit": 224,
    "spaces": [211, 212]
  }
}
```

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

Links are worked out from positions and facings (`fd.core.trackgraph`), the
same rules the in-game editor uses; a space whose links were set by hand keeps
them (`fixed`).

Tracks are expected to need hand correction after extraction -- the editor in
TTS is for that, and `tools/extract/import_track.py` brings the result back
from a saved game. The advisory enforcement model means an imperfect track file
degrades gracefully rather than blocking play, which is why it was chosen.
