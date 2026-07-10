-- TradeUI.lua
-- 1:1 직거래 UI (경매장 대체) — 상호 제안 구성 + 교환하기 확정
-- [Navy + Black Glassmorphism, InventoryUI/DismantleUI와 동일 컨벤션]
-- [모바일 대응] 모든 크기/좌표는 Scale(비율) 기반으로 구성하고, 절대 픽셀은 아이콘/보더 등
-- 화면 크기와 무관해야 하는 아주 작은 디테일에만 최소한으로 사용한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local TradeController = require(Controllers:WaitForChild("TradeController"))
local ShopController = require(Controllers:WaitForChild("ShopController"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local GOLD_INPUT_MAX_DIGITS = #tostring(Balance.GOLD_CAP)

-- Navy + Black Theme Override (Convention match with InventoryUI/DismantleUI)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL   = Color3.fromRGB(10, 15, 25)
C.BG_DARK    = Color3.fromRGB(5, 5, 10)
C.BG_SLOT    = Color3.fromRGB(12, 12, 15)
C.BORDER     = Color3.fromRGB(60, 85, 130)
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.GOLD_SEL   = Color3.fromRGB(40, 80, 160)
C.BTN        = Color3.fromRGB(40, 80, 160)
C.BTN_H      = Color3.fromRGB(60, 100, 180)
C.GREEN      = Color3.fromRGB(120, 220, 120)

local F = Theme.Fonts
local TradeUI = {}

TradeUI.Refs = {}
TradeUI.State = {
	partnerUserId = nil,
	snapshot = nil,
}

local UI_MANAGER = nil
local IS_MOBILE = false

local function setIconImage(uiObject, icon)
	uiObject.Image = (icon and icon ~= "") and icon or ""
end

-- 정사각형 유지가 필요한 요소(아이콘 슬롯 등)에 부착 — 폭을 고정 픽셀이 아니라
-- 자신의 높이(부모가 정한 Scale 크기)에 맞춰 자동 계산하게 한다.
local function makeSquare(obj)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = obj
end

--========================================
-- 초대 팝업 (거래창과 별개의 작은 모달)
--========================================
function TradeUI.ShowInvite(data)
	local parent = TradeUI.Refs.ScreenParent
	if not parent then return end

	local existing = parent:FindFirstChild("TradeInvitePopup")
	if existing then existing:Destroy() end

	local popup = Utils.mkWindow({
		name = "TradeInvitePopup",
		size = UDim2.new(0.42, 0, 0.26, 0),
		maxSize = Vector2.new(420, 210),
		pos = UDim2.new(0.5, 0, 0.35, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.1,
		stroke = 2,
		strokeC = C.BORDER,
		r = 10,
		parent = parent,
	})

	Utils.mkLabel({
		text = string.format("%s 님이 거래를 요청했습니다.", data and data.fromName or "?"),
		size = UDim2.new(0.92, 0, 0.5, 0),
		pos = UDim2.new(0.5, 0, 0.28, 0),
		anchor = Vector2.new(0.5, 0.5),
		font = F.NORMAL,
		ts = IS_MOBILE and 17 or 15,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Center,
		wrap = true,
		parent = popup,
	})

	local btnRow = Utils.mkFrame({
		name = "BtnRow",
		size = UDim2.new(0.92, 0, 0.28, 0),
		pos = UDim2.new(0.5, 0, 0.86, 0),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = popup,
	})
	local btnRowLayout = Instance.new("UIListLayout")
	btnRowLayout.FillDirection = Enum.FillDirection.Horizontal
	btnRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnRowLayout.Padding = UDim.new(0.06, 0)
	btnRowLayout.Parent = btnRow

	Utils.mkBtn({
		text = "수락",
		size = UDim2.new(0.44, 0, 1, 0),
		bg = C.BTN,
		hbg = C.BTN_H,
		color = C.WHITE,
		ts = IS_MOBILE and 17 or 15,
		font = F.TITLE,
		r = 6,
		fn = function()
			TradeController.respond(true)
			popup:Destroy()
		end,
		parent = btnRow,
	})

	Utils.mkBtn({
		text = "거절",
		size = UDim2.new(0.44, 0, 1, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = IS_MOBILE and 17 or 15,
		font = F.TITLE,
		r = 6,
		fn = function()
			TradeController.respond(false)
			popup:Destroy()
		end,
		parent = btnRow,
	})

	-- [안전장치] 서버가 "Trade.Expired"로 정상 통지하지 못하는 극단적 상황(연결 끊김 등)을 대비한
	-- 여유있는 폴백 제거. 정상적인 경우엔 서버 만료 통지(CloseInvite 호출)가 이보다 먼저 닫는다.
	task.delay(25, function()
		if popup and popup.Parent then popup:Destroy() end
	end)
end

--- 서버로부터 만료/취소 통지를 받았을 때 열려있는 초대 팝업을 닫는다
function TradeUI.CloseInvite()
	local parent = TradeUI.Refs.ScreenParent
	if not parent then return end
	local existing = parent:FindFirstChild("TradeInvitePopup")
	if existing then existing:Destroy() end
end

--========================================
-- 주변 유저 목록 팝업 (HUD "거래" 버튼에서 오픈)
--========================================
function TradeUI.ShowPlayerList()
	local parent = TradeUI.Refs.ScreenParent
	if not parent then return end

	local existing = parent:FindFirstChild("TradePlayerListPopup")
	if existing then existing:Destroy() end

	local popup = Utils.mkWindow({
		name = "TradePlayerListPopup",
		size = UDim2.new(0.4, 0, 0.55, 0),
		maxSize = Vector2.new(360, 440),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.1,
		stroke = 2,
		strokeC = C.BORDER,
		r = 10,
		parent = parent,
	})

	Utils.mkLabel({
		text = "거래할 플레이어 선택",
		size = UDim2.new(0.75, 0, 0.09, 0),
		pos = UDim2.new(0.04, 0, 0.03, 0),
		font = F.TITLE,
		ts = IS_MOBILE and 18 or 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = popup,
	})

	local closeBtn = Utils.mkBtn({
		text = "X",
		size = UDim2.new(0.09, 0, 0.06, 0),
		pos = UDim2.new(0.97, 0, 0.03, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = IS_MOBILE and 16 or 14,
		font = F.TITLE,
		r = 6,
		fn = function()
			popup:Destroy()
		end,
		parent = popup,
	})
	makeSquare(closeBtn)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PlayerScroll"
	scroll.Size = UDim2.new(0.94, 0, 0.84, 0)
	scroll.Position = UDim2.new(0.03, 0, 0.14, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.BORDER_DIM
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = popup

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0.02, 0)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	local nearby = TradeController.getNearbyPlayers()

	if #nearby == 0 then
		Utils.mkLabel({
			text = "주변에 거래 가능한 플레이어가 없습니다.",
			size = UDim2.new(1, 0, 0, IS_MOBILE and 70 or 60),
			font = F.NORMAL,
			ts = IS_MOBILE and 15 or 13,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Center,
			wrap = true,
			parent = scroll,
		})
	end

	-- 스크롤 목록의 행은 AutomaticCanvasSize와 함께 쓰이므로 정확한 픽셀 높이가 필요하다
	-- (스크롤 콘텐츠 높이는 필연적으로 절대값 — 터치 사용성을 위해 모바일에서만 더 크게)
	local rowHeightPx = IS_MOBILE and 58 or 48
	for i, entry in ipairs(nearby) do
		local row = Utils.mkFrame({
			name = "Row" .. i,
			size = UDim2.new(1, 0, 0, rowHeightPx),
			bg = C.BG_SLOT,
			r = 6,
			stroke = 1,
			strokeC = C.BORDER_DIM,
			parent = scroll,
		})

		local infoArea = Utils.mkFrame({
			name = "Info",
			size = UDim2.new(0.7, 0, 1, 0),
			bgT = 1,
			parent = row,
		})

		Utils.mkLabel({
			text = entry.player.Name,
			size = UDim2.new(1, 0, 0.55, 0),
			pos = UDim2.new(0.06, 0, 0.08, 0),
			font = F.TITLE,
			ts = IS_MOBILE and 16 or 14,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Left,
			parent = infoArea,
		})

		Utils.mkLabel({
			text = string.format("%.0fm", entry.distance),
			size = UDim2.new(1, 0, 0.4, 0),
			pos = UDim2.new(0.06, 0, 0.55, 0),
			font = F.NORMAL,
			ts = IS_MOBILE and 13 or 12,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Left,
			parent = infoArea,
		})

		Utils.mkBtn({
			text = "요청",
			size = UDim2.new(0.26, 0, 0.7, 0),
			pos = UDim2.new(0.97, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			bg = C.BTN,
			hbg = C.BTN_H,
			color = C.WHITE,
			ts = IS_MOBILE and 15 or 13,
			font = F.TITLE,
			r = 6,
			fn = function()
				TradeController.requestTrade(entry.player.UserId, entry.player.Name)
				popup:Destroy()
			end,
			parent = row,
		})
	end
end

--========================================
-- 오퍼 아이템 스트립 렌더링 (내/상대 공통)
--========================================
local function renderOfferStrip(container, offerSlots, interactive)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") and child.Name:sub(1, 5) == "Item_" then
			child:Destroy()
		end
	end

	-- [버그수정] UIAspectRatioConstraint를 0폭에서 계산시키면 실패해서 셀이 비정상 크기로
	-- 렌더링되어 하단 골드/인벤토리 클릭 영역을 가려버리는 문제가 있었음.
	-- 인벤토리 그리드와 동일하게 컨테이너 실측 높이에서 정사각형 픽셀 크기를 직접 계산한다.
	local stripHeightPx = container.AbsoluteSize.Y
	if stripHeightPx <= 0 then stripHeightPx = 56 end -- 첫 렌더 프레임 안전값

	-- [버그수정] 슬롯 번호는 각자 인벤토리에서만 의미가 있는 값이라, 내 인벤토리로 상대방의
	-- 슬롯을 조회하면 당연히 아무것도 안 나온다("상대 제안"이 텅 비어 보이던 원인).
	-- 서버가 스냅샷에 itemId를 직접 실어 보내므로 그걸 그대로 쓴다.
	local index = 0
	for slot, entry in pairs(offerSlots or {}) do
		local itemId = entry and entry.itemId
		local count = entry and entry.count or 0
		if itemId then
			index += 1

			local cell = Utils.mkFrame({
				name = "Item_" .. slot,
				size = UDim2.new(0, stripHeightPx, 0, stripHeightPx),
				bg = C.BG_SLOT,
				r = 6,
				stroke = 1,
				strokeC = C.BORDER_DIM,
				parent = container,
			})
			cell.LayoutOrder = index

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0.85, 0, 0.85, 0)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.BackgroundTransparency = 1
			setIconImage(icon, UI_MANAGER.getItemIcon(itemId))
			icon.Parent = cell

			Utils.mkLabel({
				text = "x" .. tostring(count),
				size = UDim2.new(0.5, 0, 0.3, 0),
				pos = UDim2.new(0.95, 0, 0.92, 0),
				anchor = Vector2.new(1, 1),
				font = F.TITLE,
				ts = IS_MOBILE and 13 or 11,
				color = Color3.fromRGB(255, 240, 150),
				ax = Enum.TextXAlignment.Right,
				parent = cell,
			})

			if interactive then
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 1, 0)
				btn.BackgroundTransparency = 1
				btn.Text = ""
				btn.Parent = cell
				btn.MouseButton1Click:Connect(function()
					TradeController.updateOffer({ [tostring(slot)] = 0 }, nil)
				end)
			end
		end
	end
end

--========================================
-- 내 인벤토리 그리드 (클릭해서 오퍼에 추가)
--========================================
local function renderMyInventoryGrid()
	local scroll = TradeUI.Refs.InvScroll
	if not scroll then return end

	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child.Name:sub(1, 5) == "Slot_" then
			child:Destroy()
		end
	end

	local items = InventoryController.getItems()
	local offeredSlots = TradeUI.State.snapshot and TradeUI.State.snapshot.myOffer.slots or {}

	for slot, slotData in pairs(items) do
		if slotData and slotData.itemId and DataHelper.IsTradeable(slotData.itemId) then
			local isOffered = offeredSlots[slot] ~= nil

			local cell = Utils.mkFrame({
				name = "Slot_" .. slot,
				bg = C.BG_SLOT,
				r = 6,
				stroke = isOffered and 2 or 1,
				strokeC = isOffered and C.GOLD_SEL or C.BORDER_DIM,
				parent = scroll,
			})

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0.85, 0, 0.85, 0)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.BackgroundTransparency = 1
			icon.ImageTransparency = isOffered and 0.5 or 0
			setIconImage(icon, UI_MANAGER.getItemIcon(slotData.itemId))
			icon.Parent = cell

			Utils.mkLabel({
				text = "x" .. tostring(slotData.count or 1),
				size = UDim2.new(0.5, 0, 0.3, 0),
				pos = UDim2.new(0.95, 0, 0.92, 0),
				anchor = Vector2.new(1, 1),
				font = F.TITLE,
				ts = IS_MOBILE and 13 or 11,
				color = C.WHITE,
				ax = Enum.TextXAlignment.Right,
				parent = cell,
			})

			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 1, 0)
			btn.BackgroundTransparency = 1
			btn.Text = ""
			btn.Parent = cell
			btn.MouseButton1Click:Connect(function()
				if isOffered then
					TradeController.updateOffer({ [tostring(slot)] = 0 }, nil)
				else
					TradeController.updateOffer({ [tostring(slot)] = slotData.count or 1 }, nil)
				end
			end)
		end
	end
end

--========================================
-- 스냅샷 반영 (오퍼/확정 상태 갱신)
--========================================
local function applySnapshot(data)
	if not data then return end
	TradeUI.State.snapshot = data
	TradeUI.State.partnerUserId = data.partnerUserId

	if TradeUI.Refs.PartnerName then
		TradeUI.Refs.PartnerName.Text = data.partnerName or "?"
	end

	renderOfferStrip(TradeUI.Refs.MyOfferStrip, data.myOffer.slots, true)
	renderOfferStrip(TradeUI.Refs.TheirOfferStrip, data.theirOffer.slots, false)

	if TradeUI.Refs.MyGoldBox and not TradeUI.Refs.MyGoldBox:IsFocused() then
		TradeUI.Refs.MyGoldBox.Text = tostring(data.myOffer.gold or 0)
	end
	if TradeUI.Refs.TheirGoldLbl then
		TradeUI.Refs.TheirGoldLbl.Text = string.format("골드: %d", data.theirOffer.gold or 0)
	end

	if TradeUI.Refs.ExchangeBtn then
		TradeUI.Refs.ExchangeBtn.Text = data.myConfirmed and "확정함 (취소하려면 클릭)" or "교환하기"
		TradeUI.Refs.ExchangeBtn.BackgroundColor3 = data.myConfirmed and C.GREEN or C.BTN
	end
	if TradeUI.Refs.TheirConfirmLbl then
		TradeUI.Refs.TheirConfirmLbl.Text = data.theirConfirmed and "상대방: 확정함" or "상대방: 대기 중"
		TradeUI.Refs.TheirConfirmLbl.TextColor3 = data.theirConfirmed and C.GREEN or C.GRAY
	end

	renderMyInventoryGrid()
end

--========================================
-- Init
--========================================
function TradeUI.Init(parent, manager, isMobile)
	UI_MANAGER = manager
	IS_MOBILE = isMobile or false
	TradeUI.Refs.ScreenParent = parent

	local window = Utils.mkWindow({
		name = "TradeWindow",
		size = UDim2.new(0.9, 0, 0.86, 0),
		maxSize = Vector2.new(820, 560),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.15,
		stroke = 2,
		strokeC = C.BORDER,
		r = 12,
		vis = false,
		parent = parent,
	})
	TradeUI.Refs.Frame = window
	TradeUI.Refs.Main = window

	-- ── 헤더 (제목 + 상대 이름 + 닫기) : 창 높이의 상단 15% ──
	Utils.mkLabel({
		text = "1:1 거래",
		size = UDim2.new(0.5, 0, 0.07, 0),
		pos = UDim2.new(0.025, 0, 0.025, 0),
		font = F.TITLE,
		ts = IS_MOBILE and 22 or 20,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	TradeUI.Refs.PartnerName = Utils.mkLabel({
		text = "",
		size = UDim2.new(0.5, 0, 0.05, 0),
		pos = UDim2.new(0.03, 0, 0.095, 0),
		font = F.NORMAL,
		ts = IS_MOBILE and 15 or 13,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = window,
	})

	local closeBtn = Utils.mkBtn({
		text = "X",
		size = UDim2.new(0.06, 0, 0.06, 0),
		pos = UDim2.new(0.975, 0, 0.025, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = IS_MOBILE and 18 or 16,
		font = F.TITLE,
		r = 6,
		fn = function()
			TradeController.cancel()
		end,
		parent = window,
	})
	makeSquare(closeBtn)

	-- ── 본문 (좌: 내 제안 / 우: 상대 제안) : 15% ~ 78% ──
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(0.95, 0, 0.63, 0),
		pos = UDim2.new(0.025, 0, 0.15, 0),
		bgT = 1,
		parent = window,
	})

	-- 왼쪽: 내 제안
	local leftFrame = Utils.mkFrame({
		name = "LeftFrame",
		size = UDim2.new(0.49, 0, 1, 0),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = body,
	})

	Utils.mkLabel({
		text = "내 제안",
		size = UDim2.new(0.9, 0, 0.09, 0),
		pos = UDim2.new(0.05, 0, 0.02, 0),
		font = F.TITLE,
		ts = IS_MOBILE and 16 or 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = leftFrame,
	})

	local myOfferStrip = Utils.mkFrame({
		name = "MyOfferStrip",
		size = UDim2.new(0.9, 0, 0.17, 0),
		pos = UDim2.new(0.05, 0, 0.12, 0),
		bgT = 1,
		parent = leftFrame,
	})
	TradeUI.Refs.MyOfferStrip = myOfferStrip
	local myOfferLayout = Instance.new("UIListLayout")
	myOfferLayout.FillDirection = Enum.FillDirection.Horizontal
	myOfferLayout.Padding = UDim.new(0.02, 0)
	myOfferLayout.Parent = myOfferStrip

	local goldRow = Utils.mkFrame({
		name = "GoldRow",
		size = UDim2.new(0.9, 0, 0.09, 0),
		pos = UDim2.new(0.05, 0, 0.32, 0),
		bg = C.BG_SLOT,
		r = 6,
		parent = leftFrame,
	})
	Utils.mkLabel({
		text = "골드:",
		size = UDim2.new(0.25, 0, 1, 0),
		pos = UDim2.new(0.04, 0, 0, 0),
		font = F.NORMAL,
		ts = IS_MOBILE and 15 or 13,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		parent = goldRow,
	})
	local myGoldBox = Instance.new("TextBox")
	myGoldBox.Name = "MyGoldBox"
	myGoldBox.Text = "0"
	myGoldBox.Size = UDim2.new(0.68, 0, 0.86, 0)
	myGoldBox.Position = UDim2.new(0.3, 0, 0.07, 0)
	myGoldBox.BackgroundTransparency = 1
	myGoldBox.TextSize = IS_MOBILE and 16 or 14
	myGoldBox.TextColor3 = C.WHITE
	myGoldBox.Font = F.NORMAL
	myGoldBox.TextXAlignment = Enum.TextXAlignment.Left
	myGoldBox.ClearTextOnFocus = false
	myGoldBox.Parent = goldRow
	TradeUI.Refs.MyGoldBox = myGoldBox

	-- [버그수정] 골드 입력에 자릿수/최대값 제한이 전혀 없어서 무한정 입력이 가능했음.
	-- Balance.GOLD_CAP 자릿수로 입력 길이를 막고, 포커스를 벗어날 때 실제 보유 골드 이내로 clamp한다.
	myGoldBox:GetPropertyChangedSignal("Text"):Connect(function()
		local cleanText = myGoldBox.Text:gsub("%D", "")
		if #cleanText > GOLD_INPUT_MAX_DIGITS then
			cleanText = cleanText:sub(1, GOLD_INPUT_MAX_DIGITS)
		end
		if myGoldBox.Text ~= cleanText then
			myGoldBox.Text = cleanText
		end
	end)
	myGoldBox.FocusLost:Connect(function()
		local val = tonumber(myGoldBox.Text) or 0
		local myGold = ShopController.getGold() or 0
		val = math.clamp(val, 0, math.min(myGold, Balance.GOLD_CAP))
		myGoldBox.Text = tostring(val)
		TradeController.updateOffer(nil, val)
	end)

	Utils.mkLabel({
		text = "내 인벤토리 (클릭해서 추가/제거)",
		size = UDim2.new(0.9, 0, 0.06, 0),
		pos = UDim2.new(0.05, 0, 0.44, 0),
		font = F.NORMAL,
		ts = IS_MOBILE and 13 or 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		parent = leftFrame,
	})

	local invScroll = Instance.new("ScrollingFrame")
	invScroll.Name = "InvScroll"
	invScroll.Size = UDim2.new(0.9, 0, 0.49, 0)
	invScroll.Position = UDim2.new(0.05, 0, 0.505, 0)
	invScroll.BackgroundTransparency = 1
	invScroll.BorderSizePixel = 0
	invScroll.ScrollBarThickness = 4
	invScroll.ScrollBarImageColor3 = C.BORDER_DIM
	invScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	invScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invScroll.Parent = leftFrame
	TradeUI.Refs.InvScroll = invScroll

	-- [버그수정] ScrollingFrame은 기본적으로 내용을 잘라내므로(ClipsDescendants), 여백 없이
	-- 셀을 바로 붙이면 맨 가장자리 셀의 테두리(UIStroke)가 잘려 보인다.
	local invScrollPad = Instance.new("UIPadding")
	invScrollPad.PaddingTop = UDim.new(0.02, 0)
	invScrollPad.PaddingBottom = UDim.new(0.02, 0)
	invScrollPad.PaddingLeft = UDim.new(0.02, 0)
	invScrollPad.PaddingRight = UDim.new(0.02, 0)
	invScrollPad.Parent = invScroll

	local invGrid = Instance.new("UIGridLayout")
	invGrid.CellSize = UDim2.new(0.22, 0, 0, 0)
	invGrid.SortOrder = Enum.SortOrder.LayoutOrder
	invGrid.Parent = invScroll
	-- [버그수정] CellPadding의 Scale은 X가 컨테이너 폭, Y가 컨테이너 "높이" 기준이라
	-- 서로 다른 기준값 때문에 간격이 비대칭(비율이 엉망)으로 보였다. 셀 크기 자체를 기준으로
	-- 픽셀 값을 동일하게 계산해서 가로/세로 간격을 항상 정사각 비율로 맞춘다.
	local function syncGridCellHeight()
		local w = invScroll.AbsoluteSize.X
		if w <= 0 then return end
		local cellPx = w * 0.22
		local padPx = math.max(4, cellPx * 0.09)
		invGrid.CellSize = UDim2.new(0.22, 0, 0, cellPx)
		invGrid.CellPadding = UDim2.new(0, padPx, 0, padPx)
	end
	invScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncGridCellHeight)
	task.defer(syncGridCellHeight)

	-- 오른쪽: 상대 제안
	local rightFrame = Utils.mkFrame({
		name = "RightFrame",
		size = UDim2.new(0.49, 0, 1, 0),
		pos = UDim2.new(0.51, 0, 0, 0),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = body,
	})

	Utils.mkLabel({
		text = "상대 제안",
		size = UDim2.new(0.9, 0, 0.09, 0),
		pos = UDim2.new(0.05, 0, 0.02, 0),
		font = F.TITLE,
		ts = IS_MOBILE and 16 or 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = rightFrame,
	})

	local theirOfferStrip = Utils.mkFrame({
		name = "TheirOfferStrip",
		size = UDim2.new(0.9, 0, 0.17, 0),
		pos = UDim2.new(0.05, 0, 0.12, 0),
		bgT = 1,
		parent = rightFrame,
	})
	TradeUI.Refs.TheirOfferStrip = theirOfferStrip
	local theirOfferLayout = Instance.new("UIListLayout")
	theirOfferLayout.FillDirection = Enum.FillDirection.Horizontal
	theirOfferLayout.Padding = UDim.new(0.02, 0)
	theirOfferLayout.Parent = theirOfferStrip

	-- 창 크기가 확정/변경될 때 오퍼 스트립을 실측 크기로 다시 그려서 첫 프레임 폴백 크기를 보정
	local function reRenderOfferStrips()
		local snap = TradeUI.State.snapshot
		if not snap then return end
		renderOfferStrip(myOfferStrip, snap.myOffer.slots, true)
		renderOfferStrip(theirOfferStrip, snap.theirOffer.slots, false)
	end
	myOfferStrip:GetPropertyChangedSignal("AbsoluteSize"):Connect(reRenderOfferStrips)
	theirOfferStrip:GetPropertyChangedSignal("AbsoluteSize"):Connect(reRenderOfferStrips)

	TradeUI.Refs.TheirGoldLbl = Utils.mkLabel({
		text = "골드: 0",
		size = UDim2.new(0.9, 0, 0.08, 0),
		pos = UDim2.new(0.05, 0, 0.32, 0),
		font = F.NORMAL,
		ts = IS_MOBILE and 15 or 13,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = rightFrame,
	})

	Utils.mkLabel({
		text = "※ 상대 제안은 실시간으로만 확인할 수 있으며 직접 수정할 수 없습니다.",
		size = UDim2.new(0.9, 0, 0.16, 0),
		pos = UDim2.new(0.05, 0, 0.44, 0),
		font = F.NORMAL,
		ts = IS_MOBILE and 12 or 11,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = rightFrame,
	})

	-- ── 하단 (교환하기 / 취소) : 80% ~ 98% ──
	local bottomBar = Utils.mkFrame({
		name = "BottomBar",
		size = UDim2.new(0.95, 0, 0.18, 0),
		pos = UDim2.new(0.025, 0, 0.8, 0),
		bgT = 1,
		parent = window,
	})

	TradeUI.Refs.ExchangeBtn = Utils.mkBtn({
		text = "교환하기",
		size = UDim2.new(0.65, 0, 0.46, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = C.BTN,
		hbg = C.BTN_H,
		color = C.WHITE,
		ts = IS_MOBILE and 17 or 15,
		font = F.TITLE,
		r = 6,
		fn = function()
			local snap = TradeUI.State.snapshot
			local currentlyConfirmed = snap and snap.myConfirmed or false
			TradeController.confirm(not currentlyConfirmed)
		end,
		parent = bottomBar,
	})

	TradeUI.Refs.TheirConfirmLbl = Utils.mkLabel({
		text = "상대방: 대기 중",
		size = UDim2.new(0.33, 0, 0.46, 0),
		pos = UDim2.new(0.67, 0, 0, 0),
		font = F.NORMAL,
		ts = IS_MOBILE and 15 or 14,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Center,
		parent = bottomBar,
	})

	Utils.mkBtn({
		text = "거래 취소",
		size = UDim2.new(1, 0, 0.4, 0),
		pos = UDim2.new(0, 0, 0.56, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = IS_MOBILE and 15 or 13,
		font = F.NORMAL,
		r = 6,
		fn = function()
			TradeController.cancel()
		end,
		parent = bottomBar,
	})

	InventoryController.onChanged(function()
		if window.Visible then
			renderMyInventoryGrid()
		end
	end)
end

--========================================
-- Public API
--========================================
function TradeUI.SetVisible(visible)
	local window = TradeUI.Refs.Frame
	if not window then return end
	window.Visible = visible
end

function TradeUI.SetData(data)
	applySnapshot(data)
end

function TradeUI.Refresh(data)
	applySnapshot(data)
end

return TradeUI
