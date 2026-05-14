--[[
	ControlScript - This script handles input and character control, redirecting default inputs
	to the Controller class.

	Since interfacing with the PlayerScripts is difficult without forking, a RenderStep loop
	is used to read movement and jump values from the local character's humanoid for input.
	Those values are then modified by the Controller and written back in order to implement
	features such as momentum.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local ActionManager = require(ReplicatedStorage.Utility.ActionManager)
local Controller = require(script.Parent.Controller)

local player = Players.LocalPlayer

local currentController = nil
local wasJumping = false

local function onCharacterAdded(character: Model)
	-- Create a new controller for the character
	local controller = Controller.new(character)

	-- Clean up the controller when the character is Destroyed
	local ancestryChangedConnection
	ancestryChangedConnection = character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			ancestryChangedConnection:Disconnect()
			controller:destroy()
			if currentController == controller then
				currentController = nil
			end
		end
	end)

	currentController = controller
end

local function onRenderStep(deltaTime: number)
	if not currentController then
		return
	end

	-- Since the default control scripts are brittle and hard to hook into, we'll read input from the humanoid itself.
	-- GetMoveVelocity() returns inputDirection * walkSpeed so we need to divide by walkSpeed again to normalize it.
	local moveDirection = Vector3.zero
	if currentController.humanoid.WalkSpeed ~= 0 then
		moveDirection = currentController.humanoid:GetMoveVelocity() / currentController.humanoid.WalkSpeed
	end
	local isJumping = currentController.humanoid.Jump
	local shouldJump = isJumping and not wasJumping

	-- Reset humanoid Jump to false to disable the default jumping mechanics
	currentController.humanoid.Jump = false
	wasJumping = isJumping

	-- Update our own controller with the move direction
	currentController:setInputDirection(moveDirection)
	currentController:update(deltaTime)

	-- If the humanoid was attempting to jump, perform a jump action
	if shouldJump then
		currentController:performAction("BaseJump")
	end
end

local function onSpecialActionInput(_input: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end

	if not currentController then
		return
	end

	-- Either roll or dash when the user activates their special move
	currentController:performAction("BaseSpecial")
end

local function initialize()
	player.CharacterAdded:Connect(onCharacterAdded)

	-- The default controls are bound on renderstep, so we'll bind at the highest priority to override them
	RunService:BindToRenderStep(Constants.CONTROLLER_RENDER_STEP_BIND, Enum.RenderPriority.Last.Value, onRenderStep)
	ActionManager.bindAction(
		Constants.SPECIAL_ACTION_BIND,
		onSpecialActionInput,
		Constants.KEYBOARD_SPECIAL_KEY_CODE,
		Constants.GAMEPAD_SPECIAL_KEY_CODE
	)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

initialize()
