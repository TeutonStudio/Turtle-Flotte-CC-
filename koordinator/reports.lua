-- Zweck: Persistente Job-Berichte unter reports/<jobId>.json.
-- Erwartet: common/util.lua; CC:Tweaked fs/textutils.

local util = dofile("common/util.lua")

local reports = {}
reports.DIR = "reports"

local function path(jobId)
  return reports.DIR .. "/" .. tostring(jobId) .. ".json"
end

local function summarize(data)
  local total, done, failed = 0, 0, 0
  for _, task in ipairs(data.subtasks or {}) do
    total = total + 1
    if task.status == "done" then done = done + 1 end
    if task.status == "failed" then failed = failed + 1 end
  end
  data.zusammenfassung = {
    gesamt = total,
    fertig = done,
    fehler = failed,
    offen = total - done - failed,
  }
end

local function write(data)
  summarize(data)
  return util.writeFileAtomic(path(data.jobId), util.toJson(data))
end

function reports.erstellen(job)
  if type(job) ~= "table" or not job.id then return false, "Job ungueltig" end
  local data = {
    jobId = job.id,
    befehl = job.typ,
    params = job.params,
    status = job.status,
    erstelltAm = job.erstelltAm,
    gestartetAm = job.gestartetAm,
    abgeschlossenAm = job.abgeschlossenAm,
    zusammenfassung = {},
    subtasks = job.subtasks or {},
  }
  return write(data)
end

function reports.lesen(jobId)
  local raw, err = util.readFile(path(jobId))
  if not raw then return nil, err end
  return util.fromJson(raw)
end

function reports.aktualisieren(jobId, subtaskId, statusUpdate)
  local data, err = reports.lesen(jobId)
  if not data then return false, err end
  statusUpdate = statusUpdate or {}
  if statusUpdate.jobStatus then data.status = statusUpdate.jobStatus end
  if statusUpdate.gestartetAm ~= nil then data.gestartetAm = statusUpdate.gestartetAm end
  if statusUpdate.abgeschlossenAm ~= nil then data.abgeschlossenAm = statusUpdate.abgeschlossenAm end
  if subtaskId then
    for _, task in ipairs(data.subtasks or {}) do
      if task.id == subtaskId then
        for k, v in pairs(statusUpdate) do
          if k ~= "jobStatus" then task[k] = v end
        end
        break
      end
    end
  end
  return write(data)
end

function reports.kurzfassung(jobId)
  local data, err = reports.lesen(jobId)
  if not data then return nil, err end
  summarize(data)
  return {
    jobId = data.jobId,
    befehl = data.befehl,
    params = data.params,
    status = data.status,
    erstelltAm = data.erstelltAm,
    gestartetAm = data.gestartetAm,
    abgeschlossenAm = data.abgeschlossenAm,
    zusammenfassung = data.zusammenfassung,
  }
end

return reports
