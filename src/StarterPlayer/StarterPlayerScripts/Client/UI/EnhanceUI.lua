-- EnhanceUI.lua
-- 무기 강화 전용 UI 모듈 (1개 무기 슬롯 + 골드 비용 기반)
-- 듀랑고 스타일의 프리미엄 Standalone 창 레이아웃

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))
local ShopController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("ShopController"))
local InventoryController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("InventoryController"))

-- Local Color Override for Navy + Black Theme (Match Equipment/Inventory/WeaponCraft)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
C.BG_SLOT = Color3.fromRGB(12, 12, 15) -- Near Black (Matches Inventory)
C.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White!
C.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN = Color3.fromRGB(40, 80, 160)      -- Action Buttons -> Navy

local F = Theme.Fonts

local EnhanceUI = {}

EnhanceUI.State = {
	selectedWeaponSlot = nil, -- "HAND" 또는 인벤토리 인덱스 번호
	selectedDownProtectSlot = nil,
	lastDownProtectCount = 0,
	pendingDownProtectWarning = false,
	isProcessing = false
}
EnhanceUI.Refs = {}

local UI_MANAGER = nil

-- 아이콘 이미지 설정 헬퍼
local function setIconImage(uiObject, icon)
	if not icon or icon == 0 or icon == "" then
		uiObject.Image = ""
		return
	end
	if type(icon) == "number" then
		uiObject.Image = "rbxassetid://" .. icon
	elseif type(icon) == "string" then
		if icon:match("rbxassetid://") then
			uiObject.Image = icon
		else
			uiObject.Image = "rbxassetid://" .. icon
		end
	end
end

local function getItemDataById(itemId)
	if not itemId then
		return nil
	end

	local ok, DataHelper = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
	end)
	if not ok or not DataHelper then
		return nil
	end

	return DataHelper.GetData("ItemData", itemId)
end

local function findInventoryDownProtect()
	local totalCount = 0
	local foundSlotIdx = nil
	if not UI_MANAGER then return nil, 0 end
	
	local cache = InventoryController.getInventoryCache()
	if cache then
		for slotIdx, slotData in pairs(cache) do
			if slotData and slotData.itemId then
				local itemData = getItemDataById(slotData.itemId)
				if itemData and itemData.type == "ENHANCE_SCROLL" and itemData.isDownProtect then
					local count = math.max(0, math.floor(tonumber(slotData.count) or 0))
					if count > 0 then
						totalCount = totalCount + count
						if not foundSlotIdx then
							foundSlotIdx = slotIdx
						end
					end
				end
			end
		end
	end
	return foundSlotIdx, totalCount
end

local function syncDownProtectSelection(allowPrompt)
	if not UI_MANAGER then
		return false
	end

	local foundSlotIdx, totalCount = findInventoryDownProtect()
	local slotIndex = EnhanceUI.State.selectedDownProtectSlot
	local stroke = EnhanceUI.Refs.ProtectPanel and EnhanceUI.Refs.ProtectPanel:FindFirstChildOfClass("UIStroke")

	if type(slotIndex) ~= "number" then
		EnhanceUI.State.lastDownProtectCount = 0
		if EnhanceUI.Refs.ProtectValue then
			EnhanceUI.Refs.ProtectValue.Text = string.format("%s: %d", UILocalizer.Localize("보유"), totalCount)
		end
		if EnhanceUI.Refs.ProtectButton then
			EnhanceUI.Refs.ProtectButton.Text = UILocalizer.Localize("켜기")
		end
		if stroke then
			stroke.Transparency = 1 -- Hide border
		end
		return false
	end

	-- ON state
	local count = totalCount
	if count > 0 then
		EnhanceUI.State.lastDownProtectCount = count
		EnhanceUI.State.pendingDownProtectWarning = false
		if EnhanceUI.Refs.ProtectValue then
			EnhanceUI.Refs.ProtectValue.Text = string.format("<font color='#FFD700'><b>%s</b></font> (%s: %d)", UILocalizer.Localize("적용 중"), UILocalizer.Localize("보유"), count)
		end
		if EnhanceUI.Refs.ProtectButton then
			EnhanceUI.Refs.ProtectButton.Text = UILocalizer.Localize("끄기")
		end
		if stroke then
			stroke.Transparency = 0 -- Show Navy border
		end
		return true
	else
		-- Count became 0, turn off automatically
		EnhanceUI.State.selectedDownProtectSlot = nil
		EnhanceUI.State.lastDownProtectCount = 0
		if EnhanceUI.Refs.ProtectValue then
			EnhanceUI.Refs.ProtectValue.Text = string.format("%s: 0", UILocalizer.Localize("보유"))
		end
		if EnhanceUI.Refs.ProtectButton then
			EnhanceUI.Refs.ProtectButton.Text = UILocalizer.Localize("켜기")
		end
		if stroke then
			stroke.Transparency = 1 -- Hide border
		end
		return false
	end
end

local function formatVal(num)
	local n = tonumber(num) or 0
	if n >= 1000000000000 then
		return string.format("%.2fT", n / 1000000000000)
	elseif n >= 1000000000 then
		return string.format("%.2fB", n / 1000000000)
	elseif n >= 1000000 then
		return string.format("%.2fM", n / 1000000)
	elseif n >= 1000 then
		local val = n / 1000
		if val % 1 == 0 then
			return string.format("%dK", val)
		else
			local formatted = string.format("%.2f", val)
			formatted = string.gsub(formatted, "%.?0+$", "")
			return formatted .. "K"
		end
	else
		return tostring(math.floor(n))
	end
end

-- 강화 비용 공식 (서버와 동기화)
local function getEnhanceCost(level: number): number
	if level < 5 then
		return 100 + level * 100
	elseif level < 10 then
		return 1000 + (level - 5) * 500
	elseif level < 15 then
		return 5000 + (level - 10) * 2000
	elseif level < 20 then
		return 20000 + (level - 15) * 5000
	else
		return 50000 + (level - 20) * 10000
	end
end

-- 계단식 성공 확률 곡선 (서버와 동기화)
local function getSuccessRate(level: number): number
	if level == 0 then
		return 1.00
	elseif level < 5 then
		return 0.90 - (level - 1) * 0.10
	elseif level < 10 then
		return 0.50 - (level - 5) * 0.06
	elseif level < 15 then
		return 0.20 - (level - 10) * 0.03
	elseif level < 20 then
		return 0.05 - (level - 15) * 0.008
	elseif level < 30 then
		return 0.01
	else
		return 0.002
	end
end

function EnhanceUI.Init(parent, manager)
	UI_MANAGER = manager
	
	-- Standalone Window Frame
	local window = Utils.mkWindow({
		name = "EnhanceWindow",
		size = UDim2.new(0, 400, 0, 560),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.15, -- glassmorphism
		stroke = 2,
		strokeC = C.BORDER,
		r = 10,
		vis = false,
		parent = parent
	})
	EnhanceUI.Refs.Frame = window
	EnhanceUI.Refs.Main = window
	
	-- Header Title
	EnhanceUI.Refs.Title = Utils.mkLabel({
		text = UILocalizer.Localize("무기 강화"),
		size = UDim2.new(1, -60, 0, 40),
		pos = UDim2.new(0, 20, 0, 10),
		font = F.TITLE,
		ts = 20,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = window
	})
	
	-- Close Button
	local closeBtn = Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(1, 0),
		bg = C.BG_SLOT,
		color = C.WHITE,
		ts = 16,
		font = F.TITLE,
		r = 6,
		fn = function()
			UI_MANAGER.closeEnhance()
		end,
		parent = window
	})
	
	-- Main body area
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(1, -40, 1, -70),
		pos = UDim2.new(0, 20, 0, 60),
		bgT = 1,
		parent = window
	})
	EnhanceUI.Refs.Body = body

	-- 1. Weapon Selector Slot
	local wSlot = Utils.mkFrame({
		name = "WeaponSlot",
		size = UDim2.new(0, 88, 0, 88),
		pos = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		bg = C.BG_SLOT,
		bgT = 0.3,
		r = 12,
		stroke = 2,
		strokeC = C.BORDER,
		parent = body
	})
	EnhanceUI.Refs.WeaponSlot = wSlot
	
	local wIcon = Instance.new("ImageLabel", wSlot)
	wIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
	wIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	wIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	wIcon.BackgroundTransparency = 1
	wIcon.Visible = false
	EnhanceUI.Refs.WeaponIcon = wIcon
	
	local wPlus = Utils.mkLabel({
		text = "+",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 36,
		color = C.INK,
		parent = wSlot
	})
	EnhanceUI.Refs.WeaponPlus = wPlus
	
	local wName = Utils.mkLabel({
		text = UILocalizer.Localize("강화할 무기를 선택하세요"),
		size = UDim2.new(1, 0, 0, 24),
		pos = UDim2.new(0.5, 0, 0, 105),
		anchor = Vector2.new(0.5, 0),
		ts = 14,
		font = F.TITLE,
		color = C.WHITE,
		rich = true,
		parent = body
	})
	EnhanceUI.Refs.WeaponName = wName
	
	-- Interactive text button inside the slot
	local wClick = Instance.new("TextButton")
	wClick.Name = "Click"
	wClick.Size = UDim2.new(1, 0, 1, 0)
	wClick.BackgroundTransparency = 1
	wClick.Text = ""
	wClick.Parent = wSlot
	wClick.MouseButton1Click:Connect(function()
		if EnhanceUI.State.isProcessing then return end
		EnhanceUI.OpenSelector("WEAPON")
	end)

	-- 2. Enhancement Specifications Panel (Comparison)
	local specPanel = Utils.mkFrame({
		name = "SpecPanel",
		size = UDim2.new(1, 0, 0, 85),
		pos = UDim2.new(0.5, 0, 0, 140),
		anchor = Vector2.new(0.5, 0),
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 8,
		parent = body
	})
	
	local specLabel = Utils.mkLabel({
		text = UILocalizer.Localize("무기를 선택하면 공격력 및 강화 스펙 변화가 표시됩니다."),
		size = UDim2.new(1, -20, 1, -10),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 13,
		color = C.INK,
		rich = true,
		wrap = true,
		parent = specPanel
	})
	EnhanceUI.Refs.SpecLabel = specLabel

	-- 3. Cost & Success Rates Panel
	local costPanel = Utils.mkFrame({
		name = "CostPanel",
		size = UDim2.new(1, 0, 0, 85),
		pos = UDim2.new(0.5, 0, 0, 235),
		anchor = Vector2.new(0.5, 0),
		bg = C.BG_DARK,
		bgT = 0.3,
		r = 8,
		parent = body
	})
	
	local costLabel = Utils.mkLabel({
		text = "",
		size = UDim2.new(1, -20, 1, -10),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 13,
		color = C.WHITE,
		rich = true,
		wrap = true,
		parent = costPanel
	})
	EnhanceUI.Refs.CostLabel = costLabel

	-- 4. Down Protect Selector
	local protectPanel = Utils.mkFrame({
		name = "ProtectPanel",
		size = UDim2.new(1, 0, 0, 72),
		pos = UDim2.new(0.5, 0, 0, 325),
		anchor = Vector2.new(0.5, 0),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 8,
		stroke = true,
		strokeC = Color3.fromRGB(40, 80, 160),
		strokeT = 1, -- Invisible initially
		parent = body
	})
	EnhanceUI.Refs.ProtectPanel = protectPanel

	local protectLabel = Utils.mkLabel({
		text = UILocalizer.Localize("하락 방지권 선택"),
		size = UDim2.new(1, -92, 0, 22),
		pos = UDim2.new(0, 12, 0, 8),
		ts = 13,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = protectPanel
	})
	local protectValue = Utils.mkLabel({
		text = UILocalizer.Localize("보유: 0"),
		size = UDim2.new(1, -92, 0, 18),
		pos = UDim2.new(0, 12, 0, 32),
		ts = 12,
		color = C.INK,
		ax = Enum.TextXAlignment.Left,
		rich = true, -- Enable rich text for 적용 중 color tag
		parent = protectPanel
	})
	EnhanceUI.Refs.ProtectValue = protectValue
	local protectBtn = Utils.mkBtn({
		text = UILocalizer.Localize("켜기"),
		size = UDim2.new(0, 68, 0, 38),
		pos = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = C.BTN,
		color = C.WHITE,
		ts = 15,
		r = 8,
		fn = function()
			if EnhanceUI.State.isProcessing then return end
			local slotIdx, totalCount = findInventoryDownProtect()
			if totalCount <= 0 then
				UI_MANAGER.notify(UILocalizer.Localize("하락방지권이 부족합니다."), Color3.fromRGB(255, 100, 100))
				return
			end

			if EnhanceUI.State.selectedDownProtectSlot then
				EnhanceUI.State.selectedDownProtectSlot = nil
			else
				EnhanceUI.State.selectedDownProtectSlot = slotIdx
			end
			syncDownProtectSelection(false)
			EnhanceUI.UpdateChances(false)
		end,
		parent = protectPanel
	})
	EnhanceUI.Refs.ProtectButton = protectBtn

	-- 5. Action Button (Start Enhance)
	local startBtn = Utils.mkBtn({
		text = UILocalizer.Localize("강화 시도"),
		size = UDim2.new(1, 0, 0, 44),
		pos = UDim2.new(0.5, 0, 1, -5),
		anchor = Vector2.new(0.5, 1),
		bg = C.GOLD_SEL,
		color = C.WHITE,
		ts = 18,
		font = F.TITLE,
		r = 8,
		parent = body
	})
	EnhanceUI.Refs.StartBtn = startBtn
	
	startBtn.MouseButton1Click:Connect(function()
		if EnhanceUI.State.isProcessing then return end
		if not EnhanceUI.State.selectedWeaponSlot then
			UI_MANAGER.notify(UILocalizer.Localize("강화할 무기를 선택해야 합니다."), C.RED)
			return
		end

		EnhanceUI.StartEnhance()
	end)

	-- Real-time Gold Update Listener
	ShopController.onGoldChanged(function(newGold)
		if EnhanceUI.Refs.Frame and EnhanceUI.Refs.Frame.Visible then
			EnhanceUI.UpdateChances(true)
		end
	end)

	InventoryController.onChanged(function()
		if EnhanceUI.Refs.Frame and EnhanceUI.Refs.Frame.Visible then
			EnhanceUI.UpdateChances(true)
		end
	end)

	return window
end

function EnhanceUI.OpenSelector(mode)
	if mode ~= "WEAPON" then return end
	UI_MANAGER.openItemSelector("WEAPON", function(slotIndex, itemData)
		EnhanceUI.State.selectedWeaponSlot = slotIndex
		EnhanceUI.UpdateWeapon(itemData)
		EnhanceUI.UpdateChances()
	end)
end

function EnhanceUI.UpdateWeapon(item)
	if not item then
		EnhanceUI.Refs.WeaponIcon.Image = ""
		EnhanceUI.Refs.WeaponIcon.Visible = false
		EnhanceUI.Refs.WeaponPlus.Visible = true
		EnhanceUI.Refs.WeaponName.Text = UILocalizer.Localize("강화할 무기를 선택하세요")
		EnhanceUI.Refs.WeaponSlot.BorderColor3 = C.BORDER
		return
	end
	
	setIconImage(EnhanceUI.Refs.WeaponIcon, UI_MANAGER.getItemIcon(item.itemId))
	EnhanceUI.Refs.WeaponIcon.Visible = true
	EnhanceUI.Refs.WeaponPlus.Visible = false
	
	local level = (item.attributes and item.attributes.enhanceLevel) or 0
	local isEquipped = (EnhanceUI.State.selectedWeaponSlot == "HAND")
	local equippedTag = isEquipped and string.format("<font color='#%s'>[장착중]</font> ", C.GOLD:ToHex()) or ""
	
	EnhanceUI.Refs.WeaponName.Text = equippedTag .. UI_MANAGER.getItemName(item.itemId) .. (level > 0 and " +" .. level or "")
	EnhanceUI.Refs.WeaponSlot.BorderColor3 = C.GOLD
end

function EnhanceUI.UpdateChances(allowPrompt)
	if not UI_MANAGER then return end
	syncDownProtectSelection(allowPrompt == true)
	local wSlot = EnhanceUI.State.selectedWeaponSlot
	local wData = nil
	if wSlot == "HAND" then
		local equipment = UI_MANAGER.getEquipment and UI_MANAGER.getEquipment() or {}
		wData = equipment.HAND
	elseif type(wSlot) == "number" then
		wData = UI_MANAGER.getInventorySlot(wSlot)
	end
	
	if wData then
		local level = (wData.attributes and wData.attributes.enhanceLevel) or 0
		local maxLevel = 50
		
		if level >= maxLevel then
			EnhanceUI.Refs.SpecLabel.Text = string.format("<font color='#%s'><b>최대 강화 단계(+50)에 도달했습니다!</b></font>", C.GOLD:ToHex())
			EnhanceUI.Refs.CostLabel.Text = UILocalizer.Localize("더 이상 강화를 진행할 수 없습니다.")
			EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("강화 완료")
			Utils.setBtnState(EnhanceUI.Refs.StartBtn, C.BG_SLOT, 0.5)
			return
		end
		
		local baseDmg = 10
		local success, DataHelper = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
		end)
		if success and DataHelper then
			local baseItem = DataHelper.GetData("ItemData", wData.itemId)
			if baseItem then
				baseDmg = baseItem.damage or baseItem.baseDamage or baseDmg
			end
		end
		
		-- Spec Comparison
		local curDmg = math.floor(baseDmg * (1 + level * 0.15) + 0.5)
		
		local specText = string.format(
			"<b>%s</b>: <font color='#FFFFFF'>%d</font>\n<font color='#FF4D4D'><b>실패 시 무기의 강화가 내려갑니다.</b></font>",
			UILocalizer.Localize("현재 무기 공격력"), curDmg
		)
		EnhanceUI.Refs.SpecLabel.Text = specText
		
		-- Cost & Success Rates
		local costMult = 1.0
		if success and DataHelper and baseItem then
			costMult = DataHelper.GetEnhanceCostMultiplier(baseItem.rarity or "COMMON")
		end
		local cost = math.floor(getEnhanceCost(level) * costMult)
		local successRate = getSuccessRate(level)
		local myGold = ShopController.getGold()
		
		local costStr = formatVal(cost)
		local rateText = string.format(
			"<b>%s</b>: <font color='#FFFFFF'><b>%d%%</b></font>\n<b>%s</b>: <font color='#FFD700'><b>%s</b></font> Gold",
			UILocalizer.Localize("성공 확률"), math.floor(successRate * 100),
			UILocalizer.Localize("강화 비용"), costStr
		)
		EnhanceUI.Refs.CostLabel.Text = rateText
		
		if myGold >= cost then
			EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("강화 시도")
			Utils.setBtnState(EnhanceUI.Refs.StartBtn, C.GOLD_SEL, 0)
			EnhanceUI.Refs.StartBtn.TextColor3 = C.WHITE
		else
			EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("골드 부족")
			Utils.setBtnState(EnhanceUI.Refs.StartBtn, C.BG_SLOT, 0.5)
			EnhanceUI.Refs.StartBtn.TextColor3 = C.GRAY
		end
	else
		EnhanceUI.Refs.SpecLabel.Text = UILocalizer.Localize("무기를 선택하면 공격력이 표시됩니다.")
		EnhanceUI.Refs.CostLabel.Text = UILocalizer.Localize("성공 확률과 강화 비용을 여기에 표시합니다.")
		EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("무기 선택 필요")
		Utils.setBtnState(EnhanceUI.Refs.StartBtn, C.BG_SLOT, 0.5)
		EnhanceUI.Refs.StartBtn.TextColor3 = C.GRAY
	end
end

function EnhanceUI.StartEnhance()
	if not UI_MANAGER then return end
	local wSlot = EnhanceUI.State.selectedWeaponSlot
	if not wSlot then return end

	local hasProtect = syncDownProtectSelection(false)
	local scrollsPayload = nil
	if hasProtect and EnhanceUI.State.selectedDownProtectSlot then
		scrollsPayload = {
			downProtectSlot = EnhanceUI.State.selectedDownProtectSlot
		}
	end

	EnhanceUI.State.isProcessing = true
	EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("강화 진행 중...")
	Utils.setBtnState(EnhanceUI.Refs.StartBtn, C.BG_SLOT, 0.5)

	local ok, result = NetClient.Request("Enhance.Request", {
		slot = wSlot,
		scrolls = scrollsPayload
	})

	EnhanceUI.State.isProcessing = false
	EnhanceUI.State.pendingDownProtectWarning = false

	if ok and result and result.success then
		if result.result == "SUCCESS" then
			UI_MANAGER.notify(string.format(UILocalizer.Localize("강화 성공! +%d 단계가 되었습니다."), result.newLevel), Color3.fromRGB(100, 255, 100))
		elseif result.result == "PROTECTED" then
			UI_MANAGER.notify(UILocalizer.Localize("강화 실패! 하락 방지권이 사용되어 등급이 유지되었습니다."), Color3.fromRGB(255, 220, 120))
		else
			UI_MANAGER.notify(string.format(UILocalizer.Localize("강화 실패... +%d 단계로 하락했습니다."), result.newLevel), Color3.fromRGB(255, 100, 100))
		end
		
		-- Update slot state and re-sync
		local updatedWeapon = nil
		if wSlot == "HAND" then
			local equipment = UI_MANAGER.getEquipment and UI_MANAGER.getEquipment() or {}
			updatedWeapon = equipment.HAND
		else
			updatedWeapon = UI_MANAGER.getInventorySlot(wSlot)
		end
		
		if updatedWeapon then
			if not updatedWeapon.attributes then
				updatedWeapon.attributes = {}
			end
			updatedWeapon.attributes.enhanceLevel = result.newLevel
		end
		
		EnhanceUI.UpdateWeapon(updatedWeapon)
		EnhanceUI.UpdateChances(true)
	else
		local errMsg = "NETWORK_ERROR"
		if type(result) == "table" and result.error then
			errMsg = result.error
		elseif type(result) == "string" then
			errMsg = result
		end
		
		local text = UILocalizer.Localize("서버 통신 오류가 발생했습니다.")
		if errMsg == "NOT_ENOUGH_GOLD" then
			text = UILocalizer.Localize("골드가 부족합니다.")
		elseif errMsg == "MAX_LEVEL_REACHED" then
			text = UILocalizer.Localize("이미 최대 강화 단계입니다.")
		end
		UI_MANAGER.notify(text, Color3.fromRGB(255, 50, 50))
		EnhanceUI.UpdateChances(true)
	end
end

function EnhanceUI.Refresh()
	EnhanceUI.UpdateChances(false)
end

function EnhanceUI.Reset()
	EnhanceUI.State.selectedWeaponSlot = nil
	EnhanceUI.State.selectedDownProtectSlot = nil
	EnhanceUI.State.lastDownProtectCount = 0
	EnhanceUI.State.pendingDownProtectWarning = false
	EnhanceUI.State.isProcessing = false
	EnhanceUI.UpdateWeapon(nil)
	if EnhanceUI.Refs.ProtectValue then
		EnhanceUI.Refs.ProtectValue.Text = string.format("%s: 0", UILocalizer.Localize("보유"))
	end
	EnhanceUI.UpdateChances()
end

function EnhanceUI.SetVisible(vis)
	if EnhanceUI.Refs.Frame then
		EnhanceUI.Refs.Frame.Visible = vis
		if not vis then
			EnhanceUI.Reset()
		end
	end
end

return EnhanceUI
