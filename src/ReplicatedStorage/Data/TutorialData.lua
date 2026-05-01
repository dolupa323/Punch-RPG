-- TutorialData.lua
-- 모바일 및 PC 통합 튜토리얼 단계 정의 (Origin:WILD 시스템 반영)

local TutorialData = {}

TutorialData.Steps = {
	{
		id = "STEP_WELCOME",
		message = "Origin:WILD에 오신 것을 환영합니다! 생존을 위한 기초를 배워봅시다.",
		duration = 4,
	},
	{
		id = "STEP_MOVE",
		message = "조이스틱(또는 WASD)을 사용하여 주변을 움직여보세요.",
		condition = "MOVE",
		rewardXP = 20,
	},
	{
		id = "STEP_OPEN_MENU",
		message = "화면 왼쪽 상단의 [메뉴 아이콘] 버튼을 터치(클릭)하세요.",
		condition = "MENU_OPEN",
		targetUI = "MenuButton",
		rewardXP = 10,
	},
	{
		id = "STEP_OPEN_INVENTORY",
		message = "[인벤토리] 아이콘을 눌러 가방을 확인하세요. (PC는 Tab 키)",
		condition = "INVENTORY_OPEN",
		targetUI = "InventoryTabButton",
		rewardItems = { { itemId = "BERRY", count = 5 } },
	},
	{
		id = "STEP_GATHER",
		message = "주변에서 [나뭇가지]와 [돌]을 각각 1개씩 채집하세요. (PC는 R 키 상호작용)",
		condition = "GATHER",
		targets = { BRANCH = 1, STONE = 1 },
		rewardXP = 50,
	},
	{
		id = "STEP_CRAFT",
		message = "[제작] 메뉴에서 [조잡한 돌도끼]를 만드세요.",
		condition = "CRAFT",
		targetRecipe = "CRAFT_CRUDE_STONE_AXE",
		rewardItems = { { itemId = "TORCH", count = 1 } },
	},
	{
		id = "STEP_GATHER_WOOD",
		message = "만든 돌도끼를 핫바(1~8)에서 선택하고, 주변의 나무를 베어 [통나무] 2개를 획득하세요.",
		condition = "GATHER",
		targets = { LOG = 2 },
		rewardXP = 100,
	},
	{
		id = "STEP_BUILD_CAMPFIRE",
		message = "밤을 대비하여 [모닥불]을 건설하세요. (메뉴 -> 건설 -> 기초 -> 모닥불)",
		condition = "BUILD",
		targetFacility = "CAMPFIRE",
		rewardXP = 150,
	},
	{
		id = "STEP_RECOVERY_INFO",
		message = "모닥불 근처에서 [휴식]하거나 음식을 [요리]하여 체력을 회복할 수 있습니다.",
		duration = 6,
	},
	{
		id = "STEP_BUILD_TOTEM",
		message = "이제 안전한 장소를 찾아 [거점 토템]을 건설하세요. 거점이 선언되면 그곳이 당신의 집이 됩니다.",
		condition = "BUILD",
		targetFacility = "CAMP_TOTEM",
		rewardXP = 200,
	},
	{
		id = "STEP_DONE",
		message = "축하합니다! 기초 생존 교육을 마쳤습니다. 이제 자유롭게 탐험하세요!",
		duration = 5,
	}
}

return TutorialData
