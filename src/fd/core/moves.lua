-- Where a car can get to with the roll it has: every space it can end its
-- move on, and what ending there costs. No TTS calls.
--
-- A move is `roll` steps along the track's links (on down a lane, or across
-- to the next space in a lane beside it), never through or onto another car.
-- Ending short is braking: on a straight, short of the shortest way there,
-- as a car may not weave to use up its roll; in a corner, short of the
-- longest way there along the arrows. A corner needs a number of stops -- moves ended
-- inside it -- before a car may leave it; leaving early is overshooting,
-- and every space from there on is overshot, in the lane the car left the
-- corner in. Ending in a corner while overshooting does not count as a stop
-- there.
--
-- This only reports what a move does: spaces braked, spaces overshot, stops
-- missed. What those cost is the ruleset's business (fd.rules.*), passed in
-- as `cost` to choose between two ways to the same space.

local Moves = {}

--- What an option costs when nothing better is given: a space of wear per
-- space braked or overshot, and missing two or more stops puts a car out.
function Moves.defaultCost(o)
    if o.missed >= 2 then
        return 1000 + o.brake + o.overshoot
    end
    return o.brake + o.overshoot
end

local function index(track)
    local byId = {}
    for _, s in ipairs(track.spaces) do byId[s.id] = s end
    local stops = {}
    for _, c in ipairs(track.corners or {}) do stops[c.id] = c.stops end
    local line = {}
    for _, id in ipairs(track.finish and track.finish.line or {}) do line[id] = true end
    return byId, stops, line
end

--- The spaces the car on `fromId` can end its move on, having rolled `roll`.
--
-- opts:
--   occupied  id -> true for spaces with other cars on them
--   stops     stops already made in the corner the car is in, counting the
--             one it is sitting on (default: 1 if that is a corner, else 0)
--   cost      function(option) -> number, to prefer one way to a space over
--             another (default Moves.defaultCost)
--
-- Returns id -> option, one per space the car can end on, where an option is:
--   space     the space's id
--   moved     spaces moved
--   brake     spaces short of the roll
--   overshoot spaces moved past a corner left too early (0 if none)
--   missed    stops short in that corner (0 if none)
--   corner    the corner the overshoot left, if any
--   stops     stops made in the corner it ends in, this one included;
--             0 outside a corner or when the stop does not count
--   path      the ids stepped on, `fromId` first
--   crossed   true if the move crossed the finish line: stepped onto one of
--             `track.finish.line`, the space just past it in each lane,
--             from a space not on it
-- Returns nil if `fromId` is not on the track.
function Moves.reach(track, fromId, roll, opts)
    opts = opts or {}
    local byId, need, line = index(track)
    local from = byId[fromId]
    if not from then
        return nil
    end
    local occupied = opts.occupied or {}
    local cost = opts.cost or Moves.defaultCost
    local made = opts.stops
    if made == nil then
        made = from.corner and 1 or 0
    end

    --- What ending the move in state `st`, `moved` spaces on, comes to.
    local function outcome(st, moved)
        local o = {
            space = st.space.id, moved = moved, brake = roll - moved,
            overshoot = st.over and st.over.spaces or 0,
            missed = st.over and st.over.missed or 0,
            corner = st.over and st.over.corner or nil,
            stops = 0,
        }
        if st.space.corner and not st.over then
            o.stops = st.made + 1
        end
        return o
    end

    local function finish(st, moved)
        local o = outcome(st, moved)
        local path, at = {}, st
        o.crossed = false
        while at do
            table.insert(path, 1, at.space.id)
            -- Lanes are staggered, so one line space can lead to another:
            -- that step is along the line, not over it.
            if at.prev and line[at.space.id] and not line[at.prev.space.id] then
                o.crossed = true
            end
            at = at.prev
        end
        o.path = path
        return o
    end

    -- Steps from `a` to each space, going round the cars: a run of straight
    -- steps from `a` may take no more than this. Worked out once per `a`.
    local dists = {}
    local function distFrom(a)
        if dists[a.id] then
            return dists[a.id]
        end
        local d, ring = { [a.id] = 0 }, { a }
        for k = 1, roll do
            local nxt = {}
            for _, s in ipairs(ring) do
                for _, nid in ipairs(s.next or {}) do
                    local t = byId[nid]
                    if t and not occupied[nid] and not d[nid] then
                        d[nid] = k
                        nxt[#nxt + 1] = t
                    end
                end
            end
            ring = nxt
        end
        dists[a.id] = d
        return d
    end

    -- A state is a way of standing on a space after some steps. On a
    -- straight, a run of steps must go the shortest way from where it began
    -- (`run`, where the move started or the car left a corner): lanes there
    -- are staggered by half a cell, so weaving across them takes more steps
    -- to go as far, and a car may not weave to burn off its roll -- what it
    -- does not use going the short way is braking. A step into, through or
    -- out of a corner is free to: the arrows there are the moves, and two
    -- ways along them to one space can differ in length. Of the ways to a
    -- space, the cheapest is kept -- the longest, unless it costs more on
    -- the way -- and of those ending one step count on, the move carries on
    -- from the cheapest per run.
    local start = { space = from, made = made, over = nil, prev = nil, run = from, runAt = 0 }
    local results = { [from.id] = finish(start, 0) }
    local level = { start }
    for moved = 1, roll do
        local best, order = {}, {}
        for _, st in ipairs(level) do
            local s = st.space
            for _, nid in ipairs(s.next or {}) do
                local t = byId[nid]
                local run, runAt, ok = st.run, st.runAt, false
                if t and not occupied[nid] then
                    if s.corner or t.corner then
                        run, runAt, ok = t, moved, true
                    else
                        ok = distFrom(run)[nid] == moved - runAt
                    end
                end
                if ok then
                    local over, tMade = st.over, st.made
                    if over then
                        over = { corner = over.corner, missed = over.missed, spaces = over.spaces + 1 }
                    elseif s.corner and t.corner ~= s.corner and need[s.corner]
                        and st.made < need[s.corner] then
                        over = { corner = s.corner, missed = need[s.corner] - st.made, spaces = 1 }
                    end
                    if t.corner ~= s.corner then
                        tMade = 0
                    end
                    -- Overshooting, a car keeps to its lane.
                    if not over or t.lane == s.lane then
                        local nst = { space = t, made = tMade, over = over, prev = st,
                                      run = run, runAt = runAt }
                        local key = nid .. "<" .. run.id
                        local had = best[key]
                        if not had then
                            order[#order + 1] = key
                            best[key] = nst
                        elseif cost(outcome(nst, moved)) < cost(outcome(had, moved)) then
                            best[key] = nst
                        end
                    end
                end
            end
        end
        level = {}
        for _, key in ipairs(order) do
            local st = best[key]
            local had = results[st.space.id]
            if not had or cost(outcome(st, moved)) <= cost(had) then
                results[st.space.id] = finish(st, moved)
            end
            level[#level + 1] = st
        end
    end
    return results
end

-- Moves.ahead answers, keyed by the track's spaces like fd.core.position.
local aheadCache = setmetatable({}, { __mode = "k" })

--- The corner that matters to a car on `fromId`, and how far away it is:
-- the corner it is in while it still owes stops there, or else the next one
-- along. `stops` is as for Moves.reach. Other cars are left out: this is
-- about the track, not who is on it this turn.
--
-- Returns nil off the track or with no corner ahead, or a table:
--   corner  the corner's id
--   need    stops it takes
--   made    stops made in it so far (0 for the next corner)
--   inside  true for the corner the car is in
--   entry   fewest spaces to reach it (0 inside it)
--   exit    most spaces the car can move and still stop in it: the long
--           way round, by the same rules as Moves.reach
function Moves.ahead(track, fromId, stops)
    local cache = aheadCache[track.spaces]
    if not cache then
        cache = {}
        aheadCache[track.spaces] = cache
    end
    local key = tostring(fromId) .. "/" .. tostring(stops)
    if cache[key] ~= nil then
        return cache[key] or nil
    end
    local byId, need = index(track)
    local from = byId[fromId]
    if not from then
        cache[key] = false
        return nil
    end
    local made = stops
    if made == nil then
        made = from.corner and 1 or 0
    end

    local corner, entry = nil, 0
    if from.corner and made < (need[from.corner] or 0) then
        corner = from.corner
    else
        -- Fewest steps to the first space of another corner.
        local seen, ring, k = { [from.id] = true }, { from }, 0
        while #ring > 0 and not corner do
            k = k + 1
            local nxt = {}
            for _, s in ipairs(ring) do
                for _, nid in ipairs(s.next or {}) do
                    local t = byId[nid]
                    if t and not seen[nid] then
                        seen[nid] = true
                        if t.corner and t.corner ~= from.corner then
                            corner, entry = t.corner, k
                        end
                        nxt[#nxt + 1] = t
                    end
                end
            end
            ring = nxt
        end
    end
    if not corner then
        cache[key] = false
        return nil
    end

    -- Far enough to cross the corner by any way through it, from any lane.
    local size = 0
    for _, s in ipairs(track.spaces) do
        if s.corner == corner then size = size + 1 end
    end
    local exit = entry
    for _, o in pairs(Moves.reach(track, fromId, entry + size + 4, { stops = made })) do
        if byId[o.space].corner == corner and o.overshoot == 0 and o.moved > exit then
            exit = o.moved
        end
    end
    local out = {
        corner = corner, need = need[corner] or 0, made = corner == from.corner and made or 0,
        inside = corner == from.corner, entry = entry, exit = exit,
    }
    cache[key] = out
    return out
end

return Moves
