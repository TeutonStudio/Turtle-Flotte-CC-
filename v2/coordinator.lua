local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local I,V,J,C=U.load('inventory'),U.load('nav'),U.load('jobs'),U.load('setup')
local M={}
function M.new(config,store,net)
  local d=store.data
  d.manager=d.manager or {workers={},queue={},reports={},counter=0,cargo={},phase='idle'}
  local s=d.manager
  local self={state=s,id=os.getComputerID(),config=config}
  local function save() store:save() end
  local function occupied(key,owner)
    for id,w in pairs(s.workers) do
      if not w.stored and not w.packed and tonumber(id)~=owner then
        if w.position and U.key(w.position)==key then return true end
        if w.next and U.key(w.next)==key then return true end
        if w.calibration and w.calibration[key] then return true end
        if w.task and w.task.service and U.key(w.task.service)==key and owner~=self.id then return true end
        if w.task and U.key(w.task.stand)==key then return true end
      end
    end
    if owner~=self.id and d.nav and d.nav.pos and U.key(d.nav.pos)==key then return true end
    if owner~=self.id and s.next and U.key(s.next)==key then return true end
    return false
  end
  self.occupied=occupied
  local nav
  nav=V.new(store,{
    blocked=function(k) return occupied(k,self.id) end,
    claim=function(_,target)
      if occupied(U.key(target),self.id) then return false,'Weg reserviert; warten' end
      s.next=U.copy(target); save(); return true
    end,
    arrived=function() s.next=nil; save(); return true end,
    beforeStep=function(target)
      local fuel=turtle.getFuelLevel(); if fuel=='unlimited' then return true end
      local home=V.path(nav.state.map,nav.state.pos,config.coal.pos)
      local nextHome=V.path(nav.state.map,target,config.coal.pos)
      if home and nextHome and #nextHome<#home and fuel>#nextHome then return true end
      if nextHome and fuel<#nextHome+65 then return false,'Verwalterreserve erreicht: Kohle nachladen, bevor Fahrt fortgesetzt wird' end
      return true
    end,
  })
  self.nav=nav
  local function newId(prefix)
    s.counter=s.counter+1; save(); return self.id..'-'..prefix..'-'..s.counter
  end
  local function alive(w) return w.lastSeen and U.now()-w.lastSeen<=20 and not w.stored end
  local function worker(sender,session)
    local w=s.workers[tostring(sender)]
    if not w or w.session~=session or w.stored or w.packed then return nil end
    return w
  end
  local function counts(snapshot)
    local r={}; for _,a in pairs(snapshot or {}) do r[a.name]=(r[a.name] or 0)+a.count end; return r
  end
  local function update(w,p)
    w.lastSeen=U.now()
    if type(p.seq)~='number' or p.seq<=(w.reportSeq or 0) then return end
    w.reportSeq=p.seq
    if U.pos(p.position) then
      if not w.position or U.eq(w.position,p.position) or w.next and U.eq(w.next,p.position) then
        if not w.position then w.position=U.copy(p.position) end
        nav.state.map[U.key(p.position)]='air'
      end -- Delayed heartbeats cannot override acknowledged movement.
    end
    w.lastSeen=U.now(); w.fuel=p.fuel; w.inventory=p.inventory or w.inventory
    w.needs=p.needs; w.status=p.status; w.issue=p.issue or (w.quarantine and w.issue); w.heading=p.heading
  end
  local function taskRoute(w,task)
    local route=V.path(nav.state.map,w.position,task.stand,function(k) return occupied(k,w.id) end)
    if not route then return nil end
    local out=U.copy(task); out.route=route; return out
  end
  local function parkTask(w)
    return {id=newId('park-'..w.id),kind='park',stand=w.park,status='offered',worker=w.id}
  end
  local function canAssign(w)
    return alive(w) and not w.issue and not w.quarantine and not w.needs and not w.next
  end
  function net.handler(sender,kind,p,session)
    if kind=='COMMAND' then return self:command(p.cmd,p.args or {}) end
    if kind=='STATUS' then return true,self:status() end
    if kind=='HELLO' then
      local w=s.workers[tostring(sender)]
      local newlyPlaced=false
      if not w then
        if not s.spawn or s.spawn.id~=sender then return false,nil,'Nicht vom Verwalter ausgesetzter Arbeiter' end
        if not U.pos(p.position) or not U.eq(p.position,s.spawn.position) then return false,nil,'Startposition stimmt nicht mit Aussetzplatz ueberein' end
        w={id=sender,park=s.spawn.park,role=p.role,position=p.position,ready=false,stored=false,label=s.spawn.label}
        s.workers[tostring(sender)]=w
        newlyPlaced=true
      end
      if w.stored then return false,nil,'Arbeiter ist eingelagert; neue Aussetzung abwarten' end
      if not U.pos(p.position) then return false,nil,'GPS-Position bei Anmeldung fehlt' end
      if w.calibration and (U.eq(p.position,w.position) or w.calibration[U.key(p.position)]) then
        nav.state.map[U.key(w.position)]='air'; w.position=U.copy(p.position); w.calibration=nil; w.next=nil
      elseif w.next and (U.eq(p.position,w.next) or U.eq(p.position,w.position)) then
        nav.state.map[U.key(w.position)]='air'; w.position=U.copy(p.position); w.next=nil
      elseif not U.eq(p.position,w.position) then
        w.quarantine=true; w.issue='GPS-Position bei Wiederanmeldung passt nicht zur letzten Freigabe'
      end
      if w.task and p.task~=w.task.id and not (p.completed and p.completed[w.task.id]) then
        w.quarantine=true; w.issue='Teilaufgabe nach Neustart nicht bestaetigt'
      end
      if w.session~=session then w.reportSeq=0 end
      w.session=session; update(w,p); save()
      return true,{park=w.park,heading=newlyPlaced and s.spawn.heading or w.heading or config.heading,placed=newlyPlaced,control=s.control}
    end
    local w=worker(sender,session)
    if not w then return false,nil,'Anmeldung/Sitzung fehlt' end
    if kind=='HEARTBEAT' then update(w,p); save(); return true,{control=s.control}
    elseif kind=='ROUTE' then
      if not U.pos(p.goal) then return false,nil,'Ziel fehlt' end
      local path,e=V.path(nav.state.map,w.position,p.goal,function(k) return occupied(k,w.id) end)
      return path~=nil,{route=path},e
    elseif kind=='CALIBRATE' then
      if not U.eq(p.position,w.position) or w.next then return false,nil,'Kalibrierung passt nicht zur registrierten Position' end
      local cells={}
      for h=1,4 do
        local key=U.key(U.add(w.position,U.dirs[h]))
        if occupied(key,w.id) or config.protected[key] then return false,nil,'Kalibrierungsraum belegt' end
        cells[key]=true
      end
      w.calibration=cells; save(); return true,{}
    elseif kind=='RESERVE' then
      if w.quarantine or not U.eq(p.from,w.position) or not U.pos(p.to) or U.dist(p.from,p.to)~=1 then return false,nil,'Bewegung nicht mit Position vereinbar' end
      if not alive(w) or s.frozen then return false,nil,'Flotte wartet auf Wiederanmeldung' end
      if occupied(U.key(p.to),w.id) then return false,nil,'Weg reserviert; warten' end
      if config.protected[U.key(p.to)] then return false,nil,'Geschuetzte Basisposition' end
      if w.next and not U.eq(w.next,p.to) then return false,nil,'Vorige Bewegung noch unbestaetigt' end
      w.next=U.copy(p.to); save(); return true,{}
    elseif kind=='ARRIVED' then
      if U.eq(p.from,w.position) and U.eq(p.to,w.position) then w.next=nil; w.calibration=nil; save(); return true,{} end
      if w.calibration and U.eq(p.from,w.position) and U.pos(p.to) and w.calibration[U.key(p.to)] then
        nav.state.map[U.key(w.position)]='air'; w.position=U.copy(p.to); nav.state.map[U.key(p.to)]='air'; w.calibration=nil; save(); return true,{}
      end
      if U.eq(w.position,p.to) and not w.next then return true,{} end
      if not w.next or not U.eq(w.next,p.to) then return false,nil,'Keine passende Bewegungsfreigabe' end
      if U.pos(p.from) then nav.state.map[U.key(p.from)]='air' end
      w.position=U.copy(p.to); w.next=nil; nav.state.map[U.key(p.to)]='air'; save(); return true,{}
    elseif kind=='POLL' then
      update(w,p)
      if w.task then return true,{task=taskRoute(w,w.task),control=s.control} end
      if not canAssign(w) or s.frozen then return true,{control=s.control} end
      local task
      if not w.ready or s.phase=='cleanup' then
        if not U.eq(w.position,w.park) then task=parkTask(w) else w.ready=true end
      elseif s.active and s.phase=='working' and s.control~='pause' and s.control~='abbrechen' then
        if s.active.kind=='craft' then
          local busy=false; for _,other in pairs(s.workers) do if other.task and other.task.kind=='craft' then busy=true end end
          if w.role=='werkbank' and not busy and s.active.crafted<s.active.batches then
            task={id=s.active.id..'/craft/'..(s.active.crafted+1),kind='craft',jobId=s.active.id,stand=w.park,recipe=s.active.recipe,status='offered',worker=w.id}
          end
        else
          local reason
          task,reason=J.next(s.active,nav.state.map,w,{id=self.id,position=nav.state.pos},occupied,config.blockRoles)
          if reason then s.active.blocked=reason end
        end
        if not task and not U.eq(w.position,w.park) then task=parkTask(w) end
      end
      if task then
        local routed=taskRoute(w,task)
        if routed then
          w.task=task; if task.kind=='park' then w.ready=false end
          if s.active then s.active.sequence=(s.active.sequence or 0)+1 end
          if s.active then s.active.blocked=nil end
          if task.key then s.active.tasks[task.key]=task end
          save(); return true,{task=routed,control=s.control}
        end
      end
      save(); return true,{control=s.control}
    elseif kind=='ACCEPT' then
      if not w.task or w.task.id~=p.task then return false,nil,'Zuweisung passt nicht' end
      w.task.status='active'; save(); return true,{}
    elseif kind=='DONE' then
      if w.lastDone==p.task then return true,{} end
      if not w.task or w.task.id~=p.task or w.task.status~='active' or type(p.result)~='table' then return false,nil,'Abschluss ohne aktive Zuweisung' end
      local task=w.task; local job=s.active
      for key,block in pairs(p.result.observations or {}) do
        local pos=U.pos(key)
        if pos and U.dist(pos,w.position)==1 then
          local transient=false
          for _,other in pairs(s.workers) do if not other.stored and U.eq(pos,other.position) then transient=true end end
          if U.eq(pos,nav.state.pos) then transient=true end
          nav.state.map[key]=transient and 'air' or block
        end
      end
      if task.kind=='park' then
        if not U.eq(w.position,w.park) or not p.result.parked then return false,nil,'Parkplatz nicht erreicht' end
        w.ready=true
      elseif not job or task.jobId~=job.id then return false,nil,'Falscher Auftrag'
      elseif task.kind=='craft' then
        if p.result.crafted~=1 then return false,nil,'Craftingmenge nicht bestaetigt' end
        job.crafted=job.crafted+1
      else
        local block=p.result.block
        if block~='air' and (type(block)~='table' or type(block.name)~='string') then return false,nil,'Blockbeobachtung fehlt' end
        nav.state.map[U.key(task.target)]=block
        if block=='air' then job.done[task.key]='air' end
        job.tasks[task.key]=nil
      end
      w.lastDone=task.id; w.task=nil; w.status='idle'; w.issue=nil; save(); return true,{}
    elseif kind=='CANCELLED' then
      if not s.active or not s.active.cancelled then return false,nil,'Kein Abbruch angefordert' end
      if not w.task then return true,{} end
      if w.task.id~=p.task then return false,nil,'Falsche Teilaufgabe' end
      if w.task.key then s.active.tasks[w.task.key]=nil end
      w.task=nil; w.issue=nil; w.needs=nil; save(); return true,{}
    elseif kind=='PROBLEM' then
      if not w.task or w.task.id~=p.task then return false,nil,'Falsche Teilaufgabe' end
      w.issue=tostring(p.error); if s.active then s.active.blocked='Arbeiter '..w.id..': '..w.issue end
      save(); return true,{}
    end
    return false,nil,'Unbekannte Nachricht'
  end
  function self:status()
    local workers={}
    for _,w in pairs(s.workers) do
      local a=U.copy(w); a.online=alive(w); a.inventory=nil; a.session=nil; workers[#workers+1]=a
    end
    local job=s.active and U.copy(s.active)
    if job then job.tasks=nil; job.doneCount=U.count(job.done); job.done=nil end
    return {version=2,manager=self.id,phase=s.phase,blocked=s.blocked,control=s.control,currentJob=job,queued=#s.queue,workers=workers,delivery=s.delivery,position=nav.state.pos}
  end
  function self:command(cmd,p)
    if type(p)~='table' then return false,nil,'Befehlsparameter muessen eine Tabelle sein' end
    if cmd=='status' or cmd=='list' then return true,self:status()
    elseif cmd=='bericht' then
      local job=s.active and s.active.id==p.id and s.active or s.reports[p.id]
      if not job then return false,nil,'Bericht nicht gefunden' end
      local summary=U.copy(job); summary.doneCount=U.count(job.done); summary.done=nil; summary.tasks=nil
      return true,summary
    elseif cmd=='rezepte' then
      if p.recipe then
        local good,e=J.recipe(p.recipe); if not good then return false,nil,e end
        if type(p.name)~='string' or p.name=='' then return false,nil,'Rezeptname fehlt' end
        config.recipes[p.name]=U.copy(p.recipe); C.save(config); return true,config.recipes
      end
      return true,config.recipes
    elseif cmd=='pause' or cmd=='weiter' or cmd=='abbrechen' then
      if cmd=='weiter' and d.intent and p.pruefen~='ja' then return false,nil,'Physischer Vorgang unklar. Inventar/Welt pruefen, dann weiter pruefen:ja' end
      s.control=cmd=='weiter' and nil or cmd
      s.blocked=nil
      if cmd=='weiter' then s.review=p.pruefen=='ja'; for _,w in pairs(s.workers) do w.issue=nil end end
      if cmd=='abbrechen' and s.active then s.active.cancelled=true; s.phase='cleanup' end
      s.controls={action=cmd,pruefen=p.pruefen,richtung=p.richtung}; save(); return true,self:status()
    elseif cmd=='abbau' or cmd=='holz' or cmd=='erdarbeiten' or cmd=='craft' then
      local job,e=J.create(newId('job'),cmd,p,config.recipes)
      if not job then return false,nil,e end
      if job.box then
        for key in pairs(config.protected) do if U.inside(U.pos(key),job.box) then return false,nil,'Arbeitsbereich enthaelt Basisinventar' end end
        for _,park in ipairs(config.parks) do if U.inside(park,job.box) then return false,nil,'Arbeitsbereich enthaelt Parkplatz' end end
        if U.inside(config.base,job.box) or U.inside(config.deploy.pos,job.box) then return false,nil,'Arbeitsbereich enthaelt Basisstandplatz' end
      end
      s.queue[#s.queue+1]=job; save(); return true,{jobId=job.id}
    end
    return false,nil,'Unbekannter Befehl: '..tostring(cmd)
  end
  function self:output()
    if U.count(s.cargo)==0 then return true end
    local ok,e=nav:dock(config.output,true); if not ok then return false,e end
    ok,e=I.assertChest(config.output.side); if not ok then return false,e end
    for name,count in pairs(s.cargo) do
      for slot=1,16 do
        local a=turtle.getItemDetail(slot)
        if a and a.name==name and count>0 then
          turtle.select(slot); local before=a.count
          local entries={{path={'manager','cargo',name},sign=-1,zeroNil=true}}
          if s.active then
            s.active.delivered=s.active.delivered or {}
            entries[#entries+1]={path={'manager','active','delivered',name}}
          end
          I.transfer(store,config.output.side,'drop',math.min(count,a.count),{name=name,entries=entries})
          local sent=before-turtle.getItemCount(slot)
          count=count-sent; save()
        end
      end
      if count>0 then return false,'Ergebnislager voll oder Transportbestand unklar: '..name end
    end
    return true
  end
  function self:fuel()
    local fuel=turtle.getFuelLevel()
    local home=V.path(nav.state.map,nav.state.pos,config.coal.pos)
    local reserve=math.max(2000,home and #home+256 or 2000)
    if fuel=='unlimited' or fuel>=reserve then return true end
    -- Cargo, including mined coal, must reach storage before supplies are consumed.
    local ok,e=self:output(); if not ok then return false,e end
    ok,e=nav:dock(config.coal,true); if not ok then return false,'Kohletruhe nicht erreichbar: '..tostring(e) end
    ok,e=I.assertChest(config.coal.side); if not ok then return false,e end
    for _=1,16 do
      local reserved={}
      if s.delivery and s.delivery.action=='ingredients' then
        for name,n in pairs(s.delivery.loaded) do reserved[name]=n-((s.delivery.sent or {})[name] or 0) end
      end
      I.refuel(store,math.max(4000,reserve+256),reserved)
      if turtle.getFuelLevel()>=2000 then return true end
      local receivingSlot=I.receiveSlot(); if not receivingSlot then return false,'Verwalterinventar voll' end
      local good=I.transfer(store,config.coal.side,'suck',64)
      if not good then return false,'Kohletruhe leer' end
      local received=turtle.getItemDetail(receivingSlot)
      if received and not I.fuel[received.name] then return false,'Kohletruhe enthaelt Fremdgegenstand '..received.name end
    end
    return false,'Nicht genug Kohle fuer Verwalterreserve'
  end
  function self:survey()
    for _,dock in ipairs({config.coal,config.output,config.start,config.deploy}) do
      local ok,e=nav:dock(dock,true); if not ok then return false,e end; nav:scan()
    end
    for _,p in ipairs(config.parks) do local ok,e=nav:go(p,true); if not ok then return false,e end; nav:scan() end
    if s.active.box then
      local box=s.active.box
      local ok,e=nav:go({x=box.min.x,y=box.max.y+1,z=box.min.z},true)
      if not ok then return false,'Freien Zugang oberhalb des Arbeitsbereichs herstellen: '..tostring(e) end
      nav:scan()
    end
    s.surveyed=true; save(); return true
  end
  function self:deploy()
    if s.spawn then
      if not s.spawn.id then
        local peer=peripheral.wrap('front')
        if not peer and s.spawn.slot then
          local item=turtle.getItemDetail(s.spawn.slot,true)
          local target=nav:inspect(s.spawn.position)
          if item and item.nbt==s.spawn.itemNbt and target=='air' then
            if d.intent and d.intent.kind=='deploy' then store:finish() end
            turtle.select(s.spawn.slot)
            local placed,e=I.action(store,'deploy',turtle.place,{target=s.spawn.position})
            if not placed then return false,e end
            peer=peripheral.wrap('front')
          end
        end
        if peer and peer.getID and peer.getLabel and peer.getLabel() and (not s.spawn.label or peer.getLabel()==s.spawn.label) then
          s.spawn.id=peer.getID(); s.spawn.label=peer.getLabel(); save()
          if d.intent and d.intent.kind=='deploy' then store:finish() end
          peer.turnOn()
        else return false,'Aussetzung unterbrochen: Turtle am Aussetzplatz und Beschriftung pruefen' end
      end
      local w=s.workers[tostring(s.spawn.id)]
      if w and w.ready then s.spawn=nil; save(); return true end
      if U.now()-(s.spawn.started or U.now())>20 and not w then return false,'Arbeiter meldet sich nicht: installierte Rolle, Verwalter-ID und Funkmodem pruefen' end
      if not w then
        local peer=peripheral.wrap('front')
        if peer and peer.getID and peer.getID()==s.spawn.id then peer.turnOn() end
      end
      return true
    end
    local live=0; for _,w in pairs(s.workers) do if not w.stored then live=live+1 end end
    if live>=#config.parks then s.phase='working'; save(); return true end
    local ok,e=nav:dock(config.start,true); if not ok then return false,e end
    ok,e=I.assertChest(config.start.side); if not ok then return false,e end
    local slot
    for i,item in pairs(I.snapshot()) do if item.name:match('^computercraft:turtle_') then slot=i; break end end
    local got=slot~=nil
    if not slot then
      slot=I.receiveSlot(); if not slot then return false,'Kein Platz fuer Arbeiter-Turtle' end
      got=I.transfer(store,config.start.side,'suck',1)
    end
    if not got then
      if live>0 then s.phase='working'; save(); return true end
      return false,'Starttruhe leer: vorinstallierte beschriftete Arbeiter einlegen'
    end
    local item=turtle.getItemDetail(slot)
    if not item or not item.name:match('^computercraft:turtle_') then return false,'Starttruhe enthaelt keine Turtle' end
    local detail=turtle.getItemDetail(slot,true)
    ok,e=nav:dock(config.deploy,true); if not ok then return false,e end
    local target=U.add(nav.state.pos,U.dirs[nav.state.heading])
    if occupied(U.key(target),self.id) then return false,'Aussetzplatz belegt' end
    local block=nav:inspect(target); if block~='air' then return false,'Aussetzplatz blockiert' end
    local park
    for _,p in ipairs(config.parks) do
      local used=false; for _,w in pairs(s.workers) do if not w.stored and U.eq(w.park,p) then used=true end end
      if not used then park=p; break end
    end
    turtle.select(slot)
    s.spawn={park=park,position=target,heading=nav.state.heading,itemNbt=detail.nbt,slot=slot,started=U.now()}; save()
    local placed,why=I.action(store,'deploy',turtle.place,{target=target})
    if not placed then return false,why or 'Arbeiter konnte nicht platziert werden' end
    local peer=peripheral.wrap('front')
    if not peer or not peer.getID then return false,'Ausgesetzte Turtle nicht als Computer erreichbar' end
    if not peer.getLabel or not peer.getLabel() then return false,'Arbeiter muss beschriftet sein: am ausgesetzten Arbeiter label set <name> ausfuehren' end
    s.spawn.id=peer.getID(); s.spawn.label=peer.getLabel()
    local old=s.workers[tostring(s.spawn.id)]
    if old and not old.stored then return false,'Arbeiter-ID bereits aktiv' end
    s.workers[tostring(s.spawn.id)]=nil; save()
    peer.turnOn(); return true
  end
  function self:servicePosition(w)
    local preferred=w.task and w.task.service
    local candidates=U.neighbors(w.position)
    if not w.heading then candidates={U.add(w.position,U.dirs[5]),U.add(w.position,U.dirs[6])} end
    if preferred and w.heading then table.insert(candidates,1,preferred) end
    for _,p in ipairs(candidates) do
      if U.dist(w.position,p)==1 and nav.state.map[U.key(p)]=='air' and not occupied(U.key(p),self.id) then
        local path=V.path(nav.state.map,nav.state.pos,p,function(k) return occupied(k,self.id) end)
        if path then return p end
      end
    end
    return nil,'Kein erreichbarer Uebergabeplatz fuer Arbeiter '..w.id
  end
  local function facePeer(w)
    if U.dist(nav.state.pos,w.position)~=1 then return nil,'Arbeiter hat Uebergabeplatz verlassen' end
    local side
    if w.position.y>nav.state.pos.y then side='up'
    elseif w.position.y<nav.state.pos.y then side='down'
    else
      for h=1,4 do if U.eq(U.add(nav.state.pos,U.dirs[h]),w.position) then
        local ok,e=nav:face(h); if not ok then return nil,e end; side='front'
      end end
    end
    local peer=side and peripheral.wrap(U.peripheralSide(side))
    if not peer or not peer.getID or peer.getID()~=w.id then return nil,'Arbeiter-ID an Uebergabeposition stimmt nicht' end
    return side
  end
  function self:delivery(w,action)
    local a=s.delivery
    if not a then a={id=newId('supply'),worker=w.id,action=action,phase='prepare',loaded={}}; s.delivery=a; save() end
    if a.worker~=w.id then return false,'Andere Versorgung noch aktiv' end
    if a.phase=='prepare' then
      local good,e=self:output(); if not good then return false,e end
      good,e=self:fuel(); if not good then return false,e end
      if action=='fuel' then
        good,e=nav:dock(config.coal,true); if not good then return false,e end
        good,e=I.assertChest(config.coal.side); if not good then return false,e end
        local have=I.count('minecraft:coal')+I.count('minecraft:charcoal')
        if have<32 then
          if not I.receiveSlot() then return false,'Verwalterinventar voll' end
          local got=I.transfer(store,config.coal.side,'suck',32-have)
          if not got and have==0 then return false,'Kohletruhe leer' end
        end
        if I.count('minecraft:coal')+I.count('minecraft:charcoal')<1 then return false,'Keine freigegebene Kohle geladen' end
      elseif action=='ingredients' then
        if not w.task or w.task.kind~='craft' then return false,'Craftingauftrag fehlt' end
        local required={}
        for _,name in pairs(w.task.recipe.grid) do if name then required[name]=(required[name] or 0)+1 end end
        for name,n in pairs(required) do
          local need=n-(a.loaded[name] or 0)
          if need>0 then
            local source=config.materials[name]
            if not source then return false,'Materialquelle fehlt: '..name end
            good,e=nav:dock(source,true); if not good then return false,e end
            good,e=I.assertChest(source.side); if not good then return false,e end
            if not I.receiveSlot() then return false,'Verwalterinventar voll' end
            local before=I.count(name)
            I.transfer(store,source.side,'suck',need,{name=name,entries={{path={'manager','delivery','loaded',name}}}})
            local received=I.count(name)-before
            save()
            if received<need then return false,'Zutaten fehlen: '..name end
          end
        end
      end
      a.position=self:servicePosition(w)
      if not a.position then return false,'Versorgungszugang zu Arbeiter '..w.id..' blockiert' end
      a.phase='travel'; save()
    end
    if not alive(w) then return false,'Arbeiter '..w.id..' nicht erreichbar; Bereich bleibt reserviert' end
    local ok,e=nav:go(a.position,false); if not ok then return false,e end
    local side,why=facePeer(w); if not side then return false,why end
    if a.phase=='travel' then
      local before=counts(I.snapshot())
      a.before=before; a.phase='request'; save()
    end
    if a.phase=='request' then
      local accepted,_,err=net:rpc(w.id,'SERVICE',{id=a.id,action=action,all=action=='collect' and (w.needs=='collect_all' or s.phase=='cleanup'),position=nav.state.pos,target=1600},8)
      if not accepted then return false,err end
      a.phase='transfer'; save()
    end
    if a.phase=='transfer' then
      local deadline=U.now()+30; local status
      repeat
        local got,r,err=net:rpc(w.id,'SERVICE_STATUS',{id=a.id},5)
        if not got then return false,err end
        status=r
        if status.phase~='ready' and status.phase~='done' then sleep(0.2) end
      until status.phase=='ready' or status.phase=='done' or U.now()>deadline
      if status.phase~='ready' and status.phase~='done' then return false,'Arbeiter bereitet Uebergabe nicht vor: '..tostring(w.issue) end
      if action~='collect' and status.phase~='done' then
        if not a.sent then a.sent={}; save() end
        local required=action=='ingredients' and a.loaded or nil
        for slot=1,16 do
          local item=turtle.getItemDetail(slot)
          local remaining=item and (required and ((required[item.name] or 0)-(a.sent[item.name] or 0)) or I.fuel[item.name] and (32-(a.sentFuel or 0)) or 0)
          if item and remaining>0 then
            turtle.select(slot); local before=item.count
            I.transfer(store,side,'drop',math.min(item.count,remaining),{name=item.name,entries={{path={'manager','delivery','sent',item.name}},{path={'manager','delivery','sentFuel'}}}})
            local sent=before-turtle.getItemCount(slot)
            save()
          end
        end
        if action=='ingredients' then
          for name,n in pairs(required) do if (a.sent[name] or 0)~=n then return false,'Zutatenuebergabe unvollstaendig: '..name end end
        elseif (a.sentFuel or 0)==0 then return false,'Kohle konnte nicht uebergeben werden' end
        local committed,_,err=net:rpc(w.id,'SERVICE_COMMIT',{id=a.id},6); if not committed then return false,err end
      end
      deadline=U.now()+30
      repeat
        local got,r,err=net:rpc(w.id,'SERVICE_STATUS',{id=a.id},5)
        if not got then return false,err end
        status=r; if status.phase~='done' then sleep(0.2) end
      until status.phase=='done' or U.now()>deadline
      if status.phase~='done' then return false,'Uebergabe nicht abgeschlossen: '..tostring(w.issue) end
      if action=='fuel' and status.afterFuel~='unlimited' and status.afterFuel<=status.beforeFuel then return false,'Treibstoffanstieg nicht bestaetigt' end
      if action=='collect' and not a.accounted then
        local after=counts(I.snapshot())
        for name,n in pairs(after) do
          local received=n-(a.before[name] or 0)
          if received>0 then s.cargo[name]=(s.cargo[name] or 0)+received end
        end
        a.accounted=true
      end
      a.phase='close'; save()
    end
    if a.phase=='close' then
      local closed,result,err=net:rpc(w.id,'SERVICE_CLOSE',{id=a.id},6)
      if not closed then return false,err end
      w.reportSeq=math.max(w.reportSeq or 0,result.seq or 0)
      s.delivery=nil; w.needs=nil; save()
    end
    if action=='collect' then return self:output() end
    return true
  end
  function self:serviceNext()
    if s.delivery then
      local a=s.delivery
      if s.active and s.active.cancelled and (a.phase=='prepare' or a.phase=='travel') then
        if a.action=='ingredients' then
          for name,n in pairs(a.loaded) do s.cargo[name]=(s.cargo[name] or 0)+n end
        end
        s.delivery=nil; save(); return self:output()
      end
      local w=s.workers[tostring(s.delivery.worker)]
      return self:delivery(w,s.delivery.action)
    end
    local list={}
    for _,w in pairs(s.workers) do
      if not w.stored and w.needs then list[#list+1]=w end
    end
    table.sort(list,function(a,b)
      local rank={fuel=1,collect=2,collect_all=2,ingredients=3}
      local ar,br=rank[a.needs] or 9,rank[b.needs] or 9
      return ar==br and a.id<b.id or ar<br
    end)
    local w=list[1]
    if w then
      local action=w.needs=='collect_all' and 'collect' or w.needs
      if action=='fuel' and U.count(w.inventory)>=16 then action='collect' end
      return self:delivery(w,action)
    end
    return true
  end
  function self:cleanup()
    if s.pack then
      local a=s.pack; local w=s.workers[tostring(a.worker)]
      if a.phase~='deposited' then
        local item=turtle.getItemDetail(a.slot,true)
        if not item or not item.name:match('^computercraft:turtle_') or item.count~=1 then return false,'Eingesammelte Turtle im Transportplatz nicht eindeutig bestaetigt' end
        w.packed=true; nav.state.map[U.key(w.position)]='air'; save()
        local ok,e=nav:dock(config.start,true); if not ok then return false,e end
        ok,e=I.assertChest(config.start.side); if not ok then return false,e end
        turtle.select(a.slot)
        I.transfer(store,config.start.side,'drop',1,{name=item.name,entries={{path={'manager','pack','phase'},value='deposited'}}})
        if s.pack.phase~='deposited' then return false,'Starttruhe voll' end
      end
      w.stored=true; w.packed=nil; w.task=nil; s.pack=nil; save(); return true
    end
    for _,w in pairs(s.workers) do
      if not w.stored then
        if not alive(w) then return false,'Arbeiter '..w.id..' fehlt; Abschluss bleibt offen' end
        if w.task then
          if s.active.cancelled and w.task.kind~='park' then
            return true -- CANCELLED releases ownership after the worker stops.
          else return true end
        end
        if not U.eq(w.position,w.park) or not w.ready then return true end
        if next(w.inventory or {}) then
          w.needs='collect_all'; return self:delivery(w,'collect')
        end
        local pos,e=self:servicePosition(w); if not pos then return false,e end
        local ok,err=nav:go(pos,false); if not ok then return false,err end
        local side,why=facePeer(w); if not side then return false,why end
        local accepted,r,readError=net:rpc(w.id,'STATUS',{},6)
        if not accepted or r.task or next(r.inventory or {}) then return false,readError or 'Arbeiter nicht leer und bereit zum Einsammeln' end
        local ready,_,readyError=net:rpc(w.id,'PACK_READY',{},6)
        if not ready then return false,readyError end
        local peer=peripheral.wrap(U.peripheralSide(side))
        local slot=I.receiveSlot(); if not slot then return false,'Kein Platz fuer eingesammelte Turtle' end
        s.pack={worker=w.id,slot=slot,phase='dig',side=side}; save()
        peer.shutdown()
        local fn=side=='up' and turtle.digUp or side=='down' and turtle.digDown or turtle.dig
        local dug,digError=I.action(store,'pack',fn,{worker=w.id,target=w.position})
        if not dug then s.pack=nil; peer.turnOn(); save(); return false,digError or 'Einsammeln fehlgeschlagen' end
        local item=turtle.getItemDetail(slot,true)
        if not item or not item.name:match('^computercraft:turtle_') then return false,'Eingesammelte Turtle nicht im reservierten Inventarplatz bestaetigt' end
        w.packed=true; s.pack.phase='transport'; save()
        return self:cleanup()
      end
    end
    local ok,e=self:output(); if not ok then return false,e end
    ok,e=nav:go(config.base,true); if not ok then return false,e end
    local job=s.active
    job.status=job.cancelled and 'cancelled' or 'done'; job.finished=U.now(); job.blocked=nil
    s.reports[job.id]=U.copy(job); s.active=nil; s.phase='idle'; s.surveyed=nil; s.control=nil; save()
    return true
  end
  function self:tick()
    if s.controls then
      local all=true
      for _,w in pairs(s.workers) do
        if not w.stored then
          local ok=net:rpc(w.id,'CONTROL',s.controls,3); if not ok then all=false end
        end
      end
      if all then s.controls=nil; save() end
    end
    if s.review then
      if d.intent and d.intent.kind~='move' and d.intent.kind~='turn' then
        local good,e=I.recover(store)
        if not good and d.intent.kind~='deploy' and d.intent.kind~='pack' then s.blocked=e; s.review=nil; save(); return end
      end
      local good,e=nav:recover(); if not good then s.blocked=e end
      if good and not nav.state.heading then local calibrated,why=nav:calibrate(config.heading); if not calibrated then s.blocked=why end end
      s.review=nil
    end
    if s.pack and not d.intent then
      local item=turtle.getItemDetail(s.pack.slot,true)
      local w=s.workers[tostring(s.pack.worker)]
      if s.pack.phase=='deposited' or item and item.name:match('^computercraft:turtle_') and item.count==1 then w.packed=true end
    end
    if d.intent and d.intent.kind=='deploy' and s.spawn then
      local good,e=self:deploy(); if not good then s.blocked=e; save(); return end
    elseif d.intent and d.intent.kind=='pack' and s.pack then
      local item=turtle.getItemDetail(s.pack.slot,true)
      local w=s.workers[tostring(s.pack.worker)]
      if item and item.name:match('^computercraft:turtle_') and item.count==1 then
        w.packed=true; s.pack.phase='transport'; nav.state.map[U.key(w.position)]='air'; store:finish()
      else s.blocked='Einsammeln unterbrochen: Ziel-Turtle und Transportplatz pruefen'; save(); return end
    end
    if d.intent then s.blocked=s.blocked or 'Ungeklaerter physischer Vorgang; keine automatische Wiederholung'; save(); return end
    local frozen=false
    for _,w in pairs(s.workers) do if not w.stored and not w.packed and not alive(w) then frozen=true end end
    s.frozen=frozen
    if frozen then s.blocked='Mindestens ein Arbeiter ohne Kontakt; Positionen bleiben reserviert'; save(); return end
    if not s.active and #s.queue>0 and s.control~='pause' then
      s.active=table.remove(s.queue,1); s.active.status='running'; s.phase='prepare'; s.surveyed=nil; save()
    end
    if not s.active then return end
    if s.blocked and U.now()-(s.retryAt or 0)<5 then return end
    local ok,e=self:fuel()
    if ok then ok,e=self:serviceNext() end
    if not ok then s.blocked=e; s.retryAt=U.now(); save(); return end
    if s.phase=='prepare' then
      ok,e=self:fuel()
      if ok then ok,e=self:survey() end
      if ok then s.phase='deploying'; save() end
    elseif s.phase=='deploying' then ok,e=self:deploy()
    elseif s.phase=='working' then
      if J.complete(s.active) then s.phase='cleanup'; save()
      else
        local tasks=false
        for _,w in pairs(s.workers) do if not w.stored and w.task then tasks=true end end
        if not tasks and s.control~='pause' then
          s.active.blocked=s.active.blocked or 'Keine passende erreichbare Teilaufgabe: Werkzeug, Zugang und freie Serviceplaetze pruefen'
        end
      end
    elseif s.phase=='cleanup' then ok,e=self:cleanup() end
    if ok==false then s.blocked=e; s.retryAt=U.now() else s.blocked=nil end
    save()
  end
  function self:main()
    local role,e=I.role(); assert(role=='spitzhacke',e or 'Verwalter benoetigt Spitzhacke')
    if d.intent and d.intent.kind~='move' and d.intent.kind~='turn' and d.intent.kind~='deploy' and d.intent.kind~='pack' then
      local good,why=I.recover(store); if not good then s.blocked=why end
    end
    local ok,err=nav:recover()
    if not ok then s.blocked=err end
    if ok then s.next=nil; save() end
    if ok then
      local good,why=nav:calibrate(config.heading); if not good then s.blocked=why end
    end
    rednet.host('flotte_v2',config.fleet..':'..self.id)
    -- Old heartbeat timestamps must not make a reboot look like a live session.
    for _,w in pairs(s.workers) do if not w.stored then w.lastSeen=nil end end
    save()
    while true do
      if nav.state.heading or s.review then self:tick() end
      sleep(0.2)
    end
  end
  return self
end
return M
