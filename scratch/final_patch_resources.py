
import os

def patch_harvest_service():
    path = r'c:\YJS\Roblox\Origin-WILD\src\ServerScriptService\Server\Services\HarvestService.lua'
    if not os.path.exists(path):
        print(f"File not found: {path}")
        return

    with open(path, 'rb') as f:
        content = f.read()

    start_marker = b'function HarvestService._spawnLoop()'
    end_marker = b'function HarvestService._despawnCheck()'

    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker)

    if start_idx == -1 or end_idx == -1:
        print(f"Markers not found in HarvestService.lua. start_idx={start_idx}, end_idx={end_idx}")
        return

    new_spawn_loop = b'''function HarvestService._spawnLoop()
\t-- \xed\x99\x9c\xec\x84\xb1 \xeb\x85\xb8\xeb\x93\x9c \xec\x88\x98 \xec\xb2\xb4\xed\x81\xac (\xec\x9e\x90\xeb\x8f\x99 \xec\x8a\xa4\xed\x8f\xb0 + \xec\x88\x98\xeb\x8f\x99 \xeb\xb0\xb0\xec\xb9\x98 \xeb\xaa\xa8\xeb\x91\x90 \xed\x8f\xac\xed\x95\xa8)
\tlocal totalActiveNodes = 0
\tfor _ in pairs(activeNodes) do
\t\ttotalActiveNodes = totalActiveNodes + 1
\tend
\t
\tif totalActiveNodes >= NODE_CAP then return end
\t
\t-- [\xec\x88\x98\xec\xa0\x95] \xed\x94\x8c\xeb\xa0\x88\xec\x9d\xb4\xec\x96\xb4 \xeb\xb0\x80\xec\xa7\x91\xeb\x8f\x84 \xea\xb8\xb0\xeb\xb0\x98 \xec\x8a\xa4\xed\x8f\xb0 \xec\xa0\x9c\xed\x95\x9c \xeb\xa1\x9c\xec\xa7\x81
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
\t-- \xea\xb7\xb8\xeb\xa3\xb9\xed\x99\x94\xeb\x90\x9c \xeb\x8c\x80\xed\x91\x9c \xed\x94\x8c\xeb\xa0\x88\xec\x9d\xb4\xec\x96\xb4 \xea\xb1\xb8\xec\xb2\x98\xec\x97\x90\xec\x84\x9c\xeb\xa7\x8c \xec\x8a\xa4\xed\x8f\xb0 \xec\x8b\x9c\xeb\x8f\x84
\tfor _, repHRP in ipairs(spawnRepresentativeParts) do
\t\t-- [\xec\x88\x98\xec\xa0\x95] \xec\x8a\xa4\xed\x8f\xb0 \xed\x99\x95\xeb\xa5\xa0 \xed\x95\x98\xed\x96\xa5 (20%%)
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
\tend
end\r\n\r\n'''.replace(b'\n', b'\r\n')

    new_content = content[:start_idx] + new_spawn_loop + content[end_idx:]
    with open(path, 'wb') as f:
        f.write(new_content)
    print("Successfully replaced _spawnLoop in HarvestService.lua")

def patch_balance():
    path = r'c:\YJS\Roblox\Origin-WILD\src\ReplicatedStorage\Shared\Config\Balance.lua'
    if not os.path.exists(path):
        print(f"File not found: {path}")
        return

    with open(path, 'rb') as f:
        content = f.read()

    # Increase spawning interval from 5 to 12
    old_interval = b'Balance.NODE_SPAWN_INTERVAL = 5'
    new_interval = b'Balance.NODE_SPAWN_INTERVAL = 12'

    if old_interval in content:
        content = content.replace(old_interval, new_interval)
        with open(path, 'wb') as f:
            f.write(content)
        print("Successfully updated NODE_SPAWN_INTERVAL in Balance.lua")
    else:
        print("Could not find NODE_SPAWN_INTERVAL in Balance.lua")

if __name__ == "__main__":
    patch_harvest_service()
    patch_balance()
