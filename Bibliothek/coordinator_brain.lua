-- coordinator_brain.lua
-- v5 Koordinator-Planer. Hält Queues, Terrain und Worker-Zustand.

local protocol = require("protocol")
local taskQueue = require("task_queue")
local terrain = require("terrain")
local reportLib = require("report")
local vec3 = require("vec3")

local M = {}

local HARD = { stone=true, ore=true, deepslate=true, granite=true, andesite=true, diorite=true, tuff=true, basalt=true }
local SOFT = { dirt=true, sand=true, gravel=true, snow=true, clay=true, mud=true }
local WOOD = { log=true, leaves=true, wood=true, stem=true }

local function now() return os.epoch("utc") end

local function containsAny(name, dict)
    name = tostring(name or ""):lower()
    for hint in pairs(dict) do if name:find(hint, 1, true) then return true end end
    return false
end

local function professionForBlock(block)
    local name = block and block.name or ""
    if containsAny(name, SOFT) then return "graben" end
    if containsAny(name, HARD) then return "bergbau" end
    if containsAny(name, WOOD) then return "holzfaeller" end
    return "bergbau"
end

local function queueSize(q, status)
    return #taskQueue.list(q, status)
end

local Brain = {}
Brain.__index = Brain

function M.new(cfg)
    local self = setmetatable({}, Brain)
    self.cfg = cfg
    self.workers = {}
    self.commandQueue = taskQueue.new()
    self.subtaskQueue = taskQueue.new()
    self.terrain = terrain.new()
    self.reports = {}
    self.currentCommand = nil
    self.currentReport = nil
    self.status = "bereit"
    self.standbyPlanned = false
    return self
end

function Brain:addPocketCommand(command)
    local task = taskQueue.push(self.commandQueue, {
        id = command.request_id or protocol.requestId(),
        kind = command.command,
        payload = command,
    })
    return task
end

function Brain:handleWorkerHello(sender, msg)
    local id = msg.worker or msg.id or msg.from
    if not id then return end
    self.workers[id] = self.workers[id] or { id = id }
    local w = self.workers[id]
    w.rednetId = sender
    w.profession = msg.profession or (msg.status and msg.status.profession) or w.profession or "unbekannt"
    w.status = msg.status or w.status
    w.lastSeen = now()
    w.currentTask = w.status and w.status.currentTask or w.currentTask
end

function Brain:handleWorkerStatus(sender, msg)
    self:handleWorkerHello(sender, msg)
end

function Brain:handleWorkerDone(msg)
    local worker = self.workers[msg.worker]
    if worker then worker.currentTask = nil; worker.status = msg.status or worker.status end
    taskQueue.markDone(self.subtaskQueue, msg.taskId, msg.result)
    local doneTask
    for _, task in ipairs(taskQueue.list(self.subtaskQueue)) do
        if task.id == msg.taskId then doneTask = task; break end
    end
    local target = doneTask and doneTask.payload and doneTask.payload.wohin
    if target and msg.result and msg.result.block then terrain.markBlock(self.terrain, target, msg.result.block) end
    if target and msg.result and msg.result.empty then terrain.markAir(self.terrain, target) end
    if self.currentReport then
        reportLib.event(self.currentReport, "worker_task_done", { worker = msg.worker, taskId = msg.taskId, result = msg.result })
        if msg.result and msg.result.block then reportLib.addItemsGained(self.currentReport, { [msg.result.block.name or "unknown"] = 1 }) end
    end
end

function Brain:handleWorkerFailed(msg)
    local worker = self.workers[msg.worker]
    if worker then worker.currentTask = nil; worker.status = msg.status or worker.status end
    taskQueue.markFailed(self.subtaskQueue, msg.taskId, msg.reason or msg.error)
    if self.currentReport then reportLib.addFailure(self.currentReport); reportLib.event(self.currentReport, "worker_task_failed", msg) end
end

function Brain:handleWorkerBlocked(msg)
    local worker = self.workers[msg.worker]
    if worker then worker.currentTask = nil; worker.status = msg.status or worker.status end
    taskQueue.markFailed(self.subtaskQueue, msg.taskId, msg.reason or "blocked")
    if msg.blockedPos then terrain.markBlocked(self.terrain, msg.blockedPos, msg.block) end
    if self.currentReport then reportLib.addFailure(self.currentReport); reportLib.event(self.currentReport, "worker_blocked", msg) end
    local profession = professionForBlock(msg.block)
    local task = protocol.makeTask("move_action", {
        wohin = msg.blockedPos,
        aktion = true,
        requiredProfession = profession,
        requireSupport = true,
        source = "blocked",
    })
    task.priority = 1
    taskQueue.push(self.subtaskQueue, task)
end

function Brain:handleWorkerNeedsFuel(msg)
    if self.currentReport then reportLib.event(self.currentReport, "worker_need_fuel", msg) end
    local task = self:planServiceFuel(msg.worker, msg.pos)
    task.priority = 0
    taskQueue.push(self.subtaskQueue, task)
end

function Brain:handleWorkerInventoryFull(msg)
    if self.currentReport then reportLib.event(self.currentReport, "worker_inventory_full", msg) end
    local lager = self.currentCommand and self.currentCommand.payload and self.currentCommand.payload.chest
    local task = self:planServiceUnload(msg.worker, msg.pos, lager)
    task.priority = 0
    taskQueue.push(self.subtaskQueue, task)
end

function Brain:chooseWorker(profession)
    local best = nil
    for _, worker in pairs(self.workers) do
        local busy = worker.currentTask ~= nil or (worker.status and worker.status.currentTask ~= nil)
        if worker.rednetId and not busy and (not profession or worker.profession == profession) then
            best = worker
            break
        end
    end
    return best
end

function Brain:assignWorkerTask(worker, task)
    if not worker or not worker.rednetId then return false end
    worker.currentTask = task
    task.worker = worker.id
    taskQueue.markRunning(self.subtaskQueue, task.id)
    protocol.send(self.cfg, worker.rednetId, { kind = "worker_task", worker = worker.id, task = task })
    if self.currentReport then reportLib.addWorkerTask(self.currentReport); reportLib.event(self.currentReport, "worker_task_sent", { worker = worker.id, task = task }) end
    return true
end

function Brain:planHighestPointSearch(area)
    for _, column in ipairs(terrain.splitAreaIntoColumns(area)) do
        for y = column.maxY, column.minY, -1 do
            local task = protocol.makeTask("move_action", {
                wohin = vec3.new(column.x, y, column.z),
                aktion = true,
                requiredProfession = "bergbau",
                requireSupport = true,
                phase = "highest_search",
            })
            taskQueue.push(self.subtaskQueue, task)
        end
    end
end

function Brain:planOuterToInnerLayer(area, y)
    for _, ring in ipairs(terrain.splitLayerOuterToInner(area, y)) do
        for _, pos in ipairs(ring) do
            local task = protocol.makeTask("move_action", {
                wohin = pos,
                aktion = true,
                requiredProfession = "bergbau",
                requireSupport = true,
                phase = "layer",
                y = y,
            })
            taskQueue.push(self.subtaskQueue, task)
        end
    end
end

function Brain:planLayerMining(area, highestY)
    for y = highestY, area.minY, -1 do
        self:planOuterToInnerLayer(area, y)
    end
end

function Brain:planServiceFuel(workerId, pos)
    return protocol.makeTask("service_fuel", { workerId = workerId, pos = pos })
end

function Brain:planServiceUnload(workerId, pos, lager)
    return protocol.makeTask("service_unload", { workerId = workerId, pos = pos, lager = lager })
end

function Brain:planStandby()
    if self.standbyPlanned then return end
    self.standbyPlanned = true
    self.status = "standby"
    for _, worker in pairs(self.workers) do
        if worker.rednetId and self.cfg.initChest then
            protocol.send(self.cfg, worker.rednetId, { kind = "worker_standby", target = self.cfg.initChest })
        end
    end
end

local function startAbbau(self, command)
    local payload = command.payload
    local area = vec3.normalizeBox(payload.p1, payload.p2)
    self.currentCommand = command
    self.currentReport = reportLib.start(command.id, "abbau", payload)
    self.reports[command.id] = self.currentReport
    reportLib.event(self.currentReport, "command_started", { area = area, lager = payload.chest })
    self:planHighestPointSearch(area)
    command.area = area
    command.highestSearchPlanned = true
    command.layerMiningPlanned = false
    self.status = "abbau"
end

function Brain:maybePromoteCommand()
    if self.currentCommand then return end
    local command = taskQueue.pop(self.commandQueue)
    if not command then return end
    taskQueue.markRunning(self.commandQueue, command.id)
    if command.kind == "abbau" then
        startAbbau(self, command)
    elseif command.kind == "standby" then
        self:planStandby()
        taskQueue.markDone(self.commandQueue, command.id, { standby = true })
    elseif command.kind == "stop" then
        for _, worker in pairs(self.workers) do
            if worker.rednetId then protocol.send(self.cfg, worker.rednetId, { kind = "worker_abort" }) end
        end
        taskQueue.markDone(self.commandQueue, command.id, { stopped = true })
    end
end

function Brain:highestFromDoneTasks()
    local highest
    for _, task in ipairs(taskQueue.list(self.subtaskQueue, "done")) do
        local pos = task.payload and task.payload.wohin
        if pos and task.result and task.result.dug and (not highest or pos.y > highest.y) then
            highest = vec3.copy(pos)
        end
    end
    return highest
end

function Brain:maybeFinishOrAdvance()
    if not self.currentCommand then return end
    if queueSize(self.subtaskQueue, "pending") > 0 or queueSize(self.subtaskQueue, "running") > 0 then return end
    if self.currentCommand.kind == "abbau" and not self.currentCommand.layerMiningPlanned then
        local highest = self:highestFromDoneTasks()
        if not highest then
            reportLib.finish(self.currentReport, "empty", { reason = "no_blocks_found" })
            reportLib.save(self.cfg.reportDir or "berichte", self.currentReport)
            taskQueue.markDone(self.commandQueue, self.currentCommand.id, { empty = true })
            self.currentCommand = nil
            self.currentReport = nil
            return
        end
        reportLib.event(self.currentReport, "highest_found", { highest = highest })
        self.currentCommand.layerMiningPlanned = true
        self:planLayerMining(self.currentCommand.area, highest.y)
        return
    end
    reportLib.finish(self.currentReport, "done", { command = self.currentCommand.id })
    reportLib.save(self.cfg.reportDir or "berichte", self.currentReport)
    taskQueue.markDone(self.commandQueue, self.currentCommand.id, { done = true })
    self.currentCommand = nil
    self.currentReport = nil
end

local function nextRunnableTask(self)
    local pending = taskQueue.list(self.subtaskQueue, "pending")
    table.sort(pending, function(a, b) return (a.priority or 5) < (b.priority or 5) end)
    return pending[1]
end

function Brain:tick()
    self:maybePromoteCommand()
    local task = nextRunnableTask(self)
    if task then
        if task.kind == "move_action" then
            local profession = task.payload and task.payload.requiredProfession
            local worker = self:chooseWorker(profession)
            if worker then self:assignWorkerTask(worker, task) end
        elseif task.kind == "service_fuel" or task.kind == "service_unload" then
            taskQueue.markDone(self.subtaskQueue, task.id, { planned = true })
            if self.currentReport then reportLib.event(self.currentReport, task.kind, task.payload) end
        end
    end
    self:maybeFinishOrAdvance()
    if not self.currentCommand and taskQueue.isEmpty(self.commandQueue) and taskQueue.isEmpty(self.subtaskQueue) then
        self:planStandby()
    else
        self.standbyPlanned = false
    end
end

function Brain:statusSnapshot()
    local workers = {}
    for _, w in pairs(self.workers) do workers[#workers + 1] = w end
    table.sort(workers, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return {
        id = self.cfg.id,
        group = self.cfg.group,
        status = self.status,
        commandQueue = taskQueue.list(self.commandQueue),
        subtaskQueue = taskQueue.list(self.subtaskQueue),
        currentCommand = self.currentCommand,
        currentReport = self.currentReport and self.currentReport.id or nil,
        workers = workers,
    }
end

return M
