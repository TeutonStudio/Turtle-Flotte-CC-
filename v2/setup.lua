local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local C={PATH='.flotte/config'}
function C.save(c)
  local S=U.load('store'); local journal=S.open(C.PATH..'.journal',{})
  journal.data=c; journal:save()
  U.write(C.PATH..'.new',textutils.serialize(c))
  if fs.exists(C.PATH..'.bak') then fs.delete(C.PATH..'.bak') end
  if fs.exists(C.PATH) then fs.move(C.PATH,C.PATH..'.bak') end
  fs.move(C.PATH..'.new',C.PATH)
end
function C.read()
  local raw=U.read(C.PATH)
  if not raw then
    if fs.exists(C.PATH..'.journal') or fs.exists(C.PATH..'.journal.next') or fs.exists(C.PATH..'.journal.bak') then
      return U.load('store').open(C.PATH..'.journal',{}).data
    end
    return nil
  end
  local ok,c=pcall(textutils.unserialize,raw)
  if not ok or type(c)~='table' then
    if fs.exists(C.PATH..'.journal') then return U.load('store').open(C.PATH..'.journal',{}).data end
    error('Konfiguration unlesbar: '..C.PATH)
  end
  return c
end
local function ask(label,default)
  write(label..(default and ' ['..tostring(default)..']' or '')..': ')
  local s=read(); if s=='' then return default end; return s
end
local function position(label,default)
  while true do
    local p=U.pos(ask(label,default and U.key(default)))
    if p then return p end; print('Format: x,y,z (ganzzahlig)')
  end
end
local function heading(default)
  while true do local h=U.heading(ask('Blickrichtung north/east/south/west',default)); if h then return h end end
end
local function dock(label)
  print(label..': Turtle-Standplatz, NICHT Truhenposition.')
  local d={pos=position('Standplatz'),heading=heading('north')}
  repeat d.side=ask('Uebergaberichtung front/up/down','down') until d.side=='front' or d.side=='up' or d.side=='down'
  return d
end
function C.validate(c)
  if type(c)~='table' or type(c.fleet)~='string' or c.fleet=='' or #c.fleet>64 then return false,'Flottenkennung fehlt' end
  if c.role=='taschencomputer' then return type(c.manager)=='number','Verwalter-ID fehlt' end
  if c.role=='arbeiter' then return type(c.manager)=='number' and c.manager>=0,'Verwalter-ID fehlt' end
  if c.role~='koordinator' then return false,'Rolle ungueltig' end
  if not U.pos(c.base) or not U.heading(c.heading) or type(c.parks)~='table' or #c.parks<1 then return false,'Basis/Blickrichtung/Parkplaetze fehlen' end
  local protected={}
  for _,name in ipairs({'start','coal','output','deploy'}) do
    local d=c[name]
    if type(d)~='table' or not U.pos(d.pos) or not U.heading(d.heading) or (d.side~='front' and d.side~='up' and d.side~='down') then return false,'Ungueltiger Dock: '..name end
    if name~='deploy' then
      local delta=d.side=='front' and U.dirs[d.heading] or d.side=='up' and U.dirs[5] or U.dirs[6]
      protected[U.key(U.add(d.pos,delta))]=true
    end
  end
  if c.deploy.side~='front' then return false,'Aussetzplatz muss front verwenden' end
  local parks={}
  for _,p in ipairs(c.parks) do
    if not U.pos(p) or protected[U.key(p)] or parks[U.key(p)] then return false,'Ungueltiger oder doppelter Parkplatz' end
    parks[U.key(p)]=true
  end
  for name,source in pairs(c.materials or {}) do
    if type(name)~='string' or type(source)~='table' or not U.pos(source.pos) or not U.heading(source.heading) or (source.side~='front' and source.side~='up' and source.side~='down') then return false,'Ungueltige Materialquelle: '..tostring(name) end
    local delta=source.side=='front' and U.dirs[source.heading] or source.side=='up' and U.dirs[5] or U.dirs[6]
    protected[U.key(U.add(source.pos,delta))]=true
  end
  for _,p in ipairs(c.parks) do
    if protected[U.key(p)] or U.eq(p,c.base) or U.eq(p,c.deploy.pos) or U.eq(p,U.add(c.deploy.pos,U.dirs[c.deploy.heading])) then return false,'Parkplatz blockiert Basis oder Aussetzplatz' end
    for _,name in ipairs({'start','coal','output'}) do if U.eq(p,c[name].pos) then return false,'Parkplatz blockiert Truhenstandplatz' end end
    for _,source in pairs(c.materials or {}) do if U.eq(p,source.pos) then return false,'Parkplatz blockiert Materialquelle' end end
  end
  c.recipes=c.recipes or {}; c.materials=c.materials or {}; c.blockRoles=c.blockRoles or {}
  for name,role in pairs(c.blockRoles) do
    if type(name)~='string' or (role~='spitzhacke' and role~='schaufel' and role~='axt') then return false,'Ungueltige Materialzuordnung: '..tostring(name) end
  end
  c.protected=protected
  return true
end
function C.run(role)
  assert(role~='koordinator' or not turtle or turtle.getFuelLevel()=='unlimited' or turtle.getFuelLevel()>0,'Verwalter vor Einrichtung mit etwas Kohle manuell tanken')
  local c={version=2,role=role,fleet=ask('Flottenkennung','flotte'),recipes={},materials={},blockRoles={}}
  if role~='koordinator' then c.manager=tonumber(ask('Computer-ID des Verwalters'))
  else
    local x,y,z=gps.locate(2)
    assert(x,'GPS nicht verfuegbar')
    c.base=position('Basisposition',{x=x,y=y,z=z}); c.heading=heading('north')
    print('Vor der Basis muss ein freier Block zur Richtungskalibrierung liegen.')
    c.start=dock('Starttruhe'); c.coal=dock('Kohletruhe'); c.output=dock('Ergebnislager')
    c.deploy=dock('Aussetzplatz (vor der Turtle; side=front)')
    c.parks={}
    local n=tonumber(ask('Anzahl Arbeiter/Parkplaetze','3'))
    assert(n and n>=1 and n<=8 and n%1==0,'1..8 Arbeiter erlaubt')
    for i=1,n do c.parks[i]=position('Parkplatz '..i) end
    local sources=tonumber(ask('Anzahl sortenreiner Zutatenquellen','0'))
    assert(sources and sources>=0 and sources<=64 and sources%1==0,'0..64 Quellen erlaubt')
    for _=1,sources do local item=ask('Item-ID'); c.materials[item]=dock('Quelle fuer '..item) end
  end
  local ok,e=C.validate(c); assert(ok,e)
  C.save(c)
  print('Einrichtung gespeichert. Programm neu starten. Verwalter-ID: '..os.getComputerID())
  return c
end
return C
