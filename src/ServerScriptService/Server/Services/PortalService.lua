-- PortalService.lua
-- 고대 포탈 시스템 (Ancient Portal)
-- 수리 재료 투입 → 강제 저장 → 열대섬 텔레포트

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local PortalService = {}
local initialized = false

-- Dependencies (injected via Init)
local NetController
local SaveService
local InventoryService

--========================================
-- Configuration
--========================================
local PORTAL_NAME = "Portal_Tropical"
local TARGET_PLACE_ID = 107341024431610
local PROMPT_DISTANCE = 14
local PORTAL_USE_DISTANCE = 26

-- 포탈 수리 비용 (grassland_ecosystem_design.md 섹션 9)
local REPAIR_COST = {
	{ itemId = "LOG", amount = 10, name = "통나무" },
	{ itemId = "STONE", amount = 10, name = "돌" },
}

local DEBOUNCE_COOLDOWN = 3
local debounces = {} -- userId → tick()
local promptParts = {}

--========================================
-- Internal: Player State
--========================================

--- 포탈 수리 여부 확인
local function _isPortalRepaired(userId)
	if not SaveService then return false end
	local state = SaveService.getPlayerState(userId)
	return state and state.portalRepaired == true
end

local function _ensurePortalProgress(state)
	state.portalProgress = type(state.portalProgress) == "table" and state.portalProgress or {}
	for _, req in ipairs(REPAIR_COST) do
		if type(state.portalProgress[req.itemId]) ~= "number" then
			state.portalProgress[req.itemId] = 0
		end
	end
	return state.portalProgress
end

--- 포탈 수리 완료 마킹
local function _markPortalRepaired(userId)
	if not SaveService then return end
	SaveService.updatePlayerState(userId, function(state)
		state.portalRepaired = true
		local progress = _ensurePortalProgress(state)
		for _, req in ipairs(REPAIR_COST) do
			progress[req.itemId] = req.amount
		end
		return state
	end)
end

local function _getPortalStatus(userId)
	local repaired = _isPortalRepaired(userId)
	local state = SaveService and SaveService.getPlayerState(userId)
	local progress = {}
	if state then
		progress = _ensurePortalProgress(state)
	end
	local cost = {}
	local allMet = true

	for _, req in ipairs(REPAIR_COST) do
		local current = math.clamp(tonumber(progress[req.itemId]) or 0, 0, req.amount)
		local met = current >= req.amount
		if not met then
			allMet = false
		end
		table.insert(cost, {
			itemId = req.itemId,
			name = req.name,
			required = req.amount,
			current = current,
			remaining = math.max(0, req.amount - current),
			met = met,
		})
	end

	if allMet and not repaired then
		_markPortalRepaired(userId)
		repaired = true
	end

	return {
		repaired = repaired,
		cost = cost,
	}
end

--========================================
-- Internal: Material Check
--========================================

--- 재료 보유 상태 확인 (부족한 항목 반환)
local function _checkMaterials(userId)
	local status = _getPortalStatus(userId)
	local allMet = true
	for _, item in ipairs(status.cost) do
		if not item.met then
			allMet = false
			break
		end
	end
	return allMet, status.cost
end

--- 수리 재료 소모
local function _consumeMaterials(userId)
	-- 사전 체크: 모든 재료 보유 확인
	for _, req in ipairs(REPAIR_COST) do
		if not InventoryService.hasItem(userId, req.itemId, req.amount) then
			return false
		end
	end

	-- 실제 소모
	local consumed = {}
	for _, req in ipairs(REPAIR_COST) do
		local removed = InventoryService.removeItem(userId, req.itemId, req.amount)
		table.insert(consumed, { itemId = req.itemId, count = removed })
		if removed < req.amount then
			-- 롤백
			for _, c in ipairs(consumed) do
				if c.count > 0 then
					InventoryService.addItem(userId, c.itemId, c.count)
				end
			end
			warn(string.format("[PortalService] Material consumption failed: %s (%d/%d)", req.itemId, removed, req.amount))
			return false
		end
	end
	return true
end

local function _getPortalObject()
	return workspace:FindFirstChild(PORTAL_NAME)
end

local function _getPortalReferencePart(portalObject)
	if not portalObject then return nil end
	if portalObject:IsA("BasePart") then return portalObject end
	if portalObject:IsA("Model") then
		return portalObject:FindFirstChild("PromptPart")
			or portalObject.PrimaryPart
			or portalObject:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function _distanceToPortalSurface(player, portalObject)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not portalObject then return math.huge end

	if portalObject:IsA("BasePart") then
		local p = hrp.Position
		local localPos = portalObject.CFrame:PointToObjectSpace(p)
		local half = portalObject.Size * 0.5
		local clamped = Vector3.new(
			math.clamp(localPos.X, -half.X, half.X),
			math.clamp(localPos.Y, -half.Y, half.Y),
			math.clamp(localPos.Z, -half.Z, half.Z)
		)
		local worldClosest = portalObject.CFrame:PointToWorldSpace(clamped)
		return (p - worldClosest).Magnitude
	end

	if portalObject:IsA("Model") then
		local p = hrp.Position
		local minDist = math.huge
		for _, d in ipairs(portalObject:GetDescendants()) do
			if d:IsA("BasePart") then
				local localPos = d.CFrame:PointToObjectSpace(p)
				local half = d.Size * 0.5
				local clamped = Vector3.new(
					math.clamp(localPos.X, -half.X, half.X),
					math.clamp(localPos.Y, -half.Y, half.Y),
					math.clamp(localPos.Z, -half.Z, half.Z)
				)
				local worldClosest = d.CFrame:PointToWorldSpace(clamped)
				local dist = (p - worldClosest).Magnitude
				if dist < minDist then
					minDist = dist
				end
			end
		end
		return minDist
	end

	return math.huge
end

local function _isPlayerNearPortal(player)
	local portalObject = _getPortalObject()
	if not portalObject then return false end
	return _distanceToPortalSurface(player, portalObject) <= PORTAL_USE_DISTANCE
end

local function _depositPortalMaterial(player, payload)
	local userId = player.UserId
	if not _isPlayerNearPortal(player) then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end

	if _isPortalRepaired(userId) then
		return { success = true, data = _getPortalStatus(userId) }
	end

	local itemId = payload and payload.itemId
	if type(itemId) ~= "string" or itemId == "" then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local reqData = nil
	for _, req in ipairs(REPAIR_COST) do
		if req.itemId == itemId then
			reqData = req
			break
		end
	end
	if not reqData then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local state = SaveService and SaveService.getPlayerState(userId)
	if not state then
		return { success = false, errorCode = "INVALID_STATE" }
	end

	local progress = _ensurePortalProgress(state)
	local current = math.clamp(tonumber(progress[itemId]) or 0, 0, reqData.amount)
	local need = reqData.amount - current
	if need <= 0 then
		return { success = true, data = _getPortalStatus(userId) }
	end

	local requestedAmount = math.max(1, math.floor(tonumber(payload and payload.amount) or need))
	local depositAmount = math.min(need, requestedAmount)

	if not InventoryService.hasItem(userId, itemId, 1) then
		local status = _getPortalStatus(userId)
		return { success = false, errorCode = "NO_ITEM", data = status }
	end

	local removed = InventoryService.removeItem(userId, itemId, depositAmount)
	if removed <= 0 then
		return { success = false, errorCode = "NO_ITEM" }
	end

	SaveService.updatePlayerState(userId, function(s)
		local prog = _ensurePortalProgress(s)
		prog[itemId] = math.min(reqData.amount, (tonumber(prog[itemId]) or 0) + removed)
		return s
	end)

	if SaveService and SaveService.savePlayer then
		local saveOk, saveErr = SaveService.savePlayer(userId)
		if not saveOk then
			warn(string.format("[PortalService] Immediate save failed after deposit (user=%d): %s", userId, tostring(saveErr)))
		end
	end

	local status = _getPortalStatus(userId)
	if status.repaired then
		NetController.FireClient(player, "Portal.Repaired", {})
	end

	return { success = true, data = status }
end

local function _requestPortalTeleport(player)
	if not _isPlayerNearPortal(player) then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end

	local userId = player.UserId
	if not _isPortalRepaired(userId) then
		return { success = false, errorCode = "INVALID_STATE" }
	end

	if TARGET_PLACE_ID == 0 then
		return { success = false, errorCode = "INVALID_STATE" }
	end

	NetController.FireClient(player, "Portal.Teleporting", {})
	local saveOk = SaveService.savePlayer(userId)
	if not saveOk then
		return { success = false, errorCode = "INTERNAL_ERROR" }
	end

	local success, err = pcall(function()
		TeleportService:TeleportAsync(TARGET_PLACE_ID, {player})
	end)
	if not success then
		warn("[PortalService] Teleport failed:", err)
		return { success = false, errorCode = "INTERNAL_ERROR" }
	end

	return { success = true, data = { teleporting = true } }
end

--========================================
-- Internal: Portal Interaction
--========================================

local function _onPortalTriggered(player)
	local userId = player.UserId

	-- 디바운스
	if debounces[userId] and (tick() - debounces[userId]) < DEBOUNCE_COOLDOWN then
		return
	end
	debounces[userId] = tick()

	if not _isPlayerNearPortal(player) then
		return
	end

	local status = _getPortalStatus(userId)
	NetController.FireClient(player, "Portal.UI.Open", status)
end

--========================================
-- Public API
--========================================

function PortalService.Init(_NetController, _SaveService, _InventoryService)
	if initialized then return end

	NetController = _NetController
	SaveService = _SaveService
	InventoryService = _InventoryService

	-- 포탈 오브젝트에 ProximityPrompt 설정
	task.spawn(function()
		local portalObject = workspace:WaitForChild(PORTAL_NAME, 30)
		if not portalObject then
			warn("[PortalService] Portal object not found:", PORTAL_NAME)
			return
		end

		local function attachPrompt(part)
			if not part or not part:IsA("BasePart") then return end

			local existing = part:FindFirstChild("PortalPrompt")
			if existing and existing:IsA("ProximityPrompt") then
				existing:Destroy()
			end

			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PortalPrompt"
			prompt.ObjectText = "고대 포탈"
			prompt.ActionText = "상호작용"
			prompt.KeyboardKeyCode = Enum.KeyCode.R
			prompt.MaxActivationDistance = PROMPT_DISTANCE
			prompt.HoldDuration = 0
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt.RequiresLineOfSight = false
			prompt.Parent = part

			prompt.Triggered:Connect(function(player)
				_onPortalTriggered(player)
			end)

			table.insert(promptParts, part)
		end

		if portalObject:IsA("Model") then
			local found = 0
			for _, d in ipairs(portalObject:GetDescendants()) do
				if d:IsA("BasePart") then
					attachPrompt(d)
					found += 1
				end
			end
			if found == 0 then
				local fallback = _getPortalReferencePart(portalObject)
				attachPrompt(fallback)
			end
		elseif portalObject:IsA("BasePart") then
			attachPrompt(portalObject)
		end

		print("[PortalService] Portal prompts initialized:", PORTAL_NAME)
	end)

	-- 플레이어 퇴장 시 디바운스 정리
	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId] = nil
	end)

	initialized = true
	print("[PortalService] Initialized")
end

--- 네트워크 핸들러
function PortalService.GetHandlers()
	return {
		["Portal.GetStatus.Request"] = function(player, _payload)
			return { success = true, data = _getPortalStatus(player.UserId) }
		end,
		["Portal.Deposit.Request"] = function(player, payload)
			return _depositPortalMaterial(player, payload or {})
		end,
		["Portal.Teleport.Request"] = function(player, _payload)
			return _requestPortalTeleport(player)
		end,
	}
end

return PortalService
