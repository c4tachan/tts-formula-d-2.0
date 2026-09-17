-- A small fake of the TTS scripting API: just enough to run the Global script
-- outside the game and catch wiring mistakes. It does no physics -- dice report
-- whatever value a test assigns them and are always at rest.

local Stub = { log = {}, ui = {}, objects = {} }

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepcopy(x) end
    return out
end

-- JSON round trips are deep copies here; the real encoder is not under test.
JSON = {
    encode = function(t) return { json = deepcopy(t) } end,
    decode = function(s) return deepcopy(s.json) end,
}

Wait = {
    condition = function(fn, cond) if cond() then fn() end end,
    frames = function(fn) fn() end,
    time = function(fn) fn() end,
}

UI = {
    loading = false,
    getXmlTable = function() return Stub.xml or {} end,
    setXmlTable = function(t) Stub.xml = t end,
    setAttribute = function(id, k, v)
        Stub.ui[id] = Stub.ui[id] or {}
        Stub.ui[id][k] = v
    end,
    setValue = function(id, v)
        Stub.ui[id] = Stub.ui[id] or {}
        Stub.ui[id].value = v
    end,
    getCustomAssets = function() return Stub.assets end,
    setCustomAssets = function(a) Stub.assets = a end,
}

Stub.assets = {}

Color = { fromString = function(s) return { name = s } end }

local function say(kind)
    return function(msg) Stub.log[#Stub.log + 1] = kind .. ": " .. msg end
end
printToAll = say("print")
broadcastToAll = say("broadcast")
broadcastToColor = say("broadcast")

local guidSeq = 0

function Stub.object(name, props)
    guidSeq = guidSeq + 1
    local o = {
        name = name, guid = string.format("s%05d", guidSeq),
        pos = vec(0, 1, 0), rot = vec(0, 0, 0), up = vec(0, 1, 0),
        resting = true, value = nil,
    }
    for k, v in pairs(props or {}) do o[k] = v end
    o.getName = function() return o.name end
    o.setName = function(n) o.name = n end
    o.getGUID = function() return o.guid end
    o.getPosition = function() return o.pos end
    o.getRotation = function() return o.rot end
    o.getTransformUp = function() return o.up end
    o.positionToWorld = function(p)
        -- Only translation and the Z flip matter for these tests.
        local s = o.up.y >= 0 and 1 or -1
        return vec(o.pos.x + s * p.x, o.pos.y + s * p.y, o.pos.z + p.z)
    end
    o.setPositionSmooth = function(p) o.pos = vec(p.x, p.y, p.z) end
    o.setRotationSmooth = function(r) o.rot = r end
    o.highlightOn = function() end
    o.setColorTint = function(c) o.tint = c end
    o.setRotationValues = function(v) o.rotationValues = v end
    o.getValue = function() return o.value end
    o.buttons = {}
    o.createButton = function(p) o.buttons[#o.buttons + 1] = p end
    o.clearButtons = function() o.buttons = {} end
    o.editButton = function(p)
        for k, v in pairs(p) do o.buttons[p.index + 1][k] = v end
    end
    o.destruct = function()
        for i, x in ipairs(Stub.objects) do
            if x == o then table.remove(Stub.objects, i) break end
        end
    end
    --- Click the button whose click_function is `fn`, as `color`.
    o.click = function(fn, color, alt)
        for _, b in ipairs(o.buttons) do
            if b.click_function == fn then
                return _G[fn](o, color, alt or false)
            end
        end
        error("no button " .. fn .. " on " .. o.name)
    end
    o.takeObject = function(params)
        local spawned = Stub.object(o.spawns, { pos = params.position })
        return spawned
    end
    Stub.objects[#Stub.objects + 1] = o
    return o
end

function getObjects()
    return Stub.objects
end

function getObjectFromGUID(guid)
    for _, o in ipairs(Stub.objects) do
        if o.guid == guid then return o end
    end
    return nil
end

Player = {}
function Stub.player(color, handPos)
    local p = {
        color = color, steam_name = color .. "Player", seated = true,
        getHandTransform = function() return { position = handPos } end,
    }
    Player[color] = p
    return p
end

function Stub.find(name)
    for _, o in ipairs(Stub.objects) do
        if o.name == name then return o end
    end
end

function Stub.count(name)
    local n = 0
    for _, o in ipairs(Stub.objects) do
        if o.name == name then n = n + 1 end
    end
    return n
end

function Stub.logged(pattern)
    for _, line in ipairs(Stub.log) do
        if line:find(pattern) then return true end
    end
    return false
end

Stub.vec = vec

return Stub
