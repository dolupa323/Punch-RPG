local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local HUDUI = {}
local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local tutorialWantedVisible = false
local tutorialReady = false
local tutorialPulseTween = nil

-- [에셋 참조] 하드코딩 방지를 위한 폴더 경로
local StatusIcons = nil

HUDUI.Refs = {
	harvestPct = nil,
	harvestName = nil,
	interactPrompt = nil,
	tutorialFrame = nil,
	tutorialTitle = nil,
	tutorialStep = nil,
	tutorialProgress = nil,
	tutorialReward = nil,
	tutorialCompleteBtn = nil,
	tutorialClickArea = nil,
}

function HUDUI.Init(parent, UIManager, InputManager, isMobile)
	-- [수정] 차단성 WaitForChild를 Init 내부로 이동하고 타임아웃 추가
	task.spawn(function()
		local Assets = ReplicatedStorage:WaitForChild("Assets", 5)
		if Assets then
			StatusIcons = Assets:WaitForChild("StatusIcons", 3)
		end
	end)

	local isSmall = isMobile 
	
	-- [Top Left Area] - HP, Stamina, Status Effects
	local topLeftFrame = Utils.mkFrame({
		name = "TopLeftHUD",
		size = UDim2.new(0, isSmall and 260 or 240, 0, 110), -- 110으로 확장
		pos = UDim2.new(0, isSmall and 60 or 180, 0, isSmall and 40 or 20), -- 로블록스 기본 UI 회피 (우측 이동)
		bgT = 1,
		parent = parent
	})
	HUDUI.Refs.statusPanel = topLeftFrame

	local statusList = Instance.new("UIListLayout")
	statusList.Padding = UDim.new(0, 6) -- 간격 약간 확대
	statusList.SortOrder = Enum.SortOrder.LayoutOrder
	statusList.Parent = topLeftFrame

	-- HP Bar (High-Contrast Red)
	HUDUI.Refs.healthBar = Utils.mkBar({
		name = "HP",
		size = UDim2.new(1, 0, 0, 20),
		fillC = C.HP,
		r = 3,
		parent = topLeftFrame
	})
	HUDUI.Refs.healthBar.container.LayoutOrder = 1
	HUDUI.Refs.healthBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.healthBar.label.Position = UDim2.new(0, 8, 0.5, 0)
	HUDUI.Refs.healthBar.label.AnchorPoint = Vector2.new(0, 0.5)
	HUDUI.Refs.healthBar.label.TextColor3 = C.WHITE
	HUDUI.Refs.healthBar.label.Font = F.NUM
	HUDUI.Refs.healthBar.label.TextSize = 13

	-- Stamina Bar (Vibrant Yellow - User Request)
	HUDUI.Refs.staminaBar = Utils.mkBar({
		name = "STA",
		size = UDim2.new(1, 0, 0, 18), 
		fillC = C.STA, 
		r = 3,
		parent = topLeftFrame
	})
	HUDUI.Refs.staminaBar.container.LayoutOrder = 2
	HUDUI.Refs.staminaBar.label.TextXAlignment = Enum.TextXAlignment.Left
	HUDUI.Refs.staminaBar.label.Position = UDim2.new(0, 8, 0.5, 0)
	HUDUI.Refs.staminaBar.label.AnchorPoint = Vector2.new(0, 0.5)
	HUDUI.Refs.staminaBar.label.TextColor3 = C.WHITE
	HUDUI.Refs.staminaBar.label.Font = F.NUM
	HUDUI.Refs.staminaBar.label.TextSize = 12

	-- Hunger Bar (Vibrant Orange)
	HUDUI.Refs.hungerBar = Utils.mkBar({
		name = "HUNGER",
		size = UDim2.new(1, -20, 0, 6), -- 더 얇고 깔끔하게
		fillC = C.HUNGER, 
		r = 2,
		parent = topLeftFrame
	})
	HUDUI.Refs.hungerBar.container.LayoutOrder = 3
	HUDUI.Refs.hungerBar.label.Visible = false -- 너무 얇아서 텍스트 숨김 (툴팁으로 확인 가능)

	-- Status Effect Icons Container (LayoutOrder 4)
	local effectList = Utils.mkFrame({name="EffectList", size=UDim2.new(1,0,0,30), bgT=1, parent=topLeftFrame})
	effectList.LayoutOrder = 4
	local eLayout = Instance.new("UIListLayout"); eLayout.FillDirection=Enum.FillDirection.Horizontal; eLayout.Padding=UDim.new(0,5); eLayout.Parent=effectList
	HUDUI.Refs.effectList = effectList
	
	HUDUI.Refs.statPointAlert = Utils.mkLabel({
		text = "▲ 레벨업 가능",
		size = UDim2.new(0, 120, 1, 0),
		ts = 12,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		vis = false,
		parent = effectList
	})

	-- Tutorial quest: fixed HUD panel (non-toast)
	local tutorialFrame = Utils.mkFrame({
		name = "TutorialPanel",
		size = UDim2.new(0, isSmall and 320 or 290, 0, isSmall and 122 or 106),
		pos = UDim2.new(1, -20, 0, isSmall and 182 or 174),
		anchor = Vector2.new(1, 0),
		bg = C.BG_PANEL,
		bgT = 0.62,
		r = 8,
		stroke = 1.5,
		strokeC = C.BORDER,
		vis = false,
		parent = parent,
	})
	HUDUI.Refs.tutorialFrame = tutorialFrame

	HUDUI.Refs.tutorialTitle = Utils.mkLabel({
		name = "TutorialTitle",
		text = "튜토리얼 퀘스트",
		size = UDim2.new(1, -16, 0, 24),
		pos = UDim2.new(0, 8, 0, 6),
		ax = Enum.TextXAlignment.Left,
		font = F.TITLE,
		ts = 15,
		color = C.GOLD,
		parent = tutorialFrame,
	})

	HUDUI.Refs.tutorialStep = Utils.mkLabel({
		name = "TutorialStep",
		text = "",
		size = UDim2.new(1, -16, 0, 42),
		pos = UDim2.new(0, 8, 0, 30),
		ax = Enum.TextXAlignment.Left,
		ay = Enum.TextYAlignment.Top,
		wrap = true,
		ts = 14,
		color = C.WHITE,
		parent = tutorialFrame,
	})

	HUDUI.Refs.tutorialProgress = Utils.mkLabel({
		name = "TutorialProgress",
		text = "",
		size = UDim2.new(1, -100, 0, 20),
		pos = UDim2.new(0, 8, 1, -24),
		ax = Enum.TextXAlignment.Left,
		ts = 13,
		color = C.GOLD,
		parent = tutorialFrame,
	})

	HUDUI.Refs.tutorialReward = Utils.mkLabel({
		name = "TutorialReward",
		text = "",
		size = UDim2.new(1, -16, 0, 18),
		pos = UDim2.new(0, 8, 1, -44),
		ax = Enum.TextXAlignment.Left,
		ts = 12,
		color = C.GREEN,
		parent = tutorialFrame,
	})

	local tutorialCompleteBtn = Utils.mkBtn({
		name = "TutorialCompleteBtn",
		text = "완료",
		size = UDim2.new(0, 76, 0, 24),
		pos = UDim2.new(1, -8, 1, -24),
		anchor = Vector2.new(1, 1),
		bg = C.BTN,
		bgT = 0.25,
		ts = 13,
		font = F.TITLE,
		color = C.WHITE,
		fn = function()
			if UIManager and UIManager.requestTutorialStepComplete then
				UIManager.requestTutorialStepComplete()
			end
		end,
		parent = tutorialFrame,
	})
	HUDUI.Refs.tutorialCompleteBtn = tutorialCompleteBtn

	local tutorialClickArea = Instance.new("TextButton")
	tutorialClickArea.Name = "TutorialClickArea"
	tutorialClickArea.Size = UDim2.new(1, 0, 1, 0)
	tutorialClickArea.Position = UDim2.new(0, 0, 0, 0)
	tutorialClickArea.BackgroundTransparency = 1
	tutorialClickArea.Text = ""
	tutorialClickArea.AutoButtonColor = false
	tutorialClickArea.ZIndex = 40
	tutorialClickArea.Parent = tutorialFrame
	tutorialClickArea.MouseButton1Click:Connect(function()
		if tutorialReady and UIManager and UIManager.requestTutorialStepComplete then
			UIManager.requestTutorialStepComplete()
		end
	end)
	HUDUI.Refs.tutorialClickArea = tutorialClickArea

	-- Keep tutorial panel/text responsive with actual viewport size.
	local function updateTutorialLayout()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local vp = camera.ViewportSize
		local panelWidth = math.clamp(math.floor(vp.X * (isSmall and 0.42 or 0.24)), isSmall and 300 or 270, isSmall and 430 or 390)
		local panelHeight = math.clamp(math.floor(vp.Y * (isSmall and 0.17 or 0.15)), isSmall and 112 or 98, isSmall and 170 or 150)

		tutorialFrame.Size = UDim2.new(0, panelWidth, 0, panelHeight)
		tutorialFrame.Position = UDim2.new(1, -20, 0, isSmall and 188 or 178)

		local titleSize = math.clamp(math.floor(panelHeight * 0.14), 14, 22)
		local bodySize = math.clamp(math.floor(panelHeight * 0.13), 13, 20)
		local progressSize = math.clamp(math.floor(panelHeight * 0.12), 12, 18)

		HUDUI.Refs.tutorialTitle.TextSize = titleSize
		HUDUI.Refs.tutorialStep.TextSize = bodySize
		HUDUI.Refs.tutorialProgress.TextSize = progressSize

		HUDUI.Refs.tutorialTitle.Size = UDim2.new(1, -16, 0, math.floor(panelHeight * 0.26))
		HUDUI.Refs.tutorialTitle.Position = UDim2.new(0, 8, 0, 6)

		HUDUI.Refs.tutorialStep.Size = UDim2.new(1, -16, 0, math.floor(panelHeight * 0.40))
		HUDUI.Refs.tutorialStep.Position = UDim2.new(0, 8, 0, math.floor(panelHeight * 0.28))

		HUDUI.Refs.tutorialReward.Size = UDim2.new(1, -16, 0, math.floor(panelHeight * 0.18))
		HUDUI.Refs.tutorialReward.Position = UDim2.new(0, 8, 1, -math.floor(panelHeight * 0.44))
		HUDUI.Refs.tutorialReward.TextSize = math.clamp(math.floor(panelHeight * 0.11), 11, 16)

		local btnWidth = math.clamp(math.floor(panelWidth * 0.24), 72, 110)
		local btnHeight = math.clamp(math.floor(panelHeight * 0.24), 22, 34)
		HUDUI.Refs.tutorialCompleteBtn.Size = UDim2.new(0, btnWidth, 0, btnHeight)
		HUDUI.Refs.tutorialCompleteBtn.Position = UDim2.new(1, -8, 1, -8)
		HUDUI.Refs.tutorialCompleteBtn.TextSize = math.clamp(math.floor(panelHeight * 0.12), 12, 18)

		HUDUI.Refs.tutorialProgress.Size = UDim2.new(1, -(btnWidth + 22), 0, math.floor(panelHeight * 0.2))
		HUDUI.Refs.tutorialProgress.Position = UDim2.new(0, 8, 1, -math.floor(panelHeight * 0.24))
		HUDUI.Refs.tutorialClickArea.ZIndex = HUDUI.Refs.tutorialCompleteBtn.ZIndex + 1
	end

	updateTutorialLayout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateTutorialLayout)
	end

	-- [Bottom Right Area] - Action / Hexagon Buttons
	local actionArea = Utils.mkFrame({
		name = "ActionArea",
		size = UDim2.new(0, isSmall and 300 or 240, 0, isSmall and 150 or 120),
		pos = UDim2.new(1, -20, 1, -20),
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = parent
	})
	
	-- Hexagonal Buttons Data: Attack, Dodge, Jump, Sprint (Action Cluster)
	local hScale = isSmall and 1.25 or 1.0
	local hexBtns = {
		{id="Attack", icon="rbxassetid://10452331908", pos=UDim2.new(1, -70 * hScale, 0.5, 30), size=95 * hScale},
		{id="Dodge", icon="rbxassetid://6034346917", pos=UDim2.new(1, -15 * hScale, 0.5, 45), size=65 * hScale}, -- 구르기 (오른쪽 아래)
		{id="Jump", icon="rbxassetid://6034335017", pos=UDim2.new(1, -135 * hScale, 0.5, 95), size=65 * hScale}, -- 점프 (왼쪽 아래)
		{id="Sprint", icon="rbxassetid://6034440026", pos=UDim2.new(1, -75 * hScale, 0.5, 115), size=60 * hScale}, -- 달리기 (중앙 아래)
	}
	
	-- Interact button separated (higher, above hotbar or near interaction area)
	local interactBtn = Utils.mkHexBtn({
		name = "Interact",
		size = UDim2.new(0, 75 * hScale, 0, 75 * hScale),
		pos = UDim2.new(1, -180 * hScale, 0.5, -20),
		anchor = Vector2.new(0.5, 0.5),
		stroke = true,
		parent = actionArea
	})
	local intIcon = Instance.new("ImageLabel")
	intIcon.Size = UDim2.new(0.55, 0, 0.55, 0); intIcon.Position = UDim2.new(0.5, 0, 0.5, 0); intIcon.AnchorPoint = Vector2.new(0.5, 0.5); intIcon.BackgroundTransparency = 1; intIcon.Image = "rbxassetid://6034805332"; intIcon.Parent = interactBtn
	HUDUI.Refs.hex_Interact = interactBtn
	
	for _, hb in ipairs(hexBtns) do
		local btn = Utils.mkHexBtn({
			name = hb.id,
			size = UDim2.new(0, hb.size, 0, hb.size),
			pos = hb.pos,
			anchor = Vector2.new(0.5, 0.5),
			stroke = true,
			parent = actionArea
		})
		local iconLbl = Instance.new("ImageLabel")
		iconLbl.Size = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconLbl.AnchorPoint = Vector2.new(0.5, 0.5)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Image = hb.icon
		iconLbl.ImageColor3 = Color3.new(1,1,1)
		iconLbl.Parent = btn
		HUDUI.Refs["hex_"..hb.id] = btn
	end

	-- [X] Redundant interact prompt removed (Using InteractUI instead)

	-- [Bottom Edge] - Experience Bar & Menu (Modern Minimalist)
	local bottomEdge = Utils.mkFrame({
		name = "BottomEdge",
		size = UDim2.new(1, 0, 0, isSmall and 50 or 40),
		pos = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		bg = Color3.new(0,0,0),
		bgT = 0.6,
		parent = parent
	})
	
	local xpBackground = Utils.mkFrame({
		name = "XPBG", 
		size = UDim2.new(1, 0, 0, 2), 
		pos = UDim2.new(0.5, 0, 0, 0), 
		anchor = Vector2.new(0.5, 0), 
		bgT = 0.5, 
		bg = C.BORDER_DIM,
		parent = bottomEdge
	})
	HUDUI.Refs.xpBar = Utils.mkFrame({name = "XPBar", size = UDim2.new(0, 0, 1, 0), bg = C.XP, bgT = 0, parent = xpBackground})

	local menuItems = Utils.mkFrame({name="MenuButtons", size=UDim2.new(0.7, 0, 1, 0), pos=UDim2.new(1, -20, 0, 0), anchor=Vector2.new(1, 0), bgT=1, parent=bottomEdge})
	local mList = Instance.new("UIListLayout"); mList.FillDirection=Enum.FillDirection.Horizontal; mList.VerticalAlignment=Enum.VerticalAlignment.Center; mList.HorizontalAlignment=Enum.HorizontalAlignment.Right; mList.Padding=UDim.new(0, isSmall and 6 or 12); mList.Parent=menuItems
	
	HUDUI.Refs.levelLabel = Utils.mkLabel({text="LV. 1 [ 0.0% ]", size=UDim2.new(0, 150, 0, 32), pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), ts=14, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=bottomEdge})
	
	HUDUI.Refs.bagBtn = Utils.mkBtn({text="[ INV: B ]", size=UDim2.new(0, isSmall and 75 or 100, 0, 32), bgT=1, ts=isSmall and 13 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleInventory() end, parent=menuItems})
	HUDUI.Refs.buildBtn = Utils.mkBtn({text="[ BUILD: C ]", size=UDim2.new(0, isSmall and 85 or 110, 0, 32), bgT=1, ts=isSmall and 13 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleBuild() end, parent=menuItems})
	HUDUI.Refs.equipBtn = Utils.mkBtn({text="[ CHAR: E ]", size=UDim2.new(0, isSmall and 80 or 105, 0, 32), bgT=1, ts=isSmall and 13 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleEquipment() end, parent=menuItems})
	HUDUI.Refs.collectionBtn = Utils.mkBtn({text="[ LOG: P ]", size=UDim2.new(0, isSmall and 75 or 100, 0, 32), bgT=1, ts=isSmall and 13 or 14, font=F.TITLE, color=C.WHITE, fn=function() UIManager.toggleCollection() end, parent=menuItems})

	-- [Hotbar] (Center Bottom)
	local hotbarSize = isSmall and 480 or 410
	local hotbarFrame = Utils.mkFrame({
		name = "Hotbar",
		size = UDim2.new(0, hotbarSize, 0, isSmall and 60 or 50),
		pos = UDim2.new(0.5, 0, 1, isSmall and -50 or -35),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = parent
	})
	HUDUI.Refs.hotbarSlots = {}
	local hList = Instance.new("UIListLayout")
	hList.FillDirection = Enum.FillDirection.Horizontal; hList.HorizontalAlignment = Enum.HorizontalAlignment.Center; hList.Padding = UDim.new(0, 8); hList.Parent = hotbarFrame

	for i=1, 8 do
		local slot = Utils.mkSlot({
			name = "Slot"..i,
			size = UDim2.new(0, isSmall and 55 or 48, 0, isSmall and 55 or 48),
			bg = C.BG_SLOT,
			bgT = 0.5, -- 가독성을 위해 투명도 낮춤
			stroke = 1.5,
			strokeC = C.BORDER,
			parent = hotbarFrame
		})
		
		-- Number indicator
		Utils.mkLabel({
			text = tostring(i),
			size = UDim2.new(0, 12, 0, 12),
			pos = UDim2.new(0, 2, 0, 2),
			ts = 10,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Left,
			ay = Enum.TextYAlignment.Top,
			st = 1,
			parent = slot.frame
		})
		
		HUDUI.Refs.hotbarSlots[i] = slot
	end

	-- Top Right: Minimap Placeholder (Not fully implemented, just visual)
	local minimap = Utils.mkFrame({
		name = "Minimap",
		size = UDim2.new(0, 120, 0, 120),
		pos = UDim2.new(1, -20, 0, 20),
		anchor = Vector2.new(1, 0),
		bgT = 0.5,
		r = "full",
		stroke = 2,
		strokeC = C.BORDER,
		parent = parent
	})
	HUDUI.Refs.minimap = minimap
	
	-- North Indicator
	local north = Utils.mkLabel({
		text = "N",
		size = UDim2.new(0, 20, 0, 20),
		pos = UDim2.new(0.5, 0, 0.1, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 14,
		bold = true,
		color = C.RED,
		parent = minimap
	})
	HUDUI.Refs.northIndicator = north
	
	local coordLabel = Utils.mkLabel({
		text = "X: 0  Z: 0",
		pos = UDim2.new(0.5, 0, 1, 10),
		anchor = Vector2.new(0.5, 0),
		size = UDim2.new(1, 0, 0, 20),
		ts = 12,
		color = C.WHITE,
		parent = minimap
	})
	HUDUI.Refs.coordLabel = coordLabel
	
	-- Action 버튼 클릭 연동 (모바일/클릭 지원)
	HUDUI.Refs.hex_Interact.MouseButton1Click:Connect(function() local IC = require(Controllers.InteractController); if IC.onInteractPress then IC.onInteractPress() end end)
	HUDUI.Refs.hex_Attack.MouseButton1Click:Connect(function() local CC = require(Controllers.CombatController); if CC.attack then CC.attack() end end)

	-- Dodge & Sprint & Jump (Mobile Bindings)
	HUDUI.Refs.hex_Dodge.MouseButton1Click:Connect(function() 
		local MC = require(Controllers.MovementController)
		if MC.performDodge then MC.performDodge() end -- Ensure function exists or use shared trigger
	end)
	
	HUDUI.Refs.hex_Jump.MouseButton1Click:Connect(function()
		local hum = player.Character and player.Character:FindFirstChild("Humanoid")
		if hum then hum.Jump = true end
	end)
	
	HUDUI.Refs.hex_Sprint.MouseButton1Down:Connect(function() 
		local MC = require(Controllers.MovementController)
		if MC.updateSprintState then MC.updateSprintState(true) end
	end)
	HUDUI.Refs.hex_Sprint.MouseButton1Up:Connect(function() 
		local MC = require(Controllers.MovementController)
		if MC.updateSprintState then MC.updateSprintState(false) end
	end)

	-- [UX] UI Toggle Key Bindings moved to ClientInit for consistency

	-- Harvest Setup
	HUDUI.Refs.harvestFrame = Utils.mkFrame({name="Harvest", size=UDim2.new(0, 300, 0, 60), pos=UDim2.new(0.4, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bgT=1, vis=false, parent=parent})
	local hBar = Utils.mkBar({size=UDim2.new(1, 0, 0, 6), pos=UDim2.new(0.5, 0, 0, 30), anchor=Vector2.new(0.5, 0), fillC=C.WHITE, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestBar = hBar.fill
	HUDUI.Refs.harvestName = Utils.mkLabel({text="채집 중...", size=UDim2.new(1, 0, 0, 25), ts=16, bold=true, rich=true, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestPct = Utils.mkLabel({text="0%", size=UDim2.new(1, 0, 0, 20), pos=UDim2.new(0.5, 0, 0, 45), anchor=Vector2.new(0.5, 0), ts=14, color=C.GOLD, parent=HUDUI.Refs.harvestFrame})

	-- =============================================
	-- HUD 바 툴팁 (마우스 호버 시 설명창)
	-- =============================================
	local tooltip = Instance.new("Frame")
	tooltip.Name = "HUDTooltip"
	tooltip.Size = UDim2.new(0, 210, 0, 80)
	tooltip.BackgroundColor3 = C.BG_PANEL
	tooltip.BackgroundTransparency = 0.05
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 9500
	tooltip.Visible = false
	tooltip.Parent = parent

	local tipCorner = Instance.new("UICorner")
	tipCorner.CornerRadius = UDim.new(0, 10)
	tipCorner.Parent = tooltip

	local tipStroke = Instance.new("UIStroke")
	tipStroke.Color = C.BORDER
	tipStroke.Thickness = 2
	tipStroke.Transparency = 0.2
	tipStroke.Parent = tooltip

	local tipTitle = Instance.new("TextLabel")
	tipTitle.Name = "Title"
	tipTitle.Size = UDim2.new(1, -20, 0, 30)
	tipTitle.Position = UDim2.new(0, 10, 0, 5)
	tipTitle.BackgroundTransparency = 1
	tipTitle.TextColor3 = C.INK
	tipTitle.TextSize = 18
	tipTitle.Font = F.TITLE
	tipTitle.TextXAlignment = Enum.TextXAlignment.Left
	tipTitle.ZIndex = 9501
	tipTitle.Parent = tooltip

	local tipBody = Instance.new("TextLabel")
	tipBody.Name = "Body"
	tipBody.Size = UDim2.new(1, -20, 1, -40)
	tipBody.Position = UDim2.new(0, 10, 0, 35)
	tipBody.BackgroundTransparency = 1
	tipBody.TextColor3 = C.INK
	tipBody.TextSize = 15
	tipBody.Font = F.NORMAL
	tipBody.TextXAlignment = Enum.TextXAlignment.Left
	tipBody.TextYAlignment = Enum.TextYAlignment.Top
	tipBody.TextWrapped = true
	tipBody.ZIndex = 9501
	tipBody.Parent = tooltip

	HUDUI.Refs.tooltip = tooltip
	HUDUI.Refs.tipTitle = tipTitle
	HUDUI.Refs.tipBody = tipBody

	-- 툴팁 데이터
	local barData = {
		[HUDUI.Refs.healthBar.container] = {
			title = "❤️ 생명력 (Health)",
			body  = "캐릭터의 생존력을 나타냅니다.\n0이 되면 사망하여 리스폰됩니다.\n음식이나 치료제로 회복할 수 있습니다.",
		},
		[HUDUI.Refs.staminaBar.container] = {
			title = "⚡ 기력 (Stamina)",
			body  = "구르기, 달리기, 수영 등 활동 시 소모됩니다.\n소모된 기력은 가만히 있으면 자동으로 회복됩니다.",
		},
		[HUDUI.Refs.hungerBar.container] = {
			title = "🍖 허기 (Hunger)",
			body  = "시간이 지남에 따라 점차 감소합니다.\n배고픔이 0이 되면 체력이 서서히 감소합니다.\n다양한 음식을 먹어 채워야 합니다.",
		},
	}

	local UserInputService = game:GetService("UserInputService")
	
	for container, data in pairs(barData) do
		if not container then continue end
		
		-- 투명 버튼을 위에 덮어서 호버 감지 (안정적 렌더링)
		local overlay = Instance.new("TextButton")
		overlay.Name = "TooltipTrigger"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundTransparency = 1
		overlay.Text = ""
		overlay.ZIndex = container.ZIndex + 100
		overlay.Parent = container

		overlay.MouseEnter:Connect(function()
			HUDUI.Refs.tipTitle.Text = UILocalizer.Localize(data.title)
			HUDUI.Refs.tipBody.Text = UILocalizer.Localize(data.body)
			-- 텍스트 길이에 맞춰 높이 조정
			local lines = select(2, data.body:gsub("\n", "\n")) + 1
			HUDUI.Refs.tooltip.Size = UDim2.new(0, 210, 0, 50 + lines * 16)
			HUDUI.Refs.tooltip.Visible = true
		end)

		overlay.MouseLeave:Connect(function()
			HUDUI.Refs.tooltip.Visible = false
		end)
	end

	-- 툴팁이 마우스를 따라다니게 처리
	RunService.RenderStepped:Connect(function()
		if tooltip.Visible then
			local mousePos = UserInputService:GetMouseLocation()
			local uiScale = parent:FindFirstChildOfClass("UIScale")
			local scale = uiScale and uiScale.Scale or 1
			
			-- 마우스 오른쪽 아래에 배치
			tooltip.Position = UDim2.new(0, mousePos.X / scale + 15, 0, (mousePos.Y - 36) / scale + 15)
		end
	end)
end

local function _buildRewardText(reward)
	if type(reward) ~= "table" then
		return ""
	end
	local chunks = {}
	if (reward.xp or 0) > 0 then
		table.insert(chunks, string.format("XP +%d", reward.xp))
	end
	if (reward.gold or 0) > 0 then
		table.insert(chunks, string.format("골드 +%d", reward.gold))
	end
	if type(reward.items) == "table" then
		for _, item in ipairs(reward.items) do
			if type(item) == "table" and item.itemId and item.count then
				table.insert(chunks, string.format("%s x%d", tostring(item.itemId), tonumber(item.count) or 1))
			end
		end
	end
	return table.concat(chunks, ", ")
end

local function _setReadyPulse(ready)
	tutorialReady = ready == true
	if tutorialPulseTween then
		tutorialPulseTween:Cancel()
		tutorialPulseTween = nil
	end

	if not HUDUI.Refs.tutorialFrame then
		return
	end

	local stroke = HUDUI.Refs.tutorialFrame:FindFirstChildOfClass("UIStroke")
	if ready then
		if stroke then
			stroke.Color = C.GOLD
			stroke.Transparency = 0.15
		end
		tutorialPulseTween = TweenService:Create(
			HUDUI.Refs.tutorialFrame,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.46 }
		)
		tutorialPulseTween:Play()
	else
		HUDUI.Refs.tutorialFrame.BackgroundTransparency = 0.62
		if stroke then
			stroke.Color = C.BORDER
			stroke.Transparency = 0.4
		end
	end
end

function HUDUI.SetVisible(visible)
	if HUDUI.Refs.statusPanel then HUDUI.Refs.statusPanel.Visible = visible end
	if HUDUI.Refs.xpBar then HUDUI.Refs.xpBar.Parent.Parent.Visible = visible end
	if HUDUI.Refs.hex_Attack then HUDUI.Refs.hex_Attack.Parent.Visible = visible end
	if HUDUI.Refs.tutorialFrame then
		HUDUI.Refs.tutorialFrame.Visible = visible and tutorialWantedVisible
	end
end

local function _sortedKeys(map)
	local keys = {}
	for key in pairs(map or {}) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function _buildProgressText(status)
	if type(status) ~= "table" then
		return ""
	end

	local progress = type(status.progress) == "table" and status.progress or {}
	if status.stepKind == "MULTI_ITEM" and type(status.needs) == "table" then
		local chunks = {}
		for _, itemId in ipairs(_sortedKeys(status.needs)) do
			local needCount = status.needs[itemId] or 0
			local nowCount = progress[itemId] or 0
			table.insert(chunks, string.format("%s %d/%d", tostring(itemId), nowCount, needCount))
		end
		return table.concat(chunks, "  |  ")
	end

	if status.stepKind == "ITEM_ANY" then
		local nowCount = progress.count or 0
		local needCount = status.stepCount or 1
		return string.format("진행도: %d / %d", nowCount, needCount)
	end

	return string.format("단계: %d / %d", status.stepIndex or 0, status.totalSteps or 0)
end

function HUDUI.SetTutorialVisible(visible)
	tutorialWantedVisible = visible == true
	if HUDUI.Refs.tutorialFrame then
		local hudVisible = (HUDUI.Refs.statusPanel == nil) or HUDUI.Refs.statusPanel.Visible
		HUDUI.Refs.tutorialFrame.Visible = tutorialWantedVisible and hudVisible
	end
end

function HUDUI.UpdateTutorialStatus(status)
	if type(status) ~= "table" or not HUDUI.Refs.tutorialFrame then
		return
	end

	if status.completed then
		HUDUI.Refs.tutorialTitle.Text = "튜토리얼 완료"
		HUDUI.Refs.tutorialStep.Text = "기본 생존 가이드를 모두 마쳤습니다."
		local completedReward = _buildRewardText(status.reward or status.rewardPreview)
		HUDUI.Refs.tutorialProgress.Text = "보상이 지급되었습니다"
		HUDUI.Refs.tutorialReward.Text = completedReward ~= "" and ("획득: " .. completedReward) or "획득: -"
		if HUDUI.Refs.tutorialCompleteBtn then
			HUDUI.Refs.tutorialCompleteBtn.Visible = false
		end
		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.Active = false
		end
		_setReadyPulse(false)
		HUDUI.SetTutorialVisible(true)
		return
	end

	if not status.active then
		HUDUI.SetTutorialVisible(false)
		return
	end

	HUDUI.Refs.tutorialTitle.Text = string.format("튜토리얼 퀘스트 (%d/%d)", status.stepIndex or 0, status.totalSteps or 0)
	HUDUI.Refs.tutorialStep.Text = status.currentStepText or "다음 튜토리얼 목표 진행 중"
	HUDUI.Refs.tutorialProgress.Text = _buildProgressText(status)
	local previewReward = _buildRewardText(status.rewardPreview)
	HUDUI.Refs.tutorialReward.Text = previewReward ~= "" and ("완료 보상: " .. previewReward) or "완료 보상: -"

	if HUDUI.Refs.tutorialCompleteBtn then
		local ready = status.stepReady == true
		HUDUI.Refs.tutorialCompleteBtn.Visible = true
		HUDUI.Refs.tutorialCompleteBtn.AutoButtonColor = ready
		HUDUI.Refs.tutorialCompleteBtn.Active = ready
		HUDUI.Refs.tutorialCompleteBtn.BackgroundTransparency = ready and 0.25 or 0.6
		HUDUI.Refs.tutorialCompleteBtn.Text = ready and "완료" or "진행중"
		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.Active = ready
		end
		_setReadyPulse(ready)
	end

	local shownStep = math.max(1, tonumber(status.stepIndex) or 1)
	local totalSteps = math.max(1, tonumber(status.totalSteps) or 1)
	HUDUI.Refs.tutorialTitle.Text = string.format("튜토리얼 퀘스트 (%d/%d)", shownStep, totalSteps)
	HUDUI.SetTutorialVisible(true)
end

function HUDUI.UpdateHealth(cur, max)
	local bar = HUDUI.Refs.healthBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.hpDecay then TweenService:Create(HUDUI.Refs.hpDecay, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
	bar.fill.BackgroundColor3 = r < 0.25 and C.RED or C.HP
end

function HUDUI.UpdateStamina(cur, max)
	local bar = HUDUI.Refs.staminaBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.staDecay then TweenService:Create(HUDUI.Refs.staDecay, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
end

function HUDUI.UpdateHunger(cur, max)
	local bar = HUDUI.Refs.hungerBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.hunDecay then TweenService:Create(HUDUI.Refs.hunDecay, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%d / %d", math.floor(cur), math.floor(max))
	
	-- 배고픔 수치에 따른 색상 변화 (초록 유지 강조)
	if r > 0.4 then
		bar.fill.BackgroundColor3 = C.HUNGER -- 초록
	elseif r > 0.15 then
		bar.fill.BackgroundColor3 = C.GOLD_SEL -- 노랑
	else
		bar.fill.BackgroundColor3 = C.HP -- 빨강
	end
end

function HUDUI.UpdateXP(cur, max)
	local bar = HUDUI.Refs.xpBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar, TweenInfo.new(0.3), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.levelLabel then 
		HUDUI.Refs.levelLabel.Text = string.format("LV. %s [ %.1f%% ]", tostring(HUDUI.Refs.currentLevel or 1), r * 100)
	end
end

function HUDUI.UpdateLevel(lv)
	HUDUI.Refs.currentLevel = lv
end

function HUDUI.SetStatPointAlert(available)
	if HUDUI.Refs.statPointAlert then
		HUDUI.Refs.statPointAlert.Visible = (available > 0)
	end
end

local harvestTween = nil
local harvestConn = nil

function HUDUI.ShowHarvestProgress(totalTime, targetName)
	local hf = HUDUI.Refs.harvestFrame
	if hf then
		hf.Visible = true
		if harvestTween then harvestTween:Cancel(); harvestTween = nil end
		if harvestConn then harvestConn:Disconnect(); harvestConn = nil end
		
		if HUDUI.Refs.harvestBar then HUDUI.Refs.harvestBar.Size = UDim2.new(0, 0, 1, 0) end
		if HUDUI.Refs.harvestName then HUDUI.Refs.harvestName.Text = targetName or "채집 중..." end
		if HUDUI.Refs.harvestPct then HUDUI.Refs.harvestPct.Text = "0%" end
		
		if type(totalTime) == "number" and totalTime > 0 then
			harvestTween = TweenService:Create(HUDUI.Refs.harvestBar, TweenInfo.new(totalTime, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)})
			harvestTween:Play()
			
			local start = tick()
			harvestConn = RunService.RenderStepped:Connect(function()
				local p = math.clamp((tick() - start) / totalTime, 0, 1)
				HUDUI.UpdateHarvestProgress(p)
			end)
		end
	end
end

function HUDUI.UpdateHarvestProgress(pct)
	if HUDUI.Refs.harvestBar then HUDUI.Refs.harvestBar.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0) end
	if HUDUI.Refs.harvestPct then HUDUI.Refs.harvestPct.Text = math.floor(pct * 100) .. "%" end
end

function HUDUI.HideHarvestProgress()
	if harvestTween then harvestTween:Cancel(); harvestTween = nil end
	if harvestConn then harvestConn:Disconnect(); harvestConn = nil end
	if HUDUI.Refs.harvestFrame then HUDUI.Refs.harvestFrame.Visible = false end
end

-- [X] show/hideInteractPrompt moved to InteractUI

function HUDUI.UpdateStatusEffects(debuffList)
	local container = HUDUI.Refs.effectList
	if not container then return end
	
	-- Clear existing (except stat alert)
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("GuiObject") and ch ~= HUDUI.Refs.statPointAlert then
			ch:Destroy()
		end
	end
	
	-- 에셋 타입 호환성 체크 (Decal은 Texture, ImageLabel은 Image 속성 사용)
	local function getIcon(name)
		if not StatusIcons then return "" end
		local asset = StatusIcons:FindFirstChild(name)
		if not asset then return "" end
		if asset:IsA("Decal") then return asset.Texture end
		if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then return asset.Image end
		return ""
	end

	local IconMap = {
		FREEZING    = getIcon("FREEZING"), 
		BLOOD_SMELL = getIcon("BLOOD_SMELL"), 
		BURNING     = getIcon("BURNING"),
		CHILLY      = getIcon("CHILLY"),
		WARMTH      = getIcon("WARMTH"),
	}
	
	for _, debuff in ipairs(debuffList) do
		local iconId = IconMap[debuff.id] or "rbxassetid://6034346917"
		local isBuff = (debuff.id == "WARMTH") -- 굳이 복잡하게 안하고 하드코딩

		local slot = Utils.mkFrame({
			name = debuff.id,
			size = UDim2.new(0, 26, 0, 26),
			bg = isBuff and Color3.fromRGB(0, 40, 0) or Color3.fromRGB(40, 0, 0), 
			bgT = 0.4,
			r = 4,
			stroke = 1,
			strokeC = isBuff and Color3.fromRGB(100, 255, 100) or C.RED,
			parent = container
		})
		
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(0.8, 0, 0.8, 0)
		img.Position = UDim2.new(0.5, 0, 0.5, 0)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.BackgroundTransparency = 1
		img.Image = iconId
		img.ImageColor3 = C.WHITE
		img.Parent = slot
		
		-- Hover Tooltip per Icon
		local btn = Instance.new("TextButton")
		btn.Name = "TipBtn"
		btn.Size = UDim2.new(1,0,1,0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Parent = slot

		btn.MouseEnter:Connect(function()
			if HUDUI.Refs.tooltip then
				HUDUI.Refs.tipTitle.Text = UILocalizer.Localize(debuff.name or debuff.id)
				HUDUI.Refs.tipBody.Text = UILocalizer.Localize(debuff.description or "")
				local lines = select(2, (debuff.description or ""):gsub("\n", "\n")) + 1
				HUDUI.Refs.tooltip.Size = UDim2.new(0, 210, 0, 50 + lines * 16)
				HUDUI.Refs.tooltip.Visible = true
			end
		end)

		btn.MouseLeave:Connect(function()
			if HUDUI.Refs.tooltip then
				HUDUI.Refs.tooltip.Visible = false
			end
		end)
	end
end

function HUDUI.UpdateCoordinates(x, z)
	if HUDUI.Refs.coordLabel then
		HUDUI.Refs.coordLabel.Text = string.format("X: %.0f  Z: %.0f", x, z)
	end
end

function HUDUI.UpdateCompass(angle)
	local north = HUDUI.Refs.northIndicator
	if north then
		-- HUD UI Rotation (Angle is in radians from Camera)
		local radius = 50 -- Minimap size is 120, radius 60, indicator at 50
		local x = 0.5 + math.sin(angle) * 0.4
		local y = 0.5 + math.cos(angle) * 0.4
		north.Position = UDim2.new(x, 0, y, 0)
	end
end

-- Compatibility wrappers just in case
function HUDUI.SelectHotbarSlot(idx, skipSync, UIManager, C)
	local slots = HUDUI.Refs.hotbarSlots
	if not slots then return end
	
	for i = 1, 8 do
		local s = slots[i]
		if not s then continue end
		local stroke = s.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			if i == idx then
				stroke.Color = C.GOLD_SEL
				stroke.Thickness = 2
			else
				stroke.Color = C.BORDER_DIM
				stroke.Thickness = 1
			end
		end
	end
end 

return HUDUI
