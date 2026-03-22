local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local CraftingUI = {}

CraftingUI.Refs = {
	Frame = nil,
	Title = nil,
	GridScroll = nil,
	Slots = {}, -- 슬롯 참조 저장용
	Detail = {
		Frame = nil,
		Name = nil,
		Icon = nil,
		Desc = nil,
		MatsText = nil,
		BtnCraft = nil,
	}
}

local selectedRecipeId = nil

----------------------------------------------------------------
-- 선택 하이라이트 업데이트
----------------------------------------------------------------
local function updateSelectionHighlight()
	for id, slotData in pairs(CraftingUI.Refs.Slots) do
		local borderFrame = slotData.border
		if id == selectedRecipeId then
			borderFrame.BackgroundColor3 = C.GOLD
			borderFrame.BackgroundTransparency = 0
		else
			borderFrame.BackgroundColor3 = slotData._baseBorderColor or C.BORDER
			borderFrame.BackgroundTransparency = 0.15
		end
	end
end

function CraftingUI.Init(parent, UIManager)
	CraftingUI.Refs.Frame = Utils.mkFrame({
		name = "CraftingMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent
	})
	
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isSmall and 0.95 or 0.75, 0, isSmall and 0.9 or 0.85, 0),
		maxSize = Vector2.new(1000, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = CraftingUI.Refs.Frame
	})

	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,55), bgT=1, parent=main})
	CraftingUI.Refs.Title = Utils.mkLabel({text="CRAFTING TOOLS [C]", pos=UDim2.new(0, 20, 0, 0), ts=20, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1,0.5), bg=C.BTN, bgT=0.5, ts=20, color=C.WHITE, r=4, fn=function() UIManager.closeCrafting() end, parent=header})

	local canvasWrapper = Utils.mkFrame({
		name="CanvasWrap", size=UDim2.new(1, 0, 1, -45),
		pos=UDim2.new(0,0,0,45), bgT=1, parent=main
	})
	
	-- Left Side: Grid
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(1, -340, 1, 0), bgT=1, parent=canvasWrapper})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, -5, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = C.GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0,0,0,0)
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 75, 0, 75)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = scroll
	
	CraftingUI.Refs.GridScroll = scroll
	
	-- Right Side: Detail Panel (Modern Sleek)
	local detailSize = 320
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(0, detailSize, 1, -16),
		pos=UDim2.new(1, -detailSize - 8, 0, 8),
		bg=C.BG_PANEL, bgT=math.max((T.PANEL or 0.95) - 0.03, 0), r=6, stroke=false,
		parent=canvasWrapper
	})
	CraftingUI.Refs.Detail.Frame = detail
	detail.Visible = false
	
	local dtHead = Utils.mkLabel({
		text="RECIPE INFO", size=UDim2.new(1,0,0,45),
		bg=C.BG_DARK, bgT=0.3, color=C.GOLD, ts=16, font=F.TITLE,
		parent=detail
	})
	
	CraftingUI.Refs.Detail.Name = Utils.mkLabel({
		text="NAME", size=UDim2.new(1,-30,0,40), pos=UDim2.new(0,15,0,55),
		color=C.WHITE, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	CraftingUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	CraftingUI.Refs.Detail.Icon.Size = UDim2.new(0, 80, 0, 80); CraftingUI.Refs.Detail.Icon.Position = UDim2.new(0,15,0,95)
	CraftingUI.Refs.Detail.Icon.BackgroundTransparency = 1; CraftingUI.Refs.Detail.Icon.Parent = detail
	
	CraftingUI.Refs.Detail.Desc = Utils.mkLabel({
		text="Description", size=UDim2.new(1,-120,0,105), pos=UDim2.new(0,115,0,105),
		color=C.GRAY, ts=15, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detail
	})

	-- 재료 영역
	local matLabel = Utils.mkLabel({
		text="[ MATS REQUIRED ]", size=UDim2.new(1,-30,0,25), pos=UDim2.new(0,15,0,210),
		ts=15, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	CraftingUI.Refs.Detail.MatsText = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,0,150), pos=UDim2.new(0,15,0,240),
		ts=16, color=C.WHITE, rich=true, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=detail
	})

	-- [제작 진행표시] 로딩 스피너 및 프로그레스바 추가
	local progWrap = Utils.mkFrame({name="ProgWrap", size=UDim2.new(0, 80, 0, 80), pos=UDim2.new(0,15,0,95), bgT=1, vis=false, parent=detail})
	CraftingUI.Refs.Detail.ProgWrap = progWrap
	
	local spinner = Instance.new("ImageLabel")
	spinner.Name = "Spinner"; spinner.Size = UDim2.new(1.2, 0, 1.2, 0); spinner.Position = UDim2.new(0.5, 0, 0.5, 0); spinner.AnchorPoint = Vector2.new(0.5,0.5)
	spinner.BackgroundTransparency = 1; spinner.Image = "rbxassetid://6034445544"; spinner.ImageColor3 = C.GOLD; spinner.ZIndex = 15; spinner.Parent = progWrap
	CraftingUI.Refs.Detail.Spinner = spinner

	local barBack = Utils.mkFrame({name="BarBack", size=UDim2.new(1, -24, 0, 6), pos=UDim2.new(0.5, 0, 0, 185), anchor=Vector2.new(0.5, 0), bg=C.BG_SLOT, r=3, vis=false, parent=detail})
	local barFill = Utils.mkFrame({name="Fill", size=UDim2.new(0, 0, 1, 0), bg=C.GOLD, r=3, parent=barBack})
	CraftingUI.Refs.Detail.ProgBar = barBack
	CraftingUI.Refs.Detail.ProgFill = barFill
	
	CraftingUI.Refs.Detail.BtnCraft = Utils.mkBtn({
		text=UILocalizer.Localize("제작 시작"), size=UDim2.new(1, -24, 0, 50), pos=UDim2.new(0, 12, 1, -62),
		bg=C.GOLD, color=C.BG_DARK, ts=18, font=F.TITLE, r=5,
		fn=function() UIManager._doCraft() end, parent=detail
	})
end

function CraftingUI.SetVisible(visible)
	if CraftingUI.Refs.Frame then
		CraftingUI.Refs.Frame.Visible = visible
	end
end

function CraftingUI.UpdateTitle(title)
	if CraftingUI.Refs.Title then CraftingUI.Refs.Title.Text = title end
end

function CraftingUI.Refresh(items, playerItemCounts, getItemIcon, mode, UIManager)
	local scroll = CraftingUI.Refs.GridScroll
	if not scroll then return end

	for _, ch in pairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end
	
	CraftingUI.Refs.Slots = {}

	for _, item in ipairs(items) do
		local isLocked = item.isLocked
		local canMake, _ = UIManager.checkMaterials(item, playerItemCounts)
		
		-- ===== UIStroke 대신 배경색 보더 기법 (클리핑 완전 회피) =====
		-- 1) 보더 프레임: 배경색 = 테두리 색상, UIGridLayout이 75x75로 제어
		local borderFrame = Instance.new("Frame")
		borderFrame.Name = item.id
		borderFrame.BackgroundColor3 = C.BORDER
		borderFrame.BackgroundTransparency = 0.15
		borderFrame.BorderSizePixel = 0
		borderFrame.Parent = scroll
		local borderCorner = Instance.new("UICorner")
		borderCorner.CornerRadius = UDim.new(0, 8)
		borderCorner.Parent = borderFrame

		-- 2) 내부 콘텐츠 프레임: 보더 안쪽 2px 인셋
		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.Size = UDim2.new(1, -4, 1, -4)
		inner.Position = UDim2.new(0.5, 0, 0.5, 0)
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.BackgroundColor3 = C.BG_SLOT
		inner.BackgroundTransparency = 0.2
		inner.BorderSizePixel = 0
		inner.Parent = borderFrame
		local innerCorner = Instance.new("UICorner")
		innerCorner.CornerRadius = UDim.new(0, 6)
		innerCorner.Parent = inner

		-- 3) 아이콘
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.7, 0, 0.7, 0)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = getItemIcon(item.id)
		icon.ImageColor3 = Color3.new(1, 1, 1)
		icon.ZIndex = 2
		icon.Parent = inner

		-- 4) 클릭 버튼
		local click = Instance.new("TextButton")
		click.Name = "Click"
		click.Size = UDim2.new(1, 0, 1, 0)
		click.BackgroundTransparency = 1
		click.Text = ""
		click.ZIndex = 5
		click.Parent = borderFrame

		-- 5) 상태별 색상 적용
		local baseBorderColor = C.BORDER

		if isLocked then
			inner.BackgroundColor3 = Color3.fromRGB(38, 22, 25)
			icon.ImageColor3 = Color3.new(0.4, 0.4, 0.4)
			baseBorderColor = C.BORDER_DIM
			borderFrame.BackgroundColor3 = baseBorderColor
			borderFrame.BackgroundTransparency = 0.4
			local lockIcon = Instance.new("ImageLabel")
			lockIcon.Size = UDim2.new(0,24,0,24); lockIcon.Position = UDim2.new(1,0,0,0); lockIcon.AnchorPoint = Vector2.new(1,0)
			lockIcon.BackgroundTransparency = 1; lockIcon.Image = "rbxassetid://6031084651"; lockIcon.ZIndex = 50; lockIcon.Parent = inner
		elseif not canMake then
			inner.BackgroundColor3 = C.BG_SLOT
			baseBorderColor = C.BORDER
		else
			inner.BackgroundColor3 = Color3.fromRGB(42, 40, 30)
			baseBorderColor = C.GOLD
			borderFrame.BackgroundColor3 = baseBorderColor
		end

		-- 6) Hover 효과
		click.MouseEnter:Connect(function()
			if item.id ~= selectedRecipeId then
				borderFrame.BackgroundColor3 = C.GOLD
				borderFrame.BackgroundTransparency = 0
			end
		end)
		click.MouseLeave:Connect(function()
			if item.id ~= selectedRecipeId then
				borderFrame.BackgroundColor3 = baseBorderColor
				borderFrame.BackgroundTransparency = 0.15
			end
		end)

		-- 7) Refs 저장 (기존 인터페이스 호환)
		local slotData = {
			frame = inner,
			border = borderFrame,
			icon = icon,
			click = click,
			_baseBorderColor = baseBorderColor,
		}
		CraftingUI.Refs.Slots[item.id] = slotData

		click.MouseButton1Click:Connect(function()
			selectedRecipeId = item.id
			updateSelectionHighlight()
			UIManager._onCraftSlotClick(item, mode)
		end)
	end
	
	updateSelectionHighlight()
end

function CraftingUI.UpdateDetail(item, mode, isLocked, canMake, playerItemCounts, DataHelper, getItemIcon)
	local d = CraftingUI.Refs.Detail
	if not d.Frame then return end
	
	if not item then
		d.Frame.Visible = false
		return
	end

	d.Frame.Visible = true
	local displayName = item.name or item.id
	d.Icon.Image = getItemIcon and getItemIcon(item.id) or item.id
	
	if DataHelper then
		-- 레시피인 경우 결과물 아이템 아이디를 가져옴
		local targetId = item.id
		if item.outputs and #item.outputs > 0 then
			targetId = item.outputs[1].itemId or item.outputs[1].id
		end

		displayName = UILocalizer.LocalizeDataText("ItemData", tostring(targetId), "name", displayName)
		d.Name.Text = displayName
		
		local data = DataHelper.GetData("ItemData", targetId)
		if data and data.description then
			d.Desc.Text = UILocalizer.Localize(data.description)
		elseif data and data.name then
			d.Desc.Text = UILocalizer.Localize(data.name .. " 을(를) 제작합니다.")
		else
			d.Desc.Text = UILocalizer.Localize("선택한 대상을 제작합니다.")
		end
	else
		d.Name.Text = UILocalizer.Localize(displayName)
	end

	if isLocked then
		d.MatsText.Text = string.format("<font color=\"#E63232\">✗ %s</font>", UILocalizer.Localize("기술 트리에서 해금 필요"))
		d.BtnCraft.Visible = true
		d.BtnCraft.Text = UILocalizer.Localize("잠김")
		d.BtnCraft.BackgroundColor3 = C.BG_SLOT
		d.BtnCraft.TextColor3 = Color3.fromRGB(95, 90, 80)
		d.BtnCraft.AutoButtonColor = false
		return
	end

	local matsText = ""
	local mats = item.inputs or item.requirements
	if mats then
		for _, inp in ipairs(mats) do
			local req = inp.count or inp.amount or 0
			local have = playerItemCounts[inp.itemId or inp.id] or 0
			local ok = have >= req
			
			local itemName = inp.itemId or inp.id
			if DataHelper then
				local itemData = DataHelper.GetData("ItemData", itemName)
				if itemData then itemName = itemData.name end
			end
			itemName = UILocalizer.Localize(itemName)
			
			local colorStr = ok and "#8CDC64" or "#E63232"
			local prefix = ok and "✓ " or "✗ "
			matsText = matsText .. string.format("<font color=\"%s\">%s%s: %d / %d</font>\n", colorStr, prefix, itemName, have, req)
		end
	end
	
	d.MatsText.Text = matsText
	
	d.BtnCraft.Visible = true
	d.BtnCraft.Text = UILocalizer.Localize((mode == "CRAFTING") and "제작 시작" or "건축 시작")
	
	if canMake then
		d.BtnCraft.BackgroundColor3 = C.GOLD
		d.BtnCraft.TextColor3 = C.BG_DARK
		d.BtnCraft.AutoButtonColor = true
	else
		d.BtnCraft.BackgroundColor3 = C.BG_SLOT
		d.BtnCraft.TextColor3 = Color3.fromRGB(95, 90, 80)
		d.BtnCraft.AutoButtonColor = false
	end
end

return CraftingUI
