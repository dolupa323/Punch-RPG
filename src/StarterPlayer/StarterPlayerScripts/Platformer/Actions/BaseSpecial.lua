--[[
	BaseSpecial - One of the two main 'entry point' actions. Selects the special move to perform
	based on the character's current state.
--]]

local Action = {}

function Action.perform(characterController)
	-- The character can't do anything while stunned or recovering
	local action = characterController:getAction()
	if action == "Stun" or action == "Recover" then
		return
	end

	-- The character can't roll/dash while swimming or climbing
	if characterController:isSwimming() or characterController:isClimbing() then
		return
	end

	if characterController:isGrounded() then
		characterController:performAction("Roll")
	else
		characterController:performAction("Dash")
	end
end

return Action
