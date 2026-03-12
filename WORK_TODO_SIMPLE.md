# 🎯 Origin-WILD 미완성 작업 목록 (튜토리얼 버전)

> **작성일**: 2026-03-12 (튜토리얼 버전)  
> **목적**: 튜토리얼 퀨스트만 간단하게 구현

---

## 📋 상태 요약

| 카테고리                    | 상태         | 진행률 | 예상 시간 |
| --------------------------- | ------------ | ------ | --------- |
| **서버 인프라**             | ✅ 완료      | 100%   | -         |
| **Phase 1-7 (핵심 시스템)** | ✅ 완료      | 100%   | -         |
| **튜토리얼 퀨스트** (간단)  | ❌ 미구현    | 0%     | 2-3h      |
| **Phase 9 (NPC 상점)**      | ⚠️ 부분 완료 | 80%    | 6-8h      |
| **클라이언트 UI**           | ⚠️ 부분 완료 | 70%    | 4-5h      |
| **NPC 상호작용**            | ⚠️ 부분 완료 | 20%    | 4-5h      |

---

## 🔴 우선순위 1: 튜토리얼 퀨스트 시스템 (2-3시간)

### 📖 개요

**신규 플레이어 온보딩용 간단한 튜토리얼만 구현**

```
Level 1 시작 → 자동으로 튜토리얼 부여
  ├─ 수확 (나무 3번)
  ├─ 제작 (곡괭이)
  ├─ 건축 (캠프파이어)
  ├─ 포획 (도도)
  └─ 완료! (보상 지급)
```

**📖 상세 가이드**: `TUTORIAL_QUEST_GUIDE.md` 참고

### ✅ 구현 항목

#### Step 1: 데이터 파일 (20분)

- [ ] `TutorialQuestData.lua` 생성
  - 5가지 기본 튜토리얼 정의
  - 각각 수확, 제작, 건축, 포획, 완료

#### Step 2: 서버 서비스 (1시간)

- [ ] `TutorialQuestService.lua` 구현
  - 상태 추적 (완료/진행)
  - 진행도 갱신 콜백
  - 보상 지급

#### Step 3: 서버 연결 (40분)

- [ ] ServerInit.lua 수정
  - TutorialQuestService 초기화
  - HarvestService 콜백 연결
  - CraftingService 콜백 연결
  - BuildService 콜백 연결
  - PartyService (팰 포획) 콜백 연결

#### Step 4: 클라이언트 (1시간)

- [ ] TutorialController.lua 구현
- [ ] TutorialUI.lua 구현 (진행도 띠)
- [ ] ClientInit.lua 수정

---

## 🟡 우선순위 2: Phase 9 상점 완성 (6-8시간)

### ⚠️ 현황: 80% 완료

- [ ] NPCShopData.lua 데이터 확대
- [ ] ShopController.lua 검증
- [ ] ShopUI.lua 완성 (구매/판매 탭)
- [ ] 통합 테스트

---

## 🟡 우선순위 3: NPC 상호작용 (4-5시간)

### ⚠️ 현황: 20% 완료

- [ ] DialogueData.lua 작성
- [ ] DialogueController.lua 구현
- [ ] DialogueUI.lua 구현
- [ ] InteractController.lua 수정

---

## 🟡 우선순위 4: 클라이언트 UI 보강 (4-5시간)

### ⚠️ 현황: 70% 완료

- [ ] UIManager.lua 검증
- [ ] 기존 컨트롤러들 점검
- [ ] 필요시 새로운 UI 컴포넌트

---

## 🎯 내일 시작할 작업 (우선순위순)

1. **TutorialQuestData.lua 생성** (샘플코드는 TUTORIAL_QUEST_GUIDE.md)
2. **TutorialQuestService.lua 구현** (가장 중요)
3. **ServerInit.lua에 콜백 연결**
4. **클라이언트 UI 구현**

**이 4가지만 끝내면 튜토리얼 퀨스트 완성!**

---

**📖 상세한 구현 가이드는 `TUTORIAL_QUEST_GUIDE.md` 참고하세요.**
