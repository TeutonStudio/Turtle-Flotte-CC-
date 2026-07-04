-- nav.lua
-- Primitive Navigation fuer Turtles. GPS wird bevorzugt, Dead-Reckoning wird als Fallback genutzt.

local fleet = require("fleet_common")

local M = {}

local DIRS = {
    { name = "north", x = 0,  z = -1 },
    { name = "east",  x = 1,  z = 0  },
    { name = "south", x = 0,  z = 1  },
    { name = "west",  x = -1, z = 0  },
}

local state = {
    pos = nil,
    facing = nil,
    chest = nil,
    shouldAbort = function() return false end,
    onProgress = function(_) end,
}

local function dirIndexByName(name)
    for i, d in ipairs(DIRS) do if d.name == name then return i end end
    return nil
end

local function dirIndexFromDelta(dx, dz)
    for i, d in ipairs(DIRS) do
        if d.x == dx and d.z == dz then return i end
    end
    return nil
end

local function locate(timeout)
    local x, y, z = gps.locate(timeout or 3)
    if not x then return nil end
    return {
        x = math.floor(x + 0.5),
        y = math.floor(y + 0.5),
        z = math.floor(z + 0.5),
    }
end

local function updateGpsIfPossible()
    local p = locate(1)
    if p then state.pos = p end
end

function M.getPos() return fleet.copyVec(state.pos) end
function M.getFacingName() return state.facing and DIRS[state.facing].name or nil end
function M.setChest(v) state.chest = fleet.copyVec(v) end
function M.setAbortFunction(fn) state.shouldAbort = fn or function() return false end end
function M.setProgressFunction(fn) state.onProgress = fn or function(_) end end

local function checkAbort()
    if state.shouldAbort and state.shouldAbort() then error("Auftrag abgebrochen") end
end

local function isChestPos(p)
    return state.chest and p and p.x == state.chest.x and p.y == state.chest.y and p.z == state.chest.z
end

local function nextForwardPos()
    local d = DIRS[state.facing]
    return { x = state.pos.x + d.x, y = state.pos.y, z = state.pos.z + d.z }
end

local function turnRight()
    turtle.turnRight()
    state.facing = state.facing % 4 + 1
end

local function turnLeft()
    turtle.turnLeft()
    state.facing = state.facing - 1
    if state.facing < 1 then state.facing = 4 end
end

function M.turnTo(target)
    checkAbort()
    if type(target) == "string" then target = dirIndexByName(target) end
    assert(state.facing, "Blickrichtung unbekannt")
    assert(target, "Ungueltige Zielrichtung")

    while state.facing ~= target do
        local diff = (target - state.facing) % 4
        if diff == 1 then turnRight()
        elseif diff == 3 then turnLeft()
        else turnRight(); turnRight() end
    end
end

function M.calibrate(startPos, startFacing)
    if startPos then state.pos = fleet.copyVec(startPos) end
    if startFacing then
        state.facing = type(startFacing) == "number" and startFacing or dirIndexByName(startFacing)
    end

    local gpsPos = locate(3)
    if gpsPos then state.pos = gpsPos end

    if state.pos and state.facing then return true end
    assert(state.pos, "Keine Position: GPS fehlt und kein startPos uebergeben")

    -- Blickrichtung per kurzer Bewegung bestimmen.
    for _ = 1, 4 do
        checkAbort()
        if turtle.forward() then
            local after = locate(3)
            turtle.back()
            updateGpsIfPossible()

            if after then
                local dx = after.x - state.pos.x
                local dz = after.z - state.pos.z
                state.facing = dirIndexFromDelta(dx, dz)
                assert(state.facing, "Blickrichtung konnte nicht bestimmt werden")
                return true
            end
        end
        turtle.turnRight()
    end

    error("Blickrichtung konnte nicht kalibriert werden. Eine freie Nachbarposition wird gebraucht.")
end

local function tryDigForward()
    local ok, data = turtle.inspect()
    if ok and state.digFilter and not state.digFilter(data.name, data) then
        return false, "Block passt nicht zur Rolle: " .. tostring(data.name)
    end
    turtle.dig()
    turtle.attack()
    return true
end

function M.setDigFilter(fn)
    state.digFilter = fn
end

function M.forwardDig()
    checkAbort()
    assert(state.pos and state.facing, "Navigation nicht initialisiert")

    local np = nextForwardPos()
    if isChestPos(np) then error("Pfad wuerde in die Truhe laufen") end

    for _ = 1, 40 do
        checkAbort()
        fleet.ensureFuel(10)
        local ok, reason = turtle.forward()
        if ok then
            local d = DIRS[state.facing]
            state.pos.x = state.pos.x + d.x
            state.pos.z = state.pos.z + d.z
            updateGpsIfPossible()
            return true
        end

        if reason == "Out of fuel" then
            local fuelOk, fuelErr = fleet.ensureFuel(50)
            if not fuelOk then error(fuelErr) end
        else
            local dug, err = tryDigForward()
            if not dug then error(err) end
            sleep(0.15)
        end
    end

    error("Vorwaertsbewegung blockiert")
end

function M.upDig()
    checkAbort()
    local np = { x = state.pos.x, y = state.pos.y + 1, z = state.pos.z }
    if isChestPos(np) then error("Pfad wuerde in die Truhe laufen") end

    for _ = 1, 40 do
        checkAbort()
        fleet.ensureFuel(10)
        local ok, reason = turtle.up()
        if ok then
            state.pos.y = state.pos.y + 1
            updateGpsIfPossible()
            return true
        end
        if reason == "Out of fuel" then
            local fuelOk, fuelErr = fleet.ensureFuel(50)
            if not fuelOk then error(fuelErr) end
        else
            turtle.digUp(); turtle.attackUp(); sleep(0.15)
        end
    end
    error("Aufwaertsbewegung blockiert")
end

function M.downDig()
    checkAbort()
    local np = { x = state.pos.x, y = state.pos.y - 1, z = state.pos.z }
    if isChestPos(np) then error("Pfad wuerde in die Truhe laufen") end

    for _ = 1, 40 do
        checkAbort()
        fleet.ensureFuel(10)
        local ok, reason = turtle.down()
        if ok then
            state.pos.y = state.pos.y - 1
            updateGpsIfPossible()
            return true
        end
        if reason == "Out of fuel" then
            local fuelOk, fuelErr = fleet.ensureFuel(50)
            if not fuelOk then error(fuelErr) end
        else
            turtle.digDown(); turtle.attackDown(); sleep(0.15)
        end
    end
    error("Abwaertsbewegung blockiert")
end

function M.moveYTo(y)
    while state.pos.y < y do M.upDig() end
    while state.pos.y > y do M.downDig() end
end

function M.moveXTo(x)
    while state.pos.x ~= x do
        if state.pos.x < x then M.turnTo("east") else M.turnTo("west") end
        M.forwardDig()
    end
end

function M.moveZTo(z)
    while state.pos.z ~= z do
        if state.pos.z < z then M.turnTo("south") else M.turnTo("north") end
        M.forwardDig()
    end
end

function M.goTo(target)
    checkAbort()
    if not state.pos then error("Navigation nicht initialisiert") end

    -- Erst hoch, dann X/Z, dann runter. Simpel, aber weniger gern in Lava als andersrum.
    if state.pos.y < target.y then M.moveYTo(target.y) end
    M.moveXTo(target.x)
    M.moveZTo(target.z)
    if state.pos.y > target.y then M.moveYTo(target.y) end
end

local function faceChestFromAdjacent()
    if not state.chest then return false end
    local c = state.chest
    if state.pos.x == c.x and state.pos.y == c.y and state.pos.z == c.z - 1 then M.turnTo("south"); return true end
    if state.pos.x == c.x and state.pos.y == c.y and state.pos.z == c.z + 1 then M.turnTo("north"); return true end
    if state.pos.x == c.x - 1 and state.pos.y == c.y and state.pos.z == c.z then M.turnTo("east"); return true end
    if state.pos.x == c.x + 1 and state.pos.y == c.y and state.pos.z == c.z then M.turnTo("west"); return true end
    return false
end

function M.goAdjacentToChest()
    assert(state.chest, "Keine Truhe gesetzt")
    local c = state.chest
    local candidates = {
        { x = c.x,     y = c.y, z = c.z - 1 },
        { x = c.x,     y = c.y, z = c.z + 1 },
        { x = c.x - 1, y = c.y, z = c.z     },
        { x = c.x + 1, y = c.y, z = c.z     },
    }

    table.sort(candidates, function(a, b)
        local da = math.abs(state.pos.x - a.x) + math.abs(state.pos.y - a.y) + math.abs(state.pos.z - a.z)
        local db = math.abs(state.pos.x - b.x) + math.abs(state.pos.y - b.y) + math.abs(state.pos.z - b.z)
        return da < db
    end)

    local lastErr = "unbekannt"
    for _, p in ipairs(candidates) do
        local ok, err = pcall(function()
            M.goTo(p)
            assert(faceChestFromAdjacent(), "Nicht neben der Truhe")
        end)
        if ok then return true end
        lastErr = tostring(err)
    end
    error("Keine Position neben Truhe erreichbar: " .. lastErr)
end

function M.emptyToChest(reservedSlots)
    reservedSlots = reservedSlots or {}
    local oldPos = fleet.copyVec(state.pos)
    local oldFacing = state.facing

    M.goAdjacentToChest()
    for i = 1, 16 do
        if not reservedSlots[i] then
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.drop() end
        end
    end
    turtle.select(1)
    M.goTo(oldPos)
    M.turnTo(oldFacing)
end

return M
