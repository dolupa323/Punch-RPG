-- SpawnConfig.lua
-- Zone 기반 사각형 구역 스폰 밸런싱 및 오픈월드 관리를 위한 설정 파일
-- 하나의 Place 내에서 X, Z 좌표 범위(Bounding Box)별로 구역을 구분한다.

local SpawnConfig = {}

--========================================
-- Zone 정의 (min/max bounds)
--========================================
local ZONES = {
	GRASSLAND = {
		min = Vector2.new(-532.6, -613.5),
		max = Vector2.new(1019.5, 187.2),
		spawnPoint = Vector3.new(-128, 22.9, -278), -- 초원섬 최신 스폰 지점
	},
	TROPICAL = {
		min = Vector2.new(-194.6, 1390.3),
		max = Vector2.new(1403.4, 2189.5),
		spawnPoint = Vector3.new(264.2, 35, 1761.4), -- 열대섬 리턴 포탈 지점
		portalEntry = Vector3.new(8.6, 20, -16.2), -- 초원섬 내 열대행 포탈 위치
	},
	DESERT = {
		min = Vector2.new(2218.5, -706.9),
		max = Vector2.new(3357.4, 307.3),
		spawnPoint = Vector3.new(2694.4, 35, 56.9), -- 사막섬 리턴 포탈 지점
		portalEntry = Vector3.new(-237, 33.3, -524), -- 초원섬 내 사막행 포탈 위치
	},
	SNOWY = {
		min = Vector2.new(2142.2, 1674.3),
		max = Vector2.new(3238.5, 3548.2),
		spawnPoint = Vector3.new(2473.5, 65, 1839.4), -- 설원섬 리턴 포탈 지점
		portalEntry = Vector3.new(-430.0, 58, -244.1), -- 초원섬 내 설원행 포탈 위치
	},
}

-- 신규 유저가 처음 게임에 접속했을 때 스폰될 기본 절대 좌표
SpawnConfig.DEFAULT_START_SPAWN = ZONES.GRASSLAND.spawnPoint

--========================================
-- Zone별 생태계 설정
--========================================
local ZONE_CONFIGS = {
	GRASSLAND = {
		Creatures = {
			{ id = "ARCHAEOPTERYX", weight = 100 },
			{ id = "TROODON", weight = 85 },
			{ id = "OLOROTITAN", weight = 10 },
		},
		Harvests = {
			{ id = "TREE_THIN", weight = 50 },
			{ id = "ROCK_SOFT", weight = 40 },
			{ id = "BUSH_BERRY", weight = 45 },
			{ id = "GROUND_FIBER", weight = 90 },
			{ id = "GROUND_BRANCH", weight = 120 },
		},
	},
	TROPICAL = {
		Creatures = {
			{ id = "PARASAUR", weight = 70 },
			{ id = "STEGOSAURUS", weight = 50 },
			{ id = "KELENKEN", weight = 50 },
			{ id = "DEINOCHEIRUS", weight = 30 },
		},
		Harvests = {
			{ id = "BUSH_BERRY", weight = 70 },
			{ id = "GROUND_FIBER", weight = 100 },
			{ id = "GROUND_BRANCH", weight = 100 },
			{ id = "ROCK_SOFT", weight = 50 },
			{ id = "FALM_TREE", weight = 55 },
			{ id = "OBSIDIAN_NODE", weight = 25 },
			{ id = "REED_BUSH", weight = 50 },
		},
	},
	DESERT = {
		Creatures = {
			{ id = "GIGANTORAPTOR", weight = 50 },
			{ id = "TRICERATOPS", weight = 35 },
			{ id = "TITANOSAURUS", weight = 10 },
			{ id = "ALLOSAURUS", weight = 5 },
		},
		Harvests = {
			{ id = "ROCK_SOFT", weight = 50 },
			{ id = "DESERT_TREE", weight = 40 },
			{ id = "DESERT_REED", weight = 30 },
			{ id = "BRONZE_ROCK", weight = 20 },
		},
	},
	SNOWY = {
		Creatures = {
			{ id = "ALLOSAURUS", weight = 40 },
			{ id = "TITANOSAURUS", weight = 15 },
		},
		Harvests = {
			{ id = "ROCK_SOFT", weight = 50 },
		},
	},
}

--========================================
-- 헬퍼 함수
--========================================

-- 가중치 기반 랜덤 선택
local function getRandomFromWeight(list)
	local totalWeight = 0
	for _, item in ipairs(list) do
		totalWeight = totalWeight + item.weight
	end
	
	local randomVal = math.random() * totalWeight
	local currentWeight = 0
	
	for _, item in ipairs(list) do
		currentWeight = currentWeight + item.weight
		if randomVal <= currentWeight then
			return item.id
		end
	end
	return list[1].id
end

--========================================
-- Zone 판정
--========================================

--- 사각형 범위(Bounding Box) 기반으로 위치가 속한 Zone 이름을 반환
--- @param position Vector3 월드 좌표
--- @return string? Zone 이름 ("GRASSLAND" | "TROPICAL" | "DESERT" | "SNOWY" | nil)
function SpawnConfig.GetZoneAtPosition(position: Vector3): string?
	if not position then return nil end
	
	local x, z = position.X, position.Z
	
	for zoneName, zone in pairs(ZONES) do
		if x >= zone.min.X and x <= zone.max.X and z >= zone.min.Y and z <= zone.max.Y then
			return zoneName
		end
	end
	
	return nil
end

--- 모든 Zone 이름 목록 반환
function SpawnConfig.GetAllZoneNames(): {string}
	local names = {}
	for zoneName in pairs(ZONES) do
		table.insert(names, zoneName)
	end
	return names
end

--- Zone 정보 조회 (min, max, spawnPoint 등)
function SpawnConfig.GetZoneInfo(zoneName: string): any?
	return ZONES[zoneName]
end

--- Zone의 생태계 설정 조회
function SpawnConfig.GetZoneConfig(zoneName: string): any?
	return ZONE_CONFIGS[zoneName]
end

--========================================
-- 레거시/유틸리티 함수
--========================================

function SpawnConfig.IsContentPlace(): boolean
	return true
end

function SpawnConfig.GetCurrentConfig()
	return ZONE_CONFIGS.GRASSLAND
end

--========================================
-- Zone별 랜덤 선택 함수
--========================================

function SpawnConfig.GetRandomCreatureForZone(zoneName: string): string?
	local config = ZONE_CONFIGS[zoneName]
	if not config or not config.Creatures then return nil end
	return getRandomFromWeight(config.Creatures)
end

function SpawnConfig.GetRandomHarvestForZone(zoneName: string): string?
	local config = ZONE_CONFIGS[zoneName]
	if not config or not config.Harvests then return nil end
	return getRandomFromWeight(config.Harvests)
end

function SpawnConfig.GetRandomGroundHarvestForZone(zoneName: string): string?
	local config = ZONE_CONFIGS[zoneName]
	if not config or not config.Harvests then return nil end
	local groundList = {}
	for _, item in ipairs(config.Harvests) do
		if item.id:find("GROUND") then
			table.insert(groundList, item)
		end
	end
	if #groundList == 0 then return nil end
	return getRandomFromWeight(groundList)
end

-- 기본값 (초원 기준)
function SpawnConfig.GetRandomCreature()
	return SpawnConfig.GetRandomCreatureForZone("GRASSLAND")
end

function SpawnConfig.GetRandomHarvest()
	return SpawnConfig.GetRandomHarvestForZone("GRASSLAND")
end

function SpawnConfig.GetRandomGroundHarvest()
	return SpawnConfig.GetRandomGroundHarvestForZone("GRASSLAND")
end

return SpawnConfig
