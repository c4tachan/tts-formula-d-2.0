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
local Ui = require("fd.tts.ui")
local Controls = require("fd.tts.controls")
local Mini = require("fd.tts.minidash")
local Track = require("fd.tts.track")
local Editor = require("fd.tts.track_editor")
local Ghosts = require("fd.tts.ghosts")
local Setup = require("fd.tts.setup")
local TRACKS = { FDMonaco = require("fd.data.tracks.FDMonaco") }

mod_packed = false
setup_packed = false

local race
local syncCars -- defined with the rest of the car handling, below
local snapCar -- defined with the track, below
local placeOnGrid -- likewise
local spaceUnder -- likewise
local showReach -- likewise
local clearReach -- likewise
local useBoardTrack -- likewise
local joinAt -- with the dashboard buttons, below
local deliver, dealInSeated, dropDashless, bench -- likewise
-- What syncTurns last told TTS's Turns, as { on, order, color }; nil until
-- it has, so the first sync after a load sets every part.
local turnsSet = nil
local undo = {}
local joining = {} -- steam id -> true from connecting until moved to the spectators (see bench)
local UNDO_LIMIT = 30

--- One roll of the black die, made by the script: the grid, starts,
-- collisions and engine strain are all rolled this way, the result told in
-- the chat. (The die on the table still counts if somebody throws it.)
local function rollBlack()
    return math.random(20)
end

-- The colour of each kind of message in chat. A roll is shown in the colour
-- of the seat that rolled it, when there is one (see relay).
local LEVEL_RGB = {
    info = { 0.85, 0.85, 0.85 },
    warn = { 1, 0.72, 0.3 },
    wear = { 1, 0.45, 0.35 },
    out = { 1, 0.2, 0.2 },
    finish = { 1, 0.84, 0.25 },
    turn = { 0.49, 0.99, 0 },
    order = { 0.55, 0.8, 1 },
    lap = { 0.78, 0.62, 1 },
    roll = { 1, 1, 1 },
}

local SEATS = {
    White = true, Brown = true, Red = true, Orange = true, Yellow = true,
    Green = true, Teal = true, Blue = true, Purple = true, Pink = true,
}

-- Setup ---------------------------------------------------------------------

local MOD_MENU_BAG = "a57988"
local SETUP_BAG = "0fde3b"

--- The Big Box menu button: there while the menu is packed away, but not
-- during a race -- the map is chosen before the start or after the flag.
-- Global so the menu board can call it when it closes.
function applyModMenuButton()
    local racing = race and race.state.phase == "race"
    Ui.set("showModMenuButton", "active", tostring(mod_packed and not racing))
end

--- At the start, put the Big Box menu and the setup board back in their bags.
local function packTable()
    local bags = { { MOD_MENU_BAG, mod_packed }, { SETUP_BAG, setup_packed } }
    for _, b in ipairs(bags) do
        local bag = not b[2] and getObjectFromGUID(b[1])
        if bag then
            bag.call("buttonClick_recall", {})
        end
    end
    -- The bags say so themselves (Global.setVar); this is in case they did not.
    mod_packed, setup_packed = true, true
end

--- The map on the board tile, from Maps.list, or nil if it is none we know.
local function mapOnBoard()
    local tile = Track.tile()
    local custom = tile and tile.getCustomObject()
    if not custom then
        return nil
    end
    for _, map in ipairs(Maps.list) do
        if custom.image == map.url then
            return map
        end
    end
    return nil
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
    race.autoRolls = true
    turnsSet = nil
    Dice.prepareAll()
    Dashboard.scan()
    Mini.registerAsset()
    setupTrackEditor(saved.edits, saved.markers)
    useBoardTrack()
    buildUi()
    -- A moment for every object to have spawned: a dashboard not there yet
    -- would look deleted, and its driver be taken out. Nobody is dealt in
    -- yet: that waits for Start race (see fdSetupStart).
    Wait.time(function()
        Dashboard.scan()
        dropDashless()
    end, 1)
end

--- (Re)build the race panel on the board, the screen dashboards and the
-- setup menu, then fill them in.
function buildUi()
    -- Until the new XML has loaded, updates would go to elements on their way
    -- out and then be skipped as repeats once it has (see fd.tts.ui).
    Mini.setReady(false)
    Setup.setReady(false)
    local panels = Mini.panels(Rules)
    panels[#panels + 1] = Setup.panel()
    Hud.build(Rules, panels, Track.tile(), function()
        applyModMenuButton()
        Mini.setReady()
        Setup.setReady()
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

function onPlayerConnect(player)
    rebuildUiSoon()
    -- TTS seats a newcomer in a free colour of its choosing. Before the
    -- start they are moved to the spectators instead, to pick their own:
    -- picking a seat is what deals them in.
    local id = player and player.steam_id
    if id then
        joining[id] = true
        Wait.time(function() bench(id) end, 0.5)
    end
end

-- The rebuild also brings the setup menu's list of who is seated up to date.
function onPlayerChangeColor(color)
    rebuildUiSoon()
end

--- A driver who drops out leaves their car where it is, and once the seat
-- is empty its dashboard offers "Drive this car" (see fdDashTakeOver).
function onPlayerDisconnect()
    Wait.time(function() refresh() end, 0.5)
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
    local memoryBagModMenu = getObjectFromGUID(MOD_MENU_BAG)
    if memoryBagModMenu then
        memoryBagModMenu.call("buttonClick_place", {})
    end
    mod_packed = false
    applyModMenuButton()
end

-- Plumbing ------------------------------------------------------------------

local function tintOf(color)
    return Color.fromString(color)
end

local function relay(events)
    for _, e in ipairs(events) do
        local rgb = LEVEL_RGB[e.level] or LEVEL_RGB.info
        if e.level == "roll" and SEATS[e.color] then
            rgb = tintOf(e.color)
        end
        if e.level == "wear" or e.level == "out" or e.level == "finish" then
            broadcastToAll(e.text, rgb)
        else
            printToAll(e.text, rgb)
            if e.level == "warn" and e.color and Player[e.color] and Player[e.color].seated then
                broadcastToColor(e.text, e.color, rgb)
            end
        end
    end
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
        parts[#parts + 1] = race:progress(car)
        if not car.place then
            parts[#parts + 1] = car.gear > 0 and (Race.gearName(car.gear) .. " gear") or "on the grid"
            parts[#parts + 1] = Hud.wearSummary(race, car)
            if car.lastRoll then
                parts[#parts + 1] = "rolled " .. car.lastRoll
            end
        end
    end
    if race:turn() == car then
        parts[#parts + 1] = "YOUR TURN"
    end
    if not (car.tts.car and getObjectFromGUID(car.tts.car)) then
        parts[#parts + 1] = "no car -- press Car"
    end
    for _, c in ipairs(race:pendingChecks()) do
        -- A start waiting for its turn is rolled then, by the script.
        if c.color == car.color and c.kind ~= "start" then
            parts[#parts + 1] = "ROLL BLACK DIE (" .. race:checkName(c) .. ")"
            break
        end
    end
    return table.concat(parts, "  |  ")
end

--- Whether somebody is sitting in `color`.
local function seatedIn(color)
    local p = Player[color]
    return p ~= nil and p.seated == true
end

local function renderDashboards()
    for _, obj in ipairs(Dashboard.all()) do
        local car = carOnDash(obj.getGUID())
        Controls.render(obj, car, car and dashLabel(car), car and not seatedIn(car.color))
    end
end

-- The car to play, as last shown: the key of the turn its driver was told
-- about, and the guid of the car lit up for it.
local turnTold = nil
local litCar = nil

--- Hand TTS's own turn marker to `due`, in the race's order of play, which
-- changes every round. Nobody can pass a turn from TTS's menu: the race
-- says when a turn is over. Outside a race it is switched off again -- but
-- only if it was switched on here: Turns that were on already (hotseat
-- runs its own) are left alone, as switching them off sets TTS handing the
-- turn round every seat.
--
-- Each part is written only when it changes from what was last written, not
-- from what Turns reads back: TTS does not always read back what it was
-- given, and every turn_color it is given is announced to the table.
local function syncTurns(due)
    local seated = due and Player[due.color] and Player[due.color].seated
    if not seated then
        if turnsSet and turnsSet.on then
            Turns.enable = false
            turnsSet = { on = false }
        end
        return
    end
    local order = {}
    for _, car in ipairs(race:cars()) do
        if not car.eliminated and not car.place and Player[car.color] and Player[car.color].seated then
            order[#order + 1] = car.color
        end
    end
    local key = table.concat(order, " ")
    local was = turnsSet or {}
    if not was.on then
        Turns.type = 2 -- custom order
        Turns.pass_turns = false
        Turns.enable = true
    end
    if was.order ~= key then
        Turns.order = order
    end
    if was.color ~= due.color then
        Turns.turn_color = due.color
    end
    turnsSet = { on = true, order = key, color = due.color }
end

--- Point everyone at the car to play: TTS's turn marker and a highlight on
-- the car. `announce` also tells its driver, once, when the turn passes to
-- them. (Black die rolls are made at once, so nothing else is waited on.)
local function showTurn(announce)
    local due = race:turn()
    local obj = due and due.tts and due.tts.car and getObjectFromGUID(due.tts.car)
    local guid = obj and obj.getGUID() or nil
    if guid ~= litCar then
        local old = litCar and getObjectFromGUID(litCar)
        if old then old.highlightOff() end
        if obj then obj.highlightOn(due.color) end
        litCar = guid
    end
    syncTurns(due)
    local key = due and (race.state.round .. ":" .. due.color)
    if announce and key and key ~= turnTold then
        turnTold = key
        if Player[due.color] and Player[due.color].seated then
            broadcastToColor("Your turn, " .. race:label(due) .. ": shift, roll, then move your car.",
                due.color, LEVEL_RGB.turn)
        end
    end
end

--- Bring every panel up to date. `announce` is for a change made in play:
-- a turn that has passed is announced.
function refresh(announce)
    syncCars()
    Hud.refresh(race)
    Mini.refresh(race)
    -- The map is only looked up while the setup menu shows it.
    local map, seated = nil, nil
    if Setup.shows(race.state.phase) then
        map = mapOnBoard()
        seated = {}
        for _, color in ipairs(getSeatedPlayers()) do
            local car, p = race:car(color), Player[color]
            if SEATS[color] and not car then
                seated[#seated + 1] = p and p.steam_name or color
            end
        end
    end
    Setup.refresh(race, map and { name = map.name, hasTrack = TRACKS[map.id] ~= nil }, seated)
    renderDashboards()
    showTurn(announce)
    applyModMenuButton()
end

--- Run a change to the race: snapshot for undo, apply, then publish.
local function act(fn)
    undo[#undo + 1] = JSON.encode(race:serialize())
    if #undo > UNDO_LIMIT then
        table.remove(undo, 1)
    end
    fn()
    race:rollChecks(rollBlack)
    if race.gridSettled then
        race.gridSettled = nil
        placeOnGrid()
    end
    local opened = race.opened
    race.opened = nil
    relay(race:drain())
    syncDashboards()
    refresh(true)
    if opened then
        showReach(opened)
    end
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

--- Which way is across the table from `pos` towards its middle (x, z), or
-- nil right at the middle.
local function inward(pos)
    local len = math.sqrt(pos.x ^ 2 + pos.z ^ 2)
    if len < 1 then
        return nil
    end
    return -pos.x / len, -pos.z / len
end

-- Height to drop a fresh piece from: just above the table. Hand zones sit
-- below it, so a seat's own height will not do.
local DROP_Y = 3

--- Where a car from the bag goes: to the right of its driver's dashboard as
-- they face the table, or in front of their seat if they have none.
local function carSpot(car)
    local dash = car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)
    if dash then
        local p = dash.getPosition()
        local ix, iz = inward(p)
        ix, iz = ix or 0, iz or 1
        return { x = p.x + iz * 7, y = p.y + 2, z = p.z - ix * 7 }
    end
    local hand = handPosition(car.color)
    if not hand then
        return nil
    end
    local ix, iz = inward(hand)
    ix, iz = ix or 0, iz or 0
    return { x = hand.x + ix * 8, y = DROP_Y, z = hand.z + iz * 8 }
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

--- Read gear die `obj` for `gear` once it settles, as rolled by `color`.
local function watchGearDie(obj, color, gear)
    Dice.watch(obj, color, function(value, roller)
        if value then
            clearReach()
            act(function() race:rolled(ownerOf(roller, gear), gear, value) end)
        end
    end)
end

function onObjectRandomize(obj, color)
    local gear = Dice.gearOf(obj)
    if gear then
        watchGearDie(obj, color, gear)
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
    -- A car that is due stays lit (see showTurn); a timed highlight would end that.
    if race:turn() ~= car then
        obj.highlightOn(car.color, 4)
    end
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
    -- A shift starts somebody's turn: the last move's options are done with.
    clearReach()
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
            -- undoable, and the dashboards show the result. Put down after
            -- its roll, the car's turn is over.
            act(function()
                race:placed(owner.color, space and space.id, track)
                race:putDown(owner.color)
            end)
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
            if race:turn() ~= car then
                mine.highlightOn(car.color, 4)
            end
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
        local spot = carSpot(car)
        if not bag or not spot then
            race:emit("warn", race:label(car) .. " has no car nearby -- take one from a car bag", car.color)
            return
        end
        local spawned = bag.takeObject({ position = spot, rotation = { x = 0, y = 0, z = 0 }, smooth = false })
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

--- Put `color` in the race at dashboard `dash`, with no car yet: the first
-- half of dealing them in. On no button -- Start race deals everybody in --
-- but global, so the tests can seat a driver at a given dashboard.
function joinRace(color, dash)
    if not SEATS[color] or race:car(color) or carOnDash(dash.getGUID()) then
        return
    end
    act(function() joinAt(dash, color) end)
end

--- Put `color` in the race at dashboard `dash`. Called inside act.
joinAt = function(dash, color)
    local car = race:join(color, Player[color] and Player[color].steam_name)
    car.tts = car.tts or {}
    car.tts.dash = dash.getGUID()
    car.tts.faceWarned = nil
    -- Who drives it, so they can be put back in it if they drop out.
    car.tts.steam = Player[color] and Player[color].steam_id
    return car
end

-- Delivery ------------------------------------------------------------------
-- When the host presses Start race, everybody seated is dealt in: a
-- dashboard in front of their seat -- a free one already there, or a fresh
-- one from the bag for the ruleset's face -- and a car beside it. Leave
-- takes them out again.

local DASHBOARD_BAGS = { beginner = "edfadc", advanced = "4eb678" }
-- A free dashboard this close to a seat's hand zone is that seat's.
local SEAT_RANGE = 12
-- How far in front of the hand zone a fresh dashboard goes.
local DASH_AHEAD = 3.5

local delivering = {}  -- colour -> true while their dashboard is on its way

local function dealIn(color, dash)
    delivering[color] = nil
    if race:car(color) or carOnDash(dash.getGUID()) then
        return
    end
    act(function()
        local car = joinAt(dash, color)
        race:emit("info", race:label(car) .. " is dealt in", color)
        ACTIONS.car(car)
    end)
end

--- Deal `color` in, if they are seated, picked the seat themselves, are not
-- racing yet, and the race has not started.
deliver = function(color)
    local p = Player[color]
    if not SEATS[color] or not (p and p.seated) or delivering[color] or race:car(color)
        or race.state.phase ~= "setup" or joining[p.steam_id or ""] then
        return
    end
    local hand = p.getHandTransform()
    if not hand then
        return
    end
    local taken = {}
    for _, c in ipairs(race:cars()) do
        if c.tts and c.tts.dash then taken[c.tts.dash] = true end
    end
    local near = Dashboard.nearest(hand.position, taken)
    if near then
        local q = near.getPosition()
        if (q.x - hand.position.x) ^ 2 + (q.z - hand.position.z) ^ 2 <= SEAT_RANGE * SEAT_RANGE then
            dealIn(color, near)
            return
        end
    end
    local face = Dashboard.faceFor(Rules)
    local bag = getObjectFromGUID(DASHBOARD_BAGS[face])
    if not bag then
        return
    end
    -- Straight ahead of the seat, the way its hand zone faces.
    local yaw = hand.rotation and hand.rotation.y or 0
    local ix, iz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
    delivering[color] = true
    -- Should the bag never hand it over, the seat is not held up for good;
    -- dealIn checks again, so a late arrival does no harm.
    Wait.time(function() delivering[color] = nil end, 10)
    bag.takeObject({
        position = { x = hand.position.x + ix * DASH_AHEAD, y = DROP_Y, z = hand.position.z + iz * DASH_AHEAD },
        -- Turned to face the seat; the beginner face is the underside.
        rotation = { x = 0, y = yaw, z = face == "beginner" and 180 or 0 },
        smooth = false,
        callback_function = function(dash)
            Dashboard.track(dash)
            dealIn(color, dash)
        end,
    })
end

--- Before the start, a car whose dashboard is gone -- deleted, or put away
-- in a bag -- leaves the race, so its seat can be dealt in afresh.
dropDashless = function()
    if race.state.phase ~= "setup" then
        return
    end
    for _, car in ipairs(race:cars()) do
        if not (car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)) then
            act(function() ACTIONS.leave(car) end)
        end
    end
end

--- Whether every car's object is out of its bag and done spawning, so it
-- can be put on the grid.
local function carsReady()
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        if obj and obj.spawning then
            return false
        end
    end
    return true
end

--- Deal in everybody seated who is not racing yet, then call `onDone` once
-- their dashboards and cars are on the table. A dashboard the bag never hands
-- over stops holding things up after a while (see deliver).
dealInSeated = function(onDone)
    dropDashless()
    for _, color in ipairs(getSeatedPlayers()) do
        deliver(color)
    end
    Wait.condition(function()
        Wait.condition(onDone, carsReady, 5, onDone)
    end, function() return next(delivering) == nil end, 12, onDone)
end

--- The car driven by the player with steam id `id`, if any.
local function carOf(id)
    for _, car in ipairs(race:cars()) do
        if car.tts and car.tts.steam == id then
            return car
        end
    end
    return nil
end

--- Sort out the seat TTS gave the player with steam id `id`, who has just
-- connected. A driver back from a dropped connection goes back to their own
-- car's colour. Anybody else sitting in a colour with a car in the race --
-- one whose driver is away -- is moved to the spectators, as is anybody in a
-- coloured seat before the start: they pick their own seat. Looked up
-- afresh: they may have left again already.
bench = function(id)
    joining[id] = nil
    local player = nil
    for _, p in ipairs(getPlayers()) do
        if p.steam_id == id then player = p end
    end
    if not player then
        return
    end
    local color = player.color
    local mine = carOf(id)
    if mine then
        if mine.color == color then
            return
        end
        if seatedIn(mine.color) then
            player.broadcast("Somebody is sitting in your " .. mine.color
                .. " seat: once they move, click Drive this car on your dashboard.", LEVEL_RGB.warn)
            return
        end
        player.changeColor(mine.color)
        printToAll(race:label(mine) .. " is back in the " .. mine.color .. " car", LEVEL_RGB.info)
        return
    end
    if not SEATS[color] then
        return
    end
    local there = race:car(color)
    if there then
        player.changeColor("Grey")
        player.broadcast(race:label(there) .. "'s car is waiting for its driver. To drive it instead, click Drive this car on its dashboard.",
            LEVEL_RGB.info)
    elseif race.state.phase == "setup" then
        player.changeColor("Grey")
        player.broadcast("Pick a colour to race in: you get a dashboard and a car when the race starts.", LEVEL_RGB.info)
    end
end

--- "Drive this car", on the dashboard of a car whose driver has left their
-- seat: seat whoever clicks in its colour. Its driver coming back gets their
-- car again; anybody else takes it over, and drives it under their name.
function fdDashTakeOver(dash, color)
    local car = carOnDash(dash.getGUID())
    local p = Player[color]
    if not car or not p or seatedIn(car.color) then
        return
    end
    local driving = race:car(color)
    if driving then
        broadcastToColor("You are driving the " .. driving.color .. " car already.", color, LEVEL_RGB.warn)
        return
    end
    local back = car.tts.steam == p.steam_id
    act(function()
        car.tts.steam = p.steam_id
        car.name = p.steam_name
        race:emit("info", back and (race:label(car) .. " is back in the " .. car.color .. " car")
            or (race:label(car) .. " takes over the " .. car.color .. " car"), car.color)
    end)
    p.changeColor(car.color)
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

--- Roll the gear die for the player's gear, fetching it first if it is
-- elsewhere: the same die, read the same way, as throwing it by hand.
function fdUiRoll(player)
    local car = mine(player)
    if not car then
        return
    end
    if car.gear == 0 then
        broadcastToColor("Shift into a gear first: click one on your dashboard.", player.color, LEVEL_RGB.warn)
        return
    end
    local pos = dicePosition(player.color)
    local die = pos and Dice.bring(car.gear, pos, player.color) or Dice.find(car.gear)
    if not die then
        broadcastToColor("The " .. Race.gearName(car.gear) .. " gear die is not on the table.", player.color, LEVEL_RGB.warn)
        return
    end
    if die.held_by_color then
        broadcastToColor("Someone is holding the " .. Race.gearName(car.gear) .. " gear die.", player.color, LEVEL_RGB.warn)
        return
    end
    local gear = car.gear
    Wait.condition(function()
        if die == nil then return end
        die.roll()
        watchGearDie(die, player.color, gear)
    end, function() return die == nil or not die.isSmoothMoving() end, 5, function()
        broadcastToColor("The " .. Race.gearName(gear) .. " gear die did not arrive -- click Roll again.",
            player.color, LEVEL_RGB.warn)
    end)
end

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
-- The race-wide controls belong to the host and promoted players. The panel
-- only shows them to those players; the check here covers a click that got
-- through anyway, and the editor's keys and menus, which anyone can reach.

--- Whether `player` may use the race controls. `player` is a TTS Player, or
-- just a colour as the hotkeys and context menus give it.
local function isAdmin(player)
    if player.admin ~= nil then
        return player.admin
    end
    local p = Player[player.color]
    return p and p.admin or false
end

local function admin(player)
    if isAdmin(player) then
        return true
    end
    broadcastToColor("Only the host or a promoted player can use the race controls.", player.color, LEVEL_RGB.warn)
    return false
end

--- The grid is rolled for everybody, on a black die of the script's own:
-- nobody has to wait their turn with the one on the table.
function fdGrid(player)
    if not admin(player) then return end
    printToAll(player.steam_name .. " calls the grid roll", LEVEL_RGB.info)
    act(function() race:rollForGrid(rollBlack) end)
end

local function startRace(player)
    printToAll(player.steam_name .. " starts the race", LEVEL_RGB.info)
    clearReach()
    packTable()
    act(function() race:startRace() end)
    -- Packing the setup board sweeps up the loose dice with it: once it has,
    -- put out again whatever is missing.
    Wait.time(function()
        Dice.ensureAll(function(n)
            if n > 0 then
                printToAll(string.format("Put %d dice out for the race", n), LEVEL_RGB.info)
            end
        end)
    end, 1)
end

function fdStart(player)
    if not admin(player) then return end
    startRace(player)
end

--- The players in coloured seats.
local function seatedColors()
    local out = {}
    for _, color in ipairs(getSeatedPlayers()) do
        if SEATS[color] then out[#out + 1] = color end
    end
    return out
end

local starting = false -- Start race is dealing players in

--- Start race, on the setup menu: deal in everybody seated, roll the grid
-- and start, after a reset if the last race is over. The grid roll settles
-- its own ties, so the race only waits if it could not. (fdGrid and fdStart
-- are the last two steps, still callable on their own.)
function fdSetupStart(player)
    if not admin(player) or starting then return end
    if race.state.phase == "race" then
        return
    end
    if #race:cars() == 0 and #seatedColors() == 0 then
        broadcastToColor("Nobody is seated yet: players join by taking a coloured seat.", player.color, LEVEL_RGB.warn)
        return
    end
    if race.state.phase == "finished" then
        clearReach()
        act(function() race:reset() end)
    end
    starting = true
    dealInSeated(function()
        starting = false
        if race.state.phase == "race" then
            return
        end
        printToAll(player.steam_name .. " calls the grid roll", LEVEL_RGB.info)
        act(function() race:rollForGrid(rollBlack) end)
        if race.state.phase ~= "setup" then
            broadcastToColor("The grid is not settled yet -- press Start race again.", player.color, LEVEL_RGB.warn)
            return
        end
        startRace(player)
    end)
end

--- The race distance buttons on the setup menu.
function fdSetupLaps(player, value)
    if not admin(player) then return end
    local laps = tonumber(value)
    if not laps or laps == race:serialize().laps then
        return
    end
    printToAll(player.steam_name .. " sets the race distance", LEVEL_RGB.info)
    act(function() race:setLaps(laps) end)
end

--- The Big Box menu put a new map on the board. Reloading the tile took
-- the race panel with it, so it is drawn again; the setup menu says which
-- map it is, and turn order goes by its track.
function fdMapChanged()
    useBoardTrack()
    buildUi()
end

function fdReset(player)
    if not admin(player) then return end
    printToAll(player.steam_name .. " reset the race (Undo restores it)", LEVEL_RGB.info)
    clearReach()
    act(function() race:reset() end)
end

function fdUndo(player)
    if not admin(player) then return end
    local last = table.remove(undo)
    if not last then
        broadcastToColor("Nothing to undo.", player.color, LEVEL_RGB.info)
        return
    end
    race = Race.new(Rules, JSON.decode(last))
    race.autoRolls = true
    useBoardTrack()
    clearReach()
    -- Undo puts the race back, not the pieces: the board still says where
    -- the cars are.
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        race:placed(car.color, obj and spaceUnder(obj))
    end
    race:drain() -- re-reading the board is not news
    printToAll(player.steam_name .. " undid the last change", LEVEL_RGB.info)
    -- In case the state undone to has a roll waiting: it is rolled now.
    race:rollChecks(rollBlack)
    relay(race:drain())
    syncDashboards(true)
    refresh()
end


-- Track overlay and editor -------------------------------------------------------

local trackShown = nil

--- The track data for the map on the board, if there is any.
local function trackOnBoard()
    local map = mapOnBoard()
    return map and TRACKS[map.id]
end

local function editorStatus()
    if not Editor.isOpen() then
        Setup.setEditor(nil)
        return
    end
    local track = Editor.trackFor(TRACKS[Editor.openId()])
    local _, problems = Editor.problems()
    Setup.setEditor(string.format("Editing %s: %d spaces, %d problem(s) shown red, %d marker(s) out, %d on the grid",
        track.name, #track.spaces, #problems, Editor.markerCount(), Editor.gridCount()))
end

--- Draw the spaces over the board, to check them against the print.
function fdTrack(player)
    if not admin(player) then return end
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
--- The board tile and the track data for the map on it (with any edits
-- made in the editor), or nil if there is none.
local function boardTrack()
    local tile = Track.tile()
    local track = tile and trackOnBoard()
    if not track then
        return nil
    end
    return tile, Editor.trackFor(track)
end

--- Tell the race which track the cars are on, for turn order: after a load
-- or an undo, before any car has been put down on it.
useBoardTrack = function()
    local _, track = boardTrack()
    race:useTrack(track)
end

--- Set a car down at `pos` (on the board face), level and turned to `yaw`.
local function setDown(obj, pos, yaw)
    obj.setPositionSmooth({ x = pos.x, y = pos.y + SNAP_LIFT, z = pos.z }, false, true)
    -- The car models' noses point along their local +Z.
    obj.setRotationSmooth({ x = 0, y = yaw, z = 0 }, false, true)
end

snapCar = function(obj)
    local tile, track = boardTrack()
    if not track then
        return nil
    end
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
    setDown(obj, pos, yaw)
    return space, track
end

--- Once the grid roll has settled the order, set each claimed car down on
-- its grid space, pole first. Called inside act, so the race notes where
-- they went. A car with no grid space, or no car to move, is left to the
-- players, with a word as to why.
placeOnGrid = function()
    local tile, track = boardTrack()
    local start = track and track.start or {}
    if #start == 0 then
        race:emit("warn", "No starting grid known for the map on the board -- put the cars on the grid by hand")
        return
    end
    race:useTrack(track)
    local f = Track.frame(tile, track)
    for i, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        local pos, yaw = nil, nil
        if start[i] then
            pos, yaw = Track.seat(tile, f, track, start[i])
        end
        if not obj then
            race:emit("warn", race:label(car) .. " has no car to put on the grid -- press Car", car.color)
        elseif not pos then
            race:emit("warn", string.format("%s starts in place %d, but the grid has only %d -- put the car down by hand",
                race:label(car), i, #start), car.color)
        else
            setDown(obj, pos, yaw)
            race:placed(car.color, start[i])
        end
    end
end

--- The id of the space a car is sitting on, without moving it; nil if it is
-- off the track or there is no track data for the board.
spaceUnder = function(obj)
    local tile, track = boardTrack()
    if not track then
        return nil
    end
    local s = Track.spaceNear(tile, Track.frame(tile, track), track, obj.getPosition(), ON_SPACE)
    return s and s.id
end

--- Mark where the car of `color` can end the move it has just opened: a
-- green ring for the full roll, amber dots for braking, orange for an
-- overshoot and red for going out. Advisory: nothing stops a car going
-- anywhere else.
showReach = function(color)
    local tile, track = boardTrack()
    local reach = track and race:reachable(color, track)
    if not reach then
        clearReach()
        return
    end
    local from = race:car(color).move.from
    local marks = {}
    for id, o in pairs(reach) do
        if id ~= from then
            local kind = "free"
            if race:moveOut(o) then
                kind = "out"
            elseif o.overshoot > 0 then
                kind = "overshoot"
            elseif o.brake > 0 then
                kind = "brake"
            end
            marks[#marks + 1] = { id = id, kind = kind }
        end
    end
    Track.setLayer("reach", Track.marks(tile, track, marks))
end

clearReach = function()
    Track.setLayer("reach", nil)
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
    local function item(label, fn)
        tile.addContextMenuItem(label, function(color, pos)
            if admin({ color = color }) then fn(color, pos) end
        end)
    end
    item("Pick up spaces here", pickUpAt)
    item("Add a space here", addAt)
    item("Apply track edits", function(color) fdApply({ color = color }) end)
    item("Clear the grid", function(color)
        broadcastToColor(Editor.clearGrid(), color, LEVEL_RGB.info)
        editorStatus()
    end)
end

--- Open or close the track editor for the map on the board.
function fdEdit(player)
    if not admin(player) then return end
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
    if not admin(player) then return end
    if not Editor.isOpen() then
        return
    end
    local n = Editor.apply()
    editorStatus()
    printToAll(string.format("Applied %d marker(s); links recomputed.", n), LEVEL_RGB.info)
end

--- Getting edits out of the game and into the repo.
function fdExport(player)
    if not admin(player) then return end
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
        if up or not admin({ color = color }) then return end
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
    -- Pressed on each grid space in turn, pole first; again on one takes it off.
    addHotkey("Track editor: mark grid space", editorKey(function(color, hovered, pointer)
        broadcastToColor(Editor.gridKey(hovered, pointer), color, LEVEL_RGB.info)
    end))
end

function onObjectDestroy(obj)
    Dashboard.forget(obj)
    -- A driver's dashboard deleted before the start takes them out of the race.
    local driver = race and race.state.phase == "setup" and carOnDash(obj.getGUID())
    if driver then
        runAction(driver, "leave")
    end
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
