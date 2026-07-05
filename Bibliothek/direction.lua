-- direction.lua
-- Richtungen: 0=north, 1=east, 2=south, 3=west.

local vec3 = require("vec3")
local M = {}

local NAMES = { [0] = "north", [1] = "east", [2] = "south", [3] = "west" }
local BY_NAME = { north = 0, east = 1, south = 2, west = 3 }
local VECTORS = {
    [0] = vec3.new(0, 0, -1),
    [1] = vec3.new(1, 0, 0),
    [2] = vec3.new(0, 0, 1),
    [3] = vec3.new(-1, 0, 0),
}

function M.fromName(name)
    if type(name) == "number" then return name % 4 end
    return BY_NAME[tostring(name or ""):lower()]
end

function M.toName(dir)
    if dir == nil then return nil end
    return NAMES[dir % 4]
end

function M.left(dir) return (dir - 1) % 4 end
function M.right(dir) return (dir + 1) % 4 end
function M.back(dir) return (dir + 2) % 4 end

function M.toVector(dir)
    return vec3.copy(VECTORS[dir % 4])
end

function M.fromDelta(dx, dz)
    if dx == 1 and dz == 0 then return 1 end
    if dx == -1 and dz == 0 then return 3 end
    if dx == 0 and dz == 1 then return 2 end
    if dx == 0 and dz == -1 then return 0 end
    return nil
end

function M.relativeSideToWorld(facing, side)
    facing = M.fromName(facing)
    if not facing then return nil end
    if side == "front" then return facing end
    if side == "back" then return M.back(facing) end
    if side == "left" then return M.left(facing) end
    if side == "right" then return M.right(facing) end
    return nil
end

function M.turnPlan(from, to)
    from = M.fromName(from)
    to = M.fromName(to)
    if not from or not to then return nil end
    local diff = (to - from) % 4
    if diff == 0 then return {} end
    if diff == 1 then return { "right" } end
    if diff == 3 then return { "left" } end
    return { "right", "right" }
end

return M
