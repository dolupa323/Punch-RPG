-- NPCShopData.lua
-- NPC 상점 데이터 정의 (Phase 9)
-- 4단계 아이템 체계 반영 및 오타 수정

local NPCShopData = {}

--========================================
-- 잡화점 (General Store)
--========================================
NPCShopData.GENERAL_STORE = {
	id = "GENERAL_STORE",
	name = "잡화점",
	description = "기본 물품을 판매하는 상점입니다.",
	npcName = "상인 톰",
	
	-- 이 상점은 모든 아이템을 매입하지만, 무기와 방어구(악세서리)는 제외합니다.
	acceptAllItems = true,
	denySellTypes = {"WEAPON", "ARMOR"},
	
	-- 판매 상품 (플레이어가 구매 가능)
	buyList = {
		{ itemId = "WOOD", price = 5, stock = -1 },
		{ itemId = "STONE", price = 3, stock = -1 },
		{ itemId = "FIBER", price = 2, stock = -1 },
		{ itemId = "TORCH", price = 15, stock = 50 },
		{ itemId = "RESIN", price = 10, stock = -1 },
	},
	
	-- 특수 구매 목록 (플레이어가 상점에 팔 수 있는 아이템 - 고정 가격 우선 적용)
	sellList = {
		{ itemId = "WOOD", price = 2 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "FIBER", price = 1 },
		{ itemId = "MEAT", price = 8 },       -- RAW_MEAT -> MEAT 수정
		{ itemId = "LEATHER", price = 15 },
		{ itemId = "BONE", price = 10 },
		{ itemId = "HORN", price = 25 },
	},
}

--========================================
-- 도구점 (Tool Shop)
--========================================
NPCShopData.TOOL_SHOP = {
	id = "TOOL_SHOP",
	name = "도구점",
	description = "각종 도구와 무기를 판매합니다.",
	npcName = "대장장이 한스",
	
	buyList = {
		{ itemId = "FIRM_STONE_PICKAXE", price = 50, stock = -1 },
		{ itemId = "FIRM_STONE_AXE", price = 50, stock = -1 },
		{ itemId = "WOODEN_CLUB", price = 40, stock = -1 },
		{ itemId = "BRONZE_PICKAXE", price = 250, stock = 10 },
		{ itemId = "BRONZE_AXE", price = 250, stock = 10 },
	},
	

	sellList = {
		{ itemId = "FIRM_STONE_PICKAXE", price = 15 },
		{ itemId = "FIRM_STONE_AXE", price = 15 },
		{ itemId = "BRONZE_PICKAXE", price = 75 },
		{ itemId = "IRON_PICKAXE", price = 200 },
	},
}


--========================================
-- 식료품점 (Food Shop)
--========================================
NPCShopData.FOOD_SHOP = {
	id = "FOOD_SHOP",
	name = "식료품점",
	description = "음식과 물약을 판매합니다.",
	npcName = "요리사 루시",
	
	buyList = {
		{ itemId = "BERRY", price = 5, stock = -1 },
	},
	

	sellList = {
		{ itemId = "MEAT", price = 10 },
		{ itemId = "BERRY", price = 2 },
	},
}

--========================================
-- 건축 상점 (Building Shop)
--========================================
NPCShopData.BUILDING_SHOP = {
	id = "BUILDING_SHOP",
	name = "건축 상점",
	description = "건축 재료와 설계도를 판매합니다.",
	npcName = "건축가 벤",
	
	buyList = {
		{ itemId = "WOOD", price = 4, stock = -1 },
		{ itemId = "STONE", price = 2, stock = -1 },
		{ itemId = "FIBER", price = 2, stock = -1 },
	},
	

	sellList = {
		{ itemId = "WOOD", price = 1 },
		{ itemId = "STONE", price = 1 },
		{ itemId = "FIBER", price = 1 },
	},
}

--========================================
-- 잡화상 (General Merchant)
--========================================
NPCShopData.MERCHANT = {
	id = "MERCHANT",
	name = "잡화상",
	description = "각종 전리품과 재료를 매입하며, 유용한 잡화를 판매합니다.",
	npcName = "잡화상",
	
	-- 이 상점은 모든 아이템을 매입하지만, 무기와 방어구(악세서리)는 제외합니다.
	acceptAllItems = true,
	denySellTypes = {"WEAPON", "ARMOR"},
	
	buyList = {
		{ itemId = "BASIC_HP_POTION", price = 30, stock = -1 },
		{ itemId = "BASIC_MP_POTION", price = 30, stock = -1 },
	},
	
	sellList = {
		{ itemId = "EMBER", price = 300 }, -- 불씨
		{ itemId = "DROPLET", price = 300 }, -- 물방울
		{ itemId = "NIGHT", price = 300 }, -- 짙은 밤
		
		-- 하늘섬 아이템류
		{ itemId = "GHOST_KNIGHT_SOUL", price = 120 }, -- 기사의 혼
		{ itemId = "GHOST_WIZARD_SOUL", price = 120 }, -- 마법사의 혼
		{ itemId = "GHOST_GIANT_PRIDE", price = 300 }, -- 기사의 긍지 (RARE, so higher than 120)
		{ itemId = "BLUE_FIRE", price = 1200 }, -- 푸른 화염
	},
}

return NPCShopData
