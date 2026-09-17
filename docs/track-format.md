# Track data format

*Draft. Nothing consumes this yet — it is the target the vision-based extraction
and the movement code are both being written against, and it will change once
the first real track goes through the pipeline.*

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

  "spaces": [
    {
      "id": 1,
      "pos": [1204, 880],        // pixel centre of the space
      "rot": 47.5,               // degrees; car's facing when parked here
      "lane": 1,                 // 1 = innermost
      "next": [2, 14],           // legal successors (lane changes included)
      "corner": null,            // corner id when this space is inside one
      "sector": 0                // ordinal along the lap, for lap counting
    }
  ],

  "corners": [
    {
      "id": 1,
      "stops": 2,                // mandatory stops required
      "line": [41, 42, 43]       // the spaces forming the corner's stop line
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

Track files are produced by reading the map image and identifying spaces
visually, then calibrating against the tile. The scale reference has to come
from the game — measuring the tile once yields the pixels-per-world-unit figure
every track then reuses.

Tracks are expected to need hand correction after extraction; the advisory
enforcement model means an imperfect track file degrades gracefully rather than
blocking play, which is why it was chosen.
