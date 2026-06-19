# inspect_weapons_md_v3.py
import re

def parse_lua_items(content):
    # Match the exact array blocks { ... } for each item.
    # We can split by \t{\n and then parse inside.
    # An item block starts with \t{\n\t\tid = "
    items = []
    # Let's find all entries starting with { and ending with },
    # Since items are defined like:
    # 	{
    # 		id = "...",
    # 		...
    # 	},
    # We can use a regex that matches from \t{ to \t}, with no \t{ in between.
    pattern = r'\n\t\{\s*\n\t\tid\s*=\s*"[^"]+".*?\n\t\},'
    matches = re.finditer(pattern, content, re.DOTALL)
    for m in matches:
        items.append(m.group(0))
    return items

def main():
    with open('src/ReplicatedStorage/Data/ItemData.lua', 'r', encoding='utf-8') as f:
        item_content = f.read()
        
    with open('src/ReplicatedStorage/Data/WeaponComboData.lua', 'r', encoding='utf-8') as f:
        combo_content = f.read()

    # Parse WeaponComboData
    blocks = re.split(r'\["([^"]+)"\]\s*=\s*\{', combo_content)
    combo_data = {}
    for i in range(1, len(blocks), 2):
        key = blocks[i]
        body = blocks[i+1]
        
        base_dmg_match = re.search(r'baseDamage\s*=\s*([0-9.]+)', body)
        cooldown_match = re.search(r'cooldown\s*=\s*([0-9.]+)', body)
        max_combo_match = re.search(r'maxCombo\s*=\s*([0-9.]+)', body)
        
        combo_data[key] = {
            "baseDamage": base_dmg_match.group(1) if base_dmg_match else "N/A",
            "cooldown": cooldown_match.group(1) if cooldown_match else "N/A",
            "maxCombo": max_combo_match.group(1) if max_combo_match else "N/A"
        }

    # Parse ItemData
    item_blocks = parse_lua_items(item_content)
    weapons = []
    
    for block in item_blocks:
        type_match = re.search(r'type\s*=\s*"([^"]+)"', block)
        if type_match:
            item_type = type_match.group(1)
            if item_type in ["WEAPON", "TOOL"]:
                id_match = re.search(r'id\s*=\s*"([^"]+)"', block)
                name_match = re.search(r'name\s*=\s*"([^"]+)"', block)
                damage_match = re.search(r'damage\s*=\s*([0-9.]+)', block)
                durability_match = re.search(r'durability\s*=\s*([0-9.]+)', block)
                rarity_match = re.search(r'rarity\s*=\s*"([^"]+)"', block)
                slot_match = re.search(r'slot\s*=\s*"([^"]+)"', block)
                opt_match = re.search(r'optimalTool\s*=\s*"([^"]+)"', block)
                model_match = re.search(r'modelName\s*=\s*"([^"]+)"', block)
                desc_match = re.search(r'description\s*=\s*"([^"]+)"', block)
                
                item_id = id_match.group(1) if id_match else ""
                name = name_match.group(1) if name_match else ""
                damage = damage_match.group(1) if damage_match else "N/A"
                durability = durability_match.group(1) if durability_match else "N/A"
                rarity = rarity_match.group(1) if rarity_match else "N/A"
                slot = slot_match.group(1) if slot_match else "N/A"
                opt = opt_match.group(1) if opt_match else "N/A"
                model = model_match.group(1) if model_match else "N/A"
                desc = desc_match.group(1) if desc_match else ""
                
                weapons.append({
                    "id": item_id,
                    "name": name,
                    "type": item_type,
                    "rarity": rarity,
                    "damage": damage,
                    "durability": durability,
                    "slot": slot,
                    "optimalTool": opt,
                    "modelName": model,
                    "description": desc
                })

    # Generate MD Table
    md = "# 무기 및 도구 전체 구조 분석\n\n"
    md += "이 문서는 `ItemData.lua`와 `WeaponComboData.lua` 파싱 결과를 바탕으로 작성되었습니다.\n\n"
    md += "## 1. 무기/도구 목록\n\n"
    md += "| ID | 이름 | 구분 | 등급 | 데미지(Item) | 데미지(Combo) | 공격속도(Combo) | 내구도 | 슬롯 | 무기유형(Optimal) | 모델명 | 설명 |\n"
    md += "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |\n"
    
    for w in weapons:
        combo_info = combo_data.get(w['id'], {})
        combo_dmg = combo_info.get('baseDamage', 'N/A')
        combo_spd = combo_info.get('cooldown', 'N/A')
        md += f"| `{w['id']}` | **{w['name']}** | {w['type']} | {w['rarity']} | {w['damage']} | {combo_dmg} | {combo_spd} | {w['durability']} | {w['slot']} | {w['optimalTool']} | {w['modelName']} | {w['description']} |\n"
        
    with open('scratch/weapons.md', 'w', encoding='utf-8') as f:
        f.write(md)
    print("Successfully generated scratch/weapons.md with precise matching!")

if __name__ == "__main__":
    main()
