-- MobSpawnData.lua
-- 월드 몬스터 구역별 스폰 좌표 및 에셋 템플릿 데이터 [Data-Driven Template]

local MobSpawnData = {
	["StartingZone_Slime"] = {
		spawnAreaId = "StartingZone_Slime",
		mobModelName = "Slime",
		mobDisplayName = "슬라임",
		maxHealth = 70,
		baseDamage = 5,     -- 한 방 데미지
		attackCooldown = 1.5, -- 공격 주기(초)
		respawnDelay = 1.0,
		modelScale = 0.8,
		xpReward = 45, -- 슬라임 처치 시 기본 경험치
		
		-- [활성화]: 4개의 좌표를 꼭짓점 삼아 그 '내부 영역 전체'에 무작위 랜덤 스폰합니다!
		spawnAsPolygon = true, 
		spawnCount = 6, -- 총 6마리 슬라임이 구역 안에서 제멋대로 젠 됩니다.
		
		-- [확정]: 사용자 스크린샷 기반 절대 좌표 반영
		spawnPositions = {
			{x = -270.011, y = 17.239, z = 409.002},
			{x = -340.511, y = 15.912, z = 505.033},
			{x = -425.011, y = 16.507, z = 440.902},
			{x = -329.297, y = 15.520, z = 337.943}
		}
	},
	
	["HornedLarvaZone"] = {
		spawnAreaId = "HornedLarvaZone",
		mobModelName = "HornedLarva",
		mobDisplayName = "뿔 애벌레",
		maxHealth = 120,      -- 뿔 애벌레 강력함 반영
		baseDamage = 12,      -- 슬라임보다 강력한 공격력
		attackCooldown = 2.0, -- 공격 속도 2.0초
		respawnDelay = 2.0,   -- 부활 딜레이 2초
		modelScale = 0.07,    -- 몬스터 크기 정밀 축소 보정 (조금 더 선명해진 크기)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 세로 모델의 머리 방향(아래)을 전방으로 오도록 눕힘
		walkSpeed = 6,        -- 씩씩한 전진 속도
		xpReward = 90,        -- 풍부한 경험치 보상
		
		-- [활성화]: 4개의 꼭짓점 사각형 영역 내부에 뿔 애벌레 10마리 랜덤 스폰!
		spawnAsPolygon = true,
		spawnCount = 10,       
		
		-- 유저 스크린샷 Properties 속성에서 100% 정밀 추출한 4개 꼭짓점 좌표
		spawnPositions = {
			{x = -158.764, y = -5.058, z = 113.772},
			{x = -304.24, y = -3.904, z = 257.483},
			{x = -45.12, y = 3.136, z = 195.686},
			{x = -222.64, y = -3.258, z = 367.094}
		}
	},
	
	["StumpZone"] = {
		spawnAreaId = "StumpZone",
		mobModelName = "Stump",
		mobDisplayName = "스텀프",
		maxHealth = 600,
		baseDamage = 25,
		attackCooldown = 1.5, -- 마법 공격 주기 1.5초로 단축하여 다이내믹한 템포 구현
		respawnDelay = 15.0,  -- 사망 후 정확히 15.0초 뒤 리스폰
		modelScale = 0.2,     -- 표준 크기 보정 (0.2 연동)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 눕혀진 원본 모델 머리를 전방으로 세우기 위해 회전 보정
		customHipHeight = 1.2, -- 물리 중심이 넘어지지 않고 지면에 안착되도록 정밀 조율된 힙높이
		walkSpeed = 10,
		xpReward = 400,
		spawnCount = 4,
		spawnAsPolygon = true, -- 꼭짓점 사각형 영역 내부에 스냅 스폰!
		spawnPositions = {
			{x = -182.605, y = -7.751, z = 73.701},
			{x = -292.491, y = -0.718, z = -86.676},
			{x = -131.693, y = -7.407, z = -8.74},
			{x = -333.519, y = 7.077, z = -5.293}
		}
	},
	
	["CyclopsBatZone"] = {
		spawnAreaId = "CyclopsBatZone",
		mobModelName = "CyclopsBat",
		mobDisplayName = "사이클롭스 박쥐",
		maxHealth = 350,  -- 사이클롭스 박쥐 강력함 반영
		baseDamage = 35,  
		attackCooldown = 0.8, 
		respawnDelay = 3.0,
		modelScale = 0.09, -- 박쥐 고유 에셋 규격 조율 (0.09로 적당하게 축소)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 누워있는 비행 방향을 정면 수직으로 보정
		customHipHeight = 15.0, -- 공중 비행(Hovering) 높이 15.0 스터드로 강제 보정
		walkSpeed = 10,   
		xpReward = 120,
		
		spawnAsPolygon = true,
		spawnCount = 4, -- 4마리 배치
		
		spawnPositions = {
			{x = -72.788, y = -11.347, z = -154.403},
			{x = 22.992, y = -3.737, z = -143.84},
			{x = -40.922, y = -8.358, z = -415.091},
			{x = 48.014, y = -10.638, z = -416.017}
		}
	},
	
	["SmallGolemZone"] = {
		spawnAreaId = "SmallGolemZone",
		mobModelName = "SmallGolem",
		mobDisplayName = "작은 골렘",
		maxHealth = 500,     -- 골렘 특성상 맷집이 강함
		baseDamage = 30,     -- 묵직한 데미지
		attackCooldown = 2.5, -- 공격 속도는 다소 느림
		respawnDelay = 5.0,
		modelScale = 4.0,    -- [수정] 살짝 더 키워달라는 요청 반영 (3.0 -> 4.0배 확대)
		walkSpeed = 5,       -- 느릿하고 묵직한 이동
		xpReward = 150,      -- 높은 경험치 보상
		
		spawnAsPolygon = false,
		spawnCount = 7,
		
		isIndoor = true,
		skipTerrainScan = true, -- [추가] 천장이 매우 낮은 좁은 동굴이므로 레이캐스트를 생략하고 고정 좌표에 즉시 스폰
		
		spawnPositions = {
			{x = -257.456, y = -59.146, z = -90.758},
			{x = -265.767, y = -56.683, z = -116.873},
			{x = -137.064, y = -66.545, z = -184.328},
			{x = -185.809, y = -66.258, z = -287.735},
			{x = -214.250, y = -66.869, z = -286.742},
			{x = -206.721, y = -65.324, z = -232.047},
			{x = -183.517, y = -64.792, z = -241.182}
		}
	},
	
	["StumpKingZone"] = {
		spawnAreaId = "StumpKingZone",
		mobModelName = "StumpKing",
		mobDisplayName = "스텀프 킹",
		maxHealth = 2000,
		baseDamage = 50,
		attackCooldown = 3.0,
		respawnDelay = 20.0,
		modelScale = 0.075,    -- 검증 완료: 0.05 크기 대비 1.5배 적절하게 키운 최종 보스 황금 비율
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 누워있는 원본 모델을 수직으로 세우는 회전 보정
		walkSpeed = 8,
		xpReward = 1000,
		
		spawnAsPolygon = true,
		spawnCount = 3, -- 3마리 배치
		
		spawnPositions = {
			{x = 102.705, y = -15.877, z = -369.877},
			{x = 211.63, y = -10.09, z = -321.086},
			{x = 128.91, y = -23.8, z = -90.572},
			{x = -21.537, y = -11.4, z = -120.593}
		}
	},
	
	["SpiderZone"] = {
		spawnAreaId = "SpiderZone",
		mobModelName = "Spider",
		mobDisplayName = "거미",
		maxHealth = 1200,    -- [상향] 최종 구역 몬스터에 맞게 체력 대폭 상향 (기존 150 -> 1200)
		baseDamage = 45,     -- [상향] 공격력 대폭 상향 (기존 15 -> 45)
		attackCooldown = 1.5, -- [상향] 공격 속도 상승 (기존 2.0 -> 1.5)
		respawnDelay = 5.0,
		modelScale = 0.003,
		walkSpeed = 16,      -- [상향] 이동 속도 상승 (기존 12 -> 16)
		xpReward = 500,      -- [상향] 경험치 보상 대폭 상향 (기존 60 -> 500)
		
		spawnAsPolygon = true,
		spawnCount = 5,
		
		spawnPositions = {
			{x = 109.783, y = 13.695, z = -77.87},
			{x = 265.316, y = 14.127, z = 116.704},
			{x = 261.501, y = 14.837, z = -55.239},
			{x = 108.249, y = 13.686, z = 146.901}
		}
	},
	
	["SkyIsland_BlueFlameKnight"] = {
		spawnAreaId = "SkyIsland_BlueFlameKnight",
		mobModelName = "BlueFlameKnight",
		mobDisplayName = "푸른 불꽃 기사",
		maxHealth = 35000,     -- 하늘섬 최종 보스급 스펙
		baseDamage = 110,      -- 방어 못하면 즉사급 위력
		attackCooldown = 2.0,  -- 공격 휘두르는 속도
		respawnDelay = 60.0,   -- 처치 후 1분 뒤 리스폰
		modelScale = 1.5,      -- 기본 R6 모델보다 큼 (위압감)
		customHipHeight = 1.8, -- [옵션] 3.0 이상 띄울 때 발이 공중에 뜨면 1.8로 보정 (다리 길이에 따라 조정)
		walkSpeed = 12,        -- 평상시 추격 이속
		xpReward = 10000,      -- 처치 시 보상 경험치 대폭 상승
		
		spawnAsPolygon = false,  -- [버그수정] 보스는 무작위 스폰이 아닌 보스방 정중앙 고정 스폰!
		spawnCount = 1,         -- 보스 1마리 웅장하게 대기
		isIndoor = true,        -- 실내(천장 있음) 환경
		skipTerrainScan = true, -- [완벽 작동 확인] 보스방 천장 간섭 없이 exactSpawnPosition으로 정확히 안착!
		exactSpawnPosition = {x = 1389.5, y = 500.0, z = 63.2}, -- [정밀 매칭 완료] 보스방 정중앙
		
		-- [정밀 매칭 완료] 사용자 제공 스크린샷 Properties 속성에서 추출한 4개 꼭짓점 좌표 반영
		spawnPositions = {
			{x = 1419.014, y = 499.892, z = 97.743}, -- 꼭짓점 1 (Realistic Stone)
			{x = 1363.184, y = 500.674, z = 96.8},   -- 꼭짓점 2 (Realistic Stone)
			{x = 1362.753, y = 499.739, z = 30.029}, -- 꼭짓점 3 (Realistic Stone)
			{x = 1413.178, y = 499.943, z = 28.167}  -- 꼭짓점 4 (Realistic Stone)
		}
	},
	
	["GhostKnightZone"] = {
		spawnAreaId = "GhostKnightZone",
		mobModelName = "GhostKnight",
		dropTableId = "GIANTGHOSTKNIGHT",
		mobDisplayName = "유령기사(거인)",
		maxHealth = 12000,      -- 중간 보스급 체력
		baseDamage = 70,        -- 맞으면 치명상
		attackCooldown = 2.2,   -- 공격 속도
		respawnDelay = 30.0,    -- 처치 후 30초 뒤 리스폰
		modelScale = 2.5,       -- 기존 모델보다 거대하게 2.5배 확대
		customHipHeight = 1.5,  -- [크기 스케일링 대비]: 중앙이 뜬다는 제보가 있으니 1.5로 낮춤 (다리 길이에 비례)
		walkSpeed = 9,          -- 기본 이동 속도
		xpReward = 3000,        -- 엘리트 처치 경험치
		
		spawnAsPolygon = false, -- [공중 부상 버그 영구 해결]: 불규칙 지형에서 스폰되다 뜨는 현상을 원천 방지
		spawnCount = 1,         -- 중간보스 1마리 웅장하게 대기
		isIndoor = true,        -- 실내 판정
		skipTerrainScan = true, -- [푸른화염의 기사 패턴 참조] 실내 레이캐스트 없이 exactSpawnPosition + 고정 floorY로 완벽 안착!
		exactSpawnPosition = {x = 1292.26, y = 470.75, z = -125.28}, -- [버그해결] 꼭짓점 2 대신 보스방 한가운데 정중앙(4개 꼭짓점의 평균 좌표)으로 변경하여 벽 외부 스폰을 완벽 차단!
		
		-- 유저 제공 Properties Properties에서 100% 정밀 추출한 4개 꼭짓점 좌표 반영
		spawnPositions = {
			{x = 1318.615, y = 472.166, z = -142.542}, -- 꼭짓점 1 (Realistic Stone)
			{x = 1259.659, y = 471.085, z = -140.807}, -- 꼭짓점 2 (Realistic Stone)
			{x = 1263.644, y = 470.096, z = -107.073}, -- 꼭짓점 3 (Realistic Stone)
			{x = 1327.129, y = 469.662, z = -110.689}  -- 꼭짓점 4 (Realistic Stone)
		}
	},
	
	["NormalGhostKnightZone"] = {
		spawnAreaId = "NormalGhostKnightZone",
		mobModelName = "GhostKnight",
		mobDisplayName = "유령기사",
		maxHealth = 2500,       -- 첫 통곡의 벽 수준의 맷집
		baseDamage = 40,        -- 공격력 위협적으로 증가
		attackCooldown = 2.5,   -- 공격속도
		respawnDelay = 15.0,    -- 처치 후 15초 뒤 리스폰
		modelScale = 1.0,       -- 일반 사이즈
		customHipHeight = 1.0,  -- 기본 모델에 맞는 높이
		walkSpeed = 10,         -- 일반 이동 속도
		xpReward = 400,         -- 일반 몹 경험치 상향
		
		spawnAsPolygon = true,  -- 폴리곤 내 무작위 스폰
		spawnCount = 4,         -- 4마리 스폰
		isIndoor = false,
		
		-- 유저 제공 Properties 4개 꼭짓점 좌표 반영
		spawnPositions = {
			{x = 1214.504, y = 466.107, z = -130.67},
			{x = 1155.548, y = 465.026, z = -124.793},
			{x = 1159.533, y = 464.037, z = -48.437},
			{x = 1228.095, y = 463.603, z = -44.593}
		}
	},
	
	["GhostWizardZone"] = {
		spawnAreaId = "GhostWizardZone",
		mobModelName = "GhostWizard",
		mobDisplayName = "유령 마법사",
		maxHealth = 1800,       -- 기사보다는 낮지만 높은 맷집
		baseDamage = 55,        -- 마법 데미지 강력하게 설정
		attackCooldown = 3.0,   -- 원거리 캐스팅 속도
		respawnDelay = 15.0,    -- 처치 후 15초 뒤 리스폰
		modelScale = 1.0,       -- 일반 사이즈
		customHipHeight = 1.0,  -- 기본 모델에 맞는 높이
		walkSpeed = 8,          -- 일반 기사보다 느린 이동 속도
		xpReward = 500,         -- 경험치 상향
		
		spawnAsPolygon = true,  -- 폴리곤 내 무작위 스폰
		spawnCount = 4,         -- 4마리 스폰
		isIndoor = false,       -- 실외(계단-평지 이어지는 구역) 레이캐스트 적용
		
		-- 유저 제공 Properties 4개 꼭짓점 좌표 반영 (계단 구역)
		spawnPositions = {
			{x = 1163.016, y = 465.86, z = 15.733},
			{x = 1169.343, y = 488.387, z = 84.686},
			{x = 1220.164, y = 501.171, z = 76.849},
			{x = 1212.41, y = 464.596, z = 14.831}
		}
	}
}

return MobSpawnData
