-- Buttons attached to the player dashboards. An unclaimed dashboard offers
-- "Join race"; a claimed one shows its car's status and the actions that are
-- not already covered by moving pieces (gear stick, wear marker) on it.
--
-- The buttons sit in a strip just past the printed bottom edge of whichever
-- face is up. Their click functions live in the Global script, which TTS calls
-- as fn(dashboard, playerColor, altClick).

local Dashboard = require("fd.tts.dashboard")

local Controls = {}

-- Button sizes are in TTS button units; roughly 500 per local unit here.
local EDGE_Z = 3.26       -- half depth of the dashboard model
local BUTTON_GAP = 0.45   -- button row, beyond the printed bottom edge
local LABEL_GAP = 0.95    -- status label, one row further out

-- Per face: which way along Z the art's bottom lies, how far off the model the
-- strip floats (local Y), how to turn a button so it faces out and reads
-- upright, and which way X runs for a button.
--
-- Button text reads for a viewer on the +Z side by default, so the advanced
-- face (printed bottom at +Z) needs no turn, while the beginner face needs an
-- in-plane 180 on top of the flip that points it out of the underside.
--
-- `xSign` is not the same on both faces: on the flipped face a button's X runs
-- opposite to positionToWorld, which is what the markers use. Set from what
-- the game actually draws -- the beginner row came out mirrored without it.
local FACES = {
    advanced = { down = 1, y = 0.7, rotation = { 0, 0, 0 }, xSign = -1 },
    beginner = { down = -1, y = -0.55, rotation = { 0, 180, 180 }, xSign = 1 },
}

local ACTIONS = {
    { fn = "fdDashCar", label = "Car", tip = "Claim the nearest car, or take one from the bag.\nAlso: drop a car on this dashboard." },
    { fn = "fdDashBrake", label = "Brake 1", tip = "Stop 1 space short of your roll (1 WP)" },
    { fn = "fdDashOvershoot", label = "Overshoot 1", tip = "Overshot a corner by 1 space (1 WP)" },
    { fn = "fdDashCollision", label = "Collision?", tip = "Ended next to or behind a car: roll the black die" },
    { fn = "fdDashWear", label = "WP -1 / +1", tip = "Left click: lose 1 WP. Right click: gain 1 WP.\nOr just move your WP marker." },
    { fn = "fdDashPit", label = "Pit stop", tip = "Restore WP; leave in 4th gear or lower" },
    { fn = "fdDashLeave", label = "Leave", tip = "Take your car out of the race" },
}

local rendered = {} -- guid -> key of what is currently drawn

local function rowZ(face, gap)
    return FACES[face].down * (EDGE_Z + gap)
end

local function button(dash, params, face)
    local f = FACES[face]
    params.function_owner = Global
    params.rotation = f.rotation
    params.position = { params.x, f.y, params.z }
    params.x, params.z = nil, nil
    dash.createButton(params)
end

local function drawJoin(dash, face)
    button(dash, {
        click_function = "fdDashJoin", label = "Join race", tooltip = "Race with this dashboard",
        x = 0, z = rowZ(face, BUTTON_GAP + 0.1), width = 1400, height = 260, font_size = 150,
        color = { 0.18, 0.49, 0.2 }, font_color = { 1, 1, 1 },
    }, face)
end

local function drawCar(dash, face, tint)
    -- Label first so it is button index 0 for editButton.
    button(dash, {
        click_function = "fdNoop", label = "", x = 0, z = rowZ(face, LABEL_GAP),
        width = 2600, height = 180, font_size = 110,
        color = { 0.08, 0.09, 0.11, 0.85 }, font_color = tint,
    }, face)
    local count = #ACTIONS
    local spacing = 1.75
    for i, a in ipairs(ACTIONS) do
        button(dash, {
            click_function = a.fn, label = a.label, tooltip = a.tip,
            x = FACES[face].xSign * (i - (count + 1) / 2) * spacing, z = rowZ(face, BUTTON_GAP),
            width = 430, height = 190, font_size = 70,
            color = { 0.23, 0.25, 0.28 }, font_color = { 1, 1, 1 },
        }, face)
    end
end

--- Draw the right buttons for `dash`. `car` is the race car claiming it, or
-- nil; `label` is the status text for a claimed dashboard.
function Controls.render(dash, car, label)
    local guid = dash.getGUID()
    local face = Dashboard.face(dash)
    local key = face .. "|" .. (car and car.color or "-")
    if rendered[guid] ~= key then
        dash.clearButtons()
        if car then
            drawCar(dash, face, Color.fromString(car.color))
        else
            drawJoin(dash, face)
        end
        rendered[guid] = key
    end
    if car then
        dash.editButton({ index = 0, label = label or "" })
    end
end

--- Forget what was drawn, so the next render starts from scratch (after a flip).
function Controls.invalidate(dash)
    rendered[dash.getGUID()] = nil
end

return Controls
