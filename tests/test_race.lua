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

--- A gear die rolled for `color`, shifted into its gear first, as a player
-- has to: a die from another gear is not counted.
local function rollDie(r, color, gear, value)
    local car = r:car(color)
    if car and car.gear ~= gear then r:shift(color, gear) end
    r:rolled(color, gear, value)
end

--- `color`'s car put down by hand on space `id` of `track`: judged, and
-- after a roll, the end of its move -- as the Global script does on a drop.
local function putDown(r, color, id, track)
    r:placed(color, id, track)
    r:putDown(color)
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
    rollDie(r, "Red", 1, 2)
    r:shift("Red", 2)
    assert(hasEvent(r, "info", "selects 2nd"))
    rollDie(r, "Red", 2, 3)
    eq(r:car("Red").wear.wp, 18)
end

function T.skipping_up_warns_but_is_applied()
    local r = started("Red")
    rollDie(r, "Red", 1, 2)
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
    rollDie(r, "Red", 3, 6)
    eq(r:car("Red").wear.wp, 16)
end

function T.dropping_four_gears_is_flagged()
    local r = started("Red")
    r:car("Red").rolledGear = 6
    r:shift("Red", 1)
    assert(hasEvent(r, "warn", "at most 3"))
end

function T.a_die_from_another_gear_is_not_counted()
    local r = started("Red")
    r:shift("Red", 4)
    r:drain()
    r:rolled("Red", 3, 5) -- knocked, or picked up by mistake
    assert(hasEvent(r, "warn", "3rd gear die shows 5, but Red is in 4th gear %-%- not counted"))
    eq(r:car("Red").gear, 4, "still in the gear selected")
    eq(r:car("Red").lastRoll, nil)
    eq(r:serialize().round, 1, "the turn is still Red's")
end

function T.car_is_out_at_zero_and_back_after_a_correction()
    local r = started("Red")
    r:adjust("Red", nil, -18)
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
    r:adjust("Red", nil, -1)
    r:adjust("Red", "wp", 5, "bonus")
    eq(r:car("Red").wear.wp, 18)
end

function T.top_face_in_fifth_strains_all_fast_cars()
    local r = started("Red", "Blue", "Green")
    r:car("Red").rolledGear = 4
    r:car("Blue").rolledGear = 6
    r:car("Green").rolledGear = 3
    rollDie(r, "Red", 5, 20)
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
    rollDie(r, "Red", 5, 19)
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

function T.black_die_thrown_by_another_does_not_decide_a_start()
    local r = newRace("Red", "Blue")
    r:startRace()
    r:drain()
    r:blackDie(1, "Grey")
    eq(#r:pendingChecks(), 2, "both starts still wait")
    assert(hasEvent(r, "roll", "Black die: 1"))
    r:blackDie(1, "Blue")
    eq(#r:pendingChecks(), 1, "Blue's own start is Blue's to roll")
    eq(r:pendingChecks()[1].color, "Red")
end

function T.stalled_start_sits_out_a_round()
    local r = newRace("Red", "Blue")
    r:startRace()
    r:blackDie(1, "Red")
    r:blackDie(10, "Blue")
    r:drain()
    r:shift("Red", 1)
    assert(hasEvent(r, "warn", "stalled"))
    rollDie(r, "Blue", 1, 2)
    eq(r:serialize().round, 2, "round ends without the stalled car")
    r:shift("Red", 1)
    assert(hasEvent(r, "info", "selects 1st"))
end

function T.roll_checks_rolls_only_the_start_whose_turn_it_is()
    local r = newRace("Red", "Blue")
    r.autoRolls = true
    r:startRace()
    assert(not hasEvent(r, "info", "roll the black die"), "nobody is asked to roll")
    r:rollChecks(function() return 10 end)
    local checks = r:pendingChecks()
    eq(#checks, 1, "Blue's start waits for Blue's turn")
    eq(checks[1].color, "Blue")
    -- A roll made for a check settles that check, not the car's oldest.
    r:queueCheck(r:car("Blue"), "collision", "Red")
    r:rollChecks(function() return 10 end)
    eq(#r:pendingChecks(), 1)
    eq(r:pendingChecks()[1].kind, "start", "the collision was rolled, the start still waits")
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
    rollDie(r, "Red", 1, 1)
    eq(r:serialize().round, 1)
    rollDie(r, "Blue", 1, 2)
    eq(r:serialize().round, 2)
end

function T.pit_stop_restores_and_caps_gear()
    local r = started("Red")
    r:car("Red").rolledGear = 5
    r:adjust("Red", nil, -6)
    r:pitStop("Red")
    eq(r:car("Red").wear.wp, 18)
    r:drain()
    r:shift("Red", 5)
    assert(hasEvent(r, "warn", "4th gear is the limit"))
    r:shift("Red", 4)
    rollDie(r, "Red", 4, 9)
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
    eq(r.gridSettled, nil, "not settled while a tie is open")
    r:blackDie(3, "Blue")
    r:blackDie(9, "Green")
    assert(r.gridSettled, "settled once every tie is broken")
    local order = r:serialize().order
    eq(order[1], "Green")
    eq(order[2], "Blue")
    eq(order[3], "Red")
end

--- A die that comes up with each of `values` in turn.
local function loaded(values)
    local i = 0
    return function()
        i = i + 1
        return values[i]
    end
end

function T.the_grid_can_be_rolled_for_everybody()
    local r = newRace("Red", "Blue", "Green")
    r:rollForGrid(loaded({ 5, 12, 12, 3, 9 }))
    assert(r.gridSettled, "settled in one go, the tie rolled again")
    eq(#r:pendingChecks(), 0)
    eq(r:serialize().phase, "setup")
    eq(r:serialize().order[3], "Red")
    eq(#r:car("Red").gridRolls, 1, "only the tied cars rolled again")
    eq(#r:car(r:serialize().order[1]).gridRolls, 2)
    assert(hasEvent(r, "warn", "Tie"))
    assert(not hasEvent(r, "info", "roll the black die"), "nobody is asked to roll")
end

function T.a_grid_that_will_not_settle_is_left_to_the_drivers()
    local r = newRace("Red", "Blue")
    r:rollForGrid(function() return 7 end)
    eq(r.gridSettled, nil)
    eq(#r:pendingChecks(), 2, "the tie is theirs to break")
    r:drain()
    r:blackDie(8, "Red")
    r:blackDie(2, "Blue")
    assert(r.gridSettled)
    eq(r:serialize().order[1], "Red")
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
    r:adjust("Red", nil, -2)
    local copy = Race.new(Rules, r:serialize())
    eq(copy:car("Red").wear.wp, 16)
end

function T.a_move_starts_from_the_space_the_car_was_on()
    local r = newRace("Red")
    r:placed("Red", "m.s1.3")
    r:startRace()
    eq(r:car("Red").space, "m.s1.3", "starting the race does not move the car")
    r:blackDie(10, "Red")
    rollDie(r, "Red", 1, 2)
    eq(r:car("Red").move.from, "m.s1.3")
    r:drain()
    r:placed("Red", "m.s1.5")
    eq(#r:drain(), 0, "placing a car says nothing")
    r:putDown("Red")
    eq(r:car("Red").space, "m.s1.5")
    eq(r:car("Red").move.from, "m.s1.3", "moving the car does not start a new move")
    rollDie(r, "Red", 2, 3)
    eq(r:car("Red").move.from, "m.s1.5")
    local copy = Race.new(Rules, r:serialize())
    eq(copy:car("Red").space, "m.s1.5")
end

function T.a_great_start_is_a_move_from_the_grid()
    local r = newRace("Red")
    r:placed("Red", "i.s11.4")
    r:startRace()
    r:blackDie(18, "Red")
    eq(r:car("Red").move.from, "i.s11.4")
end

function T.off_the_track_is_no_space()
    local r = started("Red")
    r:placed("Red", "m.s1.3")
    r:placed("Red", nil)
    eq(r:car("Red").space, nil)
    rollDie(r, "Red", 1, 2)
    eq(r:car("Red").move, nil)
end

-- Judging moves ---------------------------------------------------------------

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

--- Red rolls `roll` in `gear` from where the car is, and is put down on `to`.
local function move(r, track, gear, roll, to)
    rollDie(r, "Red", gear, roll)
    putDown(r, "Red", to, track)
end

function T.a_car_may_go_into_its_own_pit_box()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local brown, white = FDMonaco.pit.boxes[2], FDMonaco.pit.boxes[1]
    eq(brown.player, "Brown")
    local r = started("Brown", "White")
    r:setLaps(2)
    r:placed("Brown", brown.beside, FDMonaco)
    r:placed("White", FDMonaco.pit.entry[1], FDMonaco)
    r:car("White").lap = 1
    rollDie(r, "Brown", 1, 1)
    local reach = r:reachable("Brown", FDMonaco)
    assert(reach[brown.space], "into Brown's box from beside it")
    r:drain()
    putDown(r, "Brown", brown.space, FDMonaco)
    assert(not hasEvent(r, "warn", "not a legal"), "a legal move")
    eq(r:car("Brown").space, brown.space)
    -- Another seat's box is not on offer; the way into the pit lane is.
    rollDie(r, "White", 1, 2)
    reach = r:reachable("White", FDMonaco)
    assert(reach[FDMonaco.pit.spaces[2]], "into the pit lane")
    for id in pairs(reach) do
        assert(not FDMonaco.byId[id].box, "White reaches " .. id)
    end
end

-- Pit stops -------------------------------------------------------------------

--- A race of `laps` laps, `color` on lap `lap` and put down on `id` of Monaco.
local function onMonaco(laps, color, lap, id)
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local r = started(color)
    r:setLaps(laps)
    r:placed(color, id, FDMonaco)
    r:car(color).lap = lap
    r:drain()
    return r, FDMonaco
end

function T.the_pit_lane_is_open_only_before_the_last_lap()
    local function canPit(laps, lap)
        local FDMonaco = require("fd.data.tracks.FDMonaco")
        local r = onMonaco(laps, "White", lap, FDMonaco.pit.entry[1])
        rollDie(r, "White", 1, 2)
        return r:reachable("White", FDMonaco)[FDMonaco.pit.spaces[2]] ~= nil
    end
    assert(canPit(2, 1), "at the end of the first of two laps")
    assert(not canPit(2, 2), "not on the last lap")
    assert(not canPit(1, 1), "not in a one-lap race")
end

--- Brown's pit box on Monaco, the pit lane space beside it, and the one two
-- before that.
local function brownsBox(FDMonaco)
    local b = FDMonaco.pit.boxes[2]
    eq(b.player, "Brown")
    local before = nil
    for i, id in ipairs(FDMonaco.pit.spaces) do
        if id == b.beside then before = FDMonaco.pit.spaces[i - 2] end
    end
    return b.space, b.beside, before
end

function T.overshooting_into_the_pits_is_explained()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- Before the last corner: the roll reaches the pit entry only by going
    -- through the corner without stopping.
    local r = onMonaco(2, "White", 1, "i.s10.0")
    rollDie(r, "White", 4, 10)
    for id in pairs(r:reachable("White", FDMonaco)) do
        assert(not FDMonaco.byId[id].pit, "no pits overshooting: " .. id)
    end
    assert(hasEvent(r, "info", "keep to its lane: no turning into the pits"))
    -- Stopped in the corner, the pits are open and nothing needs saying.
    local s = onMonaco(2, "White", 1, "i.c10.0")
    s:car("White").stops = 1
    rollDie(s, "White", 2, 4)
    assert(s:reachable("White", FDMonaco)[FDMonaco.pit.spaces[2]], "into the pit lane")
    assert(not hasEvent(s, "info", "no turning into the pits"))
end

function T.pit_spaces_shut_to_a_move_are_blocked()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local entry, first = FDMonaco.pit.entry[1], FDMonaco.pit.spaces[1]
    -- On the last lap the way in is shut: the pit spaces the roll would
    -- reach are listed.
    local r = onMonaco(2, "White", 2, entry)
    rollDie(r, "White", 1, 2)
    local shut = r:blockedSpaces("White", FDMonaco, r:reachable("White", FDMonaco))
    eq(table.concat(shut, ","), first .. "," .. FDMonaco.pit.spaces[2])
    -- On a lap to pit on, none are.
    local s = onMonaco(2, "White", 1, entry)
    rollDie(s, "White", 1, 2)
    eq(#s:blockedSpaces("White", FDMonaco, s:reachable("White", FDMonaco)), 0)
    -- In the pit lane, the spaces past a car ahead are.
    local t = started("White", "Red")
    t:setLaps(2)
    t:placed("White", FDMonaco.pit.spaces[3], FDMonaco)
    t:placed("Red", FDMonaco.pit.spaces[5], FDMonaco)
    rollDie(t, "White", 2, 4)
    shut = t:blockedSpaces("White", FDMonaco, t:reachable("White", FDMonaco))
    eq(table.concat(shut, ","), FDMonaco.pit.spaces[6] .. "," .. FDMonaco.pit.spaces[7],
        "past Red, and not Red's own space or anybody else's pit box")
end

function T.spaces_past_a_car_in_the_way_are_blocked()
    local track = lane(20)
    local r = started("Red", "Blue")
    r:placed("Red", "c0", track)
    r:placed("Blue", "c3", track)
    rollDie(r, "Red", 3, 6)
    local blocked = r:blockedSpaces("Red", track, r:reachable("Red", track))
    table.sort(blocked)
    eq(table.concat(blocked, ","), "c4,c5,c6", "past Blue, not Blue's own space")
end

function T.lanes_shut_by_an_overshoot_are_blocked()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- Through the last corner without stopping: the car keeps to the inside
    -- lane, and the lanes beside it are blocked.
    local r = onMonaco(1, "White", 1, "i.s10.0")
    rollDie(r, "White", 4, 10)
    local reach = r:reachable("White", FDMonaco)
    local blocked = r:blockedSpaces("White", FDMonaco, reach)
    local lanes = {}
    for _, id in ipairs(blocked) do
        assert(not reach[id], id .. " is reachable")
        lanes[FDMonaco.byId[id].lane] = true
    end
    assert(lanes[2] and lanes[0], "the middle lane and the pit lane, past the corner")
    assert(not lanes[1], "not the lane it keeps to")
    -- Going no further than the corner, nothing is blocked.
    local s = onMonaco(1, "White", 1, "i.s10.0")
    rollDie(s, "White", 1, 2)
    eq(#s:blockedSpaces("White", FDMonaco, s:reachable("White", FDMonaco)), 0)
end

function T.no_overshoot_note_when_the_pits_were_out_of_range()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local Moves = require("fd.core.moves")
    local d = Moves.steps(FDMonaco, "i.s10.0", 30)[FDMonaco.pit.entry[1]]
    -- The roll ends on the way in: the pits were one step too far anyway.
    local r = onMonaco(2, "White", 1, "i.s10.0")
    rollDie(r, "White", 4, d)
    assert(not hasEvent(r, "info", "no turning into the pits"))
    -- A step more, and they were in range.
    r = onMonaco(2, "White", 1, "i.s10.0")
    rollDie(r, "White", 4, d + 1)
    assert(hasEvent(r, "info", "no turning into the pits"))
end

function T.a_shut_pit_lane_is_no_way_round_for_the_crosses()
    -- A pit lane that is a short cut: in at c1, out at c6.
    local spaces = {}
    for k = 0, 9 do
        spaces[#spaces + 1] = { id = "c" .. k, lane = 1, next = k < 9 and { "c" .. (k + 1) } or {} }
    end
    spaces[2].next = { "c2", "p0" }
    spaces[#spaces + 1] = { id = "p0", lane = 0, pit = true, next = { "c6" } }
    local track = { spaces = spaces, corners = {} }
    local r = started("Red") -- one lap: the pit lane is shut
    r:placed("Red", "c0", track)
    r:car("Red").lap = 1
    rollDie(r, "Red", 2, 4)
    local blocked = r:blockedSpaces("Red", track, r:reachable("Red", track))
    eq(table.concat(blocked, ","), "p0", "the pit lane, but not c6 the far side of it")
end

function T.taking_a_pit_stop_back_keeps_a_correction_made_since()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local box, _, before = brownsBox(FDMonaco)
    local r = onMonaco(2, "Brown", 1, before)
    r:adjust("Brown", nil, -6)
    rollDie(r, "Brown", 2, 4)
    putDown(r, "Brown", box, FDMonaco)
    eq(r:car("Brown").wear.wp, 18)
    r:adjust("Brown", nil, -2)
    putDown(r, "Brown", FDMonaco.pit.spaces[6], FDMonaco)
    eq(r:car("Brown").wear.wp, 10, "the 6 the stop gave back taken off the 16 it had")
end

function T.the_race_finds_spaces_on_a_track_the_editor_changes()
    local Race = require("fd.core.race")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- As the editor hands it over: its own spaces list, and no byId.
    local spaces = {}
    for i, s in ipairs(FDMonaco.spaces) do spaces[i] = s end
    local track = { spaces = spaces, pit = FDMonaco.pit, corners = FDMonaco.corners }
    local r = newRace("Red")
    r:useTrack(track)
    eq(r:space("i.s1.0").id, "i.s1.0")
    -- A space added in place, and the race told to forget, as the editor does.
    spaces[#spaces + 1] = { id = "i.s1.0+1", lane = 1, pos = { 0, 0 }, rot = 0, next = {} }
    Race.forget()
    eq(r:space("i.s1.0+1").id, "i.s1.0+1")
end

function T.a_car_over_the_line_in_the_pit_lane_is_still_on_its_way_in()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local last = FDMonaco.pit.spaces[#FDMonaco.pit.spaces]
    local r = onMonaco(2, "White", 1, FDMonaco.pit.entry[1])
    rollDie(r, "White", 5, 19)
    putDown(r, "White", last, FDMonaco)
    eq(r:car("White").lap, 2, "over the line in the pit lane")
    r:drain()
    -- Put down again on the same move: still a legal move into the pits.
    putDown(r, "White", FDMonaco.pit.spaces[#FDMonaco.pit.spaces - 3], FDMonaco)
    assert(not hasEvent(r, "warn", "not a legal"))
    eq(r:car("White").lap, 1)
end

function T.stopping_in_its_own_pit_box_is_a_pit_stop()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local box, _, before = brownsBox(FDMonaco)
    local r = onMonaco(2, "Brown", 1, before)
    r:adjust("Brown", nil, -6)
    r:drain()
    -- Three spaces to the box on a roll of four: no exact roll needed.
    rollDie(r, "Brown", 2, 4)
    eq(r:reachable("Brown", FDMonaco)[box].brake, 0, "nothing to brake into the box")
    putDown(r, "Brown", box, FDMonaco)
    eq(r:car("Brown").wear.wp, 18, "WP back")
    eq(r:car("Brown").maxGear, 4, "and out in 4th at most")
    assert(hasEvent(r, "info", "pits: wear restored"))
    -- Put down further on instead, it has not stopped: the stop is taken back.
    local on = FDMonaco.pit.spaces[6]
    putDown(r, "Brown", on, FDMonaco)
    eq(r:car("Brown").wear.wp, 12, "the WP it had")
    eq(r:car("Brown").maxGear, nil)
    assert(hasEvent(r, "info", "pit stop taken back"))
    putDown(r, "Brown", box, FDMonaco)
    eq(r:car("Brown").wear.wp, 18, "stopped again")
    -- Back where the move started: no stop.
    putDown(r, "Brown", before, FDMonaco)
    eq(r:car("Brown").wear.wp, 12)
end

function T.braking_costs_nothing_in_the_pit_lane()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local r = onMonaco(2, "Brown", 1, FDMonaco.pit.spaces[3])
    rollDie(r, "Brown", 2, 4)
    putDown(r, "Brown", FDMonaco.pit.spaces[4], FDMonaco)
    eq(r:car("Brown").wear.wp, 18, "three short, in the pit lane")
    -- Stuck behind a car in the pit lane: no cost either.
    local s = started("Brown", "Red")
    s:setLaps(2)
    s:placed("Brown", FDMonaco.pit.spaces[3], FDMonaco)
    s:placed("Red", FDMonaco.pit.spaces[5], FDMonaco)
    rollDie(s, "Brown", 2, 4)
    eq(s:reachable("Brown", FDMonaco)[FDMonaco.pit.spaces[6]], nil, "no way past")
    putDown(s, "Brown", FDMonaco.pit.spaces[4], FDMonaco)
    eq(s:car("Brown").wear.wp, 18)
end

function T.shifting_down_is_free_in_the_pit_lane()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local box = brownsBox(FDMonaco)
    local r = onMonaco(2, "Brown", 1, box)
    r:car("Brown").rolledGear = 6
    r:shift("Brown", 1)
    assert(not hasEvent(r, "warn", ""), "six to one is no skip in the pits")
    rollDie(r, "Brown", 1, 1)
    eq(r:car("Brown").wear.wp, 18)
    -- On the circuit the rule stands.
    local s = onMonaco(2, "Brown", 1, "m.s2.5")
    s:car("Brown").rolledGear = 6
    s:shift("Brown", 1)
    assert(hasEvent(s, "warn", "at most 3 gears"))
end

function T.engine_strain_spares_the_pit_lane()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local r = started("Red", "Blue", "Green")
    r:setLaps(2)
    r:placed("Red", FDMonaco.pit.spaces[5], FDMonaco)
    r:placed("Blue", "m.s2.5", FDMonaco)
    r:placed("Green", FDMonaco.pit.spaces[8], FDMonaco)
    r:car("Red").rolledGear = 6
    r:car("Blue").rolledGear = 4
    r:car("Green").rolledGear = 4
    rollDie(r, "Blue", 5, 20)
    local checks = r:pendingChecks()
    eq(#checks, 1, "Red is in the pit lane")
    eq(checks[1].color, "Blue")
    -- And a roll from the pit lane sets none off.
    r:blackDie(10, "Blue")
    rollDie(r, "Green", 5, 20)
    eq(#r:pendingChecks(), 0)
end

function T.nothing_collides_in_the_pit_lane()
    -- A pit lane whose spaces are listed as touching all the same.
    local spaces = {}
    for k = 0, 5 do
        spaces[#spaces + 1] = { id = "p" .. k, lane = 0, pit = true, next = k < 5 and { "p" .. (k + 1) } or {} }
    end
    local track = { spaces = spaces, corners = {}, near = { p2 = { "p3" }, p3 = { "p2" } } }
    local r = started("Red", "Blue")
    r:placed("Red", "p3", track)
    r:placed("Blue", "p0", track)
    rollDie(r, "Blue", 1, 2)
    putDown(r, "Blue", "p2", track)
    eq(#r:pendingChecks(), 0)
end

function T.cars_in_the_pit_lane_play_after_the_circuit()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local box = brownsBox(FDMonaco)
    local r = started("Brown", "Red")
    r:setLaps(2)
    for _, c in ipairs({ "Brown", "Red" }) do r:car(c).lap = 1 end
    -- Brown in its pit box, near the end of the lap; Red far behind.
    r:placed("Red", "m.s2.5", FDMonaco)
    r:placed("Brown", box, FDMonaco)
    eq(r:turn().color, "Red", "the circuit first")
    -- On the circuit beside the pit lane, Brown leads again.
    r:placed("Brown", "i.s11.10", FDMonaco)
    eq(r:turn().color, "Brown")
end

function T.a_disputed_move_into_the_pits_still_crosses_the_line()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local r = started("Red")
    r:placed("Red", FDMonaco.pit.entry[1], FDMonaco)
    local lap = r:car("Red").lap
    rollDie(r, "Red", 1, 1)
    r:drain()
    -- From the track, down the whole pit lane and over the line in it, on a
    -- roll of one.
    putDown(r, "Red", FDMonaco.pit.spaces[#FDMonaco.pit.spaces], FDMonaco)
    assert(hasEvent(r, "warn", "not a legal"))
    eq(r:car("Red").lap, lap + 1, "the lap still counts")
end

function T.braking_is_charged_and_rejudged()
    local track = lane(20)
    local r = started("Red")
    r:placed("Red", "c0")
    move(r, track, 1, 2, "c1")
    eq(r:car("Red").wear.wp, 17)
    assert(hasEvent(r, "wear", "braked 1 short"))
    putDown(r, "Red", "c2", track)
    eq(r:car("Red").wear.wp, 18)
    putDown(r, "Red", "c1", track)
    eq(r:car("Red").wear.wp, 17)
    -- Put back where it started, it has not moved: nothing charged.
    putDown(r, "Red", "c0", track)
    eq(r:car("Red").wear.wp, 18, "refunded")
    assert(hasEvent(r, "info", "back where its move started"))
end

function T.back_at_the_start_takes_back_what_the_move_set_off()
    local track = lane(20)
    local r = started("Red", "Blue")
    r:placed("Red", "c0")
    r:placed("Blue", "c9")
    r.state.order = { "Red", "Blue" }
    move(r, track, 1, 2, "c2")
    eq(r:car("Red").movedRound, r.state.round, "put down: done")
    -- Back to where it started before Blue rolls: the turn comes back.
    putDown(r, "Red", "c0", track)
    eq(r:car("Red").movedRound, nil)
    eq(r:turn().color, "Red")
    -- Once Blue has rolled, it does not.
    move(r, track, 1, 2, "c2")
    rollDie(r, "Blue", 1, 2)
    putDown(r, "Red", "c0", track)
    eq(r:car("Red").movedRound, r.state.round, "Blue is moving: Red's turn stays over")
end

function T.an_unreachable_space_warns_and_charges_nothing()
    local track = lane(20)
    local r = started("Red")
    r:placed("Red", "c0")
    move(r, track, 1, 2, "c1")
    r:drain()
    putDown(r, "Red", "c9", track)
    assert(hasEvent(r, "warn", "not a legal 2 from c0"))
    eq(r:car("Red").wear.wp, 18, "the brake charged before is given back")
end

function T.overshooting_is_charged()
    local track = lane(20, { 2, 4, 1 })
    local r = started("Red")
    r:placed("Red", "c0")
    move(r, track, 3, 7, "c7")
    eq(r:car("Red").wear.wp, 15)
    assert(hasEvent(r, "wear", "overshot corner 1 by 3"))
end

function T.stops_carry_from_move_to_move()
    local track = lane(20, { 2, 6, 2 })
    local r = started("Red")
    r:placed("Red", "c0")
    move(r, track, 1, 2, "c2")
    eq(r:car("Red").stops, 1)
    move(r, track, 1, 2, "c4")
    eq(r:car("Red").stops, 2)
    move(r, track, 2, 4, "c8")
    eq(r:car("Red").wear.wp, 18, "two stops made: free to leave")
    eq(r:car("Red").stops, 0)
end

function T.missing_two_stops_is_out_and_a_correction_brings_it_back()
    local track = lane(20, { 2, 6, 2 })
    local r = started("Red")
    r:placed("Red", "c0")
    move(r, track, 3, 8, "c8")
    assert(r:car("Red").eliminated)
    assert(hasEvent(r, "out", "corner 1 without its stops"))
    putDown(r, "Red", "c6", track)
    assert(not r:car("Red").eliminated)
    eq(r:car("Red").wear.wp, 16, "braked 2, stopped in the corner")
end

function T.reachable_is_what_the_move_will_be_judged_by()
    local track = lane(20, { 2, 6, 2 })
    local r = started("Red")
    eq(r:reachable("Red", track), nil, "no move open")
    r:placed("Red", "c0")
    rollDie(r, "Red", 3, 8)
    eq(r.opened, "Red", "the Global script is told a move opened")
    local reach = r:reachable("Red", track)
    eq(reach.c8.missed, 2)
    assert(r:moveOut(reach.c8), "through a 2-stop corner without stopping is out")
    assert(not r:moveOut(reach.c6))
    eq(reach.c6.brake, 2)
end

function T.cars_in_the_way_are_where_they_were_at_the_roll()
    -- Two lanes wide, Blue sitting in Red's lane.
    local track = { corners = {}, spaces = {} }
    for k = 0, 9 do
        track.spaces[#track.spaces + 1] = { id = "i" .. k, lane = 1, next = { "i" .. (k + 1), "o" .. (k + 1) } }
        track.spaces[#track.spaces + 1] = { id = "o" .. k, lane = 2, next = { "o" .. (k + 1), "i" .. (k + 1) } }
    end
    local r = started("Red", "Blue")
    r:placed("Red", "i0")
    r:placed("Blue", "i2")
    rollDie(r, "Red", 1, 2)
    r:placed("Blue", "o7") -- Blue moves on after Red rolled
    putDown(r, "Red", "i2", track)
    assert(hasEvent(r, "warn", "not a legal"), "Blue was there")
end

-- Collisions ------------------------------------------------------------------

--- Two lanes, i0 .. i9 and o0 .. o9, side by side, each space touching the
-- ones ahead, behind and beside it, diagonals included.
local function twoLanes()
    local track = { corners = {}, spaces = {}, near = {} }
    for k = 0, 9 do
        track.spaces[#track.spaces + 1] = { id = "i" .. k, lane = 1, next = { "i" .. (k + 1), "o" .. (k + 1) } }
        track.spaces[#track.spaces + 1] = { id = "o" .. k, lane = 2, next = { "o" .. (k + 1), "i" .. (k + 1) } }
        for _, l in ipairs({ { "i", "o" }, { "o", "i" } }) do
            local near = { l[2] .. k }
            for _, d in ipairs({ -1, 1 }) do
                if k + d >= 0 and k + d <= 9 then
                    near[#near + 1] = l[1] .. (k + d)
                    near[#near + 1] = l[2] .. (k + d)
                end
            end
            track.near[l[1] .. k] = near
        end
    end
    return track
end

local function collisionChecks(r, color)
    local out = {}
    for _, c in ipairs(r:pendingChecks()) do
        if c.color == color and c.kind == "collision" then out[#out + 1] = c.with or "manual" end
    end
    table.sort(out)
    return table.concat(out, ",")
end

--- Roll the black die for every check as it comes, `value` each time,
-- until none are left; returns how many times each "roller>other" came up.
local function rollAll(r, value)
    local rolled = {}
    for _ = 1, 100 do
        local c = r:pendingChecks()[1]
        if not c then return rolled end
        local key = c.color .. ">" .. tostring(c.with)
        rolled[key] = (rolled[key] or 0) + 1
        r:blackDie(value, c.color)
    end
    error("the checks never ran out")
end

function T.ending_beside_cars_rolls_once_for_each()
    local track = twoLanes()
    local r = started("Red", "Blue", "Grey", "Green")
    r:placed("Red", "i0")
    r:placed("Blue", "o3")  -- beside where Red ends
    r:placed("Grey", "i3")  -- directly ahead
    r:placed("Green", "o6") -- nowhere near
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    eq(collisionChecks(r, "Red"), "Blue,Grey")
    assert(hasEvent(r, "info", "Red: roll the black die %(collision with Blue check%)"))
    r:blackDie(3, "Red")
    r:blackDie(15, "Red")
    eq(r:car("Red").wear.wp, 17, "one roll lost a point, the other did not")
    eq(collisionChecks(r, "Red"), "")
end

function T.a_collision_roll_spreads_until_each_pair_has_rolled_twice()
    -- A chain: Red ends touching Blue, Blue touches Grey, Grey touches
    -- Green. Nobody else touches Red, and Purple is clear of them all.
    local track = twoLanes()
    local r = started("Red", "Blue", "Grey", "Green", "Purple")
    r:placed("Red", "i0")
    r:placed("Blue", "i3")
    r:placed("Grey", "i4")
    r:placed("Green", "o5")
    r:placed("Purple", "i9")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    eq(collisionChecks(r, "Red"), "Blue", "the mover only rolls for cars it touches")
    eq(collisionChecks(r, "Blue"), "", "nobody else rolls until the mover has")
    r:blackDie(10, "Red")
    eq(collisionChecks(r, "Blue"), "Grey,Red", "Blue rolls back, and against Grey")
    local rolled = rollAll(r, 10)
    rolled["Red>Blue"] = 1
    local keys = {}
    for k, n in pairs(rolled) do
        eq(n, 1, k .. " rolled once")
        keys[#keys + 1] = k
    end
    table.sort(keys)
    eq(table.concat(keys, " "), "Blue>Grey Blue>Red Green>Grey Grey>Blue Grey>Green Red>Blue")
    eq(r:car("Purple").wear.wp, 18)
end

function T.rolls_owed_survive_the_mover_moving_on()
    local track = twoLanes()
    local r = started("Red", "Blue")
    r:placed("Red", "i0")
    r:placed("Blue", "o3")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    r:blackDie(10, "Red")
    eq(collisionChecks(r, "Blue"), "Red")
    -- Red is off on its next move, clear of everyone, before Blue rolls back.
    rollDie(r, "Red", 2, 4)
    putDown(r, "Red", "i6", track)
    r:blackDie(10, "Blue")
    eq(collisionChecks(r, "Red"), "", "Red already rolled against Blue")
    eq(#r:pendingChecks(), 0)
    local n = 0
    for _ in pairs(r:serialize().packs) do n = n + 1 end
    eq(n, 1, "only the pack Red's open move could redraw is kept")
end

function T.collision_state_survives_a_round_trip()
    local track = twoLanes()
    local r = started("Red", "Blue")
    r:placed("Red", "i0")
    r:placed("Blue", "o3")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    r = Race.new(Rules, r:serialize())
    r:blackDie(10, "Red")
    eq(collisionChecks(r, "Blue"), "Red", "the roll back still comes after a reload")
end

function T.every_car_in_the_pack_pays_for_its_own_rolls()
    local track = twoLanes()
    local r = started("Red", "Blue", "Grey")
    r:placed("Red", "i0")
    r:placed("Blue", "o3")
    r:placed("Grey", "i3")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    rollAll(r, 1)
    -- All three touch each other: two rolls each, both lost.
    eq(r:car("Red").wear.wp, 16)
    eq(r:car("Blue").wear.wp, 16)
    eq(r:car("Grey").wear.wp, 16)
end

function T.moving_away_drops_the_checks_not_yet_rolled()
    local track = twoLanes()
    local r = started("Red", "Blue", "Grey")
    r:placed("Red", "i0")
    r:placed("Blue", "o3")
    r:placed("Grey", "i3")
    rollDie(r, "Red", 2, 3)
    putDown(r, "Red", "i2", track)
    eq(collisionChecks(r, "Red"), "Blue,Grey")
    r:blackDie(10, "Red") -- Blue's, rolled
    r:drain()
    putDown(r, "Red", "o1", track)
    eq(collisionChecks(r, "Red"), "", "Grey's dropped; Blue's already rolled")
    assert(hasEvent(r, "info", "no longer next to Grey"))
    putDown(r, "Red", "i2", track)
    eq(collisionChecks(r, "Red"), "Grey", "back beside Grey; Blue is not rolled for twice")
end

function T.cars_out_or_finished_are_not_hit()
    local track = twoLanes()
    local r = started("Red", "Blue", "Grey")
    r:placed("Red", "i0")
    r:placed("Blue", "o3")
    r:placed("Grey", "i3")
    r:car("Blue").eliminated = true
    r:car("Grey").place = 1
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    eq(collisionChecks(r, "Red"), "")
end

function T.no_neighbour_data_means_no_automatic_checks()
    local track = twoLanes()
    track.near = nil
    local r = started("Red", "Blue")
    r:placed("Red", "i0")
    r:placed("Blue", "o2")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i2", track)
    eq(collisionChecks(r, "Red"), "")
    r:requestCheck("Red", "collision")
    eq(collisionChecks(r, "Red"), "manual", "the button still works")
end

-- Laps and the finish ---------------------------------------------------------

--- A one-lane loop of 20 cells, c0 .. c19, with the line just before c0.
local function loop()
    local spaces = {}
    for k = 0, 19 do
        spaces[#spaces + 1] = { id = "c" .. k, lane = 1, next = { "c" .. ((k + 1) % 20) } }
    end
    return { spaces = spaces, corners = {}, finish = { line = { "c0" } } }
end

--- `color` rolls `roll` in 5th and is put down on `to`.
local function drive(r, track, color, roll, to)
    rollDie(r, color, 5, roll)
    putDown(r, color, to, track)
end

function T.the_first_crossing_starts_the_lap_and_the_next_one_finishes()
    local track = loop()
    local r = started("Red")
    r:placed("Red", "c18")
    drive(r, track, "Red", 4, "c2")
    eq(r:car("Red").lap, 1, "off the grid and over the line")
    eq(r:car("Red").place, nil)
    drive(r, track, "Red", 15, "c17")
    drive(r, track, "Red", 3, "c0")
    eq(r:car("Red").place, 1)
    assert(hasEvent(r, "finish", "Red wins the race"))
    eq(r:serialize().phase, "finished", "the only car is home")
end

function T.moving_on_from_the_line_does_not_finish_a_one_lap_race()
    -- Game night (#21): pole stopped just over the line, then moved on
    -- across the staggered line spaces and took the flag on lap 1.
    local Monaco = require("fd.data.tracks.FDMonaco")
    local r = started("Red")
    r:placed("Red", Monaco.start[1])
    drive(r, Monaco, "Red", 1, "o.s1.0")
    eq(r:car("Red").lap, 1, "over the line")
    drive(r, Monaco, "Red", 2, "i.s1.1")
    eq(r:car("Red").lap, 1, "on along it")
    eq(r:car("Red").place, nil)
    assert(not hasEvent(r, "finish", "wins"))
end

function T.the_race_runs_until_every_car_is_home()
    local track = loop()
    local r = started("Red", "Blue")
    r:placed("Red", "c18")
    r:placed("Blue", "c17")
    r:car("Red").lap = 1
    r:car("Blue").lap = 1
    drive(r, track, "Red", 4, "c2")
    assert(hasEvent(r, "finish", "Red wins"))
    eq(r:serialize().phase, "race")
    drive(r, track, "Blue", 2, "c19")
    eq(r:serialize().round, 2, "a finished car does not hold up the round")
    drive(r, track, "Blue", 2, "c1")
    local events = r:drain()
    local result = nil
    for _, e in ipairs(events) do
        if e.text:find("Result") then result = e.text end
    end
    assert(result and result:find("1st Red, 2nd Blue"), "result announced: " .. tostring(result))
    eq(r:serialize().phase, "finished")
end

function T.putting_a_car_back_short_of_the_line_takes_the_finish_back()
    local track = loop()
    local r = started("Red", "Blue")
    r:placed("Red", "c18")
    r:placed("Blue", "c10")
    r:car("Red").lap = 1
    r:car("Blue").lap = 1
    drive(r, track, "Red", 4, "c2")
    eq(r:car("Red").place, 1)
    putDown(r, "Red", "c19", track)
    eq(r:car("Red").place, nil)
    eq(r:car("Red").lap, 1)
    eq(#r:serialize().finishers, 0)
    putDown(r, "Red", "c1", track)
    eq(r:car("Red").place, 1, "and over it again")
    eq(r:car("Red").lap, 2, "counted once for the move")
end

function T.a_space_the_roll_cannot_reach_still_counts_as_crossing()
    local track = loop()
    local r = started("Red")
    r:placed("Red", "c18")
    r:car("Red").lap = 1
    drive(r, track, "Red", 2, "c5")
    assert(r:car("Red").place == 1, "the table ruled: over the line")
end

function T.two_laps_need_two_trips_round()
    local track = loop()
    local r = started("Red")
    r:setLaps(2)
    r:placed("Red", "c18")
    drive(r, track, "Red", 4, "c2")
    drive(r, track, "Red", 18, "c0")
    assert(hasEvent(r, "lap", "starts lap 2 of 2 %-%- last lap"))
    eq(r:progress(r:car("Red")), "lap 2/2")
    eq(r:car("Red").place, nil)
    drive(r, track, "Red", 19, "c19")
    drive(r, track, "Red", 1, "c0")
    eq(r:car("Red").place, 1)
    eq(r:progress(r:car("Red")), "finished 1st")
end

function T.cutting_the_race_short_finishes_the_cars_already_past_it()
    local track = loop()
    local r = started("Red", "Blue")
    r:setLaps(2)
    r:car("Red").lap = 2
    r:car("Blue").lap = 1
    r:setLaps(1)
    eq(r:car("Red").place, 1)
    eq(r:car("Blue").place, nil)
    r:setLaps(2)
    eq(r:car("Red").place, nil, "and back again")
end

function T.the_race_is_over_when_the_rest_are_out()
    local track = loop()
    local r = started("Red", "Blue")
    r:placed("Red", "c18")
    r:car("Red").lap = 1
    drive(r, track, "Red", 4, "c2")
    eq(r:serialize().phase, "race")
    r:adjust("Blue", nil, -18)
    eq(r:serialize().phase, "finished")
    eq(r:standings()[2].color, "Blue")
    r:adjust("Blue", nil, 3)
    eq(r:serialize().phase, "race", "a correction reopens it")
end

function T.a_car_that_goes_out_on_the_line_does_not_finish()
    local track = loop()
    local r = started("Red", "Blue")
    r:placed("Red", "c18")
    r:car("Red").lap = 1
    r:car("Red").wear.wp = 1
    drive(r, track, "Red", 5, "c1") -- over the line, braking 2 with 1 WP left
    local events = r:drain()
    for _, e in ipairs(events) do
        assert(e.level ~= "finish", "no flag for a car going out: " .. e.text)
    end
    assert(r:car("Red").eliminated)
    eq(r:car("Red").place, nil)
    eq(r:car("Red").lap, 2, "the crossing still counts")
    r:adjust("Red", nil, 5, "ruling")
    eq(r:car("Red").place, 1, "put back in the race, it has finished")
    assert(hasEvent(r, "finish", "Red wins"))
    r:adjust("Red", nil, -18)
    eq(r:car("Red").place, nil, "and out again, it has not")
    eq(#r:serialize().finishers, 0)
end

-- Turn order ------------------------------------------------------------------

local FDMonaco = require("fd.data.tracks.FDMonaco")

local function order(r)
    return table.concat(r:serialize().order, " ")
end

function T.the_leader_on_the_track_plays_first()
    local r = started("Red", "Blue")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s2.3")
    r:placed("Blue", "m.s2.8")
    eq(order(r), "Blue Red")
    assert(hasEvent(r, "order", "Order of play for round 1: 1%. Blue  2%. Red"))
    eq(r:turn().color, "Blue")
end

function T.a_stop_in_a_corner_is_counted_for_the_corner_line()
    local r = started("Red")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s1.5")
    eq(r:cornerAhead(r:car("Red")).here, nil, "on the straight")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i.c1.1", FDMonaco)
    local a = r:cornerAhead(r:car("Red"))
    eq(a.here.corner, 1)
    eq(a.here.made, 1, "the stop just made")
    eq(a.here.need, 1)
    eq(a.corner, 2, "its one stop made: corner 2 is next")
end

function T.the_round_moves_on_when_the_last_car_is_put_down()
    local r = started("Red", "Blue")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s2.10")
    r:placed("Blue", "i.s2.3")
    rollDie(r, "Red", 1, 2)
    eq(r:turn().color, "Red", "rolled, but the car is still to move")
    putDown(r, "Red", "i.s2.12", FDMonaco)
    eq(r:turn().color, "Blue")
    rollDie(r, "Blue", 1, 2)
    eq(r:serialize().round, 1, "not until Blue's car is down")
    r:drain()
    putDown(r, "Blue", "m.s2.15", FDMonaco)
    eq(r:serialize().round, 2)
    eq(order(r), "Blue Red", "the new round's order, from where the cars ended")
    assert(hasEvent(r, "order", "Round 2 %-%- 1%. Blue"))
    rollDie(r, "Blue", 2, 4)
    putDown(r, "Red", "m.s2.17", FDMonaco)
    eq(order(r), "Blue Red", "fixed once the round is under way")
end

function T.a_stray_die_does_not_play_anybody_s_turn()
    local r = started("Red", "Blue")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s2.10")
    r:placed("Blue", "i.s2.3")
    rollDie(r, "Red", 1, 2)
    putDown(r, "Red", "i.s2.12", FDMonaco)
    rollDie(r, "Blue", 1, 2)
    r:drain()
    -- Red, done for the round, knocks their die while Blue moves.
    r:rolled("Red", 1, 1)
    assert(hasEvent(r, "warn", "Blue is still moving %-%- Red's roll of 1 not counted"))
    eq(r:car("Red").lastRoll, 2)
    eq(r:serialize().round, 1)
    eq(r:turn().color, "Blue", "Blue is still moving")
    eq(r:car("Blue").move.roll, 2)
end

function T.rolling_on_ends_a_move_whose_car_was_never_put_down()
    local r = started("Red", "Blue")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s2.10")
    r:placed("Blue", "i.s2.3")
    rollDie(r, "Red", 1, 2)
    rollDie(r, "Blue", 1, 2) -- Red's car never put down
    eq(r:car("Blue").lastRoll, nil, "the first roll waits for Red")
    rollDie(r, "Blue", 1, 2) -- and the second goes on without them
    eq(r:car("Red").movedRound, 1)
    eq(r:car("Blue").lastRoll, 2)
    eq(r:turn().color, "Blue")
    -- And the last car of the round, never put down either: the next
    -- round's first roll, made twice, ends it.
    rollDie(r, "Red", 2, 3)
    eq(r:serialize().round, 1)
    rollDie(r, "Red", 2, 3)
    eq(r:serialize().round, 2)
    eq(r:car("Red").lastRoll, 3, "counted, in the new round")
end

function T.level_cars_go_by_gear_then_the_inside()
    local r = started("Red", "Blue")
    r:useTrack(FDMonaco)
    -- Level on the straight into corner 2, which turns left: the outside
    -- lane of the lap is its inside.
    r:placed("Red", "i.s2.8")
    r:placed("Blue", "o.s2.7")
    eq(order(r), "Blue Red", "same gear: nearer the inside of the next corner")
    r:car("Red").rolledGear = 3
    r:reorder()
    eq(order(r), "Red Blue", "higher gear first")
end

function T.a_lap_ahead_is_ahead()
    local r = started("Red", "Blue")
    r:useTrack(FDMonaco)
    r:car("Blue").lap = 1
    r:placed("Red", "o.s11.15")
    r:placed("Blue", "m.s1.2")
    eq(order(r), "Blue Red")
end

function T.cars_it_cannot_place_keep_their_slot()
    local r = started("Red", "Blue", "Grey")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s2.3")
    r:placed("Grey", "m.s2.10")
    eq(order(r), "Grey Blue Red", "Blue is off the track: the others go round it")
end

function T.rolling_out_of_turn_warns_and_is_played()
    local r = started("Red", "Blue")
    rollDie(r, "Blue", 1, 3)
    assert(hasEvent(r, "warn", "Blue rolls out of turn %-%- Red plays first"))
    eq(r:car("Blue").lastRoll, 3)
    eq(r:turn().color, "Red")
    rollDie(r, "Red", 1, 3)
    assert(not hasEvent(r, "warn", "out of turn"))
    eq(r:serialize().round, 2)
end

function T.places_have_the_right_suffix()
    local names = {}
    for _, n in ipairs({ 1, 2, 3, 4, 11, 12, 13, 21, 22 }) do names[#names + 1] = Race.placeName(n) end
    eq(table.concat(names, " "), "1st 2nd 3rd 4th 11th 12th 13th 21st 22nd")
end

return T
