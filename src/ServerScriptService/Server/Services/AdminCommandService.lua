-- AdminCommandService.lua
-- 마케팅 및 테스트용 관리자 명령어 서비스
-- !reset, !level [n] 등 명령어 처리

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminCommandService = {}

-- Dependencies
local NetController
local PlayerStatService
local InventoryService
local TechService
local TutorialService
local SaveService
local Balance = require(ReplicatedStorage.Shared.Config.Balance)

local RunService = game:GetService("RunService")

-- 관리자 권한 확인 (Balance 공통 설정 참조)
local function isAdmin(player: Player)
	return RunService:IsStudio() or (Balance.ADMIN_IDS and Balance.ADMIN_IDS[player.UserId] == true)
end

--========================================
-- Core Logic
--========================================

--- 테스트용 강화 아이템 세트 지급
local function giveEnhanceSet(player: Player)
	if not InventoryService then return end
	local userId = player.UserId
	
	InventoryService.addItem(userId, "ALCHEMY_STONE_MID", 10)
	InventoryService.addItem(userId, "ALCHEMY_STONE_HIGH", 10)
	InventoryService.addItem(userId, "3586927112", 10) -- 하락방지권
	InventoryService.addItem(userId, "3586927381", 10) -- 파괴방지권
	InventoryService.addItem(userId, "REPAIR_TICKET_LOW", 10)  -- 하급 수리권 10개 지급
	InventoryService.addItem(userId, "REPAIR_TICKET_HIGH", 10) -- 상급 수리 키트 10개 지급
	InventoryService.addItem(userId, "SWORD_IRON", 1)  -- 테스트용 무기
	
	print(string.format("[AdminCommandService] Enhancement test set given to %s", player.Name))
end

--- 계정 완전 초기화 (마케팅용)
local function resetAccount(player: Player)
	local userId = player.UserId
	print(string.format("[AdminCommandService] Resetting account for %s (%d)", player.Name, userId))

	-- 1. 인벤토리 초기화 (SaveService 직접 조작이 가장 확실함)
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.inventory = { slots = {}, maxSlots = Balance.BASE_INVENTORY_SLOTS or 20 }
			state.equipment = { HEAD = nil, SUIT = nil, HAND = nil }
			return state
		end)
	end

	-- 2. 레벨 및 스탯 초기화 (Level 1)
	if PlayerStatService and PlayerStatService.debugSetLevel then
		PlayerStatService.debugSetLevel(userId, 1)
		-- 스탯 투자 초기화
		SaveService.updatePlayerState(userId, function(state)
			state.stats.statPoints = 0
			state.stats.techPoints = 0
			state.stats.statInvested = {
				MAX_HEALTH = 0,
				MAX_STAMINA = 0,
				INV_SLOTS = 0,
				ATTACK = 0,
				DEFENSE = 0,
			}
			state.stats.techPointsSpent = 0
			return state
		end)
	end

	-- 3. 기술 해금 초기화
	if TechService and TechService.relinquish then
		TechService.relinquish(userId)
	end

	-- 4. 튜토리얼 리셋 및 즉시 시작
	if TutorialService and TutorialService.startTutorial then
		TutorialService.startTutorial(userId)
	end

	print(string.format("[AdminCommandService] Account reset complete for %s", player.Name))
	return true
end

--========================================
-- Handlers for UI
--========================================

local function handleFullReset(player: Player, payload: any)
	local success = resetAccount(player)
	return { success = success }
end

local function handleSetLevel(player: Player, payload: any)
	local level = tonumber(payload and payload.level)
	if not level then return { success = false } end
	
	local success = PlayerStatService.debugSetLevel(player.UserId, level)
	return { success = success }
end

local function handleGiveEnhanceSet(player: Player, payload: any)
	giveEnhanceSet(player)
	return { success = true }
end

--========================================
-- Command Parser
--========================================

local function processCommand(player: Player, message: string)
	-- ! 또는 / 로 시작하는 것만 처리
	local prefix = message:sub(1, 1)
	if prefix ~= "!" and prefix ~= "/" then return end

	-- 관리자 권한 확인 (isAdmin 함수 사용)
	if not isAdmin(player) then
		warn(string.format("[AdminCommandService] Unauthorized command attempt by %s", player.Name))
		return
	end

	local content = message:sub(2)
	local args = content:split(" ")
	local command = args[1]:lower()

	if command == "reset" or command == "초기화" then
		resetAccount(player)
	elseif command == "enhance" or command == "강화" then
		giveEnhanceSet(player)
	elseif (command == "level" or command == "레벨") and args[2] then
		local lv = tonumber(args[2])
		if lv and PlayerStatService.debugSetLevel then
			PlayerStatService.debugSetLevel(player.UserId, lv)
		end
	end
end

--========================================
-- Lifecycle
--========================================

function AdminCommandService.Init(_NetController, _PlayerStatService, _InventoryService, _TechService, _TutorialService, _SaveService)
	NetController = _NetController
	PlayerStatService = _PlayerStatService
	InventoryService = _InventoryService
	TechService = _TechService
	TutorialService = _TutorialService
	SaveService = _SaveService

	-- UI용 핸들러 등록
	if NetController then
		NetController.RegisterHandler("Admin.FullReset.Request", handleFullReset)
		NetController.RegisterHandler("Admin.SetLevel.Request", handleSetLevel)
		NetController.RegisterHandler("Admin.GiveEnhanceSet.Request", handleGiveEnhanceSet)
	end

	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			processCommand(player, message)
		end)
	end)

	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		player.Chatted:Connect(function(message)
			processCommand(player, message)
		end)
	end

	print("[AdminCommandService] Initialized")
end

return AdminCommandService
