-- CreatureAnimationController.lua
-- 크리처 모델의 애니메이션을 상태별로 자동 재생하는 컨트롤러

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureAnimationIds = require(Shared.Config.CreatureAnimationIds)
local DataHelper = require(Shared.Util.DataHelper)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local AnimationManager = require(Client.Utils.AnimationManager)

local CreatureAnimationController = {}

--========================================
-- Internal State
--========================================
local initialized = false
local activeCreatures = {} -- [model] = { currentTrack = AnimationTrack, lastAnim = string }

local function refreshCreatureLabel(model)
	if not model or not model:IsA("Model") then return end

	local creatureId = tostring(model:GetAttribute("CreatureId") or model.Name or ""):upper()
	if creatureId == "" then return end

	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then return end

	local label = root:FindFirstChild("CreatureLabel")
	if not label then return end

	local main = label:FindFirstChildWhichIsA("Frame")
	if not main then return end

	local nameLabel = main:FindFirstChild("NameLabel")
	if nameLabel and nameLabel:IsA("TextLabel") then
		local creatureData = DataHelper.GetData("CreatureData", creatureId)
		nameLabel.Text = (creatureData and creatureData.name) or creatureId
	end
end

--========================================
-- Private Functions
--========================================

local function getAnimNameForState(creatureModel, speed, info)
	-- [개선] 더 다양한 이름 형식 지원
	local attrId = creatureModel:GetAttribute("CreatureId")
	local nameId = creatureModel.Name:upper()
	
	local creatureId = attrId or nameId
	local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds[creatureModel.Name] or CreatureAnimationIds.DEFAULT
	
	-- 서버 상태(State) 속성 확인
	local state = creatureModel:GetAttribute("State")
	
	local animKey = "IDLE"
	if state == "STUNNED" then
		animKey = "STUNNED"
	elseif state == "DEAD" then
		animKey = "DEATH"
	elseif state == "CHASE" or state == "FLEE" then
		animKey = "RUN"
	elseif state == "WANDER" then
		animKey = "WALK"
	elseif speed and speed > 1.5 then
		animKey = speed > 15 and "RUN" or "WALK"
	end
	
	-- IDLE 상태에서 IDLE_VARIANTS가 있으면 일정 시간마다 랜덤 교체
	if animKey == "IDLE" and animSet and animSet.IDLE_VARIANTS and info then
		local now = tick()
		if not info.idleVariantUntil or now >= info.idleVariantUntil then
			local variants = animSet.IDLE_VARIANTS
			info.idleVariantAnim = variants[math.random(1, #variants)]
			info.idleVariantUntil = now + math.random(4, 8) -- 4~8초 유지
		end
		return info.idleVariantAnim
	end
	
	-- IDLE이 아닌 상태로 전환 시 변형 리셋
	if info and animKey ~= "IDLE" then
		info.idleVariantUntil = nil
		info.idleVariantAnim = nil
	end
	
	return animSet and animSet[animKey]
end

local function updateCreatureAnimation(model, info)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	-- ★ DEAD 상태에서도 사망 애니메이션 재생 허용
	local currentState = model:GetAttribute("State")
	if humanoid.Health <= 0 and currentState ~= "DEAD" then 
		return 
	end
	
	local rootPart = model.PrimaryPart
	if not rootPart then 
		-- 대기 로직 제거 (다음 프레임에 자연스럽게 처리되도록 함)
		return 
	end
	
	-- 1. 속도 기반 상태 측정 (★ EMA 스무딩 적용 — 네트워크 지연으로 인한 떨림 방지)
	local velocity = rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local rawSpeed = velocity.Magnitude
	local smoothing = 0.25 -- EMA 계수 (0~1, 낮을수록 부드러움)
	info.smoothedSpeed = info.smoothedSpeed and (info.smoothedSpeed + (rawSpeed - info.smoothedSpeed) * smoothing) or rawSpeed
	local speed = info.smoothedSpeed
	
	-- ★ 넉백 달리기 모션 방지: WalkSpeed가 0 이상이고 실제 물리 속도가 WalkSpeed의 1.5배 초과
	-- → 자발적 이동이 아닌 외부 충격(넉백)으로 판단하여 속도 0 취급
	-- 단, 서버 State가 이동 상태(WANDER/CHASE/FLEE)이면 넉백 억제 적용하지 않음
	local walkSpeed = humanoid.WalkSpeed
	local isServerMoving = (currentState == "WANDER" or currentState == "CHASE" or currentState == "FLEE")
	if not isServerMoving and walkSpeed > 0.1 and speed > walkSpeed * 1.5 then
		speed = 0
	end
	
	-- 2. 대상 애니메이션 결정
	local targetAnimName = getAnimNameForState(model, speed, info)
	
	-- [중요] 공격 중일 때는 이동 애니메이션으로 덮어쓰지 않음
	local creatureId = model:GetAttribute("CreatureId") or model.Name:upper()
	local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
	local attackAnimName = animSet.ATTACK
	
	-- ★ 사망 상태면 공격 플래그 강제 해제 → 사망 애니메이션 우선
	if currentState == "DEAD" then
		info.isAttacking = false
	elseif info.isAttacking then
		-- 공격 애니메이션이 끝났는지 체크 (캐시된 트랙 활용)
		local attackTrack = AnimationManager.load(humanoid, attackAnimName)
		if attackTrack and not attackTrack.IsPlaying then
			info.isAttacking = false
		else
			-- 아직 공격 중이면 이동 애니메이션 생략
			return
		end
	end

	-- 3. 애니메이션 전환 처리
	local isLocomotion = targetAnimName and (targetAnimName:lower():find("walk") or targetAnimName:lower():find("run"))
	
	-- ★ 보행/달리기 애니메이션 재생 속도 계산
	-- 서버 State가 이동 중이면 물리 속도가 0이어도 기본 1.0 보장 (미끄러짐 방지)
	local locomotionSpeed = 1.0
	if isLocomotion then
		local effectiveSpeed = math.max(speed, rawSpeed * 0.5)
		if isServerMoving and effectiveSpeed < 1 then
			-- 서버가 이동 상태인데 물리 속도가 거의 없는 경우 (시작/정지 순간)
			locomotionSpeed = 1.0
		else
			locomotionSpeed = math.clamp(effectiveSpeed / math.max(walkSpeed, 1), 0.5, 2.0)
		end
	end
	
	if info.lastAnim ~= targetAnimName then
		-- 기존 이동 트랙 서서히 중지
		if info.lastAnim and info.lastAnim ~= "" then
			AnimationManager.stop(humanoid, info.lastAnim, 0.3)
		end
		
		-- 새 트랙 재생
		if targetAnimName and targetAnimName ~= "" then
			local track = AnimationManager.play(humanoid, targetAnimName, 0.3)
			if track then
				-- ★ DEATH 애니메이션은 1회 재생 후 마지막 프레임 유지 (루프 X)
				local isDeath = (currentState == "DEAD")
				track.Looped = not isDeath
				-- 보행/달리기 속도 조절
				if isLocomotion then
					track:AdjustSpeed(locomotionSpeed)
				end
				info.lastAnim = targetAnimName
			else
				-- 애니메이션 로드 실패 시 잠금 방지 (다음 프레임 재시도 허용)
				info.lastAnim = ""
			end
		else
			info.lastAnim = ""
		end
	elseif targetAnimName and targetAnimName ~= "" then
		-- 동일 애니메이션 유지 중
		local track = AnimationManager.load(humanoid, targetAnimName)
		if track then
			-- 트랙이 중지된 경우 재시작 (루프 안 걸린 트랙 보호)
			if not track.IsPlaying then
				track.Looped = true
				track:Play(0.3)
			end
			-- 보행/달리기 속도 실시간 동기화
			if isLocomotion then
				track:AdjustSpeed(locomotionSpeed)
			end
		end
	end
end

local function setupFolderListeners(creatureFolder)
	local function onAdded(child)
		if child:IsA("Model") then
			task.wait(0.1) -- 속성 데이터 동기화 대기
			if not activeCreatures[child] then
				activeCreatures[child] = { lastAnim = "", isAttacking = false }
			end
			refreshCreatureLabel(child)
			child.DescendantAdded:Connect(function(desc)
				if desc.Name == "NameLabel" then
					task.defer(function()
						refreshCreatureLabel(child)
					end)
				end
			end)
		end
	end

	for _, model in ipairs(creatureFolder:GetChildren()) do
		onAdded(model)
	end
	
	creatureFolder.ChildAdded:Connect(onAdded)
	creatureFolder.ChildRemoved:Connect(function(child)
		-- 클라이언트 애니메이션 트랙 전부 정지 (공격 모션 잔류 방지)
		local humanoid = child:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0.2)
				end
			end
		end
		activeCreatures[child] = nil
	end)
end

--========================================
-- Public API
--========================================

function CreatureAnimationController.Init()
	if initialized then return end
	
	task.spawn(function()
		local creatureFolder = Workspace:WaitForChild("Creatures", 30)
		if creatureFolder then
			setupFolderListeners(creatureFolder)
		end
	end)

	-- 펫 폴더도 동일하게 감시 (펫도 크리처 애니메이션 사용)
	task.spawn(function()
		local petFolder = Workspace:WaitForChild("ActivePets", 30)
		if petFolder then
			setupFolderListeners(petFolder)
		end
	end)

	-- 서버 공격 이벤트 수신
	NetClient.On("Creature.Attack.Play", function(data)
		local model = nil
		for m, _ in pairs(activeCreatures) do
			if m:GetAttribute("InstanceId") == data.instanceId then
				model = m
				break
			end
		end
		
		if model then
			local info = activeCreatures[model]
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and info then
				local creatureId = model:GetAttribute("CreatureId") or model.Name:upper()
				local animSet = CreatureAnimationIds[creatureId] or CreatureAnimationIds.DEFAULT
				local attackAnimName = animSet.ATTACK
				
				if attackAnimName then
					-- 현재 재생 중인 이동 애니메이션 잠시 중지 (부드러운 타격)
					if info.lastAnim ~= "" then
						AnimationManager.stop(humanoid, info.lastAnim, 0.1)
						info.lastAnim = "" 
					end
					
					-- [핵심] 공격 애니메이션 재생 루틴
					task.spawn(function()
						info.isAttacking = true
						
						-- ★ 서버 권위 객체: WalkSpeed/Velocity 조작 제거
						-- NetworkOwner=nil(서버 소유) 크리처의 물리 속성은 서버에서만 제어
						-- 서버의 CreatureService에서 attackingUntil + WalkSpeed=0 으로 이미 처리됨
						
						-- 공격 애니메이션 재생
						local prepTrack = AnimationManager.play(humanoid, attackAnimName, 0.1)
						if prepTrack then
							prepTrack.Priority = Enum.AnimationPriority.Action
							task.wait(prepTrack.Length > 0 and prepTrack.Length or 0.5)
						end
						
						-- ★ 공격 상태 해제 (애니메이션 상태만 관리)
						-- 서버가 WalkSpeed를 제어하므로 클라이언트 복원 불필요
						task.wait(0.1)
						info.isAttacking = false
					end)
				end
			end
		end
	end)
	
	-- ★ 육식공룡 야간 눈빛 효과
	local EYE_GLOW_COLOR = Color3.fromRGB(180, 255, 120) -- 옅은 초록빛
	local EYE_GLOW_BRIGHTNESS = 1.5
	local EYE_GLOW_RANGE = 4
	local lastNightCheck = 0
	local isCurrentlyNight = false

	local function updateNightEyeGlow()
		local now = tick()
		-- 2초마다 밤낮 체크 (성능)
		if now - lastNightCheck > 2 then
			lastNightCheck = now
			local clockTime = Lighting.ClockTime
			isCurrentlyNight = (clockTime >= 18.5 or clockTime <= 5.5)
		end

		for model, info in pairs(activeCreatures) do
			if not model:IsDescendantOf(Workspace) then continue end
			local behavior = model:GetAttribute("Behavior")
			local isDead = model:GetAttribute("IsDead")
			if behavior ~= "AGGRESSIVE" or isDead then
				-- 육식이 아니거나 죽었으면 기존 빛 제거
				local head = model:FindFirstChild("Head", true)
				if head then
					local existing = head:FindFirstChild("NightEyeGlow")
					if existing then existing:Destroy() end
				end
				continue
			end

			local head = model:FindFirstChild("Head", true) or model:FindFirstChild("Neck", true)
			if not head or not head:IsA("BasePart") then continue end

			local glow = head:FindFirstChild("NightEyeGlow")
			if isCurrentlyNight then
				if not glow then
					glow = Instance.new("PointLight")
					glow.Name = "NightEyeGlow"
					glow.Color = EYE_GLOW_COLOR
					glow.Brightness = EYE_GLOW_BRIGHTNESS
					glow.Range = EYE_GLOW_RANGE
					glow.Shadows = false
					glow.Parent = head
				end
				glow.Enabled = true
			else
				if glow then
					glow:Destroy()
				end
			end
		end
	end

	-- 루프 업데이트 (최적화: 0.1초 간격으로 상태 체크)
	local eyeGlowTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		for model, info in pairs(activeCreatures) do
			if model:IsDescendantOf(Workspace) then
				updateCreatureAnimation(model, info)
			else
				activeCreatures[model] = nil
			end
		end
		-- 눈빛 업데이트: 3초마다 (매 프레임 불필요)
		eyeGlowTimer = eyeGlowTimer + dt
		if eyeGlowTimer >= 3 then
			eyeGlowTimer = 0
			updateNightEyeGlow()
		end
	end)
	
	initialized = true
	print("[CreatureAnimationController] Initialized")
end

return CreatureAnimationController
