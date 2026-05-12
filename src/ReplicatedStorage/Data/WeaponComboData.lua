-- WeaponComboData.lua
-- 무기별 콤보 및 Fallback 횡베기 트윈 정보 데이터 테이블 [Data-Driven Template]

local WeaponComboData = {
	["WOODEN_STAFF"] = {
		id = "WOODEN_STAFF",
		baseDamage = 25, -- [밸런스패치] 3대 때리면 70HP 몹 사냥 가능하도록 상향 (25 x 3 = 75)
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.28,
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
