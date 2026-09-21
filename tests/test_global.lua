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
    -- The board tile, showing Monaco at 44 units across.
    local Maps = require("fd.data.maps")
    S.board = S.object("Game Board Tile", {
        guid = "ebde54", pos = S.vec(0, 1, 0), size = S.vec(44, 1, 44), scale = S.vec(44, 1, 44),
        custom = { image = Maps.byId.FDMonaco.url },
    })
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

function T.track_overlay_maps_pixels_onto_the_board()
    local S = world()
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- The middle of the image sits at the middle of the tile, and the edges
    -- at its edges, in the tile's own local space.
    local mid = Track.localOf(S.board, FDMonaco, FDMonaco.image.width / 2, FDMonaco.image.height / 2)
    eq(mid.x, 0)
    eq(mid.z, 0)
    -- The tile shows its image turned half a turn from its local axes.
    local topleft = Track.localOf(S.board, FDMonaco, 0, 0)
    eq(topleft.x, 0.5)
    eq(topleft.z, -0.5)

    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    local lines = S.board.getVectorLines()
    local inCorners = 0
    for _, s in ipairs(FDMonaco.spaces) do
        if s.corner then inCorners = inCorners + 1 end
    end
    assert(inCorners > 0, "Monaco has corners")
    eq(#lines, #FDMonaco.outer + #FDMonaco.spaces + inCorners,
        "a line per piece of edge, one per space, and a second on each space inside a corner")
    assert(lines[1].thickness < 0.01, "thickness is in the tile's local space")
    assert(S.logged(FDMonaco.name))

    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    eq(#S.board.getVectorLines(), 0, "toggles back off")
end

-- Cars on the track ---------------------------------------------------------------

--- Where `space` is on the board, and whether `car` sits on it facing its way.
local function onSpace(S, car, space)
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local at = Track.worldOf(S.board, FDMonaco, space.pos[1], space.pos[2])
    if math.abs(car.pos.x - at.x) > 1e-6 or math.abs(car.pos.z - at.z) > 1e-6 then
        return false
    end
    local facing = Track.angleOf(S.board, FDMonaco, car.pos, car.rot.y)
    return math.abs(((facing - space.rot) + 180) % 360 - 180) < 1e-6
end

--- Put `car` down a few pixels off `space`.
local function putNear(S, car, space, dx, dy, color)
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    car.pos = Track.worldOf(S.board, FDMonaco, space.pos[1] + (dx or 4), space.pos[2] + (dy or -3))
    car.rot = S.vec(4, 123, -3)
    onObjectDrop(color or "Red", car)
end

function T.a_car_put_down_on_the_track_settles_onto_the_space()
    local S = world()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local car = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    for _, i in ipairs({ 1, 100, 252, 400 }) do
        local space = FDMonaco.spaces[i]
        putNear(S, car, space)
        assert(onSpace(S, car, space), "car on space " .. space.id .. ", facing " .. space.rot)
        eq(car.rot.x, 0, "set down level")
        eq(car.rot.z, 0)
    end
end

function T.a_claimed_car_snaps_and_is_not_parked_on()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    S.beginner.click("fdDashCar", "Red")
    local mine = getObjectFromGUID(state().cars.Red.tts.car)
    assert(mine and mine.name:find("Red"), "Red has a named car")
    local space = FDMonaco.spaces[100]
    putNear(S, mine, space)
    assert(onSpace(S, mine, space), "a renamed car still snaps")

    -- A second car put down on the same space goes beside it instead.
    local other = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    putNear(S, other, space, 1, 1)
    assert(not onSpace(S, other, space), "not stacked on Red")
    local moved = false
    for _, sp in ipairs(FDMonaco.spaces) do
        if sp.id ~= space.id and onSpace(S, other, sp) then moved = true end
    end
    assert(moved, "settled on a neighbouring space")
end

function T.a_car_put_down_off_the_track_stays_put()
    local S = world()
    local car = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    car.pos = S.vec(60, 1, 0)
    car.rot = S.vec(0, 17, 0)
    onObjectDrop("Red", car)
    eq(car.pos.x, 60)
    eq(car.rot.y, 17)
end

function T.no_snapping_on_a_map_without_track_data()
    local S = world()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local car = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    S.board.custom = { image = "http://example.invalid/other-map.png" }
    local space = FDMonaco.spaces[100]
    putNear(S, car, space)
    assert(not onSpace(S, car, space))
end

-- Track editor ------------------------------------------------------------------

local function editor(S)
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    return require("fd.tts.track_editor"), require("fd.tts.track"), require("fd.data.tracks.FDMonaco")
end

local function markersOut(S)
    local n = 0
    for _, o in ipairs(S.objects) do
        if o.name:find("^Space %d+") then n = n + 1 end
    end
    return n
end

function T.converting_to_the_board_and_back_is_exact()
    local S = world()
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local w = Track.worldOf(S.board, FDMonaco, 700, 300)
    local x, y = Track.pixelOf(S.board, FDMonaco, w)
    assert(math.abs(x - 700) < 1e-6 and math.abs(y - 300) < 1e-6, x .. "," .. y)
    for _, rot in ipairs({ 0, 35, 90, 200, 300 }) do
        local yaw = Track.yawOf(S.board, FDMonaco, 700, 300, rot)
        local back = Track.angleOf(S.board, FDMonaco, w, yaw)
        local d = math.abs(((back - rot) + 180) % 360 - 180)
        assert(d < 1e-6, "facing " .. rot .. " came back as " .. back)
    end
end

function T.editor_keys_need_the_editor_open()
    local S = world()
    S.press("Track editor: pick up spaces here", "Red", nil, S.vec(0, 1, 0))
    assert(S.logged("Open the track editor first"))
    eq(markersOut(S), 0)
end

function T.picking_up_spaces_only_takes_those_near_the_pointer()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    local w = Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2])
    S.press("Track editor: pick up spaces here", "Red", nil, w)
    local n = markersOut(S)
    assert(n > 0 and n < #FDMonaco.spaces / 4, "picked up " .. n)
    assert(S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")"), "the space under the pointer")
end

function T.moving_a_marker_moves_its_space()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    local w = Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2])
    S.press("Track editor: pick up spaces here", "Red", nil, w)
    local m = S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")")
    local target = Track.worldOf(S.board, FDMonaco, sp.pos[1] + 5, sp.pos[2] - 3)
    m.pos = S.vec(target.x, m.pos.y, target.z)
    S.press("Track editor: apply", "Red")
    eq(markersOut(S), 0, "markers cleared")
    local edited = Editor.trackFor(FDMonaco)
    local moved
    for _, s in ipairs(edited.spaces) do
        if s.id == sp.id then moved = s end
    end
    assert(math.abs(moved.pos[1] - (sp.pos[1] + 5)) < 1e-6 and math.abs(moved.pos[2] - (sp.pos[2] - 3)) < 1e-6)
    eq(#edited.spaces, #FDMonaco.spaces)
    eq(sp.pos[1] ~= moved.pos[1], true, "the original track data is untouched")
end

function T.deleting_a_marker_deletes_its_space()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")").destruct()
    S.press("Track editor: apply", "Red")
    eq(#Editor.trackFor(FDMonaco).spaces, #FDMonaco.spaces - 1)
end

function T.adding_a_space_takes_the_nearest_lane()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    local w = Track.worldOf(S.board, FDMonaco, sp.pos[1] + 2, sp.pos[2] + 2)
    S.press("Track editor: add a space here", "Red", nil, w)
    assert(S.logged("in lane " .. sp.lane))
    S.press("Track editor: apply", "Red")
    eq(#Editor.trackFor(FDMonaco).spaces, #FDMonaco.spaces + 1)
end

function T.a_marker_can_change_lane()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    local m = S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")")
    local to = sp.lane == 3 and 1 or 3
    S.press("Track editor: move space to lane " .. to, "Red", m)
    S.press("Track editor: apply", "Red")
    for _, s in ipairs(Editor.trackFor(FDMonaco).spaces) do
        if s.id == sp.id then eq(s.lane, to) end
    end
end

function T.edits_are_saved_with_the_game_and_come_back()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")").destruct()
    -- Saved mid-edit, markers still out: the save sees the edit, the markers stay.
    local saved = onSave()
    assert(saved.json.edits.FDMonaco, "edits are in the save")
    eq(#saved.json.edits.FDMonaco.spaces, #FDMonaco.spaces - 1)
    assert(markersOut(S) > 0, "autosave leaves the markers alone")

    -- A fresh load from that save sees the edited track.
    local S2 = world()
    onLoad(saved)
    local Editor2 = require("fd.tts.track_editor")
    eq(#Editor2.trackFor(require("fd.data.tracks.FDMonaco")).spaces, #FDMonaco.spaces - 1)
end

function T.the_editor_works_from_right_click_menus()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    local w = Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2])
    S.board.rightClick("Pick up spaces here", "Red", w)
    local m = S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")")
    assert(m, "picked up from the board's menu")
    local to = sp.lane == 3 and 1 or 3
    m.rightClick("Lane " .. to, "Red")
    eq(m.name, "Space " .. sp.id .. " (lane " .. to .. ")")
    local other = nil
    for _, o in ipairs(S.objects) do
        if o ~= m and o.name:find("^Space %d+") then other = o break end
    end
    other.rightClick("Delete space", "Red")
    S.board.rightClick("Add a space here", "Red", w)
    S.board.rightClick("Apply track edits", "Red")
    eq(#Editor.trackFor(FDMonaco).spaces, #FDMonaco.spaces, "one deleted, one added")

    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(next(S.board.menu), nil, "the board menu goes when the editor closes")
end

function T.deleting_every_marker_before_apply_is_still_saved()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    local gone = 0
    for i = #S.objects, 1, -1 do
        local o = S.objects[i]
        if o.name:find("^Space %d+") then o.destruct() gone = gone + 1 end
    end
    assert(gone > 0)
    -- No markers left and no Apply: the deletions must still reach the save.
    local saved = onSave()
    assert(saved.json.edits.FDMonaco, "the edit is saved")
    eq(#saved.json.edits.FDMonaco.spaces, #FDMonaco.spaces - gone)
end

function T.markers_saved_on_the_table_are_cleared_on_load()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    local out = markersOut(S)
    assert(out > 0)
    local saved = onSave()
    eq(#saved.json.markers, out, "the save lists the markers still out")
    -- Loading that save: the blocks are still on the table, but nothing
    -- tracks them any more, so they go -- without taking their spaces along.
    onLoad(saved)
    eq(markersOut(S), 0)
    eq(#Editor.trackFor(FDMonaco).spaces, #FDMonaco.spaces)
end

function T.links_can_be_set_by_hand_and_handed_back()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local a, b = FDMonaco.spaces[100], FDMonaco.spaces[103]
    S.board.rightClick("Pick up spaces here", "Red", Track.worldOf(S.board, FDMonaco, a.pos[1], a.pos[2]))
    local ma = S.find("Space " .. a.id .. " (lane " .. a.lane .. ")")
    local mb = S.find("Space " .. b.id .. " (lane " .. b.lane .. ")")
    assert(ma and mb, "both picked up")

    ma.rightClick("Start a link here", "Red")
    mb.rightClick("Link to here", "Red")
    assert(S.logged("now leads to space " .. b.id))
    local function space(id)
        for _, s in ipairs(Editor.trackFor(FDMonaco).spaces) do
            if s.id == id then return s end
        end
    end
    local function leadsTo(s, id)
        for _, n in ipairs(s.next) do if n == id then return true end end
        return false
    end
    assert(leadsTo(space(a.id), b.id))
    eq(space(a.id).fixed, true)

    -- Apply relinks everything else, but a hand-made link stays put.
    S.board.rightClick("Apply track edits", "Red")
    assert(leadsTo(space(a.id), b.id), "kept through Apply")
    local saved = onSave().json.edits.FDMonaco.spaces
    local found = false
    for _, s in ipairs(saved) do
        if s.id == a.id then found = s.fixed end
    end
    eq(found, true, "the hand-made link is in the save, for the export")

    -- Clicking the same link again takes it away; Automatic links hands back.
    S.board.rightClick("Pick up spaces here", "Red", Track.worldOf(S.board, FDMonaco, a.pos[1], a.pos[2]))
    ma = S.find("Space " .. a.id .. " (lane " .. a.lane .. ")")
    mb = S.find("Space " .. b.id .. " (lane " .. b.lane .. ")")
    ma.rightClick("Start a link here", "Red")
    mb.rightClick("Link to here", "Red")
    assert(not leadsTo(space(a.id), b.id), "toggled off")
    ma.rightClick("Automatic links", "Red")
    eq(space(a.id).fixed, nil)
end

function T.problems_are_counted_on_the_panel()
    local S = world()
    editor(S)
    assert(S.ui.fdr_editor.value:find("problem"), S.ui.fdr_editor.value)
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(S.ui.fdr_editor.value, "", "status cleared when the editor closes")
end

function T.track_overlay_refuses_another_map()
    local S = world()
    S.board.custom = { image = "https://example.invalid/other-map/" }
    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    assert(S.logged("No track data for the map"))
end

function T.a_late_joiner_gets_the_panels_again()
    local S = redRacing()
    S.xml = {}
    S.ui = {}
    onPlayerConnect({ color = "Grey" })
    onPlayerChangeColor("Blue")
    local ids = {}
    for _, node in ipairs(S.xml) do
        ids[node.attributes.id or ""] = (ids[node.attributes.id or ""] or 0) + 1
    end
    eq(ids.fdr, 1, "race panel sent once")
    eq(ids.fdm_Red, 1, "screen dashboards sent once")
    eq(S.ui.fdm_Red.active, "true", "filled in again")
    assert(S.ui.fdr_title, "race panel refreshed")
end

function T.a_deleted_marker_comes_back_on_the_next_action()
    local S = redRacing()
    S.find("Wear Tracker").destruct()
    eq(S.count("Wear Tracker"), 0)
    -- Nothing about the car changed when the marker went, but it is replaced
    -- as soon as anything happens.
    S.beginner.click("fdDashBrake", "Red")
    eq(S.count("Wear Tracker"), 1)
end

function T.a_dashboard_taken_out_later_gets_its_buttons()
    local S = world()
    local late = S.object("Beginner Dashboard", { pos = S.vec(0, 1, -60), up = S.vec(0, -1, 0) })
    onObjectSpawn(late)
    eq(late.buttons[1] and late.buttons[1].click_function, "fdDashJoin")
    -- And into a bag: no longer drawn, and no error.
    late.destruct()
    S.beginner.click("fdDashJoin", "Red")
end

function T.unchanged_ui_is_not_sent_again()
    local S = redRacing()
    S.beginner.click("fdDashBrake", "Red")
    S.resetCounts()
    refresh()
    eq(S.counts.ui, 0, "a refresh with nothing new sends nothing")
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
