-- PlayerLifeService.lua
-- Phase 4-2: 플레이어 생존 시스템 (사망, 리스폰, 아이템 손실)
-- Server-Authoritative

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local PlayerLifeService = {}

-- Dependencies
local NetController
local DataService
local InventoryService
local BuildService

-- Constants
local ITEM_LOSS_PERCENT = 0.3 -- 사망 시 인벤토리 아이템 30% 손실
local DEFAULT_RESPAWN_POS = Vector3.new(0, 50, 0) -- 기본 리스폰 위치
local RESPAWN_DELAY = 5 -- 리스폰까지 대기 시간(초)

-- Player State
local playerDeathState = {} -- [userId] = { isDead, deathTime, respawnPoint, respawnPart }
local playerRespawnPreference = {} -- [userId] = { structureId = string }
local recallCooldowns = {} -- [userId] = os.clock()

--========================================
-- Internal Helpers
--========================================

local function toVector3(pos): Vector3?
	if typeof(pos) == "Vector3" then
		return pos
	end
	if type(pos) == "table" then
		return Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
	end
	return nil
end

local function loadRespawnPreferenceFromSave(userId: number)
	local ok, SaveService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.SaveService)
	end)
	if not ok or not SaveService or not SaveService.getPlayerState then
		return
	end

	for _ = 1, 10 do
		local state = SaveService.getPlayerState(userId)
		if state then
			if state.respawnStructureId then
				playerRespawnPreference[userId] = { structureId = state.respawnStructureId }
			end
			return
		end
		task.wait(0.5)
	end
end

--- 침대/침낭 리스폰 위치 찾기
local function findBedRespawnPoint(userId: number): Vector3?
	print(string.format("[PlayerLifeService] findBedRespawnPoint START (userId=%d)", userId))
	if not BuildService or not DataService then
		warn("[PlayerLifeService] findBedRespawnPoint: BuildService or DataService nil!")
		return nil
	end

	local function isRespawnFacility(facilityId: string?): boolean
		if not facilityId then
			return false
		end
		local facilityData = DataService.getFacility(facilityId)
		return facilityData and facilityData.functionType == "RESPAWN" or false
	end

	local preferred = playerRespawnPreference[userId]
	print(string.format("[PlayerLifeService] preferred=%s", preferred and ("structId=" .. tostring(preferred.structureId)) or "nil"))
	if preferred and preferred.structureId and BuildService.get then
		local struct = BuildService.get(preferred.structureId)
		print(string.format("[PlayerLifeService] BuildService.get(%s) => %s, owner=%s, facility=%s",
			tostring(preferred.structureId),
			struct and "found" or "nil",
			struct and tostring(struct.ownerId) or "?",
			struct and tostring(struct.facilityId) or "?"))
		if struct and struct.ownerId == userId and isRespawnFacility(struct.facilityId) then
			local pos = toVector3(struct.position)
			print(string.format("[PlayerLifeService] => struct position %s", tostring(pos)))
			return pos
		end
	end

	-- 구조물 매칭 실패 시, 마지막 수면 좌표(lastPosition)를 우선 리스폰 기준점으로 사용.
	do
		local ok, SaveService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.SaveService)
		end)
		if ok and SaveService and SaveService.getPlayerState then
			local state = SaveService.getPlayerState(userId)
			print(string.format("[PlayerLifeService] state=%s, lastPos=%s, respawnStructId=%s",
				state and "exists" or "nil",
				state and state.lastPosition and string.format("(%.1f,%.1f,%.1f)", state.lastPosition.x or 0, state.lastPosition.y or 0, state.lastPosition.z or 0) or "nil",
				state and tostring(state.respawnStructureId) or "nil"))
			if state and state.lastPosition then
				local pos = toVector3(state.lastPosition)
				if pos then
					print(string.format("[PlayerLifeService] => lastPosition fallback %s", tostring(pos)))
					return pos
				end
			end
		end
	end

	if BuildService.getStructuresByOwner then
		local owned = BuildService.getStructuresByOwner(userId)
		local latest = nil
		for _, struct in ipairs(owned) do
			if isRespawnFacility(struct.facilityId) then
				if (not latest) or ((struct.placedAt or 0) > (latest.placedAt or 0)) then
					latest = struct
				end
			end
		end
		if latest then
			return toVector3(latest.position)
		end
	end

	return nil
end

--- 인벤토리 아이템 랜덤 손실 처리
local function applyItemLoss(userId: number)
	local inv = InventoryService.getOrCreateInventory(userId)
	if not inv then return end

	-- [UX 개선] 1~8번 슬롯(단축키)은 보호하고 9번 이후(가방)만 손실 대상으로 분류
	local lossCandidateSlots = {}
	for slot, slotData in pairs(inv.slots) do
		if slotData and slotData.itemId and slot > 8 then
			table.insert(lossCandidateSlots, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
			})
		end
	end

	if #lossCandidateSlots == 0 then return end

	-- 손실 아이템 수 계산 (가방 아이템의 최대 30%)
	local lossCount = math.max(1, math.floor(#lossCandidateSlots * ITEM_LOSS_PERCENT))
	lossCount = math.min(lossCount, #lossCandidateSlots)

	-- 랜덤 셔플
	for i = #lossCandidateSlots, 2, -1 do
		local j = math.random(1, i)
		lossCandidateSlots[i], lossCandidateSlots[j] = lossCandidateSlots[j], lossCandidateSlots[i]
	end

	for i = 1, lossCount do
		local info = lossCandidateSlots[i]
		if info then
			InventoryService.removeItemFromSlot(userId, info.slot, info.count)
			print(string.format("[PlayerLifeService] Death Loss: Player %d lost %s x%d from slot %d",
				userId, info.itemId, info.count, info.slot))
		end
	end
end

--========================================
-- Death Respawn Teleport (CharacterAdded 통합)
--========================================

--- 사망 후 리스폰 시 상태 정리 + 이벤트 발행
--- CharacterAdded에서 호출 → 위치는 CharacterSetupService가 SpawnPos attribute로 즉시 처리
local function handleDeathRespawnCleanup(player: Player, character)
	local userId = player.UserId
	local dState = playerDeathState[userId]
	if not dState or not dState.isDead then
		return
	end

	local targetPoint = dState.respawnPoint or DEFAULT_RESPAWN_POS
	playerDeathState[userId] = nil
	player:SetAttribute("PendingDeathRespawn", nil)

	print(string.format("[PlayerLifeService] handleDeathRespawnCleanup: %s → state cleared (position handled by CharacterSetupService)", player.Name))

	if NetController then
		NetController.FireClient(player, "Player.Respawned", {
			position = targetPoint,
		})
	end
end

--- CharacterAdded 공통 핸들러 (사망 감지 + 리스폰 텔레포트)
local function onCharacterAddedForLife(player: Player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		PlayerLifeService._onPlayerDied(player)
	end)

	-- 사망 리스폰 대기 중이면 상태 정리 (위치는 CharacterSetupService가 SpawnPos로 처리)
	handleDeathRespawnCleanup(player, character)
end

--========================================
-- Public API
--========================================

function PlayerLifeService.Init(_NetController, _DataService, _InventoryService, _BuildService)
	NetController = _NetController
	DataService = _DataService
	InventoryService = _InventoryService
	BuildService = _BuildService

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadRespawnPreferenceFromSave, player.UserId)
		player.CharacterAdded:Connect(function(character)
			onCharacterAddedForLife(player, character)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadRespawnPreferenceFromSave, player.UserId)
		player.CharacterAdded:Connect(function(character)
			onCharacterAddedForLife(player, character)
		end)
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					PlayerLifeService._onPlayerDied(player)
				end)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		playerDeathState[player.UserId] = nil
		playerRespawnPreference[player.UserId] = nil
		recallCooldowns[player.UserId] = nil
	end)

	print("[PlayerLifeService] Initialized")
end

--- 플레이어 사망 처리
function PlayerLifeService._onPlayerDied(player: Player)
	local userId = player.UserId

	if playerDeathState[userId] and playerDeathState[userId].isDead then
		return
	end

	print(string.format("[PlayerLifeService] Player %s (%d) died!", player.Name, userId))

	applyItemLoss(userId)

	local respawnTarget = findBedRespawnPoint(userId)
	print(string.format("[PlayerLifeService] _onPlayerDied: respawnTarget=%s", tostring(respawnTarget or DEFAULT_RESPAWN_POS)))

	-- CharacterSetupService가 사망 리스폰을 구분할 수 있도록 플래그 설정
	player:SetAttribute("PendingDeathRespawn", true)

	playerDeathState[userId] = {
		isDead = true,
		deathTime = os.time(),
		respawnPoint = respawnTarget or DEFAULT_RESPAWN_POS,
		respawnPart = (typeof(respawnTarget) == "Instance") and respawnTarget or nil,
	}

	if NetController then
		NetController.FireClient(player, "Player.Died", {
			respawnDelay = RESPAWN_DELAY,
			respawnPoint = (typeof(respawnTarget) == "Instance") and respawnTarget.Position or (respawnTarget or DEFAULT_RESPAWN_POS),
		})
	end

	task.delay(RESPAWN_DELAY, function()
		if player.Parent then
			PlayerLifeService._respawnPlayer(player)
		end
	end)
end

--- 플레이어 리스폰 (LoadCharacter 호출만 담당, 텔레포트는 CharacterAdded에서 처리)
function PlayerLifeService._respawnPlayer(player: Player)
	local userId = player.UserId
	local state = playerDeathState[userId]
	if not state then
		print(string.format("[PlayerLifeService] _respawnPlayer: deathState nil for %d (already handled by system respawn)", userId))
		return
	end

	local respawnPoint = state.respawnPoint or DEFAULT_RESPAWN_POS
	print(string.format("[PlayerLifeService] _respawnPlayer: calling LoadCharacter for %s (target=%s)", player.Name, tostring(respawnPoint)))

	-- RespawnLocation 클리어 (SpawnLocation 강제 배치 방지)
	player.RespawnLocation = nil

	-- SpawnPos attribute 설정 → CharacterSetupService가 즉시 PivotTo
	local tp = respawnPoint + Vector3.new(0, 3, 0)
	player:SetAttribute("SpawnPosX", tp.X)
	player:SetAttribute("SpawnPosY", tp.Y)
	player:SetAttribute("SpawnPosZ", tp.Z)

	-- playerDeathState는 클리어하지 않음 → CharacterAdded 핸들러가 읽고 클리어
	player:LoadCharacter()
end

function PlayerLifeService.isDead(userId: number): boolean
	local state = playerDeathState[userId]
	return state ~= nil and state.isDead == true
end

function PlayerLifeService.setPreferredRespawn(userId: number, structureId: string)
	if not userId or not structureId or structureId == "" then
		return false
	end

	playerRespawnPreference[userId] = {
		structureId = structureId,
	}

	local ok, SaveService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.SaveService)
	end)
	if ok and SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.respawnStructureId = structureId
			return state
		end)
	end

	return true
end

--========================================
-- Recall (귀환) System
--========================================

local function handleRecallRequest(player, payload)
	local userId = player.UserId

	-- 사망 중 귀환 불가
	if playerDeathState[userId] and playerDeathState[userId].isDead then
		return { success = false, errorCode = "PLAYER_DEAD" }
	end

	-- 쿨다운 체크
	local Balance = require(ReplicatedStorage:WaitForChild("Shared").Config.Balance)
	local cooldown = Balance.RECALL_COOLDOWN or 120
	local now = os.clock()
	if recallCooldowns[userId] and (now - recallCooldowns[userId]) < cooldown then
		return { success = false, errorCode = "COOLDOWN" }
	end

	-- 취침 위치 찾기 (findBedRespawnPoint 재활용)
	local recallPos = findBedRespawnPoint(userId)
	if not recallPos then
		return { success = false, errorCode = "NO_SLEEP_LOCATION" }
	end

	-- 텔레포트 실행
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not hrp then
		return { success = false, errorCode = "INTERNAL_ERROR" }
	end

	local targetPos = recallPos + Vector3.new(0, 3, 0)
	character:PivotTo(CFrame.new(targetPos))
	recallCooldowns[userId] = now

	print(string.format("[PlayerLifeService] Recall: %s teleported to (%.1f, %.1f, %.1f)",
		player.Name, targetPos.X, targetPos.Y, targetPos.Z))

	return { success = true, data = { position = { X = targetPos.X, Y = targetPos.Y, Z = targetPos.Z } } }
end

function PlayerLifeService.GetHandlers()
	return {
		["Recall.Request"] = handleRecallRequest,
	}
end

return PlayerLifeService
