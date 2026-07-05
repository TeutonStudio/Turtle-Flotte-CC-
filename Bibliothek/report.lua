-- report.lua
-- Chronologische Reports mit Saldo.

local fleet = require("fleet_common")
local M = {}

local function now()
    return os.epoch("utc")
end

local function addCounts(target, counts)
    for item, count in pairs(counts or {}) do
        target[item] = (target[item] or 0) + count
    end
end

function M.start(commandId, commandKind, payload)
    return {
        id = commandId,
        command = { kind = commandKind, payload = fleet.safeCopy(payload) },
        status = "running",
        createdAt = now(),
        finishedAt = nil,
        events = {},
        saldo = {
            fuelUsed = 0,
            itemsGained = {},
            itemsConsumed = {},
            workerTasks = 0,
            failures = 0,
        },
    }
end

function M.event(report, kind, detail)
    if not report then return end
    report.events[#report.events + 1] = { at = now(), kind = kind, detail = fleet.safeCopy(detail) }
end

function M.finish(report, status, detail)
    if not report then return end
    report.status = status
    report.finishedAt = now()
    M.event(report, "finish", detail)
end

function M.addFuelUsed(report, amount)
    if report then report.saldo.fuelUsed = report.saldo.fuelUsed + (amount or 0) end
end

function M.addItemsGained(report, itemCounts)
    if report then addCounts(report.saldo.itemsGained, itemCounts) end
end

function M.addItemsConsumed(report, itemCounts)
    if report then addCounts(report.saldo.itemsConsumed, itemCounts) end
end

function M.addWorkerTask(report)
    if report then report.saldo.workerTasks = report.saldo.workerTasks + 1 end
end

function M.addFailure(report)
    if report then report.saldo.failures = report.saldo.failures + 1 end
end

local function encode(value)
    value = fleet.safeCopy(value)
    if textutils.serializeJSON then return textutils.serializeJSON(value) end
    return textutils.serialiseJSON(value)
end

function M.save(reportDir, report)
    if not report then return end
    reportDir = reportDir or "berichte"
    if not fs.exists(reportDir) then fs.makeDir(reportDir) end
    local path = fs.combine(reportDir, report.id .. ".json")
    local h = fs.open(path, "w")
    h.write(encode(report))
    h.close()
    return path
end

return M
