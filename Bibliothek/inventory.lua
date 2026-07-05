-- inventory.lua
-- Inventar- und Fuel-Helfer fuer Turtle-Runtimes.

local M = {}

local function turnForSide(side)
    if side == "front" or side == nil then return function() end end
    if side == "back" then turtle.turnRight(); turtle.turnRight(); return function() turtle.turnRight(); turtle.turnRight() end end
    if side == "left" then turtle.turnLeft(); return function() turtle.turnRight() end end
    if side == "right" then turtle.turnRight(); return function() turtle.turnLeft() end end
    return function() end
end

function M.item(slot)
    return turtle.getItemDetail(slot)
end

function M.isFuel(slot)
    if not slot or turtle.getItemCount(slot) <= 0 then return false end
    local old = turtle.getSelectedSlot()
    turtle.select(slot)
    local ok = turtle.refuel(0)
    turtle.select(old)
    return ok
end

function M.countFuelItems()
    local count = 0
    for i = 1, 16 do
        if M.isFuel(i) then count = count + turtle.getItemCount(i) end
    end
    return count
end

function M.refuelUntil(minFuel)
    local level = turtle.getFuelLevel()
    if level == "unlimited" or level >= minFuel then return true end
    for i = 1, 16 do
        if M.isFuel(i) then
            turtle.select(i)
            while turtle.getItemCount(i) > 0 and turtle.getFuelLevel() < minFuel do
                if not turtle.refuel(1) then break end
            end
            if turtle.getFuelLevel() >= minFuel then turtle.select(1); return true end
        end
    end
    turtle.select(1)
    return false, "fuel_below_" .. tostring(minFuel)
end

function M.firstEmptySlot()
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then return i end end
    return nil
end

function M.usedSlots()
    local used = 0
    for i = 1, 16 do if turtle.getItemCount(i) > 0 then used = used + 1 end end
    return used
end

function M.freeSlots()
    return 16 - M.usedSlots()
end

function M.isFull()
    return M.freeSlots() == 0
end

function M.itemCounts()
    local counts = {}
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail then counts[detail.name] = (counts[detail.name] or 0) + detail.count end
    end
    return counts
end

function M.dropAllExcept(reservedSlots, side)
    reservedSlots = reservedSlots or {}
    local restore = turnForSide(side or "front")
    local moved = 0
    for i = 1, 16 do
        if not reservedSlots[i] and turtle.getItemCount(i) > 0 then
            turtle.select(i)
            local count = turtle.getItemCount(i)
            local ok
            if side == "top" then ok = turtle.dropUp()
            elseif side == "bottom" then ok = turtle.dropDown()
            else ok = turtle.drop() end
            if ok then moved = moved + count end
        end
    end
    restore()
    turtle.select(1)
    return moved
end

function M.suckAllPossible(side, maxIterations)
    local restore = turnForSide(side or "front")
    local pulled = 0
    for _ = 1, maxIterations or 16 do
        local before = M.usedSlots()
        local ok
        if side == "top" then ok = turtle.suckUp()
        elseif side == "bottom" then ok = turtle.suckDown()
        else ok = turtle.suck() end
        local after = M.usedSlots()
        if not ok and after == before then break end
        pulled = pulled + math.max(0, after - before)
        if M.isFull() then break end
    end
    restore()
    turtle.select(1)
    return pulled
end

return M
