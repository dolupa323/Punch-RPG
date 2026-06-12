-- LoadingScreen.client.lua
-- 로딩 스크린 및 메인 타이틀 스크린 구현

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

-- 로블록스 기본 로딩 스크린 비활성화
ReplicatedFirst:RemoveDefaultLoadingScreen()

local LOGO_ASSET_ID = "rbxassetid://124140361686945"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 30)

--=========================================
-- UI 생성 헬퍼 함수
--=========================================
local function create(className, properties)
	local inst = Instance.new(className)
	for k, v in pairs(properties) do
		inst[k] = v
	end
	return inst
end

--=========================================
-- ScreenGui 초기화
--=========================================
local screenGui = create("ScreenGui", {
	Name = "CustomLoadingTitle",
	Parent = playerGui,
	IgnoreGuiInset = true,
	DisplayOrder = 9999, -- 가장 위에 렌더링
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling
})

-- loadingFrame 및 기존 로딩 UI 제거 (titleFrame으로 통합)

--=========================================
-- 2. 타이틀 스크린 메인 메뉴 (Title Frame)
--=========================================
local titleFrame = create("Frame", {
	Name = "TitleFrame",
	Parent = screenGui,
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 1,
	Visible = true
})

-- 타이틀 배경 오버레이 (불투명 — 게임 환경만 표시)
local titleBackground = create("Frame", {
	Name = "Background",
	Parent = titleFrame,
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 2
})

-- 배경은 타이틀 화면 동안 불투명 유지 (게임 월드 숨김)

local originLogo = create("ImageLabel", {
	Name = "TitleLogo",
	Parent = titleBackground,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Image = LOGO_ASSET_ID,
	ScaleType = Enum.ScaleType.Crop,
	ImageTransparency = 0,               
	ZIndex = 3,
	Visible = true
})

-- 로고 이미지 에셋 미리 로드 (ReplicatedFirst에서는 에셋이 아직 다운로드 안 됨)
pcall(function()
	ContentProvider:PreloadAsync({originLogo})
end)

-- 로고 아래 로딩바 추가
local progressBarBG = create("Frame", {
	Name = "ProgressBarBG",
	Parent = titleFrame,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.75, 0),
	Size = UDim2.new(0.4, 0, 0, 6), -- 두께 증가
	BackgroundColor3 = Color3.fromRGB(30, 30, 30),
	BorderSizePixel = 0,
	ZIndex = 11
})
create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Parent = progressBarBG })
create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = progressBarBG })

local progressBarFill = create("Frame", {
	Name = "ProgressBarFill",
	Parent = progressBarBG,
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(245, 185, 50),
	BorderSizePixel = 0,
	ZIndex = 12
})
create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = progressBarFill })

local statusText = create("TextLabel", {
	Name = "StatusText",
	Parent = titleFrame,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.75, -24),
	Size = UDim2.new(0, 400, 0, 20),
	BackgroundTransparency = 1,
	Text = "데이터를 불러오고 있습니다...",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	ZIndex = 11
})
create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Parent = statusText })

local percentText = create("TextLabel", {
	Name = "PercentText",
	Parent = progressBarBG,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 8),
	Size = UDim2.new(0, 40, 0, 20),
	BackgroundTransparency = 1,
	Text = "0%",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 14,
	Font = Enum.Font.GothamBold,
	ZIndex = 11
})
create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Parent = percentText })

-- 로고 비율 유지를 위한 제약 조건 추가 (화면 가득 채우기 위해 제거)

local touchToStartText = create("TextLabel", {
	Name = "TouchToStartText",
	Parent = titleFrame,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.75, 0),
	Size = UDim2.new(0.5, 0, 0.05, 0),
	BackgroundTransparency = 1,
	Text = "화면을 터치해주세요.",
	TextColor3 = Color3.fromRGB(245, 185, 50), -- 골드 색상으로 컨벤션 통일
	TextSize = 24,
	Font = Enum.Font.GothamBold,
	TextTransparency = 1,
	ZIndex = 11
})
local touchStroke = create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Transparency = 1, Parent = touchToStartText })

local invisibleStartButton = create("TextButton", {
	Name = "InvisibleStartButton",
	Parent = titleFrame,
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 0.99, -- 0.99로 클릭 히트영역 확보
	Active = true, -- 입력 가로채기 보장
	Text = "",
	ZIndex = 15 -- ZIndex 순서 상위에 배치하여 클릭 차단 차단
})

-- Credits 버튼 추가
local creditsButton = create("TextButton", {
	Name = "CreditsButton",
	Parent = titleFrame,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.new(0, 100, 0, 35),
	BackgroundColor3 = Color3.fromRGB(50, 50, 50),
	BackgroundTransparency = 0.5,
	Active = true, -- 입력 가로채기 보장
	Text = "Credits",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	TextSize = 14,
	Font = Enum.Font.GothamMedium,
	ZIndex = 20  -- 전역 클릭 버튼보다 위에 배치
})

create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = creditsButton })

-- Credits GUI (Frame) 생성
local creditsFrame = create("Frame", {
	Name = "CreditsFrame",
	Parent = screenGui,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 400, 0, 300),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 20
})

create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = creditsFrame })
create("UIStroke", { Color = Color3.fromRGB(245, 185, 50), Thickness = 2, Parent = creditsFrame })

local creditsTitle = create("TextLabel", {
	Name = "Title",
	Parent = creditsFrame,
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 1,
	Text = "CREDITS",
	TextColor3 = Color3.fromRGB(245, 185, 50),
	TextSize = 24,
	Font = Enum.Font.GothamBold,
	ZIndex = 21
})

local creditsContent = create("TextLabel", {
	Name = "Content",
	Parent = creditsFrame,
	Position = UDim2.new(0.05, 0, 0.2, 0),
	Size = UDim2.new(0.9, 0, 0.65, 0),
	BackgroundTransparency = 1,
	Text = "WildForge Development Team\n\n[Assets & Tools]\ndino model : happydinos115\nTree by Poly by Google [CC-BY] via Poly Pizza\nTree-2 by Marc Solà [CC-BY] (https://poly.pizza/m/cRipmFHCEVU)\nBush with Berries by Quaternius (https://poly.pizza/m/TSbIxkDtxF)\nDeer by jeremy [CC-BY] via Poly Pizza\nROBLOX Studio / ROJO\n\nSpecial thanks to all creators for their contribution.\n모든 제작자분들의 기여에 진심으로 감사드립니다.",
	TextColor3 = Color3.fromRGB(200, 200, 200),
	TextSize = 14, -- 늘어나는 텍스트를 고려해 16에서 14로 약간 조정
	Font = Enum.Font.Gotham,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 21
})

local closeCredits = create("TextButton", {
	Name = "CloseButton",
	Parent = creditsFrame,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -15),
	Size = UDim2.new(0, 100, 0, 30),
	BackgroundColor3 = Color3.fromRGB(80, 80, 80),
	Text = "CLOSE",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	ZIndex = 21
})
create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = closeCredits })

-- (btnTextConstraint는 버튼 제거로 인해 삭제됨)

-- (전역 버튼이므로 테두리/라운딩 제거)
--=========================================
-- 로직 & 애니메이션
--=========================================

-- 플레이어 조작 비활성화 루프 (Title에 있는 동안)
local function setMovementEnabled(enabled)
	local controls = nil
	pcall(function()
		local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule", 10))
		controls = PlayerModule:GetControls()
	end)
	
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
	
	-- 임시 블러 효과
	if enabled then
		local blur = game.Lighting:FindFirstChild("TitleBlur")
		if blur then blur:Destroy() end
	else
		local blur = game.Lighting:FindFirstChild("TitleBlur") or Instance.new("BlurEffect", game.Lighting)
		blur.Name = "TitleBlur"
		blur.Size = 15
	end
end

setMovementEnabled(false) -- 조작 비활성화

-- [일시정지 형태 뷰 연출] : 캐릭터 공중 유배 및 카메라 고정
local camera = workspace.CurrentCamera
local initCFrame = CFrame.new(0, 50, 0)
local hrp = nil

task.spawn(function()
	local char = player.Character or player.CharacterAdded:Wait()
	hrp = char:WaitForChild("HumanoidRootPart", 10)
	
	-- 서버에서 설정한 SpawnPos 속성 대기 (CharacterAutoLoads=false → LoadCharacter 전에 설정됨)
	local waitTime = 0
	while not player:GetAttribute("SpawnPosX") and waitTime < 10 do
		task.wait(0.1)
		waitTime += 0.1
	end
	
	-- SpawnPos attribute에서 정확한 스폰 위치 결정 (hrp.CFrame은 0,0,0일 수 있음)
	local sx = player:GetAttribute("SpawnPosX")
	local sy = player:GetAttribute("SpawnPosY")
	local sz = player:GetAttribute("SpawnPosZ")
	if sx and sy and sz then
		initCFrame = CFrame.new(sx, sy, sz)
	elseif hrp then
		initCFrame = hrp.CFrame
	end
	
	if hrp then
		-- *** 매우 중요 *** Anchored=true를 먼저 설정 (물리 엔진 작동 방지)
		hrp.Anchored = true
		-- 프레임 대기: Anchored 설정이 완전히 적용되도록 보장
		task.wait()
		-- 이제 안전하게 위치 이동 가능
		hrp.CFrame = initCFrame + Vector3.new(0, 5000, 0)
		
		-- 카메라는 플레이어 스폰 지역 근처의 풍경을 조용히 바라보게 셋팅 (일시정지된 듯한 화면)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = initCFrame * CFrame.new(0, 15, 25) * CFrame.Angles(math.rad(-10), 0, 0)
	end
end)

-- 실제 로딩 프로그래스 제어
local progress = 0

local function updateProgress(targetProgress, speed)
	progress = targetProgress
	TweenService:Create(progressBarFill, TweenInfo.new(speed or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(progress/100, 0, 1, 0)
	}):Play()
	percentText.Text = math.floor(progress) .. "%"
end

-- 1단계: 게임 인스턴스 로딩 대기
statusText.Text = "게임 리소스를 구성하고 있습니다..."
updateProgress(5, 0.5)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
updateProgress(10, 0.3)
task.wait(0.2)

-- 2단계: 핵심 에셋 폴더 대기 및 로드 리스트 생성
statusText.Text = "에셋 데이터를 탐색하고 있습니다..."
local assetsFolder = game.ReplicatedStorage:WaitForChild("Assets", 30)

local preloadList = {}
if assetsFolder then
	-- 에셋 폴더 하위 탐색 (클론되는 투사체, VFX, 사운드, 아이콘 등 렉의 핵심 원인)
	for _, desc in ipairs(assetsFolder:GetDescendants()) do
		if desc:IsA("MeshPart") or desc:IsA("SpecialMesh") or desc:IsA("Decal") or desc:IsA("Texture") 
			or desc:IsA("Sound") or desc:IsA("Animation") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			table.insert(preloadList, desc)
		end
	end
end

-- 3단계: 실제 에셋 사전 로드 진행 (PreloadAsync)
local totalAssets = #preloadList
if totalAssets > 0 then
	local batchSize = 25
	local loadedCount = 0
	local loadingFinished = false
	
	-- 백그라운드 스레드에서 프리로드 수행 (메인 스레드 대기 방지)
	task.spawn(function()
		for i = 1, totalAssets, batchSize do
			if loadingFinished then break end
			
			local batch = {}
			for j = i, math.min(i + batchSize - 1, totalAssets) do
				table.insert(batch, preloadList[j])
			end
			
			-- 비동기 로딩을 pcall로 보호하여 오류 방지
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			
			loadedCount = loadedCount + #batch
			local ratio = loadedCount / totalAssets
			local nextProgress = 10 + math.floor(ratio * 75) -- 10% ~ 85% 구간 할당
			statusText.Text = string.format("에셋을 다운로드 중입니다... (%d/%d)", loadedCount, totalAssets)
			updateProgress(nextProgress, 0.05)
			task.wait()
		end
		loadingFinished = true
	end)
	
	-- 최대 8초간 프리로드 완료 대기 (무한 대기 방지 타임아웃)
	local preloadStartTime = os.clock()
	while not loadingFinished and (os.clock() - preloadStartTime) < 8 do
		task.wait(0.1)
	end
	
	if not loadingFinished then
		warn("[LoadingScreen] Asset preload timed out. Proceeding to prevent hanging.")
		loadingFinished = true
	end
	updateProgress(85, 0.2)
else
	updateProgress(85, 0.5)
end

-- 4단계: 플레이어 데이터 및 서비스 연동 대기
statusText.Text = "게임 정보를 동기화 중입니다..."
local waitStartTime = os.clock()
while (not player:GetAttribute("DataLoaded") or not player:GetAttribute("InventoryLoaded") or not player:GetAttribute("ShopLoaded") or not player:GetAttribute("SkillLoaded")) do
	task.wait(0.2)
	-- 데이터 로드 진행상황에 따라 85% ~ 95% 구간으로 완만히 증가
	local elapsed = os.clock() - waitStartTime
	local fakeProgress = 85 + math.min(math.floor(elapsed * 1.5), 10)
	updateProgress(fakeProgress, 0.2)
end

updateProgress(100, 0.4)
statusText.Text = "접속 완료!"
task.wait(0.6)

-- 로딩바 페이드 아웃
local fadeOutInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine)
TweenService:Create(progressBarBG, fadeOutInfo, {BackgroundTransparency = 1}):Play()
TweenService:Create(progressBarFill, fadeOutInfo, {BackgroundTransparency = 1}):Play()
TweenService:Create(percentText, fadeOutInfo, {TextTransparency = 1}):Play()
TweenService:Create(statusText, fadeOutInfo, {TextTransparency = 1}):Play()
for _, v in ipairs({progressBarBG, percentText, statusText}) do
	local stroke = v:FindFirstChildOfClass("UIStroke")
	if stroke then TweenService:Create(stroke, fadeOutInfo, {Transparency = 1}):Play() end
end
task.wait(0.5)

-- 안내 텍스트 페이드 인
TweenService:Create(touchToStartText, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
TweenService:Create(touchStroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { Transparency = 0 }):Play()

-- 안내 텍스트 깜빡임 효과 (Blink)
task.spawn(function()
	while titleFrame.Visible do
		TweenService:Create(touchToStartText, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { TextTransparency = 0.6 }):Play()
		TweenService:Create(touchStroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { Transparency = 0.6 }):Play()
		task.wait(1.0)
		TweenService:Create(touchToStartText, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
		TweenService:Create(touchStroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { Transparency = 0 }):Play()
		task.wait(1.0)
	end
end)

-- 메인 메뉴 버튼 이벤트
local function applyHoverEffect(button, defaultColor, hoverColor, defaultTrans, hoverTrans)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), {
			BackgroundColor3 = hoverColor,
			BackgroundTransparency = hoverTrans
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.2), {
			BackgroundColor3 = defaultColor,
			BackgroundTransparency = defaultTrans
		}):Play()
	end)
end

-- 듀랑고 스타일 고대 문서 호버 효과 (전역 버튼은 스킵)
applyHoverEffect(creditsButton, Color3.fromRGB(50, 50, 50), Color3.fromRGB(80, 80, 80), 0.5, 0.3)

creditsButton.MouseButton1Click:Connect(function()
	creditsFrame.Visible = true
end)

closeCredits.MouseButton1Click:Connect(function()
	creditsFrame.Visible = false
end)

-- 아무데나 클릭 시 시작
invisibleStartButton.Activated:Connect(function()
	print(string.format("[LoadingScreen] Touch/Click registered on InvisibleStartButton. Progress: %s", tostring(progress)))
	-- 로딩이 완료되지 않았으면 클릭 무시
	if progress < 100 then return end
	
	-- 클릭 시 텍스트 즉시 반응
	touchToStartText.TextTransparency = 0
	touchStroke.Transparency = 0
	
	-- 화면 암전 혹은 페이드 아웃
	local blackFrame = create("Frame", {
		Name = "FadeFrame",
		Parent = screenGui,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 30 -- 가장 위에
	})
	
	local startFade = TweenService:Create(blackFrame, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	})
	startFade:Play()
	startFade.Completed:Wait()
	
	-- 게임 조작 복구 및 UI 제거
	titleFrame.Visible = false
	
	local currentChar = player.Character
	local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
	if currentHrp then
		currentHrp.Anchored = false
	end
	
	setMovementEnabled(true)
	
	-- 플레이어 위치 원상복구 및 공룡 공격 회피 해제, 카메라 정상화
	if currentHrp then
		-- SpawnPos 속성에서 최신 서버 권위 위치 재확인
		local sx = player:GetAttribute("SpawnPosX")
		local sy = player:GetAttribute("SpawnPosY")
		local sz = player:GetAttribute("SpawnPosZ")
		if sx and sy and sz then
			currentHrp.CFrame = CFrame.new(sx, sy, sz)
		else
			currentHrp.CFrame = initCFrame
		end
		currentHrp.Anchored = false
	end
	camera.CameraType = Enum.CameraType.Custom
	
	setMovementEnabled(true)
	player:SetAttribute("GameStarted", true)
	
	-- 다시 페이드 인
	local endFade = TweenService:Create(blackFrame, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})
	endFade:Play()
	endFade.Completed:Wait()
	
	screenGui:Destroy()
end)

print("[LoadingScreen] Title Screen Sequence Initiated")
