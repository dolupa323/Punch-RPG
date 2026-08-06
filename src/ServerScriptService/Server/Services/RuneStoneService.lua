-- RuneStoneService.lua
-- 시즌 출석 보상 서비스 (게임 접속 시 자동으로 출석이 찍히고, 유저가 직접 각 일차 보상을 수령)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local AttendanceRewardData = require(DataFolder:WaitForChild("AttendanceRewardData"))

local InventoryService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("InventoryService"))
local SaveService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("SaveService"))

local RuneStoneService = {}

local NetController = nil
local initialized = false
local RUNE_STONE_NAME = "RuneStone"

-- [userId] = { loginDays = number, claimedDay = number, lastLoginDate = string }
local playerAttendanceCache = {}

local function notify(player: Player, text: string)
	if NetController then
		NetController.FireClient(player, "Notify.Message", { text = text })
	end
end

local function getKSTDate(timestamp: number)
	return os.date("!*t", timestamp + 9 * 3600)
end

local function formatKSTDateKey(timestamp: number): string
	local d = getKSTDate(timestamp)
	return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

--- 저장된 state로부터 출석 캐시 초기화 (없으면 기본값)
local function loadAttendanceState(userId: number)
	local state = SaveService and SaveService.getPlayerState and SaveService.getPlayerState(userId)
	local loginDays = 0
	local claimedDay = 0
	local lastLoginDate = ""

	if state then
		loginDays = math.clamp(math.floor(tonumber(state.attendanceLoginDays) or 0), 0, AttendanceRewardData.TOTAL_DAYS)
		claimedDay = math.clamp(math.floor(tonumber(state.attendanceClaimedDay) or 0), 0, AttendanceRewardData.TOTAL_DAYS)
		lastLoginDate = tostring(state.attendanceLastLoginDate or "")
	end

	playerAttendanceCache[userId] = {
		loginDays = loginDays,
		claimedDay = claimedDay,
		lastLoginDate = lastLoginDate,
	}
	return playerAttendanceCache[userId]
end

local function saveAttendanceState(userId: number)
	local cache = playerAttendanceCache[userId]
	if not cache then return end
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.attendanceLoginDays = cache.loginDays
			state.attendanceClaimedDay = cache.claimedDay
			state.attendanceLastLoginDate = cache.lastLoginDate
			return state
		end)
	end
end

--- 오늘 처음 접속했다면 출석일수를 1 늘림 (연속 아니어도 누적)
local function stampAttendanceOnLogin(userId: number): boolean
	local cache = playerAttendanceCache[userId] or loadAttendanceState(userId)
	local todayKey = formatKSTDateKey(os.time())

	if cache.lastLoginDate == todayKey then
		return false -- 오늘 이미 출석 찍음
	end

	cache.lastLoginDate = todayKey
	if cache.loginDays < AttendanceRewardData.TOTAL_DAYS then
		cache.loginDays += 1
	end
	saveAttendanceState(userId)
	return true
end

local function getClientAttendanceData(userId: number)
	local cache = playerAttendanceCache[userId] or loadAttendanceState(userId)
	return {
		seasonName = AttendanceRewardData.SEASON_NAME,
		totalDays = AttendanceRewardData.TOTAL_DAYS,
		loginDays = cache.loginDays,
		claimedDay = cache.claimedDay,
	}
end

--- 다음 순번(claimedDay+1) 보상을 수령. loginDays >= 해당 일차여야 함
local function claimAttendanceDay(player: Player): (boolean, string?, any?)
	local userId = player.UserId
	local cache = playerAttendanceCache[userId] or loadAttendanceState(userId)

	local nextDay = cache.claimedDay + 1
	if nextDay > AttendanceRewardData.TOTAL_DAYS then
		return false, "ALL_CLAIMED"
	end

	if cache.loginDays < nextDay then
		return false, "NOT_YET_AVAILABLE"
	end

	local reward = AttendanceRewardData.GetDayReward(nextDay)
	if not reward then
		return false, "NO_REWARD_DATA"
	end

	-- 아이템 보상 지급 (인벤토리 공간 부족 시 실패 처리)
	local grantedItems = {}
	if reward.items then
		for _, entry in ipairs(reward.items) do
			local added, remaining = InventoryService.addItem(userId, entry.itemId, entry.count)
			if added <= 0 or remaining > 0 then
				return false, "INV_FULL"
			end
			table.insert(grantedItems, { itemId = entry.itemId, count = entry.count })
		end
	end

	if reward.gold and reward.gold > 0 then
		local NPCShopService = require(ServerScriptService.Server.Services.NPCShopService)
		NPCShopService.addGold(userId, reward.gold)
	end

	cache.claimedDay = nextDay
	saveAttendanceState(userId)

	if SaveService and SaveService.savePlayer then
		task.spawn(function()
			pcall(function()
				SaveService.savePlayer(userId)
			end)
		end)
	end

	return true, nil, {
		day = nextDay,
		gold = reward.gold or 0,
		items = grantedItems,
	}
end

--========================================
-- RuneStone 월드 오브젝트 (출석 패널을 여는 상호작용 지점)
--========================================

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
		prompt.ActionText = "출석체크"
		prompt.ObjectText = "룬스톤"
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Parent = promptPart

		_attachNpcLabel(promptPart, "RuneStone", "출석체크")

		prompt.Triggered:Connect(function(player)
			if NetController then
				NetController.FireClient(player, "Attendance.Show", getClientAttendanceData(player.UserId))
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

--========================================
-- Handlers
--========================================

local function handleGetData(player: Player)
	return { success = true, data = getClientAttendanceData(player.UserId) }
end

local function handleClaim(player: Player)
	local ok, err, rewardInfo = claimAttendanceDay(player)
	if not ok then
		if err == "ALL_CLAIMED" then
			notify(player, "이번 시즌 출석 보상을 모두 수령했습니다.")
		elseif err == "NOT_YET_AVAILABLE" then
			notify(player, "아직 출석하지 않은 날짜입니다.")
		elseif err == "INV_FULL" then
			notify(player, "인벤토리가 가득 찼습니다.")
		else
			notify(player, "보상 수령에 실패했습니다.")
		end
		return { success = false, errorCode = err }
	end

	-- [주의] NetClient.Request는 응답의 "data" 필드만 언랩해서 반환하므로,
	-- attendance/reward를 전부 이 data 테이블 안에 평평하게 담아 보내야 함
	return {
		success = true,
		data = {
			attendance = getClientAttendanceData(player.UserId),
			reward = rewardInfo,
		},
	}
end

function RuneStoneService.GetHandlers()
	return {
		["Attendance.GetData.Request"] = handleGetData,
		["Attendance.Claim.Request"] = handleClaim,
	}
end

function RuneStoneService.Init(netController)
	if initialized then return end
	initialized = true
	NetController = netController

	-- [중요] 세이브 데이터가 실제로 로드되기 전(PlayerAdded 시점)에는 state가 아직 없을 수 있어서,
	-- 출석 판정/저장은 반드시 SaveService.PlayerSaveLoaded 이후에만 수행한다.
	local function onSaveLoaded(userId: number)
		loadAttendanceState(userId)
		stampAttendanceOnLogin(userId)

		local player = Players:GetPlayerByUserId(userId)
		local data = getClientAttendanceData(userId)
		if player and NetController then
			-- 접속 시 아직 수령 안 한 일차가 있으면(오늘 새로 출석 찍힌 경우 포함) 자동으로 팝업
			if data.claimedDay < data.loginDays then
				NetController.FireClient(player, "Attendance.Show", data)
			end
		end
	end

	-- [버그수정] SaveService.PlayerSaveLoaded 이벤트가 예상대로 잡히지 않는 케이스가 있어서,
	-- 대신 SaveService가 로드 완료 시 세팅해주는 "DataLoaded" 플레이어 속성을 기다리는
	-- 더 확실한 방식으로 대체한다.
	local function waitForDataLoadedThenRun(player: Player)
		if not player:GetAttribute("DataLoaded") then
			local conn
			conn = player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
				if player:GetAttribute("DataLoaded") then
					if conn then conn:Disconnect() end
					onSaveLoaded(player.UserId)
				end
			end)
			-- 이미 속성이 세팅된 채로 연결 타이밍을 놓쳤을 가능성 대비, 짧게 재확인
			task.defer(function()
				if player:GetAttribute("DataLoaded") then
					if conn then conn:Disconnect() end
					onSaveLoaded(player.UserId)
				end
			end)
		else
			onSaveLoaded(player.UserId)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(waitForDataLoadedThenRun, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player then
			playerAttendanceCache[player.UserId] = nil
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(waitForDataLoadedThenRun, player)
	end

	scanForRuneStone()
	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == RUNE_STONE_NAME and (inst:IsA("Model") or inst:IsA("BasePart")) then
			task.defer(bindRuneStoneModel, inst)
		end
	end)

	print("[RuneStoneService] Initialized (Attendance Reward mode)")
end

return RuneStoneService
