-- WindowManager.lua
-- UI 창들의 가시성(Visibility) 및 배타적 활성화 제어 (Phase 11)
-- UIManager의 'God Object' 방지를 위한 창 상태 관리 모듈

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local WindowManager = {}

local activeWindows = {} -- [winId] = boolean
local windowConfigs = {} -- [winId] = { open = fn, close = fn, frame = GuiObject? }
local activeTweens = {} -- [GuiObject] = Tween (충돌 방지)
local updateCallback = nil -- HUD 가시성 및 입력 모드 동기화용 콜백
local dimBackground = nil -- 바깥 영역 클릭 시 닫기용 배경

-- 오픈 애니메이션 상수
local OPEN_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DIM_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- 바깥 영역 클릭 시 닫기용 배경 등록
function WindowManager.setDimBackground(gui: GuiObject)
	dimBackground = gui
	dimBackground.Visible = false
	-- 버튼 기능 제거 (UserInputService에서 통합 처리)
end

--========================================
-- Click-Outside Detection
--========================================
UserInputService.InputBegan:Connect(function(input, processed)
	-- UI 요소(버튼 등)를 클릭한 경우 무시
	if processed then return end
	
	-- 마우스 왼쪽 클릭이나 터치인 경우만 처리
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- 열려있는 창이 있을 때만 닫기 수행
		if WindowManager.isAnyOpen() then
			local pos = input.Position
			local clickedInside = false
			
			-- 현재 열려있는 창들의 영역 내부를 클릭했는지 확인
			for id, isOpen in pairs(activeWindows) do
				if isOpen then
					local config = windowConfigs[id]
					local frame = config.frame
					if frame then
						local ap = frame.AbsolutePosition
						local as = frame.AbsoluteSize
						if pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y then
							clickedInside = true
							break
						end
					end
				end
			end

			-- 모바일의 경우 가상 조이스틱 영역(좌측 하단) 터치 시 창이 닫히는 현상 방지
			local isJoystickArea = false
			if input.UserInputType == Enum.UserInputType.Touch then
				local vpSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 1000)
				-- 화면 좌측 40%, 하단 50%를 조이스틱 영역으로 간주
				if pos.X < vpSize.X * 0.4 and pos.Y > vpSize.Y * 0.5 then
					isJoystickArea = true
				end
			end
			
			if not clickedInside and not isJoystickArea then
				WindowManager.closeAll()
			end
		end
	end
end)

local function updateDimBackground()
	if not dimBackground then return end
	
	local hasFullWindow = false
	local hasRadial = false
	
	for id, isOpen in pairs(activeWindows) do
		if isOpen then
			if id:find("_RADIAL") or id == "HARVEST" then
				hasRadial = true
			else
				hasFullWindow = true
			end
		end
	end
	
	if hasFullWindow then
		-- 일반 창(인벤토리 등): 적절한 감쇠
		dimBackground.Visible = true
		TweenService:Create(dimBackground, DIM_TWEEN_INFO, { BackgroundTransparency = 0.6 }):Play()
	elseif hasRadial then
		-- 상호작용 메뉴: 아주 옅은 감쇠 (클릭 영역 구분용)
		dimBackground.Visible = true
		TweenService:Create(dimBackground, DIM_TWEEN_INFO, { BackgroundTransparency = 0.85 }):Play()
	else
		-- 모두 닫힘
		local tween = TweenService:Create(dimBackground, DIM_TWEEN_INFO, { BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			if not WindowManager.isAnyOpen() then
				dimBackground.Visible = false
			end
		end)
		tween:Play()
	end
end

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
	local scale = frame:FindFirstChild("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	return scale
end

--- 오픈 애니메이션 재생 (UIScale + 투명도)
local function playOpenAnimation(frame: GuiObject?)
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
		tween = TweenService:Create(uiScale, OPEN_TWEEN_INFO, { Scale = 1 })
		TweenService:Create(frame, OPEN_TWEEN_INFO, { GroupTransparency = 0 }):Play()
	else
		tween = TweenService:Create(uiScale, OPEN_TWEEN_INFO, { Scale = 1 })
	end
	
	activeTweens[frame] = tween
	tween.Completed:Once(function() activeTweens[frame] = nil end)
	tween:Play()
end

--- 닫기 애니메이션 재생
local function playCloseAnimation(frame: GuiObject?, callback: (() -> ())?)
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
	updateDimBackground()
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
	updateDimBackground()
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
	updateDimBackground()
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

--- 전체 화면 창(인벤토리 등)이 열려있는지 확인 (HUD 숨김 여부 결정용)
function WindowManager.hasFullWindowOpen(): boolean
	for id, isOpen in pairs(activeWindows) do
		if isOpen then
			-- 방사형 UI가 아닌 일반 창이 하나라도 열려있으면 true
			if not (id:find("_RADIAL") or id == "HARVEST") then
				return true
			end
		end
	end
	return false
end

return WindowManager
