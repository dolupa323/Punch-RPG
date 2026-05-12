-- AvatarController.lua
-- 아바타 검술 RPG: 원소 속성 선택 UI, 실물 나무검(Accessory) 연계, 3단 연타 평타 콤보 및 타격 VFX 클라이언트 컨트롤러

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
	if targetAnim and hum then
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local success, track = pcall(function() return animator:LoadAnimation(targetAnim) end)
		if success and track then
			track:Play()
			playedAnim = true
			print(string.format("[AvatarController] Playing Combo %d Animation: %s", comboIndex, animName))
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

	-- 타겟 몬스터 타격 요청 발송 (서버 연동)
	local targetMob = findNearestTarget()
	local attackRemote = getRemoteEvent("Avatar.Attack.Request")
	if targetMob and attackRemote then
		attackRemote:FireServer({targetModel = targetMob, combo = comboIndex})
	else
		-- 헛손질 시 불필요한 임의 사운드 제거 완료
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

					-- 2. 원소 이펙트 파티클 (기존 큐브 대신 더 깔끔한 빛 발산)
					local ClassData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ClassData"))
					local classData = ClassData[element]
					local effColor = Color3.fromRGB(255, 255, 255)
					if classData and classData.vfxColor then
						effColor = Color3.fromRGB(classData.vfxColor.r, classData.vfxColor.g, classData.vfxColor.b)
					end

					local flash = Instance.new("Part")
					flash.Shape = Enum.PartType.Ball
					flash.Size = Vector3.new(1.5, 1.5, 1.5)
					flash.Color = effColor
					flash.Material = Enum.Material.Neon
					flash.CanCollide = false
					flash.Anchored = true
					flash.Position = pos
					flash.Transparency = 0.4
					flash.Parent = workspace
					
					TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = Vector3.new(4, 4, 4),
						Transparency = 1
					}):Play()
					task.delay(0.25, function() flash:Destroy() end)
				end
			end)
		end
	end)
end

return AvatarController
