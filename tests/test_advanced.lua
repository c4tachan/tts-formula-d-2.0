-- The advanced rules (fd.rules.advanced) through the race engine.

local Race = require("fd.core.race")
local Rules = require("fd.rules.advanced")
local Beginner = require("fd.rules.beginner")

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

local function hasEvent(race, level, pattern)
    for _, e in ipairs(race:drain()) do
        if e.level == level and e.text:find(pattern) then return true end
    end
    return false
end

local function newRace(...)
    local r = Race.new(Rules)
    for _, c in ipairs({ ... }) do r:join(c) end
    r:drain()
    return r
end

--- Start a race and get every car past its start check with a normal start.
local function started(...)
    local r = newRace(...)
    r:startRace()
    for _, c in ipairs({ ... }) do r:blackDie(10, c) end
    r:drain()
    return r
end

local function rollDie(r, color, gear, value)
    local car = r:car(color)
    if car and car.gear ~= gear then r:shift(color, gear) end
    r:rolled(color, gear, value)
end

local function putDown(r, color, id, track)
    r:placed(color, id, track)
    r:putDown(color)
end

--- One lane, cells 0 .. cells-1 named "c0", "c1", ...; `corner` is
-- { first, last, stops } for corner 1.
local function lane(cells, corner)
    local spaces = {}
    for k = 0, cells - 1 do
        local inCorner = corner and k >= corner[1] and k <= corner[2]
        spaces[#spaces + 1] = { id = "c" .. k, lane = 1, corner = inCorner and 1 or nil,
            next = k < cells - 1 and { "c" .. (k + 1) } or {} }
    end
    return { spaces = spaces, corners = corner and { { id = 1, stops = corner[3] } } or {} }
end

local function wear(r, color)
    local w = r:car(color).wear
    return string.format("T%d B%d G%d C%d E%d S%d", w.tires, w.brakes, w.gearbox, w.body, w.engine, w.handling)
end

local T = {}

function T.cars_start_with_twenty_wp_in_six_zones()
    local r = newRace("Red")
    eq(wear(r, "Red"), "T6 B3 G3 C3 E3 S2")
end

-- Braking -----------------------------------------------------------------------

function T.braking_costs_brakes_then_tires()
    local track = lane(30)
    local r = started("Red")
    r:placed("Red", "c0", track)
    rollDie(r, "Red", 3, 8)
    putDown(r, "Red", "c4", track)
    eq(wear(r, "Red"), "T5 B0 G3 C3 E3 S2", "4 short: 3 brake and 1 tire")
    r:placed("Red", "c6", track)
    eq(wear(r, "Red"), "T6 B1 G3 C3 E3 S2", "put down 2 short instead: the difference given back")
    r:placed("Red", "c3", track)
    eq(wear(r, "Red"), "T4 B0 G3 C3 E3 S2", "5 short: 3 brake and 2 tire")
    assert(not r:car("Red").eliminated)
end

function T.braking_seven_spaces_is_out()
    local track = lane(30)
    local r = started("Red")
    r:placed("Red", "c0", track)
    rollDie(r, "Red", 3, 8)
    r:drain()
    putDown(r, "Red", "c1", track)
    assert(r:car("Red").eliminated)
    assert(hasEvent(r, "out", "could not brake 7"))
    r:placed("Red", "c8", track)
    assert(not r:car("Red").eliminated, "back in, put down on the full roll")
    eq(wear(r, "Red"), "T6 B3 G3 C3 E3 S2")
end

function T.brakes_the_car_does_not_have_come_out_of_its_tires()
    local track = lane(30)
    local r = started("Red")
    r:setWear("Red", "brakes", 1)
    r:placed("Red", "c0", track)
    rollDie(r, "Red", 3, 8)
    putDown(r, "Red", "c5", track)
    eq(wear(r, "Red"), "T4 B0 G3 C3 E3 S2", "3 short with 1 brake WP: the other 2 from the tires")
end

function T.braking_further_than_brakes_and_tires_allow_is_out()
    local track = lane(30)
    local r = started("Red")
    r:setWear("Red", "brakes", 0)
    r:setWear("Red", "tires", 2)
    r:placed("Red", "c0", track)
    rollDie(r, "Red", 3, 8)
    local o = r:reachable("Red", track).c5
    assert(r:outcome("Red", o).out, "the board shows it would be out")
    putDown(r, "Red", "c5", track)
    assert(r:car("Red").eliminated, "3 short on 2 tire WP and no brakes")
end

-- Overshooting --------------------------------------------------------------------

--- Red sitting in a 2-stop corner (c1-c3) with one stop made, and rolling
-- `roll` in 3rd: each space past c3 overshoots by one, one stop missed.
local function inCorner(roll, tires)
    local track = lane(30, { 1, 3, 2 })
    local r = started("Red")
    if tires then r:setWear("Red", "tires", tires) end
    r:placed("Red", "c2", track)
    rollDie(r, "Red", 3, roll)
    r:drain()
    return r, track
end

function T.overshooting_costs_a_tire_a_space()
    local r, track = inCorner(4)
    putDown(r, "Red", "c6", track)
    eq(wear(r, "Red"), "T3 B3 G3 C3 E3 S2", "overshot by 3")
    assert(not r:car("Red").spun)
end

function T.losing_the_last_tires_overshooting_spins()
    local r, track = inCorner(4, 3)
    local o = r:reachable("Red", track).c6
    local ahead = r:outcome("Red", o)
    assert(ahead.spin and not ahead.out, "the board shows a spin, not out")
    putDown(r, "Red", "c6", track)
    eq(r:car("Red").wear.tires, 0)
    assert(r:car("Red").spun)
    assert(not r:car("Red").eliminated, "on no tires, still racing")
    assert(hasEvent(r, "warn", "spins"))
    -- Put down short of the overshoot instead, it has not spun.
    r:placed("Red", "c5", track)
    assert(not r:car("Red").spun)
    eq(r:car("Red").wear.tires, 1)
end

function T.a_spun_car_drives_off_in_first_at_no_cost()
    local r, track = inCorner(4, 3)
    putDown(r, "Red", "c6", track)
    r:drain()
    r:shift("Red", 2)
    assert(hasEvent(r, "warn", "drive off in 1st"))
    r:shift("Red", 1)
    assert(not hasEvent(r, "warn", "costs"), "no downshift wear from 3rd to 1st")
    rollDie(r, "Red", 1, 2)
    eq(wear(r, "Red"), "T0 B3 G3 C3 E3 S2")
    assert(not r:car("Red").spun, "turned round and off again")
end

function T.on_no_tires_overshooting_by_one_spins_again_and_by_more_is_out()
    local r, track = inCorner(2, 0)
    putDown(r, "Red", "c4", track)
    assert(r:car("Red").spun, "overshot by one on no tires")
    assert(not r:car("Red").eliminated)
    r:placed("Red", "c3", track) -- undo the move by putting it down short
    r = inCorner(3, 0)
    putDown(r, "Red", "c5", track)
    assert(r:car("Red").eliminated, "overshot by two on no tires")
end

function T.overshooting_by_more_than_the_tires_left_is_out()
    local r, track = inCorner(4, 2)
    putDown(r, "Red", "c6", track)
    assert(r:car("Red").eliminated)
end

function T.missing_two_stops_is_out_as_in_the_basic_rules()
    local track = lane(30, { 3, 5, 2 })
    local r = started("Red")
    r:placed("Red", "c0", track)
    rollDie(r, "Red", 3, 7)
    r:drain()
    putDown(r, "Red", "c7", track)
    assert(r:car("Red").eliminated)
    assert(hasEvent(r, "out", "without its stops"))
end

-- Gears ---------------------------------------------------------------------------

function T.skipping_gears_down_wears_gearbox_brakes_and_engine()
    local r = started("Red")
    r:car("Red").rolledGear = 6
    rollDie(r, "Red", 4, 8)
    eq(wear(r, "Red"), "T6 B3 G2 C3 E3 S2", "one skipped")
    r = started("Red")
    r:car("Red").rolledGear = 6
    rollDie(r, "Red", 3, 5)
    eq(wear(r, "Red"), "T6 B2 G2 C3 E3 S2", "two skipped")
    r = started("Red")
    r:car("Red").rolledGear = 6
    rollDie(r, "Red", 2, 3)
    eq(wear(r, "Red"), "T6 B2 G2 C3 E2 S2", "three skipped")
end

function T.with_no_gearbox_left_a_car_shifts_down_one_at_a_time()
    local r = started("Red")
    r:setWear("Red", "gearbox", 0)
    r:car("Red").rolledGear = 5
    r:drain()
    r:shift("Red", 3)
    assert(hasEvent(r, "warn", "one gear at a time"))
    r:shift("Red", 4)
    assert(not hasEvent(r, "warn", "one gear at a time"))
end

function T.no_gearbox_or_brakes_left_is_still_racing()
    local r = started("Red")
    r:setWear("Red", "gearbox", 0)
    r:setWear("Red", "brakes", 0)
    assert(not r:car("Red").eliminated)
    r:setWear("Red", "body", 0)
    assert(r:car("Red").eliminated, "no body left is out")
end

-- Black die -----------------------------------------------------------------------

function T.only_a_twenty_is_a_great_start()
    local r = newRace("Red", "Blue")
    r:startRace()
    r:blackDie(19, "Red")
    eq(r:car("Red").move, nil, "19 is a normal start")
    r:blackDie(1, "Blue")
    eq(r:car("Blue").stalledRound, 1)
    r = newRace("Red")
    r:placed("Red", "c0")
    r:startRace()
    r:blackDie(20, "Red")
    eq(r:car("Red").move.roll, 4)
end

function T.only_a_one_is_a_collision_and_it_costs_body()
    local r = started("Red")
    r:requestCheck("Red", "collision")
    r:blackDie(2, "Red")
    eq(wear(r, "Red"), "T6 B3 G3 C3 E3 S2")
    r:requestCheck("Red", "collision")
    r:blackDie(1, "Red")
    eq(wear(r, "Red"), "T6 B3 G3 C2 E3 S2")
end

function T.engine_strain_costs_engine()
    local r = started("Red")
    r:car("Red").rolledGear = 4
    rollDie(r, "Red", 5, 20)
    r:blackDie(4, "Red")
    eq(wear(r, "Red"), "T6 B3 G3 C3 E2 S2")
end

-- Pit stops -----------------------------------------------------------------------

function T.a_pit_stop_restores_only_the_tires_and_rolls_the_black_die()
    local r = started("Red")
    r:setWear("Red", "tires", 2)
    r:setWear("Red", "brakes", 1)
    r:drain()
    r:pitStop("Red")
    eq(wear(r, "Red"), "T6 B1 G3 C3 E3 S2")
    eq(r:pendingChecks()[1].kind, "pit")
    assert(hasEvent(r, "info", "pit stop check"))
end

function T.a_quick_stop_moves_half_the_roll_out_of_the_pits_in_fourth()
    local r = started("Red")
    r:placed("Red", "c0")
    r:pitStop("Red")
    r:blackDie(7, "Red")
    eq(r:car("Red").move.roll, 4, "7 halved, rounded up")
    eq(r:car("Red").rolledGear, 4)
    eq(r:car("Red").maxGear, 4, "and 4th or lower on its next roll")
end

function T.a_slow_stop_waits_for_the_next_round()
    local r = started("Red")
    r:placed("Red", "c0")
    r:pitStop("Red")
    r:drain()
    r:blackDie(15, "Red")
    eq(r:car("Red").move, nil)
    assert(hasEvent(r, "info", "slow stop"))
end

function T.the_round_waits_for_a_pit_stop_to_be_timed()
    local track = lane(10)
    local r = started("Red")
    r:placed("Red", "c0", track)
    rollDie(r, "Red", 1, 2)
    r:pitStop("Red")
    putDown(r, "Red", "c2", track)
    eq(r:serialize().round, 1, "the stop's black die is still to come")
    r:blackDie(15, "Red")
    eq(r:serialize().round, 2)
end

function T.stopping_in_the_pit_box_times_the_stop_and_a_quick_one_moves_on()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local b = FDMonaco.pit.boxes[2]
    eq(b.player, "Brown")
    local r = started("Brown")
    r:setLaps(2)
    r:placed("Brown", b.beside, FDMonaco)
    r:car("Brown").lap = 1
    r:setWear("Brown", "tires", 1)
    rollDie(r, "Brown", 1, 1)
    putDown(r, "Brown", b.space, FDMonaco)
    eq(r:car("Brown").wear.tires, 6, "the tires back")
    eq(r:pendingChecks()[1].kind, "pit")
    eq(r:serialize().round, 1, "the round waits for the stop")
    r:drain()
    r:blackDie(3, "Brown")
    local m = r:car("Brown").move
    eq(m.from, b.space, "out of the box")
    eq(m.roll, 2)
    eq(r.opened, "Brown", "the board shows where it can go")
    eq(r:serialize().round, 1, "its turn goes on")
    -- Moved out, the stop stands: it was made on the move before.
    local reach = r:reachable("Brown", FDMonaco)
    local out = nil
    for id, o in pairs(reach) do
        if o.moved == 2 then out = id end
    end
    putDown(r, "Brown", out, FDMonaco)
    eq(r:car("Brown").wear.tires, 6)
    eq(r:serialize().round, 2)
end

function T.taken_out_of_the_box_the_stop_is_not_timed()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local b = FDMonaco.pit.boxes[2]
    local r = started("Brown")
    r:setLaps(2)
    r:placed("Brown", b.beside, FDMonaco)
    r:car("Brown").lap = 1
    rollDie(r, "Brown", 1, 1)
    r:placed("Brown", b.space, FDMonaco)
    eq(#r:pendingChecks(), 1)
    r:placed("Brown", b.beside, FDMonaco)
    eq(#r:pendingChecks(), 0, "back where it started: no stop, no die")
end

-- Slipstreaming ---------------------------------------------------------------------

--- Two staggered lanes, `cells` long (as in test_moves), corner 1 over
-- `corner` = { first, last, stops } if given.
local function road(cells, corner)
    local spaces = {}
    for k = 0, cells - 1 do
        local c = corner and k >= corner[1] and k <= corner[2] and 1 or nil
        local last = k == cells - 1
        spaces[#spaces + 1] = { id = "i" .. k, lane = 1, corner = c,
            next = last and { "o" .. k } or { "i" .. (k + 1), "o" .. k } }
        spaces[#spaces + 1] = { id = "o" .. k, lane = 2, corner = c,
            next = last and {} or { "o" .. (k + 1), "i" .. (k + 1) } }
    end
    return { spaces = spaces, corners = corner and { { id = 1, stops = corner[3] } } or {} }
end

--- Red on i0 and Blue on i5, both last in 4th; Red rolls 4 in 4th.
local function behindBlue(rules, track)
    local r = Race.new(rules)
    r:join("Red")
    r:join("Blue")
    r:startRace()
    r:blackDie(10, "Red")
    r:blackDie(10, "Blue")
    r:placed("Red", "i0", track)
    r:placed("Blue", "i5", track)
    r:car("Red").rolledGear = 4
    r:car("Blue").rolledGear = 4
    r:drain()
    rollDie(r, "Red", 4, 4)
    return r
end

function T.a_car_slipstreams_past_the_one_ahead()
    local track = road(14)
    local r = behindBlue(Rules, track)
    assert(hasEvent(r, "info", "can slipstream"), "told after the roll")
    eq(r:reachable("Red", track).i6.slip, 1)
    putDown(r, "Red", "i6", track)
    local events = r:drain()
    for _, e in ipairs(events) do
        assert(not e.text:find("not a legal"), e.text)
    end
    eq(wear(r, "Red"), "T6 B3 G3 C3 E3 S2", "the 3 spaces cost nothing")
    eq(r:car("Red").space, "i6")
end

function T.a_slipstream_into_a_corner_costs_a_brake()
    local track = road(14, { 6, 9, 1 })
    local r = behindBlue(Rules, track)
    putDown(r, "Red", "i6", track)
    eq(wear(r, "Red"), "T6 B2 G3 C3 E3 S2")
    assert(hasEvent(r, "wear", "slipstreamed into a corner"))
end

function T.braking_a_slipstream_short_is_charged_as_braking()
    local track = road(14)
    local r = behindBlue(Rules, track)
    putDown(r, "Red", "o5", track)
    eq(wear(r, "Red"), "T6 B2 G3 C3 E3 S2", "a space short of the 3")
end

function T.the_basic_rules_have_no_slipstream()
    local track = road(14)
    local r = behindBlue(Beginner, track)
    eq(r:reachable("Red", track).i6, nil)
    assert(not hasEvent(r, "info", "can slipstream"))
end

-- A car's own starting wear -----------------------------------------------------

function T.a_car_built_otherwise_keeps_its_own_starting_wear()
    local r = newRace("Red")
    local car = r:car("Red")
    car.start = { tires = 9, brakes = 2, gearbox = 2, body = 2, engine = 3, handling = 2 }
    r:startRace()
    eq(wear(r, "Red"), "T9 B2 G2 C2 E3 S2", "the race starts it on its own")
    r:blackDie(10, "Red")
    r:setWear("Red", "tires", 1)
    r:pitStop("Red")
    eq(car.wear.tires, 9, "a pit stop gives back its own")
    r:adjust("Red", "brakes", 5)
    eq(car.wear.brakes, 2, "and nothing gives back more")
    r:reset()
    eq(wear(r, "Red"), "T9 B2 G2 C2 E3 S2", "kept through a reset")
    r:setRules(Beginner)
    eq(car.wear.wp, 18, "other rules, the cars are built afresh")
    eq(car.start.wp, 18)
end

function T.a_game_saved_before_cars_had_their_own_start_loads()
    local r = newRace("Red")
    local saved = r:serialize()
    saved.cars.Red.start = nil
    local copy = Race.new(Rules, saved)
    eq(copy:startOf(copy:car("Red"), "tires"), 6)
end

function T.an_empty_zone_raced_on_is_spelled_out()
    local r = started("Red")
    eq(#r:warnings(r:car("Red")), 0)
    r:setWear("Red", "tires", 0)
    r:setWear("Red", "gearbox", 0)
    local w = r:warnings(r:car("Red"))
    eq(#w, 2)
    eq(w[1], "no tire WP: overshoot 1 spins, more is out")
    eq(w[2], "no gearbox WP: one gear down at a time")
    r:setWear("Red", "body", 0)
    eq(#r:warnings(r:car("Red")), 0, "nothing for a car out of the race")
end

-- Setup -----------------------------------------------------------------------------

function T.switching_rules_starts_the_cars_afresh_in_the_new_zones()
    local r = Race.new(Beginner)
    r:join("Red")
    r:adjust("Red", nil, -3)
    r:setRules(Rules)
    eq(r:serialize().rules, "advanced")
    eq(wear(r, "Red"), "T6 B3 G3 C3 E3 S2")
    eq(r:car("Red").wear.wp, nil)
    r:setRules(Beginner)
    eq(r:car("Red").wear.wp, 18)
    eq(r:car("Red").wear.tires, nil)
end

function T.the_state_says_which_rules_it_was_raced_under()
    local r = newRace("Red")
    local copy = Race.new(Rules, r:serialize())
    eq(copy:serialize().rules, "advanced")
end

return T
