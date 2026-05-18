-- TimeController.lua
-- 클라이언트 시간 컨트롤러
-- 서버 Time 이벤트 수신 및 로컬 상태 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local NetClient = require(script.Parent.Parent.NetClient)

local TimeController = {}

--========================================
-- Private State
--========================================
local initialized = false
local renderConn = nil
local lastSyncClientClock = 0
local lastSyncDayTime = 0
local hasSync = false

-- 로컬 시간 캐시
local timeCache = {
	dayTime = 0,
	phase = "DAY",
	serverTime = 0,
}

--========================================
-- Internal Helpers
--========================================

local function getDayLength(): number
	return math.max(1, Balance.DAY_LENGTH or 2400)
end

local function getDayDuration(): number
	return math.clamp(Balance.DAY_DURATION or 1800, 0, getDayLength())
end

local function phaseFromDayTime(dayTime: number): string
	if dayTime < getDayDuration() then
		return "DAY"
	end
	return "NIGHT"
end

local function applyLighting(dayTime: number)
	-- [제거] 게임 내 해가 움직이지 않도록 실시간 로컬 라이팅 조작 비활성화
end

--========================================
-- Public API: Cache Access
--========================================

function TimeController.getTimeCache()
	return timeCache
end

function TimeController.getPhase(): string
	return timeCache.phase
end

function TimeController.getDayTime(): number
	return timeCache.dayTime
end

--========================================
-- Event Handlers
--========================================

local function onPhaseChanged(data)
	if not data then return end
	
	timeCache.phase = data.phase or timeCache.phase
	timeCache.dayTime = data.dayTime or timeCache.dayTime
	timeCache.serverTime = data.serverTime or timeCache.serverTime

	if data.dayTime ~= nil then
		lastSyncDayTime = data.dayTime
		lastSyncClientClock = os.clock()
		hasSync = true
		applyLighting(lastSyncDayTime)
	end
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[TimeController] Phase changed: %s at dayTime=%.1f", timeCache.phase, timeCache.dayTime))
end

local function onSyncChanged(data)
	if not data then return end
	
	timeCache.dayTime = data.dayTime or timeCache.dayTime
	timeCache.phase = data.phase or timeCache.phase
	timeCache.serverTime = data.serverTime or timeCache.serverTime

	if data.dayTime ~= nil then
		lastSyncDayTime = data.dayTime
		lastSyncClientClock = os.clock()
		hasSync = true
		applyLighting(lastSyncDayTime)
	end
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[TimeController] Sync: dayTime=%.1f, phase=%s", timeCache.dayTime, timeCache.phase))
end

local function requestInitialSync()
	for _ = 1, 5 do
		local ok, data = NetClient.Request("Time.Sync.Request", {})
		if ok and type(data) == "table" then
			onSyncChanged(data)
			return true
		end
		task.wait(0.5)
	end

	warn("[TimeController] Initial time sync failed")
	return false
end

--========================================
-- Initialization
--========================================

function TimeController.Init()
	if initialized then
		warn("[TimeController] Already initialized")
		return
	end
	
	-- 라이팅 시각을 오후 2시(14:00) 대낮으로 단 1번 영구 고정
	Lighting.ClockTime = 14
	
	-- 이벤트 리스너 등록
	NetClient.On("Time.Phase.Changed", onPhaseChanged)
	NetClient.On("Time.Sync.Changed", onSyncChanged)

	-- 첫 진입 시 서버 시간 동기화
	task.spawn(requestInitialSync)

	-- 서버 시각 상태 갱신만 하고, Lighting.ClockTime 조작 루프는 생략
	renderConn = RunService.RenderStepped:Connect(function()
		if not hasSync then
			return
		end

		local dayLength = getDayLength()
		local elapsed = os.clock() - lastSyncClientClock
		local predictedDayTime = (lastSyncDayTime + elapsed) % dayLength
		timeCache.dayTime = predictedDayTime
		timeCache.phase = phaseFromDayTime(predictedDayTime)
	end)
	
	initialized = true
	print("[TimeController] Initialized - Sun fixed at 14:00 (No day/night rotation)")
end

return TimeController
