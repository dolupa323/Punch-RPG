-- MovementAbilityController.lua
-- Code-driven movement abilities: jump, double jump, super jump, dash, and hit reaction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))

local Client = script.Parent.Parent
local InputManager = require(Client:WaitForChild("InputManager"))
local NetClient = require(Client:WaitForChild("NetClient"))
local AnimationManager = require(Client:WaitForChild("Utils"):WaitForChild("AnimationManager"))
local PlatformerInput = require(script.Parent:WaitForChild("PlatformerInput"))
local SkillController = require(script.Parent:WaitForChild("SkillController"))

local MovementAbilityController = {}

local player = Players.LocalPlayer
local initialized = false

local currentCharacter: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local rootAttachment: Attachment? = nil
local dashVelocity: LinearVelocity? = nil
local connections = {}

local lastGroundedTime = 0
local dashReady = true
local doubleJumpReady = true
local superJumpReady = true
local stunnedUntil = 0
local dashEndsAt = 0
local dashAvailableAt = 0

local function disconnectAll()
	for _, connection in ipairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function isStunned(): boolean
	return os.clock() < stunnedUntil
end

local function isGrounded(): boolean
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function isCoyoteJumpAllowed(): boolean
	return os.clock() - lastGroundedTime <= Balance.MOVEMENT_JUMP_COYOTE_TIME
end

local function getWorldDirection(): Vector3
	if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
		local moveDirection = humanoid.MoveDirection
		return Vector3.new(moveDirection.X, 0, moveDirection.Z)
	end

	if root then
		local look = root.CFrame.LookVector
		return Vector3.new(look.X, 0, look.Z)
	end

	return Vector3.new(0, 0, -1)
end

local function getJumpVelocity(height: number): number
	return math.sqrt(math.max(0, 2 * workspace.Gravity * height))
end

local function tryFindPlatformerFolder(): Folder?
	local platformer = ReplicatedStorage:FindFirstChild("Platformer")
	if platformer and platformer:IsA("Folder") then
		return platformer
	end
	return nil
end

local function playSound(soundName: string?)
	if not soundName or not root then
		return
	end

	local platformer = tryFindPlatformerFolder()
	local sounds = platformer and platformer:FindFirstChild("Sounds")
	if not sounds then
		return
	end

	local template = sounds:FindFirstChild(soundName, true)
	if not template or not template:IsA("Sound") then
		return
	end

	local sound = template:Clone()
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.25))
end

local function emitEffect(effectName: string?, burstCount: number?)
	if not effectName or not root then
		return
	end

	local platformer = tryFindPlatformerFolder()
	local effects = platformer and platformer:FindFirstChild("Effects")
	if not effects then
		return
	end

	local template = effects:FindFirstChild(effectName, true)
	if not template then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = effectName .. "TempAttachment"
	attachment.Parent = root
	Debris:AddItem(attachment, 2)

	local clone = template:Clone()
	clone.Parent = attachment

	local emitters = {}
	if clone:IsA("ParticleEmitter") then
		table.insert(emitters, clone)
	else
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				table.insert(emitters, desc)
			end
		end
	end

	local count = burstCount or 8
	for _, emitter in ipairs(emitters) do
		if emitter.Parent ~= attachment then
			emitter.Parent = attachment
		end
		pcall(function()
			emitter:Emit(count)
		end)
	end

	task.delay(0.5, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)
end

local function playAnimation(animName: string?)
	if not animName or not humanoid then
		return
	end

	AnimationManager.play(humanoid, animName, 0.08, nil, 1.0)
end

local function clearDash()
	if dashVelocity then
		dashVelocity:Destroy()
		dashVelocity = nil
	end

	if rootAttachment then
		rootAttachment:Destroy()
		rootAttachment = nil
	end
end

local function applyVerticalJump(height: number)
	if not root then
		return
	end

	local currentVelocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, getJumpVelocity(height), currentVelocity.Z)
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

local function setMovementFlags(canDash: boolean?, canDoubleJump: boolean?, canSuperJump: boolean?, isStunned: boolean?)
	if currentCharacter then
		if canDash ~= nil then
			currentCharacter:SetAttribute("MovementCanDash", canDash)
		end
		if canDoubleJump ~= nil then
			currentCharacter:SetAttribute("MovementCanDoubleJump", canDoubleJump)
		end
		if canSuperJump ~= nil then
			currentCharacter:SetAttribute("MovementCanSuperJump", canSuperJump)
		end
		if isStunned ~= nil then
			currentCharacter:SetAttribute("MovementIsStunned", isStunned)
		end
	end
end

local function refreshGroundState()
	if not currentCharacter or not humanoid then
		return
	end

	if isGrounded() then
		lastGroundedTime = os.clock()
		if os.clock() >= dashAvailableAt then
			dashReady = true
		end
		doubleJumpReady = true
		superJumpReady = true
		setMovementFlags(dashReady, true, true, isStunned())
	else
		setMovementFlags(nil, nil, nil, isStunned())
	end
end

function MovementAbilityController.requestJump()
	if not humanoid or not root or isStunned() then
		return
	end

	if isGrounded() or isCoyoteJumpAllowed() then
		applyVerticalJump(Balance.MOVEMENT_JUMP_HEIGHT)
		playSound("Jump")
		emitEffect("JumpParticles", 8)
		return
	end

	if doubleJumpReady then
		doubleJumpReady = false
		setMovementFlags(nil, false, nil, nil)
		applyVerticalJump(Balance.MOVEMENT_DOUBLE_JUMP_HEIGHT)
		playAnimation("DoubleJump")
		playSound("DoubleJump")
		emitEffect("JumpParticles", 8)
	end
end

function MovementAbilityController.requestDoubleJump()
	if not humanoid or not root or isStunned() or isGrounded() or isCoyoteJumpAllowed() then
		return
	end

	if not doubleJumpReady then
		return
	end

	doubleJumpReady = false
	setMovementFlags(nil, false, nil, nil)
	applyVerticalJump(Balance.MOVEMENT_DOUBLE_JUMP_HEIGHT)
	playAnimation("DoubleJump")
	playSound("DoubleJump")
	emitEffect("JumpParticles", 8)
end

function MovementAbilityController.requestSuperJump()
	-- 슈퍼점프 삭제 처리 (아무 동작 없음)
	return
end

local MovementController = require(script.Parent:WaitForChild("MovementController"))

function MovementAbilityController.requestDash()
	if not humanoid or not root or isStunned() then
		return
	end

	if not dashReady then
		return
	end

	-- Check stamina availability on client first
	local currentStamina, maxStamina = MovementController.getStamina()
	if currentStamina < Balance.MOVEMENT_DASH_STAMINA_COST then
		return
	end

	-- Request stamina consumption from the server
	local success, result = NetClient.Request("Movement.ConsumeStamina", { amount = Balance.MOVEMENT_DASH_STAMINA_COST })
	if not success or (result and not result.success) then
		return
	end

	dashReady = false
	dashAvailableAt = os.clock() + Balance.MOVEMENT_DASH_COOLDOWN
	dashEndsAt = os.clock() + Balance.MOVEMENT_DASH_DURATION
	setMovementFlags(false, nil, nil, nil)

	clearDash()

	rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "MovementDashAttachment"
	rootAttachment.Parent = root

	dashVelocity = Instance.new("LinearVelocity")
	dashVelocity.Name = "MovementDashVelocity"
	dashVelocity.Attachment0 = rootAttachment
	dashVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	dashVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	
	local dashSpeed = Balance.MOVEMENT_DASH_SPEED
	if SkillController.hasPassiveRuneEquipped("SKILL_RUNE_DASH") then
		dashSpeed = dashSpeed * 1.5
	end
	
	dashVelocity.MaxForce = dashSpeed * root.AssemblyMass * 40
	local direction = getWorldDirection()
	if direction.Magnitude < 0.01 then
		direction = root.CFrame.LookVector
	end
	dashVelocity.VectorVelocity = Vector3.new(direction.X, 0, direction.Z).Unit * dashSpeed
	dashVelocity.Parent = root

	playAnimation("Dash")
	playSound("Dash")
	emitEffect("DashParticles", 10)
end

function MovementAbilityController.applyHitReaction(bounceDirection: Vector3?)
	if not humanoid or not root then
		return
	end

	local direction = bounceDirection or -root.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(-root.CFrame.LookVector.X, 0, -root.CFrame.LookVector.Z)
	end
	direction = direction.Unit

	stunnedUntil = os.clock() + Balance.MOVEMENT_HIT_STUN_TIME
	clearDash()
	setMovementFlags(false, false, false, true)
	AnimationManager.stop(humanoid, "Stun", 0.05)

	local existing = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = direction * Balance.MOVEMENT_HIT_REACTION_FORCE + Vector3.new(0, Balance.MOVEMENT_HIT_REACTION_UPWARD, 0)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	-- 히트 시 애니메이션은 재생하지 않고 물리 넉백과 이펙트만 남긴다.
	emitEffect("WallImpactParticles", 8)

	task.delay(Balance.MOVEMENT_HIT_REACTION_DURATION, function()
		if root and root.Parent then
			local current = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(current.X, math.max(current.Y, existing.Y), current.Z)
		end
	end)
end

local function bindInputs()
	-- [버그수정] UserInputService.JumpRequest는 키보드/게임패드/모바일 점프 버튼 전부에서 발동되는데,
	-- onCharacterAdded()의 humanoid:GetPropertyChangedSignal("Jump") 리스너도 동일한 입력(로블록스
	-- 기본 컨트롤이 Humanoid.Jump=true로 바꿀 때)에서 발동한다. 점프 1번에 requestJump()가 2번 호출되어
	-- 두 번째 호출이 즉시 더블 점프 자원을 소모해버리는 버그가 있었음 — 여기서는 중복 등록하지 않는다.
	InputManager.bindAction("MovementDashAction", function()
		MovementAbilityController.requestDash()
	end, false, nil, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
end

local function onCharacterAdded(character: Model)
	currentCharacter = character
	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	lastGroundedTime = os.clock()
	dashReady = true
	doubleJumpReady = true
	superJumpReady = true
	stunnedUntil = 0
	dashEndsAt = 0
	dashAvailableAt = 0
	clearDash()
	setMovementFlags(true, true, true, false)

	-- Intercept default mobile jump request to trigger code-driven custom jump and double jump
	table.insert(connections, humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid and humanoid.Jump then
			humanoid.Jump = false -- Consume default physics jump
			MovementAbilityController.requestJump()
		end
	end))

	table.insert(connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			clearDash()
			disconnectAll()
			currentCharacter = nil
			humanoid = nil
			root = nil
			setMovementFlags(nil, nil, nil, false)
		end
	end))
end

local function onHeartbeat()
	if not currentCharacter or not humanoid or not root then
		return
	end

	refreshGroundState()

	if dashVelocity and os.clock() >= dashEndsAt then
		clearDash()
	end
end

function MovementAbilityController.Init()
	if initialized then
		return
	end

	PlatformerInput.setController(MovementAbilityController)
	bindInputs()
	NetClient.On("Player.Stun", function(bounceDirection)
		MovementAbilityController.applyHitReaction(bounceDirection)
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	RunService.Heartbeat:Connect(onHeartbeat)

	if player.Character then
		onCharacterAdded(player.Character)
	end

	initialized = true
	print("[MovementAbilityController] Initialized")
end

function MovementAbilityController.setCurrentCharacter(character: Model?)
	if currentCharacter == character then
		return
	end

	if character then
		onCharacterAdded(character)
	end
end

return MovementAbilityController
