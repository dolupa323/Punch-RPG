-- WindowManager.lua
-- UI 창들의 가시성(Visibility) 및 배타적 활성화 제어 (Phase 11)
-- UIManager의 'God Object' 방지를 위한 창 상태 관리 모듈

local TweenService = game:GetService("TweenService")

local WindowManager = {}

local activeWindows = {} -- [winId] = boolean
local windowConfigs = {} -- [winId] = { open = fn, close = fn, frame = GuiObject? }
local activeTweens = {} -- [GuiObject] = Tween (충돌 방지)
local updateCallback = nil -- HUD 가시성 및 입력 모드 동기화용 콜백

-- 오픈 애니메이션 상수
local OPEN_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--- 창 등록
function WindowManager.register(winId: string, openFn: () -> (), closeFn: () -> ())
	windowConfigs[winId] = {
		open = openFn,
		close = closeFn,
		frame = nil, -- registerFrame으로 별도 등록
	}
	activeWindows[winId] = false
end

--- 애니메이션 대상 프레임 등록 (메인 패널 프레임)
function WindowManager.registerFrame(winId: string, frame: GuiObject)
	if windowConfigs[winId] then
		windowConfigs[winId].frame = frame
	end
end

--- UIScale 인스턴스 가져오기 (없으면 생성)
local function getUIScale(frame: GuiObject): UIScale
	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "_AnimScale"
		uiScale.Scale = 1
		uiScale.Parent = frame
	end
	return uiScale
end

--- 오픈 애니메이션 재생 (UIScale + 투명도)
local function playOpenAnimation(frame: GuiObject)
	if not frame then return end
	-- 기존 트윈 취소
	if activeTweens[frame] then
		activeTweens[frame]:Cancel()
		activeTweens[frame] = nil
	end
	local uiScale = getUIScale(frame)
	uiScale.Scale = 0.85
	local tween
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 0.6
		local tweenScale = TweenService:Create(uiScale, OPEN_TWEEN_INFO, { Scale = 1 })
		TweenService:Create(frame, OPEN_TWEEN_INFO, { GroupTransparency = 0 }):Play()
		tween = tweenScale
	else
		tween = TweenService:Create(uiScale, OPEN_TWEEN_INFO, { Scale = 1 })
	end
	activeTweens[frame] = tween
	tween.Completed:Once(function() activeTweens[frame] = nil end)
	tween:Play()
end

--- 닫기 애니메이션 재생
local function playCloseAnimation(frame: GuiObject, callback: (() -> ())?)
	if not frame then
		if callback then callback() end
		return
	end
	-- 기존 트윈 취소
	if activeTweens[frame] then
		activeTweens[frame]:Cancel()
		activeTweens[frame] = nil
	end
	local uiScale = getUIScale(frame)
	local props = { Scale = 0.9 }
	if frame:IsA("CanvasGroup") then
		TweenService:Create(frame, CLOSE_TWEEN_INFO, { GroupTransparency = 0.5 }):Play()
	end
	local tween = TweenService:Create(uiScale, CLOSE_TWEEN_INFO, props)
	activeTweens[frame] = tween
	tween.Completed:Once(function()
		activeTweens[frame] = nil
		uiScale.Scale = 1
		if frame:IsA("CanvasGroup") then
			frame.GroupTransparency = 0
		end
		if callback then callback() end
	end)
	tween:Play()
end

--- 특정 창 제외 모두 닫기
function WindowManager.closeOthers(exceptId: string?)
	local closedAny = false
	for id, config in pairs(windowConfigs) do
		if id ~= exceptId and activeWindows[id] then
			activeWindows[id] = false
			-- 진행 중인 트윈 취소 + UIScale 복원
			local frame = config.frame
			if frame then
				if activeTweens[frame] then
					activeTweens[frame]:Cancel()
					activeTweens[frame] = nil
				end
				local uiScale = frame:FindFirstChildOfClass("UIScale")
				if uiScale then uiScale.Scale = 1 end
				if frame:IsA("CanvasGroup") then
					frame.GroupTransparency = 0
				end
			end
			config.close()
			closedAny = true
		end
	end
	
	if closedAny and updateCallback then
		updateCallback()
	end
end

--- 모든 창 닫기
function WindowManager.closeAll()
	WindowManager.closeOthers(nil)
end

--- 창 열기
function WindowManager.open(winId: string, ...)
	local config = windowConfigs[winId]
	if not config then return end
	
	if activeWindows[winId] then return end
	
	WindowManager.closeOthers(winId)
	activeWindows[winId] = true
	config.open(...)
	
	-- ★ 오픈 애니메이션
	playOpenAnimation(config.frame)
	
	if updateCallback then updateCallback() end
end

--- 창 닫기
function WindowManager.close(winId: string)
	local config = windowConfigs[winId]
	if not config or not activeWindows[winId] then return end
	
	activeWindows[winId] = false
	
	if config.frame then
		-- 닫기 애니메이션 후 실제 닫기
		playCloseAnimation(config.frame, function()
			config.close()
		end)
	else
		config.close()
	end
	
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
