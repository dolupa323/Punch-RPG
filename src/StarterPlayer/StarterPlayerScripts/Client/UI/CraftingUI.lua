-- CraftingUI.lua
-- 듀랑고 레퍼런스 스타일 제작/건축 종합 반응형 UI
-- PC/Mobile 통합 지원

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)

-- Local Color Override for Navy + Black Theme (Match Equipment/Inventory)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
C.BG_SLOT = Color3.fromRGB(12, 12, 15) -- Near Black (Matches Inventory)
C.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White!
C.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN = Color3.fromRGB(40, 80, 160)      -- Action Buttons -> Navy

local F = Theme.Fonts
local T = Theme.Transp

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

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
	ProgressModal = {
		Overlay = nil,
		Window = nil,
		Icon = nil,
		NameLabel = nil,
		BarFill = nil,
		PctLabel = nil,
		BtnAction = nil,
	}
}

local selectedRecipeId = nil
local _isSmall = false
local progressModalCallback = nil -- [NEW] 제작 진행 모달 전용 다이나믹 콜백

----------------------------------------------------------------
-- 선택 하이라이트 업데이트
----------------------------------------------------------------
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

----------------------------------------------------------------
-- 초기화 (반응형 레이아웃 구성)
----------------------------------------------------------------
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
	CraftingUI.Refs.Title = Utils.mkLabel({text="무기 제작 (Weapon Crafting)", pos=UDim2.new(0, 15, 0, 0), ts=26, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	
	Utils.mkBtn({
		text = "X", 
		size = UDim2.new(0, 42, 0, 42), 
		pos = UDim2.new(1, -10, 0.5, 0), 
		anchor = Vector2.new(1, 0.5), 
		isNegative = true,
		bgT = 0.5, ts = 24, color = C.WHITE, r = 4, z = 100, 
		fn = function() 
			local WindowManager = require(script.Parent.Parent.Utils.WindowManager)
			WindowManager.close("CRAFTING") 
		end, 
		parent = header
	})

	local canvasWrapper = Utils.mkFrame({
		name="CanvasWrap", size=UDim2.new(1, -20, 1, -65),
		pos=UDim2.new(0, 10, 0, 55), bgT=1, parent=main
	})
	
	-- Left Side: Grid (Responsive Ratio)
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(_isSmall and 1 or 0.6, -5, 1, 0), bgT=1, parent=canvasWrapper})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.GOLD_SEL
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0,0,0,0)
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 78, 0, 78) -- 고정 크기 슬롯이지만 배치는 반응형
	grid.CellPadding = UDim2.new(0, 12, 0, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 15)
	pad.Parent = scroll
	
	CraftingUI.Refs.GridScroll = scroll
	
	-- Right Side: Detail Panel (Responsive Ratio)
	local detail = Utils.mkFrame({
		name="Detail", 
		size=UDim2.new(_isSmall and 0.9 or 0.4, -10, _isSmall and 0.8 or 1, 0),
		pos=UDim2.new(1, 0, _isSmall and 0.5 or 0, 0),
		anchor=Vector2.new(1, _isSmall and 0.5 or 0),
		bg=C.BG_DARK, bgT=0.3, r=6, stroke=true, strokeC=C.BORDER,
		parent=canvasWrapper
	})
	
	if _isSmall then
		-- 모바일 팝업용 위치 조정 (중앙 배치)
		detail.Position = UDim2.new(0.5, 0, 0.5, 0)
		detail.AnchorPoint = Vector2.new(0.5, 0.5)
		detail.ZIndex = 50
		
		local closeDetail = Utils.mkBtn({
			text="<", size=UDim2.new(0, 44, 0, 44), pos=UDim2.new(0, 5, 0, 5),
			bgT=0.5, ts=22, color=C.WHITE, r=4, fn=function() detail.Visible = false end, parent=detail
		})
	end
	CraftingUI.Refs.Detail.Frame = detail
	detail.Visible = false
	
	local dtHead = Utils.mkLabel({
		text="RECIPE INFO", size=UDim2.new(1,0,0,45),
		bg=C.BG_DARK, bgT=0.5, color=C.GOLD, ts=16, font=F.TITLE,
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

	local matLabel = Utils.mkLabel({
		text="[ MATS REQUIRED ]", size=UDim2.new(1,-30,0,25), pos=UDim2.new(0,15,0,210),
		ts=15, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	CraftingUI.Refs.Detail.MatsText = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,0,150), pos=UDim2.new(0,15,0,240),
		ts=16, color=C.WHITE, rich=true, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=detail
	})

	-- 제작 진행표시
	local progWrap = Utils.mkFrame({name="ProgWrap", size=UDim2.new(0, 80, 0, 80), pos=UDim2.new(0,15,0,95), bgT=1, vis=false, parent=detail})
	CraftingUI.Refs.Detail.ProgWrap = progWrap
	
	local spinner = Instance.new("ImageLabel")
	spinner.Name = "Spinner"; spinner.Size = UDim2.new(1.2, 0, 1.2, 0); spinner.Position = UDim2.new(0.5, 0, 0.5, 0); spinner.AnchorPoint = Vector2.new(0.5,0.5)
	spinner.BackgroundTransparency = 1; spinner.Image = "rbxassetid://6034445544"; spinner.ImageColor3 = C.GOLD_SEL; spinner.ZIndex = 15; spinner.Parent = progWrap
	CraftingUI.Refs.Detail.Spinner = spinner

	local barBack = Utils.mkFrame({name="BarBack", size=UDim2.new(1, -24, 0, 6), pos=UDim2.new(0.5, 0, 0, 195), anchor=Vector2.new(0.5, 0), bg=C.BG_DARK, r=3, vis=false, parent=detail})
	local barFill = Utils.mkFrame({name="Fill", size=UDim2.new(0, 0, 1, 0), bg=C.GOLD_SEL, r=3, parent=barBack})
	CraftingUI.Refs.Detail.ProgBar = barBack
	CraftingUI.Refs.Detail.ProgFill = barFill
	
	CraftingUI.Refs.Detail.BtnCraft = Utils.mkBtn({
		text=UILocalizer.Localize("제작 시작"), size=UDim2.new(1, -24, 0, 52), pos=UDim2.new(0, 12, 1, -62),
		bg=C.GOLD_SEL, color=C.BG_DARK, ts=20, font=F.TITLE, r=5,
		fn=function() UIManager._DoCraft() end, parent=detail
	})
	
	----------------------------------------------------------------
	-- 별도 제작 진행 모달 (Progress Modal Popup) [NEW]
	----------------------------------------------------------------
	local overlay = Utils.mkFrame({
		name = "ProgressOverlay",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 0.65, -- 뒤쪽 무기제작 창을 부드럽게 어둡게 덮음
		z = 500,
		vis = false,
		parent = CraftingUI.Refs.Frame
	})
	
	local win = Utils.mkWindow({
		name = "ProgressWindow",
		size = UDim2.new(0, 480, 0, 320),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.05, -- 불투명에 가깝게 하여 고급스러운 느낌 배가
		r = 10,
		stroke = 2.5,
		strokeC = C.BORDER,
		z = 501,
		parent = overlay
	})
	
	local mHeader = Utils.mkFrame({name="MHeader", size=UDim2.new(1, 0, 0, 45), bgT=1, parent=win})
	Utils.mkLabel({
		text = "제작 진행 상태 (Crafting Progress)",
		pos = UDim2.new(0, 15, 0, 0),
		ts = 18,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = mHeader
	})
	-- 모달 중앙 아이템 아이콘
	local mIcon = Instance.new("ImageLabel")
	mIcon.Name = "MIcon"
	mIcon.Size = UDim2.new(0, 72, 0, 72)
	mIcon.Position = UDim2.new(0.5, 0, 0, 55)
	mIcon.AnchorPoint = Vector2.new(0.5, 0)
	mIcon.BackgroundTransparency = 1
	mIcon.ScaleType = Enum.ScaleType.Fit
	mIcon.ZIndex = 502
	mIcon.Parent = win
	
	-- 모달 중앙 아이템 이름 및 상태 문구
	local mName = Utils.mkLabel({
		text = "말랑봉",
		pos = UDim2.new(0.5, 0, 0, 135),
		anchor = Vector2.new(0.5, 0),
		ts = 20,
		font = F.TITLE,
		color = C.WHITE,
		parent = win
	})
	
	-- 모달 실시간 가로형 프로그레스 바
	local mBarBack = Utils.mkFrame({
		name = "MBarBack",
		size = UDim2.new(0.85, 0, 0, 24),
		pos = UDim2.new(0.5, 0, 0, 180),
		anchor = Vector2.new(0.5, 0),
		bg = C.BG_DARK,
		r = 6,
		stroke = 1.2,
		strokeC = C.BORDER_DIM,
		z = 502,
		parent = win
	})
	
	local mBarFill = Utils.mkFrame({
		name = "MFill",
		size = UDim2.new(0, 0, 1, 0),
		bg = Color3.fromRGB(40, 140, 240), -- 세련되고 이쁜 파란색 바
		r = 6,
		z = 503,
		parent = mBarBack
	})
	
	-- 프로그레스 바 내부 퍼센트 수치 (0% ~ 100%)
	local mPct = Utils.mkLabel({
		text = "제작 중 (0%)",
		size = UDim2.new(1, 0, 1, 0),
		ts = 14,
		font = F.NUM,
		color = C.WHITE,
		z = 505,
		parent = mBarBack
	})
	
	-- 모달 하단 액션 버튼 (평소엔 창닫기, 완료 시에는 산뜻한 아이템 수령 버튼으로 변신!)
	local mBtnAction = Utils.mkBtn({
		text = "닫기",
		size = UDim2.new(0.85, 0, 0, 44),
		pos = UDim2.new(0.5, 0, 1, -15),
		anchor = Vector2.new(0.5, 1),
		bg = C.BTN,
		color = C.WHITE,
		ts = 16,
		font = F.TITLE,
		r = 5,
		z = 504,
		parent = win
	})
	
	mBtnAction.MouseButton1Click:Connect(function()
		if progressModalCallback then
			progressModalCallback()
		end
	end)
	
	-- 모달 참조 캐시 저장
	CraftingUI.Refs.ProgressModal.Overlay = overlay
	CraftingUI.Refs.ProgressModal.Window = win
	CraftingUI.Refs.ProgressModal.Icon = mIcon
	CraftingUI.Refs.ProgressModal.NameLabel = mName
	CraftingUI.Refs.ProgressModal.BarFill = mBarFill
	CraftingUI.Refs.ProgressModal.PctLabel = mPct
	CraftingUI.Refs.ProgressModal.BtnAction = mBtnAction
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
	local scroll = CraftingUI.Refs.GridScroll
	if not scroll then return end

	-- 1) 레이아웃 초기화 및 ListLayout 설정
	for _, ch in pairs(scroll:GetChildren()) do
		if (ch:IsA("GuiObject") or ch:IsA("UIGridLayout")) and not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end
	end
	
	local listLayout = scroll:FindFirstChildOfClass("UIListLayout")
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 8)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = scroll
	end
	
	CraftingUI.Refs.Slots = {}

	-- 2) 티어(techLevel) / 제작 시간순 / 이름순 정렬
	table.sort(items, function(a, b)
		local aTech = a.techLevel or a.rarity or 0
		local bTech = b.techLevel or b.rarity or 0
		if aTech ~= bTech then return aTech < bTech end
		
		local aTime = a.craftTime or 0
		local bTime = b.craftTime or 0
		if aTime ~= bTime then return aTime < bTime end
		
		return (a.name or "") < (b.name or "")
	end)

	for i, item in ipairs(items) do
		local canMake, _ = UIManager.checkMaterials(item, playerItemCounts)
		local targetId = item.id
		if item.outputs and #item.outputs > 0 then targetId = item.outputs[1].itemId or item.outputs[1].id end
		
		-- 가로형 슬롯 프레임
		local borderFrame = Instance.new("Frame")
		borderFrame.Name = item.id
		borderFrame.Size = UDim2.new(1, -20, 0, 80) -- 가로 길이 여유 확보(우측 테두리 짤림 방지)
		borderFrame.BackgroundColor3 = C.BORDER
		borderFrame.BackgroundTransparency = 0.15
		borderFrame.BorderSizePixel = 0
		borderFrame.LayoutOrder = i
		borderFrame.Parent = scroll
		local borderCorner = Instance.new("UICorner")
		borderCorner.CornerRadius = UDim.new(0, 6)
		borderCorner.Parent = borderFrame

		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.Size = UDim2.new(1, -2, 1, -2)
		inner.Position = UDim2.new(0.5, 0, 0.5, 0)
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.BackgroundColor3 = C.BG_SLOT
		inner.BackgroundTransparency = 0 -- Opaque per user request
		inner.Parent = borderFrame
		local innerCorner = Instance.new("UICorner")
		innerCorner.CornerRadius = UDim.new(0, 5)
		innerCorner.Parent = inner

		-- [좌측] 아이콘
		local iconBg = Instance.new("Frame")
		iconBg.Size = UDim2.new(0, 64, 0, 64)
		iconBg.Position = UDim2.new(0, 8, 0.5, 0)
		iconBg.AnchorPoint = Vector2.new(0, 0.5)
		iconBg.BackgroundColor3 = C.BG_DARK
		iconBg.BorderSizePixel = 0
		iconBg.Parent = inner
		local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 4); ic.Parent = iconBg
		local st = Instance.new("UIStroke"); st.Color = C.BORDER_DIM; st.Thickness = 1; st.Parent = iconBg

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0.85, 0, 0.85, 0); icon.Position = UDim2.new(0.5, 0, 0.5, 0); icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = getItemIcon(targetId); icon.Parent = iconBg

		-- [중앙] 정보 영역
		local infoArea = Instance.new("Frame")
		infoArea.Size = UDim2.new(1, -200, 1, 0)
		infoArea.Position = UDim2.new(0, 84, 0, 0)
		infoArea.BackgroundTransparency = 1
		infoArea.Parent = inner
		
		local nameL = Utils.mkLabel({
			text = UILocalizer.Localize(item.name or targetId),
			ts = 16, font = F.TITLE, color = C.WHITE,
			pos = UDim2.new(0, 0, 0.25, 0), anchor = Vector2.new(0, 0.5),
			ax = Enum.TextXAlignment.Left, parent = infoArea
		})

		-- 공격력 정보 가져오기 (DataHelper 활용)
		local atkValue = nil
		local data = DataHelper.GetData("ItemData", targetId)
		if data then
			atkValue = data.attack or data.damage or data.atk
		end

		local statsL = Utils.mkLabel({
			text = atkValue and string.format("공격력 : %s", tostring(atkValue)) or "",
			ts = 13, font = F.NORMAL, color = Color3.fromRGB(200, 200, 200),
			pos = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5),
			ax = Enum.TextXAlignment.Left, parent = infoArea
		})
		statsL.Visible = (atkValue ~= nil)
		
		local craftTime = item.craftTime or 180
		local timeL = Utils.mkLabel({
			text = string.format("제작시간 : %ds", craftTime),
			ts = 13, font = F.NORMAL, color = C.INK,
			pos = UDim2.new(0, 0, 0.75, 0), anchor = Vector2.new(0, 0.5),
			ax = Enum.TextXAlignment.Left, parent = infoArea
		})

		-- [우측] 클릭 안내
		local promptL = Utils.mkLabel({
			text = "클릭하여 상세보기",
			ts = 13, font = F.NORMAL, color = C.GRAY,
			pos = UDim2.new(1, -10, 0.5, 0), anchor = Vector2.new(1, 0.5),
			ax = Enum.TextXAlignment.Right, parent = inner
		})

		local click = Instance.new("TextButton")
		click.Size = UDim2.new(1, 0, 1, 0); click.BackgroundTransparency = 1; click.Text = ""; click.ZIndex = 5; click.Parent = borderFrame

		local baseBorderColor = C.BORDER
		borderFrame.BackgroundColor3 = baseBorderColor

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

		CraftingUI.Refs.Slots[item.id] = { border = borderFrame, _baseBorderColor = baseBorderColor }

		click.MouseButton1Click:Connect(function()
			selectedRecipeId = item.id
			updateSelectionHighlight()
			UIManager._OnCraftSlotClick(item, mode)
		end)
	end
	
	updateSelectionHighlight()
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
	
	-- 실시간 제작 진행 및 미제작 상태에 따른 상세창 버튼 제어
	if craftState == "CRAFTING" then
		-- 이미 제작 중인 경우: 디테일 창에서는 '제작 진행 중' 비활성화 표출 (실시간 진행은 별도 모달이 전담)
		if d.ProgBar then d.ProgBar.Visible = false end
		d.BtnCraft.Text = UILocalizer.Localize("제작 진행 중")
		d.BtnCraft.BackgroundColor3 = C.BG_SLOT
		d.BtnCraft.TextColor3 = C.GRAY
		d.BtnCraft.AutoButtonColor = false
	elseif craftState == "PENDING_COLLECT" or craftState == "COMPLETED" or (progressRatio and progressRatio >= 1) then
		-- 제작 완료: 디테일 창 버튼도 수령 활성화 지원
		if d.ProgBar then d.ProgBar.Visible = false end
		d.BtnCraft.Text = UILocalizer.Localize("아이템 수령")
		d.BtnCraft.BackgroundColor3 = Color3.fromRGB(140, 220, 100) -- 연두색
		d.BtnCraft.TextColor3 = C.BG_DARK
		d.BtnCraft.AutoButtonColor = true
	else
		-- 기본 미제작 상태
		if d.ProgBar then d.ProgBar.Visible = false end
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

----------------------------------------------------------------
-- 별도 제작 진행 모달 표출 및 실시간 업데이트 [NEW]
----------------------------------------------------------------
function CraftingUI.ShowProgressModal(recipe, progressRatio, craftState, UIManager, craftId)
	local pm = CraftingUI.Refs.ProgressModal
	if not pm.Overlay then return end
	
	pm.Overlay.Visible = true
	
	-- 1. 아이콘 & 이름 바인딩
	if recipe then
		local targetId = recipe.id
		if recipe.outputs and #recipe.outputs > 0 then
			targetId = recipe.outputs[1].itemId or recipe.outputs[1].id
		end
		pm.Icon.Image = UIManager.getItemIcon(targetId)
	-- 2. 진행바 비주얼 업데이트
	local ratio = math.clamp(progressRatio or 0, 0, 1)
	pm.BarFill.Size = UDim2.new(ratio, 0, 1, 0)
	
	local pct = math.floor(ratio * 100)
	local totalTime = recipe.craftTime or 0
	local remainTime = math.max(0, math.ceil(totalTime * (1 - ratio)))
	
	-- 3. 상태 분기별 렌더링 & 버튼 동적 콜백 갈아끼우기
	if craftState == "PENDING_COLLECT" or craftState == "COMPLETED" or ratio >= 1 then
		pm.PctLabel.Text = UILocalizer.Localize("제작 완료! (100%)")
		pm.BarFill.BackgroundColor3 = Color3.fromRGB(140, 220, 100)
		
		pm.BtnAction.Text = UILocalizer.Localize("아이템 수령")
		pm.BtnAction.BackgroundColor3 = Color3.fromRGB(140, 220, 100)
		pm.BtnAction.TextColor3 = Color3.fromRGB(10, 15, 25)
		
		progressModalCallback = function()
			if craftId then UIManager._DoCollect(craftId) end
			pm.Overlay.Visible = false
		end
	else
		if totalTime > 0 then
			pm.PctLabel.Text = UILocalizer.Localize(string.format("제작 중 (%d%%) - 남은 시간: %ds", pct, remainTime))
		else
			pm.PctLabel.Text = UILocalizer.Localize(string.format("제작 중 (%d%%)", pct))
		end
		
		pm.BarFill.BackgroundColor3 = Color3.fromRGB(40, 140, 240)
		
		pm.BtnAction.Text = UILocalizer.Localize("제작 취소")
		pm.BtnAction.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		pm.BtnAction.TextColor3 = Color3.fromRGB(255, 255, 255)
		pm.BtnAction.AutoButtonColor = true
		
		progressModalCallback = function()
			if craftId then UIManager._DoCancel(craftId) end
			pm.Overlay.Visible = false
		end
	end

	end
end

function CraftingUI.HideProgressModal()
	local pm = CraftingUI.Refs.ProgressModal
	if pm.Overlay then
		pm.Overlay.Visible = false
	end
end

return CraftingUI
