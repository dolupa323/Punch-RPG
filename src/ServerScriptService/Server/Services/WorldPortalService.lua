-- WorldPortalService.lua
-- 월드 포탈 시스템 (탐험 포탈 등록 + 마을 포탈 이동)
-- 흐름: 목적지 포탈 발견 → 등록 → 마을 포탈에서 이동 선택

local WorldPortalService = {}
local initialized = false

local Players = game:GetService("Players")

local NetController
local SaveService
local ServiceRegistry = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("ServiceRegistry"))

-- 포탈 정의 (id, 이름) — 텔레포트 위치는 워크스페이스 모델에서 동적으로 계산
local PORTAL_DEFS = {
	{ id = "Grasslands",   name = "초원"        },
	{ id = "Forest",       name = "숲"          },
	{ id = "Kingdom",      name = "왕국"        },
	{ id = "Cave",         name = "동굴"        },
	{ id = "BatTerritory", name = "박쥐 서식지" },
	{ id = "Snowy",        name = "설원"        },
	{ id = "Sky",          name = "하늘섬"      },
}

local PORTAL_BY_ID = {}
for _, d in ipairs(PORTAL_DEFS) do PORTAL_BY_ID[d.id] = d end

--========================================
-- 공통 유틸
--========================================

-- 모델에서 가장 낮은(Y 최솟값) BasePart를 찾아 반환
local function _findLowestPart(model)
	local lowest = nil
	local lowestY = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local y = d.Position.Y - d.Size.Y / 2
			if y < lowestY then
				lowestY = y
				lowest = d
			end
		end
	end
	return lowest
end

--========================================
-- 저장 헬퍼
--========================================

local function _getRegistered(userId)
	if not SaveService then return {} end
	local state = SaveService.getPlayerState(userId)
	if not state then return {} end
	if not state.worldPortals then return {} end
	return state.worldPortals.registered or {}
end

local function _ensureWorldPortalState(state)
	if not state.worldPortals then
		state.worldPortals = { registered = {} }
	end
	if not state.worldPortals.registered then
		state.worldPortals.registered = {}
	end
end

--========================================
-- 핸들러
--========================================

local function _handleRegister(player, payload)
	local portalId = payload and payload.portalId
	if not PORTAL_BY_ID[portalId] then
		return { success = false, errorCode = "INVALID_PORTAL" }
	end

	local userId = player.UserId
	local registered = _getRegistered(userId)
	if registered[portalId] then
		return { success = false, errorCode = "ALREADY_REGISTERED" }
	end

	SaveService.updatePlayerState(userId, function(state)
		_ensureWorldPortalState(state)
		state.worldPortals.registered[portalId] = true
		return state
	end)

	local def = PORTAL_BY_ID[portalId]
	print(string.format("[WorldPortalService] %s registered portal: %s", player.Name, portalId))

	-- Magician 퀘스트 연동
	task.defer(function()
		local mqs = ServiceRegistry.Get("MagicianQuestService")
		if mqs and mqs.OnPortalRegistered then
			mqs.OnPortalRegistered(player, portalId)
		end
	end)

	return { success = true, portalId = portalId, name = def.name }
end

local function _handleGetList(player)
	local registered = _getRegistered(player.UserId)
	return { success = true, registered = registered }
end

-- 포탈 모델의 최하단 파트 위 스폰 위치 반환
local function _getPortalSpawnPos(portalId)
	local newWorldMap = workspace:FindFirstChild("NewWorldMap")
	if not newWorldMap then return nil end
	local portalFolder = newWorldMap:FindFirstChild("Portal") or newWorldMap:FindFirstChild("Potal")
	if not portalFolder then return nil end
	local model = portalFolder:FindFirstChild(portalId)
	if not model then return nil end
	local lowest = _findLowestPart(model)
	if lowest then
		return lowest.Position + Vector3.new(0, 5, 0)
	end
	-- 폴백: 모델 피봇 위
	if model:IsA("Model") then
		return model:GetPivot().Position + Vector3.new(0, 5, 0)
	end
	return nil
end

local function _handleTeleport(player, payload)
	local portalId = payload and payload.portalId
	if not PORTAL_BY_ID[portalId] then
		return { success = false, errorCode = "INVALID_PORTAL" }
	end

	local registered = _getRegistered(player.UserId)
	if not registered[portalId] then
		return { success = false, errorCode = "NOT_REGISTERED" }
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { success = false, errorCode = "NO_CHARACTER" }
	end

	local spawnPos = _getPortalSpawnPos(portalId)
	if not spawnPos then
		return { success = false, errorCode = "PORTAL_NOT_FOUND" }
	end

	hrp.CFrame = CFrame.new(spawnPos)
	print(string.format("[WorldPortalService] %s teleported to %s (%.0f,%.0f,%.0f)",
		player.Name, portalId, spawnPos.X, spawnPos.Y, spawnPos.Z))

	-- Magician 퀘스트 연동
	task.defer(function()
		local mqs = ServiceRegistry.Get("MagicianQuestService")
		if mqs and mqs.OnPortalTeleport then
			mqs.OnPortalTeleport(player, portalId)
		end
	end)

	return { success = true }
end

--========================================
-- ProximityPrompt 서버 설정
--========================================

local function _attachPrompt(part, objectText, actionText, onTriggered)
	if not part then return end
	local existing = part:FindFirstChild("WorldPortalPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WorldPortalPrompt"
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt.Parent = part

	prompt.Triggered:Connect(onTriggered)
	return prompt
end

local function _setupPrompts()
	task.spawn(function()
		local newWorldMap = workspace:WaitForChild("NewWorldMap", 60)
		if not newWorldMap then
			warn("[WorldPortalService] NewWorldMap not found")
			return
		end
		local portalFolder = newWorldMap:WaitForChild("Portal", 30)
		if not portalFolder then
			warn("[WorldPortalService] Portal folder not found")
			return
		end

		-- ── 목적지 포탈 (등록용 프롬프트) ──
		for _, def in ipairs(PORTAL_DEFS) do
			local model = portalFolder:WaitForChild(def.id, 15)
			if not model then
				warn("[WorldPortalService] Destination portal not found:", def.id)
				continue
			end
			-- 가장 낮은 파트에 부착 (프롬프트가 플레이어 시야에 나타나도록)
			local core = _findLowestPart(model)
			if not core then
				warn("[WorldPortalService] No BasePart in portal model:", def.id)
				continue
			end

			local capturedDef = def
			_attachPrompt(core, capturedDef.name .. " 포탈", "등록하기", function(player)
				local result = _handleRegister(player, { portalId = capturedDef.id })
				if result.success then
					NetController.FireClient(player, "WorldPortal.Registered", {
						portalId = capturedDef.id,
						name = capturedDef.name,
					})
				elseif result.errorCode == "ALREADY_REGISTERED" then
					NetController.FireClient(player, "Notify.Message", {
						text = capturedDef.name .. " 포탈은 이미 등록되어 있습니다.",
						color = "WHITE",
					})
				end
			end)

			print("[WorldPortalService] Prompt set on:", def.id)
		end

		-- ── 마을 포탈 (이동 UI 오픈) ──
		local villageModel = portalFolder:WaitForChild("Portal", 15)
		if villageModel then
			local teleportPart = villageModel:FindFirstChild("Teleport") or _findLowestPart(villageModel)
			if teleportPart then
				_attachPrompt(teleportPart, "마을 포탈", "포탈 이동", function(player)
					local registered = _getRegistered(player.UserId)
					NetController.FireClient(player, "WorldPortal.OpenUI", {
						registered = registered,
					})
				end)
				print("[WorldPortalService] Village portal prompt set")
			end
		end
	end)
end

--========================================
-- Public API
--========================================

function WorldPortalService.Init(_NetController, _SaveService)
	if initialized then return end
	initialized = true

	NetController = _NetController
	SaveService = _SaveService

	_setupPrompts()

	Players.PlayerRemoving:Connect(function() end)

	print("[WorldPortalService] Initialized with", #PORTAL_DEFS, "portals")
end

function WorldPortalService.GetHandlers()
	return {
		["WorldPortal.Register.Request"] = function(player, payload)
			return _handleRegister(player, payload)
		end,
		["WorldPortal.GetList.Request"] = function(player)
			return _handleGetList(player)
		end,
		["WorldPortal.Teleport.Request"] = function(player, payload)
			return _handleTeleport(player, payload)
		end,
	}
end

return WorldPortalService
