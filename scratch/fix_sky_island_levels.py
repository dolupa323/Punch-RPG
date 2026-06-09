file_path = r"c:\YJS\Roblox\RPG\src\ReplicatedStorage\Data\MobSpawnData.lua"

with open(file_path, 'rb') as f:
    content = f.read()

# Define the additions using .encode('utf-8')
content = content.replace(
    b'spawnAreaId = "NormalGhostKnightZone",',
    b'spawnAreaId = "NormalGhostKnightZone",\n\t\tlevel = 38, -- ' + "유령기사 레벨 38".encode('utf-8')
)

content = content.replace(
    b'spawnAreaId = "GhostWizardZone",',
    b'spawnAreaId = "GhostWizardZone",\n\t\tlevel = 43, -- ' + "유령마법사 레벨 43".encode('utf-8')
)

content = content.replace(
    b'spawnAreaId = "GhostKnightZone",',
    b'spawnAreaId = "GhostKnightZone",\n\t\tlevel = 48, -- ' + "유령기사(거인) 레벨 48".encode('utf-8')
)

content = content.replace(
    b'spawnAreaId = "SkyIsland_BlueFlameKnight",',
    b'spawnAreaId = "SkyIsland_BlueFlameKnight",\n\t\tlevel = 53, -- ' + "푸른불꽃의 기사 레벨 53".encode('utf-8')
)

with open(file_path, 'wb') as f:
    f.write(content)

print("Successfully added levels to Sky Island monsters in MobSpawnData.lua!")
