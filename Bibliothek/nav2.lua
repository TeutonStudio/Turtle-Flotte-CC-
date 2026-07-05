-- nav2.lua
-- Navigation ohne implizites Graben. Graben passiert nur mit options.dig=true.

local vec3 = require("vec3")
local direction = require("direction")

local M = {}
local state = { pos = nil, facing = nil, knownSupport = {} }

local function locate(timeout)
    if not gps or type(gps.locate) ~= "function" then return nil end
    local x, y, z = gps.locate(timeout or 2)
    if not x then return nil end
    return vec3.new(math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5))
end

local function inspectForward()
    local ok, data = turtle.inspect()
    return ok and data or nil
end

local function forwardPos()
    local d = direction.toVector(state.facing)
    return vec3.add(state.pos, d)
end

local function supportKnown(pos)
    local below = vec3.new(pos.x, pos.y - 1, pos.z)
    return state.knownSupport[vec3.key(below)]
end

local function avoidContains(avoid, pos)
    if not avoid or not pos then return false end
    local key = vec3.key(pos)
    if avoid[key] then return true end
    for _, v in ipairs(avoid) do if vec3.eq(v, pos) then return true end end
    return false
end

function M.calibrate(startPos, startFacing)
    state.pos = vec3.copy(startPos) or locate(2) or state.pos
    state.facing = direction.fromName(startFacing) or state.facing
    if state.pos and state.facing ~= nil then return true end
    assert(state.pos, "Keine Position: GPS fehlt und kein startPos uebergeben")

    for _ = 1, 4 do
        if turtle.forward() then
            local after = locate(2)
            turtle.back()
            if after then
                local dx = after.x - state.pos.x
                local dz = after.z - state.pos.z
                state.facing = direction.fromDelta(dx, dz)
                if state.facing ~= nil then return true end
            end
        end
        turtle.turnRight()
    end
    return false, "facing_unknown"
end

function M.getPose()
    return { pos = vec3.copy(state.pos), facing = direction.toName(state.facing) }
end

function M.setPose(pos, facing)
    state.pos = vec3.copy(pos)
    state.facing = direction.fromName(facing)
end

function M.setKnownSupport(support)
    state.knownSupport = support or {}
end

function M.turnTo(target)
    local to = direction.fromName(target)
    assert(to ~= nil, "Ungueltige Richtung")
    assert(state.facing ~= nil, "Blickrichtung unbekannt")
    for _, turn in ipairs(direction.turnPlan(state.facing, to)) do
        if turn == "left" then turtle.turnLeft() else turtle.turnRight() end
    end
    state.facing = to
    return true
end

function M.inspectBlockedForward()
    return inspectForward()
end

function M.stepForward(options)
    options = options or {}
    assert(state.pos and state.facing ~= nil, "Navigation nicht kalibriert")
    local nextPos = forwardPos()
    if avoidContains(options.avoid, nextPos) then
        return { ok = false, reason = "blocked", pos = vec3.copy(state.pos), blockedPos = nextPos, block = { name = "avoid" } }
    end
    if options.requireSupport then
        local support = supportKnown(nextPos)
        if support == nil then
            return { ok = false, reason = "support_unknown", pos = vec3.copy(state.pos), blockedPos = nextPos }
        elseif support == false then
            return { ok = false, reason = "unsafe_no_support", pos = vec3.copy(state.pos), blockedPos = nextPos }
        end
    end
    local ok, reason = turtle.forward()
    if ok then
        state.pos = nextPos
        return { ok = true, pos = vec3.copy(state.pos) }
    end
    if reason ~= "Out of fuel" and options.dig then
        turtle.dig()
        sleep(0.1)
        ok, reason = turtle.forward()
        if ok then
            state.pos = nextPos
            return { ok = true, pos = vec3.copy(state.pos) }
        end
    end
    return {
        ok = false,
        reason = reason == "Out of fuel" and "fuel" or "blocked",
        pos = vec3.copy(state.pos),
        blockedPos = nextPos,
        block = options.reportBlock ~= false and inspectForward() or nil,
    }
end

local function moveY(targetY, options)
    options = options or {}
    while state.pos.y ~= targetY do
        local up = state.pos.y < targetY
        local nextPos = vec3.new(state.pos.x, state.pos.y + (up and 1 or -1), state.pos.z)
        if avoidContains(options.avoid, nextPos) then
            return { ok = false, reason = "blocked", pos = vec3.copy(state.pos), blockedPos = nextPos, block = { name = "avoid" } }
        end
        if not up and options.allowDown == false then
            return { ok = false, reason = "down_disallowed", pos = vec3.copy(state.pos), blockedPos = nextPos }
        end
        local ok, reason
        if up then ok, reason = turtle.up() else ok, reason = turtle.down() end
        if ok then
            state.pos = nextPos
        elseif options.dig then
            if up then turtle.digUp() else turtle.digDown() end
            sleep(0.1)
        else
            local block
            if options.reportBlock ~= false then
                local inspectOk, data
                if up then inspectOk, data = turtle.inspectUp() else inspectOk, data = turtle.inspectDown() end
                block = inspectOk and data or nil
            end
            return { ok = false, reason = reason == "Out of fuel" and "fuel" or "blocked", pos = vec3.copy(state.pos), blockedPos = nextPos, block = block }
        end
    end
    return { ok = true, pos = vec3.copy(state.pos) }
end

function M.goTo(target, options)
    options = options or {}
    assert(state.pos, "Navigation nicht kalibriert")
    local r
    r = moveY(target.y, options); if not r.ok then return r end
    while state.pos.x ~= target.x do
        M.turnTo(state.pos.x < target.x and "east" or "west")
        r = M.stepForward(options); if not r.ok then return r end
    end
    while state.pos.z ~= target.z do
        M.turnTo(state.pos.z < target.z and "south" or "north")
        r = M.stepForward(options); if not r.ok then return r end
    end
    return { ok = true, pos = vec3.copy(state.pos) }
end

function M.safeAdjacentPositions(target)
    return vec3.neighbors4(target)
end

function M.goAdjacentTo(target, options)
    local best = M.safeAdjacentPositions(target)
    table.sort(best, function(a, b) return vec3.manhattan(state.pos, a) < vec3.manhattan(state.pos, b) end)
    local last
    for _, p in ipairs(best) do
        last = M.goTo(p, options)
        if last.ok then M.face(target); return last end
    end
    return last or { ok = false, reason = "no_adjacent", pos = vec3.copy(state.pos), blockedPos = vec3.copy(target) }
end

function M.face(target)
    local dx = target.x - state.pos.x
    local dz = target.z - state.pos.z
    local dir = direction.fromDelta(dx, dz)
    if dir == nil then return false, "target_not_adjacent" end
    M.turnTo(dir)
    return true
end

return M
