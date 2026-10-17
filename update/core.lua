-- v2 updates are staged; this compatibility wrapper never deletes running code.
local core={}
function core.run()
  return shell.run(fs.exists(".flotte/installer.lua") and ".flotte/installer.lua" or "init.lua")
end
return core
