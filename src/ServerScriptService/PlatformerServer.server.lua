--[[
	PlatformerServer - Handles replicating actions from clients to other clients.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local remotes = ReplicatedStorage.Platformer.Remotes
local setActionRemote = remotes:WaitForChild("SetAction")

local function onSetAction(player: Player, action: string)
	local character = player.Character
	if not character then
		return
	end

	-- Basic validation: ensure action is a string
	if type(action) ~= "string" then
		return
	end

	-- 마나(스태미나) 소모 로직
	local cost = 0
	if action == "DoubleJump" then cost = 15
	elseif action == "Dash" then cost = 20
	elseif action == "Roll" then cost = 25
	elseif action == "LongJump" then cost = 25
	end

	if cost > 0 then
		-- 서버의 StaminaService를 가져와서 소모 (실패 시 리플리케이션 안 함)
		local ok, StaminaService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.StaminaService)
		end)
		if ok and StaminaService then
			if not StaminaService.consumeStamina(player.UserId, cost) then
				return
			end
		end
	end

	-- Update the replicated action attribute and the last time it was performed
	local lastTimeAttribute = string.format(Constants.LAST_TIME_FORMAT_STRING, action)
	
	-- We use REPLICATED_ACTION_ATTRIBUTE so clients know this came from the server
	-- and not from their own local prediction.
	character:SetAttribute(lastTimeAttribute, os.clock())
	character:SetAttribute(Constants.REPLICATED_ACTION_ATTRIBUTE, action)
end

setActionRemote.OnServerEvent:Connect(onSetAction)
