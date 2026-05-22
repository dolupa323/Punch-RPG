
import re

with open(rc:\YJS\Roblox\RPG\src\ServerScriptService\Server\Services\SkillService.lua, r, encoding=utf-8) as f:
    text = f.read()

fixed_chunk = r"
		-- 2. 스탯 보너스 및 치명타 확률/데미지 가져오기
		local attackMult = 1.0
		local critChance = 0
		local critDamageMult = 0
		
		local success, PlayerStatService = pcall(function()
			return require(script.Parent.PlayerStatService)
		end)
		
		if success and PlayerStatService then
			local calc = PlayerStatService.GetCalculatedStats(player.UserId)
			attackMult = calc.attackMult or 1.0
			critChance = calc.critChance or 0
			critDamageMult = calc.critDamageMult or 0
		end
		
		-- 기본 스킬 데미지 (무기 데미지에 2.0배 배율 적용)
		local baseSkillDamage = finalDamage * attackMult * 2.0
		
		-- [VFX 발동 위치 고정] 플레이어가 캐스팅 후 이동해도 폭발 위치는 발사했던 시점의 도착지점으로 고정
		local hitPos = hrp.Position + look * 15
		
		-- Damage logic (4타 멀티 히트)
		task.spawn(function()
			for hitIndex = 1, 4 do
				local radius = 15 -- 넓은 광역 폭발
				
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
				
				for _, part in ipairs(nearbyParts) do
					local model = part:FindFirstAncestorOfClass(Model)
					if model then
						local hum = model:FindFirstChildOfClass(Humanoid)
						-- 체력이 0이하인 시체도 타격하여 4타의 데미지 텍스트가 모두 표기되도록 허용
						if hum and not hitHumanoids[hum] then
							hitHumanoids[hum] = true
							hitAny = true
							
							-- [타겟별 개별 데미지/치명타 연산]
							local hitDmg = baseSkillDamage
							local variance = 0.15
							hitDmg = hitDmg * (1 + (math.random() * 2 - 1) * variance)
							
							local hitCrit = false
							if critChance > 0 and math.random() < critChance then
								hitCrit = true
								hitDmg = hitDmg * (1.5 + critDamageMult)
							end
							local finalHitDmg = math.max(1, math.floor(hitDmg))
							
							local wasAlive = hum.Health > 0
							
							local tag = hum:FindFirstChild(creator)
							if tag then tag:Destroy() end
							
							tag = Instance.new(ObjectValue)
							tag.Name = creator
							tag.Value = player
							tag.Parent = hum
							game:GetService(Debris):AddItem(tag, 2)
							
							hum:TakeDamage(finalHitDmg)
							print(string.format([SkillService] %s hit %d/4: %s | Dmg: %d | Crit: %s, vfxName, hitIndex, model.Name, finalHitDmg, tostring(hitCrit)))
							
							-- 방금 일격으로 죽었을 때만 경험치 1회 지급 (시체 타격 중복 지급 방지)
							if wasAlive and hum.Health <= 0 then
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
							
							-- [타겟별 VFX 발송] (맞은 몬스터마다 각각 데미지 텍스트 출력!)
							if vfxRemote then
								local targetHrp = model:FindFirstChild(HumanoidRootPart) or model.PrimaryPart
								local vfxPos = targetHrp and targetHrp.Position or hitPos
								vfxPos = vfxPos + Vector3.new((math.random() - 0.5)*3, (math.random() - 0.5)*3, (math.random() - 0.5)*3)
								
								vfxRemote:FireAllClients({
									target = model,
									element = Skill,
									position = vfxPos,
									damage = finalHitDmg,
									isCritical = hitCrit,
									skillId = itemId,
									isMiss = false
								})
							end
						end
					end
				end
				
				-- 맞은 적이 하나도 없을 경우 (허공 폭발)
				if not hitAny and vfxRemote then
					local vfxPos = hitPos + Vector3.new((math.random() - 0.5)*5, (math.random() - 0.5)*5, (math.random() - 0.5)*5)
					
					vfxRemote:FireAllClients({
						target = char,
						element = Skill,
						position = vfxPos,
						damage = 0,
						isCritical = false,
						skillId = itemId,
						isMiss = true
					})
				end
				
				task.wait(0.15) -- 0.15초 간격으로 총 4번 타격
			end
			
			print(string.format([SkillService] %s exploded at %s, vfxName, tostring(hitPos)))
		end)
	end
end
"

start_idx = text.find(-- 2. 스탯 보너스 및 치명타 적용)
end_idx = text.find(--- 스킬 사용 요청 처리)

if start_idx != -1 and end_idx != -1:
    new_text = text[:start_idx] + fixed_chunk + \n + text[end_idx:]
    with open(rc:\YJS\Roblox\RPG\src\ServerScriptService\Server\Services\SkillService.lua, w, encoding=utf-8) as f:
        f.write(new_text)
    print(Fixed SkillService.lua)
else:
    print(Could not find chunks)

