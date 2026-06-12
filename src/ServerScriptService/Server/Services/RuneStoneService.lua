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
local RUNE_CLAIM_LIMIT = 1
local playerClaimCache = {} -- [userId] = count
local boundPrompts = {}

local runeRewardSequence = {
	{ itemId = "BOOK_FLAME", displayName = "화염" },
	{ itemId = "BOOK_WAVE", displayName = "파도" },
	{ itemId = "BOOK_SHADOW", displayName = "그림자" },
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
	local claimCount = getPlayerClaimCount(player.UserId)
	if claimCount >= RUNE_CLAIM_LIMIT then
		return nil, "CLAIM_LIMIT_REACHED"
	end
	local rewardIndex = math.random(1, #runeRewardSequence)
	return runeRewardSequence[rewardIndex], nil
end

local function notify(player: Player, text: string)
	if NetController then
		NetController.FireClient(player, "Notify.Message", { text = text })
	end
end

local function awardRune(player: Player)
	local userId = player.UserId

	local reward, errCode = getRuneReward(player)
	if not reward then
		if errCode == "CLAIM_LIMIT_REACHED" then
			notify(player, "이미 룬스톤 보상을 획득했습니다.")
		end
		return false, errCode or "NO_REWARD"
	end

	local added, remaining = InventoryService.addItem(userId, reward.itemId, 1)
	if added <= 0 or remaining > 0 then
		notify(player, "인벤토리가 가득 찼습니다.")
		return false, "INV_FULL"
	end

	local claimCount = getPlayerClaimCount(userId)
	setPlayerClaimCount(userId, claimCount + 1)
	notify(player, string.format("스킬북 [%s]을 획득했습니다!", reward.displayName))

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
	-- 룬스톤 상호작용 폐지로 인해 프롬프트를 바인딩하지 않음
	if not model then return end
	local promptPart = getPromptPart(model)
	if promptPart then
		local existingPrompt = promptPart:FindFirstChild("RuneStonePrompt")
		if existingPrompt then
			existingPrompt:Destroy()
		end
	end
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
