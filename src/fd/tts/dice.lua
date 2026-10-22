-- The shared dice set: finding the gear dice, teaching them their faces, moving
-- the right one to whoever shifts, and reading results once a roll settles.

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

--- Move a gear die to `pos` and highlight it for `color`. Leaves a die alone
-- while someone is holding it.
function Dice.bring(gear, pos, color)
    local die = Dice.find(gear)
    if not die then
        return nil
    end
    if not die.held_by_color then
        die.setPositionSmooth(pos, false, true)
    end
    die.highlightOn(color, 4)
    return die
end

-- Fetching the set --------------------------------------------------------------

-- The setup board's memory bag keeps the loose dice with the board, so
-- packing the board away takes them too; the Dice Set Bag hands out a spare
-- set, in a bag of its own.
local SETUP_BAG = "0fde3b"
local DICE_SET_BAG = "ac4939"

-- Where a fetched die is set down: the row the setup board lays them out in,
-- gears 1 to 6, then the black die.
local HOME = {
    { 57.6, -13.7 }, { 60.9, -13.7 }, { 63.6, -13.7 }, { 66.7, -13.7 }, { 69.9, -13.7 }, { 72.7, -13.7 },
    { 72.2, -10.8 },
}
local DROP_Y = 3

local function allNames()
    local out = {}
    for i, n in ipairs(DiceData.names) do out[i] = n end
    out[#out + 1] = Dice.BLACK_DIE
    return out
end

--- Take whichever of `missing` (name -> home index) `bag` holds, setting each
-- down at home. Returns how many came out.
local function takeFrom(bag, missing)
    local n = 0
    for _, item in ipairs(bag.getObjects()) do
        local home = HOME[missing[item.name] or 0]
        if home then
            missing[item.name] = nil
            bag.takeObject({
                guid = item.guid, position = { x = home[1], y = DROP_Y, z = home[2] }, smooth = false,
                callback_function = function(obj) Dice.prepare(obj) end,
            })
            n = n + 1
        end
    end
    return n
end

--- Make sure all seven dice are out on the table, fetching any that are not:
-- from the setup board's bag, else from a spare set. `onDone(n)` is told how
-- many were fetched, once they are.
function Dice.ensureAll(onDone)
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
    local fetched = setup and takeFrom(setup, missing) or 0
    local spare = fetched < count and getObjectFromGUID(DICE_SET_BAG)
    if not spare then
        return onDone(fetched)
    end
    -- The infinite bag hands out a whole set in a bag: take what is still
    -- missing and put the rest away.
    spare.takeObject({
        position = { x = HOME[7][1] + 5, y = DROP_Y, z = HOME[7][2] }, smooth = false,
        callback_function = function(set)
            fetched = fetched + takeFrom(set, missing)
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
