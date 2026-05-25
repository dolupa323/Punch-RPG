-- WorldDropController.lua
-- 클라이언트 월드 드롭 컨트롤러
-- 서버 WorldDrop 이벤트 수신 및 로컬 캐시 관리 + 3D 시각화

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent.NetClient)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local DataHelper = require(Shared.Util.DataHelper)

local WorldDropController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 드롭 캐시 [dropId] = { dropId, pos, itemId, count, despawnAt, inactive }
local dropsCache = {}
local dropCount = 0

-- 드롭 모델 캐시 [dropId] = Model
local dropModels = {}
-- 드롭 모델 폴더
local dropFolder = nil
-- [OPTIMIZATION] Batch Animation State
local animatingDrops = {} -- [dropId] = { model, startPos, t }
local renderConn = nil

--========================================
-- Helper Functions
--========================================

local function getDropColor(itemId: string): Color3
	if itemId == "GOLD" then
		return Color3.fromRGB(255, 215, 64)
	end
	if not itemId or itemId == "" then
		return Color3.fromRGB(200, 200, 200)
	end
	local itemData = DataHelper.GetData("ItemData", itemId:upper())
	return (itemData and itemData.color) or Color3.fromRGB(200, 200, 200)
end

local function getItemDisplayName(itemId: string, dropType: string?): string
	if dropType == "gold" or itemId == "GOLD" then
		return "골드"
	end
	if not itemId or itemId == "" then
		return "아이템"
	end
	local itemData = DataHelper.GetData("ItemData", itemId:upper())
	return (itemData and itemData.name) or itemId
end

local function findLootModel(itemId: string): (Instance?, boolean)
	-- 0. DNA 타입 체크
	local itemData = DataHelper.GetData("ItemData", itemId:upper())
	local isDna = itemData and itemData.type == "DNA"
	
	-- 1. 검색 시작 지점 (Assets 우선, 없으면 ReplicatedStorage 전체)
	local root = ReplicatedStorage:FindFirstChild("Assets") or ReplicatedStorage
	
	-- 2. 재귀 검색 함수
	local function searchRecursive(folder, target)
		if not folder then return nil end
		
		-- 직접 자식 확인 (대소문자 구분 없이)
		local found = folder:FindFirstChild(target)
		if not found then
			for _, child in ipairs(folder:GetChildren()) do
				if child.Name:upper() == target:upper() then
					found = child
					break
				end
			end
		end
		
		if found then return found end
		
		-- 하위 폴더 검색 (LootModels, ItemModels, Models 순으로 우선순위)
		local priority = {"LootModels", "ItemModels", "Models"}
		for _, pName in ipairs(priority) do
			local pFolder = folder:FindFirstChild(pName)
			if pFolder then
				local res = searchRecursive(pFolder, target)
				if res then return res end
			end
		end
		
		-- 기타 모든 자식 검색
		for _, child in ipairs(folder:GetChildren()) do
			if (child:IsA("Folder") or child:IsA("Model")) and not table.find(priority, child.Name) then
				local res = searchRecursive(child, target)
				if res then return res end
			end
		end
		
		return nil
	end
	
	-- 3. DNA는 전용 모델 우선 검색
	if isDna then
		local template = searchRecursive(root, "DNA_Sample")
		if template then return template, true end
	end
	
	-- 4. 실제 3D 모델 검색 (modelName 우선, 없으면 itemId)
	local targetName = (itemData and itemData.modelName) or itemId
	local template = searchRecursive(root, targetName)
	
	return template, isDna
end

-- [철벽 물리 강제 스케일링 엔진]: PrimaryPart 부재나 로블록스 API 오동작으로 ScaleTo가 실패하는 에셋 모델을 100% 강제 규격 크기로 축소하는 마스터피스 기법
local function scaleModelPhysically(model: Model, scaleFactor: number)
	if not model or scaleFactor <= 0 then return end
	local originalPivot = model:GetPivot()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Size = part.Size * scaleFactor
			local localCF = originalPivot:ToObjectSpace(part.CFrame)
			local newLocalCF = localCF.Rotation + (localCF.Position * scaleFactor)
			part.CFrame = originalPivot:ToWorldSpace(newLocalCF)
		elseif part:IsA("Attachment") then
			part.Position = part.Position * scaleFactor
		end
	end
end

local function createDropModel(dropData)
	if not dropData or not dropData.pos then return nil end
	
	local template, isDna = nil, false
	local isChest = false
	local isRune = false
	local itemData = DataHelper.GetData("ItemData", (dropData.itemId or ""):upper())
	
	if dropData.dropType ~= "gold" then
		-- [기획 보강]: 인벤토리에서 버리기 처리로 월드 드롭한 아이템은 무조건 Pouch 모델로 처리
		if dropData.dropSource == "DISCARD" then
			print(string.format("[WorldDropController] Item dropped via DISCARD. Finding 'Pouch' template..."))
			template = findLootModel("Pouch")
		elseif dropData.dropSource == "LOOT" and itemData and itemData.type == "RUNE" then
			print("[WorldDropController] Rune dropped via LOOT. Finding 'RuneModel' template...")
			template = findLootModel(itemData.modelName or "RuneModel")
			isRune = true
		-- [기획 보강]: 몬스터 사냥 전리품(LOOT) 중, 희귀도가 높거나(EPIC, LEGENDARY, RARE) 무기를 제외한 방어구 및 악세사리는 보물상자(Chest) 모델로 처리
		elseif dropData.dropSource == "LOOT" and itemData and (itemData.type == "ARMOR" or itemData.rarity == "EPIC" or itemData.rarity == "UNIQUE" or itemData.rarity == "LEGENDARY" or itemData.rarity == "RARE") then
			print(string.format("[WorldDropController] Armor/Accessory/High-Rarity loot detected. Finding 'Chest' template..."))
			template = findLootModel("Chest")
			isChest = true
		else
			-- 그 외 골드나 무기, 재료 등은 아이템 고유 모델 적용
			template, isDna = findLootModel(dropData.itemId)
		end
	end
	local mainObject
	local isModel = false
	
	-- [지면 정밀 밀착 엔진]: 지면(Terrain, Map, Baseplate 등)에만 찰떡같이 스냅되도록 Include 필터 레이캐스트 발사!
	local groundY = dropData.pos.Y
	local startRayPos = dropData.pos + Vector3.new(0, 10, 0) -- 시작점을 10스터드 위로 여유 있게 높임
	local rayDirection = Vector3.new(0, -60, 0) -- 60스터드 깊이로 탐색
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	
	-- 오직 진짜 대지(Terrain), Baseplate, 맵 디자인 폴더만 충돌 대상으로 명시! (몹 시체, 캐릭터, 상호작용 볼륨 100% 자동 통과)
	local includeInstances = {workspace.Terrain}
	for _, child in ipairs(workspace:GetChildren()) do
		local isPlayer = false
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p.Character == child then isPlayer = true; break end
		end
		local isMob = child:IsA("Model") and child:FindFirstChildOfClass("Humanoid")
		local isDrop = child == dropFolder
		
		if not isPlayer and not isMob and not isDrop then
			if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
				table.insert(includeInstances, child)
			end
		end
	end
	
	raycastParams.FilterDescendantsInstances = includeInstances
	
	local raycastResult = workspace:Raycast(startRayPos, rayDirection, raycastParams)
	if raycastResult then
		groundY = raycastResult.Position.Y
		print(string.format("[WorldDropController] Ground snapping successful! Hit '%s' at Y: %.2f", raycastResult.Instance.Name, groundY))
	end
	
	local correctedPos = Vector3.new(dropData.pos.X, groundY, dropData.pos.Z)
	local spawnCF = CFrame.new(correctedPos)
	
	print(string.format("[WorldDropController] Creating 3D drop model. ItemId: '%s', DropId: '%s', DropType: '%s', DropSource: '%s', HasTemplate: %s", 
		tostring(dropData.itemId), tostring(dropData.dropId), tostring(dropData.dropType), tostring(dropData.dropSource), tostring(template ~= nil)))
	
	if template then
		print(string.format("[WorldDropController] -> Asset template found. Name: '%s', Class: %s", template.Name, template.ClassName))
		mainObject = template:Clone()
		mainObject.Name = dropData.dropId
		mainObject.Parent = dropFolder -- Parent early to avoid warnings
		-- [수정] 모든 파트를 미리 Anchored로 설정하여 부모 설정 시 물리 연산 방지
		for _, p in ipairs(mainObject:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = true
				p.CanTouch = true
			end
		end
		if mainObject:IsA("BasePart") then
			mainObject.Anchored = true
			mainObject.CanCollide = false
		end
		
		-- [크기 정화 및 롤백]: 에셋 제작자가 만든 오리지널 예쁜 크기를 100% 최우선 존중! (DNA 등 지나치게 큰 모델만 1.5스터드로 제한 축소)
		-- [수정] 희귀 아이템용 보물상자(Chest) 및 룬(RUNE)은 일반 아이템보다 훨씬 크게(3.5스터드) 표시하여 만족도를 높임
		local DROP_TARGET = isDna and 1.0 or ((isChest or isRune) and 3.5 or (Balance.DROP_TARGET_SIZE or 1.5))
		if mainObject:IsA("Model") then
			local _, mSize = mainObject:GetBoundingBox()
			local maxDim = math.max(mSize.X, mSize.Y, mSize.Z)
			if maxDim > 0 and maxDim > DROP_TARGET then
				scaleModelPhysically(mainObject, DROP_TARGET / maxDim)
			end
		elseif mainObject:IsA("BasePart") then
			local maxDim = math.max(mainObject.Size.X, mainObject.Size.Y, mainObject.Size.Z)
			if maxDim > 0 and maxDim > DROP_TARGET then
				local s = DROP_TARGET / maxDim
				mainObject.Size = mainObject.Size * s
			end
		end
		
		-- [정밀 지면 밀착] 모델 고유 피벗을 해킹하지 않고 최하단 Y축 정밀 오프셋만 보정 (correctedPos 지면 좌표 적용)
		if mainObject:IsA("Model") then
			local cframe, size = mainObject:GetBoundingBox()
			-- 모델 피벗 중심점과 모델 최하단 바닥면 사이의 Y축 오프셋 거리 산출
			local pivotYOffset = mainObject:GetPivot().Position.Y - (cframe.Position.Y - size.Y / 2)
			spawnCF = CFrame.new(correctedPos + Vector3.new(0, pivotYOffset, 0))
		else
			spawnCF = CFrame.new(correctedPos + Vector3.new(0, mainObject.Size.Y / 2, 0))
		end
		
		mainObject:PivotTo(spawnCF)
		
		-- [수정] 자연스러운 등장을 위해 지면에서 솟구치는 팝업 트윈 및 투명도 페이드인 적용 (ScaleTo 버그 원천 차단)
		if mainObject:IsA("Model") then
			local parts = {}
			for _, p in ipairs(mainObject:GetDescendants()) do
				if p:IsA("BasePart") then
					table.insert(parts, p)
					-- 보물상자 하이라이트가 투명도 페이드 시 거슬리지 않도록 보정
					p.Transparency = 1
					TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
				end
			end
			local startCF = spawnCF * CFrame.new(0, -0.8, 0)
			mainObject:PivotTo(startCF)
			
			local val = Instance.new("CFrameValue")
			val.Value = startCF
			val.Changed:Connect(function(newCF)
				if mainObject.Parent then
					mainObject:PivotTo(newCF)
				end
			end)
			local tween = TweenService:Create(val, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Value = spawnCF })
			tween.Completed:Connect(function() val:Destroy() end)
			tween:Play()
		elseif mainObject:IsA("BasePart") then
			local targetSize = mainObject.Size
			mainObject.Size = targetSize * 0.1
			TweenService:Create(mainObject, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = targetSize }):Play()
		end
	else
		-- Fallback to visually distinct parts if assets are missing
		mainObject = Instance.new("Part")
		mainObject.Name = dropData.dropId
		mainObject.Parent = dropFolder
		mainObject.Anchored = true 
		mainObject.CanCollide = false
		mainObject.CanQuery = true
		mainObject.CanTouch = true

		if dropData.dropSource == "DISCARD" then
			-- Pouch 모델 부재 시: 귀여운 갈색 가죽 주머니 모양 구체
			local targetSize = Vector3.new(1.1, 1.3, 1.1)
			mainObject.Size = targetSize * 0.1
			mainObject.Shape = Enum.PartType.Ball
			mainObject.Color = Color3.fromRGB(139, 69, 19) -- 갈색 가죽색
			mainObject.Material = Enum.Material.Fabric
			TweenService:Create(mainObject, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = targetSize }):Play()
			warn(string.format("[WorldDropController] -> 'Pouch' asset missing! Fallback to Brown Fabric Sphere."))
		elseif dropData.dropSource == "LOOT" and itemData and (itemData.type == "ARMOR" or itemData.rarity == "EPIC" or itemData.rarity == "UNIQUE" or itemData.rarity == "LEGENDARY" or itemData.rarity == "RARE") then
			-- Chest 모델 부재 시: 영롱한 황금 보물상자 모양 직육면체
			local targetSize = Vector3.new(3.5, 2.5, 2.5)
			mainObject.Size = targetSize * 0.1
			mainObject.Shape = Enum.PartType.Block
			mainObject.Color = Color3.fromRGB(255, 200, 50) -- 황금색
			mainObject.Material = Enum.Material.DiamondPlate
			TweenService:Create(mainObject, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = targetSize }):Play()
			warn(string.format("[WorldDropController] -> 'Chest' asset missing! Fallback to Golden DiamondPlate Block."))
		else
			-- 일반 기본 폴백
			local targetSize = Balance.DROP_SIZE or Vector3.new(1, 1, 1)
			mainObject.Size = targetSize * 0.1
			mainObject.Shape = Enum.PartType.Ball
			mainObject.Color = getDropColor(dropData.dropType == "gold" and "GOLD" or dropData.itemId)
			mainObject.Material = Enum.Material.SmoothPlastic
			TweenService:Create(mainObject, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = targetSize }):Play()
		end
	end
	
	-- [수정] 상단 이름표 박스 제거 (요청 사항)
	local highlight = Instance.new("Highlight")
	if isDna then
		-- DNA 전용 하이라이트: 밝은 녹색 발광
		highlight.FillColor = Color3.fromRGB(0, 255, 180)
		highlight.FillTransparency = 0.3
		highlight.OutlineColor = Color3.fromRGB(100, 255, 200)
		highlight.OutlineTransparency = 0.0
	else
		highlight.FillColor = template and Color3.new(1,1,1) or (mainObject:IsA("BasePart") and mainObject.Color or Color3.new(1,1,1))
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0.5
	end
	highlight.Parent = mainObject
	
	-- DNA 드랍 시 PointLight로 빛 연출
	if isDna then
		local lightPart = mainObject:IsA("Model") and (mainObject.PrimaryPart or mainObject:FindFirstChildWhichIsA("BasePart", true)) or mainObject
		if lightPart and lightPart:IsA("BasePart") then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(0, 255, 180)
			light.Brightness = 3
			light.Range = 12
			light.Parent = lightPart
		end
	end
	
	-- 상호작용 포인트 설정 (아이템 본체)
	local attachmentPoint = mainObject
	if mainObject:IsA("Model") then
		attachmentPoint = mainObject.PrimaryPart or mainObject:FindFirstChildWhichIsA("BasePart", true) or mainObject
	end
	
	-- [수정] BillboardGui(상단 박스) 생성 코드 완전 삭제
	
	-- ProximityPrompt (줍기)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = UILocalizer.Localize("줍기")
	local amountText = dropData.dropType == "gold" and (tostring(dropData.goldAmount or dropData.count) .. " G") or ("x" .. tostring(dropData.count))
	prompt.ObjectText = getItemDisplayName(dropData.itemId or "GOLD", dropData.dropType) .. " (" .. amountText .. ")"
	prompt.MaxActivationDistance = Balance.DROP_PROMPT_RANGE
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.Z
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachmentPoint
	
	prompt.Triggered:Connect(function(player)
		if player == game.Players.LocalPlayer then
			task.spawn(function()
				local success, errorCode = NetClient.Request("WorldDrop.Loot.Request", {
					dropId = dropData.dropId,
				})
				
				if not success then
					warn("[WorldDropController] 줍기 실패: ", tostring(errorCode))
					local uiSuccess, UIManager = pcall(function() return _G.UIManager or require(script.Parent.Parent.UI.UIManager) end)
					if uiSuccess and UIManager and UIManager.ShowToast then
						if errorCode == "INV_FULL" then
							UIManager.ShowToast("가방이 꽉 찼습니다!", 3, Color3.fromRGB(255, 50, 50))
						elseif errorCode == "OUT_OF_RANGE" then
							UIManager.ShowToast("아이템이 너무 멀리 있습니다!", 3, Color3.fromRGB(255, 100, 50))
						else
							UIManager.ShowToast("아이템을 주울 수 없습니다: " .. tostring(errorCode), 3, Color3.fromRGB(255, 50, 50))
						end
					end
				end
			end)
		end
	end)
	
	-- [수정] 배치 애니메이션 등록 시 정확하게 들어올려진 지면 밀착 좌표(spawnCF)를 기준점으로 사용하여 회전 및 부유 축 고정!
	animatingDrops[dropData.dropId] = {
		model = mainObject,
		startPos = spawnCF.Position,
		t = math.random() * math.pi * 2
	}
	
	print(string.format("[WorldDropController] Successfully finalized drop 3D model. Parent: '%s', Position: %s, Pivot: %s, Interactive: %s", 
		tostring(mainObject.Parent), tostring(mainObject:GetPivot().Position), tostring(spawnCF.Position), tostring(attachmentPoint.Name)))
	
	return mainObject
end

local function updateDropModel(dropId, newCount)
	local model = dropModels[dropId]
	if not model then return end
	
	-- [수정] BillboardGui 관련 로직 제거 및 ProximityPrompt 업데이트 통합
	local prompt = model:FindFirstChild("PickupPrompt") or model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		local drop = dropsCache[dropId]
		local itemId = drop and drop.itemId or "Unknown"
		local displayCount = (drop and drop.dropType == "gold") and ((tostring(drop.goldAmount or newCount)) .. " G") or ("x" .. tostring(newCount))
		prompt.ObjectText = getItemDisplayName(itemId, drop and drop.dropType) .. " (" .. displayCount .. ")"
	end
end

local function removeDropModel(dropId)
	local model = dropModels[dropId]
	if model then
		-- [FIX] 삭제 시작 알림
		model:SetAttribute("IsDestroying", true)
		dropModels[dropId] = nil
		animatingDrops[dropId] = nil -- [OPTIMIZATION] Remove from batch animation
		
		if model:IsA("BasePart") then
			local tween = TweenService:Create(model, TweenInfo.new(0.2), { Transparency = 1 })
			tween:Play()
			tween.Completed:Connect(function() model:Destroy() end)
		else
			-- For Models, fade out all parts
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					TweenService:Create(p, TweenInfo.new(0.2), { Transparency = 1 }):Play()
				end
			end
			task.delay(0.25, function()
				model:Destroy()
			end)
		end
	end
end

--========================================
-- Public API: Cache Access
--========================================

function WorldDropController.getDropsCache()
	return dropsCache
end

function WorldDropController.getDrop(dropId: string)
	return dropsCache[dropId]
end

function WorldDropController.getDropCount(): number
	return dropCount
end

--========================================
-- Event Handlers
--========================================

local function onSpawned(data)
	if not data or not data.dropId then return end
	
	dropsCache[data.dropId] = {
		dropId = data.dropId,
		pos = data.pos,
		itemId = data.itemId,
		dropType = data.dropType,
		dropSource = data.dropSource, -- [신설] Loot vs Discard 식별자 수신
		goldAmount = data.goldAmount,
		count = data.count,
		despawnAt = data.despawnAt,
		inactive = data.inactive,
	}
	dropCount = dropCount + 1
	
	-- 3D 모델 생성
	local model = createDropModel(dropsCache[data.dropId])
	if model then
		dropModels[data.dropId] = model
	end
	
	-- 디버그 로그 (Studio에서만)
	-- print(string.format("[WorldDropController] Spawned: %s (%s x%d)", data.dropId, data.itemId, data.count))
end

local function onChanged(data)
	if not data or not data.dropId then return end
	
	local drop = dropsCache[data.dropId]
	if drop then
		drop.count = data.count
		drop.goldAmount = data.goldAmount or data.count
		updateDropModel(data.dropId, data.count)
		-- print(string.format("[WorldDropController] Changed: %s -> %d", data.dropId, data.count))
	end
end

local function onDespawned(data)
	if not data or not data.dropId then return end
	
	if dropsCache[data.dropId] then
		dropsCache[data.dropId] = nil
		dropCount = dropCount - 1
		removeDropModel(data.dropId)
		-- print(string.format("[WorldDropController] Despawned: %s (%s)", data.dropId, data.reason))
	end
end

--========================================
-- Initialization
--========================================

function WorldDropController.Init()
	if initialized then
		warn("[WorldDropController] Already initialized")
		return
	end
	
	-- 드롭 모델 폴더 생성
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "WorldDrops"
	dropFolder.Parent = Workspace
	
	-- 이벤트 리스너 등록
	NetClient.On("WorldDrop.Spawned", onSpawned)
	NetClient.On("WorldDrop.Changed", onChanged)
	NetClient.On("WorldDrop.Despawned", onDespawned)
	
	-- [OPTIMIZATION] Batch Animation Loop
	local camera = Workspace.CurrentCamera
	renderConn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local playerChar = game.Players.LocalPlayer.Character
		local hrp = playerChar and playerChar:FindFirstChild("HumanoidRootPart")
		local pPos = hrp and hrp.Position or Vector3.zero
		
		for id, data in pairs(animatingDrops) do
			local model = data.model
			if not model or not model.Parent then
				animatingDrops[id] = nil
				continue
			end
			
			-- 1. 거리 기반 최적화 (너무 먼 것은 애니메이션 스킵)
			local dist = (data.startPos - pPos).Magnitude
			if dist > 150 then continue end
			
			-- 2. 카메라 가시성 체크 (Frustum Culling)
			if dist > 30 then
				local _, onScreen = camera:WorldToViewportPoint(data.startPos)
				if not onScreen then continue end
			end
			
			-- 시간 누적 및 상하 부유 애니메이션 적용
			data.t = data.t + dt
			local t = data.t
			local finalY = data.startPos.Y + math.sin(t * 2) * 0.1 -- 흔들림 강도 최적화
			
			-- [수정] 모든 타입을 PivotTo로 처리하여 안정적인 위치 유지 (하단 기준 지면 밀착)
			local targetCF = CFrame.new(data.startPos.X, finalY, data.startPos.Z) * CFrame.Angles(0, t, 0)
			model:PivotTo(targetCF)
		end
	end)
	
	initialized = true
	print("[WorldDropController] Initialized - Animation optimized with RenderStepped Batching")
	
	-- [서버 권위 동기화] 클라이언트 로딩 선후관계 경쟁 상태로 유실된 활성 드롭 리스트 완벽 복구 및 동기화
	task.spawn(function()
		task.wait(0.5) -- 클라이언트 초기화 완료 시간 확보
		local pcallSuccess, requestSuccess, dataOrError = pcall(function()
			return NetClient.Request("WorldDrop.GetActiveDrops")
		end)
		
		if pcallSuccess and requestSuccess and dataOrError then
			print(string.format("[WorldDropController] Syncing %d active drops from server...", #dataOrError))
			for _, dropData in ipairs(dataOrError) do
				if not dropsCache[dropData.dropId] then
					onSpawned(dropData)
				end
			end
		else
			warn("[WorldDropController] Failed to sync active drops from server:", tostring(dataOrError or "Unknown error"))
		end
	end)
end

return WorldDropController
