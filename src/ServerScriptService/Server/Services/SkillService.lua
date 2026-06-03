-- SkillService.lua
-- 스킬 트리 서버 서비스
-- 전투 계열 택1 잠금 + SP 소모 해금 + 패시브 보너스 조회

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)

local SkillService = {}

-- Dependencies (injected via Init)
local NetController
local PlayerStatService
local SaveService
local StaminaService
local InventoryService
local DataService

-- 유저별 런타임 캐시 { [userId] = { unlockedSkills={}, combatTreeId=nil, skillPointsSpent=0, activeSkillSlots={} } }
local playerSkillCache = {}
local skillCooldowns = {} -- [userId][itemId] = endTime
local activeRuneAuras = {} -- [userId][itemId] = token

--========================================
-- Internal Helpers
--========================================

local _initPlayerSkills, _autoUnlockFreeSkills, _getAvailableSP, _findSkill, _getTreeIdForSkill, _isCombatTreeId, _arePrereqsMet, _syncToSave

--- 플레이어 스킬 캐시 초기화 (SaveService 데이터 로드)
function _initPlayerSkills(userId: number)
	if playerSkillCache[userId] then return end

	local state = SaveService.getPlayerState(userId)
	if not state then
		playerSkillCache[userId] = {
			unlockedSkills = {},
			combatTreeId = nil,
			skillPointsSpent = 0,
			activeSkillSlots = { nil, nil, nil, nil },
		}
		return
	end

	playerSkillCache[userId] = {
		unlockedSkills = type(state.unlockedSkills) == "table" and state.unlockedSkills or {},
		combatTreeId = state.combatTreeId,
		skillPointsSpent = state.skillPointsSpent or 0,
		activeSkillSlots = type(state.activeSkillSlots) == "table" and state.activeSkillSlots or { nil, nil, nil, nil },
	}

	-- 건축 등 자동 해금 스킬 처리
	_autoUnlockFreeSkills(userId)
end

--- SP 잔여량 계산 (총 획득 - 소모)
function _getAvailableSP(userId: number): number
	_initPlayerSkills(userId)
	local level = PlayerStatService.getLevel(userId) or 1
	local totalEarned = math.max(0, (level - 1) * Balance.SKILL_POINTS_PER_LEVEL)
	return math.max(0, totalEarned - playerSkillCache[userId].skillPointsSpent)
end

--- 스킬 데이터 조회 (모든 트리 탐색)
function _findSkill(skillId: string)
	return SkillTreeData.GetSkill(skillId)
end

--- 스킬이 속한 트리 ID 반환
function _getTreeIdForSkill(skillId: string): string?
	return SkillTreeData.GetTreeIdForSkill(skillId)
end

--- 전투 계열인지 체크
function _isCombatTreeId(treeId: string): boolean
	for _, id in ipairs(SkillTreeData.COMBAT_TREE_IDS) do
		if id == treeId then return true end
	end
	return false
end

--- 선행 스킬 해금 여부 체크
function _arePrereqsMet(userId: number, skill): boolean
	if not skill.prereqs or #skill.prereqs == 0 then return true end
	local cache = playerSkillCache[userId]
	for _, prereqId in ipairs(skill.prereqs) do
		if not cache.unlockedSkills[prereqId] then
			return false
		end
	end
	return true
end

--- SaveService에 스킬 데이터 즉시 반영
function _syncToSave(userId: number)
	local cache = playerSkillCache[userId]
	if not cache then return end

	local state = SaveService.getPlayerState(userId)
	if not state then return end

	state.unlockedSkills = cache.unlockedSkills
	state.combatTreeId = cache.combatTreeId
	state.skillPointsSpent = cache.skillPointsSpent
	state.activeSkillSlots = cache.activeSkillSlots
end

--- 미해금 스킬 중 SP가 0이고 레벨 조건이 충족된 스킬 자동 해금 (건축 등)
function _autoUnlockFreeSkills(userId: number)
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]
	local level = PlayerStatService.getLevel(userId) or 1
	
	local changed = false
	-- 모든 트리 순회하며 자동 해금 대상 검색 (BUILD 트리 등 spCost가 0인 것)
	for _, treeId in ipairs({ "BUILD", "TAMING" }) do
		local tree = SkillTreeData[treeId]
		if tree then
			for _, skill in ipairs(tree) do
				if (skill.spCost == 0 or skill.type == "BUILD_TIER") and not cache.unlockedSkills[skill.id] then
					if level >= (skill.reqLevel or 1) then
						-- 선행 조건 체크
						if _arePrereqsMet(userId, skill) then
							cache.unlockedSkills[skill.id] = true
							changed = true
						end
					end
				end
			end
		end
	end
	
	if changed then
		_syncToSave(userId)
	end
end

--========================================
-- Public API
--========================================

--- 룬 장착 시 스킬 자동 해금 및 슬롯 할당
function SkillService.grantRuneSkill(userId: number, runeItemId: string, equipmentSlotName: string)
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]
	local skillId = "SKILL_" .. runeItemId
	
	-- 스킬 데이터가 있는지 검증
	local skillData = _findSkill(skillId)
	if skillData then
		cache.unlockedSkills[skillId] = true
		
		-- 장착 슬롯에 맞게 액티브 스킬 슬롯에 자동 매핑 (ACTIVE 타입만)
		if skillData.type == "ACTIVE" then
			if equipmentSlotName == "RUNE1" then
				cache.activeSkillSlots[1] = skillId
			elseif equipmentSlotName == "RUNE2" then
				cache.activeSkillSlots[2] = skillId
			elseif equipmentSlotName == "RUNE3" then
				cache.activeSkillSlots[3] = skillId
			end
		end
		
		_syncToSave(userId)
		
		-- 클라이언트에 즉각 업데이트 알림
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player and NetController then
			-- handleGetData 로직을 통해 최신 데이터 전달
			local data = {
				unlockedSkills = cache.unlockedSkills,
				combatTreeId = cache.combatTreeId,
				spAvailable = _getAvailableSP(userId),
				spSpent = cache.skillPointsSpent,
				activeSkillSlots = cache.activeSkillSlots,
				level = (PlayerStatService and PlayerStatService.getLevel(userId)) or 1,
			}
			NetController.FireClient(player, "Skill.Data.Updated", data)
		end
	end
end

--- 룬 해제 시 스킬 회수
function SkillService.revokeRuneSkill(userId: number, runeItemId: string)
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]
	local skillId = "SKILL_" .. runeItemId
	
	if cache.unlockedSkills[skillId] then
		cache.unlockedSkills[skillId] = nil
		
		-- 장착 중인 슬롯에서 해당 스킬 제거
		for i = 1, 4 do
			if cache.activeSkillSlots[i] == skillId then
				cache.activeSkillSlots[i] = nil
			end
		end
		
		_syncToSave(userId)
		
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player and NetController then
			local data = {
				unlockedSkills = cache.unlockedSkills,
				combatTreeId = cache.combatTreeId,
				spAvailable = _getAvailableSP(userId),
				spSpent = cache.skillPointsSpent,
				activeSkillSlots = cache.activeSkillSlots,
				level = (PlayerStatService and PlayerStatService.getLevel(userId)) or 1,
			}
			NetController.FireClient(player, "Skill.Data.Updated", data)
		end
	end
end

--- 해금된 스킬 목록 조회
function SkillService.getUnlockedSkills(userId: number): { [string]: boolean }
	_initPlayerSkills(userId)
	return playerSkillCache[userId].unlockedSkills
end

--- 선택한 전투 계열 ID (nil = 아직 미선택)
function SkillService.getCombatTreeId(userId: number): string?
	_initPlayerSkills(userId)
	return playerSkillCache[userId].combatTreeId
end

--- 잔여 SP
function SkillService.getAvailableSP(userId: number): number
	return _getAvailableSP(userId)
end

--- 특정 스킬 해금 여부
function SkillService.isSkillUnlocked(userId: number, skillId: string): boolean
	_initPlayerSkills(userId)
	return playerSkillCache[userId].unlockedSkills[skillId] == true
end

--- 현재 장착한 무기 타입에 해당하는 해금된 패시브 효과 합산
--- weaponTreeId: "SWORD" | "BOW" | "AXE"
function SkillService.getPassiveBonuses(userId: number, weaponTreeId: string): { [string]: number }
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]
	local bonuses = {}

	-- 해당 무기 계열만 적용 (전투 계열이 다르면 보너스 없음)
	if cache.combatTreeId ~= weaponTreeId then
		return bonuses
	end

	local treeData = SkillTreeData[weaponTreeId]
	if not treeData then return bonuses end

	for _, skill in ipairs(treeData) do
		if skill.type == "PASSIVE" and cache.unlockedSkills[skill.id] then
			for _, eff in ipairs(skill.effects) do
				bonuses[eff.stat] = (bonuses[eff.stat] or 0) + eff.value
			end
		end
	end

	return bonuses
end

--- 액티브 스킬 슬롯 조회
function SkillService.getActiveSkillSlots(userId: number): { string? }
	_initPlayerSkills(userId)
	return playerSkillCache[userId].activeSkillSlots
end

--========================================
-- Handlers
--========================================

--- 스킬 해금 요청 처리
local function handleUnlockSkill(player: Player, payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	local skillId = payload and payload.skillId
	if type(skillId) ~= "string" or skillId == "" then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	-- 스킬 데이터 검증
	local skill = _findSkill(skillId)
	if not skill then
		return { success = false, errorCode = "SKILL_NOT_FOUND" }
	end

	-- 이미 해금?
	if cache.unlockedSkills[skillId] then
		return { success = false, errorCode = "ALREADY_UNLOCKED" }
	end

	-- 건축 계열은 SP 불요, 레벨만 체크
	local treeId = _getTreeIdForSkill(skillId)
	if not treeId then
		return { success = false, errorCode = "SKILL_NOT_FOUND" }
	end

	local level = PlayerStatService.getLevel(userId) or 1

	if skill.type == "BUILD_TIER" then
		-- 건축은 레벨만 체크
		if level < skill.reqLevel then
			return { success = false, errorCode = "LEVEL_TOO_LOW" }
		end
		-- 선행 체크
		if not _arePrereqsMet(userId, skill) then
			return { success = false, errorCode = "PREREQS_NOT_MET" }
		end
		cache.unlockedSkills[skillId] = true
		_syncToSave(userId)
		return { success = true, data = { skillId = skillId, type = "BUILD_TIER" } }
	end

	-- 전투 계열: 택1 잠금 체크
	if _isCombatTreeId(treeId) then
		if cache.combatTreeId and cache.combatTreeId ~= treeId then
			return { success = false, errorCode = "TREE_LOCKED" }
		end

		-- 첫 투자 시 계열 확정 (클라이언트에서 확인 다이얼로그 후 전송)
		if not cache.combatTreeId then
			cache.combatTreeId = treeId
		end
	end

	-- 레벨 체크
	if level < skill.reqLevel then
		return { success = false, errorCode = "LEVEL_TOO_LOW" }
	end

	-- SP 체크
	local available = _getAvailableSP(userId)
	if available < skill.spCost then
		return { success = false, errorCode = "NOT_ENOUGH_SP" }
	end

	-- 선행 체크
	if not _arePrereqsMet(userId, skill) then
		return { success = false, errorCode = "PREREQS_NOT_MET" }
	end

	-- 해금 처리
	cache.unlockedSkills[skillId] = true
	cache.skillPointsSpent = cache.skillPointsSpent + skill.spCost
	_syncToSave(userId)

	print(string.format("[SkillService] %s unlocked skill %s (SP spent: %d, remaining: %d)",
		player.Name, skillId, skill.spCost, _getAvailableSP(userId)))

	return {
		success = true,
		data = {
			skillId = skillId,
			spRemaining = _getAvailableSP(userId),
			combatTreeId = cache.combatTreeId,
		},
	}
end

--- 스킬 데이터 전체 조회 (UI 렌더링용)
local function handleGetData(player: Player, _payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	
	-- 레벨 업 등에 따른 자동 해금 여부 다시 체크
	_autoUnlockFreeSkills(userId)
	
	local cache = playerSkillCache[userId]

	return {
		success = true,
		data = {
			unlockedSkills = cache.unlockedSkills,
			combatTreeId = cache.combatTreeId,
			spAvailable = _getAvailableSP(userId),
			spSpent = cache.skillPointsSpent,
			activeSkillSlots = cache.activeSkillSlots,
			level = PlayerStatService.getLevel(userId) or 1,
		},
	}
end

--- 액티브 스킬 슬롯 설정
local function handleSetSlot(player: Player, payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	local slotIndex = payload and payload.slot
	local skillId = payload and payload.skillId -- nil = 슬롯 비우기

	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return { success = false, errorCode = "BAD_REQUEST" }
	end
	slotIndex = math.floor(slotIndex)

	if skillId ~= nil then
		if type(skillId) ~= "string" then
			return { success = false, errorCode = "BAD_REQUEST" }
		end
		-- 해금 여부 체크
		if not cache.unlockedSkills[skillId] then
			return { success = false, errorCode = "SKILL_NOT_UNLOCKED" }
		end
		-- 액티브 타입만 슬롯 가능
		local skill = _findSkill(skillId)
		if not skill or skill.type ~= "ACTIVE" then
			return { success = false, errorCode = "NOT_ACTIVE_SKILL" }
		end
		-- 이미 다른 슬롯에 장착된 경우 제거
		for i = 1, 4 do
			if cache.activeSkillSlots[i] == skillId then
				cache.activeSkillSlots[i] = nil
			end
		end
	end

	cache.activeSkillSlots[slotIndex] = skillId
	_syncToSave(userId)

	return {
		success = true,
		data = {
			activeSkillSlots = cache.activeSkillSlots,
		},
	}
end

--- [DEV] SP 초기화 요청 처리
local function handleResetSkills(player: Player, _payload: any)
	local userId = player.UserId
	_initPlayerSkills(userId)
	local cache = playerSkillCache[userId]

	-- 1. 투자된 스킬이 존재하여 환급받을 가치가 있는지 검사
	local totalUnlocked = 0
	if cache and cache.unlockedSkills then
		for _ in pairs(cache.unlockedSkills) do
			totalUnlocked = totalUnlocked + 1
		end
	end
	
	if totalUnlocked <= 0 then
		return { success = false, errorCode = "NOTHING_TO_RESET", message = "초기화할 스킬이 없습니다." }
	end

	-- 2. 스킬포인트 초기화권 아이템 (3587361918) 보유량 검사 및 차감
	local InventoryService = nil
	pcall(function()
		InventoryService = require(game:GetService("ServerScriptService").Server.Services.InventoryService)
	end)
	
	if not InventoryService then
		return { success = false, errorCode = "INTERNAL_ERROR" }
	end
	
	local resetTicketId = "3587361918"
	local hasTicket = InventoryService.hasItem(userId, resetTicketId, 1)
	
	if not hasTicket then
		return { success = false, errorCode = "NO_ITEM", message = "스킬초기화권 아이템이 부족합니다." }
	end
	
	-- 아이템 1개 차감결제처리
	local removed = InventoryService.removeItem(userId, resetTicketId, 1)
	if removed < 1 then
		return { success = false, errorCode = "NO_ITEM", message = "스킬초기화권 아이템이 부족합니다." }
	end

	cache.unlockedSkills = {}
	cache.combatTreeId = nil
	cache.skillPointsSpent = 0
	cache.activeSkillSlots = { nil, nil, nil, nil }
	_syncToSave(userId)

	print(string.format("[SkillService] %s RESET all skills (SP refunded, charged ticket %s)", player.Name, resetTicketId))

	return {
		success = true,
		data = {
			unlockedSkills = cache.unlockedSkills,
			combatTreeId = cache.combatTreeId,
			spAvailable = _getAvailableSP(userId),
			spSpent = cache.skillPointsSpent,
			activeSkillSlots = cache.activeSkillSlots,
			level = PlayerStatService.getLevel(userId) or 1,
		},
	}
end

--- 스킬 실행 로직
local function executeSkillEffect(player: Player, itemId: string, payload: any)
	local char = player.Character
	if not char then return end
	
	local itemData = DataService.getItem(itemId)
	if itemData and itemData.runeMode == "AURA" then
		local userId = player.UserId
		local auraDuration = tonumber(itemData.auraDuration) or 8
		local auraTickInterval = math.max(0.25, tonumber(itemData.auraTickInterval) or 0.5)
		local auraRadius = tonumber(itemData.auraRadius) or 10
		local auraHitScale = tonumber(itemData.auraHitScale) or 1.5
		local auraHitRadius = math.max(1, auraRadius * auraHitScale)
		local auraDamage = tonumber(itemData.auraDamage) or 6
		local auraTotalDamageMult = tonumber(itemData.auraTotalDamageMult) or 8.5
		local auraOrbCount = math.max(3, tonumber(itemData.auraOrbCount) or 3)
		local auraOrbitSpeed = tonumber(itemData.auraOrbitSpeed) or 2.2
		local playerStatServiceModule = PlayerStatService
		if not playerStatServiceModule then
			pcall(function()
				playerStatServiceModule = require(script.Parent.PlayerStatService)
			end)
		end
		local auraToken = {}
		activeRuneAuras[userId] = activeRuneAuras[userId] or {}
		activeRuneAuras[userId][itemId] = auraToken

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local avatarFolder = ReplicatedStorage:FindFirstChild("Avatar")
		local vfxFolder = avatarFolder and avatarFolder:FindFirstChild("VFX")
		local hitRemote = vfxFolder and vfxFolder:FindFirstChild("Hit")

		if NetController then
			NetController.FireClient(player, "Rune.Aura.Start", {
				itemId = itemId,
				duration = auraDuration,
				radius = auraRadius,
			})
		end

		task.spawn(function()
			local startAt = os.clock()
			local function pointInTriangleXZ(p, a, b, c)
				local function sign(p1, p2, p3)
					return (p1.X - p3.X) * (p2.Z - p3.Z) - (p2.X - p3.X) * (p1.Z - p3.Z)
				end

				local d1 = sign(p, a, b)
				local d2 = sign(p, b, c)
				local d3 = sign(p, c, a)
				local hasNeg = (d1 < 0) or (d2 < 0) or (d3 < 0)
				local hasPos = (d1 > 0) or (d2 > 0) or (d3 > 0)
				return not (hasNeg and hasPos)
			end

			while os.clock() - startAt < auraDuration do
				if not player.Parent then break end
				if not activeRuneAuras[userId] or activeRuneAuras[userId][itemId] ~= auraToken then
					break
				end

				local currentChar = player.Character
				local hrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
				local hum = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
				if not currentChar or not hrp or not hum or hum.Health <= 0 then
					break
				end

				local attackMult = 1.0
				if playerStatServiceModule then
					local calc = playerStatServiceModule.GetCalculatedStats(userId)
					attackMult = calc.attackMult or 1.0
				end

				local equipment = InventoryService and InventoryService.getEquipment and InventoryService.getEquipment(userId)
				local equippedWeapon = equipment and equipment.HAND
				local weaponBase = equippedWeapon and DataService.getItem(equippedWeapon.itemId)
				local weaponDmg = weaponBase and (weaponBase.damage or weaponBase.baseDamage) or 10
				if equippedWeapon then
					local quality = (equippedWeapon.attributes and equippedWeapon.attributes.quality) or 100
					weaponDmg = math.floor(weaponDmg * (quality / 100))
				end
				local enhanceLevel = equippedWeapon and equippedWeapon.attributes and equippedWeapon.attributes.enhanceLevel or 0
				local DataHelper = require(game:GetService("ReplicatedStorage").Shared.Util.DataHelper)
				local bonusRate = DataHelper.GetEnhanceBonusRate(weaponBase and weaponBase.rarity or "COMMON")
				local auraBaseDamage = (weaponDmg * (1 + enhanceLevel * bonusRate)) + auraDamage
				local totalAuraDamage = auraBaseDamage * attackMult * auraTotalDamageMult
				local ticksPossible = math.max(1, math.floor(auraDuration / auraTickInterval + 0.5))
				local finalTickDamage = math.max(1, math.floor(totalAuraDamage / ticksPossible))
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { currentChar }

				local elapsed = os.clock() - startAt
				local orbPositions = table.create(auraOrbCount)
				for orbIndex = 1, auraOrbCount do
					local offsetAngle = (elapsed * auraOrbitSpeed) + ((orbIndex - 1) * ((math.pi * 2) / auraOrbCount))
					local yOffset = math.sin(elapsed * 2 + orbIndex) * 0.6 + 2.2
					orbPositions[orbIndex] = hrp.Position + Vector3.new(
						math.cos(offsetAngle) * auraHitRadius,
						yOffset,
						math.sin(offsetAngle) * auraHitRadius
					)
				end

				local nearbyParts = workspace:GetPartBoundsInRadius(hrp.Position, auraHitRadius + 4, params)
				local hitHumanoids = {}
				local hitAny = false
				local triA = orbPositions[1]
				local triB = orbPositions[2]
				local triC = orbPositions[3]

				for _, part in ipairs(nearbyParts) do
					local model = part:FindFirstAncestorOfClass("Model")
					if model and model ~= currentChar and model:GetAttribute("MobId") then
						local targetHum = model:FindFirstChildOfClass("Humanoid")
						local targetRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or part
						local targetPos = targetRoot and targetRoot.Position
						local inAura = targetPos and triA and triB and triC and pointInTriangleXZ(targetPos, triA, triB, triC)

						if targetHum and targetHum.Health > 0 and inAura and not hitHumanoids[targetHum] then
							hitHumanoids[targetHum] = true
							hitAny = true

							local wasAlive = targetHum.Health > 0
							local tag = targetHum:FindFirstChild("creator")
							if tag then tag:Destroy() end
							tag = Instance.new("ObjectValue")
							tag.Name = "creator"
							tag.Value = player
							tag.Parent = targetHum
							game:GetService("Debris"):AddItem(tag, 2)

							targetHum:TakeDamage(finalTickDamage)
							print(string.format("[SkillService][Aura] %s hit %s for %d", tostring(itemId), model.Name, finalTickDamage))

							if wasAlive and targetHum.Health <= 0 then
								local xpReward = model:GetAttribute("XPReward") or 25
								if playerStatServiceModule and playerStatServiceModule.grantActionXP then
									local mobId = model:GetAttribute("MobId") or model.Name
									playerStatServiceModule.grantActionXP(userId, xpReward, {
										source = "RUNE_AURA_KILL",
										actionKey = "AURA:" .. tostring(itemId) .. ":" .. tostring(mobId),
										disableDiminishing = true
									})
								end
							end

							if hitRemote then
								local vfxPos = (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
									and ((model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart).Position)
									or hrp.Position
								hitRemote:FireAllClients({
									target = model,
									element = "Skill",
									position = vfxPos,
									damage = finalTickDamage,
									isCritical = false,
									skillId = itemId,
									isMiss = false,
									hideVfx = false,
								})
							end
						end
					end
				end

				if not hitAny then
					print(string.format("[SkillService][Aura] %s no-hit tick (radius=%.2f, parts=%d)", tostring(itemId), auraHitRadius, #nearbyParts))
				end

				task.wait(auraTickInterval)
			end

			if activeRuneAuras[userId] then
				activeRuneAuras[userId][itemId] = nil
			end
			if NetController then
				NetController.FireClient(player, "Rune.Aura.Stop", {
					itemId = itemId,
				})
			end
		end)

		return
	end

	if itemId == "EMBER" or itemId == "DROPLET" or itemId == "NIGHT" then
		-- Rune VFX & Damage logic
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		
		local dir = payload.aimDirection or { x = 0, y = 0, z = 0 }
		local look = Vector3.new(dir.x, dir.y, dir.z)
		if look.Magnitude < 0.1 then look = hrp.CFrame.LookVector end
		
		local vfxName = "Fireball"
		local dmgAmount = 25
		local skillColor = Color3.fromRGB(255, 100, 50)
		
		if itemId == "DROPLET" then
			vfxName = "WaterWave"
			dmgAmount = 20
			skillColor = Color3.fromRGB(50, 150, 255)
			-- 힐 로직
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.1)
			end
		elseif itemId == "NIGHT" then
			vfxName = "NightSpike"
			dmgAmount = 35
			skillColor = Color3.fromRGB(138, 43, 226)
		end
		
		-- (클라이언트가 미리 캐스팅 애니메이션/VFX/사운드를 재생했으므로 서버 연출은 생략)
		
		-- [데미지 계산]
		-- 1. 무기 기본 데미지 가져오기
		local InventoryService = require(script.Parent.InventoryService)
		local DataService = require(script.Parent.DataService)
		
		local equipment = InventoryService.getEquipment(player.UserId)
		local equippedWeapon = equipment and equipment.HAND
		local weaponBase = equippedWeapon and DataService.getItem(equippedWeapon.itemId)
		local weaponDmg = weaponBase and (weaponBase.damage or weaponBase.baseDamage) or 10
		
		if equippedWeapon then
			local quality = (equippedWeapon.attributes and equippedWeapon.attributes.quality) or 100
			weaponDmg = math.floor(weaponDmg * (quality / 100))
		end
		
		local enhanceLevel = equippedWeapon and equippedWeapon.attributes and equippedWeapon.attributes.enhanceLevel or 0
		
		-- 무기 데미지 + 스킬 고유 베이스 데미지 (dmgAmount)
		local DataHelper = require(game:GetService("ReplicatedStorage").Shared.Util.DataHelper)
		local bonusRate = DataHelper.GetEnhanceBonusRate(weaponBase and weaponBase.rarity or "COMMON")
		local finalDamage = (weaponDmg * (1 + enhanceLevel * bonusRate)) + dmgAmount
		
		-- 2. 스탯 보너스 및 치명타 확률/데미지 가져오기 (고정 스탯)
		local attackMult = 1.0
		local critChance = 0
		local critDamageMult = 0
		
		local success, PlayerStatService = pcall(function()
			return require(script.Parent.PlayerStatService)
		end)
		
		if success and PlayerStatService then
			local calc = PlayerStatService.GetCalculatedStats(player.UserId)
			attackMult = calc.attackMult or 1.0
			critChance = calc.critChance or 0
			critDamageMult = calc.critDamageMult or 0
		end
		
		-- 기본 스킬 데미지 (무기 데미지에 2.0배 배율 적용)
		local baseSkillDamage = finalDamage * attackMult * 2.0
		
		-- [VFX 발동 위치 고정] 플레이어가 캐스팅 후 이동해도 폭발 위치는 발사했던 시점의 도착지점으로 고정
		local hitPos = hrp.Position + look * 15
		
		-- Damage logic (4타 멀티 히트)
		task.spawn(function()
			for hitIndex = 1, 4 do
				local radius = 15 -- 넓은 광역 폭발
				
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = {char}
				
				local nearbyParts = workspace:GetPartBoundsInRadius(hitPos, radius, params)
				local hitHumanoids = {}
				
				local ReplicatedStorage = game:GetService("ReplicatedStorage")
				local avatarFolder = ReplicatedStorage:FindFirstChild("Avatar")
				local vfxFolder = avatarFolder and avatarFolder:FindFirstChild("VFX")
				local vfxRemote = vfxFolder and vfxFolder:FindFirstChild("Hit")
				
				local hitAny = false
				
				for _, part in ipairs(nearbyParts) do
					local model = part:FindFirstAncestorOfClass("Model")
					if model then
						local hum = model:FindFirstChildOfClass("Humanoid")
						-- 체력이 0이하인 시체도 타격하여 4타의 데미지 텍스트가 모두 표기되도록 허용
						if hum and not hitHumanoids[hum] then
							local isFirstHit = not hitAny
							hitHumanoids[hum] = true
							hitAny = true
							
							-- [타겟별 개별 데미지/치명타 연산]
							local hitDmg = baseSkillDamage
							local variance = 0.15
							hitDmg = hitDmg * (1 + (math.random() * 2 - 1) * variance)
							
							local hitCrit = false
							if critChance > 0 and math.random() < critChance then
								hitCrit = true
								hitDmg = hitDmg * (1.5 + critDamageMult)
							end
							local finalHitDmg = math.max(1, math.floor(hitDmg))
							
							local wasAlive = hum.Health > 0
							
							local tag = hum:FindFirstChild("creator")
							if tag then tag:Destroy() end
							
							tag = Instance.new("ObjectValue")
							tag.Name = "creator"
							tag.Value = player
							tag.Parent = hum
							game:GetService("Debris"):AddItem(tag, 2)
							
							hum:TakeDamage(finalHitDmg)
							print(string.format("[SkillService] %s hit %d/4: %s | Dmg: %d | Crit: %s", vfxName, hitIndex, model.Name, finalHitDmg, tostring(hitCrit)))
							
							-- 방금 일격으로 죽었을 때만 경험치 1회 지급 (시체 타격 중복 지급 방지)
							if wasAlive and hum.Health <= 0 then
								local xpReward = model:GetAttribute("XPReward") or 25
								if PlayerStatService and PlayerStatService.grantActionXP then
									local mobId = model:GetAttribute("MobId") or model.Name
									PlayerStatService.grantActionXP(player.UserId, xpReward, {
										source = "CREATURE_KILL",
										actionKey = "MOB:" .. tostring(mobId),
										disableDiminishing = true
									})
								end
							end
							
							-- [타겟별 VFX 발송] (맞은 몬스터마다 각각 데미지 텍스트 출력!)
							if vfxRemote then
								local targetHrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
								local vfxPos = targetHrp and targetHrp.Position or hitPos
								vfxPos = vfxPos + Vector3.new((math.random() - 0.5)*3, (math.random() - 0.5)*3, (math.random() - 0.5)*3)
								
								vfxRemote:FireAllClients({
									target = model,
									element = "Skill",
									position = vfxPos,
									damage = finalHitDmg,
									isCritical = hitCrit,
									skillId = itemId,
									isMiss = false,
									hideVfx = not isFirstHit
								})
							end
						end
					end
				end
				
				-- 맞은 적이 하나도 없을 경우 (허공 폭발)
				if not hitAny and vfxRemote then
					local vfxPos = hitPos + Vector3.new((math.random() - 0.5)*5, (math.random() - 0.5)*5, (math.random() - 0.5)*5)
					
					vfxRemote:FireAllClients({
						target = char,
						element = "Skill",
						position = vfxPos,
						damage = 0,
						isCritical = false,
						skillId = itemId,
						isMiss = true
					})
				end
				
				task.wait(0.15) -- 0.15초 간격으로 총 4번 타격
			end
			
			print(string.format("[SkillService] %s exploded at %s", vfxName, tostring(hitPos)))
		end)
	end
end

--- 스킬 사용 요청 처리
local function handleUseSkill(player: Player, payload: any)
	local userId = player.UserId
	local slot = payload and payload.slot -- "RUNE1", "RUNE2", "RUNE3"
	local itemId = payload and payload.itemId
	
	if not slot or not itemId then return { success = false, errorCode = "BAD_REQUEST" } end
	
	-- 1. 장착 확인
	local equip = InventoryService.getEquipment(userId)
	local equippedItem = equip[slot]
	
	if not equippedItem or equippedItem.itemId ~= itemId then
		return { success = false, errorCode = "NOT_EQUIPPED" }
	end
	
	-- 2. 아이템 데이터 확인 (ACTIVE 룬인지)
	local itemData = DataService.getItem(itemId)
	if not itemData or itemData.runeType ~= "ACTIVE" then
		return { success = false, errorCode = "INVALID_SKILL" }
	end
	
	-- 3. 쿨다운 확인
	local now = tick()
	if not skillCooldowns[userId] then skillCooldowns[userId] = {} end
	if skillCooldowns[userId][itemId] and now < skillCooldowns[userId][itemId] then
		return { success = false, errorCode = "COOLDOWN" }
	end
	
	-- 4. 기력(마나) 소모 확인
	local cost = 15 -- Default rune cost
	if not StaminaService.hasEnoughStamina(userId, cost) then
		return { success = false, errorCode = "NOT_ENOUGH_STAMINA" }
	end
	StaminaService.consumeStamina(userId, cost)
	
	-- 5. 쿨다운 설정 (임시 5초)
	local cooldown = itemData.cooldown or 5
	skillCooldowns[userId][itemId] = now + cooldown
	
	-- 6. 스킬 실행
	task.spawn(executeSkillEffect, player, itemId, payload)
	
	return {
		success = true,
		data = {
			cooldown = cooldown
		}
	}
end

--========================================
-- Init / GetHandlers
--========================================

function SkillService.GetHandlers()
	return {
		["Skill.Unlock.Request"] = handleUnlockSkill,
		["Skill.GetData.Request"] = handleGetData,
		["Skill.SetSlot.Request"] = handleSetSlot,
		["Skill.Reset.Request"] = handleResetSkills,
		["Skill.Use.Request"] = handleUseSkill,
	}
end

function SkillService.Init(_NetController, _PlayerStatService, _SaveService)
	NetController = _NetController
	PlayerStatService = _PlayerStatService
	SaveService = _SaveService

	local Services = game:GetService("ServerScriptService").Server.Services
	StaminaService = require(Services.StaminaService)
	InventoryService = require(Services.InventoryService)
	DataService = require(Services.DataService)

	local Players = game:GetService("Players")
	
	-- [신규 아키텍처] SaveService 완료 이벤트 연동
	SaveService.PlayerSaveLoaded.Event:Connect(function(userId, state)
		_initPlayerSkills(userId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		SkillService.onPlayerRemoving(player.UserId)
	end)

	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("DataLoaded") then
			_initPlayerSkills(player.UserId)
		end
	end

	print("[SkillService] Initialized with Stamina/Mana integration")
end

--- 플레이어 정리 (로그아웃 시 캐시 해제)
function SkillService.onPlayerRemoving(userId: number)
	playerSkillCache[userId] = nil
	activeRuneAuras[userId] = nil
end

return SkillService
