-- MermanService.lua
-- 클레이온 수중도시 수문장 Merman NPC
-- 레벨 50 미만: 경고 대사 → 닫기 시 청운촌으로 추방
-- TrainerQuestService 컨벤션 준수

local MermanService = {}

local Workspace  = game:GetService("Workspace")
local Players    = game:GetService("Players")

local NetController = nil
local initialized   = false

local REQUIRED_LEVEL  = 50
local COOLDOWN        = 3.0
local debounces       = {}

-- 플레이어별 "닫기 후 추방" 대기 여부
local pendingReturn = {}

local function getSaveService()
	return require(game:GetService("ServerScriptService").Server.Services.SaveService)
end

local function getPlayerLevel(userId)
	local state = getSaveService().getPlayerState(userId)
	return (state and state.level) or 1
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

-- Merman.QuestAction.Request 핸들러 (클라이언트가 "닫기" 선택 시 호출)
local function handleQuestAction(player, payload)
	local action = payload and payload.action
	if action == "CLOSE" then
		if pendingReturn[player.UserId] then
			pendingReturn[player.UserId] = nil
			-- 페이드 → 텔레포트
			if NetController then
				NetController.FireClient(player, "Fountain.Return", {})
			end
		end
	end
	return { success = true }
end

local function openDialogue(player)
	local level = getPlayerLevel(player.UserId)
	local isRejected = (level < REQUIRED_LEVEL)

	pendingReturn[player.UserId] = isRejected

	local dialogue, choices
	if isRejected then
		dialogue = "넌 이 클레이온에서 살아남기에는 너무나도 나약하군."
		choices = {
			{ text = "돌아가겠습니다.", action = "CLOSE" },
		}
	else
		dialogue = "클레이온에 온 것을 환영한다. 강한 자여, 이 도시의 힘을 느껴보아라.\n\n이 도시는 바다 아래 숨겨진 고대 문명의 마지막 흔적이다."
		choices = {
			{ text = "닫기", action = "CLOSE" },
		}
	end

	if NetController then
		NetController.FireClient(player, "Merman.OpenDialogue", {
			npcName  = "Merman",
			dialogue = dialogue,
			choices  = choices,
		})
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

function MermanService.Init(netController)
	if initialized then return end
	initialized = true

	NetController = netController
	setupProximityPrompt()

	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId]    = nil
		pendingReturn[player.UserId] = nil
	end)

	print("[MermanService] Initialized.")
end

return MermanService
