# 📋 미완성 작업 체크리스트 & 진행 기록

> **프로젝트**: Origin-WILD (DinoTribeSurvival)  
> **시작일**: 2026-03-12  
> **목표**: 모든 미완성 작업을 명확하게 추적하고 완료

---

## 🎯 전체 진행률

**전체**: `████░░░░░░` **40%** (Phase 8-9 미완성)

| Phase             | 상태        | 진행률 | 예상 소요시간 |
| ----------------- | ----------- | ------ | ------------- |
| Phase 1-4         | ✅ 완료     | 100%   | -             |
| Phase 5           | ✅ 완료     | 100%   | -             |
| Phase 6           | ✅ 완료     | 100%   | -             |
| Phase 7           | ✅ 완료     | 100%   | -             |
| Phase 9           | ⚠️ 부분완료 | 80%    | 6-8h          |
| **Phase 8**       | ❌ 미구현   | 0%     | **8-10h**     |
| **NPC 상호작용**  | ⚠️ 부분완료 | 20%    | **4-5h**      |
| **클라이언트 UI** | ⚠️ 부분완료 | 70%    | **4-5h**      |

---

## 🔴 Phase 8: 퀨스트 시스템 (우선순위 1)

**예상 소요**: 8-10시간 | **상태**: ❌ 완전 미구현

### ✅ 서버 구현 체크리스트

#### Week 1: 데이터 & 프로토콜

- [ ] **QuestData.lua 생성**
  - [ ] 10개 기본 퀘스트 데이터 정의
  - [ ] 예: QUEST_FIRST_HARVEST, QUEST_CRAFT_PICKAXE, QUEST_BUILD_CAMPFIRE 등
  - [ ] 일일 퀘스트 + 마일스톤 포함
  - 예상: 30분

- [ ] **Enums.lua 확장**
  - [ ] QuestStatus (LOCKED, AVAILABLE, ACTIVE, COMPLETED, CLAIMED)
  - [ ] QuestCategory (TUTORIAL, MAIN, SIDE, DAILY, ACHIEVEMENT)
  - [ ] QuestObjectiveType (HARVEST, KILL, CRAFT, BUILD, COLLECT, CAPTURE, REACH_LEVEL, UNLOCK_TECH)
  - 예상: 15분

- [ ] **Protocol.lua 확장**
  - [ ] Quest.List.Request / Quest.Accept.Request / Quest.Claim.Request / Quest.Abandon.Request
  - [ ] Quest.Progress.Changed / Quest.Unlocked / Quest.Completed
  - 예상: 10분

#### Week 1-2: QuestService 핵심 구현

- [ ] **QuestService.lua 작성**
  - [ ] Init() - 데이터 로드 + 플레이어 상태 초기화
  - [ ] acceptQuest(player, questId) - 선행조건 검증 + 상태 변경
  - [ ] checkProgress(userId, questId) - 진행도 계산
  - [ ] claimReward(player, questId) - 보상 지급 (XP, TechPoints, Items)
  - [ ] abandonQuest(player, questId) - 퀨스트 포기
  - [ ] on\* 콜백 (onHarvest, onKill, onCraft, onBuild, onCapture, onLevelUp, onTechUnlock)
  - [ ] GetHandlers() - 네트워크 핸들러
  - 예상: 4-5시간

- [ ] **ServerInit.lua 수정**
  - [ ] QuestService require + Init 호출
  - [ ] QuestService.GetHandlers() 등록
  - [ ] 다른 서비스에 콜백 연결
    - [ ] HarvestService.SetQuestCallback()
    - [ ] CombatService.SetQuestCallback()
    - [ ] CraftingService.SetQuestCallback()
    - [ ] BuildService.SetQuestCallback()
    - [ ] PartyService.SetQuestCallback()
    - [ ] PlayerStatService.SetQuestCallback()
  - 예상: 15분

#### Week 2-3: 클라이언트 구현

- [ ] **QuestController.lua 생성**
  - [ ] Init() - 서버 요청
  - [ ] getQuests() / getStatus() / getProgress()
  - [ ] requestAccept() / requestClaim() / requestAbandon()
  - [ ] 이벤트 리스너 (onQuestUpdated, onQuestCompleted)
  - [ ] 서버 이벤트 수신 (Progress.Changed, Unlocked, Completed)
  - 예상: 1.5시간

- [ ] **QuestUI.lua 생성**
  - [ ] 퀨스트 목록 패널
  - [ ] 진행도 바 (%). 목표를 정량적으로 표시
  - [ ] 현재 활성 퀨스트 강조 표시
  - [ ] 완료된 퀨스트 보상 수령 버튼
  - [ ] 보상 팝업 (XP, 기술포인트, 아이템 표시)
  - 예상: 3-4시간

- [ ] **ClientInit.lua 수정**
  - [ ] QuestController 추가
  - 예상: 5분

---

## 🟡 Phase 9: NPC 상점 (우선순위 2)

**예상 소요**: 6-8시간 | **상태**: ⚠️ 80% 완료

### ⚠️ 완성도 검증

- [ ] **NPCShopData.lua 확대**
  - [ ] 기존 상점 (GENERAL_STORE) 유지
  - [ ] WEAPON_SHOP 추가 (무기/도구)
  - [ ] ARMOR_SHOP 추가 (방어구)
  - [ ] ALCHEMY_SHOP 추가 (물약/소비)
  - [ ] LUXURY_SHOP 추가 (고급 아이템)
  - 예상: 1.5시간

- [ ] **ShopController.lua 동작 검증**
  - [ ] NPCShopService와 요청/응답 확인
  - [ ] 상점 정보 조회 - 아이템 목록 표시?
  - [ ] 구매 기능 - 인벤토리에 추가?
  - [ ] 판매 기능 - 슬롯에서 제거 + 골드 증가?
  - [ ] 골드 UI 갱신?
  - 예상: 1시간

- [ ] **ShopUI.lua 완성**
  - [ ] 상점 이름/설명 표시
  - [ ] 판매 아이템 탭
    - [ ] 아이템 리스트 (가격, 재고)
    - [ ] 구매 버튼 + 수량 선택
  - [ ] 판매 탭
    - [ ] 플레이어 인벤토리 표시
    - [ ] "판매" 버튼 + 개수 선택
  - [ ] 플레이어 골드 잔액 항상 표시
  - [ ] 거래 완료 팝업
  - 예상: 3-4시간

- [ ] **통합 테스트**
  - [ ] Rojo 동기화 확인
  - [ ] Studio에서 NPC와 상호작용
  - [ ] 구매/판매 거래 동작 검증
  - [ ] 골드 수치 검증
  - 예상: 1-2시간

---

## 🟡 우선순위 3: NPC 상호작용 시스템

**예상 소요**: 4-5시간 | **상태**: ⚠️ 20% 완료

### ⚠️ 구현 필요

- [ ] **DialogueData.lua 생성**
  - [ ] 다양한 NPC 대사 분지 정의
  - [ ] NPC_MERCHANT, NPC_QUEST_GIVER, NPC_TRAINER 등
  - [ ] 각 NPC별 3-5개 선택지
  - [ ] action (열 action: OPEN_SHOP, OPEN_QUEST_LIST, START_DIALOGUE 등)
  - 예상: 1시간

- [ ] **DialogueController.lua 생성**
  - [ ] 대사 로직 처리
  - [ ] 선택지 처리 및 분기
  - [ ] 서버 요청 (상점 열기, 퀨스트 수락 등)
  - 예상: 1.5시간

- [ ] **DialogueUI.lua 생성**
  - [ ] NPC 초상화 이미지 표시
  - [ ] NPC 이름 표시
  - [ ] 대사 텍스트 (점진 노출 가능)
  - [ ] 선택지 버튼 (3-5개)
  - [ ] 선택시 애니메이션
  - 예상: 2시간

- [ ] **InteractController.lua 수정**
  - [ ] 줄 189의 TODO "NPC dialogue not implemented" 제거
  - [ ] DialogueController와 연동
  - 예상: 30분

- [ ] **Studio 설정 (수동)**
  - [ ] NPC 모델에 Dialogue 속성 추가
  - [ ] 각 NPC에 대사 데이터 연결
  - 예상: 30분

---

## 🟡 우선순위 4: 클라이언트 UI 보강

**예상 소요**: 4-5시간 | **상태**: ⚠️ 70% 완료

### ⚠️ 점검 및 보강

- [ ] **UIManager.lua 검증**
  - [ ] 모든 컨트롤러가 초기화되는가?
  - [ ] UI 레이어 순서 (Z-Order)가 맞는가?
  - [ ] 각 UI의 show/hide 로직이 완벽한가?
  - [ ] 반응형 디자인 처리 (화면 크기 변화)?
  - 예상: 1-2시간

- [ ] **기존 컨트롤러들 점검**

  | 컨트롤러                 | 검증 항목                   | 예상 시간 |
  | ------------------------ | --------------------------- | --------- |
  | InventoryController      | UI 동기화, 슬롯 업데이트    | 30분      |
  | StorageController        | 창고 열기/닫기, 아이템 이동 | 30분      |
  | CraftController          | 제작 큐 표시, 진행도 바     | 30분      |
  | BuildController          | 배치 시스템, 콜리전 표시    | 1시간     |
  | CombatController         | 데미지 표시, 근거리/원거리  | 30분      |
  | DragDropController       | 드래그 메커닉               | 30분      |
  | VirtualizationController | 성능 (가상화) 동작          | 30분      |

- [ ] **새로운 UI 컴포넌트 (필요시)**
  - [ ] 로딩 스크린 개선
  - [ ] 체력/스태미너 바 애니메이션
  - [ ] 장장 슬롯 시각화
  - 예상: 1-2시간

---

## 📊 주간 계획

### 1주차 (Day 1-3)

**목표**: Phase 8 기초 완성

- Day 1:
  - [ ] QuestData.lua 작성 (30분)
  - [ ] Enums.lua 확장 (15분)
  - [ ] Protocol.lua 확장 (10분)
  - **소계**: 55분

- Day 2-3:
  - [ ] QuestService.lua 구현 (4-5시간)
  - [ ] ServerInit.lua 수정 (15분)
  - **소계**: ~4.5시간

---

### 2주차 (Day 4-7)

**목표**: Phase 8 클라이언트 + Phase 9 완성

- Day 4-5:
  - [ ] QuestController.lua (1.5시간)
  - [ ] QuestUI.lua (2시간)
  - [ ] ClientInit.lua 수정 (5분)
  - **소계**: ~3.5시간

- Day 5-6:
  - [ ] NPCShopData.lua 확대 (1.5시간)
  - [ ] ShopController.lua 검증 (1시간)
  - [ ] ShopUI.lua 완성 (3시간)
  - **소계**: ~5.5시간

- Day 7:
  - [ ] 통합 테스트 (1-2시간)
  - [ ] 버그 수정
  - **소계**: ~1.5시간

---

### 3주차 (Day 8-10)

**목표**: NPC 상호작용 + UI 보강

- Day 8:
  - [ ] DialogueData.lua (1시간)
  - [ ] DialogueController.lua (1.5시간)
  - **소계**: ~2.5시간

- Day 9:
  - [ ] DialogueUI.lua (2시간)
  - [ ] InteractController.lua 수정 (30분)
  - **소계**: ~2.5시간

- Day 10:
  - [ ] UIManager.lua 검증 (1-2시간)
  - [ ] 기존 컨트롤러 점검 (1-2시간)
  - [ ] Studio NPC 설정 (30분)
  - **소계**: ~2.5-3시간

---

## ✅ 완료 항목

### 서버 제작 (이미 완료됨)

- [x] 데이터 로드 & 검증
- [x] 시간 시스템 (낮/밤)
- [x] 저장/로드 (SaveService, DataStore)
- [x] 인벤토리 (40슬롯, 스택)
- [x] 월드 드롭 (400개 cap, 병합)
- [x] 건축 시스템
- [x] 제작 시스템
- [x] 크리처 AI
- [x] 전투 시스템
- [x] 팰 시스템 (포획, 파티, AI)
- [x] 자동화 시스템 (베이스, 팰 작업)
- [x] 기술 트리
- [x] 상점 시스템

---

## 🎯 최종 목표

**완료**시 다음 상태:

- ✅ Phase 1-9 모두 완성 (100%)
- ✅ 모든 핵심 시스템 동작 가능
- ✅ 클라이언트 UI 완성도 80% 이상
- ✅ 게임 플레이 가능 (튜토리얼 ~ 엔드게임)

---

## 📝 기록

### 작성일

| 편성               | 완료일 | 상태       | 소요시간 | 비고                            |
| ------------------ | ------ | ---------- | -------- | ------------------------------- |
| Phase 8 기초       | -      | 🔄 진행 중 | -        | QuestData, Enums, Protocol 부터 |
| Phase 8 서비스     | -      | ⏳ 대기    | -        | QuestService.lua                |
| Phase 8 클라이언트 | -      | ⏳ 대기    | -        | Controller + UI                 |
| Phase 9 완성       | -      | ⏳ 대기    | -        | 마지막 2시간                    |
| NPC 상호작용       | -      | ⏳ 대기    | -        | Dialogue 시스템                 |

---

**이 문서를 매일 확인하며 진행률을 업데이트하세요.**
