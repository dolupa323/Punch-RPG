-- PremiumShopUI.lua
-- 로벅스 전용 상품(패스, 연금석 등)을 판매하는 전용 상점 UI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))
local InventoryController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("InventoryController"))
local ShopController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("ShopController"))
local ProductConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ProductConfig"))

local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25)
C.BG_DARK = Color3.fromRGB(5, 5, 10)
C.BG_SLOT = Color3.fromRGB(12, 12, 15)
C.GOLD = Color3.fromRGB(255, 255, 255)
C.GOLD_SEL = Color3.fromRGB(40, 80, 160)
C.BORDER = Color3.fromRGB(60, 85, 130)
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN = Color3.fromRGB(40, 80, 160)
C.BTN_H = Color3.fromRGB(60, 100, 180)
C.CARD_BG_TOP = Color3.fromRGB(22, 30, 48)
C.CARD_BG_BOT = Color3.fromRGB(9, 12, 20)
C.ACCENT_ORANGE = Color3.fromRGB(255, 150, 50)
C.ACCENT_CYAN = Color3.fromRGB(80, 210, 255)
local T = Theme.Transp

local ROBUX_ICON = "rbxassetid://109619052878813"

local PremiumShopUI = {}
local UI_MANAGER = nil
local gamePassOwnershipCache = {}
local productPriceCache = {}
local priceLoading = {}
local selectedCategory = "ALL"
PremiumShopUI.Refs = {
	Frame = nil,
	Main = nil,
	Scroll = nil,
	Tabs = {},
}

function PremiumShopUI.SetVisible(visible)
	if PremiumShopUI.Refs.Frame then
		PremiumShopUI.Refs.Frame.Visible = visible
	end
end

local function clearContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "ContentPadding" and child.Name ~= "UIGridLayout" then
			child:Destroy()
		end
	end
end

local function refreshGoldFromServer()
	if not UI_MANAGER or not ShopController or not ShopController.requestGold then
		return
	end

	ShopController.requestGold(function(ok, gold)
		if ok then
			UI_MANAGER.updateGold(gold)
		end
	end)
end

local function getInventoryMaxSlots()
	local _, maxSlots = InventoryController.getSlotInfo()
	return tonumber(maxSlots) or 0
end

local function getGamePassOwnership(gamePassId: number): boolean
	gamePassId = tonumber(gamePassId)
	if not gamePassId then
		return false
	end

	local ok, data = NetClient.Request("GamePass.GetOwnership.Request", { gamePassId = gamePassId })
	if ok and type(data) == "table" then
		local owned = data.owned == true
		gamePassOwnershipCache[gamePassId] = owned
		return owned
	end

	local cached = gamePassOwnershipCache[gamePassId]
	return cached == true
end

local function fetchProductPrice(productId, isGamePass, callback)
	productId = tonumber(productId)
	if not productId then
		callback(nil)
		return
	end

	if productPriceCache[productId] then
		callback(productPriceCache[productId])
		return
	end

	if priceLoading[productId] then
		task.spawn(function()
			while priceLoading[productId] do
				task.wait(0.1)
			end
			callback(productPriceCache[productId])
		end)
		return
	end

	priceLoading[productId] = true
	task.spawn(function()
		local infoType = isGamePass and Enum.InfoType.GamePass or Enum.InfoType.Product
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, infoType)
		end)

		priceLoading[productId] = nil
		if success and info and info.PriceInRobux then
			local priceStr = tostring(info.PriceInRobux) .. " R$"
			productPriceCache[productId] = priceStr
			callback(priceStr)
		else
			warn("[PremiumShopUI] Failed to get product info for ID: " .. tostring(productId))
			callback(nil)
		end
	end)
end

local function resolveProductIcon(data, getItemIcon)
	if type(data) ~= "table" then
		return ""
	end

	local candidates = {}
	local function push(value)
		if type(value) == "string" and value ~= "" then
			table.insert(candidates, value)
		end
	end

	push(data.itemId)
	push(data.iconName)

	for _, candidate in ipairs(candidates) do
		local icon = getItemIcon(candidate)
		if icon and icon ~= "" then
			return icon
		end
	end

	return getItemIcon("Icon_Shop")
end

local function getProductCategory(data): string
	if data.rewardType == "GAMEPASS" then
		return "PASS"
	end
	return "ITEM"
end

local CATEGORY_TABS = {
	{ id = "ALL", name = "전체" },
	{ id = "PASS", name = "패스" },
	{ id = "ITEM", name = "아이템" },
}

--- 카드 하단부에 로벅스 아이콘 + 가격 숫자를 렌더링 (버튼 텍스트 대신 오버레이로 그림)
local function renderPriceContent(hostBtn, productId, priceStr)
	local existing = hostBtn:FindFirstChild("RobuxContent")
	if existing then existing:Destroy() end

	local priceNum = string.match(priceStr, "%d+") or priceStr
	hostBtn.Text = ""

	local content = Instance.new("Frame")
	content.Name = "RobuxContent"
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.Active = false
	content.ZIndex = hostBtn.ZIndex + 5
	content.Parent = hostBtn

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 16, 0, 16)
	icon.BackgroundTransparency = 1
	icon.Active = false
	icon.ZIndex = content.ZIndex + 1
	icon.Image = ROBUX_ICON
	icon.ImageColor3 = Color3.new(1, 1, 1)
	icon.Parent = content

	local textStr = tostring(priceNum)
	local font = Theme.Fonts.TITLE
	local textBounds = TextService:GetTextSize(textStr, 14, font, Vector2.new(1000, 1000))
	local labelWidth = textBounds.X + 4

	Utils.mkLabel({
		text = textStr,
		size = UDim2.new(0, labelWidth, 1, 0),
		ts = 14,
		bold = true,
		color = C.WHITE,
		active = false,
		z = content.ZIndex + 1,
		parent = content,
	})
end

--- 상품 카드 생성 (그리드 레이아웃 셀 하나를 채우는 "판매 카드")
local function makeProductCard(parent: Instance, productId: string, data: any, getItemIcon: any)
	local isInventoryExpand = data.rewardType == "INVENTORY_EXPAND"
	local isGamePass = data.rewardType == "GAMEPASS"
	local isMaxed = isInventoryExpand and getInventoryMaxSlots() >= 120
	local gamePassId = tonumber(data.gamePassId or productId)
	local ownsGamePass = isGamePass and getGamePassOwnership(gamePassId)

	local card = Utils.mkFrame({
		name = "Product_" .. productId,
		size = UDim2.new(1, 0, 1, 0),
		bg = C.CARD_BG_TOP,
		bgT = 0.05,
		r = 14,
		stroke = 1.5,
		strokeC = isGamePass and C.ACCENT_ORANGE or C.BORDER_DIM,
		strokeT = isGamePass and 0.35 or 0.5,
		clips = true,
		parent = parent,
	})

	-- 은은한 세로 그라데이션 (위: 밝은 남색 -> 아래: 어두운 배경)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.CARD_BG_TOP),
		ColorSequenceKeypoint.new(1, C.CARD_BG_BOT),
	})
	grad.Rotation = 90
	grad.Parent = card

	-- 추천 뱃지 (패스류 강조)
	if isGamePass and not ownsGamePass then
		local badge = Utils.mkFrame({
			name = "Badge",
			size = UDim2.new(0, 56, 0, 22),
			pos = UDim2.new(0, 10, 0, 10),
			bg = C.ACCENT_ORANGE,
			bgT = 0,
			r = 6,
			z = 5,
			parent = card,
		})
		Utils.mkLabel({
			text = UILocalizer.Localize("추천"),
			size = UDim2.new(1, 0, 1, 0),
			ts = 12,
			bold = true,
			color = C.BG_PANEL,
			z = 6,
			parent = badge,
		})
	end

	-- 보유중 오버레이 (게임패스를 이미 보유한 경우 카드 전체를 살짝 어둡게)
	if ownsGamePass then
		local ownedTag = Utils.mkFrame({
			name = "OwnedTag",
			size = UDim2.new(0, 68, 0, 22),
			pos = UDim2.new(0, 10, 0, 10),
			bg = Color3.fromRGB(70, 180, 110),
			bgT = 0.1,
			r = 6,
			z = 5,
			parent = card,
		})
		Utils.mkLabel({
			text = UILocalizer.Localize("보유중"),
			size = UDim2.new(1, 0, 1, 0),
			ts = 12,
			bold = true,
			color = C.WHITE,
			z = 6,
			parent = ownedTag,
		})
	end

	-- 아이콘 영역 (은은한 원형 글로우 배경 위에 아이콘)
	local iconArea = Utils.mkFrame({
		name = "IconArea",
		size = UDim2.new(1, 0, 0, 96),
		pos = UDim2.new(0, 0, 0, 0),
		bgT = 1,
		r = false,
		active = false,
		parent = card,
	})

	local glow = Utils.mkFrame({
		name = "Glow",
		size = UDim2.new(0, 88, 0, 88),
		pos = UDim2.new(0.5, 0, 0.5, 2),
		anchor = Vector2.new(0.5, 0.5),
		bg = isGamePass and C.ACCENT_ORANGE or C.ACCENT_CYAN,
		bgT = 0.82,
		r = "full",
		active = false,
		parent = iconArea,
	})

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 60, 0, 60)
	icon.Position = UDim2.new(0.5, 0, 0.5, 2)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = resolveProductIcon(data, getItemIcon)
	icon.ZIndex = 2
	icon.Parent = iconArea

	-- 이름
	Utils.mkLabel({
		text = UILocalizer.Localize(data.name or "상품"),
		size = UDim2.new(1, -20, 0, 20),
		pos = UDim2.new(0, 10, 0, 100),
		ts = 15,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = card,
	})

	-- 설명 (아이템 데이터 또는 상품 설명 사용)
	local itemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
	local desc = data.description or "설명이 없습니다."
	if type(data.itemId) == "string" then
		for _, it in ipairs(itemData) do
			if it.id == data.itemId then
				desc = it.description or desc
				break
			end
		end
	end

	Utils.mkLabel({
		text = UILocalizer.Localize(desc),
		size = UDim2.new(1, -20, 0, 40),
		pos = UDim2.new(0, 10, 0, 122),
		ts = 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		ay = Enum.TextYAlignment.Top,
		wrap = true,
		parent = card,
	})

	-- 구매 버튼 (카드 하단 전체 폭)
	local buttonText = "구매하기"
	if isMaxed then
		buttonText = "구매 불가"
	elseif ownsGamePass then
		buttonText = "보유중"
	end

	local buyBtn = Utils.mkBtn({
		text = UILocalizer.Localize(buttonText),
		size = UDim2.new(1, -16, 0, isMobile and 44 or 36),
		pos = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
		bg = (isMaxed or ownsGamePass) and C.BG_SLOT or C.BTN,
		hbg = (isMaxed or ownsGamePass) and Color3.fromRGB(45, 45, 55) or C.BTN_H,
		color = (isMaxed or ownsGamePass) and C.GRAY or C.WHITE,
		ts = isMobile and 14 or 13,
		font = Theme.Fonts.TITLE,
		r = 9,
		fn = function()
			if isInventoryExpand and getInventoryMaxSlots() >= 120 then
				if UI_MANAGER and UI_MANAGER.notify then
					UI_MANAGER.notify(UILocalizer.Localize("인벤토리 칸이 이미 최대입니다."), C.RED)
				end
				return
			end
			if isGamePass then
				if ownsGamePass then
					if UI_MANAGER and UI_MANAGER.notify then
						UI_MANAGER.notify(UILocalizer.Localize("이미 보유한 패스입니다."), C.GRAY)
					end
					return
				end
				MarketplaceService:PromptGamePassPurchase(game.Players.LocalPlayer, gamePassId)
				return
			end
			MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, tonumber(productId))
		end,
		parent = card,
	})
	buyBtn.Active = not isMaxed and not ownsGamePass
	buyBtn.AutoButtonColor = not isMaxed and not ownsGamePass

	-- 호버 시 카드 테두리가 은은하게 밝아지는 연출
	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	if cardStroke then
		local normalT = cardStroke.Transparency
		buyBtn.MouseEnter:Connect(function()
			TweenService:Create(cardStroke, TweenInfo.new(0.15), { Transparency = math.max(0, normalT - 0.25) }):Play()
		end)
		buyBtn.MouseLeave:Connect(function()
			TweenService:Create(cardStroke, TweenInfo.new(0.15), { Transparency = normalT }):Play()
		end)
	end

	if not isMaxed and not ownsGamePass then
		fetchProductPrice(productId, isGamePass, function(priceStr)
			if priceStr and buyBtn and buyBtn.Parent then
				renderPriceContent(buyBtn, productId, priceStr)
			end
		end)
	end

	return card
end

local function getFilteredProductIds()
	local productIds = {}
	for productId in pairs(ProductConfig.PRODUCTS) do
		table.insert(productIds, productId)
	end
	table.sort(productIds, function(a, b)
		return tonumber(a) < tonumber(b)
	end)

	local result = {}
	for _, productId in ipairs(productIds) do
		local data = ProductConfig.PRODUCTS[productId]
		if data and data.showInPremiumShop ~= false then
			if selectedCategory == "ALL" or getProductCategory(data) == selectedCategory then
				table.insert(result, productId)
			end
		end
	end
	return result
end

local function updateTabVisuals()
	for id, btn in pairs(PremiumShopUI.Refs.Tabs) do
		local isSel = (id == selectedCategory)
		Utils.setBtnState(btn, isSel and C.BTN or C.BG_SLOT, isSel and 0.1 or 0.3)
		btn.TextColor3 = isSel and C.WHITE or C.GRAY
	end
end

function PremiumShopUI.Refresh(getItemIcon)
	if not PremiumShopUI.Refs.Scroll then return end
	clearContainer(PremiumShopUI.Refs.Scroll)
	updateTabVisuals()

	local productIds = getFilteredProductIds()
	for _, productId in ipairs(productIds) do
		local data = ProductConfig.PRODUCTS[productId]
		makeProductCard(PremiumShopUI.Refs.Scroll, productId, data, getItemIcon)
	end
end

function PremiumShopUI.Init(parent, UIManager)
	UI_MANAGER = UIManager
	PremiumShopUI.Refs.Frame = Utils.mkFrame({
		name = "PremiumShop",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 1,
		vis = false,
		parent = parent,
	})

	-- 화면 비율 기반 크기 + 픽셀 최대 크기 제한 (모바일 잘림 방지)
	local main = Utils.mkWindow({
		name = "Main",
		size = isMobile and UDim2.new(0.94, 0, 0.86, 0) or UDim2.new(0, 700, 0, 620),
		maxSize = Vector2.new(700, 640),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 12,
		stroke = 2,
		strokeC = C.BORDER,
		parent = PremiumShopUI.Refs.Frame,
	})
	PremiumShopUI.Refs.Main = main

	-- 헤더
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, -30, 0, 56),
		pos = UDim2.new(0, 15, 0, 10),
		bgT = 1,
		parent = main,
	})

	Utils.mkLabel({
		text = UILocalizer.Localize("상점"),
		size = UDim2.new(1, 0, 0, 30),
		ts = 24,
		bold = true,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	Utils.mkLabel({
		text = UILocalizer.Localize("게임 플레이에 직접 도움이 되는 상품을 구매할 수 있습니다."),
		size = UDim2.new(1, -24, 0, 18),
		pos = UDim2.new(0, 0, 1, -6),
		anchor = Vector2.new(0, 1),
		ts = 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	Utils.mkBtn({
		text = "X",
		size = isMobile and UDim2.new(0, 40, 0, 40) or UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		isNegative = true,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		ts = isMobile and 24 or 22,
		fn = function()
			UIManager.closePremiumShop()
		end,
		parent = header,
	})

	-- 카테고리 탭 (모바일에서는 터치 타겟이 데스크톱보다 작아지지 않도록 더 크게)
	local tabBarH = isMobile and 42 or 34
	local tabBarY = 68
	local tabBar = Utils.mkFrame({
		name = "TabBar",
		size = UDim2.new(1, -30, 0, tabBarH),
		pos = UDim2.new(0, 15, 0, tabBarY),
		bgT = 1,
		parent = main,
	})
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	PremiumShopUI.Refs.Tabs = {}
	for _, tab in ipairs(CATEGORY_TABS) do
		local tabBtn = Utils.mkBtn({
			name = "Tab_" .. tab.id,
			text = UILocalizer.Localize(tab.name),
			size = UDim2.new(0, isMobile and 100 or 84, 1, 0),
			ts = isMobile and 14 or 13,
			font = Theme.Fonts.TITLE,
			r = 8,
			bg = C.BG_SLOT,
			bgT = 0.3,
			color = C.GRAY,
			fn = function()
				selectedCategory = tab.id
				PremiumShopUI.Refresh(UIManager.getItemIcon)
			end,
			parent = tabBar,
		})
		PremiumShopUI.Refs.Tabs[tab.id] = tabBtn
	end

	-- 상품 카드 그리드 영역 (탭 바 높이가 모바일에서 더 크므로 그 아래 시작 위치도 함께 계산)
	local scrollY = tabBarY + tabBarH + 8
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ProductGrid"
	scroll.Size = UDim2.new(1, -30, 1, -(scrollY + 4))
	scroll.Position = UDim2.new(0, 15, 0, scrollY)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.BORDER
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = main

	local columns = isMobile and 2 or 3
	local cardHeight = isMobile and 240 or 228
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.new(0, 12, 0, 12)
	grid.CellSize = UDim2.new(1 / columns, -12 * (columns - 1) / columns, 0, cardHeight)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = scroll

	PremiumShopUI.Refs.Scroll = scroll

	InventoryController.onChanged(function()
		if PremiumShopUI.Refs.Frame and PremiumShopUI.Refs.Frame.Visible then
			PremiumShopUI.Refresh(UIManager.getItemIcon)
		end
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(player, productId, isPurchased)
		if player ~= game.Players.LocalPlayer or not isPurchased then
			return
		end

		task.delay(0.8, refreshGoldFromServer)
		task.delay(2.0, refreshGoldFromServer)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, isPurchased)
		if player ~= game.Players.LocalPlayer or not isPurchased then
			return
		end

		gamePassId = tonumber(gamePassId)
		local isManagedGamePass = false
		for productId, data in pairs(ProductConfig.PRODUCTS) do
			if data.rewardType == "GAMEPASS" and tonumber(data.gamePassId) == gamePassId then
				isManagedGamePass = true
				break
			end
		end

		if isManagedGamePass then
			gamePassOwnershipCache[gamePassId] = nil
			task.spawn(function()
				NetClient.Request("GamePass.RefreshOwnership.Request", { gamePassId = gamePassId })
			end)
			task.delay(0.15, function()
				if PremiumShopUI.Refs.Frame and PremiumShopUI.Refs.Frame.Visible then
					PremiumShopUI.Refresh(UIManager.getItemIcon)
				end
			end)
		end
	end)
end

return PremiumShopUI
