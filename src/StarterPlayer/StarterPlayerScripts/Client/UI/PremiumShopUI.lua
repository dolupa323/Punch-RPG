-- PremiumShopUI.lua
-- 로벅스 전용 상품(연금석 등)을 판매하는 전용 상점 UI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local ProductConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ProductConfig"))

local C = Theme.Colors
local T = Theme.Transp

local PremiumShopUI = {}
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

local function makeProductRow(parent: Instance, productId: string, data: any, getItemIcon: any)
	local rowHeight = 100
	local row = Utils.mkFrame({
		name = "Product_" .. productId,
		size = UDim2.new(1, 0, 0, rowHeight),
		bg = C.BG_PANEL_L,
		bgT = 0.5,
		r = 10,
		stroke = 1,
		strokeC = C.GOLD, -- 프리미엄 느낌을 위해 금색 테두리
		parent = parent,
	})

	-- 아이콘
	local iconWrap = Utils.mkFrame({
		name = "IconWrap",
		size = UDim2.new(0, 70, 0, 70),
		pos = UDim2.new(0, 15, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_DARK,
		bgT = 0.3,
		r = 8,
		parent = row,
	})

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0.8, 0, 0.8, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = getItemIcon(data.itemId)
	icon.Parent = iconWrap

	-- 이름 및 설명
	local nameLabel = Utils.mkLabel({
		text = UILocalizer.Localize(data.name or "상품"),
		size = UDim2.new(1, -220, 0, 30),
		pos = UDim2.new(0, 100, 0, 15),
		ts = 18,
		bold = true,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = row,
	})

	-- 아이템 데이터에서 설명 가져오기
	local itemData = require(ReplicatedStorage.Data.ItemData)
	local desc = "설명이 없습니다."
	for _, it in ipairs(itemData) do
		if it.id == data.itemId then
			desc = it.description or desc
			break
		end
	end

	local descLabel = Utils.mkLabel({
		text = UILocalizer.Localize(desc),
		size = UDim2.new(1, -220, 0, 40),
		pos = UDim2.new(0, 100, 0, 45),
		ts = 13,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = row,
	})

	-- 구매 버튼 (로벅스 아이콘 포함)
	local buyBtn = Utils.mkBtn({
		text = "구매",
		size = UDim2.new(0, 100, 0, 40),
		pos = UDim2.new(1, -15, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = Color3.fromRGB(0, 162, 255), -- 로블록스 블루
		ts = 16,
		r = 8,
		fn = function()
			MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, tonumber(productId))
		end,
		parent = row,
	})
	
	-- 로벅스 아이콘 (구매 텍스트 옆에 작게 추가 가능하지만 일단 심플하게 유지)

	return row
end

function PremiumShopUI.Refresh(getItemIcon)
	if not PremiumShopUI.Refs.Scroll then return end
	clearContainer(PremiumShopUI.Refs.Scroll)

	-- ProductConfig에서 상품 목록 가져와서 생성
	for productId, data in pairs(ProductConfig.PRODUCTS) do
		makeProductRow(PremiumShopUI.Refs.Scroll, productId, data, getItemIcon)
	end
end

function PremiumShopUI.Init(parent, UIManager)
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
		size = UDim2.new(0, 500, 0, 600),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 10,
		stroke = 2,
		strokeC = C.GOLD, -- 상점의 특별함을 위해 금색 테두리
		parent = PremiumShopUI.Refs.Frame,
	})
	PremiumShopUI.Refs.Main = main

	-- 헤더
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, -30, 0, 60),
		pos = UDim2.new(0, 15, 0, 10),
		bgT = 1,
		parent = main,
	})

	Utils.mkLabel({
		text = "상점",
		size = UDim2.new(1, 0, 1, 0),
		ts = 28,
		bold = true,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Center,
		parent = header,
	})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bgT = 1,
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
	scroll.Size = UDim2.new(1, -30, 1, -90)
	scroll.Position = UDim2.new(0, 15, 0, 75)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = main

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = scroll

	PremiumShopUI.Refs.Scroll = scroll
end

return PremiumShopUI
