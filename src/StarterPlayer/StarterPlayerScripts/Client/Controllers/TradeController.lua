-- TradeController.lua
-- 클라이언트 1:1 직거래 시스템 컨트롤러 (경매장 대체)
-- [Client-Side NetClient & UIManager Bridge]
-- 흐름: HUD "거래" 버튼 -> 주변 유저 목록 -> 선택해서 요청 -> 상대 수락 -> 교환창

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))
local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local localPlayer = Players.LocalPlayer

local TradeController = {}

--========================================
-- Private State
--========================================
local initialized = false
local _UIManager = nil

local COLOR_RED = Color3.fromRGB(255, 90, 90)
local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_GREEN = Color3.fromRGB(120, 220, 120)

local ERROR_MESSAGES = {
	BAD_REQUEST = "잘못된 요청입니다.",
	NOT_FOUND = "대상을 찾을 수 없습니다.",
	INVALID_STATE = "지금은 거래할 수 없는 상태입니다.",
	OUT_OF_RANGE = "상대방과 거리가 너무 멉니다.",
	INSUFFICIENT_GOLD = "골드가 부족합니다.",
	SLOT_EMPTY = "빈 슬롯입니다.",
	INVALID_COUNT = "수량이 올바르지 않습니다.",
	INVALID_ITEM = "거래할 수 없는 아이템입니다.",
}

local function errorMessage(errorCode)
	return ERROR_MESSAGES[errorCode] or "요청을 처리하지 못했습니다."
end

-- [버그수정] Trade.Failed가 서버의 실제 실패 사유(data.reason)를 무시하고 항상 같은
-- 뭉뚱그린 메시지만 보여줬음 (예: 거리 초과로 실패해도 "아이템/골드가 변경됐을 수 있다"고 나옴)
local FAILURE_REASONS = {
	OFFER_CHANGED = "그 사이 서로의 아이템/골드 상태가 바뀌어 거래에 실패했습니다.",
	ITEM_COLLECT_FAILED = "아이템을 회수하지 못해 거래에 실패했습니다.",
	GOLD_COLLECT_FAILED = "골드를 회수하지 못해 거래에 실패했습니다.",
	OUT_OF_RANGE = "상대방과 거리가 너무 멀어져 거래에 실패했습니다.",
}

local function failureMessage(reason)
	return FAILURE_REASONS[reason] or "거래에 실패했습니다."
end

--========================================
-- Public API: 주변 유저 목록
--========================================

--- 거래 요청 가능한 주변 플레이어 목록 (거리순 정렬)
function TradeController.getNearbyPlayers(): { { player: Player, distance: number } }
	local result = {}
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return result end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			local theirChar = player.Character
			local theirHrp = theirChar and theirChar:FindFirstChild("HumanoidRootPart")
			if theirHrp then
				local dist = (hrp.Position - theirHrp.Position).Magnitude
				-- [버그수정] 목록 표시 범위가 서버의 실제 요청 허용 범위(TRADE_INTERACT_RANGE)보다 넓으면
				-- 목록엔 뜨는데 요청은 거부되는("이유 없이 실패") 상황이 생김 -> 동일한 상수로 통일
				if dist <= Balance.TRADE_INTERACT_RANGE then
					table.insert(result, { player = player, distance = dist })
				end
			end
		end
	end

	table.sort(result, function(a, b) return a.distance < b.distance end)
	return result
end

--========================================
-- Public API: Server Requests
--========================================

--- 선택한 플레이어에게 거래 요청 전송
function TradeController.requestTrade(targetUserId: number, targetName: string?)
	task.spawn(function()
		local ok, result = NetClient.Request("Trade.Request.Request", { targetUserId = targetUserId })
		if ok and result and result.success then
			if _UIManager and targetName then
				_UIManager.notify(string.format("%s 님에게 거래를 요청했습니다.", targetName), COLOR_WHITE)
			end
		else
			if _UIManager then
				_UIManager.notify(errorMessage(result and result.errorCode), COLOR_RED)
			end
		end
	end)
end

--- 받은 거래 요청에 응답 (수락/거절)
function TradeController.respond(accept: boolean)
	task.spawn(function()
		local ok, result = NetClient.Request("Trade.Respond.Request", { accept = accept })
		if accept and (not ok or not (result and result.success)) then
			if _UIManager then
				local code = result and result.errorCode
				if code == "NOT_FOUND" then
					_UIManager.notify("이미 만료되었거나 취소된 거래 요청입니다.", COLOR_RED)
				else
					_UIManager.notify(errorMessage(code), COLOR_RED)
				end
			end
		end
	end)
end

--- 내 제안 갱신 (슬롯/골드)
function TradeController.updateOffer(slots: any, gold: number?)
	task.spawn(function()
		local ok, result = NetClient.Request("Trade.UpdateOffer.Request", { slots = slots, gold = gold })
		if not ok or not (result and result.success) then
			if _UIManager then
				_UIManager.notify(errorMessage(result and result.errorCode), COLOR_RED)
			end
		end
	end)
end

--- 교환하기 버튼 토글 (둘 다 confirmed=true가 되는 즉시 거래 성사)
function TradeController.confirm(confirmed: boolean?)
	task.spawn(function()
		local ok, result = NetClient.Request("Trade.Confirm.Request", { confirmed = confirmed ~= false })
		if not ok or not (result and result.success) then
			if _UIManager then
				_UIManager.notify(errorMessage(result and result.errorCode), COLOR_RED)
			end
		end
	end)
end

--- 거래 취소
--- [버그수정] 서버 응답을 확인 안 해서, 요청이 실패하면(예: 상대가 먼저 취소해 세션이 이미 사라진 경우)
--- 창을 닫을 방법이 없어지는 데드엔드가 있었다. 취소는 "빠져나가기" 동작이므로 서버 결과와 무관하게
--- 로컬 창을 항상 닫는다.
function TradeController.cancel()
	if _UIManager then
		_UIManager.closeTradeUI()
	end
	task.spawn(function()
		NetClient.Request("Trade.Cancel.Request", {})
	end)
end

--========================================
-- Initialization
--========================================

function TradeController.Init(uiManager)
	if initialized then return end
	initialized = true
	_UIManager = uiManager or require(script.Parent.Parent:WaitForChild("UIManager"))

	-- 거래 요청 수신: 수락/거절 팝업
	NetClient.On("Trade.Invited", function(data)
		if _UIManager and _UIManager.showTradeInvite then
			_UIManager.showTradeInvite(data)
		end
	end)

	NetClient.On("Trade.Declined", function(data)
		if _UIManager then
			_UIManager.notify("상대방이 거래를 거절했습니다.", COLOR_WHITE)
		end
	end)

	-- 거래 요청이 응답 없이 만료됨 (요청자/대상자 양쪽 모두 수신)
	NetClient.On("Trade.Expired", function(data)
		if _UIManager then
			if _UIManager.closeTradeInvite then
				_UIManager.closeTradeInvite()
			end
			if data and data.role == "requester" then
				_UIManager.notify("상대방이 응답하지 않아 거래 요청이 만료되었습니다.", COLOR_WHITE)
			else
				_UIManager.notify("거래 요청이 만료되었습니다.", COLOR_WHITE)
			end
		end
	end)

	-- 거래 시작/갱신: 거래창 오픈 및 데이터 반영
	NetClient.On("Trade.Started", function(data)
		if _UIManager then
			_UIManager.openTradeUI(data)
		end
	end)

	NetClient.On("Trade.OfferUpdated", function(data)
		if _UIManager then
			_UIManager.refreshTradeUI(data)
		end
	end)

	NetClient.On("Trade.Completed", function(data)
		if _UIManager then
			_UIManager.closeTradeUI()
			_UIManager.notify("거래가 완료되었습니다!", COLOR_GREEN)
			if _UIManager.refreshInventory then
				_UIManager.refreshInventory()
			end
		end
	end)

	NetClient.On("Trade.Cancelled", function(data)
		if _UIManager then
			_UIManager.closeTradeUI()
			_UIManager.notify("거래가 취소되었습니다.", COLOR_WHITE)
		end
	end)

	NetClient.On("Trade.Failed", function(data)
		if _UIManager then
			_UIManager.closeTradeUI()
			_UIManager.notify(failureMessage(data and data.reason), COLOR_RED)
		end
	end)

	print("[TradeController] Initialized")
end

return TradeController
