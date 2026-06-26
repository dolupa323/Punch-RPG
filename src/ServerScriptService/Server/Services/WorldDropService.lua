-- WorldDropService.lua
-- 월드 드롭 서비스 (서버 권위, SSOT)
-- Cap: Balance.DROP_CAP (400)
-- Merge: Balance.DROP_MERGE_RADIUS (5m)
-- Despawn: DEFAULT 300s, GATHER 600s
-- Inactive: Balance.DROP_INACTIVE_DIST (150m)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Data = ReplicatedStorage:WaitForChild("Data")
local MaterialAttributeData = require(Data.MaterialAttributeData)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local WorldDropService = {}

--========================================
-- 4.1 Dependencies
--========================================
local initialized = false
local NetController = nil
local DataService = nil
local InventoryService = nil
local TimeService = nil
local PlayerStatService = nil -- DNA 수집을 위해 추가
local function _getGoldService()
	return require(Services:WaitForChild("NPCShopService"))
end

--========================================
-- Private State
--========================================
-- drops[dropId] = { dropId, pos, itemId, count, spawnedAt, despawnAt, inactive }
local drops = {}
local dropCount = 0
local mergeGrid = {} -- ["gx_gz"] = { [dropId] = true }

-- Tick 누적
local tickAccumulator = 0
local TICK_INTERVAL = 1  -- 1초 주기

-- Merge grid helper forward declarations (Lua local scope ordering)
local GRID_SIZE = Balance.DROP_INACTIVE_DIST or 150
local getGridKey
local makeGridBucketKey
local indexDropForMerge
local unindexDropForMerge

--========================================
-- Internal: ID 생성
--========================================
local function generateDropId(): string
	return "drop_" .. HttpService:GenerateGUID(false)
end

--========================================
-- Internal: Despawn 시간 계산
--========================================
local function getDespawnSeconds(itemId: string): number
	if itemId == nil then
		return Balance.DROP_DESPAWN_DEFAULT
	end
	local itemData = DataService.getItem(itemId)
	if itemData and itemData.dropDespawn == "GATHER" then
		return Balance.DROP_DESPAWN_GATHER
	end
	return Balance.DROP_DESPAWN_DEFAULT
end

--========================================
-- Internal: 이벤트 발행 (브로드캐스트)
--========================================
local function emitSpawned(drop: any)
	if NetController then
		-- 네트워크 최적화: 400 스터드 내 플레이어에게만 전송
		NetController.FireClientsInRange(drop.pos, 400, "WorldDrop.Spawned", {
			dropId = drop.dropId,
			pos = drop.pos,
			itemId = drop.itemId,
			dropType = drop.dropType,
			dropSource = drop.dropSource, -- [신설] Loot vs Discard 식별용
			goldAmount = drop.goldAmount,
			count = drop.count,
			despawnAt = drop.despawnAt,
			inactive = drop.inactive,
		})
	end
end

local function emitChanged(dropId: string, count: number)
	if NetController then
		local drop = drops[dropId]
		if drop then
			NetController.FireClientsInRange(drop.pos, 400, "WorldDrop.Changed", {
				dropId = dropId,
				count = count,
				goldAmount = drop.goldAmount,
			})
		end
	end
end

local function emitDespawned(dropId: string, reason: string)
	if NetController then
		local drop = drops[dropId]
		if drop then
			NetController.FireClientsInRange(drop.pos, 400, "WorldDrop.Despawned", {
				dropId = dropId,
				reason = reason,
			})
		end
	end
end

--========================================
-- Internal: 거리 계산
--========================================
local function distanceBetween(pos1: Vector3, pos2: Vector3): number
	return (pos1 - pos2).Magnitude
end

--========================================
-- Internal: 병합 대상 찾기
--========================================
local function findMergeTarget(pos: Vector3, itemId: string): any?
	local radius = Balance.DROP_MERGE_RADIUS
	local baseGx, baseGz = getGridKey(pos)
	local gridRange = math.max(1, math.ceil(radius / GRID_SIZE))

	for x = -gridRange, gridRange do
		for z = -gridRange, gridRange do
			local key = makeGridBucketKey(baseGx + x, baseGz + z)
			local bucket = mergeGrid[key]
			if bucket then
				for dropId, _ in pairs(bucket) do
					local drop = drops[dropId]
					if drop and drop.itemId == itemId then
						local dist = distanceBetween(pos, drop.pos)
						if dist <= radius then
							return drop
						end
					end
				end
			end
		end
	end
	return nil
end

--========================================
-- Internal: Cap Prune (오래된 순 제거)
--========================================
local function pruneOldestDrops()
	while dropCount > Balance.DROP_CAP do
		-- spawnedAt 가장 오래된 것 찾기
		local oldest = nil
		local oldestTime = math.huge
		
		for _, drop in pairs(drops) do
			if drop.spawnedAt < oldestTime then
				oldestTime = drop.spawnedAt
				oldest = drop
			end
		end
		
		if oldest then
			emitDespawned(oldest.dropId, "CAP_PRUNE")
			unindexDropForMerge(oldest)
			drops[oldest.dropId] = nil
			dropCount = dropCount - 1
		else
			break
		end
	end
end


--================ : OPTIMIZATION : Spatial Grid ================
function getGridKey(pos: Vector3)
	return math.floor(pos.X / GRID_SIZE), math.floor(pos.Z / GRID_SIZE)
end

function makeGridBucketKey(gx: number, gz: number): string
	return string.format("%d_%d", gx, gz)
end

function indexDropForMerge(drop: any)
	local gx, gz = getGridKey(drop.pos)
	local key = makeGridBucketKey(gx, gz)
	if not mergeGrid[key] then
		mergeGrid[key] = {}
	end
	mergeGrid[key][drop.dropId] = true
	drop.gridKey = key
end

function unindexDropForMerge(drop: any)
	if not drop then
		return
	end

	local key = drop.gridKey
	if not key then
		local gx, gz = getGridKey(drop.pos)
		key = makeGridBucketKey(gx, gz)
	end

	local bucket = mergeGrid[key]
	if bucket then
		bucket[drop.dropId] = nil
		if next(bucket) == nil then
			mergeGrid[key] = nil
		end
	end
end

--========================================
-- Internal: Tick 처리 (1초마다)
--========================================
local function processTick()
	local now = tick()
	local toRemove = {}
	
	-- 1. 유저 위치 그리드 인덱싱 (O(P))
	local activeGrids = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local gx, gz = getGridKey(hrp.Position)
			-- 자신과 주변 8방향 그리드를 활성 상태로 표시
			for x = -1, 1 do
				for z = -1, 1 do
					activeGrids[string.format("%d_%d", gx + x, gz + z)] = true
				end
			end
		end
	end

	-- 2. 드롭 체크 (O(N))
	for dropId, drop in pairs(drops) do
		-- (1) Despawn 타이머 체크
		if now >= drop.despawnAt then
			table.insert(toRemove, { dropId = dropId, reason = "DESPAWN_TIMER" })
		else
			-- (2) Inactive 상태 갱신 (O(1) Grid Lookup)
			-- 유저 근처에 있으면 active, 없으면 inactive
			local gx, gz = getGridKey(drop.pos)
			local key = string.format("%d_%d", gx, gz)
			
			drop.inactive = not activeGrids[key]
		end
	end
	
	-- 제거 처리
	for _, item in ipairs(toRemove) do
		local drop = drops[item.dropId]
		if drop then
			emitDespawned(item.dropId, item.reason)
			unindexDropForMerge(drop)
			drops[item.dropId] = nil
			dropCount = dropCount - 1
		end
	end
	
	-- 3. Cap Prune (오래된 순 제거)
	if dropCount > Balance.DROP_CAP then
		pruneOldestDrops()
	end
end

--========================================
-- Heartbeat 핸들러
--========================================
local function onHeartbeat(dt: number)
	tickAccumulator = tickAccumulator + dt
	
	if tickAccumulator >= TICK_INTERVAL then
		tickAccumulator = tickAccumulator - TICK_INTERVAL
		processTick()
	end
end

--========================================
-- 4.1.5 Helper: Ground Height Raycast
--========================================
--- 지면 높이 구하기 (레이캐스트)
--- 드롭이 지형에 닿도록 위치 조정 (100% 정확한 지면 피팅)
local function getGroundHeight(pos: Vector3): Vector3
	-- 레이캐스트: 죽은 몬스터 위치(또는 유저 위치) 바로 위(10스터드)에서 아래로 100스터드 검색
	-- 하늘(300)에서 쏘면 동굴 지붕을 바닥으로 인식해버리므로, 현재 pos 기준 상대 좌표로 탐색!
	local rayOrigin = pos + Vector3.new(0, 10, 0)
	local rayDirection = Vector3.new(0, -100, 0)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local excludeList = {}
	local Workspace = game:GetService("Workspace")
	
	-- 1. 월드 내의 모든 플레이어 캐릭터 제외 (충돌 제외)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(excludeList, player.Character)
		end
	end
	
	-- 2. 몬스터/크리처 스폰 폴더 제외
	local mobsFolder = Workspace:FindFirstChild("Mobs") or Workspace:FindFirstChild("Creatures") or Workspace:FindFirstChild("NPCs")
	if mobsFolder then
		table.insert(excludeList, mobsFolder)
	end
	
	-- 3. 이미 스폰된 드롭 폴더 및 잔해 제외
	local dropsFolder = Workspace:FindFirstChild("WorldDrops")
	if dropsFolder then
		table.insert(excludeList, dropsFolder)
	end
	
	rayParams.FilterDescendantsInstances = excludeList
	
	local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
	
	if result then
		-- 지면 물리 충돌점 자체를 반환 (클라이언트가 렌더링 시 모델의 절반 크기를 더해 바닥면을 완벽 밀착하므로, 서버는 물리 충돌 좌표 그대로를 줍니다)
		return result.Position + Vector3.new(0, 0.05, 0)
	else
		-- 지면이 없을 경우 안전장치: 몬스터 사망 높이 그대로 사용
		return pos
	end
end

--========================================
-- 4.2 Public API
--========================================

--- 드롭 생성
--- 반환: (success, errorCode?, data?)
function WorldDropService.spawnDrop(pos: Vector3, itemId: string, count: number, durability: number?, sourceLevel: number?, dropSource: string?): (boolean, string?, any?)
	-- [수정] 드롭 위치 자동 조정: 지면과의 높이 맞추기
	local adjustedPos = getGroundHeight(pos)
	
	-- 아이템 존재 검증
	local itemData = DataService.getItem(itemId)
	if not itemData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- count 검증
	if type(count) ~= "number" or count < 1 or count ~= math.floor(count) then
		return false, Enums.ErrorCode.INVALID_COUNT, nil
	end
	
	-- 병합 대상 찾기 (내구도가 있거나 비스택 아이템은 병합 제외 - AMMO만 병합)
	local mergeTarget = nil
	if not durability and itemData.type == "AMMO" then
		mergeTarget = findMergeTarget(adjustedPos, itemId)
	end
	
	if mergeTarget then
		-- 병합
		mergeTarget.count = mergeTarget.count + count
		emitChanged(mergeTarget.dropId, mergeTarget.count)
		return true, nil, { merged = true, dropId = mergeTarget.dropId, count = mergeTarget.count }
	end
	
	-- 재료 속성 롤링 (sourceLevel 기반) — 개별 아이템별로 속성 롤링
	local canHaveAttr = sourceLevel and sourceLevel > 0 and MaterialAttributeData.ItemCategory[itemId]
	
	if canHaveAttr and count > 1 then
		-- count > 1: 개별 롤링 후 동일 속성끼리 그룹화
		local groups = {} -- key = attrId or "__NONE__", value = { attrs = {..} or nil, count = n }
		for _ = 1, count do
			local attr, attrLv = MaterialAttributeData.rollAttribute(itemId, sourceLevel)
			if attr and attrLv then
				local key = attr .. "_" .. tostring(attrLv)
				if groups[key] then
					groups[key].count = groups[key].count + 1
				else
					groups[key] = { attrs = { [attr] = attrLv }, count = 1 }
				end
			else
				if groups["__NONE__"] then
					groups["__NONE__"].count = groups["__NONE__"].count + 1
				else
					groups["__NONE__"] = { attrs = nil, count = 1 }
				end
			end
		end
		
		-- 그룹별 드롭 생성
		local firstResult = nil
		local now = tick()
		local despawnSeconds = getDespawnSeconds(itemId)
		for _, group in pairs(groups) do
			local drop = {
				dropId = generateDropId(),
				pos = adjustedPos,
				itemId = itemId,
				count = group.count,
				durability = durability,
				attributes = group.attrs,
				dropSource = dropSource or "LOOT", -- [신설] 기본값은 사냥 획득("LOOT")
				spawnedAt = now,
				despawnAt = now + despawnSeconds,
				inactive = false,
			}
			drops[drop.dropId] = drop
			dropCount = dropCount + 1
			indexDropForMerge(drop)
			emitSpawned(drop)
			if not firstResult then
				firstResult = { merged = false, dropId = drop.dropId, count = drop.count }
			end
		end
		
		if dropCount > Balance.DROP_CAP then
			pruneOldestDrops()
		end
		
		return true, nil, firstResult
	end
	
	-- count == 1 또는 속성 없는 아이템: 기존 방식
	local attributes = nil
	if canHaveAttr then
		local attr, attrLv = MaterialAttributeData.rollAttribute(itemId, sourceLevel)
		if attr and attrLv then
			attributes = { [attr] = attrLv }
		end
	end
	
	-- 새 드롭 생성
	local now = tick()
	local despawnSeconds = getDespawnSeconds(itemId)
	
	local drop = {
		dropId = generateDropId(),
		pos = adjustedPos,
		itemId = itemId,
		count = count,
		durability = durability,
		attributes = attributes,
		dropSource = dropSource or "LOOT", -- [신설] 기본값은 사냥 획득("LOOT")
		spawnedAt = now,
		despawnAt = now + despawnSeconds,
		inactive = false,
	}
	
	drops[drop.dropId] = drop
	dropCount = dropCount + 1
	indexDropForMerge(drop)
	
	-- Cap 초과 시 prune
	if dropCount > Balance.DROP_CAP then
		pruneOldestDrops()
	end
	
	emitSpawned(drop)
	
	return true, nil, { merged = false, dropId = drop.dropId, count = drop.count }
end

function WorldDropService.spawnGoldDrop(pos: Vector3, amount: number): (boolean, string?, any?)
	local adjustedPos = getGroundHeight(pos)
	local goldAmount = math.max(0, math.floor(tonumber(amount) or 0))
	if goldAmount <= 0 then
		return false, Enums.ErrorCode.INVALID_COUNT, nil
	end

	local now = tick()
	local drop = {
		dropId = generateDropId(),
		pos = adjustedPos,
		dropType = "gold",
		goldAmount = goldAmount,
		count = goldAmount,
		spawnedAt = now,
		despawnAt = now + Balance.DROP_DESPAWN_DEFAULT,
		inactive = false,
	}

	drops[drop.dropId] = drop
	dropCount = dropCount + 1
	indexDropForMerge(drop)

	if dropCount > Balance.DROP_CAP then
		pruneOldestDrops()
	end

	emitSpawned(drop)
	return true, nil, { merged = false, dropId = drop.dropId, count = goldAmount }
end

function WorldDropService.spawnXpOrbs(pos: Vector3, killer: Player, totalXpAmount: number, mobName: string)
	if not killer or totalXpAmount <= 0 then return end
	
	local orbCount = math.clamp(math.ceil(totalXpAmount / 10), 1, 15)
	local xpPerOrb = math.ceil(totalXpAmount / orbCount)
	
	local xpFolder = workspace:FindFirstChild("XPOrbs")
	if not xpFolder then
		xpFolder = Instance.new("Folder")
		xpFolder.Name = "XPOrbs"
		xpFolder.Parent = workspace
	end

	local RunService = game:GetService("RunService")

	for i = 1, orbCount do
		local orbXp = (i == orbCount) and (totalXpAmount - xpPerOrb * (orbCount - 1)) or xpPerOrb
		if orbXp <= 0 then continue end
		
		local orb = Instance.new("Part")
		orb.Name = "XPOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(0.6, 0.6, 0.6)
		orb.Material = Enum.Material.Neon
		orb.Color = Color3.fromRGB(200, 255, 255)
		orb.CanCollide = true
		orb.Massless = true
		orb.Anchored = false
		orb.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.5, 0.2, 1, 1) -- 통통 튀고 구르도록
		
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 255, 255)
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = orb
		
		-- 꼬리(Trail) 추가
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.3, 0)
		a0.Parent = orb
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.3, 0)
		a1.Parent = orb
		
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.35
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(Color3.fromRGB(150, 255, 255))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1)
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0)
		})
		trail.Enabled = false -- 튕겨 나갈 땐 끄고, 흡수될 때 켬
		trail.Parent = orb
		
		-- 몬스터 몸체 중심 쯤에서 팡 터지도록 위치 설정
		orb.Position = pos + Vector3.new(math.random(-5, 5)/10, 1.5, math.random(-5, 5)/10)
		orb.Parent = xpFolder
		
		-- 펑 터지는 물리력 적용 (랜덤하게 사방으로)
		orb.AssemblyLinearVelocity = Vector3.new(math.random(-15, 15), math.random(20, 35), math.random(-15, 15))
		
		local debounce = false
		local connection = nil
		local absorbRange = 25
		local spawnTime = tick()
		local suctionDelay = math.random(8, 18) / 10 -- 0.8초 ~ 1.8초 제각각 딜레이
		local baseSpeed = math.random(4, 10) -- 구슬마다 시작 흡수 속도를 다르게 (대폭 낮춤)
		
		local isSucking = false
		local suctionStartTime = 0
		
		connection = RunService.Heartbeat:Connect(function(dt)
			if not orb or not orb.Parent then
				if connection then connection:Disconnect() end
				return
			end
			
			local elapsedTime = tick() - spawnTime
			if elapsedTime < suctionDelay then return end
			
			local char = killer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = (hrp.Position - orb.Position).Magnitude
				
				-- 범위 안에 들어오거나 이미 빨려가기 시작했다면 끝까지 추적
				if dist < absorbRange or isSucking then
					if not isSucking then
						isSucking = true
						suctionStartTime = tick()
						
						-- 흡수 시작 시 물리 충돌 끄고 꼬리 이펙트 켬
						if not orb.Anchored then
							orb.Anchored = true
							orb.CanCollide = false
							trail.Enabled = true
						end
					end
					
					-- 흡수가 시작된 지점으로부터의 시간으로 속도를 계산 (나중에 와서 먹어도 동일한 속도)
					local suctionTime = tick() - suctionStartTime
					-- 속도 증가폭을 기존 35에서 12로 대폭 낮추어 천천히 날아가게 함
					local currentSpeed = baseSpeed + (suctionTime * 12)
					local dir = (hrp.Position - orb.Position).Unit
					orb.CFrame = orb.CFrame + dir * (currentSpeed * dt)
					
					if dist < 2.5 and not debounce then
						debounce = true
						if connection then connection:Disconnect() end
						orb:Destroy()
						
						if PlayerStatService and PlayerStatService.addXP then
							PlayerStatService.addXP(killer.UserId, orbXp, "Hunt_" .. (mobName or "Mob"))
						end
						
						local hum = char:FindFirstChild("Humanoid")
						if hum then
							local originalSpeed = char:GetAttribute("OriginalWalkSpeed")
							if not originalSpeed then
								originalSpeed = hum.WalkSpeed
								char:SetAttribute("OriginalWalkSpeed", originalSpeed)
							end
							
							hum.WalkSpeed = originalSpeed + 5
							char:SetAttribute("SpeedBuffEndTime", tick() + 1.0)
							
							if not char:GetAttribute("SpeedBuffActive") then
								char:SetAttribute("SpeedBuffActive", true)
								task.spawn(function()
									while char and char.Parent do
										task.wait(0.1)
										local endTime = char:GetAttribute("SpeedBuffEndTime") or 0
										if tick() >= endTime then
											if hum then
												hum.WalkSpeed = char:GetAttribute("OriginalWalkSpeed") or 16
											end
											char:SetAttribute("SpeedBuffActive", nil)
											char:SetAttribute("OriginalWalkSpeed", nil)
											break
										end
									end
								end)
							end
						end
					end
				end
			end
		end)
		
		game:GetService("Debris"):AddItem(orb, 30)
	end
end

--- Loot (아이템 줍기)
--- 반환: (success, errorCode?, data?)
function WorldDropService.loot(player: Player, dropId: string): (boolean, string?, any?)
	local userId = player.UserId
	
	-- 드롭 존재 확인
	local drop = drops[dropId]
	if not drop then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 거리 확인
	local character = player.Character
	if not character then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	-- 거리 확인 (Y축 차이는 다소 관대하게 계산)
	local dropPos2D = Vector3.new(drop.pos.X, 0, drop.pos.Z)
	local playerPos2D = Vector3.new(humanoidRootPart.Position.X, 0, humanoidRootPart.Position.Z)
	local dist2D = (dropPos2D - playerPos2D).Magnitude
	local distY = math.abs(drop.pos.Y - humanoidRootPart.Position.Y)
	
	-- Y축 차이가 20 이하면 2D 거리만 사용, 너무 크면 전체 거리 사용
	local effectiveDist = (distY <= 20) and dist2D or distanceBetween(drop.pos, humanoidRootPart.Position)
	
	if effectiveDist > Balance.DROP_LOOT_RANGE then
		warn(string.format("[WorldDropService] 줍기 실패(OUT_OF_RANGE) - Player: %s, Dist: %.2f (2D: %.2f, Y: %.2f) | DropPos: %s | PlayerPos: %s", 
			player.Name, effectiveDist, dist2D, distY, tostring(drop.pos), tostring(humanoidRootPart.Position)))
		return false, Enums.ErrorCode.OUT_OF_RANGE, nil
	end

	if drop.itemId == "COIN" then
		local goldService = _getGoldService()
		if goldService then
			local currentGold = goldService.getGold(userId)
			if currentGold >= Balance.GOLD_CAP then
				return false, Enums.ErrorCode.GOLD_CAP_REACHED, nil
			end
			local goldAmount = math.min(100, Balance.GOLD_CAP - currentGold)
			local ok, err = goldService.addGold(userId, goldAmount)
			if not ok then
				return false, err, nil
			end
			emitDespawned(dropId, "LOOTED_OUT")
			unindexDropForMerge(drop)
			drops[dropId] = nil
			dropCount = dropCount - 1
			return true, nil, {
				dropId = dropId,
				itemId = "COIN",
				goldAmount = goldAmount,
			}
		end
	end

	if drop.dropType == "gold" then
		local availableGold = math.max(0, math.floor(tonumber(drop.goldAmount or drop.count) or 0))
		if availableGold <= 0 then
			return false, Enums.ErrorCode.NOT_FOUND, nil
		end

		local goldService = _getGoldService()
		local currentGold = goldService.getGold(userId)
		if currentGold >= Balance.GOLD_CAP then
			return false, Enums.ErrorCode.GOLD_CAP_REACHED, nil
		end
		local goldAmount = math.min(availableGold, Balance.GOLD_CAP - currentGold)
		local ok, err = goldService.addGold(userId, goldAmount)
		if not ok then
			return false, err, nil
		end

		local remaining = availableGold - goldAmount
		if remaining > 0 then
			drop.goldAmount = remaining
			drop.count = remaining
			emitChanged(dropId, remaining)
		else
			emitDespawned(dropId, "LOOTED_OUT")
			unindexDropForMerge(drop)
			drops[dropId] = nil
			dropCount = dropCount - 1
		end

		return true, nil, {
			dropId = dropId,
			dropType = "gold",
			goldAmount = goldAmount,
		}
	end

	-- DNA 타입 아이템: 인벤토리에 추가 + 특별 알림
	local itemData = DataService.getItem(drop.itemId)
	if itemData and itemData.type == "DNA" then
		local dropAttrs = (drop.attribute and drop.attributeLevel) and { [drop.attribute] = drop.attributeLevel } or drop.attributes
		local added, remaining = InventoryService.addItem(userId, drop.itemId, drop.count, drop.durability, dropAttrs)
		if added <= 0 then
			return false, Enums.ErrorCode.INV_FULL, nil
		end
		
		-- DNA 획득 특별 알림 (클라이언트에서 대형 연출)
		if NetController then
			NetController.FireClient(player, "DNA.Obtained", {
				itemId = drop.itemId,
				creatureId = itemData.creatureId,
				count = added,
				rarity = itemData.rarity,
			})
		end
		
		if remaining > 0 then
			drop.count = remaining
			emitChanged(dropId, remaining)
		else
			emitDespawned(dropId, "LOOTED_OUT")
			unindexDropForMerge(drop)
			drops[dropId] = nil
			dropCount = dropCount - 1
		end
		
		return true, nil, {
			dropId = dropId,
			itemId = drop.itemId,
			count = added,
			remaining = remaining or 0,
			isDna = true,
		}
	end

	-- 일반 아이템: 인벤토리에 추가
	local dropAttrs2 = (drop.attribute and drop.attributeLevel) and { [drop.attribute] = drop.attributeLevel } or drop.attributes
	print(string.format("[WorldDropService] Attempting to add item to inventory - Player: %s (%d), ItemId: %s, Count: %s, Durability: %s", player.Name, userId, tostring(drop.itemId), tostring(drop.count), tostring(drop.durability)))
	local added, remaining = InventoryService.addItem(userId, drop.itemId, drop.count, drop.durability, dropAttrs2)
	print(string.format("[WorldDropService] AddItem Result - Added: %d, Remaining: %d", added, remaining))
	
	if added <= 0 then
		print("[WorldDropService] AddItem failed - Inventory Full!")
		return false, Enums.ErrorCode.INV_FULL, nil
	end

	if remaining > 0 then
		-- 부분 줍기: 드롭 잔량 업데이트
		drop.count = remaining
		emitChanged(dropId, remaining)
	else
		-- 전량 줍기: 드롭 제거
		emitDespawned(dropId, "LOOTED_OUT")
		unindexDropForMerge(drop)
		drops[dropId] = nil
		dropCount = dropCount - 1
	end
	
	return true, nil, {
		dropId = dropId,
		itemId = drop.itemId,
		count = added,
		remaining = remaining,
	}
end

--- 모든 드롭 제거 (디버그/테스트용)
function WorldDropService.clearAllDrops()
	for dropId, _ in pairs(drops) do
		emitDespawned(dropId, "CLEARED")
	end
	drops = {}
	dropCount = 0
	mergeGrid = {}
end

--- 현재 드롭 수
function WorldDropService.getDropCount(): number
	return dropCount
end

--- 드롭 가져오기 (디버그용)
function WorldDropService.getDrop(dropId: string): any?
	return drops[dropId]
end

--- 모든 드롭 가져오기 (디버그용)
function WorldDropService.getAllDrops(): {any}
	local result = {}
	for _, drop in pairs(drops) do
		table.insert(result, drop)
	end
	return result
end

--========================================
-- 4.3 Debug API (Studio Only)
--========================================

--- 대량 스폰 테스트
function WorldDropService.DebugSpawnMany(itemId: string, countPerDrop: number, numDrops: number)
	for i = 1, numDrops do
		local pos = Vector3.new(
			math.random(-100, 100),
			5,
			math.random(-100, 100)
		)
		WorldDropService.spawnDrop(pos, itemId, countPerDrop)
	end
end

--- 병합 테스트 (같은 위치에 여러 번 스폰)
function WorldDropService.DebugMergeTest(itemId: string, countPerDrop: number, numDrops: number)
	local pos = Vector3.new(0, 5, 0)  -- 고정 위치
	for i = 1, numDrops do
		WorldDropService.spawnDrop(pos, itemId, countPerDrop)
	end
end

--========================================
-- Network Handlers
--========================================

local function handleLoot(player: Player, payload: any)
	local dropId = payload.dropId
	
	if type(dropId) ~= "string" then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = WorldDropService.loot(player, dropId)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleGetActiveDrops(player: Player, payload: any)
	local result = {}
	for _, drop in pairs(drops) do
		table.insert(result, {
			dropId = drop.dropId,
			pos = drop.pos,
			itemId = drop.itemId,
			dropType = drop.dropType,
			goldAmount = drop.goldAmount,
			count = drop.count,
			despawnAt = drop.despawnAt,
			inactive = drop.inactive,
		})
	end
	print(string.format("[WorldDropService] handleGetActiveDrops: Returning %d active drops to player %s", #result, player.Name))
	return { success = true, data = result }
end

--========================================
-- Initialization
--========================================

function WorldDropService.Init(netController: any, dataService: any, inventoryService: any, timeService: any, _PlayerStatService: any)
	if initialized then
		warn("[WorldDropService] Already initialized")
		return
	end
	
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	TimeService = timeService
	PlayerStatService = _PlayerStatService
	
	-- Heartbeat 연결
	RunService.Heartbeat:Connect(onHeartbeat)
	
	initialized = true
	print(string.format("[WorldDropService] Initialized - Cap: %d, MergeRadius: %d, InactiveDist: %d",
		Balance.DROP_CAP, Balance.DROP_MERGE_RADIUS, Balance.DROP_INACTIVE_DIST))
end

function WorldDropService.GetHandlers()
	return {
		["WorldDrop.Loot.Request"] = handleLoot,
		["WorldDrop.GetActiveDrops"] = handleGetActiveDrops,
	}
end

return WorldDropService
