-- MermanService.lua
-- 클레이온 수중도시 수문장 Merman NPC
-- 레벨 45 미만: 경고 대사 → 닫기 시 청운촌으로 추방
-- 레벨 45 이상: "젤리피쉬 사냥" 퀘스트 부여 (30마리 처치 -> 골드 보상)
-- TrainerQuestService / CitizenQuestService 컨벤션 준수

local MermanService = {}

local Workspace  = game:GetService("Workspace")
local Players    = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceRegistry = require(ReplicatedStorage.Shared.Utils.ServiceRegistry)

local NetController     = nil
local SaveService       = nil
local PlayerStatService = nil
local initialized       = false

local QUEST_LEVEL     = 45  -- [수정] 50 -> 45: 이 레벨 이상이면 추방 대신 퀘스트 부여
local COOLDOWN        = 3.0
local debounces       = {}

-- 젤리피쉬 사냥 퀘스트 정의
local QUEST = {
	id            = "MERMAN_JELLYFISH",
	title         = "젤리피쉬 소탕",
	targetMob     = "젤리피쉬",
	requiredKills = 30,
	rewardGold    = 5000,
}

-- 플레이어별 "닫기 후 추방" 대기 여부
local pendingReturn = {}

-- [userId] = { acceptedQuest=bool, completedQuest=bool, killProgress=number }
local playerData = {}

local function getSaveService()
	if SaveService then return SaveService end
	SaveService = require(game:GetService("ServerScriptService").Server.Services.SaveService)
	return SaveService
end

local function getPlayerLevel(userId)
	-- [버그수정] SaveService의 저장 상태(state.level)는 항상 nil이라 모든 플레이어가
	-- 레벨 1로 취급되어 무조건 추방당하는 버그가 있었음. 실제 레벨은
	-- PlayerStatService의 인메모리 상태(getLevel)가 정확한 소스.
	if PlayerStatService and PlayerStatService.getLevel then
		return PlayerStatService.getLevel(userId) or 1
	end
	local state = getSaveService().getPlayerState(userId)
	return (state and state.level) or 1
end

local function getGoldService()
	return ServiceRegistry.Get("NPCShopService")
end

local function _emptyState()
	return { acceptedQuest = false, completedQuest = false, killProgress = 0 }
end

local function _getData(userId)
	if not playerData[userId] then
		playerData[userId] = _emptyState()
	end
	return playerData[userId]
end

local function _loadFromSave(userId)
	local saved = nil
	local state = getSaveService().getPlayerState(userId)
	saved = state and state.mermanQuestData
	playerData[userId] = {
		acceptedQuest  = (saved and saved.acceptedQuest)  or false,
		completedQuest = (saved and saved.completedQuest) or false,
		killProgress   = (saved and saved.killProgress)   or 0,
	}
end

local function _saveToState(userId)
	getSaveService().updatePlayerState(userId, function(state)
		state.mermanQuestData = playerData[userId]
		return state
	end)
end

-- Recall과 동일: NewWorldMap/Portal 위치 우선, 없으면 폴백
local VILLAGE_FALLBACK = Vector3.new(-35.721, 233, 253.348)

local function getVillagePos()
	local ok, pos = pcall(function()
		local newWorldMap = workspace:WaitForChild("NewWorldMap", 3)
		local portalFolder = newWorldMap:FindFirstChild("Potal") or newWorldMap:FindFirstChild("Portal")
		if portalFolder then
			local portalModel = portalFolder:FindFirstChild("Portal")
			if portalModel and portalModel:IsA("Model") then
				return portalModel:GetPivot().Position + Vector3.new(0, 5, 0)
			end
		end
		return nil
	end)
	if ok and pos then return pos end
	return VILLAGE_FALLBACK
end

local function openDialogue(player)
	local userId = player.UserId
	local level = getPlayerLevel(userId)
	local isRejected = (level < QUEST_LEVEL)

	pendingReturn[userId] = isRejected

	local dialogue, choices
	if isRejected then
		dialogue = "넌 이 클레이온에서 살아남기에는 너무나도 나약하군."
		choices = {
			{ text = "돌아가겠습니다.", action = "CLOSE" },
		}
	else
		local d = _getData(userId)
		if d.completedQuest then
			dialogue = "클레이온에 온 것을 환영한다. 강한 자여, 이 도시의 힘을 느껴보아라.\n\n자네 덕에 젤리피쉬 소탕이 끝났군. 정말 고맙네."
			choices = {
				{ text = "닫기", action = "CLOSE" },
			}
		elseif d.acceptedQuest then
			local remain = math.max(0, QUEST.requiredKills - d.killProgress)
			if remain <= 0 then
				dialogue = string.format("호오, 벌써 젤리피쉬 %d마리를 소탕했군! 정말 대단해. 약속한 보상을 받아가게.", QUEST.requiredKills)
				choices = {
					{ text = string.format("보상 받기 (골드 +%d)", QUEST.rewardGold), action = "CLAIM", questId = QUEST.id },
					{ text = "나중에 받겠습니다.", action = "CLOSE" },
				}
			else
				dialogue = string.format("아직 젤리피쉬 소탕이 끝나지 않았군. 남은 처치: %d / %d마리.", d.killProgress, QUEST.requiredKills)
				choices = {
					{ text = "계속 해보겠습니다.", action = "CLOSE" },
				}
			end
		else
			dialogue = "클레이온에 온 것을 환영한다. 강한 자여, 이 도시의 힘을 느껴보아라.\n\n요즘 젤리피쉬가 도시 전역에 들끓어 골치가 아프다네. 30마리만 소탕해주겠나?"
			choices = {
				{ text = string.format("수락하겠습니다! (골드 +%d)", QUEST.rewardGold), action = "ACCEPT", questId = QUEST.id },
				{ text = "나중에 하겠습니다.", action = "CLOSE" },
			}
		end
	end

	if NetController then
		NetController.FireClient(player, "Merman.OpenDialogue", {
			npcName  = "Merman",
			dialogue = dialogue,
			choices  = choices,
		})
	end
end

-- Merman.QuestAction.Request 핸들러 (클라이언트가 선택지 선택 시 호출)
local function handleQuestAction(player, payload)
	local userId = player.UserId
	local action = payload and payload.action

	if action == "CLOSE" then
		if pendingReturn[userId] then
			pendingReturn[userId] = nil
			-- 페이드 → 텔레포트
			if NetController then
				NetController.FireClient(player, "Fountain.Return", {})
			end
		end
		return { success = true }
	end

	local questId = payload and payload.questId
	if questId ~= QUEST.id then return { success = false } end
	local d = _getData(userId)

	if action == "ACCEPT" then
		if d.acceptedQuest or d.completedQuest then
			return { success = false, reason = "already" }
		end
		d.acceptedQuest = true
		_saveToState(userId)

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text  = string.format("퀘스트 수락: %s", QUEST.title),
				color = "GOLD",
			})
		end
		return { success = true }

	elseif action == "CLAIM" then
		if not d.acceptedQuest then return { success = false, reason = "not_accepted" } end
		if d.completedQuest    then return { success = false, reason = "already_claimed" } end
		if d.killProgress < QUEST.requiredKills then return { success = false, reason = "not_done" } end

		local goldSvc = getGoldService()
		if goldSvc and goldSvc.addGold then goldSvc.addGold(userId, QUEST.rewardGold) end

		d.completedQuest = true
		_saveToState(userId)

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text  = string.format("퀘스트 완료! '%s' — 골드 +%d 획득!", QUEST.title, QUEST.rewardGold),
				color = "GOLD",
			})
		end
		return { success = true }
	end

	return { success = false }
end

-- ── 몹 처치 이벤트 (PlayerStatService.incrementKill에서 호출) ──
function MermanService.OnMobKilled(userId, mobDisplayName)
	if mobDisplayName ~= QUEST.targetMob then return end
	local d = _getData(userId)
	if not d.acceptedQuest or d.completedQuest then return end
	if d.killProgress >= QUEST.requiredKills then return end

	d.killProgress = d.killProgress + 1
	_saveToState(userId)

	if d.killProgress == QUEST.requiredKills then
		local player = Players:GetPlayerByUserId(userId)
		if player and NetController then
			NetController.FireClient(player, "Notify.Message", {
				text  = string.format("'%s' 목표 달성! Merman에게 돌아가 보고하세요.", QUEST.title),
				color = "GOLD",
			})
		end
	end
end

local function findMermanRootPart()
	local npcFolder = Workspace:FindFirstChild("NPC")
	if not npcFolder then return nil end
	local merman = npcFolder:FindFirstChild("Merman")
	if not merman then return nil end

	-- HumanoidRootPart 우선
	local hrp = merman:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp end

	-- 없으면 가장 Y가 낮은 BasePart (프롬프트가 아래쪽에 뜨도록)
	local lowestPart, lowestY = nil, math.huge
	for _, d in ipairs(merman:GetDescendants()) do
		if d:IsA("BasePart") and d.Position.Y < lowestY then
			lowestY = d.Position.Y
			lowestPart = d
		end
	end
	return lowestPart
end

local function setupProximityPrompt()
	task.spawn(function()
		task.wait(2)
		local rootPart = findMermanRootPart()
		if not rootPart then
			warn("[MermanService] Workspace.NPC.Merman을 찾지 못했습니다.")
			return
		end

		-- 중복 방지
		local existing = rootPart:FindFirstChild("MermanPrompt")
		if existing then existing:Destroy() end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name                  = "MermanPrompt"
		prompt.ActionText            = "대화하기"
		prompt.ObjectText            = "Merman"
		prompt.KeyboardKeyCode       = Enum.KeyCode.E
		prompt.HoldDuration          = 0.5
		prompt.RequiresLineOfSight   = false
		prompt.MaxActivationDistance = 10
		prompt.Parent                = rootPart

		prompt.Triggered:Connect(function(player)
			local now = os.clock()
			if debounces[player.UserId] and now - debounces[player.UserId] < COOLDOWN then return end
			debounces[player.UserId] = now
			_loadFromSave(player.UserId)
			openDialogue(player)
		end)

		print("[MermanService] Merman ProximityPrompt 등록:", rootPart:GetFullName())
	end)
end

function MermanService.GetHandlers()
	return {
		["Merman.QuestAction.Request"] = handleQuestAction,
	}
end

function MermanService.Init(netController, playerStatService)
	if initialized then return end
	initialized = true

	NetController     = netController
	PlayerStatService = playerStatService
	setupProximityPrompt()

	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId]    = nil
		pendingReturn[player.UserId] = nil
		playerData[player.UserId]    = nil
	end)

	print("[MermanService] Initialized.")
end

return MermanService
