-- NetController.lua
-- 네트워크 컨트롤러

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Protocol = require(Shared.Net.Protocol)
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local NetController = {}

-- requestId dedup 캐시 (TTL: Balance에서 참조 가능하나 Net은 고정 10초)
local requestCache = {}
local REQUEST_TTL = 10

local ADMIN_COMMANDS = {
	["Save.Now"] = true,
	["Time.Warp"] = true,
	["Time.WarpToPhase"] = true,
	["Time.Debug"] = true,
	["Inventory.GiveItem"] = true,
	["Craft.InstantComplete.Request"] = true,
	["Shop.Admin.GrantGold.Request"] = true,
	["GamePass.DebugForceApply.Request"] = true,
	["GamePass.DebugForceDisable.Request"] = true,
	["Tutorial.Admin.Reset.Request"] = true,
	["Tutorial.Admin.SetStep.Request"] = true,
	["Tutorial.Admin.ForceStart.Request"] = true,
	["Quest.Admin.Reset.Request"] = true,
	["Skill.Reset.Request"] = true,
	["Admin.FullReset.Request"] = true,
	["Admin.SetLevel.Request"] = true,
	["Admin.GiveEnhanceSet.Request"] = true,
	["Admin.GiveItem.Request"] = true,
	["Admin.SetElement.Request"] = true,
	-- [보안 수정] 아래 3개는 관리자/테스트 전용 퀘스트 초기화 커맨드인데 이 가드에서
	-- 누락되어 있었음. 특히 Magician.Quest.Reset.Request는 PORTAL_REGISTER 퀘스트가
	-- "이미 등록된 포탈이면 즉시 목표 달성" 처리를 하기 때문에, 아무나 이 커맨드를 반복
	-- 호출해서 (리셋 -> 수락 -> 즉시 수령) 무한 골드/XP를 얻을 수 있는 심각한 취약점이었음.
	["Magician.Quest.Reset.Request"] = true,
	["Trainer.Quest.Reset.Request"] = true,
	["Citizen.Quest.Reset.Request"] = true,
}

local function isAdmin(player: Player): boolean
	if game:GetService("RunService"):IsStudio() then
		return true
	end

	if Balance.ADMIN_IDS and Balance.ADMIN_IDS[player.UserId] == true then
		return true
	end

	return player.UserId == game.CreatorId
end

-- RemoteFunction / RemoteEvent 인스턴스
local Cmd: RemoteFunction
local Evt: RemoteEvent

-- 명령어 핸들러 테이블
local Handlers = {}

-- Ping 핸들러
Handlers["Net.Ping"] = function(player, payload)
	return { ok = true }
end

local function makeRequestKey(player: Player, requestId: string): string
	return tostring(player.UserId) .. ":" .. tostring(requestId)
end

-- requestId 중복 체크
local function isDuplicate(player: Player, requestId: string): boolean
	if not requestId then return false end
	
	local now = os.clock()
	local key = makeRequestKey(player, requestId)
	local entry = requestCache[key]
	
	if entry and (now - entry) < REQUEST_TTL then
		return true
	end
	
	return false
end

-- requestId 등록
local function registerRequest(player: Player, requestId: string)
	if not requestId then return end
	local key = makeRequestKey(player, requestId)
	requestCache[key] = os.clock()
end

-- 오래된 requestId 정리 (주기적 호출)
local function cleanupRequests()
	local now = os.clock()
	for key, timestamp in pairs(requestCache) do
		if (now - timestamp) >= REQUEST_TTL then
			requestCache[key] = nil
		end
	end
end

-- OnServerInvoke 핸들러
local function onServerInvoke(player: Player, request)
	-- 요청 검증
	if type(request) ~= "table" then
		return {
			success = false,
			error = Enums.ErrorCode.BAD_REQUEST,
		}
	end
	
	local command = request.command
	local requestId = request.requestId
	local payload = Protocol.Decompress(request.payload or {})
	
	-- 명령어 존재 확인
	if not command or not Protocol.Commands[command] then
		return {
			success = false,
			error = Enums.ErrorCode.NET_UNKNOWN_COMMAND,
		}
	end
	
	-- 어드민 명령어 가드
	if ADMIN_COMMANDS[command] and not isAdmin(player) then
		return {
			success = false,
			error = Enums.ErrorCode.NO_PERMISSION or "NO_PERMISSION",
		}
	end
	
	-- requestId 중복 체크
	if isDuplicate(player, requestId) then
		return {
			success = false,
			error = Enums.ErrorCode.NET_DUPLICATE_REQUEST,
		}
	end
	
	-- requestId 등록
	registerRequest(player, requestId)
	
	-- 핸들러 실행
	local handler = Handlers[command]
	if not handler then
		return {
			success = false,
			error = Enums.ErrorCode.NET_UNKNOWN_COMMAND,
		}
	end
	
	local success, result = pcall(handler, player, payload)
	
	if not success then
		warn("[NetController] Handler error:", command, result)
		return {
			success = false,
			error = Enums.ErrorCode.INTERNAL_ERROR,
		}
	end
	
	-- 결과 처리 및 압축
	if type(result) == "table" and result.success ~= nil then
		if result.success then
			return {
				success = true,
				data = Protocol.Compress(result.data or result),
			}
		else
			return {
				success = false,
				error = result.errorCode or result.error or Enums.ErrorCode.INTERNAL_ERROR,
			}
		end
	end
	
	return {
		success = true,
		data = Protocol.Compress(result),
	}
end

-- 초기화
function NetController.Init()
	-- RemoteFunction 생성
	Cmd = Instance.new("RemoteFunction")
	Cmd.Name = Protocol.CMD_NAME
	Cmd.Parent = ReplicatedStorage
	Cmd.OnServerInvoke = onServerInvoke
	
	-- RemoteEvent 생성
	Evt = Instance.new("RemoteEvent")
	Evt.Name = Protocol.EVT_NAME
	Evt.Parent = ReplicatedStorage
	
	-- 주기적 캐시 정리 (30초마다)
	task.spawn(function()
		while true do
			task.wait(30)
			cleanupRequests()
		end
	end)
	
	print("[NetController] Initialized")
end

-- 핸들러 등록 (외부 모듈용)
function NetController.RegisterHandler(command: string, handler: (Player, any) -> any)
	if not Protocol.Commands[command] then
		warn("[NetController] Command not in Protocol:", command)
		return false
	end
	Handlers[command] = handler
	return true
end

-- 클라이언트에 이벤트 전송
function NetController.FireClient(player: Player, eventName: string, data: any)
	if Evt then
		local compressedData = Protocol.Compress(data)
		Evt:FireClient(player, { event = eventName, data = compressedData })
	end
end

-- 모든 클라이언트에 이벤트 전송
function NetController.FireAllClients(eventName: string, data: any)
	if Evt then
		local compressedData = Protocol.Compress(data)
		Evt:FireAllClients({ event = eventName, data = compressedData })
	end
end

-- 특정 위치 기준 일정 범위 내의 클라이언트에게만 전송 (네트워크 최적화)
function NetController.FireClientsInRange(position: Vector3, range: number, eventName: string, data: any)
	if not Evt then return end
	
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end

			local dist = (hrp.Position - position).Magnitude
			if dist <= range then
				NetController.FireClient(player, eventName, data)
			end
		end
	end
end

return NetController
