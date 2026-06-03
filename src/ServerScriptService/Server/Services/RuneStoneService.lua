-- RuneStoneService.lua
-- 월드 RuneStone 상호작용으로 액티브 룬을 지급하는 서비스

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("DataService"))
local InventoryService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("InventoryService"))
local SaveService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("SaveService"))

local RuneStoneService = {}

local NetController = nil
local initialized = false
local RUNE_STONE_NAME = "RuneStone"
local RUNE_CLAIM_LIMIT = 3
local playerClaimCache = {} -- [userId] = count
local boundPrompts = {}

local runeByElement = {
	Fire = {
		itemId = "RUNE_FLAME_ACTIVE",
		displayName = "화염",
	},
	Water = {
		itemId = "RUNE_WAVE_ACTIVE",
		displayName = "파도",
	},
	Dark = {
		itemId = "RUNE_SHADOW_ACTIVE",
		displayName = "그림자",
	},
}

local function getPlayerClaimCount(userId: number): number
	local cached = playerClaimCache[userId]
	if cached ~= nil then
		return cached
	end

	local state = SaveService and SaveService.getPlayerState and SaveService.getPlayerState(userId)
	local count = 0
	if state then
		count = math.max(0, math.floor(tonumber(state.runeStoneClaims) or 0))
	end

	playerClaimCache[userId] = count
	return count
end

local function setPlayerClaimCount(userId: number, count: number)
	count = math.max(0, math.floor(tonumber(count) or 0))
	playerClaimCache[userId] = count

	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.runeStoneClaims = count
			return state
		end)
	end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("RuneStoneClaims", count)
	end
end

local function getRuneReward(player: Player)
	local element = player:GetAttribute("Element")
	if type(element) ~= "string" or element == "" or element == "None" then
		return nil, "NO_ELEMENT"
	end

	return runeByElement[element], nil
end

local function notify(player: Player, text: string)
	if NetController then
		NetController.FireClient(player, "Notify.Message", { text = text })
	end
end

local function awardRune(player: Player)
	local userId = player.UserId
	local claimCount = getPlayerClaimCount(userId)
	if claimCount >= RUNE_CLAIM_LIMIT then
		notify(player, "룬스톤의 힘은 이미 모두 소진되었습니다.")
		return false, "LIMIT_REACHED"
	end

	local reward, errCode = getRuneReward(player)
	if not reward then
		notify(player, "먼저 속성을 선택한 뒤 다시 시도하세요.")
		return false, errCode or "NO_ELEMENT"
	end

	local added, remaining = InventoryService.addItem(userId, reward.itemId, 1)
	if added <= 0 or remaining > 0 then
		notify(player, "인벤토리가 가득 찼습니다.")
		return false, "INV_FULL"
	end

	setPlayerClaimCount(userId, claimCount + 1)
	notify(player, string.format("액티브 룬 [%s]을 획득했습니다! (%d/%d)", reward.displayName, claimCount + 1, RUNE_CLAIM_LIMIT))

	if SaveService and SaveService.savePlayer then
		task.spawn(function()
			pcall(function()
				SaveService.savePlayer(userId)
			end)
		end)
	end

	return true, reward.itemId
end

local function getPromptPart(model: Instance): BasePart?
	if model:IsA("BasePart") then
		return model
	end

	local primary = model:IsA("Model") and model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end

	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			return child
		end
	end

	return nil
end

local function bindRuneStoneModel(model: Instance)
	if not model or not (model:IsA("Model") or model:IsA("BasePart")) then
		return
	end

	local promptPart = getPromptPart(model)
	if not promptPart then
		warn(string.format("[RuneStoneService] RuneStone model '%s' has no BasePart to attach prompt.", model:GetFullName()))
		return
	end

	local existingPrompt = promptPart:FindFirstChild("RuneStonePrompt")
	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		existingPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RuneStonePrompt"
	prompt.ActionText = "룬 획득"
	prompt.ObjectText = "룬스톤"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart

	prompt.Triggered:Connect(function(player)
		awardRune(player)
	end)

	boundPrompts[prompt] = true
end

local function scanForRuneStone()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst.Name == RUNE_STONE_NAME and (inst:IsA("Model") or inst:IsA("BasePart")) then
			bindRuneStoneModel(inst)
		end
	end
end

function RuneStoneService.Init(netController)
	if initialized then return end
	initialized = true
	NetController = netController

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("RuneStoneClaims", getPlayerClaimCount(player.UserId))
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player then
			playerClaimCache[player.UserId] = nil
		end
	end)

	if SaveService and SaveService.PlayerSaveLoaded then
		SaveService.PlayerSaveLoaded.Event:Connect(function(userId, state)
			local count = 0
			if state then
				count = math.max(0, math.floor(tonumber(state.runeStoneClaims) or 0))
			end
			playerClaimCache[userId] = count
			local player = Players:GetPlayerByUserId(userId)
			if player then
				player:SetAttribute("RuneStoneClaims", count)
			end
		end)
	end

	scanForRuneStone()
	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == RUNE_STONE_NAME and (inst:IsA("Model") or inst:IsA("BasePart")) then
			task.defer(bindRuneStoneModel, inst)
		end
	end)

	print("[RuneStoneService] Initialized")
end

return RuneStoneService
