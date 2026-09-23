-- A copy of the player's dashboard in the corner of their own screen.
--
-- TTS cannot render a camera view of an object, so this redraws the real thing:
-- the dashboard texture cropped to the face the ruleset uses, with the gear
-- stick and wear markers painted on in the player's colour. It is also the
-- control surface -- clicking a gear slot shifts, clicking a wear number sets
-- that value -- so a player never has to reach across the table.
--
-- Slot positions come from the same data as the physical dashboard, projected
-- onto the texture, so the two can never drift apart.

local Layout = require("fd.data.dashboard")
local Race = require("fd.core.race")
local Ui = require("fd.tts.ui")

local Mini = {}

local COLORS = { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink" }

local HEX = {
    White = "#FFFFFF", Brown = "#713B17", Red = "#DA1918", Orange = "#F4641D", Yellow = "#E7E52C",
    Green = "#31B32B", Teal = "#21B19B", Blue = "#1F87FF", Purple = "#A020F0", Pink = "#F570CE",
}

local ASSET = "fdDashboard"

-- Texture pixels to screen pixels. The printed card is 823 wide, so this puts
-- the copy at about a third of the screen's width on a 1080p display.
local SCALE = 0.42

-- Keep the markers to plain squares. A round marker would have to be a glyph
-- or an image: no TTS font carries U+25CF BLACK CIRCLE, and non-ASCII does not
-- survive the trip into the UI anyway (U+2022 arrived as mojibake), while TTS
-- UI images need an asset and nothing in the mod has a transparent circle.
local MARKER = 18      -- square marker, about the size of a printed hole
local HIT = 30         -- invisible click target over a slot

local ACTIONS = {
    { fn = "fdUiCar", label = "Car", tip = "Claim the nearest car, or take one from the bag" },
    { fn = "fdUiCollision", label = "Collision?", tip = "Ended next to or behind a car: roll the black die" },
    { fn = "fdUiPit", label = "Pit stop", tip = "Restore WP; leave in 4th gear or lower" },
    { fn = "fdUiLeave", label = "Leave", tip = "Take your car out of the race" },
}

local ready = false
local face = "beginner"

local function el(tag, attrs, children, value)
    return { tag = tag, attributes = attrs or {}, children = children or {}, value = value }
end

--- Offset of a texture pixel from the middle of the cropped card, in UI units.
local function offsetOf(px, py)
    local c = Layout.faces[face].crop
    return (px - (c.x0 + c.x1) / 2) * SCALE, -(py - (c.y0 + c.y1) / 2) * SCALE
end

--- Offset of a slot ("gear" or a zone id, plus its number).
local function slotOffset(slot, n)
    local p = Layout.localPosition(face, slot, n)
    if not p then
        return nil
    end
    return offsetOf(Layout.faces[face].pixel(p.x, p.z))
end

local function xy(x, y)
    return string.format("%.0f %.0f", x, y)
end

local function cardSize()
    local c = Layout.faces[face].crop
    return (c.x1 - c.x0) * SCALE, (c.y1 - c.y0) * SCALE
end

--- The dashboard picture: the texture, shifted so the wanted face shows
-- through a mask the size of the card.
local function picture()
    local w, h = cardSize()
    local tex = Layout.texture
    local c = Layout.faces[face].crop
    local dx = (tex.width / 2 - (c.x0 + c.x1) / 2) * SCALE
    local dy = -(tex.height / 2 - (c.y0 + c.y1) / 2) * SCALE
    return el("Mask", { id = "fdm_mask", width = tostring(w), height = tostring(h) }, {
        el("Image", {
            image = ASSET, width = tostring(tex.width * SCALE), height = tostring(tex.height * SCALE),
            offsetXY = xy(dx, dy), raycastTarget = "false",
        }),
    })
end

local function marker(id, color)
    return el("Panel", {
        id = id, color = HEX[color], width = tostring(MARKER), height = tostring(MARKER),
        raycastTarget = "false", offsetXY = "0 0",
    })
end

--- Click targets and markers laid over the picture, in one panel per player.
local function overlay(color)
    local p = "fdm_" .. color .. "_"
    local kids = {}
    for gear = 1, 6 do
        local x, y = slotOffset("gear", gear)
        kids[#kids + 1] = el("Button", {
            id = p .. "g" .. gear, onClick = "fdUiShift(" .. gear .. ")",
            width = tostring(HIT), height = tostring(HIT), offsetXY = xy(x, y),
            colors = "#FFFFFF00|#FFFFFF44|#FFFFFF66|#FFFFFF00", tooltip = Race.gearName(gear) .. " gear",
        })
    end
    for _, zone in ipairs({ "wp" }) do
        local n = 1
        while true do
            local x, y = slotOffset(zone, n)
            if not x then break end
            kids[#kids + 1] = el("Button", {
                id = p .. zone .. n, onClick = "fdUiWear(" .. zone .. ":" .. n .. ")",
                width = tostring(HIT), height = tostring(HIT), offsetXY = xy(x, y),
                colors = "#FFFFFF00|#FFFFFF44|#FFFFFF66|#FFFFFF00", tooltip = n .. " " .. zone:upper(),
            })
            n = n + 1
        end
    end
    -- Markers last so they draw over the click targets.
    kids[#kids + 1] = marker(p .. "gearMark", color)
    kids[#kids + 1] = marker(p .. "wpMark", color)
    return kids
end

local function panel(color)
    local p = "fdm_" .. color .. "_"
    local w, h = cardSize()
    local buttons = {}
    for _, a in ipairs(ACTIONS) do
        buttons[#buttons + 1] = el("Button", {
            id = p .. a.fn, text = a.label, onClick = a.fn, tooltip = a.tip, fontSize = "11",
            colors = "#3A3F47|#4E555F|#2A2E34|#3A3F4780", textColor = "#FFFFFF",
        })
    end
    local children = { picture() }
    for _, node in ipairs(overlay(color)) do
        children[#children + 1] = node
    end
    return el("Panel", {
        id = "fdm_" .. color, visibility = color, rectAlignment = "LowerRight",
        offsetXY = "-16 16", width = tostring(w + 16), height = tostring(h + 76),
        color = "#15181CE8", allowDragging = "true", returnToOriginalPositionWhenReleased = "false",
    }, {
        el("VerticalLayout", { padding = "8 8 4 6", spacing = "3", childForceExpandHeight = "false" }, {
            el("Text", { id = p .. "label", color = HEX[color], fontSize = "14", preferredHeight = "20" },
                nil, color),
            el("Panel", { preferredHeight = tostring(h) }, children),
            el("HorizontalLayout", { spacing = "3", preferredHeight = "28" }, buttons),
        }),
    })
end

--- Panels for every seat colour, to append to the Global UI.
function Mini.panels(rules)
    -- Show whichever printed face carries this ruleset's wear zones.
    for name, f in pairs(Layout.faces) do
        local fits = true
        for _, z in ipairs(rules.zones) do
            if not f.zones[z.id] then fits = false end
        end
        if fits then face = name end
    end
    local out = {}
    for _, c in ipairs(COLORS) do
        out[#out + 1] = panel(c)
    end
    return out
end

--- Make sure the dashboard texture is available to the UI, keeping any assets
-- the mod already defined.
function Mini.registerAsset()
    local assets = UI.getCustomAssets() or {}
    for _, a in ipairs(assets) do
        if a.name == ASSET then
            if a.url == Layout.texture.url then
                return
            end
            -- An older URL is saved with the game; replace it.
            a.url = Layout.texture.url
            UI.setCustomAssets(assets)
            return
        end
    end
    assets[#assets + 1] = { name = ASSET, url = Layout.texture.url }
    UI.setCustomAssets(assets)
end

--- Mark the screen dashboards ready for updates, or (false) not yet.
function Mini.setReady(on)
    ready = on ~= false
end

local function moveMarker(id, slot, n)
    local x, y = slotOffset(slot, n)
    if x then
        Ui.set(id, "offsetXY", xy(x, y))
        Ui.set(id, "active", "true")
    else
        Ui.set(id, "active", "false")
    end
end

function Mini.refresh(race)
    if not ready then
        return
    end
    for _, color in ipairs(COLORS) do
        local p = "fdm_" .. color .. "_"
        local car = race:car(color)
        Ui.set("fdm_" .. color, "active", tostring(car ~= nil))
        if car then
            local bits = { race:label(car) }
            bits[#bits + 1] = car.gear > 0 and (Race.gearName(car.gear) .. " gear") or "on the grid"
            for _, z in ipairs(race.rules.zones) do
                bits[#bits + 1] = math.max(0, car.wear[z.id]) .. " " .. z.name
            end
            if car.eliminated then
                bits[#bits + 1] = "OUT"
            end
            for _, c in ipairs(race:pendingChecks()) do
                if c.color == color then
                    bits[#bits + 1] = "roll the black die"
                    break
                end
            end
            Ui.value(p .. "label", table.concat(bits, "  -  "))
            moveMarker(p .. "gearMark", "gear", math.max(car.gear, 1))
            for _, z in ipairs(race.rules.zones) do
                moveMarker(p .. "wpMark", z.id, math.max(0, car.wear[z.id]))
            end
        end
    end
end

return Mini
