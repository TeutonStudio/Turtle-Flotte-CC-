local running=shell.getRunningProgram()
FLOTTE_ROOT=fs.getDir(fs.getDir(running))
if FLOTTE_ROOT~='' then FLOTTE_ROOT=FLOTTE_ROOT..'/' end
local U=dofile(FLOTTE_ROOT..'v2/util.lua')
local C,S,N=U.load('setup'),U.load('store'),U.load('net')
local args={...}
local role=U.read('.flotte/role')
if args[1]=='--role' then role=args[2]; table.remove(args,1); table.remove(args,1) end
local config=C.read()
role=role or (config and config.role)
if not role then error('Zuerst init.lua installieren oder --role koordinator|arbeiter|taschencomputer angeben') end
if args[1]=='einrichten' or not config then
  if fs.exists('.flotte/state') and args[1]=='einrichten' then
    local old=S.open('.flotte/state',{})
    local m=old.data.manager
    assert(not old.data.worker or not old.data.worker.task and not old.data.worker.service,'Arbeiter hat noch eine Aufgabe oder Uebergabe')
    if m and (m.active or next(m.queue or {}) or next(m.cargo or {})) then error('Vor Neueinrichtung Auftrag abschliessen/abbrechen und Transporte einlagern') end
    if m then for _,w in pairs(m.workers or {}) do assert(w.stored,'Vor Neueinrichtung alle Arbeiter einsammeln') end end
  end
  C.run(role); return
end
local valid,e=C.validate(config); assert(valid,e)
assert(config.role==role,'Installierte Rolle und Konfiguration passen nicht zusammen')
local store=S.open('.flotte/state',{version=2})
assert(store.data.version==2,'v1-Zustand wird nicht automatisch uebernommen')
local net=N.open(store,config.fleet)
if role=='taschencomputer' or #args>0 then
  if role=='koordinator' then config.manager=os.getComputerID() end
  net.handler=function() return false,nil,'Dieses Geraet ist eine Bedienkonsole' end
  local result
  parallel.waitForAny(function() net:run() end,function() result=U.load('cli').run(config,net,args) end)
  return result
end
assert(turtle,'Diese Rolle benoetigt eine Turtle')
assert(os.getComputerLabel(),'Turtle muss beschriftet sein: label set <name>')
local actor=U.load(role=='koordinator' and 'coordinator' or 'worker').new(config,store,net)
print('Flotte v2 | '..role..' | ID '..os.getComputerID())
if role=='arbeiter' then
  parallel.waitForAny(function() net:run() end,function() actor:main() end,function() actor:heartbeat() end)
else parallel.waitForAny(function() net:run() end,function() actor:main() end) end
