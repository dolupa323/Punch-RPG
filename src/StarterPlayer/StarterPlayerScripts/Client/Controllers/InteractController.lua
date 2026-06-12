-- InteractController.lua
-- 상호작용 컨트롤러 (채집, NPC 대화, 구조물 상호작용)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared:WaitForChild("Config"):WaitForChild("AnimationIds"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))

local Client = script.Parent.Parent
local NetClient = require(Client:WaitForChild("NetClient"))
local InputManager = require(Client:WaitForChild("InputManager"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local UILocalizer = require(Client:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local WindowManager = require(Client:WaitForChild("Utils"):WaitForChild("WindowManager"))
local NPCRadialUI = require(Client:WaitForChild("UI"):WaitForChild("NPCRadialUI"))

local InteractController = {}

--========================================
-- Private State
--========================================
local initialized = false
local player = Players.LocalPlayer

-- 상호작용 관련 기본 상수 및 해체 제어 변수
local INTERACT_DISTANCE = 8
local REMOVE_CONFIRM_WINDOW = 2.5
local pendingRemoveStructureId = nil
local pendingRemoveExpireAt = 0

-- [FIX] 탑승 제어 상태 변수 (Mount Control States)
local mountedControlState = { forward = false, backward = false, left = false, right = false }
local mountedJumpBound = false
local MOUNT_JUMP_ACTION = "MountJumpAction"
local MOUNT_MOVE_ACTION = "MountMoveAction"
local lastMountControlThrottle = 0
local lastMountControlSteer = 0

-- 상호작용 가능 대상
local currentTarget = nil
local currentTargetType = nil  -- "npc", "portal", "drop"
local playSleepTransitionAndRequest
local NPC_TARGET_PRIORITY_BONUS = 3.5
local isResting = false
local restAnimTrack = nil
local restMovementConn = nil

-- UIManager 참조 (Init 후 설정)
local UIManager = nil

-- [FIX] 해체 대기 상태 청소 헬퍼 함수
local function clearPendingRemove()
	pendingRemoveStructureId = nil
	pendingRemoveExpireAt = 0
end

local function getStructureIdFromTarget(target: Instance): string?
	if not target then
		return nil
	end
	local structureId = target:GetAttribute("StructureId") or target:GetAttribute("id") or target.Name
	if not structureId or structureId == "" then
		return nil
	end
	return tostring(structureId)
end

--========================================
-- Interactable Detection
--========================================

--- 파트의 표면까지 최단 거리 계산 (중심점이 아닌 실제 표면)
local function getDistToSurface(part: BasePart, playerPos: Vector3): number
	local cf = part.CFrame
	local size = part.Size
	-- 월드 좌표를 로컬로 변환하여 가장 가까운 점 계산
	local offset = cf:PointToObjectSpace(playerPos)
	local halfSize = size / 2
	local clamped = Vector3.new(
		math.clamp(offset.X, -halfSize.X, halfSize.X),
		math.clamp(offset.Y, -halfSize.Y, halfSize.Y),
		math.clamp(offset.Z, -halfSize.Z, halfSize.Z)
	)
	local closestWorld = cf:PointToWorldSpace(clamped)
	return (closestWorld - playerPos).Magnitude
end

--- 모델에서 가장 가까운 파트까지의 거리 계산
local function getDistToModel(model: Instance, playerPos: Vector3): number
	local minDist = math.huge
	if model:IsA("BasePart") then
		return getDistToSurface(model, playerPos)
	end
	-- Hitbox/InteractPart 우선
	local hitbox = model:FindFirstChild("Hitbox") or model:FindFirstChild("InteractPart")
	if hitbox and hitbox:IsA("BasePart") then
		return getDistToSurface(hitbox, playerPos)
	end
	-- PrimaryPart
	if model:IsA("Model") and model.PrimaryPart then
		return getDistToSurface(model.PrimaryPart, playerPos)
	end
	-- 가장 가까운 BasePart
	for _, child in pairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local d = getDistToSurface(child, playerPos)
			if d < minDist then minDist = d end
		end
	end
	return minDist
end

--- 플레이어 근처의 상호작용 가능 대상 찾기 (GetPartBoundsInRadius 최적화)
local function findNearbyInteractable(): (Instance?, string?)
	local character = player.Character
	if not character then return nil, nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end
	
	local playerPos = hrp.Position
	
	-- 공간 쿼리 파라미터 설정
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	
	local targetFolderNames = {"NPCs", "Portals"}
	local folderObjects = {}
	local includeList = {}
	for _, name in ipairs(targetFolderNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then 
			folderObjects[name] = folder
			table.insert(includeList, folder) 
		end
	end

	-- [특수 처리] Con_Doctor는 폴더 외부에 있어도 상호작용 가능하도록 추가
	local doctor = workspace:FindFirstChild("Con_Doctor")
	if doctor then
		table.insert(includeList, doctor)
		if not folderObjects["NPCs"] then
			folderObjects["NPCs"] = doctor
		end
	end
	
	if #includeList == 0 then 
		return nil, nil 
	end
	overlapParams.FilterDescendantsInstances = includeList
	
	-- 반경 내 파트 검색
	local searchRadius = math.max(Balance.SHOP_INTERACT_RANGE or 10, 14)
	local nearbyParts = workspace:GetPartBoundsInRadius(playerPos, searchRadius, overlapParams)
	
	local closestTarget = nil
	local closestType = nil
	local closestDist = searchRadius + 1
	local closestScore = math.huge
	
	local typeMap = {
		NPCs = "npc",
		Portals = "portal",
	}
	
	for _, part in ipairs(nearbyParts) do
		local entity = nil
		local currentType = nil
		
		-- 1. 특수 대상(Con_Doctor) 우선 체크
		local isDoctor = (doctor and (part == doctor or part:IsDescendantOf(doctor)))
		if isDoctor then
			currentType = "npc"
			-- 상호작용 가능한 루트(Con_Doctor 모델) 탐색
			local check = part
			while check do
				if check == doctor then
					entity = check
					break
				end
				if check == workspace then break end
				check = check.Parent
			end
		end

		-- 2. 일반 폴더 기반 체크 (아직 대상을 못 찾은 경우)
		if not entity then
			for folderName, folder in pairs(folderObjects) do
				if part:IsDescendantOf(folder) then
					currentType = typeMap[folderName]
					
					local check = part
					local foundEntity = nil
					
					while check do
						-- 1. 명시적인 속성이 있는 경우 일단 후보로 등록
						if check:GetAttribute("NodeId") or 
						   check:GetAttribute("FacilityId") or 
						   check:GetAttribute("NPCId") or
						   check:GetAttribute("IsPal") or
						   check:GetAttribute("ResourceNode") or
						   check:GetAttribute("PortalId") or
						   game:GetService("CollectionService"):HasTag(check, "ResourceNode") then
							
							foundEntity = check
							
							-- 2. 근데 이게 Part나 MeshPart이고 부모가 Model이라면, 데이터는 보통 Model에 있으므로 더 올라감
							if check:IsA("BasePart") and check.Parent and check.Parent:IsA("Model") then
								foundEntity = check.Parent
							end
							
							-- 최상위 엔티티를 찾았으므로 루프 종료
							break
						end
						
						-- 폴더 바로 아래의 오브젝트인 경우 (마지막 보루)
						if check.Parent == folder then
							if not foundEntity and (check:IsA("Model") or check:IsA("BasePart")) then
								foundEntity = check
							end
							break
						end
						
						if check == folder or check == workspace then break end
						check = check.Parent
					end
					
					entity = foundEntity
					break
				end
			end
		end
		
		if not entity then continue end

		-- [NEW] 포탈 타입 판정
		if entity:GetAttribute("FacilityId") == "PORTAL" or entity:GetAttribute("PortalId") then
			currentType = "portal"
		end

		if not currentType then continue end

		-- 팰인 경우 내 팰인지 체크 (RootPart 또는 Model에 걸린 IsPal 속성)
		if currentType == "pal" then
			local ownerId = entity:GetAttribute("OwnerUserId")
			if not ownerId or ownerId ~= player.UserId then
				continue -- 내 팰이 아니면 상호작용 후보에서 제외
			end
			-- 모델 자체로 entity 변경 (IsPal이 rootPart에 있을시)
			if entity:IsA("BasePart") and entity.Parent:IsA("Model") then
				entity = entity.Parent
			end
		end
		
		-- 고갈된 노드 스킵
		if currentType == "resource" and entity:GetAttribute("Depleted") then
			continue
		end
		
		local allowedDistance = INTERACT_DISTANCE
		if currentType == "pal" then
			allowedDistance = (Balance.HARVEST_RANGE or 10) + 4
		elseif currentType == "facility" then
			local facilityId = entity:GetAttribute("FacilityId")
			local facilityData = facilityId and DataHelper.GetData("FacilityData", tostring(facilityId)) or nil
			local serverRange = (facilityData and facilityData.interactRange) or INTERACT_DISTANCE
			-- 서버의 getInfo 거리 검증 기준과 클라 탐지 기준을 맞춰 접근 실패를 줄인다.
			allowedDistance = math.max(4, serverRange + 1)
		elseif currentType == "npc" then
			allowedDistance = math.max(INTERACT_DISTANCE, (Balance.SHOP_INTERACT_RANGE or 10) + 2)
		elseif currentType == "portal" then
			allowedDistance = (Balance.PORTAL_INTERACT_RANGE or 20)
		end

		local dist = getDistToModel(entity, playerPos)
		if currentType == "facility" then
			if entity:IsA("Model") then
				dist = (entity:GetPivot().Position - playerPos).Magnitude
			elseif entity:IsA("BasePart") then
				dist = (entity.Position - playerPos).Magnitude
			end
			-- 시설은 별도 추적 (채집노드가 가까워도 R키로 상호작용 가능)
			if dist <= allowedDistance and dist < closestFacilityDist then
				closestFacilityDist = dist
				closestFacility = entity
			end
		end
		-- ★ 시체(CORPSE_)는 일반 채집노드보다 항상 우선
		local nodeId = entity:GetAttribute("NodeId")
		local isCorpse = nodeId and string.sub(tostring(nodeId), 1, 7) == "CORPSE_"
		local closestIsCorpse = closestTarget and closestTarget:GetAttribute("NodeId")
			and string.sub(tostring(closestTarget:GetAttribute("NodeId")), 1, 7) == "CORPSE_"
		local score = dist
		if currentType == "npc" then
			score -= NPC_TARGET_PRIORITY_BONUS
		end
		
		if dist <= allowedDistance then
			-- 시체가 일반 노드를 밀어냄 / 같은 종류면 거리 비교
			if (isCorpse and not closestIsCorpse) or (score < closestScore and (isCorpse == closestIsCorpse or not closestIsCorpse)) then
				closestDist = dist
				closestScore = score
				closestTarget = entity
				closestType = currentType
			end
		end
	end

	return closestTarget, closestType, closestFacility
end

--========================================
-- Interaction Handlers
--========================================


-- pickupDrop function removed (moved to WorldDropController's ProximityPrompt)

--- NPC 대화/상점
local function interactNPC(target: Instance)
	local npcId = target:GetAttribute("NPCId") or target.Name
	local npcType = target:GetAttribute("NPCType") or "shop"
	
	print("[InteractController] Interacting with NPC:", npcId)
	
	if npcId == "Con_Doctor" or target.Name == "Con_Doctor" then
		if NPCRadialUI.IsOpen() then
			WindowManager.close("NPC_RADIAL")
		else
			WindowManager.open("NPC_RADIAL", target)
		end
		return
	end

	if npcType == "shop" then
		-- 상점 열기
		if UIManager then
			WindowManager.open("SHOP", npcId)
		end
	else
		-- 대화 등 다른 상호작용
		print("[InteractController] NPC interaction for", npcId, "falling back to radial menu")
		if NPCRadialUI.IsOpen() then
			WindowManager.close("NPC_RADIAL")
		else
			WindowManager.open("NPC_RADIAL", target)
		end
	end
end

--- 시설 상호작용
local function interactFacility(target: Instance)
	if not FacilityRadialUI then
		FacilityRadialUI = require(Client:WaitForChild("UI"):WaitForChild("FacilityRadialUI"))
	end
	
	if FacilityRadialUI.IsOpen() then
		WindowManager.close("FACILITY_RADIAL")
	else
		WindowManager.open("FACILITY_RADIAL", target)
	end
end

function InteractController.startRest()
	if isResting then return end
	
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	
	isResting = true
	NetClient.Request("Facility.Rest.Start", {})
	
	-- 애니메이션 재생 (AnimationManager 사용)
	local AnimationManager = require(Client:WaitForChild("Utils"):WaitForChild("AnimationManager"))
	local animName = AnimationIds.MISC.REST
	if animName then
		local track = AnimationManager.play(humanoid, animName)
		if track then
			restAnimTrack = track
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			
			-- 마지막 프레임에서 멈추기 (애니메이션 길이만큼 대기 후 속도 0)
			task.spawn(function()
				task.wait(track.Length * 0.95)
				if isResting and restAnimTrack == track then
					track:AdjustSpeed(0)
				end
			end)
		end
	end
	
	if UIManager then
		UIManager.notify("휴식 중... 이동하면 취소됩니다.", Color3.fromRGB(150, 255, 150))
	end
	
	-- [FIX] UI가 닫히는 즉시 움직임 체크를 하면 잔여 입력으로 인해 휴식이 취소될 수 있음
	-- 0.2초의 유예 기간을 두어 안정적으로 휴식 상태 진입 보장
	task.delay(0.2, function()
		if not isResting then return end
		
		if restMovementConn then
			restMovementConn:Disconnect()
		end
		
		restMovementConn = RunService.Heartbeat:Connect(function()
			if not character or not character.Parent then
				InteractController.stopRest()
				return
			end
			
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0.1 or humanoid.Jump then
				InteractController.stopRest()
			end
		end)
	end)
end

function InteractController.stopRest()
	if not isResting then return end
	isResting = false
	
	if restMovementConn then
		restMovementConn:Disconnect()
		restMovementConn = nil
	end
	
	if restAnimTrack then
		restAnimTrack:Stop(0.3)
		restAnimTrack = nil
	end
	
	NetClient.Request("Facility.Rest.Stop", {})
	
	if UIManager then
		UIManager.notify("휴식을 마쳤습니다.")
	end
end

local function removeFacility(target: Instance, skipConfirm: boolean)
	local structureId = getStructureIdFromTarget(target)
	if not structureId then
		clearPendingRemove()
		return
	end

	local now = tick()
	local isConfirmed = skipConfirm or ((pendingRemoveStructureId == structureId) and (now <= pendingRemoveExpireAt))
	if not isConfirmed then
		pendingRemoveStructureId = structureId
		pendingRemoveExpireAt = now + REMOVE_CONFIRM_WINDOW
		if UIManager then
			UIManager.notify("해체 확인: 2.5초 내 [T]를 다시 누르세요.", Color3.fromRGB(255, 210, 120))
		end
		return
	end

	clearPendingRemove()

	local ok, data = BuildController.requestRemove(structureId)
	if ok then
		if UIManager then
			UIManager.notify("시설을 해체했습니다.", Color3.fromRGB(140, 230, 140))
		end
	else
		if UIManager then
			local code = tostring(data)
			if code == "NO_PERMISSION" then
				UIManager.notify("토템 보호가 활성화되어 해체할 수 없습니다. 유지비 만료 후 약탈 가능합니다.", Color3.fromRGB(255, 120, 120))
			else
				UIManager.notify("해체할 수 없습니다. 다시 시도해주세요.", Color3.fromRGB(255, 120, 120))
				warn("[InteractController] Remove failed:", code)
			end
		end
	end
end



--========================================
-- Public API
--========================================

-- Local helper to unify and execute actual interaction
local function tryInteract()
	if not currentTarget then return false end
	
	if currentTargetType == "npc" then
		interactNPC(currentTarget)
		return true
	elseif currentTargetType == "portal" then
		local portalId = currentTarget:GetAttribute("PortalId")
		local isReturn = currentTarget:GetAttribute("IsReturn") or false
		if portalId then
			NetClient.Request("Portal.Interact.Request", { portalId = portalId, isReturn = isReturn })
		end
		return true
	elseif currentTargetType == "facility" then
		interactFacility(currentTarget)
		return true
	end
	return false
end

--- Z키 눌림 처리 (NPC/일반 상호작용)
function InteractController.onInteractPress()
	InteractController.onFacilityInteractPress()
end

--- R키 눌림 처리 (일반 상호작용)
function InteractController.onFacilityInteractPress()
	if InputManager.isUIOpen() then
		-- [Refactor] 모든 열린 창(방사형 UI 포함)을 WindowManager를 통해 닫음
		WindowManager.closeAll()
		return
	end

	tryInteract()
end

function InteractController.onFacilityRemovePress(skipConfirm: boolean)
	-- 구조물 해체 기능 제거
end

local function getMountControlValues()
	local throttle = 0
	if mountedControlState.forward then
		throttle += 1
	end
	if mountedControlState.backward then
		throttle -= 1
	end

	local steer = 0
	if mountedControlState.left then
		steer -= 1
	end
	if mountedControlState.right then
		steer += 1
	end

	return throttle, steer
end

local function sendMountedControl(force)
	local mountedPalUID = player:GetAttribute("MountedPalUID")
	local throttle, steer = getMountControlValues()
	if not mountedPalUID then
		throttle = 0
		steer = 0
	end

	lastMountControlThrottle = throttle
	lastMountControlSteer = steer

	local camera = workspace.CurrentCamera
	local lookDir = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)

	NetClient.Request("Party.Mount.Control.Request", {
		throttle = throttle,
		steer = steer,
		lookDir = lookDir,
	})
end

local function isMountedMovementKey(input: InputObject): boolean
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return false
	end

	local keyCode = input.KeyCode
	return keyCode == Enum.KeyCode.W
		or keyCode == Enum.KeyCode.A
		or keyCode == Enum.KeyCode.S
		or keyCode == Enum.KeyCode.D
		or keyCode == Enum.KeyCode.Up
		or keyCode == Enum.KeyCode.Down
		or keyCode == Enum.KeyCode.Left
		or keyCode == Enum.KeyCode.Right
end

local function updateMountedControlKey(input: InputObject, isPressed: boolean)
	local keyCode = input.KeyCode
	local handled = true
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		mountedControlState.forward = isPressed
	elseif keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		mountedControlState.backward = isPressed
	elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		mountedControlState.left = isPressed
	elseif keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		mountedControlState.right = isPressed
	else
		handled = false
	end

	if handled and player:GetAttribute("MountedPalUID") then
		sendMountedControl(false)
	end
end

local function syncMountedJumpBinding()
	local isMounted = player:GetAttribute("MountedPalUID") ~= nil

	if isMounted and not mountedJumpBound then
		ContextActionService:BindActionAtPriority(MOUNT_JUMP_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.PlayerActions.CharacterJump)
		mountedJumpBound = true
	elseif not isMounted and mountedJumpBound then
		ContextActionService:UnbindAction(MOUNT_JUMP_ACTION)
		mountedJumpBound = false
	end

	if isMounted then
		ContextActionService:BindActionAtPriority(MOUNT_MOVE_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight)
	else
		ContextActionService:UnbindAction(MOUNT_MOVE_ACTION)
	end

	if not isMounted then
		mountedControlState.forward = false
		mountedControlState.backward = false
		mountedControlState.left = false
		mountedControlState.right = false
		sendMountedControl(true)
	end
end

--- 주변 대상 감지 업데이트 (10Hz)
local function onUpdate()
	syncMountedJumpBinding()

	if player:GetAttribute("MountedPalUID") then
		currentTarget = nil
		currentTargetType = nil
		currentFacilityTarget = nil
		if UIManager then
			UIManager.hideInteractPrompt()
		end
		return
	end

	-- UI가 열려있거나 제작 중이면 상호작용 레이블 숨김
	if InputManager.isUIOpen() or (UIManager and UIManager.isCrafting and UIManager.isCrafting()) then
		if currentTarget then
			currentTarget = nil
			currentTargetType = nil
			if UIManager then UIManager.hideInteractPrompt() end
		end
		return
	end

	local target, targetType, nearbyFacility = findNearbyInteractable()
	currentFacilityTarget = nearbyFacility
	
	if target ~= currentTarget or targetType ~= currentTargetType then
		clearPendingRemove()
		currentTarget = target
		currentTargetType = targetType
	end

	if UIManager then
		if currentTarget then
			local promptText = ""
			local targetName = nil
			local fId = currentTarget:GetAttribute("FacilityId") or currentTarget:GetAttribute("id")
			if fId then
				local fid = tostring(fId):upper()
				local data = DataHelper.GetData("FacilityData", fid)
				targetName = UILocalizer.LocalizeDataText("FacilityData", fid, "name", data and data.name or fid)
			end
			
			if not targetName then
				local nId = currentTarget:GetAttribute("NodeId")
				if nId then
					local nid = tostring(nId):upper()
					local data = DataHelper.GetData("ResourceNodeData", nid)
					targetName = UILocalizer.LocalizeDataText("ResourceNodeData", nid, "name", data and data.name or nid)
				end
			end

			targetName = targetName or currentTarget:GetAttribute("DisplayName")
			if not targetName or targetName == "" then
				if currentTarget.Name == "Con_Doctor" then
					targetName = "콘닥터"
				else
					targetName = currentTarget.Name
				end
			end

			if currentTargetType == "radio" then
				targetName = UILocalizer.Localize("비상 무전기")
			elseif currentTargetType == "pal" then
				local cId = currentTarget:GetAttribute("CreatureId")
				if cId then
					local cData = DataHelper.GetData("CreatureData", cId)
					targetName = cData and cData.name or cId
				end
			end
			
			if currentTargetType == "resource" then
				promptText = UILocalizer.Localize("[R] 채집")
			elseif currentTargetType == "npc" then
				promptText = UILocalizer.Localize("[R] 대화")
			elseif currentTargetType == "facility" then
				promptText = UILocalizer.Localize("[R] 사용") .. "  " .. UILocalizer.Localize("[T] 해체")
			elseif currentTargetType == "pal" then
				promptText = UILocalizer.Localize("[R] 공룡 메뉴")
			elseif currentTargetType == "radio" then
				promptText = UILocalizer.Localize("[R] 무전 수신")
			elseif currentTargetType == "portal" then
				promptText = UILocalizer.Localize("[R] 상호작용")
			else
				promptText = UILocalizer.Localize("[R] 상호작용")
			end
			
			if promptText ~= "" then
				UIManager.showInteractPrompt(promptText, targetName)
			else
				UIManager.hideInteractPrompt()
			end
		else
			UIManager.hideInteractPrompt()
		end
	end
end

--========================================
-- Initialization
--========================================

function InteractController.Init()
	if initialized then
		warn("[InteractController] Already initialized!")
		return
	end
	
	-- UIManager 로드 (지연)
	task.spawn(function()
		UIManager = require(Client:WaitForChild("UIManager"))
		
		-- [NEW] 모바일 대응: 프롬프트 터치로 상호작용
		task.spawn(function()
			local InteractUI = require(Client:WaitForChild("UI"):WaitForChild("InteractUI"))
			if InteractUI and InteractUI.Refs and InteractUI.Refs.PromptFrame then
				InteractUI.Refs.PromptFrame.Activated:Connect(function()
					if InputManager.isUIOpen() then return end
					local handled = tryInteract()
					if handled then
						InteractUI.Hide()
					end
				end)
			end
		end)
	end)

	InteractController.rebindDefaultKeys()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local allowMountedMovement = player:GetAttribute("MountedPalUID")
			and isMountedMovementKey(input)
			and not UserInputService:GetFocusedTextBox()
		if gameProcessed and not allowMountedMovement then
			return
		end
		updateMountedControlKey(input, true)
	end)
	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		updateMountedControlKey(input, false)
	end)
	player:GetAttributeChangedSignal("MountedPalUID"):Connect(syncMountedJumpBinding)
	syncMountedJumpBinding()
	
	-- 주기적으로 대상 감지 업데이트 (0.1초 - 10Hz)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local success, err = pcall(onUpdate)
			if not success then
				-- warn("[InteractController] Update error:", err)
			end
		end
	end)
	
-- (Dino/Mount logic removed)

-- (Dino/Mount physics removed)
	
	initialized = true
	print("[InteractController] Initialized (R = Interact)")
end

--- 전역 상호작용 키 바인딩 복구 (타 UI나 모드에서 가로챈 키 반환용)
function InteractController.rebindDefaultKeys()
	local InputManager = require(Client:WaitForChild("InputManager"))
	
	-- R = 모든 상호작용 통합
	InputManager.bindKey(Enum.KeyCode.R, "InteractFacilityR", function()
		if InteractController.onFacilityInteractPress then
			InteractController.onFacilityInteractPress()
		end
	end)

	-- ESC = 모든 UI 닫기 통합
	InputManager.bindKey(Enum.KeyCode.Escape, "CloseUI", function()
		
		-- Radial UIs
		local FRUI = require(Client:WaitForChild("UI"):WaitForChild("FacilityRadialUI"))
		if FRUI.IsOpen() then FRUI.Close() end
		
		local PortalRUI = require(Client:WaitForChild("UI"):WaitForChild("PortalRadialUI"))
		if PortalRUI.IsOpen() then PortalRUI.Close() end
		
		local HarvestUI = require(Client:WaitForChild("UI"):WaitForChild("HarvestUI"))
		if HarvestUI.IsOpen() then HarvestUI.Close() end
		
		local WindowManagerMod = require(Client:WaitForChild("Utils"):WaitForChild("WindowManager"))
		if WindowManagerMod and WindowManagerMod.closeAll then
			WindowManagerMod.closeAll()
		end
	end)
	
	print("[InteractController] Default keys (R, T, ESC) rebound.")
end

return InteractController
