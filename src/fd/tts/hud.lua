-- The race panel everyone sees, lying on an empty patch of the board (or on
-- the screen, for a map without one): standings, pending black die checks,
-- and Undo. Per-player controls live on the
-- dashboards (fd.tts.controls), the race-wide ones on the setup menu
-- (fd.tts.setup).
--
-- Hud.build also sends the Global UI, appended to whatever the Global XML
-- already holds, so the Big Box menu button survives.

local Race = require("fd.core.race")
local Track = require("fd.tts.track")
local Ui = require("fd.tts.ui")

local Hud = {}

local HEX = {
    White = "#FFFFFF", Brown = "#713B17", Red = "#DA1918", Orange = "#F4641D", Yellow = "#E7E52C",
    Green = "#31B32B", Teal = "#21B19B", Blue = "#1F87FF", Purple = "#A020F0", Pink = "#F570CE",
}

local PANEL_BG = "#15181CE8"

-- Who sees the race controls: the host and promoted players.
local ADMIN = "Host|Admin"

local ready = false

local function el(tag, attrs, children, value)
    return { tag = tag, attributes = attrs or {}, children = children or {}, value = value }
end

local function button(id, text, onClick, extra)
    local a = {
        id = id, text = text, onClick = onClick, fontSize = "14",
        colors = "#3A3F47|#4E555F|#2A2E34|#3A3F4780", textColor = "#FFFFFF",
    }
    for k, v in pairs(extra or {}) do a[k] = v end
    return el("Button", a)
end

local function text(id, value, extra)
    local a = { id = id, color = "#FFFFFF", fontSize = "14", alignment = "UpperLeft" }
    for k, v in pairs(extra or {}) do a[k] = v end
    return el("Text", a, nil, value)
end

-- The standings: a table, so the columns line up whatever the names.
-- One row per seat, hidden until a car fills it.
local MAX_ROWS = 10
local ROW_HEIGHT = 18
local PANEL_HEIGHT = 360

--- The standings columns: width 0 takes what the others leave. A column per
-- wear zone, headed with its name, so the cells need no unit.
local function columns(rules)
    local cols = {
        { id = "pos", head = "#", width = 22, align = "MiddleRight" },
        { id = "driver", head = "Driver", width = 0 },
        { id = "gear", head = "Gear", width = 40 },
    }
    for _, z in ipairs(rules.zones) do
        cols[#cols + 1] = { id = "w_" .. z.id, head = z.name, width = 36, zone = z.id, align = "MiddleRight" }
    end
    cols[#cols + 1] = { id = "lap", head = "Lap", width = 36 }
    cols[#cols + 1] = { id = "roll", head = "Roll", width = 34, align = "MiddleRight" }
    cols[#cols + 1] = { id = "status", head = "", width = 70 }
    return cols
end

local function cellId(row, col)
    return "fdr_r" .. row .. "_" .. col.id
end

local function standingsTable(cols)
    local widths, head = {}, {}
    for i, c in ipairs(cols) do
        widths[i] = tostring(c.width)
        head[i] = el("Cell", nil, {
            text(nil, c.head, { fontSize = "12", color = "#AAB0B8", alignment = c.align or "MiddleLeft" }),
        })
    end
    local rows = { el("Row", { preferredHeight = tostring(ROW_HEIGHT) }, head) }
    for r = 1, MAX_ROWS do
        local cells = {}
        for i, c in ipairs(cols) do
            cells[i] = el("Cell", nil, {
                text(cellId(r, c), "", { fontSize = "14", alignment = c.align or "MiddleLeft" }),
            })
        end
        rows[#rows + 1] = el("Row", { id = "fdr_r" .. r, preferredHeight = tostring(ROW_HEIGHT), active = "false" }, cells)
    end
    return el("TableLayout", {
        id = "fdr_table", columnWidths = table.concat(widths, " "), autoCalculateHeight = "false",
        preferredHeight = tostring(ROW_HEIGHT * (MAX_ROWS + 1)), cellPadding = "2 2 0 0",
        cellBackgroundColor = "clear", rowBackgroundColor = "clear",
    }, rows)
end

local PANEL_WIDTH = 380

-- On the screen: where it was before it went on the board.
local ON_SCREEN = {
    rectAlignment = "UpperLeft", offsetXY = "20 -120",
    allowDragging = "true", returnToOriginalPositionWhenReleased = "false",
}

--- The panel, placed by `place` (ON_SCREEN or from placement).
local function racePanel(rules, cols, place)
    local attrs = { id = "fdr", width = tostring(PANEL_WIDTH), height = tostring(PANEL_HEIGHT), color = PANEL_BG }
    for k, v in pairs(place) do attrs[k] = v end
    return el("Panel", attrs, {
        el("VerticalLayout", { padding = "8 8 6 6", spacing = "4", childForceExpandHeight = "false" }, {
            text("fdr_title", "Formula D", { fontSize = "18", fontStyle = "Bold", preferredHeight = "26" }),
            text("fdr_rules", rules.name, { fontSize = "12", color = "#AAB0B8", preferredHeight = "16" }),
            standingsTable(cols),
            text("fdr_empty", "No cars yet -- take a coloured seat to join.", { preferredHeight = "18" }),
            text("fdr_checks", "", { preferredHeight = "40", color = "#FFB74D" }),
            -- For the host and promoted players only; Global checks again
            -- when it is pressed. The rest of the race controls are on the
            -- setup menu.
            el("HorizontalLayout", { spacing = "4", preferredHeight = "34", visibility = ADMIN }, {
                button("fdr_undo", "Undo", "fdUndo", { tooltip = "Undo the last change" }),
            }),
        }),
    })
end

-- On the board the panel is the tile's own UI, at the spot the track names
-- (`panel`: centre and width in image pixels). Object UI is laid out at 100
-- units per local unit, then stretched with the object, so the panel is
-- scaled back by the tile's scale and on to the width the track asks for.
--
-- The tile's UI runs with its X along local X and its Y along local Z,
-- which on the board is image left and image down: turned half round, the
-- panel reads the same way up as the picture.
local UI_PER_LOCAL = 100

--- Where the panel goes on `tile` for `track`, or nil if the track names no
-- spot for it.
local function placement(tile, track)
    local spot = track and track.panel
    if not spot then
        return nil
    end
    local f = Track.frame(tile, track)
    local scale = tile.getScale()
    local l = Track.localIn(f, spot.pos[1], spot.pos[2])
    local unit = spot.width * f.world / PANEL_WIDTH -- world units per UI unit
    return {
        position = string.format("%.1f %.1f %.1f", l.x * UI_PER_LOCAL, l.z * UI_PER_LOCAL, -l.y * UI_PER_LOCAL),
        scale = string.format("%.4f %.4f 1", unit * UI_PER_LOCAL / scale.x, unit * UI_PER_LOCAL / scale.z),
        rotation = "0 0 180",
    }
end

local cols = {}

--- Set the race panel on the board `tile`, where `track` (the map on it)
-- says, and append any `extras` to the Global UI, then call `onReady`. Safe
-- to call again: it replaces what it put there before. With no spot on the
-- board the panel goes on the screen.
function Hud.build(rules, extras, tile, track, onReady)
    cols = columns(rules)
    -- Hold updates until the new XML has loaded: sent now, they would be lost
    -- with the old elements yet remembered by fd.tts.ui, and the refresh in
    -- onReady would then skip them as repeats.
    ready = false
    local place = tile and placement(tile, track)
    local function placePanel()
        if not place then
            if tile then tile.UI.setXmlTable({}) end
            Ui.route("fdr", nil)
            ready = true
            return onReady()
        end
        tile.UI.setXmlTable({ racePanel(rules, cols, place) })
        Ui.route("fdr", tile.UI)
        Ui.reset("fdr")
        Wait.frames(function()
            Wait.condition(function()
                ready = true
                onReady()
            end, function() return tile == nil or not tile.UI.loading end)
        end, 2)
    end
    Wait.condition(function()
        local xml = UI.getXmlTable() or {}
        local kept = {}
        for _, node in ipairs(xml) do
            local id = node.attributes and node.attributes.id or ""
            if id:sub(1, 2) ~= "fd" then
                kept[#kept + 1] = node
            end
        end
        if not place then
            kept[#kept + 1] = racePanel(rules, cols, ON_SCREEN)
        end
        for _, node in ipairs(extras or {}) do
            kept[#kept + 1] = node
        end
        UI.setXmlTable(kept)
        Ui.reset()           -- every element is back to what the XML says
        Wait.frames(function()
            Wait.condition(placePanel, function() return not UI.loading end)
        end, 2)
    end, function() return not UI.loading end)
end

local function wearSummary(race, car)
    local parts = {}
    for _, z in ipairs(race.rules.zones) do
        parts[#parts + 1] = math.max(0, car.wear[z.id]) .. " " .. z.name
    end
    return table.concat(parts, " ")
end

--- What each column of the standings says for `car`, with its colour if not
-- the default. `due` is the car to play.
local function carCells(race, car, i, due, laps)
    local cells = { pos = { tostring(i) }, driver = { race:label(car), HEX[car.color] or "#FFFFFF" } }
    if car.eliminated then
        cells.status = { "OUT", "#FF5252" }
    elseif car.place then
        cells.status = { "finished", "#FFD740" }
    else
        cells.gear = { car.gear > 0 and Race.gearName(car.gear) or "grid" }
        for _, z in ipairs(race.rules.zones) do
            cells["w_" .. z.id] = { tostring(math.max(0, car.wear[z.id])) }
        end
        if laps > 1 and car.lap > 0 then
            cells.lap = { math.min(car.lap, laps) .. "/" .. laps }
        end
        cells.roll = { car.lastRoll and tostring(car.lastRoll) or "" }
        if car == due then
            cells.status = { "TO PLAY", "#7CFC00" }
        end
    end
    return cells
end

local function checkLine(race)
    local parts = {}
    for _, c in ipairs(race:pendingChecks()) do
        local car = race:car(c.color)
        -- A start waiting for its turn is rolled then, by the script.
        if car and c.kind ~= "start" then
            parts[#parts + 1] = string.format("<color=%s>%s</color> (%s)",
                HEX[c.color] or "#FFFFFF", race:label(car), race:checkName(c))
        end
    end
    if #parts == 0 then
        return ""
    end
    return "Black die: " .. table.concat(parts, ", ")
end

function Hud.refresh(race)
    if not ready then
        return
    end
    local s = race:serialize()
    local title = "Formula D"
    if s.phase == "race" then
        title = title .. "  -  Round " .. s.round
    elseif s.phase == "grid" then
        title = title .. "  -  Grid roll"
    elseif s.phase == "finished" then
        title = title .. "  -  Finished"
    end
    Ui.value("fdr_title", title)

    -- Finishers first, in their places, so the panel ends as the result;
    -- the cars still racing are in the order they play this round.
    local standings, due = race:standings(), race:turn()
    for r = 1, MAX_ROWS do
        local car = standings[r]
        Ui.set("fdr_r" .. r, "active", tostring(car ~= nil))
        if car then
            local cells = carCells(race, car, r, due, s.laps)
            for _, c in ipairs(cols) do
                local cell = cells[c.id] or { "" }
                Ui.value(cellId(r, c), cell[1])
                Ui.set(cellId(r, c), "color", cell[2] or "#FFFFFF")
            end
        end
    end
    Ui.set("fdr_empty", "active", tostring(#standings == 0))
    Ui.value("fdr_checks", checkLine(race))
end

Hud.HEX = HEX
Hud.wearSummary = wearSummary

return Hud
