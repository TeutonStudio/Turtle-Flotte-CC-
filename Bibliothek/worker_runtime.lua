-- worker_runtime.lua
-- Universeller v5-Arbeiter. Strategie kommt vom Koordinator.

local fleet = require("fleet_common")
local protocol = require("protocol")
local equipment = require("equipment")
local inventory = require("inventory")
local taskQueue = require("task_queue")
local nav2 = require("nav2")
local vec3 = require("vec3")

local M = {}

local function loadConfig()
    local cfg = fleet.loadConfig("worker")
    cfg.id = cfg.id or tostring(os.getComputerID())
    cfg.protocol = cfg.protocol or ((cfg.protocolPrefix or "teuton_fleet_v2") .. ":" .. cfg.group)
    cfg.statusInterval = cfg.statusInterval or 5
    return cfg
end

local function openRednet()
    local opened = false
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            if not rednet.isOpen(name) then rednet.open(name) end
            opened = true
        end
    end
    assert(opened, "Kein Modem gefunden")
end

local function inspectActionTarget(pos, toolSide)
    local pose = nav2.getPose()
    if not pose.pos then return nil end
    if pose.pos.y + 1 == pos.y and pose.pos.x == pos.x and pose.pos.z == pos.z then
        return turtle.inspectUp, function() return turtle.digUp(toolSide) end
    end
    if pose.pos.y - 1 == pos.y and pose.pos.x == pos.x and pose.pos.z == pos.z then
        return turtle.inspectDown, function() return turtle.digDown(toolSide) end
    end
    return turtle.inspect, function() return turtle.dig(toolSide) end
end

local function shortVec(v)
    if not v then return "?" end
    return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
end

local function taskLine(task)
    if not task then return "-" end
    local payload = task.payload or {}
    local target = payload.wohin or payload.target
    local action = payload.aktion == true and " action" or ""
    return tostring(task.status) .. " " .. tostring(task.kind) .. action .. " -> " .. shortVec(target)
end

function M.run()
    local cfg = loadConfig()
    openRednet()

    local eq = equipment.getEquipped()
    local prof = equipment.detectProfession(cfg)
    local state = {
        cfg = cfg,
        profession = prof.profession,
        professionSource = prof.source,
        toolSide = prof.toolSide,
        equipment = eq,
        warnings = prof.warnings or {},
        queue = taskQueue.new(),
        currentTask = nil,
        coordinatorRednetId = nil,
        lastError = nil,
        running = true,
        navReady = false,
        navError = nil,
    }

    local navOk, navErr = pcall(function()
        local ok, err = nav2.calibrate(cfg.start, cfg.facing)
        if ok == false then error(err or "calibration_failed") end
    end)
    state.navReady = navOk
    state.navError = navOk and nil or tostring(navErr)
    if not state.toolSide then state.warnings[#state.warnings + 1] = "Keine Werkzeugseite erkannt; dig-Fallback ohne sichere Upgrade-Seite" end

    local function status()
        local pose = nav2.getPose()
        return {
            id = cfg.id,
            profession = state.profession,
            professionSource = state.professionSource,
            toolSide = state.toolSide,
            fuel = turtle.getFuelLevel(),
            freeSlots = inventory.freeSlots(),
            pos = pose.pos,
            facing = pose.facing,
            equipment = state.equipment,
            warnings = state.warnings,
            navReady = state.navReady,
            navError = state.navError,
            currentTask = state.currentTask,
            queuedTasks = #taskQueue.list(state.queue, "pending"),
            lastError = state.lastError,
        }
    end

    local function sendToCoordinator(msg)
        if state.coordinatorRednetId then
            protocol.send(cfg, state.coordinatorRednetId, msg)
        else
            protocol.broadcast(cfg, msg)
        end
    end

    local function hello()
        protocol.broadcast(cfg, {
            kind = "worker_hello",
            id = cfg.id,
            worker = cfg.id,
            profession = state.profession,
            professionSource = state.professionSource,
            status = status(),
        })
    end

    local function failTask(task, reason, detail)
        state.lastError = reason
        taskQueue.markFailed(state.queue, task.id, reason)
        sendToCoordinator({
            kind = "worker_task_failed",
            taskId = task.id,
            worker = cfg.id,
            reason = reason,
            detail = detail,
            status = status(),
        })
    end

    local function blocked(task, result)
        protocol.send(cfg, state.coordinatorRednetId, {
            kind = "worker_blocked",
            taskId = task.id,
            worker = cfg.id,
            pos = result.pos,
            blockedPos = result.blockedPos,
            block = result.block,
            reason = result.reason,
            status = status(),
        })
    end

    local function ensureOperational(task)
        local fuel = turtle.getFuelLevel()
        if fuel ~= "unlimited" and fuel < 5 then
            sendToCoordinator({ kind = "worker_need_fuel", taskId = task and task.id, worker = cfg.id, pos = nav2.getPose().pos, fuel = fuel, status = status() })
            return false, "fuel_critical"
        end
        if inventory.isFull() then
            sendToCoordinator({ kind = "worker_inventory_full", taskId = task and task.id, worker = cfg.id, pos = nav2.getPose().pos, items = inventory.itemCounts(), status = status() })
            return false, "inventory_full"
        end
        return true
    end

    local function runMoveAction(task)
        local payload = task.payload or {}
        local target = payload.wohin
        assert(target, "move_action ohne wohin")
        if payload.requiredProfession and payload.requiredProfession ~= state.profession then
            failTask(task, "wrong_profession", { required = payload.requiredProfession, actual = state.profession })
            return
        end
        if not state.navReady then failTask(task, "nav_not_calibrated", { error = state.navError }); return end
        local ok, reason = ensureOperational(task)
        if not ok then
            taskQueue.markPending(state.queue, task.id, reason)
            return
        end

        local result
        if payload.aktion then
            result = nav2.goAdjacentTo(target, { dig = false, requireSupport = payload.requireSupport == true })
            if not result.ok then
                if result.reason == "fuel" then sendToCoordinator({ kind = "worker_need_fuel", taskId = task.id, worker = cfg.id, pos = nav2.getPose().pos, fuel = turtle.getFuelLevel(), status = status() }); taskQueue.markPending(state.queue, task.id, "fuel"); return end
                blocked(task, result); return
            end
            local faced = nav2.face(target)
            if not faced then failTask(task, "target_not_adjacent", { target = target }); return end
            local inspectFn, digFn = inspectActionTarget(target, state.toolSide)
            local hasBlock, block = inspectFn()
            if not hasBlock then
                taskQueue.markDone(state.queue, task.id, { empty = true, target = vec3.copy(target) })
                sendToCoordinator({ kind = "worker_task_done", taskId = task.id, worker = cfg.id, result = { empty = true, target = target }, status = status() })
                return
            end
            local dug, digErr = digFn()
            if not dug then
                sendToCoordinator({ kind = "worker_blocked", taskId = task.id, worker = cfg.id, pos = nav2.getPose().pos, blockedPos = target, block = block, reason = digErr or "dig_failed", status = status() })
                return
            end
            taskQueue.markDone(state.queue, task.id, { dug = true, target = vec3.copy(target), block = block })
            sendToCoordinator({ kind = "worker_task_done", taskId = task.id, worker = cfg.id, result = { dug = true, target = target, block = block }, status = status() })
        else
            result = nav2.goTo(target, { dig = false, requireSupport = payload.requireSupport == true })
            if not result.ok then
                if result.reason == "fuel" then sendToCoordinator({ kind = "worker_need_fuel", taskId = task.id, worker = cfg.id, pos = nav2.getPose().pos, fuel = turtle.getFuelLevel(), status = status() }); taskQueue.markPending(state.queue, task.id, "fuel"); return end
                blocked(task, result); return
            end
            taskQueue.markDone(state.queue, task.id, { pos = nav2.getPose().pos })
            sendToCoordinator({ kind = "worker_task_done", taskId = task.id, worker = cfg.id, result = { pos = nav2.getPose().pos }, status = status() })
        end
    end

    local function runInspectBlock(task)
        local payload = task.payload or {}
        local target = payload.target
        assert(target, "inspect_block ohne target")
        if not state.navReady then failTask(task, "nav_not_calibrated", { error = state.navError }); return end
        local ok, reason = ensureOperational(task)
        if not ok then taskQueue.markPending(state.queue, task.id, reason); return end
        local result = nav2.goAdjacentTo(target, { dig = false, requireSupport = payload.requireSupport == true })
        if not result.ok then
            if result.reason == "fuel" then sendToCoordinator({ kind = "worker_need_fuel", taskId = task.id, worker = cfg.id, pos = nav2.getPose().pos, fuel = turtle.getFuelLevel(), status = status() }); taskQueue.markPending(state.queue, task.id, "fuel"); return end
            blocked(task, result); return
        end
        local faced = nav2.face(target)
        if not faced then failTask(task, "target_not_adjacent", { target = target }); return end
        local inspectFn = inspectActionTarget(target, state.toolSide)
        local hasBlock, block = inspectFn()
        local scanResult
        if hasBlock then scanResult = { hasBlock = true, block = block, target = target }
        else scanResult = { hasBlock = false, empty = true, target = target } end
        taskQueue.markDone(state.queue, task.id, scanResult)
        sendToCoordinator({ kind = "worker_task_done", taskId = task.id, worker = cfg.id, result = scanResult, status = status() })
    end

    local function runTask(task)
        state.currentTask = task
        taskQueue.markRunning(state.queue, task.id)
        local ok, err = pcall(function()
            if task.kind == "move_action" then
                runMoveAction(task)
            elseif task.kind == "inspect_block" or task.kind == "scan_block" then
                runInspectBlock(task)
            else
                failTask(task, "unknown_task_kind", { kind = task.kind })
            end
        end)
        if not ok then failTask(task, tostring(err)) end
        state.currentTask = nil
    end

    local function listenLoop()
        rednet.host(cfg.protocol, cfg.id)
        hello()
        while state.running do
            local sender, msg = protocol.receive(cfg, 0.5)
            if sender and type(msg) == "table" then
                if msg.kind == "coordinator_hello" then
                    state.coordinatorRednetId = sender
                elseif msg.kind == "worker_status_request" then
                    sendToCoordinator({ kind = "worker_status", worker = cfg.id, status = status() })
                elseif msg.kind == "worker_task" and (not msg.worker or msg.worker == cfg.id) then
                    state.coordinatorRednetId = sender
                    local task = taskQueue.push(state.queue, {
                        id = msg.task and msg.task.id or msg.taskId,
                        kind = msg.task and msg.task.kind or msg.taskKind,
                        payload = msg.task and msg.task.payload or msg.payload,
                    })
                    protocol.send(cfg, sender, { kind = "worker_task_accepted", worker = cfg.id, taskId = task.id, status = status() })
                elseif msg.kind == "worker_abort" then
                    state.queue = taskQueue.new()
                    state.currentTask = nil
                    state.lastError = "aborted"
                elseif msg.kind == "worker_standby" then
                    local task = taskQueue.push(state.queue, { kind = "move_action", payload = { wohin = msg.target, aktion = false, requireSupport = false } })
                    protocol.send(cfg, sender, { kind = "worker_task_accepted", worker = cfg.id, taskId = task.id, status = status() })
                end
            end
        end
    end

    local function taskLoop()
        while state.running do
            local task = taskQueue.pop(state.queue)
            if task then runTask(task) else sleep(0.2) end
        end
    end

    local function heartbeatLoop()
        while state.running do hello(); sleep(cfg.statusInterval or 5) end
    end

    local function displayLoop()
        while state.running do
            if term and term.clear then
                local _, h = term.getSize()
                term.clear()
                term.setCursorPos(1, 1)
                print("Worker " .. tostring(cfg.id))
                print("Beruf: " .. tostring(state.profession) .. " (" .. tostring(state.professionSource) .. ") Tool=" .. tostring(state.toolSide))
                print("Nav: " .. tostring(state.navReady) .. (state.navError and (" | " .. tostring(state.navError)) or ""))
                print("Fuel: " .. tostring(turtle.getFuelLevel()) .. " Frei: " .. tostring(inventory.freeSlots()) .. "/16")
                local pose = nav2.getPose()
                print("Pos: " .. shortVec(pose.pos) .. " Facing: " .. tostring(pose.facing))
                print("Aktuell: " .. taskLine(state.currentTask))
                print("Naechste:")
                local line = 8
                for _, task in ipairs(taskQueue.list(state.queue)) do
                    if line >= h then break end
                    if task ~= state.currentTask and (task.status == "pending" or task.status == "running") then
                        print("  " .. taskLine(task))
                        line = line + 1
                    end
                end
                if #state.warnings > 0 and line < h then
                    print("Warnungen:")
                    line = line + 1
                    for _, warning in ipairs(state.warnings) do
                        if line >= h then break end
                        print("  " .. tostring(warning))
                        line = line + 1
                    end
                end
            end
            sleep(1)
        end
    end

    parallel.waitForAny(listenLoop, taskLoop, heartbeatLoop, displayLoop)
end

return M
