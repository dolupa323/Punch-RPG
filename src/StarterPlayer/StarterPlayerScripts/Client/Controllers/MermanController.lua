-- MermanController.lua
-- 클레이온 수문장 Merman NPC 클라이언트 대화창
-- TrainerController와 동일한 패턴, 오션(청록) 테마

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MermanController = {}

local Client    = script.Parent.Parent
local Theme     = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local NetClient = require(Client:WaitForChild("NetClient"))

local F = Theme.Fonts
local player = Players.LocalPlayer
local initialized = false

-- 오션 테마 색상
local THEME = {
	accent     = Color3.fromRGB(0,  200, 210),   -- 상단 라인
	nameBg     = Color3.fromRGB(8,  50,  60),    -- 이름 플레이트 배경
	nameStroke = Color3.fromRGB(0,  200, 210),   -- 이름 플레이트 테두리
	nameText   = Color3.fromRGB(120, 240, 245),  -- 이름 텍스트
	boxBg      = Color3.fromRGB(6,  14,  22),    -- 대화창 배경
	divider    = Color3.fromRGB(20, 80,  90),    -- 구분선
	btnBg      = Color3.fromRGB(8,  40,  50),    -- 선택지 버튼 배경
	btnHover   = Color3.fromRGB(15, 75,  90),    -- 선택지 호버
	btnAction  = Color3.fromRGB(80, 220, 230),   -- 액션 선택지 글자
	btnClose   = Color3.fromRGB(160, 160, 160),  -- 닫기 선택지 글자
}

local function showMermanDialogue(data)
	local npcName  = data.npcName  or "Merman"
	local dialogue = data.dialogue or ""
	local choices  = data.choices  or {}

	local playerGui = player:WaitForChild("PlayerGui")
	local existing  = playerGui:FindFirstChild("MermanDialogueSG")
	if existing then existing:Destroy() end

	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local sg = Instance.new("ScreenGui")
	sg.Name           = "MermanDialogueSG"
	sg.ResetOnSpawn   = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder   = 200
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	-- 메인 박스 (하단 중앙, 세로 자동 확장)
	local BOX_W = isMobile and UDim2.new(0.96, 0, 0, 0) or UDim2.new(0, 740, 0, 0)
	local dialogueBox = Instance.new("Frame")
	dialogueBox.Size                   = BOX_W
	dialogueBox.AnchorPoint            = Vector2.new(0.5, 1)
	dialogueBox.Position               = UDim2.new(0.5, 0, 1, -8)
	dialogueBox.AutomaticSize          = Enum.AutomaticSize.Y
	dialogueBox.BackgroundColor3       = THEME.boxBg
	dialogueBox.BackgroundTransparency = 0.08
	dialogueBox.BorderSizePixel        = 0
	dialogueBox.Parent                 = sg
	Instance.new("UICorner", dialogueBox).CornerRadius = UDim.new(0, 6)

	-- 상단 오션 라인
	local topLine = Instance.new("Frame")
	topLine.Size             = UDim2.new(1, 0, 0, 2)
	topLine.BackgroundColor3 = THEME.accent
	topLine.BorderSizePixel  = 0
	topLine.Parent           = dialogueBox
	Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 2)

	-- NPC 이름 플레이트
	local namePlate = Instance.new("Frame")
	namePlate.Size             = UDim2.new(0, 0, 0, 30)
	namePlate.Position         = UDim2.new(0, 18, 0, -16)
	namePlate.AutomaticSize    = Enum.AutomaticSize.X
	namePlate.BackgroundColor3 = THEME.nameBg
	namePlate.BorderSizePixel  = 0
	namePlate.ZIndex           = 2
	namePlate.Parent           = dialogueBox
	Instance.new("UICorner", namePlate).CornerRadius = UDim.new(0, 4)
	local npStroke = Instance.new("UIStroke", namePlate)
	npStroke.Color     = THEME.nameStroke
	npStroke.Thickness = 1.5

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.new(0, 0, 1, 0)
	nameLabel.AutomaticSize          = Enum.AutomaticSize.X
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = "  " .. npcName .. "  "
	nameLabel.Font                   = F.TITLE
	nameLabel.TextSize               = 14
	nameLabel.TextColor3             = THEME.nameText
	nameLabel.ZIndex                 = 3
	nameLabel.Parent                 = namePlate

	-- 내부 레이아웃
	local content = Instance.new("Frame")
	content.Size                   = UDim2.new(1, -32, 0, 0)
	content.Position               = UDim2.new(0, 16, 0, 14)
	content.AutomaticSize          = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent                 = dialogueBox
	local contentLayout = Instance.new("UIListLayout", content)
	contentLayout.SortOrder           = Enum.SortOrder.LayoutOrder
	contentLayout.Padding             = UDim.new(0, 0)
	contentLayout.FillDirection       = Enum.FillDirection.Vertical
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- 대화 텍스트
	local textLabel = Instance.new("TextLabel")
	textLabel.Size                   = UDim2.new(1, 0, 0, 0)
	textLabel.AutomaticSize          = Enum.AutomaticSize.Y
	textLabel.BackgroundTransparency = 1
	textLabel.Text                   = ""
	textLabel.Font                   = F.NORMAL
	textLabel.TextSize               = isMobile and 14 or 16
	textLabel.TextColor3             = Color3.fromRGB(230, 230, 230)
	textLabel.TextXAlignment         = Enum.TextXAlignment.Left
	textLabel.TextYAlignment         = Enum.TextYAlignment.Top
	textLabel.TextWrapped            = true
	textLabel.RichText               = true
	textLabel.LayoutOrder            = 1
	textLabel.Parent                 = content
	local textPad = Instance.new("UIPadding", textLabel)
	textPad.PaddingTop    = UDim.new(0, 10)
	textPad.PaddingBottom = UDim.new(0, 10)

	-- 구분선
	local divider = Instance.new("Frame")
	divider.Size             = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = THEME.divider
	divider.BorderSizePixel  = 0
	divider.LayoutOrder      = 2
	divider.Visible          = false
	divider.Parent           = content

	-- 선택지 컨테이너
	local choiceFrame = Instance.new("Frame")
	choiceFrame.Size                   = UDim2.new(1, 0, 0, 0)
	choiceFrame.AutomaticSize          = Enum.AutomaticSize.Y
	choiceFrame.BackgroundTransparency = 1
	choiceFrame.LayoutOrder            = 3
	choiceFrame.Parent                 = content
	local choiceLayout = Instance.new("UIListLayout", choiceFrame)
	choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	choiceLayout.Padding   = UDim.new(0, 4)
	local choicePad = Instance.new("UIPadding", choiceFrame)
	choicePad.PaddingTop    = UDim.new(0, 8)
	choicePad.PaddingBottom = UDim.new(0, 10)

	local function closeDialogue()
		if sg and sg.Parent then sg:Destroy() end
	end

	local function makeChoiceBtn(text, layoutOrder, color, fn)
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, 0, 0, isMobile and 36 or 30)
		btn.BackgroundColor3 = THEME.btnBg
		btn.BorderSizePixel  = 0
		btn.Text             = "▶  " .. text
		btn.Font             = F.NORMAL
		btn.TextSize         = isMobile and 13 or 14
		btn.TextColor3       = color
		btn.TextXAlignment   = Enum.TextXAlignment.Left
		btn.RichText         = false
		btn.LayoutOrder      = layoutOrder
		btn.ZIndex           = 2
		btn.Parent           = choiceFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		local pad = Instance.new("UIPadding", btn)
		pad.PaddingLeft = UDim.new(0, 10)
		btn.MouseEnter:Connect(function() btn.BackgroundColor3 = THEME.btnHover end)
		btn.MouseLeave:Connect(function() btn.BackgroundColor3 = THEME.btnBg end)
		btn.MouseButton1Click:Connect(fn)
		return btn
	end

	local fullText   = dialogue
	local typingDone = false

	-- 타이핑 효과
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
		choicesAdded    = true
		textLabel.Text  = fullText
		divider.Visible = true

		for idx, choice in ipairs(choices) do
			local isAction = (choice.action ~= "CLOSE")
			local color    = isAction and THEME.btnAction or THEME.btnClose
			makeChoiceBtn(choice.text, idx, color, function()
				closeDialogue()
				if choice.action == "CLOSE" then
					-- 서버에 닫기 알림 (서버가 레벨 확인 후 추방 여부 결정)
					task.spawn(function()
						NetClient.Request("Merman.QuestAction.Request", { action = "CLOSE" })
					end)
				end
			end)
		end
	end

	-- 텍스트 클릭 시 타이핑 스킵
	local boxBtn = Instance.new("TextButton")
	boxBtn.Size                   = UDim2.new(1, 0, 0, 80)
	boxBtn.BackgroundTransparency = 1
	boxBtn.Text                   = ""
	boxBtn.ZIndex                 = 5
	boxBtn.Parent                 = textLabel
	boxBtn.MouseButton1Click:Connect(function()
		if not typingDone then
			typingDone     = true
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

function MermanController.Init()
	if initialized then return end
	initialized = true

	NetClient.On("Merman.OpenDialogue", function(data)
		showMermanDialogue(data)
	end)

	print("[MermanController] Initialized.")
end

return MermanController
