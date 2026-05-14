--[[
	Dash - An effect that creates speed lines around the character, used during dashing and rolling.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local simpleParticleTimed = require(ReplicatedStorage.Utility.simpleParticleTimed)

local dashParticlesTemplate = ReplicatedStorage.Platformer.Effects.DashParticles

local LIFETIME = 0.3

local function effect(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	simpleParticleTimed(dashParticlesTemplate, CFrame.new(), LIFETIME, root)
end

return effect
