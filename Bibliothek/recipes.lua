-- recipes.lua
-- Kleine Rezeptdatenbank fuer die Handwerks-Turtle.
-- Erweitern ist absichtlich simpel: ingredients fuer Status, grid fuer turtle.craft().

local recipes = {}

local PLANKS = {
    "minecraft:oak_planks", "minecraft:spruce_planks", "minecraft:birch_planks",
    "minecraft:jungle_planks", "minecraft:acacia_planks", "minecraft:dark_oak_planks",
    "minecraft:mangrove_planks", "minecraft:cherry_planks", "minecraft:bamboo_planks",
    "minecraft:crimson_planks", "minecraft:warped_planks"
}

recipes["minecraft:stick"] = {
    output = "minecraft:stick",
    count = 4,
    ingredients = { ["#planks"] = 2 },
    aliases = { ["#planks"] = PLANKS },
    grid = {
        nil, "#planks", nil,
        nil, "#planks", nil,
        nil, nil, nil,
    }
}

local function toolRecipe(material, tool, pattern)
    local item = "minecraft:" .. material .. "_" .. tool
    recipes[item] = {
        output = item,
        count = 1,
        ingredients = {
            ["minecraft:" .. material] = pattern.materialCount,
            ["minecraft:stick"] = pattern.stickCount,
        },
        grid = pattern.grid(material),
    }
end

local pickaxePattern = {
    materialCount = 3,
    stickCount = 2,
    grid = function(material)
        local m = "minecraft:" .. material
        return {
            m, m, m,
            nil, "minecraft:stick", nil,
            nil, "minecraft:stick", nil,
        }
    end
}

local shovelPattern = {
    materialCount = 1,
    stickCount = 2,
    grid = function(material)
        local m = "minecraft:" .. material
        return {
            nil, m, nil,
            nil, "minecraft:stick", nil,
            nil, "minecraft:stick", nil,
        }
    end
}

local axePattern = {
    materialCount = 3,
    stickCount = 2,
    grid = function(material)
        local m = "minecraft:" .. material
        return {
            m, m, nil,
            m, "minecraft:stick", nil,
            nil, "minecraft:stick", nil,
        }
    end
}

for _, material in ipairs({ "wooden", "stone", "iron", "golden", "diamond" }) do
    local ingredient = material
    if material == "wooden" then ingredient = "planks" end
    if material == "stone" then ingredient = "cobblestone" end

    local function remapGrid(pattern)
        local base = pattern.grid(material)
        for i, v in ipairs(base) do
            if v == "minecraft:wooden" then base[i] = "#planks" end
            if v == "minecraft:stone" then base[i] = "minecraft:cobblestone" end
        end
        return base
    end

    local matName = material
    local matItem = "minecraft:" .. material
    if material == "wooden" then matItem = "#planks" end
    if material == "stone" then matItem = "minecraft:cobblestone" end

    for tool, pattern in pairs({ pickaxe = pickaxePattern, shovel = shovelPattern, axe = axePattern }) do
        local item = "minecraft:" .. material .. "_" .. tool
        recipes[item] = {
            output = item,
            count = 1,
            ingredients = {
                [matItem] = pattern.materialCount,
                ["minecraft:stick"] = pattern.stickCount,
            },
            aliases = matItem == "#planks" and { ["#planks"] = PLANKS } or nil,
            grid = remapGrid(pattern),
        }
    end
end

return recipes
