--[[
	BaseJump - One of the two main 'entry point' actions. Selects the type of jump to perform
	based on the character's current state.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Platformer.Constants)

local Action = {}

function Action.perform(characterController)
	-- The character can't do anything while stunned or recovering
	local action = characterController:getAction()
	if action == "Stun" or action == "Recover" then
		return
	end

	-- If the character just started rolling, put them into a long jump
	local timeSinceLastRoll = characterController:getTimeSinceAction("Roll")

	if timeSinceLastRoll <= Constants.LONG_JUMP_WINDOW then
		characterController:performAction("LongJump")
	else
		local canJump = characterController:isGrounded()
			or characterController:isSwimming()
			or characterController:isClimbing()
		-- Allow the character to still initiate a normal jump right after they've stopped being grounded.
		-- This makes jumping off the edges of platforms feel more responsive.
		local timeSinceGrounded = characterController:getTimeSinceGrounded()
		local canCoyoteJump = timeSinceGrounded <= Constants.JUMP_COYOTE_TIME

		if canJump or canCoyoteJump then
			characterController:performAction("Jump")
		else
			characterController:performAction("DoubleJump")
		end
	end
end

return Action
