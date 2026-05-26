-- SkyIslandTransportService.lua
-- 하늘섬 이동 및 귀환 NPC 상호작용 서버 서비스
-- Workspace 내의 "SkyIslandGuide"(지상 출발 NPC)와 "GroundGuide"(하늘섬 복귀 NPC)를 감지하고 텔레포트 처리

local SkyIslandTransportService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local SaveService = require(ServerScriptService.Server.Services.SaveService)
local SpawnConfig = require(ReplicatedStorage.Shared.Config.SpawnConfig)

local NetController = nil
local initialized = false

-- 대기열/중복 방지 쿨다운
local debounces = {}

-- NPC 찾기 및 프롬프트 생성 헬퍼
local function setupNPC(npc, objectText, actionText, isReturn)
	local promptName = isReturn and "GroundGuidePrompt" or "SkyIslandGuidePrompt"
	if npc:FindFirstChild(promptName, true) then return end
	
	local targetPart = npc:IsA("BasePart") and npc 
		or npc:FindFirstChild("HumanoidRootPart") 
		or npc.PrimaryPart 
		or npc:FindFirstChildWhichIsA("BasePart", true)
		
	if not targetPart then return end
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	
	prompt.Parent = targetPart
	print(string.format("[SkyIslandTransportService] NPC 프롬프트 등록 완료: %s (isReturn: %s)", npc.Name, tostring(isReturn)))
	
	prompt.Triggered:Connect(function(player)
		if NetController then
			NetController.FireClient(player, "SkyIsland.OpenUI", {
				isReturn = isReturn
			})
		end
	end)
end

-- NPC 스캔 및 실시간 감지
local function scanNPCs()
	for _, child in ipairs(Workspace:GetDescendants()) do
		if (child:IsA("Model") or child:IsA("BasePart")) then
			if child.Name == "SkyIslandGuide" then
				setupNPC(child, "하늘섬 인도자", "하늘섬으로 이동", false)
			elseif child.Name == "GroundGuide" then
				setupNPC(child, "지상 인도자", "지상으로 귀환", true)
			end
		end
	end
end

-- 텔레포트 도착 지점 계산 (NPC 모델이 있으면 NPC 근처, 없으면 구역 기본 좌표)
local function getTeleportPosition(isReturn: boolean)
	local targetNpcName = isReturn and "SkyIslandGuide" or "GroundGuide"
	local zoneName = isReturn and "CHEONGUN" or "SKY_ISLAND"
	
	local targetNpc = nil
	for _, child in ipairs(Workspace:GetDescendants()) do
		if child.Name == targetNpcName and (child:IsA("Model") or child:IsA("BasePart")) then
			targetNpc = child
			break
		end
	end
	
	if targetNpc then
		local npcPart = targetNpc:IsA("BasePart") and targetNpc 
			or targetNpc:FindFirstChild("HumanoidRootPart") 
			or targetNpc.PrimaryPart
			
		if npcPart then
			-- NPC 바로 앞에서 스폰 (LookVector 방향으로 5 스터드 앞, Y높이 보정)
			return npcPart.Position + npcPart.CFrame.LookVector * 5 + Vector3.new(0, 3, 0)
		end
	end
	
	-- NPC를 찾지 못했을 때의 구역 기본 폴백 좌표
	local zoneInfo = SpawnConfig.GetZoneInfo(zoneName)
	return zoneInfo and zoneInfo.spawnPoint or Vector3.new(0, 100, 0)
end

-- 실제 텔레포트 처리
local function handleTeleportRequest(player: Player, payload: any)
	local userId = player.UserId
	if debounces[userId] and (tick() - debounces[userId]) < 3 then
		return { success = false, errorCode = "COOLDOWN" }
	end
	debounces[userId] = tick()
	
	local isReturn = payload and payload.isReturn == true
	local targetPos = getTeleportPosition(isReturn)
	local destName = isReturn and "지상(청운촌)" or "하늘섬"
	
	-- 1. 화면 페이드 연출 전파 (포탈의 훌륭한 로딩 트랜지션 연출 재사용)
	if NetController then
		NetController.FireClient(player, "Portal.Teleporting", {
			destination = destName
		})
	end
	
	-- 2. 비동기식 순간이동 태스크 디퍼
	task.defer(function()
		task.wait(1.5) -- 페이드 아웃 완료 대기
		
		-- 안전하게 데이터 세이브
		if SaveService and SaveService.savePlayer then
			SaveService.savePlayer(userId)
		end
		
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not hrp then
			if NetController then
				NetController.FireClient(player, "Portal.Error", { message = "캐릭터를 찾을 수 없습니다" })
			end
			return
		end
		
		-- 플레이어 스폰 정보 갱신 (사망 시 복귀 좌표용)
		player:SetAttribute("SpawnPosX", targetPos.X)
		player:SetAttribute("SpawnPosY", targetPos.Y)
		player:SetAttribute("SpawnPosZ", targetPos.Z)
		
		-- ★ [대폭 개선] 캐릭터를 새로 생성(LoadCharacter)하지 않고 CFrame을 직접 피벗하여
		-- 에셋 로딩 딜레이 및 로블록스 특유의 각진 몸통(Blocky Body) 버그를 완벽히 해결합니다.
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if character and hrp then
			hrp.Anchored = true
			character:PivotTo(CFrame.new(targetPos))
			
			-- 스트리밍 로드
			pcall(function()
				player:RequestStreamAroundAsync(targetPos, 5)
			end)
			
			task.wait(0.5) -- 스트리밍 대기 및 물리 안정화
			hrp.Anchored = false
		else
			-- 캐릭터가 소실된 예외적인 경우에만 폴백으로 LoadCharacter 작동
			player:LoadCharacter()
			pcall(function()
				local loaded = false
				local connection
				connection = player.CharacterAppearanceLoaded:Connect(function()
					loaded = true
					if connection then connection:Disconnect() end
				end)
				
				local startTime = tick()
				while not loaded and (tick() - startTime) < 2.5 and player.Parent do
					task.wait(0.1)
				end
				if connection then connection:Disconnect() end
			end)
			task.wait(1.0)
		end
		
		-- 잠시 후 무적 상태 임시 부여
		task.spawn(function()
			local charStart = tick()
			while player.Parent and (tick() - charStart) < 10 do
				local newCharacter = player.Character
				if newCharacter and newCharacter:FindFirstChild("HumanoidRootPart") then
					local ff = Instance.new("ForceField")
					ff.Visible = false
					ff.Parent = newCharacter
					task.delay(5, function()
						if ff and ff.Parent then ff:Destroy() end
					end)
					break
				end
				task.wait(0.05)
			end
		end)
		
		-- 3. 페이드 인 및 트랜지션 완료 처리
		if NetController then
			NetController.FireClient(player, "Portal.Arrived", {
				zone = isReturn and "CHEONGUN" or "SKY_ISLAND"
			})
		end
		
		print(string.format("[SkyIslandTransportService] %s가 %s(으)로 텔레포트 완료 (좌표: %.1f, %.1f, %.1f)", 
			player.Name, destName, targetPos.X, targetPos.Y, targetPos.Z))
	end)
	
	return { success = true }
end

-- 초기화
function SkyIslandTransportService.Init(netController)
	if initialized then return end
	initialized = true
	
	NetController = netController
	
	-- 기존 배치된 NPC 스캔
	scanNPCs()
	
	-- 실시간 추가되는 NPC 추적 (스트리밍 및 동적 생성 대비)
	Workspace.DescendantAdded:Connect(function(child)
		if child:IsA("Model") or child:IsA("BasePart") then
			task.defer(function()
				if child.Name == "SkyIslandGuide" then
					setupNPC(child, "하늘섬 인도자", "하늘섬으로 이동", false)
				elseif child.Name == "GroundGuide" then
					setupNPC(child, "지상 인도자", "지상으로 귀환", true)
				end
			end)
		end
	end)
	
	-- 퇴장 시 쿨다운 해제
	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId] = nil
	end)
end

-- 핸들러 등록
function SkyIslandTransportService.GetHandlers()
	return {
		["SkyIsland.Teleport.Request"] = handleTeleportRequest
	}
end

return SkyIslandTransportService
