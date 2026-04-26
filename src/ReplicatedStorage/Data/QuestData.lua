-- QuestData.lua
-- 레벨별 퀘스트 풀 데이터

local QuestData = {}

-- 퀘스트 티어 정의 (레벨 기준)
QuestData.Tiers = {
	TUTORIAL = { minLevel = 0, maxLevel = 9 },
	TIER_10  = { minLevel = 10, maxLevel = 19 },
	TIER_20  = { minLevel = 20, maxLevel = 29 },
	TIER_30  = { minLevel = 30, maxLevel = 39 },
	TIER_40  = { minLevel = 40, maxLevel = 100 },
}

QuestData.Quests = {
	-- [TUTORIAL]
	TUTORIAL = {
		{
			id = "TUT_COLLECT_BRANCH",
			title = "나뭇가지 수집",
			desc = "나뭇가지(BRANCH) 5개를 주우십시오.",
			kind = "ITEM_ANY",
			targets = { "BRANCH" },
			count = 5,
			rewardGold = 100,
		},
		{
			id = "TUT_COLLECT_STONE",
			title = "돌 수집",
			desc = "돌(STONE) 3개를 확보하십시오.",
			kind = "ITEM_ANY",
			targets = { "STONE" },
			count = 3,
			rewardGold = 100,
		},
		{
			id = "TUT_CRAFT_CRUDE_AXE",
			title = "기초 도구 제작",
			desc = "조잡한 돌도끼를 제작하십시오.",
			kind = "RECIPE",
			target = "CRAFT_CRUDE_STONE_AXE",
			rewardGold = 150,
		},
		{
			id = "TUT_COLLECT_BERRY",
			title = "식량 확보",
			desc = "야생 베리(BERRY) 5개를 채집하십시오.",
			kind = "ITEM_ANY",
			targets = { "BERRY" },
			count = 5,
			rewardGold = 100,
		},
	},

	-- [10 Tier]
	TIER_10 = {
		{
			id = "T10_COLLECT_PLANK",
			title = "판재 제작",
			desc = "나무를 쪼개 판재(PLANK) 10개를 확보하십시오.",
			kind = "ITEM_ANY",
			targets = { "PLANK" },
			count = 10,
			rewardGold = 300,
		},
		{
			id = "T10_CRAFT_AXE",
			title = "도구 강화",
			desc = "돌도끼를 제작하십시오.",
			kind = "RECIPE",
			target = "CRAFT_FIRM_STONE_AXE",
			rewardGold = 400,
		},
		{
			id = "T10_KILL_ARCHAEO",
			title = "시조새 사냥",
			desc = "시조새(ARCHAEOPTERYX) 3마리를 처치하십시오.",
			kind = "KILL",
			target = "ARCHAEOPTERYX",
			count = 3,
			rewardGold = 500,
		},
		{
			id = "T10_BUILD_STORAGE",
			title = "정리 정돈",
			desc = "보관함(STORAGE_BOX)을 설치하십시오.",
			kind = "BUILD",
			target = "STORAGE_BOX",
			rewardGold = 400,
		},
	},

	-- [20 Tier]
	TIER_20 = {
		{
			id = "T20_COLLECT_BRONZE",
			title = "청동 광석 확보",
			desc = "청동 광석(BRONZE_ORE) 10개를 채굴하십시오.",
			kind = "ITEM_ANY",
			targets = { "BRONZE_ORE" },
			count = 10,
			rewardGold = 800,
		},
		{
			id = "T20_CRAFT_BONE_SWORD",
			title = "뼈검 제작",
			desc = "뼈검(BONE_SWORD)을 제작하십시오.",
			kind = "RECIPE",
			target = "CRAFT_BONE_SWORD",
			rewardGold = 1000,
		},
		{
			id = "T20_KILL_OLORO",
			title = "올로로티탄 사냥",
			desc = "올로로티탄(OLOROTITAN) 1마리를 처치하십시오.",
			kind = "KILL",
			target = "OLOROTITAN",
			rewardGold = 1200,
		},
		{
			id = "T20_BUILD_LARGE_STORAGE",
			title = "대형 보관함 설치",
			desc = "대형 보관함(LARGE_STORAGE_BOX)을 설치하십시오.",
			kind = "BUILD",
			target = "LARGE_STORAGE_BOX",
			rewardGold = 1000,
		},
	},

	-- [30 Tier]
	TIER_30 = {
		{
			id = "T30_COLLECT_IRON",
			title = "철광석 채굴",
			desc = "철광석(IRON_ORE) 15개를 확보하십시오.",
			kind = "ITEM_ANY",
			targets = { "IRON_ORE" },
			count = 15,
			rewardGold = 2000,
		},
		{
			id = "T30_CRAFT_BRONZE_SWORD",
			title = "청동 검 제작",
			desc = "청동 검을 제작하십시오.",
			kind = "RECIPE",
			target = "CRAFT_BRONZE_SWORD",
			rewardGold = 2500,
		},
		{
			id = "T30_KILL_STEGO",
			title = "스테고사우루스 사냥",
			desc = "스테고사우루스 1마리를 처치하십시오.",
			kind = "KILL",
			target = "STEGOSAURUS",
			rewardGold = 3000,
		},
		{
			id = "T30_CRAFT_LEATHER_ARMOR",
			title = "방어구 제작",
			desc = "가죽옷(LEATHER_ARMOR)을 제작하십시오.",
			kind = "RECIPE",
			target = "CRAFT_LEATHER_ARMOR",
			rewardGold = 2800,
		},
	},

	-- [40 Tier]
	TIER_40 = {
		{
			id = "T40_CRAFT_BRONZE_INGOT",
			title = "청동 주괴 대량 생산",
			desc = "청동 주괴 10개를 제련하십시오.",
			kind = "ITEM_ANY",
			targets = { "BRONZE_INGOT" },
			count = 10,
			rewardGold = 5000,
		},
		{
			id = "T40_KILL_ALLOSAUR",
			title = "알로사우루스 사냥",
			desc = "알로사우루스(ALLOSAURUS) 1마리를 처치하십시오.",
			kind = "KILL",
			target = "ALLOSAURUS",
			rewardGold = 7000,
		},
		{
			id = "T40_CRAFT_IRON_AXE",
			title = "철제 도구 제작",
			desc = "철 도끼를 제작하십시오.",
			kind = "RECIPE",
			target = "CRAFT_IRON_AXE",
			rewardGold = 6000,
		},
		{
			id = "T40_KILL_TITANO",
			title = "티타노사우루스 사냥",
			desc = "티타노사우루스(TITANOSAURUS) 1마리를 처치하십시오.",
			kind = "KILL",
			target = "TITANOSAURUS",
			rewardGold = 10000,
		},
	},
}

function QuestData.getTierByLevel(level)
	for tierKey, config in pairs(QuestData.Tiers) do
		if level >= config.minLevel and level <= config.maxLevel then
			return tierKey
		end
	end
	return "TIER_40"
end

return QuestData
