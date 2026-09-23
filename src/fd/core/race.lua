-- Race state and rule bookkeeping. No TTS calls: the Global script feeds in
-- what happened (a shift, a die result, a button) and relays the events this
-- produces. Nothing here refuses an action -- illegal moves are applied with a
-- warning, so a rules bug or a table-talk ruling can never wedge a game.
--
-- `state` is plain data so it can go straight through JSON for onSave and undo.

local Moves = require("fd.core.moves")
local Position = require("fd.core.position")

local Race = {}
Race.__index = Race

local ORDINAL = { "1st", "2nd", "3rd", "4th", "5th", "6th" }

local function gearName(g)
    return ORDINAL[g] or ("gear " .. tostring(g))
end

--- 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th ... 21st.
local function placeName(n)
    local suffix = "th"
    if n % 100 < 11 or n % 100 > 13 then
        suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
    end
    return n .. suffix
end

-- How far a car may be put from where it started a move and still have the
-- move checked for crossing the line, when the space is not one the roll
-- reaches: well past the longest roll.
local LINE_SEARCH = 60

-- Cars closer than this along the track, in cells, are level for turn
-- order. Staggered lanes put the spaces beside each other half a cell apart.
local LEVEL = 0.25

function Race.new(rules, saved)
    local self = setmetatable({ rules = rules, events = {} }, Race)
    self.state = saved or {}
    local s = self.state
    s.phase = s.phase or "setup" -- setup | grid | race | finished
    s.round = s.round or 0
    s.order = s.order or {}
    s.cars = s.cars or {}
    s.checks = s.checks or {}
    s.packs = s.packs or {} -- id -> collision record, see checkCollisions
    s.lastPack = s.lastPack or 0
    s.laps = s.laps or 1
    s.finishers = s.finishers or {} -- colors, in the order they finished
    for _, car in pairs(s.cars) do
        car.lap = car.lap or 0
    end
    return self
end

function Race:serialize()
    return self.state
end

-- Events --------------------------------------------------------------------

-- level: info | warn | wear | out | finish
function Race:emit(level, text, color)
    self.events[#self.events + 1] = { level = level, text = text, color = color }
end

--- Take the events produced since the last call.
function Race:drain()
    local e = self.events
    self.events = {}
    return e
end

-- Cars ----------------------------------------------------------------------

function Race:car(color)
    return self.state.cars[color]
end

function Race:label(car)
    return car.name or car.color
end

local function freshWear(rules)
    local w = {}
    for _, z in ipairs(rules.zones) do
        w[z.id] = z.start
    end
    return w
end

-- `space` is not reset: a reset or a fresh start does not move the cars on
-- the board. The move and corner stops are, as they belong to the race
-- being thrown away.
local function resetCar(rules, car)
    car.gear = 0         -- selected on the dashboard
    car.rolledGear = 0   -- gear of the last die actually rolled; 0 = on the grid
    car.wear = freshWear(rules)
    car.eliminated = false
    car.lastRoll = nil
    car.maxGear = nil
    car.movedRound = nil
    car.stalledRound = nil
    car.move = nil       -- the move since the last roll; see startMove
    car.stops = nil      -- stops made in the corner `space` is in
    car.crashed = nil    -- corner the car went out in, missing its stops
    car.lap = 0          -- lap it is on; 0 until it first crosses the line
    car.place = nil      -- where it finished, once it has
end

function Race:join(color, name)
    local s = self.state
    if s.cars[color] then
        self:emit("info", self:label(s.cars[color]) .. " is already racing", color)
        return s.cars[color]
    end
    local car = { color = color, name = name, tts = {} }
    resetCar(self.rules, car)
    s.cars[color] = car
    s.order[#s.order + 1] = color
    self:emit("info", self:label(car) .. " joins the race", color)
    return car
end

function Race:leave(color)
    local s = self.state
    local car = s.cars[color]
    if not car then return end
    s.cars[color] = nil
    for i = #s.order, 1, -1 do
        if s.order[i] == color then table.remove(s.order, i) end
    end
    self:dropChecks(color)
    self:emit("info", self:label(car) .. " leaves the race", color)
    if car.place then
        self:unfinish(car)
    end
    self:checkRaceOver()
end

--- Cars in race order.
function Race:cars()
    local out = {}
    for _, color in ipairs(self.state.order) do
        out[#out + 1] = self.state.cars[color]
    end
    return out
end

--- The car is now on the space `spaceId`, or off the track if nil.
--
-- With `track`, a car put down during its move has the move judged: see
-- Race:judgeMove. Without it -- a car claimed where it stands, or the board
-- re-read after an undo -- it is only noted, silently: cars are picked up
-- and put down all the time, and the board shows where they are.
function Race:placed(color, spaceId, track)
    if track then
        self:useTrack(track)
    end
    local car = self:car(color)
    if not car then return end
    if spaceId ~= car.space then
        car.stops = nil
    end
    car.space = spaceId
    if track and spaceId and car.move then
        self:judgeMove(car, track)
    end
    -- The round moves on at the last car's roll, before it is put down:
    -- until somebody moves in the new round, its order can still change.
    if self.state.phase == "race" and not self:anyMoved() and self:reorder() then
        self:emit("info", "Order of play for round " .. self.state.round .. ": " .. self:orderText())
    end
end

--- A car is about to move `roll` spaces: note where from, the stops it has
-- made in the corner there, and where the other cars are -- they are what
-- it has to get round, wherever they go afterwards.
function Race:startMove(car, roll)
    if not car.space then
        car.move = nil
        return
    end
    local occupied = {}
    for _, o in ipairs(self:cars()) do
        if o ~= car and o.space and not o.eliminated then
            occupied[#occupied + 1] = o.space
        end
    end
    -- Not state: lets the Global script show the new move's options.
    self.opened = car.color
    car.move = {
        from = car.space, roll = roll, stops = car.stops, occupied = occupied,
        charged = { brake = 0, overshoot = 0 }, -- spaces charged for so far
        crossed = false, -- whether a crossing of the line was counted for it
        pack = nil,      -- id of the collisions it set off, see checkCollisions
    }
end

--- Where the car of `color` can end the move it has open, as Moves.reach
-- gives it (space id -> option), with this ruleset's costs; nil if it has
-- no move open or started off the track data.
function Race:reachable(color, track)
    local car = self:car(color)
    local m = car and car.move
    if not m then
        return nil
    end
    local occupied = {}
    for _, id in ipairs(m.occupied) do occupied[id] = true end
    return Moves.reach(track, m.from, m.roll, {
        occupied = occupied, stops = m.stops,
        cost = function(o) return self:moveCost(o) end,
    })
end

--- Whether ending a move as `o` (a Moves.reach option) puts the car out.
function Race:moveOut(o)
    return self.rules.overshootOut(o.missed)
end

--- How bad ending a move this way is, to choose between two ways there.
function Race:moveCost(o)
    local rules, total = self.rules, 0
    for _, wear in ipairs({ rules.brakeWear(o.brake), rules.overshootWear(o.overshoot) }) do
        for _, pts in pairs(wear) do total = total + pts end
    end
    if self:moveOut(o) then
        total = total + 1000
    end
    return total
end

--- Charge (or give back) the difference between what the move has cost so
-- far and `spaces` of `kind` ("brake" or "overshoot").
function Race:chargeMove(car, kind, spaces, reason)
    local m = car.move
    local delta = spaces - m.charged[kind]
    m.charged[kind] = spaces
    local wearOf = kind == "brake" and self.rules.brakeWear or self.rules.overshootWear
    if delta > 0 then
        self:applyWear(car, wearOf(delta), reason)
    elseif delta < 0 then
        self:refund(car, wearOf(-delta), "move changed")
    end
end

--- Judge where the car was put down against the roll: brake for spaces
-- short, overshoot for a corner left too early, out for missing too many
-- stops, a lap for crossing the line, a collision check for each car it
-- ends up next to. Put down again, it is judged again and only the
-- difference is charged. A space the roll cannot reach is warned
-- about and charged nothing -- the track data may be wrong, or the table may
-- have ruled -- but still counts as crossing the line if the shortest way
-- there does, so a disputed move cannot keep a car from finishing.
function Race:judgeMove(car, track)
    local m = car.move
    local reach = self:reachable(car.color, track)
    local o = reach and reach[car.space]
    local who = self:label(car)
    if not o then
        self:emit("warn", string.format("%s: that space is not a legal %d from %s -- nothing charged for the move",
            who, m.roll, m.from), car.color)
        self:chargeMove(car, "brake", 0)
        self:chargeMove(car, "overshoot", 0)
        car.crashed = nil
        self:checkElimination(car)
        local any = Moves.reach(track, m.from, LINE_SEARCH)
        local way = any and any[car.space]
        self:crossLine(car, way and way.crossed or false)
        self:checkCollisions(car, track)
        return
    end
    car.stops = o.stops
    self:chargeMove(car, "brake", o.brake, string.format("braked %d short", o.brake))
    self:chargeMove(car, "overshoot", o.overshoot,
        string.format("overshot corner %s by %d", tostring(o.corner), o.overshoot))
    local crash = nil
    if self:moveOut(o) then
        crash = o.corner
    end
    car.crashed = crash
    self:checkElimination(car)
    -- Last, so a car that goes out on the move does not take the flag.
    self:crossLine(car, o.crossed)
    self:checkCollisions(car, track)
end

--- Which cars touch which, among the pack `car` is in: every car it can
-- be reached from through cars touching (`track.near`), as color -> colors
-- in race order. Cars out of the race or finished are not on the track.
function Race:pack(car, track)
    local near = track.near
    local running = {}
    for _, o in ipairs(self:cars()) do
        if o.space and not o.eliminated and not o.place then running[#running + 1] = o end
    end
    local function touching(o)
        local spaces, out = {}, {}
        for _, id in ipairs(near and near[o.space] or {}) do spaces[id] = true end
        for _, p in ipairs(running) do
            if p ~= o and spaces[p.space] then out[#out + 1] = p.color end
        end
        return out
    end
    local pack, todo = {}, { car }
    while #todo > 0 do
        local o = table.remove(todo)
        if not pack[o.color] then
            pack[o.color] = touching(o)
            for _, color in ipairs(pack[o.color]) do
                todo[#todo + 1] = self:car(color)
            end
        end
    end
    return pack
end

--- `car` rolls for a collision with the car of color `with`, as part of
-- the contact recorded as pack `id` -- unless it already has.
function Race:queueCollision(car, with, id)
    local done = self.state.packs[id].pairs
    local key = car.color .. ">" .. with
    if done[key] then
        return
    end
    if self:queueCheck(car, "collision", with, id) then
        done[key] = "queued"
    end
end

--- The move ended among other cars: it rolls once against each car it
-- touches, and each roll spreads (see Race:collided) until every pair of
-- touching cars in the pack has rolled twice, once each way.
--
-- What touched what is recorded when the move is judged, as a pack in
-- `state.packs` that its checks point to: the rolls it sets off can come in
-- long after the mover has moved on. Put down again, the pack is redrawn,
-- and the mover's own checks for cars it no longer touches are dropped if
-- not yet rolled; what was rolled stands.
function Race:checkCollisions(car, track)
    local s, m = self.state, car.move
    if not m.pack or not s.packs[m.pack] then
        s.lastPack = s.lastPack + 1
        m.pack = "p" .. s.lastPack
        s.packs[m.pack] = { touching = {}, pairs = {} }
    end
    local pack = s.packs[m.pack]
    pack.touching = {}
    if not car.eliminated and not car.place then
        pack.touching = self:pack(car, track)
    end
    local wanted = {}
    for _, color in ipairs(pack.touching[car.color] or {}) do wanted[color] = true end
    local checks = s.checks
    for i = #checks, 1, -1 do
        local c = checks[i]
        local key = c.with and (c.color .. ">" .. c.with)
        if c.color == car.color and c.pack == m.pack and key and not wanted[c.with]
                and pack.pairs[key] == "queued" then
            table.remove(checks, i)
            pack.pairs[key] = nil
            local other = self:car(c.with)
            self:emit("info", string.format("%s is no longer next to %s -- collision check dropped",
                self:label(car), other and self:label(other) or c.with), car.color)
        end
    end
    for _, color in ipairs(pack.touching[car.color] or {}) do
        self:queueCollision(car, color, m.pack)
    end
    self:prunePacks()
end

--- A collision check was rolled: the car it was against rolls back, and
-- against every other car touching it, so the contact spreads through the
-- pack.
function Race:collided(check)
    local pack = self.state.packs[check.pack]
    if not pack then
        return
    end
    pack.pairs[check.color .. ">" .. check.with] = "rolled"
    local hit = self:car(check.with)
    if hit and not hit.eliminated and not hit.place then
        self:queueCollision(hit, check.color, check.pack)
        for _, color in ipairs(pack.touching[hit.color] or {}) do
            self:queueCollision(hit, color, check.pack)
        end
    end
    self:prunePacks()
end

--- Forget the packs nothing needs: no check waiting on one, and no car
-- whose move could be put down again and redraw it.
function Race:prunePacks()
    local s, used = self.state, {}
    for _, c in ipairs(s.checks) do
        if c.pack then used[c.pack] = true end
    end
    for _, car in pairs(s.cars) do
        if car.move and car.move.pack then used[car.move.pack] = true end
    end
    for id in pairs(s.packs) do
        if not used[id] then s.packs[id] = nil end
    end
end

-- Laps and the finish -------------------------------------------------------
-- Every grid lies behind the line, so the first crossing starts lap 1 and
-- the one after the last lap finishes the race.

--- Count (or take back) the current move's crossing of the line.
function Race:crossLine(car, crossed)
    local m = car.move
    if (m.crossed or false) == crossed then
        return
    end
    m.crossed = crossed
    local laps = self.state.laps
    car.lap = car.lap + (crossed and 1 or -1)
    if crossed and car.lap > 1 and car.lap <= laps then
        self:emit("info", string.format("%s starts lap %d of %d%s", self:label(car), car.lap, laps,
            car.lap == laps and " -- last lap" or ""), car.color)
    end
    self:settleFinish(car)
end

--- Put the car in or out of the finishing order by its lap and whether it
-- is out: one past the last lap and still running has finished. Every
-- change that can touch either comes through here, so a car is never both
-- finished and out.
function Race:settleFinish(car)
    local s = self.state
    if s.phase ~= "race" and s.phase ~= "finished" then
        return
    end
    local home = car.lap > s.laps and not car.eliminated
    if home and not car.place then
        self:finish(car)
    elseif not home and car.place then
        self:unfinish(car)
        self:emit("info", self:label(car) .. " has not finished after all", car.color)
    end
    self:checkRaceOver()
end

--- The car has taken the flag: note its place.
function Race:finish(car)
    local s = self.state
    s.finishers[#s.finishers + 1] = car.color
    car.place = #s.finishers
    self:dropChecks(car.color)
    if car.place == 1 then
        self:emit("finish", self:label(car) .. " wins the race!", car.color)
    else
        self:emit("finish", self:label(car) .. " finishes " .. placeName(car.place), car.color)
    end
end

--- Take a car back out of the finishing order; those behind it move up.
function Race:unfinish(car)
    local s = self.state
    for i = #s.finishers, 1, -1 do
        if s.finishers[i] == car.color then table.remove(s.finishers, i) end
    end
    car.place = nil
    for i, color in ipairs(s.finishers) do
        s.cars[color].place = i
    end
end

--- The race is over once a car has finished and every other has finished
-- or is out; a correction that puts a car back in the running reopens it.
function Race:checkRaceOver()
    local s = self.state
    if s.phase ~= "race" and s.phase ~= "finished" then
        return
    end
    local over = #s.finishers > 0
    for _, car in ipairs(self:cars()) do
        if not car.place and not car.eliminated then
            over = false
        end
    end
    if over and s.phase == "race" then
        s.phase = "finished"
        local names = {}
        for i, car in ipairs(self:standings()) do
            names[i] = (car.place and placeName(car.place) or "out") .. " " .. self:label(car)
        end
        self:emit("finish", "Chequered flag! Result: " .. table.concat(names, ", "))
    elseif not over and s.phase == "finished" then
        s.phase = "race"
        self:emit("info", "The race is back on")
    end
end

--- Cars finished, in their places, then those still running in race order,
-- then those out.
function Race:standings()
    local out = {}
    for _, color in ipairs(self.state.finishers) do
        out[#out + 1] = self.state.cars[color]
    end
    for _, car in ipairs(self:cars()) do
        if not car.place and not car.eliminated then out[#out + 1] = car end
    end
    for _, car in ipairs(self:cars()) do
        if not car.place and car.eliminated then out[#out + 1] = car end
    end
    return out
end

--- How far round the car is, for the panels: its place once finished, the
-- lap it is on in a race of more than one, else nil.
function Race:progress(car)
    if car.place then
        return "finished " .. placeName(car.place)
    elseif self.state.laps > 1 and car.lap > 0 then
        return string.format("lap %d/%d", math.min(car.lap, self.state.laps), self.state.laps)
    end
    return nil
end

--- Set the race to `laps` laps. Changed mid-race, cars already past the new
-- distance finish, in race order, and those short of it are back racing.
function Race:setLaps(laps)
    local s = self.state
    s.laps = laps
    self:emit("info", string.format("The race is %d lap%s", laps, laps == 1 and "" or "s"))
    -- Those taken out of the order first, so the ones kept close up.
    for _, car in ipairs(self:standings()) do
        if car.place and car.lap <= laps then
            self:settleFinish(car)
        end
    end
    for _, car in ipairs(self:cars()) do
        self:settleFinish(car)
    end
end

function Race:zone(id)
    for _, z in ipairs(self.rules.zones) do
        if z.id == id then return z end
    end
    return nil
end

-- Wear ----------------------------------------------------------------------

function Race:checkElimination(car)
    local why = nil
    for _, z in ipairs(self.rules.zones) do
        if z.eliminateAt and car.wear[z.id] <= z.eliminateAt then
            why = "no " .. z.name .. " left"
            break
        end
    end
    if not why and car.crashed then
        why = "went through corner " .. car.crashed .. " without its stops"
    end
    if why and not car.eliminated then
        car.eliminated = true
        self:dropChecks(car.color)
        self:emit("out", self:label(car) .. " is out of the race (" .. why .. ")", car.color)
    elseif not why and car.eliminated then
        car.eliminated = false
        self:emit("info", self:label(car) .. " is back in the race", car.color)
    end
    self:settleFinish(car)
end

--- Apply a zone -> points map of wear, announcing each loss.
function Race:applyWear(car, wear, reason)
    for _, z in ipairs(self.rules.zones) do
        local pts = wear[z.id]
        if pts and pts ~= 0 then
            car.wear[z.id] = car.wear[z.id] - pts
            self:emit("wear", string.format("%s loses %d %s (%s) -- %d left",
                self:label(car), pts, z.name, reason, math.max(0, car.wear[z.id])), car.color)
        end
    end
    self:checkElimination(car)
end

--- Give back a zone -> points map of wear, capped at each zone's start.
function Race:refund(car, wear, reason)
    for _, z in ipairs(self.rules.zones) do
        local pts = wear[z.id]
        if pts and pts ~= 0 then
            local before = car.wear[z.id]
            car.wear[z.id] = math.min(z.start, before + pts)
            self:emit("info", string.format("%s gets back %d %s (%s) -- %d left",
                self:label(car), car.wear[z.id] - before, z.name, reason, car.wear[z.id]), car.color)
        end
    end
    self:checkElimination(car)
end

--- Manual correction. Gains are capped at the zone's starting value.
function Race:adjust(color, zoneId, delta, reason)
    local car = self:car(color)
    if not car then return end
    local z = self:zone(zoneId or self.rules.zones[1].id)
    if not z then return end
    if delta < 0 then
        self:applyWear(car, { [z.id] = -delta }, reason or "adjusted")
        return
    end
    local before = car.wear[z.id]
    car.wear[z.id] = math.min(z.start, before + delta)
    self:emit("info", string.format("%s gains %d %s (%s) -- %d left",
        self:label(car), car.wear[z.id] - before, z.name, reason or "adjusted", car.wear[z.id]), color)
    self:checkElimination(car)
end

--- Manual correction to an exact value, e.g. a marker moved on the dashboard.
function Race:setWear(color, zoneId, value, reason)
    local car = self:car(color)
    local z = self:zone(zoneId or self.rules.zones[1].id)
    if not car or not z then return end
    local delta = value - math.max(0, car.wear[z.id])
    if delta ~= 0 then
        self:adjust(color, z.id, delta, reason)
    end
end

function Race:pitStop(color)
    local car = self:car(color)
    if not car then return end
    for _, id in ipairs(self.rules.pitRestores) do
        car.wear[id] = self:zone(id).start
    end
    car.maxGear = self.rules.pitMaxGear
    self:emit("info", string.format("%s pits: wear restored, leave in %s gear or lower",
        self:label(car), gearName(car.maxGear)), color)
    self:checkElimination(car)
end

-- Gears ---------------------------------------------------------------------

--- What shifting `car` into `to` would mean, judged from the gear it last
-- rolled. Returns { legal, wear, notes }.
function Race:shiftAdvice(car, to)
    local rules = self.rules
    local from = car.rolledGear
    local notes, legal, wear = {}, true, nil
    if from == 0 then
        if to ~= 1 then
            legal = false
            notes[#notes + 1] = "cars start in 1st gear"
        end
        if car.stalledRound and car.stalledRound == self.state.round then
            legal = false
            notes[#notes + 1] = "stalled -- sit this round out"
        end
    elseif to > from + 1 then
        legal = false
        notes[#notes + 1] = "no skipping gears on the way up (was in " .. gearName(from) .. ")"
    elseif to < from - 1 then
        local skipped = from - to - 1
        if skipped > rules.maxDownshift then
            legal = false
            notes[#notes + 1] = string.format("at most %d gears can be skipped when shifting down", rules.maxDownshift)
        else
            wear = rules.downshiftWear(skipped)
        end
    end
    if car.maxGear and to > car.maxGear then
        legal = false
        notes[#notes + 1] = "leaving the pits, " .. gearName(car.maxGear) .. " gear is the limit"
    end
    return { legal = legal, wear = wear, notes = notes }
end

local function wearText(race, wear)
    local parts = {}
    for _, z in ipairs(race.rules.zones) do
        if wear[z.id] and wear[z.id] > 0 then
            parts[#parts + 1] = wear[z.id] .. " " .. z.name
        end
    end
    return table.concat(parts, ", ")
end

function Race:shift(color, gear)
    local car = self:car(color)
    if not car then return end
    car.gear = gear
    local adv = self:shiftAdvice(car, gear)
    local text = self:label(car) .. " selects " .. gearName(gear) .. " gear"
    if adv.wear then
        text = text .. " -- costs " .. wearText(self, adv.wear) .. " when rolled"
    end
    if #adv.notes > 0 then
        self:emit("warn", text .. " (" .. table.concat(adv.notes, "; ") .. ")", color)
    else
        self:emit("info", text, color)
    end
end

--- A gear die came to rest showing `value`.
function Race:rolled(color, gear, value)
    local car = self:car(color)
    if not car then
        self:emit("warn", string.format("%s gear die shows %s, but %s has no car in the race",
            gearName(gear), tostring(value), tostring(color)), color)
        return
    end
    local who = self:label(car)
    local due = self:turn()
    if car.eliminated then
        self:emit("warn", who .. " is out of the race but rolled anyway", color)
    elseif car.place then
        self:emit("warn", who .. " has already finished but rolled anyway", color)
    elseif due and due ~= car and car.movedRound ~= self.state.round then
        self:emit("warn", string.format("%s rolls out of turn -- %s plays first this round",
            who, self:label(due)), color)
    end
    if car.gear ~= gear then
        if car.gear ~= 0 then
            self:emit("warn", string.format("%s rolled the %s gear die with %s selected -- going with %s",
                who, gearName(gear), gearName(car.gear), gearName(gear)), color)
        end
        car.gear = gear
    end

    local adv = self:shiftAdvice(car, gear)
    for _, n in ipairs(adv.notes) do
        self:emit("warn", who .. ": " .. n, color)
    end
    if adv.wear then
        self:applyWear(car, adv.wear, "skipped gears shifting down")
    end

    local range = self.rules.gears[gear]
    if range and (value < range.min or value > range.max) then
        self:emit("warn", string.format("%s gear die read as %s, outside %d-%d -- check the die",
            gearName(gear), tostring(value), range.min, range.max), color)
    end

    car.rolledGear = gear
    car.lastRoll = value
    car.maxGear = nil
    car.movedRound = self.state.round
    self:startMove(car, value)
    self:emit("info", string.format("%s rolls %s in %s gear", who, tostring(value), gearName(gear)), color)

    if self.rules.engineStrain[gear] == value then
        self:emit("warn", "Engine strain! Every car in top gears rolls the black die", color)
        self:queueCheck(car, "engine")
        for _, other in ipairs(self:cars()) do
            if other ~= car and not other.eliminated and not other.place and self.rules.engineStrain[other.rolledGear] then
                self:queueCheck(other, "engine")
            end
        end
    end
    self:advanceRound()
end

-- Black die checks ------------------------------------------------------------

--- What a check is for, to show: "collision with Blue".
function Race:checkName(c)
    local name = self.rules.checks[c.kind].name
    local other = c.with and self:car(c.with)
    if c.with then
        name = name .. " with " .. (other and self:label(other) or c.with)
    end
    return name
end

--- Ask `car` to roll the black die for a `kind` check. A collision can be
-- against the car of color `with`, part of the contact recorded as
-- `state.packs[pack]`. Not twice for the same.
function Race:queueCheck(car, kind, with, pack)
    for _, c in ipairs(self.state.checks) do
        if c.color == car.color and c.kind == kind and c.with == with then
            return false
        end
    end
    local c = { color = car.color, kind = kind, with = with, pack = pack }
    self.state.checks[#self.state.checks + 1] = c
    self:emit("info", string.format("%s: roll the black die (%s check)",
        self:label(car), self:checkName(c)), car.color)
    return true
end

function Race:requestCheck(color, kind)
    local car = self:car(color)
    if not car or car.eliminated then return end
    if not self:queueCheck(car, kind) then
        self:emit("info", self:label(car) .. " already has a " .. kind .. " check waiting", color)
    end
end

function Race:dropChecks(color)
    local checks = self.state.checks
    for i = #checks, 1, -1 do
        if checks[i].color == color then table.remove(checks, i) end
    end
end

function Race:pendingChecks()
    return self.state.checks
end

--- The black die came to rest. Resolves the roller's oldest check, or the
-- oldest check overall if the roller has none (someone rolling for a friend).
function Race:blackDie(value, roller)
    local checks = self.state.checks
    local idx = nil
    for i, c in ipairs(checks) do
        if c.color == roller then idx = i break end
    end
    idx = idx or (#checks > 0 and 1 or nil)
    if not idx then
        self:emit("info", "Black die: " .. tostring(value), roller)
        return
    end
    local check = table.remove(checks, idx)
    local car = self:car(check.color)
    if not car then return end
    local outcome = self.rules.checks[check.kind].resolve(value)
    self:emit(outcome.wear and "warn" or "info", string.format("%s rolls %s on the black die: %s",
        self:label(car), tostring(value), outcome.text), car.color)
    if check.kind == "collision" and check.with and check.pack then
        self:collided(check)
    end

    if check.kind == "start" then
        if outcome.stall then
            car.stalledRound = self.state.round
        elseif outcome.bonus then
            car.gear = 1
            car.rolledGear = 1
            car.movedRound = self.state.round
            self:startMove(car, outcome.bonus)
        end
    elseif check.kind == "grid" then
        car.gridRolls = car.gridRolls or {}
        car.gridRolls[#car.gridRolls + 1] = value
        self:settleGrid()
    end
    if outcome.wear then
        self:applyWear(car, outcome.wear, check.kind)
    end
    self:advanceRound()
end

-- Grid and rounds -----------------------------------------------------------

function Race:rollForGrid()
    self.state.phase = "grid"
    for _, car in ipairs(self:cars()) do
        car.gridRolls = {}
        self:queueCheck(car, "grid")
    end
end

local function compareRolls(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or -1, b[i] or -1
        if x ~= y then return x > y end
    end
    return false
end

local function sameRolls(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

--- Once every grid roll is in, order the cars; tied cars roll again.
function Race:settleGrid()
    for _, c in ipairs(self.state.checks) do
        if c.kind == "grid" then return end
    end
    local cars = self:cars()
    table.sort(cars, function(a, b) return compareRolls(a.gridRolls or {}, b.gridRolls or {}) end)
    local tied = false
    for i = 1, #cars - 1 do
        local a, b = cars[i], cars[i + 1]
        if sameRolls(a.gridRolls or {}, b.gridRolls or {}) then
            tied = true
            self:queueCheck(a, "grid")
            self:queueCheck(b, "grid")
        end
    end
    if tied then
        self:emit("warn", "Tie for the grid -- tied drivers roll again")
        return
    end
    local names = {}
    self.state.order = {}
    for i, car in ipairs(cars) do
        self.state.order[i] = car.color
        names[i] = i .. ". " .. self:label(car)
    end
    self.state.phase = "setup"
    -- Not state: lets the Global script put the cars on the grid.
    self.gridSettled = true
    self:emit("info", "Starting grid: " .. table.concat(names, "  "))
end

--- The track the cars are on, for turn order. Not state: the Global script
-- hands it over after a load, and every car put down on a track brings it.
function Race:useTrack(track)
    self.track = track
end

--- Put the cars in the order they play this round, by where they are on the
-- track: the leader first. Level cars (within LEVEL cells) go by gear, the
-- higher first, then by which is nearer the inside of the corner they are
-- in or coming to. Cars it cannot place -- no track data, off the track,
-- out or finished -- keep their slots, and the rest are sorted round them.
-- Returns whether the order changed.
function Race:reorder()
    local s = self.state
    local P = self.track and Position.of(self.track)
    if not P then
        return false
    end
    local before = table.concat(s.order, " ")
    local slots, ranked = {}, {}
    for i, color in ipairs(s.order) do
        local car = s.cars[color]
        local along = car and car.space and P.along[car.space]
        if along and not car.eliminated and not car.place then
            slots[#slots + 1] = i
            ranked[#ranked + 1] = { car = car, was = i, key = car.lap * P.length + along,
                inside = Position.inside(P, car.space) }
        end
    end
    table.sort(ranked, function(a, b)
        if a.key ~= b.key then return a.key > b.key end
        return a.was < b.was
    end)
    -- Each run of cars level with the first of it is one group.
    local i = 1
    while i <= #ranked do
        local j = i
        while j < #ranked and ranked[i].key - ranked[j + 1].key < LEVEL * P.cell do
            j = j + 1
        end
        local group = {}
        for k = i, j do group[#group + 1] = ranked[k] end
        table.sort(group, function(a, b)
            if a.car.rolledGear ~= b.car.rolledGear then return a.car.rolledGear > b.car.rolledGear end
            if a.inside ~= b.inside then return a.inside > b.inside end
            return a.was < b.was
        end)
        for k, e in ipairs(group) do ranked[i + k - 1] = e end
        i = j + 1
    end
    for k, e in ipairs(ranked) do
        s.order[slots[k]] = e.car.color
    end
    return table.concat(s.order, " ") ~= before
end

--- Whether any car has moved yet this round.
function Race:anyMoved()
    for _, car in pairs(self.state.cars) do
        if car.movedRound == self.state.round then
            return true
        end
    end
    return false
end

--- The car to play next this round: the first in order still running that
-- has neither moved nor sat out. nil outside a race or once all have.
function Race:turn()
    local s = self.state
    if s.phase ~= "race" then
        return nil
    end
    for _, car in ipairs(self:cars()) do
        if not car.eliminated and not car.place and car.movedRound ~= s.round and car.stalledRound ~= s.round then
            return car
        end
    end
    return nil
end

--- The running cars in the order they play, for announcing a round.
function Race:orderText()
    local names = {}
    for _, car in ipairs(self:cars()) do
        if not car.eliminated and not car.place then
            names[#names + 1] = #names + 1 .. ". " .. self:label(car)
        end
    end
    return table.concat(names, "  ")
end

function Race:startRace()
    local s = self.state
    s.phase = "race"
    s.round = 1
    s.checks = {}
    s.packs = {}
    s.finishers = {}
    for _, car in ipairs(self:cars()) do
        resetCar(self.rules, car)
    end
    self:reorder()
    self:emit("info", "Lights out! Everyone rolls the black die for their start")
    self:emit("info", "Order of play: " .. self:orderText())
    for _, car in ipairs(self:cars()) do
        self:queueCheck(car, "start")
    end
end

--- Move to the next round once every running car has moved or sat out.
function Race:advanceRound()
    local s = self.state
    if s.phase ~= "race" then return end
    local any = false
    for _, car in ipairs(self:cars()) do
        if not car.eliminated and not car.place then
            any = true
            if car.movedRound ~= s.round and car.stalledRound ~= s.round then
                return
            end
        end
    end
    if not any then return end
    for _, c in ipairs(s.checks) do
        if c.kind == "start" then return end
    end
    s.round = s.round + 1
    self:reorder()
    self:emit("info", "Round " .. s.round .. " -- " .. self:orderText())
end

function Race:reset()
    local s = self.state
    s.phase = "setup"
    s.round = 0
    s.checks = {}
    s.packs = {}
    s.finishers = {}
    for _, car in ipairs(self:cars()) do
        resetCar(self.rules, car)
        car.gridRolls = nil
    end
    self:emit("info", "Race reset")
end

Race.gearName = gearName
Race.placeName = placeName

return Race
