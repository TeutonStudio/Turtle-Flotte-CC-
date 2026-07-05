-- protocol.lua
-- Zentrale Rednet-Nachrichten fuer v5.

local fleet = require("fleet_common")
local M = {}

function M.requestId()
    return tostring(os.epoch("utc")) .. ":" .. tostring(math.random(1, 999999))
end

function M.prepare(cfg, msg)
    msg = fleet.safeCopy(msg or {})
    msg.fleet = cfg.group
    msg.version = fleet.VERSION
    msg.from = cfg.id or tostring(os.getComputerID())
    msg.sentAt = os.epoch("utc")
    return msg
end

function M.send(cfg, target, msg)
    rednet.send(target, M.prepare(cfg, msg), cfg.protocol)
end

function M.broadcast(cfg, msg)
    rednet.broadcast(M.prepare(cfg, msg), cfg.protocol)
end

function M.receive(cfg, timeout)
    while true do
        local sender, msg, proto = rednet.receive(cfg.protocol, timeout)
        if not sender then return nil, nil, nil end
        if proto == cfg.protocol and type(msg) == "table" and msg.fleet == cfg.group then
            return sender, msg, proto
        end
    end
end

function M.makeTask(kind, payload)
    return {
        id = M.requestId(),
        kind = kind,
        status = "pending",
        createdAt = os.epoch("utc"),
        payload = payload or {},
    }
end

return M
