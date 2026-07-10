-- TradeService.lua
-- 1:1 직거래 시스템 (경매장 대체)
-- 두 플레이어가 모두 온라인인 상태에서만 성립하므로, 협상 중에는 인벤토리를 물리적으로
-- 건드리지 않고 순수 인메모리 세션으로만 제안을 들고 있다가, 양쪽 확정 시에만
-- InventoryService/NPCShopService의 기존 함수로 원자적 스왑을 실행한다.

local TradeService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)
local DataHelper = require(Shared.Util.DataHelper)

local Server = ServerScriptService:WaitForChild("Server")
local InventoryService = require(Server.Services.InventoryService)
local NPCShopService = require(Server.Services.NPCShopService)

local NetController = nil
local initialized = false

-- activeSessions[sessionId] = {
--   userA, userB,
--   offerA = { slots = { [slot] = count }, gold = number },
--   offerB = { slots = { [slot] = count }, gold = number },
--   confirmedA, confirmedB,
-- }
local activeSessions = {}
local playerSession = {}   -- [userId] = sessionId
local pendingInvite = {}   -- [targetUserId] = { fromUserId, expiresAt }

local nextSessionId = 0

--========================================
-- 내부 유틸
--========================================

local function newOffer()
	return { slots = {}, gold = 0 }
end

local function makeSessionId()
	nextSessionId += 1
	return "TRADE_" .. tostring(nextSessionId) .. "_" .. tostring(os.clock())
end

local function getSession(userId)
	local sid = playerSession[userId]
	if not sid then return nil, nil end
	return activeSessions[sid], sid
end

local function otherUserId(session, userId)
	if session.userA == userId then return session.userB end
	if session.userB == userId then return session.userA end
	return nil
end

local function offerFor(session, userId)
	if session.userA == userId then return session.offerA end
	if session.userB == userId then return session.offerB end
	return nil
end

local function resetConfirm(session)
	session.confirmedA = false
	session.confirmedB = false
end

local function clearSession(sessionId)
	local session = activeSessions[sessionId]
	if not session then return end
	playerSession[session.userA] = nil
	playerSession[session.userB] = nil
	activeSessions[sessionId] = nil
end

local function distanceBetween(userIdA, userIdB)
	local pA = Players:GetPlayerByUserId(userIdA)
	local pB = Players:GetPlayerByUserId(userIdB)
	local charA = pA and pA.Character
	local charB = pB and pB.Character
	local hrpA = charA and charA:FindFirstChild("HumanoidRootPart")
	local hrpB = charB and charB:FindFirstChild("HumanoidRootPart")
	if not hrpA or not hrpB then return math.huge end
	return (hrpA.Position - hrpB.Position).Magnitude
end

local function fireBoth(session, event, buildData)
	local pA = Players:GetPlayerByUserId(session.userA)
	local pB = Players:GetPlayerByUserId(session.userB)
	if NetController then
		if pA then NetController.FireClient(pA, event, buildData(session.userA)) end
		if pB then NetController.FireClient(pB, event, buildData(session.userB)) end
	end
end

-- 클라이언트에 보낼 세션 스냅샷 (요청자 기준 mine/theirs로 정렬)
local function buildSnapshot(session, forUserId)
	local mine = offerFor(session, forUserId)
	local theirUserId = otherUserId(session, forUserId)
	local theirs = offerFor(session, theirUserId)
	local theirPlayer = Players:GetPlayerByUserId(theirUserId)

	-- [버그수정] `cond and A or B` 삼항연산자는 A가 false일 때 무조건 B로 새버리는 Lua의 함정.
	-- confirmedA/B는 false일 수 있는 boolean이라 이 패턴을 쓰면 "내가 확정 안 했는데 상대가 확정하면
	-- 내 쪽이 확정된 것처럼", 반대로 "내가 확정하면 상대가 확정한 것처럼" 뒤바뀌어 보이는 버그가 났었다.
	local myConfirmed, theirConfirmed
	if session.userA == forUserId then
		myConfirmed = session.confirmedA
		theirConfirmed = session.confirmedB
	else
		myConfirmed = session.confirmedB
		theirConfirmed = session.confirmedA
	end

	return {
		partnerUserId = theirUserId,
		partnerName = theirPlayer and theirPlayer.Name or "?",
		myOffer = { slots = mine.slots, gold = mine.gold },
		theirOffer = { slots = theirs.slots, gold = theirs.gold },
		myConfirmed = myConfirmed,
		theirConfirmed = theirConfirmed,
	}
end

--========================================
-- 핸들러: 거래 요청 / 응답
--========================================

local function handleRequest(player, payload)
	local userId = player.UserId
	local targetUserId = payload and payload.targetUserId
	if type(targetUserId) ~= "number" then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	if targetUserId == userId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	if playerSession[userId] or playerSession[targetUserId] then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	-- [버그수정] 대상에게 이미 다른 사람의 초대가 살아있는데 체크 없이 덮어쓰면, 먼저 보낸 요청자는
	-- 아무 통지도 없이 조용히 증발해버렸다 (그 사람의 20초 타임아웃도 fromUserId가 이미 바뀌어서
	-- 발동하지 않음). 대상이 이미 다른 유효한 초대에 응답 대기 중이면 새 요청 자체를 거부한다.
	local existingInvite = pendingInvite[targetUserId]
	if existingInvite and existingInvite.expiresAt >= os.clock() and existingInvite.fromUserId ~= userId then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	if distanceBetween(userId, targetUserId) > Balance.TRADE_INTERACT_RANGE then
		return { success = false, errorCode = Enums.ErrorCode.OUT_OF_RANGE }
	end

	pendingInvite[targetUserId] = { fromUserId = userId, expiresAt = os.clock() + Balance.TRADE_INVITE_TIMEOUT }

	if NetController then
		NetController.FireClient(targetPlayer, "Trade.Invited", {
			fromUserId = userId,
			fromName = player.Name,
		})
	end

	task.delay(Balance.TRADE_INVITE_TIMEOUT, function()
		local inv = pendingInvite[targetUserId]
		-- 그 사이 이미 수락/거절되었으면(=pendingInvite가 지워졌거나 다른 요청으로 교체됐으면) 아무것도 하지 않는다
		if inv and inv.fromUserId == userId then
			pendingInvite[targetUserId] = nil
			if NetController then
				-- 요청자: "상대가 응답하지 않았다"는 것을 알려줌
				NetController.FireClient(player, "Trade.Expired", { role = "requester" })
				-- 대상자: 아직 떠있는 초대 팝업을 닫도록 알려줌
				if targetPlayer and targetPlayer.Parent then
					NetController.FireClient(targetPlayer, "Trade.Expired", { role = "target" })
				end
			end
		end
	end)

	return { success = true }
end

local function handleRespond(player, payload)
	local userId = player.UserId
	local accept = payload and payload.accept == true

	local invite = pendingInvite[userId]
	if not invite or invite.expiresAt < os.clock() then
		pendingInvite[userId] = nil
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end
	pendingInvite[userId] = nil

	local requesterId = invite.fromUserId
	local requester = Players:GetPlayerByUserId(requesterId)

	if not accept then
		if requester and NetController then
			NetController.FireClient(requester, "Trade.Declined", { byUserId = userId })
		end
		return { success = true }
	end

	if not requester then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end
	if playerSession[userId] or playerSession[requesterId] then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end
	if distanceBetween(userId, requesterId) > Balance.TRADE_INTERACT_RANGE then
		return { success = false, errorCode = Enums.ErrorCode.OUT_OF_RANGE }
	end

	local sessionId = makeSessionId()
	local session = {
		userA = requesterId,
		userB = userId,
		offerA = newOffer(),
		offerB = newOffer(),
		confirmedA = false,
		confirmedB = false,
	}
	activeSessions[sessionId] = session
	playerSession[requesterId] = sessionId
	playerSession[userId] = sessionId

	fireBoth(session, "Trade.Started", function(forUserId)
		return buildSnapshot(session, forUserId)
	end)

	return { success = true }
end

--========================================
-- 핸들러: 제안 갱신 / 취소
--========================================

local function handleUpdateOffer(player, payload)
	local userId = player.UserId
	local session = getSession(userId)
	if not session then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	local myOffer = offerFor(session, userId)

	-- 골드 제안 갱신
	-- [버그수정] NaN(자기 자신과도 다름)이나 무한대 값은 `> 0` 비교가 전부 false/우회되어
	-- 검증을 건너뛸 수 있었다(변조 클라이언트 악용 가능) — 유한한 정상 숫자인지 먼저 확인한다.
	if payload and type(payload.gold) == "number" and payload.gold == payload.gold and payload.gold < math.huge then
		local gold = math.floor(math.max(0, payload.gold))
		if gold > NPCShopService.getGold(userId) then
			return { success = false, errorCode = Enums.ErrorCode.INSUFFICIENT_GOLD }
		end
		myOffer.gold = gold
	end

	-- 슬롯 제안 갱신 (payload.slots = { [slot] = count 또는 0(제거) })
	-- [버그수정] 슬롯 번호는 각자의 인벤토리 안에서만 의미가 있는 값이라, 상대방 화면에서
	-- "상대 제안"을 그릴 때 자기 자신의 인벤토리로 그 슬롯을 조회하면 당연히 아무것도 안 나온다.
	-- 그래서 여기서 서버가 직접 조회한 itemId를 스냅샷에 같이 실어 보낸다.
	if payload and type(payload.slots) == "table" then
		for slotStr, count in pairs(payload.slots) do
			local slot = tonumber(slotStr)
			if slot then
				count = math.floor(tonumber(count) or 0)
				if count <= 0 then
					myOffer.slots[slot] = nil
				else
					local slotData = InventoryService.getSlot(userId, slot)
					if not slotData or not slotData.itemId then
						return { success = false, errorCode = Enums.ErrorCode.SLOT_EMPTY }
					end
					if not DataHelper.IsTradeable(slotData.itemId) then
						return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
					end
					if count > slotData.count then
						return { success = false, errorCode = Enums.ErrorCode.INVALID_COUNT }
					end
					myOffer.slots[slot] = { itemId = slotData.itemId, count = count }
				end
			end
		end
	end

	-- 제안이 바뀌면 양쪽 다 재확인(교환하기) 필요 (표준 거래창 UX)
	resetConfirm(session)

	fireBoth(session, "Trade.OfferUpdated", function(forUserId)
		return buildSnapshot(session, forUserId)
	end)

	return { success = true }
end

local function handleCancel(player, payload)
	local userId = player.UserId
	local session, sessionId = getSession(userId)
	if not session then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	clearSession(sessionId)

	fireBoth(session, "Trade.Cancelled", function(forUserId)
		return { byUserId = userId }
	end)

	return { success = true }
end

--========================================
-- 핸들러: 확정 (원자적 스왑)
--========================================

-- 두 플레이어의 제안 아이템을 실제 인벤토리로 옮긴다.
-- 실패 시 이미 회수한 아이템/골드를 즉시 원래 주인에게 되돌린다 (NPCShopService.buy 롤백 패턴 재사용).
local function executeSwap(session)
	local userA, userB = session.userA, session.userB
	local offerA, offerB = session.offerA, session.offerB

	-- 1. 재검증: 제안한 슬롯/수량/골드가 그 시점에도 실제로 존재하는지
	local function validateOffer(userId, offer)
		if offer.gold > 0 and NPCShopService.getGold(userId) < offer.gold then
			return false
		end
		for slot, entry in pairs(offer.slots) do
			local slotData = InventoryService.getSlot(userId, slot)
			if not slotData or not slotData.itemId or slotData.itemId ~= entry.itemId or slotData.count < entry.count then
				return false
			end
		end
		return true
	end

	if not validateOffer(userA, offerA) or not validateOffer(userB, offerB) then
		return false, "OFFER_CHANGED"
	end

	-- 2. 아이템/골드 회수 (양쪽) — 회수한 만큼 기록해서 실패 시 되돌릴 수 있게 함
	local removedFromA = {} -- slot -> {itemId, count, durability, attributes}
	local removedFromB = {}
	local goldTakenFromA, goldTakenFromB = 0, 0

	local function collect(userId, offer, removedTable)
		for slot, entry in pairs(offer.slots) do
			local slotData = InventoryService.getSlot(userId, slot)
			if not slotData or not slotData.itemId then
				return false
			end
			local removed = InventoryService.removeItemFromSlot(userId, slot, entry.count)
			if removed <= 0 then
				return false
			end
			table.insert(removedTable, {
				itemId = slotData.itemId,
				count = removed,
				durability = slotData.durability,
				attributes = slotData.attributes,
			})
			if removed < entry.count then
				-- 부분 회수: 남은 만큼은 롤백 대상에서 제외하고 실패 처리
				return false
			end
		end
		return true
	end

	local function refund(userId, removedTable, goldAmount)
		for _, entry in ipairs(removedTable) do
			InventoryService.addItem(userId, entry.itemId, entry.count, entry.durability, entry.attributes)
		end
		if goldAmount and goldAmount > 0 then
			NPCShopService.addGold(userId, goldAmount)
		end
	end

	local okA = collect(userA, offerA, removedFromA)
	if not okA then
		refund(userA, removedFromA, 0)
		return false, "ITEM_COLLECT_FAILED"
	end

	local okB = collect(userB, offerB, removedFromB)
	if not okB then
		refund(userA, removedFromA, 0)
		refund(userB, removedFromB, 0)
		return false, "ITEM_COLLECT_FAILED"
	end

	if offerA.gold > 0 then
		local ok = NPCShopService.removeGold(userA, offerA.gold)
		if ok then
			goldTakenFromA = offerA.gold
		else
			refund(userA, removedFromA, 0)
			refund(userB, removedFromB, 0)
			return false, "GOLD_COLLECT_FAILED"
		end
	end

	if offerB.gold > 0 then
		local ok = NPCShopService.removeGold(userB, offerB.gold)
		if ok then
			goldTakenFromB = offerB.gold
		else
			refund(userA, removedFromA, goldTakenFromA)
			refund(userB, removedFromB, 0)
			return false, "GOLD_COLLECT_FAILED"
		end
	end

	-- 4. 상대에게 지급. 인벤토리가 꽉 차서 일부만 들어가면, 못 들어간 만큼은 원래 주인에게 되돌린다.
	local function grant(recipientUserId, removedTable)
		local leftover = {}
		for _, entry in ipairs(removedTable) do
			local added, remaining = InventoryService.addItem(recipientUserId, entry.itemId, entry.count, entry.durability, entry.attributes)
			if remaining and remaining > 0 then
				table.insert(leftover, { itemId = entry.itemId, count = remaining, durability = entry.durability, attributes = entry.attributes })
			end
		end
		return leftover
	end

	local leftoverForB = grant(userB, removedFromA) -- A가 준 아이템 -> B에게
	local leftoverForA = grant(userA, removedFromB) -- B가 준 아이템 -> A에게

	for _, entry in ipairs(leftoverForB) do
		InventoryService.addItem(userA, entry.itemId, entry.count, entry.durability, entry.attributes)
	end
	for _, entry in ipairs(leftoverForA) do
		InventoryService.addItem(userB, entry.itemId, entry.count, entry.durability, entry.attributes)
	end

	if goldTakenFromA > 0 then
		NPCShopService.addGold(userB, goldTakenFromA)
	end
	if goldTakenFromB > 0 then
		NPCShopService.addGold(userA, goldTakenFromB)
	end

	return true
end

-- "교환하기" 버튼 1개로 확정/취소를 토글. 둘 다 확정 상태가 되는 즉시 거래를 실행한다.
local function handleConfirm(player, payload)
	local userId = player.UserId
	local session, sessionId = getSession(userId)
	if not session then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end

	local confirmed = not (payload and payload.confirmed == false)
	if session.userA == userId then
		session.confirmedA = confirmed
	else
		session.confirmedB = confirmed
	end

	if not (session.confirmedA and session.confirmedB) then
		fireBoth(session, "Trade.OfferUpdated", function(forUserId)
			return buildSnapshot(session, forUserId)
		end)
		return { success = true, waiting = true }
	end

	-- 둘 다 확정: 근접 재검증 후 원자적 스왑 실행
	if distanceBetween(session.userA, session.userB) > Balance.TRADE_INTERACT_RANGE then
		clearSession(sessionId)
		fireBoth(session, "Trade.Failed", function(forUserId)
			return { reason = "OUT_OF_RANGE" }
		end)
		return { success = false, errorCode = Enums.ErrorCode.OUT_OF_RANGE }
	end

	local ok, reason = executeSwap(session)
	clearSession(sessionId)

	if not ok then
		fireBoth(session, "Trade.Failed", function(forUserId)
			return { reason = reason }
		end)
		return { success = false, errorCode = Enums.ErrorCode.INVALID_STATE }
	end

	fireBoth(session, "Trade.Completed", function(forUserId)
		return {}
	end)

	return { success = true }
end

--========================================
-- Public API
--========================================

function TradeService.Init(netController)
	if initialized then return end
	initialized = true
	NetController = netController

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId

		-- 내가 "받은" 초대 정리
		pendingInvite[userId] = nil

		-- [버그수정] 내가 "보낸" 초대도 정리해야 한다. 안 그러면 상대는 이미 죽어버린 요청의
		-- 수락/거절 팝업을 자연 만료(최대 20초)될 때까지 붙들고 있게 된다 — 즉시 정리 + 통지.
		for targetUserId, inv in pairs(pendingInvite) do
			if inv.fromUserId == userId then
				pendingInvite[targetUserId] = nil
				local targetPlayer = Players:GetPlayerByUserId(targetUserId)
				if targetPlayer and NetController then
					NetController.FireClient(targetPlayer, "Trade.Expired", { role = "target" })
				end
			end
		end

		local session, sessionId = getSession(userId)
		if session then
			clearSession(sessionId)
			local otherId = otherUserId(session, userId)
			local otherPlayer = Players:GetPlayerByUserId(otherId)
			if otherPlayer and NetController then
				NetController.FireClient(otherPlayer, "Trade.Cancelled", { byUserId = userId })
			end
		end
	end)

	print("[TradeService] Initialized (1:1 direct trade)")
end

function TradeService.GetHandlers()
	return {
		["Trade.Request.Request"] = handleRequest,
		["Trade.Respond.Request"] = handleRespond,
		["Trade.UpdateOffer.Request"] = handleUpdateOffer,
		["Trade.Confirm.Request"] = handleConfirm,
		["Trade.Cancel.Request"] = handleCancel,
	}
end

return TradeService
