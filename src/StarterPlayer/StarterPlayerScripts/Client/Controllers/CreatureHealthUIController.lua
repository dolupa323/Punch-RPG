-- CreatureHealthUIController.lua
-- 크리처 HP/Torpor BillboardGui를 클라이언트에서 생성·관리하는 컨트롤러
-- 서버는 Attribute(CurrentHealth, MaxHealth, CurrentTorpor, MaxTorpor, LabelVisibleUntil)만 설정
-- 클라이언트가 AttributeChanged 이벤트를 감지하여 로컬에서만 UI를 갱신 → 복제 대역폭 절감

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local CreatureHealthUIController = {}

local initialized = false
local trackedCreatures = {} -- [model] = { gui, healthFill, torporFill, connections }

--========================================
-- Private Functions
--========================================

local function createBillboardGui(model, rootPart)
	local _, size = model:GetBoundingBox()
	local offsetY = 2
	if size.Y > 15 then
		offsetY = 3
	end

	local bg = Instance.new("BillboardGui")
	bg.Name = "CreatureLabel"
	bg.Size = UDim2.new(0, 100, 0, 30)
	bg.StudsOffset = Vector3.new(0, (size.Y / 2) + offsetY, 0)
	bg.AlwaysOnTop = true
	bg.MaxDistance = 60
	bg.Enabled = false
	bg.Parent = rootPart

	-- 배경 프레임
	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.95
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = bg

	local cornerMain = Instance.new("UICorner")
	cornerMain.CornerRadius = UDim.new(0, 4)
	cornerMain.Parent = mainFrame

	-- 이름 텍스트
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = model:GetAttribute("DisplayName") or model.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextTransparency = 0.5
	nameLabel.TextStrokeTransparency = 1
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 8
	nameLabel.Parent = mainFrame

	-- HP 바 배경
	local healthBG = Instance.new("Frame")
	healthBG.Name = "HealthBG"
	healthBG.Size = UDim2.new(0.8, 0, 0.15, 0)
	healthBG.Position = UDim2.new(0.5, 0, 0.65, 0)
	healthBG.AnchorPoint = Vector2.new(0.5, 0)
	healthBG.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	healthBG.BackgroundTransparency = 1
	healthBG.BorderSizePixel = 0
	healthBG.Parent = mainFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = healthBG

	-- HP 바 채우기
	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
	healthFill.BackgroundTransparency = 0.6
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBG

	local corner2 = corner:Clone()
	corner2.Parent = healthFill

	-- Torpor 바 배경
	local torporBG = Instance.new("Frame")
	torporBG.Name = "TorporBG"
	torporBG.Size = UDim2.new(0.8, 0, 0.1, 0)
	torporBG.Position = UDim2.new(0.5, 0, 0.85, 0)
	torporBG.AnchorPoint = Vector2.new(0.5, 0)
	torporBG.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	torporBG.BackgroundTransparency = 1
	torporBG.BorderSizePixel = 0
	torporBG.Parent = mainFrame

	local corner3 = corner:Clone()
	corner3.Parent = torporBG

	-- Torpor 바 채우기
	local torporFill = Instance.new("Frame")
	torporFill.Name = "TorporFill"
	torporFill.Size = UDim2.new(0, 0, 1, 0)
	torporFill.BackgroundColor3 = Color3.fromRGB(160, 60, 220)
	torporFill.BackgroundTransparency = 0.6
	torporFill.BorderSizePixel = 0
	torporFill.Visible = false
	torporFill.Parent = torporBG

	local corner4 = corner:Clone()
	corner4.Parent = torporFill

	return bg, healthFill, torporFill
end

local function updateHealthBar(healthFill, currentHealth, maxHealth)
	if not healthFill or not healthFill.Parent then return end
	
	-- ★ [FIX] 체력이 0 이하면 바를 즉시 0으로 표시
	if currentHealth <= 0 then
		healthFill.Size = UDim2.new(0, 0, 1, 0)
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		return
	end
	
	local hpRatio = math.clamp(currentHealth / math.max(maxHealth, 1), 0, 1)
	healthFill.Size = UDim2.new(hpRatio, 0, 1, 0)

	if hpRatio > 0.5 then
		healthFill.BackgroundColor3 = Color3.fromRGB(60, 220, 60)
	elseif hpRatio > 0.2 then
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
	else
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	end
end

local function updateTorporBar(torporFill, currentTorpor, maxTorpor)
	if not torporFill or not torporFill.Parent then return end
	local torporRatio = math.clamp(currentTorpor / math.max(maxTorpor, 1), 0, 1)
	torporFill.Size = UDim2.new(torporRatio, 0, 1, 0)
	torporFill.Visible = torporRatio > 0
end

local function setupCreature(model)
	-- ★ [FIX] 같은 모델 재사용 시 이전 UI 정리 (채집노드/시체 재사용 대비)
	if trackedCreatures[model] then
		cleanupCreature(model)
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not rootPart then return end

	local bg, healthFill, torporFill = createBillboardGui(model, rootPart)

	-- 초기 상태 반영
	local maxHealth = model:GetAttribute("MaxHealth") or 100
	local currentHealth = model:GetAttribute("CurrentHealth") or maxHealth
	local maxTorpor = model:GetAttribute("MaxTorpor") or 100
	local currentTorpor = model:GetAttribute("CurrentTorpor") or 0
	updateHealthBar(healthFill, currentHealth, maxHealth)
	updateTorporBar(torporFill, currentTorpor, maxTorpor)

	local connections = {}

	-- Attribute 변경 감지 (클라이언트에서만 UI 갱신)
	table.insert(connections, model:GetAttributeChangedSignal("CurrentHealth"):Connect(function()
		local hp = model:GetAttribute("CurrentHealth") or 0
		local maxHp = model:GetAttribute("MaxHealth") or 100
		updateHealthBar(healthFill, hp, maxHp)
		-- ★ [FIX] 체력 0일 때 BillboardGui도 즉시 숨김
		if hp <= 0 then
			bg.Enabled = false
		end
	end))

	table.insert(connections, model:GetAttributeChangedSignal("MaxHealth"):Connect(function()
		local hp = model:GetAttribute("CurrentHealth") or 0
		local maxHp = model:GetAttribute("MaxHealth") or 100
		updateHealthBar(healthFill, hp, maxHp)
	end))

	table.insert(connections, model:GetAttributeChangedSignal("CurrentTorpor"):Connect(function()
		local torpor = model:GetAttribute("CurrentTorpor") or 0
		local maxTorpor2 = model:GetAttribute("MaxTorpor") or 100
		updateTorporBar(torporFill, torpor, maxTorpor2)
	end))

	table.insert(connections, model:GetAttributeChangedSignal("MaxTorpor"):Connect(function()
		local torpor = model:GetAttribute("CurrentTorpor") or 0
		local maxTorpor2 = model:GetAttribute("MaxTorpor") or 100
		updateTorporBar(torporFill, torpor, maxTorpor2)
	end))

	table.insert(connections, model:GetAttributeChangedSignal("LabelVisibleUntil"):Connect(function()
		local untilTs = model:GetAttribute("LabelVisibleUntil") or 0
		local hp = model:GetAttribute("CurrentHealth") or 0
		-- ★ [FIX] 체력이 0 이하면 즉시 숨김
		bg.Enabled = (hp > 0) and (untilTs > tick())
	end))

	trackedCreatures[model] = {
		gui = bg,
		healthFill = healthFill,
		torporFill = torporFill,
		connections = connections,
	}
end

local function cleanupCreature(model)
	local info = trackedCreatures[model]
	if not info then return end

	for _, conn in ipairs(info.connections) do
		conn:Disconnect()
	end
	if info.gui and info.gui.Parent then
		info.gui:Destroy()
	end

	trackedCreatures[model] = nil
end

local function setupFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			task.defer(setupCreature, child)
		end
	end

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(setupCreature, child)
		end
	end)

	folder.ChildRemoved:Connect(function(child)
		cleanupCreature(child)
	end)
end

--========================================
-- Public API
--========================================

function CreatureHealthUIController.Init()
	if initialized then return end

	task.spawn(function()
		local creatureFolder = Workspace:WaitForChild("Creatures", 30)
		if creatureFolder then
			setupFolder(creatureFolder)
		end
	end)

	-- 라벨 표시 타이머 관리 (LabelVisibleUntil 경과 시 자동 숨김)
	RunService.Heartbeat:Connect(function()
		local now = tick()
		for model, info in pairs(trackedCreatures) do
			if not model:IsDescendantOf(Workspace) then
				cleanupCreature(model)
			elseif info.gui.Enabled then
				local untilTs = model:GetAttribute("LabelVisibleUntil") or 0
				local hp = model:GetAttribute("CurrentHealth") or 0
				if now > untilTs or hp <= 0 then
					info.gui.Enabled = false
				end
			end
		end
	end)

	initialized = true
	print("[CreatureHealthUIController] Initialized")
end

return CreatureHealthUIController
