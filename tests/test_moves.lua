local Moves = require("fd.core.moves")

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

--- A two-lane road, `cells` long, staggered like a printed straight: the
-- outside lane `o` sits half a cell ahead of the inside lane `i`, so a step
-- across a lane is only half a step on. `corners` lists { id, first, last,
-- stops }: the cells a corner covers, in both lanes.
local function road(cells, corners)
    local spaces, cs = {}, {}
    local function cornerOf(k)
        for _, c in ipairs(corners or {}) do
            if k >= c[2] and k <= c[3] then return c[1] end
        end
        return nil
    end
    for k = 0, cells - 1 do
        local last = k == cells - 1
        spaces[#spaces + 1] = { id = "i" .. k, lane = 1, corner = cornerOf(k),
            next = last and { "o" .. k } or { "i" .. (k + 1), "o" .. k } }
        spaces[#spaces + 1] = { id = "o" .. k, lane = 2, corner = cornerOf(k),
            next = last and {} or { "o" .. (k + 1), "i" .. (k + 1) } }
    end
    for _, c in ipairs(corners or {}) do
        cs[#cs + 1] = { id = c[1], stops = c[4] }
    end
    return { spaces = spaces, corners = cs }
end

--- The ids of the spaces reached using the whole roll, sorted.
local function fullRoll(r)
    local ids = {}
    for id, o in pairs(r) do
        if o.brake == 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return table.concat(ids, " ")
end

local T = {}

function T.a_full_roll_ends_one_space_on_in_each_lane()
    local r = Moves.reach(road(12), "i0", 4)
    eq(fullRoll(r), "i4 o3")
    eq(r.i4.moved, 4)
    eq(r.i0.moved, 0, "staying put is braking the whole roll")
    eq(r.i0.brake, 4)
end

function T.weaving_does_not_burn_off_a_roll()
    -- i0 -> o0 -> i1 -> o1 -> i2 takes four steps to go two spaces; i2 is
    -- two spaces on, the rest of the roll is braking.
    local r = Moves.reach(road(12), "i0", 4)
    eq(r.i2.moved, 2)
    eq(r.i2.brake, 2)
    eq(table.concat(r.i2.path, " "), "i0 i1 i2")
end

function T.cars_are_driven_round_not_through()
    local r = Moves.reach(road(12), "i0", 4, { occupied = { i2 = true } })
    eq(r.i2, nil, "no ending on a car")
    eq(r.i3.moved, 4, "round it through the other lane costs the long way")
    eq(r.i4, nil, "and the space beyond is out of reach")
    eq(fullRoll(r), "i3 o3")
end

function T.a_boxed_in_car_can_only_brake()
    local r = Moves.reach(road(12), "i0", 6, { occupied = { i1 = true, o0 = true } })
    eq(fullRoll(r), "")
    eq(r.i0.brake, 6)
end

function T.ending_in_a_corner_is_a_stop()
    local r = Moves.reach(road(12, { { 1, 3, 5, 1 } }), "i0", 4)
    eq(r.i4.stops, 1)
    eq(r.i4.overshoot, 0)
    eq(r.i2.stops, 0, "not in the corner yet")
end

function T.leaving_a_corner_without_its_stops_overshoots()
    local r = Moves.reach(road(12, { { 1, 3, 5, 1 } }), "i0", 8)
    eq(r.i8.overshoot, 3, "i6, i7, i8 are past the corner")
    eq(r.i8.missed, 1)
    eq(r.i8.corner, 1)
    eq(r.i5.overshoot, 0, "braking inside the corner does not")
    eq(Moves.defaultCost(r.i8), 3)
end

function T.an_overshooting_car_keeps_its_lane()
    local r = Moves.reach(road(12, { { 1, 3, 5, 1 } }), "i0", 8)
    for id, o in pairs(r) do
        if o.overshoot > 0 then
            -- Every step from the first one out of the corner stays in lane.
            local lane = nil
            for i = #o.path - o.overshoot, #o.path do
                local l = o.path[i]:sub(1, 1)
                eq(l, lane or l, id .. " changes lane overshooting")
                lane = l
            end
        end
    end
    -- o6 is only reachable by leaving the corner in the other lane.
    eq(r.o6.path[#r.o6.path - 1], "o5")
end

function T.stops_already_made_let_the_car_leave()
    local track = road(12, { { 1, 3, 5, 1 } })
    local r = Moves.reach(track, "i4", 4)
    eq(r.i8.overshoot, 0, "the space it sits on is a stop")
    r = Moves.reach(track, "i4", 4, { stops = 0 })
    eq(r.i8.overshoot, 3, "unless the race says it was not")
    eq(Moves.reach(track, "i4", 0).i4.stops, 2, "staying put stops again")
end

function T.missing_two_stops_is_the_worst_outcome()
    local track = road(12, { { 1, 3, 5, 2 } })
    local r = Moves.reach(track, "i0", 8)
    eq(r.i8.missed, 2)
    assert(Moves.defaultCost(r.i8) >= 1000)
    r = Moves.reach(track, "i4", 4, { stops = 1 })
    eq(r.i8.missed, 1)
    eq(Moves.defaultCost(r.i8), 3)
end

function T.an_overshoot_ending_in_a_corner_is_no_stop_there()
    local track = road(14, { { 1, 3, 5, 1 }, { 2, 8, 10, 1 } })
    local r = Moves.reach(track, "i5", 4, { stops = 0 })
    eq(r.i9.overshoot, 4)
    eq(r.i9.stops, 0)
end

function T.the_cheaper_of_two_equal_ways_is_kept()
    -- Two ways from s to e, both three steps: through a1 leaves the corner
    -- a step earlier, so it overshoots by two where through b1, b2 is one.
    local track = {
        corners = { { id = 1, stops = 1 } },
        spaces = {
            { id = "s", lane = 1, next = { "a1", "b1" } },
            { id = "a1", lane = 1, corner = 1, next = { "a2" } },
            { id = "a2", lane = 1, next = { "e" } },
            { id = "b1", lane = 1, corner = 1, next = { "b2" } },
            { id = "b2", lane = 1, corner = 1, next = { "e" } },
            { id = "e", lane = 1, next = {} },
        },
    }
    local r = Moves.reach(track, "s", 3)
    eq(r.e.overshoot, 1)
    eq(table.concat(r.e.path, " "), "s b1 b2 e")
    -- A ruleset that sees it the other way gets the other way.
    r = Moves.reach(track, "s", 3, { cost = function(o) return -o.overshoot end })
    eq(r.e.overshoot, 2)
    eq(table.concat(r.e.path, " "), "s a1 a2 e")
end

function T.unknown_start_space()
    eq(Moves.reach(road(4), "nowhere", 3), nil)
end

function T.monaco_straight_and_corner()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local r = Moves.reach(FDMonaco, "m.s2.5", 8)
    eq(fullRoll(r), "i.s2.13 m.s2.13 o.s2.12")
    -- Every step of every way found follows a link.
    for id, o in pairs(r) do
        for i = 2, #o.path do
            local ok = false
            for _, n in ipairs(FDMonaco.byId[o.path[i - 1]].next) do
                if n == o.path[i] then ok = true end
            end
            assert(ok, id .. ": no link " .. o.path[i - 1] .. " -> " .. o.path[i])
        end
    end
    -- Through corner 2 (one stop) without stopping, into corner 3.
    r = Moves.reach(FDMonaco, "m.s2.17", 12)
    eq(r["m.c3.1"].overshoot, 4)
    eq(r["m.c3.1"].stops, 0)
end

return T
