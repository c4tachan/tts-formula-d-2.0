-- A small fake of the TTS scripting API: just enough to run the Global script
-- outside the game and catch wiring mistakes. It does no physics -- dice report
-- whatever value a test assigns them and are always at rest.

local Stub = { log = {}, ui = {}, objects = {} }

-- Calls out of Lua, counted for tests/bench.lua: UI updates, object methods,
-- and scans of every object on the table.
Stub.counts = { ui = 0, object = 0, getObjects = 0 }
function Stub.resetCounts()
    Stub.counts = { ui = 0, object = 0, getObjects = 0 }
end

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
    -- Met now, or never: then the timeout, as TTS calls it once it is up.
    condition = function(fn, cond, _, timeout)
        if cond() then fn() elseif timeout then timeout() end
    end,
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

for k, fn in pairs(UI) do
    if type(fn) == "function" then
        UI[k] = function(...)
            Stub.counts.ui = Stub.counts.ui + 1
            return fn(...)
        end
    end
end

-- TTS's turn marker: plain fields, as the game's own are.
Turns = { enable = false, order = {} }

Color = { fromString = function(s) return { name = s } end }

-- Stub.said keeps the colour each message was sent in, by its text.
Stub.said = {}
local function say(kind)
    return function(msg, a, b)
        Stub.log[#Stub.log + 1] = kind .. ": " .. msg
        -- broadcastToColor(msg, color, rgb); the others (msg, rgb).
        Stub.said[msg] = kind == "broadcast" and type(a) == "string" and b or a
    end
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
    o.getScale = function() return o.scale or vec(1, 1, 1) end
    o.getBoundsNormalized = function()
        return { center = o.pos, size = o.size or vec(1, 1, 1), offset = vec(0, 0, 0) }
    end
    o.getCustomObject = function() return o.custom or {} end
    -- A global table of the object's own script, as `tables` has it.
    o.getTable = function(name) return (o.tables or {})[name] end
    o.setCustomObject = function(c) o.custom = c end
    -- Reloading keeps the object, as far as the tests go: TTS spawns it
    -- afresh, under the same guid.
    o.reload = function()
        o.reloads = (o.reloads or 0) + 1
        if onObjectSpawn then onObjectSpawn(o) end
        return o
    end
    o.setVectorLines = function(l) o.lines = l end
    o.getVectorLines = function() return o.lines or {} end
    o.setDecals = function(d) o.decals = d end
    o.getDecals = function() return o.decals end
    o.getTransformUp = function() return o.up end
    o.flip = function() o.up = vec(o.up.x, -o.up.y, o.up.z) end
    -- Local space is scaled like TTS's; rotation is left out apart from the
    -- flip a dashboard takes when turned face down.
    o.positionToWorld = function(p)
        local s = o.up.y >= 0 and 1 or -1
        local k = o.scale or vec(1, 1, 1)
        return vec(o.pos.x + s * p.x * k.x, o.pos.y + s * p.y * k.y, o.pos.z + p.z * k.z)
    end
    o.positionToLocal = function(w)
        local s = o.up.y >= 0 and 1 or -1
        local k = o.scale or vec(1, 1, 1)
        return vec(s * (w.x - o.pos.x) / k.x, s * (w.y - o.pos.y) / k.y, (w.z - o.pos.z) / k.z)
    end
    o.getBounds = function()
        return { center = o.pos, size = o.size or vec(1, 1, 1), offset = vec(0, 0, 0) }
    end
    o.setDescription = function(d) o.description = d end
    -- An object's own UI. Its elements land in Stub.ui with the screen's:
    -- the ids do not overlap.
    o.UI = {
        loading = false,
        getXmlTable = function() return o.xml or {} end,
        setXmlTable = function(t) Stub.counts.ui = Stub.counts.ui + 1 o.xml = t end,
        -- Only ever called with "" (fd.tts.hud), to clear it.
        setXml = function(s) Stub.counts.ui = Stub.counts.ui + 1 o.xml = {} end,
        setAttribute = function(id, k, v)
            Stub.counts.ui = Stub.counts.ui + 1
            Stub.ui[id] = Stub.ui[id] or {}
            Stub.ui[id][k] = v
        end,
        setValue = function(id, v)
            Stub.counts.ui = Stub.counts.ui + 1
            Stub.ui[id] = Stub.ui[id] or {}
            Stub.ui[id].value = v
        end,
    }
    o.menu = {}
    o.addContextMenuItem = function(label, fn) o.menu[label] = fn end
    o.clearContextMenu = function() o.menu = {} end
    --- Right-click the object and choose `label`, as `color`, at `pos`.
    -- Right-clicked with the pointer at `pos`. As in TTS, the item is told
    -- the object's own position, not where it was clicked: that is the
    -- player's pointer.
    o.rightClick = function(label, color, pos)
        local fn = o.menu[label]
        if not fn then error("no menu item " .. label .. " on " .. o.name) end
        color = color or "Red"
        if pos and Player[color] then Player[color].pointer = pos end
        return fn(color, o.pos, o)
    end
    -- Functions called on the object's own script, by name, in order.
    o.calls = {}
    o.call = function(fn) o.calls[#o.calls + 1] = fn end
    o.setLock = function(l) o.locked = l end
    o.setPositionSmooth = function(p) o.pos = vec(p.x, p.y, p.z) end
    o.setPosition = function(p) o.pos = vec(p.x, p.y, p.z) end
    o.setRotationSmooth = function(r) o.rot = r end
    o.isSmoothMoving = function() return false end
    -- A roll counts the throws. A gear die keeps the `value` the test set;
    -- the black die comes up whatever math.random(20) gives, so a test that
    -- loads the script's die loads this one too.
    o.roll = function()
        o.rolls = (o.rolls or 0) + 1
        if o.name == "Damage Dice" then o.value = math.random(20) end
    end
    -- The highlight left on: { color, duration }, duration nil if it stays.
    o.highlightOn = function(c, d) o.highlight = { c, d } end
    o.highlightOff = function() o.highlight = nil end
    o.setColorTint = function(c) o.tint = c end
    o.setInvisibleTo = function(colors) o.invisibleTo = colors end
    o.setScale = function(s) o.scale = vec(s.x or s[1], s.y or s[2], s.z or s[3]) end
    o.setRotationValues = function(v) o.rotationValues = v end
    -- `value` is what the face that is up shows. As in TTS, getValue() on an
    -- object with rotation values is that face's index, not its value.
    o.getRotationValue = function() return o.value end
    o.setRotationValue = function(v) o.value = v end
    o.getValue = function()
        for i, rv in ipairs(o.rotationValues or {}) do
            if rv.value == o.value then return i end
        end
        return o.value
    end
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
        if onObjectDestroy then onObjectDestroy(o) end
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
    -- A container: `contents` is what is inside ({ name, guid }), else it is
    -- an infinite bag of `spawns`, each holding `spawnContents` if given.
    o.contents = o.contents or {}
    o.getObjects = function()
        local out = {}
        for i, c in ipairs(o.contents) do out[i] = { name = c.name, guid = c.guid, index = i - 1 } end
        return out
    end
    -- A deck: its cards are its contents, dealt into a player's hand.
    o.getQuantity = function() return #o.contents end
    o.deal = function(n, color)
        local p = Player[color]
        p.hand = p.hand or {}
        for _ = 1, n do
            local c = table.remove(o.contents, 1)
            if not c then break end
            p.hand[#p.hand + 1] = c
        end
    end
    o.takeObject = function(params)
        local r = params.rotation or vec(0, 0, 0)
        local name, props = o.spawns, {}
        if params.guid then
            for i, c in ipairs(o.contents) do
                if c.guid == params.guid then
                    name, props.guid = c.name, c.guid
                    table.remove(o.contents, i)
                    break
                end
            end
        elseif o.spawnContents then
            props.contents = deepcopy(o.spawnContents)
        end
        props.pos = params.position
        props.rot = vec(r.x or 0, r.y or 0, r.z or 0)
        -- Taken out face down, as the beginner dashboard bag does.
        props.up = vec(0, math.abs(r.z or 0) == 180 and -1 or 1, 0)
        local spawned = Stub.object(name, props)
        if params.callback_function then params.callback_function(spawned) end
        return spawned
    end
    for k, fn in pairs(o) do
        if type(fn) == "function" and k ~= "click" and k ~= "rightClick" then
            o[k] = function(...)
                Stub.counts.object = Stub.counts.object + 1
                return fn(...)
            end
        end
    end
    Stub.objects[#Stub.objects + 1] = o
    return o
end

Stub.hotkeys = {}
function addHotkey(label, fn)
    Stub.hotkeys[label] = fn
end

--- Press a registered hotkey, as TTS does: colour, hovered object, pointer.
function Stub.press(label, color, hovered, pointer)
    local fn = Stub.hotkeys[label]
    if not fn then error("no hotkey " .. label) end
    return fn(color or "Red", hovered, pointer or vec(0, 1, 0), false)
end

function spawnObject(params)
    local p = params.position
    local r = params.rotation or vec(0, 0, 0)
    local o = Stub.object(params.type, {
        pos = vec(p.x or p[1], p.y or p[2], p.z or p[3]),
        rot = vec(r.x or r[1] or 0, r.y or r[2] or 0, r.z or r[3] or 0),
        scale = params.scale,
    })
    -- A tablet is a web browser.
    if params.type == "Tablet" then o.Browser = { url = "" } end
    if params.callback_function then params.callback_function(o) end
    return o
end

function spawnObjectData(params)
    Stub.counts.object = Stub.counts.object + 1
    local d = params.data
    local t = d.Transform or {}
    local o = Stub.object(d.Nickname or d.Name, {
        pos = vec(t.posX or 0, t.posY or 0, t.posZ or 0),
        rot = vec(t.rotX or 0, t.rotY or 0, t.rotZ or 0),
        scale = vec(t.scaleX or 1, t.scaleY or 1, t.scaleZ or 1),
        tint = d.ColorDiffuse, locked = d.Locked, description = d.Description,
        data = d,
    })
    -- A collider that can be switched off, as a custom model's MeshCollider.
    o.collider = { name = "MeshCollider", enabled = true }
    o.collider.set = function(k, v) o.collider[k] = v end
    o.getComponents = function() return { o.collider } end
    if params.callback_function then params.callback_function(o) end
    return o
end

function getObjects()
    Stub.counts.getObjects = Stub.counts.getObjects + 1
    return Stub.objects
end

function getObjectFromGUID(guid)
    Stub.counts.object = Stub.counts.object + 1
    for _, o in ipairs(Stub.objects) do
        if o.guid == guid then return o end
    end
    return nil
end

Player = {}
--- A seated player. `admin` makes them the host (or a promoted player).
function Stub.player(color, handPos, admin)
    local p = nil
    p = {
        color = color, steam_name = color .. "Player", steam_id = color .. "Id", seated = true,
        admin = admin or false,
        -- Seats the player in `new`, telling the game as TTS does.
        changeColor = function(new)
            if Player[p.color] == p then Player[p.color] = nil end
            p.color, p.seated = new, new ~= "Grey"
            Player[new] = p
            if onPlayerChangeColor then onPlayerChangeColor(new) end
        end,
        broadcast = function(msg) Stub.log[#Stub.log + 1] = "broadcast to " .. p.color .. ": " .. msg end,
        getPointerPosition = function() return p.pointer or vec(0, 1, 0) end,
        getHandObjects = function() return p.hand or {} end,
        -- The hand zone faces into the table, square to its nearest edge.
        getHandTransform = function()
            local yaw = math.deg(math.atan2(-handPos.x, -handPos.z))
            return { position = handPos, rotation = vec(0, (math.floor(yaw / 90 + 0.5) * 90) % 360, 0) }
        end,
    }
    Player[color] = p
    return p
end

--- Everyone connected, seated or not. A player taken out of `Player` has
-- left.
function getPlayers()
    local out = {}
    for _, p in pairs(Player) do out[#out + 1] = p end
    return out
end

function getSeatedPlayers()
    local out = {}
    for color, p in pairs(Player) do
        if p.seated then out[#out + 1] = color end
    end
    table.sort(out)
    return out
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
