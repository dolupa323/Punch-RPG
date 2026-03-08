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

-- State
local isDragging = false
local draggingSlotIdx = nil
local pendingDragIdx = nil
local dragStartPos = Vector2.zero
local dragDummy = nil

-- Visual Effects State
local dimmedSlotFrame = nil   -- 드래그 중인 원본 슬롯
local hoveredSlotFrame = nil  -- 마우스가 올라간 대상 슬롯
local hoverHighlight = nil    -- 대상 강조 프레임

--========================================
-- Private: 시각 효과 관리
--========================================

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
	dimmedSlotFrame.BackgroundTransparency = 0.3 -- 기본 투명도
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

function DragDropController.handleDragStart(idx)
	if isDragging then return end
	
	local items = InventoryController.getItems()
	local item = items[idx]
	if not item or not item.itemId then return end

	pendingDragIdx = idx
	dragStartPos = UserInputService:GetMouseLocation()
end

function DragDropController.handleDragUpdate()
	if pendingDragIdx and not isDragging then
		local delta = (UserInputService:GetMouseLocation() - dragStartPos).Magnitude
		if delta > 10 then -- 최소 드래그 거리 판정
			isDragging = true
			draggingSlotIdx = pendingDragIdx
			pendingDragIdx = nil
			
			local items = InventoryController.getItems()
			local item = items[draggingSlotIdx]
			
			-- 원본 슬롯 시각적 약화
			local invSlots = UIManager.getInvSlots()
			if invSlots[draggingSlotIdx] then
				dimSourceSlot(invSlots[draggingSlotIdx].frame)
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

	-- 대상 슬롯 감지 (호버 하이라이트)
	local foundSlotFrame = nil
	local guiObjects = player.PlayerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	for _, obj in ipairs(guiObjects) do
		if obj == dragDummy or obj:IsDescendantOf(dragDummy) then continue end
		
		-- 인벤토리/핫바/장비 슬롯인지 확인
		if UIManager.isWindowOpen("INV") then
			for _, s in pairs(UIManager.getInvSlots()) do
				if s.frame == obj or obj:IsDescendantOf(s.frame) then
					foundSlotFrame = s.frame; break
				end
			end
		end
		if not foundSlotFrame then
			for _, s in pairs(UIManager.getHotbarSlots()) do
				if s.frame == obj or obj:IsDescendantOf(s.frame) then
					foundSlotFrame = s.frame; break
				end
			end
		end
		if foundSlotFrame then break end
	end
	setHoverHighlight(foundSlotFrame)
end

function DragDropController.handleDragEnd()
	if not isDragging then 
		pendingDragIdx = nil
		return 
	end
	isDragging = false

	restoreSourceSlot()
	setHoverHighlight(nil)

	if dragDummy then
		dragDummy:Destroy()
		dragDummy = nil
	end

	local mousePos = UserInputService:GetMouseLocation()
	local foundSlot = nil
	local foundType = nil
	
	local guiObjects = player.PlayerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	for _, obj in ipairs(guiObjects) do
		-- 1. 인벤토리
		if UIManager.isWindowOpen("INV") then
			for i, s in pairs(UIManager.getInvSlots()) do
				if s.frame == obj or obj:IsDescendantOf(s.frame) then
					foundSlot = i; foundType = "bag"; break
				end
			end
		end
		if foundSlot then break end
		
		-- 2. 핫바
		for i, s in pairs(UIManager.getHotbarSlots()) do
			if s.frame == obj or obj:IsDescendantOf(s.frame) then
				foundSlot = i; foundType = "hotbar"; break
			end
		end
		if foundSlot then break end

		-- 3. 장비
		if UIManager.isWindowOpen("EQUIP") then
			for slotName, s in pairs(UIManager.getEquipSlots()) do
				if s.frame == obj or obj:IsDescendantOf(s.frame) then
					foundSlot = slotName; foundType = "equip"; break
				end
			end
		end
		if foundSlot then break end
	end

	if foundSlot then
		InventoryController.moveItem(draggingSlotIdx, foundSlot, foundType)
	end
	
	draggingSlotIdx = nil
end

function DragDropController.isDragging()
	return isDragging
end

return DragDropController
