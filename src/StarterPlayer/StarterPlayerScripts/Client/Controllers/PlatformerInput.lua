-- PlatformerInput.lua
-- Shared bridge for platformer character actions.

local PlatformerInput = {}

local currentController = nil

function PlatformerInput.setController(controller)
	currentController = controller
end

function PlatformerInput.clearController(controller)
	if controller == nil or currentController == controller then
		currentController = nil
	end
end

function PlatformerInput.getController()
	return currentController
end

function PlatformerInput.requestJump()
	if currentController then
		currentController:requestJump()
	end
end

function PlatformerInput.requestSpecial()
	PlatformerInput.requestDash()
end

function PlatformerInput.requestDash()
	if currentController then
		currentController:requestDash()
	end
end

function PlatformerInput.requestSuperJump()
	if currentController then
		currentController:requestSuperJump()
	end
end

function PlatformerInput.requestDoubleJump()
	if currentController then
		currentController:requestDoubleJump()
	end
end

return PlatformerInput
