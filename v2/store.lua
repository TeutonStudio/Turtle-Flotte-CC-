local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local S={}
-- Three independently validated generations survive interruption between rename operations.
function S.open(path, initial)
  local self={path=path,seq=0,data=U.copy(initial or {})}
  local found, valid=false,false
  for _,suffix in ipairs({'','.bak','.next'}) do
    local raw=U.read(path..suffix)
    if raw then
      found=true
      local ok,env=pcall(textutils.unserialize,raw)
      if ok and type(env)=='table' and type(env.body)=='string' and type(env.seq)=='number' and env.check==U.checksum(env.body) then
        local good,data=pcall(textutils.unserialize,env.body)
        if good and type(data)=='table' and env.seq>=self.seq then self.seq,self.data,valid=env.seq,data,true end
      end
    end
  end
  assert(not found or valid,'Alle Zustandsdateien beschaedigt: '..path..' (Sicherung wiederherstellen)')
  function self:save()
    self.seq=self.seq+1
    local body=textutils.serialize(self.data)
    U.write(self.path..'.next',textutils.serialize({seq=self.seq,body=body,check=U.checksum(body)}))
    if fs.exists(self.path) then
      if fs.exists(self.path..'.bak') then fs.delete(self.path..'.bak') end
      fs.move(self.path,self.path..'.bak')
    end
    fs.move(self.path..'.next',self.path)
  end
  function self:intent(kind,meta)
    assert(not self.data.intent,'Ungeklaerter physischer Vorgang: '..tostring(self.data.intent and self.data.intent.kind))
    self.data.intent={kind=kind,meta=U.copy(meta),time=U.now()}; self:save()
  end
  function self:finish() self.data.intent=nil; self:save() end
  return self
end
return S
