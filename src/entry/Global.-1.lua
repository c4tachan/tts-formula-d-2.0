-- Global script: owns the race and wires TTS events to it.
--
-- The rules live in fd.core.race / fd.rules.*, which make no TTS calls; this
-- file turns clicks, dice and moved pieces into calls on the race, then relays
-- the events it produces and syncs the dashboards and the race panel.
--
-- Each player drives from their dashboard: its buttons (fd.tts.controls) join
-- the race and cover damage, pit stops and WP corrections, the gear stick
-- selects a gear when dropped on a slot, and the WP marker sets WP when dropped
-- on a number. Braking and overshooting are charged when a car is put down
-- after its roll.

local Race = require("fd.core.race")
-- The rulesets to choose from on the setup menu, in its order. The race
-- state says which one it is raced under.
local RULESETS = {
    require("fd.rules.beginner"),
    require("fd.rules.advanced"),
}
local function rulesFor(id)
    for _, r in ipairs(RULESETS) do
        if r.id == id then return r end
    end
    return RULESETS[1]
end
local Maps = require("fd.data.maps")
local Assets = require("fd.data.assets")
local Dice = require("fd.tts.dice")
local Dashboard = require("fd.tts.dashboard")
local Hud = require("fd.tts.hud")
local Ui = require("fd.tts.ui")
local Controls = require("fd.tts.controls")
local Mini = require("fd.tts.minidash")
local Track = require("fd.tts.track")
local Editor = require("fd.tts.track_editor")
local Ghosts = require("fd.tts.ghosts")
local Setup = require("fd.tts.setup")
local TRACKS = {
    FDAustin = require("fd.data.tracks.FDAustin"),
    FDBuddh = require("fd.data.tracks.FDBuddh"),
    FDHockenheim = require("fd.data.tracks.FDHockenheim"),
    FDMonaco = require("fd.data.tracks.FDMonaco"),
    FDSebring = require("fd.data.tracks.FDSebring"),
    FDSingapore = require("fd.data.tracks.FDSingapore"),
    FDSotchi = require("fd.data.tracks.FDSotchi"),
    FDValencia = require("fd.data.tracks.FDValencia"),
    FDe01 = require("fd.data.tracks.FDe01"),
    FDe02 = require("fd.data.tracks.FDe02"),
    FDe03 = require("fd.data.tracks.FDe03"),
}

setup_packed = false

local race
local syncCars -- defined with the rest of the car handling, below
local snapCar -- defined with the track, below
local placeOnGrid -- likewise
local spaceUnder -- likewise
local showReach -- likewise
local clearReach -- likewise
local reachShown = nil -- whose move the marks on the board are for
local useBoardTrack -- likewise
local drawPits -- likewise
local syncDamage, damageMarker, damagePieces -- likewise
local joinAt -- with the dashboard buttons, below
local deliver, dealInSeated, dropDashless, bench -- likewise
local isAdmin -- with the race controls, below
local layDice, activateDie, restockDice -- with the track, below
local throwChecks -- with the dice, below
local boardMenu -- with the track editor, below
local startRace -- with the race controls, below
local pendingStart = nil -- who pressed Start race, while the grid is rolled
-- Which car and space the flag marking where the car to play started its
-- move stands for (see markStart).
local startKey = nil
-- What syncTurns last told TTS's Turns, as { on, order, color }; nil until
-- it has, so the first sync after a load sets every part.
local turnsSet = nil
local undo = {}
local joining = {} -- steam id -> true from connecting until moved to the spectators (see bench)
local rulebooks = {} -- colour -> guid of the rulebook out for them (fdRules)
local UNDO_LIMIT = 30

--- One roll of the black die, made by the script: only when the die itself
-- is not on the table to be thrown (see throwChecks). The result is told in
-- the chat, and shown on the die if it turns up.
local function rollBlack()
    local value = math.random(20)
    Dice.showBlack(value)
    return value
end

-- The colour of each kind of message in chat. A roll is shown in the colour
-- of the seat that rolled it, when there is one (see relay).
local LEVEL_RGB = {
    info = { 0.85, 0.85, 0.85 },
    warn = { 1, 0.72, 0.3 },
    wear = { 1, 0.45, 0.35 },
    out = { 1, 0.2, 0.2 },
    finish = { 1, 0.84, 0.25 },
    turn = { 0.49, 0.99, 0 },
    order = { 0.55, 0.8, 1 },
    lap = { 0.78, 0.62, 1 },
    roll = { 1, 1, 1 },
}

local SEATS = {
    White = true, Brown = true, Red = true, Orange = true, Yellow = true,
    Green = true, Teal = true, Blue = true, Purple = true, Pink = true,
}

-- Setup ---------------------------------------------------------------------
-- The table holds the board and nothing else to set up: the map and rules
-- are chosen on the setup menu (fd.tts.setup). The setup board and
-- everything on it are hidden where they stand -- the script still
-- reaches the bags it deals dashboards, cars and markers from.

local SETUP_BAG = "0fde3b"
-- Everyone a hidden object is hidden from: every seat, the spectators and
-- the Game Master.
local EVERYONE = {
    "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink",
    "Grey", "Black",
}
-- The bags the script deals from, which must stay on the table (hidden),
-- never inside another bag: everything else of the setup board can go.
local SOURCE_BAGS = {
    "1bb99e", -- Formula 1 Black Bag: cars (CAR_BAG, below)
    "edfadc", -- Beginner Dashboard Bag (DASHBOARD_BAGS, below)
    "4eb678", -- Advanced Dashboard Bag
    "71d89b", -- Gear Stick Bag (fd.tts.dashboard)
    "a845cd", -- Wear Tracker Bag (fd.tts.dashboard)
    "bbc10d", -- Damage Marker Bag (DAMAGE_BAG, below)
    "ac4939", -- Dice Set Bag: spare dice (fd.tts.dice)
}

--- Hide `obj` where it stands: locked, out of reach, and invisible to all.
local function hideObject(obj)
    obj.setLock(true)
    obj.interactable = false
    obj.setInvisibleTo(EVERYONE)
end

--- Hide the bags the script deals from, and whatever is left of the setup
-- board, but the dice, which sit by their tray. The setup board, packed
-- away, is put out first: the bags it holds cannot be reached inside it.
-- Without it -- once deleted from the table -- only the bags are hidden.
-- `onDone` runs once it is all hidden.
local function hideSetup(onDone)
    local bag = getObjectFromGUID(SETUP_BAG)
    local function hide()
        for _, guid in ipairs(SOURCE_BAGS) do
            local obj = getObjectFromGUID(guid)
            if obj then hideObject(obj) end
        end
        for guid in pairs(bag and bag.getTable("memoryList") or {}) do
            local obj = getObjectFromGUID(guid)
            if obj and not Dice.gearOf(obj) and not Dice.isBlack(obj) then
                hideObject(obj)
            end
        end
        onDone()
    end
    if not bag then
        return hide()
    end
    if setup_packed then
        bag.call("buttonClick_place", {})
        setup_packed = false
        -- A moment for its objects to come out of the bag.
        Wait.time(hide, 1.5)
    else
        hide()
    end
end

--- The map on the board tile, from Maps.list, or nil if it is none we know.
local function mapOnBoard()
    local tile = Track.tile()
    local custom = tile and tile.getCustomObject()
    if not custom then
        return nil
    end
    for _, map in ipairs(Maps.list) do
        if Assets.same(custom.image, map.url) then
            return map
        end
    end
    return nil
end

function onLoad(saved_data)
    local saved = {}
    if saved_data and saved_data ~= "" then
        saved = JSON.decode(saved_data) or {}
        setup_packed = saved.sp
    else
        setup_packed = true
    end

    race = Race.new(rulesFor(saved.race and saved.race.rules), saved.race)
    race.autoRolls = true
    damagePieces = saved.damage or {}
    rulebooks = saved.books or {}
    turnsSet = nil
    Dice.prepareAll()
    Dashboard.scan()
    Assets.register(UI, "-1")
    setupTrackEditor(saved.edits, saved.markers)
    drawPits(useBoardTrack())
    -- The save keeps the icons that were on the board; none are wanted yet.
    Track.drawIcons()
    buildUi()
    -- A moment for every object to have spawned: a dashboard not there yet
    -- would look deleted, and its driver be taken out. Nobody is dealt in
    -- yet: that waits for Start race (see fdSetupStart).
    Wait.time(function()
        Dashboard.scan()
        dropDashless()
        boardMenu(Editor.isOpen())
        hideSetup(function() layDice() end)
        syncDamage()
    end, 1)
end

--- (Re)build the race panel on the board, the screen dashboards and the
-- setup menu, then fill them in.
function buildUi()
    -- Until the new XML has loaded, updates would go to elements on their way
    -- out and then be skipped as repeats once it has (see fd.tts.ui).
    Mini.setReady(false)
    Setup.setReady(false)
    local rules = race.rules
    local panels = Mini.panels(rules)
    local map = mapOnBoard()
    local maps = {}
    for _, m in ipairs(Maps.list) do
        maps[#maps + 1] = { id = m.id, name = m.name, ready = TRACKS[m.id] ~= nil, current = map ~= nil and map.id == m.id }
    end
    local rulesets = {}
    for i, r in ipairs(RULESETS) do
        rulesets[i] = { name = r.name, current = r == rules }
    end
    panels[#panels + 1] = Setup.panel(maps, rulesets)
    local track = map and TRACKS[map.id]
    Hud.build(rules, panels, Track.tile(), track and Editor.trackFor(track), function()
        Mini.setReady()
        Setup.setReady()
        refresh()
    end)
end

-- Players who join after onLoad get the XML saved with the game, not the panels
-- the script added, and TTS does not re-check `visibility` when a player
-- changes seat. Sending the whole UI again fixes both. Batched so a burst of
-- joins and seat changes costs one rebuild.
local rebuildPending = false

local function rebuildUiSoon()
    if rebuildPending then
        return
    end
    rebuildPending = true
    Wait.time(function()
        rebuildPending = false
        buildUi()
    end, 1)
end

function onPlayerConnect(player)
    rebuildUiSoon()
    -- TTS seats a newcomer in a free colour of its choosing. Before the
    -- start they are moved to the spectators instead, to pick their own:
    -- picking a seat is what deals them in.
    local id = player and player.steam_id
    if id then
        joining[id] = true
        Wait.time(function() bench(id) end, 0.5)
    end
end

-- The rebuild also brings the setup menu's list of who is seated up to date.
function onPlayerChangeColor(color)
    rebuildUiSoon()
end

--- A driver who drops out leaves their car where it is, and once the seat
-- is empty its dashboard offers "Drive this car" (see fdDashTakeOver).
function onPlayerDisconnect()
    Wait.time(function() refresh() end, 0.5)
end

function onSave()
    return JSON.encode({
        sp = setup_packed, race = race and race:serialize(),
        -- Hand edits to track spaces; tools/extract/import_track.py reads them.
        edits = Editor.save(),
        -- The damage marker pieces on the board, by marker id.
        damage = damagePieces,
        -- The rulebooks players have out, by colour.
        books = rulebooks,
        -- Editor markers out on the board; removed on load (see Editor.load).
        markers = (function()
            local out = Editor.markerGuids()
            for _, g in ipairs(Ghosts.guids()) do out[#out + 1] = g end
            return out
        end)(),
    })
end

-- Plumbing ------------------------------------------------------------------

local function tintOf(color)
    return Color.fromString(color)
end

local function relay(events)
    for _, e in ipairs(events) do
        local rgb = LEVEL_RGB[e.level] or LEVEL_RGB.info
        if e.level == "roll" and SEATS[e.color] then
            rgb = tintOf(e.color)
        end
        if e.level == "wear" or e.level == "out" or e.level == "finish" then
            broadcastToAll(e.text, rgb)
        else
            printToAll(e.text, rgb)
            if e.level == "warn" and e.color and Player[e.color] and Player[e.color].seated then
                broadcastToColor(e.text, e.color, rgb)
            end
        end
    end
end

-- What each car's dashboard last showed, so an action that leaves a car alone
-- does not move all of its markers again.
local synced = {}
-- Dashboards the script is turning over to another face, by guid: until
-- they have and are drawn again (see dashboardMoved), nobody is told to.
local flipping = {}

local function dashState(car)
    local parts = { car.tts.dash or "", car.gear }
    for _, z in ipairs(race.rules.zones) do parts[#parts + 1] = car.wear[z.id] end
    return table.concat(parts, "|")
end

--- Put every car's gear stick and wear markers where the race says.
-- `force` re-places them even if nothing changed: after a player drops one
-- somewhere it should not be, or moves the dashboard.
local function syncDashboards(force)
    if force then synced = {} end
    local rules = race.rules
    for _, car in ipairs(race:cars()) do
        car.tts = car.tts or {}
        local state = dashState(car)
        local dash = synced[car.color] ~= state and car.tts.dash and getObjectFromGUID(car.tts.dash)
        if dash then
            synced[car.color] = state
            if Dashboard.fits(dash, rules) then
                car.tts.markers = car.tts.markers or {}
                Dashboard.sync(dash, car.tts.markers, car, rules, tintOf(car.color))
                car.tts.faceWarned = nil
            elseif flipping[dash.getGUID()] then
                synced[car.color] = nil -- drawn once it is over
            elseif not car.tts.faceWarned then
                car.tts.faceWarned = true
                broadcastToColor("Flip your dashboard to the " .. Dashboard.faceFor(rules)
                    .. " side to track wear on it.", car.color, LEVEL_RGB.warn)
            end
        end
    end
end

--- The car whose dashboard is `guid`, if any.
local function carOnDash(guid)
    for _, car in ipairs(race:cars()) do
        if car.tts and car.tts.dash == guid then
            return car
        end
    end
    return nil
end

local function dashLabel(car)
    local parts = { race:label(car) }
    if car.eliminated then
        parts[#parts + 1] = "OUT"
    else
        parts[#parts + 1] = race:progress(car)
        if not car.place then
            parts[#parts + 1] = car.gear > 0 and (Race.gearName(car.gear) .. " gear") or "on the grid"
            parts[#parts + 1] = Hud.wearSummary(race, car)
            if car.spun then
                parts[#parts + 1] = "SPUN: 1st gear"
            end
            for _, w in ipairs(race:warnings(car)) do
                parts[#parts + 1] = w
            end
            if car.lastRoll then
                parts[#parts + 1] = "rolled " .. car.lastRoll
            end
        end
    end
    if race:turn() == car then
        parts[#parts + 1] = "YOUR TURN"
    end
    if not (car.tts.car and getObjectFromGUID(car.tts.car)) then
        parts[#parts + 1] = "no car -- press Car"
    end
    for _, c in ipairs(race:pendingChecks()) do
        -- A start waiting for its turn is rolled then, by the script.
        if c.color == car.color and c.kind ~= "start" then
            parts[#parts + 1] = "ROLL BLACK DIE (" .. race:checkName(c) .. ")"
            break
        end
    end
    return table.concat(parts, "  |  ")
end

--- Whether somebody is sitting in `color`.
local function seatedIn(color)
    local p = Player[color]
    return p ~= nil and p.seated == true
end

local function renderDashboards()
    for _, obj in ipairs(Dashboard.all()) do
        local car = carOnDash(obj.getGUID())
        Controls.render(obj, car, car and dashLabel(car), car and not seatedIn(car.color))
    end
end

-- The car to play, as last shown: the key of the turn its driver was told
-- about, and the guid of the car lit up for it.
local turnTold = nil
local litCar = nil

--- Hand TTS's own turn marker to `due`, in the race's order of play, which
-- changes every round. Nobody can pass a turn from TTS's menu: the race
-- says when a turn is over. Outside a race it is switched off again -- but
-- only if it was switched on here: Turns that were on already (hotseat
-- runs its own) are left alone, as switching them off sets TTS handing the
-- turn round every seat.
--
-- Each part is written only when it changes from what was last written, not
-- from what Turns reads back: TTS does not always read back what it was
-- given, and every turn_color it is given is announced to the table.
local function syncTurns(due)
    local seated = due and Player[due.color] and Player[due.color].seated
    if not seated then
        if turnsSet and turnsSet.on then
            Turns.enable = false
            turnsSet = { on = false }
        end
        return
    end
    local order = {}
    for _, car in ipairs(race:cars()) do
        if not car.eliminated and not car.place and Player[car.color] and Player[car.color].seated then
            order[#order + 1] = car.color
        end
    end
    local key = table.concat(order, " ")
    local was = turnsSet or {}
    if not was.on then
        Turns.type = 2 -- custom order
        Turns.pass_turns = false
        Turns.enable = true
    end
    if was.order ~= key then
        Turns.order = order
    end
    if was.color ~= due.color then
        Turns.turn_color = due.color
    end
    turnsSet = { on = true, order = key, color = due.color }
end

--- Flag the space the car to play started its move from (where it stands,
-- before it rolls), in its colour; none outside a race. Put back on it,
-- the car has not moved (Race:backToStart).
local function markStart(due)
    local from = due and (due.move and due.move.from or due.space)
    local key = from and (due.color .. "@" .. from)
    if key == startKey then
        return
    end
    startKey = key
    local tile, track = Track.tile(), race.track
    Track.setIcons("start", from and tile and track
        and Track.marks(tile, track, { { id = from, kind = "start", color = due.color } }) or nil)
end

--- Point everyone at the car to play: TTS's turn marker and a highlight on
-- the car. `announce` also tells its driver, once, when the turn passes to
-- them. (Black die rolls are made at once, so nothing else is waited on.)
local function showTurn(announce)
    local due = race:turn()
    local obj = due and due.tts and due.tts.car and getObjectFromGUID(due.tts.car)
    local guid = obj and obj.getGUID() or nil
    if guid ~= litCar then
        local old = litCar and getObjectFromGUID(litCar)
        if old then old.highlightOff() end
        if obj then obj.highlightOn(due.color) end
        litCar = guid
    end
    syncTurns(due)
    markStart(due)
    local key = due and (race.state.round .. ":" .. due.color)
    if announce and key and key ~= turnTold then
        turnTold = key
        if Player[due.color] and Player[due.color].seated then
            broadcastToColor("Your turn, " .. race:label(due) .. ": shift, roll, then move your car.",
                due.color, LEVEL_RGB.turn)
        end
    end
end

--- Bring every panel up to date. `announce` is for a change made in play:
-- a turn that has passed is announced.
function refresh(announce)
    syncCars()
    Hud.refresh(race)
    Mini.refresh(race)
    activateDie()
    -- The map is only looked up while the setup menu shows it.
    local map, seated = nil, nil
    if Setup.shows(race.state.phase) then
        map = mapOnBoard()
        seated = {}
        for _, color in ipairs(getSeatedPlayers()) do
            local car, p = race:car(color), Player[color]
            if SEATS[color] and not car then
                seated[#seated + 1] = p and p.steam_name or color
            end
        end
    end
    Setup.refresh(race, map and { name = map.name, hasTrack = TRACKS[map.id] ~= nil }, seated)
    renderDashboards()
    showTurn(announce)
end

--- Run a change to the race: snapshot for undo, apply, then publish.
-- `followOn` is for a change that finishes the one before -- the black die
-- thrown for it settling -- which Undo takes back along with it, so it
-- takes no snapshot of its own.
local function act(fn, followOn)
    if not followOn then
        undo[#undo + 1] = JSON.encode(race:serialize())
        if #undo > UNDO_LIMIT then
            table.remove(undo, 1)
        end
    end
    fn()
    throwChecks()
    if race.gridSettled then
        race.gridSettled = nil
        placeOnGrid()
    end
    local opened = race.opened
    race.opened = nil
    relay(race:drain())
    syncDashboards()
    syncDamage()
    refresh(true)
    if opened then
        showReach(opened)
    end
    -- Start race waited on the grid roll: once it has settled, the race starts.
    local starter = pendingStart
    if starter and race.state.phase == "setup" then
        pendingStart = nil
        startRace(starter)
    end
end

local function handPosition(color)
    local p = Player[color]
    local hand = p and p.getHandTransform()
    return hand and hand.position or nil
end

--- Which way is across the table from `pos` towards its middle (x, z), or
-- nil right at the middle.
local function inward(pos)
    local len = math.sqrt(pos.x ^ 2 + pos.z ^ 2)
    if len < 1 then
        return nil
    end
    return -pos.x / len, -pos.z / len
end

-- Height to drop a fresh piece from: just above the table. Hand zones sit
-- below it, so a seat's own height will not do.
local DROP_Y = 3

--- Where a car from the bag goes: to the right of its driver's dashboard as
-- they face the table, or in front of their seat if they have none.
local function carSpot(car)
    local dash = car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)
    if dash then
        local p = dash.getPosition()
        local ix, iz = inward(p)
        ix, iz = ix or 0, iz or 1
        return { x = p.x + iz * 7, y = p.y + 2, z = p.z - ix * 7 }
    end
    local hand = handPosition(car.color)
    if not hand then
        return nil
    end
    local ix, iz = inward(hand)
    ix, iz = ix or 0, iz or 0
    return { x = hand.x + ix * 8, y = DROP_Y, z = hand.z + iz * 8 }
end

-- Dice ----------------------------------------------------------------------

-- Who a gear die result belongs to: the roller if they are racing, otherwise
-- the only car with that gear selected, otherwise the roller anyway.
local function ownerOf(color, gear)
    if race:car(color) then
        return color
    end
    local match = nil
    for _, car in ipairs(race:cars()) do
        if car.gear == gear then
            if match then return color end
            match = car.color
        end
    end
    return match or color
end

--- What to do with a roll of the die for `gear`, once it has settled.
local function onGearRoll(gear)
    return function(value, roller)
        if value then
            clearReach()
            act(function() race:rolled(ownerOf(roller, gear), gear, value) end)
        end
    end
end

--- Read gear die `obj` for `gear` once it settles, as rolled by `color`.
local function watchGearDie(obj, color, gear)
    Dice.watch(obj, color, onGearRoll(gear))
end

local throwing = nil -- the check the black die is in the air for
-- Grid rolls thrown since the grid roll was called, and the most before
-- giving up on a tie that will not break.
local gridThrows = 0
local GRID_THROWS = 40

--- The black die check to throw for next: what play waits on (collisions,
-- engine strain, the start of the car to play), else the next grid roll.
local function nextCheck()
    local c = race:checkWaiting()
    if c then
        return c
    end
    for _, g in ipairs(race.state.checks) do
        if g.kind == "grid" then
            return g
        end
    end
    return nil
end

--- Throw the black die in the tray for the next check, one at a time: each
-- result is applied when the die settles, through act, which throws for the
-- one after. Without the die on the table, the script rolls for them at once.
throwChecks = function()
    -- One die in the air at a time: bringing in another would park this one
    -- mid-throw. A gear die settling calls for this again (through act).
    if throwing or Dice.rolling() then
        return
    end
    local c = nextCheck()
    if not c then
        return
    end
    if c.kind == "grid" then
        gridThrows = gridThrows + 1
        if gridThrows > GRID_THROWS then
            race:emit("warn", "The grid is still tied -- press Start race to roll it again")
            pendingStart = nil
            return
        end
    end
    throwing = c
    local die = Dice.throw(Dice.BLACK, c.color, function(value)
        throwing = nil
        act(function()
            -- Undone or reset while it was in the air: nothing left to decide.
            for _, x in ipairs(race.state.checks) do
                if x == c then
                    race:blackDie(value or rollBlack(), c.color, c)
                    return
                end
            end
        end, true)
    end)
    if die then
        return
    end
    throwing = nil
    for _ = 1, 100 do
        c = nextCheck()
        if not c then
            return
        end
        race:blackDie(rollBlack(), c.color, c)
    end
end

function onObjectRandomize(obj, color)
    local gear = Dice.gearOf(obj)
    if gear then
        watchGearDie(obj, color, gear)
    elseif Dice.isBlack(obj) and not throwing then
        -- (While the script throws it, it reads the result itself.)
        Dice.watch(obj, color, function(value, roller)
            if value then
                act(function() race:blackDie(value, roller) end)
            end
        end)
    end
end

-- Cars ------------------------------------------------------------------------

local CAR_NAMES = { ["Formula 1 Solid"] = true, ["Sports Car"] = true }
local CAR_BAG = "1bb99e" -- Formula 1 Black Bag, an infinite bag
-- A car further away than this is somebody else's; take a fresh one instead.
local CLAIM_RANGE = 15
-- How close a dropped car has to land to a dashboard to be claimed by it.
local DROP_RANGE = 4

local function carsClaimed(except)
    local taken = {}
    for _, c in ipairs(race:cars()) do
        if c ~= except and c.tts and c.tts.car then
            taken[c.tts.car] = true
        end
    end
    return taken
end

local function nearestCar(pos, taken, range)
    local best, bestDist = nil, range and range * range or nil
    for _, obj in ipairs(getObjects()) do
        if CAR_NAMES[obj.getName()] and not taken[obj.getGUID()] then
            local p = obj.getPosition()
            local d = (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2
            if not bestDist or d <= bestDist then
                best, bestDist = obj, d
            end
        end
    end
    return best
end

--- The car in the race driving the car object `guid`, if any.
local function carOwning(guid)
    for _, c in ipairs(race:cars()) do
        if c.tts and c.tts.car == guid then
            return c
        end
    end
    return nil
end

--- Where a player's own things belong: their seat, or their dashboard.
local function basePosition(car)
    local dash = car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)
    return handPosition(car.color) or (dash and dash.getPosition())
end

--- What a claimed car is called: hovering it says whose it is.
local function carName(car)
    return race:label(car) .. " (" .. car.color .. ")"
end

local function setCar(car, obj, verb)
    car.tts.car = obj.getGUID()
    car.tts.carWas = car.tts.carWas or obj.getName()
    obj.setName(carName(car))
    obj.setColorTint(tintOf(car.color))
    -- A car that is due stays lit (see showTurn); a timed highlight would end that.
    if race:turn() ~= car then
        obj.highlightOn(car.color, 4)
    end
    -- A car claimed where it stands may already be on the track.
    race:placed(car.color, spaceUnder(obj))
    race:emit("info", race:label(car) .. " " .. verb, car.color)
end

--- Hand a car back: its own name, its own paint.
local function releaseCar(car)
    local obj = car.tts.car and getObjectFromGUID(car.tts.car)
    if obj then
        obj.setName(car.tts.carWas or "")
        obj.setColorTint({ 1, 1, 1 })
    end
    car.tts.car = nil
    car.tts.carWas = nil
    race:placed(car.color, nil)
end

--- Keep the names right as drivers join, leave or are renamed.
syncCars = function()
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        if obj and obj.getName() ~= carName(car) then
            obj.setName(carName(car))
        end
    end
end

-- Pieces on the dashboards ---------------------------------------------------

-- How far from a slot a dropped piece may land and still count, in world units.
local GEAR_REACH = 1.0
local WEAR_REACH = 0.5

--- The car and marker kind ("gear" or a zone id) that `guid` belongs to.
local function markerOwner(guid)
    for _, car in ipairs(race:cars()) do
        local m = car.tts and car.tts.markers
        if m then
            if m.gear == guid then
                return car, "gear"
            end
            for zone, g in pairs(m.wear or {}) do
                if g == guid then
                    return car, zone
                end
            end
        end
    end
    return nil
end

--- The guids of every car's dashboard markers, as a set.
local function markerGuids()
    local out = {}
    for _, car in ipairs(race:cars()) do
        local m = car.tts and car.tts.markers
        if m then
            if m.gear then out[m.gear] = true end
            for _, g in pairs(m.wear or {}) do out[g] = true end
        end
    end
    return out
end

local function shiftTo(color, gear)
    -- A shift starts somebody's turn: the last move's options are done with.
    clearReach()
    act(function() race:shift(color, gear) end)
    Dice.highlight(gear, color)
end

--- A dashboard may have been moved or flipped: redraw it and pull its markers along.
local function dashboardMoved(dash)
    Wait.time(function()
        if dash == nil then return end
        flipping[dash.getGUID()] = nil
        Controls.invalidate(dash)
        syncDashboards(true)
        renderDashboards()
    end, 0.8)
end

function onObjectHover(color, obj)
    Editor.onHover(color, obj)
end

function onObjectDrop(color, obj)
    if Editor.onDropped(obj) then
        return
    end
    if Dashboard.is(obj) then
        dashboardMoved(obj)
        return
    end
    -- A damage marker moved by hand counts on the space it is put down on,
    -- or, off the track, no more.
    local mark = damageMarker(obj.getGUID())
    if mark then
        local space = spaceUnder(obj)
        act(function() race:markerMoved(mark, space) end)
        syncDamage(true) -- back onto the middle of its space
        return
    end
    if CAR_NAMES[obj.getName()] then
        -- Dropping a car on a dashboard claims it for that dashboard's driver.
        local pos = obj.getPosition()
        local taken = carsClaimed(nil)
        for _, c in ipairs(race:cars()) do
            local dash = c.tts.dash and getObjectFromGUID(c.tts.dash)
            if dash and not taken[obj.getGUID()] then
                local p = dash.getPosition()
                if (p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2 <= DROP_RANGE * DROP_RANGE then
                    act(function() setCar(c, obj, "claims the car dropped on their dashboard") end)
                    return
                end
            end
        end
    end
    local owner = carOwning(obj.getGUID())
    if owner or CAR_NAMES[obj.getName()] then
        local space, track, yaw = snapCar(obj)
        if owner then
            -- Put down during its move, the move is judged and charged:
            -- undoable, and the dashboards show the result. Put down after
            -- its roll, the car's turn is over.
            act(function()
                race:placed(owner.color, space and space.id, track)
                race:putDown(owner.color)
            end)
            -- A car that spins there is left pointing backwards.
            if yaw and owner.spun then
                obj.setRotationSmooth({ x = 0, y = yaw + 180, z = 0 }, false, true)
            end
        end
        return
    end
    local car, kind = markerOwner(obj.getGUID())
    local dash = car and car.tts.dash and getObjectFromGUID(car.tts.dash)
    if not dash then
        return
    end
    local pos = obj.getPosition()
    if kind == "gear" then
        local gear = Dashboard.slotAt(dash, "gear", pos, GEAR_REACH)
        if gear and gear ~= car.gear then
            shiftTo(car.color, gear)
        else
            syncDashboards(true) -- same gear or off the gate: settle it back in its slot
        end
    else
        local value = Dashboard.slotAt(dash, kind, pos, WEAR_REACH)
        if value then
            act(function() race:setWear(car.color, kind, value, "marker moved") end)
        else
            syncDashboards(true)
        end
    end
end

function onObjectRotate(obj, spin, flip, color, oldSpin, oldFlip)
    if Dashboard.is(obj) and flip ~= oldFlip then
        dashboardMoved(obj)
    end
end

function onObjectSpawn(obj)
    Dice.prepare(obj)
    if Dashboard.is(obj) then
        Dashboard.track(obj)
        dashboardMoved(obj)
    end
end

-- Actions --------------------------------------------------------------------
-- Each one is reachable twice: from the buttons on the dashboard object, and
-- from the copy of the dashboard on a player's screen.

local ACTIONS = {
    --- Point the player at their car: theirs if claimed, otherwise the nearest
    -- free one, otherwise a fresh one out of the bag.
    car = function(car)
        local mine = car.tts.car and getObjectFromGUID(car.tts.car)
        if mine then
            if race:turn() ~= car then
                mine.highlightOn(car.color, 4)
            end
            race:emit("info", race:label(car) .. "'s car is highlighted", car.color)
            return
        end
        local base = basePosition(car)
        local found = base and nearestCar(base, carsClaimed(car), CLAIM_RANGE)
        if found then
            setCar(car, found, "claims the nearest car")
            return
        end
        local bag = getObjectFromGUID(CAR_BAG)
        local spot = carSpot(car)
        if not bag or not spot then
            race:emit("warn", race:label(car) .. " has no car nearby -- take one from a car bag", car.color)
            return
        end
        local spawned = bag.takeObject({ position = spot, rotation = { x = 0, y = 0, z = 0 }, smooth = false })
        setCar(car, spawned, "takes a car from the bag")
    end,
    collision = function(car) race:requestCheck(car.color, "collision") end,
    pit = function(car) race:pitStop(car.color) end,
    wearDown = function(car) race:adjust(car.color, nil, -1, "manual") end,
    wearUp = function(car) race:adjust(car.color, nil, 1, "manual") end,
    leave = function(car)
        releaseCar(car)
        local m = car.tts.markers or {}
        local guids = { m.gear }
        for _, g in pairs(m.wear or {}) do
            guids[#guids + 1] = g
        end
        for _, g in pairs(guids) do
            local obj = getObjectFromGUID(g)
            if obj then obj.destruct() end
        end
        race:leave(car.color)
    end,
}

local function runAction(car, name)
    if car and ACTIONS[name] then
        act(function() ACTIONS[name](car) end)
    end
end

-- Dashboard buttons ---------------------------------------------------------
-- TTS calls object buttons as fn(object, playerColor, altClick). The actions
-- apply to the car that owns the dashboard, whoever clicks.

function fdNoop() end

--- Put `color` in the race at dashboard `dash`, with no car yet: the first
-- half of dealing them in. On no button -- Start race deals everybody in --
-- but global, so the tests can seat a driver at a given dashboard.
function joinRace(color, dash)
    if not SEATS[color] or race:car(color) or carOnDash(dash.getGUID()) then
        return
    end
    act(function() joinAt(dash, color) end)
end

--- Put `color` in the race at dashboard `dash`. Called inside act.
joinAt = function(dash, color)
    local car = race:join(color, Player[color] and Player[color].steam_name)
    car.tts = car.tts or {}
    car.tts.dash = dash.getGUID()
    car.tts.faceWarned = nil
    -- Who drives it, so they can be put back in it if they drop out.
    car.tts.steam = Player[color] and Player[color].steam_id
    return car
end

-- Delivery ------------------------------------------------------------------
-- When the host presses Start race, everybody seated is dealt in: a
-- dashboard in front of their seat -- a free one already there, or a fresh
-- one from the bag for the ruleset's face -- and a car beside it. Leave
-- takes them out again.

local DASHBOARD_BAGS = { beginner = "edfadc", advanced = "4eb678" }
-- A free dashboard this close to a seat's hand zone is that seat's.
local SEAT_RANGE = 12
-- How far in front of the hand zone's middle a fresh dashboard goes. The
-- zones sit at the table's rim (z +-38.4, x +-55.7), the board reaches
-- z +-26 and x +-44, and a dashboard is 6.5 deep: 7.8 leaves it clear of
-- both the zone (about 6.4 deep) and the board.
local DASH_AHEAD = 7.8

-- The quick reference: four cards, one of the 2020 mod's bags. They cover
-- the advanced rules (gearbox, body, engine), so only those deal them.
local QUICK_REFERENCE_BAG = "490aa3"

local delivering = {}  -- colour -> true while their dashboard is on its way

--- Deal `color` the quick reference cards under the advanced rules, unless
-- their hand holds them -- or anything -- already: nothing else goes in a
-- hand here.
local function dealReference(color)
    if race.rules.id ~= "advanced" then
        return
    end
    local p = Player[color]
    local hand = p and p.getHandTransform()
    local bag = getObjectFromGUID(QUICK_REFERENCE_BAG)
    if not (hand and bag) or #(p.getHandObjects() or {}) > 0 then
        return
    end
    bag.takeObject({
        position = { x = hand.position.x, y = DROP_Y, z = hand.position.z },
        smooth = false,
        callback_function = function(deck)
            deck.deal(deck.getQuantity(), color)
        end,
    })
end

local function dealIn(color, dash)
    delivering[color] = nil
    if race:car(color) or carOnDash(dash.getGUID()) then
        return
    end
    act(function()
        local car = joinAt(dash, color)
        race:emit("info", race:label(car) .. " is dealt in", color)
        ACTIONS.car(car)
    end)
    dealReference(color)
end

--- Deal `color` in, if they are seated, picked the seat themselves, are not
-- racing yet, and the race has not started.
deliver = function(color)
    local p = Player[color]
    if not SEATS[color] or not (p and p.seated) or delivering[color] or race:car(color)
        or race.state.phase ~= "setup" or joining[p.steam_id or ""] then
        return
    end
    local hand = p.getHandTransform()
    if not hand then
        return
    end
    local taken = {}
    for _, c in ipairs(race:cars()) do
        if c.tts and c.tts.dash then taken[c.tts.dash] = true end
    end
    local near = Dashboard.nearest(hand.position, taken)
    if near then
        local q = near.getPosition()
        if (q.x - hand.position.x) ^ 2 + (q.z - hand.position.z) ^ 2 <= SEAT_RANGE * SEAT_RANGE then
            dealIn(color, near)
            return
        end
    end
    local face = Dashboard.faceFor(race.rules)
    local bag = getObjectFromGUID(DASHBOARD_BAGS[face])
    if not bag then
        return
    end
    -- Straight ahead of the seat, the way its hand zone faces.
    local yaw = hand.rotation and hand.rotation.y or 0
    local ix, iz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
    delivering[color] = true
    -- Should the bag never hand it over, the seat is not held up for good;
    -- dealIn checks again, so a late arrival does no harm.
    Wait.time(function() delivering[color] = nil end, 10)
    bag.takeObject({
        position = { x = hand.position.x + ix * DASH_AHEAD, y = DROP_Y, z = hand.position.z + iz * DASH_AHEAD },
        -- Turned to face the seat; the beginner face is the underside. The
        -- two faces are printed opposite ways up (see fd.data.dashboard), so
        -- the advanced one turns a half turn more to read the right way.
        rotation = { x = 0, y = face == "advanced" and (yaw + 180) % 360 or yaw, z = face == "beginner" and 180 or 0 },
        smooth = false,
        callback_function = function(dash)
            Dashboard.track(dash)
            dealIn(color, dash)
        end,
    })
end

--- Before the start, a car whose dashboard is gone -- deleted, or put away
-- in a bag -- leaves the race, so its seat can be dealt in afresh.
dropDashless = function()
    if race.state.phase ~= "setup" then
        return
    end
    for _, car in ipairs(race:cars()) do
        if not (car.tts and car.tts.dash and getObjectFromGUID(car.tts.dash)) then
            act(function() ACTIONS.leave(car) end)
        end
    end
end

--- Whether every car's object is out of its bag and done spawning, so it
-- can be put on the grid.
local function carsReady()
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        if obj and obj.spawning then
            return false
        end
    end
    return true
end

--- Deal in everybody seated who is not racing yet, then call `onDone` once
-- their dashboards and cars are on the table. A dashboard the bag never hands
-- over stops holding things up after a while (see deliver).
dealInSeated = function(onDone)
    dropDashless()
    for _, color in ipairs(getSeatedPlayers()) do
        deliver(color)
    end
    Wait.condition(function()
        Wait.condition(onDone, carsReady, 5, onDone)
    end, function() return next(delivering) == nil end, 12, onDone)
end

-- The rulebook PDFs, one bag per ruleset; the setup board hides the bags.
local RULEBOOK_BAGS = { beginner = "98b2d2", advanced = "f04a8d" }
-- How far to the left of where the seat's dashboard goes a rulebook lies.
local BOOK_SIDE = 9

--- The race panel's Rules button: put the rulebook for the rules being
-- played in front of the clicker's seat, to the left of their dashboard, or
-- put away the one they have out.
function fdRules(player)
    local color = player.color
    local out = rulebooks[color] and getObjectFromGUID(rulebooks[color])
    rulebooks[color] = nil
    if out then
        out.destruct()
        return
    end
    local hand = SEATS[color] and player.getHandTransform()
    if not hand then
        broadcastToColor("Take a seat to have the rulebook put in front of you.", color, LEVEL_RGB.info)
        return
    end
    local bag = getObjectFromGUID(RULEBOOK_BAGS[race.rules.id] or RULEBOOK_BAGS.beginner)
    if not bag then
        return
    end
    -- Ahead of the seat the way its hand zone faces, as a dashboard goes,
    -- then off to the left, the other side from the car (see carSpot).
    local yaw = hand.rotation and hand.rotation.y or 0
    local ix, iz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
    local p = hand.position
    bag.takeObject({
        position = {
            x = p.x + ix * DASH_AHEAD - iz * BOOK_SIDE,
            y = DROP_Y,
            z = p.z + iz * DASH_AHEAD + ix * BOOK_SIDE,
        },
        rotation = { x = 0, y = yaw, z = 0 },
        smooth = false,
        callback_function = function(book)
            book.setInvisibleTo({})
            rulebooks[color] = book.getGUID()
        end,
    })
end

--- The car driven by the player with steam id `id`, if any.
local function carOf(id)
    for _, car in ipairs(race:cars()) do
        if car.tts and car.tts.steam == id then
            return car
        end
    end
    return nil
end

--- Sort out the seat TTS gave the player with steam id `id`, who has just
-- connected. A driver back from a dropped connection goes back to their own
-- car's colour. Anybody else sitting in a colour with a car in the race --
-- one whose driver is away -- is moved to the spectators, as is anybody in a
-- coloured seat before the start: they pick their own seat. Looked up
-- afresh: they may have left again already.
bench = function(id)
    joining[id] = nil
    local player = nil
    for _, p in ipairs(getPlayers()) do
        if p.steam_id == id then player = p end
    end
    if not player then
        return
    end
    local color = player.color
    local mine = carOf(id)
    if mine then
        if mine.color == color then
            return
        end
        if seatedIn(mine.color) then
            player.broadcast("Somebody is sitting in your " .. mine.color
                .. " seat: once they move, click Drive this car on your dashboard.", LEVEL_RGB.warn)
            return
        end
        player.changeColor(mine.color)
        printToAll(race:label(mine) .. " is back in the " .. mine.color .. " car", LEVEL_RGB.info)
        return
    end
    if not SEATS[color] then
        return
    end
    local there = race:car(color)
    if there then
        player.changeColor("Grey")
        player.broadcast(race:label(there) .. "'s car is waiting for its driver. To drive it instead, click Drive this car on its dashboard.",
            LEVEL_RGB.info)
    elseif race.state.phase == "setup" then
        player.changeColor("Grey")
        player.broadcast("Pick a colour to race in: you get a dashboard and a car when the race starts.", LEVEL_RGB.info)
    end
end

--- "Drive this car", on the dashboard of a car whose driver has left their
-- seat: seat whoever clicks in its colour. Its driver coming back gets their
-- car again; anybody else takes it over, and drives it under their name.
function fdDashTakeOver(dash, color)
    local car = carOnDash(dash.getGUID())
    local p = Player[color]
    if not car or not p or seatedIn(car.color) then
        return
    end
    local driving = race:car(color)
    if driving then
        broadcastToColor("You are driving the " .. driving.color .. " car already.", color, LEVEL_RGB.warn)
        return
    end
    local back = car.tts.steam == p.steam_id
    act(function()
        car.tts.steam = p.steam_id
        car.name = p.steam_name
        race:emit("info", back and (race:label(car) .. " is back in the " .. car.color .. " car")
            or (race:label(car) .. " takes over the " .. car.color .. " car"), car.color)
    end)
    p.changeColor(car.color)
end

local function onDash(dash, name)
    runAction(carOnDash(dash.getGUID()), name)
end

function fdDashCar(dash) onDash(dash, "car") end
function fdDashCollision(dash) onDash(dash, "collision") end
function fdDashPit(dash) onDash(dash, "pit") end
--- Leave, on a dashboard: its own driver leaves, or the host (or a promoted
-- player) takes the car out of the race -- a driver who has dropped out and
-- is not coming back, say.
function fdDashLeave(dash, color)
    local car = carOnDash(dash.getGUID())
    if not car then
        return
    end
    if color ~= car.color then
        if not isAdmin({ color = color }) then
            broadcastToColor("Only " .. race:label(car) .. " or the host can take this car out of the race.",
                color, LEVEL_RGB.warn)
            return
        end
        local p = Player[color]
        printToAll((p and p.steam_name or color) .. " takes " .. race:label(car) .. " out of the race", LEVEL_RGB.info)
    end
    runAction(car, "leave")
end

function fdDashWear(dash, color, alt)
    onDash(dash, alt and "wearUp" or "wearDown")
end

-- The dashboard on screen ----------------------------------------------------
-- TTS calls UI handlers as fn(player, value, elementId); these act on the
-- clicking player's own car.

local function mine(player)
    return race:car(player.color)
end

function fdUiCar(player) runAction(mine(player), "car") end
function fdUiCollision(player) runAction(mine(player), "collision") end
function fdUiPit(player) runAction(mine(player), "pit") end
function fdUiLeave(player) runAction(mine(player), "leave") end

--- Throw the gear die for the player's gear, in its tray on the board: the
-- only way to roll one, as the dice cannot be picked up. It is read once it
-- settles, like any roll.
function fdUiRoll(player)
    local car = mine(player)
    if not car then
        return
    end
    if car.gear == 0 then
        broadcastToColor("Shift into a gear first: click one on your dashboard.", player.color, LEVEL_RGB.warn)
        return
    end
    if throwing or Dice.rolling() then
        broadcastToColor("A die is still rolling in the tray -- roll once it has settled.", player.color, LEVEL_RGB.warn)
        return
    end
    local gear = car.gear
    local die = Dice.throw(gear, player.color, onGearRoll(gear))
    if not die then
        broadcastToColor("The " .. Race.gearName(gear) .. " gear die has gone: another is on its way -- click Roll again in a moment.",
            player.color, LEVEL_RGB.warn)
        restockDice()
        return
    end
    die.highlightOn(player.color, 3)
end

function fdUiShift(player, value)
    local gear = tonumber(value)
    if gear and mine(player) then
        shiftTo(player.color, gear)
    end
end

--- `value` arrives as "<zone>:<number>", e.g. "wp:12". Clicking the number
-- the zone is on already takes one off: the slots start at 1, so that is
-- how a zone gets to 0.
function fdUiWear(player, value)
    local car = mine(player)
    if not car then
        return
    end
    local zone, n = tostring(value):match("^(%a+):(%d+)$")
    if zone then
        n = tonumber(n)
        if car.wear[zone] and math.max(0, car.wear[zone]) == n then
            n = n - 1
        end
        act(function() race:setWear(player.color, zone, n, "set on screen") end)
    end
end

-- Race panel ----------------------------------------------------------------
-- The race-wide controls belong to the host and promoted players. The panel
-- only shows them to those players; the check here covers a click that got
-- through anyway, and the editor's keys and menus, which anyone can reach.

--- Whether `player` may use the race controls. `player` is a TTS Player, or
-- just a colour as the hotkeys and context menus give it.
isAdmin = function(player)
    if player.admin ~= nil then
        return player.admin
    end
    local p = Player[player.color]
    return p and p.admin or false
end

local function admin(player)
    if isAdmin(player) then
        return true
    end
    broadcastToColor("Only the host or a promoted player can use the race controls.", player.color, LEVEL_RGB.warn)
    return false
end

--- The grid is rolled for everybody, on a black die of the script's own:
-- nobody has to wait their turn with the one on the table.
function fdGrid(player)
    if not admin(player) then return end
    printToAll(player.steam_name .. " calls the grid roll", LEVEL_RGB.info)
    gridThrows = 0
    act(function() race:rollForGrid() end)
end

startRace = function(player)
    printToAll(player.steam_name .. " starts the race", LEVEL_RGB.info)
    clearReach()
    act(function() race:startRace() end)
    -- The dice set out by their tray again, any gone missing fetched.
    Wait.time(function()
        layDice(function(n)
            if n > 0 then
                printToAll(string.format("Put %d dice out for the race", n), LEVEL_RGB.info)
            end
        end)
    end, 1)
end

function fdStart(player)
    if not admin(player) then return end
    startRace(player)
end

--- The players in coloured seats.
local function seatedColors()
    local out = {}
    for _, color in ipairs(getSeatedPlayers()) do
        if SEATS[color] then out[#out + 1] = color end
    end
    return out
end

local starting = false -- Start race is dealing players in

--- Start race, on the setup menu: deal in everybody seated, roll the grid
-- and start, after a reset if the last race is over. The grid roll settles
-- its own ties, so the race only waits if it could not. (fdGrid and fdStart
-- are the last two steps, still callable on their own.)
function fdSetupStart(player)
    if not admin(player) or starting then return end
    if race.state.phase == "race" then
        return
    end
    if #race:cars() == 0 and #seatedColors() == 0 then
        broadcastToColor("Nobody is seated yet: players join by taking a coloured seat.", player.color, LEVEL_RGB.warn)
        return
    end
    if race.state.phase == "finished" then
        clearReach()
        act(function() race:reset() end)
    end
    starting = true
    dealInSeated(function()
        starting = false
        if race.state.phase == "race" then
            return
        end
        printToAll(player.steam_name .. " calls the grid roll", LEVEL_RGB.info)
        -- The black die is thrown for each driver in turn; the race starts
        -- once the grid has settled (see act).
        pendingStart = player
        gridThrows = 0
        act(function() race:rollForGrid() end)
    end)
end

--- The map list on the setup menu: put the chosen map on the board.
function fdSetupMap(player, value)
    local phase = race.state.phase
    if not admin(player) or phase == "race" or phase == "grid" then
        return
    end
    local map = Maps.byId[Setup.mapFor(value) or ""]
    local tile = Track.tile()
    if not map or not tile then
        return
    end
    local now = mapOnBoard()
    if now and now.id == map.id then
        return
    end
    local custom = tile.getCustomObject()
    custom.image = Assets.url(map.url)
    custom.secondary_image = custom.image
    tile.setCustomObject(custom)
    -- Reloading takes the race panel with the tile: hold its updates until
    -- it is drawn again (fdMapChanged).
    Hud.hold()
    tile.reload()
    printToAll(player.steam_name .. " puts " .. map.name .. " on the board", LEVEL_RGB.info)
    -- Once the tile is back: the race panel, the menu and the dice follow it.
    Wait.time(function() fdMapChanged() end, 1)
end

--- The race distance field on the setup menu. Anything but a whole number
-- of laps from 1 up is put back to the distance the race has.
--- The Report buttons, on the setup menu and the race panel: TTS opens no
-- browser, so the issue tracker's link goes in a box the player can copy it
-- from. Should this TTS have no such box -- asking for a missing method
-- throws -- it goes to their chat instead.
function fdReportIssue(player)
    local shown = pcall(function()
        player.showInputDialog("Copy this link into your browser to report a bug or suggest an idea:",
            Setup.REPO, function() end)
    end)
    if not shown then
        broadcastToColor("Report a bug or an idea at " .. Setup.REPO, player.color, LEVEL_RGB.info)
    end
end

function fdSetupLaps(player, value)
    if not admin(player) then return end
    local current = race:serialize().laps
    local laps = tonumber(value)
    if not laps or laps ~= math.floor(laps) or laps < 1 or laps > Setup.MAX_LAPS then
        UI.setValue("fds_laps", tostring(current))
        return
    end
    if laps == current then
        return
    end
    printToAll(player.steam_name .. " sets the race distance", LEVEL_RGB.info)
    act(function() race:setLaps(laps) end)
    -- Whether the pit lane is open goes by the distance: marks still out
    -- are drawn again.
    if reachShown then
        showReach(reachShown)
    end
end

--- Turn the dashboards on the table to the face `rules` uses: the rules
-- are being picked, or have been undone. `change`, if given, puts the race
-- under them, once the dashboards to turn are known and before they turn.
local function turnDashboards(rules, change)
    local face, turning = Dashboard.faceFor(rules), {}
    for _, dash in ipairs(Dashboard.all()) do
        if Dashboard.face(dash) ~= face then
            flipping[dash.getGUID()] = true
            turning[#turning + 1] = dash
        end
    end
    if change then
        change()
    end
    for _, dash in ipairs(turning) do
        dash.flip()
        dashboardMoved(dash)
    end
end

--- The rules list on the setup menu: race under the rules picked, by their
-- name. Not during a race; every car starts afresh in the new zones.
function fdSetupRules(player, value)
    local phase = race.state.phase
    if not admin(player) or phase == "race" or phase == "grid" then
        return
    end
    local rules = nil
    for _, r in ipairs(RULESETS) do
        if r.name == value then rules = r end
    end
    if not rules or rules == race.rules then
        return
    end
    printToAll(player.steam_name .. " picks the " .. rules.name, LEVEL_RGB.info)
    clearReach()
    turnDashboards(rules, function()
        act(function() race:setRules(rules) end)
    end)
    -- The screen dashboards, the standings and the menu, for the new rules.
    buildUi()
end

--- A new map is on the board. Reloading the tile took the race panel with
-- it, so it is drawn again; the setup menu says which map it is, turn order
-- goes by its track, its pit boxes take their seats' colours, and the dice
-- move to its name panel.
-- Longest to wait for a reloaded board tile to be ready, in seconds. Past
-- that it is drawn on regardless.
local TILE_WAIT = 15

--- Run `fn` once the board tile is back from a reload and has its image:
-- calls into a tile still loading fail inside TTS ("Object reference not
-- set to an instance of an object"), and stop the script there. A board
-- not yet in the cache can take longer than the second the callers wait.
local function whenTileReady(fn)
    Wait.condition(fn, function()
        local tile = Track.tile()
        return tile ~= nil and not tile.spawning and not tile.loading_custom
    end, TILE_WAIT, fn)
end

function fdMapChanged()
    whenTileReady(function()
        drawPits(useBoardTrack())
        Track.drawIcons()
        buildUi()
        layDice()
        syncDamage(true)
        -- A new map means a reloaded tile, and that has lost its menu.
        boardMenu(Editor.isOpen())
    end)
end

function fdReset(player)
    if not admin(player) then return end
    printToAll(player.steam_name .. " reset the race (Undo restores it)", LEVEL_RGB.info)
    pendingStart = nil
    clearReach()
    act(function() race:reset() end)
end

function fdUndo(player)
    if not admin(player) then return end
    local last = table.remove(undo)
    if not last then
        broadcastToColor("Nothing to undo.", player.color, LEVEL_RGB.info)
        return
    end
    local state = JSON.decode(last)
    local was, had = race.rules, markerGuids()
    race = Race.new(rulesFor(state.rules), state)
    race.autoRolls = true
    pendingStart = nil
    -- Markers put out since -- one per zone of other rules, say -- are not
    -- the race's any more.
    local kept = markerGuids()
    for guid in pairs(had) do
        local obj = not kept[guid] and getObjectFromGUID(guid)
        if obj then obj.destruct() end
    end
    if race.rules ~= was then
        turnDashboards(race.rules)
        buildUi()
    end
    useBoardTrack()
    clearReach()
    -- Undo puts the race back, not the pieces: the board still says where
    -- the cars are.
    for _, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        race:placed(car.color, obj and spaceUnder(obj))
    end
    race:drain() -- re-reading the board is not news
    printToAll(player.steam_name .. " undid the last change", LEVEL_RGB.info)
    -- In case the state undone to has a roll waiting: it is rolled now.
    throwChecks()
    relay(race:drain())
    syncDashboards(true)
    syncDamage(true)
    refresh()
end


-- Track overlay and editor -------------------------------------------------------

local trackShown = nil

--- The track data for the map on the board, if there is any.
local function trackOnBoard()
    local map = mapOnBoard()
    return map and TRACKS[map.id]
end

local function editorStatus()
    if not Editor.isOpen() then
        Setup.setEditor(nil)
        return
    end
    local track = Editor.trackFor(TRACKS[Editor.openId()])
    local _, problems = Editor.problems()
    Setup.setEditor(string.format("Editing %s: %d spaces, %d problem(s) shown red, %d marker(s) out, %d on the grid",
        track.name, #track.spaces, #problems, Editor.markerCount(), Editor.gridCount()))
end

--- Draw the spaces over the board, to check them against the print.
function fdTrack(player)
    if not admin(player) then return end
    if Editor.isOpen() then
        broadcastToColor("The editor is open; close it to hide the spaces.", player.color, LEVEL_RGB.info)
        return
    end
    if trackShown then
        Track.hide()
        Ghosts.clear()
        trackShown = nil
        printToAll("Track overlay off", LEVEL_RGB.info)
        return
    end
    local track = trackOnBoard()
    if not track then
        broadcastToColor("No track data for the map on the board yet.", player.color, LEVEL_RGB.warn)
        return
    end
    local ok, why = Track.show(Editor.trackFor(track))
    if ok then
        Ghosts.show(Editor.trackFor(track))
        trackShown = track.id
        printToAll(string.format("%s: %d spaces", track.name, #Editor.trackFor(track).spaces), LEVEL_RGB.info)
    else
        broadcastToColor("Cannot show the track: " .. why, player.color, LEVEL_RGB.warn)
    end
end

-- How far from a space a car may be put down and still be moved onto it, in
-- cells. Put down further off -- off the track, or between spaces with no
-- free one near -- it stays where it was put.
local SNAP_REACH = 0.9
-- How far above the board face a snapped car is set down; it drops from there.
local SNAP_LIFT = 0.3
-- How far from a space's centre a car counts as on it, in cells: half a
-- cell is as far as a car can be from one space and still nearer to it.
local ON_SPACE = 0.5

--- A car put down on the track: settle it onto the nearest free space, facing
-- the way the track runs. Advisory like the rest -- it only helps a car land
-- neatly on a space the player chose, and does nothing off the track.
-- Returns the space it went to and the track it is on, or nil.
--- The board tile and the track data for the map on it (with any edits
-- made in the editor), or nil if there is none.
local function boardTrack()
    local tile = Track.tile()
    local track = tile and trackOnBoard()
    if not track then
        return nil
    end
    return tile, Editor.trackFor(track)
end

--- Tell the race which track the cars are on, for turn order: after a load
-- or an undo, before any car has been put down on it. Returns the board
-- tile and the track, as boardTrack does.
useBoardTrack = function()
    local tile, track = boardTrack()
    race:useTrack(track)
    return tile, track
end

-- Damage markers -------------------------------------------------------------
-- A piece from the Damage Marker Bag on each space the race has a damage
-- marker on (state.damage), locked flat on the board so the cars sit over
-- it. Kept in step after every change; a piece moved or deleted by hand
-- moves or takes away the race's marker (see onObjectDrop, onObjectDestroy).

local DAMAGE_BAG = "bbc10d"
-- The marker's model is 1.1 units long: scaled to this much of a space.
local DAMAGE_SIZE = 0.55
local DAMAGE_LENGTH = 1.1
-- Height above the board face; each more on the same space a bit higher.
local DAMAGE_LIFT = 0.02
local DAMAGE_STACK = 0.05

damagePieces = {} -- marker id -> guid of its piece
local damageSynced = nil -- the markers as last put out, as ids and spaces

--- The id of the race's marker that the piece `guid` stands for, if any.
damageMarker = function(guid)
    for id, g in pairs(damagePieces) do
        if g == guid then return id end
    end
    return nil
end

syncDamage = function(force)
    -- Unless the markers have changed, or `force` says a piece may be out of
    -- place, nothing to do and no call into the game.
    local parts = {}
    for _, e in ipairs(race.state.damage or {}) do parts[#parts + 1] = e.id .. "@" .. tostring(e.space) end
    local key = table.concat(parts, " ")
    if (key == damageSynced and not force) or (key == "" and next(damagePieces) == nil) then
        damageSynced = key
        return
    end
    damageSynced = key
    local wanted = {}
    for _, e in ipairs(race.state.damage or {}) do wanted[e.id] = true end
    for id, guid in pairs(damagePieces) do
        if not wanted[id] then
            -- Forgotten first, so its going is not taken for a hand's.
            damagePieces[id] = nil
            local obj = getObjectFromGUID(guid)
            if obj then obj.destruct() end
        end
    end
    local tile, track = boardTrack()
    local bag = getObjectFromGUID(DAMAGE_BAG)
    if not track then
        return
    end
    local f = Track.frame(tile, track)
    local k = Track.cellWorld(f, track) * DAMAGE_SIZE / DAMAGE_LENGTH
    local stacked = {}
    for _, e in ipairs(race.state.damage) do
        local pos, yaw = Track.seat(tile, f, track, e.space)
        if pos then
            local n = stacked[e.space] or 0
            stacked[e.space] = n + 1
            local at = { x = pos.x, y = pos.y + DAMAGE_LIFT + n * DAMAGE_STACK, z = pos.z }
            local rot = { x = 0, y = yaw + 90, z = 0 }
            local obj = damagePieces[e.id] and getObjectFromGUID(damagePieces[e.id])
            if obj then
                local p = obj.getPosition()
                if not obj.held_by_color and (p.x - at.x) ^ 2 + (p.z - at.z) ^ 2 > 0.01 then
                    obj.setPositionSmooth(at, false, true)
                    obj.setRotationSmooth(rot, false, true)
                end
            elseif bag then
                obj = bag.takeObject({ position = at, rotation = rot, smooth = false })
                obj.setScale({ k, k, k })
                obj.setLock(true)
                damagePieces[e.id] = obj.getGUID()
            end
        end
    end
end

--- Paint each pit box's half of its garage in the colour of the seat it
-- belongs to, on a map with a pit lane; clear them on one without. Takes
-- the board tile and track from useBoardTrack.
drawPits = function(tile, track)
    Track.setLayer("pits", tile and track and Track.pits(tile, track) or nil)
end

-- How far from the tray, in image pixels, the point the parked dice face
-- is put: any distance does, as only its direction counts.
local DICE_FACING = 200

--- Where the dice tray goes: on the map's name panel, if its track data
-- says where that is, otherwise the middle of the board face; and a point
-- the dice park on the side towards: the way the track's `dice_side` says,
-- or else the middle of the board face. Nil without a board.
local function diceCenter()
    local tile, track = boardTrack()
    tile = tile or Track.tile()
    if not tile then
        return nil
    end
    local b = tile.getBounds()
    local middle = { x = b.center.x, y = b.center.y + b.size.y / 2, z = b.center.z }
    if track and track.dice then
        local _, dir = Editor.diceSide(track)
        local x, y = track.dice[1], track.dice[2]
        return Track.worldOf(tile, track, x, y),
            Track.worldOf(tile, track, x + dir[1] * DICE_FACING, y + dir[2] * DICE_FACING)
    end
    return middle, middle
end

--- Fetch any die that has gone missing in the race, then put the die in
-- play in the tray.
restockDice = function()
    Dice.restock(function(n)
        if n > 0 then
            printToAll(string.format("Put %d missing dice back out", n), LEVEL_RGB.info)
            -- A moment for them to come out of the bag.
            Wait.time(function() activateDie() end, 1)
        end
    end)
end

--- The die in play: the gear of the car to play, if it has one; with
-- none, the tray stays empty. A die that has gone is fetched again.
activateDie = function()
    if throwing then
        return -- the black die has the tray
    end
    local due = race:turn()
    local gear = due and due.gear or 0
    if not Dice.activate(gear) and gear > 0 and not Dice.find(gear) then
        restockDice()
    end
end

--- Lay the dice out by their tray, then put the die in play in it. With
-- `onFetched`, any dice not on the table are fetched first (Dice.setOut),
-- and it is told how many.
layDice = function(onFetched)
    local center, middle = diceCenter()
    if not center then
        return
    end
    if onFetched then
        Dice.setOut(center, middle, onFetched)
    else
        Dice.layout(center, middle)
    end
    activateDie()
end

--- Set a car down at `pos` (on the board face), level and turned to `yaw`.
local function setDown(obj, pos, yaw)
    obj.setPositionSmooth({ x = pos.x, y = pos.y + SNAP_LIFT, z = pos.z }, false, true)
    -- The car models' noses point along their local +Z.
    obj.setRotationSmooth({ x = 0, y = yaw, z = 0 }, false, true)
end

snapCar = function(obj)
    local tile, track = boardTrack()
    if not track then
        return nil
    end
    local others = {}
    for _, c in ipairs(race:cars()) do
        local o = c.tts and c.tts.car ~= obj.getGUID() and c.tts.car and getObjectFromGUID(c.tts.car)
        if o then
            others[#others + 1] = o.getPosition()
        end
    end
    local space, pos, yaw = Track.snap(tile, track, obj.getPosition(), SNAP_REACH, others)
    if not space then
        return nil
    end
    setDown(obj, pos, yaw)
    return space, track, yaw
end

--- Once the grid roll has settled the order, set each claimed car down on
-- its grid space, pole first. Called inside act, so the race notes where
-- they went. A car with no grid space, or no car to move, is left to the
-- players, with a word as to why.
placeOnGrid = function()
    local tile, track = boardTrack()
    local start = track and track.start or {}
    if #start == 0 then
        race:emit("warn", "No starting grid known for the map on the board -- put the cars on the grid by hand")
        return
    end
    race:useTrack(track)
    local f = Track.frame(tile, track)
    for i, car in ipairs(race:cars()) do
        local obj = car.tts and car.tts.car and getObjectFromGUID(car.tts.car)
        local pos, yaw = nil, nil
        if start[i] then
            pos, yaw = Track.seat(tile, f, track, start[i])
        end
        if not obj then
            race:emit("warn", race:label(car) .. " has no car to put on the grid -- press Car", car.color)
        elseif not pos then
            race:emit("warn", string.format("%s starts in place %d, but the grid has only %d -- put the car down by hand",
                race:label(car), i, #start), car.color)
        else
            setDown(obj, pos, yaw)
            race:placed(car.color, start[i])
        end
    end
end

--- The id of the space a car is sitting on, without moving it; nil if it is
-- off the track or there is no track data for the board.
spaceUnder = function(obj)
    local tile, track = boardTrack()
    if not track then
        return nil
    end
    local s = Track.spaceNear(tile, Track.frame(tile, track), track, obj.getPosition(), ON_SPACE)
    return s and s.id
end

--- Mark where the car of `color` can end the move it has just opened, with
-- an icon on each space (see Track.marks): a skull where it would go out of
-- the race, else a turning arrow where it would spin, a speedometer for an
-- overshoot or the brake light for braking, each with a crash badge if it
-- ends beside another car; else the crash for a full roll beside one, or a
-- tick for a full roll that costs nothing. Badges too for damage markers on
-- the way and for a slipstream. No entry on each space the move is blocked
-- from -- by cars in the way, or a pit lane shut to it. Advisory: nothing
-- stops a car going anywhere else.
showReach = function(color)
    local tile, track = boardTrack()
    local reach = track and race:reachable(color, track)
    if not reach then
        clearReach()
        return
    end
    reachShown = color
    local from = race:car(color).move.from
    local marks = {}
    for id, o in pairs(reach) do
        if id ~= from then
            local ahead = race:outcome(color, o)
            local crash = #ahead.touching > 0
            local kind, badges = "clean", {}
            if ahead.out then
                kind = "out"
            else
                if ahead.spin then
                    kind = "spin"
                elseif o.overshoot > 0 or o.brake > 0 then
                    kind = o.overshoot > 0 and "overshoot" or "brake"
                elseif crash then
                    kind = "collision"
                end
                if crash and kind ~= "collision" then badges[#badges + 1] = "collision" end
                if ahead.hazards > 0 then badges[#badges + 1] = "damage" end
                if o.slip then badges[#badges + 1] = "slipstream" end
            end
            marks[#marks + 1] = { id = id, kind = kind, badges = badges }
        end
    end
    for _, id in ipairs(race:blockedSpaces(color, track, reach)) do
        marks[#marks + 1] = { id = id, kind = "blocked" }
    end
    Track.setIcons("reach", Track.marks(tile, track, marks))
end

clearReach = function()
    reachShown = nil
    Track.setIcons("reach", nil)
end

local function pickUpAt(color, pos)
    local n = Editor.grab(pos)
    broadcastToColor(n > 0 and ("Picked up " .. n .. " space(s).") or "No spaces nearby.", color, LEVEL_RGB.info)
    editorStatus()
end

local function addAt(color, pos)
    local s = Editor.add(pos)
    if not s then
        broadcastToColor("The board tile is missing.", color, LEVEL_RGB.warn)
        return
    end
    broadcastToColor("Added space " .. s.id .. " in lane " .. s.lane .. ".", color, LEVEL_RGB.info)
    editorStatus()
end

--- The board layout: where the dice tray and the race panel go on the map
-- on the board. Kept with the track's edits (fd.tts.track_editor), and
-- brought into the repo by import_track.py like the rest of them.
local function layoutTrack(color)
    local track = trackOnBoard()
    if not track then
        broadcastToColor("No track data for the map on the board yet.", color, LEVEL_RGB.warn)
    end
    return Track.tile(), track
end

local function diceAt(color, pos)
    local tile, track = layoutTrack(color)
    if not (tile and track) then return end
    local px, py = Track.pixelOf(tile, track, pos)
    Editor.setDice(track, px, py)
    layDice()
    broadcastToColor(string.format("Dice tray moved to (%d, %d). Save the game to keep it.", px, py),
        color, LEVEL_RGB.info)
end

local function panelAt(color, pos)
    local tile, track = layoutTrack(color)
    if not (tile and track) then return end
    local px, py = Track.pixelOf(tile, track, pos)
    Editor.setPanel(track, px, py)
    buildUi()
    broadcastToColor(string.format("Race panel moved to (%d, %d). Save the game to keep it.", px, py),
        color, LEVEL_RGB.info)
end

local function turnDice(color)
    local tile, track = layoutTrack(color)
    if not (tile and track) then return end
    local side = Editor.turnDice(track)
    if not side then
        broadcastToColor("Put the dice on the board first (Put the dice here).", color, LEVEL_RGB.warn)
        return
    end
    layDice()
    broadcastToColor("The dice now line up along the tray's " .. side
        .. " side (as the board image runs). Save the game to keep it.", color, LEVEL_RGB.info)
end

-- How much each step makes the race panel larger or smaller.
local PANEL_STEP = 1.15

local function scalePanel(color, factor)
    local tile, track = layoutTrack(color)
    if not (tile and track) then return end
    local width = Editor.scalePanel(track, factor)
    if not width then
        broadcastToColor("Put the race panel on the board first (Put the race panel here).", color, LEVEL_RGB.warn)
        return
    end
    buildUi()
    broadcastToColor(string.format("Race panel %d px wide. Save the game to keep it.", width), color, LEVEL_RGB.info)
end

-- Whether the board is open for its layout to be set (fdLayout).
local layoutOn = false

-- Edits kept in the game are used over the track file, so a track fixed in
-- the browser editor (tools/editor/) does not show until they are dropped.
-- Asked twice, within this many seconds, as it cannot be undone.
local DROP_CONFIRM = 10
local dropAsked = {}    -- track id -> when the host first asked

local function useTrackFile(color)
    local track = trackOnBoard()
    if not track then
        broadcastToColor("No track data for the map on the board yet.", color, LEVEL_RGB.warn)
        return
    end
    if not Editor.hasEdits(track.id) then
        broadcastToColor(track.name .. " has no edits in this game: it uses its track file already.",
            color, LEVEL_RGB.info)
        return
    end
    local asked = dropAsked[track.id]
    if not asked or os.time() - asked > DROP_CONFIRM then
        dropAsked[track.id] = os.time()
        broadcastToColor("This drops every edit to " .. track.name .. " made in this game -- spaces, grid, "
            .. "dice and panel -- and uses its track file instead. Choose Use the track file again to confirm.",
            color, LEVEL_RGB.warn)
        return
    end
    dropAsked[track.id] = nil
    Editor.revert(track.id)
    layDice()
    buildUi()
    if Editor.isOpen() then editorStatus() end
    broadcastToColor(track.name .. " now uses its track file. Save the game to keep it that way.",
        color, LEVEL_RGB.info)
end

--- Right-click menu on the board: it knows where the player clicked, so
-- nothing needs a key bound to it. The layout items are always there; the
-- editor's (`on`) only while it is open.
--
-- The tile is kept out of players' hands (its own onLoad), and TTS offers
-- no menu on an object that cannot be interacted with: while the editor or
-- the layout is open it can be, but stays locked, so it cannot be moved.
boardMenu = function(on)
    local tile = Track.tile()
    if not tile then return end
    tile.setLock(true)
    tile.interactable = (on or layoutOn) and true or false
    tile.clearContextMenu()
    -- TTS tells a menu item where the object is, not where it was clicked:
    -- that is the player's pointer, still where they right-clicked, as the
    -- menu opens under it.
    local function item(label, fn)
        tile.addContextMenuItem(label, function(color)
            local player = Player[color]
            if player and admin({ color = color }) then fn(color, player.getPointerPosition()) end
        end)
    end
    item("Put the dice here", diceAt)
    item("Turn the dice", turnDice)
    item("Put the race panel here", panelAt)
    item("Race panel larger", function(color) scalePanel(color, PANEL_STEP) end)
    item("Race panel smaller", function(color) scalePanel(color, 1 / PANEL_STEP) end)
    item("Use the track file", useTrackFile)
    if not on then return end
    item("Pick up spaces here", pickUpAt)
    item("Add a space here", addAt)
    item("Apply track edits", function(color) fdApply({ color = color }) end)
    item("Clear the grid", function(color)
        broadcastToColor(Editor.clearGrid(), color, LEVEL_RGB.info)
        editorStatus()
    end)
end

--- Let the board be right-clicked, for its layout menu, or stop it.
function fdLayout(player)
    if not admin(player) then return end
    layoutOn = not layoutOn
    boardMenu(Editor.isOpen())
    if layoutOn then
        broadcastToColor("Right-click the board: Put the dice here, Turn the dice, Put the race panel here, "
            .. "Race panel larger / smaller, Use the track file (drop this game's edits to it). "
            .. "Press Layout again when done, and save the game to keep it.",
            player.color, LEVEL_RGB.info)
    else
        broadcastToColor("Board layout closed. Save the game to keep it.", player.color, LEVEL_RGB.info)
    end
end

--- Open or close the track editor for the map on the board.
function fdEdit(player)
    if not admin(player) then return end
    if Editor.isOpen() then
        local n = Editor.markerCount()
        Editor.close()
        boardMenu(false)
        Track.hide()
        trackShown = nil
        printToAll(string.format("Track editor closed%s. Save the game to keep the edits.",
            n > 0 and (" (" .. n .. " marker(s) applied)") or ""), LEVEL_RGB.info)
        editorStatus()
        return
    end
    local track = trackOnBoard()
    if not track then
        broadcastToColor("No track data for the map on the board yet.", player.color, LEVEL_RGB.warn)
        return
    end
    Ghosts.clear()               -- the overlay's ghosts; the editor puts out its own
    Editor.onChange = editorStatus
    Editor.open(track)
    boardMenu(true)
    trackShown = track.id
    editorStatus()
    broadcastToColor("Track editor open. Right-click the board: Pick up spaces here. Drag the "
        .. "blocks, Q/E to turn, right-click one for its lane or to delete it, then Apply. "
        .. "(Keys for all of this can be bound in Options > Game Keys, under \"Track editor\".)",
        player.color, LEVEL_RGB.info)
end

function fdApply(player)
    if not admin(player) then return end
    if not Editor.isOpen() then
        return
    end
    local n = Editor.apply()
    editorStatus()
    printToAll(string.format("Applied %d marker(s); links recomputed.", n), LEVEL_RGB.info)
end

--- Getting edits out of the game and into the repo.
function fdExport(player)
    if not admin(player) then return end
    local saved = Editor.save()
    local names = {}
    for id, e in pairs(saved) do
        names[#names + 1] = string.format("%s (%d spaces)", id, #e.spaces)
    end
    if #names == 0 then
        broadcastToColor("No track edits to export yet.", player.color, LEVEL_RGB.info)
        return
    end
    printToAll("Edited: " .. table.concat(names, ", "), LEVEL_RGB.info)
    broadcastToColor("To export: save the game (Menu > Save), then in the repo run "
        .. "python tools/extract/import_track.py -- it writes tracks/<id>.json from the newest save.",
        player.color, LEVEL_RGB.info)
end

local function editorKey(fn)
    return function(color, hovered, pointer, up)
        if up or not admin({ color = color }) then return end
        if not Editor.isOpen() then
            broadcastToColor("Open the track editor first (Edit on the race panel).", color, LEVEL_RGB.warn)
            return
        end
        fn(color, hovered, pointer)
        editorStatus()
    end
end

local function registerEditorKeys()
    local function layoutKey(fn)
        return function(color, _, pointer, up)
            if up or not admin({ color = color }) then return end
            fn(color, pointer)
        end
    end
    addHotkey("Board layout: put the dice here", layoutKey(diceAt))
    addHotkey("Board layout: turn the dice", layoutKey(turnDice))
    addHotkey("Board layout: put the race panel here", layoutKey(panelAt))
    addHotkey("Board layout: race panel larger", layoutKey(function(color) scalePanel(color, PANEL_STEP) end))
    addHotkey("Board layout: race panel smaller", layoutKey(function(color) scalePanel(color, 1 / PANEL_STEP) end))
    addHotkey("Track editor: pick up spaces here", editorKey(function(color, _, pointer)
        pickUpAt(color, pointer)
    end))
    addHotkey("Track editor: add a space here", editorKey(function(color, _, pointer)
        addAt(color, pointer)
    end))
    for lane = 1, 3 do
        addHotkey("Track editor: move space to lane " .. lane, editorKey(function(color, hovered)
            if not Editor.setLane(hovered, lane) then
                broadcastToColor("Point at a space marker first.", color, LEVEL_RGB.warn)
            end
        end))
    end
    addHotkey("Track editor: apply", editorKey(function(color)
        fdApply({ color = color })
    end))
    -- Pressed on one space, then on another: adds the link, or removes it.
    addHotkey("Track editor: link or unlink two spaces", editorKey(function(color, hovered, pointer)
        broadcastToColor(Editor.linkKey(hovered, pointer), color, LEVEL_RGB.info)
    end))
    -- Pressed on each grid space in turn, pole first; again on one takes it off.
    addHotkey("Track editor: mark grid space", editorKey(function(color, hovered, pointer)
        broadcastToColor(Editor.gridKey(hovered, pointer), color, LEVEL_RGB.info)
    end))
end

function onObjectDestroy(obj)
    Dashboard.forget(obj)
    -- A damage marker deleted by hand is gone from the track.
    local mark = damageMarker(obj.getGUID())
    if mark then
        damagePieces[mark] = nil
        act(function() race:markerMoved(mark, nil) end)
    end
    -- A driver's dashboard deleted before the start takes them out of the race.
    local driver = race and race.state.phase == "setup" and carOnDash(obj.getGUID())
    if driver then
        runAction(driver, "leave")
    end
    -- A car's gear stick or wear marker gone: the next update brings a new one.
    local car = markerOwner(obj.getGUID())
    if car then
        synced[car.color] = nil
    end
    if Editor.onDestroyed(obj) then
        editorStatus()
    end
end

--- Called from onLoad: restore saved edits and register the editor's keys.
function setupTrackEditor(saved, strayMarkers)
    Editor.load(saved, strayMarkers)
    registerEditorKeys()
end
