-- DropRateUI.lua
-- 척척박사(citizen_01) NPC가 보여주는 몬스터별 아이템 드롭률 표

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")

local Theme       = require(script.Parent:WaitForChild("UITheme"))
local Utils       = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))

-- Navy + Black Theme Override (Convention match with InventoryUI/DismantleUI/EnhanceUI)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL   = Color3.fromRGB(10, 15, 25) -- Deep Navy
C.BG_DARK    = Color3.fromRGB(5, 5, 10)   -- Pure Black
C.BG_SLOT    = Color3.fromRGB(12, 12, 15) -- Near Black
C.BORDER     = Color3.fromRGB(60, 85, 130) -- Soft Light Blue
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.GOLD_SEL   = Color3.fromRGB(40, 80, 160)

local F = Theme.Fonts

local player = Players.LocalPlayer

local DropRateUI = {}

local function closeUI()
	local playerGui = player:WaitForChild("PlayerGui")
	local sg = playerGui:FindFirstChild("DropRateSG")
	if sg then sg:Destroy() end
end

function DropRateUI.Open(rows)
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local ROW_H          = isMobile and 36 or 30
	local GROUP_HEADER_H = isMobile and 32 or 26
	local TS_TITLE        = isMobile and 18 or 20
	local TS_HEADER        = isMobile and 12 or 13
	local TS_GROUP          = isMobile and 15 or 14
	local TS_ROW             = isMobile and 14 or 13

	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DropRateSG")
	if existing then existing:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name           = "DropRateSG"
	sg.ResetOnSpawn   = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder   = 210
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	-- Background Dim (다른 팝업들과 동일한 오버레이 방식)
	local dimFrame = Utils.mkFrame({
		name = "DropRateMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		parent = sg,
	})
	local dimBtn = Instance.new("TextButton")
	dimBtn.Size                   = UDim2.new(1, 0, 1, 0)
	dimBtn.BackgroundTransparency = 1
	dimBtn.Text                   = ""
	dimBtn.AutoButtonColor        = false
	dimBtn.Parent                 = dimFrame
	dimBtn.MouseButton1Click:Connect(closeUI)

	-- 메인 윈도우 (Navy + Black Glassmorphism, 다른 팝업들과 동일하게 화면 비율 기반 반응형 크기 사용)
	local win = Utils.mkWindow({
		name = "DropRateWindow",
		size = isMobile and UDim2.new(0.94, 0, 0.82, 0) or UDim2.new(0.42, 0, 0.72, 0),
		maxSize = Vector2.new(600, 560),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.15,
		stroke = 2,
		strokeC = C.BORDER,
		r = 12,
		parent = dimFrame,
	})

	local closeBtnSize = isMobile and 36 or 32

	Utils.mkLabel({
		text = UILocalizer.Localize("아이템 드롭률 (Drop Rate)"),
		size = UDim2.new(1, -60, 0, 40),
		pos = UDim2.new(0, 20, 0, 10),
		font = F.TITLE,
		ts = TS_TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = win,
	})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, closeBtnSize, 0, closeBtnSize),
		pos = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = 16,
		font = F.TITLE,
		r = 6,
		fn = closeUI,
		parent = win,
	})

	-- Body (분해소/인벤토리와 동일한 서브 패널 스타일)
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(1, -40, 1, -70),
		pos = UDim2.new(0, 20, 0, 60),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = win,
	})

	-- 헤더 (몬스터 / 아이템 / 확률)
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, -24, 0, 30),
		pos = UDim2.new(0, 12, 0, 10),
		bgT = 1,
		parent = body,
	})

	local function mkHeaderCell(text, x, w, align)
		Utils.mkLabel({
			text = text,
			size = UDim2.new(w, 0, 1, 0),
			pos = UDim2.new(x, 0, 0, 0),
			font = F.TITLE,
			ts = TS_HEADER,
			color = C.GRAY,
			ax = align or Enum.TextXAlignment.Left,
			parent = header,
		})
	end

	-- 몬스터 이름은 아래 목록에서 진한 배경의 그룹 헤더 행으로 별도 표시되므로,
	-- 상단 열 제목은 그 아래 아이템 행의 두 컬럼(아이템/확률)에 맞춘다.
	mkHeaderCell(UILocalizer.Localize("아이템"), 0.04, 0.72, Enum.TextXAlignment.Left)
	mkHeaderCell(UILocalizer.Localize("확률"), 0.76, 0.24, Enum.TextXAlignment.Right)

	local headerDivider = Utils.mkFrame({
		name = "HeaderDivider",
		size = UDim2.new(1, -24, 0, 2),
		pos = UDim2.new(0, 12, 0, 42),
		bg = C.BORDER,
		bgT = 0.2,
		r = false,
		parent = body,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                   = "Scroll"
	scroll.Size                   = UDim2.new(1, -24, 1, -56)
	scroll.Position               = UDim2.new(0, 12, 0, 50)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness      = 5
	scroll.ScrollBarImageColor3    = C.BORDER
	scroll.CanvasSize              = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize     = Enum.AutomaticSize.Y
	scroll.Parent                  = body

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding   = UDim.new(0, 1)
	list.Parent    = scroll

	for i, row in ipairs(rows or {}) do
		-- 몬스터 그룹의 시작: 진한 배경의 전용 헤더 행으로 몬스터 이름만 표시
		if row.groupFirst then
			local groupHeader = Utils.mkFrame({
				name = "GroupHeader" .. i,
				size = UDim2.new(1, 0, 0, GROUP_HEADER_H),
				bg = C.BG_SLOT,
				bgT = 0.1,
				r = false,
				parent = scroll,
			})
			local hStroke = Instance.new("UIStroke")
			hStroke.Thickness = 1
			hStroke.Color = C.BORDER
			hStroke.Transparency = 0.4
			hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			hStroke.Parent = groupHeader

			Utils.mkLabel({
				text = row.monster or "",
				size = UDim2.new(1, -12, 1, 0),
				pos = UDim2.new(0, 8, 0, 0),
				font = F.TITLE,
				ts = TS_GROUP,
				color = Color3.fromRGB(150, 190, 255),
				ax = Enum.TextXAlignment.Left,
				parent = groupHeader,
			})
		end

		-- 아이템 행: 모든 행이 동일한 연한 배경을 사용해 헤더 행과 명확히 구분되도록 통일
		local rowFrame = Utils.mkFrame({
			name = "Row" .. i,
			size = UDim2.new(1, 0, 0, ROW_H),
			bg = C.BG_DARK,
			bgT = 0.55,
			r = false,
			parent = scroll,
		})

		Utils.mkLabel({
			text = row.item or "",
			size = UDim2.new(0.72, -4, 1, 0),
			pos = UDim2.new(0.04, 0, 0, 0),
			font = F.NORMAL,
			ts = TS_ROW,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Left,
			parent = rowFrame,
		})

		Utils.mkLabel({
			text = string.format("%.1f%%", row.chance or 0),
			size = UDim2.new(0.24, -8, 1, 0),
			pos = UDim2.new(0.76, 0, 0, 0),
			font = F.NUM,
			ts = TS_ROW,
			color = (row.chance or 0) >= 100 and C.GREEN or C.INK,
			ax = Enum.TextXAlignment.Right,
			parent = rowFrame,
		})
	end
end

return DropRateUI
