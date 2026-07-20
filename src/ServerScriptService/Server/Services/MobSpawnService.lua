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

local Debris = game:GetService("Debris")

local function playBossSound(soundName, host, volume)
	local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
	local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster") and soundRoot.Monster:FindFirstChild("DesertGuardian")
	if not monsterSounds or not host then return end
	local template = monsterSounds:FindFirstChild(soundName)
	if template and template:IsA("Sound") then
		local sound = template:Clone()
		local finalVolume = volume
		if not finalVolume then
			local lowerName = string.lower(soundName)
			if string.find(lowerName, "charge") or string.find(lowerName, "telegraph") then
				finalVolume = 0.2
			else
				finalVolume = 0.5
			end
		end
		sound.Volume = finalVolume
		sound.Parent = host
		sound:Play()
		Debris:AddItem(sound, math.max(sound.TimeLength + 0.5, 3.0))
	end
end

local function dealDamageToHumanoid(phum: Humanoid, rawDamage: number, mobLevel: number?)
	if not phum or phum.Health <= 0 then return end
	local char = phum.Parent
	local defense = 0
	if char then
		defense = tonumber(char:GetAttribute("Defense")) or 0
	end

	-- Defense damage reduction formula: damage = rawDamage * (100 / (100 + defense))
	local finalDamage = rawDamage * (100 / (100 + defense))

	-- 레벨 차이 보정: 플레이어가 낮은 레벨일수록 더 많은 피해를 받음
	if mobLevel and mobLevel > 1 then
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then
			local playerLevel = PlayerStatService.getLevel(player.UserId) or 1
			local diff = mobLevel - playerLevel
			if diff > 0 then
				finalDamage = finalDamage * (1 + diff * 0.1)
			end
		end
	end

	finalDamage = math.max(1, math.floor(finalDamage + 0.5))
	phum:TakeDamage(finalDamage)
end

local function resolveSpawnConfig(config, index)
	if type(config) ~= "table" then
		return config
	end

	local entry = config.spawnEntries and config.spawnEntries[index]
	if type(entry) ~= "table" then
		return config
	end

	local merged = {}
	for key, value in pairs(config) do
		merged[key] = value
	end
	for key, value in pairs(entry) do
		merged[key] = value
	end

	return merged
end

local function getSpawnConfigForSlot(areaId, index, fallbackConfig)
	local spawnDataList = DataService.get("MobSpawnData")
	local areaConfig = spawnDataList and spawnDataList[areaId]
	if type(areaConfig) == "table" then
		return resolveSpawnConfig(areaConfig, index)
	end
	return resolveSpawnConfig(fallbackConfig, index)
end

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

	for i, entry in ipairs(dropTable) do
		-- [중복 방지] 이미 배운 패시브 스킬의 스킬북은 드롭되지 않도록 제외
		-- (예: "하늘의 자격"(SKILL_RUNE_HEAVEN)을 이미 장착/습득한 플레이어에게는 BOOK_HEAVEN이 드롭되지 않음)
		if entry.itemId == "BOOK_HEAVEN" and killerPlayer then
			local ok, SkillService = pcall(function()
				return require(Services:WaitForChild("SkillService"))
			end)
			if ok and SkillService and SkillService.isSkillUnlocked(killerPlayer.UserId, "SKILL_RUNE_HEAVEN") then
				continue
			end
		end

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
							WorldDropService.spawnDrop(pos, entry.itemId, remaining, nil, nil, "DISCARD")
						end
					end
				else
					-- 그 외의 슬라임 귀고리(SLIME_EARRING), 뿔 애벌레 반지(HORNED_LARVA_RING) 등 특별 악세사리 및 무기는 월드 드롭 생성
					local ok, err = WorldDropService.spawnDrop(pos, entry.itemId, count)
					if not ok then
						warn(string.format("[MobSpawnService] Failed to spawn item drop '%s': %s", entry.itemId, tostring(err)))
					end
				end
			end
		end
	end

	-- [Skill Book Drop Logic] 몬스터 처치 시 스킬북 1% 개별 드롭 분리
	if killerPlayer then
		local bookItemId = nil
		if mobName == "IceDragon" or mobName == "IceKnight" then
			bookItemId = "BOOK_DROPLET" -- 물방울 (물 속성)
		elseif mobName == "Stump" then
			bookItemId = "BOOK_EMBER" -- 불씨 (화염 속성)
		elseif mobName == "SmallGolem" then
			bookItemId = "BOOK_ROCK" -- 짙은밤 (어둠 속성)
		end

		if bookItemId then
			local bookRoll = math.random(1, 100)
			if bookRoll <= 1 then
				local ok, err = WorldDropService.spawnDrop(pos, bookItemId, 1)
				if ok then
					print(string.format("[MobSpawnService] Skill Book Dropped for %s (%s from %s)", killerPlayer.Name, bookItemId, mobName))
				else
					warn(string.format("[MobSpawnService] Skill Book Drop Failed for %s: %s", bookItemId, tostring(err)))
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

local function deformSlime(model, scaleX, scaleY, scaleZ, duration)
	local ts = game:GetService("TweenService")
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local originalSize = part:GetAttribute("OriginalSize")
			if not originalSize then
				originalSize = part.Size
				part:SetAttribute("OriginalSize", originalSize)
			end
			ts:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(originalSize.X * scaleX, originalSize.Y * scaleY, originalSize.Z * scaleZ)
			}):Play()
		end
	end
end

local function createMobModel(areaId, index, config)
	-- 실시간으로 스폰할 정확한 위치 계산! (파트 있으면 파트 위 랜덤 위치)
	local spawnPos = getNextSpawnPosition(config, index)
	-- [버그수정용] 지형 레이캐스트로 찾은 "순수 바닥 높이"(버퍼 +5 반영 전)를 별도 보관.
	-- 아래 완착 보정 단계가 spawnPos.Y(이미 +5 버퍼 포함)를 기준으로 또 HipHeight를 더해 이중으로
	-- 떠버리는 문제를 막기 위함 (모델 스케일이 클수록 HipHeight도 커져서 이 이중 오프셋이 크게 두드러짐).
	local terrainGroundY = nil

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local monstersFolder = assetsFolder and assetsFolder:FindFirstChild("Monsters")
	local mobAsset = monstersFolder and monstersFolder:FindFirstChild(config.mobModelName)

	local model
	if mobAsset then
		-- 실물 에셋 복제 스폰
		model = mobAsset:Clone()

		-- [중요] 만약 모델이 이중 중첩되어 있는 경우 (예: Samurai -> elite samurai -> Humanoid)
		-- 실제 Humanoid를 품고 있는 서브 모델을 메인 모델로 승격시키고 겉껍질을 제거합니다.
		local innerHumanoid = model:FindFirstChildOfClass("Humanoid", true)
		if innerHumanoid and innerHumanoid.Parent ~= model then
			local actualModel = innerHumanoid.Parent
			if actualModel:IsA("Model") then
				actualModel.Name = model.Name
				-- 임시로 부모를 nil로 뺀 뒤 겉껍질을 제거하고 model 변수를 서브 모델로 교체
				actualModel.Parent = nil
				model:Destroy()
				model = actualModel
			end
		end

		-- [지형 인식 스폰 (Terrain Raycast)]
		if not config.skipTerrainScan then
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {model}
			raycastParams.RespectCanCollide = true

			local startOffset = config.raycastStartOffsetY or (config.isIndoor and 20 or 200)
			local rayDist = config.raycastDepth or (config.isIndoor and -100 or -1000)

			local startY = spawnPos.Y + startOffset
			if not config.raycastStartOffsetY and not config.isIndoor then
				startY = math.max(startY, 500)
			end

			local skyPos = Vector3.new(spawnPos.X, startY, spawnPos.Z)
			local rayResult = workspace:Raycast(skyPos, Vector3.new(0, rayDist, 0), raycastParams)

			if rayResult then
				-- 바닥(Floor) 정확한 고도를 찾아내고, 모델이 지형에 끼이지 않도록 살짝(5스터드) 위에서 스폰시킴
				-- 이후 아래에 있는 하이브리드 HipHeight 엔진이 알아서 중력과 함께 완벽히 안착시킴
				terrainGroundY = rayResult.Position.Y
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

	-- [바다 테마 리스킨] 서쪽 협곡 보스는 DesertGuardian 에셋/애니메이션/FSM을 그대로 재사용하지만,
	-- workspace 인스턴스 이름이 똑같이 "DesertGuardian"이면 RaidBossData/HUDUI의 보스 UI 탐색
	-- (workspace:FindFirstChild(mobModelName))이 사막 보스와 구분을 못해 이름표/체력바 테마가 뒤섞임.
	-- 이름만 별도로 바꿔서 두 존을 완전히 분리한다.
	if config.spawnAreaId == "AbyssGuardianZone" then
		model.Name = "AbyssGuardian"
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
		end)
	end

	-- Jellyfish: PointLight 기본 OFF (공격 시에만 켜짐)
	if config.mobModelName == "Jellyfish" then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				desc.Enabled = false
			end
		end
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
			animator = Instance.new("Animator", humanoid)
		end
	end
	model:SetAttribute("MaxHealth", config.maxHealth or 100)
	model:SetAttribute("CurrentHealth", config.maxHealth or 100)
	model:SetAttribute("MobId", config.mobModelName or "Slime")
	model:SetAttribute("XPReward", config.xpReward or 25)
	model:SetAttribute("Level", config.level or 1)

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
					-- [버그수정] 젤리피쉬는 PlatformStand+BodyVelocity로 움직이는 3D 자유유영 몹이라
					-- HRP 충돌을 켜두면 바다 바닥/벽에 물리적으로 막혀서 플레이어 높이까지 완전히
					-- 내려오지 못하는 문제가 있었음 (사용자가 직접 지적: "젤리피쉬 하단에 뭐가 있어서
					-- 일정부분 못내려가는거 아니냐"). 젤리피쉬만 HRP 충돌을 꺼서 자유롭게 통과하게 함.
					p.CanCollide = (config.mobModelName ~= "Jellyfish")
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

		if config.visualGroundSink and config.visualGroundSink > 0 then
			local welds = {}
			for _, w in ipairs(model:GetDescendants()) do
				if w:IsA("WeldConstraint") then
					w.Enabled = false
					table.insert(welds, w)
				end
			end

			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") and p ~= hrp and p.Name ~= "CombatHitbox" then
					p.CFrame = p.CFrame - Vector3.new(0, config.visualGroundSink, 0)
				end
			end

			for _, w in ipairs(welds) do
				w.Enabled = true
			end
		end

		if config.hitboxScaleFromBounds then
			local _, boundsSize = model:GetBoundingBox()
			local scale = config.hitboxScaleFromBounds
			local hitboxSize = Vector3.new(
				math.max(2, boundsSize.X * (scale.x or 1)),
				math.max(2, boundsSize.Y * (scale.y or 1)),
				math.max(2, boundsSize.Z * (scale.z or 1))
			)
			local combatHitbox = model:FindFirstChild("CombatHitbox")
			if not combatHitbox then
				combatHitbox = Instance.new("Part")
				combatHitbox.Name = "CombatHitbox"
				combatHitbox.Transparency = 1
				combatHitbox.Anchored = false
				combatHitbox.CanCollide = false
				combatHitbox.CanTouch = false
				combatHitbox.CanQuery = true
				combatHitbox.Massless = true
				combatHitbox.Size = hitboxSize
				combatHitbox.CFrame = hrp.CFrame
				combatHitbox.Parent = model

				-- [버그수정] WeldConstraint는 Part0/Part1이 모두 지정되는 순간의 상대 위치를 그대로 고정한다.
				-- 파트가 원점(0,0,0)에 있을 때 먼저 웰드를 걸면 그 잘못된 상대위치가 영구히 박혀버려서,
				-- 이후 CFrame을 hrp 위치로 옮겨도 웰드가 매 프레임 원래(잘못된) 상대위치로 되돌려버림.
				-- 반드시 위치/크기를 먼저 맞춘 뒤에 웰드를 걸어야 함.
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = combatHitbox
				weld.Parent = combatHitbox
			else
				combatHitbox.Size = hitboxSize
				combatHitbox.CFrame = hrp.CFrame
			end
			model:SetAttribute("HitboxRadius", math.max(hitboxSize.X, hitboxSize.Z) * 0.5)
			model:SetAttribute("HitboxHeight", hitboxSize.Y)
		else
			model:SetAttribute("HitboxRadius", math.max(hrp.Size.X, hrp.Size.Z) * 0.5)
			model:SetAttribute("HitboxHeight", hrp.Size.Y)
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
		
		local extents = model:GetExtentsSize()
		local head = model:FindFirstChild("Head")
		if head then
			bb.Adornee = head
			bb.StudsOffset = Vector3.new(0, head.Size.Y/2 + 1.5, 0)
		else
			bb.Adornee = hrp
			-- [버그수정] GetBoundingBox()는 Part.Size(비주얼 메쉬보다 훨씬 큰 보이지 않는 충돌
			-- 박스 크기) 기준이라 실제 렌더링되는 몸통보다 훨씬 위까지 계산돼버림 (Studio에서 마커
			-- 파트로 직접 확인: HRP는 이미 실제 몸통 꼭대기 근처에 있는데 GetBoundingBox 계산값은
			-- 천장까지 치솟아 있었음). 젤리피쉬는 HRP가 이미 몸통 꼭대기 근처이므로 작은 고정
			-- 오프셋만 추가.
			local yOff
			if config.mobModelName == "Jellyfish" then
				yOff = 8
			else
				yOff = extents.Y + 1.0
			end
			bb.StudsOffset = Vector3.new(0, yOff, 0)
		end
		
		bb.AlwaysOnTop = true
		bb.MaxDistance = 60 -- 너무 멀리있는건 안보여서 화면 깔끔하게 유지

		-- 1. 이름표 라벨 (레벨 배지 + 이름, RichText로 레벨만 금색 강조)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0, 16)
		nameLabel.BackgroundTransparency = 1
		nameLabel.RichText = true
		nameLabel.Text = string.format(
			'<font color="rgb(255,210,90)">Lv.%d</font>  %s',
			config.level or 1,
			config.mobDisplayName or config.mobModelName
		)
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextStrokeTransparency = 0.4
		nameLabel.Font = Enum.Font.SourceSansBold
		nameLabel.TextSize = 12 -- 미니멀 폰트사이즈
		nameLabel.Parent = bb

		-- 2. HP 바 컨테이너 (캡슐형 라운드 + 은은한 그라디언트로 고급스럽게)
		local hpBg = Instance.new("Frame")
		hpBg.Name = "HPBackground"
		hpBg.Size = UDim2.new(0.85, 0, 0, 10) -- [요청반영] 기존 15 -> 10으로 초슬림화!!
		hpBg.Position = UDim2.new(0.5, 0, 0, 16) -- 이름 바로 밑에 밀착
		hpBg.AnchorPoint = Vector2.new(0.5, 0)
		hpBg.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
		hpBg.BackgroundTransparency = 0.15
		hpBg.BorderSizePixel = 0
		hpBg.ClipsDescendants = true
		hpBg.Parent = bb

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(1, 0) -- 캡슐형으로 완전히 둥글게
		bgCorner.Parent = hpBg

		local bgStroke = Instance.new("UIStroke")
		bgStroke.Thickness = 1
		bgStroke.Color = Color3.fromRGB(0, 0, 0)
		bgStroke.Transparency = 0.2
		bgStroke.Parent = hpBg

		local bgGradient = Instance.new("UIGradient")
		bgGradient.Rotation = 90
		bgGradient.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), Color3.fromRGB(38, 38, 42))
		bgGradient.Parent = hpBg

		-- 3. 실제 채워지는 게이지 (Fill)
		local hpFill = Instance.new("Frame")
		hpFill.Name = "HPFill"
		hpFill.Size = UDim2.new(1, 0, 1, 0)
		hpFill.BackgroundColor3 = Color3.fromRGB(60, 220, 80)
		hpFill.BorderSizePixel = 0
		hpFill.ClipsDescendants = true
		hpFill.ZIndex = 2
		hpFill.Parent = hpBg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = hpFill

		-- 광택 효과: 게이지 위쪽 절반에 옅은 하이라이트를 얹어 유리질 느낌 부여
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"
		sheen.Size = UDim2.new(1, 0, 0.5, 0)
		sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sheen.BorderSizePixel = 0
		sheen.ZIndex = 3
		sheen.Parent = hpFill

		local sheenGradient = Instance.new("UIGradient")
		sheenGradient.Rotation = 90
		sheenGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		sheenGradient.Parent = sheen

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

				-- [포세이돈 전용] 아직 Poseidon_Idle/Poseidon_Walk 정식 애니메이션이 없어서
				-- (모델에 딸려온 AnimSaves.Walk는 발행되지 않은 KeyframeSequence 원본 데이터일
				-- 뿐이라 Animation.AnimationId로 바로 못 씀 - Studio 밖에서는 재생 불가) 우선
				-- 같은 이족보행 R6 무기 몹인 사무라이 걷기 모션으로 폴백. 추후 Animation Editor에서
				-- AnimSaves.Walk를 정식 발행해서 이 폴더에 Poseidon_Walk로 넣으면 자동으로 전환됨.
				if config.mobModelName == "Poseidon" then
					if not monsterAnims:FindFirstChild(idleAnimName) then
						idleAnimName = "Samurai_Idle"
					end
					if not monsterAnims:FindFirstChild(walkAnimName) then
						walkAnimName = "Samurai_Walk"
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
							if config.mobModelName == "IceDragon" or config.mobModelName == "CyclopsBat" then
								isMoving = true -- 아이스 드래곤과 사이클롭스 배트는 항상 날갯짓(Walk) 애니메이션 상태를 유지합니다.
							end

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
		-- [완착 보정] 스케일링/부모화 및 힙하이트 조정이 모두 완료된 후, 물리 엔진에 의한 지면 반발 또는 땅속 끼임 후 기어올라옴을 방지하기 위해 최종 스폰 높이 재조정!
		if hrp then
			pcall(function()
				local groundClearance = if config.groundClearance ~= nil then config.groundClearance else 0.1
				local baseGroundY = terrainGroundY or spawnPos.Y
				local heightOffset = humanoid.HipHeight + (hrp.Size.Y / 2) + groundClearance
				model:PivotTo(CFrame.new(spawnPos.X, baseGroundY + heightOffset, spawnPos.Z))

				if config.snapVisualToGround then
					local lowestY = math.huge
					for _, part in ipairs(model:GetDescendants()) do
						if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "CombatHitbox" and part.Transparency < 0.9 then
							local cf = part.CFrame
							local size = part.Size
							local halfHeight = 0.5 * (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
							lowestY = math.min(lowestY, cf.Position.Y - halfHeight)
						end
					end

					if lowestY < math.huge then
						local desiredBottomY = baseGroundY + groundClearance
						model:PivotTo(model:GetPivot() + Vector3.new(0, desiredBottomY - lowestY, 0))
					end
				end
			end)
		end
	end

	local isAlive = true

	-- [몸박 데미지] 몬스터 몸체(HRP)에 플레이어가 직접 닿으면 소량의 접촉 데미지가 들어감 (모든 몬스터 공통, 패턴 공격과 별개)
	if hrp then
		local touchCooldowns = {}
		local CONTACT_DAMAGE_COOLDOWN = 1.0
		hrp.Touched:Connect(function(other)
			if not isAlive then return end
			local otherChar = other.Parent
			local otherPlayer = otherChar and Players:GetPlayerFromCharacter(otherChar)
			local otherHum = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
			if not otherPlayer or not otherHum or otherHum.Health <= 0 then return end

			local now = os.clock()
			local last = touchCooldowns[otherPlayer.UserId] or 0
			if now - last < CONTACT_DAMAGE_COOLDOWN then return end
			touchCooldowns[otherPlayer.UserId] = now

			local contactDamage = config.contactDamage or math.max(1, math.floor((config.baseDamage or 10) * 0.15))
			dealDamageToHumanoid(otherHum, contactDamage, config.level)
		end)
	end

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
			local lastCheckerboardTick = 0 -- 크라켄 전용 체스판 물기둥 광역기 쿨타임
			local lastTsunamiLeapTick = 0 -- 포세이돈 전용 쓰나미 강하(기믹) 쿨타임
			local poseidonPatternBusy = false -- 포세이돈 전용 - 패턴 진행 중 다른 패턴이 끼어들지 못하게 잠금
			local jellyAttackBusy = false -- 젤리피쉬 전용 - 공격(전조+판정) 진행 중엔 몸통이 다시 떠오르지 못하게 고정
			local currentGimmickMode = 1
			local isBoss = (config.mobModelName == "BlueFlameKnight" or config.mobModelName == "StumpKing" or config.mobModelName == "Stump" or config.mobModelName == "DesertGuardian" or config.mobModelName == "Kraken" or config.mobModelName == "Poseidon")
			local spawnCenter = getNextSpawnPosition(config, index) -- 스폰 중심점 (배회 및 둥지 복귀 기준)

			-- [푸른불꽃 기사 전용 Phase 2 스태틱 변수군]
			local bfkPhase2Active = false
			local bfkAuraEmitters = {}

			-- [반응속도 및 감지혁신]: 스텀프/박쥐의 유저 인식 반경 상승, FSM 주기를 단축하여 극적인 초고속 즉시 타격 실현!
			local AGGRO_RADIUS = (config.mobModelName == "Stump") and 70 or ((config.mobModelName == "CyclopsBat") and 60 or ((config.mobModelName == "Jellyfish") and 40 or (isBoss and 40 or 30))) -- [수정] 90->25(과함)->40: 인식범위 너무 짧다는 피드백 반영
			local ATTACK_RANGE = (config.mobModelName == "FireLizard") and 18 or ((config.mobModelName == "StumpKing") and 15 or ((config.mobModelName == "Jellyfish") and 18 or ((config.mobModelName == "Kraken") and 42 or ((config.mobModelName == "Poseidon") and 16 or 6))))
			local TICK_RATE = (config.mobModelName == "Stump") and 0.12 or ((config.mobModelName == "CyclopsBat") and 0.15 or ((config.mobModelName == "Jellyfish") and 0.15 or (isBoss and 0.15 or 0.2)))

			-- [크라켄 전용] 절차적(Procedural) 촉수 애니메이션 - Motor6D 체인으로 만든 촉수 8개를
			-- 매 프레임 C0 회전을 갱신해서 물결처럼 흐느적거리게 함 (이동 중엔 더 크게, 정지 중엔 은은하게)
			-- [공격 패턴 연동] tentacleJoints/krakenAttackOverride는 아래쪽 공격 FSM에서도 공유해서 사용하므로
			-- task.spawn 바깥(코루틴 상위 스코프)에 선언해 접근 가능하게 함
			local tentacleJoints = {}
			local krakenAttackOverride = {}
			if config.mobModelName == "Kraken" then
				local tentaclesFolder = model:FindFirstChild("Tentacles")
				if tentaclesFolder then
					-- Part1(자식 파츠) 기준으로 Motor6D를 빠르게 찾기 위한 조회 테이블 구성
					local jointByChild = {}
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("Motor6D") then
							jointByChild[d.Part1] = d
						end
					end

					-- 촉수별로 [세그먼트 조인트, 원래 C0(휴식 자세)] 목록을 미리 수집
					for _, tentacleFolder in ipairs(tentaclesFolder:GetChildren()) do
						local joints = {}
						for si = 1, 5 do
							local seg = tentacleFolder:FindFirstChild("Seg" .. si)
							local joint = seg and jointByChild[seg]
							if joint then
								table.insert(joints, { motor = joint, restC0 = joint.C0 })
							end
						end
						if #joints > 0 then
							table.insert(tentacleJoints, joints)
						end
					end
				end

				task.spawn(function()
					local t = 0
					local lastPos = hrp.Position
					while model.Parent and humanoid.Health > 0 do
						local dt = task.wait(1 / 20)
						t += dt
						local curPos = hrp.Position
						local horizontalDelta = Vector3.new(curPos.X - lastPos.X, 0, curPos.Z - lastPos.Z).Magnitude
						local isMoving = (horizontalDelta / dt) > 0.5
						lastPos = curPos

						local amplitude = isMoving and 0.22 or 0.08
						local speed = isMoving and 3.2 or 1.1

						for ti, joints in ipairs(tentacleJoints) do
							if not krakenAttackOverride[ti] then
								local tentaclePhase = ti * 0.9 -- 촉수마다 위상을 어긋나게 해서 제각각 흐느적이도록
								for si, jointData in ipairs(joints) do
									local segPhase = si * 0.6 -- 마디마다 위상을 지연시켜 파도처럼 전달되는 움직임 연출
									local wave = math.sin(t * speed - segPhase - tentaclePhase) * amplitude
									local sway = math.cos(t * speed * 0.6 - segPhase - tentaclePhase) * amplitude * 0.5
									jointData.motor.C0 = jointData.restC0 * CFrame.Angles(wave, 0, sway)
								end
							end
						end
					end
				end)
			end

			-- [빅골렘 전용] 콰콰쾅 바위 타격 이펙트 함수
			local function playRockSmashEffect(pos, radius, soundName)
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
				local monsterSoundsFolder = game.ReplicatedStorage:FindFirstChild("Assets")
					and game.ReplicatedStorage.Assets:FindFirstChild("Sounds")
					and game.ReplicatedStorage.Assets.Sounds:FindFirstChild("Monster")
				local customSound = monsterSoundsFolder
					and ((soundName and monsterSoundsFolder:FindFirstChild(soundName)) or monsterSoundsFolder:FindFirstChild("BigGolem_Smash"))

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
					rock.CanCollide = false
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

			-- [크라켄 전용] 다리 내려찍기 충돌 이펙트 - playRockSmashEffect와 달리 원형 크레이터/충격파를
			-- 전혀 쓰지 않고, 경고 장판과 동일한 직사각형 영역 전체에 걸쳐 파편/흙먼지가 흩뿌려지도록 함
			local function playKrakenRectSmashEffect(centerPos: Vector3, flatDir: Vector3, rectW: number, rectL: number)
				local ts = game:GetService("TweenService")
				local rightDir = Vector3.new(-flatDir.Z, 0, flatDir.X)

				-- 직사각형 영역 전체(전방 0~rectL, 좌우 ±rectW/2)에 걸쳐 무작위로 파편을 흩뿌림 (원형 X)
				for _ = 1, 18 do
					local alongT = math.random()
					local acrossT = (math.random() - 0.5)
					local pos = centerPos + flatDir * (alongT * rectL) + rightDir * (acrossT * rectW)
					local rock = Instance.new("Part")
					rock.Name = "KrakenRockDebris"
					rock.Size = Vector3.new(math.random(2, 4), math.random(2, 4), math.random(2, 4))
					rock.Position = pos + Vector3.new(0, 2, 0)
					rock.Material = Enum.Material.Slate
					rock.Color = Color3.fromRGB(100, 100, 100)
					rock.CanCollide = false
					rock.Anchored = false
					rock.Parent = workspace

					local angle = math.random() * math.pi * 2
					local speed = math.random(30, 70)
					rock.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * speed, math.random(40, 90), math.sin(angle) * speed)
					rock.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))

					ts:Create(rock, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.2), { Transparency = 1 }):Play()
					game:GetService("Debris"):AddItem(rock, 3.0)
				end

				-- 직사각형 영역을 따라 흙먼지를 여러 지점에 분산 배치 (한 점에서 퍼지는 원형 연기 X)
				for i = 1, 4 do
					local t = (i - 0.5) / 4
					local pos = centerPos + flatDir * (t * rectL)
					local smokePart = Instance.new("Part")
					smokePart.Name = "KrakenSmashSmoke"
					smokePart.Size = Vector3.new(1, 1, 1)
					smokePart.Position = pos
					smokePart.Anchored = true
					smokePart.CanCollide = false
					smokePart.Transparency = 1
					smokePart.Parent = workspace
					local smoke = Instance.new("Smoke")
					smoke.Color = Color3.fromRGB(120, 110, 100)
					smoke.Size = rectW * 0.35
					smoke.Opacity = 0.45
					smoke.RiseVelocity = 12
					smoke.Parent = smokePart
					game:GetService("Debris"):AddItem(smokePart, 3)
					task.delay(0.4, function()
						if smoke then smoke.Enabled = false end
					end)
				end
			end

			-- [크라켄 전용] 체스판 물기둥 광역기 - 몸 주변을 체스판처럼 칸으로 나눠 생존/사망 구역을
			-- 표시하고, 잠시 후 사망 구역에서 물줄기가 솟아올라 그 안에 있으면 피해를 입음
			local function playKrakenCheckerboardAttack(mob, targetChar)
				local centerHrp = mob:FindFirstChild("HumanoidRootPart")
				if not centerHrp then return end
				local center = centerHrp.Position

				-- [수정] 거의 전역 범위로 대폭 확대 (10x10칸, 칸당 16스터드 = 총 160x160스터드)
				local gridSize = 10
				local cellSize = 16
				local halfSpan = (gridSize * cellSize) / 2

				-- [버그수정] 격자 범위(160x160)가 레이드룸 크기와 거의 같아서, 크라켄의 현재 위치를
				-- 그대로 중심으로 쓰면 격자가 방 벽 밖으로 튀어나가버림 -> 레이드룸(RaidArena) 경계
				-- 안에 격자 전체가 들어오도록 중심 좌표를 방 범위 안으로 고정(clamp)함
				local ARENA_X_MIN, ARENA_X_MAX = 663.4, 833.4
				local ARENA_Z_MIN, ARENA_Z_MAX = 117.6, 277.6
				local clampedX = math.clamp(center.X, ARENA_X_MIN + halfSpan, ARENA_X_MAX - halfSpan)
				local clampedZ = math.clamp(center.Z, ARENA_Z_MIN + halfSpan, ARENA_Z_MAX - halfSpan)
				-- 방 폭(160)이 격자 폭(160)과 거의 같아 clamp 여유가 없을 수 있으므로, 그 경우 방 중앙으로 고정
				if ARENA_X_MIN + halfSpan > ARENA_X_MAX - halfSpan then
					clampedX = (ARENA_X_MIN + ARENA_X_MAX) / 2
				end
				if ARENA_Z_MIN + halfSpan > ARENA_Z_MAX - halfSpan then
					clampedZ = (ARENA_Z_MIN + ARENA_Z_MAX) / 2
				end
				center = Vector3.new(clampedX, center.Y, clampedZ)

				local telegraphDuration = 1.8

				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { mob }
				local rayResult = workspace:Raycast(center + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams)
				local floorY = rayResult and rayResult.Position.Y or (center.Y - 20)

				local tilesFolder = Instance.new("Folder")
				tilesFolder.Name = "KrakenCheckerboard"
				tilesFolder.Parent = workspace

				-- [수정] 규칙적인 체스판(i+j 짝/홀) 무늬가 아니라 칸마다 완전히 독립적인 난수로 사망/생존을 결정.
				-- 사망 구역만 4칸이 붙어있거나 뭉치는 등 완전히 불규칙한 배치가 나올 수 있음.
				-- 색상은 항상 고정: 빨강=사망, 파랑=생존 (어느 색이 사망인지는 절대 무작위로 바뀌지 않음)
				local deathCells = {}
				local cellRecords = {}
				for i = 0, gridSize - 1 do
					for j = 0, gridSize - 1 do
						local isDeath = math.random() < 0.5
						table.insert(cellRecords, { i = i, j = j, isDeath = isDeath })
					end
				end
				-- 극히 드문 경우(전부 생존)를 대비해 최소 1칸은 사망 구역으로 강제 보장
				local hasDeath = false
				for _, rec in ipairs(cellRecords) do
					if rec.isDeath then hasDeath = true break end
				end
				if not hasDeath then
					cellRecords[math.random(1, #cellRecords)].isDeath = true
				end

				-- [수정] 생존 구역은 별도 표시를 하지 않음 - 타일이 없는 자리가 곧 생존 구역.
				-- 오직 사망 구역(빨강)만 타일을 생성함.
				for _, rec in ipairs(cellRecords) do
					if rec.isDeath then
						local cellCenterX = center.X - halfSpan + cellSize * (rec.i + 0.5)
						local cellCenterZ = center.Z - halfSpan + cellSize * (rec.j + 0.5)

						local tile = Instance.new("Part")
						tile.Name = "DeathTile"
						tile.Size = Vector3.new(cellSize - 0.4, 0.3, cellSize - 0.4)
						tile.CFrame = CFrame.new(cellCenterX, floorY + 0.2, cellCenterZ)
						tile.Anchored = true
						tile.CanCollide = false
						tile.CanTouch = false
						tile.CanQuery = false
						tile.CastShadow = false
						tile.Material = Enum.Material.Neon
						tile.Color = Color3.fromRGB(255, 30, 30)
						tile.Transparency = 0.55
						tile.Parent = tilesFolder

						table.insert(deathCells, { x = cellCenterX, z = cellCenterZ, part = tile })
					end
				end

				-- 사망 구역만 깜빡여서 위험을 알림
				task.spawn(function()
					local elapsed = 0
					while elapsed < telegraphDuration and tilesFolder.Parent do
						for _, cell in ipairs(deathCells) do
							if cell.part.Parent then cell.part.Transparency = 0.25 end
						end
						task.wait(0.2)
						elapsed += 0.2
						for _, cell in ipairs(deathCells) do
							if cell.part.Parent then cell.part.Transparency = 0.65 end
						end
						task.wait(0.2)
						elapsed += 0.2
					end
				end)

				task.wait(telegraphDuration)

				-- 사망 구역에서 물줄기 솟아오름
				local ts = game:GetService("TweenService")
				-- 실제 게임에서 쓰는 물 텍스처 재사용 (DROPLET_Hit / RUNE_WAVE_ACTIVE_Aura)
				local WATER_TEX_1 = "rbxassetid://15990457929" -- WAVE_Aura Water1 (넓게 퍼지는 물결)
				local WATER_TEX_2 = "rbxassetid://15081467386" -- DROPLET_Hit Water Slash 2 (튀는 물보라)

				for _, cell in ipairs(deathCells) do
					task.spawn(function()
						if cell.part.Parent then cell.part:Destroy() end

						local spoutHeight = 26
						local spout = Instance.new("Part")
						spout.Name = "KrakenWaterSpout"
						spout.Shape = Enum.PartType.Cylinder
						spout.Material = Enum.Material.Glass
						spout.Color = Color3.fromRGB(100, 180, 235)
						spout.Transparency = 0.35
						spout.Anchored = true
						spout.CanCollide = false
						spout.CanTouch = false
						spout.CanQuery = false
						spout.CastShadow = false
						spout.Size = Vector3.new(0.1, cellSize * 0.55, cellSize * 0.55)
						spout.CFrame = CFrame.new(cell.x, floorY, cell.z) * CFrame.Angles(0, 0, math.rad(90))
						spout.Parent = workspace

						-- 기둥 내부에서 계속 위로 솟구치는 물살 (파트에 직접 부착 - 파트가 커지는 동안 계속 중심에서 뿜어져 나옴)
						local risePe = Instance.new("ParticleEmitter")
						risePe.Texture = WATER_TEX_1
						risePe.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
						risePe.Size = NumberSequence.new({
							NumberSequenceKeypoint.new(0, cellSize * 0.5),
							NumberSequenceKeypoint.new(1, cellSize * 0.3),
						})
						risePe.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.2),
							NumberSequenceKeypoint.new(0.8, 0.4),
							NumberSequenceKeypoint.new(1, 1),
						})
						risePe.Lifetime = NumberRange.new(0.35, 0.55)
						risePe.Rate = 90
						risePe.Speed = NumberRange.new(3, 6)
						risePe.SpreadAngle = Vector2.new(8, 8)
						risePe.Rotation = NumberRange.new(0, 360)
						risePe.EmissionDirection = Enum.NormalId.Top
						risePe.Parent = spout

						-- [고도화] 실제 게임 분수 이펙트(Assets/VFX/Water의 SquirtWater)를 그대로 재사용해서
						-- 진짜 물이 솟구쳤다 중력으로 떨어지는 자연스러운 물줄기를 기둥 밑동에 덧붙임
						local squirtTemplate = ReplicatedStorage:FindFirstChild("Assets")
						squirtTemplate = squirtTemplate and squirtTemplate:FindFirstChild("VFX")
						squirtTemplate = squirtTemplate and squirtTemplate:FindFirstChild("Water")
						if squirtTemplate then
							local squirt = squirtTemplate:Clone()
							squirt.Anchored = true
							squirt.CanCollide = false
							squirt.CanQuery = false
							squirt.CanTouch = false
							squirt.CFrame = CFrame.new(cell.x, floorY + 0.3, cell.z)
							squirt.Parent = workspace
							game:GetService("Debris"):AddItem(squirt, 2.5)

							local squirtPe = squirt:FindFirstChild("SquirtWater")
							if squirtPe then
								-- 기본값(Speed 100)은 물기둥(spoutHeight=26)보다 훨씬 높게 튀므로,
								-- 이 기둥 높이에 맞춰 자연스러운 포물선을 그리도록 속도만 축소 조정
								squirtPe.Speed = NumberRange.new(spoutHeight * 2.1, spoutHeight * 2.3)
								squirtPe.Rate = 150
								task.delay(0.6, function()
									if squirtPe and squirtPe.Parent then
										squirtPe.Enabled = false
									end
								end)
							end
						end

						ts:Create(spout, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Size = Vector3.new(spoutHeight, cellSize * 0.55, cellSize * 0.55),
							CFrame = CFrame.new(cell.x, floorY + spoutHeight / 2, cell.z) * CFrame.Angles(0, 0, math.rad(90)),
						}):Play()

						-- 바닥 물보라 (사방으로 퍼지며 튀었다가 중력으로 떨어짐)
						local baseSplashPart = Instance.new("Part")
						baseSplashPart.Name = "KrakenSplashBase"
						baseSplashPart.Size = Vector3.new(0.2, 0.2, 0.2)
						baseSplashPart.Transparency = 1
						baseSplashPart.Anchored = true
						baseSplashPart.CanCollide = false
						baseSplashPart.CanQuery = false
						baseSplashPart.CanTouch = false
						baseSplashPart.CFrame = CFrame.new(cell.x, floorY + 0.5, cell.z)
						baseSplashPart.Parent = workspace
						game:GetService("Debris"):AddItem(baseSplashPart, 2)

						local ringPe = Instance.new("ParticleEmitter")
						ringPe.Texture = WATER_TEX_2
						ringPe.Color = ColorSequence.new(Color3.fromRGB(180, 225, 255))
						ringPe.Size = NumberSequence.new({
							NumberSequenceKeypoint.new(0, cellSize * 0.35),
							NumberSequenceKeypoint.new(1, 0),
						})
						ringPe.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.15),
							NumberSequenceKeypoint.new(1, 1),
						})
						ringPe.Lifetime = NumberRange.new(0.4, 0.7)
						ringPe.Rate = 0
						ringPe.Speed = NumberRange.new(14, 26)
						ringPe.SpreadAngle = Vector2.new(180, 180)
						ringPe.Acceleration = Vector3.new(0, -60, 0)
						ringPe.Rotation = NumberRange.new(0, 360)
						ringPe.Parent = baseSplashPart
						ringPe:Emit(45)

						-- 기둥이 다 자란 뒤 꼭대기에서 터지는 물보라 (정확한 최종 높이에서 재생되도록 지연)
						task.delay(0.2, function()
							if not spout.Parent then return end
							local topSplashPart = Instance.new("Part")
							topSplashPart.Name = "KrakenSplashTop"
							topSplashPart.Size = Vector3.new(0.2, 0.2, 0.2)
							topSplashPart.Transparency = 1
							topSplashPart.Anchored = true
							topSplashPart.CanCollide = false
							topSplashPart.CanQuery = false
							topSplashPart.CanTouch = false
							topSplashPart.CFrame = CFrame.new(cell.x, floorY + spoutHeight, cell.z)
							topSplashPart.Parent = workspace
							game:GetService("Debris"):AddItem(topSplashPart, 2)

							local topPe = Instance.new("ParticleEmitter")
							topPe.Texture = WATER_TEX_2
							topPe.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
							topPe.Size = NumberSequence.new({
								NumberSequenceKeypoint.new(0, cellSize * 0.5),
								NumberSequenceKeypoint.new(1, 0),
							})
							topPe.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.1),
								NumberSequenceKeypoint.new(1, 1),
							})
							topPe.Lifetime = NumberRange.new(0.35, 0.6)
							topPe.Rate = 0
							topPe.Speed = NumberRange.new(10, 20)
							topPe.SpreadAngle = Vector2.new(180, 180)
							topPe.Acceleration = Vector3.new(0, -35, 0)
							topPe.Rotation = NumberRange.new(0, 360)
							topPe.Parent = topSplashPart
							topPe:Emit(30)
						end)

						task.wait(0.2)

						if targetChar and targetChar.Parent then
							local thrp = targetChar:FindFirstChild("HumanoidRootPart")
							if thrp then
								local dx = math.abs(thrp.Position.X - cell.x)
								local dz = math.abs(thrp.Position.Z - cell.z)
								if dx <= cellSize / 2 and dz <= cellSize / 2 then
									local thum = targetChar:FindFirstChildOfClass("Humanoid")
									if thum and thum.Health > 0 then
										dealDamageToHumanoid(thum, config.baseDamage or 220)
									end
								end
							end
						end

						task.wait(0.5)
						risePe.Enabled = false
						ts:Create(spout, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
						game:GetService("Debris"):AddItem(spout, 1)
					end)
				end

				task.wait(1.5)
				if tilesFolder.Parent then tilesFolder:Destroy() end
			end

			-- [포세이돈 전용] 물 패턴 3종 - 전부 물 컨셉으로 통일
			local POSEIDON_WATER_TEX_1 = "rbxassetid://15990457929" -- WAVE_Aura Water1 (넓게 퍼지는 물결)
			local POSEIDON_WATER_TEX_2 = "rbxassetid://15081467386" -- DROPLET_Hit Water Slash 2 (튀는 물보라)

			-- 1) 트라이던트 돌진 찌르기 (기본기) - 사무라이 발도 돌진과 동일한 기법(실제 CFrame 트윈 슬라이드 +
			-- 이동 중 프레임 단위 판정)을 물 테마로 재구성. 크라켄 기본기와 동일하게 config.baseDamage 그대로 사용.
			local function playPoseidonThrust(mob, targetChar)
				local ts = game:GetService("TweenService")
				local mobHrp = mob:FindFirstChild("HumanoidRootPart")
				local mobHum = mob:FindFirstChildOfClass("Humanoid")
				local tHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
				if not (mobHrp and mobHum and tHrp) then return end

				local mobRootPos = mobHrp.Position
				local dir = tHrp.Position - mobRootPos
				local flatDir = Vector3.new(dir.X, 0, dir.Z)
				flatDir = (flatDir.Magnitude > 0.1) and flatDir.Unit or mobHrp.CFrame.LookVector

				local rectWidth = 8
				local chargeLength = 32 -- [버그수정] 먼 거리를 좁히는 추격기 역할을 하도록 사거리 확장 (기존 22 -> 32)
				local telegraphDuration = 0.9

				-- 지형 레이캐스트로 정확한 바닥 높이 확보 (크라켄/사무라이 패턴과 동일한 기법)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local ignoreList = {mob}
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Character then table.insert(ignoreList, p.Character) end
				end
				rayParams.FilterDescendantsInstances = ignoreList
				local rayResult = workspace:Raycast(mobRootPos, Vector3.new(0, -30, 0), rayParams)
				local floorY = rayResult and (rayResult.Position.Y + 0.2) or (mobRootPos.Y - mobHum.HipHeight - mobHrp.Size.Y / 2 + 0.2)

				local warnRect = Instance.new("Part")
				warnRect.Name = "PoseidonThrustTelegraph"
				warnRect.Size = Vector3.new(rectWidth, 0.4, chargeLength)
				warnRect.CFrame = CFrame.lookAt(
					Vector3.new(mobRootPos.X, floorY, mobRootPos.Z),
					Vector3.new(mobRootPos.X + flatDir.X, floorY, mobRootPos.Z + flatDir.Z)
				) * CFrame.new(0, 0, -chargeLength / 2)
				warnRect.Anchored = true
				warnRect.CanCollide = false
				warnRect.CanTouch = false
				warnRect.CanQuery = false
				warnRect.CastShadow = false
				warnRect.Material = Enum.Material.Neon
				warnRect.Color = Color3.fromRGB(90, 205, 255)
				warnRect.Transparency = 0.8
				warnRect.Parent = workspace

				local border = Instance.new("Part")
				border.Name = "PoseidonThrustTelegraphBorder"
				border.Size = Vector3.new(rectWidth + 0.8, 0.35, chargeLength + 0.8)
				border.CFrame = warnRect.CFrame
				border.Anchored = true
				border.CanCollide = false
				border.CanTouch = false
				border.CanQuery = false
				border.CastShadow = false
				border.Material = Enum.Material.Neon
				border.Color = Color3.fromRGB(20, 130, 200)
				border.Transparency = 0.85
				border.Parent = workspace

				local decal = Instance.new("Decal")
				decal.Texture = POSEIDON_WATER_TEX_1
				decal.Face = Enum.NormalId.Top
				decal.Transparency = 0.4
				decal.Parent = warnRect

				ts:Create(warnRect, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 0.35,
				}):Play()
				ts:Create(border, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 0.45,
				}):Play()

				task.wait(telegraphDuration)
				if warnRect.Parent then warnRect:Destroy() end
				if border.Parent then border:Destroy() end
				if not mob.Parent or mobHum.Health <= 0 then return end

				-- 공격 애니메이션 (동적 감지, 없으면 조용히 통과 - 다른 보스들과 동일한 관례)
				pcall(function()
					local animator = mobHum:FindFirstChildOfClass("Animator")
					local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
					local monsterAnims = anims and anims:FindFirstChild("Monster")
					-- 전용 애니메이션이 없으므로 사무라이 발도 돌진 모션을 그대로 재사용
					local thrustAnim = monsterAnims and (monsterAnims:FindFirstChild("Poseidon_Thrust") or monsterAnims:FindFirstChild("Samurai_Dash"))
					if animator and thrustAnim then
						local track = animator:LoadAnimation(thrustAnim)
						if track then
							track.Priority = Enum.AnimationPriority.Action
							track:Play()
						end
					end
				end)

				-- 돌진 궤적 잔상 파티클 (물보라 트레일)
				local peDash = Instance.new("ParticleEmitter")
				peDash.Texture = POSEIDON_WATER_TEX_2
				peDash.Color = ColorSequence.new(Color3.fromRGB(140, 220, 255))
				peDash.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 3),
					NumberSequenceKeypoint.new(1, 0),
				})
				peDash.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				})
				peDash.Rate = 200
				peDash.Speed = NumberRange.new(6, 12)
				peDash.SpreadAngle = Vector2.new(15, 15)
				peDash.Lifetime = NumberRange.new(0.3, 0.5)
				peDash.EmissionDirection = Enum.NormalId.Back
				peDash.Parent = mobHrp

				-- [크라켄/사무라이 돌진과 동일한 기법] 실제 CFrame을 짧은 시간 동안 슬라이드시켜서
				-- 진짜로 이동하는 돌진처럼 보이게 하고, 그 이동 구간 내내 프레임 단위로 판정
				local targetLand = mobRootPos + flatDir * chargeLength
				local slideTime = 0.28
				local slideTween = ts:Create(mobHrp, TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = CFrame.lookAt(targetLand, targetLand + flatDir),
				})
				slideTween:Play()

				local elapsed = 0
				local hit = false
				local startPos = mobRootPos
				while elapsed < slideTime and mobHum.Health > 0 do
					local dt = task.wait(0.03)
					elapsed += dt

					if not hit then
						local finalHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
						local currentPhum = targetChar and targetChar:FindFirstChild("Humanoid")
						if finalHrp and currentPhum and currentPhum.Health > 0 then
							local toTarget = finalHrp.Position - startPos
							local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
							local forwardDist = flatToTarget:Dot(flatDir)
							local lateralDist = (flatToTarget - flatDir * forwardDist).Magnitude
							-- [버그수정] 여유값(+2/+1)이 더해져서 실제 판정이 눈에 보이는 장판보다 넓었음 -> 장판 크기와 정확히 일치시킴
							if forwardDist >= 0 and forwardDist <= chargeLength and lateralDist <= rectWidth / 2 then
								hit = true
								dealDamageToHumanoid(currentPhum, config.baseDamage or 450)
								local hitPlayer = Players:GetPlayerFromCharacter(targetChar)
								if hitPlayer then
									local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
									local NetController = require(Controllers:WaitForChild("NetController"))
									NetController.FireClient(hitPlayer, "Player.Stun", flatDir * 1.5)
								end
							end
						end
					end
				end

				task.wait(0.1)
				peDash.Enabled = false
				game:GetService("Debris"):AddItem(peDash, 1)
			end

			-- 2) 쓰나미 강하 (기믹형 광역기) - 푸른불꽃 기사의 LeapSlam(도약 강타) 구조를 그대로 따르되
			-- 물 테마로 리스킨: 공중으로 솟구침 -> 플레이어 현재 위치에 원거리 경고 장판(회피 시간 제공)
			-- -> 급강하 -> 물보라 파편 + 즉사급 고정 데미지(350, LeapSlam과 동일 수치). 사거리와 무관하게
			-- 원거리에서도 스킬이 나가야 하므로 자신이 아닌 "플레이어 낙하지점"을 기준으로 발동한다.
			local function playPoseidonTsunamiLeap(mob, targetChar)
				local ts = game:GetService("TweenService")
				local Debris = game:GetService("Debris")
				local mobHrp = mob:FindFirstChild("HumanoidRootPart")
				local mobHum = mob:FindFirstChildOfClass("Humanoid")
				local tHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
				if not (mobHrp and mobHum and tHrp) then return end

				-- 공격(도약) 애니메이션 (동적 감지, 없으면 조용히 통과)
				pcall(function()
					local animator = mobHum:FindFirstChildOfClass("Animator")
					local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
					local monsterAnims = anims and anims:FindFirstChild("Monster")
					-- 전용 애니메이션이 없으므로 푸른불꽃 기사의 도약 강타 모션을 그대로 재사용
					local leapAnim = monsterAnims and (monsterAnims:FindFirstChild("Poseidon_TsunamiLeap") or monsterAnims:FindFirstChild("BlueFlameKnight_LeapSlam"))
					if animator and leapAnim then
						local track = animator:LoadAnimation(leapAnim)
						if track then
							track.Looped = false
							track:Play()
						end
					end
				end)

				local targetLandPos = tHrp.Position
				local telegraphRadius = 14

				-- [버그수정] 바닥 레이캐스트가 플레이어 캐릭터 본인은 제외 목록에 없어서, 낙하지점
				-- 바닥을 찾는 레이가 실제 바닥이 아니라 플레이어 자신의 몸(머리/어깨)에 맞아버려서
				-- 경고 장판이 플레이어 키 높이(공중)에 생기던 문제 -> 모든 플레이어 캐릭터도 제외
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local ignoreList = {mob}
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Character then table.insert(ignoreList, p.Character) end
				end
				rayParams.FilterDescendantsInstances = ignoreList

				-- 천장 레이캐스트로 도약 가능 높이 확보 (실내 레이드방 대비)
				local ceilResult = workspace:Raycast(mobHrp.Position, Vector3.new(0, 40, 0), rayParams)
				local availableHeight = ceilResult and math.max(6, ceilResult.Distance - 3) or 20
				local leapUpHeight = math.min(18, availableHeight)

				-- 도약 (하늘로 솟구침) - 중력에 밀려 떨어지지 않도록 공중에서 고정
				mobHrp.Anchored = true
				local leapUp = ts:Create(mobHrp, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = CFrame.new(mobHrp.Position + Vector3.new(0, leapUpHeight, 0)),
				})
				leapUp:Play()
				task.wait(0.4)

				if not mob.Parent or mobHum.Health <= 0 then
					mobHrp.Anchored = false
					return
				end

				-- 공중 체공 중 플레이어의 낙하지점 바닥에 경고 장판 생성 (원거리 스킬 - 자신이 아닌 낙하지점 기준)
				targetLandPos = (targetChar and targetChar.Parent and tHrp.Parent) and tHrp.Position or targetLandPos
				local groundRay = workspace:Raycast(targetLandPos + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), rayParams)
				local floorY = groundRay and (groundRay.Position.Y + 0.2) or (targetLandPos.Y - mobHum.HipHeight - mobHrp.Size.Y / 2)

				local warnCircle = Instance.new("Part")
				warnCircle.Name = "PoseidonTsunamiTelegraph"
				warnCircle.Shape = Enum.PartType.Cylinder
				warnCircle.Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2)
				warnCircle.CFrame = CFrame.new(targetLandPos.X, floorY, targetLandPos.Z) * CFrame.Angles(0, 0, math.rad(90))
				warnCircle.Anchored = true
				warnCircle.CanCollide = false
				warnCircle.CanTouch = false
				warnCircle.CanQuery = false
				warnCircle.CastShadow = false
				warnCircle.Material = Enum.Material.Neon
				warnCircle.Color = Color3.fromRGB(90, 205, 255)
				warnCircle.Transparency = 0.85
				warnCircle.Parent = workspace

				local decal = Instance.new("Decal")
				decal.Texture = POSEIDON_WATER_TEX_1
				decal.Face = Enum.NormalId.Top
				decal.Transparency = 0.5
				decal.Parent = warnCircle

				ts:Create(warnCircle, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()

				-- 1.0초 체공 대기 (회피 시간 제공 - LeapSlam과 동일)
				task.wait(1.0)
				if warnCircle.Parent then warnCircle:Destroy() end

				if not mob.Parent or mobHum.Health <= 0 then
					mobHrp.Anchored = false
					return
				end

				-- 경고 장판 위치로 급강하 내리치기
				local groundOffset = mobHum.HipHeight + (mobHrp.Size.Y / 2)
				local leapDown = ts:Create(mobHrp, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(targetLandPos.X, floorY + groundOffset, targetLandPos.Z),
				})
				leapDown:Play()
				task.wait(0.2)

				mobHrp.Anchored = false -- 착지 완료 후 다시 물리 활성화

				-- 착지 지점 물보라 파편 (LeapSlam의 돌 파편 대신 물방울 파편으로 리스킨)
				local impactFloorPos = Vector3.new(targetLandPos.X, floorY, targetLandPos.Z)
				for i = 1, 12 do
					local droplet = Instance.new("Part")
					droplet.Name = "PoseidonSplashDebris"
					droplet.Shape = Enum.PartType.Ball
					droplet.Size = Vector3.new(math.random(1, 2), math.random(1, 2), math.random(1, 2))
					droplet.Color = Color3.fromRGB(140, 220, 255)
					droplet.Material = Enum.Material.Glass
					droplet.Transparency = 0.2
					droplet.CFrame = CFrame.new(impactFloorPos + Vector3.new(0, 1, 0))
					droplet.Velocity = Vector3.new(math.random(-40, 40), math.random(50, 80), math.random(-40, 40))
					droplet.RotVelocity = Vector3.new(math.random(-30, 30), math.random(-30, 30), math.random(-30, 30))
					droplet.CanCollide = true
					droplet.Parent = workspace
					Debris:AddItem(droplet, math.random(15, 25) / 10)
				end

				if mobHum.Health > 0 then
					-- 착지 강타 사운드 (동적 감지, 없으면 조용히 통과)
					pcall(function()
						local soundRoot = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
						local monsterSounds = soundRoot and soundRoot:FindFirstChild("Monster")
						local sound = monsterSounds and monsterSounds:FindFirstChild("Poseidon_TsunamiLeap")
						if sound then
							local s = sound:Clone()
							s.Parent = mobHrp
							s:Play()
							Debris:AddItem(s, 2)
						end
					end)

					local exp = Instance.new("Explosion")
					exp.BlastRadius = telegraphRadius
					exp.BlastPressure = 0
					exp.Position = targetLandPos
					exp.ExplosionType = Enum.ExplosionType.NoCraters
					exp.Visible = false
					exp.Parent = workspace

					-- 데미지 판정 (LeapSlam과 동일: 즉사급 고정 350)
					for _, p in ipairs(Players:GetPlayers()) do
						local char = p.Character
						local phum = char and char:FindFirstChild("Humanoid")
						local pRoot = char and char:FindFirstChild("HumanoidRootPart")
						if phum and phum.Health > 0 and pRoot then
							local dXZ = Vector3.new(pRoot.Position.X - targetLandPos.X, 0, pRoot.Position.Z - targetLandPos.Z).Magnitude
							if dXZ <= telegraphRadius and math.abs(pRoot.Position.Y - targetLandPos.Y) < 15 then
								dealDamageToHumanoid(phum, 350) -- 쓰나미 강하 즉사급 데미지 (BlueFlameKnight LeapSlam과 동일 수치)

								local bounceDir = (pRoot.Position - targetLandPos)
								bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
								local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
								local NetController = require(Controllers:WaitForChild("NetController"))
								NetController.FireClient(p, "Player.Stun", bounceDir * 1.5)
							end
						end
					end
				end

				-- 착지 후 딜레이(프리딜 타임) - LeapSlam과 동일하게 3.5초
				task.wait(3.5)
			end

			-- 3) 소용돌이 급류 (기믹형) - 푸른불꽃 기사의 회오리(Whirlwind Tornado) 구조를 그대로 따르되
			-- 물 테마로 리스킨: 3연속으로 전방을 향해 소용돌이 투사체를 발사, 진행 경로에 닿으면 피격.
			-- 데미지도 회오리와 동일한 즉사급 고정값(250) 사용.
			-- [버그수정] 기존엔 한 방향으로 3연발이었으나, 요청에 따라 한 번에 4방향(전/후/좌/우) 십자형으로
			-- 동시에 발사하도록 재설계. 파티클도 손으로 만든 스모크/스파클 재질감 대신 실제 워터 파티클
			-- 팩(ReplicatedStorage.LowPoly."Particle Pack (Water Based)") 템플릿을 그대로 복제해서 사용.
			local function playPoseidonWhirlpool(mob, targetChar)
				local ts = game:GetService("TweenService")
				local Debris = game:GetService("Debris")
				local mobHrp = mob:FindFirstChild("HumanoidRootPart")
				local mobHum = mob:FindFirstChildOfClass("Humanoid")
				local tHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
				if not (mobHrp and mobHum and tHrp) then return end

				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local ignoreList = {mob}
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Character then table.insert(ignoreList, p.Character) end
				end
				rayParams.FilterDescendantsInstances = ignoreList
				local rayResult = workspace:Raycast(mobHrp.Position, Vector3.new(0, -30, 0), rayParams)
				local floorY = rayResult and (rayResult.Position.Y + 0.2) or (mobHrp.Position.Y - mobHum.HipHeight - mobHrp.Size.Y / 2 + 0.2)

				-- 실제 워터 파티클 팩 템플릿 조회 (이름 -> ParticleEmitter)
				local waterEmitterByName = {}
				local waterPack = ReplicatedStorage:FindFirstChild("LowPoly")
				waterPack = waterPack and waterPack:FindFirstChild("Particle Pack (Water Based)")
				if waterPack then
					for _, d in ipairs(waterPack:GetDescendants()) do
						if d:IsA("ParticleEmitter") and not waterEmitterByName[d.Name] then
							waterEmitterByName[d.Name] = d
						end
					end
				end

				-- 타겟 방향을 "정면"으로 삼아 전/우/후/좌 순서로 4방향 벡터 산출
				local lookDir = (tHrp.Position - mobHrp.Position)
				lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
				lookDir = (lookDir.Magnitude > 0.1) and lookDir.Unit or mobHrp.CFrame.LookVector
				mobHrp.CFrame = CFrame.lookAt(mobHrp.Position, mobHrp.Position + lookDir)

				local rightDir = Vector3.new(-lookDir.Z, 0, lookDir.X)
				local directions = { lookDir, rightDir, -lookDir, -rightDir }

				local tornadoLength = 45
				local tornadoWidth = 16 -- [요청반영] 더 뚱뚱한 십자로 판정/경고 범위 확대 (기존 8 -> 16)

				-- 1. 4방향 전조 장판을 동시에 생성
				local warnLines = {}
				for _, dir in ipairs(directions) do
					local warnLine = Instance.new("Part")
					warnLine.Name = "PoseidonWhirlpoolTelegraph"
					warnLine.Size = Vector3.new(tornadoWidth, 0.4, tornadoLength)
					local wcf = CFrame.lookAt(mobHrp.Position, mobHrp.Position + dir) * CFrame.new(0, 0, -tornadoLength / 2)
					warnLine.CFrame = CFrame.new(wcf.Position.X, floorY, wcf.Position.Z) * CFrame.lookAt(Vector3.zero, dir).Rotation
					warnLine.Anchored = true
					warnLine.CanCollide = false
					warnLine.CanTouch = false
					warnLine.CanQuery = false
					warnLine.CastShadow = false
					warnLine.Material = Enum.Material.Neon
					warnLine.Color = Color3.fromRGB(90, 205, 255)
					warnLine.Transparency = 0.85
					warnLine.Parent = workspace

					local decal = Instance.new("Decal")
					decal.Texture = POSEIDON_WATER_TEX_1
					decal.Face = Enum.NormalId.Top
					decal.Transparency = 0.5
					decal.Parent = warnLine

					ts:Create(warnLine, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()
					table.insert(warnLines, warnLine)
				end

				task.wait(0.8)
				for _, w in ipairs(warnLines) do
					if w.Parent then w:Destroy() end
				end
				if not mob.Parent or mobHum.Health <= 0 then return end

				-- 2. 애니메이션 (전용 없으므로 푸른불꽃 기사 회오리 모션 재사용)
				pcall(function()
					local animator = mobHum:FindFirstChildOfClass("Animator")
					local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
					local monsterAnims = anims and anims:FindFirstChild("Monster")
					local spinAnim = monsterAnims and (monsterAnims:FindFirstChild("Poseidon_Whirlpool") or monsterAnims:FindFirstChild("BlueFlameKnight_Whirlwind"))
					if animator and spinAnim then
						local track = animator:LoadAnimation(spinAnim)
						if track then
							track.Looped = false
							track:Play()
						end
					end
				end)

				-- 3. 4방향 소용돌이 투사체를 동시에 발사 (각자 독립 코루틴)
				for _, dir in ipairs(directions) do
					task.spawn(function()
						local tornadoHeight = 12
						local tornado = Instance.new("Part")
						tornado.Name = "PoseidonWhirlpoolProjectile"
						tornado.Shape = Enum.PartType.Cylinder
						tornado.Size = Vector3.new(tornadoHeight, tornadoWidth, tornadoWidth)
						local startPos = mobHrp.Position + dir * 3
						tornado.CFrame = CFrame.new(startPos.X, floorY + (tornadoHeight / 2), startPos.Z) * CFrame.lookAt(Vector3.zero, dir).Rotation * CFrame.Angles(0, math.rad(90), 0)
						tornado.Anchored = true
						tornado.CanCollide = false
						tornado.Material = Enum.Material.Neon
						tornado.Color = Color3.fromRGB(90, 205, 255)
						tornado.Transparency = 1.0
						tornado.Parent = workspace

						-- 실제 워터팩 파티클 복제 (물소용돌이 본체 + 물보라 트레일)
						local swirl = waterEmitterByName["water 7"] or waterEmitterByName["water 5"]
						if swirl then
							local swirlClone = swirl:Clone()
							swirlClone.Enabled = true
							swirlClone.Parent = tornado
						end
						local spray = waterEmitterByName["Water Slash"] or waterEmitterByName["shards"]
						if spray then
							local sprayClone = spray:Clone()
							sprayClone.Enabled = true
							sprayClone.Parent = tornado
						end
						if not (swirl or spray) then
							-- 워터팩을 못 찾은 경우를 대비한 최소 폴백
							local pe = Instance.new("ParticleEmitter")
							pe.Texture = POSEIDON_WATER_TEX_1
							pe.Color = ColorSequence.new(Color3.fromRGB(90, 205, 255))
							pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, tornadoWidth), NumberSequenceKeypoint.new(1, 0)})
							pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)})
							pe.Rate = 150
							pe.Speed = NumberRange.new(4, 9)
							pe.Lifetime = NumberRange.new(0.6, 1.0)
							pe.Parent = tornado
						end

						-- 4. 소용돌이 전진 (Tween)
						local endPos = mobHrp.Position + dir * tornadoLength
						local endCFrame = CFrame.new(endPos.X, floorY + (tornadoHeight / 2), endPos.Z) * CFrame.lookAt(Vector3.zero, dir).Rotation * CFrame.Angles(0, math.rad(90), 0)
						ts:Create(tornado, TweenInfo.new(1.3, Enum.EasingStyle.Linear), {CFrame = endCFrame}):Play()

						-- 5. 이동 중 데미지 판정
						local moveTime = 1.3
						local hitPlayers = {}
						local elapsed = 0
						while elapsed < moveTime and tornado and tornado.Parent do
							local dt = task.wait(0.1)
							elapsed += dt

							local tPos = tornado.Position
							for _, p in ipairs(Players:GetPlayers()) do
								local char = p.Character
								local phum = char and char:FindFirstChild("Humanoid")
								local pRoot = char and char:FindFirstChild("HumanoidRootPart")
								if phum and phum.Health > 0 and pRoot and not hitPlayers[p.UserId] then
									local dist = (Vector3.new(pRoot.Position.X, 0, pRoot.Position.Z) - Vector3.new(tPos.X, 0, tPos.Z)).Magnitude
									if dist <= (tornadoWidth / 2 + 2) and math.abs(pRoot.Position.Y - tPos.Y) < 15 then
										hitPlayers[p.UserId] = true
										dealDamageToHumanoid(phum, 250) -- 소용돌이 급류 즉사급 데미지 (BlueFlameKnight 회오리와 동일 수치)

										local hitPlayer = Players:GetPlayerFromCharacter(char)
										if hitPlayer then
											local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
											local NetController = require(Controllers:WaitForChild("NetController"))
											NetController.FireClient(hitPlayer, "Player.Stun", dir * 1.5)
										end
									end
								end
							end
						end
						if tornado.Parent then tornado:Destroy() end
					end)
				end

				-- 4방향 투사체가 전부 소진될 시간만큼 대기 후 함수 종료 (poseidonPatternBusy 잠금 유지)
				task.wait(1.3 + 0.2)
			end

			-- 4) 체스판 물기둥 (기믹형) - 크라켄의 playKrakenCheckerboardAttack과 완전히 동일한 로직이지만,
			-- 그 함수는 크라켄 방(DeepAbyss) 좌표(X:663~833, Z:117~277)가 하드코딩되어 있어 그대로 재사용하면
			-- 포세이돈 방(DeepAbyss_North)이 아닌 엉뚱한 빈 방에서 격자가 생성되는 문제가 있었음.
			-- DeepAbyss_North.RaidArena.ArenaFloor 실측 범위로 방 경계만 교체한 전용 버전.
			local function playPoseidonCheckerboard(mob, targetChar)
				local centerHrp = mob:FindFirstChild("HumanoidRootPart")
				if not centerHrp then return end
				local center = centerHrp.Position

				local gridSize = 10
				local cellSize = 16
				local halfSpan = (gridSize * cellSize) / 2

				-- DeepAbyss_North.RaidArena.ArenaFloor 실측: 위치(-50.7, 65, -411.8), 크기(160, 6, 170)
				local ARENA_X_MIN, ARENA_X_MAX = -130.7, 49.3
				local ARENA_Z_MIN, ARENA_Z_MAX = -496.8, -326.8
				local clampedX = math.clamp(center.X, ARENA_X_MIN + halfSpan, ARENA_X_MAX - halfSpan)
				local clampedZ = math.clamp(center.Z, ARENA_Z_MIN + halfSpan, ARENA_Z_MAX - halfSpan)
				if ARENA_X_MIN + halfSpan > ARENA_X_MAX - halfSpan then
					clampedX = (ARENA_X_MIN + ARENA_X_MAX) / 2
				end
				if ARENA_Z_MIN + halfSpan > ARENA_Z_MAX - halfSpan then
					clampedZ = (ARENA_Z_MIN + ARENA_Z_MAX) / 2
				end
				center = Vector3.new(clampedX, center.Y, clampedZ)

				local telegraphDuration = 1.8

				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local ignoreList = { mob }
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Character then table.insert(ignoreList, p.Character) end
				end
				rayParams.FilterDescendantsInstances = ignoreList
				local rayResult = workspace:Raycast(center + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams)
				local floorY = rayResult and rayResult.Position.Y or (center.Y - 20)

				local tilesFolder = Instance.new("Folder")
				tilesFolder.Name = "PoseidonCheckerboard"
				tilesFolder.Parent = workspace

				local deathCells = {}
				local cellRecords = {}
				for i = 0, gridSize - 1 do
					for j = 0, gridSize - 1 do
						local isDeath = math.random() < 0.5
						table.insert(cellRecords, { i = i, j = j, isDeath = isDeath })
					end
				end
				local hasDeath = false
				for _, rec in ipairs(cellRecords) do
					if rec.isDeath then hasDeath = true break end
				end
				if not hasDeath then
					cellRecords[math.random(1, #cellRecords)].isDeath = true
				end

				for _, rec in ipairs(cellRecords) do
					if rec.isDeath then
						local cellCenterX = center.X - halfSpan + cellSize * (rec.i + 0.5)
						local cellCenterZ = center.Z - halfSpan + cellSize * (rec.j + 0.5)

						local tile = Instance.new("Part")
						tile.Name = "PoseidonDeathTile"
						tile.Size = Vector3.new(cellSize - 0.4, 0.3, cellSize - 0.4)
						tile.CFrame = CFrame.new(cellCenterX, floorY + 0.2, cellCenterZ)
						tile.Anchored = true
						tile.CanCollide = false
						tile.CanTouch = false
						tile.CanQuery = false
						tile.CastShadow = false
						tile.Material = Enum.Material.Neon
						tile.Color = Color3.fromRGB(90, 205, 255)
						tile.Transparency = 0.55
						tile.Parent = tilesFolder

						table.insert(deathCells, { x = cellCenterX, z = cellCenterZ, part = tile })
					end
				end

				task.spawn(function()
					local elapsed = 0
					while elapsed < telegraphDuration and tilesFolder.Parent do
						for _, cell in ipairs(deathCells) do
							if cell.part.Parent then cell.part.Transparency = 0.25 end
						end
						task.wait(0.2)
						elapsed += 0.2
						for _, cell in ipairs(deathCells) do
							if cell.part.Parent then cell.part.Transparency = 0.65 end
						end
						task.wait(0.2)
						elapsed += 0.2
					end
				end)

				task.wait(telegraphDuration)

				local ts = game:GetService("TweenService")

				for _, cell in ipairs(deathCells) do
					task.spawn(function()
						if cell.part.Parent then cell.part:Destroy() end

						local spoutHeight = 26
						local spout = Instance.new("Part")
						spout.Name = "PoseidonWaterSpout"
						spout.Shape = Enum.PartType.Cylinder
						spout.Material = Enum.Material.Glass
						spout.Color = Color3.fromRGB(100, 180, 235)
						spout.Transparency = 0.35
						spout.Anchored = true
						spout.CanCollide = false
						spout.CanTouch = false
						spout.CanQuery = false
						spout.CastShadow = false
						spout.Size = Vector3.new(0.1, cellSize * 0.55, cellSize * 0.55)
						spout.CFrame = CFrame.new(cell.x, floorY, cell.z) * CFrame.Angles(0, 0, math.rad(90))
						spout.Parent = workspace

						local risePe = Instance.new("ParticleEmitter")
						risePe.Texture = POSEIDON_WATER_TEX_1
						risePe.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
						risePe.Size = NumberSequence.new({
							NumberSequenceKeypoint.new(0, cellSize * 0.5),
							NumberSequenceKeypoint.new(1, cellSize * 0.3),
						})
						risePe.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.2),
							NumberSequenceKeypoint.new(0.8, 0.4),
							NumberSequenceKeypoint.new(1, 1),
						})
						risePe.Lifetime = NumberRange.new(0.35, 0.55)
						risePe.Rate = 90
						risePe.Speed = NumberRange.new(3, 6)
						risePe.SpreadAngle = Vector2.new(8, 8)
						risePe.Rotation = NumberRange.new(0, 360)
						risePe.EmissionDirection = Enum.NormalId.Top
						risePe.Parent = spout

						ts:Create(spout, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Size = Vector3.new(spoutHeight, cellSize * 0.55, cellSize * 0.55),
							CFrame = CFrame.new(cell.x, floorY + spoutHeight / 2, cell.z) * CFrame.Angles(0, 0, math.rad(90)),
						}):Play()

						local baseSplashPart = Instance.new("Part")
						baseSplashPart.Name = "PoseidonSplashBase"
						baseSplashPart.Size = Vector3.new(0.2, 0.2, 0.2)
						baseSplashPart.Transparency = 1
						baseSplashPart.Anchored = true
						baseSplashPart.CanCollide = false
						baseSplashPart.CanQuery = false
						baseSplashPart.CanTouch = false
						baseSplashPart.CFrame = CFrame.new(cell.x, floorY + 0.5, cell.z)
						baseSplashPart.Parent = workspace
						game:GetService("Debris"):AddItem(baseSplashPart, 2)

						local ringPe = Instance.new("ParticleEmitter")
						ringPe.Texture = POSEIDON_WATER_TEX_2
						ringPe.Color = ColorSequence.new(Color3.fromRGB(180, 225, 255))
						ringPe.Size = NumberSequence.new({
							NumberSequenceKeypoint.new(0, cellSize * 0.35),
							NumberSequenceKeypoint.new(1, 0),
						})
						ringPe.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.15),
							NumberSequenceKeypoint.new(1, 1),
						})
						ringPe.Lifetime = NumberRange.new(0.4, 0.7)
						ringPe.Rate = 0
						ringPe.Speed = NumberRange.new(14, 26)
						ringPe.SpreadAngle = Vector2.new(180, 180)
						ringPe.Acceleration = Vector3.new(0, -60, 0)
						ringPe.Rotation = NumberRange.new(0, 360)
						ringPe.Parent = baseSplashPart
						ringPe:Emit(45)

						task.wait(0.2)

						if targetChar and targetChar.Parent then
							local thrp = targetChar:FindFirstChild("HumanoidRootPart")
							if thrp then
								local dx = math.abs(thrp.Position.X - cell.x)
								local dz = math.abs(thrp.Position.Z - cell.z)
								if dx <= cellSize / 2 and dz <= cellSize / 2 then
									local thum = targetChar:FindFirstChildOfClass("Humanoid")
									if thum and thum.Health > 0 then
										dealDamageToHumanoid(thum, config.baseDamage or 450)
									end
								end
							end
						end

						task.wait(0.5)
						risePe.Enabled = false
						ts:Create(spout, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
						game:GetService("Debris"):AddItem(spout, 1)
					end)
				end

				task.wait(1.5)
				if tilesFolder.Parent then tilesFolder:Destroy() end
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
				crater.Color = Color3.fromRGB(34, 139, 34) -- 깊은 숲의 초록색
				crater.Parent = workspace
				ts:Create(crater, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
				game:GetService("Debris"):AddItem(crater, 3.5)

				-- 2. 타격음 삭제

				-- 3. 나무 파편(Wood Debris) 튀기기
				for i = 1, 12 do
					local wood = Instance.new("Part")
					wood.Size = Vector3.new(math.random(2, 4), math.random(2, 4), math.random(2, 4))
					wood.Position = pos + Vector3.new(math.random(-3, 3), 2, math.random(-3, 3))
					wood.Material = Enum.Material.Wood
					wood.Color = Color3.fromRGB(120, 85, 45)
					wood.CanCollide = false
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
				pe.Color = ColorSequence.new(Color3.fromRGB(50, 205, 50), Color3.fromRGB(34, 139, 34)) -- 싱그러운 나뭇잎 초록빛 먼지색
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
				shockwave.Color = Color3.fromRGB(46, 204, 113) -- 신성한 숲의 비취색(에메랄드) 충격파
				shockwave.Parent = workspace
				ts:Create(shockwave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.5, radius * 2, radius * 2),
					Transparency = 1
				}):Play()
				game:GetService("Debris"):AddItem(shockwave, 0.5)
			end

			local lastTarget = nil

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

				-- 1단계: 주변에 가장 가까운 생존한 플레이어 탐색 (추격 유지 거리 별도 적용)
				local targetPlayer = nil
				local minDist = AGGRO_RADIUS
				local chaseRadius = AGGRO_RADIUS * 1.5 -- 기존 2.5배에서 1.5배로 축소 (너무 멀리 쫓아오지 않도록)

				-- 먼저 기존 타겟이 추격 반경 내에 있는지 확인합니다.
				if lastTarget and lastTarget.Parent then
					local lHum = lastTarget:FindFirstChild("Humanoid")
					local lHrp = lastTarget:FindFirstChild("HumanoidRootPart")
					if lHum and lHum.Health > 0 and lHrp then
						local d = (hrp.Position - lHrp.Position).Magnitude
						if d <= chaseRadius then
							targetPlayer = lastTarget
							minDist = d
						end
					end
				end

				-- 기존 타겟이 없거나 멀리 도망갔다면, 기본 인식 거리 내의 새로운 타겟을 찾습니다.
				if not targetPlayer then
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
				end

				-- 2단계: 타겟 존재 여부에 따른 행동 분기
				if targetPlayer then
					if lastTarget ~= targetPlayer then
						lastTarget = targetPlayer
						
						-- 어그로 느낌표 시각 효과 (어그로가 유지되는 동안 계속 떠 있음)
						task.spawn(function()
							pcall(function()
								local head = model:FindFirstChild("Head")
								local adorneePart = head or hrp
								
								-- 기존에 떠있던 ! 나 ? 가 있다면 제거
								local oldAlert = model:FindFirstChild("AggroAlert", true) or adorneePart:FindFirstChild("AggroAlert")
								if oldAlert then oldAlert:Destroy() end
								local oldLost = model:FindFirstChild("AggroLost", true) or adorneePart:FindFirstChild("AggroLost")
								if oldLost then oldLost:Destroy() end
								
								local billboard = Instance.new("BillboardGui")
								billboard.Name = "AggroAlert"
								billboard.Adornee = adorneePart
								billboard.Size = UDim2.new(2, 0, 2, 0)
								
								local extents = model:GetExtentsSize()
								local yOffset
								if head then
									yOffset = head.Size.Y/2 + 1.0
								elseif config.mobModelName == "Jellyfish" then
									-- [버그수정] GetBoundingBox는 비주얼보다 훨씬 큰 Part.Size 기준이라 부정확함.
									-- HRP가 이미 몸통 꼭대기 근처이므로 작은 고정 오프셋만 사용.
									yOffset = 10
								else
									yOffset = extents.Y + 2.0
								end
								billboard.StudsOffset = Vector3.new(0, yOffset, 0)
								billboard.AlwaysOnTop = true
								
								local textLabel = Instance.new("TextLabel")
								textLabel.Size = UDim2.new(1, 0, 1, 0)
								textLabel.BackgroundTransparency = 1
								textLabel.Text = "!"
								textLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
								textLabel.TextScaled = true
								textLabel.Font = Enum.Font.FredokaOne
								textLabel.TextStrokeTransparency = 0
								textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
								textLabel.Parent = billboard
								
								billboard.Parent = hrp
								
								local ts = game:GetService("TweenService")
								local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
								ts:Create(billboard, tweenInfo, {StudsOffset = Vector3.new(0, yOffset + 2.0, 0)}):Play()
								
								-- 경고음 재생
								local soundRoot = game.ReplicatedStorage:FindFirstChild("Assets") and game.ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local alertSound = soundRoot and (soundRoot:FindFirstChild("AggroAlert") or soundRoot:FindFirstChild("UI_Click"))
								if alertSound then
									local s = alertSound:Clone()
									s.Parent = hrp
									s:Play()
									game:GetService("Debris"):AddItem(s, 2)
								end
								
								-- 이제 느낌표는 어그로가 풀릴 때까지(포기할 때까지) 계속 떠 있습니다.
							end)
						end)
					end

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

								local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0), raycastParams)
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
								warnCircle.Color = Color3.fromRGB(0, 180, 80) -- 숲의 수호자 느낌의 초록빛 예고
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
									Color = Color3.fromRGB(100, 255, 150) -- 영롱한 에메랄드빛 점멸
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

								-- A. 중앙 메인 나무 기둥 (WedgePart로 뾰족한 형상 구현)
								local mainSpire = Instance.new("WedgePart")
								mainSpire.Name = "MainSpire"
								mainSpire.Size = Vector3.new(3.5, 12, 3.5)
								mainSpire.Color = Color3.fromRGB(120, 85, 45) -- 나무 갈색
								mainSpire.Material = Enum.Material.Wood
								mainSpire.CanCollide = false
								mainSpire.Anchored = true
								mainSpire.Parent = magicSpikeModel

								-- B. 주변 보조 나뭇가지 파편 1
								local sideShard1 = Instance.new("WedgePart")
								sideShard1.Name = "SideShard1"
								sideShard1.Size = Vector3.new(2, 6, 2)
								sideShard1.Color = Color3.fromRGB(100, 70, 35) -- 약간 어두운 나무 갈색
								sideShard1.Material = Enum.Material.Wood
								sideShard1.CanCollide = false
								sideShard1.Anchored = true
								sideShard1.Parent = magicSpikeModel

								-- C. 주변 보조 나뭇가지 파편 2
								local sideShard2 = Instance.new("WedgePart")
								sideShard2.Name = "SideShard2"
								sideShard2.Size = Vector3.new(1.8, 4, 1.8)
								sideShard2.Color = Color3.fromRGB(140, 100, 55) -- 약간 밝은 나무 갈색
								sideShard2.Material = Enum.Material.Wood
								sideShard2.CanCollide = false
								sideShard2.Anchored = true
								sideShard2.Parent = magicSpikeModel

								-- D. 상단 무성한 나뭇잎 구체
								local leaves = Instance.new("Part")
								leaves.Name = "Leaves"
								leaves.Shape = Enum.PartType.Ball
								leaves.Size = Vector3.new(5.5, 5.5, 5.5)
								leaves.Color = Color3.fromRGB(34, 139, 34) -- 깊은 숲의 나뭇잎 초록색
								leaves.Material = Enum.Material.Grass
								leaves.CanCollide = false
								leaves.Anchored = true
								leaves.Parent = magicSpikeModel

								-- 일관적인 위치 보정 함수 (트윈/수학적 루프 연산용)
								local function updateSpikeCF(centerPos, verticalOffset)
									local baseCF = CFrame.new(centerPos + Vector3.new(0, verticalOffset, 0))
									mainSpire.CFrame = baseCF * CFrame.Angles(0, 0, 0)
									sideShard1.CFrame = baseCF * CFrame.new(-1.2, -3, 0.8) * CFrame.Angles(math.rad(15), 0, math.rad(15))
									sideShard2.CFrame = baseCF * CFrame.new(1.2, -4, -0.8) * CFrame.Angles(math.rad(-15), 0, math.rad(-15))
									leaves.CFrame = baseCF * CFrame.new(0, 5.5, 0)
								end

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
												dealDamageToHumanoid(phum, config.baseDamage or 25, config.level)

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

								local rayResult = workspace:Raycast(meleeTelegraphPos + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0), raycastParams)
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
										dealDamageToHumanoid(phum, config.baseDamage or 25, config.level)

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

							local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), raycastParams)
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
							playBossSound("Laser_Charge", chargeSphere)

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
								playBossSound("Laser_Shoot", laserCore)

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
											dealDamageToHumanoid(phum, config.baseDamage or 35, config.level)

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
							warnCircle.Color = Color3.fromRGB(0, 180, 80) -- 숲의 힘 (초록색) 경고
							warnCircle.Transparency = 0.85
							warnCircle.Parent = workspace

							local ts = game:GetService("TweenService")
							ts:Create(warnCircle, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
								Transparency = 0.4,
								Color = Color3.fromRGB(100, 255, 150) -- 비취빛/에메랄드빛 점멸
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

							pcall(function()
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local monsterSounds = sounds and sounds:FindFirstChild("Monster")
								local sound = monsterSounds and monsterSounds:FindFirstChild("StumpKing_Stomp")
								if sound then
									local sfx = sound:Clone()
									sfx.Parent = hrp
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
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
											dealDamageToHumanoid(phum, config.baseDamage or 50, config.level)
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

							pcall(function()
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local monsterSounds = sounds and sounds:FindFirstChild("Monster")
								local sound = monsterSounds and monsterSounds:FindFirstChild("StumpKing_TreeDrop")
								if sound then
									local sfx = sound:Clone()
									sfx.Parent = hrp
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
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
								local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 5, 0), Vector3.new(0, -30, 0), raycastParams)
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
								warnCircle.Color = Color3.fromRGB(0, 160, 60) -- 초록빛 낙하 경고
								warnCircle.Transparency = 0.85
								warnCircle.Parent = workspace

								ts:Create(warnCircle, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 0.4,
									Color = Color3.fromRGB(80, 255, 130) -- 에메랄드빛 점멸
								}):Play()

								-- 0.5초 대기 (회피 시간)
								task.wait(0.5)
								warnCircle:Destroy()
								if not isAlive then break end

								-- 나무 둥치 모델 생성 (대형 통나무)
								local trunk = Instance.new("Part")
								trunk.Name = "FallingTrunk"
								trunk.Shape = Enum.PartType.Cylinder
								trunk.Size = Vector3.new(12, 6, 6) -- 거대 원기둥 통나무
								trunk.Color = Color3.fromRGB(100, 70, 35) -- 통나무 갈색
								trunk.Material = Enum.Material.Wood
								trunk.CanCollide = false
								trunk.Anchored = true

								-- 하늘에서 서서히 돌면서 떨어지는 CFrame 연출
								local startPos = targetFloorPos + Vector3.new(0, 40, 0)
								trunk.CFrame = CFrame.new(startPos) * CFrame.Angles(math.rad(45), math.rad(45), 0)
								trunk.Parent = workspace

								local fallTween = ts:Create(trunk, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									CFrame = CFrame.new(targetFloorPos) * CFrame.Angles(math.rad(135), math.rad(90), math.rad(45))
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
												dealDamageToHumanoid(phum, config.baseDamage or 50, config.level)
												local bounceDir = Vector3.new(pRoot.Position.X - targetFloorPos.X, 0, pRoot.Position.Z - targetFloorPos.Z).Unit
												local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
												local NetController = require(Controllers:WaitForChild("NetController"))
												NetController.FireClient(p, "Player.Stun", bounceDir)

												task.spawn(function()
													local highlight = Instance.new("Highlight")
													highlight.Name = "DamageFlash"
													highlight.FillColor = Color3.fromRGB(244, 164, 96) -- 모래 데미지색
													highlight.OutlineColor = Color3.fromRGB(255, 200, 100)
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
					elseif config.mobModelName == "DesertGuardian" then
						--========================================================================
						-- [DesertGuardian 전용 FSM 분기]: 모래 흩날림(상시) + 3대 모래 기믹 마법
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()

						-- [바다 테마 리스킨] 서쪽 협곡 레이드방(AbyssGuardianZone)에 스폰된 개체는
						-- 동일한 패턴/수치를 그대로 쓰되 색감만 모래톤 -> 바다톤으로 바꿔서 표시.
						-- 기존 사막존(DesertGuardianZone) 개체는 spawnAreaId가 달라 영향 없음.
						local isSeaVariant = (config.spawnAreaId == "AbyssGuardianZone")
						local function seaTone(sandColor, seaColor)
							return isSeaVariant and seaColor or sandColor
						end
						-- 크라켄 체스판 공격(playKrakenCheckerboardAttack)이 쓰는 실제 물 텍스처를 그대로 재사용
						local SEA_WATER_TEX_1 = "rbxassetid://15990457929" -- WAVE_Aura Water1 (넓게 퍼지는 물결)
						local SEA_WATER_TEX_2 = "rbxassetid://15081467386" -- DROPLET_Hit Water Slash 2 (튀는 물보라)

						local ts = game:GetService("TweenService")
						local Debris = game:GetService("Debris")

						local function setVfxCFrame(inst, cf)
							if inst:IsA("Model") then
								inst:PivotTo(cf)
							elseif inst:IsA("BasePart") then
								inst.CFrame = cf
							end
						end

						local function getVfxCFrame(inst)
							if inst:IsA("Model") then
								return inst:GetPivot()
							elseif inst:IsA("BasePart") then
								return inst.CFrame
							end
							return CFrame.new()
						end

						local function getVfxPosition(inst)
							if inst:IsA("Model") then
								return inst:GetPivot().Position
							elseif inst:IsA("BasePart") then
								return inst.Position
							end
							return Vector3.zero
						end

						local function getEmitterHost(inst)
							if inst:IsA("BasePart") then
								return inst
							end
							if inst:IsA("Model") then
								return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
							end
							return nil
						end

						-- [바다 테마 리스킨] DesertGuardian_Tornado / DesertGuardian_RisingStone 같은 완제품
						-- VFX 에셋은 모래색이 파티클/파츠에 직접 구워져 있어 seaTone() 색상 파라미터만으론
						-- 바뀌지 않음. 복제된 인스턴스의 파티클/파츠 색을 런타임에 바다톤으로 덮어써서
						-- 새 에셋 제작 없이 동일 VFX를 재사용한다.
						local function tintVfxForSea(inst)
							local SEA_PARTICLE = Color3.fromRGB(140, 210, 255)
							local SEA_PART = Color3.fromRGB(20, 45, 95) -- 짙은 남색 암석/파츠 톤
							local SEA_STONE = Color3.fromRGB(25, 50, 110) -- 솟구치는 돌 전용 남색
							local texToggle = false

							local function tintOne(desc)
								if desc:IsA("ParticleEmitter") then
									desc.Color = ColorSequence.new(SEA_PARTICLE)
									-- 회오리(Windspin류)가 모래 텍스처 그대로 남아있으면 색만 바뀐 모래로
									-- 보이므로, 실제 물결/물보라 텍스처(크라켄 체스판 공격과 동일)로 교체해서
									-- 진짜 소용돌이처럼 보이게 함
									texToggle = not texToggle
									desc.Texture = texToggle and SEA_WATER_TEX_1 or SEA_WATER_TEX_2
								elseif desc:IsA("MeshPart") and desc.Transparency < 1 then
									-- RisingStone(암석 스파이크)은 이미 Material.Ice라 색만 바꿔도
									-- 크리스탈처럼 보임 -> 요청하신 푸른 남색으로
									desc.Color = SEA_STONE
								elseif desc:IsA("BasePart") and desc.Transparency < 1 then
									desc.Color = SEA_PART
								elseif desc:IsA("PointLight") or desc:IsA("SpotLight") then
									desc.Color = SEA_PARTICLE
								end
							end

							-- [버그수정] DesertGuardian_RisingStone처럼 자식이 없는 단일 MeshPart는
							-- GetDescendants()가 빈 배열을 반환해서 색이 하나도 안 바뀌었음.
							-- 최상위 인스턴스 자체도 반드시 함께 칠해야 함.
							tintOne(inst)
							for _, desc in ipairs(inst:GetDescendants()) do
								tintOne(desc)
							end
						end

						local function prepareVfxInstance(template, name, cf, hideParts)
							local inst = template:Clone()
							inst.Name = name
							if inst:IsA("BasePart") then
								inst.CanCollide = false
								inst.Anchored = true
								if hideParts then
									inst.Transparency = 1
								end
							elseif inst:IsA("Model") then
								for _, desc in ipairs(inst:GetDescendants()) do
									if desc:IsA("BasePart") then
										desc.CanCollide = false
										desc.Anchored = true
										if hideParts then
											desc.Transparency = 1
										end
									end
								end
							end
							setVfxCFrame(inst, cf)
							inst.Parent = workspace
							if isSeaVariant then
								tintVfxForSea(inst)
							end
							return inst
						end

						local function emitVfxParticles(inst, amount)
							for _, emitter in ipairs(inst:GetDescendants()) do
								if emitter:IsA("ParticleEmitter") then
									emitter.Enabled = true
									emitter:Emit(amount)
								end
							end
						end

						local function stopVfxParticles(inst)
							for _, emitter in ipairs(inst:GetDescendants()) do
								if emitter:IsA("ParticleEmitter") then
									emitter.Enabled = false
								end
							end
						end

						local function addSandBurst(host, name, amount, speed, sizeScale)
							if not host then return end
							local burst = Instance.new("ParticleEmitter")
							burst.Name = name
							burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
							burst.Color = ColorSequence.new(seaTone(Color3.fromRGB(255, 232, 175), Color3.fromRGB(200, 235, 255)), seaTone(Color3.fromRGB(185, 135, 80), Color3.fromRGB(60, 160, 220)))
							burst.Size = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.25 * sizeScale),
								NumberSequenceKeypoint.new(0.4, 0.85 * sizeScale),
								NumberSequenceKeypoint.new(1, 0)
							})
							burst.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.05),
								NumberSequenceKeypoint.new(0.7, 0.45),
								NumberSequenceKeypoint.new(1, 1)
							})
							burst.Lifetime = NumberRange.new(0.45, 0.9)
							burst.Rate = 0
							burst.Speed = speed
							burst.SpreadAngle = Vector2.new(180, 180)
							burst.VelocitySpread = 180
							burst.RotSpeed = NumberRange.new(-520, 520)
							burst.LightInfluence = 0
							burst.Parent = host
							burst:Emit(amount)
							Debris:AddItem(burst, 1.2)
						end

						local function createSandShockwave(pos, radius, color, duration)
							local ring = Instance.new("Part")
							ring.Name = "DesertGuardianSandShockwave"
							ring.Shape = Enum.PartType.Cylinder
							ring.Size = Vector3.new(0.25, 1, 1)
							ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
							ring.Anchored = true
							ring.CanCollide = false
							ring.Material = Enum.Material.Neon
							ring.Color = color
							ring.Transparency = 0.35
							ring.Parent = workspace
							ts:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Size = Vector3.new(0.25, radius * 2, radius * 2),
								Transparency = 1
							}):Play()
							Debris:AddItem(ring, duration + 0.2)
						end

						local function getRigNodeWorldCFrame(node)
							if not node then
								return nil
							end
							if node:IsA("Bone") or node:IsA("Attachment") then
								return node.WorldCFrame
							end
							if node:IsA("BasePart") then
								return node.CFrame
							end
							return nil
						end

						local function getDesertGuardianVisualBounds(forward)
							local minV = Vector3.new(math.huge, math.huge, math.huge)
							local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
							local minForward = math.huge
							local maxForward = -math.huge
							local found = false

							for _, part in ipairs(model:GetDescendants()) do
								if part:IsA("BasePart") and part ~= hrp and part.Name ~= "CombatHitbox" and part.Transparency < 0.95 then
									found = true
									local halfSize = part.Size * 0.5
									for _, x in ipairs({-1, 1}) do
										for _, y in ipairs({-1, 1}) do
											for _, z in ipairs({-1, 1}) do
												local corner = (part.CFrame * CFrame.new(halfSize.X * x, halfSize.Y * y, halfSize.Z * z)).Position
												minV = Vector3.new(
													math.min(minV.X, corner.X),
													math.min(minV.Y, corner.Y),
													math.min(minV.Z, corner.Z)
												)
												maxV = Vector3.new(
													math.max(maxV.X, corner.X),
													math.max(maxV.Y, corner.Y),
													math.max(maxV.Z, corner.Z)
												)
												local forwardProjection = corner:Dot(forward)
												minForward = math.min(minForward, forwardProjection)
												maxForward = math.max(maxForward, forwardProjection)
											end
										end
									end
								end
							end

							if found then
								local center = (minV + maxV) * 0.5
								local size = maxV - minV
								return center, size, maxForward - center:Dot(forward)
							end

							local boundsCf, boundsSize = model:GetBoundingBox()
							return boundsCf.Position, boundsSize, boundsSize.Z * 0.5
						end

						local function getDesertGuardianEyeCFrame()
							local nameCandidates = {
								"eye", "eyeball", "iris", "pupil", "oculus"
							}

							for _, descendant in ipairs(model:GetDescendants()) do
								if descendant ~= hrp and descendant.Name ~= "CombatHitbox" then
									local lowerName = string.lower(descendant.Name)
									for _, keyword in ipairs(nameCandidates) do
										if string.find(lowerName, keyword, 1, true) then
											local candidateCFrame = getRigNodeWorldCFrame(descendant)
											if candidateCFrame then
												return candidateCFrame
											end
										end
									end
								end
							end

							local forward = hrp.CFrame.LookVector
							local visualCenter, visualSize, frontOffset = getDesertGuardianVisualBounds(forward)
							local eyePos = visualCenter
								+ Vector3.new(0, visualSize.Y * 0.18, 0)
								+ forward * math.max(frontOffset + 0.25, 2.5)
							return CFrame.lookAt(eyePos, eyePos + forward)
						end

						-- 1. 상시 모래 휘날림 파티클 연출 (중복 생성 방지)
						if hrp and not hrp:FindFirstChild("DesertSandParticle") then
							local emitter = Instance.new("ParticleEmitter")
							emitter.Name = "DesertSandParticle"
							emitter.Texture = "rbxassetid://243577789"
							emitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(210, 180, 140), Color3.fromRGB(150, 210, 255)))
							emitter.Size = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.5),
								NumberSequenceKeypoint.new(0.5, 3.0),
								NumberSequenceKeypoint.new(1, 0)
							})
							emitter.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.2, 0.6),
								NumberSequenceKeypoint.new(0.8, 0.6),
								NumberSequenceKeypoint.new(1, 1)
							})
							emitter.Lifetime = NumberRange.new(1.5, 2.5)
							emitter.Rate = 25
							emitter.Speed = NumberRange.new(5, 12)
							emitter.SpreadAngle = Vector2.new(180, 180)
							emitter.VelocitySpread = 180
							emitter.Parent = hrp

							local grainEmitter = Instance.new("ParticleEmitter")
							grainEmitter.Name = "DesertSandGrainParticle"
							grainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
							grainEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(255, 230, 170), Color3.fromRGB(210, 235, 255)), seaTone(Color3.fromRGB(175, 125, 70), Color3.fromRGB(50, 150, 210)))
							grainEmitter.Size = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.12),
								NumberSequenceKeypoint.new(0.6, 0.35),
								NumberSequenceKeypoint.new(1, 0)
							})
							grainEmitter.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.35),
								NumberSequenceKeypoint.new(0.8, 0.65),
								NumberSequenceKeypoint.new(1, 1)
							})
							grainEmitter.Lifetime = NumberRange.new(0.7, 1.4)
							grainEmitter.Rate = 18
							grainEmitter.Speed = NumberRange.new(3, 9)
							grainEmitter.SpreadAngle = Vector2.new(180, 180)
							grainEmitter.VelocitySpread = 180
							grainEmitter.RotSpeed = NumberRange.new(-240, 240)
							grainEmitter.LightInfluence = 0
							grainEmitter.Parent = hrp

							local coreLight = Instance.new("PointLight")
							coreLight.Name = "DesertGuardianCoreLight"
							coreLight.Color = seaTone(Color3.fromRGB(255, 190, 95), Color3.fromRGB(90, 200, 255))
							coreLight.Brightness = 0.8
							coreLight.Range = 18
							coreLight.Shadows = false
							coreLight.Parent = hrp
						end

						-- 2. 상시 지면 모래 먼지 소용돌이 연출 (바닥 높이 실시간 매칭)
						local groundRayParams = RaycastParams.new()
						groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
						groundRayParams.FilterDescendantsInstances = {model}
						local groundRay = workspace:Raycast(hrp.Position, Vector3.new(0, -50, 0), groundRayParams)
						local groundY = hrp.Position.Y - (humanoid.HipHeight or 1.5) - (hrp.Size.Y / 2)
						if groundRay then
							groundY = groundRay.Position.Y
						end

						local groundPart = model:FindFirstChild("GroundSandStormPart")
						if not groundPart then
							groundPart = Instance.new("Part")
							groundPart.Name = "GroundSandStormPart"
							groundPart.Size = Vector3.new(1, 0.1, 1)
							groundPart.Transparency = 1
							groundPart.Anchored = true
							groundPart.CanCollide = false
							groundPart.Parent = model

							local groundEmitter = Instance.new("ParticleEmitter")
							groundEmitter.Name = "GroundEmitter"
							groundEmitter.Texture = "rbxassetid://243577789"
							groundEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(195, 160, 120), Color3.fromRGB(140, 200, 240)))
							groundEmitter.Size = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1.0),
								NumberSequenceKeypoint.new(0.5, 5.0),
								NumberSequenceKeypoint.new(1, 8.0)
							})
							groundEmitter.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.1, 0.75),
								NumberSequenceKeypoint.new(0.8, 0.75),
								NumberSequenceKeypoint.new(1, 1)
							})
							groundEmitter.Lifetime = NumberRange.new(1.0, 2.0)
							groundEmitter.Rate = 35
							groundEmitter.Speed = NumberRange.new(3, 8)
							groundEmitter.SpreadAngle = Vector2.new(90, 90)
							groundEmitter.VelocitySpread = 180
							groundEmitter.Parent = groundPart
						end
						groundPart.CFrame = CFrame.new(hrp.Position.X, groundY + 0.1, hrp.Position.Z)



						-- 스킬별 쿨타임 정의
						local waveCooldown = 15.0
						local quicksandCooldown = 18.0
						local laserCooldown = config.attackCooldown or 1.5
						local blastCooldown = 6.0

						-- [패턴 1] 모래 해일 장벽 (Sand Wall Storm) - 전역 공격 & 안전 구멍 틈새 파훼 기믹
						if distToPlayer <= 45 and (now - lastJumpTick >= waveCooldown) then
							lastJumpTick = now
							humanoid:MoveTo(hrp.Position) -- 제자리 캐스팅
							playBossSound("SandWall_Charge", hrp)

							-- 물리 흔들림을 막기 위해 시전 동안 고정
							hrp.Anchored = true

							-- 1~5 중 하나의 틈새 안전지대(Safe Zone) 인덱스 무작위 결정
							local safeIndex1 = math.random(1, 5)

							local forward = hrp.CFrame.LookVector
							local right = hrp.CFrame.RightVector
							local baseFloorPos = hrp.Position - Vector3.new(0, (humanoid.HipHeight or 1.5) + (hrp.Size.Y / 2), 0)

							local telegraphParts = {}

							-- 2초 동안 전조 가로 예고선 표시 (안전 영역 i == safeIndex1 를 비워둠)
							for i = 1, 5 do
								if i ~= safeIndex1 then
									local offset = -40 + (i - 0.5) * 16
									local startPos = baseFloorPos + right * offset + forward * 5
									local centerPos = startPos + forward * 40

									local warnPart = Instance.new("Part")
									warnPart.Name = "SandWallTelegraph_" .. i
									warnPart.Size = Vector3.new(16, 0.4, 80)
									warnPart.CFrame = CFrame.new(centerPos) * hrp.CFrame.Rotation
									warnPart.Anchored = true
									warnPart.CanCollide = false
									warnPart.Material = Enum.Material.Neon
									warnPart.Color = Color3.fromRGB(255, 60, 60)
									warnPart.Transparency = 0.85
									warnPart.Parent = workspace
									table.insert(telegraphParts, warnPart)

									ts:Create(warnPart, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										Transparency = 0.45
									}):Play()
								end
							end

							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("DesertGuardian_Magic") or anims.Monster:FindFirstChild("Stump_Magic"))
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									if track then track:Play() end
								end
							end)

							task.wait(2.0)

							-- 예고 장판 제거
							for _, p in ipairs(telegraphParts) do
								p:Destroy()
							end

							hrp.Anchored = false

							playBossSound("SandWall_Cast", hrp)
							if isAlive then
								-- 실제 모래 해일 장벽 생성 및 발사 (안전 영역 i == safeIndex1 를 비워둠)
								task.spawn(function()
									local waveParts = {}
									local waveTornados = {}

									local vfxBoss = ReplicatedStorage:FindFirstChild("Assets")
										and ReplicatedStorage.Assets:FindFirstChild("VFX")
										and ReplicatedStorage.Assets.VFX:FindFirstChild("Boss")
									local tornadoModel = vfxBoss and vfxBoss:FindFirstChild("DesertGuardian_Tornado")

									for i = 1, 5 do
										if i ~= safeIndex1 then
											local offset = -40 + (i - 0.5) * 16
											-- 장벽 시작 위치 (보스 앞 5스터드)
											local startPos = baseFloorPos + right * offset + forward * 5 + Vector3.new(0, 10, 0) -- 세로 두께 20의 중심 높이 10스터드

											local wallPart = Instance.new("Part")
											wallPart.Name = "SandWallPart_" .. i
											wallPart.Size = Vector3.new(16, 20, 3)
											wallPart.CFrame = CFrame.new(startPos) * hrp.CFrame.Rotation
											wallPart.Anchored = true
											wallPart.CanCollide = false
											wallPart.Transparency = 1 -- 실제 충돌감지 파트는 투명
											wallPart.Parent = workspace

											table.insert(waveParts, wallPart)

											-- 사용자가 제작한 회오리 에셋을 해일 장벽에 연동
											if tornadoModel then
												local tornado = prepareVfxInstance(tornadoModel, "SandWallTornado_" .. i, wallPart.CFrame, true)
												emitVfxParticles(tornado, 45)
												addSandBurst(getEmitterHost(tornado), "SandWallGoldGrain", 70, NumberRange.new(18, 34), 1.2)

												table.insert(waveTornados, tornado)
											else
												-- 폴백: 기존 모래벽 파티클 이펙트
												local wallEmitter = Instance.new("ParticleEmitter")
												wallEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
												wallEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(240, 212, 155), Color3.fromRGB(170, 220, 255)))
												wallEmitter.Size = NumberSequence.new({
													NumberSequenceKeypoint.new(0, 1.2),
													NumberSequenceKeypoint.new(0.5, 2.5),
													NumberSequenceKeypoint.new(1, 0)
												})
												wallEmitter.Transparency = NumberSequence.new({
													NumberSequenceKeypoint.new(0, 0.15),
													NumberSequenceKeypoint.new(0.8, 0.45),
													NumberSequenceKeypoint.new(1, 1.0)
												})
												wallEmitter.Lifetime = NumberRange.new(0.4, 0.8)
												wallEmitter.Rate = 280
												wallEmitter.Speed = NumberRange.new(12, 26)
												wallEmitter.SpreadAngle = Vector2.new(8, 8)
												wallEmitter.VelocitySpread = 10
												wallEmitter.RotSpeed = NumberRange.new(-360, 360)
												wallEmitter.LightInfluence = 0
												wallEmitter.Parent = wallPart
												wallEmitter:Emit(40)
											end
										end
									end

									-- 2.5초간 보스 전방 80스터드 거리 트윈 전진
									local travelTime = 2.5
									local startTime = os.clock()

									for i, wall in ipairs(waveParts) do
										local targetCFrame = wall.CFrame + forward * 80
										ts:Create(wall, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
											CFrame = targetCFrame
										}):Play()

										local tornado = waveTornados[i]
										if tornado then
											setVfxCFrame(tornado, wall.CFrame)
										end
									end

									-- 트윈 중 회오리 개별 회전 및 종료 시 페이드아웃 제어
									if #waveTornados > 0 then
										task.spawn(function()
											local rotY = 0
											while os.clock() - startTime < travelTime and isAlive do
												task.wait(0.02)
												rotY = (rotY + 15) % 360
												for idx, tornado in ipairs(waveTornados) do
													if tornado and tornado.Parent then
														local wall = waveParts[idx]
														local followPos = (wall and wall.Parent) and wall.Position or getVfxPosition(tornado)
														setVfxCFrame(tornado, CFrame.new(followPos) * CFrame.Angles(0, math.rad(rotY), 0))
													end
												end
											end

											-- 전진 종료 후 파티클 방출 중지
											for _, tornado in ipairs(waveTornados) do
												if tornado and tornado.Parent then
													stopVfxParticles(tornado)
												end
											end

											-- 1.2초 후 오브젝트 소멸
											task.wait(1.2)
											for _, tornado in ipairs(waveTornados) do
												if tornado and tornado.Parent then
													tornado:Destroy()
												end
											end
										end)
									end

									-- 이동하는 모래 장벽의 플레이어 충돌 검사 (AABB 로컬 좌표계 판정)
									local hitPlayers = {}
									while os.clock() - startTime < travelTime and isAlive do
										task.wait(0.05)
										for _, wall in ipairs(waveParts) do
											if not wall or not wall.Parent then continue end

											for _, p in ipairs(Players:GetPlayers()) do
												local char = p.Character
												local phum = char and char:FindFirstChild("Humanoid")
												local pRoot = char and char:FindFirstChild("HumanoidRootPart")

												if phum and phum.Health > 0 and pRoot and not hitPlayers[p.UserId] then
													local localPos = wall.CFrame:Inverse() * pRoot.Position
													local halfX = wall.Size.X / 2 + 1.5
													local halfY = wall.Size.Y / 2 + 2.0
													local halfZ = wall.Size.Z / 2 + 1.5

													-- 장벽 충돌 박스 안으로 들어갔을 때
													if math.abs(localPos.X) <= halfX and localPos.Y >= -halfY and localPos.Y <= halfY and math.abs(localPos.Z) <= halfZ then
														hitPlayers[p.UserId] = true
														dealDamageToHumanoid(phum, (config.baseDamage or 80) * 2.0)

														local bounceDir = (pRoot.Position - wall.Position)
														bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
														local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
														local NetController = require(Controllers:WaitForChild("NetController"))
														NetController.FireClient(p, "Player.Stun", bounceDir * 1.5)
													end
												end
											end
										end
									end

									-- 전진 종료 후 삭제
									for _, wall in ipairs(waveParts) do
										wall:Destroy()
									end
								end)
							end

							task.wait(1.0)

						-- [패턴 2] 유사(流沙) 늪과 3연속 솟구침 (Quicksand & Spout Combo) - 늪 소용돌이 인지 & 3연속 무빙 회피 기믹
						elseif distToPlayer <= 45 and (now - lastPoisonTick >= quicksandCooldown) then
							lastPoisonTick = now
							humanoid:MoveTo(hrp.Position)
							playBossSound("Quicksand_Cast", hrp)

							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("DesertGuardian_Attack") or anims.Monster:FindFirstChild("Stump_Magic"))
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									if track then track:Play() end
								end
							end)

							local targetFloorPos = targetPlayerPos
							local raycastParams = RaycastParams.new()
							raycastParams.FilterType = Enum.RaycastFilterType.Exclude
							raycastParams.FilterDescendantsInstances = {model, targetPlayer}
							local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), raycastParams)
							if rayResult then targetFloorPos = rayResult.Position else targetFloorPos = targetFloorPos - Vector3.new(0, phrp.Size.Y / 2, 0) end

							-- 1초 늪 영역 예고 장판 생성 (반경 14스터드)
							local warnCircle = Instance.new("Part")
							warnCircle.Name = "QuicksandTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, 28, 28)
							warnCircle.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = seaTone(Color3.fromRGB(160, 120, 80), Color3.fromRGB(30, 140, 200))
							warnCircle.Transparency = 0.85
							warnCircle.Parent = workspace

							ts:Create(warnCircle, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()

							task.wait(1.0)
							warnCircle:Destroy()

							if isAlive then
								-- 실제 유사 늪 파트 생성
								local quicksand = Instance.new("Part")
								quicksand.Name = "QuicksandPrison"
								quicksand.Shape = Enum.PartType.Cylinder
								quicksand.Size = Vector3.new(0.2, 28, 28)
								quicksand.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
								quicksand.Anchored = true
								quicksand.CanCollide = false
								quicksand.Material = Enum.Material.Sand
								quicksand.Color = seaTone(Color3.fromRGB(110, 85, 55), Color3.fromRGB(20, 60, 95))
								quicksand.Parent = workspace

								-- 늪 비주얼용 투명 파트 생성 (회전이 없어 파티클이 수직으로 이쁘게 상승함)
								local particlePart = Instance.new("Part")
								particlePart.Name = "QuicksandParticlePart"
								particlePart.Size = Vector3.new(28, 0.1, 28)
								particlePart.Position = targetFloorPos + Vector3.new(0, 0.1, 0)
								particlePart.Transparency = 1
								particlePart.Anchored = true
								particlePart.CanCollide = false
								particlePart.Parent = workspace

								local vfxBoss = ReplicatedStorage:FindFirstChild("Assets")
									and ReplicatedStorage.Assets:FindFirstChild("VFX")
									and ReplicatedStorage.Assets.VFX:FindFirstChild("Boss")
								local tornadoModel = vfxBoss and vfxBoss:FindFirstChild("DesertGuardian_Tornado")

								local quicksandTornado = nil
								if tornadoModel then
									quicksandTornado = prepareVfxInstance(tornadoModel, "QuicksandTornado", CFrame.new(targetFloorPos), true)
									emitVfxParticles(quicksandTornado, 55)
									addSandBurst(getEmitterHost(quicksandTornado), "QuicksandGoldGrain", 110, NumberRange.new(10, 24), 1.5)
									createSandShockwave(targetFloorPos, 16, seaTone(Color3.fromRGB(210, 160, 95), Color3.fromRGB(70, 190, 255)), 0.45)

									-- 회오리 회전 루프 (늪 유지 시간 동안 실행)
									task.spawn(function()
										local rotY = 0
										local sTime = os.clock()
										while quicksandTornado and quicksandTornado.Parent and os.clock() - sTime < 5.0 and isAlive do
											task.wait(0.02)
											rotY = (rotY + 15) % 360
											setVfxCFrame(quicksandTornado, CFrame.new(targetFloorPos) * CFrame.Angles(0, math.rad(rotY), 0))
										end
									end)
								else
									-- 폴백: 늪 회전 소용돌이 이펙트 이미터 장착 (100% 무조건 노출되는 로블록스 내장 텍스처 사용)
									local quicksandEmitter = Instance.new("ParticleEmitter")
									quicksandEmitter.Texture = "rbxasset://textures/particles/fire_main.dds" -- 소용돌이 갈래 형태
									quicksandEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(235, 205, 150), Color3.fromRGB(160, 225, 255))) -- 밝고 화사한 모래 옐로우
									quicksandEmitter.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 0.8),
										NumberSequenceKeypoint.new(0.5, 1.6),
										NumberSequenceKeypoint.new(1, 0)
									})
									quicksandEmitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.9)})
									quicksandEmitter.Lifetime = NumberRange.new(0.6, 1.2)
									quicksandEmitter.Rate = 240
									quicksandEmitter.Speed = NumberRange.new(6, 12)
									quicksandEmitter.SpreadAngle = Vector2.new(180, 180)
									quicksandEmitter.VelocitySpread = 180
									quicksandEmitter.RotSpeed = NumberRange.new(-360, 360) -- 늪 속에서 빠르게 회용돌이치는 스핀
									quicksandEmitter.LightInfluence = 0
									quicksandEmitter.EmissionDirection = Enum.NormalId.Top
									quicksandEmitter.Parent = particlePart
									quicksandEmitter:Emit(60) -- 생성 즉시 방출로 늪 비주얼 즉각 인지 유도
								end

								-- 늪 유지(5초) 및 3연속 가시 솟구침 콤보 시작
								task.spawn(function()
									local duration = 5.0
									local startTime = os.clock()
									local nextSpikeTime = 0.5 -- 늪 생성 0.5초 후 첫 솟구침 예고
									local spikeCount = 0

									while os.clock() - startTime < duration and isAlive do
										task.wait(0.1)

										-- 늪 속 플레이어 감속 디버프 적용
										for _, p in ipairs(Players:GetPlayers()) do
											local char = p.Character
											local phum = char and char:FindFirstChild("Humanoid")
											local pRoot = char and char:FindFirstChild("HumanoidRootPart")
											if phum and phum.Health > 0 and pRoot then
												local dist = Vector3.new(targetFloorPos.X - pRoot.Position.X, 0, targetFloorPos.Z - pRoot.Position.Z).Magnitude
												if dist <= 14 then
													if not phum:GetAttribute("OriginalSpeed") then
														phum:SetAttribute("OriginalSpeed", phum.WalkSpeed)
													end
													phum.WalkSpeed = 6 -- 늪 안에서 감속 (화면 떨림 물리력 적용 완전 배제)
													dealDamageToHumanoid(phum, (config.baseDamage or 80) * 0.03) -- 경미한 늪 틱 데미지
												else
													local origSpeed = phum:GetAttribute("OriginalSpeed")
													if origSpeed then
														phum.WalkSpeed = origSpeed
														phum:SetAttribute("OriginalSpeed", nil)
													end
												end
											end
										end

										-- 1.2초 간격 3연속 가시 솟구침 콤보
										if os.clock() - startTime >= nextSpikeTime and spikeCount < 3 then
											spikeCount = spikeCount + 1
											nextSpikeTime = nextSpikeTime + 1.3

											-- 현재 타겟 플레이어 발밑 좌표 따옴 (Character 직접 대입으로 crash 해결)
											local currentTargetChar = targetPlayer
											local currentTargetRoot = currentTargetChar and currentTargetChar:FindFirstChild("HumanoidRootPart")
											if currentTargetRoot then
												local spikeTargetPos = currentTargetRoot.Position
												local raycastParams2 = RaycastParams.new()
												raycastParams2.FilterType = Enum.RaycastFilterType.Exclude
												raycastParams2.FilterDescendantsInstances = {model, targetPlayer}
												local rayResult2 = workspace:Raycast(spikeTargetPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), raycastParams2)
												if rayResult2 then spikeTargetPos = rayResult2.Position else spikeTargetPos = spikeTargetPos - Vector3.new(0, currentTargetRoot.Size.Y / 2, 0) end

												task.spawn(function()
													-- 가시 솟구침 0.5초 경고 장판 (반경 4스터드)
													local spikeTelegraph = Instance.new("Part")
													spikeTelegraph.Name = "SpikeTelegraph"
													spikeTelegraph.Shape = Enum.PartType.Cylinder
													spikeTelegraph.Size = Vector3.new(0.4, 8, 8)
													spikeTelegraph.CFrame = CFrame.new(spikeTargetPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
													spikeTelegraph.Anchored = true
													spikeTelegraph.CanCollide = false
													spikeTelegraph.Material = Enum.Material.Neon
													spikeTelegraph.Color = Color3.fromRGB(255, 0, 0)
													spikeTelegraph.Transparency = 0.8
													spikeTelegraph.Parent = workspace
													playBossSound("Spike_Telegraph", spikeTelegraph)

													ts:Create(spikeTelegraph, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.35}):Play()

													task.wait(0.5)
													spikeTelegraph:Destroy()

													if isAlive then
														-- 솟구침 돌 VFX 소환 및 솟구쳐오르는 연출 (DesertGuardian_RisingStone)
														local vfxBoss = ReplicatedStorage:FindFirstChild("Assets")
															and ReplicatedStorage.Assets:FindFirstChild("VFX")
															and ReplicatedStorage.Assets.VFX:FindFirstChild("Boss")
														local stoneModel = vfxBoss and vfxBoss:FindFirstChild("DesertGuardian_RisingStone")

														local stonePart = nil
														if stoneModel then
															stonePart = prepareVfxInstance(stoneModel, "DesertGuardian_RisingStone", CFrame.new(spikeTargetPos), false)
															playBossSound("Spike_Burst", stonePart)
															-- 돌의 Y 크기를 구해와 지면 아래로 완전히 감춤 (크기 + 마진)
															local stoneHeight
															if stonePart:IsA("Model") then
																local _, bounds = stonePart:GetBoundingBox()
																stoneHeight = bounds.Y
															else
																stoneHeight = stonePart.Size.Y
															end
															setVfxCFrame(stonePart, CFrame.new(spikeTargetPos - Vector3.new(0, stoneHeight + 2, 0)) * hrp.CFrame.Rotation)

															-- 0.15초 동안 지면 높이(spikeTargetPos)로 급속 솟구침 트윈
															if stonePart:IsA("BasePart") then
																ts:Create(stonePart, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
																	CFrame = CFrame.new(spikeTargetPos) * hrp.CFrame.Rotation
																}):Play()
															else
																task.spawn(function()
																	local startCf = getVfxCFrame(stonePart)
																	local endCf = CFrame.new(spikeTargetPos) * hrp.CFrame.Rotation
																	local startAt = os.clock()
																	while stonePart and stonePart.Parent and os.clock() - startAt < 0.15 do
																		local alpha = math.clamp((os.clock() - startAt) / 0.15, 0, 1)
																		setVfxCFrame(stonePart, startCf:Lerp(endCf, alpha))
																		task.wait()
																	end
																	if stonePart and stonePart.Parent then
																		setVfxCFrame(stonePart, endCf)
																	end
																end)
															end
															createSandShockwave(spikeTargetPos, 9, seaTone(Color3.fromRGB(235, 190, 115), Color3.fromRGB(90, 200, 255)), 0.35)

															-- 돌이 솟구친 후 다시 땅속으로 자연스레 들어가는 프리미엄 트윈
															task.spawn(function()
																task.wait(0.5)
																if stonePart and stonePart.Parent then
																	local sinkCf = CFrame.new(spikeTargetPos - Vector3.new(0, stoneHeight + 2, 0)) * hrp.CFrame.Rotation
																	if stonePart:IsA("BasePart") then
																		local sink = ts:Create(stonePart, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
																			CFrame = sinkCf
																		})
																		sink:Play()
																		sink.Completed:Connect(function()
																			stonePart:Destroy()
																		end)
																	else
																		local startCf = getVfxCFrame(stonePart)
																		local startAt = os.clock()
																		while stonePart and stonePart.Parent and os.clock() - startAt < 0.3 do
																			local alpha = math.clamp((os.clock() - startAt) / 0.3, 0, 1)
																			setVfxCFrame(stonePart, startCf:Lerp(sinkCf, alpha))
																			task.wait()
																		end
																		if stonePart and stonePart.Parent then
																			stonePart:Destroy()
																		end
																	end
																end
															end)
														else
															-- 폴백: 기존 원기둥 앵커 파트 (수직 실린더 형태)
															stonePart = Instance.new("Part")
															stonePart.Name = "SandTornadoSpout"
															stonePart.Shape = Enum.PartType.Cylinder
															stonePart.Size = Vector3.new(16, 4, 4) -- X가 길이 방향
															-- 수직으로 세우기 위해 Z축 90도 회전 각도 부여
															stonePart.CFrame = CFrame.new(spikeTargetPos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90))
															stonePart.Color = seaTone(Color3.fromRGB(240, 215, 160), Color3.fromRGB(25, 50, 110))
															stonePart.Material = Enum.Material.Glass
															stonePart.Transparency = 0.85 -- 아주 희미하게 비치는 모래 원기둥 기둥
															stonePart.CanCollide = false
															stonePart.Anchored = true
															stonePart.Parent = workspace
															playBossSound("Spike_Burst", stonePart)

															-- 스크립트로 회오리 기둥 고속 회전 및 트윈 상승 애니메이션 실행
															task.spawn(function()
																local rotY = 0
																local spoutTime = 0.8
																local start = os.clock()
																while os.clock() - start < spoutTime and stonePart and stonePart.Parent do
																	task.wait(0.02)
																	rotY = (rotY + 25) % 360 -- 고속 회전 물리 비주얼 구현
																	stonePart.CFrame = CFrame.new(spikeTargetPos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(rotY), math.rad(90))
																end
															end)

															Debris:AddItem(stonePart, 1.0)
														end

														local stoneEmitterHost = getEmitterHost(stonePart)
														-- 세찬 모래바람 돌풍 줄기 (원기둥 표면 또는 돌 표면에서 위로 고속 방출)
														local spoutEmitter = Instance.new("ParticleEmitter")
														spoutEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
														spoutEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(240, 215, 160), Color3.fromRGB(150, 215, 255))) -- 밝고 화사한 모래 베이지
														spoutEmitter.Size = NumberSequence.new({
															NumberSequenceKeypoint.new(0, 0.8),
															NumberSequenceKeypoint.new(0.5, 2.0),
															NumberSequenceKeypoint.new(1, 0)
														})
														spoutEmitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.95)})
														spoutEmitter.Lifetime = NumberRange.new(0.35, 0.65)
														spoutEmitter.Rate = 240
														spoutEmitter.Speed = NumberRange.new(50, 90) -- 고속 수직 상승
														spoutEmitter.SpreadAngle = Vector2.new(3, 3) -- 확산을 극도로 억제하여 수직 회오리 기둥 고정!
														spoutEmitter.RotSpeed = NumberRange.new(400, 600) -- 고속 깔대기 회전 스핀
														spoutEmitter.LightInfluence = 0
														spoutEmitter.Shape = Enum.ParticleEmitterShape.Cylinder
														spoutEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
														spoutEmitter.EmissionDirection = Enum.NormalId.Top -- 실린더 윗면 방향으로 방출
														spoutEmitter.Parent = stoneEmitterHost
														spoutEmitter:Emit(120)

														-- 거친 모래가루 및 비산 알갱이 레이어 결합 (고운 황금가루 비산)
														local grainEmitter = Instance.new("ParticleEmitter")
														grainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
														grainEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(245, 222, 179), Color3.fromRGB(190, 230, 255)))
														grainEmitter.Size = NumberSequence.new({
															NumberSequenceKeypoint.new(0, 0.4),
															NumberSequenceKeypoint.new(1, 0)
														})
														grainEmitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1.0)})
														grainEmitter.Lifetime = NumberRange.new(0.5, 0.9)
														grainEmitter.Rate = 160
														grainEmitter.Speed = NumberRange.new(25, 60)
														grainEmitter.SpreadAngle = Vector2.new(25, 25) -- 좁은 비산각
														grainEmitter.VelocitySpread = 25
														grainEmitter.LightInfluence = 0
														grainEmitter.EmissionDirection = Enum.NormalId.Top
														grainEmitter.Parent = stoneEmitterHost
														grainEmitter:Emit(70)
														addSandBurst(stoneEmitterHost, "RisingStoneDustHalo", 90, NumberRange.new(18, 42), 1.4)

														-- 피해 및 부드러운 에어본 판정
														for _, p in ipairs(Players:GetPlayers()) do
															local char = p.Character
															local phum = char and char:FindFirstChild("Humanoid")
															local pRoot = char and char:FindFirstChild("HumanoidRootPart")
															if phum and phum.Health > 0 and pRoot then
																local dist = Vector3.new(spikeTargetPos.X - pRoot.Position.X, 0, spikeTargetPos.Z - pRoot.Position.Z).Magnitude
																if dist <= 4 then
																	dealDamageToHumanoid(phum, (config.baseDamage or 80) * 0.6)

																	-- 부드러운 에어본 속도 부여 (하늘로 45스터드)
																	pRoot.AssemblyLinearVelocity = Vector3.new(0, 45, 0)

																	local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
																	local NetController = require(Controllers:WaitForChild("NetController"))
																	NetController.FireClient(p, "Player.Stun", Vector3.new(0, 0.5, 0))
																end
															end
														end
													end
												end)
											end
										end
									end

									-- 디버프 복구
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										if phum then
											local origSpeed = phum:GetAttribute("OriginalSpeed")
											if origSpeed then
												phum.WalkSpeed = origSpeed
												phum:SetAttribute("OriginalSpeed", nil)
											end
										end
									end

									quicksand:Destroy()
									particlePart:Destroy()

									if quicksandTornado and quicksandTornado.Parent then
										stopVfxParticles(quicksandTornado)

										local tempTornado = quicksandTornado
										task.spawn(function()
											task.wait(1.2)
											if tempTornado and tempTornado.Parent then
												tempTornado:Destroy()
											end
										end)
									end
								end)
							end

							task.wait(1.0)

						-- [패턴 3] 사안 레이저 (Eye Laser) - CyclopsBat 레이저 형식 그대로, 색상만 사막 테마 적용
						elseif distToPlayer <= 55 and (now - lastThrustTick >= laserCooldown) then
							lastThrustTick = now
							humanoid:MoveTo(hrp.Position)

							local telegraphDuration = 0.8
							local targetFloorPos = targetPlayerPos

							local raycastParams = RaycastParams.new()
							raycastParams.FilterType = Enum.RaycastFilterType.Exclude
							raycastParams.FilterDescendantsInstances = {model, targetPlayer}

							local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), raycastParams)
							if rayResult then
								targetFloorPos = rayResult.Position
							else
								targetFloorPos = targetFloorPos - Vector3.new(0, phrp.Size.Y / 2 + 0.1, 0)
							end

							local warnCircle = Instance.new("Part")
							warnCircle.Name = "DesertGuardianLaserTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, 18, 18)
							warnCircle.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.CanTouch = false
							warnCircle.CanQuery = false
							warnCircle.CastShadow = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = Color3.fromRGB(255, 40, 25)
							warnCircle.Transparency = 0.8
							warnCircle.Parent = workspace

							ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
								Transparency = 0.3,
								Color = Color3.fromRGB(255, 0, 0)
							}):Play()

							local eyeCFrame = getDesertGuardianEyeCFrame()
							local laserOriginCFrame = eyeCFrame * CFrame.new(0, 0, -1)
							local chargeSphere = Instance.new("Part")
							chargeSphere.Name = "DesertGuardianLaserCharge"
							chargeSphere.Shape = Enum.PartType.Ball
							chargeSphere.Size = Vector3.new(1.6, 1.6, 1.6)
							chargeSphere.Color = seaTone(Color3.fromRGB(255, 190, 80), Color3.fromRGB(90, 200, 255))
							chargeSphere.Material = Enum.Material.Neon
							chargeSphere.Anchored = true
							chargeSphere.CanCollide = false
							chargeSphere.CanTouch = false
							chargeSphere.CanQuery = false
							chargeSphere.CFrame = laserOriginCFrame
							chargeSphere.Parent = workspace
							playBossSound("Laser_Charge", chargeSphere)

							ts:Create(chargeSphere, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Elastic), {
								Size = Vector3.new(3.8, 3.8, 3.8)
							}):Play()

							local castStartTime = os.clock()
							while os.clock() - castStartTime < telegraphDuration and isAlive do
								if phrp and phrp.Parent then
									local lookDir = (phrp.Position - hrp.Position)
									lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
									if lookDir.Magnitude > 0.1 then
										hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
									end
									eyeCFrame = getDesertGuardianEyeCFrame()
									laserOriginCFrame = eyeCFrame * CFrame.new(0, 0, -1)
									chargeSphere.CFrame = laserOriginCFrame
								end
								task.wait(0.05)
							end

							if warnCircle and warnCircle.Parent then
								warnCircle:Destroy()
							end
							if chargeSphere and chargeSphere.Parent then
								chargeSphere:Destroy()
							end

							if isAlive and phrp and phrp.Parent then
								eyeCFrame = getDesertGuardianEyeCFrame()
								laserOriginCFrame = eyeCFrame * CFrame.new(0, 0, -1)
								local startLaserPos = laserOriginCFrame.Position
								local endLaserPos = targetFloorPos

								local laserModel = Instance.new("Model")
								laserModel.Name = "DesertGuardianEyeLaserModel"

								local laserCore = Instance.new("Part")
								laserCore.Name = "LaserCore"
								laserCore.Material = Enum.Material.Neon
								laserCore.Color = seaTone(Color3.fromRGB(255, 235, 160), Color3.fromRGB(210, 240, 255))
								laserCore.CanCollide = false
								laserCore.CanTouch = false
								laserCore.CanQuery = false
								laserCore.Anchored = true
								laserCore.Parent = laserModel

								local laserAura = Instance.new("Part")
								laserAura.Name = "LaserAura"
								laserAura.Material = Enum.Material.Neon
								laserAura.Color = seaTone(Color3.fromRGB(205, 125, 35), Color3.fromRGB(25, 140, 200))
								laserAura.CanCollide = false
								laserAura.CanTouch = false
								laserAura.CanQuery = false
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

								updateLaserVisual(startLaserPos, endLaserPos, 3.2)
								laserModel.Parent = workspace
								playBossSound("Laser_Shoot", laserCore)

								local exp = Instance.new("Explosion")
								exp.BlastRadius = 9
								exp.BlastPressure = 0
								exp.Position = endLaserPos
								exp.ExplosionType = Enum.ExplosionType.NoCraters
								if isSeaVariant then
									-- 로블록스 기본 Explosion은 항상 주황 화염/연기 비주얼이 강제로 재생되므로
									-- 바다 테마에서는 그 기본 비주얼을 끄고, 크라켄 체스판 공격과 동일한
									-- 물기둥+물보라 이펙트로 완전히 대체한다.
									exp.Visible = false
								end
								exp.Parent = workspace

								if isSeaVariant then
									task.spawn(function()
										local splashHost = Instance.new("Part")
										splashHost.Name = "AbyssGuardianLaserSplash"
										splashHost.Size = Vector3.new(0.2, 0.2, 0.2)
										splashHost.Transparency = 1
										splashHost.Anchored = true
										splashHost.CanCollide = false
										splashHost.CanQuery = false
										splashHost.CanTouch = false
										splashHost.CFrame = CFrame.new(endLaserPos)
										splashHost.Parent = workspace
										Debris:AddItem(splashHost, 2.0)

										-- 상승하는 물기둥 + 사방으로 튀는 물보라 (크라켄 체스판 공격과 동일한 텍스처)
										local burstPe = Instance.new("ParticleEmitter")
										burstPe.Texture = SEA_WATER_TEX_2
										burstPe.Color = ColorSequence.new(Color3.fromRGB(190, 230, 255))
										burstPe.Size = NumberSequence.new({
											NumberSequenceKeypoint.new(0, 9),
											NumberSequenceKeypoint.new(1, 0),
										})
										burstPe.Transparency = NumberSequence.new({
											NumberSequenceKeypoint.new(0, 0.1),
											NumberSequenceKeypoint.new(1, 1),
										})
										burstPe.Lifetime = NumberRange.new(0.4, 0.7)
										burstPe.Rate = 0
										burstPe.Speed = NumberRange.new(20, 40)
										burstPe.SpreadAngle = Vector2.new(180, 180)
										burstPe.Acceleration = Vector3.new(0, -70, 0)
										burstPe.Parent = splashHost
										burstPe:Emit(60)

										local risePe = Instance.new("ParticleEmitter")
										risePe.Texture = SEA_WATER_TEX_1
										risePe.Color = ColorSequence.new(Color3.fromRGB(140, 210, 255))
										risePe.Size = NumberSequence.new({
											NumberSequenceKeypoint.new(0, 6),
											NumberSequenceKeypoint.new(1, 12),
										})
										risePe.Transparency = NumberSequence.new({
											NumberSequenceKeypoint.new(0, 0.2),
											NumberSequenceKeypoint.new(1, 1),
										})
										risePe.Lifetime = NumberRange.new(0.3, 0.5)
										risePe.Rate = 0
										risePe.Speed = NumberRange.new(6, 14)
										risePe.SpreadAngle = Vector2.new(20, 20)
										risePe.EmissionDirection = Enum.NormalId.Top
										risePe.Parent = splashHost
										risePe:Emit(30)

										-- 실제 게임 분수 이펙트(SquirtWater) 재사용
										local squirtTemplate = ReplicatedStorage:FindFirstChild("Assets")
										squirtTemplate = squirtTemplate and squirtTemplate:FindFirstChild("VFX")
										squirtTemplate = squirtTemplate and squirtTemplate:FindFirstChild("Water")
										if squirtTemplate then
											local squirt = squirtTemplate:Clone()
											squirt.Anchored = true
											squirt.CanCollide = false
											squirt.CanQuery = false
											squirt.CanTouch = false
											squirt.CFrame = CFrame.new(endLaserPos)
											squirt.Parent = workspace
											Debris:AddItem(squirt, 2.5)
											local squirtPe = squirt:FindFirstChild("SquirtWater")
											if squirtPe then
												squirtPe.Rate = 150
												task.delay(0.5, function()
													if squirtPe and squirtPe.Parent then
														squirtPe.Enabled = false
													end
												end)
											end
										end
									end)
								end

								for _, p in ipairs(Players:GetPlayers()) do
									local char = p.Character
									local phum = char and char:FindFirstChild("Humanoid")
									local pRoot = char and char:FindFirstChild("HumanoidRootPart")
									if phum and phum.Health > 0 and pRoot then
										local dist = (pRoot.Position - endLaserPos).Magnitude
										if dist <= 9 then
											dealDamageToHumanoid(phum, config.baseDamage or 80, config.level)

											local bounceDir = (pRoot.Position - endLaserPos)
											bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
											local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
											local NetController = require(Controllers:WaitForChild("NetController"))
											NetController.FireClient(p, "Player.Stun", bounceDir * 1.5)

											task.spawn(function()
												local highlight = Instance.new("Highlight")
												highlight.Name = "DamageFlash"
												highlight.FillColor = seaTone(Color3.fromRGB(220, 150, 55), Color3.fromRGB(70, 190, 255))
												highlight.OutlineColor = seaTone(Color3.fromRGB(255, 235, 150), Color3.fromRGB(210, 240, 255))
												highlight.FillTransparency = 0.45
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

						-- [패턴 4] 모래 분출 (Sand Spout) - 즉발 견제기 & 무빙 회피 기믹
						elseif distToPlayer <= 45 and (now - lastAttackTick >= blastCooldown) then
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position)

							pcall(function()
								local animator = humanoid:FindFirstChildOfClass("Animator")
								local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
								local attackAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("DesertGuardian_Attack") or anims.Monster:FindFirstChild("Stump_Magic"))
								if animator and attackAnim then
									local track = animator:LoadAnimation(attackAnim)
									if track then track:Play() end
								end
							end)

							local targetFloorPos = targetPlayerPos
							local raycastParams = RaycastParams.new()
							raycastParams.FilterType = Enum.RaycastFilterType.Exclude
							raycastParams.FilterDescendantsInstances = {model, targetPlayer}
							local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), raycastParams)
							if rayResult then targetFloorPos = rayResult.Position else targetFloorPos = targetFloorPos - Vector3.new(0, phrp.Size.Y / 2, 0) end

							-- 0.6초 즉발성 좁은 예고 장판 (반경 7스터드)
							local warnCircle = Instance.new("Part")
							warnCircle.Name = "SandSpoutTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, 14, 14)
							warnCircle.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = seaTone(Color3.fromRGB(230, 150, 80), Color3.fromRGB(50, 170, 230))
							warnCircle.Transparency = 0.8
							warnCircle.Parent = workspace
							playBossSound("Spout_Telegraph", warnCircle)

							ts:Create(warnCircle, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.45}):Play()

							task.wait(0.6)
							warnCircle:Destroy()

							if isAlive then
								-- 디폴트 화염 폭발 비주얼 차단 (Visible = false)
								local blastEffect = Instance.new("Explosion")
								blastEffect.BlastRadius = 7
								blastEffect.BlastPressure = 0
								blastEffect.Position = targetFloorPos
								blastEffect.ExplosionType = Enum.ExplosionType.NoCraters
								blastEffect.Visible = false
								blastEffect.Parent = workspace

								-- 모래 분출 비주얼 파티클 기둥 생성 (DesertGuardian_Tornado)
								local vfxBoss = ReplicatedStorage:FindFirstChild("Assets")
									and ReplicatedStorage.Assets:FindFirstChild("VFX")
									and ReplicatedStorage.Assets.VFX:FindFirstChild("Boss")
								local tornadoModel = vfxBoss and vfxBoss:FindFirstChild("DesertGuardian_Tornado")

								local spoutVisual = nil
								if tornadoModel then
									spoutVisual = prepareVfxInstance(tornadoModel, "SandSpoutTornado", CFrame.new(targetFloorPos), true)
									playBossSound("Spout_Burst", spoutVisual)
									emitVfxParticles(spoutVisual, 60)
									addSandBurst(getEmitterHost(spoutVisual), "SandSpoutGoldGrain", 85, NumberRange.new(24, 48), 1.1)
									createSandShockwave(targetFloorPos, 10, seaTone(Color3.fromRGB(245, 180, 95), Color3.fromRGB(100, 205, 255)), 0.3)
								else
									-- 폴백: 기존 수직 실린더 형태 생성
									spoutVisual = Instance.new("Part")
									spoutVisual.Name = "SandSpoutTornado"
									spoutVisual.Shape = Enum.PartType.Cylinder
									spoutVisual.Size = Vector3.new(12, 3, 3) -- X가 길이 방향
									-- 수직으로 세우기 위해 Z축 90도 회전
									spoutVisual.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.rad(90))
									spoutVisual.Color = seaTone(Color3.fromRGB(240, 215, 160), Color3.fromRGB(150, 215, 255))
									spoutVisual.Material = Enum.Material.Glass
									spoutVisual.Transparency = 0.85
									spoutVisual.CanCollide = false
									spoutVisual.Anchored = true
									spoutVisual.Parent = workspace
									playBossSound("Spout_Burst", spoutVisual)

									-- 모래바람 돌풍 줄기 (회오리 기둥 모양 형성)
									local spoutEmitter = Instance.new("ParticleEmitter")
									spoutEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
									spoutEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(240, 215, 160), Color3.fromRGB(150, 215, 255))) -- 밝고 화사한 모래 베이지
									spoutEmitter.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 0.6),
										NumberSequenceKeypoint.new(0.2, 2.0),
										NumberSequenceKeypoint.new(1, 0)
									})
									spoutEmitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.95)})
									spoutEmitter.Lifetime = NumberRange.new(0.35, 0.65)
									spoutEmitter.Rate = 220
									spoutEmitter.Speed = NumberRange.new(45, 75) -- 고속 수직 상승
									spoutEmitter.SpreadAngle = Vector2.new(4, 4) -- 확산을 극도로 억제하여 수직 회오리 기둥 고정!
									spoutEmitter.RotSpeed = NumberRange.new(400, 600) -- 고속 깔대기 회전 스핀
									spoutEmitter.LightInfluence = 0
									spoutEmitter.Shape = Enum.ParticleEmitterShape.Cylinder
									spoutEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
									spoutEmitter.EmissionDirection = Enum.NormalId.Top
									spoutEmitter.Parent = spoutVisual
									spoutEmitter:Emit(70)

									-- 거친 모래알갱이 비산 레이어 결합
									local grainEmitter = Instance.new("ParticleEmitter")
									grainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
									grainEmitter.Color = ColorSequence.new(seaTone(Color3.fromRGB(245, 222, 179), Color3.fromRGB(190, 230, 255)))
									grainEmitter.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 0.4),
										NumberSequenceKeypoint.new(1, 0)
									})
									grainEmitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1.0)})
									grainEmitter.Lifetime = NumberRange.new(0.4, 0.8)
									grainEmitter.Rate = 140
									grainEmitter.Speed = NumberRange.new(20, 45)
									grainEmitter.SpreadAngle = Vector2.new(20, 20) -- 좁은 비산각
									grainEmitter.VelocitySpread = 20
									grainEmitter.LightInfluence = 0
									grainEmitter.EmissionDirection = Enum.NormalId.Top
									grainEmitter.Parent = spoutVisual
									grainEmitter:Emit(40)
								end

								-- 스크립트로 회오리 기둥 고속 회전 및 잔여 이펙트 정리 제어
								task.spawn(function()
									local rotY = 0
									local spoutTime = 0.7
									local start = os.clock()
									while os.clock() - start < spoutTime and spoutVisual and spoutVisual.Parent do
										task.wait(0.02)
										rotY = (rotY + 25) % 360
										if tornadoModel then
											setVfxCFrame(spoutVisual, CFrame.new(targetFloorPos) * CFrame.Angles(0, math.rad(rotY), 0))
										else
											spoutVisual.CFrame = CFrame.new(targetFloorPos + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(rotY), math.rad(90))
										end
									end

									-- 0.7초의 연출 완료 후, 새로운 파티클 생성을 끄고 부드러운 페이드 아웃을 대기
									if spoutVisual and spoutVisual.Parent then
										stopVfxParticles(spoutVisual)

										-- 기존 방출된 파티클의 잔여 수명(약 1.0초)을 대기한 뒤 인스턴스 소멸
										task.wait(1.2)
										if spoutVisual and spoutVisual.Parent then
											spoutVisual:Destroy()
										end
									end
								end)

								for _, p in ipairs(Players:GetPlayers()) do
									local char = p.Character
									local phum = char and char:FindFirstChild("Humanoid")
									local pRoot = char and char:FindFirstChild("HumanoidRootPart")
									if phum and phum.Health > 0 and pRoot then
										if (pRoot.Position - targetFloorPos).Magnitude <= 7 then
											dealDamageToHumanoid(phum, (config.baseDamage or 80) * 0.8)
											local bounceDir = Vector3.new(pRoot.Position.X - targetFloorPos.X, 0.5, pRoot.Position.Z - targetFloorPos.Z).Unit
											local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
											local NetController = require(Controllers:WaitForChild("NetController"))
											NetController.FireClient(p, "Player.Stun", bounceDir * 1.3)
										end
									end
								end
							end
							task.wait(0.4)

						-- 평상시 추격 (사막 보스는 15~22스터드 거리를 유지하며 기믹 시전을 준비)
						else
							if distToPlayer > 22 then
								humanoid:MoveTo(targetPlayerPos)
							elseif distToPlayer < 15 then
								local retreatPos = hrp.Position - (targetPlayerPos - hrp.Position).Unit * 15
								humanoid:MoveTo(retreatPos)
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
												dealDamageToHumanoid(phum, pDamage)
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
											dealDamageToHumanoid(currentPhum, config.baseDamage or 15)
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
												dealDamageToHumanoid(phum, 80) -- 돌진 데미지 80

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
												dealDamageToHumanoid(phum, 55)
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
												dealDamageToHumanoid(phum, 45) -- 평타 데미지 45

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
															dealDamageToHumanoid(phum, 180) -- 즉사급 데미지로 대폭 상향 (기믹 1)

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
														dealDamageToHumanoid(phum, 350) -- [데미지 즉사급 상향] 레이저 데미지 350

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
														dealDamageToHumanoid(phum, 250) -- 회오리 데미지 대폭 상향

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
												dealDamageToHumanoid(phum, 350) -- 도약 강타 즉사급 데미지로 상향

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
												dealDamageToHumanoid(phum, 300) -- 찌르기 데미지 대폭 상향
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
													dealDamageToHumanoid(phum, 200) -- 평타 데미지 대폭 상향
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
													dealDamageToHumanoid(phum, config.baseDamage, config.level)

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
														dealDamageToHumanoid(phum, pDamage)
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

									end)
								end
							end
						else
							humanoid:MoveTo(targetPlayerPos)
						end
					elseif config.mobModelName == "Samurai" then
						--========================================================================
						-- [Samurai 전용 FSM 분기]: 발도 돌진 참격, 벚꽃 회오리 광역 참격, 기본 참격 평타
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()

						-- 1. 발도 돌진 참격 (Iaido Dash Cut): 거리 15 ~ 35, 쿨타임 8.0초
						if distToPlayer >= 15 and distToPlayer <= 35 and (now - lastThrustTick >= 8.0) then
							lastThrustTick = now
							humanoid:MoveTo(hrp.Position) -- 이동 정지

							-- 타겟 방향으로 회전
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							-- 전방 직사각형 예고 장판 생성 (길이 25, 너비 8)
							local chargeLength = 25
							local chargeWidth = 8
							local wcf = hrp.CFrame * CFrame.new(0, 0, -chargeLength/2)
							local telegraphPos = wcf.Position

							-- 지형 판독 레이캐스트
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							local rayStart = Vector3.new(telegraphPos.X, hrp.Position.Y, telegraphPos.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end

							local warnLine = Instance.new("Part")
							warnLine.Name = "SamuraiDashTelegraph"
							warnLine.Size = Vector3.new(chargeWidth, 0.4, chargeLength)
							warnLine.CFrame = CFrame.new(telegraphPos.X, floorY, telegraphPos.Z) * (hrp.CFrame.Rotation)
							warnLine.Anchored = true
							warnLine.CanCollide = false
							warnLine.Material = Enum.Material.Neon
							warnLine.Color = Color3.fromRGB(255, 0, 0)
							warnLine.Transparency = 0.8
							warnLine.Parent = workspace

							local ts = game:GetService("TweenService")
							ts:Create(warnLine, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.35}):Play()

							-- 1.0초간 경고 장판 유지
							task.wait(1.0)
							warnLine:Destroy()

							if isAlive then
								-- 돌진 애니메이션
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local dashAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("Samurai_Dash")
									if animator and dashAnim then
										local track = animator:LoadAnimation(dashAnim)
										if track then track:Play() end
									end
								end)

								-- 돌진 사운드
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and (monsterSounds:FindFirstChild("Samurai_SwordSwing") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)

								-- [대쉬 이펙트] 고속 잔상 및 적/흑 참격 기류 트레일
								local peDash = Instance.new("ParticleEmitter")
								peDash.Texture = "rbxasset://textures/particles/smoke_main.dds"
								peDash.Color = ColorSequence.new(Color3.fromRGB(180, 0, 0), Color3.fromRGB(15, 15, 15))
								peDash.Size = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 3.5),
									NumberSequenceKeypoint.new(1, 0)
								})
								peDash.Transparency = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 0.2),
									NumberSequenceKeypoint.new(0.8, 0.6),
									NumberSequenceKeypoint.new(1, 1.0)
								})
								peDash.Rate = 250
								peDash.Speed = NumberRange.new(8, 15)
								peDash.SpreadAngle = Vector2.new(15, 15)
								peDash.Lifetime = NumberRange.new(0.3, 0.5)
								peDash.EmissionDirection = Enum.NormalId.Back
								peDash.Parent = hrp

								-- 0.25초 동안 대상 위치로 빠르게 슬라이드 돌진 (Tween)
								local fwd = hrp.CFrame.LookVector
								local targetLand = hrp.Position + fwd * chargeLength
								local slideTime = 0.25
								local slideTween = ts:Create(hrp, TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.lookAt(targetLand, targetLand + fwd)
								})
								slideTween:Play()

								-- 돌진 경로 상 플레이어 타격
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

											if forwardDist > 0 and forwardDist <= chargeLength + 3 and math.abs(rightDist) <= chargeWidth/2 + 1 and math.abs(pRoot.Position.Y - currentHrpPos.Y) < 12 then
												hitPlayers[p.UserId] = true
												dealDamageToHumanoid(phum, 80) -- Iaido Dash Cut: 80 damage

												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", fwd * 1.5) -- 넉백/기절
												end
											end
										end
									end
								end
								if peDash then peDash:Destroy() end
							end
							task.wait(0.5) -- 돌진 후 딜레이

						-- 2. 벚꽃 회오리 광역 참격 (Cherry Blossom Whirlwind Slash): 거리 18 이하, 쿨타임 12.0초
						elseif distToPlayer <= 18 and (now - lastWhirlwindTick >= 12.0) then
							lastWhirlwindTick = now
							humanoid:MoveTo(hrp.Position) -- 정지

							-- 회전 정렬
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							local telegraphRadius = 20
							local hitCenter = hrp.Position

							-- 지형 판독 레이캐스트
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							local rayStart = Vector3.new(hitCenter.X, hrp.Position.Y, hitCenter.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end

							-- 빨간색 원형 예고 장판 생성 (매우 얇은 경고선 형태)
							local warnCircle = Instance.new("Part")
							warnCircle.Name = "SamuraiSpecialTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2)
							warnCircle.CFrame = CFrame.new(hitCenter.X, floorY, hitCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = Color3.fromRGB(255, 0, 0)
							warnCircle.Transparency = 0.8
							warnCircle.Parent = workspace

							local ts = game:GetService("TweenService")
							ts:Create(warnCircle, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()

							-- 1.2초 대기
							task.wait(1.2)
							warnCircle:Destroy()

							if isAlive then
								-- 애니메이션 재생
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local specialAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("Samurai_Special")
									if animator and specialAnim then
										local track = animator:LoadAnimation(specialAnim)
										if track then track:Play() end
									end
								end)

								-- 벚꽃 스페셜 사운드
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and (monsterSounds:FindFirstChild("Samurai_Special") or monsterSounds:FindFirstChild("BlueFlameKnight_Spell") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)

								-- [고도화] 매화낙락(플레이어 스킬)과 동일한 구조 - 판정 반경 전체에 실제 Assets/VFX/Slash
								-- 참격 에셋을 흩뿌리는 방식 - 을 그대로 계승하되, 꽃잎은 완전히 제거하고 검기를
								-- 적/흑으로 물들여 "검기폭풍" 느낌으로 재구성
								local whirlwindModel = Instance.new("Model")
								whirlwindModel.Name = "SamuraiWhirlwind"
								whirlwindModel.Parent = workspace

								-- 고속 회전 적/흑 참격 바람 파티클 (시전자 중심, 배경 소용돌이 역할)
								local peWind = Instance.new("ParticleEmitter")
								peWind.Texture = "rbxasset://textures/particles/smoke_main.dds"
								peWind.Color = ColorSequence.new(Color3.fromRGB(180, 0, 0), Color3.fromRGB(15, 15, 15)) -- 적/흑 칼바람
								peWind.Size = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 3),
									NumberSequenceKeypoint.new(0.5, 6.5),
									NumberSequenceKeypoint.new(1, 0)
								})
								peWind.Transparency = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 0.3),
									NumberSequenceKeypoint.new(0.2, 0.1),
									NumberSequenceKeypoint.new(0.8, 0.4),
									NumberSequenceKeypoint.new(1, 1.0)
								})
								peWind.Rate = 350
								peWind.Speed = NumberRange.new(15, 30)
								peWind.SpreadAngle = Vector2.new(0, 360)
								peWind.Lifetime = NumberRange.new(0.4, 0.7)
								peWind.Rotation = NumberRange.new(0, 360)
								peWind.RotSpeed = NumberRange.new(900, 1400)
								peWind.EmissionDirection = Enum.NormalId.Top
								peWind.Parent = hrp

								-- 흩날리는 적/흑 스파크 (배경 질감 보강)
								local peSpark = Instance.new("ParticleEmitter")
								peSpark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
								peSpark.Color = ColorSequence.new(Color3.fromRGB(220, 0, 0), Color3.fromRGB(20, 20, 20)) -- 적/흑 기운
								peSpark.Size = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 1.6),
									NumberSequenceKeypoint.new(1, 0)
								})
								peSpark.Rate = 150
								peSpark.Speed = NumberRange.new(8, 20)
								peSpark.SpreadAngle = Vector2.new(360, 360)
								peSpark.Lifetime = NumberRange.new(0.6, 1.0)
								peSpark.Parent = hrp

								-- 매화낙락과 동일한 Assets/VFX/Slash 참격 에셋을 판정 반경(telegraphRadius) 전체에
								-- 무작위 위치/시점으로 흩뿌리되, 원본 분홍색 대신 적/흑 절반씩 물들여서 사용
								local slashVfxFolder = ReplicatedStorage:FindFirstChild("Assets")
								slashVfxFolder = slashVfxFolder and slashVfxFolder:FindFirstChild("VFX")
								local slashTemplate = slashVfxFolder and slashVfxFolder:FindFirstChild("Slash")

								local duration = 1.5
								local slashCount = 40

								if slashTemplate then
									for i = 1, slashCount do
										local posTheta = math.random() * math.pi * 2
										local posPhi = math.acos(2 * math.random() - 1)
										local posDir = Vector3.new(math.sin(posPhi) * math.cos(posTheta), math.cos(posPhi) * 0.4, math.sin(posPhi) * math.sin(posTheta))
										local posDist = math.random(2, telegraphRadius)
										local slashPos = hrp.Position + posDir * posDist
										slashPos = Vector3.new(slashPos.X, math.max(slashPos.Y, floorY + 1), slashPos.Z)

										local appearDelay = math.random() * duration

										task.delay(appearDelay, function()
											if not isAlive or not whirlwindModel.Parent then return end

											local slash = slashTemplate:Clone()
											slash.Name = "SamuraiSlashMark"
											slash.Anchored = true
											slash.CanCollide = false
											slash.CanQuery = false
											slash.CanTouch = false
											slash.CastShadow = false

											local scale = math.random(20, 34) / 10
											slash.CFrame = CFrame.new(slashPos)
												* CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
											slash.Parent = whirlwindModel
											Debris:AddItem(slash, 1.0)

											-- 절반은 붉게, 절반은 칠흑으로 물들여 적/흑 대비되는 "검기폭풍" 느낌을 줌
											local bladeColor = (math.random() > 0.5) and Color3.fromRGB(230, 0, 0) or Color3.fromRGB(10, 10, 10)
											local emitters = {}
											for _, desc in ipairs(slash:GetDescendants()) do
												if desc:IsA("ParticleEmitter") then
													desc.Color = ColorSequence.new(bladeColor)
													local nsSeq = {}
													for _, kp in ipairs(desc.Size.Keypoints) do
														table.insert(nsSeq, NumberSequenceKeypoint.new(kp.Time, kp.Value * scale, kp.Envelope * scale))
													end
													desc.Size = NumberSequence.new(nsSeq)
													local spd = math.random(6, 14)
													desc.Speed = NumberRange.new(spd, spd)
													desc.Rate = 0
													table.insert(emitters, desc)
												end
											end

											-- [버그수정] 새로 Clone/Parent한 인스턴스에 같은 프레임에서 바로 :Emit()을 호출하면
											-- 클라이언트에 아직 복제되기 전이라 방출 신호가 씹혀서 슬래시가 안 보이는 현상이
											-- 있었음(지속 방출인 peWind/peSpark만 보이고 일회성 Emit인 슬래시만 안 보였던 원인).
											-- 복제될 시간을 한 프레임 확보한 뒤 Emit.
											task.wait()
											for _, desc in ipairs(emitters) do
												desc:Emit(1)
											end
										end)
									end
								end

								task.delay(duration + 0.6, function()
									if peWind then peWind:Destroy() end
									if peSpark then peSpark:Destroy() end
									if whirlwindModel then whirlwindModel:Destroy() end
								end)

								-- 다단 참격 데미지 판정 (0.3초 간격 총 4회 타격, 각 20 데미지 = 총 80 데미지)
								task.spawn(function()
									for tick = 1, 4 do
										task.wait(0.3)
										if not isAlive then break end

										local currentHrpPos = hrp.Position
										for _, p in ipairs(Players:GetPlayers()) do
											local char = p.Character
											local phum = char and char:FindFirstChild("Humanoid")
											local pRoot = char and char:FindFirstChild("HumanoidRootPart")

											if phum and phum.Health > 0 and pRoot then
												local dist = (Vector3.new(pRoot.Position.X, 0, pRoot.Position.Z) - Vector3.new(currentHrpPos.X, 0, currentHrpPos.Z)).Magnitude
												if dist <= telegraphRadius and math.abs(pRoot.Position.Y - currentHrpPos.Y) < 12 then
													dealDamageToHumanoid(phum, 20)

													local hitPlayer = Players:GetPlayerFromCharacter(char)
													if hitPlayer then
														local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
														local bounceDir = (pRoot.Position - currentHrpPos)
														bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
														NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.9)
													end
												end
											end
										end
									end
								end)
							end
							task.wait(1.5) -- 후딜레이

						-- 3. 기본 참격 평타 (Standard Melee Attack): 사거리 9 이내, 쿨타임 2.0초
						elseif distToPlayer <= 9 and (now - lastAttackTick >= 2.0) then
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position) -- 정지

							-- 회전 정렬
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							local atkRadius = 9
							local hitCenter = hrp.Position + (hrp.CFrame.LookVector * (atkRadius/3))

							-- 지형 판독 레이캐스트
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							local rayStart = Vector3.new(hitCenter.X, hrp.Position.Y, hitCenter.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end

							local warnCircle = Instance.new("Part")
							warnCircle.Name = "SamuraiAtkTelegraph"
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
							ts:Create(warnCircle, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()

							-- 0.8초 대기
							task.wait(0.8)
							warnCircle:Destroy()

							if isAlive then
								-- 애니메이션 재생
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local attackAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("Samurai_Attack")
									if animator and attackAnim then
										local track = animator:LoadAnimation(attackAnim)
										if track then track:Play() end
									end
								end)

								-- 평타 사운드 재생
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and (monsterSounds:FindFirstChild("Samurai_SwordSwing") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)

								task.wait(0.3) -- 베는 연출 대기

								if isAlive then
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											local dXZ = Vector3.new(pRoot.Position.X - hitCenter.X, 0, pRoot.Position.Z - hitCenter.Z).Magnitude
											if dXZ <= atkRadius and math.abs(pRoot.Position.Y - hitCenter.Y) < 12 then
												dealDamageToHumanoid(phum, 50) -- Standard Attack: 50 damage

												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
													local bounceDir = (pRoot.Position - hitCenter)
													bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.8)
												end
											end
										end
									end
								end
							end
							task.wait(0.4)

						-- 4. 추격 상태
						else
							humanoid:MoveTo(targetPlayerPos)
							task.wait(0.3)
						end
					elseif config.mobModelName == "IceKnight" then
						--========================================================================
						-- [IceKnight 전용 FSM 분기]: 얼음 가시 돌진, 빙결 폭풍 광역기, 냉기 참격 평타
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()

						-- Helper function to spawn a beautiful rising ice spike
						local function spawnIceSpike(pos, floorY)
							local spike = Instance.new("Part")
							spike.Name = "IceSpike"
							spike.Size = Vector3.new(2.5, 0.1, 2.5)
							spike.Color = Color3.fromRGB(150, 220, 255)
							spike.Material = Enum.Material.Glass
							spike.Transparency = 0.5
							spike.Anchored = true
							spike.CanCollide = false

							spike.CFrame = CFrame.new(pos.X, floorY, pos.Z) * CFrame.Angles(
								math.rad(math.random(-20, 20)),
								math.rad(math.random(0, 360)),
								math.rad(math.random(-20, 20))
							)
							spike.Parent = workspace

							local targetHeight = math.random(5, 10)
							local targetSize = Vector3.new(1.8, targetHeight, 1.8)
							local targetCF = spike.CFrame * CFrame.new(0, targetHeight/2, 0)

							local ts = game:GetService("TweenService")
							ts:Create(spike, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Size = targetSize,
								CFrame = targetCF,
								Transparency = 0.2
							}):Play()

							task.spawn(function()
								task.wait(0.8)
								local fade = ts:Create(spike, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 1,
									Size = Vector3.new(0.01, 0.01, 0.01)
								})
								fade:Play()
								fade.Completed:Wait()
								spike:Destroy()
							end)
						end

						-- 1. 얼음 가시 돌진 (Ice Spike Dash): 거리 15 ~ 30, 쿨타임 9.0초
						if distToPlayer >= 15 and distToPlayer <= 30 and (now - lastThrustTick >= 9.0) then
							lastThrustTick = now
							humanoid:MoveTo(hrp.Position) -- 이동 정지

							-- 타겟 방향으로 회전
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							-- 전방 직사각형 예고 장판 생성 (길이 25, 너비 8)
							local chargeLength = 25
							local chargeWidth = 8
							local wcf = hrp.CFrame * CFrame.new(0, 0, -chargeLength/2)
							local telegraphPos = wcf.Position

							-- 지형 판독 레이캐스트
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							rayParams.RespectCanCollide = true
							local rayStart = Vector3.new(telegraphPos.X, hrp.Position.Y, telegraphPos.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end

							local warnLine = Instance.new("Part")
							warnLine.Name = "IceKnightDashTelegraph"
							warnLine.Size = Vector3.new(chargeWidth, 0.4, chargeLength)
							warnLine.CFrame = CFrame.new(telegraphPos.X, floorY, telegraphPos.Z) * (hrp.CFrame.Rotation)
							warnLine.Anchored = true
							warnLine.CanCollide = false
							warnLine.Material = Enum.Material.Neon
							warnLine.Color = Color3.fromRGB(0, 160, 255) -- 청록색/얼음색 장판
							warnLine.Transparency = 0.8
							warnLine.Parent = workspace

							local ts = game:GetService("TweenService")
							ts:Create(warnLine, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.35}):Play()

							-- 1.0초간 경고 장판 유지
							task.wait(1.0)
							warnLine:Destroy()

							if isAlive then
								-- 돌진 애니메이션
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local dashAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("IceKnight_Dash")
									if animator and dashAnim then
										local track = animator:LoadAnimation(dashAnim)
										if track then track:Play() end
									end
								end)

								-- 돌진 사운드
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and (monsterSounds:FindFirstChild("IceKnight_Dash") or monsterSounds:FindFirstChild("IceKnight_SwordSwing") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)

								-- 0.25초 동안 대상 위치로 빠르게 슬라이드 돌진 (Tween)
								local fwd = hrp.CFrame.LookVector
								local targetLand = hrp.Position + fwd * chargeLength
								local slideTime = 0.25
								local slideTween = ts:Create(hrp, TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.lookAt(targetLand, targetLand + fwd)
								})
								slideTween:Play()

								-- 돌진 경로 상 플레이어 타격 및 얼음 가시 스폰
								local elapsed = 0
								local hitPlayers = {}
								local startPos = hrp.Position
								local lastSpikeTime = 0

								while elapsed < slideTime and isAlive do
									local dt = task.wait(0.03)
									elapsed = elapsed + dt

									-- 실시간 가시 생성
									if elapsed - lastSpikeTime >= 0.05 then
										lastSpikeTime = elapsed
										spawnIceSpike(hrp.Position, floorY)
									end

									local currentHrpPos = hrp.Position
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")

										if phum and phum.Health > 0 and pRoot and not hitPlayers[p.UserId] then
											local pDir = pRoot.Position - startPos
											local forwardDist = fwd:Dot(pDir)
											local rightDist = hrp.CFrame.RightVector:Dot(pDir)

											if forwardDist > 0 and forwardDist <= chargeLength + 3 and math.abs(rightDist) <= chargeWidth/2 + 1 and math.abs(pRoot.Position.Y - currentHrpPos.Y) < 12 then
												hitPlayers[p.UserId] = true
												dealDamageToHumanoid(phum, 90) -- 90 Damage

												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", fwd * 0.5) -- 1.5초 기절(빙결)
												end
											end
										end
									end
								end
							end
							task.wait(0.5) -- 돌진 후 딜레이

						-- 2. 빙결 폭풍 광역기 (Glacial Nova): 거리 15 이하, 쿨타임 14.0초
						elseif distToPlayer <= 15 and (now - lastWhirlwindTick >= 14.0) then
							lastWhirlwindTick = now
							humanoid:MoveTo(hrp.Position) -- 정지

							-- 회전 정렬
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							local telegraphRadius = 16
							local hitCenter = hrp.Position

							-- 지형 판독 레이캐스트
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							rayParams.RespectCanCollide = true
							local rayStart = Vector3.new(hitCenter.X, hrp.Position.Y, hitCenter.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end

							-- 하늘색 원형 예고 장판 생성
							local warnCircle = Instance.new("Part")
							warnCircle.Name = "IceKnightSpecialTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2)
							warnCircle.CFrame = CFrame.new(hitCenter.X, floorY, hitCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = Color3.fromRGB(0, 160, 255)
							warnCircle.Transparency = 0.8
							warnCircle.Parent = workspace

							local ts = game:GetService("TweenService")
							ts:Create(warnCircle, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()

							-- 1.2초 대기
							task.wait(1.2)
							warnCircle:Destroy()

							if isAlive then
								-- 애니메이션 재생
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local specialAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("IceKnight_Special")
									if animator and specialAnim then
										local track = animator:LoadAnimation(specialAnim)
										if track then track:Play() end
									end
								end)

								-- 빙결 마법 사운드 (디폴트)
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and (monsterSounds:FindFirstChild("IceKnight_Special") or monsterSounds:FindFirstChild("BlueFlameKnight_Spell") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)

								-- 주변 얼음 폭풍 가시 연타 스폰
								task.spawn(function()
									-- 1단계: 가까운 원 (8개)
									for i = 1, 8 do
										local angle = (i / 8) * math.pi * 2
										local offset = Vector3.new(math.cos(angle) * 7, 0, math.sin(angle) * 7)
										spawnIceSpike(hitCenter + offset, floorY)
										task.wait(0.04)
									end
									-- 2단계: 먼 원 (12개)
									for i = 1, 12 do
										local angle = (i / 12) * math.pi * 2
										local offset = Vector3.new(math.cos(angle) * 13, 0, math.sin(angle) * 13)
										spawnIceSpike(hitCenter + offset, floorY)
										task.wait(0.03)
									end
								end)

								-- 광역 타격 데미지 판정
								local currentHrpPos = hrp.Position
								for _, p in ipairs(Players:GetPlayers()) do
									local char = p.Character
									local phum = char and char:FindFirstChild("Humanoid")
									local pRoot = char and char:FindFirstChild("HumanoidRootPart")

									if phum and phum.Health > 0 and pRoot then
										local dist = (Vector3.new(pRoot.Position.X, 0, pRoot.Position.Z) - Vector3.new(currentHrpPos.X, 0, currentHrpPos.Z)).Magnitude
										if dist <= telegraphRadius and math.abs(pRoot.Position.Y - currentHrpPos.Y) < 12 then
											dealDamageToHumanoid(phum, 120) -- 120 Damage

											local hitPlayer = Players:GetPlayerFromCharacter(char)
											if hitPlayer then
												local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
												local bounceDir = (pRoot.Position - currentHrpPos)
												bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
												NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.5) -- 1.5초 기절(빙결)
											end
										end
									end
								end
							end
							task.wait(1.5) -- 후딜레이

						-- 3. 냉기 참격 평타 (Frost Slash): 사거리 8 이내, 쿨타임 2.2초
						elseif distToPlayer <= 8 and (now - lastAttackTick >= 2.2) then
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position) -- 정지

							-- 회전 정렬
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							local atkRadius = 8
							local hitCenter = hrp.Position + (hrp.CFrame.LookVector * (atkRadius/3))

							-- 지형 판독 레이캐스트
							local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							local ignoreList = {model}
							for _, p in ipairs(Players:GetPlayers()) do
								if p.Character then table.insert(ignoreList, p.Character) end
							end
							rayParams.FilterDescendantsInstances = ignoreList
							rayParams.RespectCanCollide = true
							local rayStart = Vector3.new(hitCenter.X, hrp.Position.Y, hitCenter.Z)
							local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
							if rayResult then
								floorY = rayResult.Position.Y + 0.2
							end

							local warnCircle = Instance.new("Part")
							warnCircle.Name = "IceKnightAtkTelegraph"
							warnCircle.Shape = Enum.PartType.Cylinder
							warnCircle.Size = Vector3.new(0.4, atkRadius * 2, atkRadius * 2)
							warnCircle.CFrame = CFrame.new(hitCenter.X, floorY, hitCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
							warnCircle.Anchored = true
							warnCircle.CanCollide = false
							warnCircle.Material = Enum.Material.Neon
							warnCircle.Color = Color3.fromRGB(0, 160, 255)
							warnCircle.Transparency = 0.8
							warnCircle.Parent = workspace

							local ts = game:GetService("TweenService")
							ts:Create(warnCircle, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.4}):Play()

							-- 0.8초 대기
							task.wait(0.8)
							warnCircle:Destroy()

							if isAlive then
								-- 애니메이션 재생
								pcall(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
									local attackAnim = anims and anims:FindFirstChild("Monster") and anims.Monster:FindFirstChild("IceKnight_Attack")
									if animator and attackAnim then
										local track = animator:LoadAnimation(attackAnim)
										if track then track:Play() end
									end
								end)

								-- 평타 사운드 재생 (디폴트)
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and (monsterSounds:FindFirstChild("IceKnight_SwordSwing") or monsterSounds:FindFirstChild("GhostKnight_SwordSwing"))
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)

								task.wait(0.3) -- 베는 연출 대기

								if isAlive then
									-- 짧은 냉기 이펙트 (한 번 뿜어짐)
									local peSlash = Instance.new("ParticleEmitter")
									peSlash.Texture = "rbxasset://textures/particles/smoke_main.dds"
									peSlash.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255))
									peSlash.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 1),
										NumberSequenceKeypoint.new(1, 4)
									})
									peSlash.Rate = 50
									peSlash.Lifetime = NumberRange.new(0.3, 0.5)
									peSlash.Speed = NumberRange.new(10, 20)
									peSlash.Parent = hrp
									game.Debris:AddItem(peSlash, 0.4)

									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")
										if phum and phum.Health > 0 and pRoot then
											local dXZ = Vector3.new(pRoot.Position.X - hitCenter.X, 0, pRoot.Position.Z - hitCenter.Z).Magnitude
											if dXZ <= atkRadius and math.abs(pRoot.Position.Y - hitCenter.Y) < 12 then
												dealDamageToHumanoid(phum, 60) -- 60 Damage

												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													-- 임시 냉기 감속 (3초간 WalkSpeed 8로 디버프)
													task.spawn(pcall, function()
														local originalSpeed = phum.WalkSpeed
														phum.WalkSpeed = 8
														task.wait(3.0)
														if phum and phum.Parent then
															phum.WalkSpeed = originalSpeed
														end
													end)

													local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
													local bounceDir = (pRoot.Position - hitCenter)
													bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.4)
												end
											end
										end
									end
								end
							end
							task.wait(0.4)

						-- 4. 추격 상태
						else
							humanoid:MoveTo(targetPlayerPos)
							task.wait(0.3)
						end
					elseif config.mobModelName == "IceDragon" then
						--========================================================================
						-- [IceDragon 전용 FSM 분기]: 빙결 브레스, 얼음 가시 낙하(광역), 냉기 포지셔닝
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()

						local breathRange = 35
						local stormRange = 25
						local attackCooldown = config.attackCooldown or 2.2

						local ts = game:GetService("TweenService")

						-- 고품질 다중 유리 얼음 가시 모델 생성 함수
						local function spawnIceDragonSpike(pos, floorY)
							local spikeModel = Instance.new("Model")
							spikeModel.Name = "IceDragonSpikeModel"

							-- A. 메인 날카로운 얼음 가시 (WedgePart 사용)
							local mainSpire = Instance.new("WedgePart")
							mainSpire.Name = "MainSpire"
							mainSpire.Size = Vector3.new(2.5, 0.1, 2.5)
							mainSpire.Color = Color3.fromRGB(135, 206, 250) -- Sky Blue
							mainSpire.Material = Enum.Material.Glass
							mainSpire.CanCollide = false
							mainSpire.Anchored = true
							mainSpire.Parent = spikeModel

							-- B. 보조 사선 가시 1
							local sideShard1 = Instance.new("WedgePart")
							sideShard1.Name = "SideShard1"
							sideShard1.Size = Vector3.new(1.5, 0.1, 1.5)
							sideShard1.Color = Color3.fromRGB(175, 238, 238) -- Pale Turquoise
							sideShard1.Material = Enum.Material.Glass
							sideShard1.CanCollide = false
							sideShard1.Anchored = true
							sideShard1.Parent = spikeModel

							-- C. 보조 사선 가시 2
							local sideShard2 = Instance.new("WedgePart")
							sideShard2.Name = "SideShard2"
							sideShard2.Size = Vector3.new(1.2, 0.1, 1.2)
							sideShard2.Color = Color3.fromRGB(0, 206, 209) -- Dark Turquoise
							sideShard2.Material = Enum.Material.Glass
							sideShard2.CanCollide = false
							sideShard2.Anchored = true
							sideShard2.Parent = spikeModel

							local rotationAngles = CFrame.Angles(
								math.rad(math.random(-15, 15)),
								math.rad(math.random(0, 360)),
								math.rad(math.random(-15, 15))
							)

							local function updateSpikeCF(centerPos, verticalHeight)
								local baseCF = CFrame.new(centerPos.X, floorY - 6 + verticalHeight/2, centerPos.Z) * rotationAngles
								mainSpire.Size = Vector3.new(mainSpire.Size.X, verticalHeight, mainSpire.Size.Z)
								mainSpire.CFrame = baseCF

								sideShard1.Size = Vector3.new(sideShard1.Size.X, verticalHeight * 0.6, sideShard1.Size.Z)
								sideShard1.CFrame = baseCF * CFrame.new(-0.8, -verticalHeight * 0.1, 0.6) * CFrame.Angles(math.rad(15), 0, math.rad(15))

								sideShard2.Size = Vector3.new(sideShard2.Size.X, verticalHeight * 0.4, sideShard2.Size.Z)
								sideShard2.CFrame = baseCF * CFrame.new(0.8, -verticalHeight * 0.2, -0.6) * CFrame.Angles(math.rad(-15), 0, math.rad(-15))
							end

							updateSpikeCF(pos, 0.1)
							spikeModel.Parent = workspace

							local targetHeight = math.random(8, 14)

							-- 지면 위로 강력하게 솟구침
							local popStartTime = os.clock()
							local popDuration = 0.2
							while os.clock() - popStartTime < popDuration do
								local alpha = (os.clock() - popStartTime) / popDuration
								local easeAlpha = 1 - (1 - alpha)^3
								local currentHeight = 0.1 + (targetHeight - 0.1) * easeAlpha
								updateSpikeCF(pos, currentHeight)
								task.wait()
							end
							updateSpikeCF(pos, targetHeight)

							-- 일정 대기 후 스무스하게 수축하며 투명하게 제거
							task.spawn(function()
								task.wait(1.2)
								local fadeStartTime = os.clock()
								local fadeDuration = 0.4
								while os.clock() - fadeStartTime < fadeDuration do
									local alpha = (os.clock() - fadeStartTime) / fadeDuration
									local currentHeight = targetHeight * (1 - alpha)
									local transparency = 0.2 + 0.8 * alpha
									for _, child in ipairs(spikeModel:GetChildren()) do
										if child:IsA("BasePart") then
											child.Transparency = transparency
										end
									end
									updateSpikeCF(pos, math.max(0.1, currentHeight))
									task.wait()
								end
								spikeModel:Destroy()
							end)
						end

						-- [통합 쿨다운 판단 분기]: 스킬 사거리 이내이며 2.2초 쿨타임 충족 시
						if distToPlayer <= breathRange and (now - lastAttackTick >= attackCooldown) then
							-- 즉시 쿨타임 차단하여 중복 시전 방지 (최종 타격 종료 후 실시간으로 os.clock() 갱신하여 2.2초 갭 보정 예정)
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position) -- 정지

							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end

							-- 타겟이 25 스터드 이내인 경우 50% 확률로 빙결 낙하(스톰), 아니면 빙결 브레스
							local useStorm = false
							if distToPlayer <= stormRange then
								useStorm = (math.random() > 0.5)
							end

							if useStorm then
								--========================================================================
								-- 1. 빙결 낙하 (Ice Storm) 시전
								--========================================================================
								local targetFloorPos = targetPlayerPos
								local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
								local rayParams = RaycastParams.new()
								rayParams.FilterType = Enum.RaycastFilterType.Exclude
								local ignoreList = {model, targetPlayer}
								rayParams.FilterDescendantsInstances = ignoreList
								local rayResult = workspace:Raycast(targetFloorPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
								if rayResult then
									targetFloorPos = rayResult.Position
									floorY = rayResult.Position.Y + 0.2
								end

								local telegraphRadius = 14
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "IceDragonStormTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2)
								warnCircle.CFrame = CFrame.new(targetFloorPos.X, floorY, targetFloorPos.Z) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(30, 144, 255) -- 로얄 블루 네온
								warnCircle.Transparency = 0.8
								warnCircle.Parent = workspace

								ts:Create(warnCircle, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 0.4,
									Color = Color3.fromRGB(175, 238, 238)
								}):Play()

								task.wait(0.8)
								warnCircle:Destroy()

								if isAlive then
									pcall(function()
										local animator = humanoid:FindFirstChildOfClass("Animator")
										local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
										local stormAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("IceDragon_Storm") or anims.Monster:FindFirstChild("IceDragon_Special"))
										if animator and stormAnim then
											local track = animator:LoadAnimation(stormAnim)
											if track then track:Play() end
										end
									end)

									pcall(function()
										local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = sounds and sounds:FindFirstChild("Monster")
										local sound = monsterSounds and (monsterSounds:FindFirstChild("IceDragon_Storm") or monsterSounds:FindFirstChild("IceDragon_Breath"))
										if sound then
											local sfx = sound:Clone()
											sfx.Parent = hrp
											sfx:Play()
											game.Debris:AddItem(sfx, 3)
										end
									end)

									-- 하늘에서 떨어지는 거대한 네온 얼음 송곳 3개 소환
									task.spawn(function()
										for i = 1, 3 do
											if not isAlive then break end
											local offset = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
											local dropCenter = targetFloorPos + offset

											-- 정확한 지면 Y 구하기
											local stepFloorY = floorY
											local rayResultDrop = workspace:Raycast(dropCenter + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
											if rayResultDrop then
												stepFloorY = rayResultDrop.Position.Y
											end

											-- 입체감 있는 거대 고드름 모델 (Wedge 조합)
											local shardModel = Instance.new("Model")
											shardModel.Name = "GiantIcicle"

											local shardPart = Instance.new("WedgePart")
											shardPart.Size = Vector3.new(3.5, 10, 3.5)
											shardPart.Color = Color3.fromRGB(175, 238, 238) -- 연한 하늘색
											shardPart.Material = Enum.Material.Glass
											shardPart.CanCollide = false
											shardPart.Anchored = true
											shardPart.Parent = shardModel

											local shardCore = Instance.new("Part")
											shardCore.Size = Vector3.new(1.8, 8, 1.8)
											shardCore.Color = Color3.fromRGB(0, 206, 209)
											shardCore.Material = Enum.Material.Neon
											shardCore.CanCollide = false
											shardCore.Anchored = true
											shardCore.Parent = shardModel

											local startPos = dropCenter + Vector3.new(0, 45, 0)
											local dropAngle = CFrame.Angles(math.rad(180 + math.random(-10, 10)), math.rad(math.random(0, 360)), 0)

											local function updateShardCF(currentCF)
												shardPart.CFrame = currentCF
												shardCore.CFrame = currentCF * CFrame.new(0, -1, 0)
											end

											updateShardCF(CFrame.new(startPos) * dropAngle)
											shardModel.Parent = workspace

											-- 낙하 트윈
											local dropStartTime = os.clock()
											local dropDuration = 0.3
											while os.clock() - dropStartTime < dropDuration do
												local progress = (os.clock() - dropStartTime) / dropDuration
												local currentPos = startPos:Lerp(dropCenter, progress)
												updateShardCF(CFrame.new(currentPos) * dropAngle)
												task.wait()
											end
											updateShardCF(CFrame.new(dropCenter) * dropAngle)

											shardModel:Destroy()

											-- 지면 서리 팽창 링 생성
											local frostRing = Instance.new("Part")
											frostRing.Shape = Enum.PartType.Cylinder
											frostRing.Size = Vector3.new(0.2, 2, 2)
											frostRing.Color = Color3.fromRGB(0, 206, 209)
											frostRing.Material = Enum.Material.Neon
											frostRing.Transparency = 0.3
											frostRing.CanCollide = false
											frostRing.Anchored = true
											frostRing.CFrame = CFrame.new(dropCenter.X, stepFloorY + 0.1, dropCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
											frostRing.Parent = workspace

											ts:Create(frostRing, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
												Size = Vector3.new(0.2, 18, 18),
												Transparency = 1
											}):Play()
											game.Debris:AddItem(frostRing, 0.45)

											-- 쾅! 사운드 및 가시 분출
											pcall(function()
												local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
												local monsterSounds = sounds and sounds:FindFirstChild("Monster")
												local hitSound = monsterSounds and (monsterSounds:FindFirstChild("BigGolem_Smash") or monsterSounds:FindFirstChild("Stump_Magic"))
												if hitSound then
													local sfx = hitSound:Clone()
													sfx.Parent = workspace
													sfx.Position = dropCenter
													sfx.Volume = 1.3
													sfx.PlaybackSpeed = 1.4
													sfx:Play()
													game.Debris:AddItem(sfx, 3)
												end
											end)

											spawnIceDragonSpike(dropCenter, stepFloorY)
											task.wait(0.2)
										end
									end)

									-- 타격 판정
									task.wait(0.45)
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")

										if phum and phum.Health > 0 and pRoot then
											local dist = (Vector3.new(pRoot.Position.X, 0, pRoot.Position.Z) - Vector3.new(targetFloorPos.X, 0, targetFloorPos.Z)).Magnitude
											if dist <= telegraphRadius and math.abs(pRoot.Position.Y - targetFloorPos.Y) < 15 then
												dealDamageToHumanoid(phum, 80) -- 폭풍 피해 80

												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
													local bounceDir = (pRoot.Position - targetFloorPos)
													bounceDir = Vector3.new(bounceDir.X, 0.5, bounceDir.Z).Unit
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.4)
												end
											end
										end
									end
								end
								task.wait(0.2)
							else
								--========================================================================
								-- 2. 빙결 브레스 (Ice Breath) 시전
								--========================================================================
								local chargeLength = 32
								local chargeWidth = 12
								local wcf = hrp.CFrame * CFrame.new(0, 0, -chargeLength/2)
								local telegraphPos = wcf.Position

								local floorY = hrp.Position.Y - humanoid.HipHeight - (hrp.Size.Y / 2) + 0.2
								local rayParams = RaycastParams.new()
								rayParams.FilterType = Enum.RaycastFilterType.Exclude
								local ignoreList = {model}
								for _, p in ipairs(Players:GetPlayers()) do
									if p.Character then table.insert(ignoreList, p.Character) end
								end
								rayParams.FilterDescendantsInstances = ignoreList
								rayParams.RespectCanCollide = true
								local rayStart = Vector3.new(telegraphPos.X, hrp.Position.Y, telegraphPos.Z)
								local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -30, 0), rayParams)
								if rayResult then
									floorY = rayResult.Position.Y + 0.2
								end

								-- 강력한 네온 가시성 경고 장판 생성
								local warnLine = Instance.new("Part")
								warnLine.Name = "IceDragonBreathTelegraph"
								warnLine.Size = Vector3.new(chargeWidth, 0.4, chargeLength)
								warnLine.CFrame = CFrame.new(telegraphPos.X, floorY, telegraphPos.Z) * (hrp.CFrame.Rotation)
								warnLine.Anchored = true
								warnLine.CanCollide = false
								warnLine.Material = Enum.Material.Neon
								warnLine.Color = Color3.fromRGB(0, 206, 209) -- 청록빛 네온
								warnLine.Transparency = 0.85
								warnLine.Parent = workspace

								ts:Create(warnLine, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
									Transparency = 0.35,
									Color = Color3.fromRGB(175, 238, 238)
								}):Play()

								task.wait(1.0)
								warnLine:Destroy()

								if isAlive then
									pcall(function()
										local animator = humanoid:FindFirstChildOfClass("Animator")
										local anims = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Animations")
										local breathAnim = anims and anims:FindFirstChild("Monster") and (anims.Monster:FindFirstChild("IceDragon_Breath") or anims.Monster:FindFirstChild("IceDragon_Attack"))
										if animator and breathAnim then
											local track = animator:LoadAnimation(breathAnim)
											if track then track:Play() end
										end
									end)

									pcall(function()
										local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = sounds and sounds:FindFirstChild("Monster")
										local sound = monsterSounds and (monsterSounds:FindFirstChild("IceDragon_Breath") or monsterSounds:FindFirstChild("BlueFlameKnight_Spell"))
										if sound then
											local sfx = sound:Clone()
											sfx.Parent = hrp
											sfx:Play()
											game.Debris:AddItem(sfx, 3.5)
										end
									end)

									-- 극적 효과: 네온 빙결 빔 실린더 생성 및 굵기 성장 트윈
									local headPart = model:FindFirstChild("Head") or hrp
									local startBeamPos = headPart.Position
									local endBeamPos = hrp.Position + hrp.CFrame.LookVector * chargeLength

									local beamModel = Instance.new("Model")
									beamModel.Name = "IceDragonBreathBeamModel"

									local beamCore = Instance.new("Part")
									beamCore.Shape = Enum.PartType.Cylinder
									beamCore.Material = Enum.Material.Neon
									beamCore.Color = Color3.fromRGB(175, 238, 238) -- 연한 백청색
									beamCore.CanCollide = false
									beamCore.Anchored = true
									beamCore.Parent = beamModel

									local beamAura = Instance.new("Part")
									beamAura.Shape = Enum.PartType.Cylinder
									beamAura.Material = Enum.Material.Glass
									beamAura.Color = Color3.fromRGB(0, 206, 209) -- 청록색 반투명 유리 아우라
									beamAura.CanCollide = false
									beamAura.Anchored = true
									beamAura.Transparency = 0.4
									beamAura.Parent = beamModel

									local function updateBeamVisual(p1, p2, width)
										local distance = (p1 - p2).Magnitude
										beamCore.Size = Vector3.new(distance, width, width)
										beamCore.CFrame = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -distance/2) * CFrame.Angles(0, math.rad(90), 0)

										beamAura.Size = Vector3.new(distance, width * 1.6, width * 1.6)
										beamAura.CFrame = beamCore.CFrame
									end

									beamModel.Parent = workspace

									-- 파티클 분사 병행
									local peBreath = Instance.new("ParticleEmitter")
									peBreath.Texture = "rbxasset://textures/particles/smoke_main.dds"
									peBreath.Color = ColorSequence.new(Color3.fromRGB(175, 238, 238), Color3.fromRGB(255, 255, 255))
									peBreath.Size = NumberSequence.new({
										NumberSequenceKeypoint.new(0, 2.0),
										NumberSequenceKeypoint.new(1, 8.0)
									})
									peBreath.Rate = 150
									peBreath.Lifetime = NumberRange.new(0.6, 0.9)
									peBreath.Speed = NumberRange.new(30, 45)
									peBreath.SpreadAngle = Vector2.new(20, 20)
									peBreath.EmissionDirection = Enum.NormalId.Front
									peBreath.Parent = headPart
									game.Debris:AddItem(peBreath, 0.8)

									-- 빔 성장 및 경로 얼음 가시 폭발 동시 실행
									task.spawn(function()
										local stepCount = 6
										for i = 1, stepCount do
											if not isAlive then break end
											local stepPos = hrp.Position + hrp.CFrame.LookVector * ((chargeLength / stepCount) * i)
											local stepFloorY = floorY
											local rayResult = workspace:Raycast(stepPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
											if rayResult then
												stepFloorY = rayResult.Position.Y
											end
											spawnIceDragonSpike(stepPos, stepFloorY)

											-- 발동 지점에 작은 얼음 폭발 흔적
											pcall(function()
												local exp = Instance.new("Explosion")
												exp.BlastRadius = 6
												exp.BlastPressure = 0
												exp.Position = Vector3.new(stepPos.X, stepFloorY, stepPos.Z)
												exp.ExplosionType = Enum.ExplosionType.NoCraters
												exp.Visible = false
												exp.Parent = workspace
											end)

											task.wait(0.08)
										end
									end)

									-- 0.6초간 브레스 빔 두께 증가 및 페이드 아웃 트윈
									local beamStartTime = os.clock()
									local beamDuration = 0.6
									while os.clock() - beamStartTime < beamDuration and isAlive do
										local progress = (os.clock() - beamStartTime) / beamDuration
										local currentWidth = 1.5 + (chargeWidth - 1.5) * progress

										if progress > 0.5 then
											beamCore.Transparency = (progress - 0.5) * 2
											beamAura.Transparency = 0.4 + 0.6 * ((progress - 0.5) * 2)
										end

										updateBeamVisual(headPart.Position, hrp.Position + hrp.CFrame.LookVector * chargeLength, currentWidth)
										task.wait()
									end

									beamModel:Destroy()

									-- 데미지 계산 및 슬로우/스턴 적용
									local fwd = hrp.CFrame.LookVector
									local currentHrpPos = hrp.Position
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phum = char and char:FindFirstChild("Humanoid")
										local pRoot = char and char:FindFirstChild("HumanoidRootPart")

										if phum and phum.Health > 0 and pRoot then
											local pDir = pRoot.Position - currentHrpPos
											local forwardDist = fwd:Dot(pDir)
											local rightDist = hrp.CFrame.RightVector:Dot(pDir)

											if forwardDist > 0 and forwardDist <= chargeLength + 4 and math.abs(rightDist) <= chargeWidth/2 + 2 and math.abs(pRoot.Position.Y - currentHrpPos.Y) < 15 then
												dealDamageToHumanoid(phum, 70) -- 브레스 피해 70

												local hitPlayer = Players:GetPlayerFromCharacter(char)
												if hitPlayer then
													task.spawn(pcall, function()
														local originalSpeed = phum.WalkSpeed
														phum.WalkSpeed = 6 -- 강력 감속
														task.wait(3.0)
														if phum and phum.Parent then
															phum.WalkSpeed = originalSpeed
														end
													end)

													local NetController = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", fwd * 0.4)
												end
											end
										end
									end
								end
								task.wait(0.2)
							end

							-- 공격 시전 종료 시점에 lastAttackTick을 다시 갱신하여 완전히 대기 타임(2.2초) 보정!
							lastAttackTick = os.clock()
						-- 3. 추격 상태 및 호버링 유지
						else
							if distToPlayer > 25 then
								humanoid:MoveTo(targetPlayerPos)
							else
								humanoid:MoveTo(hrp.Position) -- 제자리 호버링 유지
							end

							-- 플레이어 정면 주시
							local lookDir = (phrp.Position - hrp.Position)
							lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
							if lookDir.Magnitude > 0.1 then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
							end
							task.wait(0.25)
						end
					elseif config.mobModelName == "SmallGolem" then
						--========================================================================
						-- [SmallGolem 전용 FSM 분기]: 느릿하지만 묵직한 바위 강타 광역 공격
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()

						local G_ATTACK_RANGE = 18
						local attackCooldown = config.attackCooldown or 2.5
						local telegraphDuration = 1.2

						if distToPlayer <= G_ATTACK_RANGE then
							-- 사거리 내라면 정지하고 즉시 공격 준비
							humanoid:MoveTo(hrp.Position) -- 멈춤

							if now - lastAttackTick >= attackCooldown then
								lastAttackTick = now

								-- 플레이어 정면 주시
								local lookDir = (phrp.Position - hrp.Position)
								lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
								if lookDir.Magnitude > 0.1 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
								end

								-- 몬스터 공격 애니메이션 재생 시도
								task.spawn(function()
									local animator = humanoid:FindFirstChildOfClass("Animator")
									if animator then
										local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
										local animsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
										local monsterAnims = animsFolder and animsFolder:FindFirstChild("Monster")
										local attackAnim = monsterAnims and (monsterAnims:FindFirstChild("SmallGolem_Attack") or monsterAnims:FindFirstChild("Golem_Attack") or monsterAnims:FindFirstChild("Slime_Attack"))

										if attackAnim then
											local success, attackTrack = pcall(function() return animator:LoadAnimation(attackAnim) end)
											if success and attackTrack then
												attackTrack.Priority = Enum.AnimationPriority.Action
												attackTrack:Play()
											end
										end
									end
								end)

								-- 전방 찌르기/강타 전조 장판 생성 (네온 레드 원반)
								task.spawn(function()
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "GolemAtkTelegraph"
									warnCircle.Shape = Enum.PartType.Cylinder
									warnCircle.Size = Vector3.new(0.4, G_ATTACK_RANGE * 2, G_ATTACK_RANGE * 2)

									-- 레이캐스트로 몬스터 바로 아래 실제 바닥 고도 측정
									local rayParams = RaycastParams.new()
									rayParams.FilterType = Enum.RaycastFilterType.Exclude
									rayParams.FilterDescendantsInstances = {model}
									local rayResult = workspace:Raycast(currentPos, Vector3.new(0, -50, 0), rayParams)

									local floorPos
									if rayResult then
										floorPos = rayResult.Position + Vector3.new(0, 0.1, 0)
									else
										local groundOffset = humanoid.HipHeight + (hrp.Size.Y / 2)
										floorPos = currentPos - Vector3.new(0, groundOffset - 0.2, 0)
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

									task.wait(telegraphDuration)
									warnCircle:Destroy()

									-- 최종 판정 및 데미지/이펙트 적용
									if isAlive and targetPlayer and targetPlayer.Parent and targetPlayer:FindFirstChild("HumanoidRootPart") then
										local currentPhrp = targetPlayer.HumanoidRootPart
										local currentDist = (hrp.Position - currentPhrp.Position).Magnitude

										-- 강타 이펙트는 무조건 시전됨 (바닥 파편 등 연출)
										local smashPos = currentPos + hrp.CFrame.LookVector * (G_ATTACK_RANGE / 2)
										local smashRayResult = workspace:Raycast(smashPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
										local finalSmashPos = smashRayResult and smashRayResult.Position or Vector3.new(smashPos.X, floorPos.Y, smashPos.Z)
										playRockSmashEffect(finalSmashPos, G_ATTACK_RANGE * 0.8, "SmallGolem_Attack")

										if currentDist <= G_ATTACK_RANGE + 2 then
											local dmg = config.baseDamage or 22
											local currentPhum = targetPlayer:FindFirstChild("Humanoid")
											if currentPhum and currentPhum.Health > 0 then
												dealDamageToHumanoid(currentPhum, dmg)

												-- 넉백 기절 적용
												local bounceDir = (currentPhrp.Position - hrp.Position)
												bounceDir = Vector3.new(bounceDir.X, 0.3, bounceDir.Z).Unit
												local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
												if hitPlayer then
													local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
													local NetController = require(Controllers:WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 1.2)
												end

												-- 데미지 피격 플래시
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
								end)

								task.wait(1.5) -- 공격 후 딜레이
							end
						else
							humanoid:MoveTo(targetPlayerPos)
							task.wait(0.2)
						end
					elseif config.mobModelName == "Slime" then
						--========================================================================
						-- [Slime 전용 FSM 분기]: 일반 공격(연두빛 몸통 박치기)
						--========================================================================
						if minDist <= ATTACK_RANGE or (minDist <= 25 and os.clock() - lastAttackTick >= (config.attackCooldown or 2.5) + 1.0) then
							humanoid:MoveTo(hrp.Position) -- 멈춤
							local now = os.clock()
							local cooldown = config.attackCooldown or 2.5

							if now - lastAttackTick >= cooldown then
								lastAttackTick = now

								-- [일반 공격] 연두빛 몸통 박치기 (히트박스 경고 범위 및 실제 판정 100% 일치화)
								local targetHrpPos = phrp.Position
								local lungeDir = (targetHrpPos - hrp.Position)
								lungeDir = Vector3.new(lungeDir.X, 0, lungeDir.Z).Unit

								-- 돌진할 대상 지점 및 경고 장판 반경 정의
								local lungeTargetPos = hrp.Position + lungeDir * 6
								local telegraphRadius = 7
								local telegraphDuration = 0.7

								-- 1. 연두색 팽창 링 전조 생성
								task.spawn(function()
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "SlimeAtkTelegraph"
									warnCircle.Shape = Enum.PartType.Cylinder
									warnCircle.Size = Vector3.new(0.4, 0.1, 0.1)

									local rayParams = RaycastParams.new()
									rayParams.FilterType = Enum.RaycastFilterType.Exclude
									local ignoreList = {model}
									for _, p in ipairs(Players:GetPlayers()) do
										if p.Character then table.insert(ignoreList, p.Character) end
									end
									rayParams.FilterDescendantsInstances = ignoreList
									local rayResult = workspace:Raycast(lungeTargetPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
									local floorPos = rayResult and rayResult.Position or (lungeTargetPos - Vector3.new(0, 2, 0))

									warnCircle.CFrame = CFrame.new(floorPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
									warnCircle.Anchored = true
									warnCircle.CanCollide = false
									warnCircle.Material = Enum.Material.Neon
									warnCircle.Color = Color3.fromRGB(50, 255, 50)
									warnCircle.Transparency = 0.85
									warnCircle.Parent = workspace

									local ts = game:GetService("TweenService")
									ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2),
										Transparency = 0.6
									}):Play()

									task.wait(telegraphDuration)
									warnCircle:Destroy()
								end)

								-- 2. 몸통 박치기 동작 트윈 연출 (웅크림 -> 튕겨 나감)
								deformSlime(model, 1.4, 0.4, 1.4, 0.2)
								task.wait(0.25)

								if isAlive then
									deformSlime(model, 0.7, 1.5, 0.7, 0.15)

									-- 앞으로 살짝 돌진
									local origCF = hrp.CFrame
									local ts = game:GetService("TweenService")
									ts:Create(hrp, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										CFrame = CFrame.new(lungeTargetPos) * origCF.Rotation
									}):Play()

									task.wait(0.2)
									deformSlime(model, 1.0, 1.0, 1.0, 0.2)

									-- 3. 최종 판정 및 데미지 (예고된 원반의 중심/반경과 100% 일치 판정)
									local currentPhrp = targetPlayer:FindFirstChild("HumanoidRootPart")
									if currentPhrp then
										local playerDistFromCenter = (currentPhrp.Position - lungeTargetPos).Magnitude
										if playerDistFromCenter <= telegraphRadius then
											local dmg = config.baseDamage or 6
											local currentPhum = targetPlayer:FindFirstChild("Humanoid")
											if currentPhum and currentPhum.Health > 0 then
												dealDamageToHumanoid(currentPhum, dmg)

												local bounceDir = (currentPhrp.Position - lungeTargetPos)
												bounceDir = Vector3.new(bounceDir.X, 0.2, bounceDir.Z).Unit
												local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
												if hitPlayer then
													local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
													local NetController = require(Controllers:WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.7)
												end
											end
										end
									end
								end
							end
						else
							humanoid:MoveTo(phrp.Position)
						end
					elseif config.mobModelName == "LavaSlime" then
						--========================================================================
						-- [LavaSlime 전용 FSM 분기]: 일반 박치기 + 용암 강타(광역 도약 슬램, 내부쿨 9초)
						--========================================================================
						local ts = game:GetService("TweenService")
						local Debris = game:GetService("Debris")
						local now = os.clock()
						local slamCooldown = config.leapSlamCooldown or 9.0

						local function playLavaSlimeSound(soundName, parent)
							pcall(function()
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local monsterSounds = sounds and sounds:FindFirstChild("Monster")
								local sound = monsterSounds and monsterSounds:FindFirstChild(soundName)
								if sound then
									local sfx = sound:Clone()
									sfx.Parent = parent
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
								end
							end)
						end

						if minDist <= 45 and now - lastLeapSlamTick >= slamCooldown and now - lastAttackTick >= (config.attackCooldown or 2.5) then
							-- [패턴] 용암 강타: 높이 도약했다가 넓은 범위에 착지하며 용암을 터뜨림
							lastLeapSlamTick = now
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position)

							local targetPos = phrp.Position
							local slamRadius = 21 -- [요청반영] 커진 몸집(3.2배)에 맞춰 범위 확대
							local slamDuration = 0.9

							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							rayParams.FilterDescendantsInstances = {model}
							local rayResult = workspace:Raycast(targetPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams)
							local floorPos = rayResult and rayResult.Position or (targetPos - Vector3.new(0, 3, 0))

							deformSlime(model, 1.5, 0.35, 1.5, 0.35)
							task.spawn(function()
								local warnCircle = Instance.new("Part")
								warnCircle.Name = "LavaSlimeSlamTelegraph"
								warnCircle.Shape = Enum.PartType.Cylinder
								warnCircle.Size = Vector3.new(0.4, 0.1, 0.1)
								warnCircle.CFrame = CFrame.new(floorPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
								warnCircle.Anchored = true
								warnCircle.CanCollide = false
								warnCircle.Material = Enum.Material.Neon
								warnCircle.Color = Color3.fromRGB(255, 90, 20)
								warnCircle.Transparency = 0.8
								warnCircle.Parent = workspace
								ts:Create(warnCircle, TweenInfo.new(slamDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									Size = Vector3.new(0.4, slamRadius * 2, slamRadius * 2),
									Transparency = 0.5
								}):Play()
								task.wait(slamDuration)
								warnCircle:Destroy()
							end)
							task.wait(0.35)

							if isAlive then
								local jumpCF = CFrame.new(floorPos + Vector3.new(0, 22, 0))
								ts:Create(hrp, TweenInfo.new(slamDuration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = jumpCF}):Play()
								deformSlime(model, 0.8, 1.6, 0.8, slamDuration * 0.5)
								task.wait(slamDuration * 0.5)
							end

							if isAlive then
								local landCF = CFrame.new(floorPos + Vector3.new(0, 3, 0))
								ts:Create(hrp, TweenInfo.new(slamDuration * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = landCF}):Play()
								deformSlime(model, 1.6, 0.6, 1.6, 0.15)
								task.wait(slamDuration * 0.35)
								deformSlime(model, 1.0, 1.0, 1.0, 0.25)
								playLavaSlimeSound("LavaSlime_LeapSlam", hrp)

								local burstPart = Instance.new("Part")
								burstPart.Name = "LavaSlimeBurst"
								burstPart.Anchored = true
								burstPart.CanCollide = false
								burstPart.Transparency = 1
								burstPart.Size = Vector3.new(1, 1, 1)
								burstPart.CFrame = CFrame.new(floorPos + Vector3.new(0, 1, 0))
								burstPart.Parent = workspace
								Debris:AddItem(burstPart, 2.0)
								local vfxSrc = ReplicatedStorage:FindFirstChild("Assets")
								vfxSrc = vfxSrc and vfxSrc:FindFirstChild("VFX")
								vfxSrc = vfxSrc and vfxSrc:FindFirstChild("Explosion-01")
								vfxSrc = vfxSrc and vfxSrc:FindFirstChild("Main")
								if vfxSrc then
									for _, pname in ipairs({"Fire1", "Fire2", "Fire3", "Specks1"}) do
										local src = vfxSrc:FindFirstChild(pname)
										if src then
											local pe = src:Clone()
											local nk = {}
											for _, kp in ipairs(pe.Size.Keypoints) do
												table.insert(nk, NumberSequenceKeypoint.new(kp.Time, kp.Value * 0.9, kp.Envelope * 0.9))
											end
											pe.Size = NumberSequence.new(nk)
											pe.Parent = burstPart
											pe:Emit(pname == "Specks1" and 40 or 12)
											task.delay(0.6, function() if pe and pe.Parent then pe.Enabled = false end end)
										end
									end
								end

								for _, p in ipairs(Players:GetPlayers()) do
									local char = p.Character
									local phumLocal = char and char:FindFirstChild("Humanoid")
									local pRootLocal = char and char:FindFirstChild("HumanoidRootPart")
									if phumLocal and phumLocal.Health > 0 and pRootLocal then
										local dist = (pRootLocal.Position - floorPos).Magnitude
										if dist <= slamRadius then
											local dmg = (config.baseDamage or 50) * 1.6
											dealDamageToHumanoid(phumLocal, dmg)
											local bounceDir = (pRootLocal.Position - floorPos)
											bounceDir = Vector3.new(bounceDir.X, 0.3, bounceDir.Z)
											bounceDir = (bounceDir.Magnitude > 0.1) and bounceDir.Unit or Vector3.new(0, 0.3, 1)
											local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
											local NetController = require(Controllers:WaitForChild("NetController"))
											NetController.FireClient(p, "Player.Stun", bounceDir)
										end
									end
								end
							end

							task.wait(0.4)
						elseif minDist > 22 and minDist <= 55 and now - lastThrustTick >= (config.lavaSpitCooldown or 4.5) then
							-- [패턴] 용암 튀김: 원거리에서 용암 덩어리 3발을 흩뿌려 던짐
							lastThrustTick = now
							humanoid:MoveTo(hrp.Position)
							playLavaSlimeSound("LavaSlime_LavaSpit", hrp)

							local aimBase = phrp.Position
							for i = 1, 3 do
								task.spawn(function()
									task.wait((i - 1) * 0.15)
									if not isAlive then return end
									local spread = Vector3.new((math.random() - 0.5) * 10, 0, (math.random() - 0.5) * 10)
									local aimPos = aimBase + spread
									local startPos = hrp.Position + Vector3.new(0, 4, 0)

									local glob = Instance.new("Part")
									glob.Name = "LavaSlimeGlob"
									glob.Shape = Enum.PartType.Ball
									glob.Anchored = true
									glob.CanCollide = false
									glob.Material = Enum.Material.Neon
									glob.Color = Color3.fromRGB(255, 100, 20)
									glob.Size = Vector3.new(1.8, 1.8, 1.8)
									glob.CFrame = CFrame.new(startPos)
									glob.Parent = workspace

									local flightTime = math.clamp((aimPos - startPos).Magnitude / 45, 0.3, 1.4)
									local peakCF = CFrame.new((startPos + aimPos) / 2 + Vector3.new(0, 12, 0))
									ts:Create(glob, TweenInfo.new(flightTime * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = peakCF}):Play()
									task.wait(flightTime * 0.5)
									if glob and glob.Parent then
										ts:Create(glob, TweenInfo.new(flightTime * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {CFrame = CFrame.new(aimPos)}):Play()
										task.wait(flightTime * 0.5)
									end

									if glob and glob.Parent then
										glob:Destroy()
										local burstPart = Instance.new("Part")
										burstPart.Name = "LavaGlobBurst"
										burstPart.Anchored = true
										burstPart.CanCollide = false
										burstPart.Transparency = 1
										burstPart.Size = Vector3.new(1, 1, 1)
										burstPart.CFrame = CFrame.new(aimPos)
										burstPart.Parent = workspace
										Debris:AddItem(burstPart, 1.5)
										local ring = Instance.new("Part")
										ring.Name = "LavaGlobRing"
										ring.Shape = Enum.PartType.Cylinder
										ring.Anchored = true
										ring.CanCollide = false
										ring.Material = Enum.Material.Neon
										ring.Color = Color3.fromRGB(255, 100, 20)
										ring.Transparency = 0.3
										ring.Size = Vector3.new(0.3, 1, 1)
										ring.CFrame = CFrame.new(aimPos) * CFrame.Angles(0, 0, math.rad(90))
										ring.Parent = workspace
										ts:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
											Size = Vector3.new(0.3, 9, 9), Transparency = 1
										}):Play()
										Debris:AddItem(ring, 0.5)

										for _, p in ipairs(Players:GetPlayers()) do
											local char = p.Character
											local phumLocal = char and char:FindFirstChild("Humanoid")
											local pRootLocal = char and char:FindFirstChild("HumanoidRootPart")
											if phumLocal and phumLocal.Health > 0 and pRootLocal then
												local dist = (pRootLocal.Position - aimPos).Magnitude
												if dist <= 4.5 then
													dealDamageToHumanoid(phumLocal, (config.baseDamage or 50) * 0.7)
												end
											end
										end
									end
								end)
							end
							task.wait(0.6)
						elseif minDist <= ATTACK_RANGE or (minDist <= 25 and now - lastAttackTick >= (config.attackCooldown or 2.5) + 1.0) then
							humanoid:MoveTo(hrp.Position)
							local cooldown = config.attackCooldown or 2.5
							if now - lastAttackTick >= cooldown then
								lastAttackTick = now
								local targetHrpPos = phrp.Position
								local lungeDir = (targetHrpPos - hrp.Position)
								lungeDir = Vector3.new(lungeDir.X, 0, lungeDir.Z)
								lungeDir = (lungeDir.Magnitude > 0.1) and lungeDir.Unit or Vector3.new(0, 0, 1)
								local lungeTargetPos = hrp.Position + lungeDir * 6
								local telegraphRadius = 7
								local telegraphDuration = 0.7

								task.spawn(function()
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "SlimeAtkTelegraph"
									warnCircle.Shape = Enum.PartType.Cylinder
									warnCircle.Size = Vector3.new(0.4, 0.1, 0.1)
									local rayParams2 = RaycastParams.new()
									rayParams2.FilterType = Enum.RaycastFilterType.Exclude
									rayParams2.FilterDescendantsInstances = {model}
									local rayResult2 = workspace:Raycast(lungeTargetPos + Vector3.new(0, 50, 0), Vector3.new(0, -150, 0), rayParams2)
									local floorPos2 = rayResult2 and rayResult2.Position or (lungeTargetPos - Vector3.new(0, 2, 0))
									warnCircle.CFrame = CFrame.new(floorPos2 + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
									warnCircle.Anchored = true
									warnCircle.CanCollide = false
									warnCircle.Material = Enum.Material.Neon
									warnCircle.Color = Color3.fromRGB(255, 130, 40)
									warnCircle.Transparency = 0.85
									warnCircle.Parent = workspace
									ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										Size = Vector3.new(0.4, telegraphRadius * 2, telegraphRadius * 2),
										Transparency = 0.6
									}):Play()
									task.wait(telegraphDuration)
									warnCircle:Destroy()
								end)

								deformSlime(model, 1.4, 0.4, 1.4, 0.2)
								task.wait(0.25)
								if isAlive then
									deformSlime(model, 0.7, 1.5, 0.7, 0.15)
									local origCF = hrp.CFrame
									ts:Create(hrp, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										CFrame = CFrame.new(lungeTargetPos) * origCF.Rotation
									}):Play()
									task.wait(0.2)
									deformSlime(model, 1.0, 1.0, 1.0, 0.2)
									local currentPhrp = targetPlayer:FindFirstChild("HumanoidRootPart")
									if currentPhrp then
										local playerDistFromCenter = (currentPhrp.Position - lungeTargetPos).Magnitude
										if playerDistFromCenter <= telegraphRadius then
											local dmg = config.baseDamage or 50
											local currentPhum = targetPlayer:FindFirstChild("Humanoid")
											if currentPhum and currentPhum.Health > 0 then
												dealDamageToHumanoid(currentPhum, dmg)
												local bounceDir = (currentPhrp.Position - lungeTargetPos)
												bounceDir = Vector3.new(bounceDir.X, 0.2, bounceDir.Z)
												bounceDir = (bounceDir.Magnitude > 0.1) and bounceDir.Unit or Vector3.new(0, 0.2, 1)
												local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
												if hitPlayer then
													local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
													local NetController = require(Controllers:WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.7)
												end
											end
										end
									end
								end
							end
						else
							humanoid:MoveTo(phrp.Position)
						end
					elseif config.mobModelName == "FireMan" then
						--========================================================================
						-- [FireMan 전용 FSM 분기]: 순간이동(내부쿨 13초) + 불기둥(근거리 광역) + 화염 투척(원거리)
						--========================================================================
						local ts = game:GetService("TweenService")
						local Debris = game:GetService("Debris")
						local now = os.clock()

						local fireVfxRoot = ReplicatedStorage:FindFirstChild("Assets")
						fireVfxRoot = fireVfxRoot and fireVfxRoot:FindFirstChild("VFX")
						fireVfxRoot = fireVfxRoot and fireVfxRoot:FindFirstChild("Explosion-01")
						fireVfxRoot = fireVfxRoot and fireVfxRoot:FindFirstChild("Main")

						local function playFireManSound(soundName, parent)
							pcall(function()
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local monsterSounds = sounds and sounds:FindFirstChild("Monster")
								local sound = monsterSounds and monsterSounds:FindFirstChild(soundName)
								if sound then
									local sfx = sound:Clone()
									sfx.Parent = parent
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
								end
							end)
						end

						local function spawnFirePuff(pos, scale, amount)
							local host = Instance.new("Part")
							host.Name = "FireManPuff"
							host.Anchored = true
							host.CanCollide = false
							host.Transparency = 1
							host.Size = Vector3.new(1, 1, 1)
							host.CFrame = CFrame.new(pos)
							host.Parent = workspace
							Debris:AddItem(host, 2.0)
							if fireVfxRoot then
								for _, pname in ipairs({"Fire1", "Fire2", "Fire3", "Specks1"}) do
									local src = fireVfxRoot:FindFirstChild(pname)
									if src then
										local pe = src:Clone()
										local nk = {}
										for _, kp in ipairs(pe.Size.Keypoints) do
											table.insert(nk, NumberSequenceKeypoint.new(kp.Time, kp.Value * scale, kp.Envelope * scale))
										end
										pe.Size = NumberSequence.new(nk)
										pe.Parent = host
										pe:Emit(pname == "Specks1" and (amount * 2) or amount)
										task.delay(0.5, function() if pe and pe.Parent then pe.Enabled = false end end)
									end
								end
							end
						end

						local teleportCooldown = config.teleportCooldown or 13.0
						local pillarCooldown = config.pillarCooldown or 7.0
						local fireballCooldown = config.fireballCooldown or 5.0

						if now - lastGimmickTick >= teleportCooldown and minDist > 12 then
							-- [패턴] 순간이동: 플레이어 근처(8~14스터드)로 불꽃과 함께 블링크
							lastGimmickTick = now
							humanoid:MoveTo(hrp.Position)

							spawnFirePuff(hrp.Position + Vector3.new(0, 2, 0), 0.12, 20)
							playFireManSound("FireMan_Teleport", hrp)

							local ang = math.random() * math.pi * 2
							local dist = math.random(10, 20)
							local destPos = phrp.Position + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
							local rayParams = RaycastParams.new()
							rayParams.FilterType = Enum.RaycastFilterType.Exclude
							rayParams.FilterDescendantsInstances = {model}
							local rayResult = workspace:Raycast(destPos + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), rayParams)
							local landPos = rayResult and rayResult.Position or destPos

							task.wait(0.15)
							if isAlive then
								model:PivotTo(CFrame.new(landPos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
								spawnFirePuff(landPos + Vector3.new(0, 2, 0), 0.14, 22)
							end
							task.wait(0.3)

						elseif minDist <= 34 and now - lastWhirlwindTick >= pillarCooldown and now - lastAttackTick >= (config.attackCooldown or 2.0) then
							-- [패턴] 불기둥: 플레이어 주변 4곳에서 땅을 뚫고 불기둥이 솟구침
							lastWhirlwindTick = now
							lastAttackTick = now
							humanoid:MoveTo(hrp.Position)
							playFireManSound("FireMan_Pillar", hrp)

							local centerPos = phrp.Position
							local pillarSpots = {}
							for i = 1, 4 do
								local ang = (i - 1) * (math.pi * 2 / 4) + math.random() * 0.5
								local dist = math.random(0, 13)
								local spotXZ = centerPos + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
								local rayParams = RaycastParams.new()
								rayParams.FilterType = Enum.RaycastFilterType.Exclude
								rayParams.FilterDescendantsInstances = {model}
								local rayResult = workspace:Raycast(spotXZ + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), rayParams)
								table.insert(pillarSpots, rayResult and rayResult.Position or spotXZ)
							end

							for _, spot in ipairs(pillarSpots) do
								task.spawn(function()
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "FireManPillarTelegraph"
									warnCircle.Shape = Enum.PartType.Cylinder
									warnCircle.Size = Vector3.new(0.3, 9, 9)
									warnCircle.CFrame = CFrame.new(spot + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
									warnCircle.Anchored = true
									warnCircle.CanCollide = false
									warnCircle.Material = Enum.Material.Neon
									warnCircle.Color = Color3.fromRGB(255, 60, 20)
									warnCircle.Transparency = 0.7
									warnCircle.Parent = workspace
									ts:Create(warnCircle, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 0.2}):Play()
									task.wait(0.8)
									warnCircle:Destroy()

									if not isAlive then return end

									-- 불기둥 솟구침
									local pillar = Instance.new("Part")
									pillar.Name = "FireManPillar"
									pillar.Anchored = true
									pillar.CanCollide = false
									pillar.Material = Enum.Material.Neon
									pillar.Color = Color3.fromRGB(255, 110, 30)
									pillar.Transparency = 0.15
									pillar.Size = Vector3.new(4.5, 0.5, 4.5)
									pillar.CFrame = CFrame.new(spot)
									pillar.Parent = workspace
									ts:Create(pillar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										Size = Vector3.new(4.5, 24, 4.5),
										CFrame = CFrame.new(spot + Vector3.new(0, 12, 0)),
									}):Play()
									spawnFirePuff(spot + Vector3.new(0, 1, 0), 0.18, 24)
									Debris:AddItem(pillar, 0.9)

									task.wait(0.25)
									for _, p in ipairs(Players:GetPlayers()) do
										local char = p.Character
										local phumLocal = char and char:FindFirstChild("Humanoid")
										local pRootLocal = char and char:FindFirstChild("HumanoidRootPart")
										if phumLocal and phumLocal.Health > 0 and pRootLocal then
											local dist = (Vector3.new(pRootLocal.Position.X, 0, pRootLocal.Position.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude
											if dist <= 7.5 then
												dealDamageToHumanoid(phumLocal, config.baseDamage or 60)
											end
										end
									end
								end)
								task.wait(0.15)
							end
							task.wait(0.5)

						elseif minDist > 20 and now - lastThrustTick >= fireballCooldown then
							-- [패턴] 화염 투척: 원거리에서 불덩이를 던짐
							lastThrustTick = now
							humanoid:MoveTo(hrp.Position)
							playFireManSound("FireMan_Fireball", hrp)

							local startPos = hrp.Position + Vector3.new(0, 3, 0) + hrp.CFrame.LookVector * 1.5
							local fireball = Instance.new("Part")
							fireball.Name = "FireManFireball"
							fireball.Shape = Enum.PartType.Ball
							fireball.Anchored = true
							fireball.CanCollide = false
							fireball.Material = Enum.Material.Neon
							fireball.Color = Color3.fromRGB(255, 130, 30)
							fireball.Size = Vector3.new(1.6, 1.6, 1.6)
							fireball.CFrame = CFrame.new(startPos)
							fireball.Parent = workspace
							local trail = Instance.new("ParticleEmitter")
							trail.Texture = "rbxasset://textures/particles/fire_main.dds"
							trail.Color = ColorSequence.new(Color3.fromRGB(255, 180, 60))
							trail.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0)})
							trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
							trail.Lifetime = NumberRange.new(0.2, 0.3)
							trail.Rate = 60
							trail.Speed = NumberRange.new(0, 1)
							trail.Parent = fireball

							local aimPos = phrp.Position
							local flightTime = math.clamp((aimPos - startPos).Magnitude / 60, 0.25, 1.6)
							ts:Create(fireball, TweenInfo.new(flightTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(aimPos)}):Play()

							task.spawn(function()
								task.wait(flightTime)
								if fireball and fireball.Parent then
									spawnFirePuff(fireball.Position, 0.13, 16)
									fireball:Destroy()
								end
								local currentPhrp = targetPlayer:FindFirstChild("HumanoidRootPart")
								if currentPhrp then
									local dist = (currentPhrp.Position - aimPos).Magnitude
									if dist <= 12 then
										local currentPhum = targetPlayer:FindFirstChild("Humanoid")
										if currentPhum and currentPhum.Health > 0 then
											dealDamageToHumanoid(currentPhum, config.baseDamage or 60)
										end
									end
								end
							end)
							task.wait(0.4)

						elseif minDist <= ATTACK_RANGE then
							-- [기본 근접 공격]
							humanoid:MoveTo(hrp.Position)
							if now - lastAttackTick >= (config.attackCooldown or 2.0) then
								lastAttackTick = now
								local currentPhum = targetPlayer:FindFirstChild("Humanoid")
								if currentPhum and currentPhum.Health > 0 then
									dealDamageToHumanoid(currentPhum, config.baseDamage or 60)
								end
							end
						else
							humanoid:MoveTo(phrp.Position)
						end
					elseif config.mobModelName == "HornedLarva" then
						--========================================================================
						-- [HornedLarva 전용 FSM 분기]: 일반 공격(뿔 크레센트 스윕)
						--========================================================================
						if minDist <= ATTACK_RANGE or (minDist <= 28 and os.clock() - lastAttackTick >= (config.attackCooldown or 2.5) + 1.0) then
							humanoid:MoveTo(hrp.Position) -- 멈춤
							local now = os.clock()
							local cooldown = config.attackCooldown or 2.5

							if now - lastAttackTick >= cooldown then
								lastAttackTick = now

								-- [일반 공격] 뿔 크레센트 스윕 (Horn Crescent Sweep)
								local sweepWidth = 14
								local sweepDuration = 0.6
								local sweepTelegraphCF = hrp.CFrame * CFrame.new(0, 0, -4)

								-- 1. 초승달 전방 전조 생성
								task.spawn(function()
									local warnArc = Instance.new("Part")
									warnArc.Name = "LarvaAtkTelegraph"
									warnArc.Size = Vector3.new(sweepWidth, 0.4, 6)

									local rayParams = RaycastParams.new()
									rayParams.FilterType = Enum.RaycastFilterType.Exclude
									rayParams.FilterDescendantsInstances = {model}
									local rayResult = workspace:Raycast(sweepTelegraphCF.Position, Vector3.new(0, -50, 0), rayParams)
									local floorY = rayResult and rayResult.Position.Y or (sweepTelegraphCF.Position.Y - 2)

									warnArc.CFrame = CFrame.new(sweepTelegraphCF.Position.X, floorY + 0.1, sweepTelegraphCF.Position.Z) * hrp.CFrame.Rotation
									warnArc.Anchored = true
									warnArc.CanCollide = false
									warnArc.Material = Enum.Material.Neon
									warnArc.Color = Color3.fromRGB(255, 140, 0) -- 주황색
									warnArc.Transparency = 0.8
									warnArc.Parent = workspace

									local ts = game:GetService("TweenService")
									ts:Create(warnArc, TweenInfo.new(sweepDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										Transparency = 0.5,
										Size = Vector3.new(sweepWidth + 2, 0.4, 7)
									}):Play()

									task.wait(sweepDuration)
									warnArc:Destroy()
								end)

								-- 2. 머리 젖히기 좌우 스윕 회전 물리 모션 연출
								local origCF = hrp.CFrame
								local ts = game:GetService("TweenService")
								ts:Create(hrp, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = origCF * CFrame.Angles(0, math.rad(-25), 0)
								}):Play()

								task.wait(0.25)

								if isAlive then
									ts:Create(hrp, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
										CFrame = origCF * CFrame.Angles(0, math.rad(25), 0)
									}):Play()

									task.wait(0.15)
									ts:Create(hrp, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										CFrame = origCF
									}):Play()

									-- 날카로운 주황색 스파크 파티클 뿜어내기
									local att = Instance.new("Attachment", hrp)
									att.Position = Vector3.new(0, 0, -2)

									local pe = Instance.new("ParticleEmitter")
									pe.Texture = "rbxasset://textures/particles/spark.dds"
									pe.Color = ColorSequence.new(Color3.fromRGB(255, 140, 0), Color3.fromRGB(255, 255, 255))
									pe.Size = NumberSequence.new(0.5, 1.5)
									pe.Rate = 80
									pe.Lifetime = NumberRange.new(0.3, 0.5)
									pe.Speed = NumberRange.new(12, 22)
									pe.SpreadAngle = Vector2.new(45, 45)
									pe.Parent = att
									game.Debris:AddItem(att, 0.4)

									-- 3. 최종 판정 및 데미지 (전방 장판 범위와 100% 정합)
									local currentPhrp = targetPlayer:FindFirstChild("HumanoidRootPart")
									if currentPhrp then
										local relativePos = hrp.CFrame:PointToObjectSpace(currentPhrp.Position)
										if relativePos.Z < 0 and relativePos.Z > -8 and math.abs(relativePos.X) <= (sweepWidth / 2 + 1) and math.abs(relativePos.Y) < 6 then
											local dmg = config.baseDamage or 5
											local currentPhum = targetPlayer:FindFirstChild("Humanoid")
											if currentPhum and currentPhum.Health > 0 then
												dealDamageToHumanoid(currentPhum, dmg)

												local bounceDir = (currentPhrp.Position - hrp.Position)
												bounceDir = Vector3.new(bounceDir.X, 0.1, bounceDir.Z).Unit
												local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
												if hitPlayer then
													local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
													local NetController = require(Controllers:WaitForChild("NetController"))
													NetController.FireClient(hitPlayer, "Player.Stun", bounceDir * 0.8)
												end
											end
										end
									end
								end
							end
						else
							humanoid:MoveTo(phrp.Position)
						end

					elseif config.mobModelName == "Jellyfish" then
						--========================================================================
						-- [Jellyfish 전용 FSM 분기]: 3D 수중 유영 + 바닥 장판 전조 공격
						-- CyclopsBat 패턴 참조: humanoid:MoveTo + PlatformStand
						--========================================================================
						local currentPos = hrp.Position
						local targetPos  = phrp.Position
						local distToPlayer = minDist
						local now = os.clock()
						local attackCooldown = config.attackCooldown or 2.2
						local JELLY_ATTACK_RANGE = 36  -- [수정] 28 -> 16 -> 6 -> 9 -> 18 -> 36: 요청에 따라 2배로 확대
						local JELLY_LEASH_RADIUS = 40 -- [버그수정] 스폰지점(협곡)에서 이 거리 이상 끌려나가면 강제 귀환 -> 수중도시 바깥까지 쫓아가는 것 방지

						-- Humanoid 물리 간섭 차단 (파닥거림 방지)
						humanoid.PlatformStand = true

						-- BodyVelocity로 3D 수중 이동 (중력 무효화)
						local bv = hrp:FindFirstChild("JellyBV")
						if not bv then
							bv = Instance.new("BodyVelocity")
							bv.Name = "JellyBV"
							bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
							bv.P = 8000
							bv.Velocity = Vector3.new(0, 0, 0)
							bv.Parent = hrp
						end

						-- BodyGyro로 회전 고정 (빙글빙글 방지)
						local bg = hrp:FindFirstChild("JellyBG")
						if not bg then
							bg = Instance.new("BodyGyro")
							bg.Name = "JellyBG"
							bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
							bg.P = 10000
							bg.D = 1000
							bg.CFrame = hrp.CFrame
							bg.Parent = hrp
						end

						local yDiff = math.abs(currentPos.Y - targetPos.Y)
						local inAttackRange = distToPlayer <= JELLY_ATTACK_RANGE and yDiff <= 5 -- [수정] 12 -> 5: 플레이어 높이까지 실제로 내려와야 공격
						local distFromHome = (currentPos - spawnCenter).Magnitude

						if jellyAttackBusy then
							-- [버그수정] 공격(전조+판정) 진행 중엔 몸통을 그 자리에 완전히 고정시켜서,
							-- 플레이어가 살짝 움직였다고 다시 떠오르며 "공중에서 공격"하는 것처럼 보이는 문제를 방지.
							bv.Velocity = Vector3.new(0, 0, 0)
						elseif distFromHome > JELLY_LEASH_RADIUS then
							-- [버그수정] 스폰 협곡에서 너무 멀리 끌려나감 -> 타겟 강제 포기하고 스폰지점으로 귀환
							lastTarget = nil
							local dir = (spawnCenter - currentPos)
							if dir.Magnitude > 1 then
								bv.Velocity = dir.Unit * (config.walkSpeed or 12)
								local lookDir = Vector3.new(dir.X, 0, dir.Z)
								if lookDir.Magnitude > 0.1 then
									local targetCF = CFrame.lookAt(currentPos, currentPos + lookDir.Unit)
									bg.CFrame = targetCF
									hrp.CFrame = targetCF
								end
							else
								bv.Velocity = Vector3.new(0, 0, 0)
							end
						elseif not inAttackRange then
							-- 플레이어 Y 높이로 내려오면서 3D 수영 이동
							local swimTarget = Vector3.new(targetPos.X, targetPos.Y, targetPos.Z)
							local dir = (swimTarget - currentPos)
							if dir.Magnitude > 1 then
								bv.Velocity = dir.Unit * (config.walkSpeed or 12)
								local lookDir = Vector3.new(dir.X, 0, dir.Z)
								if lookDir.Magnitude > 0.1 then
									local targetCF = CFrame.lookAt(currentPos, currentPos + lookDir.Unit)
									bg.CFrame = targetCF
									hrp.CFrame = targetCF
								end
							else
								bv.Velocity = Vector3.new(0, 0, 0)
							end
						else
							-- 플레이어 높이 도달 + 공격 범위 내 → 정지 후 공격
							bv.Velocity = Vector3.new(0, 0, 0)
							bg.CFrame = hrp.CFrame  -- 현재 방향 유지

							if now - lastAttackTick >= attackCooldown then
								lastAttackTick = now
								jellyAttackBusy = true

								task.spawn(function()
									pcall(function()
									local mobRootPos = hrp.Position
									local ts = game:GetService("TweenService")
									local attackRadius = 7 -- [수정] 14 -> 7 -> 12 -> 24 -> 7: 판정 범위는 원래대로, "사거리"는 접근거리(JELLY_ATTACK_RANGE)만 의미했음
									local telegraphDuration = 1.2

									-- [버그수정] 젤리피쉬는 3D 자유유영이라 플레이어가 바다 바닥 근처에 있지 않은 경우가
									-- 대부분이라, 바닥에 레이캐스트로 찍은 지점(floorPos)을 판정 중심으로 쓰면 실제
									-- 전투 위치와 수직으로 수십 스터드씩 어긋나 "판정이 하나도 안 맞는"(=멀리서 헛치는
									-- 것처럼 보이는) 문제가 있었다. 바닥 대신 트리거 시점 플레이어의 실제 3D 위치를
									-- 판정 중심으로 사용한다.
									local floorPos = Vector3.new(targetPos.X, targetPos.Y, targetPos.Z)

									if not isAlive then return end
									local attackHrp = targetPlayer and targetPlayer:FindFirstChild("HumanoidRootPart")
									if not attackHrp then return end

									local endP = attackHrp.Position

									local vfxAssets = ReplicatedStorage:FindFirstChild("Assets")
									local thunderTemplate = vfxAssets
										and vfxAssets:FindFirstChild("VFX")
										and vfxAssets.VFX:FindFirstChild("Boss")
										and vfxAssets.VFX.Boss:FindFirstChild("Thunder")

									-- ── 1. 경고 구체 (전조) ── [수정] 바닥 원판(Cylinder) -> 3D 구체(Ball)
									-- 수중 자유유영 몹이라 바닥에 눕는 장판은 실제 판정 위치와 맞지 않음.
									local warnCircle = Instance.new("Part")
									warnCircle.Name = "JellyfishTelegraph"
									warnCircle.Shape = Enum.PartType.Ball
									warnCircle.Size = Vector3.new(attackRadius * 2, attackRadius * 2, attackRadius * 2)
									warnCircle.CFrame = CFrame.new(floorPos)
									warnCircle.Anchored = true
									warnCircle.CanCollide = false
									warnCircle.CanTouch = false
									warnCircle.CanQuery = false
									warnCircle.CastShadow = false
									warnCircle.Material = Enum.Material.Neon
									warnCircle.Color = Color3.fromRGB(0, 220, 255)
									warnCircle.Transparency = 0.85
									warnCircle.Parent = workspace

									ts:Create(warnCircle, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
										Transparency = 0.2,
										Size = Vector3.new(attackRadius * 2.4, attackRadius * 2.4, attackRadius * 2.4),
									}):Play()

									pcall(function()
										local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = sounds and sounds:FindFirstChild("Monster")
										local sound = monsterSounds and monsterSounds:FindFirstChild("Jellyfish_Attack")
										if sound then
											local sfx = sound:Clone()
											sfx.Parent = hrp
											sfx:Play()
											game.Debris:AddItem(sfx, 3)
										end
									end)

									task.wait(telegraphDuration)
									warnCircle:Destroy()

									-- ── 2. Thunder VFX (패턴 공격) ──
									-- 공격 시 PointLight 켜기
									for _, desc in ipairs(model:GetDescendants()) do
										if desc:IsA("PointLight") or desc:IsA("SpotLight") then
											desc.Enabled = true
										end
									end
									task.delay(1.5, function()
										for _, desc in ipairs(model:GetDescendants()) do
											if desc:IsA("PointLight") or desc:IsA("SpotLight") then
												desc.Enabled = false
											end
										end
									end)

									if thunderTemplate then
										local thunder = thunderTemplate:Clone()
										local VFX_SCALE = 6.0
										if thunder:IsA("Model") then
											pcall(function() thunder:ScaleTo(VFX_SCALE) end)
											thunder:PivotTo(CFrame.new(endP))
										elseif thunder:IsA("BasePart") then
											thunder.Size = thunder.Size * VFX_SCALE
											thunder.CFrame = CFrame.new(endP)
										end
										thunder.Parent = workspace
										for _, desc in ipairs(thunder:GetDescendants()) do
											if desc:IsA("ParticleEmitter") then
												desc.Speed = NumberRange.new(desc.Speed.Min * VFX_SCALE, desc.Speed.Max * VFX_SCALE)
												desc.Enabled = true
												task.delay(1.5, function() if desc and desc.Parent then desc.Enabled = false end end)
											elseif desc:IsA("Beam") or desc:IsA("Trail") then
												desc.Enabled = true
												task.delay(1.5, function() if desc and desc.Parent then desc.Enabled = false end end)
											elseif desc:IsA("Sound") then
												desc:Play()
											end
										end
										if thunder:IsA("BasePart") then
											ts:Create(thunder, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
												Transparency = 1
											}):Play()
										end
										task.delay(2.5, function()
											if thunder and thunder.Parent then thunder:Destroy() end
										end)
									end

									-- ── 3. 데미지 판정 ──
									if not isAlive then return end
									local finalHrp = targetPlayer and targetPlayer:FindFirstChild("HumanoidRootPart")
									if not finalHrp then return end

									local playerDistFromCenter = (finalHrp.Position - floorPos).Magnitude
									if playerDistFromCenter <= attackRadius then
										local dmg = config.baseDamage or 65
										local currentPhum = targetPlayer:FindFirstChild("Humanoid")
										if currentPhum and currentPhum.Health > 0 then
											dealDamageToHumanoid(currentPhum, dmg)
											local bounceDir = (finalHrp.Position - mobRootPos)
											bounceDir = Vector3.new(bounceDir.X, 0, bounceDir.Z).Unit
											local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
											if hitPlayer then
												local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
												local NetController = require(Controllers:WaitForChild("NetController"))
												NetController.FireClient(hitPlayer, "Player.Stun", bounceDir)
											end
										end
									end
									end)
									jellyAttackBusy = false
								end)
							end
						end

					elseif config.mobModelName == "Kraken" then
						--========================================================================
						-- [크라켄 전용 FSM 분기]: 촉수를 들어올렸다가 내려찍는 기본 공격
						-- (원형 경고 서클이 아니라 몸통->착지점까지 이어지는 직사각형 경고 장판)
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude

						-- [거의 전역 범위 광역기] 사거리와 무관하게 독자 쿨타임으로 발동 (플레이어가 멀리 있어도 발동)
						do
							local nowCB = os.clock()
							local checkerboardCooldown = config.checkerboardCooldown or 16
							if nowCB - lastCheckerboardTick >= checkerboardCooldown then
								lastCheckerboardTick = nowCB
								lastAttackTick = nowCB -- 광역기 직후 바로 기본 공격이 겹치지 않도록 기본 공격 쿨다운도 같이 갱신
								humanoid:MoveTo(currentPos) -- 캐스팅 동안 정지
								pcall(function()
									local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
									local monsterSounds = sounds and sounds:FindFirstChild("Monster")
									local sound = monsterSounds and monsterSounds:FindFirstChild("Kraken_Checkerboard")
									if sound then
										local sfx = sound:Clone()
										sfx.Parent = hrp
										sfx:Play()
										game.Debris:AddItem(sfx, 3)
									end
								end)
								task.spawn(function()
									playKrakenCheckerboardAttack(model, targetPlayer)
								end)
							end
						end

						if distToPlayer > ATTACK_RANGE then
							humanoid:MoveTo(Vector3.new(targetPlayerPos.X, currentPos.Y, targetPlayerPos.Z))
						else
							humanoid:MoveTo(currentPos) -- 정지 후 공격

							local now = os.clock()
							local cooldown = config.attackCooldown or 2.5
							if now - lastAttackTick >= cooldown and #tentacleJoints > 0 then
								lastAttackTick = now

								task.spawn(function()
									local mobRootPos = hrp.Position
									local attackHrp = targetPlayer and targetPlayer:FindFirstChild("HumanoidRootPart")
									if not attackHrp then return end
									
									local dir = attackHrp.Position - mobRootPos
									local flatDir = Vector3.new(dir.X, 0, dir.Z)
									flatDir = (flatDir.Magnitude > 0.1) and flatDir.Unit or Vector3.new(0, 0, -1)
									
									-- [버그수정] 무작위로 다리를 고르면 경고 장판 방향과 반대쪽 다리가 내려찍는
									-- 이상한 상황이 생김 -> 플레이어 방향과 가장 가깝게 뻗어있는(세그먼트1의 실제
									-- 월드 위치 기준) 다리를 골라서 항상 장판과 같은 쪽 다리가 공격하도록 함
									local armCount = math.min(8, #tentacleJoints)
									local ti, bestDot = nil, -math.huge
									for idx = 1, armCount do
										local candJoints = tentacleJoints[idx]
										local seg1 = candJoints and candJoints[1] and candJoints[1].motor.Part1
										if seg1 then
											local segOffset = seg1.Position - mobRootPos
											local flatSegOffset = Vector3.new(segOffset.X, 0, segOffset.Z)
											if flatSegOffset.Magnitude > 0.01 then
												local d = flatSegOffset.Unit:Dot(flatDir)
												if d > bestDot then
													bestDot = d
													ti = idx
												end
											end
										end
									end
									ti = ti or math.random(1, armCount)
									local joints = tentacleJoints[ti]
									if not joints or #joints == 0 then return end
									
									krakenAttackOverride[ti] = true
									
									-- 착지 지점의 실제 바닥 높이 레이캐스트
									-- [수정] 크라켄의 거대한 스케일(촉수 반경 약 45+)에 맞춰 판정 사거리/장판 크기를 대폭 확대
									local strikeDistance = 32
									local strikeCenter = mobRootPos + flatDir * strikeDistance
									local rayParams = RaycastParams.new()
									rayParams.FilterType = Enum.RaycastFilterType.Exclude
									rayParams.FilterDescendantsInstances = { model, targetPlayer }
									local rayResult = workspace:Raycast(strikeCenter + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams)
									local floorY = rayResult and rayResult.Position.Y or (mobRootPos.Y - 20)

									-- 몸통 근처에서 착지 지점까지 길게 이어지는 직사각형 경고 장판
									local rectWidth = 18
									local rectLength = strikeDistance + 10
									local telegraphDuration = 0.9

									local warnRect = Instance.new("Part")
									warnRect.Name = "KrakenTelegraph"
									warnRect.Size = Vector3.new(rectWidth, 0.6, rectLength)
									warnRect.CFrame = CFrame.lookAt(
										Vector3.new(mobRootPos.X, floorY + 0.4, mobRootPos.Z),
										Vector3.new(mobRootPos.X + flatDir.X, floorY + 0.4, mobRootPos.Z + flatDir.Z)
									) * CFrame.new(0, 0, -rectLength / 2)
									warnRect.Anchored = true
									warnRect.CanCollide = false
									warnRect.CanTouch = false
									warnRect.CanQuery = false
									warnRect.CastShadow = false
									warnRect.Material = Enum.Material.Neon
									warnRect.Color = Color3.fromRGB(255, 25, 25)
									warnRect.Transparency = 0.55
									warnRect.Parent = workspace

									-- 선명한 테두리(외곽선)를 덧대어 범위 경계를 더 직관적으로 표시
									local border = Instance.new("Part")
									border.Name = "KrakenTelegraphBorder"
									border.Size = Vector3.new(rectWidth + 1.2, 0.5, rectLength + 1.2)
									border.CFrame = warnRect.CFrame
									border.Anchored = true
									border.CanCollide = false
									border.CanTouch = false
									border.CanQuery = false
									border.CastShadow = false
									border.Material = Enum.Material.Neon
									border.Color = Color3.fromRGB(180, 0, 0) -- [수정] 주황 대신 짙은 빨강으로 통일 (오직 빨간색만)
									border.Transparency = 0.7
									border.Parent = workspace

									local ts = game:GetService("TweenService")
									ts:Create(warnRect, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
										Transparency = 0.1,
									}):Play()
									ts:Create(border, TweenInfo.new(telegraphDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
										Transparency = 0.2,
									}):Play()

									-- 경고 장판을 짧게 두 번 깜빡여 위험을 더 직관적으로 알림
									task.spawn(function()
										for _ = 1, 3 do
											if not warnRect.Parent then break end
											warnRect.Transparency = 0.6
											border.Transparency = 0.75
											task.wait(0.12)
											if not warnRect.Parent then break end
											warnRect.Transparency = 0.15
											border.Transparency = 0.25
											task.wait(0.12)
										end
									end)
									
									pcall(function()
										local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
										local monsterSounds = sounds and sounds:FindFirstChild("Monster")
										local sound = monsterSounds and monsterSounds:FindFirstChild("Kraken_TentacleSlam")
										if sound then
											local sfx = sound:Clone()
											sfx.Parent = hrp
											sfx:Play()
											game.Debris:AddItem(sfx, 3)
										end
									end)

									-- 다리를 들어올림 (텔레그래프 지속시간 동안 다리 전체가 하나의 팔처럼 위로 들림)
									-- [버그수정] 회전 부호가 반대였음 - 음수(-) 방향이 오히려 땅 아래로 내려가는 방향이었고
									-- 양수(+) 방향이 위로 들리는 방향이었음. 부호를 뒤집어서 실제로 위로 들리도록 수정.
									local raiseStart = os.clock()
									while os.clock() - raiseStart < telegraphDuration do
										local a = math.min(1, (os.clock() - raiseStart) / telegraphDuration)
										local eased = 1 - (1 - a) * (1 - a)
										for si, jointData in ipairs(joints) do
											local liftDeg = (60 + si * 3) * eased
											jointData.motor.C0 = jointData.restC0 * CFrame.Angles(math.rad(liftDeg), 0, 0)
										end
										task.wait(1 / 30)
									end

									if warnRect.Parent then warnRect:Destroy() end
									if border.Parent then border:Destroy() end

									-- 내려찍기 (위로 들었던 자세에서 아래로 확실히 보이는 속도로 내려침)
									-- [수정] 0.15초는 너무 빨라서 거의 안 보였음 -> 0.55초로 늘려서 내려찍는 동작이 눈에 확실히 보이게 함
									local slamDuration = 0.55
									local slamStart = os.clock()
									while os.clock() - slamStart < slamDuration do
										local a = math.min(1, (os.clock() - slamStart) / slamDuration)
										local easedSlam = a * a -- 처음엔 느리게, 끝에 갈수록 빠르게 내려찍히는 가속 느낌
										for si, jointData in ipairs(joints) do
											local liftDeg = (60 + si * 3)
											local slamDeg = -(70 + si * 4)
											local deg = liftDeg + (slamDeg - liftDeg) * easedSlam
											jointData.motor.C0 = jointData.restC0 * CFrame.Angles(math.rad(deg), 0, 0)
										end
										task.wait(1 / 30)
									end
									for si, jointData in ipairs(joints) do
										local slamDeg = -(70 + si * 4)
										jointData.motor.C0 = jointData.restC0 * CFrame.Angles(math.rad(slamDeg), 0, 0)
									end

									-- [버그수정] 다리가 지면을 뚫고 아래까지 내려가버리는 문제 -> 다리 끝(마지막 세그먼트)의
									-- 실제 월드 위치를 측정해서, 지면(floorY) 아래로 파고들면 각도를 줄여가며(이분 탐색)
									-- 정확히 지면 높이에서 멈추도록 보정
									task.wait() -- 물리/렌더링에 최신 C0가 반영되도록 한 프레임 대기
									local lastJoint = joints[#joints]
									local lastSeg = lastJoint and lastJoint.motor.Part1
									if lastSeg then
										local tipBottomY = lastSeg.Position.Y - lastSeg.Size.Y / 2
										if tipBottomY < floorY then
											local lo, hi = 0, 1
											for _ = 1, 8 do
												local mid = (lo + hi) / 2
												for si, jointData in ipairs(joints) do
													local liftDeg = (60 + si * 3)
													local slamDegFull = -(70 + si * 4)
													local deg = liftDeg + (slamDegFull - liftDeg) * mid
													jointData.motor.C0 = jointData.restC0 * CFrame.Angles(math.rad(deg), 0, 0)
												end
												task.wait()
												local by = lastSeg.Position.Y - lastSeg.Size.Y / 2
												if by < floorY then
													hi = mid -- 아직도 지면 아래 -> 각도를 더 줄임
												else
													lo = mid
												end
											end
											for si, jointData in ipairs(joints) do
												local liftDeg = (60 + si * 3)
												local slamDegFull = -(70 + si * 4)
												local deg = liftDeg + (slamDegFull - liftDeg) * lo
												jointData.motor.C0 = jointData.restC0 * CFrame.Angles(math.rad(deg), 0, 0)
											end
										end
									end

									-- 지면 충돌 지점에 콰쾅 바위 타격 이펙트 재생 - 경고 장판과 동일한 직사각형 범위 전체에
									-- 파편/흙먼지가 흩뿌려지도록 함 (원형 크레이터/충격파 X)
									local impactBasePos = Vector3.new(mobRootPos.X, floorY, mobRootPos.Z)
									pcall(function()
										playKrakenRectSmashEffect(impactBasePos, flatDir, rectWidth, rectLength)
									end)

									-- 데미지 판정: 직사각형 경고 장판 영역과 정확히 일치하도록 판정
									-- [수정] 기존엔 -2 스터드 여유값이 있어서 시각적 장판과 실제 판정 범위가 어긋났음.
									-- 장판이 mobRootPos(전방 0)부터 rectLength까지 정확히 이어지므로 그 범위와 완전히 동일하게 맞춤.
									if isAlive then
										local finalHrp = targetPlayer and targetPlayer:FindFirstChild("HumanoidRootPart")
										if finalHrp then
											local toTarget = finalHrp.Position - mobRootPos
											local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
											local forwardDist = flatToTarget:Dot(flatDir)
											local lateralDist = (flatToTarget - flatDir * forwardDist).Magnitude
											if forwardDist >= 0 and forwardDist <= rectLength and lateralDist <= rectWidth / 2 then
												local dmg = config.baseDamage or 220
												local currentPhum = targetPlayer:FindFirstChild("Humanoid")
												if currentPhum and currentPhum.Health > 0 then
													dealDamageToHumanoid(currentPhum, dmg)
													local bounceDir = flatDir
													local hitPlayer = Players:GetPlayerFromCharacter(targetPlayer)
													if hitPlayer then
														local Controllers = ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers")
														local NetController = require(Controllers:WaitForChild("NetController"))
														NetController.FireClient(hitPlayer, "Player.Stun", bounceDir)
													end
												end
											end
										end
									end
									
									-- 잠깐 유지 후 원래 흐느적임 애니메이션으로 자연스럽게 복귀
									task.wait(0.35)
									krakenAttackOverride[ti] = false
								end)
							end
						end

					elseif config.mobModelName == "Poseidon" then
						--========================================================================
						-- [포세이돈 전용 FSM 분기]: 4종 패턴을 우선순위 체인으로 배치 (동시 발동 방지)
						-- 1순위: 체스판 물기둥 (크라켄 재사용, 사거리 무관, 쿨 16초)
						-- 2순위: 소용돌이 급류 (푸른불꽃 기사 회오리 리스킨, 거리<=25, 쿨 12초)
						-- 3순위: 쓰나미 강하 (푸른불꽃 기사 LeapSlam 리스킨, 거리>=18, 쿨 12초)
						-- 4순위: 트라이던트 돌진 찌르기 (기본기, 사거리 이내)
						--========================================================================
						local currentPos = hrp.Position
						local targetPlayerPos = phrp.Position
						local distToPlayer = (currentPos - targetPlayerPos).Magnitude
						local now = os.clock()
						local checkerboardCooldown = config.checkerboardCooldown or 16

						local function playPoseidonSound(soundName)
							pcall(function()
								local sounds = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Sounds")
								local monsterSounds = sounds and sounds:FindFirstChild("Monster")
								local sound = monsterSounds and monsterSounds:FindFirstChild(soundName)
								if sound then
									local sfx = sound:Clone()
									sfx.Parent = hrp
									sfx:Play()
									game.Debris:AddItem(sfx, 3)
								end
							end)
						end

						-- [버그수정] 패턴들이 task.spawn으로 비동기 실행되는 동안 메인 FSM 루프가 계속
						-- 돌면서 다른 패턴이 끼어들어 서로 방해/덮어쓰기 하던 문제 -> 진행 중엔 잠금
						if poseidonPatternBusy then
							-- 아무 패턴도 새로 시작하지 않고 대기 (진행 중인 패턴이 끝날 때까지)
						elseif now - lastCheckerboardTick >= checkerboardCooldown then
							lastCheckerboardTick = now
							lastAttackTick = now
							poseidonPatternBusy = true
							humanoid:MoveTo(currentPos)
							playPoseidonSound("Poseidon_Checkerboard")
							task.spawn(function()
								pcall(playPoseidonCheckerboard, model, targetPlayer)
								poseidonPatternBusy = false
							end)
						elseif distToPlayer <= 25 and (now - lastWhirlwindTick >= 9.0) then
							lastWhirlwindTick = now
							lastAttackTick = now
							poseidonPatternBusy = true
							humanoid:MoveTo(currentPos)
							playPoseidonSound("Poseidon_Whirlpool")
							task.spawn(function()
								pcall(playPoseidonWhirlpool, model, targetPlayer)
								poseidonPatternBusy = false
							end)
						elseif distToPlayer >= 18 and (now - lastTsunamiLeapTick >= 26.0) then
							lastTsunamiLeapTick = now
							lastAttackTick = now
							poseidonPatternBusy = true
							humanoid:MoveTo(currentPos)
							task.spawn(function()
								pcall(playPoseidonTsunamiLeap, model, targetPlayer)
								poseidonPatternBusy = false
							end)
						elseif distToPlayer > 32 then
							-- [버그수정] 예전엔 ATTACK_RANGE(근접 거리) 밖이면 그냥 걷기만 하고, 돌진은
							-- 이미 가까울 때만 나가서 "먼 거리를 좁히는 추격기" 역할을 전혀 못 했음.
							-- 돌진 자체의 사거리(chargeLength=30)만큼은 걷지 않고 돌진으로 좁히도록 함.
							humanoid:MoveTo(Vector3.new(targetPlayerPos.X, currentPos.Y, targetPlayerPos.Z))
						else
							humanoid:MoveTo(currentPos)

							local cooldown = config.attackCooldown or 2.5
							if now - lastAttackTick >= cooldown then
								lastAttackTick = now
								poseidonPatternBusy = true
								playPoseidonSound("Poseidon_Thrust")
								task.spawn(function()
									pcall(playPoseidonThrust, model, targetPlayer)
									poseidonPatternBusy = false
								end)
							end
						end

					else
						--========================================================================
						-- [기타 일반 몬스터 Melee 전투 FSM 분기]
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
												dealDamageToHumanoid(currentPhum, dmg)

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
				if lastTarget ~= nil then
					-- 어그로가 풀렸을 때(포기) 물음표 시각 효과
					task.spawn(function()
						pcall(function()
							local head = model:FindFirstChild("Head")
							local adorneePart = head or hrp
							
							-- 기존 느낌표(!) 제거
							local oldAlert = model:FindFirstChild("AggroAlert", true) or adorneePart:FindFirstChild("AggroAlert")
							if oldAlert then oldAlert:Destroy() end
							
							local billboard = Instance.new("BillboardGui")
							billboard.Name = "AggroLost"
							billboard.Adornee = adorneePart
							billboard.Size = UDim2.new(2, 0, 2, 0)
							
							local extents = model:GetExtentsSize()
							local yOffset
							if head then
								yOffset = head.Size.Y/2 + 1.0
							elseif config.mobModelName == "Jellyfish" then
								-- [버그수정] GetBoundingBox는 비주얼보다 훨씬 큰 Part.Size 기준이라 부정확함.
								-- HRP가 이미 몸통 꼭대기 근처이므로 작은 고정 오프셋만 사용.
								yOffset = 10
							else
								yOffset = extents.Y + 2.0
							end
							billboard.StudsOffset = Vector3.new(0, yOffset, 0)
							billboard.AlwaysOnTop = true
							
							local textLabel = Instance.new("TextLabel")
							textLabel.Size = UDim2.new(1, 0, 1, 0)
							textLabel.BackgroundTransparency = 1
							textLabel.Text = "?"
							textLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
							textLabel.TextScaled = true
							textLabel.Font = Enum.Font.FredokaOne
							textLabel.TextStrokeTransparency = 0
							textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
							textLabel.Parent = billboard
							
							billboard.Parent = hrp
							
							local ts = game:GetService("TweenService")
							ts:Create(billboard, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {StudsOffset = Vector3.new(0, yOffset + 2.0, 0)}):Play()
							
							task.wait(1.0)
							if textLabel and textLabel.Parent then
								ts:Create(textLabel, TweenInfo.new(0.5), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
							end
							task.wait(0.5)
							if billboard then billboard:Destroy() end
						end)
					end)
				end
				lastTarget = nil

				-- [B. 평화 모드] 배회 (Wander) - 스폰 중심(spawnCenter) 기준 랜덤 오프셋 영역으로 자연스럽게 배회합니다.
				local isFlying = (config.mobModelName == "CyclopsBat" or config.mobModelName == "IceDragon" or config.mobModelName == "Jellyfish")
				local wanderRadius = (config.mobModelName == "BlueFlameKnight" or config.mobModelName == "StumpKing" or config.mobModelName == "DesertGuardian" or config.mobModelName == "Kraken" or config.mobModelName == "Poseidon") and 35 or 20

				-- [Jellyfish 전용 수중 배회] PlatformStand + BodyVelocity 3D 유영
				if config.mobModelName == "Jellyfish" then
					humanoid.PlatformStand = true
					local bv = hrp:FindFirstChild("JellyBV")
					if not bv then
						bv = Instance.new("BodyVelocity")
						bv.Name = "JellyBV"
						bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
						bv.P = 8000
						bv.Velocity = Vector3.new(0, 0, 0)
						bv.Parent = hrp
					end
					local wanderTarget = Vector3.new(
						spawnCenter.X + math.random(-20, 20),
						spawnCenter.Y + math.random(-6, 6),
						spawnCenter.Z + math.random(-20, 20)
					)
					local dir = (wanderTarget - hrp.Position)
					bv.Velocity = dir.Magnitude > 2 and (dir.Unit * 5) or Vector3.new(0, 0, 0)
					task.wait(math.random(4, 8))
					continue
				end

				local wanderOffset = Vector3.new(math.random(-wanderRadius, wanderRadius), 0, math.random(-wanderRadius, wanderRadius))
				local nextDest = spawnCenter + wanderOffset

				if not isFlying then
					-- 지면 고도 레이캐스트 투영
					local rayParams = RaycastParams.new()
					rayParams.FilterDescendantsInstances = {model}
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					local rayResult = workspace:Raycast(nextDest + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rayParams)
					if rayResult then
						nextDest = Vector3.new(nextDest.X, rayResult.Position.Y + 0.1, nextDest.Z)
					end
				else
					-- 공중 몬스터 비행 높이 무작위성 추가
					nextDest = Vector3.new(nextDest.X, spawnCenter.Y + math.random(-4, 4), nextDest.Z)
				end

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
					task.wait(math.random(2, 5)) -- 대기 시간 다각화하여 동시에 스파이럴되는 것 방지
				end
			end
		end
	end)

		humanoid.Died:Connect(function()
			isAlive = false
			local key = areaId .. "_" .. index
			if activeMobs[key] == model then
				activeMobs[key] = nil
			end

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
			-- HRP 기준으로 지면 근처 좌표 사용 (GetPivot은 모델 중심이라 공중일 수 있음)
			local deathHrp = model:FindFirstChild("HumanoidRootPart")
			local deathPos = deathHrp and deathHrp.Position or model:GetPivot().Position
			-- 몬스터가 workspace 직하위에 있으므로 바닥 레이캐스트 시 몹 자신을 직접 제외
			local deathRayParams = RaycastParams.new()
			deathRayParams.FilterType = Enum.RaycastFilterType.Exclude
			deathRayParams.FilterDescendantsInstances = { model }
			local deathRay = workspace:Raycast(deathPos + Vector3.new(0, 2, 0), Vector3.new(0, -50, 0), deathRayParams)
			if deathRay then
				deathPos = deathRay.Position + Vector3.new(0, 0.05, 0)
			end
			
			if killer and killer:IsA("Player") then
				local xpReward = config.xpReward or 10
				if PlayerStatService then
					-- [수정] 흰 구슬을 줍는 방식 전면 폐기 -> 처치 즉시 경험치 바로 지급
					if PlayerStatService.grantActionXP then
						PlayerStatService.grantActionXP(killer.UserId, xpReward, {
							source = "CREATURE_KILL",
							actionKey = "MOB:" .. tostring(config.mobId or config.mobModelName or "Mob"),
							disableDiminishing = true,
						})
					end

					if PlayerStatService.incrementKill then
						PlayerStatService.incrementKill(killer.UserId, config.mobDisplayName or "Mob")
					end
					print(string.format("[MobSpawnService] Granted %d XP instantly and updated kills for %s killing %s", xpReward, killer.Name, config.mobDisplayName or "Mob"))
				end
			end

			-- ★ 사망 시 아이템 드롭 처리
			spawnLoot(config.dropTableId or config.mobModelName or "Slime", deathPos, killer)

			-- [사막 수호자 보스 전용 보상]: 5개의 물리 코인 드롭 생성
			if config.mobModelName == "DesertGuardian" then
				task.spawn(function()
					for i = 1, 5 do
						local angle = (i / 5) * math.pi * 2
						local distance = math.random(30, 100) / 10
						local offset = Vector3.new(math.cos(angle) * distance, 1, math.sin(angle) * distance)
						local spawnPos = deathPos + offset
						WorldDropService.spawnDrop(spawnPos, "COIN", 1, nil, nil, "LOOT")
						task.wait(0.05)
					end
				end)
			end

			-- 페이드 아웃 시간(1.5초) 후 시체 모델 완전히 삭제 (보이지 않는 물리 충돌/길막 버그 원천 차단)
			task.delay(1.5, function()
				if model then model:Destroy() end
			end)

			-- 시체가 파괴된 상태로 설정된 리스폰 시간 대기
			local respawnDelay = math.max(config.respawnDelay or 15.0, 1.5)
			task.wait(respawnDelay)

			-- 재스폰 시 원본 MobSpawnData를 다시 읽어 같은 슬롯을 정확히 복구합니다.
			local respawned = false
			for attempt = 1, 3 do
				local ok, newMob = pcall(function()
					return createMobModel(areaId, index, getSpawnConfigForSlot(areaId, index, config))
				end)
				if ok and newMob then
					activeMobs[key] = newMob
					respawned = true
					break
				end
				warn(string.format("[MobSpawnService] Respawn failed for %s_%d (attempt %d): %s", areaId, index, attempt, tostring(newMob)))
				task.wait(3.0)
			end
			if not respawned then
				activeMobs[key] = nil
			end
		end)
	end

	return model
end

function MobSpawnService.Init()
	print("[MobSpawnService] Initializing Dynamic Smart Zone Mob Spawn Service...")

	task.spawn(function()
		task.wait(4.0) -- 에셋 로드 대기
		local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
		local monstersFolder = assetsFolder and assetsFolder:FindFirstChild("Monsters")
		if not monstersFolder then
			warn("[MobSpawnService] Monsters folder NOT found in ReplicatedStorage.Assets!")
		end
	end)

	task.spawn(function()
		task.wait(3.0) -- 에셋 로드 완료를 위해 여유 대기

		local spawnDataList = DataService.get("MobSpawnData")
		if not spawnDataList then return end

		for areaId, config in pairs(spawnDataList) do
			-- 루프 횟수 결정: spawnEntries가 있으면 그것을 우선 사용, 없으면 spawnCount/positions 사용
			local spawnLoopCount = (config.spawnEntries and #config.spawnEntries) or config.spawnCount or (config.spawnPositions and #config.spawnPositions) or 0

			for idx = 1, spawnLoopCount do
				local key = areaId .. "_" .. idx
				activeMobs[key] = createMobModel(areaId, idx, resolveSpawnConfig(config, idx))
			end

			-- print(string.format("[MobSpawnService] Successfully auto-spawned %d Mobs for Area: %s!", spawnLoopCount, areaId))
		end
	end)
end

return MobSpawnService
