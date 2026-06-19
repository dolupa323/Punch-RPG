# inspect_weapons.py
# Parse ItemData.lua and print all weapons/tools

import re

def parse_lua_table(content):
    # Let's extract items inside the main table
    # Since ItemData is an array of tables: { {id="...", ...}, { ... } }
    # We can search for all items matching { ... } inside the array
    # A simple regex for nested structures
    pattern = r'\{\s*id\s*=\s*"([^"]+)",(?:[^{}]|\{[^{}]*\})*\}'
    matches = re.finditer(pattern, content, re.DOTALL)
    
    items = []
    for match in matches:
        item_str = match.group(0)
        items.append(item_str)
    return items

def main():
    with open('src/ReplicatedStorage/Data/ItemData.lua', 'r', encoding='utf-8') as f:
        content = f.read()
    
    items = parse_lua_table(content)
    
    weapons = []
    for item in items:
        # Check type
        type_match = re.search(r'type\s*=\s*"([^"]+)"', item)
        if type_match:
            item_type = type_match.group(1)
            if item_type in ["WEAPON", "TOOL"]:
                # Parse fields
                id_match = re.search(r'id\s*=\s*"([^"]+)"', item)
                name_match = re.search(r'name\s*=\s*"([^"]+)"', item)
                damage_match = re.search(r'damage\s*=\s*([0-9.]+)', item)
                durability_match = re.search(r'durability\s*=\s*([0-9.]+)', item)
                rarity_match = re.search(r'rarity\s*=\s*"([^"]+)"', item)
                slot_match = re.search(r'slot\s*=\s*"([^"]+)"', item)
                opt_match = re.search(r'optimalTool\s*=\s*"([^"]+)"', item)
                model_match = re.search(r'modelName\s*=\s*"([^"]+)"', item)
                
                item_id = id_match.group(1) if id_match else ""
                name = name_match.group(1) if name_match else ""
                damage = damage_match.group(1) if damage_match else "N/A"
                durability = durability_match.group(1) if durability_match else "N/A"
                rarity = rarity_match.group(1) if rarity_match else "N/A"
                slot = slot_match.group(1) if slot_match else "N/A"
                opt = opt_match.group(1) if opt_match else "N/A"
                model = model_match.group(1) if model_match else "N/A"
                
                weapons.append({
                    "id": item_id,
                    "name": name,
                    "type": item_type,
                    "rarity": rarity,
                    "damage": damage,
                    "durability": durability,
                    "slot": slot,
                    "optimalTool": opt,
                    "modelName": model
                })
                
    print(f"Total Weapons/Tools found: {len(weapons)}")
    print(f"{'ID':<22} | {'Name':<15} | {'Type':<6} | {'Rarity':<10} | {'Dmg':<5} | {'Dur':<5} | {'Slot':<5} | {'OptTool':<8} | {'Model':<15}")
    print("-" * 110)
    for w in weapons:
        print(f"{w['id']:<22} | {w['name']:<15} | {w['type']:<6} | {w['rarity']:<10} | {w['damage']:<5} | {w['durability']:<5} | {w['slot']:<5} | {w['optimalTool']:<8} | {w['modelName']:<15}")

if __name__ == "__main__":
    main()
