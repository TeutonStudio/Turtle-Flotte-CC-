-- terrain.lua
-- Geländespeicher und einfache Abbauplanung.

local vec3 = require("vec3")
local M = {}

function M.new()
    return { blocks = {}, air = {}, blocked = {}, support = {} }
end

function M.markBlock(t, pos, block)
    t.blocks[vec3.key(pos)] = block or { name = "unknown" }
    t.air[vec3.key(pos)] = nil
end

function M.markAir(t, pos)
    t.air[vec3.key(pos)] = true
    t.blocks[vec3.key(pos)] = nil
end

function M.markBlocked(t, pos, block)
    t.blocked[vec3.key(pos)] = block or { name = "unknown" }
    M.markBlock(t, pos, block)
end

function M.markSupport(t, pos, hasSupport)
    t.support[vec3.key(pos)] = hasSupport and true or false
end

function M.getHighestInBox(t, box)
    local highest = nil
    for key, block in pairs(t.blocks) do
        local pos = vec3.fromKey(key)
        if pos and vec3.inside(pos, box) and (not highest or pos.y > highest.y) then
            highest = vec3.copy(pos)
            highest.block = block
        end
    end
    return highest
end

function M.splitAreaIntoColumns(box)
    local tasks = {}
    for x = box.minX, box.maxX do
        for z = box.minZ, box.maxZ do
            tasks[#tasks + 1] = { x = x, z = z, minY = box.minY, maxY = box.maxY }
        end
    end
    return tasks
end

function M.nextScanTasks(box)
    local tasks = {}
    for _, col in ipairs(M.splitAreaIntoColumns(box)) do
        tasks[#tasks + 1] = { kind = "scan_column", payload = col }
    end
    return tasks
end

function M.outerRing(area, y)
    local points = {}
    for x = area.minX, area.maxX do
        points[#points + 1] = vec3.new(x, y, area.minZ)
        if area.maxZ ~= area.minZ then points[#points + 1] = vec3.new(x, y, area.maxZ) end
    end
    for z = area.minZ + 1, area.maxZ - 1 do
        points[#points + 1] = vec3.new(area.minX, y, z)
        if area.maxX ~= area.minX then points[#points + 1] = vec3.new(area.maxX, y, z) end
    end
    return points
end

function M.shrinkBox(area, amount)
    amount = amount or 1
    if area.minX + amount > area.maxX - amount or area.minZ + amount > area.maxZ - amount then return nil end
    return {
        minX = area.minX + amount, maxX = area.maxX - amount,
        minY = area.minY, maxY = area.maxY,
        minZ = area.minZ + amount, maxZ = area.maxZ - amount,
    }
end

function M.splitLayerOuterToInner(area, y)
    local layers = {}
    local current = {
        minX = area.minX, maxX = area.maxX,
        minY = area.minY, maxY = area.maxY,
        minZ = area.minZ, maxZ = area.maxZ,
    }
    while current do
        local ring = M.outerRing(current, y)
        if #ring == 0 then break end
        layers[#layers + 1] = ring
        current = M.shrinkBox(current, 1)
    end
    return layers
end

return M
