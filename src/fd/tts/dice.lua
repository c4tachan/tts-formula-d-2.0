-- The shared dice set: finding the dice, teaching the gear dice their faces,
-- keeping them in a row in the middle of the board, and rolling them there.
-- A die thrown by hand anyway (only the host can unlock one) is still read
-- once it settles (Dice.watch).

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

-- The dice sit in a row in the middle of the board, locked and out of
-- players' hands: they are rolled with the Roll button only (Dice.roll),
-- which turns a face up rather than throwing the die, so nothing tumbles into
-- the cars on the track.

local SPACING = 2.2 -- world units between neighbouring dice
local LIFT = 0.6    -- above the board face, so a die sits on it

--- Where die `i` of the row (gears 1 to 6, then the black die) goes, in a
-- row centred on `center`, the middle of the board face.
local function spot(i, center)
    return { x = center.x + (i - 4) * SPACING, y = center.y + LIFT, z = center.z }
end

--- Lock `obj` at `pos`, where players cannot pick it up.
local function fix(obj, pos)
    obj.interactable = false
    obj.setLock(true)
    obj.setPosition(pos)
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

--- Put the dice that are out in their row at `center`.
function Dice.layout(center)
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

--- Roll the die for `gear` where it sits: a face picked at random and turned
-- up. Returns the value it shows and the die, or nil if the die is not out.
function Dice.roll(gear)
    local die = Dice.find(gear)
    local faces = DiceData[gear]
    if not die or not faces then
        return nil
    end
    local face = faces[math.random(#faces)]
    die.setRotationSmooth(face.rotation, false, true)
    return face.value, die
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
