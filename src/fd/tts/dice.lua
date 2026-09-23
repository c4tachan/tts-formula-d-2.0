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
