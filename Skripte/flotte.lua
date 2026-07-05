-- flotte.lua
-- Taschencomputer-Steuerung fuer Koordinator/Worker-Flotten.

local DEFAULT_PREFIX = "teuton_fleet_v2"

local function loadPocketConfig()
    local ok, cfg = pcall(require, "fleet_pocket_config")
    if ok and type(cfg) == "table" then return cfg end
    return { group = "bergwerk_01", coordinator = "basis_01", protocolPrefix = DEFAULT_PREFIX }
end

local cfg = loadPocketConfig()
cfg.protocolPrefix = cfg.protocolPrefix or DEFAULT_PREFIX

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

local function requestId()
    return tostring(os.epoch("utc")) .. ":" .. tostring(math.random(1, 999999))
end

local function parseVec(text)
    if type(text) ~= "string" then return nil end
    local x, y, z = text:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
    if not x then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function vecString(v)
    if not v then return "?" end
    return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
end

local function protocol()
    return (cfg.protocolPrefix or DEFAULT_PREFIX) .. ":" .. cfg.group
end

local function sendCommand(command, extra)
    extra = extra or {}
    local rid = requestId()
    extra.kind = "pocket_command"
    extra.command = command
    extra.fleet = cfg.group
    extra.from = "pocket"
    extra.target = cfg.coordinator
    extra.request_id = rid

    local proto = protocol()
    local id = rednet.lookup(proto, cfg.coordinator)
    if not id then
        print("Koordinator nicht gefunden: " .. tostring(cfg.coordinator) .. " in Gruppe " .. tostring(cfg.group))
        return nil
    end

    rednet.send(id, extra, proto)

    local deadline = os.epoch("utc") + ((cfg.timeout or 8) * 1000)
    while true do
        local remaining = (deadline - os.epoch("utc")) / 1000
        if remaining <= 0 then
            print("Keine Antwort vom Koordinator.")
            return nil
        end
        local sender, msg = rednet.receive(proto, remaining)
        if sender == id and type(msg) == "table" and msg.request_id == rid and msg.fleet == cfg.group then
            return msg
        end
    end
end

local function printNeeds(needs)
    needs = needs or {}

    local printed = false
    if needs.items then
        for item, count in pairs(needs.items) do
            if not printed then print("Bedarf:") printed = true end
            print("  Item: " .. item .. " x" .. tostring(count))
        end
    end

    if needs.recipes then
        for _, r in ipairs(needs.recipes) do
            if not printed then print("Bedarf:") printed = true end
            if type(r) == "table" then
                print("  Rezept: " .. tostring(r.recipe) .. " fuer " .. tostring(r.worker))
            else
                print("  Rezept: " .. tostring(r))
            end
        end
    end

    if needs.warnings then
        for _, w in ipairs(needs.warnings) do
            if not printed then print("Bedarf:") printed = true end
            print("  Hinweis: " .. tostring(w))
        end
    end
end

local function printStatus(status)
    if not status then print("Kein Status.") return end
    print("Koordinator: " .. tostring(status.id))
    print("Gruppe: " .. tostring(status.group))
    print("Status: " .. tostring(status.progress))
    if status.currentJobKind then print("Aktueller Auftrag: " .. tostring(status.currentJobKind) .. " | Bericht: " .. tostring(status.currentReportId)) end
    if status.currentJobChest then print("Job-Truhe: " .. vecString(status.currentJobChest)) end
    if status.queuedServiceRequests then print("Service-Warteschlange: " .. tostring(status.queuedServiceRequests)) end
    print("Depotseite: " .. tostring(status.chestSide) .. " | Deployseite: " .. tostring(status.deploySide))
    if status.initStatus then
        local init = status.initStatus
        print("Init: " .. (init.initialized and "initialisiert" or "offen") ..
            " | geplant " .. tostring(init.plannedWorkers) ..
            " | online " .. tostring(init.onlineWorkers) ..
            " | fehlend " .. tostring(init.missingWorkers) ..
            " | Fuel-Reserve " .. tostring(init.fuelReserve))
        for _, slot in ipairs(init.formationSlots or {}) do
            print("  Slot " .. tostring(slot.label or slot.index) ..
                " | Reihe " .. tostring(slot.row) ..
                " | Seite " .. tostring(slot.side) ..
                " | " .. (slot.occupied and "belegt" or "offen"))
        end
    end
    if status.lastError then print("Letzter Fehler: " .. tostring(status.lastError)) end
    print("")
    print("Worker:")

    for _, w in ipairs(status.workers or {}) do
        local s = w.status or {}
        local line = "- " .. tostring(w.id) .. " [" .. tostring(w.role) .. "]"
        line = line .. " | " .. (w.online and "online" or "offline")
        if s.busy ~= nil then line = line .. " | " .. (s.busy and "arbeitet" or "frei") end
        if s.progress then line = line .. " | " .. tostring(s.progress) end
        if s.fuel then line = line .. " | Fuel " .. tostring(s.fuel) end
        if s.freeSlots then line = line .. " | frei " .. tostring(s.freeSlots) .. "/16" end
        if s.pos then line = line .. " | Pos " .. vecString(s.pos) end
        print(line)
        if s.lastError then print("    Fehler: " .. tostring(s.lastError)) end
    end

    print("")
    printNeeds(status.needs)
end

local function usage()
    print("flotte - Taschencomputer fuer Turtle-Flotten")
    print("")
    print("Optionen:")
    print("  --gruppe <id>       Arbeitsgruppe ueberschreiben")
    print("  --basis <id>        Koordinator-ID ueberschreiben")
    print("")
    print("Befehle:")
    print("  flotte list")
    print("  flotte status")
    print("  flotte deploy [all|rolle]")
    print("  flotte stop")
    print("  flotte abbau <truhe:x,y,z> <punkt1:x,y,z> <punkt2:x,y,z>")
    print("  flotte abbau lager <truhe:x,y,z> von <punkt1:x,y,z> bis <punkt2:x,y,z>")
    print("  flotte lager_wechsel <truhe:x,y,z>")
    print("  flotte craft <rezept> [anzahl]")
    print("  flotte job <rolle> <kind> <truhe:x,y,z> <punkt1:x,y,z> <punkt2:x,y,z>")
    print("")
    print("Beispiele:")
    print("  flotte status")
    print("  flotte deploy all")
    print("  flotte abbau 100,64,200 90,67,190 110,80,210")
    print("  flotte lager_wechsel 105,64,205")
    print("  flotte job graben graben 100,64,200 90,67,190 110,80,210")
    print("  flotte craft minecraft:diamond_pickaxe 1")
end

local function parseOptions(args)
    local out = {}
    local i = 1
    while i <= #args do
        if args[i] == "--gruppe" then
            cfg.group = args[i + 1]
            i = i + 2
        elseif args[i] == "--basis" then
            cfg.coordinator = args[i + 1]
            i = i + 2
        else
            out[#out + 1] = args[i]
            i = i + 1
        end
    end
    return out
end

local args = parseOptions({ ... })
local cmd = args[1]

if not cmd or cmd == "help" then usage(); return end

openRednet()

if cmd == "list" then
    local proto = protocol()
    local rid = requestId()
    rednet.broadcast({
        kind = "pocket_command",
        command = "discover",
        fleet = cfg.group,
        target = nil,
        request_id = rid,
        from = "pocket",
    }, proto)

    print("Koordinatoren in Gruppe " .. tostring(cfg.group) .. ":")
    local deadline = os.epoch("utc") + 2500
    local count = 0
    while true do
        local rem = (deadline - os.epoch("utc")) / 1000
        if rem <= 0 then break end
        local sender, msg = rednet.receive(proto, rem)
        if type(msg) == "table" and msg.request_id == rid and msg.kind == "coordinator_discovered" then
            count = count + 1
            print("- " .. tostring(msg.coordinator) .. " | rednet " .. tostring(sender))
        end
    end
    if count == 0 then print("Keine gefunden.") end

elseif cmd == "status" then
    local msg = sendCommand("status")
    if msg then printStatus(msg.status) end

elseif cmd == "deploy" then
    local role = args[2] or "all"
    local msg = sendCommand("deploy", { role = role })
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end

elseif cmd == "stop" then
    local msg = sendCommand("stop")
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end

elseif cmd == "abbau" then
    local chest, p1, p2
    if args[2] == "lager" and args[4] == "von" and args[6] == "bis" then
        chest = parseVec(args[3])
        p1 = parseVec(args[5])
        p2 = parseVec(args[7])
    else
        chest = parseVec(args[2])
        p1 = parseVec(args[3])
        p2 = parseVec(args[4])
    end
    if not chest or not p1 or not p2 then usage(); return end
    local msg = sendCommand("abbau", { chest = chest, p1 = p1, p2 = p2 })
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end

elseif cmd == "lager_wechsel" then
    local chest = parseVec(args[2])
    if not chest then usage(); return end
    local msg = sendCommand("lager_wechsel", { chest = chest })
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end

elseif cmd == "craft" then
    local recipe = args[2]
    local count = tonumber(args[3]) or 1
    if not recipe then usage(); return end
    local msg = sendCommand("craft", { recipe = recipe, count = count })
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end

elseif cmd == "job" then
    local role = args[2]
    local kind = args[3]
    local chest = parseVec(args[4])
    local p1 = parseVec(args[5])
    local p2 = parseVec(args[6])
    if not role or not kind or not chest or not p1 or not p2 then usage(); return end

    local msg = sendCommand("job", {
        workerRole = role,
        job = { kind = kind, chest = chest, p1 = p1, p2 = p2 },
    })
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end
else
    usage()
end
