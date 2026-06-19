# simulate_flat.py
# Simulate 20% flat progression per tier

weapons = [
    {"name": "나무봉", "dmg": 10},
    {"name": "슬라임검", "dmg": 54},
    {"name": "단단한 검", "dmg": 107},
    {"name": "사막의 검", "dmg": 170},
    {"name": "사막의 밤", "dmg": 246},
    {"name": "철검", "dmg": 337},
    {"name": "카타나", "dmg": 446},
    {"name": "뱀파이어 소드", "dmg": 577},
    {"name": "아이스 소드", "dmg": 734},
    {"name": "나이트 소드", "dmg": 923},
    {"name": "소울 소드", "dmg": 1150},
    {"name": "저스티스 소드", "dmg": 1422},
    {"name": "블루파이어 소드", "dmg": 1748},
]

def main():
    # If enhancement rate is unified (e.g., 0.20), then the ratio at any enhancement level is exactly the same as the +0 ratio!
    # Because (1 + E * R) is the same for both weapon A and weapon B, so they cancel out in the ratio.
    print("| 비교 구간 | 무기 A 데미지 | 무기 B 데미지 | +0강 시 상승률 | +3강 시 상승률 | +5강 시 상승률 |")
    print("| :--- | :---: | :---: | :---: | :---: | :---: |")
    for i in range(len(weapons) - 1):
        w1 = weapons[i]
        w2 = weapons[i+1]
        
        d1 = 210 + w1['dmg']
        d2 = 210 + w2['dmg']
        ratio = (d2 / d1 - 1.0) * 100
        
        print(f"| {w1['name']} -> {w2['name']} | {w1['dmg']} | {w2['dmg']} | {ratio:.2f}% | {ratio:.2f}% | {ratio:.2f}% |")

if __name__ == "__main__":
    main()
