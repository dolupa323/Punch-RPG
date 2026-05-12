# 🏛️ [Punch-RPG] 레거시 잔재 & 시스템 기능 동작 정밀 감사 보고서

본 보고서는 **DinoTribeSurvival (공룡 부족 서바이벌 / Origin-WILD)** 시절부터 누적되어 기동 중인 **43개의 거대 서버 서비스군**의 기능 동작과 현재 **아바타 속성 검술 RPG** 아키텍처 간의 강한 상호 간섭 및 잔재 실태를 샅샅이 추적하여 기록한 시스템 감사 명세서입니다.

---

## 🧭 1. 레거시 전체 서비스군 기능 동작 및 매핑 트리

현재 `ServerInit.server.lua`를 기점으로 서버 기동 시 동시 활성화되는 레거시 서비스들을 기능별로 그룹화한 실태입니다.

```
ServerScriptService/Server/Services/
├── ⚙️ [Core & Data] 
│   ├── DataService.lua          # 게임 데이터 무결성 검증 및 로더
│   ├── SaveService.lua          # DataStore 영속 플레이어/월드 데이터 저장
│   └── TimeService.lua          # 낮/밤 2400초 사이클 계산 및 클라 시간 동기화
│
├── 🎒 [Inventory & Item Economy]
│   ├── InventoryService.lua     # 인벤토리 이동/분할/드롭 트랜잭션 (75KB)
│   ├── WorldDropService.lua     # 월드 아이템 드롭, 5스터드 병합 및 Prune 제한
│   ├── StorageService.lua       # 영토 내 보관 상자의 아이템 이송 관리
│   ├── EquipService.lua         # 도구 및 무구 장착 권한 유효성 스펙 검증
│   ├── DurabilityService.lua    # 타격 시 무기/도구 내구도 감쇠 및 파괴
│   ├── NPCShopService.lua       # 골드 기반 NPC 거래 상점 (31KB)
│   └── EnhanceService.lua       # 무기 수치 강화 % 확률 계산 및 파괴 방지 주문서
│
├── 🔨 [Building & Crafting]
│   ├── BuildService.lua         # 구조물 배치, 충돌 검증, 500개 캡 Prune 제한
│   ├── BlockBuildService.lua    # 복셀/마인크래프트식 블록 쌓기 및 내구도 파괴
│   ├── FacilityService.lua      # 화로, 화탑 등 상태 머신(IDLE/ACTIVE) 연료 소모
│   ├── RecipeService.lua        # 제작 동적 효율 계산 및 시간 보정
│   └── CraftingService.lua      # Timestamp 기반 즉시/대기 제작 큐 수거
│
├── 👾 [Monster, AI & Combat]
│   ├── CreatureService.lua      # 공룡, 고블린 등 FSM(Idle/Wander/Chase) AI (111KB)
│   ├── CombatService.lua        # 대미지 계산, 무기 기절 50%, 넉백 물리 가해 (40KB)
│   ├── DebuffService.lua        # 추위(Freezing), 화염, 피냄새 디버프 및 틱 대미지
│   ├── StaminaService.lua       # 대시, 공격 시 소모되는 스태미나 계산 감쇠
│   └── HungerService.lua        # 포만감 지속 감쇠 및 굶주림 도트 대미지
│
├── 🦖 [Pal System (팰월드 스타일)]
│   ├── PalboxService.lua        # 보관함 팰 CRUD 및 저장 연계 (19KB)
│   ├── CaptureService.lua       # HP 비율식 팰 포획 확률 공식 및 포획구 소모
│   ├── PartyService.lua         # 팰 파티 편성/해제 및 소환/회수 제어 (55KB)
│   └── PalAIService.lua         # 소환된 팰의 전투/수행/따라오기 FSM 가동
│
├── 🏕️ [Territory & Infrastructure]
│   ├── BaseClaimService.lua     # 부족 영토 영역 캐시 및 범위 권한 판정 (33KB)
│   ├── TotemService.lua         # 보호 토템 충전 및 영역 내 침입자 보호막 차단
│   ├── PortalService.lua        # 맵 간 포탈 이동 및 인벤토리 해제 요구 검사
│   ├── CharacterSetupService.lua # 플레이어 캐릭터 바디 스케일링
│   ├── AdminCommandService.lua  # 관리자 치트 명령어셋 바인딩
│   └── BotService.lua           # 자동 가동 테스트용 봇 소환 루틴
│
└── 📝 [Quest & Tutorial]
    ├── TutorialService.lua      # 스타팅 튜토리얼 진행도 추적
    └── TutorialQuestService.lua # 15종의 퀘스트 조건 판정 및 보상 연계 (11KB)
```

---

## ⚠️ 2. 현재 아바타 속성 검술 RPG 시스템과의 "치명적 상호 간섭" 지점 분석

이전 공룡 부족 서바이벌의 거대 모듈들이 백그라운드에 여전히 활성화되어 있어, 아바타 검술 조작 시 심각한 연산 간섭과 버그 위험을 초래하고 있는 포인트들입니다.

### ① 콤보 타격 시 자원 채집의 이중 트리거 간섭 ([HarvestService.lua](file:///c:/YJS/Roblox/RPG/src/ServerScriptService/Server/Services/HarvestService.lua))
*   **문제점**: `HarvestService`는 맵 상의 나무, 돌 등 자원 노드를 무구로 때리면 자원을 수급하게 설계되어 있습니다. 
*   **부작용**: 플레이어가 속성 나무검을 쥐고 하급 슬라임을 향해 3단 공격 콤보를 전개하는 반경 내에 나무나 돌 에셋이 존재할 경우, **슬라임 타격 대미지와 동시에 자원 채집 연산이 이중으로 격발**되어 원치 않는 아이템 획득 및 내구도 차감 연산이 메모리 상에서 강하게 꼬일 수 있습니다.

### ② 튜토리얼 퀘스트 연동 콜백의 스레드 병목 ([TutorialQuestService.lua](file:///c:/YJS/Roblox/RPG/src/ServerScriptService/Server/Services/TutorialQuestService.lua))
*   **문제점**: `ServerInit.server.lua` L274-279를 보면, `InventoryService`, `HarvestService`, `CraftingService`, `BuildService`, `CombatService`의 모든 핵심 비즈니스 트랜잭션 마감 직후 퀘스트 추적 콜백(`TutorialQuestService.onItemAdded` 등)을 다이렉트로 강제 호출하게 엮여 있습니다.
*   **부작용**: 플레이어가 속성검으로 슬라임을 처치할 때마다, 현재 게임엔 기획조차 되어 있지 않은 레거시 15종 공룡 부족 퀘스트의 카운트 연산을 검증하기 위해 거대한 스레드 조회 연산이 동시 격발되어 불필요한 연산 낭비 및 Null 에러를 유발합니다.

### ③ 포만감 및 스태미나 생존 스탯의 괴리 ([HungerService.lua](file:///c:/YJS/Roblox/RPG/src/ServerScriptService/Server/Services/HungerService.lua))
*   **문제점**: `HungerService`와 `StaminaService`가 백그라운드에서 실시간 스레드로 돌며 플레이어의 포만감을 깎고 있습니다.
*   **부작용**: 콤보 공격과 속성 액션을 호쾌하게 펼치는 검술 RPG 장르임에도 불구하고, 일정 시간이 지나면 공룡 서바이벌 시절의 포만감 게이지가 고갈되어 캐릭터가 도트 피해를 입고 사망해 버리는 기획적 심각한 부조화가 활성화 상태입니다.

### ④ 유령 팰 시스템 리소스 점유 (`PalboxService`, `PartyService` 등)
*   **문제점**: 팰 보관함, 포획률 계산, 팰 AI 등 약 150KB에 달하는 팰월드 스타일의 거대 코드 모듈들이 `ServerInit`에서 전부 로딩 및 기동하고 있습니다.
*   **부작용**: 현재 게임엔 포획구 에셋도 없고 소환할 팰도 없으므로, 아무 일도 하지 않으면서 원격 네트워크 리스너 리소스를 점유한 채 메모리 유출을 잠재적으로 대기시키는 유령 상태로 기동되고 있습니다.

---

## 🛠️ 3. 레거시 정리 및 완벽 템플릿화를 위한 3대 격리 가이드라인

데이터값만 바꾸면 작동되는 유연한 템플릿 RPG를 구축하기 위해, 거대 레거시 코드들을 다음과 같이 **3단 격리 및 청소(Clean-Up)**해야 합니다.

```
[레거시 청소 및 격리 로드맵]

1. 레거시 모듈 기능 격리 (Isolation)
   - Stamina, Hunger 등 생존 요소 작동 스레드 온/오프 스위치 데이터화 (Balance.lua 연동)
   - 팰월드/공룡 시스템 (Capture, Party, Palbox) 로딩 선택적 주석 처리

2. 자원 채집 & 무기 타격 결합 해제 (Decoupling)
   - HarvestService 타격 가동을 콤보 도구 및 일반 공격과 완벽 분리
   - 도구와 전투용 무기의 애니메이션 및 타격 영역 독점 처리

3. 퀘스트 콜백 범용화 (Event-Driven Questing)
   - 강한 하드코딩 콜백 바인딩을 제거
   - 옵저버(Observer) 패턴 기반의 느슨한 이벤트 전달로 아키텍처 개선
```

### 1) 생존 스탯 스위치화 (`Balance.lua` 상수로 제어)
*   `Balance.lua`에 생존 게임 전용 여부를 켜고 끄는 스위치 추가:
    ```lua
    Balance.ENABLE_SURVIVAL_STATS = false -- false로 설정 시 Hunger 및 Stamina 자동 감쇠 정지
    ```
*   `HungerService.lua`, `StaminaService.lua` 내부 루프 연산 첫머리에 위 스위치가 `false`일 시 연산을 즉각 우회(`return`)하도록 가드를 주입합니다.

### 2) 팰 시스템 및 이중 자동화 시스템 완전 걷어내기
*   `ServerInit.server.lua`에서 `PalboxService`, `CaptureService`, `PartyService`, `PalAIService`를 연결하는 require 문과 Init 문을 전면 차단하여 무협 RPG 상태에서 쓸모없는 팰 메모리 릭 요소를 100% 제거합니다.

### 3) 퀘스트 콜백의 느슨한 이벤트화 (Decoupling)
*   각 서비스(`InventoryService`, `CombatService` 등) 내부에 `TutorialQuestService` 콜백을 명시적으로 참조하여 호출하는 대신, **중앙 이벤트 버스(Event Bus)** 또는 **BindableEvent**를 통해 이벤트를 쏘아주고, 필요한 퀘스트 시스템만 이를 수신하게 만들어 상호 간섭을 영구 격리합니다.
