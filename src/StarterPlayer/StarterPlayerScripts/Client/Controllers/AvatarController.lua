-- AvatarController.lua
-- 아바타 검술 RPG: 원소 속성 선택 UI, 실물 나무검(Accessory) 연계, 3단 연타 평타 콤보 및 타격 VFX 클라이언트 컨트롤러

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

-- [Convention Integration] 기존 인벤토리/스텟 시스템과 동일한 UI 테마 및 유틸리티 도입
local Theme = require(script.Parent.Parent.UI.UITheme)
local Utils = require(script.Parent.Parent.UI.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local player = Players.LocalPlayer
local AvatarController = {}
local elementSelected = false

-- 콤보 시스템 상태 제어용 프라이빗 변수군
local comboIndex = 1              -- 현재 공격 콤보 단계 (1 ➡️ 2 ➡️ 3)
local lastAttackTime = 0          -- 마지막 평타 시전 타임스탬프
local attackCooldown = false      -- 연타 쿨다운 가드
local COMBO_WINDOW = 0.8          -- 콤보 연타 유효 판정 시간 (0.8초 이내 클릭 시 다음 콤보 발동)

--========================================
-- [FX] 기본 공격 VFX 및 Sound 유틸리티
--========================================
local function getElementVFXFolder(category: string) -- "Cast" or "Hit"
	local assets = ReplicatedStorage:WaitForChild("Assets", 5)
	if not assets then 
		warn("[VFX ERROR] 'Assets' folder not found in ReplicatedStorage!")
		return nil 
	end
	local vfxRoot = assets:FindFirstChild("VFX")
	if not vfxRoot then 
		warn("[VFX ERROR] 'VFX' folder not found in ReplicatedStorage.Assets!")
		return nil 
	end
	local sub = vfxRoot:FindFirstChild(category)
	if not sub then
		warn(string.format("[VFX ERROR] '%s' subfolder not found in ReplicatedStorage.Assets.VFX!", category))
	end
	return sub
end

local function spawnCombatVFX(template: Instance, cframe: CFrame, lifetime: number, parentPart: BasePart?, scaleFactor: number?, moveForwardDist: number?)
	if not template then return end
	local vfx = template:Clone()
	
	scaleFactor = scaleFactor or 1.0
	if scaleFactor ~= 1.0 then
		-- 1. 모델 또는 파트 스케일링
		if vfx:IsA("Model") then
			pcall(function() vfx:ScaleTo(scaleFactor) end)
		elseif vfx:IsA("BasePart") then
			vfx.Size = vfx.Size * scaleFactor
		end
		
		-- 2. 파티클 이미터 및 어태치먼트 내부 스케일링 보정
		for _, desc in ipairs(vfx:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				-- 파티클 크기 스퀀스 스케일링
				local originalSeq = desc.Size
				local keypoints = originalSeq.Keypoints
				local newKeypoints = {}
				for _, kp in ipairs(keypoints) do
					table.insert(newKeypoints, NumberSequenceKeypoint.new(
						kp.Time, 
						kp.Value * scaleFactor, 
						kp.Envelope * scaleFactor
					))
				end
				desc.Size = NumberSequence.new(newKeypoints)
				
				-- 파티클 속도 범위도 스케일에 맞춰 확장
				desc.Speed = NumberRange.new(desc.Speed.Min * scaleFactor, desc.Speed.Max * scaleFactor)
			elseif desc:IsA("Attachment") and not vfx:IsA("Model") then
				-- 단일 파트일 경우에만 어태치먼트 상대좌표 수동 보정 (모델은 ScaleTo가 자동 처리)
				desc.Position = desc.Position * scaleFactor
			end
		end
	end
	
	-- [디렉티브 반영] 앞으로 투사(Tween)해야하는지 여부 판별
	local shouldTweenForward = (moveForwardDist and moveForwardDist > 0)
	
	if vfx:IsA("BasePart") then
		vfx.CFrame = cframe
		-- 앞으로 뻗어나갈 때는 물리 엔진의 중력 낙하를 막기 위해 무조건 고정(Anchored) 처리
		vfx.Anchored = (parentPart == nil) or shouldTweenForward
		vfx.CanCollide = false
		vfx.CanQuery = false
		vfx.CanTouch = false
		
		-- 날아가는 투사체 형태가 아닐 때만 원래대로 캐릭터에 본드 고정(Weld)
		if parentPart and not shouldTweenForward then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = vfx
			weld.Part1 = parentPart
			weld.Parent = vfx
		end
		if not vfx:IsA("MeshPart") then
			vfx.Transparency = 1
		end
	elseif vfx:IsA("Model") then
		vfx:PivotTo(cframe)
		if parentPart and not shouldTweenForward then
			local root = vfx.PrimaryPart or vfx:FindFirstChildWhichIsA("BasePart")
			if root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = parentPart
				weld.Parent = root
				for _, d in ipairs(vfx:GetDescendants()) do
					if d:IsA("BasePart") then d.Anchored = false end
				end
			end
		elseif shouldTweenForward then
			-- 모델 투사체 역시 트윈 시 공중 부양을 위해 전부 고정
			for _, d in ipairs(vfx:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true end
			end
		end
	end

	for _, desc in ipairs(vfx:GetDescendants()) do
		if desc:IsA("Part") and not desc:IsA("MeshPart") then
			desc.Transparency = 1
		end
	end

	-- [긴급 교정 디렉티브 반영] 에셋 자체에 내포되어있던 로컬 오프셋(Attachment Offset 또는 Pivot Offset) 강제 영점(Zeroing) 보정!
	-- 아티스트가 로블록스 스튜디오에서 파티클 위치나 피벗을 임의로 밀어서 제작했더라도, 강제로 몸통 중심으로 결속시킵니다.
	if shouldTweenForward then
		-- 1. 어태치먼트 오프셋 제거 (Z축 강제 정렬)
		for _, desc in ipairs(vfx:GetDescendants()) do
			if desc:IsA("Attachment") then
				-- 기존 X(가로), Y(높이) 레이아웃만 보존하고 Z(전후방) 오프셋을 0으로 밀어버려 완벽한 몸통 생성 강제!
				desc.Position = Vector3.new(desc.Position.X, desc.Position.Y, 0)
			end
		end
		
		-- 2. 모델 피벗 정렬 (만약 모델 자체가 기하학적으로 중심에서 밀려있는 경우)
		if vfx:IsA("Model") then
			pcall(function()
				local currentBoundingCF, _ = vfx:GetBoundingBox()
				-- 모델의 피벗을 내부 구성물들의 기하학적 정중앙으로 강제 귀속
				vfx.WorldPivot = currentBoundingCF
				-- 바뀐 중앙 피벗 기준으로 몸통 중심(cframe)에 재배치
				vfx:PivotTo(cframe)
			end)
		end
	end

	vfx.Parent = workspace

	-- [디렉티브 반영] 1단계: 파티클 이미터를 즉시 가동하여 '몸통 고정 지점'에서 무조건 첫 출력을 완료합니다.
	-- 파트가 트윈으로 전진을 시작하기 전에, 몸통 자리에서 먼저 번쩍이거나 첫 이미트가 발생하도록 보장합니다.
	for _, desc in ipairs(vfx:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			local burstCount = desc:GetAttribute("BurstCount")
			if burstCount then
				desc:Emit(burstCount)
			else
				-- 연속 방출형일 경우에도 스폰 순간 첫 발을 강제 이미트(Emit)하여 몸체 빈 공간 제거!
				pcall(function() desc:Emit(math.max(1, math.floor(desc.Rate * 0.1))) end)
				desc.Enabled = true
				task.delay(lifetime * 0.5, function()
					if desc and desc.Parent then desc.Enabled = false end
				end)
			end
		end
	end
	
	-- [디렉티브 반영] 2단계: 0.06초(약 4프레임) 간 몸체 자리에 확고한 앵커링을 통해 시각적 각인을 준 후 전방 고속 비행을 개시합니다.
	if shouldTweenForward then
		task.delay(0.06, function()
			if not vfx or not vfx.Parent then return end
			
			local targetCF = cframe * CFrame.new(0, 0, -moveForwardDist)
			local tweenDur = math.min(lifetime * 0.65, 0.45) 
			local info = TweenInfo.new(tweenDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			
			if vfx:IsA("BasePart") then
				TweenService:Create(vfx, info, {CFrame = targetCF}):Play()
			elseif vfx:IsA("Model") then
				local cfProxy = Instance.new("CFrameValue")
				cfProxy.Value = cframe
				cfProxy.Changed:Connect(function(val)
					if vfx and vfx.Parent then
						vfx:PivotTo(val)
					end
				end)
				local t = TweenService:Create(cfProxy, info, {Value = targetCF})
				t:Play()
				t.Completed:Once(function()
					cfProxy:Destroy()
				end)
			end
		end)
	end
	
	Debris:AddItem(vfx, lifetime)
end
local function getCombatSoundFolder(category: string) -- "Cast"
	local assets = ReplicatedStorage:WaitForChild("Assets", 5)
	if not assets then 
		warn("[SOUND ERROR] 'Assets' folder not found in ReplicatedStorage!")
		return nil 
	end
	local soundRoot = assets:FindFirstChild("Sounds")
	if not soundRoot then 
		warn("[SOUND ERROR] 'Sounds' folder not found in ReplicatedStorage.Assets!")
		return nil 
	end
	local sub = soundRoot:FindFirstChild(category)
	if not sub then
		warn(string.format("[SOUND ERROR] '%s' subfolder not found in ReplicatedStorage.Assets.Sounds!", category))
	end
	return sub
end

local SOUND_VOLUME_SCALE = 0.3
local function playCombatSound(template: Sound, parent: BasePart?)
	if not template or not parent then return end
	local sfx = template:Clone()
	sfx.Volume = (sfx.Volume or 0.5) * SOUND_VOLUME_SCALE
	sfx.Parent = parent
	sfx:Play()
	sfx.Ended:Once(function()
		if sfx and sfx.Parent then
			sfx:Destroy()
		end
	end)
end

--- 카메라 쉐이크 (타격감)
local function playHitShake(intensity)
	local cam = workspace.CurrentCamera
	if not cam then return end
	
	task.spawn(function()
		local originalCF = cam.CFrame
		for i = 1, 4 do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)
			cam.CFrame = originalCF * CFrame.new(offset)
			task.wait(0.02)
		end
		cam.CFrame = originalCF
	end)
end

local function getRemoteEvent(name)
	local parts = string.split(name, ".")
	local current = ReplicatedStorage
	for _, partName in ipairs(parts) do
		current = current:WaitForChild(partName, 10)
		if not current then
			warn(string.format("[AvatarController] Remote %s not found in ReplicatedStorage!", name))
			return nil
		end
	end
	return current
end

local function createSelectionUI()
	local playerGui = player:WaitForChild("PlayerGui")
	
	local oldScreen = playerGui:FindFirstChild("AvatarSelectScreen")
	if oldScreen then oldScreen:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AvatarSelectScreen"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	mainFrame.BackgroundTransparency = 0.25
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 80)
	title.Position = UDim2.new(0, 0, 0.15, 0)
	title.Text = "아바타 아앙의 전설: 검술 RPG"
	title.TextColor3 = Color3.fromRGB(255, 240, 200)
	title.TextSize = 36
	title.Font = Enum.Font.SourceSansBold
	title.TextStrokeTransparency = 0.5
	title.BackgroundTransparency = 1
	title.Parent = mainFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0, 40)
	subtitle.Position = UDim2.new(0, 0, 0.23, 0)
	subtitle.Text = "숙명의 원소 속성을 선택하여 검의 지배자가 되십시오"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 190)
	subtitle.TextSize = 18
	subtitle.Font = Enum.Font.SourceSans
	subtitle.BackgroundTransparency = 1
	subtitle.Parent = mainFrame

	local cardsContainer = Instance.new("Frame")
	cardsContainer.Size = UDim2.new(0, 660, 0, 240)
	cardsContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	cardsContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.Parent = mainFrame

	local ClassData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ClassData"))
	local elements = {}
	for classId, data in pairs(ClassData) do
		table.insert(elements, {
			id = classId,
			name = data.name,
			color = Color3.fromRGB(data.color.r, data.color.g, data.color.b),
			desc = data.desc
		})
	end
	table.sort(elements, function(a, b)
		local order = {Fire = 1, Water = 2, Earth = 3}
		return (order[a.id] or 99) < (order[b.id] or 99)
	end)

	for idx, el in ipairs(elements) do
		local card = Instance.new("TextButton")
		card.Name = el.id.."Card"
		card.Size = UDim2.new(0, 200, 1, 0)
		card.Position = UDim2.new(0, (idx - 1) * 230, 0, 0)
		card.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.Parent = cardsContainer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = el.color
		stroke.Parent = card

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, 0, 0, 40)
		nameLbl.Position = UDim2.new(0, 0, 0.2, 0)
		nameLbl.Text = el.name
		nameLbl.TextColor3 = el.color
		nameLbl.TextSize = 20
		nameLbl.Font = Enum.Font.SourceSansBold
		nameLbl.BackgroundTransparency = 1
		nameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.85, 0, 0.4, 0)
		descLbl.Position = UDim2.new(0.5, 0, 0.45, 0)
		descLbl.AnchorPoint = Vector2.new(0.5, 0)
		descLbl.Text = el.desc
		descLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
		descLbl.TextSize = 14
		descLbl.Font = Enum.Font.SourceSans
		descLbl.TextWrapped = true
		descLbl.BackgroundTransparency = 1
		descLbl.Parent = card

		card.MouseEnter:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(40, 40, 55),
				Size = UDim2.new(0, 210, 1, 10),
				Position = UDim2.new(0, (idx - 1) * 230 - 5, 0, -5)
			}):Play()
		end)

		card.MouseLeave:Connect(function()
			TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(25, 25, 35),
				Size = UDim2.new(0, 200, 1, 0),
				Position = UDim2.new(0, (idx - 1) * 230, 0, 0)
			}):Play()
		end)

		card.MouseButton1Click:Connect(function()
			if elementSelected then return end
			elementSelected = true
			
			TweenService:Create(mainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
			task.delay(0.4, function() screenGui:Destroy() end)

			local selectRemote = getRemoteEvent("Avatar.SelectElement.Request")
			if selectRemote then
				selectRemote:FireServer({element = el.id})
				print(string.format("[AvatarController] Sent Element choice: %s to server", el.id))
			end
		end)
	end

	screenGui.Parent = playerGui
end

local function createDialogueUI(element)
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- [기존 UI 제거]
	local oldScreen = playerGui:FindFirstChild("AvatarSelectScreen")
	if oldScreen then oldScreen:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AvatarSelectScreen"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- 1. 백그라운드 딤 오버레이
	local mainFrame = Utils.mkFrame({
		name = "DimOverlay",
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		useCanvas = true, -- 페이드 트랜지션용
		parent = screenGui
	})

	-- 2. 메인 윈도우 박스 (Convention: mkWindow 활용)
	local ClassData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ClassData"))
	local data = ClassData[element]
	local themeColor = data and Color3.fromRGB(data.color.r, data.color.g, data.color.b) or C.BORDER

	local dialogBox = Utils.mkWindow({
		name = "DialogueBox",
		-- [반응형 업그레이드] 고정 픽셀(Offset) 제거 -> 비율(Scale) + 종횡비(Ratio) 체제로 전환!
		-- 모바일에서는 화면의 85%를 차지하며 유동적으로 변하고, PC 대화면에서는 maxSize에 걸려 최적 크기를 유지합니다.
		size = UDim2.new(0.85, 0, 0.8, 0),
		maxSize = Vector2.new(560, 280), -- PC 환경 최대 제한 폭
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		stroke = 2.5,
		strokeC = themeColor,
		ratio = 2.0, -- 황금 종횡비 고정 (2:1) -> 어떤 기기에서도 동일한 디자인 비율 강제!
		parent = mainFrame
	})

	-- 텍스트 내용 구성
	local masterTitle = ""
	local dialogueText = ""
	if element == "Water" then
		masterTitle = "물의 스승"
		dialogueText = "“세상은 언제나 변한다.\n강한 자가 살아남는 것이 아니라, 흐름을 아는 자가 살아남는다.\n자, 선택하라. 너는 물처럼 변하고, 다시 일어설 수 있느냐?”"
	elseif element == "Fire" then
		masterTitle = "불의 스승"
		dialogueText = "“내 힘을 받는 순간, 너는 더 이상 뒤로 물러설 수 없다.\n적을 베고, 어둠을 태우고, 네 길을 스스로 밝혀라.\n자, 선택하라. 너의 심장은 불타고 있느냐?”"
	else
		masterTitle = "흙의 스승"
		dialogueText = "“빠른 힘은 쉽게 꺼지고, 얕은 뿌리는 쉽게 뽑힌다.\n하지만 대지는 오래 버티는 자에게 응답한다.\n자, 선택하라. 너는 마지막까지 서 있을 수 있느냐?”"
	end

	-- 3. 타이틀 레이블 (Scale 좌표계 적용)
	local titleLbl = Utils.mkLabel({
		text = masterTitle,
		size = UDim2.new(1, 0, 0.22, 0),
		pos = UDim2.new(0, 0, 0.05, 0),
		ts = 22, -- 기준 폰트 크기
		font = F.TITLE,
		color = themeColor,
		bold = true,
		parent = dialogBox
	})

	-- 4. 본문 내용 레이블 (반응형 폰트 스케일링 결합)
	local contentLbl = Utils.mkLabel({
		text = dialogueText,
		size = UDim2.new(0.88, 0, 0.38, 0),
		pos = UDim2.new(0.5, 0, 0.32, 0),
		anchor = Vector2.new(0.5, 0),
		ts = 16,
		font = F.NORMAL,
		color = C.WHITE,
		wrap = true,
		parent = dialogBox
	})
	contentLbl.LineHeight = 1.25
	-- [핵심] 화면이 작아지면 텍스트도 자동 축소되어 오버플로우 방지
	contentLbl.TextScaled = true 
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MaxTextSize = 18
	textLimit.MinTextSize = 11
	textLimit.Parent = contentLbl

	-- 5. 버튼 컨테이너 (Scale 좌표계 적용)
	local btnArea = Utils.mkFrame({
		size = UDim2.new(0.9, 0, 0.18, 0),
		pos = UDim2.new(0.5, 0, 0.88, 0),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = dialogBox
	})
	
	local btnList = Instance.new("UIListLayout")
	btnList.FillDirection = Enum.FillDirection.Horizontal
	btnList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnList.Padding = UDim.new(0, 15)
	btnList.Parent = btnArea

	-- 6. "예" 수락 버튼 (액션 버튼 컬러)
	local yesBtn = Utils.mkBtn({
		text = "예 (Choose)",
		size = UDim2.new(0.45, 0, 1, 0),
		bg = themeColor, -- 테마 컬러를 버튼에도 살짝 주입하여 포인트 강화
		bgT = 0.3,
		ts = 16,
		font = F.TITLE,
		color = C.WHITE,
		stroke = 1.5,
		strokeC = themeColor,
		parent = btnArea
	})

	-- 7. "아니오" 취소 버튼 (Negative Gray 컨벤션)
	local noBtn = Utils.mkBtn({
		text = "아니오 (Cancel)",
		size = UDim2.new(0.45, 0, 1, 0),
		isNegative = true,
		ts = 16,
		font = F.TITLE,
		parent = btnArea
	})

	-- 8. 이벤트 및 클로즈 애니메이션 연동
	local dialogClicked = false
	local function closeUI(instant)
		if instant then
			screenGui:Destroy()
			return
		end
		TweenService:Create(mainFrame, TweenInfo.new(0.25), {GroupTransparency = 1}):Play()
		task.delay(0.25, function() screenGui:Destroy() end)
	end

	yesBtn.MouseButton1Click:Connect(function()
		if dialogClicked then return end
		dialogClicked = true
		
		closeUI()
		local selectRemote = getRemoteEvent("Avatar.SelectElement.Request")
		if selectRemote then
			selectRemote:FireServer({element = element})
			print(string.format("[AvatarController] %s 스승의 제자 선택 완료 (Sent to Server)", element))
		end
	end)

	noBtn.MouseButton1Click:Connect(function()
		closeUI()
	end)

	screenGui.Parent = playerGui
	
	-- 등장 페이드 인 애니메이션
	mainFrame.GroupTransparency = 1
	TweenService:Create(mainFrame, TweenInfo.new(0.35), {GroupTransparency = 0}):Play()
end

local function findNearestTarget()
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local bestTarget = nil
	local minDistance = 18 -- [상향] 타격 사거리 12 -> 18 스터드 확대

	-- Workspace 전체에서 타격 대상 검색 고도화
	for _, obj in ipairs(workspace:GetChildren()) do
		-- 1. 자신은 제외
		if obj == char then continue end
		
		-- 2. 휴머노이드가 있는 생명체 모델만 대상
		if obj:IsA("Model") then
			local hum = obj:FindFirstChild("Humanoid")
			local targetHrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
			
			-- 3. 죽지 않았고, 다른 플레이어가 아닌 경우에만 몬스터 타겟으로 인식!
			if hum and hum.Health > 0 and targetHrp and not Players:GetPlayerFromCharacter(obj) then
				local dist = (hrp.Position - targetHrp.Position).Magnitude
				if dist < minDistance then
					minDistance = dist
					bestTarget = obj
				end
			end
		end
	end

	return bestTarget
end

-- 기본 좌클릭 3단 콤보 공격 처리 함수
local function handleLMBAttack()
	if attackCooldown then return end
	
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if hum and hum.Health <= 0 then return end

	-- [Data-Driven 무기 및 콤보 정보 획득]
	local WeaponComboData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponComboData"))
	local equippedWeapon = player:GetAttribute("EquippedWeapon") or "WOODEN_STAFF"
	local weaponData = WeaponComboData[equippedWeapon]
	if not weaponData then return end

	-- 무기 장착 확인 (실물 3D Accessory 또는 어트리뷰트 감지)
	local hasStaff = char:FindFirstChild(equippedWeapon) or player:GetAttribute("EquippedWeapon") == equippedWeapon
	if not hasStaff then return end

	attackCooldown = true
	local comboCooldown = weaponData.cooldown or 0.28
	local comboWindow = weaponData.comboWindow or 0.8
	local maxCombo = weaponData.maxCombo or 3

	task.delay(comboCooldown, function() attackCooldown = false end)

	local now = os.clock()
	-- 콤보 타이밍 판정 (데이터 스펙 기반의 연타 유효 판정)
	if now - lastAttackTime <= comboWindow then
		comboIndex = comboIndex + 1
		if comboIndex > maxCombo then comboIndex = 1 end -- 최대 타수 초과 시 다시 1타 순환
	else
		comboIndex = 1 -- 콤보 연결 시간 초과 시 1타로 초기화
	end
	lastAttackTime = now

	-- [대분류 및 스크린샷 완벽 싱크 경로 검색] ReplicatedStorage/Assets/Animations/Weapons/Staff/Staff_None_AttackSwing[1/2/3]
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local animationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	local weaponsAnimFolder = animationsFolder and animationsFolder:FindFirstChild("Weapons")
	local staffAnimFolder = weaponsAnimFolder and weaponsAnimFolder:FindFirstChild("Staff")
	
	-- 콤보 인덱스에 매핑되는 애니메이션 불러오기
	local animName = weaponData.animations[comboIndex] or ("Staff_None_AttackSwing" .. comboIndex)
	local targetAnim = staffAnimFolder and staffAnimFolder:FindFirstChild(animName)

	local playedAnim = false
	local currentAttackTrack = nil
	if targetAnim and hum then
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local success, track = pcall(function() return animator:LoadAnimation(targetAnim) end)
		if success and track then
			track:Play()
			playedAnim = true
			currentAttackTrack = track
			print(string.format("[AvatarController] Playing Combo %d Animation: %s", comboIndex, animName))
		end
	end

	-- [Sound] 기본 공격 Cast 사운드 재생 (공기 가르기)
	local castSoundFolder = getCombatSoundFolder("Cast")
	if castSoundFolder then
		local soundName = string.format("Default_Attack_Cast_%d", comboIndex)
		local template = castSoundFolder:FindFirstChild(soundName)
		if template then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				playCombatSound(template, hrp)
			end
		else
			warn(string.format("[SOUND INFO] '%s' sound not found in Assets.Sounds.Cast (Skipping)", soundName))
		end
	end

	-- [VFX] 기본 공격 Cast VFX 재생 (스윙 즉시 캐릭터 위치 생성)
	local castVFXFolder = getElementVFXFolder("Cast")
	if castVFXFolder then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local targetCFrame = hrp.CFrame * CFrame.new(0, 0, 0.2) -- [디렉티브 반영] 완벽하게 캐릭터 몸통 내부(Torso Center)에서 시작
			
			-- [디렉티브 반영] 속성이 선택되어 있다면 '속성 CAST'만 출력, 아무 속성도 없을 때(디폴트)만 '디폴트 CAST' 출력!
			local currentElement = player and player:GetAttribute("Element")
			local hasElement = currentElement and currentElement ~= "" and currentElement ~= "None"
			
			if hasElement then
				-- 1. 속성 레이어 전용 출력
				local vfxName = string.format("%s_Attack_Cast_%d", currentElement, comboIndex)
				local elementTemplate = castVFXFolder:FindFirstChild(vfxName)
				if elementTemplate then
					-- 완벽히 속성 파티클 단독으로 9.5스터드 비행
					spawnCombatVFX(elementTemplate, targetCFrame, 2.0, hrp, 1.0, 9.5)
				else
					warn(string.format("[VFX INFO] '%s' not found in Assets.VFX.Cast (Skipping element cast)", vfxName))
				end
			else
				-- 2. 디폴트 레이어 전용 출력 (무속성 상태)
				local baseCandidates = {
					string.format("Default_Attack_Cast_%d", comboIndex),
					string.format("Base_Attack_Cast_%d", comboIndex),
				}
				local baseTemplate = nil
				for _, candidate in ipairs(baseCandidates) do
					baseTemplate = castVFXFolder:FindFirstChild(candidate)
					if baseTemplate then break end
				end
				if baseTemplate then
					spawnCombatVFX(baseTemplate, targetCFrame, 2.0, hrp, 1.0, 9.5)
				else
					warn(string.format("[VFX INFO] '%s' not found in Assets.VFX.Cast (Skipping base cast)", string.format("Default_Attack_Cast_%d", comboIndex)))
				end
			end
		end
	end

	-- 애니메이션 객체가 없을 때의 부드러운 우회 횡베기 콤보 연출 트윈 (안전 장치)
	if not playedAnim then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local visualData = weaponData.fallbackVisuals[comboIndex] or { angle = 25, duration = 0.08 }
			local angleDir = visualData.angle
			local duration = visualData.duration
			local origCFrame = hrp.CFrame
			TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				CFrame = origCFrame * CFrame.Angles(0, math.rad(angleDir), 0)
			}):Play()
		end
	end

	-- 비동기 스코프 보존용 콤보 인덱스 복제
	local attackCombo = comboIndex
	local targetMob = findNearestTarget()

	-- [FX 피드백 비동기 연동 타임]
	task.spawn(function()
		local hitTriggered = false
		local conn
		
		if currentAttackTrack then
			conn = currentAttackTrack:GetMarkerReachedSignal("Hit"):Connect(function()
				hitTriggered = true
				if conn then conn:Disconnect(); conn = nil end
			end)
		end
		
		-- 마커 대기 또는 windup 타임아웃 대기
		local startWait = os.clock()
		local windupTime = 0.22 -- 맨손보다 살짝 느린 스태프 기준의 기본 대기시간
		while os.clock() - startWait < windupTime and not hitTriggered do
			task.wait()
		end
		if conn then conn:Disconnect() end

		-- 타격 진동 (카메라 쉐이크)
		playHitShake(0.5)

		-- [시스템화 반영] 서버 데미지 틱 단위 재생을 위해, 기존 클라이언트 애니메이션 이벤트 단일 사운드/VFX 로직 삭제 및 하단 OnClientEvent로 대통합.
	end)

	-- 타겟 몬스터 타격 요청 발송 (서버 연동)
	local attackRemote = getRemoteEvent("Avatar.Attack.Request")
	if targetMob and attackRemote then
		attackRemote:FireServer({targetModel = targetMob, combo = comboIndex})
	end
end



function AvatarController.Init()
	print("[AvatarController] Initializing Client Avatar Controller with 3-Combo Attack...")

	-- [상호작용 연동] 스승 NPC 및 제단 ProximityPrompt에서 서버가 OpenSelectionUI 신호를 보내올 때 속성 선택 대화/카드 UI 노출
	task.spawn(function()
		local openRemote = getRemoteEvent("Avatar.OpenSelectionUI")
		if openRemote then
			openRemote.OnClientEvent:Connect(function(element)
				print(string.format("[AvatarController] Received OpenSelectionUI event from server! Element argument: %s", tostring(element)))
				if element then
					createDialogueUI(element)
				else
					createSelectionUI()
				end
			end)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			handleLMBAttack()
		end
	end)

	task.spawn(function()
		local vfxRemote = getRemoteEvent("Avatar.VFX.Hit")
		if vfxRemote then
			vfxRemote.OnClientEvent:Connect(function(data)
				local target = data.target
				local element = data.element
				local pos = data.position
				local damage = data.damage
				local isCrit = data.isCritical == true

				if target and pos then
					local targetHrp = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
					if not targetHrp then return end

					-- 0. [디렉티브 반영] 기본 공격 다단히트 틱당 공용 어택 히트 VFX/사운드 시스템 동기화 재생
					pcall(function()
						-- [Sound 재생]
						local hitSoundFolder = getCombatSoundFolder("Hit")
						if hitSoundFolder then
							local hitSndTemplate = hitSoundFolder:FindFirstChild("Default_Attack_Hit") or hitSoundFolder:FindFirstChild("Base_Attack_Hit")
							if hitSndTemplate then
								playCombatSound(hitSndTemplate, targetHrp)
							end
						end
						
						-- [VFX 재생]
						local hitFolder = getElementVFXFolder("Hit")
						if hitFolder then
							local hitVfxTemplate = hitFolder:FindFirstChild("Default_Attack_Hit") or hitFolder:FindFirstChild("Base_Attack_Hit")
							if hitVfxTemplate then
								-- 데미지 타격 좌표를 바탕으로 월드에 이펙트 투척
								spawnCombatVFX(hitVfxTemplate, CFrame.new(pos), 2.0)
							end
						end
					end)

					-- 1. 플로팅 대미지 텍스트 생성 (Floating Damage Text)
					local bb = Instance.new("BillboardGui")
					bb.Size = UDim2.new(0, 100, 0, 40)
					-- 랜덤 오프셋을 살짝 주어 여러개 뜰 때 겹치지 않게 함
					local rx = math.random(-15, 15) / 10
					local rz = math.random(-15, 15) / 10
					bb.StudsOffset = Vector3.new(rx, 3, rz) 
					bb.AlwaysOnTop = true
					
					local label = Instance.new("TextLabel")
					label.Size = UDim2.new(1, 0, 1, 0)
					label.BackgroundTransparency = 1
					label.Text = tostring(math.floor(damage))
					label.Font = Enum.Font.LuckiestGuy -- 아케이드 느낌의 두꺼운 폰트
					
					local stroke = Instance.new("UIStroke")
					stroke.Thickness = 3.5 -- 레퍼런스처럼 굵은 외곽선!
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
					stroke.Parent = label
					
					-- [레퍼런스 핏] 메이플스타일 치명타/일반 컬러 완벽 구현!
					if isCrit then
						-- [치명타] 강렬한 핫핑크/레드 계열 + 화이트 외곽선!
						label.TextColor3 = Color3.fromRGB(255, 30, 80) 
						label.TextSize = 42 -- 더 과감하게 키움!
						label.Text = label.Text .. "!"
						stroke.Color = Color3.fromRGB(255, 255, 255) -- 흰색 외곽선
					else
						-- [일반 타격] 노란색/주황 계열 + 검은색 외곽선!
						label.TextColor3 = Color3.fromRGB(255, 215, 0) 
						label.TextSize = 28
						stroke.Color = Color3.fromRGB(0, 0, 0) -- 검정 외곽선
					end
					
					label.Parent = bb
					bb.Parent = targetHrp
					
					-- 부드럽게 위로 솟구치며 사라지는 트윈 애니메이션!
					local duration = isCrit and 1.2 or 0.8
					TweenService:Create(bb, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						StudsOffset = bb.StudsOffset + Vector3.new(0, 3.5, 0)
					}):Play()
					
					TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						TextTransparency = 1
					}):Play()
					
					TweenService:Create(stroke, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						Transparency = 1
					}):Play()
					
					task.delay(duration, function() bb:Destroy() end)


				end
			end)
		end
	end)
end

return AvatarController
