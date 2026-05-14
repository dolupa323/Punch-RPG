--[[
	Stun - Bounces the character backwards after running into a wall during a long jump.

	A LinearVelocity is used to move the character, and sphere casting is used to check for collisions.
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
	movementAcceleration = 0,
	animation = "Stun",
	effect = "WallImpact",
	sound = "WallImpact",
}

-- Bounce back off a wall and enter recovery after landing on the ground
function Action.perform(characterController, direction: Vector3)
	-- Flatten the direction out to only be on the XZ plane
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	characterController:setAction("Stun")

	local attachment = getOrCreateAttachment(characterController.root, "StunAttachment")

	-- We'll use a LinearVelocity to control the character's movement during the stun
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "StunVelocity"
	velocity.Attachment0 = attachment :: Attachment
	-- Velocity application is constrained to the XZ plane so the character can still move up and down
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	-- Stun force is multiplied by the character's total mass to ensure consistency across different size characters
	velocity.MaxForce = Constants.STUN_FORCE_FACTOR * characterController.root.AssemblyMass
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Constants.STUN_BOUNCE_SPEED
	velocity.Parent = characterController.root

	-- Add a small bounce upward
	local verticalVelocity = calculateVelocityForHeight(Constants.STUN_BOUNCE_HEIGHT)
	setVerticalVelocity(characterController.root, verticalVelocity)

	local heartbeatConnection
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { characterController.character }
	raycastParams.RespectCanCollide = true
	raycastParams.IgnoreWater = true

	local function finish()
		heartbeatConnection:Disconnect()

		velocity:Destroy()
	end

	local function onHeartbeat()
		-- If the character gets removed (e.g. reseting or falling off the map), no need to do anything else
		if not characterController.character:IsDescendantOf(game) then
			finish()
			return
		end

		-- If the character has landed on the ground, finish and enter recovery
		if characterController:isGrounded() then
			local timeInAction = characterController:getTimeSinceAction("Stun")
			if timeInAction >= Action.minTimeInAction then
				finish()
				characterController:performAction("Recover")
				return
			end
		end

		-- Since shape casts don't detect intersections at their origin, we offset the start of the cast in the opposite
		-- direction that we're checking and then cast back toward it.
		local checkDirection = direction * Constants.WALL_CHECK_RADIUS
		local position = characterController.root.Position - checkDirection

		-- Check if there are any walls in the direction the character is moving and bounce off of them if necessary
		local result = Workspace:Spherecast(position, Constants.WALL_CHECK_RADIUS, checkDirection * 2, raycastParams)
		if result then
			direction = Vector3.new(result.Normal.X, 0, result.Normal.Z).Unit
			velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Constants.STUN_BOUNCE_SPEED
		end
	end

	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
end

return Action
