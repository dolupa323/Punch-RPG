# 무기 및 도구 전체 구조 분석

이 문서는 `ItemData.lua`와 `WeaponComboData.lua` 파싱 결과를 바탕으로 작성되었습니다.

## 1. 무기/도구 목록

| ID | 이름 | 구분 | 등급 | 데미지(Item) | 데미지(Combo) | 공격속도(Combo) | 내구도 | 슬롯 | 무기유형(Optimal) | 모델명 | 설명 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `CRUDE_STONE_AXE` | **조잡한 돌도끼** | TOOL | COMMON | 20 | N/A | N/A | 30 | HAND | AXE | StoneAxe | 가는 나무 타격 시 데미지를 줌. 내구도 0 시 완전 파괴. (수리 불가) |
| `CRUDE_STONE_PICKAXE` | **조잡한 돌곡괭이** | TOOL | COMMON | 15 | N/A | N/A | 30 | HAND | PICKAXE | StonePickaxe | 무른 바위 타격 시 (스탯+15)의 데미지를 줌. 내구도 0 시 완전 파괴. (수리 불가) |
| `FIRM_STONE_AXE` | **돌도끼** | TOOL | UNCOMMON | 32 | N/A | N/A | 150 | HAND | AXE | FirmStoneAxe | 통나무와 돌을 견고하게 엮어 만든 도끼. 전투와 채집 겸용. 내구도 0 시 파괴. (수리 불가) |
| `FIRM_STONE_PICKAXE` | **돌곡괭이** | TOOL | UNCOMMON | 12 | N/A | N/A | 150 | HAND | PICKAXE | FirmStonePickaxe | 돌을 효율적으로 캘 수 있는 단단한 곡괭이. 내구도 0 시 파괴. (수리 불가) |
| `BONE_SWORD` | **뼈검** | WEAPON | UNCOMMON | 35 | N/A | N/A | 150 | HAND | SWORD | BONE_SWORD | 짐승의 뼈를 덧대어 사냥 효율이 급상승하는 본격적인 검 무기. (수리 불가) |
| `STONE_SICKLE` | **돌 낫** | TOOL | COMMON | 5 | N/A | N/A | 100 | HAND | SICKLE | N/A | 풀을 효율적으로 벨 수 있는 기본 도구. (수리 불가) |
| `TORCH` | **횃불** | TOOL | COMMON | 5 | N/A | N/A | 60 | HAND | N/A | N/A | 시야 확보 및 체온 유지. 내구도 0 시 파괴. (수리 불가) |
| `SoftClub` | **슬라임검** | WEAPON | UNCOMMON | 30 | 30 | 0.38 | 200 | HAND | CLUB | SoftClub | 슬라임 점액으로 만든 말랑말랑한 검입니다. 생각보다 아프다. |
| `Gakchang` | **단단한 검** | WEAPON | UNCOMMON | 45 | 45 | 0.38 | 250 | HAND | SPEAR | Gakchang | 뿔 애벌레의 단단한 뿔을 나뭇가지 끝에 엮어 만든 가볍고 날카로운 검입니다. |
| `FangSpear` | **뱀파이어 소드** | WEAPON | EPIC | 170 | 170 | 0.38 | 300 | HAND | SPEAR | FangSpear | 늑대의 송곳니와 슬라임 점액을 단단하게 굳혀 만든 치명적인 검입니다. |
| `IronStaff` | **철검** | WEAPON | RARE | 100 | 100 | 0.38 | 500 | HAND | CLUB | IronStaff | 골렘의 돌조각과 늑대의 송곳니를 제련해 만든 강력한 철검입니다. 뼈를 부수는 타격감을 자랑합니다. |
| `POISON_HORN_SPEAR` | **사막의 밤** | WEAPON | RARE | 80 | 80 | 0.38 | 600 | HAND | SPEAR | PoisonHornSpear | 골렘의 돌조각과 맹독 거미의 단단한 다리를 결합하여 벼려낸 치명적인 검입니다. 벨 때마다 맹독의 기운을 뿜어냅니다. |
| `KNIGHT_SWORD` | **나이트 소드** | WEAPON | EPIC | 280 | 280 | 0.38 | 800 | HAND | SWORD | KnightSword | 유령기사들의 원념이 깃든 날카로운 검. 벨 때마다 서늘한 한기가 느껴진다. |
| `SOUL_SWORD` | **소울 소드** | WEAPON | EPIC | 350 | 350 | 0.38 | 800 | HAND | SWORD | SoulSword | 유령 마법사들이 다루던 영혼의 기운을 응축시킨 마법 검. 마력이 흘러넘친다. |
| `SWORD_OF_JUSTICE` | **저스티스 소드** | WEAPON | EPIC | 450 | 450 | 0.38 | 1000 | HAND | SWORD | SwordOfJustice | 거인 유령기사의 꺾이지 않은 긍지가 담긴 거대한 검. 강력한 파괴력을 자랑한다. |
| `BLUE_FLAME_SWORD` | **블루파이어 소드** | WEAPON | UNIQUE | 600 | 600 | 0.38 | 1200 | HAND | SWORD | BlueFlameSword | 푸른 불꽃 기사의 타오르는 검. 서늘하고도 맹렬한 푸른 불꽃이 깃들어 있다. |
| `KATANA` | **카타나** | WEAPON | RARE | 130 | 130 | 0.38 | 600 | HAND | SWORD | Katana | 동방의 무사들이 사용하던 외날의 곡도. 빠르고 정교한 베기가 가능합니다. |
| `ICE_SWORD` | **아이스 소드** | WEAPON | EPIC | 220 | 220 | 0.38 | 700 | HAND | SWORD | IceSword | 만년설의 기운과 드래곤의 힘이 깃든 얼음 검. 벨 때마다 상대의 골수에 시린 한기를 심어줍니다. |
| `WOODEN_CLUB` | **나무 몽둥이** | WEAPON | COMMON | 15 | N/A | N/A | 120 | HAND | CLUB | N/A | 야수를 때려서 기절시키거나 체력을 깎는 둔기. (수리 불가) |
| `WOODEN_BOW` | **나무 활** | WEAPON | COMMON | 40 | N/A | N/A | 150 | HAND | BOW | N/A | 원거리 공격이 가능한 기초적인 활. (수리 불가) |
| `STONE_HOE` | **돌 괭이** | TOOL | COMMON | 5 | N/A | N/A | 100 | HAND | N/A | STONE_HOE | 농경지 개간용 기초 도구. (수리 불가) |
| `BRONZE_PICKAXE` | **청동 곡괭이** | TOOL | UNCOMMON | 25 | N/A | N/A | 250 | HAND | PICKAXE | BronzePickaxe | 더 단단한 광석을 캘 수 있는 청동 곡괭이. (수리 불가) |
| `BRONZE_AXE` | **청동 도끼** | TOOL | UNCOMMON | 80 | N/A | N/A | 250 | HAND | AXE | BronzeAxe | 전투와 벌목 모두 향상된 청동 도끼. (수리 불가) |
| `BRONZE_SWORD` | **청동 검** | WEAPON | UNCOMMON | 75 | N/A | N/A | 250 | HAND | SWORD | BronzeSword | 공격력이 향상된 청동 검. (수리 불가) |
| `BRONZE_BOW` | **청동 활** | WEAPON | UNCOMMON | 90 | N/A | N/A | 300 | HAND | BOW | N/A | 안정적인 사격이 가능한 청동 활. (수리 불가) |
| `IRON_PICKAXE` | **철 곡괭이** | TOOL | RARE | 50 | N/A | N/A | 500 | HAND | PICKAXE | IronPickaxe | 모든 광석을 캘 수 있는 가장 강력한 곡괭이. (수리 불가) |
| `IRON_AXE` | **철 도끼** | TOOL | RARE | 120 | N/A | N/A | 500 | HAND | AXE | IronAxe | 최고의 전투·벌목 성능을 자랑하는 철 도끼. (수리 불가) |
| `IRON_SWORD` | **철 검** | WEAPON | RARE | 130 | N/A | N/A | 500 | HAND | N/A | N/A | 가장 강력한 위력을 가진 철 검. (수리 불가) |
| `CROSSBOW` | **석궁** | WEAPON | RARE | 180 | N/A | N/A | 400 | HAND | CROSSBOW | N/A | 파괴력이 높고 조준이 쉬운 기계식 무기. (수리 불가) |
| `OBSIDIAN_AXE` | **흑요석 도끼** | TOOL | RARE | 100 | N/A | N/A | 400 | HAND | AXE | ObsidianAxe | 흑요석 날이 달린 강력한 도끼. (수리 불가) |
| `OBSIDIAN_PICKAXE` | **흑요석 곡괭이** | TOOL | RARE | 40 | N/A | N/A | 400 | HAND | PICKAXE | ObsidianPickaxe | 흑요석 날이 달린 강력한 곡괭이. (수리 불가) |
| `OBSIDIAN_SWORD` | **흑요석 검** | WEAPON | RARE | 110 | N/A | N/A | 400 | HAND | SWORD | ObsidianSword | 날카로운 흑요석 날의 검. (수리 불가) |
| `OBSIDIAN_BOW` | **흑요석 활** | WEAPON | RARE | 120 | N/A | N/A | 350 | HAND | BOW | ObsidianBow | 흑요석 강화 활. 높은 관통력을 자랑한다. (수리 불가) |
| `WOODEN_STAFF` | **나무봉** | WEAPON | COMMON | 10 | 15 | 0.38 | 999 | HAND | N/A | WoodenStaff | 기본으로 지급되는 튼튼한 나무봉입니다. |
| `Mogwoldo` | **사막의 검** | WEAPON | UNCOMMON | 60 | 60 | 0.38 | 350 | HAND | CLUB | Mogwoldo | 스텀프의 단단한 나무껍질을 깎아 만든 반달 형태의 묵직한 검입니다. 슬라임검의 부드러움을 뛰어넘는 강인한 타격력을 가졌습니다. |
