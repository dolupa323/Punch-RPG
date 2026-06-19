# balance_simulation.py
import math

# --- 1. 환경 및 공식 설정 ---
BASE_XP_PER_LEVEL = 100
XP_SCALING = 1.2
MAX_LEVEL = 50
STAT_POINTS_PER_LEVEL = 3
ATTACK_PER_POINT = 0.02
BASE_PLAYER_DMG = 210

# 레벨별 필요 누적 XP 테이블 계산
def get_total_xp_for_level(level):
    if level <= 1:
        return 0
    total = 0
    for l in range(1, level):
        total += math.floor(BASE_XP_PER_LEVEL * (XP_SCALING ** (l - 1)))
    return total

def get_level_from_xp(total_xp):
    for level in range(MAX_LEVEL, 0, -1):
        if total_xp >= get_total_xp_for_level(level):
            return level
    return 1

# 몬스터 데이터 (Name, Level, HP, XP Reward, Drop Item, Avg Drop Count)
mobs = {
    "SLIME": {"name": "슬라임", "level": 3, "hp": 300, "xp": 12, "drop_avg": 2.5},
    "HORNEDLARVA": {"name": "뿔 애벌레", "level": 7, "hp": 700, "xp": 30, "drop_avg": 1.5},
    "STUMP": {"name": "스텀프", "level": 12, "hp": 1000, "xp": 85, "drop_avg": 3.0},
    "STUMPKING": {"name": "스텀프 킹(보스)", "level": 18, "hp": 4000, "xp": 320, "drop_avg": 50.0},
    "SMALLGOLEM": {"name": "작은 골렘", "level": 18, "hp": 2100, "xp": 180, "drop_avg": 2.0},
    "SAMURAI": {"name": "사무라이", "level": 23, "hp": 3000, "xp": 380, "drop_avg": 1.5},
    "CYCLOPSBAT": {"name": "사이클롭스 박쥐", "level": 28, "hp": 2400, "xp": 260, "drop_avg": 1.5},
    "ICEDRAGON": {"name": "아이스 드래곤", "level": 33, "hp": 3600, "xp": 520, "drop_avg": 1.5},
    "ICEKNIGHT": {"name": "얼음 기사", "level": 38, "hp": 4300, "xp": 750, "drop_avg": 2.5},
    "GHOSTKNIGHT": {"name": "유령기사", "level": 48, "hp": 6700, "xp": 1600, "drop_avg": 1.5},
    "GHOSTWIZARD": {"name": "유령 마법사", "level": 53, "hp": 8300, "xp": 2200, "drop_avg": 1.5},
    "GIANTGHOSTKNIGHT": {"name": "유령기사(거인)", "level": 58, "hp": 21000, "xp": 4500, "drop_avg": 2.0},
    "BLUEFLAMEKNIGHT": {"name": "푸른 불꽃 기사", "level": 63, "hp": 45000, "xp": 12000, "drop_avg": 2.0},
}

# 무기 데이터 (ID, Name, Dmg, Rarity, Required Material Name, Required Count)
weapons = [
    {"id": "WOODEN_STAFF", "name": "나무봉", "dmg": 10, "mob": None, "req_count": 0},
    {"id": "SoftClub", "name": "슬라임검", "dmg": 54, "mob": "SLIME", "req_count": 10},
    {"id": "Gakchang", "name": "단단한 검", "dmg": 107, "mob": "HORNEDLARVA", "req_count": 15},
    {"id": "Mogwoldo", "name": "사막의 검", "dmg": 170, "mob": "STUMP", "req_count": 30},
    {"id": "POISON_HORN_SPEAR", "name": "사막의 밤", "dmg": 246, "mob": "STUMPKING", "req_count": 100},
    {"id": "IronStaff", "name": "철검", "dmg": 337, "mob": "SMALLGOLEM", "req_count": 40},
    {"id": "KATANA", "name": "카타나", "dmg": 446, "mob": "SAMURAI", "req_count": 40},
    {"id": "FangSpear", "name": "뱀파이어 소드", "dmg": 577, "mob": "CYCLOPSBAT", "req_count": 30},
    {"id": "ICE_SWORD", "name": "아이스 소드", "dmg": 734, "mob": "ICEKNIGHT", "req_count": 40}, # 주재료는 얼음기사(빙결의 얼음)
    {"id": "KNIGHT_SWORD", "name": "나이트 소드", "dmg": 923, "mob": "GHOSTKNIGHT", "req_count": 100},
    {"id": "SOUL_SWORD", "name": "소울 소드", "dmg": 1150, "mob": "GHOSTWIZARD", "req_count": 150},
    {"id": "SWORD_OF_JUSTICE", "name": "저스티스 소드", "dmg": 1422, "mob": "GIANTGHOSTKNIGHT", "req_count": 100},
    {"id": "BLUE_FLAME_SWORD", "name": "블루파이어 소드", "dmg": 1748, "mob": "BLUEFLAMEKNIGHT", "req_count": 100},
]

def main():
    player_xp = 0
    player_level = 1
    current_weapon = weapons[0] # 시작: 나무봉
    
    report = "# 무협 아바타 RPG 유저 성장 및 몬스터 밸런스 시뮬레이션\n\n"
    report += "이 시뮬레이션은 유저가 레벨 1(나무봉 장착)에서 시작하여 각 티어 무기 제작을 위해 필요한 몬스터를 사냥하며 성장해가는 과정을 역추적합니다.\n"
    report += "- **스탯 투자**: 획득하는 모든 스탯 포인트는 공격(ATTACK)에 올인한다고 가정합니다. (`attackMult = 1.0 + 레벨업수 * 3 * 0.02`)\n"
    report += "- **데미지 보정**: 플레이어와 몬스터의 레벨 차이에 따라 레벨이 낮으면 데미지 50% 반감, 레벨이 높으면 1레벨당 +5% 추가 데미지가 적용됩니다.\n"
    report += "- **무기 상태**: 무기는 0강화, 품질 100% 기준으로 계산합니다.\n\n"

    report += "| 단계 | 장착 무기 (공격력) | 사냥 몬스터 (Lv/HP) | 필요 사냥 수 | 사냥 전 플레이어 Lv | 사냥 후 플레이어 Lv | 타격당 실데미지 | **처치에 필요한 타격 횟수** |\n"
    report += "| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: |\n"

    for i in range(len(weapons) - 1):
        w_current = weapons[i]
        w_next = weapons[i+1]
        mob_key = w_next["mob"]
        mob = mobs[mob_key]
        
        # 이전 티어 사냥 후 플레이어 레벨 및 스탯
        sp_points = (player_level - 1) * STAT_POINTS_PER_LEVEL
        attack_mult = 1.0 + (sp_points * ATTACK_PER_POINT)
        
        # 현재 무기 데미지
        wp_dmg = w_current["dmg"]
        base_dmg = BASE_PLAYER_DMG + wp_dmg
        
        # 레벨 보정 전 최종 데미지
        raw_final_dmg = base_dmg * attack_mult
        
        # 레벨 차이 보정 적용
        level_diff = player_level - mob["level"]
        adjusted_dmg = raw_final_dmg
        if level_diff > 0:
            adjusted_dmg = adjusted_dmg * (1 + level_diff * 0.05)
        elif level_diff < 0:
            adjusted_dmg = adjusted_dmg * 0.5
            
        final_hit_dmg = max(1, math.floor(adjusted_dmg))
        
        # 처치에 필요한 타격 횟수
        hits_required = math.ceil(mob["hp"] / final_hit_dmg)
        
        # 필요한 사냥 마릿수 계산
        kills_required = math.ceil(w_next["req_count"] / mob["drop_avg"])
        
        # 아이스 소드의 경우 예외 처리 (얼음 기사 16마리 + 아이스 드래곤 14마리 사냥 필요)
        if w_next["id"] == "ICE_SWORD":
            # 얼음 기사만 표에 기록하되 사냥 경험치는 두 몬스터 모두 합산
            ice_dragon_kills = math.ceil(20 / 1.5) # 드래곤 발톱 20개
            xp_gained = (kills_required * mob["xp"]) + (ice_dragon_kills * mobs["ICEDRAGON"]["xp"])
        else:
            xp_gained = kills_required * mob["xp"]
            
        # 사냥 전 레벨 기록
        pre_level = player_level
        
        # 경험치 획득 및 제작 보너스 경험치 20 추가
        player_xp += xp_gained + 20
        player_level = get_level_from_xp(player_xp)
        
        # 마크다운 행 추가
        report += f"| {i+1} | {w_current['name']} ({wp_dmg}) | {mob['name']} ({mob['level']}/{mob['hp']}) | {kills_required}마리 | Lv.{pre_level} | Lv.{player_level} | {final_hit_dmg} | **{hits_required}방** |\n"
        
    with open("scratch/balance_analysis.md", "w", encoding="utf-8") as f:
        f.write(report)
    print("Done! Report written to scratch/balance_analysis.md")

if __name__ == "__main__":
    main()
