--[[
	WallImpact - An effect that creates an impact particle and stars in front of the character,
	used when the character runs into a wall during a long jump.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local simpleParticleBurst = require(ReplicatedStorage.Utility.simpleParticleBurst)

local wallImpactParticlesTemplate = ReplicatedStorage.Platformer.Effects.WallImpactParticles

local function effect(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local cframe = root.CFrame * CFrame.new(0, 0, -1)
	simpleParticleBurst(wallImpactParticlesTemplate, cframe)
end

return effect
