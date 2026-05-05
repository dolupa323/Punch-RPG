-- EnhanceService.lua
-- 무기 강화(연금) 서버 로직
-- 갱신: 듀얼 주문서(하락방지 + 파괴방지) 동시 적용 지원

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataService = require(ServerScriptService.Server.Services.DataService)
local InventoryService = require(ServerScriptService.Server.Services.InventoryService)

local Server = ServerScriptService:WaitForChild("Server")
local Controllers = Server:WaitForChild("Controllers")
local NetController = require(Controllers.NetController)

local EnhanceService = {}

-- 강화 설정 데이터 (밸런스)
local ENHANCE_CONFIG = {
	BASE_SUCCESS_RATES = {
		[0] = 1.00, -- 0 -> 1
		[1] = 0.90, -- 1 -> 2
		[2] = 0.80, -- 2 -> 3
		[3] = 0.60, -- 3 -> 4
		[4] = 0.40, -- 4 -> 5
		[5] = 0.25, -- 5 -> 6
		[6] = 0.15, -- 6 -> 7
		[7] = 0.10, -- 7 -> 8
		[8] = 0.05, -- 8 -> 9
		[9] = 0.03, -- 9 -> 10
	},
	
	STONES = {
		ALCHEMY_STONE_LOW = { bonusRate = 0.00, bonusDamage = 5 },
		ALCHEMY_STONE_MID = { bonusRate = 0.10, bonusDamage = 15 },
		ALCHEMY_STONE_HIGH = { bonusRate = 0.25, bonusDamage = 40 },
	},
	
	SCROLLS = {
		ENHANCE_SCROLL_NORMAL = { bonusRate = 0.05 },
		ENHANCE_SCROLL_SURE = { bonusRate = 0.15 },
		["3586927112"] = { isDownProtect = true },    -- 하락방지권
		["3586927381"] = { isDestroyProtect = true }, -- 파괴방지권
	},
	
	RISK_BY_LEVEL = {
		[0] = { stay = 100, down = 0, destroy = 0 },
		[1] = { stay = 100, down = 0, destroy = 0 },
		[2] = { stay = 100, down = 0, destroy = 0 },
		[3] = { stay = 70, down = 25, destroy = 5 },
		[4] = { stay = 70, down = 25, destroy = 5 },
		[5] = { stay = 70, down = 25, destroy = 5 },
		[6] = { stay = 40, down = 40, destroy = 20 },
		[7] = { stay = 40, down = 40, destroy = 20 },
		[8] = { stay = 40, down = 40, destroy = 20 },
		[9] = { stay = 40, down = 40, destroy = 20 },
	}
}

function EnhanceService.Init()
	NetController.RegisterHandler("Enhance.Request", function(player, data)
		return EnhanceService.processEnhance(player, data.weaponSlot, data.stoneSlot, data.scrollSlots)
	end)
	print("[EnhanceService] Initialized")
end

--- 실패 시 결과 계산 (하락/유지/파괴)
local function calculateFailureResult(level)
	local risk = ENHANCE_CONFIG.RISK_BY_LEVEL[level] or { stay = 100, down = 0, destroy = 0 }
	local rng = math.random(1, 100)
	
	if rng <= risk.destroy then
		return "DESTROYED"
	elseif rng <= (risk.destroy + risk.down) then
		return "DOWN"
	else
		return "FAILED" -- 유지
	end
end

--- 강화 로직 실행
function EnhanceService.processEnhance(player, weaponSlot, stoneSlot, scrolls)
	local userId = player.UserId
	local inv = InventoryService.getInventory(userId)
	if not inv then return { success = false, error = "INVENTORY_NOT_FOUND" } end
	
	-- 1. 아이템 데이터 확인
	local weaponData = inv.slots[weaponSlot]
	local stoneData = inv.slots[stoneSlot]
	
	if not weaponData or not stoneData then
		return { success = false, error = "ITEM_NOT_FOUND" }
	end
	
	-- 2. 검증 (무기 타입 및 강화 재료 등급)
	local weaponBase = DataService.getItem(weaponData.itemId)
	if not weaponBase or (weaponBase.type ~= "WEAPON" and weaponBase.type ~= "TOOL") then
		return { success = false, error = "NOT_ENHANCEABLE" }
	end
	
	local stoneConfig = ENHANCE_CONFIG.STONES[stoneData.itemId]
	if not stoneConfig then
		return { success = false, error = "INVALID_ENHANCE_MATERIAL" }
	end
	
	-- 주문서 처리 (여러 개 지원)
	local scrollConfigs = {}
	if scrolls and type(scrolls) == "table" then
		for _, slotIdx in ipairs(scrolls) do
			local sData = inv.slots[slotIdx]
			if sData then
				local cfg = ENHANCE_CONFIG.SCROLLS[tostring(sData.itemId)]
				if cfg then
					table.insert(scrollConfigs, cfg)
					-- 주문서 소모
					InventoryService.removeItemFromSlot(userId, slotIdx, 1)
				end
			end
		end
	end
	
	-- 3. 확률 계산
	local currentLevel = (weaponData.attributes and weaponData.attributes.enhanceLevel) or 0
	if currentLevel >= 10 then
		return { success = false, error = "MAX_LEVEL_REACHED" }
	end
	
	local baseRate = ENHANCE_CONFIG.BASE_SUCCESS_RATES[currentLevel] or 0.01
	local stoneBonus = stoneConfig.bonusRate or 0
	
	local isDownProtected = false
	local isDestroyProtected = false
	local scrollBonusTotal = 0
	
	for _, cfg in ipairs(scrollConfigs) do
		if cfg.isDownProtect then isDownProtected = true end
		if cfg.isDestroyProtect then isDestroyProtected = true end
		scrollBonusTotal = scrollBonusTotal + (cfg.bonusRate or 0)
	end
	
	local finalSuccessRate = baseRate + stoneBonus + scrollBonusTotal
	
	-- 4. 재료 소모
	InventoryService.removeItemFromSlot(userId, stoneSlot, 1)
	
	-- 5. 판정
	local rng = Random.new()
	local isSuccess = rng:NextNumber() <= finalSuccessRate
	
	local attributes = weaponData.attributes or {}
	
	if isSuccess then
		-- 성공: 레벨 상승 및 공격력 대폭 상향
		local newLevel = currentLevel + 1
		attributes.enhanceLevel = newLevel
		
		local currentBonus = attributes.enhanceDamage or 0
		attributes.enhanceDamage = currentBonus + (stoneConfig.bonusDamage or 0)
		
		InventoryService.updateSlotAttributes(userId, weaponSlot, attributes)
		
		print(string.format("[Enhance] SUCCESS: Player %d -> +%d", userId, newLevel))
		return {
			success = true,
			result = "SUCCESS",
			newLevel = newLevel,
			itemId = weaponData.itemId,
			rates = { success = finalSuccessRate }
		}
	else
		-- 실패: 하락/유지/파괴 판정
		local failResult = calculateFailureResult(currentLevel)
		
		-- 방지권 적용
		if failResult == "DESTROYED" and isDestroyProtected then
			failResult = "FAILED"
			print(string.format("[Enhance] PROTECTED: Destruction prevented for player %d", userId))
		elseif failResult == "DOWN" and isDownProtected then
			failResult = "FAILED"
			print(string.format("[Enhance] PROTECTED: Level drop prevented for player %d", userId))
		end
		
		if failResult == "DESTROYED" then
			InventoryService.removeItemFromSlot(userId, weaponSlot, 1)
			print(string.format("[Enhance] DESTROYED: Player %d lost item", userId))
			return { success = true, result = "DESTROYED", itemId = weaponData.itemId, isDestroyed = true }
			
		elseif failResult == "DOWN" then
			local newLevel = math.max(0, currentLevel - 1)
			attributes.enhanceLevel = newLevel
			attributes.enhanceDamage = math.floor((attributes.enhanceDamage or 0) * 0.8)
			
			InventoryService.updateSlotAttributes(userId, weaponSlot, attributes)
			print(string.format("[Enhance] DOWN: Player %d -> +%d", userId, newLevel))
			return { success = true, result = "DOWN", newLevel = newLevel, itemId = weaponData.itemId, isDown = true }
			
		else
			-- 단순 실패 (유지)
			print(string.format("[Enhance] FAILED: Player %d item maintained", userId))
			return { success = true, result = "FAILED", currentLevel = currentLevel, itemId = weaponData.itemId }
		end
	end
end

return EnhanceService
