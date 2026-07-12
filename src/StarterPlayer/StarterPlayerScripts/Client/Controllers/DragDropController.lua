-- DragDropController.lua
-- 인벤토리 및 장비 슬롯 드래그 앤 드롭 로직 (고급 시각 효과 포함)

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local DragDropController = {}
local UIManager -- Late injection
local InventoryController
local Balance
local player = Players.LocalPlayer
local mainGui
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UITheme"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local T = Theme.Transp

-- State
local isDragging = false
local draggingSlotIdx = nil
local pendingDragIdx = nil
local pendingSourceType = nil
local pendingSourceWindow = "inventory"
local dragStartPos = Vector2.zero
local dragDummy = nil
local draggingSourceType = nil
local draggingSourceWindow = "inventory"

-- Visual Effects State
local dimmedSlotFrame = nil   -- 드래그 중인 원본 슬롯
local hoveredSlotFrame = nil  -- 마우스가 올라간 대상 슬롯
local hoverHighlight = nil    -- 대상 강조 프레임

--========================================
-- Private: 시각 효과 관리
--========================================

local function isMouseOverSlot(mousePos, slotFrame)
	if not slotFrame or not slotFrame.Visible then
		return false
	end
	local absPos = slotFrame.AbsolutePosition
	local absSize = slotFrame.AbsoluteSize
	
	-- 슬롯 영역을 상하 대칭으로 30% 확장 (위아래 동일하게)
	local expandY = absSize.Y * 0.3
	
	return mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
		and mousePos.Y >= absPos.Y - expandY and mousePos.Y <= absPos.Y + absSize.Y + expandY
end

local function setHoverHighlight(slotFrame)
	if hoveredSlotFrame == slotFrame then return end
	
	-- 이전 하이라이트 제거
	if hoverHighlight then
		hoverHighlight:Destroy()
		hoverHighlight = nil
	end
	hoveredSlotFrame = slotFrame

	if not slotFrame then return end

	-- 새 하이라이트 생성 (노란색 강조 테두리)
	hoverHighlight = Instance.new("Frame")
	hoverHighlight.Name = "DragHoverHighlight"
	hoverHighlight.Size = UDim2.new(1, 4, 1, 4)
	hoverHighlight.Position = UDim2.new(0, -2, 0, -2)
	hoverHighlight.BackgroundColor3 = Color3.fromRGB(255, 230, 100)
	hoverHighlight.BackgroundTransparency = 0.7
	hoverHighlight.BorderSizePixel = 0
	hoverHighlight.ZIndex = slotFrame.ZIndex + 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = hoverHighlight

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 240, 150)
	stroke.Thickness = 2
	stroke.Parent = hoverHighlight

	hoverHighlight.Parent = slotFrame
end

local function dimSourceSlot(slotFrame)
	if not slotFrame then return end
	dimmedSlotFrame = slotFrame
	
	-- 아이콘과 슬롯 배경을 반투명하게 처리하여 '들려나간' 느낌 부여
	local icon = slotFrame:FindFirstChild("Icon") or slotFrame:FindFirstChildWhichIsA("ImageLabel")
	if icon then icon.ImageTransparency = 0.7 end
	slotFrame.BackgroundTransparency = 0.7
end

local function restoreSourceSlot()
	if not dimmedSlotFrame then return end
	local icon = dimmedSlotFrame:FindFirstChild("Icon") or dimmedSlotFrame:FindFirstChildWhichIsA("ImageLabel")
	if icon then icon.ImageTransparency = 0 end
	dimmedSlotFrame.BackgroundTransparency = T.SLOT -- 기본 투명도
	dimmedSlotFrame = nil
end

--========================================
-- Public API
--========================================

function DragDropController.Init(_UIManager, _InventoryController, _Balance, _mainGui)
	UIManager = _UIManager
	InventoryController = _InventoryController
	Balance = _Balance
	mainGui = _mainGui
end

function DragDropController.handleDragStart(idx, sourceType, sourceWindow)
	if isDragging then return end

	sourceWindow = sourceWindow or "inventory"
	local item = nil
	if sourceWindow == "storage" then
		item = UIManager.getStorageDragItem and UIManager.getStorageDragItem(idx, sourceType) or nil
	else
		local items = InventoryController.getItems()
		item = items[idx]
	end
	if not item or not item.itemId then return end

	pendingDragIdx = idx
	pendingSourceType = sourceType
	pendingSourceWindow = sourceWindow
	dragStartPos = UserInputService:GetMouseLocation()
end

function DragDropController.handleDragUpdate()
	if pendingDragIdx and not isDragging then
		local delta = (UserInputService:GetMouseLocation() - dragStartPos).Magnitude
		if delta > 10 then -- 최소 드래그 거리 판정
			isDragging = true
			draggingSlotIdx = pendingDragIdx
			draggingSourceType = pendingSourceType
			draggingSourceWindow = pendingSourceWindow or "inventory"
			pendingDragIdx = nil
			pendingSourceType = nil
			
			local item = nil
			if draggingSourceWindow == "storage" then
				item = UIManager.getStorageDragItem and UIManager.getStorageDragItem(draggingSlotIdx, draggingSourceType) or nil
			else
				local items = InventoryController.getItems()
				item = items[draggingSlotIdx]
			end
			
			-- 원본 슬롯 시각적 약화
			local sourceSlots = nil
			if draggingSourceWindow == "storage" then
				sourceSlots = draggingSourceType == "storage" and UIManager.getStorageSlots() or UIManager.getStorageInventorySlots()
			else
				sourceSlots = UIManager.getInvSlots()
			end
			if sourceSlots and sourceSlots[draggingSlotIdx] then
				dimSourceSlot(sourceSlots[draggingSlotIdx].frame)
			end
			
			-- 드래그 고스트(Dummy) 생성: 실제 슬롯 미니어처 스타일
			if dragDummy then dragDummy:Destroy() end
			
			dragDummy = Instance.new("Frame")
			dragDummy.Name = "DragGhost"
			dragDummy.Size = UDim2.new(0, 60, 0, 60)
			dragDummy.BackgroundColor3 = Color3.fromRGB(40, 42, 48)
			dragDummy.BackgroundTransparency = 0.2
			dragDummy.BorderSizePixel = 0
			dragDummy.ZIndex = 3000
			dragDummy.Parent = mainGui
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = dragDummy

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 215, 0)
			stroke.Thickness = 2
			stroke.Parent = dragDummy

			local iconImg = Instance.new("ImageLabel")
			iconImg.Name = "Icon"
			iconImg.Size = UDim2.new(0.8, 0, 0.8, 0)
			iconImg.Position = UDim2.new(0.5, 0, 0.5, 0)
			iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			iconImg.BackgroundTransparency = 1
			iconImg.Image = UIManager.getItemIcon(item.itemId)
			iconImg.ScaleType = Enum.ScaleType.Fit
			iconImg.ZIndex = 3001
			iconImg.Parent = dragDummy

			if item.count and item.count > 1 then
				local countLbl = Instance.new("TextLabel")
				countLbl.Name = "Count"
				countLbl.Size = UDim2.new(0, 25, 0, 18)
				countLbl.Position = UDim2.new(1, -2, 1, -2)
				countLbl.AnchorPoint = Vector2.new(1, 1)
				countLbl.BackgroundColor3 = Color3.new(0,0,0)
				countLbl.BackgroundTransparency = 0.4
				countLbl.Text = "x" .. item.count
				countLbl.TextColor3 = Color3.new(1, 1, 1)
				countLbl.TextSize = 12
				countLbl.Font = Enum.Font.GothamBold
				countLbl.ZIndex = 3002
				countLbl.Parent = dragDummy
				
				local cCorner = Instance.new("UICorner")
				cCorner.CornerRadius = UDim.new(0, 4)
				cCorner.Parent = countLbl
			end
		end
	end

	if not isDragging or not dragDummy then return end
	
	-- 마우스 위치 보정: Inset과 UI Scale 고려하여 커서 중앙 정렬
	local mousePos = UserInputService:GetMouseLocation()
	local uiScale = mainGui:FindFirstChildOfClass("UIScale")
	local scale = uiScale and uiScale.Scale or 1
	
	-- dragDummy의 Position을 마우스 좌표 / scale로 설정하여 정확히 커서 밑에 오도록 함
	dragDummy.Position = UDim2.new(0, mousePos.X / scale - 30, 0, mousePos.Y / scale - 30)

	-- 대상 슬롯 감지 (호버 하이라이트) — 마우스에 가장 가까운 슬롯 선택
	local foundSlotFrame = nil
	local minDistance = math.huge
	-- GetMouseLocation()은 GuiInset 포함 좌표 → IgnoreGuiInset=true의 AbsolutePosition과 맞추려면 인셋 차감
	local rawMouse = UserInputService:GetMouseLocation()
	local insetTop = GuiService:GetGuiInset()
	local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - insetTop.Y)
	
	-- 1. 인벤토리 슬롯 확인
	if draggingSourceWindow == "storage" then
		for _, s in pairs(UIManager.getStorageSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlotFrame = s.frame
				end
			end
		end

		for _, s in pairs(UIManager.getStorageInventorySlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlotFrame = s.frame
				end
			end
		end
	elseif UIManager.isWindowOpen("INV") then
		for _, s in pairs(UIManager.getInvSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				-- 마우스와 슬롯 중심 사이의 2D 거리 계산
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				
				if distance < minDistance then
					minDistance = distance
					foundSlotFrame = s.frame
				end
			end
		end
	end
	
	-- 2. 핫바 슬롯 확인
	if draggingSourceWindow ~= "storage" and (UIManager.isWindowOpen("INV") or true) then  -- 핫바는 항상 확인
		for _, s in pairs(UIManager.getHotbarSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				-- 마우스와 슬롯 중심 사이의 2D 거리 계산
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				
				if distance < minDistance then
					minDistance = distance
					foundSlotFrame = s.frame
				end
			end
		end
	end
	

	-- 2.5. 소모품 단축키 슬롯 확인 (인벤토리 열릴 때)
	if draggingSourceWindow ~= "storage" and UIManager.isWindowOpen("INV") then
		local consumableSlots = UIManager.getConsumableSlots and UIManager.getConsumableSlots() or {}
		for _, s in pairs(consumableSlots) do
			local slotFrame = s and s.frame
			if slotFrame and isMouseOverSlot(mousePos, slotFrame) then
				local absPos = slotFrame.AbsolutePosition
				local absSize = slotFrame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlotFrame = slotFrame
				end
			end
		end
	end

	-- 2.7. 룬 슬롯 확인
	if draggingSourceWindow ~= "storage" and UIManager.isWindowOpen("SKILL") then
		local runeSlots = UIManager.getRuneSlots and UIManager.getRuneSlots() or {}
		for _, s in pairs(runeSlots) do
			if isMouseOverSlot(mousePos, s.frame) then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlotFrame = s.frame
				end
			end
		end
	end
	
	setHoverHighlight(foundSlotFrame)
end

function DragDropController.handleDragEnd()
	if not isDragging then 
		pendingDragIdx = nil
		pendingSourceType = nil
		pendingSourceWindow = "inventory"
		return 
	end
	isDragging = false

	restoreSourceSlot()
	setHoverHighlight(nil)

	if dragDummy then
		dragDummy:Destroy()
		dragDummy = nil
	end

	-- GetMouseLocation()은 GuiInset 포함 좌표 → IgnoreGuiInset=true의 AbsolutePosition과 맞추려면 인셋 차감
	local rawMouse = UserInputService:GetMouseLocation()
	local insetTop = GuiService:GetGuiInset()
	local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - insetTop.Y)
	local foundSlot = nil
	local foundType = nil
	local minDistance = math.huge
	
	-- 1. 인벤토리 확인
	if draggingSourceWindow == "storage" then
		for i, s in pairs(UIManager.getStorageSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlot = i
					foundType = "storage"
				end
			end
		end

		for i, s in pairs(UIManager.getStorageInventorySlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlot = i
					foundType = "player"
				end
			end
		end
	elseif UIManager.isWindowOpen("INV") then
		for i, s in pairs(UIManager.getInvSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				-- 마우스와 슬롯 중심 사이의 2D 거리 계산
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				
				if distance < minDistance then
					minDistance = distance
					foundSlot = i
					foundType = "bag"
				end
			end
		end
	end
	
	-- 2. 핫바 확인
	if draggingSourceWindow ~= "storage" and (UIManager.isWindowOpen("INV") or true) then  -- 핫바는 항상 확인
		for i, s in pairs(UIManager.getHotbarSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				-- 마우스와 슬롯 중심 사이의 2D 거리 계산
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				
				if distance < minDistance then
					minDistance = distance
					foundSlot = i
					foundType = "hotbar"
				end
			end
		end
	end

	-- 2.5. 소모품 단축키 슬롯 확인
	if draggingSourceWindow ~= "storage" and UIManager.isWindowOpen("INV") then
		local consumableSlots = UIManager.getConsumableSlots and UIManager.getConsumableSlots() or {}
		for i, s in pairs(consumableSlots) do
			local slotFrame = s and s.frame
			if slotFrame and isMouseOverSlot(mousePos, slotFrame) then
				local absPos = slotFrame.AbsolutePosition
				local absSize = slotFrame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlot = i
					foundType = "consumable"
				end
			end
		end
	end

	-- 3. 장비 확인
	if draggingSourceWindow ~= "storage" and UIManager.isWindowOpen("EQUIP") then
		for slotName, s in pairs(UIManager.getEquipSlots()) do
			if isMouseOverSlot(mousePos, s.frame) then
				-- 마우스와 슬롯 중심 사이의 2D 거리 계산
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				
				if distance < minDistance then
					minDistance = distance
					foundSlot = slotName
					foundType = "equip"
				end
			end
		end
	end

	-- 4. 룬 슬롯 확인
	if draggingSourceWindow ~= "storage" and UIManager.isWindowOpen("SKILL") then
		local runeSlots = UIManager.getRuneSlots and UIManager.getRuneSlots() or {}
		for slotName, s in pairs(runeSlots) do
			if isMouseOverSlot(mousePos, s.frame) then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				local slotCenterX = absPos.X + absSize.X * 0.5
				local slotCenterY = absPos.Y + absSize.Y * 0.5
				local distX = mousePos.X - slotCenterX
				local distY = mousePos.Y - slotCenterY
				local distance = math.sqrt(distX * distX + distY * distY)
				if distance < minDistance then
					minDistance = distance
					foundSlot = slotName
					foundType = "equip" -- Type is still equip, handled by server equipItem
				end
			end
		end
	end

	if draggingSourceWindow == "storage" then
		if foundSlot then
			UIManager.moveStorageItem(draggingSlotIdx, draggingSourceType, foundSlot, foundType)
		end
	elseif foundType == "consumable" and foundSlot then
		-- 소모품 단축키 슬롯에 드랍 → RegisterConsumable
		local items = InventoryController.getItems()
		local item = items[draggingSlotIdx]
		if item and item.itemId then
			local itemData = DataHelper.GetData("ItemData", item.itemId)
			if itemData and (itemData.type == "CONSUMABLE" or itemData.type == "FOOD") then
				local HUDUI = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("HUDUI"))
				if HUDUI and HUDUI.RegisterConsumable then
					HUDUI.RegisterConsumable(foundSlot, item.itemId)
				end
			else
				if UIManager.notify then UIManager.notify("소모품만 단축키에 등록할 수 있습니다.", Color3.fromRGB(255, 160, 60)) end
			end
		end
	elseif foundSlot then
		InventoryController.moveItem(draggingSlotIdx, foundSlot, foundType)
	else
		-- 인벤토리가 열려있을 때만 바깥 드래그 → 월드 드랍
		-- [요청반영] 월드드랍은 이제 예외 없이 소멸 처리이므로, 아이템 종류와 무관하게 항상 경고 후 확인받는다.
		if draggingSlotIdx and UIManager.isWindowOpen("INV") then
			local items = InventoryController.getItems()
			local item = items[draggingSlotIdx]
			if item and item.itemId then
				local itemData = DataHelper.GetData("ItemData", item.itemId)
				local rawName = itemData and itemData.name or item.itemId
				local localizedName = UILocalizer.LocalizeDataText("ItemData", item.itemId, "name", rawName)
				local count = item.count or 1
				local dropSlotIdx = draggingSlotIdx

				UIManager.showDropConfirm({
					message = string.format("<font color='#FF5555'>%s %d개</font>를 버리시겠습니까?<br/>버린 아이템은 땅에 떨어지지 않고 <font color='#FFAA00'>완전히 소멸</font>되어 복구할 수 없습니다.", tostring(localizedName), count),
					onConfirm = function()
						InventoryController.requestDrop(dropSlotIdx, count)
					end
				})
			end
		end
	end
	
	draggingSlotIdx = nil
	draggingSourceType = nil
	draggingSourceWindow = "inventory"
	pendingSourceWindow = "inventory"
end

-- 소모품 슬롯 간 드래그앤드랍 처리
function DragDropController.handleConsumableDrop()
	local HUDUI = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("HUDUI"))
	local fromIdx = HUDUI._consumableDragStart
	if not fromIdx then return end

	local rawMouse = UserInputService:GetMouseLocation()
	local insetTop = GuiService:GetGuiInset()
	local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - insetTop.Y)

	local consumableSlots = UIManager.getConsumableSlots and UIManager.getConsumableSlots() or {}
	local toIdx = nil
	local minDist = math.huge
	for i, s in pairs(consumableSlots) do
		local slotFrame = s and s.frame
		if slotFrame and i ~= fromIdx and isMouseOverSlot(mousePos, slotFrame) then
			local absPos = slotFrame.AbsolutePosition
			local absSize = slotFrame.AbsoluteSize
			local cx = absPos.X + absSize.X * 0.5
			local cy = absPos.Y + absSize.Y * 0.5
			local dist = math.sqrt((mousePos.X - cx)^2 + (mousePos.Y - cy)^2)
			if dist < minDist then
				minDist = dist
				toIdx = i
			end
		end
	end

	if toIdx then
		local qs = HUDUI.ConsumableQuickslots
		if qs then
			qs[fromIdx], qs[toIdx] = qs[toIdx], qs[fromIdx]
			-- 화면 갱신
			if HUDUI.RefreshConsumableSlots then
				HUDUI.RefreshConsumableSlots()
			end
		end
	end
	HUDUI._consumableDragStart = nil
end

function DragDropController.isDragging()
	return isDragging
end

return DragDropController
