-- BotService.lua
-- Survivor Bot (가짜 유저) 관리 서비스 (Phase 7 - 표준 애니메이션 폴백 적용)
-- 월드에 플레이어와 유사한 봇을 스폰하고 "보여주기용" 채집, 전투, 휴식 연출 제공

local BotService = {}

--========================================
-- Dependencies
--========================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local BotConfig = require(Shared.Config.BotConfig)
local Appearance = require(Shared.Config.Appearance)
local SpawnConfig = require(Shared.Config.SpawnConfig)
local AnimationIds = require(Shared.Config.AnimationIds)

--========================================
-- Internal State
--========================================
local activeBots = {}
local botCount = 0
local initialized = false

-- AI Constants
local UPDATE_INTERVAL = 1.0
local WANDER_RADIUS = 50
local SPAWN_HEIGHT_OFFSET = 10
local HARVEST_LOOKUP_RADIUS = 50
local COMBAT_LOOKUP_RADIUS = 80
local INTERACT_DIST = 5.5
local ATTACK_DIST = 9.0

-- Roblox Standard Animation IDs (폴백용)
local DEFAULT_ANIMS = {
	IDLE = "rbxassetid://507766388",
	WALK = "rbxassetid://507777826",
	RUN = "rbxassetid://507767714"
}

--========================================
-- Internal Functions
--========================================

--- 봇 외형 적용
local function applyBotAppearance(model, botName)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	for _, item in ipairs(model:GetChildren()) do
		if item:IsA("Accessory") or item:IsA("ShirtGraphic") or item:IsA("CharacterMesh") then
			item:Destroy()
		end
	end

	local rng = Random.new(tick() + botCount)
	local skinTone = Appearance.SKIN_TONES[rng:NextInteger(1, #Appearance.SKIN_TONES)]
	local clothingColor = Appearance.CLOTHING_COLORS[rng:NextInteger(1, #Appearance.CLOTHING_COLORS)]
	
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = skinTone
		end
	end
	
	local skinParts = {"Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"}
	local clothingParts = {"UpperTorso", "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
	
	for _, name in ipairs(skinParts) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then part.Color = skinTone end
	end
	for _, name in ipairs(clothingParts) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then part.Color = clothingColor end
	end
	
	local shirt = model:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", model)
	shirt.ShirtTemplate = Appearance.CLOTHING_IDS.DEFAULT_SHIRT
	
	local pants = model:FindFirstChildOfClass("Pants") or Instance.new("Pants", model)
	pants.PantsTemplate = Appearance.CLOTHING_IDS.DEFAULT_PANTS
end

--- 연출용 타겟 노드 찾기
local function findNearbyDecorationTarget(position, radius)
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then return nil end
	
	local nodes = {}
	for _, node in ipairs(nodeFolder:GetChildren()) do
		if node:IsA("Model") and not node:GetAttribute("Depleted") then
			local dist = (node:GetPivot().Position - position).Magnitude
			if dist < radius then
				table.insert(nodes, node)
			end
		end
	end
	
	if #nodes > 0 then
		return nodes[math.random(1, #nodes)]
	end
	return nil
end

--- 연출용 전투 대상 찾기
local function findNearbyCreature(position, radius)
	local creatureFolder = workspace:FindFirstChild("ActiveCreatures")
	if not creatureFolder then return nil end
	
	local best = nil
	local minDist = radius
	
	for _, creature in ipairs(creatureFolder:GetChildren()) do
		if creature:IsA("Model") and not creature:GetAttribute("IsDead") then
			local dist = (creature:GetPivot().Position - position).Magnitude
			if dist < minDist then
				minDist = dist
				best = creature
			end
		end
	end
	
	return best
end

local function playBotAnim(bot, animNameOrId, isLoop)
	if bot.currentAnimName == animNameOrId and bot.currentAnim and bot.currentAnim.IsPlaying then
		return bot.currentAnim
	end

	if bot.currentAnim then bot.currentAnim:Stop(0.2) end
	
	local animator = bot.humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animObj = nil
		
		-- 1. rbxassetid 직접 입력 처리
		if animNameOrId:match("^rbxassetid://") then
			animObj = Instance.new("Animation")
			animObj.AnimationId = animNameOrId
		else
			-- 2. Assets/Animations 폴더 검색
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			local anims = assets and assets:FindFirstChild("Animations")
			animObj = anims and anims:FindFirstChild(animNameOrId)
		end
		
		if animObj and animObj:IsA("Animation") then
			local track = animator:LoadAnimation(animObj)
			track.Looped = isLoop or false
			track:Play(0.2)
			bot.currentAnim = track
			bot.currentAnimName = animNameOrId
			return track
		end
	end
	return nil
end

--- 기본 이동 애니메이션 처리
local function setupBotAnimationHandler(bot)
	bot.humanoid.Running:Connect(function(speed)
		if bot.state == "ACTING_GATHER" or bot.state == "ATTACKING_CREATURE" or bot.state == "RESTING" then
			return
		end
		
		if speed > 0.5 then
			if speed > 15 then
				playBotAnim(bot, DEFAULT_ANIMS.RUN, true)
			else
				playBotAnim(bot, DEFAULT_ANIMS.WALK, true)
			end
		else
			playBotAnim(bot, DEFAULT_ANIMS.IDLE, true)
		end
	end)
end

function BotService.spawnBot(position: Vector3)
	if botCount >= BotConfig.MAX_BOTS then return end
	
	local model = Players:CreateHumanoidModelFromUserId(1)
	local botName = BotConfig.BOT_NAMES[math.random(1, #BotConfig.BOT_NAMES)]
	local instanceId = "BOT_" .. HttpService:GenerateGUID(false)
	
	model.Name = botName
	model:SetAttribute("InstanceId", instanceId)
	model:SetAttribute("IsBot", true)
	
	model:PivotTo(CFrame.new(position + Vector3.new(0, SPAWN_HEIGHT_OFFSET, 0)))
	
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if hrp then
		hrp.CollisionGroup = "Players"
		pcall(function() hrp:SetNetworkOwner(nil) end)
	end
	
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid.WalkSpeed = 10 + math.random() * 4
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	
	applyBotAppearance(model, botName)
	
	model.Parent = workspace:FindFirstChild("SurvivorBots") or (function()
		local f = Instance.new("Folder", workspace)
		f.Name = "SurvivorBots"
		return f
	end)()
	
	local botData = {
		id = instanceId,
		model = model,
		humanoid = humanoid,
		rootPart = hrp,
		state = "IDLE",
		nextActionTime = tick() + math.random(1, 4),
		targetNode = nil,
		targetCreature = nil,
		actionEndTime = 0,
		currentAnim = nil,
		currentAnimName = "",
	}
	
	setupBotAnimationHandler(botData)
	activeBots[instanceId] = botData
	botCount += 1
	
	return instanceId
end

function BotService.notifyHit(instanceId, attackerModel)
	local bot = activeBots[instanceId]
	if not bot or not attackerModel then return end
	
	if bot.state ~= "ATTACKING_CREATURE" and bot.state ~= "CHASE_CREATURE" then
		bot.targetCreature = attackerModel
		bot.state = "CHASE_CREATURE"
		bot.humanoid.WalkSpeed = 18
		bot.nextActionTime = tick() + 10
	end
end

local function _updateBotsLoop()
	local now = tick()
	for id, bot in pairs(activeBots) do
		if not bot.model or not bot.model.Parent then
			activeBots[id] = nil
			botCount -= 1
			continue
		end
		
		local hrpPos = bot.rootPart.Position
		
		if bot.state == "IDLE" then
			if now >= bot.nextActionTime then
				if math.random() < 0.4 then
					local creature = findNearbyCreature(hrpPos, COMBAT_LOOKUP_RADIUS)
					if creature then
						bot.targetCreature = creature
						bot.state = "CHASE_CREATURE"
						bot.humanoid.WalkSpeed = 18
						continue
					end
				end
				
				if math.random() < 0.1 then
					bot.state = "RESTING"
					bot.actionEndTime = now + math.random(15, 30)
					playBotAnim(bot, AnimationIds.MISC.REST, true)
					continue
				end

				if math.random() < 0.4 then
					local node = findNearbyDecorationTarget(hrpPos, HARVEST_LOOKUP_RADIUS)
					if node then
						bot.targetNode = node
						bot.state = "MOVING_TO_ACT"
						bot.humanoid:MoveTo(node:GetPivot().Position)
						bot.humanoid.WalkSpeed = 12
						continue
					end
				end
				
				local angle = math.rad(math.random(0, 360))
				local dist = math.random(20, WANDER_RADIUS)
				local target = hrpPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
				bot.humanoid:MoveTo(target)
				bot.state = "WANDERING"
				bot.humanoid.WalkSpeed = 10
				bot.nextActionTime = now + 8
			end
			
		elseif bot.state == "RESTING" then
			if now >= bot.actionEndTime then
				bot.state = "IDLE"
				bot.nextActionTime = now + math.random(3, 8)
			end

		elseif bot.state == "CHASE_CREATURE" then
			if not bot.targetCreature or not bot.targetCreature.Parent or bot.targetCreature:GetAttribute("IsDead") then
				bot.state = "IDLE"
				bot.targetCreature = nil
				bot.nextActionTime = now + 1
				continue
			end
			
			local cPos = bot.targetCreature:GetPivot().Position
			local dist = (cPos - hrpPos).Magnitude
			
			if dist <= ATTACK_DIST then
				bot.humanoid:MoveTo(hrpPos)
				bot.state = "ATTACKING_CREATURE"
				bot.actionEndTime = now + math.random(8, 15)
				bot.lastAttackTime = 0
			else
				bot.humanoid:MoveTo(cPos)
			end
			
		elseif bot.state == "ATTACKING_CREATURE" then
			if not bot.targetCreature or not bot.targetCreature.Parent or bot.targetCreature:GetAttribute("IsDead") or now >= bot.actionEndTime then
				bot.state = "IDLE"
				bot.targetCreature = nil
				bot.nextActionTime = now + math.random(3, 6)
				continue
			end
			
			if now - (bot.lastAttackTime or 0) > 1.2 then
				bot.lastAttackTime = now
				playBotAnim(bot, AnimationIds.ATTACK_TOOL.SWING)
				local dir = (bot.targetCreature:GetPivot().Position - hrpPos) * Vector3.new(1, 0, 1)
				if dir.Magnitude > 0.1 then
					bot.rootPart.CFrame = CFrame.lookAt(hrpPos, hrpPos + dir.Unit)
				end
			end

		elseif bot.state == "MOVING_TO_ACT" then
			if not bot.targetNode or not bot.targetNode.Parent or bot.targetNode:GetAttribute("Depleted") then
				bot.state = "IDLE"
				bot.targetNode = nil
				bot.nextActionTime = now + 1
				continue
			end
			
			local dist = (bot.targetNode:GetPivot().Position - hrpPos).Magnitude
			if dist <= INTERACT_DIST then
				bot.humanoid:MoveTo(hrpPos)
				bot.state = "ACTING_GATHER"
				bot.actionEndTime = now + math.random(5, 12)
				playBotAnim(bot, AnimationIds.HARVEST.GATHER, true)
			end
			
		elseif bot.state == "ACTING_GATHER" then
			if now >= bot.actionEndTime or not bot.targetNode or not bot.targetNode.Parent or bot.targetNode:GetAttribute("Depleted") then
				bot.state = "IDLE"
				bot.targetNode = nil
				bot.nextActionTime = now + math.random(3, 7)
			end
			
		elseif bot.state == "WANDERING" then
			if now >= bot.nextActionTime then
				bot.state = "IDLE"
				bot.nextActionTime = now + math.random(2, 5)
			end
		end
	end
end

--========================================
-- Public API
--========================================

function BotService.Init()
	if initialized then return end
	
	task.spawn(function()
		task.wait(5)
		local hubZone = SpawnConfig.GetZoneInfo("HUB")
		local center = (hubZone and hubZone.center) or Vector3.new(0, 20, 0)
		
		for i = 1, BotConfig.MAX_BOTS do
			local angle = math.rad((360 / BotConfig.MAX_BOTS) * i)
			local dist = math.random(30, 150)
			local spawnPos = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
			
			local ray = workspace:Raycast(spawnPos + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0))
			if ray then spawnPos = ray.Position end
			
			BotService.spawnBot(spawnPos)
			task.wait(0.3)
		end
	end)
	
	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			_updateBotsLoop()
		end
	end)
	
	initialized = true
	print("[BotService] Initialized Phase 7 - Standard Animation Fallback Active")
end

return BotService
