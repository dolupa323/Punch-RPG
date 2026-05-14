--[[
	Dash - Performs a dash forward using a LinearVelocity to move the character.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local getOrCreateAttachment = require(ReplicatedStorage.Utility.getOrCreateAttachment)

local Action = {
	clearOnGrounded = true,
	movementAcceleration = 4,
	animation = "Dash",
	effect = "Dash",
	sound = "Dash",
}

-- Dash forward through the air for a short period of time
function Action.perform(characterController)
	-- Make sure the character is currently allowed to dash
	local canDash = characterController.character:GetAttribute(Constants.CAN_DASH_ATTRIBUTE)
	if not canDash then
		return
	end

	characterController.character:SetAttribute(Constants.CAN_DASH_ATTRIBUTE, false)
	-- 스태미나 클라이언트 체크 (소모량 20)
	local ok, MovementController = pcall(function() return require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.MovementController) end)
	if ok and MovementController then
		local currentStamina = MovementController.getStamina()
		if currentStamina < 20 then return end
	end

	characterController:setAction("Dash")

	local attachment = getOrCreateAttachment(characterController.root, "DashAttachment")

	-- We'll use a LinearVelocity to control the character's movement during the dash
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment :: Attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	-- Dash force is multiplied by the character's total mass to ensure consistency across different size characters
	velocity.MaxForce = Constants.DASH_FORCE_FACTOR * characterController.root.AssemblyMass
	velocity.VectorVelocity = Vector3.new(0, 0, -Constants.DASH_SPEED)
	velocity.Parent = characterController.root

	task.delay(Constants.DASH_TIME, velocity.Destroy, velocity)
end

return Action
