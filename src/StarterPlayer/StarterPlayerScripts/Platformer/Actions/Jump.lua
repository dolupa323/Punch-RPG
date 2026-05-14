--[[
	Jump - A simple jump implementation using the default humanoid jumping state.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Platformer.Constants)

local Action = {
	minTimeInAction = 0.2,
	clearOnGrounded = true,
	sound = "Jump",
}

function Action.perform(characterController)
	-- The character can only jump while while they're not doing anything
	local action = characterController:getAction()
	if action ~= "None" then
		return
	end

	-- Don't let the character spam jump too fast
	local timeSinceLastJump = characterController:getTimeSinceAction("Jump")
	if timeSinceLastJump < Constants.JUMP_COOLDOWN then
		return
	end

	characterController:setAction("Jump")

	-- Change the humanoid state to jumping to make it do a normal jump
	characterController.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	-- If the character is currently climbing, apply velocity backwards to eject them off the ladder
	if characterController:isClimbing() then
		local ejectVelocity = -characterController.root.CFrame.LookVector * Constants.LADDER_EJECT_SPEED
		characterController.root.AssemblyLinearVelocity += ejectVelocity
	end
end

return Action
