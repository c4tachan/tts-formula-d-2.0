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
    -- The script's black die (math.random(20)) rolls a 10 -- a normal start,
    -- no contact -- unless a test loads it otherwise.
    local random = S.realRandom or math.random
    S.realRandom = random
    math.random = function(m, n)
        if m == 20 and n == nil then return 10 end
        if n then return random(m, n) end
        return random(m)
    end
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
    assert(loadfile(ROOT .. "/src/entry/Global.-1.lua"))()
    onLoad("")
    -- Seated after the load, so nobody is dealt in: these tests join by hand.
    S.player("Red", S.vec(0, 1, -38), true) -- the host
    S.player("Blue", S.vec(0, 1, 38))
    return S
end

local function state()
    return onSave().json.race
end

--- How many lines paint Monaco's pit boxes in their seats' colours: they
-- are on the board whenever it shows a map with a pit lane.
local function pitLines(S)
    local Track = require("fd.tts.track")
    return #(Track.pits(S.board, require("fd.data.tracks.FDMonaco")) or {})
end

--- Red joins at the beginner dashboard and gets the race under way.
local function redRacing()
    local S = world()
    joinRace("Red", S.beginner)
    fdStart({ steam_name = "host", color = "Red" }) -- Red's start is rolled at once
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

--- The dice tray's walls, and the middle of them.
local function tray(S)
    local walls, x, z = {}, 0, 0
    for _, o in ipairs(S.objects) do
        if o.name == "Dice tray" then
            walls[#walls + 1] = o
            x, z = x + o.pos.x, z + o.pos.z
        end
    end
    return walls, { x = x / #walls, z = z / #walls }
end

--- Whether `die` lies inside the tray's walls.
local function inTray(S, die)
    local walls = tray(S)
    local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
    for _, w in ipairs(walls) do
        x0, x1 = math.min(x0, w.pos.x), math.max(x1, w.pos.x)
        z0, z1 = math.min(z0, w.pos.z), math.max(z1, w.pos.z)
    end
    return die.pos.x > x0 and die.pos.x < x1 and die.pos.z > z0 and die.pos.z < z1
end

--- Move `car` (of `color`) on the full roll it has open, to the first
-- space the roll reaches, and put it down there.
local function moveOn(S, car, color)
    local Moves = require("fd.core.moves")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local m = state().cars[color].move
    local to = nil
    for id, o in pairs(Moves.reach(FDMonaco, m.from, m.roll)) do
        if o.brake == 0 and (not to or id < to) then to = id end
    end
    local Track = require("fd.tts.track")
    local s = FDMonaco.byId[to]
    car.pos = Track.worldOf(S.board, FDMonaco, s.pos[1], s.pos[2])
    onObjectDrop(color, car)
end

local T = {}

function T.load_builds_the_panel_and_teaches_the_dice()
    local S = world()
    assert(S.ui.fdr_title, "race panel refreshed")
    eq(#S.find("Sixth Gear Dice").rotationValues, 30)
    eq(#S.find("First Gear Dice").rotationValues, 4)
end

--- Whether `obj` is hidden from everyone, players and spectators alike.
local function hidden(obj)
    local seen = {}
    for _, c in ipairs(obj.invisibleTo or {}) do seen[c] = true end
    return seen.Red and seen.Blue and seen.Grey and seen.Black and true or false
end

function T.the_setup_board_is_hidden_where_it_stands()
    local S = world()
    local carBag = getObjectFromGUID("1bb99e") -- the world's, the one cars come from
    local rulebook = S.object("Beginner Rulebook Bag", { guid = "98b2d2", pos = S.vec(72, 0, -26) })
    local die = S.find("First Gear Dice")
    S.object("Memory Bag - Setup Board", { guid = "0fde3b", tables = { memoryList = {
        [carBag.guid] = {}, [rulebook.guid] = {}, [die.guid] = {},
    } } })
    onLoad("")
    local at = rulebook.pos
    for _, obj in ipairs({ carBag, rulebook }) do
        eq(hidden(obj), true, obj.name .. " hidden")
        eq(obj.locked, true, obj.name .. " locked")
        eq(obj.interactable, false, obj.name .. " out of reach")
    end
    eq(rulebook.pos, at, "left where it stands")
    eq(hidden(die), false, "the dice stay in sight, by their tray")
    -- The hidden bags still deal: a driver gets a car from one.
    joinRace("Red", S.beginner)
    S.beginner.click("fdDashCar", "Red")
    assert(getObjectFromGUID(state().cars.Red.tts.car), "a car out of the hidden bag")
end

function T.the_source_bags_are_hidden_without_the_setup_board()
    local S = world()
    local carBag = getObjectFromGUID("1bb99e")
    onLoad("") -- no setup board's memory bag: deleted from the table
    eq(hidden(carBag), true, "the car bag hidden all the same")
    eq(carBag.locked, true)
end

function T.a_packed_setup_board_is_put_out_and_hidden()
    local S = world()
    local bag = S.object("Memory Bag - Setup Board", { guid = "0fde3b", tables = { memoryList = {} } })
    local saved = onSave()
    saved.json.sp = true -- packed away when saved
    onLoad(saved)
    eq(bag.calls[1], "buttonClick_place", "put out, so its bags can be reached")
end

function T.the_big_box_menu_stays_in_its_bag()
    local S = world()
    local menuBag = S.object("Memory Bag - Mod Menu", { guid = "a57988" })
    local saved = onSave()
    saved.json.mp = false -- left out when saved
    onLoad(saved)
    eq(menuBag.calls[1], "buttonClick_recall", "packed away")
    eq(S.ui.showModMenuButton, nil, "and no button to bring it out")
end

-- The script's die always comes up 10 unless a test loads it, so with two or
-- more drivers Start race deals them in but leaves the grid tied: the cars
-- stay where they were dealt.

function T.start_race_deals_you_in_at_the_dashboard_there()
    local S = world()
    onPlayerChangeColor("Red")
    eq(state().cars.Red, nil, "sitting down deals nobody in")
    fdSetupStart(Player.Red)
    local red = state().cars.Red
    assert(red, "Red is in the race")
    eq(red.tts.dash, S.beginner.guid, "at the free dashboard in front of the seat")
    local car = getObjectFromGUID(red.tts.car)
    assert(car, "with a car")
    assert(car.pos.y > 1, "on the table, not under it with the hand zone")
    assert(math.abs(car.pos.z - S.beginner.pos.z) < 1 and math.abs(car.pos.x - S.beginner.pos.x) > 5,
        "beside the dashboard")
    assert(S.logged("dealt in"))

    -- Pressing it again deals nobody twice.
    fdSetupStart(Player.Red)
    eq(state().cars.Red.tts.car, red.tts.car)
    eq(S.count("Formula 1 Solid") + S.count("RedPlayer (Red)"), 1)
end

function T.a_seat_with_no_dashboard_gets_one_from_the_bag()
    local S = world()
    S.object("Beginner Dashboard Bag", { guid = "edfadc", spawns = "Beginner Dashboard" })
    S.player("Green", S.vec(-24, 1, -38))
    onPlayerChangeColor("Green")
    fdSetupStart(Player.Red)
    local green = state().cars.Green
    assert(green, "Green is in the race")
    local dash = getObjectFromGUID(green.tts.dash)
    assert(dash ~= S.beginner and dash ~= S.advanced, "a fresh dashboard")
    eq(dash.up.y, -1, "beginner side up")
    eq(dash.rot.y, 0, "turned to face the seat")
    assert(dash.pos.z > -38 and dash.pos.z < -30, "in front of the seat")
    assert(dash.pos.y > 1, "on the table")
    eq(dash.buttons[1].click_function, "fdNoop", "its status label is drawn")
    assert(getObjectFromGUID(green.tts.car), "and a car")
    assert(getObjectFromGUID(green.tts.markers.gear), "with its gear stick")
end

function T.nobody_is_dealt_in_once_the_race_has_started()
    local S = redRacing()
    onPlayerChangeColor("Blue")
    eq(state().cars.Blue, nil, "mid-race, Blue joins by hand if they want to")
    onPlayerChangeColor("Grey")
    eq(state().cars.Grey, nil, "spectators never")
end

function T.players_seated_at_load_wait_for_start_race()
    local S = world()
    onLoad("")
    eq(state().cars.Red, nil, "nobody is dealt in at load")
    eq(S.ui.fds_drivers.value, "Drivers (2): BluePlayer, RedPlayer", "but the menu lists who is seated")
    fdSetupStart(Player.Red)
    eq(state().cars.Red.tts.dash, S.beginner.guid)
    eq(state().cars.Blue.tts.dash, S.advanced.guid)
    assert(getObjectFromGUID(state().cars.Red.tts.car), "with a car")
end

function T.a_newcomer_is_moved_to_the_spectators_to_pick_a_colour()
    local S = world()
    S.object("Beginner Dashboard Bag", { guid = "edfadc", spawns = "Beginner Dashboard" })
    local green = S.player("Green", S.vec(-24, 1, -38))
    onPlayerConnect(green)
    -- TTS's own seat for them, which it announces as a colour change.
    onPlayerChangeColor("Green")
    eq(green.color, "Grey", "benched")
    eq(state().cars.Green, nil, "and not dealt in")
    assert(S.logged("broadcast to Grey: Pick a colour"), "told what to do")

    green.changeColor("Green")
    eq(state().cars.Green, nil, "not until the race starts")
    fdSetupStart(Player.Red)
    assert(state().cars.Green, "then the seat they picked is dealt in")
    assert(getObjectFromGUID(state().cars.Green.tts.car), "with a car")
end

function T.a_newcomer_who_leaves_at_once_is_left_alone()
    local S = world()
    local green = S.player("Green", S.vec(-24, 1, -38))
    local moved = false
    green.changeColor = function() moved = true end
    local wait = Wait.time
    local later = nil
    Wait.time = function(fn) later = fn end
    onPlayerConnect(green)
    Wait.time = wait
    Player.Green = nil -- gone before the moment is up
    green.steam_id = nil -- and their old object knows nothing
    later()
    eq(moved, false, "not moved, and nothing thrown")
end

function T.a_driver_reconnecting_keeps_their_seat()
    local S = world()
    joinRace("Red", S.beginner)
    onPlayerConnect(Player.Red)
    eq(Player.Red.color, "Red")
    assert(state().cars.Red)
end

function T.newcomers_keep_their_seat_once_the_race_has_started()
    local S = redRacing()
    onPlayerConnect(Player.Blue)
    eq(Player.Blue.color, "Blue")
    eq(state().cars.Blue, nil, "mid-race, Blue joins by hand if they want to")
end

function T.deleting_a_dashboard_before_the_start_takes_its_driver_out()
    local S = world()
    joinRace("Red", S.beginner)
    S.beginner.destruct()
    eq(state().cars.Red, nil, "Red has left")
    eq(S.count("Gear Stick"), 0, "and their gear stick went with them")
end

function T.a_save_whose_dashboard_was_deleted_deals_the_seat_in_again()
    local S = world()
    S.object("Beginner Dashboard Bag", { guid = "edfadc", spawns = "Beginner Dashboard" })
    joinRace("Red", S.beginner)
    local saved = onSave()
    -- Deleted without the script hearing of it, as when cleaning up a save.
    local hook = onObjectDestroy
    onObjectDestroy = nil
    S.beginner.destruct()
    onObjectDestroy = hook

    onLoad(saved)
    eq(state().cars.Red, nil, "Red is out")
    fdSetupStart(Player.Red)
    local red = state().cars.Red
    assert(red, "Red is dealt in again")
    local dash = getObjectFromGUID(red.tts.dash)
    assert(dash and dash ~= S.beginner, "at a fresh dashboard")
end

--- Every one of the seven dice off the table, as packed away.
local function packDice(S)
    local gone = {}
    for _, n in ipairs({ "First", "Second", "Third", "Fourth", "Fifth", "Sixth" }) do
        gone[#gone + 1] = n .. " Gear Dice"
    end
    gone[#gone + 1] = "Damage Dice"
    for _, name in ipairs(gone) do S.find(name).destruct() end
    return gone
end

function T.the_setup_menu_chooses_the_map()
    local S = world()
    local Maps = require("fd.data.maps")
    -- The list: the maps with track data first, then the rest, marked.
    local list = nil
    for _, node in ipairs(S.xml) do
        if node.attributes.id == "fds" then
            local function find(n)
                if n.attributes.id == "fds_maps" then list = n end
                for _, c in ipairs(n.children or {}) do find(c) end
            end
            find(node)
        end
    end
    assert(list, "a map list on the setup menu")
    local at, marked = {}, false
    for i, o in ipairs(list.children) do
        at[o.value] = i
        if o.value:match("%(no track data%)$") then
            marked = true
        else
            assert(not marked, o.value .. " has track data, so comes before the maps without")
        end
    end
    assert(at["Formula D: Austin"] and at["Formula D: Monaco"], "the maps with track data, unmarked")
    eq(list.children[at["Formula D: Monaco"]].attributes.selected, "true", "showing the map on the board")
    assert(at["Formula De Circuit 27: Detroit  (no track data)"], "the rest, marked")
    eq(at["Formula D: Baltimore"] or at["Formula D: Baltimore  (no track data)"], nil, "no board of a circuit that is not F1")

    fdSetupMap(Player.Blue, "Formula D: Austin")
    eq(S.board.custom.image, Maps.byId.FDMonaco.url, "only the host chooses")
    fdSetupMap(Player.Red, "Formula D: Austin")
    eq(S.board.custom.image, Maps.byId.FDAustin.url, "the host's choice goes on the board")
    eq(S.board.reloads, 1, "reloaded to show it")
    assert(S.logged("puts Formula D: Austin on the board"))
    assert(S.ui.fds_map.value:find("Austin"), "and the menu says so")
end

function T.the_start_falls_back_on_the_spare_dice_set()
    local S = world()
    local names = packDice(S)
    local set = {}
    for i, name in ipairs(names) do set[i] = { name = name, guid = "d" .. i } end
    S.object("Dice Set Bag", { guid = "ac4939", spawns = "Dice Set", spawnContents = set })
    joinRace("Red", S.beginner)
    fdStart(Player.Red)
    for _, name in ipairs(names) do
        eq(S.count(name), 1, name)
    end
    eq(S.count("Dice Set"), 0, "the spare set's bag is put away")
    assert(S.logged("Put 7 dice out"))
    -- In the row in the middle of the board, and the ones the race uses.
    local die = S.find("First Gear Dice")
    eq(die.interactable, false, "out of reach")
    dropOn(S, S.find("Gear Stick"), "gear", 1)
    eq(die.highlight[1], "Red")
end

function T.no_dice_fetched_when_all_are_out()
    local S = world()
    joinRace("Red", S.beginner)
    fdStart(Player.Red)
    assert(not S.logged("dice out"))
end

function T.free_dashboards_have_no_buttons()
    local S = world()
    eq(#S.beginner.buttons, 0, "players are dealt in at Start race, not by joining")
    eq(#S.advanced.buttons, 0)
end

function T.joining_from_a_dashboard_claims_it_and_places_markers()
    local S = world()
    joinRace("Red", S.beginner)
    eq(state().cars.Red.tts.dash, S.beginner.guid)
    eq(S.count("Gear Stick"), 1)
    eq(S.count("Wear Tracker"), 1)
    eq(S.beginner.buttons[1].click_function, "fdNoop", "status label first")
    assert(S.beginner.buttons[1].label:find("18 WP"), S.beginner.buttons[1].label)
    eq(S.beginner.buttons[1].position[2], -0.55, "drawn on the face that is up")
end

function T.buttons_read_the_same_way_as_the_printed_art()
    local S = world()
    joinRace("Red", S.beginner)
    joinRace("Blue", S.advanced)
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
    joinRace("Red", S.beginner)
    joinRace("Blue", S.beginner)
    eq(state().cars.Blue, nil)
end

function T.spectators_cannot_join()
    local S = world()
    joinRace("Grey", S.beginner)
    eq(state().cars.Grey, nil)
end

function T.advanced_face_warns_instead_of_placing_wear()
    local S = world()
    joinRace("Blue", S.advanced)
    eq(S.count("Wear Tracker"), 0)
    assert(S.logged("beginner side"))
    eq(S.advanced.buttons[1].position[2], 0.7)
end

function T.dropping_the_gear_stick_shifts_and_lights_the_die()
    local S = redRacing()
    local die = S.find("First Gear Dice")
    dropOn(S, S.find("Gear Stick"), "gear", 1)
    eq(state().cars.Red.gear, 1)
    eq(die.highlight[1], "Red", "the die for the gear is lit")
    assert(inTray(S, die), "and in the tray")
    roll(S, 1, 2)
    eq(state().cars.Red.lastRoll, 2)
    eq(state().round, 2)
end

function T.a_gear_die_reads_the_number_on_its_face()
    local S = redRacing()
    roll(S, 1, 2)
    dropOn(S, S.find("Gear Stick"), "gear", 2)
    -- The 2nd gear die's faces are 3, 3, 4, 4, 4, 2: a 2 is its sixth face.
    roll(S, 2, 2)
    eq(state().cars.Red.lastRoll, 2)
    assert(not S.logged("check the die"))
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
    S.beginner.click("fdDashWear", "Blue")
    eq(state().cars.Red.wear.wp, 17)
    S.beginner.click("fdDashWear", "Red", true)
    eq(state().cars.Red.wear.wp, 18)
    S.beginner.click("fdDashWear", "Red")
    eq(state().cars.Red.wear.wp, 17)
    S.beginner.click("fdDashCollision", "Red")
    assert(S.logged("RedPlayer rolls 10 on the black die %(collision%)"), "rolled at once")
    eq(#state().checks, 0)
end

function T.wear_moves_the_marker()
    local S = redRacing()
    local marker = S.find("Wear Tracker")
    local before = marker.pos.z
    for _ = 1, 3 do
        S.beginner.click("fdDashWear", "Red")
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
    eq(#S.beginner.buttons, 0, "its buttons go with the car")
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

function T.chat_is_coloured_by_kind_of_event()
    local S = redRacing()
    local function said(pattern)
        for msg, rgb in pairs(S.said) do
            if msg:find(pattern) then return rgb end
        end
        error("nothing said like " .. pattern)
    end
    local order = said("^Order of play")
    local info = said("joins the race")
    assert(order[1] ~= info[1] or order[3] ~= info[3], "the order of play stands out from the rest")
    dropOn(S, S.find("Gear Stick"), "gear", 1)
    roll(S, 1, 2)
    eq(said("rolls 2 in 1st gear").name, "Red", "a roll in the roller's own colour")
end

function T.a_knocked_die_from_another_gear_changes_nothing()
    local S = redRacing()
    fdUiShift(Player.Red, "2")
    roll(S, 5, 14, "Red") -- the 5th gear die, knocked while reaching for the 2nd
    assert(S.logged("5th gear die shows 14, but RedPlayer is in 2nd gear %-%- not counted"))
    eq(state().cars.Red.gear, 2, "still in 2nd")
    eq(state().cars.Red.lastRoll, nil, "no roll counted")
    roll(S, 2, 3, "Red")
    eq(state().cars.Red.lastRoll, 3, "the right die still counts")
end

function T.the_roll_button_rolls_the_die_for_your_gear()
    local S = redRacing()
    fdUiRoll(Player.Red)
    assert(S.logged("Shift into a gear first"), "no gear, no roll")

    fdUiShift(Player.Red, "2")
    local die = S.find("Second Gear Dice")
    die.value = 4
    fdUiRoll(Player.Red)
    eq(die.rolls, 1, "thrown once")
    eq(state().cars.Red.lastRoll, 4, "and read once it settles")

    -- Someone else's button rolls nothing for Red.
    fdUiRoll(Player.Blue)
    eq(die.rolls, 1)
end

function T.the_tray_sits_on_the_map_name_panel_with_the_dice_parked_beside_it()
    local S = world()
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local spot = Track.worldOf(S.board, FDMonaco, FDMonaco.dice[1], FDMonaco.dice[2])
    local walls, middle = tray(S)
    eq(#walls, 4)
    assert(math.abs(middle.x - spot.x) < 1e-6 and math.abs(middle.z - spot.z) < 1e-6, "the tray on the panel")
    -- Before the race no die is in play: all parked, locked, in gear order,
    -- on the side of the tray towards the middle of the board.
    local last = nil
    for _, name in ipairs({ "First Gear Dice", "Second Gear Dice", "Sixth Gear Dice", "Damage Dice" }) do
        local die = S.find(name)
        eq(die.locked, true, name .. " parked")
        eq(die.interactable, false, name .. " cannot be picked up")
        assert(not inTray(S, die), name .. " outside the tray")
        assert(math.abs(die.pos.z) < math.abs(spot.z), name .. " towards the middle of the board")
        if last then
            eq(die.pos.z, last.pos.z, "in one row")
            assert(die.pos.x > last.pos.x, "in gear order")
        end
        last = die
    end
end

function T.only_the_die_in_play_is_in_the_tray()
    local S = redRacing()
    local first, second = S.find("First Gear Dice"), S.find("Second Gear Dice")
    assert(not inTray(S, first), "Red has no gear yet: the tray is empty")
    fdUiShift(Player.Red, "1")
    assert(inTray(S, first), "the 1st gear die comes in")
    eq(first.locked, false, "loose, to roll")
    eq(first.interactable, false, "but still out of reach")
    fdUiShift(Player.Red, "2")
    assert(not inTray(S, first), "out again on the shift")
    eq(first.locked, true, "parked and locked")
    assert(inTray(S, second), "and the 2nd gear die in")
    -- Laid out again (a new map, the start): the tray moves, the die in play
    -- goes back in.
    fdMapChanged()
    eq(#tray(S), 4, "still four walls")
    assert(inTray(S, second))
end

function T.the_dice_keep_their_spot_on_a_track_with_edits()
    local S = world()
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- Opening the editor makes an edited copy of the track, as a save with
    -- hand edits has.
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    fdMapChanged()
    local spot = Track.worldOf(S.board, FDMonaco, FDMonaco.dice[1], FDMonaco.dice[2])
    local _, middle = tray(S)
    assert(math.abs(middle.x - spot.x) < 1e-6 and math.abs(middle.z - spot.z) < 1e-6, "still on the name panel")
end

function T.the_tray_sits_in_the_middle_of_a_board_without_a_spot()
    local S = world()
    S.board.custom = { image = "http://example.invalid/other-map.png" }
    fdMapChanged()
    local _, middle = tray(S)
    assert(math.abs(middle.x) < 1e-6 and math.abs(middle.z) < 1e-6, "in the middle of the board")
end

function T.the_black_die_shows_the_scripts_roll()
    local S = redRacing()
    eq(S.find("Damage Dice").value, 10, "Red's start, rolled by the script")
end

function T.screen_buttons_act_on_the_clickers_car()
    local S = redRacing()
    fdUiWear({ color = "Red" }, "wp:17")
    eq(state().cars.Red.wear.wp, 17)
    fdUiWear({ color = "Blue" }, "wp:12") -- not racing: nothing happens
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
    joinRace("Blue", S.advanced)
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

function T.pit_boxes_are_painted_in_their_seats_colours()
    local S = world()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local seats = {}
    for _, b in ipairs(FDMonaco.pit.boxes) do seats[b.player] = (seats[b.player] or 0) + 1 end
    for _, c in ipairs({ "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink" }) do
        eq(seats[c], 1, c .. " has one pit box")
    end
    local painted = {}
    for _, l in ipairs(S.board.getVectorLines()) do
        if l.color.name then painted[l.color.name] = true end
    end
    for c in pairs(seats) do assert(painted[c], c .. "'s garage is painted on load") end
    assert(pitLines(S) > 0)
    eq(#S.board.getVectorLines(), pitLines(S), "and nothing else is drawn")
    -- They stay under the overlay, and when it goes.
    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    eq(#S.board.getVectorLines(), pitLines(S))
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
    local byId, onDown = {}, 0
    for _, s in ipairs(FDMonaco.spaces) do byId[s.id] = s end
    for _, s in ipairs(FDMonaco.spaces) do
        for _, n in ipairs(s.next) do
            if byId[n] and byId[n].lane == s.lane then onDown = onDown + 1 break end
        end
    end
    eq(#lines, pitLines(S) + #FDMonaco.outer + onDown,
        "the pit boxes, a line per piece of edge and an arrow on down each lane")
    assert(lines[1].thickness < 0.01, "thickness is in the tile's local space")
    eq(S.count("Space " .. FDMonaco.spaces[1].id .. " (lane " .. FDMonaco.spaces[1].lane .. ")"), 1,
        "a ghost car on the space")
    local ghosts = 0
    for _, o in ipairs(S.objects) do
        if o.name:find("^Space [iompb]%.") then ghosts = ghosts + 1 end
    end
    eq(ghosts, #FDMonaco.spaces, "one on every space")
    local g = S.find("Space " .. FDMonaco.spaces[1].id .. " (lane " .. FDMonaco.spaces[1].lane .. ")")
    eq(g.collider.enabled, false, "no collision: a car put down goes through to the board")
    assert(S.logged(FDMonaco.name))

    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    eq(#S.board.getVectorLines(), pitLines(S), "toggles back off, to the pit boxes")
    eq(S.count("Space " .. FDMonaco.spaces[1].id .. " (lane " .. FDMonaco.spaces[1].lane .. ")"), 0,
        "and the ghosts go with it")
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

function T.the_race_knows_which_space_a_car_is_on()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    S.beginner.click("fdDashCar", "Red")
    local mine = getObjectFromGUID(state().cars.Red.tts.car)
    local space = FDMonaco.spaces[100]
    putNear(S, mine, space)
    eq(state().cars.Red.space, space.id)

    roll(S, 1, 2)
    eq(state().cars.Red.move.from, space.id, "the move starts where the car was")
    local nxt = FDMonaco.byId[space.next[1]]
    putNear(S, mine, nxt)
    eq(state().cars.Red.space, nxt.id)
    eq(state().cars.Red.move.from, space.id)

    mine.pos = S.vec(60, 1, 0)
    onObjectDrop("Red", mine)
    eq(state().cars.Red.space, nil, "off the track")

    -- Somebody else's car, or nobody's, does not move Red.
    putNear(S, mine, space)
    local other = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    putNear(S, other, FDMonaco.spaces[200])
    eq(state().cars.Red.space, space.id)
end

function T.a_car_claimed_on_the_track_is_on_its_space()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local space = FDMonaco.spaces[100]
    local car = S.object("Formula 1 Solid", { pos = S.vec(0, 1, 40) })
    putNear(S, car, space)
    -- Nobody's car snaps too; claiming it, where it stands, finds it there.
    -- Red sits by the track, so it is the nearest car.
    local hand = Player.Red.getHandTransform().position
    hand.x, hand.z = car.pos.x, car.pos.z - 3
    S.beginner.click("fdDashCar", "Red")
    eq(state().cars.Red.tts.car, car.guid)
    eq(state().cars.Red.space, space.id)
    S.beginner.click("fdDashLeave", "Red")
    eq(state().cars.Red, nil)
end

--- Red's car, claimed and put down on the Monaco space `id`.
local function redOn(S, id)
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    S.beginner.click("fdDashCar", "Red")
    local mine = getObjectFromGUID(state().cars.Red.tts.car)
    putNear(S, mine, FDMonaco.byId[id])
    eq(state().cars.Red.space, id)
    return mine
end

function T.a_car_put_down_in_its_pit_box_makes_its_pit_stop()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local box = nil
    for _, b in ipairs(FDMonaco.pit.boxes) do
        if b.player == "Red" then box = b end
    end
    local before = nil
    for i, id in ipairs(FDMonaco.pit.spaces) do
        if id == box.beside then before = FDMonaco.pit.spaces[i - 1] end
    end
    local mine = redOn(S, before)
    roll(S, 1, 2)
    putNear(S, mine, FDMonaco.byId[box.space])
    eq(state().cars.Red.space, box.space, "settled into the box")
    eq(state().cars.Red.maxGear, 4, "out in 4th at most")
    assert(S.logged("pits: wear restored"))
end

function T.a_car_put_down_after_its_roll_is_charged_for_the_move()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local mine = redOn(S, "m.s2.5")
    roll(S, 1, 2)
    putNear(S, mine, FDMonaco.byId["m.s2.6"])
    eq(state().cars.Red.wear.wp, 17)
    assert(S.logged("braked 1 short"))
    -- Put down again, it is judged again: the full roll costs nothing.
    putNear(S, mine, FDMonaco.byId["m.s2.7"])
    eq(state().cars.Red.wear.wp, 18)
    assert(S.logged("gets back 1 WP"))
    -- Too far is warned about, not charged or refused.
    putNear(S, mine, FDMonaco.byId["m.s2.10"])
    eq(state().cars.Red.wear.wp, 18)
    eq(state().cars.Red.space, "m.s2.10")
    assert(S.logged("not a legal 2"))
end

--- The icons on the board, counted by name: { clean = 3, brake = 3, ... }.
local function marksOn(S)
    local n = {}
    for _, d in ipairs(S.board.decals or {}) do n[d.name] = (n[d.name] or 0) + 1 end
    return n
end

--- The names of the icons on Monaco's space `id`, a badge included, sorted
-- and joined.
local function iconsAt(S, id)
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local f = Track.frame(S.board, FDMonaco)
    local s = FDMonaco.byId[id]
    local out = {}
    for _, d in ipairs(S.board.decals or {}) do
        local px, py = f.w / 2 - d.position.x / f.kx, f.h / 2 + d.position.z / f.kz
        if (px - s.pos[1]) ^ 2 + (py - s.pos[2]) ^ 2 < 20 * 20 then out[#out + 1] = d.name end
    end
    table.sort(out)
    return table.concat(out, ",")
end

function T.a_roll_marks_where_the_car_can_go()
    local S = redRacing()
    redOn(S, "m.s2.5")
    roll(S, 1, 2)
    local n = marksOn(S)
    eq(n.clean, 3, "a full roll ends one space on in each lane")
    eq(n.brake, 3, "and one short in each")
    eq(n["start-Red"], 1, "and where the move started is flagged")
    eq(#S.board.decals, 7, "nothing else")
    -- The next shift starts a turn: the marks go, the flag stays.
    dropOn(S, S.find("Gear Stick"), "gear", 2)
    eq(#S.board.decals, 1)
    eq(S.board.decals[1].name, "start-Red")
end

function T.an_icon_lies_face_up_on_its_space()
    local S = world()
    local Track = require("fd.tts.track")
    local Icons = require("fd.data.icons")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local id = FDMonaco.pit.spaces[3]
    local decals = Track.marks(S.board, FDMonaco, { { id = id, kind = "blocked" } })
    eq(#decals, 1)
    local d = decals[1]
    eq(d.url, Icons.url("blocked"))
    local s = FDMonaco.byId[id]
    local mid = Track.localOf(S.board, FDMonaco, s.pos[1], s.pos[2])
    assert(math.abs(d.position.x - mid.x) < 1e-9 and math.abs(d.position.z - mid.z) < 1e-9, "on the space")
    assert(d.position.y > mid.y, "over the lines")
    eq(d.rotation[1], 90, "face up")
    -- A badge rides ahead of the icon it is on.
    decals = Track.marks(S.board, FDMonaco, { { id = id, kind = "brake", badge = "collision" } })
    eq(#decals, 2)
    eq(decals[2].name, "collision")
    assert(decals[2].scale[1] < decals[1].scale[1], "smaller")
end

function T.every_icon_the_board_can_show_is_drawn()
    local Icons = require("fd.data.icons")
    local listed = {}
    for _, n in ipairs(Icons.names) do listed[n] = true end
    local wanted = { "clean", "brake", "overshoot", "collision", "out", "blocked" }
    for _, seat in ipairs({ "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink" }) do
        wanted[#wanted + 1] = "start-" .. seat
    end
    for _, n in ipairs(wanted) do
        assert(listed[n], n .. " is not in fd.data.icons: rerun tools/make_icons.py")
        local f = io.open(ROOT .. "/assets/icons/" .. n .. ".png", "rb")
        assert(f, n .. ".png is not in assets/icons")
        f:close()
    end
end

function T.a_move_that_would_put_the_car_out_is_marked()
    local S = redRacing()
    redOn(S, "m.s2.5")
    for _ = 1, 17 do S.beginner.click("fdDashWear", "Red") end
    eq(state().cars.Red.wear.wp, 1)
    roll(S, 1, 2)
    local n = marksOn(S)
    eq(n.clean, 3, "the full roll costs nothing")
    eq(n.out, 3, "braking 1 costs the last WP")
    eq(n.brake, nil)
end

function T.changing_the_distance_redraws_the_marks()
    local S = redRacing()
    redOn(S, "m.s2.5")
    roll(S, 1, 2)
    local before = S.board.decals
    assert(marksOn(S).clean)
    fdSetupLaps({ color = "Red", steam_name = "host" }, "2")
    assert(S.board.decals ~= before, "drawn again")
    eq(marksOn(S).clean, 3)
    -- With no marks out, nothing is drawn.
    dropOn(S, S.find("Gear Stick"), "gear", 2)
    eq(marksOn(S).clean, nil)
    fdSetupLaps({ color = "Red", steam_name = "host" }, "1")
    eq(marksOn(S).clean, nil)
end

function T.the_marks_leave_the_track_overlay_alone()
    local S = redRacing()
    redOn(S, "m.s2.5")
    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    local overlay = #S.board.lines
    roll(S, 1, 2)
    eq(#S.board.lines, overlay, "the marks are icons, not lines")
    eq(marksOn(S).clean, 3)
    fdTrack({ color = "Red", steam_name = "RedPlayer" })
    eq(#S.board.lines, pitLines(S), "the overlay goes")
    eq(marksOn(S).clean, 3, "the marks stay")
    fdUndo({ color = "Red", steam_name = "RedPlayer" })
    eq(marksOn(S).clean, nil, "undo clears them")
end

function T.undo_keeps_the_cars_where_they_are()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local mine = redOn(S, "m.s2.5")
    roll(S, 1, 2)
    putNear(S, mine, FDMonaco.byId["m.s2.6"])
    eq(state().cars.Red.wear.wp, 17)
    fdUndo({ color = "Red", steam_name = "RedPlayer" })
    eq(state().cars.Red.wear.wp, 18, "the charge is undone")
    eq(state().cars.Red.move.from, "m.s2.5", "the roll is not")
    eq(state().cars.Red.space, "m.s2.6", "and the car is still where it was put")
end

--- Grid roll, with the script's die loaded: `rolls` is color -> value, and
-- `more` the values it comes up with after those, for breaking ties.
local function gridRoll(S, rolls, more)
    local values = {}
    for _, color in ipairs(state().order) do
        values[#values + 1] = rolls[color]
    end
    for _, v in ipairs(more or {}) do
        values[#values + 1] = v
    end
    local random, i = math.random, 0
    math.random = function()
        i = i + 1
        return values[i]
    end
    local ok, err = pcall(fdGrid, { steam_name = "host", color = "Red" })
    math.random = random
    assert(ok, err)
end

--- Red and Blue in the race, each with a car parked off the board.
local function twoCars()
    local S = world()
    joinRace("Red", S.beginner)
    joinRace("Blue", S.advanced)
    S.beginner.click("fdDashCar", "Red")
    S.advanced.click("fdDashCar", "Blue")
    return S, getObjectFromGUID(state().cars.Red.tts.car), getObjectFromGUID(state().cars.Blue.tts.car)
end

function T.the_grid_roll_puts_the_cars_on_the_grid()
    local S, red, blue = twoCars()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    gridRoll(S, { Red = 4, Blue = 15 })
    local pole, second = FDMonaco.byId[FDMonaco.start[1]], FDMonaco.byId[FDMonaco.start[2]]
    assert(onSpace(S, blue, pole), "the higher roll takes pole, facing along the track")
    assert(onSpace(S, red, second), "and the other car lines up behind")
    eq(state().cars.Blue.space, pole.id)
    eq(state().cars.Red.space, second.id)
end

function T.the_screen_dashboard_shows_the_corner_ahead()
    local S = twoCars()
    eq(S.ui["fdm_Red_corner"].value, "", "nothing before the car is on the track")
    gridRoll(S, { Red = 4, Blue = 15 })
    eq(S.ui["fdm_Blue_here"].value, "", "in no corner on the grid")
    eq(S.ui["fdm_Blue_corner"].value, "Corner 1 (1 stop)  -  entry 6  -  exit 12")
    eq(S.ui["fdm_Red_corner"].value, "Corner 1 (1 stop)  -  entry 8  -  exit 14", "from the row behind")
end

function T.the_screen_dashboard_counts_stops_in_the_corner()
    local S = world()
    local Race, Rules = require("fd.core.race"), require("fd.rules.beginner")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local Mini = require("fd.tts.minidash")
    local r = Race.new(Rules)
    r:join("Red")
    r:startRace()
    r:blackDie(10, "Red")
    r:useTrack(FDMonaco)
    r:placed("Red", "i.s1.5")
    r:shift("Red", 1)
    r:rolled("Red", 1, 2)
    r:placed("Red", "i.c1.1", FDMonaco)
    r:putDown("Red")
    Mini.setReady(true)
    Mini.refresh(r)
    eq(S.ui["fdm_Red_here"].value, "In corner 1: 1 of 1 stop made")
    eq(S.ui["fdm_Red_corner"].value:match("^Corner 2 "), "Corner 2 ", "then the next corner")
end

function T.the_grid_roll_breaks_its_own_ties()
    local S = twoCars()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    gridRoll(S, { Red = 9, Blue = 9 }, { 12, 3 })
    assert(S.logged("Tie for the grid"))
    assert(not S.logged("roll the black die"), "nobody is asked to roll")
    eq(#state().checks, 0)
    local pole = state().cars[state().order[1]]
    eq(pole.gridRolls[2], 12, "the higher second roll takes pole")
    eq(pole.space, FDMonaco.start[1])
    eq(state().cars[state().order[2]].space, FDMonaco.start[2])
end

function T.a_driver_without_a_car_is_told_at_the_grid()
    local S = world()
    joinRace("Red", S.beginner)
    gridRoll(S, { Red = 7 })
    assert(S.logged("no car to put on the grid"))
    eq(state().cars.Red.space, nil)
end

function T.no_grid_placing_on_a_map_without_track_data()
    local S, red = twoCars()
    local at = red.pos
    S.board.custom = { image = "http://example.invalid/other-map.png" }
    gridRoll(S, { Red = 4, Blue = 15 })
    assert(S.logged("No starting grid known"))
    eq(red.pos, at)
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
        if o.name:find("^Space [iompb]%.") then n = n + 1 end
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

function T.opening_the_editor_puts_a_ghost_car_on_every_space()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    eq(markersOut(S), #FDMonaco.spaces)
    local sp = FDMonaco.spaces[100]
    local m = S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")")
    eq(m.data.Name, "Custom_Model")
    assert(m.data.CustomMesh.MeshURL:find("steamusercontent"), "the car's own model")
    eq(m.locked, true, "locked: no physics")
    eq(m.collider.enabled, true, "keeps its collision, so it can be picked up")
    assert(m.tint.a < 1, "see-through")
    -- Picking up is still there, and finds nothing left to put out.
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    eq(markersOut(S), #FDMonaco.spaces)
end

function T.a_marker_is_loose_only_under_a_pointer_or_in_a_hand()
    local S = world()
    local _, _, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    local m = S.find("Space " .. sp.id .. " (lane " .. sp.lane .. ")")
    onObjectHover("Red", m)
    eq(m.locked, false, "under the pointer: loose, so it can be picked up")
    m.held_by_color = "Red"
    onObjectHover("Red", nil)
    eq(m.locked, false, "not locked while in a hand")
    onObjectHover("Red", m)
    m.held_by_color = nil
    onObjectDrop("Red", m)
    eq(m.locked, false, "put down but still under the pointer: loose")
    onObjectHover("Red", nil)
    eq(m.locked, true, "pointer gone and at rest: locked again")
    -- Let go of while the pointer moves on: locked once it settles.
    onObjectHover("Red", m)
    m.held_by_color = "Red"
    onObjectHover("Red", nil)
    m.held_by_color = nil
    onObjectDrop("Red", m)
    eq(m.locked, true, "dropped and settled: locked again")
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
    eq(markersOut(S), #FDMonaco.spaces, "the ghosts stay out after apply")
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

local function nextOf(Editor, FDMonaco, id)
    for _, s in ipairs(Editor.trackFor(FDMonaco).spaces) do
        if s.id == id then return s.next, s.fixed end
    end
end

local function has(list, x)
    for _, v in ipairs(list) do
        if v == x then return true end
    end
    return false
end

function T.the_link_key_adds_then_removes_a_link()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local a, b = FDMonaco.spaces[100], FDMonaco.spaces[140]
    local at = function(sp) return Track.worldOf(S.board, FDMonaco, sp.pos[1] + 1, sp.pos[2] - 1) end
    local key = "Track editor: link or unlink two spaces"
    assert(not has(nextOf(Editor, FDMonaco, a.id), b.id), "not linked to start with")

    -- No markers out: the key goes by the space under the pointer.
    S.press(key, "Red", nil, at(a))
    assert(S.logged("Linking from space " .. a.id))
    S.press(key, "Red", nil, at(b))
    local nxt, fixed = nextOf(Editor, FDMonaco, a.id)
    assert(has(nxt, b.id), "linked")
    assert(fixed, "set by hand, so relinking keeps it")

    -- The same two presses take it away again.
    S.press(key, "Red", nil, at(a))
    S.press(key, "Red", nil, at(b))
    assert(not has(nextOf(Editor, FDMonaco, a.id), b.id), "unlinked")
end

function T.editing_draws_every_link_as_an_arrow()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local track = Editor.trackFor(FDMonaco)
    local nLinks = 0
    for _, s in ipairs(track.spaces) do
        nLinks = nLinks + #(s.next or {})
    end
    local lines = S.board.getVectorLines()
    -- The grid is drawn over the links while editing.
    local nGrid = #(Track.grid(S.board, track, track.start) or {})
    eq(#lines, pitLines(S) + #(FDMonaco.outer or {}) + nLinks + nGrid)
    -- A link's arrow is shaft plus head: five points, the tip twice.
    local last = lines[#lines - nGrid].points
    eq(#last, 5)
    eq(last[2].x, last[4].x)
    eq(last[2].z, last[4].z)
end

function T.the_link_key_is_called_off_on_the_same_space_or_off_the_track()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local a = FDMonaco.spaces[100]
    local key = "Track editor: link or unlink two spaces"
    local before = #nextOf(Editor, FDMonaco, a.id)
    S.press(key, "Red", nil, Track.worldOf(S.board, FDMonaco, a.pos[1], a.pos[2]))
    S.press(key, "Red", nil, Track.worldOf(S.board, FDMonaco, a.pos[1], a.pos[2]))
    assert(S.logged("Link called off"))
    eq(#nextOf(Editor, FDMonaco, a.id), before)
    S.press(key, "Red", nil, Track.worldOf(S.board, FDMonaco, 5, 5))
    assert(S.logged("Point at a space first"))
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

function T.the_grid_plays_in_order_after_the_editor_has_been_open()
    -- The edited copy of the track is what the race goes by: without its
    -- spaces' sectors, pole measured as last on the lap (#20).
    local S = twoCars()
    local Editor, _, FDMonaco = editor(S)
    for _, sp in ipairs(Editor.trackFor(FDMonaco).spaces) do
        assert(sp.sector, sp.id .. " keeps its sector")
    end
    gridRoll(S, { Red = 4, Blue = 15 })
    fdStart({ steam_name = "host", color = "Red" })
    eq(table.concat(state().order, " "), "Blue Red", "pole plays first")
end

function T.edits_saved_without_sectors_get_them_back()
    local S = world()
    local _, _, FDMonaco = editor(S)
    local saved = onSave()
    for _, sp in ipairs(saved.json.edits.FDMonaco.spaces) do sp.sector = nil end
    world()
    onLoad(saved)
    local Editor = require("fd.tts.track_editor")
    local want = {}
    for _, sp in ipairs(FDMonaco.spaces) do want[sp.id] = sp.sector end
    for _, sp in ipairs(Editor.trackFor(FDMonaco).spaces) do
        eq(sp.sector, want[sp.id], sp.id .. ": read back from its code")
    end
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
        if o ~= m and o.name:find("^Space [iompb]%.") then other = o break end
    end
    other.rightClick("Delete space", "Red")
    S.board.rightClick("Add a space here", "Red", w)
    S.board.rightClick("Apply track edits", "Red")
    eq(#Editor.trackFor(FDMonaco).spaces, #FDMonaco.spaces, "one deleted, one added")

    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(S.board.menu["Add a space here"], nil, "the editor's items go when it closes")
    assert(S.board.menu["Put the dice here"], "leaving the board layout's")
end

function T.deleting_every_marker_before_apply_is_still_saved()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local sp = FDMonaco.spaces[100]
    S.press("Track editor: pick up spaces here", "Red", nil, Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2]))
    local gone = 0
    for i = #S.objects, 1, -1 do
        local o = S.objects[i]
        if o.name:find("^Space [iompb]%.") then o.destruct() gone = gone + 1 end
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

function T.the_grid_key_marks_the_grid_in_order()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local key = "Track editor: mark grid space"
    -- From an empty grid, not the one Monaco's file has.
    S.board.rightClick("Clear the grid", "Red")
    local a, b, c = FDMonaco.spaces[100], FDMonaco.spaces[101], FDMonaco.spaces[102]
    local at = function(sp) return Track.worldOf(S.board, FDMonaco, sp.pos[1] + 1, sp.pos[2] - 1) end
    local before = #S.board.getVectorLines()

    S.press(key, "Red", nil, at(a))
    assert(S.logged("Space " .. a.id .. " is grid place 1 %(pole%)"))
    S.press(key, "Red", nil, at(b))
    S.press(key, "Red", nil, at(c))
    local start = Editor.trackFor(FDMonaco).start
    eq(#start, 3)
    eq(start[1], a.id)
    eq(start[3], c.id)
    -- Three rings, a second on pole, and the line through them.
    eq(#S.board.getVectorLines(), before + 5)
    assert(S.find("Space " .. b.id .. " (lane " .. b.lane .. ") - grid 2"), "its marker says its place")
    assert(S.ui.fds_editor.value:find("3 on the grid"), S.ui.fds_editor.value)

    -- Pressed again on one: it comes off, and those behind move up.
    S.press(key, "Red", nil, at(a))
    assert(S.logged("is off the grid"))
    start = Editor.trackFor(FDMonaco).start
    eq(#start, 2)
    eq(start[1], b.id)
    assert(S.find("Space " .. b.id .. " (lane " .. b.lane .. ") - grid 1"))
    assert(S.find("Space " .. a.id .. " (lane " .. a.lane .. ")"), "renamed back")

    -- Deleting a grid space's marker takes it off the grid too.
    S.find("Space " .. b.id .. " (lane " .. b.lane .. ") - grid 1").destruct()
    start = Editor.trackFor(FDMonaco).start
    eq(#start, 1)
    eq(start[1], c.id)

    S.press(key, "Red", nil, Track.worldOf(S.board, FDMonaco, 5, 5))
    assert(S.logged("Point at a space first"))
end

function T.the_grid_is_saved_and_can_be_cleared()
    local S = world()
    local Editor, Track, FDMonaco = editor(S)
    local key = "Track editor: mark grid space"
    -- From an empty grid, not the one Monaco's file has.
    S.board.rightClick("Clear the grid", "Red")
    local a, b = FDMonaco.spaces[100], FDMonaco.spaces[101]
    S.press(key, "Red", nil, Track.worldOf(S.board, FDMonaco, a.pos[1], a.pos[2]))
    S.press(key, "Red", nil, Track.worldOf(S.board, FDMonaco, b.pos[1], b.pos[2]))
    local saved = onSave()
    local start = saved.json.edits.FDMonaco.start
    eq(#start, 2)
    eq(start[1], a.id)

    local S2 = world()
    onLoad(saved)
    local Editor2 = require("fd.tts.track_editor")
    eq(Editor2.trackFor(require("fd.data.tracks.FDMonaco")).start[2], b.id)

    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    S2.board.rightClick("Clear the grid", "Red")
    assert(S2.logged("Grid cleared %(2"))
    eq(#Editor2.trackFor(require("fd.data.tracks.FDMonaco")).start, 0)
    assert(S2.find("Space " .. a.id .. " (lane " .. a.lane .. ")"), "markers lose their place")
end

function T.problems_are_counted_on_the_panel()
    local S = world()
    editor(S)
    assert(S.ui.fds_editor.value:find("problem"), S.ui.fds_editor.value)
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(S.ui.fds_editor.value, "", "status cleared when the editor closes")
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
    S.board.xml = {}
    S.ui = {}
    onPlayerConnect({ color = "Grey" })
    onPlayerChangeColor("Blue")
    local ids = {}
    for _, node in ipairs(S.xml) do
        ids[node.attributes.id or ""] = (ids[node.attributes.id or ""] or 0) + 1
    end
    for _, node in ipairs(S.board.xml) do
        ids[node.attributes.id or ""] = (ids[node.attributes.id or ""] or 0) + 1
    end
    eq(ids.fdr, 1, "race panel sent once")
    eq(ids.fds, 1, "setup menu sent once")
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
    S.beginner.click("fdDashWear", "Red")
    eq(S.count("Wear Tracker"), 1)
end

function T.a_dashboard_taken_out_later_gets_its_buttons()
    local S = world()
    local late = S.object("Beginner Dashboard", { pos = S.vec(0, 1, -60), up = S.vec(0, -1, 0) })
    onObjectSpawn(late)
    eq(#late.buttons, 0, "free, so no buttons")
    -- And into a bag: no longer drawn, and no error.
    late.destruct()
    joinRace("Red", S.beginner)
end

function T.unchanged_ui_is_not_sent_again()
    local S = redRacing()
    S.beginner.click("fdDashWear", "Red")
    S.resetCounts()
    refresh()
    eq(S.counts.ui, 0, "a refresh with nothing new sends nothing")
end

function T.undo_restores_the_previous_state()
    local S = redRacing()
    S.beginner.click("fdDashWear", "Red")
    eq(state().cars.Red.wear.wp, 17)
    fdUndo({ steam_name = "host", color = "Red" })
    eq(state().cars.Red.wear.wp, 18)
end

function T.strain_is_rolled_at_once()
    local S = redRacing()
    local stick = S.find("Gear Stick")
    local values = { 2, 4, 8, 12, 20 }
    for g = 1, 5 do
        dropOn(S, stick, "gear", g)
        roll(S, g, values[g])
    end
    eq(state().cars.Red.wear.wp, 18, "shifting up one at a time is free")
    assert(S.logged("Engine strain"))
    assert(S.logged("RedPlayer rolls 10 on the black die %(engine%): engine holds"))
    eq(#state().checks, 0, "nothing left to roll")
    eq(S.ui.fdr_checks.value, "")
end


function T.laps_button_sets_the_distance_and_undo_puts_it_back()
    local S = redRacing()
    fdSetupLaps({ steam_name = "host", color = "Red" }, "2")
    eq(state().laps, 2)
    assert(S.logged("The race is 2 laps"))
    fdUndo({ steam_name = "host", color = "Red" })
    eq(state().laps, 1)
end

function T.a_car_over_the_line_on_its_last_lap_wins()
    local S = redRacing()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local Moves = require("fd.core.moves")
    local mine = redOn(S, "o.s11.15")
    -- Round once already: saved and loaded that way, as the state is copied.
    local saved = onSave()
    saved.json.race.cars.Red.lap = 1
    onLoad(saved)
    roll(S, 1, 2)
    local over = nil
    for id, o in pairs(Moves.reach(FDMonaco, "o.s11.15", 2)) do
        if o.crossed then over = id end
    end
    assert(over, "two spaces on from pole is over the line")
    putNear(S, mine, FDMonaco.byId[over])
    eq(state().cars.Red.place, 1)
    eq(state().phase, "finished")
    assert(S.logged("broadcast: Red"), "announced to everyone")
    assert(S.logged("wins the race"))
    assert(S.ui.fdr_title.value:find("Finished"))
    eq(S.ui.fdr_r1_pos.value, "1")
    eq(S.ui.fdr_r1_status.value, "finished")
end
function T.the_standings_are_a_table()
    local S = world()
    eq(S.ui.fdr_empty.active, "true", "an empty race says how to join")
    eq(S.ui.fdr_r1.active, "false")
    joinRace("Red", S.beginner)
    joinRace("Blue", S.advanced)
    eq(S.ui.fdr_empty.active, "false")
    eq(S.ui.fdr_r1.active, "true")
    eq(S.ui.fdr_r2.active, "true")
    eq(S.ui.fdr_r3.active, "false", "a row per car")
    eq(S.ui.fdr_r1_driver.value, "RedPlayer")
    eq(S.ui.fdr_r1_driver.color, "#DA1918", "in the seat's colour")
    eq(S.ui.fdr_r1_w_wp.value, "18", "a number under the WP heading")
    eq(S.ui.fdr_r1_gear.value, "grid")

    fdStart(Player.Red)
    local black = S.find("Damage Dice")
    black.value = 10
    onObjectRandomize(black, "Red")
    onObjectRandomize(black, "Blue")
    local due = state().order[1]
    local row = S.ui.fdr_r1_driver.value == due .. "Player" and 1 or 2
    eq(S.ui["fdr_r" .. row .. "_status"].value, "TO PLAY")
    S.beginner.click("fdDashLeave", "Red")
    eq(S.ui.fdr_r2.active, "false", "rows go with their cars")
end

function T.each_first_turn_starts_with_the_start_roll()
    local S, red, blue = twoCars()
    gridRoll(S, { Red = 4, Blue = 15 }) -- Blue on pole
    fdStart(Player.Red)

    -- The leader's start is rolled at once; Red's waits for Red's turn.
    assert(S.logged("BluePlayer rolls 10 on the black die %(start%): normal start"))
    assert(not S.logged("RedPlayer rolls 10 on the black die %(start%)"))
    eq(Turns.turn_color, "Blue")
    assert(S.logged("Your turn, BluePlayer"))

    -- A normal start: still Blue's turn, to shift, roll and move.
    fdUiShift(Player.Blue, "1")
    roll(S, 1, 2, "Blue")
    eq(state().cars.Blue.lastRoll, 2)
    moveOn(S, blue, "Blue")

    -- Then Red's first turn, starting with Red's start.
    assert(S.logged("RedPlayer rolls 10 on the black die %(start%): normal start"))
    eq(Turns.turn_color, "Red")
    assert(S.logged("Your turn, RedPlayer"))
    eq(#state().checks, 0)
end

function T.a_stall_rolls_the_next_start_too()
    local S, red, blue = twoCars()
    gridRoll(S, { Red = 4, Blue = 15 })
    local random = math.random
    local rolls = { 1, 10 } -- Blue stalls; Red starts normally
    math.random = function(m, n)
        if m == 20 and n == nil then return table.remove(rolls, 1) or 10 end
        return random(m, n)
    end
    fdStart(Player.Red)
    math.random = random
    assert(S.logged("BluePlayer rolls 1 on the black die %(start%): stalled"))
    assert(S.logged("RedPlayer rolls 10 on the black die %(start%): normal start"))
    eq(Turns.turn_color, "Red", "Blue sits out the round")
end

function T.a_collision_is_rolled_at_once()
    local S, red, blue = twoCars()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local Moves = require("fd.core.moves")
    gridRoll(S, { Red = 4, Blue = 15 }) -- Blue on pole
    fdStart(Player.Red)
    -- Somewhere Blue can go in 2 with a space beside it that Red can reach
    -- in 2, picked in a fixed order.
    local function sorted(t)
        local ids = {}
        for id in pairs(t) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    local redCan = Moves.reach(FDMonaco, state().cars.Red.space, 2)
    local ahead, beside = nil, nil
    for _, id in ipairs(sorted(Moves.reach(FDMonaco, state().cars.Blue.space, 2))) do
        for _, n in ipairs(FDMonaco.near[id] or {}) do
            if not beside and redCan[n] and n ~= state().cars.Red.space then ahead, beside = id, n end
        end
    end
    assert(beside, "a space beside Blue's in Red's reach")
    fdUiShift(Player.Blue, "1")
    roll(S, 1, 2, "Blue")
    putNear(S, blue, FDMonaco.byId[ahead], 0, 0, "Blue")
    fdUiShift(Player.Red, "1")
    roll(S, 1, 2, "Red")
    -- Red ends its move beside Blue.
    S.log = {}
    putNear(S, red, FDMonaco.byId[beside], 0, 0, "Red")

    -- Red rolls against Blue, Blue back against Red, then Blue's turn.
    local function at(pattern)
        for i, l in ipairs(S.log) do if l:find(pattern) then return i end end
        error("nothing said like " .. pattern)
    end
    local redRoll = at("RedPlayer rolls 10 on the black die %(collision with BluePlayer%): no contact")
    local blueRoll = at("BluePlayer rolls 10 on the black die %(collision with RedPlayer%): no contact")
    assert(redRoll < blueRoll, "the contact spreads from the car that moved")
    assert(blueRoll < at("Your turn, BluePlayer"), "and is over before the next turn")
    assert(not S.logged("roll the black die"), "nobody is asked to roll")
    eq(#state().checks, 0)
end

function T.beside_another_car_a_mark_warns_of_a_collision()
    local S, red, blue = twoCars()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    local Moves = require("fd.core.moves")
    gridRoll(S, { Red = 4, Blue = 15 }) -- Blue on pole, to play first
    fdStart(Player.Red)
    -- Blue moves on to somewhere Red can end beside in 2.
    local redCan = Moves.reach(FDMonaco, state().cars.Red.space, 2)
    local ahead = nil
    for id in pairs(Moves.reach(FDMonaco, state().cars.Blue.space, 2)) do
        for _, n in ipairs(FDMonaco.near[id] or {}) do
            if redCan[n] and n ~= state().cars.Red.space and (not ahead or id < ahead) then ahead = id end
        end
    end
    fdUiShift(Player.Blue, "1")
    roll(S, 1, 2, "Blue")
    putNear(S, blue, FDMonaco.byId[ahead], 0, 0, "Blue")
    fdUiShift(Player.Red, "1")
    roll(S, 1, 2, "Red")
    local nearBlue = {}
    for _, id in ipairs(FDMonaco.near[ahead] or {}) do nearBlue[id] = true end
    local seen = { collision = 0, badge = 0, clean = 0 }
    for id, o in pairs(redCan) do
        local icons = iconsAt(S, id)
        if id == ahead then
            eq(icons, "", "nothing on Blue's own space")
        elseif nearBlue[id] and o.brake == 0 and o.overshoot == 0 then
            eq(icons, "collision", id .. ", a full roll beside Blue")
            seen.collision = seen.collision + 1
        elseif nearBlue[id] then
            assert(icons:find("collision"), id .. ", short of the roll beside Blue: " .. icons)
            seen.badge = seen.badge + 1
        elseif o.brake == 0 and o.overshoot == 0 then
            eq(icons, "clean", id)
            seen.clean = seen.clean + 1
        end
    end
    assert(seen.collision > 0 and seen.badge > 0, "a full roll and a short one beside Blue")
end

function T.the_car_to_play_is_lit_and_its_driver_told()
    local S, red, blue = twoCars()
    gridRoll(S, { Red = 4, Blue = 15 })
    red.highlight, blue.highlight = nil, nil -- the few seconds' glow from claiming them
    fdStart(Player.Red) -- the leader's start is rolled at once

    local first, second = state().order[1], state().order[2]
    local cars = { Red = red, Blue = blue }
    assert(S.logged("Your turn, " .. first .. "Player"))
    eq(Turns.enable, true)
    eq(Turns.turn_color, first)
    eq(table.concat(Turns.order, " "), first .. " " .. second, "TTS follows the race's order")
    eq(cars[first].highlight[1], first, "the car to play is lit")
    eq(cars[first].highlight[2], nil, "and stays lit")
    eq(cars[second].highlight, nil)

    -- A roll opens the move; the turn passes once the car is put down.
    roll(S, 1, 2, first)
    eq(Turns.turn_color, first, "still moving")
    eq(cars[first].highlight[1], first)
    assert(not S.logged("Your turn, " .. second .. "Player"))
    moveOn(S, cars[first], first)
    assert(S.logged("Your turn, " .. second .. "Player"))
    eq(Turns.turn_color, second)
    eq(cars[first].highlight, nil)
    eq(cars[second].highlight[1], second)

    -- Undoing back is not news; the marker and highlight follow it.
    local told = #S.log
    fdUndo(Player.Red)
    eq(Turns.turn_color, first)
    eq(cars[first].highlight[1], first)
    for i = told + 1, #S.log do
        assert(not S.log[i]:find("Your turn"), S.log[i])
    end
end

function T.the_turn_is_handed_to_tts_once_however_it_reads_back()
    local S = twoCars()
    gridRoll(S, { Red = 4, Blue = 15 })
    fdStart(Player.Red)
    local first = state().order[1]

    -- TTS reads back other than it was given (here: nothing), and announces
    -- every turn_color it is handed.
    local real, writes = Turns, {}
    Turns = setmetatable({}, {
        __index = function() return nil end,
        __newindex = function(_, k, v) writes[#writes + 1] = k .. "=" .. tostring(v) end,
    })
    for _ = 1, 5 do
        refresh()
        onPlayerConnect()
    end
    Turns = real
    eq(table.concat(writes, " "), "", "nothing is written again")
    eq(Turns.turn_color, first)
end

function T.turns_already_on_are_left_alone_before_the_start()
    local S = twoCars()
    local saved = onSave()
    -- On already, as hotseat has them: switching them off makes TTS hand the
    -- turn round every seat, announcing each.
    local real, writes = Turns, {}
    Turns = setmetatable({}, {
        __index = function(_, k) if k == "enable" then return true end end,
        __newindex = function(_, k, v) writes[#writes + 1] = k .. "=" .. tostring(v) end,
    })
    onLoad(saved)
    refresh()
    onPlayerChangeColor("Red")
    Turns = real
    eq(table.concat(writes, " "), "", "Turns untouched")
    assert(state().cars.Red and state().cars.Blue, "the drivers are still in")
end

function T.only_the_host_can_use_the_race_controls()
    local S = redRacing()
    -- Shown only to the host and promoted players.
    local rows = {}
    local function walk(node, panel)
        if node.attributes.visibility == "Host|Admin" then rows[panel] = (rows[panel] or 0) + 1 end
        for _, c in ipairs(node.children or {}) do walk(c, panel) end
    end
    for _, node in ipairs(S.xml) do walk(node, node.attributes.id) end
    for _, node in ipairs(S.board.xml) do walk(node, node.attributes.id) end
    eq(rows.fdr, 1, "Undo, on the race panel, is the host's")
    eq(rows.fds, 4, "as are the setup menu's choices, Start race, the track tools and the editor line")

    -- A click that gets through anyway does nothing.
    joinRace("Blue", S.advanced)
    local blue = Player.Blue
    fdReset(blue)
    eq(state().phase, "race", "not reset")
    assert(S.logged("Only the host"))
    fdSetupLaps(blue, "2")
    eq(state().laps, 1)
    fdEdit(blue)
    eq(require("fd.tts.track_editor").isOpen(), false)
    S.press("Track editor: apply", "Blue")
    -- The host can, promoted players too.
    blue.admin = true
    fdSetupLaps(blue, "2")
    eq(state().laps, 2)
end

function T.spectator_roll_goes_to_the_car_in_that_gear()
    local S = redRacing()
    dropOn(S, S.find("Gear Stick"), "gear", 1)
    roll(S, 1, 1, "Grey")
    eq(state().cars.Red.lastRoll, 1)
end

--- Call `fn` with the script's black die coming up `values` in turn.
local function withRolls(values, fn)
    local random, i = math.random, 0
    math.random = function(m, n)
        if m == 20 and n == nil then
            i = i + 1
            return values[i] or 10
        end
        return random(m, n)
    end
    local ok, err = pcall(fn)
    math.random = random
    assert(ok, err)
end

function T.the_setup_menu_shows_from_the_load()
    local S = world()
    eq(S.ui.fds.active, "true", "everyone sees it at load")
    eq(S.ui.fds_map.value, "Map: Formula D: Monaco")
    eq(S.ui.fds_rules.value, "Rules: Formula D basic rules, 1 lap")
    refresh() -- world() seats them without telling the script
    eq(S.ui.fds_drivers.value, "Drivers (2): BluePlayer, RedPlayer", "everyone seated")
    Player.Blue.changeColor("Grey")
    eq(S.ui.fds_drivers.value, "Drivers (1): RedPlayer", "spectators are not")
    Player.Red.changeColor("Grey")
    assert(S.ui.fds_drivers.value:find("none yet"), S.ui.fds_drivers.value)
end

function T.the_setup_menu_sets_the_distance()
    local S = world()
    fdSetupLaps(Player.Red, "2")
    eq(state().laps, 2)
    eq(S.ui.fds_rules.value, "Rules: Formula D basic rules, 2 laps")
    eq(S.ui.fds_laps.value, "2", "the field shows the distance")
    fdSetupLaps(Player.Red, "5")
    eq(state().laps, 5, "any number of laps")
    eq(S.ui.fds_rules.value, "Rules: Formula D basic rules, 5 laps")
    fdSetupLaps(Player.Red, "0")
    fdSetupLaps(Player.Red, "abc")
    fdSetupLaps(Player.Red, "2.5")
    eq(state().laps, 5, "not a distance")
    eq(S.ui.fds_laps.value, "5", "the field goes back to the distance")
    fdSetupLaps(Player.Blue, "1")
    eq(state().laps, 5, "only the host chooses")
end

function T.start_race_rolls_the_grid_and_starts()
    local S, red, blue = twoCars()
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- In join order: Red rolls 4, Blue 15; then the starts.
    withRolls({ 4, 15 }, function() fdSetupStart(Player.Red) end)
    eq(state().phase, "race")
    eq(state().round, 1)
    eq(state().cars.Blue.space, FDMonaco.start[1], "the higher roll takes pole")
    eq(state().cars.Red.space, FDMonaco.start[2])
    assert(onSpace(S, blue, FDMonaco.byId[FDMonaco.start[1]]))
    eq(S.ui.fds.active, "false", "the menu goes once the race starts")
    -- Reset brings it back for the next race.
    fdReset(Player.Red)
    eq(S.ui.fds.active, "true")
end

function T.start_race_waits_on_an_unsettled_grid()
    local S = twoCars()
    -- The script's die always comes up 10: a tie it cannot break.
    fdSetupStart(Player.Red)
    eq(state().phase, "grid")
    assert(S.logged("press Start race to roll it again"))
    eq(S.ui.fds.active, "true")
end

function T.start_race_needs_drivers_and_the_host()
    local S = world()
    fdSetupStart(Player.Blue)
    eq(state().phase, "setup", "a player who is not the host cannot start")
    eq(state().cars.Red, nil, "nor deal anyone in")
    assert(S.logged("Only the host"))
    local host = Player.Red
    Player.Blue.changeColor("Grey")
    host.changeColor("Grey")
    fdSetupStart(host)
    eq(state().phase, "setup")
    assert(S.logged("Nobody is seated yet"))
end

function T.the_race_panel_lies_on_the_board_where_the_track_says()
    local S = world()
    local panel = S.board.xml[1].attributes
    eq(panel.id, "fdr", "drawn on the board tile")
    for _, node in ipairs(S.xml) do
        assert(node.attributes.id ~= "fdr", "not on the screen")
    end
    -- Monaco's spot, on the Formula D logo: centred on (2172, 1410) of the
    -- 2474 x 1616 image, which is local (-935 / 2474, 602 / 1616) on a
    -- 1-unit tile; 400 pixels wide.
    local x, y = panel.position:match("^(%S+) (%S+)")
    eq(x, "-37.8")
    eq(y, "37.3")
    eq(panel.scale, "0.0425 0.0425 1", "380 UI units across 400 pixels")
    eq(panel.rotation, "0 0 180", "the same way up as the picture")
    -- A new map reloads the tile, which loses its UI: it is drawn again.
    S.board.xml = {}
    fdMapChanged()
    eq(S.board.xml[1].attributes.id, "fdr")
end

function T.the_dice_tray_moves_where_the_board_menu_says_and_is_saved()
    local S = world()
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- On the board's menu with the editor closed, for the host only.
    local spot = Track.worldOf(S.board, FDMonaco, 600, 900)
    S.board.rightClick("Put the dice here", "Blue", spot)
    local _, middle = tray(S)
    assert(math.abs(middle.x - spot.x) > 1e-3, "not for a player who is not the host")
    S.board.rightClick("Put the dice here", "Red", spot)
    _, middle = tray(S)
    assert(math.abs(middle.x - spot.x) < 1e-6 and math.abs(middle.z - spot.z) < 1e-6, "moved to the spot")
    local saved = onSave().json.edits.FDMonaco
    eq(saved.dice[1], 600)
    eq(saved.dice[2], 900)
    -- And kept through a load, and a new map.
    onLoad(onSave())
    fdMapChanged()
    _, middle = tray(S)
    assert(math.abs(middle.x - spot.x) < 1e-6 and math.abs(middle.z - spot.z) < 1e-6, "still there")
end

function T.the_board_takes_a_right_click_only_while_the_layout_or_editor_is_open()
    local S = world()
    local host = { color = "Red", steam_name = "RedPlayer" }
    eq(S.board.interactable, false, "out of reach in a race")
    fdLayout(host)
    eq(S.board.interactable, true, "open to the layout menu")
    eq(S.board.locked, true, "but locked, so it cannot be moved")
    fdMapChanged()
    eq(S.board.interactable, true, "and still, on a new map")
    fdLayout(host)
    eq(S.board.interactable, false, "out of reach again")
    fdEdit(host)
    eq(S.board.interactable, true, "open to the editor's menu")
    fdEdit(host)
    eq(S.board.interactable, false)
    fdLayout({ color = "Blue", steam_name = "BluePlayer" })
    eq(S.board.interactable, false, "not for a player who is not the host")
end

function T.turning_the_dice_moves_their_row_a_quarter_round_the_tray()
    local S = world()
    -- Where the parked dice lie from the tray's middle, on average.
    local function row()
        local _, c = tray(S)
        local x, z, n = 0, 0, 0
        -- The six gear dice and the black one, the row's middle die the fourth.
        for _, name in ipairs({ "First Gear Dice", "Second Gear Dice", "Third Gear Dice", "Fourth Gear Dice",
                                "Fifth Gear Dice", "Sixth Gear Dice", "Damage Dice" }) do
            local d = S.find(name)
            x, z, n = x + d.pos.x - c.x, z + d.pos.z - c.z, n + 1
        end
        return x / n, z / n
    end
    local x0, z0 = row()
    local sides = {}
    for i = 1, 4 do
        S.board.menu["Turn the dice"]("Red")
        sides[i] = onSave().json.edits.FDMonaco.dice_side
        local x, z = row()
        -- A quarter turn: the row's offset is square to where it was.
        assert(math.abs(x * x0 + z * z0) < 1e-6 * (x0 * x0 + z0 * z0) + 1e-6, "square to the last, turn " .. i)
        x0, z0 = x, z
    end
    -- Monaco's dice sit low on the board, so face up it to start with.
    eq(table.concat(sides, " "), "right down left up")
end

function T.the_race_panel_moves_and_resizes_from_the_board_menu()
    local S = world()
    local Track = require("fd.tts.track")
    local FDMonaco = require("fd.data.tracks.FDMonaco")
    -- Monaco's own spot is 2474 / 2 - 935 = 302 pixels from its middle's x.
    S.board.rightClick("Put the race panel here", "Red", Track.worldOf(S.board, FDMonaco, 1237, 808))
    local panel = S.board.xml[1].attributes
    local x, y = panel.position:match("^(%S+) (%S+)")
    assert(math.abs(tonumber(x)) < 0.05 and math.abs(tonumber(y)) < 0.05, "centred on the board: " .. x .. " " .. y)
    eq(panel.scale, "0.0425 0.0425 1", "as wide as before")
    S.board.menu["Race panel larger"]("Red")
    eq(S.board.xml[1].attributes.scale, "0.0489 0.0489 1", "15% wider")
    assert(math.abs(onSave().json.edits.FDMonaco.panel.width - 460) < 1e-6, "saved")
    S.board.menu["Race panel smaller"]("Red")
    eq(S.board.xml[1].attributes.scale, "0.0425 0.0425 1")
    -- The editor's own items join the layout ones while it is open, and go
    -- again when it closes.
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    assert(S.board.menu["Pick up spaces here"], "editor items while it is open")
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(S.board.menu["Pick up spaces here"], nil)
    assert(S.board.menu["Put the race panel here"], "layout items stay")
end

function T.the_race_panel_goes_on_the_screen_for_a_map_without_a_spot()
    local S = world()
    S.board.custom = { image = "http://example.invalid/other-map.png" }
    fdMapChanged()
    eq(#S.board.xml, 0, "off the board")
    local found = nil
    for _, node in ipairs(S.xml) do
        if node.attributes.id == "fdr" then found = node end
    end
    assert(found, "on the screen")
    eq(found.attributes.rectAlignment, "UpperLeft")
    assert(S.ui.fdr_title, "and filled in")
end

function T.the_setup_menu_comes_back_after_the_flag()
    local S = redRacing()
    eq(S.ui.fds.active, "false")
    local saved = onSave()
    saved.json.race.phase = "finished"
    onLoad(saved)
    eq(S.ui.fds.active, "true", "back once the race is over")
    withRolls({ 12 }, function() fdSetupStart(Player.Red) end)
    eq(state().phase, "race", "Start race begins the next one")
    eq(state().round, 1)
    eq(S.ui.fds.active, "false")
end

function T.the_setup_menu_stays_up_while_the_editor_is_open()
    local S = redRacing()
    eq(S.ui.fds.active, "false")
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(S.ui.fds.active, "true", "so the editor can be closed")
    fdEdit({ color = "Red", steam_name = "RedPlayer" })
    eq(S.ui.fds.active, "false")
end

--- Red drops out mid-race: their seat empties.
local function redDropsOut(S)
    local red = Player.Red
    Player.Red = nil
    red.seated = false
    onPlayerDisconnect(red)
    return red
end

local function hasButton(dash, fn)
    for _, b in ipairs(dash.buttons) do
        if b.click_function == fn then return true end
    end
    return false
end

function T.a_dropped_driver_comes_back_to_their_car()
    local S = redRacing()
    local red = redDropsOut(S)
    assert(hasButton(S.beginner, "fdDashTakeOver"), "the dashboard offers its car")
    -- TTS seats them wherever it likes when they reconnect.
    red.color, red.seated = "Green", true
    Player.Green = red
    onPlayerConnect(red)
    eq(red.color, "Red", "back in their own colour")
    assert(state().cars.Red, "with their place in the race")
    assert(S.logged("RedPlayer is back in the Red car"))
    assert(not hasButton(S.beginner, "fdDashTakeOver"), "no longer orphaned")
end

function T.a_driver_back_by_the_dashboard_button()
    local S = redRacing()
    local red = redDropsOut(S)
    red.color, red.seated = "Grey", false
    Player.Grey = red
    S.beginner.click("fdDashTakeOver", "Grey")
    eq(red.color, "Red")
    assert(S.logged("RedPlayer is back in the Red car"))
end

function T.someone_else_can_take_over_an_orphaned_car()
    local S = redRacing()
    redDropsOut(S)
    local orange = S.player("Orange", S.vec(20, 1, -38))
    S.beginner.click("fdDashTakeOver", "Orange")
    eq(orange.color, "Red", "seated in the car's colour")
    eq(state().cars.Red.name, "OrangePlayer", "and drives it under their name")
    eq(state().cars.Red.tts.steam, "OrangeId")
    assert(S.logged("OrangePlayer takes over the Red car"))
end

function T.only_an_orphaned_car_can_be_taken_over()
    local S = redRacing()
    assert(not hasButton(S.beginner, "fdDashTakeOver"), "Red is in their seat")
    local orange = S.player("Orange", S.vec(20, 1, -38))
    fdDashTakeOver(S.beginner, "Orange")
    eq(orange.color, "Orange")
    eq(state().cars.Red.name, "RedPlayer")
end

function T.a_newcomer_in_an_orphaned_seat_is_moved_to_the_spectators()
    local S = redRacing()
    redDropsOut(S)
    local stranger = S.player("Red", S.vec(0, 1, -38))
    stranger.steam_id, stranger.steam_name = "StrangerId", "Stranger"
    onPlayerConnect(stranger)
    eq(stranger.color, "Grey")
    eq(state().cars.Red.name, "RedPlayer", "the car still waits for its driver")
    assert(S.logged("waiting for its driver"))
end

function T.only_the_driver_or_the_host_can_take_a_car_out()
    local S = redRacing()
    joinRace("Blue", S.advanced)
    S.beginner.click("fdDashLeave", "Blue")
    assert(state().cars.Red, "another driver cannot")
    assert(S.logged("Only RedPlayer or the host"))
    S.advanced.click("fdDashLeave", "Red")
    eq(state().cars.Blue, nil, "the host can")
    assert(S.logged("RedPlayer takes BluePlayer out of the race"))
end

function T.the_host_can_remove_a_driver_who_dropped_out()
    local S = redRacing()
    local host = S.player("Orange", S.vec(20, 1, -38), true)
    redDropsOut(S)
    S.beginner.click("fdDashLeave", "Orange")
    eq(state().cars.Red, nil, "out of the race")
    eq(#S.beginner.buttons, 0, "and the dashboard is free")
    assert(host.color == "Orange", "the host stays where they are")
end

function T.a_die_lost_in_the_race_is_fetched_again()
    local S = redRacing()
    local names = {}
    for i, n in ipairs({ "First", "Second", "Third", "Fourth", "Fifth", "Sixth" }) do
        names[i] = { name = n .. " Gear Dice", guid = "d" .. i }
    end
    names[7] = { name = "Damage Dice", guid = "d7" }
    S.object("Dice Set Bag", { guid = "ac4939", spawns = "Dice Set", spawnContents = names })
    fdUiShift(Player.Red, "1")
    -- Thrown, it falls through the table and is gone.
    S.find("First Gear Dice").destruct()
    fdUiRoll(Player.Red)
    assert(S.logged("1st gear die has gone"), "Red is told")
    assert(S.logged("Put 1 missing dice back out"))
    local die = S.find("First Gear Dice")
    assert(die, "a new one is out")
    eq(S.count("First Gear Dice"), 1, "just the one")
    eq(S.count("Second Gear Dice"), 1, "and nothing else doubled")
    assert(inTray(S, die), "in the tray, as it is the die in play")
    die.value = 2
    fdUiRoll(Player.Red)
    eq(state().cars.Red.lastRoll, 2, "and it rolls")
end

function T.the_die_in_play_is_let_go_above_the_tray()
    local S = redRacing()
    fdUiShift(Player.Red, "1")
    local loose, parked = S.find("First Gear Dice"), S.find("Second Gear Dice")
    assert(loose.pos.y > parked.pos.y + 1, "dropped in from well above the board")
end

function T.a_gear_die_is_given_a_convex_collider()
    local S = world()
    local die = S.object("First Gear Dice", { custom = { mesh = "m", collider = "c", convex = false } })
    onObjectSpawn(die)
    eq(die.custom.convex, true, "convex, so it cannot fall through the board")
    eq(die.reloads, 1, "reloaded to take it")
    eq(#die.rotationValues, 4, "and taught its faces once back")
    onObjectSpawn(die)
    eq(die.reloads, 1, "only once")
end

function T.the_black_die_is_thrown_in_the_tray_for_each_check()
    local S, red, blue = twoCars()
    local black = S.find("Damage Dice")
    -- In join order: Red rolls 4, Blue 15 for the grid; then Blue's start.
    withRolls({ 4, 15, 12 }, function() fdSetupStart(Player.Red) end)
    eq(black.rolls, 3, "thrown for each grid roll and the leader's start")
    eq(state().phase, "race", "and the race under way once the grid settled")
    assert(S.logged("BluePlayer rolls 12 on the black die %(start%)"))
    eq(black.locked, true, "parked again once it has settled")
    assert(not inTray(S, black))
end

function T.without_the_black_die_the_script_rolls_for_it()
    local S = twoCars()
    S.find("Damage Dice").destruct()
    withRolls({ 4, 15 }, function() fdSetupStart(Player.Red) end)
    eq(state().phase, "race", "the grid is rolled all the same")
end

--- The ghost marking where the car to play started, if one is out.
--- The start flag on the board and the seat it is for; nil if none is out.
local function startFlag(S)
    for _, d in ipairs(S.board.decals or {}) do
        local seat = d.name:match("^start%-(%a+)$")
        if seat then return d, seat end
    end
    return nil
end

function T.a_flag_marks_where_the_car_to_play_started()
    local S, red, blue = twoCars()
    eq(startFlag(S), nil, "none before the race")
    gridRoll(S, { Red = 4, Blue = 15 })
    fdStart(Player.Red)
    local first, second = state().order[1], state().order[2]
    local cars = { Red = red, Blue = blue }
    eq(select(2, startFlag(S)), first, "out for the car to play, in its colour")
    eq(iconsAt(S, state().cars[first].space), "start-" .. first, "on its space")

    -- Rolled, and put back on the flag: not moved, still its turn.
    fdUiShift(Player[first], "1")
    roll(S, 1, 2, first)
    onObjectDrop(first, cars[first])
    assert(S.logged(first .. "Player is back where its move started"))
    eq(Turns.turn_color, first, "still to move")
    -- Moved for real: the turn passes, and the flag with it.
    moveOn(S, cars[first], first)
    eq(Turns.turn_color, second)
    local flags = 0
    for _, d in ipairs(S.board.decals or {}) do
        if d.name:find("^start%-") then flags = flags + 1 end
    end
    eq(flags, 1, "one flag at a time")
    eq(select(2, startFlag(S)), second)
end

function T.the_panels_go_up_even_if_the_ui_never_says_it_has_loaded()
    local S = world()
    UI.loading = true -- TTS stuck saying so
    S.xml, S.ui = {}, {}
    onLoad("")
    UI.loading = false
    local ids = {}
    for _, node in ipairs(S.xml) do ids[node.attributes.id or ""] = true end
    assert(ids.fds, "the setup menu is sent")
    eq(S.ui.fds.active, "true", "and shown")
end

function T.a_load_clears_the_marks_the_save_kept()
    local S = redRacing()
    redOn(S, "m.s2.5")
    roll(S, 1, 2)
    assert(marksOn(S).clean, "marks out")
    local saved, kept = onSave(), S.board.decals
    -- Loaded afresh, the board comes back with the decals it was saved with.
    local S2 = world()
    S2.board.decals = kept
    onLoad(saved)
    eq(marksOn(S2).clean, nil, "the move's marks are gone")
    eq(marksOn(S2).brake, nil)
end

function T.the_map_cannot_change_during_the_grid_roll()
    local S = twoCars()
    local Maps = require("fd.data.maps")
    local saved = onSave()
    saved.json.race.phase = "grid"
    onLoad(saved)
    fdSetupMap(Player.Red, "Formula D: Austin  (no track data)")
    eq(S.board.custom.image, Maps.byId.FDMonaco.url)
end

return T
