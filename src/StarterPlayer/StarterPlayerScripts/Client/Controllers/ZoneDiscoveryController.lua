-- ZoneDiscoveryController.lua
-- 클라이언트용 지역 발견 안내 UI 시스템 (실시간 디버그 모드 탑재)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnConfig = require(Shared.Config.SpawnConfig)

local ZoneDiscoveryController = {}

local initialized = false
local player = Players.LocalPlayer
local currentZoneName = nil
local zonePollAccumulator = 0
local ZONE_POLL_INTERVAL = 0.5 -- 감도 향상: 0.5초마다 체크

-- 디버그 모드 비활성화 (실운영 최적화)
local DEBUG_MODE = false
local debugLabel = nil

-- GUI References
local screenGui = nil
local container = nil
local mainLabel = nil
local subLabel = nil
local decoLineLeft = nil
local decoLineRight = nil

-- Animation Settings
local FADE_IN_TIME = 1.0
local HOLD_TIME = 2.5
local FADE_OUT_TIME = 1.2

---------------------------------------------------------
-- 1. UI 레이아웃 동적 빌드 (프로그래머틱 UI)
---------------------------------------------------------
local function setupUI()
	local success, err = pcall(function()
		local playerGui = player:WaitForChild("PlayerGui", 10)
		if not playerGui then
			warn("[ZoneDiscovery] Failed to find PlayerGui")
			return
		end
		
		-- 구 Gui 정리 Failsafe
		local old = playerGui:FindFirstChild("ZoneDiscoveryGui")
		if old then old:Destroy() end
		
		-- 1. 메인 ScreenGui
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "ZoneDiscoveryGui"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 999 -- 최상단 렌더링 보장
		screenGui.Parent = playerGui
		
		-- 2. 메인 컨테이너 프레임
		container = Instance.new("Frame")
		container.Name = "Container"
		container.Size = UDim2.new(0.6, 0, 0.2, 0)
		container.Position = UDim2.new(0.5, 0, 0.28, 0)
		container.AnchorPoint = Vector2.new(0.5, 0.5)
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.Visible = false
		container.Parent = screenGui
		
		-- UI 리스트 레이아웃
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = container
		
		-- 3. 메인 지명 텍스트
		mainLabel = Instance.new("TextLabel")
		mainLabel.Name = "MainTitle"
		mainLabel.Size = UDim2.new(1, 0, 0.4, 0)
		mainLabel.BackgroundTransparency = 1
		mainLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		mainLabel.TextSize = 48
		mainLabel.Font = Enum.Font.Garamond
		mainLabel.RichText = true
		mainLabel.Text = ""
		mainLabel.TextTransparency = 1
		mainLabel.LayoutOrder = 1
		mainLabel.Parent = container
		
		local mainStroke = Instance.new("UIStroke")
		mainStroke.Color = Color3.fromRGB(0, 0, 0)
		mainStroke.Thickness = 2
		mainStroke.Transparency = 1
		mainStroke.Parent = mainLabel
		
		-- 4. 중앙 장식선 바
		local lineContainer = Instance.new("Frame")
		lineContainer.Name = "LineBar"
		lineContainer.Size = UDim2.new(0.8, 0, 0, 2)
		lineContainer.BackgroundTransparency = 1
		lineContainer.LayoutOrder = 2
		lineContainer.Parent = container
		
		decoLineLeft = Instance.new("Frame")
		decoLineLeft.Name = "LineL"
		decoLineLeft.Size = UDim2.new(0, 0, 1, 0)
		decoLineLeft.Position = UDim2.new(0.5, 0, 0.5, 0)
		decoLineLeft.AnchorPoint = Vector2.new(1, 0.5)
		decoLineLeft.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		decoLineLeft.BackgroundTransparency = 1
		decoLineLeft.BorderSizePixel = 0
		decoLineLeft.Parent = lineContainer
		
		decoLineRight = Instance.new("Frame")
		decoLineRight.Name = "LineR"
		decoLineRight.Size = UDim2.new(0, 0, 1, 0)
		decoLineRight.Position = UDim2.new(0.5, 0, 0.5, 0)
		decoLineRight.AnchorPoint = Vector2.new(0, 0.5)
		decoLineRight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		decoLineRight.BackgroundTransparency = 1
		decoLineRight.BorderSizePixel = 0
		decoLineRight.Parent = lineContainer
		
		local gradL = Instance.new("UIGradient")
		gradL.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		gradL.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0)
		})
		gradL.Parent = decoLineLeft

		local gradR = Instance.new("UIGradient")
		gradR.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		gradR.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1)
		})
		gradR.Parent = decoLineRight
		
		-- 5. 서브 지명 한문/영문 텍스트
		subLabel = Instance.new("TextLabel")
		subLabel.Name = "SubTitle"
		subLabel.Size = UDim2.new(1, 0, 0.3, 0)
		subLabel.BackgroundTransparency = 1
		subLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
		subLabel.TextSize = 24
		subLabel.Font = Enum.Font.Garamond
		subLabel.Text = ""
		subLabel.TextTransparency = 1
		subLabel.LayoutOrder = 3
		subLabel.Parent = container
		
		local subStroke = Instance.new("UIStroke")
		subStroke.Color = Color3.fromRGB(0, 0, 0)
		subStroke.Thickness = 1.5
		subStroke.Transparency = 1
		subStroke.Parent = subLabel
		
		-- [디버그 전용] 최상단 실시간 정보창 생성
		if DEBUG_MODE then
			debugLabel = Instance.new("TextLabel")
			debugLabel.Name = "DebugHUD"
			debugLabel.Size = UDim2.new(0, 350, 0, 60)
			debugLabel.Position = UDim2.new(0, 20, 0, 20)
			debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			debugLabel.BackgroundTransparency = 0.5
			debugLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			debugLabel.TextSize = 16
			debugLabel.Font = Enum.Font.Code
			debugLabel.TextAlignmentX = Enum.TextAlignment.Left
			debugLabel.Text = "Initializing HUD..."
			debugLabel.Parent = screenGui
			
			local debugPadding = Instance.new("UIPadding")
			debugPadding.PaddingLeft = UDim.new(0, 10)
			debugPadding.Parent = debugLabel
		end
		
		print("[ZoneDiscovery] UI successfully built programmatically.")
	end)
	
	if not success then
		warn("[ZoneDiscovery] Setup UI crash: " .. tostring(err))
	end
end

---------------------------------------------------------
-- 2. 영화적 연출 애니메이션 실행
---------------------------------------------------------
local activeTweenSet = {}

local function cancelActiveTweens()
	for _, t in ipairs(activeTweenSet) do
		if t then t:Cancel() end
	end
	table.clear(activeTweenSet)
end

local function playDiscoveryEffect(displayName: string, subName: string)
	if not container then 
		warn("[ZoneDiscovery] Container UI is missing during play!")
		return 
	end
	cancelActiveTweens()
	
	mainLabel.Text = displayName
	subLabel.Text = subName or ""
	
	local startPos = UDim2.new(0.5, 0, 0.30, 0)
	local targetPos = UDim2.new(0.5, 0, 0.27, 0)
	
	container.Position = startPos
	mainLabel.TextTransparency = 1
	mainLabel:FindFirstChildOfClass("UIStroke").Transparency = 1
	subLabel.TextTransparency = 1
	subLabel:FindFirstChildOfClass("UIStroke").Transparency = 1
	
	decoLineLeft.Size = UDim2.new(0, 0, 1, 0)
	decoLineLeft.BackgroundTransparency = 1
	decoLineRight.Size = UDim2.new(0, 0, 1, 0)
	decoLineRight.BackgroundTransparency = 1
	
	container.Visible = true
	
	local infoIn = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	
	local tPosition = TweenService:Create(container, infoIn, { Position = targetPos })
	local tMainText = TweenService:Create(mainLabel, infoIn, { TextTransparency = 0 })
	local tMainStroke = TweenService:Create(mainLabel:FindFirstChildOfClass("UIStroke"), infoIn, { Transparency = 0.3 })
	local tSubText = TweenService:Create(subLabel, infoIn, { TextTransparency = 0.15 })
	local tSubStroke = TweenService:Create(subLabel:FindFirstChildOfClass("UIStroke"), infoIn, { Transparency = 0.4 })
	local tLineL = TweenService:Create(decoLineLeft, infoIn, { Size = UDim2.new(0.4, 0, 1, 0), BackgroundTransparency = 0.3 })
	local tLineR = TweenService:Create(decoLineRight, infoIn, { Size = UDim2.new(0.4, 0, 1, 0), BackgroundTransparency = 0.3 })
	
	table.insert(activeTweenSet, tPosition)
	table.insert(activeTweenSet, tMainText)
	table.insert(activeTweenSet, tMainStroke)
	table.insert(activeTweenSet, tSubText)
	table.insert(activeTweenSet, tSubStroke)
	table.insert(activeTweenSet, tLineL)
	table.insert(activeTweenSet, tLineR)
	
	for _, t in ipairs(activeTweenSet) do t:Play() end
	
	task.delay(FADE_IN_TIME + HOLD_TIME, function()
		if not container or not container.Visible then return end
		
		local infoOut = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		
		local tOutMain = TweenService:Create(mainLabel, infoOut, { TextTransparency = 1 })
		local tOutMainStr = TweenService:Create(mainLabel:FindFirstChildOfClass("UIStroke"), infoOut, { Transparency = 1 })
		local tOutSub = TweenService:Create(subLabel, infoOut, { TextTransparency = 1 })
		local tOutSubStr = TweenService:Create(subLabel:FindFirstChildOfClass("UIStroke"), infoOut, { Transparency = 1 })
		local tOutLineL = TweenService:Create(decoLineLeft, infoOut, { BackgroundTransparency = 1 })
		local tOutLineR = TweenService:Create(decoLineRight, infoOut, { BackgroundTransparency = 1 })
		
		tOutMain:Play()
		tOutMainStr:Play()
		tOutSub:Play()
		tOutSubStr:Play()
		tOutLineL:Play()
		tOutLineR:Play()
		
		tOutMain.Completed:Wait()
		
		if mainLabel.TextTransparency >= 0.95 then
			container.Visible = false
		end
	end)
end

---------------------------------------------------------
-- 3. 지역 실시간 감시 함수
---------------------------------------------------------
local function refreshCurrentZone()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local pos = hrp.Position
	local zoneName = SpawnConfig.GetZoneAtPosition(pos)
	
	-- [디버그 HUD 갱신] 실시간 정보 표기
	if DEBUG_MODE and debugLabel then
		debugLabel.Text = string.format(
			"POS: X=%d, Z=%d\nACTIVE ZONE: %s",
			math.floor(pos.X),
			math.floor(pos.Z),
			zoneName or "NONE (Out of Zone)"
		)
	end
	
	-- 구역 변경 감지
	if zoneName ~= currentZoneName then
		currentZoneName = zoneName
		
		if zoneName then
			local info = SpawnConfig.GetZoneInfo(zoneName)
			-- 래거시(이전 프로젝트) 구역은 화면에 UI 팝업이 뜨지 않도록 원천 배제 처리
			if info and info.displayName and not info.isLegacy then
				print(string.format("[ZoneDiscovery] Welcome to %s (%s)", info.displayName, zoneName))
				playDiscoveryEffect(info.displayName, info.subName)
			end
		end
	end
end

---------------------------------------------------------
-- 4. 라이프사이클 초기화
---------------------------------------------------------
function ZoneDiscoveryController.Init()
	if initialized then return end
	initialized = true
	
	print("[ZoneDiscoveryController] Init started...")
	
	-- UI 구성
	setupUI()
	
	-- 캐릭터 리스폰 핸들러
	player.CharacterAdded:Connect(function()
		currentZoneName = nil
		task.wait(1.0)
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui and not playerGui:FindFirstChild("ZoneDiscoveryGui") then
			setupUI()
		end
		refreshCurrentZone()
	end)
	
	-- 하트비트 루프 연동
	RunService.Heartbeat:Connect(function(dt)
		zonePollAccumulator = zonePollAccumulator + dt
		if zonePollAccumulator < ZONE_POLL_INTERVAL then return end
		zonePollAccumulator = 0
		refreshCurrentZone()
	end)
	
	-- 첫 접속 지연 가동
	task.defer(function()
		task.wait(2.0)
		refreshCurrentZone()
	end)
	
	print("🚀 [ZoneDiscoveryController] Successfully initialized and polling!")
end

return ZoneDiscoveryController
