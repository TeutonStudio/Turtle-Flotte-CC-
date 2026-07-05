-- flotte.lua
-- Taschencomputer-Steuerung fuer Teuton-Fleet v5.

local DEFAULT_PREFIX = "teuton_fleet_v2"

local function loadPocketConfig()
    local ok, cfg = pcall(require, "fleet_pocket_config")
    if ok and type(cfg) == "table" then return cfg end
    return { group = "bergwerk_01", coordinator = "basis_01", protocolPrefix = DEFAULT_PREFIX, timeout = 60 }
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

local function protocolName()
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

    local proto = protocolName()
    local id = rednet.lookup(proto, cfg.coordinator)
    if not id then print("Koordinator nicht gefunden: " .. tostring(cfg.coordinator)); return nil end
    rednet.send(id, extra, proto)

    local deadline = os.epoch("utc") + ((cfg.timeout or 60) * 1000)
    while true do
        local remaining = (deadline - os.epoch("utc")) / 1000
        if remaining <= 0 then print("Keine Antwort vom Koordinator."); return nil end
        local sender, msg = rednet.receive(proto, remaining)
        if sender == id and type(msg) == "table" and msg.request_id == rid and msg.fleet == cfg.group then return msg end
    end
end

local function printQueue(name, list)
    print(name .. ": " .. tostring(#(list or {})))
    for _, task in ipairs(list or {}) do
        print("  - " .. tostring(task.id) .. " | " .. tostring(task.kind) .. " | " .. tostring(task.status))
    end
end

local function printStatus(status)
    if not status then print("Kein Status.") return end
    print("Koordinator: " .. tostring(status.id))
    print("Gruppe: " .. tostring(status.group))
    print("Status: " .. tostring(status.status))
    print("Nav: " .. tostring(status.navReady) .. (status.navError and (" | " .. tostring(status.navError)) or ""))
    if status.currentCommand then print("Aktueller Befehl: " .. tostring(status.currentCommand.kind) .. " | " .. tostring(status.currentCommand.id)) end
    if status.currentReport then print("Aktueller Report: " .. tostring(status.currentReport)) end
    if status.warnings and #status.warnings > 0 then
        print("Warnungen:")
        for _, warning in ipairs(status.warnings) do
            print("  - " .. tostring(warning.text))
        end
    end
    printQueue("CommandQueue", status.commandQueue)
    printQueue("SubtaskQueue", status.subtaskQueue)
    print("Worker:")
    for _, w in ipairs(status.workers or {}) do
        local s = w.status or {}
        local eq = s.equipment or {}
        local line = "- " .. tostring(w.id) .. " [" .. tostring(w.profession) .. "]"
        line = line .. " | Quelle " .. tostring(s.professionSource or w.professionSource)
        line = line .. " | Tool " .. tostring(s.toolSide)
        line = line .. " | Fuel " .. tostring(s.fuel)
        line = line .. " | frei " .. tostring(s.freeSlots)
        line = line .. " | Pos " .. vecString(s.pos)
        line = line .. " | Facing " .. tostring(s.facing)
        line = line .. " | Nav " .. tostring(s.navReady)
        line = line .. " | Task " .. tostring(w.currentTask and w.currentTask.id or "frei")
        print(line)
        print("    Equipment L=" .. tostring(eq.left and eq.left.name) .. " R=" .. tostring(eq.right and eq.right.name))
        for _, warn in ipairs(s.warnings or {}) do print("    Warnung: " .. tostring(warn)) end
        if s.navError then print("    Nav-Fehler: " .. tostring(s.navError)) end
    end
end

local function usage()
    print("flotte v5")
    print("  flotte list")
    print("  flotte status")
    print("  flotte abbau <lager:x,y,z> <von:x,y,z> <bis:x,y,z>")
    print("  flotte abbau lager <lager:x,y,z> von <von:x,y,z> bis <bis:x,y,z>")
    print("  flotte stop")
    print("  flotte standby")
end

local function parseOptions(args)
    local out = {}
    local i = 1
    while i <= #args do
        if args[i] == "--gruppe" then cfg.group = args[i + 1]; i = i + 2
        elseif args[i] == "--basis" then cfg.coordinator = args[i + 1]; i = i + 2
        else out[#out + 1] = args[i]; i = i + 1 end
    end
    return out
end

local args = parseOptions({ ... })
local cmd = args[1]
if not cmd or cmd == "help" then usage(); return end

openRednet()

if cmd == "list" then
    local proto = protocolName()
    local rid = requestId()
    rednet.broadcast({ kind = "pocket_command", command = "discover", fleet = cfg.group, request_id = rid, from = "pocket" }, proto)
    local deadline = os.epoch("utc") + 2500
    while true do
        local rem = (deadline - os.epoch("utc")) / 1000
        if rem <= 0 then break end
        local sender, msg = rednet.receive(proto, rem)
        if type(msg) == "table" and msg.request_id == rid then print("- " .. tostring(msg.coordinator or msg.from) .. " | rednet " .. tostring(sender)) end
    end
elseif cmd == "status" then
    local msg = sendCommand("status")
    if msg then printStatus(msg.status) end
elseif cmd == "abbau" then
    local chest, p1, p2
    if args[2] == "lager" and args[4] == "von" and args[6] == "bis" then
        chest = parseVec(args[3]); p1 = parseVec(args[5]); p2 = parseVec(args[7])
    else
        chest = parseVec(args[2]); p1 = parseVec(args[3]); p2 = parseVec(args[4])
    end
    if not chest or not p1 or not p2 then usage(); return end
    local msg = sendCommand("abbau", { chest = chest, p1 = p1, p2 = p2 })
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end
elseif cmd == "stop" then
    local msg = sendCommand("stop")
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end
elseif cmd == "standby" then
    local msg = sendCommand("standby")
    if msg then print(tostring(msg.message or msg.error or msg.kind)) end
else
    usage()
end
