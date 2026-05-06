-- DurabilityService.lua
-- 아이템 내구도 관리 서비스 (Phase 2-4)
-- 내구도 감소 및 파괴 담당 (수리 불가 반영)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local DurabilityService = {}

-- Dependencies
local NetController
local InventoryService
local DataService
local Balance

--========================================
-- Public API
--========================================

function DurabilityService.Init(_NetController, _InventoryService, _DataService, _BuildService, _Balance)
	NetController = _NetController
	InventoryService = _InventoryService
	DataService = _DataService
	Balance = _Balance
	
	print("[DurabilityService] Initialized (No-Repair Mode)")
	
	-- 패시브 내구도 감소 루프 (예: 횃불)
	local Players = game:GetService("Players")
	local PASSIVE_DRAIN_INTERVAL = 5 -- 5초 단위 배치 처리 (1초→5초)
	
	task.spawn(function()
		while true do
			task.wait(PASSIVE_DRAIN_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local userId = player.UserId
				-- 장착 중인 아이템 가져오기
				local activeSlot = InventoryService.getActiveSlot and InventoryService.getActiveSlot(userId)
				if activeSlot then
					local slotData = InventoryService.getSlot and InventoryService.getSlot(userId, activeSlot)
					if slotData and slotData.itemId and slotData.durability then
						local itemData = DataService.getItem(slotData.itemId)
						if itemData and itemData.passiveDurabilityDrain and itemData.passiveDurabilityDrain > 0 then
							-- 누적량 일괄 감소 (drain × interval)
							DurabilityService.reduceDurability(player, activeSlot, itemData.passiveDurabilityDrain * PASSIVE_DRAIN_INTERVAL)
						end
					end
				end
			end
		end
	end)
end

--- 내구도 감소 요청 (채집, 공격 등에서 호출)
--- @param player Player
--- @param slot number 인벤토리 슬롯
--- @param amount number 감소량 (양수)
--- @return boolean success
function DurabilityService.reduceDurability(player: Player, slot: number, amount: number): boolean
	if not player or not slot or not amount then return false end
	if amount <= 0 then return false end -- 감소량은 양수여야 함
	
	local userId = player.UserId
	
	-- InventoryService에 위임 (내구도 0 시 InventoryService에서 파괴 처리됨)
	local success, errorCode, current = InventoryService.decreaseDurability(userId, slot, amount)
	
	if not success then
		if errorCode ~= Enums.ErrorCode.INVALID_ITEM then
			warn(string.format("[DurabilityService] Failed to reduce durability for player %d slot %d: %s", 
				userId, slot, tostring(errorCode)))
		end
		return false
	end
	
	return true
end

--========================================
-- Network Handlers
--========================================

function DurabilityService.GetHandlers()
	return {
		["Durability.Repair.Request"] = function(player, payload)
			local userId = player.UserId
			local ticketSlot = tonumber(payload.ticketSlot)
			local targetSlot = tonumber(payload.targetSlot)
			
			if not ticketSlot or not targetSlot then
				return { success = false, errorCode = Enums.ErrorCode.INVALID_SLOT }
			end
			
			-- 1. 수리권 정보 검증
			local ticketItem = InventoryService.getSlot(userId, ticketSlot)
			if not ticketItem then
				return { success = false, errorCode = Enums.ErrorCode.SLOT_EMPTY }
			end
			
			local ticketData = DataService.getItem(ticketItem.itemId)
			if not ticketData or ticketData.type ~= "REPAIR_ITEM" then
				return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
			end
			
			-- 2. 수리 대상 장비 검증
			local targetItem = InventoryService.getSlot(userId, targetSlot)
			if not targetItem then
				return { success = false, errorCode = Enums.ErrorCode.SLOT_EMPTY }
			end
			
			local targetData = DataService.getItem(targetItem.itemId)
			if not targetData or not targetItem.durability then
				return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
			end
			
			-- 최대 내구도 확인 및 이미 가득 찬 경우의 예외 리턴 처리
			local maxDur = targetData.durability or 100
			if targetItem.durability >= maxDur then
				return { success = false, errorCode = "ALREADY_MAX_DURABILITY" }
			end
			
			-- 3. 내구도 복구 연산
			local repairAmt = ticketData.repairAmount or 30
			local newDur = math.min(maxDur, targetItem.durability + repairAmt)
			
			-- 4. 재료 소모 및 내구도 적용
			InventoryService.removeItemFromSlot(userId, ticketSlot, 1)
			InventoryService.setDurability(userId, targetSlot, newDur)
			
			return { success = true, newDurability = newDur }
		end,
	}
end

return DurabilityService
