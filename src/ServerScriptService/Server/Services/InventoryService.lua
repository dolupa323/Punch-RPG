-- InventoryService.lua
-- ?�벤?�리 ?�비??(?�버 권위, SSOT)
-- ?�롯 ?? 기본 60�? ?�텟 ?�자�?최�? 120�?
-- 최�? ?�택: Balance.MAX_STACK (99)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local InventoryService = {}

--========================================
-- Private State
--========================================
local initialized = false
local playerInventories = {}  -- [userId] = { slots = { [1] = {itemId, count}, ... }, equipment = { Head, Body, Feet, Hand } }
local playerFoodCooldowns = {} -- [userId] = os.clock() last eaten time
local playerRuneCooldowns = {} -- [userId] = timestamp (os.clock() + 10)

-- NetController 참조
local NetController = nil
-- DataService 참조 (?�이??검증용)
local DataService = nil
-- SaveService 참조 (?�속??
local SaveService = nil
-- PlayerStatService 참조 (?�탯??
local PlayerStatService = nil
-- NPCShopService 참조 (골드 지급용)
local NPCShopService = nil
-- EquipService 참조 (?�각?�용)
local EquipService = nil
-- ?�토리얼/?�스?�용 ?�이???�득 콜백
local questItemCallback = nil
local questFoodEatenCallback = nil

local DEBUG_ITEM_GRANT_ADMIN_IDS = {
	[10311679477] = true,
}

local function _canUseDebugGrant(player: Player): boolean
	return RunService:IsStudio() or Balance.ADMIN_IDS[player.UserId] == true
end

local function _getDefaultEquipment()
	return {
		EARRING = nil,
		SUIT = nil,
		HAND = nil,
		NECKLACE = nil,
		RING1 = nil,
		RING2 = nil,
		RUNE1 = nil,
		RUNE2 = nil,
		RUNE3 = nil,
	}
end

local function _normalizeQuickslots(quickslots: any): {string}
	local normalized = { "", "", "" }
	if type(quickslots) ~= "table" then
		return normalized
	end

	for i = 1, 3 do
		local value = quickslots[i]
		if value == nil or value == "" then
			value = quickslots[tostring(i)]
		end
		if type(value) == "string" and value ~= "" then
			normalized[i] = value
		end
	end

	return normalized
end

local HOTBAR_SLOT_MAX = 8

local function _isArmorItemId(itemId: string): boolean
	if not (DataService and DataService.getItem and itemId) then
		return false
	end
	local itemData = DataService.getItem(itemId)
	return itemData and itemData.type == "ARMOR" or false
end

--- 아이템 스택 가능 여부 (탄약 + 명시적 stackable 플래그 + maxStack이 1보다 큰 기초 자원 및 기타 아이템 허용)
local function _isStackable(itemId: string): boolean
	if not (DataService and DataService.getItem and itemId) then
		return false
	end
	local itemData = DataService.getItem(itemId)
	if not itemData then
		return false
	end
	if itemData.durability then
		return false
	end
	if itemData.type == "AMMO" then
		return true
	end
	if itemData.stackable == true then
		return true
	end
	-- maxStack이 1보다 큰 경우 기본적으로 스택이 가능한 아이템으로 취급
	if itemData.maxStack and itemData.maxStack > 1 then
		return true
	end
	return false
end

--- 아이템별 최대 스택 수량
local function _getMaxStack(itemId: string): number
	if not _isStackable(itemId) then return 1 end
	if DataService then
		local itemData = DataService.getItem(itemId)
		if itemData and itemData.maxStack then return itemData.maxStack end
	end
	return Balance.MAX_STACK
end

local function _cloneSlotData(slotData)
	if type(slotData) ~= "table" then
		return nil
	end

	return {
		itemId = slotData.itemId,
		count = slotData.count,
		durability = slotData.durability,
		attributes = slotData.attributes,
	}
end

local function _cloneInventorySlots(inv, ignoreSlot: number?)
	local cloned = {}
	if type(inv) ~= "table" or type(inv.slots) ~= "table" then
		return cloned
	end

	for slot, slotData in pairs(inv.slots) do
		if ignoreSlot == nil or slot ~= ignoreSlot then
			cloned[slot] = _cloneSlotData(slotData)
		end
	end

	return cloned
end

local function _simulateAddItemToSlots(slots, maxSlots: number, itemId: string, count: number, durability: number?, attributes: any?): boolean
	if type(slots) ~= "table" or not itemId or count <= 0 then
		return false
	end

	local remaining = count
	local stackable = _isStackable(itemId)
	local itemMaxStack = _getMaxStack(itemId)

	if stackable and not durability then
		for slot = 1, maxSlots do
			if remaining <= 0 then break end

			local slotData = slots[slot]
			if slotData and slotData.itemId == itemId and slotData.count < itemMaxStack and not slotData.durability then
				local canAddByStack = itemMaxStack - slotData.count
				local canAdd = math.min(remaining, canAddByStack)
				if canAdd > 0 then
					slotData.count = slotData.count + canAdd
					remaining = remaining - canAdd
				end
			end
		end
	end

	for slot = 1, maxSlots do
		if remaining <= 0 then break end

		if slots[slot] == nil then
			local canAdd = stackable and math.min(remaining, itemMaxStack) or 1
			if canAdd <= 0 then break end

			slots[slot] = {
				itemId = itemId,
				count = canAdd,
				durability = durability,
				attributes = attributes,
			}
			remaining = remaining - canAdd
		end
	end

	return remaining <= 0
end

local function _canAddRewardBundle(userId: number, rewards: { [number]: any }, ignoreSlot: number?): boolean
	local inv = playerInventories[userId]
	if not inv then return false end

	local slots = _cloneInventorySlots(inv, ignoreSlot)
	local maxSlots = Balance.BASE_INV_SLOTS
	if PlayerStatService and PlayerStatService.GetCalculatedStats then
		local ok, calc = pcall(function()
			return PlayerStatService.GetCalculatedStats(userId)
		end)
		if ok and type(calc) == "table" and calc.maxSlots then
			maxSlots = calc.maxSlots
		end
	end

	for _, reward in ipairs(rewards or {}) do
		local itemId = reward and reward.itemId
		local amount = tonumber(reward and reward.count) or 1
		if type(itemId) ~= "string" or itemId == "" then
			return false
		end
		if not _simulateAddItemToSlots(slots, maxSlots, itemId, amount, reward and reward.durability, reward and reward.attributes) then
			return false
		end
	end

	return true
end

local function _normalizeEquipmentSlots(equipment: any): any
	local normalized = _getDefaultEquipment()
	if type(equipment) ~= "table" then
		return normalized
	end

	-- EARRING (기존 HEAD 마이그레이션 지원)
	normalized.EARRING = equipment.EARRING or equipment.Earring or equipment.HEAD or equipment.Head
	normalized.SUIT = equipment.SUIT or equipment.Suit
	normalized.HAND = equipment.HAND or equipment.Hand
	normalized.NECKLACE = equipment.NECKLACE or equipment.Necklace
	normalized.RING1 = equipment.RING1 or equipment.Ring1
	normalized.RING2 = equipment.RING2 or equipment.Ring2
	normalized.RUNE1 = equipment.RUNE1 or equipment.Rune1
	normalized.RUNE2 = equipment.RUNE2 or equipment.Rune2
	normalized.RUNE3 = equipment.RUNE3 or equipment.Rune3

	return normalized
end

--========================================
-- Internal: Validation Functions
--========================================

--- ?�롯 범위 검�?(1 ~ MAX_INV_SLOTS)
local function _validateSlotRange(slot: number): (boolean, string?)
	if type(slot) ~= "number" then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	if slot < 1 or slot > Balance.MAX_INV_SLOTS or slot ~= math.floor(slot) then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	return true, nil
end

--- ?�롯???�이?�이 ?�는지 검�?
local function _validateHasItem(inv: any, slot: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData == nil then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	return true, nil
end

--- ?�롯??비어?�는지 검�?
local function _validateSlotEmpty(inv: any, slot: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData ~= nil then
		return false, Enums.ErrorCode.SLOT_NOT_EMPTY
	end
	return true, nil
end

--- ?�량???�효?��? 검�?
local function _validateCount(count: number?): (boolean, string?)
	if count == nil then
		return true, nil  -- nil?� "?�체"�??��?
	end
	if type(count) ~= "number" then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	if count < 1 or count ~= math.floor(count) then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	return true, nil
end

--- ?�용 가?�한 ?�량 검�?
local function _validateCountAvailable(inv: any, slot: number, count: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData == nil then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	if count > slotData.count then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	return true, nil
end

--========================================
-- Internal: Slot Calculations
--========================================

--- ?�벤?�리 ?�용 중인 �???계산
local function _getUsedSlots(inv: any): number
	local count = 0
	for _, slotData in pairs(inv.slots) do
		if slotData then
			count = count + 1
		end
	end
	return count
end

--- ?�레?�어 최�? ?�벤?�리 �???조회
local function _getMaxSlots(userId: number): number
	if PlayerStatService then
		local stats = PlayerStatService.GetCalculatedStats(userId)
		return stats.maxSlots or Balance.BASE_INV_SLOTS
	end
	return Balance.BASE_INV_SLOTS
end

--========================================
-- Internal: Apply Functions (Atomic)
--========================================

--- ?�롯 ?�정 (?��???
local function _setSlot(inv: any, slot: number, itemId: string?, count: number?, durability: number?, attributes: any?)
	if itemId == nil or count == nil or count <= 0 then
		inv.slots[slot] = nil
	else
		inv.slots[slot] = {
			itemId = itemId,
			count = count,
			durability = durability,
			attributes = attributes,
		}
	end
end

--- ?�롯?�서 ?�량 감소
local function _decreaseSlot(inv: any, slot: number, count: number)
	local slotData = inv.slots[slot]
	if slotData then
		local newCount = slotData.count - count
		if newCount <= 0 then
			inv.slots[slot] = nil
		else
			slotData.count = newCount
		end
	end
end

--- ?�롯???�량 증�? (?�는 ?�로 ?�성)
local function _increaseSlot(inv: any, slot: number, itemId: string, count: number, durability: number?, attributes: any?)
	local slotData = inv.slots[slot]
	if slotData then
		slotData.count = slotData.count + count
	else
		inv.slots[slot] = {
			itemId = itemId,
			count = count,
			durability = durability,
			attributes = attributes,
		}
	end
end

--========================================
-- Internal: Emit Events
--========================================

--- 변경된 ?롯 ?? ?벤??발생 ?SaveService ?기??
local function _emitChanged(player: Player, changes: {{slot: number, itemId: string?, count: number?, empty: boolean?}}, fullSyncData: any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	-- SaveService ?기??
	if SaveService and inv then
		SaveService.updatePlayerState(userId, function(state)
			state.inventory = inv.slots
			state.equipment = inv.equipment
			return state
		end)
	end

	-- [HOTBAR REMOVED] 핫바 연동은 장비창 기반 시각화로 대체되므로 처리 생략

	if NetController then
		local usedSlots = _getUsedSlots(inv)
		local maxSlots = _getMaxSlots(userId)

		local payload = {
			userId = userId,
			usedSlots = usedSlots,
			maxSlots = maxSlots,
		}
		
		if fullSyncData then
			payload.fullInventory = fullSyncData
		else
			payload.changes = changes
		end

		NetController.FireClient(player, "Inventory.Changed", payload)
	end
end

--- ?롯 ?이?? 변????변??
local function _makeChange(inv: any, slot: number): {slot: number, itemId: string?, count: number?, empty: boolean?, durability: number?}
	local slotData = inv.slots[slot]
	if slotData then
		return { slot = slot, itemId = slotData.itemId, count = slotData.count, durability = slotData.durability, attributes = slotData.attributes }
	else
		return { slot = slot, empty = true }
	end
end

function InventoryService.getEquipment(userId: number)
	local inv = playerInventories[userId]
	return inv and inv.equipment or {}
end

--- 장착 중인 모든 장비의 속성 보너스 합산
function InventoryService.getEquipmentAttributeBonuses(userId: number)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return {} end
	
	local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data").MaterialAttributeData)
	local totalBonuses = {
		damageMult = 0,
		critChance = 0,
		critDamageMult = 0,
		durabilityMult = 0,
		maxHealthMult = 0,
		defenseMult = 0,
	}
	
	for _, item in pairs(inv.equipment) do
		if item.attributes then
			for attrId, level in pairs(item.attributes) do
				local fx = MaterialAttributeData.getEffectValues(attrId, level)
				if fx then
					for statKey, value in pairs(fx) do
						if totalBonuses[statKey] ~= nil then
							totalBonuses[statKey] = totalBonuses[statKey] + value
						end
					end
				end
			end
		end
	end
	
	return totalBonuses
end

--- 장착 중인 모든 장비의 기본 스탯 보너스(ItemData에 선언된 maxHealth, critChance 등) 합산
function InventoryService.getEquipmentBaseStats(userId: number)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return { maxHealth = 0, critChance = 0 } end
	
	local hp = 0
	local crit = 0
	local critDmgMult = 0
	
	for _, item in pairs(inv.equipment) do
		local data = DataService.getItem(item.itemId)
		if data then
			local quality = (item.attributes and item.attributes.quality) or 100
			local qMult = quality / 100
			if data.maxHealth then
				hp = hp + math.floor(data.maxHealth * qMult)
			end
			if data.critChance then
				crit = crit + (data.critChance * qMult)
			end
			if data.critDamageMult then
				critDmgMult = critDmgMult + (data.critDamageMult * qMult)
			end
		end
	end
	
	return {
		maxHealth = hp,
		critChance = crit,
		critDamageMult = critDmgMult,
	}
end

function InventoryService.getTotalDefense(userId: number): number
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return 0 end
	
	local defense = 0
	local attrBonuses = InventoryService.getEquipmentAttributeBonuses(userId)
	local globalDefenseMult = attrBonuses.defenseMult or 0

	for _, item in pairs(inv.equipment) do
		local data = DataService.getItem(item.itemId)
		if data and data.defense then
			defense = defense + math.floor(data.defense * (1 + globalDefenseMult) + 0.5)
		end
	end
	
	-- ?트 ?과 추? 방어??
	local setBonuses = InventoryService.getArmorSetBonuses(userId)
	if setBonuses and setBonuses.defense then
		defense = defense + setBonuses.defense
	end
	
	return defense
end

function InventoryService.getArmorSetBonuses(userId: number)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return nil end
	
	local counts = {} -- { setID = count }
	for _, item in pairs(inv.equipment) do
		local data = DataService.getItem(item.itemId)
		if data and data.armorSet then
			counts[data.armorSet] = (counts[data.armorSet] or 0) + 1
		end
	end
	
	local ArmorSetData = require(ReplicatedStorage.Data.ArmorSetData)
	local bestSet = nil
	local bestBonus = nil
	
	for setId, count in pairs(counts) do
		local setData = ArmorSetData[setId]
		if setData and count >= #setData.items then
			-- ?트 ?성! (가??최근???인???트 ?나??용?거??중첩 가?하??????음)
			-- ?재??간단???산?거???선?위 ?? ??나?반환
			bestSet = setId
			bestBonus = setData.bonuses
		end
	end
	
	return bestBonus, bestSet
end


function InventoryService.equipItem(player: Player, inventorySlot: number, equipmentSlotName: string)
	local userId = player.UserId
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[inventorySlot]
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData then return false, Enums.ErrorCode.INVALID_ITEM end
	
	-- 슬롯 유효성 체크
	local targetSlot = equipmentSlotName:upper()
	local isValidSlot = (targetSlot == "EARRING" or targetSlot == "SUIT" or targetSlot == "HAND" or 
	                    targetSlot == "NECKLACE" or targetSlot == "RING" or targetSlot == "RING1" or targetSlot == "RING2" or
	                    targetSlot == "RUNE1" or targetSlot == "RUNE2" or targetSlot == "RUNE3")
	if not isValidSlot then
		return false, Enums.ErrorCode.BAD_REQUEST
	end
	
	-- 만약 targetSlot이 "RING"으로 넘어왔다면, 빈 슬롯 탐색 또는 RING1 자동 할당
	if targetSlot == "RING" then
		if not inv.equipment["RING1"] then
			targetSlot = "RING1"
		elseif not inv.equipment["RING2"] then
			targetSlot = "RING2"
		else
			targetSlot = "RING1" -- 둘 다 가득 찬 경우 RING1을 교체 슬롯으로 설정
		end
	end
	
	local itemSlot = itemData.slot and itemData.slot:upper()
	local isRuneSlot = (targetSlot:sub(1, 4) == "RUNE")
	
	-- 룬 장착 쿨타임 검증
	if isRuneSlot then
		if playerRuneCooldowns[userId] and os.clock() < playerRuneCooldowns[userId] then
			local remain = math.ceil(playerRuneCooldowns[userId] - os.clock())
			if NetController then
				NetController.FireClient(player, "Notify.Message", { text = string.format("룬 재장착 대기시간입니다. (%d초 남음)", remain) })
			end
			return false, "COOLDOWN"
		end
	end
	
	local isMatch = false
	if isRuneSlot and itemSlot == "RUNE" then
		-- 룬 속성 일치 여부 확인
		local playerElement = player:GetAttribute("Element") or "Fire"
		if itemData.element and itemData.element ~= playerElement then
			if NetController then
				NetController.FireClient(player, "Notify.Message", { text = string.format("현재 속성(%s)과 일치하는 룬만 장착할 수 있습니다.", playerElement) })
			end
			return false, "ELEMENT_MISMATCH"
		end
		
		-- 룬 중복 장착(완전히 동일한 룬) 검사
		for equipKey, equipNode in pairs(inv.equipment) do
			if equipKey:sub(1, 4) == "RUNE" and equipKey ~= targetSlot and equipNode.itemId == slotData.itemId then
				if NetController then
					NetController.FireClient(player, "Notify.Message", { text = "이미 동일한 스킬(룬)을 장착하고 있습니다.", color = "RED" })
				end
				return false, "DUPLICATE_RUNE"
			end
		end
		
		isMatch = true
	elseif itemSlot == "RING" and (targetSlot == "RING1" or targetSlot == "RING2") then
		-- 반지 아이템은 반지 1, 반지 2 슬롯 어디든 장착 허용!
		isMatch = true
	elseif itemSlot == targetSlot then
		isMatch = true
	end

	if not isMatch then
		warn(string.format("[InventoryService] Slot mismatch: %s vs %s", itemSlot or "NIL", targetSlot))
		return false, Enums.ErrorCode.BAD_REQUEST
	end

	-- 기존 ?비? 교체
	local oldEquip = inv.equipment[targetSlot]
	inv.equipment[targetSlot] = {
		itemId = slotData.itemId,
		durability = slotData.durability,
		attributes = slotData.attributes,
	}
	
	-- ?벤?리?서 ?거 (1개만)
	if slotData.count > 1 then
		slotData.count -= 1
	else
		inv.slots[inventorySlot] = nil
	end
	
	-- 기존 ?비가 ?었?면 ?벤?리?복구
	if oldEquip then
		InventoryService.addItem(userId, oldEquip.itemId, 1, oldEquip.durability, oldEquip.attributes)
		if isRuneSlot then
			local SkillService = require(game:GetService("ServerScriptService").Server.Services.SkillService)
			SkillService.revokeRuneSkill(userId, oldEquip.itemId)
		end
	end
	
	if isRuneSlot then
		local SkillService = require(game:GetService("ServerScriptService").Server.Services.SkillService)
		SkillService.grantRuneSkill(userId, slotData.itemId, targetSlot)
	end
	
	-- ?태 ????청
	_emitChanged(player, { _makeChange(inv, inventorySlot) })
	
	-- ?라?언?에 ?비 변??보
	NetController.FireClient(player, "Inventory.Equipment.Changed", {
		equipment = inv.equipment
	})
	
	-- ?비 변??보 (EquipService ?동 - ?구/무기거나 방어??각???요 ??
	if EquipService then
		EquipService.updateAppearance(player) -- ?체 ?형 갱신 (?의/?의/?트 ?함)
		if targetSlot == "HAND" then
			EquipService.equipItem(player, inv.equipment[targetSlot].itemId)
		end
	end
	
	-- ?탯 ?계??(방어???
	if PlayerStatService then
		PlayerStatService.applyStats(userId)
	end

	pcall(function()
		local tqs = require(game:GetService("ServerScriptService").Server.Services.TutorialQuestService)
		if tqs and tqs.OnEquipmentChanged then
			tqs.OnEquipmentChanged(userId)
		end
	end)
	
	return true
end

function InventoryService.unequipItem(player: Player, equipmentSlotName: string)
	local userId = player.UserId
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local oldEquip = inv.equipment[equipmentSlotName]
	if not oldEquip then return false, Enums.ErrorCode.SLOT_EMPTY end
	
	-- ?벤?리??공간 ?는지 체크
	local added, remaining = InventoryService.addItem(userId, oldEquip.itemId, 1, oldEquip.durability, oldEquip.attributes)
	if added == 0 then
		return false, Enums.ErrorCode.INV_FULL
	end
	
	-- 룬 해제 시 10초 쿨타임 적용
	if equipmentSlotName:sub(1, 4) == "RUNE" then
		playerRuneCooldowns[userId] = os.clock() + 10
		local SkillService = require(game:GetService("ServerScriptService").Server.Services.SkillService)
		SkillService.revokeRuneSkill(userId, oldEquip.itemId)
		if NetController then
			NetController.FireClient(player, "Notify.Message", { text = "룬 해제 완료. 10초의 재장착 대기시간이 적용됩니다." })
		end
	end
	
	inv.equipment[equipmentSlotName] = nil
	
	-- ?태 ????청
	_emitChanged(player, {}) -- 무게 ?산 ?을 ?해 ?change??출 가??
	
	-- ?라?언?에 ?비 변??보
	NetController.FireClient(player, "Inventory.Equipment.Changed", {
		equipment = inv.equipment
	})
	
	-- ?비 ?제 ?보
	if EquipService then
		EquipService.updateAppearance(player)
		if equipmentSlotName == "HAND" then
			EquipService.equipItem(player, nil)
		end
	end
	
	if PlayerStatService then
		PlayerStatService.applyStats(userId)
	end

	pcall(function()
		local tqs = require(game:GetService("ServerScriptService").Server.Services.TutorialQuestService)
		if tqs and tqs.OnEquipmentChanged then
			tqs.OnEquipmentChanged(userId)
		end
	end)

	return true
end

function InventoryService.updateEquipmentAttributes(userId: number, equipmentSlotName: string, attributes: any)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return false end
	
	local slotData = inv.equipment[equipmentSlotName]
	if not slotData then return false end
	
	slotData.attributes = attributes
	
	-- Notify client of equipment change
	local player = Players:GetPlayerByUserId(userId)
	if player then
		NetController.FireClient(player, "Inventory.Equipment.Changed", {
			equipment = inv.equipment
		})
	end
	
	if PlayerStatService then
		PlayerStatService.applyStats(userId)
	end
	
	return true
end

--========================================
-- Public API: Inventory Management
--========================================

local function hasRawInventoryItems(rawInv)
	if type(rawInv) ~= "table" then
		return false
	end

	local source = rawInv
	if type(rawInv.slots) == "table" then
		source = rawInv.slots
	end

	for _, node in pairs(source) do
		if type(node) == "table" and type(node.itemId) == "string" and node.itemId ~= "" then
			return true
		end
	end

	return false
end

--- ?레?어 ?벤?리 가?오??는 ?성
function InventoryService.getOrCreateInventory(userId: number): any
	if playerInventories[userId] then
		return playerInventories[userId]
	end
	
	-- SaveService?서 로드 ?도
	local savedInv = nil
	local savedEquip = nil
	local loadedState = nil
	
	-- [Race Condition FIX] ?라?언?의 Get Request가 ServerInit 주입(Init)보다 먼? ?달??경우 ?적 ?당
	if not SaveService then
		local ServerService = game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Services")
		SaveService = require(ServerService:WaitForChild("SaveService"))
	end
	if not DataService then
		local ServerService = game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Services")
		DataService = require(ServerService:WaitForChild("DataService"))
	end

	if SaveService then
		local state = SaveService.getPlayerState(userId)
		if state then
			loadedState = state
			if state.inventory then savedInv = state.inventory end
			if state.equipment then savedEquip = state.equipment end
		else
			-- [신규 아키텍처] SaveService.PlayerSaveLoaded 에서 데이터가 주입될 때까지 대기하지 않음
			return nil
		end
	end

	-- [중요] Yield(???는 ?안 ?른 ?레???? Get.Request)?서 ?벤?리??성?을 ???으므??시 체크
	if playerInventories[userId] then
		return playerInventories[userId]
	end

	-- ?이???규???마이그레?션 (?구???락 ???????자 ?덱??강제)
	local normalizedSlots = {}
	local inventorySource = savedInv

	if type(savedInv) == "table" and type(savedInv.slots) == "table" then
		inventorySource = savedInv.slots
	end

	if inventorySource then
		for k, node in pairs(inventorySource) do
			if type(node) == "table" then
				local numKey = tonumber(k) or node.slot
				if numKey and node.itemId then
					local item = DataService.getItem(node.itemId)
					if item and item.durability and not node.durability then
						node.durability = item.durability -- ?락???구??초기??
					end
					
					normalizedSlots[numKey] = {
						itemId = node.itemId,
						count = node.count or 1,
						durability = node.durability,
						attributes = (node.attributes) or (node.attribute and node.attributeLevel and { [node.attribute] = node.attributeLevel }) or nil,
					}
				end
			end
		end
	end

	if hasRawInventoryItems(savedInv) and next(normalizedSlots) == nil then
		warn(string.format(
			"[InventoryService] BLOCKED empty inventory creation for user %d: raw inventory existed but parsed 0 slots",
			userId
		))
		return nil
	end
	
	if savedEquip then
		for _, node in pairs(savedEquip) do
			if node and node.itemId then
				local item = DataService.getItem(node.itemId)
				if item and item.durability and not node.durability then
					node.durability = item.durability
				end
			end
		end
	end

	-- [Defensive Fix] ?토리얼 초반(1?계)?데 BRANCH가 비정??최??택?로 로드?면 1개로 보정
	-- ?상 진행 ????보유 ???건드리? ?기 ?해 "초반 + 미완? ?태?서??용
	local sanitizedBranch = false
	if loadedState and (type(loadedState.rpgTutorialQuest) == "table" or type(loadedState.tutorialQuest) == "table") then
		local tq = loadedState.rpgTutorialQuest or loadedState.tutorialQuest
		local isEarlyTutorial = (tq.completed ~= true) and ((tonumber(tq.stepIndex) or 1) <= 1)
		if isEarlyTutorial then
			for slot, node in pairs(normalizedSlots) do
				if type(node) == "table" and node.itemId == "BRANCH" and (tonumber(node.count) or 0) >= Balance.MAX_STACK then
					normalizedSlots[slot].count = 1
					sanitizedBranch = true
					print(string.format("[InventoryService] Sanitized BRANCH stack for user %d at slot %s", userId, tostring(slot)))
				end
			end
		end
	end

	if sanitizedBranch and loadedState then
		loadedState.inventory = normalizedSlots
	end

	-- [Migration] 비스택 아이템 확장: count > 1인 비AMMO 아이템을 개별 슬롯으로 분리
	if DataService then
		local expandQueue = {}
		for slot = 1, Balance.MAX_INV_SLOTS do
			local node = normalizedSlots[slot]
			if node and node.itemId then
				local itemData = DataService.getItem(node.itemId)
				local isStackable = _isStackable(node.itemId)
				if not isStackable and node.count and node.count > 1 then
					table.insert(expandQueue, {
						slot = slot,
						itemId = node.itemId,
						extra = node.count - 1,
						durability = node.durability,
						attributes = node.attributes,
					})
					node.count = 1
				end
			end
		end
		for _, expand in ipairs(expandQueue) do
			for i = 1, expand.extra do
				local placed = false
				for s = 1, Balance.MAX_INV_SLOTS do
					if normalizedSlots[s] == nil then
						normalizedSlots[s] = {
							itemId = expand.itemId,
							count = 1,
							durability = expand.durability,
							attributes = expand.attributes,
						}
						placed = true
						break
					end
				end
				if not placed then
					warn(string.format("[InventoryService] Migration overflow: %s dropped for user %d", expand.itemId, userId))
					break
				end
			end
		end
	end

	-- 새 인벤토리 객체 생성
	local inv = {
		slots = normalizedSlots,
		equipment = _normalizeEquipmentSlots(savedEquip)
	}

	-- [Migration] skillBooks 상태에 남아있는 스킬북을 인벤토리 아이템으로 이관
	if loadedState and type(loadedState.skillBooks) == "table" and #loadedState.skillBooks > 0 then
		local remaining = {}
		for _, bookId in ipairs(loadedState.skillBooks) do
			-- 빈 슬롯에 배치
			local placed = false
			for s = 1, Balance.MAX_INV_SLOTS do
				if inv.slots[s] == nil then
					inv.slots[s] = { itemId = bookId, count = 1 }
					placed = true
					break
				end
			end
			if not placed then
				table.insert(remaining, bookId)
				warn(string.format("[InventoryService] skillBook migration overflow: %s for user %d", bookId, userId))
			end
		end
		-- 이관 완료된 항목 제거 (인벤토리 꽉 찬 경우 남은 것만 유지)
		loadedState.skillBooks = remaining
		print(string.format("[InventoryService] Migrated %d skillBook(s) to inventory for user %d", #loadedState.skillBooks == 0 and #loadedState.skillBooks or (#loadedState.skillBooks), userId))
	end

	playerInventories[userId] = inv
	return inv
end

--- ?레?어 ?벤?리 가?오?
function InventoryService.getInventory(userId: number): any?
	return playerInventories[userId]
end

--- ?레?어 ?벤?리 ?? (PlayerRemoving ??
function InventoryService.removeInventory(userId: number)
	playerInventories[userId] = nil
end

--- [HOTBAR REMOVED] 핫바 제거용 더미 함수 (Failsafe용)
function InventoryService.setActiveSlot(userId: number, slot: number)
	-- No-op
end

--- [HOTBAR REMOVED] 항상 1번 슬롯 반환 (Failsafe용)
function InventoryService.getActiveSlot(userId: number): number
	return 1
end

--========================================
-- Public API: Move
--========================================

--- ?이???동 (fromSlot -> toSlot)
--- count가 nil?면 ?체 ?동
function InventoryService.move(player: Player, fromSlot: number, toSlot: number, count: number?): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?롯 범위 검?(먼?!)
	local ok, err = _validateSlotRange(fromSlot)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRange(toSlot)
	if not ok then return false, err, nil end
	
	-- 같? ?롯?면 무시
	if fromSlot == toSlot then
		return true, nil, nil
	end
	
	-- 출발 ?롯???이?이 ?는지
	ok, err = _validateHasItem(inv, fromSlot)
	if not ok then return false, err, nil end
	
	-- ?량 검?
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local fromData = inv.slots[fromSlot]
	local moveCount = count or fromData.count  -- nil?면 ?체

	-- [HOTBAR REMOVED] 1~8번 슬롯도 평범한 일반 보관 슬롯이므로 방어구 이동 제한 불필요
	
	-- ?동 ?량 검?
	ok, err = _validateCountAvailable(inv, fromSlot, moveCount)
	if not ok then return false, err, nil end
	
	local toData = inv.slots[toSlot]
	local changes = {}
	
	if toData == nil then
		-- ????롯??비어?으? ?순 ?동
		_increaseSlot(inv, toSlot, fromData.itemId, moveCount, fromData.durability, fromData.attributes)
		_decreaseSlot(inv, fromSlot, moveCount)
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
		
	elseif toData.itemId == fromData.itemId then
		if _isStackable(fromData.itemId) then
			-- 스택 가능 아이템(화살류): 스택 병합
			local itemMaxStack = _getMaxStack(fromData.itemId)
			local canAdd = math.max(0, itemMaxStack - toData.count)
			local actualMove = math.min(moveCount, canAdd)
			
			if actualMove > 0 then
				_increaseSlot(inv, toSlot, fromData.itemId, actualMove, fromData.durability, fromData.attributes)
				_decreaseSlot(inv, fromSlot, actualMove)
				
				table.insert(changes, _makeChange(inv, fromSlot))
				table.insert(changes, _makeChange(inv, toSlot))
			else
				return false, Enums.ErrorCode.STACK_OVERFLOW, nil
			end
		else
			-- 비스택 아이템: 같은 아이템이어도 스왑
			if count ~= nil then
				return false, Enums.ErrorCode.ITEM_MISMATCH, nil
			end
			inv.slots[fromSlot] = toData
			inv.slots[toSlot] = fromData
			table.insert(changes, _makeChange(inv, fromSlot))
			table.insert(changes, _makeChange(inv, toSlot))
		end
		
	else
		-- ?른 ?이?이? ?왑 (?체 ?동???만)
		if count ~= nil then
			-- 부??동? ?른 ?이?과 불?
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		-- ?왑
		inv.slots[fromSlot] = toData
		inv.slots[toSlot] = fromData
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
	end
	
	-- ?벤??발생
	_emitChanged(player, changes)
	
	return true, nil, { changes = changes }
end

--========================================
-- Public API: Split
--========================================

--- ?택 분할 (fromSlot?서 count만큼 ?서 toSlot?????택)
--- toSlot? 반드??비어?어????
function InventoryService.split(player: Player, fromSlot: number, toSlot: number, count: number): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?롯 범위 검?(먼?!)
	local ok, err = _validateSlotRange(fromSlot)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRange(toSlot)
	if not ok then return false, err, nil end
	
	-- 같? ?롯?면 불?
	if fromSlot == toSlot then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- 출발 ?롯???이?이 ?는지
	ok, err = _validateHasItem(inv, fromSlot)
	if not ok then return false, err, nil end
	
	-- ????롯??비어?는지
	ok, err = _validateSlotEmpty(inv, toSlot)
	if not ok then return false, err, nil end
	
	-- ?량 검?(split? count ?수)
	if count == nil then
		return false, Enums.ErrorCode.INVALID_COUNT, nil
	end
	
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	-- ?동 ?량 검?
	ok, err = _validateCountAvailable(inv, fromSlot, count)
	if not ok then return false, err, nil end
	
	local fromData = inv.slots[fromSlot]
	
	-- 분할 ?용
	_setSlot(inv, toSlot, fromData.itemId, count, fromData.durability, fromData.attributes)
	_decreaseSlot(inv, fromSlot, count)
	
	local changes = {
		_makeChange(inv, fromSlot),
		_makeChange(inv, toSlot),
	}
	
	-- ?벤??발생
	_emitChanged(player, changes)
	
	return true, nil, { changes = changes }
end

--========================================
-- Public API: Drop
--========================================

--- ?이???롭 (?벤?서 감소? ?드 ?롭? ?중??
--- count가 nil?면 ?체 ?롭
function InventoryService.drop(player: Player, slot: number, count: number?): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?롯 범위 검?
	local ok, err = _validateSlotRange(slot)
	if not ok then return false, err, nil end
	
	-- ?롯???이?이 ?는지
	ok, err = _validateHasItem(inv, slot)
	if not ok then return false, err, nil end
	
	-- ?량 검?
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local slotData = inv.slots[slot]
	local dropCount = count or slotData.count  -- nil?면 ?체
	
	-- ?롭 ?량 검?
	ok, err = _validateCountAvailable(inv, slot, dropCount)
	if not ok then return false, err, nil end
	
	local droppedItem = {
		itemId = slotData.itemId,
		count = dropCount,
		durability = slotData.durability, -- ?구??보존
	}
	
	-- ?벤?서 감소
	_decreaseSlot(inv, slot, dropCount)
	
	local changes = {
		_makeChange(inv, slot),
	}
	
	-- ?벤??발생
	_emitChanged(player, changes)
	
	return true, nil, {
		dropped = droppedItem,
		changes = changes,
	}
end

--- 아이템 ID를 기준으로 여러 슬롯에서 합계 수량만큼 드랍
function InventoryService.dropByItemId(player: Player, itemId: string, count: number): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 수량 검증
	local ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local remaining = count
	local totalDropped = 0
	local changes = {}
	local firstDroppedItem = nil -- 첫 번째로 찾은 슬롯의 아이템 정보 (내구도 등 보존용)
	
	-- 슬롯 순회하며 제거
	for slot = 1, Balance.MAX_INV_SLOTS do
		if remaining <= 0 then break end
		
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId then
			local canRemove = math.min(remaining, slotData.count)
			
			if not firstDroppedItem then
				firstDroppedItem = {
					itemId = itemId,
					count = 0,
					durability = slotData.durability
				}
			end
			
			_decreaseSlot(inv, slot, canRemove)
			remaining = remaining - canRemove
			totalDropped = totalDropped + canRemove
			table.insert(changes, _makeChange(inv, slot))
		end
	end
	
	if totalDropped > 0 then
		firstDroppedItem.count = totalDropped
		_emitChanged(player, changes)
		
		return true, nil, {
			dropped = firstDroppedItem,
			changes = changes,
		}
	end
	
	return false, Enums.ErrorCode.ITEM_MISMATCH, nil
end

--========================================
-- Public API: MoveInternal (범용 컨테?너 ??동)
-- StorageService ?에???사??
--========================================

--- ?롯 범위 검?(커스? maxSlots)
local function _validateSlotRangeCustom(slot: number, maxSlots: number, allowZero: boolean?): (boolean, string?)
	if type(slot) ~= "number" then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	if allowZero and slot == 0 then return true, nil end
	if slot < 1 or slot > maxSlots or slot ~= math.floor(slot) then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	return true, nil
end

--- 범용 컨테?너 ??이???동
--- sourceContainer, targetContainer: { slots = { [slot] = {itemId, count} } }
--- maxSlots: ?롯 최? ??
--- ?벤??발행? ?출??책임
function InventoryService.MoveInternal(
	sourceContainer: any,
	sourceSlot: number,
	sourceMaxSlots: number,
	targetContainer: any,
	targetSlot: number,
	targetMaxSlots: number,
	count: number?
): (boolean, string?, any?)
	
	-- ?스/??검?
	if not sourceContainer or not sourceContainer.slots then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not targetContainer or not targetContainer.slots then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?롯 범위 검?
	local ok, err = _validateSlotRangeCustom(sourceSlot, sourceMaxSlots)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRangeCustom(targetSlot, targetMaxSlots, true)
	if not ok then return false, err, nil end
	
	-- ?물 ?이???보 ?인
	ok, err = _validateHasItem(sourceContainer, sourceSlot)
	if not ok then return false, err, nil end
	
	local sourceData = sourceContainer.slots[sourceSlot]

	-- 자동 슬롯 이동 선택 (targetSlot == 0)
	if targetSlot == 0 then
		-- 1. 스택 가능 아이템만: 같은 아이템 스택 가능 슬롯 찾기
		if _isStackable(sourceData.itemId) then
			local itemMaxStack = _getMaxStack(sourceData.itemId)
			for i = 1, targetMaxSlots do
				local ts = targetContainer.slots[i]
				if ts and ts.itemId == sourceData.itemId and ts.count < itemMaxStack then
					targetSlot = i
					break
				end
			end
		end
		-- 2. 빈 슬롯 찾기
		if targetSlot == 0 then
			for i = 1, targetMaxSlots do
				if targetContainer.slots[i] == nil then
					targetSlot = i
					break
				end
			end
		end
		-- 여전히 0이면 공간 없음
		if targetSlot == 0 then
			return false, Enums.ErrorCode.INV_FULL, nil
		end
	end

	-- 같? 컨테?너 + 같? ?롯?면 무시
	if sourceContainer == targetContainer and sourceSlot == targetSlot then
		return true, nil, nil
	end
	
	-- ?량 검?
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local sourceData = sourceContainer.slots[sourceSlot]
	local moveCount = count or sourceData.count  -- nil?면 ?체
	
	-- ?동 ?량 검?
	ok, err = _validateCountAvailable(sourceContainer, sourceSlot, moveCount)
	if not ok then return false, err, nil end
	
	local targetData = targetContainer.slots[targetSlot]
	
	local sourceChanges = {}
	local targetChanges = {}
	
	if targetData == nil then
		-- ???롯??비어?으? ?순 ?동
		_increaseSlot(targetContainer, targetSlot, sourceData.itemId, moveCount, sourceData.durability, sourceData.attributes)
		_decreaseSlot(sourceContainer, sourceSlot, moveCount)
		
		table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
		table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
		
	elseif targetData.itemId == sourceData.itemId then
		if _isStackable(sourceData.itemId) then
			-- 스택 가능 아이템(화살류): 스택 병합
			local itemMaxStack = _getMaxStack(sourceData.itemId)
			local canAdd = math.max(0, itemMaxStack - targetData.count)
			local actualMove = math.min(moveCount, canAdd)
			
			if actualMove > 0 then
				_increaseSlot(targetContainer, targetSlot, sourceData.itemId, actualMove, sourceData.durability, sourceData.attributes)
				_decreaseSlot(sourceContainer, sourceSlot, actualMove)
				
				table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
				table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
			else
				return false, Enums.ErrorCode.STACK_OVERFLOW, nil
			end
		else
			-- 비스택 아이템: 같은 아이템이어도 스왑
			if count ~= nil then
				return false, Enums.ErrorCode.ITEM_MISMATCH, nil
			end
			if sourceContainer ~= targetContainer then
				return false, Enums.ErrorCode.ITEM_MISMATCH, nil
			end
			sourceContainer.slots[sourceSlot] = targetData
			sourceContainer.slots[targetSlot] = sourceData
			table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
			table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
		end
		
	else
		-- ?른 ?이?이? ?왑 (?체 ?동???만, 같? 컨테?너 ?에?만)
		if count ~= nil then
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		if sourceContainer ~= targetContainer then
			-- ?른 컨테?너 ??왑? 복잡???금?
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		-- ?왑
		sourceContainer.slots[sourceSlot] = targetData
		sourceContainer.slots[targetSlot] = sourceData
		
		table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
		table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
	end
	
	return true, nil, {
		sourceChanges = sourceChanges,
		targetChanges = targetChanges,
		movedItem = { itemId = sourceData.itemId, count = moveCount },
	}
end

--========================================
-- Public API: Utility
--========================================

--- ?이??추? (??롯 ?는 기존 ?택??
--- 반환: 추????량, ?? ?량
function InventoryService.addItem(userId: number, itemId: string, count: number, durability: number?, attributes: any?): (number, number)
	local inv = playerInventories[userId]
	if not inv then
		return 0, count
	end
	
	local player = Players:GetPlayerByUserId(userId)

	local remaining = count
	local added = 0
	local changedSlots = {}
	
	-- ?롯 ??체크
	local maxSlots = _getMaxSlots(userId)

	-- ?구???보 조회 (???택 ?성 ???용) 및 품질(Quality) 초기화
	local maxDurability = durability -- ?달받? ?구???선
	local itemData = nil
	if DataService then
		itemData = DataService.getItem(itemId)
		if itemData then
			if not maxDurability then maxDurability = itemData.durability end
			
			-- 품질 자동 부여 (무기, 방어구/장신구)
			if itemData.type == "WEAPON" or itemData.type == "ARMOR" then
				attributes = attributes or {}
				if attributes.quality == nil then
					attributes.quality = math.random(0, 100)
				end
			end
		end
	end
	

	-- 스택 가능 여부 / 아이템별 최대 스택
	local stackable = _isStackable(itemId)
	local itemMaxStack = _getMaxStack(itemId)
	
	-- 1. 기존 스택에 병합 (스택 가능 아이템(화살류)만, 내구도 없는 경우)
	if stackable and not maxDurability then
		for slot = 1, maxSlots do
			if remaining <= 0 then break end
			
			local slotData = inv.slots[slot]
			if slotData and slotData.itemId == itemId and slotData.count < itemMaxStack and not slotData.durability then
				local canAddByStack = itemMaxStack - slotData.count
				
				local canAdd = math.min(remaining, canAddByStack)
				if canAdd <= 0 then break end

				slotData.count = slotData.count + canAdd
				remaining = remaining - canAdd
				added = added + canAdd
				changedSlots[slot] = true
			end
		end
	end
	
	-- 2. 빈 슬롯에 새 아이템 배치
	-- [HOTBAR REMOVED] 1~8번이 평범한 슬롯이므로 방어구 우선 배치 필터 없이 정상 순차 배치
	for slot = 1, maxSlots do
		if remaining <= 0 then break end
		
		if inv.slots[slot] == nil then
			-- 스택 가능: 최대 itemMaxStack, 비스택: 항상 1
			local canAdd = stackable and math.min(remaining, itemMaxStack) or 1
			if canAdd <= 0 then break end

			inv.slots[slot] = {
				itemId = itemId,
				count = canAdd,
				durability = maxDurability,
				attributes = attributes,
			}
			remaining = remaining - canAdd
			added = added + canAdd
			changedSlots[slot] = true
		end
	end
	
	if player then
		local changes = {}
		for slot, _ in pairs(changedSlots) do
			table.insert(changes, _makeChange(inv, slot))
		end
		_emitChanged(player, changes)
	end

	if added > 0 and questItemCallback then
		task.spawn(function()
			questItemCallback(userId, itemId, added)
		end)
	end
	
	return added, remaining
end

--- ?벤?리 ?렬 (??롯 채우?
function InventoryService.sort(userId: number)
	local inv = playerInventories[userId]
	if not inv then return end
	
	local items = {}
	for slot = 1, Balance.MAX_INV_SLOTS do
		if inv.slots[slot] then
			table.insert(items, inv.slots[slot])
			inv.slots[slot] = nil
		end
	end
	
	-- 아이템 압축 (스택 가능 아이템만 병합, 비스택은 개별 유지)
	local compressed = {}
	for _, item in ipairs(items) do
		local remaining = item.count or 1
		local isItemStackable = _isStackable(item.itemId)
		local itemMaxStack = _getMaxStack(item.itemId)
		
		if isItemStackable then
			for _, comp in ipairs(compressed) do
				if remaining <= 0 then break end
				if comp.itemId == item.itemId and comp.count < itemMaxStack and not comp.durability and not item.durability then
					local space = itemMaxStack - comp.count
					local amount = math.min(remaining, space)
					comp.count = comp.count + amount
					remaining = remaining - amount
				end
			end
		end
		
		-- 비스택 아이템은 1개씩 개별 슬롯으로 배치
		if not isItemStackable then
			for i = 1, remaining do
				table.insert(compressed, {
					itemId = item.itemId,
					count = 1,
					durability = item.durability,
					attributes = item.attributes,
				})
			end
		elseif remaining > 0 then
			table.insert(compressed, {
				itemId = item.itemId,
				count = remaining,
				durability = item.durability,
				attributes = item.attributes,
			})
		end
	end

	inv.slots = {}
	for index, item in ipairs(compressed) do
		if index > Balance.MAX_INV_SLOTS then
			break
		end
		inv.slots[index] = {
			itemId = item.itemId,
			count = item.count,
			durability = item.durability,
			attributes = item.attributes,
		}
	end
	
	local player = Players:GetPlayerByUserId(userId)
	
	if player then
		-- [최적?? 모든 ?롯 ?? ???FullStack ?송 (?덱???실 방???해 getFullInventory 배열 ?용)
		_emitChanged(player, {}, InventoryService.getFullInventory(userId))
	end
end

--- ??롯 개수
function InventoryService.getEmptySlotCount(userId: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local count = 0
	for slot = 1, Balance.MAX_INV_SLOTS do
		if inv.slots[slot] == nil then
			count = count + 1
		end
	end
	return count
end

--- ?량 ?용 가???? 검?(?수 ?수, ?태 변??음)
--- Loot ?자???보??
function InventoryService.canAdd(userId: number, itemId: string, count: number): boolean
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local remaining = count
	local stackable = _isStackable(itemId)
	local itemMaxStack = _getMaxStack(itemId)
	local maxSlots = _getMaxSlots(userId)
	
	-- 1. 스택 가능 아이템만: 기존 스택 여유분 계산
	if stackable then
		for slot = 1, maxSlots do
			if remaining <= 0 then break end
			
			local slotData = inv.slots[slot]
			if slotData and slotData.itemId == itemId and slotData.count < itemMaxStack then
				remaining = remaining - (itemMaxStack - slotData.count)
			end
		end
	end
	
	-- 2. 빈 슬롯 개수 계산 (스택 가능: itemMaxStack씩, 비스택: 1씩)
	for slot = 1, maxSlots do
		if remaining <= 0 then break end
		
		if inv.slots[slot] == nil then
			remaining = remaining - itemMaxStack
		end
	end
	
	return remaining <= 0
end

--- ?이??보유 ?? ?인 (?수 ?수)
function InventoryService.hasItem(userId: number, itemId: string, count: number): boolean
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local total = 0
	for slot = 1, Balance.MAX_INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId then
			total = total + slotData.count
			if total >= count then
				return true
			end
		end
	end
	return total >= count
end

--- ?이???거 (?러 ?롯?서 분산 ?거)
--- 반환: ?거???량
function InventoryService.removeItem(userId: number, itemId: string, count: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local remaining = count
	local removed = 0
	local changedSlots = {}
	
	-- ?롯 ?회?며 ?거
	for slot = 1, Balance.MAX_INV_SLOTS do
		if remaining <= 0 then break end
		
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId then
			local canRemove = math.min(remaining, slotData.count)
			_decreaseSlot(inv, slot, canRemove)
			remaining = remaining - canRemove
			removed = removed + canRemove
			changedSlots[slot] = true
		end
	end
	
	-- ?벤??발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local changes = {}
		for slot, _ in pairs(changedSlots) do
			table.insert(changes, _makeChange(inv, slot))
		end
		_emitChanged(player, changes)
	end
	
	return removed
end

--- ?정 ?롯?서 ?이???거
function InventoryService.removeItemFromSlot(userId: number, slot: number, count: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local ok, err = _validateSlotRange(slot)
	if not ok then return 0 end
	
	local slotData = inv.slots[slot]
	if not slotData then return 0 end
	
	local toRemove = math.min(count, slotData.count)
	_decreaseSlot(inv, slot, toRemove)
	
	-- ?벤??발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, { _makeChange(inv, slot) })
	end
	
	return toRemove
end

--- 특정 슬롯의 속성(Attributes)을 업데이트
function InventoryService.updateSlotAttributes(userId: number, slot: number, attributes: any)
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local ok, err = _validateSlotRange(slot)
	if not ok then return false end
	
	local slotData = inv.slots[slot]
	if not slotData then return false end
	
	slotData.attributes = attributes
	
	-- 인벤토리 변경 알림 발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, { _makeChange(inv, slot) })
	end
	
	return true
end

--- 전체 인벤토리 아이템 반환 (클라이언트 초기화용)
function InventoryService.getFullInventory(userId: number): {{slot: number, itemId: string?, count: number?}}
	local inv = playerInventories[userId]
	if not inv then return {} end
	
	local result = {}
	for slot = 1, Balance.MAX_INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData then
			table.insert(result, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
				durability = slotData.durability,
				attributes = slotData.attributes,
			})
		end
	end
	return result
end

--- ?구??감소 (0 ?하 ?괴)
--- 반환: success, errorCode, currentDurability(or 0)
function InventoryService.decreaseDurability(userId: number, slot: number, amount: number)
	-- [MODIFIED] DEACTIVATED SYSTEM-WIDE: Items are now unbreakable!
	-- [MODIFIED] Wrapped in do-end to satisfy Luau grammar syntax requirement
	do return true, nil, 100 end
	
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[slot]
	
	-- ?이?이 ?거???구?? ?는 ?이?이?무시 (?는 ?러)
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	if not slotData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	slotData.durability = slotData.durability - amount
	local current = slotData.durability
	
	if current <= 0 then
		-- ?괴
		inv.slots[slot] = nil
	end
	
	-- ?벤??
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, {_makeChange(inv, slot)})
	end
	
	return true, nil, math.max(0, current)
end

--- ?비 ?롯 ?구??감소
function InventoryService.decreaseEquipmentDurability(userId: number, equipmentSlotName: string, amount: number)
	-- [MODIFIED] DEACTIVATED SYSTEM-WIDE: Weapons are now unbreakable!
	-- [MODIFIED] Wrapped in do-end to satisfy Luau grammar syntax requirement
	do return true, nil, 100 end

	-- local inv = playerInventories[userId]
	-- local slotData = inv.equipment[equipmentSlotName]
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	if not slotData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	slotData.durability = math.max(0, slotData.durability - amount)
	local current = slotData.durability
	
	if current <= 0 then
		-- 장비 파괴 (장착 제거)
		print(string.format("[InventoryService] Equipment %s destroyed for user %d", equipmentSlotName, userId))
		inv.equipment[equipmentSlotName] = nil
	end
	
	-- SaveService에 장비 상태 동기화 (내구도 변동 및 파괴 반영)
	if SaveService then
		SaveService.updatePlayerState(userId, function(state)
			state.equipment = inv.equipment
			return state
		end)
	end
	
	-- 이벤트 발생
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player then
		NetController.FireClient(player, "Inventory.Equipment.Changed", { equipment = inv.equipment })
		
		-- ?드 ?롯 ?괴 ???각???데?트
		if equipmentSlotName == "HAND" and current <= 0 then
			if EquipService then
				EquipService.equipItem(player, nil)
			end
		end
		
		-- 스탯 재계산 (방어구/공격력 변화 수치 반영)
		if PlayerStatService then
			PlayerStatService.recalculateStats(userId)
		end
	end
	
	return true, nil, current
end

--- 장비 슬롯에서 아이템 강제 제거 (사망 손실 등)
function InventoryService.removeItemFromEquipment(userId: number, equipmentSlotName: string)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return false end
	
	local slotData = inv.equipment[equipmentSlotName]
	if not slotData then return false end
	
	inv.equipment[equipmentSlotName] = nil
	
	-- SaveService 동기화
	if SaveService then
		SaveService.updatePlayerState(userId, function(state)
			state.equipment = inv.equipment
			return state
		end)
	end
	
	-- 클라이언트 알림 및 파기 효과 처리
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player then
		NetController.FireClient(player, "Inventory.Equipment.Changed", { equipment = inv.equipment })
		
		-- 장착 외형 및 스탯 갱신
		if EquipService then
			EquipService.updateAppearance(player)
			if equipmentSlotName == "HAND" then
				EquipService.equipItem(player, nil)
			end
		end
		
		if PlayerStatService then
			PlayerStatService.recalculateStats(userId)
		end
	end
	
	return true
end


--- 내구도 설정 (수리 등에 사용)
function InventoryService.setDurability(userId: number, slot: number, amount: number)
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[slot]
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	
	slotData.durability = amount
	
	-- 이벤트 발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, {_makeChange(inv, slot)})
	end
	
	return true
end

--- 현재 장착 중인(장비창 HAND 슬롯) 아이템 조회
function InventoryService.getEquippedItem(userId: number): any?
	local inv = playerInventories[userId]
	if not inv then return nil end
	
	-- [HOTBAR REMOVED] 핫바가 아닌 장비창의 HAND 슬롯에 든 장비 정보 조회
	return inv.equipment and inv.equipment.HAND
end

--- 특정 슬롯 아이템 조회
function InventoryService.getSlot(userId: number, slot: number): any?
	local inv = playerInventories[userId]
	if not inv then return nil end
	return inv.slots[slot]
end

--- 아이템 스택 가능 여부 조회 (외부 서비스용)
function InventoryService.isStackable(itemId: string): boolean
	return _isStackable(itemId)
end

--- 아이템별 최대 스택 수량 조회 (외부 서비스용)
function InventoryService.getMaxStackForItem(itemId: string): number
	return _getMaxStack(itemId)
end

--========================================
-- Network Handlers
--========================================

local function handleDropByItemId(player: Player, payload: any)
	local itemId = payload.itemId
	local count = payload.count
	local success, errorCode, data = InventoryService.dropByItemId(player, itemId, count)
	if not success then return { success = false, errorCode = errorCode } end
	return { success = true, data = data }
end

local function handleDropGold(player: Player, payload: any)
	local count = math.floor(tonumber(payload and payload.count) or 0)
	if count < 1 then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_COUNT }
	end

	local goldService = require(game:GetService("ServerScriptService").Server.Services.NPCShopService)
	local worldDropService = require(game:GetService("ServerScriptService").Server.Services.WorldDropService)
	local currentGold = goldService.getGold(player.UserId)
	if currentGold < count then
		return { success = false, errorCode = Enums.ErrorCode.INSUFFICIENT_GOLD }
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	local ok, err = goldService.removeGold(player.UserId, count)
	if not ok then
		return { success = false, errorCode = err }
	end

	local spawnOk, spawnErr = worldDropService.spawnGoldDrop(hrp.Position + hrp.CFrame.LookVector * 2 + Vector3.new(0, -1, 0), count)
	if not spawnOk then
		goldService.addGold(player.UserId, count)
		return { success = false, errorCode = spawnErr }
	end

	return {
		success = true,
		data = {
			dropType = "gold",
			goldAmount = count,
		}
	}
end

local function handleActiveSlot(player: Player, payload: any)
	local slot = payload.slot
	if type(slot) ~= "number" or slot < 1 or slot > 8 then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_SLOT }
	end
	
	InventoryService.setActiveSlot(player.UserId, slot)
	return { success = true }
end

local function handleUse(player: Player, payload: any)
	local userId = player.UserId
	local slot = payload.slot
	
	local inv = playerInventories[userId]
	if not inv then return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND } end
	
	local slotData = inv.slots[slot]
	if not slotData then return { success = false, errorCode = Enums.ErrorCode.SLOT_EMPTY } end
	
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData then return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM } end

	-- 초보자 스타터팩 상자: 사용 시 포션/링/골드 지급
	if slotData.itemId == "STARTER_PACK_BOX" then
		local rewards = {
			{ itemId = "BASIC_HP_POTION", count = 50 },
			{ itemId = "BASIC_MP_POTION", count = 50 },
			{ itemId = "WELCOME_RING", count = 1, attributes = { quality = 100 } },
		}

		if not _canAddRewardBundle(userId, rewards, slot) then
			return { success = false, errorCode = Enums.ErrorCode.INV_FULL }
		end

		local goldService = NPCShopService
		if not goldService then
			local okReq, svc = pcall(function()
				return require(Services.NPCShopService)
			end)
			if okReq then
				goldService = svc
				NPCShopService = svc
			end
		end
		if not goldService then
			return { success = false, errorCode = Enums.ErrorCode.INTERNAL_ERROR }
		end

		InventoryService.removeItemFromSlot(userId, slot, 1)

		for _, reward in ipairs(rewards) do
			local added, remaining = InventoryService.addItem(userId, reward.itemId, reward.count or 1, reward.durability, reward.attributes)
			if remaining ~= 0 then
				warn(string.format("[InventoryService] Starter pack reward add mismatch for user %d: %s remaining=%d", userId, reward.itemId, remaining))
			end
		end

		local okGold, errGold = goldService.addGold(userId, 1000)
		if not okGold then
			warn(string.format("[InventoryService] Starter pack gold grant failed for user %d: %s", userId, tostring(errGold)))
			return { success = false, errorCode = errGold or Enums.ErrorCode.INTERNAL_ERROR }
		end

		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text = "초보자 스타터팩을 사용했습니다! 포션, 웰컴 링, 골드 1000을 획득했습니다.",
			})
		end

		return { success = true, data = { action = "STARTER_PACK_OPENED" } }
	end

	-- 1. 스킬북 사용: 인벤토리에서 소모 후 스킬 습득
	if itemData.type == "SKILL_BOOK" then
		local BOOK_TO_SKILL = {
			["BOOK_GRIT"]     = "SKILL_RUNE_GRIT",
			["BOOK_STEADFAST"]= "SKILL_RUNE_STEADFAST",
			["BOOK_DROPLET"]  = "SKILL_DROPLET",
			["BOOK_EMBER"]    = "SKILL_EMBER",
			["BOOK_ROCK"]     = "SKILL_ROCK",
			["BOOK_FLAME"]    = "SKILL_RUNE_FLAME_ACTIVE",
			["BOOK_WAVE"]     = "SKILL_RUNE_WAVE_ACTIVE",
			["BOOK_SHADOW"]   = "SKILL_RUNE_SHADOW_ACTIVE",
			["BOOK_SLASH"]    = "SKILL_SLASH",
			["BOOK_DASH"]     = "SKILL_RUNE_DASH",
			["BOOK_HEAVEN"]   = "SKILL_RUNE_HEAVEN",
		}
		local skillId = BOOK_TO_SKILL[slotData.itemId]
		local state = SaveService and SaveService.getPlayerState(userId)
		if not state then
			return { success = false, errorCode = Enums.ErrorCode.INTERNAL_ERROR }
		end

		if not skillId then
			if NetController then
				NetController.FireClient(player, "Notify.Message", { text = "알 수 없는 스킬북입니다." })
			end
			return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
		end

		-- 이미 습득 여부 확인
		if state.unlockedSkills and state.unlockedSkills[skillId] then
			if NetController then
				NetController.FireClient(player, "Notify.Message", { text = "이미 습득한 스킬입니다." })
			end
			return { success = false, errorCode = Enums.ErrorCode.ALREADY_OWNED }
		end

		-- 인벤토리에서 스킬북 1개 소모
		InventoryService.removeItemFromSlot(userId, slot, 1)

		-- 스킬 습득
		state.unlockedSkills = state.unlockedSkills or {}
		state.unlockedSkills[skillId] = true
		SaveService.markPlayerDirty(userId)

		-- 클라이언트에 스킬 데이터 업데이트
		local okSkill, SkillService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.SkillService)
		end)
		if okSkill and SkillService and NetController then
			local data = {
				unlockedSkills    = state.unlockedSkills or {},
				combatTreeId      = state.combatTreeId,
				spAvailable       = SkillService.getAvailableSP(userId),
				spSpent           = state.skillPointsSpent or 0,
				activeSkillSlots  = state.activeSkillSlots or { nil, nil, nil, nil },
				level             = (PlayerStatService and PlayerStatService.getLevel(userId)) or 1,
				skillBooks        = state.skillBooks,
				equippedPassives  = state.equippedPassives or {},
			}
			NetController.FireClient(player, "Skill.Data.Updated", data)
		end

		if NetController then
			NetController.FireClient(player, "Notify.Message", { text = "스킬북을 사용하여 스킬을 습득했습니다!" })
		end

		if questItemCallback then
			task.spawn(function() questItemCallback(userId, slotData.itemId, 1) end)
		end

		return { success = true, data = { action = "SKILL_BOOK_USED", itemId = slotData.itemId } }
	end

	-- 2. 장착 가능 아이템 (무기, 도구 등)
	if itemData.type == Enums.ItemType.WEAPON or itemData.type == Enums.ItemType.TOOL or itemData.type == Enums.ItemType.ARMOR then
		-- ?? ?바(1-8)???는 경우 -> ?성 ?롯?로 ?정
		if slot >= 1 and slot <= 8 then
			InventoryService.setActiveSlot(userId, slot)
			NetController.FireClient(player, "Inventory.ActiveSlot.Changed", { slot = slot })
			return { success = true, data = { action = "SELECT", slot = slot } }
		else
			-- 가방에 ?는 경우
			
			-- [추?] 방어???이??용 ?롯(BODY ?? ?보가 ?는 경우 바로 ?착
			if itemData.type == Enums.ItemType.ARMOR and itemData.slot then
				local success, err = InventoryService.equipItem(player, slot, itemData.slot:upper())
				if success then
					return { success = true, data = { action = "EQUIP_ARMOR", slot = itemData.slot } }
				end
				-- ?�패 ???�롯 꽉참 ?? ?�반 Swap 로직?�로 ?�오버하거나 ?�러 반환
				if err then return { success = false, errorCode = err } end
			end

			-- 무기/?�구 ?��? ?�롯 ?�보 ?�는 방어�?-> ?�재 ?�성 ?�바 ?�롯�?교체(Swap)
			local activeSlot = InventoryService.getActiveSlot(userId)
			local success, err = InventoryService.move(player, slot, activeSlot, nil)
			if success then
				-- ?�동 ?�공 ???�성 ?�롯???�???�착 ?�데?�트
				local newItem = InventoryService.getSlot(userId, activeSlot)
				if EquipService then
					EquipService.equipItem(player, newItem and newItem.itemId)
				end
				return { success = true, data = { action = "EQUIP", from = slot, to = activeSlot } }
			else
				return { success = false, errorCode = err }
			end
		end
	end
	
	-- 2. DNA ?�이??(?�용 ???�감 ?�록)

		-- ?�감??DNA ?�록

		-- ?�벤?�리?�서 1�??�모 (?�롯 기반 ?�거)

		-- ?�라?�언?�에 ?�감 ?�록 ?�공 ?�림

	
	-- 2.5 포획 상자 (CAPTURE_BOX) → 길들이기 확률 굴림
	if itemData.type == Enums.ItemType.CAPTURE_BOX then
		local creatureId = itemData.creatureId
		if not creatureId then
			return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
		end

		-- ★ 파티 풀 체크: 파티가 가득 찬 상태에서는 길들이기 불가
		local PartyServiceRef = require(game:GetService("ServerScriptService").Server.Services.PartyService)
		if PartyServiceRef.isPartyFull and PartyServiceRef.isPartyFull(userId) then
			if NetController then
				NetController.FireClient(player, "Notify.Message", {
					text = "파티가 가득 찼습니다! 팰을 해제한 후 다시 시도하세요. (최대 " .. Balance.MAX_PARTY .. "마리)",
				})
			end
			return { success = false, errorCode = Enums.ErrorCode.PARTY_FULL }
		end

		-- 크리처 데이터에서 레벨 가져오기 → 길들이기 확률 계산
		local CreatureDataModule = require(game:GetService("ReplicatedStorage").Data.CreatureData)
		local SkillTreeDataModule = require(game:GetService("ReplicatedStorage").Data.SkillTreeData)
		local SkillServiceRef = require(game:GetService("ServerScriptService").Server.Services.SkillService)

		local creatureLevel = (slotData.attributes and slotData.attributes.level) or 1
		if not slotData.attributes or not slotData.attributes.level then
			-- 폴백: 데이터 모듈에서 기본 레벨 조회
			for _, cData in ipairs(CreatureDataModule) do
				if cData.id == creatureId then
					creatureLevel = cData.minLevel or 1
					break
				end
			end
		end

		-- 길들이기 확률: 레벨이 높을수록 낮음
		-- [DEV] 개발용 100% 확률 고정 — 릴리스 시 아래 원래 공식으로 복원할 것
		-- 원래 공식:
		local baseTameRate = math.clamp(0.50 - creatureLevel * 0.05, 0.05, 0.50)

		-- 스킬 보너스 적용
		local unlockedMap = SkillServiceRef.getUnlockedSkills(userId)
		local learnedList = {}
		for skillId, _ in pairs(unlockedMap) do
			table.insert(learnedList, skillId)
		end
		local tamingBonus = SkillTreeDataModule.GetTamingRateBonus(learnedList)
		local finalRate = math.clamp(baseTameRate + tamingBonus, 0.03, 0.60)

		-- 확률 굴림
		local roll = math.random()
		local tamed = roll <= finalRate

		if not tamed then
			-- 길들이기 실패 → 아이템 소모
			InventoryService.removeItemFromSlot(userId, slot, 1)
			if NetController then
				NetController.FireClient(player, "Notify.Message", {
					text = "길들이기에 실패했습니다... (확률: " .. math.floor(finalRate * 100) .. "%)",
				})
			end
			return { success = true, data = { action = "TAME_FAIL", creatureId = creatureId, tameRate = finalRate } }
		end

		-- 길들이기 성공 → PalboxService에 팰 등록
		local PalboxServiceRef = require(game:GetService("ServerScriptService").Server.Services.PalboxService)
		local HttpService = game:GetService("HttpService")
		local palUID = HttpService:GenerateGUID(false)

		-- 크리처 기본 스탯으로 팰 데이터 생성
		local creatureName = creatureId
		for _, cData in ipairs(CreatureDataModule) do
			if cData.id == creatureId then
				creatureName = cData.name or creatureId
				break
			end
		end

		-- [UPDATE] 아이템 속성에 저장된 레벨과 스탯 사용
		local creatureLevel = slotData.attributes and slotData.attributes.level or 1
		local creaturePetHealth = slotData.attributes and slotData.attributes.baseMaxHealth
		local creatureCombatPower = slotData.attributes and slotData.attributes.baseDamage
		
		local creatureWorkTypes = {}
		local creaturePetSpeed = 16
		local creatureDefense = 0

		-- 나머지 고정 데이터 (WorkTypes, Speed, Defense) 조회
		for _, cEntry in ipairs(CreatureDataModule) do
			if cEntry.id == creatureId then
				creatureWorkTypes = cEntry.workTypes or {}
				creaturePetHealth = creaturePetHealth or cEntry.petHealth or cEntry.baseHealth or 100
				creaturePetSpeed = cEntry.runSpeed or cEntry.walkSpeed or 16
				creatureCombatPower = creatureCombatPower or cEntry.petDamage or cEntry.damage or 0
				creatureDefense = cEntry.petDefense or cEntry.defense or 0
				break
			end
		end

		-- ★ 속성(특성) 롤링: 크리처 레벨 기반 랜덤 속성 부여
		local PalTraitDataModule = require(game:GetService("ReplicatedStorage").Data.PalTraitData)
		local rolledTraits = PalTraitDataModule.RollTraits(creatureLevel)
		local multipliers = PalTraitDataModule.GetAllMultipliers(rolledTraits)

		local palData = {
			uid = palUID,
			creatureId = creatureId,
			nickname = creatureName,
			level = creatureLevel,
			workTypes = creatureWorkTypes,
			combatPower = creatureCombatPower,
			traits = rolledTraits,
			stats = {
				hp = math.floor(creaturePetHealth * multipliers.hp),
				hunger = 100,
				san = 100,
				speed = math.floor(creaturePetSpeed * multipliers.speed * 10) / 10,
				attack = math.floor(creatureCombatPower * multipliers.attack),
				defense = math.floor(creatureDefense * multipliers.defense),
			},
			baseStats = {
				hp = creaturePetHealth,
				speed = creaturePetSpeed,
				attack = creatureCombatPower,
				defense = creatureDefense,
			},
			state = "STORED",
		}

		local added = PalboxServiceRef.addPal(userId, palData)
		if not added then
			-- ★ 팰박스 가득 참 → 아이템 소모하지 않음 (재시도 가능)
			if NetController then
				NetController.FireClient(player, "Notify.Message", {
					text = "팰 보관함이 가득 차서 길들일 수 없습니다!",
				})
			end
			return { success = false, errorCode = "PALBOX_FULL" }
		end

		-- 팰 등록 성공 → 아이템 소모
		InventoryService.removeItemFromSlot(userId, slot, 1)

		-- ★ 자동 파티 편성: 파티에 빈 슬롯이 있으면 즉시 편성
		local autoPartyMsg = ""
		local partyAdded, partyErr = PartyServiceRef.addToParty(userId, palUID)
		if partyAdded then
			autoPartyMsg = " 파티에 편성되었습니다!"
		else
			autoPartyMsg = " 팰 보관함에 등록되었습니다."
			warn(string.format("[InventoryService] Auto-party failed for pal %s: %s", palUID, tostring(partyErr)))
		end

		-- 성공 알림 (속성 정보 포함)
		local traitNames = {}
		for _, t in ipairs(rolledTraits) do
			table.insert(traitNames, t.name)
		end
		local traitMsg = #traitNames > 0 and (" [속성: " .. table.concat(traitNames, ", ") .. "]") or ""
		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text = creatureName .. " 길들이기 성공!" .. autoPartyMsg .. traitMsg,
			})
		end

		print(string.format("[InventoryService] Player %d tamed %s (rate: %.0f%%, traits: %d)", userId, creatureId, finalRate * 100, #rolledTraits))
		return { success = true, data = { action = "TAME_SUCCESS", creatureId = creatureId, palUID = palUID, tameRate = finalRate, traits = rolledTraits } }
	end
	
	-- 수리 키트 사용 요청 지원 (USE_REPAIR_TICKET 반환)
	if itemData.type == "REPAIR_ITEM" or itemData.type == Enums.ItemType.REPAIR_ITEM then
		print(string.format("[InventoryService] User %d requested repair ticket usage: %s", userId, slotData.itemId))
		return { success = true, data = { action = "USE_REPAIR_TICKET" } }
	end
	
	-- 3. ?모???이??
	if itemData.type == Enums.ItemType.CONSUMABLE then
		-- ?시: ?용 ?림?
		print(string.format("[InventoryService] User %d used %s", userId, slotData.itemId))
		return { success = true, data = { action = "USE", itemId = slotData.itemId } }
	end
	
	-- 3. ?식 (Phase 11 ?동)
	if itemData.type == Enums.ItemType.FOOD or itemData.foodValue then
		local hasHungerService, HungerService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.HungerService)
		end)
		
		local current, max = 0, 100
		if hasHungerService and HungerService then
			current, max = HungerService.getHunger(userId)
		end
		
		if hasHungerService and HungerService and current >= max and not itemData.healingValue and not itemData.staminaRestoreValue then
			-- 배�? 가??차있�?치유 ?�과???�는 ?�식?�면 ??먹어�?
			return { success = false, errorCode = "HUNGER_FULL" }
		end
		
		-- 배고???�복
		if itemData.foodValue and hasHungerService and HungerService then
			HungerService.eatFood(userId, itemData.foodValue)
		end
		
		-- 체력 ?�복
		if itemData.healingValue then
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid")
			if humanoid then
				if itemData.gradual then
					task.spawn(function()
						local ticks = 6
						local interval = 0.5
						local healPerTick = itemData.healingValue / ticks
						for i = 1, ticks do
							if not player.Parent then break end
							local char = player.Character
							local hum = char and char:FindFirstChild("Humanoid")
							if hum and hum.Health > 0 then
								hum.Health = math.min(hum.MaxHealth, hum.Health + healPerTick)
							else
								break
							end
							task.wait(interval)
						end
					end)
				else
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + itemData.healingValue)
				end
			end
		end
		
		-- ?�이??1�??�모
		if itemData.staminaRestoreValue then
			local StaminaService = require(game:GetService("ServerScriptService").Server.Services.StaminaService)
			if itemData.gradual then
				task.spawn(function()
					local ticks = 6
					local interval = 0.5
					local staminaPerTick = itemData.staminaRestoreValue / ticks
					for i = 1, ticks do
						if not player.Parent then break end
						StaminaService.addStamina(userId, staminaPerTick)
						task.wait(interval)
					end
				end)
			else
				StaminaService.addStamina(userId, itemData.staminaRestoreValue)
			end
		end

		InventoryService.removeItemFromSlot(userId, slot, 1)

		-- ?�스??콜백 (?�식 ??��)
		if questFoodEatenCallback then
			task.spawn(questFoodEatenCallback, userId, slotData.itemId)
		end
		
		return { success = true, data = { action = "EAT", itemId = slotData.itemId, foodValue = itemData.foodValue } }
	end
	
	return { success = false, errorCode = Enums.ErrorCode.NOT_SUPPORTED }
end

local function handleGetInventory(player: Player, payload: any)
	local userId = player.UserId
	-- [중요] ?�라?�언?��? ?�이?��? ?�청?????�버 로드가 ?�나지 ?�았?????�으므�??��?(Race Condition ?�결)
	local inv = InventoryService.getOrCreateInventory(userId)
	local slots = InventoryService.getFullInventory(userId)
	
	return {
		success = true,
		data = {
			inventory = slots, -- Client expects 'inventory'
			equipment = inv and inv.equipment or {},
			usedSlots = inv and _getUsedSlots(inv) or 0,
			maxSlots = _getMaxSlots(userId),
			maxStack = Balance.MAX_STACK,
		}
	}
end

--- ?�버�? ?�이??지�?
local function handleGiveItem(player: Player, payload: any)
	if not _canUseDebugGrant(player) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NO_PERMISSION,
		}
	end

	local body = type(payload) == "table" and payload or {}
	local itemId = type(body.itemId) == "string" and body.itemId or "STONE"
	local count = tonumber(body.count) or 30
	count = math.floor(count)
	count = math.clamp(count, 1, Balance.MAX_STACK)

	if DataService and not DataService.getItem(itemId) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NOT_FOUND,
		}
	end
	
	local userId = player.UserId
	local added, remaining = InventoryService.addItem(userId, itemId, count)
	
	return {
		success = true,
		data = {
			itemId = itemId,
			requested = count,
			added = added,
			remaining = remaining,
		}
	}
end

--========================================
-- Event Handlers
--========================================

local function onPlayerAdded(player: Player)
	local userId = player.UserId
	
	-- [MODIFIED] Race Condition Fix: Connect IMMEDIATELY
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		
		-- Ensures inventory data loads from state
		local inv = InventoryService.getOrCreateInventory(userId)
		
		-- Stabilization delay for Roblox character rig + welds
		task.delay(1.5, function()
			if not player.Parent or not character.Parent then return end
			
			if EquipService then
				EquipService.updateAppearance(player)
				
				if inv and inv.equipment and inv.equipment.HAND and inv.equipment.HAND.itemId ~= "" then
					print(string.format("[InventoryService] Restoring persistent weapon '%s' for %s", inv.equipment.HAND.itemId, player.Name))
					EquipService.equipItem(player, inv.equipment.HAND.itemId)
				end
			end
		end)
	end)
	
	-- Studio instant spawn fallback
	if player.Character then
		task.spawn(function()
			local inv = InventoryService.getOrCreateInventory(userId)
			task.delay(1.5, function()
				if EquipService and player.Parent then
					EquipService.updateAppearance(player)
					if inv and inv.equipment and inv.equipment.HAND and inv.equipment.HAND.itemId ~= "" then
						EquipService.equipItem(player, inv.equipment.HAND.itemId)
					end
				end
			end)
		end)
	end

	-- Trigger background load
	task.spawn(function()
		InventoryService.getOrCreateInventory(userId)
	end)
end


-- onPlayerRemoving moved to SaveService to prevent Race Condition

--========================================
-- Initialization
--========================================

function InventoryService.Init(netController, dataService, saveService, playerStatService, equipService)
	if initialized then
		warn("[InventoryService] Already initialized")
		return
	end
	
	NetController = netController
	DataService = dataService
	SaveService = saveService
	PlayerStatService = playerStatService
	EquipService = equipService
	
	-- [신규 아키텍처] SaveService 완료 이벤트 연동
	SaveService.PlayerSaveLoaded.Event:Connect(function(userId, state)
		InventoryService.getOrCreateInventory(userId)
	end)

	-- ?레?레?어 ?벤???결
	Players.PlayerAdded:Connect(onPlayerAdded)
	
	-- ?? ?속???레?어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	
	initialized = true
	print(string.format("[InventoryService] Initialized - Slots: %d, MaxStack: %d", 
		Balance.MAX_INV_SLOTS, Balance.MAX_STACK))
end

--========================================
-- Public API: Drop Excess Items (스탯 초기화 시)
--========================================

--- newMaxSlots를 초과하는 슬롯의 아이템을 월드에 드랍하고 인벤에서 제거
--- @return table 드랍된 아이템 목록 {{itemId, count, durability}}
function InventoryService.dropExcessItems(player: Player, newMaxSlots: number): {{itemId: string, count: number, durability: number?}}
	local userId = player.UserId
	local inv = playerInventories[userId]
	if not inv then return {} end
	
	local droppedItems = {}
	local changedSlots = {}
	
	-- newMaxSlots+1 ~ MAX_INV_SLOTS 범위의 아이템 수집 및 제거
	for slot = newMaxSlots + 1, Balance.MAX_INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData then
			table.insert(droppedItems, {
				itemId = slotData.itemId,
				count = slotData.count,
				durability = slotData.durability,
			})
			inv.slots[slot] = nil
			changedSlots[slot] = true
		end
	end
	
	if #droppedItems <= 0 then return droppedItems end
	
	-- WorldDropService 지연 로딩으로 월드에 드랍
	local wdOk, WorldDropService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.WorldDropService)
	end)
	
	if wdOk and WorldDropService and WorldDropService.spawnDrop then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local basePos = hrp.Position + Vector3.new(0, -1, 0)
			for i, item in ipairs(droppedItems) do
				-- 아이템별로 약간 다른 위치에 드랍 (원형 배치)
				local angle = (i - 1) * (2 * math.pi / math.max(#droppedItems, 1))
				local offset = Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3)
				WorldDropService.spawnDrop(basePos + offset, item.itemId, item.count, item.durability)
			end
		end
	end
	
	-- 클라이언트에 변경 알림
	local changes = {}
	for slot, _ in pairs(changedSlots) do
		table.insert(changes, _makeChange(inv, slot))
	end
	_emitChanged(player, changes)
	
	return droppedItems
end

function InventoryService.GetHandlers()
	local handlers = {
		["Inventory.Move.Request"] = function(player, payload)
			local success, err, data = InventoryService.move(player, payload.fromSlot, payload.toSlot, payload.count)
			return { success = success, errorCode = err, data = data }
		end,
		["Inventory.Split.Request"] = function(player, payload)
			local success, err, data = InventoryService.split(player, payload.fromSlot, payload.toSlot, payload.count)
			return { success = success, errorCode = err, data = data }
		end,
		["Inventory.Drop.Request"] = function(player, payload)
			local success, err, data = InventoryService.drop(player, payload.slot, payload.count)
			return { success = success, errorCode = err, data = data }
		end,
		["Inventory.DropByItemId.Request"] = handleDropByItemId,
		["Inventory.DropGold.Request"] = handleDropGold,
		["Inventory.Get.Request"] = handleGetInventory,
		-- [HOTBAR REMOVED] ActiveSlot 관련 네트워크 요청 핸들러 미사용
		["Inventory.Use.Request"] = handleUse,
		["Inventory.Equip.Request"] = function(player, payload)
			local success, err = InventoryService.equipItem(player, payload.fromSlot, payload.toSlot)
			return { success = success, errorCode = err }
		end,
		["Inventory.Unequip.Request"] = function(player, payload)
			local success, err = InventoryService.unequipItem(player, payload.slot)
			return { success = success, errorCode = err }
		end,
		["Inventory.Sort.Request"] = function(player, payload)
			InventoryService.sort(player.UserId)
			return { success = true }
		end,
		["Inventory.SaveQuickslots.Request"] = function(player, payload)
			local userId = player.UserId
			local quickslots = payload.quickslots
			if type(quickslots) == "table" then
				local state = SaveService.getPlayerState(userId)
				if state then
					state.quickslots = _normalizeQuickslots(quickslots)
					if SaveService.markPlayerDirty then
						SaveService.markPlayerDirty(userId)
					end
					
					local ok, TutorialQuestService = pcall(function()
						return require(game:GetService("ServerScriptService").Server.Services.TutorialQuestService)
					end)
					if ok and TutorialQuestService and TutorialQuestService.OnQuickslotSaved then
						TutorialQuestService.OnQuickslotSaved(userId, state.quickslots)
					end
					
					return { success = true }
				end
			end
			return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
		end,
		["Inventory.GetQuickslots.Request"] = function(player, payload)
			local userId = player.UserId
			local state = SaveService.getPlayerState(userId)
			if state then
				return { success = true, quickslots = _normalizeQuickslots(state.quickslots) }
			end
			return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
		end,
	}

	if RunService:IsStudio() then
		handlers["Inventory.GiveItem"] = handleGiveItem
	end

	return handlers
end

function InventoryService.SetQuestItemCallback(callback)
	questItemCallback = callback
end

function InventoryService.SetQuestFoodEatenCallback(callback)
	questFoodEatenCallback = callback
end

--========================================
-- Robux Purchase Handler (ProcessReceipt)
--========================================
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

function InventoryService.ProcessReceipt(receiptInfo)
	local userId = receiptInfo.PlayerId
	local productId = tostring(receiptInfo.ProductId)
	local purchaseId = receiptInfo.PurchaseId
	
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- 1. SaveService가 유효한지 확인하고 플레이어 상태 로드
	if not SaveService or not SaveService.getPlayerState then
		warn("[Purchase] SaveService not ready, deferring purchase")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local state = SaveService.getPlayerState(userId)
	if not state then
		warn(string.format("[Purchase] Player state not loaded for user %d, deferring purchase", userId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- 2. 중복 수령 방지 (Deduplication Check)
	state.processedPurchases = state.processedPurchases or {}
	if state.processedPurchases[purchaseId] then
		print(string.format("[Purchase] PurchaseId %s already processed for %s, skipping reward grant", purchaseId, player.Name))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	
	-- ProductConfig 로딩
	local ProductConfig = nil
	pcall(function()
		ProductConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ProductConfig"))
	end)
	
	if not (ProductConfig and ProductConfig.PRODUCTS) then
		warn("[Purchase] ProductConfig or PRODUCTS not loaded, deferring purchase")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local productData = ProductConfig.PRODUCTS[productId]
	if not productData then
		warn(string.format("[Purchase] Product data missing for ProductId %s, deferring purchase", productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local rewardGranted = false
	
	-- 3. 보상 처리 분기
	if productData.rewardType == "INVENTORY_EXPAND" then
		local slots = tonumber(productData.slots) or 30
		if PlayerStatService and PlayerStatService.grantInventoryBonusSlots then
			local ok, newMaxSlots, appliedSlots = PlayerStatService.grantInventoryBonusSlots(userId, slots)
			if ok then
				print(string.format("[Purchase] Inventory expansion granted to %s (+%d slots, max=%d) for product %s",
					player.Name, appliedSlots or 0, newMaxSlots or 0, productId))
				rewardGranted = true
			end
		end
		if not rewardGranted then
			warn(string.format("[Purchase] Inventory expansion failed for %s (product %s)", player.Name, productId))
		end
	elseif productData.rewardType == "STARTER_PACK" then
		local boxItemId = productData.itemId or productData.boxItemId
		local amount = tonumber(productData.amount) or 1
		if type(boxItemId) == "string" and boxItemId ~= "" then
			local added, remaining = InventoryService.addItem(userId, boxItemId, amount)
			if added > 0 and remaining == 0 then
				print(string.format("[Purchase] Successfully awarded starter pack box (%s) to player %s for product %s", boxItemId, player.Name, productId))
				rewardGranted = true
			else
				warn(string.format("[Purchase] Failed to award starter pack box to player %s - Inventory Full? product %s", player.Name, productId))
			end
		else
			warn(string.format("[Purchase] Starter pack missing box itemId for product %s (player=%s)", productId, player.Name))
		end
	elseif productData.rewardType == "GOLD" then
		local amount = tonumber(productData.amount) or 0
		local goldService = NPCShopService
		if not goldService then
			local okReq, svc = pcall(function()
				return require(Services.NPCShopService)
			end)
			if okReq then
				goldService = svc
				NPCShopService = svc
			end
		end
		if goldService and amount > 0 then
			local ok, err = goldService.addGold(userId, amount)
			if ok then
				print(string.format("[Purchase] Successfully awarded %d gold to player %s for product %s", amount, player.Name, productId))
				rewardGranted = true
			else
				warn(string.format("[Purchase] Failed to award gold to player %s - %s", player.Name, tostring(err)))
			end
		else
			warn(string.format("[Purchase] Gold service unavailable or invalid amount for product %s (player=%s, amount=%s)", productId, player.Name, tostring(amount)))
		end
	elseif productData.rewardType == "CRAFT_SPEEDUP" then
		local craftId = player:GetAttribute("PendingInstantCompleteCraftId")
		if craftId and craftId ~= "" then
			local CraftingService = nil
			pcall(function()
				CraftingService = require(ServerScriptService.Server.Services.CraftingService)
			end)
			if CraftingService then
				local ok, err, data = CraftingService.instantComplete(player, craftId)
				if ok then
					player:SetAttribute("PendingInstantCompleteCraftId", nil)
					print(string.format("[Purchase] Successfully speeded up craft %s for player %s via product %s", craftId, player.Name, productId))
					rewardGranted = true
				else
					warn(string.format("[Purchase] Failed to speed up craft %s for player %s: %s", craftId, player.Name, tostring(err)))
				end
			else
				warn("[Purchase] CraftingService not found for speedup")
			end
		else
			warn(string.format("[Purchase] No PendingInstantCompleteCraftId found for player %s on speedup purchase", player.Name))
		end
	elseif productData.itemId then
		local itemId = productData.itemId
		local amount = productData.amount or 1
		local added, remaining = InventoryService.addItem(userId, itemId, amount)
		if added > 0 then
			print(string.format("[Purchase] Successfully awarded %d of %s to player %s for product %s", amount, itemId, player.Name, productId))
			rewardGranted = true
		else
			warn(string.format("[Purchase] Failed to award %s to player %s - Inventory Full?", itemId, player.Name))
		end
	end
	
	-- 4. Failsafe Save 및 최종 판정
	if rewardGranted then
		-- 중복 방지 기록
		state.processedPurchases[purchaseId] = true
		if SaveService.markPlayerDirty then
			SaveService.markPlayerDirty(userId)
		end
		
		-- 즉시 DB 저장
		if SaveService.savePlayer then
			local saveSuccess, saveErr = SaveService.savePlayer(userId)
			if saveSuccess then
				print(string.format("[Purchase] Successfully saved purchase %s to DataStore for %s", purchaseId, player.Name))
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				-- 저장 실패 시 메모리 데이터 롤백 후 재시도 유도 (로벅스 차감 안 됨)
				state.processedPurchases[purchaseId] = nil
				warn(string.format("[Purchase] Failed to save database for purchase %s: %s. Rolling back and deferring.", purchaseId, tostring(saveErr)))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		else
			-- 만약 savePlayer가 비정상적으로 누락된 경우
			warn("[Purchase] SaveService.savePlayer function not found! Deferring purchase to prevent data loss.")
			state.processedPurchases[purchaseId] = nil
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	
	-- 보상 지급 자체가 실패했거나 미처리된 경우
	warn(string.format("[Purchase] Reward not granted for ProductId %s, PurchaseId %s. Deferring purchase.", productId, purchaseId))
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = InventoryService.ProcessReceipt

return InventoryService
