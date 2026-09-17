-- Drives src/entry/Global.-1.lua against the fake TTS API in tts_stub.lua.

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

local NAMES = { "First", "Second", "Third", "Fourth", "Fifth", "Sixth" }

--- Fresh stub world and a freshly loaded Global script.
local function world()
    for name in pairs(package.loaded) do
        if name == "tts_stub" or name:sub(1, 3) == "fd." then
            package.loaded[name] = nil
        end
    end
    local S = require("tts_stub")
    S.object("Gear Stick Bag", { guid = "71d89b", spawns = "Gear Stick" })
    S.object("Wear Tracker Bag", { guid = "a845cd", spawns = "Wear Tracker" })
    S.object("Formula 1 Black Bag", { guid = "1bb99e", spawns = "Formula 1 Solid" })
    for _, n in ipairs(NAMES) do
        S.object(n .. " Gear Dice", { pos = S.vec(40, 1, 40) })
    end
    S.object("Damage Dice")
    -- A beginner dashboard (flipped) near Red's seat, an advanced one near Blue's.
    S.beginner = S.object("Beginner Dashboard", { pos = S.vec(0, 1, -30), up = S.vec(0, -1, 0) })
    S.advanced = S.object("Advanced Dashboard", { pos = S.vec(0, 1, 30) })
    S.player("Red", S.vec(0, 1, -38))
    S.player("Blue", S.vec(0, 1, 38))
    assert(loadfile(ROOT .. "/src/entry/Global.-1.lua"))()
    onLoad("")
    return S
end

local function state()
    return onSave().json.race
end

--- Red joins at the beginner dashboard and gets the race under way.
local function redRacing()
    local S = world()
    S.beginner.click("fdDashJoin", "Red")
    fdStart({ steam_name = "host", color = "Red" })
    local black = S.find("Damage Dice")
    black.value = 10
    onObjectRandomize(black, "Red")
    return S
end

--- Drop `obj` at the world position of a dashboard slot.
local function dropOn(S, obj, slot, n)
    local Dashboard = require("fd.tts.dashboard")
    local p = Dashboard.worldSlot(S.beginner, slot, n)
    obj.pos = S.vec(p.x, p.y, p.z)
    onObjectDrop("Red", obj)
end

local function roll(S, gear, value, color)
    local die = S.find(NAMES[gear] .. " Gear Dice")
    die.value = value
    onObjectRandomize(die, color or "Red")
end

local T = {}

function T.load_builds_the_panel_and_teaches_the_dice()
    local S = world()
    assert(S.ui.fdr_title, "race panel refreshed")
    eq(S.ui.showModMenuButton.active, "true", "mod menu button kept")
    eq(#S.find("Sixth Gear Dice").rotationValues, 30)
    eq(#S.find("First Gear Dice").rotationValues, 4)
end

function T.free_dashboards_offer_join()
    local S = world()
    eq(#S.beginner.buttons, 1)
    eq(S.beginner.buttons[1].click_function, "fdDashJoin")
    eq(S.advanced.buttons[1].click_function, "fdDashJoin")
end

function T.joining_from_a_dashboard_claims_it_and_places_markers()
    local S = world()
    S.beginner.click("fdDashJoin", "Red")
    eq(state().cars.Red.tts.dash, S.beginner.guid)
    eq(S.count("Gear Stick"), 1)
    eq(S.count("Wear Tracker"), 1)
    eq(S.beginner.buttons[1].click_function, "fdNoop", "status label first")
    assert(S.beginner.buttons[1].label:find("18 WP"), S.beginner.buttons[1].label)
    eq(S.beginner.buttons[1].position[2], -0.55, "drawn on the face that is up")
end

function T.buttons_read_the_same_way_as_the_printed_art()
    local S = world()
    S.beginner.click("fdDashJoin", "Red")
    S.advanced.click("fdDashJoin", "Blue")
    local function row(dash)
        local out = {}
        for _, b in ipairs(dash.buttons) do
            if b.click_function ~= "fdNoop" then
                out[#out + 1] = { x = b.position[1], label = b.label, rot = b.rotation }
            end
        end
        table.sort(out, function(a, b) return a.x < b.x end)
        return out
    end
    -- Left to right as the art reads: the beginner face is flipped, so its
    -- buttons run the other way along X, and its text is turned to match.
    local beginner = row(S.beginner)
    eq(beginner[1].label, "Car")
    eq(beginner[#beginner].label, "Leave")
    eq(beginner[1].rot[2], 180)
    eq(beginner[1].rot[3], 180)
    local advanced = row(S.advanced)
    eq(advanced[1].label, "Leave")
    eq(advanced[#advanced].label, "Car")
    eq(advanced[1].rot[2], 0)
    eq(advanced[1].rot[3], 0)
end

function T.a_claimed_dashboard_cannot_be_taken()
    local S = world()
    S.beginner.click("fdDashJoin", "Red")
    eq(S.beginner.buttons[1].click_function, "fdNoop", "join button gone")
    fdDashJoin(S.beginner, "Blue") -- a click that raced the redraw
    eq(state().cars.Blue, nil)
    assert(S.logged("already using"))
end

function T.spectators_cannot_join()
    local S = world()
    S.beginner.click("fdDashJoin", "Grey")
    eq(state().cars.Grey, nil)
end

function T.advanced_face_warns_instead_of_placing_wear()
    local S = world()
    S.advanced.click("fdDashJoin", "Blue")
    eq(S.count("Wear Tracker"), 0)
    assert(S.logged("beginner side"))
    eq(S.advanced.buttons[1].position[2], 0.7)
end

function T.dropping_the_gear_stick_shifts_and_brings_the_die()
    local S = redRacing()
    dropOn(S, S.find("Gear Stick"), "gear", 1)
    eq(state().cars.Red.gear, 1)
    local die = S.find("First Gear Dice")
    assert(die.pos.z > -30 and die.pos.z < 0, "die moved towards the table centre from the dashboard")
    roll(S, 1, 2)
    eq(state().cars.Red.lastRoll, 2)
    eq(state().round, 2)
end

function T.gear_stick_dropped_off_the_gate_goes_back()
    local S = redRacing()
    local stick = S.find("Gear Stick")
    local home = stick.pos
    stick.pos = S.vec(50, 1, 50)
    onObjectDrop("Red", stick)
    eq(state().cars.Red.gear, 0)
    eq(stick.pos.x, home.x)
    eq(stick.pos.z, home.z)
end

function T.dropping_the_wp_marker_sets_wear()
    local S = redRacing()
    dropOn(S, S.find("Wear Tracker"), "wp", 11)
    eq(state().cars.Red.wear.wp, 11)
    assert(S.logged("loses 7 WP"))
end

function T.dashboard_buttons_act_on_the_owner()
    local S = redRacing()
    S.beginner.click("fdDashBrake", "Blue")
    eq(state().cars.Red.wear.wp, 17)
    S.beginner.click("fdDashWear", "Red", true)
    eq(state().cars.Red.wear.wp, 18)
    S.beginner.click("fdDashWear", "Red")
    eq(state().cars.Red.wear.wp, 17)
    S.beginner.click("fdDashCollision", "Red")
    assert(S.beginner.buttons[1].label:find("BLACK DIE"))
end

function T.wear_moves_the_marker()
    local S = redRacing()
    local marker = S.find("Wear Tracker")
    local before = marker.pos.z
    for _ = 1, 3 do
        S.beginner.click("fdDashBrake", "Red")
    end
    eq(state().cars.Red.wear.wp, 15)
    assert(marker.pos.z ~= before, "marker moved down a row")
end

function T.leaving_clears_markers_and_frees_the_dashboard()
    local S = redRacing()
    S.beginner.click("fdDashLeave", "Red")
    eq(state().cars.Red, nil)
    eq(S.count("Gear Stick"), 0)
    eq(S.count("Wear Tracker"), 0)
    eq(S.beginner.buttons[1].click_function, "fdDashJoin")
end

function T.flipping_a_dashboard_redraws_its_buttons()
    local S = redRacing()
    S.beginner.up = S.vec(0, 1, 0)
    onObjectRotate(S.beginner, 0, 0, "Red", 0, 180)
    eq(S.beginner.buttons[1].position[2], 0.7)
end

function T.the_screen_copy_follows_the_car()
    local S = redRacing()
    eq(S.assets[1].name, "fdDashboard", "dashboard texture registered once")
    assert(S.assets[1].url:find("akamaihd"), "a URL that still serves the image")
    eq(S.ui.fdm_Red.active, "true")
    eq(S.ui.fdm_Blue.active, "false", "only shown to players in the race")
    assert(S.ui["fdm_Red_label"].value:find("18 WP"))

    local gearAt = {}
    for g = 1, 6 do
        S.ui["fdm_Red_gearMark"] = nil
        fdUiShift({ color = "Red" }, tostring(g))
        gearAt[g] = S.ui["fdm_Red_gearMark"].offsetXY
    end
    assert(gearAt[1] ~= gearAt[2], "the gear stick moves down the gate")
    eq(state().cars.Red.gear, 6)

    local before = S.ui["fdm_Red_wpMark"].offsetXY
    fdUiWear({ color = "Red" }, "wp:11")
    eq(state().cars.Red.wear.wp, 11)
    assert(S.ui["fdm_Red_wpMark"].offsetXY ~= before, "the wear marker moves")
end

function T.screen_and_dashboard_stay_in_step()
    local S = redRacing()
    -- Setting wear on screen moves the marker on the table, and vice versa.
    fdUiWear({ color = "Red" }, "wp:9")
    local marker = S.find("Wear Tracker")
    local Dashboard = require("fd.tts.dashboard")
    local slot = Dashboard.worldSlot(S.beginner, "wp", 9)
    eq(marker.pos.x, slot.x)
    eq(marker.pos.z, slot.z)
    dropOn(S, marker, "wp", 4)
    eq(state().cars.Red.wear.wp, 4)
    assert(S.ui["fdm_Red_label"].value:find("4 WP"))
end

function T.screen_buttons_act_on_the_clickers_car()
    local S = redRacing()
    fdUiBrake({ color = "Red" })
    eq(state().cars.Red.wear.wp, 17)
    fdUiBrake({ color = "Blue" }) -- not racing: nothing happens
    eq(state().cars.Red.wear.wp, 17)
    fdUiLeave({ color = "Red" })
    eq(state().cars.Red, nil)
    eq(S.ui.fdm_Red.active, "false")
end

function T.claiming_takes_the_nearest_free_car()
    local S = redRacing()
    local far = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 30) })
    local near = S.object("Formula 1 Solid", { pos = S.vec(2, 1, -34) })
    S.beginner.click("fdDashCar", "Red")
    eq(state().cars.Red.tts.car, near.guid)
    eq(near.tint.name, "Red", "tinted to the player")
    eq(near.name, "RedPlayer (Red)", "labelled with its driver")
    eq(far.tint, nil)
    eq(far.name, "Formula 1 Solid", "an unclaimed car keeps its own name")

    -- Leaving the race hands the car back as it was found.
    S.beginner.click("fdDashLeave", "Red")
    eq(near.name, "Formula 1 Solid")
    eq(near.tint[1], 1)
end

function T.claiming_takes_a_car_from_the_bag_when_none_is_near()
    local S = redRacing()
    local distant = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 60) })
    S.beginner.click("fdDashCar", "Red")
    local mine = getObjectFromGUID(state().cars.Red.tts.car)
    assert(mine ~= distant, "a distant car is not taken")
    assert(mine.pos.z < -20, "the spawned one arrives by the player's seat")
end

function T.a_car_claimed_by_someone_else_is_left_alone()
    local S = redRacing()
    local blues = S.object("Formula 1 Solid", { pos = S.vec(1, 1, 34) })
    S.advanced.click("fdDashJoin", "Blue")
    S.advanced.click("fdDashCar", "Blue")
    eq(state().cars.Blue.tts.car, blues.guid)
    -- Even parked right next to Red, a claimed car is not up for grabs.
    blues.pos = S.vec(1, 1, -33)
    S.beginner.click("fdDashCar", "Red")
    assert(state().cars.Red.tts.car ~= blues.guid, "Red gets their own car")
end

function T.dropping_a_car_on_a_dashboard_claims_it()
    local S = redRacing()
    local car = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    car.pos = S.vec(S.beginner.pos.x + 1, 1, S.beginner.pos.z + 1)
    onObjectDrop("Red", car)
    eq(state().cars.Red.tts.car, car.guid)
    assert(S.logged("dropped on their dashboard"))
end

function T.the_status_line_asks_for_a_car()
    local S = redRacing()
    assert(S.beginner.buttons[1].label:find("no car"))
    S.beginner.click("fdDashCar", "Red")
    assert(not S.beginner.buttons[1].label:find("no car"))
end

function T.undo_restores_the_previous_state()
    local S = redRacing()
    S.beginner.click("fdDashBrake", "Red")
    eq(state().cars.Red.wear.wp, 17)
    fdUndo({ steam_name = "host", color = "Red" })
    eq(state().cars.Red.wear.wp, 18)
end

function T.strain_roll_queues_black_die_checks()
    local S = redRacing()
    local stick = S.find("Gear Stick")
    local values = { 2, 4, 8, 12, 20 }
    for g = 1, 5 do
        dropOn(S, stick, "gear", g)
        roll(S, g, values[g])
    end
    eq(state().cars.Red.wear.wp, 18, "shifting up one at a time is free")
    assert(S.logged("Engine strain"))
    assert(S.ui.fdr_checks.value:find("engine"), "race panel lists the check")
end

function T.spectator_roll_goes_to_the_car_in_that_gear()
    local S = redRacing()
    dropOn(S, S.find("Gear Stick"), "gear", 1)
    roll(S, 1, 1, "Grey")
    eq(state().cars.Red.lastRoll, 1)
end

return T
