--[[
	FXScript - This scripts creates and destroys FXController classes as necessary to control
	effects and sounds on all player characters.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local safePlayerAdded = require(ReplicatedStorage.Utility.safePlayerAdded)
local FXController = require(script.Parent.FXController)

local function onCharacterAdded(character: Model)
	-- Create a new FXController for each character that gets added
	local fxController = FXController.new(character)

	-- When the character is removed, we need to clean up the FXController
	local ancestryChangedConnection
	ancestryChangedConnection = character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			ancestryChangedConnection:Disconnect()
			fxController:destroy()
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

safePlayerAdded(onPlayerAdded)
