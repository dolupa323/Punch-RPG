import os

file_path = r'c:\YJS\Roblox\RPG\src\ServerScriptService\Server\Services\InventoryService.lua'

with open(file_path, 'rb') as f:
    content = f.read()

lines = content.splitlines()

# The specific block is between line 720 and 732 (0-indexed: 719 to 731)
start_idx = 719
end_idx = 732

# Verify first
if len(lines) > end_idx:
    print(f"Replacing lines {start_idx+1} to {end_idx+1}")
    
    # Use generic comments in English to avoid encoding headaches in the script itself
    new_block = [
        b"\t-- Item check",
        b"\tok, err = _validateHasItem(inv, fromSlot)",
        b"\tif not ok then return false, err, nil end",
        b"\t",
        b"\t-- Count check",
        b"\tok, err = _validateCount(count)",
        b"\tif not ok then return false, err, nil end"
    ]

    new_lines = lines[:start_idx] + new_block + lines[end_idx+1:]

    with open(file_path, 'wb') as f:
        f.write(b'\n'.join(new_lines))
    print("Successfully cleaned up InventoryService.lua")
else:
    print("Error: File too short")
