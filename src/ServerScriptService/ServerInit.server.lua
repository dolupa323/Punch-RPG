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

local HungerService = require(Services.HungerService)
HungerService.Init(NetController)

local PlayerStatService = require(Services.PlayerStatService)
PlayerStatService.Init(NetController, SaveService, DataService, StaminaService)
for command, handler in pairs(PlayerStatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

WorldDropService.Init(NetController, DataService, InventoryService, TimeService, PlayerStatService)

local TechService = require(Services.TechService)
TechService.Init(NetController, DataService, PlayerStatService, SaveService, InventoryService)
for command, handler in pairs(TechService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local EquipService = require(Services.EquipService)
EquipService.Init(DataService, TechService)

InventoryService.Init(NetController, DataService, SaveService, PlayerStatService, EquipService)

local StorageService = require(Services.StorageService)
for command, handler in pairs(StorageService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local FacilityService = require(Services.FacilityService)
FacilityService.Init(NetController, DataService, InventoryService, nil, Balance, RecipeService, WorldDropService, TechService)
for command, handler in pairs(FacilityService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local BuildService = require(Services.BuildService)
BuildService.Init(NetController, DataService, InventoryService, SaveService, TechService, PlayerStatService)
BuildService.SetFacilityService(FacilityService)
BuildService.SetWorldDropService(WorldDropService)
for command, handler in pairs(BuildService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

DL = require(Services.DurabilityService)
DL.Init(NetController, InventoryService, DataService, BuildService, Balance)

local CraftingService = require(Services.CraftingService)
CraftingService.Init(NetController, DataService, InventoryService, BuildService, RecipeService, TechService, PlayerStatService, WorldDropService, TimeService)
for command, handler in pairs(CraftingService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

FacilityService.SetBuildService(BuildService)

local DebuffService = require(Services.DebuffService)
DebuffService.Init(NetController, TimeService, DataService, StaminaService, FacilityService, InventoryService)
for command, handler in pairs(DebuffService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local CreatureService = require(Services.CreatureService)
CreatureService.Init(NetController, DataService, WorldDropService, DebuffService, PlayerStatService)
for command, handler in pairs(CreatureService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local CombatService = require(Services.CombatService)
CombatService.Init(NetController, DataService, CreatureService, InventoryService, DurabilityService, DebuffService, WorldDropService, PlayerStatService, HungerService, TechService)
for command, handler in pairs(CombatService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local EnhanceService = require(Services.EnhanceService)
EnhanceService.Init()

local SkillService = require(Services.SkillService)
SkillService.Init(NetController, PlayerStatService, SaveService)
for command, handler in pairs(SkillService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
CombatService.SetSkillService(SkillService)

local ActiveSkillService = require(Services.ActiveSkillService)
ActiveSkillService.Init(NetController, SkillService, CombatService, CreatureService, InventoryService, DataService, PlayerStatService, DebuffService, StaminaService, HungerService)
for command, handler in pairs(ActiveSkillService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local PlayerLifeService = require(Services.PlayerLifeService)
PlayerLifeService.Init(NetController, DataService, InventoryService, BuildService)
for command, handler in pairs(PlayerLifeService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local PalboxService = require(Services.PalboxService)
PalboxService.Init(NetController, DataService, SaveService)
for command, handler in pairs(PalboxService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

local CaptureService = require(Services.CaptureService)
CaptureService.Init(NetController, CreatureService, InventoryService, SkillService, PlayerStatService)
for command, handler in pairs(CaptureService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

FacilityService.SetPalboxService(PalboxService)

local PalAIService = require(Services.PalAIService)
PalAIService.Init(NetController, CreatureService, DataService, PalboxService, BuildService)
FacilityService.SetPalAIService(PalAIService)

local PartyService = require(Services.PartyService)
PartyService.Init(NetController, PalboxService, CreatureService, SaveService)
for command, handler in pairs(PartyService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("PartyService", PartyService)

local HarvestService = require(Services.HarvestService)
HarvestService.Init(NetController, DataService, InventoryService, PlayerStatService, DurabilityService, WorldDropService, TechService)
for command, handler in pairs(HarvestService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
CreatureService.SetHarvestService(HarvestService)
ServiceRegistry.Register("HarvestService", HarvestService)

local BaseClaimService = require(Services.BaseClaimService)
BaseClaimService.Init(NetController, SaveService, BuildService)
BuildService.SetBaseClaimService(BaseClaimService)
for command, handler in pairs(BaseClaimService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("BaseClaimService", BaseClaimService)

StorageService.Init(NetController, SaveService, InventoryService, BuildService, BaseClaimService)
ServiceRegistry.Register("StorageService", StorageService)

-- [무협 RPG 대전환] 공룡 부족 자동 수납/채집 백그라운드 스케줄 연산 영구 비활성화
-- local AutoHarvestService = require(Services.AutoHarvestService)
-- AutoHarvestService.Init(HarvestService, FacilityService, BaseClaimService, PalboxService, DataService, BuildService, PalAIService)

-- local AutoDepositService = require(Services.AutoDepositService)
-- AutoDepositService.Init(FacilityService, StorageService, BaseClaimService, BuildService, DataService, PalboxService, PalAIService)

-- NPCShopService 초기화
local NPCShopService = require(Services.NPCShopService)
NPCShopService.Init(NetController, DataService, InventoryService, TimeService)
for command, handler in pairs(NPCShopService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("NPCShopService", NPCShopService)

-- QuestService Remastered Init (조건부 피처 토글 구동)
local TutorialQuestService
if Balance.ENABLE_QUEST_SYSTEM then
	TutorialQuestService = require(Services.TutorialQuestService)
	TutorialQuestService.Init(NetController, SaveService, PlayerStatService, InventoryService, NPCShopService)
	for command, handler in pairs(TutorialQuestService.GetHandlers()) do
		NetController.RegisterHandler(command, handler)
	end
	ServiceRegistry.Register("TutorialQuestService", TutorialQuestService)

	-- 액션 콜백 연결
	InventoryService.SetQuestItemCallback(function(userId, itemId, count) TutorialQuestService.onItemAdded(userId, itemId, count) end)
	HarvestService.SetQuestCallback(function(userId, nodeType) TutorialQuestService.onHarvest(userId, nodeType) end)
	CraftingService.SetQuestCallback(function(userId, recipeId) TutorialQuestService.onCrafted(userId, recipeId) end)
	BuildService.SetQuestCallback(function(userId, facilityId) TutorialQuestService.onBuilt(userId, facilityId) end)
	CombatService.SetQuestCallback(function(userId, creatureId) TutorialQuestService.onKilled(userId, creatureId) end)
	InventoryService.SetQuestFoodEatenCallback(function(userId, itemId) TutorialQuestService.onFoodEaten(userId, itemId) end)
end

local TotemService = require(Services.TotemService)
TotemService.Init(NetController, SaveService, BaseClaimService, BuildService, NPCShopService)
for command, handler in pairs(TotemService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
BuildService.SetTotemService(TotemService)
StorageService.SetTotemService(TotemService)
FacilityService.SetTotemService(TotemService)
CreatureService.SetProtectedZoneChecker(function(position) return TotemService.getProtectionInfoAt(position) end)
ServiceRegistry.Register("TotemService", TotemService)

local BlockBuildService = require(Services.BlockBuildService)
BlockBuildService.Init(NetController, DataService, InventoryService, SaveService, PlayerStatService)
BlockBuildService.SetBaseClaimService(BaseClaimService)
BlockBuildService.SetTotemService(TotemService)
BlockBuildService.SetWorldDropService(WorldDropService)
BlockBuildService.SetDurabilityService(DurabilityService)
if Balance.ENABLE_QUEST_SYSTEM and TutorialQuestService then
	BlockBuildService.SetQuestCallback(function(userId, blockTypeId) TutorialQuestService.onBuilt(userId, blockTypeId) end)
end
for command, handler in pairs(BlockBuildService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("BlockBuildService", BlockBuildService)

for command, handler in pairs(StaminaService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
CombatService.SetStaminaService(StaminaService)

local CharacterSetupService = require(Services.CharacterSetupService)
CharacterSetupService.Init()
ServiceRegistry.Register("CharacterSetupService", CharacterSetupService)

local PortalService = require(Services.PortalService)
PortalService.Init(NetController, SaveService, InventoryService, HarvestService, CreatureService, NPCShopService)
for command, handler in pairs(PortalService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
ServiceRegistry.Register("PortalService", PortalService)

local TutorialService = require(Services.TutorialService)
TutorialService.Init(NetController, SaveService, PlayerStatService, InventoryService)
for command, handler in pairs(TutorialService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end
CreatureService.SetTutorialService(TutorialService)
ServiceRegistry.Register("TutorialService", TutorialService)

local AdminCommandService = require(Services.AdminCommandService)
AdminCommandService.Init(NetController, PlayerStatService, InventoryService, TechService, TutorialService, SaveService)
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

print("[ServerInit] Server initialized (No-BOM) - AdminCommandService, BotService & Avatar Elements Ready")