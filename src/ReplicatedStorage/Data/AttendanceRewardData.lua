-- AttendanceRewardData.lua
-- 시즌 출석 보상 테이블 (1~28일차, 누적 출석 - 연속 아닐 필요 없음)

local AttendanceRewardData = {}

AttendanceRewardData.SEASON_NAME = "시즌 1: 출석 보상"
AttendanceRewardData.TOTAL_DAYS = 28

-- 각 일차: { gold = number?, items = { {itemId, count} }?, special = boolean? }
-- special = 7/14/21/28일차 등 주요 마일스톤 (UI에서 강조 표시용)
-- [주의] 아이템은 반드시 (a) 실제 판매/제작 경로가 있거나 (b) 실제 게임 로직에서
-- 소비/효과가 확인된 것만 사용한다. ItemData.lua에 정의만 있고 실사용처가 없는
-- 항목(죽은 데이터)은 절대 넣지 않는다. 아래는 이번에 직접 코드에서 확인한 근거:
--   기초 HP 포션(BASIC_HP_POTION) : NPCShopData.MERCHANT.buyList에서 30골드 판매
--   기초 MP 포션(BASIC_MP_POTION) : NPCShopData.MERCHANT.buyList에서 30골드 판매
--   하락방지권("3602118498")       : ProductConfig.PRODUCTS에서 실제 판매 상품 +
--                                    EnhanceService.lua(강화 실패 시 등급 하락 방지 화이트리스트)에서 실사용
-- (2026-07-30: ALCHEMY_STONE_LOW는 드랍/제작 어디에도 정상 경로가 없는 미완성
--  데이터라 제외했었고, "파괴방지권"(3586927381)도 이 게임에는 강화 실패 시
--  "아이템 파괴" 자체가 존재하지 않아 - EnhanceService.lua에 destroy 로직 없음,
--  ProductConfig에도 없는 - 완전히 근거 없는 항목이었음이 확인되어 전면 제외함)
AttendanceRewardData.Days = {
	[1]  = { gold = 100 },
	[2]  = { items = { { itemId = "BASIC_HP_POTION", count = 3 } } },
	[3]  = { gold = 150 },
	[4]  = { items = { { itemId = "BASIC_MP_POTION", count = 3 } } },
	[5]  = { gold = 200 },
	[6]  = { items = { { itemId = "3602118498", count = 1 } } },
	[7]  = { items = { { itemId = "3602118498", count = 3 } }, gold = 100, special = true },
	[8]  = { gold = 250 },
	[9]  = { items = { { itemId = "BASIC_HP_POTION", count = 5 } } },
	[10] = { items = { { itemId = "3602118498", count = 1 } } },
	[11] = { gold = 300 },
	[12] = { items = { { itemId = "BASIC_MP_POTION", count = 5 } } },
	[13] = { gold = 350 },
	[14] = { items = { { itemId = "3602118498", count = 3 } }, gold = 200, special = true },
	[15] = { gold = 400 },
	[16] = { items = { { itemId = "3602118498", count = 2 } } },
	[17] = { items = { { itemId = "BASIC_HP_POTION", count = 8 }, { itemId = "BASIC_MP_POTION", count = 8 } } },
	[18] = { gold = 450 },
	[19] = { items = { { itemId = "3602118498", count = 2 } } },
	[20] = { gold = 500 },
	[21] = { items = { { itemId = "3602118498", count = 5 } }, gold = 300, special = true },
	[22] = { gold = 550 },
	[23] = { items = { { itemId = "3602118498", count = 3 } } },
	[24] = { items = { { itemId = "BASIC_HP_POTION", count = 10 }, { itemId = "BASIC_MP_POTION", count = 10 } } },
	[25] = { gold = 600 },
	[26] = { items = { { itemId = "3602118498", count = 3 } } },
	[27] = { gold = 700 },
	[28] = { gold = 1000, items = { { itemId = "3602118498", count = 10 } }, special = true },
}

function AttendanceRewardData.GetDayReward(day: number)
	return AttendanceRewardData.Days[day]
end

return AttendanceRewardData
