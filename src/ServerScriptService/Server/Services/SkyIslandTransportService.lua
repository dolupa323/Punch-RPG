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
local PlayerStatService = nil
local initialized = false

local HEAVEN_RUNE_ID = "SKILL_RUNE_HEAVEN"
local REQUIRED_LEVEL = 40

local function playerHasHeavenRune(player: Player): boolean
	local state = SaveService.getPlayerState(player.UserId)
	if not state or not state.equippedPassives then return false end
	for _, skillId in pairs(state.equippedPassives) do
		if skillId == HEAVEN_RUNE_ID then return true end
	end
	return false
end

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
		if not NetController then return end

		if isReturn then
			-- 귀환 NPC는 조건 없이 대화 시작
			NetController.FireClient(player, "SkyIsland.OpenDialogue", {
				isReturn = true,
				canTravel = true,
				npcName = "지상 인도자",
				dialogue = "지상으로 돌아가시겠습니까?\n아르하임 입구 앞에 내려드리겠습니다.",
				confirmText = "예, 돌아가겠습니다.",
				declineText = "아직 괜찮습니다.",
			})
			return
		end

		-- 하늘섬 이동 조건 검사
		local level = PlayerStatService.getLevel(player.UserId) or 1
		local hasRune = playerHasHeavenRune(player)
		local canTravel = level >= REQUIRED_LEVEL and hasRune

		local dialogue, confirmText, declineText
		if canTravel then
			dialogue = "어서 오십시오, 여행자여.\n당신의 자격을 확인했습니다.\n하늘섬으로 인도해 드리겠습니다."
			confirmText = "하늘섬으로 이동한다."
			declineText = "아직 괜찮다."
		elseif level < REQUIRED_LEVEL and not hasRune then
			dialogue = string.format(
				"이곳은 아무나 오를 수 있는 곳이 아닙니다.\n\n하늘섬에 오르려면 레벨 <b>%d</b> 이상이어야 하며,\n<b>'하늘의 자격'</b> 패시브 룬을 장착해야 합니다.\n\n현재 레벨: <b>%d</b> / 룬 미장착",
				REQUIRED_LEVEL, level
			)
			confirmText = nil
			declineText = "알겠습니다."
		elseif level < REQUIRED_LEVEL then
			dialogue = string.format(
				"당신의 자격은 아직 부족합니다.\n\n하늘섬에 오르려면 레벨 <b>%d</b> 이상이어야 합니다.\n\n현재 레벨: <b>%d</b>",
				REQUIRED_LEVEL, level
			)
			confirmText = nil
			declineText = "알겠습니다."
		else
			dialogue = "'하늘의 자격' 패시브 룬을 장착하지 않으셨군요.\n\n하늘섬의 기운을 감당하려면 그 룬이 반드시 필요합니다.\n룬을 장착한 뒤 다시 찾아오십시오."
			confirmText = nil
			declineText = "알겠습니다."
		end

		NetController.FireClient(player, "SkyIsland.OpenDialogue", {
			isReturn = false,
			canTravel = canTravel,
			npcName = "하늘섬 인도자",
			dialogue = dialogue,
			confirmText = confirmText,
			declineText = declineText,
		})
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

	-- 서버 측 재검증 (하늘섬으로 이동하는 경우만)
	if not isReturn then
		local level = PlayerStatService.getLevel(player.UserId) or 1
		local hasRune = playerHasHeavenRune(player)
		if level < REQUIRED_LEVEL or not hasRune then
			return { success = false, errorCode = "NOT_QUALIFIED" }
		end
	end

	local targetPos = getTeleportPosition(isReturn)
	local destName = isReturn and "지상(아르하임)" or "하늘섬"
	
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
function SkyIslandTransportService.Init(netController, playerStatService)
	if initialized then return end
	initialized = true

	NetController = netController
	PlayerStatService = playerStatService
	
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
