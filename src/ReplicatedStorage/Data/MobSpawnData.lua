-- MobSpawnData.lua
-- 월드 몬스터 구역별 스폰 좌표 및 에셋 템플릿 데이터 [Data-Driven Template]
local MobSpawnData = {
	["StartingZone_Slime"] = {
		spawnAreaId = "StartingZone_Slime",
		mobModelName = "Slime",
		mobDisplayName = "슬라임",
		maxHealth = 35,
		baseDamage = 5,     -- 한 방 데미지
		attackCooldown = 1.5, -- 공격 주기(초)
		respawnDelay = 1.0,
		modelScale = 0.8,
		xpReward = 10, -- 슬라임 처치 시 기본 경험치 (하향)
		level = 3, -- 몬스터 레벨 추가
		
		-- [활성화]: 4개의 좌표를 꼭짓점 삼아 그 '내부 영역 전체'에 무작위 랜덤 스폰합니다!
		spawnAsPolygon = true, 
		spawnCount = 6, -- 총 6마리 슬라임이 구역 안에서 제멋대로 젠 됩니다.
		
		-- [확정]: 사용자 스크린샷 기반 절대 좌표 반영
		-- 순서는 외곽을 따라가도록 맞춰서 polygon 삼각분할이 안정적으로 동작하게 유지
		spawnPositions = {
			{x = -922.388, y = -30.945, z = 1269.169},
			{x = -555.075, y = -33.995, z = 1397.042},
			{x = -658.257, y = -22.857, z = 1540.193},
			{x = -951.85, y = -42.676, z = 1404.165}
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
		xpReward = 40,        -- 풍부한 경험치 보상 (하향 조정)
		level = 8, -- 몬스터 레벨 추가
		
		-- [활성화]: 4개의 꼭짓점 사각형 영역 내부에 뿔 애벌레 10마리 랜덤 스폰!
		spawnAsPolygon = true,
		spawnCount = 10,       
		
		-- 유저 스크린샷 Properties 속성에서 100% 정밀 추출한 4개 꼭짓점 좌표
		-- 외곽을 따라가는 순서로 배치
		spawnPositions = {
			{x = -1006.012, y = -87.932, z = 1729.527},
			{x = -824.111, y = -97.606, z = 1814.448},
			{x = -710.737, y = -93.947, z = 1638.615},
			{x = -963.822, y = -88.578, z = 1544.864}
		}
	},
	
	["StumpZone"] = {
		spawnAreaId = "StumpZone",
		spawnAsPolygon = true,
		spawnCount = 5,
		respawnDelay = 15.0,
		spawnRotationOffset = {x = 90, y = 0, z = 0},
		customHipHeight = 1.2,
		walkSpeed = 10,
		level = 13, -- 몬스터 기본 레벨 추가
		-- 스텀프 5마리 스폰 (스텀프 킹 제외)
		spawnEntries = {
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 300,
				baseDamage = 18,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 250,
				level = 13,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 300,
				baseDamage = 18,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 250,
				level = 13,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 300,
				baseDamage = 18,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 250,
				level = 13,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 300,
				baseDamage = 18,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 250,
				level = 13,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 300,
				baseDamage = 18,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 250,
				level = 13,
			},
		},
		spawnPositions = {
			{x = -1611.779, y = -70.431, z = 1605.406},
			{x = -1391.265, y = -70.087, z = 1542.456},
			{x = -1421.699, y = -67.172, z = 1405.311},
			{x = -1652.929, y = -79.086, z = 1439.088}
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
		level = 23, -- 박쥐 레벨 23
		
		spawnAsPolygon = true,
		spawnCount = 4, -- 4마리 배치
		isIndoor = true,
		skipTerrainScan = true,
		
		spawnPositions = {
			{x = -585.736, y = -341.991, z = 2412.599},
			{x = -785.001, y = -339.711, z = 2346.044},
			{x = -918.129, y = -345.004, z = 2623.978},
			{x = -687.244, y = -342.859, z = 2729.772}
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
		modelScale = 4.5,    -- [수정] 살짝 더 키워달라는 요청 반영 (4.0 -> 4.5배 확대)
		walkSpeed = 5,       -- 느릿하고 묵직한 이동
		xpReward = 200,      -- 높은 경험치 보상 (상향 조정)
		level = 18, -- 작은 골렘 레벨 18
		
		spawnAsPolygon = true,
		spawnCount = 6,
		
		isIndoor = true,
		skipTerrainScan = false, -- [수정] 천장 고려는 유지하되, 바닥 정확도 보정을 위해 레이캐스트를 다시 사용
		
		spawnPositions = {
			{x = -622.158, y = -370.514, z = 1939.376},
			{x = -375.183, y = -370.514, z = 2052.879},
			{x = -466.153, y = -370.514, z = 2204.655},
			{x = -670.563, y = -370.514, z = 2114.954}
		}
	},
	
	["StumpKingZone"] = {
		spawnAreaId = "StumpKingZone",
		mobModelName = "StumpKing",
		mobDisplayName = "스텀프 킹",
		maxHealth = 1200,
		baseDamage = 35,
		attackCooldown = 3.0,
		respawnDelay = 20.0,
		modelScale = 0.075,    -- 검증 완료: 0.05 크기 대비 1.5배 적절하게 키운 최종 보스 황금 비율
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 누워있는 원본 모델을 수직으로 세우는 회전 보정
		walkSpeed = 8,
		xpReward = 1000,
		level = 28, -- 스텀프 킹 레벨 28
		
		spawnAsPolygon = true,
		spawnCount = 2, -- 스텀프 킹 2마리씩 스폰되게 조정
		
		spawnPositions = {
			{x = -2018.001, y = -42.021, z = 1607.719},
			{x = -1860.809, y = -41.677, z = 1562.279},
			{x = -1895.659, y = -38.762, z = 1425.677},
			{x = -2037.874, y = -50.676, z = 1427.003}
		}
	},
	
	["SpiderZone"] = {
		spawnAreaId = "SpiderZone",
		level = 33, -- 거미 레벨 33
		mobModelName = "Spider",
		mobDisplayName = "거미",
		maxHealth = 700,    -- [상향] 최종 구역 몬스터에 맞게 체력 대폭 상향 (기존 150 -> 1200 -> 700 조정)
		baseDamage = 30,     -- [상향] 공격력 대폭 상향 (기존 15 -> 45 -> 30 조정)
		attackCooldown = 1.5, -- [상향] 공격 속도 상승 (기존 2.0 -> 1.5)
		respawnDelay = 5.0,
		modelScale = 0.003,
		walkSpeed = 16,      -- [상향] 이동 속도 상승 (기존 12 -> 16)
		xpReward = 450,      -- [상향] 경험치 보상 대폭 상향 (기존 60 -> 500 -> 450 조정)
		
		spawnAsPolygon = true,
		spawnCount = 4,
		isIndoor = true,
		skipTerrainScan = true,
		
		spawnPositions = {
			{x = -1278.704, y = 7.924, z = 2503.958},
			{x = -1101.201, y = -30.295, z = 1997.338},
			{x = -928.863, y = -30.452, z = 2107.137},
			{x = -1047.553, y = -5.076, z = 2550.495}
		}
	},
	
	["SkyIsland_BlueFlameKnight"] = {
		spawnAreaId = "SkyIsland_BlueFlameKnight",
		level = 53, -- 푸른불꽃의 기사 레벨 53
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
		level = 48, -- 유령기사(거인) 레벨 48
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
		level = 38, -- 유령기사 레벨 38
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
		level = 43, -- 유령마법사 레벨 43
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
	},
	
	["SamuraiZone"] = {
		spawnAreaId = "SamuraiZone",
		level = 40, -- 사무라이 기본 레벨 40 설정
		mobModelName = "Samurai",
		mobDisplayName = "사무라이",
		maxHealth = 3000, -- 기사급의 체력
		baseDamage = 50, -- 날카로운 참격 데미지
		attackCooldown = 2.0,
		respawnDelay = 15.0,
		modelScale = 1.6,
		customHipHeight = 1.0, -- 지면 밀착을 위해 1.0으로 복구
		walkSpeed = 11, -- 약간 기민한 이동 속도
		xpReward = 600,
		
		spawnAsPolygon = true,
		spawnCount = 6, -- 스폰 마리수 6마리로 증가
		isIndoor = true, -- 상공의 하늘섬 지형 간섭 방지 (Y축 레이캐스트 보정)
		raycastStartOffsetY = 150, -- 하늘섬(Y=500)을 피해 Y=130대에서 높이 시작하여 땅속에 묻히지 않게 보장
		raycastDepth = -300,
		
		-- 유저 제공 Properties 4개 꼭짓점 좌표 반영
		spawnPositions = {
			{x = -1937.312, y = 25.096, z = 2133.741},
			{x = -1754.342, y = 37.01, z = 2110.797},
			{x = -1708.144, y = 34.095, z = 2349.627},
			{x = -1865.336, y = 33.751, z = 2395.068}
		}
	},
	
	["IceKnightZone"] = {
		spawnAreaId = "IceKnightZone",
		level = 45, -- 얼음 기사 레벨 45 설정
		mobModelName = "IceKnight",
		mobDisplayName = "얼음 기사",
		maxHealth = 6000, -- 튼튼한 체력
		baseDamage = 60, -- 묵직한 냉기 데미지
		attackCooldown = 2.2,
		respawnDelay = 15.0,
		modelScale = 1.5,
		customHipHeight = 1.0, -- 지면 밀착 안착 높이
		walkSpeed = 8, -- 약간 묵직한 이동 속도
		xpReward = 1200,
		
		spawnAsPolygon = true,
		spawnCount = 4, -- 스폰 마리수 4마리
		isIndoor = true, -- 지형 고도 레이캐스트 스캔 적용
		raycastStartOffsetY = 100, -- 눈산 고도보다 충분히 높은 곳에서 지면 레이캐스트 시작
		raycastDepth = -200,
		
		-- 유저 제공 Properties MeshPart "Realistic Stone" 4개 꼭짓점 좌표 반영
		spawnPositions = {
			{x = -41.777, y = -52.658, z = 3218.926},
			{x = -241.641, y = -78.034, z = 2938.122},
			{x = -488.123, y = -77.877, z = 3056.269},
			{x = -248.026, y = -39.658, z = 3329.409}
		}
	},
	
	["IceKnightZone2"] = {
		spawnAreaId = "IceKnightZone2",
		level = 45, -- 얼음 기사 레벨 45 설정
		mobModelName = "IceKnight",
		mobDisplayName = "얼음 기사",
		maxHealth = 6000,
		baseDamage = 60,
		attackCooldown = 2.2,
		respawnDelay = 15.0,
		modelScale = 1.5,
		customHipHeight = 1.0,
		walkSpeed = 8,
		xpReward = 1200,
		
		spawnAsPolygon = true,
		spawnCount = 4, -- 추가 구역 스폰 마리수 4마리
		isIndoor = true,
		raycastStartOffsetY = 100,
		raycastDepth = -200,
		
		-- 두 번째 스폰지역 좌표 반영
		spawnPositions = {
			{x = -450.573, y = -34.651, z = 2979.76},
			{x = -343.85, y = -47.651, z = 2937.212},
			{x = -529.822, y = -73.027, z = 2611.048},
			{x = -621.871, y = -72.87, z = 2684.114}
		}
	}
}

return MobSpawnData
