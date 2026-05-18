-- EquipmentUI.lua
-- 듀랑고 레퍼런스 스타일 장비 및 스탯 종합 UI 창

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
-- Local Color Override for Navy + Black Theme
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
C.BG_SLOT = Color3.fromRGB(15, 20, 35)  -- Deep Navy
C.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White!
C.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN = Color3.fromRGB(40, 80, 160)      -- Action Buttons -> Navy instead of Yellow
C.BTN_H = Color3.fromRGB(60, 100, 190)   -- Button Hover

local F = Theme.Fonts
local T = Theme.Transp

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data").MaterialAttributeData)

local EquipmentUI = {}

EquipmentUI.Refs = {
	Frame = nil,
	Viewport = nil,
	Slots = {},
	StatPoints = nil,
	StatLines = {},
	ActionFrame = nil,
}

local tooltipMoveConn = nil

local _UIManager = nil -- UIManager 참조 저장용

function EquipmentUI.SetVisible(visible)
	if EquipmentUI.Refs.Frame then
		EquipmentUI.Refs.Frame.Visible = visible
	end
	if not visible and EquipmentUI.Refs.Tooltip then
		EquipmentUI.Refs.Tooltip.Visible = false
	end
end

function EquipmentUI.Init(parent, UIManager, Enums, isMobile)
	local isSmall = isMobile
	_UIManager = UIManager
	EquipmentUI.Refs.Frame = Utils.mkFrame({
		name = "EquipmentMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 1, -- GlobalDimBackground가 처리
		vis = false,
		parent = parent
	})

	local main = Utils.mkWindow({
		name = "EquipmentMenu",
		size = UDim2.new(isSmall and 0.95 or 0.65, 0, isSmall and 0.9 or 0.8, 0),
		maxSize = Vector2.new(900, 750),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = EquipmentUI.Refs.Frame
	})
	
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	Utils.mkLabel({text="EQUIPMENT [E]", pos=UDim2.new(0, 15, 0, 0), ts=26, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 42, 0, 42), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1,0.5), bgT=0.5, ts=24, color=C.WHITE, isNegative=true, r=4, fn=function() UIManager.closeEquipment() end, parent=header})
	
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	content.ClipsDescendants = true -- 캐릭터가 프레임 바깥으로 나가는 것 방지
	
	-- [Left: Character & Equip Slots] (45%)
	local eqArea = Utils.mkFrame({name="EquipArea", size=UDim2.new(0.45, -10, 1, 0), pos=UDim2.new(0, 0, 0, 0), bgT=1, parent=content})
	
	-- Slots Container
	local slotsContainer = Utils.mkFrame({
		name = "SlotsContainer",
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bgT = 1,
		parent = eqArea
	})

	local sGrid = Instance.new("UIGridLayout")
	sGrid.SortOrder = Enum.SortOrder.LayoutOrder
	sGrid.FillDirection = Enum.FillDirection.Vertical
	sGrid.StartCorner = Enum.StartCorner.TopLeft
	sGrid.CellSize = UDim2.new(0, 95, 0, 95)
	sGrid.CellPadding = UDim2.new(0, 16, 0, 15)
	sGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sGrid.VerticalAlignment = Enum.VerticalAlignment.Center
	sGrid.Parent = slotsContainer
	
	local slotConfigs = {
		{id="EARRING", name="귀걸이", order=1},
		{id="SUIT", name="한벌옷", order=2},
		{id="HAND", name="도구/무기", order=3},
		{id="NECKLACE", name="목걸이", order=4},
		{id="RING1", name="반지 1", order=5},
		{id="RING2", name="반지 2", order=6},
	}
	
	for i, conf in ipairs(slotConfigs) do
		local wrapper = Utils.mkFrame({
			name = conf.id.."Wrap",
			size = UDim2.new(1, 0, 1, 0),
			bgT = 1,
			parent = slotsContainer
		})
		wrapper.LayoutOrder = conf.order
		
		local slot = Utils.mkSlot({
			name = conf.id.."Slot", 
			size = UDim2.new(0, 60, 0, 60),
			pos = UDim2.new(0.5, 0, 0, 0),
			anchor = Vector2.new(0.5, 0.5),
			bgT = T.SLOT, 
			stroke = false, 
			parent = wrapper
		})
		
		Utils.mkLabel({
			text = UILocalizer.Localize(conf.name),
			size = UDim2.new(1, -4, 0, 20),
			pos = UDim2.new(0.5, -2, 1, 0),
			anchor = Vector2.new(0.5, 1),
			bgT = 1,
			ts = 15,
			font = F.NORMAL,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Center,
			parent = wrapper
		})
		
		slot.click.MouseButton1Click:Connect(function()
			local now = tick()
			if slot._lastClickTime and (now - slot._lastClickTime) < 0.4 then
				-- 더블클릭 → 장비 해제
				if _UIManager.onEquipmentSlotRightClick then _UIManager.onEquipmentSlotRightClick(conf.id) end
				slot._lastClickTime = nil
				-- 모바일 툴팁 닫기
				if EquipmentUI.Refs.Tooltip then EquipmentUI.Refs.Tooltip.Visible = false end
			else
				slot._lastClickTime = now
				-- 모바일일 경우 툴팁 토글, PC일 경우 장비 선택
				if isSmall then
					if EquipmentUI.Refs.Tooltip and EquipmentUI.Refs.Tooltip.Visible and EquipmentUI.Refs.Tooltip._lastSlot == conf.id then
						EquipmentUI.Refs.Tooltip.Visible = false
					else
						-- 툴팁 강제 호출을 위해 MouseEnter 로직 재사용 가능하게 하거나 직접 호출
						-- 여기서는 slot._showTooltip() 같은 함수가 미리 정의되어 있으면 좋음.
						-- 아래 Refresh 루프에서 정의될 예정이므로 일단 플래그만 세움.
						if slot._triggerTooltip then slot._triggerTooltip() end
						if EquipmentUI.Refs.Tooltip then EquipmentUI.Refs.Tooltip._lastSlot = conf.id end
					end
				else
					if _UIManager.onEquipmentSlotClick then _UIManager.onEquipmentSlotClick(conf.id) end
				end
			end
		end)
		slot.click.MouseButton2Click:Connect(function()
			if _UIManager.onEquipmentSlotRightClick then _UIManager.onEquipmentSlotRightClick(conf.id) end
		end)
		
		EquipmentUI.Refs.Slots[conf.id] = slot
	end
	
	-- [Right: Stats Distribution] (55%)
	local statArea = Utils.mkFrame({name="StatArea", size=UDim2.new(0.55, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1,0), bgT=1, parent=content})
	EquipmentUI.Refs.StatPoints = Utils.mkLabel({text=UILocalizer.Localize("보유 포인트: 0"), size=UDim2.new(1, -110, 0, 40), pos=UDim2.new(0,10,0,0), ts=24, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=statArea})
	
	-- 전부 초기화 버튼 (StatPoints 라벨 오른쪽)
	EquipmentUI.Refs.ResetAllBtn = Utils.mkBtn({
		text=UILocalizer.Localize("초기화"),
		size=UDim2.new(0, 110, 0, 36),
		pos=UDim2.new(1, -10, 0, 5),
		anchor=Vector2.new(1, 0),
		bg=C.BTN_GRAY,
		isNegative=true,
		ts=17,
		font=F.TITLE,
		parent=statArea
	})
	EquipmentUI.Refs.ResetAllBtn.MouseButton1Click:Connect(function()
		if UIManager.resetAllStats then UIManager.resetAllStats() end
	end)
	
	local statsScroll = Instance.new("ScrollingFrame")
	statsScroll.Size = UDim2.new(1,-20,1,-120); statsScroll.Position = UDim2.new(0,10,0,50); statsScroll.BackgroundTransparency = 1; statsScroll.BorderSizePixel = 0; statsScroll.ScrollBarThickness = 2; statsScroll.Parent = statArea
	local sLayout = Instance.new("UIListLayout"); sLayout.Padding=UDim.new(0, 5); sLayout.Parent=statsScroll
	
	local stats = {
		{id=Enums.StatId.MAX_HEALTH, name="최대 체력", up=true}, 
		{id=Enums.StatId.MAX_STAMINA, name="최대 스태미나", up=true}, 
		{id=Enums.StatId.INV_SLOTS, name="인벤토리 칸", up=true}, 
		{id=Enums.StatId.ATTACK, name="공격력", up=true},
		{id=Enums.StatId.DEFENSE, name="방어력", up=false}
	}
	for _, s in ipairs(stats) do
		-- 스텟 라인 크기 비율화 (배경 제거)
		local line = Utils.mkFrame({size=UDim2.new(1, 0, 0, 60), bgT=1, parent=statsScroll})
		Utils.mkLabel({text=UILocalizer.Localize(s.name), size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0,10,0,0), ts=20, ax=Enum.TextXAlignment.Left, parent=line})
		local val = Utils.mkLabel({text="0", size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0.8,-40,0,0), anchor=Vector2.new(1,0), ts=21, font=F.NUM, ax=Enum.TextXAlignment.Right, parent=line})
		
		-- 강화 버튼: 필요한 스탯에만 노출
		local btn = nil
		if s.up then
			local bSize = isSmall and 50 or 44
			btn = Utils.mkBtn({
				text="+", 
				size=UDim2.new(0, bSize, 0.8, 0), -- 가로 오프셋 고정, 세로 비율 유지
				pos=UDim2.new(1, -10, 0.5, 0), 
				anchor=Vector2.new(1, 0.5), 
				bg=C.GOLD_SEL, 
				ts=isSmall and 30 or 26, 
				font=F.NUM, 
				parent=line
			})
			
			-- 텍스트가 잘리지 않도록 설정
			btn.TextScaled = false
			btn.TextWrapped = false
	
			btn.MouseButton1Click:Connect(function() UIManager.addPendingStat(s.id) end)
		else
			-- 강화 불가 스탯은 값 라벨을 오른쪽 끝으로 정렬
			val.Position = UDim2.new(1, -10, 0, 0)
		end
		
		EquipmentUI.Refs.StatLines[s.id] = {val=val, btn=btn}
	end
	
	-- Action Frame (Apply/Cancel) 가변 비율 조정
	local actionFrame = Utils.mkFrame({size=UDim2.new(1,-20,0.15,0), pos=UDim2.new(0,10,1,-5), anchor=Vector2.new(0,1), bgT=1, vis=false, parent=statArea})
	EquipmentUI.Refs.ActionFrame = actionFrame
	local aList = Instance.new("UIListLayout"); aList.FillDirection=Enum.FillDirection.Horizontal; aList.Padding=UDim.new(0.05,0); aList.HorizontalAlignment=Enum.HorizontalAlignment.Center; aList.VerticalAlignment=Enum.VerticalAlignment.Center; aList.Parent=actionFrame

	Utils.mkBtn({text=UILocalizer.Localize("적용"), size=UDim2.new(0.45,0,0.8,0), bg=C.GREEN, font=F.TITLE, color=C.BG_PANEL, fn=function() UIManager.confirmPendingStats() end, parent=actionFrame})
	Utils.mkBtn({text=UILocalizer.Localize("초기화"), size=UDim2.new(0.45,0,0.8,0), bg=C.BTN, font=F.TITLE, fn=function() UIManager.cancelPendingStats() end, parent=actionFrame})
	
	-- [New] Tooltip Frame (Initially Hidden)
	local TT_W = isSmall and 300 or 320
	EquipmentUI.Refs.Tooltip = Utils.mkFrame({
		name = "Tooltip",
		size = UDim2.new(0, TT_W, 0, 0),
		bg = Color3.fromRGB(12, 15, 25), -- [MODIFIED] Deep Navy
		bgT = 0.05,
		r = 8, stroke = 1.8, strokeC = C.BORDER,
		vis = false,
		parent = parent
	})
	EquipmentUI.Refs.Tooltip.ZIndex = 100
	EquipmentUI.Refs.Tooltip.AutomaticSize = Enum.AutomaticSize.Y
	
	local tt = EquipmentUI.Refs.Tooltip
	Utils.AddShadow(tt)

	-- Header Line (Rarity Line)
	local rLine = Utils.mkFrame({
		name = "RarityLine",
		size = UDim2.new(1, 0, 0, 4),
		pos = UDim2.new(0, 0, 0, 0),
		bg = C.GOLD,
		parent = tt
	})
	Utils.AddCorner(rLine, 4)
	EquipmentUI.Refs.TooltipRarityLine = rLine

	-- 내부 레이아웃 컨테이너
	local ttContent = Instance.new("Frame")
	ttContent.Name = "Content"
	ttContent.Size = UDim2.new(1, -20, 0, 0)
	ttContent.Position = UDim2.new(0, 10, 0, 12)
	ttContent.BackgroundTransparency = 1
	ttContent.AutomaticSize = Enum.AutomaticSize.Y
	ttContent.ZIndex = 101
	ttContent.Parent = tt
	
	local ttLayout = Instance.new("UIListLayout")
	ttLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ttLayout.Padding = UDim.new(0, 6)
	ttLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ttLayout.Parent = ttContent
	
	local ttPad = Instance.new("UIPadding")
	ttPad.PaddingBottom = UDim.new(0, 15)
	ttPad.Parent = ttContent

	EquipmentUI.Refs.TooltipContent = ttContent
	EquipmentUI.Refs.TooltipLayout = ttLayout

	if tooltipMoveConn then
		tooltipMoveConn:Disconnect()
		tooltipMoveConn = nil
	end
	local isMobileUser = isMobile
	tooltipMoveConn = game:GetService("RunService").RenderStepped:Connect(function()
		local tt = EquipmentUI.Refs.Tooltip
		if tt and tt.Visible then
			-- 모바일일 경우 중앙 배치, PC일 경우 마우스 추적
			if isMobileUser then
				tt.AnchorPoint = Vector2.new(0.5, 0.5)
				tt.Position = UDim2.new(0.5, 0, 0.5, 0)
			else
				tt.AnchorPoint = Vector2.new(0, 0)
				local mousePos = game:GetService("UserInputService"):GetMouseLocation()
				local ttWidth = tt.AbsoluteSize.X
				local ttHeight = tt.AbsoluteSize.Y
				
				local xPos = mousePos.X + 20
				local yPos = mousePos.Y - ttHeight - 20
				
				-- 화면 상단/우측 경계 체크
				if yPos < 10 then yPos = mousePos.Y + 20 end
				local screenWidth = game.Workspace.CurrentCamera.ViewportSize.X
				if xPos + ttWidth > screenWidth - 10 then xPos = mousePos.X - ttWidth - 20 end
				
				EquipmentUI.Refs.Tooltip.Position = UDim2.new(0, xPos, 0, yPos)
			end
		end
	end)
end

function EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
	local refs = EquipmentUI.Refs
	if not refs.Frame or not refs.Frame.Visible then return end
	
	-- 장비 아이콘 업데이트 및 호버 이벤트
	if equipmentData then
		local ArmorSetData = require(ReplicatedStorage:WaitForChild("Data").ArmorSetData)
		local DataHelper = require(ReplicatedStorage:WaitForChild("Shared").Util.DataHelper)
		
		-- 현재 장착 중인 아이템 ID 목록 (세트효과 판정용)
		local equippedItemIds = {}
		for _, eqItem in pairs(equipmentData) do
			if eqItem and eqItem.itemId then
				equippedItemIds[eqItem.itemId] = true
			end
		end
		
		for name, slot in pairs(refs.Slots) do
			if slot._hoverConnEnter then
				slot._hoverConnEnter:Disconnect()
				slot._hoverConnEnter = nil
			end
			if slot._hoverConnLeave then
				slot._hoverConnLeave:Disconnect()
				slot._hoverConnLeave = nil
			end

			if slot._hoverConnLeave2 then
				slot._hoverConnLeave2:Disconnect()
				slot._hoverConnLeave2 = nil
			end

			local item = equipmentData[name]
			if item then
				slot.icon.Image = getItemIcon(item.itemId)
				slot.icon.Visible = true
				
				-- Enhancement level text indicator on the slot itself
				local levelText = slot.frame:FindFirstChild("EnhanceLevelText")
				local enhanceLevel = item.attributes and item.attributes.enhanceLevel or 0
				if enhanceLevel > 0 then
					if not levelText then
						levelText = Utils.mkLabel({
							name = "EnhanceLevelText",
							text = "+" .. enhanceLevel,
							size = UDim2.new(0, 30, 0, 20),
							pos = UDim2.new(1, -2, 1, -2),
							anchor = Vector2.new(1, 1),
							ts = 14,
							font = F.TITLE,
							color = Color3.fromRGB(255, 215, 0), -- Bright Gold
							parent = slot.frame
						})
						levelText.ZIndex = slot.icon.ZIndex + 1
					else
						levelText.Text = "+" .. enhanceLevel
						levelText.Visible = true
					end
				else
					if levelText then levelText.Visible = false end
				end
				
				local itemData = DataHelper.GetData("ItemData", item.itemId) or { id = item.itemId, name = item.itemId, type = "UNKNOWN", rarity = "COMMON" }
				
				-- [MODIFIED] DEACTIVATED: Durability concept disabled per design requirements
				if false and item.durability and itemData and itemData.durability then
					local ratio = math.clamp(item.durability / itemData.durability, 0, 1)
					slot.durBg.Visible = true
					slot.durFill.Size = UDim2.new(ratio, 0, 1, 0)
					if ratio > 0.5 then slot.durFill.BackgroundColor3 = Color3.fromRGB(120, 200, 80)
					elseif ratio > 0.2 then slot.durFill.BackgroundColor3 = Color3.fromRGB(230, 180, 60)
					else slot.durFill.BackgroundColor3 = Color3.fromRGB(200, 70, 50) end
				else
					if slot.durBg then slot.durBg.Visible = false end
				end
				
				-- 툴팁 이벤트 로직을 함수화
				local function showTooltip()
					local ttRef = EquipmentUI.Refs.Tooltip
					local ttCont = EquipmentUI.Refs.TooltipContent
					if not ttRef or not ttCont then return end
					
					-- 기존 행 정리
					for _, child in ipairs(ttCont:GetChildren()) do
						if child:IsA("GuiObject") then child:Destroy() end
					end
					
					local order = 0
					local TT_TS = 16 -- 툴팁 텍스트 사이즈
					
					-- Rarity Color
					local rarityColor = C.GOLD
					if itemData.rarity == "RARE" then rarityColor = Color3.fromRGB(80, 180, 255)
					elseif itemData.rarity == "EPIC" then rarityColor = Color3.fromRGB(180, 100, 255)
					elseif itemData.rarity == "LEGENDARY" then rarityColor = Color3.fromRGB(255, 180, 50)
					end
					
					if EquipmentUI.Refs.TooltipRarityLine then EquipmentUI.Refs.TooltipRarityLine.BackgroundColor3 = rarityColor end
					ttRef.UIStroke.Color = rarityColor

					-- 헬퍼: 제목 라벨
					local function addName(text, color)
						order = order + 1
						local lbl = Instance.new("TextLabel")
						lbl.Name = "Name_" .. order
						lbl.Size = UDim2.new(1, 0, 0, 32)
						lbl.BackgroundTransparency = 1
						lbl.RichText = true
						lbl.Text = text
						lbl.TextColor3 = color
						lbl.TextSize = 20
						lbl.Font = F.TITLE
						lbl.TextXAlignment = Enum.TextXAlignment.Center
						lbl.LayoutOrder = order
						lbl.Parent = ttCont
					end
					
					-- 헬퍼: 카테고리 헤더
					local function addCategory(label, color)
						order = order + 1
						local row = Instance.new("TextLabel")
						row.Name = "Cat_" .. order
						row.Size = UDim2.new(1, 0, 0, 24)
						row.BackgroundTransparency = 1
						row.RichText = true
						row.Text = "▣ " .. label
						row.TextColor3 = Color3.fromHex(color)
						row.TextSize = 15
						row.Font = F.TITLE
						row.TextXAlignment = Enum.TextXAlignment.Left
						row.LayoutOrder = order
						row.Parent = ttCont
					end

					-- 헬퍼: 스탯/효과 행
					local function addRow(label, value, colorHex, isBullet)
						order = order + 1
						local row = Instance.new("Frame")
						row.Name = "Row_" .. order
						row.Size = UDim2.new(1, 0, 0, TT_TS + 4)
						row.BackgroundTransparency = 1
						row.LayoutOrder = order
						row.Parent = ttCont
						
						local nameL = Instance.new("TextLabel")
						nameL.Size = UDim2.new(0.6, 0, 1, 0)
						nameL.BackgroundTransparency = 1
						nameL.Text = (isBullet and "-   " or "") .. label
						nameL.TextColor3 = isBullet and C.WHITE or Color3.fromHex("#AAAAAA")
						nameL.TextSize = TT_TS
						nameL.Font = F.NORMAL
						nameL.TextXAlignment = Enum.TextXAlignment.Left
						nameL.Parent = row
						
						local valL = Instance.new("TextLabel")
						valL.Size = UDim2.new(0.4, 0, 1, 0)
						valL.Position = UDim2.new(0.6, 0, 0, 0)
						valL.BackgroundTransparency = 1
						valL.RichText = true
						valL.Text = value or ""
						valL.TextColor3 = colorHex and Color3.fromHex(colorHex) or C.WHITE
						valL.TextSize = TT_TS
						valL.Font = F.TITLE
						valL.TextXAlignment = Enum.TextXAlignment.Right
						valL.Parent = row
					end
					
					-- 헬퍼: 구분선
					local function addSep()
						order = order + 1
						local sep = Instance.new("Frame")
						sep.Name = "Sep_" .. order
						sep.Size = UDim2.new(1, 0, 0, 1)
						sep.BackgroundColor3 = C.BORDER
						sep.BackgroundTransparency = 0.4
						sep.BorderSizePixel = 0
						sep.LayoutOrder = order
						sep.Parent = ttCont
					end
					
					local iType = itemData.type
					
					-- 아이템 이름
					local baseName = UILocalizer.LocalizeDataText("ItemData", tostring(itemData.id or item.itemId), "name", itemData.name or item.itemId)
					local enhanceLevel = item.attributes and item.attributes.enhanceLevel or 0
					local displayName = baseName .. (enhanceLevel > 0 and (" +" .. enhanceLevel) or "")
					addName(displayName, rarityColor)
					addSep()
					
					-- 아이콘 (미리보기) - 작게 표시
					order = order + 1
					local img = Instance.new("ImageLabel")
					img.Size = UDim2.new(0, 64, 0, 64); img.AnchorPoint = Vector2.new(0.5, 0.5); img.Position = UDim2.new(0.5, 0, 0, 32)
					img.BackgroundTransparency = 1
					img.Image = getItemIcon(item.itemId)
					img.LayoutOrder = order
					img.Parent = ttCont

					addSep()
					
					-- =====================
					-- 메인 스탯
					-- =====================
					if iType == "WEAPON" or iType == "TOOL" then
						local bonusDmg, bonusCrit, bonusCritDmg, bonusDur = 0, 0, 0, 0
						if item.attributes then
							for attrId, level in pairs(item.attributes) do
								local fx = MaterialAttributeData.getEffectValues(attrId, level)
								if fx then
									bonusDmg = bonusDmg + (fx.damageMult or 0)
									bonusCrit = bonusCrit + (fx.critChance or 0)
									bonusCritDmg = bonusCritDmg + (fx.critDamageMult or 0)
									bonusDur = bonusDur + (fx.durabilityMult or 0)
								end
							end
						end
						
						local baseDmg = itemData.damage or 0
						local enhanceLevel = item.attributes and item.attributes.enhanceLevel or 0
						local enhanceDamage = item.attributes and item.attributes.enhanceDamage or 0
						
						local finalDmg = math.floor(baseDmg * (1 + bonusDmg) + 0.5)
						if enhanceDamage > 0 then
							finalDmg = finalDmg + enhanceDamage
						elseif enhanceLevel > 0 then
							finalDmg = finalDmg + math.floor(baseDmg * (enhanceLevel * 0.15) + 0.5)
						end
						local extraDmg = finalDmg - baseDmg
						
						local finalCrit = math.floor(bonusCrit * 100 + 0.5)
						
						local dmgValStr
						if extraDmg > 0 then
							dmgValStr = finalDmg .. " (" .. baseDmg .. "+" .. extraDmg .. ")"
						elseif extraDmg < 0 then
							dmgValStr = finalDmg .. " (" .. baseDmg .. extraDmg .. ")"
						else
							dmgValStr = tostring(baseDmg)
						end
						addRow("공격력", dmgValStr)
						
						local critValStr
						if finalCrit ~= 0 then
							critValStr = "0% (+" .. finalCrit .. "%)"
						else
							critValStr = "0%"
						end
						addRow("치명타 확률", critValStr)
						
					elseif iType == "ARMOR" then
						local bonusDef, bonusHp, bonusDur = 0, 0, 0
						if item.attributes then
							for attrId, level in pairs(item.attributes) do
								local fx = MaterialAttributeData.getEffectValues(attrId, level)
								if fx then
									bonusDef = bonusDef + (fx.defenseMult or 0)
									bonusHp = bonusHp + (fx.maxHealthMult or 0)
									bonusDur = bonusDur + (fx.durabilityMult or 0)
								end
							end
						end
						
						local baseDef = itemData.defense or 0
						local finalDef = math.floor(baseDef * (1 + bonusDef) + 0.5)
						local extraDef = finalDef - baseDef
						local finalHp = math.floor(bonusHp * 100 + 0.5)
						
						local defColor = bonusDef > 0 and "#8CDC64" or "#FFFFFF"
						local hpColor = bonusHp > 0 and "#8CDC64" or "#FFFFFF"
						
						-- 1) 방어력 (기본 스탯이 있거나 attributes가 있을 경우에만 표기)
						if baseDef > 0 or extraDef ~= 0 then
							local defValStr
							if extraDef ~= 0 then
								defValStr = finalDef .. " <font color=\"#FFFFFF\">(" .. baseDef .. "</font><font color=\"" .. defColor .. "\">+" .. extraDef .. "</font><font color=\"#FFFFFF\>)</font>"
							else
								defValStr = tostring(baseDef)
							end
							addRow("방어력", defValStr)
						end
						
						-- 2) 추가 체력 (아이템 고유 체력 스탯이 있거나 attributes 추가 체력이 있을 때 표기)
						local baseHealth = itemData.maxHealth or 0
						if baseHealth > 0 or finalHp > 0 then
							local hpValueStr
							if finalHp > 0 then
								hpValueStr = "+" .. baseHealth .. " <font color=\"" .. hpColor .. "\">" .. string.format("(%+d%%)", finalHp) .. "</font>"
							else
								hpValueStr = "+" .. baseHealth
							end
							addRow("추가 체력", hpValueStr)
						end
						
						-- 3) 치명타 확률 (아이템 자체 고유 치명타 스탯이 있을 때 표기)
						local baseCrit = itemData.critChance or 0
						if baseCrit > 0 then
							addRow("치명타 확률", string.format("+%.0f%%", baseCrit * 100))
						end
					end
					
					-- =====================
					-- 아이템 효과 (버프/데버프)
					-- =====================
					if item.attributes and next(item.attributes) then
						addSep()
						
						local buffs, debuffs = {}, {}
						local isProduct = (iType == "TOOL" or iType == "WEAPON" or iType == "ARMOR")
						
						for attrId, level in pairs(item.attributes) do
							local attrInfo = MaterialAttributeData.getAttribute(attrId)
							if attrInfo then
								local displayName = isProduct and attrInfo.effect or attrInfo.name
								local txt = string.format("%s Lv.%d", displayName, level)
								if attrInfo.positive then table.insert(buffs, txt) else table.insert(debuffs, txt) end
							end
						end

						if #buffs > 0 then
							addCategory("버프", "#8CDC64")
							for _, b in ipairs(buffs) do addRow(b, nil, nil, true) end
						end
						if #debuffs > 0 then
							if #buffs > 0 then order = order + 1; local s = Instance.new("Frame"); s.Size=UDim2.new(1,0,0,4); s.BackgroundTransparency=1; s.LayoutOrder=order; s.Parent=ttCont end
							addCategory("데버프", "#E63232")
							for _, d in ipairs(debuffs) do addRow(d, nil, nil, true) end
						end
					end
					
					-- =====================
					-- 세트 효과 (생략 가능하면 간결하게)
					-- =====================
					if itemData.armorSet then
						local setData = ArmorSetData[itemData.armorSet]
						if setData then
							addSep()
							local equippedCount = 0
							for _, setItemId in ipairs(setData.items) do if equippedItemIds[setItemId] then equippedCount = equippedCount + 1 end end
							local setActive = (equippedCount >= #setData.items)
							
							order = order + 1
							local setL = Instance.new("TextLabel")
							setL.Size = UDim2.new(1, 0, 0, 24); setL.BackgroundTransparency = 1; setL.RichText = true
							setL.Text = string.format("<b>세트: %s</b> <font color='%s'>(%d/%d)</font>", setData.name, setActive and "#78C850" or "#888888", equippedCount, #setData.items)
							setL.TextColor3 = setActive and Color3.fromRGB(120, 200, 80) or Color3.fromHex("#888888")
							setL.TextSize = 15; setL.Font = F.TITLE; setL.TextXAlignment = Enum.TextXAlignment.Left; setL.LayoutOrder = order; setL.Parent = ttCont
							
							if setActive then
								order = order + 1
								local bonus = Instance.new("TextLabel")
								bonus.Size = UDim2.new(1, 0, 0, 0); bonus.AutomaticSize = Enum.AutomaticSize.Y; bonus.BackgroundTransparency = 1; bonus.Text = "★ " .. setData.bonusText
								bonus.TextColor3 = Color3.fromRGB(255, 220, 80); bonus.TextSize = 14; bonus.Font = F.NORMAL; bonus.TextWrapped = true; bonus.TextXAlignment = Enum.TextXAlignment.Left; bonus.LayoutOrder = order; bonus.Parent = ttCont
							end
						end
					end
					
					ttRef.Visible = true
				end
				
				slot._triggerTooltip = showTooltip
				-- 툴팁 이벤트 연결 (PC)
				slot._hoverConnEnter = slot.click.MouseEnter:Connect(showTooltip)
				
				local function hideTooltip()
					if EquipmentUI.Refs.Tooltip then EquipmentUI.Refs.Tooltip.Visible = false end
				end
				slot._hoverConnLeave = slot.click.MouseLeave:Connect(hideTooltip)
				-- 프레임 MouseLeave도 연결 (안전장치)
				slot._hoverConnLeave2 = slot.frame.MouseLeave:Connect(hideTooltip)
			else
				slot.icon.Image = ""
				slot.icon.Visible = false
				if slot.durBg then slot.durBg.Visible = false end
				local levelText = slot.frame:FindFirstChild("EnhanceLevelText")
				if levelText then levelText.Visible = false end
			end
		end
	end
	
	-- 스탯 업데이트
	if not cachedStats then return end
	local available = (cachedStats.statPointsAvailable or 0) - (totalPending or 0)
	refs.StatPoints.Text = UILocalizer.Localize("남은 강화 포인트: " .. available)
	
	local calc = cachedStats.calculated or {}
	local invested = cachedStats.statInvested or {}
	
	for statId, line in pairs(refs.StatLines) do
		local valText = ""
		local baseValue = 0
		if statId == Enums.StatId.MAX_HEALTH then baseValue = calc.maxHealth or 100; valText = string.format("%d HP", baseValue)
		elseif statId == Enums.StatId.MAX_STAMINA then baseValue = calc.maxStamina or 100; valText = string.format("%d STA", baseValue)
		elseif statId == Enums.StatId.INV_SLOTS then baseValue = calc.maxSlots or 60; valText = string.format("%d 칸", baseValue)
		elseif statId == Enums.StatId.ATTACK then
			local mult = calc.attackMult or 1.0
			local wData = equipmentData and equipmentData.HAND
			if wData then
				local DataHelper = require(ReplicatedStorage:WaitForChild("Shared").Util.DataHelper)
				local itemData = DataHelper.GetData("ItemData", wData.itemId)
				local baseDmg = itemData and itemData.damage or 0
				local enhanceLevel = wData.attributes and wData.attributes.enhanceLevel or 0
				local finalDmg = math.floor(baseDmg * (1 + enhanceLevel * 0.15) + 0.5)
				local charDmg = math.floor(finalDmg * mult + 0.5)
				valText = string.format("%.0f%% (%d DMG)", mult * 100, charDmg)
			else
				valText = string.format("%.0f%%", mult * 100)
			end
		elseif statId == Enums.StatId.DEFENSE then baseValue = calc.defense or 0; valText = string.format("%d", baseValue) end
		
		-- PendingStats: 저장된 UIManager 참조 사용
		local added = _UIManager and _UIManager.getPendingStatCount(statId) or 0
		if added > 0 then
			line.val.Text = string.format("%s <font color='#8CDC64'>+%d</font>", valText, added)
			line.val.RichText = true
		else
			line.val.Text = valText
			line.val.RichText = false
		end
		
		if line.btn then
			line.btn.Visible = true
			line.btn.BackgroundTransparency = (available > 0) and 0 or 0.6
			line.btn.TextTransparency = (available > 0) and 0 or 0.6
			line.btn.Active = (available > 0)
		end
	end
	
	refs.ActionFrame.Visible = (totalPending > 0)
end

function EquipmentUI.UpdateCharacterPreview(character)
	-- [제거됨] 유저 요청으로 장비창 내 캐릭터 미리보기 기능 완전 삭제
end

return EquipmentUI
