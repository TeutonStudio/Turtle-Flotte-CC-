-- worker_core.lua
-- Gemeinsamer Worker-Dienst. Rollen-Dateien uebergeben nur noch ihre Logik.

local fleet = require("fleet_common")
local nav = require("nav")

local M = {}

function M.run(roleModule)
    local cfg = fleet.loadConfig("worker")
    fleet.openRednet()

    local state = {
        busy = false,
        role = cfg.workerRole or roleModule.role,
        progress = "bereit",
        lastError = nil,
        currentJob = nil,
        currentRequest = nil,
        abort = false,
        coordinatorRednetId = nil,
        waitingService = false,
        serviceDone = nil,
    }

    local pendingJob = nil

    local function reportProgress(text)
        state.progress = text
        print("[" .. state.role .. "] " .. text)

        if state.coordinatorRednetId and state.currentRequest then
            fleet.send(cfg, state.coordinatorRednetId, {
                kind = "worker_progress",
                worker = cfg.id,
                workerRole = state.role,
                request_id = state.currentRequest,
                progress = text,
                pos = nav.getPos(),
                facing = nav.getFacingName(),
            })
        end
    end

    local function makeStatus()
        local used, free = fleet.slotSummary()
        local needs = {}

        if roleModule.needs then
            local ok, n = pcall(roleModule.needs, cfg, state)
            if ok then needs = n or {} else needs = { errors = { tostring(n) } } end
        end

        local fuel = turtle.getFuelLevel()
        local fuelLimit = turtle.getFuelLimit and turtle.getFuelLimit() or "?"

        return {
            id = cfg.id,
            role = state.role,
            busy = state.busy,
            job = state.currentJob,
            progress = state.progress,
            lastError = state.lastError,
            fuel = fuel,
            fuelLimit = fuelLimit,
            usedSlots = used,
            freeSlots = free,
            pos = nav.getPos(),
            facing = nav.getFacingName(),
            waitingService = state.waitingService,
            needs = needs,
            items = cfg.reportItems and fleet.itemCounts() or nil,
        }
    end

    local function sendHello()
        fleet.broadcast(cfg, {
            kind = "worker_hello",
            worker = cfg.id,
            workerRole = state.role,
            coordinator = cfg.coordinator,
            status = makeStatus(),
        })
    end

    local function sendStatus(to, requestId)
        fleet.send(cfg, to, {
            kind = "worker_status",
            worker = cfg.id,
            workerRole = state.role,
            request_id = requestId,
            status = makeStatus(),
        })
    end

    nav.setAbortFunction(function() return state.abort end)
    nav.setProgressFunction(reportProgress)

    local function requestService(reason, detail)
        assert(state.coordinatorRednetId, "Koordinator unbekannt")
        assert(state.currentRequest, "Kein aktiver Auftrag fuer Service-Anfrage")

        state.waitingService = true
        state.serviceDone = nil
        reportProgress("Warte auf Koordinator: " .. tostring(reason))

        fleet.send(cfg, state.coordinatorRednetId, {
            kind = "worker_service_request",
            worker = cfg.id,
            workerRole = state.role,
            request_id = state.currentRequest,
            reason = reason,
            detail = detail,
            pos = nav.getPos(),
            facing = nav.getFacingName(),
            status = makeStatus(),
            items = fleet.itemCounts(),
        })

        while not state.serviceDone do
            os.pullEvent("fleet_worker_service_done")
            if state.abort then error("Auftrag abgebrochen") end
        end

        state.waitingService = false
        if state.serviceDone and state.serviceDone.error then
            error("Koordinator-Service fehlgeschlagen: " .. tostring(state.serviceDone.error))
        end
        reportProgress("Koordinator-Service erledigt")
    end

    local function acceptJob(sender, msg)
        if state.busy or pendingJob then
            fleet.send(cfg, sender, {
                kind = "worker_rejected",
                worker = cfg.id,
                request_id = msg.request_id,
                reason = "busy",
                status = makeStatus(),
            })
            return
        end

        if msg.worker and msg.worker ~= cfg.id then return end
        if msg.workerRole and msg.workerRole ~= state.role then return end

        pendingJob = { sender = sender, msg = msg }
        state.coordinatorRednetId = sender

        fleet.send(cfg, sender, {
            kind = "worker_accepted",
            worker = cfg.id,
            workerRole = state.role,
            request_id = msg.request_id,
            status = makeStatus(),
        })

        os.queueEvent("fleet_worker_job")
    end

    local function runPendingJob()
        local bundle = pendingJob
        pendingJob = nil
        if not bundle then return end

        local sender = bundle.sender
        local msg = bundle.msg

        state.busy = true
        state.abort = false
        state.currentJob = msg.job and msg.job.kind or "job"
        state.currentRequest = msg.request_id
        state.coordinatorRednetId = sender
        state.lastError = nil

        local ctx = {
            cfg = cfg,
            state = state,
            nav = nav,
            progress = reportProgress,
            status = makeStatus,
            requestService = requestService,
        }

        local ok, err = pcall(function()
            local fuel = turtle.getFuelLevel()
            if fuel ~= "unlimited" then
                local fuelOk, fuelErr = fleet.ensureFuel(cfg.minFuel or 100)
                if not fuelOk then
                    requestService("fuel", { fuel = fuel, error = fuelErr })
                    fuelOk, fuelErr = fleet.ensureFuel(cfg.minFuel or 100)
                    if not fuelOk then error(fuelErr) end
                end
            end
            roleModule.run(ctx, msg.job or {})
        end)

        if ok then
            state.progress = "fertig"
            fleet.send(cfg, sender, {
                kind = "worker_done",
                worker = cfg.id,
                workerRole = state.role,
                request_id = msg.request_id,
                status = makeStatus(),
            })
        else
            state.lastError = tostring(err)
            state.progress = "Fehler"
            fleet.send(cfg, sender, {
                kind = "worker_error",
                worker = cfg.id,
                workerRole = state.role,
                request_id = msg.request_id,
                error = tostring(err),
                status = makeStatus(),
            })
        end

        state.busy = false
        state.abort = false
        state.currentJob = nil
        state.currentRequest = nil
    end

    local function heartbeatLoop()
        while true do
            sendHello()
            sleep(cfg.statusInterval)
        end
    end

    local function listenLoop()
        rednet.host(cfg.protocol, cfg.id)
        sendHello()

        while true do
            local sender, msg = fleet.receive(cfg)
            if sender and type(msg) == "table" then
                if msg.kind == "coordinator_hello" and (not msg.coordinator or msg.coordinator == cfg.coordinator) then
                    state.coordinatorRednetId = sender

                elseif msg.kind == "worker_status_request" and (not msg.worker or msg.worker == cfg.id) then
                    sendStatus(sender, msg.request_id)

                elseif msg.kind == "worker_job" then
                    if msg.worker == cfg.id or msg.workerRole == state.role then
                        acceptJob(sender, msg)
                    end

                elseif msg.kind == "worker_abort" then
                    if not msg.worker or msg.worker == cfg.id then
                        state.abort = true
                        reportProgress("Abbruch angefordert")
                    end
                elseif msg.kind == "coordinator_service_done" then
                    if (not msg.worker or msg.worker == cfg.id) and msg.request_id == state.currentRequest then
                        state.serviceDone = msg
                        os.queueEvent("fleet_worker_service_done")
                    end
                end
            end
        end
    end

    local function jobLoop()
        while true do
            os.pullEvent("fleet_worker_job")
            runPendingJob()
        end
    end

    print("Worker gestartet: " .. cfg.id .. " | Gruppe: " .. cfg.group .. " | Rolle: " .. state.role)
    parallel.waitForAny(listenLoop, heartbeatLoop, jobLoop)
end

return M
