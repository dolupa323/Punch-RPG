-- GamePassService.lua
-- 게임패스 소유 여부 캐시 및 서버 권위 플래그 관리

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local GamePassService = {}

local DROP_RATE_2X_GAMEPASS_ID = 1864732763
local XP_2X_GAMEPASS_ID = 1919168387

-- 관리 대상 게임패스 정의: 각 패스가 어떤 상태키/속성/배율 속성에 매핑되는지
local MANAGED_GAMEPASSES = {
	[DROP_RATE_2X_GAMEPASS_ID] = { stateKey = "dropRate2x", ownedAttr = "HasDropRate2xPass", multAttr = "DropRateMultiplier" },
	[XP_2X_GAMEPASS_ID] = { stateKey = "xp2x", ownedAttr = "HasXP2xPass", multAttr = "XPMultiplier" },
}

local initialized = false
local NetController = nil
local playerPassState = {} -- [userId] = { dropRate2x = boolean, xp2x = boolean }

local function _setPassState(player: Player, gamePassId: number, ownsPass: boolean)
	local cfg = MANAGED_GAMEPASSES[gamePassId]
	if not cfg or not player then return end

	playerPassState[player.UserId] = playerPassState[player.UserId] or {}
	playerPassState[player.UserId][cfg.stateKey] = ownsPass == true
	player:SetAttribute(cfg.ownedAttr, ownsPass == true)
	player:SetAttribute(cfg.multAttr, ownsPass == true and 2 or 1)
end

local function _syncPass(player: Player, gamePassId: number)
	local cfg = MANAGED_GAMEPASSES[gamePassId]
	if not cfg or not player then return false, "INVALID_PLAYER" end

	local forced = player:GetAttribute("DebugForce" .. cfg.ownedAttr)
	if forced ~= nil then
		local ownsForced = forced == true
		_setPassState(player, gamePassId, ownsForced)
		return true, ownsForced
	end

	local ok, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)
	if not ok then
		warn(string.format("[GamePassService] Failed to query gamepass ownership for %s: %s", player.Name, tostring(ownsPass)))
		return false, tostring(ownsPass)
	end

	_setPassState(player, gamePassId, ownsPass == true)
	return true, ownsPass == true
end

local function _syncAllPasses(player: Player)
	for gamePassId in pairs(MANAGED_GAMEPASSES) do
		_syncPass(player, gamePassId)
	end
end

function GamePassService.playerHasDropRate2x(userId: number): boolean
	local state = playerPassState[userId]
	if state then
		return state.dropRate2x == true
	end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player:GetAttribute("HasDropRate2xPass") == true
	end

	return false
end

function GamePassService.playerHasXP2x(userId: number): boolean
	local state = playerPassState[userId]
	if state then
		return state.xp2x == true
	end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player:GetAttribute("HasXP2xPass") == true
	end

	return false
end

function GamePassService.refreshPlayer(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false, "NOT_FOUND"
	end
	_syncAllPasses(player)
	return true
end

function GamePassService.GetHandlers()
	return {
		["GamePass.DebugForceApply.Request"] = function(player: Player, payload: any)
			local targetId = tonumber(payload and payload.gamePassId) or DROP_RATE_2X_GAMEPASS_ID
			local cfg = MANAGED_GAMEPASSES[targetId]
			if not cfg then
				return { success = false, errorCode = "INVALID_GAMEPASS" }
			end
			player:SetAttribute("DebugForce" .. cfg.ownedAttr, true)
			_setPassState(player, targetId, true)
			return {
				success = true,
				data = {
					owned = true,
					dropRateMultiplier = player:GetAttribute("DropRateMultiplier") or 1,
					xpMultiplier = player:GetAttribute("XPMultiplier") or 1,
				},
			}
		end,
		["GamePass.DebugForceDisable.Request"] = function(player: Player, payload: any)
			local targetId = tonumber(payload and payload.gamePassId) or DROP_RATE_2X_GAMEPASS_ID
			local cfg = MANAGED_GAMEPASSES[targetId]
			if not cfg then
				return { success = false, errorCode = "INVALID_GAMEPASS" }
			end
			player:SetAttribute("DebugForce" .. cfg.ownedAttr, false)
			_setPassState(player, targetId, false)
			return {
				success = true,
				data = {
					owned = false,
					dropRateMultiplier = player:GetAttribute("DropRateMultiplier") or 1,
					xpMultiplier = player:GetAttribute("XPMultiplier") or 1,
				},
			}
		end,
		["GamePass.GetOwnership.Request"] = function(player: Player, payload: any)
			local targetId = tonumber(payload and payload.gamePassId)
			local cfg = targetId and MANAGED_GAMEPASSES[targetId]
			if not cfg then
				return { success = false, errorCode = "INVALID_GAMEPASS" }
			end

			local ok, result = _syncPass(player, targetId)
			if not ok then
				return { success = false, errorCode = result or "INTERNAL_ERROR" }
			end

			return {
				success = true,
				data = {
					owned = result == true,
					dropRateMultiplier = player:GetAttribute("DropRateMultiplier") or 1,
					xpMultiplier = player:GetAttribute("XPMultiplier") or 1,
				},
			}
		end,
		["GamePass.RefreshOwnership.Request"] = function(player: Player, payload: any)
			local targetId = tonumber(payload and payload.gamePassId)
			local cfg = targetId and MANAGED_GAMEPASSES[targetId]
			if not cfg then
				return { success = false, errorCode = "INVALID_GAMEPASS" }
			end

			local ok, result = _syncPass(player, targetId)
			if not ok then
				return { success = false, errorCode = result or "INTERNAL_ERROR" }
			end

			return {
				success = true,
				data = {
					owned = result == true,
					dropRateMultiplier = player:GetAttribute("DropRateMultiplier") or 1,
					xpMultiplier = player:GetAttribute("XPMultiplier") or 1,
				},
			}
		end,
	}
end

function GamePassService.Init(netController)
	if initialized then return end
	initialized = true
	NetController = netController

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			_syncAllPasses(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		if player then
			playerPassState[player.UserId] = nil
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	print("[GamePassService] Initialized")
end

return GamePassService
