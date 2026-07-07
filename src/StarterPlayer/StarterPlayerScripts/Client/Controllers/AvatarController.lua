-- AvatarController.lua
-- 아바타 검술 RPG: 원소 속성 선택 UI, 실물 나무검(Accessory) 연계, 3단 연타 평타 콤보 및 타격 VFX 클라이언트 컨트롤러

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

-- [Convention Integration] 기존 인벤토리/스텟 시스템과 동일한 UI 테마 및 유틸리티 도입
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UITheme"))
local Utils = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIUtils"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local player = Players.LocalPlayer
local AvatarController = {}
local elementSelected = false

-- [버그수정] 스킬 이펙트(오버그로스 나무, 빙화검무 얼음기둥 등)의 바닥 높이 감지용 레이캐스트가
-- 시전자 캐릭터만 제외하고 있어서, 무작위로 흩뿌려지는 위치에 거대 몬스터(크라켄 등)가 서 있으면
-- 레이가 실제 바닥이 아니라 몬스터 몸통 표면에 맞아 그 높이에 이펙트가 붕 떠버리는 문제가 있었음.
-- workspace 최상위의 Humanoid 보유 모델(몬스터/다른 플레이어)을 전부 제외 목록에 추가해서 방지.
local function getGroundRayExcludes(char: Instance)
	local excludes = { char }
	for _, c in ipairs(workspace:GetChildren()) do
		if c ~= char and c:IsA("Model") and c:FindFirstChildOfClass("Humanoid") then
			table.insert(excludes, c)
		end
	end
	return excludes
end

-- 콤보 시스템 상태 제어용 프라이빗 변수군
local comboIndex = 1              -- 현재 공격 콤보 단계 (1 ➡️ 2 ➡️ 3)
local lastAttackTime = 0          -- 마지막 평타 시전 타임스탬프
local attackCooldown = false      -- 연타 쿨다운 가드
local activeAttackTrack = nil     -- 현재 재생 중인 평타 애니메이션 트랙 캐싱
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
	local rotationAdjustment = CFrame.new() -- 180도 강제 반대 출력 회전 제거 (0도로 원상복구)
	
	if vfx:IsA("Attachment") or vfx:IsA("ParticleEmitter") then
		local wrapper = Instance.new("Part")
		wrapper.Name = "VFX_Wrapper"
		wrapper.Transparency = 1
		wrapper.Anchored = true
		wrapper.CanCollide = false
		wrapper.CanQuery = false
		wrapper.CanTouch = false
		wrapper.Size = Vector3.new(0.1, 0.1, 0.1)
		vfx.Parent = wrapper
		vfx = wrapper
	elseif vfx:IsA("BasePart") then
		local hasEffectChildren = false
		for _, desc in ipairs(vfx:GetDescendants()) do
			if desc:IsA("ParticleEmitter") or desc:IsA("Attachment") then
				hasEffectChildren = true
				break
			end
		end
		if hasEffectChildren then
			vfx.Transparency = 1
		end
	end
	
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
		vfx.CFrame = cframe * rotationAdjustment
		-- 앞으로 뻗어나갈 때는 물리 엔진의 중력 낙하를 막기 위해 무조건 고정(Anchored) 처리
		vfx.Anchored = (parentPart == nil) or shouldTweenForward
		vfx.CanCollide = false
		vfx.CanQuery = false
		vfx.CanTouch = false
		
		-- 날아가는 투사체 형태가 아닐 때만 원래대로 캐릭터에 본드 고정(Weld)
		if parentPart and not shouldTweenForward then
			-- 템플릿 에셋이 스튜디오 상에서 가졌던 고유한 원래의 3D 회전 각도를 추출합니다.
			local originalRotation = template.CFrame.Rotation
			
			-- WeldConstraint 대신 클래식 Weld를 사용하여 물리 프레임 지연으로 인한 위치 오차를 완전히 차단합니다.
			local weld = Instance.new("Weld")
			weld.Part0 = parentPart
			weld.Part1 = vfx
			weld.C0 = CFrame.new(0, 0, -3.5) * originalRotation
			weld.C1 = CFrame.new()
			weld.Parent = vfx
		end
	elseif vfx:IsA("Model") then
		vfx:PivotTo(cframe * rotationAdjustment)
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
				vfx:PivotTo(cframe * rotationAdjustment)
			end)
		end
	end

	vfx.Parent = workspace

	-- 파티클의 즉각적인 생성을 보장하기 위해 첫 발을 강제로 Emit 합니다. (Delay 등의 속성 무시)
	for _, desc in ipairs(vfx:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			local emitCount = tonumber(desc:GetAttribute("EmitCount")) or 1
			
			-- [엔진 글로벌 렌더 싱크 버그 차단]
			-- 복제 즉시 원래 텍스처 ID를 캐싱하고 비워두어, 글로벌 텍스처 타이머 동기화를 강제로 끊습니다.
			local originalTexture = desc.Texture
			desc.Texture = ""
			
			task.spawn(function()
				task.wait()
				if desc and desc.Parent then
					-- 방출 직전 텍스처를 복원하여 무조건 1프레임부터 새롭게 재생을 개시하도록 강제합니다.
					desc.Texture = originalTexture
					pcall(function() desc:Emit(emitCount) end)
				end
			end)
		end
	end
	
	-- [디렉티브 반영] 2단계: 0.06초(약 4프레임) 간 몸체 자리에 확고한 앵커링을 통해 시각적 각인을 준 후 전방 고속 비행을 개시합니다.
	if shouldTweenForward then
		task.delay(0.06, function()
			if not vfx or not vfx.Parent then return end
			
			local targetCF = (cframe * CFrame.new(0, 0, -moveForwardDist)) * rotationAdjustment
			local tweenDur = math.min(lifetime * 0.65, 0.45) 
			local info = TweenInfo.new(tweenDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			
			if vfx:IsA("BasePart") then
				TweenService:Create(vfx, info, {CFrame = targetCF}):Play()
			elseif vfx:IsA("Model") then
				local cfProxy = Instance.new("CFrameValue")
				cfProxy.Value = cframe * rotationAdjustment
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
	return vfx
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
	title.Text = UILocalizer.Localize("아바타 아앙의 전설: 검술 RPG")
	title.TextColor3 = Color3.fromRGB(255, 240, 200)
	title.TextSize = 36
	title.Font = Enum.Font.SourceSansBold
	title.TextStrokeTransparency = 0.5
	title.BackgroundTransparency = 1
	title.Parent = mainFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0, 40)
	subtitle.Position = UDim2.new(0, 0, 0.23, 0)
	subtitle.Text = UILocalizer.Localize("숙명의 원소 속성을 선택하여 검의 지배자가 되십시오")
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
		local order = {Fire = 1, Water = 2, Dark = 3}
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
		nameLbl.Text = UILocalizer.Localize(el.name)
		nameLbl.TextColor3 = el.color
		nameLbl.TextSize = 20
		nameLbl.Font = Enum.Font.SourceSansBold
		nameLbl.BackgroundTransparency = 1
		nameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.85, 0, 0.4, 0)
		descLbl.Position = UDim2.new(0.5, 0, 0.45, 0)
		descLbl.AnchorPoint = Vector2.new(0.5, 0)
		descLbl.Text = UILocalizer.Localize(el.desc)
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
		masterTitle = UILocalizer.Localize("물의 스승")
		dialogueText = UILocalizer.Localize("“세상은 언제나 변한다.\n강한 자가 살아남는 것이 아니라, 흐름을 아는 자가 살아남는다.\n자, 선택하라. 너는 물처럼 변하고, 다시 일어설 수 있느냐?”")
	elseif element == "Fire" then
		masterTitle = UILocalizer.Localize("불의 스승")
		dialogueText = UILocalizer.Localize("“내 힘을 받는 순간, 너는 더 이상 뒤로 물러설 수 없다.\n적을 베고, 어둠을 태우고, 네 길을 스스로 밝혀라.\n자, 선택하라. 너의 심장은 불타고 있느냐?”")
	else
		masterTitle = UILocalizer.Localize("어둠의 스승")
		dialogueText = UILocalizer.Localize("“빛은 필연적으로 그림자를 드리운다.\n모두가 빛을 우러러볼 때, 어둠은 묵묵히 모든 것을 삼킨다.\n자, 선택하라. 너는 기꺼이 심연 속으로 걸어갈 수 있느냐?”")
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
		text = UILocalizer.Localize("예 (Choose)"),
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
		text = UILocalizer.Localize("아니오 (Cancel)"),
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

	-- Workspace 자식들 수집
	local targets = {}
	for _, obj in ipairs(workspace:GetChildren()) do
		table.insert(targets, obj)
	end
	
	-- 시작마을 허수아비 폴더 수집 추가
	local newWorldMap = workspace:FindFirstChild("NewWorldMap")
	local trainingFolder = newWorldMap and newWorldMap:FindFirstChild("Training")
	if trainingFolder then
		for _, obj in ipairs(trainingFolder:GetChildren()) do
			table.insert(targets, obj)
		end
	end

	-- 전체 대상에서 타격 대상 검색 고도화
	for _, obj in ipairs(targets) do
		-- 1. 자신은 제외
		if obj == char then continue end
		
		-- 2. 휴머노이드가 있는 생명체 모델만 대상
		if obj:IsA("Model") then
			local hum = obj:FindFirstChild("Humanoid")
			local targetHrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
			
			-- 3. 죽지 않았고, 다른 플레이어가 아닌 경우에만 몬스터/허수아비 타겟으로 인식!
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
	local equippedWeapon = player:GetAttribute("EquippedWeapon")
	if not equippedWeapon or equippedWeapon == "" then
		equippedWeapon = "NONE"
	end
	local weaponData = WeaponComboData[equippedWeapon]
	if not weaponData then return end

	-- 무기 장착 확인 (실물 3D Accessory 또는 어트리뷰트 감지)
	local hasStaff = (equippedWeapon == "NONE") or char:FindFirstChild(equippedWeapon) or player:GetAttribute("EquippedWeapon") == equippedWeapon
	if not hasStaff then return end

	attackCooldown = true
	local comboCooldown = weaponData.cooldown or 0.28
	
	-- [패시브 룬/스킬 버프]: 룬 슬롯에 '근성 룬(GRIT_RUNE)' 장착 또는 패시브 스킬 슬롯에 '근성' 장착 시 공격 쿨다운 5% 감소 (공속 5% 증가) 적용
	local hasGrit = false
	local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
	local equip = InventoryController.getEquipment()
	if equip then
		for _, runeSlot in ipairs({"RUNE1", "RUNE2", "RUNE3"}) do
			local eqItem = equip[runeSlot]
			if eqItem and eqItem.itemId == "GRIT_RUNE" then
				hasGrit = true
				break
			end
		end
	end
	if not hasGrit then
		local SkillController = require(script.Parent:WaitForChild("SkillController"))
		local equippedPassives = SkillController.getEquippedPassives()
		for _, skillId in pairs(equippedPassives) do
			if skillId == "SKILL_RUNE_GRIT" then
				hasGrit = true
				break
			end
		end
	end
	if hasGrit then
		comboCooldown = comboCooldown * 0.95
	end

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
	local defaultSwordAnim = "AttackSword_Swing_" .. comboIndex
	local animName = weaponData.animations[comboIndex] or defaultSwordAnim
	local targetAnim = staffAnimFolder and staffAnimFolder:FindFirstChild(animName)

	-- 이전 평타 애니메이션이 아직 진행 중이면 겹치지 않게 중단 처리
	if activeAttackTrack then
		pcall(function()
			activeAttackTrack:Stop(0.1)
		end)
		activeAttackTrack = nil
	end

	local playedAnim = false
	local currentAttackTrack = nil
	local animLength = 0.4
	
	if targetAnim and hum then
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local success, track = pcall(function() return animator:LoadAnimation(targetAnim) end)
		if success and track then
			playedAnim = true
			currentAttackTrack = track
			animLength = (track.Length > 0) and track.Length or 0.4
			activeAttackTrack = track
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

	-- [Sound] 기본 공격 Cast 사운드 재생 (애니메이션 시작과 동시 재생)
	local castSoundFolder = getCombatSoundFolder("Cast")
	if castSoundFolder then
		local soundName = string.format("Default_Attack_Cast_%d", comboIndex)
		local template = castSoundFolder:FindFirstChild(soundName)
		if template then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				playCombatSound(template, hrp)
			end
		end
	end

	-- [VFX] 기본 공격 Cast VFX 재생 (애니메이션 시작과 동시 재생)
	local castVFXFolder = getElementVFXFolder("Cast")
	local spawnedVFX = nil
	if castVFXFolder then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- [수정] 몸통 중심(0.2)에서 뻗은 무기 끝부분(-3.5)으로 출력 위치 전진
			local targetCFrame = hrp.CFrame * CFrame.new(0, 0, -3.5)
			local currentElement = player and player:GetAttribute("Element")
			local hasElement = currentElement and currentElement ~= "" and currentElement ~= "None"
			
			local elementTemplate = nil
			if hasElement then
				local vfxName = string.format("%s_Attack_Cast_%d", currentElement, comboIndex)
				elementTemplate = castVFXFolder:FindFirstChild(vfxName)
			end
			
			local targetTemplate = elementTemplate or castVFXFolder:FindFirstChild(string.format("Default_Attack_Cast_%d", comboIndex)) or castVFXFolder:FindFirstChild(string.format("Base_Attack_Cast_%d", comboIndex))
			if targetTemplate then
				-- 캐릭터 몸에 달라붙어 이동을 따라가도록 nil 대신 hrp를 넘겨 결속(Weld)시킵니다.
				spawnedVFX = spawnCombatVFX(targetTemplate, targetCFrame, 0.5, hrp, 1.0, 0)
			end
		end
	end

	-- [정확한 순서 동기화] 임의의 딜레이나 추정값을 사용하지 않고, 이벤트 기반으로 정확히 제어합니다.
	if currentAttackTrack then
		-- 1. 애니메이션 즉시 재생 및 속도 조절 (기획된 무기 쿨다운 내에 애니메이션이 완료되도록 재생 속도 조정)
		currentAttackTrack:Play()
		if animLength > 0 and comboCooldown > 0 then
			currentAttackTrack:AdjustSpeed(animLength / comboCooldown)
		end
		print(string.format("[AvatarController] Playing Combo %d Animation: %s (Speed: %.2f)", comboIndex, animName, animLength / comboCooldown))
		
		-- 2. 애니메이션 트랙이 끝날 때(종료) 즉시 파티클 방출을 중단(종료)하여 자연스럽게 잔상이 남고 사라지게 함
		currentAttackTrack.Stopped:Once(function()
			if spawnedVFX then
				for _, desc in ipairs(spawnedVFX:GetDescendants()) do
					if desc:IsA("ParticleEmitter") then
						desc.Enabled = false
					end
				end
				-- 기존에 방출된 파티클이 사라질 시간을 주고 완전히 파괴
				game:GetService("Debris"):AddItem(spawnedVFX, 1.0)
			end
		end)
	end

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

function AvatarController.attack()
	handleLMBAttack()
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
				local skillId = data.skillId
				local isMiss = data.isMiss == true

				if pos then
					local targetHrp = target and (target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart)
					if not data.hideVfx then
						if skillId then
							AvatarController.playSkillHit(skillId, pos, targetHrp)
						else
							-- 0. [디렉티브 반영] 기본 공격 다단히트 틱당 공용 어택 히트 VFX/사운드 시스템 동기화 재생
							if targetHrp then
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
							end
						end
					end

					-- 1. 플로팅 대미지 텍스트 생성 (Floating Damage Text) (허공 타격 시에는 텍스트 생략)
					if targetHrp and not isMiss and damage and damage > 0 then
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

				end
			end)
		end
	end)
end

--========================================
-- [Skill System 연동] 스킬 액션 시각화
--========================================

-- StumpKing 보스 낙하 패턴(MobSpawnService.playWoodSmashEffect)과 동일한 구조를 슬라임 버전으로 재구성
-- (파티클만 쓰지 않고, 실제 물리 파츠가 튕겨 날아가는 잔해를 함께 사용 - 돌 파편 대신 초록 슬라임 덩어리가 튀도록 재구성)
local function playRockSmashEffect(pos: Vector3, radius: number)
	local Debris = game:GetService("Debris")

	-- 1. 바닥에 남는 초록 슬라임 자국(크레이터) 링
	local crater = Instance.new("Part")
	crater.Name = "RockCrater"
	crater.Shape = Enum.PartType.Cylinder
	crater.Size = Vector3.new(0.2, radius * 1.5, radius * 1.5)
	crater.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	crater.Anchored = true
	crater.CanCollide = false
	crater.CastShadow = false
	crater.Material = Enum.Material.Neon
	crater.Color = Color3.fromRGB(90, 220, 90)
	crater.Parent = workspace
	TweenService:Create(crater, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
	Debris:AddItem(crater, 2.0)

	-- 2. 슬라임 덩어리 튀기기 (실제 물리 파츠, 구형태로 사방에 튕겨나갔다 사라짐)
	for _ = 1, 10 do
		local rock = Instance.new("Part")
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(1, 1, 1) * math.random(10, 20) / 10
		rock.Position = pos + Vector3.new(math.random(-2, 2), 1, math.random(-2, 2))
		rock.Material = Enum.Material.SmoothPlastic
		rock.Color = Color3.fromRGB(math.random(70, 130), math.random(200, 240), math.random(70, 130))
		rock.CanCollide = false
		rock.Anchored = false
		rock.Parent = workspace

		local angle = math.random() * math.pi * 2
		local speed = math.random(20, 40)
		rock.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * speed, math.random(25, 45), math.sin(angle) * speed)
		rock.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))

		TweenService:Create(rock, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
		Debris:AddItem(rock, 1.2)
	end

	-- 3. 튀는 초록 슬라임 물방울 안개
	local dustPart = Instance.new("Part")
	dustPart.Size = Vector3.new(1, 1, 1)
	dustPart.Position = pos
	dustPart.Anchored = true
	dustPart.CanCollide = false
	dustPart.Transparency = 1
	dustPart.Parent = workspace

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(140, 230, 120), Color3.fromRGB(80, 190, 90))
	dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0)})
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Lifetime = NumberRange.new(0.6, 1.0)
	dust.Rate = 60
	dust.Speed = NumberRange.new(6, 16)
	dust.SpreadAngle = Vector2.new(90, 90)
	dust.Parent = dustPart

	Debris:AddItem(dustPart, 2.0)
	task.delay(0.3, function() if dust then dust.Enabled = false end end)

	-- 4. 확산되는 초록 충격파 고리
	local shockwave = Instance.new("Part")
	shockwave.Name = "RockShockwave"
	shockwave.Shape = Enum.PartType.Cylinder
	shockwave.Size = Vector3.new(0.5, 1, 1)
	shockwave.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.CastShadow = false
	shockwave.Material = Enum.Material.Neon
	shockwave.Color = Color3.fromRGB(110, 230, 110)
	shockwave.Parent = workspace
	TweenService:Create(shockwave, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(shockwave, 0.5)
end

-- 오버그로스 버스트: 목표 지점에 마법진(회전하는 이중 링)이 그려진 뒤,
-- 그 안에서 나무 3그루가 대각선으로 기울어진 채 솟아올라 공격하고 다시 가라앉음
local function playOvergrowthBurstEffect(hrp: BasePart, targetCFrame: CFrame, char: Instance)
	local Debris = game:GetService("Debris")

	local aimDir = targetCFrame.LookVector
	local flatAimDir = Vector3.new(aimDir.X, 0, aimDir.Z)
	if flatAimDir.Magnitude < 0.01 then flatAimDir = Vector3.new(0, 0, -1) else flatAimDir = flatAimDir.Unit end
	local castDistance = 15 -- SkillService.lua의 OVERGROWTH hitPos 거리(15)와 동일하게 맞춤
	local xzTarget = Vector3.new(hrp.Position.X, hrp.Position.Y, hrp.Position.Z) + flatAimDir * castDistance

	-- 실제 바닥 높이 레이캐스트 (슬라임샷과 동일한 방식)
	-- [수정] 경사/단차/구덩이 등 굴곡진 지형에서도 바닥을 놓치지 않도록 탐색 범위를 넉넉하게 확장 (+20~-60 -> +50~-150)
	local groundY = hrp.Position.Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = getGroundRayExcludes(char)
	local rayResult = workspace:Raycast(xzTarget + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
	if rayResult then
		groundY = rayResult.Position.Y
	end
	local groundPos = Vector3.new(xzTarget.X, groundY, xzTarget.Z)

	local circleRadius = 11 -- SkillService.lua의 OVERGROWTH 판정 반경(11)과 동일

	-- 1. 마법진 (이중 링, 서로 반대로 회전)
	local circleModel = Instance.new("Model")
	circleModel.Name = "OvergrowthCircle"

	local function makeRing(sizeMult, thickness, color)
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(thickness, circleRadius * 2 * sizeMult, circleRadius * 2 * sizeMult)
		ring.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 1
		ring.Parent = circleModel
		return ring
	end

	local outerRing = makeRing(1.0, 0.15, Color3.fromRGB(80, 200, 90))
	local innerRing = makeRing(0.65, 0.12, Color3.fromRGB(140, 230, 120))
	circleModel.Parent = workspace

	TweenService:Create(outerRing, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.3}):Play()
	TweenService:Create(innerRing, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.45}):Play()

	-- 회전 연출 (서로 반대 방향)
	local spinning = true
	task.spawn(function()
		local angle1, angle2 = 0, 0
		while spinning and outerRing.Parent do
			angle1 += 90 * (1 / 30)
			angle2 -= 130 * (1 / 30)
			outerRing.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, math.rad(angle1), math.rad(90))
			innerRing.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, math.rad(angle2), math.rad(90))
			task.wait(1 / 30)
		end
	end)

	-- 2. 텔레그래프 대기 (서버 데미지 판정 시작 시점인 0.25s와 맞춤)
	task.wait(0.3)

	-- 3. 나무 3그루가 마법진 안에서 대각선으로 솟아오름 (0.15초 간격 - 서버 히트 간격과 동일)
	for i = 1, 3 do
		task.spawn(function(treeIndex)
			local angle = math.rad(90 + (treeIndex - 1) * 120)
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (circleRadius * 0.45)
			local basePos = groundPos + offset

			-- [수정] 마법진 중심의 바닥 높이를 그대로 재사용하면 경사지/단차가 있는 지형에서
			-- 나무가 뜨거나 파묻히므로, 각 나무가 실제로 서는 위치에서 다시 개별 레이캐스트해 보정
			local treeRayParams = RaycastParams.new()
			treeRayParams.FilterType = Enum.RaycastFilterType.Exclude
			treeRayParams.FilterDescendantsInstances = getGroundRayExcludes(char)
			local treeRayResult = workspace:Raycast(basePos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), treeRayParams)
			if treeRayResult then
				basePos = Vector3.new(basePos.X, treeRayResult.Position.Y, basePos.Z)
			end

			local leanAngle = math.rad(22) -- 대각선으로 삐쳐 나오는 기울기
			local spinDir = (treeIndex % 2 == 0) and 1 or -1
			local baseCFrame = CFrame.new(basePos) * CFrame.Angles(0, angle * spinDir, 0) * CFrame.Angles(leanAngle, 0, 0)

			local tree = Instance.new("Model")
			tree.Name = "OvergrowthTree"

			-- [고도화 v3] 이 게임 맵에 이미 있는 실제 나무(Workspace...BorderTrees.Tree: Trunk Block + Crown Block들)와
			-- 동일한 스타일로 제작 - 갈색 각진 몸통 + 초록 뭉치 잎사귀들로 구성된 "진짜 나무" 형태
			local trunkHeight = 20
			local trunkWidth = 3.6
			local barkColor = Color3.fromRGB(75, 50, 28)
			local leafColor = Color3.fromRGB(58, 108, 42)

			local trunk = Instance.new("Part")
			trunk.Name = "Trunk"
			trunk.Shape = Enum.PartType.Block
			trunk.Size = Vector3.new(trunkWidth, 0.1, trunkWidth)
			trunk.Material = Enum.Material.Wood
			trunk.Color = barkColor
			trunk.Anchored = true
			trunk.CanCollide = false
			trunk.CanQuery = false
			trunk.CanTouch = false
			trunk.CastShadow = true
			trunk.Parent = tree

			-- 잎사귀 뭉치 (Crown) 3덩어리를 나무 꼭대기에 살짝 겹치게 배치해 풍성한 수관을 표현
			local crownDefs = {
				{ size = 13, offset = Vector3.new(0, 0, 0) },
				{ size = 10, offset = Vector3.new(2.6, 1.6, 1.2) },
				{ size = 10, offset = Vector3.new(-2.2, -1.2, 1.8) },
			}
			local crowns = {}
			for ci, def in ipairs(crownDefs) do
				local crown = Instance.new("Part")
				crown.Name = "Crown" .. ci
				crown.Shape = Enum.PartType.Block
				crown.Size = Vector3.new(0.1, 0.1, 0.1)
				crown.Material = Enum.Material.Grass
				crown.Color = leafColor
				crown.Anchored = true
				crown.CanCollide = false
				crown.CanQuery = false
				crown.CanTouch = false
				crown.CastShadow = true
				crown.Parent = tree
				crowns[ci] = crown
			end

			-- [중요] baseCFrame의 로컬 Y축(기울어진 방향)을 따라 절반 높이만큼 이동시켜 몸통을 배치
			local function poseAt(growT: number)
				local curHeight = trunkHeight * growT
				trunk.CFrame = baseCFrame * CFrame.new(0, curHeight / 2, 0)
				trunk.Size = Vector3.new(trunkWidth, math.max(curHeight, 0.05), trunkWidth)

				-- 잎사귀 뭉치들은 몸통 꼭대기 부근에 뭉쳐서 성장과 함께 같이 부풀어오름
				for ci, def in ipairs(crownDefs) do
					local crown = crowns[ci]
					crown.CFrame = baseCFrame * CFrame.new(def.offset * growT + Vector3.new(0, curHeight, 0))
					crown.Size = Vector3.new(1, 1, 1) * (def.size * growT)
				end
			end

			poseAt(0.02)
			tree.Parent = workspace

			-- 성장(=찌르기) 트윈: 부드럽게 자라는 느낌이 아니라, 순식간에 솟구쳐 찌르는 느낌으로 매우 빠르게 처리
			local growValue = Instance.new("NumberValue")
			growValue.Value = 0.02
			growValue.Changed:Connect(function(v)
				if trunk.Parent then poseAt(v) end
			end)
			local growTween = TweenService:Create(growValue, TweenInfo.new(0.12, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Value = 1})
			growTween:Play()

			growTween.Completed:Once(function()
				task.wait(0.45) -- 잠시 유지 (공격 판정 시간)
				local shrinkTween = TweenService:Create(growValue, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Value = 0})
				shrinkTween:Play()
				shrinkTween.Completed:Once(function()
					growValue:Destroy()
					tree:Destroy()
				end)
			end)

			Debris:AddItem(tree, 3.0)
		end, i)

		task.wait(0.15) -- 서버 히트 간격(0.15초)과 동일하게 순차적으로 솟아오름
	end

	-- 4. 마법진 정리
	spinning = false
	TweenService:Create(outerRing, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
	TweenService:Create(innerRing, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
	Debris:AddItem(circleModel, 0.6)
end

-- 매화낙락: 캐릭터 주위에 벚꽃 잎이 휘날리고, 분홍빛 검기가 사방으로 뻗어나가는 광역 슬래시
-- [고도화] 직접 만든 Part/Beam 대신, 맵에 이미 있는 실제 에셋을 활용:
--   - 벚꽃 잎: SamuraiZone의 "Cherry Blossom M" 나무에 쓰이는 진짜 벚꽃잎 텍스처(rbxassetid://243160943)
--   - 검기 슬래시: SLASH_Cast에서 쓰는 진짜 참격 텍스처(rbxassetid://13805841956, Flipbook 애니메이션)
local function playMaehwaEffect(hrp: BasePart)
	local Debris = game:GetService("Debris")
	local slashColor = Color3.fromRGB(255, 130, 190)

	-- [수정] 실제 서버 판정 반경(SkillService.lua의 MAEHWA radius=18)과 정확히 맞춰서
	-- "보이는 범위"와 "맞는 범위"가 일치하도록 함
	local AOE_RADIUS = 18

	-- 캐릭터를 따라다니는 앵커 파트 (짧은 지속시간 동안만 위치 갱신)
	-- [수정] 꽃잎이 한 점에서 날아가 퍼지는 게 아니라 판정 범위 전체(지름 AOE_RADIUS*2)에 걸쳐
	-- 곧바로 분포되도록, 크기가 있는 구(Sphere) 볼륨으로 만듦
	local anchor = Instance.new("Part")
	anchor.Name = "MaehwaAnchor"
	anchor.Size = Vector3.new(AOE_RADIUS * 2, AOE_RADIUS * 2, AOE_RADIUS * 2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	-- [수정] 서버의 실제 판정 중심(SkillService.lua hitPos = hrp.Position + look*3)과 정확히 일치시킴
	-- 기존엔 hrp.CFrame(플레이어 위치 자체)을 중심으로 그려서 판정 중심과 3스터드 어긋나 있었음
	anchor.CFrame = hrp.CFrame + hrp.CFrame.LookVector * 3
	anchor.Parent = workspace

	-- 1. 벚꽃 잎 파티클 - 실제 벚꽃나무 에셋과 동일한 텍스처 사용, 판정 범위 전체에 걸쳐 훨씬 넓고 풍성하게
	local petals = Instance.new("ParticleEmitter")
	petals.Texture = "rbxassetid://243160943" -- 실제 Cherry Blossom M 나무의 꽃잎 텍스처
	petals.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)) -- 텍스처 자체에 색이 있어 흰색 통과가 자연스러움
	-- [수정] 파트 크기(AOE_RADIUS*2)를 볼륨으로 사용해 판정 범위 전체에 즉시 분포되도록 함
	petals.Shape = Enum.ParticleEmitterShape.Sphere
	petals.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	petals.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	petals.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(0.7, 1.3),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	petals.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.8, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	petals.Lifetime = NumberRange.new(1.2, 2.0)
	petals.Rate = 0
	petals.Speed = NumberRange.new(6, 16) -- 이미 넓게 분포되므로 추가 이동 속도는 줄임
	petals.SpreadAngle = Vector2.new(180, 180)
	petals.RotSpeed = NumberRange.new(-200, 200)
	petals.Rotation = NumberRange.new(0, 360)
	petals.Drag = 1.5
	petals.Acceleration = Vector3.new(0, -10, 0)
	petals.Orientation = Enum.ParticleOrientation.FacingCamera
	petals.Parent = anchor
	petals:Emit(220) -- [수정] 140 -> 220: 넓어진 범위를 꽉 채우도록 증량

	-- 2. 분홍 검기 - Assets/VFX/Slash 파트(전용 제작 에셋)를 여러 개 복제해 판정 범위(AOE_RADIUS) 안에만 흩뿌림
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets")
	vfxFolder = vfxFolder and vfxFolder:FindFirstChild("VFX")
	local slashTemplate = vfxFolder and vfxFolder:FindFirstChild("Slash")
	if not slashTemplate then
		warn("[MaehwaEffect] Assets/VFX/Slash 파트를 찾을 수 없습니다.")
	end

	local slashCount = 56

	for i = 1, slashCount do
		-- 슬래시 위치: 판정 범위(AOE_RADIUS) 안에서만 무작위 위치 - 판정 범위 밖에서 이펙트가 보이지 않도록
		local posTheta = math.random() * math.pi * 2
		local posPhi = math.acos(2 * math.random() - 1)
		local posDir = Vector3.new(math.sin(posPhi) * math.cos(posTheta), math.cos(posPhi), math.sin(posPhi) * math.sin(posTheta))
		local posDist = math.random(2, AOE_RADIUS) -- 실제 판정 반경과 일치
		local slashPos = anchor.Position + posDir * posDist

		-- 각 슬래시가 완전히 무작위 시점에(0~0.8초 사이) 따로따로 나타나도록 - "순서도 불규칙"
		local appearDelay = math.random() * 0.8

		task.delay(appearDelay, function()
			if not anchor.Parent or not slashTemplate then return end

			local slash = slashTemplate:Clone()
			slash.Name = "MaehwaSlashMark"
			slash.Anchored = true
			slash.CanCollide = false
			slash.CanQuery = false
			slash.CanTouch = false
			slash.CastShadow = false
			-- 원본 파트는 Transparency=1인 투명 앵커라서 그대로 유지 (보이는 건 안의 파티클)

			-- 완전히 무작위 회전 + 크기 다양화(2.0~3.6배, 더 크게)를 줘서 슬래시가 다양한 각도/크기로 찍힌 것처럼 보이게 함
			local scale = math.random(20, 36) / 10
			slash.CFrame = CFrame.new(slashPos)
				* CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
			slash.Parent = workspace
			Debris:AddItem(slash, 1.5)

			-- 파티클(SlashImpact1 등)을 한 번씩 발사 (색은 이미 분홍이라 그대로 사용, 크기만 키움)
			-- [중요] 이 파티클은 Orientation = VelocityPerpendicular라서 실제 "속도" 벡터 방향을 기준으로
			-- 슬래시 각도가 정해짐. 원본 Speed가 0.001로 사실상 0이라 파트를 아무리 랜덤 회전시켜도
			-- 항상 같은(가로) 방향으로만 보였던 것 -- 그래서 Speed를 실질적인 값으로 줘야 파트의
			-- 랜덤 회전(Attachment Front 방향)이 실제 슬래시 각도에 반영된다.
			for _, desc in ipairs(slash:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then
					local nsSeq = {}
					for _, kp in ipairs(desc.Size.Keypoints) do
						table.insert(nsSeq, NumberSequenceKeypoint.new(kp.Time, kp.Value * scale, kp.Envelope * scale))
					end
					desc.Size = NumberSequence.new(nsSeq)
					local spd = math.random(6, 14)
					desc.Speed = NumberRange.new(spd, spd)
					desc.Rate = 0
					desc:Emit(1)
				end
			end
		end)
	end

	Debris:AddItem(anchor, 2.2)
end

-- 빙화검무: 매화낙락과 동일한 구조(자기중심 광역기, 판정반경 18)를 얼음 테마로 재구성.
-- 눈보라(스노우) + 서릿빛 검기(매화낙락과 같은 Slash 파트 재사용, 색만 얼음톤) + 땅에서 엇갈려 솟는 얼음 기둥.
local function playIceBladeEffect(hrp: BasePart, char: Instance)
	local Debris = game:GetService("Debris")
	local iceColor = Color3.fromRGB(200, 235, 255) -- [수정] 더 연한 하늘색으로

	-- [수정] 서버의 실제 판정 반경(SkillService.lua의 ICEBLADE radius=18)과 정확히 맞춤
	local AOE_RADIUS = 18

	local anchor = Instance.new("Part")
	anchor.Name = "IceBladeAnchor"
	anchor.Size = Vector3.new(AOE_RADIUS * 2, AOE_RADIUS * 2, AOE_RADIUS * 2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	-- 서버의 실제 판정 중심(hitPos = hrp.Position + look*8)과 정확히 일치시킴
	-- 매화낙락(제자리 중심)과 달리, 빙화검무는 플레이어 살짝 앞에서 이펙트가 시작되도록 함
	anchor.CFrame = hrp.CFrame + hrp.CFrame.LookVector * 8
	anchor.Parent = workspace

	-- 1. 눈보라 파티클 - 판정 범위 전체에 걸쳐 흩날리는 눈송이 (텍스처 없는 기본 원형 파티클을 아주 연한 하늘색으로)
	local snow = Instance.new("ParticleEmitter")
	snow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, iceColor),
	})
	snow.Shape = Enum.ParticleEmitterShape.Sphere
	snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	snow.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Lifetime = NumberRange.new(1.6, 2.8) -- [수정] 눈보라처럼 좀 더 오래 흩날리도록 연장
	snow.Rate = 0
	-- [수정] 눈보라 느낌으로 옆바람에 휘날리듯 속도/스프레드를 키움
	snow.Speed = NumberRange.new(8, 20)
	snow.SpreadAngle = Vector2.new(180, 180)
	snow.RotSpeed = NumberRange.new(-180, 180)
	snow.Rotation = NumberRange.new(0, 360)
	snow.Drag = 1.2
	snow.Acceleration = Vector3.new(0, -4, 0)
	snow.Orientation = Enum.ParticleOrientation.FacingCamera
	snow.Parent = anchor
	snow:Emit(260)

	-- 1-1. 옆바람에 흩날리는 눈보라 느낌을 강화하기 위해 랜덤한 수평 방향으로 추가 돌풍(윈드 버스트)을 여러 번 발사
	task.spawn(function()
		for i = 1, 5 do
			if not anchor.Parent then return end
			local windAngle = math.random() * math.pi * 2
			local windDir = Vector3.new(math.cos(windAngle), 0.15, math.sin(windAngle))
			snow.Acceleration = windDir * math.random(6, 14)
			snow:Emit(40)
			task.wait(0.15)
		end
	end)

	-- 1-2. 아주 연한 안개/연기 - 느리고 부드럽게 소용돌이치듯 감도는 연출
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.fromRGB(225, 245, 255))
	mist.Shape = Enum.ParticleEmitterShape.Sphere
	mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	mist.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(0.5, 7),
		NumberSequenceKeypoint.new(1, 10),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85), -- 아주 연하게
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(2.0, 3.2)
	mist.Rate = 0
	mist.Speed = NumberRange.new(1, 3) -- 연기처럼 아주 느리게 퍼짐
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.RotSpeed = NumberRange.new(-15, 15)
	mist.Drag = 0.5
	mist.Acceleration = Vector3.new(0, 1.5, 0) -- 연기처럼 살짝 위로 감돌아 올라감
	mist.Orientation = Enum.ParticleOrientation.FacingCamera
	mist.Parent = anchor
	mist:Emit(30)

	-- 2. 서릿빛 검기 - 매화낙락과 동일한 Slash 파트 재사용, 색만 얼음톤으로
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets")
	vfxFolder = vfxFolder and vfxFolder:FindFirstChild("VFX")
	local slashTemplate = vfxFolder and vfxFolder:FindFirstChild("Slash")
	if not slashTemplate then
		warn("[IceBladeEffect] Assets/VFX/Slash 파트를 찾을 수 없습니다.")
	end

	local slashCount = 18 -- [수정] 매화낙락(56)보다 검기 개수를 훨씬 적게
	for i = 1, slashCount do
		local posTheta = math.random() * math.pi * 2
		local posPhi = math.acos(2 * math.random() - 1)
		local posDir = Vector3.new(math.sin(posPhi) * math.cos(posTheta), math.cos(posPhi), math.sin(posPhi) * math.sin(posTheta))
		local posDist = math.random(2, AOE_RADIUS)
		local slashPos = anchor.Position + posDir * posDist
		local appearDelay = math.random() * 0.8

		task.delay(appearDelay, function()
			if not anchor.Parent or not slashTemplate then return end

			local slash = slashTemplate:Clone()
			slash.Name = "IceBladeSlashMark"
			slash.Anchored = true
			slash.CanCollide = false
			slash.CanQuery = false
			slash.CanTouch = false
			slash.CastShadow = false

			local scale = math.random(20, 36) / 10
			slash.CFrame = CFrame.new(slashPos)
				* CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
			slash.Parent = workspace
			Debris:AddItem(slash, 1.5)

			for _, desc in ipairs(slash:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then
					desc.Color = ColorSequence.new(iceColor)
					local nsSeq = {}
					for _, kp in ipairs(desc.Size.Keypoints) do
						table.insert(nsSeq, NumberSequenceKeypoint.new(kp.Time, kp.Value * scale, kp.Envelope * scale))
					end
					desc.Size = NumberSequence.new(nsSeq)
					local spd = math.random(6, 14)
					desc.Speed = NumberRange.new(spd, spd)
					desc.Rate = 0
					desc:Emit(1)
				end
			end
		end)
	end

	-- 3. 얼음 기둥 - Assets/VFX/Shockwave 메쉬파트(전용 제작 에셋)를 재사용.
	-- 일자로 규칙적으로 나오는 게 아니라, 판정 범위 안 아무 곳에나 대각선으로 기울어진 채
	-- 불규칙한 타이밍(파바바박)으로 여기저기서 솟아오르도록 구성.
	local pillarTemplate = vfxFolder and vfxFolder:FindFirstChild("Shockwave")
	if not pillarTemplate then
		warn("[IceBladeEffect] Assets/VFX/Shockwave 파트를 찾을 수 없습니다.")
	end

	if pillarTemplate then
		local pillarCount = 10
		for i = 1, pillarCount do
			-- 완전히 무작위 위치(검기와 동일한 방식으로 판정 범위 안 아무 곳이나) + 무작위 시점에 튀어나옴
			local posTheta = math.random() * math.pi * 2
			local posDist = math.random(2, AOE_RADIUS)
			local offset = Vector3.new(math.cos(posTheta), 0, math.sin(posTheta)) * posDist
			local basePos = anchor.Position + offset

			-- "파바바박" 느낌: 일정 간격이 아니라 짧은 시간 안에 뭉쳐서 불규칙하게 튀어나오도록
			local appearDelay = math.random() * 0.5

			task.delay(appearDelay, function()
				if not anchor.Parent then return end

				-- 각 기둥 위치에서 개별 레이캐스트로 바닥 높이 보정 (굴곡진 지형 대응)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = getGroundRayExcludes(char)
				local rayResult = workspace:Raycast(basePos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
				if rayResult then
					basePos = Vector3.new(basePos.X, rayResult.Position.Y, basePos.Z)
				end

				-- 대각선으로 삐딱하게 솟아오르도록 기울기 + 무작위 방위각을 줌 (일자로 반듯하게 X)
				local yaw = math.random() * math.pi * 2
				local leanAngle = math.rad(math.random(12, 32)) * (math.random() < 0.5 and 1 or -1)
				local leanAxisAngle = math.random() * math.pi * 2
				local baseCFrame = CFrame.new(basePos)
					* CFrame.Angles(0, yaw, 0)
					* CFrame.Angles(0, 0, leanAxisAngle) -- 기울어지는 방향을 무작위로 회전
					* CFrame.Angles(leanAngle, 0, 0) -- 대각선 기울기
					* CFrame.Angles(0, 0, -leanAxisAngle) -- 원래 방위로 복귀 (기울기 방향만 무작위였던 것 유지)

				local scale = math.random(6, 13) / 10 -- 크기도 제각각으로

				local pillar = pillarTemplate:Clone()
				pillar.Name = "IceBladePillar"
				pillar.Anchored = true
				pillar.CanCollide = false
				pillar.CanQuery = false
				pillar.CanTouch = false
				pillar.Parent = workspace
				Debris:AddItem(pillar, 3.0)

				local fullSize = pillarTemplate.Size * scale
				local fullHeight = fullSize.Y

				-- 아래에서 솟아오르는 느낌: Y축 크기를 0에서 실제 크기까지 빠르게 키움
				local function poseAt(growT: number)
					local curHeight = math.max(fullHeight * growT, 0.05)
					pillar.Size = Vector3.new(fullSize.X, curHeight, fullSize.Z)
					-- 메쉬 원점이 중심이라, 바닥에 발이 붙어있도록 커지는 만큼 위로 올려줌
					pillar.CFrame = baseCFrame * CFrame.new(0, curHeight / 2, 0)
				end

				poseAt(0.02)

				local growValue = Instance.new("NumberValue")
				growValue.Value = 0.02
				growValue.Changed:Connect(function(v)
					if pillar.Parent then poseAt(v) end
				end)
				local growTween = TweenService:Create(growValue, TweenInfo.new(0.12, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Value = 1})
				growTween:Play()

				growTween.Completed:Once(function()
					task.wait(0.45)
					local shrinkTween = TweenService:Create(growValue, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Value = 0})
					shrinkTween:Play()
					shrinkTween.Completed:Once(function()
						growValue:Destroy()
						pillar:Destroy()
					end)
				end)
			end)
		end
	end

	Debris:AddItem(anchor, 2.2)
end

function AvatarController.playSkillCast(itemId: string, hrp: BasePart, targetCFrame: CFrame)
	local char = hrp.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local itemData = DataHelper.GetData("ItemData", itemId)
	local isAuraRune = itemData and itemData.runeMode == "AURA"
	
	-- itemId 매핑 (예: SKILL_EMBER -> EMBER, SKILL_DROPLET -> DROPLET, SKILL_ROCK -> NIGHT)
	local assetKey = string.gsub(itemId, "^SKILL_", "")
	if assetKey == "ROCK" then
		assetKey = "NIGHT"
	end
	
	-- 1. 로컬 애니메이션 재생 (Assets/Animations/Weapons/Skill/<itemId>_Cast)
	if hum and not isAuraRune then
		local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
		local animationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
		local weaponsAnimFolder = animationsFolder and animationsFolder:FindFirstChild("Weapons")
		local skillAnimFolder = weaponsAnimFolder and weaponsAnimFolder:FindFirstChild("Skill")
		
		local targetAnim = skillAnimFolder and skillAnimFolder:FindFirstChild(assetKey .. "_Cast")
		if not targetAnim and assetKey == "SLASH" then
			targetAnim = skillAnimFolder and (skillAnimFolder:FindFirstChild("EMBER_Cast") or skillAnimFolder:FindFirstChild("DROPLET_Cast") or skillAnimFolder:FindFirstChild("NIGHT_Cast"))
		end
		if targetAnim then
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
			local track = animator:LoadAnimation(targetAnim)
			track:Play()
		else
			warn(string.format("[ANIM INFO] '%s_Cast' not found in Assets.Animations.Weapons.Skill", assetKey))
		end
	end

	-- 2. Cast Sound 재생 (Assets/Sounds/Cast/<itemId>_Cast)
	if not isAuraRune then
		local castSoundFolder = getCombatSoundFolder("Cast")
		if castSoundFolder then
			local soundTemplate = castSoundFolder:FindFirstChild(assetKey .. "_Cast")
			if not soundTemplate and assetKey == "SLASH" then
				soundTemplate = castSoundFolder:FindFirstChild("Default_Attack_Cast_1") or castSoundFolder:FindFirstChild("Base_Attack_Cast_1")
			end
			if soundTemplate then
				playCombatSound(soundTemplate, hrp)
			else
				warn(string.format("[SOUND INFO] '%s_Cast' not found in Assets.Sounds.Cast", assetKey))
			end
		end
	end

	-- 3. Cast VFX 재생 (Assets/VFX/Cast/<itemId>_Cast)
	if assetKey == "OVERGROWTH" then
		-- 오버그로스 버스트: 목표 지점에 마법진이 그려지고, 그 위에서 나무 3그루가 대각선으로 솟아올라 공격
		-- [주의] 내부적으로 task.wait를 여러 번 사용하므로, 호출부(서버 요청 등)를 막지 않도록 반드시 task.spawn으로 감싼다
		task.spawn(playOvergrowthBurstEffect, hrp, targetCFrame, char)
	elseif assetKey == "MAEHWA" then
		-- 매화낙락: 캐릭터 주위로 벚꽃 잎 + 분홍 검기가 사방으로 퍼지는 광역기 (조준 방향과 무관하게 자기 중심)
		task.spawn(playMaehwaEffect, hrp)
	elseif assetKey == "ICEBLADE" then
		-- 빙화검무: 캐릭터 주위로 눈보라 + 서릿빛 검기 + 땅에서 엇갈려 솟는 얼음 기둥 (자기 중심 광역기)
		task.spawn(playIceBladeEffect, hrp, char)
	elseif not isAuraRune then
		local castVFXFolder = getElementVFXFolder("Cast")
		if castVFXFolder then
			local vfxTemplate = castVFXFolder:FindFirstChild(assetKey .. "_Cast")
			if not vfxTemplate and assetKey == "SLASH" then
				vfxTemplate = castVFXFolder:FindFirstChild("Default_Attack_Cast_1") or castVFXFolder:FindFirstChild("Base_Attack_Cast_1")
			end
			if vfxTemplate and assetKey == "SLIMESHOT" then
				-- 슬라임샷(개편): 목표 지점 위에서 커다란 슬라임을 소환해 떨어뜨리고,
				-- 착지하면 돌 깨지는 이펙트(SLIMESHOT_Hit)와 함께 슬라임이 사라짐
				local aimDir = targetCFrame.LookVector
				local flatAimDir = Vector3.new(aimDir.X, 0, aimDir.Z)
				if flatAimDir.Magnitude < 0.01 then flatAimDir = Vector3.new(0, 0, -1) else flatAimDir = flatAimDir.Unit end
				local dropDistance = 12 -- SkillService.lua의 SLIMESHOT hitPos 거리(12)와 동일하게 맞춤
				local xzTarget = Vector3.new(hrp.Position.X, hrp.Position.Y, hrp.Position.Z) + flatAimDir * dropDistance

				-- [수정] hrp.Position.Y(허리 높이)를 그대로 쓰면 장판/착지 지점이 실제 지면보다 떠버리므로,
				-- 목표 지점 위에서 아래로 레이캐스트해 실제 바닥 높이를 구함
				local groundY = hrp.Position.Y
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = getGroundRayExcludes(char)
				-- [수정] 다른 스킬들과 동일하게 탐색 범위 확장 (+20~-60 -> +50~-150): 단차 큰 지형에서도 놓치지 않도록
				local rayResult = workspace:Raycast(xzTarget + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
				if rayResult then
					groundY = rayResult.Position.Y
				end
				local landPos = Vector3.new(xzTarget.X, groundY, xzTarget.Z)
				local dropHeight = 22
				local fallDuration = 1.0 -- [수정] 0.4 -> 1.0: 더 천천히 떨어지도록

				local bigSlime = vfxTemplate:Clone()
				bigSlime.Name = "SLIMESHOT_Cast"
				for _, d in ipairs(bigSlime:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				bigSlime:PivotTo(CFrame.new(landPos + Vector3.new(0, dropHeight, 0)))
				bigSlime.Parent = workspace

				local cfProxy = Instance.new("CFrameValue")
				cfProxy.Value = bigSlime:GetPivot()
				local fallConn
				fallConn = cfProxy.Changed:Connect(function(val)
					if bigSlime and bigSlime.Parent then
						bigSlime:PivotTo(val)
					end
				end)
				local fallTween = TweenService:Create(cfProxy, TweenInfo.new(fallDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Value = CFrame.new(landPos),
				})
				fallTween:Play()
				fallTween.Completed:Once(function()
					fallConn:Disconnect()
					cfProxy:Destroy()

					playRockSmashEffect(landPos, 9) -- 9 = SkillService.lua의 SLIMESHOT 폭발 반경과 동일
					if bigSlime and bigSlime.Parent then
						bigSlime:Destroy()
					end
				end)
			elseif vfxTemplate then
				local scale = 1.0
				local moveDist = 20.0

				-- 불씨(EMBER), 물방울(DROPLET), 짙은밤(NIGHT/ROCK), 슬래시(SLASH): 원거리에 즉시 착탄하는 연출이라 비행 없이 목표 지점에 바로 표시
				if assetKey == "EMBER" or assetKey == "DROPLET" or assetKey == "NIGHT" or assetKey == "SLASH" then
					scale = 2.5
					moveDist = nil -- 투사체 비행 제외
				end

				local spawned = spawnCombatVFX(vfxTemplate, targetCFrame, 2.0, hrp, scale, moveDist)
				if spawned then
					task.delay(0.25, function()
						if spawned and spawned.Parent then
							for _, desc in ipairs(spawned:GetDescendants()) do
								if desc:IsA("ParticleEmitter") then
									desc.Enabled = false
								end
							end
						end
					end)
				end
			else
				warn(string.format("[VFX INFO] '%s_Cast' not found in Assets.VFX.Cast", assetKey))
			end
		end
	end
end

function AvatarController.playSkillHit(itemId: string, pos: Vector3, targetHrp: BasePart?)
	local itemData = DataHelper.GetData("ItemData", itemId)
	local isAuraRune = itemData and itemData.runeMode == "AURA"
	local auraHitVfxName = itemData and itemData.auraHitVfxName

	-- itemId 매핑 (예: SKILL_EMBER -> EMBER, SKILL_DROPLET -> DROPLET, SKILL_ROCK -> NIGHT)
	local assetKey = string.gsub(itemId, "^SKILL_", "")
	if assetKey == "ROCK" then
		assetKey = "NIGHT"
	end

	-- 슬라임샷은 낙하 착지 시(playSkillCast) playRockSmashEffect로 이미 터지는 연출을 전부 처리하므로
	-- 서버 명중 확인 시 또 여기서 재생하면 같은 자리에 이펙트가 중복으로 보임 -> 여기서는 스킵
	if assetKey == "SLIMESHOT" then
		return
	end

	-- 1. 공용 Hit Sound 재생 (룬이든 평타든 모두 동일하게)
	local hitSoundFolder = getCombatSoundFolder("Hit")
	if hitSoundFolder then
		local soundTemplate
		if isAuraRune then
			soundTemplate = hitSoundFolder:FindFirstChild("Default_Attack_Hit")
		else
			soundTemplate = hitSoundFolder:FindFirstChild(assetKey .. "_Hit")
				or hitSoundFolder:FindFirstChild("Default_Attack_Hit")
				or hitSoundFolder:FindFirstChild("Base_Attack_Hit")
		end
		if soundTemplate and targetHrp then
			playCombatSound(soundTemplate, targetHrp)
		else
			if not soundTemplate then
				warn("[SOUND INFO] 'Default_Attack_Hit' not found in Assets.Sounds.Hit")
			end
		end
	end

	-- 2. Hit VFX 재생 (Assets/VFX/Hit/<itemId>_Hit)
	local hitVFXFolder = getElementVFXFolder("Hit")
	if hitVFXFolder then
		local vfxTemplate
		if isAuraRune then
			vfxTemplate = (type(auraHitVfxName) == "string" and hitVFXFolder:FindFirstChild(auraHitVfxName))
				or hitVFXFolder:FindFirstChild("Default_Attack_Hit")
				or hitVFXFolder:FindFirstChild("Base_Attack_Hit")
		else
			if assetKey == "SLASH" then
				vfxTemplate = hitVFXFolder:FindFirstChild("Default_Attack_Hit") or hitVFXFolder:FindFirstChild("Base_Attack_Hit")
			else
				vfxTemplate = hitVFXFolder:FindFirstChild(assetKey .. "_Hit")
					or hitVFXFolder:FindFirstChild("Default_Attack_Hit")
					or hitVFXFolder:FindFirstChild("Base_Attack_Hit")
			end
		end
		if vfxTemplate then
			-- 타격 이펙트가 캐릭터의 발 밑이나 너무 낮게 생성되지 않도록 Y축 보정(예: +3 스터드 위로)
			local adjustedPos = pos + Vector3.new(0, 3, 0)
			local hitLifetime = isAuraRune and 4.0 or 2.0
			spawnCombatVFX(vfxTemplate, CFrame.new(adjustedPos), hitLifetime)
		else
			warn(string.format("[VFX INFO] '%s_Hit' not found in Assets.VFX.Hit", assetKey))
		end
	end
end

return AvatarController
