-- DropTableData.lua
-- 크리처 드롭 아이템 데이터 정의
-- ※ 실제 모델이 있는 크리처만 등록

local DropTableData = {
	--========================================
	-- 초식 / PASSIVE
	--========================================
	["ARCHAEOPTERYX"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "FEATHER", chance = 0.8, min = 1, max = 3 },
	},
	["TROODON"] = {
		{ itemId = "MEAT", chance = 0.8, min = 1, max = 1 },
		{ itemId = "SMALL_BONE", chance = 0.6, min = 1, max = 2 },
	},
	["PARASAUR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 3, max = 6 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.7, min = 2, max = 4 },
	},

	--========================================
	-- 초식 / NEUTRAL
	--========================================
	["TRICERATOPS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 8 },
		{ itemId = "DESERT_LEATHER", chance = 1.0, min = 3, max = 5 },
		{ itemId = "HORN", chance = 0.3, min = 1, max = 1 },
	},
	["OLOROTITAN"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "LEATHER", chance = 1.0, min = 1, max = 3 },
	},
	["STEGOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 4, max = 7 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.8, min = 3, max = 5 },
		{ itemId = "BONE", chance = 0.4, min = 1, max = 2 },
	},
	["TITANOSAURUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 10, max = 20 },
		{ itemId = "TITANOSAURUS_LEATHER", chance = 1.0, min = 3, max = 5 },
		{ itemId = "BONE", chance = 1.0, min = 5, max = 10 },
		{ itemId = "IRON_ORE", chance = 0.5, min = 2, max = 4 },
	},

	--========================================
	-- 육식 / AGGRESSIVE
	--========================================
	["RAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 3 },
		{ itemId = "TROPICAL_LEATHER", chance = 0.6, min = 2, max = 3 },
		{ itemId = "BONE", chance = 0.3, min = 1, max = 1 },
		{ itemId = "SHARP_TOOTH", chance = 0.4, min = 1, max = 2 },
	},
	["TREX"] = {
		{ itemId = "MEAT", chance = 1.0, min = 8, max = 15 },
		{ itemId = "BONE", chance = 0.8, min = 3, max = 6 },
		{ itemId = "HORN", chance = 0.4, min = 1, max = 2 },
	},
	["YUTYRANNUS"] = {
		{ itemId = "MEAT", chance = 1.0, min = 5, max = 10 },
		{ itemId = "DESERT_LEATHER", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BONE", chance = 1.0, min = 2, max = 4 },
		{ itemId = "SHARP_TOOTH", chance = 0.8, min = 2, max = 5 },
	},
	["SABERTOOTH"] = {
		{ itemId = "MEAT", chance = 1.0, min = 2, max = 4 },
		{ itemId = "TROPICAL_LEATHER", chance = 1.0, min = 2, max = 3 },
		{ itemId = "SHARP_TOOTH", chance = 1.0, min = 2, max = 2 },
	},
	["GIGANTORAPTOR"] = {
		{ itemId = "MEAT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "LEATHER", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BONE", chance = 0.5, min = 1, max = 1 },
	},

	--========================================
	-- RPG MOBS / NEW
	--========================================
	["SLIME"] = {
		{ itemId = "SLIME_MUCUS", chance = 0.5, min = 1, max = 1 }, -- 50% 확률, 1개씩 드롭되게 패치
		-- 일단 1% 확률은 주석 달아놓고 100%로 작업 (실서비스 반영 시: chance = 0.01)
		{ itemId = "SLIME_EARRING", chance = 0.01, min = 1, max = 1 },
	},
	["DUNGBEETLE"] = {
		-- 일단 1% 확률은 주석 달아놓고 100%로 작업 (실서비스 반영 시: chance = 0.01)
		{ itemId = "DUNG_BEETLE_RING", chance = 0.01, min = 1, max = 1 },
	},
	["FIRELIZARD"] = {
		{ itemId = "FIRE_LIZARD_SCALE", chance = 1.0, min = 2, max = 4 },
		{ itemId = "FIRE_NECKLACE", chance = 0.015, min = 1, max = 1 },
	},
	["VAMPIREWOLF"] = {
		{ itemId = "WOLF_FANG", chance = 1.0, min = 1, max = 2 },
	},
	["SMALLGOLEM"] = {
		{ itemId = "GOLEM_STONE", chance = 1.0, min = 1, max = 3 }, -- 100% 확률로 1~3개 기본 재료 드롭
		-- 희귀 아이템 (실서비스 반영 시 1% 확률 셋팅)
		{ itemId = "GOLEM_RING", chance = 0.01, min = 1, max = 1 },
	},
}

return DropTableData
