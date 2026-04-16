local f = io.open("src/ServerScriptService/Server/Services/DebuffService.lua", "r")
local content = f:read("*a")
f:close()

print("First 200 bytes as hex:")
for i=1, 200 do
    local b = content:byte(i)
    if b then
        io.write(string.format("%02X ", b))
    end
end
print("")
