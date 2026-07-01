local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"):WaitForChild("Enums"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local ProductConfig = require(Shared:WaitForChild("Config"):WaitForChild("ProductConfig"))
local DataHelper = require(Shared:WaitForChild("Util"):WaitForChild("DataHelper"))

local Client = script.Parent
local NetClient = require(Client:WaitForChild("NetClient"))
local InputManager = require(Client:WaitForChild("InputManager"))
local LocaleService = require(Client:WaitForChild("Localization"):WaitForChild("LocaleService"))
local UILocalizer = require(Client:WaitForChild("Localization"):WaitForChild("UILocalizer"))

local Controllers = Client:WaitForChild("Controllers")
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local ShopController = require(Controllers:WaitForChild("ShopController"))
local StorageController = require(Controllers:WaitForChild("StorageController"))
local TimeController = require(Controllers:WaitForChild("TimeController"))
local DragDropController = require(Controllers:WaitForChild("DragDropController"))
local InteractController = require(Controllers:WaitForChild("InteractController"))
local SkillController = require(Controllers:WaitForChild("SkillController"))

local NavigationController = require(Controllers:WaitForChild("NavigationController"))

-- UI Modules
local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("UITheme"))
local Utils = require(UI:WaitForChild("UIUtils"))
local HUDUI = require(UI:WaitForChild("HUDUI"))
local InventoryUI = require(UI:WaitForChild("InventoryUI"))
local CraftingUI = require(UI:WaitForChild("CraftingUI"))
local ShopUI = require(UI:WaitForChild("ShopUI"))
local InteractUI = require(UI:WaitForChild("InteractUI"))
local EquipmentUI = require(UI:WaitForChild("EquipmentUI"))
local StorageUI = require(UI:WaitForChild("StorageUI"))
local MaterialSelectUI = require(UI:WaitForChild("MaterialSelectUI"))
local PremiumShopUI = require(UI:WaitForChild("PremiumShopUI"))

local SkillTreeUI = require(UI:WaitForChild("SkillTreeUI"))
local PromptUI = require(UI:WaitForChild("PromptUI"))
local PortalUI = require(UI:WaitForChild("PortalUI"))
local PortalRadialUI = require(UI:WaitForChild("PortalRadialUI"))
local EnhanceUI = require(UI:WaitForChild("EnhanceUI"))
local NPCRadialUI = require(UI:WaitForChild("NPCRadialUI"))
local TentUI = require(UI:WaitForChild("TentUI"))
local DismantleUI = require(UI:WaitForChild("DismantleUI"))
local AuctionUI = require(UI:WaitForChild("AuctionUI"))

local WindowManager = require(Client:WaitForChild("Utils"):WaitForChild("WindowManager"))

local UIManager = {}

-- State
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local initialized = false
local isMobile = UserInputService.TouchEnabled
local mainGui = nil
local blurEffect = nil
local activeShopId = nil
local currentStorageData = nil
local hoveredStorageSlotInfo = nil
local selectedPersonalRecipeId = nil
local cachedPersonalRecipes = nil
local personalCraftNodes = {}
-- (Building state removed)
local pendingStats = {}
local cachedStats = {}
local STARTER_PACK_PRODUCT_ID = "3602119011"

-- Constants
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local WEAPON_CRAFTER_RECIPE_ORDER = {
	"CraftSoftClub",          -- 슬라임검
	"CraftGakchang",          -- 단단한 검
	"CraftMogwoldo",          -- 숲의 검
	"CraftPoisonHornSpear",   -- 숲의 밤
	"CraftKatana",            -- 카타나
	"CraftIronStaff",         -- 철검
	"CraftFangSpear",         -- 뱀파이어 소드
	"CraftIceSword",          -- 아이스 소드
	-- 하늘섬 티어
	"CraftKnightSword",
	"CraftSoulSword",
	"CraftSwordOfJustice",
	"CraftBlueFlameSword",
}

local function collectWeaponCrafterRecipes(recipeData)
	local recipeById = {}
	local ordered = {}
	for _, recipe in ipairs(recipeData or {}) do
		if recipe and recipe.id then
			recipeById[recipe.id] = recipe
		end
	end
	for _, recipeId in ipairs(WEAPON_CRAFTER_RECIPE_ORDER) do
		local recipe = recipeById[recipeId]
		if recipe then
			table.insert(ordered, recipe)
		end
	end
	return ordered
end

--========================================
-- UI Handlers
--========================================
function UIManager._onOpenInventory()
	InventoryUI.SetVisible(true)
	InventoryUI.Refresh()
end

function UIManager._onCloseInventory()
	InventoryUI.SetVisible(false)
end

function UIManager._onOpenSkillTree()
	SkillTreeUI.SetVisible(true)
	SkillTreeUI.Refresh()
end

function UIManager._onCloseSkillTree()
	SkillTreeUI.SetVisible(false)
end

function UIManager._onOpenShop()
	ShopUI.SetVisible(true)
end

function UIManager._onCloseShop()
	ShopUI.SetVisible(false)
end

function UIManager._onOpenStorage()
	StorageUI.SetVisible(true)
end

function UIManager._onCloseStorage()
	StorageUI.SetVisible(false)
end

function UIManager._onOpenMaterialSelect()
	MaterialSelectUI.SetVisible(true)
end

function UIManager._onCloseMaterialSelect()
	MaterialSelectUI.SetVisible(false)
end

function UIManager._onOpenPremiumShop()
	PremiumShopUI.SetVisible(true)
end

function UIManager._onClosePremiumShop()
	PremiumShopUI.SetVisible(false)
end

function UIManager._onOpenEnhance()
	EnhanceUI.SetVisible(true)
	EnhanceUI.Refresh()
end

function UIManager._onCloseEnhance()
	EnhanceUI.SetVisible(false)
end

function UIManager.openEnhance()
	WindowManager.open("ENHANCE")
end

function UIManager.closeEnhance()
	WindowManager.close("ENHANCE")
end

function UIManager.requestTutorialStepComplete()
	task.spawn(function()
		local ok, data = NetClient.Request("Tutorial.Step.Complete.Request", {})
		if ok and data then
			UIManager.updateTutorialStatus(data)
		end
	end)
end

function UIManager.requestQuestStepComplete()
	UIManager.requestTutorialStepComplete()
end

-- 사이드퀘스트 통합 패널 (HUDUI에 위임)
function UIManager.updateSideQuest(id, data)
	if HUDUI and HUDUI.UpdateSideQuest then
		HUDUI.UpdateSideQuest(id, data)
	end
end

function UIManager.removeSideQuest(id)
	if HUDUI and HUDUI.RemoveSideQuest then
		HUDUI.RemoveSideQuest(id)
	end
end

function UIManager._onOpenDismantle()
	DismantleUI.SetVisible(true)
	DismantleUI.Refresh()
end

function UIManager._onCloseDismantle()
	DismantleUI.SetVisible(false)
end

function UIManager.openDismantle()
	WindowManager.open("DISMANTLE")
end

function UIManager.closeDismantle()
	WindowManager.close("DISMANTLE")
end

function UIManager.openPortalRadial(data)
	WindowManager.open("PORTAL_RADIAL", data)
end

function UIManager.closePortalRadial()
	WindowManager.close("PORTAL_RADIAL")
end


-- Signals for Internal Use
local menuOpenedEvent = Instance.new("BindableEvent")
UIManager.OnMenuOpened = menuOpenedEvent.Event
local inventoryOpenedEvent = Instance.new("BindableEvent")
UIManager.OnInventoryOpened = inventoryOpenedEvent.Event

function UIManager.fireMenuOpened() menuOpenedEvent:Fire() end
function UIManager.fireInventoryOpened() inventoryOpenedEvent:Fire() end

function UIManager.getInventorySlot(slot)
	if slot == "HAND" then
		return InventoryController.getEquipment().HAND
	end
	local cache = InventoryController.getInventoryCache()
	return cache[slot]
end

function UIManager.getEquipment()
	return InventoryController.getEquipment()
end

local ERROR_MESSAGES = {
	BAD_REQUEST = "잘못된 요청입니다.",
	NOT_FOUND = "대상을 찾을 수 없습니다.",
	INVALID_STATE = "현재 상태에서는 수행할 수 없습니다.",
	OUT_OF_RANGE = "대상과 거리가 너무 멉니다. 더 가까이 이동하세요.",
	COOLDOWN = "재사용 대기 중입니다.",
	UNKNOWN = "알 수 없는 오류가 발생했습니다.",
	UNKNOWN_ERROR = "알 수 없는 오류가 발생했습니다.",
	NOT_ENOUGH_STAMINA = "마나가 부족합니다.",
	PLAYER_DEAD = "사용할 수 없는 상태입니다.",
	INV_FULL = "인벤토리가 가득 찼습니다.",
	INVENTORY_FULL = "인벤토리가 가득 찼습니다.",
	NO_ITEM = "재료가 부족합니다.",
	CRAFT_NOT_FOUND = "제작법을 찾을 수 없습니다.",
	NODE_NOT_FOUND = "채집 대상을 찾을 수 없습니다.",
	NO_PERMISSION = "토템 보호가 활성화된 시설입니다.",
	INSUFFICIENT_GOLD = "골드가 부족합니다.",
	TOTEM_NOT_OWNER = "소유한 토템에서만 유지비를 결제할 수 있습니다.",
	TOTEM_NOT_FOUND = "토템을 찾을 수 없습니다.",
	INVALID_COUNT = "결제 기간이 올바르지 않습니다.",
	INSUFFICIENT_STAT_POINTS = "스탯 포인트가 부족합니다.",
	
	-- 상점 관련 에러 메시지
	ITEM_NOT_SELLABLE = "판매할 수 없는 아이템입니다.",
	ITEM_NOT_IN_SHOP = "상점에서 취급하지 않는 아이템입니다.",
	SHOP_NOT_FOUND = "상점을 찾을 수 없습니다.",
	SHOP_OUT_OF_STOCK = "상점 재고가 부족합니다.",
	SHOP_TOO_FAR = "상점과 거리가 너무 멉니다.",
	LEVEL_NOT_MET = "요구 레벨이 부족합니다.",
	GOLD_CAP_REACHED = "골드 보유 한도를 초과할 수 없습니다.",
}

local function friendlyError(errCode)
	local code = tostring(errCode or "UNKNOWN")
	local msg = ERROR_MESSAGES[code]
	if msg then return msg end
	warn("[UIManager] Unmapped error code:", code)
	return "요청을 처리할 수 없습니다. 잠시 후 다시 시도하세요."
end
local activeDebuffs = {} -- { [debuffId] = {id, name, startTime, duration} }

--========================================
-- UI Management Helpers
--========================================
local function updateUIMode()
	local anyOpen = WindowManager.isAnyOpen()
	local hasFullWindow = WindowManager.hasFullWindowOpen()
	
	InputManager.setUIOpen(anyOpen)
	
	-- 전체 화면 창(인벤토리 등)이 열릴 때만 메인 HUD를 숨김
	HUDUI.SetVisible(not hasFullWindow)
	
	-- 블러 효과 및 마우스 잠금 제어
	if blurEffect then
		blurEffect.Enabled = anyOpen
	end
	
	if anyOpen then
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	else
		-- UI가 모두 닫히면 게임 월드 조작 모드로 복귀 (필요시 InteractController에서 추가 처리)
	end
end
UIManager.updateUIMode = updateUIMode

function UIManager.toggleInventory() WindowManager.toggle("INV") end
function UIManager.toggleSkillTree() WindowManager.toggle("SKILL") end
function UIManager.toggleRuneSystem() WindowManager.toggle("SKILL") end

function UIManager._setMainHUDVisible(visible)
	HUDUI.SetVisible(visible)
end

-- Harvest progress
local harvestFrame, harvestBar, harvestPctLabel, harvestNameLabel

-- Combat State
local currentCombatCreatureId = nil

-- Inventory
local invSlots = {}
local invDetailPanel
local selectedInvSlot = nil
local categoryButtons = {}

-- Crafting / Building
local craftNodes = {}
local selectedRecipeId = nil
local craftDetailPanel
local equipmentUIFrame

function UIManager.updateHealth(cur, max) HUDUI.UpdateHealth(cur, max) end
function UIManager.updateStamina(cur, max) HUDUI.UpdateStamina(cur, max) end
function UIManager.updateXP(cur, max) HUDUI.UpdateXP(cur, max) end
function UIManager.updateLevel(lvl)
	HUDUI.UpdateLevel(lvl)
	if UIManager.refreshStarterPackButton then
		UIManager.refreshStarterPackButton()
	end
end
function UIManager.updateStatPoints(pts) HUDUI.UpdateStatPoints(pts) end
function UIManager.setTutorialVisible(visible) HUDUI.SetTutorialVisible(visible) end

local blinkingActive = false
local blinkThread = nil

function UIManager.updateTutorialBlinking(status)
	local stepKey = status and status.stepKey
	
	local isProgressDone = false
	if status and status.progress then
		local count = status.progress.count or 0
		local stepCount = status.stepCount or 1
		isProgressDone = status.progress.done or (count >= stepCount)
	end
	
	local isDistributeStat = (stepKey == "DISTRIBUTE_STAT") and not isProgressDone
	local isEquipSoftClub = (stepKey == "EQUIP_SOFTCLUB") and not isProgressDone
	local isEquipDash = (stepKey == "EQUIP_DASH") and not isProgressDone
	
	if not isDistributeStat and not isEquipSoftClub and not isEquipDash then
		blinkingActive = false
		if blinkThread then
			task.cancel(blinkThread)
			blinkThread = nil
		end
		local eqTab = HUDUI.Refs.EquipTabButton
		if eqTab then
			eqTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			eqTab.BackgroundTransparency = 0.3
		end
		local invTab = HUDUI.Refs.InventoryTabButton
		if invTab then
			invTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			invTab.BackgroundTransparency = 0.3
		end
		local skillTab = HUDUI.Refs.SkillTabButton
		if skillTab then
			skillTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			skillTab.BackgroundTransparency = 0.3
		end
		local atkBtn = EquipmentUI.Refs.StatLines and EquipmentUI.Refs.StatLines[Enums.StatId.ATTACK] and EquipmentUI.Refs.StatLines[Enums.StatId.ATTACK].btn
		if atkBtn then
			atkBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
		end
		local applyBtn = EquipmentUI.Refs.ApplyBtn
		if applyBtn then
			applyBtn.BackgroundColor3 = Color3.fromRGB(90, 210, 90)
		end
		if InventoryUI.Refs.Slots then
			for _, slot in pairs(InventoryUI.Refs.Slots) do
				if slot and slot.frame then
					slot.frame.BackgroundColor3 = Color3.fromRGB(15, 20, 35)
				end
			end
		end
		return
	end
	
	if blinkThread then
		task.cancel(blinkThread)
		blinkThread = nil
	end
	
	blinkingActive = true
	
	blinkThread = task.spawn(function()
		local isHighlight = false
		while blinkingActive do
			local eqTab = HUDUI.Refs.EquipTabButton
			local invTab = HUDUI.Refs.InventoryTabButton
			
			if isDistributeStat then
				local atkBtn = EquipmentUI.Refs.StatLines and EquipmentUI.Refs.StatLines[Enums.StatId.ATTACK] and EquipmentUI.Refs.StatLines[Enums.StatId.ATTACK].btn
				local applyBtn = EquipmentUI.Refs.ApplyBtn
				local isEquipOpen = WindowManager.isOpen("EQUIP")
				
				if invTab then
					invTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
					invTab.BackgroundTransparency = 0.3
				end
				
				if isEquipOpen then
					if eqTab then
						eqTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
						eqTab.BackgroundTransparency = 0.3
					end
					
					local hasPendingAtk = (UIManager.getPendingStatCount(Enums.StatId.ATTACK) > 0)
					if hasPendingAtk then
						if atkBtn then
							atkBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
						end
						if applyBtn then
							applyBtn.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(90, 210, 90)
						end
					else
						if applyBtn then
							applyBtn.BackgroundColor3 = Color3.fromRGB(90, 210, 90)
						end
						if atkBtn then
							atkBtn.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(40, 80, 160)
						end
					end
				else
					if atkBtn then
						atkBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
					end
					if applyBtn then
						applyBtn.BackgroundColor3 = Color3.fromRGB(90, 210, 90)
					end
					if eqTab then
						eqTab.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(28, 28, 28)
						eqTab.BackgroundTransparency = isHighlight and 0.25 or 0.3
					end
				end
				
			elseif isEquipSoftClub then
				local isInvOpen = WindowManager.isOpen("INV")
				
				if eqTab then
					eqTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
					eqTab.BackgroundTransparency = 0.3
				end
				
				if isInvOpen then
					if invTab then
						invTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
						invTab.BackgroundTransparency = 0.3
					end
					
					local targetSlotIndex = nil
					local cache = InventoryController.getInventoryCache()
					for slotIndex, itemData in pairs(cache) do
						if itemData and itemData.itemId == "SoftClub" then
							targetSlotIndex = slotIndex
							break
						end
					end
					
					if InventoryUI.Refs.Slots then
						for i, slot in pairs(InventoryUI.Refs.Slots) do
							if slot and slot.frame then
								if i == targetSlotIndex then
									slot.frame.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(15, 20, 35)
								else
									slot.frame.BackgroundColor3 = Color3.fromRGB(15, 20, 35)
								end
							end
						end
					end
				else
					if InventoryUI.Refs.Slots then
						for _, slot in pairs(InventoryUI.Refs.Slots) do
							if slot and slot.frame then
								slot.frame.BackgroundColor3 = Color3.fromRGB(15, 20, 35)
							end
						end
					end
					
					if invTab then
						invTab.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(28, 28, 28)
						invTab.BackgroundTransparency = isHighlight and 0.25 or 0.3
					end
				end
			elseif isEquipDash then
				local isSkillOpen = WindowManager.isOpen("SKILL")
				local skillTab = HUDUI.Refs.SkillTabButton
				
				if isSkillOpen then
					if skillTab then
						skillTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
						skillTab.BackgroundTransparency = 0.3
					end
					
					local hasDashUnlocked = false
					if SkillController and SkillController.getUnlockedSkills then
						hasDashUnlocked = SkillController.getUnlockedSkills()["SKILL_RUNE_DASH"] == true
					end
					
					local uiBookTabBtn = SkillTreeUI.Refs.BookTabBtn
					local uiSkillTabBtn = SkillTreeUI.Refs.SkillTabBtn
					local bookTabContent = SkillTreeUI.Refs.BookTabContent
					local skillTabContent = SkillTreeUI.Refs.SkillTabContent
					
					-- Reset all highlights first
					if uiBookTabBtn then uiBookTabBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 60) end
					if uiSkillTabBtn then uiSkillTabBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 60) end
					
					if not hasDashUnlocked then
						-- Highlight BookTabBtn if they are not in the book tab
						if bookTabContent and not bookTabContent.Visible then
							if uiBookTabBtn then
								uiBookTabBtn.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(45, 50, 60)
							end
						else
							-- In book tab, highlight the book list item if it exists, or the learn button if selected
							local bookList = SkillTreeUI.Refs.BookList
							local learnBtn = SkillTreeUI.Refs.BookDetail and SkillTreeUI.Refs.BookDetail:FindFirstChild("LearnBtn")
							local isSelected = SkillTreeUI.GetSelectedBookId and SkillTreeUI.GetSelectedBookId() == "BOOK_DASH"
							
							if isSelected then
								if learnBtn and learnBtn.Visible then
									learnBtn.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(90, 210, 90)
								end
							else
								if bookList then
									local dashBookUI = bookList:FindFirstChild("BOOK_DASH")
									if dashBookUI then
										dashBookUI.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(25, 30, 45)
									end
								end
							end
						end
					else
						-- Dash is unlocked, they need to equip it
						if skillTabContent and not skillTabContent.Visible then
							if uiSkillTabBtn then
								uiSkillTabBtn.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(45, 50, 60)
							end
						else
							-- In skill tab, highlight the passive skill and equip button
							local passiveList = SkillTreeUI.Refs.PassiveList
							if passiveList then
								local dashPassiveUI = passiveList:FindFirstChild("SKILL_RUNE_DASH")
								if dashPassiveUI then
									local btnContainer = dashPassiveUI:FindFirstChild("BtnContainer")
									local equipBtn = btnContainer and btnContainer:FindFirstChild("EquipBtn")
									if equipBtn and equipBtn.Visible then
										equipBtn.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(90, 210, 90)
									else
										dashPassiveUI.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(25, 30, 45)
									end
								end
							end
						end
					end
				else
					if skillTab then
						skillTab.BackgroundColor3 = isHighlight and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(28, 28, 28)
						skillTab.BackgroundTransparency = isHighlight and 0.25 or 0.3
					end
				end
			end
			
			isHighlight = not isHighlight
			task.wait(0.4)
		end
		
		-- Reset on stop
		local eqTab = HUDUI.Refs.EquipTabButton
		if eqTab then
			eqTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			eqTab.BackgroundTransparency = 0.3
		end
		local invTab = HUDUI.Refs.InventoryTabButton
		if invTab then
			invTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			invTab.BackgroundTransparency = 0.3
		end
		local skillTab = HUDUI.Refs.SkillTabButton
		if skillTab then
			skillTab.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			skillTab.BackgroundTransparency = 0.3
		end
		if SkillTreeUI and SkillTreeUI.Refs then
			local uiBookTabBtn = SkillTreeUI.Refs.BookTabBtn
			local uiSkillTabBtn = SkillTreeUI.Refs.SkillTabBtn
			if uiBookTabBtn then uiBookTabBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 60) end
			if uiSkillTabBtn then uiSkillTabBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 60) end
			
			local bookList = SkillTreeUI.Refs.BookList
			if bookList then
				local dashBookUI = bookList:FindFirstChild("BOOK_DASH")
				if dashBookUI then dashBookUI.BackgroundColor3 = Color3.fromRGB(25, 30, 45) end
			end
			local learnBtn = SkillTreeUI.Refs.BookDetail and SkillTreeUI.Refs.BookDetail:FindFirstChild("LearnBtn")
			if learnBtn then learnBtn.BackgroundColor3 = Color3.fromRGB(90, 210, 90) end
			
			local passiveList = SkillTreeUI.Refs.PassiveList
			if passiveList then
				local dashPassiveUI = passiveList:FindFirstChild("SKILL_RUNE_DASH")
				if dashPassiveUI then
					dashPassiveUI.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
					local btnContainer = dashPassiveUI:FindFirstChild("BtnContainer")
					local equipBtn = btnContainer and btnContainer:FindFirstChild("EquipBtn")
					if equipBtn then equipBtn.BackgroundColor3 = Color3.fromRGB(90, 210, 90) end
				end
			end
		end
		local atkBtn = EquipmentUI.Refs.StatLines and EquipmentUI.Refs.StatLines[Enums.StatId.ATTACK] and EquipmentUI.Refs.StatLines[Enums.StatId.ATTACK].btn
		if atkBtn then
			atkBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
		end
		local applyBtn = EquipmentUI.Refs.ApplyBtn
		if applyBtn then
			applyBtn.BackgroundColor3 = Color3.fromRGB(90, 210, 90)
		end
		if InventoryUI.Refs.Slots then
			for _, slot in pairs(InventoryUI.Refs.Slots) do
				if slot and slot.frame then
					slot.frame.BackgroundColor3 = Color3.fromRGB(15, 20, 35)
				end
			end
		end
	end)
end

function UIManager.updateTutorialStatus(status)
	HUDUI.UpdateTutorialStatus(status)
	NavigationController.UpdateTutorialStatus(status)
	UIManager.updateTutorialBlinking(status)
end

function UIManager.getPendingStatCount(statId)
	return pendingStats[statId] or 0
end

-- refreshStats는 하단에 isEquipmentOpen 가드와 함께 올바르게 정의됩니다.

function UIManager.addPendingStat(statId)
	local available = (cachedStats and cachedStats.statPointsAvailable or 0)
	local currentTotalPending = 0
	for _, v in pairs(pendingStats) do currentTotalPending = currentTotalPending + (v or 0) end
	
	-- 인벤토리 칸 스탯: 120칸 상한 검사
	if statId == Enums.StatId.INV_SLOTS then
		local calc = cachedStats and cachedStats.calculated or {}
		local currentMaxSlots = calc.maxSlots or Balance.BASE_INV_SLOTS
		local pendingSlots = (pendingStats[Enums.StatId.INV_SLOTS] or 0) * Balance.SLOTS_PER_POINT
		if currentMaxSlots + pendingSlots >= Balance.MAX_INV_SLOTS then
			UIManager.notify("인벤토리 최대 칸수(" .. Balance.MAX_INV_SLOTS .. "칸)에 도달했습니다.", C.RED)
			return
		end
	end
	
	if currentTotalPending < available then
		pendingStats[statId] = (pendingStats[statId] or 0) + 1
		UIManager.refreshStats()
	else
		UIManager.notify("강화 포인트가 부족합니다.", C.RED)
	end
end

function UIManager.cancelPendingStats()
	pendingStats = {}
	UIManager.refreshStats()
end

function UIManager.confirmPendingStats()
	local total = 0
	for _, v in pairs(pendingStats) do total = total + v end
	if total <= 0 then return end
	
	task.spawn(function()
		local ok, data = NetClient.Request("Player.Stats.Upgrade.Request", {stats = pendingStats})
		if ok then
			pendingStats = {}
			UIManager.refreshStats()
			-- cachedStats는 Player.Stats.Changed 이벤트로 업데이트됨
		else
			UIManager.notify(friendlyError(data, "강화"), C.RED)
		end
	end)
end

function UIManager.resetAllStats()
	-- 투자된 스탯이 하나라도 있는지 확인
	local invested = cachedStats and cachedStats.statInvested
	if not invested then
		UIManager.notify("초기화할 스탯이 없습니다.", C.RED)
		return
	end
	local totalInvested = 0
	for _, v in pairs(invested) do totalInvested = totalInvested + (v or 0) end
	if totalInvested <= 0 then
		UIManager.notify("초기화할 스탯이 없습니다.", C.RED)
		return
	end
	
	-- 보류 중인 강화 취소
	pendingStats = {}
	
	task.spawn(function()
		local ok, data = NetClient.Request("Player.Stats.Reset.Request", {})
		if ok then
			local refunded = data and data.refunded or 0
			local dropped = data and data.droppedCount or 0
			UIManager.notify(string.format("스탯 초기화 완료! %d 포인트 환급", refunded), C.GREEN)
			if dropped > 0 then
				UIManager.notify(string.format("초과 아이템 %d종이 발 밑에 드랍되었습니다.", dropped), C.GOLD)
			end
			UIManager.refreshStats()
			UIManager.refreshInventory()
		else
			if data == "NO_ITEM" or (type(data) == "table" and data.errorCode == "NO_ITEM") then
				UIManager.notify("스텟초기화권이 필요합니다.", C.RED)
				return
			end
			UIManager.notify(friendlyError(data, "스탯 초기화"), C.RED)
		end
	end)
end
----------------------------------------------------------------
-- Public API: Equipment (장비창)
----------------------------------------------------------------
function UIManager.openEquipment()
	WindowManager.open("EQUIP")
end

function UIManager._onOpenEquipment()
	-- UI 상태 즉시 반영
	EquipmentUI.SetVisible(true)
	updateUIMode()
	EquipmentUI.UpdateCharacterPreview(player.Character)
	
	-- 데이터 최신화 요청 (백그라운드)
	task.spawn(function()
		local ok, d = NetClient.Request("Player.Stats.Request", {})
		if ok and d then cachedStats = d end
		
		local equipmentData = InventoryController.getEquipment and InventoryController.getEquipment() or {}
		UIManager.refreshStats() 
	end)

	if HUDUI and HUDUI.LastStatus then
		UIManager.updateTutorialBlinking(HUDUI.LastStatus)
	end
end

function UIManager.closeEquipment()
	WindowManager.close("EQUIP")
end

function UIManager._onCloseEquipment()
	EquipmentUI.SetVisible(false)
	if HUDUI and HUDUI.LastStatus then
		UIManager.updateTutorialBlinking(HUDUI.LastStatus)
	end
end

function UIManager.toggleEquipment()
	WindowManager.toggle("EQUIP")
	UIManager.fireInventoryOpened()
end
----------------------------------------------------------------
-- Public API: Settings/Etc 
----------------------------------------------------------------

-- Personal Crafting
local invPersonalCraftGrid = nil
local invCraftContainer = nil
local personalCraftNodes = {}
local selectedPersonalRecipeId = nil
local bagTabBtn, craftTabBtn

-- Notification State
local notifyQueue = {}
local sideNotifyStack = {} -- [frame] = { startTime, label }
local sideNotifyContainer = nil

-- Drag & Drop
local DRAG_THRESHOLD = 5 -- Lower threshold for easier dragging
local pendingDragIdx = nil
local draggingSlotIdx = nil
local dragStartPos = Vector2.zero
local dragDummy = nil

local cachedPersonalRecipes = nil

----------------------------------------------------------------
-- UI Helpers (Module Aliases)
----------------------------------------------------------------
local mkFrame = Utils.mkFrame
local mkLabel = Utils.mkLabel
local mkBtn   = Utils.mkBtn
local mkSlot  = Utils.mkSlot
local mkBar   = Utils.mkBar

function UIManager.upgradeStat(statId)
	UIManager.addPendingStat(statId)
end

function UIManager.updateStatPoints(available)
	HUDUI.SetStatPointAlert(available)
end

function UIManager.updateGold(amt)
	InventoryUI.UpdateCurrency(amt)
	ShopUI.UpdateGold(amt)
	if HUDUI.UpdateGold then HUDUI.UpdateGold(amt) end
end

----------------------------------------------------------------
-- Public API: Hotbar
----------------------------------------------------------------
function UIManager.selectHotbarSlot(idx, skipSync)
	selectedSlot = idx
	HUDUI.SelectHotbarSlot(idx, skipSync, UIManager, C)

	if not skipSync then
		InventoryController.requestSetActiveSlot(idx)
	end
end

function UIManager.getSelectedSlot()
	return selectedSlot
end

local ICON_FOLDERS = {}
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("Assets", 5)
	if assets then
		local folderNames = {"UI", "ItemIcons", "UIIcons", "Images", "Icons"}
		for _, name in ipairs(folderNames) do
			local f = assets:FindFirstChild(name)
			if f then
				table.insert(ICON_FOLDERS, f)
			end
		end
	end
	
	-- 아이콘 폴더가 로드되면 UI를 한 번 새로고침 해줍니다.
	if UIManager.refreshInventory then
		task.wait(0.5)
		UIManager.refreshInventory()
		UIManager.refreshHotbar()
	end
end)

-- 아이템 아이콘 가져오기 (폴더 검색 우선, 데이터 폴백)
local function getItemIcon(itemId: string): string
	if not itemId then return "" end
	
	local itemDataRef = DataHelper and DataHelper.GetData("ItemData", itemId)
	local searchCandidates = {}
	local function pushCandidate(value)
		if type(value) ~= "string" or value == "" then
			return
		end
		for _, existing in ipairs(searchCandidates) do
			if existing == value then
				return
			end
		end
		table.insert(searchCandidates, value)
	end

	pushCandidate(itemDataRef and itemDataRef.iconName)
	pushCandidate(itemDataRef and itemDataRef.modelName)
	pushCandidate(itemId)

	-- 1. 로드된 아이콘 폴더들에서 검색
	for _, folder in ipairs(ICON_FOLDERS) do
		local iconObj = nil
		for _, candidate in ipairs(searchCandidates) do
			iconObj = folder:FindFirstChild(candidate, true)
			if iconObj then
				break
			end
		end
		
		if iconObj then
			local result = nil
			if iconObj:IsA("Decal") or iconObj:IsA("Texture") then
				result = iconObj.Texture
			elseif iconObj:IsA("ImageLabel") or iconObj:IsA("ImageButton") then
				result = iconObj.Image
			elseif iconObj:IsA("StringValue") then
				result = iconObj.Value
			end
			if result and result ~= "" and result ~= "rbxassetid://0" and result ~= "0" then
				return result
			end
		end
	end

	if itemDataRef and itemDataRef.icon and itemDataRef.icon ~= "" and itemDataRef.icon ~= "rbxassetid://0" and itemDataRef.icon ~= "0" then
		return itemDataRef.icon
	end

	-- 아이콘이 아예 지정되지 않았거나 에셋 폴더에 누락된 경우 기본 돌 모양 아이콘("rbxassetid://13515086700")을 폴백으로 노출하여 투명 증발을 방지합니다.
	return "rbxassetid://13515086700"
end
UIManager.getItemIcon = getItemIcon

function UIManager.refreshHotbar()
	local items = InventoryController.getItems()
	for i=1,8 do
		local s = hotbarSlots and hotbarSlots[i]
		if s then
			local item = items[i]
			if item and item.itemId then
				local icon = getItemIcon(item.itemId)
				s.icon.Image = icon
				s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
				s.icon.Visible = (icon ~= "")
				if s.durBg then s.durBg.Visible = false end
			else
				s.icon.Image = ""; s.countLabel.Text = ""
				if s.durBg then s.durBg.Visible = false end
			end
		end
	end
end

----------------------------------------------------------------
-- Public API: Inventory
----------------------------------------------------------------
function UIManager.openInventory(startTab)
	WindowManager.open("INV", startTab)
end

function UIManager._onOpenInventory(startTab)
	selectedInvSlot = nil 
	
	if InventoryUI and InventoryUI.RestoreDetailParent then
		InventoryUI.RestoreDetailParent()
	end 
	
	InventoryUI.SetVisible(true)
	InventoryUI.SetTab(startTab or "BAG")
	InventoryUI.UpdateCurrency(ShopController.getGold())
	ShopController.requestGold(function(ok, gold)
		if ok then
			InventoryUI.UpdateCurrency(gold)
		end
	end)
	UIManager.refreshInventory()
	if startTab == "CRAFT" then
		UIManager.refreshPersonalCrafting(true)
	end
end

function UIManager.closeInventory()
	WindowManager.close("INV")
end

function UIManager._onCloseInventory()
	if DragDropController.isDragging() then
		DragDropController.handleDragEnd()
	end
	
	InventoryUI.SetVisible(false)
	selectedInvSlot = nil
end

function UIManager.toggleInventory(startTab)
	print("[UIManager] toggleInventory called with startTab:", tostring(startTab))
	WindowManager.toggle("INV", startTab)
	UIManager.fireInventoryOpened()
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	local _, currentMaxSlots = InventoryController.getSlotInfo()
	InventoryUI.RefreshSlots(items, getItemIcon, C, DataHelper, currentMaxSlots)
	
	if selectedInvSlot and items[selectedInvSlot] then
		InventoryUI.UpdateDetail(items[selectedInvSlot], getItemIcon, Enums, DataHelper, InventoryController.getItemCounts())
	elseif selectedInvSlot == nil and WindowManager.isOpen("INV") and InventoryUI.Refs.CraftFrame and InventoryUI.Refs.CraftFrame.Visible then
		if selectedPersonalRecipeId and cachedPersonalRecipes then
			for _, r in ipairs(cachedPersonalRecipes) do
				if r.id == selectedPersonalRecipeId then
					UIManager._updatePersonalCraftDetail(r)
					break
				end
			end
		end
	else
		InventoryUI.UpdateDetail(nil) 
	end
	
	local usedSlots, maxSlots = InventoryController.getSlotInfo()
	InventoryUI.UpdateSlotInfo(usedSlots, maxSlots, C)
	
	UIManager.refreshHotbar()
end

function UIManager.sortInventory()
	local InventoryController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("InventoryController"))
	if InventoryController and InventoryController.requestSort then
		InventoryController.requestSort()
	end
end

function UIManager.refreshStats()
	local totalPending = 0
	for _, v in pairs(pendingStats) do totalPending = totalPending + v end
	
	if WindowManager.isOpen("EQUIP") then
		local equipmentData = InventoryController.getEquipment and InventoryController.getEquipment() or {}
		EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
	end

	if HUDUI and HUDUI.LastStatus then
		UIManager.updateTutorialBlinking(HUDUI.LastStatus)
	end
end

function UIManager.onEquipmentSlotClick(slotName)
	local equip = InventoryController.getEquipment()
	local item = equip[slotName]
	if item then
		local itemData = DataHelper.GetData("ItemData", item.itemId)
		if itemData then
			UIManager.notify(string.format("[%s] %s", slotName, itemData.name), C.GOLD)
		end
	end
end

function UIManager.onEquipmentSlotRightClick(slotName)
	local equip = InventoryController.getEquipment()
	if equip[slotName] then
		InventoryController.requestUnequip(slotName)
	end
end

----------------------------------------------------------------
-- [Refactor] Inventory Drag & Drop Logic (DragDropController로 이관)
----------------------------------------------------------------
function UIManager.handleDragStart(idx, input) DragDropController.handleDragStart(idx) end
function UIManager.handleDragUpdate(input) DragDropController.handleDragUpdate() end
function UIManager.handleDragEnd(input) DragDropController.handleDragEnd() end
function UIManager.isDragging() return DragDropController.isDragging() end

function UIManager.getInvSlots() return invSlots end
function UIManager.getHotbarSlots() return hotbarSlots end
function UIManager.getEquipSlots() return equipSlots end
function UIManager.isWindowOpen(winId) return WindowManager.isOpen(winId) end
function UIManager.getIsMobile() return isMobile end

local modalActionType = "DROP" -- DROP, SPLIT, DROP_GOLD

local function openCountModal(title, amount)
	local safeAmount = math.max(1, math.floor(tonumber(amount) or 1))
	local m = InventoryUI.Refs.DropModal
	m.Frame.Visible = true
	m.Input.Text = tostring(safeAmount)
	m.MaxLabel.Text = "(최대: " .. safeAmount .. ")"
	if m.Title then
		m.Title.Text = title or "수량 입력"
	end
end

function UIManager.openDropModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	modalActionType = "DROP"
	
	local totalCount = 0
	local items = InventoryController.getItems()
	for _, slotData in pairs(items) do
		if slotData and slotData.itemId == item.itemId then
			totalCount = totalCount + (slotData.count or 1)
		end
	end
	if totalCount < 1 then totalCount = 1 end
	
	openCountModal("수량 입력", totalCount)
end

function UIManager.openGoldDropModal()
	local currentGold = ShopController.getGold()
	if currentGold <= 0 then
		UIManager.notify("드랍할 골드가 없습니다.", C.RED)
		return
	end

	modalActionType = "DROP_GOLD"
	openCountModal("드랍할 골드", currentGold)
end

function UIManager.openSplitModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item or not item.count or item.count <= 1 then return end
	
	modalActionType = "SPLIT"
	
	openCountModal("수량 입력", math.floor(item.count / 2))
	InventoryUI.Refs.DropModal.MaxLabel.Text = "(최대: " .. (item.count - 1) .. ")"
end

function UIManager.getSelectedInvSlot()
	return selectedInvSlot
end

function UIManager.confirmModalAction(count)
	if modalActionType == "DROP_GOLD" then
		local currentGold = ShopController.getGold()
		local validCount = math.max(1, math.min(count, currentGold))
		InventoryController.requestDropGold(validCount)
		InventoryUI.Refs.DropModal.Frame.Visible = false
		return
	end

	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	if modalActionType == "DROP" then
		local totalCount = 0
		local items = InventoryController.getItems()
		for _, slotData in pairs(items) do
			if slotData and slotData.itemId == item.itemId then
				totalCount = totalCount + (slotData.count or 1)
			end
		end
		if totalCount < 1 then totalCount = 1 end
		
		local validCount = math.max(1, math.min(count, totalCount))
		
		local isTradeable = true
		if DataHelper and DataHelper.IsTradeable then
			isTradeable = DataHelper.IsTradeable(item.itemId)
		end
		
		if not isTradeable then
			local itemData = DataHelper.GetData("ItemData", item.itemId)
			local rawName = itemData and itemData.name or item.itemId
			local localizedName = UILocalizer.LocalizeDataText("ItemData", item.itemId, "name", rawName)
			
			UIManager.showDropConfirm({
				message = string.format("<font color='#FF5555'>%s %d개</font>는 <font color='#FFAA00'>교환 불가</font> 아이템입니다.<br/>버리면 땅에 떨어지지 않고 완전히 소멸되어 복구할 수 없습니다.<br/>정말 버리시겠습니까?", tostring(localizedName), validCount),
				onConfirm = function()
					InventoryController.requestDropByItemId(item.itemId, validCount)
				end
			})
		else
			InventoryController.requestDropByItemId(item.itemId, validCount)
		end
	elseif modalActionType == "SPLIT" then
		local maxCount = (item.count or 1) - 1
		if maxCount >= 1 then
			local validCount = math.max(1, math.min(count, maxCount))
			local emptySlot = nil
			local items = InventoryController.getItems()
			for i=1, Balance.MAX_INV_SLOTS do
				if not items[i] then emptySlot = i; break end
			end
			if emptySlot then
				task.spawn(function()
					NetClient.Request("Inventory.Split.Request", {
						fromSlot = selectedInvSlot,
						toSlot = emptySlot,
						count = validCount
					})
				end)
			else
				UIManager.notify("빈 슬롯이 없습니다.", C.RED)
			end
		end
	end
	
	InventoryUI.Refs.DropModal.Frame.Visible = false
end

function UIManager._onInvSlotClick(idx)
	if not WindowManager.isOpen("INV") then return end
	selectedInvSlot = idx
	local items = InventoryController.getItems()
	local data = items[idx]
	InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper)
	InventoryUI.UpdateSlotSelectionHighlight(idx, items, DataHelper)
end

function UIManager.onInventorySlotClick(idx)
	UIManager._onInvSlotClick(idx)
end

function UIManager._onInvSlotDoubleClick(idx)
	local items = InventoryController.getItems()
	local item = items[idx]
	if not item or not item.itemId then return end
	
	local itemData = DataHelper.GetData("ItemData", item.itemId)
	if not itemData then return end
	
	if itemData.type == "ARMOR" then
		local slot = itemData.slot and itemData.slot:upper() or nil
		local isValidSlot = (slot == "HEAD" or slot == "SUIT" or slot == "EARRING" or slot == "RING" or slot == "NECKLACE")
		if not isValidSlot then
			UIManager.notify("장착 가능한 장비가 아닙니다.", C.RED)
			return
		end
		InventoryController.requestEquip(idx, slot)
	elseif itemData.type == "TOOL" or itemData.type == "WEAPON" then
		InventoryController.requestEquip(idx, "HAND")
	elseif itemData.type == "FOOD" or itemData.type == "CONSUMABLE" or itemData.type == "REPAIR_ITEM" then
		InventoryController.requestUse(idx)
	elseif itemData.type == "RUNE" then
		local equip = InventoryController.getEquipment()
		local targetSlot = "RUNE1"
		if equip.RUNE1 then targetSlot = "RUNE2" end
		if equip.RUNE1 and equip.RUNE2 then targetSlot = "RUNE3" end
		InventoryController.requestEquip(idx, targetSlot)
	end
end

function UIManager.onUseItem()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item or not item.itemId then return end

	local itemData = DataHelper.GetData("ItemData", item.itemId)
	if not itemData then return end

	if itemData.type == "ARMOR" then
		local slot = itemData.slot and itemData.slot:upper() or nil
		local isValidSlot = (slot == "HEAD" or slot == "SUIT" or slot == "EARRING" or slot == "RING" or slot == "NECKLACE")
		if not isValidSlot then
			UIManager.notify("방어구 슬롯 정보가 올바르지 않습니다.", C.RED)
			return
		end
		InventoryController.requestEquip(selectedInvSlot, slot)
		return
	elseif itemData.type == "TOOL" or itemData.type == "WEAPON" then
		InventoryController.requestEquip(selectedInvSlot, "HAND")
		return
	elseif itemData.type == "RUNE" then
		local equip = InventoryController.getEquipment()
		local targetSlot = "RUNE1"
		if equip.RUNE1 then targetSlot = "RUNE2" end
		if equip.RUNE1 and equip.RUNE2 then targetSlot = "RUNE3" end
		InventoryController.requestEquip(selectedInvSlot, targetSlot)
		return
	end

	InventoryController.requestUse(selectedInvSlot)
end

function UIManager.onInventorySlotRightClick(idx)
	if not WindowManager.isOpen("INV") or not idx then return end
	
	local items = InventoryController.getItems()
	local item = items[idx]
	if not item or not item.itemId then return end
	
	local itemData = DataHelper.GetData("ItemData", item.itemId)
	if not itemData then return end
	
	UIManager._onInvSlotClick(idx)
	
	if itemData.type == "TOOL" or itemData.type == "WEAPON" then
		InventoryController.requestEquip(idx, "HAND")
		return
	elseif itemData.type == "REPAIR_ITEM" or itemData.type == Enums.ItemType.REPAIR_ITEM then
		return
	end
	
	InventoryController.requestUse(idx)
end

----------------------------------------------------------------
-- Public API: Weapon Crafting (NPC) [RESTORED]
----------------------------------------------------------------
function UIManager.openWeaponCrafting(recipes)
	WindowManager.open("CRAFTING", recipes)
end

local SelectedCraftRecipe = nil
local SelectedCraftMode = nil
local ActiveCraftQueue = {} -- 클라이언트 캐시
local CraftingLoopActive = false

-- 백그라운드 큐 조회 루프 (탭을 닫았다가 다시 열어도 0.5초 안에 완벽 상태 복원!)
local function StartCraftingMonitorLoop()
	if CraftingLoopActive then return end
	CraftingLoopActive = true

	task.spawn(function()
		while CraftingLoopActive and WindowManager.isOpen("CRAFTING") do
			local ok, response = NetClient.Request("Craft.GetQueue.Request", {})
			if ok and response and response.queue then
				ActiveCraftQueue = response.queue
				-- 슬롯 인라인 진행도 실시간 업데이트
				CraftingUI.UpdateAllSlots(ActiveCraftQueue, UIManager)
				-- 상세 패널도 갱신
				if SelectedCraftRecipe then
					local playerItemCounts = {}
					local invCache = InventoryController.getInventoryCache()
					for _, slot in pairs(invCache) do
						playerItemCounts[slot.itemId] = (playerItemCounts[slot.itemId] or 0) + slot.count
					end
					local matched = nil
					for _, q in ipairs(ActiveCraftQueue) do
						if q.recipeId == SelectedCraftRecipe.id then matched = q; break end
					end
					local canMake = UIManager.checkMaterials(SelectedCraftRecipe, playerItemCounts)
					CraftingUI.UpdateDetail(
						SelectedCraftRecipe, SelectedCraftMode, false, canMake,
						playerItemCounts, DataHelper, UIManager.getItemIcon,
						matched and matched.progressRatio or 0,
						matched and matched.state or nil
					)
				end
			end
			task.wait(0.5)
		end
		CraftingLoopActive = false
	end)
end

function UIManager._OnOpenCrafting(recipes)
	CraftingUI.UpdateTitle(UILocalizer.Localize("무기 제작 (Weapon Crafting)"))
	CraftingUI.SetVisible(true)
	
	-- 아이템 개수 캐시 (재료 체크용)
	local playerItemCounts = {}
	local invCache = InventoryController.getInventoryCache()
	for _, slot in pairs(invCache) do
		playerItemCounts[slot.itemId] = (playerItemCounts[slot.itemId] or 0) + slot.count
	end
	
	CraftingUI.Refresh(recipes or {}, playerItemCounts, UIManager.getItemIcon, "CRAFTING", UIManager)
	updateUIMode()
	
	-- [UX 개선] 오픈 시 첫 번째 레시피가 있다면 상세 정보창을 자동으로 로딩/활성화 시켜 무반응 버그 원천 예방
	if recipes and #recipes > 0 then
		UIManager._OnCraftSlotClick(recipes[1], "CRAFTING")
	end
	
	-- 진행 모니터링 루프 기동!
	StartCraftingMonitorLoop()
end

function UIManager._OnCloseCrafting()
	CraftingLoopActive = false
	CraftingUI.SetVisible(false)
	updateUIMode()
end

function UIManager._OnCraftSlotClick(item, mode)
	SelectedCraftRecipe = item
	SelectedCraftMode = mode
	
	local playerItemCounts = {}
	local invCache = InventoryController.getInventoryCache()
	for _, slot in pairs(invCache) do
		playerItemCounts[slot.itemId] = (playerItemCounts[slot.itemId] or 0) + slot.count
	end
	
	local canMake, _ = UIManager.checkMaterials(item, playerItemCounts)
	
	-- 큐 매칭 조회
	local matchedQueueEntry = nil
	for _, q in ipairs(ActiveCraftQueue) do
		if q.recipeId == item.id then
			matchedQueueEntry = q
			break
		end
	end
	
	CraftingUI.UpdateDetail(
		item, mode, false, canMake, playerItemCounts, DataHelper, UIManager.getItemIcon,
		matchedQueueEntry and matchedQueueEntry.progressRatio or 0,
		matchedQueueEntry and matchedQueueEntry.state or nil
	)
end

-- 레시피를 받아 제작 요청하는 공통 내부 함수
local function _startCraftRequest(recipe)
	if not recipe then return end

	for _, q in ipairs(ActiveCraftQueue) do
		if q.recipeId == recipe.id then
			if q.state == "PENDING_COLLECT" or q.state == "COMPLETED" or q.progressRatio >= 1 then
				UIManager._DoCollect(q.craftId)
			end
			-- 이미 제작 중이면 무시
			return
		end
	end

	local playerItemCounts = {}
	local invCache = InventoryController.getInventoryCache()
	for _, slot in pairs(invCache) do
		playerItemCounts[slot.itemId] = (playerItemCounts[slot.itemId] or 0) + slot.count
	end

	local canMake, msg = UIManager.checkMaterials(recipe, playerItemCounts)
	if not canMake then
		UIManager.notify(msg, Color3.fromRGB(255, 75, 50))
		return
	end

	task.spawn(function()
		local resultOk, _ = NetClient.Request("Craft.Start.Request", { recipeId = recipe.id })
		if resultOk then
			UIManager.notify("제작 등록 완료!", Color3.fromRGB(140, 220, 100))
			local ok, qRes = NetClient.Request("Craft.GetQueue.Request", {})
			if ok and qRes and qRes.queue then
				ActiveCraftQueue = qRes.queue
				CraftingUI.UpdateAllSlots(ActiveCraftQueue, UIManager)
			end
		else
			UIManager.notify("제작 요청 실패!", Color3.fromRGB(255, 75, 50))
		end
	end)
end

-- 상세 패널 "제작 시작" 버튼에서 호출
function UIManager._DoCraft()
	_startCraftRequest(SelectedCraftRecipe)
end

-- 슬롯 인라인 "제작 시작" 버튼에서 호출 (레시피 직접 전달)
function UIManager._DoCraftDirect(recipe)
	_startCraftRequest(recipe)
end

function UIManager._DoCollect(craftId)
	if not craftId then return end
	
	task.spawn(function()
		local resultOk, response = NetClient.Request("Craft.Collect.Request", {
			craftId = craftId
		})
		
		if resultOk and response and response.success ~= false then
			UIManager.notify("제작 완료! 아이템을 수령했습니다.", Color3.fromRGB(140, 220, 100))
			UIManager.refreshInventory()
			local ok, qRes = NetClient.Request("Craft.GetQueue.Request", {})
			ActiveCraftQueue = (ok and qRes and qRes.queue) or {}
			CraftingUI.UpdateAllSlots(ActiveCraftQueue, UIManager)
			UIManager.RefreshWeaponCrafting()
		else
			UIManager.notify("수령 실패: 인벤토리 공간이 가득 찼습니다", Color3.fromRGB(255, 75, 50))
		end
	end)
end

function UIManager._DoCancel(craftId)
	if not craftId then return end
	
	task.spawn(function()
		local resultOk, response = NetClient.Request("Craft.Cancel.Request", {
			craftId = craftId
		})
		
		if resultOk and response and response.success ~= false then
			UIManager.notify("제작이 취소되었습니다. 재료가 반환되었습니다.", Color3.fromRGB(255, 150, 50))
			UIManager.refreshInventory()
			local ok, qRes = NetClient.Request("Craft.GetQueue.Request", {})
			ActiveCraftQueue = (ok and qRes and qRes.queue) or {}
			CraftingUI.UpdateAllSlots(ActiveCraftQueue, UIManager)
			UIManager.RefreshWeaponCrafting()
		else
			UIManager.notify("제작 취소 실패", Color3.fromRGB(255, 75, 50))
		end
	end)
end

function UIManager._DoInstantComplete(craftId)
	if not craftId then return end
	
	task.spawn(function()
		local resultOk, response = NetClient.Request("Craft.InstantComplete.Request", {
			craftId = craftId
		})
		
		if resultOk and response and response.success ~= false then
			local MarketplaceService = game:GetService("MarketplaceService")
			local Players = game:GetService("Players")
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, 3602616787)
		else
			UIManager.notify("즉시 완료 요청 실패", Color3.fromRGB(255, 75, 50))
		end
	end)
end


function UIManager.RefreshWeaponCrafting()
	if not WindowManager.isOpen("CRAFTING") then return end
	
	-- 무기 장인 오픈 시의 레시피 목록 구하기
	local RecipeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("RecipeData"))
	local weaponRecipes = collectWeaponCrafterRecipes(RecipeData)
	
	local playerItemCounts = {}
	local invCache = InventoryController.getInventoryCache()
	for _, slot in pairs(invCache) do
		playerItemCounts[slot.itemId] = (playerItemCounts[slot.itemId] or 0) + slot.count
	end
	
	CraftingUI.Refresh(weaponRecipes, playerItemCounts, UIManager.getItemIcon, "CRAFTING", UIManager)
	-- Refresh로 슬롯이 재생성됐으므로 큐 상태 즉시 반영
	CraftingUI.UpdateAllSlots(ActiveCraftQueue, UIManager)

	if SelectedCraftRecipe then
		local matched = nil
		for _, q in ipairs(ActiveCraftQueue) do
			if q.recipeId == SelectedCraftRecipe.id then matched = q; break end
		end
		local canMake = UIManager.checkMaterials(SelectedCraftRecipe, playerItemCounts)
		CraftingUI.UpdateDetail(
			SelectedCraftRecipe, SelectedCraftMode, false, canMake, playerItemCounts,
			DataHelper, UIManager.getItemIcon,
			matched and matched.progressRatio or 0,
			matched and matched.state or nil
		)
	end
end

----------------------------------------------------------------
-- Public API: Crafting
----------------------------------------------------------------
function UIManager.checkMaterials(item, playerItemCounts)
	playerItemCounts = playerItemCounts or InventoryController.getItemCounts()
	local inputs = item.inputs or item.requirements
	if not inputs then return true, "" end

	local missing = {}
	for _, inp in ipairs(inputs) do
		local reqId = inp.itemId or inp.id
		local req = inp.count or inp.amount or 0
		local have = playerItemCounts[reqId] or 0
		if have < req then
			local itemName = reqId
			local itemData = DataHelper.GetData("ItemData", itemName)
			if itemData then itemName = itemData.name end
			table.insert(missing, string.format("%s (%d/%d)", itemName, have, req))
		end
	end

	if #missing > 0 then
		return false, "부족한 재료: " .. table.concat(missing, ", ")
	end
	return true, ""
end

----------------------------------------------------------------
-- Personal Crafting (Inventory Tab)
----------------------------------------------------------------
function UIManager.refreshPersonalCrafting(forceRefresh)
	if not invPersonalCraftGrid then return end
	
	if forceRefresh or not cachedPersonalRecipes then
		for _, ch in pairs(invPersonalCraftGrid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
		personalCraftNodes = {}; selectedPersonalRecipeId = nil
		
		local allRecipes = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("RecipeData"))
		cachedPersonalRecipes = {}
		
		for _, recipe in ipairs(allRecipes) do
			if not recipe.requiredFacility then
				local r = table.clone(recipe)
				r._isFacility = false
				table.insert(cachedPersonalRecipes, r)
			end
		end
		
		table.sort(cachedPersonalRecipes, function(a, b) 
			local lvA = a.techLevel or 0
			local lvB = b.techLevel or 0
			if lvA ~= lvB then return lvA < lvB end
			return (a.name or "") < (b.name or "")
		end)
	end

	local gridLayout = invPersonalCraftGrid:FindFirstChildOfClass("UIGridLayout")
	if not gridLayout then
		gridLayout = Instance.new("UIGridLayout")
		local sSize = isMobile and 64 or 56
		gridLayout.CellSize = UDim2.new(0, sSize, 0, sSize)
		gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = invPersonalCraftGrid
		
		local uiPadding = Instance.new("UIPadding")
		uiPadding.PaddingLeft = UDim.new(0, 4)
		uiPadding.PaddingTop = UDim.new(0, 4)
		uiPadding.Parent = invPersonalCraftGrid
	end
	
	invPersonalCraftGrid.ClipsDescendants = true

	local function updateNodes(recipes)
		local playerItemCounts = InventoryController.getItemCounts()
		
		for _, recipe in ipairs(recipes) do
			local canCraft, _ = UIManager.checkMaterials(recipe)
			local node = personalCraftNodes[recipe.id]
			
			if not node then
				local nodeCount = 0
				for _ in pairs(personalCraftNodes) do nodeCount = nodeCount + 1 end
				local idx = nodeCount + 1
				local nf = mkFrame({
					name="PNode"..idx,
					size=UDim2.new(1,0,1,0),
					bg=C.BG_SLOT,
					bgT=0.3,
					r=0,
					stroke=1,
					strokeC=C.BORDER_DIM,
					z=12,
					parent=invPersonalCraftGrid
				})
				
				local icon = Instance.new("ImageLabel")
				icon.Name="Icon"; icon.Size=UDim2.new(0.7,0,0.7,0); icon.Position=UDim2.new(0.5,0,0.5,0)
				icon.AnchorPoint=Vector2.new(0.5,0.5); icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=13; icon.Parent=nf
				
				local iconId = ""
				if recipe.outputs and recipe.outputs[1] then
					iconId = getItemIcon(recipe.outputs[1].itemId)
				end
				if iconId == "" then
					local ridIcon = getItemIcon(recipe.id)
					if ridIcon ~= "" then iconId = ridIcon end
				end
				icon.Image = iconId
				
				local iconLbl = mkLabel({text=recipe.name, size=UDim2.new(0.9,0,0.9,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), ts=8, color=C.WHITE, wrap=true, z=14, parent=nf})
				iconLbl.Visible = (iconId == "")
				
				local btn = mkBtn({name="B", size=UDim2.new(1,0,1,0), bgT=1, z=25, parent=nf})
				btn.MouseButton1Click:Connect(function()
				selectedPersonalRecipeId = recipe.id
					UIManager.refreshPersonalCrafting()
					UIManager._updatePersonalCraftDetail(recipe)
				end)
				
				node = {frame=nf, icon=icon, nameLabel=iconLbl, recipe=recipe}
				personalCraftNodes[recipe.id] = node
			end
			
			local nf = node.frame
			local icon = node.icon
			local st = nf:FindFirstChildOfClass("UIStroke")
			
			nf.BackgroundTransparency = T.SLOT
			if canCraft then
				icon.ImageColor3 = Color3.new(1,1,1)
				nf.BackgroundColor3 = Color3.fromRGB(45, 65, 45)
			else
				icon.ImageColor3 = Color3.fromRGB(150,150,150)
				nf.BackgroundColor3 = C.BG_SLOT
			end
			if st then 
				st.Color = (recipe.id == selectedPersonalRecipeId) and C.GOLD or C.BORDER 
				st.Thickness = (recipe.id == selectedPersonalRecipeId) and 2.5 or 1.5
			end
		end
		
		local rows = math.ceil(#recipes / 4)
		local sSize = isMobile and 64 or 56
		invPersonalCraftGrid.CanvasSize = UDim2.new(0, 0, 0, rows * (sSize + 10) + 10)
	end

	updateNodes(cachedPersonalRecipes)
end

function UIManager._updatePersonalCraftDetail(recipe)
	if not recipe then 
		InventoryUI.UpdateDetail(nil)
		return 
	end
	
	InventoryUI.UpdateDetail(recipe, getItemIcon, Enums, DataHelper, InventoryController.getItemCounts(), false)
	
	local refs = InventoryUI.Refs.Detail
	if refs and refs.ProgFill then
		refs.ProgFill.Size = UDim2.new(0,0,1,0)
		if refs.ProgWrap then refs.ProgWrap.Visible = false end
		if refs.ProgBar then refs.ProgBar.Visible = false end
	end
end

function UIManager.getSelectedRecipeId()
	return selectedPersonalRecipeId
end

function UIManager.isInventoryVisible()
	return InventoryUI.Refs.Frame and InventoryUI.Refs.Frame.Visible
end

function UIManager.isCraftingTabVisible()
	return InventoryUI.Refs.CraftFrame and InventoryUI.Refs.CraftFrame.Visible
end

function UIManager.isMenuOpen()
	return HUDUI.Refs.sideMenu and HUDUI.Refs.sideMenu.Visible
end

local isCrafting = false
local spinnerTween = nil
local progConn = nil

function UIManager.isCrafting()
	return isCrafting and WindowManager.isOpen("INV")
end

function UIManager.showCraftingProgress(duration)
	if isCrafting then return end
	isCrafting = true
	
	local refs = InventoryUI.Refs.Detail
	
	if refs and refs.ProgWrap then
		refs.ProgWrap.Visible = true
		if refs.ProgBar then refs.ProgBar.Visible = true end
		
		if spinnerTween then spinnerTween:Cancel() end
		if refs.Spinner then
			refs.Spinner.Rotation = 0
			spinnerTween = TweenService:Create(refs.Spinner, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Rotation = 360})
			spinnerTween:Play()
		end
		
		if progConn then progConn:Disconnect() end
		local start = tick()
		progConn = RunService.RenderStepped:Connect(function()
			local p = math.clamp((tick() - start) / duration, 0, 1)
			if refs.ProgFill then refs.ProgFill.Size = UDim2.new(p, 0, 1, 0) end
		end)
	end
end

function UIManager.stopCraftingProgress()
	isCrafting = false
	
	if spinnerTween then spinnerTween:Cancel(); spinnerTween = nil end
	if progConn then progConn:Disconnect(); progConn = nil end
	
	local refs = InventoryUI.Refs.Detail
	if refs and refs.ProgWrap then
		refs.ProgWrap.Visible = false
		if refs.ProgBar then refs.ProgBar.Visible = false end
	end
end

function UIManager._doCraft()
	local isInvOpen = WindowManager.isOpen("INV")
	
	if isInvOpen and invCraftContainer and invCraftContainer.Visible then
		if not selectedPersonalRecipeId then return end
		
		local recipe = nil
		for _, r in ipairs(cachedPersonalRecipes or {}) do
			if r.id == selectedPersonalRecipeId then recipe = r; break end
		end
		if not recipe then return end

		local ok, msg = UIManager.checkMaterials(recipe)
		if not ok then UIManager.notify(msg, C.RED); return end

		local craftTime = recipe.craftTime or 3
		UIManager.showCraftingProgress(craftTime)
		
		task.spawn(function()
			local resultOk, response = NetClient.Request("Craft.Start.Request", {
				recipeId = selectedPersonalRecipeId
			})
			
			if resultOk then
				if response and response.instant then
					UIManager.stopCraftingProgress()
					local craftedName = UILocalizer.LocalizeDataText("RecipeData", tostring(recipe.id or ""), "name", recipe.name or "아이템")
					UIManager.notify(craftedName .. " 제작 완료!", C.GREEN)
					UIManager.refreshInventory()
					UIManager.refreshPersonalCrafting() 
				else
					UIManager.stopCraftingProgress()
					UIManager.notify("제작 의뢰 완료!", C.GOLD)
				end
			else
				UIManager.stopCraftingProgress()
				UIManager.notify(friendlyError(response, "제작"), C.RED)
			end
		end)
		return
	end
end

----------------------------------------------------------------
-- Public API: Shop
----------------------------------------------------------------
function UIManager.openShop(shopId)
	WindowManager.open("SHOP", shopId)
end

function UIManager._onOpenShop(shopId)
	activeShopId = shopId
	ShopUI.SetVisible(true)
	updateUIMode()
	
	ShopController.requestShopInfo(shopId, function(ok, shopInfo)
		if ok then
			UIManager.refreshShop(shopId)
		end
	end)
end

function UIManager.closeShop()
	WindowManager.close("SHOP")
end

function UIManager._onCloseShop()
	activeShopId = nil
	ShopUI.SetVisible(false)
end

function UIManager.refreshShop(shopId)
	local sid = shopId or activeShopId
	local shopInfo = ShopController.getShopInfo(sid)
	local playerItems = InventoryController.getItems()
	local gold = ShopController.getGold()
	
	ShopUI.UpdateGold(gold)
	ShopUI.Refresh(shopInfo, playerItems, getItemIcon, C, UIManager)
end

function UIManager.openAuctionHouse()
	WindowManager.open("AUCTION")
end

function UIManager._onOpenAuctionHouse()
	AuctionUI.SetVisible(true)
	updateUIMode()
end

function UIManager.closeAuctionHouse()
	WindowManager.close("AUCTION")
end

function UIManager._onCloseAuctionHouse()
	AuctionUI.SetVisible(false)
end

function UIManager.toggleAuctionHouse()
	WindowManager.toggle("AUCTION")
end

function UIManager.refreshAuctionPending(data)
	AuctionUI.RefreshPendingOnly(data)
end

function UIManager.requestBuy(itemId, count)
	ShopController.requestBuy(activeShopId, itemId, count or 1, function(ok, err)
		if ok then
			UIManager.notify("구매 완료!", C.GOLD)
			UIManager.refreshShop()
		else
			UIManager.notify(friendlyError(err, "구매"), C.RED)
		end
	end)
end

function UIManager.requestSell(slotIdx, count)
	ShopController.requestSell(activeShopId, slotIdx, count or 1, function(ok, err)
		if ok then
			UIManager.notify("판매 완료!", C.GOLD)
			UIManager.refreshShop()
		else
			UIManager.notify(friendlyError(err, "판매"), C.RED)
		end
	end)
end

----------------------------------------------------------------
-- Public API: Interact / Harvest
----------------------------------------------------------------
function UIManager.showInteractPrompt(text, targetName, durability)
	local keyHint = UILocalizer.Localize(text or "[R] 상호작용")
	local buildingName = targetName and targetName ~= "" and targetName or ""

	InteractUI.UpdatePrompt(buildingName, keyHint)
	InteractUI.SetDurabilityVisible(false)
	InteractUI.SetVisible(true)
end

function UIManager.hideInteractPrompt()
	InteractUI.SetDurabilityVisible(false)
	InteractUI.SetVisible(false)
end

function UIManager.showHarvestProgress(totalTime, targetName)
	HUDUI.ShowHarvestProgress(totalTime, targetName)
end

function UIManager.hideHarvestProgress()
	HUDUI.HideHarvestProgress()
end

function UIManager.notify(text, color)
	if not mainGui then return end
	text = UILocalizer.Localize(text)
	
	if currentToast and currentToast.Parent then
		currentToast:Destroy()
	end
	
	local toast = Utils.mkFrame({
		name = "Toast",
		size = UDim2.new(0, 320, 0, 45),
		pos = UDim2.new(0.5, 0, 0.2, -50),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.9,
		r = 4,
		stroke = false,
		parent = mainGui
	})
	
	local label = Utils.mkLabel({
		text = text,
		ts = 18,
		color = color or C.WHITE,
		ink = not color,
		parent = toast
	})
	
	currentToast = toast
	
	toast.Position = UDim2.new(0.5, 0, 0.15, 0)
	local ti = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(toast, ti, {Position = UDim2.new(0.5, 0, 0.2, 0)}):Play()
	
	task.delay(2.5, function()
		if not toast or not toast.Parent then return end
		local fade = TweenService:Create(toast, TweenInfo.new(0.5), {BackgroundTransparency = 1})
		TweenService:Create(label, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		fade:Play()
		fade.Completed:Connect(function() toast:Destroy() end)
	end)
end

-- (Legacy DNA display removed)

-- [New] Side Notification (Corner stack)
function UIManager.sideNotify(text, color, icon)
	if not mainGui then return end
	text = UILocalizer.Localize(text)
	
	if not sideNotifyContainer then
		sideNotifyContainer = Utils.mkFrame({
			name = "SideNotifyContainer",
			size = UDim2.new(0, 250, 0.6, 0),
			pos = UDim2.new(1, -20, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			bgT = 1,
			parent = mainGui
		})
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 5)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.Parent = sideNotifyContainer
	end
	
	local item = Utils.mkFrame({
		name = "NotifyItem",
		size = UDim2.new(1, 0, 0, 45),
		bg = C.BG_PANEL,
		bgT = 0.9, -- 훨씬 더 투명하게
		r = 4,
		stroke = false,
		parent = sideNotifyContainer
	})
	
	local content = Utils.mkFrame({size=UDim2.new(1,0,1,0), bgT=1, parent=item})
	
	if icon then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(0, 30, 0, 30)
		img.Position = UDim2.new(0, 10, 0.5, 0)
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.BackgroundTransparency = 1
		img.Image = icon
		img.Parent = content
	end
	
	local lbl = Utils.mkLabel({
		text = text,
		size = UDim2.new(1, icon and -50 or -20, 1, 0),
		pos = UDim2.new(0, icon and 45 or 10, 0, 0),
		ts = 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = content
	})
	
	-- FX: Slide in from right
	item.Position = UDim2.new(1, 100, 0, 0)
	TweenService:Create(item, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)}):Play()
	
	-- Auto cleanup
	task.delay(4, function()
		if not item or not item.Parent then return end
		local out = TweenService:Create(item, TweenInfo.new(0.5), {BackgroundTransparency = 1, Position = UDim2.new(1, 50, 0, 0)})
		TweenService:Create(lbl, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		out:Play()
		out.Completed:Connect(function() item:Destroy() end)
	end)
end

function UIManager.refreshStatusEffects()
	local list = {}
	for _, data in pairs(activeDebuffs) do
		table.insert(list, data)
	end
	HUDUI.UpdateStatusEffects(list)
end
function UIManager.updateHealth(cur, max)
	HUDUI.UpdateHealth(cur, max)
end

function UIManager.updateStamina(cur, max)
	HUDUI.UpdateStamina(cur, max)
end

-- (Hunger system removed)

function UIManager.updateXP(cur, max)
	HUDUI.UpdateXP(cur, max)
end

local function getStarterPackConfig()
	return ProductConfig.PRODUCTS and ProductConfig.PRODUCTS[STARTER_PACK_PRODUCT_ID] or nil
end

function UIManager.getCurrentPlayerLevel()
	local lvl = cachedStats and cachedStats.level
	if type(lvl) == "number" then
		return lvl
	end

	lvl = player and player:GetAttribute("Level")
	return tonumber(lvl) or 0
end

local function getCurrentPlayerLevel()
	return UIManager.getCurrentPlayerLevel()
end

function UIManager.canShowStarterPackButton()
	local data = getStarterPackConfig()
	if not data or data.showInPremiumShop == true then
		return false
	end

	local limit = tonumber(data.levelThreshold) or 0
	if limit > 0 then
		return getCurrentPlayerLevel() <= limit
	end

	return true
end

function UIManager.refreshStarterPackButton()
	if HUDUI and HUDUI.SetStarterPackVisible then
		HUDUI.SetStarterPackVisible(UIManager.canShowStarterPackButton())
	end
end

function UIManager.promptStarterPackPurchase()
	local data = getStarterPackConfig()
	if not data then
		if UIManager.notify then
			UIManager.notify("스타터팩 정보를 찾을 수 없습니다.", C.RED)
		end
		return
	end

	local limit = tonumber(data.levelThreshold) or 0
	if limit > 0 and getCurrentPlayerLevel() > limit then
		if UIManager.notify then
			UIManager.notify(string.format("초보자 스타터 팩은 %d레벨 이하만 구매할 수 있습니다.", limit), C.RED)
		end
		return
	end

	MarketplaceService:PromptProductPurchase(player, tonumber(STARTER_PACK_PRODUCT_ID))
end

function UIManager.updateStatPoints(available)
	HUDUI.SetStatPointAlert(available)
end

-- (Facility check removed)

----------------------------------------------------------------
-- Event Listeners
----------------------------------------------------------------
local function setupEventListeners()
	InventoryController.onChanged(function()
		if WindowManager.isOpen("INV") then UIManager.refreshInventory() end
		if WindowManager.isOpen("STORAGE") then UIManager.refreshStorage() end
		UIManager.refreshHotbar()
		if HUDUI and HUDUI.UpdateRuneHotbar then HUDUI.UpdateRuneHotbar(InventoryController.getEquipment()) end
		if HUDUI and HUDUI.UpdateConsumableHotbar then HUDUI.UpdateConsumableHotbar() end
		if WindowManager.isOpen("EQUIP") then UIManager.refreshStats() end
		if invCraftContainer and invCraftContainer.Visible then
			UIManager.refreshPersonalCrafting()
		end
	end)
	ShopController.onGoldChanged(function(g) UIManager.updateGold(g) end)
	-- [수정] 구 refreshCrafting() 제거 — 하단 onTechUpdated 콜백이 올바르게 처리합니다.

	-- HUD Update Loop
	RunService.RenderStepped:Connect(function()
		local didPruneDebuff = false
		local now = os.time()
		for debuffId, debuff in pairs(activeDebuffs) do
			if type(debuff) == "table" and (debuff.duration or -1) > 0 then
				local started = debuff.startTime or now
				if (now - started) >= (debuff.duration or 0) then
					activeDebuffs[debuffId] = nil
					didPruneDebuff = true
				end
			end
		end
		if didPruneDebuff then
			UIManager.refreshStatusEffects()
		end

		-- Update Coordinates & Compass
		local char = player.Character
		if char and char.PrimaryPart then
			local pos = char.PrimaryPart.Position
			HUDUI.UpdateCoordinates(pos.X, pos.Z)
		end
		
		local cam = workspace.CurrentCamera
		if cam then
			local look = cam.CFrame.LookVector
			-- Camera North is -Z in world coords
			local angle = math.atan2(look.X, look.Z)
			HUDUI.UpdateCompass(angle)
		end

		HUDUI.UpdateDayNightClock(TimeController.getDayTime(), Balance.DAY_LENGTH)
	end)

	-- 활성 슬롯 동기화 (서버 -> 클라)
	NetClient.On("Inventory.ActiveSlot.Changed", function(data)
		if data and data.slot then
			UIManager.selectHotbarSlot(data.slot, true) -- 루프 방지 위해 skipSync=true
			if WindowManager.isOpen("EQUIP") then
				EquipmentUI.UpdateCharacterPreview(player.Character)
			end
		end
	end)
	-- [Phase 5] UI Toggle Key Bindings are handled in ClientInit.client.lua
	-- (Redundant bindings removed to avoid conflicts)

	-- [HOTBAR REMOVED] 핫바 번호 키 바인딩 및 클릭 이벤트 미사용 (핫바 개념 청산)

	-- Mouse Wheel (Hotbar scroll) - DISABLED as per user request to allow zoom only
	-- UserInputService.InputChanged:Connect(function(input, processed)
	-- 	if processed or isUIOpen or isCraftOpen or isShopOpen or isTechOpen then return end
	-- 	if input.UserInputType == Enum.UserInputType.MouseWheel then
	-- 		local delta = input.Position.Z
	-- 		local newSlot = selectedSlot
	-- 		if delta > 0 then
	-- 			newSlot = selectedSlot - 1
	-- 		else
	-- 			newSlot = selectedSlot + 1
	-- 		end
	-- 		
	-- 		if newSlot < 1 then newSlot = 8 end
	-- 		if newSlot > 8 then newSlot = 1 end
	-- 		
	-- 		if newSlot ~= selectedSlot then
	-- 			UIManager.selectHotbarSlot(newSlot)
	-- 		end
	-- 	end
	-- end)

	-- Stats event
	if NetClient.On then
		NetClient.On("Player.Stats.Changed", function(d)
			if d then
				for k, v in pairs(d) do cachedStats[k] = v end
				if d.level then UIManager.updateLevel(d.level) end
				if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
				if d.leveledUp then
					UIManager.showLevelUpEffect(d.level)
				end
				if d.upgradedStat then
					UIManager.notify(" 💪 능력치 강화 성공!", C.GREEN)
				end
				if d.statPointsAvailable ~= nil then UIManager.updateStatPoints(d.statPointsAvailable) end
				if WindowManager.isOpen("EQUIP") then UIManager.refreshStats() end
				-- 스탯 변경 시 인벤토리 슬롯 수 즉시 동기화
				if d.calculated and d.calculated.maxSlots then
					InventoryController.setMaxSlots(d.calculated.maxSlots)
				end
				UIManager.refreshInventory()
				UIManager.refreshStarterPackButton()
			end
		end)

		NetClient.On("Tutorial.Status.Changed", function(status)
			UIManager.updateTutorialStatus(status)
		end)
	end


	-- DNA 획득 이벤트
	-- (DNA system removed)
		
	-- Debuff Events
	if NetClient.On then
		NetClient.On("Debuff.Applied", function(data)
			if data and data.debuffId then
				activeDebuffs[data.debuffId] = {
					id = data.debuffId,
					name = data.name,
					description = data.description, -- 설명 추가
					startTime = os.time(),
					duration = data.duration
				}
				UIManager.refreshStatusEffects()
			end
		end)
		
		NetClient.On("Debuff.Removed", function(data)
			if data and data.debuffId then
				activeDebuffs[data.debuffId] = nil
				UIManager.refreshStatusEffects()
			end
		end)
	end

	-- Combat Engagement UI
	if NetClient.On then
		NetClient.On("Combat.Engagement.Changed", function(data)
			if not data then return end
			
			if data.inCombat then
				currentCombatCreatureId = data.instanceId
				
				-- Find creature model by instanceId
				local creatureModel = nil
				local workspace_creatures = workspace:FindFirstChild("Creatures") or workspace
				
				-- Search for creature with matching instanceId
				for _, model in ipairs(workspace_creatures:GetDescendants()) do
					if model:IsA("Model") and model:GetAttribute("InstanceId") == data.instanceId then
						creatureModel = model
						break
					end
				end
				
				-- Fallback: search in Workspace directly
				if not creatureModel then
					for _, child in ipairs(workspace:GetChildren()) do
						if child:IsA("Model") and child:GetAttribute("InstanceId") == data.instanceId then
							creatureModel = child
							break
						end
					end
				end
				
				if creatureModel then
					local displayName = creatureModel:GetAttribute("DisplayName") or creatureModel.Name
					local creatureId = creatureModel:GetAttribute("CreatureId") or creatureModel.Name
					
					-- Clean up display name (remove "Lv.X" if already included)
					displayName = string.match(displayName, "([^L][^v]*?)%s*Lv%.%d+$") or displayName
					displayName = string.match(displayName, "^(.+?)%s*Lv%.") or displayName
					
					-- Look up creature data for actual level
					local creatureLevel = creatureModel:GetAttribute("Level") or 1
					if CreatureData and type(CreatureData) == "table" then
						for _, cData in ipairs(CreatureData) do
							if cData.id == creatureId or cData.name == displayName then
								creatureLevel = cData.level or creatureLevel
								break
							end
						end
					end
					
					local currentHP = creatureModel:GetAttribute("CurrentHealth") or 100
					local maxHP = creatureModel:GetAttribute("MaxHealth") or 100
					
					HUDUI.ShowCombatUI(displayName, creatureLevel, currentHP, maxHP)
				end
			else
				-- 전투 해제 시: 짧은 딜레이 후 숨김 (사망 시 HP바=0 반영을 위해)
				-- Hit.Result 이벤트가 먼저 도착하여 HP바를 0으로 업데이트할 여유를 줌
				local disengagedId = currentCombatCreatureId
				task.delay(0.8, function()
					-- 딜레이 중 새 전투가 시작되지 않았으면 숨김
					if currentCombatCreatureId == disengagedId then
						currentCombatCreatureId = nil
						HUDUI.HideCombatUI()
					end
				end)
			end
		end)

		-- 플레이어 공격 히트 시 체력바 즉시 반영
		NetClient.On("Combat.Hit.Result", function(data)
			if data and data.currentHP and data.maxHP and currentCombatCreatureId then
				if data.targetId == currentCombatCreatureId then
					HUDUI.UpdateCombatUI(data.currentHP, data.maxHP)
				end
			end
		end)

-- (Pal combat hit removed)
	end

	-- Portal Events (고대 포탈 시스템)
	if NetClient.On then
		NetClient.On("SkyIsland.OpenDialogue", function(data)
			local isReturn = data and data.isReturn == true
			local canTravel = data and data.canTravel == true
			local npcName = (data and data.npcName) or "인도자"
			local dialogueText = (data and data.dialogue) or ""
			local confirmText = data and data.confirmText
			local declineText = (data and data.declineText) or "알겠습니다."

			-- 기존 대화창 제거
			if mainGui:FindFirstChild("SkyDialogueRoot") then
				mainGui.SkyDialogueRoot:Destroy()
			end

			-- 루트 (클릭 차단용)
			local root = Instance.new("Frame")
			root.Name = "SkyDialogueRoot"
			root.Size = UDim2.new(1, 0, 1, 0)
			root.BackgroundTransparency = 1
			root.ZIndex = 950
			root.Parent = mainGui

			-- 하단 대화 박스 (화면 하단 고정, RPG 스타일)
			local BOX_H = isMobile and 0.32 or 0.28
			local dialogueBox = Instance.new("Frame")
			dialogueBox.Name = "DialogueBox"
			dialogueBox.Size = UDim2.new(1, 0, BOX_H, 0)
			dialogueBox.Position = UDim2.new(0, 0, 1 - BOX_H, 0)
			dialogueBox.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
			dialogueBox.BackgroundTransparency = 0.08
			dialogueBox.BorderSizePixel = 0
			dialogueBox.ZIndex = 951
			dialogueBox.Parent = root

			-- 상단 테두리 라인
			local topLine = Instance.new("Frame")
			topLine.Size = UDim2.new(1, 0, 0, 2)
			topLine.Position = UDim2.new(0, 0, 0, 0)
			topLine.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
			topLine.BorderSizePixel = 0
			topLine.ZIndex = 952
			topLine.Parent = dialogueBox

			-- NPC 이름 플레이트
			local namePlate = Instance.new("Frame")
			namePlate.Name = "NamePlate"
			namePlate.Size = UDim2.new(0, 0, 0, 32)
			namePlate.Position = UDim2.new(0, 20, 0, -18)
			namePlate.BackgroundColor3 = Color3.fromRGB(20, 40, 90)
			namePlate.BorderSizePixel = 0
			namePlate.AutomaticSize = Enum.AutomaticSize.X
			namePlate.ZIndex = 953
			namePlate.Parent = dialogueBox

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 0, 1, 0)
			nameLabel.AutomaticSize = Enum.AutomaticSize.X
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = " " .. npcName .. " "
			nameLabel.Font = F.TITLE
			nameLabel.TextSize = 15
			nameLabel.TextColor3 = Color3.fromRGB(180, 210, 255)
			nameLabel.ZIndex = 954
			nameLabel.Parent = namePlate

			local nameStroke = Instance.new("UIStroke")
			nameStroke.Color = Color3.fromRGB(100, 150, 255)
			nameStroke.Thickness = 1.5
			nameStroke.Parent = namePlate

			local nameCorner = Instance.new("UICorner")
			nameCorner.CornerRadius = UDim.new(0, 4)
			nameCorner.Parent = namePlate

			-- 대화 텍스트 영역
			local textLabel = Instance.new("TextLabel")
			textLabel.Name = "DialogueText"
			textLabel.Size = UDim2.new(1, -40, 0.6, 0)
			textLabel.Position = UDim2.new(0, 20, 0, 22)
			textLabel.BackgroundTransparency = 1
			textLabel.Text = ""
			textLabel.Font = F.NORMAL
			textLabel.TextSize = isMobile and 14 or 16
			textLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
			textLabel.TextXAlignment = Enum.TextXAlignment.Left
			textLabel.TextYAlignment = Enum.TextYAlignment.Top
			textLabel.TextWrapped = true
			textLabel.RichText = true
			textLabel.ZIndex = 952
			textLabel.Parent = dialogueBox

			-- 선택지 영역 (대화 박스 하단)
			local choiceFrame = Instance.new("Frame")
			choiceFrame.Name = "ChoiceFrame"
			choiceFrame.Size = UDim2.new(1, -40, 0, 0)
			choiceFrame.Position = UDim2.new(0, 20, 1, -10)
			choiceFrame.AnchorPoint = Vector2.new(0, 1)
			choiceFrame.BackgroundTransparency = 1
			choiceFrame.AutomaticSize = Enum.AutomaticSize.Y
			choiceFrame.ZIndex = 952
			choiceFrame.Parent = dialogueBox

			local choiceLayout = Instance.new("UIListLayout")
			choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
			choiceLayout.Padding = UDim.new(0, 6)
			choiceLayout.Parent = choiceFrame

			local function makeChoiceBtn(text, layoutOrder, color, fn)
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 0, isMobile and 36 or 32)
				btn.BackgroundColor3 = Color3.fromRGB(18, 28, 55)
				btn.BorderSizePixel = 0
				btn.Text = "▶  " .. text
				btn.Font = F.NORMAL
				btn.TextSize = isMobile and 13 or 14
				btn.TextColor3 = color or Color3.fromRGB(200, 220, 255)
				btn.TextXAlignment = Enum.TextXAlignment.Left
				btn.RichText = false
				btn.LayoutOrder = layoutOrder
				btn.ZIndex = 953
				btn.Parent = choiceFrame

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 4)
				corner.Parent = btn

				local pad = Instance.new("UIPadding")
				pad.PaddingLeft = UDim.new(0, 10)
				pad.Parent = btn

				btn.MouseEnter:Connect(function()
					btn.BackgroundColor3 = Color3.fromRGB(30, 50, 100)
				end)
				btn.MouseLeave:Connect(function()
					btn.BackgroundColor3 = Color3.fromRGB(18, 28, 55)
				end)
				btn.MouseButton1Click:Connect(fn)
				return btn
			end

			local function closeDialogue()
				root:Destroy()
			end

			-- 타이프라이터 효과
			local typingDone = false
			local fullText = dialogueText
			task.spawn(function()
				local displayed = ""
				-- RichText를 보존하면서 문자 단위로 표시
				local plainChars = {}
				local i = 1
				while i <= #fullText do
					-- <b> 태그 등은 통째로 처리
					if fullText:sub(i, i) == "<" then
						local tagEnd = fullText:find(">", i)
						if tagEnd then
							local tag = fullText:sub(i, tagEnd)
							displayed = displayed .. tag
							i = tagEnd + 1
						else
							displayed = displayed .. fullText:sub(i, i)
							i = i + 1
						end
					else
						displayed = displayed .. fullText:sub(i, i)
						i = i + 1
						textLabel.Text = displayed
						task.wait(0.012)
					end
				end
				textLabel.Text = fullText
				typingDone = true
			end)

			-- 선택지 버튼 생성 (타이핑 완료 후 또는 클릭 즉시 건너뛰기)
			local choicesAdded = false
			local function addChoices()
				if choicesAdded then return end
				choicesAdded = true
				textLabel.Text = fullText

				if confirmText then
					makeChoiceBtn(confirmText, 1, Color3.fromRGB(150, 210, 255), function()
						closeDialogue()
						task.spawn(function()
							local success, err = NetClient.Request("SkyIsland.Teleport.Request", { isReturn = isReturn })
							if not success then
								UIManager.notify("이동 실패: " .. friendlyError(err), C.RED)
							end
						end)
					end)
				end

				makeChoiceBtn(declineText, 2, Color3.fromRGB(180, 180, 180), function()
					closeDialogue()
				end)
			end

			-- 대화창 클릭 시 타이핑 스킵 or 선택지 표시
			local boxBtn = Instance.new("TextButton")
			boxBtn.Size = UDim2.new(1, 0, 1, 0)
			boxBtn.BackgroundTransparency = 1
			boxBtn.Text = ""
			boxBtn.ZIndex = 951
			boxBtn.Parent = dialogueBox
			boxBtn.MouseButton1Click:Connect(function()
				if not typingDone then
					typingDone = true
					textLabel.Text = fullText
					task.wait(0.05)
					addChoices()
				else
					addChoices()
				end
			end)

			-- 타이핑 완료 후 자동으로 선택지 추가
			task.spawn(function()
				while not typingDone do
					task.wait(0.05)
				end
				task.wait(0.1)
				addChoices()
			end)
		end)

		NetClient.On("Portal.UI.Open", function(data)
			UIManager.openPortalRadial(data)
		end)

		NetClient.On("Portal.MissingMaterials", function()
			UIManager.notify("⚡ 골드가 부족하거나 잘못된 요청입니다.", Color3.fromRGB(255, 120, 80))
		end)

		NetClient.On("Portal.Repaired", function(_data)
			UIManager.notify("🌀 고대 포탈이 수리되었습니다!", Color3.fromRGB(255, 200, 0))
			UIManager.sideNotify("포탈 UI의 [포탈 이용] 탭에서 이동할 수 있습니다", Color3.fromRGB(100, 200, 255))
			UIManager.refreshPortal({ repaired = true })
		end)

		NetClient.On("Portal.Teleporting", function(data)
			local dest = (data and data.destination) or "다음 섬"
			UIManager.closePortalRadial()

			local oldFadeGui = player.PlayerGui:FindFirstChild("PortalFadeGui")
			if oldFadeGui then
				oldFadeGui:Destroy()
			end

			-- 페이드 스크린 생성
			local fadeGui = Instance.new("ScreenGui")
			fadeGui.Name = "PortalFadeGui"
			fadeGui.DisplayOrder = 999
			fadeGui.IgnoreGuiInset = true
			fadeGui.ResetOnSpawn = false
			fadeGui.Parent = player.PlayerGui

			local overlay = Instance.new("Frame")
			overlay.Size = UDim2.new(1, 0, 1, 0)
			overlay.BackgroundColor3 = Color3.new(0, 0, 0)
			overlay.BackgroundTransparency = 1
			overlay.BorderSizePixel = 0
			overlay.Parent = fadeGui

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 0, 60)
			label.Position = UDim2.new(0, 0, 0.45, -40)
			label.BackgroundTransparency = 1
			label.Text = "🌀 " .. dest .. "(으)로 이동 중..."
			label.TextColor3 = Color3.fromRGB(200, 230, 255)
			label.TextSize = 28
			label.Font = Enum.Font.GothamBold
			label.TextTransparency = 1
			label.Parent = overlay

			-- 로딩바 배경
			local barBg = Instance.new("Frame")
			barBg.Name = "ProgressBarBg"
			barBg.Size = UDim2.new(0.4, 0, 0, 12)
			barBg.Position = UDim2.new(0.3, 0, 0.45, 30)
			barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			barBg.BorderSizePixel = 0
			barBg.BackgroundTransparency = 1
			local bgCorner = Instance.new("UICorner")
			bgCorner.CornerRadius = UDim.new(0.5, 0)
			bgCorner.Parent = barBg
			barBg.Parent = overlay

			-- 로딩바 채움
			local barFill = Instance.new("Frame")
			barFill.Name = "ProgressBarFill"
			barFill.Size = UDim2.new(0, 0, 1, 0)
			barFill.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
			barFill.BorderSizePixel = 0
			barFill.BackgroundTransparency = 1
			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(0.5, 0)
			fillCorner.Parent = barFill
			barFill.Parent = barBg

			-- 빛나는 효과 (가짜 진행률)
			local uigradient = Instance.new("UIGradient")
			uigradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 180, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 230, 255))
			})
			uigradient.Parent = barFill

			-- 페이드 인 (검정화면)
			TweenService:Create(overlay, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
			TweenService:Create(label, TweenInfo.new(0.8), {TextTransparency = 0}):Play()
			TweenService:Create(barBg, TweenInfo.new(0.8), {BackgroundTransparency = 0.3}):Play()
			TweenService:Create(barFill, TweenInfo.new(0.8), {BackgroundTransparency = 0}):Play()

			-- 모의 로딩 애니메이션 (85%까지 약 4초에 걸쳐 천천히 진입)
			task.delay(0.8, function()
				if barFill and barFill.Parent then
					TweenService:Create(barFill, TweenInfo.new(4.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 1, 0)}):Play()
				end
			end)
		end)

		NetClient.On("Portal.Arrived", function(_data)
			local fadeGui = player.PlayerGui:FindFirstChild("PortalFadeGui")
			if fadeGui then
				local overlay = fadeGui:FindFirstChildWhichIsA("Frame")
				if overlay then
					local label = overlay:FindFirstChildWhichIsA("TextLabel")
					local barBg = overlay:FindFirstChild("ProgressBarBg")
					local barFill = barBg and barBg:FindFirstChild("ProgressBarFill")

					task.spawn(function()
						-- 1. 완료 시 잔여 로딩바를 빠르게 100%로 채움
						if barFill then
							TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 1, 0)}):Play()
						end
						if label then
							label.Text = "🌀 안전하게 도착했습니다!"
							label.TextColor3 = Color3.fromRGB(150, 255, 150)
						end
						task.wait(0.5)

						-- 2. 서서히 화면 페이드 아웃
						local fadeOut = TweenService:Create(overlay, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
						if label then TweenService:Create(label, TweenInfo.new(0.6), {TextTransparency = 1}):Play() end
						if barBg then TweenService:Create(barBg, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play() end
						if barFill then TweenService:Create(barFill, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play() end

						fadeOut:Play()
						fadeOut.Completed:Connect(function()
							fadeGui:Destroy()
						end)
					end)
				else
					fadeGui:Destroy()
				end
			end
		end)

		NetClient.On("Portal.Error", function(data)
			local msg = (data and data.message) or "포탈 오류"
			local fadeGui = player.PlayerGui:FindFirstChild("PortalFadeGui")
			if fadeGui then
				fadeGui:Destroy()
			end
			UIManager.sideNotify("❌ " .. msg, Color3.fromRGB(255, 80, 80))
		end)
	end

	-- Humanoid HP / Stats Sync
	local function connectHumanoid(hum)
		UIManager.updateHealth(hum.Health, hum.MaxHealth)
		
		hum.HealthChanged:Connect(function(h)
			UIManager.updateHealth(h, hum.MaxHealth)
		end)
		
		hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			UIManager.updateHealth(hum.Health, hum.MaxHealth)
		end)
	end

	-- MovementController 연동 (스태미나)
	local function setupMovementController()
		local MovementController = require(Client:WaitForChild("Controllers"):WaitForChild("MovementController"))
		if MovementController and MovementController.onStaminaChanged then
			MovementController.onStaminaChanged(function(cur, max)
				UIManager.updateStamina(cur, max)
			end)
			
			-- 초기값 반영
			local c, m = MovementController.getStamina()
			UIManager.updateStamina(c, m)
		end
	end

-- (Hunger system removed)

	task.spawn(function()
		setupMovementController()
		
		-- (Hunger request removed)

		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then connectHumanoid(hum) end
		
		player.CharacterAdded:Connect(function(c)
			local h2 = c:WaitForChild("Humanoid", 10)
			if h2 then 
				connectHumanoid(h2)
				-- [Safety] 리스폰 시 서버가 스탯을 적용할 시간을 주기 위해 약간 지연 후 강제 갱신
				task.delay(0.5, function()
					if h2 and h2.Parent then
						UIManager.updateHealth(h2.Health, h2.MaxHealth)
					end
				end)
			end
			
			-- 리스폰 시 레벨/XP/배고픔/스태미나 재동기화
			task.delay(0.5, function()
				local ok2, d2 = NetClient.Request("Player.Stats.Request", {})
				if ok2 and d2 then
					cachedStats = d2
					if d2.level then UIManager.updateLevel(d2.level) end
					if d2.currentXP and d2.requiredXP then UIManager.updateXP(d2.currentXP, d2.requiredXP) end
					if d2.statPointsAvailable then UIManager.updateStatPoints(d2.statPointsAvailable) end
					UIManager.refreshStarterPackButton()
				end
				
-- (Hunger respawn removed)
			end)
		end)
	end)

	-- Initial stats load (재시도 포함 — 서버 SaveService 로딩 대기 대응)
	task.spawn(function()
		local player = game:GetService("Players").LocalPlayer
		while not player:GetAttribute("DataLoaded") do task.wait(0.2) end
		
		task.wait(1)
		for _attempt = 1, 15 do
			local ok, d = NetClient.Request("Player.Stats.Request", {})
			if ok and d then
				cachedStats = d
				if d.level then UIManager.updateLevel(d.level) end
				if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
				if d.statPointsAvailable then UIManager.updateStatPoints(d.statPointsAvailable) end
				UIManager.refreshStarterPackButton()
				break
			end
			task.wait(2)
		end
	end)

	-- [FIX] 제작 서버 이벤트 동기화 (Phase 11)
	if NetClient.On then
		NetClient.On("Craft.Started", function(data)
			if data and data.craftTime then
				UIManager.showCraftingProgress(data.craftTime)
			end
		end)
		
		NetClient.On("Craft.Completed", function(data)
			UIManager.stopCraftingProgress()
			
			local itemName = "아이템"
			if data and data.recipeId then
				local recipe = DataHelper.GetData("RecipeData", data.recipeId)
				if recipe then
					itemName = UILocalizer.LocalizeDataText("RecipeData", tostring(data.recipeId), "name", recipe.name)
				end
			end
			
			UIManager.notify(itemName .. " 제작 완료!", C.GREEN)
			UIManager.refreshInventory()
			UIManager.refreshPersonalCrafting()
		end)
		
		NetClient.On("Craft.Cancelled", function(data)
			UIManager.stopCraftingProgress()
			UIManager.notify("제작이 취소되었습니다.", C.WHITE)
		end)

		-- 범용 서버 알림 메시지
		NetClient.On("Notify.Message", function(data)
			if data and data.text then
				local color = C.WHITE
				if data.color then
					color = Color3.fromRGB(data.color.r or 255, data.color.g or 255, data.color.b or 255)
				end
				UIManager.notify(data.text, color)
			end
		end)

		-- 무기 장인 대화창 (TrainerController/MagicianController와 동일 컨벤션)
		NetClient.On("WeaponCrafter.OpenDialogue", function(_data)
			local playerGui = player:WaitForChild("PlayerGui")
			local existing = playerGui:FindFirstChild("WeaponCrafterDialogueSG")
			if existing then existing:Destroy() end

			local sg = Instance.new("ScreenGui")
			sg.Name           = "WeaponCrafterDialogueSG"
			sg.ResetOnSpawn   = false
			sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			sg.DisplayOrder   = 200
			sg.IgnoreGuiInset = true
			sg.Parent         = playerGui

			-- 가로 폭 제한, 하단 중앙, 세로 자동 확장
			local BOX_W = isMobile and UDim2.new(0.96, 0, 0, 0) or UDim2.new(0, 740, 0, 0)
			local dialogueBox = Instance.new("Frame")
			dialogueBox.Name                  = "DialogueBox"
			dialogueBox.Size                  = BOX_W
			dialogueBox.AnchorPoint           = Vector2.new(0.5, 1)
			dialogueBox.Position              = UDim2.new(0.5, 0, 1, -8)
			dialogueBox.AutomaticSize         = Enum.AutomaticSize.Y
			dialogueBox.BackgroundColor3      = Color3.fromRGB(8, 12, 22)
			dialogueBox.BackgroundTransparency = 0.08
			dialogueBox.BorderSizePixel       = 0
			dialogueBox.Parent                = sg
			Instance.new("UICorner", dialogueBox).CornerRadius = UDim.new(0, 6)

			local topLine = Instance.new("Frame")
			topLine.Size             = UDim2.new(1, 0, 0, 2)
			topLine.BackgroundColor3 = Color3.fromRGB(200, 140, 60)  -- 무기 장인 테마: 황금/주황
			topLine.BorderSizePixel  = 0
			topLine.Parent           = dialogueBox
			Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 2)

			local namePlate = Instance.new("Frame")
			namePlate.Size             = UDim2.new(0, 0, 0, 30)
			namePlate.Position         = UDim2.new(0, 18, 0, -16)
			namePlate.AutomaticSize    = Enum.AutomaticSize.X
			namePlate.BackgroundColor3 = Color3.fromRGB(55, 35, 10)
			namePlate.BorderSizePixel  = 0
			namePlate.ZIndex           = 2
			namePlate.Parent           = dialogueBox
			Instance.new("UICorner", namePlate).CornerRadius = UDim.new(0, 4)
			local npStroke = Instance.new("UIStroke", namePlate)
			npStroke.Color = Color3.fromRGB(200, 140, 60); npStroke.Thickness = 1.5

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size                   = UDim2.new(0, 0, 1, 0)
			nameLabel.AutomaticSize          = Enum.AutomaticSize.X
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text                   = "  무기 장인  "
			nameLabel.Font                   = F.TITLE
			nameLabel.TextSize               = 14
			nameLabel.TextColor3             = Color3.fromRGB(255, 210, 140)
			nameLabel.ZIndex                 = 3
			nameLabel.Parent                 = namePlate

			-- 내부 레이아웃: 텍스트 → 구분선 → 선택지 세로 적층
			local content = Instance.new("Frame")
			content.Size                  = UDim2.new(1, -32, 0, 0)
			content.Position              = UDim2.new(0, 16, 0, 14)
			content.AutomaticSize         = Enum.AutomaticSize.Y
			content.BackgroundTransparency = 1
			content.Parent                = dialogueBox
			local contentLayout = Instance.new("UIListLayout", content)
			contentLayout.SortOrder          = Enum.SortOrder.LayoutOrder
			contentLayout.Padding            = UDim.new(0, 0)
			contentLayout.FillDirection      = Enum.FillDirection.Vertical
			contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

			local textLabel = Instance.new("TextLabel")
			textLabel.Name                 = "DialogueText"
			textLabel.Size                 = UDim2.new(1, 0, 0, 0)
			textLabel.AutomaticSize        = Enum.AutomaticSize.Y
			textLabel.BackgroundTransparency = 1
			textLabel.Text                 = ""
			textLabel.Font                 = F.NORMAL
			textLabel.TextSize             = isMobile and 14 or 16
			textLabel.TextColor3           = Color3.fromRGB(230, 230, 230)
			textLabel.TextXAlignment       = Enum.TextXAlignment.Left
			textLabel.TextYAlignment       = Enum.TextYAlignment.Top
			textLabel.TextWrapped          = true
			textLabel.RichText             = true
			textLabel.LayoutOrder          = 1
			textLabel.Parent               = content
			local textPad = Instance.new("UIPadding", textLabel)
			textPad.PaddingTop = UDim.new(0, 10); textPad.PaddingBottom = UDim.new(0, 10)

			local divider = Instance.new("Frame")
			divider.Size             = UDim2.new(1, 0, 0, 1)
			divider.BackgroundColor3 = Color3.fromRGB(80, 55, 20)
			divider.BorderSizePixel  = 0
			divider.LayoutOrder      = 2
			divider.Visible          = false
			divider.Parent           = content

			local choiceFrame = Instance.new("Frame")
			choiceFrame.Size                  = UDim2.new(1, 0, 0, 0)
			choiceFrame.AutomaticSize         = Enum.AutomaticSize.Y
			choiceFrame.BackgroundTransparency = 1
			choiceFrame.LayoutOrder           = 3
			choiceFrame.Parent                = content
			local choiceLayout = Instance.new("UIListLayout", choiceFrame)
			choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
			choiceLayout.Padding   = UDim.new(0, 4)
			local choicePad = Instance.new("UIPadding", choiceFrame)
			choicePad.PaddingTop = UDim.new(0, 8); choicePad.PaddingBottom = UDim.new(0, 10)

			local function closeDialogue() sg:Destroy() end

			local function makeChoiceBtn(text, layoutOrder, color, fn)
				local btn = Instance.new("TextButton")
				btn.Size             = UDim2.new(1, 0, 0, isMobile and 36 or 30)
				btn.BackgroundColor3 = Color3.fromRGB(45, 28, 8)
				btn.BorderSizePixel  = 0
				btn.Text             = "▶  " .. text
				btn.Font             = F.NORMAL
				btn.TextSize         = isMobile and 13 or 14
				btn.TextColor3       = color or Color3.fromRGB(255, 210, 140)
				btn.TextXAlignment   = Enum.TextXAlignment.Left
				btn.RichText         = false
				btn.LayoutOrder      = layoutOrder
				btn.ZIndex           = 2
				btn.Parent           = choiceFrame
				Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
				local pad = Instance.new("UIPadding", btn); pad.PaddingLeft = UDim.new(0, 10)
				btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(80, 52, 15) end)
				btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(45, 28, 8) end)
				btn.MouseButton1Click:Connect(fn)
				return btn
			end

			local fullText = "어서 오십시오, 모험가님!\n저는 이 마을의 무기 장인입니다.\n좋은 무기 하나가 전장에서 목숨을 구하지요.\n무엇을 도와드릴까요?"
			local typingDone = false

			task.spawn(function()
				local displayed = ""
				local i = 1
				while i <= #fullText do
					if fullText:sub(i, i) == "<" then
						local tagEnd = fullText:find(">", i)
						if tagEnd then
							displayed = displayed .. fullText:sub(i, tagEnd)
							i = tagEnd + 1
						else
							displayed = displayed .. fullText:sub(i, i)
							i = i + 1
						end
					else
						displayed = displayed .. fullText:sub(i, i)
						i = i + 1
						textLabel.Text = displayed
						task.wait(0.012)
					end
				end
				textLabel.Text = fullText
				typingDone = true
			end)

			local choicesAdded = false
			local function addChoices()
				if choicesAdded then return end
				choicesAdded = true
				textLabel.Text = fullText
				divider.Visible = true

				makeChoiceBtn("무기를 제작하고 싶습니다.", 1, Color3.fromRGB(255, 200, 100), function()
					closeDialogue()
					local RecipeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("RecipeData"))
					local weaponRecipes = collectWeaponCrafterRecipes(RecipeData)
					UIManager.openWeaponCrafting(weaponRecipes)
				end)
				makeChoiceBtn("아무것도 필요 없습니다.", 2, Color3.fromRGB(160, 160, 160), function()
					closeDialogue()
				end)
			end

			local boxBtn = Instance.new("TextButton")
			boxBtn.Size                 = UDim2.new(1, 0, 0, 80)
			boxBtn.BackgroundTransparency = 1
			boxBtn.Text                 = ""
			boxBtn.ZIndex               = 5
			boxBtn.Parent               = textLabel
			boxBtn.MouseButton1Click:Connect(function()
				if not typingDone then
					typingDone = true
					textLabel.Text = fullText
					task.wait(0.05)
					addChoices()
				else
					addChoices()
				end
			end)

			task.spawn(function()
				while not typingDone do task.wait(0.05) end
				task.wait(0.1)
				addChoices()
			end)
		end)
	end

	-- Drag & Drop global listeners
	UserInputService.InputChanged:Connect(function(input) UIManager.handleDragUpdate(input) end)
	UserInputService.InputEnded:Connect(function(input) UIManager.handleDragEnd(input) end)
end


----------------------------------------------------------------
-- Init
----------------------------------------------------------------
function UIManager.Init()
	if initialized then return end

	LocaleService.Init()

	mainGui = Instance.new("ScreenGui")
	mainGui.Name = "GameUI"
	mainGui.ResetOnSpawn = false
	mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainGui.IgnoreGuiInset = true -- SafeArea 제어를 위해 true 설정
	mainGui.Parent = playerGui
	
	-- 블러 효과 초기화 (Lighting에 추가)
	blurEffect = Lighting:FindFirstChild("UIBlur")
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect")
		blurEffect.Name = "UIBlur"
		blurEffect.Size = 12
		blurEffect.Enabled = false
		blurEffect.Parent = Lighting
	end

	-- [Click-Outside-to-Close] 전역 배경용 전용 레이어 (HUD 뒤에 배치하기 위해 분리)
	local dimGui = Instance.new("ScreenGui")
	dimGui.Name = "GlobalDimGui"
	dimGui.DisplayOrder = -10 -- HUD 및 모든 UI보다 뒤에 배치
	dimGui.IgnoreGuiInset = true
	dimGui.ResetOnSpawn = false
	dimGui.Parent = playerGui

	local globalDim = Instance.new("Frame")
	globalDim.Name = "GlobalDimBackground"
	globalDim.Size = UDim2.new(1, 0, 1, 0)
	globalDim.BackgroundTransparency = 1
	globalDim.BackgroundColor3 = Color3.new(0, 0, 0)
	globalDim.BorderSizePixel = 0
	globalDim.Active = false
	globalDim.Visible = false
	globalDim.Parent = dimGui
	WindowManager.setDimBackground(globalDim)

	-- [Responsive] UIScale 도입
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = mainGui
	
	local function updateScale()
		local viewportSize = workspace.CurrentCamera.ViewportSize
		local baseRes = Vector2.new(1280, 720)
		local scaleX = viewportSize.X / baseRes.X
		local scaleY = viewportSize.Y / baseRes.Y
		local finalScale = math.min(scaleX, scaleY)
		
		-- 모바일은 조금 더 크게 (가독성/터치 영역)
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			finalScale = finalScale * 1.15
		end
		
		uiScale.Scale = math.clamp(finalScale, 0.5, 2.5)
	end
	
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	-- [수정] 기본 로블록스 UI 요소 비활성화 (모바일 쾌적성 극대화)
	local SG = game:GetService("StarterGui")
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
	-- 모바일 점프 버튼 등은 ContextActionService로 제어되거나 HUDUI가 덮어씌움

	-- 신규 모듈형 UI 초기화 (안전한 래퍼 도입으로 특정 모듈 에러가 전체 파이프라인을 중단하지 않도록 방지)
	local function safeInit(name, module, ...)
		if not module then
			warn(string.format("[UIManager] Module %s is nil, skipping Init", name))
			return
		end
		local initFn = module.Init or module.init
		if type(initFn) ~= "function" then
			warn(string.format("[UIManager] Module %s does not have an Init function", name))
			return
		end
		local success, err = pcall(initFn, ...)
		if not success then
			warn(string.format("[UIManager] Failed to initialize module %s: %s", name, tostring(err)))
		else
			-- print(string.format("[UIManager] Module %s initialized successfully.", name))
		end
	end

	-- 기존 함수 형태(콜백 등)를 위해 pcall로 별도 실행하는 헬퍼
	local function safeCall(name, fn, ...)
		if type(fn) ~= "function" then return end
		local success, err = pcall(fn, ...)
		if not success then
			warn(string.format("[UIManager] safeCall failed for %s: %s", name, tostring(err)))
		end
	end

	safeInit("HUDUI", HUDUI, mainGui, UIManager, InputManager, isMobile)
	safeInit("InventoryUI", InventoryUI, mainGui, UIManager, isMobile)
	safeInit("CraftingUI", CraftingUI, mainGui, UIManager, isMobile)
	safeInit("ShopUI", ShopUI, mainGui, UIManager, isMobile)
	safeInit("InteractUI", InteractUI, mainGui, isMobile)
	safeInit("EquipmentUI", EquipmentUI, mainGui, UIManager, Enums, isMobile)
	if EquipmentUI and EquipmentUI.Refs then
		equipmentUIFrame = EquipmentUI.Refs.Frame
	end
	safeInit("StorageUI", StorageUI, mainGui, UIManager, isMobile)
	safeInit("MaterialSelectUI", MaterialSelectUI, mainGui, UIManager)
	safeInit("PremiumShopUI", PremiumShopUI, mainGui, UIManager)
	safeInit("AuctionUI", AuctionUI, mainGui, UIManager, isMobile)

	safeInit("PortalUI", PortalUI, mainGui, UIManager, isMobile)
	if PortalRadialUI then
		safeCall("PortalRadialUI.Init", function() PortalRadialUI:Init(UIManager) end)
	end
	safeInit("EnhanceUI", EnhanceUI, mainGui, UIManager)
	safeInit("DismantleUI", DismantleUI, mainGui, UIManager)
	safeInit("NPCRadialUI", NPCRadialUI, UIManager)
	safeInit("TentUI", TentUI, UIManager)
	safeInit("SkillTreeUI", SkillTreeUI, mainGui, UIManager, isMobile)
	if SkillTreeUI and SkillTreeUI.SetController then
		safeCall("SkillTreeUI.SetController", function() SkillTreeUI.SetController(SkillController) end)
	end
	safeInit("PromptUI", PromptUI)
	safeCall("UILocalizer.StartAuto", function() UILocalizer.StartAuto(mainGui) end)

	safeInit("StorageController", StorageController)


	-- 슬롯 참조만 유지 (드래그 앤 드롭 및 리프레시 로직용)
	hotbarSlots = HUDUI.Refs.hotbarSlots
	invSlots = InventoryUI.Refs.Slots
	equipSlots = EquipmentUI.Refs.Slots
	
	-- Tutorial Aliases
	HUDUI.Refs.QuickCraftTab = InventoryUI.Refs.TabCraft
	HUDUI.Refs.CraftStartButton = InventoryUI.Refs.Detail.BtnMain
	
	-- Personal Crafting references
	invPersonalCraftGrid = InventoryUI.Refs.CraftGrid
	invCraftContainer = InventoryUI.Refs.CraftFrame
	invDetailPanel = InventoryUI.Refs.Detail.Frame
	
	setupEventListeners()

	UIManager.refreshInventory()
	UIManager.refreshHotbar()
	if HUDUI and HUDUI.UpdateRuneHotbar then HUDUI.UpdateRuneHotbar(InventoryController.getEquipment()) end
	-- UIManager.updateHealth(100,100) -- 제거: 캐릭터 스폰 리스너에서 처리함
	UIManager.updateStamina(100,100)
	UIManager.updateXP(0,100)
	UIManager.updateLevel(1)
	task.spawn(function()
		local ok, data = NetClient.Request("Tutorial.GetStatus.Request", {})
		if ok and data then
			UIManager.updateTutorialStatus(data)
		end
	end)
	
	-- 알림 라벨 (사용 중단되거나 제거)
	UIManager._notifyLabel = nil

	-- [Refactor] WindowManager 창 등록 (관리 생산성 극대화)
	WindowManager.onUpdate(updateUIMode)
	WindowManager.register("INV", UIManager._onOpenInventory, UIManager._onCloseInventory)
	WindowManager.register("EQUIP", UIManager._onOpenEquipment, UIManager._onCloseEquipment)
	WindowManager.register("SHOP", UIManager._onOpenShop, UIManager._onCloseShop)
	WindowManager.register("PREMIUM_SHOP", UIManager._onOpenPremiumShop, UIManager._onClosePremiumShop)
	WindowManager.register("STORAGE", UIManager._onOpenStorage, UIManager._onCloseStorage)
	WindowManager.register("CRAFTING", UIManager._OnOpenCrafting, UIManager._OnCloseCrafting)
	WindowManager.register("PORTAL", UIManager._onOpenPortal, UIManager._onClosePortal)
	WindowManager.register("SKILL", UIManager._onOpenSkillTree, UIManager._onCloseSkillTree)
	WindowManager.register("ENHANCE", UIManager._onOpenEnhance, UIManager._onCloseEnhance)
	WindowManager.register("DISMANTLE", UIManager._onOpenDismantle, UIManager._onCloseDismantle)
	WindowManager.register("AUCTION", UIManager._onOpenAuctionHouse, UIManager._onCloseAuctionHouse)

	-- [NEW] 상호작용 방사형 UI 등록
	WindowManager.register("PORTAL_RADIAL", function(...) PortalRadialUI:Open(...) end, PortalRadialUI.Close)
	WindowManager.register("NPC_RADIAL", NPCRadialUI.Open, NPCRadialUI.Close)
	WindowManager.register("TENT_UI", TentUI.Open, TentUI.Close)

	-- ★ 오픈/닫기 애니메이션용 메인 패널 프레임 등록
	-- 오버레이 구조(INV, BUILD 등): 첫 자식 윈도우가 애니 대상
	-- 직접 윈도우 구조(TOTEM, PORTAL): Frame 자체가 애니 대상
	task.defer(function()
		-- 오버레이 내부의 메인 윈도우 패널 검색 헬퍼
		local function findMainPanel(overlay)
			if not overlay then return nil end
			local main = overlay:FindFirstChild("Main")
			if main and (main:IsA("Frame") or main:IsA("CanvasGroup")) then
				return main
			end
			for _, child in ipairs(overlay:GetChildren()) do
				if child:IsA("Frame") or child:IsA("CanvasGroup") then
					return child
				end
			end
			return nil
		end

		-- 오버레이 구조 UI들 (Refs.Frame이 전체 오버레이)
		WindowManager.registerFrame("INV", findMainPanel(InventoryUI.Refs.Frame))
		WindowManager.registerFrame("EQUIP", findMainPanel(EquipmentUI.Refs.Frame))
		WindowManager.registerFrame("SHOP", findMainPanel(ShopUI.Refs.Frame))
		WindowManager.registerFrame("STORAGE", findMainPanel(StorageUI.Refs.Frame))
		WindowManager.registerFrame("CRAFTING", findMainPanel(CraftingUI.Refs.Frame))

		WindowManager.registerFrame("SKILL", findMainPanel(SkillTreeUI.Refs.Frame))
		WindowManager.registerFrame("AUCTION", findMainPanel(AuctionUI.Refs.Frame))

		-- 직접 윈도우 구조 UI들 (Refs.Frame이 곧 패널)
		WindowManager.registerFrame("PORTAL", PortalUI.Refs.Frame)
		WindowManager.registerFrame("PREMIUM_SHOP", PremiumShopUI.Refs.Frame)
		WindowManager.registerFrame("ENHANCE", EnhanceUI.Refs.Frame)
		WindowManager.registerFrame("DISMANTLE", DismantleUI.Refs.Frame)
		WindowManager.registerFrame("TENT_UI", TentUI.Refs.Window)
	end)

	-- [Refactor] DragDropController 초기화
	DragDropController.Init(UIManager, InventoryController, Balance, mainGui)

	initialized = true
	print("[UIManager] Initialized — WindowManager & Controllers decoupled")
end

function UIManager.hideAllLoading()
	if craftSpinner then
		craftSpinner.Visible = false
	end
	-- 추가적인 로딩 UI가 있다면 여기서 처리
end

-- =============================================
-- Combat UI Periodic Update
-- =============================================
RunService.RenderStepped:Connect(function()
	if currentCombatCreatureId then
		-- Find creature model by instanceId
		local creatureModel = nil
		local workspace_creatures = workspace:FindFirstChild("Creatures")
		
		if workspace_creatures then
			for _, model in ipairs(workspace_creatures:GetDescendants()) do
				if model:IsA("Model") and model:GetAttribute("InstanceId") == currentCombatCreatureId then
					creatureModel = model
					break
				end
			end
		end
		
		if not creatureModel then
			for _, child in ipairs(workspace:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("InstanceId") == currentCombatCreatureId then
					creatureModel = child
					break
				end
			end
		end
		
		if creatureModel then
			local currentHP = creatureModel:GetAttribute("CurrentHealth") or 0
			local maxHP = creatureModel:GetAttribute("MaxHealth") or 100
			HUDUI.UpdateCombatUI(currentHP, maxHP)
		end
	end
end)

-- (Animal Management removed)

----------------------------------------------------------------
-- 사냥 통계 (Monster Hunt Stats)
----------------------------------------------------------------
local statsOverlay = nil

function UIManager.toggleQuest()
	if statsOverlay then
		statsOverlay:Destroy()
		statsOverlay = nil
		return
	end
	
	-- 1. Fetch latest stats (including mobKills)
	local ok, d = NetClient.Request("Player.Stats.Request", {})
	if not ok or not d or not d.mobKills then
		UIManager.notify("통계 정보를 불러오지 못했습니다.", C.RED)
		return
	end
	
	-- Navy + Black Theme matching the UI
	local C_Override = {}
	for k, v in pairs(C) do C_Override[k] = v end
	C_Override.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
	C_Override.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
	C_Override.BG_SLOT = Color3.fromRGB(15, 20, 35)  -- Deep Navy
	C_Override.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White
	C_Override.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
	C_Override.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
	
	-- 2. Create Overlay
	statsOverlay = Utils.mkFrame({
		name = "StatsOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.6,
		z = 100,
		parent = mainGui
	})
	
	local winWidth = isMobile and 0.94 or 0.45
	local winHeight = isMobile and 0.90 or 0.65
	local maxW = isMobile and 760 or 500
	local maxH = isMobile and 760 or 450
	
	local main = Utils.mkWindow({
		name = "StatsWindow",
		size = UDim2.new(winWidth, 0, winHeight, 0),
		maxSize = Vector2.new(maxW, maxH),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C_Override.BG_PANEL,
		stroke = 2,
		strokeC = C_Override.BORDER,
		r = 10,
		parent = statsOverlay
	})
	
	-- Close button on overlay click
	local bgBtn = Instance.new("TextButton")
	bgBtn.Size = UDim2.new(1, 0, 1, 0)
	bgBtn.BackgroundTransparency = 1
	bgBtn.Text = ""
	bgBtn.ZIndex = 1
	bgBtn.Parent = statsOverlay
	bgBtn.MouseButton1Click:Connect(function()
		if statsOverlay then
			statsOverlay:Destroy()
			statsOverlay = nil
		end
	end)
	
	main.ZIndex = 2
	
	-- Title
	Utils.mkLabel({
		text = UILocalizer.Localize("사냥 통계 (Monster Hunt Stats)"),
		size = UDim2.new(1, 0, 0, isMobile and 58 or 50),
		pos = UDim2.new(0, 0, 0, isMobile and 12 or 15),
		ts = isMobile and 24 or 22,
		font = F.TITLE,
		color = Color3.fromRGB(255, 215, 0), -- Gold Title
		ax = Enum.TextXAlignment.Center,
		parent = main
	})
	
	-- Close Button (X) inside Window
	local closeBtn = Utils.mkBtn({
		name = "CloseBtn",
		text = "X",
		size = UDim2.new(0, isMobile and 40 or 30, 0, isMobile and 40 or 30),
		pos = UDim2.new(1, isMobile and -10 or -15, 0, isMobile and 10 or 15),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		stroke = false,
		ts = isMobile and 22 or 18,
		font = F.TITLE,
		color = Color3.fromRGB(200, 200, 200),
		fn = function()
			if statsOverlay then
				statsOverlay:Destroy()
				statsOverlay = nil
			end
		end,
		parent = main
	})
	
	-- Scrollable frame for list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, isMobile and -20 or -40, 1, isMobile and -92 or -100)
	scroll.Position = UDim2.new(0.5, 0, 0, isMobile and 74 or 80)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = isMobile and 8 or 4
	scroll.ScrollBarImageColor3 = C_Override.BORDER
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ClipsDescendants = true
	scroll.Parent = main
	
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 5)
	scrollPad.PaddingBottom = UDim.new(0, 5)
	scrollPad.PaddingLeft = UDim.new(0, 10)
	scrollPad.PaddingRight = UDim.new(0, 15)
	scrollPad.Parent = scroll
	
	local vList = Instance.new("UIListLayout")
	vList.FillDirection = Enum.FillDirection.Vertical
	vList.Padding = UDim.new(0, 10)
	vList.Parent = scroll
	
	-- Populate kills list
	local sortedKills = {}
	if d.mobKills then
		for mobName, kills in pairs(d.mobKills) do
			table.insert(sortedKills, { name = mobName, count = kills })
		end
	end
	table.sort(sortedKills, function(a, b) return a.count > b.count end)
	
	if #sortedKills == 0 then
		Utils.mkLabel({
			text = UILocalizer.Localize("아직 처치한 몬스터가 없습니다."),
			size = UDim2.new(1, 0, 0, 50),
			pos = UDim2.new(0, 0, 0.4, 0),
			ts = isMobile and 18 or 16,
			font = F.TITLE,
			color = Color3.fromRGB(150, 150, 150),
			ax = Enum.TextXAlignment.Center,
			parent = scroll
		})
	else
		for _, entry in ipairs(sortedKills) do
			local row = Utils.mkFrame({
				name = "MobKillRow",
				size = UDim2.new(1, 0, 0, isMobile and 58 or 45),
				bg = C_Override.BG_SLOT,
				bgT = 0.2,
				r = 6,
				stroke = 1,
				strokeC = C_Override.BORDER,
				parent = scroll
			})
			
			local textLabel = Utils.mkLabel({
				text = UILocalizer.Localize(entry.name),
				size = UDim2.new(0.7, 0, 1, 0),
				pos = UDim2.new(0, 15, 0, 0),
				ts = isMobile and 18 or 15,
				font = F.TITLE,
				color = C_Override.GOLD,
				ax = Enum.TextXAlignment.Left,
				parent = row
			})
			
			local countLabel = Utils.mkLabel({
				text = tostring(entry.count),
				size = UDim2.new(0.2, 0, 1, 0),
				pos = UDim2.new(1, -15, 0, 0),
				anchor = Vector2.new(1, 0),
				ts = isMobile and 18 or 15,
				font = F.NUM,
				color = Color3.fromRGB(120, 220, 100), -- Greenish color for kills
				ax = Enum.TextXAlignment.Right,
				parent = row
			})
		end
	end
end

----------------------------------------------------------------
-- 프리미엄 상점 (Premium Shop)
----------------------------------------------------------------
function UIManager.togglePremiumShop()
	if WindowManager.isOpen("PREMIUM_SHOP") then
		UIManager.closePremiumShop()
	else
		UIManager.openPremiumShop()
	end
end

function UIManager.openPremiumShop()
	WindowManager.closeOthers({"PREMIUM_SHOP"})
	PremiumShopUI.Refresh(UIManager.getItemIcon)
	PremiumShopUI.SetVisible(true)
	WindowManager.open("PREMIUM_SHOP")
	ShopController.requestGold(function(ok, gold)
		if ok then
			UIManager.updateGold(gold)
		end
	end)
	
	updateUIMode()
end

function UIManager.closePremiumShop()
	PremiumShopUI.SetVisible(false)
	WindowManager.close("PREMIUM_SHOP")
	
	updateUIMode()
end

----------------------------------------------------------------
-- Enhancement (Alchemy)
----------------------------------------------------------------

local activeSelectorCallback = nil
local activeSelectorMode = nil -- "WEAPON" or "STONE"

function UIManager.openItemSelector(mode, callback)
	if selectorOverlay then selectorOverlay:Destroy() end
	activeSelectorCallback = callback
	activeSelectorMode = mode
	
	-- Local Color Override for Navy + Black Theme (Match Equipment/SkillTree UI)
	local C_Override = {}
	for k, v in pairs(Theme.Colors) do C_Override[k] = v end
	C_Override.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
	C_Override.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
	C_Override.BG_SLOT = Color3.fromRGB(15, 20, 35)  -- Deep Navy
	C_Override.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White!
	C_Override.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
	C_Override.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
	C_Override.BORDER_DIM = Color3.fromRGB(30, 45, 70)
	
	local C = C_Override
	
	-- 1. 오버레이 생성
	selectorOverlay = Utils.mkFrame({
		name = "ItemSelectorOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.6,
		z = 100,
		parent = mainGui
	})
	
	local main = Utils.mkWindow({
		name = "SelectorWindow",
		size = UDim2.new(0.6, 0, 0.7, 0),
		maxSize = Vector2.new(600, 500),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		stroke = 2,
		strokeC = C.BORDER,
		r = 10,
		parent = selectorOverlay
	})
	
	local titles = {
		WEAPON = "강화할 무기 선택",
		ALCHEMY_STONE = "사용할 연금석 선택",
		ENHANCE_SCROLL = "사용할 주문서 선택",
		DOWN_PROTECT = "하락 방지 주문서 선택",
		DESTROY_PROTECT = "파괴 방지 주문서 선택",
	}
	local titleStr = titles[mode] or "아이템 선택"
	
	Utils.mkLabel({
		text = UILocalizer.Localize(titleStr),
		size = UDim2.new(1, 0, 0, 50),
		pos = UDim2.new(0, 0, 0, 10),
		ts = 22,
		font = Theme.Fonts.TITLE,
		color = C.GOLD, -- Now White
		ax = Enum.TextXAlignment.Center,
		parent = main
	})
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -120)
	scroll.Position = UDim2.new(0.5, 0, 0, 65)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.BORDER -- Styled with Light Navy Scrollbar
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ClipsDescendants = true
	scroll.Parent = main
	
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 5)
	scrollPad.PaddingBottom = UDim.new(0, 5)
	scrollPad.PaddingLeft = UDim.new(0, 5)
	scrollPad.PaddingRight = UDim.new(0, 10)
	scrollPad.Parent = scroll
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 80, 0, 80)
	grid.CellPadding = UDim2.new(0, 15, 0, 15)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroll
	
	-- 2. 아이템 필터링 및 생성
	local cache = InventoryController.getInventoryCache()
	local found = false
	
	-- [장착 장비 HAND 특화 지원]
	if mode == "WEAPON" or mode == "REPAIR" then
		local equipHand = InventoryController.getEquipment().HAND
		if equipHand and equipHand.itemId then
			local itemData = DataHelper.GetData("ItemData", equipHand.itemId)
			local isValid = false
			if mode == "WEAPON" then
				if itemData and (itemData.type == "WEAPON" or itemData.type == "TOOL") then
					isValid = true
				end
			elseif mode == "REPAIR" then
				if itemData and (itemData.type == "WEAPON" or itemData.type == "TOOL" or itemData.type == "ARMOR") then
					isValid = true
				end
			end
			
			if isValid then
				found = true
				local btn = Utils.mkFrame({
					name = "Slot_HAND",
					size = UDim2.new(0, 80, 0, 80),
					bg = C.BG_SLOT,
					bgT = 0.2,
					r = 6,
					stroke = 2,
					strokeC = C.GOLD_SEL, -- Styled with accent blue border for selection
					parent = scroll
				})
				
				local icon = Instance.new("ImageLabel")
				icon.Size = UDim2.new(0.8, 0, 0.8, 0)
				icon.Position = UDim2.new(0.5, 0, 0.5, 0)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.BackgroundTransparency = 1
				icon.Image = UIManager.getItemIcon(equipHand.itemId)
				icon.Parent = btn
				
				-- Equipped badge
				Utils.mkLabel({
					text = UILocalizer.Localize("[장착중]"),
					size = UDim2.new(1, 0, 0, 20),
					pos = UDim2.new(0, 0, 0, 2),
					ts = 11,
					font = Theme.Fonts.TITLE,
					color = Color3.fromRGB(80, 180, 255), -- Sky blue
					ax = Enum.TextXAlignment.Center,
					parent = btn
				})
				
				-- Enhance level indicator
				if equipHand.attributes and equipHand.attributes.enhanceLevel and equipHand.attributes.enhanceLevel > 0 then
					Utils.mkLabel({
						text = "+" .. equipHand.attributes.enhanceLevel,
						size = UDim2.new(0, 30, 0, 20),
						pos = UDim2.new(1, -2, 1, -2),
						anchor = Vector2.new(1, 1),
						ts = 14,
						font = Theme.Fonts.TITLE,
						color = Color3.fromRGB(240, 240, 240), -- White
						parent = btn
					})
				end
				
				local click = Instance.new("TextButton")
				click.Size = UDim2.new(1, 0, 1, 0)
				click.BackgroundTransparency = 1
				click.Text = ""
				click.Parent = btn
				
				click.MouseButton1Click:Connect(function()
					selectorOverlay:Destroy()
					selectorOverlay = nil
					local cb = activeSelectorCallback
					activeSelectorCallback = nil
					activeSelectorMode = nil
					cb("HAND", equipHand)
				end)
			end
		end
	end
	
	for slot, data in pairs(cache) do
		local isValid = false
		local itemData = DataHelper.GetData("ItemData", data.itemId)
		
		if mode == "WEAPON" then
			if itemData and (itemData.type == "WEAPON" or itemData.type == "TOOL") then
				isValid = true
			end
		elseif mode == "ALCHEMY_STONE" then
			if itemData and itemData.type == "ENHANCE_MATERIAL" then
				isValid = true
			elseif data.itemId and data.itemId:find("ALCHEMY_STONE") then
				isValid = true
			end
		elseif mode == "ENHANCE_SCROLL" then
			if itemData and itemData.type == "ENHANCE_SCROLL" then
				isValid = true
			elseif data.itemId == "3586927112" or data.itemId == "3586927381" or data.itemId == "3602118498" then
				isValid = true
			elseif data.itemId and data.itemId:find("SCROLL") then
				isValid = true
			end
		elseif mode == "DOWN_PROTECT" then
			if data.itemId == "3586927112" or data.itemId == "3602118498" then
				isValid = true
			elseif itemData and itemData.type == "ENHANCE_SCROLL" and itemData.isDownProtect then
				isValid = true
			end
		elseif mode == "DESTROY_PROTECT" then
			if data.itemId == "3586927381" then
				isValid = true
			elseif itemData and itemData.type == "ENHANCE_SCROLL" and itemData.isDestroyProtect then
				isValid = true
			end
		elseif mode == "REPAIR" then
			if itemData and (itemData.type == "WEAPON" or itemData.type == "TOOL" or itemData.type == "ARMOR") then
				isValid = true
			end
		end
		
		if isValid then
			found = true
			local btn = Utils.mkFrame({
				name = "Slot_" .. slot,
				size = UDim2.new(0, 80, 0, 80),
				bg = C.BG_SLOT,
				bgT = 0.2,
				r = 6,
				stroke = 1,
				strokeC = C.BORDER,
				parent = scroll
			})
			
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0.8, 0, 0.8, 0)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.BackgroundTransparency = 1
			icon.Image = UIManager.getItemIcon(data.itemId)
			icon.Parent = btn
			
			-- 강화 수치 표시
			if data.attributes and data.attributes.enhanceLevel and data.attributes.enhanceLevel > 0 then
				Utils.mkLabel({
					text = "+" .. data.attributes.enhanceLevel,
					size = UDim2.new(0, 30, 0, 20),
					pos = UDim2.new(1, -2, 1, -2),
					anchor = Vector2.new(1, 1),
					ts = 14,
					font = Theme.Fonts.TITLE,
					color = Color3.fromRGB(240, 240, 240), -- White
					parent = btn
				})
			end
			
			local click = Instance.new("TextButton")
			click.Size = UDim2.new(1, 0, 1, 0)
			click.BackgroundTransparency = 1
			click.Text = ""
			click.Parent = btn
			
			click.MouseButton1Click:Connect(function()
				selectorOverlay:Destroy()
				selectorOverlay = nil
				local cb = activeSelectorCallback
				activeSelectorCallback = nil
				activeSelectorMode = nil
				cb(slot, data)
			end)
		end
	end
	
	if not found then
		Utils.mkLabel({
			text = UILocalizer.Localize("선택 가능한 아이템이 없습니다."),
			size = UDim2.new(1, 0, 0, 100),
			pos = UDim2.new(0, 0, 0, 80),
			ts = 16,
			color = C_Override.GRAY,
			ax = Enum.TextXAlignment.Center,
			parent = scroll
		})
	end
	
	local cancel = Utils.mkBtn({
		text = UILocalizer.Localize("취소"),
		size = UDim2.new(0, 150, 0, 40),
		pos = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
		bg = C.BG_DARK,
		color = C.WHITE, -- Fixed contrast: white text on dark background
		ts = 18,
		fn = function()
			selectorOverlay:Destroy()
			selectorOverlay = nil
			activeSelectorCallback = nil
			activeSelectorMode = nil
		end,
		parent = main
	})
end

function UIManager.closeItemSelector()
	if selectorOverlay then
		selectorOverlay:Destroy()
		selectorOverlay = nil
		activeSelectorCallback = nil
		activeSelectorMode = nil
	end
end
function UIManager.requestEnhance(weaponSlot, stoneSlot, callback, scrolls)
	task.spawn(function()
		local success, result = NetClient.Request("Enhance.Request", {
			weaponSlot = weaponSlot,
			stoneSlot = stoneSlot,
			scrolls = scrolls
		})
		if callback then
			callback(success, result)
		end
	end)
end

function UIManager.showEnhanceResult(result, data)
	if not mainGui then return end
	
	local overlay = Utils.mkFrame({
		name = "EnhanceResultOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 1,
		z = 1000,
		useCanvas = true,
		parent = mainGui
	})
	overlay.GroupTransparency = 1
	
	local bgDim = Utils.mkFrame({
		name = "Dim",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.5,
		parent = overlay
	})
	
	local center = Utils.mkFrame({
		name = "Center",
		size = UDim2.new(0.6, 0, 0.4, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgT = 1,
		parent = overlay
	})
	
	local isSuccess = (result == "SUCCESS")
	local isProtected = (result == "PROTECTED")
	local isDestroyed = (result == "DESTROYED")
	
	local titleText = ""
	local titleColor = C.WHITE
	
	if isSuccess then
		titleText = "연금 성공!"
		titleColor = C.GOLD
	elseif isProtected then
		titleText = "하락 방지 성공!"
		titleColor = C.GOLD
	elseif isDestroyed then
		titleText = "아이템 파괴!"
		titleColor = C.RED
	else
		titleText = "연금 실패"
		titleColor = C.WHITE
	end
	
	-- Glow Effect for Success
	if isSuccess then
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.Size = UDim2.new(1.5, 0, 2.5, 0)
		glow.Position = UDim2.new(0.5, 0, 0.5, 0)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BackgroundTransparency = 1
		glow.Image = "rbxassetid://352348164"
		glow.ImageColor3 = C.GOLD
		glow.ImageTransparency = 0.6
		glow.Parent = center
	end
	
	local title = Utils.mkLabel({
		text = UILocalizer.Localize(titleText),
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 64, -- Even bigger
		font = Theme.Fonts.TITLE,
		color = titleColor,
		parent = center
	})
	
	-- Success subtitle (New Level)
	if (isSuccess or isProtected) and data and data.newLevel then
		Utils.mkLabel({
			text = isProtected and ("+" .. data.newLevel .. " 유지") or ("+" .. data.newLevel),
			size = UDim2.new(1, 0, 0, 40),
			pos = UDim2.new(0.5, 0, 0.75, 0),
			anchor = Vector2.new(0.5, 0.5),
			ts = 32,
			color = C.GOLD,
			parent = center
		})
	end
	
	-- Animations
	TweenService:Create(overlay, TweenInfo.new(0.3), {GroupTransparency = 0}):Play()
	
	task.delay(2.5, function()
		if overlay and overlay.Parent then
			local t = TweenService:Create(overlay, TweenInfo.new(0.5), {GroupTransparency = 1})
			t:Play()
			t.Completed:Wait()
			if overlay and overlay.Parent then overlay:Destroy() end
		end
	end)
	
	-- Close on click
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = overlay
	btn.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)
end

function UIManager.getItemName(itemId)
	local data = DataHelper.GetData("ItemData", itemId)
	if data and data.name then
		return UILocalizer.LocalizeDataText("ItemData", tostring(itemId), "name", data.name)
	end
	
	-- ItemData에 없으면 ProductConfig 확인 (로벅스 아이템 등)
	local ProductConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ProductConfig"))
	local pData = ProductConfig.PRODUCTS[tostring(itemId)]
	if pData and pData.name then
		return UILocalizer.Localize(pData.name)
	end
	
	return tostring(itemId)
end


function UIManager.showEnhanceConfirm(params)
	if not mainGui then return end
	
	local overlay = Utils.mkFrame({
		name = "EnhanceConfirmOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.6,
		z = 2000,
		parent = mainGui
	})
	
	local win = Utils.mkWindow({
		name = "ConfirmWindow",
		size = UDim2.new(0, 400, 0, 320),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		stroke = 2,
		strokeC = C.BORDER,
		r = 8,
		parent = overlay
	})
	
	Utils.mkLabel({
		text = UILocalizer.Localize(params.title or "연금 강화 확인"),
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		ts = 20,
		font = Theme.Fonts.TITLE,
		color = C.WHITE,
		parent = win
	})
	
	local content = Utils.mkLabel({
		text = params.message,
		size = UDim2.new(0.9, 0, 0, 140),
		pos = UDim2.new(0.5, 0, 0.45, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 16,
		color = C.WHITE,
		rich = true,
		wrap = true,
		parent = win
	})
	
	local btnWrap = Utils.mkFrame({
		size = UDim2.new(1, -40, 0, 50),
		pos = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = win
	})
	
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 20)
	list.Parent = btnWrap
	
	local cancelBtn = Utils.mkBtn({
		text = UILocalizer.Localize("취소"),
		size = UDim2.new(0, 120, 1, 0),
		bg = C.BG_SLOT,
		color = C.WHITE,
		ts = 16,
		fn = function() overlay:Destroy() if params.onCancel then params.onCancel() end end,
		parent = btnWrap
	})
	
	local confirmBtn = Utils.mkBtn({
		text = UILocalizer.Localize("확인"),
		size = UDim2.new(0, 120, 1, 0),
		bg = C.BTN,
		color = C.WHITE,
		ts = 16,
		fn = function()
			overlay:Destroy()
			if params.onConfirm then params.onConfirm() end
		end,
		parent = btnWrap
	})
end

function UIManager.showDismantleConfirm(params)
	if not mainGui then return end
	
	local overlay = Utils.mkFrame({
		name = "DismantleConfirmOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.6,
		z = 2000,
		parent = mainGui
	})
	
	-- 테두리 컨벤션에 맞춘 네이비/블루 창 레이아웃
	local win = Utils.mkWindow({
		name = "ConfirmWindow",
		size = UDim2.new(0, 400, 0, 320),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		stroke = 2,
		strokeC = Color3.fromRGB(60, 85, 130), -- 테두리 블루 컨벤션 정확히 매칭!
		r = 10,
		parent = overlay
	})
	
	Utils.mkLabel({
		text = UILocalizer.Localize("무기 분해 확인"), -- 연금 강화 확인이 아님!
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		ts = 20,
		font = Theme.Fonts.TITLE,
		color = C.WHITE, -- 노란색 제목이 아닌 깔끔한 흰색 적용
		parent = win
	})
	
	local content = Utils.mkLabel({
		text = params.message,
		size = UDim2.new(0.9, 0, 0, 140),
		pos = UDim2.new(0.5, 0, 0.45, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 15,
		color = Color3.fromRGB(220, 220, 220),
		rich = true,
		wrap = true,
		parent = win
	})
	
	local btnWrap = Utils.mkFrame({
		size = UDim2.new(1, -40, 0, 50),
		pos = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = win
	})
	
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 20)
	list.Parent = btnWrap
	
	local cancelBtn = Utils.mkBtn({
		text = UILocalizer.Localize("취소"),
		size = UDim2.new(0, 120, 1, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = 16,
		fn = function() overlay:Destroy() if params.onCancel then params.onCancel() end end,
		parent = btnWrap
	})
	
	local confirmBtn = Utils.mkBtn({
		text = UILocalizer.Localize("확인"),
		size = UDim2.new(0, 120, 1, 0),
		bg = Color3.fromRGB(40, 80, 160),
		hbg = Color3.fromRGB(60, 100, 180),
		color = C.WHITE,
		ts = 16,
		fn = function()
			overlay:Destroy()
			if params.onConfirm then params.onConfirm() end
		end,
		parent = btnWrap
	})
end

function UIManager.showDropConfirm(params)
	local overlay = Utils.mkFrame({
		name = "DropConfirmOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.5,
		z = 2000,
		parent = mainGui
	})
	
	local win = Utils.mkWindow({
		name = "ConfirmWindow",
		size = UDim2.new(0, 400, 0, 320),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		stroke = 2,
		strokeC = Color3.fromRGB(60, 85, 130),
		r = 10,
		parent = overlay
	})
	
	Utils.mkLabel({
		text = UILocalizer.Localize("아이템 버리기 경고"),
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		ts = 20,
		font = Theme.Fonts.TITLE,
		color = C.WHITE,
		parent = win
	})
	
	local content = Utils.mkLabel({
		text = params.message or UILocalizer.Localize("교환 불가 아이템은 버리면 소멸됩니다. 버리시겠습니까?"),
		size = UDim2.new(0.9, 0, 0, 140),
		pos = UDim2.new(0.5, 0, 0.45, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 15,
		color = Color3.fromRGB(220, 220, 220),
		rich = true,
		wrap = true,
		parent = win
	})
	
	local btnWrap = Utils.mkFrame({
		size = UDim2.new(1, -40, 0, 50),
		pos = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = win
	})
	
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 20)
	list.Parent = btnWrap
	
	local cancelBtn = Utils.mkBtn({
		text = UILocalizer.Localize("취소"),
		size = UDim2.new(0, 120, 1, 0),
		bg = C.BG_SLOT,
		hbg = C.BTN_GRAY_H,
		color = C.WHITE,
		isNegative = true,
		ts = 16,
		fn = function() overlay:Destroy() if params.onCancel then params.onCancel() end end,
		parent = btnWrap
	})
	
	local confirmBtn = Utils.mkBtn({
		text = UILocalizer.Localize("확인"),
		size = UDim2.new(0, 120, 1, 0),
		bg = Color3.fromRGB(180, 50, 50),
		hbg = Color3.fromRGB(210, 70, 70),
		color = C.WHITE,
		ts = 16,
		fn = function()
			overlay:Destroy()
			if params.onConfirm then params.onConfirm() end
		end,
		parent = btnWrap
	})
end

--========================================
-- 레벨업 이펙트 (캐릭터 몸 빛 + 머리 위 BillboardGui)
--========================================
do
	local levelUpPlaying = false

	function UIManager.showLevelUpEffect(newLevel)
		if levelUpPlaying then return end
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		local head = char and char:FindFirstChild("Head")
		if not hrp or not head then return end
		levelUpPlaying = true

		-- ── 1) Highlight: 몸 전체 흰색 빛 ──
		local highlight = Instance.new("Highlight")
		highlight.Adornee             = char
		highlight.FillColor           = Color3.fromRGB(255, 255, 255)
		highlight.OutlineColor        = Color3.fromRGB(220, 235, 255)
		highlight.FillTransparency    = 0.2
		highlight.OutlineTransparency = 0
		highlight.Parent              = char

		-- ── 2) PointLight: 흰 발광 ──
		local light = Instance.new("PointLight")
		light.Color      = Color3.fromRGB(210, 230, 255)
		light.Brightness = 10
		light.Range      = 22
		light.Parent     = hrp

		-- ── 3) ParticleEmitter: 흰 빛 입자 ──
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color          = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 220, 255)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(180, 200, 255)),
		})
		emitter.LightEmission  = 1
		emitter.LightInfluence = 0
		emitter.Size           = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   0.18),
			NumberSequenceKeypoint.new(0.5, 0.22),
			NumberSequenceKeypoint.new(1,   0),
		})
		emitter.Transparency   = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   0.05),
			NumberSequenceKeypoint.new(0.7, 0.5),
			NumberSequenceKeypoint.new(1,   1),
		})
		emitter.Speed       = NumberRange.new(5, 12)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Lifetime    = NumberRange.new(0.4, 0.8)
		emitter.Rate        = 80
		emitter.RotSpeed    = NumberRange.new(-180, 180)
		emitter.Rotation    = NumberRange.new(0, 360)
		emitter.Parent      = hrp

		-- ── 4) BillboardGui: 머리 위 텍스트 ──
		local billboard = Instance.new("BillboardGui")
		billboard.Adornee      = head
		billboard.Size         = UDim2.new(0, 220, 0, 80)
		billboard.StudsOffset  = Vector3.new(0, 2.5, 0)
		billboard.AlwaysOnTop  = true
		billboard.ResetOnSpawn = false
		billboard.Parent       = head

		local levelUpLbl = Instance.new("TextLabel")
		levelUpLbl.Size                   = UDim2.new(1, 0, 0.5, 0)
		levelUpLbl.Position               = UDim2.new(0, 0, 0, 0)
		levelUpLbl.BackgroundTransparency = 1
		levelUpLbl.Text                   = "LEVEL UP"
		levelUpLbl.Font                   = Enum.Font.GothamBold
		levelUpLbl.TextSize               = 22
		levelUpLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
		levelUpLbl.TextStrokeTransparency = 0.3
		levelUpLbl.TextStrokeColor3       = Color3.fromRGB(80, 110, 180)
		levelUpLbl.TextTransparency       = 1
		levelUpLbl.Parent                 = billboard

		local lvNumLbl = Instance.new("TextLabel")
		lvNumLbl.Size                   = UDim2.new(1, 0, 0.5, 0)
		lvNumLbl.Position               = UDim2.new(0, 0, 0.5, 0)
		lvNumLbl.BackgroundTransparency = 1
		lvNumLbl.Text                   = "Lv. " .. tostring(newLevel)
		lvNumLbl.Font                   = Enum.Font.GothamBold
		lvNumLbl.TextSize               = 26
		lvNumLbl.TextColor3             = Color3.fromRGB(220, 235, 255)
		lvNumLbl.TextStrokeTransparency = 0.3
		lvNumLbl.TextStrokeColor3       = Color3.fromRGB(60, 90, 160)
		lvNumLbl.TextTransparency       = 1
		lvNumLbl.Parent                 = billboard

		-- ── 5) 애니메이션 (총 ~2초) ──
		task.spawn(function()
			-- 텍스트 페이드인
			TweenService:Create(levelUpLbl, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
			TweenService:Create(lvNumLbl,   TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()

			-- 위로 서서히 상승
			local elapsed = 0
			local riseDur = 1.6
			local startY, endY = 2.5, 5.0
			task.spawn(function()
				while elapsed < riseDur do
					local dt = task.wait()
					elapsed += dt
					local t = math.min(elapsed / riseDur, 1)
					billboard.StudsOffset = Vector3.new(0, startY + (endY - startY) * t, 0)
				end
			end)

			-- Highlight 2회 깜빡임
			for _ = 1, 2 do
				TweenService:Create(highlight, TweenInfo.new(0.15), { FillTransparency = 0.75 }):Play()
				task.wait(0.15)
				TweenService:Create(highlight, TweenInfo.new(0.15), { FillTransparency = 0.15 }):Play()
				task.wait(0.15)
			end

			-- 유지 (짧게)
			task.wait(0.7)

			-- 파티클 중지
			emitter.Enabled = false

			-- 페이드아웃
			TweenService:Create(levelUpLbl, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			TweenService:Create(lvNumLbl,   TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			TweenService:Create(highlight,  TweenInfo.new(0.35), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
			TweenService:Create(light,      TweenInfo.new(0.35), { Brightness = 0 }):Play()
			task.wait(0.4)

			highlight:Destroy()
			light:Destroy()
			emitter:Destroy()
			billboard:Destroy()
			levelUpPlaying = false
		end)
	end
end

return UIManager
