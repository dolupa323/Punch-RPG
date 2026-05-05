-- BotConfig.lua
-- Survivor Bot (가짜 유저) 설정

local BotConfig = {}

-- 봇 스폰 설정
BotConfig.MAX_BOTS = 10                -- 서버당 최대 봇 수
BotConfig.SPAWN_RADIUS = 500           -- 스폰 반경 (스터드)
BotConfig.NAME_VISIBLE_DIST = 50       -- 이름 표시 거리

-- 봇 이름 후보군 (부족/선사시대 느낌)
BotConfig.BOT_NAMES = {
	"Grog", "Kira", "Unga", "Bunga", "Tara", 
	"Moko", "Zul", "Raka", "Ona", "Hura",
	"Koda", "Nali", "Vorg", "Esh", "Jana",
	"Torg", "Lina", "Mura", "Dax", "Sola"
}

-- 봇 행동 타입 (Phase 2 확장용)
BotConfig.BotType = {
	WANDERER = "WANDERER",  -- 배회형
	GATHERER = "GATHERER",  -- 채집형
	WARRIOR = "WARRIOR",    -- 전투형
}

return BotConfig
