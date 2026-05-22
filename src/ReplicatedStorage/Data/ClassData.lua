-- ClassData.lua
-- 아바타 원소/직업 데이터 테이블 [Data-Driven Template]

local ClassData = {
	["Fire"] = {
		id = "Fire",
		name = "불 (Fire-Bending)",
		desc = "파괴적인 화염 지속 대미지 가중",
		color = {r = 240, g = 80, b = 60},
		vfxColor = {r = 255, g = 100, b = 50},
		onHit = {
			damageModifier = 1.2, -- 20% 보너스
			effects = {
				{ name = "BurnTicks", value = 3, target = "Target" }
			}
		}
	},
	["Water"] = {
		id = "Water",
		name = "물 (Water-Bending)",
		desc = "타격 시 마나 MP 고속 수급 연타",
		color = {r = 60, g = 160, b = 240},
		vfxColor = {r = 50, g = 150, b = 255},
		onHit = {
			damageModifier = 1.0,
			effects = {
				{ name = "MP", value = 2, target = "Self", maxClamp = 200 }
			}
		}
	},
	["Dark"] = {
		id = "Dark",
		name = "어둠 (Dark-Arts)",
		desc = "타격 시 어둠의 방어막(쉴드) 생성",
		color = {r = 138, g = 43, b = 226},
		vfxColor = {r = 100, g = 50, b = 150},
		onHit = {
			damageModifier = 1.0,
			effects = {
				{ name = "DarkShield", value = 3, target = "Self", maxClamp = 50 }
			}
		}
	}
}

return ClassData
