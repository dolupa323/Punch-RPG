# 📝 프로젝트 전반 구조 및 인수인계 문서 (Roblox RPG)

다음 세션에서 Antigravity(AI)가 전체 프로젝트 구조와 맥락을 즉시 파악하고 원활하게 작업을 이어가기 위해 작성된 **글로벌 전제 조건 및 인수인계 문서**입니다. 새로운 채팅창에서 이 문서를 읽어보라고 지시하면, 프로젝트의 기본 원리부터 최근 작업 내역까지 단번에 파악할 수 있습니다.

---

## 1. 🏗️ 프로젝트 전반 전제 조건 및 아키텍처 (Global Premises)

이 프로젝트는 일반적인 로블록스 기본 기능을 단순하게 사용하는 것을 넘어, 확장성과 보안성을 고려한 자체적인 프레임워크와 시스템 컨벤션을 사용합니다. 코드를 수정하거나 기능을 추가할 때 **반드시** 아래의 전제 조건들을 따라야 합니다.

### [A] 서버-클라이언트 네트워크 구조 (Network Architecture)
* **보안 및 명시성:** 모든 클라이언트-서버 간의 통신은 `NetController`(서버)와 `NetClient`(클라이언트)를 통해 이루어지며, **`ReplicatedStorage/Shared/Net/Protocol.lua`**에 등록된 문자열(Request/Response) 명령어만 허용하는 화이트리스트 방식을 채택하고 있습니다.
* **작업 시 주의:** UI 버튼 클릭 등으로 서버에 패킷을 보내는 신규 기능을 추가할 경우, 가장 먼저 `Protocol.lua`에 명령어(예: `["Craft.InstantComplete.Request"] = true`)를 등록해야 `Command not in Protocol` 에러가 발생하지 않습니다.

### [B] 데이터 분리 및 관리 (Data Management)
* **중앙 집중형 데이터:** 아이템 스펙, 레시피, 무기 콤보, 몬스터 스탯 등 모든 정적 데이터는 **`ReplicatedStorage/Data`** 폴더 내의 파일들(`ItemData.lua`, `RecipeData.lua`, `WeaponComboData.lua` 등)에서 중앙 집중적으로 관리됩니다.
* **접근 방식:** 스크립트에서 데이터를 조회할 때는 하드코딩하지 않고, 가급적 **`DataHelper.lua`** 모듈을 사용하여 데이터를 안전하게 불러오도록 설계되어 있습니다.

### [C] 무기 및 전투 시스템 (Combat & Avatar System)
* **액세서리 기반 전투:** 로블록스의 기본 `Tool` 객체를 손에 쥐는 구형 방식을 사용하지 않습니다. 부드러운 콤보 애니메이션과 히트박스 처리를 위해 **`AvatarService` 기반의 무기 액세서리 장착 시스템**을 사용합니다.
* **연동 필수 3박자:**
  1. `ItemData.lua`에 `modelName`과 `iconName`을 정확한 **파스칼 케이스(PascalCase)**로 입력.
  2. `WeaponComboData.lua`에 해당 무기의 `itemId`를 키값으로 콤보/데미지/쿨타임 정보 필수 등록. (누락 시 구형 Tool로 강제 렌더링되어 버그 발생)
  3. `ReplicatedStorage/Assets/ItemModels/Weapons` 폴더 하위에 3D 모델(Accessory)을 파스칼 케이스 네이밍으로 배치.

### [D] UI 시스템 구조 및 하드코딩 주의 (UI Rendering)
* **모듈화된 UI 관리:** `StarterPlayerScripts/Client/UI` 폴더 내에 `InventoryUI.lua`, `EquipmentUI.lua`, `CraftingUI.lua` 등으로 철저히 모듈화되어 있으며, 전체 렌더링 관리는 `UIManager.lua`가 통제합니다.
* **리스트 필터링 주의:** 특정 상점이나 장인 NPC의 UI를 열 때나 새로고침(Refresh)할 때, 전체 아이템을 불러오지 않고 **스크립트 내부에 특정 아이템 ID들이 하드코딩 필터링**되어 있는 경우가 존재합니다. (예: `RefreshWeaponCrafting` 함수). 아이템 추가 시 이 필터링 목록도 반드시 업데이트해야 UI에 노출됩니다.

### [E] 래거시 구조 포함 컴포넌트
* **로딩 스크린:** `ReplicatedFirst/LoadingScreen.client.lua` 파일은 로딩 애니메이션 및 로고 이미지(`LOGO_ASSET_ID`)가 하드코딩되어 동작하는 래거시 구조를 띄고 있습니다. 변경 시 기존 Tween 애니메이션들이 깨지지 않도록 유의해야 합니다.

---

## 2. 🛠 최근 주요 작업 내역 (Recent Work History)

* **신규 무기 4종 연동 및 밸런싱:** `기사의 창`, `영혼의 지팡이`, `정의의 창`, `청화창` 추가 및 상위 몬스터 기준 밸런스 데이터 셋업 완료.
* **제작 UI 편의성 개선:** 무기 장인 NPC UI에 "즉시 완료" 버튼 추가 및 서버 연동. 필터링 로직 수정으로 신규 무기들도 정상 리스트업되도록 수정.
* **UI 시인성 및 버그 픽스:** 
  * 장비/인벤토리 툴팁 내 '품질' 게이지바 길이를 축소하여 텍스트 침범 현상 완벽 해결.
  * 로딩 스크린 텍스트에 골드 컬러 적용 및 `UIStroke`(외곽선) 추가로 화려한 배경에서도 가시성 대폭 향상. 배경 이미지 화면 꽉 차게(`Crop`) 스케일 조정.
* **훈련용 허수아비 타격 피드백 변경:** 기존 UI 박스 테두리 깜빡임 로직을 제거하고, 타격 시 더미 3D 매쉬 자체에 `Highlight` 인스턴스를 부여하여 붉은색/초록색으로 직관적으로 빛나도록 개선.
