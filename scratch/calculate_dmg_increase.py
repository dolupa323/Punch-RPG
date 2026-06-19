# calculate_dmg_increase.py
import sys
import math

def get_enhance_rate(rarity):
    return 0.15

weapons = [
    {"id": "WOODEN_STAFF", "name": "나무봉", "dmg": 10, "rarity": "COMMON"},
    {"id": "SoftClub", "name": "슬라임검", "dmg": 54, "rarity": "UNCOMMON"},
    {"id": "Gakchang", "name": "단단한 검", "dmg": 107, "rarity": "UNCOMMON"},
    {"id": "Mogwoldo", "name": "사막의 검", "dmg": 170, "rarity": "UNCOMMON"},
    {"id": "POISON_HORN_SPEAR", "name": "사막의 밤", "dmg": 246, "rarity": "RARE"},
    {"id": "IronStaff", "name": "철검", "dmg": 337, "rarity": "RARE"},
    {"id": "KATANA", "name": "카타나", "dmg": 446, "rarity": "RARE"},
    {"id": "FangSpear", "name": "뱀파이어 소드", "dmg": 577, "rarity": "EPIC"},
    {"id": "ICE_SWORD", "name": "아이스 소드", "dmg": 734, "rarity": "EPIC"},
    {"id": "KNIGHT_SWORD", "name": "나이트 소드", "dmg": 923, "rarity": "EPIC"},
    {"id": "SOUL_SWORD", "name": "소울 소드", "dmg": 1150, "rarity": "EPIC"},
    {"id": "SWORD_OF_JUSTICE", "name": "저스티스 소드", "dmg": 1422, "rarity": "EPIC"},
    {"id": "BLUE_FLAME_SWORD", "name": "블루파이어 소드", "dmg": 1748, "rarity": "UNIQUE"},
]

def get_min_damage(index):
    if index == 0:
        return math.floor(weapons[0]["dmg"] * 0.5)
    prev_max_dmg = weapons[index - 1]["dmg"]
    return math.floor(prev_max_dmg * 0.9)

def calc_quality_dmg(index, quality):
    max_dmg = weapons[index]["dmg"]
    min_dmg = get_min_damage(index)
    adjusted_dmg = min_dmg + (max_dmg - min_dmg) * (quality / 100)
    return math.floor(adjusted_dmg)

def calc_dmg(base_dmg, rarity, enhance_lv):
    rate = get_enhance_rate(rarity)
    return (210 + base_dmg) * (1.0 + enhance_lv * rate)

def main():
    # 1. 품질별 무기 공격력 및 최종 데미지 시뮬레이션
    md = "# 무기 품질 보정 공격력 및 최종 데미지 시뮬레이션 결과\n\n"
    md += "품질 0%, 50%, 100% 조건에 따라 보정된 무기 공격력 및 전투 시 최종 기본 데미지 수치입니다.\n\n"
    
    md += "## [1] 품질별 무기 자체 표기 공격력\n\n"
    md += "| 무기 이름 | 기본 공격력 (100%) | 품질 0% 일 때 (최소) | 품질 50% 일 때 | 품질 100% 일 때 (최대) |\n"
    md += "| :--- | :---: | :---: | :---: | :---: |\n"
    
    for i, w in enumerate(weapons):
        dmg_0 = calc_quality_dmg(i, 0)
        dmg_50 = calc_quality_dmg(i, 50)
        dmg_100 = calc_quality_dmg(i, 100)
        md += f"| {w['name']} | {w['dmg']} | **{dmg_0}** | **{dmg_50}** | **{dmg_100}** |\n"
        
    md += "\n## [2] 품질별 전투 시 최종 기본 데미지 (210 보정 적용)\n\n"
    md += "| 무기 이름 | 품질 0% 일 때 | 품질 50% 일 때 | 품질 100% 일 때 |\n"
    md += "| :--- | :---: | :---: | :---: |\n"
    
    for i, w in enumerate(weapons):
        dmg_0 = calc_quality_dmg(i, 0)
        dmg_50 = calc_quality_dmg(i, 50)
        dmg_100 = calc_quality_dmg(i, 100)
        
        final_0 = 210 + dmg_0
        final_50 = 210 + dmg_50
        final_100 = 210 + dmg_100
        md += f"| {w['name']} | **{final_0}** | **{final_50}** | **{final_100}** |\n"

    # 2. 기존 티어별 데미지 상승률 분석 (강화 단계별 비교 - 품질 100% 기준)
    md += "\n\n# 무기 티어별 데미지 상승률 분석 (품질 100% 기준)\n\n"
    md += "| 비교 구간 | 무기 A (데미지/등급) | 무기 B (데미지/등급) | +0강 시 상승률 | +3강 시 상승률 | +5강 시 상승률 |\n"
    md += "| :--- | :--- | :--- | :---: | :---: | :---: |\n"
    
    for i in range(len(weapons) - 1):
        w1 = weapons[i]
        w2 = weapons[i+1]
        
        # 0강
        d1_0 = calc_dmg(w1['dmg'], w1['rarity'], 0)
        d2_0 = calc_dmg(w2['dmg'], w2['rarity'], 0)
        inc_0 = (d2_0 / d1_0 - 1.0) * 100
        
        # +3강
        d1_3 = calc_dmg(w1['dmg'], w1['rarity'], 3)
        d2_3 = calc_dmg(w2['dmg'], w2['rarity'], 3)
        inc_3 = (d2_3 / d1_3 - 1.0) * 100
        
        # +5강
        d1_5 = calc_dmg(w1['dmg'], w1['rarity'], 5)
        d2_5 = calc_dmg(w2['dmg'], w2['rarity'], 5)
        inc_5 = (d2_5 / d1_5 - 1.0) * 100
        
        label = f"{w1['name']} -> {w2['name']}"
        w1_info = f"{w1['dmg']} / {w1['rarity']}"
        w2_info = f"{w2['dmg']} / {w2['rarity']}"
        md += f"| {label} | {w1_info} | {w2_info} | {inc_0:.2f}% | {inc_3:.2f}% | {inc_5:.2f}% |\n"

    with open('scratch/dmg_increase.md', 'w', encoding='utf-8') as f:
        f.write(md)
    print("Done! Output written to scratch/dmg_increase.md")

if __name__ == "__main__":
    main()
