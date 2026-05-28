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
			{x = -266.563, y = 0.335, z = 498.755}, -- 스크린샷 3번 지점
			{x = -196.063, y = 1.235, z = 402.724}, -- 스크린샷 4번 지점
			{x = -303.963, y = 1.235, z = 363.024}, -- 스크린샷 2번 지점
			{x = -351.063, y = 1.235, z = 434.624}  -- 스크린샷 1번 지점
		}
	},
	
	["DungBeetleZone"] = {
		spawnAreaId = "DungBeetleZone",
		mobModelName = "DungBeetle",
		mobDisplayName = "쇠똥구리",
		maxHealth = 120,      -- 쇠똥구리 강력함 반영
		baseDamage = 12,      -- 슬라임보다 강력한 공격력
		attackCooldown = 2.0, -- 공격 속도 2.0초
		respawnDelay = 2.0,   -- 부활 딜레이 2초
		modelScale = 0.005,   -- [초대형 에셋 보정]: 800스터드급 괴수 에셋을 알맞은 4스터드 크기로 정밀 축소!
		walkSpeed = 6,        -- [추가] 쇠똥구리 특유의 묵직하고 씩씩한 전진 속도
		xpReward = 90,        -- 풍부한 경험치 보상
		
		-- [활성화]: 4개의 꼭짓점 사각형 영역 내부에 쇠똥구리 5마리 랜덤 스폰!
		spawnAsPolygon = true,
		spawnCount = 5,       
		
		-- 유저 스크린샷 Properties 속성에서 100% 정밀 추출한 4개 꼭짓점 좌표
		spawnPositions = {
			{x = -306.025, y = 0.561, z = 349.748}, -- 꼭짓점 1번 (Realistic Stone)
			{x = -208.725, y = 0.561, z = 361.948}, -- 꼭짓점 2번 (Realistic Stone)
			{x = -213.225, y = 0.561, z = 288.448}, -- 꼭짓점 3번 (Realistic Stone)
			{x = -306.025, y = 0.561, z = 288.448}  -- 꼭짓점 4번 (Realistic Stone)
		}
	},
	
	["FireLizardZone"] = {
		spawnAreaId = "FireLizardZone",
		mobModelName = "FireLizard",
		mobDisplayName = "화염의 불도마뱀",
		maxHealth = 600,
		baseDamage = 25,
		attackCooldown = 3.0,
		respawnDelay = 15.0,  -- 사망 후 정확히 15.0초 뒤 리스폰
		modelScale = 0.015,     -- 중간보스 0.015배 정밀 다운스케일 보정 (4스터드 대비 12스터드 보스급 비율)
		walkSpeed = 10,
		xpReward = 400,
		spawnCount = 1,
		spawnAsPolygon = true, -- [활성화] 꼭짓점 사각형 영역 내부에 불도마뱀 스폰!
		spawnPositions = {
			{x = -306.025, y = 0.561, z = 272.848}, -- 꼭짓점 1번 (Realistic Stone)
			{x = -208.725, y = 0.561, z = 277.548}, -- 꼭짓점 2번 (Realistic Stone)
			{x = -177.954, y = 1.445, z = 215.782}, -- 꼭짓점 3번 (Realistic Stone)
			{x = -271.54, y = 0.561, z = 204.048}   -- 꼭짓점 4번 (Realistic Stone)
		}
	},
	
	["VampireWolfZone"] = {
		spawnAreaId = "VampireWolfZone",
		mobModelName = "VampireWolf",
		mobDisplayName = "흡혈 늑대",
		maxHealth = 350,  -- [상향] 180 -> 350 (맷집 강화)
		baseDamage = 35,  -- [상향] 18 -> 35 (치명적인 늑대 이빨 데미지)
		attackCooldown = 1.5, -- [수정] 1.0초 시 시스템 쿨타임(1.1초)과 충돌하여 1.5로 너프
		respawnDelay = 3.0,
		modelScale = 0.015, -- [수정] 크기를 더 키워달라는 요청에 따라 0.008 -> 0.015배로 확대
		walkSpeed = 10,   -- 늑대 특유의 빠른 이속
		xpReward = 120,
		
		spawnAsPolygon = true,
		spawnCount = 4, -- 4마리 배치
		
		spawnPositions = {
			{x = -168.149, y = 6.702, z = 189.711},
			{x = -143.127, y = 10.384, z = -15.972},
			{x = -232.063, y = 3.521, z = -16.382},
			{x = -263.929, y = 6.286, z = 179.344}
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
		
		spawnAsPolygon = true,
		spawnCount = 5,      -- 동굴 내부에 5마리 랜덤 배치
		
		isIndoor = true,     -- [추가] 동굴 천장 위로 스폰되는 현상을 막기 위해 실내 판정 적용
		
		-- 유저 제공 스크린샷 기반 동굴 구역 꼭짓점 좌표 (시계 방향 정렬)
		spawnPositions = {
			{x = -222.482, y = -1.003, z = -72.143},  -- Top Left
			{x = -63.286, y = -6.928, z = -75.227},   -- Top Right
			{x = -64.303, y = -8.856, z = -126.754},  -- Bottom Right
			{x = -225.556, y = -6.728, z = -139.186}  -- Bottom Left
		}
	},
	
	["BigGolemZone"] = {
		spawnAreaId = "BigGolemZone",
		mobModelName = "BigGolem",
		mobDisplayName = "거대 골렘",
		maxHealth = 2000,
		baseDamage = 50,
		attackCooldown = 3.0,
		respawnDelay = 20.0,
		modelScale = 16.0,    -- 8배에서 다시 2배(총 16배)로 초대형화
		walkSpeed = 8,
		xpReward = 1000,
		
		spawnAsPolygon = true,
		spawnCount = 1,
		
		spawnPositions = {
			{x = 27.652, y = 11.083, z = 121.988},
			{x = -77.52, y = 11.522, z = 123.529},
			{x = 26.635, y = 10.497, z = 28.371},
			{x = -76.426, y = 9.9, z = 13.452}
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
			{x = 46.71, y = 13.686, z = 75.196},
			{x = 203.777, y = 14.127, z = 64.349},
			{x = 199.962, y = 14.837, z = -26.702},
			{x = 48.244, y = 13.695, z = -19.045}
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
