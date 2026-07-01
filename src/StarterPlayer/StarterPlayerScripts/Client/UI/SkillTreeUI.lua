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
	SkillTabBtn = nil,
	BookTabBtn = nil,
	SkillTabContent = nil,
	BookTabContent = nil,
	ActiveList = nil,
	PassiveList = nil,
	BookList = nil,
}

local _UIManager = nil
local _isMobile = false
local _connections = {}
local currentTab = "SKILL" -- "SKILL" or "BOOK"
local selectedBookId = nil

local function showKeyBindModal(skillId)
	local modal = SkillTreeUI.Refs.KeyBindModal
	if not modal then return end
	
	-- Clear old buttons/labels
	for _, child in ipairs(modal:GetChildren()) do
		if not child:IsA("UIAspectRatioConstraint") then child:Destroy() end
	end
	
	-- Title
	Utils.mkLabel({
		text = UILocalizer.Localize("스킬 장착 [Equip Skill]"),
		size = UDim2.new(1, 0, 0, 32),
		pos = UDim2.new(0, 0, 0, 15),
		ts = 18,
		font = F.TITLE,
		color = C.GOLD,
		parent = modal
	})
	
	local SkillTreeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("SkillTreeData"))
	local skillData = SkillTreeData.GetSkill(skillId)
	local skillName = skillData and skillData.name or "스킬"
	Utils.mkLabel({
		text = string.format("'%s' 스킬을 장착할 슬롯을 선택하세요.", skillName),
		size = UDim2.new(1, -20, 0, 30),
		pos = UDim2.new(0.5, 0, 0, 48),
		anchor = Vector2.new(0.5, 0),
		ts = 13,
		color = C.WHITE,
		wrap = true,
		parent = modal
	})
	
	-- Buttons Container
	local btnList = Utils.mkFrame({
		name = "Buttons",
		size = UDim2.new(0.9, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0, 85),
		anchor = Vector2.new(0.5, 0),
		bgT = 1,
		parent = modal
	})
	
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = btnList
	
	local keys = {"E", "R", "T"}
	local activeSlots = SkillController.getActiveSkillSlots()
	for i, keyName in ipairs(keys) do
		local slotIndex = i
		local isCurrentlyAssigned = (activeSlots[i] == skillId)
		Utils.mkBtn({
			text = keyName .. " 슬롯",
			size = UDim2.new(0.31, 0, 1, 0),
			ts = 13,
			bg = isCurrentlyAssigned and Color3.fromRGB(0, 102, 204) or C.BG_SLOT,
			color = C.WHITE,
			hbg = isCurrentlyAssigned and Color3.fromRGB(51, 153, 255) or C.BG_PANEL_L,
				fn = function()
					SkillController.requestSetSlot(slotIndex, skillId, function(ok, err)
						if ok then
							modal.Visible = false
							return
						end
						local manager = _UIManager
						if manager and manager.notify then
							local message = string.format("슬롯 배치 실패: %s", tostring(err or "UNKNOWN"))
							if err == "AURA_SKILL_CONFLICT" then
								message = "오라류 스킬은 하나만 장착가능합니다."
							end
							manager.notify(message, Color3.fromRGB(255, 140, 140))
						end
					end)
				end,
			parent = btnList
		})
	end
	
	-- Unequip / Cancel row
	local bottomRow = Utils.mkFrame({
		size = UDim2.new(0.9, 0, 0, 36),
		pos = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = modal
	})
	
	local bottomLayout = Instance.new("UIListLayout")
	bottomLayout.FillDirection = Enum.FillDirection.Horizontal
	bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bottomLayout.Padding = UDim.new(0, 10)
	bottomLayout.Parent = bottomRow
	
	-- Check if currently equipped in any slot
	local equippedSlot = nil
	for i = 1, 3 do
		if activeSlots[i] == skillId then
			equippedSlot = i
			break
		end
	end
	
	if equippedSlot then
		Utils.mkBtn({
			text = UILocalizer.Localize("장착 해제"),
			size = UDim2.new(0.45, 0, 1, 0),
			ts = 13,
			isNegative = true,
			bg = C.BTN_GRAY,
			hbg = C.BTN_GRAY_H,
			color = C.INK,
			fn = function()
				SkillController.requestSetSlot(equippedSlot, nil)
				modal.Visible = false
			end,
			parent = bottomRow
		})
	end
	
	Utils.mkBtn({
		text = UILocalizer.Localize("취소"),
		size = UDim2.new(equippedSlot and 0.45 or 0.9, 0, 1, 0),
		ts = 13,
		isNegative = true,
		fn = function()
			modal.Visible = false
		end,
		parent = bottomRow
	})
	
	modal.Visible = true
end

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
	
	-- Tab Buttons Container
	local tabContainer = Utils.mkFrame({name="TabContainer", size=UDim2.new(1, -20, 0, 35), pos=UDim2.new(0, 10, 0, 50), bgT=1, parent=main})
	
	local skillTabBtn = Utils.mkBtn({
		name = "SkillTabBtn",
		text = UILocalizer.Localize("보유 스킬"),
		size = UDim2.new(0.5, -5, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		ts = 15,
		font = F.TITLE,
		color = C.WHITE,
		bg = C.BG_SLOT,
		bgT = 0.4,
		hbg = C.BG_PANEL_L,
		fn = function()
			currentTab = "SKILL"
			SkillTreeUI.UpdateTabState()
		end,
		parent = tabContainer
	})
	SkillTreeUI.Refs.SkillTabBtn = skillTabBtn

	local bookTabBtn = Utils.mkBtn({
		name = "BookTabBtn",
		text = UILocalizer.Localize("소장 스킬북"),
		size = UDim2.new(0.5, -5, 1, 0),
		pos = UDim2.new(0.5, 5, 0, 0),
		ts = 15,
		font = F.TITLE,
		color = C.WHITE,
		bg = C.BG_SLOT,
		bgT = 0.8,
		hbg = C.BG_PANEL_L,
		fn = function()
			currentTab = "BOOK"
			SkillTreeUI.UpdateTabState()
		end,
		parent = tabContainer
	})
	SkillTreeUI.Refs.BookTabBtn = bookTabBtn

	-- Content Body
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -105), pos=UDim2.new(0, 10, 0, 95), bgT=1, active=false, parent=main})
	
	-- Skill Tab Content (Active / Passive Lists)
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
 
	-- Book Tab Content (Skill Book Grid + Detail Panel)
	local bookTabContent = Utils.mkFrame({name="BookTabContent", size=UDim2.new(1, 0, 1, 0), bgT=1, active=false, vis=false, parent=content})
	SkillTreeUI.Refs.BookTabContent = bookTabContent

	-- Left: Grid Panel
	local bookLeft = Utils.mkFrame({name="BookLeft", size=UDim2.new(isSmall and 0.55 or 0.6, -8, 1, 0), pos=UDim2.new(0, 0, 0, 0), bgT=1, parent=bookTabContent})

	local bookScroll = Instance.new("ScrollingFrame")
	bookScroll.Size = UDim2.new(1, 0, 1, 0)
	bookScroll.BackgroundTransparency = 1
	bookScroll.BorderSizePixel = 0
	bookScroll.ScrollBarThickness = 4
	bookScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bookScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	bookScroll.Parent = bookLeft
	
	local bookGrid = Instance.new("UIGridLayout")
	bookGrid.CellSize = UDim2.new(isSmall and 0.45 or 0.31, -8, 0, isSmall and 90 or 120)
	bookGrid.CellPadding = UDim2.new(0, 8, 0, 8)
	bookGrid.Parent = bookScroll
	SkillTreeUI.Refs.BookList = bookScroll

	-- Right: Details Panel
	local bookDetail = Utils.mkFrame({name="BookDetail", size=UDim2.new(isSmall and 0.45 or 0.4, 8, 1, 0), pos=UDim2.new(isSmall and 0.55 or 0.6, 8, 0, 0), bg=C.BG_DARK, bgT=0.5, r=6, parent=bookTabContent})
	SkillTreeUI.Refs.BookDetail = bookDetail

	-- Key Binding Modal (Popup)
	local bindModal = Utils.mkFrame({
		name = "KeyBindModal",
		size = UDim2.new(isSmall and 0.65 or 0.4, 0, isSmall and 0.55 or 0.45, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.05,
		r = 8,
		stroke = 2,
		strokeC = C.BORDER,
		vis = false,
		z = 100,
		parent = frame,
	})
	local mRatio = Instance.new("UIAspectRatioConstraint")
	mRatio.AspectRatio = 1.35
	mRatio.Parent = bindModal
	SkillTreeUI.Refs.KeyBindModal = bindModal

	-- Controller listeners
	SkillController.onSkillDataUpdated(function()
		SkillTreeUI.Refresh()
	end)
end

function SkillTreeUI.UpdateTabState()
	if currentTab == "SKILL" then
		Utils.setBtnState(SkillTreeUI.Refs.SkillTabBtn, C.BG_SLOT, 0.2)
		Utils.setBtnState(SkillTreeUI.Refs.BookTabBtn, C.BG_SLOT, 0.8)
		SkillTreeUI.Refs.SkillTabContent.Visible = true
		SkillTreeUI.Refs.BookTabContent.Visible = false
	else
		Utils.setBtnState(SkillTreeUI.Refs.SkillTabBtn, C.BG_SLOT, 0.8)
		Utils.setBtnState(SkillTreeUI.Refs.BookTabBtn, C.BG_SLOT, 0.2)
		SkillTreeUI.Refs.SkillTabContent.Visible = false
		SkillTreeUI.Refs.BookTabContent.Visible = true
	end
	SkillTreeUI.Refresh()
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
	for _, child in ipairs(SkillTreeUI.Refs.BookList:GetChildren()) do
		if not child:IsA("UIGridLayout") then child:Destroy() end
	end

	local unlocked = SkillController.getUnlockedSkills()
	local activeSlots = SkillController.getActiveSkillSlots()
	local equippedPassives = SkillController.getEquippedPassives()
	local skillBooks = SkillController.getSkillBooks()

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
	-- Render each learned skill
	for _, skill in ipairs(allSkills) do
		if unlocked[skill.id] then
			local item
			if skill.type == "ACTIVE" then
				item = Utils.mkBtn({
					name = skill.id .. "_Item",
					text = "",
					size = UDim2.new(1, -6, 0, 60), -- 모바일 대응을 위해 높이를 60으로 축소
					bg = C.BG_SLOT,
					bgT = 0.5,
					r = 6,
					stroke = 1.0,
					strokeC = C.BORDER_DIM, -- 옐로우/블루 대신 UI 컨벤션에 맞춘 차분한 네이비 테두리 적용
					hbg = C.BG_PANEL_L,
					fn = function()
						showKeyBindModal(skill.id)
					end,
				})
			else
				item = Utils.mkFrame({
					name = skill.id .. "_Item",
					size = UDim2.new(1, -6, 0, 60), -- 모바일 대응을 위해 높이를 60으로 축소
					bg = C.BG_SLOT,
					bgT = 0.5,
					r = 6,
					stroke = 1.0,
					strokeC = C.BORDER_DIM, -- 옐로우/블루 대신 UI 컨벤션에 맞춘 차분한 네이비 테두리 적용
					active = false, -- 마우스 클릭 이벤트 통과 허용
				})
			end

			-- Icon
			local iconImg = Instance.new("ImageLabel")
			iconImg.Size = UDim2.new(0, 40, 0, 40) -- 아이콘 크기 최적화 (40x40)
			iconImg.Position = UDim2.new(0, 8, 0.5, 0)
			iconImg.AnchorPoint = Vector2.new(0, 0.5)
			iconImg.BackgroundTransparency = 1
			iconImg.Image = _UIManager and _UIManager.getItemIcon(skill.icon) or "rbxassetid://13515086700"
			iconImg.Parent = item

			-- Info Label (버튼 영역과 겹치지 않도록 너비 설정 최적화)
			local info = Utils.mkLabel({
				text = string.format("<font color='#FFFFFF'>%s</font>\n<font size='10' color='#8AA0B8'>%s</font>", skill.name, skill.description or ""),
				size = UDim2.new(1, -125, 1, 0), -- 전체 너비에서 아이콘(56px)과 우측 버튼(65px) 공간 제외하여 오버랩 원천 차단
				pos = UDim2.new(0, 56, 0, 0),
				ax = Enum.TextXAlignment.Left,
				ay = Enum.TextYAlignment.Center,
				wrap = true,
				rich = true,
				ts = 13,
				parent = item
			})

			if skill.type == "ACTIVE" then
				-- Check if equipped in a slot
				local equippedSlotName = nil
				for i = 1, 4 do
					local slotSkillId = activeSlots[i]
					if slotSkillId == skill.id then
						if i == 1 then equippedSlotName = "E"
						elseif i == 2 then equippedSlotName = "R"
						elseif i == 3 then equippedSlotName = "T"
						else equippedSlotName = tostring(i)
						end
						break
					end
				end
				
				if equippedSlotName then
					-- Render a nice badge on the right
					local badge = Utils.mkFrame({
						name = "EquippedBadge",
						size = UDim2.new(0, 55, 0, 26), -- 크기 축소 (55x26)
						pos = UDim2.new(1, -8, 0.5, 0),
						anchor = Vector2.new(1, 0.5),
						bg = Color3.fromRGB(40, 80, 160), -- 튀는 파란색 대신 네이비 톤 컬러 적용
						r = 4,
						parent = item
					})
					Utils.mkLabel({
						text = equippedSlotName,
						size = UDim2.new(1, 0, 1, 0),
						ts = 12,
						font = F.TITLE,
						color = C.WHITE,
						parent = badge
					})
				else
					-- Render "미장착" text on the right
					Utils.mkLabel({
						text = UILocalizer.Localize("미장착"),
						size = UDim2.new(0, 55, 0, 26),
						pos = UDim2.new(1, -8, 0.5, 0),
						anchor = Vector2.new(1, 0.5),
						ts = 11,
						color = C.GRAY,
						ax = Enum.TextXAlignment.Center,
						parent = item
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

	-- Clear all children of BookDetail
	local bookDetail = SkillTreeUI.Refs.BookDetail
	if bookDetail then
		for _, child in ipairs(bookDetail:GetChildren()) do
			child:Destroy()
		end
	end

	-- 2. Render Skill Books
	local isSmall = _isMobile
	if #skillBooks > 0 then
		-- Automatically select first book if selectedBookId is invalid or not set
		local hasSelectedBook = false
		for _, bid in ipairs(skillBooks) do
			if bid == selectedBookId then
				hasSelectedBook = true
				break
			end
		end
		if not hasSelectedBook then
			selectedBookId = skillBooks[1]
		end
	else
		selectedBookId = nil
	end

	for _, bookId in ipairs(skillBooks) do
		local bookData = nil
		for _, item in ipairs(ItemData) do
			if item.id == bookId then
				bookData = item
				break
			end
		end

		if bookData then
			local isSelected = (selectedBookId == bookId)
			local displayName = bookData.name:gsub("^스킬북:%s*", "")

			local cardBorderC = C.BORDER_DIM
			if bookData.runeType == "ACTIVE" then
				cardBorderC = Color3.fromRGB(80, 170, 255)
			elseif bookData.runeType == "PASSIVE" then
				cardBorderC = Color3.fromRGB(230, 180, 60)
			end

			local card = Utils.mkBtn({
				name = bookId .. "_Card",
				text = "",
				size = UDim2.new(1, 0, 1, 0),
				bg = C.BG_SLOT,
				bgT = isSelected and 0.2 or 0.6,
				r = 6,
				stroke = isSelected and 2.5 or 1.5,
				strokeC = isSelected and C.GOLD_SEL or cardBorderC,
				hbg = C.BG_PANEL_L,
				fn = function()
					selectedBookId = bookId
					SkillTreeUI.Refresh()
				end,
				parent = SkillTreeUI.Refs.BookList
			})

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, isSmall and 36 or 48, 0, isSmall and 36 or 48)
			icon.Position = UDim2.new(0.5, 0, 0, 10)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.BackgroundTransparency = 1
			icon.Image = _UIManager and _UIManager.getItemIcon(bookData.iconName or bookData.id) or "rbxassetid://13515086700"
			icon.Parent = card

			Utils.mkLabel({
				text = displayName,
				size = UDim2.new(1, -10, 0, 40),
				pos = UDim2.new(0.5, 0, 0, isSmall and 50 or 65),
				anchor = Vector2.new(0.5, 0),
				ts = isSmall and 11 or 12,
				color = C.WHITE,
				wrap = true,
				parent = card
			})
		end
	end

	-- Populate Details Panel
	if bookDetail then
		if selectedBookId then
			local bookData = nil
			for _, item in ipairs(ItemData) do
				if item.id == selectedBookId then
					bookData = item
					break
				end
			end

			if bookData then
				-- Rarity Line
				local rarityColor = Color3.fromRGB(80, 180, 255) -- Default RARE blue
				if bookData.rarity == "COMMON" then rarityColor = C.COMMON
				elseif bookData.rarity == "UNCOMMON" then rarityColor = C.UNCOMMON
				elseif bookData.rarity == "EPIC" then rarityColor = C.EPIC
				elseif bookData.rarity == "UNIQUE" then rarityColor = C.UNIQUE
				elseif bookData.rarity == "LEGENDARY" then rarityColor = C.LEGENDARY
				end

				local rarityLine = Utils.mkFrame({
					name = "RarityLine",
					size = UDim2.new(1, 0, 0, 4),
					pos = UDim2.new(0, 0, 0, 0),
					bg = rarityColor,
					r = 0,
					parent = bookDetail
				})

				local iconBorderC = C.BORDER_DIM
				if bookData.runeType == "ACTIVE" then
					iconBorderC = Color3.fromRGB(80, 170, 255)
				elseif bookData.runeType == "PASSIVE" then
					iconBorderC = Color3.fromRGB(230, 180, 60)
				end

				-- Icon Frame
				local iconFrame = Utils.mkFrame({
					name = "IconFrame",
					size = UDim2.new(0, isSmall and 54 or 64, 0, isSmall and 54 or 64),
					pos = UDim2.new(0.5, 0, 0, 15),
					anchor = Vector2.new(0.5, 0),
					bg = C.BG_DARK,
					bgT = 0.5,
					r = 6,
					stroke = 1.5,
					strokeC = iconBorderC,
					parent = bookDetail
				})
				local icon = Instance.new("ImageLabel")
				icon.Size = UDim2.new(0.8, 0, 0.8, 0)
				icon.Position = UDim2.new(0.5, 0, 0.5, 0)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.BackgroundTransparency = 1
				icon.Image = _UIManager and _UIManager.getItemIcon(bookData.iconName or bookData.id) or "rbxassetid://13515086700"
				icon.Parent = iconFrame

				-- Display Name
				local displayName = bookData.name:gsub("^스킬북:%s*", "")
				Utils.mkLabel({
					text = displayName,
					size = UDim2.new(1, -16, 0, 24),
					pos = UDim2.new(0.5, 0, 0, isSmall and 75 or 90),
					anchor = Vector2.new(0.5, 0),
					ts = isSmall and 14 or 16,
					font = F.TITLE,
					color = rarityColor,
					parent = bookDetail
				})

				-- Description Scroll
				local descScroll = Instance.new("ScrollingFrame")
				descScroll.Size = UDim2.new(1, -16, 1, isSmall and -150 or -175)
				descScroll.Position = UDim2.new(0, 8, 0, isSmall and 105 or 125)
				descScroll.BackgroundTransparency = 1
				descScroll.BorderSizePixel = 0
				descScroll.ScrollBarThickness = 3
				descScroll.ScrollBarImageColor3 = C.BORDER
				descScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
				descScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
				descScroll.Parent = bookDetail
				
				local descLabel = Utils.mkLabel({
					text = bookData.description or "",
					size = UDim2.new(1, 0, 0, 0),
					ts = isSmall and 11 or 12,
					color = C.WHITE,
					wrap = true,
					ax = Enum.TextXAlignment.Center,
					ay = Enum.TextYAlignment.Top,
					parent = descScroll
				})
				descLabel.AutomaticSize = Enum.AutomaticSize.Y

				-- Use button
				Utils.mkBtn({
					name = "LearnBtn",
					text = UILocalizer.Localize("사용하기"),
					size = UDim2.new(0.9, 0, 0, isSmall and 32 or 38),
					pos = UDim2.new(0.5, 0, 1, -8),
					anchor = Vector2.new(0.5, 1),
					ts = isSmall and 13 or 14,
					bg = C.BORDER,
					color = C.WHITE,
					hbg = C.BORDER_SEL,
					fn = function()
						local targetId = selectedBookId
						SkillController.requestLearnBook(targetId, function(success, err)
							if success then
								_UIManager.notify("스킬을 무사히 습득했습니다!", Color3.fromRGB(100, 255, 100))
								if selectedBookId == targetId then
									selectedBookId = nil
								end
							else
								local message = "습득 실패: " .. tostring(err or "알 수 없는 에러")
								if err == "ALREADY_LEARNED" then
									message = "이미 습득한 스킬입니다."
								end
								_UIManager.notify(message, Color3.fromRGB(255, 100, 100))
							end
						end)
					end,
					parent = bookDetail
				})
			end
		else
			-- No book owned/selected placeholder
			Utils.mkLabel({
				text = UILocalizer.Localize("스킬북을 선택하세요."),
				size = UDim2.new(1, -20, 0, 30),
				pos = UDim2.new(0.5, 0, 0.5, 0),
				anchor = Vector2.new(0.5, 0.5),
				ts = 13,
				color = C.GRAY,
				parent = bookDetail
			})
		end
	end
end

function SkillTreeUI.SetController(controller)
	SkillController = controller
end

function SkillTreeUI.GetSlots()
	return SkillTreeUI.Refs.Slots
end

function SkillTreeUI.GetSelectedBookId()
	return selectedBookId
end

function SkillTreeUI.GetSelectedSkillId()
	return selectedSkillId
end

return SkillTreeUI
