-- ClientInit.client.lua
-- 클라이언트 초기화 스크립트

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")

local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UIManager = require(Client.UIManager)
local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local player = Players.LocalPlayer

local function createStudioAdminGoldPanel()
	local function checkIsAdmin(userId)
		return RunService:IsStudio() or Balance.ADMIN_IDS[userId] == true
	end

	if not checkIsAdmin(player.UserId) then
		return
	end

	-- [임시 해제] 기존 줌아웃 제한: 45 (Balance.CAM_MAX_ZOOM)
	player.CameraMaxZoomDistance = 1000 -- Balance.CAM_MAX_ZOOM
	player.CameraMinZoomDistance = Balance.CAM_MIN_ZOOM
	
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui or playerGui:FindFirstChild("StudioAdminGoldUI") then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "StudioAdminGoldUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.Parent = playerGui

	-- [반응형] 모바일 여부 확인
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = isMobile and 0.85 or 1.0
	uiScale.Parent = gui

	local frame = Instance.new("ScrollingFrame")
	frame.Name = "StudioAdminPanel"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = isMobile and UDim2.new(1, -10, 0, 85) or UDim2.new(1, -48, 0, 85)
	frame.Size = UDim2.new(0, isMobile and 200 or 250, 0, isMobile and 260 or 360)
	frame.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ScrollBarThickness = 4
	frame.ScrollBarImageColor3 = Color3.fromRGB(185, 155, 80)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.Parent = gui
	
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 10)
	frameCorner.Parent = frame
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(185, 155, 80)
	frameStroke.Thickness = 1.2
	frameStroke.Parent = frame

	local list = Instance.new("UIListLayout", frame)
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder

	local pad = Instance.new("UIPadding", frame)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "AdminToggleBtn"
	toggleBtn.Size = UDim2.new(0, 42, 0, 42)
	toggleBtn.Position = isMobile and UDim2.new(1, -10, 0, 40) or UDim2.new(1, -5, 0, 80)
	toggleBtn.AnchorPoint = Vector2.new(1, 0)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	toggleBtn.BackgroundTransparency = 0.18
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Text = "ADM"
	toggleBtn.TextColor3 = Color3.fromRGB(255, 220, 120)
	toggleBtn.TextSize = 13
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.Parent = gui
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 6)
	toggleCorner.Parent = toggleBtn
	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = Color3.fromRGB(185, 155, 80)
	toggleStroke.Thickness = 1
	toggleStroke.Parent = toggleBtn

	toggleBtn.MouseButton1Click:Connect(function()
		frame.Visible = not frame.Visible
	end)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, isMobile and 20 or 24)
	title.BackgroundTransparency = 1
	title.Text = "Studio Admin Panel"
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.TextSize = isMobile and 14 or 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local goldLabel = Instance.new("TextLabel")
	goldLabel.Size = UDim2.new(1, 0, 0, isMobile and 14 or 18)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Text = "현재 골드: --"
	goldLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	goldLabel.TextSize = isMobile and 12 or 14
	goldLabel.Font = Enum.Font.Gotham
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Parent = frame

	local amountBox = Instance.new("TextBox")
	amountBox.Size = UDim2.new(1, 0, 0, isMobile and 28 or 32)
	amountBox.BackgroundColor3 = Color3.fromRGB(38, 42, 48)
	amountBox.BorderSizePixel = 0
	amountBox.Text = "5000"
	amountBox.PlaceholderText = "지급 골드"
	amountBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	amountBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
	amountBox.TextSize = isMobile and 14 or 16
	amountBox.Font = Enum.Font.Gotham
	amountBox.ClearTextOnFocus = false
	amountBox.Parent = frame
	local amountCorner = Instance.new("UICorner")
	amountCorner.CornerRadius = UDim.new(0, 6)
	amountCorner.Parent = amountBox

	local goldBtns = Instance.new("Frame")
	goldBtns.Size = UDim2.new(1, 0, 0, isMobile and 28 or 32)
	goldBtns.BackgroundTransparency = 1
	goldBtns.Parent = frame
	local gGrid = Instance.new("UIListLayout", goldBtns)
	gGrid.FillDirection = Enum.FillDirection.Horizontal
	gGrid.Padding = UDim.new(0, 8)

	local grantButton = Instance.new("TextButton")
	grantButton.Size = UDim2.new(0.65, -4, 1, 0)
	grantButton.BackgroundColor3 = Color3.fromRGB(196, 164, 74)
	grantButton.BorderSizePixel = 0
	grantButton.Text = "골드 지급"
	grantButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	grantButton.TextSize = isMobile and 12 or 14
	grantButton.Font = Enum.Font.GothamBold
	grantButton.Parent = goldBtns
	Instance.new("UICorner", grantButton).CornerRadius = UDim.new(0, 6)

	local refreshButton = Instance.new("TextButton")
	refreshButton.Size = UDim2.new(0.35, -4, 1, 0)
	refreshButton.BackgroundColor3 = Color3.fromRGB(70, 78, 92)
	refreshButton.BorderSizePixel = 0
	refreshButton.Text = "새로고침"
	refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	refreshButton.TextSize = isMobile and 12 or 14
	refreshButton.Font = Enum.Font.GothamBold
	refreshButton.Parent = goldBtns
	Instance.new("UICorner", refreshButton).CornerRadius = UDim.new(0, 6)

	local ShopController = require(Controllers.ShopController)

	local function refreshGold()
		ShopController.requestGold(function(ok, amount)
			if ok then
				goldLabel.Text = string.format("현재 골드: %d", tonumber(amount) or 0)
			end
		end)
	end

	ShopController.onGoldChanged(function(amount)
		goldLabel.Text = string.format("현재 골드: %d", tonumber(amount) or 0)
	end)

	refreshButton.MouseButton1Click:Connect(refreshGold)
	grantButton.MouseButton1Click:Connect(function()
		local amount = math.floor(tonumber(amountBox.Text) or 0)
		if amount <= 0 then
			UIManager.notify("지급 골드를 올바르게 입력하세요.", Color3.fromRGB(255, 100, 100))
			return
		end

		local ok, data = NetClient.Request("Shop.Admin.GrantGold.Request", {
			amount = amount,
		})
		if ok and type(data) == "table" then
			UIManager.notify(string.format("Studio 골드 %d 지급 완료", amount), Color3.fromRGB(255, 220, 120))
			refreshGold()
		else
			UIManager.notify("골드 지급에 실패했습니다.", Color3.fromRGB(255, 100, 100))
		end
	end)

	refreshGold()

	--========================================
	-- Level & Account Reset (Marketing)
	--========================================
	local line2 = Instance.new("Frame")
	line2.Size = UDim2.new(1, 0, 0, 1)
	line2.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	line2.BorderSizePixel = 0
	line2.Parent = frame

	local levelTitle = Instance.new("TextLabel")
	levelTitle.Size = UDim2.new(1, 0, 0, 20)
	levelTitle.BackgroundTransparency = 1
	levelTitle.Text = "Level & Reset (Marketing)"
	levelTitle.TextColor3 = Color3.fromRGB(255, 150, 100)
	levelTitle.TextSize = 14
	levelTitle.Font = Enum.Font.GothamBold
	levelTitle.TextXAlignment = Enum.TextXAlignment.Left
	levelTitle.Parent = frame

	local lvBtns = Instance.new("Frame")
	lvBtns.Size = UDim2.new(1, 0, 0, 32)
	lvBtns.BackgroundTransparency = 1
	lvBtns.Parent = frame
	local lvGrid = Instance.new("UIListLayout", lvBtns)
	lvGrid.FillDirection = Enum.FillDirection.Horizontal
	lvGrid.Padding = UDim.new(0, 8)

	local lvBox = Instance.new("TextBox")
	lvBox.Size = UDim2.new(0.35, -4, 1, 0)
	lvBox.BackgroundColor3 = Color3.fromRGB(38, 42, 48)
	lvBox.Text = "50"
	lvBox.PlaceholderText = "레벨"
	lvBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	lvBox.TextSize = 14
	lvBox.Font = Enum.Font.Gotham
	lvBox.Parent = lvBtns
	Instance.new("UICorner", lvBox).CornerRadius = UDim.new(0, 6)

	local setLvBtn = Instance.new("TextButton")
	setLvBtn.Size = UDim2.new(0.65, -4, 1, 0)
	setLvBtn.BackgroundColor3 = Color3.fromRGB(100, 120, 180)
	setLvBtn.Text = "레벨 설정"
	setLvBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	setLvBtn.TextSize = 13
	setLvBtn.Font = Enum.Font.GothamBold
	setLvBtn.Parent = lvBtns
	Instance.new("UICorner", setLvBtn).CornerRadius = UDim.new(0, 6)

	local fullResetBtn = Instance.new("TextButton")
	fullResetBtn.Size = UDim2.new(1, 0, 0, 32)
	fullResetBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	fullResetBtn.Text = "마케팅용 완전 초기화 (!)"
	fullResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	fullResetBtn.TextSize = 13
	fullResetBtn.Font = Enum.Font.GothamBold
	fullResetBtn.Parent = frame
	Instance.new("UICorner", fullResetBtn).CornerRadius = UDim.new(0, 6)

	-- 강화 아이템 지급 버튼 추가
	local giveEnhanceBtn = Instance.new("TextButton")
	giveEnhanceBtn.Size = UDim2.new(1, 0, 0, 32)
	giveEnhanceBtn.BackgroundColor3 = Color3.fromRGB(185, 155, 80)
	giveEnhanceBtn.Text = "강화 아이템 세트 지급"
	giveEnhanceBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
	giveEnhanceBtn.TextSize = 13
	giveEnhanceBtn.Font = Enum.Font.GothamBold
	giveEnhanceBtn.Parent = frame
	Instance.new("UICorner", giveEnhanceBtn).CornerRadius = UDim.new(0, 6)

	giveEnhanceBtn.MouseButton1Click:Connect(function()
		local ok = NetClient.Request("Admin.GiveEnhanceSet.Request", {})
		if ok then
			UIManager.notify("강화 테스트 아이템이 지급되었습니다.", Color3.fromRGB(255, 220, 120))
		end
	end)

	setLvBtn.MouseButton1Click:Connect(function()
		local lv = tonumber(lvBox.Text)
		if not lv then return end
		local ok = NetClient.Request("Admin.SetLevel.Request", { level = lv })
		if ok then
			UIManager.notify("레벨이 " .. lv .. "로 설정되었습니다.", Color3.fromRGB(100, 200, 255))
		end
	end)

	fullResetBtn.MouseButton1Click:Connect(function()
		local ok = NetClient.Request("Admin.FullReset.Request", {})
		if ok then
			UIManager.notify("계정이 완전히 초기화되었습니다.", Color3.fromRGB(255, 100, 100))
			frame.Visible = false -- 촬영을 위해 패널 닫기
		end
	end)

	--========================================
	-- New Tutorial (Manual Test)
	--========================================
	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	line.BorderSizePixel = 0
	line.Parent = frame

	local tutTitle = Instance.new("TextLabel")
	tutTitle.Size = UDim2.new(1, 0, 0, isMobile and 16 or 20)
	tutTitle.BackgroundTransparency = 1
	tutTitle.Text = "Tutorial (Manual Test)"
	tutTitle.TextColor3 = Color3.fromRGB(150, 255, 180)
	tutTitle.TextSize = isMobile and 12 or 14
	tutTitle.Font = Enum.Font.GothamBold
	tutTitle.TextXAlignment = Enum.TextXAlignment.Left
	tutTitle.Parent = frame

	local tutLabel = Instance.new("TextLabel")
	tutLabel.Size = UDim2.new(1, 0, 0, isMobile and 28 or 36)
	tutLabel.BackgroundTransparency = 1
	tutLabel.Text = "현재 상태: 대기중"
	tutLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	tutLabel.TextSize = isMobile and 11 or 13
	tutLabel.Font = Enum.Font.Gotham
	tutLabel.TextWrapped = true
	tutLabel.Parent = frame

	local startTutBtn = Instance.new("TextButton")
	startTutBtn.Size = UDim2.new(1, 0, 0, isMobile and 28 or 32)
	startTutBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
	startTutBtn.Text = "튜토리얼 강제 시작"
	startTutBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	startTutBtn.TextSize = isMobile and 12 or 13
	startTutBtn.Font = Enum.Font.GothamBold
	startTutBtn.Parent = frame
	Instance.new("UICorner", startTutBtn).CornerRadius = UDim.new(0, 6)

	local qBtns = Instance.new("Frame")
	qBtns.Size = UDim2.new(1, 0, 0, isMobile and 28 or 32)
	qBtns.BackgroundTransparency = 1
	qBtns.Parent = frame
	local qGrid = Instance.new("UIListLayout", qBtns)
	qGrid.FillDirection = Enum.FillDirection.Horizontal
	qGrid.Padding = UDim.new(0, 8)

	local stepBox = Instance.new("TextBox")
	stepBox.Size = UDim2.new(0.3, -4, 1, 0)
	stepBox.BackgroundColor3 = Color3.fromRGB(38, 42, 48)
	stepBox.BorderSizePixel = 0
	stepBox.Text = "1"
	stepBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	stepBox.TextSize = isMobile and 13 or 14
	stepBox.Font = Enum.Font.Gotham
	stepBox.Parent = qBtns
	Instance.new("UICorner", stepBox).CornerRadius = UDim.new(0, 6)

	local setStepBtn = Instance.new("TextButton")
	setStepBtn.Size = UDim2.new(0.7, -4, 1, 0)
	setStepBtn.BackgroundColor3 = Color3.fromRGB(70, 85, 110)
	setStepBtn.Text = "단계 강제 이동"
	setStepBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	setStepBtn.TextSize = isMobile and 12 or 13
	setStepBtn.Font = Enum.Font.GothamBold
	setStepBtn.Parent = qBtns
	Instance.new("UICorner", setStepBtn).CornerRadius = UDim.new(0, 6)

	local resetTutBtn = Instance.new("TextButton")
	resetTutBtn.Size = UDim2.new(1, 0, 0, isMobile and 28 or 32)
	resetTutBtn.BackgroundColor3 = Color3.fromRGB(150, 70, 70)
	resetTutBtn.Text = "진행 정보 초기화"
	resetTutBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	resetTutBtn.TextSize = isMobile and 12 or 13
	resetTutBtn.Font = Enum.Font.GothamBold
	resetTutBtn.Parent = frame
	Instance.new("UICorner", resetTutBtn).CornerRadius = UDim.new(0, 6)

	-- 스크롤 크기 동적 업데이트 보강
	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		frame.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 20)
	end)
	frame.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 20)
	stepBox.Text = "1"
	stepBox.PlaceholderText = "Step"
	stepBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	stepBox.TextSize = 14
	stepBox.Font = Enum.Font.Gotham
	stepBox.Parent = qBtns
	Instance.new("UICorner", stepBox).CornerRadius = UDim.new(0, 6)

	local setStepBtn = Instance.new("TextButton")
	setStepBtn.Size = UDim2.new(0.7, -4, 1, 0)
	setStepBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 180)
	setStepBtn.Text = "단계 이동"
	setStepBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	setStepBtn.TextSize = 13
	setStepBtn.Font = Enum.Font.GothamBold
	setStepBtn.Parent = qBtns
	Instance.new("UICorner", setStepBtn).CornerRadius = UDim.new(0, 6)

	local resetTutBtn = Instance.new("TextButton")
	resetTutBtn.Size = UDim2.new(1, 0, 0, 32)
	resetTutBtn.BackgroundColor3 = Color3.fromRGB(180, 70, 70)
	resetTutBtn.Text = "진행 정보 초기화"
	resetTutBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	resetTutBtn.TextSize = 12
	resetTutBtn.Font = Enum.Font.GothamBold
	resetTutBtn.Parent = frame
	Instance.new("UICorner", resetTutBtn).CornerRadius = UDim.new(0, 6)

	local function refreshTutorialStatus()
		local ok, result = NetClient.Request("Tutorial.GetStatus.Request", {})
		if ok and result and result.data then
			local data = result.data
			tutLabel.Text = string.format("단계: %d / %d (%s)", 
				data.stepIndex or 0, data.totalSteps or 0, 
				data.completed and "완료" or (data.stepIndex > 0 and "진행중" or "시작안함"))
		end
	end

	startTutBtn.MouseButton1Click:Connect(function()
		local ok, result = NetClient.Request("Tutorial.Start.Request", {})
		if ok then
			UIManager.notify("튜토리얼이 시작되었습니다.", Color3.fromRGB(100, 255, 150))
			refreshTutorialStatus()
		else
			UIManager.notify("시작 실패", Color3.fromRGB(255, 100, 100))
		end
	end)

	setStepBtn.MouseButton1Click:Connect(function()
		local step = tonumber(stepBox.Text)
		if not step then return end
		local ok, result = NetClient.Request("Tutorial.Admin.SetStep.Request", { stepIndex = step })
		if ok then
			UIManager.notify("튜토리얼 단계가 " .. step .. "으로 설정되었습니다.", Color3.fromRGB(100, 200, 255))
			refreshTutorialStatus()
		else
			UIManager.notify("단계 설정 실패", Color3.fromRGB(255, 100, 100))
		end
	end)

	resetTutBtn.MouseButton1Click:Connect(function()
		local ok, result = NetClient.Request("Tutorial.Admin.Reset.Request", {})
		if ok then
			UIManager.notify("튜토리얼 진행 정보가 초기화되었습니다.", Color3.fromRGB(255, 150, 100))
			refreshTutorialStatus()
		else
			UIManager.notify("리셋 실패", Color3.fromRGB(255, 100, 100))
		end
	end)

	task.spawn(function()
		while gui.Parent do
			refreshTutorialStatus()
			task.wait(3)
		end
	end)
end

-- NetClient 초기화
local success = NetClient.Init()

if success then
	-- InputManager 초기화 (키 바인딩)
	InputManager.Init()
	
	-- WorldDropController 초기화 (이벤트 소비자)
	local WorldDropController = require(Controllers.WorldDropController)
	WorldDropController.Init()
	
	-- InventoryController 초기화 (이벤트 소비자)
	local InventoryController = require(Controllers.InventoryController)
	InventoryController.Init()
	
	-- TimeController 초기화 (이벤트 소비자)
	local TimeController = require(Controllers.TimeController)
	TimeController.Init()
	
	-- StorageController 초기화 (이벤트 소비자)
	local StorageController = require(Controllers.StorageController)
	StorageController.Init()
	
	-- BuildController 초기화 (이벤트 소비자)
	local BuildController = require(Controllers.BuildController)
	BuildController.Init()
	
	-- CraftController 초기화 (이벤트 소비자)
	local CraftController = require(Controllers.CraftController)
	CraftController.Init()
	
	-- FacilityController 초기화 (이벤트 소비자)
	local FacilityController = require(Controllers.FacilityController)
	FacilityController.Init()

	-- ShopController 초기화 (Phase 9)
	local ShopController = require(Controllers.ShopController)
	ShopController.Init()
	
	
	-- CombatController 초기화 (공격 시스템)
	local CombatController = require(Controllers.CombatController)
	CombatController.Init()
	
	-- InteractController 초기화 (채집/상호작용)
	local InteractController = require(Controllers.InteractController)
	InteractController.Init()
	InteractController.rebindDefaultKeys()
	
	-- MovementController 초기화 (스프린트/구르기)
	local MovementController = require(Controllers.MovementController)
	MovementController.Init()
	
	-- ResourceUIController 초기화 (노드 HP 바)
	local ResourceUIController = require(Controllers.ResourceUIController)
	ResourceUIController.Init()
	
	-- VirtualizationController 초기화 (성능 최적화: 가상화)
	local VirtualizationController = require(Controllers.VirtualizationController)
	VirtualizationController.Init()

	-- CreatureAnimationController 초기화 (공룡 애니메이션)
	local CreatureAnimationController = require(Controllers.CreatureAnimationController)
	CreatureAnimationController.Init()

	-- AttackIndicatorController 초기화 (크리처 텔레그래프 범위 표시)
	local AttackIndicatorController = require(Controllers.AttackIndicatorController)
	AttackIndicatorController.Init()
	
	-- [REMOVED] CreatureHealthUIController — 레거시 흰색 이름+초록 HP바 박스 제거
	-- 크리처 HP/Torpor 정보는 별도 UI로 대체됨
	
	-- [추가] HitFeedbackController 초기화 (피격 연출 및 물리 보정)
	local HitFeedbackController = require(Controllers.HitFeedbackController)
	HitFeedbackController.Init()
	
	-- [추가] DamageUIController 초기화 (부동 데미지 텍스트)
	local DamageUIController = require(Controllers.DamageUIController)
	DamageUIController.Init()

	-- SkillController 초기화 (스킬 트리 데이터)
	local SkillController = require(Controllers.SkillController)
	SkillController.Init()

	-- SkillEffectController 초기화 (스킬 VFX/사운드/애니메이션 연출)
	local SkillEffectController = require(Controllers.SkillEffectController)
	SkillEffectController.Init()

	-- BGMController 초기화 (전투 BGM)
	local BGMController = require(Controllers.BGMController)
	BGMController.Init()
	
	-- [추가] PromptUI 초기화 (커스텀 ProximityPrompt)
	local PromptUI = require(Client:WaitForChild("UI"):WaitForChild("PromptUI"))
	PromptUI.Init()
	
	-- UIManager 초기화 (UI 생성 - 컨트롤러들 초기화 후)
	UIManager.Init()
	createStudioAdminGoldPanel()

	-- BlockBuildController 초기화 (핫바 블럭 건축)
	local BlockBuildController = require(Controllers.BlockBuildController)
	BlockBuildController.Init()

	-- TutorialController 초기화 (첫 진입 튜토리얼)
	local TutorialController = require(Controllers.TutorialController)
	TutorialController.Init()

	-- TotemController 초기화 (거점 토템 유지비/범위 프리뷰)
	local TotemController = require(Controllers.TotemController)
	TotemController.Init()
	
	-- MovementController 스태미나 → UIManager 연동
	MovementController.onStaminaChanged(function(current, max)
		UIManager.updateStamina(current, max)
	end)
	
	-- 배고픔 → UIManager 연동 (Phase 11)
	NetClient.On("Hunger.Update", function(data)
		UIManager.updateHunger(data.current, data.max)
	end)

	-- [추가] 탑승 중 공룡별 목표 크기(주석 수치)로 줌아웃 제한 설정
	local CreatureData = require(ReplicatedStorage.Data.CreatureData)
	local function updateCameraZoomLimit()
		local mountedUID = player:GetAttribute("MountedPalUID")
		if mountedUID then
			-- 탑승 중: 현재 타고 있는 공룡의 ID로 데이터 조회
			local mountedPalId = player:GetAttribute("MountedCreatureId")
			if mountedPalId then
				for _, data in ipairs(CreatureData) do
					if data.id == mountedPalId then
						-- 주석에 적어놨던 cameraMaxZoom 수치를 적용
						player.CameraMaxZoomDistance = data.cameraMaxZoom or 45
						return
					end
				end
			end
			-- 데이터를 못 찾을 경우의 기본 확장값
			player.CameraMaxZoomDistance = 60
		else
			-- 하차 시: 기본 월드 줌아웃(45)으로 제한
			player.CameraMaxZoomDistance = Balance.CAM_MAX_ZOOM or 45
		end
	end

	-- 탑승/하차 시점 감지
	player:GetAttributeChangedSignal("MountedPalUID"):Connect(updateCameraZoomLimit)
	player:GetAttributeChangedSignal("MountedCreatureId"):Connect(updateCameraZoomLimit)
	updateCameraZoomLimit()

	
	-- 키 바인딩 설정
	-- [Key Bindings] Tab = 인벤토리, C = 건축, E = 장비창, P = 도감, B = 귀환
	InputManager.bindKey(Enum.KeyCode.Tab, "ToggleInventory_Tab", function() UIManager.toggleInventory() end)
	InputManager.bindKey(Enum.KeyCode.C, "ToggleBuilding", function() UIManager.toggleBuild() end)
	InputManager.bindKey(Enum.KeyCode.E, "ToggleEquipment", function() UIManager.toggleEquipment() end)

	InputManager.bindKey(Enum.KeyCode.K, "ToggleSkillTree", function() UIManager.toggleSkillTree() end)

	-- [Active Skills] Q / F / V = 액티브 스킬 슬롯 1/2/3
	local ActiveSkillBarUI = require(Client:WaitForChild("UI"):WaitForChild("ActiveSkillBarUI"))
	InputManager.bindKey(Enum.KeyCode.Q, "ActiveSkill1", function() ActiveSkillBarUI.UseSlot(1) end)
	InputManager.bindKey(Enum.KeyCode.F, "ActiveSkill2", function() ActiveSkillBarUI.UseSlot(2) end)
	InputManager.bindKey(Enum.KeyCode.V, "ActiveSkill3", function() ActiveSkillBarUI.UseSlot(3) end)

	-- B = 귀환 (최근 취침 장소로 순간이동, 진행도 바 + 피격/이동 취소)
	local recallCasting = false -- 시전 중 여부
	local recallCancelled = false
	local recallCooldownEnd = 0 -- os.clock 기준 쿨다운 종료 시각

	-- 쿨다운 타이머 UI (HUD 위에 표시)
	local function showRecallCooldownTimer(cooldownSec)
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		local playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return end

		-- 기존 타이머 제거
		local old = playerGui:FindFirstChild("RecallCooldownUI")
		if old then old:Destroy() end

		local cdGui = Instance.new("ScreenGui")
		cdGui.Name = "RecallCooldownUI"
		cdGui.ResetOnSpawn = true
		cdGui.DisplayOrder = 90
		cdGui.Parent = playerGui

		local cdFrame = Instance.new("Frame")
		cdFrame.AnchorPoint = Vector2.new(0.5, 1)
		cdFrame.Position = UDim2.new(0.5, 0, 0.82, 0)
		cdFrame.Size = UDim2.new(0, 160, 0, 36)
		cdFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		cdFrame.BackgroundTransparency = 0.4
		cdFrame.BorderSizePixel = 0
		cdFrame.Parent = cdGui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = cdFrame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(80, 80, 100)
		stroke.Thickness = 1
		stroke.Parent = cdFrame

		local cdLabel = Instance.new("TextLabel")
		cdLabel.Size = UDim2.new(1, 0, 1, 0)
		cdLabel.BackgroundTransparency = 1
		cdLabel.Text = string.format("귀환 [B] %ds", cooldownSec)
		cdLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
		cdLabel.TextSize = 14
		cdLabel.Font = Enum.Font.GothamMedium
		cdLabel.Parent = cdFrame

		task.spawn(function()
			while cdGui.Parent do
				local remain = math.ceil(recallCooldownEnd - os.clock())
				if remain <= 0 then
					cdLabel.Text = "귀환 [B] 준비 완료"
					cdLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
					task.wait(1.5)
					if cdGui.Parent then cdGui:Destroy() end
					return
				end
				cdLabel.Text = string.format("귀환 [B] %ds", remain)
				task.wait(0.5)
			end
		end)
	end

	InputManager.bindKey(Enum.KeyCode.B, "RecallTeleport", function()
		-- 쿨다운 중이면 남은 시간 표시
		if recallCooldownEnd > os.clock() then
			local remain = math.ceil(recallCooldownEnd - os.clock())
			UIManager.sideNotify(string.format("귀환 쿨다운: %d초 남음", remain), Color3.fromRGB(255, 200, 80))
			return
		end
		if recallCasting then return end
		if InputManager.isUIOpen() then return end

		recallCasting = true
		recallCancelled = false

		local Players = game:GetService("Players")
		local Balance = require(game:GetService("ReplicatedStorage").Shared.Config.Balance)
		local castTime = Balance.RECALL_CAST_TIME or 5
		local player = Players.LocalPlayer
		local character = player.Character
		local playerGui = player:FindFirstChild("PlayerGui")

		if not character or not character:FindFirstChild("HumanoidRootPart") then
			recallDebounce = false
			return
		end

		-- 귀환 진행도 바 UI 생성
		local recallGui = Instance.new("ScreenGui")
		recallGui.Name = "RecallCastUI"
		recallGui.ResetOnSpawn = true
		recallGui.DisplayOrder = 100
		recallGui.Parent = playerGui

		local bg = Instance.new("Frame")
		bg.Name = "RecallBG"
		bg.AnchorPoint = Vector2.new(0.5, 0.5)
		bg.Position = UDim2.new(0.5, 0, 0.75, 0)
		bg.Size = UDim2.new(0, 300, 0, 60)
		bg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		bg.BackgroundTransparency = 0.3
		bg.BorderSizePixel = 0
		bg.Parent = recallGui
		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 8)
		bgCorner.Parent = bg
		local bgStroke = Instance.new("UIStroke")
		bgStroke.Color = Color3.fromRGB(100, 180, 255)
		bgStroke.Thickness = 1.5
		bgStroke.Parent = bg

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0, 24)
		titleLbl.Position = UDim2.new(0, 0, 0, 4)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Text = "귀환 시전 중..."
		titleLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
		titleLbl.TextSize = 16
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.Parent = bg

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(0.85, 0, 0, 14)
		barBg.Position = UDim2.new(0.075, 0, 0, 34)
		barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		barBg.BorderSizePixel = 0
		barBg.Parent = bg
		local barBgCorner = Instance.new("UICorner")
		barBgCorner.CornerRadius = UDim.new(0, 4)
		barBgCorner.Parent = barBg

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		local barFillCorner = Instance.new("UICorner")
		barFillCorner.CornerRadius = UDim.new(0, 4)
		barFillCorner.Parent = barFill

		local pctLbl = Instance.new("TextLabel")
		pctLbl.Size = UDim2.new(1, 0, 0, 16)
		pctLbl.Position = UDim2.new(0, 0, 0, 42)
		pctLbl.BackgroundTransparency = 1
		pctLbl.Text = "0%"
		pctLbl.TextColor3 = Color3.fromRGB(200, 220, 240)
		pctLbl.TextSize = 12
		pctLbl.Font = Enum.Font.GothamMedium
		pctLbl.Parent = bg

		-- Highlight 이펙트
		local highlight = Instance.new("Highlight")
		highlight.Name = "RecallGlow"
		highlight.FillColor = Color3.fromRGB(180, 220, 255)
		highlight.FillTransparency = 0.4
		highlight.OutlineColor = Color3.fromRGB(100, 180, 255)
		highlight.OutlineTransparency = 0
		highlight.Adornee = character
		highlight.Parent = character

		-- 피격 감지 (HealthChanged)
		local humanoid = character:FindFirstChild("Humanoid")
		local prevHealth = humanoid and humanoid.Health or 100
		local healthConn = nil
		if humanoid then
			healthConn = humanoid.HealthChanged:Connect(function(newHealth)
				if newHealth < prevHealth then
					recallCancelled = true
				end
				prevHealth = newHealth
			end)
		end

		-- 시전 루프
		local startPos = character.HumanoidRootPart.Position
		local elapsed = 0
		while elapsed < castTime do
			task.wait(0.1)
			elapsed += 0.1

			-- 이동 체크
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then recallCancelled = true end
			if hrp and (hrp.Position - startPos).Magnitude > 3 then recallCancelled = true end

			if recallCancelled then break end

			-- 진행도 업데이트
			local pct = math.clamp(elapsed / castTime, 0, 1)
			barFill.Size = UDim2.new(pct, 0, 1, 0)
			pctLbl.Text = string.format("%d%%", math.floor(pct * 100))
			highlight.FillTransparency = math.max(0, 0.4 - pct * 0.4)

			-- 색상 그라데이션 (파란색 → 밝은 흰색)
			local r = math.floor(100 + pct * 155)
			local g = math.floor(180 + pct * 60)
			local b = 255
			barFill.BackgroundColor3 = Color3.fromRGB(r, g, b)
		end

		if healthConn then healthConn:Disconnect() end

		local function cleanup()
			if highlight and highlight.Parent then highlight:Destroy() end
			if recallGui and recallGui.Parent then recallGui:Destroy() end
		end

		if recallCancelled then
			cleanup()
			UIManager.sideNotify("귀환이 취소되었습니다.", Color3.fromRGB(255, 100, 100))
			task.delay(2, function() recallCasting = false end)
			return
		end

		-- 100% 완료 → 서버 요청
		barFill.Size = UDim2.new(1, 0, 1, 0)
		pctLbl.Text = "100%"
		titleLbl.Text = "귀환!"
		titleLbl.TextColor3 = Color3.fromRGB(100, 255, 150)

		local ok, data = NetClient.Request("Recall.Request", {})
		cleanup()

		if ok then
			UIManager.sideNotify("귀환 완료!", Color3.fromRGB(100, 255, 150))
			local cdTime = Balance.RECALL_COOLDOWN or 60
			recallCooldownEnd = os.clock() + cdTime
			recallCasting = false
			showRecallCooldownTimer(cdTime)
		else
			local errMsg = "귀환 실패"
			if data == "NO_SLEEP_LOCATION" then
				errMsg = "취침한 장소가 없습니다. 침대에서 수면 후 사용하세요."
			elseif data == "PLAYER_DEAD" then
				errMsg = "사망 상태에서는 귀환할 수 없습니다."
			elseif data == "COOLDOWN" then
				errMsg = "귀환 쿨다운 중입니다."
			end
			UIManager.sideNotify(errMsg, Color3.fromRGB(255, 100, 100))
			task.delay(2, function() recallCasting = false end)
		end
	end)
	
	-- R, T, Escape 키는 InteractController.rebindDefaultKeys()에서 통합 관리됨
end

print("[ClientInit] Client initialized")
