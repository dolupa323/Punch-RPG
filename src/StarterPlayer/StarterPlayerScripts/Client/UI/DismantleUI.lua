-- DismantleUI.lua
-- 무기 분해 전용 UI 모듈 (인벤토리 무기 자동 감지 + 50% 재료 반환 시각화)
-- [Durango Style Premium Recycler UI & Mobile Responsive Layout]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local DismantleController = require(Controllers:WaitForChild("DismantleController"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))

-- Navy + Black Theme Override (Convention match with InventoryUI/EnhanceUI)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Deep Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Pure Black
C.BG_SLOT = Color3.fromRGB(12, 12, 15)  -- Near Black
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Soft Light Blue
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN_DANGER = Color3.fromRGB(180, 60, 60) -- Rosewood Red

local F = Theme.Fonts
local DismantleUI = {}

DismantleUI.State = {
	selectedSlot = nil, -- 선택된 인벤토리 슬롯 인덱스
	isProcessing = false
}

DismantleUI.Refs = {}
local UI_MANAGER = nil

-- 아이템 아이콘 설정 헬퍼
local function setIconImage(uiObject, icon)
	if not icon or icon == "" then
		uiObject.Image = ""
		return
	end
	uiObject.Image = icon
end

-- 무기 분해 반환 재료 계산 공식 (서버 로직과 100% 동기화)
local function getEstimatedMaterials(itemId: string)
	local RecipeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("RecipeData"))
	local foundRecipe = nil
	
	for _, recipe in ipairs(RecipeData) do
		if recipe.category == "WEAPON" and recipe.outputs then
			for _, output in ipairs(recipe.outputs) do
				if output.itemId == itemId then
					foundRecipe = recipe
					break
				end
			end
		end
		if foundRecipe then break end
	end
	
	local materials = {}
	if foundRecipe and foundRecipe.inputs then
		for _, input in ipairs(foundRecipe.inputs) do
			table.insert(materials, {
				itemId = input.itemId,
				count = math.max(1, math.floor(input.count * 0.5))
			})
		end
	else
		table.insert(materials, {
			itemId = "SLIME_MUCUS",
			count = 3
		})
	end
	return materials
end

function DismantleUI.Init(parent, manager)
	UI_MANAGER = manager
	
	-- Standalone Window Frame (반응형 최적 가로 세로 배분)
	local window = Utils.mkWindow({
		name = "DismantleWindow",
		size = UDim2.new(0, 720, 0, 460),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.15, -- glassmorphism
		stroke = 2,
		strokeC = C.BORDER,
		r = 12,
		vis = false,
		parent = parent
	})
	
	-- 모바일 세로/가로 대응을 위한 종횡비 제약 추가
	local ratioConstraint = Instance.new("UIAspectRatioConstraint")
	ratioConstraint.AspectRatio = 1.56 -- 720 x 460
	ratioConstraint.AspectType = Enum.AspectType.ScaleWithParentSize
	ratioConstraint.Parent = window
	
	DismantleUI.Refs.Frame = window
	DismantleUI.Refs.Main = window
	
	-- Header Title
	DismantleUI.Refs.Title = Utils.mkLabel({
		text = UILocalizer.Localize("무기 분해소 (Dismantle Recycler)"),
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
			UI_MANAGER.closeDismantle()
		end,
		parent = window
	})
	
	-- Main Layout Frame (2분할 분할구조)
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(1, -40, 1, -70),
		pos = UDim2.new(0, 20, 0, 60),
		bgT = 1,
		parent = window
	})
	DismantleUI.Refs.Body = body
	
	-- [왼쪽 영역]: 무기 목록 (Grid ScrollList)
	local leftFrame = Utils.mkFrame({
		name = "LeftFrame",
		size = UDim2.new(0.55, -10, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = body
	})
	
	local leftTitle = Utils.mkLabel({
		text = UILocalizer.Localize("분해 가능한 무기 목록"),
		size = UDim2.new(1, -20, 0, 30),
		pos = UDim2.new(0, 10, 0, 5),
		font = F.TITLE,
		ts = 14,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = leftFrame
	})
	
	local weaponScroll = Instance.new("ScrollingFrame")
	weaponScroll.Name = "WeaponScroll"
	weaponScroll.Size = UDim2.new(1, -20, 1, -45)
	weaponScroll.Position = UDim2.new(0.5, 0, 1, -10)
	weaponScroll.AnchorPoint = Vector2.new(0.5, 1)
	weaponScroll.BackgroundTransparency = 1
	weaponScroll.BorderSizePixel = 0
	weaponScroll.ScrollBarThickness = 4
	weaponScroll.ScrollBarImageColor3 = C.BORDER_DIM
	weaponScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	weaponScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	weaponScroll.Parent = leftFrame
	DismantleUI.Refs.WeaponScroll = weaponScroll
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 72, 0, 72)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = weaponScroll
	
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 4)
	gridPad.PaddingLeft = UDim.new(0, 4)
	gridPad.Parent = weaponScroll
	
	-- [오른쪽 영역]: 분해 정보 세부 카드
	local rightFrame = Utils.mkFrame({
		name = "RightFrame",
		size = UDim2.new(0.45, -10, 1, 0),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 8,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = body
	})
	DismantleUI.Refs.RightFrame = rightFrame
	
	-- 상세 정보 표기용 뷰 포트
	local detailView = Utils.mkFrame({
		name = "DetailView",
		size = UDim2.new(1, -20, 1, -20),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgT = 1,
		parent = rightFrame
	})
	DismantleUI.Refs.DetailView = detailView
	
	-- Failsafe 빈 패널 텍스트
	local emptyLbl = Utils.mkLabel({
		text = UILocalizer.Localize("분해할 무기를 목록에서 선택하세요."),
		size = UDim2.new(1, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0),
		font = F.NORMAL,
		ts = 15,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Center,
		ay = Enum.TextYAlignment.Center,
		parent = detailView
	})
	DismantleUI.Refs.EmptyLbl = emptyLbl
	
	-- 무기 정보 표출 프레임
	local infoFrame = Utils.mkFrame({
		name = "InfoFrame",
		size = UDim2.new(1, 0, 1, 0),
		bgT = 1,
		vis = false,
		parent = detailView
	})
	DismantleUI.Refs.InfoFrame = infoFrame
	
	-- 선택 무기 아이콘 슬롯
	local selectedSlotBg = Utils.mkFrame({
		name = "SelectedSlotBg",
		size = UDim2.new(0, 68, 0, 68),
		pos = UDim2.new(0, 0, 0, 5),
		bg = C.BG_SLOT,
		r = 8,
		stroke = 1.5,
		strokeC = C.BORDER,
		parent = infoFrame
	})
	
	local selectedIcon = Instance.new("ImageLabel")
	selectedIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
	selectedIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	selectedIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	selectedIcon.BackgroundTransparency = 1
	selectedIcon.Parent = selectedSlotBg
	DismantleUI.Refs.SelectedIcon = selectedIcon
	
	-- 무기 강화 수치 및 품질 라벨
	local selectedEnhanceLbl = Utils.mkLabel({
		text = "",
		size = UDim2.new(0, 30, 0, 20),
		pos = UDim2.new(1, -3, 1, -3),
		anchor = Vector2.new(1, 1),
		font = F.TITLE,
		ts = 13,
		color = Color3.fromRGB(255, 240, 150),
		ax = Enum.TextXAlignment.Right,
		parent = selectedSlotBg
	})
	DismantleUI.Refs.SelectedEnhanceLbl = selectedEnhanceLbl
	
	-- 무기 이름 및 레벨 조건
	local selectedName = Utils.mkLabel({
		text = "무기 이름",
		size = UDim2.new(1, -85, 0, 28),
		pos = UDim2.new(0, 80, 0, 5),
		font = F.TITLE,
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = infoFrame
	})
	DismantleUI.Refs.SelectedName = selectedName
	
	local selectedDesc = Utils.mkLabel({
		text = "설명 정보",
		size = UDim2.new(1, -85, 0, 35),
		pos = UDim2.new(0, 80, 0, 33),
		font = F.NORMAL,
		ts = 12,
		color = C.GRAY,
		ax = Enum.TextXAlignment.Left,
		wrap = true,
		parent = infoFrame
	})
	DismantleUI.Refs.SelectedDesc = selectedDesc
	
	-- 반환 재료 미리보기 타이틀
	local matTitle = Utils.mkLabel({
		text = UILocalizer.Localize("🛠️ 분해 시 100% 반환 재료 (50% 비율)"),
		size = UDim2.new(1, 0, 0, 25),
		pos = UDim2.new(0, 0, 0, 90),
		font = F.TITLE,
		ts = 13,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = infoFrame
	})
	
	-- 반환 재료 스크롤/목록 프레임
	local matList = Utils.mkFrame({
		name = "MatList",
		size = UDim2.new(1, 0, 0, 140),
		pos = UDim2.new(0, 0, 0, 120),
		bg = C.BG_SLOT,
		r = 6,
		stroke = 1,
		strokeC = C.BORDER_DIM,
		parent = infoFrame
	})
	DismantleUI.Refs.MatList = matList
	
	local matListLayout = Instance.new("UIListLayout")
	matListLayout.FillDirection = Enum.FillDirection.Vertical
	matListLayout.Padding = UDim.new(0, 6)
	matListLayout.Parent = matList
	
	local matListPad = Instance.new("UIPadding")
	matListPad.PaddingTop = UDim.new(0, 8)
	matListPad.PaddingBottom = UDim.new(0, 8)
	matListPad.PaddingLeft = UDim.new(0, 10)
	matListPad.PaddingRight = UDim.new(0, 10)
	matListPad.Parent = matList
	
	-- 분해 실행 액션 버튼 (Danger Rosewood 테마 적용)
	local actionBtn = Utils.mkBtn({
		text = UILocalizer.Localize("무기 분해 실행"),
		size = UDim2.new(1, 0, 0, 44),
		pos = UDim2.new(0.5, 0, 1, 0),
		anchor = Vector2.new(0.5, 1),
		bg = C.BTN_DANGER,
		color = C.WHITE,
		ts = 16,
		font = F.TITLE,
		r = 8,
		stroke = 1.5,
		strokeC = Color3.fromRGB(240, 100, 100),
		fn = function()
			DismantleUI.executeDismantle()
		end,
		parent = infoFrame
	})
	DismantleUI.Refs.ActionBtn = actionBtn

	-- 인벤토리 실시간 동적 갱신 콜백 등록 (분해 즉시 목록 자동 갱신!)
	InventoryController.onChanged(function()
		if window.Visible then
			DismantleUI.Refresh()
		end
	end)
end

function DismantleUI.SetVisible(visible: boolean)
	local window = DismantleUI.Refs.Frame
	if not window then return end
	
	if visible then
		window.Visible = true
		-- 마운트 시 등장 팝 애니메이션
		window.Size = UDim2.new(0, 50, 0, 30)
		window.BackgroundTransparency = 1
		TweenService:Create(window, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 720, 0, 460),
			BackgroundTransparency = 0.15
		}):Play()
	else
		window.Visible = false
	end
end

-- 인벤토리 리스트 및 미리보기 화면 실시간 동적 새로고침
function DismantleUI.Refresh()
	local scroll = DismantleUI.Refs.WeaponScroll
	if not scroll then return end
	
	-- 1. 기존 슬롯 오브젝트 일제 소거
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child.Name:sub(1, 5) == "Slot_" then
			child:Destroy()
		end
	end
	
	-- 2. 인벤토리 목록 획득 및 무기 필터링
	local items = InventoryController.getItems()
	local weaponsCount = 0
	
	for slotIdx, slotData in pairs(items) do
		if slotData and slotData.itemId then
			local itemInfo = DataHelper.GetData("ItemData", slotData.itemId)
			
			-- 오직 일반 무기(type == "WEAPON")만 분해 목록에 추가
			if itemInfo and itemInfo.type == "WEAPON" then
				weaponsCount = weaponsCount + 1
				
				-- 슬롯 버튼 컨테이너 생성
				local slotFrame = Utils.mkFrame({
					name = "Slot_" .. slotIdx,
					size = UDim2.new(0, 72, 0, 72),
					bg = C.BG_SLOT,
					r = 8,
					stroke = 1,
					strokeC = (DismantleUI.State.selectedSlot == slotIdx) and C.GOLD_SEL or C.BORDER_DIM,
					parent = scroll
				})
				
				-- 아이템 이미지 아이콘
				local icon = Instance.new("ImageLabel")
				icon.Size = UDim2.new(0.85, 0, 0.85, 0)
				icon.Position = UDim2.new(0.5, 0, 0.5, 0)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.BackgroundTransparency = 1
				setIconImage(icon, UI_MANAGER.getItemIcon(slotData.itemId))
				icon.Parent = slotFrame
				
				-- 강화 수치 라벨 (+)
				if slotData.attributes and slotData.attributes.enhanceLevel and slotData.attributes.enhanceLevel > 0 then
					Utils.mkLabel({
						text = "+" .. slotData.attributes.enhanceLevel,
						size = UDim2.new(0, 30, 0, 18),
						pos = UDim2.new(1, -2, 1, -2),
						anchor = Vector2.new(1, 1),
						font = F.TITLE,
						ts = 12,
						color = Color3.fromRGB(255, 240, 150),
						ax = Enum.TextXAlignment.Right,
						parent = slotFrame
					})
				end
				
				-- 클릭 인터랙션
				local clickBtn = Instance.new("TextButton")
				clickBtn.Size = UDim2.new(1, 0, 1, 0)
				clickBtn.BackgroundTransparency = 1
				clickBtn.Text = ""
				clickBtn.Parent = slotFrame
				
				-- 터치 애니메이션 바운스 리스너 연동
				clickBtn.MouseButton1Down:Connect(function()
					local scale = slotFrame:FindFirstChild("UIScale") or Instance.new("UIScale", slotFrame)
					TweenService:Create(scale, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.92}):Play()
				end)
				
				clickBtn.MouseButton1Up:Connect(function()
					local scale = slotFrame:FindFirstChild("UIScale")
					if scale then
						TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.0}):Play()
					end
				end)
				
				clickBtn.MouseButton1Click:Connect(function()
					DismantleUI.selectWeaponSlot(slotIdx)
				end)
			end
		end
	end
	
	-- 분해할 수 있는 무기가 전혀 없을 경우 처리
	if weaponsCount == 0 then
		-- 만약 선택된 무기가 사라졌다면 선택 정보 비워줌
		DismantleUI.selectWeaponSlot(nil)
	else
		-- 이전 선택 무기가 유효한지 재확인하여 연동 유지
		if DismantleUI.State.selectedSlot and not items[DismantleUI.State.selectedSlot] then
			DismantleUI.selectWeaponSlot(nil)
		else
			DismantleUI.selectWeaponSlot(DismantleUI.State.selectedSlot)
		end
	end
end

-- 특정 슬롯의 무기 카드 선택
function DismantleUI.selectWeaponSlot(slotIdx: number?)
	DismantleUI.State.selectedSlot = slotIdx
	
	-- 1. 리스트 아웃라인 하이라이트 갱신
	local scroll = DismantleUI.Refs.WeaponScroll
	if scroll then
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") and child.Name:sub(1, 5) == "Slot_" then
				local sIdx = tonumber(child.Name:sub(6))
				local stroke = child:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = (sIdx == slotIdx) and Color3.fromRGB(255, 210, 100) or C.BORDER_DIM
					stroke.Thickness = (sIdx == slotIdx) and 2 or 1
				end
			end
		end
	end
	
	local emptyLbl = DismantleUI.Refs.EmptyLbl
	local infoFrame = DismantleUI.Refs.InfoFrame
	
	if not slotIdx then
		-- 아무것도 선택하지 않았을 때 폴백 패널 기동
		if emptyLbl then emptyLbl.Visible = true end
		if infoFrame then infoFrame.Visible = false end
		return
	end
	
	if emptyLbl then emptyLbl.Visible = false end
	if infoFrame then infoFrame.Visible = true end
	
	-- 2. 무기 정보 추출 및 시각화 적용
	local itemData = InventoryController.getItems()[slotIdx]
	if not itemData then return end
	
	local itemInfo = DataHelper.GetData("ItemData", itemData.itemId)
	
	-- 메인 무기 정보 표출
	local selectedIcon = DismantleUI.Refs.SelectedIcon
	if selectedIcon then setIconImage(selectedIcon, UI_MANAGER.getItemIcon(itemData.itemId)) end
	
	local selectedEnhanceLbl = DismantleUI.Refs.SelectedEnhanceLbl
	if selectedEnhanceLbl then
		local enhance = itemData.attributes and itemData.attributes.enhanceLevel or 0
		selectedEnhanceLbl.Text = enhance > 0 and ("+" .. enhance) or ""
	end
	
	local selectedName = DismantleUI.Refs.SelectedName
	if selectedName then
		local rarityName = itemInfo and itemInfo.rarity or "COMMON"
		selectedName.Text = itemInfo and itemInfo.name or itemData.itemId
		
		-- 레어리티 컬러 매칭
		local rarityColors = {
			COMMON = Color3.fromRGB(240, 240, 240),
			UNCOMMON = Color3.fromRGB(100, 220, 120),
			RARE = Color3.fromRGB(100, 180, 255),
			EPIC = Color3.fromRGB(180, 100, 255),
			UNIQUE = Color3.fromRGB(255, 120, 50),
			LEGENDARY = Color3.fromRGB(255, 215, 0)
		}
		selectedName.TextColor3 = rarityColors[rarityName] or C.WHITE
	end
	
	local selectedDesc = DismantleUI.Refs.SelectedDesc
	if selectedDesc then
		selectedDesc.Text = UILocalizer.Localize(itemInfo and itemInfo.description or "아이템 설명 정보가 존재하지 않습니다.")
	end
	
	-- 3. [반환 재료 예측 리스트 채우기]
	local matList = DismantleUI.Refs.MatList
	if matList then
		-- 기존 노드 완벽 청소
		for _, child in ipairs(matList:GetChildren()) do
			if child:IsA("Frame") and child.Name:sub(1, 4) == "Mat_" then
				child:Destroy()
			end
		end
		
		-- 예상 반환 재료 계산
		local materials = getEstimatedMaterials(itemData.itemId)
		for idx, mat in ipairs(materials) do
			local matData = DataHelper.GetData("ItemData", mat.itemId)
			
			local row = Utils.mkFrame({
				name = "Mat_" .. idx,
				size = UDim2.new(1, 0, 0, 36),
				bgT = 1,
				parent = matList
			})
			
			-- 재료 아이콘
			local matIconSlot = Utils.mkFrame({
				name = "IconBg",
				size = UDim2.new(0, 28, 0, 28),
				pos = UDim2.new(0, 0, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				bg = C.BG_PANEL,
				r = 4,
				stroke = 1,
				strokeC = C.BORDER_DIM,
				parent = row
			})
			
			local matIcon = Instance.new("ImageLabel")
			matIcon.Size = UDim2.new(0.85, 0, 0.85, 0)
			matIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
			matIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			matIcon.BackgroundTransparency = 1
			setIconImage(matIcon, UI_MANAGER.getItemIcon(mat.itemId))
			matIcon.Parent = matIconSlot
			
			-- 재료 이름
			local matName = matData and matData.name or mat.itemId
			local matNameLbl = Utils.mkLabel({
				text = UILocalizer.LocalizeDataText("ItemData", mat.itemId, "name", matName),
				size = UDim2.new(0.6, 0, 1, 0),
				pos = UDim2.new(0, 38, 0, 0),
				font = F.NORMAL,
				ts = 13,
				color = C.WHITE,
				ax = Enum.TextXAlignment.Left,
				parent = row
			})
			
			-- 반환 수량
			local matCountLbl = Utils.mkLabel({
				text = "x" .. mat.count,
				size = UDim2.new(0.2, 0, 1, 0),
				pos = UDim2.new(1, 0, 0, 0),
				anchor = Vector2.new(1, 0),
				font = F.TITLE,
				ts = 14,
				color = Color3.fromRGB(120, 220, 100), -- Green
				ax = Enum.TextXAlignment.Right,
				parent = row
			})
		end
	end
end

-- 분해 트랜잭션 실행 함수
function DismantleUI.executeDismantle()
	if DismantleUI.State.isProcessing or not DismantleUI.State.selectedSlot then return end
	
	local slot = DismantleUI.State.selectedSlot
	local items = InventoryController.getItems()
	local weaponData = items[slot]
	if not weaponData then return end
	
	local weaponInfo = DataHelper.GetData("ItemData", weaponData.itemId)
	local weaponName = weaponInfo and weaponInfo.name or weaponData.itemId
	
	-- 이중 안전을 위한 전용 무기 분해 확인 모달 가동 (골드가 아닌 분해 위험 테마)
	local localizedMsgFormat = UILocalizer.Localize("정말로 <font color='#FF4040'>%s</font> 무기를 분해하시겠습니까?<br/>분해한 장비는 복구할 수 없으며 원본 재료의 50%%를 돌려받습니다.")
	UI_MANAGER.showDismantleConfirm({
		message = string.format(localizedMsgFormat, weaponName),
		onConfirm = function()
			DismantleUI.State.isProcessing = true
			DismantleUI.Refs.ActionBtn.Text = UILocalizer.Localize("분해 가동 중...")
			DismantleUI.Refs.ActionBtn.Active = false
			
			DismantleController.requestDismantle(slot, function(success, errorCode, data)
				DismantleUI.State.isProcessing = false
				if DismantleUI.Refs.ActionBtn then
					DismantleUI.Refs.ActionBtn.Text = UILocalizer.Localize("무기 분해 실행")
					DismantleUI.Refs.ActionBtn.Active = true
				end
				
				if success then
					-- 카메라 흔들기 피드백
					pcall(function()
						local cam = workspace.CurrentCamera
						if cam then
							task.spawn(function()
								local originalCF = cam.CFrame
								for i = 1, 6 do
									local offset = Vector3.new((math.random() - 0.5) * 0.4, (math.random() - 0.5) * 0.4, 0)
									cam.CFrame = originalCF * CFrame.new(offset)
									task.wait(0.02)
								end
								cam.CFrame = originalCF
							end)
						end
					end)
					
					-- 분해 성공 사운드 재생
					pcall(function()
						local sfx = Instance.new("Sound")
						sfx.SoundId = "rbxassetid://9063990812" -- Premium Tech Success sound
						sfx.Volume = 0.4
						sfx.Parent = game:GetService("SoundService")
						sfx:Play()
						game:GetService("Debris"):AddItem(sfx, 3)
					end)
					
					-- 목록 및 카드 갱신
					DismantleUI.selectWeaponSlot(nil)
					DismantleUI.Refresh()
				else
					-- 실패 팝업 처리
					local errMsg = errorCode or "UNKNOWN_ERROR"
					if errMsg == "INV_FULL" then
						errMsg = UILocalizer.Localize("가방이 꽉 차서 재료를 반환받을 공간이 없습니다.")
					end
					UI_MANAGER.notify(errMsg, Color3.fromRGB(255, 80, 80))
				end
			end)
		end
	})
end

return DismantleUI
