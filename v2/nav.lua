local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local V={}
function V.path(map,start,goal,occupied)
  if U.eq(start,goal) then return {} end
  local q={start}; local seen={[U.key(start)]=true}; local prev={}; local head=1
  while q[head] and head<=16384 do
    if head%128==0 and sleep then sleep(0) end
    local p=q[head]; head=head+1
    for _,n in ipairs(U.neighbors(p)) do
      local k=U.key(n)
      if not seen[k] and map[k]=='air' and not (occupied and occupied(k)) then
        seen[k]=true; prev[k]=p
        if U.eq(n,goal) then
          local route={n}; local a=p
          while not U.eq(a,start) do table.insert(route,1,a); a=prev[U.key(a)] end
          return route
        end
        q[#q+1]=n
      end
    end
  end
  return nil,'Kein bekannter freier Weg nach '..U.key(goal)
end
function V.new(store, opts)
  opts=opts or {}
  local d=store.data; d.nav=d.nav or {map={}}
  local s=d.nav
  local self={state=s,blocked=opts.blocked,claim=opts.claim,arrived=opts.arrived}
  function self:locate()
    local x,y,z=gps.locate(2,false)
    if not x then return nil,'GPS ausgefallen' end
    return U.pos({x=math.floor(x+0.5),y=math.floor(y+0.5),z=math.floor(z+0.5)})
  end
  function self:recover()
    local p,err=self:locate(); if not p then return false,err end
    local intent=d.intent
    if intent and intent.kind=='move' then
      if not U.eq(p,intent.meta.from) and not U.eq(p,intent.meta.to) and not (intent.meta.calibrating and U.dist(p,intent.meta.from)==1 and p.y==intent.meta.from.y) then return false,'Position nach Neustart unklar' end
      s.pos=p; s.map[U.key(p)]='air'; store:finish()
      if self.arrived then self.arrived(intent.meta.from,p) end
    elseif intent and intent.kind=='turn' then
      s.heading=nil; s.pos=p; store:finish()
    elseif intent then return false,'Ungeklaerter Vorgang '..intent.kind..': weiter pruefen:ja nach Inventarpruefung' end
    if s.pos and not U.eq(s.pos,p) then
      s.pos=p; s.heading=nil; store:save()
      return false,'Turtle wurde versetzt; Blickrichtung neu einrichten'
    end
    s.pos=p; s.map[U.key(p)]='air'; store:save(); return true
  end
  function self:calibrate(hint)
    if s.heading then return true end
    if not hint then return false,'Blickrichtung fehlt; einrichten richtung:north|east|south|west' end
    local blocked=turtle.inspect()
    if blocked then return false,'Kalibrierung benoetigt einen freien Block vor der Turtle' end
    local before,err=self:locate(); if not before then return false,err end
    local target=U.add(before,U.dirs[hint])
    for h=1,4 do
      if self.blocked and self.blocked(U.key(U.add(before,U.dirs[h]))) then return false,'Kalibrierung braucht freie reservierbare Nachbarplaetze' end
    end
    if opts.calibrationClaim then local ok,e=opts.calibrationClaim(before); if not ok then return false,e end
    elseif self.claim then local ok,e=self.claim(before,target); if not ok then return false,e end end
    store:intent('move',{from=before,to=target,calibrating=true})
    local ok,e=turtle.forward()
    if not ok then store:finish(); if self.arrived then self.arrived(before,before) end; return false,e end
    local after=self:locate()
    if not after then return false,'GPS nach Kalibrierung ausgefallen' end
    local heading
    for i=1,4 do if U.eq(after,U.add(before,U.dirs[i])) then heading=i end end
    s.pos=after; s.heading=heading; s.map[U.key(before)]='air'; s.map[U.key(after)]='air'
    store:finish()
    if self.arrived then self.arrived(before,after) end
    if heading~=hint then return false,'Blickrichtung stimmt nicht mit Einrichtung ueberein; neu einrichten' end
    return true
  end
  function self:face(h)
    if not s.heading then return false,'Blickrichtung unbekannt' end
    while s.heading~=h do
      store:intent('turn',{from=s.heading,to=s.heading%4+1})
      local ok,err=turtle.turnRight()
      if not ok then store:finish(); return false,err end
      s.heading=s.heading%4+1; store:finish()
    end
    return true
  end
  function self:inspect(target)
    local direction
    for i,n in ipairs(U.neighbors(s.pos)) do if U.eq(n,target) then direction=i end end
    if not direction then return nil,'Ziel nicht benachbart' end
    local ok,data
    if direction<=4 then
      local good,e=self:face(direction); if not good then return nil,e end
      ok,data=turtle.inspect()
    elseif direction==5 then ok,data=turtle.inspectUp()
    else ok,data=turtle.inspectDown() end
    local value=ok and data or 'air'
    s.map[U.key(target)]=value; store:save()
    return value
  end
  function self:scan()
    for _,p in ipairs(U.neighbors(s.pos)) do self:inspect(p) end
  end
  function self:step(target)
    if opts.beforeStep then local ok,e=opts.beforeStep(target); if not ok then return false,e end end
    local before=self:locate()
    if not before then return false,'GPS ausgefallen' end
    if not U.eq(before,s.pos) then return false,'Position weicht von Bewegungsaufzeichnung ab' end
    if U.dist(before,target)~=1 then return false,'Bewegung muss genau einen Block betragen' end
    if self.claim then local ok,e=self.claim(before,target); if not ok then return false,e end end
    local block,err=self:inspect(target)
    if block~='air' then
      if self.arrived then self.arrived(before,before) end
      return false,err or 'Weg blockiert: '..U.key(target)
    end
    local fn=target.y>s.pos.y and turtle.up or target.y<s.pos.y and turtle.down or turtle.forward
    store:intent('move',{from=before,to=target})
    local moved,e=fn()
    if not moved then store:finish(); if self.arrived then self.arrived(before,before) end; return false,e end
    local after=self:locate()
    if not after then return false,'GPS nach Bewegung ausgefallen' end
    if not U.eq(after,target) then return false,'Unerwartete GPS-Position nach Bewegung' end
    s.pos=target; s.map[U.key(target)]='air'; store:finish()
    if self.arrived then local ok,e=self.arrived(before,target); if not ok then return false,e end end
    return true
  end
  function self:go(goal, explore)
    if not U.pos(goal) then return false,'Ungueltiger Standplatz' end
    local attempts=0
    while not U.eq(s.pos,goal) do
      if d.intent then return false,'Physischer Vorgang muss zuerst geklaert werden' end
      if explore then self:scan() end
      local path=V.path(s.map,s.pos,goal,self.blocked)
      if not path and opts.route then
        local ok,e=opts.route(goal)
        if not ok then return false,e end
        path=V.path(s.map,s.pos,goal,self.blocked)
      end
      if not path and explore then
        -- Explore only air inside a bounded corridor enclosing start and destination.
        local best,score
        for key,value in pairs(s.map) do
          if value=='air' then
            local p=U.pos(key)
            if math.abs(p.x-goal.x)+math.abs(p.z-goal.z)+math.abs(p.y-goal.y)<=U.dist(s.pos,goal)+8 then
              local frontier=false
              for _,n in ipairs(U.neighbors(p)) do if s.map[U.key(n)]==nil then frontier=true end end
              local route=frontier and V.path(s.map,s.pos,p,self.blocked)
              local cost=route and (#route+U.dist(p,goal))
              if cost and (not score or cost<score) then best,score=route,cost end
            end
          end
        end
        path=best
      end
      if not path or #path==0 then return false,'Kein freier Zugang zu '..U.key(goal)..'; Zugang freiraeumen und weiter ausfuehren' end
      local fuel=turtle.getFuelLevel()
      if fuel~='unlimited' and fuel<1 then return false,'Eigener Treibstoff leer' end
      local ok,e=self:step(path[1])
      if not ok then
        if e=='Weg reserviert; warten' and opts.route then opts.route(goal); sleep(0.3)
        else return false,e end
      end
      attempts=attempts+1
      if attempts>4096 then return false,'Erkundungsgrenze erreicht; kuerzeren freien Zugang einrichten' end
    end
    return true
  end
  function self:dock(dock, explore)
    local ok,e=self:go(dock.pos,explore); if not ok then return false,e end
    return self:face(dock.heading)
  end
  return self
end
return V
