
import re
with open(rsrc\StarterPlayer\StarterPlayerScripts\Client\Controllers\AvatarController.lua, r, encoding=utf-8) as f:
    text = f.read()

target = r"
					if skillId then
						AvatarController.playSkillHit(skillId, pos, targetHrp)
					else
						-- 0. [리팩티브 반영] 기본 공격 판단시트 해당 공용 타격 이펙트 VFX/사운드 시스템 동기화 재생
						if targetHrp then
							pcall(function()
								-- [Sound 재생]
								local hitSoundFolder = getCombatSoundFolder(Hit)
								if hitSoundFolder then
									local hitSndTemplate = hitSoundFolder:FindFirstChild(Default_Attack_Hit) or hitSoundFolder:FindFirstChild(Base_Attack_Hit)
									if hitSndTemplate then
										playCombatSound(hitSndTemplate, targetHrp)
									end
								end
								
								-- [VFX 재생]
								local hitFolder = getElementVFXFolder(Hit)
								if hitFolder then
									local hitVfxTemplate = hitFolder:FindFirstChild(Default_Attack_Hit) or hitFolder:FindFirstChild(Base_Attack_Hit)
									if hitVfxTemplate then
										-- 데미지 발생좌표를 바탕으로 월드에 이펙트 투척
										spawnCombatVFX(hitVfxTemplate, CFrame.new(pos), 2.0)
									end
								end
							end)
						end
					end
"

chunk = r"
					-- [중복 폭발 방지] hideVfx 플래그가 있으면 이펙트/사운드 재생 생략 (데미지 텍스트만 띄움)
					if not data.hideVfx then
						if skillId then
							AvatarController.playSkillHit(skillId, pos, targetHrp)
						else
							-- 0. [리팩티브 반영] 기본 공격 판단시트 해당 공용 타격 이펙트 VFX/사운드 시스템 동기화 재생
							if targetHrp then
								pcall(function()
									-- [Sound 재생]
									local hitSoundFolder = getCombatSoundFolder(Hit)
									if hitSoundFolder then
										local hitSndTemplate = hitSoundFolder:FindFirstChild(Default_Attack_Hit) or hitSoundFolder:FindFirstChild(Base_Attack_Hit)
										if hitSndTemplate then
											playCombatSound(hitSndTemplate, targetHrp)
										end
									end
									
									-- [VFX 재생]
									local hitFolder = getElementVFXFolder(Hit)
									if hitFolder then
										local hitVfxTemplate = hitFolder:FindFirstChild(Default_Attack_Hit) or hitFolder:FindFirstChild(Base_Attack_Hit)
										if hitVfxTemplate then
											-- 데미지 발생좌표를 바탕으로 월드에 이펙트 투척
											spawnCombatVFX(hitVfxTemplate, CFrame.new(pos), 2.0)
										end
									end
								end)
							end
						end
					end
"

start = text.find(if skillId then)
end_idx = text.find(-- 1. 플로팅 데미지 텍스트 생성)
if start != -1 and end_idx != -1:
    new_text = text[:start] + chunk + text[end_idx:]
    with open(rsrc\StarterPlayer\StarterPlayerScripts\Client\Controllers\AvatarController.lua, w, encoding=utf-8) as f:
        f.write(new_text)
    print(Fixed AvatarController.lua)
else:
    print(Could not find target)

