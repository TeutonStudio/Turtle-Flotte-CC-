-- worker_bergbau.lua
-- Worker fuer harten Abbau: Stein, Erz, Deepslate usw.

local core = require("worker_core")
local fleet = require("fleet_common")

local role = {}
role.role = "bergbau"

local HARD_HINTS = {
    "stone", "ore", "deepslate", "granite", "andesite", "diorite", "tuff",
    "basalt", "blackstone", "netherrack", "calcite", "dripstone"
}

local function looksHard(name)
    name = tostring(name or "")
    for _, h in ipairs(HARD_HINTS) do if name:find(h) then return true end end
    return true -- Pickaxe-Turtle darf im Zweifel versuchen. Minecraft liebt Ausnahmen.
end

function role.needs(cfg, state)
    local fuel = turtle.getFuelLevel()
    local needs = { recipes = {}, items = {}, warnings = {} }
    if fuel ~= "unlimited" and fuel < (cfg.minFuel or 500) then
        needs.items["minecraft:coal"] = math.ceil(((cfg.minFuel or 500) - fuel) / 80)
    end
    needs.recipes[#needs.recipes + 1] = cfg.preferredPickaxe or "minecraft:diamond_pickaxe"
    needs.warnings[#needs.warnings + 1] = "Werkzeughaltbarkeit kann CC-seitig nicht in jeder Version sauber ausgelesen werden. Bei Grabfehlern Ersatz-Pickaxe craften. Ja, herrlich elegant."
    return needs
end

local function mineLine(ctx, targetX)
    while ctx.nav.getPos().x ~= targetX do
        local fuel = turtle.getFuelLevel()
        if fuel ~= "unlimited" and fuel < (ctx.cfg.serviceFuelThreshold or 100) then
            ctx.requestService("fuel", { fuel = fuel })
        end
        if ctx.nav.getPos().x < targetX then ctx.nav.turnTo("east") else ctx.nav.turnTo("west") end
        ctx.nav.forwardDig()
        local _, free = fleet.slotSummary()
        if free <= 1 then ctx.requestService("inventory_full", { freeSlots = free }) end
    end
end

local function mineLayer(ctx, area, y)
    ctx.progress("Bergbau-Schicht Y=" .. y)
    ctx.nav.goTo({ x = area.minX, y = y, z = area.minZ })

    local dir = 1
    for z = area.minZ, area.maxZ do
        local targetX = dir == 1 and area.maxX or area.minX
        mineLine(ctx, targetX)

        if z < area.maxZ then
            ctx.nav.turnTo("south")
            ctx.nav.forwardDig()
        end
        dir = dir * -1
    end
end

function role.run(ctx, job)
    assert(job.p1 and job.p2, "job.p1 und job.p2 fehlen")
    if job.chest then ctx.nav.setChest(job.chest); ctx.state.chest = job.chest end

    ctx.progress("Kalibriere Bergbau-Turtle")
    ctx.nav.calibrate(job.start, job.facing)
    ctx.nav.setDigFilter(function(name) return looksHard(name) end)

    local area = fleet.normalizeArea(job.p1, job.p2)
    if job.chest and fleet.insideArea(job.chest, area) then error("Truhe liegt im Abbaubereich") end

    -- Von oben nach unten: erst ueber den Bereich, dann runter.
    ctx.nav.goTo({ x = area.minX, y = area.maxY + 1, z = area.minZ })
    ctx.nav.downDig()

    for y = area.maxY, area.minY, -1 do
        mineLayer(ctx, area, y)
        if y > area.minY then ctx.nav.downDig() end
    end

    ctx.requestService("inventory_unload", { reason = "job_done" })
end

core.run(role)
