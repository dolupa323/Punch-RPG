--[[
	LongJump - Performs a short vertical and long horizontal jump. Running into a wall
	stuns the character.

	A LinearVelocity is used to move the character forward, and sphere casting is used
	to check for collisions in front of the character.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local getOrCreateAttachment = require(ReplicatedStorage.Utility.getOrCreateAttachment)
local calculateVelocityForHeight = require(ReplicatedStorage.Utility.calculateVelocityForHeight)
local setVerticalVelocity = require(ReplicatedStorage.Utility.setVerticalVelocity)

local Action = {
	minTimeInAction = 0.2,
	clearOnGrounded = true,
	movementAcceleration = 1,
	animation = "LongJump",
	effect = "Jump",
	sound = "LongJump",
}

-- Long jump forward, stunning the character if they run into anything
function Action.perform(characterController)
	-- Don't let the character long jump too fast
	local timeSinceLastJump = characterController:getTimeSinceAction("LongJump")
	if timeSinceLastJump < Constants.JUMP_COOLDOWN then
		return
	end

	-- 스태미나 클라이언트 체크 (소모량 25)
	local ok, MovementController = pcall(function() return require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.MovementController) end)
	if ok and MovementController then
		local currentStamina = MovementController.getStamina()
		if currentStamina < 25 then return end
	end

	characterController:setAction("LongJump")

	local attachment =
		getOrCreateAttachment(characterController.root, "LongJumpAttachment", Vector3.xAxis, -Vector3.zAxis)

	-- We'll use a LinearVelocity to control the character's movement during the long jump
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "LongJumpVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	-- Long jump force is multiplied by the character's total mass to ensure consistency across different size characters
	velocity.MaxForce = Constants.LONG_JUMP_FORCE_FACTOR * characterController.root.AssemblyMass
	-- Velocity application is constrained to the XZ plane so the character can still move up and down
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PlaneVelocity = Vector2.new(0, Constants.LONG_JUMP_SPEED)
	velocity.Parent = characterController.root

	-- Set the character's vertical velocity to make them jump
	local jumpVelocity = calculateVelocityForHeight(Constants.LONG_JUMP_HEIGHT)
	setVerticalVelocity(characterController.root, jumpVelocity)

	local actionChangedConnection
	local heartbeatConnection
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { characterController.character }
	raycastParams.RespectCanCollide = true
	raycastParams.IgnoreWater = true

	local function finish()
		actionChangedConnection:Disconnect()
		heartbeatConnection:Disconnect()

		velocity:Destroy()
	end

	local function onHeartbeat()
		-- If the character gets removed (e.g. reseting or falling off the map), no need to do anything else
		if not characterController.character:IsDescendantOf(game) then
			finish()
			return
		end

		-- If the character starts swimming or climbing, finish
		if characterController:isSwimming() or characterController:isClimbing() then
			finish()
			return
		end

		-- Check if the character has run into anything using a spherecast, and stun them if they do.
		-- Since shape casts don't detect intersections at their origin, we offset the start of the cast in the opposite
		-- direction that we're checking and then cast back toward it.
		local position =
			characterController.root.CFrame:PointToWorldSpace(Vector3.new(0, 0, Constants.WALL_CHECK_RADIUS))
		local direction =
			characterController.root.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -Constants.WALL_CHECK_RADIUS * 2))
		local result = Workspace:Spherecast(position, Constants.WALL_CHECK_RADIUS, direction, raycastParams)
		if result then
			finish()
			local bounceDirection = result.Normal
			-- Perform the stun action, bouncing off the wall's normal direction
			characterController:performAction("Stun", bounceDirection)
		end
	end

	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	-- If the action changes to something else, we're done with this action and can finish
	actionChangedConnection = characterController.actionChanged:Once(finish)
end

return Action
