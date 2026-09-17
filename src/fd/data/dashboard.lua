-- Slot positions on the dashboard model, in the object's local space.
--
-- One model serves both dashboards: the advanced face is on top (+Y), and the
-- beginner face is underneath, so the Beginner Dashboard bag spawns it flipped
-- 180 degrees about Z. Positions come from the model's 55 attached snap points,
-- matched to the printed slots by projecting them through the mesh UVs onto the
-- texture. The snap points sit on the advanced face; the beginner face uses the
-- same X/Z grid at its own height.
--
-- Pass a position through object.positionToWorld() to get a world position.

local Layout = {}

-- Grid columns, left to right as printed, and rows, top to bottom as printed on
-- the advanced face. The beginner face is printed upside down relative to it,
-- so it walks the rows in reverse.
local COL_X = { 0.96, 0.10, -0.77, -1.63, -2.49, -3.35, -4.21 }
local ROW_Z = { -2.31, -1.55, -0.78, 0.00, 0.77, 1.55, 2.33 }

-- Gear slots alternate between two columns down the gate.
local GATE = {
    { 2.48, -2.03 }, { 4.23, -1.22 }, { 2.47, -0.40 },
    { 4.20, 0.34 }, { 2.45, 1.16 }, { 4.20, 1.94 },
}

local function row(r, first, count)
    local out = {}
    for c = 1, count do
        out[first + c - 1] = { COL_X[c], ROW_Z[r] }
    end
    return out
end

local function merge(a, b)
    for k, v in pairs(b) do a[k] = v end
    return a
end

local advancedGears, beginnerGears = {}, {}
for gear = 1, 6 do
    advancedGears[gear] = GATE[gear]
    beginnerGears[gear] = GATE[7 - gear]
end

-- 18 WP in three columns, 1-3 on the printed top row.
local beginnerWp = {}
for n = 1, 18 do
    local r = math.floor((n - 1) / 3)
    local c = (n - 1) % 3
    beginnerWp[n] = { COL_X[c + 1], ROW_Z[7 - r] }
end

-- The texture both faces are printed on, and where each face sits on it.
-- `crop` is the printed card in pixels; `pixel` converts a local X/Z to a pixel
-- on it (px runs against X on both faces; py runs with Z on the advanced face
-- and against it on the beginner face, which is printed the other way up).
-- Note the host: the save still carries the old cloud-3.steamusercontent.com
-- URL for this texture, which now answers 403. The board itself keeps working
-- from the local TTS cache, but a UI asset is fetched fresh and comes back
-- blank, so this uses the same host the map registry does.
Layout.texture = {
    url = "https://steamusercontent-a.akamaihd.net/ugc/1014943869376223859/3149670324DC1FF3D734BC3145C0C47C1D0EE65D/",
    width = 1024,
    height = 1024,
}

local PX_PER_UNIT = 82.3

Layout.faces = {
    advanced = {
        y = 0.384,
        crop = { x0 = 7, y0 = 7, x1 = 830, y1 = 505 },
        pixel = function(x, z) return 7 + (5 - x) * PX_PER_UNIT, 7 + (z + 3.03) * PX_PER_UNIT end,
        gears = advancedGears,
        zones = {
            tires = merge(row(1, 1, 7), row(2, 8, 7)),
            brakes = row(3, 1, 7),
            gearbox = row(4, 1, 7),
            body = row(5, 1, 7),
            engine = row(6, 1, 7),
            handling = row(7, 1, 7),
        },
    },
    beginner = {
        y = -0.2,
        crop = { x0 = 7, y0 = 517, x1 = 830, y1 = 1015 },
        pixel = function(x, z) return 7 + (5 - x) * PX_PER_UNIT, 517 + (3.03 - z) * PX_PER_UNIT end,
        gears = beginnerGears,
        zones = { wp = beginnerWp },
    },
}

--- Local position of a slot, or nil if the face has no such slot.
-- `slot` is "gear" or a wear zone id; `n` is the gear or the wear value.
function Layout.localPosition(face, slot, n)
    local f = Layout.faces[face]
    if not f then return nil end
    local list = slot == "gear" and f.gears or f.zones[slot]
    local xz = list and list[n]
    if not xz then return nil end
    return { x = xz[1], y = f.y, z = xz[2] }
end

return Layout
