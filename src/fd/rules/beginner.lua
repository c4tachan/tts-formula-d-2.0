-- Formula D basic rules (Asmodee 2008, the "Rulebook Beginner" PDF in the mod).
--
-- A ruleset is data plus a few pure functions; fd.core.race does the
-- bookkeeping. Wear is always expressed as a map of zone id -> points, so the
-- advanced rules can route the same events to tires, brakes, gearbox and so on
-- without the engine changing. Here every zone is the single 18 WP pool.

local Rules = {}

Rules.id = "beginner"
Rules.name = "Formula D basic rules"

-- Spaces each gear's die can show.
Rules.gears = {
    { min = 1, max = 2 },
    { min = 2, max = 4 },
    { min = 4, max = 8 },
    { min = 7, max = 12 },
    { min = 11, max = 20 },
    { min = 21, max = 30 },
}

-- `eliminateAt`: a car is out once the zone falls to this value or below.
Rules.zones = {
    { id = "wp", name = "WP", start = 18, eliminateAt = 0 },
}

-- Rolling the top face of these gears strains every engine in 5th or 6th.
Rules.engineStrain = { [5] = 20, [6] = 30 }

-- Pit stops (the two-lap race): a car that ends a move in its own pit box
-- gets back the zones in `pitRestores` and leaves in `pitMaxGear` at most.
-- No exact roll is needed to get there.

-- The rules that do not apply in the pit lane: a move ending there brakes
-- for nothing (so a car stuck behind another loses nothing), and a car
-- there shifts down freely, collides with nothing and is spared engine
-- strain.
Rules.pitLaneExempt = { braking = true, downshift = true, collisions = true, engineStrain = true }

-- Cars in the pit lane play after those on the circuit.
Rules.pitLanePlaysLast = true

--- Whether a car on lap `lap` of `laps` may take the way into the pit lane:
-- at the end of any lap but the last -- in the two-lap race, between the
-- first and the second.
function Rules.mayPit(lap, laps)
    return lap >= 1 and lap < laps
end

-- Gear cap on the turn after a pit stop.
Rules.pitMaxGear = 4

-- Most gears a car may drop in one shift.
Rules.maxDownshift = 3

--- Wear for dropping `skipped` gears beyond the first (6th -> 4th skips 1).
function Rules.downshiftWear(skipped)
    return { wp = skipped }
end

--- Wear for braking `spaces` short of the die roll.
function Rules.brakeWear(spaces)
    return { wp = spaces }
end

--- Wear for overshooting a corner by `spaces`.
function Rules.overshootWear(spaces)
    return { wp = spaces }
end

--- Whether leaving a corner `missed` stops short puts a car out: a
-- 2-stop corner with none made, a 3-stop corner with one or none.
function Rules.overshootOut(missed)
    return missed >= 2
end

--- What ending a move as `o` (a Moves.reach option) does to a car that had
-- `wear` before it: { wear = zone -> points, spin, out = why }. Here the
-- wear is the same whatever the car has left, and nobody spins.
function Rules.moveWear(o, wear)
    local w = {}
    for _, part in ipairs({ Rules.brakeWear(o.brake or 0), Rules.overshootWear(o.overshoot or 0) }) do
        for z, pts in pairs(part) do
            if pts ~= 0 then w[z] = (w[z] or 0) + pts end
        end
    end
    local out = nil
    if Rules.overshootOut(o.missed or 0) then
        out = string.format("went through corner %s without its stops", tostring(o.corner))
    end
    return { wear = w, out = out }
end

--- Zones a pit stop restores to their starting value.
Rules.pitRestores = { "wp" }

-- Black die checks. `resolve(value)` returns an outcome table:
--   wear      zone -> points lost
--   stall     true when the car misses its first move
--   bonus     spaces to move immediately
--   text      what to announce
Rules.checks = {
    start = {
        name = "start",
        resolve = function(v)
            if v == 1 then
                return { stall = true, text = "stalled -- no move this round, start in 1st next round" }
            elseif v >= 17 then
                -- The 4 spaces are the car's whole first move: no 1st gear roll.
                return { bonus = 4, text = "great start! Move 4 spaces now (may change 1-2 lanes) -- that is "
                    .. "your move this round, instead of the 1st gear roll; shift to 2nd next round if you like" }
            end
            return { text = "normal start -- roll the 1st gear die" }
        end,
    },
    engine = {
        name = "engine",
        resolve = function(v)
            if v <= 4 then
                return { wear = { wp = 1 }, text = "engine strain" }
            end
            return { text = "engine holds" }
        end,
    },
    collision = {
        name = "collision",
        resolve = function(v)
            if v <= 4 then
                return { wear = { wp = 1 }, text = "collision" }
            end
            return { text = "no contact" }
        end,
    },
    -- Grid order: highest roll takes pole. The race engine handles ties.
    grid = {
        name = "grid position",
        resolve = function(v)
            return { text = "rolled " .. v .. " for the grid" }
        end,
    },
}

return Rules
