local Graph = require("fd.core.trackgraph")

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

--- A straight three-lane road running right, cells 40 px long, lanes 25 px
-- apart. Ids run lane by lane.
local function straight(cells)
    local spaces, id = {}, 0
    for lane = 1, 3 do
        for c = 1, cells do
            id = id + 1
            spaces[#spaces + 1] = { id = id, lane = lane, rot = 0, pos = { c * 40, lane * 25 } }
        end
    end
    return spaces
end

local function byId(spaces, id)
    for _, s in ipairs(spaces) do
        if s.id == id then return s end
    end
end

local T = {}

function T.cell_length_is_the_step_along_a_lane()
    eq(Graph.cellLength(straight(6)), 40)
end

function T.links_go_ahead_and_diagonally()
    local s = straight(6)
    Graph.relink(s)
    -- Middle lane, second cell (id 8): ahead is id 9, diagonals 3 and 15.
    local links = table.concat(byId(s, 8).next, ",")
    eq(links, "3,9,15")
    -- Inside lane has no lane below it.
    eq(table.concat(byId(s, 2).next, ","), "3,9")
end

function T.diagonals_take_the_space_touching_in_a_staggered_lane()
    -- Middle lane set part of a cell ahead, as printed boards often are, so
    -- no two lanes line up: from the inside lane's id 2 (x 80) the straight
    -- move lands at x 120, between middle-lane ids 8 (x 95) and 9 (x 135).
    -- 9 is nearer that point, but 8 is the space touching 2's front; taking
    -- 9 would skip it.
    local s = straight(6)
    for _, sp in ipairs(s) do
        if sp.lane == 2 then sp.pos[1] = sp.pos[1] + 15 end
    end
    Graph.relink(s)
    eq(table.concat(byId(s, 2).next, ","), "3,8")
    eq(table.concat(byId(s, 8).next, ","), "3,9,15")
end

function T.last_cell_has_nothing_ahead()
    local s = straight(4)
    Graph.relink(s)
    eq(#byId(s, 4).next, 0)
end

function T.a_missing_space_is_not_bridged_across_far()
    local s = straight(8)
    -- Remove cells 3-5 of the middle lane: too far to link across.
    for i = #s, 1, -1 do
        if s[i].lane == 2 and s[i].pos[1] >= 120 and s[i].pos[1] <= 200 then
            table.remove(s, i)
        end
    end
    Graph.relink(s)
    local sameLane = false
    for _, n in ipairs(byId(s, 10).next) do
        if byId(s, n).lane == 2 then sameLane = true end
    end
    assert(not sameLane, "no link jumps the gap")
    local found = false
    for _, p in ipairs(Graph.problems(s)) do
        if p.id == 10 and p.text:find("no space ahead") then found = true end
    end
    assert(found, "the gap is reported")
end

function T.facing_decides_what_is_ahead()
    local s = straight(4)
    for _, sp in ipairs(s) do sp.rot = 180 end      -- running left instead
    Graph.relink(s)
    eq(table.concat(byId(s, 3).next, ","), "2,6")
    eq(#byId(s, 1).next, 0)
end

function T.overlapping_spaces_are_reported()
    local s = straight(4)
    s[#s + 1] = { id = 99, lane = 1, rot = 0, pos = { 42, 26 } }
    Graph.relink(s)
    local found = false
    for _, p in ipairs(Graph.problems(s)) do
        if p.text:find("on top of space 99") then found = true end
    end
    assert(found)
end

function T.links_set_by_hand_are_kept()
    local s = straight(4)
    byId(s, 2).next = { 12 }
    byId(s, 2).fixed = true
    Graph.relink(s)
    eq(table.concat(byId(s, 2).next, ","), "12", "a fixed space keeps its links")
    eq(table.concat(byId(s, 1).next, ","), "2,6", "the rest are worked out as usual")
end

function T.a_hairpin_apex_links_round_the_turn()
    -- One lane doubling back on itself: the apex space faces across the turn,
    -- so the next space sits square to it, not ahead of it.
    local s = {
        { id = 1, lane = 1, rot = 0, pos = { 0, 0 } },
        { id = 2, lane = 1, rot = 0, pos = { 40, 0 } },
        { id = 3, lane = 1, rot = 0, pos = { 80, 0 } },
        { id = 4, lane = 1, rot = 60, pos = { 110, 20 } },     -- the apex
        { id = 5, lane = 1, rot = 180, pos = { 80, 45 } },
        { id = 6, lane = 1, rot = 180, pos = { 40, 45 } },
    }
    Graph.relink(s)
    eq(table.concat(byId(s, 4).next, ","), "5", "the apex leads on round the turn")
    eq(table.concat(byId(s, 3).next, ","), "4")
end

function T.a_space_turned_round_is_reported()
    local s = straight(5)
    byId(s, 8).rot = 180
    Graph.relink(s)
    local found = {}
    for _, p in ipairs(Graph.problems(s)) do
        if p.text:find("faces against") then found[#found + 1] = p.id end
    end
    eq(table.concat(found, ","), "8", "only the turned space")
end

local function flagged(spaces, pattern)
    local ids = {}
    for _, p in ipairs(Graph.problems(spaces)) do
        if p.text:find(pattern) then ids[#ids + 1] = p.id end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

function T.a_corner_space_forks_one_way_only()
    local s = straight(4)
    Graph.relink(s)
    -- On a straight the middle lane leads both ways across, as it should.
    eq(flagged(s, "both ways"), "", "not a problem on a straight")
    byId(s, 6).corner = 1
    byId(s, 7).corner = 1
    byId(s, 7).next, byId(s, 7).fixed = { 8 }, true
    eq(flagged(s, "both ways"), "6", "inside a corner it is")
end

function T.corner_links_across_a_lane_do_not_double_up()
    local s = straight(4)
    Graph.relink(s)
    for _, id in ipairs({ 1, 2, 3 }) do byId(s, id).corner = 1 end
    byId(s, 1).next, byId(s, 1).fixed = { 2, 6 }, true
    byId(s, 2).next, byId(s, 2).fixed = { 3, 6 }, true
    eq(flagged(s, "and so does"), "2", "the second space to claim 6 is flagged")
end

function T.nearest_finds_the_closest_space()
    local s = straight(4)
    local n, d = Graph.nearest(s, 81, 51)
    eq(n.id, 6)
    assert(d < 2)
end

return T
