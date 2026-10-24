-- What every track's data has to get right, checked on each track the mod
-- plays (Global's TRACKS). The Monaco tests elsewhere pin its particulars;
-- these are the rules a track file follows whatever the board.

local Graph = require("fd.core.trackgraph")
local Moves = require("fd.core.moves")
local Position = require("fd.core.position")

local TRACKS = { "FDAustin", "FDBuddh", "FDHockenheim", "FDMonaco", "FDSebring", "FDSingapore", "FDSotchi", "FDValencia" }

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

--- Run `fn(track, id)` on every track, naming the track in any failure.
local function each(fn)
    for _, id in ipairs(TRACKS) do
        local ok, err = pcall(fn, require("fd.data.tracks." .. id), id)
        if not ok then
            error(id .. ": " .. tostring(err), 2)
        end
    end
end

local T = {}

function T.the_editor_finds_nothing_wrong()
    each(function(track)
        -- As the editor opens it: relinked, then checked.
        local spaces = {}
        for i, s in ipairs(track.spaces) do
            local nxt = {}
            for k, n in ipairs(s.next) do nxt[k] = n end
            spaces[i] = { id = s.id, pos = s.pos, rot = s.rot, lane = s.lane, next = nxt,
                          fixed = s.fixed, corner = s.corner, pit = s.pit, box = s.box }
        end
        local cell = Graph.relink(spaces)
        for _, p in ipairs(Graph.problems(spaces, cell)) do
            error(p.id .. ": " .. p.text)
        end
    end)
end

function T.every_link_leads_forward()
    each(function(track)
        local P = Position.of(track)
        local line = {}
        for _, id in ipairs(track.finish.line) do line[id] = true end
        for _, s in ipairs(track.spaces) do
            assert(P.along[s.id], s.id .. " has no place round the lap")
            for _, n in ipairs(s.next) do
                local t = track.byId[n]
                assert(t, s.id .. " -> " .. n .. ": no such space")
                if not line[n] then
                    -- A pit lane merge is beside the track spaces touching
                    -- it, and a pit box beside its space in the pit lane.
                    local across = (s.pit or false) ~= (t.pit or false) or s.box or t.box
                    local slack = across and P.cell / 2 or 0
                    -- A fork can point into a space printed level with it:
                    -- round a hairpin, or the outside of a bend, the lane
                    -- beside has cells longer or out of step. Never behind.
                    local ok = P.along[n] > P.along[s.id] - slack
                        or (t.lane ~= s.lane and P.along[n] == P.along[s.id])
                    assert(ok, s.id .. " -> " .. n .. " runs backwards")
                end
            end
        end
    end)
end

function T.every_space_can_be_driven_onto()
    each(function(track)
        local into = {}
        for _, s in ipairs(track.spaces) do
            for _, n in ipairs(s.next) do into[n] = true end
        end
        for _, s in ipairs(track.spaces) do
            assert(into[s.id], s.id .. " has no link into it")
        end
    end)
end

function T.the_grid_runs_back_from_pole()
    each(function(track)
        local P = Position.of(track)
        eq(#track.start, 10, "a place for each seat")
        for i = 2, #track.start do
            assert(P.along[track.start[i]] < P.along[track.start[i - 1]],
                track.start[i] .. " should be behind " .. track.start[i - 1])
        end
        -- Pole sits right behind the line; the back row is further off.
        local crossed = false
        for _, o in pairs(Moves.reach(track, track.start[1], 2)) do crossed = crossed or o.crossed end
        assert(crossed, "pole reaches the line on a 2")
        for id, o in pairs(Moves.reach(track, track.start[#track.start], 4)) do
            eq(o.crossed, false, "the back row on a 4, to " .. id)
        end
    end)
end

function T.no_link_hops_over_the_line()
    each(function(track)
        local line = {}
        for _, id in ipairs(track.finish.line) do line[id] = true end
        eq(#track.finish.line, track.lanes + (track.pit and 1 or 0), "a space past the line in each lane")
        for _, s in ipairs(track.spaces) do
            for _, n in ipairs(s.next) do
                if s.sector ~= "s1" and track.byId[n].sector == "s1" then
                    assert(line[n], s.id .. " -> " .. n .. " enters s1 past the line")
                end
            end
        end
    end)
end

function T.every_corner_has_its_stops_and_spaces()
    each(function(track)
        for i, c in ipairs(track.corners) do
            eq(c.id, i, "corners in running order")
            assert(c.stops and c.stops >= 1, "corner " .. c.id .. " has a stop count")
            local lanes = {}
            for _, s in ipairs(track.spaces) do
                if s.corner == c.id then lanes[s.lane] = true end
            end
            for lane = 1, track.lanes do
                assert(lanes[lane], "corner " .. c.id .. " has spaces in lane " .. lane)
            end
        end
    end)
end

function T.the_lane_with_fewest_spaces_in_a_corner_is_its_inside()
    each(function(track)
        local P = Position.of(track)
        for _, c in ipairs(track.corners) do
            local count, inside = {}, {}
            for _, s in ipairs(track.spaces) do
                if s.corner == c.id then
                    count[s.lane] = (count[s.lane] or 0) + 1
                    inside[s.lane] = (inside[s.lane] or 0) + Position.inside(P, s.id)
                end
            end
            if count[1] ~= count[3] then
                local fewest = count[1] < count[3] and 1 or 3
                local other = 4 - fewest
                assert(inside[fewest] / count[fewest] > inside[other] / count[other],
                    "corner " .. c.id .. ": lane " .. fewest .. " is the inside")
            end
        end
    end)
end

function T.the_pit_lane_is_one_way_with_a_box_for_each_seat()
    each(function(track)
        local pit = track.pit
        eq(#pit.boxes, 10, "two pit boxes for each of five teams")
        local into = {}
        for _, s in ipairs(track.spaces) do
            for _, n in ipairs(s.next) do
                if track.byId[n].pit and not s.pit then
                    into[#into + 1] = s.id
                    eq(n, pit.spaces[1], s.id .. " leads into the entry merge")
                end
            end
        end
        table.sort(into)
        eq(table.concat(into, ","), table.concat(pit.entry, ","), "the only ways in")
        for i, id in ipairs(pit.spaces) do
            local s = track.byId[id]
            assert(s.pit and s.lane == 0, id)
            local on = {}
            for _, n in ipairs(s.next) do
                if not track.byId[n].box then on[#on + 1] = n end
            end
            eq(table.concat(on, ","), pit.spaces[i + 1] or table.concat(pit.exit, ","),
                id .. " leads on down the pit lane")
        end
        for _, entry in ipairs(pit.entry) do
            eq(Moves.reach(track, entry, 3)[pit.spaces[1]], nil, entry .. ": driving past")
            assert(Moves.reach(track, entry, 3, { pit = true })[pit.spaces[1]], entry .. ": pitting")
        end
        local seats = {}
        for _, b in ipairs(pit.boxes) do
            assert(not seats[b.player], b.player .. " has one pit box")
            seats[b.player] = true
            assert(b.garage, b.space .. " has its garage to paint")
            eq(track.byId[b.space].box, b.player, b.space)
            eq(table.concat(track.byId[b.space].next, ","), b.beside, b.space .. " leads out beside it")
            assert(Moves.reach(track, b.beside, 1, { color = b.player })[b.space], b.player .. " goes in")
        end
    end)
end

-- Both are optional: without them the dice sit in the board's middle and
-- the panel goes on the screen.
function T.the_dice_and_the_panel_lie_on_the_board_clear_of_the_track()
    each(function(track)
        local w, h = track.image.width, track.image.height
        local function clear(x, y, reach, what)
            assert(x >= 0 and x <= w and y >= 0 and y <= h, what .. " is on the board")
            for _, s in ipairs(track.spaces) do
                local dx, dy = math.abs(s.pos[1] - x), math.abs(s.pos[2] - y)
                assert(dx > reach[1] or dy > reach[2], what .. " covers " .. s.id)
            end
        end
        if track.dice then
            clear(track.dice[1], track.dice[2], { 60, 60 }, "the dice")
        end
        local p = track.panel
        if p then
            -- The panel is laid out 380 by 360, stretched to its width.
            local half = { p.width / 2, p.width * 360 / 380 / 2 }
            clear(p.pos[1], p.pos[2], half, "the race panel")
            assert(p.pos[1] + half[1] <= w and p.pos[2] + half[2] <= h, "the race panel is on the board")
        end
    end)
end

function T.every_space_touches_another()
    each(function(track)
        for _, s in ipairs(track.spaces) do
            if not s.pit then
                assert(track.near[s.id] and #track.near[s.id] > 0, s.id .. " touches no space")
            end
        end
    end)
end

return T
