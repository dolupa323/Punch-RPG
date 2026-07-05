local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local Client = script.Parent.Parent
local NetClient = require(Client:WaitForChild("NetClient"))
local PlatformerInput = require(Client:WaitForChild("Controllers"):WaitForChild("PlatformerInput"))
local LocaleService = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("LocaleService"))
local RaidBossData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("RaidBossData"))

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local HUDUI = {}
local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local isSmall = isMobile
local isTutorialMinimized = false
local tutorialWantedVisible = false
local tutorialReady = false
local tutorialPulseTween = nil
local tutorialHintPulseTween = nil
local tutorialClickPulseTween = nil
local tutorialRelayoutFn = nil
local starterPackWantedVisible = false
HUDUI.LastStatus = nil
local questTokenNameCache = {}
local TOOLTIP_WIDTH = 280
local TOOLTIP_MARGIN = 14
local localPotionCooldownEnd = 0

local function formatVal(num)
	local n = tonumber(num) or 0
	if n >= 1000000000000 then
		return string.format("%.2fT", n / 1000000000000)
	elseif n >= 1000000000 then
		return string.format("%.2fB", n / 1000000000)
	elseif n >= 1000000 then
		return string.format("%.2fM", n / 1000000)
	elseif n >= 1000 then
		-- 만약 소수점이 00이면 정수로 보이도록 처리
		local val = n / 1000
		if val % 1 == 0 then
			return string.format("%dK", val)
		else
			-- 소수점 첫째 또는 둘째짜리까지 유연하게 표시
			local formatted = string.format("%.2f", val)
			formatted = string.gsub(formatted, "%.?0+$", "")
			return formatted .. "K"
		end
	else
		return tostring(math.floor(n))
	end
end

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

local function bindSlotAction(slot, actionName, actionFn)
	if not slot or not slot.click or type(actionFn) ~= "function" then
		return
	end

	slot.click.Active = true
	slot.click.Selectable = false
	slot.click.AutoButtonColor = false
	slot.click.Modal = false

	local touchHandled = false
	local label = actionName or slot.Name or "Slot"

	slot.click.MouseButton1Down:Connect(function()
		triggerScale(slot.frame)
	end)

	slot.click.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchHandled = true
			if isMobile then
				print(string.format("[HUDUI][%s] TouchDown", label))
			end
			triggerScale(slot.frame)
			actionFn()
		end
	end)

	slot.click.Activated:Connect(function()
		if touchHandled then
			touchHandled = false
			if isMobile then
				print(string.format("[HUDUI][%s] ActivatedSkippedAfterTouch", label))
			end
			return
		end
		if isMobile then
			print(string.format("[HUDUI][%s] Activated", label))
		end
		actionFn()
	end)
end

local function bindRuneSlotAction(slot, slotIndex, actionFn)
	if not slot or not slot.click or type(actionFn) ~= "function" then
		return
	end

	slot.click.Active = true
	slot.click.Selectable = false
	slot.click.AutoButtonColor = false
	slot.click.Modal = false

	local touchHandled = false
	local label = string.format("Rune%d", tonumber(slotIndex) or 0)

	slot.click.MouseButton1Down:Connect(function()
		triggerScale(slot.frame)
	end)

	slot.click.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchHandled = true
			if isMobile then
				print(string.format("[HUDUI][%s] TouchDown", label))
			end
			triggerScale(slot.frame)
			actionFn()
		end
	end)

	slot.click.Activated:Connect(function()
		if touchHandled then
			touchHandled = false
			if isMobile then
				print(string.format("[HUDUI][%s] ActivatedSkippedAfterTouch", label))
			end
			return
		end
		if isMobile then
			print(string.format("[HUDUI][%s] Activated", label))
		end
		actionFn()
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
	KILL_SLIME = {
		currentStepText = "Hunt a Slime",
		stepCommand = "Defeat 1 Slime.",
	},
	COLLECT_SLIME_MUCUS = {
		currentStepText = "Gather Slime Mucus",
		stepCommand = "Gather 10 Slime Mucus.",
	},
	CRAFT_SOFTCLUB = {
		currentStepText = "Craft a Slime Sword",
		stepCommand = "Craft a Slime Sword.",
	},
	EQUIP_SOFTCLUB = {
		currentStepText = "Equip the Slime Sword",
		stepCommand = "Open Inventory (I) or Character window and equip the crafted Slime Sword.",
	},
	DISTRIBUTE_STAT = {
		currentStepText = "Upgrade Stats",
		stepCommand = "Open Equipment (Stats) window and upgrade Attack stat by 1.",
	},
	KILL_HORNED_LARVA = {
		currentStepText = "Hunt Horned Larva",
		stepCommand = "Defeat 15 Horned Larvas.",
	},
	CRAFT_GAKCHANG = {
		currentStepText = "Craft a Hard Sword",
		stepCommand = "Craft a Hard Sword.",
	},
	ENHANCE_GAKCHANG = {
		currentStepText = "Try enhancing the Hard Sword",
		stepCommand = "Enhance the Hard Sword to +1 or higher.",
	},
	REGISTER_POTION = {
		currentStepText = "Equip potion to quickslot",
		stepCommand = "Buy an HP or MP potion, then open Inventory (I) and equip it to a consumable quickslot.",
	},
	COLLECT_STUMP_BARK = {
		currentStepText = "Gather Stump Bark",
		stepCommand = "Gather 30 Stump Barks.",
	},
	CRAFT_MOGWOLDO = {
		currentStepText = "Craft a Desert Sword",
		stepCommand = "Craft a Desert Sword.",
	},
	COMPLETED = {
		currentStepText = "You have completed all tutorial quests.",
		stepCommand = "Now proceed with the RPG loop freely.",
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
			local module = dataFolder:FindFirstChild("CreatureData")
			return module and require(module)
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

local function stripRichTextTags(text: string?): string
	if type(text) ~= "string" or text == "" then
		return ""
	end

	return (text:gsub("<.->", ""))
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
local _UIManager = nil

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
	starterPackButton = nil,
	raidBossContainer = nil,
	raidBossSizeConstraint = nil,
	raidBossName = nil,
	raidHpBarBg = nil,
	raidHpUnderFill = nil,
	raidHpBarFill = nil,
	raidHpLabel = nil,
	raidMultiplier = nil,
	raidHpBorder = nil,
	raidHpGradient = nil,
}

function HUDUI.Init(parent, UIManager, InputManager, isMobile)
	_UIManager = UIManager
	local runeFrame = nil
	local consumableFrame = nil
	-- [수정] 차단성 WaitForChild를 Init 내부로 이동하고 타임아웃 추가
	task.spawn(function()
		local Assets = ReplicatedStorage:WaitForChild("Assets", 5)
		if Assets then
			StatusIcons = Assets:WaitForChild("StatusIcons", 3)
		end
	end)

	local isSmall = isMobile 
	local actionButtonSize = isMobile and 84 or 64
	local actionButtonGap = isMobile and 8 or 10
	
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
		size = UDim2.new(0.34, 0, 0.08, 0),
		pos = UDim2.new(0.5, 0, 0.91, 0),
		anchor = Vector2.new(0.5, 1),
		bgT = 1, -- Invisible root
		parent = parent
	})
	HUDUI.Refs.mainAnchor = mainAnchor

	local mainAR = Instance.new("UIAspectRatioConstraint")
	mainAR.AspectRatio = 3.8
	mainAR.AspectType = Enum.AspectType.ScaleWithParentSize
	mainAR.DominantAxis = Enum.DominantAxis.Width
	mainAR.Parent = mainAnchor
	
	local szConstraint = Instance.new("UISizeConstraint")
	szConstraint.MinSize = Vector2.new(340, 90); szConstraint.MaxSize = Vector2.new(620, 163); szConstraint.Parent = mainAnchor
	
	local mainContainer = Utils.mkFrame({
		name = "MainHUDContainer",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = Color3.fromRGB(12, 12, 12),
		bgT = 1,
		r = 0,
		parent = mainAnchor
	})
	HUDUI.Refs.statusPanel = mainContainer

	-- Vertical stacking logic: SUM of all sub-element heights MUST EQUAL exactly 1.00 (including padding gaps)
	local mainStack = Instance.new("UIListLayout")
	mainStack.FillDirection = Enum.FillDirection.Vertical; mainStack.Padding = UDim.new(0.03, 0); mainStack.SortOrder = Enum.SortOrder.LayoutOrder
	mainStack.HorizontalAlignment = Enum.HorizontalAlignment.Center; mainStack.Parent = mainContainer

	-- 1. Stat Row (Top 19%) - Shrink width to 0.82 for narrower bar display
	local statRow = Utils.mkFrame({name = "StatRow", size = UDim2.new(0.82, 0, 0.19, 0), bgT = 1, r = 0, parent = mainContainer})
	statRow.LayoutOrder = 1
	local statHList = Instance.new("UIListLayout")
	statHList.FillDirection = Enum.FillDirection.Horizontal; statHList.HorizontalAlignment = Enum.HorizontalAlignment.Center; statHList.Padding = UDim.new(0.04, 0); statHList.Parent = statRow

	-- Health Bar (Left 40%)
	local hpSeg = Utils.mkFrame({name="HPSegment", size = UDim2.new(0.40, 0, 1, 0), bg = Color3.fromRGB(45, 15, 15), bgT=0, r=6, stroke=1, strokeC=Color3.new(1,1,1), strokeT=0, parent=statRow})
	hpSeg.LayoutOrder = 1
	local hpFill = Utils.mkFrame({name="Fill", size = UDim2.new(1, 0, 1, 0), bg = Color3.fromRGB(200, 25, 25), bgT=0, r=6, parent=hpSeg})
	local hpLabel = Utils.mkLabel({text="100/100", size = UDim2.new(0.9, 0, 0.62, 0), pos = UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), font = F.NUM, color=C.WHITE, st=1, parent=hpSeg})
	hpLabel.TextScaled = true
	HUDUI.Refs.healthBar = {container = hpSeg, fill = hpFill, label = hpLabel}

	-- Level Segment (Center 12%) 
	local lvSeg = Utils.mkFrame({name="LvSeg", size = UDim2.new(0.12, 0, 1, 0), bg = Color3.new(0,0,0), bgT=1, r=0, parent=statRow})
	lvSeg.LayoutOrder = 2
	local lvLabel = Utils.mkLabel({
		text = "<font size=\"16\">Lv.</font>1", size = UDim2.new(0.95, 0, 0.85, 0), pos = UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5),
		font = Enum.Font.GothamBlack, bold = true, color = Color3.new(1, 1, 1), st = 0, rich = true, parent = lvSeg
	})
	lvLabel.TextScaled = true
	-- Heavy contrast text outline for professional polished typography
	local lvTextStr = Instance.new("UIStroke")
	lvTextStr.Thickness = 2.5; lvTextStr.Color = Color3.new(0,0,0); lvTextStr.Parent = lvLabel
	HUDUI.Refs.levelLabel = lvLabel

	-- Mana Bar (Right 40%)
	local mpSeg = Utils.mkFrame({name="MPSegment", size = UDim2.new(0.40, 0, 1, 0), bg = Color3.fromRGB(10, 25, 45), bgT=0, r=6, stroke=1, strokeC=Color3.new(1,1,1), strokeT=0, parent=statRow})
	mpSeg.LayoutOrder = 3
	local mpFill = Utils.mkFrame({name="Fill", size = UDim2.new(1, 0, 1, 0), bg = Color3.fromRGB(0, 102, 204), bgT=0, r=6, parent=mpSeg})
	local mpLabel = Utils.mkLabel({text="100/100", size = UDim2.new(0.9, 0, 0.62, 0), pos = UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), font = F.NUM, color=C.WHITE, st=1, parent=mpSeg})
	mpLabel.TextScaled = true
	HUDUI.Refs.staminaBar = {container = mpSeg, fill = mpFill, label = mpLabel}

	-- Spacer Row (Middle-Top 8% height to increase vertical gap between HP/Mana and EXP) - Set width to 0.82 to align
	local spacerRow = Utils.mkFrame({name = "SpacerRow", size = UDim2.new(0.82, 0, 0.08, 0), bgT = 1, r = 0, parent = mainContainer})
	spacerRow.LayoutOrder = 2

	-- 2. EXP Row (Middle 10% height) - Shrink width to 0.82 to match statRow perfectly
	local expRow = Utils.mkFrame({name = "EXPRow", size = UDim2.new(0.82, 0, 0.10, 0), bg = Color3.fromRGB(20, 30, 20), bgT=0.3, r=6, stroke=1, strokeC=Color3.new(1,1,1), strokeT=0, parent = mainContainer})
	expRow.LayoutOrder = 3
	local expFill = Utils.mkFrame({name="Fill", size = UDim2.new(0, 0, 1, 0), bg = Color3.fromRGB(130, 225, 100), bgT=0.3, r=6, parent=expRow})
	HUDUI.Refs.xpBar = expFill
	local expLabel = Utils.mkLabel({text="0/0", size = UDim2.new(0.9, 0, 0.8, 0), pos = UDim2.new(0.5, 0, 0.5, 0), anchor = Vector2.new(0.5, 0.5), font = F.NUM, color = C.WHITE, st = 1, parent = expRow})
	expLabel.TextScaled = true
	HUDUI.Refs.xpValueLabel = expLabel

	-- Placeholder replaced by Consumable Hotbar

	-- 3. Left Menu Panel (Vertical layout on left edge) - Mobile Responsive Sizes
	local menuWidth = isMobile and 58 or 72
	local cellSize = isMobile and 46 or 56
	local menuHeight = isMobile and 330 or 440
	local menuPadding = isMobile and 6 or 8
	local menuY = isMobile and 80 or 100
	local toggleY = menuY + (menuHeight / 2)

	local leftMenuContainer = Utils.mkFrame({
		name = "LeftMenuContainer",
		size = UDim2.new(0, menuWidth, 0, menuHeight),
		pos = UDim2.new(0, 12, 0, menuY),
		bg = Color3.fromRGB(15, 15, 20),
		bgT = 0.55,
		r = 10,
		stroke = 1.5,
		strokeC = Color3.fromRGB(30, 45, 70), -- Blue border convention (matches Dismantle/Tutorial)
		parent = parent
	})
	HUDUI.Refs.leftMenuContainer = leftMenuContainer

	local leftList = Instance.new("UIListLayout")
	leftList.FillDirection = Enum.FillDirection.Vertical
	leftList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leftList.VerticalAlignment = Enum.VerticalAlignment.Center
	leftList.Padding = UDim.new(0, menuPadding)
	leftList.Parent = leftMenuContainer

	local function mkMenuCell(name, iconId, label, order, fn)
		local btn = Utils.mkFrame({
			name = name,
			size = UDim2.new(0, cellSize, 0, cellSize),
			bg = Color3.fromRGB(28, 28, 28),
			bgT = 0.3,
			r = 8,
			stroke = 1,
			strokeC = Color3.fromRGB(30, 45, 70), -- Blue border convention (matches Dismantle/Tutorial)
			parent = leftMenuContainer
		})
		btn.LayoutOrder = order
		
		local inner = Instance.new("ImageLabel")
		inner.Size = UDim2.new(0.45, 0, 0.45, 0)
		inner.Position = UDim2.new(0.5, 0, 0.35, 0)
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.BackgroundTransparency = 1
		inner.ScaleType = Enum.ScaleType.Fit
		inner.Image = iconId
		inner.Active = false
		inner.Parent = btn
		
		local asp = Instance.new("UIAspectRatioConstraint")
		asp.AspectRatio = 1
		asp.Parent = inner
		
		local txt = Utils.mkLabel({
			text = UILocalizer.Localize(label),
			size = UDim2.new(0.9, 0, 0.28, 0),
			pos = UDim2.new(0.5, 0, 0.78, 0),
			anchor = Vector2.new(0.5, 0.5),
			font = F.TITLE,
			color = C.WHITE,
			st = 1,
			parent = btn
		})
		txt.TextScaled = true
		txt.Active = false
		
		local clk = Instance.new("TextButton")
		clk.Size = UDim2.new(1, 0, 1, 0)
		clk.BackgroundTransparency = 1
		clk.Text = ""
		clk.ZIndex = 5
		clk.Active = true
		clk.Selectable = true
		clk.Parent = btn
		
		local sc = Instance.new("UIScale", btn)
		
		clk.MouseEnter:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(65, 65, 65)}):Play()
		end)
		clk.MouseLeave:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(28, 28, 28)}):Play()
		end)
		clk.MouseButton1Down:Connect(function()
			TweenService:Create(sc, TweenInfo.new(0.05), {Scale = 0.9}):Play()
		end)
		clk.MouseButton1Up:Connect(function()
			TweenService:Create(sc, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Scale = 1}):Play()
		end)
		clk.Activated:Connect(function()
			print(string.format("[HUDUI] Menu Cell '%s' (%s) Activated!", name, label))
			fn()
		end)
		return btn
	end

	HUDUI.Refs.InventoryTabButton = mkMenuCell("BtnInv", UIManager.getItemIcon("Icon_Inventory"), "가방", 1, function()
		print("[HUDUI] InventoryTabButton Clicked! calling UIManager.toggleInventory")
		UIManager.toggleInventory()
	end)
	HUDUI.Refs.EquipTabButton = mkMenuCell("BtnStats", UIManager.getItemIcon("Icon_Equipment"), "스탯", 2, function()
		print("[HUDUI] EquipTabButton Clicked! calling UIManager.toggleEquipment")
		UIManager.toggleEquipment()
	end)
	HUDUI.Refs.SkillTabButton = mkMenuCell("BtnRune", UIManager.getItemIcon("Icon_Skill"), "스킬", 3, function()
		print("[HUDUI] SkillTabButton Clicked! calling UIManager.toggleSkillTree")
		UIManager.toggleSkillTree()
	end)
	HUDUI.Refs.ShopTabButton = mkMenuCell("BtnPass", UIManager.getItemIcon("Icon_Shop"), "상점", 4, function()
		print("[HUDUI] ShopTabButton Clicked! calling UIManager.togglePremiumShop")
		if UIManager.togglePremiumShop then UIManager.togglePremiumShop() end
	end)
	HUDUI.Refs.QuestTabButton = mkMenuCell("BtnStats2", UIManager.getItemIcon("Icon_Quest"), "통계", 5, function()
		print("[HUDUI] QuestTabButton Clicked! calling UIManager.toggleQuest")
		if UIManager.toggleQuest then UIManager.toggleQuest() end
	end)
	mkMenuCell("BtnTrade", UIManager.getItemIcon("BtnTrade"), "경매장", 6, function()
		print("[HUDUI] BtnTrade (경매장) Clicked! calling UIManager.toggleAuctionHouse")
		if UIManager.toggleAuctionHouse then UIManager.toggleAuctionHouse() end
	end)

	-- Sidebar collapse/expand functionality (Premium Glassmorphic Design) - Mobile Responsive
	local menuOpen = true
	local toggleBtnWidth = isMobile and 20 or 24
	local toggleBtnHeight = isMobile and 48 or 56
	local openToggleX = 12 + menuWidth
	local closedToggleX = 12
	local hideMenuX = -(menuWidth + 2)

	local toggleBtn = Utils.mkFrame({
		name = "MenuToggleBtn",
		size = UDim2.new(0, toggleBtnWidth, 0, toggleBtnHeight),
		pos = UDim2.new(0, openToggleX, 0, toggleY),
		anchor = Vector2.new(0, 0.5),
		bg = Color3.fromRGB(20, 22, 30),
		bgT = 0.25,
		r = 6,
		stroke = 1.5,
		strokeC = Color3.fromRGB(30, 45, 70), -- Blue border convention (matches Dismantle/Tutorial)
		parent = parent -- Parented to screen directly so it is never clipped when sidebar is hidden
	})
	
	local toggleLabel = Utils.mkLabel({
		text = "<",
		size = UDim2.new(1, 0, 1, 0),
		font = Enum.Font.GothamBold,
		color = C.WHITE,
		parent = toggleBtn
	})
	toggleLabel.TextScaled = true
	
	local toggleClick = Instance.new("TextButton")
	toggleClick.Size = UDim2.new(1, 0, 1, 0)
	toggleClick.BackgroundTransparency = 1
	toggleClick.Text = ""
	toggleClick.ZIndex = toggleBtn.ZIndex + 5
	toggleClick.Parent = toggleBtn

	local sc = Instance.new("UIScale", toggleBtn)
	local stroke = toggleBtn:FindFirstChildOfClass("UIStroke")

	toggleClick.MouseEnter:Connect(function()
		TweenService:Create(toggleBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(35, 38, 50)}):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(60, 85, 130)}):Play()
		end
	end)
	toggleClick.MouseLeave:Connect(function()
		TweenService:Create(toggleBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(20, 22, 30)}):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(30, 45, 70)}):Play()
		end
	end)
	toggleClick.MouseButton1Down:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.05), {Scale = 0.88}):Play()
	end)
	toggleClick.MouseButton1Up:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Scale = 1}):Play()
	end)

	toggleClick.MouseButton1Click:Connect(function()
		menuOpen = not menuOpen
		
		local targetMenuX = menuOpen and 12 or hideMenuX
		local targetToggleX = menuOpen and openToggleX or closedToggleX
		local targetArrow = menuOpen and "<" or ">"
		
		toggleLabel.Text = targetArrow
		
		TweenService:Create(leftMenuContainer, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, targetMenuX, 0, menuY)
		}):Play()
		
		TweenService:Create(toggleBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, targetToggleX, 0, toggleY)
		}):Play()
	end)

	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local starterBtnPx = math.clamp(
		math.floor(viewport.X * (isSmall and 0.15 or 0.085)),
		isSmall and 72 or 86,
		isSmall and 104 or 124
	)

	local starterPackButton = Utils.mkBtn({
		name = "StarterPackButton",
		size = UDim2.new(0, starterBtnPx, 0, starterBtnPx),
		pos = UDim2.new(1, -12, 1, -(isSmall and 192 or 206)),
		anchor = Vector2.new(1, 1),
		bg = Color3.fromRGB(85, 76, 39),
		bgT = 1,
		stroke = false,
		color = C.WHITE,
		ts = isSmall and 12 or 14,
		font = F.TITLE,
		r = 12,
		z = 25,
		noHover = true,
		vis = false,
		parent = parent,
		fn = function()
			if UIManager and UIManager.promptStarterPackPurchase then
				UIManager.promptStarterPackPurchase()
			end
		end,
	})
	starterPackButton.Text = ""
	local starterPackIcon = Instance.new("ImageLabel")
	starterPackIcon.Name = "StarterPackIcon"
	starterPackIcon.Size = UDim2.new(0.72, 0, 0.72, 0)
	starterPackIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	starterPackIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	starterPackIcon.BackgroundTransparency = 1
	starterPackIcon.ScaleType = Enum.ScaleType.Fit
	starterPackIcon.Image = UIManager.getItemIcon and UIManager.getItemIcon("Icon_StarterPack") or ""
	starterPackIcon.ZIndex = starterPackButton.ZIndex + 1
	starterPackIcon.Parent = starterPackButton
	HUDUI.Refs.starterPackButton = starterPackButton

	HUDUI.Refs.hungerBar = {container = Instance.new("Frame"), fill = Instance.new("Frame"), label = Instance.new("TextLabel")}
	HUDUI.Refs.xpPctLabel = Instance.new("TextLabel")
	HUDUI.Refs.bottomEdge = mainContainer 
	HUDUI.Refs.statPointAlert = Utils.mkLabel({text = "▲ UP", size = UDim2.new(0.8, 0, 0.25, 0), pos = UDim2.new(1, 2, 0, 0), font = F.TITLE, color = C.GOLD, vis = false, parent = lvSeg})
	HUDUI.Refs.statPointAlert.TextScaled = true

	-- 퀘스트 통합 패널 — 반응형 너비
	local vp0 = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
	local QUEST_PANEL_W = math.clamp(math.floor(vp0.X * (isSmall and 0.52 or 0.22)), isSmall and 200 or 200, isSmall and 280 or 260)

	local tutorialFrame = Utils.mkFrame({
		name = "TutorialPanel",
		size = UDim2.new(0, QUEST_PANEL_W, 0, 82),
		pos = UDim2.new(1, -12, 0, isSmall and 180 or 220),
		anchor = Vector2.new(1, 0),
		bg = Color3.fromRGB(15, 20, 30),
		bgT = 0.2,
		r = 8,
		stroke = 1.5,
		strokeC = Color3.fromRGB(60, 85, 130),
		strokeT = 0.2,
		vis = false,
		parent = parent,
	})
	tutorialFrame.ClipsDescendants = true  -- 최소화 시 자식 요소 자동 숨김
	
	local relayoutTutorialPanel -- Forward declaration
	
	local function updateTutorialMinimize()
		-- [Fix] 하드코딩된 큰 수치 제거 및 동적 너비 유지
		local vp = workspace.CurrentCamera.ViewportSize
		local panelWidth
		if isTutorialMinimized then
			HUDUI.Refs.tutorialTitle.Text = UILocalizer.Localize("퀘스트")
			local titleText = HUDUI.Refs.tutorialTitle.Text
			local titleFontSize = HUDUI.Refs.tutorialTitle.TextSize
			local font = HUDUI.Refs.tutorialTitle.Font
			local bounds = TextService:GetTextSize(titleText, titleFontSize, (font == Enum.Font.Unknown or font == Enum.Font.Custom) and Enum.Font.Gotham or font, Vector2.new(1000, 1000))
			panelWidth = math.max(80, bounds.X + 54)
			tutorialFrame.Size = UDim2.new(0, panelWidth, 0, 40)
		else
			panelWidth = math.floor(vp.X * (isSmall and 0.35 or 0.22))
			panelWidth = math.clamp(panelWidth, isSmall and 220 or 280, isSmall and 280 or 360)
			tutorialFrame.Size = UDim2.new(0, panelWidth, 0, tutorialFrame.Size.Y.Offset)
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

	HUDUI.Refs.tutorialFrame = tutorialFrame

	-- ─── 퀘스트 패널 헤더 + 최소화 버튼 ────────────────────────────────
	local isQuestPanelMinimized = false
	local QUEST_HEADER_H = 28

	local questPanelHeader = Utils.mkLabel({
		name = "QuestPanelHeader",
		text = "퀘스트",
		size = UDim2.new(1, -44, 0, QUEST_HEADER_H),
		pos = UDim2.new(0, 10, 0, 0),
		ax = Enum.TextXAlignment.Left,
		font = F.TITLE,
		ts = 13,
		color = Color3.fromRGB(160, 190, 255),
		parent = tutorialFrame,
	})

	-- 최소화/확대 토글 버튼 (-/+)
	local questMinimizeBtn = Instance.new("TextButton")
	questMinimizeBtn.Name = "QuestMinimizeBtn"
	questMinimizeBtn.Size = UDim2.new(0, 24, 0, 24)
	questMinimizeBtn.Position = UDim2.new(1, -30, 0, 2)
	questMinimizeBtn.BackgroundColor3 = Color3.fromRGB(30, 45, 80)
	questMinimizeBtn.BorderSizePixel = 0
	questMinimizeBtn.Text = "-"
	questMinimizeBtn.Font = Enum.Font.GothamBold
	questMinimizeBtn.TextSize = 18
	questMinimizeBtn.TextColor3 = Color3.fromRGB(160, 190, 255)
	questMinimizeBtn.AutoButtonColor = false
	questMinimizeBtn.ZIndex = 60
	questMinimizeBtn.Parent = tutorialFrame
	Instance.new("UICorner", questMinimizeBtn).CornerRadius = UDim.new(0, 4)

	local function _setQuestPanelMinimized(minimized)
		isQuestPanelMinimized = minimized
		questMinimizeBtn.Text = minimized and "+" or "-"

		local entry   = HUDUI.Refs.tutorialEntry
		local divider = HUDUI.Refs.sqDivider
		local section = HUDUI.Refs.sqSection

		if entry   then entry.Visible   = not minimized end
		if divider then divider.Visible = not minimized end
		if section then section.Visible = not minimized end

		if minimized then
			tutorialFrame.Size = UDim2.new(tutorialFrame.Size.X.Scale, tutorialFrame.Size.X.Offset, 0, QUEST_HEADER_H + 4)
		else
			if tutorialRelayoutFn then tutorialRelayoutFn() end
		end
	end

	questMinimizeBtn.MouseButton1Click:Connect(function()
		_setQuestPanelMinimized(not isQuestPanelMinimized)
	end)
	HUDUI.Refs.questMinimizeBtn = questMinimizeBtn
	-- ──────────────────────────────────────────────────────────────────

	-- 튜토리얼 전용 서브프레임 — 펄스/클릭 이벤트 격리
	local tutorialEntry = Instance.new("Frame")
	tutorialEntry.Name = "TutorialEntry"
	tutorialEntry.Size = UDim2.new(1, 0, 0, 60)
	tutorialEntry.Position = UDim2.new(0, 0, 0, 26)
	tutorialEntry.BackgroundColor3 = Color3.fromRGB(20, 28, 45)
	tutorialEntry.BackgroundTransparency = 0.35
	tutorialEntry.BorderSizePixel = 0
	tutorialEntry.ClipsDescendants = false
	tutorialEntry.Parent = tutorialFrame
	Instance.new("UICorner", tutorialEntry).CornerRadius = UDim.new(0, 6)
	-- 튜토리얼 전용 UIStroke (펄스 애니메이션 여기에만 적용)
	local tutorialEntryStroke = Instance.new("UIStroke")
	tutorialEntryStroke.Name = "TutorialEntryStroke"
	tutorialEntryStroke.Color = Color3.fromRGB(60, 85, 130)
	tutorialEntryStroke.Thickness = 0  -- 평소엔 숨김
	tutorialEntryStroke.Parent = tutorialEntry
	HUDUI.Refs.tutorialEntry = tutorialEntry
	HUDUI.Refs.tutorialEntryStroke = tutorialEntryStroke

	-- ── 사이드퀘스트와 동일한 레이아웃: 제목 → 진행텍스트 → 진행바 ──

	-- 퀘스트 제목 (GothamBold 13, white) — "[ 튜토리얼 ] 6/12"
	HUDUI.Refs.tutorialTitle = Utils.mkLabel({
		name = "TutorialTitle",
		text = "[ 튜토리얼 ]",
		size = UDim2.new(1, 0, 0, 16),
		pos = UDim2.new(0, 0, 0, 0),
		ax = Enum.TextXAlignment.Left,
		font = F.TITLE,
		ts = 13,
		color = C.WHITE,
		parent = tutorialEntry,
	})

	-- MinimizeBtn 제거 (통합 패널에서는 미니마이즈 불필요)
	local minimizeBtn = nil
	HUDUI.Refs.minimizeBtn = minimizeBtn

	-- 진행 텍스트 (Gotham 11, gray) — "애벌레 5마리를 처치하세요. 0/5"
	HUDUI.Refs.tutorialStep = Utils.mkLabel({
		name = "TutorialStep",
		text = "",
		size = UDim2.new(1, 0, 0, 14),
		pos = UDim2.new(0, 0, 0, 19),
		ax = Enum.TextXAlignment.Left,
		ay = Enum.TextYAlignment.Top,
		wrap = true,
		rich = false,
		ts = 11,
		color = Color3.fromRGB(160, 160, 160),
		parent = tutorialEntry,
	})

	-- 진행 바 배경
	local tutBarBg = Instance.new("Frame")
	tutBarBg.Name = "TutBarBg"
	tutBarBg.Size = UDim2.new(1, 0, 0, 5)
	tutBarBg.Position = UDim2.new(0, 0, 0, 36)
	tutBarBg.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
	tutBarBg.BorderSizePixel = 0
	tutBarBg.ZIndex = 5
	tutBarBg.Parent = tutorialEntry
	Instance.new("UICorner", tutBarBg).CornerRadius = UDim.new(1, 0)

	local tutBarFill = Instance.new("Frame")
	tutBarFill.Name = "TutBarFill"
	tutBarFill.Size = UDim2.new(0, 0, 1, 0)
	tutBarFill.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
	tutBarFill.BorderSizePixel = 0
	tutBarFill.ZIndex = 6
	tutBarFill.Parent = tutBarBg
	Instance.new("UICorner", tutBarFill).CornerRadius = UDim.new(1, 0)

	HUDUI.Refs.tutorialBarBg = tutBarBg
	HUDUI.Refs.tutorialBarFill = tutBarFill

	-- 숨김 처리용 호환 ref (기존 코드 에러 방지)
	HUDUI.Refs.tutorialProgress = Utils.mkLabel({ name="TutorialProgress", text="", size=UDim2.new(0,0,0,0), vis=false, parent=tutorialEntry })
	HUDUI.Refs.tutorialReward   = Utils.mkLabel({ name="TutorialReward",   text="", size=UDim2.new(0,0,0,0), vis=false, parent=tutorialEntry })

	HUDUI.Refs.tutorialReadyHint = Utils.mkLabel({
		name = "TutorialReadyHint",
		text = "클릭하여 완료",
		size = UDim2.new(1, 0, 0, 12),
		pos = UDim2.new(0, 0, 0, 43),
		ax = Enum.TextXAlignment.Right,
		ts = 10,
		font = F.TITLE,
		color = Color3.fromRGB(110, 140, 200),
		vis = false,
		parent = tutorialEntry,
	})

	local tutorialCompleteBtn = Utils.mkBtn({
		name = "TutorialCompleteBtn",
		text = "완료",
		size = UDim2.new(0, 75, 0, 26),
		pos = UDim2.new(1, -10, 1, -8),
		anchor = Vector2.new(1, 1),
		bg = Color3.fromRGB(25, 35, 55),
		bgT = 0.3,
		stroke = 1,
		strokeC = Color3.fromRGB(60, 85, 130),
		strokeT = 0.2,
		r = 6,
		ts = 13,
		font = F.TITLE,
		color = Color3.fromRGB(255, 220, 120),
		fn = function()
			if UIManager and UIManager.requestTutorialStepComplete then
				UIManager.requestTutorialStepComplete()
			end
		end,
		parent = tutorialEntry,
	})
	HUDUI.Refs.tutorialCompleteBtn = tutorialCompleteBtn

	-- tutorialClickArea: tutorialEntry 범위만 커버 (사이드퀘스트 영역 제외)
	local tutorialClickArea = Instance.new("TextButton")
	tutorialClickArea.Name = "TutorialClickArea"
	tutorialClickArea.Size = UDim2.new(1, 0, 1, 0)
	tutorialClickArea.Position = UDim2.new(0, 0, 0, 0)
	tutorialClickArea.BackgroundTransparency = 1
	tutorialClickArea.BackgroundColor3 = C.GOLD
	tutorialClickArea.Text = ""
	tutorialClickArea.AutoButtonColor = false
	tutorialClickArea.ZIndex = 40
	tutorialClickArea.Parent = tutorialEntry
	tutorialClickArea.MouseButton1Click:Connect(function()
		if tutorialReady and UIManager and UIManager.requestTutorialStepComplete then
			UIManager.requestTutorialStepComplete()
		end
	end)
	HUDUI.Refs.tutorialClickArea = tutorialClickArea

	-- 사이드퀘스트와 동일: 항목 고정 높이 56px
	local TUTORIAL_ENTRY_H = 56
	local QUEST_HEADER_H_CONST = 28

	relayoutTutorialPanel = function()
		if not (HUDUI.Refs.tutorialFrame and HUDUI.Refs.tutorialEntry) then return end

		local panel = HUDUI.Refs.tutorialFrame
		local entry = HUDUI.Refs.tutorialEntry
		local isTutorialDone = (HUDUI.LastStatus or {}).completed

		if isTutorialDone then
			-- 튜토리얼 완료: 엔트리 숨기고 패널 높이를 헤더만큼으로 줄임
			entry.Visible = false
			panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, QUEST_HEADER_H_CONST + 4)
			return
		end

		entry.Visible = not isQuestPanelMinimized
		entry.Position = UDim2.new(0, 8, 0, QUEST_HEADER_H_CONST + 2)
		entry.Size = UDim2.new(1, -16, 0, TUTORIAL_ENTRY_H)

		local panelH = QUEST_HEADER_H_CONST + 2 + TUTORIAL_ENTRY_H + 6
		panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, panelH)

		HUDUI.Refs.tutorialReward.Visible = false
		HUDUI.Refs.tutorialProgress.Visible = false
		if HUDUI.Refs.tutorialCompleteBtn then HUDUI.Refs.tutorialCompleteBtn.Visible = false end
	end
	
	-- ─── 사이드퀘스트: tutorialFrame 내부에 통합 ────────────────────────
	-- 구분선 + 사이드퀘스트 항목들을 tutorialFrame 안에 직접 추가
	-- relayoutTutorialPanel이 총 높이를 재계산해서 패널을 늘려줌

	local sqDivider = Instance.new("Frame")
	sqDivider.Name = "SQDivider"
	sqDivider.Size = UDim2.new(1, -16, 0, 1)
	sqDivider.BackgroundColor3 = Color3.fromRGB(60, 85, 130)
	sqDivider.BorderSizePixel = 0
	sqDivider.Visible = false
	sqDivider.ZIndex = 3
	sqDivider.Parent = tutorialFrame
	HUDUI.Refs.sqDivider = sqDivider

	local sqSection = Instance.new("Frame")
	sqSection.Name = "SQSection"
	sqSection.Size = UDim2.new(1, 0, 0, 0)
	sqSection.BackgroundTransparency = 1
	sqSection.AutomaticSize = Enum.AutomaticSize.Y
	sqSection.Visible = false
	sqSection.ZIndex = 3
	sqSection.Parent = tutorialFrame
	HUDUI.Refs.sqSection = sqSection

	local sqSectionLayout = Instance.new("UIListLayout")
	sqSectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sqSectionLayout.Padding = UDim.new(0, 6)
	sqSectionLayout.Parent = sqSection

	local sideQuestEntries = {}  -- [id] = { frame, data }

	-- relayoutTutorialPanel 확장: 사이드퀘스트 섹션을 tutorialEntry 아래에 배치
	local _coreRelayout = relayoutTutorialPanel
	relayoutTutorialPanel = function()
		_coreRelayout()

		local panel = HUDUI.Refs.tutorialFrame
		if not panel then return end

		local hasSideQuests = next(sideQuestEntries) ~= nil
		sqDivider.Visible = hasSideQuests and not isQuestPanelMinimized
		sqSection.Visible = hasSideQuests and not isQuestPanelMinimized

		if not hasSideQuests then return end

		-- tutorialEntry까지 쌓인 높이 아래에 구분선 + 섹션 배치
		local baseH = panel.Size.Y.Offset

		sqDivider.Size = UDim2.new(1, -16, 0, 1)
		sqDivider.Position = UDim2.new(0, 8, 0, baseH + 4)

		sqSection.Position = UDim2.new(0, 8, 0, baseH + 10)
		sqSection.Size = UDim2.new(1, -16, 0, 0)

		-- sqSection UIPadding
		if not sqSection:FindFirstChild("UIPadding") then
			local sqPad = Instance.new("UIPadding")
			sqPad.PaddingBottom = UDim.new(0, 6)
			sqPad.Parent = sqSection
		end

		task.defer(function()
			if not panel or not panel.Parent then return end
			local sqH = sqSection.AbsoluteSize.Y
			panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, baseH + 14 + math.max(sqH, 0))
		end)
	end
	tutorialRelayoutFn = relayoutTutorialPanel

	-- 사이드퀘스트 항목 빌더 (tutorialFrame 안 섹션에 추가)
	local function _buildSQEntry(id, data)
		local isDone    = data.done
		local hasCount  = (data.required ~= nil and data.required > 0)
		local progress  = hasCount and math.clamp((data.current or 0) / data.required, 0, 1) or (isDone and 1 or 0)

		-- 표시할 진행 텍스트 결정
		local progText
		if isDone then
			progText = data.doneText or "완료! NPC에게 보고하세요."
		elseif hasCount then
			local label = data.countLabel or "진행"
			progText = string.format("%s: %d / %d", label, data.current or 0, data.required)
		else
			progText = data.desc or ""
		end

		local entry = Instance.new("Frame")
		entry.Name = "SQ_" .. tostring(id)
		entry.Size = UDim2.new(1, 0, 0, 0)
		entry.AutomaticSize = Enum.AutomaticSize.Y
		entry.BackgroundTransparency = 1
		entry.BorderSizePixel = 0
		entry.LayoutOrder = id
		entry.ZIndex = 4

		local layout = Instance.new("UIListLayout", entry)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 3)

		-- 퀘스트 이름
		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0, 0)
		titleLbl.AutomaticSize = Enum.AutomaticSize.Y
		titleLbl.BackgroundTransparency = 1
		titleLbl.Text = data.title or ""
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.TextSize = 13
		titleLbl.TextColor3 = isDone and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(230, 230, 230)
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextWrapped = true
		titleLbl.LayoutOrder = 1
		titleLbl.ZIndex = 5
		titleLbl.Parent = entry

		-- 진행 설명 텍스트
		local progLbl = Instance.new("TextLabel")
		progLbl.Size = UDim2.new(1, 0, 0, 0)
		progLbl.AutomaticSize = Enum.AutomaticSize.Y
		progLbl.BackgroundTransparency = 1
		progLbl.Text = progText
		progLbl.Font = Enum.Font.Gotham
		progLbl.TextSize = 11
		progLbl.TextColor3 = isDone and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(160, 160, 160)
		progLbl.TextXAlignment = Enum.TextXAlignment.Left
		progLbl.TextWrapped = true
		progLbl.LayoutOrder = 2
		progLbl.ZIndex = 5
		progLbl.Parent = entry

		-- 진행 바 (수치 있을 때만 표시)
		if hasCount or isDone then
			local barBg = Instance.new("Frame")
			barBg.Size = UDim2.new(1, 0, 0, 5)
			barBg.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
			barBg.BorderSizePixel = 0
			barBg.LayoutOrder = 3
			barBg.ZIndex = 5
			barBg.Parent = entry
			Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

			local barFill = Instance.new("Frame")
			barFill.Size = UDim2.new(progress, 0, 1, 0)
			barFill.BackgroundColor3 = isDone and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(255, 190, 30)
			barFill.BorderSizePixel = 0
			barFill.ZIndex = 6
			barFill.Parent = barBg
			Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
		end

		-- 하단 여백
		local spacer = Instance.new("Frame")
		spacer.Size = UDim2.new(1, 0, 0, 4)
		spacer.BackgroundTransparency = 1
		spacer.LayoutOrder = 4
		spacer.Parent = entry

		return entry
	end

	function HUDUI.UpdateSideQuest(id, data)
		if sideQuestEntries[id] then
			sideQuestEntries[id]:Destroy()
			sideQuestEntries[id] = nil
		end
		if not data or not data.active then
			-- tutorialFrame 보이게 하기 위해 퀘스트 패널도 visible 유지 필요할 수 있음
			relayoutTutorialPanel()
			return
		end
		-- tutorialFrame이 안 보이면 사이드퀘스트 때문에 보이게 함
		tutorialFrame.Visible = true
		local entry = _buildSQEntry(id, data)
		entry.Parent = sqSection
		sideQuestEntries[id] = entry
		task.defer(relayoutTutorialPanel)
	end

	function HUDUI.RemoveSideQuest(id)
		if sideQuestEntries[id] then
			sideQuestEntries[id]:Destroy()
			sideQuestEntries[id] = nil
		end
		-- 사이드퀘스트가 없고 튜토리얼도 없으면 패널 숨김
		if next(sideQuestEntries) == nil and not (HUDUI.LastStatus and not HUDUI.LastStatus.completed) then
			tutorialFrame.Visible = false
		end
		task.defer(relayoutTutorialPanel)
	end
	-- ──────────────────────────────────────────────────────────────────

	-- Keep tutorial panel/text responsive with actual viewport size.
	local function updateTutorialLayout()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local vp = camera.ViewportSize

		-- 반응형 폰트 크기
		local titleSize = isSmall and 12 or 13
		local bodySize  = isSmall and 10 or 11
		HUDUI.Refs.tutorialTitle.TextSize = titleSize
		HUDUI.Refs.tutorialStep.TextSize  = bodySize
		if HUDUI.Refs.tutorialProgress then HUDUI.Refs.tutorialProgress.TextSize = bodySize end
		if HUDUI.Refs.tutorialReward   then HUDUI.Refs.tutorialReward.TextSize   = bodySize end

		-- 반응형 패널 너비 (모바일: 화면의 52%, 데스크탑: 22%, 최대 260px)
		local panelWidth = math.clamp(
			math.floor(vp.X * (isSmall and 0.52 or 0.22)),
			isSmall and 200 or 200,
			isSmall and 280 or 260
		)
		tutorialFrame.Size = UDim2.new(0, panelWidth, 0, tutorialFrame.Size.Y.Offset)
		tutorialFrame.Position = UDim2.new(1, -12, 0, isSmall and 180 or 220)

		if HUDUI.Refs.tutorialCompleteBtn then
			HUDUI.Refs.tutorialCompleteBtn.Size = UDim2.new(0, 60, 0, 22)
			HUDUI.Refs.tutorialCompleteBtn.TextSize = 11
		end
		if HUDUI.Refs.tutorialReadyHint then
			HUDUI.Refs.tutorialReadyHint.TextSize = 10
		end

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
		local ShopCtrl = require(Controllers:WaitForChild("ShopController"))
		if ShopCtrl and ShopCtrl.getGold then HUDUI.UpdateGold(ShopCtrl.getGold()) end
	end)

	-- 2. Usable Hotbar (Dynamically bonded to the Main HUD's right periphery)
	local hotbarFrame = Utils.mkFrame({
		name = "HotbarFrame",
		size = UDim2.new(0.12, 0, 2.3, 0), 
		pos = UDim2.new(0, 0, 0, 0), -- Will be dynamically calculated below to avoid boundary clicks blocking
		anchor = Vector2.new(0, 1), 
		bgT = 1,
		vis = false, -- [HOTBAR REMOVED] 핫바 UI 완전 비활성화 및 숨김
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
		numLabel.ZIndex = slot.icon.ZIndex + 10 -- 아이템 아이콘 위로 ZIndex 레이어 보정
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
	
	-- 4. Consumable Hotbar (1, 2, 3) - Positioned dynamically slightly above the right of the Mana bar
	local consumableQuickslots = { "", "", "" }
	HUDUI.ConsumableQuickslots = consumableQuickslots

	consumableFrame = Utils.mkFrame({
		name = "ConsumableHotbarFrame",
		size = UDim2.new(1, 0, 0.54, 0),
		pos = UDim2.new(0, 0, 0, 0),
		anchor = Vector2.new(0, 0),
		bgT = 1,
		parent = mainContainer
	})
	consumableFrame.LayoutOrder = 5
	HUDUI.Refs.consumableFrame = consumableFrame

	local consumableHList = Instance.new("UIListLayout")
	consumableHList.FillDirection = Enum.FillDirection.Horizontal
	consumableHList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	consumableHList.VerticalAlignment = Enum.VerticalAlignment.Center
	consumableHList.Padding = UDim.new(0, 8)
	consumableHList.SortOrder = Enum.SortOrder.LayoutOrder
	consumableHList.Parent = consumableFrame

	HUDUI.Refs.consumableSlots = {}
	local consumableKeys = {"1", "2", "3"}

	for i, keyName in ipairs(consumableKeys) do
		local slot = Utils.mkSlot({
			name = "ConsumableSlot_"..keyName,
			size = UDim2.new(0, 48, 0, 48),
			bg = C.BG_SLOT, bgT = 0.4, r = 6, parent = consumableFrame
		})
		slot.frame.LayoutOrder = i -- descending: 1 is top, 2 is middle, 3 is bottom
		
		local keyLabel = Utils.mkLabel({
			text = keyName, size = UDim2.new(0.4, 0, 0.4, 0), pos = UDim2.new(0.06, 0, 0.06, 0),
			font = F.TITLE, color = C.WHITE, ax = Enum.TextXAlignment.Left, ay = Enum.TextYAlignment.Top, st = 1, parent = slot.frame
		})
		keyLabel.TextScaled = true
		keyLabel.ZIndex = slot.icon.ZIndex + 10

		local clkBtn = Instance.new("TextButton")
		clkBtn.Size = UDim2.new(1, 0, 1, 0)
		clkBtn.BackgroundTransparency = 1
		clkBtn.Text = ""
		clkBtn.ZIndex = slot.frame.ZIndex + 5
		clkBtn.Parent = slot.frame
		
		-- 드래그앤드랍: 소모품 슬롯 간 이동
		local dragStartPos = nil
		local dragSlotIdx = i
		local consumableGhost = nil
		local moveConn = nil

		local function destroyGhost()
			if consumableGhost then
				consumableGhost:Destroy()
				consumableGhost = nil
			end
			if moveConn then
				moveConn:Disconnect()
				moveConn = nil
			end
		end

		local function createGhost(itemId)
			destroyGhost()
			local uiScale = parent:FindFirstChildOfClass("UIScale")
			local scale = uiScale and uiScale.Scale or 1
			consumableGhost = Instance.new("Frame")
			consumableGhost.Name = "ConsumableDragGhost"
			consumableGhost.Size = UDim2.new(0, 60, 0, 60)
			consumableGhost.BackgroundColor3 = Color3.fromRGB(40, 42, 48)
			consumableGhost.BackgroundTransparency = 0.2
			consumableGhost.BorderSizePixel = 0
			consumableGhost.ZIndex = 3000
			consumableGhost.Parent = parent
			local gc = Instance.new("UICorner")
			gc.CornerRadius = UDim.new(0, 8)
			gc.Parent = consumableGhost
			local gs = Instance.new("UIStroke")
			gs.Color = Color3.fromRGB(255, 215, 0)
			gs.Thickness = 2
			gs.Parent = consumableGhost
			local gi = Instance.new("ImageLabel")
			gi.Size = UDim2.new(0.8, 0, 0.8, 0)
			gi.Position = UDim2.new(0.1, 0, 0.1, 0)
			gi.BackgroundTransparency = 1
			gi.Image = _UIManager and _UIManager.getItemIcon and _UIManager.getItemIcon(itemId) or ""
			gi.ScaleType = Enum.ScaleType.Fit
			gi.ZIndex = 3001
			gi.Parent = consumableGhost
			-- 마우스 추적
			local mp = UserInputService:GetMouseLocation()
			consumableGhost.Position = UDim2.new(0, mp.X / scale - 30, 0, mp.Y / scale - 30)
			moveConn = UserInputService.InputChanged:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
					local p = UserInputService:GetMouseLocation()
					if consumableGhost then
						consumableGhost.Position = UDim2.new(0, p.X / scale - 30, 0, p.Y / scale - 30)
					end
				end
			end)
		end

		clkBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragStartPos = UserInputService:GetMouseLocation()
				HUDUI._consumableDragStart = dragSlotIdx
				-- ghost는 일정 거리 이상 이동 후 생성 (threshold 체크용 delayed spawn)
				local startSnap = dragStartPos
				task.spawn(function()
					while dragStartPos do
						local cur = UserInputService:GetMouseLocation()
						if (cur - startSnap).Magnitude >= 10 then
							local itemId = consumableQuickslots[dragSlotIdx]
							if itemId and itemId ~= "" then
								createGhost(itemId)
							end
							break
						end
						task.wait(0.02)
					end
				end)
			end
		end)
		clkBtn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local moved = dragStartPos and (UserInputService:GetMouseLocation() - dragStartPos).Magnitude or 0
				destroyGhost()
				if moved < 10 then
					HUDUI.UseConsumableQuickslot(i)
				else
					-- 드래그앤드랍: 다른 소모품 슬롯으로 이동
					local DragDropController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("DragDropController"))
					DragDropController.handleConsumableDrop()
				end
				HUDUI._consumableDragStart = nil
				dragStartPos = nil
			end
		end)
		
		-- [추가] 포션용 쿨타임 오버레이
		local cdOverlay = Instance.new("Frame")
		cdOverlay.Name = "CooldownOverlay"
		cdOverlay.Size = UDim2.new(1, 0, 1, 0)
		cdOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		cdOverlay.BackgroundTransparency = 0.5
		cdOverlay.Visible = false
		cdOverlay.ZIndex = slot.frame.ZIndex + 2
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = cdOverlay
		cdOverlay.Parent = slot.frame
		
		local cdLabel = Utils.mkLabel({
			name = "CooldownText",
			text = "0.0", size = UDim2.new(1, 0, 1, 0),
			font = F.TITLE, color = C.WHITE, st = 1, parent = cdOverlay
		})
		cdLabel.TextScaled = true
		cdLabel.ZIndex = cdOverlay.ZIndex + 1
		
		slot.cdOverlay = cdOverlay
		slot.cdLabel = cdLabel
		
		HUDUI.Refs.consumableSlots[i] = slot
	end

	-- ── 마을 귀환 버튼 (1,2,3 슬롯과 간격 두고 우측 배치) ─────────────
	do
		local VILLAGE_POS = Vector3.new(-35.721, 230, 253.348)
		local COOLDOWN_SEC = 10
		local returnCooling = false
		local TweenS = game:GetService("TweenService")

		-- 1,2,3 슬롯과 시각적 분리를 위한 빈 스페이서
		local spacer = Instance.new("Frame")
		spacer.Name = "VillageReturnSpacer"
		spacer.Size = UDim2.new(0, 16, 0, 48)
		spacer.BackgroundTransparency = 1
		spacer.LayoutOrder = 4
		spacer.Parent = consumableFrame

		-- 귀환 버튼 (넓게, 텍스트 명확하게)
		local returnBtn = Instance.new("TextButton")
		returnBtn.Name = "VillageReturnBtn"
		returnBtn.Size = UDim2.new(0, 72, 0, 48)
		returnBtn.BackgroundColor3 = Color3.fromRGB(22, 55, 35)
		returnBtn.BackgroundTransparency = 0.15
		returnBtn.BorderSizePixel = 0
		returnBtn.Text = ""
		returnBtn.LayoutOrder = 5
		returnBtn.ZIndex = 5
		returnBtn.Parent = consumableFrame
		local rbCorner = Instance.new("UICorner")
		rbCorner.CornerRadius = UDim.new(0, 8)
		rbCorner.Parent = returnBtn
		local rbStroke = Instance.new("UIStroke")
		rbStroke.Color = Color3.fromRGB(70, 190, 100)
		rbStroke.Thickness = 1.8
		rbStroke.Parent = returnBtn

		-- "마을귀환" 텍스트 (버튼 중앙, 크게)
		local rbLabel = Instance.new("TextLabel")
		rbLabel.Size = UDim2.new(1, -6, 1, -6)
		rbLabel.Position = UDim2.new(0, 3, 0, 3)
		rbLabel.BackgroundTransparency = 1
		rbLabel.Text = "마을귀환"
		rbLabel.Font = Enum.Font.GothamBold
		rbLabel.TextScaled = true
		rbLabel.TextColor3 = Color3.fromRGB(170, 255, 185)
		rbLabel.TextStrokeColor3 = Color3.fromRGB(0, 60, 20)
		rbLabel.TextStrokeTransparency = 0.2
		rbLabel.TextXAlignment = Enum.TextXAlignment.Center
		rbLabel.TextYAlignment = Enum.TextYAlignment.Center
		rbLabel.ZIndex = 6
		rbLabel.Parent = returnBtn

		-- 쿨타임 오버레이
		local rbCdOverlay = Instance.new("Frame")
		rbCdOverlay.Size = UDim2.new(1, 0, 1, 0)
		rbCdOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		rbCdOverlay.BackgroundTransparency = 0.4
		rbCdOverlay.Visible = false
		rbCdOverlay.ZIndex = 7
		rbCdOverlay.Parent = returnBtn
		Instance.new("UICorner", rbCdOverlay).CornerRadius = UDim.new(0, 8)
		local rbCdLabel = Instance.new("TextLabel")
		rbCdLabel.Size = UDim2.new(1, 0, 1, 0)
		rbCdLabel.BackgroundTransparency = 1
		rbCdLabel.Text = ""
		rbCdLabel.Font = Enum.Font.GothamBold
		rbCdLabel.TextScaled = true
		rbCdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		rbCdLabel.TextStrokeTransparency = 0.3
		rbCdLabel.ZIndex = 8
		rbCdLabel.Parent = rbCdOverlay

		local TeleportFade = require(script.Parent.Parent:WaitForChild("Utils"):WaitForChild("TeleportFade"))

		local function doReturn()
			if returnCooling then return end
			local char = game:GetService("Players").LocalPlayer.Character
			if not char then return end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health <= 0 then return end

			returnCooling = true

			task.spawn(function()
				-- 서버에 텔레포트 요청 (페이드아웃+로딩+이동+페이드인 서버가 처리)
				NetClient.Request("Fountain.Return.Request", {})
				-- 마법사 퀘스트 연동
				NetClient.Request("Magician.VillageReturn.Event", {})
			end)
			rbCdOverlay.Visible = true
			rbLabel.TextColor3 = Color3.fromRGB(100, 160, 110)
			TweenS:Create(returnBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(12, 28, 18)}):Play()

			local remain = COOLDOWN_SEC
			while remain > 0 do
				rbCdLabel.Text = tostring(remain)
				task.wait(1)
				remain = remain - 1
			end

			rbCdOverlay.Visible = false
			returnCooling = false
			rbLabel.TextColor3 = Color3.fromRGB(170, 255, 185)
			TweenS:Create(returnBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(22, 55, 35)}):Play()
		end

		returnBtn.MouseButton1Click:Connect(doReturn)

		returnBtn.MouseEnter:Connect(function()
			if not returnCooling then
				TweenS:Create(returnBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(35, 85, 52)}):Play()
				TweenS:Create(rbStroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(100, 230, 130)}):Play()
			end
		end)
		returnBtn.MouseLeave:Connect(function()
			if not returnCooling then
				TweenS:Create(returnBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(22, 55, 35)}):Play()
				TweenS:Create(rbStroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(70, 190, 100)}):Play()
			end
		end)

		HUDUI.Refs.villageReturnBtn = returnBtn
	end

	-- UI Assets Folder check
	local uiAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI")
	local function getIconImage(name)
		if not uiAssets then return nil end
		local asset = uiAssets:FindFirstChild(name)
		if not asset then return nil end
		if asset:IsA("ImageLabel") or asset:IsA("ImageAsset") then
			return asset.Image
		elseif asset:IsA("Decal") then
			return asset.Texture
		end
		return nil
	end

	-- 5. Mobile/Universal Attack Button (Styled to match other slots)
	local attackSlot = Utils.mkSlot({
		name = "AttackSlot",
		size = UDim2.new(0, actionButtonSize, 0, actionButtonSize),
		bg = C.BG_SLOT,
		bgT = 0.4,
		r = 6,
		z = 10,
		parent = parent
	})
	
	local attackIconId = getIconImage("Attack")
	if attackIconId and attackIconId ~= "" then
		attackSlot.icon.Image = attackIconId
		attackSlot.icon.Visible = true
	else
		attackSlot.icon.Visible = false
	end
	
	local attackLabel = Utils.mkLabel({
		text = attackIconId and "" or UILocalizer.Localize("공격"),
		size = UDim2.new(1, 0, 1, 0),
		font = F.TITLE,
		color = C.WHITE,
		ts = 13,
		z = 12,
		parent = attackSlot.frame
	})
	attackLabel.TextScaled = true

	bindSlotAction(attackSlot, "Attack", function()
		local AvatarCtrl = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("AvatarController"))
		if AvatarCtrl and AvatarCtrl.attack then
			AvatarCtrl.attack()
		end
	end)

	-- 7. Mobile/Universal Dash Button (Styled to match other slots)
	local dashSlot = Utils.mkSlot({
		name = "DashSlot",
		size = UDim2.new(0, actionButtonSize, 0, actionButtonSize),
		bg = C.BG_SLOT,
		bgT = 0.4,
		r = 6,
		z = 10,
		parent = parent
	})
	
	local dashIconId = getIconImage("Dash")
	if dashIconId and dashIconId ~= "" then
		dashSlot.icon.Image = dashIconId
		dashSlot.icon.Visible = true
	else
		dashSlot.icon.Visible = false
	end

	local dashLabel = Utils.mkLabel({
		text = dashIconId and "" or UILocalizer.Localize("대쉬"),
		size = UDim2.new(1, 0, 1, 0),
		font = F.TITLE,
		color = C.WHITE,
		ts = 13,
		z = 12,
		parent = dashSlot.frame
	})
	dashLabel.TextScaled = true

	bindSlotAction(dashSlot, "Dash", function()
		PlatformerInput.requestSpecial()
	end)

	local function syncConsumableHotbarPosition()
		if not mainAnchor or not runeFrame then return end
		local ap = mainAnchor.AbsolutePosition
		local as = mainAnchor.AbsoluteSize
		local scale = parent:FindFirstChildOfClass("UIScale") and parent:FindFirstChildOfClass("UIScale").Scale or 1
		
		runeFrame.Position = UDim2.new(
			0, (ap.X + as.X) / scale + 12,
			0, ap.Y / scale + as.Y * 0.35
		)

		-- Get the viewport size to prevent buttons from going off-screen
		local camera = workspace.CurrentCamera
		local vpSize = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local screenWidth = vpSize.X / scale

		local attackX = (ap.X + as.X) / scale + 90
		local dashX = attackX + actionButtonSize + actionButtonGap

		-- If the buttons would go off-screen, align them from the right edge of the screen instead
		if dashX + actionButtonSize > screenWidth - 10 then
			dashX = screenWidth - 16 - actionButtonSize
			attackX = dashX - actionButtonGap - actionButtonSize
		end

		if attackSlot and attackSlot.frame then
			attackSlot.frame.Position = UDim2.new(0, attackX, 0, ap.Y / scale + as.Y * 0.35)
		end

		if dashSlot and dashSlot.frame then
			dashSlot.frame.Position = UDim2.new(
				0, dashX,
				0, ap.Y / scale + as.Y * 0.35
			)
		end
	end

	mainAnchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(syncConsumableHotbarPosition)
	mainAnchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncConsumableHotbarPosition)
	task.spawn(function() task.wait(0.15); syncConsumableHotbarPosition() end)

	local function safeRequest(requestName, payload)
		if NetClient and NetClient.Request then
			return NetClient.Request(requestName, payload)
		else
			warn("NetClient not available for request:", requestName)
			return false, nil
		end
	end

	local function cloneConsumableQuickslots()
		return {
			consumableQuickslots[1] or "",
			consumableQuickslots[2] or "",
			consumableQuickslots[3] or "",
		}
	end

	function HUDUI.RefreshConsumableSlots()
		HUDUI.UpdateConsumableHotbar()
		task.spawn(function()
			safeRequest("Inventory.SaveQuickslots.Request", { quickslots = cloneConsumableQuickslots() })
		end)
	end

	function HUDUI.RegisterConsumable(slotIdx, itemId)
		consumableQuickslots[slotIdx] = itemId or ""
		HUDUI.UpdateConsumableHotbar()
		
		-- 서버에 즉시 영속 저장 요청
		task.spawn(function()
			safeRequest("Inventory.SaveQuickslots.Request", { quickslots = cloneConsumableQuickslots() })
		end)
	end

	-- 서버로부터 저장된 단축슬롯 정보 로드
	task.spawn(function()
		local Players = game:GetService("Players")
		local localPlayer = Players.LocalPlayer
		while not (localPlayer and localPlayer:GetAttribute("DataLoaded")) do
			task.wait(0.2)
		end

		local success, result = safeRequest("Inventory.GetQuickslots.Request")
		if success and result and result.quickslots then
			for i = 1, 3 do
				local itemId = result.quickslots[i]
				consumableQuickslots[i] = (type(itemId) == "string" and itemId ~= "") and itemId or ""
			end
			HUDUI.UpdateConsumableHotbar()
		end
	end)

	function HUDUI.UseConsumableQuickslot(slotIdx)
		local itemId = consumableQuickslots[slotIdx]
		if not itemId then
			_UIManager.notify("단축슬롯에 등록된 소비 아이템이 없습니다.", C.RED)
			return
		end

		local isPotion = string.find(string.upper(itemId), "POTION") ~= nil
		if isPotion and tick() < localPotionCooldownEnd then
			_UIManager.notify("포션 재사용 대기 중입니다.", C.RED)
			return
		end
		
		local items = InventoryController.getItems()
		local foundSlot = nil
		for sIdx, slotData in pairs(items) do
			if slotData and slotData.itemId == itemId and slotData.count > 0 then
				foundSlot = sIdx
				break
			end
		end
		
		if foundSlot then
			local slot = HUDUI.Refs.consumableSlots[slotIdx]
			if slot then triggerScale(slot.frame) end
			if isPotion then
				localPotionCooldownEnd = tick() + 3.0 -- Start local 3s cooldown
			end
			InventoryController.requestUse(foundSlot)
		else
			local ItemData = require(game:GetService("ReplicatedStorage"):WaitForChild("Data"):WaitForChild("ItemData"))
			local itemName = "아이템"
			for _, item in ipairs(ItemData) do
				if item.id == itemId then
					itemName = item.name
					break
				end
			end
			_UIManager.notify(string.format("가방에 %s이(가) 부족합니다!", itemName), C.RED)
		end
	end

	function HUDUI.UpdateConsumableHotbar()
		local items = InventoryController.getItems()
		local counts = {}
		for _, slotData in pairs(items) do
			if slotData and slotData.itemId then
				counts[slotData.itemId] = (counts[slotData.itemId] or 0) + (slotData.count or 0)
			end
		end
		
		for i = 1, 3 do
			local slot = HUDUI.Refs.consumableSlots[i]
			if slot then
				local itemId = consumableQuickslots[i]
				if itemId and itemId ~= "" then
					local count = counts[itemId] or 0
					local icon = _UIManager.getItemIcon(itemId)
					
					slot.icon.Image = icon
					slot.icon.Visible = true
					slot.countLabel.Text = tostring(count)
					slot.countLabel.Visible = count > 0
					slot.frame.BackgroundTransparency = count > 0 and 0.4 or 0.8
				else
					slot.icon.Visible = false
					slot.countLabel.Visible = false
					slot.frame.BackgroundTransparency = 0.4
				end
			end
		end
	end

	-- 3. Rune Hotbar (E, R, T) - Decoupled parent to guarantee clicks work
	runeFrame = Utils.mkFrame({
		name = "RuneHotbarFrame",
		size = UDim2.new(0, 52, 0, 180), 
		pos = UDim2.new(0, 0, 0, 0), 
		anchor = Vector2.new(0, 1),
		bgT = 1,
		parent = parent -- CRITICAL: Parent to ScreenGui ensures slots can accept click events
	})

	local runeVList = Instance.new("UIListLayout")
	runeVList.FillDirection = Enum.FillDirection.Vertical
	runeVList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	runeVList.VerticalAlignment = Enum.VerticalAlignment.Bottom
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
		keyLabel.ZIndex = slot.icon.ZIndex + 10 -- 룬 아이콘 이미지 레이어보다 위로 강제 노출 보장
		
		-- [추가] 쿨타임 오버레이
		local cdOverlay = Instance.new("Frame")
		cdOverlay.Name = "CooldownOverlay"
		cdOverlay.Size = UDim2.new(1, 0, 1, 0)
		cdOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		cdOverlay.BackgroundTransparency = 0.5
		cdOverlay.Visible = false
		cdOverlay.ZIndex = slot.frame.ZIndex + 2
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = cdOverlay
		cdOverlay.Parent = slot.frame
		
		local cdLabel = Utils.mkLabel({
			name = "CooldownText",
			text = "0.0", size = UDim2.new(1, 0, 1, 0),
			font = F.TITLE, color = C.WHITE, st = 1, parent = cdOverlay
		})
		cdLabel.TextScaled = true
		cdLabel.ZIndex = cdOverlay.ZIndex + 1
		
		slot.cdOverlay = cdOverlay
		slot.cdLabel = cdLabel
		
		HUDUI.Refs.runeSlots[i] = slot
		
		-- [추가] 슬롯 직접 클릭 시 애니메이션 및 스킬 발동
		bindRuneSlotAction(slot, i, function()
			local SkillCtrl = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SkillController"))
			if SkillCtrl and SkillCtrl.useSkillIndex then
				SkillCtrl.useSkillIndex(i)
			end
		end)
	end

	-- 스킬 단축키 지정 변경 시 핫바의 스킬 아이콘 자동 동기화
	task.spawn(function()
		local SkillCtrl = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SkillController"))
		if SkillCtrl and SkillCtrl.onSkillDataUpdated then
			SkillCtrl.onSkillDataUpdated(function()
				if HUDUI.UpdateRuneHotbar then
					HUDUI.UpdateRuneHotbar()
				end
			end)
		end
	end)

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
		HUDUI.Refs.hex_Attack.MouseButton1Click:Connect(function() local CC = require(Controllers:WaitForChild("CombatController")); if CC.attack then CC.attack() end end)
	end

	-- Dodge & Jump (Mobile Bindings)
	if HUDUI.Refs.hex_Dodge then
		HUDUI.Refs.hex_Dodge.MouseButton1Click:Connect(function() 
			local MC = require(Controllers:WaitForChild("MovementController"))
			if MC.performDodge then MC.performDodge() end -- Ensure function exists or use shared trigger
		end)
	end
	
	if HUDUI.Refs.hex_Jump then
		HUDUI.Refs.hex_Jump.MouseButton1Click:Connect(function()
			-- MovementAbilityController의 커스텀 점프 시스템으로 통일
			-- hum.Jump = true 대신 JumpRequest 이벤트를 직접 발생시켜 requestJump() 경유
			local MAC = require(Controllers:WaitForChild("MovementAbilityController"))
			if MAC and MAC.requestJump then
				MAC.requestJump()
			else
				-- 폴백: humanoid.Jump
				local hum = player.Character and player.Character:FindFirstChild("Humanoid")
				if hum then hum.Jump = true end
			end
		end)
	end

	-- [UX] UI Toggle Key Bindings moved to ClientInit for consistency

	-- Harvest Setup
	HUDUI.Refs.harvestFrame = Utils.mkFrame({name="Harvest", size=UDim2.new(0, 300, 0, 60), pos=UDim2.new(0.4, 0, 0.5, 0), anchor=Vector2.new(0.5, 0.5), bgT=1, vis=false, parent=parent})
	local hBar = Utils.mkBar({size=UDim2.new(1, 0, 0, 6), pos=UDim2.new(0.5, 0, 0, 30), anchor=Vector2.new(0.5, 0), fillC=C.WHITE, parent=HUDUI.Refs.harvestFrame})
	HUDUI.Refs.harvestBar = hBar.fill
	HUDUI.Refs.harvestName = Utils.mkLabel({text=UILocalizer.Localize("채집 중..."), size=UDim2.new(1, 0, 0, 25), ts=16, bold=true, rich=true, parent=HUDUI.Refs.harvestFrame})
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
	-- =============================================
	-- Raid Boss HP UI (Premium Center Top Design)
	-- =============================================
	local raidBossContainer = Instance.new("Frame")
	raidBossContainer.Name = "RaidBossUIContainer"
	raidBossContainer.Size = UDim2.new(0.75, 0, 0, 120)
	raidBossContainer.Position = UDim2.new(0.5, 0, 0, 15) -- Placed at top center, 15px below top
	raidBossContainer.AnchorPoint = Vector2.new(0.5, 0)
	raidBossContainer.BackgroundTransparency = 1
	raidBossContainer.BorderSizePixel = 0
	raidBossContainer.Visible = false
	raidBossContainer.ZIndex = 100
	raidBossContainer.Parent = parent
	HUDUI.Refs.raidBossContainer = raidBossContainer

	local raidBossSizeConstraint = Instance.new("UISizeConstraint")
	raidBossSizeConstraint.Name = "RaidBossSizeConstraint"
	raidBossSizeConstraint.MinSize = Vector2.new(450, 0)
	raidBossSizeConstraint.MaxSize = Vector2.new(900, 999)
	raidBossSizeConstraint.Parent = raidBossContainer
	HUDUI.Refs.raidBossSizeConstraint = raidBossSizeConstraint

	-- Boss Name Label
	local raidBossName = Utils.mkLabel({
		name = "RaidBossName",
		text = "사막의 수호자",
		size = UDim2.new(1, 0, 0, 32),
		pos = UDim2.new(0.5, 0, 0, 0),
		anchor = Vector2.new(0.5, 0),
		ts = 22,
		bold = true,
		color = Color3.fromRGB(255, 255, 255),
		ax = Enum.TextXAlignment.Center,
		parent = raidBossContainer
	})
	raidBossName.Font = F.TITLE
	HUDUI.Refs.raidBossName = raidBossName

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 2.5
	nameStroke.Parent = raidBossName

	-- HP Bar Background Frame (Full Width)
	local raidHpBarBg = Instance.new("Frame")
	raidHpBarBg.Name = "RaidHPBarBg"
	raidHpBarBg.Size = UDim2.new(1, 0, 0, 26) -- Stretching to fill full container width
	raidHpBarBg.Position = UDim2.new(0, 0, 0, 42)
	raidHpBarBg.BackgroundColor3 = Color3.fromRGB(15, 20, 30) -- Deep Navy BG
	raidHpBarBg.BorderSizePixel = 0
	raidHpBarBg.Parent = raidBossContainer
	HUDUI.Refs.raidHpBarBg = raidHpBarBg

	local raidHpCorner = Instance.new("UICorner")
	raidHpCorner.CornerRadius = UDim.new(0, 6)
	raidHpCorner.Parent = raidHpBarBg

	local raidHpBorder = Instance.new("UIStroke")
	raidHpBorder.Color = Color3.fromRGB(190, 155, 75) -- Default gold border
	raidHpBorder.Thickness = 2
	raidHpBorder.Parent = raidHpBarBg
	HUDUI.Refs.raidHpBorder = raidHpBorder

	-- HP Decay Underfill (rust-orange)
	local raidHpUnderFill = Instance.new("Frame")
	raidHpUnderFill.Name = "RaidHPUnderFill"
	raidHpUnderFill.Size = UDim2.new(1, 0, 1, 0)
	raidHpUnderFill.BackgroundColor3 = Color3.fromRGB(200, 80, 40) -- Orange/Rust damage decay
	raidHpUnderFill.BorderSizePixel = 0
	raidHpUnderFill.Parent = raidHpBarBg
	HUDUI.Refs.raidHpUnderFill = raidHpUnderFill

	local underCorner = Instance.new("UICorner")
	underCorner.CornerRadius = UDim.new(0, 6)
	underCorner.Parent = raidHpUnderFill

	-- Main HP Bar Fill
	local raidHpBarFill = Instance.new("Frame")
	raidHpBarFill.Name = "RaidHPBarFill"
	raidHpBarFill.Size = UDim2.new(1, 0, 1, 0)
	raidHpBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	raidHpBarFill.BorderSizePixel = 0
	raidHpBarFill.ClipsDescendants = true
	raidHpBarFill.Parent = raidHpBarBg
	HUDUI.Refs.raidHpBarFill = raidHpBarFill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = raidHpBarFill

	-- Dynamic UIGradient for custom boss themes
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Name = "RaidHPGradient"
	fillGradient.Parent = raidHpBarFill
	HUDUI.Refs.raidHpGradient = fillGradient

	-- HP Text Label
	local raidHpLabel = Utils.mkLabel({
		name = "RaidHPLabel",
		text = "0 / 0",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 14,
		bold = true,
		color = Color3.fromRGB(255, 255, 255),
		ax = Enum.TextXAlignment.Center,
		ay = Enum.TextYAlignment.Center,
		parent = raidHpBarBg
	})
	raidHpLabel.ZIndex = raidHpBarBg.ZIndex + 5
	HUDUI.Refs.raidHpLabel = raidHpLabel

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 1.8
	textStroke.Parent = raidHpLabel

	HUDUI.Refs.raidMultiplier = nil

	-- =============================================
	-- HUD 바 툴팁 (마우스 호버 시 설명창) - 프리미엄 Navy + Black 테마로 색감 강제 대통합
	-- =============================================
	local tooltip = Instance.new("Frame")
	tooltip.Name = "HUDTooltip"
	tooltip.Size = UDim2.new(0, 210, 0, 80)
	tooltip.BackgroundColor3 = Color3.fromRGB(10, 15, 25) -- Deep Navy (장비/룬 창과 일치)
	tooltip.BackgroundTransparency = 0.05
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 9500
	tooltip.Visible = false
	tooltip.Parent = parent

	local tipCorner = Instance.new("UICorner")
	tipCorner.CornerRadius = UDim.new(0, 10)
	tipCorner.Parent = tooltip

	local tipStroke = Instance.new("UIStroke")
	tipStroke.Color = Color3.fromRGB(60, 85, 130) -- Light Navy 테두리
	tipStroke.Thickness = 1.8
	tipStroke.Transparency = 0.1
	tipStroke.Parent = tooltip

	local tipTitle = Instance.new("TextLabel")
	tipTitle.Name = "Title"
	tipTitle.Size = UDim2.new(1, -20, 0, 30)
	tipTitle.Position = UDim2.new(0, 10, 0, 5)
	tipTitle.BackgroundTransparency = 1
	tipTitle.TextColor3 = Color3.fromRGB(255, 255, 255) -- 완전 화이트 타이틀
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
	tipBody.TextColor3 = Color3.fromRGB(180, 200, 230) -- 고품격 소프트 블루 그레이 바디
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

		-- 반응형 가로폭 계산 (고정 280px 제거, 모바일 해상도 감지 및 기기 화면비 대응)
		local camera = workspace.CurrentCamera
		local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		
		local responsiveWidth = 280
		if isSmall or vp.X < 768 then
			-- 모바일/태블릿 화면 크기 대응 (최소 180px, 최대 230px 내로 가로 비율 조정)
			responsiveWidth = math.clamp(vp.X * 0.45, 180, 230)
		else
			-- PC 화면 대응
			responsiveWidth = math.clamp(vp.X * 0.2, 260, 310)
		end

		local maxBodyWidth = responsiveWidth - 20
		local bodyFont = HUDUI.Refs.tipBody.Font
		local textBounds = TextService:GetTextSize(
			localizedBody,
			HUDUI.Refs.tipBody.TextSize,
			(bodyFont == Enum.Font.Unknown or bodyFont == Enum.Font.Custom) and Enum.Font.Gotham or bodyFont,
			Vector2.new(maxBodyWidth, 2000)
		)
		local bodyHeight = math.max(40, textBounds.Y + 6)
		HUDUI.Refs.tipBody.Size = UDim2.new(1, -20, 0, bodyHeight)
		HUDUI.Refs.tooltip.Size = UDim2.new(0, responsiveWidth, 0, 44 + bodyHeight + 10)
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
			if slotIdx >= 1 and slotIdx <= 3 then
				HUDUI.UseConsumableQuickslot(slotIdx)
			else
				local slot = HUDUI.Refs.hotbarSlots and HUDUI.Refs.hotbarSlots[slotIdx]
				if slot then triggerScale(slot.frame) end
			end
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

	-- =============================================
	-- Raid Boss HP Bar Client Loop (Data-Driven Theme Mapping)
	-- =============================================
	task.spawn(function()
		local Players = game:GetService("Players")
		local localPlayer = Players.LocalPlayer
		
		-- Cache active boss visual styling to avoid redundantly setting properties
		local currentActiveBossKey = nil
		
		while true do
			task.wait(0.1)
			
			local character = localPlayer.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			
			-- Search workspace for any active raid boss defined in RaidBossData
			local activeBossModel = nil
			local activeBossData = nil
			local bossKey = nil
			
			local closestDist = 999999
			for key, data in pairs(RaidBossData) do
				local foundModel = workspace:FindFirstChild(data.mobModelName)
				if foundModel and foundModel:FindFirstChildOfClass("Humanoid") then
					local bHrp = foundModel:FindFirstChild("HumanoidRootPart") or foundModel.PrimaryPart
					if bHrp and hrp then
						local dist = (hrp.Position - bHrp.Position).Magnitude
						if dist < closestDist then
							activeBossModel = foundModel
							activeBossData = data
							bossKey = key
							closestDist = dist
						end
					end
				end
			end
			
			local bossHrp = activeBossModel and (activeBossModel:FindFirstChild("HumanoidRootPart") or activeBossModel.PrimaryPart)
			local bossHum = activeBossModel and activeBossModel:FindFirstChildOfClass("Humanoid")
			
			if hrp and bossHrp and bossHum and bossHum.Health > 0 then
				local dist = (hrp.Position - bossHrp.Position).Magnitude
				if dist < 85 then
					-- 1. Client-side: hide the default 3D head-up health BillboardGui
					local mobUI = activeBossModel:FindFirstChild("MobUI", true)
					if mobUI and mobUI:IsA("BillboardGui") then
						mobUI.Enabled = false
					end
					
					-- 2. Dynamically bind boss theme visual assets on initial detection
					if currentActiveBossKey ~= bossKey then
						currentActiveBossKey = bossKey
						
						if HUDUI.Refs.raidBossName then
							HUDUI.Refs.raidBossName.Text = UILocalizer.Localize(activeBossData.displayName)
						end
						if HUDUI.Refs.raidHpBorder then
							HUDUI.Refs.raidHpBorder.Color = activeBossData.themeColor
						end
						if HUDUI.Refs.raidHpGradient then
							HUDUI.Refs.raidHpGradient.Color = activeBossData.hpGradient
						end
						if HUDUI.Refs.raidHpUnderFill then
							HUDUI.Refs.raidHpUnderFill.BackgroundColor3 = activeBossData.underfillColor
						end
						if HUDUI.Refs.raidMultiplier then
							HUDUI.Refs.raidMultiplier.TextColor3 = activeBossData.themeColor
						end
					end
					
					-- 3. Show 2D ScreenGui Raid Boss health container
					if HUDUI.Refs.raidBossContainer then
						HUDUI.Refs.raidBossContainer.Visible = true
					end
					
					-- 4. Calculate actual HP bar details in real time
					local curHP = bossHum.Health
					local maxHP = bossHum.MaxHealth
					local hpRatio = math.clamp(curHP / maxHP, 0, 1)
					
					if HUDUI.Refs.raidHpBarFill then
						TweenService:Create(HUDUI.Refs.raidHpBarFill, TweenInfo.new(0.05, Enum.EasingStyle.Quad), {Size = UDim2.new(hpRatio, 0, 1, 0)}):Play()
					end
					
					if HUDUI.Refs.raidHpUnderFill then
						TweenService:Create(HUDUI.Refs.raidHpUnderFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Size = UDim2.new(hpRatio, 0, 1, 0)}):Play()
					end
					
					if HUDUI.Refs.raidHpLabel then
						HUDUI.Refs.raidHpLabel.Text = string.format("%d / %d", math.floor(curHP), math.floor(maxHP))
					end
				else
					-- Player moved away, hide boss HP bar and restore 3D UI
					if HUDUI.Refs.raidBossContainer and HUDUI.Refs.raidBossContainer.Visible then
						HUDUI.Refs.raidBossContainer.Visible = false
					end
					local mobUI = activeBossModel:FindFirstChild("MobUI", true)
					if mobUI and mobUI:IsA("BillboardGui") then
						mobUI.Enabled = true
					end
					currentActiveBossKey = nil
				end
			else
				-- Boss is dead/nil, reset and hide 2D ScreenGui HP bar
				if HUDUI.Refs.raidBossContainer and HUDUI.Refs.raidBossContainer.Visible then
					-- Fast zero-out animation before hiding
					if HUDUI.Refs.raidHpBarFill then HUDUI.Refs.raidHpBarFill.Size = UDim2.new(0, 0, 1, 0) end
					if HUDUI.Refs.raidHpUnderFill then HUDUI.Refs.raidHpUnderFill.Size = UDim2.new(0, 0, 1, 0) end
					if HUDUI.Refs.raidMultiplier then HUDUI.Refs.raidMultiplier.Text = "x0" end
					
					local containerToHide = HUDUI.Refs.raidBossContainer
					task.spawn(function()
						task.wait(0.5)
						if containerToHide and currentActiveBossKey == nil then
							containerToHide.Visible = false
						end
					end)
				end
				currentActiveBossKey = nil
			end
		end
	end)

	-- Responsive Layout for Raid Boss HP UI (Mobile / Portrait / Landscape support)
	local function updateRaidBossLayout()
		local camera = workspace.CurrentCamera
		local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local isSmallScreen = isSmall or vp.X < 768

		local container = HUDUI.Refs.raidBossContainer
		local constraint = HUDUI.Refs.raidBossSizeConstraint
		local bossName = HUDUI.Refs.raidBossName
		local hpBarBg = HUDUI.Refs.raidHpBarBg
		local hpLabel = HUDUI.Refs.raidHpLabel

		if not container then return end

		if isSmallScreen then
			-- Mobile / Small Screen layout
			container.Size = UDim2.new(0.85, 0, 0, 65)
			container.Position = UDim2.new(0.5, 0, 0, 8)
			if constraint then
				constraint.MinSize = Vector2.new(280, 0)
				constraint.MaxSize = Vector2.new(500, 999)
			end
			if bossName then
				bossName.Size = UDim2.new(1, 0, 0, 20)
				bossName.TextSize = 15
			end
			if hpBarBg then
				hpBarBg.Size = UDim2.new(1, 0, 0, 16)
				hpBarBg.Position = UDim2.new(0, 0, 0, 24)
			end
			if hpLabel then
				hpLabel.TextSize = 10
			end
		else
			-- PC / Large Screen layout
			container.Size = UDim2.new(0.75, 0, 0, 120)
			container.Position = UDim2.new(0.5, 0, 0, 15)
			if constraint then
				constraint.MinSize = Vector2.new(450, 0)
				constraint.MaxSize = Vector2.new(900, 999)
			end
			if bossName then
				bossName.Size = UDim2.new(1, 0, 0, 32)
				bossName.TextSize = 22
			end
			if hpBarBg then
				hpBarBg.Size = UDim2.new(1, 0, 0, 26)
				hpBarBg.Position = UDim2.new(0, 0, 0, 42)
			end
			if hpLabel then
				hpLabel.TextSize = 14
			end
		end
	end

	updateRaidBossLayout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateRaidBossLayout)
	end
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

	-- tutorialEntry 의 전용 stroke만 펄스 (사이드퀘스트에 영향 없음)
	local stroke = HUDUI.Refs.tutorialEntryStroke
	if ready then
		if stroke then
			stroke.Color = Color3.fromRGB(60, 85, 130)
			stroke.Thickness = 1.5
			stroke.Transparency = 0.05
			tutorialPulseTween = TweenService:Create(
				stroke,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = Color3.fromRGB(240, 190, 60), Transparency = 0.1 }
			)
			tutorialPulseTween:Play()
		end
		if HUDUI.Refs.tutorialReadyHint then
			HUDUI.Refs.tutorialReadyHint.Visible = true
			HUDUI.Refs.tutorialReadyHint.Text = UILocalizer.Localize("클릭/터치하여 완료")
			HUDUI.Refs.tutorialReadyHint.TextTransparency = 0
			tutorialHintPulseTween = TweenService:Create(
				HUDUI.Refs.tutorialReadyHint,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ TextTransparency = 0.5 }
			)
			tutorialHintPulseTween:Play()
		end

		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.Active = true
		end
	else
		if stroke then
			stroke.Color = Color3.fromRGB(60, 85, 130)
			stroke.Thickness = 0
			stroke.Transparency = 1
		end
		if HUDUI.Refs.tutorialReadyHint then
			HUDUI.Refs.tutorialReadyHint.Visible = false
			HUDUI.Refs.tutorialReadyHint.TextTransparency = 0
		end
		if HUDUI.Refs.tutorialClickArea then
			HUDUI.Refs.tutorialClickArea.Active = false
		end
	end
end

function HUDUI.SetVisible(visible)
	-- mainContainer 자체는 숨기지 않음 (bgT=1 투명) — consumableFrame 제외한 자식만 토글
	if HUDUI.Refs.statusPanel then
		for _, child in ipairs(HUDUI.Refs.statusPanel:GetChildren()) do
			if child:IsA("GuiObject") and child ~= HUDUI.Refs.consumableFrame then
				child.Visible = visible
			end
		end
	end
	if HUDUI.Refs.leftMenuContainer then HUDUI.Refs.leftMenuContainer.Visible = visible end
	if HUDUI.Refs.hex_Attack then HUDUI.Refs.hex_Attack.Parent.Visible = visible end
	if HUDUI.Refs.starterPackButton then
		HUDUI.Refs.starterPackButton.Visible = visible and starterPackWantedVisible
	end
	if HUDUI.Refs.tutorialFrame then
		HUDUI.Refs.tutorialFrame.Visible = visible and tutorialWantedVisible
	end
end

function HUDUI.SetStarterPackVisible(visible)
	starterPackWantedVisible = visible == true
	if HUDUI.Refs.starterPackButton then
		local hudVisible = (HUDUI.Refs.statusPanel == nil) or HUDUI.Refs.statusPanel.Visible
		HUDUI.Refs.starterPackButton.Visible = starterPackWantedVisible and hudVisible
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
		-- 튜토리얼 완료 시 엔트리만 숨김 (사이드퀘스트 패널은 유지)
		if HUDUI.Refs.tutorialEntry then
			HUDUI.Refs.tutorialEntry.Visible = false
		end
		_setReadyPulse(false)
		if tutorialRelayoutFn then tutorialRelayoutFn() end
		return
	end

	if not status.active then
		_setReadyPulse(false)
		HUDUI.SetTutorialVisible(false)
		return
	end

	local stepIndex = tonumber(status.stepIndex) or 0
	local totalSteps = tonumber(status.totalSteps) or 0

	-- 제목: "[ 튜토리얼 ] 6/12  애벌레 잡기"
	local currentStepText = localizeTutorialStepField(status, "currentStepText")
	if currentStepText ~= "" then
		HUDUI.Refs.tutorialTitle.Text = string.format("[ 튜토리얼 ] %d/%d  %s", stepIndex, totalSteps, localizeQuestRuntimeText(currentStepText))
	else
		HUDUI.Refs.tutorialTitle.Text = string.format("[ 튜토리얼 ] %d/%d", stepIndex, totalSteps)
	end
	HUDUI.Refs.tutorialTitle.TextColor3 = Color3.fromRGB(230, 230, 230)

	-- 진행 텍스트: "애벌레 5마리를 처치하세요.  0 / 5"
	local stepCommand = localizeTutorialStepField(status, "stepCommand")
	local hasCount = status.progress and status.stepCount and status.stepCount > 0
	local count = hasCount and (status.progress.count or 0) or 0
	local total = hasCount and status.stepCount or 0
	local done = status.progress and status.progress.done == true

	local progStr
	if stepCommand ~= "" then
		progStr = localizeQuestRuntimeText(stepCommand)
		if hasCount then progStr = progStr .. string.format("  %d / %d", count, total) end
	elseif hasCount then
		progStr = string.format("%d / %d", count, total)
	else
		progStr = UILocalizer.Localize("다음 목표 대기 중")
	end
	if done then progStr = "✓ " .. progStr end

	HUDUI.Refs.tutorialStep.Text = progStr
	HUDUI.Refs.tutorialStep.RichText = false
	HUDUI.Refs.tutorialStep.TextColor3 = done and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(160, 160, 160)

	-- 진행 바
	local progress = (hasCount and total > 0) and math.clamp(count / total, 0, 1) or (done and 1 or 0)
	if HUDUI.Refs.tutorialBarFill then
		HUDUI.Refs.tutorialBarFill.Size = UDim2.new(progress, 0, 1, 0)
		HUDUI.Refs.tutorialBarFill.BackgroundColor3 = done and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(100, 150, 255)
	end

	HUDUI.Refs.tutorialProgress.Visible = false
	HUDUI.Refs.tutorialReward.Visible = false
	if tutorialRelayoutFn then tutorialRelayoutFn() end
	if HUDUI.Refs.tutorialCompleteBtn then HUDUI.Refs.tutorialCompleteBtn.Visible = false end
	if HUDUI.Refs.tutorialReadyHint then HUDUI.Refs.tutorialReadyHint.Visible = done end
	if HUDUI.Refs.tutorialClickArea then HUDUI.Refs.tutorialClickArea.Active = done end
	_setReadyPulse(done)

	HUDUI.SetTutorialVisible(true)
end

function HUDUI.UpdateRuneHotbar(equipment)
	if not HUDUI.Refs.runeSlots then return end
	
	local SkillController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SkillController"))
	local activeSlots = SkillController and SkillController.getActiveSkillSlots and SkillController.getActiveSkillSlots() or { "", "", "" }
	local SkillTreeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("SkillTreeData"))

	for i = 1, 3 do
		local slot = HUDUI.Refs.runeSlots[i]
		if not slot then continue end
		
		local skillId = activeSlots[i]
		if skillId and skillId ~= "" then
			local skillData = SkillTreeData.GetSkill(skillId)
			slot.icon.Image = _UIManager and _UIManager.getItemIcon(skillData and skillData.icon or skillId) or ""
			slot.icon.Visible = true
		else
			slot.icon.Image = ""
			slot.icon.Visible = false
		end
	end
end

function HUDUI.UpdateHealth(cur, max)
	local bar = HUDUI.Refs.healthBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.hpDecay then TweenService:Create(HUDUI.Refs.hpDecay, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%s / %s", formatVal(cur), formatVal(max))
	bar.fill.BackgroundColor3 = r < 0.25 and C.RED or C.HP
end

function HUDUI.UpdateStamina(cur, max)
	local bar = HUDUI.Refs.staminaBar
	if not bar then return end
	local r = math.clamp(cur/max, 0, 1)
	TweenService:Create(bar.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play()
	if HUDUI.Refs.staDecay then TweenService:Create(HUDUI.Refs.staDecay, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Size = UDim2.new(r, 0, 1, 0)}):Play() end
	bar.label.Text = string.format("%s / %s", formatVal(cur), formatVal(max))
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
		HUDUI.Refs.xpValueLabel.Text = string.format("%s / %s", formatVal(cur), formatVal(max))
	end
end

function HUDUI.UpdateLevel(lv)
	HUDUI.Refs.currentLevel = lv
	if HUDUI.Refs.levelLabel then
		HUDUI.Refs.levelLabel.Text = string.format("<font size=\"16\">Lv.</font>%d", tonumber(lv) or 0)
	end
end

function HUDUI.SetStatPointAlert(available)
	if HUDUI.Refs.statPointAlert then
		HUDUI.Refs.statPointAlert.Visible = false
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
		if HUDUI.Refs.harvestName then HUDUI.Refs.harvestName.Text = UILocalizer.Localize(targetName or "채집 중...") end
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

-- [추가] 룬 및 포션 쿨타임 주기적 업데이트
local _cachedSkillController = nil
RunService.RenderStepped:Connect(function()
	if HUDUI.Refs.runeSlots then
		if not _cachedSkillController then
			local ok, sc = pcall(function() return require(Controllers:FindFirstChild("SkillController")) end)
			if ok and sc then _cachedSkillController = sc end
		end
		
		if _cachedSkillController and _cachedSkillController.getRuneCooldownRemaining then
			for i = 1, 3 do
				local slot = HUDUI.Refs.runeSlots[i]
				if slot and slot.cdOverlay and slot.cdLabel then
					local cd = _cachedSkillController.getRuneCooldownRemaining(i)
					if cd > 0 then
						slot.cdOverlay.Visible = true
						-- 1초 이상이면 정수로, 1초 미만이면 소수점 첫째 자리까지 표시
						if cd >= 1.0 then
							slot.cdLabel.Text = string.format("%d", math.ceil(cd))
						else
							slot.cdLabel.Text = string.format("%.1f", cd)
						end
					else
						slot.cdOverlay.Visible = false
					end
				end
			end
		end
	end

	if HUDUI.Refs.consumableSlots then
		local remaining = localPotionCooldownEnd - tick()
		for i = 1, 3 do
			local slot = HUDUI.Refs.consumableSlots[i]
			if slot and slot.cdOverlay and slot.cdLabel then
				if remaining > 0 then
					slot.cdOverlay.Visible = true
					if remaining >= 1.0 then
						slot.cdLabel.Text = string.format("%d", math.ceil(remaining))
					else
						slot.cdLabel.Text = string.format("%.1f", remaining)
					end
				else
					slot.cdOverlay.Visible = false
				end
			end
		end
	end
end)

function HUDUI.IsTutorialMinimized()
	return isTutorialMinimized
end

return HUDUI

