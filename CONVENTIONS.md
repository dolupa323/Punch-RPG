# WildForge 개발 컨벤션 및 준수 사항

## 1. 스튜디오 네이밍 규칙 (Studio Naming Convention)
로블록스 스튜디오 내의 모든 오브젝트(Model, Accessory, Decal 등)는 **PascalCase**를 사용합니다.
- **예시**: `Dobok`, `WoodenStaff`, `BronzeAxe`, `IronHelmet`

## 2. 에셋 경로 규칙 (Asset Paths)
모든 게임 에셋은 `ReplicatedStorage/Assets` 하위의 정해진 폴더에 분류하여 배치합니다.

### 아이템 아이콘 (Item Icons)
- **경로**: `Assets/ItemIcons/[Category]/[ItemName]`
- **예시**: `Assets/ItemIcons/Armor/Dobok`
- **검색 방식**: 스크립트에서 하위 폴더를 포함하여 재귀적으로 검색합니다.

### 아이템 모델 (Item Models)
- **경로**: `Assets/ItemModels/[Category]/[ItemName]`
- **예시**: `Assets/ItemModels/Armor/Dobok`
- **검색 방식**: 스크립트에서 하위 폴더를 포함하여 재귀적으로 검색합니다.

## 3. 코드 데이터 규칙 (Data ID Convention)
`ItemData.lua` 등 스크립트 내에서 사용하는 ID는 **UPPER_SNAKE_CASE**를 사용합니다.
- **예시**: `DOBOK`, `WOODEN_STAFF`, `BRONZE_AXE`
- **주의**: 스튜디오 에셋 매핑 필드(`modelId`, `modelName`, `iconName`)에는 반드시 위의 **PascalCase** 이름을 입력해야 합니다.

## 4. 시스템 주요 규칙
### 핫바 (QuickSlot) 시스템
- **등록 제한**: 오직 소모품(`FOOD`) 및 즉시 사용 가능한 아이템만 등록할 수 있습니다.
- **차단 대상**: 무기(`WEAPON`), 도구(`TOOL`), 재료(`RESOURCE`) 등은 등록이 불가능합니다.
- **중복 방지**: 동일한 아이템을 다른 슬롯에 등록할 경우, 이전 슬롯은 자동으로 비워집니다 (Single Source of Truth).

### 스타팅 아이템 (Starter Equipment)
- **기본 지급**: 모든 플레이어(신규 및 기존)는 접속 시 다음 아이템을 기본으로 장착합니다.
    - **무기(HAND)**: `WOODEN_STAFF` (나무봉)
    - **방어구(SUIT)**: `DOBOK` (도복)
- **보정 로직**: `SaveService.lua`에서 해당 슬롯이 비어있을 경우 자동으로 채워줍니다.

## 5. 아바타 및 장비 시각화
- **무기**: `AvatarService`가 `Accessory` 시스템을 통해 장착을 관리합니다.
- **방어구**: `EquipService`가 `Shirt`, `Pants` 텍스처 및 `Accessory` 모델을 제어하며, 캐릭터 스폰 시 자동으로 `updateAppearance`를 호출합니다.
