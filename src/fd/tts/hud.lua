-- The race panel everyone sees, on the screen: standings, pending black die
-- checks, the rulebook, the issue link, and Undo. Per-player controls live on the
-- dashboards (fd.tts.controls), the race-wide ones on the setup menu
-- (fd.tts.setup).
--
-- Hud.build also sends the Global UI, appended to whatever the Global XML
-- already holds.

local Race = require("fd.core.race")
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

-- Width of a wear column: one zone headed by its name, or one of several
-- headed by its letter (the name in its tooltip).
local ZONE_WIDTH = 36
local ZONES_WIDTH = 18

--- The standings columns: width 0 takes what the others leave. A column per
-- wear zone, so the cells need no unit.
local function columns(rules)
    local cols = {
        { id = "pos", head = "#", width = 22, align = "MiddleRight" },
        { id = "driver", head = "Driver", width = 0 },
        { id = "gear", head = "Gear", width = 40 },
    }
    local several = #rules.zones > 1
    for _, z in ipairs(rules.zones) do
        cols[#cols + 1] = {
            id = "w_" .. z.id, head = several and (z.short or z.name) or z.name, tip = z.name,
            width = several and ZONES_WIDTH or ZONE_WIDTH, zone = z.id, align = "MiddleRight",
        }
    end
    cols[#cols + 1] = { id = "lap", head = "Lap", width = 36 }
    cols[#cols + 1] = { id = "roll", head = "Roll", width = 34, align = "MiddleRight" }
    cols[#cols + 1] = { id = "status", head = "", width = 70 }
    return cols
end

local function cellId(row, col)
    return "fdr_r" .. row .. "_" .. col.id
end

--- The standings, with the zone names as tooltips on their letters.
local function standingsTable(cols)
    local widths, head = {}, {}
    for i, c in ipairs(cols) do
        widths[i] = tostring(c.width)
        head[i] = el("Cell", nil, {
            text(nil, c.head, { fontSize = "12", color = "#AAB0B8", alignment = c.align or "MiddleLeft", tooltip = c.tip }),
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

-- With one wear column; each more widens it.
local PANEL_WIDTH = 380

--- The panel's width for the columns `cols`.
local function panelWidth(cols)
    local w = PANEL_WIDTH - ZONE_WIDTH
    for _, c in ipairs(cols) do
        if c.zone then w = w + c.width end
    end
    return w
end

-- Where it sits on the screen; players can drag it.
local ON_SCREEN = {
    rectAlignment = "UpperLeft", offsetXY = "20 -120",
    allowDragging = "true", returnToOriginalPositionWhenReleased = "false",
}

--- The panel.
local function racePanel(rules, cols)
    local attrs = { id = "fdr", width = tostring(panelWidth(cols)), height = tostring(PANEL_HEIGHT), color = PANEL_BG }
    for k, v in pairs(ON_SCREEN) do attrs[k] = v end
    return el("Panel", attrs, {
        el("VerticalLayout", { padding = "8 8 6 6", spacing = "4", childForceExpandHeight = "false" }, {
            el("HorizontalLayout", { spacing = "4", preferredHeight = "26", childForceExpandWidth = "false" }, {
                text("fdr_title", "Formula D", { fontSize = "18", fontStyle = "Bold", flexibleWidth = "1" }),
                -- For everyone: hands the clicker the rulebook (fdRules).
                button("fdr_rules_book", "Rules", "fdRules", {
                    preferredWidth = "64", tooltip = "The rulebook, in front of your seat. Again to put it away.",
                }),
                -- Also on the setup menu: the issue tracker's link (fdReportIssue).
                button("fdr_issue", "Report", "fdReportIssue", {
                    preferredWidth = "64",
                    tooltip = "Report a bug or an idea: the link to the issue tracker",
                }),
            }),
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

local cols = {}

-- Longest to wait for the UI to finish loading, in seconds. Should TTS
-- never say it has, the panels go on regardless rather than never at all.
local LOAD_WAIT = 5

--- Run `fn` once `ui` (the screen's UI, or an object's) has loaded.
local function whenLoaded(ui, fn)
    Wait.condition(fn, function() return ui == nil or not ui.loading end, LOAD_WAIT, fn)
end

--- Put the race panel on the screen with any `extras`, appended to the
-- Global UI, then call `onReady`. Safe to call again: it replaces what it
-- put there before. A game saved while the panel lay on the board `tile`
-- has it there still: it is taken off.
function Hud.build(rules, extras, tile, onReady)
    cols = columns(rules)
    -- Hold updates until the new XML has loaded: sent now, they would be lost
    -- with the old elements yet remembered by fd.tts.ui, and the refresh in
    -- onReady would then skip them as repeats.
    ready = false
    whenLoaded(UI, function()
        local xml = UI.getXmlTable() or {}
        local kept = {}
        for _, node in ipairs(xml) do
            local id = node.attributes and node.attributes.id or ""
            if id:sub(1, 2) ~= "fd" then
                kept[#kept + 1] = node
            end
        end
        kept[#kept + 1] = racePanel(rules, cols)
        for _, node in ipairs(extras or {}) do
            kept[#kept + 1] = node
        end
        UI.setXmlTable(kept)
        Ui.reset()           -- every element is back to what the XML says
        Wait.frames(function()
            whenLoaded(UI, function()
                -- Only if there is one: TTS fails inside on an empty table
                -- ("Object reference not set to an instance of an object"),
                -- so it is cleared with an empty string.
                local had = tile and tile.UI.getXmlTable()
                if had and #had > 0 then tile.UI.setXml("") end
                ready = true
                onReady()
            end)
        end, 2)
    end)
end

--- "12 WP", or with several zones each by its letter: "T5 B3 G2 C3 E3 S2".
local function wearSummary(race, car)
    local zones = race.rules.zones
    if #zones == 1 then
        return math.max(0, car.wear[zones[1].id] or 0) .. " " .. zones[1].name
    end
    local parts = {}
    for _, z in ipairs(zones) do
        parts[#parts + 1] = (z.short or z.name) .. math.max(0, car.wear[z.id] or 0)
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
        -- A zone worn away that the car races on without stands out.
        for _, z in ipairs(race.rules.zones) do
            local left = math.max(0, car.wear[z.id] or 0)
            cells["w_" .. z.id] = { tostring(left), left == 0 and "#FFB74D" or nil }
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
