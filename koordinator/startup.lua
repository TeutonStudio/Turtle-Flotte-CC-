-- Zweck: Top-Level-Loop des Koordinators fuer Queue, Worker und Rednet-Befehle.
-- Erwartet: common/*, koordinator/*, optional turtle/gps/chatBox.

local protocol = dofile("common/protocol.lua")
local vec3 = dofile("common/vec3.lua")
local util = dofile("common/util.lua")
local queue = dofile("koordinator/queue.lua")
local workers = dofile("koordinator/workers.lua")
local deploy = dofile("koordinator/deploy.lua")
local economy = dofile("koordinator/economy.lua")
local reports = dofile("koordinator/reports.lua")

local koordinator = {}
koordinator.DISPATCH_INTERVAL = 1
koordinator.LISTEN_TIMEOUT = 0.05

local phase = "IDLE"

local function shouldEnterMaintenance()
  if fs.exists("koordinator/maintenance") then return true end
  print("Koordinator startet. Taste M fuer Wartungsmodus.")
  local timer = os.startTimer(3)
  while true do
    local event, p1 = os.pullEvent()
    if event == "char" and (p1 == "m" or p1 == "M") then return true end
    if event == "timer" and p1 == timer then return false end
  end
end

local function printMaintenanceHelp()
  print("Wartungsmodus aktiv.")
  print("edit koordinator/config.lua")
  print("update/koordinator")
  print("rm startup.lua")
  print("koordinator/resume")
end

local function response(target, ok, data, err, request)
  local payload = { ok = ok, data = data, error = err }
  if request and request.msgId then payload.replyTo = request.msgId end
  local sent, sendErr = protocol.send(target, protocol.RESPONSE, payload)
  print("Antwort an " .. tostring(target) .. ": " .. tostring(sent) .. (sendErr and (" (" .. tostring(sendErr) .. ")") or ""))
  return sent, sendErr
end

local function currentStatus()
  local job = queue.current()
  return {
    koordinatorId = os.getComputerID(),
    phase = phase,
    currentJob = job and { id = job.id, typ = job.typ, status = job.status } or nil,
    queued = queue.pendingCount(),
    workers = workers.list(),
  }
end

local function handleCommand(sender, msg)
  print("Kommando empfangen: " .. tostring(msg.type) .. " von " .. tostring(sender))
  if msg.type == protocol.CMD_LIST then
    return response(sender, true, currentStatus(), nil, msg)
  elseif msg.type == protocol.CMD_STATUS then
    return response(sender, true, currentStatus(), nil, msg)
  elseif msg.type == protocol.CMD_BERICHT then
    local jobId = msg.payload and msg.payload.jobId
    local data, err
    if msg.payload and msg.payload.voll then data, err = reports.lesen(jobId) else data, err = reports.kurzfassung(jobId) end
    return response(sender, data ~= nil, data, err, msg)
  elseif msg.type == protocol.CMD_ABBAU then
    local p = msg.payload or {}
    if not vec3.isVec(p.lager) or not vec3.isVec(p.von) or not vec3.isVec(p.bis) then
      return response(sender, false, nil, "lager/von/bis muessen vec3 sein", msg)
    end
    local job, err = queue.createAbbau(p)
    if not job then return response(sender, false, nil, err, msg) end
    reports.erstellen(job)
    return response(sender, true, { jobId = job.id, subtasks = #(job.subtasks or {}) }, nil, msg)
  end
end

local function handleWorker(sender, msg)
  if msg.type == protocol.WORKER_REGISTER then
    local dock = deploy.naechsteDockPos() or (msg.payload and msg.payload.position)
    local entry = workers.register(msg.payload, dock)
    response(sender, true, { registered = true, dockPos = dock })
    return entry
  elseif msg.type == protocol.WORKER_STATUS then
    return workers.updateStatus(sender, msg.payload)
  elseif msg.type == protocol.WORKER_PROBLEM then
    return workers.problem(sender, msg.payload)
  elseif msg.type == protocol.TASK_DONE then
    local job = queue.current()
    local taskId = msg.payload and msg.payload.taskId
    local task = queue.findSubtask(taskId)
    if task then
      task.status = "done"
      task.abgeschlossenAm = util.now()
      workers.markIdle(sender)
      reports.aktualisieren(job.id, task.id, { status = "done", abgeschlossenAm = task.abgeschlossenAm })
    end
  elseif msg.type == protocol.TASK_FAILED then
    local job = queue.current()
    local taskId = msg.payload and msg.payload.taskId
    local task = queue.findSubtask(taskId)
    if task then
      task.status = "failed"
      task.fehler = msg.payload and msg.payload.error or "Unbekannter Fehler"
      task.abgeschlossenAm = util.now()
      workers.markIdle(sender)
      reports.aktualisieren(job.id, task.id, { status = "failed", fehler = task.fehler, abgeschlossenAm = task.abgeschlossenAm })
    end
  elseif msg.type == protocol.READY_AT_DOCK then
    workers.markReturning(sender)
  end
end

function koordinator.pollNetwork()
  local sender, msg = protocol.receive(koordinator.LISTEN_TIMEOUT)
  if not msg then return end
  if msg.type == protocol.CMD_LIST or msg.type == protocol.CMD_STATUS or msg.type == protocol.CMD_ABBAU or msg.type == protocol.CMD_BERICHT then
    handleCommand(sender, msg)
  else
    handleWorker(sender, msg)
  end
end

local function updateAssignedReports(job, assigned)
  for _, task in ipairs(assigned or {}) do
    reports.aktualisieren(job.id, task.id, { status = task.status, workerId = task.workerId, zugewiesenAm = task.zugewiesenAm })
  end
end

function koordinator.tick()
  local job = queue.current()
  if not job and queue.peek() then
    phase = "AUSPACKEN"
    job = queue.startNext()
    reports.aktualisieren(job.id, nil, { jobStatus = "running", gestartetAm = job.gestartetAm })
    local count = math.min(#(job.subtasks or {}), 8)
    if turtle then deploy.auspacken(count) end
    phase = "ARBEITEN"
  end
  job = queue.current()
  if job then
    for _, worker in pairs(workers.all()) do
      if worker.status == "problem" then economy.handleProblem(worker, job) end
    end
    local assigned = workers.dispatch(job)
    updateAssignedReports(job, assigned)
    local complete, hasFailure = queue.isCurrentComplete()
    if complete then
      local doneJob = queue.finishCurrent(hasFailure and "failed" or "done")
      reports.aktualisieren(doneJob.id, nil, { jobStatus = doneJob.status, abgeschlossenAm = doneJob.abgeschlossenAm })
      phase = "EINPACKEN"
      if turtle then deploy.einpacken(workers.list()); deploy.einlagernInventar() end
      phase = "IDLE"
    end
  end
end

function koordinator.main()
  if shouldEnterMaintenance() then
    printMaintenanceHelp()
    return true
  end
  math.randomseed(util.now())
  local ok, err = protocol.ensureOpen()
  if not ok then print("Rednet nicht bereit: " .. tostring(err)); return false end
  print("Flotte-Koordinator " .. tostring(os.getComputerID()) .. " bereit.")
  local lastTick = os.clock()
  while true do
    koordinator.pollNetwork()
    if os.clock() - lastTick >= koordinator.DISPATCH_INTERVAL then
      koordinator.tick()
      lastTick = os.clock()
    end
  end
end

koordinator.main()
return koordinator
