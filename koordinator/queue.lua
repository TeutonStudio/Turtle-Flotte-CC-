-- Zweck: Chronologische Job-Queue fuer den Koordinator.
-- Erwartet: common/util.lua und koordinator/jobs/abbau.lua.

local util = dofile("common/util.lua")
local abbau = dofile("koordinator/jobs/abbau.lua")

local queue = {}

local jobs = {}
local activeJob = nil

function queue.createAbbau(params)
  if type(params) ~= "table" then return nil, "Parameter fehlen" end
  local job = {
    id = util.jobId(),
    typ = "abbau",
    params = { lager = params.lager, von = params.von, bis = params.bis },
    status = "queued",
    erstelltAm = util.now(),
    gestartetAm = nil,
    abgeschlossenAm = nil,
  }
  local subtasks, err = abbau.planeSubtasks(job)
  if not subtasks then return nil, err end
  job.subtasks = subtasks
  jobs[#jobs + 1] = job
  return job
end

function queue.add(job)
  if type(job) ~= "table" or not job.id then return false, "Ungueltiger Job" end
  jobs[#jobs + 1] = job
  return true
end

function queue.peek()
  return jobs[1]
end

function queue.startNext()
  if activeJob then return activeJob end
  local job = table.remove(jobs, 1)
  if not job then return nil end
  job.status = "running"
  job.gestartetAm = util.now()
  activeJob = job
  return job
end

function queue.current()
  return activeJob
end

function queue.finishCurrent(status)
  if not activeJob then return nil end
  activeJob.status = status or "done"
  activeJob.abgeschlossenAm = util.now()
  local done = activeJob
  activeJob = nil
  return done
end

function queue.all()
  return jobs
end

function queue.pendingCount()
  return #jobs
end

function queue.isCurrentComplete()
  if not activeJob then return false end
  local hasFailure = false
  for _, task in ipairs(activeJob.subtasks or {}) do
    if task.status ~= "done" and task.status ~= "failed" then return false end
    if task.status == "failed" then hasFailure = true end
  end
  return true, hasFailure
end

function queue.findSubtask(taskId)
  if not activeJob then return nil end
  for _, task in ipairs(activeJob.subtasks or {}) do
    if task.id == taskId then return task end
  end
  return nil
end

return queue
