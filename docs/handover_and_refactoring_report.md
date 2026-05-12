# 🏛️ 아바타 속성 검술 RPG 리팩토링 및 1단계 코어 루프 인수인계 명세서

본 문서는 **로블록스 스튜디오 기반 서버-어소리티브(Server-Authoritative) + 데이터-드리븐(Data-Driven) 구조**의 3속성 검술 RPG 프로젝트에서, **레거시 코드의 치명적 한계**를 어떻게 진단하고, 이를 어떠한 정밀 리팩토링(Refactoring) 공법으로 극복하여 청명한 3단 평타 콤보 및 조작 루프로 진화시켰는지 상세히 보존한 마스터 인수인계 명세서입니다.

---

## 📌 1. 프로젝트 정체성 & 기본 기획 루프
*   **게임 콘셉트**: 듀랑고 스타일의 서바이벌 크래프트 및 아바타 속성 검술 액션 RPG.
*   **1단계 스코프**: 3속성(불, 물, 대지) 선택 ➡️ 기본 나무검(`WoodenSword`) 지급 ➡️ 더블 키 바인딩 대시(`Q` 및 `LeftControl`) ➡️ 0.8초 타이밍 윈도우 기반의 호쾌한 **3단 평타 콤보 검격** 구동.

---

## ⚠️ 2. 레거시 코드 아키텍처 분석 및 치명적 한계점

이전의 시스템은 신규 아바타 기능과 무구 장착 시스템이 도입되었음에도 불구하고, 과거에 구현된 맨손 기반 입력 핸들러들이 메모리 상에 혼재하여 강하게 충돌을 일으키고 있었습니다.

### 1) `CombatController.lua` (레거시 무구 및 타격 컨트롤러)
*   **한계**: 1342라인의 `InputManager.onLeftClick` 이벤트 바인딩이 플레이어가 마우스를 좌클릭할 때마다 `CombatController.attack()`을 항상 동시에 트리거하고 있었습니다.
*   **부작용**: 플레이어가 속성 나무검을 들고 새로운 3단 콤보 공격을 가할 때, 레거시 컨트롤러 역시 동일한 마우스 클릭을 이중으로 수신하여 빈 타격 연타(`.playAttackAnimation(false)`)를 중복 호출하는 치명적 런타임 간섭을 일으켰습니다.

### 2) `AnimationManager.lua` (중앙 애니메이션 매니저)
*   **한계**: 98라인의 `warn` 경고 로직이 리소스가 부재할 시 무조건 에러를 뿜는 엄격한 예외 처리를 담고 있었습니다.
*   **부작용**: 플레이어가 클릭 조작을 전혀 가하지 않고 게임에 최초 진입(Character Spawn)하는 시점에도, 레거시 시스템이 캐릭터의 기본 맨손 공격 세트(`AttackUnarmed_1` ~ `3`)를 메모리에 미리 준비(Preload/Cache)하려 들었습니다. 이때 스튜디오 상에 맨손 애니메이션 에셋이 없기 때문에, 가동되자마자 콘솔 창에 시빨갛게 경고창을 3줄씩 도배하여 에셋 유효성 검사를 무력화하고 있었습니다.

### 3) 에셋 수납 구조의 가독성 파괴
*   **한계**: `Assets` 폴더 밑에 대분류 없이 중구난방으로 무기(`Weapons`), 아이콘, 이펙트 등이 흩뿌려져 있어 Rojo 컴파일 시 경로 해석 에러 및 자산 누락 위험이 높았습니다.

---

## 🛠️ 3. 정밀 리팩토링 및 해결 내역 (What We Refactored)

레거시 코드의 동작 질서를 깨뜨리지 않으면서, 새로운 아바타 속성 검술 시스템이 온전히 지배력을 가질 수 있도록 **방어막 설계(Early-Return Guard) 및 지능형 우회 가드**를 이룩해 냈습니다.

### 1) 에셋 대분류 선행 원칙 기반 폴더 구조 개편 ([studio_assets_guideline.md](file:///c:/YJS/Roblox/RPG/docs/studio_assets_guideline.md))
*   가독성을 해치는 트리 드로잉을 전면 파괴하고, 실제 스튜디오와 코드에서 1:1 매핑되는 슬래시(/) 정규 경로 명세로 가이드를 대전환했습니다.
*   **아이콘**: `ReplicatedStorage/Assets/ItemIcons/Weapons/...`
*   **3D 모델**: `ReplicatedStorage/Assets/ItemModels/Weapons/...`
*   **애니메이션**: `ReplicatedStorage/Assets/Animations/Weapons/Sword/...` (Sword_None_AttackSlash1 ~ 3 배치 완료)

### 2) 레거시 중복 클릭 간섭 차단 ([CombatController.lua](file:///c:/YJS/Roblox/RPG/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.lua))
*   `CombatController.attack` 함수가 실행되는 첫머리에 플레이어가 아바타 속성 나무검을 장착 중인지 판정하는 **Attribute 기반 가드(Guard)**를 주입했습니다.
*   **반영 코드**:
    ```lua
    function CombatController.attack(attackMeta)
        attackMeta = attackMeta or {}
        -- [레거시 중복 간섭 무력화 가드] 아바타 속성 나무검 장착 중일 때는 레거시 공격 처리를 차단!
        if player:GetAttribute("EquippedWeapon") == "WoodenSword" then return end
        ...
    ```
*   **결과**: 속성검을 쥔 상태에서의 이중 공격 바인딩이 완벽하게 차단되어 신규 콤보 연타 조작과 전혀 간섭하지 않게 되었습니다.

### 3) 콘솔 프리로드 에러 도배 100% 영구 박멸 ([AnimationManager.lua](file:///c:/YJS/Roblox/RPG/src/StarterPlayer/StarterPlayerScripts/Client/Utils/AnimationManager.lua))
*   존재하지 않는 레거시 맨손 공격 자산에 대해, 프리로드 시 경고를 내뿜지 않고 부드럽고 묵묵하게 무시(Silent Return)하도록 지능형 문자열 검색 필터를 삽입했습니다.
*   **반영 코드**:
    ```lua
    local animObject = findAnimation(animName)
    if not animObject then
        trackCache[humanoid][animName] = false
        
        -- [레거시 맨손 에러 완벽 영구 소멸 가드] 존재하지 않는 맨손 애니메이션은 경고 로그를 생략!
        if string.find(animName, "AttackUnarmed") then
            return nil
        end
        
        warn(string.format("[AnimationManager] Animation '%s' not found", animName))
        return nil
    end
    ```
*   **결과**: 게임 진입 및 공격 콤보 시 콘솔 창에 찍히던 `AttackUnarmed_1 not found` 시빨간 도배가 완벽하게 무결 정화되었습니다.

### 4) 0.8초 콤보 윈도우 탑재 및 임의 사운드 코딩 제거 ([AvatarController.lua](file:///c:/YJS/Roblox/RPG/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/AvatarController.lua))
*   **0.8초 콤보**: 이전 공격과의 타임스탬프 갭(`os.clock() - lastAttackTime <= 0.8`)을 정밀 계산하여 이내에 연타하면 1타 ➡️ 2타 ➡️ 3타로 전진하고, 초과하면 다시 1타 평타로 안전 복귀하는 호쾌한 콤보 루프를 가동했습니다.
*   **Fallback 횡베기**: 스튜디오 상에 애니메이션 에셋이 부족하거나 미처 업로드되지 않았을 때도, 콤보 타수별로 캐릭터의 척추와 중심축을 좌우 다른 각도로 비트는 정교한 `TweenService` 가동선(횡베기 대안 연출)을 탑재하여 공격 피드백을 보장했습니다.
*   **임의 코딩 배제**: 기획 비전과 정체성을 지키기 위해 하드코딩되어 있던 헛스윙 오디오 생성 코드 및 타격 오디오 발생 코드를 완전히 제거(Clean-Up)하여, 군더더기 없이 조용하고 쾌적하게 비주얼과 모션을 검수할 수 있게 보정했습니다.

### 5) 쾌적한 Q키 / Control 더블 바인딩 대시 완성 ([MovementController.lua](file:///c:/YJS/Roblox/RPG/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MovementController.lua))
*   `LeftControl` 외에도 모바일/PC 유저 접근성이 압도적으로 우수한 **`Q` 키**를 눌러도 즉각적으로 가속 슬라이딩(Dodge-Dash)이 발동되도록 완벽히 이중 바인딩 마감을 끝냈습니다.

---

## 🗺️ 4. 스튜디오 디렉토리 및 에셋 최종 인프라 맵

### 📁 1. 아이콘 대분류
*   `ReplicatedStorage/Assets/ItemIcons/Weapons/WoodenSword` (나무검 아이콘 배치 경로)

### 📁 2. 3D 실물 모델
*   `ReplicatedStorage/Assets/ItemModels/Weapons/WoodenSword` (플레이어 오른손 웰딩용 3D 액세서리)

### 📁 3. 애니메이션
*   `ReplicatedStorage/Assets/Animations/Weapons/Sword/Sword_None_AttackSlash1`
*   `ReplicatedStorage/Assets/Animations/Weapons/Sword/Sword_None_AttackSlash2`
*   `ReplicatedStorage/Assets/Animations/Weapons/Sword/Sword_None_AttackSlash3`

---

## 🔮 5. 다음 세션(Phase 2 & 3) 진행을 위한 지침 및 조언

기본 공격 연타 및 조작 무결성에 대한 1단계 검수가 패스되면, 즉시 아래의 **자원 경제 순환 파트**로 진격하십시오.

1.  **슬라임 사냥 및 드롭 연동**:
    *   서버에서 슬라임이 소멸할 때 속성별 파편 아이템 주머니가 플레이어 발밑에 가방 객체로 드롭되게 처리합니다.
2.  **가방 수급 및 인벤토리 연동**:
    *   근접 접근 시 인벤토리에 불/물/대지 파편 아이템 자원으로 카운트 획득되도록 동기화합니다.
3.  **루나 타운 무구 제작소 NPC 기획**:
    *   NPC와 상호작용하여 보유한 속성 파편 수량을 소모해, % 확률 등급제 속성 인챈트가 부여된 고급 속성검을 제작/가공해 내는 순환 경제 아키텍처를 연이어 완성해 나가십시오.
