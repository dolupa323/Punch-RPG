local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpiritController = {}
local initialized = false
local currentSpirit = nil
local renderConnection = nil

local function cleanSpirit()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if currentSpirit then
		currentSpirit:Destroy()
		currentSpirit = nil
	end
end

local function setupSpirit(character)
	cleanSpirit()
	
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end
	
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local monsters = assets:WaitForChild("Monsters")

	local function spawnDemon(demonTemplate)
		local spirit = demonTemplate:Clone()
		spirit.Name = "FollowerDemon"
		
		-- 물리 충돌 및 그림자 차단
		for _, part in ipairs(spirit:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = true
				part.CastShadow = false
			end
		end
		
		-- PrimaryPart 설정 안전망
		local root = spirit.PrimaryPart or spirit:FindFirstChild("HumanoidRootPart") or spirit:FindFirstChildWhichIsA("BasePart")
		if not root then
			warn("[SpiritController] Demon model has no BasePart to anchor/move!")
			spirit:Destroy()
			return
		end
		spirit.PrimaryPart = root
		
		-- [에미터 A: 이글거리는 보랏빛 마기 연무 (양과 크기를 적절히 조절)]
		local flowingAura = Instance.new("ParticleEmitter")
		flowingAura.Name = "FlowingAura"
		flowingAura.Texture = "rbxasset://textures/particles/fire_main.dds"
		flowingAura.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 4, 12)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(65, 12, 105)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 5, 50))
		})
		flowingAura.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.5, 1.5), -- 2.2 -> 1.5로 다소 축소하여 시야 확보
			NumberSequenceKeypoint.new(1, 0.6)
		})
		flowingAura.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.6, 0.42),
			NumberSequenceKeypoint.new(1, 1)
		})
		flowingAura.Lifetime = NumberRange.new(0.7, 1.1)
		flowingAura.Rate = 60 -- 연기 방출량 180 -> 60으로 하향 조정하여 너무 덮이지 않게 조절
		flowingAura.Speed = NumberRange.new(0.3, 0.6)
		flowingAura.SpreadAngle = Vector2.new(15, 15)
		flowingAura.Orientation = Enum.ParticleOrientation.VelocityParallel
		flowingAura.Acceleration = Vector3.new(0, 3.8, 0)
		flowingAura.RotSpeed = NumberRange.new(-50, 50)
		flowingAura.LockedToPart = true
		flowingAura.LightEmission = 0.35
		flowingAura.LightInfluence = 0
		flowingAura.Enabled = true
		flowingAura.Parent = root

		-- [에미터 B: 이동할 때 뒤로 흩날리는 어두운 꼬리 연기 (조절)]
		local flowingTrail = Instance.new("ParticleEmitter")
		flowingTrail.Name = "FlowingTrail"
		flowingTrail.Texture = "rbxasset://textures/particles/smoke_main.dds"
		flowingTrail.Color = ColorSequence.new(Color3.fromRGB(20, 10, 30))
		flowingTrail.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.6, 1.4), -- 2.0 -> 1.4로 축소
			NumberSequenceKeypoint.new(1, 0)
		})
		flowingTrail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.8, 0.7),
			NumberSequenceKeypoint.new(1, 1)
		})
		flowingTrail.Lifetime = NumberRange.new(0.8, 1.3)
		flowingTrail.Rate = 35 -- 90 -> 35로 하향
		flowingTrail.Speed = NumberRange.new(0.15, 0.4)
		flowingTrail.SpreadAngle = Vector2.new(15, 15)
		flowingTrail.Acceleration = Vector3.new(0, 1.8, 0)
		flowingTrail.LockedToPart = false
		flowingTrail.Enabled = true
		flowingTrail.Parent = root
		
		-- 마법 스파클
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "MagicSparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(Color3.fromRGB(170, 70, 255))
		sparkles.Size = NumberSequence.new(0.1, 0)
		sparkles.Transparency = NumberSequence.new(0.2, 1)
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.Rate = 6
		sparkles.Speed = NumberRange.new(0.2, 0.5)
		sparkles.Acceleration = Vector3.new(0, 1.2, 0)
		sparkles.Enabled = true
		sparkles.Parent = root
		
		-- 오직 나에게만 보이는 개인 화면 전용 지정 (Camera 하위)
		local camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")
		spirit.Parent = camera
		currentSpirit = spirit
		
		root.CFrame = hrp.CFrame * CFrame.new(-6, 3, 6)
		
		-- [자율적 넓은 반경 배회 및 유저 최소 거리(안전 스페이스) 확보 AI]
		local state = "ROAMING" -- "ROAMING" or "RETURNING"
		local roamTargetPos = hrp.Position + Vector3.new(-6, 3, 6)
		local nextRoamTime = 0
		local roamInterval = 4.0
		
		local accumTime = 0
		renderConnection = RunService.RenderStepped:Connect(function(dt)
			if not hrp.Parent or not character:FindFirstChild("Humanoid") or character.Humanoid.Health <= 0 then
				cleanSpirit()
				return
			end
			
			accumTime += dt
			
			local currentPos = root.Position
			local playerPos = hrp.Position
			local distToPlayer = (playerPos - currentPos).Magnitude
			
			local targetPos
			local lerpSpeed = 0.035 -- 넓은 범위 자율 비행을 위한 부드러운 속도
			
			-- 상태 제어 전이 판정
			if distToPlayer > 26 then -- 유저가 멀리 달아나서 26스터드 이상 차이 나면 빠르게 복귀 개시
				state = "RETURNING"
			elseif state == "RETURNING" and distToPlayer < 9 then -- 9스터드 이내로 도달 시 유저 안전거리 확보 후 배회 전환
				state = "ROAMING"
				nextRoamTime = 0 -- 즉시 다음 자율 배회 목적지 선정
			end
			
			if state == "RETURNING" then
				-- 복귀 목적지도 플레이어의 바로 머리가 아닌, 7.5스터드 뒤쪽 안전 오프셋으로 설정하여 근접 비빔을 방지
				local followOffset = Vector3.new(-6, 3.2, 6)
				targetPos = (hrp.CFrame * CFrame.new(followOffset)).Position
				lerpSpeed = 0.10 -- 신속하지만 급격히 들이받지 않게 복귀 속도 조율
			else
				-- 자율 배회 모드 (ROAMING)
				if accumTime >= nextRoamTime then
					nextRoamTime = accumTime + roamInterval + math.random() * 2.0
					
					-- [핵심 로직: 유저와의 최소 거리를 7.5스터드로 강제하여 퍼스널 스페이스 확보]
					-- XZ 도넛 모양(Ring) 범위 설정: 최소 7.5스터드 ~ 최대 22스터드 이내에서 넓게 자율 탐색
					local randomAngle = math.random() * math.pi * 2
					local randomDist = math.random(8, 23) -- 더 먼 거리(8 ~ 23)를 시원시원하게 돌아다님
					local rx = math.cos(randomAngle) * randomDist
					local rz = math.sin(randomAngle) * randomDist
					local ry = math.random(1.8, 4.5) -- 유저 머리 위나 옆 높이 유지
					
					roamTargetPos = playerPos + Vector3.new(rx, ry, rz)
				end
				targetPos = roamTargetPos
			end
			
			-- 위치 보간 이동
			local newPos = currentPos:Lerp(targetPos, lerpSpeed)
			
			-- 자율 배회 중일 때 둥실둥실(Bobbing) 움직임 적용
			if state == "ROAMING" then
				newPos = newPos + Vector3.new(0, math.sin(accumTime * 2.2) * 0.015, 0)
			end
			
			-- 진행 방향 각도로 몸체 회전
			local moveDir = (newPos - currentPos)
			local lookAtPos
			if moveDir.Magnitude > 0.02 then
				lookAtPos = newPos + moveDir.Unit * 10
			else
				lookAtPos = newPos + (playerPos - newPos).Unit * 10
			end
			
			spirit:SetPrimaryPartCFrame(CFrame.new(newPos, lookAtPos))
		end)
	end
	
	local demon = monsters:FindFirstChild("Demon")
	if demon then
		spawnDemon(demon)
	else
		warn("[SpiritController] 'Demon' model not found in Assets/Monsters yet. Waiting for insertion...")
		
		local connection
		connection = monsters.ChildAdded:Connect(function(child)
			if child.Name == "Demon" then
				connection:Disconnect()
				spawnDemon(child)
			end
		end)
		
		task.delay(60, function()
			if connection.Connected then
				connection:Disconnect()
				warn("[SpiritController] Timeout waiting for 'Demon' model to be added.")
			end
		end)
	end
end

function SpiritController.Init()
	if initialized then return end
	initialized = true
	print("[SpiritController] SpiritController disabled (Demon spawning removed)")
end

return SpiritController
