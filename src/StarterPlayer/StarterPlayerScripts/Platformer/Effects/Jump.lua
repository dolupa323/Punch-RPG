--[[
	Jump - An effect that creates a puff of smoke and ring particle around the character's feet,
	used for double jumping and long jumping.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local simpleParticleBurst = require(ReplicatedStorage.Utility.simpleParticleBurst)

local jumpParticlesTemplate = ReplicatedStorage.Platformer.Effects.JumpParticles

local function effect(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		return
	end

	local cframe = root.CFrame * CFrame.new(0, -humanoid.HipHeight, 0)
	simpleParticleBurst(jumpParticlesTemplate, cframe)
end

return effect
