-- Balance.lua
-- 게임 밸런스 상수 (동결 - 단일 진실)
-- 이 파일의 값만 참조할 것. 매직 넘버 금지.

local Balance = {}

--========================================
-- 시간 시스템
--========================================
Balance.DAY_LENGTH = 960           -- 하루 총 길이 (초, 16분)
Balance.DAY_DURATION = 640         -- 낮 지속 시간 (초, 10.67분)
Balance.NIGHT_DURATION = 320       -- 밤 지속 시간 (초, 5.33분)

--========================================
-- 인벤토리
--========================================
Balance.INV_SLOTS = 60             -- 기본 인벤토리 슬롯 수
Balance.MAX_STACK = 99             -- 최대 스택 수량

--========================================
-- 창고 (Storage)
--========================================
Balance.STORAGE_SLOTS = 20         -- 창고 슬롯 수 (INV_SLOTS와 동일)

--========================================
-- 월드 드롭
--========================================
Balance.DROP_CAP = 400             -- 서버 전체 드롭 아이템 최대 개수
Balance.DROP_MERGE_RADIUS = 5      -- 드롭 병합 반경 (스터드)
Balance.DROP_INACTIVE_DIST = 150   -- 비활성화 거리 (스터드)
Balance.DROP_DESPAWN_DEFAULT = 300 -- 기본 디스폰 시간 (초)
Balance.DROP_DESPAWN_GATHER = 600  -- 채집 드롭 디스폰 시간 (초)
Balance.DROP_LOOT_RANGE = 14       -- [상향] 루팅 최대 거리 (10 -> 14)

--========================================
-- 월드 / 맵 설정
--========================================
Balance.MAP_EXTENT = 2500          -- 초기 스폰 시 탐색할 맵 최대 범위 (스터드, 1500 -> 2500)
Balance.SEA_LEVEL = 2              -- 해수면 높이 (0 -> 2)

--========================================
-- 카메라 (Camera)
--========================================
Balance.CAM_MAX_ZOOM = 45          -- 줌아웃 최대 거리 (스터드)
Balance.CAM_MIN_ZOOM = 0           -- 줌인 최소 거리 (1인칭 허용)

--========================================
-- 야생동물 / 크리처
--========================================
Balance.WILDLIFE_CAP = 400         -- 서버 전체 야생동물 최대 수
Balance.CREATURE_COOLDOWN = 600    -- 크리처 리스폰 쿨다운 (초)
Balance.INITIAL_CREATURE_COUNT = 160 -- 서버 시작 시 초기 스폰 크리처 수 (Zone당 80마리)
Balance.CREATURE_REPLENISH_INTERVAL = 60 -- 보충 스폰 간격 (초) (45 -> 60)

--========================================
-- 자원 노드 (Resource Nodes)
--========================================
Balance.RESOURCE_NODE_CAP = 600    -- 서버 전체 자원 노드 최대 수
Balance.NODE_SPAWN_INTERVAL = 12   -- 자원 노드 보충 스폰 간격 (초)
Balance.NODE_DESPAWN_DIST = 500    -- 자원 노드 디스폰 거리 (멀리서도 유지)
Balance.INITIAL_NODE_COUNT = 400   -- 서버 시작 시 초기 스폰 노드 수

--========================================
-- 시설
--========================================
Balance.FACILITY_QUEUE_MAX = 10    -- 시설 대기열 최대 크기
Balance.FACILITY_ACTIVE_CAP = 15   -- 동시 활성 시설 최대 수
Balance.MAX_FACILITY_OUTPUT = 1000 -- 시설 Output 슬롯 최대 아이템 개수
Balance.FACILITY_WORK_HP_LOSS = 0.1   -- 작업 1회당 시설 내구도 소모
Balance.FACILITY_PASSIVE_DECAY_TICK = 5 -- 시설 자연 내구도 감소 적용 주기(초)

--========================================
-- 건축 (Build)
--========================================
Balance.BUILD_STRUCTURE_CAP = 500    -- 서버 전체 구조물 최대 수
Balance.BUILD_RANGE = 30             -- 플레이어 건축 가능 거리 (스터드)
Balance.BUILD_MIN_GROUND_DIST = 0.5  -- 지면 최소 거리 (스터드)
Balance.BUILD_COLLISION_RADIUS = 2   -- 기본 충돌 체크 반경 (스터드)
Balance.BUILD_PLACEMENT_PROFILE = "DEFAULT" -- DEFAULT | STRICT_FIELD
Balance.BUILD_MAX_GROUND_SLOPE_DEG = 42      -- 일반 공간의 허용 경사
Balance.BUILD_STRICT_MAX_GROUND_SLOPE_DEG = 12 -- 엄격 모드 허용 경사
Balance.BUILD_MAX_GROUND_GAP = 3.5           -- 일반 공간 지면 오차 허용
Balance.BUILD_STRICT_MAX_GROUND_GAP = 1.2    -- 엄격 모드 지면 오차 허용
Balance.BLOCK_GRID_SIZE = 4                  -- 블럭 건축 그리드 크기
Balance.BLOCK_BUILD_RANGE = 35               -- 블럭 건축 가능 거리
Balance.BLOCK_STRUCTURE_CAP = 3000           -- 서버 전체 블럭 최대 개수

--========================================
-- 제작 (Craft)
--========================================
Balance.CRAFT_RANGE = 10               -- 시설 제작 가능 거리 (스터드)
Balance.CRAFT_QUEUE_MAX = 5            -- 플레이어 동시 제작 큐 최대 크기
Balance.CRAFT_CANCEL_REFUND = 1.0      -- 취소 시 재료 환불 비율 (1.0 = 전액)

--========================================
-- 플레이어 레벨 & 경험치 (Phase 6)
--========================================
Balance.PLAYER_MAX_LEVEL = 100         -- 최대 레벨 (50->100 확장. 50레벨 이후 곡선은 PlayerStatService의
                                        -- _computeLevelXPRequirement 참고 - 지수 증가를 그대로 이어가면
                                        -- 폭증하므로 50레벨 이후는 완만한 선형 증가로 전환됨)
Balance.BASE_XP_PER_LEVEL = 100        -- 레벨 1→2 필요 XP
Balance.XP_SCALING = 1.2               -- 레벨당 필요 XP 증가율
Balance.STAT_POINTS_PER_LEVEL = 3      -- 레벨업당 스탯 포인트 지급
Balance.SKILL_POINTS_PER_LEVEL = 1      -- 레벨업당 스킬 포인트 지급

-- [튜토리얼 라인 레벨 반감 방지] 슬라임(Lv3)→뿔애벌레(Lv7)→스텀프(Lv12)→스텀프킹(Lv18)
-- 순서로 이어지는 튜토리얼 초반 구간에서, 정상 경험치 곡선(지수 증가)을 그대로 적용하면
-- 스텀프킹을 만날 시점에 플레이어 레벨이 한참 못 미쳐 레벨반감(AvatarService의 몹 레벨차 데미지
-- 감소) 페널티에 걸리게 됨. 이를 막기 위해 레벨 20 미만 구간만 요구 경험치를 대폭 할인해
-- 자연스러운 사냥만으로도 스텀프킹 시점엔 레벨 18~20에 도달하도록 함.
-- 사무라이(Lv23)부터는 정상(할인 없는) 곡선으로 복귀 - 이 지점부터 다시 어려워지는 것은 의도된 것.
Balance.TUTORIAL_XP_LEVEL_CAP = 20      -- 이 레벨 미만(1~19) 구간까지만 할인 적용
Balance.TUTORIAL_XP_DISCOUNT = 0.35     -- 할인 배율 (요구 경험치를 35%로 감소)

--========================================
-- XP 획득량 (Phase 6)
--========================================
Balance.XP_CREATURE_KILL = 100           -- 크리처 처치
Balance.XP_CRAFT_ITEM = 20              -- 아이템 제작

--========================================
-- 플레이어 스탯 보너스 (Phase 6)
--========================================
Balance.HP_PER_POINT = 1               -- 포인트당 체력 증가
Balance.STAMINA_PER_POINT = 2          -- 포인트당 스태미너 증가
Balance.SLOTS_PER_POINT = 5            -- 포인트당 인벤토리 칸 증가
Balance.BASE_INV_SLOTS = 60            -- 기본 인벤토리 칸 수
Balance.MAX_INV_SLOTS = 120            -- 최대 인벤토리 칸 수
Balance.ATTACK_PER_POINT = 0.02        -- 포인트당 공격력 증가

--========================================
-- 스태미나 & 이동 시스템 (Phase 10)
--========================================
Balance.STAMINA_MAX = 100              -- 최대 스태미나
Balance.STAMINA_REGEN = 10             -- 초당 스태미나 회복량
Balance.STAMINA_REGEN_DELAY = 0.8      -- 회복 시작 딜레이

-- 스프린트 (빠르게 달리기)
Balance.SPRINT_SPEED_MULT = 1.50       -- 스프린트 속도 배율
Balance.SPRINT_STAMINA_COST = 18       -- 초당 스태미나 소모
Balance.SPRINT_MIN_STAMINA = 5         -- 스프린트 시작 최소 스태미나

-- 구르기 (회피)
Balance.DODGE_STAMINA_COST = 25        -- 구르기 1회 스태미나 소모
Balance.DODGE_COOLDOWN = 1.2           -- 구르기 쿨타임
Balance.DODGE_DISTANCE = 12            -- 구르기 이동 거리
Balance.DODGE_DURATION = 0.4           -- 구르기 소요 시간
Balance.DODGE_IFRAMES = 0.35           -- 무적 프레임 지속 시간

--========================================
-- 코드 제어 이동 능력
--========================================
Balance.MOVEMENT_JUMP_HEIGHT = 7            -- 기본 점프 높이
Balance.MOVEMENT_JUMP_COYOTE_TIME = 0.12    -- 점프 코요테 타임
Balance.MOVEMENT_DOUBLE_JUMP_HEIGHT = 9.5   -- 이단점프 높이
Balance.MOVEMENT_SUPER_JUMP_HEIGHT = 14      -- 슈퍼점프 높이
Balance.MOVEMENT_DASH_SPEED = 90             -- 대쉬 속도
Balance.MOVEMENT_DASH_DURATION = 0.22        -- 대쉬 지속 시간
Balance.MOVEMENT_DASH_COOLDOWN = 0.7         -- 대쉬 쿨다운
Balance.MOVEMENT_DASH_STAMINA_COST = 20       -- 대쉬 스태미나 소모
Balance.MOVEMENT_DOUBLE_JUMP_STAMINA_COST = 15 -- 이단점프 스태미나 소모
Balance.MOVEMENT_SUPER_JUMP_STAMINA_COST = 25  -- 슈퍼점프 스태미나 소모
Balance.MOVEMENT_HIT_REACTION_FORCE = 32       -- 피격 반응 넉백 강도
Balance.MOVEMENT_HIT_REACTION_UPWARD = 10      -- 피격 반응 상향 힘
Balance.MOVEMENT_HIT_REACTION_DURATION = 0.18  -- 피격 반응 지속 시간
Balance.MOVEMENT_HIT_STUN_TIME = 0.25          -- 피격 경직 시간

--========================================
-- 수확 및 공격 판정 (Phase 7)
--========================================
Balance.HARVEST_COOLDOWN = 0.4         -- 연속 타격 쿨다운
Balance.HARVEST_RANGE = 12             -- 기본 수확 거리
Balance.COMBAT_HITBOX_SIZE = 10        -- 기본 공격 판정 반경

-- 도구별 사거리 (Reach)
Balance.REACH_BAREHAND = 12             -- 맨손
Balance.REACH_TOOL = 14               -- 도구
Balance.REACH_SWORD = 16               -- 검
Balance.REACH_ANGLE = 75               -- 공격 인정 각도

--========================================
-- 🛠️ 범용 RPG 템플릿 마스터 피처 토글 (Feature Toggles)
--========================================
Balance.ENABLE_SURVIVAL_STATS   = false  -- Hunger/Stamina 허기 및 스태미나 지속 감쇠 작동 스위치
Balance.ENABLE_BUILD_SYSTEM     = false  -- 제작대, 상자 등 거점 건축 시스템 활성화 스위치
Balance.ENABLE_DURABILITY_DECAY = true   -- 도구 및 장비 타격 시 내구도 감소 소모 여부 스위치
Balance.ENABLE_SHOP_SYSTEM      = true   -- 골드 기반 상인 거래 경제 시스템 활성화 스위치

Balance.HEALTH_REGEN_RATE = 0.001       -- 초당 체력 회복 비율

-- 귀환 관련
Balance.RECALL_CAST_TIME = 5           -- 귀환 시전 시간(초)
Balance.RECALL_COOLDOWN = 60           -- 귀환 쿨다운(초)
Balance.REST_HEAL_RATE = 5             -- 휴식 시 초당 체력 회복량
Balance.REST_STAMINA_REGEN_RATE = 15   -- 휴식 시 초당 기력 추가 회복량

-- 채집 홀드 시스템 (E키 꿉 누르기)
Balance.HARVEST_HOLD_TIME_BASE = 2.0   -- 기본 채집 시간
Balance.HARVEST_HOLD_TIME_OPTIMAL = 0.8 -- 최적 도구 사용 시 채집 시간
Balance.HARVEST_EFFICIENCY_BAREHAND = 0.5 -- 맨손 효율
Balance.HARVEST_EFFICIENCY_WRONG_TOOL = 0.7 -- 맞지 않는 도구 효율
Balance.HARVEST_EFFICIENCY_OPTIMAL = 1.2 -- 최적 도구 효율
Balance.HARVEST_BAREHAND_HP_PENALTY = 2 -- 맨손 패널티

--========================================
-- 베이스 시스템 (Phase 7)
--========================================
Balance.BASE_DEFAULT_RADIUS = 30       -- 기본 베이스 반경
Balance.BASE_MAX_RADIUS = 60           -- 최대 베이스 반경
Balance.BASE_RADIUS_PER_LEVEL = 10     -- 레벨당 추가 반경
Balance.BASE_MAX_PER_PLAYER = 1        -- 플레이어당 최대 베이스 수
Balance.TOTEM_UPKEEP_COST_1D = 100       -- 1일 유지비
Balance.TOTEM_INITIAL_GRACE_SECONDS = 86400 -- 토템 첫 설치 무료 유지시간
Balance.TOTEM_PROXIMITY_SHOW_RANGE = 65  -- 토템 범위 프리뷰 노출 거리
Balance.STARTER_PROTECTION_RADIUS = 45   -- 초보자 스폰 보호존 반경
Balance.QUEST_DAILY_RESET_HOUR = 0     -- 일일 퀘스트 리셋 시간 (UTC)
Balance.QUEST_ABANDON_COOLDOWN = 60    -- 퀘스트 포기 후 재수락 쿨다운 (초)

--========================================
-- NPC 상점 시스템 (Phase 9)
--========================================
Balance.SHOP_INTERACT_RANGE = 10       -- NPC 상점 상호작용 최대 거리 (스터드)
Balance.SHOP_DEFAULT_SELL_MULT = 0.5   -- 기본 판매 배율 (구매가의 50%)
Balance.SHOP_RESTOCK_TIME = 300        -- 재고 리필 시간 (초)
Balance.STARTING_GOLD = 100            -- 신규 플레이어 기본 골드
Balance.GOLD_CAP = 100000000              -- 최대 보유 가능 골드
Balance.GOLD_EARN_MULTIPLIER = 1.0     -- 골드 획득 배율 (이벤트용)

--========================================
-- 1:1 거래 시스템
--========================================
Balance.TRADE_INTERACT_RANGE = 12      -- 거래 요청 가능 최대 거리 (스터드)
Balance.TRADE_INVITE_TIMEOUT = 20      -- 거래 요청 자동 만료 시간 (초)

-- 테이블 동결 (런타임 수정 방지)
Balance.ARMOR_DURABILITY_LOSS_RATIO = 0.1 -- 피격 시 방어구 내구도 감소 비율
Balance.KNOCKBACK_FORCE = 25               -- 피격 시 기본 넉백 강도 (플레이어)
Balance.CREATURE_KNOCKBACK_FORCE = 12      -- 크리처 피격 넉백 강도
Balance.DAMAGE_VARIANCE = 0.15             -- 데미지 등락폭 (±15%)

Balance.PACK_AGGRO_RADIUS = 50             -- 주변 동족 어그로 반경
Balance.DROP_BILLBOARD_MAX_DIST = 25       -- 드롭 라벨 최대 거리
Balance.DROP_PROMPT_RANGE = 5              -- 드롭 루팅 거리
Balance.DROP_MODEL_DEFAULT = "POUCH"       -- 드롭 아이템 기본 모델

Balance.BASE_WALK_SPEED = 24               -- 플레이어 기본 이동 속도
Balance.CREATURE_AI_TICK = 0.3             -- 크리처 AI 업데이트 간격
Balance.CREATURE_DESPAWN_DIST = 300        -- 크리처 디스폰 거리

--========================================
-- 어드민 / 개발자 설정
--========================================
Balance.ADMIN_IDS = {
	[game.CreatorId] = true,
	[10311679477] = true, -- 메인 관리자
	[331908682] = true,   -- 보조 관리자
}

table.freeze(Balance)

return Balance
