-- SkillTreeUI.lua (Replaced with Rune System UI)
-- 3 Circular Slots positioned in a triangle layout with a Magic Circle background.

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

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

-- Color Overrides
local C_BASE = Theme.Colors
local BG_PANEL = Color3.fromRGB(10, 15, 25)
local MAGIC_GOLD = Color3.fromRGB(255, 210, 100)

local SkillTreeUI = {}

SkillTreeUI.Refs = {
	Frame = nil,
	Slots = {},
	CircleGlow = nil,
	ElementIcon = nil,
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
	
	-- 1. Background Fullscreen Overlay
	local frame = Utils.mkFrame({
		name = "SkillTreeMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.4,
		vis = false,
		parent = parent
	})
	SkillTreeUI.Refs.Frame = frame
	
	-- 2. Main Window (Responsive scaling via Aspect Ratio Constraint)
	local main = Utils.mkWindow({
		name = "RuneWindow",
		size = UDim2.fromScale(0.75, 0.75), -- Responsive relative scaling
		pos = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		bg = BG_PANEL,
		bgT = 0.15,
		r = "full", -- Perfectly circular scaling
		stroke = 3,
		strokeC = Color3.fromRGB(20, 40, 80), -- Deep Navy Blue
		ratio = 1.0, -- LOCK ASPECT RATIO TO 1:1 for perfect responsive circle
		parent = frame
	})
	
	-- Background Image Logic
	local bgImage = Instance.new("ImageLabel")
	bgImage.Name = "RuneBackground"
	bgImage.Size = UDim2.fromScale(1.25, 1.25) -- Scaled up from 1.0 to 1.25 to fill navy border
	bgImage.Position = UDim2.fromScale(0.5, 0.5)
	bgImage.AnchorPoint = Vector2.new(0.5, 0.5)
	bgImage.BackgroundTransparency = 1
	bgImage.Image = "rbxassetid://7165355021" -- Default fallback
	bgImage.ImageColor3 = MAGIC_GOLD
	bgImage.ImageTransparency = 0.4
	bgImage.ZIndex = 2
	bgImage.Parent = main
	
	-- Dynamically attempt to load from User provided Assets
	task.spawn(function()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			local uiAssets = assets:FindFirstChild("UI")
			if uiAssets then
				local customBg = uiAssets:FindFirstChild("RuneBackground")
				if customBg and (customBg:IsA("Decal") or customBg:IsA("Texture") or customBg:IsA("ImageLabel")) then
					bgImage.Image = customBg:IsA("ImageLabel") and customBg.Image or (customBg.Texture or bgImage.Image)
					bgImage.ImageColor3 = Color3.new(1,1,1)
					bgImage.ImageTransparency = 0
					warn("[RuneUI] Successfully loaded custom background from Assets/UI/RuneBackground.")
				end
			end
		end
	end)

	
	-- Header Label
	Utils.mkLabel({
		text = "RUNE SYSTEM",
		size = UDim2.fromScale(0.6, 0.08), -- Scaled size
		pos = UDim2.fromScale(0.5, 0.07),
		anchor = Vector2.new(0.5, 0),
		ts = 28,
		font = F.TITLE,
		color = Color3.new(1, 1, 1), -- White text
		parent = main,
		z = 10
	})
	
	-- Close Button (Scaled)
	Utils.mkBtn({
		text = "X",
		size = UDim2.fromScale(0.08, 0.08),
		pos = UDim2.fromScale(0.85, 0.15),
		anchor = Vector2.new(0.5, 0.5),
		bg = Color3.fromRGB(100, 30, 30),
		ts = 20,
		font = F.TITLE,
		r = "full",
		fn = function() UIManager.toggleSkillTree() end,
		parent = main,
		z = 15
	})

	-- Calculate mathematically perfect equilateral triangle centered at 0.5, 0.5
	-- R is scaled linearly: (Original 0.28) * (Bg Scale 1.25) = 0.35
	local R = 0.35 
	local slotPos = {
		RUNE1 = UDim2.fromScale(0.5, 0.5 - R), -- Top
		RUNE2 = UDim2.fromScale(0.5 - R * 0.866, 0.5 + R * 0.5), -- Bottom Left (30 deg down)
		RUNE3 = UDim2.fromScale(0.5 + R * 0.866, 0.5 + R * 0.5)  -- Bottom Right
	}

	-- 3. Central Decorative Circle (Navy Border) - Even Larger and Responsive
	local centerCircle = Utils.mkFrame({
		name = "CenterCircle",
		size = UDim2.fromScale(0.35, 0.35), -- Increased slightly from 0.32 to 0.35 for stronger dominance
		pos = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		bg = Color3.fromRGB(20, 25, 40),
		bgT = 1.0, -- Transparent background, only border
		r = "full", -- Circular
		stroke = 2.5,
		strokeC = Color3.fromRGB(20, 40, 80), -- Deep Navy Blue matching outer frame
		parent = main,
		z = 4
	})

	-- Inner Image for the Player's Element (Larger Pop Effect)
	local elementIcon = Instance.new("ImageLabel")
	elementIcon.Name = "ElementIcon"
	elementIcon.Size = UDim2.fromScale(1.15, 1.15) -- Increased to 1.15 to break the frame and look more powerful
	elementIcon.Position = UDim2.fromScale(0.5, 0.5)
	elementIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	elementIcon.BackgroundTransparency = 1
	elementIcon.Image = ""
	elementIcon.ZIndex = 5
	elementIcon.Parent = centerCircle
	SkillTreeUI.Refs.ElementIcon = elementIcon


	-- Create Slots (Responsive)
	for id, pos in pairs(slotPos) do
		local slotFrame = Utils.mkFrame({
			name = id.."_Slot",
			size = UDim2.fromScale(0.18, 0.18), -- Responsive relative sizing (approx 90px at 500px)
			pos = pos,
			anchor = Vector2.new(0.5, 0.5),
			bg = Color3.fromRGB(20, 25, 40),
			bgT = 0.3,
			r = "full", -- Circular Scaling
			stroke = 2,
			strokeC = MAGIC_GOLD,
			parent = main,
			z = 5
		})
		
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.75, 0, 0.75, 0)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = ""
		icon.Visible = false
		icon.ZIndex = 6
		icon.Parent = slotFrame
		
		-- Click Area
		local click = Instance.new("TextButton")
		click.Name = "Click"
		click.Size = UDim2.new(1, 0, 1, 0)
		click.BackgroundTransparency = 1
		click.Text = ""
		click.ZIndex = 10
		click.Parent = slotFrame
		
		local _lastClick = 0
		click.MouseButton1Click:Connect(function()
			local t = tick()
			if t - _lastClick < 0.4 then
				-- Double Click: Unequip
				InventoryController.requestUnequip(id)
			end
			_lastClick = t
		end)
		
		SkillTreeUI.Refs.Slots[id] = {
			frame = slotFrame,
			icon = icon,
			click = click
		}
	end
	
	-- Listen to updates from controller
	local conn = InventoryController.onChanged(function()
		if frame.Visible then
			SkillTreeUI.Refresh()
		end
	end)
	table.insert(_connections, conn)
	
	-- Tooltip Label at the bottom
	Utils.mkLabel({
		text = UILocalizer.Localize("인벤토리에서 룬을 드래그해 장착하세요.\n더블클릭하여 해제할 수 있습니다."),
		size = UDim2.new(1, 0, 0, 50),
		pos = UDim2.new(0.5, 0, 0.9, 0),
		anchor = Vector2.new(0.5, 1),
		ts = 16,
		font = F.NORMAL,
		color = Color3.fromRGB(200, 200, 200),
		parent = main,
		z = 10
	})
end

function SkillTreeUI.Refresh()
	if not SkillTreeUI.Refs.Frame or not SkillTreeUI.Refs.Frame.Visible then return end
	
	-- 1. Update Center Element Icon
	local player = Players.LocalPlayer
	local currentElement = player and player:GetAttribute("Element")
	if SkillTreeUI.Refs.ElementIcon and currentElement and currentElement ~= "" then
		-- Attempt dynamic lookup from Assets/UI/Element_[Name]
		local assetFolder = ReplicatedStorage:FindFirstChild("Assets")
		local uiFolder = assetFolder and assetFolder:FindFirstChild("UI")
		if uiFolder then
			-- Looks for 'Element_Fire', 'Element_Water', 'Element_Earth'
			local assetName = "Element_" .. currentElement
			local elementAsset = uiFolder:FindFirstChild(assetName)
			if elementAsset and (elementAsset:IsA("ImageLabel") or elementAsset:IsA("Decal") or elementAsset:IsA("Texture")) then
				SkillTreeUI.Refs.ElementIcon.Image = elementAsset:IsA("ImageLabel") and elementAsset.Image or (elementAsset.Texture or SkillTreeUI.Refs.ElementIcon.Image)
				SkillTreeUI.Refs.ElementIcon.Visible = true
			else
				SkillTreeUI.Refs.ElementIcon.Visible = false
			end
		end
	elseif SkillTreeUI.Refs.ElementIcon then
		SkillTreeUI.Refs.ElementIcon.Visible = false
	end
	
	-- 2. Update Rune Slots
	local equip = InventoryController.getEquipment()
	
	for id, slotRef in pairs(SkillTreeUI.Refs.Slots) do
		local eqItem = equip[id]
		if eqItem and eqItem.itemId then
			local itemData = DataHelper.GetData("ItemData", eqItem.itemId)
			slotRef.icon.Image = _UIManager and _UIManager.getItemIcon(eqItem.itemId) or ""
			slotRef.icon.Visible = true
			
			-- Set border color based on rarity
			local rarityColor = MAGIC_GOLD
			if itemData and itemData.rarity == "RARE" then rarityColor = Color3.fromRGB(80, 180, 255)
			elseif itemData and itemData.rarity == "EPIC" then rarityColor = Color3.fromRGB(180, 100, 255)
			elseif itemData and itemData.rarity == "LEGENDARY" then rarityColor = Color3.fromRGB(255, 180, 50)
			end
			slotRef.frame.UIStroke.Color = rarityColor
		else
			slotRef.icon.Image = ""
			slotRef.icon.Visible = false
			slotRef.frame.UIStroke.Color = MAGIC_GOLD
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
