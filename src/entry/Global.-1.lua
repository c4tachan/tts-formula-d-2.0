-- Global script: owns the race and wires TTS events to it.
--
-- The rules live in fd.core.race / fd.rules.*, which make no TTS calls; this
-- file turns clicks, dice and moved pieces into calls on the race, then relays
-- the events it produces and syncs the dashboards and the race panel.
--
-- Each player drives from their dashboard: its buttons (fd.tts.controls) join
-- the race and cover braking, damage and pit stops, the gear stick selects a
-- gear when dropped on a slot, and the WP marker sets WP when dropped on a number.

local Race = require("fd.core.race")
local Rules = require("fd.rules.beginner")
local Dice = require("fd.tts.dice")
local Dashboard = require("fd.tts.dashboard")
local Hud = require("fd.tts.hud")
local Controls = require("fd.tts.controls")
local Mini = require("fd.tts.minidash")

mod_packed = false
setup_packed = false

local race
local syncCars -- defined with the rest of the car handling, below
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
    Mini.registerAsset()
    Hud.build(Rules.name, Mini.panels(Rules), function()
        applyModMenuButton()
        Mini.setReady()
        refresh()
    end)
end

function onSave()
    return JSON.encode({ mp = mod_packed, sp = setup_packed, race = race and race:serialize() })
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

local function syncDashboards()
    for _, car in ipairs(race:cars()) do
        car.tts = car.tts or {}
        local dash = car.tts.dash and getObjectFromGUID(car.tts.dash)
        if dash then
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
    for _, obj in ipairs(getObjects()) do
        if Dashboard.is(obj) then
            local car = carOnDash(obj.getGUID())
            Controls.render(obj, car, car and dashLabel(car))
        end
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
    local match
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
        syncDashboards()
        renderDashboards()
    end, 0.8)
end

function onObjectDrop(color, obj)
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
            syncDashboards() -- same gear or off the gate: settle it back in its slot
        end
    else
        local value = Dashboard.slotAt(dash, kind, pos, WEAR_REACH)
        if value then
            act(function() race:setWear(car.color, kind, value, "marker moved") end)
        else
            syncDashboards()
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
    brake = function(car) race:brake(car.color, 1) end,
    overshoot = function(car) race:overshoot(car.color, 1) end,
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
function fdDashBrake(dash) onDash(dash, "brake") end
function fdDashOvershoot(dash) onDash(dash, "overshoot") end
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
function fdUiBrake(player) runAction(mine(player), "brake") end
function fdUiOvershoot(player) runAction(mine(player), "overshoot") end
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
    printToAll(player.steam_name .. " undid the last change", LEVEL_RGB.info)
    syncDashboards()
    refresh()
end

function fdToggleRace()
    Hud.toggleRace()
end
