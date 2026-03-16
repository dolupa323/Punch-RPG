-- BuildController.lua
-- 클라이언트 건설 컨트롤러
-- 서버 Build 이벤트 수신 및 로컬 캐시 관리 + 건축 배치(Ghost) 로직

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local NetClient = require(script.Parent.Parent.NetClient)
local InputManager = require(script.Parent.Parent.InputManager)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

local BuildController = {}

--========================================
-- Private State
--========================================
local player = Players.LocalPlayer
local initialized = false

-- 로컬 구조물 캐시 [structureId] = { id, facilityId, position, rotation, health, ownerId }
local structuresCache = {}
local structureCount = 0

-- Placement Mode State
local isPlacing = false
local currentFacilityId = nil
local currentGhost = nil
local currentRotation = 0 -- Degree
local heartbeatConn = nil

-- World Durability Bar (look-at structure)
local lookConn = nil
local durabilityBillboard = nil
local durabilityFill = nil
local durabilityLabel = nil
local durabilityTitle = nil
local focusedStructureId = nil
local lookRayAccumulator = 0

--========================================
-- Helpers
--========================================

local function createGhost(facilityId)
	local facilityData = DataHelper.GetData("FacilityData", facilityId)
	if not facilityData then return nil end

	-- ReplicatedStorage/Assets/FacilityModels 에서 모델 복사 시도
	local models = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FacilityModels")
	local sourceModel = models and models:FindFirstChild(facilityData.modelName)
	
	local ghost
	if sourceModel then
		ghost = sourceModel:Clone()
		if not ghost.PrimaryPart then
			ghost.PrimaryPart = ghost:FindFirstChildWhichIsA("BasePart", true)
		end
	else
		-- 모델이 없으면 임시 박스 생성
		ghost = Instance.new("Model")
		local part = Instance.new("Part")
		part.Size = Vector3.new(4, 4, 4)
		part.Color = Color3.fromRGB(0, 255, 0)
		part.Parent = ghost
		ghost.PrimaryPart = part
	end

	-- Ghost 효과 (반투명 녹색)
	for _, p in ipairs(ghost:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 0.5
			p.Color = Color3.fromRGB(100, 255, 100)
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		elseif p:IsA("Script") or p:IsA("LocalScript") then
			p:Destroy()
		end
	end
	
	ghost.Name = "BUILD_GHOST"
	ghost.Parent = workspace
	return ghost
end

local function getStructureModel(structureId: string)
	local facilitiesFolder = workspace:FindFirstChild("Facilities")
	if not facilitiesFolder then return nil end
	return facilitiesFolder:FindFirstChild(structureId)
end

local function getAdorneeFromModel(model: Instance)
	if not model then return nil end
	if model:IsA("Model") then
		return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	elseif model:IsA("BasePart") then
		return model
	end
	return nil
end

local function ensureDurabilityBillboard()
	if durabilityBillboard then return end

	durabilityBillboard = Instance.new("BillboardGui")
	durabilityBillboard.Name = "StructureDurabilityBar"
	durabilityBillboard.Size = UDim2.new(0, 140, 0, 34)
	durabilityBillboard.StudsOffsetWorldSpace = Vector3.new(0, 3.8, 0)
	durabilityBillboard.AlwaysOnTop = true
	durabilityBillboard.MaxDistance = 70
	durabilityBillboard.Enabled = false
	durabilityBillboard.Parent = player:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.45
	bg.BorderSizePixel = 0
	bg.Parent = durabilityBillboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	durabilityTitle = Instance.new("TextLabel")
	durabilityTitle.Name = "Title"
	durabilityTitle.Size = UDim2.new(1, -8, 0, 14)
	durabilityTitle.Position = UDim2.new(0, 4, 0, 1)
	durabilityTitle.BackgroundTransparency = 1
	durabilityTitle.Font = Enum.Font.GothamBold
	durabilityTitle.TextSize = 10
	durabilityTitle.TextColor3 = Color3.fromRGB(255, 235, 170)
	durabilityTitle.TextStrokeTransparency = 0.7
	durabilityTitle.TextXAlignment = Enum.TextXAlignment.Center
	durabilityTitle.Text = UILocalizer.Localize("시설")
	durabilityTitle.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBG"
	barBg.Size = UDim2.new(1, -10, 0, 10)
	barBg.Position = UDim2.new(0, 5, 1, -14)
	barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = barBg

	durabilityFill = Instance.new("Frame")
	durabilityFill.Name = "Fill"
	durabilityFill.Size = UDim2.new(1, 0, 1, 0)
	durabilityFill.BackgroundColor3 = Color3.fromRGB(95, 200, 120)
	durabilityFill.BorderSizePixel = 0
	durabilityFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = durabilityFill

	durabilityLabel = Instance.new("TextLabel")
	durabilityLabel.Name = "Percent"
	durabilityLabel.Size = UDim2.new(1, 0, 1, 0)
	durabilityLabel.BackgroundTransparency = 1
	durabilityLabel.Font = Enum.Font.GothamSemibold
	durabilityLabel.TextSize = 9
	durabilityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	durabilityLabel.Text = "100%"
	durabilityLabel.Parent = barBg
end

local function hideWorldDurabilityBar()
	focusedStructureId = nil
	if durabilityBillboard then
		durabilityBillboard.Enabled = false
		durabilityBillboard.Adornee = nil
	end
end

local function updateWorldDurabilityBar(structureId: string)
	local struct = structuresCache[structureId]
	if not struct then
		hideWorldDurabilityBar()
		return
	end

	local facilityData = DataHelper.GetData("FacilityData", struct.facilityId)
	if not facilityData or not facilityData.maxHealth or facilityData.maxHealth <= 0 then
		hideWorldDurabilityBar()
		return
	end

	local model = getStructureModel(structureId)
	local adornee = getAdorneeFromModel(model)
	if not adornee then
		hideWorldDurabilityBar()
		return
	end

	ensureDurabilityBillboard()
	local ratio = math.clamp((struct.health or 0) / facilityData.maxHealth, 0, 1)

	durabilityBillboard.Adornee = adornee
	durabilityBillboard.Enabled = true
	focusedStructureId = structureId

	if durabilityTitle then
		durabilityTitle.Text = UILocalizer.Localize(facilityData.name or struct.facilityId or "시설")
	end

	if durabilityLabel then
		durabilityLabel.Text = string.format("%d%%", math.floor(ratio * 100))
	end

	if durabilityFill then
		TweenService:Create(durabilityFill, TweenInfo.new(0.1), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		if ratio < 0.25 then
			durabilityFill.BackgroundColor3 = Color3.fromRGB(210, 80, 80)
		elseif ratio < 0.5 then
			durabilityFill.BackgroundColor3 = Color3.fromRGB(220, 150, 70)
		else
			durabilityFill.BackgroundColor3 = Color3.fromRGB(95, 200, 120)
		end
	end
end

local function getLookedStructureId(): string?
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)

	local facilitiesFolder = workspace:FindFirstChild("Facilities")
	if not facilitiesFolder then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { facilitiesFolder }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 90, params)
	if not result then return nil end

	local hit = result.Instance
	if not hit then return nil end
	local model = hit:FindFirstAncestorWhichIsA("Model")

	return hit:GetAttribute("StructureId")
		or (hit.Parent and hit.Parent:GetAttribute("StructureId"))
		or (model and model:GetAttribute("StructureId"))
		or (model and model.Name)
end

--========================================
-- Public API: Cache Access
--========================================

function BuildController.getStructuresCache()
	return structuresCache
end

function BuildController.getStructure(structureId: string)
	return structuresCache[structureId]
end

function BuildController.getStructureCount(): number
	return structureCount
end

--========================================
-- Public API: Build Requests & Placement
--========================================

--- 건설 배치 모드 시작
function BuildController.startPlacement(facilityId: string)
	if isPlacing then BuildController.cancelPlacement() end
	
	local facilityData = DataHelper.GetData("FacilityData", facilityId)
	if not facilityData then return end
	
	currentFacilityId = facilityId
	currentGhost = createGhost(facilityId)
	if not currentGhost then return end
	
	isPlacing = true
	currentRotation = 0
	
	-- 매 프레임 위치 업데이트
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not currentGhost then return end
		
		-- 마우스가 가리키는 지면 찾기
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {currentGhost, player.Character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local mousePos = UserInputService:GetMouseLocation()
		local ray = workspace.CurrentCamera:ViewportPointToRay(mousePos.X, mousePos.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 150, rayParams) -- 사거리 소폭 상향
		
		local isPlaceable = false
		local finalCF = nil
		
		if result then
			local hitPos = result.Position
			local hitNormal = result.Normal
			local hitPart = result.Instance
			
			-- 기본 위치 설정 (건축물이 아닌 지면에 설치 시)
			local baseRotation = CFrame.Angles(0, math.rad(currentRotation), 0)
			finalCF = CFrame.lookAt(hitPos, hitPos + baseRotation.LookVector, hitNormal)
			
			-- [Snapping 핵심 로직]
			-- 1. 근처 시설물 검색
			local facilitiesFolder = workspace:FindFirstChild("Facilities")
			local snapFound = false
			
			if facilitiesFolder then
				-- 마우스 위치 주변 구조물 검색
				local overlap = OverlapParams.new()
				overlap.FilterType = Enum.RaycastFilterType.Include
				overlap.FilterDescendantsInstances = {facilitiesFolder}
				
				local nearby = workspace:GetPartBoundsInRadius(hitPos, 6, overlap)
				
				for _, part in ipairs(nearby) do
					local structId = part:GetAttribute("StructureId") or (part.Parent and part.Parent:GetAttribute("StructureId"))
					local fId = part:GetAttribute("FacilityId") or (part.Parent and part.Parent:GetAttribute("FacilityId"))
					
					if not fId then continue end
					
					-- 10x10x1 그리드 기준 스냅 (표준 사이즈 가정)
					local targetCF = part.CFrame
					local targetSize = part.Size
					
					-- (A) 토대 -> 토대 스냅 (옆으로 붙이기)
					if currentFacilityId:find("FOUNDATION") and fId:find("FOUNDATION") then
						local localPos = targetCF:PointToObjectSpace(hitPos)
						local snappedLocalPos = Vector3.new(0, 0, 0)
						
						-- X축 또는 Z축 중 마우스가 더 치우친 쪽으로 스냅
						if math.abs(localPos.X) > math.abs(localPos.Z) then
							snappedLocalPos = Vector3.new(math.sign(localPos.X) * 10, 0, 0)
						else
							snappedLocalPos = Vector3.new(0, 0, math.sign(localPos.Z) * 10)
						end
						
						finalCF = targetCF * CFrame.new(snappedLocalPos)
						snapFound = true
						break
						
					-- (B) 벽 -> 토대 스냅 (가장자리에 세우기)
					elseif currentFacilityId:find("WALL") and fId:find("FOUNDATION") then
						local localPos = targetCF:PointToObjectSpace(hitPos)
						local snappedLocalPos = Vector3.new(0, 5, 0) -- 토대 위 5 스터드 (벽 높이 절반)
						local wallRot = CFrame.Angles(0, 0, 0)
						
						if math.abs(localPos.X) > math.abs(localPos.Z) then
							snappedLocalPos = Vector3.new(math.sign(localPos.X) * 5, 5, 0)
							wallRot = CFrame.Angles(0, math.rad(90), 0)
						else
							snappedLocalPos = Vector3.new(0, 5, math.sign(localPos.Z) * 5)
							wallRot = CFrame.Angles(0, 0, 0)
						end
						
						finalCF = targetCF * CFrame.new(snappedLocalPos) * wallRot
						snapFound = true
						break
						
					-- (C) 지붕 -> 벽 스냅 (벽 위에 얹기)
					elseif currentFacilityId:find("ROOF") and fId:find("WALL") then
						local localPos = targetCF:PointToObjectSpace(hitPos)
						-- 벽의 회전 방향을 알아내야 함
						-- 벽은 높이가 10이므로 위쪽 스냅 (로컬 Y=5)
						local snappedLocalPos = Vector3.new(0, 5, 5) -- 벽 중심에서 앞쪽으로 5
						
						finalCF = targetCF * CFrame.new(0, 5, 0) -- 일단 벽 위 정중앙
						-- 마우스 방향에 따라 옆으로 확장 가능하지만 여기서는 수직 스냅만 우선
						snapFound = true
						break
					end
				end
			end
			
			if currentGhost.PrimaryPart then
				currentGhost:SetPrimaryPartCFrame(finalCF)
			end
			
			-- 건설 가능 조건 체크
			local dist = (player.Character.PrimaryPart.Position - hitPos).Magnitude
			isPlaceable = (dist <= 35) -- 35 스터드 이내로 상향
			
			if not snapFound then
				-- 스냅이 아닐 때는 경사도 체크
				local dot = hitNormal:Dot(Vector3.new(0, 1, 0))
				local slope = math.deg(math.acos(math.clamp(dot, -1, 1)))
				if slope > 45 then isPlaceable = false end
			else
				isPlaceable = true -- 스냅 지점은 경사 무시
			end
		else
			isPlaceable = false
		end

		
		-- Ghost 색상 업데이트
		local color = isPlaceable and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
		for _, p in ipairs(currentGhost:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Color = color
				p.Transparency = 0.6
			end
		end
	end)
	
	-- 키 입력 바인딩 (R: 회전, X: 취소)
	InputManager.bindKey(Enum.KeyCode.R, "BuildRotate", function()
		currentRotation = (currentRotation + 45) % 360
	end)
	
	InputManager.bindKey(Enum.KeyCode.X, "BuildCancel", function()
		BuildController.cancelPlacement()
	end)
	
	-- 좌클릭: 배치 확정
	InputManager.onLeftClick("BuildPlace", function()
		if isPlacing and currentGhost then
			-- Ghost 색상이 빨간색이면(불가) 무시
			local isRed = false
			local pPart = currentGhost.PrimaryPart
			if pPart and pPart.Color.R > pPart.Color.G then isRed = true end
			
			if isRed then
				local UIManager = require(script.Parent.Parent.UIManager)
				UIManager.notify("이 위치에는 건설할 수 없습니다.", Color3.fromRGB(255, 100, 100))
				return
			end
			
			local pos = currentGhost.PrimaryPart.Position
			-- rotation은 currentRotation 기반 또는 Ghost의 실제 rotation 전달
			local rot = Vector3.new(0, currentRotation, 0)
			BuildController.requestPlace(currentFacilityId, pos, rot)
		end
	end)

    -- UI 가이드 표시 (UIManager 연동은 UIManager에서 처리하거나 여기서 호출)
    local UIManager = require(script.Parent.Parent.UIManager)
    UIManager.showBuildPrompt(true)
end

--- 건설 배치 취소
function BuildController.cancelPlacement()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	if currentGhost then currentGhost:Destroy(); currentGhost = nil end
	
	InputManager.unbindKey(Enum.KeyCode.R)
	InputManager.unbindKey(Enum.KeyCode.X)
	InputManager.unbindLeftClick("BuildPlace")

	-- Build 모드가 R 바인딩을 덮어쓰므로 종료 시 시설 상호작용 R 바인딩을 복구
	InputManager.bindKey(Enum.KeyCode.R, "InteractFacilityR", function()
		local InteractController = require(script.Parent.InteractController)
		if InteractController.onFacilityInteractPress then
			InteractController.onFacilityInteractPress()
		end
	end)
	
	isPlacing = false
	currentFacilityId = nil
	
    local UIManager = require(script.Parent.Parent.UIManager)
    UIManager.showBuildPrompt(false)
end

--- 건설 요청 (시설물 배치)
function BuildController.requestPlace(facilityId: string, position: Vector3, rotation: Vector3?): (boolean, any)
	print(string.format("[BuildController] Requesting build: %s", facilityId))
	
	local success, data = NetClient.Request("Build.Place.Request", {
		facilityId = facilityId,
		position = position,
		rotation = rotation or Vector3.new(0, 0, 0),
	})
	
	if success then
		print("[BuildController] Build success")
		BuildController.cancelPlacement()
	else
		warn("[BuildController] Build failed:", data)
		local UIManager = require(script.Parent.Parent.UIManager)
		UIManager.notify("건설 실패: " .. tostring(data), Color3.fromRGB(255, 100, 100))
	end
	
	return success, data
end

--- 해체 요청 (시설물 제거)
function BuildController.requestRemove(structureId: string): (boolean, any)
	local success, data = NetClient.Request("Build.Remove.Request", {
		structureId = structureId,
	})
	return success, data
end

--- 전체 구조물 조회 요청
function BuildController.requestGetAll(): (boolean, any)
	local success, data = NetClient.Request("Build.GetAll.Request", {})
	
	if success and data and data.structures then
		structuresCache = {}
		structureCount = 0
		for _, struct in ipairs(data.structures) do
			structuresCache[struct.id] = struct
			structureCount = structureCount + 1
		end
	end
	
	return success, data
end

--========================================
-- Event Handlers
--========================================

local function onPlaced(data)
	if not data or not data.id then return end
	
	structuresCache[data.id] = {
		id = data.id,
		facilityId = data.facilityId,
		position = data.position,
		rotation = data.rotation,
		health = data.health,
		ownerId = data.ownerId,
	}
	structureCount = structureCount + 1
end

local function onRemoved(data)
	if not data or not data.id then return end
	if structuresCache[data.id] then
		structuresCache[data.id] = nil
		structureCount = structureCount - 1
	end

	if focusedStructureId == data.id then
		hideWorldDurabilityBar()
	end
end

local function onChanged(data)
	if not data or not data.id then return end
	local structure = structuresCache[data.id]
	if not structure then return end
	
	if data.changes then
		for key, value in pairs(data.changes) do
			structure[key] = value
		end
	end

	if focusedStructureId == data.id then
		updateWorldDurabilityBar(data.id)
	end
end

--========================================
-- Initialization
--========================================

function BuildController.Init()
	if initialized then return end
	
	NetClient.On("Build.Placed", onPlaced)
	NetClient.On("Build.Removed", onRemoved)
	NetClient.On("Build.Changed", onChanged)

	lookConn = RunService.Heartbeat:Connect(function(dt)
		lookRayAccumulator = lookRayAccumulator + dt
		if lookRayAccumulator < 0.08 then
			return
		end
		lookRayAccumulator = 0

		local lookedId = getLookedStructureId()
		if lookedId then
			updateWorldDurabilityBar(lookedId)
		else
			hideWorldDurabilityBar()
		end
	end)
	
	initialized = true
	print("[BuildController] Initialized")
end

return BuildController
