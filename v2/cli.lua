local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local CLI={}
function CLI.parse(args)
  local p={}
  for i=2,#args do
    local k,v=args[i]:match('^([^:]+):(.+)$')
    if not k then return nil,'Argument erwartet name:wert, erhalten: '..args[i] end
    p[k]=v
  end
  return p
end
local function showStatus(s)
  print('Verwalter '..s.manager..' | '..s.phase..(s.control and ' | '..s.control or ''))
  print('Position: '..(s.position and U.key(s.position) or 'unbekannt')..' | Warteschlange: '..s.queued)
  if s.blocked then print('WARTET: '..s.blocked) end
  if s.currentJob then
    local j=s.currentJob
    print('Auftrag '..j.id..' ('..j.kind..'): '..(j.doneCount or j.crafted or 0)..'/'..(j.total or j.batches or 0))
    if j.blocked then print('Auftrag wartet: '..j.blocked) end
  end
  for _,w in ipairs(s.workers) do
    print('Arbeiter '..w.id..' '..w.role..' '..(w.stored and 'eingelagert' or w.online and w.status or 'KEIN KONTAKT')..' Kohle: '..tostring(w.fuel))
    if w.issue then print('  '..w.issue) end
  end
  if s.delivery then print('Versorgung: '..s.delivery.action..' -> '..s.delivery.worker..' ('..s.delivery.phase..')') end
end
function CLI.run(config,net,args)
  local cmd=args[1]
  if not cmd then
    print('flotte list | status | bericht id:<job>')
    print('flotte abbau|erdarbeiten|holz von:x,y,z bis:x,y,z')
    print('flotte craft rezept:<name> menge:<anzahl>')
    print('flotte rezepte [name:<name> datei:<rezept.json>]')
    print('flotte pause | weiter [pruefen:ja] | abbrechen')
    print('flotte einrichten (lokal auf dem jeweiligen Geraet)')
    return true
  end
  local p,e=CLI.parse(args); if not p then print(e); return false end
  if cmd=='rezepte' and p.datei then
    local raw=U.read(p.datei); if not raw then print('Rezeptdatei fehlt'); return false end
    local ok,recipe=pcall(textutils.unserializeJSON,raw)
    if not ok then print('Rezeptdatei ist kein JSON'); return false end
    p.recipe=recipe
  end
  local target=tonumber(p.id) or config.manager
  if cmd=='bericht' then target=config.manager end
  if cmd=='list' then
    local ids={rednet.lookup('flotte_v2')}; local seen={}
    if config.manager then ids[#ids+1]=config.manager end
    for _,id in ipairs(ids) do if not seen[id] then
      seen[id]=true
      local ok,s=net:rpc(id,'COMMAND',{cmd='status',args={}},5)
      if ok then showStatus(s) end
    end end
    if not next(seen) then print('Kein Verwalter gefunden') end
    return true
  end
  if not target then print('Verwalter-ID fehlt; flotte einrichten ausfuehren'); return false end
  local ok,r,why=net:rpc(target,'COMMAND',{cmd=cmd,args=p},16)
  if not ok then print('Fehler: '..tostring(why)); return false end
  if cmd=='status' or cmd=='pause' or cmd=='weiter' or cmd=='abbrechen' then showStatus(r)
  elseif r.jobId then print('Auftrag angelegt: '..r.jobId)
  else print(textutils.serialize(r)) end
  return true
end
return CLI
