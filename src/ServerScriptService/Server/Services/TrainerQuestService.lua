-- TrainerQuestService.lua
-- Trainer NPC 허수아비 타격 퀘스트 시스템
-- 퀘스트 수락/진행/보상 지급 처리

local TrainerQuestService = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceRegistry = require(ReplicatedStorage.Shared.Utils.ServiceRegistry)

local NetController = nil
local SaveService = nil
local PlayerStatService = nil
local initialized = false

-- 퀘스트 정의
local QUESTS = {
	{
		id = "TRAINER_DUMMY_50",
		title = "수련의 시작",
		desc = "허수아비를 50회 타격하세요.",
		requiredHits = 50,
		rewardXP = 500,
		rewardGold = 200,
		order = 1,
	},
	{
		id = "TRAINER_DUMMY_100",
		title = "수련의 완성",
		desc = "허수아비를 100회 타격하세요.",
		requiredHits = 100,
		rewardXP = 1500,
		rewardGold = 500,
		order = 2,
	},
}

local QUEST_BY_ID = {}
for _, q in ipairs(QUESTS) do QUEST_BY_ID[q.id] = q end

-- 플레이어 퀘스트 데이터 (메모리 캐시)
local playerData = {} -- [userId] = { dummyHits, acceptedQuests, completedQuests }

local function _getGoldService()
	return ServiceRegistry.Get("NPCShopService")
end

local function _getData(userId)
	if not playerData[userId] then
		playerData[userId] = { dummyHits = 0, acceptedQuests = {}, completedQuests = {} }
	end
	return playerData[userId]
end

local function _loadFromSave(userId)
	if not SaveService then return end
	local state = SaveService.getPlayerState(userId)
	if state and state.trainerQuestData then
		local saved = state.trainerQuestData
		playerData[userId] = {
			dummyHits    = saved.dummyHits or 0,
			acceptedQuests  = saved.acceptedQuests or {},
			completedQuests = saved.completedQuests or {},
		}
	else
		playerData[userId] = { dummyHits = 0, acceptedQuests = {}, completedQuests = {} }
	end
end

local function _saveToState(userId)
	if not SaveService then return end
	local state = SaveService.getPlayerState(userId)
	if not state then return end
	local d = _getData(userId)
	state.trainerQuestData = {
		dummyHits    = d.dummyHits,
		acceptedQuests  = d.acceptedQuests,
		completedQuests = d.completedQuests,
	}
end

-- 현재 퀘스트 상태에 따른 인디케이터 종류 반환
local function _getIndicatorState(userId)
	local d = _getData(userId)

	for _, q in ipairs(QUESTS) do
		if d.completedQuests[q.id] then
			-- skip
		elseif d.acceptedQuests[q.id] then
			if d.dummyHits >= q.requiredHits then
				return "CLAIMABLE" -- 물음표
			else
				return "NONE" -- 진행 중
			end
		else
			-- 이전 퀘스트 완료 여부 확인
			local prevDone = true
			if q.order > 1 then
				for _, pq in ipairs(QUESTS) do
					if pq.order == q.order - 1 and not d.completedQuests[pq.id] then
						prevDone = false; break
					end
				end
			end
			if prevDone then return "AVAILABLE" end -- 느낌표
		end
	end
	return "NONE"
end

-- 플레이어에게 인디케이터 상태 전송
local function _updateIndicator(player)
	if not NetController then return end
	local state = _getIndicatorState(player.UserId)
	NetController.FireClient(player, "Trainer.SetIndicator", { state = state })
end

-- 플레이어에게 퀘스트 트래커 데이터 전송
local function _updateQuestTracker(player)
	if not NetController then return end
	local userId = player.UserId
	local d = _getData(userId)

	-- 현재 진행 중인 퀘스트 탐색
	local activeQuest = nil
	for _, q in ipairs(QUESTS) do
		if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
			activeQuest = q
			break
		end
	end

	if activeQuest then
		local hits = d.dummyHits
		local isDone = hits >= activeQuest.requiredHits
		NetController.FireClient(player, "Trainer.QuestTracker", {
			active      = true,
			title       = activeQuest.title,
			desc        = activeQuest.desc,
			current     = math.min(hits, activeQuest.requiredHits),
			required    = activeQuest.requiredHits,
			countLabel  = "허수아비 타격",
			doneText    = "완료! 훈련 교관에게 보고하세요.",
			done        = isDone,
		})
	else
		NetController.FireClient(player, "Trainer.QuestTracker", { active = false })
	end
end

-- 현재 플레이어에게 보여줄 대화/선택지 생성
local function _buildDialogue(userId)
	local d = _getData(userId)

	-- 다음으로 받을 수 있는 퀘스트 / 진행 중인 퀘스트 탐색
	local activeQuest = nil
	local claimableQuest = nil
	local nextAvailableQuest = nil

	for _, q in ipairs(QUESTS) do
		if d.completedQuests[q.id] then
			-- 완료됨, 건너뜀
		elseif d.acceptedQuests[q.id] then
			if d.dummyHits >= q.requiredHits then
				claimableQuest = q
			else
				activeQuest = q
			end
			break
		else
			-- 이전 퀘스트가 모두 완료되었는지 확인
			local prevDone = true
			if q.order > 1 then
				for _, pq in ipairs(QUESTS) do
					if pq.order == q.order - 1 and not d.completedQuests[pq.id] then
						prevDone = false
						break
					end
				end
			end
			if prevDone then
				nextAvailableQuest = q
				break
			end
		end
	end

	local allDone = true
	for _, q in ipairs(QUESTS) do
		if not d.completedQuests[q.id] then allDone = false; break end
	end

	local dialogue, choices

	if claimableQuest then
		dialogue = string.format(
			"잘 했네! '%s' 퀘스트를 완료했군.\n허수아비 %d회 타격 달성!\n\n보상을 받아가게.",
			claimableQuest.title, claimableQuest.requiredHits
		)
		choices = {
			{ text = string.format("보상 받기 (XP +%d, 골드 +%d)", claimableQuest.rewardXP, claimableQuest.rewardGold), action = "CLAIM", questId = claimableQuest.id },
			{ text = "나중에 받겠습니다.", action = "CLOSE" },
		}
	elseif activeQuest then
		local remain = math.max(0, activeQuest.requiredHits - d.dummyHits)
		dialogue = string.format(
			"수련 중이군! '%s' 퀘스트가 진행 중이네.\n\n허수아비 타격: %d / %d\n남은 횟수: %d회",
			activeQuest.title, d.dummyHits, activeQuest.requiredHits, remain
		)
		choices = {
			{ text = "계속 수련하겠습니다.", action = "CLOSE" },
		}
	elseif nextAvailableQuest then
		dialogue = string.format(
			"어서오게나, 수련생!\n이곳에서 수련하면 강해질 수 있네.\n\n퀘스트: <b>%s</b>\n%s\n\n보상: XP +%d, 골드 +%d",
			nextAvailableQuest.title,
			nextAvailableQuest.desc,
			nextAvailableQuest.rewardXP,
			nextAvailableQuest.rewardGold
		)
		choices = {
			{ text = "퀘스트를 수락합니다.", action = "ACCEPT", questId = nextAvailableQuest.id },
			{ text = "다음에 하겠습니다.", action = "CLOSE" },
		}
	elseif allDone then
		dialogue = "모든 수련 퀘스트를 완료했군!\n자네는 이제 진정한 전사야.\n앞으로도 계속 정진하게."
		choices = {
			{ text = "감사합니다.", action = "CLOSE" },
		}
	else
		dialogue = "아직 수련을 시작하지 않았군.\n먼저 이전 퀘스트를 완료해야 하네."
		choices = {
			{ text = "알겠습니다.", action = "CLOSE" },
		}
	end

	return dialogue, choices
end

-- 프롬프트 트리거 핸들러
local function handleOpen(player)
	if not NetController then return end
	local userId = player.UserId

	local dialogue, choices = _buildDialogue(userId)

	NetController.FireClient(player, "Trainer.OpenDialogue", {
		npcName = "훈련 교관",
		dialogue = dialogue,
		choices = choices,
	})
end

-- 퀘스트 액션 핸들러 (C2S Request)
local function handleQuestAction(player, payload)
	local userId = player.UserId
	local action = payload and payload.action
	local questId = payload and payload.questId

	if action == "ACCEPT" then
		local q = QUEST_BY_ID[questId]
		if not q then return { success = false } end

		local d = _getData(userId)
		if d.acceptedQuests[questId] or d.completedQuests[questId] then
			return { success = false, reason = "already" }
		end
		d.acceptedQuests[questId] = true
		_saveToState(userId)
		_updateIndicator(player)
		_updateQuestTracker(player)

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text = string.format("퀘스트 수락: %s — 허수아비를 %d회 타격하세요!", q.title, q.requiredHits),
				color = "GOLD",
			})
		end
		return { success = true }

	elseif action == "CLAIM" then
		local q = QUEST_BY_ID[questId]
		if not q then return { success = false } end

		local d = _getData(userId)
		if not d.acceptedQuests[questId] then return { success = false, reason = "not_accepted" } end
		if d.completedQuests[questId] then return { success = false, reason = "already_claimed" } end
		if d.dummyHits < q.requiredHits then return { success = false, reason = "not_done" } end

		-- XP 지급
		if PlayerStatService and PlayerStatService.addXP then
			PlayerStatService.addXP(userId, q.rewardXP, "TrainerQuest")
		end

		-- 골드 지급
		local goldSvc = _getGoldService()
		if goldSvc and goldSvc.addGold then
			goldSvc.addGold(userId, q.rewardGold)
		end

		d.completedQuests[questId] = true
		_saveToState(userId)
		_updateIndicator(player)
		_updateQuestTracker(player)

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text = string.format("퀘스트 완료! '%s' — XP +%d, 골드 +%d 획득!", q.title, q.rewardXP, q.rewardGold),
				color = "GOLD",
			})
		end

		-- 다음 퀘스트가 있으면 대화창 갱신
		task.defer(function()
			handleOpen(player)
		end)

		return { success = true }
	end

	return { success = false }
end

function TrainerQuestService.Init(netController, saveService, playerStatService)
	if initialized then return end
	initialized = true

	NetController = netController
	SaveService = saveService
	PlayerStatService = playerStatService

	-- 허수아비 타격 콜백 등록
	local TrainingDummyService = require(ServerScriptService.Server.Services.TrainingDummyService)
	TrainingDummyService.RegisterHitCallback(function(player)
		local userId = player.UserId
		local d = _getData(userId)

		-- 수락된 미완료 퀘스트가 있을 때만 카운트
		local hasActive = false
		for _, q in ipairs(QUESTS) do
			if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
				hasActive = true
				break
			end
		end
		if not hasActive then return end

		d.dummyHits = d.dummyHits + 1
		_saveToState(userId)

		-- 매 타격마다 트래커 갱신 (5회마다 전송해서 네트워크 절약)
		if d.dummyHits % 5 == 0 or d.dummyHits == 1 then
			_updateQuestTracker(player)
		end

		-- 목표 달성 시 알림 + 인디케이터 갱신
		for _, q in ipairs(QUESTS) do
			if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
				if d.dummyHits == q.requiredHits then
					_updateIndicator(player)
					_updateQuestTracker(player)
					if NetController then
						NetController.FireClient(player, "Notify.Message", {
							text = string.format("'%s' 퀘스트 완료! 훈련 교관에게 돌아가 보상을 받으세요.", q.title),
							color = "GOLD",
						})
					end
				end
				break
			end
		end
	end)

	-- 플레이어 접속 시 데이터 로드 + 인디케이터 초기화
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			-- 캐릭터 스폰 및 클라이언트 컨트롤러 초기화 대기
			player.CharacterAdded:Wait()
			task.wait(4)  -- SaveService DataStore 로드 완료 대기
			_loadFromSave(player.UserId)  -- wait 후 로드해야 데이터가 준비된 상태
			_updateIndicator(player)
			_updateQuestTracker(player)
			print("[TrainerQuestService] PlayerAdded indicator sent to", player.Name, _getIndicatorState(player.UserId))
		end)
	end)

	-- 이미 접속 중인 플레이어 처리 (서버 재시작 등)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.wait(4)
			_loadFromSave(player.UserId)
			_updateIndicator(player)
			_updateQuestTracker(player)
			print("[TrainerQuestService] ExistingPlayer indicator sent to", player.Name, _getIndicatorState(player.UserId))
		end)
	end

	-- Workspace NPC 프롬프트 연결
	task.defer(function()
		local npcFolder = workspace:WaitForChild("NPC", 15)
		if not npcFolder then
			warn("[TrainerQuestService] NPC folder not found")
			return
		end
		local trainer = npcFolder:WaitForChild("Trainer", 15)
		if not trainer then
			warn("[TrainerQuestService] Trainer NPC not found")
			return
		end
		local rootPart = trainer:WaitForChild("HumanoidRootPart", 10)
		if not rootPart then
			warn("[TrainerQuestService] Trainer has no HumanoidRootPart")
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TrainerPrompt"
		prompt.ActionText = "대화하기"
		prompt.ObjectText = "훈련 교관"
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Parent = rootPart

		prompt.Triggered:Connect(function(player)
			_loadFromSave(player.UserId) -- 최신 상태 동기화
			handleOpen(player)
		end)

		print("[TrainerQuestService] Trainer NPC prompt registered.")
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerData[player.UserId] = nil
	end)
end

local function handleGetIndicator(player)
	_loadFromSave(player.UserId)
	local state = _getIndicatorState(player.UserId)
	task.defer(function() _updateQuestTracker(player) end)
	return { state = state }
end

local function handleQuestReset(player)
	local userId = player.UserId
	playerData[userId] = { dummyHits = 0, acceptedQuests = {}, completedQuests = {} }
	_saveToState(userId)
	_updateIndicator(player)
	_updateQuestTracker(player)
	print("[TrainerQuestService] Quest reset for", player.Name)
	return { success = true }
end

function TrainerQuestService.GetHandlers()
	return {
		["Trainer.QuestAction.Request"] = handleQuestAction,
		["Trainer.GetIndicator.Request"] = handleGetIndicator,
		["Trainer.Quest.Reset.Request"] = handleQuestReset,
	}
end

return TrainerQuestService
