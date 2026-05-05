import os

file_path = r'c:\YJS\Roblox\Origin-WILD\src\StarterPlayer\StarterPlayerScripts\Client\UIManager.lua'

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# We want to keep everything up to line 3708 (index 3707)
# Then skip the garbage (3709 to 3719)
# Then keep the rest (requestEnhance, etc.)
# Then stop before the old click handler (3737)

new_lines = []

# Part 1: Start to end of openItemSelector
for i in range(min(len(lines), 3708)):
    new_lines.append(lines[i])

# Part 2: requestEnhance and getItemName
# They start after the garbage. Let's find them by content to be safe.
for i in range(3718, len(lines)):
    line = lines[i]
    if "function UIManager.requestEnhance" in line:
        # Add a few lines before it if they are empty
        new_lines.append(line)
        # Continue adding until we reach the old click handler
        for j in range(i + 1, len(lines)):
            line_j = lines[j]
            if "-- 인벤토리 아이템 클릭 핸들러" in line_j:
                break
            if "return UIManager" in line_j:
                break
            new_lines.append(line_j)
        break

new_lines.append("\nreturn UIManager\n")

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print("Cleanup complete.")
