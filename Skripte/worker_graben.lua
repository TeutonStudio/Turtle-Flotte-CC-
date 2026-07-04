-- worker_graben.lua
-- Worker fuer weiche Bloecke: Erde, Sand, Kies, Schnee, Lehm usw.

local core = require("worker_core")
local fleet = require("fleet_common")

local role = {}
role.role = "graben"

local SOFT_HINTS = {
    "dirt", "grass_block", "sand", "gravel", "clay", "mud", "snow", "soul_sand",
    "soul_soil", "farmland", "podzol", "mycelium", "path", "concrete_powder"
}

local function isSoft(name)
    name = tostring(name or "")
    for _, h in ipairs(SOFT_HINTS) do if name:find(h) then return true end end
    return false
end

function role.needs(cfg, state)
    local fuel = turtle.getFuelLevel()
    local needs = { recipes = {}, items = {}, warnings = {} }
    if fuel ~= "unlimited" and fuel < (cfg.minFuel or 500) then
        needs.items["minecraft:coal"] = math.ceil(((cfg.minFuel or 500) - fuel) / 80)
    end
    needs.recipes[#needs.recipes + 1] = cfg.preferredShovel or "minecraft:diamond_shovel"
    return needs
end

local function digIfSoftForward()
    local ok, data = turtle.inspect()
    if ok and isSoft(data.name) then return turtle.dig() end
    return false
end

local function processCurrentColumn(ctx, area)
    -- Soft-Worker entfernt nur passende Bloecke ueber/unter sich, nicht Stein. Sonst bohrt die Schaufel beleidigt durch Granit.
    local okUp, dataUp = turtle.inspectUp()
    if okUp and isSoft(dataUp.name) then turtle.digUp() end
    local okDown, dataDown = turtle.inspectDown()
    if okDown and isSoft(dataDown.name) then turtle.digDown() end
end

function role.run(ctx, job)
    assert(job.p1 and job.p2, "job.p1 und job.p2 fehlen")
    if job.chest then ctx.nav.setChest(job.chest); ctx.state.chest = job.chest end

    ctx.progress("Kalibriere Graben-Turtle")
    ctx.nav.calibrate(job.start, job.facing)

    local area = fleet.normalizeArea(job.p1, job.p2)
    ctx.nav.goTo({ x = area.minX, y = area.maxY, z = area.minZ })

    for y = area.maxY, area.minY, -1 do
        ctx.progress("Graben-Schicht Y=" .. y)
        ctx.nav.goTo({ x = area.minX, y = y, z = area.minZ })
        local dir = 1
        for z = area.minZ, area.maxZ do
            while (dir == 1 and ctx.nav.getPos().x < area.maxX) or (dir == -1 and ctx.nav.getPos().x > area.minX) do
                local fuel = turtle.getFuelLevel()
                if fuel ~= "unlimited" and fuel < (ctx.cfg.serviceFuelThreshold or 100) then
                    ctx.requestService("fuel", { fuel = fuel })
                end
                processCurrentColumn(ctx, area)
                if dir == 1 then ctx.nav.turnTo("east") else ctx.nav.turnTo("west") end
                digIfSoftForward()
                ctx.nav.forwardDig()
                local _, free = fleet.slotSummary()
                if free <= 1 then ctx.requestService("inventory_full", { freeSlots = free }) end
            end
            processCurrentColumn(ctx, area)
            if z < area.maxZ then ctx.nav.turnTo("south"); ctx.nav.forwardDig() end
            dir = dir * -1
        end
        if y > area.minY then ctx.nav.downDig() end
    end

    ctx.requestService("inventory_unload", { reason = "job_done" })
end

core.run(role)
