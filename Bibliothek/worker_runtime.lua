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

local function inspectActionTarget(pos)
    local pose = nav2.getPose()
    if not pose.pos then return nil end
    if pose.pos.y + 1 == pos.y and pose.pos.x == pos.x and pose.pos.z == pos.z then return turtle.inspectUp, turtle.digUp end
    if pose.pos.y - 1 == pos.y and pose.pos.x == pos.x and pose.pos.z == pos.z then return turtle.inspectDown, turtle.digDown end
    return turtle.inspect, turtle.dig
end

function M.run()
    local cfg = loadConfig()
    openRednet()

    local eq = equipment.getEquipped()
    local prof = equipment.detectProfession()
    local state = {
        cfg = cfg,
        profession = prof.profession,
        equipment = eq,
        warnings = prof.warnings or {},
        queue = taskQueue.new(),
        currentTask = nil,
        coordinatorRednetId = nil,
        lastError = nil,
        running = true,
    }

    pcall(function() nav2.calibrate(cfg.start, cfg.facing) end)

    local function status()
        local pose = nav2.getPose()
        return {
            id = cfg.id,
            profession = state.profession,
            fuel = turtle.getFuelLevel(),
            freeSlots = inventory.freeSlots(),
            pos = pose.pos,
            facing = pose.facing,
            equipment = state.equipment,
            warnings = state.warnings,
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
        local ok, reason = ensureOperational(task)
        if not ok then failTask(task, reason); return end

        local result
        if payload.aktion then
            result = nav2.goAdjacentTo(target, { dig = false, requireSupport = payload.requireSupport == true })
            if not result.ok then blocked(task, result); return end
            local faced = nav2.face(target)
            if not faced then failTask(task, "target_not_adjacent", { target = target }); return end
            local inspectFn, digFn = inspectActionTarget(target)
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
            if not result.ok then blocked(task, result); return end
            taskQueue.markDone(state.queue, task.id, { pos = nav2.getPose().pos })
            sendToCoordinator({ kind = "worker_task_done", taskId = task.id, worker = cfg.id, result = { pos = nav2.getPose().pos }, status = status() })
        end
    end

    local function runTask(task)
        state.currentTask = task
        taskQueue.markRunning(state.queue, task.id)
        local ok, err = pcall(function()
            if task.kind == "move_action" then
                runMoveAction(task)
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
                elseif msg.kind == "worker_status" then
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

    parallel.waitForAny(listenLoop, taskLoop, heartbeatLoop)
end

return M
