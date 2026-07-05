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

local navOk, navErr = pcall(function()
    local ok, err = nav2.calibrate(cfg.start, cfg.facing)
    if ok == false then error(err or "calibration_failed") end
end)
brain.coordinatorNav.ready = navOk
brain.coordinatorNav.error = navOk and nil or tostring(navErr)

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
        local tickOk, tickErr = pcall(function() brain:tick() end)
        if not tickOk then brain:warn("pocket_tick", "Brain-Tick nach Pocket-Befehl fehlgeschlagen: " .. tostring(tickErr)) end
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

local function shortVec(v)
    if not v then return "?" end
    return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
end

local function taskLine(task)
    if not task then return "-" end
    local payload = task.payload or {}
    local target = payload.wohin or payload.target or payload.pos
    local worker = task.worker and (" @" .. tostring(task.worker)) or ""
    return tostring(task.status) .. " " .. tostring(task.kind) .. worker .. " -> " .. shortVec(target)
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

local function returnNonFuelForward()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and not inventory.isFuel(slot) then
            turtle.select(slot)
            turtle.drop()
        end
    end
    turtle.select(1)
end

local function suckFuelFromFront(wanted)
    wanted = wanted or 16
    local before = inventory.countFuelItems()
    for _ = 1, 64 do
        if inventory.countFuelItems() - before >= wanted then break end
        if not turtle.suck(1) then break end
        returnNonFuelForward()
    end
    return inventory.countFuelItems() - before
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
        suckFuelFromFront(cfg.workerFuelItems or 16)
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

local function listenLoop()
    while true do
        local sender, msg = protocol.receive(cfg, 0.5)
        if sender and type(msg) == "table" then
            if msg.kind == "worker_hello" then brain:handleWorkerHello(sender, msg)
            elseif msg.kind == "worker_status" then brain:handleWorkerStatus(sender, msg)
            elseif msg.kind == "worker_task_done" then brain:handleWorkerDone(msg)
            elseif msg.kind == "worker_task_failed" then brain:handleWorkerFailed(msg)
            elseif msg.kind == "worker_task_accepted" then brain:handleWorkerAccepted(msg)
            elseif msg.kind == "worker_blocked" then brain:handleWorkerBlocked(msg)
            elseif msg.kind == "worker_need_fuel" then brain:handleWorkerNeedsFuel(msg)
            elseif msg.kind == "worker_inventory_full" then brain:handleWorkerInventoryFull(msg)
            elseif msg.kind == "pocket_command" then handlePocket(sender, msg)
            end
        end
    end
end

local function serviceLoop()
    while true do
        local task = brain:claimServiceTask()
        if task then
            local ok, err = pcall(function()
                if task.kind == "service_fuel" then
                    local done, why = serviceFuel({ worker = task.payload.workerId, pos = task.payload.pos })
                    if not done then error(why) end
                    return true
                elseif task.kind == "service_unload" then
                    local done, why = serviceUnload({ worker = task.payload.workerId, pos = task.payload.pos })
                    if not done then error(why) end
                    return true
                end
            end)
            brain:completeServiceTask(task.id, ok, ok and { ok = true } or tostring(err))
        else
            sleep(0.2)
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

local function displayLoop()
    while true do
        if term and term.clear then
            local _, h = term.getSize()
            local status = brain:statusSnapshot()
            term.clear()
            term.setCursorPos(1, 1)
            print("Koordinator " .. tostring(status.id) .. " | " .. tostring(status.status))
            print("Nav: " .. tostring(status.navReady) .. (status.navError and (" | " .. tostring(status.navError)) or ""))
            if status.currentCommand then
                print("Aktuell: " .. tostring(status.currentCommand.kind) .. " " .. tostring(status.currentCommand.id))
            else
                print("Aktuell: -")
            end
            print("Report: " .. tostring(status.currentReport or "-"))
            local line = 5
            if status.warnings and #status.warnings > 0 and line < h then
                print("Warnung: " .. tostring(status.warnings[#status.warnings].text))
                line = line + 1
            end
            print("Commands:")
            line = line + 1
            for _, task in ipairs(status.commandQueue or {}) do
                if line >= h then break end
                if task.status == "pending" or task.status == "running" then
                    print("  " .. tostring(task.status) .. " " .. tostring(task.kind) .. " " .. tostring(task.id))
                    line = line + 1
                end
            end
            if line < h then print("Subtasks:"); line = line + 1 end
            for _, task in ipairs(status.subtaskQueue or {}) do
                if line >= h then break end
                if task.status == "pending" or task.status == "running" or task.status == "held" then
                    print("  " .. taskLine(task))
                    line = line + 1
                end
            end
            if line < h then print("Worker:"); line = line + 1 end
            for _, worker in ipairs(status.workers or {}) do
                if line >= h then break end
                local s = worker.status or {}
                print("  " .. tostring(worker.id) .. " " .. tostring(worker.profession) .. " " .. shortVec(s.pos) .. " " .. tostring(worker.currentTask and "busy" or "frei"))
                line = line + 1
            end
        end
        sleep(1)
    end
end

parallel.waitForAny(listenLoop, heartbeatLoop, brainLoop, serviceLoop, displayLoop)
