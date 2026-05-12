local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local LocaleService = require(script.Parent.Parent.Localization.LocaleService)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local HUDUI = {}
local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local isSmall = isMobile
local isTutorialMinimized = false
local tutorialWantedVisible = false
local tutorialReady = false
local tutorialPulseTween = nil
local tutorialHintPulseTween = nil
local tutorialClickPulseTween = nil
local tutorialRelayoutFn = nil
HUDUI.LastStatus = nil
local questTokenNameCache = {}
local TOOLTIP_WIDTH = 280
local TOOLTIP_MARGIN = 14

-- [UX] 버튼 클릭/터치/키보드 시각 피드백 (스케일 애니메이션)
local function triggerScale(btn)
	if not btn then return end
	local uiScale = btn:FindFirstChild("UIScale") or Instance.new("UIScale", btn)
	TweenService:Create(uiScale, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.85}):Play()
	task.delay(0.05, function()
		if not uiScale or not uiScale.Parent then return end
		TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end)
end

local function buildIdLookup(tableModule)
	local out = {}
	if type(tableModule) ~= "table" then
		return out
	end
	for key, value in pairs(tableModule) do
		if type(value) == "table" and value.id then
			out[tostring(value.id)] = value
		elseif type(key) == "string" and type(value) == "table" and value.id == nil then
			out[key] = value
		end
	end
	return out
end

local itemLookup = {}
local facilityLookup = {}
local recipeLookup = {}
local creatureLookup = {}

local TUTORIAL_STEP_EN = {
	COLLECT_BASICS = {
		currentStepText = "Gather 1 Small Stone and 1 Branch first",
		stepCommand = "Pick up 1 SMALL_STONE + 1 BRANCH nearby",
	},
	CRAFT_AXE = {
		currentStepText = "Craft a Crude Stone Axe",
		stepCommand = "Craft CRAFT_CRUDE_STONE_AXE in the inventory crafting tab",
	},
	GET_WOOD = {
		currentStepText = "Secure wood resources",
		stepCommand = "Obtain at least 1 WOOD or LOG",
	},
	KILL_DODO = {
		currentStepText = "Hunt for food",
		stepCommand = "Kill 1 DODO",
	},
	BUILD_CAMPFIRE = {
		currentStepText = "Build a warmth point before night",
		stepCommand = "Place 1 CAMPFIRE",
	},
	COOK_MEAT = {
		currentStepText = "Cook 1 meat",
		stepCommand = "Craft CRAFT_COOKED_MEAT",
	},
	PLACE_TOTEM = {
		currentStepText = "Secure a base center point",
		stepCommand = "Place 1 CAMP_TOTEM",
	},
	BUILD_LEAN_TO = {
		currentStepText = "Secure a sleep/respawn point",
		stepCommand = "Place 1 BED_T1",
	},
}

do
	local dataFolder = ReplicatedStorage:FindFirstChild("Data")
	if dataFolder then
		local okItem, itemData = pcall(function()
			return require(dataFolder:WaitForChild("ItemData"))
		end)
		if okItem then
			itemLookup = buildIdLookup(itemData)
		end

		local okFacility, facilityData = pcall(function()
			return require(dataFolder:WaitForChild("FacilityData"))
		end)
		if okFacility then
			facilityLookup = buildIdLookup(facilityData)
		end

		local okRecipe, recipeData = pcall(function()
			return require(dataFolder:WaitForChild("RecipeData"))
		end)
		if okRecipe then
			recipeLookup = buildIdLookup(recipeData)
		end

		local okCreature, creatureData = pcall(function()
			return require(dataFolder:WaitForChild("CreatureData"))
		end)
		if okCreature then
			creatureLookup = buildIdLookup(creatureData)
		end
	end
end

local function resolveQuestTokenName(token: string): string
	local normalizedToken = tostring(token or "")
	local upperToken = string.upper(normalizedToken)
	local cached = questTokenNameCache[token]
	if cached ~= nil then
		return cached
	end

	local item = itemLookup[normalizedToken] or itemLookup[upperToken]
	if item and item.name then
		cached = UILocalizer.LocalizeDataText("ItemData", tostring(item.id or upperToken), "name", tostring(item.name))
		questTokenNameCache[token] = cached
		return cached
	end

	local facility = facilityLookup[normalizedToken] or facilityLookup[upperToken]
	if facility and facility.name then
		cached = UILocalizer.LocalizeDataText("FacilityData", tostring(facility.id or upperToken), "name", tostring(facility.name))
		questTokenNameCache[token] = cached
		return cached
	end

	local recipe = recipeLookup[normalizedToken] or recipeLookup[upperToken]
	if recipe and recipe.name then
		cached = UILocalizer.LocalizeDataText("RecipeData", tostring(recipe.id or upperToken), "name", tostring(recipe.name))
		questTokenNameCache[token] = cached
		return cached
	end

	local creature = creatureLookup[normalizedToken] or creatureLookup[upperToken]
	if creature and creature.name then
		cached = UILocalizer.LocalizeDataText("CreatureData", tostring(creature.id or upperToken), "name", tostring(creature.name))
		questTokenNameCache[token] = cached
		return cached
	end

	questTokenNameCache[token] = token
	return token
end

local function localizeQuestRuntimeText(text: string?): string
	if type(text) ~= "string" or text == "" then
		return ""
	end

	local replaced = string.gsub(text, "([%a][%w_]+)", function(token)
		return resolveQuestTokenName(token)
	end)

	return UILocalizer.Localize(replaced)
end

local function localizeTutorialStepField(status, fieldName: string): string
	local base = status and status[fieldName]
	if type(base) ~= "string" then
		return ""
	end

	if LocaleService.GetLanguage() ~= "en" then
		return base
	end

	local stepKey = tostring(status and status.stepKey or "")
	local stepMap = TUTORIAL_STEP_EN[stepKey]
	if stepMap and type(stepMap[fieldName]) == "string" and stepMap[fieldName] ~= "" then
		return stepMap[fieldName]
	end

	return base or ""
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
			table.insert(chunks, string.format("%s %d/%d", resolveQuestTokenName(tostring(itemId)), nowCount, needCount))
		end
		return table.concat(chunks, "  |  ")
	end

	local isCountBased = status.stepKind == "ITEM_ANY" or status.stepKind == "KILL" or status.stepKind == "BUILD" or status.stepKind == "HARVEST"
	if isCountBased then
		local nowCount = progress.count or 0
		local needCount = status.stepCount or 1
		return string.format("%d / %d", nowCount, needCount)
	end

	return string.format("%d / %d", status.stepIndex or 0, status.totalSteps or 0)
end

local function _buildRewardText(reward)
	if type(reward) ~= "table" then
		return ""
	end
	local greenHex = "#78D050"
	local function styleLabelAmount(labelText: string, amountText: string, greenLabel: boolean): string
		local localizedLabel = UILocalizer.Localize(labelText)
		if greenLabel then
			return string.format("<font color=\"%s\">%s</font> %s", greenHex, localizedLabel, amountText)
		end
		return string.format("%s %s", localizedLabel, amountText)
	end
	local chunks = {}
	if (reward.xp or 0) > 0 then
		table.insert(chunks, styleLabelAmount("XP", string.format("+%d", reward.xp), true))
	end
	if (reward.gold or 0) > 0 then
		table.insert(chunks, styleLabelAmount("골드", string.format("+%d", reward.gold), true))
	end
	if type(reward.items) == "table" then
		for _, item in ipairs(reward.items) do
			if type(item) == "table" and item.itemId and item.count then
				local itemName = tostring(item.itemId)
				local displayName = resolveQuestTokenName(itemName)
				local countText = string.format("*%d", tonumber(item.count) or 1)
				table.insert(chunks, styleLabelAmount(displayName, countText, false))
			end
		end
	end
	return table.concat(chunks, ", ")
end

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
	tutorialReadyHint = nil,
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
	
	-- [FIX] Moved OUT of the MainHUDContainer to solve the total container height stacking bug!
	local debuffRow = Utils.mkFrame({
		name = "DebuffRow",
		size = UDim2.new(0.42, 0, 0.04, 0),
		pos = UDim2.new(0.5, 0, 0.98 - 0.09, 0), -- Position directly above main frame
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = parent
	})
	local dLayout = Instance.new("UIListLayout")
	dLayout.FillDirection = Enum.FillDirection.Horizontal; dLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; dLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom; dLayout.Padding = UDim.new(0.02, 0); dLayout.Parent = debuffRow
	HUDUI.Refs.effectList = debuffRow

	-- [Punch-RPG Master Bounding Reference]
	-- This invisible container enforces constraints while providing an absolute coordinate space
	-- for adjacent floating components like the Hotbar to attach without colliding with UIListLayout.
	local mainAnchor = Utils.mkFrame({
		name = "MainHUDAnchor",
		size = UDim2.new(0.42, 0, 0.08, 0), 
		pos = UDim2.new(0.5, 0, 0.98, 0), 
		anchor = Vector2.new(0.5, 1),
		bgT = 1, -- Invisible root
		parent = parent
	})
	HUDUI.Refs.mainAnchor = mainAnchor

	local mainAR = Instance.new("UIAspectRatioConstraint")
	mainAR.AspectRatio = 4.8
	mainAR.AspectType = Enum.AspectType.ScaleWithParentSize
	mainAR.DominantAxis = Enum.DominantAxis.Width
	mainAR.Parent = mainAnchor
	
	local szConstraint = Instance.new("UISizeConstraint")
	szConstraint.MinSize = Vector2.new(340, 70); szConstraint.MaxSize = Vector2.new(780, 160); szConstraint.Parent = mainAnchor
	
	-- Actual visual container, child of the anchor
	local mainContainer = Utils.mkFrame({
		name = "MainHUDContainer",
		size = UDim2.new(1, 0, 1, 0), -- Fully conform to constrained anchor bounds
		pos = UDim2.new(0, 0, 0, 0), 
		bg = Color3.fromRGB(12, 12, 12),
		bgT = 1, -- Fully transparent background for clean floating components
		r = 0, 
		parent = mainAnchor
	})
	HUDUI.Refs.statusPanel = mainContainer

	-- Vertical stacking logic: SUM of all sub-element heights MUST EQUAL exactly 1.00
	local mainStack = Instance.new("UIListLayout")
	mainStack.FillDirection = Enum.FillDirection.Vertical; mainStack.Padding = UDim.new(0, 0); mainStack.SortOrder = Enum.SortOrder.LayoutOrder; mainStack.Parent = mainContainer

	-- 1. Stat Row (Top 31%)
	local statRow = Utils.mkFrame({name = "StatRow", size = UDim2.new(1, 0, 0.31, 0), bgT = 1, r = 0, parent = mainContainer})
	statRow.LayoutOrder = 1
	local statHList = Instance.new("UIListLayout")
	statHList.FillDirection = Enum.FillDirection.Horizontal; statHList.HorizontalAlignment = Enum.HorizontalAlignment.Center; statHList.Padding = UDim.new(0, 0); statHList.Parent = statRow

	-- Health Bar (Left 43%)
	local hpSeg = Utils.mkFrame({name="HPSegment", size = UDim2.new(0.43, 0, 1, 0), bgT=1, r=0, parent=statRow})
	hpSeg.LayoutOrder = 1
	local hpFill = Utils.mkFrame({name="Fill", size = UDim2.new(1, 0, 1, 0), bg = Color3.fromRGB(200, 25, 25), r=0, parent=hpSeg})
	local hpLabel = Utils.mkLabel({text="100/100", size = UDim2.new(0.9, 0, 0.6, 0), pos = UDim2.new(0.5,0,0.4,0), anchor=Vector2.new(0.5,0.5), font = F.NUM, color=C.WHITE, st=1, parent=hpSeg})
	hpLabel.TextScaled = true
	local hpSub = Utils.mkLabel({text="HP", size = UDim2.new(0.9, 0, 0.25, 0), pos = UDim2.new(0.5,0,0.85,0), anchor=Vector2.new(0.5,0.5), font=F.TITLE, color=Color3.new(0.9,0.9,0.9), st=0.5, parent=hpSeg})
	hpSub.TextScaled = true
	HUDUI.Refs.healthBar = {container = hpSeg, fill = hpFill, label = hpLabel}

	-- Level Segment (Center 14%) 
	local lvSeg = Utils.mkFrame({name="LvSeg", size = UDim2.new(0.14, 0, 1, 0), bg = Color3.new(0,0,0), bgT=0.7, r=0, parent=statRow})
	lvSeg.LayoutOrder = 2
	local lvLabel = Utils.mkLabel({
		text = "1", size = UDim2.new(0.85, 0, 0.85, 0), pos = UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5),
		font = Enum.Font.GothamBlack, bold = true, color = Color3.new(1, 1, 1), st = 0, parent = lvSeg
	})
	lvLabel.TextScaled = true
	-- Heavy contrast text outline for professional polished typography
	local lvTextStr = Instance.new("UIStroke")
	lvTextStr.Thickness = 2.5; lvTextStr.Color = Color3.new(0,0,0); lvTextStr.Parent = lvLabel
	HUDUI.Refs.levelLabel = lvLabel

	-- Mana Bar (Right 43%)
	local mpSeg = Utils.mkFrame({name="MPSegment", size = UDim2.new(0.43, 0, 1, 0), bgT=1, r=0, parent=statRow})
	mpSeg.LayoutOrder = 3
	local mpFill = Utils.mkFrame({name="Fill", size = UDim2.new(1, 0, 1, 0), bg = Color3.fromRGB(0, 102, 204), r=0, parent=mpSeg})
	local mpLabel = Utils.mkLabel({text="100/100", size = UDim2.new(0.9, 0, 0.6, 0), pos = UDim2.new(0.5,0,0.4,0), anchor=Vector2.new(0.5,0.5), font = F.NUM, color=C.WHITE, st=1, parent=mpSeg})
	mpLabel.TextScaled = true
	local mpSub = Utils.mkLabel({text="Mana", size = UDim2.new(0.9, 0, 0.25, 0), pos = UDim2.new(0.5,0,0.85,0), anchor=Vector2.new(0.5,0.5), font=F.TITLE, color=Color3.new(0.9,0.9,0.9), st=0.5, parent=mpSeg})
	mpSub.TextScaled = true
	HUDUI.Refs.staminaBar = {container = mpSeg, fill = mpFill, label = mpLabel}

	-- 2. EXP Row (Middle 19% height)
	local expRow = Utils.mkFrame({name = "EXPRow", size = UDim2.new(1, 0, 0.19, 0), bg = Color3.new(0,0,0), bgT=0.8, r=0, parent = mainContainer})
	expRow.LayoutOrder = 3
	local expFill = Utils.mkFrame({name="Fill", size = UDim2.new(0, 0, 1, 0), bg = Color3.fromRGB(255, 180, 0), r=0, parent=expRow})
	HUDUI.Refs.xpBar = expFill
	local expLabel = Utils.mkLabel({text="0/0", size = UDim2.new(0.9, 0, 0.6, 0), pos = UDim2.new(0.5, 0, 0.35, 0), anchor = Vector2.new(0.5, 0.5), font = F.NUM, color = C.WHITE, st = 1, parent = expRow})
	expLabel.TextScaled = true
	HUDUI.Refs.xpValueLabel = expLabel
	local expSub = Utils.mkLabel({text="EXP", size = UDim2.new(0.9, 0, 0.3, 0), pos = UDim2.new(0.5, 0, 0.85, 0), anchor = Vector2.new(0.5, 0.5), font = F.TITLE, color = Color3.new(0.8,0.8,0.8), st = 0.5, parent = expRow})
	expSub.TextScaled = true

	-- 3. Menu Row (Bottom 50% height maximizing icon clarity)
	local menuRow = Utils.mkFrame({name = "MenuRow", size = UDim2.new(1, 0, 0.50, 0), bgT=1, r=0, parent = mainContainer})
	menuRow.LayoutOrder = 5
	local menuGrid = Instance.new("UIGridLayout")
	menuGrid.CellSize = UDim2.new(0.16, 0, 0.95, 0) -- Perfect maximizing fit
	menuGrid.CellPadding = UDim2.new(0.006, 0, 0, 0); menuGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; menuGrid.VerticalAlignment = Enum.VerticalAlignment.Center; menuGrid.SortOrder = Enum.SortOrder.LayoutOrder; menuGrid.Parent = menuRow

	local function mkMenuCell(name, iconId, label, order, fn)
		local btn = Utils.mkFrame({name=name, size=UDim2.new(1,0,1,0), bg=Color3.fromRGB(28,28,28), bgT=1, r=0, parent=menuRow})
		btn.LayoutOrder = order
		local inner = Instance.new("ImageLabel")
		inner.Size = UDim2.new(0.4, 0, 0.6, 0); inner.Position = UDim2.new(0.5, 0, 0.35, 0); inner.AnchorPoint = Vector2.new(0.5, 0.5); inner.BackgroundTransparency = 1; inner.ScaleType = Enum.ScaleType.Fit; inner.Image = iconId; inner.Parent = btn
		local asp = Instance.new("UIAspectRatioConstraint"); asp.AspectRatio = 1; asp.Parent = inner
		local txt = Utils.mkLabel({text=label, size=UDim2.new(0.9, 0, 0.3, 0), pos=UDim2.new(0.5, 0, 0.8, 0), anchor=Vector2.new(0.5, 0.5), font=F.TITLE, color=C.WHITE, st=1, parent=btn})
		txt.TextScaled = true
		local clk = Instance.new("TextButton")
		clk.Size = UDim2.new(1,0,1,0); clk.BackgroundTransparency=1; clk.Text=""; clk.Parent=btn
		local sc = Instance.new("UIScale", btn)
		clk.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(65,65,65)}):Play() end)
		clk.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(28,28,28)}):Play() end)
		clk.MouseButton1Down:Connect(function() TweenService:Create(sc, TweenInfo.new(0.05), {Scale = 0.9}):Play() end)
		clk.MouseButton1Up:Connect(function() TweenService:Create(sc, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Scale = 1}):Play() end)
		clk.MouseButton1Click:Connect(fn)
		return btn
	end

	HUDUI.Refs.InventoryTabButton = mkMenuCell("BtnInv", UIManager.getItemIcon("Icon_Inventory"), "가방", 1, function() UIManager.toggleInventory() end)
	HUDUI.Refs.EquipTabButton = mkMenuCell("BtnStats", UIManager.getItemIcon("Icon_Equipment"), "스탯", 2, function() UIManager.toggleEquipment() end)
	HUDUI.Refs.SkillTabButton = mkMenuCell("BtnRune", UIManager.getItemIcon("Icon_Skill"), "룬", 3, function() UIManager.toggleSkillTree() end)
	HUDUI.Refs.ShopTabButton = mkMenuCell("BtnPass", UIManager.getItemIcon("Icon_Shop"), "게임 패스", 4, function() if UIManager.togglePremiumShop then UIManager.togglePremiumShop() end end)
	HUDUI.Refs.QuestTabButton = mkMenuCell("BtnStats2", UIManager.getItemIcon("Icon_Quest"), "통계", 5, function() if UIManager.toggleQuest then UIManager.toggleQuest() end end)
	mkMenuCell("BtnTrade", UIManager.getItemIcon("BtnTrade"), "거래", 6, function() end)

	HUDUI.Refs.hungerBar = {container = Instance.new("Frame"), fill = Instance.new("Frame"), label = Instance.new("TextLabel")}
	HUDUI.Refs.xpPctLabel = Instance.new("TextLabel")
	HUDUI.Refs.bottomEdge = mainContainer 
	HUDUI.Refs.statPointAlert = Utils.mkLabel({text = "▲ UP", size = UDim2.new(0.8, 0, 0.25, 0), pos = UDim2.new(1, 2, 0, 0), font = F.TITLE, color = C.GOLD, vis = false, parent = lvSeg})
	HUDUI.Refs.statPointAlert.TextScaled = true

	-- Tutorial quest: ultra-minimalist responsive HUD panel
	local tutorialFrame = Utils.mkFrame({
		name = "TutorialPanel",
		size = UDim2.new(isSmall and 0.4 or 0.2, 0, 0, isSmall and 75 or 65),
		pos = UDim2.new(1, -12, 0, 180),
		anchor = Vector2.new(1, 0),
		bg = C.BG_PANEL,
		bgT = 0.5,
		r = 6,
		stroke = 1,
		strokeC = C.BORDER,
		vis = false,
		parent = parent,
	})
	
	local relayoutTutorialPanel -- Forward declaration
	
	local function updateTutorialMinimize()
		-- [Fix] 하드코딩된 큰 수치 제거 및 동적 너비 유지
		local vp = workspace.CurrentCamera.ViewportSize
		local panelWidth = math.clamp(math.floor(vp.X * (isSmall and 0.25 or 0.12)), 130, 180)
		
		if isTutorialMinimized then
			tutorialFrame.Size = UDim2.new(0, panelWidth, 0, 48)
		else
			-- 확장 상태는 relayoutTutorialPanel에서 텍스트 길이에 맞춰 높이를 자동 계산함
			relayoutTutorialPanel()
		end
		
		for _, child in ipairs(tutorialFrame:GetChildren()) do
			local isAlwaysHidden = (child.Name == "TutorialCompleteBtn" or child.Name == "TutorialReward" or child.Name == "TutorialProgress" or child.Name == "TutorialReadyHint")
			if not isAlwaysHidden and child.Name ~= "TutorialTitle" and child.Name ~= "MinimizeBtn" and child:IsA("GuiObject") and child.Name ~= "UIGradient" then
				child.Visible = not isTutorialMinimized
			elseif isAlwaysHidden then
				child.Visible = false
			end
		end
		
		if HUDUI.Refs.minimizeBtn then
			HUDUI.Refs.minimizeBtn.Text = isTutorialMinimized and "+" or "-"
		end
	end

	-- MinimizeBtn 제거 (미니멀리즘 준수)
	-- isTutorialMinimized는 항상 false로 유지
	isTutorialMinimized = false

	local tutorialGradient = Instance.new("UIGradient")
	tutorialGradient.Rotation = 90
	tutorialGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.35, 0.40),
		NumberSequenceKeypoint.new(1, 0.65),
	})
	tutorialGradient.Parent = tutorialFrame
	HUDUI.Refs.tutorialFrame = tutorialFrame

	HUDUI.Refs.tutorialTitle = Utils.mkLabel({
		name = "TutorialTitle",
		text = UILocalizer.Localize("퀘스트"),
		size = UDim2.new(1, -16, 0, 24),
		pos = UDim2.new(0, 10, 0, 4),
		ax = Enum.TextXAlignment.Left,
		font = F.TITLE,
		ts = 16,
		color = C.GOLD,
		parent = tutorialFrame,
	})
	
	-- [Restore] Minimize button
	local minimizeBtn = Utils.mkBtn({
		name = "MinimizeBtn",
		text = "-",
		size = UDim2.new(0, 24, 0, 24),
		pos = UDim2.new(1, -4, 0, 4),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		stroke = false,
		ts = 18, -- Reduced from 20+
		font = F.TITLE,
		color = C.GOLD,
		z = 100, -- Ensure it's above TutorialClickArea
		fn = function()
			isTutorialMinimized = not isTutorialMinimized
			updateTutorialMinimize()
		end,
		parent = tutorialFrame,
	})
	HUDUI.Refs.minimizeBtn = minimizeBtn

	HUDUI.Refs.tutorialStep = Utils.mkLabel({
		name = "TutorialStep",
		text = "",
		size = UDim2.new(1, -20, 1, -30),
		pos = UDim2.new(0, 10, 0, 30),
		ax = Enum.TextXAlignment.Left,
		ay = Enum.TextYAlignment.Top,
		wrap = true,
		ts = 13,
		color = C.WHITE,
		parent = tutorialFrame,
	})

	HUDUI.Refs.tutorialProgress = Utils.mkLabel({
		name = "TutorialProgress",
		text = "",
		size = UDim2.new(0, 0, 0, 0),
		vis = false,
		parent = tutorialFrame,
	})

	HUDUI.Refs.tutorialReward = Utils.mkLabel({
		name = "TutorialReward",
		text = "",
		size = UDim2.new(0, 0, 0, 0),
		vis = false,
		parent = tutorialFrame,
	})

	HUDUI.Refs.tutorialReadyHint = Utils.mkLabel({
		name = "TutorialReadyHint",
		text = UILocalizer.Localize("박스를 클릭해 완료"),
		size = UDim2.new(0.48, 0, 0, 24),
		pos = UDim2.new(0.5, 0, 1, -30),
		ax = Enum.TextXAlignment.Right,
		ts = 18,
		font = F.TITLE,
		color = C.GOLD,
		vis = false,
		parent = tutorialFrame,
	})

	local tutorialCompleteBtn = Utils.mkBtn({
		name = "TutorialCompleteBtn",
		text = "완료",
		size = UDim2.new(0, 96, 0, 32),
		pos = UDim2.new(1, -10, 1, -30),
		anchor = Vector2.new(1, 1),
		bg = C.BG_PANEL_L,
		bgT = 0.94,
		stroke = false,
		ts = 17,
		font = F.TITLE,
		color = C.WHITE,
		fn = function()
			if UIManager and UIManager.requestTutorialStepComplete then
				UIManager.requestTutorialStepComplete()
			end
		end,
		parent = tutorialFrame,
	})

	local btnGradient = Instance.new("UIGradient")
	btnGradient.Rotation = 90
	btnGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(1, 0.38),
	})
	btnGradient.Parent = tutorialCompleteBtn
	HUDUI.Refs.tutorialCompleteBtn = tutorialCompleteBtn

	local tutorialClickArea = Instance.new("TextButton")
	tutorialClickArea.Name = "TutorialClickArea"
	tutorialClickArea.Size = UDim2.new(1, 0, 1, 0)
	tutorialClickArea.Position = UDim2.new(0, 0, 0, 0)
	tutorialClickArea.BackgroundTransparency = 1
	tutorialClickArea.BackgroundColor3 = C.GOLD
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

	relayoutTutorialPanel = function()
		if not (HUDUI.Refs.tutorialFrame and HUDUI.Refs.tutorialTitle and HUDUI.Refs.tutorialStep) then
			return
		end

		local panel = HUDUI.Refs.tutorialFrame
		local panelWidth = panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.X or (isSmall and 320 or 220)
		local contentWidth = panelWidth - 20
		local topPadding = 6
		local sidePadding = 10
		local rowGap = 2
		local bottomPadding = 6

		-- [중요] '진행도' 글씨 제거 및 타이틀 옆에 수량 강제 병합
		local titleBase = UILocalizer.Localize("퀘스트")
		local progressText = _buildProgressText(HUDUI.LastStatus) or "0/1"
		HUDUI.Refs.tutorialTitle.Text = string.format("%s (%s)", titleBase, progressText)

		local titleH = math.ceil(HUDUI.Refs.tutorialTitle.TextSize * 1.3)
		local stepBounds = TextService:GetTextSize(HUDUI.Refs.tutorialStep.Text or "", HUDUI.Refs.tutorialStep.TextSize, HUDUI.Refs.tutorialStep.Font, Vector2.new(contentWidth, 10000))
		local stepH = stepBounds.Y + 6

		local wantedHeight = topPadding + titleH + rowGap + stepH + bottomPadding
		local panelHeight = isTutorialMinimized and 40 or math.max(44, wantedHeight)

		panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, panelHeight)

		HUDUI.Refs.tutorialTitle.Size = UDim2.new(1, -20, 0, titleH)
		HUDUI.Refs.tutorialTitle.Position = UDim2.new(0, sidePadding, 0, topPadding)

		HUDUI.Refs.tutorialStep.Size = UDim2.new(1, -20, 0, stepH)
		HUDUI.Refs.tutorialStep.Position = UDim2.new(0, sidePadding, 0, topPadding + titleH + rowGap)

		-- Hide unused elements (Permanently)
		HUDUI.Refs.tutorialReward.Visible = false
		HUDUI.Refs.tutorialProgress.Visible = false
		if HUDUI.Refs.tutorialCompleteBtn then HUDUI.Refs.tutorialCompleteBtn.Visible = false end
		if HUDUI.Refs.tutorialReadyHint then HUDUI.Refs.tutorialReadyHint.Visible = false end
	end
	
	tutorialRelayoutFn = relayoutTutorialPanel

	-- Keep tutorial panel/text responsive with actual viewport size.
	local function updateTutorialLayout()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local vp = camera.ViewportSize
		local panelWidth = math.floor(vp.X * (isSmall and 0.25 or 0.12))
		panelWidth = math.clamp(panelWidth, 130, 180) -- 160~200 -> 130~180 (너비 축소)

		tutorialFrame.Size = UDim2.new(0, panelWidth, 0, tutorialFrame.Size.Y.Offset)
		tutorialFrame.Position = UDim2.new(1, -12, 0, 260) -- 210 -> 260 (위치 내림)

		local titleSize = math.clamp(math.floor(vp.Y * (isSmall and 0.022 or 0.018)), 14, 20)
		local bodySize = math.clamp(math.floor(vp.Y * (isSmall and 0.018 or 0.015)), 12, 16)
		local progressSize = math.clamp(math.floor(vp.Y * (isSmall and 0.018 or 0.015)), 12, 16)

		HUDUI.Refs.tutorialTitle.TextSize = titleSize
		HUDUI.Refs.tutorialStep.TextSize = bodySize
		HUDUI.Refs.tutorialProgress.TextSize = progressSize
		HUDUI.Refs.tutorialReward.TextSize = math.clamp(math.floor(vp.Y * (isSmall and 0.022 or 0.020)), 16, 24)

		local panelHeight = math.max(40, tutorialFrame.Size.Y.Offset) 
		local btnWidth = math.clamp(math.floor(panelWidth * 0.24), 90, 130)
		local btnHeight = math.clamp(math.floor(panelHeight * 0.24), 28, 42)
		HUDUI.Refs.tutorialCompleteBtn.Size = UDim2.new(0, btnWidth, 0, btnHeight)
		HUDUI.Refs.tutorialCompleteBtn.TextSize = math.clamp(math.floor(panelHeight * 0.13), 13, 18)
		HUDUI.Refs.tutorialReadyHint.TextSize = math.clamp(math.floor(panelHeight * 0.13), 13, 18)

		relayoutTutorialPanel()
	end

	updateTutorialLayout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateTutorialLayout)
	end

	--[[ [LEGACY DELETED] Action / Hexagon Buttons disabled completely
	local actionArea = Utils.mkFrame({
		name = "ActionArea",
		size = UDim2.new(0, isSmall and 300 or 240, 0, isSmall and 150 or 120),
		pos = UDim2.new(1, -20, 1, -20),
		anchor = Vector2.new(1, 1),
		bgT = 1,
		vis = false, -- [비활성화]
		parent = parent
	})
	
	-- Hexagonal Buttons Data: Attack, Dodge, Jump (Action Cluster)
	local hScale = isSmall and 1.25 or 1.0
	local hexBtns = {
		{id="Attack", icon="rbxassetid://10452331908", pos=UDim2.new(1, -70 * hScale, 0.5, 30), size=95 * hScale},
		{id="Dodge", icon="rbxassetid://6034346917", pos=UDim2.new(1, -15 * hScale, 0.5, 45), size=65 * hScale}, -- 구르기 (오른쪽 아래)
		{id="Jump", icon="rbxassetid://6034335017", pos=UDim2.new(1, -135 * hScale, 0.5, 95), size=65 * hScale}, -- 점프 (왼쪽 아래)
	}
	
	HUDUI.Refs.hex_Interact = nil
	
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
	]]

	-- [X] Redundant interact prompt removed (Using InteractUI instead)

	-- [Punch-RPG Hotbar & Gold] (Right Side, Responsive)
	local rightArea = Utils.mkFrame({
		name = "RightHUDArea",
		size = UDim2.new(0.10, 0, 0.42, 0), -- Sleeker percent-based bounding container
		pos = UDim2.new(0.98, 0, 0.98, 0), 
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = parent
	})
	local rightConstraint = Instance.new("UISizeConstraint")
	rightConstraint.MinSize = Vector2.new(60, 220); rightConstraint.MaxSize = Vector2.new(110, 460); rightConstraint.Parent = rightArea

	-- 1. Gold Display (Attached perfectly to bottom right)
	local moneyFrame = Utils.mkFrame({
		name = "MoneyFrame",
		size = UDim2.new(1, 0, 0.08, 0), 
		pos = UDim2.new(1, 0, 1, 0),
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = rightArea
	})
	local goldLabel = Utils.mkLabel({
		text = "0 G",
		size = UDim2.new(1, 0, 1, 0),
		font = F.TITLE,
		color = Color3.fromRGB(255, 215, 0),
		bold = true,
		ax = Enum.TextXAlignment.Right,
		st = 1,
		parent = moneyFrame
	})
	goldLabel.TextScaled = true
	HUDUI.Refs.goldLabel = goldLabel
	
	task.spawn(function()
		local ShopCtrl = require(Controllers.ShopController)
		if ShopCtrl and ShopCtrl.getGold then HUDUI.UpdateGold(ShopCtrl.getGold()) end
	end)

	-- 2. Usable Hotbar (Dynamically bonded to the Main HUD's right periphery)
	local hotbarFrame = Utils.mkFrame({
		name = "HotbarFrame",
		size = UDim2.new(0.12, 0, 2.3, 0), 
		pos = UDim2.new(0, 0, 0, 0), -- Will be dynamically calculated below to avoid boundary clicks blocking
		anchor = Vector2.new(0, 1), 
		bgT = 1,
		parent = parent -- CRITICAL: Parent directly to ScreenGui to guarantee clicks work!
	})

	-- Dynamically lock Hotbar precisely to Main HUD edge without boundary clipping issues
	local function syncHotbarPosition()
		if not mainAnchor or not hotbarFrame then return end
		local ap = mainAnchor.AbsolutePosition
		local as = mainAnchor.AbsoluteSize
		-- UI scale normalization
		local scale = parent:FindFirstChildOfClass("UIScale") and parent:FindFirstChildOfClass("UIScale").Scale or 1
		
		hotbarFrame.Position = UDim2.new(
			0, (ap.X + as.X) / scale + 15, 
			0, (ap.Y + as.Y) / scale
		)
	end
	mainAnchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(syncHotbarPosition)
	mainAnchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncHotbarPosition)
	task.spawn(function() task.wait(0.1); syncHotbarPosition() end)
	
	-- Add constraint to keep hotbar from getting comically huge on ultra-wide screens
	local hotConstraint = Instance.new("UISizeConstraint")
	hotConstraint.MinSize = Vector2.new(35, 100); hotConstraint.MaxSize = Vector2.new(70, 250); hotConstraint.Parent = hotbarFrame

	-- Top-to-bottom vertical flow matching user 1->2->3 descending request
	local hotVList = Instance.new("UIListLayout")
	hotVList.FillDirection = Enum.FillDirection.Vertical
	hotVList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hotVList.VerticalAlignment = Enum.VerticalAlignment.Bottom -- Fills from bottom up to stay attached to HUD edge
	hotVList.Padding = UDim.new(0, 8) -- Standard relative gap matching Rune Slots
	hotVList.SortOrder = Enum.SortOrder.LayoutOrder
	hotVList.Parent = hotbarFrame
	
	HUDUI.Refs.hotbarSlots = {}
	
	for i = 1, 3 do 
		local slot = Utils.mkSlot({
			name = "Slot"..i,
			size = UDim2.new(0, 48, 0, 48), -- Set to fixed size exactly matching Rune (E, R, T) slots
			bg = C.BG_SLOT, bgT = 0.3, r = 4, parent = hotbarFrame
		})
		slot.frame.LayoutOrder = i -- 1 is Top, 2 Middle, 3 Bottom
		
		-- Force square slots cross-resolution
		local sq = Instance.new("UIAspectRatioConstraint")
		sq.AspectRatio = 1; sq.Parent = slot.frame

		local numLabel = Utils.mkLabel({
			text = tostring(i), size = UDim2.new(0.3, 0, 0.3, 0), pos = UDim2.new(0.06, 0, 0.06, 0),
			font = F.TITLE, color = C.WHITE, ax = Enum.TextXAlignment.Left, ay = Enum.TextYAlignment.Top, st = 1, parent = slot.frame
		})
		numLabel.TextScaled = true
		HUDUI.Refs.hotbarSlots[i] = slot
		
		-- [추가] 슬롯 직접 클릭 시 애니메이션 발동
		if slot.click then
			slot.click.MouseButton1Down:Connect(function() triggerScale(slot.frame) end)
		end
	end
	
	local hiddenContainer = Instance.new("Frame"); hiddenContainer.Visible = false; hiddenContainer.Parent = parent
	for i = 4, 8 do
		HUDUI.Refs.hotbarSlots[i] = Utils.mkSlot({name="HiddenSlot"..i, parent=hiddenContainer})
	end

	-- Top Right: Minimap
	local minimap = Utils.mkFrame({
		name = "Minimap",
		size = UDim2.new(0, 120, 0, 120),
		pos = UDim2.new(1, -20, 0, 20),
		anchor = Vector2.new(1, 0),
		bgT = 0.4,
		bg = C.BG_DARK,
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
	
	-- 3. Rune Hotbar (E, R, T) - Decoupled parent to guarantee clicks work
	local runeFrame = Utils.mkFrame({
		name = "RuneHotbarFrame",
		size = UDim2.new(0, 52, 0, 200), 
		-- Map center is at right margin -80. 180px down puts it right below map and coord text.
		pos = UDim2.new(1, -80, 0, 180), 
		anchor = Vector2.new(0.5, 0),
		bgT = 1,
		parent = parent -- CRITICAL: Parent to ScreenGui ensures slots can accept click events
	})

	local runeVList = Instance.new("UIListLayout")
	runeVList.FillDirection = Enum.FillDirection.Vertical
	runeVList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	runeVList.VerticalAlignment = Enum.VerticalAlignment.Top
	runeVList.Padding = UDim.new(0, 8) 
	runeVList.SortOrder = Enum.SortOrder.LayoutOrder
	runeVList.Parent = runeFrame
	
	HUDUI.Refs.runeSlots = {}
	local runeKeys = {"E", "R", "T"}
	
	for i, keyName in ipairs(runeKeys) do
		local slot = Utils.mkSlot({
			name = "RuneSlot_"..keyName,
			size = UDim2.new(0, 48, 0, 48), -- Fixed sizing matches rigid minimap behavior
			bg = C.BG_SLOT, bgT = 0.4, r = 6, parent = runeFrame
		})
		slot.frame.LayoutOrder = i
		
		local keyLabel = Utils.mkLabel({
			text = keyName, size = UDim2.new(0.4, 0, 0.4, 0), pos = UDim2.new(0.06, 0, 0.06, 0),
			font = F.TITLE, color = C.WHITE, ax = Enum.TextXAlignment.Left, ay = Enum.TextYAlignment.Top, st = 1, parent = slot.frame
		})
		keyLabel.TextScaled = true
		HUDUI.Refs.runeSlots[i] = slot
		
		-- [추가] 슬롯 직접 클릭 시 애니메이션 발동
		if slot.click then
			slot.click.MouseButton1Down:Connect(function() triggerScale(slot.frame) end)
		end
	end

	local dayNightRing = Utils.mkFrame({
		name = "DayNightRing",
		size = UDim2.new(0, 96, 0, 96),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_DARK,
		bgT = 0.25,
		r = "full",
		stroke = 2,
		strokeC = C.GOLD,
		parent = minimap,
	})

	local dayNightHand = Utils.mkFrame({
		name = "SunMarker",
		size = UDim2.new(0, 12, 0, 12),
		pos = UDim2.new(0.5, 0, 0.1, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.GOLD,
		bgT = 0,
		r = "full",
		stroke = 1,
		strokeC = C.WOOD_DARK,
		parent = minimap,
	})

	local moonMarker = Utils.mkFrame({
		name = "MoonMarker",
		size = UDim2.new(0, 10, 0, 10),
		pos = UDim2.new(0.5, 0, 0.9, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = Color3.fromRGB(160, 175, 200),
		bgT = 0,
		r = "full",
		stroke = 1,
		strokeC = C.WOOD_DARK,
		parent = minimap,
	})

	local phaseLabel = Utils.mkLabel({
		name = "PhaseLabel",
		text = "DAY",
		size = UDim2.new(0, 48, 0, 18),
		pos = UDim2.new(0.5, 0, 0.9, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 11,
		bold = true,
		color = C.GOLD,
		parent = minimap,
	})

	HUDUI.Refs.dayNightRing = dayNightRing
	HUDUI.Refs.dayNightHand = dayNightHand
	HUDUI.Refs.dayNightMoon = moonMarker
	HUDUI.Refs.phaseLabel = phaseLabel
	
	if HUDUI.Refs.hex_Attack then
		HUDUI.Refs.hex_Attack.MouseButton1Click:Connect(function() local CC = require(Controllers.CombatController); if CC.attack then CC.attack() end end)
	end

	-- Dodge & Jump (Mobile Bindings)
	if HUDUI.Refs.hex_Dodge then
		HUDUI.Refs.hex_Dodge.MouseButton1Click:Connect(function() 
			local MC = require(Controllers.MovementController)
			if MC.performDodge then MC.performDodge() end -- Ensure function exists or use shared trigger
		end)
	end
	
	if HUDUI.Refs.hex_Jump then
		HUDUI.Refs.hex_Jump.MouseButton1Click:Connect(function()
			local hum = player.Character and player.Character:FindFirstChild("Humanoid")
			if hum then hum.Jump = true end
		end)
	end

	-- [UX] UI Toggle Key Bindings moved to ClientInit for consistency

	-- Harvest Setup
	HUDUI.Refs.harvestFrame = Utils.mkFrame({name="Harvest", size=UDim2.new(0, 300, 0, 60), pos=UDim2.new(0.4, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bgT=1, vis=false, parent=parent})
	local hBar = Utils.mkBar({size=UDim2.new(1, 0, 0, 6), pos=UDim2.new(0.5, 0, 0, 30), anchor=Vector2.new(0.5, 0), fillC=C.WHITE, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestBar = hBar.fill
	HUDUI.Refs.harvestName = Utils.mkLabel({text="채집 중...", size=UDim2.new(1, 0, 0, 25), ts=16, bold=true, rich=true, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestPct = Utils.mkLabel({text="0%", size=UDim2.new(1, 0, 0, 20), pos=UDim2.new(0.5, 0, 0, 45), anchor=Vector2.new(0.5, 0), ts=14, color=C.GOLD, parent=HUDUI.Refs.harvestFrame})

	-- =============================================
	-- Combat UI (Durango Style - Reference Based)
	-- =============================================
	
	-- Combat container (no visible background)
	local combatContainer = Instance.new("Frame")
	combatContainer.Name = "CombatUIContainer"
	combatContainer.Size = UDim2.new(1, 0, 0, 200)
	combatContainer.Position = UDim2.new(0, 0, 0, 0)
	combatContainer.BackgroundTransparency = 1
	combatContainer.BorderSizePixel = 0
	combatContainer.ClipsDescendants = true -- ★ 범위 밖 테스트 숨김
	combatContainer.Visible = false
	combatContainer.ZIndex = 99
	combatContainer.Parent = parent
	HUDUI.Refs.combatUIContainer = combatContainer

	-- Creature Name Label (White, Bold, 28pt)
	HUDUI.Refs.combatBossName = Utils.mkLabel({
		name = "CreatureName",
		text = "",
		size = UDim2.new(1, 0, 0, 32),
		pos = UDim2.new(0.5, 0, 0, 60),
		anchor = Vector2.new(0.5, 0),
		ts = 28,
		bold = true,
		color = Color3.fromRGB(255, 255, 255),
		ax = Enum.TextXAlignment.Center,
		parent = combatContainer
	})
	HUDUI.Refs.combatBossName.BackgroundTransparency = 1
	HUDUI.Refs.combatBossName.Font = F.TITLE

	-- Creature Level Label (Red, 20pt, right next to name)
	HUDUI.Refs.combatBossLevel = Utils.mkLabel({
		name = "CreatureLevel",
		text = "",
		size = UDim2.new(0, 80, 0, 32),
		pos = UDim2.new(0.5, 60, 0, 60),
		anchor = Vector2.new(0, 0),
		ts = 24,
		bold = true,
		color = Color3.fromRGB(255, 100, 100),
		ax = Enum.TextXAlignment.Left,
		parent = combatContainer
	})
	HUDUI.Refs.combatBossLevel.BackgroundTransparency = 1
	HUDUI.Refs.combatBossLevel.Font = F.TITLE

	-- HP Bar Background (Black, max width 400px)
	local hpBarBg = Instance.new("Frame")
	hpBarBg.Name = "HPBarBg"
	hpBarBg.Size = UDim2.new(0.5, 0, 0, 8)
	hpBarBg.Position = UDim2.new(0.5, 0, 0, 135)
	hpBarBg.AnchorPoint = Vector2.new(0.5, 0)
	hpBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	hpBarBg.BackgroundTransparency = 0.1
	hpBarBg.BorderSizePixel = 0
	-- ★ 최대 너비 400px 제약
	local hpSizeConstraint = Instance.new("UISizeConstraint")
	hpSizeConstraint.MaxSize = Vector2.new(400, 999)
	hpSizeConstraint.Parent = hpBarBg
	hpBarBg.Parent = combatContainer
	HUDUI.Refs.combatHPBarBg = hpBarBg

	-- HP Bar Fill (Red)
	local hpBarFill = Instance.new("Frame")
	hpBarFill.Name = "HPBarFill"
	hpBarFill.Size = UDim2.new(1, 0, 1, 0)
	hpBarFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	hpBarFill.BackgroundTransparency = 0
	hpBarFill.BorderSizePixel = 0
	hpBarFill.Parent = hpBarBg
	HUDUI.Refs.combatHPBarFill = hpBarFill

	-- HP Text Label (White, 16pt, centered below bar)
	HUDUI.Refs.combatHPLabel = Utils.mkLabel({
		name = "HPLabel",
		text = "",
		size = UDim2.new(0.5, 0, 0, 24),
		pos = UDim2.new(0.5, 0, 0, 147),
		anchor = Vector2.new(0.5, 0),
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Center,
		parent = combatContainer
	})
	HUDUI.Refs.combatHPLabel.BackgroundTransparency = 1

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
	tipBody.Size = UDim2.new(1, -20, 0, 40)
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

	function HUDUI.ShowTooltip(titleText: string, bodyText: string)
		if not HUDUI.Refs.tooltip or not HUDUI.Refs.tipTitle or not HUDUI.Refs.tipBody then
			return
		end

		local localizedTitle = UILocalizer.Localize(titleText or "")
		local localizedBody = UILocalizer.Localize(bodyText or "")

		HUDUI.Refs.tipTitle.Text = localizedTitle
		HUDUI.Refs.tipBody.Text = localizedBody

		local maxBodyWidth = TOOLTIP_WIDTH - 20
		local textBounds = TextService:GetTextSize(
			localizedBody,
			HUDUI.Refs.tipBody.TextSize,
			HUDUI.Refs.tipBody.Font,
			Vector2.new(maxBodyWidth, 2000)
		)
		local bodyHeight = math.max(40, textBounds.Y + 6)
		HUDUI.Refs.tipBody.Size = UDim2.new(1, -20, 0, bodyHeight)
		HUDUI.Refs.tooltip.Size = UDim2.new(0, TOOLTIP_WIDTH, 0, 44 + bodyHeight + 10)
		HUDUI.Refs.tooltip.Visible = true
	end

	function HUDUI.HideTooltip()
		if HUDUI.Refs.tooltip then
			HUDUI.Refs.tooltip.Visible = false
		end
	end

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
			HUDUI.ShowTooltip(data.title, data.body)
		end)

		overlay.MouseLeave:Connect(function()
			HUDUI.HideTooltip()
		end)
	end

	-- 툴팁이 마우스를 따라다니게 처리
	RunService.RenderStepped:Connect(function()
		if tooltip.Visible then
			local mousePos = UserInputService:GetMouseLocation()
			local uiScale = parent:FindFirstChildOfClass("UIScale")
			local scale = uiScale and uiScale.Scale or 1
			local camera = workspace.CurrentCamera
			local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)

			local desiredX = mousePos.X / scale + 15
			local desiredY = (mousePos.Y - 36) / scale + 15
			local maxX = math.max(0, vp.X - tooltip.AbsoluteSize.X - TOOLTIP_MARGIN)
			local maxY = math.max(0, vp.Y - tooltip.AbsoluteSize.Y - TOOLTIP_MARGIN)

			tooltip.Position = UDim2.new(
				0,
				math.floor(math.clamp(desiredX, TOOLTIP_MARGIN, math.max(TOOLTIP_MARGIN, maxX))),
				0,
				math.floor(math.clamp(desiredY, TOOLTIP_MARGIN, math.max(TOOLTIP_MARGIN, maxY)))
			)
		end
	end)
	
	-- [UX] 입력 리스너 통합 관리 (Init 시점에 딱 한 번만 연결하여 누수 방지)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			local focused = UserInputService:GetFocusedTextBox()
			if focused then return end
		end

		-- 1~8 숫자 키 처리
		local kc = input.KeyCode.Value
		if kc >= Enum.KeyCode.One.Value and kc <= Enum.KeyCode.Eight.Value then
			local slotIdx = kc - Enum.KeyCode.One.Value + 1
			local slot = HUDUI.Refs.hotbarSlots and HUDUI.Refs.hotbarSlots[slotIdx]
			if slot then triggerScale(slot.frame) end
		end
		
		-- E, R, T 룬 키 처리
		local rKeys = { [Enum.KeyCode.E] = 1, [Enum.KeyCode.R] = 2, [Enum.KeyCode.T] = 3 }
		local rIdx = rKeys[input.KeyCode]
		if rIdx and HUDUI.Refs.runeSlots then
			local slot = HUDUI.Refs.runeSlots[rIdx]
			if slot then triggerScale(slot.frame) end
		end

		-- 기타 UI 트리거 (Tab 등)
		if input.KeyCode == Enum.KeyCode.Tab then
			triggerScale(HUDUI.Refs.InventoryTabButton)
		end

		-- 액션 버튼 시각 효과
		if input.KeyCode == Enum.KeyCode.Space then
			triggerScale(HUDUI.Refs.hex_Jump)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerScale(HUDUI.Refs.hex_Attack)
		elseif input.KeyCode == Enum.KeyCode.LeftControl then
			triggerScale(HUDUI.Refs.hex_Dodge)
		end
	end)
end


local function _setReadyPulse(ready)
	tutorialReady = ready == true
	if tutorialPulseTween then
		tutorialPulseTween:Cancel()
		tutorialPulseTween = nil
	end
	if tutorialHintPulseTween then
		tutorialHintPulseTween:Cancel()
		tutorialHintPulseTween = nil
	end
	if tutorialClickPulseTween then
		tutorialClickPulseTween:Cancel()
		tutorialClickPulseTween = nil
	end

	if not HUDUI.Refs.tutorialFrame then
		return
	end

	local stroke = HUDUI.Refs.tutorialFrame:FindFirstChildOfClass("UIStroke")
	if ready then
		if stroke then
			stroke.Color = C.GOLD
			stroke.Transparency = 0.05
		end
		HUDUI.Refs.tutorialFrame.BackgroundTransparency = 0.97
		tutorialPulseTween = TweenService:Create(
			HUDUI.Refs.tutorialFrame,
			TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.8 }
		)
		tutorialPulseTween:Play()

		if HUDUI.Refs.tutorialReadyHint then
			HUDUI.Refs.tutorialReadyHint.Visible = false
			HUDUI.Refs.tutorialReadyHint.TextTransparency = 0
			tutorialHintPulseTween = TweenService:Create(
				HUDUI.Refs.tutorialReadyHint,
				TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ TextTransparency = 0.82 }
			)
			tutorialHintPulseTween:Play()
		end

		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.BackgroundTransparency = 0.92
			tutorialClickPulseTween = TweenService:Create(
				HUDUI.Refs.tutorialClickArea,
				TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.6 }
			)
			tutorialClickPulseTween:Play()
		end
	else
		HUDUI.Refs.tutorialFrame.BackgroundTransparency = 0.96
		if stroke then
			stroke.Color = C.BORDER
			stroke.Transparency = 0.4
		end
		if HUDUI.Refs.tutorialReadyHint then
			HUDUI.Refs.tutorialReadyHint.Visible = false
			HUDUI.Refs.tutorialReadyHint.TextTransparency = 0
		end
		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.BackgroundTransparency = 1
		end
	end
end

function HUDUI.SetVisible(visible)
	if HUDUI.Refs.statusPanel then HUDUI.Refs.statusPanel.Visible = visible end
	if HUDUI.Refs.bottomEdge then HUDUI.Refs.bottomEdge.Visible = visible end
	if HUDUI.Refs.menuRow then HUDUI.Refs.menuRow.Visible = visible end
	if HUDUI.Refs.hex_Attack then HUDUI.Refs.hex_Attack.Parent.Visible = visible end
	if HUDUI.Refs.tutorialFrame then
		HUDUI.Refs.tutorialFrame.Visible = visible and tutorialWantedVisible
	end
end

function HUDUI.SetTutorialVisible(visible)
	tutorialWantedVisible = visible == true
	if HUDUI.Refs.tutorialFrame then
		local hudVisible = (HUDUI.Refs.statusPanel == nil) or HUDUI.Refs.statusPanel.Visible
		HUDUI.Refs.tutorialFrame.Visible = tutorialWantedVisible and hudVisible
	end
end

function HUDUI.UpdateTutorialStatus(status)
	HUDUI.LastStatus = status
	if type(status) ~= "table" or not HUDUI.Refs.tutorialFrame then
		return
	end

	if status.completed then
		HUDUI.Refs.tutorialTitle.Text = UILocalizer.Localize("퀘스트 완료")
		HUDUI.Refs.tutorialStep.Text = UILocalizer.Localize("기본 생존 가이드를 모두 마쳤습니다.\n가이드: 이제부터는 네 판단으로 살아남아.")
		local completedReward = _buildRewardText(status.reward or status.rewardPreview)
		HUDUI.Refs.tutorialProgress.Text = UILocalizer.Localize("보상이 지급되었습니다")
		HUDUI.Refs.tutorialReward.Text = completedReward ~= "" and (UILocalizer.Localize("획득:") .. " " .. completedReward) or (UILocalizer.Localize("획득:") .. " -")
		if tutorialRelayoutFn then
			tutorialRelayoutFn()
		end
		if HUDUI.Refs.tutorialCompleteBtn then
			HUDUI.Refs.tutorialCompleteBtn.Visible = false
		end
		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.Active = false
		end
		_setReadyPulse(false)
		HUDUI.SetTutorialVisible(false)
		return
	end

	if not status.active then
		_setReadyPulse(false)
		HUDUI.SetTutorialVisible(false)
		return
	end

	local progText = _buildProgressText(status)
	HUDUI.Refs.tutorialTitle.Text = UILocalizer.Localize("퀘스트") .. " " .. (progText or "0/1")
	
	HUDUI.Refs.tutorialProgress.Visible = false
	HUDUI.Refs.tutorialReward.Visible = false
	
	local stepLines = {}
	local currentStepText = localizeTutorialStepField(status, "currentStepText")
	if currentStepText ~= "" then
		table.insert(stepLines, localizeQuestRuntimeText(currentStepText))
	end
	local stepCommand = localizeTutorialStepField(status, "stepCommand")
	if stepCommand ~= "" then
		-- '진행도' 단어 제거, 목푯값만 표시
		table.insert(stepLines, localizeQuestRuntimeText(stepCommand))
	end
	HUDUI.Refs.tutorialStep.Text = (#stepLines > 0) and table.concat(stepLines, "\n") or UILocalizer.Localize("다음 목표 대기 중")
	
	HUDUI.Refs.tutorialProgress.Text = ""
	HUDUI.Refs.tutorialReward.Text = ""
	if tutorialRelayoutFn then
		tutorialRelayoutFn()
	end

	if HUDUI.Refs.tutorialCompleteBtn then
		HUDUI.Refs.tutorialCompleteBtn.Visible = false
	end
	if HUDUI.Refs.tutorialReadyHint then
		HUDUI.Refs.tutorialReadyHint.Visible = false
	end
	if HUDUI.Refs.tutorialClickArea then
		HUDUI.Refs.tutorialClickArea.Active = false
	end
	_setReadyPulse(false)
	
	-- 접힌 상태 레이아웃 강제 업데이트
	if isTutorialMinimized then
		for _, child in ipairs(HUDUI.Refs.tutorialFrame:GetChildren()) do
			if child.Name ~= "TutorialTitle" and child.Name ~= "MinimizeBtn" and child:IsA("GuiObject") and child.Name ~= "UIGradient" then
				child.Visible = false
			end
		end
	end

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
	if HUDUI.Refs.xpPctLabel then
		HUDUI.Refs.xpPctLabel.Text = string.format("%d%%", math.floor(r * 100))
	end
	if HUDUI.Refs.xpValueLabel then
		HUDUI.Refs.xpValueLabel.Text = string.format("%d/%d", math.floor(cur), math.floor(max))
	end
end

function HUDUI.UpdateLevel(lv)
	HUDUI.Refs.currentLevel = lv
	if HUDUI.Refs.levelLabel then
		HUDUI.Refs.levelLabel.Text = string.format("Lv.%s", tostring(lv))
	end
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
		SHELTER     = getIcon("WARMTH"), -- 요청에 따라 따뜻함과 동일한 아이콘 사용
	}
	
	for _, debuff in ipairs(debuffList) do
		local iconId = IconMap[debuff.id] or "rbxassetid://6034346917"
		local isBuff = (debuff.id == "WARMTH" or debuff.id == "SHELTER")

		local slot = Utils.mkFrame({
			name = debuff.id,
			size = UDim2.new(0, 26, 0, 26),
			bg = isBuff and Color3.fromRGB(20, 40, 25) or Color3.fromRGB(42, 18, 20), 
			bgT = 0.4,
			r = 6,
			stroke = 1.5,
			strokeC = isBuff and Color3.fromRGB(120, 200, 80) or C.RED,
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
			HUDUI.ShowTooltip(debuff.name or debuff.id, debuff.description or "")
		end)

		btn.MouseLeave:Connect(function()
			HUDUI.HideTooltip()
		end)
	end

	-- [정리] 누수 방지를 위해 입력 리스너 관련 코드가 Init으로 안정적으로 이전되었습니다.
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

function HUDUI.UpdateDayNightClock(dayTime, dayLength)
	local hand = HUDUI.Refs.dayNightHand
	local moon = HUDUI.Refs.dayNightMoon
	if not hand then return end

	dayLength = math.max(1, dayLength or 2400)
	local t = (tonumber(dayTime) or 0) % dayLength
	local ratio = t / dayLength
	local theta = ratio * math.pi * 2
	local radius = 48

	hand.Position = UDim2.new(
		0.5 + math.sin(theta) * (radius / 120),
		0,
		0.5 - math.cos(theta) * (radius / 120),
		0
	)

	if moon then
		local opposite = theta + math.pi
		moon.Position = UDim2.new(
			0.5 + math.sin(opposite) * (radius / 120),
			0,
			0.5 - math.cos(opposite) * (radius / 120),
			0
		)
	end

	local isDay = t < (Balance.DAY_DURATION or (dayLength * 0.75))
	hand.BackgroundColor3 = isDay and Color3.fromRGB(255, 233, 130) or Color3.fromRGB(170, 206, 255)

	if HUDUI.Refs.phaseLabel then
		HUDUI.Refs.phaseLabel.Text = isDay and "DAY" or "NIGHT"
		HUDUI.Refs.phaseLabel.TextColor3 = isDay and Color3.fromRGB(255, 223, 143) or Color3.fromRGB(190, 225, 255)
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

-- =============================================
-- Combat UI Functions (Reference Style)
-- =============================================

function HUDUI.ShowCombatUI(creatureName, level, currentHP, maxHP)
	if not HUDUI.Refs.combatUIContainer then return end
	
	-- Show container
	HUDUI.Refs.combatUIContainer.Visible = true
	
	-- Clean creature name (remove any "Lv." prefix if exists)
	local cleanName = creatureName or "?"
	cleanName = string.gsub(cleanName, "^Lv%.%d+%s*", "")
	cleanName = string.gsub(cleanName, "%s*Lv%.%d+$", "")
	
	-- Set creature name only (White)
	if HUDUI.Refs.combatBossName then
		HUDUI.Refs.combatBossName.Text = cleanName
	end
	
	-- Set creature level only (Red, separate label)
	if HUDUI.Refs.combatBossLevel then
		HUDUI.Refs.combatBossLevel.Text = string.format("Lv.%d", level or 1)
	end
	
	-- ★ Dynamically adjust level label position based on name length
	-- to avoid overlap (updated Y positions for new 200px container)
	if HUDUI.Refs.combatBossLevel then
		local nameLength = string.len(cleanName)
		if nameLength > 15 then
			-- If name is long, move level below (name: y=60, h=32, so below at y=92)
			HUDUI.Refs.combatBossLevel.Position = UDim2.new(0.5, 0, 0, 100)
			HUDUI.Refs.combatBossLevel.TextXAlignment = Enum.TextXAlignment.Center
		else
			-- Otherwise, place level to the right (y=60, same as name)
			HUDUI.Refs.combatBossLevel.Position = UDim2.new(0.5, 80, 0, 60)
			HUDUI.Refs.combatBossLevel.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
	
	-- Update HP bar
	HUDUI.UpdateCombatUI(currentHP, maxHP)
end

function HUDUI.HideCombatUI()
	if HUDUI.Refs.combatUIContainer then
		HUDUI.Refs.combatUIContainer.Visible = false
	end
end

function HUDUI.UpdateCombatUI(currentHP, maxHP)
	if not currentHP or not maxHP or maxHP <= 0 then return end
	
	local hpRatio = math.clamp(currentHP / maxHP, 0, 1)
	
	-- Update HP bar fill (always RED, no color change)
	if HUDUI.Refs.combatHPBarFill then
		HUDUI.Refs.combatHPBarFill.Size = UDim2.new(hpRatio, 0, 1, 0)
		HUDUI.Refs.combatHPBarFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60) -- Always red
	end
	
	-- Update HP text label
	if HUDUI.Refs.combatHPLabel then
		HUDUI.Refs.combatHPLabel.Text = string.format("%d / %d", math.floor(currentHP), math.floor(maxHP))
	end
end

function HUDUI.isSideMenuVisible()
	return false -- Side menu fully replaced by bottom menu row
end

function HUDUI.UpdateGold(val)
	if not HUDUI.Refs or not HUDUI.Refs.goldLabel then return end
	local goldVal = tonumber(val) or 0
	local txt = ""
	if goldVal >= 1000000 then
		txt = string.format("%.2fM G", goldVal / 1000000)
	elseif goldVal >= 1000 then
		txt = string.format("%.2fK G", goldVal / 1000)
	else
		txt = string.format("%d G", goldVal)
	end
	HUDUI.Refs.goldLabel.Text = txt
end

return HUDUI
