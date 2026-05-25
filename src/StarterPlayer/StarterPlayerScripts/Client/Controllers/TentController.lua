-- TentController.lua

local TentController = {}

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local WindowManager = require(Client.Utils.WindowManager)

local initialized = false

function TentController.Init()
	if initialized then return end
	initialized = true
	
	-- 서버에서 프롬프트를 통해 UI를 열라고 지시하면 수행
	NetClient.On("Tent.OpenUI", function(data)
		WindowManager.open("TENT_UI")
	end)
end

return TentController
