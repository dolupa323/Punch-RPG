-- DurabilityService.lua
-- [DEACTIVATED] 내구도 시스템 완전 제거 및 비활성화 (No-op Dummy Service)
-- 이 게임은 내구도(Durability) 개념 자체가 없으므로, 서버 런타임 에러 예방을 위해 더미 형태로만 존재합니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local DurabilityService = {}

function DurabilityService.Init(_NetController, _InventoryService, _DataService, _BuildService, _Balance)
	print("[DurabilityService] System Deactivated (No-op mode active)")
	-- 모든 내구도 감소 루프 및 스케줄러 영구 차단
end

function DurabilityService.reduceDurability(player: Player, slot: number, amount: number): boolean
	-- 내구도가 없으므로 어떠한 차감 연산도 수행하지 않고 즉시 성공 반환
	return true
end

function DurabilityService.GetHandlers()
	return {
		["Durability.Repair.Request"] = function(player, payload)
			-- 내구도 수리 요청 시 지원하지 않음 에러 리턴
			return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
		end,
	}
end

return DurabilityService
