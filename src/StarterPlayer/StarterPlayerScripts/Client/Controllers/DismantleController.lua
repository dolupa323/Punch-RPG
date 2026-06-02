-- DismantleController.lua
-- 클라이언트 무기 분해 시스템 컨트롤러
-- [Client-Side NetClient & UIManager Bridge]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))

local DismantleController = {}

--========================================
-- Private State
--========================================
local initialized = false
local _UIManager = nil

--========================================
-- Public API: Server Requests
--========================================

--- 특정 인벤토리 슬롯의 무기 분해 요청
function DismantleController.requestDismantle(slot: number, callback: ((boolean, string?, any?) -> ())?)
	task.spawn(function()
		local ok, result = NetClient.Request("Dismantle.Request", {
			slot = slot
		})
		
		local success = ok and result and result.success
		local errorCode = not success and (result and result.errorCode or "UNKNOWN_ERROR") or nil
		local data = success and result.data or nil
		
		if callback then
			callback(success, errorCode, data)
		end
	end)
end

--========================================
-- Initialization
--========================================

function DismantleController.Init(uiManager)
	if initialized then return end
	_UIManager = uiManager or require(script.Parent.Parent:WaitForChild("UIManager"))
	
	-- 서버로부터 무기 분해 UI 오픈 요청 수신 (NPC ProximityPrompt 상호작용 시 트리거)
	NetClient.On("Dismantle.OpenUI", function()
		print("[DismantleController] Received Dismantle.OpenUI event")
		if _UIManager then
			_UIManager.openDismantle()
		else
			warn("[DismantleController] UIManager is not set!")
		end
	end)
	
	initialized = true
	print("[DismantleController] Initialized")
end

return DismantleController
