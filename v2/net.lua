local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local N={NAME='flotte_v2',VERSION=2}
function N.open(store, fleet)
  local opened=false
  for _,side in ipairs(peripheral.getNames()) do
    if peripheral.hasType(side,'modem') then
      local m=peripheral.wrap(side)
      if m.isWireless() then rednet.open(side); opened=true end
    end
  end
  assert(opened,'Funkmodem fehlt')
  local d=store.data
  d.net=d.net or {counter=0,replies={},order={}}
  d.net.boot=(d.net.boot or 0)+1; store:save()
  local self={id=os.getComputerID(),fleet=fleet,session=tostring(d.net.boot),pending={}}
  local function packet(kind,payload,id)
    return {version=2,fleet=fleet,from=self.id,session=self.session,id=id,kind=kind,payload=payload or {}}
  end
  function self:send(target,kind,payload)
    d.net.counter=d.net.counter+1; store:save()
    local p=packet(kind,payload,self.id..':'..self.session..':'..d.net.counter)
    rednet.send(target,p,N.NAME); return p
  end
  function self:rpc(target,kind,payload,timeout)
    local p=self:send(target,kind,payload)
    local deadline=U.now()+(timeout or 16)
    local retry=U.now()+0.6+(d.net.counter%7)*0.07
    while U.now()<deadline do
      local reply=self.pending[p.id]
      if reply then self.pending[p.id]=nil; return reply.ok,reply.data,reply.error end
      sleep(0.2)
      if U.now()>=retry then rednet.send(target,p,N.NAME); retry=U.now()+0.7+(d.net.counter%5)*0.09 end
    end
    return false,nil,'Keine Bestaetigung von '..target..' fuer '..kind
  end
  function self:receive(sender,p)
    if type(p)~='table' or p.version~=2 or p.fleet~=fleet or p.from~=sender or type(p.id)~='string' or #p.id>160 or type(p.session)~='string' or type(p.payload)~='table' then return end
    if p.kind=='REPLY' then
      local waiting=self.waiting and self.waiting[p.payload.replyTo]
      if waiting and waiting==sender then self.pending[p.payload.replyTo]=p.payload end
      return
    end
    local key=sender..':'..p.id
    local reply=d.net.replies[key]
    if not reply then
      local handled,ok,data,err=pcall(self.handler,sender,p.kind,p.payload,p.session)
      if not handled then
        if tostring(ok)=='Terminated' then error(ok,0) end
        err='Nachricht abgewiesen: '..tostring(ok); ok=false; data=nil
      end
      reply={replyTo=p.id,ok=ok==true,data=data,error=err}
      -- Read-only status/poll/step requests are intentionally not journalled at 5 Hz.
      if p.kind~='STATUS' and p.kind~='SERVICE_STATUS' and p.kind~='ROUTE' and p.kind~='HEARTBEAT' and p.kind~='POLL' and p.kind~='RESERVE' then
        d.net.replies[key]=reply; d.net.order[#d.net.order+1]=key
        while #d.net.order>512 do d.net.replies[table.remove(d.net.order,1)]=nil end
        store:save()
      end
    end
    rednet.send(sender,packet('REPLY',reply,p.id..':reply'),N.NAME)
  end
  local originalRpc=self.rpc
  function self:rpc(target,kind,payload,timeout)
    -- Register before sending, as an adjacent turtle can reply immediately.
    self.waiting=self.waiting or {}
    local id=self.id..':'..self.session..':'..(d.net.counter+1)
    self.waiting[id]=target
    local ok,data,err=originalRpc(self,target,kind,payload,timeout)
    self.waiting[id]=nil; self.pending[id]=nil
    return ok,data,err
  end
  function self:run()
    while true do
      local sender,p=rednet.receive(N.NAME,0.5)
      if sender then self:receive(sender,p) end
    end
  end
  return self
end
return N
