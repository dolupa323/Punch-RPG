-- TutorialQuestService.lua (QuestService Remastered)
-- NPC 기반 일일 선택형 퀘스트 시스템

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local QuestData = require(ReplicatedStorage.Data.QuestData)

local QuestService = {}

local initialized = false
local NetController = nil
local SaveService = nil
local PlayerStatService = nil
local InventoryService = nil
local NPCShopService = nil

local ADMIN_USER_IDS = {
	[10311679477] = true,
}

--========================================
-- Helper Logic
--========================================

local function getTodayString()
	local t = os.date("!*t") -- UTC 기준
	return string.format("%04d%02d%02d", t.year, t.month, t.day)
end

local function isAdminUser(userId)
	if userId == game.CreatorId then return true end
	return ADMIN_USER_IDS[userId] == true
end

local function getOrCreateProgress(userId)
	local state = SaveService and SaveService.getPlayerState(userId)
	if type(state) ~= "table" then return nil end

	if type(state.tutorialQuest) ~= "table" then
		state.tutorialQuest = {
			activeQuest = nil, -- 현재 진행중인 퀘스트 { id, progress, completed }
			lastQuestDate = "", -- 마지막으로 퀘스트를 수락한 날짜 (YYYYMMDD)
			completedCount = 0,
		}
	end
	
	-- 레거시 데이터 마이그레이션 (필요 시)
	if state.tutorialQuest.stepIndex then
		state.tutorialQuest = {
			activeQuest = nil,
			lastQuestDate = "",
			completedCount = 0,
		}
	end

	return state.tutorialQuest
end

local function serializeStatus(userId)
	local progress = getOrCreateProgress(userId)
	if not progress then return { active = false } end

	local active = progress.activeQuest
	local status = {
		active = active ~= nil,
		lastQuestDate = progress.lastQuestDate,
		isTodayDone = false, -- [테스트] 24시간 제한 해제
	}

	if active then
		local qData = nil
		-- QuestData에서 원본 데이터 찾기
		for tier, pool in pairs(QuestData.Quests) do
			for _, q in ipairs(pool) do
				if q.id == active.id then
					qData = q
					break
				end
			end
			if qData then break end
		end

		if qData then
			status.questId = active.id
			status.title = qData.title
			status.desc = qData.desc
			
			-- HUD 호환 필드
			status.stepKind = qData.kind
			status.progress = active.progress
			status.stepReady = active.completed
			status.stepCount = qData.count or 1
			status.needs = qData.needs
			
			status.rewardGold = qData.rewardGold
			status.rewardPreview = { gold = qData.rewardGold }
			
			-- 단계 정보 (단일 단계 퀘스트이므로 1/1 고정)
			status.stepIndex = 1
			local poolSize = 1
			if active and active.id then
				for _, pool in pairs(QuestData.Quests) do
					for _, q in ipairs(pool) do
						if q.id == active.id then
							poolSize = #pool
							break
						end
					end
				end
			end
			status.totalSteps = poolSize
			
			-- UI 텍스트 필드
			status.currentStepText = qData.title
			status.stepCommand = qData.desc
		else
			-- [안전 로직] 데이터에 없는 유효하지 않은 퀘스트면 강제 초기화
			progress.activeQuest = nil
			status.active = false
		end
	end

	return status
end

local function fireStatus(userId)
	if not NetController then return end
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	NetController.FireClient(player, "Tutorial.Step.Updated", serializeStatus(userId))
end

--========================================
-- Core Logic
--========================================

local function handleGetList(player, payload)
	local userId = player.UserId
	local isAdmin = isAdminUser(userId)
	
	local tier = (payload and payload.tier and isAdmin) and payload.tier or nil
	if not tier then
		local stats = PlayerStatService and PlayerStatService.getStats(userId)
		local level = stats and stats.level or 1
		tier = QuestData.getTierByLevel(level)
	end
	
	local pool = QuestData.Quests[tier] or {}

	-- 셔플하여 4개 선택
	local indices = {}
	for i = 1, #pool do table.insert(indices, i) end
	for i = #indices, 2, -1 do
		local j = math.random(i)
		indices[i], indices[j] = indices[j], indices[i]
	end

	local selection = {}
	for i = 1, math.min(4, #indices) do
		table.insert(selection, pool[indices[i]])
	end

	return {
		success = true,
		quests = selection,
		isAdmin = isAdmin,
		currentTier = tier,
		isTodayDone = false -- [테스트] 24시간 제한 해제
	}
end

local function handleAcceptQuest(player, payload)
	local userId = player.UserId
	local questId = payload and payload.questId
	if not questId then return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST } end

	local progress = getOrCreateProgress(userId)
	-- [테스트] 24시간 제한 해제
	-- if progress.lastQuestDate == getTodayString() then
	-- 	return { success = false, errorCode = Enums.ErrorCode.COOLDOWN, message = "오늘은 이미 임무를 수행했습니다." }
	-- end
	if progress.activeQuest then
		return { success = false, errorCode = Enums.ErrorCode.ALREADY_EXISTS, message = "이미 진행 중인 임무가 있습니다." }
	end

	-- 퀘스트 유효성 확인
	local qData = nil
	for _, pool in pairs(QuestData.Quests) do
		for _, q in ipairs(pool) do
			if q.id == questId then qData = q; break end
		end
		if qData then break end
	end

	if not qData then return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND } end

	-- 수락 처리
	progress.activeQuest = {
		id = questId,
		progress = {},
		completed = false,
	}
	progress.lastQuestDate = getTodayString()
	
	fireStatus(userId)
	return { success = true, data = serializeStatus(userId) }
end

local function handleStepComplete(player, _payload)
	local userId = player.UserId
	local progress = getOrCreateProgress(userId)
	local active = progress and progress.activeQuest
	if not active or not active.completed then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	-- 보상 지급
	local qData = nil
	for _, pool in pairs(QuestData.Quests) do
		for _, q in ipairs(pool) do
			if q.id == active.id then qData = q; break end
		end
		if qData then break end
	end

	if qData and qData.rewardGold and NPCShopService then
		NPCShopService.addGold(userId, qData.rewardGold)
	end

	-- 퀘스트 종료
	progress.activeQuest = nil
	progress.completedCount = (progress.completedCount or 0) + 1
	
	fireStatus(userId)
	return { success = true, data = serializeStatus(userId) }
end

--========================================
-- Event Hooks (기존 로직 재사용)
--========================================

local function updateQuestProgress(userId, eventKind, target, count)
	local progress = getOrCreateProgress(userId)
	local active = progress and progress.activeQuest
	if not active or active.completed then return end

	local qData = nil
	for _, pool in pairs(QuestData.Quests) do
		for _, q in ipairs(pool) do
			if q.id == active.id then qData = q; break end
		end
		if qData then break end
	end
	if not qData then return end

	local changed = false
	if qData.kind == "MULTI_ITEM" and eventKind == "ITEM" then
		if qData.needs[target] then
			active.progress[target] = math.max(active.progress[target] or 0, count or 0)
			changed = true
			local done = true
			for k, v in pairs(qData.needs) do
				if (active.progress[k] or 0) < v then done = false; break end
			end
			if done then active.completed = true end
		end
	elseif qData.kind == "ITEM_ANY" and eventKind == "ITEM" then
		local matched = false
		for _, v in ipairs(qData.targets or {}) do if v == target then matched = true; break end end
		if matched then
			active.progress.count = (active.progress.count or 0) + (count or 1)
			changed = true
			if active.progress.count >= (qData.count or 1) then active.completed = true end
		end
	elseif qData.kind == "RECIPE" and eventKind == "RECIPE" and qData.target == target then
		active.completed = true
		changed = true
	elseif qData.kind == "BUILD" and eventKind == "BUILD" and qData.target == target then
		active.progress.count = (active.progress.count or 0) + (count or 1)
		changed = true
		if active.progress.count >= (qData.count or 1) then active.completed = true end
	elseif qData.kind == "KILL" and eventKind == "KILL" and qData.target == target then
		active.progress.count = (active.progress.count or 0) + (count or 1)
		changed = true
		if active.progress.count >= (qData.count or 1) then active.completed = true end
	elseif qData.kind == "HARVEST" and eventKind == "HARVEST" and qData.target == target then
		active.progress.count = (active.progress.count or 0) + (count or 1)
		changed = true
		if active.progress.count >= (qData.count or 1) then active.completed = true end
	end

	if changed then
		fireStatus(userId)
	end
end

function QuestService.onItemAdded(userId, itemId, count) updateQuestProgress(userId, "ITEM", itemId, count) end
function QuestService.onCrafted(userId, recipeId) updateQuestProgress(userId, "RECIPE", recipeId, 1) end
function QuestService.onBuilt(userId, facilityId) updateQuestProgress(userId, "BUILD", facilityId, 1) end
function QuestService.onKilled(userId, creatureId) updateQuestProgress(userId, "KILL", creatureId, 1) end
function QuestService.onFoodEaten(userId, itemId) updateQuestProgress(userId, "USE_ITEM", itemId, 1) end
function QuestService.onHarvest(userId, nodeType) updateQuestProgress(userId, "HARVEST", nodeType, 1) end

--========================================
-- Handlers Registration
--========================================

function QuestService.GetHandlers()
	return {
		["Tutorial.GetStatus.Request"] = function(p, payload) return { success = true, data = serializeStatus(p.UserId) } end,
		["Tutorial.Step.Complete.Request"] = handleStepComplete,
		["Quest.GetList.Request"] = handleGetList,
		["Quest.Accept.Request"] = handleAcceptQuest,
		["Quest.Complete.Request"] = handleStepComplete,
		
		-- 어드민 명령어 (리셋용)
		["Tutorial.Admin.Reset.Request"] = function(p, payload)
			if not isAdminUser(p.UserId) then return { success = false } end
			local prg = getOrCreateProgress(p.UserId)
			prg.activeQuest = nil
			prg.lastQuestDate = ""
			fireStatus(p.UserId)
			return { success = true, data = serializeStatus(p.UserId) }
		end,
	}
end

function QuestService.Init(_NetController, _SaveService, _PlayerStatService, _InventoryService, _NPCShopService)
	NetController = _NetController
	SaveService = _SaveService
	PlayerStatService = _PlayerStatService
	InventoryService = _InventoryService
	NPCShopService = _NPCShopService
	initialized = true
	
	Players.PlayerAdded:Connect(function(player)
		task.wait(2)
		fireStatus(player.UserId)
	end)
end

return QuestService
