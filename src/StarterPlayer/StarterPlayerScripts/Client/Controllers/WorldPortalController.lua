-- WorldPortalController.lua
-- 월드 포탈 이동 UI (CraftingUI 동일 컨벤션)

local WorldPortalController = {}

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client       = script.Parent.Parent
local UI           = Client:WaitForChild("UI")
local Theme        = require(UI:WaitForChild("UITheme"))
local Utils        = require(UI:WaitForChild("UIUtils"))
local NetClient    = require(Client:WaitForChild("NetClient"))
local UIManager    = require(Client:WaitForChild("UIManager"))
local TeleportFade = require(Client:WaitForChild("Utils"):WaitForChild("TeleportFade"))

local player   = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled
local initialized = false

-- CraftingUI / InventoryUI 와 완전히 동일한 컬러 오버라이드
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL   = Color3.fromRGB(10,  15,  25)
C.BG_DARK    = Color3.fromRGB(5,   5,   10)
C.BG_SLOT    = Color3.fromRGB(12,  12,  15)
C.GOLD       = Color3.fromRGB(255, 255, 255)
C.GOLD_SEL   = Color3.fromRGB(40,  80,  160)
C.BORDER     = Color3.fromRGB(60,  85,  130)
C.BORDER_DIM = Color3.fromRGB(30,  45,  70)
C.BTN        = Color3.fromRGB(40,  80,  160)
C.BTN_H      = Color3.fromRGB(60,  100, 180)

local F = Theme.Fonts
local T = Theme.Transp

local PORTAL_DEFS = {
	{ id = "Grasslands",   name = "초원"        },
	{ id = "Forest",       name = "숲"          },
	{ id = "Kingdom",      name = "왕국"        },
	{ id = "Cave",         name = "동굴"        },
	{ id = "BatTerritory", name = "박쥐 서식지" },
	{ id = "Snowy",        name = "설원"        },
	{ id = "Lava",         name = "용암지대"    },
	{ id = "Sky",          name = "하늘섬"      },
}

--========================================
-- 포탈 선택 UI
--========================================
local function showPortalSelectUI(registered)
	local playerGui = player:WaitForChild("PlayerGui")

	if playerGui:FindFirstChild("WorldPortalSG") then
		playerGui.WorldPortalSG:Destroy()
		return
	end

	-- 별도 ScreenGui — HUD(기본 ~10) 위에 표시
	local sg = Instance.new("ScreenGui")
	sg.Name           = "WorldPortalSG"
	sg.ResetOnSpawn   = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder   = 300
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	-- [버그수정] AutomaticSize.Y로 콘텐츠 양만큼 무한정 늘어나던 창이 모바일 화면 높이를
	-- 넘어가면서 위/아래가 잘리고 X 버튼까지 가려지던 문제. 모바일에서는 화면 비율 기반
	-- 고정 높이로 전환하고, 내부 스크롤 영역이 남은 공간을 채우도록 해서 항상 화면 안에 들어오게 한다.
	-- 데스크톱=절대 440px 폭 + 콘텐츠에 맞춰 자동 높이, 모바일=화면 비율 기반 고정 크기
	local main = Utils.mkWindow({
		name    = "Main",
		size    = isMobile and UDim2.new(0.95, 0, 0.82, 0) or UDim2.new(0, 440, 0, 0),
		maxSize = Vector2.new(440, 620),
		pos     = UDim2.new(0.5, 0, 0.5, 0),
		anchor  = Vector2.new(0.5, 0.5),
		bg      = C.BG_PANEL,
		bgT     = T.PANEL,
		r       = 6,
		stroke  = 1.5,
		strokeC = C.BORDER,
		parent  = sg,
	})
	if not isMobile then
		main.AutomaticSize = Enum.AutomaticSize.Y
	end

	-- ── 헤더 (CraftingUI: bgT=1, 높이 50) ──
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, 0, 0, 50),
		bgT  = 1,
		parent = main,
	})

	Utils.mkLabel({
		text   = "포탈 이동",
		size   = UDim2.new(1, -60, 1, 0),
		pos    = UDim2.new(0, 15, 0, 0),
		ts     = 26,
		font   = F.TITLE,
		color  = C.GOLD,
		ax     = Enum.TextXAlignment.Left,
		parent = header,
	})

	Utils.mkBtn({
		text       = "X",
		size       = UDim2.new(0, 42, 0, 42),
		pos        = UDim2.new(1, -10, 0.5, 0),
		anchor     = Vector2.new(1, 0.5),
		isNegative = true,
		bgT        = 0.5,
		ts         = 24,
		color      = C.GOLD,
		r          = 4,
		fn         = function() sg:Destroy() end,
		parent     = header,
	})

	-- ── 콘텐츠 영역 (CraftingUI: pos y=55, size h=-65) ──
	-- 모바일에서는 main이 이미 화면 비율로 고정 높이라, 콘텐츠 영역도 남은 공간을 그대로
	-- 채우게 해서(1,-65) 스크롤이 그 안에서 알아서 넘치는 부분을 처리하도록 한다.
	local canvasWrapper = Utils.mkFrame({
		name   = "CanvasWrap",
		size   = isMobile and UDim2.new(1, -20, 1, -65) or UDim2.new(1, -20, 0, 0),
		pos    = UDim2.new(0, 10, 0, 55),
		bgT    = 1,
		parent = main,
	})
	if not isMobile then
		canvasWrapper.AutomaticSize = Enum.AutomaticSize.Y
	end

	-- 스크롤 (CraftingUI 동일 방식)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                 = "PortalScroll"
	scroll.Size                 = isMobile and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0, math.min(#PORTAL_DEFS * 82 + 16, 420))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel      = 0
	scroll.ScrollBarThickness   = 4
	scroll.ScrollBarImageColor3 = C.GOLD_SEL
	scroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
	scroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
	scroll.Parent               = canvasWrapper

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding    = UDim.new(0, 8)
	listLayout.SortOrder  = Enum.SortOrder.LayoutOrder
	listLayout.Parent     = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop   = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft  = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent       = scroll

	-- ── 슬롯 행 (CraftingUI: border frame → inner frame) ──
	for i, def in ipairs(PORTAL_DEFS) do
		local isReg = registered[def.id] == true

		-- 외곽 테두리 (CraftingUI와 동일)
		local borderFrame = Instance.new("Frame")
		borderFrame.Name                 = def.id
		borderFrame.Size                 = UDim2.new(1, -20, 0, 72)
		borderFrame.BackgroundColor3     = isReg and C.GOLD_SEL or C.BORDER
		borderFrame.BackgroundTransparency = isReg and 0.6 or 0.85
		borderFrame.BorderSizePixel      = 0
		borderFrame.LayoutOrder          = i
		borderFrame.Parent               = scroll
		Instance.new("UICorner", borderFrame).CornerRadius = UDim.new(0, 6)

		-- 내부 프레임
		local inner = Instance.new("Frame")
		inner.Size                 = UDim2.new(1, -2, 1, -2)
		inner.Position             = UDim2.new(0.5, 0, 0.5, 0)
		inner.AnchorPoint          = Vector2.new(0.5, 0.5)
		inner.BackgroundColor3     = C.BG_SLOT
		inner.BackgroundTransparency = 0
		inner.BorderSizePixel      = 0
		inner.ZIndex               = 2
		inner.Parent               = borderFrame
		Instance.new("UICorner", inner).CornerRadius = UDim.new(0, 5)

		-- 등록됨 표시: 좌측 세로 바
		if isReg then
			local bar = Instance.new("Frame")
			bar.Size             = UDim2.new(0, 3, 0.55, 0)
			bar.Position         = UDim2.new(0, 0, 0.225, 0)
			bar.BackgroundColor3 = C.GOLD_SEL
			bar.BorderSizePixel  = 0
			bar.ZIndex           = 3
			bar.Parent           = inner
			Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
		end

		-- 지역명
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size                   = UDim2.new(1, -120, 0, 32)
		nameLabel.Position               = UDim2.new(0, 14, 0, 9)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text                   = def.name
		nameLabel.Font                   = F.TITLE
		nameLabel.TextSize               = isMobile and 18 or 17
		nameLabel.TextColor3             = isReg and C.GOLD or C.GRAY
		nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
		nameLabel.ZIndex                 = 3
		nameLabel.Parent                 = inner

		-- 상태 레이블
		local stLabel = Instance.new("TextLabel")
		stLabel.Size                   = UDim2.new(1, -120, 0, 22)
		stLabel.Position               = UDim2.new(0, 14, 0, 40)
		stLabel.BackgroundTransparency = 1
		stLabel.Text                   = isReg and "등록됨  ·  이동 가능" or "미등록  ·  현지 포탈에서 E키로 등록"
		stLabel.Font                   = F.NORMAL
		stLabel.TextSize               = isMobile and 13 or 12
		stLabel.TextColor3             = isReg and Color3.fromRGB(90, 200, 110) or C.DIM
		stLabel.TextXAlignment         = Enum.TextXAlignment.Left
		stLabel.ZIndex                 = 3
		stLabel.Parent                 = inner

		-- 이동 버튼 (등록된 경우만)
		if isReg then
			local capturedId = def.id
			Utils.mkBtn({
				text   = "이동",
				size   = UDim2.new(0, isMobile and 76 or 68, 0, 40),
				pos    = UDim2.new(1, -(isMobile and 84 or 78), 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				bg     = C.BTN,
				hbg    = C.BTN_H,
				bgT    = 0,
				ts     = isMobile and 16 or 15,
				font   = F.TITLE,
				color  = C.GOLD,
				r      = 5,
				z      = 4,
				fn     = function()
					sg:Destroy()
					task.spawn(function()
						local ret = TeleportFade.execute(function()
							local ok, result = NetClient.Request("WorldPortal.Teleport.Request", { portalId = capturedId })
							return { ok = ok, result = result }
						end)
						if not ret or not ret.ok or (ret.result and not ret.result.success) then
							UIManager.notify("이동에 실패했습니다.", C.RED)
						end
					end)
				end,
				parent = inner,
			})
		end
	end

	-- 하단 여백
	local bottomPad = Instance.new("Frame")
	bottomPad.Size                 = UDim2.new(1, 0, 0, 10)
	bottomPad.BackgroundTransparency = 1
	bottomPad.Parent               = canvasWrapper
end

--========================================
-- Init
--========================================
function WorldPortalController.Init()
	if initialized then return end
	initialized = true

	NetClient.On("WorldPortal.OpenUI", function(data)
		local registered = (data and data.registered) or {}
		showPortalSelectUI(registered)
	end)

	NetClient.On("WorldPortal.Registered", function(data)
		if data and data.name then
			UIManager.notify(data.name .. " 포탈이 등록되었습니다!", Color3.fromRGB(90, 210, 110))
		end
	end)

	print("[WorldPortalController] Initialized")
end

return WorldPortalController
