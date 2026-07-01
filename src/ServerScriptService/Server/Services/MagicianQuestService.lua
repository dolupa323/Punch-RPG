-- MagicianQuestService.lua
-- Magician NPC 포탈 교육 퀘스트 시스템
-- 퀘스트: 포탈 등록 / 포탈 이동 / 마을 귀환 실습

local MagicianQuestService = {}

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceRegistry = require(ReplicatedStorage.Shared.Utils.ServiceRegistry)

local NetController    = nil
local SaveService      = nil
local PlayerStatService = nil
local initialized      = false

-- ── 퀘스트 정의 ──
-- 포탈 시스템 구조:
--   각 지역 포탈 모델(현지) → E키로 등록 → 마을 포탈 목록에 해금 → 마을 포탈 E키 → 선택 이동
local QUESTS = {
	{
		id    = "MAGICIAN_INTRO",
		order = 1,
		title = "포탈 마법사와 대화",
		-- 퀘스트 트래커 설명 (짧고 행동 지시형)
		trackerDesc = "마을의 마법사에게 말을 걸어보세요.",
		type  = "TALK",
		rewardXP   = 300,
		rewardGold = 100,
		-- NPC 대화: 포탈 시스템 전체 구조를 먼저 설명
		npcDialogue = "오오, 반갑소 여행자!\n나는 포탈 마법을 연구하는 마법사라오.\n\n이 세계의 <b>포탈 시스템</b>을 설명해 주겠소.\n\n① 각 지역에는 <b>포탈</b>이 세워져 있다오.\n② 그 앞에서 <b>E키</b>를 누르면 그 지역이 <b>등록</b>되지요.\n③ 등록한 지역은 마을 중앙 포탈에서 <b>순간이동</b>으로 언제든 갈 수 있다오!\n\n먼저 초원에 있는 포탈을 찾아 등록해 보겠나?",
		npcChoices = {
			{ text = "배워보겠습니다! (퀘스트 수락)", action = "ACCEPT_AND_CLOSE" },
			{ text = "나중에 하겠습니다.", action = "CLOSE" },
		},
	},
	{
		id    = "MAGICIAN_REGISTER",
		order = 2,
		title = "초원 포탈 등록",
		trackerDesc = "초원 지역으로 이동 → 포탈 앞에서 E키로 등록",
		type  = "PORTAL_REGISTER",
		targetPortalId = "Grasslands",
		rewardXP   = 500,
		rewardGold = 200,
		-- 수락 시 NPC 대사 (아직 안 했을 때)
		npcDialogue = "초원 방향으로 나가면 포탈이 보일 것이오.\n포탈에 가까이 다가가서 <b>E키</b>를 누르면\n그 지역이 내 포탈 목록에 <b>등록</b>된다오.\n\n등록을 완료하면 이곳으로 돌아오게나!",
		-- 등록 완료 후 돌아왔을 때 NPC 대사
		npcDialogueDone = "오호! 초원 포탈을 등록했군!\n이제 마을 중앙 포탈에서 초원을 선택해 이동할 수 있다오.\n\n마을 포탈은 이 근처 중앙 광장에 있으니\n가서 <b>E키</b>로 상호작용해 보게나!",
	},
	{
		id    = "MAGICIAN_TELEPORT",
		order = 3,
		title = "마을 포탈로 초원 이동",
		trackerDesc = "마을 중앙 포탈 → E키 상호작용 → 초원 선택 → 이동",
		type  = "PORTAL_TELEPORT",
		targetPortalId = "Grasslands",
		rewardXP   = 800,
		rewardGold = 300,
		npcDialogue = "마을 중앙에 있는 큰 포탈 석상으로 가보게!\n<b>E키</b>를 누르면 등록된 지역 목록이 열린다오.\n거기서 <b>초원</b>을 선택하면 순간이동이 된다네!\n\n이동하고 나면 마을귀환 방법도 배워야 하네.",
		npcDialogueDone = "초원까지 포탈로 다녀왔구나! 훌륭하이!\n이제 마지막으로 <b>마을귀환</b> 기능을 배워보세나.",
	},
	{
		id    = "MAGICIAN_VILLAGE_RETURN",
		order = 4,
		title = "마을귀환 버튼 사용",
		trackerDesc = "어디서든 화면 하단 [마을귀환] 버튼 → 마을로 복귀",
		type  = "VILLAGE_RETURN",
		rewardXP   = 600,
		rewardGold = 250,
		npcDialogue = "마지막 수업이오!\n멀리 떠났다가 돌아오고 싶을 때를 대비해야 하지.\n\n화면 <b>하단 중앙</b>에 <b>[마을귀환]</b> 버튼이 있다오.\n포탈 없이도 그 버튼 하나로 즉시 마을로 돌아올 수 있다네!\n\n한번 눌러보게나. 어디 있든 바로 이 마을로 돌아온다오.",
		npcDialogueDone = "완벽하이! 이제 자네는 어떤 지역에 가더라도\n포탈로 이동하고, 마을귀환으로 복귀하는 것을 알게 됐군.\n\n앞으로의 여정에서 이 지식이 큰 도움이 될 것이오. 행운을 빌겠네!",
	},
}

local QUEST_BY_ID = {}
for _, q in ipairs(QUESTS) do QUEST_BY_ID[q.id] = q end

local playerData = {} -- [userId] = { acceptedQuests, completedQuests }

local function _getGoldService()
	return ServiceRegistry.Get("NPCShopService")
end

local function _getData(userId)
	if not playerData[userId] then
		playerData[userId] = { acceptedQuests = {}, completedQuests = {} }
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
		}
	else
		playerData[userId] = { acceptedQuests = {}, completedQuests = {} }
	end
end

local function _saveToState(userId)
	if not SaveService then return end
	SaveService.updatePlayerState(userId, function(state)
		local d = _getData(userId)
		state.magicianQuestData = {
			acceptedQuests  = d.acceptedQuests,
			completedQuests = d.completedQuests,
		}
		return state
	end)
end

-- 인디케이터 상태 계산
local function _getIndicatorState(userId)
	local d = _getData(userId)
	for _, q in ipairs(QUESTS) do
		if d.completedQuests[q.id] then
			-- skip
		elseif d.acceptedQuests[q.id] then
			-- TALK 퀘스트는 대화 즉시 완료 → 여기 오면 아직 진행중
			return "NONE"
		else
			local prevDone = true
			if q.order > 1 then
				for _, pq in ipairs(QUESTS) do
					if pq.order == q.order - 1 and not d.completedQuests[pq.id] then
						prevDone = false; break
					end
				end
			end
			if prevDone then
				return "AVAILABLE" -- 느낌표
			end
		end
	end
	return "NONE"
end

local function _updateIndicator(player)
	if not NetController then return end
	local state = _getIndicatorState(player.UserId)
	NetController.FireClient(player, "Magician.SetIndicator", { state = state })
end

-- 퀘스트 트래커 전송
local function _updateQuestTracker(player)
	if not NetController then return end
	local userId = player.UserId
	local d      = _getData(userId)

	local activeQuest = nil
	for _, q in ipairs(QUESTS) do
		if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
			activeQuest = q; break
		end
	end

	if activeQuest then
		NetController.FireClient(player, "Magician.QuestTracker", {
			active   = true,
			title    = activeQuest.title,
			desc     = activeQuest.trackerDesc or activeQuest.desc or "",
			doneText = "완료! 마법사에게 돌아가세요.",
		})
	else
		NetController.FireClient(player, "Magician.QuestTracker", { active = false })
	end
end

-- 다음 수락 가능 / 진행중 / 완료 가능 퀘스트 탐색
local function _getCurrentContext(userId)
	local d = _getData(userId)
	local active, claimable, nextAvailable = nil, nil, nil

	for _, q in ipairs(QUESTS) do
		if d.completedQuests[q.id] then
			-- skip
		elseif d.acceptedQuests[q.id] then
			active = q; break
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

	local allDone = true
	for _, q in ipairs(QUESTS) do
		if not d.completedQuests[q.id] then allDone = false; break end
	end

	return active, claimable, nextAvailable, allDone
end

local function _buildDialogue(userId)
	local d = _getData(userId)
	local active, _, nextAvail, allDone = _getCurrentContext(userId)

	-- 모든 퀘스트 완료
	if allDone then
		local lastQ = QUESTS[#QUESTS]
		return
			lastQ.npcDialogueDone or "이미 모든 포탈 수련을 마쳤군!\n포탈과 마을귀환을 자유자재로 쓸 수 있는 여행자가 됐다네.\n앞으로 좋은 여정이 되길 바라네!",
			{{ text = "감사합니다, 마법사님.", action = "CLOSE" }}
	end

	-- 진행 중인 퀘스트가 있음 (완료 후 돌아온 경우 → npcDialogueDone, 아직 진행 중 → npcDialogue)
	if active then
		-- 퀘스트 완료 여부 체크 (완료됐는데 active로 잡히는 경우는 없지만 방어)
		local dialogue = active.npcDialogue or ("'" .. active.title .. "' 퀘스트를 진행 중이라네.\n" .. (active.trackerDesc or ""))
		return dialogue, {{ text = "알겠습니다, 계속 해보겠습니다.", action = "CLOSE" }}
	end

	-- 완료된 퀘스트 다음에 새 퀘스트 제안
	if nextAvail then
		-- 바로 전 퀘스트가 완료됐다면 완료 축하 대사 먼저 보여주고 다음 퀘스트 제안
		local prevDoneDialogue = nil
		if nextAvail.order > 1 then
			for _, pq in ipairs(QUESTS) do
				if pq.order == nextAvail.order - 1 and d.completedQuests[pq.id] and pq.npcDialogueDone then
					prevDoneDialogue = pq.npcDialogueDone
					break
				end
			end
		end

		if nextAvail.type == "TALK" then
			return
				nextAvail.npcDialogue,
				nextAvail.npcChoices or {
					{ text = "배워보겠습니다! (수락)", action = "ACCEPT_AND_CLOSE", questId = nextAvail.id },
					{ text = "나중에 하겠습니다.", action = "CLOSE" },
				}
		else
			local dialogue = prevDoneDialogue or nextAvail.npcDialogue or ("새로운 퀘스트가 있다네.\n\n<b>" .. nextAvail.title .. "</b>\n" .. (nextAvail.trackerDesc or ""))
			return
				dialogue,
				{
					{ text = string.format("수락하겠습니다! (XP +%d, 골드 +%d)", nextAvail.rewardXP, nextAvail.rewardGold), action = "ACCEPT", questId = nextAvail.id },
					{ text = "나중에 하겠습니다.", action = "CLOSE" },
				}
		end
	end

	return "잠시 후 다시 이야기하세.", {{ text = "알겠습니다.", action = "CLOSE" }}
end

-- NPC 대화 오픈
local function handleOpen(player)
	if not NetController then return end
	local dialogue, choices = _buildDialogue(player.UserId)
	NetController.FireClient(player, "Magician.OpenDialogue", {
		npcName  = "마법사",
		dialogue = dialogue,
		choices  = choices,
	})
end

-- 퀘스트 액션 핸들러
local function handleQuestAction(player, payload)
	local userId = player.UserId
	local action  = payload and payload.action
	local questId = payload and payload.questId

	if action == "ACCEPT" or action == "ACCEPT_AND_CLOSE" then
		local q = questId and QUEST_BY_ID[questId]
		-- ACCEPT_AND_CLOSE 시 questId가 없을 경우 nextAvailable 자동 선택
		if not q then
			local _, _, nextAvail = _getCurrentContext(userId)
			q = nextAvail
		end
		if not q then return { success = false } end

		local d = _getData(userId)
		if d.acceptedQuests[q.id] or d.completedQuests[q.id] then
			return { success = false, reason = "already" }
		end
		d.acceptedQuests[q.id] = true

		-- PORTAL_REGISTER: 이미 등록되어 있으면 즉시 완료
		if q.type == "PORTAL_REGISTER" and q.targetPortalId then
			local alreadyRegistered = false
			if SaveService then
				local state = SaveService.getPlayerState(userId)
				if state and state.worldPortals and state.worldPortals.registered then
					alreadyRegistered = state.worldPortals.registered[q.targetPortalId] == true
				end
			end
			if alreadyRegistered then
				d.completedQuests[q.id] = true
				if PlayerStatService and PlayerStatService.addXP then
					PlayerStatService.addXP(userId, q.rewardXP, "MagicianQuest")
				end
				local goldSvc = _getGoldService()
				if goldSvc and goldSvc.addGold then goldSvc.addGold(userId, q.rewardGold) end
				if NetController then
					NetController.FireClient(player, "Notify.Message", {
						text  = string.format("퀘스트 완료: %s — XP +%d, 골드 +%d!", q.title, q.rewardXP, q.rewardGold),
						color = "GOLD",
					})
				end
				_advanceToNext(player)
				return { success = true }
			end
		end

		-- TALK 퀘스트는 수락과 동시에 완료
		if q.type == "TALK" then
			d.completedQuests[q.id] = true
			if PlayerStatService and PlayerStatService.addXP then
				PlayerStatService.addXP(userId, q.rewardXP, "MagicianQuest")
			end
			local goldSvc = _getGoldService()
			if goldSvc and goldSvc.addGold then goldSvc.addGold(userId, q.rewardGold) end
			_saveToState(userId)
			_updateIndicator(player)
			_updateQuestTracker(player)
			if NetController then
				NetController.FireClient(player, "Notify.Message", {
					text  = string.format("퀘스트 완료: %s — XP +%d, 골드 +%d!", q.title, q.rewardXP, q.rewardGold),
					color = "GOLD",
				})
			end
			-- 다음 퀘스트 자동 오픈
			if action == "ACCEPT_AND_CLOSE" then
				return { success = true }
			end
			task.defer(function() handleOpen(player) end)
			return { success = true }
		end

		_saveToState(userId)
		_updateIndicator(player)
		_updateQuestTracker(player)
		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text  = string.format("퀘스트 수락: %s — %s", q.title, q.trackerDesc or q.desc or ""),
				color = "GOLD",
			})
		end
		return { success = true }
	end

	return { success = false }
end

-- ── 진행 조건 달성 이벤트 처리 ──

-- 다음 퀘스트 자동 수락 + 트래커/인디케이터 업데이트 (보상 지급 없음)
local function _advanceToNext(player)
	local userId = player.UserId
	local _, _, nextAvail = _getCurrentContext(userId)
	if nextAvail and nextAvail.type ~= "TALK" then
		local d = _getData(userId)
		if not d.acceptedQuests[nextAvail.id] then
			d.acceptedQuests[nextAvail.id] = true
		end
	end
	_saveToState(userId)
	_updateIndicator(player)
	_updateQuestTracker(player)
end

-- 완료 후 다음 퀘스트 자동 수락 + 트래커/인디케이터 한 번에 업데이트
local function _completeAndAdvance(player, q)
	local userId = player.UserId
	if PlayerStatService and PlayerStatService.addXP then
		PlayerStatService.addXP(userId, q.rewardXP, "MagicianQuest")
	end
	local goldSvc = _getGoldService()
	if goldSvc and goldSvc.addGold then goldSvc.addGold(userId, q.rewardGold) end
	_advanceToNext(player)
end

-- 포탈 등록 시 호출
function MagicianQuestService.OnPortalRegistered(player, portalId)
	local userId = player.UserId
	local d      = _getData(userId)

	for _, q in ipairs(QUESTS) do
		if q.type == "PORTAL_REGISTER" and q.targetPortalId == portalId then
			if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
				d.completedQuests[q.id] = true
				if NetController then
					NetController.FireClient(player, "Notify.Message", {
						text  = string.format("퀘스트 완료: %s — XP +%d, 골드 +%d!", q.title, q.rewardXP, q.rewardGold),
						color = "GOLD",
					})
				end
				_completeAndAdvance(player, q)
			end
		end
	end
end

-- 포탈 이동 시 호출
function MagicianQuestService.OnPortalTeleport(player, portalId)
	local userId = player.UserId
	local d      = _getData(userId)

	for _, q in ipairs(QUESTS) do
		if q.type == "PORTAL_TELEPORT" and q.targetPortalId == portalId then
			if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
				d.completedQuests[q.id] = true
				if NetController then
					NetController.FireClient(player, "Notify.Message", {
						text  = string.format("퀘스트 완료: %s — XP +%d, 골드 +%d!\n이번엔 화면 하단 [마을귀환] 버튼을 눌러보세요!", q.title, q.rewardXP, q.rewardGold),
						color = "GOLD",
					})
				end
				_completeAndAdvance(player, q)
			end
		end
	end
end

-- 마을귀환 버튼 사용 시 호출
local function handleVillageReturn(player)
	local userId = player.UserId
	local d      = _getData(userId)

	for _, q in ipairs(QUESTS) do
		if q.type == "VILLAGE_RETURN" then
			if d.acceptedQuests[q.id] and not d.completedQuests[q.id] then
				d.completedQuests[q.id] = true
				if NetController then
					NetController.FireClient(player, "Notify.Message", {
						text  = string.format("퀘스트 완료: %s — XP +%d, 골드 +%d!\n마법사에게 돌아가 마지막 인사를 나누세요!", q.title, q.rewardXP, q.rewardGold),
						color = "GOLD",
					})
				end
				_completeAndAdvance(player, q)
			end
		end
	end
	return { success = true }
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

	-- NPC 프롬프트 연결
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

-- PlayerLifeService 등 서버 내부에서 직접 호출하는 퍼블릭 메서드
function MagicianQuestService.OnVillageReturn(player)
	handleVillageReturn(player)
end

local function handleQuestReset(player)
	local userId = player.UserId
	playerData[userId] = { acceptedQuests = {}, completedQuests = {} }
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
