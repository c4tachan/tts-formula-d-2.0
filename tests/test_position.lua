local Position = require("fd.core.position")
local FDMonaco = require("fd.data.tracks.FDMonaco")

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

local T = {}

function T.every_link_on_monaco_leads_forward()
    local P = Position.of(FDMonaco)
    local line = {}
    for _, id in ipairs(FDMonaco.finish.line) do line[id] = true end
    for _, s in ipairs(FDMonaco.spaces) do
        assert(P.along[s.id], s.id .. " has no place round the lap")
        for _, n in ipairs(s.next) do
            if not line[n] then
                assert(P.along[n] > P.along[s.id], s.id .. " -> " .. n .. " runs backwards")
            end
        end
    end
end

function T.the_monaco_grid_runs_back_from_pole()
    local P = Position.of(FDMonaco)
    for i = 2, #FDMonaco.start do
        assert(P.along[FDMonaco.start[i]] < P.along[FDMonaco.start[i - 1]],
            FDMonaco.start[i] .. " should be behind " .. FDMonaco.start[i - 1])
    end
end

function T.the_lane_with_fewest_spaces_in_a_corner_is_its_inside()
    local P = Position.of(FDMonaco)
    for _, c in ipairs(FDMonaco.corners) do
        local count, inside = {}, {}
        for _, s in ipairs(FDMonaco.spaces) do
            if s.corner == c.id then
                count[s.lane] = (count[s.lane] or 0) + 1
                inside[s.lane] = (inside[s.lane] or 0) + Position.inside(P, s.id)
            end
        end
        if count[1] ~= count[3] then
            local fewest = count[1] < count[3] and 1 or 3
            local other = 4 - fewest
            assert(inside[fewest] / count[fewest] > inside[other] / count[other],
                "corner " .. c.id .. ": lane " .. fewest .. " is the inside")
        end
    end
end

function T.straights_keep_the_stagger_and_corners_line_up()
    local P = Position.of(FDMonaco)
    local cells = function(a, b) return (P.along[b] - P.along[a]) / P.cell end
    assert(math.abs(cells("i.s2.5", "m.s2.5") - 0.5) < 0.1, "the middle lane is half a cell on")
    assert(math.abs(cells("i.s2.8", "o.s2.7")) < 0.1, "the outside lanes are level")
    assert(math.abs(cells("i.c5.6", "o.c5.1")) < 0.1, "printed level across a corner")
end

function T.a_track_without_positions_or_a_line_has_none()
    eq(Position.of({ spaces = { { id = "a", lane = 1, next = {} } } }), nil)
    eq(Position.of({ spaces = { { id = "a", lane = 1, next = { "b" } }, { id = "b", lane = 1, next = {} } },
        finish = { line = { "a" } } }), nil)
end

return T
