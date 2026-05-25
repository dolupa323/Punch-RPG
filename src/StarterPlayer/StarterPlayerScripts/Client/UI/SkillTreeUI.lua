-- SkillTreeUI.lua (Rune System UI with Equipment UI Convention)
-- 장비창 스타일의 세련된 3개 룬 장착 슬롯 창

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local UI = script.Parent
local Theme = require(UI.UITheme)
local Utils = require(UI.UIUtils)
local UILocalizer = require(Client.Localization.UILocalizer)
local InventoryController = require(Client.Controllers.InventoryController)
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared").Util.DataHelper)

-- Local Color Override for Navy + Black Theme (EquipmentUI와 동일)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
C.BG_SLOT = Color3.fromRGB(15, 20, 35)  -- Deep Navy
C.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)

local F = Theme.Fonts
local T = Theme.Transp

local SkillTreeUI = {}

SkillTreeUI.Refs = {
	Frame = nil,
	Slots = {},
}

local _UIManager = nil
local _isMobile = false
local _connections = {}

function SkillTreeUI.SetVisible(visible)
	if SkillTreeUI.Refs.Frame then
		SkillTreeUI.Refs.Frame.Visible = visible
		if visible then
			SkillTreeUI.Refresh()
		end
	end
end

function SkillTreeUI.Init(parent, UIManager, isMobile)
	_UIManager = UIManager
	_isMobile = isMobile
	local isSmall = _isMobile
	
	-- 1. Background Dim Layer
	local frame = Utils.mkFrame({
		name = "SkillTreeMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.4,
		vis = false,
		parent = parent
	})
	SkillTreeUI.Refs.Frame = frame
	
	-- 2. Main Window (Equipment UI 스타일로 단정하게)
	local main = Utils.mkWindow({
		name = "RuneWindow",
		size = UDim2.new(isSmall and 0.9 or 0.45, 0, isSmall and 0.5 or 0.35, 0),
		maxSize = Vector2.new(650, 260),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = frame
	})
	
	-- Title Header
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	Utils.mkLabel({text="룬 시스템 [Rune System]", pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1,0.5), bgT=0.5, ts=20, color=C.WHITE, isNegative=true, r=4, fn=function() UIManager.toggleSkillTree() end, parent=header})
	
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	
	-- Slots Row Container
	local slotsContainer = Utils.mkFrame({name="SlotsContainer", size=UDim2.new(1, 0, 0, 110), pos=UDim2.new(0,0,0.1,0), bgT=1, parent=content})
	local sList = Instance.new("UIListLayout")
	sList.FillDirection = Enum.FillDirection.Horizontal
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Padding = UDim.new(0, 30)
	sList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.Parent = slotsContainer
	
	local slotConfigs = {
		{id="RUNE1", name="룬 슬롯 1"},
		{id="RUNE2", name="룬 슬롯 2"},
		{id="RUNE3", name="룬 슬롯 3"},
	}
	
	for i, conf in ipairs(slotConfigs) do
		local wrapper = Utils.mkFrame({
			name = conf.id.."Wrap",
			size = UDim2.new(0, 120, 0, 110),
			bgT = 1,
			parent = slotsContainer
		})
		wrapper.LayoutOrder = i
		
		-- EquipmentUI와 완전 동일한 정사각형 슬롯
		local slot = Utils.mkSlot({
			name = conf.id.."Slot", 
			size = UDim2.new(0, 78, 0, 78),
			pos = UDim2.new(0.5, 0, 0, 0),
			anchor = Vector2.new(0.5, 0.5),
			bgT = T.SLOT, 
			stroke = false, 
			parent = wrapper
		})
		
		-- 장비 슬롯 명칭 라벨
		Utils.mkLabel({
			text = UILocalizer.Localize(conf.name),
			size = UDim2.new(1, 0, 0, 20),
			pos = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			bgT = 1,
			ts = 15,
			font = F.NORMAL,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Center,
			parent = wrapper
		})
		
		-- Double click to unequip, Single click to select/tooltip
		slot.click.MouseButton1Click:Connect(function()
			local now = tick()
			if slot._lastClickTime and (now - slot._lastClickTime) < 0.4 then
				InventoryController.requestUnequip(conf.id)
				slot._lastClickTime = nil
			else
				slot._lastClickTime = now
			end
		end)
		slot.click.MouseButton2Click:Connect(function()
			InventoryController.requestUnequip(conf.id)
		end)
		
		SkillTreeUI.Refs.Slots[conf.id] = slot
	end
	
	-- 3. Bottom Guide Label
	Utils.mkLabel({
		text = UILocalizer.Localize("인벤토리에서 룬을 드래그해 장착하세요.\n더블클릭 또는 우클릭하여 해제할 수 있습니다."),
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 1, 0),
		anchor = Vector2.new(0.5, 1),
		ts = 14,
		font = F.NORMAL,
		color = Color3.fromRGB(150, 170, 200),
		parent = content,
		z = 10
	})
	
	-- Listen to updates from controller
	local conn = InventoryController.onChanged(function()
		if frame.Visible then
			SkillTreeUI.Refresh()
		end
	end)
	table.insert(_connections, conn)
end

function SkillTreeUI.Refresh()
	if not SkillTreeUI.Refs.Frame or not SkillTreeUI.Refs.Frame.Visible then return end
	
	local equip = InventoryController.getEquipment()
	
	for id, slotRef in pairs(SkillTreeUI.Refs.Slots) do
		local eqItem = equip[id]
		if eqItem and eqItem.itemId then
			local itemData = DataHelper.GetData("ItemData", eqItem.itemId)
			slotRef.icon.Image = _UIManager and _UIManager.getItemIcon(eqItem.itemId) or ""
			slotRef.icon.Visible = true
			
			-- Set border color based on rarity (EquipmentUI와 일치)
			local rarityColor = C.BORDER
			if itemData and itemData.rarity == "RARE" then rarityColor = Color3.fromRGB(80, 180, 255)
			elseif itemData and itemData.rarity == "EPIC" then rarityColor = Color3.fromRGB(180, 100, 255)
			elseif itemData and itemData.rarity == "UNIQUE" then rarityColor = Color3.fromRGB(255, 180, 50)
			elseif itemData and itemData.rarity == "LEGENDARY" then rarityColor = Color3.fromRGB(255, 50, 50)
			end
			
			-- UIStroke가 없으면 생성하여 채색
			local stroke = slotRef.frame:FindFirstChildOfClass("UIStroke")
			if not stroke then
				stroke = Instance.new("UIStroke")
				stroke.Thickness = 1.8
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = slotRef.frame
			end
			stroke.Color = rarityColor
			stroke.Enabled = true
		else
			slotRef.icon.Image = ""
			slotRef.icon.Visible = false
			local stroke = slotRef.frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
			end
		end
	end
end

function SkillTreeUI.SetController(controller)
	-- Keep placeholder compatibility
end

function SkillTreeUI.GetSlots()
	return SkillTreeUI.Refs.Slots
end

return SkillTreeUI
