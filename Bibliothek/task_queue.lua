-- task_queue.lua
-- Generische FIFO-TODO-Liste mit chronologischem Status.

local M = {}

local function now()
    return os.epoch and os.epoch("utc") or os.time()
end

local function ensureId(task)
    task.id = task.id or tostring(now()) .. ":" .. tostring(math.random(1, 999999))
    return task.id
end

local function find(q, id)
    for _, task in ipairs(q.tasks) do
        if task.id == id then return task end
    end
    return nil
end

function M.new()
    return { tasks = {} }
end

function M.push(q, task)
    task = task or {}
    ensureId(task)
    task.status = task.status or "pending"
    task.createdAt = task.createdAt or now()
    q.tasks[#q.tasks + 1] = task
    return task
end

function M.pop(q)
    for _, task in ipairs(q.tasks) do
        if task.status == "pending" then return task end
    end
    return nil
end

function M.peek(q)
    return M.pop(q)
end

function M.markRunning(q, id)
    local task = find(q, id)
    if task then task.status = "running"; task.startedAt = task.startedAt or now() end
    return task
end

function M.markDone(q, id, result)
    local task = find(q, id)
    if task then task.status = "done"; task.finishedAt = now(); task.result = result end
    return task
end

function M.markFailed(q, id, errorText)
    local task = find(q, id)
    if task then task.status = "failed"; task.finishedAt = now(); task.error = errorText end
    return task
end

function M.list(q, status)
    local out = {}
    for _, task in ipairs(q.tasks) do
        if not status or task.status == status then out[#out + 1] = task end
    end
    return out
end

function M.isEmpty(q)
    return M.pop(q) == nil
end

return M
