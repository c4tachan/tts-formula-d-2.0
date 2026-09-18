-- Player dashboards: finding one for a player and keeping its gear stick and
-- wear markers in step with the race state.

local Layout = require("fd.data.dashboard")

local Dashboard = {}

Dashboard.NAMES = { ["Beginner Dashboard"] = true, ["Advanced Dashboard"] = true }

local GEAR_STICK_BAG = "71d89b"
local WEAR_MARKER_BAG = "a845cd"

-- Drop markers from slightly above the slot so they settle into it.
local LIFT = 0.3

function Dashboard.is(obj)
    return Dashboard.NAMES[obj.getName()] == true
end

--- "advanced" or "beginner", whichever face is showing.
function Dashboard.face(dash)
    return dash.getTransformUp().y >= 0 and "advanced" or "beginner"
end

--- True if the showing face has every slot the ruleset's zones need.
function Dashboard.fits(dash, rules)
    local zones = Layout.faces[Dashboard.face(dash)].zones
    for _, z in ipairs(rules.zones) do
        if not zones[z.id] then
            return false
        end
    end
    return true
end

function Dashboard.worldSlot(dash, slot, n)
    local p = Layout.localPosition(Dashboard.face(dash), slot, n)
    if not p then
        return nil
    end
    local w = dash.positionToWorld(p)
    return { x = w.x, y = w.y + LIFT, z = w.z }
end

--- The slot of kind `slot` ("gear" or a zone id) nearest to world `pos`,
-- or nil if none is within `reach` (measured across the table surface).
function Dashboard.slotAt(dash, slot, pos, reach)
    local face = Layout.faces[Dashboard.face(dash)]
    local list = slot == "gear" and face.gears or face.zones[slot]
    if not list then
        return nil
    end
    local best, bestDist = nil, reach * reach
    for n in pairs(list) do
        local p = Dashboard.worldSlot(dash, slot, n)
        local d = (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2
        if d <= bestDist then
            best, bestDist = n, d
        end
    end
    return best
end

-- The dashboards on the table, by GUID. Kept up to date from Global's spawn
-- and destroy events, because scanning every object on the table after each
-- click adds up once the table is full of pieces.
local known = {}

--- Find the dashboards already on the table. Once, at load.
function Dashboard.scan()
    known = {}
    for _, obj in ipairs(getObjects()) do
        if Dashboard.is(obj) then known[obj.getGUID()] = true end
    end
end

function Dashboard.track(obj)
    if Dashboard.is(obj) then known[obj.getGUID()] = true end
end

function Dashboard.forget(obj)
    known[obj.getGUID()] = nil
end

--- Every dashboard on the table.
function Dashboard.all()
    local out = {}
    for guid in pairs(known) do
        local obj = getObjectFromGUID(guid)
        if obj then
            out[#out + 1] = obj
        else
            known[guid] = nil        -- gone into a bag
        end
    end
    return out
end

--- The closest dashboard to `pos` whose GUID is not in `taken`.
function Dashboard.nearest(pos, taken)
    local best, bestDist = nil, nil
    for _, obj in ipairs(Dashboard.all()) do
        if not taken[obj.getGUID()] then
            local p = obj.getPosition()
            local d = (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2
            if not bestDist or d < bestDist then
                best, bestDist = obj, d
            end
        end
    end
    return best
end

local function far(a, b)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2 > 0.01
end

-- Move the marker `guid` to a slot, taking a new one from the bag if it is
-- gone. Returns the marker's GUID, or the old one if the slot does not exist.
local function place(dash, guid, bagGuid, slot, n, tint)
    local pos = Dashboard.worldSlot(dash, slot, n)
    if not pos then
        return guid
    end
    local rot = { x = 0, y = dash.getRotation().y, z = 0 }
    local marker = guid and getObjectFromGUID(guid)
    if marker then
        if far(marker.getPosition(), pos) and not marker.held_by_color then
            marker.setPositionSmooth(pos, false, true)
            marker.setRotationSmooth(rot, false, true)
        end
        return guid
    end
    local bag = getObjectFromGUID(bagGuid)
    if not bag then
        return guid
    end
    local obj = bag.takeObject({ position = pos, rotation = rot, smooth = false })
    obj.setColorTint(tint)
    return obj.getGUID()
end

--- Bring a car's dashboard markers up to date. `markers` is the car's
-- persistent { gear = guid, wear = { zone = guid } } table and is updated in place.
function Dashboard.sync(dash, markers, car, rules, tint)
    markers.wear = markers.wear or {}
    markers.gear = place(dash, markers.gear, GEAR_STICK_BAG, "gear", math.max(car.gear, 1), tint)
    for _, z in ipairs(rules.zones) do
        local value = car.wear[z.id]
        if value >= 1 then
            markers.wear[z.id] = place(dash, markers.wear[z.id], WEAR_MARKER_BAG, z.id, value, tint)
        end
    end
end

return Dashboard
