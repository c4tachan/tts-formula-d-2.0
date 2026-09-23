local Race = require("fd.core.race")
local Rules = require("fd.rules.beginner")

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

local T = {}

function T.cars_start_with_full_wear()
    local r = newRace("Red")
    eq(r:car("Red").wear.wp, 18)
    eq(r:car("Red").rolledGear, 0)
end

function T.shifting_up_one_gear_is_free()
    local r = started("Red")
    r:shift("Red", 1)
    r:rolled("Red", 1, 2)
    r:shift("Red", 2)
    assert(hasEvent(r, "info", "selects 2nd"))
    r:rolled("Red", 2, 3)
    eq(r:car("Red").wear.wp, 18)
end

function T.skipping_up_warns_but_is_applied()
    local r = started("Red")
    r:rolled("Red", 1, 2)
    r:drain()
    r:shift("Red", 3)
    assert(hasEvent(r, "warn", "no skipping"))
    eq(r:car("Red").gear, 3)
end

function T.first_move_must_be_in_first()
    local r = started("Red")
    r:shift("Red", 2)
    assert(hasEvent(r, "warn", "start in 1st"))
end

function T.downshift_wear_is_charged_on_the_roll()
    local r = started("Red")
    r:car("Red").rolledGear = 6
    r:shift("Red", 3)
    assert(hasEvent(r, "info", "costs 2 WP"))
    eq(r:car("Red").wear.wp, 18, "not charged when selecting")
    r:shift("Red", 5)
    r:shift("Red", 3)
    r:rolled("Red", 3, 6)
    eq(r:car("Red").wear.wp, 16)
end

function T.dropping_four_gears_is_flagged()
    local r = started("Red")
    r:car("Red").rolledGear = 6
    r:shift("Red", 1)
    assert(hasEvent(r, "warn", "at most 3"))
end

function T.die_overrides_selected_gear()
    local r = started("Red")
    r:shift("Red", 1)
    r:car("Red").rolledGear = 3
    r:shift("Red", 4)
    r:drain()
    r:rolled("Red", 3, 5)
    assert(hasEvent(r, "warn", "going with 3rd"))
    eq(r:car("Red").gear, 3)
end

function T.brake_and_overshoot_cost_wp()
    local r = started("Red")
    r:brake("Red", 2)
    r:overshoot("Red", 3)
    eq(r:car("Red").wear.wp, 13)
end

function T.car_is_out_at_zero_and_back_after_a_correction()
    local r = started("Red")
    r:overshoot("Red", 18)
    assert(r:car("Red").eliminated)
    assert(hasEvent(r, "out", "out of the race"))
    r:adjust("Red", nil, 1)
    assert(not r:car("Red").eliminated)
end

function T.set_wear_moves_to_an_exact_value()
    local r = started("Red")
    r:setWear("Red", "wp", 12, "marker moved")
    eq(r:car("Red").wear.wp, 12)
    assert(hasEvent(r, "wear", "loses 6 WP"))
    r:setWear("Red", "wp", 15, "marker moved")
    eq(r:car("Red").wear.wp, 15)
    r:drain()
    r:setWear("Red", "wp", 15, "marker moved")
    eq(#r:drain(), 0, "no-op when unchanged")
end

function T.gains_are_capped()
    local r = started("Red")
    r:brake("Red", 1)
    r:adjust("Red", "wp", 5, "bonus")
    eq(r:car("Red").wear.wp, 18)
end

function T.top_face_in_fifth_strains_all_fast_cars()
    local r = started("Red", "Blue", "Green")
    r:car("Red").rolledGear = 4
    r:car("Blue").rolledGear = 6
    r:car("Green").rolledGear = 3
    r:rolled("Red", 5, 20)
    local checks = r:pendingChecks()
    eq(#checks, 2)
    eq(checks[1].color, "Red", "roller checks first")
    eq(checks[2].color, "Blue")
    r:blackDie(3, "Red")
    eq(r:car("Red").wear.wp, 17)
    r:blackDie(12, "Blue")
    eq(r:car("Blue").wear.wp, 18)
end

function T.nineteen_in_fifth_is_not_strain()
    local r = started("Red")
    r:rolled("Red", 5, 19)
    eq(#r:pendingChecks(), 0)
end

function T.collision_check_on_request()
    local r = started("Red")
    r:requestCheck("Red", "collision")
    r:requestCheck("Red", "collision")
    eq(#r:pendingChecks(), 1, "no duplicate checks")
    r:blackDie(4, "Red")
    eq(r:car("Red").wear.wp, 17)
end

function T.black_die_resolves_the_rollers_check_first()
    local r = started("Red", "Blue")
    r:requestCheck("Red", "collision")
    r:requestCheck("Blue", "collision")
    r:blackDie(1, "Blue")
    eq(r:car("Blue").wear.wp, 17)
    eq(r:car("Red").wear.wp, 18)
    r:blackDie(1, "Grey")
    eq(r:car("Red").wear.wp, 17, "spectator roll takes the oldest check")
end

function T.stalled_start_sits_out_a_round()
    local r = newRace("Red", "Blue")
    r:startRace()
    r:blackDie(1, "Red")
    r:blackDie(10, "Blue")
    r:drain()
    r:shift("Red", 1)
    assert(hasEvent(r, "warn", "stalled"))
    r:rolled("Blue", 1, 2)
    eq(r:serialize().round, 2, "round ends without the stalled car")
    r:shift("Red", 1)
    assert(hasEvent(r, "info", "selects 1st"))
end

function T.great_start_moves_and_allows_second()
    local r = newRace("Red")
    r:startRace()
    r:blackDie(18, "Red")
    assert(hasEvent(r, "info", "great start"))
    eq(r:car("Red").rolledGear, 1)
    r:shift("Red", 2)
    assert(hasEvent(r, "info", "selects 2nd"))
end

function T.rounds_advance_once_everyone_has_moved()
    local r = started("Red", "Blue")
    eq(r:serialize().round, 1)
    r:rolled("Red", 1, 1)
    eq(r:serialize().round, 1)
    r:rolled("Blue", 1, 2)
    eq(r:serialize().round, 2)
end

function T.pit_stop_restores_and_caps_gear()
    local r = started("Red")
    r:car("Red").rolledGear = 5
    r:brake("Red", 6)
    r:pitStop("Red")
    eq(r:car("Red").wear.wp, 18)
    r:drain()
    r:shift("Red", 5)
    assert(hasEvent(r, "warn", "4th gear is the limit"))
    r:shift("Red", 4)
    r:rolled("Red", 4, 9)
    eq(r:car("Red").maxGear, nil, "cap lifts after the first move")
end

function T.grid_orders_by_roll_and_rerolls_ties()
    local r = newRace("Red", "Blue", "Green")
    r:rollForGrid()
    r:blackDie(5, "Red")
    r:blackDie(12, "Blue")
    r:blackDie(12, "Green")
    assert(hasEvent(r, "warn", "Tie"))
    eq(#r:pendingChecks(), 2)
    r:blackDie(3, "Blue")
    r:blackDie(9, "Green")
    local order = r:serialize().order
    eq(order[1], "Green")
    eq(order[2], "Blue")
    eq(order[3], "Red")
end

function T.leaving_drops_pending_checks()
    local r = started("Red", "Blue")
    r:requestCheck("Red", "collision")
    r:leave("Red")
    eq(#r:pendingChecks(), 0)
    eq(#r:cars(), 1)
end

function T.state_survives_a_round_trip()
    local r = started("Red")
    r:brake("Red", 2)
    local copy = Race.new(Rules, r:serialize())
    eq(copy:car("Red").wear.wp, 16)
end

function T.a_move_starts_from_the_space_the_car_was_on()
    local r = newRace("Red")
    r:placed("Red", "m.s1.3")
    r:startRace()
    eq(r:car("Red").space, "m.s1.3", "starting the race does not move the car")
    r:blackDie(10, "Red")
    r:rolled("Red", 1, 2)
    eq(r:car("Red").moveFrom, "m.s1.3")
    r:drain()
    r:placed("Red", "m.s1.5")
    eq(#r:drain(), 0, "placing a car says nothing")
    eq(r:car("Red").space, "m.s1.5")
    eq(r:car("Red").moveFrom, "m.s1.3", "moving the car does not start a new move")
    r:rolled("Red", 2, 3)
    eq(r:car("Red").moveFrom, "m.s1.5")
    local copy = Race.new(Rules, r:serialize())
    eq(copy:car("Red").space, "m.s1.5")
end

function T.a_great_start_is_a_move_from_the_grid()
    local r = newRace("Red")
    r:placed("Red", "i.s11.4")
    r:startRace()
    r:blackDie(18, "Red")
    eq(r:car("Red").moveFrom, "i.s11.4")
end

function T.off_the_track_is_no_space()
    local r = started("Red")
    r:placed("Red", "m.s1.3")
    r:placed("Red", nil)
    eq(r:car("Red").space, nil)
    r:rolled("Red", 1, 2)
    eq(r:car("Red").moveFrom, nil)
end

return T
