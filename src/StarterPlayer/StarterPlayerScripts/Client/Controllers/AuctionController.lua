-- AuctionController.lua
-- 클라이언트 경매장 이벤트/요청 관리 컨트롤러

local AuctionController = {}

local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))
local UIManager = require(script.Parent.Parent:WaitForChild("UIManager"))

local initialized = false
local pendingListeners = {}

-- 에러 코드 한글 번역 맵
local ERROR_MESSAGES = {
	["TRADE_RESTRICTED"] = "교환 불가 아이템은 등록할 수 없습니다.",
	["ITEM_NOT_FOUND_OR_INSUFFICIENT"] = "아이템이 없거나 수량이 부족합니다.",
	["INVALID_PARAMETERS"] = "수량과 가격은 올바른 숫자여야 합니다.",
	["INVALID_VALUES"] = "수량과 가격은 올바른 숫자여야 합니다.",
	["REGISTRATION_FAILED"] = "매물 등록에 실패했습니다. 다시 시도해주세요.",
	["ITEM_NOT_FOUND"] = "해당 매물을 찾을 수 없습니다.",
	["CANNOT_BUY_OWN_ITEM"] = "본인이 등록한 매물은 구매할 수 없습니다.",
	["NOT_ENOUGH_GOLD"] = "골드가 부족합니다.",
	["INVENTORY_FULL"] = "가방에 빈 슬롯이 없습니다.",
	["ALREADY_SOLD_OR_EXPIRED"] = "이미 판매되었거나 취소된 매물입니다.",
	["GOLD_DEDUCTION_FAILED"] = "골드 차감에 실패했습니다.",
	["NO_PERMISSION"] = "권한이 없습니다.",
	["NO_PENDING_GOLD"] = "정산금이 없습니다.",
	["TIMEOUT"] = "서버 응답 시간이 초과되었습니다.",
	["NETWORK_ERROR"] = "네트워크 오류가 발생했습니다."
}

local function getErrorMessage(errCode)
	return ERROR_MESSAGES[errCode] or ("오류가 발생했습니다: " .. tostring(errCode))
end

--========================================
-- Public API: Listeners
--========================================
function AuctionController.onPendingUpdated(callback)
	table.insert(pendingListeners, callback)
	return {
		Disconnect = function()
			for i, cb in ipairs(pendingListeners) do
				if cb == callback then
					table.remove(pendingListeners, i)
					break
				end
			end
		end
	}
end

local function firePendingListeners(data)
	for _, callback in ipairs(pendingListeners) do
		pcall(function() callback(data) end)
	end
end

--========================================
-- Public API: Server Requests
--========================================
function AuctionController.getListings()
	local success, response = NetClient.Request("Auction.GetListings.Request", {})
	if success then
		return response.listings or {}
	else
		warn("[AuctionController] Failed to get listings:", response)
		return nil, response
	end
end

function AuctionController.registerSale(slot, count, pricePerUnit)
	local success, response = NetClient.Request("Auction.RegisterSale.Request", {
		slot = slot,
		count = count,
		pricePerUnit = pricePerUnit
	})
	if success then
		UIManager.sideNotify("매물이 정상 등록되었습니다.", Color3.fromRGB(100, 255, 100))
		UIManager.refreshInventory()
		return true
	else
		UIManager.notify(getErrorMessage(response), Color3.fromRGB(255, 100, 100))
		return false, response
	end
end

function AuctionController.buyItem(listingId)
	local success, response = NetClient.Request("Auction.BuyItem.Request", {
		listingId = listingId
	})
	if success then
		UIManager.sideNotify("아이템을 구매하였습니다.", Color3.fromRGB(100, 255, 100))
		UIManager.refreshInventory()
		return true
	else
		UIManager.notify("구매 실패: " .. getErrorMessage(response), Color3.fromRGB(255, 100, 100))
		return false, response
	end
end

function AuctionController.cancelSale(listingId)
	local success, response = NetClient.Request("Auction.CancelSale.Request", {
		listingId = listingId
	})
	if success then
		UIManager.sideNotify("판매가 취소되었습니다.", Color3.fromRGB(100, 255, 100))
		UIManager.refreshInventory()
		return true
	else
		UIManager.notify("취소 실패: " .. getErrorMessage(response), Color3.fromRGB(255, 100, 100))
		return false, response
	end
end

function AuctionController.getPending()
	local success, response = NetClient.Request("Auction.GetPending.Request", {})
	if success then
		return response
	else
		warn("[AuctionController] Failed to get pending data:", response)
		return nil, response
	end
end

function AuctionController.claimPending()
	local success, response = NetClient.Request("Auction.ClaimPending.Request", {})
	if success then
		local gold = response.claimedGold or 0
		if gold <= 0 then
			UIManager.notify("정산금이 없습니다.", Color3.fromRGB(255, 100, 100))
			return false, "정산금이 없습니다."
		end
		UIManager.sideNotify(string.format("%d 골드를 정산받았습니다.", gold), Color3.fromRGB(255, 215, 0))
		return true, gold
	else
		local errorMsg = getErrorMessage(response)
		UIManager.notify(errorMsg, Color3.fromRGB(255, 100, 100))
		return false, response
	end
end

--========================================
-- Server Event Handlers
--========================================
local function onAuctionPendingUpdated(data)
	firePendingListeners(data)
	
	-- UIManager에 알림 및 정산 UI 리프레시 유도
	if UIManager.refreshAuctionPending then
		UIManager.refreshAuctionPending(data)
	end
end

--========================================
-- Initialization
--========================================
function AuctionController.Init()
	if initialized then return end
	initialized = true
	
	-- 서버로부터 실시간 알림 이벤트 대기
	NetClient.On("Auction.UpdatePending", onAuctionPendingUpdated)
	
	print("[AuctionController] Initialized")
end

return AuctionController
