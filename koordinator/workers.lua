-- Zweck: Worker-Registry, Statuspflege und Subtask-Zuweisung.
-- Erwartet: common/vec3.lua, common/util.lua, common/protocol.lua.

local vec3 = dofile("common/vec3.lua")
local util = dofile("common/util.lua")
local protocol = dofile("common/protocol.lua")

local workers = {}
local registry = {}

function workers.register(payload, dockPos)
  if type(payload) ~= "table" or not payload.id then return nil, "Worker-ID fehlt" end
  local id = tonumber(payload.id)
  local entry = registry[id] or {}
  entry.id = id
  entry.beruf = payload.beruf or entry.beruf or "unbekannt"
  entry.status = "idle"
  entry.position = payload.position or entry.position
  entry.fuel = payload.fuel or entry.fuel or 0
  entry.dockPos = dockPos or payload.dockPos or payload.position or entry.dockPos
  entry.currentTask = nil
  registry[id] = entry
  return entry
end

function workers.updateStatus(id, payload)
  local entry = registry[tonumber(id)]
  if not entry then return nil, "Worker unbekannt" end
  payload = payload or {}
  entry.status = payload.status or entry.status
  if entry.status ~= "problem" then entry.fuelProblemLogged = nil end
  entry.position = payload.position or entry.position
  entry.fuel = payload.fuel or entry.fuel
  entry.currentTask = payload.currentTask or entry.currentTask
  return entry
end

function workers.problem(id, payload)
  local entry = registry[tonumber(id)]
  if not entry then return nil, "Worker unbekannt" end
  entry.status = "problem"
  entry.problemArt = payload and payload.art or "unbekannt"
  entry.position = payload and payload.position or entry.position
  return entry
end

function workers.markIdle(id)
  local entry = registry[tonumber(id)]
  if entry then
    entry.status = "idle"
    entry.currentTask = nil
    entry.fuelProblemLogged = nil
  end
  return entry
end

function workers.markReturning(id)
  local entry = registry[tonumber(id)]
  if entry then entry.status = "returning" end
  return entry
end

function workers.all()
  return registry
end

function workers.list()
  local out = {}
  for _, worker in pairs(registry) do out[#out + 1] = worker end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function workers.count()
  return util.count(registry)
end

function workers.idleList()
  local out = {}
  for _, worker in pairs(registry) do
    if worker.status == "idle" then out[#out + 1] = worker end
  end
  return out
end

local function scoreTask(worker, task)
  if worker.position and task.params then
    return math.abs((worker.position.y or task.params.y) - task.params.y)
  end
  return 0
end

function workers.assignBest(job, worker)
  if not job or not worker then return nil end
  local best, bestScore = nil, nil
  for _, task in ipairs(job.subtasks or {}) do
    local berufPasst = (not task.requiredBeruf) or task.requiredBeruf == worker.beruf
    if task.status == "pending" and berufPasst then
      local s = scoreTask(worker, task)
      if not bestScore or s < bestScore then
        best, bestScore = task, s
      end
    end
  end
  if not best then return nil end
  best.status = "assigned"
  best.workerId = worker.id
  best.zugewiesenAm = util.now()
  worker.status = "busy"
  worker.currentTask = best.id
  protocol.send(worker.id, protocol.TASK_ASSIGN, best)
  return best
end

function workers.dispatch(job)
  local assigned = {}
  if not job then return assigned end
  for _, worker in ipairs(workers.idleList()) do
    local task = workers.assignBest(job, worker)
    if task then assigned[#assigned + 1] = task end
  end
  return assigned
end

return workers
