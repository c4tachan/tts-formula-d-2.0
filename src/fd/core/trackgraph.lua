-- The space graph of a track: which spaces lead to which, and what looks wrong.
--
-- Positions are image pixels and facings degrees in image space (0 = right,
-- clockwise, since image y runs down), as in the track files. No TTS calls,
-- so the editor's rules can be tested outside the game.
--
-- Every question here is about a space's neighbours, so spaces are filed in
-- a grid of buckets and each one only looks at the buckets around it. Checking
-- every pair instead took a noticeable pause per edit on a 500-space track --
-- and TTS runs Lua several times slower than a desktop Lua does.

local Graph = {}

local function dist(a, b)
    local dx, dy = a.pos[1] - b.pos[1], a.pos[2] - b.pos[2]
    return math.sqrt(dx * dx + dy * dy)
end

local function facing(s)
    local r = math.rad(s.rot)
    return math.cos(r), math.sin(r)
end

--- How far ahead of `s` another space `o` sits, and how far off to the side.
local function relative(s, fx, fy, o)
    local dx, dy = o.pos[1] - s.pos[1], o.pos[2] - s.pos[2]
    return dx * fx + dy * fy, math.abs(dx * fy - dy * fx)
end

--- Spaces filed by position, `size` pixels to a bucket.
local function newGrid(spaces, size)
    local cells = {}
    for _, s in ipairs(spaces) do
        local key = math.floor(s.pos[1] / size) * 65536 + math.floor(s.pos[2] / size)
        local b = cells[key]
        if not b then
            b = {}
            cells[key] = b
        end
        b[#b + 1] = s
    end
    return { size = size, cells = cells }
end

--- Call fn(o) for every space in the buckets within `r` of (x, y).
local function around(g, x, y, r, fn)
    local size = g.size
    for kx = math.floor((x - r) / size), math.floor((x + r) / size) do
        for ky = math.floor((y - r) / size), math.floor((y + r) / size) do
            local b = g.cells[kx * 65536 + ky]
            if b then
                for i = 1, #b do fn(b[i]) end
            end
        end
    end
end

local function byLane(spaces, size)
    local lanes, grids = {}, {}
    for _, s in ipairs(spaces) do
        lanes[s.lane] = lanes[s.lane] or {}
        table.insert(lanes[s.lane], s)
    end
    for l, list in pairs(lanes) do grids[l] = newGrid(list, size) end
    return grids
end

--- The typical distance from a space to the next one in its lane.
function Graph.cellLength(spaces)
    if #spaces < 2 then return 0 end
    -- The spacing isn't known yet, so look in widening circles: once a space
    -- ahead turns up within the circle, nothing outside it can be nearer.
    local grids = byLane(spaces, 64)
    local gaps = {}
    for _, s in ipairs(spaces) do
        local fx, fy = facing(s)
        local g = grids[s.lane]
        local r = 64
        while r <= 1024 do
            local best = nil
            around(g, s.pos[1], s.pos[2], r, function(o)
                if o ~= s then
                    local ahead, side = relative(s, fx, fy, o)
                    if ahead > 0 and side < ahead then
                        local d = dist(s, o)
                        if d <= r and (not best or d < best) then best = d end
                    end
                end
            end)
            if best then
                gaps[#gaps + 1] = best
                break
            end
            r = r * 2
        end
    end
    if #gaps == 0 then return 0 end
    table.sort(gaps)
    return gaps[math.ceil(#gaps / 2)]
end

--- Recompute every space's links from where the spaces are.
--
-- A car moves to the next space in its lane, or diagonally into a lane
-- beside it: that is the nearest space ahead in the neighbouring lane, the
-- one touching this one's front. (Not the one nearest where the straight
-- move lands: lanes are staggered by half a cell, so the spaces either side
-- of that point are equally near it, and the far one skips a space.) Only
-- spaces ahead and within reach count, so a missing space leaves a visible
-- gap rather than a link across the infield.
-- Returns the cell length it worked with, for problems() to reuse.
function Graph.relink(spaces, reachCells)
    local cell = Graph.cellLength(spaces)
    if cell <= 0 then
        for _, s in ipairs(spaces) do s.next = {} end
        return cell
    end
    local reach = cell * (reachCells or 2.2)
    local grids = byLane(spaces, reach)
    local function nearestAhead(s, fx, fy, g, cone)
        if not g then return nil end
        local best, bestD = nil, nil
        around(g, s.pos[1], s.pos[2], reach, function(o)
            if o ~= s then
                local ahead, side = relative(s, fx, fy, o)
                local d = dist(s, o)
                if ahead > 0.25 * cell and side <= cone * ahead + 0.6 * cell and d <= reach then
                    if not bestD or d < bestD then best, bestD = o, d end
                end
            end
        end)
        return best
    end
    -- At the apex of a tight hairpin the track turns so fast that the next
    -- space sits almost square to this one's facing, and nothing passes the
    -- test above. Judged by the direction halfway between the two spaces'
    -- facings -- the way the road actually turns there -- it is ahead.
    local function turningAhead(s, fx, fy, g)
        if not g then return nil end
        local best, bestD = nil, nil
        around(g, s.pos[1], s.pos[2], 1.6 * cell, function(o)
            if o ~= s then
                local gx, gy = facing(o)
                local bx, by = fx + gx, fy + gy
                local n = math.sqrt(bx * bx + by * by)
                local d = dist(s, o)
                if n > 1e-6 and d <= 1.6 * cell then
                    local ahead = ((o.pos[1] - s.pos[1]) * bx + (o.pos[2] - s.pos[2]) * by) / n
                    if ahead > 0 and (not bestD or d < bestD) then best, bestD = o, d end
                end
            end
        end)
        return best
    end
    for _, s in ipairs(spaces) do
        -- Links set by hand are kept as they are.
        if not s.fixed then
            local fx, fy = facing(s)
            local straight = nearestAhead(s, fx, fy, grids[s.lane], 0.5)
                or turningAhead(s, fx, fy, grids[s.lane])
            local nxt = {}
            if straight then nxt[#nxt + 1] = straight.id end
            for _, l in ipairs({ s.lane - 1, s.lane + 1 }) do
                local diag = nearestAhead(s, fx, fy, grids[l], 1.2)
                if diag then nxt[#nxt + 1] = diag.id end
            end
            table.sort(nxt)
            s.next = nxt
        end
    end
    return cell
end

--- Things that look wrong, as { id = space id, text = why }.
function Graph.problems(spaces, cell)
    cell = cell or Graph.cellLength(spaces)
    local byId, out = {}, {}
    for _, s in ipairs(spaces) do byId[s.id] = s end
    local close = 0.3 * cell
    local g = close > 0 and newGrid(spaces, close) or nil
    -- A space turned the wrong way round links backwards and parks cars
    -- backwards, but nothing else about it looks odd; its neighbours give it
    -- away, all facing the other way.
    local near = 1.2 * cell
    local wide = near > 0 and newGrid(spaces, near) or nil
    for _, s in ipairs(spaces) do
        if wide then
            local fx, fy = facing(s)
            local along, against = 0, 0
            around(wide, s.pos[1], s.pos[2], near, function(o)
                if o ~= s and dist(s, o) < near then
                    local ox, oy = facing(o)
                    if fx * ox + fy * oy < 0 then against = against + 1 else along = along + 1 end
                end
            end)
            if against >= 2 and against > along then
                out[#out + 1] = { id = s.id, text = "faces against the spaces around it" }
            end
        end
        local straight = false
        for _, n in ipairs(s.next or {}) do
            local o = byId[n]
            if o and o.lane == s.lane then straight = true end
            if o and dist(s, o) > 2.2 * cell then
                out[#out + 1] = { id = s.id, text = "link to space " .. n .. " is unusually long" }
            end
        end
        if not straight then
            out[#out + 1] = { id = s.id, text = "no space ahead in lane " .. s.lane }
        end
        if g then
            around(g, s.pos[1], s.pos[2], close, function(o)
                if o.id > s.id and dist(s, o) < close then
                    out[#out + 1] = { id = s.id, text = "on top of space " .. o.id }
                end
            end)
        end
        -- In a corner a space leads across a lane one way or the other, never
        -- both: the arrows printed there fork towards one side only. (On a
        -- straight both ways is the rule.)
        local sides = {}
        for _, n in ipairs(s.next or {}) do
            local o = byId[n]
            if o and o.lane ~= s.lane then sides[o.lane < s.lane and "in" or "out"] = n end
        end
        if s.corner and sides["in"] and sides["out"] then
            out[#out + 1] = { id = s.id,
                text = "leads both ways across the lanes, to " .. sides["in"] .. " and " .. sides["out"] }
        end
    end
    -- In a corner two spaces in one lane never lead to the same space in
    -- another: the arrows across a lane are printed in step with it.
    local from = {}
    for _, s in ipairs(spaces) do
        for _, n in ipairs(s.corner and s.next or {}) do
            local o = byId[n]
            if o and o.lane ~= s.lane then
                local key = s.lane .. ":" .. n
                if from[key] then
                    out[#out + 1] = { id = s.id,
                        text = "leads to space " .. n .. ", and so does space " .. from[key] }
                else
                    from[key] = s.id
                end
            end
        end
    end
    return out
end

--- The space nearest a point, and how far away it is.
function Graph.nearest(spaces, x, y)
    local best, bestD = nil, nil
    for _, s in ipairs(spaces) do
        local dx, dy = s.pos[1] - x, s.pos[2] - y
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = s, d end
    end
    return best, bestD and math.sqrt(bestD) or nil
end

return Graph
