-- WeaponComboData.lua
-- 무기별 콤보 및 Fallback 횡베기 트윈 정보 데이터 테이블 [Data-Driven Template]

local WeaponComboData = {
	["WOODEN_STAFF"] = {
		id = "WOODEN_STAFF",
		baseDamage = 15, -- [기획 동기화] ItemData.lua 공격력(15)과 100% 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.5, -- [기획 동기화] ItemData.lua 공격속도(0.5)와 100% 일치화!
		animations = {
			[1] = "Staff_None_AttackSwing1",
			[2] = "Staff_None_AttackSwing2",
			[3] = "Staff_None_AttackSwing3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["SoftClub"] = {
		id = "SoftClub",
		baseDamage = 25, -- [기획 동기화] ItemData.lua 공격력(25)과 100% 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.5, -- [기획 동기화] 나무봉과 동일한 기획 쿨다운 표준인 0.5초 고정!
		animations = {
			[1] = "Staff_None_AttackSwing1",
			[2] = "Staff_None_AttackSwing2",
			[3] = "Staff_None_AttackSwing3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	}
}

return WeaponComboData
