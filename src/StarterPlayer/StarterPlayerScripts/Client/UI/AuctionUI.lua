-- AuctionUI.lua
-- 클라이언트 통합 경매장 UI 모듈
-- Navy + Black Glassmorphic 테마 적용 및 완벽한 반응형 레이아웃 보장

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"):WaitForChild("Enums"))

local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
C.BG_SLOT = Color3.fromRGB(12, 12, 15) -- Near Black
C.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White
C.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN = Color3.fromRGB(40, 80, 160)      -- Action Buttons
C.BTN_H = Color3.fromRGB(60, 100, 180)   -- Action Buttons Hover

local F = Theme.Fonts
local T = Theme.Transp

local AuctionUI = {}
AuctionUI.Refs = {}

local currentUIManager = nil
local AuctionController = nil
local activeTab = "BUY" -- "BUY", "SELL", "MANAGE"
local selectedInventorySlot = nil
local currentPage = 1
local itemsPerPage = 6
local totalListings = {}
local activeRefreshId = 0

-- UI 테마 색상 재정의 (Navy + Black Glass)
local NAVY_BLACK_BG = C.BG_PANEL
local NAVY_HIGHLIGHT = C.BORDER
local GOLD_COLOR = C.GOLD_SEL

-- 구매 확인 팝업 상태
local activeConfirmPopup = nil


function AuctionUI.FormatNumber(val: number): string
	local formatted = tostring(val)
	while true do  
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then
			break
		end
	end
	return formatted
end

function AuctionUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager
	AuctionController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("AuctionController"))
	
	-- 메인 오버레이 프레임
	local frame = Utils.mkFrame({
		name = "AuctionMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent,
	})
	AuctionUI.Refs.Frame = frame
	
	-- 메인 윈도우 (Navy + Black Glassmorphism)
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isMobile and 1 or 0.85, 0, isMobile and 1 or 0.85, 0),
		maxSize = Vector2.new(1050, 750),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = NAVY_BLACK_BG,
		bgT = 0.25, -- 반투명 유리 효과
		stroke = 2,
		strokeC = NAVY_HIGHLIGHT,
		r = 10,
		parent = frame,
	})
	AuctionUI.Refs.MainWindow = main
	
	-- 헤더 영역
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, 0, 0, 55),
		bg = Color3.fromRGB(8, 8, 15),
		bgT = 0.4,
		parent = main,
	})
	
	Utils.mkLabel({
		text = "통합 경매장",
		pos = UDim2.new(0, 20, 0, 0),
		size = UDim2.new(0.3, 0, 1, 0),
		ts = 22,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})
	
	-- 닫기 버튼
	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 36, 0, 36),
		pos = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = C.BTN_GRAY,
		hbg = C.BTN_GRAY_H,
		bgT = 0.5,
		ts = 18,
		font = F.TITLE,
		color = C.WHITE,
		isNegative = true,
		r = 6,
		fn = function() UIManager.closeAuctionHouse() end,
		parent = header,
	})
	
	-- 탭 네비게이션바
	local tabContainer = Utils.mkFrame({
		name = "TabContainer",
		size = UDim2.new(0.5, 0, 1, 0),
		pos = UDim2.new(0.3, 0, 0, 0),
		bgT = 1,
		parent = header,
	})
	
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.Parent = tabContainer
	
	local tabs = {
		{ id = "BUY", name = "구매" },
		{ id = "SELL", name = "판매 등록" },
		{ id = "MANAGE", name = "정산 및 관리" }
	}
	
	AuctionUI.Refs.TabButtons = {}
	
	for _, tabInfo in ipairs(tabs) do
		local btn = Utils.mkBtn({
			text = tabInfo.name,
			size = UDim2.new(0, isMobile and 85 or 110, 0, 36),
			bg = C.BTN_GRAY,
			hbg = C.BTN_GRAY_H,
			bgT = 0.5,
			ts = isMobile and 13 or 15,
			font = F.TITLE,
			color = C.GRAY,
			isNegative = true,
			r = 6,
			parent = tabContainer
		})
		
		AuctionUI.Refs.TabButtons[tabInfo.id] = btn
		
		btn.MouseButton1Click:Connect(function()
			AuctionUI.SwitchTab(tabInfo.id)
		end)
	end
	
	-- 메인 콘텐츠 영역
	local contentBox = Utils.mkFrame({
		name = "ContentBox",
		size = UDim2.new(1, -30, 1, -80),
		pos = UDim2.new(0, 15, 0, 65),
		bgT = 1,
		parent = main
	})
	
	--==============================================================
	-- 1. 구매(BUY) 탭 프레임
	--==============================================================
	local buyFrame = Utils.mkFrame({
		name = "BuyFrame",
		bgT = 1,
		vis = true,
		parent = contentBox
	})
	AuctionUI.Refs.BuyFrame = buyFrame
	
	-- 상단 검색/필터 바
	local searchBar = Utils.mkFrame({
		name = "SearchBar",
		size = UDim2.new(1, 0, 0, 45),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.4,
		r = 6,
		parent = buyFrame
	})
	
	-- 검색창 배경
	local searchInputBg = Utils.mkFrame({
		name = "SearchInputBg",
		size = UDim2.new(0.6, -10, 0, 35),
		pos = UDim2.new(0, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_SLOT,
		bgT = 0.5,
		r = 6,
		parent = searchBar
	})
	
	local searchInput = Instance.new("TextBox")
	searchInput.Size = UDim2.new(1, -20, 1, 0)
	searchInput.Position = UDim2.new(0, 10, 0, 0)
	searchInput.BackgroundTransparency = 1
	searchInput.Text = ""
	searchInput.PlaceholderText = "아이템 이름 검색..."
	searchInput.TextColor3 = C.WHITE
	searchInput.PlaceholderColor3 = C.GRAY
	searchInput.TextSize = 16
	searchInput.Font = F.NORMAL
	searchInput.TextXAlignment = Enum.TextXAlignment.Left
	searchInput.Parent = searchInputBg
	AuctionUI.Refs.SearchInput = searchInput
	
	-- 새로고침 버튼
	local refreshBtn = Utils.mkBtn({
		text = "새로고침",
		size = UDim2.new(0, 120, 0, 35),
		pos = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = C.BTN_GRAY,
		hbg = C.BTN_GRAY_H,
		bgT = 0.4,
		ts = 14,
		font = F.TITLE,
		color = C.WHITE,
		isNegative = true,
		r = 6,
		fn = function()
			AuctionUI.RefreshListings()
		end,
		parent = searchBar
	})
	
	-- 검색 버튼
	local searchBtn = Utils.mkBtn({
		text = "검색",
		size = UDim2.new(0, 90, 0, 35),
		pos = UDim2.new(0.6, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BTN,
		hbg = C.BTN_H,
		bgT = 0.35,
		ts = 14,
		font = F.TITLE,
		color = C.WHITE,
		r = 6,
		fn = function()
			AuctionUI.RefreshListings()
		end,
		parent = searchBar
	})
	
	searchInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			AuctionUI.RefreshListings()
		end
	end)
	
	-- 매물 리스트 스크롤 프레임
	local buyScroll = Instance.new("ScrollingFrame")
	buyScroll.Name = "BuyScroll"
	buyScroll.Size = UDim2.new(1, 0, 1, -100) -- 하단 페이징 바를 위해 높이 축소
	buyScroll.Position = UDim2.new(0, 0, 0, 55)
	buyScroll.BackgroundTransparency = 1
	buyScroll.BorderSizePixel = 0
	buyScroll.ScrollBarThickness = 6
	buyScroll.ScrollBarImageColor3 = GOLD_COLOR
	buyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	buyScroll.Parent = buyFrame
	AuctionUI.Refs.BuyScroll = buyScroll
	
	local buyListLayout = Instance.new("UIListLayout")
	buyListLayout.Padding = UDim.new(0, 8)
	buyListLayout.Parent = buyScroll
	AuctionUI.Refs.BuyListLayout = buyListLayout
	
	-- 하단 페이징 바 프레임
	local pagingBar = Utils.mkFrame({
		name = "PagingBar",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0, 0, 1, -40),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.5,
		r = 6,
		parent = buyFrame
	})
	AuctionUI.Refs.PagingBar = pagingBar

	-- 이전 페이지 버튼
	local prevPageBtn = Utils.mkBtn({
		text = "<",
		size = UDim2.new(0, 40, 0, 30),
		pos = UDim2.new(0.5, -70, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BTN_GRAY,
		hbg = C.BTN_GRAY_H,
		bgT = 0.4,
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		isNegative = true,
		r = 4,
		fn = function()
			AuctionUI.PrevPage()
		end,
		parent = pagingBar
	})
	AuctionUI.Refs.PrevPageBtn = prevPageBtn

	-- 페이지 정보 텍스트
	local pageInfoLabel = Utils.mkLabel({
		text = "1 / 1",
		size = UDim2.new(0, 80, 0, 30),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 14,
		font = F.TITLE,
		color = C.WHITE,
		parent = pagingBar
	})
	AuctionUI.Refs.PageInfoLabel = pageInfoLabel

	-- 다음 페이지 버튼
	local nextPageBtn = Utils.mkBtn({
		text = ">",
		size = UDim2.new(0, 40, 0, 30),
		pos = UDim2.new(0.5, 70, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BTN_GRAY,
		hbg = C.BTN_GRAY_H,
		bgT = 0.4,
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		isNegative = true,
		r = 4,
		fn = function()
			AuctionUI.NextPage()
		end,
		parent = pagingBar
	})
	AuctionUI.Refs.NextPageBtn = nextPageBtn
	
	--==============================================================
	-- 2. 판매 등록(SELL) 탭 프레임
	--==============================================================
	local sellFrame = Utils.mkFrame({
		name = "SellFrame",
		bgT = 1,
		vis = false,
		parent = contentBox
	})
	AuctionUI.Refs.SellFrame = sellFrame
	
	-- 좌측 내 가방 인벤토리 그리드
	local invPanel = Utils.mkFrame({
		name = "InventoryPanel",
		size = UDim2.new(0.55, -10, 1, 0),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.4,
		r = 6,
		stroke = 1,
		strokeC = NAVY_HIGHLIGHT,
		parent = sellFrame
	})
	
	Utils.mkLabel({
		text = "등록할 아이템 선택",
		size = UDim2.new(1, -20, 0, 30),
		pos = UDim2.new(0, 15, 0, 10),
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = invPanel
	})
	
	local invScroll = Instance.new("ScrollingFrame")
	invScroll.Name = "InventoryScroll"
	invScroll.Size = UDim2.new(1, -20, 1, -55)
	invScroll.Position = UDim2.new(0, 10, 0, 45)
	invScroll.BackgroundTransparency = 1
	invScroll.BorderSizePixel = 0
	invScroll.ScrollBarThickness = 6
	invScroll.ScrollBarImageColor3 = GOLD_COLOR
	invScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	invScroll.Parent = invPanel
	AuctionUI.Refs.InventoryScroll = invScroll
	
	local invGrid = Instance.new("UIGridLayout")
	invGrid.CellSize = UDim2.new(0, 64, 0, 64)
	invGrid.CellPadding = UDim2.new(0, 8, 0, 8)
	invGrid.Parent = invScroll
	
	local function updateGridCellSize()
		local absSize = invScroll.AbsoluteSize
		if absSize.X <= 0 then return end
		local availableWidth = absSize.X - 28
		local paddingSize = 6
		local targetSize = 64
		local slotsPerRow = math.max(4, math.floor((availableWidth + paddingSize) / (targetSize + paddingSize)))
		local cellSize = math.floor((availableWidth - (paddingSize * (slotsPerRow - 1))) / slotsPerRow)
		invGrid.CellSize = UDim2.new(0, cellSize, 0, cellSize)
		invGrid.CellPadding = UDim2.new(0, paddingSize, 0, paddingSize)
	end
	invScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridCellSize)
	task.defer(updateGridCellSize)
	
	-- 우측 판매 설정 패널
	local sellForm = Utils.mkFrame({
		name = "SellForm",
		size = UDim2.new(0.45, 0, 1, 0),
		pos = UDim2.new(0.55, 10, 0, 0),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.4,
		r = 6,
		stroke = 1,
		strokeC = NAVY_HIGHLIGHT,
		parent = sellFrame
	})
	AuctionUI.Refs.SellForm = sellForm
	
	-- 선택 아이템 디테일 영역
	local itemDetailSection = Utils.mkFrame({
		name = "ItemDetailSection",
		size = UDim2.new(1, -24, 0, 90),
		pos = UDim2.new(0, 12, 0, 12),
		bg = C.BG_SLOT,
		bgT = 0.5,
		r = 6,
		parent = sellForm
	})
	
	local selIcon = Instance.new("ImageLabel")
	selIcon.Size = UDim2.new(0, 64, 0, 64)
	selIcon.Position = UDim2.new(0, 12, 0.5, 0)
	selIcon.AnchorPoint = Vector2.new(0, 0.5)
	selIcon.BackgroundTransparency = 1
	selIcon.Visible = false
	selIcon.Parent = itemDetailSection
	AuctionUI.Refs.SelIcon = selIcon
	
	local selName = Utils.mkLabel({
		text = "선택된 아이템 없음",
		size = UDim2.new(1, -95, 0, 25),
		pos = UDim2.new(0, 88, 0, 18),
		ts = 18,
		font = F.TITLE,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		parent = itemDetailSection
	})
	AuctionUI.Refs.SelName = selName
	
	local selInfo = Utils.mkLabel({
		text = "보유 수량: -",
		size = UDim2.new(1, -95, 0, 20),
		pos = UDim2.new(0, 88, 0, 48),
		ts = 14,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		parent = itemDetailSection
	})
	AuctionUI.Refs.SelInfo = selInfo
	
	-- 수량 및 단가 입력 폼
	local formInputs = Utils.mkFrame({
		name = "FormInputs",
		size = UDim2.new(1, -24, 1, -120),
		pos = UDim2.new(0, 12, 0, 115),
		bgT = 1,
		parent = sellForm
	})
	
	-- 1) 등록 수량
	Utils.mkLabel({
		text = "등록 수량",
		size = UDim2.new(1, 0, 0, 20),
		ts = 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = formInputs
	})
	
	local qtyInputBg = Utils.mkFrame({
		name = "QtyInputBg",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0, 0, 0, 25),
		bg = C.BG_SLOT,
		bgT = 0.5,
		r = 6,
		parent = formInputs
	})
	
	local qtyInput = Instance.new("TextBox")
	qtyInput.Size = UDim2.new(1, -20, 1, 0)
	qtyInput.Position = UDim2.new(0, 10, 0, 0)
	qtyInput.BackgroundTransparency = 1
	qtyInput.Text = "1"
	qtyInput.TextColor3 = C.WHITE
	qtyInput.TextSize = 16
	qtyInput.Font = F.NORMAL
	qtyInput.TextXAlignment = Enum.TextXAlignment.Left
	qtyInput.Parent = qtyInputBg
	AuctionUI.Refs.QtyInput = qtyInput
	
	-- 2) 개당 판매 가격
	Utils.mkLabel({
		text = "개당 가격 (골드)",
		size = UDim2.new(1, 0, 0, 20),
		pos = UDim2.new(0, 0, 0, 80),
		ts = 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = formInputs
	})
	
	local priceInputBg = Utils.mkFrame({
		name = "PriceInputBg",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0, 0, 0, 105),
		bg = C.BG_SLOT,
		bgT = 0.5,
		r = 6,
		parent = formInputs
	})
	
	local priceInput = Instance.new("TextBox")
	priceInput.Size = UDim2.new(1, -20, 1, 0)
	priceInput.Position = UDim2.new(0, 10, 0, 0)
	priceInput.BackgroundTransparency = 1
	priceInput.Text = "100"
	priceInput.TextColor3 = C.WHITE
	priceInput.TextSize = 16
	priceInput.Font = F.NORMAL
	priceInput.TextXAlignment = Enum.TextXAlignment.Left
	priceInput.Parent = priceInputBg
	AuctionUI.Refs.PriceInput = priceInput
	
	-- 3) 총 예상 수수료 및 예상 정산 금액
	local summaryBox = Utils.mkFrame({
		name = "SummaryBox",
		size = UDim2.new(1, 0, 0, 75),
		pos = UDim2.new(0, 0, 0, 165),
		bg = Color3.fromRGB(10, 10, 18),
		bgT = 0.4,
		r = 6,
		parent = formInputs
	})
	
	local summaryLabel = Utils.mkLabel({
		text = "총 합계: 100 골드\n(수수료 5% 제외 예상 정산: 95 골드)",
		size = UDim2.new(1, -20, 1, 0),
		pos = UDim2.new(0, 10, 0, 0),
		ts = 14,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = summaryBox
	})
	AuctionUI.Refs.SummaryLabel = summaryLabel
	
	-- 동적 가격 계산 리스너
	local function updateSummary()
		local qty = tonumber(qtyInput.Text) or 0
		local price = tonumber(priceInput.Text) or 0
		local total = qty * price
		local receiveAmount = math.floor(total * 0.95)
		summaryLabel.Text = string.format("총 합계: %s 골드\n(수수료 5%% 제외 예상 정산: %s 골드)", 
			AuctionUI.FormatNumber(total), 
			AuctionUI.FormatNumber(receiveAmount)
		)
	end
	
	qtyInput:GetPropertyChangedSignal("Text"):Connect(updateSummary)
	priceInput:GetPropertyChangedSignal("Text"):Connect(updateSummary)
	
	-- 등록 버튼
	local registerBtn = Utils.mkBtn({
		text = "판매 등록",
		size = UDim2.new(1, 0, 0, 45),
		pos = UDim2.new(0, 0, 1, -55),
		bg = C.BTN,
		hbg = C.BTN_H,
		color = C.WHITE,
		ts = 16,
		font = F.TITLE,
		r = 6,
		fn = function()
			AuctionUI.SubmitSale()
		end,
		parent = formInputs
	})
	AuctionUI.Refs.RegisterBtn = registerBtn
	
	--==============================================================
	-- 3. 정산 및 관리(MANAGE) 탭 프레임
	--==============================================================
	local manageFrame = Utils.mkFrame({
		name = "ManageFrame",
		bgT = 1,
		vis = false,
		parent = contentBox
	})
	AuctionUI.Refs.ManageFrame = manageFrame
	
	-- 상단 정산 수령 패널
	local claimPanel = Utils.mkFrame({
		name = "ClaimPanel",
		size = UDim2.new(1, 0, 0, 75),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.4,
		r = 6,
		stroke = 1,
		strokeC = NAVY_HIGHLIGHT,
		parent = manageFrame
	})
	
	local claimGoldText = Utils.mkLabel({
		text = "정산 가능 대금: 0 골드",
		size = UDim2.new(0.6, 0, 1, 0),
		pos = UDim2.new(0, 20, 0, 0),
		ts = 18,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = claimPanel
	})
	AuctionUI.Refs.ClaimGoldText = claimGoldText
	
	local claimBtn = Utils.mkBtn({
		text = "정산 받기",
		size = UDim2.new(0, 140, 0, 45),
		pos = UDim2.new(1, -20, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = C.BTN,
		hbg = C.BTN_H,
		color = C.WHITE,
		ts = 16,
		font = F.TITLE,
		r = 6,
		fn = function()
			AuctionUI.ClaimPendingGold()
		end,
		parent = claimPanel
	})
	AuctionUI.Refs.ClaimBtn = claimBtn
	
	-- 하단 분할 패널: 내 매물 관리(좌) vs 판매 이력(우)
	local manageBottom = Utils.mkFrame({
		name = "ManageBottom",
		size = UDim2.new(1, 0, 1, -85),
		pos = UDim2.new(0, 0, 0, 85),
		bgT = 1,
		parent = manageFrame
	})
	
	-- 좌측 내 등록 매물
	local myListingsPanel = Utils.mkFrame({
		name = "MyListingsPanel",
		size = UDim2.new(0.5, -10, 1, 0),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.4,
		r = 6,
		stroke = 1,
		strokeC = NAVY_HIGHLIGHT,
		parent = manageBottom
	})
	
	Utils.mkLabel({
		text = "현재 판매 대기 중인 물품",
		size = UDim2.new(1, -20, 0, 30),
		pos = UDim2.new(0, 15, 0, 10),
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = myListingsPanel
	})
	
	local myScroll = Instance.new("ScrollingFrame")
	myScroll.Name = "MyScroll"
	myScroll.Size = UDim2.new(1, -20, 1, -55)
	myScroll.Position = UDim2.new(0, 10, 0, 45)
	myScroll.BackgroundTransparency = 1
	myScroll.BorderSizePixel = 0
	myScroll.ScrollBarThickness = 6
	myScroll.ScrollBarImageColor3 = GOLD_COLOR
	myScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	myScroll.Parent = myListingsPanel
	AuctionUI.Refs.MyScroll = myScroll
	
	local myListLayout = Instance.new("UIListLayout")
	myListLayout.Padding = UDim.new(0, 6)
	myListLayout.Parent = myScroll
	
	-- 우측 판매 거래 이력
	local historyPanel = Utils.mkFrame({
		name = "HistoryPanel",
		size = UDim2.new(0.5, 0, 1, 0),
		pos = UDim2.new(0.5, 10, 0, 0),
		bg = Color3.fromRGB(15, 15, 25),
		bgT = 0.4,
		r = 6,
		stroke = 1,
		strokeC = NAVY_HIGHLIGHT,
		parent = manageBottom
	})
	
	Utils.mkLabel({
		text = "최근 판매 거래 이력",
		size = UDim2.new(1, -20, 0, 30),
		pos = UDim2.new(0, 15, 0, 10),
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = historyPanel
	})
	
	local historyScroll = Instance.new("ScrollingFrame")
	historyScroll.Name = "HistoryScroll"
	historyScroll.Size = UDim2.new(1, -20, 1, -55)
	historyScroll.Position = UDim2.new(0, 10, 0, 45)
	historyScroll.BackgroundTransparency = 1
	historyScroll.BorderSizePixel = 0
	historyScroll.ScrollBarThickness = 6
	historyScroll.ScrollBarImageColor3 = GOLD_COLOR
	historyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	historyScroll.Parent = historyPanel
	AuctionUI.Refs.HistoryScroll = historyScroll
	
	local historyListLayout = Instance.new("UIListLayout")
	historyListLayout.Padding = UDim.new(0, 6)
	historyListLayout.Parent = historyScroll
	
	-- 인벤토리 리스너 연결
	local InventoryController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("InventoryController"))
	InventoryController.onChanged(function()
		if AuctionUI.Refs.Frame and AuctionUI.Refs.Frame.Visible then
			AuctionUI.RefreshInventoryList()
		end
	end)
	
	local SkillController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SkillController"))
	if SkillController and SkillController.onSkillDataUpdated then
		SkillController.onSkillDataUpdated(function()
			if AuctionUI.Refs.Frame and AuctionUI.Refs.Frame.Visible then
				AuctionUI.RefreshInventoryList()
			end
		end)
	end
end

function AuctionUI.SetVisible(visible)
	if not AuctionUI.Refs.Frame then return end
	AuctionUI.Refs.Frame.Visible = visible
	
	if visible then
		AuctionUI.SwitchTab("BUY")
	else
		AuctionUI.CloseConfirmPopup()
	end
end

-- 탭 전환 로직
function AuctionUI.SwitchTab(tabId)
	activeTab = tabId
	
	-- 탭 버튼 색상 갱신
	for tid, btn in pairs(AuctionUI.Refs.TabButtons) do
		if tid == tabId then
			Utils.setBtnState(btn, C.GOLD_SEL, 0.25)
			btn.TextColor3 = C.WHITE
		else
			Utils.setBtnState(btn, C.BTN_GRAY, 0.6)
			btn.TextColor3 = C.GRAY
		end
	end
	
	-- 프레임 가시성 토글
	if AuctionUI.Refs.BuyFrame then AuctionUI.Refs.BuyFrame.Visible = (tabId == "BUY") end
	if AuctionUI.Refs.SellFrame then AuctionUI.Refs.SellFrame.Visible = (tabId == "SELL") end
	if AuctionUI.Refs.ManageFrame then AuctionUI.Refs.ManageFrame.Visible = (tabId == "MANAGE") end
	
	-- 탭별 정보 갱신
	if tabId == "BUY" then
		AuctionUI.RefreshListings()
	elseif tabId == "SELL" then
		selectedInventorySlot = nil
		AuctionUI.UpdateSellSelection()
		AuctionUI.RefreshInventoryList()
	elseif tabId == "MANAGE" then
		AuctionUI.RefreshManageTab()
	end
end

function AuctionUI.RefreshListings()
	activeRefreshId = activeRefreshId + 1
	local currentRefreshId = activeRefreshId

	-- 로딩 인디케이터나 목록 지우기
	for _, child in ipairs(AuctionUI.Refs.BuyScroll:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	
	local query = string.lower(string.gsub(AuctionUI.Refs.SearchInput.Text, "%s+", ""))
	
	task.spawn(function()
		local listings, err = AuctionController.getListings()
		if not listings then
			return
		end
		
		-- 비동기 작업 도중 새로운 새로고침 요청이 발생했다면 이전 요청은 취소
		if currentRefreshId ~= activeRefreshId then
			return
		end

		local filtered = {}
		for _, entry in ipairs(listings) do
			local matched = true
			
			if query ~= "" then
				local itemData = DataHelper.GetData("ItemData", entry.itemId)
				local rawName = itemData and itemData.name or entry.itemId
				
				-- 한글 이름과 영어 로컬라이징 이름을 모두 추출하여 비교 (Locale 환경 영향 없이 둘 다 조회 가능)
				local koName, enName = UILocalizer.GetBothNames("ItemData", entry.itemId, rawName)
				local nameKo = string.lower(string.gsub(koName, "%s+", ""))
				local nameEn = string.lower(string.gsub(enName, "%s+", ""))
				local translateKo = string.lower(string.gsub(UILocalizer.Localize(rawName), "%s+", ""))
				local translateEn = string.lower(string.gsub(rawName, "%s+", ""))
				
				local lowerItemId = string.lower(entry.itemId)
				
				if not string.find(nameKo, query, 1, true) and 
				   not string.find(nameEn, query, 1, true) and 
				   not string.find(translateKo, query, 1, true) and
				   not string.find(translateEn, query, 1, true) and
				   not string.find(lowerItemId, query, 1, true) then
					matched = false
				end
			end
			
			if matched then
				table.insert(filtered, entry)
			end
		end
		
		-- 시간순 역순 정렬
		table.sort(filtered, function(a, b)
			return (a.timestamp or 0) > (b.timestamp or 0)
		end)
		
		-- UI 렌더링 시작하기 전 다시 한 번 ID 검사
		if currentRefreshId ~= activeRefreshId then
			return
		end

		totalListings = filtered
		currentPage = 1
		
		AuctionUI.DrawPageListings()
	end)
end

function AuctionUI.DrawPageListings()
	-- 이전 매물 렌더링 삭제
	for _, child in ipairs(AuctionUI.Refs.BuyScroll:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local totalItems = #totalListings
	local totalPages = math.max(1, math.ceil(totalItems / itemsPerPage))
	
	-- 현재 페이지 범위 검사 및 보정
	if currentPage > totalPages then
		currentPage = totalPages
	end
	if currentPage < 1 then
		currentPage = 1
	end

	-- 페이지 표시 라벨 업데이트
	if AuctionUI.Refs.PageInfoLabel then
		AuctionUI.Refs.PageInfoLabel.Text = string.format("%d / %d", currentPage, totalPages)
	end

	-- 이전/다음 버튼 활성/비활성 처리
	if AuctionUI.Refs.PrevPageBtn then
		local prevActive = currentPage > 1
		AuctionUI.Refs.PrevPageBtn.Active = prevActive
		AuctionUI.Refs.PrevPageBtn.AutoButtonColor = prevActive
		AuctionUI.Refs.PrevPageBtn.BackgroundColor3 = prevActive and C.BTN_GRAY or Color3.fromRGB(30, 30, 35)
		AuctionUI.Refs.PrevPageBtn.TextColor3 = prevActive and C.WHITE or C.GRAY
	end
	if AuctionUI.Refs.NextPageBtn then
		local nextActive = currentPage < totalPages
		AuctionUI.Refs.NextPageBtn.Active = nextActive
		AuctionUI.Refs.NextPageBtn.AutoButtonColor = nextActive
		AuctionUI.Refs.NextPageBtn.BackgroundColor3 = nextActive and C.BTN_GRAY or Color3.fromRGB(30, 30, 35)
		AuctionUI.Refs.NextPageBtn.TextColor3 = nextActive and C.WHITE or C.GRAY
	end

	-- 현재 페이지에 해당하는 매물만 슬라이싱하여 렌더링
	local startIndex = (currentPage - 1) * itemsPerPage + 1
	local endIndex = math.min(currentPage * itemsPerPage, totalItems)

	for i = startIndex, endIndex do
		local entry = totalListings[i]
		if not entry then break end

		local itemData = DataHelper.GetData("ItemData", entry.itemId)
		local rawName = itemData and itemData.name or entry.itemId
		local name = UILocalizer.LocalizeDataText("ItemData", entry.itemId, "name", rawName)
		local rarity = itemData and itemData.rarity or "COMMON"
		local rarityColor = C[rarity] or C.COMMON
		
		local itemFrame = Utils.mkFrame({
			name = "ListingItem_" .. entry.listingId,
			size = UDim2.new(1, -12, 0, 70),
			bg = C.BG_SLOT,
			bgT = 0.3,
			r = 6,
			stroke = 1,
			strokeC = C.BORDER_DIM,
			parent = AuctionUI.Refs.BuyScroll
		})
		
		-- 아이콘
		local icon = Instance.new("ImageButton")
		icon.Size = UDim2.new(0, 54, 0, 54)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = currentUIManager.getItemIcon(entry.itemId)
		icon.Parent = itemFrame
		
		-- 아이템 이름 & 등급 표기
		local nameLabel = Utils.mkLabel({
			text = name,
			size = UDim2.new(0.3, 0, 0, 25),
			pos = UDim2.new(0, 72, 0, 10),
			ts = 16,
			font = F.TITLE,
			color = rarityColor,
			ax = Enum.TextXAlignment.Left,
			parent = itemFrame
		})
		
		-- 이름 텍스트 라벨을 버튼 형태로 터치 가능하게 만들기 위한 Invisible TextButton 추가
		local nameBtn = Instance.new("TextButton")
		nameBtn.Size = UDim2.new(1, 0, 1, 0)
		nameBtn.BackgroundTransparency = 1
		nameBtn.Text = ""
		nameBtn.Parent = nameLabel
		
		-- 아이템 디테일 보기 바인딩 (아이콘 또는 이름 클릭 시)
		local function showItemDetail()
			AuctionUI.OpenItemDetailPopup(entry, name, rarityColor)
		end
		
		icon.MouseButton1Click:Connect(showItemDetail)
		nameBtn.MouseButton1Click:Connect(showItemDetail)
		
		-- 수량 표기
		local countLabel = Utils.mkLabel({
			text = "수량: " .. tostring(entry.count) .. "개",
			size = UDim2.new(0.3, 0, 0, 20),
			pos = UDim2.new(0, 72, 0, 35),
			ts = 14,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Left,
			parent = itemFrame
		})
		
		-- 가격 정보
		local priceFrame = Utils.mkFrame({
			name = "PriceFrame",
			size = UDim2.new(0.35, 0, 1, 0),
			pos = UDim2.new(0.4, 0, 0, 0),
			bgT = 1,
			parent = itemFrame
		})
		
		Utils.mkLabel({
			text = "개당: " .. AuctionUI.FormatNumber(entry.pricePerUnit) .. " 골드",
			size = UDim2.new(1, 0, 0.5, 0),
			ts = 13,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Right,
			parent = priceFrame
		})
		
		Utils.mkLabel({
			text = "총액: " .. AuctionUI.FormatNumber(entry.pricePerUnit * entry.count) .. " 골드",
			size = UDim2.new(1, 0, 0.5, 0),
			pos = UDim2.new(0, 0, 0.5, 0),
			ts = 15,
			font = F.TITLE,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Right,
			parent = priceFrame
		})
		
		-- 구매 버튼
		local buyBtn = Utils.mkBtn({
			text = "즉시 구매",
			size = UDim2.new(0, 100, 0, 36),
			pos = UDim2.new(1, -10, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			bg = C.BTN,
			hbg = C.BTN_H,
			color = C.WHITE,
			ts = 14,
			font = F.TITLE,
			r = 6,
			fn = function()
				AuctionUI.OpenConfirmBuyPopup(entry, name, rarityColor)
			end,
			parent = itemFrame
		})
		
		-- 본인 매물이더라도 구매가 가능하도록 제한 없음
	end
	
	AuctionUI.Refs.BuyScroll.CanvasSize = UDim2.new(0, 0, 0, AuctionUI.Refs.BuyListLayout.AbsoluteContentSize.Y + 20)
end

function AuctionUI.PrevPage()
	if currentPage > 1 then
		currentPage = currentPage - 1
		AuctionUI.DrawPageListings()
	end
end

function AuctionUI.NextPage()
	local totalPages = math.max(1, math.ceil(#totalListings / itemsPerPage))
	if currentPage < totalPages then
		currentPage = currentPage + 1
		AuctionUI.DrawPageListings()
	end
end

local originalDetailParent = nil
local dismissShield = nil

function AuctionUI.CloseItemDetailPopup()
	local InventoryUI = require(script.Parent:WaitForChild("InventoryUI"))
	local d = InventoryUI.Refs and InventoryUI.Refs.Detail
	
	if d and d.Frame then
		d.Frame.Visible = false
		if originalDetailParent then
			d.Frame.Parent = originalDetailParent
			d.Frame.Position = UDim2.new(1, -5, 0.5, 0)
			d.Frame.AnchorPoint = Vector2.new(1, 0.5)
			d.Frame.Size = UDim2.new(0.3, 0, 1, -10)
			originalDetailParent = nil
		end
	end
	
	if dismissShield then
		dismissShield:Destroy()
		dismissShield = nil
	end
end

function AuctionUI.OpenItemDetailPopup(entry, name, rarityColor)
	AuctionUI.CloseItemDetailPopup()
	
	local InventoryUI = require(script.Parent:WaitForChild("InventoryUI"))
	local d = InventoryUI.Refs and InventoryUI.Refs.Detail
	
	if not d or not d.Frame then
		return
	end
	
	-- 1. 원래 부모 백업
	originalDetailParent = d.Frame.Parent
	
	-- 2. 전체 화면 가림막 생성 (외부 클릭 시 닫히도록)
	dismissShield = Instance.new("TextButton")
	dismissShield.Name = "DetailDismissShield"
	dismissShield.Size = UDim2.new(1, 0, 1, 0)
	dismissShield.BackgroundTransparency = 0.6 -- 약간 어두운 오버레이 효과
	dismissShield.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dismissShield.Text = ""
	dismissShield.ZIndex = 1005
	dismissShield.Parent = AuctionUI.Refs.Frame -- 경매장 전체 프레임
	
	dismissShield.MouseButton1Click:Connect(function()
		AuctionUI.CloseItemDetailPopup()
	end)
	
	-- 3. 디테일 프레임 부모를 가림막 위로 이동하여 경매장 위에 단독 팝업처럼 띄우기
	d.Frame.Parent = dismissShield
	d.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	
	-- 팝업용 크기 설정
	local isMobile = (AuctionUI.Refs.Frame.AbsoluteSize.X < 800)
	d.Frame.Size = isMobile and UDim2.new(0, 280, 0, 420) or UDim2.new(0, 320, 0, 480)
	
	local detailData = {
		itemId = entry.itemId,
		attributes = entry.attributes or {},
		durability = entry.durability or 100,
		count = entry.count
	}
	
	InventoryUI.UpdateDetail(detailData, currentUIManager.getItemIcon, Enums, DataHelper, {}, false)
	
	-- UpdateDetail 실행 후 사용/버리기 등의 버튼 숨기기
	if d.BtnMain then d.BtnMain.Visible = false end
	if d.BtnDrop then d.BtnDrop.Visible = false end
	if d.QuickRow then d.QuickRow.Visible = false end
	
	d.Frame.Visible = true
end

-- 구매 확인 다이얼로그 (Confirm Popup)
function AuctionUI.OpenConfirmBuyPopup(entry, name, rarityColor)
	AuctionUI.CloseConfirmPopup()
	
	local popup = Utils.mkFrame({
		useCanvas = true,
		name = "ConfirmPopup",
		size = UDim2.new(0, 340, 0, 180),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = NAVY_BLACK_BG,
		bgT = 0.15,
		stroke = 2,
		strokeC = GOLD_COLOR,
		r = 8,
		z = 1000,
		parent = AuctionUI.Refs.MainWindow
	})
	activeConfirmPopup = popup
	
	Utils.mkLabel({
		text = "아이템 구매 확인",
		size = UDim2.new(1, 0, 0, 35),
		pos = UDim2.new(0, 0, 0, 10),
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		parent = popup
	})
	
	Utils.mkLabel({
		text = string.format("정말로 <font color='#%s'>%s %d개</font>를\n<b>%s 골드</b>에 구매하시겠습니까?", 
			rarityColor:ToHex(), name, entry.count, AuctionUI.FormatNumber(entry.pricePerUnit * entry.count)),
		size = UDim2.new(1, -30, 0, 60),
		pos = UDim2.new(0, 15, 0, 50),
		ts = 15,
		wrap = true,
		rich = true,
		parent = popup
	})
	
	-- 취소 버튼
	Utils.mkBtn({
		text = "취소",
		size = UDim2.new(0, 120, 0, 35),
		pos = UDim2.new(0.5, -10, 1, -20),
		anchor = Vector2.new(1, 1),
		bg = C.BTN_GRAY,
		color = C.WHITE,
		ts = 14,
		font = F.TITLE,
		r = 6,
		fn = function()
			AuctionUI.CloseConfirmPopup()
		end,
		parent = popup
	})
	
	-- 확인 버튼
	Utils.mkBtn({
		text = "확인",
		size = UDim2.new(0, 120, 0, 35),
		pos = UDim2.new(0.5, 10, 1, -20),
		anchor = Vector2.new(0, 1),
		bg = C.BTN,
		color = C.BG_DARK,
		ts = 14,
		font = F.TITLE,
		r = 6,
		fn = function()
			AuctionUI.CloseConfirmPopup()
			task.spawn(function()
				local success, err = AuctionController.buyItem(entry.listingId)
				if success then
					AuctionUI.RefreshListings()
				end
			end)
		end,
		parent = popup
	})
end

function AuctionUI.CloseConfirmPopup()
	if activeConfirmPopup then
		activeConfirmPopup:Destroy()
		activeConfirmPopup = nil
	end
end

--==============================================================
-- 판매 등록(SELL) 탭 핵심 로직
--==============================================================
function AuctionUI.RefreshInventoryList()
	for _, child in ipairs(AuctionUI.Refs.InventoryScroll:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	
	local InventoryController = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.InventoryController)
	local items = InventoryController.getItems() or {}
	
	local SkillController = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.SkillController)
	local skillBooks = SkillController and SkillController.getSkillBooks() or {}
	
	-- 1. 일반 인벤토리 아이템 렌더링
	for slot, item in pairs(items) do
		if item and item.itemId then
			local itemData = DataHelper.GetData("ItemData", item.itemId)
			local rarity = itemData and itemData.rarity or "COMMON"
			local rarityColor = C[rarity] or C.COMMON
			
			local isTradeable = true
			if DataHelper and DataHelper.IsTradeable then
				isTradeable = DataHelper.IsTradeable(item.itemId)
			end
			
			local slotFrame = Utils.mkFrame({
				name = "Slot_" .. slot,
				bg = C.BG_SLOT,
				bgT = isTradeable and 0.5 or 0.8,
				r = 6,
				stroke = 1,
				strokeC = selectedInventorySlot == slot and GOLD_COLOR or C.BORDER_DIM,
				parent = AuctionUI.Refs.InventoryScroll
			})
			
			-- 아이콘
			local icon = Instance.new("ImageButton")
			icon.Size = UDim2.new(1, -8, 1, -8)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.BackgroundTransparency = 1
			icon.Image = currentUIManager.getItemIcon(item.itemId)
			if not isTradeable then
				icon.ImageColor3 = Color3.fromRGB(100, 100, 100)
			end
			icon.Parent = slotFrame
			
			-- 수량 표기
			if item.count and item.count > 1 then
				Utils.mkLabel({
					text = tostring(item.count),
					size = UDim2.new(0, 30, 0, 15),
					pos = UDim2.new(1, -2, 1, -2),
					anchor = Vector2.new(1, 1),
					ts = 12,
					font = F.NUM,
					color = C.WHITE,
					ax = Enum.TextXAlignment.Right,
					parent = slotFrame
				})
			end
			
			icon.MouseButton1Click:Connect(function()
				if not isTradeable then
					currentUIManager.notify(UILocalizer.Localize("교환 불가 아이템은 등록할 수 없습니다."), Color3.fromRGB(255, 100, 100))
					return
				end
				selectedInventorySlot = slot
				AuctionUI.RefreshInventoryList() -- 선택 테두리 갱신을 위해 재호출
				AuctionUI.UpdateSellSelection()
			end)
		end
	end
	
	-- 2. 스킬북 아이템 렌더링
	for index, bookItemId in ipairs(skillBooks) do
		local slotKey = "BOOK_SLOT_" .. index
		local itemData = DataHelper.GetData("ItemData", bookItemId)
		local rarity = itemData and itemData.rarity or "COMMON"
		local rarityColor = C[rarity] or C.COMMON
		
		-- 스킬북은 항상 교환 가능
		local isTradeable = true
		
		local slotFrame = Utils.mkFrame({
			name = "Slot_" .. slotKey,
			bg = C.BG_SLOT,
			bgT = 0.5,
			r = 6,
			stroke = 1,
			strokeC = selectedInventorySlot == slotKey and GOLD_COLOR or C.BORDER_DIM,
			parent = AuctionUI.Refs.InventoryScroll
		})
		
		local icon = Instance.new("ImageButton")
		icon.Size = UDim2.new(1, -8, 1, -8)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = currentUIManager.getItemIcon(bookItemId)
		icon.Parent = slotFrame
		
		icon.MouseButton1Click:Connect(function()
			selectedInventorySlot = slotKey
			AuctionUI.RefreshInventoryList() -- 선택 테두리 갱신을 위해 재호출
			AuctionUI.UpdateSellSelection()
		end)
	end
	
	local itemsCount = 0
	for _ in pairs(items) do itemsCount = itemsCount + 1 end
	for _ in ipairs(skillBooks) do itemsCount = itemsCount + 1 end
	local rowCount = math.ceil(itemsCount / 5)
	AuctionUI.Refs.InventoryScroll.CanvasSize = UDim2.new(0, 0, 0, rowCount * 72 + 20)
end

function AuctionUI.UpdateSellSelection()
	if not selectedInventorySlot then
		AuctionUI.Refs.SelIcon.Visible = false
		AuctionUI.Refs.SelName.Text = "선택된 아이템 없음"
		AuctionUI.Refs.SelInfo.Text = "보유 수량: -"
		AuctionUI.Refs.QtyInput.Text = "1"
		AuctionUI.Refs.PriceInput.Text = "100"
		return
	end
	
	local item = nil
	local isSkillBookSlot = (type(selectedInventorySlot) == "string" and string.sub(selectedInventorySlot, 1, 10) == "BOOK_SLOT_")
	
	if isSkillBookSlot then
		local index = tonumber(string.sub(selectedInventorySlot, 11))
		local SkillController = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.SkillController)
		local skillBooks = SkillController and SkillController.getSkillBooks() or {}
		local bookItemId = skillBooks[index]
		if bookItemId then
			item = { itemId = bookItemId, count = 1 }
		end
	else
		local InventoryController = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.InventoryController)
		item = InventoryController.getSlot(selectedInventorySlot)
	end
	
	if not item then
		selectedInventorySlot = nil
		AuctionUI.UpdateSellSelection()
		return
	end
	
	local itemData = DataHelper.GetData("ItemData", item.itemId)
	local rarity = itemData and itemData.rarity or "COMMON"
	local rarityColor = C[rarity] or C.COMMON
	
	AuctionUI.Refs.SelIcon.Image = currentUIManager.getItemIcon(item.itemId)
	AuctionUI.Refs.SelIcon.Visible = true
	
	AuctionUI.Refs.SelName.Text = itemData and itemData.name or item.itemId
	AuctionUI.Refs.SelName.TextColor3 = rarityColor
	
	AuctionUI.Refs.SelInfo.Text = "보유 수량: " .. tostring(item.count) .. "개"
	
	AuctionUI.Refs.QtyInput.Text = tostring(item.count)
end

function AuctionUI.SubmitSale()
	if not selectedInventorySlot then
		currentUIManager.notify(UILocalizer.Localize("아이템을 먼저 선택하세요."), Color3.fromRGB(255, 100, 100))
		return
	end
	
	local item = nil
	local isSkillBookSlot = (type(selectedInventorySlot) == "string" and string.sub(selectedInventorySlot, 1, 10) == "BOOK_SLOT_")
	
	if isSkillBookSlot then
		local index = tonumber(string.sub(selectedInventorySlot, 11))
		local SkillController = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.SkillController)
		local skillBooks = SkillController and SkillController.getSkillBooks() or {}
		local bookItemId = skillBooks[index]
		if bookItemId then
			item = { itemId = bookItemId, count = 1 }
		end
	else
		local InventoryController = require(Players.LocalPlayer.PlayerScripts.Client.Controllers.InventoryController)
		item = InventoryController.getSlot(selectedInventorySlot)
	end
	
	if not item then
		selectedInventorySlot = nil
		AuctionUI.UpdateSellSelection()
		return
	end
	
	if DataHelper and DataHelper.IsTradeable and not DataHelper.IsTradeable(item.itemId) then
		currentUIManager.notify(UILocalizer.Localize("교환 불가 아이템은 등록할 수 없습니다."), Color3.fromRGB(255, 100, 100))
		return
	end
	
	local qty = tonumber(AuctionUI.Refs.QtyInput.Text)
	local price = tonumber(AuctionUI.Refs.PriceInput.Text)
	
	if not qty or qty <= 0 or not price or price <= 0 then
		currentUIManager.notify("수량과 가격은 올바른 숫자여야 합니다.", Color3.fromRGB(255, 100, 100))
		return
	end
	
	task.spawn(function()
		local success = AuctionController.registerSale(selectedInventorySlot, qty, price)
		if success then
			selectedInventorySlot = nil
			AuctionUI.UpdateSellSelection()
			AuctionUI.RefreshInventoryList()
		end
	end)
end

--==============================================================
-- 정산 및 관리(MANAGE) 탭 핵심 로직
--==============================================================
function AuctionUI.RefreshManageTab()
	-- 대금 조회 및 매물 갱신
	task.spawn(function()
		local pendingData = AuctionController.getPending()
		if pendingData then
			AuctionUI.Refs.ClaimGoldText.Text = string.format("정산 가능 대금: %s 골드", AuctionUI.FormatNumber(pendingData.gold or 0))
			
			-- 이력 갱신
			for _, child in ipairs(AuctionUI.Refs.HistoryScroll:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			
			for _, hist in ipairs(pendingData.history or {}) do
				local itemData = DataHelper.GetData("ItemData", hist.itemId)
				local name = itemData and itemData.name or hist.itemId
				
				local histFrame = Utils.mkFrame({
					size = UDim2.new(1, -10, 0, 50),
					bg = Color3.fromRGB(15, 15, 25),
					bgT = 0.5,
					r = 4,
					parent = AuctionUI.Refs.HistoryScroll
				})
				
				Utils.mkLabel({
					text = string.format("%s %d개 판매 완료", name, hist.count),
					size = UDim2.new(0.6, 0, 1, 0),
					pos = UDim2.new(0, 10, 0, 0),
					ts = 13,
					color = C.WHITE,
					ax = Enum.TextXAlignment.Left,
					parent = histFrame
				})
				
				Utils.mkLabel({
					text = string.format("+%s 골드", AuctionUI.FormatNumber(hist.count * hist.pricePerUnit)),
					size = UDim2.new(0.4, -10, 1, 0),
					pos = UDim2.new(0.6, 0, 0, 0),
					ts = 13,
					font = F.TITLE,
					color = C.GREEN,
					ax = Enum.TextXAlignment.Right,
					parent = histFrame
				})
			end
			
			local layout = AuctionUI.Refs.HistoryScroll:FindFirstChildOfClass("UIListLayout")
			AuctionUI.Refs.HistoryScroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
		end
		
		-- 내 등록 물품 갱신
		for _, child in ipairs(AuctionUI.Refs.MyScroll:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		
		local listings = AuctionController.getListings()
		if listings then
			local myId = Players.LocalPlayer.UserId
			local count = 0
			for _, entry in ipairs(listings) do
				if entry.sellerId == myId then
					count = count + 1
					local itemData = DataHelper.GetData("ItemData", entry.itemId)
					local name = itemData and itemData.name or entry.itemId
					
					local myFrame = Utils.mkFrame({
						size = UDim2.new(1, -10, 0, 60),
						bg = Color3.fromRGB(15, 15, 25),
						bgT = 0.5,
						r = 4,
						parent = AuctionUI.Refs.MyScroll
					})
					
					-- 아이콘
					local icon = Instance.new("ImageButton")
					icon.Size = UDim2.new(0, 44, 0, 44)
					icon.Position = UDim2.new(0, 8, 0.5, 0)
					icon.AnchorPoint = Vector2.new(0, 0.5)
					icon.BackgroundTransparency = 1
					icon.Image = currentUIManager.getItemIcon(entry.itemId)
					icon.Parent = myFrame
					
					local nameLabel = Utils.mkLabel({
						text = string.format("%s (x%d)", name, entry.count),
						size = UDim2.new(0.4, 0, 0.5, 0),
						pos = UDim2.new(0, 60, 0, 5),
						ts = 14,
						font = F.TITLE,
						color = C.WHITE,
						ax = Enum.TextXAlignment.Left,
						parent = myFrame
					})
					
					local nameBtn = Instance.new("TextButton")
					nameBtn.Size = UDim2.new(1, 0, 1, 0)
					nameBtn.BackgroundTransparency = 1
					nameBtn.Text = ""
					nameBtn.Parent = nameLabel
					
					local function showItemDetail()
						AuctionUI.OpenItemDetailPopup(entry, name, rarityColor)
					end
					
					icon.MouseButton1Click:Connect(showItemDetail)
					nameBtn.MouseButton1Click:Connect(showItemDetail)
					
					Utils.mkLabel({
						text = string.format("등록가: %s 골드", AuctionUI.FormatNumber(entry.pricePerUnit * entry.count)),
						size = UDim2.new(0.4, 0, 0.5, 0),
						pos = UDim2.new(0, 60, 0.5, 0),
						ts = 13,
						color = C.GRAY,
						ax = Enum.TextXAlignment.Left,
						parent = myFrame
					})
					
					-- 취소 버튼
					Utils.mkBtn({
						text = "회수",
						size = UDim2.new(0, 64, 0, 32),
						pos = UDim2.new(1, -10, 0.5, 0),
						anchor = Vector2.new(1, 0.5),
						bg = C.BTN_GRAY,
						hbg = C.BTN_GRAY_H,
						color = C.WHITE,
						isNegative = true,
						ts = 13,
						font = F.TITLE,
						r = 4,
						fn = function()
							task.spawn(function()
								local success = AuctionController.cancelSale(entry.listingId)
								if success then
									AuctionUI.RefreshManageTab()
									AuctionUI.RefreshListings()
								end
							end)
						end,
						parent = myFrame
					})
				end
			end
			
			local layout = AuctionUI.Refs.MyScroll:FindFirstChildOfClass("UIListLayout")
			AuctionUI.Refs.MyScroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
		end
	end)
end

function AuctionUI.ClaimPendingGold()
	task.spawn(function()
		local success, goldOrErr = AuctionController.claimPending()
		if success then
			AuctionUI.RefreshManageTab()
		end
	end)
end

function AuctionUI.RefreshPendingOnly(data)
	if AuctionUI.Refs.ClaimGoldText and AuctionUI.Refs.Frame and AuctionUI.Refs.Frame.Visible then
		local gold = data and data.gold or 0
		AuctionUI.Refs.ClaimGoldText.Text = string.format("정산 가능 대금: %s 골드", AuctionUI.FormatNumber(gold))
		
		-- 정산 탭인 경우 실시간 업데이트
		if activeTab == "MANAGE" then
			AuctionUI.RefreshManageTab()
		end
	end
end

return AuctionUI
