-- TutorialQuestService.lua
-- RPG 전용 초반 튜토리얼 퀘스트 체인

local TutorialQuestService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local ServiceRegistry = require(Shared.Utils.ServiceRegistry)
local Balance = require(Shared.Config.Balance)

local initialized = false
local NetController
local SaveService
local InventoryService
local PlayerStatService

local questStates = {} -- [userId] = state table
local playerConnections = {} -- [userId] = { RBXScriptConnection, ... }

local QUEST_ID = "RPG_TUTORIAL"
local QUEST_TITLE = "튜토리얼 퀘스트"
local TOTAL_STEPS = 12
local QUEST_VERSION = 7
local QUEST_SCHEMA_VERSION = 1
local QUEST_RESET_MARKER = "RPG_TUTORIAL_RESET_20260612_V4"
local QUEST_SAVE_KEY = "rpgTutorialQuest"
local LEGACY_SAVE_KEY = "tutorialQuest"

local _getMobKillCount
local _countInventoryItem
local _hasInventoryOrEquipItem
local _hasEnhancedItem

local STEP_DEFS = {
	[1] = {
		id = "KILL_SLIME",
		currentStepText = "슬라임 잡기",
		stepCommand = "슬라임 1마리를 처치하세요.",
		stepKind = "KILL",
		stepCount = 1,
		rewardGold = 100,
	},
	[2] = {
		id = "COLLECT_SLIME_MUCUS",
		currentStepText = "슬라임 점액 모으기",
		stepCommand = "슬라임 점액 5개를 모으세요.",
		stepKind = "ITEM_ANY",
		stepCount = 5,
		rewardGold = 100,
		sync = function(userId, state, progress)
			progress.count = math.max(progress.count or 0, _countInventoryItem(userId, "SLIME_MUCUS"))
		end,
	},
	[3] = {
		id = "CRAFT_SOFTCLUB",
		currentStepText = "슬라임검 만들기",
		stepCommand = "슬라임검을 제작하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 100,
	},
	[4] = {
		id = "EQUIP_SOFTCLUB",
		currentStepText = "슬라임검 장착하기",
		stepCommand = "가방(I) 또는 캐릭터 창을 열어 제작한 슬라임검을 장착하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 100,
		sync = function(userId, state, progress)
			local hasEquipped = false
			if InventoryService and InventoryService.getInventory then
				local inv = InventoryService.getInventory(userId)
				if inv and inv.equipment and inv.equipment.HAND then
					if inv.equipment.HAND.itemId == "SoftClub" then
						hasEquipped = true
					end
				end
			end
			if hasEquipped then
				progress.count = 1
			else
				progress.count = 0
			end
		end,
	},
	[5] = {
		id = "DISTRIBUTE_STAT",
		currentStepText = "스탯 올리기",
		stepCommand = "장비창(스탯)을 열고 공격력 스탯을 1 올리세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 100,
		sync = function(userId, state, progress)
			local pStats = PlayerStatService and PlayerStatService.getStats(userId)
			local invested = pStats and pStats.statInvested
			local attackInvested = invested and invested[Enums.StatId.ATTACK] or 0
			progress.count = math.max(progress.count or 0, attackInvested)
		end,
	},
	[6] = {
		id = "KILL_HORNED_LARVA",
		currentStepText = "뿔 애벌레 잡기",
		stepCommand = "뿔 애벌레 5마리를 처치하세요.",
		stepKind = "KILL",
		stepCount = 5,
		rewardGold = 100,
	},
	[7] = {
		id = "CRAFT_GAKCHANG",
		currentStepText = "단단한 검 만들기",
		stepCommand = "단단한 검을 제작하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 100,
	},
	[8] = {
		id = "ENHANCE_GAKCHANG",
		currentStepText = "단단한 검 1강 강화해보기",
		stepCommand = "단단한 검을 +1 이상으로 강화하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 100,
	},
	[9] = {
		id = "REGISTER_POTION",
		currentStepText = "포션 단축키 등록하기",
		stepCommand = "HP/MP 포션을 구매하고, 가방(I)에서 소비 단축슬롯에 등록하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 100,
		sync = function(userId, state, progress)
			local saveState = SaveService and SaveService.getPlayerState(userId)
			local quickslots = saveState and saveState.quickslots or {}
			local hasPotionInQuickslot = false
			for _, itemId in ipairs(quickslots) do
				if itemId == "BASIC_HP_POTION" or itemId == "BASIC_MP_POTION" then
					hasPotionInQuickslot = true
					break
				end
			end
			if hasPotionInQuickslot then
				progress.count = 1
			end
		end,
	},
	[10] = {
		id = "COLLECT_STUMP_BARK",
		currentStepText = "숲의 검 재료 모으기",
		stepCommand = "스텀프 나무껍질 10개를 모으세요.",
		stepKind = "ITEM_ANY",
		stepCount = 10,
		rewardGold = 100,
		sync = function(userId, state, progress)
			progress.count = math.max(progress.count or 0, _countInventoryItem(userId, "STUMP_BARK"))
		end,
	},
	[11] = {
		id = "CRAFT_MOGWOLDO",
		currentStepText = "숲의 검 만들기",
		stepCommand = "숲의 검을 제작하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 200,
	},
	[12] = {
		id = "EQUIP_DASH",
		currentStepText = "스킬 장착하기",
		stepCommand = "스킬 탭(K)을 열어 스킬북을 배우고 패시브 슬롯에 대쉬를 장착하세요.",
		stepKind = "ITEM_ANY",
		stepCount = 1,
		rewardGold = 300,
		sync = function(userId, state, progress)
			local saveState = SaveService and SaveService.getPlayerState(userId)
			local equippedPassives = saveState and saveState.equippedPassives or {}
			local hasDashEquipped = false
			for k, v in pairs(equippedPassives) do
				if v == "SKILL_RUNE_DASH" then
					hasDashEquipped = true
					break
				end
			end
			if hasDashEquipped then
				progress.count = 1
			end
		end,
	},
}

local function _getDefaultState()
	return {
		active = true,
		completed = false,
		stepIndex = 1,
		startedAt = os.time(),
		completedAt = nil,
		progressByStep = {},
		version = QUEST_VERSION,
		schemaVersion = QUEST_SCHEMA_VERSION,
		resetMarker = QUEST_RESET_MARKER,
	}
end

local function _ensureState(userId: number)
	if not SaveService or not SaveService.getPlayerState then
		return nil
	end

	local saveState = SaveService.getPlayerState(userId)
	if not saveState then
		return nil
	end

	local state = saveState[QUEST_SAVE_KEY]
	local isValid = false
	if type(state) == "table" then
		local v = tonumber(state.version) or 0
		local m = tostring(state.resetMarker or "")
		if (v == 7 or v == 8) and (m == "RPG_TUTORIAL_RESET_20260612_V4" or m == "RPG_TUTORIAL_RESET_20260626_V1") then
			isValid = true
		end
	end

	if not isValid then
		state = _getDefaultState()
		saveState[QUEST_SAVE_KEY] = state
	end
	saveState[LEGACY_SAVE_KEY] = nil

	state.active = state.completed ~= true
	state.completed = state.completed == true
	state.stepIndex = math.clamp(math.floor(tonumber(state.stepIndex) or 1), 1, TOTAL_STEPS)
	
	-- 만약 예전에 모든 퀘스트를 완료(completed=true)했었으나, 새로운 퀘스트 단계가 추가되었다면 다시 활성화합니다.
	if state.completed and state.stepIndex < TOTAL_STEPS then
		state.completed = false
		state.active = true
		state.stepIndex = state.stepIndex + 1
	end
	
	if state.completed then
		state.active = false
		state.stepIndex = TOTAL_STEPS
	end
	state.progressByStep = type(state.progressByStep) == "table" and state.progressByStep or {}
	for i = 1, TOTAL_STEPS do
		state.progressByStep[i] = type(state.progressByStep[i]) == "table" and state.progressByStep[i] or {}
		state.progressByStep[i].count = math.max(0, math.floor(tonumber(state.progressByStep[i].count) or 0))
		state.progressByStep[i].done = state.progressByStep[i].done == true
	end

	questStates[userId] = state
	return state
end

local function _persistState(userId: number)
	if not SaveService or not SaveService.updatePlayerState then
		return
	end

	local state = questStates[userId]
	if not state then
		return
	end

	SaveService.updatePlayerState(userId, function(saveState)
		saveState[QUEST_SAVE_KEY] = state
		saveState[LEGACY_SAVE_KEY] = nil
		return saveState
	end)
end

local function _notify(player: Player?, text: string, color: string?)
	if not player or not NetController then
		return
	end
	NetController.FireClient(player, "Notify.Message", {
		text = text,
		color = color or "WHITE",
	})
end

local function _getGoldService()
	return ServiceRegistry.Get("NPCShopService")
end

local function _addGold(userId: number, amount: number)
	if amount <= 0 then
		return true
	end
	local goldService = _getGoldService()
	if goldService and goldService.addGold then
		local ok, err = goldService.addGold(userId, amount)
		if not ok then
			warn(string.format("[TutorialQuestService] Gold reward failed for user %d: %s", userId, tostring(err)))
		end
		return ok
	end

	warn(string.format("[TutorialQuestService] NPCShopService not ready while rewarding user %d", userId))
	return false
end

local function _getPlayer(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

_getMobKillCount = function(userId: number, mobDisplayName: string): number
	if not PlayerStatService or not PlayerStatService.getStats then
		return 0
	end

	local stats = PlayerStatService.getStats(userId)
	local mobKills = stats and stats.mobKills or {}
	return math.max(0, math.floor(tonumber(mobKills and mobKills[mobDisplayName]) or 0))
end

_countInventoryItem = function(userId: number, itemId: string): number
	if not InventoryService or not InventoryService.getInventory then
		return 0
	end

	local inv = InventoryService.getInventory(userId)
	if not inv then
		return 0
	end

	local total = 0
	for _, slotData in pairs(inv.slots or {}) do
		if slotData and slotData.itemId == itemId then
			total += tonumber(slotData.count) or 1
		end
	end

	for _, equipData in pairs(inv.equipment or {}) do
		if equipData and equipData.itemId == itemId then
			total += 1
		end
	end

	return total
end

_hasInventoryOrEquipItem = function(userId: number, itemId: string): boolean
	return _countInventoryItem(userId, itemId) > 0
end

_hasEnhancedItem = function(userId: number, itemId: string, minLevel: number): boolean
	if not InventoryService or not InventoryService.getInventory then
		return false
	end

	local inv = InventoryService.getInventory(userId)
	if not inv then
		return false
	end

	local function checkNode(node)
		if not node or node.itemId ~= itemId then
			return false
		end
		local level = tonumber(node.attributes and node.attributes.enhanceLevel) or 0
		return level >= minLevel
	end

	for _, slotData in pairs(inv.slots or {}) do
		if checkNode(slotData) then
			return true
		end
	end

	for _, equipData in pairs(inv.equipment or {}) do
		if checkNode(equipData) then
			return true
		end
	end

	return false
end

local function _getStepDef(stepIndex: number)
	return STEP_DEFS[stepIndex]
end

local function _getStepProgress(state, stepIndex: number)
	state.progressByStep = state.progressByStep or {}
	local progress = state.progressByStep[stepIndex]
	if type(progress) ~= "table" then
		progress = {}
		state.progressByStep[stepIndex] = progress
	end
	progress.count = math.max(0, math.floor(tonumber(progress.count) or 0))
	progress.done = progress.done == true
	return progress
end

local function _syncStepProgress(userId: number, state, stepIndex: number)
	local stepDef = _getStepDef(stepIndex)
	if not stepDef then
		return
	end

	local progress = _getStepProgress(state, stepIndex)
	if type(stepDef.sync) == "function" then
		stepDef.sync(userId, state, progress)
	end

	progress.count = math.max(0, math.floor(tonumber(progress.count) or 0))
	progress.done = progress.done == true or (progress.count >= (stepDef.stepCount or 1))
	state.progressByStep[stepIndex] = progress
end

local function _isStepSatisfied(state, stepIndex: number)
	local stepDef = _getStepDef(stepIndex)
	if not stepDef then
		return false
	end
	local progress = _getStepProgress(state, stepIndex)
	return progress.count >= (stepDef.stepCount or 1)
end

local function _buildStatus(userId: number)
	local state = _ensureState(userId)
	if not state then
		return {
			questId = QUEST_ID,
			active = false,
			completed = false,
			stepIndex = 0,
			totalSteps = TOTAL_STEPS,
		}
	end

	local stepIndex = math.clamp(state.stepIndex or 1, 1, TOTAL_STEPS)
	local stepDef = _getStepDef(stepIndex)
	_syncStepProgress(userId, state, stepIndex)
	local progress = _getStepProgress(state, stepIndex)

	if state.completed then
		return {
			questId = QUEST_ID,
			questName = QUEST_TITLE,
			active = false,
			completed = true,
			stepIndex = TOTAL_STEPS,
			totalSteps = TOTAL_STEPS,
			currentStepText = "튜토리얼 퀘스트를 모두 마쳤습니다.",
			stepCommand = "이제 RPG 루프를 자유롭게 진행하세요.",
			reward = { gold = 0 },
			rewardPreview = { gold = 0 },
			progress = { count = TOTAL_STEPS, done = true },
			stepKind = "ITEM_ANY",
			stepCount = 1,
			stepKey = "COMPLETED",
		}
	end

	return {
		questId = QUEST_ID,
		questName = QUEST_TITLE,
		active = state.active ~= false,
		completed = false,
		stepIndex = stepIndex,
		totalSteps = TOTAL_STEPS,
		stepKey = stepDef and stepDef.id or "UNKNOWN",
		currentStepText = stepDef and stepDef.currentStepText or "다음 목표를 확인하세요.",
		stepCommand = stepDef and stepDef.stepCommand or "",
		stepKind = stepDef and stepDef.stepKind or "ITEM_ANY",
		stepCount = stepDef and (stepDef.stepCount or 1) or 1,
		progress = {
			count = progress.count or 0,
			done = progress.done == true,
		},
		reward = { gold = (stepDef and stepDef.rewardGold) or 0 },
		rewardPreview = { gold = (stepDef and stepDef.rewardGold) or 0 },
	}
end

local function _broadcastStatus(userId: number)
	local player = _getPlayer(userId)
	if not player or not NetController then
		return
	end

	local status = _buildStatus(userId)
	NetController.FireClient(player, "Tutorial.Status.Changed", status)
	NetController.FireClient(player, "Quest.Status.Changed", status)
end

local function _grantCurrentStepReward(userId: number, stepIndex: number)
	local stepDef = _getStepDef(stepIndex)
	if not stepDef then
		return
	end

	local rewardGold = tonumber(stepDef.rewardGold) or 0
	if rewardGold > 0 then
		_addGold(userId, rewardGold)
	end

	-- 말랑봉 만들기 완료 시 플레이어가 레벨 2가 되어 스탯 포인트(3포인트)를 갖도록 처리
	if stepDef.id == "CRAFT_SOFTCLUB" then
		if PlayerStatService and PlayerStatService.getLevel then
			local currentLevel = PlayerStatService.getLevel(userId)
			if currentLevel < 2 then
				PlayerStatService.addXP(userId, 100, "TUTORIAL")
			end
		end
	elseif stepDef.id == "CRAFT_MOGWOLDO" then
		if InventoryService and InventoryService.addItem then
			InventoryService.addItem(userId, "BOOK_DASH", 1)
		end
	end
end

local function _updateProgressAndSync(userId: number)
	local state = _ensureState(userId)
	if not state then
		return
	end

	local stepIndex = math.clamp(state.stepIndex or 1, 1, TOTAL_STEPS)
	_syncStepProgress(userId, state, stepIndex)
	_persistState(userId)
	_broadcastStatus(userId)
end

local function _tryCompleteStep(userId: number): boolean
	local state = _ensureState(userId)
	if not state or state.completed then
		return false
	end

	local stepIndex = math.clamp(state.stepIndex or 1, 1, TOTAL_STEPS)
	_syncStepProgress(userId, state, stepIndex)
	local progress = _getStepProgress(state, stepIndex)
	local stepDef = _getStepDef(stepIndex)

	if progress.done or (stepDef and progress.count >= (stepDef.stepCount or 1)) then
		_grantCurrentStepReward(userId, stepIndex)

		if stepIndex >= TOTAL_STEPS then
			state.completed = true
			state.active = false
			state.completedAt = os.time()
			state.stepIndex = TOTAL_STEPS
		else
			state.stepIndex = stepIndex + 1
			state.active = true
			local nextProgress = _getStepProgress(state, state.stepIndex)
			nextProgress.count = 0
			nextProgress.done = false
		end

		_persistState(userId)
		_broadcastStatus(userId)
		return true
	end

	return false
end

local function _forceReset(userId: number)
	local saveState = SaveService and SaveService.getPlayerState and SaveService.getPlayerState(userId)
	if not saveState then
		return false
	end

	saveState[QUEST_SAVE_KEY] = _getDefaultState()
	saveState[LEGACY_SAVE_KEY] = nil
	questStates[userId] = saveState[QUEST_SAVE_KEY]
	_persistState(userId)
	_broadcastStatus(userId)
	return true
end

local function _forceSetStep(userId: number, stepIndex: number)
	local saveState = SaveService and SaveService.getPlayerState and SaveService.getPlayerState(userId)
	if not saveState then
		return false
	end

	local clamped = math.clamp(math.floor(tonumber(stepIndex) or 1), 1, TOTAL_STEPS)
	saveState[QUEST_SAVE_KEY] = saveState[QUEST_SAVE_KEY] or _getDefaultState()
	saveState[LEGACY_SAVE_KEY] = nil
	local state = saveState[QUEST_SAVE_KEY]
	state.active = true
	state.completed = false
	state.stepIndex = clamped
	state.progressByStep = state.progressByStep or {}
	state.progressByStep[clamped] = state.progressByStep[clamped] or { count = 0, done = false }
	questStates[userId] = state
	_persistState(userId)
	_broadcastStatus(userId)
	return true
end

local function _ensurePlayerHook(player: Player)
	local userId = player.UserId
	if playerConnections[userId] then
		return
	end

	playerConnections[userId] = {}

	local function attachElementWatcher()
		local current = player:GetAttribute("Element")
		if type(current) == "string" and current ~= "" and current ~= "None" then
			_updateProgressAndSync(userId)
		else
			_broadcastStatus(userId)
		end
	end

	table.insert(playerConnections[userId], player:GetAttributeChangedSignal("Element"):Connect(function()
		_updateProgressAndSync(userId)
	end))

	task.delay(0.3, function()
		if player.Parent then
			attachElementWatcher()
		end
	end)
end

local function _cleanupPlayer(userId: number)
	local conns = playerConnections[userId]
	if conns then
		for _, conn in ipairs(conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
	end
	playerConnections[userId] = nil
	questStates[userId] = nil
end

function TutorialQuestService.OnEquipmentChanged(userId: number)
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	if state.stepIndex == 4 or state.stepIndex == 12 then
		_updateProgressAndSync(userId)
	end
end

function TutorialQuestService.OnElementChanged(userId: number)
	_updateProgressAndSync(userId)
end

function TutorialQuestService.OnMobKilled(userId: number, mobDisplayName: string)
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	local stepIndex = state.stepIndex or 1
	local progress = _getStepProgress(state, stepIndex)

	if stepIndex == 1 and mobDisplayName == "슬라임" then
		progress.count = (progress.count or 0) + 1
		state.progressByStep[stepIndex] = progress
		_updateProgressAndSync(userId)
	elseif stepIndex == 6 and mobDisplayName == "뿔 애벌레" then
		progress.count = (progress.count or 0) + 1
		state.progressByStep[stepIndex] = progress
		_updateProgressAndSync(userId)
	end
end

function TutorialQuestService.OnItemAdded(userId: number, itemId: string, added: number)
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	if state.stepIndex == 2 and itemId == "SLIME_MUCUS" then
		local progress = _getStepProgress(state, 2)
		progress.count = (progress.count or 0) + added
		state.progressByStep[2] = progress
		_persistState(userId)
		_updateProgressAndSync(userId)
	elseif state.stepIndex == 10 and itemId == "STUMP_BARK" then
		local progress = _getStepProgress(state, 10)
		progress.count = (progress.count or 0) + added
		state.progressByStep[10] = progress
		_persistState(userId)
		_updateProgressAndSync(userId)
	end
end

function TutorialQuestService.OnCraftCompleted(userId: number, recipeId: string)
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	local stepIndex = state.stepIndex or 1
	local progress = _getStepProgress(state, stepIndex)

	if stepIndex == 3 and recipeId == "CraftSoftClub" then
		progress.count = 1
		state.progressByStep[stepIndex] = progress
		_updateProgressAndSync(userId)
	elseif stepIndex == 7 and recipeId == "CraftGakchang" then
		progress.count = 1
		state.progressByStep[stepIndex] = progress
		_updateProgressAndSync(userId)
	elseif stepIndex == 11 and recipeId == "CraftMogwoldo" then
		progress.count = 1
		state.progressByStep[stepIndex] = progress
		_updateProgressAndSync(userId)
	end
end

function TutorialQuestService.OnShopPurchased(userId: number, shopId: string, itemId: string, count: number)
	-- 포션 구매 자체로는 완료 처리하지 않고 단축키 등록 시점에 완료되도록 변경됨
end

function TutorialQuestService.OnQuickslotSaved(userId: number, quickslots: {string})
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	if state.stepIndex ~= 9 then
		return
	end

	local hasPotionInQuickslot = false
	for _, itemId in ipairs(quickslots) do
		if itemId == "BASIC_HP_POTION" or itemId == "BASIC_MP_POTION" then
			hasPotionInQuickslot = true
			break
		end
	end

	if hasPotionInQuickslot then
		local progress = _getStepProgress(state, 9)
		progress.count = 1
		state.progressByStep[9] = progress
		_tryCompleteStep(userId)
	end
end

function TutorialQuestService.OnEnhanceCompleted(userId: number, itemId: string, newLevel: number)
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	if state.stepIndex ~= 8 then
		return
	end

	if itemId ~= "Gakchang" or (tonumber(newLevel) or 0) < 1 then
		return
	end

	local progress = _getStepProgress(state, 8)
	progress.count = 1
	state.progressByStep[8] = progress
	_updateProgressAndSync(userId)
end

function TutorialQuestService.OnStatUpgraded(userId: number, statId: string)
	local state = _ensureState(userId)
	if not state or state.completed then
		return
	end

	if state.stepIndex ~= 5 or statId ~= Enums.StatId.ATTACK then
		return
	end

	local progress = _getStepProgress(state, 5)
	progress.count = 1
	state.progressByStep[5] = progress
	_updateProgressAndSync(userId)
end

function TutorialQuestService.StartForPlayer(userId: number)
	_ensureState(userId)
	_updateProgressAndSync(userId)
	return _buildStatus(userId)
end

function TutorialQuestService.GetStatus(userId: number)
	_ensureState(userId)
	_updateProgressAndSync(userId)
	return _buildStatus(userId)
end

function TutorialQuestService.GetList()
	local steps = {}
	for index = 1, TOTAL_STEPS do
		local def = STEP_DEFS[index]
		table.insert(steps, {
			index = index,
			id = def.id,
			title = def.currentStepText,
			description = def.stepCommand,
			reward = { gold = def.rewardGold or 0 },
		})
	end

	return {
		questId = QUEST_ID,
		questName = QUEST_TITLE,
		description = "게임 시작 후 바로 진행되는 RPG 입문 튜토리얼입니다.",
		steps = steps,
	}
end

function TutorialQuestService.Init(_NetController, _SaveService, _InventoryService, _PlayerStatService)
	if initialized then
		return
	end

	NetController = _NetController
	SaveService = _SaveService
	InventoryService = _InventoryService
	PlayerStatService = _PlayerStatService

	if InventoryService and InventoryService.SetQuestItemCallback then
		InventoryService.SetQuestItemCallback(function(userId, itemId, added)
			TutorialQuestService.OnItemAdded(userId, itemId, added)
		end)
	end
	
	local skillService = require(game:GetService("ServerScriptService").Server.Services.SkillService)
	if skillService and skillService.SetQuestEquipCallback then
		skillService.SetQuestEquipCallback(function(userId)
			TutorialQuestService.OnEquipmentChanged(userId)
		end)
	end

	local craftingService = require(game:GetService("ServerScriptService").Server.Services.CraftingService)
	if craftingService and craftingService.SetQuestCallback then
		craftingService.SetQuestCallback(function(userId, recipeId)
			TutorialQuestService.OnCraftCompleted(userId, recipeId)
		end)
	end

	local enhanceService = require(game:GetService("ServerScriptService").Server.Services.EnhanceService)
	if enhanceService and enhanceService.SetQuestCallback then
		enhanceService.SetQuestCallback(function(userId, itemId, newLevel)
			TutorialQuestService.OnEnhanceCompleted(userId, itemId, newLevel)
		end)
	end

	local shopService = require(game:GetService("ServerScriptService").Server.Services.NPCShopService)
	if shopService and shopService.SetQuestCallback then
		shopService.SetQuestCallback(function(userId, shopId, itemId, count)
			TutorialQuestService.OnShopPurchased(userId, shopId, itemId, count)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		_ensurePlayerHook(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_cleanupPlayer(player.UserId)
	end)

	if SaveService and SaveService.PlayerSaveLoaded and SaveService.PlayerSaveLoaded.Event then
		SaveService.PlayerSaveLoaded.Event:Connect(function(userId, _state)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				_ensurePlayerHook(player)
			end
			_ensureState(userId)
			_updateProgressAndSync(userId)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		_ensurePlayerHook(player)
		_ensureState(player.UserId)
		_broadcastStatus(player.UserId)
	end

	initialized = true
	print("[TutorialQuestService] Initialized")
end

local function _isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return Balance.ADMIN_IDS and Balance.ADMIN_IDS[player.UserId] == true
end

function TutorialQuestService.GetHandlers()
	return {
		["Tutorial.Start.Request"] = function(player, _payload)
			local status = TutorialQuestService.StartForPlayer(player.UserId)
			return { success = true, data = status }
		end,
		["Tutorial.GetStatus.Request"] = function(player, _payload)
			local status = TutorialQuestService.GetStatus(player.UserId)
			return { success = true, data = status }
		end,
		["Tutorial.Step.Complete.Request"] = function(player, _payload)
			local state = _ensureState(player.UserId)
			if not state or state.completed then
				return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
			end

			_tryCompleteStep(player.UserId)
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
		["Tutorial.Admin.Reset.Request"] = function(player, _payload)
			if not _isAdmin(player) then
				return { success = false, errorCode = Enums.ErrorCode.NO_PERMISSION }
			end
			local ok = _forceReset(player.UserId)
			if not ok then
				return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
			end
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
		["Tutorial.Admin.SetStep.Request"] = function(player, payload)
			if not _isAdmin(player) then
				return { success = false, errorCode = Enums.ErrorCode.NO_PERMISSION }
			end
			local stepIndex = payload and payload.stepIndex
			local ok = _forceSetStep(player.UserId, stepIndex)
			if not ok then
				return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
			end
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
		["Tutorial.Admin.ForceStart.Request"] = function(player, _payload)
			if not _isAdmin(player) then
				return { success = false, errorCode = Enums.ErrorCode.NO_PERMISSION }
			end
			local ok = _forceSetStep(player.UserId, 1)
			if not ok then
				return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
			end
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,

		["Quest.GetList.Request"] = function(player, _payload)
			return { success = true, data = { quests = { TutorialQuestService.GetList() } } }
		end,
		["Quest.Accept.Request"] = function(player, _payload)
			local status = TutorialQuestService.StartForPlayer(player.UserId)
			return { success = true, data = status }
		end,
		["Quest.Complete.Request"] = function(player, _payload)
			local state = _ensureState(player.UserId)
			if not state or state.completed then
				return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
			end
			_tryCompleteStep(player.UserId)
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
		["Quest.GetStatus.Request"] = function(player, _payload)
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
		["Quest.Step.Complete.Request"] = function(player, _payload)
			local state = _ensureState(player.UserId)
			if not state or state.completed then
				return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
			end
			_tryCompleteStep(player.UserId)
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
		["Quest.Admin.Reset.Request"] = function(player, _payload)
			if not _isAdmin(player) then
				return { success = false, errorCode = Enums.ErrorCode.NO_PERMISSION }
			end
			local ok = _forceReset(player.UserId)
			if not ok then
				return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
			end
			return { success = true, data = TutorialQuestService.GetStatus(player.UserId) }
		end,
	}
end

return TutorialQuestService
