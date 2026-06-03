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
		local dropMultiplier = 1
		if killerPlayer then
			local attrMult = tonumber(killerPlayer:GetAttribute("DropRateMultiplier")) or 1
			dropMultiplier = math.max(1, attrMult)
		end
		chance = math.clamp(chance * dropMultiplier, 0, 1)
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
				
				-- [기획 보강]: 재료 아이템(RESOURCE 타입)은 월드 드롭 모델로 땅에 떨어지지 않고 타겟 플레이어의 인벤토리에 즉시 자동 파밍 지급!
				local itemData = DataService.getItem(entry.itemId)
				local isResource = itemData and itemData.type == "RESOURCE"
				
				if isResource and targetPlayer and targetPlayer:IsA("Player") then
					local InventoryService = require(Services:WaitForChild("InventoryService"))
					if InventoryService and InventoryService.addItem then
						local added, remaining = InventoryService.addItem(targetPlayer.UserId, entry.itemId, count)
						print(string.format("[MobSpawnService] Direct Resource Add - Player: %s, Item: %s, Added: %d, Remaining: %d", targetPlayer.Name, entry.itemId, added, remaining))
						
						-- [명품 UI 피드백]: 획득 알림 전송!
						if added > 0 then
							local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
							local NetController = require(Controllers:WaitForChild("NetController"))
							if NetController and NetController.FireClient then
								local displayName = itemData.name or entry.itemId
								NetController.FireClient(targetPlayer, "Notify.Message", {
									text = string.format("%s x%d 획득!", displayName, added),
									color = "GREEN"
								})
							end
						end
						
						-- 인벤토리가 가득 찬 특수 예외 상황 시에는 땅바닥에 Failsafe용 주머니(Pouch) 드롭으로 처리!
						if remaining > 0 then
							local ok, err, data = WorldDropService.spawnDrop(pos, entry.itemId, remaining, nil, nil, "DISCARD")
							if ok then
								print("[MobSpawnService] Inventory full! Spawned remaining resource as backup discard drop.")
							end
						end
					end
				else
					-- 그 외의 슬라임 귀고리(SLIME_EARRING), 뿔 애벌레 반지(HORNED_LARVA_RING) 등 특별 악세사리 및 무기는 월드 드롭 생성
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
	
	-- [Active Rune Drop Logic] 스텀프 처치 시 룬 15% 드롭
	if mobName == "Stump" and killerPlayer then
		local element = killerPlayer:GetAttribute("Element")
		if element and element ~= "None" then
			local runeRoll = math.random(1, 100)
			if runeRoll <= 15 then
				local runeItemId = "EMBER"
				if element == "Water" then runeItemId = "DROPLET"
				elseif element == "Dark" then runeItemId = "NIGHT" end
				
				local ok, err = WorldDropService.spawnDrop(pos, runeItemId, 1)
				if ok then
					print(string.format("[MobSpawnService] Boss Rune Dropped for %s (%s)", killerPlayer.Name, runeItemId))
				else
					warn("[MobSpawnService] Boss Rune Drop Failed: ", tostring(err))
				end
			end
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
	-- [NEW] 최우선: 보스방 등에서 사용할 정확한 고정 스폰 좌표
	if config.exactSpawnPosition then
		return Vector3.new(config.exactSpawnPosition.x, config.exactSpawnPosition.y, config.exactSpawnPosition.z)
	end
	
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
		
		-- [지형 인식 스폰 (Terrain Raycast)] 
		if not config.skipTerrainScan then
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {model}
			
			-- [수정] 동굴 같은 실내 환경(isIndoor = true)일 경우 하늘이 아닌, 스폰 좌표 바로 위(20스터드)에서 짧게 레이저를 쏴서 천장을 피합니다.
			local startY = config.isIndoor and (spawnPos.Y + 20) or math.max(spawnPos.Y + 200, 500)
			local rayDist = config.isIndoor and -100 or -1000
			
			local skyPos = Vector3.new(spawnPos.X, startY, spawnPos.Z)
			local rayResult = workspace:Raycast(skyPos, Vector3.new(0, rayDist, 0), raycastParams)
			
			if rayResult then
				-- 바닥(Floor) 정확한 고도를 찾아내고, 모델이 지형에 끼이지 않도록 살짝(5스터드) 위에서 스폰시킴
				-- 이후 아래에 있는 하이브리드 HipHeight 엔진이 알아서 중력과 함께 완벽히 안착시킴
				spawnPos = rayResult.Position + Vector3.new(0, 5, 0)
			end
		end
		
		model:PivotTo(CFrame.new(spawnPos))
		
		-- [물리 폭발 방지] 모델 내부 파트들의 자체 충돌로 인한 튕김(Fling) 방지
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.CanCollide = false
			end
		end
		-- print(string.format("[MobSpawnService] Real 3D %s spawned for %s Card %d at actual floor Y: %.2f", config.mobModelName, areaId, index, spawnPos.Y))
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
	
	-- [최강의 자가진단 및 물리 스케일링 엔진]
	-- 1. PrimaryPart 강제 확보 (ScaleTo가 정상 작동하기 위한 필수 선행요건)
	if not model.PrimaryPart then
		local foundHrp = model:FindFirstChild("HumanoidRootPart")
		if foundHrp then
			model.PrimaryPart = foundHrp
		else
			for _, child in ipairs(model:GetChildren()) do
				if child:IsA("BasePart") then
					model.PrimaryPart = child
					break
				end
			end
		end
	end

	-- 2. Humanoid 스케일러 간섭 방지 (Roblox 자동 스케일러가 ScaleTo를 무효화하는 버그 차단)
	local preHumanoid = model:FindFirstChildOfClass("Humanoid")
	if preHumanoid then
		pcall(function()
			preHumanoid.AutomaticScalingEnabled = false
			local bh = preHumanoid:FindFirstChild("BodyHeightScale") if bh then bh:Destroy() end
			local bw = preHumanoid:FindFirstChild("BodyWidthScale") if bw then bw:Destroy() end
			local bd = preHumanoid:FindFirstChild("BodyDepthScale") if bd then bd:Destroy() end
			local hs = preHumanoid:FindFirstChild("HeadScale") if hs then hs:Destroy() end
		end)
	end

	-- 3. 스케일 적용
	if config.modelScale and config.modelScale > 0 then
		pcall(function()
			model:ScaleTo(config.modelScale)
			print(string.format("[MobSpawnService Scale] Applied scale %f to '%s'", config.modelScale, model.Name))
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
		
		-- [중요] 모든 애니메이션의 서버 로딩 및 클라이언트 동기화 복제를 위해 Animator 객체 선제 생성 보장!
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			Instance.new("Animator", humanoid)
		end
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
		
		-- [하이브리드 힙 하이트(HipHeight) 엔진] 원본 아티스트 캘리브레이션 비율 캡처
		local originalHipHeight = humanoid.HipHeight or 0
		local originalHrpSizeY = hrp.Size.Y
		local hipHeightRatio = 0
		if originalHrpSizeY > 0.001 then
			hipHeightRatio = originalHipHeight / originalHrpSizeY
		end
		
		-- [물리갱신] HRP의 물리 충돌 영역이 너무 작아 지형 아래로 꺼지는 물리 엔진 버그를 완벽 해결하기 위해 최소 규격 강제 조정!
		local currentSize = hrp.Size
		if currentSize.X < 2 or currentSize.Y < 2 or currentSize.Z < 2 then
			hrp.Size = Vector3.new(math.max(2, currentSize.X), math.max(2, currentSize.Y), math.max(2, currentSize.Z))
		end
		
		-- [물리갱신] 몬스터 밀림(축구공) 방지 및 유저 튕겨남(Fling) 방지: HRP 밀도를 5로 낮추어 유저가 부딪혀도 멀리 날아가지 않게 함!
		hrp.CustomPhysicalProperties = PhysicalProperties.new(5, 2.0, 0)
		hrp.Massless = false
		hrp.Transparency = 1
		
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
		
		-- [신규] 몬스터 모델의 자체 방향이 잘못되었을 때 (세로로 서 있는 모델 등) 비주얼 회전 보정 (재귀형 웰드 세이프 연산)
		if config.spawnRotationOffset then
			local rotCF = CFrame.Angles(
				math.rad(config.spawnRotationOffset.x or 0),
				math.rad(config.spawnRotationOffset.y or 0),
				math.rad(config.spawnRotationOffset.z or 0)
			)
			-- 모든 WeldConstraint 수집 및 일시 비활성화 (물리 엔진 교란 방지)
			local welds = {}
			for _, w in ipairs(model:GetDescendants()) do
				if w:IsA("WeldConstraint") then
					w.Enabled = false
					table.insert(welds, w)
				end
			end

			-- A. Rig 모델인 경우 RootJoint 회전 보정 (Roblox Humanoid가 HRP의 upright 상태를 강제하므로 joint 회전이 가장 적합)
			local rootJoint = model:FindFirstChild("RootJoint", true) 
				or model:FindFirstChild("Root Joint", true) 
				or hrp:FindFirstChildOfClass("Motor6D")
			
			if rootJoint then
				rootJoint.C0 = rootJoint.C0 * rotCF
			else
				-- B. Welded 모델인 경우 모든 비주얼 파트(중첩 폴더/모델 자식들 포함)를 HRP 기준으로 회전 보정
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p ~= hrp then
						local relativeCF = hrp.CFrame:Inverse() * p.CFrame
						p.CFrame = hrp.CFrame * rotCF * relativeCF
					end
				end
			end

			-- 웰드 상태 복구
			for _, w in ipairs(welds) do
				w.Enabled = true
			end
		end

		-- 2. 동적 힙 하이트(HipHeight) 정밀 보정 (모든 몬스터 지형 파고듦 및 낙하 버그 방지)
		if config.customHipHeight then
			humanoid.HipHeight = config.customHipHeight
		elseif hipHeightRatio > 0.05 and not config.spawnRotationOffset then
			-- [오리지널 비율 유지] 불도마뱀, 쇠똥구리처럼 원래 정밀 세팅된 리그의 경우 비율을 따라감! (회전된 모델은 제외)
			humanoid.HipHeight = hrp.Size.Y * hipHeightRatio
		else
			-- [비주얼 스캐너 렌더링 폴백] 슬라임 같이 HipHeight가 없는 조립형 몬스터용 (회전 반영 정밀 보정)
			local lowestY = math.huge
			local ignoreParts = {["HumanoidRootPart"] = true}
			
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and not ignoreParts[part.Name] and part.Transparency < 0.9 then
					local CF = part.CFrame
					local S = part.Size
					-- 파트의 회전 행렬을 반영한 정밀한 글로벌 수직 반폭(halfHeight) 산출
					local halfHeight = 0.5 * (math.abs(CF.RightVector.Y) * S.X + math.abs(CF.UpVector.Y) * S.Y + math.abs(CF.LookVector.Y) * S.Z)
					local bottomY = CF.Position.Y - halfHeight
					if bottomY < lowestY then
						lowestY = bottomY
					end
				end
			end
			
			if lowestY == math.huge then
				lowestY = hrp.Position.Y - hrp.Size.Y / 2
			end
			
			-- HRP 중심에서 최하단 비주얼까지의 정밀 거리 계산
			local offset = hrp.Position.Y - lowestY
			local halfHrpY = hrp.Size.Y / 2
			local targetHipHeight = offset - halfHrpY
			
			if targetHipHeight < 0 then
				-- 비주얼이 너무 작아 HRP 바닥에 안 닿는 경우: 모든 비주얼 파트를 HRP 바닥면으로 강제 재배치 (재귀 웰드 해제 적용)
				local shiftY = -targetHipHeight -- 아래로 내릴 거리
				
				local welds = {}
				for _, w in ipairs(model:GetDescendants()) do
					if w:IsA("WeldConstraint") then
						w.Enabled = false
						table.insert(welds, w)
					end
				end

				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p ~= hrp then
						p.CFrame = p.CFrame - Vector3.new(0, shiftY, 0)
					end
				end

				for _, w in ipairs(welds) do
					w.Enabled = true
				end

				humanoid.HipHeight = 0.05 -- 지면 스크래치 방지 최소 오프셋
			else
				humanoid.HipHeight = targetHipHeight
			end
		end
		
		-- 3. 최종 위치 초기화
		-- [물리혁신 2단계] 이미 상단에서 선행 다운사이징 및 정확한 CFrame 정렬이 끝났으므로, 조립 완료 후의 중복 PivotTo는 물리 엔진 교란을 막기 위해 제외 처리!
		
		-- [완성] 몬스터 헤드업 UI (프리미엄 HP 바 & 이름표) 통합 생성
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		
		local bb = Instance.new("BillboardGui")
		bb.Name = "MobUI"
		bb.Size = UDim2.new(0, 90, 0, 30) -- 폭과 높이 전체적으로 다이어트! (120x45 -> 90x30)
		bb.StudsOffset = Vector3.new(0, humanoid.HipHeight + hrp.Size.Y/2 + 0.5, 0) -- 캐릭터 머리에 더 바짝 붙임
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
				local idleAnimName = config.mobModelName .. "_Idle"
				local walkAnimName = config.mobModelName .. "_Walk"
				
				-- StumpKing일 때 전용 애니메이션이 없으면 Stump 애니메이션으로 안전히 폴백
				if config.mobModelName == "StumpKing" then
					if not monsterAnims:FindFirstChild(idleAnimName) then
						idleAnimName = "Stump_Idle"
					end
					if not monsterAnims:FindFirstChild(walkAnimName) then
						walkAnimName = "Stump_Walk"
					end
				end

				local idleAnim = monsterAnims:FindFirstChild(idleAnimName)
				local walkAnim = monsterAnims:FindFirstChild(walkAnimName)
				
				local idleTrack = nil
				local walkTrack = nil
				
				if idleAnim then
					local success, track = pcall(function() return animator:LoadAnimation(idleAnim) end)
					if success and track then
						track.Looped = false
						track.Priority = Enum.AnimationPriority.Idle
						idleTrack = track
					end
				end
				
				if walkAnim then
					local success, track = pcall(function() return animator:LoadAnimation(walkAnim) end)
					if success and track then
						track.Looped = true
						track.Priority = Enum.AnimationPriority.Movement
						walkTrack = track
					end
				end
				
				if idleTrack or walkTrack then
					task.spawn(function()
						while model and model.Parent and humanoid and humanoid.Health > 0 do
							local isMoving = humanoid.MoveDirection.Magnitude > 0.05 or (hrp and hrp.AssemblyLinearVelocity.Magnitude > 0.5)
							
							if isMoving then
								if idleTrack and idleTrack.IsPlaying then idleTrack:Stop() end
								if walkTrack and not walkTrack.IsPlaying then
									walkTrack:Play()
								end
								task.wait(0.1)
							else
								if walkTrack and walkTrack.IsPlaying then walkTrack:Stop() end
								
								if idleTrack then
									task.wait(math.random(20, 50) / 10.0)
									local stillNotMoving = humanoid.MoveDirection.Magnitude <= 0.05 and (hrp and hrp.AssemblyLinearVelocity.Magnitude <= 0.5)
									if stillNotMoving and humanoid.Health > 0 then
										if not idleTrack.IsPlaying then
											idleTrack:Play()
										end
									end
								else
									task.wait(0.5)
								end
							end
						end
						if idleTrack then pcall(function() idleTrack:Stop() end) end
						if walkTrack then pcall(function() walkTrack:Stop() end) end
					end)
				end
			end
		end)
	end

	local isAlive = true

	if humanoid then
		-- [추가] 심플 몬스터 AI 엔진 (배회 + 추격 + 공격 기능 융합!)
		task.spawn(function()
			if config.mobModelName == "Stump" then
				task.wait(0.1) -- 스텀프는 젠 즉시 즉각적인 초스피드 AI 가동!
			else
				task.wait(math.random(1, 3)) -- 초기 엇박자 대기
			end

			-- [몬스터 FSM 공통 엔진] 슬라임, 쇠똥구리, 불도마뱀 등 모든 몬스터가 동일한 FSM 뼈대를 완벽히 공유합니다!
			local lastAttackTick = 0
			local lastPoisonTick = 0
			local lastJumpTick = 0
			local lastThrustTick = 0
			local lastLeapSlamTick = 0
			local lastWhirlwindTick = 0
			local lastGimmickTick = 0
			local lastSwordDropTick = 0 -- 유령기사 패턴 3(검 낙하)용
			local currentGimmickMode = 1
			local isBoss = (config.mobModelName == "BlueFlameKnight" or config.mobModelName == "StumpKing" or config.mobModelName == "Stump")
			local spawnCenter = getNextSpawnPosition(config, index) -- 스폰 중심점 (배회 및 둥지 복귀 기준)
			
			-- [푸른불꽃 기사 전용 Phase 2 스태틱 변수군]
			local bfkPhase2Active = false
			local bfkAuraEmitters = {}
			
			-- [반응속도 및 감지혁신]: 스텀프/박쥐의 유저 인식 반경 상승, FSM 주기를 단축하여 극적인 초고속 즉시 타격 실현!
			local AGGRO_RADIUS = (config.mobModelName == "Stump") and 70 or ((config.mobModelName == "CyclopsBat") and 60 or (isBoss and 40 or 30))
			local ATTACK_RANGE = (config.mobModelName == "FireLizard") and 18 or ((config.mobModelName == "StumpKing") and 15 or 6)
			local TICK_RATE = (config.mobModelName == "Stump") and 0.12 or ((config.mobModelName == "CyclopsBat") and 0.15 or (isBoss and 0.3 or 0.5))
			
			-- [빅골렘 전용] 콰콰쾅 바위 타격 이펙트 함수
			local function playRockSmashEffect(pos, radius)
				local ts = game:GetService("TweenService")
				
				-- 1. 땅 패임 (크레이터 흉내)
				local crater = Instance.new("Part")
				crater.Name = "Crater"
				crater.Shape = Enum.PartType.Cylinder
				crater.Size = Vector3.new(0.2, radius * 1.5, radius * 1.5)
				crater.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
				crater.Anchored = true
				crater.CanCollide = false
				crater.Material = Enum.Material.Slate
				crater.Color = Color3.fromRGB(30, 30, 30)
				crater.Parent = workspace
				ts:Create(crater, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.0), {Transparency = 1}):Play()
				game:GetService("Debris"):AddItem(crater, 3.5)
				
				-- 2. 묵직한 타격음 (사운드 객체를 찾아서 클론하거나 기본 폭발음 사용)
				local sfx = nil
				local customSound = game.ReplicatedStorage:FindFirstChild("Assets") 
					and game.ReplicatedStorage.Assets:FindFirstChild("Sounds")
					and game.ReplicatedStorage.Assets.Sounds:FindFirstChild("Monster")
					and game.ReplicatedStorage.Assets.Sounds.Monster:FindFirstChild("BigGolem_Smash")
					
				if customSound and customSound:IsA("Sound") then
					sfx = customSound:Clone()
					sfx.Parent = crater
				else
					sfx = Instance.new("Sound")
					sfx.SoundId = "rbxassetid://142070127" -- 기본 폭발 사운드로 교체
					sfx.PlaybackSpeed = 0.6
					sfx.Volume = 2.0
					sfx.Parent = crater
				end
				
				sfx.RollOffMaxDistance = 150
				sfx:Play()
				
				-- 3. 파편 (Debris) 튀기기
				for i = 1, 10 do
					local rock = Instance.new("Part")
					rock.Size = Vector3.new(math.random(2,4), math.random(2,4), math.random(2,4))
					rock.Position = pos + Vector3.new(math.random(-2,2), 2, math.random(-2,2))
					rock.Material = Enum.Material.Slate
					rock.Color = Color3.fromRGB(100, 100, 100)
					rock.CanCollide = true
					rock.Anchored = false
					rock.Parent = workspace
					
					local angle = math.random() * math.pi * 2
					local speed = math.random(40, 80)
					rock.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * speed, math.random(50, 100), math.sin(angle) * speed)
					rock.AssemblyAngularVelocity = Vector3.new(math.random(-20,20), math.random(-20,20), math.random(-20,20))
					
					ts:Create(rock, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {Transparency = 1}):Play()
					game:GetService("Debris"):AddItem(rock, 3.0)
				end
				
				-- 4. 흙먼지 (Smoke)
				local smokePart = Instance.new("Part")
				smokePart.Size = Vector3.new(1,1,1)
				smokePart.Position = pos
				smokePart.Anchored = true
				smokePart.CanCollide = false
				smokePart.Transparency = 1
				smokePart.Parent = workspace
				local smoke = Instance.new("Smoke")
				smoke.Color = Color3.fromRGB(120, 110, 100)
				smoke.Size = radius * 0.8
				smoke.Opacity = 0.5
				smoke.RiseVelocity = 15
				smoke.Parent = smokePart
				game:GetService("Debris"):AddItem(smokePart, 3)
				task.delay(0.4, function() if smoke then smoke.Enabled = false end end)
				
				-- 5. 확산되는 충격파 고리
				local shockwave = Instance.new("Part")
				shockwave.Name = "RockShockwave"
				shockwave.Shape = Enum.PartType.Cylinder
				shockwave.Size = Vector3.new(0.5, 1, 1)
				shockwave.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
				shockwave.Anchored = true
				shockwave.CanCollide = false
				shockwave.Material = Enum.Material.Slate
				shockwave.Color = Color3.fromRGB(130, 130, 130)
				shockwave.Parent = workspace
				ts:Create(shockwave, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.5, radius * 2, radius * 2),
					Transparency = 1
				}):Play()
				game:GetService("Debris"):AddItem(shockwave, 0.5)
			end

			-- [스텀프 킹 전용] 자연 대지 나무 타격 이펙트 함수
			local function playWoodSmashEffect(pos, radius)
				local ts = game:GetService("TweenService")
				
				-- 1. 나무 잔디 고리 이펙트
				local crater = Instance.new("Part")
				crater.Name = "WoodCrater"
				crater.Shape = Enum.PartType.Cylinder
				crater.Size = Vector3.new(0.2, radius * 1.5, radius * 1.5)
				crater.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
				crater.Anchored = true
				crater.CanCollide = false
				crater.Material = Enum.Material.Grass
				crater.Color = Color3.fromRGB(46, 110, 30) -- 무성한 잔디색
				crater.Parent = workspace
				ts:Create(crater, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
				game:GetService("Debris"):AddItem(crater, 3.5)
				
				-- 2. 타격음
				local sfx = Instance.new("Sound")
				sfx.SoundId = "rbxassetid://142070127" -- 묵직한 폭발음 베이스
				sfx.PlaybackSpeed = 0.55 -- 더 무겁고 낮은 톤
				sfx.Volume = 2.2
				sfx.RollOffMaxDistance = 150
				sfx.Parent = crater
				sfx:Play()
				
				-- 3. 나무 파편(Wood Debris) 튀기기
				for i = 1, 12 do
					local wood = Instance.new("Part")
					wood.Size = Vector3.new(math.random(2, 4), math.random(2, 4), math.random(2, 4))
					wood.Position = pos + Vector3.new(math.random(-3, 3), 2, math.random(-3, 3))
					wood.Material = Enum.Material.Wood
					wood.Color = Color3.fromRGB(110, 75, 35) -- 나무색
					wood.CanCollide = true
					wood.Anchored = false
					wood.Parent = workspace
					
					local angle = math.random() * math.pi * 2
					local speed = math.random(40, 80)
					wood.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * speed, math.random(50, 100), math.sin(angle) * speed)
					wood.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
					
					ts:Create(wood, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
					game:GetService("Debris"):AddItem(wood, 3.0)
				end
				
				-- 4. 무성한 나뭇잎 가루 (Green particles)
				local leafPart = Instance.new("Part")
				leafPart.Size = Vector3.new(1, 1, 1)
				leafPart.Position = pos
				leafPart.Anchored = true
				leafPart.CanCollide = false
				leafPart.Transparency = 1
				leafPart.Parent = workspace
				
				local pe = Instance.new("ParticleEmitter")
				pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
				pe.Color = ColorSequence.new(Color3.fromRGB(34, 139, 34), Color3.fromRGB(144, 238, 144))
				pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0)})
				pe.Transparency = NumberSequence.new(0.4, 1)
				pe.Lifetime = NumberRange.new(0.8, 1.5)
				pe.Rate = 60
				pe.Speed = NumberRange.new(10, 30)
				pe.SpreadAngle = Vector2.new(90, 90)
				pe.Parent = leafPart
				
				game:GetService("Debris"):AddItem(leafPart, 3)
				task.delay(0.4, function() if pe then pe.Enabled = false end end)
				
				-- 5. 확산되는 나뭇잎 녹색 충격파 고리
				local shockwave = Instance.new("Part")
				shockwave.Name = "WoodShockwave"
				shockwave.Shape = Enum.PartType.Cylinder
				shockwave.Size = Vector3.new(0.5, 1, 1)
				shockwave.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
				shockwave.Anchored = true
				shockwave.CanCollide = false
				shockwave.Material = Enum.Material.Neon
				shockwave.Color = Color3.fromRGB(60, 150, 40) -- 형광 초록빛 대지의 충격파
				shockwave.Parent = workspace
				ts:Create(shockwave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.5, radius * 2, radius * 2),
					Transparency = 1
				}):Play()
				game:GetService("Debris"):AddItem(shockwave, 0.5)
			end

			while isAlive and humanoid and humanoid.Parent and model:FindFirstChild("HumanoidRootPart") do
				local hrp = model.HumanoidRootPart
				
				-- [푸른불꽃 기사 특수 기믹]: 체력 1만 이하 도달 시 몸을 휘감는 신비로운 푸른 불꽃 이펙트 활성화
				if config.mobModelName == "BlueFlameKnight" and humanoid.Health <= 10000 and not bfkPhase2Active then
					bfkPhase2Active = true
					print("[MobSpawnService] Blue Flame Knight health below 10,000! Activating Phase 2 blue flame aura.")
					
					-- 페이즈 2 각성 폭발음 재생 연동
					pcall(function()
						local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
						local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
						local phaseSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_PhaseTransition")
						if phaseSound then
							local s = phaseSound:Clone()
							s.Parent = hrp
							s:Play()
							game:GetService("Debris"):AddItem(s, 6)
						end
					end)
					
					-- 보스 파트마다 푸른 불꽃 이미터 추가
					local function attachBlueFlame(part)
						local pe = Instance.new("ParticleEmitter")
						pe.Name = "BlueFlameAura"
						pe.Texture = "rbxasset://textures/particles/fire_main.dds"
						pe.Color = ColorSequence.new(Color3.fromRGB(0, 100, 255), Color3.fromRGB(0, 200, 255))
						pe.Size = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1.5),
							NumberSequenceKeypoint.new(0.5, 3.5),
							NumberSequenceKeypoint.new(1, 0)
						})
						pe.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.2),
							NumberSequenceKeypoint.new(0.8, 0.5),
							NumberSequenceKeypoint.new(1, 1.0)
						})
						pe.Rate = 35
						pe.Speed = NumberRange.new(2, 5)
						pe.Lifetime = NumberRange.new(0.6, 1.0)
						pe.SpreadAngle = Vector2.new(45, 45)
						pe.ZOffset = 0.3
						pe.EmissionDirection = Enum.NormalId.Top
						pe.Parent = part
						table.insert(bfkAuraEmitters, pe)
					end
					
					for _, child in ipairs(model:GetChildren()) do
						if child:IsA("BasePart") then
							attachBlueFlame(child)
						end
					end
				end

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
					
					if config.mobModelName == "Stump" then
						--========================================================================
						-- [Stump 전용 FSM 분기]: 이동 -> (근접/마법 교대 공격) FSM 순환
						--========================================================================
						
						-- 1. 이동 단계 (Move)
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local dir = (targetPlayerPos - currentPos)
						local dirUnit = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
						
						-- 일반 근접공격을 위해 타겟팅 거리를 6스터드로 좁힘
						local moveTargetPos = targetPlayerPos - dirUnit * 6
						
						-- 둥지 경계 CAMP_RADIUS = 35 클램프
						local CAMP_RADIUS = 35
						local distFromCenter = (moveTargetPos - spawnCenter).Magnitude
						if distFromCenter > CAMP_RADIUS then
							moveTargetPos = spawnCenter + (moveTargetPos - spawnCenter).Unit * CAMP_RADIUS
						end
						
						-- Y축 고정
						moveTargetPos = Vector3.new(moveTargetPos.X, currentPos.Y, moveTargetPos.Z)
						
						-- 플레이어와의 거리가 너무 멀거나 어긋날 때 이동 실행
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						if distToPlayer > 8 or (currentPos - moveTargetPos).Magnitude > 3 then
							humanoid:MoveTo(moveTargetPos)
							
							local arrived = false
							local conn = humanoid.MoveToFinished:Connect(function() arrived = true end)
							local moveStartTime = os.clock()
							
							local stuckFrames = 0
							while not arrived and os.clock() - moveStartTime < 1.5 and isAlive do
								task.wait(0.1)
								
								-- [전투 벽걸림 우회 Flanking AI]
								local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
								if speed < 0.6 and humanoid.MoveDirection.Magnitude > 0.1 then
									stuckFrames = stuckFrames + 1
									if stuckFrames > 4 then -- 약 0.4초간 공격 대상을 향해 가다 벽에 가로막히면
										-- 좌/우측 방향으로 비껴서 크게 회피 우회로를 탐색하여 진입
										local flankDirection = hrp.CFrame.RightVector * (math.random() > 0.5 and 16 or -16) - hrp.CFrame.LookVector * 4
										local escapeTarget = hrp.Position + flankDirection
										humanoid:MoveTo(escapeTarget)
										task.wait(0.6) -- 0.6초간 급속 플랭킹 탈출
										break -- 대기 상태로 이양하여 루프 해제
									end
								else
									stuckFrames = 0
								end
							end
							if conn then conn:Disconnect() end
							humanoid:MoveTo(hrp.Position) -- 이동 멈춤
						end
						
						-- 이동 완료 후 0.3초 대기
						task.wait(0.3)
						
						if not isAlive or not targetPlayer.Parent or not phrp.Parent then
							task.wait(TICK_RATE)
							continue
						end
						
						-- 2. 캐스팅 및 공격 단계
						local now = os.clock()
						local cooldown = config.attackCooldown or 3.0
						if now - lastAttackTick >= cooldown then
							lastAttackTick = now
							
							-- [수정] 일반 근접 공격을 전면 제외하고, 100% 특수 대지 마법 공격만 가하도록 설계!
							local isMagicAttack = true
							
							if isMagicAttack then
								-- [스텀프 특수 마법 패턴 - 대지 나무 솟구치기]
								local telegraphDuration = 1.0
								local targetFloorPos = phrp.Position
								
								-- 지면 레이캐스트
								local raycastParams = RaycastParams.new()
								raycastParams.FilterType = Enum.RaycastFilterType.Exclude
								raycastParams.FilterDescendantsInstances = {model, targetPlayer}
								
								local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), raycastParams)
								if rayResult then
									targetFloorPos = rayResult.Position
								else
									targetFloorPos = targetFloorPos - Vector3.new(0, phrp.Size.Y / 2 + 0.1, 0)
								end
								
								-- 나무 경판 예고 이펙트 생성 (어스 브라운 톤)
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "StumpTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, 24, 24) -- 공격 범위 12스터드 반경 (지름 24)으로 확장
								warnCircle.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.CanTouch = false
								warnCircle.CanQuery = false
								warnCircle.CastShadow = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(110, 80, 30) -- 어스 브라운 톤
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								-- [Stump_Magic 애니메이션 재생]
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
									if animator then
										local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
										local animsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
										local monsterAnims = animsFolder and animsFolder:FindFirstChild("Monster")
										local attackAnim = monsterAnims and monsterAnims:FindFirstChild("Stump_Magic")
										if attackAnim then
											local attackTrack = animator:LoadAnimation(attackAnim)
											if attackTrack then
												attackTrack.Priority = Enum.AnimationPriority.Action
												attackTrack.Looped = false
												attackTrack:Play()
											end
										end
									end
								end)

								local castStartTime = os.clock()
								local ts = game:GetService("TweenService")
								local flashTween = ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 0.4,
									Color = Color3.fromRGB(70, 110, 50) -- 나무느낌에 맞춘 초록/갈색 점멸
								})
								flashTween:Play()
								
								-- 1.0초 캐스팅 동안 정렬 회전
								while os.clock() - castStartTime < telegraphDuration and isAlive do
									if phrp and phrp.Parent then
										local lookDir = (phrp.Position - hrp.Position)
										lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
										if lookDir.Magnitude > 0.1 then
											hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
										end
									end
									task.wait(0.05)
								end
								
								warnCircle:Destroy()
								if not isAlive then break end
								
								-- 땅에서 솟구치는 명품 나무 기둥 (나무 질감 갈색 기둥 + 풍성한 풀잎 녹색 구체 연합 이펙트)
								local attackPos = targetFloorPos
								
								local magicSpikeModel = Instance.new("Model")
								magicSpikeModel.Name = "MagicTreeSpike"
								
								-- A. 나무 둥치 (갈색 실린더 - 나무 재질 반영)
								local trunk = Instance.new("Part")
								trunk.Name = "Trunk"
								trunk.Shape = Enum.PartType.Cylinder
								trunk.Size = Vector3.new(12, 3, 3) -- 지름 3스터드짜리 튼튼한 나무
								trunk.Color = Color3.fromRGB(100, 65, 30) -- 리치 딥 브라운
								trunk.Material = Enum.Material.Wood
								trunk.CanCollide = false
								trunk.Anchored = true
								trunk.Parent = magicSpikeModel
								
								-- B. 무성한 나뭇잎 구체 1 (가운데 상단)
								local leaf1 = Instance.new("Part")
								leaf1.Shape = Enum.PartType.Ball
								leaf1.Size = Vector3.new(5.5, 5.5, 5.5)
								leaf1.Color = Color3.fromRGB(34, 139, 34) -- 깊은 나뭇잎 녹색
								leaf1.Material = Enum.Material.Grass
								leaf1.CanCollide = false
								leaf1.Anchored = true
								leaf1.Parent = magicSpikeModel
								
								-- C. 무성한 나뭇잎 구체 2 (좌측)
								local leaf2 = Instance.new("Part")
								leaf2.Shape = Enum.PartType.Ball
								leaf2.Size = Vector3.new(4, 4, 4)
								leaf2.Color = Color3.fromRGB(46, 170, 46) -- 연한 하이라이트 녹색
								leaf2.Material = Enum.Material.Grass
								leaf2.CanCollide = false
								leaf2.Anchored = true
								leaf2.Parent = magicSpikeModel
								
								-- D. 무성한 나뭇잎 구체 3 (우측)
								local leaf3 = Instance.new("Part")
								leaf3.Shape = Enum.PartType.Ball
								leaf3.Size = Vector3.new(4, 4, 4)
								leaf3.Color = Color3.fromRGB(20, 100, 25) -- 어두운 나뭇잎 그늘 녹색
								leaf3.Material = Enum.Material.Grass
								leaf3.CanCollide = false
								leaf3.Anchored = true
								leaf3.Parent = magicSpikeModel
								
								-- 일관적인 위치 보정 함수 (트윈/수학적 루프 연산용)
								local function updateSpikeCF(centerPos, verticalOffset)
									local baseCF = CFrame.new(centerPos + Vector3.new(0, verticalOffset, 0))
									trunk.CFrame = baseCF * CFrame.Angles(0, 0, math.rad(90))
									leaf1.CFrame = baseCF * CFrame.new(0, 6, 0) -- 기둥 꼭대기
									leaf2.CFrame = baseCF * CFrame.new(-1.8, 3.5, 1.2) -- 좌측 가지
									leaf3.CFrame = baseCF * CFrame.new(1.8, 4.0, -1.2) -- 우측 가지
								end
								
								-- 초기 지면 아래 위치
								updateSpikeCF(attackPos, -7)
								magicSpikeModel.Parent = workspace
								
								-- 지면 위로 빠르게 솟아오르는 백 트윈 연출 (0.2초)
								local popStartTime = os.clock()
								local popDuration = 0.2
								while os.clock() - popStartTime < popDuration do
									local alpha = (os.clock() - popStartTime) / popDuration
									local backAlpha = 1 - (1 - alpha)^3 -- Cubic Out 방식으로 부드럽고 강한 솟구침
									local currentYOffset = -7 + (5.5 - (-7)) * backAlpha
									updateSpikeCF(attackPos, currentYOffset)
									task.wait()
								end
								updateSpikeCF(attackPos, 5.5) -- 최종 위치 고정
								
								if isAlive then
									local exp = Instance.new("Explosion")
									exp.BlastRadius = 12 -- 폭발 범위 12스터드로 확장
									exp.BlastPressure = 0
									exp.Position = attackPos
									exp.ExplosionType = Enum.ExplosionType.NoCraters
									exp.Parent = workspace
									
									-- 광역 피해 판정 및 넉백
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										
										if phum and phum.Health > 0 and pRoot then
											local dist = (pRoot.Position - attackPos).Magnitude
											if dist <= 12 then -- 피해 반경 12스터드로 확장
												phum:TakeDamage(config.baseDamage or 25)
												
												local bounceDir = (pRoot.Position - attackPos)
												bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
												local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
												local NetController = require(Controllers:WaitForChild("NetController"))
												NetController.FireClient(p, "Player.Stun", bounceDir)
												
												task.spawn(function()
													local highlight = Instance.new("Highlight")
													highlight.Name = "DamageFlash"
													highlight.FillColor = Color3.fromRGB(255, 0, 0)
													highlight.OutlineColor = Color3.fromRGB(255, 100, 100)
													highlight.FillTransparency = 0.4
													highlight.OutlineTransparency = 0
													highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
													highlight.Adornee = char
													highlight.Parent = char
													
													task.wait(0.12)
													if highlight and highlight.Parent then
														highlight:Destroy()
													end
												end)
											end
										end
									end
								end
								
								task.wait(0.6)
								
								-- 나무 가시를 부드럽게 지면 밑으로 회수
								local pullStartTime = os.clock()
								local pullDuration = 0.4
								while os.clock() - pullStartTime < pullDuration do
									local alpha = (os.clock() - pullStartTime) / pullDuration
									local easeAlpha = alpha * alpha -- Quad In 방식으로 안착
									local currentYOffset = 5.5 - (5.5 - (-7)) * easeAlpha
									updateSpikeCF(attackPos, currentYOffset)
									task.wait()
								end
								magicSpikeModel:Destroy()
								
								task.wait(1.0)
							else
								-- [스텀프 일반 근접 물리 공격 패턴 - 예고 이펙트 추가!]
								local meleeTelegraphPos = phrp.Position
								local raycastParams = RaycastParams.new()
								raycastParams.FilterType = Enum.RaycastFilterType.Exclude
								raycastParams.FilterDescendantsInstances = {model, targetPlayer}
								
								local rayResult = workspace:Raycast(meleeTelegraphPos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), raycastParams)
								if rayResult then
									meleeTelegraphPos = rayResult.Position
								else
									meleeTelegraphPos = meleeTelegraphPos - Vector3.new(0, phrp.Size.Y / 2 + 0.1, 0)
								end

								local meleeWarn = Instance.new("Part")
								meleeWarn.Name = "StumpMeleeTelegraph"
								meleeWarn.Shape = Enum.PartType.Cylinder
								meleeWarn.Size = Vector3.new(0.4, 24, 24) -- 근접 공격 범위 12스터드 반경 (지름 24)
								meleeWarn.CFrame = CFrame.new(meleeTelegraphPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
								meleeWarn.Anchored = true
								meleeWarn.CanCollide = false
								meleeWarn.CanTouch = false
								meleeWarn.CanQuery = false
								meleeWarn.CastShadow = false
								meleeWarn.Material = Enum.Material.Neon
								meleeWarn.Color = Color3.fromRGB(255, 50, 50) -- 근거리 타격은 붉은 경고로 명확하게 표시!
								meleeWarn.Transparency = 0.85
								meleeWarn.Parent = workspace

								local ts = game:GetService("TweenService")
								ts:Create(meleeWarn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 0.4,
									Color = Color3.fromRGB(180, 0, 0)
								}):Play()

								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
									if animator then
										local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
										local animsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
										local monsterAnims = animsFolder and animsFolder:FindFirstChild("Monster")
										local attackAnim = monsterAnims and monsterAnims:FindFirstChild("Stump_Attack")
										if attackAnim then
											local attackTrack = animator:LoadAnimation(attackAnim)
											if attackTrack then
												attackTrack.Priority = Enum.AnimationPriority.Action
												attackTrack.Looped = false
												attackTrack:Play()
											end
										end
									end
								end)
								
								task.wait(0.3)
								meleeWarn:Destroy()
								
								if isAlive and phrp and phum and phum.Health > 0 then
									local dist = (hrp.Position - phrp.Position).Magnitude
									if dist <= 12 then
										phum:TakeDamage(config.baseDamage or 25)
										
										local bounceDir = (phrp.Position - hrp.Position)
										bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
										local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
										local NetController = require(Controllers:WaitForChild("NetController"))
										local playerObj = game.Players:GetPlayerFromCharacter(targetPlayer)
										if playerObj then
											NetController.FireClient(playerObj, "Player.Stun", bounceDir)
										end
										
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
								
								task.wait(1.0)
							end
						end

					elseif config.mobModelName == "CyclopsBat" then
						--========================================================================
						-- [CyclopsBat 전용 FSM 분기]: 원거리 눈 검은 레이저 공격 (경고 장판 선출력)
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()
						
						-- 원거리 타겟팅 범위는 55스터드 설정
						local RANGE_ATTACK_DIST = 55
						local laserCooldown = config.attackCooldown or 1.5
						
						-- 플레이어를 향해 서서히 이동 또는 바라보기
						-- 공중 몬스터이므로, 일정 거리 이상 떨어져있으면 다가감
						if distToPlayer > 30 then
							humanoid:MoveTo(targetPlayerPos)
						else
							humanoid:MoveTo(hrp.Position) -- 제자리 유지
						end
						
						-- 플레이어 정면 응시
						local lookDir = (targetPlayerPos - currentPos)
						lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
						if lookDir.Magnitude > 0.1 then
							hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
						end
						
						if distToPlayer <= RANGE_ATTACK_DIST and (now - lastAttackTick >= laserCooldown) then
							lastAttackTick = now
							
							-- 공격 경고 범위표시 (선행 출력)
							local telegraphDuration = 0.8 -- 경고 시간
							local targetFloorPos = targetPlayerPos
							
							-- 지면 레이캐스트를 통해 바닥에 경고 표시 안착
							local raycastParams = RaycastParams.new()
							raycastParams.FilterType = Enum.RaycastFilterType.Exclude
							raycastParams.FilterDescendantsInstances = {model, targetPlayer}
							
							local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), raycastParams)
							if rayResult then
								targetFloorPos = rayResult.Position
							else
								targetFloorPos = targetFloorPos - Vector3.new(0, phrp.Size.Y / 2 + 0.1, 0)
							end
							
							-- 검은색/보라색 계열 경고 장판 생성
							local warnCircle = Instance.new("Part")
							warnCircle.Name = "CyclopsBatTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, 18, 18) -- 반경 9스터드 (지름 18)
							warnCircle.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.CanTouch = false
							warnCircle.CanQuery = false
							warnCircle.CastShadow = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = Color3.fromRGB(40, 0, 80) -- 딥 다크 퍼플
							warnCircle.Transparency = 0.8
							warnCircle.Parent = workspace
							
							-- 점멸 트윈
							local ts = game:GetService("TweenService")
							ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
								Transparency = 0.3,
								Color = Color3.fromRGB(10, 10, 10) -- 최종적으로 검은색에 가까워짐
							}):Play()
							
							-- 눈 충전용 구체 이펙트 (검은색/자색 네온 기운)
							local headPart = model:FindFirstChild("Head") or model:FindFirstChild("Eye") or hrp
							local chargeSphere = Instance.new("Part")
							chargeSphere.Shape = Enum.PartType.Ball
							chargeSphere.Size = Vector3.new(1.0, 1.0, 1.0)
							chargeSphere.Color = Color3.fromRGB(0, 0, 0)
							chargeSphere.Material = Enum.Material.Neon
							chargeSphere.Anchored = true
							chargeSphere.CanCollide = false
							chargeSphere.CFrame = headPart.CFrame * CFrame.new(0, 0, -1) -- 정면 눈 위치 즈음
							chargeSphere.Parent = workspace
							
							ts:Create(chargeSphere, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Elastic), {
								Size = Vector3.new(2.5, 2.5, 2.5)
							}):Play()
							
							-- 충전 사운드 재생 시도
							pcall(function()
								local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
								local castSound = monsterSounds and (monsterSounds:FindFirstChild("Stump_Magic") or monsterSounds:FindFirstChild("BlueFlameKnight_Spell"))
								if castSound then
									local s = castSound:Clone()
									s.PlaybackSpeed = 1.5
									s.Volume = 1.2
									s.Parent = chargeSphere
									s:Play()
								end
							end)
							
							-- 0.8초 동안 기 모으면서 정렬 회전
							local castStartTime = os.clock()
							while os.clock() - castStartTime < telegraphDuration and isAlive do
								if phrp and phrp.Parent then
									local lookDir = (phrp.Position - hrp.Position)
									lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
									if lookDir.Magnitude > 0.1 then
										hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
									end
									chargeSphere.CFrame = headPart.CFrame * CFrame.new(0, 0, -1)
								end
								task.wait(0.05)
							end
							
							warnCircle:Destroy()
							chargeSphere:Destroy()
							
							if isAlive and phrp and phrp.Parent then
								-- 눈에서 검은 레이저 발사!
								local startLaserPos = headPart.Position
								local endLaserPos = targetFloorPos
								
								-- 레이저를 연결하는 원기둥 생성 (검은색 / 퍼플 아웃라인)
								local laserModel = Instance.new("Model")
								laserModel.Name = "EyeLaserModel"
								
								local laserCore = Instance.new("Part")
								laserCore.Name = "LaserCore"
								laserCore.Material = Enum.Material.Neon
								laserCore.Color = Color3.fromRGB(0, 0, 0) -- 완벽한 검은색 레이저 코어
								laserCore.CanCollide = false
								laserCore.Anchored = true
								laserCore.Parent = laserModel
								
								local laserAura = Instance.new("Part")
								laserAura.Name = "LaserAura"
								laserAura.Material = Enum.Material.Neon
								laserAura.Color = Color3.fromRGB(75, 0, 130) -- 어두운 자색 아우라
								laserAura.CanCollide = false
								laserAura.Anchored = true
								laserAura.Transparency = 0.4
								laserAura.Parent = laserModel
								
								local function updateLaserVisual(p1, p2, width)
									local distance = (p1 - p2).Magnitude
									laserCore.Size = Vector3.new(width, distance, width)
									laserCore.CFrame = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -distance / 2) * CFrame.Angles(math.rad(90), 0, 0)
									
									laserAura.Size = Vector3.new(width * 1.5, distance, width * 1.5)
									laserAura.CFrame = laserCore.CFrame
								end
								
								updateLaserVisual(startLaserPos, endLaserPos, 1.2)
								laserModel.Parent = workspace
								
								-- 콰쾅! 폭발 연출
								local exp = Instance.new("Explosion")
								exp.BlastRadius = 9
								exp.BlastPressure = 0
								exp.Position = endLaserPos
								exp.ExplosionType = Enum.ExplosionType.NoCraters
								exp.Parent = workspace
								
								-- 타격 및 사운드
								pcall(function()
									local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
									local hitSound = monsterSounds and (monsterSounds:FindFirstChild("BigGolem_Smash") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if hitSound then
										local s = hitSound:Clone()
										s.PlaybackSpeed = 1.8
										s.Volume = 1.5
										s.Parent = laserCore
										s:Play()
									end
								end)
								
								-- 데미지 판정
								for _, p in ipairs(Players:GetPlayers()) do
									local char = p.Character
									local phum = char and char:FindFirstChild("Humanoid")
									local pRoot = char and char:FindFirstChild("HumanoidRootPart")
									if phum and phum.Health > 0 and pRoot then
										local dist = (pRoot.Position - endLaserPos).Magnitude
										if dist <= 9 then
											phum:TakeDamage(config.baseDamage or 35)
											
											local bounceDir = (pRoot.Position - endLaserPos)
											bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
											local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
											local NetController = require(Controllers:WaitForChild("NetController"))
											NetController.FireClient(p, "Player.Stun", bounceDir * 1.5)
											
											task.spawn(function()
												local highlight = Instance.new("Highlight")
												highlight.Name = "DamageFlash"
												highlight.FillColor = Color3.fromRGB(0, 0, 0) -- 검은 레이저 피격의 맛
												highlight.OutlineColor = Color3.fromRGB(150, 0, 255)
												highlight.FillTransparency = 0.5
												highlight.OutlineTransparency = 0
												highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
												highlight.Adornee = char
												highlight.Parent = char
												
												task.wait(0.12)
												if highlight and highlight.Parent then
													highlight:Destroy()
												end
											end)
										end
									end
								end
								
								-- 레이저를 0.3초간 점점 투명하고 얇게 만들면서 사라지게 트윈
								local fadeStartTime = os.clock()
								local fadeDuration = 0.3
								while os.clock() - fadeStartTime < fadeDuration do
									local progress = (os.clock() - fadeStartTime) / fadeDuration
									local currentWidth = 1.2 * (1 - progress)
									laserCore.Transparency = progress
									laserAura.Transparency = 0.4 + 0.6 * progress
									updateLaserVisual(startLaserPos, endLaserPos, currentWidth)
									task.wait()
								end
								
								laserModel:Destroy()
							end
							
							task.wait(0.5)
						end

					elseif config.mobModelName == "StumpKing" then
						--========================================================================
						-- [StumpKing 전용 FSM 분기]: 다가가기 -> 제자리 점프 광역(우선) -> 나무 둥치 낙하
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						
						local now = os.clock()
						local rockCooldown = config.attackCooldown or 5.0
						local jumpCooldown = 8.0
						
						-- 우선순위 1: 대지 붕괴 점프 패턴 (보스 덩치가 매우 크므로 거리가 35 이하일 때 발동)
						if distToPlayer <= 35 and (now - lastJumpTick >= jumpCooldown) then
							lastJumpTick = now
							humanoid:MoveTo(hrp.Position) -- 정지
							
							-- 1. 예고 장판 (반경 30스터드)
							local warnCircle = Instance.new("Part")
							warnCircle.Name = "StumpKingJumpTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, 60, 60)
							warnCircle.CFrame = CFrame.new(currentPos - Vector3.new(0, humanoid.HipHeight + hrp.Size.Y/2 - 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = Color3.fromRGB(110, 80, 30) -- 대지 브라운 경고
							warnCircle.Transparency = 0.85
							warnCircle.Parent = workspace
							
							local ts = game:GetService("TweenService")
							ts:Create(warnCircle, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
								Transparency = 0.4,
								Color = Color3.fromRGB(70, 110, 50) -- 나무빛 녹색으로 점멸
							}):Play()
							
							-- 애니메이션 (Stump 에셋 기반이므로 Stump_Magic/Stump_Attack 시도)
							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("StumpKing_Jump") or anims.Monster:FindFirstChild("StumpKing_Attack") or anims.Monster:FindFirstChild("Stump_Magic"))
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									if track then track:Play() end
								end
							end)
							
							-- 공중으로 떠오르기
							local jumpHeight = currentPos + Vector3.new(0, 20, 0)
							ts:Create(hrp, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = CFrame.new(jumpHeight)}):Play()
							task.wait(0.5)
							
							-- 공중 체공
							task.wait(0.2)
							
							-- 내려찍기
							warnCircle:Destroy()
							local landPos = currentPos
							local fallTween = ts:Create(hrp, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = CFrame.new(landPos)})
							fallTween:Play()
							fallTween.Completed:Wait()
							
							local groundPos = landPos - Vector3.new(0, humanoid.HipHeight + (hrp.Size.Y / 2), 0)
							
							-- 폭발 데미지 판정
							local exp = Instance.new("Explosion")
							exp.BlastRadius = 30
							exp.BlastPressure = 0
							exp.Position = groundPos
							exp.ExplosionType = Enum.ExplosionType.NoCraters
							exp.Visible = false
							exp.Parent = workspace
							
							-- 자연 나뭇잎 충격파 효과 실행
							playWoodSmashEffect(groundPos, 35)
							
							for _, p in ipairs(Players:GetPlayers()) do
								local char = p.Character
								local phum = char and char:FindFirstChild("Humanoid")
								local pRoot = char and char:FindFirstChild("HumanoidRootPart")
								if phum and phum.Health > 0 and pRoot then
									-- XZ 평면 거리 계산 (지진파 형태이므로 원기둥 판정)
									local distXZ = Vector3.new(pRoot.Position.X - groundPos.X, 0, pRoot.Position.Z - groundPos.Z).Magnitude
									if distXZ <= 30 then
										-- [점프 회피 로직] 플레이어 중심이 바닥 기준 7 스터드 이상 높다면 회피 성공
										local heightDiff = pRoot.Position.Y - groundPos.Y
										if heightDiff > 7.0 then
											-- 타이밍 맞춰 점프함 (데미지 무시)
										else
											phum:TakeDamage(config.baseDamage or 50)
											local bounceDir = (pRoot.Position - groundPos)
											bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
											local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
											local NetController = require(Controllers:WaitForChild("NetController"))
											NetController.FireClient(p, "Player.Stun", bounceDir)
										end
									end
								end
							end
							task.wait(1.0)
							
						-- 우선순위 2: 하늘 나무 둥치 낙하 패턴 (쿨타임이 찼을 때)
						elseif now - lastAttackTick >= rockCooldown then
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position) -- 정지
							
							-- 연속 둥치 소환 (1~4번 랜덤)
							local dropCount = math.random(1, 4)
							local ts = game:GetService("TweenService")
							
							-- 공격 애니메이션 1회 재생
							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("StumpKing_Attack") or anims.Monster:FindFirstChild("StumpKing_Magic") or anims.Monster:FindFirstChild("Stump_Magic"))
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									if track then track:Play() end
								end
							end)
							
							for i = 1, dropCount do
								if not isAlive then break end
								
								-- 현재 플레이어 위치 기반으로 바닥 좌표 구하기 (계속 추적)
								local currentTargetPos = targetPlayerPos
								if phrp and phrp.Parent then currentTargetPos = phrp.Position end
								
								-- 보스가 플레이어를 바라보게 회전
								local lookDir = Vector3.new(currentTargetPos.X - hrp.Position.X, 0, currentTargetPos.Z - hrp.Position.Z)
								if lookDir.Magnitude > 0.1 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
								end
								
								local targetFloorPos = currentTargetPos
								local raycastParams = RaycastParams.new()
								raycastParams.FilterType = Enum.RaycastFilterType.Exclude
								raycastParams.FilterDescendantsInstances = {model, targetPlayer}
								local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), raycastParams)
								if rayResult then targetFloorPos = rayResult.Position else targetFloorPos = targetFloorPos - Vector3.new(0, phrp.Size.Y / 2, 0) end
								
								-- 예고 장판 (반경 12스터드로 축소)
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "StumpKingTrunkTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, 24, 24)
								warnCircle.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(70, 110, 50) -- 나무빛 초록 장판
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								ts:Create(warnCircle, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								-- 0.5초 대기 (회피 시간)
								task.wait(0.5)
								warnCircle:Destroy()
								if not isAlive then break end
								
								-- 나무 둥치 모델 생성 (대형 통나무)
								local trunk = Instance.new("Part")
								trunk.Name = "FallingTrunk"
								trunk.Shape = Enum.PartType.Cylinder
								trunk.Size = Vector3.new(16, 4, 4) -- 거대한 통나무 형태
								trunk.Color = Color3.fromRGB(100, 65, 30) -- 나무색
								trunk.Material = Enum.Material.Wood
								trunk.CanCollide = false
								trunk.Anchored = true
								
								-- 하늘에서 서서히 돌면서 떨어지는 CFrame 연출
								local startPos = targetFloorPos + Vector3.new(0, 40, 0)
								trunk.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
								trunk.Parent = workspace
								
								local fallTween = ts:Create(trunk, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									CFrame = CFrame.new(targetFloorPos) * CFrame.Angles(math.rad(45), math.rad(45), math.rad(90))
								})
								fallTween:Play()
								task.wait(0.3)
								trunk:Destroy()
								
								if isAlive then
									local exp = Instance.new("Explosion")
									exp.BlastRadius = 12
									exp.BlastPressure = 0
									exp.Position = targetFloorPos
									exp.ExplosionType = Enum.ExplosionType.NoCraters
									exp.Visible = false
									exp.Parent = workspace
									
									-- 자연 나무 파쇄 효과 실행
									playWoodSmashEffect(targetFloorPos, 15)
									
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											if (pRoot.Position - targetFloorPos).Magnitude <= 12 then
												phum:TakeDamage(config.baseDamage or 50)
												local bounceDir = Vector3.new(pRoot.Position.X - targetFloorPos.X, 0, pRoot.Position.Z - targetFloorPos.Z).Unit
												local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
												local NetController = require(Controllers:WaitForChild("NetController"))
												NetController.FireClient(p, "Player.Stun", bounceDir)
												
												task.spawn(function()
													local highlight = Instance.new("Highlight")
													highlight.Name = "DamageFlash"
													highlight.FillColor = Color3.fromRGB(34, 139, 34) -- 나무 데미지색
													highlight.OutlineColor = Color3.fromRGB(100, 255, 100)
													highlight.FillTransparency = 0.4
													highlight.OutlineTransparency = 0
													highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
													highlight.Adornee = char
													highlight.Parent = char
													task.wait(0.12)
													if highlight and highlight.Parent then highlight:Destroy() end
												end)
											end
										end
									end
								end
								
								-- 다음 통나무 떨어지기 전 약간의 간격
								task.wait(0.2)
							end
							task.wait(1.0)
							
						-- 우선순위 3: 플레이어에게 다가가기 (보스 덩치가 크므로 25스터드 밖에서 멈춤)
						else
							if distToPlayer > 25 then
								humanoid:MoveTo(targetPlayerPos)
							else
								humanoid:MoveTo(hrp.Position)
							end
						end
					elseif config.mobModelName == "Spider" then
						--========================================================================
						-- [Spider 전용 FSM 분기]: 독연무 시전(비동기 광역기) + 독립적인 근접 공격 추격
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						
						local now = os.clock()
						local meleeCooldown = config.attackCooldown or 2.0
						local poisonCooldown = 15.0
						
						local MELEE_RANGE = 10 -- [수정] 일반공격 사거리 넓힘 (기존 6 -> 10)
						local POISON_RANGE = 30 -- [수정] 포이즌 발동 사거리 넓힘 (기존 20 -> 30)
						
						if distToPlayer <= POISON_RANGE and (now - lastPoisonTick >= poisonCooldown) then
							lastPoisonTick = now
							
							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("Spider_Poison")
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									if track then track:Play() end
								end
							end)
							
							task.spawn(function()
								local pDuration = 8.0
								local pRadius = 22.0 -- [수정] 포이즌 장판 범위 넓힘 (기존 12 -> 22)
								local pDamage = 20.0 -- [상향] 최종 구역에 맞게 독 틱 데미지 상향 (기존 5.0 -> 20.0)
								local cloudFloorPos = currentPos - Vector3.new(0, humanoid.HipHeight + (hrp.Size.Y / 2) - 0.2, 0)
								
								local cloud = Instance.new("Part")
								cloud.Name = "PoisonCloud"
								cloud.Shape = Enum.PartType.Cylinder
								cloud.Size = Vector3.new(0.2, pRadius * 2, pRadius * 2)
								cloud.CFrame = CFrame.new(cloudFloorPos) * CFrame.Angles(0, 0, math.rad(90))
								cloud.Anchored = true
								cloud.CanCollide = false
								cloud.Material = Enum.Material.SmoothPlastic
								cloud.Color = Color3.fromRGB(150, 0, 200)
								cloud.Transparency = 0.85 -- [수정] 피자판 같은 바닥은 거의 투명하게
								cloud.Parent = workspace
								
								local pe = Instance.new("ParticleEmitter")
								pe.Texture = "rbxasset://textures/particles/smoke_main.dds" -- [추가] 진짜 연기 텍스처 적용
								pe.Color = ColorSequence.new(Color3.fromRGB(150, 0, 200), Color3.fromRGB(100, 255, 100))
								pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(0.5, 12), NumberSequenceKeypoint.new(1, 15)}) -- 뭉게뭉게 커지게
								pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1.0)})
								pe.Lifetime = NumberRange.new(3, 5)
								pe.Rate = 50 -- 뿜어내는 양 증가
								pe.Speed = NumberRange.new(1, 4)
								pe.SpreadAngle = Vector2.new(90, 90)
								pe.Rotation = NumberRange.new(0, 360)
								pe.RotSpeed = NumberRange.new(-20, 20)
								pe.ZOffset = 1
								pe.EmissionDirection = Enum.NormalId.Top
								pe.Shape = Enum.ParticleEmitterShape.Cylinder
								pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
								pe.Parent = cloud
								
								local ticks = math.floor(pDuration)
								for i = 1, ticks do
									task.wait(1.0)
									if not cloud or not cloud.Parent then break end
									
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											local dXZ = math.sqrt(math.pow(pRoot.Position.X - cloudFloorPos.X, 2) + math.pow(pRoot.Position.Z - cloudFloorPos.Z, 2))
											if dXZ <= pRadius and math.abs(pRoot.Position.Y - cloudFloorPos.Y) < 10 then
												phum:TakeDamage(pDamage)
												task.spawn(function()
													local highlight = Instance.new("Highlight")
													highlight.FillColor = Color3.fromRGB(150, 0, 200)
													highlight.OutlineColor = Color3.fromRGB(100, 255, 100)
													highlight.FillTransparency = 0.5
													highlight.Adornee = char
													highlight.Parent = char
													task.wait(0.2)
													if highlight and highlight.Parent then highlight:Destroy() end
												end)
											end
										end
									end
								end
								
								if cloud then
									if pe then pe.Enabled = false end
									local ts = game:GetService("TweenService")
									local fade = ts:Create(cloud, TweenInfo.new(1.0), {Transparency = 1})
									fade:Play()
									fade.Completed:Wait()
									cloud:Destroy()
								end
							end)
							task.wait(0.5)
						end
						
						currentPos = hrp.Position
						targetPlayerPos = phrp.Position
						distToPlayer = (currentPos - targetPlayerPos).Magnitude
						
						if distToPlayer <= MELEE_RANGE then
							humanoid:MoveTo(hrp.Position)
							if now - lastAttackTick >= meleeCooldown then
								lastAttackTick = now
								
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local attackAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("Spider_Attack")
									if animator and attackAnim then
										local track = animator:LoadAnimation(attackAnim)
										if track then track:Play() end
									end
								end)
								
								local telegraphDuration = 0.6
								local mobRootPos = hrp.Position
								
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "SpiderMeleeTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, MELEE_RANGE * 2, MELEE_RANGE * 2)
								local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
								local floorPos = mobRootPos - Vector3.new(0, groundOffset - 0.2, 0)
								warnCircle.CFrame = CFrame.new(floorPos) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(255, 0, 0)
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								local lookDir = Vector3.new(targetPlayerPos.X - hrp.Position.X, 0, targetPlayerPos.Z - hrp.Position.Z)
								if lookDir.Magnitude > 0.1 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
								end
								
								task.wait(telegraphDuration)
								warnCircle:Destroy()
								
								if isAlive and targetPlayer and targetPlayer.Parent and targetPlayer:FindFirstChild("HumanoidRootPart") then
									local currentPhrp = targetPlayer.HumanoidRootPart
									if (hrp.Position - currentPhrp.Position).Magnitude <= MELEE_RANGE + 1.5 then
										local currentPhum = targetPlayer:FindFirstChild("Humanoid")
										if currentPhum and currentPhum.Health > 0 then
											currentPhum:TakeDamage(config.baseDamage or 15)
											local bounceDir = (currentPhrp.Position - hrp.Position)
											bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
											local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
											if hitPlayer then
												local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
												NetController.FireClient(hitPlayer, "Player.Stun", bounceDir)
											end
											task.spawn(function()
												local highlight = Instance.new("Highlight")
												highlight.FillColor = Color3.fromRGB(255, 0, 0)
												highlight.OutlineColor = Color3.fromRGB(255, 100, 100)
												highlight.FillTransparency = 0.4
												highlight.Adornee = targetPlayer
												highlight.Parent = targetPlayer
												task.wait(0.12)
												if highlight and highlight.Parent then highlight:Destroy() end
											end)
										end
									end
								end
							end
						else
							if distToPlayer > 25 then
								humanoid:MoveTo(targetPlayerPos)
							else
								humanoid:MoveTo(targetPlayerPos)
							end
						end
					elseif config.mobModelName == "GhostKnight" then
						--========================================================================
						-- [GhostKnight 전용 중간 보스 FSM 분기]: 영혼의 질주 돌진 + 묵직한 대회전 격타 평타
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()
						
						local scaleRatio = (config.modelScale or 1) / 2.5
						
						local MELEE_RANGE = 9 * scaleRatio
						local CHARGE_RANGE_MIN = 16 * scaleRatio
						local CHARGE_RANGE_MAX = 35 * scaleRatio
						local chargeCooldown = 9.0 -- 9초마다 기습 질주
						local meleeCooldown = config.attackCooldown or 2.2
						local swordDropCooldown = 12.0 -- 12초마다 유령검 낙하
						
						-- 패턴 1: 영혼의 질주 돌진 (Phantom Charge) - 거리 벌어질 때
						if distToPlayer >= CHARGE_RANGE_MIN and distToPlayer <= CHARGE_RANGE_MAX and (now - lastJumpTick >= chargeCooldown) then
							lastJumpTick = now
							humanoid:MoveTo(hrp.Position) -- 정지
							
							-- 타겟을 정면으로 정밀 바라보기
							local lookDir = (targetPlayerPos - currentPos)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end
							
							-- 전방 직사각형 예고 장판 생성 (길이 22, 너비 8) - 스케일에 맞게 조절
							local chargeLength = 22 * scaleRatio
							local chargeWidth = 8 * scaleRatio
							
							local wcf = hrp.CFrame * CFrame.new(0, 0, -chargeLength/2)
							local telegraphPos = wcf.Position
							
							-- [지형 판독 레이캐스트]: 스폰 고도가 달라지거나 울퉁불퉁한 지형에서도 장판이 완벽히 지면에 밀착하도록 동적 판독
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							-- 보스의 중심 고도(hrp.Position.Y)에서 하향 레이캐스트하여 천장 간섭 및 플레이어 피격 원천 차단
							local rayStart = Vector3.new(telegraphPos.X, hrp.Position.Y, telegraphPos.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end
							
							local warnLine = Instance.new("Part")
							warnLine.Name = "GhostKnightChargeTelegraph"
							warnLine.Size = Vector3.new(chargeWidth, 0.4, chargeLength)
							warnLine.CFrame = CFrame.new(telegraphPos.X, floorY, telegraphPos.Z) * (hrp.CFrame.Rotation)
							warnLine.Anchored = true
							warnLine.CanCollide = false
							warnLine.Material = Enum.Material.Neon
							warnLine.Color = Color3.fromRGB(255, 0, 0) -- unified red telegraph
							warnLine.Transparency = 0.8
							warnLine.Parent = workspace
							
							local ts = game:GetService("TweenService")
							ts:Create(warnLine, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.35}):Play()
							
							-- 1. 경고장판이 먼저 나타나고 1.0초간 유지 (전조 단계)
							task.wait(1.0)
							
							-- 2. 1.0초 뒤 애니메이션 및 사운드, VFX 발동
							local peCharge = Instance.new("ParticleEmitter")
							peCharge.Texture = "rbxasset://textures/particles/smoke_main.dds"
							peCharge.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255), Color3.fromRGB(255, 255, 255))
							peCharge.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 0)})
							peCharge.Transparency = NumberSequence.new(0.6, 1)
							peCharge.Rate = 150
							peCharge.Speed = NumberRange.new(5, 15)
							peCharge.Lifetime = NumberRange.new(0.5, 0.8)
							peCharge.EmissionDirection = Enum.NormalId.Back
							peCharge.Parent = hrp
							
							local animator = humanoid:FindFirstChildOfClass("Animator")
							local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
							local chargeAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("GhostKnight_Charge")
							if animator and chargeAnim then
								local track = animator:LoadAnimation(chargeAnim)
								track:Play()
							end
							
							-- (사운드 재생 위치를 실제 돌진 시점으로 이동)
							
							-- 3. 애니메이션이 끝나고 타격 판정이 들어오는 시점까지 0.5초 추가 대기
							task.wait(0.5)
							
							-- 4. 장판 삭제 및 돌진 시작
							warnLine:Destroy()
							
							if isAlive then
								-- 영혼의 쾌속 전진 돌진 (CF 트윈을 통해 거인의 육중한 질주 물리 재현)
								local fwd = hrp.CFrame.LookVector
								local targetLand = hrp.Position + fwd * chargeLength
								
								-- 0.25초 동안 번개처럼 빠른 참격 슬라이드 돌진
								local slideTime = 0.25
								local slideTween = ts:Create(hrp, TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.lookAt(targetLand, targetLand + fwd)
								})
								slideTween:Play()
								
								-- 돌진 시 타격(슬래시) 사운드 재생
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local chargeSound = sounds and sounds:FindFirstChild("Monster") and sounds.Monster:FindFirstChild("GhostKnight_SwordSwing")
								if chargeSound then
									local sfx = chargeSound:Clone()
									sfx.Parent = hrp
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
								end
								
								-- 돌진 경로상 데미지 다단 판정 방지 및 타격 처리
								local elapsed = 0
								local hitPlayers = {}
								local startPos = hrp.Position
								
								while elapsed < slideTime and isAlive do
									local dt = task.wait(0.04)
									elapsed = elapsed + dt
									
									local currentHrpPos = hrp.Position
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										
										if phum and phum.Health > 0 and pRoot and not hitPlayers[p.UserId] then
											local pDir = pRoot.Position - startPos
											local forwardDist = fwd:Dot(pDir)
											local rightDist = hrp.CFrame.RightVector:Dot(pDir)
											
											-- 돌진 전방 경로 안에 있고, 좌우폭 내인 경우 적중
											if forwardDist > 0 and forwardDist <= chargeLength + 3 and math.abs(rightDist) <= chargeWidth/2 + 1 and math.abs(pRoot.Position.Y - currentHrpPos.Y) < 12 then
												hitPlayers[p.UserId] = true
												phum:TakeDamage(80) -- 돌진 데미지 80
												
												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService.Server.Controllers.NetController)
													NetController.FireClient(hitPlayer, "Player.Stun", fwd * 2.2) -- 강력 넉백
												end
											end
										end
									end
								end
							end
							
							if peCharge then peCharge:Destroy() end
							task.wait(1.0) -- [딜레이 증가] 0.5 -> 1.0초: 돌진 후 묵직한 경직 딜레이
							
						-- 패턴 3: 유령검 낙하 (Sword Rain) - 거인(중간보스) 한정 패턴
						elseif scaleRatio >= 0.8 and (now - lastSwordDropTick >= swordDropCooldown) then
							lastSwordDropTick = now
							humanoid:MoveTo(hrp.Position)
							
							-- 타겟을 향해 즉시 회전
							local lookDir = (targetPlayerPos - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end
							
							-- 캐스팅 애니메이션 재생 (Charge 모션을 캐스팅처럼 활용)
							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local castAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("GhostKnight_Charge")
								if animator and castAnim then
									local track = animator:LoadAnimation(castAnim)
									if track then track:Play() end
								end
							end)
							
							local dropCount = math.random(1, 4)
							for i = 1, dropCount do
								if not isAlive then break end
								
								task.wait(0.5) -- 엇박자 캐스팅
								
								local currentTargetPos = targetPlayerPos
								if phrp and phrp.Parent then currentTargetPos = phrp.Position end
								
								local targetFloorY = currentTargetPos.Y - 2.5
								local rayParams = RaycastParams.new()
								rayParams.FilterType = Enum.RaycastFilterType.Exclude
								local ignoreList = {model}
								for _, p in ipairs(Players:GetPlayers()) do
									if p.Character then table.insert(ignoreList, p.Character) end
								end
								rayParams.FilterDescendantsInstances = ignoreList
								local rayStart = Vector3.new(currentTargetPos.X, currentTargetPos.Y + 2, currentTargetPos.Z)
								local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
								if rayResult then
									targetFloorY = rayResult.Position.Y + 0.2
								end
								
								-- 예고 장판 생성
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "GhostKnightSwordTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, 16, 16)
								warnCircle.CFrame = CFrame.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(220, 230, 255) -- 유령빛 장판
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(warnCircle, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								task.wait(0.6)
								warnCircle:Destroy()
								if not isAlive then break end
								
								-- 유령검 모델 생성 (대검/클레이모어 형태)
								local swordModel = Instance.new("Model")
								swordModel.Name = "FallingSword"
								
								local blade = Instance.new("Part")
								blade.Name = "Blade"
								blade.Size = Vector3.new(0.4, 7, 2)
								blade.Color = Color3.fromRGB(220, 230, 255)
								blade.Material = Enum.Material.Neon
								blade.Anchored = true
								blade.CanCollide = false
								blade.CFrame = CFrame.new(currentTargetPos.X, targetFloorY + 40, currentTargetPos.Z)
								blade.Parent = swordModel
								
								local tip = Instance.new("WedgePart")
								tip.Name = "Tip"
								tip.Size = Vector3.new(0.4, 2, 2)
								tip.Color = Color3.fromRGB(220, 230, 255)
								tip.Material = Enum.Material.Neon
								tip.Anchored = false
								tip.CanCollide = false
								tip.CFrame = blade.CFrame * CFrame.new(0, -4.5, 0) * CFrame.Angles(math.rad(180), 0, 0)
								tip.Parent = swordModel
								
								local w1 = Instance.new("WeldConstraint")
								w1.Part0 = blade
								w1.Part1 = tip
								w1.Parent = blade
								
								local guard = Instance.new("Part")
								guard.Name = "Guard"
								guard.Size = Vector3.new(1.2, 0.6, 3.5)
								guard.Color = Color3.fromRGB(150, 180, 255)
								guard.Material = Enum.Material.Neon
								guard.Anchored = false
								guard.CanCollide = false
								guard.CFrame = blade.CFrame * CFrame.new(0, 3.5, 0)
								guard.Parent = swordModel
								
								local w2 = Instance.new("WeldConstraint")
								w2.Part0 = blade
								w2.Part1 = guard
								w2.Parent = blade
								
								local handle = Instance.new("Part")
								handle.Name = "Handle"
								handle.Shape = Enum.PartType.Cylinder
								handle.Size = Vector3.new(2.5, 0.5, 0.5)
								handle.Color = Color3.fromRGB(100, 120, 150)
								handle.Material = Enum.Material.Neon
								handle.Anchored = false
								handle.CanCollide = false
								handle.CFrame = blade.CFrame * CFrame.new(0, 4.75, 0) * CFrame.Angles(0, 0, math.rad(90))
								handle.Parent = swordModel
								
								local w3 = Instance.new("WeldConstraint")
								w3.Part0 = blade
								w3.Part1 = handle
								w3.Parent = blade
								
								swordModel.PrimaryPart = blade
								swordModel.Parent = workspace
								
								local fallTween = ts:Create(blade, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {CFrame = CFrame.new(currentTargetPos.X, targetFloorY + 4, currentTargetPos.Z)})
								fallTween:Play()
								task.wait(0.2)
								
								-- 타격음
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local impactSound = sounds and sounds:FindFirstChild("Monster") and sounds.Monster:FindFirstChild("GhostKnight_SwordSwing")
								if impactSound then
									local sfx = impactSound:Clone()
									sfx.Parent = blade
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
								end
								
								-- 데미지 판정
								if isAlive then
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											if (pRoot.Position - Vector3.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z)).Magnitude <= 8 then
												phum:TakeDamage(55)
												local NetController = require(ServerScriptService.Server.Controllers.NetController)
												local bounceDir = (pRoot.Position - Vector3.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z)).Unit
												bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
												NetController.FireClient(p, "Player.Stun", bounceDir * 1.3)
											end
										end
									end
								end
								
								task.spawn(function()
									for _, v in ipairs(swordModel:GetChildren()) do
										if v:IsA("BasePart") then
											ts:Create(v, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1}):Play()
										end
									end
									task.wait(0.5)
									swordModel:Destroy()
								end)
							end
							task.wait(1.0)
							
						-- 패턴 2: 묵직한 참격 (Melee Slam) - 사거리 이내
						elseif distToPlayer <= MELEE_RANGE then
							humanoid:MoveTo(hrp.Position)
							if now - lastAttackTick >= meleeCooldown then
								lastAttackTick = now
								
								-- 타겟을 향해 즉시 회전
								local lookDir = (targetPlayerPos - hrp.Position)
								lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
								if lookDir.Magnitude > 0.1 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
								end
								
								-- 원형 타격 예고 장판 생성
								local atkRadius = MELEE_RANGE
								local hitCenter = hrp.Position + (hrp.CFrame.LookVector * (atkRadius/3))
								
								-- [지형 판독 레이캐스트]: 스폰 고도가 달라지거나 울퉁불퉁한 지형에서도 장판이 완벽히 지면에 밀착하도록 동적 판독
								local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
								local rayParams = RaycastParams.new()
								rayParams.FilterType = Enum.RaycastFilterType.Exclude
								local ignoreList = {model}
								for _, p in ipairs(Players:GetPlayers()) do
									if p.Character then table.insert(ignoreList, p.Character) end
								end
								rayParams.FilterDescendantsInstances = ignoreList
								-- 보스의 중심 고도(hrp.Position.Y)에서 하향 레이캐스트하여 천장 간섭 및 플레이어 피격 원천 차단
								local rayStart = Vector3.new(hitCenter.X, hrp.Position.Y, hitCenter.Z)
								local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
								if rayResult then
									floorY = rayResult.Position.Y + 0.2
								end
								
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "GhostKnightAtkTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, atkRadius * 2, atkRadius * 2)
								warnCircle.CFrame = CFrame.new(hitCenter.X, floorY, hitCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(255, 0, 0)
								warnCircle.Transparency = 0.8
								warnCircle.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(warnCircle, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								-- 1. 경고장판이 먼저 나타나고 0.8초간 유지 (전조 단계)
								task.wait(0.8)
								
								-- 2. 0.8초 뒤 애니메이션 및 사운드, VFX 발동
								local peMelee = Instance.new("ParticleEmitter")
								peMelee.Texture = "rbxasset://textures/particles/smoke_main.dds"
								peMelee.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255), Color3.fromRGB(255, 255, 255))
								peMelee.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(1, 0)})
								peMelee.Transparency = NumberSequence.new(0.6, 1)
								peMelee.Rate = 120
								peMelee.Speed = NumberRange.new(3, 10)
								peMelee.Lifetime = NumberRange.new(0.4, 0.7)
								peMelee.EmissionDirection = Enum.NormalId.Top
								peMelee.Parent = hrp
								
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("GhostKnight_Attack")
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									track:Play()
								end
								
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local attackSound = sounds and sounds:FindFirstChild("Monster") and sounds.Monster:FindFirstChild("GhostKnight_SwordSwing")
								if attackSound then
									local sfx = attackSound:Clone()
									sfx.Parent = hrp
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
								end
								
								-- 3. 애니메이션이 끝나는 시점(타격 판정 순간)까지 0.5초 추가 대기
								task.wait(0.5) 
								
								-- 4. 장판 삭제 및 데미지 적용
								warnCircle:Destroy()
								if peMelee then peMelee:Destroy() end
								
								if isAlive then
									-- 실제 참격 데미지 판정
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											local dXZ = Vector3.new(pRoot.Position.X - hitCenter.X, 0, pRoot.Position.Z - hitCenter.Z).Magnitude
											if dXZ <= atkRadius and math.abs(pRoot.Position.Y - hitCenter.Y) < 12 then
												phum:TakeDamage(45) -- 평타 데미지 45
												
												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService.Server.Controllers.NetController)
													local bounceDir = (pRoot.Position - hitCenter)
													bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 1.1)
												end
											end
										end
									end
								end
								task.wait(0.7) -- [딜레이 증가] 0.3 -> 0.7초: 참격 후 묵직한 경직 후딜
							end
						else
							-- 평화로운 추격
							humanoid:MoveTo(targetPlayerPos)
						end
					elseif config.mobModelName == "BlueFlameKnight" then
						--========================================================================
						-- [BlueFlameKnight 전용 최종 보스 FSM 분기]: 일반참격/도약/회오리 + 대형 기믹 패턴(줄넘기/회전 레이저)
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()
						
						-- 스크린샷 4개 꼭짓점 기준 산출한 정확한 보스방 중심 좌표
						local centerPos = Vector3.new(1389.5, 500.0, 63.2)
						
						-- 천장 높이 실시간 감지 (보스방 천장으로 인한 끼임/충돌 방지 동적 예외 처리)
						local maxCeilingHeight = 30
						local ceilingRayParams = RaycastParams.new()
						ceilingRayParams.FilterType = Enum.RaycastFilterType.Exclude
						ceilingRayParams.FilterDescendantsInstances = {model}
						local ceilingRay = workspace:Raycast(centerPos, Vector3.new(0, maxCeilingHeight, 0), ceilingRayParams)
						local availableHeight = maxCeilingHeight
						if ceilingRay then
							availableHeight = math.max(5, (ceilingRay.Position.Y - centerPos.Y) - 3)
						end
						
						-- [대형 기믹 패턴 판단]: 평상시 30초, 체력 1만 이하의 Phase 2 돌입 시 15초 쿨타임으로 회폭 증가!
						local gimmickCooldown = bfkPhase2Active and 15.0 or 30.0
						if now - lastGimmickTick >= gimmickCooldown then
							lastGimmickTick = now
							humanoid:MoveTo(hrp.Position) -- 이동 정지
							
							-- [기믹 빈도 조율]: Phase 2(체력 1만 이하)일 경우 레이저(50%)와 파동(50%)을 동등한 빈도로 번갈아 출현시켜 긴장감 극대화!
							local selectedGimmick = currentGimmickMode
							if bfkPhase2Active then
								if math.random() <= 0.5 then
									selectedGimmick = 2 -- 레이저 강제 발동
								else
									selectedGimmick = 1 -- 파동(줄넘기) 강제 발동
								end
							end

							if selectedGimmick == 1 then
								-- 기믹 1: 심연의 파동 (줄넘기 파동 기믹) - 정밀 밸런스 패치
								currentGimmickMode = 2 -- 다음 기믹 번갈아가기
								
								-- 보스방 중심으로 즉시 텔레포트 및 정렬
								hrp.CFrame = CFrame.new(centerPos + Vector3.new(0, 1.5, 0))
								task.wait(0.3)
								
								-- [프리미엄 2초 전조 예고 장판] 거대한 레드 서클 생성하여 플레이어에게 회피 준비 유도!
								local gWarnCircle = Instance.new("Part")
								gWarnCircle.Name = "BFKWavePreTelegraph"
								gWarnCircle.Shape = Enum.PartType.Cylinder
								gWarnCircle.Size = Vector3.new(0.4, 60, 60)
								local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
								gWarnCircle.CFrame = CFrame.new(centerPos - Vector3.new(0, groundOffset - 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
								gWarnCircle.Anchored = true
								gWarnCircle.CanCollide = false
								gWarnCircle.Material = Enum.Material.Neon
								gWarnCircle.Color = Color3.fromRGB(255, 0, 0) -- 위험 경고 RED
								gWarnCircle.Transparency = 0.85
								gWarnCircle.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(gWarnCircle, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.4}):Play()
								
								-- 1. 애니메이션 로드 및 재생 (전조 캐스팅 돌림)
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local castAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("BlueFlameKnight_PillarCast")
									if animator and castAnim then
										local track = animator:LoadAnimation(castAnim)
										if track then track:Play() end
									end
								end)
								
								-- 2. 사운드 재생 연동 (Pillar/Wave 전조 충격음)
								pcall(function()
									local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
									local waveSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_Wave")
									if waveSound then
										local s = waveSound:Clone()
										s.Parent = hrp
										s:Play()
										game:GetService("Debris"):AddItem(s, 5)
									end
								end)
								
								-- 2초 동안 충분히 예고하여 플레이어가 장판 인지 및 더블점프 준비를 완료하도록 함
								task.wait(2.0)
								gWarnCircle:Destroy()
								
								-- 3. 3단계 줄넘기 링 생성 및 확장 검사
								task.spawn(function()
									local waveColors = {
										Color3.fromRGB(0, 120, 255),
										Color3.fromRGB(0, 180, 255),
										Color3.fromRGB(80, 220, 255)
									}
									
									for step = 1, 3 do
										if not isAlive then break end
										
										-- 엇박자 지연 전조 연출 (다음 링 준비 시간 확보)
										task.wait(1.5)
										if not isAlive then break end
										
										-- 지면 안착 링(고무줄 모양) 생성
										local ringFloorPos = centerPos
										local wavePart = Instance.new("Part")
										wavePart.Name = "WaveRing_" .. step
										wavePart.Shape = Enum.PartType.Cylinder
										wavePart.Size = Vector3.new(0.6, 2, 2)
										wavePart.CFrame = CFrame.new(ringFloorPos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
										wavePart.Color = waveColors[step]
										wavePart.Material = Enum.Material.Neon
										wavePart.Transparency = 1 -- 파트 자체는 투명하게 (충돌 판정용)
										wavePart.Anchored = true
										wavePart.CanCollide = false
										wavePart.CanTouch = false
										wavePart.Parent = workspace
										
										-- [VFX 비주얼 업그레이드]: 링 테두리 전체를 감싸고 확장되는 웅장한 푸른 불꽃 이미터 추가
										local peRing = Instance.new("ParticleEmitter")
										peRing.Name = "FlameRingEmitter"
										peRing.Texture = "rbxasset://textures/particles/fire_main.dds"
										peRing.Color = ColorSequence.new(Color3.fromRGB(0, 120, 255), Color3.fromRGB(80, 220, 255))
										peRing.Size = NumberSequence.new({
											NumberSequenceKeypoint.new(0, 2.0),
											NumberSequenceKeypoint.new(0.5, 4.0),
											NumberSequenceKeypoint.new(1, 0)
										})
										peRing.Transparency = NumberSequence.new({
											NumberSequenceKeypoint.new(0, 0.3),
											NumberSequenceKeypoint.new(0.8, 0.6),
											NumberSequenceKeypoint.new(1, 1.0)
										})
										peRing.Rate = 400 -- 촘촘하게 불꽃을 휘두르는 고밀도 기화 가닥수
										peRing.Speed = NumberRange.new(1, 3.5) -- 불꽃이 링 선로에 촘촘하게 결합되도록 속도 압축
										peRing.Lifetime = NumberRange.new(0.3, 0.5) -- 링 선로에 오밀조밀하게 불타오르도록 수명 축소
										peRing.SpreadAngle = Vector2.new(10, 10) -- 링 형태 보존을 위해 확산각 억제
										peRing.Rotation = NumberRange.new(0, 360)
										peRing.RotSpeed = NumberRange.new(-120, 120)
										
										-- 실린더의 둘레 표면(Surface)에서만 뿜어나오도록 특수 형상 제어!
										peRing.Shape = Enum.ParticleEmitterShape.Cylinder
										peRing.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
										peRing.EmissionDirection = Enum.NormalId.Top
										peRing.Parent = wavePart
										
										-- [수정] 오리지널 원형(Cylinder) 로직으로 롤백하되, 속을 비우기 위해 Adornment 사용
										local adornment = Instance.new("CylinderHandleAdornment")
										adornment.Radius = 1
										adornment.InnerRadius = 0.5
										adornment.Height = 0.6
										adornment.Color3 = waveColors[step]
										adornment.Transparency = 1 -- [비주얼 대폭 강화]: 인위적인 형광 링을 완전히 투명화하여 푸른 불꽃만 휘날리도록 보정
										adornment.ZIndex = 5
										adornment.Adornee = wavePart
										-- [버그 수정] 실린더 베이스 파트의 원형 면(Y-Z)에 맞추기 위해 Adornment(Z축 연장)를 Y축 기준 90도 회전!
										adornment.CFrame = CFrame.Angles(0, math.rad(90), 0)
										adornment.Parent = wavePart
										
										-- 링 확장 및 데미지 검증 루프 (2.2초 동안 서서히 확장하여 직관적인 피하기 제공)
										task.spawn(function()
											local expTime = 2.2
											local expStart = os.clock()
											local hitPlayers = {} -- 이번 파동에 이미 맞은 플레이어 목록
											
											local ts = game:GetService("TweenService")
											
											-- 기존의 완벽한 원형 스케일링 로직 그대로 복구 (지름 60)
											ts:Create(wavePart, TweenInfo.new(expTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
												Size = Vector3.new(0.6, 60, 60)
											}):Play()
											
											-- 테두리 링(고무줄)도 똑같이 확장
											ts:Create(adornment, TweenInfo.new(expTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
												Radius = 30,
												InnerRadius = 29.2, -- 0.8 두께의 얇은 링
												Transparency = 1
											}):Play()
											
											while os.clock() - expStart < expTime do
												task.wait(0.04)
												if not wavePart or not wavePart.Parent then break end
												
												-- 다시 원래의 원형 사이즈 기반 판정으로 복구
												local currentRadius = (wavePart.Size.Y) / 2
												
												for _, p in ipairs(Players:GetPlayers()) do
													local char = p.Character
													local phum = char and char:FindFirstChild("Humanoid")
													local pRoot = char and char:FindFirstChild("HumanoidRootPart")
													
													if phum and phum.Health > 0 and pRoot and not hitPlayers[p.UserId] then
														local dXZ = math.sqrt(math.pow(pRoot.Position.X - ringFloorPos.X, 2) + math.pow(pRoot.Position.Z - ringFloorPos.Z, 2))
														-- 플레이어가 점프하지 않고 지면에 가깝게 붙어 있을 때 충격파 강타 (Y축 높이가 3 스터드 이내일 때)
														local dY = pRoot.Position.Y - ringFloorPos.Y
														
														-- 정밀 마찰 판정 (오차 2.0 스터드 내로 좁히고 시인성 일치)
														if dXZ >= (currentRadius - 2.5) and dXZ <= (currentRadius + 1.0) and dY < 3.2 then
															hitPlayers[p.UserId] = true
															phum:TakeDamage(180) -- 즉사급 데미지로 대폭 상향 (기믹 1)
															print(string.format("[Gimmick 1 DEBUG] Player %s hit by WaveRing! Damage: 180", p.Name))
															
															-- 넉백 처리
															local bounceDir = (pRoot.Position - ringFloorPos)
															bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
															local NetController = require(ServerScriptService.Server.Controllers.NetController)
															NetController.FireClient(p, "Player.Stun", bounceDir * 1.2)
														end
													end
												end
											end
											
											wavePart:Destroy()
										end)
									end
								end)
								
								-- 줄넘기 기믹 시전 동안 충분히 대기
								task.wait(7.5)
								
							else
								-- 기믹 2: 연소의 광선 (360도 지면 회전 레이저 기믹) - 정밀 밸런스 패치
								currentGimmickMode = 1 -- 다음 기믹 번갈아가기
								
								-- 보스방 지면에 고정 (공중 부상 전면 제거)
								hrp.CFrame = CFrame.new(centerPos + Vector3.new(0, 1.5, 0))
								task.wait(0.3)
								
								-- [프리미엄 2.0초 레이저 시작점 예고선 생성] 빨간색 일직선 레일로 시전 방향 미리 경고!
								local startAngle = 0
								local startAngleRad = math.rad(startAngle)
								local startDirection = Vector3.new(math.cos(startAngleRad), 0, math.sin(startAngleRad)).Unit
								
								local gWarnLine = Instance.new("Part")
								gWarnLine.Name = "BFKLaserPreTelegraph"
								gWarnLine.Size = Vector3.new(3, 0.3, 35)
								local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
								local targetCF = CFrame.lookAt(centerPos, centerPos + startDirection)
								gWarnLine.CFrame = CFrame.new(centerPos + startDirection * 17.5 - Vector3.new(0, groundOffset - 0.2, 0)) * targetCF.Rotation
								gWarnLine.Anchored = true
								gWarnLine.CanCollide = false
								gWarnLine.Material = Enum.Material.Neon
								gWarnLine.Color = Color3.fromRGB(255, 0, 0) -- 경고 RED
								gWarnLine.Transparency = 0.85
								gWarnLine.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(gWarnLine, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.4}):Play()
								
								-- 1. 애니메이션 로드 및 재생
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local sweepAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("BlueFlameKnight_LaserSweep")
									if animator and sweepAnim then
										local track = animator:LoadAnimation(sweepAnim)
										if track then track:Play() end
									end
								end)
								
								-- [전조 단계] 2초 캐스팅 대기하는 동안 웅장하게 차징되는 기 모으기 사운드 재생
								pcall(function()
									local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
									local chargeSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_LaserCharge")
									if chargeSound then
										local s = chargeSound:Clone()
										s.Parent = hrp
										s:Play()
										game:GetService("Debris"):AddItem(s, 4)
									end
								end)
								
								-- 2.0초 충분히 대기하여 플레이어가 피할 시간 보장
								task.wait(2.0)
								gWarnLine:Destroy()
								
								-- [본 방출 단계] 레이저가 생성되어 회전을 개시하는 순간에 맞춰 지속 광선 방출 루프음 재생
								pcall(function()
									local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
									local laserSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_LaserLoop")
									if laserSound then
										local s = laserSound:Clone()
										s.Parent = hrp
										s:Play()
										game:GetService("Debris"):AddItem(s, 6)
									end
								end)
								
								-- 3. 레이저 회전 빔 생성 및 360도 휩쓸기 검사
								-- [비주얼 업그레이드]: 형광 사각 박스 제거 -> 이중 코어 플라즈마 원기둥 빔 + 일렉트릭 스파크 연출!
								local laserPart = Instance.new("Part")
								laserPart.Name = "LaserBeamOuter"
								laserPart.Shape = Enum.PartType.Cylinder
								laserPart.Color = Color3.fromRGB(0, 150, 255) -- 화려한 청록색 아우라
								laserPart.Material = Enum.Material.Neon
								laserPart.Transparency = 0.45 -- 아우라 느낌을 위해 반투명화
								laserPart.Anchored = true
								laserPart.CanCollide = false
								laserPart.CanTouch = false
								laserPart.Parent = workspace

								local laserCore = Instance.new("Part")
								laserCore.Name = "LaserBeamCore"
								laserCore.Shape = Enum.PartType.Cylinder
								laserCore.Color = Color3.fromRGB(240, 250, 255) -- 초고열 백색 내부 코어
								laserCore.Material = Enum.Material.Neon
								laserCore.Transparency = 0.1
								laserCore.Anchored = true
								laserCore.CanCollide = false
								laserCore.CanTouch = false
								laserCore.Parent = workspace

								-- 에너지 불꽃 스파크 파티클 추가
								local peLaser = Instance.new("ParticleEmitter")
								peLaser.Texture = "rbxasset://textures/particles/sparkles_main.dds"
								peLaser.Color = ColorSequence.new(Color3.fromRGB(0, 200, 255), Color3.fromRGB(255, 255, 255))
								peLaser.Size = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 1.2),
									NumberSequenceKeypoint.new(1, 0)
								})
								peLaser.Transparency = NumberSequence.new(0.2, 1.0)
								peLaser.Rate = 120
								peLaser.Speed = NumberRange.new(5, 12)
								peLaser.SpreadAngle = Vector2.new(360, 360)
								peLaser.Lifetime = NumberRange.new(0.4, 0.8)
								peLaser.ZOffset = 1
								peLaser.Parent = laserPart
								
								local angle = 0
								local laserDuration = 2.9 -- [속도 미세 조율] 조금 더 빠른 긴장감을 위해 지속시간 최적화 (1바퀴 회전)
								local laserStart = os.clock()
								local lastLaserHitTick = {} -- 플레이어 다단히트 방지
								
								while os.clock() - laserStart < laserDuration and isAlive do
									-- [속도 미세 조율] 너무 느리지 않고 회피 쾌감을 주는 적절한 회전 속도(5.0도)로 상향 조정
									angle = angle + 5.0 
									local angleRad = math.rad(angle)
									
									-- 지면에서 35스터드 사거리로 수평 레이저 조준
									local laserDirection = Vector3.new(math.cos(angleRad), 0, math.sin(angleRad)).Unit
									local beamLength = 35
									
									-- [버그수정] 로블록스 실린더는 X축 방향으로 연장되므로 X를 길이(beamLength)로 세팅하고 Y,Z를 구경으로 설정
									laserPart.Size = Vector3.new(beamLength, 1.8, 1.8)
									laserCore.Size = Vector3.new(beamLength, 0.7, 0.7)
									
									-- 지면 근처(높이 2.0스터드)에서 수평으로 레이저 휩쓸기 (점프로 회피 가능하도록 배치)
									local startPoint = hrp.Position + Vector3.new(0, 0.5, 0)
									local endPoint = startPoint + laserDirection * beamLength
									
									-- [중요] 실린더의 축방향(X)을 발사방향으로 일치시키기 위해 Y축으로 90도 강제 회전 각도 결합!
									local lookCF = CFrame.lookAt(startPoint, endPoint) * CFrame.new(0, 0, -beamLength/2)
									laserPart.CFrame = lookCF * CFrame.Angles(0, math.rad(90), 0)
									laserCore.CFrame = laserPart.CFrame
									
									-- 레이저 궤적 접촉 검사
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										
										if phum and phum.Health > 0 and pRoot then
											-- 1) height 검사 (점프하지 않은 지면 상태 판정)
											local dY = pRoot.Position.Y - centerPos.Y
											if dY < 3.0 then
												-- 2) 플레이어 각도가 현재 회전중인 레이저 바닥 도달선에 접촉했는지 판정
												local playerDir = (pRoot.Position - centerPos)
												local playerDirXZ = Vector3.new(playerDir.X, 0, playerDir.Z)
												local angleDiff = math.acos(math.clamp(playerDirXZ.Unit:Dot(laserDirection), -1, 1))
												
												-- 좁은 마찰 범위(약 12도 이내)이고 레이저 사거리 안일 때
												if math.deg(angleDiff) < 12 and playerDirXZ.Magnitude <= 37 then
													local uId = p.UserId
													local nowHit = os.clock()
													-- [쿨다운 증가] 다단히트 주기 연장 0.5 -> 0.8초 (순간 삭제 방지)
													if not lastLaserHitTick[uId] or nowHit - lastLaserHitTick[uId] >= 0.8 then
														lastLaserHitTick[uId] = nowHit
														phum:TakeDamage(350) -- [데미지 즉사급 상향] 레이저 데미지 350
														print(string.format("[Gimmick 2 DEBUG] Player %s hit by Laser! Damage: 350", p.Name))
														
														-- 경미한 Stun
														local bounceDir = playerDirXZ.Unit
														local NetController = require(ServerScriptService.Server.Controllers.NetController)
														NetController.FireClient(p, "Player.Stun", bounceDir * 0.4)
													end
												end
											end
										end
									end
									
									task.wait(0.04)
								end
								
								laserPart:Destroy()
								if laserCore then laserCore:Destroy() end
								
								-- 보스를 정위치 대기
								local ts = game:GetService("TweenService")
								ts:Create(hrp, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.new(centerPos + Vector3.new(0, 1.5, 0))
								}):Play()
								task.wait(0.6)
							end
							
						else
							--========================================================================
							-- [일반 전투 패턴]: 찌르기, 도약 베기, 360도 회오리 베기, 기본 대검 참격
							--========================================================================
							
							-- 우선순위 1: 3연속 투사체 회오리 (Whirlwind Tornado) (거리 <= 25, 쿨 12초)
							if distToPlayer <= 25 and (now - lastWhirlwindTick >= 12.0) then
								lastWhirlwindTick = now
								humanoid:MoveTo(hrp.Position) -- 정지
								
								-- [버그 수정] 보스방 바닥 500.2 고정
								local floorY = 500.2
								
								-- 3회 연속 발사 루프
								for i = 1, 3 do
									if not isAlive then break end
									
									-- 1. 타겟 방향으로 즉시 회전
									local lookDir = (phrp.Position - hrp.Position)
									lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
									if lookDir.Magnitude > 0.1 then
										hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
									end
									
									-- 2. 전조 장판 생성 (길이 60, 너비 8 직사각형)
									local tornadoLength = 60
									local tornadoWidth = 8
									local warnLine = Instance.new("Part")
									warnLine.Name = "BFKTornadoTelegraph"
									warnLine.Size = Vector3.new(tornadoWidth, 0.4, tornadoLength)
									local wcf = hrp.CFrame * CFrame.new(0, 0, -tornadoLength/2)
									warnLine.CFrame = CFrame.new(wcf.Position.X, floorY, wcf.Position.Z) * hrp.CFrame.Rotation
									warnLine.Anchored = true
									warnLine.CanCollide = false
									warnLine.Material = Enum.Material.Neon
									warnLine.Color = Color3.fromRGB(255, 0, 0)
									warnLine.Transparency = 0.85
									warnLine.Parent = workspace
									
									local ts = game:GetService("TweenService")
									ts:Create(warnLine, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
									
									-- 0.8초 대기
									task.wait(0.8)
									if warnLine then warnLine:Destroy() end
									if not isAlive then break end
									
									-- 3. 애니메이션 및 신규 회오리 사운드 재생
									pcall(function()
										local animator = humanoid:FindFirstChildOfClass("Animator")
										local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
										local spinAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("BlueFlameKnight_Whirlwind")
										if animator and spinAnim then
											local track = animator:LoadAnimation(spinAnim)
											if track then 
												track.Looped = false
												track:Play() 
											end
										end
									end)
									
									pcall(function()
										local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
										local sound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_Whirlwind")
										if sound then
											local s = sound:Clone()
											s.Parent = hrp
											s:Play()
											game:GetService("Debris"):AddItem(s, 2)
										end
									end)
									
									-- 4. 실제 회오리 투사체 파트 생성 (가시적인 기둥 제거 + 이중 폭풍/스파크 파티클 연출)
									-- [비주얼 업그레이드]: 딱딱한 푸른색 실린더는 Transparency = 1로 감춰서 완전히 투명화!
									local tornadoHeight = 12
									local tornado = Instance.new("Part")
									tornado.Name = "BFKTornadoProjectile"
									tornado.Shape = Enum.PartType.Cylinder
									tornado.Size = Vector3.new(tornadoHeight, tornadoWidth, tornadoWidth)
									local startCFrame = hrp.CFrame * CFrame.new(0, 0, -3)
									-- Y축으로 세우기 위해 Z축 90도 회전
									tornado.CFrame = CFrame.new(startCFrame.Position.X, floorY + (tornadoHeight/2), startCFrame.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
									tornado.Anchored = true
									tornado.CanCollide = false
									tornado.Material = Enum.Material.Neon
									tornado.Color = Color3.fromRGB(0, 150, 255)
									tornado.Transparency = 1.0 -- [비주얼 교정] 실린더 지우고 파티클만 보이게 강제!
									tornado.Parent = workspace
									
									-- 1층 레이어: 휘몰아치는 가스 폭풍
									local pe = Instance.new("ParticleEmitter")
									pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
									pe.Color = ColorSequence.new(Color3.fromRGB(0, 120, 255), Color3.fromRGB(80, 220, 255))
									pe.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, tornadoWidth * 0.7),
										NumberSequenceKeypoint.new(0.5, tornadoWidth * 1.2),
										NumberSequenceKeypoint.new(1, tornadoWidth * 1.8)
									})
									pe.Transparency = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 0.8),
										NumberSequenceKeypoint.new(0.2, 0.4),
										NumberSequenceKeypoint.new(0.8, 0.6),
										NumberSequenceKeypoint.new(1, 1.0)
									})
									pe.Rate = 180
									pe.Speed = NumberRange.new(4, 9)
									pe.Lifetime = NumberRange.new(0.8, 1.3)
									pe.Rotation = NumberRange.new(0, 360)
									pe.RotSpeed = NumberRange.new(400, 600) -- 고속 회전 회오리
									pe.ZOffset = 1
									pe.EmissionDirection = Enum.NormalId.Right
									pe.Parent = tornado

									-- 2층 레이어: 빛나는 신비로운 에너지 스파크 입자
									local peSparks = Instance.new("ParticleEmitter")
									peSparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
									peSparks.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(0, 180, 255))
									peSparks.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 1.8),
										NumberSequenceKeypoint.new(1, 0)
									})
									peSparks.Transparency = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 0.1),
										NumberSequenceKeypoint.new(0.8, 0.5),
										NumberSequenceKeypoint.new(1, 1.0)
									})
									peSparks.Rate = 120
									peSparks.Speed = NumberRange.new(5, 15)
									peSparks.SpreadAngle = Vector2.new(90, 90)
									peSparks.Lifetime = NumberRange.new(0.5, 1.0)
									peSparks.Rotation = NumberRange.new(0, 360)
									peSparks.RotSpeed = NumberRange.new(-500, 500)
									peSparks.ZOffset = 1.5
									peSparks.EmissionDirection = Enum.NormalId.Right
									peSparks.Parent = tornado
									
									-- 5. 회오리 전진시키기 (Tween)
									local endPos = hrp.Position + (hrp.CFrame.LookVector * tornadoLength)
									local endCFrame = CFrame.new(endPos.X, floorY + (tornadoHeight/2), endPos.Z) * CFrame.Angles(0, 0, math.rad(90))
									
									local tornadoMove = ts:Create(tornado, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {CFrame = endCFrame})
									tornadoMove:Play()
									
									-- 6. 이동 중 데미지 판정 (1.5초 동안 지속)
									local moveTime = 1.5
									local fwdDir = hrp.CFrame.LookVector
									
									task.spawn(function()
										local elapsed = 0
										local hitPlayers = {} -- 중복 타격 방지 기록
										
										while elapsed < moveTime and isAlive and tornado and tornado.Parent do
											local dt = task.wait(0.1)
											elapsed = elapsed + dt
											
											local tPos = tornado.Position
											for _, p in ipairs(Players:GetPlayers()) do
												local char = p.Character
												local phum = char and char:FindFirstChild("Humanoid")
												local pRoot = char and char:FindFirstChild("HumanoidRootPart")
												
												if phum and phum.Health > 0 and pRoot and not hitPlayers[p.UserId] then
													local dist = (Vector3.new(pRoot.Position.X, 0, pRoot.Position.Z) - Vector3.new(tPos.X, 0, tPos.Z)).Magnitude
													if dist <= (tornadoWidth/2 + 2) and math.abs(pRoot.Position.Y - tPos.Y) < 15 then
														hitPlayers[p.UserId] = true
														phum:TakeDamage(250) -- 회오리 데미지 대폭 상향
														
														local hitPlayer = Players:GetPlayerFromCharacter(char)
														if hitPlayer then
															local NetController = require(ServerScriptService.Server.Controllers.NetController)
															NetController.FireClient(hitPlayer, "Player.Stun", fwdDir * 1.5)
														end
													end
												end
											end
										end
										if tornado then tornado:Destroy() end
									end)
									
									-- 다음 투사체 발사까지 애니메이션 모션 대기 (0.7초)
									task.wait(0.7)
								end
								
							-- 우선순위 2: 심연의 약진 (Leap Slam) - 플레이어가 너무 멀 때 진형 파괴 접근 (거리 >= 18, 쿨 12초) [Phase 2에서는 미사용]
							elseif not bfkPhase2Active and distToPlayer >= 18 and (now - lastLeapSlamTick >= 12.0) then
								lastLeapSlamTick = now
								humanoid:MoveTo(hrp.Position)
								
								-- 1. 도약베기 애니메이션 로드 및 재생
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local leapAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("BlueFlameKnight_LeapSlam")
									if animator and leapAnim then
										local track = animator:LoadAnimation(leapAnim)
										if track then 
											track.Looped = false
											track:Play() 
										end
									end
								end)
								
								local targetLandPos = phrp.Position
								local telegraphRadius = 14
								local ts = game:GetService("TweenService")
								
								-- 도약 (하늘로 솟구침)
								local leapUpHeight = math.min(20, availableHeight)
								hrp.Anchored = true -- [버그 수정] 중력에 밀려 떨어지지 않도록 공중에서 완전히 고정시킴
								
								local leapUp = ts:Create(hrp, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.new(hrp.Position + Vector3.new(0, leapUpHeight, 0))
								})
								leapUp:Play()
								task.wait(0.4)
								
								if not isAlive then 
									hrp.Anchored = false 
									break 
								end
								
								-- 공중에 체공한 상태에서 플레이어 낙하지점 바닥에 경고 장판 생성
								targetLandPos = (phrp and phrp.Parent) and phrp.Position or targetLandPos
								
								-- [버그 수정] 보스방 지면은 정확히 500.0이므로 장판을 500.2에 밀착 생성!
								local floorY = 500.2
								
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "BFKLeapTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2)
								local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
								warnCircle.CFrame = CFrame.new(targetLandPos.X, floorY, targetLandPos.Z) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(255, 0, 0)
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								ts:Create(warnCircle, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								-- 1.0초 체공 대기 (회피 시간 제공)
								task.wait(1.0)
								if warnCircle then warnCircle:Destroy() end
								
								if not isAlive then 
									hrp.Anchored = false 
									break 
								end
								
								-- 경고 장판 위치로 급강하 내리치기
								local leapDown = ts:Create(hrp, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									CFrame = CFrame.new(targetLandPos.X, 500.0 + groundOffset, targetLandPos.Z)
								})
								leapDown:Play()
								task.wait(0.2)
								
								hrp.Anchored = false -- 착지 완료 후 다시 물리 활성화
								
								-- [추가] 지면 강타 이펙트 (돌 파편 튕김)
								local impactFloorPos = Vector3.new(targetLandPos.X, 500.0, targetLandPos.Z)
								for i = 1, 12 do
									local rock = Instance.new("Part")
									rock.Size = Vector3.new(math.random(1, 3), math.random(1, 3), math.random(1, 3))
									rock.Color = Color3.fromRGB(80, 80, 80)
									rock.Material = Enum.Material.Slate
									rock.CFrame = CFrame.new(impactFloorPos + Vector3.new(0, 1, 0)) * CFrame.Angles(math.random(), math.random(), math.random())
									rock.Velocity = Vector3.new(math.random(-40, 40), math.random(50, 80), math.random(-40, 40))
									rock.RotVelocity = Vector3.new(math.random(-30, 30), math.random(-30, 30), math.random(-30, 30))
									rock.CanCollide = true -- 바닥에 튕기도록
									rock.Parent = workspace
									game:GetService("Debris"):AddItem(rock, math.random(15, 25) / 10) -- 1.5 ~ 2.5초 후 제거
								end								
								-- 착지 강타 대폭발 (지름 14스터드)
								if isAlive then
									-- 도약 대폭발 강타 데미지 사운드 재생
									pcall(function()
										local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
										local sound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_LeapSlam")
										if sound then
											local s = sound:Clone()
											s.Parent = hrp
											s:Play()
											game:GetService("Debris"):AddItem(s, 2)
										end
									end)
									
									local exp = Instance.new("Explosion")
									exp.BlastRadius = telegraphRadius
									exp.BlastPressure = 0
									exp.Position = targetLandPos
									exp.ExplosionType = Enum.ExplosionType.NoCraters
									exp.Visible = false
									exp.Parent = workspace
									
									-- 데미지 판정
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											-- 정확한 실린더 범위 내 판정
											local dXZ = Vector3.new(pRoot.Position.X - targetLandPos.X, 0, pRoot.Position.Z - targetLandPos.Z).Magnitude
											if dXZ <= telegraphRadius and math.abs(pRoot.Position.Y - targetLandPos.Y) < 15 then
												phum:TakeDamage(350) -- 도약 강타 즉사급 데미지로 상향
												
												-- 넉백
												local bounceDir = (pRoot.Position - targetLandPos)
												bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
												local NetController = require(ServerScriptService.Server.Controllers.NetController)
												NetController.FireClient(p, "Player.Stun", bounceDir * 1.5)
											end
										end
									end
								end
								-- [버그 수정] 넘어진 상태에서 즉시 다른 패턴(찌르기 등)을 이어서 쓰는 현상 방지
								-- 착지 후 일어나는 애니메이션(약 3.5초) 동안 완전히 대기하여 유저에게 프리딜 타임(Free DPS) 부여!
								task.wait(3.5)
								
							-- 우선순위 3: 염화의 찌르기 (Fiery Thrust) - 미드 레인지 카이팅 플레이어 예리한 찌르기 (거리 10~18, 쿨 6초)
							elseif distToPlayer >= 10 and distToPlayer <= 18 and (now - lastThrustTick >= 6.0) then
								lastThrustTick = now
								humanoid:MoveTo(hrp.Position)
								
								-- 타겟을 향해 즉시 회전 정렬
								local lookDir = (phrp.Position - hrp.Position)
								lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
								if lookDir.Magnitude > 0.1 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
								end
								
								-- [추가] 찌르기 전방 직사각형 장판 생성 (길이 18, 너비 6)
								local thrustLength = 18
								local thrustWidth = 6
								-- [버그 수정] 보스방 바닥 500.2 고정
								local floorY = 500.2
								local warnLine = Instance.new("Part")
								warnLine.Name = "BFKThrustTelegraph"
								warnLine.Size = Vector3.new(thrustWidth, 0.4, thrustLength)
								local wcf = hrp.CFrame * CFrame.new(0, 0, -thrustLength/2)
								warnLine.CFrame = CFrame.new(wcf.Position.X, floorY, wcf.Position.Z) * (hrp.CFrame.Rotation)
								warnLine.Anchored = true
								warnLine.CanCollide = false
								warnLine.Material = Enum.Material.Neon
								warnLine.Color = Color3.fromRGB(255, 0, 0)
								warnLine.Transparency = 0.85
								warnLine.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(warnLine, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								-- 1.0초 대기 (회피 시간 제공)
								task.wait(1.0)
								if warnLine then warnLine:Destroy() end
								
								if not isAlive then break end
								
								-- 1. 애니메이션 재생
								local animDuration = 1.0
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local thrustAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("BlueFlameKnight_Thrust")
									if animator and thrustAnim then
										local track = animator:LoadAnimation(thrustAnim)
										if track then 
											track.Looped = false
											track:Play() 
											if track.Length > 0 then animDuration = track.Length end
										end
									end
								end)
								
								-- 2. 신규 참격 효과음 재생
								pcall(function()
									local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
									local swingSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_SwordSwing")
									if swingSound then
										local s = swingSound:Clone()
										s.Parent = hrp
										s:Play()
										game:GetService("Debris"):AddItem(s, 2)
									end
								end)
								
								-- [버그수정] 찌르기는 타격점이 애니메이션 중간(0.5초)이므로 애니메이션 전체 길이가 아닌 하드코딩 타이밍 사용
								task.wait(0.5)
								
								if isAlive then
									local fwd = hrp.CFrame.LookVector
									local startPos = hrp.Position
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											local pDir = pRoot.Position - startPos
											local forwardDist = fwd:Dot(pDir)
											local rightDist = hrp.CFrame.RightVector:Dot(pDir)
											
											-- 전방 0~18 스터드 안쪽, 좌우폭 3스터드(총 너비 6) 안쪽일 경우 적중
											if forwardDist > 0 and forwardDist <= thrustLength and math.abs(rightDist) <= thrustWidth/2 and math.abs(pRoot.Position.Y - hrp.Position.Y) < 10 then
												phum:TakeDamage(300) -- 찌르기 데미지 대폭 상향
												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService.Server.Controllers.NetController)
													NetController.FireClient(hitPlayer, "Player.Stun", fwd)
												end
											end
										end
									end
								end
								task.wait(0.2) -- 짧은 후딜레이
								
							-- 우선순위 4: 기본 대검 단일 공격 (Attack) - 근접 평타 베기 (거리 <= 8, 쿨 2.0초)
							elseif distToPlayer <= 8 then
								humanoid:MoveTo(hrp.Position) -- 정지
								
								local meleeCooldown = config.attackCooldown or 2.0
								if now - lastAttackTick >= meleeCooldown then
									lastAttackTick = now
									
									-- 플레이어 방향으로 즉시 회전 정렬
									local lookDir = (phrp.Position - hrp.Position)
									lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
									if lookDir.Magnitude > 0.1 then
										hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
									end
									
									-- [추가] 기본 평타 전방 원형 장판 (반경 11스터드) 생성
									local atkRadius = 11
									-- [버그 수정] 보스방 바닥 500.2 고정
									local floorY = 500.2
									
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "BFKAtkTelegraph"
									warnCircle.Shape = Enum.PartType.Cylinder
									warnCircle.Size = Vector3.new(0.4, atkRadius * 2, atkRadius * 2)
									-- 보스 앞쪽으로 살짝 치우친 판정 중심점
									local hitCenter = hrp.Position + (hrp.CFrame.LookVector * (atkRadius/3))
									warnCircle.CFrame = CFrame.new(hitCenter.X, floorY, hitCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
									warnCircle.Anchored = true
									warnCircle.CanCollide = false
									warnCircle.Material = Enum.Material.Neon
									warnCircle.Color = Color3.fromRGB(255, 0, 0)
									warnCircle.Transparency = 0.85
									warnCircle.Parent = workspace
									
									local ts = game:GetService("TweenService")
									ts:Create(warnCircle, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
									
									-- 0.8초 대기 (회피 시간 부여)
									task.wait(0.8)
									if warnCircle then warnCircle:Destroy() end
									
									if not isAlive then break end
									
									-- 1. 애니메이션 재생
									local animDuration = 1.0
									pcall(function()
										local animator = humanoid:FindFirstChildOfClass("Animator")
										local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
										local atkAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("BlueFlameKnight_Attack")
										if animator and atkAnim then
											local track = animator:LoadAnimation(atkAnim)
											if track then 
												track.Looped = false
												track:Play() 
												if track.Length > 0 then animDuration = track.Length end
											end
										end
									end)
									
									-- 2. 신규 참격 효과음 재생
									pcall(function()
										local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
										local swingSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_SwordSwing")
										if swingSound then
											local s = swingSound:Clone()
											s.Parent = hrp
											s:Play()
											game:GetService("Debris"):AddItem(s, 2)
										end
									end)
									
									-- [버그수정] 평타는 타격점이 애니메이션 중간(0.35초)이므로 하드코딩 타이밍 사용
									task.wait(0.35)
									
									if isAlive then
										for _, p in ipairs(Players:GetPlayers()) do
											local char = p.Character
											local phum = char and char:FindFirstChild("Humanoid")
											local pRoot = char and char:FindFirstChild("HumanoidRootPart")
											if phum and phum.Health > 0 and pRoot then
												-- 장판과 일치하는 히트박스 검사
												local dXZ = Vector3.new(pRoot.Position.X - hitCenter.X, 0, pRoot.Position.Z - hitCenter.Z).Magnitude
												if dXZ <= atkRadius and math.abs(pRoot.Position.Y - hitCenter.Y) < 10 then
													phum:TakeDamage(200) -- 평타 데미지 대폭 상향
													local hitPlayer = Players:GetPlayerFromCharacter(char)
													if hitPlayer then
														local NetController = require(ServerScriptService.Server.Controllers.NetController)
														local bounceDir = (pRoot.Position - hitCenter)
														bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
														NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.8)
													end
												end
											end
										end
									end
									task.wait(0.2) -- 짧은 후딜레이
								end
								
							-- 추격 상태
							else
								humanoid:MoveTo(targetPlayerPos)
								task.wait(0.3)
							end
						end
					elseif config.mobModelName == "GhostWizard" then
						--========================================================================
						-- [GhostWizard 전용 FSM 분기]: 속성(불, 물, 어둠) 단일 유령검 낙하 (원거리 전용, 근접 없음)
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()
						
						local CAST_RANGE_MAX = 50
						local castCooldown = config.attackCooldown or 3.0
						
						if distToPlayer <= CAST_RANGE_MAX and (now - (model:GetAttribute("LastCastTick") or 0) >= castCooldown) then
							model:SetAttribute("LastCastTick", now)
							humanoid:MoveTo(currentPos)
							
							-- 타겟을 향해 즉시 회전
							local lookDir = (targetPlayerPos - currentPos)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(currentPos, currentPos + lookDir.Unit)
							end
							-- 속성 결정 (1: 불, 2: 어둠)
							local elementType = math.random(1, 2)
							local elementColor
							local animSuffix
							if elementType == 1 then
								elementColor = Color3.fromRGB(255, 60, 40) -- Fire
								animSuffix = "Fire"
							else
								elementColor = Color3.fromRGB(130, 40, 255) -- Darkness
								animSuffix = "Dark"
							end
							-- 준비(캐스팅) 사운드 재생
							local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
							local castSound = sounds and sounds:FindFirstChild("Monster") and sounds.Monster:FindFirstChild("GhostWizard_MeteorCast")
							if castSound then
								local sfx = castSound:Clone()
								sfx.Parent = hrp
								sfx:Play()
								game.Debris:AddItem(sfx, 3)
							end
							
							-- 캐스팅 애니메이션 재생 (속성별 애니메이션)
							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local castAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("GhostWizard_Attack_" .. animSuffix)
								if animator and castAnim then
									local track = animator:LoadAnimation(castAnim)
									if track then track:Play() end
								end
							end)
							
							task.wait(0.5) -- 캐스팅 딜레이
							if not isAlive then return end
							
							-- 타겟 바닥 찾기
							local currentTargetPos = targetPlayerPos
							if phrp and phrp.Parent then currentTargetPos = phrp.Position end
							
							local targetFloorY = currentTargetPos.Y - 2.5
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							local rayStart = Vector3.new(currentTargetPos.X, currentTargetPos.Y + 2, currentTargetPos.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								targetFloorY = rayResult.Position.Y + 0.2
							end
							
							if elementType == 1 then
								-- [불 속성]: 메테오 낙하 (불도마뱀 스타일 리팩터링)
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "WizardMeteorTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, 16, 16)
								warnCircle.CFrame = CFrame.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = elementColor
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								local castStartTime = os.clock()
								local telegraphDuration = 0.8
								local ts = game:GetService("TweenService")
								ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								
								-- 캐스팅 동안 플레이어 방향으로 실시간 회전 정렬 (불도마뱀 방식)
								while os.clock() - castStartTime < telegraphDuration and isAlive do
									if phrp and phrp.Parent then
										local ld = (phrp.Position - hrp.Position)
										ld = Vector3.new(ld.X, 0, ld.Z)
										if ld.Magnitude > 0.1 then
											hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + ld.Unit)
										end
									end
									task.wait(0.05)
								end
								
								warnCircle:Destroy()
								
								if isAlive then
									-- 단일 원형 운석(Meteor) 생성 (불도마뱀 이펙트 동일)
									local meteor = Instance.new("Part")
									meteor.Name = "Fireball"
									meteor.Shape = Enum.PartType.Ball
									meteor.Size = Vector3.new(3, 3, 3)
									meteor.Color = Color3.fromRGB(255, 120, 0)
									meteor.Material = Enum.Material.Neon
									meteor.Anchored = true
									meteor.CanCollide = false
									meteor.Position = Vector3.new(currentTargetPos.X, targetFloorY + 25, currentTargetPos.Z)
									meteor.Parent = workspace
									
									local attackPos = Vector3.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z)
									local fallTime = 0.35
									local fallTween = ts:Create(meteor, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
										Position = attackPos
									})
									fallTween:Play()
									task.wait(fallTime)
									
									meteor:Destroy()
									
									-- 타격음
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local impactSound = sounds and sounds:FindFirstChild("Monster") and sounds.Monster:FindFirstChild("GhostWizard_MeteorImpact")
									if impactSound then
										local soundPart = Instance.new("Part")
										soundPart.Anchored = true
										soundPart.CanCollide = false
										soundPart.Transparency = 1
										soundPart.CFrame = CFrame.new(attackPos)
										soundPart.Parent = workspace
										
										local sfx = impactSound:Clone()
										sfx.Parent = soundPart
										sfx:Play()
										game.Debris:AddItem(soundPart, 3)
									end
									
									if isAlive then
										-- Explosion 오브젝트 생성 (기본 폭발 이펙트 보이게 함)
										local exp = Instance.new("Explosion")
										exp.BlastRadius = 8
										exp.BlastPressure = 0
										exp.Position = attackPos
										exp.ExplosionType = Enum.ExplosionType.NoCraters
										exp.Parent = workspace
										
										-- 데미지 판정 및 플래시
										for _, p in ipairs(Players:GetPlayers()) do
											local char = p.Character
											local phum = char and char:FindFirstChild("Humanoid")
											local pRoot = char and char:FindFirstChild("HumanoidRootPart")
											
											if phum and phum.Health > 0 and pRoot then
												local dist = (pRoot.Position - attackPos).Magnitude
												if dist <= 8 then
													phum:TakeDamage(config.baseDamage)
													
													local bounceDir = (pRoot.Position - attackPos)
													bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
													local NetController = require(ServerScriptService.Server.Controllers.NetController)
													NetController.FireClient(p, "Player.Stun", bounceDir * 1.3)
													
													task.spawn(function()
														local highlight = Instance.new("Highlight")
														highlight.Name = "DamageFlash"
														highlight.FillColor = elementColor
														highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
														highlight.FillTransparency = 0.4
														highlight.OutlineTransparency = 0
														highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
														highlight.Adornee = char
														highlight.Parent = char
														task.wait(0.2)
														if highlight and highlight.Parent then highlight:Destroy() end
													end)
												end
											end
										end
									end
								end
							else
								-- [어둠 속성]: 독안개(Poison Fog) 생성
								local pDuration = 6.0
								local pRadius = 10.0
								local pDamage = config.baseDamage * 0.5 -- 틱당 데미지
								
								-- 장판(Telegraph) 생성
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "WizardFogTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, pRadius * 2, pRadius * 2)
								warnCircle.CFrame = CFrame.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = elementColor
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace
								
								local ts = game:GetService("TweenService")
								ts:Create(warnCircle, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
								task.wait(0.6)
								warnCircle:Destroy()
								
								if isAlive then
									local cloudFloorPos = Vector3.new(currentTargetPos.X, targetFloorY, currentTargetPos.Z)
									
									local cloud = Instance.new("Part")
									cloud.Name = "DarkFogCloud"
									cloud.Shape = Enum.PartType.Cylinder
									cloud.Size = Vector3.new(0.2, pRadius * 2, pRadius * 2)
									cloud.CFrame = CFrame.new(cloudFloorPos) * CFrame.Angles(0, 0, math.rad(90))
									cloud.Anchored = true
									cloud.CanCollide = false
									cloud.Material = Enum.Material.SmoothPlastic
									cloud.Color = elementColor
									cloud.Transparency = 0.85
									cloud.Parent = workspace
									
									local pe = Instance.new("ParticleEmitter")
									pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
									pe.Color = ColorSequence.new(elementColor, Color3.fromRGB(80, 0, 150))
									pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(0.5, 12), NumberSequenceKeypoint.new(1, 15)})
									pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1.0)})
									pe.Lifetime = NumberRange.new(3, 5)
									pe.Rate = 50
									pe.Speed = NumberRange.new(1, 4)
									pe.SpreadAngle = Vector2.new(90, 90)
									pe.Rotation = NumberRange.new(0, 360)
									pe.RotSpeed = NumberRange.new(-20, 20)
									pe.ZOffset = 1
									pe.EmissionDirection = Enum.NormalId.Top
									pe.Shape = Enum.ParticleEmitterShape.Cylinder
									pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
									pe.Parent = cloud
									
									task.spawn(function()
										local ticks = math.floor(pDuration)
										for i = 1, ticks do
											if not cloud or not cloud.Parent then break end
											
											for _, p in ipairs(Players:GetPlayers()) do
												local char = p.Character
												local phum = char and char:FindFirstChild("Humanoid")
												local pRoot = char and char:FindFirstChild("HumanoidRootPart")
												if phum and phum.Health > 0 and pRoot then
													local dXZ = math.sqrt(math.pow(pRoot.Position.X - cloudFloorPos.X, 2) + math.pow(pRoot.Position.Z - cloudFloorPos.Z, 2))
													if dXZ <= pRadius and math.abs(pRoot.Position.Y - cloudFloorPos.Y) < 10 then
														phum:TakeDamage(pDamage)
														task.spawn(function()
															local highlight = Instance.new("Highlight")
															highlight.FillColor = Color3.fromRGB(150, 0, 200)
															highlight.OutlineColor = Color3.fromRGB(100, 255, 100)
															highlight.FillTransparency = 0.5
															highlight.Adornee = char
															highlight.Parent = char
															task.wait(0.2)
															if highlight and highlight.Parent then highlight:Destroy() end
														end)
													end
												end
											end
											
											task.wait(1.0)
										end
										
										if cloud then
											if pe then pe.Enabled = false end
											local fade = ts:Create(cloud, TweenInfo.new(1.0), {Transparency = 1})
											fade:Play()
											fade.Completed:Wait()
											cloud:Destroy()
										end
									end)
								end
							end
						else
							humanoid:MoveTo(targetPlayerPos)
						end
					else
						--========================================================================
						-- [일반 몬스터 (Slime, HornedLarva 등) Melee 전투 FSM 분기]
						--========================================================================
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
								
								-- 공격 전 텔레그래프(Telegraph) 히트박스 경고 장치!
								local telegraphDuration = config.telegraphDuration or 1.1 -- 1.1초 대기 후 공격판정 (회피 시간 확보)
								local mobRootPos = hrp.Position
								
								task.spawn(function()
									-- 1. 바닥 경고 이펙트 생성 (네온 레드 원반)
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "SlimeAtkTelegraph"
									warnCircle.Shape = Enum.PartType.Cylinder
									warnCircle.Size = Vector3.new(0.4, ATTACK_RANGE * 2, ATTACK_RANGE * 2)
									
									-- [정밀 지면 밀착] 레이캐스트로 몬스터 바로 아래 실제 바닥 고도 측정!
									local rayParams = RaycastParams.new()
									rayParams.FilterType = Enum.RaycastFilterType.Exclude
									rayParams.FilterDescendantsInstances = {model}
									local rayResult = workspace:Raycast(mobRootPos, Vector3.new(0, -50, 0), rayParams)
									
									local floorPos
									if rayResult then
										floorPos = rayResult.Position + Vector3.new(0, 0.1, 0)
									else
										local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
										floorPos = mobRootPos - Vector3.new(0, groundOffset - 0.2, 0)
									end
									
									warnCircle.CFrame = CFrame.new(floorPos) * CFrame.Angles(0, 0, math.rad(90)) -- 눕히기
									warnCircle.Anchored = true
									warnCircle.CanCollide = false
									warnCircle.CanTouch = false
									warnCircle.CanQuery = false
									warnCircle.CastShadow = false
									warnCircle.Material = Enum.Material.Neon
									warnCircle.Color = Color3.fromRGB(255, 0, 0)
									warnCircle.Transparency = 0.85
									warnCircle.Parent = workspace
									
									local ts = game:GetService("TweenService")
									local flashTween = ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
										Transparency = 0.5
									})
									flashTween:Play()

									-- 2. 선행 딜레이 대기
									task.wait(telegraphDuration)
									
									-- 3. 최종 판정 및 데미지 적용
									if isAlive and targetPlayer and targetPlayer.Parent and targetPlayer:FindFirstChild("HumanoidRootPart") then
										local currentPhrp = targetPlayer.HumanoidRootPart
										local currentDist = (mobRootPos - currentPhrp.Position).Magnitude
										
										if currentDist <= ATTACK_RANGE + 1.5 then
											local dmg = config.baseDamage or 5
											local currentPhum = targetPlayer:FindFirstChild("Humanoid")
											if currentPhum and currentPhum.Health > 0 then
												currentPhum:TakeDamage(dmg)
												
												-- [Knockback Stun]
												local bounceDir = (currentPhrp.Position - mobRootPos)
												bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
												local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
												if hitPlayer then
													local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
													local NetController = require(Controllers:WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir)
												end
												
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
									
									warnCircle:Destroy()
								end)
							end
						else
							humanoid:MoveTo(phrp.Position)
						end
					end
					task.wait(TICK_RATE)
			else
				-- [B. 평화 모드] 배회 (Wander) - 스폰 중심(spawnCenter)을 향해 안전하게 복귀하거나 배회합니다.
				local nextDest = getNextSpawnPosition(config, index)
				
				-- [건물/장애물 충돌 회피 위스커(Whisker) 로직]
				local dir = nextDest - hrp.Position
				local dist = math.min(dir.Magnitude, 20)
				if dist > 2 then
					local rayParams = RaycastParams.new()
					rayParams.FilterDescendantsInstances = {model}
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					-- 가슴 높이에서 가려는 방향으로 레이캐스트 발사
					local rayPos = hrp.Position + Vector3.new(0, 2, 0)
					local ray = workspace:Raycast(rayPos, dir.Unit * dist, rayParams)
					if ray then
						-- 벽이나 건물에 막힌 경우, 무식하게 머리를 박지 않고 좌우로 랜덤하게 우회 배회함
						local detourRight = hrp.CFrame.RightVector * (math.random() > 0.5 and 15 or -15)
						nextDest = hrp.Position + detourRight
					end
				end
				
				humanoid:MoveTo(nextDest)
				
				local arrived = false
				local c = humanoid.MoveToFinished:Connect(function() arrived = true end)
				
				local startWait = os.clock()
				local stuckFrames = 0
				while not arrived and os.clock() - startWait < 6 and isAlive do
					task.wait(TICK_RATE)
					
					-- [벽 걸림 실시간 감지 탈출 AI]
					local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
					if speed < 0.6 and humanoid.MoveDirection.Magnitude > 0.1 then
						stuckFrames = stuckFrames + 1
						if stuckFrames > 3 then -- 약 1.5초간 벽에 대고 헛발질한 경우
							-- 즉시 180도 정반대 방향으로 돌아서 이동하여 탈출!
							local escapeDest = hrp.Position - hrp.CFrame.LookVector * 15
							humanoid:MoveTo(escapeDest)
							task.wait(1.0) -- 1초간 뒤돌아서 힘차게 걸어가기
							break -- 현재 배회루프 종료하고 새로운 배회지점 재추출
						end
					else
						stuckFrames = 0
					end
					
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
				
				if isAlive then
					task.wait(math.random(2, 4))
				end
			end
		end
	end)

		humanoid.Died:Connect(function()
			isAlive = false
			
			-- 기사 보스 사망 시 웅장한 사망 소멸 사운드 재생 연동
			if config.mobModelName == "BlueFlameKnight" then
				pcall(function()
					local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
					local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
					local deathSound = monsterSounds and monsterSounds:FindFirstChild("BlueFlameKnight_Death")
					if deathSound then
						local s = deathSound:Clone()
						s.Parent = hrp
						s:Play()
						game:GetService("Debris"):AddItem(s, 8)
					end
				end)
			end
			
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
				if PlayerStatService then
					if PlayerStatService.addXP then
						PlayerStatService.addXP(killer.UserId, xpReward, "Hunt_" .. (config.mobDisplayName or "Mob"))
					end
					if PlayerStatService.incrementKill then
						PlayerStatService.incrementKill(killer.UserId, config.mobDisplayName or "Mob")
					end
					print(string.format("[MobSpawnService] Awarded %d XP and updated kills for %s killing %s", xpReward, killer.Name, config.mobDisplayName or "Mob"))
				end
			end

			-- ★ 사망 시 아이템 드롭 처리
			local deathPos = model:GetPivot().Position
			spawnLoot(config.dropTableId or config.mobModelName or "Slime", deathPos, killer)
			
			-- 페이드 아웃 시간(1.5초) 후 시체 모델 완전히 삭제 (보이지 않는 물리 충돌/길막 버그 원천 차단)
			task.delay(1.5, function()
				if model then model:Destroy() end
			end)
			
			-- 시체가 파괴된 상태로 설정된 리스폰 시간 대기
			local respawnDelay = math.max(config.respawnDelay or 15.0, 1.5)
			task.wait(respawnDelay)
			
			local key = areaId .. "_" .. index
			-- 재스폰 시 다시 createMobModel을 호출하여 '새로운 랜덤 위치'를 추출하게 함!
			activeMobs[key] = createMobModel(areaId, index, config)
		end)
	end

	-- [DEBUG] 최종 스폰된 몬스터의 정확한 월드 피벗 및 물리 속성 정밀 진단 (도배 방지를 위해 비활성화)
	--[[
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
	--]]

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
			
			-- print(string.format("[MobSpawnService] Successfully auto-spawned %d Mobs for Area: %s!", spawnLoopCount, areaId))
		end
	end)
end

return MobSpawnService
