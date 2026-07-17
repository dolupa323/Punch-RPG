-- WeaponComboData.lua
-- 무기별 콤보 및 Fallback 횡베기 트윈 정보 데이터 테이블 [Data-Driven Template]

local WeaponComboData = {
	["NONE"] = {
		id = "NONE",
		baseDamage = 1,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["WOODEN_STAFF"] = {
		id = "WOODEN_STAFF",
		baseDamage = 10, -- [기획 동기화] ItemData.lua 공격력(10)과 100% 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38, -- [기획 동기화] ItemData.lua 공격속도(0.38)와 100% 일치화!
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["SoftClub"] = {
		id = "SoftClub",
		baseDamage = 54, -- [기획 동기화] ItemData.lua 공격력(54)과 100% 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38, -- [기획 동기화] 나무봉과 동일한 기획 쿨다운 표준인 0.38초 고정!
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["Gakchang"] = {
		id = "Gakchang",
		baseDamage = 107, -- [기획 동기화] ItemData.lua 공격력(107)과 100% 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["Mogwoldo"] = {
		id = "Mogwoldo",
		baseDamage = 170,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["FireHalberd"] = {
		id = "FireHalberd",
		baseDamage = 35, -- [기획 동기화] ItemData.lua 공격력(35)과 100% 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38, -- 0.38초 쿨다운
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["FangSpear"] = {
		id = "FangSpear",
		baseDamage = 577, -- [기획 동기화] ItemData.lua 공격력(577)과 일치화!
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["IronStaff"] = {
		id = "IronStaff",
		baseDamage = 337,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["POISON_HORN_SPEAR"] = {
		id = "POISON_HORN_SPEAR",
		baseDamage = 246,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["KNIGHT_SWORD"] = {
		id = "KNIGHT_SWORD",
		baseDamage = 923,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["SOUL_SWORD"] = {
		id = "SOUL_SWORD",
		baseDamage = 1150,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["SWORD_OF_JUSTICE"] = {
		id = "SWORD_OF_JUSTICE",
		baseDamage = 1422,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["BLUE_FLAME_SWORD"] = {
		id = "BLUE_FLAME_SWORD",
		baseDamage = 1748,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["KRAKEN_SWORD"] = {
		id = "KRAKEN_SWORD",
		baseDamage = 2150,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["ABYSS_SWORD"] = {
		id = "ABYSS_SWORD",
		baseDamage = 2650,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["POSEIDON_SWORD"] = {
		id = "POSEIDON_SWORD",
		baseDamage = 3260,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["KATANA"] = {
		id = "KATANA",
		baseDamage = 446,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["ICE_SWORD"] = {
		id = "ICE_SWORD",
		baseDamage = 734,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
	["MAGMA_SWORD"] = {
		id = "MAGMA_SWORD",
		baseDamage = 830,
		maxCombo = 3,
		comboWindow = 0.8,
		cooldown = 0.38,
		animations = {
			[1] = "AttackSword_Swing_1",
			[2] = "AttackSword_Swing_2",
			[3] = "AttackSword_Swing_3"
		},
		fallbackVisuals = {
			[1] = { angle = 30, duration = 0.08 },
			[2] = { angle = -30, duration = 0.08 },
			[3] = { angle = 40, duration = 0.08 }
		}
	},
}

return WeaponComboData
