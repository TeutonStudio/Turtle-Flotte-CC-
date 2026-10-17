-- Deterministic multi-computer CC:Tweaked simulation; no Minecraft/server required.
local Sim={}
local function copy(t)
  if type(t)~='table' then return t end
  local r={}; for k,v in pairs(t) do r[k]=copy(v) end; return r
end
local function serialize(t)
  if type(t)=='string' then return string.format('%q',t) end
  if type(t)~='table' then return tostring(t) end
  local r={'{'}; for k,v in pairs(t) do r[#r+1]='['..serialize(k)..']='..serialize(v)..',' end
  r[#r+1]='}'; return table.concat(r)
end
local function unserialize(s) local f=load('return '..s,'state','t',{}); if f then return f() end end
local dirs={{x=0,y=0,z=-1},{x=1,y=0,z=0},{x=0,y=0,z=1},{x=-1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=-1,z=0}}
local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function key(p) return p.x..','..p.y..','..p.z end
local function empty(inv) for s=1,16 do if not inv[s] then return s end end end
local function insert(inv,a,count,preferred,capacity)
  local left=count
  local order={}
  if preferred then order[1]=preferred end
  for s=1,capacity or 16 do if s~=preferred then order[#order+1]=s end end
  for _,s in ipairs(order) do
    local b=inv[s]
    if not b or b.name==a.name and not a.label and not b.label then
      local limit=a.name:match('turtle_') and 1 or 64
      local n=math.min(left,limit-(b and b.count or 0))
      if n>0 then if not b then b=copy(a); b.count=0; inv[s]=b end; b.count=b.count+n; left=left-n end
      if left==0 then break end
    end
  end
  return count-left
end
function Sim.new()
  local sim={time=0,world={},actors={},tasks={},logs={},dropped=0,duplicated=0,operations={},gps=true,network=true,nextId=100}
  function sim:chest(p,items)
    local c={name='minecraft:chest',inventory={},size=27}
    for _,a in ipairs(items or {}) do insert(c.inventory,a,a.count,nil,27) end
    self.world[key(p)]=c; return c
  end
  function sim:block(p,name,tags) self.world[key(p)]={name=name,tags=tags or {}} end
  function sim:addTask(actor,fn)
    self.tasks[#self.tasks+1]={actor=actor,co=coroutine.create(fn),wake=self.time}
  end
  function sim:run(seconds,untilFn)
    local limit=self.time+seconds
    while self.time<limit do
      if untilFn and untilFn() then return true end
      local ready=false
      for _,t in ipairs(self.tasks) do
        if t.actor.on and coroutine.status(t.co)~='dead' and t.wake<=self.time then
          ready=true
          local ok,delay=coroutine.resume(t.co)
          if not ok then error('Computer '..t.actor.id..': '..tostring(delay)..'\n'..debug.traceback(t.co),0) end
          t.wake=self.time+(delay or 0.01)
        end
      end
      self.time=self.time+(ready and 0.01 or 0.05)
    end
    return untilFn and untilFn() or false
  end
  function sim:computer(id,role,p,heading)
    local a={id=id,role=role,pos=copy(p),heading=heading or 2,inv={},selected=1,fuel=role=='koordinator' and 1000 or 0,files={},on=true,label='Turtle-'..id,inbox={},profession=role=='koordinator' and 'spitzhacke' or 'spitzhacke'}
    self.actors[id]=a; self.world[key(p)]={name='computercraft:turtle_normal',actor=a}
    local env=setmetatable({},{__index=_G}); a.env=env
    env._G=env; env.FLOTTE_ROOT=''
    env.dofile=function(path)
      local f,e=loadfile(path,'t',env); assert(f,e); return f()
    end
    env.sleep=function(n) coroutine.yield(n or 0.05) end
    env.print=function(...) local out={...}; for i,v in ipairs(out) do out[i]=tostring(v) end; sim.logs[#sim.logs+1]=id..': '..table.concat(out,' ') end
    env.textutils={serialize=serialize,unserialize=unserialize}
    env.os={epoch=function() return math.floor(sim.time*1000) end,getComputerID=function() return id end,getComputerLabel=function() return a.label end}
    env.fs={
      exists=function(p) return a.files[p]~=nil end,
      getDir=function(p) return p:match('^(.*)/[^/]+$') or '' end,
      makeDir=function() end,
      delete=function(p) a.files[p]=nil end,
      copy=function(from,to) assert(a.files[from]); assert(not a.files[to]); a.files[to]=a.files[from] end,
      move=function(from,to) assert(a.files[from],from..' missing'); assert(not a.files[to],to..' exists'); a.files[to],a.files[from]=a.files[from],nil end,
      open=function(p,mode)
        if mode=='r' then if not a.files[p] then return nil end; return {readAll=function() return a.files[p] end,close=function() end} end
        local s=''; return {write=function(v) s=s..v end,close=function() a.files[p]=s end}
      end,
    }
    env.gps={locate=function() if sim.gps then return a.pos.x,a.pos.y,a.pos.z end end}
    local function neighbor(side)
      return add(a.pos,dirs[side=='up' and 5 or side=='down' and 6 or a.heading])
    end
    local function peer(side) return sim.world[key(neighbor(side))] end
    local function inspect(side)
      local b=peer(side)
      if b then return true,{name=b.name,tags=copy(b.tags or {})} end
      return false,'No block to inspect'
    end
    local function physical(kind,meta)
      sim.operations[#sim.operations+1]={id=id,kind=kind,meta=copy(meta),time=sim.time}
      if sim.crash and sim.crash(a,kind,meta) then a.on=false; sim.crashed=a; sim.crash=nil end
      env.sleep(0.01)
    end
    local function move(direction)
      local pos=add(a.pos,dirs[direction]); if sim.world[key(pos)] then return false,'Movement obstructed' end
      if a.fuel<=0 then return false,'Out of fuel' end
      sim.world[key(a.pos)]=nil; a.pos=pos; sim.world[key(pos)]={name='computercraft:turtle_normal',actor=a}; a.fuel=a.fuel-1
      physical('move',pos); return true
    end
    local function drop(side,count)
      local item=a.inv[a.selected]; if not item then return false,'No items to drop' end
      local b=peer(side); if not b or not (b.inventory or b.actor) then return false,'No receiving inventory' end
      local inv=b.inventory or b.actor.inv
      local sent=insert(inv,item,math.min(item.count,count or 64),b.actor and b.actor.selected,b.size or 16)
      item.count=item.count-sent; if item.count==0 then a.inv[a.selected]=nil end
      physical('drop',{side=side,name=item.name,count=sent}); return sent>0
    end
    local function suck(side,count)
      local b=peer(side); if not b or not b.inventory then return false,'No inventory' end
      for slot=1,b.size or 27 do
        local item=b.inventory[slot]
        if item then
          local n=insert(a.inv,item,math.min(item.count,count or 64),a.selected)
          item.count=item.count-n; if item.count==0 then b.inventory[slot]=nil end
          physical('suck',{side=side,count=n}); return n>0
        end
      end
      return false,'No items'
    end
    local function dig(side)
      local p=neighbor(side); local b=sim.world[key(p)]
      if not b then return false,'Nothing to dig' end
      if b.inventory or b.name=='minecraft:bedrock' then return false,'Unbreakable block' end
      if b.actor then
        if b.actor.on then return false,'Running turtle' end
        local item={name=b.name,count=1,label=b.actor.label,computer=b.actor.id,profession=b.actor.profession}
        if insert(a.inv,item,1,a.selected)~=1 then return false,'Inventory full' end
      else
        local expected=b.tags['minecraft:mineable/shovel'] and 'schaufel' or b.tags['minecraft:logs'] and 'axt' or 'spitzhacke'
        if a.profession~=expected then return false,'Wrong tool' end
        local item={name=b.name,count=1}; if insert(a.inv,item,1,a.selected)~=1 then return false,'Inventory full' end
      end
      sim.world[key(p)]=nil; physical('dig',p); return true
    end
    env.turtle={
      forward=function() return move(a.heading) end,back=function() return move((a.heading+1)%4+1) end,
      up=function() return move(5) end,down=function() return move(6) end,
      turnRight=function() a.heading=a.heading%4+1; physical('turn'); return true end,
      turnLeft=function() a.heading=(a.heading+2)%4+1; physical('turn'); return true end,
      inspect=function() return inspect('front') end,inspectUp=function() return inspect('up') end,inspectDown=function() return inspect('down') end,
      dig=function() return dig('front') end,digUp=function() return dig('up') end,digDown=function() return dig('down') end,
      drop=function(n) return drop('front',n) end,dropUp=function(n) return drop('up',n) end,dropDown=function(n) return drop('down',n) end,
      suck=function(n) return suck('front',n) end,suckUp=function(n) return suck('up',n) end,suckDown=function(n) return suck('down',n) end,
      getFuelLevel=function() return a.fuel end,getFuelLimit=function() return 20000 end,
      getEquippedLeft=function()
        local names={spitzhacke='minecraft:diamond_pickaxe',schaufel='minecraft:diamond_shovel',axt='minecraft:diamond_axe',werkbank='minecraft:crafting_table'}
        return {name=names[a.profession]}
      end,
      getEquippedRight=function() return {name='computercraft:wireless_modem_advanced'} end,
      getItemDetail=function(slot,detailed)
        local item=a.inv[slot or a.selected]; if not item then return nil end
        return {name=item.name,count=item.count,nbt=item.computer and tostring(item.computer) or item.nbt,displayName=detailed and (item.label or item.name) or nil}
      end,
      getItemCount=function(slot) return a.inv[slot or a.selected] and a.inv[slot or a.selected].count or 0 end,
      getSelectedSlot=function() return a.selected end,
      select=function(slot) a.selected=slot; return true end,
      refuel=function(n)
        local item=a.inv[a.selected]
        if not item or (item.name~='minecraft:coal' and item.name~='minecraft:charcoal') then return false,'Not fuel' end
        if n==0 then return true end
        local used=math.min(n or item.count,item.count,math.ceil((20000-a.fuel)/80))
        item.count=item.count-used; a.fuel=a.fuel+80*used
        if item.count==0 then a.inv[a.selected]=nil end
        physical('refuel'); return used>0
      end,
      transferTo=function(slot,n)
        if slot==a.selected then return false end
        local item=a.inv[a.selected]; if not item then return false end
        local target=a.inv[slot]
        if target and target.name~=item.name then return false end
        local moved=math.min(n or item.count,item.count,64-(target and target.count or 0))
        if not target then target=copy(item); target.count=0; a.inv[slot]=target end
        target.count=target.count+moved; item.count=item.count-moved
        if item.count==0 then a.inv[a.selected]=nil end
        physical('transfer'); return moved>0
      end,
      place=function()
        local item=a.inv[a.selected]; local p=neighbor('front')
        if sim.world[key(p)] or not item or not item.computer then return false,'Cannot place turtle' end
        local w=sim.actors[item.computer] or sim:computer(item.computer,'arbeiter',p,a.heading)
        sim.world[key(w.pos)]=nil; w.pos=p; w.heading=a.heading; w.label=item.label; w.profession=item.profession; w.on=false
        sim.world[key(p)]={name=item.name,actor=w}
        a.inv[a.selected]=nil; physical('place',p); return true
      end,
      craft=function(n)
        assert(n==1)
        local slots={1,2,3,5,6,7,9,10,11}
        for _,r in pairs(sim.config.recipes) do
          local match=true
          for i,slot in ipairs(slots) do local item=a.inv[slot]; if (item and item.name or false)~=(r.grid[i] or false) then match=false end end
          if match then
            for _,slot in ipairs(slots) do if a.inv[slot] then a.inv[slot].count=a.inv[slot].count-1; if a.inv[slot].count==0 then a.inv[slot]=nil end end end
            insert(a.inv,{name=r.output,count=r.count},r.count,a.selected)
            for name,count in pairs(r.returns or {}) do insert(a.inv,{name=name,count=count},count) end
            physical('craft'); return true
          end
        end
        return false,'No matching recipes'
      end,
    }
    env.peripheral={
      getNames=function() return {'right'} end,
      hasType=function(side,t)
        assert(side~='up' and side~='down','Peripheral sides must be top/bottom')
        side=side=='top' and 'up' or side=='bottom' and 'down' or side
        if side=='right' then return t=='modem' end
        local b=peer(side); return b and (t=='inventory' and b.inventory~=nil or t=='computer' and b.actor~=nil) or false
      end,
      wrap=function(side)
        assert(side~='up' and side~='down','Peripheral sides must be top/bottom')
        side=side=='top' and 'up' or side=='bottom' and 'down' or side
        if side=='right' then return {isWireless=function() return true end} end
        local b=peer(side)
        if b and b.actor then return {
          getID=function() return b.actor.id end,
          getLabel=function() return b.actor.label end,
          isOn=function() return b.actor.on end,
          turnOn=function() if not b.actor.on then sim:start(b.actor) end end,
          shutdown=function() b.actor.on=false end,
        } end
        if b and b.inventory then return {} end
      end,
    }
    env.rednet={
      open=function() end,host=function() end,
      send=function(to,p)
        local dest=sim.actors[to]
        sim.messages=(sim.messages or 0)+1
        if sim.network and dest and (not sim.lossEvery or sim.messages%sim.lossEvery~=0) then
          dest.inbox[#dest.inbox+1]={id,copy(p)}
          if sim.duplicateEvery and sim.messages%sim.duplicateEvery==0 then dest.inbox[#dest.inbox+1]={id,copy(p)}; sim.duplicated=sim.duplicated+1 end
        else sim.dropped=sim.dropped+1 end
        return dest~=nil
      end,
      receive=function(_,timeout)
        local deadline=sim.time+(timeout or 1)
        repeat
          local p=table.remove(a.inbox,1)
          if p then return p[1],p[2] end
          env.sleep(0.01)
        until sim.time>=deadline
      end,
    }
    return a
  end
  function sim:start(a)
    for _,t in ipairs(self.tasks) do if t.actor==a then t.co=coroutine.create(function() end) end end
    a.on=true; a.inbox={}
    local env=a.env
    local S=env.dofile('v2/store.lua'); local N=env.dofile('v2/net.lua')
    a.store=S.open('.flotte/state',{version=2})
    a.net=N.open(a.store,'test')
    local c=a.role=='koordinator' and self.config or {role='arbeiter',manager=1,fleet='test',blockRoles={}}
    a.app=env.dofile(a.role=='koordinator' and 'v2/coordinator.lua' or 'v2/worker.lua').new(c,a.store,a.net)
    self:addTask(a,function() a.net:run() end)
    self:addTask(a,function() a.app:main() end)
    if a.role~='koordinator' then self:addTask(a,function() a.app:heartbeat() end) end
  end
  return sim
end
function Sim.fixture(professions)
  local sim=Sim.new()
  local function dock(x,z) return {pos={x=x,y=0,z=z},heading=2,side='down'} end
  sim.config={role='koordinator',fleet='test',base={x=0,y=0,z=0},heading=2,start=dock(4,2),coal=dock(0,2),output=dock(2,2),deploy={pos={x=4,y=0,z=0},heading=2,side='front'},parks={},recipes={},materials={},blockRoles={},protected={['4,-1,2']=true,['0,-1,2']=true,['2,-1,2']=true}}
  local items={}
  for i,profession in ipairs(professions or {'spitzhacke'}) do
    sim.config.parks[i]={x=5+2*(i-1),y=0,z=2}
    items[i]={name='computercraft:turtle_normal',count=1,label='worker-'..(100+i),computer=100+i,profession=profession}
  end
  sim.startChest=sim:chest({x=4,y=-1,z=2},items)
  sim.coalChest=sim:chest({x=0,y=-1,z=2},{{name='minecraft:coal',count=256}})
  sim.outputChest=sim:chest({x=2,y=-1,z=2})
  sim.manager=sim:computer(1,'koordinator',sim.config.base,2)
  sim:start(sim.manager)
  return sim
end
Sim.copy=copy; Sim.serialize=serialize; Sim.unserialize=unserialize; Sim.key=key
return Sim
