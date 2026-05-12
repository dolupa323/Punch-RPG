# 🎮 아바타 검술 RPG 공식 에셋 경로 및 네이밍 규칙 가이드
> **문서 코드**: `Avatar-Asset-Convention-v1.3`  
> **상태**: 대분류 선행 및 유스케이스 확장 구조 완전 고정 완료  
> **개정 취지**: 에셋의 성격에 따른 대분류(`ItemIcons`, `ItemModels`, `Animations`, `Monsters`)를 최상위 분기점으로 고정하고, 하위에 사용처 유스케이스(`Weapons`, `Tools` 등)를 세분화하여 격리 수납함으로써 대규모 확장 시의 가독성을 극대화함.

---

## 📁 1. 로블록스 스튜디오 에셋 정규 경로 구조 (Slash-Based Path Structure)

실제 스튜디오 탐색기(Explorer) 및 코드에서 무결하게 접근할 수 있는 최첨단 경로 명세입니다.

### A. 애니메이션 대분류 (Animations)
*   공통 대시 모션: `ReplicatedStorage/Assets/Animations/Movement/Movement_Dash`
*   공통 피격 모션: `ReplicatedStorage/Assets/Animations/Movement/Interact_Hit`
*   검 기본 평타: `ReplicatedStorage/Assets/Animations/Weapons/Sword/Sword_None_AttackSlash`
*   검 불 스킬 1 (화염 베기): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Fire/Sword_Fire_FlameSlash`
*   검 불 스킬 2 (화염 폭풍): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Fire/Sword_Fire_FireStorm`
*   검 불 스킬 3 (일섬 돌파): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Fire/Sword_Fire_SunBurst`
*   검 물 스킬 1 (파도 베기): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Water/Sword_Water_WaveCut`
*   검 물 스킬 2 (해일 찌르기): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Water/Sword_Water_TorrentThrust`
*   검 물 스킬 3 (격류 폭풍): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Water/Sword_Water_Vortex`
*   검 흙 스킬 1 (대지 내려치기): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Earth/Sword_Earth_StoneSmash`
*   검 흙 스킬 2 (바위 장벽): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Earth/Sword_Earth_RockShield`
*   검 흙 스킬 3 (지진파 방출): `ReplicatedStorage/Assets/Animations/Weapons/Sword/Earth/Sword_Earth_QuakeWave`

### B. 아이템 실물 3D 모델 대분류 (ItemModels)
*   나무검 실물 액세서리: `ReplicatedStorage/Assets/ItemModels/Weapons/WoodenSword`
*   돌검 실물 액세서리: `ReplicatedStorage/Assets/ItemModels/Weapons/StoneSword`
*   철검 실물 액세서리: `ReplicatedStorage/Assets/ItemModels/Weapons/IronSword`
*   미라 슬레이어 실물 액세서리: `ReplicatedStorage/Assets/ItemModels/Weapons/MummySlayer`
*   혈도 카타나 실물 액세서리: `ReplicatedStorage/Assets/ItemModels/Weapons/BloodKatana`

### C. 아이템 2D UI 아이콘 대분류 (ItemIcons)
*   나무검 2D 아이콘 데칼: `ReplicatedStorage/Assets/ItemIcons/Weapons/WoodenSword`
*   돌검 2D 아이콘 데칼: `ReplicatedStorage/Assets/ItemIcons/Weapons/StoneSword`
*   철검 2D 아이콘 데칼: `ReplicatedStorage/Assets/ItemIcons/Weapons/IronSword`
*   미라 슬레이어 2D 아이콘 데칼: `ReplicatedStorage/Assets/ItemIcons/Weapons/MummySlayer`
*   혈도 카타나 2D 아이콘 데칼: `ReplicatedStorage/Assets/ItemIcons/Weapons/BloodKatana`

### D. 필드 몬스터 3D 모델 대분류 (Monsters)
*   하급 슬라임 3D 모델: `ReplicatedStorage/Assets/Monsters/Slime`
*   하급 고블린 3D 모델: `ReplicatedStorage/Assets/Monsters/Goblin`
*   갑옷 고블린 보스 모델: `ReplicatedStorage/Assets/Monsters/ArmoredGoblin`
*   사막 미라 3D 모델: `ReplicatedStorage/Assets/Monsters/Mummy`
*   사무라이 보스 3D 모델: `ReplicatedStorage/Assets/Monsters/BloodlessSamurai`

---

## 👑 2. 무기 액세서리 내부 조립 명세

무기는 100% `Accessory` 인스턴스 형식을 따르며, 인스턴스 내부의 명칭과 관계는 아래의 엄격한 규격을 준수합니다.

*   액세서리 최상위: `[무기명]` (예: `WoodenSword`)
*   최상위 바로 밑 손잡이 파트: `Handle` (MeshPart 또는 Part)
*   손잡이 파트 바로 밑 어태치먼트: `RightGripAttachment` (Attachment)

이 세 가지 명칭과 계층 구조가 어긋나면 무기 자동 장착 시 런타임 에러가 발생합니다.

---

## 🎬 3. 동적 스킬 애니메이션 네이밍 수식

스킬 애니메이션 객체의 이름은 단축키 장착 변경 시 동적으로 자동 로드될 수 있도록 아래 명구 명칭 포맷을 사용합니다.

$$\text{Name} = \text{[WeaponType]} \mathbin{\_} \text{[ElementPrefix]} \mathbin{\_} \text{[SkillID]}$$

*   `WeaponType`: 무기의 대분류 (예: `Sword`, `Spear`, `Bow`, `Hammer`)
*   `ElementPrefix`: 속성의 한글/영문 매핑 Prefix (예: `Fire`, `Water`, `Earth`, `None`)
*   `SkillID`: 스킬의 고유 식별 명칭 (예: `FlameSlash`, `WaveCut`, `StoneSmash` 등)
