-- ProductConfig.lua
-- 개발자 상품(Developer Products) 및 패스 설정

local ProductConfig = {
	PRODUCTS = {
		["1864732763"] = {
			name = "드랍률 2배 패스",
			description = "몬스터 처치 보상 드롭률이 영구적으로 2배 증가합니다.",
			rewardType = "GAMEPASS",
			gamePassId = 1864732763,
			iconName = "Icon_Shop",
		},
		["3602119011"] = {
			name = "초보자 스타터 팩",
			description = "일정 레벨 이하에서만 구매할 수 있는 초보자 지원 팩입니다.",
			rewardType = "STARTER_PACK",
			itemId = "STARTER_PACK_BOX",
			amount = 1,
			levelThreshold = 5,
			iconName = "Icon_StarterPack",
			showInPremiumShop = false,
		},
		["3602118667"] = {
			name = "인벤토리 확장권",
			description = "인벤토리 최대 칸 수가 30칸 증가합니다.",
			rewardType = "INVENTORY_EXPAND",
			slots = 30,
			iconName = "Icon_InventoryExpand",
		},
		["3602118498"] = {
			name = "하락 방지권",
			description = "강화 실패 시 등급 하락을 막아주는 주문서입니다.",
			rewardType = "ITEM",
			itemId = "3602118498",
			amount = 1,
			iconName = "ProtectScroll_Down",
		},
		["3602277334"] = {
			name = "하락 방지권 10개",
			description = "강화 실패 시 등급 하락을 막아주는 주문서 10개가 지급됩니다.",
			rewardType = "ITEM",
			itemId = "3602118498",
			amount = 10,
			iconName = "ProtectScroll_Down",
		},
		["3602118281"] = {
			name = "100Gold",
			description = "골드 100이 지급됩니다.",
			rewardType = "GOLD",
			amount = 100,
			iconName = "Icon_Gold",
		},
		["3602118136"] = {
			name = "1000Gold",
			description = "골드 1000이 지급됩니다.",
			rewardType = "GOLD",
			amount = 1000,
			iconName = "Icon_Gold",
		},
		["3602616787"] = {
			name = "제작 즉시 완료",
			description = "진행 중인 제작 작업을 즉시 완료합니다.",
			rewardType = "CRAFT_SPEEDUP",
			iconName = "Icon_Speedup",
			showInPremiumShop = false,
		},
	}
}

-- 역방향 매핑 (ItemId -> ProductId) - UI에서 구매 팝업 띄울 때 사용
ProductConfig.ITEM_TO_PRODUCT = {}
local orderedProductIds = {}
for productId in pairs(ProductConfig.PRODUCTS) do
	table.insert(orderedProductIds, productId)
end
table.sort(orderedProductIds, function(a, b)
	return tonumber(a) < tonumber(b)
end)
for _, productId in ipairs(orderedProductIds) do
	local data = ProductConfig.PRODUCTS[productId]
	if data and data.itemId and not ProductConfig.ITEM_TO_PRODUCT[data.itemId] then
		ProductConfig.ITEM_TO_PRODUCT[data.itemId] = productId
	end
end

return ProductConfig
