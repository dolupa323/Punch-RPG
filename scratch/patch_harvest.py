
import os

path = r'c:\YJS\Roblox\Origin-WILD\src\ServerScriptService\Server\Services\HarvestService.lua'
with open(path, 'rb') as f:
    content = f.read()

# 1. _spawnLoop replacement
old_spawn_loop = b'for _, player in ipairs(Players:GetPlayers()) do\r\n\t\tlocal char = player.Character\r\n\t\tif char and char:FindFirstChild(\"HumanoidRootPart\") then\r\n\t\t\t-- \xec\x8a\xa4\xed\x8f\xb0 \xed\x99\x95\xeb\xa5\xa0: 50%\r\n\t\t\tif math.random() <= 0.5 then\r\n\t\t\t\tlocal pos, material = HarvestService._findSpawnPosition(char.HumanoidRootPart)\r\n\t\t\t\tif pos and material then\r\n\t\t\t\t\t-- [\xec\x88\x98\xec\xa0\x95] \xed\x94\x8c\xeb\xa0\x88\xec\x9d\xb4\xec\x96\xb4 \xec\x9c\x84\xec\xb9\x98\xec\x9d\x98 Zone\xec\x97\x90 \xeb\xa7\x9e\xeb\x8a\x94 \xeb\xb0\x94\xeb\x8b\xac \xec\x9e\x90\xec\x9b\x90 \xec\x8a\xa4\xed\x8f\xb0\r\n\t\t\t\t\tlocal zoneName = SpawnConfig.GetZoneAtPosition(char.HumanoidRootPart.Position)\r\n\t\t\t\t\tlocal nodeId\r\n\t\t\t\t\tif zoneName then\r\n\t\t\t\t\t\tnodeId = SpawnConfig.GetRandomGroundHarvestForZone(zoneName)\r\n\t\t\t\t\telse\r\n\t\t\t\t\t\tnodeId = SpawnConfig.GetRandomGroundHarvest()\r\n\t\t\t\t\tend\r\n\t\t\t\t\tif nodeId then\r\n\t\t\t\t\t\tHarvestService._spawnAutoNode(nodeId, pos)\r\n\t\t\t\t\t\t\r\n\t\t\t\t\t\ttotalActiveNodes = totalActiveNodes + 1\r\n\t\t\t\t\t\tif totalActiveNodes >= NODE_CAP then break end\r\n\t\t\t\t\tend\r\n\t\t\t\tend\r\n\t\t\tend\r\n\t\tend\r\n\tend'

new_spawn_loop = b'''\t-- [\xec\x88\x98\xec\xa0\x95] \xed\x94\x8c\xeb\xa0\x88\xec\x9d\xb4\xec\x96\xb4 \xeb\xb0\x80\xec\xa7\x91\xeb\x8f\x84 \xea\xb8\xb0\xeb\xb0\x98 \xec\x8a\xa4\xed\x8f\xb0 \xec\xa0\x9c\xed\x95\x9c \xeb\xa1\x9c\xec\xa7\x81
\tlocal players = Players:GetPlayers()
\tlocal spawnRepresentativeParts = {}
\tlocal GROUP_RADIUS = 120 -- \xec\x9d\xb4 \xeb\xb0\x98\xea\xb2\xbd \xeb\x82\xb4 \xed\x94\x8c\xeb\xa0\x88\xec\x9d\xb4\xec\x96\xb4\xeb\x93\xa4\xec\x9d\x80 \xed\x95\x98\xeb\x82\x98\xec\x9d\x98 \xea\xb7\xb8\xeb\xa3\xb9\xec\x9c\xbc\xeb\xa1\x9c \xea\xb0\x84\xec\xa3\xbc
\t
\tfor _, player in ipairs(players) do
\t\tlocal char = player.Character
\t\tlocal hrp = char and char:FindFirstChild(\"HumanoidRootPart\")
\t\tif hrp then
\t\t\tlocal isNearGroup = false
\t\t\tfor _, repPart in ipairs(spawnRepresentativeParts) do
\t\t\t\tif (hrp.Position - repPart.Position).Magnitude < GROUP_RADIUS then
\t\t\t\t\tisNearGroup = true
\t\t\t\t\tbreak
\t\t\t\tend
\t\t\tend
\t\t\t
\t\t\tif not isNearGroup then
\t\t\t\ttable.insert(spawnRepresentativeParts, hrp)
\t\t\tend
\t\tend
\tend
\t
\t-- \xea\xb7\xb8\xeb\xa3\xb9\xed\x99\x94\xeb\x90\x9c \xeb\x8c\x80\xed\x91\x9c \xed\x94\x8c\xeb\xa0\x88\xec\x9d\xb4\xec\x96\xb4 \xea\xb1\xbc\xec\xb2\x98\xec\x97\x90\xec\x84\x9c\xeb\xa7\x8c \xec\x8a\xa4\xed\x8f\xb0 \xec\x8b\x9c\xeb\x8f\x84
\tfor _, repHRP in ipairs(spawnRepresentativeParts) do
\t\t-- [\xec\x88\x98\xec\xa0\x95] \xec\x8a\xa4\xed\x8f\xb0 \xed\x99\x95\xeb\xa5\xa0 \xed\x95\x98\xed\x96\xa5 (50% -> 20%)
\t\tif math.random() <= 0.2 then
\t\t\tlocal pos, material = HarvestService._findSpawnPosition(repHRP)
\t\t\tif pos and material then
\t\t\t\tlocal zoneName = SpawnConfig.GetZoneAtPosition(repHRP.Position)
\t\t\t\tlocal nodeId
\t\t\t\tif zoneName then
\t\t\t\t\tnodeId = SpawnConfig.GetRandomGroundHarvestForZone(zoneName)
\t\t\t\telse
\t\t\t\t\tnodeId = SpawnConfig.GetRandomGroundHarvest()
\t\t\t\tend
\t\t\t\tif nodeId then
\t\t\t\t\tHarvestService._spawnAutoNode(nodeId, pos)
\t\t\t\t\t
\t\t\t\t\ttotalActiveNodes = totalActiveNodes + 1
\t\t\t\t\tif totalActiveNodes >= NODE_CAP then break end
\t\t\t\tend
\t\t\tend
\t\tend
\tend'''.replace(b'\n', b'\r\n')

# 2. _replenishLoop replacement
old_replenish = b'for _, player in ipairs(Players:GetPlayers()) do\r\n\t\tif toSpawn <= 0 then break end\r\n\t\t\r\n\t\tlocal char = player.Character\r\n\t\tif char and char:FindFirstChild(\"HumanoidRootPart\") then\r\n\t\t\tlocal pos, material = HarvestService._findSpawnPosition(char.HumanoidRootPart)\r\n\t\t\tif pos and material then\r\n\t\t\t\tlocal nodeId = selectNodeForTerrain(material)\r\n\t\t\t\tif nodeId then\r\n\t\t\t\t\tlocal uid = HarvestService._spawnAutoNode(nodeId, pos)\r\n\t\t\t\t\tif uid then\r\n\t\t\t\t\t\ttoSpawn = toSpawn - 1\r\n\t\t\t\t\tend\r\n\t\t\t\tend\r\n\t\t\tend\r\n\t\tend\r\n\tend'

new_replenish = b'''\t-- [\xec\x88\x98\xec\xa0\x95] \xea\xb7\xb8\xeb\xa3\xb9\xed\x99\x94 \xea\xb8\xb0\xeb\xb0\x98 \xeb\xb3\xb4\xec\xb6\xa9 \xeb\xa1\x9c\xec\xa7\x81
\tlocal players = Players:GetPlayers()
\tlocal spawnRepresentativeParts = {}
\tlocal GROUP_RADIUS = 120
\t
\tfor _, player in ipairs(players) do
\t\tlocal char = player.Character
\t\tlocal hrp = char and char:FindFirstChild(\"HumanoidRootPart\")
\t\tif hrp then
\t\t\tlocal isNearGroup = false
\t\t\tfor _, repPart in ipairs(spawnRepresentativeParts) do
\t\t\t\tif (hrp.Position - repPart.Position).Magnitude < GROUP_RADIUS then
\t\t\t\t\tisNearGroup = true
\t\t\t\t\tbreak
\t\t\t\tend
\t\t\tend
\t\t\tif not isNearGroup then
\t\t\t\ttable.insert(spawnRepresentativeParts, hrp)
\t\t\tend
\t\tend
\tend
\t
\tfor _, repHRP in ipairs(spawnRepresentativeParts) do
\t\tif toSpawn <= 0 then break end
\t\t
\t\tlocal pos, material = HarvestService._findSpawnPosition(repHRP)
\t\tif pos and material then
\t\t\tlocal nodeId = selectNodeForTerrain(material)
\t\t\tif nodeId then
\t\t\t\tlocal uid = HarvestService._spawnAutoNode(nodeId, pos)
\t\t\t\tif uid then
\t\t\t\t\ttoSpawn = toSpawn - 1
\t\t\t\t\tend
\t\t\tend
\t\tend
\tend'''.replace(b'\n', b'\r\n')

if old_spawn_loop not in content:
    print('Failed to find old spawn loop')
else:
    content = content.replace(old_spawn_loop, new_spawn_loop)

if old_replenish not in content:
    print('Failed to find old replenish loop')
else:
    content = content.replace(old_replenish, new_replenish)

with open(path, 'wb') as f:
    f.write(content)
print('Successfully patched HarvestService.lua')
