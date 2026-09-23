-- Global script: owns the race and wires TTS events to it.
--
-- The rules live in fd.core.race / fd.rules.*, which make no TTS calls; this
-- file turns clicks, dice and moved pieces into calls on the race, then relays
-- the events it produces and syncs the dashboards and the race panel.
--
-- Each player drives from their dashboard: its buttons (fd.tts.controls) join
-- the race and cover damage, pit stops and WP corrections, the gear stick
-- selects a gear when dropped on a slot, and the WP marker sets WP when dropped
-- on a number. Braking and overshooting are charged when a car is put down
-- after its roll.

local Race = require("fd.core.race")
local Rules = require("fd.rules.beginner")
local Maps = require("fd.data.maps")
local Dice = require("fd.tts.dice")
local Dashboard = require("fd.tts.dashboard")
local Hud = require("fd.tts.hud")
local Controls = require("fd.tts.controls")
local Mini = require("fd.tts.minidash")
local Track = require("fd.tts.track")
local Editor = require("fd.tts.track_editor")
local Ghosts = require("fd.tts.ghosts")
local TRACKS = { FDMonaco = require("fd.data.tracks.FDMonaco") }

mod_packed = false
setup_packed = false

local race
local syncCars -- defined with the rest of the car handling, below
local snapCar -- defined with the track, below
local spaceUnder -- likewise
local undo = {}
local UNDO_LIMIT = 30

local LEVEL_RGB = {
    info = { 0.85, 0.85, 0.85 },
    warn = { 1, 0.72, 0.3 },
    wear = { 1, 0.45, 0.35 },
    out = { 1, 0.2, 0.2 },
}

-- Setup ---------------------------------------------------------------------

local function applyModMenuButton()
    UI.setAttribute("showModMenuButton", "active", mod_packed and "true" or "false")
end

function onLoad(saved_data)
    local saved = {}
    if saved_data and saved_data ~= "" then
        saved = JSON.decode(saved_data) or {}
        mod_packed = saved.mp
        setup_packed = saved.sp
    else
        mod_packed = true
        setup_packed = true
    end
    applyModMenuButton()

    race = Race.new(Rules, saved.race)
    Dice.prepareAll()
    Dashboard.scan()
    Mini.registerAsset()
    setupTrackEditor(saved.edits, saved.markers)
    buildUi()
end

--- (Re)build the race panel and the screen dashboards, then fill them in.
function buildUi()
    -- Until the new XML has loaded, updates would go to elements on their way
    -- out and then be skipped as repeats once it has (see fd.tts.ui).
    Mini.setReady(false)
    Hud.build(Rules.name, Mini.panels(Rules), function()
        applyModMenuButton()
        Mini.setReady()
        refresh()
    end)
end

-- Players who join after onLoad get the XML saved with the game, not the panels
-- the script added, and TTS does not re-check `visibility` when a player
-- changes seat. Sending the whole UI again fixes both. Batched so a burst of
-- joins and seat changes costs one rebuild.
local rebuildPending = false

local function rebuildUiSoon()
    if rebuildPending then
        return
    end
    rebuildPending = true
    Wait.time(function()
        rebuildPending = false
        buildUi()
    end, 1)
end

function onPlayerConnect()
    rebuildUiSoon()
end

function onPlayerChangeColor()
    rebuildUiSoon()
end

function onSave()
    return JSON.encode({
        mp = mod_packed, sp = setup_packed, race = race and race:serialize(),
        -- Hand edits to track spaces; tools/extract/import_track.py reads them.
        edits = Editor.save(),
        -- Editor markers out on the board; removed on load (see Editor.load).
        markers = (function()
            local out = Editor.markerGuids()
            for _, g in ipairs(Ghosts.guids()) do out[#out + 1] = g end
            return out
        end)(),
    })
end

function showModMenu()
    local memoryBagModMenu = getObjectFromGUID("a57988")
    if memoryBagModMenu then
        memoryBagModMenu.call("buttonClick_place", {})
    end
    mod_packed = false
    applyModMenuButton()
end

-- Plumbing ------------------------------------------------------------------

local function relay(events)
    for _, e in ipairs(events) do
        local rgb = LEVEL_RGB[e.level] or LEVEL_RGB.info
        if e.level == "wear" or e.level == "out" then
            broadcastToAll(e.text, rgb)
        else
            printToAll(e.text, rgb)
            if e.level == "warn" and e.color and Player[e.color] and Player[e.color].seated then
                broadcastToColor(e.text, e.color, rgb)
            end
        end
    end
end

local function tintOf(color)
    return Color.fromString(color)
end

-- What each car's dashboard last showed, so an action that leaves a car alone
-- does not move all of its markers again.
local synced = {}

local function dashState(car)
    local parts = { car.tts.dash or "", car.gear }
    for _, z in ipairs(Rules.zones) do parts[#parts + 1] = car.wear[z.id] end
    return table.concat(parts, "|")
end

--- Put every car's gear stick and wear markers where the race says.
-- `force` re-places them even if nothing changed: after a player drops one
-- somewhere it should not be, or moves the dashboard.
local function syncDashboards(force)
    if force then synced = {} end
    for _, car in ipairs(race:cars()) do
        car.tts = car.tts or {}
        local state = dashState(car)
        local dash = synced[car.color] ~= state and car.tts.dash and getObjectFromGUID(car.tts.dash)
        if dash then
            synced[car.color] = state
            if Dashboard.fits(dash, Rules) then
                car.tts.markers = car.tts.markers or {}
                Dashboard.sync(dash, car.tts.markers, car, Rules, tintOf(car.color))
                car.tts.faceWarned = nil
            elseif not car.tts.faceWarned then
                car.tts.faceWarned = true
                broadcastToColor("Flip your dashboard to the beginner side to track wear on it.",
                    car.color, LEVEL_RGB.warn)
            end
        end
    end
end

--- The car whose dashboard is `guid`, if any.
local function carOnDash(guid)
    for _, car in ipairs(race:cars()) do
        if car.tts and car.tts.dash == guid then
            return car
        end
    end
    return nil
end

local function dashLabel(car)
    local parts = { race:label(car) }
    if car.eliminated then
        parts[#parts + 1] = "OUT"
    else
        parts[#parts + 1] = car.gear > 0 and (Race.gearName(car.gear) .. " gear") or "on the grid"
        parts[#parts + 1] = Hud.wearSummary(race, car)
        if car.lastRoll then
            parts[#parts + 1] = "rolled " .. car.lastRoll
        end
    end
    if not (car.tts.car and getObjectFromGUID(car.tts.car)) then
        parts[#parts + 1] = "no car -- press Car"
    end
    for _, c in ipairs(race:pendingChecks()) do
        if c.color == car.color then
            parts[#parts + 1] = "ROLL BLACK DIE (" .. race.rules.checks[c.kind].name .. ")"
            break
        end
    end
    return table.concat(parts, "  |  ")
end

local function renderDashboards()
    for _, obj in ipairs(Dashboard.all()) do
        local car = carOnDash(obj.getGUID())
        Controls.render(obj, car, car and dashLabel(car))
    end
end

function refresh()
    syncCars()
    Hud.refresh(race)
    Mini.refresh(race)
    renderDashboards()
end

--- Run a change to the race: snapshot for undo, apply, then publish.
local function act(fn)
    undo[#undo + 1] = JSON.encode(race:serialize())
    if #undo > UNDO_LIMIT then
        table.remove(undo, 1)
    end
    fn()
    relay(race:drain())
    syncDashboards()
    refresh()
end

local function handPosition(color)
    local p = Player[color]
    local hand = p and p.getHandTransform()
    return hand and hand.position or nil
end

--- Where to put a die for `color`: just past their dashboard (or hand),
-- towards the middle of the table.
local function dicePosition(color)
    local car = race:car(color)
    local dash = car and car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)
    local base = dash and dash.getPosition() or handPosition(color)
    if not base then
        return nil
    end
    local len = math.sqrt(base.x ^ 2 + base.z ^ 2)
    local reach = dash and 6 or 8
    if len < 1 then
        return { x = base.x, y = base.y + 2, z = base.z }
    end
    return { x = base.x - base.x / len * reach, y = base.y + 2, z = base.z - base.z / len * reach }
end

-- Dice ----------------------------------------------------------------------

-- Who a gear die result belongs to: the roller if they are racing, otherwise
-- the only car with that gear selected, otherwise the roller anyway.
local function ownerOf(color, gear)
    if race:car(color) then
        return color
    end
    local match = nil
    for _, car in ipairs(race:cars()) do
        if car.gear == gear then
            if match then return color end
            match = car.color
        end
    end
    return match or color
end

function onObjectRandomize(obj, color)
    local gear = Dice.gearOf(obj)
    if gear then
        Dice.watch(obj, color, function(value, roller)
            if value then
                act(function() race:rolled(ownerOf(roller, gear), gear, value) end)
            end
        end)
    elseif Dice.isBlack(obj) then
        Dice.watch(obj, color, function(value, roller)
            if value then
                act(function() race:blackDie(value, roller) end)
            end
        end)
    end
end

-- Cars ------------------------------------------------------------------------

local CAR_NAMES = { ["Formula 1 Solid"] = true, ["Sports Car"] = true }
local CAR_BAG = "1bb99e" -- Formula 1 Black Bag, an infinite bag
-- A car further away than this is somebody else's; take a fresh one instead.
local CLAIM_RANGE = 15
-- How close a dropped car has to land to a dashboard to be claimed by it.
local DROP_RANGE = 4

local function carsClaimed(except)
    local taken = {}
    for _, c in ipairs(race:cars()) do
        if c ~= except and c.tts and c.tts.car then
            taken[c.tts.car] = true
        end
    end
    return taken
end

local function nearestCar(pos, taken, range)
    local best, bestDist = nil, range and range * range or nil
    for _, obj in ipairs(getObjects()) do
        if CAR_NAMES[obj.getName()] and not taken[obj.getGUID()] then
            local p = obj.getPosition()
            local d = (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2
            if not bestDist or d <= bestDist then
                best, bestDist = obj, d
            end
        end
    end
    return best
end

--- The car in the race driving the car object `guid`, if any.
local function carOwning(guid)
    for _, c in ipairs(race:cars()) do
        if c.tts and c.tts.car == guid then
            return c
        end
    end
    return nil
end

--- Where a player's own things belong: their seat, or their dashboard.
local function basePosition(car)
    local dash = car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)
    return handPosition(car.color) or (dash and dash.getPosition())
end

--- What a claimed car is called: hovering it says whose it is.
local function carName(car)
    return race:label(car) .. " (" .. car.color .. ")"
end

local function setCar(car, obj, verb)
    car.tts.car = obj.getGUID()
    car.tts.carWas = car.tts.carWas or obj.getName()
    obj.setName(carName(car))
    obj.setColorTint(tintOf(car.color))
    obj.highlightOn(car.color, 4)
    -- A car claimed where it stands may already be on the track.
    race:placed(car.color, spaceUnder(obj))
    race:emit("info", race:label(car) .. " " .. verb, car.color)
end

--- Hand a car back: its own name, its own paint.
local function releaseCar(car)
    local obj = car.tts.car and getObjectFromGUID(car.tts.car)
    if obj then
        obj.setName(car.tts.carWas or "")
        obj.setColorTint({ 1, 1, 1 })
    end
    car.tts.car = nil
    car.tts.carWas = nil
    race:placed(car.color, nil)
end

--- Keep the names right as drivers join, leave or are renamed.
syncCars = function()
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        if obj and obj.getName() ~= carName(car) then
            obj.setName(carName(car))
        end
    end
end

-- Pieces on the dashboards ---------------------------------------------------

-- How far from a slot a dropped piece may land and still count, in world units.
local GEAR_REACH = 1.0
local WEAR_REACH = 0.5

--- The car and marker kind ("gear" or a zone id) that `guid` belongs to.
local function markerOwner(guid)
    for _, car in ipairs(race:cars()) do
        local m = car.tts and car.tts.markers
        if m then
            if m.gear == guid then
                return car, "gear"
            end
            for zone, g in pairs(m.wear or {}) do
                if g == guid then
                    return car, zone
                end
            end
        end
    end
    return nil
end

local function shiftTo(color, gear)
    act(function() race:shift(color, gear) end)
    local pos = dicePosition(color)
    if pos then
        Dice.bring(gear, pos, color)
    end
end

--- A dashboard may have been moved or flipped: redraw it and pull its markers along.
local function dashboardMoved(dash)
    Wait.time(function()
        if dash == nil then return end
        Controls.invalidate(dash)
        syncDashboards(true)
        renderDashboards()
    end, 0.8)
end

function onObjectHover(color, obj)
    Editor.onHover(color, obj)
end

function onObjectDrop(color, obj)
    if Editor.onDropped(obj) then
        return
    end
    if Dashboard.is(obj) then
        dashboardMoved(obj)
        return
    end
    if CAR_NAMES[obj.getName()] then
        -- Dropping a car on a dashboard claims it for that dashboard's driver.
        local pos = obj.getPosition()
        local taken = carsClaimed(nil)
        for _, c in ipairs(race:cars()) do
            local dash = c.tts.dash and getObjectFromGUID(c.tts.dash)
            if dash and not taken[obj.getGUID()] then
                local p = dash.getPosition()
                if (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2 <= DROP_RANGE * DROP_RANGE then
                    act(function() setCar(c, obj, "claims the car dropped on their dashboard") end)
                    return
                end
            end
        end
    end
    local owner = carOwning(obj.getGUID())
    if owner or CAR_NAMES[obj.getName()] then
        local space, track = snapCar(obj)
        if owner then
            -- Put down during its move, the move is judged and charged:
            -- undoable, and the dashboards show the result.
            act(function() race:placed(owner.color, space and space.id, track) end)
        end
        return
    end
    local car, kind = markerOwner(obj.getGUID())
    local dash = car and car.tts.dash and getObjectFromGUID(car.tts.dash)
    if not dash then
        return
    end
    local pos = obj.getPosition()
    if kind == "gear" then
        local gear = Dashboard.slotAt(dash, "gear", pos, GEAR_REACH)
        if gear and gear ~= car.gear then
            shiftTo(car.color, gear)
        else
            syncDashboards(true) -- same gear or off the gate: settle it back in its slot
        end
    else
        local value = Dashboard.slotAt(dash, kind, pos, WEAR_REACH)
        if value then
            act(function() race:setWear(car.color, kind, value, "marker moved") end)
        else
            syncDashboards(true)
        end
    end
end

function onObjectRotate(obj, spin, flip, color, oldSpin, oldFlip)
    if Dashboard.is(obj) and flip ~= oldFlip then
        dashboardMoved(obj)
    end
end

function onObjectSpawn(obj)
    Dice.prepare(obj)
    if Dashboard.is(obj) then
        Dashboard.track(obj)
        dashboardMoved(obj)
    end
end

-- Actions --------------------------------------------------------------------
-- Each one is reachable twice: from the buttons on the dashboard object, and
-- from the copy of the dashboard on a player's screen.

local ACTIONS = {
    --- Point the player at their car: theirs if claimed, otherwise the nearest
    -- free one, otherwise a fresh one out of the bag.
    car = function(car)
        local mine = car.tts.car and getObjectFromGUID(car.tts.car)
        if mine then
            mine.highlightOn(car.color, 4)
            race:emit("info", race:label(car) .. "'s car is highlighted", car.color)
            return
        end
        local base = basePosition(car)
        local found = base and nearestCar(base, carsClaimed(car), CLAIM_RANGE)
        if found then
            setCar(car, found, "claims the nearest car")
            return
        end
        local bag = getObjectFromGUID(CAR_BAG)
        if not bag or not base then
            race:emit("warn", race:label(car) .. " has no car nearby -- take one from a car bag", car.color)
            return
        end
        local spawned = bag.takeObject({
            position = { x = base.x, y = base.y + 2, z = base.z },
            rotation = { x = 0, y = 0, z = 0 }, smooth = false,
        })
        setCar(car, spawned, "takes a car from the bag")
    end,
    collision = function(car) race:requestCheck(car.color, "collision") end,
    pit = function(car) race:pitStop(car.color) end,
    wearDown = function(car) race:adjust(car.color, nil, -1, "manual") end,
    wearUp = function(car) race:adjust(car.color, nil, 1, "manual") end,
    leave = function(car)
        releaseCar(car)
        local m = car.tts.markers or {}
        local guids = { m.gear }
        for _, g in pairs(m.wear or {}) do
            guids[#guids + 1] = g
        end
        for _, g in pairs(guids) do
            local obj = getObjectFromGUID(g)
            if obj then obj.destruct() end
        end
        race:leave(car.color)
    end,
}

local function runAction(car, name)
    if car and ACTIONS[name] then
        act(function() ACTIONS[name](car) end)
    end
end

-- Dashboard buttons ---------------------------------------------------------
-- TTS calls object buttons as fn(object, playerColor, altClick). The actions
-- apply to the car that owns the dashboard, whoever clicks.

function fdNoop() end

local SEATS = {
    White = true, Brown = true, Red = true, Orange = true, Yellow = true,
    Green = true, Teal = true, Blue = true, Purple = true, Pink = true,
}

function fdDashJoin(dash, color)
    if not SEATS[color] then
        broadcastToColor("Take a coloured seat to join the race.", color, LEVEL_RGB.warn)
        return
    end
    local guid = dash.getGUID()
    local holder = carOnDash(guid)
    if holder and holder.color ~= color then
        broadcastToColor(race:label(holder) .. " is already using this dashboard.", color, LEVEL_RGB.warn)
        return
    end
    act(function()
        local car = race:join(color, Player[color] and Player[color].steam_name)
        car.tts = car.tts or {}
        car.tts.dash = guid
        car.tts.faceWarned = nil
    end)
    dash.highlightOn(color, 3)
end

local function onDash(dash, name)
    runAction(carOnDash(dash.getGUID()), name)
end

function fdDashCar(dash) onDash(dash, "car") end
function fdDashCollision(dash) onDash(dash, "collision") end
function fdDashPit(dash) onDash(dash, "pit") end
function fdDashLeave(dash) onDash(dash, "leave") end

function fdDashWear(dash, color, alt)
    onDash(dash, alt and "wearUp" or "wearDown")
end

-- The dashboard on screen ----------------------------------------------------
-- TTS calls UI handlers as fn(player, value, elementId); these act on the
-- clicking player's own car.

local function mine(player)
    return race:car(player.color)
end

function fdUiCar(player) runAction(mine(player), "car") end
function fdUiCollision(player) runAction(mine(player), "collision") end
function fdUiPit(player) runAction(mine(player), "pit") end
function fdUiLeave(player) runAction(mine(player), "leave") end

function fdUiShift(player, value)
    local gear = tonumber(value)
    if gear and mine(player) then
        shiftTo(player.color, gear)
    end
end

--- `value` arrives as "<zone>:<number>", e.g. "wp:12".
function fdUiWear(player, value)
    local car = mine(player)
    if not car then
        return
    end
    local zone, n = tostring(value):match("^(%a+):(%d+)$")
    if zone then
        act(function() race:setWear(player.color, zone, tonumber(n), "set on screen") end)
    end
end

-- Race panel ----------------------------------------------------------------

function fdGrid(player)
    printToAll(player.steam_name .. " calls the grid roll", LEVEL_RGB.info)
    act(function() race:rollForGrid() end)
end

function fdStart(player)
    printToAll(player.steam_name .. " starts the race", LEVEL_RGB.info)
    act(function() race:startRace() end)
end

function fdReset(player)
    printToAll(player.steam_name .. " reset the race (Undo restores it)", LEVEL_RGB.info)
    act(function() race:reset() end)
end

function fdUndo(player)
    local last = table.remove(undo)
    if not last then
        broadcastToColor("Nothing to undo.", player.color, LEVEL_RGB.info)
        return
    end
    race = Race.new(Rules, JSON.decode(last))
    -- Undo puts the race back, not the pieces: the board still says where
    -- the cars are.
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        race:placed(car.color, obj and spaceUnder(obj))
    end
    printToAll(player.steam_name .. " undid the last change", LEVEL_RGB.info)
    syncDashboards(true)
    refresh()
end

function fdToggleRace()
    Hud.toggleRace()
end

-- Track overlay and editor -------------------------------------------------------

local trackShown = nil

--- The track data for the map on the board, if there is any.
local function trackOnBoard()
    local tile = Track.tile()
    local custom = tile and tile.getCustomObject()
    for id, track in pairs(TRACKS) do
        local map = Maps and Maps.byId and Maps.byId[id]
        if custom and map and custom.image == map.url then
            return track
        end
    end
    return nil
end

local function editorStatus()
    if not Editor.isOpen() then
        Hud.setEditor(nil)
        return
    end
    local track = Editor.trackFor(TRACKS[Editor.openId()])
    local _, problems = Editor.problems()
    Hud.setEditor(string.format("Editing %s: %d spaces, %d problem(s) shown red, %d marker(s) out",
        track.name, #track.spaces, #problems, Editor.markerCount()))
end

--- Draw the spaces over the board, to check them against the print.
function fdTrack(player)
    if Editor.isOpen() then
        broadcastToColor("The editor is open; close it to hide the spaces.", player.color, LEVEL_RGB.info)
        return
    end
    if trackShown then
        Track.hide()
        Ghosts.clear()
        trackShown = nil
        printToAll("Track overlay off", LEVEL_RGB.info)
        return
    end
    local track = trackOnBoard()
    if not track then
        broadcastToColor("No track data for the map on the board yet.", player.color, LEVEL_RGB.warn)
        return
    end
    local ok, why = Track.show(Editor.trackFor(track))
    if ok then
        Ghosts.show(Editor.trackFor(track))
        trackShown = track.id
        printToAll(string.format("%s: %d spaces", track.name, #Editor.trackFor(track).spaces), LEVEL_RGB.info)
    else
        broadcastToColor("Cannot show the track: " .. why, player.color, LEVEL_RGB.warn)
    end
end

-- How far from a space a car may be put down and still be moved onto it, in
-- cells. Put down further off -- off the track, or between spaces with no
-- free one near -- it stays where it was put.
local SNAP_REACH = 0.9
-- How far above the board face a snapped car is set down; it drops from there.
local SNAP_LIFT = 0.3
-- How far from a space's centre a car counts as on it, in cells: half a
-- cell is as far as a car can be from one space and still nearer to it.
local ON_SPACE = 0.5

--- A car put down on the track: settle it onto the nearest free space, facing
-- the way the track runs. Advisory like the rest -- it only helps a car land
-- neatly on a space the player chose, and does nothing off the track.
-- Returns the space it went to and the track it is on, or nil.
snapCar = function(obj)
    local tile = Track.tile()
    local track = tile and trackOnBoard()
    if not track then
        return nil
    end
    track = Editor.trackFor(track)
    local others = {}
    for _, c in ipairs(race:cars()) do
        local o = c.tts and c.tts.car ~= obj.getGUID() and c.tts.car and getObjectFromGUID(c.tts.car)
        if o then
            others[#others + 1] = o.getPosition()
        end
    end
    local space, pos, yaw = Track.snap(tile, track, obj.getPosition(), SNAP_REACH, others)
    if not space then
        return nil
    end
    obj.setPositionSmooth({ x = pos.x, y = pos.y + SNAP_LIFT, z = pos.z }, false, true)
    -- The car models' noses point along their local +Z.
    obj.setRotationSmooth({ x = 0, y = yaw, z = 0 }, false, true)
    return space, track
end

--- The id of the space a car is sitting on, without moving it; nil if it is
-- off the track or there is no track data for the board.
spaceUnder = function(obj)
    local tile = Track.tile()
    local track = tile and trackOnBoard()
    if not track then
        return nil
    end
    track = Editor.trackFor(track)
    local s = Track.spaceNear(tile, Track.frame(tile, track), track, obj.getPosition(), ON_SPACE)
    return s and s.id
end

local function pickUpAt(color, pos)
    local n = Editor.grab(pos)
    broadcastToColor(n > 0 and ("Picked up " .. n .. " space(s).") or "No spaces nearby.", color, LEVEL_RGB.info)
    editorStatus()
end

local function addAt(color, pos)
    local s = Editor.add(pos)
    if not s then
        broadcastToColor("The board tile is missing.", color, LEVEL_RGB.warn)
        return
    end
    broadcastToColor("Added space " .. s.id .. " in lane " .. s.lane .. ".", color, LEVEL_RGB.info)
    editorStatus()
end

--- Right-click menu on the board while the editor is open: it knows where
-- the player clicked, so nothing needs a key bound to it.
local function boardMenu(on)
    local tile = Track.tile()
    if not tile then return end
    tile.clearContextMenu()
    if not on then return end
    tile.addContextMenuItem("Pick up spaces here", function(color, pos) pickUpAt(color, pos) end)
    tile.addContextMenuItem("Add a space here", function(color, pos) addAt(color, pos) end)
    tile.addContextMenuItem("Apply track edits", function(color) fdApply({ color = color }) end)
end

--- Open or close the track editor for the map on the board.
function fdEdit(player)
    if Editor.isOpen() then
        local n = Editor.markerCount()
        Editor.close()
        boardMenu(false)
        Track.hide()
        trackShown = nil
        printToAll(string.format("Track editor closed%s. Save the game to keep the edits.",
            n > 0 and (" (" .. n .. " marker(s) applied)") or ""), LEVEL_RGB.info)
        editorStatus()
        return
    end
    local track = trackOnBoard()
    if not track then
        broadcastToColor("No track data for the map on the board yet.", player.color, LEVEL_RGB.warn)
        return
    end
    Ghosts.clear()               -- the overlay's ghosts; the editor puts out its own
    Editor.onChange = editorStatus
    Editor.open(track)
    boardMenu(true)
    trackShown = track.id
    editorStatus()
    broadcastToColor("Track editor open. Right-click the board: Pick up spaces here. Drag the "
        .. "blocks, Q/E to turn, right-click one for its lane or to delete it, then Apply. "
        .. "(Keys for all of this can be bound in Options > Game Keys, under \"Track editor\".)",
        player.color, LEVEL_RGB.info)
end

function fdApply(player)
    if not Editor.isOpen() then
        return
    end
    local n = Editor.apply()
    editorStatus()
    printToAll(string.format("Applied %d marker(s); links recomputed.", n), LEVEL_RGB.info)
end

--- Getting edits out of the game and into the repo.
function fdExport(player)
    local saved = Editor.save()
    local names = {}
    for id, e in pairs(saved) do
        names[#names + 1] = string.format("%s (%d spaces)", id, #e.spaces)
    end
    if #names == 0 then
        broadcastToColor("No track edits to export yet.", player.color, LEVEL_RGB.info)
        return
    end
    printToAll("Edited: " .. table.concat(names, ", "), LEVEL_RGB.info)
    broadcastToColor("To export: save the game (Menu > Save), then in the repo run "
        .. "python tools/extract/import_track.py -- it writes tracks/<id>.json from the newest save.",
        player.color, LEVEL_RGB.info)
end

local function editorKey(fn)
    return function(color, hovered, pointer, up)
        if up then return end
        if not Editor.isOpen() then
            broadcastToColor("Open the track editor first (Edit on the race panel).", color, LEVEL_RGB.warn)
            return
        end
        fn(color, hovered, pointer)
        editorStatus()
    end
end

local function registerEditorKeys()
    addHotkey("Track editor: pick up spaces here", editorKey(function(color, _, pointer)
        pickUpAt(color, pointer)
    end))
    addHotkey("Track editor: add a space here", editorKey(function(color, _, pointer)
        addAt(color, pointer)
    end))
    for lane = 1, 3 do
        addHotkey("Track editor: move space to lane " .. lane, editorKey(function(color, hovered)
            if not Editor.setLane(hovered, lane) then
                broadcastToColor("Point at a space marker first.", color, LEVEL_RGB.warn)
            end
        end))
    end
    addHotkey("Track editor: apply", editorKey(function(color)
        fdApply({ color = color })
    end))
    -- Pressed on one space, then on another: adds the link, or removes it.
    addHotkey("Track editor: link or unlink two spaces", editorKey(function(color, hovered, pointer)
        broadcastToColor(Editor.linkKey(hovered, pointer), color, LEVEL_RGB.info)
    end))
end

function onObjectDestroy(obj)
    Dashboard.forget(obj)
    -- A car's gear stick or wear marker gone: the next update brings a new one.
    local car = markerOwner(obj.getGUID())
    if car then
        synced[car.color] = nil
    end
    if Editor.onDestroyed(obj) then
        editorStatus()
    end
end

--- Called from onLoad: restore saved edits and register the editor's keys.
function setupTrackEditor(saved, strayMarkers)
    Editor.load(saved, strayMarkers)
    registerEditorKeys()
end
