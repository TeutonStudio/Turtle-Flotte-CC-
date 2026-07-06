-- Zweck: Rednet-Protokoll, Nachrichtentypen und sichere send/receive Wrapper.
-- Erwartet: CC:Tweaked APIs rednet, peripheral, textutils, os.

local function loadUtil()
  if fs and fs.exists and fs.exists("common/util.lua") then
    return dofile("common/util.lua")
  end
  return dofile("Flotte/common/util.lua")
end

local util = loadUtil()

local protocol = {}
protocol.NAME = "flotte_v1"

protocol.CMD_LIST = "CMD_LIST"
protocol.CMD_STATUS = "CMD_STATUS"
protocol.CMD_ABBAU = "CMD_ABBAU"
protocol.CMD_BERICHT = "CMD_BERICHT"
protocol.RESPONSE = "RESPONSE"
protocol.WORKER_REGISTER = "WORKER_REGISTER"
protocol.WORKER_STATUS = "WORKER_STATUS"
protocol.WORKER_PROBLEM = "WORKER_PROBLEM"
protocol.TASK_DONE = "TASK_DONE"
protocol.TASK_FAILED = "TASK_FAILED"
protocol.READY_AT_DOCK = "READY_AT_DOCK"
protocol.TASK_ASSIGN = "TASK_ASSIGN"
protocol.REFUEL = "REFUEL"
protocol.RETURN_TO_STORAGE = "RETURN_TO_STORAGE"
protocol.RETURN_TO_DOCK = "RETURN_TO_DOCK"

local function openAnyModem()
  if not peripheral or not rednet then return false, "Rednet/Peripheral API fehlt" end
  if rednet.isOpen and rednet.isOpen() then return true end
  local names = peripheral.getNames and peripheral.getNames() or {}
  for _, name in ipairs(names) do
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)
      if modem and (not modem.isWireless or modem.isWireless()) then
        local ok = pcall(rednet.open, name)
        if ok and rednet.isOpen(name) then return true, name end
      end
    end
  end
  return false, "Kein offenes Modem gefunden"
end

local function isValid(msg)
  return type(msg) == "table"
    and type(msg.type) == "string"
    and type(msg.from) == "number"
    and type(msg.msgId) == "string"
    and type(msg.payload) == "table"
    and type(msg.ts) == "number"
end

function protocol.ensureOpen()
  return openAnyModem()
end

function protocol.wrap(kind, payload)
  return {
    type = kind,
    from = util.computerId(),
    msgId = util.newId(util.computerId()),
    payload = payload or {},
    ts = util.now(),
  }
end

function protocol.send(targetId, kind, payload)
  local okOpen, err = openAnyModem()
  if not okOpen then return false, err end
  targetId = tonumber(targetId)
  if not targetId then return false, "Ungueltige Ziel-ID" end
  local msg = protocol.wrap(kind, payload)
  local encoded = textutils.serialize(msg)
  local ok, sendErr = pcall(rednet.send, tonumber(targetId), encoded, protocol.NAME)
  if not ok then return false, sendErr end
  return true, msg.msgId
end

function protocol.broadcast(kind, payload)
  local okOpen, err = openAnyModem()
  if not okOpen then return false, err end
  local msg = protocol.wrap(kind, payload)
  local encoded = textutils.serialize(msg)
  local ok, sendErr = pcall(rednet.broadcast, encoded, protocol.NAME)
  if not ok then return false, sendErr end
  return true, msg.msgId
end

function protocol.decode(raw)
  local msg = raw
  if type(raw) == "string" then
    local ok, decoded = pcall(textutils.unserialize, raw)
    if not ok then return nil, "Paket nicht lesbar" end
    msg = decoded
  end
  if not isValid(msg) then return nil, "Fremdes oder ungueltiges Paket" end
  return msg
end

function protocol.receive(timeout, filterFn)
  local okOpen, err = openAnyModem()
  if not okOpen then return nil, nil, err end
  local deadline = nil
  if timeout then deadline = os.clock() + timeout end
  while true do
    local wait = timeout
    if deadline then
      wait = deadline - os.clock()
      if wait <= 0 then return nil, nil, "timeout" end
    end
    local ok, sender, raw = pcall(rednet.receive, protocol.NAME, wait)
    if not ok then return nil, nil, sender end
    if sender == nil then return nil, nil, "timeout" end
    local msg = protocol.decode(raw)
    if msg and (not filterFn or filterFn(msg, sender)) then
      return sender, msg
    end
  end
end

return protocol
