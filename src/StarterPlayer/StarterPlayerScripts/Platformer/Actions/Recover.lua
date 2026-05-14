--[[
	Recover - A simple action used to delay the character after a stun.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Platformer.Constants)

local Action = {
	movementAcceleration = 1,
	animation = "Recover",
	effect = "FloorImpact",
	sound = "FloorImpact",
}

-- Recover after being stunned
function Action.perform(characterController)
	characterController:setAction("Recover")
	-- Reset the character controller's moveDirection to zero to remove their momentum
	characterController.moveDirection = Vector3.zero

	-- Return to normal after a short delay
	task.delay(Constants.RECOVER_TIME, function()
		characterController:setAction("None")
	end)
end

return Action
