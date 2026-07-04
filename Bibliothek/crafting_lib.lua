-- crafting_lib.lua
-- Hilfsfunktionen fuer Crafting Turtle. Erwartet freie Crafting-Slots oder raeumt sie in Slots 12-16.

local fleet = require("fleet_common")
local recipes = require("recipes")

local M = {}

local GRID_TO_SLOT = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
local BUFFER_SLOTS = { 12, 13, 14, 15, 16, 4, 8 }

local function asList(recipe, name)
    if name == nil then return nil end
    if recipe.aliases and recipe.aliases[name] then return recipe.aliases[name] end
    return { name }
end

local function countMatching(names)
    local wanted = {}
    for _, n in ipairs(names) do wanted[n] = true end
    local total = 0
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and wanted[d.name] then total = total + d.count end
    end
    return total
end

function M.missing(recipeName, times)
    times = times or 1
    local recipe = recipes[recipeName]
    if not recipe then return { [recipeName] = "Rezept unbekannt" } end

    local missing = {}
    for name, count in pairs(recipe.ingredients or {}) do
        local names = asList(recipe, name)
        local have = countMatching(names)
        local need = count * times
        if have < need then missing[name] = need - have end
    end
    return missing
end

local function tableEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

local function clearSlot(slot)
    if turtle.getItemCount(slot) == 0 then return true end
    turtle.select(slot)
    for _, target in ipairs(BUFFER_SLOTS) do
        if target ~= slot then
            local before = turtle.getItemCount(slot)
            turtle.transferTo(target)
            if turtle.getItemCount(slot) == 0 then return true end
            if turtle.getItemCount(slot) < before then return clearSlot(slot) end
        end
    end
    return turtle.getItemCount(slot) == 0
end

local function clearGrid()
    for _, slot in ipairs(GRID_TO_SLOT) do
        if not clearSlot(slot) then
            return false, "Crafting-Raster konnte nicht geleert werden, Slot " .. slot .. " blockiert"
        end
    end
    return true
end

local function findIngredientSlot(recipe, ingredient)
    local names = asList(recipe, ingredient)
    return fleet.findItemSlot(names)
end

local function moveOneTo(recipe, ingredient, targetSlot)
    local source = findIngredientSlot(recipe, ingredient)
    if not source then return false, "Zutat fehlt: " .. tostring(ingredient) end
    turtle.select(source)
    if not turtle.transferTo(targetSlot, 1) then
        return false, "Konnte Zutat nicht in Slot " .. targetSlot .. " schieben"
    end
    return true
end

local function arrange(recipe)
    local ok, err = clearGrid()
    if not ok then return false, err end

    for gridIndex, ingredient in ipairs(recipe.grid) do
        if ingredient then
            local targetSlot = GRID_TO_SLOT[gridIndex]
            local moved, moveErr = moveOneTo(recipe, ingredient, targetSlot)
            if not moved then return false, moveErr end
        end
    end
    turtle.select(1)
    return true
end

function M.craft(recipeName, times)
    times = times or 1
    local recipe = recipes[recipeName]
    if not recipe then return false, "Unbekanntes Rezept: " .. tostring(recipeName) end

    local missing = M.missing(recipeName, times)
    if not tableEmpty(missing) then return false, "Zutaten fehlen", missing end

    local totalCrafted = 0
    while totalCrafted < times do
        local ok, err = arrange(recipe)
        if not ok then return false, err end

        local craftOk, craftErr = turtle.craft(1)
        if not craftOk then return false, craftErr or "Crafting fehlgeschlagen" end
        totalCrafted = totalCrafted + (recipe.count or 1)
    end

    return true, "Crafting fertig"
end

function M.knownRecipes()
    local names = {}
    for name in pairs(recipes) do names[#names + 1] = name end
    table.sort(names)
    return names
end

return M
