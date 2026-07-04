-- worker_handwerk.lua
-- Handwerks-Turtle. Kann bekannte Rezepte craften, wenn Zutaten im eigenen Inventar liegen.

local core = require("worker_core")
local crafting = require("crafting_lib")
local fleet = require("fleet_common")

local role = {}
role.role = "handwerk"

function role.needs(cfg, state)
    return {
        recipesKnown = crafting.knownRecipes(),
        info = "Handwerks-Turtle craftet aus eigenem Inventar. Koordinator/Spieler muss Zutaten bereitstellen, sonst wird nur sauber gejammert."
    }
end

function role.run(ctx, job)
    if job.kind ~= "craft" then
        error("Handwerk versteht nur job.kind='craft'")
    end
    assert(job.recipe, "job.recipe fehlt")

    local times = tonumber(job.count) or 1
    ctx.progress("Pruefe Rezept " .. job.recipe)

    local missing = crafting.missing(job.recipe, times)
    for _ in pairs(missing) do
        error("Zutaten fehlen fuer " .. job.recipe .. ": " .. textutils.serialize(missing))
    end

    ctx.progress("Crafte " .. times .. "x " .. job.recipe)
    local ok, err, missingAgain = crafting.craft(job.recipe, times)
    if not ok then
        if missingAgain then error(err .. ": " .. textutils.serialize(missingAgain)) end
        error(err)
    end

    if job.chest then
        ctx.requestService("inventory_unload", { reason = "craft_done" })
    end
end

core.run(role)
