local f, err = loadfile("src/ServerScriptService/Server/Services/MobSpawnService.lua")
if not f then
    print("Syntax Error:", err)
else
    print("Syntax OK")
end
