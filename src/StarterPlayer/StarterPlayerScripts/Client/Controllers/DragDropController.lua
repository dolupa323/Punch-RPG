-- DragDropController.lua
-- 인벤토리 및 장비 슬롯 드래그 앤 드롭 로직 분리 (Phase 11)

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local DragDropController = {}

local UIManager -- Circular dependency 방지를 위해 Late injection
local InventoryController
local Balance
local player = Players.LocalPlayer
local mainGui

-- State
local isDragging = false
local DRAG_THRESHOLD = 8
local pendingDragIdx = nil
local draggingSlotIdx = nil
local dragStartPos = Vector2.zero
local dragDummy = nil

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
		local mousePos = UserInputService:GetMouseLocation()
		if (mousePos - dragStartPos).Magnitude > DRAG_THRESHOLD then
			isDragging = true
			draggingSlotIdx = pendingDragIdx
			pendingDragIdx = nil
			
			local items = InventoryController.getItems()
			local item = items[draggingSlotIdx]
			
			if dragDummy then dragDummy:Destroy() end
			dragDummy = Instance.new("ImageLabel")
			dragDummy.Name = "DragDummy"
			dragDummy.Size = UDim2.new(0, 56, 0, 56)
			dragDummy.BackgroundTransparency = 0.4
			dragDummy.Image = UIManager.getItemIcon(item.itemId)
			dragDummy.ZIndex = 2000
			dragDummy.Parent = mainGui
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = dragDummy
		end
	end

	if not isDragging or not dragDummy then return end
	
	local inset = GuiService:GetGuiInset()
	local mousePos = UserInputService:GetMouseLocation()
	local actualX = mousePos.X - inset.X
	local actualY = mousePos.Y - inset.Y
	dragDummy.Position = UDim2.new(0, actualX - 28, 0, actualY - 28)
end

function DragDropController.handleDragEnd()
	if not isDragging then 
		pendingDragIdx = nil
		return 
	end
	isDragging = false

	if dragDummy then
		dragDummy:Destroy()
		dragDummy = nil
	end

	local mousePos = UserInputService:GetMouseLocation()
	local foundSlot = nil
	local foundType = nil
	
	local playerGui = player:WaitForChild("PlayerGui")
	local guiObjects = playerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	
	for _, obj in ipairs(guiObjects) do
		-- UIManager의 Refs를 통해 슬롯 감지
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
		if foundType == "equip" then
			InventoryController.requestEquip(draggingSlotIdx, foundSlot)
		elseif foundSlot ~= draggingSlotIdx then
			InventoryController.swapSlots(draggingSlotIdx, foundSlot)
		end
	end

	draggingSlotIdx = nil
	pendingDragIdx = nil
end

function DragDropController.isDragging()
	return isDragging
end

return DragDropController
