-- equipment.lua
-- Erkennung der ausgeruesteten Turtle-Upgrades, nicht der Inventarslots.

local M = {}

local function normalizeUpgrade(value)
    if type(value) == "table" then return value end
    if type(value) == "string" then return { name = value } end
    return nil
end

local function warning(text)
    return { text }
end

function M.getLeft()
    if turtle and type(turtle.getEquippedLeft) == "function" then
        local ok, result = pcall(turtle.getEquippedLeft)
        if ok then return normalizeUpgrade(result) end
        return nil, tostring(result)
    end
    return nil, "turtle.getEquippedLeft nicht verfuegbar"
end

function M.getRight()
    if turtle and type(turtle.getEquippedRight) == "function" then
        local ok, result = pcall(turtle.getEquippedRight)
        if ok then return normalizeUpgrade(result) end
        return nil, tostring(result)
    end
    return nil, "turtle.getEquippedRight nicht verfuegbar"
end

function M.getEquipped()
    local left, leftErr = M.getLeft()
    local right, rightErr = M.getRight()
    local warnings = {}
    if leftErr then warnings[#warnings + 1] = leftErr end
    if rightErr and rightErr ~= leftErr then warnings[#warnings + 1] = rightErr end
    return { left = left, right = right, warnings = warnings }
end

local function isModem(upgrade)
    local name = upgrade and tostring(upgrade.name or upgrade.adjective or ""):lower() or ""
    return name:find("modem", 1, true) ~= nil
end

function M.findModemSide()
    local eq = M.getEquipped()
    if isModem(eq.left) then return "left", eq.left end
    if isModem(eq.right) then return "right", eq.right end
    return nil, nil, eq.warnings
end

function M.findToolSide()
    local eq = M.getEquipped()
    if eq.left and not isModem(eq.left) then return "left", eq.left end
    if eq.right and not isModem(eq.right) then return "right", eq.right end
    return nil, nil, eq.warnings
end

function M.professionFromUpgrade(upgradeName)
    local name = tostring(upgradeName or ""):lower()
    if name:find("shovel", 1, true) then return "graben" end
    if name:find("pickaxe", 1, true) then return "bergbau" end
    if name:find("craft", 1, true) or name:find("crafting", 1, true) or name:find("workbench", 1, true) or name:find("crafty", 1, true) then return "handwerk" end
    if name:find("axe", 1, true) and not name:find("pickaxe", 1, true) then return "holzfaeller" end
    return "unbekannt"
end

function M.detectProfession()
    local side, tool, warnings = M.findToolSide()
    if not tool then
        return {
            profession = "unbekannt",
            toolSide = side,
            tool = nil,
            warnings = warnings and #warnings > 0 and warnings or warning("Kein Werkzeug-/Funktions-Upgrade erkannt"),
        }
    end
    return {
        profession = M.professionFromUpgrade(tool.name or tool.adjective),
        toolSide = side,
        tool = tool,
        warnings = warnings or {},
    }
end

return M
