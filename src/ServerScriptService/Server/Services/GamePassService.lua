-- GamePassService.lua
-- 게임패스 소유 여부 캐시 및 서버 권위 플래그 관리

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local GamePassService = {}

local DROP_RATE_2X_GAMEPASS_ID = 1864732763

local initialized = false
local NetController = nil
local playerPassState = {} -- [userId] = { dropRate2x = boolean }

local function _setDropRateState(player: Player, ownsPass: boolean)
	if not player then return end
	playerPassState[player.UserId] = {
		dropRate2x = ownsPass == true,
	}
	player:SetAttribute("HasDropRate2xPass", ownsPass == true)
	player:SetAttribute("DropRateMultiplier", ownsPass == true and 2 or 1)
end

local function _syncDropRatePass(player: Player)
	if not player then return false, "INVALID_PLAYER" end

	local forced = player:GetAttribute("DebugForceDropRate2xPass")
	if forced ~= nil then
		local ownsForced = forced == true
		_setDropRateState(player, ownsForced)
		return true, ownsForced
	end

	local ok, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, DROP_RATE_2X_GAMEPASS_ID)
	end)
	if not ok then
		warn(string.format("[GamePassService] Failed to query gamepass ownership for %s: %s", player.Name, tostring(ownsPass)))
		return false, tostring(ownsPass)
	end

	_setDropRateState(player, ownsPass == true)
	return true, ownsPass == true
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

function GamePassService.refreshPlayer(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false, "NOT_FOUND"
	end
	return _syncDropRatePass(player)
end

function GamePassService.GetHandlers()
	return {
		["GamePass.DebugForceApply.Request"] = function(player: Player)
			player:SetAttribute("DebugForceDropRate2xPass", true)
			_setDropRateState(player, true)
			return {
				success = true,
				data = {
					owned = true,
					dropRateMultiplier = 2,
				},
			}
		end,
		["GamePass.DebugForceDisable.Request"] = function(player: Player)
			player:SetAttribute("DebugForceDropRate2xPass", false)
			_setDropRateState(player, false)
			return {
				success = true,
				data = {
					owned = false,
					dropRateMultiplier = 1,
				},
			}
		end,
		["GamePass.GetOwnership.Request"] = function(player: Player, payload: any)
			local targetId = tonumber(payload and payload.gamePassId)
			if targetId and targetId ~= DROP_RATE_2X_GAMEPASS_ID then
				return { success = false, errorCode = "INVALID_GAMEPASS" }
			end

			local ok, result = _syncDropRatePass(player)
			if not ok then
				return { success = false, errorCode = result or "INTERNAL_ERROR" }
			end

			return {
				success = true,
				data = {
					owned = result == true,
					dropRateMultiplier = player:GetAttribute("DropRateMultiplier") or 1,
				},
			}
		end,
		["GamePass.RefreshOwnership.Request"] = function(player: Player, payload: any)
			local targetId = tonumber(payload and payload.gamePassId)
			if targetId and targetId ~= DROP_RATE_2X_GAMEPASS_ID then
				return { success = false, errorCode = "INVALID_GAMEPASS" }
			end

			local ok, result = _syncDropRatePass(player)
			if not ok then
				return { success = false, errorCode = result or "INTERNAL_ERROR" }
			end

			return {
				success = true,
				data = {
					owned = result == true,
					dropRateMultiplier = player:GetAttribute("DropRateMultiplier") or 1,
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
			_syncDropRatePass(player)
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
