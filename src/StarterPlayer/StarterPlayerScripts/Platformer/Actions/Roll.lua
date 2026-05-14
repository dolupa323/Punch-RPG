--[[
	Roll - Performs a roll forward using a LinearVelocity to move the character.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local getOrCreateAttachment = require(ReplicatedStorage.Utility.getOrCreateAttachment)

local TOTAL_ROLL_TIME = Constants.ROLL_TIME + Constants.ROLL_COOLDOWN
local TWEEN_INFO = TweenInfo.new(Constants.ROLL_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

local Action = {
	movementAcceleration = 4,
	animation = "Roll",
	effect = "Dash",
	sound = "Roll",
}

-- Roll forward!
function Action.perform(characterController)
	-- Don't let the character roll again too quickly after performing a previous roll
	local timeSinceLastRoll = characterController:getTimeSinceAction("Roll")
	if timeSinceLastRoll < TOTAL_ROLL_TIME then
		return
	end

	-- The character can only roll while they're not doing anything else
	local initialAction = characterController:getAction()
	if initialAction ~= "None" then
		return
	end

	-- 스태미나 클라이언트 체크 (소모량 25)
	local ok, MovementController = pcall(function() return require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.MovementController) end)
	if ok and MovementController then
		local currentStamina = MovementController.getStamina()
		if currentStamina < 25 then return end
	end

	characterController:setAction("Roll")

	local attachment = getOrCreateAttachment(characterController.root, "RollAttachment", Vector3.xAxis, -Vector3.zAxis)

	-- We'll use a LinearVelocity to control the character's movement during the roll
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "RollVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	-- Roll force is multiplied by the character's total mass to ensure consistency across different size characters
	velocity.MaxForce = Constants.ROLL_FORCE_FACTOR * characterController.root.AssemblyMass
	-- Velocity application is constrained to the XZ plane so the character can still move up and down
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PlaneVelocity = Vector2.new(0, Constants.ROLL_SPEED)
	velocity.Parent = characterController.root

	-- Create a tween to ramp down the roll velocity over time
	local tween = TweenService:Create(velocity, TWEEN_INFO, { PlaneVelocity = Vector2.zero })

	local actionChangedConnection
	local tweenCompletedConnection

	local function finish()
		actionChangedConnection:Disconnect()
		tweenCompletedConnection:Disconnect()

		velocity:Destroy()

		-- Since this action is not automatically cleared when the character is grounded (it can only be performed
		-- on the ground), we need to manually set the action back to None when it finishes.
		local action = characterController:getAction()
		if action == "Roll" then
			characterController:setAction("None")
		end
	end

	-- If the current action changes (e.g. if the character begins a long jump) or the tween completes, this action
	-- is complete and we can call finish.
	actionChangedConnection = characterController.actionChanged:Once(finish)
	tweenCompletedConnection = tween.Completed:Once(finish)

	tween:Play()
end

return Action
