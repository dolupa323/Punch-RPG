# 🎯 Origin-WILD 미완성 작업 목록 (실행 가능 문서)

> **작성일**: 2026-03-12  
> **작성자**: AI Review  
> **목적**: 현재 미완성된 모든 작업을 명확하게 정리하여 즉시 구현 가능하도록 작성

---

## 📋 상태 요약

| 카테고리                   | 상태         | 진행률 | 우선순위 |
| -------------------------- | ------------ | ------ | -------- |
| **서버 인프라**            | ✅ 완료      | 100%   | -        |
| **Phase 1-4**              | ✅ 완료      | 100%   | -        |
| **Phase 5 (팰 시스템)**    | ✅ 완료      | 100%   | -        |
| **Phase 6 (기술 트리)**    | ✅ 완료      | 100%   | -        |
| **Phase 7 (자동화)**       | ✅ 완료      | 100%   | -        |
| **튜토리얼 퀨스트 (간단)** | ❌ 미구현    | 0%     | 🔴 높음  |
| **Phase 9 (NPC 상점)**     | ⚠️ 부분 완료 | 80%    | 🟡 중간  |
| **클라이언트 UI**          | ⚠️ 부분 완료 | 70%    | 🟡 중간  |
| **NPC 상호작용**           | ⚠️ 부분 완료 | 20%    | 🟡 중간  |

---

## 🔴 우선순위 1: Phase 8 퀘스트 시스템 (완전 미구현)

### ❌ 서버 구현 필요

#### 1.1 `QuestData.lua` 데이터 파일 생성

**경로**: `src/ReplicatedStorage/Data/QuestData.lua`

**구현 내용**: 퀘스트 정의 데이터 테이블

```lua
-- 최소 10개의 기본 퀘스트 정의 필요
local QuestData = {
  -- [1] 튜토리얼
  {
    id = "QUEST_FIRST_HARVEST",
    name = "첫 수확",
    description = "나무를 3번 수확하세요",
    category = "TUTORIAL",
    prerequisites = {},
    requiredLevel = 1,
    objectives = {
      {
        type = "HARVEST",
        targetId = "TREE",
        count = 3,
      }
    },
    rewards = {
      xp = 50,
      techPoints = 0,
      items = {
        { itemId = "WOOD", count = 10 },
      }
    },
    autoGrant = true,
    autoGrantLevel = 1,
    repeatable = false,
  },

  -- [2] 기초 도구
  {
    id = "QUEST_CRAFT_PICKAXE",
    name = "곡괭이 제작",
    description = "돌 곡괭이를 만드세요",
    category = "TUTORIAL",
    prerequisites = { "QUEST_FIRST_HARVEST" },
    requiredLevel = 1,
    objectives = {
      {
        type = "CRAFT",
        targetId = "CRAFT_STONE_PICKAXE",
        count = 1,
      }
    },
    rewards = {
      xp = 100,
      techPoints = 0,
      items = {},
    },
    autoGrant = false,
    repeatable = false,
  },

  -- [3] 첫 건축
  {
    id = "QUEST_BUILD_CAMPFIRE",
    name = "캠프파이어 건설",
    description = "캠프파이어를 건설하세요",
    category = "TUTORIAL",
    prerequisites = { "QUEST_CRAFT_PICKAXE" },
    requiredLevel = 1,
    objectives = {
      {
        type = "BUILD",
        targetId = "CAMPFIRE",
        count = 1,
      }
    },
    rewards = {
      xp = 150,
      techPoints = 1,
      items = {},
    },
    autoGrant = false,
    repeatable = false,
  },

  -- [4] 첫 포획
  {
    id = "QUEST_FIRST_CAPTURE",
    name = "첫 팰 포획",
    description = "도도를 포획하세요",
    category = "TUTORIAL",
    prerequisites = { "QUEST_BUILD_CAMPFIRE" },
    requiredLevel = 5,
    objectives = {
      {
        type = "CAPTURE",
        targetId = "DODO",
        count = 1,
      }
    },
    rewards = {
      xp = 200,
      techPoints = 1,
      items = {
        { itemId = "PAL_SPHERE", count = 5 },
      },
    },
    autoGrant = false,
    repeatable = false,
  },

  -- [5] 지속적 퀘스트 (일일)
  {
    id = "QUEST_DAILY_HARVEST",
    name = "일일 수확",
    description = "자원 노드에서 아이템을 100개 채집하세요",
    category = "DAILY",
    prerequisites = { "QUEST_FIRST_HARVEST" },
    requiredLevel = 1,
    objectives = {
      {
        type = "HARVEST",
        targetId = nil,  -- 모든 노드
        count = 100,
      }
    },
    rewards = {
      xp = 100,
      techPoints = 0,
      items = {
        { itemId = "BRANCH", count = 50 },
      },
    },
    autoGrant = true,
    autoGrantLevel = 1,
    repeatable = true,
    repeatCooldown = 86400,  -- 24시간
  },

  -- [6] 마일스톤
  {
    id = "QUEST_MILESTONE_LEVEL_10",
    name = "레벨 10 달성",
    description = "플레이어 레벨 10에 도달하세요",
    category = "ACHIEVEMENT",
    prerequisites = {},
    requiredLevel = 1,
    objectives = {
      {
        type = "REACH_LEVEL",
        targetId = "10",
        count = 1,
      }
    },
    rewards = {
      xp = 500,
      techPoints = 5,
      items = {
        { itemId = "BRONZE_PICKAXE", count = 1 },
      },
    },
    autoGrant = true,
    repeatable = false,
  },

  -- [7] 팰 포획 마일스톤
  {
    id = "QUEST_MILESTONE_CAPTURE_5",
    name = "팰 5마리 포획",
    description = "서로 다른 팰 종류 5마리를 포획하세요",
    category = "ACHIEVEMENT",
    prerequisites = { "QUEST_FIRST_CAPTURE" },
    requiredLevel = 1,
    objectives = {
      {
        type = "CAPTURE",
        targetId = nil,  -- 모든 팰
        count = 5,
      }
    },
    rewards = {
      xp = 300,
      techPoints = 3,
      items = {},
    },
    autoGrant = false,
    repeatable = false,
  },

  -- [8] 크리처 처치
  {
    id = "QUEST_KILL_RAPTOR",
    name = "랩터 처치",
    description = "랩터를 3마리 처치하세요",
    category = "MAIN",
    prerequisites = { "QUEST_BUILD_CAMPFIRE" },
    requiredLevel = 10,
    objectives = {
      {
        type = "KILL",
        targetId = "RAPTOR",
        count = 3,
      }
    },
    rewards = {
      xp = 250,
      techPoints = 2,
      items = {
        { itemId = "LEATHER", count = 5 },
      },
    },
    autoGrant = false,
    repeatable = false,
  },

  -- [9] 제작 마일스톤
  {
    id = "QUEST_MILESTONE_CRAFT_50",
    name = "50개 제작 완료",
    description = "총 50개의 아이템을 제작하세요",
    category = "ACHIEVEMENT",
    prerequisites = { "QUEST_CRAFT_PICKAXE" },
    requiredLevel = 1,
    objectives = {
      {
        type = "CRAFT",
        targetId = nil,  -- 모든 아이템
        count = 50,
      }
    },
    rewards = {
      xp = 400,
      techPoints = 4,
      items = {},
    },
    autoGrant = true,
    repeatable = false,
  },

  -- [10] 시설 건설
  {
    id = "QUEST_BUILD_STORAGE",
    name = "보관함 건설",
    description = "보관함을 건설하여 인벤토리를 확장하세요",
    category = "MAIN",
    prerequisites = { "QUEST_BUILD_CAMPFIRE" },
    requiredLevel = 5,
    objectives = {
      {
        type = "BUILD",
        targetId = "STORAGE_BOX",
        count = 1,
      }
    },
    rewards = {
      xp = 150,
      techPoints = 1,
      items = {},
    },
    autoGrant = false,
    repeatable = false,
  },
}

return QuestData
```

**작업량**: ~200줄 코드 (30분)

---

#### 1.2 `QuestService.lua` 서버 서비스 생성

**경로**: `src/ServerScriptService/Server/Services/QuestService.lua`

**구현 내용**: 퀘스트 상태 관리, 진행도 추적, 보상 지급

```lua
-- 큰 서비스이므로 다음 구조로 구현:

local QuestService = {}

-- Dependencies
local NetController
local DataService
local SaveService
local InventoryService
local PlayerStatService
local CombatService
local HarvestService

-- State: [userId] = { [questId] = { status, progress, claimedAt } }
local playerQuests = {}

-- API:
-- QuestService.Init(NetController, DataService, SaveService, InventoryService, PlayerStatService)
-- QuestService.acceptQuest(player, questId) → success, errorCode
-- QuestService.checkProgress(userId, questId) → progress
-- QuestService.claimReward(player, questId) → success, errorCode, rewards
-- QuestService.abandonQuest(player, questId) → success
-- QuestService.getQuests(userId) → { [questId] = questState }
-- QuestService.onHarvest(userId, nodeType, count) → 진행도 갱신
-- QuestService.onKill(userId, creatureId, count) → 진행도 갱신
-- QuestService.onCraft(userId, recipeId, count) → 진행도 갱신
-- QuestService.onBuild(userId, facilityId) → 진행도 갱신
-- QuestService.onCapture(userId, palId) → 진행도 갱신
-- QuestService.onLevelUp(userId, newLevel) → 진행도 갱신
-- QuestService.GetHandlers() → { ["Quest.Accept.Request"] = handler, ... }

return QuestService
```

**작업량**: ~800줄 코드 (4-5시간)

**핵심 로직**:

- 퀘스트 상태 머신 (LOCKED → AVAILABLE → ACTIVE → COMPLETED → CLAIMED)
- 선행 조건 검증 (prerequisite 퀘스트 완료 여부)
- 진행도 기반 자동 완료 감지
- 다른 서비스 콜백 연동 (harvest, kill, craft, build, capture)
- 보상 지급 (XP, 기술 포인트, 아이템)

---

#### 1.3 `Enums.lua` 확장

**경로**: `src/ReplicatedStorage/Shared/Enums/Enums.lua`

**추가 열거형**:

```lua
Enums.QuestStatus = {
  LOCKED = "LOCKED",           -- 선행조건 미충족
  AVAILABLE = "AVAILABLE",     -- 수락 가능
  ACTIVE = "ACTIVE",           -- 진행 중
  COMPLETED = "COMPLETED",     -- 완료 (보상 미지급)
  CLAIMED = "CLAIMED",         -- 보상 지급 완료
}

Enums.QuestCategory = {
  TUTORIAL = "TUTORIAL",       -- 튜토리얼 (신규 플레이어)
  MAIN = "MAIN",               -- 메인 스토리
  SIDE = "SIDE",               -- 사이드 퀘스트
  DAILY = "DAILY",             -- 일일 퀘스트
  ACHIEVEMENT = "ACHIEVEMENT", -- 업적
}

Enums.QuestObjectiveType = {
  HARVEST = "HARVEST",         -- 자원 수확
  KILL = "KILL",               -- 크리처 처치
  CRAFT = "CRAFT",             -- 아이템 제작
  BUILD = "BUILD",             -- 시설 건설
  COLLECT = "COLLECT",         -- 아이템 수집
  CAPTURE = "CAPTURE",         -- 팰 포획
  TALK = "TALK",               -- NPC 대화
  REACH_LEVEL = "REACH_LEVEL", -- 레벨 달성
  UNLOCK_TECH = "UNLOCK_TECH", -- 기술 해금
}
```

**작업량**: ~50줄 (15분)

---

#### 1.4 `Protocol.lua` 확장

**경로**: `src/ReplicatedStorage/Shared/Net/Protocol.lua`

**추가 명령어**:

```lua
["Quest.List.Request"] = true,        -- 퀘스트 목록 조회
["Quest.Accept.Request"] = true,      -- 퀘스트 수락
["Quest.Claim.Request"] = true,       -- 보상 수령
["Quest.Abandon.Request"] = true,     -- 퀘스트 포기
["Quest.Progress.Changed"] = true,    -- 진행도 업데이트 (서버 → 클라이언트)
["Quest.Unlocked"] = true,            -- 새 퀘스트 해금 (서버 → 클라이언트)
["Quest.Completed"] = true,           -- 퀘스트 완료 (서버 → 클라이언트)
```

**작업량**: ~15줄 (10분)

---

#### 1.5 ServerInit.lua에 QuestService 초기화 코드 추가

**경로**: `src/ServerScriptService/ServerInit.server.lua` (줄 ~350 이후)

```lua
-- QuestService 초기화 (Phase 8)
local QuestService = require(Services.QuestService)
QuestService.Init(NetController, DataService, SaveService, InventoryService, PlayerStatService, CombatService, HarvestService)

-- QuestService 핸들러 등록
for command, handler in pairs(QuestService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- 다른 서비스에 QuestService 콜백 주입 (진행도 갱신용)
HarvestService.SetQuestCallback(QuestService)
CombatService.SetQuestCallback(QuestService)
CraftingService.SetQuestCallback(QuestService)
BuildService.SetQuestCallback(QuestService)
PartyService.SetQuestCallback(QuestService)
PlayerStatService.SetQuestCallback(QuestService)
```

**작업량**: ~15줄 (10분)

---

### ✅ 클라이언트 구현 필요

#### 1.6 `QuestController.lua` 클라이언트 컨트롤러 생성

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/QuestController.lua`

**구현 내용**: 서버 퀼 정보 요청, 로컬 상태 캐시, UI 이벤트

```lua
-- TechController.lua와 유사한 패턴으로 구현

local QuestController = {}

-- State
local playerQuests = {}       -- [questId] = { status, progress }
local questDefinitions = {}   -- [questId] = questData
local listeners = {}

-- API:
-- QuestController.Init()
-- QuestController.getQuests() → { [questId] = questState }
-- QuestController.getQuestDef(questId) → questData
-- QuestController.getStatus(questId) → status
-- QuestController.getProgress(questId) → progress%
-- QuestController.requestAccept(questId, callback)
-- QuestController.requestClaim(questId, callback)
-- QuestController.requestAbandon(questId, callback)
-- QuestController.onQuestUpdated(callback)
-- QuestController.onQuestCompleted(callback)

return QuestController
```

**작업량**: ~200줄 (1.5시간)

---

#### 1.7 `QuestUI.lua` / UI 업데이트

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/UI/QuestUI.lua` (신규 또는 기존 수정)

**구현 내용**:

- 퀼 목록 패널 (진행도 바)
- 현재 활성 퀼 표시
- 퀼 완료 팝업
- 보상 표시 및 수령 버튼

**작업량**: ~500줄 (3시간) - **토탈 Phase 8: 8-10시간**

---

## 🟡 우선순위 2: Phase 9 NPC 상점 시스템 완성

### ⚠️ 부분 완료 (80%)

#### 2.1 `ShopController.lua` 완성도 확인 및 보완

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.lua`

**확인 항목**:

- [ ] NPCShopService와의 요청/응답 완료?
- [ ] 상점 인벤토리 UI 반영?
- [ ] 구매/판매 버튼 동작?
- [ ] 골드 UI 갱신?

**작업량**: ~1시간 (검토 + 보완)

---

#### 2.2 `NPCShopUI.lua` / 상점 UI 생성 또는 수정

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/UI/ShopUI.lua` (기존 여부 확인)

**필요 구현**:

- 상점 이름/설명 표시
- 판매 아이템 목록 (스크롤)
- 구매 가격, 재고 표시
- "구매" 버튼 + 수량 선택
- 플레이어 골드 잔액 표시
- 판매 목록 탭 (거래 역방향)
- "판매" 버튼 + 슬롯 선택
- 거래 완료 팝업

**작업량**: ~600줄 (3-4시간)

---

#### 2.3 `NPCShopData.lua` 데이터 보강

**경로**: `src/ReplicatedStorage/Data/NPCShopData.lua`

**현황**: 기본 구조는 있으나 **상점 데이터가 가능하면 3-5개로 확대 필요**

```lua
-- 현재: GENERAL_STORE만 있음 (추측)

-- 추가할 상점:
1. GENERAL_STORE      - 기본 물품 (기존)
2. WEAPON_SHOP        - 무기/도구 전문
3. ARMOR_THRIFT       - 방어구/의류
4. ALCHEMY_POTION     - 물약/소비 아이템
5. LUXURY_GOODS       - 고급 장식 아이템 (선택)
```

**작업량**: ~300줄 (1.5시간)

---

#### 2.4 보상 및 테스트

- [ ] Rojo 동기화 확인
- [ ] Studio에서 NPC와의 상호작용 테스트
- [ ] 구매/판매 거래 동작 확인
- [ ] 골드 수치 정확성 검증

**작업량**: ~1-2시간 (테스트)

**토탈 Phase 9: 6-8시간**

---

## 🟡 우선순위 3: NPC 상호작용 시스템

### ⚠️ 부분 불완전 (20%)

#### 3.1 `InteractController.lua` NPC 대화 시스템 구현

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/InteractController.lua`

**現況**: 줄 189에 `NPC dialogue not implemented` TODO 있음

**구현 내용**:

```lua
-- 현재 상태:
-- E 키로 NPC와 상호작용하면 대화 창 열기
-- 대화 분지(옵션) 표시
-- 옵션 선택 시 서버에 요청 (상점 열기, 퀼 받기 등)

-- 필요한 추가 구현:
1. Dialogue 데이터 구조 정의 (DialogueData.lua 신규)
2. DialogueUI.lua - 대화 창 UI
3. DialogueController.lua - 대사 분지 처리
4. NPC 모델에 Humanoid 및 Dialogue 속성 설정 (Studio에서)
```

**DialogueData.lua 예시**:

```lua
local DialogueData = {
  NPC_MERCHANT = {
    id = "NPC_MERCHANT",
    name = "상인 톰",
    greeting = "안녕하세요! 뭔가 필요하신가요?",
    branches = {
      {
        text = "상점을 열어주세요",
        action = "OPEN_SHOP",
        data = { shopId = "GENERAL_STORE" },
      },
      {
        text = "뭔가 팔고 싶어요",
        action = "OPEN_SHOP_SELL",
        data = { shopId = "GENERAL_STORE" },
      },
      {
        text = "나중에 다시 만나요",
        action = "CLOSE",
      },
    }
  }
}
```

**작업량**: ~400줄 (2.5시간)

---

#### 3.2 `DialogueUI.lua` 대화 창 구현

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/UI/DialogueUI.lua` (신규)

**기능**:

- NPC 이름과 초상화(아바타) 표시
- 대사 텍스트 표시 (점진적 노출 가능)
- 선택지 버튼 (3-5개)
- 선택지 선택 시 애니메이션

**작업량**: ~300줄 (2시간)

---

#### 3.3 Studio 안의 NPC 설정 (수동)

**토탈 NPC 상호작용: 4-5시간**

---

## 🟡 우선순위 4: 클라이언트 UI 완성도 보강

### ⚠️ 기존 컨트롤러/UI 점검 및 보완 필요

#### 4.1 `UIManager.lua` 전체 UI 통합 상태 확인

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/UIManager.lua`

**확인 항목**:

- [ ] 모든 컨트롤러가 UIManager에 등록되어 있는가?
- [ ] UI 레이어 구조 (패널 Z-Order)가 정확한가?
- [ ] 각 UI 요소의 보이기/숨기기 로직이 완벽한가?
- [ ] 반응형 디자인 (화면 크기 변화) 처리?

**작업량**: ~2시간 (검토 + 보강)

---

#### 4.2 기존 컨트롤러들 상태 검증

**검사 항목**:

| 컨트롤러                 | 상태         | 우선순위 |
| ------------------------ | ------------ | -------- |
| InventoryController      | ⚠️ 확인 필요 | 중       |
| StorageController        | ⚠️ 확인 필요 | 중       |
| CraftController          | ⚠️ 확인 필요 | 중       |
| BuildController          | ⚠️ 확인 필요 | 중       |
| CombatController         | ⚠️ 확인 필요 | 중       |
| DragDropController       | ⚠️ 확인 필요 | 중       |
| VirtualizationController | ⚠️ 확인 필요 | 낮       |

**각 컨트롤러당 작업량**: ~30분

**토탈: 4-5시간**

---

## 📊 전체 작업 로드맵

### Phase 8 (퀨스트) - 우선순위 1 (가장 중요)

```
[총 소요 시간: 8-10시간]

Week 1-2:
├─ QuestData.lua 작성 (30분)
├─ Enums.lua 확장 (15분)
├─ Protocol.lua 확장 (10분)
├─ QuestService.lua 구현 (4-5시간) ⭐ 가장 오래 걸림
├─ ServerInit.lua 수정 (10분)
└─ 경계: 다른 Service 콜백 추가 (HarvestService 등)

Week 3:
├─ QuestController.lua 구현 (1.5시간)
└─ UI 구현 (4-5시간)
  ├─ QuestUI.lua (Progress bar, Quest list)
  ├─ QuestRewardUI.lua (Complete popup)
  └─ Integration tests
```

---

### Phase 9 (상점) - 우선순위 2 (보완)

```
[총 소요 시간: 6-8시간]

진행 중:
├─ NPCShopData.lua 확대 (1.5시간)
├─ ShopController.lua 검증 (1시간)
├─ ShopUI.lua 완성 (3-4시간)
└─ 테스트 (1-2시간)
```

---

### NPC 상호작용 - 우선순위 3 (신규)

```
[총 소요 시간: 4-5시간]

진행 중:
├─ DialogueData.lua 작성 (1시간)
├─ DialogueController.lua 구현 (1.5시간)
├─ DialogueUI.lua 구현 (2시간)
└─ Studio 설정 (0.5시간)
```

---

### 클라이언트 UI 보강 - 우선순위 4 (점진적)

```
[총 소요 시간: 4-5시간]

진행 중:
├─ UIManager.lua 검증 (1-2시간)
├─ 기존 컨트롤러들 점검 (2-3시간)
└─ 새로운 UI 컴포넌트 (1-2시간, 필요시)
```

---

## 📝 구현 체크리스트

### Phase 8 구현 순서

- [ ] **Step 1**: QuestData.lua 생성 (10개 기본 퀘스트)
- [ ] **Step 2**: Enums.lua 에 QuestStatus/Category/ObjectiveType 추가
- [ ] **Step 3**: Protocol.lua 에 Quest.\* 명령어 추가
- [ ] **Step 4**: QuestService.lua 서버 서비스 구현
  - [ ] Ⅰ. Init 및 PlayerState 로드
  - [ ] Ⅱ. acceptQuest() - 인수 검증 + 상태 변경
  - [ ] Ⅲ. checkProgress() - 진행도 계산
  - [ ] Ⅳ. claimReward() - 보상 지급
  - [ ] Ⅴ. on\* 콜백 (onHarvest, onKill, onCraft, onBuild 등)
  - [ ] Ⅵ. GetHandlers() - 네트워크 핸들러 등록
- [ ] **Step 5**: ServerInit.lua 에 QuestService 추가
- [ ] **Step 6**: HarvestService/CombatService/CraftingService 등에 QuestService 콜백 연결
- [ ] **Step 7**: ClientInit.lua 에 QuestController 추가
- [ ] **Step 8**: QuestController.lua 클라이언트 구현
- [ ] **Step 9**: QuestUI.lua 및 관련 UI 구현
- [ ] **Step 10**: 통합 테스트

---

### Phase 9 완성 순서

- [ ] **Step 1**: NPCShopData.lua 데이터 확대 (5개 상점)
- [ ] **Step 2**: ShopController.lua 동작 검증
- [ ] **Step 3**: ShopUI.lua 완성 (구매/판매 탭)
- [ ] **Step 4**: 통합 테스트

---

### NPC 상호작용 구현 순서

- [ ] **Step 1**: DialogueData.lua 작성
- [ ] **Step 2**: DialogueController.lua 구현
- [ ] **Step 3**: DialogueUI.lua 구현
- [ ] **Step 4**: InteractController.lua 의 NPC 대화 부분 완성
- [ ] **Step 5**: Studio 에서 NPC 모델에 대화 데이터 연결

---

## 🎯 다음 즉시 작업 (내일 시작)

**Phase 8 (퀨스트) 우선 구현**:

1. `QuestData.lua` 파일 생성 → 최소 10개 퀘스트 정의
2. `Enums.lua` 확장 → QuestStatus, QuestCategory, ObjectiveType 추가
3. `Protocol.lua` 확장 → Quest.\* 명령어 추가
4. `QuestService.lua` 구현 시작 → 먼저 상태 관리와 기본 API부터

이 점 4가지만 끝내도 **첫 주 목표 달성** 가능.

---

## 📞 구현 시 참고

### 기존 패턴 참고

- **TechService.lua** → QuestService.lua 구조의 참고점
- **TechController.lua** → QuestController.lua 구조의 참고점
- **InventoryService.lua** → 콜백 패턴 참고 (onHarvest 등)
- **TimeService.lua** → 이벤트 드리븐 구조 참고

### 데이터 검증

- Validator.lua 의 assert() 활용 (데이터 무결성)
- 모든 questId는 유일해야 함
- prerequisites 는 이미 완료된 퀘스트만 참조
- targetId는 DataService에 존재해야 함

### 성능 최적화

- playerQuests 는 [userId] → 메모리 효율
- progress 는 필요할 때만 계산 (캐시 X, 실시간 O)
- 일일 퀘스트는 repeatCooldown 검증

---

**작성 완료. 이 문서만 참고하면 모든 미완성 작업 즉시 시작 가능합니다.**
