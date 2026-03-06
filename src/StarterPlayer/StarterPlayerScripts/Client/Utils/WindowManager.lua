-- WindowManager.lua
-- UI 창들의 가시성(Visibility) 및 배타적 활성화 제어 (Phase 11)
-- UIManager의 'God Object' 방지를 위한 창 상태 관리 모듈

local WindowManager = {}

local activeWindows = {} -- [winId] = boolean
local windowConfigs = {} -- [winId] = { open = fn, close = fn }
local updateCallback = nil -- HUD 가시성 및 입력 모드 동기화용 콜백

--- 창 등록
function WindowManager.register(winId: string, openFn: () -> (), closeFn: () -> ())
	windowConfigs[winId] = {
		open = openFn,
		close = closeFn
	}
	activeWindows[winId] = false
end

--- 특정 창 제외 모두 닫기
function WindowManager.closeOthers(exceptId: string?)
	for id, config in pairs(windowConfigs) do
		if id ~= exceptId and activeWindows[id] then
			activeWindows[id] = false
			config.close()
		end
	end
end

--- 창 열기
function WindowManager.open(winId: string, ...)
	local config = windowConfigs[winId]
	if not config then return end
	
	if activeWindows[winId] then return end
	
	WindowManager.closeOthers(winId)
	activeWindows[winId] = true
	config.open(...)
	
	if updateCallback then updateCallback() end
end

--- 창 닫기
function WindowManager.close(winId: string)
	local config = windowConfigs[winId]
	if not config or not activeWindows[winId] then return end
	
	activeWindows[winId] = false
	config.close()
	
	if updateCallback then updateCallback() end
end

--- 창 토글
function WindowManager.toggle(winId: string, ...)
	if activeWindows[winId] then
		WindowManager.close(winId)
	else
		WindowManager.open(winId, ...)
	end
end

--- 열린 창이 하나라도 있는지 확인
function WindowManager.isAnyOpen(): boolean
	for _, isOpen in pairs(activeWindows) do
		if isOpen then return true end
	end
	return false
end

--- 특정 창이 열려있는지 확인
function WindowManager.isOpen(winId: string): boolean
	return activeWindows[winId] or false
end

--- 상태 변경 시 호출될 콜백 설정
function WindowManager.onUpdate(cb: () -> ())
	updateCallback = cb
end

return WindowManager
