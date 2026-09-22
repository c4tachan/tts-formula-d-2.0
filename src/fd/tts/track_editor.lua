-- Editing a track's spaces in the game.
--
-- The whole track stays drawn as vector lines, which costs next to nothing.
-- Only the spaces around the pointer are turned into markers -- small blocks
-- a player can drag, turn with Q/E, delete, or recolour into another lane --
-- because a few hundred physical objects at once would bog the game down.
-- Applying reads the markers back into the working copy and relinks it.
--
-- Edits live in the Global save. TTS scripts cannot write files, so getting
-- an edited track into the repo is a job for tools/extract/import_track.py,
-- which reads them back out of a saved game.

local Track = require("fd.tts.track")
local Graph = require("fd.core.trackgraph")

local Editor = {}

-- How far round the pointer to pick up spaces, in world units.
local RADIUS = 5
-- A marker is about the size of a printed cell.
local MARKER_SCALE = { x = 0.34, y = 0.06, z = 0.62 }
local MARKER_LIFT = 0.25

local edits = {}        -- track id -> { spaces = {...}, nextId = n, name = ... }
local base = {}         -- track id -> the track module it started from
local open = nil        -- id of the track being edited
local markers = {}      -- marker guid -> space id
local applying = false
local linkFrom = nil     -- space id a hand-made link starts from
-- The problem list for the open track, kept until something changes: the
-- overlay and the status line both want it after every action.
local problemCache = nil
local function changed()
    problemCache = nil
end

local function copySpace(s)
    local nxt = {}
    for i, n in ipairs(s.next or {}) do nxt[i] = n end
    return { id = s.id, pos = { s.pos[1], s.pos[2] }, rot = s.rot, lane = s.lane, next = nxt,
             fixed = s.fixed or nil, corner = s.corner }
end

--- The track as it stands: the edited copy if there is one, else the original.
function Editor.trackFor(track)
    local e = edits[track.id]
    if not e then
        return track
    end
    return {
        id = track.id, name = track.name, ruleset = track.ruleset, lanes = track.lanes,
        laps = track.laps, image = track.image, outer = track.outer, spaces = e.spaces,
    }
end

local function working(track)
    base[track.id] = track
    if not edits[track.id] then
        local spaces = {}
        for i, s in ipairs(track.spaces) do
            spaces[i] = copySpace(s)
        end
        -- Start from links worked out the editor's way: the detector's are
        -- cruder, and would paint a hundred sound spaces red on Monaco.
        local cell = Graph.relink(spaces)
        edits[track.id] = { spaces = spaces, nextId = 1, cell = cell }
        changed()
    end
    return edits[track.id]
end

local function find(e, id)
    for i, s in ipairs(e.spaces) do
        if s.id == id then return s, i end
    end
end

function Editor.isOpen()
    return open ~= nil
end

function Editor.openId()
    return open
end

--- Problems in the working copy, as a set of flagged space ids and a list.
function Editor.problems()
    if not open then return {}, {} end
    if not problemCache then
        local e = edits[open]
        local list = Graph.problems(e.spaces, e.cell)
        local flagged = {}
        for _, p in ipairs(list) do flagged[p.id] = true end
        problemCache = { flagged = flagged, list = list }
    end
    return problemCache.flagged, problemCache.list
end

function Editor.draw()
    if not open then return end
    local flagged = Editor.problems()
    Track.show(Editor.trackFor(base[open]), flagged, true)
end

function Editor.open(track)
    local e = working(track)
    -- Edits saved by an earlier version carry links worked out by its rules;
    -- relinking is quick and leaves hand-made links alone, so bring them up
    -- to date.
    e.cell = Graph.relink(e.spaces)
    open = track.id
    changed()
    Editor.draw()
end

function Editor.close()
    Editor.apply()
    -- Anything apply could not read back (the board tile has gone) goes too,
    -- so no marker is left pointing into a track that is no longer open.
    applying = true
    for guid in pairs(markers) do
        local obj = getObjectFromGUID(guid)
        if obj then obj.destruct() end
    end
    applying = false
    markers = {}
    open = nil
end

local function boardTop(tile)
    local b = tile.getBounds()
    return b.center.y + b.size.y / 2
end

-- `f` is the board's frame and `top` the height of its face, measured once
-- by the caller for however many markers it is putting out.
local function spawnMarker(tile, f, top, s)
    local w = Track.worldIn(tile, f, s.pos[1], s.pos[2])
    local obj = spawnObject({
        type = "BlockSquare",
        position = { x = w.x, y = top + MARKER_LIFT, z = w.z },
        rotation = { x = 0, y = Track.yawIn(tile, f, s.pos[1], s.pos[2], s.rot), z = 0 },
        scale = MARKER_SCALE,
        sound = false,
    })
    obj.setColorTint(Track.LANE_COLOUR[s.lane] or { 1, 1, 1 })
    obj.setName("Space " .. s.id .. " (lane " .. s.lane .. ")")
    obj.setDescription("Track editor marker. Drag to move, Q/E to turn; right-click for its lane.")
    markers[obj.getGUID()] = s.id
    -- Right-click menu, so nothing needs a key bound to it.
    for lane = 1, 3 do
        obj.addContextMenuItem("Lane " .. lane, function()
            Editor.setLane(obj, lane)
            if Editor.onChange then Editor.onChange() end
        end)
    end
    obj.addContextMenuItem("Delete space", function()
        obj.destruct()           -- onObjectDestroy takes the space away
    end)
    -- Links by hand, for the few places no rule gets right.
    local tell = { 0.6, 0.85, 1 }
    obj.addContextMenuItem("Start a link here", function(color)
        broadcastToColor(Editor.startLink(obj), color, tell)
    end)
    obj.addContextMenuItem("Link to here", function(color)
        broadcastToColor(Editor.linkTo(obj), color, tell)
        if Editor.onChange then Editor.onChange() end
    end)
    obj.addContextMenuItem("Automatic links", function(color)
        broadcastToColor(Editor.autoLinks(obj), color, tell)
        if Editor.onChange then Editor.onChange() end
    end)
    return obj
end

--- Turn the spaces around a point into markers. Returns how many.
--
-- The pointer is turned into image pixels once and the spaces are compared
-- there, rather than working out every space's place in the world.
function Editor.grab(pointer)
    if not open then return 0 end
    local tile, track = Track.tile(), base[open]
    if not tile then return 0 end
    local e = edits[open]
    local out = {}
    for _, id in pairs(markers) do out[id] = true end
    local f = Track.frame(tile, track)
    local top = boardTop(tile)
    local px, py = Track.pixelIn(tile, f, pointer)
    local r = RADIUS / f.world
    local n = 0
    for _, s in ipairs(e.spaces) do
        if not out[s.id] then
            local dx, dy = s.pos[1] - px, s.pos[2] - py
            if dx * dx + dy * dy <= r * r then
                spawnMarker(tile, f, top, s)
                n = n + 1
            end
        end
    end
    return n
end

--- A new space at a point, in the lane and facing of the nearest one.
--
-- Its id is the nearest space's code with "+n" on the end, which says where
-- it was put: the next run of find_corners.py gives it a code of its own.
function Editor.add(pointer)
    if not open then return nil end
    local tile, track = Track.tile(), base[open]
    if not tile then return nil end
    local e = edits[open]
    local px, py = Track.pixelOf(tile, track, pointer)
    local near = Graph.nearest(e.spaces, px, py)
    local id = nil
    repeat
        id = tostring(near and near.id or "new") .. "+" .. e.nextId
        e.nextId = e.nextId + 1
    until not find(e, id)
    local s = {
        id = id, pos = { px, py }, next = {},
        lane = near and near.lane or 1, rot = near and near.rot or 0,
    }
    e.dirty = true
    table.insert(e.spaces, s)
    changed()
    spawnMarker(tile, Track.frame(tile, track), boardTop(tile), s)
    return s
end

local function spaceOf(obj)
    local id = obj and markers[obj.getGUID()]
    return id and find(edits[open], id) or nil
end

--- The space a player means: the marker they are pointing at, or else the
-- space nearest the pointer, if the pointer is on its cell.
function Editor.spaceAt(obj, pointer)
    local s = spaceOf(obj)
    if s or not open or not pointer then return s end
    local tile = Track.tile()
    if not tile then return nil end
    local e = edits[open]
    local px, py = Track.pixelOf(tile, base[open], pointer)
    local near, d = Graph.nearest(e.spaces, px, py)
    local cell = (e.cell and e.cell > 0) and e.cell or 30
    if near and d <= 0.6 * cell then return near end
    return nil
end

local function beginLink(s)
    linkFrom = s.id
    return "Linking from space " .. s.id .. ": now right-click the space a car can move on to, Link to here."
end

--- Begin a hand-made link from a marker's space.
function Editor.startLink(obj)
    local s = spaceOf(obj)
    if not s then return "That is not a space marker." end
    return beginLink(s)
end

--- Finish a hand-made link: the start space leads to this one (or no longer
-- does, if it already did). The start space's links are then kept exactly
-- as set, and relinking leaves them alone.
local function toggleLink(to)
    local from = linkFrom and find(edits[open], linkFrom)
    if not from then return "Right-click a space and choose Start a link here first." end
    if from.id == to.id then return "A space cannot lead to itself." end
    local nxt, had = {}, false
    for _, n in ipairs(from.next or {}) do
        if n == to.id then had = true else nxt[#nxt + 1] = n end
    end
    if not had then nxt[#nxt + 1] = to.id end
    table.sort(nxt)
    from.next, from.fixed = nxt, true
    edits[open].dirty = true
    changed()
    Editor.draw()
    local verb = had and "no longer leads to" or "now leads to"
    local list = #nxt > 0 and table.concat(nxt, ", ") or "none"
    return "Space " .. from.id .. " " .. verb .. " space " .. to.id
        .. "; its links are now set by hand (" .. list .. ")."
end

function Editor.linkTo(obj)
    local to = spaceOf(obj)
    if not to then return "That is not a space marker." end
    return toggleLink(to)
end

--- One key for a link, pressed twice: on the space a car moves from, then
-- on the space it moves to. The link is added, or taken away if it was
-- there. Pressing it twice on the same space calls it off.
function Editor.linkKey(obj, pointer)
    local s = Editor.spaceAt(obj, pointer)
    if not s then return "Point at a space first." end
    if not linkFrom or not find(edits[open], linkFrom) then
        linkFrom = s.id
        return "Linking from space " .. s.id .. ": point at the space a car can move on to and press the key again."
    end
    if linkFrom == s.id then
        linkFrom = nil
        return "Link called off."
    end
    local msg = toggleLink(s)
    linkFrom = nil
    return msg
end

--- Hand a space's links back to the automatic rules.
function Editor.autoLinks(obj)
    local s = spaceOf(obj)
    if not s then return "That is not a space marker." end
    s.fixed = nil
    local e = edits[open]
    e.cell = Graph.relink(e.spaces)
    e.dirty = true
    changed()
    Editor.draw()
    return "Space " .. s.id .. " is linked automatically again (" .. table.concat(s.next, ", ") .. ")."
end

--- Move a marker's space to another lane.
function Editor.setLane(obj, lane)
    local id = obj and markers[obj.getGUID()]
    if not id then return false end
    local s = find(edits[open], id)
    if not s then return false end
    s.lane = lane
    edits[open].dirty = true
    changed()
    obj.setColorTint(Track.LANE_COLOUR[lane] or { 1, 1, 1 })
    obj.setName("Space " .. s.id .. " (lane " .. lane .. ")")
    return true
end

--- Read every marker back into the working copy, clear them, and relink.
function Editor.apply()
    if not open then return 0 end
    local tile, track = Track.tile(), base[open]
    -- Without the board there is nothing to measure the markers against;
    -- leave them where they are rather than fail.
    if not tile then return 0 end
    local e = edits[open]
    local n = 0
    local f = Track.frame(tile, track)
    local index = {}
    for _, s in ipairs(e.spaces) do index[s.id] = s end
    applying = true
    for guid, id in pairs(markers) do
        local obj = getObjectFromGUID(guid)
        local s = index[id]
        if obj and s then
            local p = obj.getPosition()
            local px, py = Track.pixelIn(tile, f, p)
            s.pos = { px, py }
            s.rot = Track.angleIn(tile, f, p, obj.getRotation().y)
            obj.destruct()
            n = n + 1
        end
    end
    applying = false
    markers = {}
    e.cell = Graph.relink(e.spaces)
    e.dirty = true
    changed()
    Editor.draw()
    return n
end

--- A marker was deleted by hand: the space goes with it.
function Editor.onDestroyed(obj)
    if applying then return false end
    local id = markers[obj.getGUID()]
    if not id then return false end
    markers[obj.getGUID()] = nil
    local e = edits[open]
    local _, i = find(e, id)
    if i then
        table.remove(e.spaces, i)
        e.dirty = true
        changed()
    end
    return true
end

function Editor.markerCount()
    local n = 0
    for _ in pairs(markers) do n = n + 1 end
    return n
end

--- For Global's onSave: every edited track, spaces only.
--
-- Markers still out on the board are read in as they stand but left where
-- they are: TTS saves on its own every few minutes, and clearing a player's
-- markers in the middle of an edit would be no help.
function Editor.save()
    local out = {}
    local pending = {}
    local tile = open and Track.tile()
    if tile and Editor.markerCount() > 0 then
        local track = base[open]
        local f = Track.frame(tile, track)
        for guid, id in pairs(markers) do
            local obj = getObjectFromGUID(guid)
            if obj then
                local p = obj.getPosition()
                local px, py = Track.pixelIn(tile, f, p)
                pending[id] = { pos = { px, py }, rot = Track.angleIn(tile, f, p, obj.getRotation().y) }
            end
        end
    end
    for id, e in pairs(edits) do
        if e.dirty or (id == open and next(pending)) then
            local spaces = {}
            for i, sp in ipairs(e.spaces) do
                local c = copySpace(sp)
                local moved = id == open and pending[sp.id]
                if moved then
                    c.pos, c.rot = moved.pos, moved.rot
                end
                spaces[i] = c
            end
            out[id] = { spaces = spaces, nextId = e.nextId }
        end
    end
    return out
end

--- For Global's onSave: the markers out on the board, so a load can clear them.
function Editor.markerGuids()
    local out = {}
    for guid in pairs(markers) do out[#out + 1] = guid end
    return out
end

--- Restore saved edits. Markers saved mid-edit are already read into the
-- spaces, and nothing tracks them after a load, so they are taken away.
function Editor.load(saved, strayMarkers)
    -- Start clean. Loading normally means a fresh script, but if it ever
    -- runs in one that has been editing, the strays below must not still be
    -- counted as live markers -- removing those would delete their spaces.
    edits, base, markers, open, linkFrom = {}, {}, {}, nil, nil
    changed()
    for id, e in pairs(saved or {}) do
        -- Edits saved before spaces had codes for ids name them by numbers
        -- the track file no longer uses; kept, they would hide it entirely.
        local first = e.spaces and e.spaces[1]
        if first and type(first.id) == "number" then
            printToAll("Track edits for " .. id .. " in this save predate space codes and were dropped.",
                { 1, 0.8, 0.3 })
        else
            edits[id] = { spaces = e.spaces, nextId = e.nextId or 1, dirty = true }
        end
    end
    for _, guid in ipairs(strayMarkers or {}) do
        local obj = getObjectFromGUID(guid)
        if obj then obj.destruct() end
    end
end

--- Forget the edits to a track: back to the file.
function Editor.revert(id)
    edits[id] = nil
    changed()
    if open == id then
        applying = true
        for guid in pairs(markers) do
            local obj = getObjectFromGUID(guid)
            if obj then obj.destruct() end
        end
        applying = false
        markers = {}
        working(base[id])
        Editor.draw()
    end
end

return Editor
