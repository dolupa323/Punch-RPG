-- CollectionUI.lua
-- 생존 도감 (일반 동물 표본실 디자인 레이아웃 컨벤션)
-- 탭 메뉴, 스크롤링 프레임, 상세정보, 업그레이드 표시

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local WindowManager = require(script.Parent.Parent.Utils.WindowManager)
local DataHelper = require(game:GetService("ReplicatedStorage").Shared.Util.DataHelper)
local CollectionController = require(script.Parent.Parent.Controllers.CollectionController)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local CollectionUI = {}
CollectionUI.Refs = {}
local isUIInitialized = false
local UIManager = nil

local CATEGORY_TABS = {
	{ label = "전체", key = "ALL" },
	{ label = "초원", key = "GRASSLAND" },
	{ label = "열대", key = "TROPICAL" },
	{ label = "사막", key = "DESERT" },
	{ label = "툰드라", key = "TUNDRA" }
}

-- 현재 운영 기준: 초원섬 도감은 3종 중심으로 노출
local REGION_MAP = {
	COMPY = "GRASSLAND",
	DODO = "GRASSLAND",
	BABY_TRICERATOPS = "GRASSLAND",
	PARASAUR = "TROPICAL",
	TRICERATOPS = "TROPICAL",
	STEGOSAURUS = "TROPICAL",
	ANKYLOSAURUS = "DESERT",
	RAPTOR = "DESERT",
	TREX = "TUNDRA"
}

local activeTabKey = "ALL"
local selectedCreatureId = nil

--========================================
-- Helpers
--========================================

local function getCreatureIcon(cid)
	-- 1. CreatureData 아이콘 ID 확인 (DataHelper 경유)
	local creature = DataHelper.GetData("CreatureData", cid)
	if creature and creature.icon then
		return creature.icon
	end

	local function normalize(name: string): string
		return string.lower(tostring(name or "")):gsub("[^%w]", "")
	end

	local function extractImageAsset(inst)
		if inst:IsA("Decal") or inst:IsA("Texture") then return inst.Texture end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then return inst.Image end
		if inst:IsA("StringValue") then return inst.Value end
		return ""
	end

	-- 2. Assets 폴더 내 다중 후보 경로를 순회해 가장 먼저 매칭되는 아이콘 사용
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local searchFolders = {
			assets:FindFirstChild("CreatureIcons"),
			assets:FindFirstChild("ItemIcons"),
			assets:FindFirstChild("Icons"),
		}

		local aliases = {
			cid,
			creature and creature.modelName,
			creature and creature.name,
		}

		for _, folder in ipairs(searchFolders) do
			if folder then
				for _, child in ipairs(folder:GetChildren()) do
					local cname = normalize(child.Name)
					for _, alias in ipairs(aliases) do
						if alias and cname == normalize(alias) then
							local imageId = extractImageAsset(child)
							if imageId and imageId ~= "" then
								return imageId
							end
						end
					end
				end
			end
		end
	end
	return "rbxassetid://0" -- 투명 아이콘
end

--========================================
-- Render Loop
--========================================

local function _renderTabs()
	for _, c in ipairs(CollectionUI.Refs.TabList:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	for i, tab in ipairs(CATEGORY_TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. tab.key
		btn.Size = UDim2.new(1, 0, 0, 50)
		btn.Font = F.TITLE
		btn.TextSize = 18
		btn.Text = UILocalizer.Localize(tab.label)
		
		if activeTabKey == tab.key then
			btn.BackgroundColor3 = C.GOLD
			btn.TextColor3 = C.BG_OVERLAY
		else
			btn.BackgroundColor3 = C.BG_PANEL
			btn.TextColor3 = C.DIM
		end
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn
		
		btn.MouseButton1Click:Connect(function()
			activeTabKey = tab.key
			_renderTabs()
			CollectionUI.refreshData()
		end)
		
		btn.Parent = CollectionUI.Refs.TabList
	end
end

local function _renderDetails()
	local detailFrame = CollectionUI.Refs.DetailFrame
	if not detailFrame then return end
	
	for _, c in ipairs(detailFrame:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false end
	end
	
	if not selectedCreatureId then
		local mt = detailFrame:FindFirstChild("EmptyText")
		if not mt then
			mt = Utils.CreateTextLabel("EmptyText", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize("동물을 선택하세요."))
			mt.TextColor3 = C.DIM
			mt.Parent = detailFrame
		end
		mt.Visible = true
		return
	end
	
	-- 상세 내용물
	local pnl = detailFrame:FindFirstChild("ContentPnl")
	if not pnl then
		pnl = Instance.new("Frame")
		pnl.Name = "ContentPnl"
		pnl.Size = UDim2.new(1,0,1,0)
		pnl.BackgroundTransparency = 1
		pnl.Parent = detailFrame
		
		local iconBg = Utils.CreateFrame("IconBg", UDim2.new(0, 100, 0, 100), UDim2.new(0.5, 0, 0, 20), C.BG_SLOT)
		iconBg.AnchorPoint = Vector2.new(0.5, 0)
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = iconBg
		
		local iconImg = Utils.CreateImage("IconImg", UDim2.new(0.8,0,0.8,0), UDim2.new(0.1,0,0.1,0), "")
		iconImg.Parent = iconBg
		
		local nameTxt = Utils.CreateTextLabel("NameTxt", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 130), UILocalizer.Localize("이름"))
		nameTxt.Font = F.TITLE
		nameTxt.TextSize = 24
		
		local dnaTxt = Utils.CreateTextLabel("DnaTxt", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 160), UILocalizer.Localize("DNA: 0/5"))
		dnaTxt.TextColor3 = C.GOLD
		
		local infoTxt = Utils.CreateTextLabel("InfoTxt", UDim2.new(0.9, 0, 0, 60), UDim2.new(0.05, 0, 0, 190), UILocalizer.Localize("동물 정보"))
		infoTxt.TextColor3 = C.DIM
		infoTxt.TextXAlignment = Enum.TextXAlignment.Left
		infoTxt.TextYAlignment = Enum.TextYAlignment.Top
		
		iconBg.Parent = pnl
		nameTxt.Parent = pnl
		dnaTxt.Parent = pnl
		infoTxt.Parent = pnl
		
		-- 장착 효과
		local effBg = Utils.CreateFrame("EffBg", UDim2.new(0.9,0,0,80), UDim2.new(0.05,0,0,260), C.BTN)
		Instance.new("UICorner", effBg).CornerRadius = UDim.new(0,8)
		
		local effTit = Utils.CreateTextLabel("EffTit", UDim2.new(1,0,0,20), UDim2.new(0,0,0,5), UILocalizer.Localize("장착 시 플레이어 효과"))
		effTit.TextSize = 14
		effTit.Font = F.TITLE
		effTit.Parent = effBg
		
		local effVal = Utils.CreateTextLabel("EffVal", UDim2.new(0.9,0,0,40), UDim2.new(0.05,0,0,30), UILocalizer.Localize("[장착 보너스 비활성]\n준비 중인 기능입니다."))
		effVal.TextXAlignment = Enum.TextXAlignment.Left
		effVal.Parent = effBg
		effBg.Parent = pnl
		
	end
	pnl.Visible = true
	
	local data = CollectionController.getCreatureData(selectedCreatureId)
	local dnaCount = CollectionController.getDnaCount(selectedCreatureId)
	
	local iconBg = pnl:FindFirstChild("IconBg")
	if iconBg and iconBg:FindFirstChild("IconImg") then
		iconBg.IconImg.Image = getCreatureIcon(selectedCreatureId)
	end
	local nameTxt = pnl:FindFirstChild("NameTxt")
	if nameTxt then
		local sourceName = (data and data.name) or selectedCreatureId
		nameTxt.Text = UILocalizer.LocalizeDataText("CreatureData", selectedCreatureId, "name", sourceName)
	end
	local dnaTxt = pnl:FindFirstChild("DnaTxt")
	if dnaTxt then
		dnaTxt.Text = UILocalizer.Localize(string.format("DNA: %d/5", dnaCount))
	end
	
	local effVal = pnl:FindFirstChild("EffBg") and pnl.EffBg:FindFirstChild("EffVal")
	if effVal then
		effVal.Text = UILocalizer.Localize("[장착 보너스 비활성]\n준비 중인 기능입니다.")
		effVal.TextColor3 = C.DIM
	end
end

----------------------------------------------------------------
-- Refresh Items (Scroll List)
----------------------------------------------------------------
function CollectionUI.refreshData()
	if not isUIInitialized then return end
	
	local scroll = CollectionUI.Refs.Scroll
	
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	local creatures = CollectionController.getCreatureList()
	if not creatures then return end
	
	local x, y = 10, 10
	local CARD_W = 110
	local CARD_H = 130
	local SPACING = 10
	local cols = 4
	
	local count = 0
	
	for _, data in ipairs(creatures) do
		local cid = data.id
		local region = REGION_MAP[cid] or "GRASSLAND"
		
		if activeTabKey == "ALL" or activeTabKey == region then
			local dCount = CollectionController.getDnaCount(cid)
			
			local card = Utils.CreateFrame("Card_"..cid, UDim2.new(0, CARD_W, 0, CARD_H), UDim2.new(0, x, 0, y), C.BTN)
			local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = card
			
			-- 선택 하이라이트
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = (cid == selectedCreatureId) and C.GOLD_SEL or Color3.fromRGB(60,60,60)
			stroke.Parent = card
			
			-- 아이콘
			local icon = Utils.CreateImage("Icon", UDim2.new(0, 60, 0, 60), UDim2.new(0.5, -30, 0, 15), getCreatureIcon(cid))
			icon.Parent = card
			
			-- 이름
			local sourceName = data.name or cid
			local localizedName = UILocalizer.LocalizeDataText("CreatureData", cid, "name", sourceName)
			local nameL = Utils.CreateTextLabel("Name", UDim2.new(1,0,0,20), UDim2.new(0,0,0,80), localizedName)
			nameL.TextSize = 13
			nameL.Parent = card
			
			-- DNA 바
			local barBg = Utils.CreateFrame("BarBg", UDim2.new(0.8, 0, 0, 10), UDim2.new(0.1, 0, 0, 105), Color3.fromRGB(0,0,0))
			Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)
			
			local fillRatio = math.clamp(dCount / 5, 0, 1)
			local barFill = Utils.CreateFrame("BarFill", UDim2.new(fillRatio, 0, 1, 0), UDim2.new(0,0,0,0), C.GOLD)
			Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 5)
			barFill.Parent = barBg
			
			local countT = Utils.CreateTextLabel("Cnt", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize(string.format("%d/5", dCount)))
			countT.TextSize = 10
			countT.Parent = barBg
			
			barBg.Parent = card
			
			-- Click Event
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1,0,1,0)
			btn.BackgroundTransparency = 1
			btn.Text = ""
			btn.Parent = card
			
			btn.MouseButton1Click:Connect(function()
				selectedCreatureId = cid
				CollectionUI.refreshData() -- 재렌더링
			end)
			
			card.Parent = scroll
			
			-- Layout calculation
			count = count + 1
			if count % cols == 0 then
				x = 10
				y = y + CARD_H + SPACING
			else
				x = x + CARD_W + SPACING
			end
		end
	end
	
	scroll.CanvasSize = UDim2.new(0, 0, 0, y + CARD_H + SPACING)
	
	_renderDetails()
end

--========================================
-- Init
--========================================

function CollectionUI.Init(mainGui, uiManager)
	if isUIInitialized then return end
	UIManager = uiManager
	
	-- Main Window (Using Modern Theme style)
	local Frame = Utils.mkFrame({
		name = "CollectionFrame", 
		size = UDim2.new(0, 900, 0, 580), 
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER
	})
	Frame.Visible = false
	CollectionUI.Refs.Frame = Frame
	
	-- Header
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=Frame})
	Utils.mkLabel({text=UILocalizer.Localize("도감 [P]"), pos=UDim2.new(0, 15, 0, 0), ts=20, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1, 0.5), bg=C.BTN, bgT=0.5, ts=20, color=C.WHITE, r=4, fn=function() UIManager.closeCollection() end, parent=header})
	
	-- 좌측 탭 영역
	local TabList = Instance.new("ScrollingFrame")
	TabList.Name = "TabList"
	TabList.Size = UDim2.new(0, 120, 1, -60)
	TabList.Position = UDim2.new(0, 10, 0, 50)
	TabList.BackgroundTransparency = 1
	TabList.CanvasSize = UDim2.new(0, 0, 0, 500)
	TabList.ScrollBarThickness = 4
	local tlLayout = Instance.new("UIListLayout"); tlLayout.Padding = UDim.new(0, 10); tlLayout.Parent = TabList
	CollectionUI.Refs.TabList = TabList
	TabList.Parent = Frame
	
	-- 중앙 스크롤 (공룡카드)
	local Scroll = Instance.new("ScrollingFrame")
	Scroll.Name = "CreatureList"
	Scroll.Size = UDim2.new(0, 490, 1, -70)
	Scroll.Position = UDim2.new(0, 140, 0, 60)
	Scroll.BackgroundColor3 = C.BG_SLOT
	Scroll.BackgroundTransparency = 0.35
	Scroll.ScrollBarThickness = 5
	Scroll.ScrollBarImageColor3 = C.GOLD
	Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Scroll.CanvasSize = UDim2.new(0,0,0,0)
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = Scroll
	
	Utils.AddCorner(Scroll, 8)
	CollectionUI.Refs.Scroll = Scroll
	Scroll.Parent = Frame
	
	-- 우측 상세 정보창
	local DetailFrame = Instance.new("Frame")
	DetailFrame.Name = "DetailFrame"
	DetailFrame.Size = UDim2.new(0, 240, 1, -60)
	DetailFrame.Position = UDim2.new(0, 640, 0, 50)
	DetailFrame.BackgroundColor3 = C.BG_PANEL_L
	DetailFrame.BackgroundTransparency = 0.15
	Utils.AddCorner(DetailFrame, 8)
	CollectionUI.Refs.DetailFrame = DetailFrame
	DetailFrame.Parent = Frame
	
	Frame.Parent = mainGui
	
	isUIInitialized = true
	print("[CollectionUI] Initialized")
end

--========================================
-- API
--========================================

function CollectionUI.Show()
	if not CollectionUI.Refs.Frame then return end
	CollectionUI.Refs.Frame.Visible = true
	
	_renderTabs()
	CollectionUI.refreshData()
	
	-- Data Event Hook (DNA 획득 시 UI에 열려있으면 즉시 반영)
	CollectionController.onDnaUpdated(function()
		if WindowManager.isOpen("COLLECTION") then
			CollectionUI.refreshData()
		end
	end)
end

function CollectionUI.Hide()
	if not CollectionUI.Refs.Frame then return end
	CollectionUI.Refs.Frame.Visible = false
	selectedCreatureId = nil
end

return CollectionUI
