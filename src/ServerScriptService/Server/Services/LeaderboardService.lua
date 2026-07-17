-- LeaderboardService.lua
-- 레벨 / 전투력 통합 랭킹
-- OrderedDataStore는 서버 단위가 아니라 게임(Experience) 전체에 공유되므로,
-- 별도 외부 DB 없이 다른 서버에서 갱신한 값도 그대로 통합 랭킹에 반영된다.

local LeaderboardService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)

local NetController = nil
local PlayerStatService = nil
local InventoryService = nil
local initialized = false

local STORE_VERSION = "v1"
local levelStore = DataStoreService:GetOrderedDataStore("Leaderboard_Level_" .. STORE_VERSION)
local combatPowerStore = DataStoreService:GetOrderedDataStore("Leaderboard_CombatPower_" .. STORE_VERSION)

local TOP_N = 100
local UPDATE_COOLDOWN = 30 -- 초 단위. 유저당 이 주기 이내에는 재기록하지 않음 (DataStore 쓰기 한도 보호)

local lastUpdateAt = {} -- [userId] = { level = os.clock(), combatPower = os.clock() }
local lastCombatPowerValue = {} -- [userId] = 마지막으로 기록한 전투력 값 (변동 없으면 쓰기 스킵)

local nameCache = {} -- [userId] = playerName

-- [요청반영] 운영자 계정은 랭킹에 기록되지도, 노출되지도 않아야 한다.
local function isAdminAccount(userId: number): boolean
	return Balance.ADMIN_IDS and Balance.ADMIN_IDS[userId] == true
end

local function safeSetAsync(store, key, value)
	local ok, err = pcall(function()
		store:SetAsync(key, value)
	end)
	if not ok then
		warn(string.format("[LeaderboardService] SetAsync failed for key %s: %s", key, tostring(err)))
	end
	return ok
end

--- 레벨 랭킹 갱신 (레벨업 시점에 호출)
function LeaderboardService.UpdateLevel(userId: number, level: number)
	if not level or level <= 0 then return end
	if isAdminAccount(userId) then return end
	local now = os.clock()
	lastUpdateAt[userId] = lastUpdateAt[userId] or {}
	local last = lastUpdateAt[userId].level or 0
	if now - last < UPDATE_COOLDOWN then return end
	lastUpdateAt[userId].level = now
	safeSetAsync(levelStore, tostring(userId), math.floor(level))
end

--- 전투력 랭킹 갱신
function LeaderboardService.UpdateCombatPower(userId: number, combatPower: number)
	if not combatPower then return end
	if isAdminAccount(userId) then return end
	combatPower = math.floor(combatPower)
	if lastCombatPowerValue[userId] == combatPower then return end -- 값 변동 없으면 스킵

	local now = os.clock()
	lastUpdateAt[userId] = lastUpdateAt[userId] or {}
	local last = lastUpdateAt[userId].combatPower or 0
	if now - last < UPDATE_COOLDOWN then return end
	lastUpdateAt[userId].combatPower = now
	lastCombatPowerValue[userId] = combatPower
	safeSetAsync(combatPowerStore, tostring(userId), combatPower)
end

--- 서버 authoritative 전투력 계산.
--- [주의] EquipmentUI.lua 클라이언트 표시용 공식과 동일하게 유지할 것 (수치가 다르면 혼란을 줌).
function LeaderboardService.ComputeCombatPower(userId: number): number
	if not PlayerStatService or not PlayerStatService.GetCalculatedStats then return 0 end
	local calc = PlayerStatService.GetCalculatedStats(userId)
	if not calc then return 0 end

	local hp = calc.maxHealth or 100
	local stamina = calc.maxStamina or 100
	local atkMult = calc.attackMult or 1.0
	local def = calc.defense or 0
	local critChance = calc.critChance or 0
	local critMult = calc.critDamageMult or 0
	local speed = Balance.BASE_WALK_SPEED * (1 + (calc.speedMult or 0))

	local charDmg = 0
	if InventoryService and InventoryService.getInventory then
		local ok, inv = pcall(InventoryService.getInventory, userId)
		local wData = ok and inv and inv.equipment and inv.equipment.HAND
		if wData then
			local okData, DataHelper = pcall(function()
				return require(ReplicatedStorage.Shared.Util.DataHelper)
			end)
			if okData and DataHelper then
				local itemData = DataHelper.GetData("ItemData", wData.itemId)
				local quality = (wData.attributes and wData.attributes.quality) or 100
				local baseDmg = itemData and DataHelper.GetQualityAdjustedWeaponDamage(wData.itemId, quality) or 0
				local enhanceLevel = wData.attributes and wData.attributes.enhanceLevel or 0
				local bonusRate = DataHelper.GetEnhanceBonusRate(itemData and itemData.rarity or "COMMON")
				local finalDmg = math.floor(baseDmg * (1 + enhanceLevel * bonusRate) + 0.5)
				charDmg = math.floor(finalDmg * atkMult + 0.5)
			end
		end
	end

	local cpDmg = (charDmg > 0) and charDmg or math.floor(atkMult * 100)
	local cp = math.floor(hp * 0.5 + stamina * 0.2 + cpDmg * 5 + def * 10 + (critChance * 100 * 20) + (critMult * 100 * 15) + (speed * 10))
	return cp
end

--- 레벨/전투력 둘 다 최신값으로 갱신 시도 (쿨다운/변동 없음 체크는 내부에서 처리)
function LeaderboardService.RefreshPlayer(userId: number)
	if PlayerStatService and PlayerStatService.getLevel then
		local level = PlayerStatService.getLevel(userId)
		if level then
			LeaderboardService.UpdateLevel(userId, level)
		end
	end
	local cp = LeaderboardService.ComputeCombatPower(userId)
	LeaderboardService.UpdateCombatPower(userId, cp)
end

--- [ADMIN 1회성 마이그레이션] 이 랭킹 기능이 생기기 전부터 저장되어 있던 모든 유저의 세이브
--- 데이터(state.stats.level)를 DataStore ListKeysAsync로 전부 훑어서 레벨 랭킹에 소급 반영한다.
--- 전투력은 장비/스킬까지 다시 계산해야 해서 이 백필 대상에서 제외 (재접속 시 자연스럽게 채워짐).
function LeaderboardService.BackfillLevelsFromSaveData()
	local mainStore = DataStoreService:GetDataStore("DinoTribeSurvival_Main")
	local PREFIX = "PLAYER_"
	local stats = { processed = 0, written = 0, failed = 0 }

	local ok, err = pcall(function()
		local pages = mainStore:ListKeysAsync(PREFIX)
		while true do
			local items = pages:GetCurrentPage()
			for _, item in ipairs(items) do
				local userIdStr = string.match(item.KeyName, "^" .. PREFIX .. "(%d+)$")
				if userIdStr then
					stats.processed += 1
					local okGet, data = pcall(function()
						return mainStore:GetAsync(item.KeyName)
					end)
					if okGet and type(data) == "table" and data.stats and data.stats.level then
						local level = math.floor(tonumber(data.stats.level) or 0)
						if level > 0 then
							local okSet = safeSetAsync(levelStore, userIdStr, level)
							if okSet then stats.written += 1 else stats.failed += 1 end
						end
					else
						stats.failed += 1
					end
					task.wait(0.05) -- DataStore 요청 예산 보호
				end
			end
			if pages.IsFinished then break end
			pages:AdvanceToNextPageAsync()
		end
	end)

	if not ok then
		warn("[LeaderboardService] BackfillLevelsFromSaveData failed: " .. tostring(err))
	end

	print(string.format(
		"[LeaderboardService] Backfill complete: processed=%d written=%d failed=%d",
		stats.processed, stats.written, stats.failed
	))
	return stats
end

local function getDisplayName(userId: number): string
	if nameCache[userId] then return nameCache[userId] end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.Name
		return player.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Unknown"
end

local function getTop(store): { any }
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		warn("[LeaderboardService] GetSortedAsync failed: " .. tostring(pages))
		return {}
	end

	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage then
		warn("[LeaderboardService] GetCurrentPage failed: " .. tostring(page))
		return {}
	end

	local result = {}
	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if not isAdminAccount(userId) then
			table.insert(result, {
				rank  = #result + 1,
				userId = userId,
				name  = getDisplayName(userId),
				value = entry.value,
			})
		end
	end
	return result
end

local function handleGetTop(player: Player, payload: any)
	local rtype = payload and payload.type
	if rtype == "LEVEL" then
		return { success = true, data = { entries = getTop(levelStore), type = "LEVEL" } }
	elseif rtype == "COMBAT_POWER" then
		return { success = true, data = { entries = getTop(combatPowerStore), type = "COMBAT_POWER" } }
	end
	return { success = false, errorCode = "BAD_REQUEST" }
end

function LeaderboardService.GetHandlers()
	return {
		["Leaderboard.GetTop.Request"] = handleGetTop,
	}
end

--========================================
-- 마을 게시판 (Workspace.NewWorldMap.LeaderBoard.leaderboard1/2에 미리 배치된 모델의
-- SurfaceGui를 찾아 텍스트만 갱신 - Part는 새로 만들지 않음, 전 클라이언트에 자동 복제됨)
--========================================
local BOARD_TOP_N = 10
local BOARD_REFRESH_INTERVAL = 60 -- 초

local boardListFrames = {} -- { LEVEL = ScrollingFrame, COMBAT_POWER = ScrollingFrame }

local function renderBoardEntries(listFrame: ScrollingFrame, entries: { any }, valueSuffix: string)
	if not listFrame or not listFrame.Parent then return end
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	if #entries == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "아직 랭킹 데이터가 없습니다"
		emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextScaled = true
		emptyLabel.Parent = listFrame
		return
	end

	for _, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = Color3.fromRGB(15, 20, 35)
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		row.Parent = listFrame
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent = row

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, 45, 1, 0)
		rankLabel.Position = UDim2.new(0, 8, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = "#" .. tostring(entry.rank)
		rankLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextScaled = true
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.5, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 58, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = tostring(entry.name or "Unknown")
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0, 130, 1, 0)
		valueLabel.Position = UDim2.new(1, -8, 0, 0)
		valueLabel.AnchorPoint = Vector2.new(1, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = string.format("%s %s", tostring(entry.value or 0), valueSuffix)
		valueLabel.TextColor3 = Color3.fromRGB(120, 220, 100)
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextScaled = true
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Parent = row
	end
end

local function getTopN(store, n: number): { any }
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, n)
	end)
	if not ok then
		warn("[LeaderboardService] (Board) GetSortedAsync failed: " .. tostring(pages))
		return {}
	end
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage then return {} end

	local result = {}
	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if not isAdminAccount(userId) then
			table.insert(result, {
				rank = #result + 1,
				userId = userId,
				name = getDisplayName(userId),
				value = entry.value,
			})
		end
	end
	return result
end

local function refreshBoards()
	if boardListFrames.LEVEL then
		renderBoardEntries(boardListFrames.LEVEL, getTopN(levelStore, BOARD_TOP_N), "Lv")
	end
	if boardListFrames.COMBAT_POWER then
		renderBoardEntries(boardListFrames.COMBAT_POWER, getTopN(combatPowerStore, BOARD_TOP_N), "전투력")
	end
end

--- 사용자가 Studio에서 직접 배치한 Workspace.NewWorldMap.LeaderBoard.leaderboard1/leaderboard2
--- 모델의 기존 SurfaceGui(Meshes/untitled_Cube.056.SurfaceGui.Frame)를 찾아서 재사용한다.
--- 각 모델 안의 Display(TextLabel)에 제목을, Frame(ScrollingFrame)에 순위 행을 채운다.
--- leaderboard1 = 전투력 랭킹, leaderboard2 = 레벨 랭킹으로 배정 (반대로 하려면 이 두 줄만 바꾸면 됨).
local BOARD_MODEL_ASSIGNMENT = {
	{ modelName = "leaderboard1", rtype = "COMBAT_POWER", title = "⚔ 전투력 랭킹" },
	{ modelName = "leaderboard2", rtype = "LEVEL",         title = "★ 레벨 랭킹" },
}

local function findBoardGuiParts(model: Instance): (TextLabel?, ScrollingFrame?)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local gui = part:FindFirstChildOfClass("SurfaceGui")
			if gui then
				local frame = gui:FindFirstChild("Frame")
				local display = frame and frame:FindFirstChild("Display")
				local scrollFrame = frame and frame:FindFirstChildWhichIsA("ScrollingFrame")
				if display and scrollFrame then
					return display, scrollFrame
				end
			end
		end
	end
	return nil, nil
end

function LeaderboardService.EnsureBoards()
	local ok, err = pcall(function()
		local leaderBoardFolder = workspace:WaitForChild("NewWorldMap", 10):WaitForChild("LeaderBoard", 10)

		for _, def in ipairs(BOARD_MODEL_ASSIGNMENT) do
			local model = leaderBoardFolder:FindFirstChild(def.modelName)
			if not model then
				warn(string.format("[LeaderboardService] %s 모델을 찾지 못했습니다.", def.modelName))
			else
				local display, scrollFrame = findBoardGuiParts(model)
				if not scrollFrame then
					warn(string.format("[LeaderboardService] %s에서 SurfaceGui 구조를 찾지 못했습니다.", def.modelName))
				else
					if display then display.Text = def.title end
					boardListFrames[def.rtype] = scrollFrame
				end
			end
		end
	end)
	if not ok then
		warn("[LeaderboardService] EnsureBoards failed: " .. tostring(err))
	end
end

local function setupVillageBoards()
	LeaderboardService.EnsureBoards()
	refreshBoards()
	task.spawn(function()
		while true do
			task.wait(BOARD_REFRESH_INTERVAL)
			refreshBoards()
		end
	end)
end

function LeaderboardService.Init(netController, playerStatService, inventoryService)
	if initialized then return end
	initialized = true

	NetController     = netController
	PlayerStatService = playerStatService
	InventoryService  = inventoryService

	Players.PlayerAdded:Connect(function(player)
		nameCache[player.UserId] = player.Name
		task.spawn(function()
			player.CharacterAdded:Wait()
			task.wait(5) -- 스탯 하이드레이션 완료 대기
			LeaderboardService.RefreshPlayer(player.UserId)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		nameCache[player.UserId] = player.Name
	end

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		lastUpdateAt[userId] = nil
		-- lastCombatPowerValue/nameCache는 재접속 시 중복 기록 방지를 위해 유지
	end)

	task.spawn(setupVillageBoards)

	print("[LeaderboardService] Initialized")
end

return LeaderboardService
