local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local I,J=U.load('inventory'),U.load('jobs')
local W={}
function W.new(config,store,net)
  local d=store.data
  d.worker=d.worker or {status='boot',completed={},services={}}
  local s=d.worker
  local self={state=s}
  local nav
  local blockedUntil={}
  nav=U.load('nav').new(store,{
    claim=function(from,to)
      local ok,_,e=net:rpc(config.manager,'RESERVE',{from=from,to=to},6)
      if not ok and e=='Weg reserviert; warten' then blockedUntil[U.key(to)]=U.now()+3 end
      return ok,e
    end,
    arrived=function(from,to)
      local ok,_,e=net:rpc(config.manager,'ARRIVED',{from=from,to=to},6); return ok,e
    end,
    beforeStep=function() return self:gate() end,
    blocked=function(k) return (blockedUntil[k] or 0)>U.now() end,
    calibrationClaim=function(p)
      local ok,_,e=net:rpc(config.manager,'CALIBRATE',{position=p},6); return ok,e
    end,
    route=function(goal)
      local ok,r,e=net:rpc(config.manager,'ROUTE',{goal=goal},6)
      if ok then for _,p in ipairs(r.route) do nav.state.map[U.key(p)]='air' end end
      return ok,e
    end,
  })
  self.nav=nav
  local function report()
    s.reportSeq=(s.reportSeq or 0)+1
    return {seq=s.reportSeq,role=s.role,status=s.status,position=nav.state.pos,heading=nav.state.heading,fuel=turtle.getFuelLevel(),inventory=I.snapshot(),task=s.task and s.task.id,needs=s.needs,issue=s.issue,service=s.service,completed=s.completed}
  end
  function net.handler(sender,kind,p)
    if sender~=config.manager then return false,nil,'Falscher Verwalter' end
    if kind=='SERVICE' then
      if type(p.id)~='string' or (p.action~='fuel' and p.action~='collect' and p.action~='ingredients') or not U.pos(p.position) then return false,nil,'Ungueltige Versorgung' end
      if s.services[p.id] then return true,s.services[p.id] end
      if s.service and s.service.id~=p.id then return false,nil,'Andere Uebergabe aktiv' end
      s.service=s.service or U.copy(p); s.service.phase=s.service.phase or 'requested'; store:save(); return true,s.service
    elseif kind=='SERVICE_STATUS' then return true,s.services[p.id] or (s.service and s.service.id==p.id and s.service) or {phase='unknown'}
    elseif kind=='SERVICE_COMMIT' then
      if s.services[p.id] then return true,s.services[p.id] end
      if not s.service or s.service.id~=p.id then return false,nil,'Uebergabe unbekannt' end
      s.service.commit=true; store:save(); return true,s.service
    elseif kind=='SERVICE_CLOSE' then
      if s.service and s.service.id==p.id and s.service.phase=='done' then s.service=nil; s.needs=nil; store:save() end
      s.reportSeq=(s.reportSeq or 0)+1; store:save()
      return true,{seq=s.reportSeq}
    elseif kind=='STATUS' then return true,report()
    elseif kind=='PACK_READY' then
      if s.task or s.service or I.count()>0 or not U.eq(nav.state.pos,s.park) then return false,nil,'Arbeiter noch nicht leer am Parkplatz' end
      s.packing=true; s.status='ready_to_pack'; store:save(); return true,{ready=true}
    elseif kind=='CONTROL' then
      s.control=p.action
      if p.richtung and U.heading(p.richtung) then s.headingHint=U.heading(p.richtung) end
      if p.action=='weiter' and p.pruefen=='ja' then s.review=true end
      store:save(); return true,{}
    end
    return false,nil,'Unbekannte Arbeiternachricht'
  end
  local function sideTo(position)
    if not nav.state.pos or U.dist(nav.state.pos,position)~=1 then return nil,'Verwalter nicht benachbart' end
    if position.y>nav.state.pos.y then return 'up' end
    if position.y<nav.state.pos.y then return 'down' end
    for h=1,4 do
      if U.eq(U.add(nav.state.pos,U.dirs[h]),position) then
        local ok,e=nav:face(h); if not ok then return nil,e end; return 'front'
      end
    end
  end
  function self:service()
    local a=s.service
    if not a or a.phase=='done' then return true end
    local side,e=sideTo(a.position); if not side then return false,e end
    local peer=peripheral.wrap(U.peripheralSide(side))
    if not peer or not peer.getID or peer.getID()~=config.manager then return false,'Uebergabe verweigert: Verwalter-ID am Nachbarblock stimmt nicht' end
    if a.phase=='requested' then
      a.beforeFuel=turtle.getFuelLevel(); a.before=I.snapshot()
      if a.action~='collect' and not I.receiveSlot() then return false,'Kein Empfangsplatz frei' end
      a.phase='ready'; store:save()
    end
    if a.action=='collect' then
      for slot=1,16 do
        local item=turtle.getItemDetail(slot)
        if item and (a.all or not I.fuel[item.name]) then
          turtle.select(slot)
          local ok=I.transfer(store,side,'drop',item.count)
          if not ok or turtle.getItemCount(slot)>0 then break end
        end
      end
      a.after=I.snapshot(); a.phase='done'
    elseif a.commit then
      if a.action=='fuel' then
        I.refuel(store,a.target or 1600)
        a.afterFuel=turtle.getFuelLevel()
        if a.afterFuel~='unlimited' and a.beforeFuel~='unlimited' and a.afterFuel<=a.beforeFuel then return false,'Kohlelieferung hat Treibstoffstand nicht erhoeht' end
      end
      a.after=I.snapshot(); a.phase='done'
    end
    if a.phase=='done' then s.services[a.id]=U.copy(a) end
    store:save(); return true
  end
  function self:waitNeed(need)
    s.needs=need; s.status='waiting'; store:save()
    while s.needs do
      if s.control=='abbrechen' and not s.service then s.needs=nil; store:save(); return false,'Auftrag abgebrochen' end
      local ok,e=self:service()
      if not ok then s.issue=e; store:save() end
      sleep(0.2)
    end
    s.issue=nil; s.status='working'; store:save(); return true
  end
  function self:gate()
    if s.control=='abbrechen' and not (s.task and s.task.kind=='park') then return false,'Auftrag abgebrochen' end
    while s.control=='pause' and not (s.task and s.task.kind=='park') do self:service(); sleep(0.2) end
    if s.contact and U.now()-s.contact>20 then return false,'Kontakt zum Verwalter verloren; warten auf weiter' end
    if I.emptySlots()<2 then local ok,e=self:waitNeed('collect'); if not ok then return false,e end end
    local fuel=turtle.getFuelLevel()
    if fuel~='unlimited' and fuel<64 then local ok,e=self:waitNeed('fuel'); if not ok then return false,e end end
    return true
  end
  local function verifyInputs(recipe)
    local gridSlots={1,2,3,5,6,7,9,10,11}
    local required={}
    for _,name in pairs(recipe.grid) do if name then required[name]=(required[name] or 0)+1 end end
    local actual={}
    for _,a in pairs(I.snapshot()) do actual[a.name]=(actual[a.name] or 0)+a.count end
    for name,n in pairs(required) do if actual[name]~=n then return false,'Zutatenmenge falsch: '..name end end
    for name in pairs(actual) do if not required[name] then return false,'Fremdgegenstand vor Crafting: '..name end end
    -- First consolidate, then place one ingredient per recipe cell in the 4x4 inventory.
    for a=1,16 do
      local item=turtle.getItemDetail(a)
      if item then for b=1,a-1 do
        local other=turtle.getItemDetail(b)
        if other and other.name==item.name then turtle.select(a); turtle.transferTo(b) end
      end end
    end
    -- Build the raster in a journalled sequence; a restart during layout is blocked.
    for index,slot in ipairs(gridSlots) do
      local wanted=recipe.grid[index]
      local current=turtle.getItemDetail(slot)
      if current and (current.name~=wanted or current.count>1) then
        local free
        for x=16,1,-1 do if turtle.getItemCount(x)==0 then free=x; break end end
        if not free then return false,'Kein Platz zum Anordnen des Rezepts' end
        turtle.select(slot); assert(turtle.transferTo(free),'Raster kann nicht vorbereitet werden')
      end
      current=turtle.getItemDetail(slot)
      if wanted and not current then
        local from
        for x=1,16 do
          local item=turtle.getItemDetail(x)
          local fixed=false
          for prev=1,index-1 do if gridSlots[prev]==x then fixed=true end end
          if not fixed and item and item.name==wanted then from=x; break end
        end
        if not from then return false,'Zutat fehlt beim Anordnen: '..wanted end
        turtle.select(from); assert(turtle.transferTo(slot,1),'Zutat kann nicht angeordnet werden')
      end
    end
    return true
  end
  function self:execute(task)
    for _,p in ipairs(task.route or {}) do nav.state.map[U.key(p)]='air' end
    local ok,e=self:gate(); if not ok then return nil,e end
    s.status='working'; store:save()
    ok,e=nav:go(task.stand,false); if not ok then return nil,e end
    if task.kind=='craft' then
      if s.craftReceipt and s.craftReceipt.task==task.id then
        local valid,why=I.checkCraft(task.recipe)
        if not valid then return nil,why end
        return {crafted=1}
      end
      if not s.task.materialsReady then
        if I.count()>0 then self:waitNeed('collect_all') end
        self:waitNeed('ingredients')
        s.task.materialsReady=true; store:save()
      end
      if s.control=='abbrechen' then return nil,'Auftrag abgebrochen' end
      store:intent('layout',{task=task.id,before=I.snapshot()})
      local good,err=verifyInputs(task.recipe)
      store:finish(); if not good then return nil,err end
      turtle.select(16)
      local made,why=I.action(store,'craft',function() return turtle.craft(1) end,{task=task.id,recipe=task.recipe})
      if not made then return nil,why or 'Rezept nicht von turtle.craft unterstuetzt' end
      local valid,why=I.checkCraft(task.recipe); if not valid then return nil,why end
      return {crafted=1}
    elseif task.kind=='park' then return {parked=true}
    else
      local block,err=nav:inspect(task.target); if not block then return nil,err end
      if task.kind=='inspect' then return {block=block} end
      if block=='air' then return {block='air'} end
      local classification=U.copy(config.blockRoles or {})
      if task.expected and task.role then classification[task.expected]=task.role end
      local role,why=J.classify(block,classification)
      if role~=s.role or block.name~=task.expected then return {block=block,changed=true,reason=why} end
      local permitted,reason=self:gate(); if not permitted then return nil,reason end
      local dir
      for i,p in ipairs(U.neighbors(nav.state.pos)) do if U.eq(p,task.target) then dir=i end end
      local fn=dir==5 and turtle.digUp or dir==6 and turtle.digDown or turtle.dig
      local dug,digError=I.action(store,'dig',fn,{target=task.target,task=task.id})
      local after=nav:inspect(task.target)
      if not dug and after~='air' then return nil,digError or 'Block nicht abbaubar' end
      return {block=after}
    end
  end
  function self:heartbeat()
    while true do
      local nextBeat=U.now()+5
      local ok,data=net:rpc(config.manager,'HEARTBEAT',report(),4)
      if ok then s.control=data.control; s.contact=U.now() end
      sleep(math.max(0.1,nextBeat-U.now()))
    end
  end
  function self:main()
    local role,e=I.role(config.profession); assert(role,e); s.role=role
    if d.intent and d.intent.kind~='move' and d.intent.kind~='turn' then
      local good,why=I.recover(store); if not good then s.issue=why end
    end
    local ok,err=nav:recover()
    if not ok then s.issue=err; s.status='blocked' end
    while not s.registered do
      local accepted,reply,why=net:rpc(config.manager,'HELLO',report(),8)
      if accepted then
        s.registered=true; s.park=reply.park; s.headingHint=reply.heading; s.control=reply.control
        if not d.intent then s.issue=nil end
        if reply.placed then nav.state.heading=reply.heading end
        for _,p in ipairs(reply.route or {}) do nav.state.map[U.key(p)]='air' end
      else s.issue=why; sleep(2) end
      store:save()
    end
    while true do
      if not d.intent and s.service then self:service() end
      if s.task and s.task.kind~='park' and s.control=='abbrechen' then
        local accepted=net:rpc(config.manager,'CANCELLED',{task=s.task.id},5)
        if accepted then s.task=nil; s.issue=nil; s.needs=nil; s.status='idle'; store:save() end
      end
      if s.review then
        local ok,e=true,nil
        if d.intent and d.intent.kind~='move' and d.intent.kind~='turn' then ok,e=I.recover(store) end
        if ok then ok,e=nav:recover() end
        s.issue=not ok and e or nil
        s.review=nil; store:save()
      end
      if not nav.state.heading and not d.intent then
        if turtle.getFuelLevel()~='unlimited' and turtle.getFuelLevel()<1 then self:waitNeed('fuel') end
        local good,why=nav:calibrate(s.headingHint)
        if not good then s.issue=why end
      end
      if s.packing then sleep(0.5)
      elseif s.issue and not s.needs then
        s.status='blocked'; sleep(1)
      elseif s.task then
        local task=s.task
        local result=s.completed[task.id]
        if not task.accepted and not result then
          local accepted=net:rpc(config.manager,'ACCEPT',{task=task.id},8)
          if accepted then task.accepted=true; store:save() else sleep(0.5) end
        end
        if not result and task.accepted then
          local good,why=self:execute(task)
          if good then
            result=good
            nav:scan(); result.observations={}
            for _,p in ipairs(U.neighbors(nav.state.pos)) do result.observations[U.key(p)]=nav.state.map[U.key(p)] end
            s.completed[task.id]=result
            if s.craftReceipt and s.craftReceipt.task==task.id then s.craftReceipt=nil end
            store:save()
          else
            s.issue=why; s.status='blocked'; store:save()
            net:rpc(config.manager,'PROBLEM',{task=task.id,error=why},4)
          end
        end
        if result then
          local done=net:rpc(config.manager,'DONE',{task=task.id,result=result},8)
          if done then s.completed={[task.id]=result}; s.task=nil; s.status='idle'; store:save() end
        end
      else
        self:service()
        if not s.service and I.emptySlots()<2 then self:waitNeed('collect') end
        if not s.service and turtle.getFuelLevel()~='unlimited' and turtle.getFuelLevel()<256 then self:waitNeed('fuel') end
        local accepted,reply=net:rpc(config.manager,'POLL',report(),6)
        if accepted and reply.task then
          s.task=reply.task; s.issue=nil; store:save()
          local taken,_,why=net:rpc(config.manager,'ACCEPT',{task=s.task.id},6)
          if taken then s.task.accepted=true; store:save() end
          if not taken then
            s.status='accepting'; s.issue=nil; store:save()
            while not taken do
              sleep(0.5)
              taken,_,why=net:rpc(config.manager,'ACCEPT',{task=s.task.id},8)
              if taken then s.task.accepted=true; store:save() end
              if s.control=='abbrechen' then break end
            end
          end
        elseif accepted then s.control=reply.control; s.status='idle' end
        sleep(0.2)
      end
    end
  end
  -- Registration is per boot, never trusted from the previous session.
  s.registered=nil
  s.packing=nil
  return self
end
return W
