-- CitizenQuestService.lua
-- 청운촌 주민 3인(citizen_01/02/03) 순차 퀘스트 체인
-- 마을 생활(농부) -> 실력 증명/스킬 힌트(용병) -> 하늘섬/세계관 떡밥(촌장) 순으로 이어지는 사이드 스토리
-- Trainer/MagicianQuestService와 동일한 수락->진행->보고->보상 구조를 3개 NPC에 걸쳐 재사용

local CitizenQuestService = {}

local Players           = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local ServiceRegistry = require(ReplicatedStorage.Shared.Utils.ServiceRegistry)

local NetController     = nil
local SaveService       = nil
local PlayerStatService = nil
local initialized       = false

-- ── NPC별 퀘스트 체인 정의 ──
-- [주의] citizen_01("농부 만석")은 드롭률 안내 NPC("척척박사")로 용도가 변경되어
-- 퀘스트 체인에서 제외됨. 해당 NPC의 상호작용은 DropRateInfoService.lua가 전담.
local CITIZENS = {
	citizen_02 = {
		npcModel = "citizen_02",
		npcName  = "용병 두칠",
		quests = {
			{
				id = "CITIZEN2_STUMP", order = 1,
				title = "숲의 잔재",
				targetMob = "스텀프", requiredKills = 10,
				rewardXP = 500, rewardGold = 250,
				npcDialogue     = "허, 제법 강해 보이는군. 스텀프 무리 속에서 이상한 빛이 났다는 소문이 있는데, 가서 확인 좀 해주겠나? 10마리만 처리하면 되네.",
				npcDialogueDone = "역시! 자네 정도면 알아도 되겠군. 저 하늘 위에 떠 있는 섬 말일세... 예사롭지 않은 곳이라 하더군. 게다가 남쪽 바다 밑에는 심해 도시가 가라앉아 있다는 소문도 있다네. 둘 다 아무나 갈 수 있는 곳은 아니라지.",
			},
			{
				id = "CITIZEN2_SAMURAI", order = 2,
				title = "실력 증명",
				targetMob = "사무라이", requiredKills = 15,
				rewardXP = 900, rewardGold = 400,
				npcDialogue     = "사무라이들과 제대로 붙어봤나? 15마리 정도 처리하고 오면 자네 실력을 인정해주지.",
				npcDialogueDone = "훌륭하군! 그 정도 실력이면 강화의 대장장이도 자넬 반길 걸세. 무기를 더 갈고 닦아보게.",
			},
		},
	},
	citizen_03 = {
		npcModel = "citizen_03",
		npcName  = "촌장 백씨",
		quests = {
			{
				id = "CITIZEN3_ICE", order = 1,
				title = "얼어붙은 전조",
				targetMob = "얼음 기사", requiredKills = 6,
				rewardXP = 1500, rewardGold = 600,
				npcDialogue     = "어서 오게, 여행자. 요즘 얼음 기사들이 부쩍 늘어서 걱정이 많다네. 6마리만 처리해서 무슨 일인지 살펴봐 주겠나?",
				npcDialogueDone = "수고했네. 저 위에 떠 있는 섬 말일세... 얼음 기운이 저 하늘섬에서 흘러나온다는 이야기가 있어. 예사롭지 않은 곳이지.",
			},
		},
	},
}

-- questId -> quest / npcId 역참조 테이블
local QUEST_BY_ID = {}
local NPC_BY_QUEST_ID = {}
for npcId, npc in pairs(CITIZENS) do
	for _, q in ipairs(npc.quests) do
		QUEST_BY_ID[q.id] = q
		NPC_BY_QUEST_ID[q.id] = npcId
	end
end

-- [userId] = { [npcId] = { acceptedQuests={}, completedQuests={}, killProgress={} } }
local playerData = {}

local function _getGoldService()
	return ServiceRegistry.Get("NPCShopService")
end

local function _emptyNpcState()
	return { acceptedQuests = {}, completedQuests = {}, killProgress = {} }
end

local function _getData(userId, npcId)
	if not playerData[userId] then playerData[userId] = {} end
	if not playerData[userId][npcId] then
		playerData[userId][npcId] = _emptyNpcState()
	end
	return playerData[userId][npcId]
end

local function _loadFromSave(userId)
	playerData[userId] = {}
	local saved = nil
	if SaveService then
		local state = SaveService.getPlayerState(userId)
		saved = state and state.citizenQuestData
	end
	for npcId in pairs(CITIZENS) do
		local s = saved and saved[npcId]
		playerData[userId][npcId] = {
			acceptedQuests  = (s and s.acceptedQuests)  or {},
			completedQuests = (s and s.completedQuests) or {},
			killProgress    = (s and s.killProgress)    or {},
		}
	end
end

local function _saveToState(userId)
	if not SaveService then return end
	SaveService.updatePlayerState(userId, function(state)
		state.citizenQuestData = playerData[userId]
		return state
	end)
end

local function _isObjectiveDone(userId, npcId, q)
	if (q.requiredKills or 0) <= 0 then return true end
	local d = _getData(userId, npcId)
	local progress = d.killProgress[q.id] or 0
	return progress >= q.requiredKills
end

-- 인디케이터 상태: AVAILABLE(!) / CLAIMABLE(?) / NONE
local function _getIndicatorState(userId, npcId)
	local npc = CITIZENS[npcId]
	local d = _getData(userId, npcId)
	for _, q in ipairs(npc.quests) do
		if d.completedQuests[q.id] then
			-- 완료됨, 건너뜀
		elseif d.acceptedQuests[q.id] then
			if _isObjectiveDone(userId, npcId, q) then
				return "CLAIMABLE"
			else
				return "NONE"
			end
		else
			local prevDone = true
			if q.order > 1 then
				for _, pq in ipairs(npc.quests) do
					if pq.order == q.order - 1 and not d.completedQuests[pq.id] then
						prevDone = false; break
					end
				end
			end
			if prevDone then return "AVAILABLE" end
		end
	end
	return "NONE"
end

local function _updateIndicator(player, npcId)
	if not NetController then return end
	local state = _getIndicatorState(player.UserId, npcId)
	NetController.FireClient(player, "Citizen.SetIndicator", { npcId = npcId, state = state })
end

local function _updateQuestTracker(player, npcId)
	if not NetController then return end
	local userId = player.UserId
	local npc = CITIZENS[npcId]
	local d = _getData(userId, npcId)

	for _, q in ipairs(npc.quests) do
		if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
			local isDone  = _isObjectiveDone(userId, npcId, q)
			local current = math.min(d.killProgress[q.id] or 0, q.requiredKills or 0)
			NetController.FireClient(player, "Citizen.QuestTracker", {
				npcId      = npcId,
				active     = true,
				title      = q.title,
				desc       = q.targetMob and string.format("%s 처치: %d / %d", q.targetMob, current, q.requiredKills)
					or ("완료! " .. npc.npcName .. "에게 돌아가 보고하세요."),
				current    = current,
				required   = q.requiredKills or 0,
				countLabel = q.targetMob and (q.targetMob .. " 처치") or "",
				doneText   = "완료! " .. npc.npcName .. "에게 돌아가 보고하세요.",
				done       = isDone,
			})
			return
		end
	end
	NetController.FireClient(player, "Citizen.QuestTracker", { npcId = npcId, active = false })
end

-- 현재 퀘스트 상태 파악 (TrainerQuestService/MagicianQuestService와 동일한 구조)
local function _getCurrentContext(userId, npcId)
	local npc = CITIZENS[npcId]
	local d = _getData(userId, npcId)
	local claimable, active, nextAvailable = nil, nil, nil
	local allDone = true

	for _, q in ipairs(npc.quests) do
		if not d.completedQuests[q.id] then
			allDone = false
			if d.acceptedQuests[q.id] then
				if _isObjectiveDone(userId, npcId, q) then
					claimable = q
				else
					active = q
				end
				break
			else
				local prevDone = true
				if q.order > 1 then
					for _, pq in ipairs(npc.quests) do
						if pq.order == q.order - 1 and not d.completedQuests[pq.id] then
							prevDone = false; break
						end
					end
				end
				if prevDone then nextAvailable = q; break end
			end
		end
	end

	return claimable, active, nextAvailable, allDone
end

local function _buildDialogue(userId, npcId)
	local npc = CITIZENS[npcId]
	local claimable, active, nextAvail, allDone = _getCurrentContext(userId, npcId)

	if allDone then
		return "이제 더는 부탁할 게 없다네. 자네 덕에 마을이 한결 편해졌어. 정말 고맙네.",
			{{ text = "감사합니다.", action = "CLOSE" }}
	end

	if claimable then
		return claimable.npcDialogueDone or string.format("'%s' 퀘스트를 완료했군! 보상을 받아가게.", claimable.title),
			{
				{ text = string.format("보상 받기 (XP +%d, 골드 +%d)", claimable.rewardXP, claimable.rewardGold), action = "CLAIM", questId = claimable.id },
				{ text = "나중에 받겠습니다.", action = "CLOSE" },
			}
	end

	if active then
		local d = _getData(userId, npcId)
		local remain = math.max(0, (active.requiredKills or 0) - (d.killProgress[active.id] or 0))
		local desc = active.targetMob and string.format("%s 남은 처치: %d회", active.targetMob, remain)
			or "완료 조건을 충족했는지 다시 확인해 보게."
		return string.format("'%s' 진행 중이라네.\n\n%s", active.title, desc),
			{{ text = "계속 해보겠습니다.", action = "CLOSE" }}
	end

	if nextAvail then
		return nextAvail.npcDialogue,
			{
				{ text = string.format("수락하겠습니다! (XP +%d, 골드 +%d)", nextAvail.rewardXP, nextAvail.rewardGold), action = "ACCEPT", questId = nextAvail.id },
				{ text = "나중에 하겠습니다.", action = "CLOSE" },
			}
	end

	return "잠시 후 다시 이야기하세.", {{ text = "알겠습니다.", action = "CLOSE" }}
end

local function handleOpen(player, npcId)
	if not NetController then return end
	local npc = CITIZENS[npcId]
	if not npc then return end
	local dialogue, choices = _buildDialogue(player.UserId, npcId)
	NetController.FireClient(player, "Citizen.OpenDialogue", {
		npcId    = npcId,
		npcName  = npc.npcName,
		dialogue = dialogue,
		choices  = choices,
	})
end

-- 퀘스트 액션 핸들러 (C→S)
local function handleQuestAction(player, payload)
	local userId  = player.UserId
	local action  = payload and payload.action
	local questId = payload and payload.questId
	local q = questId and QUEST_BY_ID[questId]
	if not q then return { success = false } end
	local npcId = NPC_BY_QUEST_ID[questId]
	local npc   = CITIZENS[npcId]
	local d     = _getData(userId, npcId)

	if action == "ACCEPT" then
		if d.acceptedQuests[q.id] or d.completedQuests[q.id] then
			return { success = false, reason = "already" }
		end
		d.acceptedQuests[q.id] = true
		_saveToState(userId)
		_updateIndicator(player, npcId)
		_updateQuestTracker(player, npcId)

		if NetController then
			local notifyText = _isObjectiveDone(userId, npcId, q)
				and string.format("퀘스트 '%s': %s에게 돌아가 보고하세요.", q.title, npc.npcName)
				or  string.format("퀘스트 수락: %s", q.title)
			NetController.FireClient(player, "Notify.Message", { text = notifyText, color = "GOLD" })
		end
		return { success = true }

	elseif action == "CLAIM" then
		if not d.acceptedQuests[q.id]  then return { success = false, reason = "not_accepted" } end
		if d.completedQuests[q.id]     then return { success = false, reason = "already_claimed" } end
		if not _isObjectiveDone(userId, npcId, q) then return { success = false, reason = "not_done" } end

		if PlayerStatService and PlayerStatService.addXP then
			PlayerStatService.addXP(userId, q.rewardXP, "CitizenQuest")
		end
		local goldSvc = _getGoldService()
		if goldSvc and goldSvc.addGold then goldSvc.addGold(userId, q.rewardGold) end

		d.completedQuests[q.id] = true
		_saveToState(userId)
		_updateIndicator(player, npcId)
		_updateQuestTracker(player, npcId)

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text  = string.format("퀘스트 완료! '%s' — XP +%d, 골드 +%d 획득!", q.title, q.rewardXP, q.rewardGold),
				color = "GOLD",
			})
		end

		task.defer(function() handleOpen(player, npcId) end)
		return { success = true }
	end

	return { success = false }
end

-- ── 몹 처치 이벤트 (PlayerStatService.incrementKill에서 호출) ──
function CitizenQuestService.OnMobKilled(userId, mobDisplayName)
	local player = Players:GetPlayerByUserId(userId)

	for npcId, npc in pairs(CITIZENS) do
		local d = _getData(userId, npcId)
		for _, q in ipairs(npc.quests) do
			if q.targetMob == mobDisplayName and d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
				if not _isObjectiveDone(userId, npcId, q) then
					d.killProgress[q.id] = (d.killProgress[q.id] or 0) + 1
					_saveToState(userId)

					if player then
						if d.killProgress[q.id] % 3 == 0 or d.killProgress[q.id] == 1 then
							_updateQuestTracker(player, npcId)
						end
						if d.killProgress[q.id] == q.requiredKills then
							_updateIndicator(player, npcId)
							_updateQuestTracker(player, npcId)
							if NetController then
								NetController.FireClient(player, "Notify.Message", {
									text  = string.format("'%s' 목표 달성! %s에게 돌아가 보고하세요.", q.title, npc.npcName),
									color = "GOLD",
								})
							end
						end
					end
				end
				break
			end
		end
	end
end

-- ── Init ──
function CitizenQuestService.Init(netController, saveService, playerStatService)
	if initialized then return end
	initialized = true

	NetController     = netController
	SaveService       = saveService
	PlayerStatService = playerStatService

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			player.CharacterAdded:Wait()
			task.wait(4)
			_loadFromSave(player.UserId)
			for npcId in pairs(CITIZENS) do
				_updateIndicator(player, npcId)
				_updateQuestTracker(player, npcId)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.wait(4)
			_loadFromSave(player.UserId)
			for npcId in pairs(CITIZENS) do
				_updateIndicator(player, npcId)
				_updateQuestTracker(player, npcId)
			end
		end)
	end

	task.defer(function()
		local npcFolder = workspace:WaitForChild("NPC", 30)
		if not npcFolder then warn("[CitizenQuestService] NPC folder not found"); return end

		for npcId, npc in pairs(CITIZENS) do
			task.spawn(function()
				local model = npcFolder:WaitForChild(npc.npcModel, 30)
				if not model then warn("[CitizenQuestService] " .. npc.npcModel .. " NPC not found"); return end

				local rootPart = model:FindFirstChild("HumanoidRootPart")
					or model:WaitForChild("HumanoidRootPart", 15)
				if not rootPart then
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") then rootPart = d; break end
					end
				end
				if not rootPart then warn("[CitizenQuestService] " .. npc.npcModel .. " has no root part"); return end

				local prompt = Instance.new("ProximityPrompt")
				prompt.Name                  = "CitizenPrompt"
				prompt.ActionText            = "대화하기"
				prompt.ObjectText            = npc.npcName
				prompt.KeyboardKeyCode       = Enum.KeyCode.E
				prompt.HoldDuration          = 0.3
				prompt.RequiresLineOfSight   = false
				prompt.MaxActivationDistance = 10
				prompt.Parent                = rootPart

				prompt.Triggered:Connect(function(player)
					_loadFromSave(player.UserId)
					handleOpen(player, npcId)
				end)

				print(string.format("[CitizenQuestService] %s (%s) NPC prompt registered.", npcId, npc.npcName))
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerData[player.UserId] = nil
	end)
end

local function handleGetIndicator(player, payload)
	local npcId = payload and payload.npcId
	if not npcId or not CITIZENS[npcId] then return { state = "NONE" } end
	_loadFromSave(player.UserId)
	local state = _getIndicatorState(player.UserId, npcId)
	task.defer(function() _updateQuestTracker(player, npcId) end)
	return { state = state }
end

local function handleQuestReset(player)
	local userId = player.UserId
	playerData[userId] = {}
	for npcId in pairs(CITIZENS) do
		playerData[userId][npcId] = _emptyNpcState()
	end
	if SaveService then
		SaveService.updatePlayerState(userId, function(state)
			state.citizenQuestData = nil
			return state
		end)
	end
	for npcId in pairs(CITIZENS) do
		_updateIndicator(player, npcId)
		_updateQuestTracker(player, npcId)
	end
	print(string.format("[CitizenQuestService] Quest reset for %s", player.Name))
	return { success = true }
end

function CitizenQuestService.GetHandlers()
	return {
		["Citizen.QuestAction.Request"]  = handleQuestAction,
		["Citizen.GetIndicator.Request"] = handleGetIndicator,
		["Citizen.Quest.Reset.Request"]  = handleQuestReset,
	}
end

return CitizenQuestService
