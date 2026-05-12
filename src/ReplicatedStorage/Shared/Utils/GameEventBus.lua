-- GameEventBus.lua
-- 범용 RPG 템플릿용 비결합 글로벌 이벤트 버스 (Decoupled Global Event Bus)
-- 서로 직접적인 require를 거치지 않고 이벤트를 수신/발행할 수 있도록 중계합니다.

local GameEventBus = {}
local listeners = {} -- eventName -> table of callback functions

-- 이벤트 리스너 구독 (On)
-- @param eventName: 이벤트 이름 (예: "ItemAdded", "EnemyKilled", "CraftCompleted")
-- @param callback: 이벤트 발생 시 실행할 콜백 함수
-- @return unsubscribe: 구독 해제용 무명 함수
function GameEventBus.On(eventName: string, callback: (...any) -> ())
	assert(typeof(eventName) == "string", "[GameEventBus] EventName must be a string")
	assert(typeof(callback) == "function", "[GameEventBus] Callback must be a function")

	if not listeners[eventName] then
		listeners[eventName] = {}
	end
	
	table.insert(listeners[eventName], callback)
	
	-- 구독 취소 함수를 클로저로 리턴
	return function()
		local eventList = listeners[eventName]
		if eventList then
			local idx = table.find(eventList, callback)
			if idx then
				table.remove(eventList, idx)
			end
		end
	end
end

-- 이벤트 발행 (Fire)
-- @param eventName: 발행할 이벤트 이름
-- @param ...: 콜백 함수로 전달할 가변 인자 목록
function GameEventBus.Fire(eventName: string, ...: any)
	assert(typeof(eventName) == "string", "[GameEventBus] EventName must be a string")
	
	local eventList = listeners[eventName]
	if not eventList then return end
	
	-- task.spawn을 사용해 비동기식으로 각 리스너 호출함으로써,
	-- 한 리스너의 오류가 이벤트 발행원이나 다른 리스너 스레드에 전파되는 것을 차단합니다.
	for _, callback in ipairs(eventList) do
		task.spawn(callback, ...)
	end
end

-- 모든 리스너 일괄 청소 (디버깅용)
function GameEventBus.ClearAll()
	listeners = {}
end

return GameEventBus
