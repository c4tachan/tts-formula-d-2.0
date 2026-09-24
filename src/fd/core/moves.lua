-- Where a car can get to with the roll it has: every space it can end its
-- move on, and what ending there costs. No TTS calls.
--
-- A move is `roll` steps along the track's links (on down a lane, or across
-- to the next space in a lane beside it), never through or onto another car.
-- Ending short is braking. A corner needs a number of stops -- moves ended
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
--             `track.finish.line`, the space just past it in each lane
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
            if at.prev and line[at.space.id] then
                o.crossed = true
            end
            at = at.prev
        end
        o.path = path
        return o
    end

    -- A state is a way of standing on a space after some steps. Each space
    -- is only reached the shortest way: lanes on a straight are staggered
    -- by half a cell, so weaving across them takes more steps to go as far,
    -- and a car may not weave to burn off its roll -- what it does not use
    -- going the short way is braking. Of the ways to a space that are
    -- equally short, the cheapest is kept, and the move carries on from it.
    local start = { space = from, made = made, over = nil, prev = nil }
    local results = { [from.id] = finish(start, 0) }
    local level = { start }
    for moved = 1, roll do
        local best, order = {}, {}
        for _, st in ipairs(level) do
            local s = st.space
            for _, nid in ipairs(s.next or {}) do
                local t = byId[nid]
                if t and not occupied[nid] and not results[nid] then
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
                        local nst = { space = t, made = tMade, over = over, prev = st }
                        local had = best[nid]
                        if not had then
                            order[#order + 1] = nid
                            best[nid] = nst
                        elseif cost(outcome(nst, moved)) < cost(outcome(had, moved)) then
                            best[nid] = nst
                        end
                    end
                end
            end
        end
        level = {}
        for _, id in ipairs(order) do
            results[id] = finish(best[id], moved)
            level[#level + 1] = best[id]
        end
    end
    return results
end

return Moves
