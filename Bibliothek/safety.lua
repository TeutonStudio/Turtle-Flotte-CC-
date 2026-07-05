-- safety.lua
-- Sicherheitslogik gegen Herunterfallen.

local vec3 = require("vec3")
local M = {}

function M.hasSupportBelowCurrent()
    if turtle and turtle.inspectDown then
        local ok = turtle.inspectDown()
        return ok
    end
    return nil
end

function M.hasKnownSupportBelow(pos, knownTerrain)
    if not pos or not knownTerrain or not knownTerrain.support then return nil end
    local key = vec3.key(vec3.new(pos.x, pos.y - 1, pos.z))
    return knownTerrain.support[key]
end

function M.hasSupportBelow(pos)
    return M.hasKnownSupportBelow(pos) == true
end

function M.safeToStand(pos, knownTerrain)
    return M.hasKnownSupportBelow(pos, knownTerrain) == true
end

function M.safeOuterRing(area, y, knownTerrain)
    local ring = {}
    for x = area.minX, area.maxX do
        ring[#ring + 1] = vec3.new(x, y, area.minZ)
        if area.maxZ ~= area.minZ then ring[#ring + 1] = vec3.new(x, y, area.maxZ) end
    end
    for z = area.minZ + 1, area.maxZ - 1 do
        ring[#ring + 1] = vec3.new(area.minX, y, z)
        if area.maxX ~= area.minX then ring[#ring + 1] = vec3.new(area.maxX, y, z) end
    end
    local safe = {}
    for _, p in ipairs(ring) do
        local below = vec3.new(p.x, p.y - 1, p.z)
        local key = vec3.key(below)
        if knownTerrain and knownTerrain.support and knownTerrain.support[key] == true then
            safe[#safe + 1] = p
        end
    end
    return safe
end

function M.filterNoFallPositions(positions, knownTerrain)
    local safe = {}
    for _, p in ipairs(positions or {}) do
        if M.safeToStand(p, knownTerrain) then safe[#safe + 1] = p end
    end
    return safe
end

return M
