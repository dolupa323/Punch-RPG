
import re

with open(rc:\YJS\Roblox\RPG\src\ServerScriptService\Server\Services\SkillService.lua, r, encoding=utf-8) as f:
    text = f.read()

fixed_chunk = r"
		local dmgTotal = math.max(1, math.floor(finalDamage))
		
		-- Damage logic (4타 멀티 히트)
		task.spawn(function()
			for hitIndex = 1, 4 do
				local hitPos = hrp.Position + look * 15
				local radius = 8
				
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = {char}
				
				local nearbyParts = workspace:GetPartBoundsInRadius(hitPos, radius, params)
				local hitHumanoids = {}
				
				local ReplicatedStorage = game:GetService(ReplicatedStorage)
				local avatarFolder = ReplicatedStorage:FindFirstChild(Avatar)
				local vfxFolder = avatarFolder and avatarFolder:FindFirstChild(VFX)
				local vfxRemote = vfxFolder and vfxFolder:FindFirstChild(Hit)
				
				local hitAny = false
				local firstHitModel = nil
				
				for _, part in ipairs(nearbyParts) do
					local model = part:FindFirstAncestorOfClass(Model)
					if model then
						local hum = model:FindFirstChildOfClass(Humanoid)
						if hum and hum.Health > 0 and not hitHumanoids[hum] then
							hitHumanoids[hum] = true
							hitAny = true
							if not firstHitModel then firstHitModel = model end
							
							local tag = hum:FindFirstChild(creator)
							if tag then tag:Destroy() end
							
							tag = Instance.new(ObjectValue)
							tag.Name = creator
							tag.Value = player
							tag.Parent = hum
							game:GetService(Debris):AddItem(tag, 2)
							
							hum:TakeDamage(dmgTotal)
							print(string.format([SkillService] %s hit %d/4: %s | Dmg: %d | Crit: %s, vfxName, hitIndex, model.Name, dmgTotal, tostring(isCritical)))
							
							-- 경험치 지급
							if hum.Health <= 0 then
								local xpReward = model:GetAttribute(XPReward) or 25
								if PlayerStatService and PlayerStatService.grantActionXP then
									local mobId = model:GetAttribute(MobId) or model.Name
									PlayerStatService.grantActionXP(player.UserId, xpReward, {
										source = CREATURE_KILL,
										actionKey = MOB: .. tostring(mobId),
										disableDiminishing = true
									})
								end
							end
						end
					end
				end
				
				-- [VFX Hit 방송] 몬스터 적중 여부와 상관없이 허공에 쏴도 폭발 이펙트 재생
				if vfxRemote then
					local targetModel = firstHitModel or char
					local displayDamage = hitAny and dmgTotal or 0
					
					-- 타격 이펙트는 매 타수마다 약간씩 랜덤한 위치에서 터지도록 처리
					local vfxPos = hitPos + Vector3.new((math.random() - 0.5)*3, (math.random() - 0.5)*3, (math.random() - 0.5)*3)
					
					vfxRemote:FireAllClients({
						target = targetModel,
						element = Skill,
						position = vfxPos,
						damage = displayDamage,
						isCritical = isCritical,
						skillId = itemId,
						isMiss = not hitAny
					})
				end
				
				task.wait(0.15) -- 0.15초 간격으로 총 4번 타격
			end
			
			print(string.format([SkillService] %s exploded at %s, vfxName, tostring(hitPos)))
		end)
	end
end
"

# Find the start of local dmgTotal = math.max(1, math.floor(finalDamage))
start_idx = text.find(local dmgTotal = math.max(1, math.floor(finalDamage)))
# Find the start of --- 스킬 사용 요청 처리
end_idx = text.find(--- 스킬 사용 요청 처리)

if start_idx != -1 and end_idx != -1:
    new_text = text[:start_idx] + fixed_chunk + \n + text[end_idx:]
    with open(rc:\YJS\Roblox\RPG\src\ServerScriptService\Server\Services\SkillService.lua, w, encoding=utf-8) as f:
        f.write(new_text)
    print(Fixed SkillService.lua)
else:
    print(Could not find chunks)

