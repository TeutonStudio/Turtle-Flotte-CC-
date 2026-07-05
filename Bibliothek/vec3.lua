-- vec3.lua
-- Kleine, serialisierbare Vektor-Helfer fuer Flottenplanung.

local M = {}

function M.new(x, y, z)
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

function M.copy(v)
    if not v then return nil end
    return { x = v.x, y = v.y, z = v.z }
end

function M.eq(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

function M.add(a, b)
    return M.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

function M.sub(a, b)
    return M.new(a.x - b.x, a.y - b.y, a.z - b.z)
end

function M.manhattan(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

function M.key(v)
    return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
end

function M.fromKey(key)
    local x, y, z = tostring(key):match("^(-?%d+),(-?%d+),(-?%d+)$")
    if not x then return nil end
    return M.new(x, y, z)
end

function M.normalizeBox(a, b)
    return {
        minX = math.min(a.x, b.x), maxX = math.max(a.x, b.x),
        minY = math.min(a.y, b.y), maxY = math.max(a.y, b.y),
        minZ = math.min(a.z, b.z), maxZ = math.max(a.z, b.z),
    }
end

function M.inside(v, box)
    return v and box
       and v.x >= box.minX and v.x <= box.maxX
       and v.y >= box.minY and v.y <= box.maxY
       and v.z >= box.minZ and v.z <= box.maxZ
end

function M.neighbors6(v)
    return {
        M.new(v.x + 1, v.y, v.z),
        M.new(v.x - 1, v.y, v.z),
        M.new(v.x, v.y + 1, v.z),
        M.new(v.x, v.y - 1, v.z),
        M.new(v.x, v.y, v.z + 1),
        M.new(v.x, v.y, v.z - 1),
    }
end

function M.neighbors4(v)
    return {
        M.new(v.x + 1, v.y, v.z),
        M.new(v.x - 1, v.y, v.z),
        M.new(v.x, v.y, v.z + 1),
        M.new(v.x, v.y, v.z - 1),
    }
end

return M
