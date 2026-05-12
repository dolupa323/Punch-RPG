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
		modelScale = 0.8, -- 추가 다이어트 반영 (1.0 이하로 축소)
		
		-- [활성화]: 4개의 좌표를 꼭짓점 삼아 그 '내부 영역 전체'에 무작위 랜덤 스폰합니다!
		spawnAsPolygon = true, 
		spawnCount = 6, -- 총 6마리 슬라임이 구역 안에서 제멋대로 젠 됩니다.
		
		-- [활성화]: 고정 좌표 리스트 (꼭짓점 경계)
		spawnPositions = {
			{x = -266.563, y = 1.235, z = 498.755}, -- 1번 지점
			{x = -196.063, y = 1.235, z = 402.724}, -- 2번 지점
			{x = -303.963, y = 1.235, z = 363.024}, -- 3번 지점
			{x = -351.063, y = 1.235, z = 434.624}  -- 4번 지점
		}
	}
}

return MobSpawnData
