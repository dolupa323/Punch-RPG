-- MagicianQuestService.lua
-- Magician NPC 포탈 교육 퀘스트 시스템
-- 전통 RPG 퀘스트 루프: 수락 → 목표 수행 → NPC 복귀 → 보상 수령

local MagicianQuestService = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceRegistry = require(ReplicatedStorage.Shared.Utils.ServiceRegistry)

local NetController     = nil
local SaveService       = nil
local PlayerStatService = nil
local initialized       = false

-- ── 퀘스트 정의 ──
-- 포탈 시스템 구조:
--   각 지역 포탈(현지) → E키로 등록 → 마을 포탈 목록 해금 → 마을 포탈 E키 → 이동
local QUESTS = {
	{
		id    = "MAGICIAN_REGISTER",
		order = 1,
		title = "초원 포탈 등록",
		type  = "PORTAL_REGISTER",
		targetPortalId = "Grasslands",
		rewardXP   = 500,
		rewardGold = 200,
		trackerDesc = "초원 지역으로 이동 → 포탈 앞에서 E키로 등록 → 마법사에게 보고",
		-- 첫 대화: 포탈 시스템 설명 + 퀘스트 제안
		npcDialogue = "오오, 반갑소 여행자!\n나는 포탈 마법을 연구하는 마법사라오.\n\n이 세계의 <b>포탈 시스템</b>을 알려주겠소!\n\n① 각 지역에는 <b>포탈</b>이 세워져 있다오.\n② 그 앞에서 <b>E키</b>를 누르면 그 지역이 <b>등록</b>되지요.\n③ 등록한 지역은 마을 중앙 포탈에서 <b>순간이동</b>으로 언제든 갈 수 있다오!\n\n먼저 초원에 나가 포탈을 등록해 보겠나?",
		-- 목표 달성 후 NPC 복귀 시 대사
		npcDialogueDone = "오호! 초원 포탈을 등록했군! 잘 했다오!\n\n이제 마을 중앙 포탈에서 초원을 선택해 이동할 수 있다오.\n마을 포탈은 이 근처 중앙 광장에 있으니\n가서 <b>E키</b>로 상호작용해 보게나!",
	},
	{
		id    = "MAGICIAN_TELEPORT",
		order = 2,
		title = "마을 포탈로 초원 이동",
		type  = "PORTAL_TELEPORT",
		targetPortalId = "Grasslands",
		rewardXP   = 800,
		rewardGold = 300,
		trackerDesc = "마을 중앙 포탈 → E키 → 초원 선택하여 이동 → 마법사에게 보고",
		npcDialogue = "마을 중앙에 있는 큰 포탈로 가보게!\n<b>E키</b>를 누르면 등록된 지역 목록이 열린다오.\n거기서 <b>초원</b>을 선택하면 순간이동이 된다네!\n\n이동하고 나면 이곳으로 돌아오게나.",
		npcDialogueDone = "초원까지 포탈로 다녀왔구나! 훌륭하이!\n\n이제 마지막으로 <b>마을귀환</b> 기능을 배워보세나.\n화면 하단의 [마을귀환] 버튼을 누르면\n포탈 없이도 즉시 마을로 돌아온다오!",
	},
	{
		id    = "MAGICIAN_VILLAGE_RETURN",
		order = 3,
		title = "마을귀환 버튼 사용",
		type  = "VILLAGE_RETURN",
		rewardXP   = 600,
		rewardGold = 250,
		trackerDesc = "화면 하단 [마을귀환] 버튼 사용 → 마을 복귀 → 마법사에게 보고",
		npcDialogue = "마지막 수업이오!\n화면 <b>하단 중앙</b>에 <b>[마을귀환]</b> 버튼이 있다오.\n포탈 없이도 그 버튼 하나로 즉시 마을로 돌아올 수 있다네!\n\n한번 눌러보게나. 어디 있든 바로 이 마을로 돌아온다오.",
		npcDialogueDone = "완벽하이! 이제 자네는 어떤 지역에 가더라도\n포탈로 이동하고, 마을귀환으로 복귀하는 것을 알게 됐군.\n\n앞으로의 여정에서 이 지식이 큰 도움이 될 것이오. 행운을 빌겠네!",
	},
}

local QUEST_BY_ID = {}
for _, q in ipairs(QUESTS) do QUEST_BY_ID[q.id] = q end

-- [userId] = { acceptedQuests, completedQuests, objectiveDone }
local playerData = {}

local function _getGoldService()
	return ServiceRegistry.Get("NPCShopService")
end

local function _getData(userId)
	if not playerData[userId] then
		playerData[userId] = { acceptedQuests = {}, completedQuests = {}, objectiveDone = {} }
	end
	return playerData[userId]
end

local function _loadFromSave(userId)
	if not SaveService then return end
	local state = SaveService.getPlayerState(userId)
	if state and state.magicianQuestData then
		local saved = state.magicianQuestData
		playerData[userId] = {
			acceptedQuests  = saved.acceptedQuests  or {},
			completedQuests = saved.completedQuests or {},
			objectiveDone   = saved.objectiveDone   or {},
		}
	else
		playerData[userId] = { acceptedQuests = {}, completedQuests = {}, objectiveDone = {} }
	end
end

local function _saveToState(userId)
	if not SaveService then return end
	SaveService.updatePlayerState(userId, function(state)
		local d = _getData(userId)
		state.magicianQuestData = {
			acceptedQuests  = d.acceptedQuests,
			completedQuests = d.completedQuests,
			objectiveDone   = d.objectiveDone,
		}
		return state
	end)
end

-- 인디케이터 상태: AVAILABLE(!) / CLAIMABLE(?) / NONE
local function _getIndicatorState(userId)
	local d = _getData(userId)
	for _, q in ipairs(QUESTS) do
		if d.completedQuests[q.id] then
			-- 완료됨, 건너뜀
		elseif d.acceptedQuests[q.id] then
			if d.objectiveDone[q.id] then
				return "CLAIMABLE"  -- 물음표: 목표 달성, NPC 보고 대기
			else
				return "NONE"       -- 진행 중
			end
		else
			local prevDone = true
			if q.order > 1 then
				for _, pq in ipairs(QUESTS) do
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

local function _updateIndicator(player)
	if not NetController then return end
	local state = _getIndicatorState(player.UserId)
	NetController.FireClient(player, "Magician.SetIndicator", { state = state })
end

local function _updateQuestTracker(player)
	if not NetController then return end
	local userId = player.UserId
	local d = _getData(userId)

	for _, q in ipairs(QUESTS) do
		if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
			local isDone = d.objectiveDone[q.id]
			NetController.FireClient(player, "Magician.QuestTracker", {
				active   = true,
				title    = q.title,
				desc     = isDone and "완료! 마법사에게 돌아가 보고하세요." or (q.trackerDesc or ""),
				doneText = "완료! 마법사에게 돌아가 보고하세요.",
				done     = isDone,
			})
			return
		end
	end
	NetController.FireClient(player, "Magician.QuestTracker", { active = false })
end

-- 현재 퀘스트 상태 파악 (TrainerQuestService와 동일한 구조)
local function _getCurrentContext(userId)
	local d = _getData(userId)
	local claimable     = nil  -- 목표 달성, 보상 수령 대기
	local active        = nil  -- 진행 중
	local nextAvailable = nil  -- 수락 가능
	local allDone       = true

	for _, q in ipairs(QUESTS) do
		if not d.completedQuests[q.id] then
			allDone = false
			if d.acceptedQuests[q.id] then
				if d.objectiveDone[q.id] then
					claimable = q
				else
					active = q
				end
				break
			else
				local prevDone = true
				if q.order > 1 then
					for _, pq in ipairs(QUESTS) do
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

-- NPC 대화 내용 빌드 (TrainerQuestService._buildDialogue 패턴)
local function _buildDialogue(userId)
	local claimable, active, nextAvail, allDone = _getCurrentContext(userId)

	-- 모든 퀘스트 완료
	if allDone then
		return
			"이미 모든 포탈 수련을 마쳤군!\n포탈과 마을귀환을 자유자재로 쓸 수 있는 여행자가 됐다네.\n앞으로의 여정에 행운을 빌겠네!",
			{{ text = "감사합니다, 마법사님.", action = "CLOSE" }}
	end

	-- 목표 달성 → 보상 수령 (CLAIM)
	if claimable then
		return
			claimable.npcDialogueDone or string.format("'%s' 퀘스트를 완료했군! 보상을 받아가게.", claimable.title),
			{
				{ text = string.format("보상 받기 (XP +%d, 골드 +%d)", claimable.rewardXP, claimable.rewardGold), action = "CLAIM", questId = claimable.id },
				{ text = "나중에 받겠습니다.", action = "CLOSE" },
			}
	end

	-- 진행 중 (목표 미달성)
	if active then
		return
			active.npcDialogue or string.format("'%s' 퀘스트가 진행 중이라네.\n\n%s", active.title, active.trackerDesc or ""),
			{{ text = "알겠습니다, 계속 해보겠습니다.", action = "CLOSE" }}
	end

	-- 다음 퀘스트 제안
	if nextAvail then
		return
			nextAvail.npcDialogue or string.format("새 퀘스트: <b>%s</b>\n%s", nextAvail.title, nextAvail.trackerDesc or ""),
			{
				{ text = string.format("수락하겠습니다! (XP +%d, 골드 +%d)", nextAvail.rewardXP, nextAvail.rewardGold), action = "ACCEPT", questId = nextAvail.id },
				{ text = "나중에 하겠습니다.", action = "CLOSE" },
			}
	end

	return "잠시 후 다시 이야기하세.", {{ text = "알겠습니다.", action = "CLOSE" }}
end

local function handleOpen(player)
	if not NetController then return end
	local dialogue, choices = _buildDialogue(player.UserId)
	NetController.FireClient(player, "Magician.OpenDialogue", {
		npcName  = "마법사",
		dialogue = dialogue,
		choices  = choices,
	})
end

-- 퀘스트 액션 핸들러 (C→S)
local function handleQuestAction(player, payload)
	local userId  = player.UserId
	local action  = payload and payload.action
	local questId = payload and payload.questId

	-- ACCEPT: 퀘스트 수락
	if action == "ACCEPT" then
		local q = questId and QUEST_BY_ID[questId]
		if not q then return { success = false } end
		local d = _getData(userId)
		if d.acceptedQuests[q.id] or d.completedQuests[q.id] then
			return { success = false, reason = "already" }
		end

		d.acceptedQuests[q.id] = true

		-- PORTAL_REGISTER: 이미 등록되어 있으면 즉시 objectiveDone
		if q.type == "PORTAL_REGISTER" and q.targetPortalId then
			if SaveService then
				local state = SaveService.getPlayerState(userId)
				if state and state.worldPortals and state.worldPortals.registered then
					if state.worldPortals.registered[q.targetPortalId] == true then
						d.objectiveDone[q.id] = true
					end
				end
			end
		end

		_saveToState(userId)
		_updateIndicator(player)
		_updateQuestTracker(player)

		if NetController then
			local notifyText = d.objectiveDone[q.id]
				and string.format("퀘스트 '%s': 이미 달성했군요! 마법사에게 보고하세요.", q.title)
				or  string.format("퀘스트 수락: %s", q.title)
			NetController.FireClient(player, "Notify.Message", {
				text  = notifyText,
				color = "GOLD",
			})
		end
		return { success = true }

	-- CLAIM: NPC에게 보고 → 보상 수령 (TrainerQuestService CLAIM과 동일)
	elseif action == "CLAIM" then
		local q = questId and QUEST_BY_ID[questId]
		if not q then return { success = false } end
		local d = _getData(userId)

		if not d.acceptedQuests[q.id]  then return { success = false, reason = "not_accepted" } end
		if d.completedQuests[q.id]     then return { success = false, reason = "already_claimed" } end
		if not d.objectiveDone[q.id]   then return { success = false, reason = "not_done" } end

		-- 보상 지급
		if PlayerStatService and PlayerStatService.addXP then
			PlayerStatService.addXP(userId, q.rewardXP, "MagicianQuest")
		end
		local goldSvc = _getGoldService()
		if goldSvc and goldSvc.addGold then goldSvc.addGold(userId, q.rewardGold) end

		d.completedQuests[q.id] = true
		_saveToState(userId)
		_updateIndicator(player)
		_updateQuestTracker(player)

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text  = string.format("퀘스트 완료! '%s' — XP +%d, 골드 +%d 획득!", q.title, q.rewardXP, q.rewardGold),
				color = "GOLD",
			})
		end

		-- 다음 퀘스트 대화 즉시 오픈
		task.defer(function() handleOpen(player) end)
		return { success = true }
	end

	return { success = false }
end

-- ── 목표 달성 이벤트 (외부 서비스에서 호출) ──

local function _markObjectiveDone(player, questType, targetPortalId)
	local userId = player.UserId
	local d = _getData(userId)

	for _, q in ipairs(QUESTS) do
		if q.type == questType then
			if targetPortalId == nil or q.targetPortalId == targetPortalId then
				if d.acceptedQuests[q.id] and not d.completedQuests[q.id] and not d.objectiveDone[q.id] then
					d.objectiveDone[q.id] = true
					_saveToState(userId)
					_updateIndicator(player)
					_updateQuestTracker(player)
					if NetController then
						NetController.FireClient(player, "Notify.Message", {
							text  = string.format("'%s' 목표 달성! 마법사에게 돌아가 보고하세요.", q.title),
							color = "GOLD",
						})
					end
				end
			end
		end
	end
end

function MagicianQuestService.OnPortalRegistered(player, portalId)
	_markObjectiveDone(player, "PORTAL_REGISTER", portalId)
end

function MagicianQuestService.OnPortalTeleport(player, portalId)
	_markObjectiveDone(player, "PORTAL_TELEPORT", portalId)
end

function MagicianQuestService.OnVillageReturn(player)
	_markObjectiveDone(player, "VILLAGE_RETURN", nil)
end

-- ── Init ──

function MagicianQuestService.Init(netController, saveService, playerStatService)
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
			_updateIndicator(player)
			_updateQuestTracker(player)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.wait(4)
			_loadFromSave(player.UserId)
			_updateIndicator(player)
			_updateQuestTracker(player)
		end)
	end

	task.defer(function()
		local npcFolder = workspace:WaitForChild("NPC", 30)
		if not npcFolder then warn("[MagicianQuestService] NPC folder not found"); return end
		local magician  = npcFolder:WaitForChild("Magician", 30)
		if not magician  then warn("[MagicianQuestService] Magician NPC not found"); return end
		local rootPart  = magician:WaitForChild("HumanoidRootPart", 15)
		if not rootPart  then warn("[MagicianQuestService] Magician has no HumanoidRootPart"); return end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name                  = "MagicianPrompt"
		prompt.ActionText            = "대화하기"
		prompt.ObjectText            = "마법사"
		prompt.KeyboardKeyCode       = Enum.KeyCode.E
		prompt.HoldDuration          = 0.3
		prompt.RequiresLineOfSight   = false
		prompt.MaxActivationDistance = 10
		prompt.Parent                = rootPart

		prompt.Triggered:Connect(function(player)
			_loadFromSave(player.UserId)
			handleOpen(player)
		end)

		print("[MagicianQuestService] Magician NPC prompt registered.")
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerData[player.UserId] = nil
	end)
end

local function handleVillageReturn(player)
	MagicianQuestService.OnVillageReturn(player)
	return { success = true }
end

local function handleQuestReset(player)
	local userId = player.UserId
	playerData[userId] = { acceptedQuests = {}, completedQuests = {}, objectiveDone = {} }
	if SaveService then
		SaveService.updatePlayerState(userId, function(state)
			state.magicianQuestData = nil
			return state
		end)
	end
	_updateIndicator(player)
	_updateQuestTracker(player)
	print(string.format("[MagicianQuestService] Quest reset for %s", player.Name))
	return { success = true }
end

function MagicianQuestService.GetHandlers()
	return {
		["Magician.QuestAction.Request"] = handleQuestAction,
		["Magician.VillageReturn.Event"] = handleVillageReturn,
		["Magician.Quest.Reset.Request"] = handleQuestReset,
	}
end

return MagicianQuestService
