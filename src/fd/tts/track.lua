-- Putting a track file onto the board tile.
--
-- Track data is in image pixels (see docs/track-format.md) because the tile is
-- movable; this converts to the tile's own local space, so anything drawn or
-- snapped to it follows the board when a player drags or turns it.

local Maps = require("fd.data.maps")
local Graph = require("fd.core.trackgraph")

local Track = {}

Track.TILE_GUID = "ebde54"

-- How far above the board face to float the overlay, in world units.
local LIFT = 0.12

-- Line thickness in world units. Lines attached to an object are given in its
-- local space, and the board tile is scaled up ~44x, so this is divided by the
-- tile's scale or it comes out metres thick.
local THICKNESS = 0.06

local EDGE_COLOUR = { 1, 0.9, 0.1 }

local LANE_COLOUR = {
    { 1, 0.82, 0.2 },
    { 0.3, 0.95, 0.45 },
    { 0.35, 0.65, 1 },
}

function Track.tile()
    return getObjectFromGUID(Track.TILE_GUID)
end

--- True if the board is currently showing this track's map.
function Track.onBoard(track, tile)
    local map = Maps.byId[track.id]
    local custom = tile and tile.getCustomObject()
    return not map or not custom or custom.image == map.url
end

--- How the track's image lies on the tile, measured once.
--
-- Asking the tile for its size and scale is a call into the game; an overlay
-- has a few thousand points, so they are read once here and reused.
function Track.frame(tile, track)
    local size = tile.getBoundsNormalized().size
    local scale = tile.getScale()
    return {
        -- Local units per image pixel, and the height to float things at.
        kx = size.x / scale.x / track.image.width,
        kz = size.z / scale.z / track.image.height,
        y = (size.y * 0.5 + LIFT) / scale.y,
        w = track.image.width,
        h = track.image.height,
        -- World units per image pixel, for distances on the board.
        world = size.x / track.image.width,
    }
end

--- A point in image pixels as a position in the tile's local space.
--
-- The tile shows its image turned half a turn from its local axes: the top
-- left of the picture sits at local +X, -Z. Drawn the other way round, the
-- overlay comes out rotated 180 degrees on the board.
function Track.localIn(f, px, py)
    return { x = -(px - f.w / 2) * f.kx, y = f.y, z = (py - f.h / 2) * f.kz }
end

function Track.localOf(tile, track, px, py)
    return Track.localIn(Track.frame(tile, track), px, py)
end

-- The conversions below come in two forms: `...In` takes a frame measured
-- once (see Track.frame) for work done many times over, `...Of` measures the
-- board itself for a one-off.

function Track.worldIn(tile, f, px, py)
    return tile.positionToWorld(Track.localIn(f, px, py))
end

function Track.worldOf(tile, track, px, py)
    return Track.worldIn(tile, Track.frame(tile, track), px, py)
end

--- A world position back to image pixels: the inverse of worldIn.
function Track.pixelIn(tile, f, world)
    local l = tile.positionToLocal(world)
    return f.w / 2 - l.x / f.kx, f.h / 2 + l.z / f.kz
end

function Track.pixelOf(tile, track, world)
    return Track.pixelIn(tile, Track.frame(tile, track), world)
end

--- The world yaw of something facing `rot` degrees in image space at (px, py).
function Track.yawIn(tile, f, px, py, rot)
    local a = math.rad(rot)
    local p0 = Track.worldIn(tile, f, px, py)
    local p1 = Track.worldIn(tile, f, px + 10 * math.cos(a), py + 10 * math.sin(a))
    return math.deg(math.atan2(p1.x - p0.x, p1.z - p0.z)) % 360
end

function Track.yawOf(tile, track, px, py, rot)
    return Track.yawIn(tile, Track.frame(tile, track), px, py, rot)
end

--- The image-space facing of something at `world` turned to `yaw` degrees.
function Track.angleIn(tile, f, world, yaw)
    local r = math.rad(yaw)
    local ahead = { x = world.x + math.sin(r), y = world.y, z = world.z + math.cos(r) }
    local x0, y0 = Track.pixelIn(tile, f, world)
    local x1, y1 = Track.pixelIn(tile, f, ahead)
    return math.deg(math.atan2(y1 - y0, x1 - x0)) % 360
end

function Track.angleOf(tile, track, world, yaw)
    return Track.angleIn(tile, Track.frame(tile, track), world, yaw)
end

-- Snapping cars ----------------------------------------------------------------

-- Cell length per track, in image pixels; worked out on first use. Keyed
-- weakly, so an edited copy of a track that is thrown away takes its entry
-- with it.
local cellOf = setmetatable({}, { __mode = "k" })

local function cellLength(track)
    local c = cellOf[track]
    if not c then
        c = Graph.cellLength(track.spaces)
        cellOf[track] = c
    end
    return c
end

--- The space nearest `world`, within `reach` cells of it, skipping any id
-- listed in `taken`. Returns the space and the frame, or nil.
function Track.spaceNear(tile, f, track, world, reach, taken)
    local px, py = Track.pixelIn(tile, f, world)
    local limit = cellLength(track) * reach
    local best, bestD = nil, limit * limit
    for _, s in ipairs(track.spaces) do
        if not (taken and taken[s.id]) then
            local dx, dy = s.pos[1] - px, s.pos[2] - py
            local d = dx * dx + dy * dy
            if d <= bestD then best, bestD = s, d end
        end
    end
    return best
end

--- Where a car put down at `world` belongs: the nearest free space within
-- `reach` cells, as a world position and the yaw that faces the way the
-- track runs. `others` are world positions of cars already on the track;
-- the spaces they sit on are not offered. Returns nil if there is no space
-- close enough -- a car put down off the track stays where it was put.
function Track.snap(tile, track, world, reach, others)
    local f = Track.frame(tile, track)
    local taken = {}
    for _, p in ipairs(others or {}) do
        local s = Track.spaceNear(tile, f, track, p, 0.5, taken)
        if s then taken[s.id] = true end
    end
    local s = Track.spaceNear(tile, f, track, world, reach, taken)
    if not s then
        return nil
    end
    return s, Track.worldIn(tile, f, s.pos[1], s.pos[2]), Track.yawIn(tile, f, s.pos[1], s.pos[2], s.rot)
end

-- Footprint drawn at each space, in image pixels: roughly a car's outline, so
-- the marker shows which way a car parked there would face.
local MARK_LONG, MARK_WIDE = 13, 7
local PROBLEM_COLOUR = { 1, 0.15, 0.15 }
-- Spaces inside a corner get a second, smaller outline in this colour.
local CORNER_COLOUR = { 1, 0.3, 0.85 }
local CORNER_INSET = 0.55

--- A footprint on every space, with a tick out to the space straight ahead.
--
-- One line per space: the outline, then on from its front edge towards the
-- next space in its lane. Spaces listed in `flagged` (id -> true) are drawn
-- red. The track's outside edge is drawn too, where the file has one.
function Track.overlay(tile, track, flagged)
    local thickness = THICKNESS / math.max(tile.getScale().x, 0.001)
    local f = Track.frame(tile, track)
    local lines = {}
    local byId = {}
    for _, s in ipairs(track.spaces) do byId[s.id] = s end

    for _, piece in ipairs(track.outer or {}) do
        if #piece > 1 then
            local edge = {}
            for i, p in ipairs(piece) do
                edge[i] = Track.localIn(f, p[1], p[2])
            end
            lines[#lines + 1] = { points = edge, color = EDGE_COLOUR, thickness = thickness }
        end
    end

    for _, s in ipairs(track.spaces) do
        local a = math.rad(s.rot)
        local fx, fy = math.cos(a), math.sin(a)      -- along the car
        local rx, ry = -fy, fx                       -- across it
        local function at(along, across)
            return Track.localIn(f, s.pos[1] + fx * along + rx * across, s.pos[2] + fy * along + ry * across)
        end
        local pts = {
            at(MARK_LONG, MARK_WIDE), at(MARK_LONG, -MARK_WIDE), at(-MARK_LONG, -MARK_WIDE),
            at(-MARK_LONG, MARK_WIDE), at(MARK_LONG, MARK_WIDE), at(MARK_LONG, 0),
        }
        for _, n in ipairs(s.next or {}) do
            local o = byId[n]
            if o and o.lane == s.lane then
                -- Stop short of the next space's own outline.
                local mx = s.pos[1] + (o.pos[1] - s.pos[1]) * 0.62
                local my = s.pos[2] + (o.pos[2] - s.pos[2]) * 0.62
                pts[#pts + 1] = Track.localIn(f, mx, my)
                break
            end
        end
        lines[#lines + 1] = {
            points = pts,
            color = (flagged and flagged[s.id]) and PROBLEM_COLOUR or LANE_COLOUR[s.lane] or { 1, 1, 1 },
            thickness = thickness,
        }
        if s.corner then
            local l, w = MARK_LONG * CORNER_INSET, MARK_WIDE * CORNER_INSET
            lines[#lines + 1] = {
                points = { at(l, w), at(l, -w), at(-l, -w), at(-l, w), at(l, w) },
                color = CORNER_COLOUR, thickness = thickness,
            }
        end
        -- Links set by hand are drawn out in full, in white.
        if s.fixed then
            for _, n in ipairs(s.next or {}) do
                local o = byId[n]
                if o then
                    lines[#lines + 1] = {
                        points = { Track.localIn(f, s.pos[1], s.pos[2]), Track.localIn(f, o.pos[1], o.pos[2]) },
                        color = { 1, 1, 1 }, thickness = thickness,
                    }
                end
            end
        end
    end
    return lines
end

--- Draw the space graph on the board. Returns false if the board is showing
-- a different map.
function Track.show(track, flagged)
    local tile = Track.tile()
    if not tile then
        return false, "the board tile is missing"
    end
    if not Track.onBoard(track, tile) then
        return false, "the board is showing a different map"
    end
    tile.setVectorLines(Track.overlay(tile, track, flagged))
    return true
end

function Track.hide()
    local tile = Track.tile()
    if tile then
        tile.setVectorLines({})
    end
end

Track.LANE_COLOUR = LANE_COLOUR

return Track
