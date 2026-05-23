-- EnhanceService.lua
-- 무기 강화(연금) 서버 로직
-- 갱신: 오직 골드만 소모하며 장착/인벤토리 무기 강화 지원

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)
local InventoryService = require(ServerScriptService.Server.Services.InventoryService)
local NPCShopService = require(ServerScriptService.Server.Services.NPCShopService)

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local NetController = require(Controllers.NetController)

local EnhanceService = {}

-- 강화 골드 비용 곡선
local function getEnhanceCost(level: number): number
	if level < 5 then
		return 100 + level * 100
	elseif level < 10 then
		return 1000 + (level - 5) * 500
	elseif level < 15 then
		return 5000 + (level - 10) * 2000
	elseif level < 20 then
		return 20000 + (level - 15) * 5000
	else
		return 50000 + (level - 20) * 10000
	end
end

-- 계단식 성공 확률 곡선
local function getSuccessRate(level: number): number
	if level == 0 then
		return 1.00
	elseif level < 5 then
		return 0.90 - (level - 1) * 0.10
	elseif level < 10 then
		return 0.50 - (level - 5) * 0.06
	elseif level < 15 then
		return 0.20 - (level - 10) * 0.03
	elseif level < 20 then
		return 0.05 - (level - 15) * 0.008
	elseif level < 30 then
		return 0.01
	else
		return 0.002
	end
end

function EnhanceService.Init()
	NetController.RegisterHandler("Enhance.Request", function(player, data)
		return EnhanceService.processEnhance(player, data.slot)
	end)
	print("[EnhanceService] Initialized")
end

--- 강화 로직 실행
function EnhanceService.processEnhance(player: Player, slot: any)
	local userId = player.UserId
	
	-- 1. 아이템 데이터 확인 (장착중인 무기 "HAND" 또는 인벤토리 슬롯 번호)
	local weaponData = nil
	if slot == "HAND" then
		local equipment = InventoryService.getEquipment(userId)
		weaponData = equipment and equipment.HAND
	elseif type(slot) == "number" then
		local inv = InventoryService.getInventory(userId)
		weaponData = inv and inv.slots[slot]
	end
	
	if not weaponData then
		return { success = false, error = "ITEM_NOT_FOUND" }
	end
	
	-- 2. 검증 (무기 타입 검증)
	local weaponBase = DataService.getItem(weaponData.itemId)
	if not weaponBase or (weaponBase.type ~= "WEAPON" and weaponBase.type ~= "TOOL") then
		return { success = false, error = "NOT_ENHANCEABLE" }
	end
	
	-- 3. 강화 수치 한계 검사 (최대 50강)
	local currentLevel = (weaponData.attributes and weaponData.attributes.enhanceLevel) or 0
	if currentLevel >= 50 then
		return { success = false, error = "MAX_LEVEL_REACHED" }
	end
	
	-- 4. 소지 골드 검사 및 차감
	local success, DataHelper = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
	end)
	local costMult = 1.0
	if success and DataHelper then
		costMult = DataHelper.GetEnhanceCostMultiplier(weaponBase.rarity or "COMMON")
	end
	
	local baseCost = getEnhanceCost(currentLevel)
	local cost = math.floor(baseCost * costMult)
	local playerGold = NPCShopService.getGold(userId)
	if playerGold < cost then
		return { success = false, error = "NOT_ENOUGH_GOLD" }
	end
	
	local ok, goldErr = NPCShopService.removeGold(userId, cost)
	if not ok then
		return { success = false, error = goldErr or "GOLD_DEDUCTION_FAILED" }
	end
	
	-- 5. 판정
	local finalSuccessRate = getSuccessRate(currentLevel)
	local rng = Random.new()
	local isSuccess = rng:NextNumber() <= finalSuccessRate
	
	local attributes = {}
	if weaponData.attributes then
		for k, v in pairs(weaponData.attributes) do
			attributes[k] = v
		end
	end
	
	if isSuccess then
		-- 성공: 레벨 상승
		local newLevel = currentLevel + 1
		attributes.enhanceLevel = newLevel
		
		if slot == "HAND" then
			InventoryService.updateEquipmentAttributes(userId, "HAND", attributes)
		else
			InventoryService.updateSlotAttributes(userId, slot, attributes)
		end
		
		print(string.format("[Enhance] SUCCESS: Player %d -> +%d (Cost: %d)", userId, newLevel, cost))
		return {
			success = true,
			result = "SUCCESS",
			newLevel = newLevel,
			itemId = weaponData.itemId,
			cost = cost
		}
	else
		-- 실패: 1레벨 하락 페널티
		local newLevel = math.max(0, currentLevel - 1)
		attributes.enhanceLevel = newLevel
		
		if slot == "HAND" then
			InventoryService.updateEquipmentAttributes(userId, "HAND", attributes)
		else
			InventoryService.updateSlotAttributes(userId, slot, attributes)
		end
		
		print(string.format("[Enhance] DOWN: Player %d -> +%d (Cost: %d)", userId, newLevel, cost))
		return {
			success = true,
			result = "DOWN",
			newLevel = newLevel,
			itemId = weaponData.itemId,
			isDown = true,
			cost = cost
		}
	end
end

return EnhanceService
