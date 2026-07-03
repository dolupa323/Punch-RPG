-- MagicianController.lua
-- Magician NPC 클라이언트 대화창 + 퀘스트 인디케이터
-- TrainerController와 동일한 패턴

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MagicianController = {}

local Client      = script.Parent.Parent
local Theme       = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local NetClient   = require(Client:WaitForChild("NetClient"))
local UIManager   = require(Client:WaitForChild("UIManager"))
local UILocalizer = require(Client:WaitForChild("Localization"):WaitForChild("UILocalizer"))

local player = Players.LocalPlayer
local F = Theme.Fonts
local initialized = false

local indicatorGui = nil
local pendingState = "NONE"

-- ── NPC 루트 파트 탐색 ──

local function _waitForMagicianPart()
	local npcFolder = workspace:WaitForChild("NPC", 30)
	if not npcFolder then warn("[MagicianController] workspace.NPC 폴더 없음"); return nil end
	local magician = npcFolder:WaitForChild("Magician", 30)
	if not magician then warn("[MagicianController] workspace.NPC.Magician 없음"); return nil end

	local head = magician:WaitForChild("Head", 15)
	if head then return head end

	local hrp = magician:WaitForChild("HumanoidRootPart", 10)
	if hrp then return hrp end

	for _, d in ipairs(magician:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	warn("[MagicianController] Magician BasePart를 찾지 못했습니다.")
	return nil
end

-- ── 인디케이터 BillboardGui ──

local function _buildIndicatorGui(rootPart, state)
	if indicatorGui then
		indicatorGui:Destroy()
		indicatorGui = nil
	end
	if state == "NONE" then return end
	if not rootPart then warn("[MagicianController] rootPart 없음"); return end

	local isAvailable = (state == "AVAILABLE")
	local playerGui = player:WaitForChild("PlayerGui")

	local bb = Instance.new("BillboardGui")
	bb.Name           = "MagicianQuestIndicator"
	bb.Size           = UDim2.new(0, 36, 0, 58)
	bb.StudsOffset    = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop    = true
	bb.MaxDistance    = 100
	bb.ResetOnSpawn   = false
	bb.Adornee        = rootPart
	bb.Parent         = playerGui

	-- 그림자
	local shadow = Instance.new("TextLabel")
	shadow.Size                 = UDim2.new(1, 0, 1, 0)
	shadow.Position             = UDim2.new(0, 2, 0, 3)
	shadow.BackgroundTransparency = 1
	shadow.Text                 = isAvailable and "!" or "?"
	shadow.Font                 = Enum.Font.GothamBold
	shadow.TextSize             = 52
	shadow.TextColor3           = isAvailable and Color3.fromRGB(120, 50, 0) or Color3.fromRGB(20, 60, 140)
	shadow.TextTransparency     = 0.3
	shadow.TextXAlignment       = Enum.TextXAlignment.Center
	shadow.TextYAlignment       = Enum.TextYAlignment.Center
	shadow.ZIndex               = 1
	shadow.Parent               = bb

	-- 메인 텍스트
	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                  = isAvailable and "!" or "?"
	label.Font                  = Enum.Font.GothamBold
	label.TextSize              = 52
	label.TextColor3            = isAvailable and Color3.fromRGB(255, 190, 30) or Color3.fromRGB(100, 200, 255)
	label.TextStrokeColor3      = isAvailable and Color3.fromRGB(160, 80, 0) or Color3.fromRGB(30, 80, 180)
	label.TextStrokeTransparency = 0
	label.TextXAlignment        = Enum.TextXAlignment.Center
	label.TextYAlignment        = Enum.TextYAlignment.Center
	label.ZIndex                = 2
	label.Parent                = bb

	-- 바운스 애니메이션
	task.spawn(function()
		while bb and bb.Parent do
			TweenService:Create(bb, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				StudsOffset = Vector3.new(0, 4.6, 0)
			}):Play()
			task.wait(0.6)
			if not bb or not bb.Parent then break end
			TweenService:Create(bb, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				StudsOffset = Vector3.new(0, 3.5, 0)
			}):Play()
			task.wait(0.6)
		end
	end)

	indicatorGui = bb
end

local function setIndicator(state)
	pendingState = state
	task.spawn(function()
		local rootPart = _waitForMagicianPart()
		_buildIndicatorGui(rootPart, pendingState)
	end)
end

-- ── 대화창 UI ──

local function showDialogue(data)
	local npcName  = UILocalizer.Localize(data.npcName  or "마법사")
	local dialogue = UILocalizer.Localize(data.dialogue or "")
	local choices  = data.choices  or {}

	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("MagicianDialogueSG")
	if existing then existing:Destroy() end

	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local sg = Instance.new("ScreenGui")
	sg.Name           = "MagicianDialogueSG"
	sg.ResetOnSpawn   = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder   = 200
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	-- ── 메인 박스: 가로 폭 제한, 하단 중앙 배치, 세로 자동 확장 ──
	local BOX_W = isMobile and UDim2.new(0.96, 0, 0, 0) or UDim2.new(0, 740, 0, 0)
	local dialogueBox = Instance.new("Frame")
	dialogueBox.Name                  = "DialogueBox"
	dialogueBox.Size                  = BOX_W
	dialogueBox.AnchorPoint           = Vector2.new(0.5, 1)
	dialogueBox.Position              = UDim2.new(0.5, 0, 1, -8)
	dialogueBox.AutomaticSize         = Enum.AutomaticSize.Y
	dialogueBox.BackgroundColor3      = Color3.fromRGB(8, 12, 22)
	dialogueBox.BackgroundTransparency = 0.08
	dialogueBox.BorderSizePixel       = 0
	dialogueBox.Parent                = sg
	Instance.new("UICorner", dialogueBox).CornerRadius = UDim.new(0, 6)

	-- 상단 보라 라인
	local topLine = Instance.new("Frame")
	topLine.Size             = UDim2.new(1, 0, 0, 2)
	topLine.BackgroundColor3 = Color3.fromRGB(140, 100, 255)
	topLine.BorderSizePixel  = 0
	topLine.Parent           = dialogueBox
	Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 2)

	-- NPC 이름 플레이트 (박스 상단 왼쪽 위에 튀어나옴)
	local namePlate = Instance.new("Frame")
	namePlate.Size             = UDim2.new(0, 0, 0, 30)
	namePlate.Position         = UDim2.new(0, 18, 0, -16)
	namePlate.AutomaticSize    = Enum.AutomaticSize.X
	namePlate.BackgroundColor3 = Color3.fromRGB(35, 20, 70)
	namePlate.BorderSizePixel  = 0
	namePlate.ZIndex           = 2
	namePlate.Parent           = dialogueBox
	Instance.new("UICorner", namePlate).CornerRadius = UDim.new(0, 4)
	local npStroke = Instance.new("UIStroke", namePlate)
	npStroke.Color = Color3.fromRGB(140, 100, 255); npStroke.Thickness = 1.5

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.new(0, 0, 1, 0)
	nameLabel.AutomaticSize          = Enum.AutomaticSize.X
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = "  " .. npcName .. "  "
	nameLabel.Font                   = F.TITLE
	nameLabel.TextSize               = 14
	nameLabel.TextColor3             = Color3.fromRGB(200, 170, 255)
	nameLabel.ZIndex                 = 3
	nameLabel.Parent                 = namePlate

	-- ── 내부 레이아웃: 텍스트 → 구분선 → 선택지 순서로 세로 적층 ──
	local content = Instance.new("Frame")
	content.Name                  = "Content"
	content.Size                  = UDim2.new(1, -32, 0, 0)
	content.Position              = UDim2.new(0, 16, 0, 14)
	content.AutomaticSize         = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent                = dialogueBox

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder          = Enum.SortOrder.LayoutOrder
	contentLayout.Padding            = UDim.new(0, 0)
	contentLayout.FillDirection      = Enum.FillDirection.Vertical
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	contentLayout.Parent             = content

	-- 대화 텍스트 영역
	local textLabel = Instance.new("TextLabel")
	textLabel.Name                 = "DialogueText"
	textLabel.Size                 = UDim2.new(1, 0, 0, 0)
	textLabel.AutomaticSize        = Enum.AutomaticSize.Y
	textLabel.BackgroundTransparency = 1
	textLabel.Text                 = ""
	textLabel.Font                 = F.NORMAL
	textLabel.TextSize             = isMobile and 14 or 16
	textLabel.TextColor3           = Color3.fromRGB(230, 230, 230)
	textLabel.TextXAlignment       = Enum.TextXAlignment.Left
	textLabel.TextYAlignment       = Enum.TextYAlignment.Top
	textLabel.TextWrapped          = true
	textLabel.RichText             = true
	textLabel.LayoutOrder          = 1
	textLabel.Parent               = content
	local textPad = Instance.new("UIPadding", textLabel)
	textPad.PaddingTop    = UDim.new(0, 10)
	textPad.PaddingBottom = UDim.new(0, 10)

	-- 구분선 (선택지 나타날 때만 표시)
	local divider = Instance.new("Frame")
	divider.Name             = "Divider"
	divider.Size             = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(60, 45, 100)
	divider.BorderSizePixel  = 0
	divider.LayoutOrder      = 2
	divider.Visible          = false
	divider.Parent           = content

	-- 선택지 컨테이너
	local choiceFrame = Instance.new("Frame")
	choiceFrame.Name                  = "Choices"
	choiceFrame.Size                  = UDim2.new(1, 0, 0, 0)
	choiceFrame.AutomaticSize         = Enum.AutomaticSize.Y
	choiceFrame.BackgroundTransparency = 1
	choiceFrame.LayoutOrder           = 3
	choiceFrame.Parent                = content
	local choiceLayout = Instance.new("UIListLayout", choiceFrame)
	choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	choiceLayout.Padding   = UDim.new(0, 4)
	local choicePad = Instance.new("UIPadding", choiceFrame)
	choicePad.PaddingTop    = UDim.new(0, 8)
	choicePad.PaddingBottom = UDim.new(0, 10)

	-- 하단 여백 (이름 플레이트 아래 패딩)
	local bottomPad = Instance.new("Frame")
	bottomPad.Size                  = UDim2.new(1, 0, 0, 0)
	bottomPad.BackgroundTransparency = 1
	bottomPad.LayoutOrder           = 4
	bottomPad.Parent                = content

	local function closeDialogue()
		sg:Destroy()
	end

	local function makeChoiceBtn(text, layoutOrder, color, fn)
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, 0, 0, isMobile and 36 or 30)
		btn.BackgroundColor3 = Color3.fromRGB(25, 18, 50)
		btn.BorderSizePixel  = 0
		btn.Text             = "▶  " .. text
		btn.Font             = F.NORMAL
		btn.TextSize         = isMobile and 13 or 14
		btn.TextColor3       = color or Color3.fromRGB(200, 180, 255)
		btn.TextXAlignment   = Enum.TextXAlignment.Left
		btn.RichText         = false
		btn.LayoutOrder      = layoutOrder
		btn.ZIndex           = 2
		btn.Parent           = choiceFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		local pad = Instance.new("UIPadding", btn); pad.PaddingLeft = UDim.new(0, 10)
		btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(50, 35, 90) end)
		btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(25, 18, 50) end)
		btn.MouseButton1Click:Connect(fn)
		return btn
	end

	local fullText = dialogue
	local typingDone = false

	task.spawn(function()
		local displayed = ""
		local i = 1
		while i <= #fullText do
			if fullText:sub(i, i) == "<" then
				local tagEnd = fullText:find(">", i)
				if tagEnd then
					displayed = displayed .. fullText:sub(i, tagEnd)
					i = tagEnd + 1
				else
					displayed = displayed .. fullText:sub(i, i)
					i = i + 1
				end
			else
				displayed = displayed .. fullText:sub(i, i)
				i = i + 1
				textLabel.Text = displayed
				task.wait(0.012)
			end
		end
		textLabel.Text = fullText
		typingDone = true
	end)

	local choicesAdded = false
	local function addChoices()
		if choicesAdded then return end
		choicesAdded = true
		textLabel.Text = fullText
		divider.Visible = true

		for idx, choice in ipairs(choices) do
			local isAction = (choice.action ~= "CLOSE")
			local color = isAction and Color3.fromRGB(180, 150, 255) or Color3.fromRGB(160, 160, 160)
			makeChoiceBtn(UILocalizer.Localize(choice.text), idx, color, function()
				if choice.action == "CLOSE" then
					closeDialogue()
				elseif choice.action == "ACCEPT" or choice.action == "ACCEPT_TALK" or choice.action == "CLAIM" then
					closeDialogue()
					task.spawn(function()
						local ok, _ = NetClient.Request("Magician.QuestAction.Request", {
							action  = choice.action,
							questId = choice.questId,
						})
						if not ok then
							warn("[MagicianController] Quest action failed:", choice.action)
						end
					end)
				end
			end)
		end
	end

	-- 텍스트 클릭 시 타이핑 스킵
	local boxBtn = Instance.new("TextButton")
	boxBtn.Size                 = UDim2.new(1, 0, 0, 80)
	boxBtn.Position             = UDim2.new(0, 0, 0, 0)
	boxBtn.BackgroundTransparency = 1
	boxBtn.Text                 = ""
	boxBtn.ZIndex               = 5
	boxBtn.Parent               = textLabel
	boxBtn.MouseButton1Click:Connect(function()
		if not typingDone then
			typingDone = true
			textLabel.Text = fullText
			task.wait(0.05)
			addChoices()
		else
			addChoices()
		end
	end)

	task.spawn(function()
		while not typingDone do task.wait(0.05) end
		task.wait(0.1)
		addChoices()
	end)
end

-- ── 퀘스트 트래커 ──

local MAGICIAN_QUEST_SLOT = 101

local function showQuestTracker(data)
	UIManager.updateSideQuest(MAGICIAN_QUEST_SLOT, data)
end

-- ── Init ──

function MagicianController.Init()
	if initialized then return end
	initialized = true

	NetClient.On("Magician.OpenDialogue", function(data)
		showDialogue(data)
	end)

	NetClient.On("Magician.SetIndicator", function(data)
		local state = data and data.state or "NONE"
		setIndicator(state)
	end)

	NetClient.On("Magician.QuestTracker", function(data)
		showQuestTracker(data)
	end)

	-- 초기 로드 시 서버에서 인디케이터 상태 수신 (서버가 PlayerAdded에서 FireClient 보내줌)
	-- 혹시 놓친 경우를 대비해 5초 후 Trainer 패턴 동일하게 처리는 생략
	-- (MagicianQuestService.Init에서 PlayerAdded → task.wait(4) 후 _updateIndicator 호출)

	print("[MagicianController] Initialized.")
end

return MagicianController
