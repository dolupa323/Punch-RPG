-- MobSpawnData.lua
-- 월드 몬스터 구역별 스폰 좌표 및 에셋 템플릿 데이터 [Data-Driven Template]
local MobSpawnData = {
	["StartingZone_Slime"] = {
		spawnAreaId = "StartingZone_Slime",
		mobModelName = "Slime",
		mobDisplayName = "슬라임",
		maxHealth = 20,
		baseDamage = 6,     -- 한 방 데미지
		attackCooldown = 1.5, -- 공격 주기(초)
		respawnDelay = 1.0,
		modelScale = 0.8,
		xpReward = 12, -- 슬라임 처치 시 기본 경험치
		level = 3, -- 몬스터 레벨 추가

		-- [활성화]: 4개의 좌표를 꼭짓점 삼아 그 '내부 영역 전체'에 무작위 랜덤 스폰합니다!
		spawnAsPolygon = true,
		spawnCount = 15, -- 총 15마리 슬라임이 구역 안에서 제멋대로 젠 됩니다.

		-- [확정]: 사용자 스크린샷 기반 절대 좌표 반영
		-- 순서는 외곽을 따라가도록 맞춰서 polygon 삼각분할이 안정적으로 동작하게 유지
		spawnPositions = {
			{x = -277.952, y = 260.177, z = 240.502},
			{x = -285.595, y = 263.227, z = 121.537},
			{x = -419.98, y = 251.496, z = 102.266},
			{x = -434.738, y = 271.315, z = 228.362}
		}
	},

	["HornedLarvaZone"] = {
		spawnAreaId = "HornedLarvaZone",
		mobModelName = "HornedLarva",
		mobDisplayName = "뿔 애벌레",
		maxHealth = 90,
		baseDamage = 10,
		attackCooldown = 2.0, -- 공격 속도 2.0초
		respawnDelay = 2.0,   -- 부활 딜레이 2초
		modelScale = 0.07,    -- 몬스터 크기 정밀 축소 보정 (조금 더 선명해진 크기)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 세로 모델의 머리 방향(아래)을 전방으로 오도록 눕힘
		walkSpeed = 6,        -- 씩씩한 전진 속도
		xpReward = 30,
		level = 7,

		-- [활성화]: 4개의 꼭짓점 사각형 영역 내부에 뿔 애벌레 10마리 랜덤 스폰!
		spawnAsPolygon = true,
		spawnCount = 10,

		-- 유저 스크린샷 Properties 속성에서 100% 정밀 추출한 4개 꼭짓점 좌표
		spawnPositions = {
			{x = -248.838, y = 204.668, z = -196.585},
			{x = -357.219, y = 215.493, z = -206.382},
			{x = -396.7, y = 213.697, z = 31.497},
			{x = -273.007, y = 214.342, z = 30.909}
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
		level = 12,
		-- 스텀프 5마리 스폰 (스텀프 킹 제외)
		spawnEntries = {
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 330,
				baseDamage = 15,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 85,
				level = 12,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 330,
				baseDamage = 15,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 85,
				level = 12,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 330,
				baseDamage = 15,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 85,
				level = 12,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 330,
				baseDamage = 15,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 85,
				level = 12,
			},
			{
				mobModelName = "Stump",
				mobDisplayName = "스텀프",
				maxHealth = 330,
				baseDamage = 15,
				attackCooldown = 1.5,
				modelScale = 0.2,
				xpReward = 85,
				level = 12,
			},
		},
		spawnPositions = {
			{x = -215.001, y = 232.34, z = -425.888},
			{x = -238.797, y = 244.255, z = -246.924},
			{x = -378.935, y = 241.339, z = -237.11},
			{x = -380.47, y = 240.995, z = -443.279}
		}
	},

	["CyclopsBatZone"] = {
		spawnAreaId = "CyclopsBatZone",
		mobModelName = "CyclopsBat",
		mobDisplayName = "사이클롭스 박쥐",
		maxHealth = 4040,
		baseDamage = 35,
		attackCooldown = 0.8,
		respawnDelay = 3.0,
		modelScale = 0.09, -- 박쥐 고유 에셋 규격 조율 (0.09로 적당하게 축소)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 누워있는 비행 방향을 정면 수직으로 보정
		customHipHeight = 15.0, -- 공중 비행(Hovering) 높이 15.0 스터드로 강제 보정
		walkSpeed = 10,
		xpReward = 700,
		level = 29,

		spawnAsPolygon = true,
		spawnCount = 10, -- 스폰수 상향
		isIndoor = true,
		skipTerrainScan = true,

		spawnPositions = {
			{x = 471.762, y = 349.679, z = -1550.957},
			{x = 279.44, y = 348.811, z = -1544.267},
			{x = 289.605, y = 351.959, z = -1400.382},
			{x = 446.498, y = 346.666, z = -1390.943}
		}
	},

	["SmallGolemZone"] = {
		spawnAreaId = "SmallGolemZone",
		mobModelName = "SmallGolem",
		mobDisplayName = "작은 골렘",
		maxHealth = 2850,
		baseDamage = 32,
		attackCooldown = 2.5, -- 공격 속도는 다소 느림
		respawnDelay = 5.0,
		modelScale = 9.0,    -- 스텀프 킹 다음 티어가 확실히 느껴지도록 추가 확대
		walkSpeed = 5,       -- 느릿하고 묵직한 이동
		xpReward = 580,
		level = 26,

		spawnAsPolygon = true,
		spawnCount = 6,

		isIndoor = true,
		skipTerrainScan = false, -- [수정] 천장 고려는 유지하되, 바닥 정확도 보정을 위해 레이캐스트를 다시 사용

		spawnPositions = {
			{x = 289.603, y = 284.8, z = -1125.696},
			{x = 293.787, y = 284.8, z = -1191.427},
			{x = 412.594, y = 284.8, z = -1182.341},
			{x = 370.001, y = 284.72, z = -1089.959}
		}
	},

	["StumpKingZone"] = {
		spawnAreaId = "StumpKingZone",
		mobModelName = "StumpKing",
		mobDisplayName = "스텀프 킹",
		maxHealth = 1350,
		baseDamage = 24,
		attackCooldown = 3.0,
		respawnDelay = 20.0,
		modelScale = 0.075,    -- 검증 완료: 0.05 크기 대비 1.5배 적절하게 키운 최종 보스 황금 비율
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 누워있는 원본 모델을 수직으로 세우는 회전 보정
		walkSpeed = 8,
		xpReward = 320,
		level = 18,

		spawnAsPolygon = true,
		spawnCount = 2, -- 스텀프 킹 2마리씩 스폰되게 조정

		spawnPositions = {
			{x = -196.368, y = 212.597, z = -459.477},
			{x = -181.61, y = 215.512, z = -599.68},
			{x = -371.0, y = 213.745, z = -630.97},
			{x = -359.558, y = 212.253, z = -471.455}
		}
	},

	["DesertGuardianZone"] = {
		spawnAreaId = "DesertGuardianZone",
		level = 30,
		mobModelName = "DesertGuardian",
		mobDisplayName = "사막의 수호자",
		maxHealth = 40400,
		baseDamage = 80,
		attackCooldown = 2.5,
		respawnDelay = 60.0,
		modelScale = 0.25, -- 몬스터 크기 대폭 축소 보정
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- 뿔애벌레처럼 누워있는 뼈대 축 회전 보정
		customHipHeight = 0.0, -- 지면 밀착: 부유 효과 제거
		groundClearance = 0.0,
		snapVisualToGround = true,
		visualGroundSink = 3.0,
		hitboxScaleFromBounds = {x = 0.85, y = 0.9, z = 0.85}, -- 보스 비주얼 크기에 맞춰 HRP 피격 박스 확장
		walkSpeed = 10,
		xpReward = 4500,

		spawnAsPolygon = false, -- 보스는 정확한 중심 위치에 고정 스폰
		spawnCount = 1,
		isIndoor = false,
		skipTerrainScan = true,
		exactSpawnPosition = {x = -2002.4, y = -60.9, z = 940.0},

		-- 사막 보스 구역 4개 꼭짓점
		spawnPositions = {
			{x = -2151.013, y = -68.271, z = 808.698},
			{x = -1849.755, y = -59.272, z = 1067.421},
			{x = -1864.732, y = -56.357, z = 796.764},
			{x = -2144.129, y = -59.616, z = 1086.938}
		}
	},

	-- [바다 테마 리스킨] 수중도시 서쪽 협곡 레이드방 보스. 사막의 수호자와 동일한 모델/능력치를
	-- 재사용하되, MobSpawnService.lua의 DesertGuardian FSM 분기가 spawnAreaId로 이 존을 감지해서
	-- 공격 패턴 색감만 모래톤 -> 바다톤으로 자동 전환함 (사막존 원본은 그대로 유지).
	["AbyssGuardianZone"] = {
		spawnAreaId = "AbyssGuardianZone",
		-- [요청반영] 같은 수중도시 월드보스인 크라켄과 스펙(레벨/체력/공격력/리스폰/경험치)을 맞춤
		level = 65,
		mobModelName = "DesertGuardian",
		mobDisplayName = "심연의 수호자",
		maxHealth = 450000,
		baseDamage = 450,
		attackCooldown = 2.5,
		respawnDelay = 90.0,
		modelScale = 0.17, -- [요청반영] 사막 원본(0.25)보다 축소
		spawnRotationOffset = {x = 90, y = 0, z = 0},
		customHipHeight = 0.0,
		groundClearance = 0.0,
		snapVisualToGround = false, -- 수중 협곡 레이드방은 바닥이 뜬 구조라 지면 스냅 불필요
		hitboxScaleFromBounds = {x = 0.85, y = 0.9, z = 0.85},
		walkSpeed = 6,
		xpReward = 30000,

		spawnAsPolygon = false,
		spawnCount = 1,
		isIndoor = true,
		skipTerrainScan = true,
		exactSpawnPosition = {x = -731, y = 100, z = 203.2}, -- 서쪽 협곡 레이드방 BossSpawnMarker
	},

	["SpiderZone"] = {
		spawnAreaId = "SpiderZone",
		level = 33, -- 거 거미 레벨 33
		mobModelName = "Spider",
		mobDisplayName = "거미",
		maxHealth = 1100,    -- [상향] 최종 구역 몬스터에 맞게 체력 대폭 상향 (기존 150 -> 1200 -> 700 조정)
		baseDamage = 30,     -- [상향] 공격력 대폭 상향 (기존 15 -> 45 -> 30 조정)
		attackCooldown = 1.5, -- [상향] 공격 속도 상승 (기존 2.0 -> 1.5)
		respawnDelay = 5.0,
		modelScale = 0.005,  -- 거미 실루엣이 더 확실히 보이도록 크기 상향
		walkSpeed = 16,      -- [상향] 이동 속도 상승 (기존 12 -> 16)
		xpReward = 450,      -- [상향] 경험치 보상 대폭 상향 (기존 60 -> 500 -> 450 조정)

		spawnAsPolygon = true,
		spawnCount = 0, -- [임시 비활성화] 원인 불명의 무한 스폰/드롭 스팸 디버깅을 위해 0으로 설정
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
		level = 63,
		mobModelName = "BlueFlameKnight",
		mobDisplayName = "푸른 불꽃 기사",
		maxHealth = 134000,
		baseDamage = 200,
		attackCooldown = 2.0,  -- 공격 휘두르는 속도
		respawnDelay = 60.0,   -- 처치 후 1분 뒤 리스폰
		modelScale = 1.5,      -- 기본 R6 모델보다 큼 (위압감)
		customHipHeight = 1.8, -- [옵션] 3.0 이상 띄울 때 발이 공중에 뜨면 1.8로 보정 (다리 길이에 따라 조정)
		walkSpeed = 12,        -- 평상시 추격 이속
		xpReward = 12000,

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

	["DeepAbyss_Kraken"] = {
		spawnAreaId = "DeepAbyss_Kraken",
		-- [밸런스 수정] 레벨을 만렙(50)에 맞추면 몹 레벨차 데미지 페널티(AvatarService)가 0이 되어
		-- 오히려 하늘섬 보스(BlueFlameKnight, Lv63)보다 쉬워지는 모순이 있었음. "다음 지역이니 더
		-- 강해야 한다"는 아래 코멘트 의도에 맞춰 BlueFlameKnight보다 약간 높은 레벨로 조정.
		level = 65,
		mobModelName = "Kraken",
		dropTableId = "KRAKEN",
		mobDisplayName = "크라켄",
		-- [밸런스 조정] 수중도시는 하늘섬(BlueFlameKnight: 체력13.4만/공격200) 다음 지역이므로
		-- 그보다 확실히 강해야 함 -> 체력/공격력 대폭 상향
		maxHealth = 450000,
		baseDamage = 450,
		attackCooldown = 2.5,   -- 패턴 미정 상태의 임시값 (추후 패턴 추가 시 조정)
		respawnDelay = 90.0,    -- 처치 후 1분 30초 뒤 리스폰
		-- [자체 제작 모델] Parts로 직접 제작(맨틀+촉수 8개, Motor6D 체인)한 실제 크기라 modelScale 불필요
		-- 촉수 8개가 넓게 퍼진 형태라 HRP 기준 판정 반경이 어긋날 수 있어 바운딩 박스 기반 히트박스 사용
		hitboxScaleFromBounds = {x = 1.0, y = 1.0, z = 1.0},
		walkSpeed = 6,          -- 거대한 심해 크라켄이라 느릿느릿하게 이동
		xpReward = 30000,

		spawnAsPolygon = false, -- 보스는 무작위 스폰이 아닌 보스방 정중앙 고정 스폰
		spawnCount = 1,
		isIndoor = true,        -- 실내(천장 있음) 환경
		skipTerrainScan = true, -- RaidArena 바닥 높이(Y=68)에 정확히 안착시키기 위해 exactSpawnPosition을 그대로 사용
		exactSpawnPosition = {x = 798.4, y = 100, z = 197.6}, -- 촉수가 아래로 길게 늘어지므로 여유있게 높은 위치에서 시작 (자동 HipHeight 보정이 바닥에 맞춰줌)
	},

	-- [수중도시 4번째 레이드방] 크라켄(DeepAbyss)/사막의 수호자(DeepAbyss_West)에 이은
	-- 다음 자리 - DeepAbyss_North의 정식 RaidArena.BossSpawnMarker 좌표에 배치
	["DeepAbyss_North_Poseidon"] = {
		spawnAreaId = "DeepAbyss_North_Poseidon",
		level = 65,
		mobModelName = "Poseidon",
		dropTableId = "KRAKEN", -- 임시로 크라켄 드롭 재사용 (정식 드롭 테이블 확정 전까지)
		mobDisplayName = "포세이돈",
		maxHealth = 450000,
		baseDamage = 450,
		attackCooldown = 2.5,
		respawnDelay = 90.0,
		hitboxScaleFromBounds = {x = 1.0, y = 1.0, z = 1.0}, -- 자체 제작 Parts 모델이라 실제 크기 그대로
		walkSpeed = 8,
		xpReward = 30000,

		spawnAsPolygon = false,
		spawnCount = 1,
		isIndoor = true,
		skipTerrainScan = true,
		exactSpawnPosition = {x = -50.7, y = 100, z = -411.8}, -- DeepAbyss_North.RaidArena.BossSpawnMarker 실측 좌표
	},

	["GhostKnightZone"] = {
		spawnAreaId = "GhostKnightZone",
		level = 58,
		mobModelName = "GhostKnight",
		dropTableId = "GIANTGHOSTKNIGHT",
		mobDisplayName = "유령기사(거인)",
		maxHealth = 39100,
		baseDamage = 90,
		attackCooldown = 2.2,   -- 공격 속도
		respawnDelay = 30.0,    -- 처치 후 30초 뒤 리스폰
		modelScale = 2.5,       -- 기존 모델보다 거대하게 2.5배 확대
		customHipHeight = 1.5,  -- [크기 스케일링 대비]: 중앙이 뜬다는 제보가 있으니 1.5로 낮춤 (다리 길이에 비례)
		walkSpeed = 9,          -- 기본 이동 속도
		xpReward = 4500,

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
		level = 48,
		mobModelName = "GhostKnight",
		mobDisplayName = "유령기사",
		maxHealth = 12650,
		baseDamage = 68,
		attackCooldown = 2.5,   -- 공격속도
		respawnDelay = 15.0,    -- 처치 후 15초 뒤 리스폰
		modelScale = 1.0,       -- 일반 사이즈
		customHipHeight = 1.0,  -- 기본 모델에 맞는 높이
		walkSpeed = 10,         -- 일반 이동 속도
		xpReward = 1600,

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
		level = 53,
		mobModelName = "GhostWizard",
		mobDisplayName = "유령 마법사",
		maxHealth = 15600,
		baseDamage = 80,
		attackCooldown = 3.0,   -- 원거리 캐스팅 속도
		respawnDelay = 15.0,    -- 처치 후 15초 뒤 리스폰
		modelScale = 1.0,       -- 일반 사이즈
		customHipHeight = 1.0,  -- 기본 모델에 맞는 높이
		walkSpeed = 8,          -- 일반 기사보다 느린 이동 속도
		xpReward = 2200,

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
		level = 23,
		mobModelName = "Samurai",
		mobDisplayName = "사무라이",
		maxHealth = 1600,
		baseDamage = 28,
		attackCooldown = 2.0,
		respawnDelay = 15.0,
		modelScale = 1.6,
		customHipHeight = 1.0, -- 지면 밀착을 위해 1.0으로 복구
		walkSpeed = 11, -- 약간 기민한 이동 속도
		xpReward = 380,

		spawnAsPolygon = true,
		spawnCount = 6, -- 스폰 마리수 6마리로 증가
		isIndoor = true, -- 상공의 하늘섬 지형 간섭 방지 (Y축 레이캐스트 보정)
		raycastStartOffsetY = 150, -- 하늘섬(Y=500)을 피해 Y=130대에서 높이 시작하여 땅속에 묻히지 않게 보장
		raycastDepth = -300,

		-- 유저 제공 Properties 4개 꼭짓점 좌표 반영
		spawnPositions = {
			{x = -149.68, y = 416.38, z = -1026.644},
			{x = -93.685, y = 419.295, z = -1332.117},
			{x = -375.734, y = 407.381, z = -1297.102},
			{x = -350.584, y = 416.036, z = -1035.45}
		}
	},

	["IceKnightZone"] = {
		spawnAreaId = "IceKnightZone",
		level = 38,
		mobModelName = "IceKnight",
		mobDisplayName = "얼음 기사",
		maxHealth = 14000,
		baseDamage = 52,
		attackCooldown = 2.2,
		respawnDelay = 15.0,
		modelScale = 2.5,    -- [수정] 얼음 기사 크기 상향 (1.5 -> 2.5)
		customHipHeight = 1.0, -- 지면 밀착 안착 높이
		walkSpeed = 8, -- 약간 묵직한 이동 속도
		xpReward = 900,

		spawnAsPolygon = true,
		spawnCount = 4, -- 스폰 마리수 4마리
		isIndoor = true, -- 지형 고도 레이캐스트 스캔 적용
		raycastStartOffsetY = 100, -- 눈산 고도보다 충분히 높은 곳에서 지면 레이캐스트 시작
		raycastDepth = -200,

		spawnPositions = {
			{x = 1136.166, y = 368.974, z = -1575.19},
			{x = 981.651, y = 371.275, z = -1573.427},
			{x = 971.592, y = 380.672, z = -1333.505},
			{x = 1139.045, y = 367.672, z = -1330.537}
		}
	},

	["IceKnightZone2"] = {
		spawnAreaId = "IceKnightZone2",
		level = 38,
		mobModelName = "IceKnight",
		mobDisplayName = "얼음 기사",
		maxHealth = 7650,
		baseDamage = 46,
		attackCooldown = 2.2,
		respawnDelay = 15.0,
		modelScale = 2.5,    -- [수정] 얼음 기사 2구역 크기 상향 (1.5 -> 2.5)
		customHipHeight = 1.0,
		walkSpeed = 8,
		xpReward = 750,

		spawnAsPolygon = true,
		spawnCount = 0,
		isIndoor = true,
		raycastStartOffsetY = 100,
		raycastDepth = -200,

		-- 두 번째 스폰지역 좌표 반영
		spawnPositions = {}
	},

	-- [레벨디자인 보강] 얼음 기사(38)와 유령기사(48) 사이 갭을 메우는 신규 사냥터.
	-- 사무라이존 서쪽 화산 능선 지대(VolcanicField)에 배치.
	["LavaSlimeZone"] = {
		spawnAreaId = "LavaSlimeZone",
		level = 41,
		mobModelName = "LavaSlime",
		mobDisplayName = "용암 슬라임",
		maxHealth = 8500,
		baseDamage = 50,
		attackCooldown = 1.5,
		respawnDelay = 10.0,
		modelScale = 3.2, -- [요청반영] 크기 대폭 확대
		xpReward = 850,

		spawnAsPolygon = true,
		spawnCount = 8,
		isIndoor = false,

		-- 화산 분지 4개 꼭짓점 (사용자 제공 실측 좌표)
		spawnPositions = {
			{x = -961.977, y = 574.234, z = -907.889},
			{x = -641.514, y = 550.443, z = -902.067},
			{x = -655.299, y = 551.708, z = -1220.3},
			{x = -957.604, y = 587.019, z = -1185.684},
		}
	},

	["FireManZone"] = {
		spawnAreaId = "FireManZone",
		level = 45,
		mobModelName = "FireMan", -- [자체 제작] 크라켄처럼 Part/WedgePart로 직접 제작 (앤더맨 모티브의 불타는 시커먼 형체)
		mobDisplayName = "파이어맨",
		maxHealth = 12000,
		baseDamage = 60,
		attackCooldown = 2.0,
		respawnDelay = 14.0,
		modelScale = 1.0,
		walkSpeed = 12,
		xpReward = 1300,

		spawnAsPolygon = true,
		spawnCount = 5,
		isIndoor = false,

		-- 화산 분지 4개 꼭짓점 (사용자 제공 실측 좌표)
		spawnPositions = {
			{x = -961.977, y = 574.234, z = -907.889},
			{x = -641.514, y = 550.443, z = -902.067},
			{x = -655.299, y = 551.708, z = -1220.3},
			{x = -957.604, y = 587.019, z = -1185.684},
		}
	},

	["IceDragonZone"] = {
		spawnAreaId = "IceDragonZone",
		level = 33,
		mobModelName = "IceDragon",
		mobDisplayName = "아이스 드래곤",
		maxHealth = 8000,
		baseDamage = 38,
		attackCooldown = 2.2,
		respawnDelay = 15.0,
		modelScale = 0.08, -- [수정] 크기 추가 축소 (0.15 -> 0.08)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- [추가] 정자세 스폰용 회전 보정
		customHipHeight = 5.0, -- 공중 비행(Hovering) 높이 5.0 스터드로 보정
		walkSpeed = 8,
		xpReward = 520,

		spawnAsPolygon = true,
		spawnCount = 8, -- 스폰수 상향
		isIndoor = true,
		raycastStartOffsetY = 100,
		raycastDepth = -200,

		spawnPositions = {
			{x = 941.079, y = 368.974, z = -1574.317},
			{x = 786.565, y = 371.275, z = -1572.554},
			{x = 776.506, y = 380.672, z = -1332.632},
			{x = 943.959, y = 367.672, z = -1329.664}
		}
	},

	["IceDragonZone2"] = {
		spawnAreaId = "IceDragonZone2",
		level = 33,
		mobModelName = "IceDragon",
		mobDisplayName = "아이스 드래곤",
		maxHealth = 8000,
		baseDamage = 38,
		attackCooldown = 2.2,
		respawnDelay = 15.0,
		modelScale = 0.08, -- [수정] 크기 추가 축소 (0.15 -> 0.08)
		spawnRotationOffset = {x = 90, y = 0, z = 0}, -- [추가] 정자세 스폰용 회전 보정
		customHipHeight = 5.0, -- 공중 비행(Hovering) 높이 5.0 스터드로 보정
		walkSpeed = 8,
		xpReward = 520,

		spawnAsPolygon = true,
		spawnCount = 0,
		isIndoor = true,
		raycastStartOffsetY = 100,
		raycastDepth = -200,

		-- 얼음 기사 2구역과 동일한 좌표 반영
		spawnPositions = {}
	},

	["JellyfishZone"] = {
		spawnAreaId   = "JellyfishZone",
		level         = 50, -- 현재 만렙이 50이라 레벨 상한에 맞춤
		mobModelName  = "Jellyfish",
		mobDisplayName = "젤리피쉬",
		maxHealth     = 22000,
		baseDamage    = 65,
		attackCooldown = 2.2,
		respawnDelay  = 12.0,
		modelScale    = 7.0,    -- 24.6 * 7 ≈ 172 스터드
		walkSpeed     = 12,
		xpReward      = 2800,
		isSwimming    = true,   -- 3D 자유유영 (지면 레이캐스트 제외)
		aggroRadius   = 55,

		spawnAsPolygon = false,
		spawnCount    = 10,
		isIndoor      = true,
		raycastStartOffsetY = 0,
		raycastDepth  = 0,

		spawnPositions = {
			{x = 243, y = 100, z = 255},
			{x = 290, y = 110, z = 274},
			{x = 335, y = 108, z = 260},
			{x = 380, y = 107, z = 256},
			{x = 425, y =  97, z = 248},
			{x = 469, y = 102, z = 230},
			{x = 517, y = 106, z = 200},
			{x = 557, y =  98, z = 190},
			{x = 605, y = 102, z = 188},
			{x = 650, y = 100, z = 198},
		},
	},
}

return MobSpawnData
