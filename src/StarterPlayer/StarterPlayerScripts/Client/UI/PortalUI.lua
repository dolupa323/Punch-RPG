-- PortalUI.lua
-- 고대 포탈 상호작용 UI (WindowManager 연동)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)

local C = Theme.Colors
local F = Theme.Fonts

local PortalUI = {}
PortalUI.Refs = {}

local currentUIManager = nil
local statusData = nil
local currentTab = "REPAIR" -- REPAIR | USE

-- forward declarations
local renderUseTab
local renderRepairTab

----------------------------------------------------------------
-- Init
----------------------------------------------------------------
function PortalUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager

	local window = Utils.mkWindow({
		name = "PortalWindow",
		size = UDim2.new(0.88, 0, 0.6, 0),
		maxSize = Vector2.new(470, 500),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.5,
		stroke = 1,
		strokeC = C.BORDER,
		vis = false,
		parent = parent,
	})
	PortalUI.Refs.Frame = window

	-- 제목
	Utils.mkLabel({
		text = "고대 포탈",
		size = UDim2.new(1, -70, 0, 46),
		pos = UDim2.new(0, 16, 0, 10),
		font = F.TITLE,
		ts = 24,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	-- 닫기 버튼
	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 42, 0, 42),
		pos = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		ts = 20,
		fn = function()
			UIManager.closePortal()
		end,
		parent = window,
	})

	-- 탭 영역 (ShopUI 컨벤션: 투명 컨테이너 + UIListLayout)
	local tabContainer = Utils.mkFrame({
		name = "TabContainer",
		size = UDim2.new(1, -32, 0, 40),
		pos = UDim2.new(0, 16, 0, 62),
		bgT = 1,
		parent = window,
	})
	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal
	tabList.Padding = UDim.new(0, 10)
	tabList.Parent = tabContainer

	PortalUI.Refs.BtnRepairTab = Utils.mkBtn({
		text = "포탈 활성화",
		size = UDim2.new(0.48, 0, 0, 40),
		bg = C.BTN_H,
		font = F.TITLE,
		ts = 14,
		r = 4,
		parent = tabContainer,
	})

	local btnUse = Utils.mkBtn({
		text = "포탈 이용",
		size = UDim2.new(0.48, 0, 0, 40),
		bg = C.BTN,
		font = F.TITLE,
		ts = 14,
		r = 4,
		parent = tabContainer,
	})
	btnUse.Visible = false
	PortalUI.Refs.BtnUseTab = btnUse
	PortalUI.Refs.TabContainer = tabContainer

	-- 본문 영역 (투명 컨테이너)
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(1, -32, 1, -120),
		pos = UDim2.new(0, 16, 0, 110),
		bgT = 1,
		clips = true,
		parent = window,
	})
	PortalUI.Refs.Body = body

	-- 탭 전환 이벤트
	PortalUI.Refs.BtnRepairTab.MouseButton1Click:Connect(function()
		currentTab = "REPAIR"
		PortalUI.Refresh()
	end)
	PortalUI.Refs.BtnUseTab.MouseButton1Click:Connect(function()
		currentTab = "USE"
		PortalUI.Refresh()
	end)
end

----------------------------------------------------------------
-- Visibility
----------------------------------------------------------------
function PortalUI.SetVisible(visible)
	if PortalUI.Refs.Frame then
		PortalUI.Refs.Frame.Visible = visible
	end
end

----------------------------------------------------------------
-- SetData
----------------------------------------------------------------
function PortalUI.SetData(data)
	statusData = data or { repaired = false, cost = {} }
	if statusData.repaired then
		currentTab = "USE"
	else
		currentTab = "REPAIR"
	end
end

----------------------------------------------------------------
-- Refresh
----------------------------------------------------------------
function PortalUI.Refresh(newData)
	if newData then
		statusData = newData
	end
	if not statusData then
		return
	end

	local repaired = statusData.repaired == true

	-- 탭 상태 갱신 (ShopUI 패턴: BackgroundColor3 토글)
	local btnRepair = PortalUI.Refs.BtnRepairTab
	local btnUse = PortalUI.Refs.BtnUseTab
	if btnRepair then
		btnRepair.BackgroundColor3 = (currentTab == "REPAIR") and C.BTN_H or C.BTN
	end
	if btnUse then
		btnUse.Visible = repaired
		btnUse.BackgroundColor3 = (currentTab == "USE") and C.BTN_H or C.BTN
	end

	-- 본문 렌더링
	local body = PortalUI.Refs.Body
	if not body then
		return
	end
	for _, ch in ipairs(body:GetChildren()) do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end

	if currentTab == "USE" and repaired then
		renderUseTab(body)
	else
		renderRepairTab(body)
	end
end

----------------------------------------------------------------
-- Tab: USE
----------------------------------------------------------------
renderUseTab = function(body)
	Utils.mkLabel({
		text = "포탈이 활성화되었습니다.\n다음 스페이스로 이동할 수 있습니다.",
		size = UDim2.new(1, 0, 0, 60),
		pos = UDim2.new(0, 0, 0, 8),
		ax = Enum.TextXAlignment.Left,
		ay = Enum.TextYAlignment.Top,
		wrap = true,
		ts = 16,
		color = C.INK,
		parent = body,
	})

	Utils.mkBtn({
		text = "다음 스페이스 이동",
		size = UDim2.new(1, -4, 0, 44),
		pos = UDim2.new(0, 2, 1, -56),
		bg = C.GOLD,
		color = C.BG_DARK,
		font = F.TITLE,
		ts = 17,
		fn = function()
			currentUIManager.requestPortalTeleport()
		end,
		parent = body,
	})
end

----------------------------------------------------------------
-- Tab: REPAIR
----------------------------------------------------------------
renderRepairTab = function(body)
	local costList = statusData.cost or {}

	Utils.mkLabel({
		text = "수리 재료를 넣어 포탈을 활성화하세요.",
		size = UDim2.new(1, 0, 0, 26),
		pos = UDim2.new(0, 0, 0, 4),
		ax = Enum.TextXAlignment.Left,
		ts = 16,
		color = C.INK,
		parent = body,
	})

	local rowY = 36
	for _, item in ipairs(costList) do
		local row = Utils.mkFrame({
			name = "CostRow_" .. tostring(item.itemId),
			size = UDim2.new(1, -4, 0, 44),
			pos = UDim2.new(0, 2, 0, rowY),
			bg = C.BG_DARK,
			bgT = 0.25,
			r = 6,
			stroke = 1,
			strokeC = item.met and C.GREEN or C.BORDER_DIM,
			parent = body,
		})

		local infoText = string.format("%s  %d / %d", item.name or item.itemId, item.current or 0, item.required or 0)
		Utils.mkLabel({
			text = infoText,
			size = UDim2.new(0.62, 0, 1, 0),
			pos = UDim2.new(0, 12, 0, 0),
			ax = Enum.TextXAlignment.Left,
			ts = 16,
			color = item.met and C.GREEN or C.INK,
			parent = row,
		})

		if item.met then
			Utils.mkLabel({
				text = "완료",
				size = UDim2.new(0, 78, 0, 30),
				pos = UDim2.new(1, -86, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				font = F.TITLE,
				ts = 16,
				color = C.GREEN,
				parent = row,
			})
		else
			Utils.mkBtn({
				text = "넣기",
				size = UDim2.new(0, 78, 0, 30),
				pos = UDim2.new(1, -86, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				bg = C.BG_SLOT,
				font = F.TITLE,
				ts = 16,
				fn = function()
					currentUIManager.requestPortalDeposit(item.itemId, item.remaining)
				end,
				parent = row,
			})
		end

		rowY += 50
	end
end

return PortalUI
