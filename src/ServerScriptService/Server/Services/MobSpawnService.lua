-- MobSpawnService.lua
-- 아바타 검술 RPG: 월드 구역별 몬스터(Slime, Goblin 등) FSM 실물 3D 복제 및 데이터 기반 부활 스폰 서버 서비스

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))

local MobSpawnService = {}
local activeMobs = {} -- areaId_index -> Model Instance

local function getRandomPosInPart(part)
	local size = part.Size
	local cf = part.CFrame
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	-- 스폰 시 파트 정중앙 Y 높이 기준 정확한 윗면(Surface) 산출!
	local topY = size.Y / 2
	return (cf * CFrame.new(rx, topY, rz)).Position
end

local function getRandomPointInTriangle(A, B, C)
	local r1 = math.sqrt(math.random())
	local r2 = math.random()
	return (1 - r1) * A + (r1 * (1 - r2)) * B + (r1 * r2) * C
end

local function getRandomPosInQuad(p1, p2, p3, p4)
	-- 4각형을 2개의 삼각형으로 분할하여 각각의 면적비에 따른 확률 가중 무작위 점 산출!
	local area1 = (p2 - p1):Cross(p3 - p1).Magnitude
	local area2 = (p3 - p1):Cross(p4 - p1).Magnitude
	local totalArea = area1 + area2
	
	if math.random() * totalArea <= area1 then
		return getRandomPointInTriangle(p1, p2, p3)
	else
		return getRandomPointInTriangle(p1, p3, p4)
	end
end

local function getNextSpawnPosition(config, index)
	-- 1순위: 구역 파트 기반 랜덤 스폰
	if config.spawnZonePartName then
		-- Workspace에서 해당 이름의 파트 검색
		local zonePart = workspace:FindFirstChild(config.spawnZonePartName, true)
		if zonePart and zonePart:IsA("BasePart") then
			return getRandomPosInPart(zonePart)
		else
			warn(string.format("[MobSpawnService] Zone Part '%s' not found in Workspace! Falling back to static coordinates.", config.spawnZonePartName))
		end
	end

	-- [NEW] 1.5순위: 4개의 고정 꼭짓점 내부 영역 무작위 스폰 (다각형 헐 랜덤)
	if config.spawnAsPolygon and config.spawnPositions and #config.spawnPositions == 4 then
		local pts = config.spawnPositions
		local v1 = Vector3.new(pts[1].x, pts[1].y, pts[1].z)
		local v2 = Vector3.new(pts[2].x, pts[2].y, pts[2].z)
		local v3 = Vector3.new(pts[3].x, pts[3].y, pts[3].z)
		local v4 = Vector3.new(pts[4].x, pts[4].y, pts[4].z)
		
		-- 시계/반시계 순서가 꼬이지 않게 순서 배치 (1->2->3->4)
		return getRandomPosInQuad(v1, v2, v3, v4)
	end

	-- 2순위: 고정 좌표 리스트 개별 매칭
	if config.spawnPositions and #config.spawnPositions > 0 then
		local posIdx = math.clamp(index, 1, #config.spawnPositions)
		local pt = config.spawnPositions[posIdx]
		return Vector3.new(pt.x, pt.y, pt.z)
	end

	-- 최후 수단: 원점 백업
	return Vector3.new(0, 10, 0)
end

local function createMobModel(areaId, index, config)
	-- 실시간으로 스폰할 정확한 위치 계산! (파트 있으면 파트 위 랜덤 위치)
	local spawnPos = getNextSpawnPosition(config, index)

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local monstersFolder = assetsFolder and assetsFolder:FindFirstChild("Monsters")
	local mobAsset = monstersFolder and monstersFolder:FindFirstChild(config.mobModelName)

	local model
	if mobAsset then
		-- 실물 에셋 복제 스폰
		model = mobAsset:Clone()
		model:PivotTo(CFrame.new(spawnPos))
		print(string.format("[MobSpawnService] Real 3D %s spawned for %s Card %d!", config.mobModelName, areaId, index))
	else
		-- 실물 에셋 부재 시 자동 생성 임시 파트 조립 (디버깅 안전장치)
		model = Instance.new("Model")
		model.Name = config.mobModelName
		
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Size = Vector3.new(3, 3, 3)
		hrp.Shape = Enum.PartType.Ball
		hrp.Color = Color3.fromRGB(80, 220, 100)
		hrp.Material = Enum.Material.Glass
		hrp.Transparency = 0.2
		hrp.Position = spawnPos
		hrp.CanCollide = true
		hrp.Anchored = false
		hrp.Parent = model
		model.PrimaryPart = hrp

		local hum = Instance.new("Humanoid")
		hum.MaxHealth = config.maxHealth or 30
		hum.Health = config.maxHealth or 30
		hum.Parent = model
		
		warn(string.format("[MobSpawnService] %s Asset NOT found. Generated temp visual for %s_%d at %s.", config.mobModelName, areaId, index, tostring(spawnPos)))
	end

	-- [핵심 결정타] 계산 전 Workspace 부모화 강제!!
	-- 부모가 nil일 때 ScaleTo를 하면 하위 파트들의 Position이 갱신되지 않아 이전 값이 수집되는 버그 방지!
	model.Parent = workspace
	task.wait() -- 물리 캐시 한 프레임 대기하여 정확한 Size/Position 반영 보장

	-- [추가] 스케일 조정 로직 (데이터 테이블의 modelScale 적용)
	if config.modelScale and config.modelScale > 0 then
		pcall(function()
			model:ScaleTo(config.modelScale)
		end)
	end

	-- [추가] 지형 파고듦 방지 엔진 (Dynamic Rig Setup & HipHeight Calibration)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	
	if humanoid then
		-- [버그수정] 에셋 클론 시 누락되었던 데이터 연동 체력 오버라이드 강제 적용!
		local targetHp = config.maxHealth or 70
		humanoid.MaxHealth = targetHp
		humanoid.Health = targetHp -- 풀체력 설정
	end
	
	if humanoid and hrp then
		model.PrimaryPart = hrp
		
		-- 1. 물리 해제 및 안정화 (Anchored 제거)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				-- 슬라임 바디 콜라이더 강제 세팅 (Root만 활성화!)
				if p == hrp then
					p.CanCollide = true 
				else
					p.CanCollide = false -- [핵심] 바디 파트 충돌 꺼야 HipHeight가 오작동하여 공중에 안 뜸!
				end
			end
		end

		-- 2. 동적 힙 하이트(HipHeight) 정밀 보정 (구조적 Dummy Rig 배제)
		-- [핵심] 모델 내부의 R6 더미 부위(Leg, Torso)를 배제하고 '순수 슬라임 메쉬'만 추적!
		local lowestY = math.huge
		local r6Limbs = {["Head"]=true, ["Torso"]=true, ["Left Arm"]=true, ["Right Arm"]=true, ["Left Leg"]=true, ["Right Leg"]=true, ["HumanoidRootPart"]=true}
		
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not r6Limbs[part.Name] and part.Transparency < 0.9 then
				local bottomY = part.Position.Y - part.Size.Y / 2
				if bottomY < lowestY then lowestY = bottomY end
			end
		end
		
		-- 최하단을 찾지 못했을 경우의 비상 로직
		if lowestY == math.huge then
			lowestY = hrp.Position.Y - hrp.Size.Y / 2
		end
		
		-- HRP 바닥면에서 모델 최하단까지의 정밀한 물리적 거리를 HipHeight로 지정!
		local hrpBottom = hrp.Position.Y - hrp.Size.Y / 2
		local heightDiff = math.max(0, hrpBottom - lowestY)
		humanoid.HipHeight = heightDiff
		
		-- 3. 최종 위치 초기화 (기하학적 모델 바닥면이 spawnPos 표면에 정확히 닿도록 Pivot 보간)
		local modelPivot = model:GetPivot()
		local pivotBottomDiff = modelPivot.Position.Y - lowestY
		-- spawnPos(지표면) + 모델 절반 높이 만큼만 띄워 정확하게 바닥에 딱 붙임 (+0.5 여유분도 완벽 제거!)
		model:PivotTo(CFrame.new(spawnPos + Vector3.new(0, pivotBottomDiff, 0)))
		
		-- [완성] 몬스터 헤드업 UI (프리미엄 HP 바 & 이름표) 통합 생성
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		
		local bb = Instance.new("BillboardGui")
		bb.Name = "MobUI"
		bb.Size = UDim2.new(0, 90, 0, 30) -- 폭과 높이 전체적으로 다이어트! (120x45 -> 90x30)
		bb.StudsOffset = Vector3.new(0, heightDiff + hrp.Size.Y/2 + 0.5, 0) -- 캐릭터 머리에 더 바짝 붙임
		bb.AlwaysOnTop = true
		bb.MaxDistance = 60 -- 너무 멀리있는건 안보여서 화면 깔끔하게 유지
		
		-- 1. 이름표 라벨 (더 얇고 작게)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0, 16)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = config.mobDisplayName or config.mobModelName
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextStrokeTransparency = 0.4
		nameLabel.Font = Enum.Font.SourceSansBold
		nameLabel.TextSize = 12 -- 미니멀 폰트사이즈
		nameLabel.Parent = bb
		
		-- 2. HP 바 컨테이너 (극도로 얇게 조정)
		local hpBg = Instance.new("Frame")
		hpBg.Name = "HPBackground"
		hpBg.Size = UDim2.new(0.85, 0, 0, 10) -- [요청반영] 기존 15 -> 10으로 초슬림화!!
		hpBg.Position = UDim2.new(0.5, 0, 0, 16) -- 이름 바로 밑에 밀착
		hpBg.AnchorPoint = Vector2.new(0.5, 0)
		hpBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		hpBg.BackgroundTransparency = 0.2
		hpBg.BorderSizePixel = 0
		hpBg.Parent = bb
		
		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 3) -- 뚱뚱해보이지 않게 코너값 축소
		bgCorner.Parent = hpBg
		
		local bgStroke = Instance.new("UIStroke")
		bgStroke.Thickness = 1
		bgStroke.Color = Color3.fromRGB(0, 0, 0)
		bgStroke.Parent = hpBg
		
		-- 3. 실제 채워지는 게이지 (Fill)
		local hpFill = Instance.new("Frame")
		hpFill.Name = "HPFill"
		hpFill.Size = UDim2.new(1, 0, 1, 0)
		hpFill.BackgroundColor3 = Color3.fromRGB(60, 220, 80)
		hpFill.BorderSizePixel = 0
		hpFill.Parent = hpBg
		
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 3)
		fillCorner.Parent = hpFill
		
		-- 4. 게이지 안에 들어갈 HP 텍스트 숫자 (초슬림바에 맞게 아주 작게)
		local hpLabel = Instance.new("TextLabel")
		hpLabel.Name = "HPLabel"
		hpLabel.Size = UDim2.new(1, 0, 1, 0)
		hpLabel.BackgroundTransparency = 1
		hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		hpLabel.TextStrokeTransparency = 0.5
		hpLabel.Font = Enum.Font.SourceSansBold
		hpLabel.TextSize = 9 -- 작은 바 안에 쏙 들어가도록 사이즈 9로 축소
		hpLabel.ZIndex = 5
		hpLabel.Parent = hpBg

		local TweenService = game:GetService("TweenService")
		local function updateHPDisplay()
			local cur = math.max(0, humanoid.Health)
			local mx = math.max(1, humanoid.MaxHealth)
			local pct = math.clamp(cur / mx, 0, 1)
			
			-- 텍스트 갱신
			hpLabel.Text = string.format("%d / %d", math.floor(cur), math.floor(mx))
			
			-- 게이지 부드러운 애니메이션 트윈
			TweenService:Create(hpFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(pct, 0, 1, 0)
			}):Play()
			
			-- 색상 동적 변경 (피 적어지면 노랑 -> 빨강 트랜지션)
			local targetColor = Color3.fromRGB(60, 220, 80) -- 기본 녹색
			if pct <= 0.3 then
				targetColor = Color3.fromRGB(230, 50, 50) -- 빨강
			elseif pct <= 0.6 then
				targetColor = Color3.fromRGB(240, 200, 40) -- 노랑
			end
			
			TweenService:Create(hpFill, TweenInfo.new(0.25), {
				BackgroundColor3 = targetColor
			}):Play()
		end
		
		updateHPDisplay()
		humanoid.HealthChanged:Connect(updateHPDisplay)
		
		bb.Parent = hrp
	end

	local isAlive = true

	if humanoid then
		-- [추가] 심플 몬스터 AI 엔진 (배회 + 추격 + 공격 기능 융합!)
		task.spawn(function()
			task.wait(math.random(1, 3)) -- 초기 엇박자 대기
			local lastAttackTick = 0
			
			local AGGRO_RADIUS = 30  -- 인식 범위
			local ATTACK_RANGE = 6   -- 공격 사거리
			local TICK_RATE = 0.5    -- AI 판단 주기(초)

			while isAlive and humanoid and humanoid.Parent and model:FindFirstChild("HumanoidRootPart") do
				local hrp = model.HumanoidRootPart
				
				-- 1단계: 주변에 가장 가까운 생존한 플레이어 탐색
				local targetPlayer = nil
				local minDist = AGGRO_RADIUS
				
				for _, p in ipairs(Players:GetPlayers()) do
					local char = p.Character
					local phum = char and char:FindFirstChild("Humanoid")
					local phrp = char and char:FindFirstChild("HumanoidRootPart")
					
					if phum and phum.Health > 0 and phrp then
						local d = (hrp.Position - phrp.Position).Magnitude
						if d < minDist then
							minDist = d
							targetPlayer = char
						end
					end
				end
				
				-- 2단계: 타겟 존재 여부에 따른 행동 분기
				if targetPlayer then
					-- [A. 전투 모드] 플레이어 추격 및 공격
					local phrp = targetPlayer.HumanoidRootPart
					local phum = targetPlayer.Humanoid
					
					if minDist <= ATTACK_RANGE then
						-- 사거리 이내라면 정지하고 즉시 공격!
						humanoid:MoveTo(hrp.Position) -- 멈춤
						local now = os.clock()
						local cooldown = config.attackCooldown or 1.5
						
						if now - lastAttackTick >= cooldown then
							lastAttackTick = now
							
							-- [핵심 기능 추가] 공격 전 텔레그래프(Telegraph) 히트박스 경고 장치!
							local telegraphDuration = 0.65 -- 0.65초 대기 후 공격판정
							local mobRootPos = hrp.Position
							
							task.spawn(function()
								-- 1. 바닥 경고 이펙트 생성 (네온 레드 원반)
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "SlimeAtkTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								-- 두께 0.4, 반경 ATTACK_RANGE (Size.Y, Size.Z가 지름이므로 *2)
								warnCircle.Size = Vector3.new(0.4, ATTACK_RANGE * 2, ATTACK_RANGE * 2)
								
								-- 정확한 지면 높이 산출 (Humanoid의 HipHeight와 RootPart 절반 크기 합산)
								local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
								local floorPos = mobRootPos - Vector3.new(0, groundOffset - 0.2, 0)
								
								warnCircle.CFrame = CFrame.new(floorPos) * CFrame.Angles(0, 0, math.rad(90)) -- 눕히기
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.CanTouch = false -- [추가] 물리 접촉 무시 (이벤트 낭비 방지)
								warnCircle.CanQuery = false -- [핵심] 레이캐스트 감지 무시하여 마우스 클릭이 이펙트를 뚫고 지나가게 함!
								warnCircle.CastShadow = false -- 그림자 비활성
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(255, 0, 0)
								warnCircle.Transparency = 0.85 -- 더 투명하게 시작
								warnCircle.Parent = workspace
								
								-- 깜빡거리는 애니메이션 (더욱 위협적으로 보이게)
								local ts = game:GetService("TweenService")
								local flashTween = ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 0.5 -- 끝날 때도 은은한 투명도 유지 (너무 새빨갛지 않게)
								})
								flashTween:Play()

								-- 2. 선행 딜레이 대기 (플레이어가 도망칠 수 있는 골든 타임)
								task.wait(telegraphDuration)
								
								-- 3. 최종 판정 및 데미지 적용
								-- 대기 시간 동안 플레이어가 범위를 벗어났는지 재측정!
								if isAlive and targetPlayer and targetPlayer.Parent and targetPlayer:FindFirstChild("HumanoidRootPart") then
									local currentPhrp = targetPlayer.HumanoidRootPart
									local currentDist = (mobRootPos - currentPhrp.Position).Magnitude
									
									-- 회피 판정: 판정 거리 내에 아직 남아있는 경우에만 타격!
									if currentDist <= ATTACK_RANGE + 1.5 then -- 약간의 여유 판정 추가
										local dmg = config.baseDamage or 5
										local currentPhum = targetPlayer:FindFirstChild("Humanoid")
										if currentPhum and currentPhum.Health > 0 then
											currentPhum:TakeDamage(dmg)
											
											-- 시각적 피격 타격감 (Highlight)
											task.spawn(function()
												local highlight = Instance.new("Highlight")
												highlight.Name = "DamageFlash"
												highlight.FillColor = Color3.fromRGB(255, 0, 0)
												highlight.OutlineColor = Color3.fromRGB(255, 100, 100)
												highlight.FillTransparency = 0.4
												highlight.OutlineTransparency = 0
												highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
												highlight.Adornee = targetPlayer
												highlight.Parent = targetPlayer
												
												task.wait(0.12)
												if highlight and highlight.Parent then
													highlight:Destroy()
												end
											end)
										end
									end
								end
								
								-- 4. 이펙트 깔끔하게 제거
								warnCircle:Destroy()
							end)
						end
					else
						-- 사거리 밖이라면 플레이어 방향으로 계속 쫓아감!
						humanoid:MoveTo(phrp.Position)
					end
					task.wait(TICK_RATE) -- 전투 중엔 기민하게 재판단
				else
					-- [B. 평화 모드] 배회 (Wander)
					local nextDest = getNextSpawnPosition(config, index)
					humanoid:MoveTo(nextDest)
					
					-- 도착할 때까지 대기하되, 도중에 적이 나타나면 루프 탈출하게 설계
					local arrived = false
					local c = humanoid.MoveToFinished:Connect(function() arrived = true end)
					
					local startWait = os.clock()
					-- 최대 6초 대기하나, 0.5초마다 적이 나타났는지 스캔 수행!
					while not arrived and os.clock() - startWait < 6 and isAlive do
						task.wait(TICK_RATE)
						-- 배회 도중 근처에 플레이어가 나타나면 즉시 배회 취소하고 루프 최상단으로!
						local enemySpotted = false
						for _, p in ipairs(Players:GetPlayers()) do
							if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
								if (hrp.Position - p.Character.HumanoidRootPart.Position).Magnitude < AGGRO_RADIUS then
									enemySpotted = true
									break
								end
							end
						end
						if enemySpotted then break end
					end
					if c then c:Disconnect() end
					
					-- 도착 후 멍때리기 (IDLE)
					if isAlive then
						task.wait(math.random(2, 4))
					end
				end
			end
		end)

		humanoid.Died:Connect(function()
			isAlive = false
			local respawnDelay = config.respawnDelay or 1.0
			task.wait(respawnDelay)
			if model then model:Destroy() end
			
			local key = areaId .. "_" .. index
			-- 재스폰 시 다시 createMobModel을 호출하여 '새로운 랜덤 위치'를 추출하게 함!
			activeMobs[key] = createMobModel(areaId, index, config)
		end)
	end

	return model
end

function MobSpawnService.Init()
	print("[MobSpawnService] Initializing Dynamic Smart Zone Mob Spawn Service...")

	task.spawn(function()
		task.wait(3.0) -- 에셋 로드 완료를 위해 여유 대기
		
		local spawnDataList = DataService.get("MobSpawnData")
		if not spawnDataList then return end

		for areaId, config in pairs(spawnDataList) do
			-- 루프 횟수 결정: spawnCount가 있으면 우선 사용, 없으면 spawnPositions 개수 사용
			local spawnLoopCount = config.spawnCount or (config.spawnPositions and #config.spawnPositions) or 0
			
			for idx = 1, spawnLoopCount do
				local key = areaId .. "_" .. idx
				activeMobs[key] = createMobModel(areaId, idx, config)
			end
			
			print(string.format("[MobSpawnService] Successfully auto-spawned %d Mobs for Area: %s!", spawnLoopCount, areaId))
		end
	end)
end

return MobSpawnService
