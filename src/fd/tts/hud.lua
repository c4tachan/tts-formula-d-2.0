-- The race panel everyone sees: standings, pending black die checks, and the
-- race-wide buttons. Per-player controls live on the dashboards (fd.tts.controls).
-- Built at load and appended to whatever the Global XML already holds, so the
-- Big Box menu button survives.

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
local PANEL_HEIGHT = 440

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

local function racePanel(rules, cols)
    return el("Panel", {
        id = "fdr", rectAlignment = "UpperLeft", offsetXY = "20 -120", width = "380", height = tostring(PANEL_HEIGHT),
        allowDragging = "true", returnToOriginalPositionWhenReleased = "false", color = PANEL_BG,
    }, {
        el("VerticalLayout", { padding = "8 8 6 6", spacing = "4", childForceExpandHeight = "false" }, {
            el("HorizontalLayout", { preferredHeight = "26", spacing = "4" }, {
                text("fdr_title", "Formula D", { fontSize = "18", fontStyle = "Bold", flexibleWidth = "1" }),
                button("fdr_min", "_", "fdToggleRace", { preferredWidth = "30", flexibleWidth = "0", tooltip = "Collapse" }),
            }),
            el("VerticalLayout", { id = "fdr_body", spacing = "4", childForceExpandHeight = "false", preferredHeight = tostring(PANEL_HEIGHT - 50) }, {
                text("fdr_rules", rules.name, { fontSize = "12", color = "#AAB0B8", preferredHeight = "16" }),
                standingsTable(cols),
                text("fdr_empty", "No cars yet -- click Join race on a dashboard.", { preferredHeight = "18" }),
                text("fdr_checks", "", { preferredHeight = "40", color = "#FFB74D" }),
                -- The race-wide buttons are for the host and promoted players
                -- only; Global checks again when one is pressed.
                el("HorizontalLayout", { spacing = "4", preferredHeight = "34", visibility = ADMIN }, {
                    button("fdr_grid", "Grid roll", "fdGrid", { tooltip = "Roll the black die for everyone and put the cars on the grid" }),
                    button("fdr_start", "Start", "fdStart", { tooltip = "Reset cars and roll for the start" }),
                    button("fdr_undo", "Undo", "fdUndo", { tooltip = "Undo the last change" }),
                    button("fdr_reset", "Reset", "fdReset", { tooltip = "Back to setup, keeping the drivers" }),
                    button("fdr_track", "Track", "fdTrack", { tooltip = "Show or hide the detected spaces on the board" }),
                }),
                el("HorizontalLayout", { spacing = "4", preferredHeight = "30", visibility = ADMIN }, {
                    button("fdr_laps", "1 lap", "fdLaps", { tooltip = "Race over one lap (basic rules) or two" }),
                    button("fdr_edit", "Edit track", "fdEdit", { tooltip = "Open or close the track editor for the map on the board" }),
                    button("fdr_apply", "Apply", "fdApply", { tooltip = "Put the space markers back into the track" }),
                    button("fdr_export", "Export", "fdExport", { tooltip = "How to get your edits into the repo" }),
                }),
                text("fdr_editor", "", { preferredHeight = "34", fontSize = "12", color = "#9FD3FF" }),
            }),
        }),
    })
end

local SEATS = { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink" }

--- The big button in the middle of a player's screen when the black die is
-- theirs to roll: one per seat, each shown only to its own, hidden until
-- asked for (see Hud.askToRoll).
local function rollButton(color)
    return el("Button", {
        id = "fdBlack_" .. color, visibility = color, active = "false",
        rectAlignment = "MiddleCenter", offsetXY = "0 120", width = "360", height = "96",
        text = "Roll the black die", fontSize = "30", fontStyle = "Bold", textColor = "#FFFFFF",
        colors = "#1B1D21F0|#2E3238F0|#0E0F11F0|#1B1D2180", outline = HEX[color], outlineSize = "4 -4",
        onClick = "fdRollBlack", tooltip = "Rolls it for you; the result is in the chat",
    })
end

local collapsed = false
local editorText = ""
local cols = {}

--- Append the race panel for `rules` and any `extras` to the Global UI, then
-- call `onReady`. Safe to call again: it replaces the panels it added before.
function Hud.build(rules, extras, onReady)
    collapsed = false
    cols = columns(rules)
    -- Hold updates until the new XML has loaded: sent now, they would be lost
    -- with the old elements yet remembered by fd.tts.ui, and the refresh in
    -- onReady would then skip them as repeats.
    ready = false
    Wait.condition(function()
        local xml = UI.getXmlTable() or {}
        local kept = {}
        for _, node in ipairs(xml) do
            local id = node.attributes and node.attributes.id or ""
            if id:sub(1, 2) ~= "fd" then
                kept[#kept + 1] = node
            end
        end
        kept[#kept + 1] = racePanel(rules, cols)
        for _, c in ipairs(SEATS) do
            kept[#kept + 1] = rollButton(c)
        end
        for _, node in ipairs(extras or {}) do
            kept[#kept + 1] = node
        end
        UI.setXmlTable(kept)
        Ui.reset()           -- every element is back to what the XML says
        Wait.frames(function()
            Wait.condition(function()
                ready = true
                Ui.value("fdr_editor", editorText)
                onReady()
            end, function() return not UI.loading end)
        end, 2)
    end, function() return not UI.loading end)
end

--- Show the black die button to `color` alone, or (nil) to nobody.
function Hud.askToRoll(color)
    if not ready then
        return
    end
    for _, c in ipairs(SEATS) do
        Ui.set("fdBlack_" .. c, "active", tostring(c == color))
    end
end

--- The track editor's status line; nil hides it.
function Hud.setEditor(textValue)
    editorText = textValue or ""
    if not ready then
        return
    end
    Ui.value("fdr_editor", textValue or "")
end

function Hud.toggleRace()
    collapsed = not collapsed
    Ui.set("fdr_body", "active", tostring(not collapsed))
    Ui.set("fdr", "height", collapsed and "46" or tostring(PANEL_HEIGHT))
    Ui.value("fdr_min", collapsed and "+" or "_")
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
        if car then
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
    Ui.value("fdr_laps", s.laps == 1 and "1 lap" or (s.laps .. " laps"))

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
