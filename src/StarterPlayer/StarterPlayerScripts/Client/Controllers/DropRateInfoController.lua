-- DropRateInfoController.lua
-- 척척박사(citizen_01) NPC 대화창: "무엇이 알고싶나?" -> 아이템 드롭률 표 오픈

local Players          = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")

local DropRateInfoController = {}

local Client      = script.Parent.Parent
local Theme       = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local NetClient   = require(Client:WaitForChild("NetClient"))
local UILocalizer = require(Client:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local DropRateUI  = require(Client:WaitForChild("UI"):WaitForChild("DropRateUI"))

local player = Players.LocalPlayer
local F = Theme.Fonts
local initialized = false

local function showDialogue(data)
	local npcName  = UILocalizer.Localize(data.npcName  or "척척박사")
	local dialogue = UILocalizer.Localize(data.dialogue or "")
	local choices  = data.choices  or {}

	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DropInfoDialogueSG")
	if existing then existing:Destroy() end

	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local sg = Instance.new("ScreenGui")
	sg.Name           = "DropInfoDialogueSG"
	sg.ResetOnSpawn   = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder   = 200
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	local BOX_W = isMobile and UDim2.new(0.96, 0, 0, 0) or UDim2.new(0, 740, 0, 0)
	local dialogueBox = Instance.new("Frame")
	dialogueBox.Name                   = "DialogueBox"
	dialogueBox.Size                   = BOX_W
	dialogueBox.AnchorPoint            = Vector2.new(0.5, 1)
	dialogueBox.Position               = UDim2.new(0.5, 0, 1, -8)
	dialogueBox.AutomaticSize          = Enum.AutomaticSize.Y
	dialogueBox.BackgroundColor3       = Color3.fromRGB(8, 12, 22)
	dialogueBox.BackgroundTransparency = 0.08
	dialogueBox.BorderSizePixel        = 0
	dialogueBox.Parent                 = sg
	Instance.new("UICorner", dialogueBox).CornerRadius = UDim.new(0, 6)

	local topLine = Instance.new("Frame")
	topLine.Size             = UDim2.new(1, 0, 0, 2)
	topLine.BackgroundColor3 = Color3.fromRGB(230, 190, 90)
	topLine.BorderSizePixel  = 0
	topLine.Parent           = dialogueBox
	Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 2)

	local namePlate = Instance.new("Frame")
	namePlate.Size             = UDim2.new(0, 0, 0, 30)
	namePlate.Position         = UDim2.new(0, 18, 0, -16)
	namePlate.AutomaticSize    = Enum.AutomaticSize.X
	namePlate.BackgroundColor3 = Color3.fromRGB(45, 35, 15)
	namePlate.BorderSizePixel  = 0
	namePlate.ZIndex           = 2
	namePlate.Parent           = dialogueBox
	Instance.new("UICorner", namePlate).CornerRadius = UDim.new(0, 4)
	local npStroke = Instance.new("UIStroke", namePlate)
	npStroke.Color = Color3.fromRGB(230, 190, 90); npStroke.Thickness = 1.5

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.new(0, 0, 1, 0)
	nameLabel.AutomaticSize          = Enum.AutomaticSize.X
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = "  " .. npcName .. "  "
	nameLabel.Font                   = F.TITLE
	nameLabel.TextSize               = 14
	nameLabel.TextColor3             = Color3.fromRGB(255, 225, 160)
	nameLabel.ZIndex                 = 3
	nameLabel.Parent                 = namePlate

	local content = Instance.new("Frame")
	content.Name                   = "Content"
	content.Size                   = UDim2.new(1, -32, 0, 0)
	content.Position               = UDim2.new(0, 16, 0, 14)
	content.AutomaticSize          = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent                 = dialogueBox

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder           = Enum.SortOrder.LayoutOrder
	contentLayout.Padding             = UDim.new(0, 0)
	contentLayout.FillDirection       = Enum.FillDirection.Vertical
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	contentLayout.Parent              = content

	local textLabel = Instance.new("TextLabel")
	textLabel.Name                   = "DialogueText"
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

	local divider = Instance.new("Frame")
	divider.Name             = "Divider"
	divider.Size             = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(65, 55, 35)
	divider.BorderSizePixel  = 0
	divider.LayoutOrder      = 2
	divider.Visible          = false
	divider.Parent           = content

	local choiceFrame = Instance.new("Frame")
	choiceFrame.Name                   = "Choices"
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

	local bottomPad = Instance.new("Frame")
	bottomPad.Size                   = UDim2.new(1, 0, 0, 0)
	bottomPad.BackgroundTransparency = 1
	bottomPad.LayoutOrder            = 4
	bottomPad.Parent                 = content

	local function closeDialogue()
		sg:Destroy()
	end

	local function makeChoiceBtn(text, layoutOrder, color, fn)
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, 0, 0, isMobile and 36 or 30)
		btn.BackgroundColor3 = Color3.fromRGB(32, 26, 14)
		btn.BorderSizePixel  = 0
		btn.Text             = "▶  " .. text
		btn.Font             = F.NORMAL
		btn.TextSize         = isMobile and 13 or 14
		btn.TextColor3       = color or Color3.fromRGB(230, 210, 170)
		btn.TextXAlignment   = Enum.TextXAlignment.Left
		btn.RichText         = false
		btn.LayoutOrder      = layoutOrder
		btn.ZIndex           = 2
		btn.Parent           = choiceFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		local pad = Instance.new("UIPadding", btn); pad.PaddingLeft = UDim.new(0, 10)
		btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(60, 48, 22) end)
		btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(32, 26, 14) end)
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
			local color = isAction and Color3.fromRGB(255, 215, 130) or Color3.fromRGB(160, 160, 160)
			makeChoiceBtn(UILocalizer.Localize(choice.text), idx, color, function()
				if choice.action == "CLOSE" then
					closeDialogue()
				elseif choice.action == "SHOW_DROPTABLE" then
					closeDialogue()
					task.spawn(function()
						local ok, result = NetClient.Request("DropInfo.GetTable.Request", {})
						if ok and type(result) == "table" and result.rows then
							DropRateUI.Open(result.rows)
						else
							warn("[DropRateInfoController] Failed to fetch drop table")
						end
					end)
				end
			end)
		end
	end

	local boxBtn = Instance.new("TextButton")
	boxBtn.Size                   = UDim2.new(1, 0, 0, 80)
	boxBtn.BackgroundTransparency = 1
	boxBtn.Text                   = ""
	boxBtn.ZIndex                 = 5
	boxBtn.Parent                 = textLabel
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

function DropRateInfoController.Init()
	if initialized then return end
	initialized = true

	NetClient.On("DropInfo.OpenDialogue", function(data)
		showDialogue(data)
	end)

	print("[DropRateInfoController] Initialized.")
end

return DropRateInfoController
