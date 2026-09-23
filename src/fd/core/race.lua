-- Race state and rule bookkeeping. No TTS calls: the Global script feeds in
-- what happened (a shift, a die result, a button) and relays the events this
-- produces. Nothing here refuses an action -- illegal moves are applied with a
-- warning, so a rules bug or a table-talk ruling can never wedge a game.
--
-- `state` is plain data so it can go straight through JSON for onSave and undo.

local Race = {}
Race.__index = Race

local ORDINAL = { "1st", "2nd", "3rd", "4th", "5th", "6th" }

local function gearName(g)
    return ORDINAL[g] or ("gear " .. tostring(g))
end

function Race.new(rules, saved)
    local self = setmetatable({ rules = rules, events = {} }, Race)
    self.state = saved or {}
    local s = self.state
    s.phase = s.phase or "setup" -- setup | grid | race
    s.round = s.round or 0
    s.order = s.order or {}
    s.cars = s.cars or {}
    s.checks = s.checks or {}
    return self
end

function Race:serialize()
    return self.state
end

-- Events --------------------------------------------------------------------

-- level: info | warn | wear | out
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
-- the board. `moveFrom` is, as it belongs to the race being thrown away.
local function resetCar(rules, car)
    car.gear = 0         -- selected on the dashboard
    car.rolledGear = 0   -- gear of the last die actually rolled; 0 = on the grid
    car.wear = freshWear(rules)
    car.eliminated = false
    car.lastRoll = nil
    car.maxGear = nil
    car.movedRound = nil
    car.stalledRound = nil
    car.moveFrom = nil
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
end

--- Cars in race order.
function Race:cars()
    local out = {}
    for _, color in ipairs(self.state.order) do
        out[#out + 1] = self.state.cars[color]
    end
    return out
end

--- The car is now on the space `spaceId`, or off the track if nil. Silent:
-- cars are put down all the time, and the board shows where they are.
function Race:placed(color, spaceId)
    local car = self:car(color)
    if car then
        car.space = spaceId
    end
end

--- Where a car starts the move it is about to make.
local function startMove(car)
    car.moveFrom = car.space
end

function Race:zone(id)
    for _, z in ipairs(self.rules.zones) do
        if z.id == id then return z end
    end
    return nil
end

-- Wear ----------------------------------------------------------------------

function Race:checkElimination(car)
    local out = nil
    for _, z in ipairs(self.rules.zones) do
        if z.eliminateAt and car.wear[z.id] <= z.eliminateAt then
            out = z
            break
        end
    end
    if out and not car.eliminated then
        car.eliminated = true
        self:dropChecks(car.color)
        self:emit("out", self:label(car) .. " is out of the race (no " .. out.name .. " left)", car.color)
    elseif not out and car.eliminated then
        car.eliminated = false
        self:emit("info", self:label(car) .. " is back in the race", car.color)
    end
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

function Race:brake(color, spaces)
    local car = self:car(color)
    if not car then return end
    self:applyWear(car, self.rules.brakeWear(spaces), "braked " .. spaces .. " short")
end

function Race:overshoot(color, spaces)
    local car = self:car(color)
    if not car then return end
    self:applyWear(car, self.rules.overshootWear(spaces), "overshot a corner by " .. spaces)
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
    if car.eliminated then
        self:emit("warn", who .. " is out of the race but rolled anyway", color)
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
    startMove(car)
    self:emit("info", string.format("%s rolls %s in %s gear", who, tostring(value), gearName(gear)), color)

    if self.rules.engineStrain[gear] == value then
        self:emit("warn", "Engine strain! Every car in top gears rolls the black die", color)
        self:queueCheck(car, "engine")
        for _, other in ipairs(self:cars()) do
            if other ~= car and not other.eliminated and self.rules.engineStrain[other.rolledGear] then
                self:queueCheck(other, "engine")
            end
        end
    end
    self:advanceRound()
end

-- Black die checks ------------------------------------------------------------

function Race:queueCheck(car, kind)
    for _, c in ipairs(self.state.checks) do
        if c.color == car.color and c.kind == kind then
            return false
        end
    end
    self.state.checks[#self.state.checks + 1] = { color = car.color, kind = kind }
    self:emit("info", string.format("%s: roll the black die (%s check)",
        self:label(car), self.rules.checks[kind].name), car.color)
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

    if check.kind == "start" then
        if outcome.stall then
            car.stalledRound = self.state.round
        elseif outcome.bonus then
            car.gear = 1
            car.rolledGear = 1
            car.movedRound = self.state.round
            startMove(car)
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
    self:emit("info", "Starting grid: " .. table.concat(names, "  "))
end

function Race:startRace()
    local s = self.state
    s.phase = "race"
    s.round = 1
    s.checks = {}
    for _, car in ipairs(self:cars()) do
        resetCar(self.rules, car)
    end
    self:emit("info", "Lights out! Everyone rolls the black die for their start")
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
        if not car.eliminated then
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
    self:emit("info", "Round " .. s.round)
end

function Race:reset()
    local s = self.state
    s.phase = "setup"
    s.round = 0
    s.checks = {}
    for _, car in ipairs(self:cars()) do
        resetCar(self.rules, car)
        car.gridRolls = nil
    end
    self:emit("info", "Race reset")
end

Race.gearName = gearName

return Race
