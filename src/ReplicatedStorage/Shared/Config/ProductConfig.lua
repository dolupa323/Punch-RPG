-- ProductConfig.lua
-- 개발자 상품(Developer Products) 및 패스 설정

local ProductConfig = {
	--========================================
	-- 연금석 (Alchemy Stones)
	--========================================
	PRODUCTS = {
		["3586867278"] = {
			itemId = "ALCHEMY_STONE_MID",
			amount = 1,
			name = "중급 연금석",
		},
		["3586867473"] = {
			itemId = "ALCHEMY_STONE_HIGH",
			amount = 1,
			name = "상급 연금석",
		},
		-- 방지권 추가
		["3586927112"] = {
			itemId = "3586927112",
			amount = 1,
			name = "하락방지권",
		},
		["3586927381"] = {
			itemId = "3586927381",
			amount = 1,
			name = "파괴방지권",
		},
		["3586927639"] = {
			itemId = "REPAIR_TICKET_HIGH",
			amount = 1,
			name = "상급 수리 키트",
		},
		["3587361918"] = {
			itemId = "3587361918",
			amount = 1,
			name = "스킬초기화권",
		},
		["3587362100"] = {
			itemId = "3587362100",
			amount = 1,
			name = "스텟초기화권",
		},
	}
}

-- 역방향 매핑 (ItemId -> ProductId) - UI에서 구매 팝업 띄울 때 사용
ProductConfig.ITEM_TO_PRODUCT = {}
for productId, data in pairs(ProductConfig.PRODUCTS) do
	ProductConfig.ITEM_TO_PRODUCT[data.itemId] = productId
end

return ProductConfig
