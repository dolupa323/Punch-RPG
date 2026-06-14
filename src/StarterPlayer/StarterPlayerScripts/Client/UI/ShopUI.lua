-- ShopUI.lua
-- Responsive split-layout shop UI: trader inventory on the left, player sell list on the right
-- Features: Navy/Black Theme, Quantity Input Modal for Sell/Buy, Mobile Responsive

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MaterialAttributeData"))

local function formatVal(num)
	local n = tonumber(num) or 0
	if n >= 1000000000000 then
		return string.format("%.2fT", n / 1000000000000)
	elseif n >= 1000000000 then
		return string.format("%.2fB", n / 1000000000)
	elseif n >= 1000000 then
		return string.format("%.2fM", n / 1000000)
	elseif n >= 1000 then
		local val = n / 1000
		if val % 1 == 0 then
			return string.format("%dK", val)
		else
			local formatted = string.format("%.2f", val)
			formatted = string.gsub(formatted, "%.?0+$", "")
			return formatted .. "K"
		end
	else
		return tostring(math.floor(n))
	end
end

-- Apply EnhanceUI/CraftingUI Navy/Black Convention
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

local T = Theme.Transp

local ShopUI = {}
ShopUI.IsMobile = false
ShopUI.Refs = {
	Frame = nil,
	Main = nil,
	Title = nil,
	Subtitle = nil,
	GoldLabel = nil,
	TraderPanel = nil,
	PlayerPanel = nil,
	TraderScroll = nil,
	PlayerScroll = nil,
	QuantityModal = nil,
}

local function clearContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "ContentPadding" and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function resolveItemName(itemId: string): string
	local itemData = DataHelper.GetData("ItemData", itemId)
	local rawName = (itemData and itemData.name) or tostring(itemId)
	return UILocalizer.LocalizeDataText("ItemData", itemId, "name", rawName)
end

local function formatAttributes(attributes: any): string
	if type(attributes) ~= "table" then
		return ""
	end

	local chunks = {}
	for attrId, attrLevel in pairs(attributes) do
		local attrInfo = MaterialAttributeData.getAttribute(attrId)
		if attrInfo then
			table.insert(chunks, string.format("%s Lv.%d", attrInfo.name, tonumber(attrLevel) or 1))
		end
	end
	table.sort(chunks)
	return table.concat(chunks, ", ")
end

-- ==========================================
-- Quantity Modal
-- ==========================================
local function showQuantityModal(titleText: string, itemName: string, maxQty: number, unitPrice: number, onConfirm: (number) -> ())
	local modal = ShopUI.Refs.QuantityModal
	if not modal then return end
	
	modal.Visible = true
	local currentQty = 1
	
	local title = modal:FindFirstChild("Title", true)
	local itemLbl = modal:FindFirstChild("ItemName", true)
	local qtyLbl = modal:FindFirstChild("QtyText", true)
	local priceLbl = modal:FindFirstChild("PriceText", true)
	
	if title then title.Text = UILocalizer.Localize(titleText) end
	if itemLbl then itemLbl.Text = itemName end
	
	local function updateUI()
		if qtyLbl then qtyLbl.Text = tostring(currentQty) end
		if priceLbl then priceLbl.Text = UILocalizer.Localize(string.format("총 %s G", formatVal(unitPrice * currentQty))) end
	end
	
	updateUI()
	
	local btnMinus = modal:FindFirstChild("BtnMinus", true)
	local btnPlus = modal:FindFirstChild("BtnPlus", true)
	local btnMax = modal:FindFirstChild("BtnMax", true)
	local btnConfirm = modal:FindFirstChild("BtnConfirm", true)
	local btnCancel = modal:FindFirstChild("BtnCancel", true)
	
	-- Disconnect previous connections to prevent memory leaks and stacked handlers
	if ShopUI._qtyConnections then
		for _, conn in ipairs(ShopUI._qtyConnections) do
			conn:Disconnect()
		end
	end
	ShopUI._qtyConnections = {}
	local function track(conn)
		table.insert(ShopUI._qtyConnections, conn)
	end
	
	if btnMinus then
		track(btnMinus.MouseButton1Click:Connect(function()
			if currentQty > 1 then
				currentQty -= 1
				updateUI()
			end
		end))
	end
	
	if btnPlus then
		track(btnPlus.MouseButton1Click:Connect(function()
			if currentQty < maxQty then
				currentQty += 1
				updateUI()
			end
		end))
	end
	
	if btnMax then
		track(btnMax.MouseButton1Click:Connect(function()
			currentQty = maxQty
			updateUI()
		end))
	end
	
	if btnCancel then
		track(btnCancel.MouseButton1Click:Connect(function()
			modal.Visible = false
		end))
	end
	
	if btnConfirm then
		track(btnConfirm.MouseButton1Click:Connect(function()
			modal.Visible = false
			onConfirm(currentQty)
		end))
	end
	
	if qtyLbl and qtyLbl:IsA("TextBox") then
		track(qtyLbl.FocusLost:Connect(function()
			local val = tonumber(qtyLbl.Text)
			if not val or val < 1 then
				val = 1
			elseif val > maxQty then
				val = maxQty
			end
			currentQty = val
			updateUI()
		end))
		
		track(qtyLbl:GetPropertyChangedSignal("Text"):Connect(function()
			local cleanText = qtyLbl.Text:gsub("%D", "")
			if qtyLbl.Text ~= cleanText then
				qtyLbl.Text = cleanText
			end
			local val = tonumber(cleanText)
			if val then
				if val > maxQty then
					val = maxQty
					qtyLbl.Text = tostring(val)
				end
				if val > 0 then
					if priceLbl then
						priceLbl.Text = UILocalizer.Localize(string.format("총 %s G", formatVal(unitPrice * val)))
					end
				end
			end
		end))
	end
end

-- ==========================================
-- Section Header
-- ==========================================
local function makeSectionHeader(parent: Instance, title: string, subtitle: string?)
	local header = Utils.mkFrame({
		name = "SectionHeader",
		size = UDim2.new(1, 0, 0, 58),
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})
	header.LayoutOrder = -1

	Utils.mkLabel({
		text = title,
		size = UDim2.new(1, -20, 0, 24),
		pos = UDim2.new(0, 10, 0, 8),
		ts = 17,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	if subtitle and subtitle ~= "" then
		Utils.mkLabel({
			text = subtitle,
			size = UDim2.new(1, -20, 0, 18),
			pos = UDim2.new(0, 10, 0, 32),
			ts = ShopUI.IsMobile and 11 or 12,
			color = C.BORDER,
			ax = Enum.TextXAlignment.Left,
			wrap = true,
			parent = header,
		})
	end
	return header
end

local function makeEmptyState(parent: Instance, text: string)
	local frame = Utils.mkFrame({
		name = "EmptyState",
		size = UDim2.new(1, 0, 0, 72),
		bg = C.BG_DARK,
		bgT = 0.6,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	Utils.mkLabel({
		text = text,
		size = UDim2.new(1, -20, 1, 0),
		pos = UDim2.new(0, 10, 0, 0),
		ts = ShopUI.IsMobile and 12 or 13,
		color = C.BORDER,
		wrap = true,
		parent = frame,
	})
end

-- ==========================================
-- Item Row
-- ==========================================
local function makeItemRow(parent: Instance, itemId: string, nameText: string, detailText: string, priceText: string, accentText: string?, iconResolver: (string) -> string, actionLabel: string?, actionCallback: (() -> ())?)
	local rowHeight = 94
	local iconSize = 54
	local actionWidth = 72
	local priceWidth = 90
	
	local row = Utils.mkFrame({
		name = "ItemRow_" .. tostring(itemId),
		size = UDim2.new(1, 0, 0, rowHeight),
		bg = C.BG_SLOT,
		bgT = 0.3, 
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = parent,
	})

	local iconWrap = Utils.mkFrame({
		name = "IconWrap",
		size = UDim2.new(0, iconSize, 0, iconSize),
		pos = UDim2.new(0, 12, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_DARK,
		bgT = 0.2,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = row,
	})

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0.8, 0, 0.8, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconResolver and iconResolver(itemId) or ""
	icon.Parent = iconWrap

	-- Details container (Responsive width)
	local detailContainer = Utils.mkFrame({
		name = "Details",
		size = UDim2.new(1, -(iconSize + 24 + actionWidth + 16), 1, 0),
		pos = UDim2.new(0, iconSize + 24, 0, 0),
		bgT = 1,
		parent = row
	})

	Utils.mkLabel({
		text = nameText,
		size = UDim2.new(1, 0, 0, 22),
		pos = UDim2.new(0, 0, 0, 10),
		ts = 15,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = detailContainer,
	})

	Utils.mkLabel({
		text = detailText,
		size = UDim2.new(1, 0, 0, 18),
		pos = UDim2.new(0, 0, 0, 36),
		ts = ShopUI.IsMobile and 11 or 12,
		color = C.BORDER,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = detailContainer,
	})

	if accentText and accentText ~= "" then
		Utils.mkLabel({
			text = accentText,
			size = UDim2.new(1, 0, 0, 18),
			pos = UDim2.new(0, 0, 0, 56),
			ts = ShopUI.IsMobile and 11 or 12,
			color = C.GOLD_SEL,
			ax = Enum.TextXAlignment.Left,
			wrap = true,
			parent = detailContainer,
		})
	end

	-- Price & Action (Right aligned)
	local rightContainer = Utils.mkFrame({
		name = "RightArea",
		size = UDim2.new(0, math.max(actionWidth, priceWidth), 1, 0),
		pos = UDim2.new(1, -12, 0, 0),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		parent = row
	})

	Utils.mkLabel({
		text = priceText,
		size = UDim2.new(1, 0, 0, 22),
		pos = UDim2.new(0, 0, 0, 12),
		ts = 15,
		bold = true,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Right,
		parent = rightContainer,
	})

	if actionCallback then
		Utils.mkBtn({
			text = actionLabel or "선택",
			size = UDim2.new(0, actionWidth, 0, 34),
			pos = UDim2.new(1, 0, 1, -12),
			anchor = Vector2.new(1, 1),
			bg = C.BTN,
			hbg = C.BTN_H,
			color = C.WHITE,
			ts = 13,
			r = 6,
			parent = rightContainer,
			fn = actionCallback,
		})
	end

	return row
end

local function makeColumnPanel(parent: Instance, name: string, size: UDim2, layoutOrder: number): (Frame, ScrollingFrame)
	local panel = Utils.mkFrame({
		name = name,
		size = size,
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 10,
		stroke = 2,
		strokeC = C.BORDER,
		parent = parent,
	})
	panel.LayoutOrder = layoutOrder

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, -16, 1, -16)
	scroll.Position = UDim2.new(0, 8, 0, 8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = ShopUI.IsMobile and 4 or 6
	scroll.ScrollBarImageColor3 = C.BORDER
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = scroll

	return panel, scroll
end

local function populateTraderPane(scroll: Instance, shopInfo: any, iconResolver: (string) -> string, uiManager: any)
	clearContainer(scroll)

	local buyItems = (shopInfo and shopInfo.buyList) or {}
	local sellOnly = shopInfo and shopInfo.sellOnly == true
	makeSectionHeader(scroll, UILocalizer.Localize("교역상 판매 물품"), sellOnly and UILocalizer.Localize("이 상점은 매입만 합니다.") or UILocalizer.Localize("교역상이 판매하는 물품입니다."))

	if #buyItems == 0 then
		makeEmptyState(scroll, UILocalizer.Localize("구매할 수 있는 물품이 없습니다."))
		return
	end

	for i, item in ipairs(buyItems) do
		local stockText = UILocalizer.Localize((item.stock and item.stock >= 0) and string.format("재고 %d개", item.stock) or "재고 무제한")
		local itemName = resolveItemName(item.itemId)
		local unitPrice = tonumber(item.price) or 0
		
		local row = makeItemRow(
			scroll,
			item.itemId,
			itemName,
			stockText,
			string.format("%d G", unitPrice),
			nil,
			iconResolver,
			UILocalizer.Localize("구매"),
			function()
				-- 수량이 1개보다 많게 구매 가능한 경우 (재고 무제한이거나 재고 > 1)
				local maxBuy = item.stock and item.stock >= 0 and item.stock or 99
				if maxBuy > 1 then
					showQuantityModal("아이템 구매", itemName, maxBuy, unitPrice, function(amount)
						uiManager.requestBuy(item.itemId, amount)
					end)
				else
					uiManager.requestBuy(item.itemId, 1)
				end
			end
		)
		row.LayoutOrder = i
	end
end

local function populatePlayerPane(scroll: Instance, shopInfo: any, playerItems: any, iconResolver: (string) -> string, uiManager: any)
	clearContainer(scroll)

	local sellQuotes = (shopInfo and shopInfo.sellQuotes) or {}
	local acceptAllItems = shopInfo and shopInfo.acceptAllItems == true
	local subtitle = acceptAllItems and "거의 모든 전리품을 판매할 수 있습니다." or "상점이 매입하는 아이템 목록입니다."
	makeSectionHeader(scroll, UILocalizer.Localize("내 아이템 판매"), UILocalizer.Localize(subtitle))

	if #sellQuotes == 0 then
		makeEmptyState(scroll, UILocalizer.Localize("판매 가능한 아이템이 없습니다."))
		return
	end

	for i, quote in ipairs(sellQuotes) do
		local playerItem = playerItems and playerItems[quote.slot]
		local itemId = (playerItem and playerItem.itemId) or quote.itemId
		local itemName = resolveItemName(itemId)
		local attrText = formatAttributes((playerItem and playerItem.attributes) or quote.attributes)
		
		local count = quote.count or 1
		local unitPrice = quote.unitPrice or quote.totalPrice or 0
		
		local detailParts = {
			UILocalizer.Localize(string.format("보유 %d개", count)),
			UILocalizer.Localize(string.format("슬롯 %d", quote.slot or 0)),
		}

		if attrText ~= "" then
			table.insert(detailParts, attrText)
		end

		local accentText = nil
		if count > 1 and unitPrice > 0 then
			accentText = UILocalizer.Localize(string.format("개당 %d G", unitPrice))
		end

		local row = makeItemRow(
			scroll,
			itemId,
			itemName,
			table.concat(detailParts, " · "),
			string.format("%d G", unitPrice),
			accentText,
			iconResolver,
			UILocalizer.Localize("판매"),
			function()
				if count > 1 then
					showQuantityModal("아이템 판매", itemName, count, unitPrice, function(amount)
						uiManager.requestSell(quote.slot, amount)
					end)
				else
					uiManager.requestSell(quote.slot, 1)
				end
			end
		)
		row.LayoutOrder = i
	end
end

-- ==========================================
-- Main Public API
-- ==========================================
function ShopUI.Refresh(shopInfo, playerItems, getItemIcon, _themeColors, uiManager)
	if ShopUI.Refs.Title then
		ShopUI.Refs.Title.Text = UILocalizer.Localize((shopInfo and shopInfo.name) or "상점")
	end

	if ShopUI.Refs.Subtitle then
		local zoneName = shopInfo and shopInfo.zoneName
		local subtitle = UILocalizer.Localize((shopInfo and shopInfo.description) or "상점 정보를 확인하세요.")
		if zoneName and zoneName ~= "" then
			subtitle = UILocalizer.Localize(string.format("%s  |  지역: %s", subtitle, zoneName))
		end
		ShopUI.Refs.Subtitle.Text = subtitle
	end

	populateTraderPane(ShopUI.Refs.TraderScroll, shopInfo, getItemIcon, uiManager)
	populatePlayerPane(ShopUI.Refs.PlayerScroll, shopInfo, playerItems, getItemIcon, uiManager)
end

function ShopUI.SetVisible(visible)
	if ShopUI.Refs.Frame then
		ShopUI.Refs.Frame.Visible = visible
		if not visible and ShopUI.Refs.QuantityModal then
			ShopUI.Refs.QuantityModal.Visible = false
		end
	end
end

function ShopUI.UpdateGold(gold)
	if ShopUI.Refs.GoldLabel then
		ShopUI.Refs.GoldLabel.Text = string.format("%s G", formatVal(gold or 0))
	end
end

-- ==========================================
-- UI Initialization
-- ==========================================
local function createQuantityModal(parent: Instance)
	local overlay = Utils.mkFrame({
		name = "QuantityModalOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 0.5,
		vis = false,
		z = 10,
		parent = parent,
	})
	
	local box = Utils.mkWindow({
		name = "Box",
		size = UDim2.new(0, 320, 0, 220),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0,
		r = 12,
		stroke = 2,
		strokeC = C.BORDER,
		parent = overlay
	})
	
	Utils.mkLabel({
		name = "Title",
		text = "수량 선택",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0, 0, 0, 0),
		ts = 18,
		bold = true,
		color = C.WHITE,
		parent = box,
	})
	
	Utils.mkLabel({
		name = "ItemName",
		text = "아이템 이름",
		size = UDim2.new(1, -24, 0, 24),
		pos = UDim2.new(0, 12, 0, 40),
		ts = 15,
		color = C.GOLD_SEL,
		parent = box,
	})
	
	-- Qty Controls
	local qtyArea = Utils.mkFrame({
		name = "QtyArea",
		size = UDim2.new(1, -40, 0, 44),
		pos = UDim2.new(0, 20, 0, 75),
		bg = C.BG_SLOT,
		r = 6,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = box
	})
	
	Utils.mkBtn({
		name = "BtnMinus",
		text = "-",
		size = UDim2.new(0, 44, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = C.BG_DARK,
		ts = 20,
		color = C.WHITE,
		r = 6,
		parent = qtyArea
	})
	
	local qtyText = Instance.new("TextBox")
	qtyText.Name = "QtyText"
	qtyText.Text = "1"
	qtyText.Size = UDim2.new(1, -160, 1, 0)
	qtyText.Position = UDim2.new(0, 44, 0, 0)
	qtyText.BackgroundTransparency = 1
	qtyText.TextSize = 20
	qtyText.TextColor3 = C.WHITE
	qtyText.TextXAlignment = Enum.TextXAlignment.Center
	qtyText.TextYAlignment = Enum.TextYAlignment.Center
	qtyText.ClearTextOnFocus = false
	qtyText.Parent = qtyArea
	
	Utils.mkBtn({
		name = "BtnMax",
		text = "MAX",
		size = UDim2.new(0, 72, 1, 0),
		pos = UDim2.new(1, -116, 0, 0),
		bg = C.BTN,
		ts = 14,
		color = C.WHITE,
		r = 6,
		parent = qtyArea
	})
	
	Utils.mkBtn({
		name = "BtnPlus",
		text = "+",
		size = UDim2.new(0, 44, 1, 0),
		pos = UDim2.new(1, -44, 0, 0),
		bg = C.BG_DARK,
		ts = 20,
		color = C.WHITE,
		r = 6,
		parent = qtyArea
	})
	
	Utils.mkLabel({
		name = "PriceText",
		text = "총 0 G",
		size = UDim2.new(1, 0, 0, 24),
		pos = UDim2.new(0, 0, 0, 125),
		ts = 15,
		color = C.GOLD,
		parent = box,
	})
	
	local btnArea = Utils.mkFrame({
		name = "BtnArea",
		size = UDim2.new(1, -40, 0, 40),
		pos = UDim2.new(0, 20, 1, -55),
		bgT = 1,
		parent = box
	})
	
	Utils.mkBtn({
		name = "BtnCancel",
		text = "취소",
		size = UDim2.new(0.48, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = C.BG_DARK,
		ts = 15,
		color = C.WHITE,
		r = 8,
		parent = btnArea
	})
	
	Utils.mkBtn({
		name = "BtnConfirm",
		text = "확인",
		size = UDim2.new(0.48, 0, 1, 0),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BTN,
		ts = 15,
		color = C.WHITE,
		r = 8,
		parent = btnArea
	})
	
	return overlay
end

function ShopUI.Init(parent, UIManager, isMobile)
	ShopUI.IsMobile = isMobile == true

	ShopUI.Refs.Frame = Utils.mkFrame({
		name = "ShopMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 1,
		vis = false,
		parent = parent,
	})

	local main = Utils.mkWindow({
		name = "Main",
		-- Responsive size: wider for desktop, fills screen for mobile
		size = ShopUI.IsMobile and UDim2.new(0.95, 0, 0.95, 0) or UDim2.new(0.85, 0, 0.88, 0),
		maxSize = Vector2.new(1280, 900),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.15,
		r = 12,
		stroke = 2,
		strokeC = C.BORDER,
		ratio = not ShopUI.IsMobile and 1.5 or nil,
		parent = ShopUI.Refs.Frame,
	})
	ShopUI.Refs.Main = main

	local topBarHeight = 78
	local topBar = Utils.mkFrame({
		name = "TopBar",
		size = UDim2.new(1, -32, 0, topBarHeight),
		pos = UDim2.new(0, 16, 0, 12),
		bgT = 1,
		parent = main,
	})

	ShopUI.Refs.Title = Utils.mkLabel({
		text = UILocalizer.Localize("상점"),
		size = UDim2.new(1, -220, 0, 28),
		pos = UDim2.new(0, 0, 0, 0),
		ts = 22,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = topBar,
	})

	ShopUI.Refs.Subtitle = Utils.mkLabel({
		text = UILocalizer.Localize("상점 정보를 확인하세요."),
		size = UDim2.new(1, -220, 0, 36),
		pos = UDim2.new(0, 0, 0, 32),
		ts = ShopUI.IsMobile and 11 or 12,
		color = C.BORDER,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = topBar,
	})

	ShopUI.Refs.GoldLabel = Utils.mkLabel({
		text = "0 G",
		size = UDim2.new(0, 160, 0, 28),
		pos = UDim2.new(1, -48, 0, 0),
		anchor = Vector2.new(1, 0),
		ts = 18,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Right,
		parent = topBar,
	})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		color = C.WHITE,
		ts = 18,
		r = 6,
		fn = function()
			UIManager.closeShop()
		end,
		parent = topBar,
	})

	local content = Utils.mkFrame({
		name = "Content",
		size = UDim2.new(1, -32, 1, -(topBarHeight + 32)),
		pos = UDim2.new(0, 16, 1, -16),
		anchor = Vector2.new(0, 1),
		bgT = 1,
		parent = main,
	})

	local columns = Utils.mkFrame({
		name = "Columns",
		size = UDim2.new(1, 0, 1, 0),
		bgT = 1,
		parent = content,
	})

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, ShopUI.IsMobile and 12 or 16)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = columns

	-- Make sizes responsive relative to their layout mode (always side-by-side)
	local traderSize = UDim2.new(0.48, -8, 1, 0)
	local playerSize = UDim2.new(0.52, -8, 1, 0)

	ShopUI.Refs.TraderPanel, ShopUI.Refs.TraderScroll = makeColumnPanel(columns, "TraderPanel", traderSize, 1)
	ShopUI.Refs.PlayerPanel, ShopUI.Refs.PlayerScroll = makeColumnPanel(columns, "PlayerPanel", playerSize, 2)
	
	-- Quantity Modal overlay
	ShopUI.Refs.QuantityModal = createQuantityModal(ShopUI.Refs.Frame)
end

return ShopUI
