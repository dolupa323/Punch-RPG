-- CraftingUI.lua
-- 무기 제작 UI - 인라인 진행도 표시 (슬롯별 동시 제작 지원)

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))

local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL    = Color3.fromRGB(10, 15, 25)
C.BG_DARK     = Color3.fromRGB(5, 5, 10)
C.BG_SLOT     = Color3.fromRGB(12, 12, 15)
C.GOLD        = Color3.fromRGB(255, 255, 255)
C.GOLD_SEL    = Color3.fromRGB(40, 80, 160)
C.BORDER      = Color3.fromRGB(60, 85, 130)
C.BORDER_DIM  = Color3.fromRGB(30, 45, 70)
C.BTN         = Color3.fromRGB(40, 80, 160)
C.BTN_H       = Color3.fromRGB(60, 100, 180)

local F = Theme.Fonts
local T = Theme.Transp

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))

local CraftingUI = {}

CraftingUI.Refs = {
	Frame = nil,
	Title = nil,
	GridScroll = nil,
	Slots = {},
	Detail = {
		Frame = nil,
		Name = nil,
		Icon = nil,
		Desc = nil,
		MatsText = nil,
		BtnCraft = nil,
	},
}

local selectedRecipeId = nil
local _isSmall = false

local function updateSelectionHighlight()
	for id, slotData in pairs(CraftingUI.Refs.Slots) do
		local borderFrame = slotData.border
		if id == selectedRecipeId then
			borderFrame.BackgroundColor3 = C.GOLD_SEL
			borderFrame.BackgroundTransparency = 0
		else
			borderFrame.BackgroundColor3 = slotData._baseBorderColor or C.BORDER
			borderFrame.BackgroundTransparency = 0.15
		end
	end
end

function CraftingUI.Init(parent, UIManager, isMobile)
	_isSmall = isMobile

	CraftingUI.Refs.Frame = Utils.mkFrame({
		name = "CraftingMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 1,
		vis = false,
		parent = parent
	})

	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(_isSmall and 0.95 or 0.75, 0, _isSmall and 0.9 or 0.85, 0),
		maxSize = Vector2.new(1000, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = CraftingUI.Refs.Frame
	})

	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	CraftingUI.Refs.Title = Utils.mkLabel({text="무기 제작 (Weapon Crafting)", pos=UDim2.new(0,15,0,0), ts=26, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 42, 0, 42),
		pos = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		isNegative = true,
		hbg = C.BTN_GRAY_H,
		bgT = 0.5, ts = 24, color = C.WHITE, r = 4, z = 100,
		fn = function()
			local WindowManager = require(script.Parent.Parent:WaitForChild("Utils"):WaitForChild("WindowManager"))
			WindowManager.close("CRAFTING")
		end,
		parent = header
	})

	local canvasWrapper = Utils.mkFrame({
		name="CanvasWrap", size=UDim2.new(1,-20,1,-65),
		pos=UDim2.new(0,10,0,55), bgT=1, parent=main
	})

	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(_isSmall and 0.55 or 0.6, -5, 1, 0), bgT=1, parent=canvasWrapper})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1,0,1,0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.GOLD_SEL
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0,0,0,0)
	scroll.Parent = gridArea
	CraftingUI.Refs.GridScroll = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,15)
	pad.Parent = scroll

	-- Right Detail Panel
	local detail = Utils.mkFrame({
		name="Detail",
		size=UDim2.new(_isSmall and 0.45 or 0.4, -5, 1, 0),
		pos=UDim2.new(1,0,0,0), anchor=Vector2.new(1,0),
		bg=C.BG_DARK, bgT=0.3, r=6, stroke=true, strokeC=C.BORDER,
		parent=canvasWrapper
	})
	CraftingUI.Refs.Detail.Frame = detail
	detail.Visible = false

	Utils.mkLabel({text="RECIPE INFO", size=UDim2.new(1,0,0,45), bg=C.BG_DARK, bgT=0.5, color=C.GOLD, ts=16, font=F.TITLE, parent=detail})

	CraftingUI.Refs.Detail.Name = Utils.mkLabel({
		text="NAME", size=UDim2.new(1,-30,0,40), pos=UDim2.new(0,15,0,55),
		color=C.WHITE, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detail
	})

	CraftingUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	CraftingUI.Refs.Detail.Icon.Size = UDim2.new(0,80,0,80)
	CraftingUI.Refs.Detail.Icon.Position = UDim2.new(0,15,0,95)
	CraftingUI.Refs.Detail.Icon.BackgroundTransparency = 1
	CraftingUI.Refs.Detail.Icon.Parent = detail

	CraftingUI.Refs.Detail.Desc = Utils.mkLabel({
		text="Description", size=UDim2.new(1,-120,0,105), pos=UDim2.new(0,115,0,105),
		color=C.GRAY, ts=15, wrap=true, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detail
	})

	Utils.mkLabel({text="[ MATS REQUIRED ]", size=UDim2.new(1,-30,0,25), pos=UDim2.new(0,15,0,210), ts=15, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=detail})

	CraftingUI.Refs.Detail.MatsText = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,0,150), pos=UDim2.new(0,15,0,240),
		ts=16, color=C.WHITE, rich=true, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=detail
	})

	CraftingUI.Refs.Detail.BtnCraft = Utils.mkBtn({
		text=UILocalizer.Localize("제작 시작"), size=UDim2.new(1,-24,0,52), pos=UDim2.new(0,12,1,-62),
		bg=C.GOLD_SEL, hbg=C.BTN_H, color=C.BG_DARK, ts=20, font=F.TITLE, r=5,
		fn=function() UIManager._DoCraft() end, parent=detail
	})
end

function CraftingUI.SetVisible(visible)
	if CraftingUI.Refs.Frame then
		CraftingUI.Refs.Frame.Visible = visible
	end
end

function CraftingUI.UpdateTitle(text)
	if CraftingUI.Refs.Title then
		CraftingUI.Refs.Title.Text = text
	end
end

function CraftingUI.Refresh(items, playerItemCounts, getItemIcon, mode, UIManager)
	local scroll = CraftingUI.Refs.GridScroll
	if not scroll then return end

	for _, ch in pairs(scroll:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end
	end

	local listLayout = scroll:FindFirstChildOfClass("UIListLayout")
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 8)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = scroll
	end

	CraftingUI.Refs.Slots = {}

	if mode ~= "CRAFTING" then
		table.sort(items, function(a, b)
			local aTech = a.techLevel or a.rarity or 0
			local bTech = b.techLevel or b.rarity or 0
			if aTech ~= bTech then return aTech < bTech end
			local aTime = a.craftTime or 0
			local bTime = b.craftTime or 0
			if aTime ~= bTime then return aTime < bTime end
			return (a.name or "") < (b.name or "")
		end)
	end

	for i, item in ipairs(items) do
		local targetId = item.id
		if item.outputs and #item.outputs > 0 then targetId = item.outputs[1].itemId or item.outputs[1].id end

		local craftTime = item.craftTime or 180
		local currentCraftId = nil

		-- 슬롯 외곽 테두리
		local borderFrame = Instance.new("Frame")
		borderFrame.Name = item.id
		borderFrame.Size = UDim2.new(1, -20, 0, 80)
		borderFrame.BackgroundColor3 = C.BORDER
		borderFrame.BackgroundTransparency = 0.15
		borderFrame.BorderSizePixel = 0
		borderFrame.LayoutOrder = i
		borderFrame.Parent = scroll
		local bCorner = Instance.new("UICorner"); bCorner.CornerRadius = UDim.new(0,6); bCorner.Parent = borderFrame

		-- inner (ZIndex=1 이면 click 버튼보다 아래 → ZIndex=3으로 올려 액션 버튼 클릭 보장)
		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.Size = UDim2.new(1,-2,1,-2)
		inner.Position = UDim2.new(0.5,0,0.5,0)
		inner.AnchorPoint = Vector2.new(0.5,0.5)
		inner.BackgroundColor3 = C.BG_SLOT
		inner.BackgroundTransparency = 0
		inner.ZIndex = 3
		inner.Parent = borderFrame
		local iCorner = Instance.new("UICorner"); iCorner.CornerRadius = UDim.new(0,5); iCorner.Parent = inner

		-- 아이콘
		local iconBg = Instance.new("Frame")
		iconBg.Size = UDim2.new(0,64,0,64)
		iconBg.Position = UDim2.new(0,8,0.5,0)
		iconBg.AnchorPoint = Vector2.new(0,0.5)
		iconBg.BackgroundColor3 = C.BG_DARK
		iconBg.BorderSizePixel = 0
		iconBg.ZIndex = 3
		iconBg.Parent = inner
		local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0,4); ic.Parent = iconBg
		local st = Instance.new("UIStroke"); st.Color = C.BORDER_DIM; st.Thickness = 1; st.Parent = iconBg

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0.85,0,0.85,0)
		icon.Position = UDim2.new(0.5,0,0.5,0)
		icon.AnchorPoint = Vector2.new(0.5,0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = getItemIcon(targetId)
		icon.ZIndex = 3
		icon.Parent = iconBg

		-- ACTION AREA (우측 끝 고정, 너비 165px)
		-- inner 안에서 오른쪽 끝에 배치, click 버튼이 침범하지 않음
		local ACTION_W = 165
		local ACTION_PAD = 8  -- 우측 여백

		local actionArea = Instance.new("Frame")
		actionArea.Name = "ActionArea"
		actionArea.Size = UDim2.new(0, ACTION_W, 1, -12)
		actionArea.Position = UDim2.new(1, -(ACTION_W + ACTION_PAD), 0.5, 0)
		actionArea.AnchorPoint = Vector2.new(0, 0.5)
		actionArea.BackgroundTransparency = 1
		actionArea.ZIndex = 5
		actionArea.Parent = inner

		-- [IDLE] 제작 시작 버튼
		local idleBtn = Instance.new("TextButton")
		idleBtn.Name = "IdleBtn"
		idleBtn.Size = UDim2.new(1, 0, 0, 38)
		idleBtn.Position = UDim2.new(0, 0, 0.5, 0)
		idleBtn.AnchorPoint = Vector2.new(0, 0.5)
		idleBtn.BackgroundColor3 = C.GOLD_SEL
		idleBtn.BorderSizePixel = 0
		idleBtn.Text = "제작 시작"
		idleBtn.Font = F.TITLE
		idleBtn.TextSize = 14
		idleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		idleBtn.ZIndex = 6
		idleBtn.Parent = actionArea
		local idleCorner = Instance.new("UICorner"); idleCorner.CornerRadius = UDim.new(0,5); idleCorner.Parent = idleBtn
		idleBtn.MouseEnter:Connect(function() idleBtn.BackgroundColor3 = C.BTN_H end)
		idleBtn.MouseLeave:Connect(function() idleBtn.BackgroundColor3 = C.GOLD_SEL end)
		idleBtn.MouseButton1Click:Connect(function() UIManager._DoCraftDirect(item) end)

		-- [CRAFTING] 진행도 영역 (Visible=false 시작)
		local progressArea = Instance.new("Frame")
		progressArea.Name = "ProgressArea"
		progressArea.Size = UDim2.new(1, 0, 1, 0)
		progressArea.BackgroundTransparency = 1
		progressArea.Visible = false
		progressArea.ZIndex = 5
		progressArea.Parent = actionArea

		local pctLabel = Instance.new("TextLabel")
		pctLabel.Size = UDim2.new(1, 0, 0, 16)
		pctLabel.Position = UDim2.new(0, 0, 0.5, -30)
		pctLabel.BackgroundTransparency = 1
		pctLabel.Text = "제작 중 (0%)"
		pctLabel.Font = F.NUM
		pctLabel.TextSize = 13
		pctLabel.TextColor3 = Color3.fromRGB(140, 190, 255)
		pctLabel.TextXAlignment = Enum.TextXAlignment.Center
		pctLabel.ZIndex = 5
		pctLabel.Parent = progressArea

		local barBack = Instance.new("Frame")
		barBack.Size = UDim2.new(1, 0, 0, 8)
		barBack.Position = UDim2.new(0, 0, 0.5, -10)
		barBack.BackgroundColor3 = C.BG_DARK
		barBack.BorderSizePixel = 0
		barBack.ZIndex = 5
		barBack.Parent = progressArea
		local bkCorner = Instance.new("UICorner"); bkCorner.CornerRadius = UDim.new(0,3); bkCorner.Parent = barBack
		local bkStroke = Instance.new("UIStroke"); bkStroke.Color = C.BORDER_DIM; bkStroke.Thickness = 1; bkStroke.Parent = barBack

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(40, 140, 240)
		barFill.BorderSizePixel = 0
		barFill.ZIndex = 6
		barFill.Parent = barBack
		local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(0,3); fillCorner.Parent = barFill

		local timeLabel = Instance.new("TextLabel")
		timeLabel.Size = UDim2.new(1, 0, 0, 10)
		timeLabel.Position = UDim2.new(0, 0, 0.5, 2)
		timeLabel.BackgroundTransparency = 1
		timeLabel.Text = ""
		timeLabel.Font = F.NORMAL
		timeLabel.TextSize = 10
		timeLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		timeLabel.TextXAlignment = Enum.TextXAlignment.Center
		timeLabel.ZIndex = 5
		timeLabel.Parent = progressArea

		-- 취소 / 즉시완료 버튼 (진행 중일 때 하단에 나란히 표시)
		local cancelBtn = Instance.new("TextButton")
		cancelBtn.Name = "CancelBtn"
		cancelBtn.Size = UDim2.new(0.48, 0, 0, 18)
		cancelBtn.Position = UDim2.new(0, 0, 0.5, 16)
		cancelBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
		cancelBtn.BorderSizePixel = 0
		cancelBtn.Text = "취소"
		cancelBtn.Font = F.NORMAL
		cancelBtn.TextSize = 12
		cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		cancelBtn.ZIndex = 6
		cancelBtn.Visible = false
		cancelBtn.Parent = actionArea
		local cancelCorner = Instance.new("UICorner"); cancelCorner.CornerRadius = UDim.new(0,3); cancelCorner.Parent = cancelBtn
		cancelBtn.MouseButton1Click:Connect(function()
			if currentCraftId then UIManager._DoCancel(currentCraftId) end
		end)

		local instantBtn = Instance.new("TextButton")
		instantBtn.Name = "InstantBtn"
		instantBtn.Size = UDim2.new(0.48, 0, 0, 18)
		instantBtn.Position = UDim2.new(1, 0, 0.5, 16)
		instantBtn.AnchorPoint = Vector2.new(1, 0)
		instantBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
		instantBtn.BorderSizePixel = 0
		instantBtn.Text = "즉시완료"
		instantBtn.Font = F.NORMAL
		instantBtn.TextSize = 12
		instantBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		instantBtn.ZIndex = 6
		instantBtn.Visible = false
		instantBtn.Parent = actionArea
		local instantCorner = Instance.new("UICorner"); instantCorner.CornerRadius = UDim.new(0,3); instantCorner.Parent = instantBtn
		instantBtn.MouseButton1Click:Connect(function()
			if currentCraftId and UIManager._DoInstantComplete then
				UIManager._DoInstantComplete(currentCraftId)
			end
		end)

		-- [COMPLETED] 수령 버튼
		local collectBtn = Instance.new("TextButton")
		collectBtn.Name = "CollectBtn"
		collectBtn.Size = UDim2.new(1, 0, 0, 38)
		collectBtn.Position = UDim2.new(0, 0, 0.5, 0)
		collectBtn.AnchorPoint = Vector2.new(0, 0.5)
		collectBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
		collectBtn.BorderSizePixel = 0
		collectBtn.Text = "✓  수령하기"
		collectBtn.Font = F.TITLE
		collectBtn.TextSize = 14
		collectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		collectBtn.ZIndex = 6
		collectBtn.Visible = false
		collectBtn.Parent = actionArea
		local collectCorner = Instance.new("UICorner"); collectCorner.CornerRadius = UDim.new(0,5); collectCorner.Parent = collectBtn
		collectBtn.MouseEnter:Connect(function() collectBtn.BackgroundColor3 = Color3.fromRGB(70, 210, 100) end)
		collectBtn.MouseLeave:Connect(function() collectBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80) end)
		collectBtn.MouseButton1Click:Connect(function()
			if currentCraftId then UIManager._DoCollect(currentCraftId) end
		end)

		-- 중앙 정보 영역 (action area 왼쪽까지만)
		local infoArea = Instance.new("Frame")
		infoArea.Size = UDim2.new(1, -(84 + ACTION_W + ACTION_PAD + 12), 1, 0)
		infoArea.Position = UDim2.new(0, 84, 0, 0)
		infoArea.BackgroundTransparency = 1
		infoArea.ZIndex = 3
		infoArea.Parent = inner

		Utils.mkLabel({
			text = UILocalizer.Localize(item.name or targetId),
			ts = 16, font = F.TITLE, color = C.WHITE,
			pos = UDim2.new(0,0,0.2,0), anchor = Vector2.new(0,0.5),
			ax = Enum.TextXAlignment.Left, parent = infoArea
		})

		local itemData = DataHelper.GetData("ItemData", targetId)
		local atkValue = itemData and (itemData.attack or itemData.damage or itemData.atk)
		local statsText = ""
		if atkValue then
			if itemData.type == "WEAPON" and itemData.damage then
				-- [품질 반영] 무기는 품질(0~100)에 따라 최종 공격력이 최솟값~최댓값 범위로 변동되므로 그 범위를 표기
				local minDmg = DataHelper.GetQualityAdjustedWeaponDamage(targetId, 0)
				local maxDmg = DataHelper.GetQualityAdjustedWeaponDamage(targetId, 100)
				statsText = string.format("공격력 : %d~%d", minDmg, maxDmg)
			else
				statsText = string.format("공격력 : %s", tostring(atkValue))
			end
		end
		local statsL = Utils.mkLabel({
			text = statsText,
			ts = 13, font = F.NORMAL, color = Color3.fromRGB(200,200,200),
			pos = UDim2.new(0,0,0.48,0), anchor = Vector2.new(0,0.5),
			ax = Enum.TextXAlignment.Left, parent = infoArea
		})
		statsL.Visible = (atkValue ~= nil)

		Utils.mkLabel({
			text = string.format("제작시간 : %ds", craftTime),
			ts = 13, font = F.NORMAL, color = C.INK,
			pos = UDim2.new(0,0,0.75,0), anchor = Vector2.new(0,0.5),
			ax = Enum.TextXAlignment.Left, parent = infoArea
		})

		-- 슬롯 클릭 (상세 패널) - action area를 침범하지 않도록 좌측 영역만 덮음
		local click = Instance.new("TextButton")
		click.Size = UDim2.new(1, -(ACTION_W + ACTION_PAD + 4), 1, 0)
		click.Position = UDim2.new(0, 0, 0, 0)
		click.BackgroundTransparency = 1
		click.Text = ""
		click.ZIndex = 4  -- inner(3) 위, actionArea(5) 아래
		click.Parent = inner

		local baseBorderColor = C.BORDER
		click.MouseEnter:Connect(function()
			if item.id ~= selectedRecipeId then
				borderFrame.BackgroundColor3 = C.BORDER_SEL or C.WHITE
				borderFrame.BackgroundTransparency = 0
			end
		end)
		click.MouseLeave:Connect(function()
			if item.id ~= selectedRecipeId then
				borderFrame.BackgroundColor3 = baseBorderColor
				borderFrame.BackgroundTransparency = 0.15
			end
		end)
		click.MouseButton1Click:Connect(function()
			selectedRecipeId = item.id
			updateSelectionHighlight()
			UIManager._OnCraftSlotClick(item, mode)
		end)

		CraftingUI.Refs.Slots[item.id] = {
			border = borderFrame,
			_baseBorderColor = baseBorderColor,
			idleBtn = idleBtn,
			progressArea = progressArea,
			barFill = barFill,
			pctLabel = pctLabel,
			timeLabel = timeLabel,
			cancelBtn = cancelBtn,
			instantBtn = instantBtn,
			collectBtn = collectBtn,
			_craftTime = craftTime,
			_setCraftId = function(id) currentCraftId = id end,
		}
	end

	updateSelectionHighlight()
end

-- 개별 슬롯의 진행 상태 업데이트
function CraftingUI.UpdateSlotProgress(recipeId, progressRatio, state, craftId, totalCraftTime)
	local slot = CraftingUI.Refs.Slots[recipeId]
	if not slot then return end

	if slot._setCraftId then slot._setCraftId(craftId) end

	local isCompleted = (state == "PENDING_COLLECT" or state == "COMPLETED" or (progressRatio and progressRatio >= 1))
	local isCrafting  = (state == "CRAFTING") and not isCompleted

	slot.idleBtn.Visible      = not isCrafting and not isCompleted
	slot.progressArea.Visible = isCrafting
	slot.cancelBtn.Visible    = isCrafting
	slot.instantBtn.Visible   = isCrafting
	slot.collectBtn.Visible   = isCompleted

	if isCrafting then
		local ratio = math.clamp(progressRatio or 0, 0, 1)
		slot.barFill.Size = UDim2.new(ratio, 0, 1, 0)
		slot.pctLabel.Text = string.format("제작 중 (%d%%)", math.floor(ratio * 100))

		local craftTime = totalCraftTime or slot._craftTime or 0
		if craftTime > 0 then
			local remain = math.max(0, math.ceil(craftTime * (1 - ratio)))
			slot.timeLabel.Text = string.format("남은 시간: %ds", remain)
		else
			slot.timeLabel.Text = ""
		end
	end

	if isCompleted then
		slot.border.BackgroundColor3 = Color3.fromRGB(30, 80, 40)
		slot.border.BackgroundTransparency = 0
	elseif isCrafting then
		slot.border.BackgroundColor3 = Color3.fromRGB(20, 50, 100)
		slot.border.BackgroundTransparency = 0
	else
		slot.border.BackgroundColor3 = slot._baseBorderColor
		slot.border.BackgroundTransparency = 0.15
	end
end

-- 큐 전체를 반영하여 모든 슬롯 업데이트
function CraftingUI.UpdateAllSlots(queue, _UIManager)
	-- 먼저 전체 슬롯을 IDLE 상태로 리셋
	for recipeId, slot in pairs(CraftingUI.Refs.Slots) do
		slot.idleBtn.Visible      = true
		slot.progressArea.Visible = false
		slot.cancelBtn.Visible    = false
		slot.instantBtn.Visible   = false
		slot.collectBtn.Visible   = false
		slot.border.BackgroundColor3 = slot._baseBorderColor
		slot.border.BackgroundTransparency = 0.15
		if selectedRecipeId == recipeId then
			slot.border.BackgroundColor3 = C.GOLD_SEL
			slot.border.BackgroundTransparency = 0
		end
		if slot._setCraftId then slot._setCraftId(nil) end
	end

	-- 큐 항목을 슬롯에 반영
	if not queue then return end
	for _, q in ipairs(queue) do
		CraftingUI.UpdateSlotProgress(q.recipeId, q.progressRatio, q.state, q.craftId, q.craftTime)
	end
end

function CraftingUI.UpdateDetail(item, mode, isLocked, canMake, playerItemCounts, DataHelper, getItemIcon, progressRatio, craftState)
	local d = CraftingUI.Refs.Detail
	if not d.Frame then return end

	if not item then
		d.Frame.Visible = false
		return
	end

	d.Frame.Visible = true
	local targetId = item.id
	if item.outputs and #item.outputs > 0 then targetId = item.outputs[1].itemId or item.outputs[1].id end

	local displayName = DataHelper and UILocalizer.LocalizeDataText("ItemData", tostring(targetId), "name", item.name or targetId) or (item.name or targetId)
	d.Name.Text = UILocalizer.Localize(displayName)
	d.Icon.Image = getItemIcon(targetId)

	if DataHelper then
		local data = DataHelper.GetData("ItemData", targetId)
		d.Desc.Text = data and data.description and UILocalizer.Localize(data.description) or UILocalizer.Localize("대상을 제작합니다.")
	else
		d.Desc.Text = UILocalizer.Localize("대상을 제작합니다.")
	end

	local matsText = ""
	local mats = item.inputs or item.requirements
	if mats then
		for _, inp in ipairs(mats) do
			local req = inp.count or inp.amount or 0
			local have = playerItemCounts[inp.itemId or inp.id] or 0
			local ok = have >= req
			local colorStr = ok and "#8CDC64" or "#FF4B32"
			local name = inp.itemId or inp.id
			if DataHelper then local idat = DataHelper.GetData("ItemData", name); if idat then name = idat.name end end
			matsText = matsText .. string.format("<font color=\"%s\">%s %s: %d / %d</font>\n", colorStr, ok and "✓" or "✗", UILocalizer.Localize(name), have, req)
		end
	end
	d.MatsText.Text = matsText

	if craftState == "CRAFTING" then
		d.BtnCraft.Text = UILocalizer.Localize("제작 진행 중")
		d.BtnCraft.BackgroundColor3 = C.BG_SLOT
		d.BtnCraft.TextColor3 = C.GRAY
		d.BtnCraft.AutoButtonColor = false
	elseif craftState == "PENDING_COLLECT" or craftState == "COMPLETED" or (progressRatio and progressRatio >= 1) then
		d.BtnCraft.Text = UILocalizer.Localize("아이템 수령")
		d.BtnCraft.BackgroundColor3 = Color3.fromRGB(140, 220, 100)
		d.BtnCraft.TextColor3 = C.BG_DARK
		d.BtnCraft.AutoButtonColor = true
	else
		d.BtnCraft.Text = UILocalizer.Localize((mode == "CRAFTING") and "제작 시작" or "건축 시작")
		if canMake then
			d.BtnCraft.BackgroundColor3 = C.GOLD_SEL
			d.BtnCraft.TextColor3 = C.BG_DARK
			d.BtnCraft.AutoButtonColor = true
		else
			d.BtnCraft.BackgroundColor3 = C.BG_SLOT
			d.BtnCraft.TextColor3 = C.GRAY
			d.BtnCraft.AutoButtonColor = false
		end
	end
end

-- 하위 호환: 더 이상 팝업 모달을 사용하지 않지만 외부 호출을 위해 빈 함수로 유지
function CraftingUI.ShowProgressModal() end
function CraftingUI.HideProgressModal() end

return CraftingUI
