-- The setup menu: a welcome in the middle of everyone's screen from the load
-- until the race starts. It says how to get a game going, shows the rules the
-- host has picked, and holds the one button that starts the race -- the grid
-- is rolled and the race begun in the same click (see fdSetupStart).
--
-- Everyone sees it; the buttons are for the host and promoted players: the
-- rules, Start race, and the track tools. It comes back once the race is
-- over, and stays up while the track editor is open, so the editor can
-- always be closed.

local Ui = require("fd.tts.ui")

local Setup = {}

local REPO = "https://github.com/c4tachan/tts-formula-d-2.0/issues"

local PANEL_BG = "#15181CF2"
local DIM = "#AAB0B8"
local ADMIN = "Host|Admin"

-- A button's colours, normal and picked: the picked one stands out.
local COLORS = "#3A3F47|#4E555F|#2A2E34|#3A3F4780"
local PICKED = "#2E7D32|#388E3C|#1B5E20|#2E7D3280"

local ready = false
local editorText = ""
local noRace = true -- whether the last refresh found no race on

local function el(tag, attrs, children, value)
    return { tag = tag, attributes = attrs or {}, children = children or {}, value = value }
end

local function text(id, value, extra)
    local a = { id = id, color = "#FFFFFF", fontSize = "14", alignment = "UpperLeft" }
    for k, v in pairs(extra or {}) do a[k] = v end
    return el("Text", a, nil, value)
end

local function button(id, label, onClick, extra)
    local a = { id = id, text = label, onClick = onClick, fontSize = "14", colors = COLORS, textColor = "#FFFFFF" }
    for k, v in pairs(extra or {}) do a[k] = v end
    return el("Button", a)
end

local STEPS = table.concat({
    "<b>1.</b> Take a coloured seat. Everyone seated is dealt a dashboard and a car when the race starts.",
    "<b>2.</b> The host picks a map and the rules, below.",
    "<b>3.</b> The host presses <b>Start race</b>: the grid is rolled, the cars put on it, and the race begins.",
    "<b>4.</b> On your turn: click a gear on your screen dashboard, press <b>Roll</b>, then move your car. "
        .. "The spaces it can reach are marked on the board.",
}, "\n")

-- The map list's labels, to the map ids they stand for.
local mapIds = {}

--- The map behind a label in the map list, as fdSetupMap is handed it.
function Setup.mapFor(label)
    return mapIds[label]
end

--- The map list: those with track data first, the rest marked as without.
local function mapList(maps)
    local options = {}
    mapIds = {}
    for _, ready in ipairs({ true, false }) do
        for _, m in ipairs(maps) do
            if m.ready == ready then
                local label = ready and m.name or (m.name .. "  (no track data)")
                mapIds[label] = m.id
                options[#options + 1] = el("Option", m.current and { selected = "true" } or {}, nil, label)
            end
        end
    end
    return el("Dropdown", {
        id = "fds_maps", onValueChanged = "fdSetupMap", preferredWidth = "260", fontSize = "13",
    }, options)
end

--- The panel, for Hud.build to add to the Global UI. `maps` lists the maps
-- to choose from: { id, name, ready (has track data), current }.
function Setup.panel(maps)
    -- The host's choices: the map, then the race distance.
    local choices = { mapList(maps or {}) }
    choices[#choices + 1] = text(nil, "Laps:", { preferredWidth = "40", alignment = "MiddleRight" })
    choices[#choices + 1] = el("InputField", {
        id = "fds_laps", onEndEdit = "fdSetupLaps", inputType = "IntegerNumber", characterLimit = "2",
        preferredWidth = "50", fontSize = "14", alignment = "MiddleCenter",
        tooltip = "How many laps the race lasts",
    }, nil, "1")
    local tools = {
        button("fds_track", "Track", "fdTrack", { tooltip = "Show or hide the detected spaces on the board" }),
        button("fds_edit", "Edit track", "fdEdit", { tooltip = "Open or close the track editor for the map on the board" }),
        button("fds_layout", "Layout", "fdLayout", { tooltip = "Let the board be right-clicked, to move the dice and the race panel" }),
        button("fds_apply", "Apply", "fdApply", { tooltip = "Put the space markers back into the track" }),
        button("fds_export", "Export", "fdExport", { tooltip = "How to get your edits into the repo" }),
        button("fds_reset", "Reset", "fdReset", { tooltip = "Back to setup, keeping the drivers (Undo restores it)" }),
    }
    return el("Panel", {
        -- Hidden until the first refresh says the race has not started, so a
        -- rebuild during the race does not flash it up.
        id = "fds", active = "false",
        rectAlignment = "MiddleCenter", width = "560", height = "580", color = PANEL_BG,
        allowDragging = "true", returnToOriginalPositionWhenReleased = "false",
    }, {
        el("VerticalLayout", { padding = "16 16 12 12", spacing = "6", childForceExpandHeight = "false" }, {
            text(nil, "Welcome to Formula D", { fontSize = "22", fontStyle = "Bold", preferredHeight = "30" }),
            text(nil, STEPS, { preferredHeight = "130" }),
            text(nil, "<b>This race</b>", { fontSize = "16", preferredHeight = "22" }),
            text("fds_map", "", { preferredHeight = "20" }),
            text("fds_rules", "", { preferredHeight = "20" }),
            text("fds_drivers", "", { preferredHeight = "38" }),
            el("HorizontalLayout", { spacing = "6", preferredHeight = "32", visibility = ADMIN, childForceExpandWidth = "false" },
                choices),
            button("fds_start", "Start race", "fdSetupStart", {
                preferredHeight = "40", fontSize = "18", fontStyle = "Bold", visibility = ADMIN, colors = PICKED,
                tooltip = "Roll the grid, put the cars on it and start the race",
            }),
            text("fds_wait", "The host starts the race once everyone has a seat.",
                { preferredHeight = "20", color = DIM }),
            el("HorizontalLayout", { spacing = "4", preferredHeight = "28", visibility = ADMIN }, tools),
            text("fds_editor", "", { preferredHeight = "34", fontSize = "12", color = "#9FD3FF", visibility = ADMIN }),
            text(nil, "Found a bug, or have an idea? Report it here (select the link to copy it):",
                { preferredHeight = "20", fontSize = "12", color = DIM }),
            el("InputField", { id = "fds_link", readOnly = "true", preferredHeight = "26", fontSize = "13" }, nil, REPO),
        }),
    })
end

function Setup.setReady(on)
    ready = on ~= false
end

--- The track editor's status line; nil while the editor is closed. The
-- menu stays up while there is one.
function Setup.setEditor(textValue)
    editorText = textValue or ""
    if not ready then
        return
    end
    Ui.value("fds_editor", editorText)
    Ui.set("fds", "active", tostring(noRace or editorText ~= ""))
end

--- Who will race: the drivers already in, and the names of the players
-- seated but not yet dealt in.
local function driverList(race, seated)
    local names = {}
    for _, car in ipairs(race:cars()) do
        names[#names + 1] = race:label(car)
    end
    for _, name in ipairs(seated or {}) do
        names[#names + 1] = name
    end
    if #names == 0 then
        return "Drivers: none yet -- take a coloured seat to join."
    end
    return "Drivers (" .. #names .. "): " .. table.concat(names, ", ")
end

--- Whether the menu shows for a race in `phase`: whenever no race is on.
function Setup.shows(phase)
    return phase ~= "race"
end

--- Show the menu while no race is on, filled in from `race`. `map` is the
-- map on the board ({ name, hasTrack }), or nil if it is not one we know,
-- and `seated` the names of the players seated but not yet dealt in; both
-- only looked at while the menu shows.
function Setup.refresh(race, map, seated)
    if not ready then
        return
    end
    local s = race:serialize()
    noRace = Setup.shows(s.phase)
    local open = noRace or editorText ~= ""
    Ui.set("fds", "active", tostring(open))
    Ui.value("fds_editor", editorText)
    if not open then
        return
    end
    if not map then
        Ui.value("fds_map", "Map: not one the mod knows")
    elseif map.hasTrack then
        Ui.value("fds_map", "Map: " .. map.name)
    else
        Ui.value("fds_map", "Map: " .. map.name
            .. "  <color=#FFB74D>(no track data yet: place the cars and judge moves by hand)</color>")
    end
    Ui.value("fds_rules", "Rules: " .. race.rules.name .. ", " .. (s.laps == 1 and "1 lap" or (s.laps .. " laps")))
    Ui.value("fds_drivers", driverList(race, seated))
    Ui.value("fds_laps", s.laps)
end

--- The most laps the field takes.
Setup.MAX_LAPS = 99

Setup.REPO = REPO

return Setup
