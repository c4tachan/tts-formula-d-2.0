-- Formula D advanced rules (Asmodee 2008, the "Rulebook Advanced" PDF in the
-- mod), without the optional rules.
--
-- The same shape as fd.rules.beginner: wear goes to six zones instead of one
-- pool, and what a move costs depends on what the car has left -- braking
-- past its brakes takes tires, and overshooting on its last tires spins it.

local Rules = {}

Rules.id = "advanced"
Rules.name = "Formula D advanced rules"

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
-- A car on no tires is still racing (it spins, see moveWear); losing more
-- than it has is out. Brakes and gearbox never put a car out by themselves.
-- The ids are the dashboard's (fd.data.dashboard). `short` heads the
-- standings column; `empty` says what racing on with none left means.
Rules.zones = {
    { id = "tires", name = "tire WP", short = "T", start = 6, eliminateAt = -1, empty = "overshoot 1 spins, more is out" },
    { id = "brakes", name = "brake WP", short = "B", start = 3, empty = "braking takes tires" },
    { id = "gearbox", name = "gearbox WP", short = "G", start = 3, empty = "one gear down at a time" },
    { id = "body", name = "body WP", short = "C", start = 3, eliminateAt = 0 },
    { id = "engine", name = "engine WP", short = "E", start = 3, eliminateAt = 0 },
    { id = "handling", name = "suspension WP", short = "S", start = 2, eliminateAt = 0 },
}

-- Rolling the top face of these gears strains every engine in 5th or 6th.
Rules.engineStrain = { [5] = 20, [6] = 30 }

-- The rules that do not apply in the pit lane (see fd.rules.beginner).
Rules.pitLaneExempt = { braking = true, downshift = true, collisions = true, engineStrain = true }

-- Cars in the pit lane play after those on the circuit.
Rules.pitLanePlaysLast = true

--- Whether a car on lap `lap` of `laps` may take the way into the pit lane:
-- at the end of any lap but the last.
function Rules.mayPit(lap, laps)
    return lap >= 1 and lap < laps
end

-- Gear cap on the turn after a pit stop, and the gear a quick stop leaves in.
Rules.pitMaxGear = 4

--- Zones a pit stop restores to their starting value: only the tires.
Rules.pitRestores = { "tires" }

-- Slipstreaming: a car ending its full roll right behind another, both in
-- 4th or higher and the one behind in no lower a gear, may go 3 further
-- round it (see Moves.slipstream). Carried into a corner, it loses a brake
-- WP (see moveWear).
Rules.slipstream = { minGear = 4, spaces = 3 }

-- Most gears a car may drop in one shift.
Rules.maxDownshift = 3

--- Most gears a car with `wear` may drop in one shift: one at a time, with
-- no gearbox left.
function Rules.downshiftLimit(wear)
    if (wear.gearbox or 0) <= 0 then
        return 0
    end
    return Rules.maxDownshift
end

-- Wear for skipping gears shifting down, by gears skipped.
local DOWNSHIFT = {
    { gearbox = 1 },
    { gearbox = 1, brakes = 1 },
    { gearbox = 1, brakes = 1, engine = 1 },
}

--- Wear for dropping `skipped` gears beyond the first (6th -> 4th skips 1).
function Rules.downshiftWear(skipped)
    local w = {}
    for z, pts in pairs(DOWNSHIFT[skipped] or DOWNSHIFT[#DOWNSHIFT]) do w[z] = pts end
    return w
end

-- Braking further than this is out of the race.
local MAX_BRAKE = 6

--- Whether leaving a corner `missed` stops short puts a car out: a
-- 2-stop corner with none made, a 3-stop corner with one or none.
function Rules.overshootOut(missed)
    return missed >= 2
end

--- What ending a move as `o` (a Moves.reach option) does to a car that had
-- `wear` before it. Returns:
--   wear   zone -> points lost
--   spin   true if the car spins: it lost its last tire WP overshooting,
--          or overshot by one on none
--   out    why it is out of the race, if it is
--
-- Braking costs a brake WP a space, the 4th space on a tire WP a space too
-- (3 brake and 1-3 tire); 7 or more is out. Brake WP the car does not have
-- come out of its tires. A slipstream into a corner costs a brake WP too.
-- Overshooting costs a tire WP a space, after the braking.
function Rules.moveWear(o, wear)
    local w = {}
    local out = nil
    local b = o.brake or 0
    if b > MAX_BRAKE then
        out = string.format("could not brake %d spaces", b)
    end
    local slipped = o.slipCorners or 0
    if b > 0 or slipped > 0 then
        local brakes = math.min(b, 3) + slipped
        local tires = math.max(0, b - 3)
        local have = math.max(0, wear.brakes or 0)
        if brakes > have then
            tires = tires + brakes - have
            brakes = have
        end
        if brakes > 0 then w.brakes = brakes end
        if tires > 0 then w.tires = tires end
    end
    local spin = nil
    local n = o.overshoot or 0
    if n > 0 then
        local t = (wear.tires or 0) - (w.tires or 0)
        if n < t then
            w.tires = (w.tires or 0) + n
        elseif n == t then
            w.tires = (w.tires or 0) + n
            spin = true
        elseif t <= 0 and n == 1 then
            spin = true
        else
            w.tires = (w.tires or 0) + n
            out = out or string.format("overshot corner %s by %d with %d tire WP left",
                tostring(o.corner), n, math.max(0, t))
        end
    end
    if Rules.overshootOut(o.missed or 0) then
        out = string.format("went through corner %s without its stops", tostring(o.corner))
    end
    return { wear = w, spin = spin, out = out }
end

-- Black die checks; see fd.rules.beginner for the outcome table.
Rules.checks = {
    start = {
        name = "start",
        resolve = function(v)
            if v == 1 then
                return { stall = true, text = "stalled -- no move this round, start in 1st next round" }
            elseif v >= 20 then
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
                return { wear = { engine = 1 }, text = "engine strain" }
            end
            return { text = "engine holds" }
        end,
    },
    collision = {
        name = "collision",
        resolve = function(v)
            if v == 1 then
                return { wear = { body = 1 }, text = "collision" }
            end
            return { text = "no contact" }
        end,
    },
    -- How long the mechanics take: a quick stop moves half the roll, rounded
    -- up, out of the pits at once in 4th gear; a slow one waits for the next
    -- round.
    pit = {
        name = "pit stop",
        resolve = function(v)
            if v <= 10 then
                local spaces = math.ceil(v / 2)
                return { bonus = spaces, text = string.format("quick stop! Move %d space%s out of the pits now, "
                    .. "in 4th gear", spaces, spaces == 1 and "" or "s") }
            end
            return { text = "slow stop -- wait in the pits; leave next round in 4th gear or lower" }
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
