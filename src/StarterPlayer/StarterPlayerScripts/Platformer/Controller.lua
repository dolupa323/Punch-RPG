--[[
	Controller - This module script implements the character controller class. This class
	handles character movement, momentum, and performing actions, as well as utility functions
	to read the humanoid's state.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local loadModules = require(ReplicatedStorage.Utility.loadModules)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)

local Actions = loadModules(script.Parent.Actions)

local remotes = ReplicatedStorage.Platformer.Remotes
local setActionRemote = remotes.SetAction

local Controller = {}
Controller.__index = Controller

function Controller.new(character: Model)
	-- Characters are not replicated atomically so we need to wait for children to replicate
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")

	local self = {
		character = character,
		humanoid = humanoid,
		root = root,
		inputDirection = Vector3.zero,
		moveDirection = Vector3.zero,
		connections = {},
		actionChanged = character:GetAttributeChangedSignal(Constants.ACTION_ATTRIBUTE),
	}
	setmetatable(self, Controller)
	return self
end

function Controller:setInputDirection(inputDirection: Vector3)
	if inputDirection.Magnitude > 1 then
		inputDirection = inputDirection.Unit
	end
	self.inputDirection = inputDirection
end

function Controller:isSwimming(): boolean
	local humanoidState = self.humanoid:GetState()
	return humanoidState == Enum.HumanoidStateType.Swimming
end

function Controller:isClimbing(): boolean
	local humanoidState = self.humanoid:GetState()
	return humanoidState == Enum.HumanoidStateType.Climbing
end

function Controller:isGrounded(): boolean
	return self.humanoid.FloorMaterial ~= Enum.Material.Air
end

function Controller:getAction(): string
	return self.character:GetAttribute(Constants.ACTION_ATTRIBUTE) or "None"
end

function Controller:setAction(action: string)
	local lastTimeAttribute = string.format(Constants.LAST_TIME_FORMAT_STRING, action)

	self.character:SetAttribute(lastTimeAttribute, os.clock())
	self.character:SetAttribute(Constants.ACTION_ATTRIBUTE, action)

	setActionRemote:FireServer(action)
end

function Controller:getTimeSinceAction(action: string): number
	local lastTimeAttribute = string.format(Constants.LAST_TIME_FORMAT_STRING, action)
	local lastTime = self.character:GetAttribute(lastTimeAttribute) or 0
	return os.clock() - lastTime
end

function Controller:getTimeSinceGrounded(): number
	local lastGroundedTime = self.character:GetAttribute(Constants.LAST_GROUNDED_ATTRIBUTE) or 0
	return os.clock() - lastGroundedTime
end

function Controller:performAction(action: string, ...)
	local actionModule = Actions[action]
	if not actionModule then
		warn(`Invalid action: {action}`)
		return
	end

	actionModule.perform(self, ...)
end

function Controller:getAcceleration(): number
	-- Check if the current action has a set acceleration to use
	local action = self:getAction()
	local actionModule = Actions[action]
	if actionModule and actionModule.movementAcceleration then
		return actionModule.movementAcceleration
	end

	if self:isClimbing() then
		return Constants.LADDER_ACCELERATION
	elseif self:isSwimming() then
		return Constants.WATER_ACCELERATION
	elseif not self:isGrounded() then
		return Constants.AIR_ACCELERATION
	end

	return Constants.GROUND_ACCELERATION
end

function Controller:update(deltaTime: number)
	local isGrounded = self:isGrounded()

	-- Allow dashing and double jumping again once the character is grounded/climbing/swimming.
	-- Additionally, check if the current action needs to be cleared
	if isGrounded or self:isClimbing() or self:isSwimming() then
		self:tryClearGroundedAction()
		self.character:SetAttribute(Constants.CAN_DASH_ATTRIBUTE, true)
		self.character:SetAttribute(Constants.CAN_DOUBLE_JUMP_ATTRIBUTE, true)
	end

	if isGrounded then
		self.character:SetAttribute(Constants.LAST_GROUNDED_ATTRIBUTE, os.clock())
	end

	-- Lerp moveDirection to inputDirection at a constant rate
	if self.moveDirection ~= self.inputDirection then
		-- Get the character's current acceleration and update moveDirection toward inputDirection
		local acceleration = self:getAcceleration()
		local offset = self.inputDirection - self.moveDirection
		local maxChange = acceleration * deltaTime

		-- Make sure we don't overshoot the target
		if offset.Magnitude <= maxChange then
			self.moveDirection = self.inputDirection
		else
			self.moveDirection += offset.Unit * maxChange
		end
	end

	-- Move the character
	self.humanoid:Move(self.moveDirection)
end

function Controller:tryClearGroundedAction()
	local action = self:getAction()
	local actionModule = Actions[action]
	if actionModule and actionModule.clearOnGrounded then
		local minTimeInAction = actionModule.minTimeInAction or 0
		local timeSinceAction = self:getTimeSinceAction(action)
		if timeSinceAction >= minTimeInAction then
			self:setAction("None")
		end
	end
end

function Controller:destroy()
	disconnectAndClear(self.connections)
end

return Controller
