-- worker_holzfaeller.lua
-- Worker fuer Holz. Arbeitet mit Bereichen oder Einzelbaeumen.

local core = require("worker_core")
local fleet = require("fleet_common")

local role = {}
role.role = "holzfaeller"

local function isWood(name)
    name = tostring(name or "")
    return name:find("_log") or name:find("_wood") or name:find("_stem") or name:find("hyphae") or name:find("leaves")
end

function role.needs(cfg, state)
    local fuel = turtle.getFuelLevel()
    local needs = { recipes = {}, items = {}, warnings = {} }
    if fuel ~= "unlimited" and fuel < (cfg.minFuel or 500) then
        needs.items["minecraft:coal"] = math.ceil(((cfg.minFuel or 500) - fuel) / 80)
    end
    needs.recipes[#needs.recipes + 1] = cfg.preferredAxe or "minecraft:diamond_axe"
    return needs
end

local function digWoodAround()
    local dug = false
    local ok, data = turtle.inspect()
    if ok and isWood(data.name) then turtle.dig(); dug = true end
    local okU, dataU = turtle.inspectUp()
    if okU and isWood(dataU.name) then turtle.digUp(); dug = true end
    local okD, dataD = turtle.inspectDown()
    if okD and isWood(dataD.name) then turtle.digDown(); dug = true end
    return dug
end

local function chopColumn(ctx, maxUp)
    maxUp = maxUp or 32
    local climbed = 0

    while climbed < maxUp do
        digWoodAround()
        local okU, dataU = turtle.inspectUp()
        if okU and isWood(dataU.name) then
            turtle.digUp()
            ctx.nav.upDig()
            climbed = climbed + 1
        else
            break
        end
    end

    while climbed > 0 do
        ctx.nav.downDig()
        climbed = climbed - 1
    end
end

function role.run(ctx, job)
    if job.chest then ctx.nav.setChest(job.chest); ctx.state.chest = job.chest end
    ctx.progress("Kalibriere Holzfaeller-Turtle")
    ctx.nav.calibrate(job.start, job.facing)

    if job.kind == "baum" then
        assert(job.pos, "job.pos fehlt")
        ctx.nav.goTo(job.pos)
        chopColumn(ctx, job.maxUp or 32)
        ctx.requestService("inventory_unload", { reason = "job_done" })
        return
    end

    assert(job.p1 and job.p2, "job.p1/job.p2 fehlen fuer Holz-Bereich")
    local area = fleet.normalizeArea(job.p1, job.p2)
    ctx.nav.goTo({ x = area.minX, y = area.minY, z = area.minZ })

    local dir = 1
    for z = area.minZ, area.maxZ do
        while (dir == 1 and ctx.nav.getPos().x < area.maxX) or (dir == -1 and ctx.nav.getPos().x > area.minX) do
            local fuel = turtle.getFuelLevel()
            if fuel ~= "unlimited" and fuel < (ctx.cfg.serviceFuelThreshold or 100) then
                ctx.requestService("fuel", { fuel = fuel })
            end
            digWoodAround()
            if dir == 1 then ctx.nav.turnTo("east") else ctx.nav.turnTo("west") end
            digWoodAround()
            ctx.nav.forwardDig()
            chopColumn(ctx, area.maxY - area.minY + 8)
            local _, free = fleet.slotSummary()
            if free <= 1 then ctx.requestService("inventory_full", { freeSlots = free }) end
        end
        chopColumn(ctx, area.maxY - area.minY + 8)
        if z < area.maxZ then ctx.nav.turnTo("south"); ctx.nav.forwardDig() end
        dir = dir * -1
    end

    ctx.requestService("inventory_unload", { reason = "job_done" })
end

core.run(role)
