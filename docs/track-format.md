# Track data format

*Monaco and Austin have been through the pipeline; their grids, finish
lines and pit lanes are all marked.*

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
      "sector": "c1",            // the corner or straight it lies in
      "pit": true,               // optional: in the pit lane (below)
      "box": "Brown"             // optional: a pit box, and the seat it belongs to
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
  "finish": { "line": ["i.s1.0", "m.s1.0", "o.s1.0"] }, // (below)
  "dice": [1505, 1468],          // optional: where the dice sit, clear of the track
                                 // (the map's name panel); default the board's middle
  "dice_side": "up",             // optional: the tray side, on the image, the dice not in
                                 // play line up along; default the side facing the middle
  "panel": { "pos": [2172, 1410], "width": 400 }, // optional: the race panel's centre
                                 // and width, on an empty patch; default on the screen

  "pit": {                       // omitted on tracks without a pit lane (below)
    "entry": ["i.s11.0", "i.s11.1"], // the track spaces that lead into it
    "exit": ["i.s1.1", "i.s1.2"],    // the track spaces it leads out to
    "spaces": ["p.s11.0", "p.s11.1", ...], // entry to exit
    "boxes": [{                  // the pit boxes, in running order
      "space": "b.s11.3",        // the pit box itself
      "beside": "p.s11.3",       // the pit lane space that is its way in and out
      "colour": "white",         // as printed
      "player": "White",         // the seat it belongs to
      "garage": { "pos": [207.3, 1172.1], "rot": 267.3, "size": [41.2, 35.6] }
    }, ...]
  }
}
```

## Space codes

A space's id is its code, `<lane>.<sector>.<n>`, given by
`tools/extract/find_corners.py`:

- **lane**: `i`, `m` or `o`, the inside, middle and outside lane of the lap
  (lanes 1, 2 and 3). This is fixed round the lap, not per bend. `p` is
  the pit lane (below), lane 0 wherever it lies, and `b` a pit box, coded
  after the pit lane space beside it.
- **sector**: `c1`, `c2`, ... for the corners, in running order from the finish
  line; `s1`, `s2`, ... for the straights, `sK` being the one that leads into
  `cK`. The straight from the last corner round to the finish line is one more
  (`s11` on Monaco).
- **n**: `0` for the first cell of the lane that touches the sector's leading
  edge, counting up in running order. At the finish line that is the cell the
  checkered band crosses; where the band lies on a cell boundary, as in a lane
  staggered against the others, it is the cell just past it.

## The finish line

`finish.line` is the line as the space just past it in each lane: the `n = 0`
cell of `s1`, which is where the space codes start counting. A move that
steps onto one of these has crossed the line (`crossed` on each option from
`fd.core.moves`); starting on one does not count. That takes every link over
the line to land on one of them, never further into `s1`, which
`tests/test_moves.lua` checks for Monaco. `find_corners.py` writes it along
with the codes.

Where the pit lane runs past the line, it has a space on the line too: the
pit cell the checkered band would cross if it were carried on over the pit
road -- or, where the band would lie along a division (Austin), the cell
just past it. A car leaving the pits crosses the line there.

## The pit lane

The pit lane is lane 0, its spaces marked `pit` and coded `p.<sector>.<n>`
like the rest, counting from 0 at the entry and starting again at the
finish line. It is one lane, so each space leads on to the next and nothing
else. At each end it opens into a merge space, and every track space
touching a merge is a way in or out: each one touching the entry merge
leads into it (`pit.entry`), and the exit merge leads to each one touching
it (`pit.exit`). Those are the only links between the pit lane and the
track, and the only ones that may step square across rather than ahead: a
merge is beside the spaces touching it. All of the pit lane's links are
`fixed`; the editor's relinking never links across its wall, and keeps the
ways in and out, of the pit lane and of its pit boxes.

Each team's garage is printed beside two cells of the pit lane, a car
drawn in each; on Monaco there are five teams. There are ten seats at the
table, so each of those cells is one seat's, and the half of the garage
beside it is that seat's pit box, where its car stops to make a pit stop.
Each printed colour is shared by the two seats nearest it in hue -- white
by White and Brown, yellow by Yellow and Orange, green by Green and Teal,
red by Red and Pink, blue by Blue and Purple -- the first cell of the
colour going to the first seat.

The garages can lie on either side of the pit lane: on Monaco between it
and the track, on Austin along its wall. `find_pit.py` takes the side
where the ground beside the pit lane is coloured.

A pit box is a space of its own (`b.<sector>.<n>`, `pit`, with `box` the
seat it belongs to), at the middle of its garage half. It links both ways
with the pit lane space beside it (`beside` in `pit.boxes`): a car goes in
from there and comes back out the same way, a step each, square across.
`fd.core.moves` opens a pit box only to the car of its seat (`opts.color`).
`garage` is the garage half as a rectangle (centre, the way its length
runs, length by depth, in pixels), which the mod paints in the seat's
colour (`fd.tts.track`, `Track.pits`).

When a car may take the way into the pit lane is the ruleset's to say:
`fd.core.moves` leaves it shut unless asked (`opts.pit`), and the race asks
when the ruleset's `mayPit` says so -- in the basic rules, at the end of
any lap but the last. The rest is rules too (`fd.rules`, `fd.core.race`),
not track data: a car that ends its move in its own pit box makes its pit
stop, with no exact roll needed to get there; braking, shifting down,
collisions and engine strain do not count in the pit lane
(`pitLaneExempt`); and cars there play after those on the circuit
(`pitLanePlaysLast`).

`tools/extract/find_pit.py` finds the pit lane's cells and the garages,
and writes all of this. The two ends -- the slanted last divisions and the
merge spaces past them -- are read by eye, and kept in the script with the
colours printed on the garages. Which track spaces touch a merge is read off the print: two cells
touch where only a grid line lies between them, never a wall.

## The starting grid

`start` is marked by hand in the editor: bind **Track editor: mark grid
space** (Options > Game Keys), then point at each grid space in turn, pole
first. Each one is ringed on the board -- pole twice -- with a line through
them in order, and its marker's name gains its place (`- grid 3`). Pressing
the key on a space already on the grid takes it off; **Clear the grid** on
the board's right-click menu starts again. `import_track.py` brings the list
out with the rest of the edits.

Where the grid boxes are printed with their numbers, as on Austin, the
list can be read straight off the board into the track file instead.

## The dice and the race panel

`tools/extract/find_dice_spot.py` gives a track its first `dice` and
`dice_side`: the tray over the board's name logo (the Formula D name card,
or the Formula Dé checkered title box), turned and nudged to keep the
parked dice as clear of the track as it can. It leaves a track that has a
spot already alone (`--force` replaces it).

`dice` and `panel` are set in the game, from the board's right-click menu
(the host only, editor open or not): **Put the dice here** moves the dice
tray to where you clicked, **Turn the dice** moves the row of dice not in
play a quarter turn round the tray, **Put the race panel here** centres the panel
there, and **Race panel larger** / **smaller** change its width by 15% a
step (150 to 1600 pixels). The tray and panel move at once. The same five
can be bound as keys under "Board layout" in Options > Game Keys. They are
kept with the track's edits: save the game and `import_track.py` writes
them into the track file with the rest.

A fresh scan from `find_grid.py` has plain numbers for ids until
`find_corners.py` runs; that step renames every link and the arrow reading in
`tracks/<id>.arrows.json` to match. A space added in the editor is named
after the space nearest it, with `+n` on the end, and a space moved to
another lane keeps its old letter, until the codes are worked out again:
`tools/extract/renumber.py` does that from the track file alone -- each
lane followed round from the finish line, numbered within the sectors its
spaces have -- renaming the space everywhere it is named, and the browser
editor runs it on every save. It needs each lane to be one loop of links.

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

Boards differ in how the grid is printed. Monaco's is pale, and is read as
rungs: the divisions across each lane, with gaps filled in where one is too
faint to see. Austin's is printed dark and crisp, and reads better as cells
(`--cells`): each patch of asphalt the lines enclose is a space. A patch
spanning more than a lane is cells whose lines were painted out with the
flag, and is cut up by lane and along the lap; one lane wide it is one cell
however long, since the inside of a hairpin and the outside of a bend have
cells twice the usual size. The choice is kept in the track file's
`detect.read`, with `detect.reverse` for which way round the lap runs, so a
rerun reads the board the same way.

Austin's board also prints its run-off and service roads in the same grey
as the track, but warm where the asphalt is cool, so only the cool grey
counts as road (`detect_track.asphalt`).

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

A fork normally lands on a space ahead of it. The one exception is a
hairpin's exit, where the lane on the inside has cells twice as long, and
the one an arrow points into starts level with the fork. A fork the reading
is sure of that finds nothing ahead may take a space squarely alongside, if
no other fork has it and the links stay in order (Austin's Turns 1, 5 and 7).

Elsewhere links are worked out from positions and facings
(`fd.core.trackgraph`), the same rules the in-game editor uses; a space whose
links were set by hand, or read off an arrow, keeps them (`fixed`).

`tools/extract/find_pit.py` adds the pit lane, which `find_grid.py` leaves
out; see [The pit lane](#the-pit-lane). The other scripts set it aside, so
it survives them.

`tools/extract/find_adjacency.py` answers a different question from the
links: which spaces touch, in any direction and whatever the arrows say. That
is what a collision check needs -- a car ending its move rolls the black die
once for each car on a space touching its own, and the contact spreads through
the cars touching those until every touching pair has rolled once each way.
Each patch of road goes to its nearest space, and two spaces touch when their
patches share an edge and the line between them crosses no kerb (which keeps
the two legs of a hairpin apart). The next space along the same lane always counts, since the lanes
either side pinch that border to nothing. It reads the spaces from
`tracks/<id>.json` as edited and writes the pairs to
`tracks/<id>.adjacency.json`, which `gen_tracks.py` turns into `T.near` in the
Lua module. Rerun both after moving spaces. The check image goes to
`out/<id>_adjacency.png`.

Tracks are expected to need hand correction after extraction. The browser
editor (`tools/editor/`, see [track-editor.md](track-editor.md)) writes the
track file directly; the editor in TTS works too, and
`tools/extract/import_track.py` brings its result back from a saved game. The advisory enforcement model means an imperfect track file
degrades gracefully rather than blocking play, which is why it was chosen.
