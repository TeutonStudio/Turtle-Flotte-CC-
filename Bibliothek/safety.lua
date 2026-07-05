-- safety.lua
-- Sicherheitslogik gegen Herunterfallen.

local vec3 = require("vec3")
local M = {}

local knownSupport = {}

function M.hasSupportBelow(pos)
    local key = vec3.key(vec3.new(pos.x, pos.y - 1, pos.z))
    if knownSupport[key] ~= nil then return knownSupport[key] end
    if turtle and turtle.inspectDown then
        local ok = turtle.inspectDown()
        return ok
    end
    return false
end

function M.safeToStand(pos)
    return M.hasSupportBelow(pos)
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
        elseif M.safeToStand(p) then
            safe[#safe + 1] = p
        end
    end
    return safe
end

function M.filterNoFallPositions(positions)
    local safe = {}
    for _, p in ipairs(positions or {}) do
        if M.safeToStand(p) then safe[#safe + 1] = p end
    end
    return safe
end

return M
