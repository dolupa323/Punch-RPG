import re

file_path = r"c:\YJS\Roblox\RPG\src\ReplicatedStorage\Data\MobSpawnData.lua"

with open(file_path, 'rb') as f:
    content_bytes = f.read()

# Pattern in bytes
pattern = rb'(\t\["SpiderZone"\] = \{.*?\n\t\},\s*\n\s*\n\s*\["SpiderZone"\] = \{)(.*?)(\t\},)'

# Let's find matches
matches = list(re.finditer(pattern, content_bytes, re.DOTALL))
print(f"Found {len(matches)} matches.")

if len(matches) == 1:
    match = matches[0]
    second_zone_content = match.group(2)
    if b'level =' not in second_zone_content:
        # We need to insert: level = 33, -- 거미 레벨 33
        # In UTF-8, "거미 레벨 33" is:
        comment = " 거미 레벨 33".encode('utf-8')
        replacement_line = b'spawnAreaId = "SpiderZone",\n\t\tlevel = 33, --' + comment
        second_zone_content = second_zone_content.replace(
            b'spawnAreaId = "SpiderZone",',
            replacement_line
        )
    
    replacement = b'\t["SpiderZone"] = {' + second_zone_content + b'\t},'
    new_content = content_bytes[:match.start()] + replacement + content_bytes[match.end():]
    
    with open(file_path, 'wb') as f:
        f.write(new_content)
    print("Successfully cleaned up SpiderZone in MobSpawnData.lua using binary mode!")
else:
    # Let's print out what is there to debug
    print("Pattern match failed. Searching for simple SpiderZone occurrences.")
    all_spider_zones = list(re.finditer(rb'\["SpiderZone"\]', content_bytes))
    print(f"Total 'SpiderZone' occurrences: {len(all_spider_zones)}")
    for m in all_spider_zones:
        start_idx = max(0, m.start() - 50)
        end_idx = min(len(content_bytes), m.end() + 100)
        print(f"Occurrence at {m.start()}: {content_bytes[start_idx:end_idx]}")
