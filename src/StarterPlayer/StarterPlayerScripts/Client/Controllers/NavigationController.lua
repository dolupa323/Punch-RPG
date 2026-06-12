-- NavigationController.lua
-- 튜토리얼 퀘스트 가이드용 플레이어 전방 3D 화살표 안내 시스템 (Client Only)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnConfig = require(Shared:WaitForChild("Config"):WaitForChild("SpawnConfig"))
local MobSpawnData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MobSpawnData"))
local HUDUI = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("HUDUI"))

local NavigationController = {}


local initialized = false
local player = Players.LocalPlayer
local activeTargetPos = nil
local activeTargetZone = nil
local activeStepIndex = nil
local targetRadius = 15 -- 이 반경 이내로 들어오면 화살표를 숨김

-- 가이드 모델 및 파트 참조
local guideModel = nil
local arrowShaft = nil
local arrowTipLeft = nil
local arrowTipRight = nil

local function normalizeName(name: string): string
	return string.lower((tostring(name or "")):gsub("[%s_%-%(%)]", ""))
end

local function getInstancePosition(inst: Instance?): Vector3?
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Attachment") and inst.Parent and inst.Parent:IsA("BasePart") then
		return inst.Parent.Position
	end
	if inst:IsA("Model") then
		local ok, pivot = pcall(function() return inst:GetPivot() end)
		if ok and pivot then return pivot.Position end
		local root = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart", true)
		if root and root:IsA("BasePart") then return root.Position end
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
	if #normalizedAliases == 0 then return nil end

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
				if exactContains then
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
	if type(point) ~= "table" then return nil end
	local x = tonumber(point.x or point.X)
	local y = tonumber(point.y or point.Y)
	local z = tonumber(point.z or point.Z)
	if not x or not y or not z then return nil end
	return Vector3.new(x, y, z)
end

local function getSpawnDataCentroid(spawnData)
	if type(spawnData) ~= "table" then return nil end
	if spawnData.exactSpawnPosition then
		local exact = vector3FromTable(spawnData.exactSpawnPosition)
		if exact then return exact end
	end

	local positions = spawnData.spawnPositions
	if type(positions) ~= "table" then return nil end

	local total = Vector3.zero
	local count = 0
	for _, point in ipairs(positions) do
		local pos = vector3FromTable(point)
		if pos then
			total += pos
			count += 1
		end
	end

	if count > 0 then return total / count end
	return nil
end

local function getZoneCenterFromConfig(zoneName: string): Vector3?
	local zoneInfo = SpawnConfig.GetZoneInfo(zoneName)
	if not zoneInfo then return nil end
	if zoneInfo.spawnPoint then
		local spawnPoint = vector3FromTable({
			x = zoneInfo.spawnPoint.X,
			y = zoneInfo.spawnPoint.Y,
			z = zoneInfo.spawnPoint.Z,
		})
		if spawnPoint then return spawnPoint end
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
	if target then return target end

	local zoneTarget = getZoneCenterFromConfig(zoneName)
	if zoneTarget then return zoneTarget end

	return fallbackPos
end

local function raycastWithFilter(origin: Vector3, direction: Vector3, rayParams: RaycastParams): RaycastResult?
	local result = Workspace:Raycast(origin, direction, rayParams)
	if result then
		local hitPart = result.Instance
		local hitModel = hitPart:FindFirstAncestorOfClass("Model")
		if hitModel then
			local nameLower = string.lower(hitModel.Name)
			if hitModel:FindFirstChildOfClass("Humanoid") or 
			   hitModel:FindFirstChild("NPC") or 
			   string.find(nameLower, "npc") or 
			   string.find(nameLower, "master") or 
			   string.find(nameLower, "monster") or 
			   string.find(nameLower, "dummy") or 
			   hitModel:IsA("Accessory") then
				
				local currentFilter = rayParams.FilterDescendantsInstances
				table.insert(currentFilter, hitModel)
				rayParams.FilterDescendantsInstances = currentFilter
				return raycastWithFilter(origin, direction, rayParams)
			end
		end
	end
	return result
end

local function getGroundY(position: Vector3, char: Model?): number
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local filterList = {Workspace:FindFirstChild("__NavigationGuide")}
	if char then table.insert(filterList, char) end
	
	local startVillage = Workspace:FindFirstChild("StartVillage")
	if startVillage then table.insert(filterList, startVillage) end
	
	rayParams.FilterDescendantsInstances = filterList

	local origin = position + Vector3.new(0, 10, 0)
	local direction = Vector3.new(0, -30, 0)
	local result = raycastWithFilter(origin, direction, rayParams)

	local playerY = char and char.PrimaryPart and char.PrimaryPart.Position.Y or position.Y
	if result then
		return result.Position.Y
	end
	return position.Y
end

local function groundProject(position: Vector3, char: Model?): Vector3
	return Vector3.new(position.X, getGroundY(position, char), position.Z)
end

local STEP_TARGETS = {
	SELECT_ELEMENT = {
		kind = "monster",
		zoneName = "SLIME_HABITAT",
		spawnDataKey = "StartingZone_Slime",
		fallback = Vector3.new(-753.46, -32.0, 1404.68),
	},
	KILL_SLIME = {
		kind = "monster",
		zoneName = "SLIME_HABITAT",
		spawnDataKey = "StartingZone_Slime",
		fallback = Vector3.new(-753.46, -32.0, 1404.68),
	},
	COLLECT_SLIME_MUCUS = {
		kind = "monster",
		zoneName = "SLIME_HABITAT",
		spawnDataKey = "StartingZone_Slime",
		fallback = Vector3.new(-753.46, -32.0, 1404.68),
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
		fallback = Vector3.new(-858.37, -92.0, 1679.66),
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
		fallback = Vector3.new(-1519.42, -71.69, 1498.07),
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

	if not target then return nil end

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

local function cleanupVisuals()
	if guideModel then
		guideModel:Destroy()
		guideModel = nil
	end
	arrowShaft = nil
	arrowTipLeft = nil
	arrowTipRight = nil
end

local function setupVisuals()
	cleanupVisuals()

	guideModel = Instance.new("Model")
	guideModel.Name = "__NavigationGuide"
	guideModel.Parent = Workspace

	-- Shaft (몸체)
	arrowShaft = Instance.new("Part")
	arrowShaft.Name = "Shaft"
	arrowShaft.Size = Vector3.new(0.5, 0.1, 1.6)
	arrowShaft.Material = Enum.Material.Neon
	arrowShaft.Color = Color3.fromRGB(0, 220, 255)
	arrowShaft.CanCollide = false
	arrowShaft.CanTouch = false
	arrowShaft.CanQuery = false
	arrowShaft.Anchored = true
	arrowShaft.CastShadow = false
	arrowShaft.Parent = guideModel

	-- Left Wedge for arrowhead
	arrowTipLeft = Instance.new("WedgePart")
	arrowTipLeft.Name = "TipLeft"
	arrowTipLeft.Size = Vector3.new(0.1, 0.5, 1.0)
	arrowTipLeft.Material = Enum.Material.Neon
	arrowTipLeft.Color = Color3.fromRGB(0, 220, 255)
	arrowTipLeft.CanCollide = false
	arrowTipLeft.CanTouch = false
	arrowTipLeft.CanQuery = false
	arrowTipLeft.Anchored = true
	arrowTipLeft.CastShadow = false
	arrowTipLeft.Parent = guideModel

	-- Right Wedge for arrowhead
	arrowTipRight = Instance.new("WedgePart")
	arrowTipRight.Name = "TipRight"
	arrowTipRight.Size = Vector3.new(0.1, 0.5, 1.0)
	arrowTipRight.Material = Enum.Material.Neon
	arrowTipRight.Color = Color3.fromRGB(0, 220, 255)
	arrowTipRight.CanCollide = false
	arrowTipRight.CanTouch = false
	arrowTipRight.CanQuery = false
	arrowTipRight.Anchored = true
	arrowTipRight.CastShadow = false
	arrowTipRight.Parent = guideModel
end

local function updateArrow(dt: number)
	if not activeTargetPos or not guideModel or not arrowShaft or not arrowTipLeft or not arrowTipRight then
		return
	end

	-- 튜토리얼 UI가 최소화된 경우 화살표 가이드 숨김
	if HUDUI.IsTutorialMinimized and HUDUI.IsTutorialMinimized() then
		arrowShaft.Transparency = 1
		arrowTipLeft.Transparency = 1
		arrowTipRight.Transparency = 1
		return
	end

	local char = player.Character

	if not char then
		arrowShaft.Transparency = 1
		arrowTipLeft.Transparency = 1
		arrowTipRight.Transparency = 1
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		arrowShaft.Transparency = 1
		arrowTipLeft.Transparency = 1
		arrowTipRight.Transparency = 1
		return
	end

	local playerPos = hrp.Position

	-- 타겟 사냥 영역(Zone) 내에 들어왔다면 화살표 숨김
	if activeTargetZone then
		local currentZone = SpawnConfig.GetZoneAtPosition(playerPos)
		if currentZone == activeTargetZone then
			arrowShaft.Transparency = 1
			arrowTipLeft.Transparency = 1
			arrowTipRight.Transparency = 1
			return
		end
	end

	local distToGoal = (playerPos - activeTargetPos).Magnitude

	-- 목적지에 다다르면 화살표를 숨김
	if distToGoal < targetRadius then
		arrowShaft.Transparency = 1
		arrowTipLeft.Transparency = 1
		arrowTipRight.Transparency = 1
		return
	else
		arrowShaft.Transparency = 0.25
		arrowTipLeft.Transparency = 0.25
		arrowTipRight.Transparency = 0.25
	end

	-- 플레이어 머리 위 공중 위치 계산
	local arrowCenter = playerPos + Vector3.new(0, 4.2, 0)

	-- 화살표가 위아래로 부드럽게 흔들리는 공중 부유 연출
	local bob = math.sin(os.clock() * 4) * 0.15
	local finalPos = arrowCenter + Vector3.new(0, bob, 0)

	-- 목적지 방향 CFrame 연산 (수평 방향만)
	local lookCF = CFrame.lookAt(finalPos, Vector3.new(activeTargetPos.X, finalPos.Y, activeTargetPos.Z))

	-- 파트 배치 (Shaft는 뒤쪽, Wedge 두 개는 대칭으로 앞쪽에 맞물려 결합하여 완벽한 화살촉 생성)
	arrowShaft.CFrame = lookCF * CFrame.new(0, 0, 0.6)
	arrowTipLeft.CFrame = lookCF * CFrame.new(-0.25, 0, -0.7) * CFrame.Angles(0, 0, math.rad(90))
	arrowTipRight.CFrame = lookCF * CFrame.new(0.25, 0, -0.7) * CFrame.Angles(0, 0, math.rad(-90))
end

-- 튜토리얼 상태 갱신 함수
function NavigationController.UpdateTutorialStatus(status)
	if not status or status.completed or not status.active then
		activeTargetPos = nil
		activeTargetZone = nil
		cleanupVisuals()
		return
	end

	local key = tostring(status.stepKey or "")
	local target = STEP_TARGETS[key]
	if not target and status.stepIndex then
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
		target = STEP_TARGETS[fallbackKeyByIndex[status.stepIndex]]
	end

	if target then
		activeTargetZone = target.zoneName
		activeTargetPos = resolveTargetPosition(status.stepKey, status.stepIndex)
		activeStepIndex = status.stepIndex
		setupVisuals()
	else
		activeTargetPos = nil
		activeTargetZone = nil
		cleanupVisuals()
	end
end

function NavigationController.Init()
	if initialized then return end
	initialized = true
	cleanupVisuals()
	
	RunService.Heartbeat:Connect(function(dt)
		pcall(function()
			updateArrow(dt)
		end)
	end)
	print("[NavigationController] Arrow Guide system initialized.")
end

return NavigationController
