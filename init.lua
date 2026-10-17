-- Standalone installer. Every download is pinned to one resolved Git commit.
local BASE='https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/'
local API='https://api.github.com/repos/TeutonStudio/Turtle-Flotte-CC-/commits/'
local requestedRef=({...})[1]
local function readFile(p)
  if not fs.exists(p) then return nil end
  local h=assert(fs.open(p,'r')); local s=h.readAll(); h.close(); return s
end
local function writeFile(p,s)
  local dir=fs.getDir(p); if dir~='' then fs.makeDir(dir) end
  local h=assert(fs.open(p,'w'),'Nicht schreibbar: '..p); h.write(s); h.close()
end
local function get(url)
  local h,e=http.get(url)
  assert(h,'Download fehlgeschlagen: '..url..' ('..tostring(e)..')')
  local data=h.readAll(); h.close(); return data
end
local function checksum(s)
  local h=1; for i=1,#s do h=(h*31+s:byte(i))%2147483647 end; return h
end
local function switch(path,s)
  writeFile(path..'.new',s)
  if fs.exists(path..'.bak') then fs.delete(path..'.bak') end
  if fs.exists(path) then fs.move(path,path..'.bak') end
  fs.move(path..'.new',path)
end
local function install()
  assert(http and http.get,'HTTP muss aktiviert sein')
  local ref=requestedRef or readFile('.flotte/source') or 'master'
  assert(ref:match('^[%w%._/%-]+$'),'Ungueltiger Git-Ref')
  local commit=textutils.unserializeJSON(get(API..ref:gsub('/','%%2F'))).sha
  assert(type(commit)=='string' and #commit==40 and commit:match('^%x+$'),'GitHub lieferte keinen gueltigen Commit')
  local manifest=textutils.unserializeJSON(get(BASE..commit..'/manifest.json'))
  assert(manifest.format==2 and type(manifest.files)=='table' and type(manifest.version)=='string' and manifest.version:match('^2%.%d+%.%d+$'),'Kein unterstuetztes v2-Manifest')
  local role=readFile('.flotte/role')
  if not role then
    print('[1] Taschencomputer  [2] Koordinator  [3] Arbeiter')
    write('Rolle: '); role=({['1']='taschencomputer',['2']='koordinator',['3']='arbeiter'})[read()]
  end
  assert(role=='koordinator' or role=='arbeiter' or role=='taschencomputer','Ungueltige Rolle')
  local newest,sequence=nil,-1
  for _,suffix in ipairs({'','.next','.bak'}) do
    local raw=readFile('.flotte/state'..suffix)
    if raw then
      local env=textutils.unserialize(raw)
      if env and type(env.body)=='string' and type(env.seq)=='number' and checksum(env.body)==env.check then
        local data=textutils.unserialize(env.body)
        if data and env.seq>sequence then newest,sequence=data,env.seq end
      end
    end
  end
  if fs.exists('.flotte/state') or fs.exists('.flotte/state.next') or fs.exists('.flotte/state.bak') then assert(newest,'Zustand unlesbar; Update abgebrochen') end
  if newest then
    assert(newest.version==2,'Unbekanntes Zustandsformat')
    assert(not newest.intent,'Ungeklaerten physischen Vorgang vor Update beheben')
    assert(not newest.manager or not newest.manager.active,'Auftrag vor Update abschliessen oder abbrechen und einsammeln')
    assert(not newest.worker or not newest.worker.task,'Arbeiter vor Update zurueckrufen')
  end
  local root='.flotte/releases/'..manifest.version..'-'..commit..'/'
  if not fs.exists(root..'.complete') then
    if fs.exists(root) then fs.delete(root) end
    local seen={}
    for _,file in ipairs(manifest.files) do
      assert(type(file.path)=='string' and file.path:match('^v2/[%w_%-]+%.lua$') and not seen[file.path],'Ungueltiger oder doppelter Manifestpfad')
      assert(type(file.bytes)=='number' and type(file.checksum)=='number','Dateipruefsumme fehlt')
      seen[file.path]=true
      local data=get(BASE..commit..'/'..file.path)
      assert(#data==file.bytes and checksum(data)==file.checksum,'Downloadpruefung fehlgeschlagen: '..file.path)
      assert(load(data,'@'..file.path),'Lua-Syntaxfehler: '..file.path)
      writeFile(root..file.path,data); print('Geprueft: '..file.path)
    end
    assert(seen['v2/main.lua'] and seen['v2/bootstrap_startup.lua'],'Pflichtdatei fehlt')
    writeFile(root..'.complete',commit)
  end
  if not readFile('.flotte/active') then
    local backup='.flotte/v1-backup/'..os.epoch('utc')
    for _,path in ipairs({'startup.lua','common','koordinator','arbeiter','taschencomputer','Flotte','update'}) do
      if fs.exists(path) then fs.makeDir(backup); fs.copy(path,backup..'/'..path) end
    end
  end
  local startup=assert(readFile(root..'v2/bootstrap_startup.lua'))
  local installer=get(BASE..commit..'/init.lua')
  assert(type(manifest.installer)=='table' and #installer==manifest.installer.bytes and checksum(installer)==manifest.installer.checksum,'Installerpruefung fehlgeschlagen')
  assert(load(installer,'@init.lua'),'Installer enthaelt Lua-Syntaxfehler')
  switch('.flotte/role',role)
  switch('.flotte/source',ref)
  switch('.flotte/active',root)
  switch('startup.lua',startup)
  switch('.flotte/installer.lua',installer)
  print('Flotte '..manifest.version..' installiert ('..commit:sub(1,8)..').')
  print('Konfiguration und Betriebsdaten erhalten. Neustart mit reboot.')
end
local ok,e=pcall(install)
if not ok then printError('Installation abgebrochen; bisherige vollstaendige Fassung bleibt erhalten.\n'..tostring(e)); return false end
return true
