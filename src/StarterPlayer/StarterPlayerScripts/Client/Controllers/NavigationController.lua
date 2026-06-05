-- NavigationController.lua
-- 튜토리얼 퀘스트 가이드용 날파리/위스프 공중 안내 시스템 (Client Only)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local wispCurrentPos = nil
local currentPath = nil
local currentWaypoints = nil
local currentWaypointIndex = 1
local currentPathGoal = nil
local pathRequestToken = 0
local pathRequestPending = false
local pathRequestStartedAt = 0
local pathNextRetryAt = 0
local pathRailFolder = nil
local WISP_FOLLOW_SPEED = 32
local WISP_HOVER_HEIGHT = 4.2
local WISP_REACH_DISTANCE = 1.5
local WISP_IDLE_BOB_AMPLITUDE = 0.25
local WISP_IDLE_BOB_SPEED = 3.0
local PATH_RAIL_THICKNESS = 0.28
local PATH_NODE_SIZE = 0.5

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

local function groundProject(position: Vector3, char: Model?): Vector3
	return Vector3.new(position.X, getGroundY(position, char), position.Z)
end

local function clearPathState()
	currentPath = nil
	currentWaypoints = nil
	currentWaypointIndex = 1
	currentPathGoal = nil
	pathRequestPending = false
	pathRequestStartedAt = 0
	pathNextRetryAt = 0
	if pathRailFolder then
		pathRailFolder:Destroy()
		pathRailFolder = nil
	end
end

local function buildPathRail(waypoints, char: Model?)
	if not guideFolder then
		return
	end

	if pathRailFolder then
		pathRailFolder:Destroy()
		pathRailFolder = nil
	end

	pathRailFolder = Instance.new("Folder")
	pathRailFolder.Name = "GuideRail"
	pathRailFolder.Parent = guideFolder

	local sampledPoints = {}
	for index = 1, #waypoints do
		local waypoint = waypoints[index]
		local waypointPos = waypoint and waypoint.Position
		if waypointPos then
			local projected = groundProject(waypointPos, char) + Vector3.new(0, 0.15, 0)
			sampledPoints[#sampledPoints + 1] = projected
		end
	end

	local expandedPoints = {}
	for index = 1, #sampledPoints do
		local currentPoint = sampledPoints[index]
		expandedPoints[#expandedPoints + 1] = currentPoint

		local nextPoint = sampledPoints[index + 1]
		if nextPoint then
			local delta = nextPoint - currentPoint
			local distance = delta.Magnitude
			local segmentCount = math.max(1, math.ceil(distance / 8))
			for segmentIndex = 1, segmentCount - 1 do
				local alpha = segmentIndex / segmentCount
				local sample = currentPoint:Lerp(nextPoint, alpha)
				sample = groundProject(sample, char) + Vector3.new(0, 0.15, 0)
				expandedPoints[#expandedPoints + 1] = sample
			end
		end
	end

	for index = 1, #expandedPoints do
		local point = expandedPoints[index]
		local node = Instance.new("Part")
		node.Name = ("Node_%02d"):format(index)
		node.Shape = Enum.PartType.Ball
		node.Size = Vector3.new(PATH_NODE_SIZE, PATH_NODE_SIZE, PATH_NODE_SIZE)
		node.Material = Enum.Material.Neon
		node.Color = COLOR_NORMAL
		node.Transparency = 0.18
		node.CanCollide = false
		node.CanQuery = false
		node.CanTouch = false
		node.CastShadow = false
		node.Anchored = true
		node.Parent = pathRailFolder
		node.CFrame = CFrame.new(point)

		local nextPoint = expandedPoints[index + 1]
		if nextPoint then
			local startPos = point
			local endPos = nextPoint
			local delta = endPos - startPos
			local length = delta.Magnitude
			if length > 0.1 then
				local rail = Instance.new("Part")
				rail.Name = ("Rail_%02d"):format(index)
				rail.Shape = Enum.PartType.Block
				rail.Size = Vector3.new(PATH_RAIL_THICKNESS, PATH_RAIL_THICKNESS, length)
				rail.Material = Enum.Material.Neon
				rail.Color = COLOR_NORMAL
				rail.Transparency = 0.35
				rail.CanCollide = false
				rail.CanQuery = false
				rail.CanTouch = false
				rail.CastShadow = false
				rail.Anchored = true
				rail.Parent = pathRailFolder
				rail.CFrame = CFrame.lookAt(startPos:Lerp(endPos, 0.5), endPos)
			end
		end
	end
end

local function buildFallbackWaypoints(startPos: Vector3, goalPos: Vector3, char: Model?)
	local points = {}
	local startFlat = Vector3.new(startPos.X, 0, startPos.Z)
	local goalFlat = Vector3.new(goalPos.X, 0, goalPos.Z)
	local flatDelta = goalFlat - startFlat
	local totalDistance = flatDelta.Magnitude
	local segments = math.clamp(math.floor(totalDistance / 18) + 2, 4, 12)
	local topY = math.max(startPos.Y, goalPos.Y) + 50

	for index = 0, segments do
		local alpha = index / segments
		local xz = startFlat:Lerp(goalFlat, alpha)
		local sampleOrigin = Vector3.new(xz.X, topY, xz.Z)
		local groundY = getGroundY(sampleOrigin, char)
		points[#points + 1] = {
			Position = Vector3.new(xz.X, groundY, xz.Z),
		}
	end

	return points
end

local function requestPathRebuild(startPos: Vector3, goalPos: Vector3, char: Model?)
	if pathRequestPending then
		return
	end
	local now = os.clock()
	if now < pathNextRetryAt then
		return
	end

	pathRequestToken += 1
	local token = pathRequestToken
	local startFlat = groundProject(startPos, char)
	local goalFlat = groundProject(goalPos, char)
	pathRequestPending = true
	pathRequestStartedAt = os.clock()

	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentCanClimb = false,
			WaypointSpacing = 4,
		})

		local ok = pcall(function()
			path:ComputeAsync(startFlat, goalFlat)
		end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			local fallbackWaypoints = buildFallbackWaypoints(startFlat, goalFlat, char)
			currentPath = nil
			currentWaypoints = fallbackWaypoints
			currentWaypointIndex = 1
			currentPathGoal = goalPos
			buildPathRail(fallbackWaypoints, char)
			pathRequestPending = false
			pathRequestStartedAt = 0
			pathNextRetryAt = os.clock() + 0.75
			return
		end
		local waypoints = path:GetWaypoints()
		if not waypoints or #waypoints == 0 then
			local fallbackWaypoints = buildFallbackWaypoints(startFlat, goalFlat, char)
			currentPath = nil
			currentWaypoints = fallbackWaypoints
			currentWaypointIndex = 1
			currentPathGoal = goalPos
			buildPathRail(fallbackWaypoints, char)
			pathRequestPending = false
			pathRequestStartedAt = 0
			pathNextRetryAt = os.clock() + 0.75
			return
		end
		if token ~= pathRequestToken or activeTargetPos ~= goalPos then
			pathRequestPending = false
			pathRequestStartedAt = 0
			return
		end

		currentPath = path
		currentWaypoints = waypoints
		currentWaypointIndex = 1
		currentPathGoal = goalPos
		pathRequestPending = false
		pathRequestStartedAt = 0
		buildPathRail(waypoints, char)
		pathNextRetryAt = 0
	end)
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
		fallback = Vector3.new(-309.554, 10, 425.738),
	},
	COLLECT_SLIME_MUCUS = {
		kind = "monster",
		zoneName = "SLIME_HABITAT",
		spawnDataKey = "StartingZone_Slime",
		fallback = Vector3.new(-309.554, 10, 425.738),
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
		fallback = Vector3.new(-4.65, 8, 466.528),
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
		zoneName = "STUMP_ZONE",
		spawnDataKey = "StumpZone",
		fallback = Vector3.new(240.8065, 70.2, 642.298),
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
	clearPathState()
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
		clearPathState()
		setupVisuals()
	end
end

function NavigationController.Init()
	if initialized then return end
	initialized = true

	player.CharacterAdded:Connect(function()
		if activeTargetPos then
			wispCurrentPos = nil
			clearPathState()
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
		if typeof(activeTargetPos) ~= "Vector3" then
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
		if not wispCurrentPos then
			local startDirection = guideGoal - playerPos
			if startDirection.Magnitude < 0.1 then
				startDirection = hrp.CFrame.LookVector
			end
			startDirection = Vector3.new(startDirection.X, 0, startDirection.Z)
			if startDirection.Magnitude < 0.1 then
				startDirection = Vector3.new(0, 0, -1)
			end
			local playerGroundY = getGroundY(playerPos, char)
			wispCurrentPos = Vector3.new(playerPos.X, playerGroundY + WISP_HOVER_HEIGHT, playerPos.Z) + startDirection.Unit * 5
		end

		if not currentWaypoints or currentPathGoal ~= guideGoal then
			requestPathRebuild(playerPos, guideGoal, char)
		end

		if pathRequestPending and (not currentWaypoints) and pathRequestStartedAt > 0 and (os.clock() - pathRequestStartedAt) > 0.6 then
			local fallbackWaypoints = buildFallbackWaypoints(playerPos, guideGoal, char)
			currentPath = nil
			currentWaypoints = fallbackWaypoints
			currentWaypointIndex = 1
			currentPathGoal = guideGoal
			pathRequestPending = false
			pathRequestStartedAt = 0
			pathNextRetryAt = os.clock() + 0.75
			buildPathRail(fallbackWaypoints, char)
		end

		local finalPos = wispCurrentPos
		local facingDir = guideGoal - wispCurrentPos
		local targetColor = COLOR_NORMAL
		local currentTransparency = 0.05

		if currentWaypoints then
			local waypoint = currentWaypoints[currentWaypointIndex] or currentWaypoints[#currentWaypoints]
			local pathTarget = waypoint and (groundProject(waypoint.Position, char) + Vector3.new(0, WISP_HOVER_HEIGHT, 0)) or guideGoal
			local toTarget = pathTarget - wispCurrentPos
			local targetDistance = toTarget.Magnitude
			local moveStep = math.max(WISP_FOLLOW_SPEED * dt, 0)
			local isLastWaypoint = currentWaypointIndex >= #currentWaypoints
			facingDir = toTarget
			if facingDir.Magnitude < 0.1 then
				facingDir = (guideGoal - wispCurrentPos)
			end

			if targetDistance <= WISP_REACH_DISTANCE then
				if not isLastWaypoint then
					currentWaypointIndex += 1
				else
					local bob = math.sin(os.clock() * WISP_IDLE_BOB_SPEED) * WISP_IDLE_BOB_AMPLITUDE
					wispCurrentPos = pathTarget + Vector3.new(0, bob, 0)
					finalPos = wispCurrentPos
				end
			else
				local step = math.min(moveStep, targetDistance)
				wispCurrentPos = wispCurrentPos + toTarget.Unit * step
				finalPos = wispCurrentPos
			end
		else
			local idleY = getGroundY(wispCurrentPos, char) + WISP_HOVER_HEIGHT
			local bob = math.sin(os.clock() * WISP_IDLE_BOB_SPEED) * WISP_IDLE_BOB_AMPLITUDE
			finalPos = Vector3.new(wispCurrentPos.X, idleY + bob, wispCurrentPos.Z)
			wispCurrentPos = finalPos
			targetColor = COLOR_WARNING
		end

		wispPart.Size = Vector3.new(1.2, 1.2, 1.2)
		wispPart.Transparency = currentTransparency
		wispLight.Brightness = 5
		wispTrail.Lifetime = 0.65

		-- 색상 보간 적용
		wispPart.Color = wispPart.Color:Lerp(targetColor, math.clamp(dt * 8, 0, 1))
		wispLight.Color = wispPart.Color
		wispTrail.Color = ColorSequence.new(wispPart.Color)

		wispPart.CFrame = CFrame.lookAt(finalPos, finalPos + facingDir.Unit)
	end)

	print("[NavigationController] Pioneer Waypoint Wisp Guide Initialized")
end

return NavigationController
