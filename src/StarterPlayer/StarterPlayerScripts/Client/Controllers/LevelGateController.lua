-- LevelGateController.lua
-- Knight NPC 상호작용 - SkyIslandGuide와 동일한 하단 RPG 대화창 스타일

local Players = game:GetService("Players")

local LevelGateController = {}

local Client = script.Parent.Parent
local Theme = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local UIManager = require(Client:WaitForChild("UIManager"))
local player = Players.LocalPlayer

local F = Theme.Fonts

local initialized = false

local function showNpcDialogue(npcName, dialogueText, confirmText, declineText, onConfirm)
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:FindFirstChild("MainGui") or playerGui:FindFirstChildWhichIsA("ScreenGui")
	if not mainGui then return end

	if mainGui:FindFirstChild("KnightDialogueRoot") then
		mainGui.KnightDialogueRoot:Destroy()
	end

	local isMobile = (game:GetService("UserInputService").TouchEnabled
		and not game:GetService("UserInputService").KeyboardEnabled)

	local root = Instance.new("Frame")
	root.Name = "KnightDialogueRoot"
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.ZIndex = 950
	root.Parent = mainGui

	local BOX_H = isMobile and 0.32 or 0.28
	local dialogueBox = Instance.new("Frame")
	dialogueBox.Name = "DialogueBox"
	dialogueBox.Size = UDim2.new(1, 0, BOX_H, 0)
	dialogueBox.Position = UDim2.new(0, 0, 1 - BOX_H, 0)
	dialogueBox.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
	dialogueBox.BackgroundTransparency = 0.08
	dialogueBox.BorderSizePixel = 0
	dialogueBox.ZIndex = 951
	dialogueBox.Parent = root

	local topLine = Instance.new("Frame")
	topLine.Size = UDim2.new(1, 0, 0, 2)
	topLine.Position = UDim2.new(0, 0, 0, 0)
	topLine.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
	topLine.BorderSizePixel = 0
	topLine.ZIndex = 952
	topLine.Parent = dialogueBox

	local namePlate = Instance.new("Frame")
	namePlate.Name = "NamePlate"
	namePlate.Size = UDim2.new(0, 0, 0, 32)
	namePlate.Position = UDim2.new(0, 20, 0, -18)
	namePlate.BackgroundColor3 = Color3.fromRGB(20, 40, 90)
	namePlate.BorderSizePixel = 0
	namePlate.AutomaticSize = Enum.AutomaticSize.X
	namePlate.ZIndex = 953
	namePlate.Parent = dialogueBox

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 0, 1, 0)
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = " " .. npcName .. " "
	nameLabel.Font = F.TITLE
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(180, 210, 255)
	nameLabel.ZIndex = 954
	nameLabel.Parent = namePlate

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(100, 150, 255)
	nameStroke.Thickness = 1.5
	nameStroke.Parent = namePlate

	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 4)
	nameCorner.Parent = namePlate

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "DialogueText"
	textLabel.Size = UDim2.new(1, -40, 0.6, 0)
	textLabel.Position = UDim2.new(0, 20, 0, 22)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = ""
	textLabel.Font = F.NORMAL
	textLabel.TextSize = isMobile and 14 or 16
	textLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.TextWrapped = true
	textLabel.RichText = true
	textLabel.ZIndex = 952
	textLabel.Parent = dialogueBox

	local choiceFrame = Instance.new("Frame")
	choiceFrame.Name = "ChoiceFrame"
	choiceFrame.Size = UDim2.new(1, -40, 0, 0)
	choiceFrame.Position = UDim2.new(0, 20, 1, -10)
	choiceFrame.AnchorPoint = Vector2.new(0, 1)
	choiceFrame.BackgroundTransparency = 1
	choiceFrame.AutomaticSize = Enum.AutomaticSize.Y
	choiceFrame.ZIndex = 952
	choiceFrame.Parent = dialogueBox

	local choiceLayout = Instance.new("UIListLayout")
	choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	choiceLayout.Padding = UDim.new(0, 6)
	choiceLayout.Parent = choiceFrame

	local function makeChoiceBtn(text, layoutOrder, color, fn)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, isMobile and 36 or 32)
		btn.BackgroundColor3 = Color3.fromRGB(18, 28, 55)
		btn.BorderSizePixel = 0
		btn.Text = "▶  " .. text
		btn.Font = F.NORMAL
		btn.TextSize = isMobile and 13 or 14
		btn.TextColor3 = color or Color3.fromRGB(200, 220, 255)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.RichText = false
		btn.LayoutOrder = layoutOrder
		btn.ZIndex = 953
		btn.Parent = choiceFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = btn

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = btn

		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = Color3.fromRGB(30, 50, 100)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = Color3.fromRGB(18, 28, 55)
		end)
		btn.MouseButton1Click:Connect(fn)
		return btn
	end

	local function closeDialogue()
		root:Destroy()
	end

	local fullText = dialogueText
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

		if confirmText and onConfirm then
			makeChoiceBtn(confirmText, 1, Color3.fromRGB(150, 210, 255), function()
				closeDialogue()
				onConfirm()
			end)
		end

		makeChoiceBtn(declineText or "알겠습니다.", 2, Color3.fromRGB(180, 180, 180), function()
			closeDialogue()
		end)
	end

	local boxBtn = Instance.new("TextButton")
	boxBtn.Size = UDim2.new(1, 0, 1, 0)
	boxBtn.BackgroundTransparency = 1
	boxBtn.Text = ""
	boxBtn.ZIndex = 951
	boxBtn.Parent = dialogueBox
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
		while not typingDone do
			task.wait(0.05)
		end
		task.wait(0.1)
		addChoices()
	end)
end

local function _setupPrompt(rootPart)
	if rootPart:FindFirstChild("KnightPrompt") then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "KnightPrompt"
	prompt.ActionText = "대화하기"
	prompt.ObjectText = "기사"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function()
		local lvl = UIManager.getCurrentPlayerLevel() or 1
		if lvl <= 40 then
			showNpcDialogue(
				"수호기사",
				"앗, 모험가님! 죄송하지만 여기부터는 레벨 <b>41</b> 이상의 모험가분들만 통과할 수 있도록 상부의 지시를 받았습니다.\n아직은 진입하시기에 다소 위험할 수 있으니, 조금 더 수련을 마친 후에 와주시기 바랍니다.",
				nil, "알겠습니다.", nil
			)
		else
			showNpcDialogue(
				"수호기사",
				"레벨 <b>41</b>을 달성하셨군요! 이제 문을 통과하여 위쪽 구역으로 이동하셔도 좋습니다.\n상층 구역은 아래보다 길이 많이 험난하니 부디 몸조심해서 다녀오십시오.",
				nil, "알겠습니다.", nil
			)
		end
	end)

	print("[LevelGateController] KnightPrompt 등록 완료.")
end

function LevelGateController.Init()
	if initialized then return end
	initialized = true

	task.spawn(function()
		-- 타임아웃 60초로 확보 (느린 로드 / 스트리밍 환경 대응)
		local npcFolder = workspace:WaitForChild("NPC", 60)
		if not npcFolder then
			warn("[LevelGateController] NPC 폴더 없음")
			return
		end

		local knight = npcFolder:WaitForChild("Knight", 60)
		if not knight then
			warn("[LevelGateController] Knight NPC 없음")
			return
		end

		local rootPart = knight:WaitForChild("HumanoidRootPart", 30)
		if not rootPart then
			warn("[LevelGateController] Knight HumanoidRootPart 없음")
			return
		end

		_setupPrompt(rootPart)
	end)
end

return LevelGateController
