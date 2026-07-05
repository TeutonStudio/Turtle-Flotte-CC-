-- koordinator.lua
-- Duennes v5-Hauptprogramm. Planung lebt in coordinator_brain.lua.

local fleet = require("fleet_common")
local protocol = require("protocol")
local brainLib = require("coordinator_brain")
local nav2 = require("nav2")
local inventory = require("inventory")

local cfg = fleet.loadConfig("coordinator")
cfg.protocol = cfg.protocol or ((cfg.protocolPrefix or "teuton_fleet_v2") .. ":" .. cfg.group)
cfg.statusInterval = cfg.statusInterval or 5
cfg.reportDir = cfg.reportDir or "berichte"

fleet.openRednet()
rednet.host(cfg.protocol, cfg.id)

local brain = brainLib.new(cfg)

pcall(function() nav2.calibrate(cfg.start, cfg.facing) end)

local function reply(to, requestId, kind, extra)
    extra = extra or {}
    extra.kind = kind
    extra.request_id = requestId
    protocol.send(cfg, to, extra)
end

local function handlePocket(sender, msg)
    if msg.target and msg.target ~= cfg.id then return end
    if msg.command == "discover" then
        reply(sender, msg.request_id, "coordinator_status", { status = brain:statusSnapshot() })
    elseif msg.command == "status" then
        reply(sender, msg.request_id, "coordinator_status", { status = brain:statusSnapshot() })
    elseif msg.command == "abbau" then
        brain:addPocketCommand({
            request_id = msg.request_id,
            command = "abbau",
            chest = msg.chest,
            p1 = msg.p1,
            p2 = msg.p2,
            from = msg.from,
        })
        reply(sender, msg.request_id, "coordinator_report", { message = "Abbau-Befehl eingereiht", status = brain:statusSnapshot() })
    elseif msg.command == "stop" then
        brain:addPocketCommand({ request_id = msg.request_id, command = "stop" })
        reply(sender, msg.request_id, "coordinator_report", { message = "Stop eingereiht", status = brain:statusSnapshot() })
    elseif msg.command == "standby" then
        brain:addPocketCommand({ request_id = msg.request_id, command = "standby" })
        reply(sender, msg.request_id, "coordinator_report", { message = "Standby eingereiht", status = brain:statusSnapshot() })
    else
        reply(sender, msg.request_id, "coordinator_report", { error = "Unbekannter Befehl: " .. tostring(msg.command), status = brain:statusSnapshot() })
    end
end

local function dropFuelForward(wanted)
    wanted = wanted or 8
    local dropped = 0
    for slot = 1, 16 do
        if dropped >= wanted then break end
        if inventory.isFuel(slot) then
            turtle.select(slot)
            local amount = math.min(wanted - dropped, turtle.getItemCount(slot))
            if turtle.drop(amount) then dropped = dropped + amount end
        end
    end
    turtle.select(1)
    return dropped
end

local function currentLager()
    local snap = brain:statusSnapshot()
    return snap.currentCommand and snap.currentCommand.payload and snap.currentCommand.payload.chest or cfg.initChest
end

local function serviceFuel(msg)
    if not msg.pos then return false, "worker_pos_missing" end
    if cfg.initChest then
        local r = nav2.goAdjacentTo(cfg.initChest, { dig = false })
        if not r.ok then return false, r.reason end
        inventory.suckAllPossible("front", 16)
    end
    local r = nav2.goAdjacentTo(msg.pos, { dig = false })
    if not r.ok then return false, r.reason end
    local dropped = dropFuelForward(cfg.workerFuelItems or 16)
    return dropped > 0, dropped > 0 and nil or "no_fuel"
end

local function serviceUnload(msg)
    if not msg.pos then return false, "worker_pos_missing" end
    local lager = currentLager()
    if not lager then return false, "lager_missing" end
    local r = nav2.goAdjacentTo(msg.pos, { dig = false })
    if not r.ok then return false, r.reason end
    inventory.suckAllPossible("front", 16)
    r = nav2.goAdjacentTo(lager, { dig = false })
    if not r.ok then return false, r.reason end
    inventory.dropAllExcept({}, "front")
    return true
end

local function tryService(kind, msg)
    local ok, err
    if kind == "fuel" then ok, err = serviceFuel(msg)
    elseif kind == "unload" then ok, err = serviceUnload(msg)
    else return end
    if not ok then print("[Koordinator] Service " .. kind .. " fehlgeschlagen: " .. tostring(err)) end
end

local function listenLoop()
    while true do
        local sender, msg = protocol.receive(cfg, 0.5)
        if sender and type(msg) == "table" then
            if msg.kind == "worker_hello" then brain:handleWorkerHello(sender, msg)
            elseif msg.kind == "worker_status" then brain:handleWorkerStatus(sender, msg)
            elseif msg.kind == "worker_task_done" then brain:handleWorkerDone(msg)
            elseif msg.kind == "worker_task_failed" then brain:handleWorkerFailed(msg)
            elseif msg.kind == "worker_blocked" then brain:handleWorkerBlocked(msg)
            elseif msg.kind == "worker_need_fuel" then brain:handleWorkerNeedsFuel(msg); tryService("fuel", msg)
            elseif msg.kind == "worker_inventory_full" then brain:handleWorkerInventoryFull(msg); tryService("unload", msg)
            elseif msg.kind == "pocket_command" then handlePocket(sender, msg)
            end
        end
    end
end

local function heartbeatLoop()
    while true do
        protocol.broadcast(cfg, { kind = "coordinator_hello", coordinator = cfg.id, status = brain:statusSnapshot() })
        sleep(cfg.statusInterval)
    end
end

local function brainLoop()
    while true do
        local ok, err = pcall(function() brain:tick() end)
        if not ok then print("[Koordinator] Brain-Fehler: " .. tostring(err)) end
        sleep(0.2)
    end
end

parallel.waitForAny(listenLoop, heartbeatLoop, brainLoop)
