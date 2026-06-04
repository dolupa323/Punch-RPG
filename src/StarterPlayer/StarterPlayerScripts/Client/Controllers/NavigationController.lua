-- NavigationController.lua
-- 튜토리얼 퀘스트 가이드용 날파리/위스프 공중 안내 시스템 (Client Only)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnConfig = require(Shared:WaitForChild("Config"):WaitForChild("SpawnConfig"))
local MobSpawnData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MobSpawnData"))

local NavigationController = {}

local initialized = false
local player = Players.LocalPlayer
local activeTargetPos = nil
local activeStepIndex = nil
local isDone = false

-- 가이드 파트 참조
local guideFolder = nil
local wispPart = nil
local wispLight = nil
local wispTrail = nil

-- 지능형 노드(체크포인트) 제어 변수
local wispCurrentPos = nil
local pathWaypoints = nil
local pathWaypointIndex = 1
local pathGoalPos = nil
local nextPathRebuildAt = 0
local MAX_PATH_REBUILD_INTERVAL = 1.25
local WISP_FOLLOW_SPEED = 18
local WISP_HOVER_HEIGHT = 4.2
local WISP_REACH_DISTANCE = 2.5

-- 디자인 색상 상수
local COLOR_NORMAL = Color3.fromRGB(0, 220, 255)  -- 정상 안내 시: 네온 싸이언
local COLOR_WARNING = Color3.fromRGB(255, 120, 0) -- 경로 이탈 시: 네온 오렌지/앰버

local function normalizeName(name: string): string
	return string.lower((tostring(name or "")):gsub("[%s_%-%(%)]", ""))
end

local function getInstancePosition(inst: Instance?): Vector3?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Attachment") and inst.Parent and inst.Parent:IsA("BasePart") then
		return inst.Parent.Position
	end
	if inst:IsA("Model") then
		local ok, pivot = pcall(function()
			return inst:GetPivot()
		end)
		if ok and pivot then
			return pivot.Position
		end
		local root = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart", true)
		if root and root:IsA("BasePart") then
			return root.Position
		end
	end
	return nil
end

local function findWorkspaceTargetPosition(aliases: {string}): Vector3?
	local normalizedAliases = {}
	for _, alias in ipairs(aliases or {}) do
		local normalized = normalizeName(alias)
		if normalized ~= "" then
			table.insert(normalizedAliases, normalized)
		end
	end
	if #normalizedAliases == 0 then
		return nil
	end

	local bestMatch: Instance? = nil
	local bestScore = math.huge

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			local normalized = normalizeName(inst.Name)
			for _, alias in ipairs(normalizedAliases) do
				if normalized == alias then
					return getInstancePosition(inst)
				end
				local exactContains = string.find(normalized, alias, 1, true)
				local aliasContains = string.find(alias, normalized, 1, true)
				if exactContains or aliasContains then
					local score = math.abs(#normalized - #alias)
					if score < bestScore then
						bestMatch = inst
						bestScore = score
					end
				end
			end
		end
	end

	return getInstancePosition(bestMatch)
end

local function vector3FromTable(point)
	if type(point) ~= "table" then
		return nil
	end
	local x = tonumber(point.x or point.X)
	local y = tonumber(point.y or point.Y)
	local z = tonumber(point.z or point.Z)
	if not x or not y or not z then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function getSpawnDataCentroid(spawnData)
	if type(spawnData) ~= "table" then
		return nil
	end

	if spawnData.exactSpawnPosition then
		local exact = vector3FromTable(spawnData.exactSpawnPosition)
		if exact then
			return exact
		end
	end

	local positions = spawnData.spawnPositions
	if type(positions) ~= "table" then
		return nil
	end

	local total = Vector3.zero
	local count = 0
	for _, point in ipairs(positions) do
		local pos = vector3FromTable(point)
		if pos then
			total += pos
			count += 1
		end
	end

	if count > 0 then
		return total / count
	end

	return nil
end

local function getZoneCenterFromConfig(zoneName: string): Vector3?
	local zoneInfo = SpawnConfig.GetZoneInfo(zoneName)
	if not zoneInfo then
		return nil
	end
	if zoneInfo.spawnPoint then
		local spawnPoint = vector3FromTable({
			x = zoneInfo.spawnPoint.X,
			y = zoneInfo.spawnPoint.Y,
			z = zoneInfo.spawnPoint.Z,
		})
		if spawnPoint then
			return spawnPoint
		end
	end
	if zoneInfo.min and zoneInfo.max then
		return Vector3.new(
			(zoneInfo.min.X + zoneInfo.max.X) * 0.5,
			(zoneInfo.spawnPoint and zoneInfo.spawnPoint.Y) or 0,
			(zoneInfo.min.Y + zoneInfo.max.Y) * 0.5
		)
	end
	return nil
end

local function resolveMonsterGuidePosition(zoneName: string, spawnDataKey: string?, fallbackPos: Vector3?)
	local spawnData = spawnDataKey and MobSpawnData[spawnDataKey] or nil
	local target = getSpawnDataCentroid(spawnData)
	if target then
		return target
	end

	local zoneTarget = getZoneCenterFromConfig(zoneName)
	if zoneTarget then
		return zoneTarget
	end

	return fallbackPos
end

local STEP_TARGETS = {
	SELECT_ELEMENT = {
		kind = "npc",
		aliases = { "DarkMaster", "어둠 스승", "Dark Master" },
		fallback = Vector3.new(-588.057, 37.151, 961.323),
	},
	KILL_SLIME = {
		kind = "monster",
		zoneName = "SLIME_HABITAT",
		spawnDataKey = "StartingZone_Slime",
		fallback = Vector3.new(-341.2, 16.3, 423.2),
	},
	COLLECT_SLIME_MUCUS = {
		kind = "monster",
		zoneName = "SLIME_HABITAT",
		spawnDataKey = "StartingZone_Slime",
		fallback = Vector3.new(-341.2, 16.3, 423.2),
	},
	CRAFT_SOFTCLUB = {
		kind = "npc",
		aliases = { "WeaponCrafter", "무기제작", "무기 장인", "Weapon Crafter" },
		fallback = Vector3.new(-662.486, 32.939, 791.484),
	},
	KILL_HORNED_LARVA = {
		kind = "monster",
		zoneName = "HornedLarvaZone",
		spawnDataKey = "HornedLarvaZone",
		fallback = Vector3.new(-222.64, -3.258, 195.686),
	},
	CRAFT_GAKCHANG = {
		kind = "npc",
		aliases = { "WeaponCrafter", "무기제작", "무기 장인", "Weapon Crafter" },
		fallback = Vector3.new(-662.486, 32.939, 791.484),
	},
	ENHANCE_GAKCHANG = {
		kind = "npc",
		aliases = { "EnhanceMaster", "강화스승", "무기 강화", "Weapon Enhance" },
		fallback = Vector3.new(-677.292, 35.511, 822.341),
	},
	BUY_POTION = {
		kind = "npc",
		aliases = { "Merchant", "잡화상", "General Merchant" },
		fallback = Vector3.new(-419.315, 32.774, 936.809),
	},
	KILL_STUMP = {
		kind = "monster",
		zoneName = "StumpZone",
		spawnDataKey = "StumpZone",
		fallback = Vector3.new(-235.1, -2.2, -6.7),
	},
	CRAFT_MOGWOLDO = {
		kind = "npc",
		aliases = { "WeaponCrafter", "무기제작", "무기 장인", "Weapon Crafter" },
		fallback = Vector3.new(-662.486, 32.939, 791.484),
	},
}

local function resolveTargetPosition(stepKey: string?, stepIndex: number?): Vector3?
	local key = tostring(stepKey or "")
	local target = STEP_TARGETS[key]

	if not target and stepIndex then
		local fallbackKeyByIndex = {
			[1] = "SELECT_ELEMENT",
			[2] = "KILL_SLIME",
			[3] = "COLLECT_SLIME_MUCUS",
			[4] = "CRAFT_SOFTCLUB",
			[5] = "KILL_HORNED_LARVA",
			[6] = "CRAFT_GAKCHANG",
			[7] = "ENHANCE_GAKCHANG",
			[8] = "BUY_POTION",
			[9] = "KILL_STUMP",
			[10] = "CRAFT_MOGWOLDO",
		}
		target = STEP_TARGETS[fallbackKeyByIndex[stepIndex]]
	end

	if not target then
		return nil
	end

	if target.kind == "npc" then
		local livePos = findWorkspaceTargetPosition(target.aliases or {})
		return livePos or target.fallback
	end

	if target.kind == "monster" then
		local livePos = findWorkspaceTargetPosition({
			target.zoneName or "",
			target.spawnDataKey or "",
		})
		return livePos or resolveMonsterGuidePosition(target.zoneName or "", target.spawnDataKey, target.fallback)
	end

	return target.fallback
end

-- 비주얼 가이드 오브젝트 파괴
local function cleanupVisuals()
	if guideFolder then
		guideFolder:Destroy()
		guideFolder = nil
	end
	wispPart = nil
	wispLight = nil
	wispTrail = nil
	wispCurrentPos = nil
	pathWaypoints = nil
	pathWaypointIndex = 1
	pathGoalPos = nil
	nextPathRebuildAt = 0
end

-- 비주얼 가이드 오브젝트 생성
local function setupVisuals()
	cleanupVisuals()

	guideFolder = Instance.new("Folder")
	guideFolder.Name = "__NavigationGuide"
	guideFolder.Parent = Workspace

	wispPart = Instance.new("Part")
	wispPart.Name = "GuideWisp"
	wispPart.Shape = Enum.PartType.Ball
	wispPart.Size = Vector3.new(0.5, 0.5, 0.5)
	wispPart.Material = Enum.Material.Neon
	wispPart.Color = COLOR_NORMAL
	wispPart.Transparency = 0.2
	wispPart.CanCollide = false
	wispPart.CanQuery = false
	wispPart.CanTouch = false
	wispPart.CastShadow = false
	wispPart.Anchored = true
	wispPart.Parent = guideFolder

	wispLight = Instance.new("PointLight")
	wispLight.Color = wispPart.Color
	wispLight.Range = 8
	wispLight.Brightness = 2.5
	wispLight.Parent = wispPart

	local att0 = Instance.new("Attachment")
	att0.Name = "Att0"
	att0.Position = Vector3.new(0, -0.2, 0)
	att0.Parent = wispPart

	local att1 = Instance.new("Attachment")
	att1.Name = "Att1"
	att1.Position = Vector3.new(0, 0.2, 0)
	att1.Parent = wispPart

	wispTrail = Instance.new("Trail")
	wispTrail.Attachment0 = att0
	wispTrail.Attachment1 = att1
	wispTrail.Color = ColorSequence.new(wispPart.Color)
	wispTrail.Lifetime = 0.4
	wispTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	wispTrail.LightEmission = 1
	wispTrail.FaceCamera = true
	wispTrail.Parent = wispPart
end

-- 지면 높이를 구하는 함수
local function getGroundY(position: Vector3, char: Model?): number
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {Workspace:FindFirstChild("__NavigationGuide")}
	if char then
		table.insert(filterList, char)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local origin = position + Vector3.new(0, 15, 0)
	local direction = Vector3.new(0, -30, 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)

	if result then
		return result.Position.Y
	end
	return position.Y
end

local function getRaycastParams(char: Model?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {Workspace:FindFirstChild("__NavigationGuide")}
	if char then
		table.insert(filterList, char)
	end
	params.FilterDescendantsInstances = filterList
	return params
end

local function clampToClearPath(fromPos: Vector3, desiredPos: Vector3, char: Model?): Vector3
	local params = getRaycastParams(char)
	local delta = desiredPos - fromPos
	local dist = delta.Magnitude
	if dist <= 0.001 then
		return desiredPos
	end

	local result = Workspace:Raycast(fromPos, delta, params)
	if not result then
		return desiredPos
	end

	local backOff = math.max(0.75, math.min(2.5, dist * 0.15))
	return result.Position - delta.Unit * backOff + Vector3.new(0, 0.75, 0)
end

local function rebuildPath(fromPos: Vector3, goalPos: Vector3, char: Model?)
	local safeFrom = fromPos + Vector3.new(0, 1.5, 0)
	local safeGoal = goalPos + Vector3.new(0, 1.5, 0)

	local path = PathfindingService:CreatePath({
		AgentRadius = 1.0,
		AgentHeight = 3.5,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	})

	local ok = pcall(function()
		path:ComputeAsync(safeFrom, safeGoal)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		pathWaypoints = nil
		pathWaypointIndex = 1
		return false
	end

	local waypoints = path:GetWaypoints()
	if type(waypoints) ~= "table" or #waypoints == 0 then
		pathWaypoints = nil
		pathWaypointIndex = 1
		return false
	end

	pathWaypoints = waypoints
	pathWaypointIndex = 1
	if #waypoints > 1 then
		pathWaypointIndex = 2
	end
	return true
end

-- 튜토리얼 상태 갱신 함수
function NavigationController.UpdateTutorialStatus(status)
	if type(status) ~= "table" then
		activeTargetPos = nil
		cleanupVisuals()
		return
	end

	isDone = status.progress and status.progress.done == true
	if not status.active or status.completed or isDone then
		activeTargetPos = nil
		cleanupVisuals()
		return
	end

	local stepIndex = tonumber(status.stepIndex)
	local stepKey = tostring(status.stepKey or "")
	local targetPos = resolveTargetPosition(stepKey, stepIndex)
	if not targetPos then
		activeTargetPos = nil
		cleanupVisuals()
		return
	end

	if activeTargetPos ~= targetPos then
		activeTargetPos = targetPos
		activeStepIndex = stepIndex
		wispCurrentPos = nil
		pathWaypoints = nil
		pathWaypointIndex = 1
		pathGoalPos = nil
		nextPathRebuildAt = 0
		setupVisuals()
	end
end

function NavigationController.Init()
	if initialized then return end
	initialized = true

	player.CharacterAdded:Connect(function()
		if activeTargetPos then
			wispCurrentPos = nil
			pathWaypoints = nil
			pathWaypointIndex = 1
			pathGoalPos = nil
			nextPathRebuildAt = 0
			setupVisuals()
		else
			cleanupVisuals()
		end
	end)

	-- 매 프레임 업데이트 루프
	RunService.RenderStepped:Connect(function(dt)
		if not activeTargetPos or not wispPart or not wispLight or not wispTrail then
			return
		end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not char or not hrp or not hum or hum.Health <= 0 then
			wispPart.Transparency = 1
			wispLight.Brightness = 0
			return
		end

		local playerPos = hrp.Position
		local guideGoal = activeTargetPos
		local now = os.clock()

		if not wispCurrentPos then
			local spawnOffset = hrp.CFrame.LookVector * 4
			wispCurrentPos = playerPos + spawnOffset + Vector3.new(0, WISP_HOVER_HEIGHT, 0)
		end

		if pathGoalPos ~= guideGoal then
			pathGoalPos = guideGoal
			pathWaypoints = nil
			pathWaypointIndex = 1
			nextPathRebuildAt = 0
		end

		if now >= nextPathRebuildAt or not pathWaypoints or pathWaypointIndex > #pathWaypoints then
			rebuildPath(wispCurrentPos, guideGoal, char)
			nextPathRebuildAt = now + MAX_PATH_REBUILD_INTERVAL
		end

		local targetPos = guideGoal
		if pathWaypoints and pathWaypointIndex <= #pathWaypoints then
			local waypoint = pathWaypoints[pathWaypointIndex]
			if waypoint then
				targetPos = waypoint.Position
			end
		end

		local toTarget = targetPos - wispCurrentPos
		local distToTarget = toTarget.Magnitude
		if distToTarget <= WISP_REACH_DISTANCE then
			if pathWaypoints and pathWaypointIndex < #pathWaypoints then
				pathWaypointIndex += 1
			end
		else
			local step = math.min(distToTarget, WISP_FOLLOW_SPEED * dt)
			local nextPos = wispCurrentPos + toTarget.Unit * step
			wispCurrentPos = clampToClearPath(wispCurrentPos, nextPos, char)
		end

		local groundY = getGroundY(wispCurrentPos, char)
		local finalPos = Vector3.new(wispCurrentPos.X, groundY + WISP_HOVER_HEIGHT, wispCurrentPos.Z)
		local timeVal = os.clock()

		local targetColor = COLOR_NORMAL
		local baseBrightness = 2.5
		local currentTransparency = 0.2
		local distToGoal = (activeTargetPos - playerPos).Magnitude

		wispPart.Size = Vector3.new(0.5, 0.5, 0.5)
		wispPart.Transparency = currentTransparency
		wispLight.Brightness = baseBrightness
		wispTrail.Lifetime = 0.40

		if distToGoal < 15 then
			local fade = math.clamp(distToGoal / 15, 0, 1)
			wispPart.Transparency = 1.0 - ((1.0 - currentTransparency) * fade)
			wispLight.Brightness = baseBrightness * fade
			wispTrail.Lifetime = 0.40 * fade
		end

		-- 색상 보간 적용
		wispPart.Color = wispPart.Color:Lerp(targetColor, math.clamp(dt * 8, 0, 1))
		wispLight.Color = wispPart.Color
		wispTrail.Color = ColorSequence.new(wispPart.Color)

		wispPart.CFrame = CFrame.new(finalPos)
	end)

	print("[NavigationController] Pioneer Waypoint Wisp Guide Initialized")
end

return NavigationController
