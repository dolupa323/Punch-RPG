ㄴㅁ-- EnhanceUI.lua
-- 무기 강화(연금) 전용 UI 모듈
-- 갱신: 듀얼 주문서 슬롯 지원 (하락방지 + 파괴방지 동시 사용 가능)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local NetClient = require(script.Parent.Parent.NetClient)
local C = Theme.Colors
local F = Theme.Fonts

local EnhanceUI = {}

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

EnhanceUI.State = {
	selectedWeaponSlot = nil,
	selectedStoneSlot = nil,
	selectedDownSlot = nil,
	selectedDestroySlot = nil,
	isProcessing = false
}
EnhanceUI.Refs = {}

local UI_MANAGER = nil

-- 클라이언트 측 확률 데이터 (서버와 동기화 필요)
local CLIENT_PROBS = {
	BASE_SUCCESS = { [0]=1.00, [1]=0.90, [2]=0.80, [3]=0.60, [4]=0.40, [5]=0.25, [6]=0.15, [7]=0.10, [8]=0.05, [9]=0.03 },
	STONES = { ALCHEMY_STONE_LOW=0.00, ALCHEMY_STONE_MID=0.10, ALCHEMY_STONE_HIGH=0.25 },
	SCROLLS = { 
		ENHANCE_SCROLL_NORMAL=0.05, 
		ENHANCE_SCROLL_SURE=0.15,
		["3586927112"] = { isDownProtect = true },    -- 하락방지권
		["3586927381"] = { isDestroyProtect = true }, -- 파괴방지권
	},
	RISKS = {
		SAFE = { stay=100, down=0, destroy=0 },
		MID  = { stay=70, down=25, destroy=5 },
		HIGH = { stay=40, down=40, destroy=20 }
	}
}

function EnhanceUI.Init(parent, manager)
	UI_MANAGER = manager
	local frame = Utils.mkFrame({
		name = "EnhanceContainer",
		size = UDim2.new(1, 0, 1, 0),
		bgT = 1,
		vis = false,
		parent = parent
	})
	EnhanceUI.Refs.Main = frame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.015, 0)
	list.Parent = frame
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0); pad.PaddingBottom = UDim.new(0.04, 0)
	pad.Parent = frame

	-- 1. 무기 선택 영역
	local weaponArea = Utils.mkFrame({
		name = "WeaponArea",
		size = UDim2.new(0.95, 0, 0.22, 0),
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 6,
		z = 1,
		parent = frame
	})
	weaponArea.LayoutOrder = 1
	
	Utils.mkLabel({
		text = UILocalizer.Localize("강화할 무기"),
		size = UDim2.new(1, 0, 0, 20),
		pos = UDim2.new(0, 0, 0, 4),
		ts = 15,
		font = F.TITLE,
		color = C.GOLD,
		parent = weaponArea
	})

	local wSlot = Utils.mkFrame({
		name = "WeaponSlot",
		size = UDim2.new(0, 56, 0, 56),
		pos = UDim2.new(0.5, 0, 0.45, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_SLOT,
		r = 8,
		stroke = 2,
		strokeC = C.BORDER,
		parent = weaponArea
	})
	Instance.new("UIAspectRatioConstraint", wSlot).AspectRatio = 1

	EnhanceUI.Refs.WeaponSlot = wSlot
	EnhanceUI.Refs.WeaponIcon = Instance.new("ImageLabel", wSlot)
	EnhanceUI.Refs.WeaponIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
	EnhanceUI.Refs.WeaponIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	EnhanceUI.Refs.WeaponIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	EnhanceUI.Refs.WeaponIcon.BackgroundTransparency = 1

	EnhanceUI.Refs.WeaponName = Utils.mkLabel({
		text = UILocalizer.Localize("무기를 선택하세요"),
		size = UDim2.new(1, 0, 0, 18),
		pos = UDim2.new(0, 0, 1, -4),
		anchor = Vector2.new(0, 1),
		ts = 12,
		color = C.WHITE,
		parent = weaponArea
	})

	-- 2. 연금석 선택 영역
	local stoneArea = Utils.mkFrame({
		name = "StoneArea",
		size = UDim2.new(0.95, 0, 0.22, 0),
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 6,
		z = 1,
		parent = frame
	})
	stoneArea.LayoutOrder = 2

	Utils.mkLabel({
		text = UILocalizer.Localize("연금석 선택"),
		size = UDim2.new(1, 0, 0, 20),
		pos = UDim2.new(0, 0, 0, 4),
		ts = 15,
		font = F.TITLE,
		color = C.GOLD,
		parent = stoneArea
	})

	local sSlot = Utils.mkFrame({
		name = "StoneSlot",
		size = UDim2.new(0, 56, 0, 56),
		pos = UDim2.new(0.5, 0, 0.45, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_SLOT,
		r = 8,
		stroke = 2,
		strokeC = C.BORDER,
		parent = stoneArea
	})
	Instance.new("UIAspectRatioConstraint", sSlot).AspectRatio = 1

	EnhanceUI.Refs.StoneSlot = sSlot
	EnhanceUI.Refs.StoneIcon = Instance.new("ImageLabel", sSlot)
	EnhanceUI.Refs.StoneIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
	EnhanceUI.Refs.StoneIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	EnhanceUI.Refs.StoneIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	EnhanceUI.Refs.StoneIcon.BackgroundTransparency = 1

	EnhanceUI.Refs.StoneName = Utils.mkLabel({
		text = UILocalizer.Localize("연금석을 선택하세요"),
		size = UDim2.new(1, 0, 0, 18),
		pos = UDim2.new(0, 0, 1, -4),
		anchor = Vector2.new(0, 1),
		ts = 12,
		color = C.WHITE,
		parent = stoneArea
	})
	
	-- 3. 주문서 선택 영역 (2개 슬롯)
	local scrollArea = Utils.mkFrame({
		name = "ScrollArea",
		size = UDim2.new(0.95, 0, 0.28, 0),
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 6,
		z = 1,
		parent = frame
	})
	scrollArea.LayoutOrder = 3

	Utils.mkLabel({
		text = UILocalizer.Localize("보호 주문서 (선택 사항)"),
		size = UDim2.new(1, 0, 0, 20),
		pos = UDim2.new(0, 0, 0, 4),
		ts = 15,
		font = F.TITLE,
		color = C.GOLD,
		parent = scrollArea
	})

	local scrollContainer = Instance.new("Frame", scrollArea)
	scrollContainer.Size = UDim2.new(1, 0, 1, -25)
	scrollContainer.Position = UDim2.new(0, 0, 0, 25)
	scrollContainer.BackgroundTransparency = 1
	
	local sList = Instance.new("UIListLayout", scrollContainer)
	sList.FillDirection = Enum.FillDirection.Horizontal
	sList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.Padding = UDim.new(0, 40)

	-- 하락방지 슬롯
	local dSlot = Utils.mkFrame({
		name = "DownSlot",
		size = UDim2.new(0, 56, 0, 56),
		bg = C.BG_SLOT,
		r = 8,
		stroke = 2,
		strokeC = C.BORDER,
		parent = scrollContainer
	})
	EnhanceUI.Refs.DownSlot = dSlot
	EnhanceUI.Refs.DownIcon = Instance.new("ImageLabel", dSlot)
	EnhanceUI.Refs.DownIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
	EnhanceUI.Refs.DownIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	EnhanceUI.Refs.DownIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	EnhanceUI.Refs.DownIcon.BackgroundTransparency = 1
	Utils.mkLabel({text=UILocalizer.Localize("하락방지"), size=UDim2.new(1.5,0,0,15), pos=UDim2.new(0.5,0,1,10), anchor=Vector2.new(0.5,0), ts=10, color=C.WHITE, parent=dSlot})

	-- 파괴방지 슬롯
	local dsSlot = Utils.mkFrame({
		name = "DestroySlot",
		size = UDim2.new(0, 56, 0, 56),
		bg = C.BG_SLOT,
		r = 8,
		stroke = 2,
		strokeC = C.BORDER,
		parent = scrollContainer
	})
	EnhanceUI.Refs.DestroySlot = dsSlot
	EnhanceUI.Refs.DestroyIcon = Instance.new("ImageLabel", dsSlot)
	EnhanceUI.Refs.DestroyIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
	EnhanceUI.Refs.DestroyIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	EnhanceUI.Refs.DestroyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	EnhanceUI.Refs.DestroyIcon.BackgroundTransparency = 1
	Utils.mkLabel({text=UILocalizer.Localize("파괴방지"), size=UDim2.new(1.5,0,0,15), pos=UDim2.new(0.5,0,1,10), anchor=Vector2.new(0.5,0), ts=10, color=C.WHITE, parent=dsSlot})

	-- 4. 확률 및 리스크 영역
	local riskArea = Utils.mkFrame({
		name = "RiskArea",
		size = UDim2.new(0.95, 0, 0.1, 0),
		bgT = 1,
		parent = frame
	})
	riskArea.LayoutOrder = 4

	EnhanceUI.Refs.ChanceLabel = Utils.mkLabel({
		text = "",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		ts = 14,
		color = C.WHITE,
		rich = true,
		wrap = true,
		parent = riskArea
	})

	-- 5. 버튼 영역
	local btnArea = Utils.mkFrame({
		name = "BtnArea",
		size = UDim2.new(0.95, 0, 0.12, 0),
		bgT = 1,
		parent = frame
	})
	btnArea.LayoutOrder = 10

	local startBtn = Utils.mkBtn({
		text = UILocalizer.Localize("연금 시도"),
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.GOLD,
		color = C.BG_DARK,
		ts = 20,
		font = F.TITLE,
		r = 6,
		parent = btnArea
	})
	EnhanceUI.Refs.StartBtn = startBtn

	-- 클릭 핸들러 연동
	local function addClick(obj, mode)
		local btn = Instance.new("TextButton")
		btn.Name = "Click"
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Parent = obj
		btn.MouseButton1Click:Connect(function()
			EnhanceUI.OpenSelector(mode)
		end)
	end

	addClick(wSlot, "WEAPON")
	addClick(sSlot, "ALCHEMY_STONE")
	addClick(dSlot, "DOWN_PROTECT")
	addClick(dsSlot, "DESTROY_PROTECT")

	startBtn.MouseButton1Click:Connect(function()
		if EnhanceUI.State.isProcessing then return end
		if not EnhanceUI.State.selectedWeaponSlot or not EnhanceUI.State.selectedStoneSlot then
			UI_MANAGER.notify(UILocalizer.Localize("무기와 연금석을 모두 선택해야 합니다."), C.RED)
			return
		end
		
		EnhanceUI.StartEnhance()
	end)

	return frame
end

function EnhanceUI.OpenSelector(mode)
	UI_MANAGER.openItemSelector(mode, function(slotIndex, itemData)
		if mode == "WEAPON" then
			EnhanceUI.State.selectedWeaponSlot = slotIndex
			EnhanceUI.UpdateWeapon(itemData)
		elseif mode == "ALCHEMY_STONE" then
			EnhanceUI.State.selectedStoneSlot = slotIndex
			EnhanceUI.UpdateStone(itemData)
		elseif mode == "DOWN_PROTECT" then
			EnhanceUI.State.selectedDownSlot = slotIndex
			EnhanceUI.UpdateDownProtect(itemData)
		elseif mode == "DESTROY_PROTECT" then
			EnhanceUI.State.selectedDestroySlot = slotIndex
			EnhanceUI.UpdateDestroyProtect(itemData)
		end
		
		EnhanceUI.UpdateChances()
	end)
end

function EnhanceUI.UpdateWeapon(item)
	if not item then
		EnhanceUI.Refs.WeaponIcon.Image = ""
		EnhanceUI.Refs.WeaponIcon.Visible = false
		EnhanceUI.Refs.WeaponName.Text = UILocalizer.Localize("무기를 선택하세요")
		return
	end
	setIconImage(EnhanceUI.Refs.WeaponIcon, UI_MANAGER.getItemIcon(item.itemId))
	EnhanceUI.Refs.WeaponIcon.Visible = true
	local level = (item.attributes and item.attributes.enhanceLevel) or 0
	EnhanceUI.Refs.WeaponName.Text = UI_MANAGER.getItemName(item.itemId) .. (level > 0 and " +" .. level or "")
end

function EnhanceUI.UpdateStone(item)
	if not item then
		EnhanceUI.Refs.StoneIcon.Image = ""
		EnhanceUI.Refs.StoneIcon.Visible = false
		EnhanceUI.Refs.StoneName.Text = UILocalizer.Localize("연금석을 선택하세요")
		return
	end
	setIconImage(EnhanceUI.Refs.StoneIcon, UI_MANAGER.getItemIcon(item.itemId))
	EnhanceUI.Refs.StoneIcon.Visible = true
	EnhanceUI.Refs.StoneName.Text = UI_MANAGER.getItemName(item.itemId)
end

function EnhanceUI.UpdateDownProtect(item)
	EnhanceUI.State.selectedDownProtect = item
	if item then
		setIconImage(EnhanceUI.Refs.DownIcon, UI_MANAGER.getItemIcon(item.itemId))
		EnhanceUI.Refs.DownIcon.Visible = true
	else
		EnhanceUI.Refs.DownIcon.Image = ""
		EnhanceUI.Refs.DownIcon.Visible = false
	end
	EnhanceUI.UpdateChances()
end

function EnhanceUI.UpdateDestroyProtect(item)
	EnhanceUI.State.selectedDestroyProtect = item
	if item then
		setIconImage(EnhanceUI.Refs.DestroyIcon, UI_MANAGER.getItemIcon(item.itemId))
		EnhanceUI.Refs.DestroyIcon.Visible = true
	else
		EnhanceUI.Refs.DestroyIcon.Image = ""
		EnhanceUI.Refs.DestroyIcon.Visible = false
	end
	EnhanceUI.UpdateChances()
end

function EnhanceUI.UpdateChances()
	if not UI_MANAGER then return end
	local wData = EnhanceUI.State.selectedWeaponSlot and UI_MANAGER.getInventorySlot(EnhanceUI.State.selectedWeaponSlot)
	local sData = EnhanceUI.State.selectedStoneSlot and UI_MANAGER.getInventorySlot(EnhanceUI.State.selectedStoneSlot)
	local dData = EnhanceUI.State.selectedDownSlot and UI_MANAGER.getInventorySlot(EnhanceUI.State.selectedDownSlot)
	local dsData = EnhanceUI.State.selectedDestroySlot and UI_MANAGER.getInventorySlot(EnhanceUI.State.selectedDestroySlot)
	
	if wData and sData then
		local level = (wData.attributes and wData.attributes.enhanceLevel) or 0
		local base = CLIENT_PROBS.BASE_SUCCESS[level] or 0.01
		local sBonus = CLIENT_PROBS.STONES[sData.itemId] or 0
		
		-- 두 주문서의 효과를 각각 체크
		local isDownProtected = dData ~= nil
		local isDestroyProtected = dsData ~= nil
		
		local finalRate = math.min(1, base + sBonus)
		local failRate = 1 - finalRate
		
		local risk
		if level <= 2 then risk = CLIENT_PROBS.RISKS.SAFE
		elseif level <= 5 then risk = CLIENT_PROBS.RISKS.MID
		else risk = CLIENT_PROBS.RISKS.HIGH end
		
		local successStr = string.format("<font color='#ffcc00' size='16'><b>성공: %d%%</b></font>", math.floor(finalRate * 100))
		local failStr = ""
		
		if failRate > 0 then
			local stayP = math.floor(failRate * risk.stay)
			local downP = math.floor(failRate * risk.down)
			local destP = math.floor(failRate * risk.destroy)
			
			-- 방지권 처리
			local downText = isDownProtected and "<font color='#88ff88'>하락 방지됨</font>" or string.format("<font color='#ff8800'>하락: %d%%</font>", downP)
			local destText = isDestroyProtected and "<font color='#88ff88'>파괴 방지됨</font>" or string.format("<font color='#ff4444'>파괴: %d%%</font>", destP)
			
			failStr = string.format("\n<font size='13'>유지: %d%% | %s | %s</font>", stayP, downText, destText)
		end
		
		EnhanceUI.Refs.ChanceLabel.Text = successStr .. failStr
	else
		EnhanceUI.Refs.ChanceLabel.Text = UILocalizer.Localize("무기와 연금석을 선택하여 확률을 확인하세요.")
	end
end

function EnhanceUI.StartEnhance()
	if not UI_MANAGER then return end
	local wSlot = EnhanceUI.State.selectedWeaponSlot
	local sSlot = EnhanceUI.State.selectedStoneSlot
	local dSlot = EnhanceUI.State.selectedDownSlot
	local dsSlot = EnhanceUI.State.selectedDestroySlot
	
	local wData = wSlot and UI_MANAGER.getInventorySlot(wSlot)
	local sData = sSlot and UI_MANAGER.getInventorySlot(sSlot)
	
	if not wData or not sData then return end
	
	EnhanceUI.State.isProcessing = true
	EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("연금 진행 중...")
	
	local scrolls = {}
	if dSlot then table.insert(scrolls, dSlot) end
	if dsSlot then table.insert(scrolls, dsSlot) end
	
	local ok, result = NetClient.Request("Enhance.Request", {
		weaponSlot = wSlot,
		stoneSlot = sSlot,
		scrollSlots = scrolls
	})
	
	EnhanceUI.State.isProcessing = false
	EnhanceUI.Refs.StartBtn.Text = UILocalizer.Localize("연금 시도")
	
	if ok and result then
		if result.result == "SUCCESS" then
			UI_MANAGER.notify(UILocalizer.Localize("강화 성공!"), Color3.fromRGB(100, 255, 100))
		else
			local msg = result.isDestroyed and "아이템이 파괴되었습니다..." or (result.isDown and "강화 단계가 하락했습니다." or "강화에 실패했습니다.")
			UI_MANAGER.notify(UILocalizer.Localize(msg), result.isDestroyed and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 200, 50))
		end
		
		-- 선택 초기화 (파괴되지 않은 경우 무기는 유지)
		EnhanceUI.State.selectedStoneSlot = nil
		EnhanceUI.State.selectedDownSlot = nil
		EnhanceUI.State.selectedDestroySlot = nil
		
		if result.isDestroyed then
			EnhanceUI.State.selectedWeaponSlot = nil
			EnhanceUI.UpdateWeapon(nil)
		else
			local updatedWeapon = UI_MANAGER.getInventorySlot(EnhanceUI.State.selectedWeaponSlot)
			EnhanceUI.UpdateWeapon(updatedWeapon)
		end
		
		EnhanceUI.UpdateStone(nil)
		EnhanceUI.UpdateDownProtect(nil)
		EnhanceUI.UpdateDestroyProtect(nil)
		EnhanceUI.UpdateChances()
	else
		UI_MANAGER.notify(UILocalizer.Localize("서버 통신 오류가 발생했습니다."), Color3.fromRGB(255, 50, 50))
	end
end

function EnhanceUI.SetVisible(vis)
	if EnhanceUI.Refs.Main then
		EnhanceUI.Refs.Main.Visible = vis
	end
end

return EnhanceUI
