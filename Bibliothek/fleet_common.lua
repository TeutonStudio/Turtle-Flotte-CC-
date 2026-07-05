-- fleet_common.lua
-- Gemeinsame Hilfsfunktionen fuer Teuton-Fleet-Turtles.

local M = {}

M.VERSION = "4.1.0"

local function safeCopyValue(value, stack)
    local valueType = type(value)
    if valueType ~= "table" then
        if valueType == "string" or valueType == "number" or valueType == "boolean" or value == nil then
            return value
        end
        return tostring(value)
    end

    if stack[value] then return "<cycle>" end

    stack[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            copy[key] = safeCopyValue(child, stack)
        end
    end
    stack[value] = nil
    return copy
end

function M.safeCopy(value)
    return safeCopyValue(value, {})
end

function M.safeMessage(value)
    return M.safeCopy(value)
end

function M.loadConfig(requiredRole)
    local ok, cfg = pcall(require, "fleet_config")
    if not ok then
        error("fleet_config.lua fehlt oder ist fehlerhaft: " .. tostring(cfg), 2)
    end

    cfg.protocolPrefix = cfg.protocolPrefix or "teuton_fleet_v2"
    assert(cfg.group and cfg.group ~= "", "fleet_config.group fehlt")
    assert(cfg.id and cfg.id ~= "", "fleet_config.id fehlt")

    if requiredRole and cfg.role ~= requiredRole then
        error("Diese Datei erwartet role='" .. requiredRole .. "', Config hat aber role='" .. tostring(cfg.role) .. "'")
    end

    cfg.protocol = cfg.protocolPrefix .. ":" .. cfg.group
    cfg.statusInterval = cfg.statusInterval or 5
    cfg.replyTimeout = cfg.replyTimeout or 5

    return cfg
end

function M.openRednet()
    local opened = false
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            if not rednet.isOpen(name) then rednet.open(name) end
            opened = true
        end
    end
    assert(opened, "Kein Modem gefunden")
end

function M.requestId()
    return tostring(os.epoch("utc")) .. ":" .. tostring(math.random(1, 999999))
end

function M.prepareMessage(cfg, msg)
    msg = M.safeMessage(msg or {})
    if type(msg) ~= "table" then msg = { value = msg } end
    msg.fleet = cfg.group
    msg.version = M.VERSION
    msg.from = cfg.id
    msg.sentAt = os.epoch("utc")
    return msg
end

function M.send(cfg, targetRednetId, msg)
    rednet.send(targetRednetId, M.prepareMessage(cfg, msg), cfg.protocol)
end

function M.broadcast(cfg, msg)
    rednet.broadcast(M.prepareMessage(cfg, msg), cfg.protocol)
end

function M.validMessage(cfg, msg)
    return type(msg) == "table" and msg.fleet == cfg.group
end

function M.receive(cfg, timeout)
    while true do
        local sender, msg, protocol = rednet.receive(cfg.protocol, timeout)
        if not sender then return nil, nil, nil end
        if protocol == cfg.protocol and M.validMessage(cfg, msg) then
            return sender, msg, protocol
        end
    end
end

function M.receiveReply(cfg, requestId, timeout, expectedKind)
    local deadline = os.epoch("utc") + ((timeout or cfg.replyTimeout or 5) * 1000)

    while true do
        local remaining = (deadline - os.epoch("utc")) / 1000
        if remaining <= 0 then return nil, "timeout" end

        local sender, msg = M.receive(cfg, remaining)
        if not sender then return nil, "timeout" end

        if msg.request_id == requestId and (not expectedKind or msg.kind == expectedKind) then
            return msg, nil, sender
        end
    end
end

function M.vec(x, y, z)
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

function M.copyVec(v)
    if not v then return nil end
    return { x = v.x, y = v.y, z = v.z }
end

function M.parseVec(text)
    if type(text) == "table" then return M.copyVec(text) end
    if type(text) ~= "string" then return nil end

    local x, y, z = text:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
    if not x then return nil end

    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

function M.vecString(v)
    if not v then return "?" end
    return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
end

function M.normalizeArea(p1, p2)
    return {
        minX = math.min(p1.x, p2.x), maxX = math.max(p1.x, p2.x),
        minY = math.min(p1.y, p2.y), maxY = math.max(p1.y, p2.y),
        minZ = math.min(p1.z, p2.z), maxZ = math.max(p1.z, p2.z),
    }
end

function M.insideArea(p, a)
    return p.x >= a.minX and p.x <= a.maxX
       and p.y >= a.minY and p.y <= a.maxY
       and p.z >= a.minZ and p.z <= a.maxZ
end

function M.slotSummary()
    local used, free = 0, 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then used = used + 1 else free = free + 1 end
    end
    return used, free
end

function M.itemCounts()
    local counts = {}
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail then
            counts[detail.name] = (counts[detail.name] or 0) + detail.count
        end
    end
    return counts
end

function M.findItemSlot(nameOrList)
    local wanted = {}
    if type(nameOrList) == "table" then
        for _, n in ipairs(nameOrList) do wanted[n] = true end
    else
        wanted[nameOrList] = true
    end

    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and wanted[d.name] then return i, d end
    end
    return nil, nil
end

function M.selectNonEmptySlot()
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            return i
        end
    end
    return nil
end

function M.ensureFuel(minimum)
    minimum = minimum or 1
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return true end
    if fuel >= minimum then return true end

    for i = 16, 1, -1 do
        turtle.select(i)
        if turtle.refuel(0) then
            turtle.refuel(1)
            if turtle.getFuelLevel() >= minimum then
                turtle.select(1)
                return true
            end
        end
    end

    turtle.select(1)
    return false, "Zu wenig Treibstoff"
end

function M.printTableLine(key, value)
    print(tostring(key) .. ": " .. tostring(value))
end

return M
