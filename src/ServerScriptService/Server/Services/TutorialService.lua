-- TutorialService.lua
-- 선형적 튜토리얼 시스템 서비스

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local TutorialData = require(ReplicatedStorage.Data.TutorialData)

local TutorialService = {}

local NetController = nil
local SaveService = nil
local PlayerStatService = nil
local InventoryService = nil

--========================================
-- Helper Logic
--========================================

local function getOrCreateProgress(userId, waitIfNull)
	local state = SaveService and SaveService.getPlayerState(userId)
	
	if not state and waitIfNull then
		-- 데이터 로딩 대기 루프 (최대 10초)
		local start = tick()
		while not state and (tick() - start) < 10 do
			task.wait(0.5)
			state = SaveService and SaveService.getPlayerState(userId)
		end
	end
	
	if type(state) ~= "table" then return nil end

	if type(state.introTutorial) ~= "table" then
		state.introTutorial = {
			stepIndex = 0, -- 0: 시작 전, 1~N: 진행 중, -1: 완료
			completed = false,
		}
	end

	local progress = state.introTutorial
	
	-- [수정] 신규 데이터 상태(stepIndex == 0)일 때만 레벨에 따른 분기 처리
	if progress.stepIndex == 0 and not progress.completed then
		if PlayerStatService and PlayerStatService.getLevel then
			-- getLevel은 내부적으로 waitForPlayerState를 수행하므로 안전함
			local level = PlayerStatService.getLevel(userId)
			print(string.format("[TutorialService] Checking level for %d: Current Level = %d", userId, level))
			
			if level > 1 then
				-- 레벨 2 이상인데 튜토리얼 기록이 없다면 -> 이미 진행한 플레이어로 간주하여 스킵
				progress.stepIndex = -1
				progress.completed = true
				print(string.format("[TutorialService] Skipped tutorial for existing player %d (Level %d)", userId, level))
			else
				-- 레벨 1이고 기록이 없다면 -> 신규 플레이어이므로 튜토리얼 시작
				progress.stepIndex = 1
				progress.completed = false
				print(string.format("[TutorialService] Auto-started tutorial for new player %d", userId))
			end
		else
			warn("[TutorialService] PlayerStatService not ready for " .. userId)
		end
	end

	return progress
end

-- 튜토리얼 중인지 확인 (CreatureService에서 참조)
function TutorialService.isPlayerInTutorial(userId)
	local progress = getOrCreateProgress(userId, false)
	return progress and progress.stepIndex > 0 and not progress.completed
end

local function fireUpdate(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player or not NetController then return end

	local progress = getOrCreateProgress(userId, true)
	if not progress then
		warn("[TutorialService] Failed to fire update: progress data not ready for " .. userId)
		return
	end

	local stepData = nil
	if progress.stepIndex > 0 then
		stepData = TutorialData.Steps[progress.stepIndex]
	end

	NetController.FireClient(player, "Tutorial.Step.Update", {
		stepIndex = progress.stepIndex,
		completed = progress.completed,
		stepData = stepData
	})
end

--========================================
-- Core API
--========================================

-- 튜토리얼 시작
function TutorialService.startTutorial(userId)
	local progress = getOrCreateProgress(userId, true)
	if not progress then return end
	
	progress.stepIndex = 1
	progress.completed = false
	
	fireUpdate(userId)
	print(string.format("[TutorialService] Started for %d", userId))
end

-- 단계 완료 처리 및 보상
function TutorialService.completeStep(userId, stepIndex)
	local progress = getOrCreateProgress(userId, true)
	if not progress or progress.stepIndex ~= stepIndex then return false end
	
	local stepData = TutorialData.Steps[stepIndex]
	if not stepData then return false end

	-- 보상 지급 (XP)
	if stepData.rewardXP and PlayerStatService then
		PlayerStatService.grantActionXP(userId, stepData.rewardXP, {
			source = Enums.XPSource.TUTORIAL or 10, -- Enums에 없을 경우 기본값
			actionKey = "TUTORIAL_STEP_" .. stepIndex
		})
	end

	-- 보상 지급 (아이템)
	if stepData.rewardItems and InventoryService then
		for _, item in ipairs(stepData.rewardItems) do
			InventoryService.addItem(userId, item.itemId, item.count)
		end
	end

	-- 다음 단계로
	if stepIndex < #TutorialData.Steps then
		progress.stepIndex = stepIndex + 1
	else
		progress.stepIndex = -1
		progress.completed = true
		print(string.format("[TutorialService] Completed for %d", userId))
	end

	fireUpdate(userId)
	
	-- 즉시 저장
	if SaveService then
		SaveService.savePlayer(userId)
	end
	
	return true
end

--========================================
-- Handlers
--========================================

function TutorialService.GetHandlers()
	return {
		["Tutorial.Start.Request"] = function(player)
			-- 튜토리얼 수동 시작 (테스트용)
			TutorialService.startTutorial(player.UserId)
			return { success = true }
		end,
		
		["Tutorial.GetStatus.Request"] = function(player)
			local progress = getOrCreateProgress(player.UserId, true)
			if not progress then 
				return { success = false, message = "Data not loaded" } 
			end
			
			return { success = true, data = {
				stepIndex = progress.stepIndex,
				totalSteps = #TutorialData.Steps,
				completed = progress.completed
			}}
		end,

		["Tutorial.Step.Complete.Request"] = function(player, payload)
			local success = TutorialService.completeStep(player.UserId, payload.stepIndex)
			return { success = success }
		end,

		["Tutorial.Admin.Reset.Request"] = function(player)
			local progress = getOrCreateProgress(player.UserId, true)
			if not progress then return { success = false } end
			progress.stepIndex = 0
			progress.completed = false
			fireUpdate(player.UserId)
			return { success = true }
		end,

		["Tutorial.Admin.SetStep.Request"] = function(player, payload)
			local progress = getOrCreateProgress(player.UserId, true)
			if not progress then return { success = false } end
			progress.stepIndex = payload.stepIndex or 1
			progress.completed = false
			fireUpdate(player.UserId)
			return { success = true }
		end,
		
		["Tutorial.Admin.ForceStart.Request"] = function(player)
			TutorialService.startTutorial(player.UserId)
			return { success = true }
		end,
	}
end

function TutorialService.Init(_NetController, _SaveService, _PlayerStatService, _InventoryService)
	NetController = _NetController
	SaveService = _SaveService
	PlayerStatService = _PlayerStatService
	InventoryService = _InventoryService

	local function setupPlayer(player)
		local userId = player.UserId
		task.spawn(function()
			local start = tick()
			print(string.format("[TutorialService] setupPlayer for %s (%d): Waiting for data...", player.Name, userId))
			-- 데이터 로딩 대기 (SaveService가 SetAttribute("DataLoaded", true)를 함)
			while player.Parent and not player:GetAttribute("DataLoaded") and (tick() - start) < 15 do
				task.wait(0.5)
			end

			if player.Parent then
				print(string.format("[TutorialService] setupPlayer for %s: Data ready, firing update.", player.Name))
				fireUpdate(userId)
			end
		end)
	end

	-- [수정] 플레이어 접속 시 및 기접속 플레이어 처리 통합
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end

	print("[TutorialService] Initialized with Auto-Sync")
end

return TutorialService
