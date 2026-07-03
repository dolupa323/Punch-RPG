-- FountainController.lua
-- 지하에서 마을로 복귀 시 TeleportFade 처리

local FountainController = {}

local Client       = script.Parent.Parent
local NetClient    = require(Client:WaitForChild("NetClient"))
local TeleportFade = require(Client:WaitForChild("Utils"):WaitForChild("TeleportFade"))

local initialized   = false
local isTeleporting = false

function FountainController.Init()
	if initialized then return end
	initialized = true

	-- Fountain.Return (S→C): 페이드 후 청운촌으로 텔레포트
	NetClient.On("Fountain.Return", function()
		if isTeleporting then return end
		isTeleporting = true
		task.spawn(function()
			TeleportFade.execute(function()
				NetClient.Request("Fountain.Return.Request", {})
			end)
			isTeleporting = false
		end)
	end)

	print("[FountainController] Initialized.")
end

return FountainController
