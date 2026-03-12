# 📋 튜토리얼 퀨스트 구현 체크리스트

> **프로젝트**: Origin-WILD  
> **버전**: 튜토리얼 퀨스트만  
> **예상 소요**: 2-3시간

---

## 🎯 전체 진행률

**전체**: `███░░░░░░` **30%** (튜토리얼 추가 구현 필요)

---

## 🔴 Step 1: 데이터 파일 (20분)

**목표**: TutorialQuestData.lua 작성

- [ ] `src/ReplicatedStorage/Data/TutorialQuestData.lua` 생성
  - [ ] TUTORIAL_HARVEST (자원 수확 3번)
  - [ ] TUTORIAL_CRAFT_PICKAXE (곡괭이 제작)
  - [ ] TUTORIAL_BUILD_CAMPFIRE (캠프파이어 건설)
  - [ ] TUTORIAL_CAPTURE_DODO (도도 포획)
  - [ ] TUTORIAL_COMPLETE (모두 완료)
  - 각 튜토리얼에 rewards 정의 (XP, 아이템)

**참고**: TUTORIAL_QUEST_GUIDE.md의 1단계 코드 복사

---

## 🔴 Step 2: 서버 서비스 (1시간)

**목표**: TutorialQuestService.lua 구현

- [ ] `src/ServerScriptService/Server/Services/TutorialQuestService.lua` 생성
  - [ ] Init() 함수
  - [ ] \_loadPlayerTutorials() - 플레이어 튜토리얼 상태 로드
  - [ ] getTutorials() - 튜토리얼 조회
  - [ ] updateProgress() - 진행도 갱신
  - [ ] \_grantRewards() - 보상 지급
  - [ ] isAllCompleted() - 모든 튜토리얼 완료 여부 확인
  - [ ] onHarvest() - 수확 콜백
  - [ ] onCraft() - 제작 콜백
  - [ ] onBuild() - 건축 콜백
  - [ ] onCapture() - 포획 콜백
  - [ ] GetHandlers() - 네트워크 핸들러

**참고**: TUTORIAL_QUEST_GUIDE.md의 2단계 코드 복사

---

## 🔴 Step 3: 서버 연결 (40분)

**목표**: ServerInit.lua에 TutorialQuestService 연결

- [ ] **TutorialQuestService 초기화**

  ```lua
  local TutorialQuestService = require(Services.TutorialQuestService)
  TutorialQuestService.Init(NetController, SaveService, InventoryService, PlayerStatService)
  ```

- [ ] **핸들러 등록**

  ```lua
  for command, handler in pairs(TutorialQuestService.GetHandlers()) do
    NetController.RegisterHandler(command, handler)
  end
  ```

- [ ] **HarvestService 콜백 연결**

  ```lua
  HarvestService.SetTutorialCallback(function(userId)
    TutorialQuestService.onHarvest(userId)
  end)
  ```

- [ ] **CraftingService 콜백 연결**

  ```lua
  CraftingService.SetTutorialCallback(function(userId, recipeId)
    TutorialQuestService.onCraft(userId, recipeId)
  end)
  ```

- [ ] **BuildService 콜백 연결**

  ```lua
  BuildService.SetTutorialCallback(function(userId, facilityId)
    TutorialQuestService.onBuild(userId, facilityId)
  end)
  ```

- [ ] **PartyService 콜백 연결 (팰 포획)**

  ```lua
  PartyService.SetTutorialCallback(function(userId, creatureId)
    TutorialQuestService.onCapture(userId, creatureId)
  end)
  ```

- [ ] **기존 서비스에 콜백 함수 추가**
  - [ ] HarvestService.lua: SetTutorialCallback() + hit() 수정
  - [ ] CraftingService.lua: SetTutorialCallback() + 제작 완료 시 호출
  - [ ] BuildService.lua: SetTutorialCallback() + 건축 완료 시 호출
  - [ ] PartyService.lua: SetTutorialCallback() + 포획 완료 시 호출

---

## 🔴 Step 4: 클라이언트 (1시간)

**목표**: 클라이언트 튜토리얼 컨트롤러 & UI 구현

### 4.1 TutorialController 생성

- [ ] `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.lua` 생성
  - [ ] Init() - 서버 상태 요청
  - [ ] requestStatus() - 서버에서 전체 튜토리얼 조회
  - [ ] getTutorials() - 로컬 캐시 조회
  - [ ] getProgress() - 특정 튜토리얼 진행도
  - [ ] onCompleted() - 이벤트 리스너 등록
  - [ ] 서버 이벤트 수신 (Tutorial.Completed)

**참고**: TUTORIAL_QUEST_GUIDE.md의 4.1 코드 복사

### 4.2 TutorialUI 생성

- [ ] `src/StarterPlayer/StarterPlayerScripts/Client/UI/TutorialUI.lua` 생성
  - [ ] Create() - UI 화면 생성
  - [ ] Update() - 튜토리얼 진행도 표시
  - [ ] Destroy() - UI 정리
  - UI 배치: 오른쪽 상단 (300×150)
  - 각 튜토리얼별 상태 표시 (✅ 완료 / ⏳ 진행 중)

**참고**: TUTORIAL_QUEST_GUIDE.md의 4.2 코드 복사

### 4.3 ClientInit 수정

- [ ] ClientInit.client.lua에 TutorialController 추가

  ```lua
  local TutorialController = require(Controllers.TutorialController)
  TutorialController.Init()
  ```

- [ ] ClientInit.client.lua에 TutorialUI 추가
  ```lua
  local TutorialUI = require(Client.UI.TutorialUI)
  TutorialUI.Create(script.Parent.Parent.PlayerGui)
  ```

---

## ✅ 테스트 체크리스트

- [ ] **Rojo 동기화** 확인
  - [ ] Studio 콘솔에 "[TutorialQuestService] Initialized" 로그 표시
  - [ ] 클라이언트 UI "튜토리얼" 띠 표시됨

- [ ] **신규 플레이어 테스트**
  - [ ] 새 캐릭터로 게임 시작
  - [ ] 튜토리얼 상태가 자동으로 부여됨
  - [ ] 각 단계마다 UI 업데이트 확인

- [ ] **단계별 완료 테스트**
  - [ ] 나무 3번 수확 → TUTORIAL_HARVEST 완료 + UI ✅ 표시
  - [ ] 곡괭이 제작 → TUTORIAL_CRAFT_PICKAXE 완료 + XP 획득
  - [ ] 캠프파이어 건설 → TUTORIAL_BUILD_CAMPFIRE 완료 + XP 획득
  - [ ] 도도 포획 → TUTORIAL_CAPTURE_DODO 완료 + PAL_SPHERE 획득
  - [ ] 모든 단계 완료 → TUTORIAL_COMPLETE 완료 + 최종 보상

- [ ] **보상 검증**
  - [ ] 각 단계별 XP 획득 확인
  - [ ] TECHPOINT 증가 확인
  - [ ] 아이템 인벤토리 추가 확인

---

## 📊 진행 기록

| 단계     | 작업                         | 상태    | 예상 시간     | 완료 시간 |
| -------- | ---------------------------- | ------- | ------------- | --------- |
| 1        | TutorialQuestData.lua        | ⏳ 대기 | 20분          | -         |
| 2        | TutorialQuestService.lua     | ⏳ 대기 | 1시간         | -         |
| 3        | 서버 연결 (콜백)             | ⏳ 대기 | 40분          | -         |
| 4        | 클라이언트 (Controller + UI) | ⏳ 대기 | 1시간         | -         |
| 5        | 테스트 & 버그 수정           | ⏳ 대기 | 30분          | -         |
| **총계** | -                            | ⏳ 대기 | **2.5-3시간** | -         |

---

## 🎯 완료 조건 (DoD)

✅ **완료 기준**:

- [ ] 신규 플레이어가 게임 시작하면 튜토리얼 자동 부여
- [ ] 각 단계마다 자동 진행도 갱신
- [ ] UI에서 완료/진행 상태 시각화
- [ ] 완료 시 보상 (XP, 아이템) 지급
- [ ] ServerLog에 오류 없음
- [ ] 클라이언트 콘솔에 오류 없음

---

## 🚀 다음 단계 (구현 후)

✅ **튜토리얼 퀨스트 완성 후**:

1. Phase 9 (NPC 상점) 완성 (6-8시간)
2. NPC 상호작용 구현 (4-5시간)
3. 클라이언트 UI 최적화 (4-5시간)

---

**이 체크리스트를 따라 진행하면 2-3시간 안에 튜토리얼 퀨스트 완성!**

**📖 상세 구현 코드는 `TUTORIAL_QUEST_GUIDE.md` 참고**
