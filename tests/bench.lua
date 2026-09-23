-- How much work common actions cost, counted against the fake TTS API.
--
-- Not a test: run with  python tools/test_lua.py --bench
-- In TTS the expensive part is rarely the Lua itself but the calls out of it:
-- every UI.setAttribute / setValue goes to every player's client, and every
-- object method crosses from Lua into the game. So this counts those calls for
-- a handful of everyday actions, and times the pure-Lua track graph work.

local function world()
    for name in pairs(package.loaded) do
        if name == "tts_stub" or name:sub(1, 3) == "fd." then
            package.loaded[name] = nil
        end
    end
    local S = require("tts_stub")
    S.object("Gear Stick Bag", { guid = "71d89b", spawns = "Gear Stick" })
    S.object("Wear Tracker Bag", { guid = "a845cd", spawns = "Wear Tracker" })
    S.object("Formula 1 Black Bag", { guid = "1bb99e", spawns = "Formula 1 Solid" })
    for _, n in ipairs({ "First", "Second", "Third", "Fourth", "Fifth", "Sixth" }) do
        S.object(n .. " Gear Dice", { pos = S.vec(40, 1, 40) })
    end
    S.object("Damage Dice")
    -- A realistic table: scenery and pieces the scripts have to look past.
    for i = 1, 150 do
        S.object("Scenery " .. i, { pos = S.vec(i, 1, -i) })
    end
    local Maps = require("fd.data.maps")
    S.board = S.object("Game Board Tile", {
        guid = "ebde54", pos = S.vec(0, 1, 0), size = S.vec(44, 1, 44), scale = S.vec(44, 1, 44),
        custom = { image = Maps.byId.FDMonaco.url },
    })
    S.dashes = {}
    for i, c in ipairs({ "Red", "Blue", "Green", "Yellow" }) do
        S.dashes[c] = S.object("Beginner Dashboard", { pos = S.vec(i * 12, 1, -30), up = S.vec(0, -1, 0) })
        S.player(c, S.vec(i * 12, 1, -38))
    end
    assert(loadfile(ROOT .. "/src/entry/Global.-1.lua"))()
    onLoad("")
    return S
end

local results = {}

local function measure(label, S, fn)
    S.resetCounts()
    local t0 = os.clock()
    fn()
    local ms = (os.clock() - t0) * 1000
    local c = S.counts
    results[#results + 1] = string.format("%-42s UI %5d   object calls %6d   getObjects %3d   %7.1f ms",
        label, c.ui, c.object, c.getObjects, ms)
end

local S = world()
for _, c in ipairs({ "Red", "Blue", "Green", "Yellow" }) do
    S.dashes[c].click("fdDashJoin", c)
end
fdStart({ steam_name = "host", color = "Red" })

measure("WP -1 (one race action)", S, function() S.dashes.Red.click("fdDashWear", "Red") end)
measure("shift gear (drop the gear stick)", S, function()
    local Dashboard = require("fd.tts.dashboard")
    local stick = nil
    for _, o in ipairs(S.objects) do if o.name == "Gear Stick" then stick = o break end end
    local p = Dashboard.worldSlot(S.dashes.Red, "gear", 1)
    stick.pos = S.vec(p.x, p.y, p.z)
    onObjectDrop("Red", stick)
end)
measure("show the track (ghost cars)", S, function() fdTrack({ color = "Red", steam_name = "host" }) end)
fdTrack({ color = "Red", steam_name = "host" })
measure("open the track editor", S, function() fdEdit({ color = "Red", steam_name = "host" }) end)
local Track = require("fd.tts.track")
local FDMonaco = require("fd.data.tracks.FDMonaco")
local sp = FDMonaco.spaces[100]
local here = Track.worldOf(S.board, FDMonaco, sp.pos[1], sp.pos[2])
measure("editor: pick up spaces", S, function() S.board.rightClick("Pick up spaces here", "Red", here) end)
local marker = nil
for _, o in ipairs(S.objects) do if o.name:find("^Space [iom]%.") then marker = o break end end
measure("editor: change a lane", S, function() marker.rightClick("Lane 2", "Red") end)
measure("editor: apply", S, function() S.board.rightClick("Apply track edits", "Red") end)
measure("save the game", S, function() onSave() end)

local Graph = require("fd.core.trackgraph")
local copy = {}
for i, s in ipairs(FDMonaco.spaces) do
    copy[i] = { id = s.id, pos = { s.pos[1], s.pos[2] }, rot = s.rot, lane = s.lane, next = {} }
end
local t0 = os.clock()
Graph.relink(copy)
local relinkMs = (os.clock() - t0) * 1000
t0 = os.clock()
Graph.problems(copy)
local problemsMs = (os.clock() - t0) * 1000

print("")
for _, r in ipairs(results) do print("  " .. r) end
print(string.format("  %-42s %7.1f ms", "track graph: relink " .. #copy .. " spaces", relinkMs))
print(string.format("  %-42s %7.1f ms", "track graph: find problems", problemsMs))
return {}
