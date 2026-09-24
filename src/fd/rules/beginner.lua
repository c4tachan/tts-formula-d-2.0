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
                return { bonus = 4, text = "great start! Move 4 spaces now, still in 1st gear (may change 1-2 lanes)" }
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
