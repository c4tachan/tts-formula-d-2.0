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

local function racePanel(rulesName)
    return el("Panel", {
        id = "fdr", rectAlignment = "UpperLeft", offsetXY = "20 -120", width = "380", height = "420",
        allowDragging = "true", returnToOriginalPositionWhenReleased = "false", color = PANEL_BG,
    }, {
        el("VerticalLayout", { padding = "8 8 6 6", spacing = "4", childForceExpandHeight = "false" }, {
            el("HorizontalLayout", { preferredHeight = "26", spacing = "4" }, {
                text("fdr_title", "Formula D", { fontSize = "18", fontStyle = "Bold", flexibleWidth = "1" }),
                button("fdr_min", "_", "fdToggleRace", { preferredWidth = "30", flexibleWidth = "0", tooltip = "Collapse" }),
            }),
            el("VerticalLayout", { id = "fdr_body", spacing = "4", childForceExpandHeight = "false", preferredHeight = "370" }, {
                text("fdr_rules", rulesName, { fontSize = "12", color = "#AAB0B8", preferredHeight = "16" }),
                text("fdr_cars", "No cars yet -- click Join race on a dashboard.", { preferredHeight = "180", fontSize = "15" }),
                text("fdr_checks", "", { preferredHeight = "40", color = "#FFB74D" }),
                el("HorizontalLayout", { spacing = "4", preferredHeight = "34" }, {
                    button("fdr_grid", "Grid roll", "fdGrid", { tooltip = "Everyone rolls the black die for grid position" }),
                    button("fdr_start", "Start", "fdStart", { tooltip = "Reset cars and roll for the start" }),
                    button("fdr_undo", "Undo", "fdUndo", { tooltip = "Undo the last change" }),
                    button("fdr_reset", "Reset", "fdReset", { tooltip = "Back to setup, keeping the drivers" }),
                    button("fdr_track", "Track", "fdTrack", { tooltip = "Show or hide the detected spaces on the board" }),
                }),
                el("HorizontalLayout", { spacing = "4", preferredHeight = "30" }, {
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

local collapsed = false
local editorText = ""

--- Append the race panel and any `extras` to the Global UI, then call `onReady`.
-- Safe to call again: it replaces the panels it added before.
function Hud.build(rulesName, extras, onReady)
    collapsed = false
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
        kept[#kept + 1] = racePanel(rulesName)
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
    Ui.set("fdr", "height", collapsed and "46" or "420")
    Ui.value("fdr_min", collapsed and "+" or "_")
end

local function wearSummary(race, car)
    local parts = {}
    for _, z in ipairs(race.rules.zones) do
        parts[#parts + 1] = math.max(0, car.wear[z.id]) .. " " .. z.name
    end
    return table.concat(parts, " ")
end

local function carLine(race, car, i)
    local hex = HEX[car.color] or "#FFFFFF"
    local status = nil
    if car.eliminated then
        status = "<color=#FF5252>OUT</color>"
    elseif car.place then
        status = "<color=#FFD740>" .. race:progress(car) .. "</color>"
    else
        status = (car.gear > 0 and Race.gearName(car.gear) or "grid")
            .. "  " .. wearSummary(race, car)
            .. (car.lastRoll and ("  last " .. car.lastRoll) or "")
        local lap = race:progress(car)
        if lap then
            status = lap .. "  " .. status
        end
    end
    return string.format("%d. <color=%s>%s</color>  %s", i, hex, race:label(car), status)
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

    -- Finishers first, in their places, so the panel ends as the result.
    local lines = {}
    for i, car in ipairs(race:standings()) do
        lines[i] = carLine(race, car, i)
    end
    Ui.value("fdr_cars", #lines > 0 and table.concat(lines, "\n") or "No cars yet -- click Join race on a dashboard.")
    Ui.value("fdr_checks", checkLine(race))
end

Hud.HEX = HEX
Hud.wearSummary = wearSummary

return Hud
