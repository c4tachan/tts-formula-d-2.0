-- How far round the track each space lies, for turn order. No TTS calls.
--
-- A lane's own count of spaces says little about how far along a space is:
-- round a corner the outside lane has twice the spaces of the inside, and on
-- a straight the lanes are staggered by half a cell. So distance is measured
-- on one line instead: the middle lane, followed from the finish line round
-- the lap. Each space is dropped square onto that line, which round a bend
-- is along the radius -- spaces printed level with each other across a
-- corner land together -- and on a straight keeps the stagger.
--
-- The same drop says how far off to the side a space is. With the way each
-- corner turns, that tells which of two level cars is nearer its inside.

local Position = {}

-- Worked out once per track: keyed by its spaces, which the editor's copy of
-- a track shares with it.
local cache = setmetatable({}, { __mode = "k" })

local function wrap(deg)
    deg = deg % 360
    if deg > 180 then deg = deg - 360 end
    return deg
end

--- The middle lane's spaces, from the finish line once round the lap. Where
-- that lane has no space ahead, the chain steps to the lane nearest it.
local function chain(track, byId)
    local lanes = {}
    for _, s in ipairs(track.spaces) do lanes[s.lane] = true end
    local lo, hi = nil, nil
    for l in pairs(lanes) do
        if not lo or l < lo then lo = l end
        if not hi or l > hi then hi = l end
    end
    if not lo then
        return nil
    end
    local mid = math.floor((lo + hi) / 2 + 0.5)
    local line, first = {}, nil
    for _, id in ipairs(track.finish and track.finish.line or {}) do
        local s = byId[id]
        if s then
            line[id] = true
            if not first or math.abs(s.lane - mid) < math.abs(first.lane - mid) then first = s end
        end
    end
    if not first then
        return nil
    end
    local out, seen, at = { first }, { [first.id] = true }, first
    while true do
        local best = nil
        for _, nid in ipairs(at.next or {}) do
            local t = byId[nid]
            if t and (not best or math.abs(t.lane - mid) < math.abs(best.lane - mid)) then best = t end
        end
        if not best or line[best.id] or seen[best.id] then
            break
        end
        out[#out + 1] = best
        seen[best.id] = true
        at = best
    end
    return out
end

--- Where `track`'s spaces lie round the lap, or nil without a finish line
-- to measure from:
--   along   id -> distance past the line along the middle lane, in pixels;
--           a space level with the line in a staggered lane can be a little
--           below 0
--   side    id -> how far right of that line it lies, in pixels
--   corner  id -> the corner a space is in, or else the next one ahead
--   turn    corner id -> 1 if its inside is on the right, -1 if on the left
--   length  the lap, in pixels
--   cell    the typical distance between spaces along it
function Position.of(track)
    local key = track.spaces
    if cache[key] ~= nil then
        return cache[key] or nil
    end
    local byId = {}
    for _, s in ipairs(track.spaces) do byId[s.id] = s end
    local pts = chain(track, byId)
    local placed = pts and #pts >= 3
    for _, s in ipairs(placed and track.spaces or {}) do
        if not s.pos then placed = false end
    end
    if not placed then
        cache[key] = false
        return nil
    end

    -- Sectors in running order, as the chain meets them.
    local sectorAt, sectors = {}, {}
    for _, p in ipairs(pts) do
        if p.sector and not sectorAt[p.sector] then
            sectors[#sectors + 1] = p.sector
            sectorAt[p.sector] = #sectors
        end
    end

    -- Segment i runs from pts[i] to pts[i + 1]; the last closes the lap.
    local segs, cum, gaps = {}, 0, {}
    for i, a in ipairs(pts) do
        local b = pts[i % #pts + 1]
        local dx, dy = b.pos[1] - a.pos[1], b.pos[2] - a.pos[2]
        local len = math.sqrt(dx * dx + dy * dy)
        segs[i] = { a = a, dx = dx, dy = dy, len = len, from = cum,
            sectors = { [a.sector or ""] = true, [b.sector or ""] = true } }
        cum = cum + len
        gaps[#gaps + 1] = len
    end
    local closing = segs[#segs]
    table.sort(gaps)
    local P = {
        along = {}, side = {}, corner = {}, turn = {},
        length = cum, cell = gaps[math.ceil(#gaps / 2)],
    }
    local firstSector = pts[1].sector

    -- Drop each space onto the nearest segment touching its own sector
    -- (every segment if it has none on the chain). The closing segment is
    -- not a way to the first sector's spaces: they are past the line, and
    -- one level with it in a staggered lane measures back off the first
    -- segment instead.
    for _, s in ipairs(track.spaces) do
        local own = s.sector and sectorAt[s.sector] and s.sector
        local best, bestD, bestT = nil, nil, nil
        for i, g in ipairs(segs) do
            if g.len > 0 and (not own or g.sectors[own]) and not (g == closing and own == firstSector) then
                local px, py = s.pos[1] - g.a.pos[1], s.pos[2] - g.a.pos[2]
                local t = (px * g.dx + py * g.dy) / (g.len * g.len)
                local tc = math.max(0, math.min(1, t))
                if i == 1 and t < 0 then tc = t end
                local ex, ey = px - tc * g.dx, py - tc * g.dy
                local d = ex * ex + ey * ey
                if not bestD or d < bestD then best, bestD, bestT = g, d, tc end
            end
        end
        if best then
            local px, py = s.pos[1] - best.a.pos[1], s.pos[2] - best.a.pos[2]
            P.along[s.id] = best.from + bestT * best.len
            -- Right of the way the line runs; image y points down.
            P.side[s.id] = (px * -best.dy + py * best.dx) / best.len
        end
    end

    -- Which way each corner turns. Its inside is the lane with the fewest
    -- spaces, the short way round: that holds for a chicane too, where the
    -- heading ends up about where it started. Where every lane has as many,
    -- the heading's change across it decides.
    local lanes = {}
    for _, s in ipairs(track.spaces) do
        if s.corner and P.side[s.id] then
            local c = lanes[s.corner] or {}
            lanes[s.corner] = c
            local l = c[s.lane] or { n = 0, side = 0 }
            c[s.lane] = l
            l.n = l.n + 1
            l.side = l.side + P.side[s.id]
        end
    end
    local heading = {}
    for i, p in ipairs(pts) do
        if p.corner and i > 1 then
            heading[p.corner] = (heading[p.corner] or 0) + wrap(p.rot - pts[i - 1].rot)
        end
    end
    for id, c in pairs(lanes) do
        local lo, hi = nil, nil
        for l in pairs(c) do
            if not lo or l < lo then lo = l end
            if not hi or l > hi then hi = l end
        end
        local a, b = c[lo], c[hi]
        if a.n ~= b.n then
            local short, long = a, b
            if b.n < a.n then short, long = b, a end
            P.turn[id] = short.side / short.n > long.side / long.n and 1 or -1
        else
            P.turn[id] = (heading[id] or 0) >= 0 and 1 or -1
        end
    end

    -- The corner each sector is in or leads to; after the last, the first.
    local cornerOf = {}
    for _, p in ipairs(pts) do
        if p.corner and p.sector then cornerOf[p.sector] = p.corner end
    end
    local ahead = {}
    for i = 1, #sectors do
        for j = 0, #sectors - 1 do
            local c = cornerOf[sectors[(i - 1 + j) % #sectors + 1]]
            if c then
                ahead[sectors[i]] = c
                break
            end
        end
    end
    for _, s in ipairs(track.spaces) do
        P.corner[s.id] = s.corner or (s.sector and ahead[s.sector]) or nil
    end

    cache[key] = P
    return P
end

--- How far toward the inside of the corner it is in or heading for the
-- space `id` lies, in pixels: more is further in. 0 if not known.
function Position.inside(P, id)
    local c = P.corner[id]
    local turn = c and P.turn[c]
    if not turn or not P.side[id] then
        return 0
    end
    return turn * P.side[id]
end

return Position
