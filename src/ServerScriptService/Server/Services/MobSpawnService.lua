-- MobSpawnService.lua
-- 아바타 검술 RPG: 월드 구역별 몬스터(Slime, Goblin 등) FSM 실물 3D 복제 및 데이터 기반 부활 스폰 서버 서비스

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local WorldDropService = require(Services:WaitForChild("WorldDropService"))
local PlayerStatService = require(Services:WaitForChild("PlayerStatService"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"):WaitForChild("Enums"))

local MobSpawnService = {}
local activeMobs = {} -- areaId_index -> Model Instance

--========================================
-- Internal: Loot 생성
--========================================
local function spawnLoot(mobName: string, pos: Vector3, killerPlayer: Player?)
	if not WorldDropService then
		warn("[MobSpawnService] Cannot spawn loot: WorldDropService is not initialized!")
		return
	end
	if not DataService then
		warn("[MobSpawnService] Cannot spawn loot: DataService is not initialized!")
		return
	end
	
	-- 드롭 테이블 조회 (대문자로 변환하여 매칭)
	local dropTableId = string.upper(mobName)
	local dropTable = DataService.getDropTable(dropTableId)
	
	if not dropTable then
		warn(string.format("[MobSpawnService] No drop table found for mob '%s' (Table ID: '%s')", mobName, dropTableId))
		return
	end
	
	print(string.format("[MobSpawnService] Processing loot drop for '%s' at %s. Table entries: %d", mobName, tostring(pos), #dropTable))
	
	for i, entry in ipairs(dropTable) do
		local roll = math.random()
		local chance = entry.chance or 1.0
		if roll <= chance then
			local count = math.random(entry.min or 1, entry.max or 1)
			print(string.format("[MobSpawnService] -> Roll success (%.2f <= %.2f): Spawning %d of '%s'", roll, chance, count, entry.itemId))
			
			if entry.itemId == "GOLD" or entry.itemId == "GOLD_COIN" then
				local ok, err = WorldDropService.spawnGoldDrop(pos, count)
				if not ok then
					warn(string.format("[MobSpawnService] Failed to spawn gold drop: %s", tostring(err)))
				end
			else
				-- [기획 보강]: 킬러 플레이어가 없더라도 주변에 있는 가장 가까운 플레이어를 백업 타겟으로 지정하는 Failsafe 가동!
				local targetPlayer = killerPlayer
				if not targetPlayer then
					-- 주변 100스터드 안의 플레이어를 동적으로 검색
					local limit = 100
					local closestPlayer = nil
					local closestDist = limit
					for _, p in ipairs(game.Players:GetPlayers()) do
						local char = p.Character
						local hrp = char and char:FindFirstChild("HumanoidRootPart")
						if hrp then
							local dist = (hrp.Position - pos).Magnitude
							if dist < closestDist then
								closestDist = dist
								closestPlayer = p
							end
						end
					end
					targetPlayer = closestPlayer
				end
				
				-- [기획 보강]: 슬라임 점액("SLIME_MUCUS")은 월드 드롭 모델로 땅에 떨어지지 않고 타겟 플레이어의 인벤토리에 즉시 자동 파밍 지급!
				if entry.itemId == "SLIME_MUCUS" and targetPlayer and targetPlayer:IsA("Player") then
					local InventoryService = require(Services:WaitForChild("InventoryService"))
					if InventoryService and InventoryService.addItem then
						local added, remaining = InventoryService.addItem(targetPlayer.UserId, "SLIME_MUCUS", count)
						print(string.format("[MobSpawnService] Direct Mucus Add - Player: %s, Added: %d, Remaining: %d", targetPlayer.Name, added, remaining))
						
						-- [명품 UI 피드백]: 슬라임 점액 획득 알림 전송!
						if added > 0 then
							local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
							local NetController = require(Controllers:WaitForChild("NetController"))
							if NetController and NetController.FireClient then
								NetController.FireClient(targetPlayer, "Notify.Message", {
									text = string.format("슬라임 점액 x%d 획득!", added),
									color = "GREEN"
								})
							end
						end
						
						-- 인벤토리가 가득 찬 특수 예외 상황 시에는 땅바닥에 Failsafe용 주머니(Pouch) 드롭으로 처리!
						if remaining > 0 then
							local ok, err, data = WorldDropService.spawnDrop(pos, "SLIME_MUCUS", remaining, nil, nil, "DISCARD")
							if ok then
								print("[MobSpawnService] Inventory full! Spawned remaining mucus as backup discard drop.")
							end
						end
					end
				else
					-- 그 외의 슬라임 귀고리(SLIME_EARRING), 쇠똥구리 반지(DUNG_BEETLE_RING) 등 특별 악세사리 및 무기는 월드 드롭 생성
					local ok, err, data = WorldDropService.spawnDrop(pos, entry.itemId, count)
					if not ok then
						warn(string.format("[MobSpawnService] Failed to spawn item drop '%s': %s", entry.itemId, tostring(err)))
					else
						print(string.format("[MobSpawnService] Successfully spawned drop '%s' (Count: %d). Details: %s", entry.itemId, count, game:GetService("HttpService"):JSONEncode(data)))
					end
				end
			end
		else
			print(string.format("[MobSpawnService] -> Roll failed (%.2f > %.2f) for '%s'", roll, chance, entry.itemId))
		end
	end
end

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
		hum.Parent = model
		
		warn(string.format("[MobSpawnService] %s Asset NOT found. Generated temp visual for %s_%d at %s.", config.mobModelName, areaId, index, tostring(spawnPos)))
	end

	-- ★ 모든 몬스터(실물/임시) 공통 속성 설정 및 자가 복구(Self-Healing) 리깅
	-- [외부 용접 고스트 정화 엔진] 에셋이 복제될 때 에셋 바깥(Baseplate 등)에 강제로 묶여있던 깨진 용접을 완벽하게 제거하여 구속을 풂!
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("ManualWeld") then
			local p0 = child.Part0
			local p1 = child.Part1
			if (p0 and not p0:IsDescendantOf(model)) or (p1 and not p1:IsDescendantOf(model)) then
				child:Destroy()
			end
		end
	end

	-- [물리혁신 1단계] ScaleTo 연산 및 부모화를 "가장 먼저" 수행하여 가상 HRP 크기가 강제 쪼그라드는 버그를 근본적으로 방지!
	model.Parent = workspace
	if config.modelScale and config.modelScale > 0 then
		pcall(function()
			model:ScaleTo(config.modelScale)
		end)
	end
	task.wait() -- 물리 정합성 캐시 대기

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		-- [정석적인 뼈대 보존형 자가복구] 
		-- 비주얼 파트들의 이름이나 리깅을 훼손하지 않기 위해 가상의 깡통 투명 RootPart를 생성!
		-- 축소가 완료된 이후에 장착되므로, 규격 사이즈(2, 4, 2)가 축소되지 않고 온전하게 유지됨!
		hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Size = Vector3.new(1.5, 1.2, 1.5)
		hrp.Transparency = 1
		hrp.CFrame = model:GetPivot()
		hrp.CanCollide = true
		hrp.Parent = model
		model.PrimaryPart = hrp
		
		-- 오리지널 비주얼 파트들을 이 투명 RootPart에 단 하나의 WeldConstraint로 얹어 결속!
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and p ~= hrp then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid.MaxHealth = config.maxHealth or 100
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = config.walkSpeed or 8 -- [추가] 데이터 테이블 연동 또는 기본 배회속도 세팅!
	end
	model:SetAttribute("MaxHealth", config.maxHealth or 100)
	model:SetAttribute("CurrentHealth", config.maxHealth or 100)
	model:SetAttribute("MobId", config.mobModelName or "Slime")
	model:SetAttribute("XPReward", config.xpReward or 25)

	-- [추가] 지형 파고듦 방지 엔진 (Dynamic Rig Setup & HipHeight Calibration)
	if humanoid then
		-- [버그수정] 에셋 클론 시 누락되었던 데이터 연동 체력 오버라이드 강제 적용!
		local targetHp = config.maxHealth or 70
		humanoid.MaxHealth = targetHp
		humanoid.Health = targetHp -- 풀체력 설정
	end
	
	if humanoid and hrp then
		model.PrimaryPart = hrp
		
		-- 1. 물리 해제 및 안정화 (Anchored 제거)
		-- [중요] 모든 몬스터는 파트 간 물리적 겹침 반발 폭발(하늘 발사 버그) 차단을 위해 HRP 외의 파트 CanCollide를 false로 처리!
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				
				if p == hrp then
					p.CanCollide = true 
					p.Massless = false
				else
					p.CanCollide = false
					p.Massless = true -- [물리혁신]: 거대 비주얼 메쉬 무게 저항을 0으로 소멸시켜 가볍게 질주하게 함!
				end
			end
		end
		
		-- 2. 동적 HipHeight 수동 안착 엔진 보완
		-- 쇠똥구리처럼 HRP가 비표준인 경우, HipHeight가 0이면 지면 밑에 묻히므로 HRP 크기 비례하여 적절한 높이 강제 설정!
		if humanoid.HipHeight == 0 or humanoid.HipHeight < 0.5 then
			local heightVal = (hrp.Size.Y / 2) + 0.15
			humanoid.HipHeight = heightVal
		end

		-- 2. 동적 힙 하이트(HipHeight) 정밀 보정 (구조적 Dummy Rig 배제)
		-- [핵심] 슬라임일 때만 복잡한 바닥 메쉬 추적 재연산 수행!
		local heightDiff = 0
		local lowestY = nil
		
		if config.mobModelName == "Slime" then
			lowestY = math.huge
			local r6Limbs = {["Head"]=true, ["Torso"]=true, ["Left Arm"]=true, ["Right Arm"]=true, ["Left Leg"]=true, ["Right Leg"]=true, ["HumanoidRootPart"]=true}
			
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and not r6Limbs[part.Name] and part.Transparency < 0.9 then
					local bottomY = part.Position.Y - part.Size.Y / 2
					if bottomY < lowestY then lowestY = bottomY end
				end
			end
			
			if lowestY == math.huge then
				lowestY = hrp.Position.Y - hrp.Size.Y / 2
			end
			
			-- HRP 바닥면에서 모델 최하단까지의 정밀한 물리적 거리를 HipHeight로 지정!
			local hrpBottom = hrp.Position.Y - hrp.Size.Y / 2
			heightDiff = math.max(0, hrpBottom - lowestY)
			humanoid.HipHeight = heightDiff
		else
			-- 쇠똥구리 등은 자가 복구된 HipHeight 값을 신뢰하고 유지!
			heightDiff = humanoid.HipHeight
			lowestY = hrp.Position.Y - hrp.Size.Y / 2 -- [버그해결] lowestY가 nil이 되지 않도록 HRP 바닥 높이로 칼같이 설정!
		end
		
		-- 3. 최종 위치 초기화
		-- [물리혁신 2단계] 이미 상단에서 선행 다운사이징 및 정확한 CFrame 정렬이 끝났으므로, 조립 완료 후의 중복 PivotTo는 물리 엔진 교란을 막기 위해 제외 처리!
		
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
		
		-- 몬스터 모델 전용 Idle 애니메이션 동적 감지 및 루프 재생 (서버 동기화)
		task.spawn(function()
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
			local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
			local animsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
			local monsterAnims = animsFolder and animsFolder:FindFirstChild("Monster")
			
			if monsterAnims then
				local idleAnim = monsterAnims:FindFirstChild(config.mobModelName .. "_Idle")
				if idleAnim then
					local success, idleTrack = pcall(function() return animator:LoadAnimation(idleAnim) end)
					if success and idleTrack then
						idleTrack.Looped = true
						idleTrack.Priority = Enum.AnimationPriority.Idle
						idleTrack:Play()
						
						-- [정밀 오토 애니메이션 스위처] 
						-- 몬스터가 움직일 때는 뼈대 굳음 방지를 위해 Idle 트랙 속도를 0으로 멈추고, 
						-- 제자리에 멈춰 멍때릴 때만 꼼지락거리는 Idle 모션을 다시 살아 움직이게 활성화!
						task.spawn(function()
							while model and model.Parent and humanoid and humanoid.Health > 0 do
								local isMoving = humanoid.MoveDirection.Magnitude > 0.05 or (hrp and hrp.AssemblyLinearVelocity.Magnitude > 0.5)
								if isMoving then
									if idleTrack.IsPlaying then
										idleTrack:AdjustSpeed(0) -- 모션을 정지시켜 뼈대 물리 이동을 100% 해제!
									end
								else
									if idleTrack.IsPlaying then
										idleTrack:AdjustSpeed(1) -- 제자리에 서 있을 때만 꼼지락꼼지락 재생 활성화!
									end
								end
								task.wait(0.2) -- 0.2초 간격으로 가볍고 정밀하게 체킹
							end
							pcall(function() idleTrack:Stop() end)
						end)
					end
				end
			end
		end)
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
							
							-- 몬스터 공격 애니메이션 동적 감지 및 재생 (서버 동기화)
							task.spawn(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								if animator then
									local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
									local animsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
									local monsterAnims = animsFolder and animsFolder:FindFirstChild("Monster")
									local attackAnim = monsterAnims and monsterAnims:FindFirstChild(config.mobModelName .. "_Attack")
									
									if attackAnim then
										local success, attackTrack = pcall(function() return animator:LoadAnimation(attackAnim) end)
										if success and attackTrack then
											attackTrack.Priority = Enum.AnimationPriority.Action
											attackTrack:Play()
											print(string.format("[MobSpawnService] Successfully playing dynamic Attack Animation for '%s'", config.mobModelName))
										end
									end
								end
							end)
							
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
			
			-- 1. 체력바 UI 빌보드 가시성 즉각 종료
			local bb = hrp and hrp:FindFirstChildOfClass("BillboardGui")
			if bb then
				bb.Enabled = false
			end

			-- 2. 시체 물리 충돌 해제 및 위치 고정 (시체 물리 길막 및 덜덜덜 튕김 차단)
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.Anchored = true
				end
			end

			-- 3. [프리미엄 페이드 아웃 연출] 모든 비주얼 파트들의 Transparency를 1.2초에 걸쳐 부드럽게 1로 보간!
			task.spawn(function()
				local fadeDuration = 1.2
				local steps = 24
				local interval = fadeDuration / steps
				
				-- 페이드 대상 실물 파트들과 원본 투명도 캐싱
				local fadeParts = {}
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 1 then
						fadeParts[p] = p.Transparency
					end
				end
				
				for step = 1, steps do
					local ratio = step / steps
					for part, origTrans in pairs(fadeParts) do
						if part and part.Parent then
							part.Transparency = origTrans + (1 - origTrans) * ratio
						end
					end
					task.wait(interval)
				end
			end)

			-- ★ 사망 시 경험치 지급 처리
			local tag = humanoid:FindFirstChild("creator")
			local killer = tag and tag.Value
			if killer and killer:IsA("Player") then
				local xpReward = config.xpReward or 10
				if PlayerStatService and PlayerStatService.addXP then
					PlayerStatService.addXP(killer.UserId, xpReward, "Hunt_" .. (config.mobDisplayName or "Mob"))
					print(string.format("[MobSpawnService] Awarded %d XP to %s for killing %s", xpReward, killer.Name, config.mobDisplayName or "Mob"))
				end
			end

			-- ★ 사망 시 아이템 드롭 처리
			local deathPos = model:GetPivot().Position
			spawnLoot(config.mobModelName or "Slime", deathPos, killer)
			
			-- 페이드 아웃 시간(1.2초)보다 약간 넉넉하게 대기한 후 안전 파괴
			local respawnDelay = math.max(config.respawnDelay or 1.0, 1.4)
			task.wait(respawnDelay)
			if model then model:Destroy() end
			
			local key = areaId .. "_" .. index
			-- 재스폰 시 다시 createMobModel을 호출하여 '새로운 랜덤 위치'를 추출하게 함!
			activeMobs[key] = createMobModel(areaId, index, config)
		end)
	end

	-- [DEBUG] 최종 스폰된 몬스터의 정확한 월드 피벗 및 물리 속성 정밀 진단
	task.spawn(function()
		task.wait(0.5) -- 완전히 안착할 시간을 준 후 진단
		if model and model.Parent then
			local finalCF = model:GetPivot()
			local hrp = model:FindFirstChild("HumanoidRootPart")
			local hum = model:FindFirstChildOfClass("Humanoid")
			print(string.format("[MobSpawnService DEBUG] Mob '%s' (%s_%d) Final World Pos: %s, HipHeight: %s, HRP Size: %s, Active: %s", 
				model.Name, areaId, index, tostring(finalCF.Position), 
				tostring(hum and hum.HipHeight or "NoHum"), 
				tostring(hrp and hrp.Size or "NoHRP"),
				tostring(hum and hum.Health > 0)))
		else
			warn(string.format("[MobSpawnService DEBUG] Mob '%s' (%s_%d) is ALREADY DESTROYED OR NIL after 0.5s!", config.mobModelName, areaId, index))
		end
	end)

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
