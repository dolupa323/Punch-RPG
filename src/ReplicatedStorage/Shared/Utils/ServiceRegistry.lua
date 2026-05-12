-- ServiceRegistry.lua
-- 현업 레벨 범용 RPG 템플릿용 중앙 서비스 레지스트리 (Service Registry)
-- 모듈 간 직접 수입(require)으로 인한 순환 참조(Circular Dependency) 및 
-- 강결합(Tightly-Coupling) 문제를 완전 해소하고, 조건부 로딩 시 존재하지 않는 
-- 서비스에 대한 안전한 조회 가드를 보장합니다.

local ServiceRegistry = {}
local services = {}

-- 1. 서비스 등록 (Register)
-- @param name: 등록할 서비스 고유 키값 (예: "InventoryService", "PalboxService")
-- @param service: 실제 서비스 객체 (테이블)
function ServiceRegistry.Register(name: string, service: any)
	assert(typeof(name) == "string", "[ServiceRegistry] Name must be a string")
	assert(service ~= nil, "[ServiceRegistry] Service cannot be nil")
	
	if services[name] then
		warn(string.format("[ServiceRegistry] Overwriting existing registered service: %s", name))
	end
	
	services[name] = service
	-- print(string.format("[ServiceRegistry] Service '%s' successfully registered.", name))
end

-- 2. 서비스 단일 조회 (Get)
-- @param name: 조회할 서비스 고유 키값
-- @return: 등록된 서비스 객체 (없을 경우 nil 반환하여 호출 측에서 우회 처리 유도)
function ServiceRegistry.Get(name: string): any?
	assert(typeof(name) == "string", "[ServiceRegistry] Name must be a string")
	return services[name]
end

-- 3. 안전한 메서드 격발 실행 (SafeInvoke)
-- 서비스 존재 유무를 먼저 검증하고 메서드를 호출하여 크래시를 사전 방어합니다.
-- @param name: 호출할 서비스 고유 키값
-- @param methodName: 실행할 메서드 이름 (문자열)
-- @param ...: 메서드로 전달할 가변 인자 목록
-- @return success, ...: 함수 실행 성공 여부 및 결과 리턴
function ServiceRegistry.SafeInvoke(name: string, methodName: string, ...: any): (boolean, ...any)
	local service = services[name]
	if not service then
		-- 서비스가 로드되지 않은 상태라면 에러 없이 경고 처리 후 silent 리턴
		return false, "[ServiceRegistry] Service not loaded: " .. name
	end
	
	local method = service[methodName]
	if not method then
		return false, string.format("[ServiceRegistry] Method '%s' not found on service '%s'", methodName, name)
	end
	
	local results = { pcall(method, service, ...) }
	local ok = results[1]
	if not ok then
		warn(string.format("[ServiceRegistry] Error executing %s:%s - %s", name, methodName, tostring(results[2])))
		return false, results[2]
	end
	
	return true, unpack(results, 2)
end

-- 4. 등록된 모든 서비스 목록 조회 (디버깅용)
function ServiceRegistry.GetAllRegistered(): { [string]: any }
	local copy = {}
	for k, v in pairs(services) do
		copy[k] = v
	end
	return copy
end

return ServiceRegistry
