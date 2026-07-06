-- Zweck: Token-basierter CLI-Parser fuer flotte-Befehle auf Taschencomputern.
-- Erwartet: common/protocol.lua, common/vec3.lua.

local protocol = dofile("common/protocol.lua")
local vec3 = dofile("common/vec3.lua")

local cli = {}
cli.RESPONSE_WINDOW = 1.5

local function usage()
  print("flotte list")
  print("flotte status id:<koordId>")
  print("flotte bericht id:<jobId> [--voll]")
  print("flotte abbau id:<koordId> lager:x,y,z von:x,y,z bis:x,y,z")
end

local function parseArgs(args)
  local out = { flags = {} }
  for _, token in ipairs(args) do
    if string.sub(token, 1, 2) == "--" then
      out.flags[string.sub(token, 3)] = true
    else
      local k, v = string.match(token, "^([^:]+):(.+)$")
      if k then out[k] = v end
    end
  end
  return out
end

local function expectVec(parsed, key)
  local v, err = vec3.parse(parsed[key])
  if not v then return nil, key .. ": " .. err end
  return v
end

local function waitResponse()
  local _, msg = protocol.receive(5, function(m) return m.type == protocol.RESPONSE end)
  if not msg then print("Keine Antwort."); return nil end
  if not msg.payload.ok then print("Fehler: " .. tostring(msg.payload.error)); return nil end
  return msg.payload.data
end

local function printStatus(data)
  print("Koordinator: " .. tostring(data.koordinatorId) .. " Phase: " .. tostring(data.phase))
  if data.currentJob then print("Job: " .. data.currentJob.id .. " (" .. data.currentJob.status .. ")") else print("Job: keiner") end
  print("Queue: " .. tostring(data.queued))
  for _, w in ipairs(data.workers or {}) do
    print("Worker " .. tostring(w.id) .. " " .. tostring(w.beruf) .. " " .. tostring(w.status))
  end
end

function cli.list()
  protocol.broadcast(protocol.CMD_LIST, {})
  local untilTime = os.clock() + cli.RESPONSE_WINDOW
  local found = 0
  while os.clock() < untilTime do
    local _, msg = protocol.receive(math.max(0.1, untilTime - os.clock()), function(m) return m.type == protocol.RESPONSE end)
    if msg and msg.payload and msg.payload.ok then
      found = found + 1
      local data = msg.payload.data or {}
      printStatus(data)
    end
  end
  if found == 0 then print("Keine Koordinatoren gefunden.") end
end

function cli.status(parsed)
  local id = tonumber(parsed.id)
  if not id then print("id:<koordId> fehlt"); return end
  protocol.send(id, protocol.CMD_STATUS, {})
  local data = waitResponse()
  if data then printStatus(data) end
end

local function coordinatorFromJobId(jobId)
  local id = string.match(tostring(jobId or ""), "^(%d+)%-")
  return tonumber(id)
end

function cli.bericht(parsed)
  if not parsed.id then print("id:<jobId> fehlt"); return end
  local koord = coordinatorFromJobId(parsed.id)
  if not koord then print("Koordinator-ID nicht aus jobId lesbar"); return end
  protocol.send(koord, protocol.CMD_BERICHT, { jobId = parsed.id, voll = parsed.flags.voll })
  local data = waitResponse()
  if not data then return end
  print("Bericht " .. tostring(data.jobId) .. " Status: " .. tostring(data.status))
  if data.zusammenfassung then
    print("Gesamt " .. data.zusammenfassung.gesamt .. ", fertig " .. data.zusammenfassung.fertig .. ", Fehler " .. data.zusammenfassung.fehler .. ", offen " .. data.zusammenfassung.offen)
  end
  if parsed.flags.voll and data.subtasks then
    for _, task in ipairs(data.subtasks) do print(task.id .. " " .. task.status) end
  end
end

function cli.abbau(parsed)
  local id = tonumber(parsed.id)
  if not id then print("id:<koordId> fehlt"); return end
  local lager, e1 = expectVec(parsed, "lager")
  local von, e2 = expectVec(parsed, "von")
  local bis, e3 = expectVec(parsed, "bis")
  if not lager or not von or not bis then print(e1 or e2 or e3); return end
  protocol.send(id, protocol.CMD_ABBAU, { lager = lager, von = von, bis = bis })
  local data = waitResponse()
  if data then print("Job angelegt: " .. tostring(data.jobId) .. " (" .. tostring(data.subtasks) .. " Layer)") end
end

function cli.run(args)
  if #args == 0 or args[1] ~= "flotte" then usage(); return false end
  local cmd = args[2]
  local rest = {}
  for i = 3, #args do rest[#rest + 1] = args[i] end
  local parsed = parseArgs(rest)
  if cmd == "list" then cli.list()
  elseif cmd == "status" then cli.status(parsed)
  elseif cmd == "bericht" then cli.bericht(parsed)
  elseif cmd == "abbau" then cli.abbau(parsed)
  else usage(); return false end
  return true
end

return cli
