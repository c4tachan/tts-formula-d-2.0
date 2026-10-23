-- The shared dice set: finding the dice, teaching the gear dice their faces,
-- keeping them in a walled tray on the board, rolling them there, and reading
-- a die once it settles (Dice.watch).

local DiceData = require("fd.data.dice")

local Dice = {}

Dice.BLACK_DIE = "Damage Dice"

local gearByName = {}
for gear, name in ipairs(DiceData.names) do
    gearByName[name] = gear
end

--- Gear a die belongs to, or nil if `obj` is not a gear die.
function Dice.gearOf(obj)
    return gearByName[obj.getName()]
end

function Dice.isBlack(obj)
    return obj.getName() == Dice.BLACK_DIE
end

-- GUID of each gear die, found as they are prepared, so finding one does not
-- mean scanning every object on the table.
local known = {}

--- Give a gear die its rotation values. The models ship without any, so TTS
-- cannot read them until this runs; it is idempotent and cheap.
function Dice.prepare(obj)
    local gear = Dice.gearOf(obj)
    if gear then
        obj.setRotationValues(DiceData[gear])
        known[gear] = obj.getGUID()
    end
end

function Dice.prepareAll()
    for _, obj in ipairs(getObjects()) do
        Dice.prepare(obj)
    end
end

function Dice.find(gear)
    local obj = known[gear] and getObjectFromGUID(known[gear])
    if obj then
        return obj
    end
    -- Not seen yet, or put back in its bag and taken out again: look for it.
    local name = DiceData.names[gear]
    for _, o in ipairs(getObjects()) do
        if o.getName() == name then
            known[gear] = o.getGUID()
            return o
        end
    end
    return nil
end

-- The dice sit in rows in a tray on the board, out of players' hands: they
-- cannot be picked up, only thrown with the Roll button (Dice.throw). Four
-- low walls round them keep a throw from tumbling into the cars.

local SPACING = 2.2 -- world units between neighbouring dice
local LIFT = 0.6    -- above the board face, so a die sits on it
-- Two rows, to fit on a map's name panel: gears 1 to 4, then 5, 6 and the
-- black die.
local ROWS = { { 1, 2, 3, 4 }, { 5, 6, 7 } }

--- Where die `i` (gears 1 to 6, then the black die) goes, in the rows
-- centred on `center`, a point on the board face.
local function spot(i, center)
    for r, row in ipairs(ROWS) do
        for k, n in ipairs(row) do
            if n == i then
                return {
                    x = center.x + (k - (#row + 1) / 2) * SPACING,
                    y = center.y + LIFT,
                    z = center.z + (r - (#ROWS + 1) / 2) * SPACING,
                }
            end
        end
    end
    -- Past the end of the rows: beside the first.
    return { x = center.x + (i - 1) * SPACING, y = center.y + LIFT, z = center.z - SPACING }
end

--- Set die `obj` down at `pos`, where players cannot pick it up. It is left
-- unlocked, to roll.
local function fix(obj, pos)
    obj.interactable = false
    obj.setLock(false)
    obj.setPosition(pos)
end

-- The tray: its inside, and its walls. Spawned afresh wherever the dice are
-- laid out, and found again by name after a load.
local TRAY = "Dice tray"
local TRAY_WIDTH = 11   -- inside, world units: room for the rows and a throw
local TRAY_DEPTH = 7
local WALL_HEIGHT = 2     -- a throw goes up a little way: high enough to keep it in
local WALL_THICKNESS = 0.3
local TRAY_TINT = { 0.12, 0.13, 0.15 }

local trayGuids = nil -- the walls put out, once known

local function clearTray()
    if not trayGuids then
        trayGuids = {}
        for _, o in ipairs(getObjects()) do
            if o.getName() == TRAY then trayGuids[#trayGuids + 1] = o.getGUID() end
        end
    end
    for _, g in ipairs(trayGuids) do
        local o = getObjectFromGUID(g)
        if o then o.destruct() end
    end
    trayGuids = {}
end

--- One wall, centred on `pos`, `size` across in world units. The block's own
-- size is only known once it is out, so it is scaled to fit then.
local function wall(pos, size)
    local obj = spawnObject({
        type = "BlockRectangle", position = pos, sound = false,
        callback_function = function(o)
            local s = o.getBoundsNormalized().size
            o.setScale({ size.x / s.x, size.y / s.y, size.z / s.z })
            o.setName(TRAY)
            o.setColorTint(TRAY_TINT)
            o.setLock(true)
            o.interactable = false
        end,
    })
    trayGuids[#trayGuids + 1] = obj.getGUID()
end

--- Four walls round the rows at `center`, standing on the board face.
function Dice.tray(center)
    clearTray()
    local y = center.y + WALL_HEIGHT / 2
    local w, d, t = TRAY_WIDTH, TRAY_DEPTH, WALL_THICKNESS
    wall({ x = center.x, y = y, z = center.z - (d + t) / 2 }, { x = w + 2 * t, y = WALL_HEIGHT, z = t })
    wall({ x = center.x, y = y, z = center.z + (d + t) / 2 }, { x = w + 2 * t, y = WALL_HEIGHT, z = t })
    wall({ x = center.x - (w + t) / 2, y = y, z = center.z }, { x = t, y = WALL_HEIGHT, z = d })
    wall({ x = center.x + (w + t) / 2, y = y, z = center.z }, { x = t, y = WALL_HEIGHT, z = d })
end

local function findBlack()
    local obj = known.black and getObjectFromGUID(known.black)
    if obj then
        return obj
    end
    for _, o in ipairs(getObjects()) do
        if Dice.isBlack(o) then
            known.black = o.getGUID()
            return o
        end
    end
    return nil
end

local function allNames()
    local out = {}
    for i, n in ipairs(DiceData.names) do out[i] = n end
    out[#out + 1] = Dice.BLACK_DIE
    return out
end

--- Put the dice that are out in their rows at `center`, in a tray.
function Dice.layout(center)
    Dice.tray(center)
    for i in ipairs(allNames()) do
        local obj = nil
        if i <= #DiceData.names then
            obj = Dice.find(i)
        else
            obj = findBlack()
        end
        if obj then
            fix(obj, spot(i, center))
        end
    end
end

--- Light up the die for `gear` for `color`, who has just shifted into it.
function Dice.highlight(gear, color)
    local die = Dice.find(gear)
    if die then
        die.highlightOn(color, 4)
    end
    return die
end

--- Throw the die for `gear` in the tray. Returns the die, or nil if it is
-- not out; read it with Dice.watch.
function Dice.throw(gear)
    local die = Dice.find(gear)
    if die then
        die.roll()
    end
    return die
end

--- Turn the black die to show `value`, rolled by the script.
function Dice.showBlack(value)
    local die = findBlack()
    if die then
        die.setRotationValue(value)
    end
end

-- Fetching the set --------------------------------------------------------------

-- The setup board's memory bag keeps the loose dice with the board, so
-- packing the board away takes them too; the Dice Set Bag hands out a spare
-- set, in a bag of its own.
local SETUP_BAG = "0fde3b"
local DICE_SET_BAG = "ac4939"

--- Take whichever of `missing` (name -> place in the row) `bag` holds,
-- setting each down in its place in the row at `center`. Returns how many
-- came out.
local function takeFrom(bag, missing, center)
    local n = 0
    for _, item in ipairs(bag.getObjects()) do
        local i = missing[item.name]
        if i then
            missing[item.name] = nil
            local pos = spot(i, center)
            bag.takeObject({
                guid = item.guid, position = pos, smooth = false,
                callback_function = function(obj)
                    Dice.prepare(obj)
                    fix(obj, pos)
                end,
            })
            n = n + 1
        end
    end
    return n
end

--- Make sure all seven dice are out, in their row at `center`, fetching any
-- that are not: from the setup board's bag, else from a spare set.
-- `onDone(n)` is told how many were fetched, once they are.
function Dice.setOut(center, onDone)
    Dice.layout(center)
    local onTable = {}
    for _, o in ipairs(getObjects()) do onTable[o.getName()] = true end
    local missing, count = {}, 0
    for i, name in ipairs(allNames()) do
        if not onTable[name] then missing[name] = i count = count + 1 end
    end
    if count == 0 then
        return onDone(0)
    end
    local setup = getObjectFromGUID(SETUP_BAG)
    local fetched = setup and takeFrom(setup, missing, center) or 0
    local spare = fetched < count and getObjectFromGUID(DICE_SET_BAG)
    if not spare then
        return onDone(fetched)
    end
    -- The infinite bag hands out a whole set in a bag: take what is still
    -- missing and put the rest away.
    local beside = spot(#DiceData.names + 3, center)
    spare.takeObject({
        position = { x = beside.x, y = beside.y + 3, z = beside.z }, smooth = false,
        callback_function = function(set)
            fetched = fetched + takeFrom(set, missing, center)
            set.destruct()
            onDone(fetched)
        end,
    })
end

local watching = {}

--- Call onResult(value, color) once a rolled die comes to rest. Rolling fires
-- the randomize event repeatedly while a die is shaken, so a die already being
-- watched just updates who rolled it.
function Dice.watch(obj, color, onResult)
    local guid = obj.getGUID()
    if watching[guid] then
        watching[guid].color = color
        return
    end
    watching[guid] = { color = color }
    local function settled()
        return obj == nil or (obj.resting and not obj.held_by_color)
    end
    local function report()
        local w = watching[guid]
        watching[guid] = nil
        if obj ~= nil and w then
            -- getValue() is the index of the face that is up, not what is
            -- printed on it: on the 1st gear die, face 4 shows a 2.
            local value = tonumber(obj.getRotationValue())
            if value == nil then
                value = tonumber(obj.getValue())
            end
            onResult(value, w.color)
        end
    end
    -- Give the throw a moment to leave the resting state before waiting on it.
    Wait.time(function()
        Wait.condition(report, settled, 60, function() watching[guid] = nil end)
    end, 0.3)
end

return Dice
