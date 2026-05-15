-- EnhanceController.lua
-- 클라이언트 강화 시스템 컨트롤러
-- 서버 통신 및 UI 연동

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local EnhanceController = {}

--========================================
-- Private State
--========================================
local initialized = false
local _UIManager = nil

--========================================
-- Public API: Server Requests
--========================================

--- 특정 슬롯의 아이템 강화 요청
function EnhanceController.requestEnhance(slot: number, callback: ((boolean, string?, any?) -> ())?)
	task.spawn(function()
		local ok, result = NetClient.Request("Enhance.Request", {
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

function EnhanceController.Init(uiManager)
	if initialized then return end
	_UIManager = uiManager
	
	-- 서버로부터 UI 오픈 요청 수신 (NPC ProximityPrompt 연동)
	NetClient.On("Enhance.OpenUI", function()
		print("[EnhanceController] Received Enhance.OpenUI event")
		if _UIManager then
			_UIManager.openEnhance()
		else
			warn("[EnhanceController] UIManager is not set!")
		end
	end)
	
	initialized = true
	print("[EnhanceController] Initialized")
end

return EnhanceController
