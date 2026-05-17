-- ServerInit.server.lua
-- 서버 초기화 스크립트

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local Services = Server:WaitForChild("Services")

local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local ServiceRegistry = require(Shared:WaitForChild("Utils"):WaitForChild("ServiceRegistry"))
local GameEventBus = require(Shared:WaitForChild("Utils"):WaitForChild("GameEventBus"))

local function initCollisionGroups()
	local groups = {"Players", "Creatures", "CombatCreatures", "Structures", "Resources"}
	for _, group in ipairs(groups) do
		pcall(function() PhysicsService:RegisterCollisionGroup(group) end)
	end
	PhysicsService:CollisionGroupSetCollidable("Creatures", "Creatures", false)
	PhysicsService:CollisionGroupSetCollidable("Creatures", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("CombatCreatures", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("CombatCreatures", "Creatures", false)
	PhysicsService:CollisionGroupSetCollidable("CombatCreatures", "CombatCreatures", false)
	print("[ServerInit] Collision groups initialized")
end

initCollisionGroups()

local DataService = require(Services.DataService)
DataService.Init()
ServiceRegistry.Register("DataService", DataService)

local NetController = require(Controllers.NetController)
NetController.Init()
ServiceRegistry.Register("NetController", NetController)

local RecipeService = require(Services.RecipeService)
RecipeService.Init(DataService)
for command, handler in pairs(RecipeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("RecipeService", RecipeService)

local TimeService = require(Services.TimeService)
TimeService.Init(NetController)
for command, handler in pairs(TimeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("TimeService", TimeService)

local SaveService = require(Services.SaveService)
SaveService.Init(NetController)
for command, handler in pairs(SaveService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("SaveService", SaveService)

local InventoryService = require(Services.InventoryService)
for command, handler in pairs(InventoryService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("InventoryService", InventoryService)

local DurabilityService = require(Services.DurabilityService)
for command, handler in pairs(DurabilityService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("DurabilityService", DurabilityService)

local WorldDropService = require(Services.WorldDropService)
for command, handler in pairs(WorldDropService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("WorldDropService", WorldDropService)

local function handleInventoryDropWithWorldDrop(player, payload)
	local slot = payload.slot
	local count = payload.count
	local success, errorCode, data = InventoryService.drop(player, slot, count)
	if not success then return { success = false, errorCode = errorCode } end
	local dropped = data.dropped
	if dropped then
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dropPos = hrp.Position + hrp.CFrame.LookVector * 2 + Vector3.new(0, -1, 0)
				local spawnOk, _, spawnData = WorldDropService.spawnDrop(dropPos, dropped.itemId, dropped.count, dropped.durability)
				if spawnOk then data.worldDrop = spawnData end
			end
		end
	end
	return { success = true, data = data }
end

local function handleInventoryDropByItemIdWithWorldDrop(player, payload)
	local itemId = payload.itemId
	local count = payload.count
	local success, errorCode, data = InventoryService.dropByItemId(player, itemId, count)
	if not success then return { success = false, errorCode = errorCode } end
	
	local dropped = data.dropped
	if dropped then
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dropPos = hrp.Position + hrp.CFrame.LookVector * 2 + Vector3.new(0, -1, 0)
				local spawnOk, _, spawnData = WorldDropService.spawnDrop(dropPos, dropped.itemId, dropped.count, dropped.durability)
				if spawnOk then data.worldDrop = spawnData end
			end
		end
	end
	return { success = true, data = data }
end

NetController.RegisterHandler("Inventory.Drop.Request", handleInventoryDropWithWorldDrop)
NetController.RegisterHandler("Inventory.DropByItemId.Request", handleInventoryDropByItemIdWithWorldDrop)

local StaminaService = require(Services.StaminaService)
StaminaService.Init(NetController)

local PlayerStatService = require(Services.PlayerStatService)
PlayerStatService.Init(NetController, SaveService, DataService, StaminaService)
for command, handler in pairs(PlayerStatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

WorldDropService.Init(NetController, DataService, InventoryService, TimeService, PlayerStatService)

local EquipService = require(Services.EquipService)
EquipService.Init(DataService, nil) -- TechService removed

InventoryService.Init(NetController, DataService, SaveService, PlayerStatService, EquipService)

local StorageService = require(Services.StorageService)
for command, handler in pairs(StorageService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

DL = require(Services.DurabilityService)
DL.Init(NetController, InventoryService, DataService, nil, Balance) -- BuildService removed

local CraftingService = require(Services.CraftingService)
CraftingService.Init(NetController, DataService, InventoryService, nil, RecipeService, nil, PlayerStatService, WorldDropService, TimeService) -- BuildService removed
for command, handler in pairs(CraftingService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- [RPG CORE] Services
local DebuffService = require(Services.DebuffService)
DebuffService.Init(NetController, TimeService, DataService, StaminaService, nil, InventoryService)
for command, handler in pairs(DebuffService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local EnhanceService = require(Services.EnhanceService)
EnhanceService.Init()

local PlayerLifeService = require(Services.PlayerLifeService)
PlayerLifeService.Init(NetController, DataService, InventoryService, nil)
for command, handler in pairs(PlayerLifeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

StorageService.Init(NetController, SaveService, InventoryService)
ServiceRegistry.Register("StorageService", StorageService)

-- NPCShopService 초기화
local NPCShopService = require(Services.NPCShopService)
NPCShopService.Init(NetController, DataService, InventoryService, TimeService)
for command, handler in pairs(NPCShopService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("NPCShopService", NPCShopService)

for command, handler in pairs(StaminaService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local CharacterSetupService = require(Services.CharacterSetupService)
CharacterSetupService.Init()
ServiceRegistry.Register("CharacterSetupService", CharacterSetupService)

local PortalService = require(Services.PortalService)
PortalService.Init(NetController, SaveService, InventoryService, nil, nil, NPCShopService) -- HarvestService removed
for command, handler in pairs(PortalService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("PortalService", PortalService)

local AdminCommandService = require(Services.AdminCommandService)
AdminCommandService.Init(NetController, PlayerStatService, InventoryService, nil, nil, SaveService) -- TechService removed
ServiceRegistry.Register("AdminCommandService", AdminCommandService)

local BotService = require(Services.BotService)
BotService.Init()
ServiceRegistry.Register("BotService", BotService)

-- [무협 아바타 RPG] 코어 서비스 전격 초기화
local AvatarService = require(Services.AvatarService)
AvatarService.Init()
ServiceRegistry.Register("AvatarService", AvatarService)

local MobSpawnService = require(Services.MobSpawnService)
MobSpawnService.Init()
ServiceRegistry.Register("MobSpawnService", MobSpawnService)

local WeaponCrafterService = require(Services.WeaponCrafterService)
WeaponCrafterService.Init(NetController)
ServiceRegistry.Register("WeaponCrafterService", WeaponCrafterService)

local SkillService = require(Services.SkillService)
SkillService.Init(NetController, PlayerStatService, SaveService)
for command, handler in pairs(SkillService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("SkillService", SkillService)

print("[ServerInit] RPG Core initialized - Legacy systems removed")