-- LiveOpsManager.lua
-- 현업 상용 게임 스튜디오 레벨 LiveOps 운영, 디버깅 및 업데이트 최적화 통합 모듈
-- 1. 디버깅 간소화 (로그 등급제 및 스코프 필터링)
-- 2. 패치 및 업데이트 안전성 (데이터 스키마 마이그레이션 레지스트리)
-- 3. 실시간 라이브 이벤트 지원 (XP/드랍률 멀티플라이어, 기간제 이벤트 가드)
-- 4. 서비스 정기 점검 모드 (점검 상태 로그인 제어)

local LiveOpsManager = {}

--========================================
-- 1. 디버깅 및 실시간 로그 설정
--========================================
local LOG_LEVELS = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

local CURRENT_LOG_LEVEL = LOG_LEVELS.INFO -- 상용 서버 런타임에는 WARN/ERROR 위주로 설정 가능

-- 특정 시스템별 디버그 필터링 활성화 여부
local ENABLED_LOG_SCOPES = {
	["SaveService"] = true,
	["Inventory"] = true,
	["Combat"] = false,
	["LiveEvents"] = true,
}

-- Scoped Logger 함수
function LiveOpsManager.Log(scope: string, levelName: string, message: string, ...: any)
	local level = LOG_LEVELS[levelName:upper()] or LOG_LEVELS.INFO
	if level < CURRENT_LOG_LEVEL then return end
	
	-- 스코프별 필터링
	if levelName:upper() == "DEBUG" and not ENABLED_LOG_SCOPES[scope] then
		return
	end
	
	local formatted = string.format("[%s][%s] %s", scope, levelName:upper(), string.format(message, ...))
	
	if levelName:upper() == "ERROR" then
		error(formatted, 2)
	elseif levelName:upper() == "WARN" then
		warn(formatted)
	else
		print(formatted)
	end
end

--========================================
-- 2. 스키마 마이그레이션 (데이터 보존 안전성 보장)
--========================================
local Migrations = {
	-- 스키마 버전을 1에서 2로 업그레이드할 때 실행되는 마이그레이션 함수
	[2] = function(oldState)
		-- 예: 구버전 세이브에는 없던 신규 재화 골드(gold) 필드 자동 추가
		if oldState.resources and not oldState.resources.gold then
			oldState.resources.gold = 100 -- 신규 패치 웰컴 보너스 골드 지급
			LiveOpsManager.Log("Migration", "INFO", "Migrated player state to v2: Added welcome gold.")
		end
		return oldState
	end,
	
	-- 스키마 버전을 2에서 3으로 업그레이드할 때 실행되는 마이그레이션 함수
	[3] = function(oldState)
		-- 예: 길들여진 팰들의 기본 스탯 밸런스 패치 자동 이식
		if oldState.palbox then
			for _, pal in pairs(oldState.palbox) do
				if pal.stats and not pal.stats.san then
					pal.stats.san = 100 -- 신규 정신력 스탯 필드 추가
				end
			end
			LiveOpsManager.Log("Migration", "INFO", "Migrated player state to v3: Added sanity (san) stat to palbox.")
		end
		return oldState
	end,
}

-- 데이터 세이브 시 자동 호출되어 하위 버전 유저 정보를 최신 버전으로 순차 이식
function LiveOpsManager.MigrateState(playerState: any, targetVersion: number): any
	local currentVersion = playerState.version or 1
	if currentVersion >= targetVersion then
		return playerState
	end
	
	LiveOpsManager.Log("Migration", "WARN", "Player state is v%d, migrating to v%d...", currentVersion, targetVersion)
	
	-- 마이그레이션 단계별 순차 처리 (v1 -> v2 -> v3)
	for version = currentVersion + 1, targetVersion do
		local migrationFn = Migrations[version]
		if migrationFn then
			local success, result = pcall(migrationFn, playerState)
			if success then
				playerState = result
				playerState.version = version
			else
				LiveOpsManager.Log("Migration", "ERROR", "Failed at v%d migration step: %s", version, tostring(result))
			end
		end
	end
	
	return playerState
end

--========================================
-- 3. 실시간 라이브 이벤트 설정 (XP/드롭률 배율)
--========================================
local ActiveEvents = {
	["DoubleXP"] = {
		enabled = true,
		multiplier = 2.0,
		startTime = 1715234400, -- (예시) 이벤트 개시 타임스탬프
		endTime = 1715839200,   -- (예시) 이벤트 마감 타임스탬프
	},
	["ChuseokHarvestBonus"] = {
		enabled = false,
		multiplier = 1.5,
		startTime = 0,
		endTime = 0,
	}
}

-- 특정 라이브 이벤트 작동 및 멀티플라이어 반환 함수
function LiveOpsManager.GetEventMultiplier(eventName: string): number
	local event = ActiveEvents[eventName]
	if not event or not event.enabled then
		return 1.0
	end
	
	local now = os.time()
	-- 시간 기반 유효성 가드 (테스트 시 startTime = 0 으로 무조건 검증 가능)
	if event.startTime > 0 and (now < event.startTime or now > event.endTime) then
		return 1.0
	end
	
	return event.multiplier
end

--========================================
-- 4. 서비스 유지보수 (점검) 모드 설정
--========================================
local MAINTENANCE_MODE = false -- 점검 시 true로 켜서 일반 로그인 제한
local ALLOWED_ADMINS = {
	[123456] = true, -- 점검 중에도 진입 가능한 개발자/어드민 UserId 등록
}

function LiveOpsManager.CheckLoginAllowed(userId: number): (boolean, string?)
	if not MAINTENANCE_MODE then
		return true
	end
	
	if ALLOWED_ADMINS[userId] then
		return true, "Admin Override Allowed"
	end
	
	return false, "현재 긴급 서버 점검이 진행 중입니다. 점검 완료 후 다시 접속해 주시기 바랍니다!"
end

return LiveOpsManager
