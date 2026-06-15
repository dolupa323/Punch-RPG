-- PremiumShopUI.lua
-- 로벅스 전용 상품(연금석 등)을 판매하는 전용 상점 UI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

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
local T = Theme.Transp

local PremiumShopUI = {}
local UI_MANAGER = nil
local gamePassOwnershipCache = {}
local productPriceCache = {}
local priceLoading = {}
PremiumShopUI.Refs = {
	Frame = nil,
	Main = nil,
	Scroll = nil,
}

function PremiumShopUI.SetVisible(visible)
	if PremiumShopUI.Refs.Frame then
		PremiumShopUI.Refs.Frame.Visible = visible
	end
end

local function clearContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "ContentPadding" and child.Name ~= "UIListLayout" then
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

local function makeProductRow(parent: Instance, productId: string, data: any, getItemIcon: any)
	local rowHeight = 118
	local row = Utils.mkFrame({
		name = "Product_" .. productId,
		size = UDim2.new(1, 0, 0, rowHeight),
		bg = C.BG_DARK,
		bgT = 0.18,
		r = 12,
		stroke = 1.5,
		strokeC = C.BORDER,
		parent = parent,
	})

	local accent = Utils.mkFrame({
		name = "Accent",
		size = UDim2.new(0, 4, 1, -18),
		pos = UDim2.new(0, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.GOLD_SEL,
		bgT = 0.05,
		r = 2,
		parent = row,
	})
	accent.ZIndex = row.ZIndex + 1

	-- 아이콘
	local iconWrap = Utils.mkFrame({
		name = "IconWrap",
		size = UDim2.new(0, 76, 0, 76),
		pos = UDim2.new(0, 28, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_SLOT,
		bgT = 0.08,
		r = 12,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = row,
	})

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0.8, 0, 0.8, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = resolveProductIcon(data, getItemIcon)
	icon.Parent = iconWrap

	-- 이름 및 설명
	local nameLabel = Utils.mkLabel({
		text = UILocalizer.Localize(data.name or "상품"),
		size = UDim2.new(1, -265, 0, 28),
		pos = UDim2.new(0, 118, 0, 12),
		ts = 17,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = row,
	})

	-- 아이템 데이터 또는 상품 설명 사용
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

	local descLabel = Utils.mkLabel({
		text = UILocalizer.Localize(desc),
		size = UDim2.new(1, -275, 0, 48),
		pos = UDim2.new(0, 118, 0, 40),
		ts = 13,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = row,
	})

	-- 구매 버튼 (상품 유형별 분기)
	local isInventoryExpand = data.rewardType == "INVENTORY_EXPAND"
	local isGamePass = data.rewardType == "GAMEPASS"
	local isMaxed = isInventoryExpand and getInventoryMaxSlots() >= 120
	local gamePassId = tonumber(data.gamePassId or productId)
	local ownsGamePass = isGamePass and getGamePassOwnership(gamePassId)
	local buttonText = "구매하기"
	if isMaxed then
		buttonText = "구매 불가"
	elseif ownsGamePass then
		buttonText = "보유중"
	end
	local buyBtn = Utils.mkBtn({
		text = UILocalizer.Localize(buttonText),
		size = UDim2.new(0, 135, 0, 42),
		pos = UDim2.new(1, -18, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = (isMaxed or ownsGamePass) and C.BG_SLOT or C.BTN,
		hbg = (isMaxed or ownsGamePass) and Color3.fromRGB(45, 45, 55) or C.BTN_H,
		color = (isMaxed or ownsGamePass) and C.GRAY or C.WHITE,
		ts = 13,
		font = Theme.Fonts.TITLE,
		r = 10,
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
		parent = row,
	})
	buyBtn.Active = not isMaxed and not ownsGamePass
	buyBtn.AutoButtonColor = not isMaxed and not ownsGamePass

	if not isMaxed and not ownsGamePass then
		fetchProductPrice(productId, isGamePass, function(priceStr)
			if priceStr and buyBtn and buyBtn.Parent then
				local priceNum = string.match(priceStr, "%d+") or priceStr
				buyBtn.Text = ""
				
				-- Row 아래에 이미 존재하는 RobuxContent 삭제
				local existing = buyBtn.Parent:FindFirstChild("RobuxContent_" .. productId)
				if existing then existing:Destroy() end
				
				-- 버튼 영역 바로 위에 투명 오버레이로 마운트하여 렌더링 순서 보장
				local content = Instance.new("Frame")
				content.Name = "RobuxContent_" .. productId
				content.Size = buyBtn.Size
				content.Position = buyBtn.Position
				content.AnchorPoint = buyBtn.AnchorPoint
				content.BackgroundTransparency = 1
				content.Active = false
				content.ZIndex = buyBtn.ZIndex + 5
				content.Parent = buyBtn.Parent
				
				local listLayout = Instance.new("UIListLayout")
				listLayout.FillDirection = Enum.FillDirection.Horizontal
				listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
				listLayout.Padding = UDim.new(0, 5)
				listLayout.Parent = content
				
				local icon = Instance.new("ImageLabel")
				icon.Name = "Icon"
				icon.Size = UDim2.new(0, 18, 0, 18)
				icon.BackgroundTransparency = 1
				icon.Active = false
				icon.ZIndex = content.ZIndex + 1
				icon.Image = "rbxassetid://109619052878813" -- 진짜 로벅스 아이콘 이미지 ID
				icon.ImageColor3 = Color3.new(1, 1, 1) -- 틴트 없이 오리지널 색상 유지
				icon.Parent = content
				
				local textStr = tostring(priceNum)
				local font = Theme.Fonts.TITLE
				local textBounds = game:GetService("TextService"):GetTextSize(textStr, 15, font, Vector2.new(1000, 1000))
				local labelWidth = textBounds.X + 4
				
				local label = Utils.mkLabel({
					text = textStr,
					size = UDim2.new(0, labelWidth, 1, 0),
					ts = 15,
					bold = true,
					color = C.WHITE,
					active = false,
					z = content.ZIndex + 1,
					parent = content,
				})
			end
		end)
	end
	
	-- 로벅스 아이콘 (구매 텍스트 옆에 작게 추가 가능하지만 일단 심플하게 유지)

	return row
end

function PremiumShopUI.Refresh(getItemIcon)
	if not PremiumShopUI.Refs.Scroll then return end
	clearContainer(PremiumShopUI.Refs.Scroll)

	-- ProductConfig에서 상품 목록 가져와서 생성
	local productIds = {}
	for productId in pairs(ProductConfig.PRODUCTS) do
		table.insert(productIds, productId)
	end
	table.sort(productIds, function(a, b)
		return tonumber(a) < tonumber(b)
	end)
	for _, productId in ipairs(productIds) do
		local data = ProductConfig.PRODUCTS[productId]
		if data and data.showInPremiumShop ~= false then
			makeProductRow(PremiumShopUI.Refs.Scroll, productId, data, getItemIcon)
		end
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

	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(0, 560, 0, 660),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 10,
		stroke = 2,
		strokeC = C.BORDER,
		parent = PremiumShopUI.Refs.Frame,
	})
	PremiumShopUI.Refs.Main = main

	-- 헤더
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, -30, 0, 72),
		pos = UDim2.new(0, 15, 0, 10),
		bgT = 1,
		parent = main,
	})

	Utils.mkLabel({
		text = UILocalizer.Localize("상점"),
		size = UDim2.new(1, 0, 1, 0),
		ts = 26,
		bold = true,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Center,
		parent = header,
	})

	Utils.mkLabel({
		text = UILocalizer.Localize("게임 플레이에 직접 도움이 되는 상품을 구매할 수 있습니다."),
		size = UDim2.new(1, -24, 0, 18),
		pos = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
		ts = 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Center,
		parent = header,
	})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		isNegative = true,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		ts = 22,
		fn = function()
			UIManager.closePremiumShop()
		end,
		parent = header,
	})

	-- 상품 리스트 스크롤 영역
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ProductList"
	scroll.Size = UDim2.new(1, -30, 1, -110)
	scroll.Position = UDim2.new(0, 15, 0, 92)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.BORDER
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = main

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 12)
	list.Parent = scroll

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

		if tonumber(gamePassId) == 1864732763 then
			gamePassOwnershipCache[1864732763] = nil
			task.spawn(function()
				NetClient.Request("GamePass.RefreshOwnership.Request", { gamePassId = 1864732763 })
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
