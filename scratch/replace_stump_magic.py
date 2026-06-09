# replace_stump_magic.py
import os

file_path = r"c:\YJS\Roblox\RPG\src\ServerScriptService\Server\Services\MobSpawnService.lua"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Let's find the start of Stump magic spike definition:
start_marker = 'local magicSpikeModel = Instance.new("Model")\n\t\t\t\t\t\t\t\tmagicSpikeModel.Name = "MagicTreeSpike"'
if start_marker not in content:
    # Try with CRLF
    start_marker = start_marker.replace('\n', '\r\n')

end_marker = 'updateSpikeCF(attackPos, -7)'
if end_marker not in content:
    end_marker = end_marker.replace('\n', '\r\n')

if start_marker in content and end_marker in content:
    idx_start = content.index(start_marker) + len(start_marker)
    idx_end = content.index(end_marker)
    
    new_spire_defs = """
								
								-- A. 중앙 메인 사암 가시 (WedgePart로 뾰족한 형상 구현)
								local mainSpire = Instance.new("WedgePart")
								mainSpire.Name = "MainSpire"
								mainSpire.Size = Vector3.new(3.5, 12, 3.5)
								mainSpire.Color = Color3.fromRGB(195, 145, 95) -- 사암색
								mainSpire.Material = Enum.Material.Sandstone
								mainSpire.CanCollide = false
								mainSpire.Anchored = true
								mainSpire.Parent = magicSpikeModel
								
								-- B. 주변 보조 사암 파편 1 (좌측 경사 쐐기)
								local sideShard1 = Instance.new("WedgePart")
								sideShard1.Name = "SideShard1"
								sideShard1.Size = Vector3.new(2, 6, 2)
								sideShard1.Color = Color3.fromRGB(180, 130, 80) -- 약간 어두운 사암
								sideShard1.Material = Enum.Material.Sandstone
								sideShard1.CanCollide = false
								sideShard1.Anchored = true
								sideShard1.Parent = magicSpikeModel
								
								-- C. 주변 보조 사암 파편 2 (우측 경사 쐐기)
								local sideShard2 = Instance.new("WedgePart")
								sideShard2.Name = "SideShard2"
								sideShard2.Size = Vector3.new(1.8, 4, 1.8)
								sideShard2.Color = Color3.fromRGB(210, 160, 110) -- 약간 밝은 사암
								sideShard2.Material = Enum.Material.Sandstone
								sideShard2.CanCollide = false
								sideShard2.Anchored = true
								sideShard2.Parent = magicSpikeModel
								
								-- 일관적인 위치 보정 함수 (트윈/수학적 루프 연산용)
								local function updateSpikeCF(centerPos, verticalOffset)
									local baseCF = CFrame.new(centerPos + Vector3.new(0, verticalOffset, 0))
									mainSpire.CFrame = baseCF * CFrame.Angles(0, 0, 0)
									sideShard1.CFrame = baseCF * CFrame.new(-1.2, -3, 0.8) * CFrame.Angles(math.rad(15), 0, math.rad(15))
									sideShard2.CFrame = baseCF * CFrame.new(1.2, -4, -0.8) * CFrame.Angles(math.rad(-15), 0, math.rad(-15))
								end
								
								"""
    
    if "\r\n" in content:
        new_spire_defs = new_spire_defs.replace("\n", "\r\n")
        
    content = content[:idx_start] + new_spire_defs + content[idx_end:]
    print("Successfully replaced magicSpikeModel parts!")
else:
    print("Could not find start/end markers for magicSpikeModel!")

# Let's do the same for FallingTrunk:
trunk_start = 'local trunk = Instance.new("Part")\n\t\t\t\t\t\t\t\ttrunk.Name = "FallingTrunk"'
if trunk_start not in content:
    trunk_start = trunk_start.replace('\n', '\r\n')

trunk_end = 'trunk:Destroy()'
if trunk_end not in content:
    trunk_end = trunk_end.replace('\n', '\r\n')

if trunk_start in content and trunk_end in content:
    idx_t_start = content.index(trunk_start)
    idx_t_end = content.index(trunk_end) + len(trunk_end)
    
    new_falling_boulder = """local trunk = Instance.new("Part")
								trunk.Name = "FallingBoulder"
								trunk.Shape = Enum.PartType.Block
								trunk.Size = Vector3.new(8, 10, 8) -- 거대한 사암 바위
								trunk.Color = Color3.fromRGB(195, 145, 95) -- 사암색
								trunk.Material = Enum.Material.Sandstone
								trunk.CanCollide = false
								trunk.Anchored = true
								
								-- 하늘에서 서서히 돌면서 떨어지는 CFrame 연출
								local startPos = targetFloorPos + Vector3.new(0, 40, 0)
								trunk.CFrame = CFrame.new(startPos) * CFrame.Angles(math.rad(45), math.rad(45), 0)
								trunk.Parent = workspace
								
								local fallTween = ts:Create(trunk, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									CFrame = CFrame.new(targetFloorPos) * CFrame.Angles(math.rad(135), math.rad(90), math.rad(45))
								})
								fallTween:Play()
								task.wait(0.3)
								trunk:Destroy()"""
    
    if "\r\n" in content:
        new_falling_boulder = new_falling_boulder.replace("\n", "\r\n")
        
    content = content[:idx_t_start] + new_falling_boulder + content[idx_t_end:]
    print("Successfully replaced FallingTrunk!")
else:
    print("Could not find start/end markers for FallingTrunk!")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Done!")
