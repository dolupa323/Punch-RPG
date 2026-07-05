-- SkillTreeUI.lua (Untitled RPG style Skill UI)
-- 탭 시스템이 탑재된 세련된 스킬 & 스킬북 UI 창

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local UI = script.Parent
local Theme = require(UI:WaitForChild("UITheme"))
local Utils = require(UI:WaitForChild("UIUtils"))
local UILocalizer = require(Client:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local SkillController = require(Client:WaitForChild("Controllers"):WaitForChild("SkillController"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))

-- Navy + Black Theme (EquipmentUI와 동일)
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
	SkillTabContent = nil,
	ActiveList = nil,
	PassiveList = nil,
}

local _UIManager = nil
local _isMobile = false
local _connections = {}

-- 다음 비어있는 슬롯 반환 (1=E, 2=R, 3=T). 없으면 nil
local function findNextEmptySlot(activeSlots)
	for i = 1, 3 do
		local v = activeSlots[i]
		if not v or v == "" then
			return i
		end
	end
	return nil
end

local SLOT_NAMES = { [1] = "E", [2] = "R", [3] = "T" }

function SkillTreeUI.SetVisible(visible)
	if SkillTreeUI.Refs.Frame then
		SkillTreeUI.Refs.Frame.Visible = visible
		if visible then
			SkillController.requestData(function()
				SkillTreeUI.Refresh()
			end)
		else
			local HUDUI = require(UI:WaitForChild("HUDUI"))
			if HUDUI.HideTooltip then
				HUDUI.HideTooltip()
			end
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
	
	-- 2. Main Window
	local main = Utils.mkWindow({
		name = "SkillWindow",
		size = UDim2.new(isSmall and 0.95 or 0.65, 0, isSmall and 0.8 or 0.65, 0),
		maxSize = Vector2.new(850, 500),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = frame
	})
	
	-- Title Header
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	Utils.mkLabel({text=UILocalizer.Localize("스킬 [Skill System]"), pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1,0.5), bgT=0.5, ts=20, color=C.WHITE, isNegative=true, r=4, fn=function() UIManager.toggleSkillTree() end, parent=header})
	
	-- Content Body
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -65), pos=UDim2.new(0, 10, 0, 55), bgT=1, active=false, parent=main})
	
	-- Skill Content (Active / Passive Lists)
	local skillTabContent = Utils.mkFrame({name="SkillTabContent", size=UDim2.new(1, 0, 1, 0), bgT=1, active=false, parent=content})
	SkillTreeUI.Refs.SkillTabContent = skillTabContent
	
	-- Left Side: Active Skills
	local leftPanel = Utils.mkFrame({name="LeftPanel", size=UDim2.new(0.5, -10, 1, 0), pos=UDim2.new(0, 0, 0, 0), bg=C.BG_DARK, bgT=0.5, r=6, active=false, parent=skillTabContent})
	Utils.mkLabel({text="액티브 스킬 (Active Skills)", size=UDim2.new(1, 0, 0, 30), pos=UDim2.new(0,0,0,5), ts=15, font=F.TITLE, color=Color3.fromRGB(200, 220, 255), parent=leftPanel})
	
	local activeScroll = Instance.new("ScrollingFrame")
	activeScroll.Size = UDim2.new(1, -10, 1, -45)
	activeScroll.Position = UDim2.new(0, 5, 0, 40)
	activeScroll.BackgroundTransparency = 1
	activeScroll.BorderSizePixel = 0
	activeScroll.ScrollBarThickness = 4
	activeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	activeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	activeScroll.Active = false
	activeScroll.Parent = leftPanel
	
	local activeLayout = Instance.new("UIListLayout")
	activeLayout.Padding = UDim.new(0, 6)
	activeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	activeLayout.Parent = activeScroll
	SkillTreeUI.Refs.ActiveList = activeScroll
 
	-- Right Side: Passive Skills
	local rightPanel = Utils.mkFrame({name="RightPanel", size=UDim2.new(0.5, -10, 1, 0), pos=UDim2.new(0.5, 10, 0, 0), bg=C.BG_DARK, bgT=0.5, r=6, active=false, parent=skillTabContent})
	Utils.mkLabel({text="패시브 스킬 (Passive Skills)", size=UDim2.new(1, 0, 0, 30), pos=UDim2.new(0,0,0,5), ts=15, font=F.TITLE, color=Color3.fromRGB(255, 220, 200), parent=rightPanel})
	
	local passiveScroll = Instance.new("ScrollingFrame")
	passiveScroll.Size = UDim2.new(1, -10, 1, -45)
	passiveScroll.Position = UDim2.new(0, 5, 0, 40)
	passiveScroll.BackgroundTransparency = 1
	passiveScroll.BorderSizePixel = 0
	passiveScroll.ScrollBarThickness = 4
	passiveScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	passiveScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	passiveScroll.Active = false
	passiveScroll.Parent = rightPanel
	
	local passiveLayout = Instance.new("UIListLayout")
	passiveLayout.Padding = UDim.new(0, 6)
	passiveLayout.SortOrder = Enum.SortOrder.LayoutOrder
	passiveLayout.Parent = passiveScroll
	SkillTreeUI.Refs.PassiveList = passiveScroll
 
	-- Controller listeners
	SkillController.onSkillDataUpdated(function()
		SkillTreeUI.Refresh()
	end)
end

function SkillTreeUI.Refresh()
	if not SkillTreeUI.Refs.Frame or not SkillTreeUI.Refs.Frame.Visible then return end
	
	-- Clear dynamically rendered elements
	for _, child in ipairs(SkillTreeUI.Refs.ActiveList:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
	for _, child in ipairs(SkillTreeUI.Refs.PassiveList:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end

	local unlocked = SkillController.getUnlockedSkills()
	local activeSlots = SkillController.getActiveSkillSlots()
	local equippedPassives = SkillController.getEquippedPassives()

	-- 1. Render Skills (Active & Passive)
	local SkillTreeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("SkillTreeData"))
	local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))

	-- Collect all skills from SkillTreeData
	local allSkills = {}
	for _, treeId in ipairs({ "SWORD", "BOW", "AXE", "RUNES" }) do
		local tree = SkillTreeData[treeId]
		if tree then
			for _, skill in ipairs(tree) do
				table.insert(allSkills, skill)
			end
		end
	end

	-- Render each learned skill
	for _, skill in ipairs(allSkills) do
		if unlocked[skill.id] then
			local item = Utils.mkFrame({
				name = skill.id .. "_Item",
				size = UDim2.new(1, -6, 0, 60),
				bg = C.BG_SLOT,
				bgT = 0.5,
				r = 6,
				stroke = 1.0,
				strokeC = C.BORDER_DIM,
				active = false,
			})

			-- Icon
			local iconImg = Instance.new("ImageLabel")
			iconImg.Size = UDim2.new(0, 40, 0, 40)
			iconImg.Position = UDim2.new(0, 8, 0.5, 0)
			iconImg.AnchorPoint = Vector2.new(0, 0.5)
			iconImg.BackgroundTransparency = 1
			iconImg.Image = _UIManager and _UIManager.getItemIcon(skill.icon) or "rbxassetid://13515086700"
			iconImg.Parent = item

			-- Info Label
			Utils.mkLabel({
				text = string.format("<font color='#FFFFFF'>%s</font>\n<font size='10' color='#8AA0B8'>%s</font>", skill.name, skill.description or ""),
				size = UDim2.new(1, -125, 1, 0),
				pos = UDim2.new(0, 56, 0, 0),
				ax = Enum.TextXAlignment.Left,
				ay = Enum.TextYAlignment.Center,
				wrap = true,
				rich = true,
				ts = 13,
				parent = item
			})

			if skill.type == "ACTIVE" then
				-- 현재 장착된 슬롯 확인
				local equippedSlot = nil
				for i = 1, 3 do
					if activeSlots[i] ~= "" and activeSlots[i] == skill.id then
						equippedSlot = i
						break
					end
				end

				local btnContainer = Utils.mkFrame({
					name = "ActiveBtn",
					size = UDim2.new(0, 55, 0, 26),
					pos = UDim2.new(1, -8, 0.5, 0),
					anchor = Vector2.new(1, 0.5),
					bgT = 1,
					active = false,
					parent = item
				})

				if equippedSlot then
					-- 장착 중 → 슬롯 이름 뱃지 + 해제 버튼
					Utils.mkBtn({
						name = "UnequipBtn",
						text = SLOT_NAMES[equippedSlot] .. " 해제",
						size = UDim2.new(1, 0, 1, 0),
						pos = UDim2.new(0.5, 0, 0.5, 0),
						anchor = Vector2.new(0.5, 0.5),
						ts = 11,
						isNegative = true,
						bg = C.BTN_GRAY,
						bgT = 0.3,
						hbg = C.BTN_GRAY_H,
						color = C.INK,
						fn = function()
							SkillController.requestSetSlot(equippedSlot, nil, function(ok, err)
								if not ok then
									_UIManager.notify("해제 실패: " .. tostring(err or "Unknown"), Color3.fromRGB(255, 100, 100))
								end
							end)
						end,
						parent = btnContainer
					})
				else
					-- 미장착 → 장착 버튼 (다음 빈 슬롯에 순차 배치)
					Utils.mkBtn({
						name = "EquipBtn",
						text = UILocalizer.Localize("장착"),
						size = UDim2.new(1, 0, 1, 0),
						pos = UDim2.new(0.5, 0, 0.5, 0),
						anchor = Vector2.new(0.5, 0.5),
						ts = 11,
						bg = C.BORDER,
						bgT = 0.3,
						hbg = C.BORDER_SEL,
						color = C.WHITE,
						fn = function()
							local slots = SkillController.getActiveSkillSlots()
							local nextSlot = findNextEmptySlot(slots)
							if not nextSlot then
								_UIManager.notify("슬롯이 가득 찼습니다. 기존 스킬을 해제하세요.", Color3.fromRGB(255, 200, 100))
								return
							end
							SkillController.requestSetSlot(nextSlot, skill.id, function(ok, err)
								if not ok then
									local msg = "장착 실패: " .. tostring(err or "Unknown")
									if err == "AURA_SKILL_CONFLICT" then
										msg = "오라류 스킬은 하나만 장착가능합니다."
									end
									_UIManager.notify(msg, Color3.fromRGB(255, 100, 100))
								end
							end)
						end,
						parent = btnContainer
					})
				end

				item.Parent = SkillTreeUI.Refs.ActiveList
			elseif skill.type == "PASSIVE" then
				-- Render Passive slots assignment
				local btnContainer = Utils.mkFrame({
					name = "PassiveBtn",
					size = UDim2.new(0, 55, 0, 26), -- 액티브 스킬 배지와 완전히 대칭되는 크기 (55x26)
					pos = UDim2.new(1, -8, 0.5, 0),
					anchor = Vector2.new(1, 0.5),
					bgT = 1,
					active = false, -- 자식 텍스트 버튼 클릭 차단 방지
					parent = item
				})

				local isAssigned = false
				for _, sid in pairs(equippedPassives) do
					if sid == skill.id then
						isAssigned = true
						break
					end
				end

				if isAssigned then
					Utils.mkBtn({
						name = "EquippedBtn",
						text = UILocalizer.Localize("해제"),
						size = UDim2.new(1, 0, 1, 0),
						pos = UDim2.new(0.5, 0, 0.5, 0),
						anchor = Vector2.new(0.5, 0.5),
						ts = 11,
						isNegative = true,
						bg = C.BTN_GRAY,
						bgT = 0.3,
						hbg = C.BTN_GRAY_H,
						color = C.INK,
						fn = function()
							print("[SkillTreeUI] Unequip clicked for passive:", skill.id)
							SkillController.requestUnequipPassive(skill.id, function(success, err)
								if not success then
									warn("[SkillTreeUI] Unequip failed:", err)
									_UIManager.notify("해제 실패: " .. tostring(err or "Unknown"), Color3.fromRGB(255, 100, 100))
								else
									print("[SkillTreeUI] Unequip success!")
								end
							end)
						end,
						parent = btnContainer
					})
				else
					Utils.mkBtn({
						name = "EquipBtn",
						text = UILocalizer.Localize("장착"),
						size = UDim2.new(1, 0, 1, 0),
						pos = UDim2.new(0.5, 0, 0.5, 0),
						anchor = Vector2.new(0.5, 0.5),
						ts = 11,
						bg = C.BORDER,
						bgT = 0.3,
						hbg = C.BORDER_SEL,
						color = C.WHITE,
						fn = function()
							print("[SkillTreeUI] Equip clicked for passive:", skill.id)
							SkillController.requestEquipPassive(skill.id, skill.id, function(success, err)
								if not success then
									warn("[SkillTreeUI] Equip failed:", err)
									_UIManager.notify("장착 실패: " .. tostring(err or "Unknown"), Color3.fromRGB(255, 100, 100))
								else
									print("[SkillTreeUI] Equip success!")
								end
							end)
						end,
						parent = btnContainer
					})
				end

				item.Parent = SkillTreeUI.Refs.PassiveList
			end
		end
	end

end

function SkillTreeUI.SetController(controller)
	SkillController = controller
end

return SkillTreeUI
