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
local claimDebounce = {}

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

local function notify(player: Player, text: string)
	if NetController then
		NetController.FireClient(player, "Notify.Message", { text = text })
	end
end

local function getKSTDate(timestamp: number)
	return os.date("!*t", timestamp + 9 * 3600)
end

local function isSameKSTDay(time1: number, time2: number): boolean
	if not time1 or not time2 or time1 <= 0 or time2 <= 0 then
		return false
	end
	local d1 = getKSTDate(time1)
	local d2 = getKSTDate(time2)
	return d1.year == d2.year and d1.month == d2.month and d1.day == d2.day
end

local function claimDailyReward(player: Player): (boolean, string?)
	local userId = player.UserId
	if claimDebounce[userId] then
		return false, "ALREADY_CLAIMED"
	end
	claimDebounce[userId] = true

	local now = os.time()

	local state = SaveService and SaveService.getPlayerState and SaveService.getPlayerState(userId)
	local lastClaimTime = 0
	if state then
		lastClaimTime = tonumber(state.lastRuneStoneClaimTimestamp) or 0
	end

	-- Check if already claimed today
	if lastClaimTime > 0 and isSameKSTDay(lastClaimTime, now) then
		claimDebounce[userId] = nil
		return false, "ALREADY_CLAIMED"
	end

	-- Check inventory space for "강화 하락방지권" (Item ID: 3602118498)
	local added, remaining = InventoryService.addItem(userId, "3602118498", 1)
	if added <= 0 or remaining > 0 then
		claimDebounce[userId] = nil
		return false, "INV_FULL"
	end

	-- Add 100 Gold
	local NPCShopService = require(game:GetService("ServerScriptService").Server.Services.NPCShopService)
	NPCShopService.addGold(userId, 100)

	-- Update state
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(st)
			st.lastRuneStoneClaimTimestamp = now
			return st
		end)
	end
	
	claimDebounce[userId] = nil

	-- Save player
	if SaveService and SaveService.savePlayer then
		task.spawn(function()
			pcall(function()
				SaveService.savePlayer(userId)
			end)
		end)
	end

	return true
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

local function _attachNpcLabel(root: BasePart, name: string, role: string)
	if not root or root:FindFirstChild("NpcLabel") then return end
	local label = Instance.new("BillboardGui")
	label.Name = "NpcLabel"
	label.Size = UDim2.new(0, 200, 0, 50)
	label.StudsOffset = Vector3.new(0, 4.5, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = 80
	label.Parent = root

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.SourceSansBold
	text.TextColor3 = Color3.fromRGB(255, 233, 184)
	text.TextStrokeTransparency = 0.35
	text.Text = string.format("%s\n%s", name, role)
	text.Parent = label
end

local function bindRuneStoneModel(model: Instance)
	if not model then return end
	local promptPart = getPromptPart(model)
	if promptPart then
		local existingPrompt = promptPart:FindFirstChild("RuneStonePrompt")
		if existingPrompt then
			existingPrompt:Destroy()
		end
		
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RuneStonePrompt"
		prompt.ActionText = "일일보상"
		prompt.ObjectText = "룬스톤"
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Parent = promptPart

		_attachNpcLabel(promptPart, "RuneStone", "일일보상")

		prompt.Triggered:Connect(function(player)
			local success, err = claimDailyReward(player)
			if success then
				-- [요청반영] 지급 즉시 소지품에만 조용히 반영하지 않고, 무엇을 받았는지
				-- 아이콘+이름+개수로 보여주는 팝업 UI를 클라이언트에 띄운다.
				if NetController then
					NetController.FireClient(player, "RuneStone.RewardShown", {
						items = { { itemId = "3602118498", count = 1 } },
						gold = 100,
					})
				end
			else
				if err == "ALREADY_CLAIMED" then
					notify(player, "이미 오늘의 일일보상을 수령했습니다.")
				elseif err == "INV_FULL" then
					notify(player, "인벤토리가 가득 찼습니다.")
				else
					notify(player, "일일보상 수령에 실패했습니다.")
				end
			end
		end)
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
