local function check(path)
    local f, err = loadfile(path)
    if not f then
        print("Syntax Error [" .. path .. "]:", err)
    else
        print("Syntax OK [" .. path .. "]")
    end
end

check("src/ServerScriptService/Server/Services/HazardService.lua")
check("src/ServerScriptService/ServerInit.server.lua")

