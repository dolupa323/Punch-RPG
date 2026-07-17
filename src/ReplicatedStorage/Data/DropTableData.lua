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
		{ itemId = "SLIME_MUCUS", chance = 1.0, min = 2, max = 3 }, -- 100% 확률, 2~3개 드롭되게 상향
		-- 일단 1% 확률은 주석 달아놓고 100%로 작업 (실서비스 반영 시: chance = 0.01)
		{ itemId = "SLIME_EARRING", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "BOOK_SLIMESHOT", chance = 0.05, min = 1, max = 1 },
	},
	["HORNEDLARVA"] = {
		{ itemId = "HORNED_LARVA_HORN", chance = 1.0, min = 1, max = 2 },
		-- 실서비스 반영 1% 드롭 확률 복원
		{ itemId = "HORNED_LARVA_RING", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
	},
	["STUMP"] = {
		{ itemId = "STUMP_BARK", chance = 1.0, min = 2, max = 4 },
		{ itemId = "STUMP_NECKLACE", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "BOOK_OVERGROWTH", chance = 0.03, min = 1, max = 1 },
	},
	["CYCLOPSBAT"] = {
		{ itemId = "BAT_FANG", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
	},
	["SMALLGOLEM"] = {
		{ itemId = "GOLEM_STONE", chance = 1.0, min = 1, max = 3 }, -- 100% 확률로 1~3개 기본 재료 드롭
		-- 희귀 아이템 (실서비스 반영 시 1% 확률 셋팅)
		{ itemId = "GOLEM_RING", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
	},
	["STUMPKING"] = {
		{ itemId = "WOOD_GOLEM_SOUL", chance = 1.0, min = 50, max = 50 }, -- 확정으로 영혼조각 50개
		{ itemId = "WOOD_GOLEM_EARRING", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "BOOK_OVERGROWTH", chance = 0.03, min = 1, max = 1 },
	},
	["SPIDER"] = {
		{ itemId = "SPIDER_LEG", chance = 1.0, min = 1, max = 3 },
		{ itemId = "SPIDER_NECKLACE", chance = 0.03, min = 1, max = 1 },
	},
	["SAMURAI"] = {
		{ itemId = "BROKEN_SWORD_FRAGMENT", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "BOOK_MAEHWA", chance = 0.03, min = 1, max = 1 },
	},
	["ICEDRAGON"] = {
		{ itemId = "DRAGON_CLAW", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "BOOK_ICEBLADE", chance = 0.01, min = 1, max = 1 },
	},
	["ICEKNIGHT"] = {
		{ itemId = "CHILLING_ICE", chance = 1.0, min = 2, max = 3 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "BOOK_ICEBLADE", chance = 0.01, min = 1, max = 1 },
	},
	["GHOSTKNIGHT"] = {
		{ itemId = "GHOST_KNIGHT_SOUL", chance = 1.0, min = 1, max = 2 },
		{ itemId = "BOOK_SLASH", chance = 0.01, min = 1, max = 1 },
	},
	["GHOSTWIZARD"] = {
		{ itemId = "GHOST_WIZARD_SOUL", chance = 1.0, min = 1, max = 2 },
	},
	["GIANTGHOSTKNIGHT"] = {
		{ itemId = "GHOST_GIANT_PRIDE", chance = 1.0, min = 1, max = 3 },
		{ itemId = "GHOST_KNIGHT_EARRING", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_SWORDFALL", chance = 0.01, min = 1, max = 1 },
	},
	["BLUEFLAMEKNIGHT"] = {
		{ itemId = "BLUE_FIRE", chance = 1.0, min = 1, max = 3 },
		{ itemId = "BLUE_FIRE_RING", chance = 0.03, min = 1, max = 1 },
		{ itemId = "BOOK_BLUEFIREBALL", chance = 0.01, min = 1, max = 1 },
	},
	["DESERTGUARDIAN"] = {
		{ itemId = "BOOK_SLASH", chance = 0.01, min = 1, max = 1 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
	},
	-- [무기 재료] 크라켄 전용 재료아이템(크라켄의 심장) 추가.
	-- [수정] 포세이돈은 더 이상 이 테이블을 재사용하지 않고 아래 별도 ["POSEIDON"] 테이블을 사용함.
	["KRAKEN"] = {
		{ itemId = "COIN", chance = 1.0, min = 500, max = 800 },
		{ itemId = "KRAKEN_HEART", chance = 1.0, min = 2, max = 4 },
		{ itemId = "JELLYFISH_NECKLACE", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_RING", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_PEARL_RING", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_EARRING", chance = 0.001, min = 1, max = 1 },
	},
	-- [심연의 수호자 전용] AbyssGuardianZone은 사막의 수호자와 모델을 재사용하지만 별개의 레이드
	-- 보스이므로, 저레벨 사막 보스(DESERTGUARDIAN)와 드롭테이블을 분리함.
	-- [무기 재료] 심연 수호자 전용 재료아이템(심연 수호자의 결정) 추가.
	["ABYSSGUARDIAN"] = {
		{ itemId = "COIN", chance = 1.0, min = 500, max = 800 },
		{ itemId = "ABYSS_GUARDIAN_STONE", chance = 1.0, min = 3, max = 5 },
		{ itemId = "JELLYFISH_NECKLACE", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_RING", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_PEARL_RING", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_EARRING", chance = 0.001, min = 1, max = 1 },
	},
	-- [포세이돈 전용] 그동안 KRAKEN 테이블을 임시로 재사용하던 것을 분리.
	-- [무기 재료] 포세이돈 전용 재료아이템(포세이돈의 정수) 추가.
	["POSEIDON"] = {
		{ itemId = "COIN", chance = 1.0, min = 500, max = 800 },
		{ itemId = "POSEIDON_ESSENCE", chance = 1.0, min = 4, max = 6 },
		{ itemId = "JELLYFISH_NECKLACE", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_RING", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_PEARL_RING", chance = 0.001, min = 1, max = 1 },
		{ itemId = "JELLYFISH_EARRING", chance = 0.001, min = 1, max = 1 },
	},
	["LAVASLIME"] = {
		{ itemId = "LAVA_SLIME_GEL",    chance = 1.0, min = 2, max = 4 },
		{ itemId = "LAVASLIME_NECKLACE", chance = 0.03, min = 1, max = 1 },
	},
	["FIREMAN"] = {
		{ itemId = "FIREMAN_EMBER",  chance = 1.0, min = 1, max = 3 },
		{ itemId = "BOOK_BLAZE",     chance = 0.01, min = 1, max = 1 },
		{ itemId = "FIREMAN_EARRING", chance = 0.03, min = 1, max = 1 },
	},
	["JELLYFISH"] = {
		{ itemId = "JELLYFISH_TENTACLE", chance = 1.0, min = 1, max = 3 },
		{ itemId = "BOOK_HEAVEN", chance = 0.05, min = 1, max = 1 },
		{ itemId = "JELLYFISH_NECKLACE", chance = 0.0005, min = 1, max = 1 },
		{ itemId = "JELLYFISH_RING", chance = 0.0005, min = 1, max = 1 },
		{ itemId = "JELLYFISH_PEARL_RING", chance = 0.0005, min = 1, max = 1 },
		{ itemId = "JELLYFISH_EARRING", chance = 0.0005, min = 1, max = 1 },
	},
}

return DropTableData


