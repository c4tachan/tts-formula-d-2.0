-- Ghost cars: a see-through car on a track space, in its lane's colour.
--
-- Shown on every space to check the track against the print, and used by the
-- editor as the markers a player drags. Each is one spawnObjectData call --
-- model, tint, name and lock all in the data -- and a whole track is spawned
-- a batch at a time over a few frames, so the game does not stall on it.
--
-- Ghosts are locked: no physics, so hundreds packed nose to tail cannot knock
-- each other about, but a player can still pick one up, turn it and put it
-- down. The ones only there to be looked at have no collision at all.

local Track = require("fd.tts.track")

local Ghosts = {}

-- The Formula 1 Solid car from the mod's own bag (see CAR_BAG in Global).
local MESH = "https://steamusercontent-a.akamaihd.net/ugc/1014943869376509471/CE18C3F74DA725FD41EAC3D46E26CC284C566EB1/"
local DIFFUSE = "https://steamusercontent-a.akamaihd.net/ugc/1014943869376507421/8A5B06F5BD75053F2140E2401DB81A55918D61FC/"
-- Smaller than the cars players race with (1.5), so neighbouring ghosts
-- stand clear of each other and the print shows round them.
local SCALE = 1.0
-- How far above the board face a ghost floats, in world units.
local LIFT = 0.3
-- How see-through a ghost is: 0 invisible, 1 solid.
local ALPHA = 0.45
-- Ghosts spawned per frame.
local BATCH = 25

Ghosts.PROBLEM = { 1, 0.15, 0.15 }

local shown = {}         -- guids of the ghosts put out by Ghosts.show

local function boardTop(tile)
    local b = tile.getBounds()
    return b.center.y + b.size.y / 2
end

--- The colour a ghost of `s` takes: its lane's, or red if it has a problem.
function Ghosts.tint(s, problem)
    local c = problem and Ghosts.PROBLEM or Track.LANE_COLOUR[s.lane] or { 1, 1, 1 }
    return { r = c[1], g = c[2], b = c[3], a = ALPHA }
end

function Ghosts.name(s)
    return "Space " .. s.id .. " (lane " .. s.lane .. ")"
end

--- Switch off an object's colliders, so it neither stops nor is hit by
-- anything. The pointer finds objects by their colliders too, so it cannot
-- be picked up afterwards.
local function noCollision(obj)
    for _, c in ipairs(obj.getComponents() or {}) do
        if c.name and c.name:find("Collider") then
            c.set("enabled", false)
        end
    end
end

--- Put a ghost on space `s`. `f` is the board's frame and `top` the height
-- of its face, measured once by the caller for however many it puts out.
-- `solid` false leaves it with no collision: for ghosts nobody handles.
function Ghosts.spawn(tile, f, top, s, problem, description, solid)
    local w = Track.worldIn(tile, f, s.pos[1], s.pos[2])
    return spawnObjectData({
        -- A custom model's collider only exists once its mesh has loaded.
        callback_function = solid == false and noCollision or nil,
        data = {
            Name = "Custom_Model",
            Transform = {
                posX = w.x, posY = top + LIFT, posZ = w.z,
                rotX = 0, rotY = Track.yawIn(tile, f, s.pos[1], s.pos[2], s.rot), rotZ = 0,
                scaleX = SCALE, scaleY = SCALE, scaleZ = SCALE,
            },
            Nickname = Ghosts.name(s),
            Description = description or "",
            ColorDiffuse = Ghosts.tint(s, problem),
            Locked = true,
            Grid = false,
            Snap = false,
            Tooltip = true,
            CustomMesh = {
                MeshURL = MESH, DiffuseURL = DIFFUSE, NormalURL = "", ColliderURL = "",
                Convex = true, MaterialIndex = 0, TypeIndex = 0, CastShadows = false,
            },
        },
    })
end

--- Call `fn(item)` for every item, BATCH to a frame. `done` runs after the last.
function Ghosts.each(items, fn, done)
    local i = 1
    local function step()
        local last = math.min(i + BATCH - 1, #items)
        for k = i, last do fn(items[k]) end
        i = last + 1
        if i <= #items then
            Wait.frames(step, 1)
        elseif done then
            done()
        end
    end
    if #items == 0 then
        if done then done() end
    else
        step()
    end
end

--- A ghost on every space of `track`, for looking at only: locked, not to be
-- picked up, and with no collision, so a car put down on the track goes
-- straight through to the board. `flagged` (id -> true) turns a ghost red.
function Ghosts.show(track, flagged)
    Ghosts.clear()
    local tile = Track.tile()
    if not tile then return false end
    local f = Track.frame(tile, track)
    local top = boardTop(tile)
    Ghosts.each(track.spaces, function(s)
        local obj = Ghosts.spawn(tile, f, top, s, flagged and flagged[s.id], nil, false)
        obj.interactable = false
        shown[#shown + 1] = obj.getGUID()
    end)
    return true
end

function Ghosts.clear()
    for _, guid in ipairs(shown) do
        local obj = getObjectFromGUID(guid)
        if obj then obj.destruct() end
    end
    shown = {}
end

--- For Global's onSave: the ghosts out on the table, so a load can clear them.
function Ghosts.guids()
    local out = {}
    for i, g in ipairs(shown) do out[i] = g end
    return out
end

Ghosts.boardTop = boardTop

return Ghosts
