-- FountainService.lua
-- 분수대 물 터치 → 페이드아웃 → 지하 텔레포트 → 페이드인 (하늘섬 동일 방식)
-- UndergroundExit 터치 → 마을 복귀 (기존 동일)

local FountainService = {}

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

local NetController = nil
local initialized   = false

-- 지하 도착 좌표 (SpawnConfig UNDERGROUND spawnPoint 기준)
local UNDERGROUND_DEST = Vector3.new(-67, 118, 251)

-- 스트리밍 사전 로드 위치
local UNDERGROUND_STREAM_POSITIONS = {
	Vector3.new(-67,  85, 251),   -- 지하도시 중심
	Vector3.new(430,  95, 230),   -- 협곡 중심
	Vector3.new(243, 100, 255),   -- 협곡 서쪽
	Vector3.new(650, 100, 198),   -- 협곡 동쪽
}

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
	end)
	if ok and pos then return pos end
	return VILLAGE_FALLBACK
end

local TELEPORT_COOLDOWN = 4.0
local debounces = {}

local function canTeleport(userId)
	local now = os.clock()
	if debounces[userId] and now - debounces[userId] < TELEPORT_COOLDOWN then return false end
	debounces[userId] = now
	return true
end

local function findPart(name)
	local function scan(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name == name and child:IsA("BasePart") then return child end
			local found = scan(child)
			if found then return found end
		end
	end
	return scan(Workspace)
end

-- 실제 텔레포트 처리 (하늘섬 패턴 동일)
-- preFadeDelay: 페이드아웃 시작 전 대기 시간 (낙하 연출용)
local function doTeleport(player, targetPos, zone, destLabel, preFadeDelay)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then return end

	task.defer(function()
		-- 낙하 연출: 잠깐 자유낙하 후 페이드아웃
		if preFadeDelay and preFadeDelay > 0 then
			task.wait(preFadeDelay)
		end

		-- 캐릭터 재확인 (낙하 중 사망 등 방지)
		local c0 = player.Character
		if not c0 or not c0:FindFirstChild("HumanoidRootPart") then return end

		-- 1. 클라이언트에 페이드아웃 + 로딩화면 요청
		if NetController then
			NetController.FireClient(player, "Portal.Teleporting", { destination = destLabel })
		end

		task.wait(1.5) -- 페이드아웃 완료 대기

		local c2  = player.Character
		local h2  = c2 and c2:FindFirstChild("HumanoidRootPart")
		if not c2 or not h2 then return end

		h2.Anchored = true
		c2:PivotTo(CFrame.new(targetPos))

		-- 스트리밍 로드 (도착 위치 + 협곡 전체)
		task.spawn(function()
			for _, pos in ipairs(UNDERGROUND_STREAM_POSITIONS) do
				pcall(function() player:RequestStreamAroundAsync(pos, 8) end)
			end
		end)

		task.wait(0.5)
		h2.Anchored = false

		-- 무적 ForceField 5초
		task.spawn(function()
			local ff = Instance.new("ForceField")
			ff.Visible = false
			ff.Parent  = c2
			task.delay(5, function() if ff and ff.Parent then ff:Destroy() end end)
		end)

		-- 스폰 좌표 갱신 (사망 시 복귀)
		player:SetAttribute("SpawnPosX", targetPos.X)
		player:SetAttribute("SpawnPosY", targetPos.Y)
		player:SetAttribute("SpawnPosZ", targetPos.Z)

		-- 2. 클라이언트에 페이드인 요청
		if NetController then
			NetController.FireClient(player, "Portal.Arrived", { zone = zone })
		end

		print(string.format("[FountainService] %s → %s (%.0f,%.0f,%.0f)",
			player.Name, destLabel, targetPos.X, targetPos.Y, targetPos.Z))
	end)
end

-- 분수대 물 터치 → 지하 이동
local function setupFountainWater()
	task.spawn(function()
		task.wait(2)
		local waterPart = findPart("FountainWater")
		if not waterPart then
			warn("[FountainService] 'FountainWater' 파트 없음")
			return
		end
		waterPart.CanCollide = false
		waterPart.CanTouch   = true
		print("[FountainService] FountainWater CanCollide=false 처리 완료:", waterPart:GetFullName())

		waterPart.Touched:Connect(function(hit)
			local char = hit.Parent
			if not char then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end
			local player = Players:GetPlayerFromCharacter(char)
			if not player then return end
			if not canTeleport(player.UserId) then return end

			-- 구멍 아래로 충분히 낙하한 뒤 페이드아웃 시작
			local fallTriggerY = waterPart.Position.Y - 20
			task.spawn(function()
				local deadline = os.clock() + 5
				while os.clock() < deadline do
					local c = player.Character
					local h = c and c:FindFirstChild("HumanoidRootPart")
					if not h then break end
					if h.Position.Y < fallTriggerY then
						doTeleport(player, UNDERGROUND_DEST, "UNDERGROUND", "클레이온", 0)
						break
					end
					task.wait(0.05)
				end
			end)
		end)
	end)
end

-- FountainEntrance 파트도 동일 처리 (백업 트리거)
local function setupFountainEntrance()
	task.spawn(function()
		task.wait(2)
		local entrance = workspace:FindFirstChild("FountainEntrance")
		if not entrance or not entrance:IsA("BasePart") then return end
		entrance.CanCollide = false
		entrance.CanTouch   = true

		entrance.Touched:Connect(function(hit)
			local char = hit.Parent
			if not char then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end
			local player = Players:GetPlayerFromCharacter(char)
			if not player then return end
			if not canTeleport(player.UserId) then return end

			local fallTriggerY = entrance.Position.Y - 20
			task.spawn(function()
				local deadline = os.clock() + 5
				while os.clock() < deadline do
					local c = player.Character
					local h = c and c:FindFirstChild("HumanoidRootPart")
					if not h then break end
					if h.Position.Y < fallTriggerY then
						doTeleport(player, UNDERGROUND_DEST, "UNDERGROUND", "클레이온", 0)
						break
					end
					task.wait(0.05)
				end
			end)
		end)
		print("[FountainService] FountainEntrance 트리거 등록")
	end)
end

-- 지하 탈출 트리거 → 마을 복귀
local function setupUndergroundExit()
	task.spawn(function()
		task.wait(2)
		local exitPart = findPart("UndergroundExit")
		if not exitPart then
			print("[FountainService] 'UndergroundExit' 파트 없음")
			return
		end
		exitPart.CanCollide = false
		exitPart.CanTouch   = true
		print("[FountainService] UndergroundExit 감지:", exitPart:GetFullName())

		exitPart.Touched:Connect(function(hit)
			local char = hit.Parent
			if not char then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end
			local player = Players:GetPlayerFromCharacter(char)
			if not player then return end
			if not canTeleport(player.UserId) then return end

			if NetController then
				NetController.FireClient(player, "Fountain.Return", {})
			end
		end)
	end)
end

-- 클라이언트 복귀 요청 핸들러 (페이드아웃 → 로딩 → 텔레포트 → 페이드인)
local VILLAGE_STREAM_POSITIONS = {
	Vector3.new(-35.721, 233, 253.348),
}

local function handleReturnRequest(player, _payload)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then return { success = false } end

	local targetPos = getVillagePos()

	-- 1. 페이드아웃 + 로딩화면
	if NetController then
		NetController.FireClient(player, "Portal.Teleporting", { destination = "아르하임" })
	end

	task.defer(function()
		task.wait(1.5)

		local c2 = player.Character
		local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
		if not c2 or not h2 then return end

		h2.Anchored = true
		c2:PivotTo(CFrame.new(targetPos))

		task.spawn(function()
			pcall(function() player:RequestStreamAroundAsync(targetPos, 8) end)
		end)

		task.wait(0.5)
		h2.Anchored = false

		-- 2. 페이드인
		if NetController then
			NetController.FireClient(player, "Portal.Arrived", { zone = "VILLAGE" })
		end
	end)

	return { success = true }
end

function FountainService.GetHandlers()
	return {
		["Fountain.Return.Request"] = handleReturnRequest,
	}
end

function FountainService.Init(netController)
	if initialized then return end
	initialized = true

	NetController = netController

	setupFountainWater()
	setupFountainEntrance()
	setupUndergroundExit()

	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId] = nil
	end)

	print("[FountainService] Initialized.")
end

return FountainService
