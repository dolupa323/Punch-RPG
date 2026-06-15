-- AuctionService.lua
-- 전 서버 통합 경매장 서비스
-- MemoryStoreService를 활용해 실시간 매물 동기화 및 DataStore 기반 안전한 정산 처리

local AuctionService = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Server = ServerScriptService:WaitForChild("Server")
local Persistence = Server:WaitForChild("Persistence")
local DataStoreClient = require(Persistence.DataStoreClient)

local InventoryService = require(Server.Services.InventoryService)
local NPCShopService = require(Server.Services.NPCShopService)
local DataHelper = require(Shared.Util.DataHelper)
local SaveService = require(Server.Services.SaveService)
local SkillService = require(Server.Services.SkillService)

local NetController = nil
local sortedMap = nil
local initialized = false

-- 경매장 매물 만료 시간 (7일)
local LISTING_EXPIRY = 604800

function AuctionService.Init(netController)
	if initialized then return end
	initialized = true
	
	NetController = netController
	sortedMap = MemoryStoreService:GetSortedMap("AuctionListings")
	
	print("[AuctionService] Initialized with MemoryStore sortedMap")
end

-- 헬퍼: 정산 데이터 업데이트 (DataStore)
local function updatePendingGold(userId: number, earnedGold: number, itemId: string, count: number, pricePerUnit: number)
	local key = "PENDING_GOLD_" .. tostring(userId)
	local success, result = DataStoreClient.update(key, function(oldData)
		oldData = oldData or { gold = 0, history = {} }
		oldData.gold = (oldData.gold or 0) + earnedGold
		
		-- 최대 30개 기록 보관
		table.insert(oldData.history, 1, {
			itemId = itemId,
			count = count,
			pricePerUnit = pricePerUnit,
			timestamp = os.time(),
			type = "SALE"
		})
		
		while #oldData.history > 30 do
			table.remove(oldData.history)
		end
		
		return oldData
	end)
	
	-- 만약 판매자가 현재 서버에 있다면 즉시 알림
	local seller = Players:GetPlayerByUserId(userId)
	if seller then
		NetController.FireClient(seller, "Auction.UpdatePending", {
			gold = result and result.gold or 0
		})
	end
end

-- 1. 매물 전체 조회
function AuctionService.getListings(player, payload)
	local listings = {}
	local success, range = pcall(function()
		return sortedMap:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	
	if success and range then
		for _, entry in ipairs(range) do
			local val = entry.value
			if val and not val.isSold and not val.isCancelled then
				table.insert(listings, val)
			end
		end
	else
		warn("[AuctionService] GetRangeAsync failed:", range)
	end
	
	return { success = true, listings = listings }
end

-- 2. 매물 등록
function AuctionService.registerSale(player, payload)
	local userId = player.UserId
	local count = tonumber(payload.count)
	local pricePerUnit = tonumber(payload.pricePerUnit)
	
	if not payload.slot or not count or not pricePerUnit then
		return { success = false, errorCode = "INVALID_PARAMETERS" }
	end
	
	if count <= 0 or pricePerUnit <= 0 then
		return { success = false, errorCode = "INVALID_VALUES" }
	end
	
	-- 슬롯 아이템 정보 획득 (스킬북 인벤토리 대응)
	local slotStr = tostring(payload.slot)
	local isSkillBook = (string.sub(slotStr, 1, 10) == "BOOK_SLOT_")
	local slotData = nil
	local bookIndex = nil
	
	if isSkillBook then
		bookIndex = tonumber(string.sub(slotStr, 11))
		if not bookIndex then
			return { success = false, errorCode = "INVALID_PARAMETERS" }
		end
		
		local state = SaveService.getPlayerState(userId)
		if not state or not state.skillBooks or not state.skillBooks[bookIndex] then
			return { success = false, errorCode = "ITEM_NOT_FOUND_OR_INSUFFICIENT" }
		end
		
		local bookItemId = state.skillBooks[bookIndex]
		slotData = {
			itemId = bookItemId,
			count = 1,
			durability = 100,
			attributes = {}
		}
	else
		local slotNum = tonumber(payload.slot)
		if not slotNum then
			return { success = false, errorCode = "INVALID_PARAMETERS" }
		end
		slotData = InventoryService.getSlot(userId, slotNum)
	end
	
	if not slotData or slotData.count < count then
		return { success = false, errorCode = "ITEM_NOT_FOUND_OR_INSUFFICIENT" }
	end
	
	-- 교환 제한 아이템 여부 검증
	if not DataHelper.IsTradeable(slotData.itemId) then
		return { success = false, errorCode = "TRADE_RESTRICTED" }
	end
	
	-- 아이템 제거
	if isSkillBook then
		local state = SaveService.getPlayerState(userId)
		table.remove(state.skillBooks, bookIndex)
		SaveService.markPlayerDirty(userId)
		
		-- 클라이언트 데이터 동기화 알림
		local clientData = SkillService.getClientSkillData(userId)
		NetController.FireClient(player, "Skill.Data.Updated", clientData)
	else
		local slotNum = tonumber(payload.slot)
		local removed = InventoryService.removeItemFromSlot(userId, slotNum, count)
		if removed <= 0 then
			return { success = false, errorCode = "REMOVE_FAILED" }
		end
	end
	
	-- 유니크 매물 ID 생성
	local listingId = tostring(userId) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	
	local listing = {
		listingId = listingId,
		sellerId = userId,
		sellerName = player.Name,
		itemId = slotData.itemId,
		count = count,
		pricePerUnit = pricePerUnit,
		durability = slotData.durability,
		attributes = slotData.attributes,
		timestamp = os.time(),
	}
	
	-- MemoryStore에 등록
	local success, err = pcall(function()
		sortedMap:SetAsync(listingId, listing, LISTING_EXPIRY)
	end)
	
	if not success then
		warn("[AuctionService] SetAsync failed:", err)
		-- 복구: 플레이어에게 아이템 복구
		if isSkillBook then
			local state = SaveService.getPlayerState(userId)
			table.insert(state.skillBooks, bookIndex, slotData.itemId)
			SaveService.markPlayerDirty(userId)
			
			local clientData = SkillService.getClientSkillData(userId)
			NetController.FireClient(player, "Skill.Data.Updated", clientData)
		else
			InventoryService.addItem(userId, slotData.itemId, count, slotData.durability, slotData.attributes)
		end
		return { success = false, errorCode = "REGISTRATION_FAILED" }
	end
	
	print(string.format("[AuctionService] User %s registered %x%s for %d gold each (ListingID: %s)", player.Name, count, slotData.itemId, pricePerUnit, listingId))
	
	return { success = true }
end

-- 3. 매물 즉시 구매 (트랜잭션)
function AuctionService.buyItem(player, payload)
	local buyerUserId = player.UserId
	local listingId = payload.listingId
	
	if not listingId then
		return { success = false, errorCode = "INVALID_PARAMETERS" }
	end
	
	-- 1. MemoryStore에서 매물 조회
	local success, listing = pcall(function()
		return sortedMap:GetAsync(listingId)
	end)
	
	if not success or not listing then
		return { success = false, errorCode = "ITEM_NOT_FOUND" }
	end
	
	-- 본인 매물도 구매 가능하도록 수정됨
	
	local totalPrice = listing.pricePerUnit * listing.count
	
	-- 2. 구매자 재화 검증
	local buyerGold = NPCShopService.getGold(buyerUserId)
	if buyerGold < totalPrice then
		return { success = false, errorCode = "NOT_ENOUGH_GOLD" }
	end
	
	-- 3. 구매자 가방 공간 검증 (스킬북은 가방 공간 검증 제외)
	local itemData = DataHelper.GetData("ItemData", listing.itemId)
	local isBuyerSkillBook = (itemData and itemData.type == "SKILL_BOOK") or (string.sub(listing.itemId, 1, 5) == "BOOK_")
	if not isBuyerSkillBook then
		if not InventoryService.canAdd(buyerUserId, listing.itemId, listing.count) then
			return { success = false, errorCode = "INVENTORY_FULL" }
		end
	end
	
	-- 4. 원자적 키 획득 (중복 방지 락 핵심)
	local isBought = false
	local listingData = nil
	
	local successUpdate, errUpdate = pcall(function()
		sortedMap:UpdateAsync(listingId, function(oldValue)
			if oldValue and not oldValue.isSold and not oldValue.isCancelled then
				listingData = oldValue
				isBought = true
				
				-- 판매 완료 상태로 마킹하여 업데이트 (중복 구매 락)
				local newValue = {}
				for k, v in pairs(oldValue) do newValue[k] = v end
				newValue.isSold = true
				return newValue
			end
			return oldValue
		end, LISTING_EXPIRY)
	end)
	
	if not successUpdate or not isBought or not listingData then
		return { success = false, errorCode = "ALREADY_SOLD_OR_EXPIRED" }
	end
	
	-- 물리적으로 메모리 스토어에서 매물 삭제
	pcall(function()
		sortedMap:RemoveAsync(listingId)
	end)
	
	-- 5. 구매자 재화 차감
	local deductOk, deductErr = NPCShopService.removeGold(buyerUserId, totalPrice)
	if not deductOk then
		-- 극단적인 비정상 상태 대비 롤백 (메모리에 매물 복구)
		pcall(function()
			local rollbackData = {}
			for k, v in pairs(listingData) do rollbackData[k] = v end
			rollbackData.isSold = nil
			sortedMap:SetAsync(listingId, rollbackData, LISTING_EXPIRY)
		end)
		return { success = false, errorCode = "GOLD_DEDUCTION_FAILED" }
	end
	
	-- 6. 구매자 아이템 지급 (스킬북 여부 판단 후 추가)
	local itemData = DataHelper.GetData("ItemData", listingData.itemId)
	local isBuyerSkillBook = (itemData and itemData.type == "SKILL_BOOK") or (string.sub(listingData.itemId, 1, 5) == "BOOK_")
	if isBuyerSkillBook then
		local state = SaveService.getPlayerState(buyerUserId)
		state.skillBooks = state.skillBooks or {}
		table.insert(state.skillBooks, listingData.itemId)
		SaveService.markPlayerDirty(buyerUserId)
		
		local clientData = SkillService.getClientSkillData(buyerUserId)
		NetController.FireClient(player, "Skill.Data.Updated", clientData)
	else
		InventoryService.addItem(buyerUserId, listingData.itemId, listingData.count, listingData.durability, listingData.attributes)
	end
	
	-- 7. 판매자에게 대금 적립 (오프라인 정산소 지원)
	updatePendingGold(listingData.sellerId, totalPrice, listingData.itemId, listingData.count, listingData.pricePerUnit)
	
	print(string.format("[AuctionService] User %s bought %d %s (ListingID: %s) from seller %d for total %d gold", player.Name, listingData.count, listingData.itemId, listingId, listingData.sellerId, totalPrice))
	
	return { success = true }
end

-- 4. 매물 판매 취소
function AuctionService.cancelSale(player, payload)
	local userId = player.UserId
	local listingId = payload.listingId
	
	if not listingId then
		return { success = false, errorCode = "INVALID_PARAMETERS" }
	end
	
	-- 1. 인벤토리 공간 검증
	-- (취소 시 아이템이 다시 돌려받게 되므로 인벤토리에 들어갈 자리가 있어야 함)
	local successGet, listing = pcall(function()
		return sortedMap:GetAsync(listingId)
	end)
	
	if not successGet or not listing then
		return { success = false, errorCode = "ITEM_NOT_FOUND" }
	end
	
	if listing.sellerId ~= userId then
		return { success = false, errorCode = "NO_PERMISSION" }
	end
	
	local itemData = DataHelper.GetData("ItemData", listing.itemId)
	local isSellerSkillBook = (itemData and itemData.type == "SKILL_BOOK") or (string.sub(listing.itemId, 1, 5) == "BOOK_")
	if not isSellerSkillBook then
		if not InventoryService.canAdd(userId, listing.itemId, listing.count) then
			return { success = false, errorCode = "INVENTORY_FULL" }
		end
	end
	
	-- 2. 원자적 키 획득 (중복 방지 락 핵심)
	local isCancelled = false
	local listingData = nil
	
	local successUpdate, errUpdate = pcall(function()
		sortedMap:UpdateAsync(listingId, function(oldValue)
			if oldValue and oldValue.sellerId == userId and not oldValue.isSold and not oldValue.isCancelled then
				listingData = oldValue
				isCancelled = true
				
				-- 취소 상태로 마킹하여 업데이트 (중복 취소 방지 락)
				local newValue = {}
				for k, v in pairs(oldValue) do newValue[k] = v end
				newValue.isCancelled = true
				return newValue
			end
			return oldValue
		end, LISTING_EXPIRY)
	end)
	
	if not successUpdate or not isCancelled or not listingData then
		return { success = false, errorCode = "ALREADY_SOLD_OR_EXPIRED" }
	end
	
	-- 물리적으로 메모리 스토어에서 매물 삭제
	pcall(function()
		sortedMap:RemoveAsync(listingId)
	end)
	
	-- 3. 판매자에게 아이템 환수 (스킬북 처리)
	local itemData = DataHelper.GetData("ItemData", listingData.itemId)
	local isSellerSkillBook = (itemData and itemData.type == "SKILL_BOOK") or (string.sub(listingData.itemId, 1, 5) == "BOOK_")
	if isSellerSkillBook then
		local state = SaveService.getPlayerState(userId)
		state.skillBooks = state.skillBooks or {}
		table.insert(state.skillBooks, listingData.itemId)
		SaveService.markPlayerDirty(userId)
		
		local clientData = SkillService.getClientSkillData(userId)
		NetController.FireClient(player, "Skill.Data.Updated", clientData)
	else
		InventoryService.addItem(userId, listingData.itemId, listingData.count, listingData.durability, listingData.attributes)
	end
	
	print(string.format("[AuctionService] User %s cancelled listing %s and reclaimed %d %s", player.Name, listingId, listingData.count, listingData.itemId))
	
	return { success = true }
end

-- 5. 정산 대금 조회
function AuctionService.getPending(player, payload)
	local userId = player.UserId
	local key = "PENDING_GOLD_" .. tostring(userId)
	
	local success, data = DataStoreClient.get(key)
	if not success then
		return { success = true, gold = 0, history = {} }
	end
	
	data = data or { gold = 0, history = {} }
	return { success = true, gold = data.gold or 0, history = data.history or {} }
end

-- 6. 정산 대금 수령
function AuctionService.claimPending(player, payload)
	local userId = player.UserId
	local key = "PENDING_GOLD_" .. tostring(userId)
	
	local claimedGold = 0
	local success, result = DataStoreClient.update(key, function(oldData)
		if not oldData or (oldData.gold or 0) <= 0 then
			return oldData
		end
		
		claimedGold = oldData.gold
		oldData.gold = 0
		return oldData
	end)
	
	if not success or claimedGold <= 0 then
		return { success = false, errorCode = "NO_PENDING_GOLD" }
	end
	
	-- 지갑에 골드 추가
	NPCShopService.addGold(userId, claimedGold)
	
	print(string.format("[AuctionService] User %s claimed pending gold: %d gold", player.Name, claimedGold))
	
	return { success = true, claimedGold = claimedGold }
end

function AuctionService.GetHandlers()
	return {
		["Auction.GetListings.Request"] = function(player, payload)
			return AuctionService.getListings(player, payload)
		end,
		["Auction.RegisterSale.Request"] = function(player, payload)
			return AuctionService.registerSale(player, payload)
		end,
		["Auction.BuyItem.Request"] = function(player, payload)
			return AuctionService.buyItem(player, payload)
		end,
		["Auction.CancelSale.Request"] = function(player, payload)
			return AuctionService.cancelSale(player, payload)
		end,
		["Auction.GetPending.Request"] = function(player, payload)
			return AuctionService.getPending(player, payload)
		end,
		["Auction.ClaimPending.Request"] = function(player, payload)
			return AuctionService.claimPending(player, payload)
		end,
	}
end

return AuctionService
