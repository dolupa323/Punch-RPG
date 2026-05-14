--[[
	FXController - This module script implements a class to handle sounds and effects for characters.
	Actions are replicated with the Constants.REPLICATED_ACTION_ATTRIBUTE on the character, and each
	action can have associated effects and sounds to play.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Platformer.Constants)
local loadModules = require(ReplicatedStorage.Utility.loadModules)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local playSoundFromSource = require(ReplicatedStorage.Utility.playSoundFromSource)

local Actions = loadModules(script.Parent.Actions)
local Effects = loadModules(script.Parent.Effects)

local camera = Workspace.CurrentCamera
local player = Players.LocalPlayer
local animations = ReplicatedStorage.Platformer.Animations
local sounds = ReplicatedStorage.Platformer.Sounds

local audioEmitterTemplate = script:FindFirstChild("CharacterAudioEmitter")
if not audioEmitterTemplate then
	audioEmitterTemplate = Instance.new("Attachment")
	audioEmitterTemplate.Name = "CharacterAudioEmitter"
	-- 템플릿용이므로 Parent는 설정하지 않음
end

local FXController = {}
FXController.__index = FXController

function FXController.new(character: Model)
	-- Characters are not replicated atomically so we need to wait for children to replicate
	local root = character:WaitForChild("HumanoidRootPart")
	local isLocalCharacter = character == player.Character

	-- Create an audio emitter
	local audioEmitter = audioEmitterTemplate:Clone()
	audioEmitter.Parent = root

	local self = {
		isLocalCharacter = isLocalCharacter,
		character = character,
		root = root,
		audioEmitter = audioEmitter,
		animationTracks = {},
		connections = {},
	}
	setmetatable(self, FXController)

	self:initialize()

	return self
end

function FXController:initialize()
	-- Animations only need to be initialized if this is the local character, since they will automatically replicate
	if self.isLocalCharacter then
		self:initializeAnimations()
	end

	-- Since we are using two attributes: one that's set locally and one that's replicated by the server,
	-- we need to select the correct one based on if this is our local character or not.
	local actionAttribute = if self.isLocalCharacter
		then Constants.ACTION_ATTRIBUTE
		else Constants.REPLICATED_ACTION_ATTRIBUTE

	-- When the character's action changes, do the associated FX
	table.insert(
		self.connections,
		self.character:GetAttributeChangedSignal(actionAttribute):Connect(function()
			local action = self.character:GetAttribute(actionAttribute)
			self:doActionFX(action)
		end)
	)
end

function FXController:doActionFX(action: string)
	local actionModule = Actions[action]
	if not actionModule then
		return
	end

	-- If the action has an associated effect, run it
	if actionModule.effect then
		-- Only run effects if the character is close enough. Effects on the local character are always run.
		local distance = (self.root.Position - camera.CFrame.Position).Magnitude
		if self.isLocalCharacter or distance < Constants.EFFECTS_MAX_DISTANCE then
			local effectFunction = Effects[actionModule.effect]
			if effectFunction then
				effectFunction(self.character)
			else
				warn(`Missing effect: {actionModule.effect}`)
			end
		end
	end

	-- If the action has an associated sound, play it
	if actionModule.sound then
		local soundTemplate = sounds:FindFirstChild(actionModule.sound)
		if soundTemplate then
			-- 사운드를 Attachment 대신 직접 HumanoidRootPart에 붙여서 확실하게 들리도록 수정
			pcall(function()
				local sound = soundTemplate:Clone()
				sound.Parent = self.root
				sound:Play()
				game:GetService("Debris"):AddItem(sound, math.max(sound.TimeLength, 2))
			end)
		else
			warn(`[FXController] Missing sound: {actionModule.sound}`)
		end
	end
end

function FXController:initializeAnimations()
	-- Characters are not replicated atomically so we need to wait for children to replicate
	local humanoid = self.character:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator")

	-- Load animations
	for _, animation in animations:GetChildren() do
		local animationTrack = animator:LoadAnimation(animation)
		self.animationTracks[animation.Name] = animationTrack
	end

	-- When the character's action changes, play the associated animation
	table.insert(
		self.connections,
		self.character:GetAttributeChangedSignal(Constants.ACTION_ATTRIBUTE):Connect(function()
			local action = self.character:GetAttribute(Constants.ACTION_ATTRIBUTE)
			self:playActionAnimation(action)
		end)
	)
end

function FXController:playActionAnimation(action: string)
	-- If we're currently playing a looped action animation, stop it
	if self.loopedActionAnimation then
		self.loopedActionAnimation:Stop()
		self.loopedActionAnimation = nil
	end

	-- Check that there's an action module for this action
	local actionModule = Actions[action]
	if not actionModule then
		return
	end

	-- If the action doesn't have a set animation, no need to do anything
	if not actionModule.animation then
		return
	end

	local animationTrack = self.animationTracks[actionModule.animation]
	if not animationTrack then
		warn(`Missing animation: {actionModule.animation}`)
		return
	end

	-- Play the animation
	animationTrack:Play(Constants.ACTION_ANIMATION_FADE_TIME)

	-- If this is a looped animation, keep track of it so we can stop it later
	if animationTrack.Looped then
		self.loopedActionAnimation = animationTrack
	end
end

function FXController:destroy()
	disconnectAndClear(self.connections)
	self.audioEmitter:Destroy()
end

return FXController
