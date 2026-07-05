-- koordinator.lua
-- Basisdienst: nimmt Pocket-Befehle an, deployt Worker aus der Truhe, betankt sie grob und verteilt Jobs.

local fleet = require("fleet_common")
local nav = require("nav")

local cfg = fleet.loadConfig("coordinator")
fleet.openRednet()
rednet.host(cfg.protocol, cfg.id)

local workers = {}
for _, w in ipairs(cfg.workers or {}) do
    workers[w.id] = {
        id = w.id,
        role = w.role,
        rednetId = nil,
        online = false,
        lastSeen = nil,
        status = nil,
    }
end

local state = {
    busy = false,
    progress = "bereit",
    lastError = nil,
    lastDeploy = nil,
    currentReportId = nil,
    currentJobChest = nil,
    currentJobKind = nil,
    serviceBusy = false,
    serviceQueue = {},
    fuelEmptyWarned = false,
    activeJobs = {},
    formation = {
        initialized = false,
        slots = {},
    },
}

local reports = {}
local DEFAULT_DEPLOY_SIDES = { "left", "right", "front" }
local LEGACY_DEPLOY_SIDES = { "right", "left", "back", "top" }
local appendReport
local log
local chat
local withInitChest
local leaveInitChest

local function shortage(kind, text, extra, reportId)
    state.lastError = text
    log(text)
    chat(text)
    appendReport(reportId or state.currentReportId, "Mangelmeldung/" .. tostring(kind) .. ": " .. text, extra)
    return text
end

function log(text)
    state.progress = text
    print("[Koordinator] " .. text)
end

function chat(text)
    if not cfg.chat or cfg.chat.enabled == false then return end
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p then
            if type(p.sendMessage) == "function" then
                local ok = pcall(function() p.sendMessage("[" .. cfg.id .. "] " .. text) end)
                if ok then return end
            elseif type(p.sendFormattedMessage) == "function" then
                local ok = pcall(function() p.sendFormattedMessage("[" .. cfg.id .. "] " .. text) end)
                if ok then return end
            end
        end
    end
end

local function now()
    return os.epoch("utc")
end

local function vecString(v)
    return fleet.vecString(v)
end

local function reportDir()
    return cfg.reportDir or "berichte"
end

local function ensureReportDir()
    if fs and not fs.exists(reportDir()) then fs.makeDir(reportDir()) end
end

local function encodeJson(value)
    local safe = fleet.safeCopy(value)
    if textutils and textutils.serializeJSON then return textutils.serializeJSON(safe) end
    if textutils and textutils.serialiseJSON then return textutils.serialiseJSON(safe) end
    error("textutils.serializeJSON fehlt")
end

local function saveReport(report)
    if not report then return end
    ensureReportDir()
    local path = fs.combine(reportDir(), report.id .. ".json")
    local h = fs.open(path, "w")
    h.write(encodeJson(report))
    h.close()

    local index = {}
    for id, r in pairs(reports) do
        index[#index + 1] = {
            id = id,
            kind = r.kind,
            status = r.status,
            createdAt = r.createdAt,
            updatedAt = r.updatedAt,
            chest = fleet.safeCopy(r.chest),
        }
    end
    table.sort(index, function(a, b) return tostring(a.createdAt) < tostring(b.createdAt) end)
    local ih = fs.open(fs.combine(reportDir(), "index.json"), "w")
    ih.write(encodeJson(index))
    ih.close()
end

function appendReport(reportId, text, extra)
    if not reportId then return end
    local report = reports[reportId]
    if not report then return end
    report.updatedAt = now()
    report.events[#report.events + 1] = {
        at = report.updatedAt,
        text = text,
        extra = fleet.safeCopy(extra),
    }
    local ok, err = pcall(function() saveReport(report) end)
    if not ok then
        state.lastError = "Report konnte nicht gespeichert werden: " .. tostring(err)
        print("[Koordinator] " .. state.lastError)
    end
end

local function startReport(requestId, kind, job)
    local id = requestId or fleet.requestId()
    local safeJob = fleet.safeCopy(job)
    local report = {
        id = id,
        kind = kind,
        status = "running",
        createdAt = now(),
        updatedAt = now(),
        coordinator = cfg.id,
        group = cfg.group,
        chest = job and fleet.safeCopy(job.chest) or nil,
        job = safeJob,
        workers = {},
        events = {},
    }
    reports[id] = report
    state.currentReportId = id
    state.currentJobKind = kind
    state.currentJobChest = job and fleet.safeCopy(job.chest) or state.currentJobChest
    appendReport(id, "Auftrag angelegt: " .. tostring(kind), { job = job })
    return report
end

local function finishReport(reportId, status, text, extra)
    local report = reports[reportId]
    if not report then return end
    report.status = status
    appendReport(reportId, text, extra)
    if state.currentReportId == reportId and status ~= "running" then
        state.currentReportId = nil
        state.currentJobKind = nil
    end
end

local function turnRelative(side)
    if side == "front" then return function() end end
    if side == "back" then turtle.turnRight(); turtle.turnRight(); return function() turtle.turnRight(); turtle.turnRight() end end
    if side == "left" then turtle.turnLeft(); return function() turtle.turnRight() end end
    if side == "right" then turtle.turnRight(); return function() turtle.turnLeft() end end
    if side == "top" or side == "bottom" then return function() end end
    error("Ungueltige Seite: " .. tostring(side))
end

local function suckFrom(side, amount)
    local restore = turnRelative(side)
    local ok, err
    if side == "top" then ok, err = turtle.suckUp(amount)
    elseif side == "bottom" then ok, err = turtle.suckDown(amount)
    else ok, err = turtle.suck(amount) end
    restore()
    return ok, err
end

local function dropTo(side, amount)
    local restore = turnRelative(side)
    local ok, err
    if side == "top" then ok, err = turtle.dropUp(amount)
    elseif side == "bottom" then ok, err = turtle.dropDown(amount)
    else ok, err = turtle.drop(amount) end
    restore()
    return ok, err
end

local function placeTo(side)
    local restore = turnRelative(side)
    local ok, err
    if side == "top" then ok, err = turtle.placeUp()
    elseif side == "bottom" then ok, err = turtle.placeDown()
    else ok, err = turtle.place() end
    restore()
    return ok, err
end

local function detectTo(side)
    local restore = turnRelative(side)
    local ok
    if side == "top" then ok = turtle.detectUp()
    elseif side == "bottom" then ok = turtle.detectDown()
    else ok = turtle.detect() end
    restore()
    return ok
end

local function inspectTo(side)
    local restore = turnRelative(side)
    local ok, data
    if side == "top" then ok, data = turtle.inspectUp()
    elseif side == "bottom" then ok, data = turtle.inspectDown()
    else ok, data = turtle.inspect() end
    restore()
    return ok, data
end

local function digTo(side)
    local restore = turnRelative(side)
    local ok, err
    if side == "top" then ok, err = turtle.digUp()
    elseif side == "bottom" then ok, err = turtle.digDown()
    else ok, err = turtle.dig() end
    restore()
    return ok, err
end

local function firstFilledSlot()
    for i = 1, 16 do if turtle.getItemCount(i) > 0 then return i end end
    return nil
end

local function isTurtleItem(detail)
    return detail and type(detail.name) == "string" and detail.name:find("turtle", 1, true) ~= nil
end

local function isTurtleBlock(data)
    return data and type(data.name) == "string" and data.name:find("turtle", 1, true) ~= nil
end

local function isFuelSlot(slot)
    if not slot or turtle.getItemCount(slot) <= 0 then return false end
    local old = turtle.getSelectedSlot()
    turtle.select(slot)
    local ok = turtle.refuel(0)
    turtle.select(old)
    return ok
end

local function returnSlotToChest(slot)
    if not slot or turtle.getItemCount(slot) <= 0 then return true end
    turtle.select(slot)
    return dropTo(state.depotAccessSide or cfg.chestSide or "front")
end

local function returnNonFuelToChest(preserveTurtles)
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and not isFuelSlot(i) and not (preserveTurtles and isTurtleItem(d)) then
            returnSlotToChest(i)
        end
    end
    turtle.select(1)
end

local function returnAllLooseItemsToChest()
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then returnSlotToChest(i) end
    end
    turtle.select(1)
end

local function findTurtleSlotInInventory()
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if isTurtleItem(d) then return i, d end
    end
    return nil, nil
end

local function countFuelInInventory()
    local count = 0
    for i = 1, 16 do
        if isFuelSlot(i) then count = count + turtle.getItemCount(i) end
    end
    return count
end

local function sameList(a, b)
    if type(a) ~= "table" or #a ~= #b then return false end
    for i = 1, #b do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function copyList(list)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    return copy
end

local function usesLegacyDeployLayout()
    return sameList(cfg.deploySides, LEGACY_DEPLOY_SIDES)
end

local function deploySides()
    if usesLegacyDeployLayout() then return copyList(DEFAULT_DEPLOY_SIDES) end
    if cfg.deploySides and #cfg.deploySides > 0 then return cfg.deploySides end
    if cfg.deploySide then return { cfg.deploySide } end
    return copyList(DEFAULT_DEPLOY_SIDES)
end

local function initFormation()
    if type(cfg.initFormation) == "table" and #cfg.initFormation > 0 then return cfg.initFormation end
    local sides = deploySides()
    local rows = {}
    local row = { sides = {}, moveForwardAfter = false }
    for _, side in ipairs(sides) do row.sides[#row.sides + 1] = side end
    rows[1] = row
    return rows
end

local function plannedFormationSlots(limit)
    local slots = {}
    limit = limit or cfg.deployCount or 4
    for rowIndex, row in ipairs(initFormation()) do
        for _, side in ipairs(row.sides or {}) do
            if #slots >= limit then return slots end
            slots[#slots + 1] = {
                index = #slots + 1,
                row = rowIndex,
                side = side,
                label = "Reihe " .. tostring(rowIndex) .. " " .. tostring(side),
            }
        end
    end
    return slots
end

local function deployCount()
    local count = cfg.deployCount or #(cfg.workers or {})
    if type(cfg.initFormation) == "table" and #cfg.initFormation > 0 and count == 0 then count = #plannedFormationSlots(99) end
    if usesLegacyDeployLayout() and count == 4 and not cfg.initFormation then count = #DEFAULT_DEPLOY_SIDES end
    if count <= 0 then count = 1 end
    return count
end

local function configuredWorkerCount()
    local byConfig = deployCount()
    if byConfig and byConfig > 0 then return byConfig end
    local count = 0
    for _ in pairs(workers) do count = count + 1 end
    return math.max(count, 1)
end

local function warnLowFuelBuffer(available)
    local required = (configuredWorkerCount() + 1) * 64
    if available < required then
        local text = "Treibstoffpuffer gering: " .. tostring(available) .. "/" .. tostring(required) .. " Items in Koordinator/gezogener Reserve"
        log(text)
        chat(text)
        appendReport(state.currentReportId, text)
    end
    if available <= 0 and not state.fuelEmptyWarned then
        state.fuelEmptyWarned = true
        chat("Treibstoff in der Init-Truhe ist leer oder nicht erreichbar")
        appendReport(state.currentReportId, "Treibstoff in der Init-Truhe ist leer oder nicht erreichbar")
    elseif available > 0 then
        state.fuelEmptyWarned = false
    end
end

local pullFuelFromChest

local function pullUntilTurtleFound(label)
    local chestSide = state.depotAccessSide or cfg.chestSide or "front"
    local limit = cfg.searchPullLimit or 64

    local slot = findTurtleSlotInInventory()
    if slot then return slot end

    local held = {}
    for i = 1, limit do
        local ok, err = suckFrom(chestSide, 1)
        if not ok then
            if i == 1 then error("Konnte keinen Worker aus der Truhe ziehen: " .. tostring(err)) end
            break
        end

        slot = findTurtleSlotInInventory()
        if slot then return slot end
        for s = 1, 16 do
            if turtle.getItemCount(s) > 0 and not held[s] then held[s] = true end
        end
    end

    returnNonFuelToChest()
    error(shortage("worker", "Keine Turtle in der Init-Truhe gefunden" .. (label and (" fuer " .. label) or ""), {
        label = label,
        searchPullLimit = limit,
    }))
end

local function countTurtlesInInventory()
    local count = 0
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if isTurtleItem(d) then count = count + turtle.getItemCount(i) end
    end
    return count
end

local function prefetchInitSupplies(workerCount)
    state.atInitChest = true
    state.depotAccessSide = cfg.chestSide or "back"
    local limit = (cfg.searchPullLimit or 64) * workerCount
    local attempts = 0
    while countTurtlesInInventory() < workerCount do
        attempts = attempts + 1
        if attempts > limit then
            error(shortage("worker", "Nicht genug Worker-Turtles zum Vorladen gefunden: " .. tostring(countTurtlesInInventory()) .. "/" .. tostring(workerCount), {
                required = workerCount,
                found = countTurtlesInInventory(),
            }))
        end
        local ok = suckFrom(state.depotAccessSide, 1)
        if not ok then
            error(shortage("worker", "Init-Truhe enthaelt nicht genug Worker-Turtles: " .. tostring(countTurtlesInInventory()) .. "/" .. tostring(workerCount), {
                required = workerCount,
                found = countTurtlesInInventory(),
            }))
        end
    end
    local fuelNeeded = workerCount * (cfg.workerFuelItems or 64) + (cfg.coordinatorFuelReserveItems or 64)
    if countFuelInInventory() < fuelNeeded then
        state.preserveTurtlesDuringFuelSearch = true
        pullFuelFromChest(fuelNeeded - countFuelInInventory())
        state.preserveTurtlesDuringFuelSearch = false
    end
    state.atInitChest = false
    state.depotAccessSide = nil
end

function pullFuelFromChest(minItems)
    minItems = minItems or (cfg.workerFuelItems or 8)
    if minItems <= 0 then return 0 end

    local chestSide = state.depotAccessSide or cfg.chestSide or "front"
    local limit = cfg.fuelSearchPullLimit or cfg.searchPullLimit or math.max(128, minItems * 3)
    local before = countFuelInInventory()
    local heldNonFuel = false

    for _ = 1, limit do
        if countFuelInInventory() - before >= minItems then break end
        local ok = suckFrom(chestSide, 1)
        if not ok then break end
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and not isFuelSlot(slot) then
                heldNonFuel = true
                break
            end
        end
    end

    -- Keep accidental depot items in inventory during the search so the next suck
    -- can reach later chest slots instead of pulling the same turtle forever.
    if heldNonFuel then returnNonFuelToChest(state.preserveTurtlesDuringFuelSearch) end

    local pulled = countFuelInInventory() - before
    if pulled < minItems then
        warnLowFuelBuffer(countFuelInInventory())
        shortage("fuel", "Zu wenig Treibstoff in der Init-Truhe: " .. tostring(pulled) .. "/" .. tostring(minItems) .. " Items gezogen", {
            requested = minItems,
            pulled = pulled,
            available = countFuelInInventory(),
        })
    end
    return pulled
end

local function dropFuelToWorker(side, wanted)
    wanted = wanted or (cfg.workerFuelItems or 64)
    if wanted <= 0 then return 0 end

    local dropped = 0
    for i = 1, 16 do
        if dropped >= wanted then break end
        if isFuelSlot(i) then
            turtle.select(i)
            local amount = math.min(wanted - dropped, turtle.getItemCount(i))
            local ok = dropTo(side, amount)
            if ok then dropped = dropped + amount end
        end
    end
    turtle.select(1)
    return dropped
end

local function fuelPlacedWorker(side)
    local wanted = cfg.workerFuelItems or 64
    if wanted <= 0 then return 0 end

    if countFuelInInventory() < wanted then
        if state.atInitChest then
            pullFuelFromChest(wanted - countFuelInInventory())
        else
            withInitChest(function()
                pullFuelFromChest(wanted - countFuelInInventory())
            end)
        end
    end

    local dropped = dropFuelToWorker(side, wanted)
    if dropped < wanted then
        local text = shortage("fuel", "Worker auf " .. tostring(side) .. " erhielt nur " .. tostring(dropped) .. "/" .. tostring(wanted) .. " Treibstoff-Items", {
            side = side,
            wanted = wanted,
            dropped = dropped,
        })
        if dropped <= 0 then error(text) end
    end

    -- Fuel bleibt als Koordinator-Reserve im Inventar. Nicht-Fuel wird nur dann
    -- zurueckgelegt, wenn wir gerade wirklich an der Init-Truhe arbeiten.
    if state.atInitChest then returnNonFuelToChest() end

    return dropped
end

local function deployOne(label, side)
    side = side or deploySides()[1]
    if detectTo(side) then
        local okInspect, data = inspectTo(side)
        local blockName = okInspect and data and data.name or "unbekannt"
        if isTurtleBlock(data) then
            appendReport(state.currentReportId, "Formation-Slot bereits durch Turtle belegt: " .. tostring(label), {
                side = side,
                block = blockName,
            })
            return side, "occupied"
        end
        local dug = digTo(side)
        if not dug or detectTo(side) then
            local text = "Deploy-Seite blockiert durch " .. tostring(blockName) .. " auf " .. tostring(side)
            chat(text)
            appendReport(state.currentReportId, text, { side = side, block = blockName })
            error(text)
        end
        appendReport(state.currentReportId, "Stoerenden Block beim Initialisieren abgebaut: " .. tostring(blockName), {
            side = side,
            block = blockName,
        })
    end

    log("Ziehe Worker aus Depot" .. (label and (" fuer " .. label) or ""))
    local slot = findTurtleSlotInInventory()
    if slot then
        -- Bereits vorgeladen.
    elseif state.atInitChest then
        slot = pullUntilTurtleFound(label)
    else
        slot = withInitChest(function() return pullUntilTurtleFound(label) end)
    end
    turtle.select(slot)

    log("Platziere Worker nach " .. side)
    local placed, placeErr = placeTo(side)
    if not placed then
        withInitChest(function() returnSlotToChest(slot) end)
        error("Konnte Worker nicht platzieren auf " .. tostring(side) .. ": " .. tostring(placeErr))
    end

    local fuelDropped = fuelPlacedWorker(side)
    if fuelDropped > 0 then log("Worker auf " .. side .. " mit " .. fuelDropped .. " Fuel-Items bestueckt") end
    appendReport(state.currentReportId, "Arbeiter auf " .. side .. " erhielt " .. tostring(fuelDropped) .. " Treibstoff-Items", {
        side = side,
        fuelItems = fuelDropped,
    })

    state.lastDeploy = os.epoch("utc")
    sleep(cfg.deployPause or 1.5)
    return side
end

local function recordWorker(sender, msg)
    local id = msg.worker or msg.from
    if not id then return end

    if not workers[id] then
        workers[id] = {
            id = id,
            role = msg.workerRole or "unbekannt",
        }
    end

    workers[id].rednetId = sender
    workers[id].role = msg.workerRole or workers[id].role
    workers[id].online = true
    workers[id].lastSeen = os.epoch("utc")
    workers[id].status = fleet.safeCopy(msg.status or workers[id].status)
end

local function getWorkersByRole(role)
    local list = {}
    for _, w in pairs(workers) do
        local status = w.status or {}
        if w.role == role and w.rednetId and not status.busy and not status.waitingService then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function waitForRole(role, timeout)
    local deadline = os.epoch("utc") + ((timeout or cfg.deployWait or 8) * 1000)

    while true do
        local existing = getWorkersByRole(role)
        if #existing > 0 then return existing[1] end

        local remaining = (deadline - os.epoch("utc")) / 1000
        if remaining <= 0 then return nil end

        local sender, msg = fleet.receive(cfg, remaining)
        if sender and type(msg) == "table" then
            if msg.kind == "worker_hello" or msg.kind == "worker_status" or msg.kind == "worker_progress" or msg.kind == "worker_done" or msg.kind == "worker_error" then
                recordWorker(sender, msg)
            elseif msg.kind == "pocket_command" then
                -- Waehrend Auto-Deploy ignorieren wir neue Pocket-Befehle. Sonst wird das hier ein Callcenter.
            end
        end
    end
end

local function onlineWorkerCount()
    local count = 0
    for _, w in pairs(workers) do
        if w.rednetId then count = count + 1 end
    end
    return count
end

local function waitForOnlineWorkers(required, timeout)
    local deadline = os.epoch("utc") + ((timeout or cfg.workerOnlineWait or cfg.deployWait or 12) * 1000)
    while onlineWorkerCount() < required do
        local remaining = (deadline - os.epoch("utc")) / 1000
        if remaining <= 0 then return false end
        local sender, msg = fleet.receive(cfg, remaining)
        if sender and type(msg) == "table" then
            if msg.kind == "worker_hello" or msg.kind == "worker_status" or msg.kind == "worker_progress" or msg.kind == "worker_done" or msg.kind == "worker_error" then
                recordWorker(sender, msg)
            end
        end
    end
    return true
end

local function deployUntilRole(role)
    local existing = getWorkersByRole(role)
    if #existing > 0 then return existing[1] end

    local sides = deploySides()
    local tried = {}

    for _, side in ipairs(sides) do
        if not detectTo(side) then
            tried[#tried + 1] = side
            deployOne(role, side)
            local w = waitForRole(role, cfg.deployWait or 8)
            if w then return w end
        end
    end

    error("Kein erreichbarer Worker fuer Rolle: " .. tostring(role) ..
        ". Auto-Deploy versucht auf Seiten: " .. table.concat(tried, ", ") ..
        ". Pruefe: Worker-Config, startup.lua, Arbeitsgruppe, IDs und ob die gewuenschte Turtle in der Truhe liegt.")
end

local function formationForward()
    calibrateCoordinator()
    leaveInitChest()
    local ok, err = pcall(function() nav.forwardDig() end)
    if not ok then
        error(shortage("formation_blocked", "Initialisierungs-Formation blockiert: Koordinator kann nicht vorfahren (" .. tostring(err) .. ")", {
            pos = nav.getPos(),
            facing = nav.getFacingName(),
        }))
    end
end

local function ensureInitialized(required)
    required = required or deployCount()
    local alreadyOnline = onlineWorkerCount()
    if alreadyOnline >= required then
        state.formation.initialized = true
        return true
    end

    local slots = plannedFormationSlots(required)
    if #slots < required then
        error(shortage("worker", "Init-Formation plant nur " .. tostring(#slots) .. "/" .. tostring(required) .. " Worker", {
            required = required,
            planned = #slots,
        }))
    end

    calibrateCoordinator()
    appendReport(state.currentReportId, "Initialisiere Worker-Formation", {
        required = required,
        online = alreadyOnline,
        slots = slots,
    })
    if not cfg.initChest then
        appendReport(state.currentReportId, "Keine initChest-Koordinate gesetzt; lade Worker und Treibstoff vor dem Vorfahren vor")
        prefetchInitSupplies(required - alreadyOnline)
    end

    local placedOrOccupied = 0
    local slotIndex = 1
    for rowIndex, row in ipairs(initFormation()) do
        for _, side in ipairs(row.sides or {}) do
            if slotIndex > required then break end
            local label = "Worker " .. tostring(slotIndex) .. "/" .. tostring(required) .. " (" .. tostring(side) .. ", Reihe " .. tostring(rowIndex) .. ")"
            local occupied = false
            if detectTo(side) then
                local okInspect, data = inspectTo(side)
                if okInspect and isTurtleBlock(data) then
                    occupied = true
                    appendReport(state.currentReportId, "Formation-Slot bereits belegt: " .. label, {
                        side = side,
                        row = rowIndex,
                        block = data.name,
                    })
                else
                    local name = okInspect and data and data.name or "unbekannt"
                    error(shortage("formation_blocked", "Formation-Slot blockiert: " .. label .. " durch " .. tostring(name), {
                        side = side,
                        row = rowIndex,
                        block = name,
                    }))
                end
            end
            if not occupied then deployOne(label, side) end
            placedOrOccupied = placedOrOccupied + 1
            state.formation.slots[slotIndex] = {
                row = rowIndex,
                side = side,
                occupied = true,
                label = label,
                pos = nav.getPos(),
                facing = nav.getFacingName(),
            }
            slotIndex = slotIndex + 1
        end
        if row.moveForwardAfter then formationForward() end
        if slotIndex > required then break end
    end

    requestWorkerStatuses()
    local okOnline = waitForOnlineWorkers(required, cfg.workerOnlineWait or cfg.deployWait or 12)
    if not okOnline then
        local text = "Nur " .. tostring(onlineWorkerCount()) .. "/" .. tostring(required) .. " Worker kamen online. Pruefe startup.lua, fleet_config.lua, Rolle, Modem, Gruppe und ob platzierte Turtles betankt sind."
        error(shortage("worker", text, {
            required = required,
            online = onlineWorkerCount(),
            formationSlots = state.formation.slots,
        }))
    end

    state.formation.initialized = true
    appendReport(state.currentReportId, "Worker-Formation initialisiert", {
        required = required,
        online = onlineWorkerCount(),
        placedOrOccupied = placedOrOccupied,
    })
    return true
end

local function deployAll()
    return ensureInitialized(deployCount())
end

local function allWorkerList()
    local list = {}
    for _, w in pairs(workers) do
        list[#list + 1] = {
            id = w.id,
            role = w.role,
            online = w.rednetId ~= nil,
            lastSeen = w.lastSeen,
            rednetId = w.rednetId,
            status = w.status,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function aggregateNeeds()
    local needs = { items = {}, recipes = {}, warnings = {} }

    for _, w in pairs(workers) do
        local s = w.status
        if s and s.needs then
            for item, count in pairs(s.needs.items or {}) do
                if type(count) == "number" then needs.items[item] = math.max(needs.items[item] or 0, count) end
            end
            for _, recipe in ipairs(s.needs.recipes or {}) do
                needs.recipes[#needs.recipes + 1] = { worker = w.id, recipe = recipe }
            end
            for _, warning in ipairs(s.needs.warnings or {}) do
                needs.warnings[#needs.warnings + 1] = w.id .. ": " .. warning
            end
        end
    end

    return needs
end

local function coordinatorStatus()
    local used, free = fleet.slotSummary()
    local planned = deployCount()
    local online = onlineWorkerCount()
    local missing = math.max(0, planned - online)
    return {
        id = cfg.id,
        group = cfg.group,
        busy = state.busy,
        progress = state.progress,
        lastError = state.lastError,
        currentReportId = state.currentReportId,
        currentJobKind = state.currentJobKind,
        currentJobChest = state.currentJobChest,
        queuedServiceRequests = #state.serviceQueue,
        usedSlots = used,
        freeSlots = free,
        chestSide = cfg.chestSide or "front",
        deploySide = cfg.deploySide or "right",
        deploySides = deploySides(),
        initStatus = {
            initialized = state.formation.initialized or online >= planned,
            plannedWorkers = planned,
            onlineWorkers = online,
            missingWorkers = missing,
            formationSlots = fleet.safeCopy(state.formation.slots),
            fuelReserve = countFuelInInventory(),
        },
        workers = allWorkerList(),
        needs = aggregateNeeds(),
    }
end

local function reply(to, requestId, kind, extra)
    extra = extra or {}
    extra.kind = kind
    extra.coordinator = cfg.id
    extra.request_id = requestId
    fleet.send(cfg, to, extra)
end

local function requestWorkerStatuses()
    for _, w in pairs(workers) do
        if w.rednetId then
            fleet.send(cfg, w.rednetId, {
                kind = "worker_status_request",
                worker = w.id,
                request_id = fleet.requestId(),
            })
        end
    end
end

local function calibrateCoordinator()
    if state.navReady then return true end
    nav.calibrate(cfg.start, cfg.facing)
    nav.setDigFilter(function() return false end)
    state.navReady = true
    return true
end

local function goAdjacentTo(pos)
    calibrateCoordinator()
    if leaveInitChest then leaveInitChest() end
    nav.setChest(pos)
    nav.goAdjacentToChest()
end

local function reserveFuelSlots()
    local slots = {}
    for i = 1, 16 do
        if isFuelSlot(i) then slots[i] = true end
    end
    return slots
end

local function goToInitChest()
    assert(cfg.initChest, "cfg.initChest fehlt: Koordinator braucht Koordinaten der Init-Truhe fuer Nachversorgung")
    goAdjacentTo(cfg.initChest)
    state.atInitChest = true
    state.depotAccessSide = "front"
end

function leaveInitChest()
    state.atInitChest = false
    state.depotAccessSide = nil
end

local function saveNavPose()
    return { pos = nav.getPos(), facing = nav.getFacingName() }
end

local function restoreNavPose(pose)
    if not pose or not pose.pos then return end
    calibrateCoordinator()
    leaveInitChest()
    nav.goTo(pose.pos)
    if pose.facing then nav.turnTo(pose.facing) end
end

function withInitChest(fn)
    local pose = nil
    local canReturn = cfg.initChest ~= nil
    if canReturn then pose = saveNavPose(); goToInitChest() else state.atInitChest = true; state.depotAccessSide = cfg.chestSide or "back" end
    local ok, result = pcall(fn)
    if canReturn then restoreNavPose(pose) else state.atInitChest = false; state.depotAccessSide = nil end
    if not ok then error(result) end
    return result
end

local function ensureFuelReserve()
    local wanted = cfg.coordinatorFuelReserveItems or 64
    if countFuelInInventory() >= wanted then return true end
    goToInitChest()
    pullFuelFromChest(wanted - countFuelInInventory())
    if countFuelInInventory() < wanted then warnLowFuelBuffer(countFuelInInventory()) end
    return countFuelInInventory() >= math.min(wanted, 1)
end

local function dropFuelForward(wanted)
    wanted = wanted or (cfg.workerFuelItems or 64)
    local dropped = 0
    for i = 1, 16 do
        if dropped >= wanted then break end
        if isFuelSlot(i) then
            turtle.select(i)
            local amount = math.min(wanted - dropped, turtle.getItemCount(i))
            if turtle.drop(amount) then dropped = dropped + amount end
        end
    end
    turtle.select(1)
    return dropped
end

local function pullItemsForward()
    local pulled = 0
    for _ = 1, 16 do
        local before = 0
        for i = 1, 16 do before = before + turtle.getItemCount(i) end
        local ok = turtle.suck()
        local after = 0
        for i = 1, 16 do after = after + turtle.getItemCount(i) end
        if not ok or after == before then break end
        pulled = pulled + (after - before)
    end
    return pulled
end

local function emptyItemsToJobChest(jobChest, reportId)
    jobChest = jobChest or state.currentJobChest
    assert(jobChest, "Keine Job-Truhe fuer aktuellen Auftrag gesetzt")
    local reserved = reserveFuelSlots()
    goAdjacentTo(jobChest)
    local moved = 0
    for i = 1, 16 do
        if not reserved[i] and turtle.getItemCount(i) > 0 then
            turtle.select(i)
            local count = turtle.getItemCount(i)
            local ok = turtle.drop()
            if ok then
                moved = moved + count
            else
                local text = shortage("storage_full", "Job-Truhe voll oder nicht erreichbar bei " .. vecString(jobChest), {
                    chest = jobChest,
                    slot = i,
                    count = count,
                }, reportId)
                error(text)
            end
        end
    end
    turtle.select(1)
    return moved
end

local function enqueueService(sender, msg)
    recordWorker(sender, msg)
    state.serviceQueue[#state.serviceQueue + 1] = {
        sender = sender,
        requestId = msg.request_id,
        worker = msg.worker,
        role = msg.workerRole,
        reason = msg.reason,
        pos = msg.pos,
        facing = msg.facing,
        detail = msg.detail,
        items = msg.items,
        job = msg.job,
        jobKind = msg.jobKind or (msg.job and msg.job.kind),
        jobChest = msg.jobChest or (msg.job and msg.job.chest) or state.currentJobChest,
        reportId = msg.request_id,
    }
    appendReport(msg.request_id, "Service-Anfrage von Arbeiter " .. tostring(msg.worker) .. ": " .. tostring(msg.reason), {
        worker = msg.worker,
        role = msg.workerRole,
        pos = msg.pos,
        detail = msg.detail,
    })
end

local function completeService(req, ok, err)
    fleet.send(cfg, req.sender, {
        kind = "coordinator_service_done",
        worker = req.worker,
        request_id = req.requestId,
        ok = ok,
        error = err,
    })
end

local function handleServiceRequest(req)
    assert(req and req.pos, "Service-Anfrage ohne Worker-Position")
    if not ensureFuelReserve() then
        error(shortage("fuel", "Koordinator hat keine Treibstoffreserve fuer Servicefahrt", {
            worker = req.worker,
            reason = req.reason,
        }, req.reportId))
    end
    goAdjacentTo(req.pos)

    if req.reason == "fuel" then
        local dropped = dropFuelForward(cfg.workerFuelItems or 64)
        if dropped <= 0 then
            error(shortage("fuel", "Kein Treibstoff fuer Worker-Service verfuegbar", {
                worker = req.worker,
                pos = req.pos,
            }, req.reportId))
        end
        appendReport(req.reportId, "Arbeiter " .. tostring(req.worker) .. " erhielt " .. tostring(dropped) .. " Treibstoff-Items", {
            worker = req.worker,
            pos = req.pos,
            fuelItems = dropped,
        })
    elseif req.reason == "inventory_full" or req.reason == "inventory_unload" then
        local pulled = pullItemsForward()
        appendReport(req.reportId, "Items von Arbeiter " .. tostring(req.worker) .. " aufgenommen: " .. tostring(pulled), {
            worker = req.worker,
            pos = req.pos,
            items = req.items,
            count = pulled,
        })
        local moved = emptyItemsToJobChest(req.jobChest, req.reportId)
        appendReport(req.reportId, "Items von Arbeiter " .. tostring(req.worker) .. " zu Lager " .. vecString(req.jobChest) .. " gebracht: " .. tostring(moved), {
            worker = req.worker,
            chest = req.jobChest,
            count = moved,
        })
    else
        appendReport(req.reportId, "Unbekannte Service-Anfrage von Arbeiter " .. tostring(req.worker) .. ": " .. tostring(req.reason))
    end
end

local function serviceLoop()
    while true do
        if not state.serviceBusy and #state.serviceQueue > 0 then
            state.serviceBusy = true
            local req = table.remove(state.serviceQueue, 1)
            local ok, err = pcall(function() handleServiceRequest(req) end)
            if ok then
                local sent = pcall(function() completeService(req, true) end)
                if not sent then print("[Koordinator] Service-Antwort konnte nicht gesendet werden") end
            else
                local text = tostring(err)
                state.lastError = text
                appendReport(req.reportId, "Koordinator-Service fehlgeschlagen: " .. text)
                chat("Koordinator-Service fehlgeschlagen fuer " .. tostring(req.worker) .. ": " .. text)
                local sent = pcall(function() completeService(req, false, text) end)
                if not sent then print("[Koordinator] Service-Fehlerantwort konnte nicht gesendet werden") end
            end
            state.serviceBusy = false
            if #state.serviceQueue == 0 and cfg.initChest then
                local okBack, backErr = pcall(function() goToInitChest() end)
                if not okBack then
                    state.lastError = tostring(backErr)
                    appendReport(req.reportId, "Rueckkehr zur Init-Truhe fehlgeschlagen: " .. tostring(backErr))
                end
            end
        end
        sleep(0.5)
    end
end

local function sendJobToWorker(w, job, requestId)
    assert(w and w.rednetId, "Worker ist nicht erreichbar")
    fleet.send(cfg, w.rednetId, {
        kind = "worker_job",
        worker = w.id,
        workerRole = w.role,
        request_id = requestId,
        job = job,
    })
end

local function dispatchRole(role, job, requestId)
    local list = getWorkersByRole(role)
    local worker = list[1]

    if not worker and cfg.autoDeploy ~= false then
        log("Kein Online-Worker fuer Rolle " .. tostring(role) .. ", starte Auto-Deploy")
        worker = deployUntilRole(role)
    end

    if not worker then error("Kein erreichbarer Worker fuer Rolle: " .. tostring(role)) end
    sendJobToWorker(worker, job, requestId)
    appendReport(requestId, "Auftrag an Arbeiter " .. tostring(worker.id) .. " gesendet", {
        worker = worker.id,
        role = worker.role,
        job = job,
    })
    return worker
end

local function makeLayerJobs(job, highestY)
    local area = fleet.normalizeArea(job.p1, job.p2)
    local layers = {}
    local startY = highestY or area.maxY
    if startY > area.maxY then startY = area.maxY end
    if startY < area.minY then return layers end
    for y = startY, area.minY, -1 do
        layers[#layers + 1] = {
            kind = "abbau",
            chest = job.chest,
            p1 = { x = area.minX, y = y, z = area.minZ },
            p2 = { x = area.maxX, y = y, z = area.maxZ },
            layerY = y,
        }
    end
    return layers
end

local function markWorkerBusy(worker, busy)
    if not worker.status then worker.status = {} end
    worker.status.busy = busy
end

local function dispatchLayerJobs(requestId)
    local active = state.activeJobs[requestId]
    if not active then return end

    local workersForRole = getWorkersByRole(active.role)
    for _, worker in ipairs(workersForRole) do
        if active.nextLayer > #active.layers then break end
        local layer = active.layers[active.nextLayer]
        active.nextLayer = active.nextLayer + 1
        active.running = active.running + 1
        markWorkerBusy(worker, true)
        sendJobToWorker(worker, layer, requestId)
        appendReport(requestId, "Schicht Y=" .. tostring(layer.layerY) .. " an Arbeiter " .. tostring(worker.id) .. " gesendet", {
            worker = worker.id,
            role = worker.role,
            layerY = layer.layerY,
            job = layer,
        })
    end
end

local function startLayeredAbbau(requestId, job, discoveredHighest)
    local role = cfg.abbauRole or "bergbau"
    if #getWorkersByRole(role) == 0 and cfg.autoDeploy ~= false then
        deployUntilRole(role)
    end

    if not discoveredHighest then
        finishReport(requestId, "empty", "Im Abbaubereich wurden keine Bloecke gefunden")
        return "empty"
    end

    local layers = makeLayerJobs(job, discoveredHighest.y)
    state.activeJobs[requestId] = {
        kind = "abbau",
        role = role,
        layers = layers,
        nextLayer = 1,
        running = 0,
    }
    appendReport(requestId, "Abbau ab gefundenem Hoechstpunkt Y=" .. tostring(discoveredHighest.y) .. " in " .. tostring(#layers) .. " Y-Schichten zerlegt", {
        discoveredHighest = discoveredHighest,
        layers = layers,
    })
    if #layers == 0 then
        finishReport(requestId, "empty", "Keine Schichten im Abbaubereich zu starten", { discoveredHighest = discoveredHighest })
        return "empty"
    end
    dispatchLayerJobs(requestId)
    if state.activeJobs[requestId].running == 0 then
        error("Kein freier Worker fuer Schicht-Abbau verfuegbar")
    end
end

local function startAbbauPrepare(requestId, job)
    local role = cfg.abbauRole or "bergbau"
    local prepareJob = {
        kind = "abbau_prepare",
        chest = job.chest,
        p1 = job.p1,
        p2 = job.p2,
    }
    local worker = dispatchRole(role, prepareJob, requestId)
    state.activeJobs[requestId] = {
        kind = "abbau_prepare",
        role = role,
        originalJob = fleet.safeCopy(job),
        prepareWorker = worker.id,
        running = 1,
        layers = {},
        nextLayer = 1,
    }
    appendReport(requestId, "Etappe 1 gestartet: Abbau-Vorbereitung", {
        worker = worker.id,
        job = prepareJob,
    })
    return worker
end

local function handlePocket(sender, msg)
    if msg.target and msg.target ~= cfg.id then return end

    if msg.command == "discover" then
        reply(sender, msg.request_id, "coordinator_discovered", { status = coordinatorStatus() })

    elseif msg.command == "status" then
        requestWorkerStatuses()
        sleep(0.5)
        reply(sender, msg.request_id, "coordinator_status", { status = coordinatorStatus() })

    elseif msg.command == "deploy" then
        local ok, err = pcall(function()
            if msg.role and msg.role ~= "all" then deployUntilRole(msg.role) else deployAll() end
        end)
        if ok then
            chat("Worker deployt")
            reply(sender, msg.request_id, "coordinator_ok", { message = "Deploy abgeschlossen", status = coordinatorStatus() })
        else
            state.lastError = tostring(err)
            reply(sender, msg.request_id, "coordinator_error", { error = tostring(err), status = coordinatorStatus() })
        end

    elseif msg.command == "stop" then
        for _, w in pairs(workers) do
            if w.rednetId then
                fleet.send(cfg, w.rednetId, { kind = "worker_abort", worker = w.id, request_id = msg.request_id })
            end
        end
        reply(sender, msg.request_id, "coordinator_ok", { message = "Abbruch an Worker gesendet" })

    elseif msg.command == "job" then
        startReport(msg.request_id, msg.job and msg.job.kind or "job", msg.job)
        local ok, resultOrErr = pcall(function()
            return dispatchRole(msg.workerRole, msg.job, msg.request_id)
        end)
        if ok then
            reply(sender, msg.request_id, "coordinator_ok", {
                message = "Job an " .. resultOrErr.id .. " gesendet",
                worker = resultOrErr.id,
                role = resultOrErr.role,
            })
        else
            finishReport(msg.request_id, "error", "Auftrag konnte nicht gestartet werden: " .. tostring(resultOrErr))
            reply(sender, msg.request_id, "coordinator_error", { error = tostring(resultOrErr) })
        end

    elseif msg.command == "abbau" then
        local job = {
            kind = "abbau",
            chest = msg.chest,
            p1 = msg.p1,
            p2 = msg.p2,
        }
        startReport(msg.request_id, "abbau", job)
        local ok, resultOrErr = pcall(function()
            ensureInitialized(deployCount())
            return startAbbauPrepare(msg.request_id, job)
        end)
        if ok then
            chat("Abbauauftrag vorbereitet: Etappe 1 gestartet")
            reply(sender, msg.request_id, "coordinator_ok", {
                message = "Abbauauftrag gestartet: Vorbereitung laeuft",
                reportId = msg.request_id,
            })
        else
            finishReport(msg.request_id, "error", "Abbauauftrag konnte nicht gestartet werden: " .. tostring(resultOrErr))
            reply(sender, msg.request_id, "coordinator_error", { error = tostring(resultOrErr) })
        end

    elseif msg.command == "craft" then
        local job = { kind = "craft", recipe = msg.recipe, count = msg.count or 1, chest = msg.chest or state.currentJobChest }
        startReport(msg.request_id, "craft", job)
        local ok, resultOrErr = pcall(function()
            return dispatchRole("handwerk", job, msg.request_id)
        end)
        if ok then
            reply(sender, msg.request_id, "coordinator_ok", {
                message = "Craftingauftrag an " .. resultOrErr.id .. " gesendet",
                worker = resultOrErr.id,
            })
        else
            finishReport(msg.request_id, "error", "Craftingauftrag konnte nicht gestartet werden: " .. tostring(resultOrErr))
            reply(sender, msg.request_id, "coordinator_error", { error = tostring(resultOrErr) })
        end

    elseif msg.command == "lager_wechsel" then
        if not state.currentReportId or not state.currentJobKind then
            reply(sender, msg.request_id, "coordinator_error", { error = "Kein aktuell koordinierter Auftrag" })
            return
        end
        local old = state.currentJobChest
        state.currentJobChest = fleet.safeCopy(msg.chest)
        local report = reports[state.currentReportId]
        if report then report.chest = fleet.safeCopy(msg.chest) end
        appendReport(state.currentReportId,
            "Lager Truhenaenderungsdiktat von " .. vecString(old) .. " nach " .. vecString(msg.chest),
            { old = old, new = msg.chest, dictatedBy = msg.from or "pocket" })
        reply(sender, msg.request_id, "coordinator_ok", {
            message = "Lager fuer aktuellen Auftrag geaendert: " .. vecString(msg.chest),
            reportId = state.currentReportId,
        })
    end
end

local function heartbeatLoop()
    while true do
        local ok, err = pcall(function()
            fleet.broadcast(cfg, { kind = "coordinator_hello", coordinator = cfg.id })
        end)
        if not ok then
            state.lastError = "Heartbeat fehlgeschlagen: " .. tostring(err)
            print("[Koordinator] " .. state.lastError)
        end
        sleep(cfg.statusInterval or 5)
    end
end

local function listenLoop()
    log("Gestartet: Gruppe=" .. cfg.group .. ", ID=" .. cfg.id)
    chat("Koordinator online")

    while true do
        local ok, err = pcall(function()
            local sender, msg = fleet.receive(cfg)
            if sender and type(msg) == "table" then
                if msg.kind == "worker_hello" or msg.kind == "worker_status" or msg.kind == "worker_progress" or msg.kind == "worker_done" or msg.kind == "worker_error" then
                    recordWorker(sender, msg)
                    if msg.kind == "worker_progress" then
                        log(msg.worker .. ": " .. tostring(msg.progress))
                        appendReport(msg.request_id, "Fortschritt " .. tostring(msg.worker) .. ": " .. tostring(msg.progress), {
                            worker = msg.worker,
                            pos = msg.pos,
                            facing = msg.facing,
                        })
                    end
                    if msg.kind == "worker_done" then
                        local active = state.activeJobs[msg.request_id]
                        if active then
                            if workers[msg.worker] then markWorkerBusy(workers[msg.worker], false) end
                            if active.kind == "abbau_prepare" then
                                active.running = math.max(0, active.running - 1)
                                local result = msg.result or {}
                                local highest = result.discoveredHighest
                                appendReport(msg.request_id, "Etappe 1 abgeschlossen", {
                                    worker = msg.worker,
                                    result = result,
                                    discoveredHighest = highest,
                                })
                                if not highest then
                                    state.activeJobs[msg.request_id] = nil
                                    finishReport(msg.request_id, "empty", "Abbaubereich ist leer", { result = result })
                                else
                                    state.activeJobs[msg.request_id] = nil
                                    startLayeredAbbau(msg.request_id, active.originalJob, highest)
                                end
                                return
                            end
                            active.running = math.max(0, active.running - 1)
                            appendReport(msg.request_id, "Arbeiter " .. tostring(msg.worker) .. " meldet Schicht fertig", {
                                worker = msg.worker,
                                status = msg.status,
                            })
                            dispatchLayerJobs(msg.request_id)
                            if active.running == 0 and active.nextLayer > #active.layers then
                                state.activeJobs[msg.request_id] = nil
                                finishReport(msg.request_id, "done", "Alle Y-Schichten abgeschlossen")
                            end
                        else
                            finishReport(msg.request_id, "done", "Arbeiter " .. tostring(msg.worker) .. " meldet fertig", {
                                worker = msg.worker,
                                status = msg.status,
                            })
                        end
                    end
                    if msg.kind == "worker_error" then
                        chat("Worker-Fehler " .. tostring(msg.worker) .. ": " .. tostring(msg.error))
                        state.activeJobs[msg.request_id] = nil
                        finishReport(msg.request_id, "error", "Arbeiter " .. tostring(msg.worker) .. " meldet Fehler: " .. tostring(msg.error), {
                            worker = msg.worker,
                            error = msg.error,
                            status = msg.status,
                        })
                    end
                elseif msg.kind == "worker_service_request" then
                    enqueueService(sender, msg)
                elseif msg.kind == "pocket_command" then
                    handlePocket(sender, msg)
                end
            end
        end)
        if not ok then
            state.lastError = "Nachrichtenverarbeitung fehlgeschlagen: " .. tostring(err)
            print("[Koordinator] " .. state.lastError)
            sleep(0.2)
        end
    end
end

parallel.waitForAny(listenLoop, heartbeatLoop, serviceLoop)
