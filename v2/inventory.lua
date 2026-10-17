local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local I={fuel={['minecraft:coal']=true,['minecraft:charcoal']=true}}
function I.snapshot()
  local out={}
  for slot=1,16 do
    local a=turtle.getItemDetail(slot)
    if a then out[slot]={name=a.name,count=a.count,nbt=a.nbt} end
  end
  return out
end
function I.emptySlots()
  local n=0; for s=1,16 do if turtle.getItemCount(s)==0 then n=n+1 end end; return n
end
function I.count(name)
  local n=0; for _,a in pairs(I.snapshot()) do if not name or a.name==name then n=n+a.count end end; return n
end
function I.refuel(store,target,reserved)
  if turtle.getFuelLevel()=='unlimited' then return true end
  local available={}
  for name in pairs(I.fuel) do available[name]=math.max(0,I.count(name)-((reserved or {})[name] or 0)) end
  for s=1,16 do
    local a=turtle.getItemDetail(s)
    if a and I.fuel[a.name] then
      turtle.select(s)
      while turtle.getItemCount(s)>0 and available[a.name]>0 and turtle.getFuelLevel()<math.min(target,turtle.getFuelLimit()) do
        store:intent('refuel',{before=I.snapshot(),fuel=turtle.getFuelLevel()})
        local ok,e=turtle.refuel(1); store:finish()
        if not ok then return false,e end
        available[a.name]=available[a.name]-1
      end
    end
  end
  return turtle.getFuelLevel()>=math.min(target,turtle.getFuelLimit())
end
local function itemCounts(snapshot)
  local r={}; for _,a in pairs(snapshot or {}) do r[a.name]=(r[a.name] or 0)+a.count end; return r
end
local function account(store,meta,kind)
  if not meta.account then return true end
  local before,after=itemCounts(meta.before),itemCounts(I.snapshot())
  local delta=(after[meta.account.name] or 0)-(before[meta.account.name] or 0)
  if kind=='drop' then delta=-delta end
  if delta<0 or delta>(meta.count or 64) then return false,'Uebergabemenge im Journal unklar' end
  for _,entry in ipairs(meta.account.entries) do
    local t=store.data
    for i=1,#entry.path-1 do t=t[entry.path[i]]; if not t then return false,'Buchungsziel fehlt' end end
    local k=entry.path[#entry.path]
    if entry.value~=nil then
      if delta==(meta.count or 1) then t[k]=entry.value end
    else
      local n=(t[k] or 0)+delta*(entry.sign or 1)
      t[k]=entry.zeroNil and n==0 and nil or n
      if entry.zeroNil and n==0 then t[k]=nil end
    end
  end
  return true
end
function I.action(store,kind,fn,meta)
  meta=meta or {}; meta.before=I.snapshot()
  store:intent(kind,meta)
  local result={fn()}
  if kind=='craft' and result[1] and store.data.worker then store.data.worker.craftReceipt=U.copy(meta) end
  local ok,e=account(store,meta,kind); if not ok then return false,e end
  store:finish(); return table.unpack(result)
end
function I.checkCraft(recipe)
  local actual=itemCounts(I.snapshot())
  local expected=U.copy(recipe.returns or {}); expected[recipe.output]=(expected[recipe.output] or 0)+recipe.count
  for name,n in pairs(expected) do if actual[name]~=n then return false,'Craftingausgabe stimmt nicht: '..name end end
  for name,n in pairs(actual) do if expected[name]~=n then return false,'Unerwarteter Craftingrest: '..name end end
  return true
end
function I.transfer(store,side,mode,count,booking)
  local fn=mode=='drop' and (side=='up' and turtle.dropUp or side=='down' and turtle.dropDown or turtle.drop)
    or (side=='up' and turtle.suckUp or side=='down' and turtle.suckDown or turtle.suck)
  return I.action(store,mode, function() return fn(count) end,{side=side,count=count,slot=turtle.getSelectedSlot(),account=booking})
end
function I.recover(store)
  local a=store.data.intent
  if not a then return true end
  if a.kind=='drop' or a.kind=='suck' then
    local ok,e=account(store,a.meta,a.kind); if not ok then return false,e end
    store:finish(); return true
  elseif a.kind=='refuel' or a.kind=='layout' or a.kind=='dig' then
    -- These actions are re-evaluated from current fuel, recipe totals or block inspection.
    store:finish(); return true
  elseif a.kind=='craft' then
    local recipe=a.meta.recipe; local actual=itemCounts(I.snapshot())
    local expected=U.copy(recipe.returns or {}); expected[recipe.output]=(expected[recipe.output] or 0)+recipe.count
    local same=true
    for name,n in pairs(expected) do if actual[name]~=n then same=false end end
    for name,n in pairs(actual) do if expected[name]~=n then same=false end end
    if same and store.data.worker then
      store.data.worker.completed[a.meta.task]={crafted=1}; store:finish(); return true
    end
    return false,'Crafting unterbrochen: Rezeptausgabe nicht eindeutig bestaetigt; Zutaten/Ergebnis manuell pruefen'
  end
  return false,'Physischer Vorgang benoetigt gesonderte Wiederherstellung: '..a.kind
end
function I.assertChest(side)
  local name=U.peripheralSide(side)
  if not peripheral.hasType(name,'inventory') then return false,'Erwartete Truhe fehlt an '..side end
  return true
end
function I.unload(store,side,keepFuel)
  local ok,e=I.assertChest(side); if not ok then return false,e end
  for s=1,16 do
    local a=turtle.getItemDetail(s)
    if a and not (keepFuel and I.fuel[a.name]) then
      turtle.select(s)
      local good,err=I.transfer(store,side,'drop',a.count)
      if not good or turtle.getItemCount(s)>0 then return false,err or 'Ergebnislager voll' end
    end
  end
  return true
end
function I.receiveSlot()
  for slot=1,16 do if turtle.getItemCount(slot)==0 then turtle.select(slot); return slot end end
end
function I.role(configured)
  if not turtle.getEquippedLeft or not turtle.getEquippedRight then
    return nil,'CC:Tweaked mit getEquippedLeft/Right erforderlich; Ausstattung kann nicht sicher geprueft werden'
  end
  local roles={['minecraft:diamond_pickaxe']='spitzhacke',['minecraft:diamond_shovel']='schaufel',['minecraft:diamond_axe']='axt',['minecraft:crafting_table']='werkbank',['computercraft:crafting_table']='werkbank'}
  local role
  for _,f in ipairs({turtle.getEquippedLeft,turtle.getEquippedRight}) do
    local a=f()
    if a and roles[a.name] then if role then return nil,'Genau ein Arbeitswerkzeug erforderlich' end; role=roles[a.name] end
  end
  if not role then return nil,'Kein unterstuetztes Werkzeug erkannt' end
  if configured and role~=configured then return nil,'Konfigurierter Beruf passt nicht zum Werkzeug' end
  return role
end
return I
