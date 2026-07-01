-- TrainerController.lua
-- Trainer NPC 클라이언트 대화창 처리
-- 서버에서 보내주는 대화/선택지를 SkyIslandGuide와 동일한 하단 RPG 대화창으로 표시

local Players = game:GetService("Players")

local TrainerController = {}

local Client = script.Parent.Parent
local Theme = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local NetClient = require(Client:WaitForChild("NetClient"))
local UIManager = require(Client:WaitForChild("UIManager"))
local player = Players.LocalPlayer

local F = Theme.Fonts
local TweenService = game:GetService("TweenService")
local initialized = false

-- NPC 머리 위 퀘스트 인디케이터 (느낌표 / 물음표)
local indicatorGui = nil
local pendingState = "NONE"  -- NPC 로드 전에 받은 상태 보관

-- Trainer NPC의 BillboardGui를 붙일 파트 탐색 (스트리밍 대응)
local function _waitForTrainerRootPart()
	-- NPC 폴더와 Trainer 모델 대기
	local npcFolder = workspace:WaitForChild("NPC", 30)
	if not npcFolder then
		warn("[TrainerController] workspace.NPC 폴더 없음")
		return nil
	end

	local trainer = npcFolder:WaitForChild("Trainer", 30)
	if not trainer then
		warn("[TrainerController] workspace.NPC.Trainer 없음")
		return nil
	end

	-- Head, HumanoidRootPart가 스트리밍으로 늦게 로드될 수 있으므로 WaitForChild 사용
	local head = trainer:WaitForChild("Head", 15)
	if head then
		print("[TrainerController] Head 파트 발견:", head:GetFullName())
		return head
	end

	local hrp = trainer:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		print("[TrainerController] HumanoidRootPart 발견:", hrp:GetFullName())
		return hrp
	end

	warn("[TrainerController] Head/HumanoidRootPart 로드 타임아웃. 자손에서 BasePart 탐색...")
	for _, d in ipairs(trainer:GetDescendants()) do
		if d:IsA("BasePart") then
			print("[TrainerController] 대체 파트:", d:GetFullName())
			return d
		end
	end

	warn("[TrainerController] BasePart를 찾지 못했습니다.")
	return nil
end

local function _buildIndicatorGui(rootPart, state)
	-- 기존 인디케이터 제거
	if indicatorGui then
		indicatorGui:Destroy()
		indicatorGui = nil
	end
	if state == "NONE" then
		print("[TrainerController] 인디케이터 상태 NONE → 제거")
		return
	end
	if not rootPart then
		warn("[TrainerController] rootPart 없음 → 인디케이터 생성 불가")
		return
	end

	print("[TrainerController] 인디케이터 생성:", state, rootPart:GetFullName())

	local isAvailable = (state == "AVAILABLE")

	local playerGui = player:WaitForChild("PlayerGui")

	local bb = Instance.new("BillboardGui")
	bb.Name = "TrainerQuestIndicator"
	bb.Size = UDim2.new(0, 36, 0, 58)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 100
	bb.ResetOnSpawn = false
	bb.Adornee = rootPart
	bb.Parent = playerGui

	-- 그림자 레이어 (아래쪽 진한 색)
	local shadow = Instance.new("TextLabel")
	shadow.Size = UDim2.new(1, 0, 1, 0)
	shadow.Position = UDim2.new(0, 2, 0, 3)
	shadow.BackgroundTransparency = 1
	shadow.Text = isAvailable and "!" or "?"
	shadow.Font = Enum.Font.GothamBold
	shadow.TextSize = 52
	shadow.TextColor3 = isAvailable and Color3.fromRGB(120, 50, 0) or Color3.fromRGB(20, 60, 140)
	shadow.TextTransparency = 0.3
	shadow.TextXAlignment = Enum.TextXAlignment.Center
	shadow.TextYAlignment = Enum.TextYAlignment.Center
	shadow.ZIndex = 1
	shadow.Parent = bb

	-- 메인 텍스트 (밝은 황금/파랑)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = isAvailable and "!" or "?"
	label.Font = Enum.Font.GothamBold
	label.TextSize = 52
	label.TextColor3 = isAvailable and Color3.fromRGB(255, 190, 30) or Color3.fromRGB(100, 200, 255)
	label.TextStrokeColor3 = isAvailable and Color3.fromRGB(160, 80, 0) or Color3.fromRGB(30, 80, 180)
	label.TextStrokeTransparency = 0.0
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 2
	label.Parent = bb


	-- 위아래 바운스 애니메이션
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

-- 상태 설정 진입점: NPC가 아직 없으면 로드될 때까지 대기
local function setIndicator(state)
	pendingState = state

	task.spawn(function()
		local rootPart = _waitForTrainerRootPart()
		-- 대기 중에 상태가 바뀌었으면 최신 상태 사용
		_buildIndicatorGui(rootPart, pendingState)
	end)
end

local function showTrainerDialogue(data)
	local npcName   = data.npcName   or "훈련 교관"
	local dialogue  = data.dialogue  or ""
	local choices   = data.choices   or {}

	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("TrainerDialogueSG")
	if existing then existing:Destroy() end

	local UIS = game:GetService("UserInputService")
	local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

	local sg = Instance.new("ScreenGui")
	sg.Name           = "TrainerDialogueSG"
	sg.ResetOnSpawn   = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder   = 200
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	-- 메인 박스: 가로 폭 제한, 하단 중앙, 세로 자동 확장
	local BOX_W = isMobile and UDim2.new(0.96, 0, 0, 0) or UDim2.new(0, 740, 0, 0)
	local dialogueBox = Instance.new("Frame")
	dialogueBox.Size                  = BOX_W
	dialogueBox.AnchorPoint           = Vector2.new(0.5, 1)
	dialogueBox.Position              = UDim2.new(0.5, 0, 1, -8)
	dialogueBox.AutomaticSize         = Enum.AutomaticSize.Y
	dialogueBox.BackgroundColor3      = Color3.fromRGB(8, 12, 22)
	dialogueBox.BackgroundTransparency = 0.08
	dialogueBox.BorderSizePixel       = 0
	dialogueBox.Parent                = sg
	Instance.new("UICorner", dialogueBox).CornerRadius = UDim.new(0, 6)

	-- 상단 파랑 라인
	local topLine = Instance.new("Frame")
	topLine.Size             = UDim2.new(1, 0, 0, 2)
	topLine.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
	topLine.BorderSizePixel  = 0
	topLine.Parent           = dialogueBox
	Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 2)

	-- NPC 이름 플레이트
	local namePlate = Instance.new("Frame")
	namePlate.Size             = UDim2.new(0, 0, 0, 30)
	namePlate.Position         = UDim2.new(0, 18, 0, -16)
	namePlate.AutomaticSize    = Enum.AutomaticSize.X
	namePlate.BackgroundColor3 = Color3.fromRGB(20, 40, 90)
	namePlate.BorderSizePixel  = 0
	namePlate.ZIndex           = 2
	namePlate.Parent           = dialogueBox
	Instance.new("UICorner", namePlate).CornerRadius = UDim.new(0, 4)
	local npStroke = Instance.new("UIStroke", namePlate)
	npStroke.Color = Color3.fromRGB(100, 150, 255); npStroke.Thickness = 1.5

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.new(0, 0, 1, 0)
	nameLabel.AutomaticSize          = Enum.AutomaticSize.X
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = "  " .. npcName .. "  "
	nameLabel.Font                   = F.TITLE
	nameLabel.TextSize               = 14
	nameLabel.TextColor3             = Color3.fromRGB(180, 210, 255)
	nameLabel.ZIndex                 = 3
	nameLabel.Parent                 = namePlate

	-- 내부 레이아웃: 텍스트 → 구분선 → 선택지
	local content = Instance.new("Frame")
	content.Size                  = UDim2.new(1, -32, 0, 0)
	content.Position              = UDim2.new(0, 16, 0, 14)
	content.AutomaticSize         = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent                = dialogueBox
	local contentLayout = Instance.new("UIListLayout", content)
	contentLayout.SortOrder          = Enum.SortOrder.LayoutOrder
	contentLayout.Padding            = UDim.new(0, 0)
	contentLayout.FillDirection      = Enum.FillDirection.Vertical
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- 대화 텍스트
	local textLabel = Instance.new("TextLabel")
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
	textPad.PaddingTop = UDim.new(0, 10); textPad.PaddingBottom = UDim.new(0, 10)

	-- 구분선
	local divider = Instance.new("Frame")
	divider.Size             = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(40, 55, 100)
	divider.BorderSizePixel  = 0
	divider.LayoutOrder      = 2
	divider.Visible          = false
	divider.Parent           = content

	-- 선택지 컨테이너
	local choiceFrame = Instance.new("Frame")
	choiceFrame.Size                  = UDim2.new(1, 0, 0, 0)
	choiceFrame.AutomaticSize         = Enum.AutomaticSize.Y
	choiceFrame.BackgroundTransparency = 1
	choiceFrame.LayoutOrder           = 3
	choiceFrame.Parent                = content
	local choiceLayout = Instance.new("UIListLayout", choiceFrame)
	choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	choiceLayout.Padding   = UDim.new(0, 4)
	local choicePad = Instance.new("UIPadding", choiceFrame)
	choicePad.PaddingTop = UDim.new(0, 8); choicePad.PaddingBottom = UDim.new(0, 10)

	local function closeDialogue()
		sg:Destroy()
	end

	local function makeChoiceBtn(text, layoutOrder, color, fn)
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, 0, 0, isMobile and 36 or 30)
		btn.BackgroundColor3 = Color3.fromRGB(18, 28, 55)
		btn.BorderSizePixel  = 0
		btn.Text             = "▶  " .. text
		btn.Font             = F.NORMAL
		btn.TextSize         = isMobile and 13 or 14
		btn.TextColor3       = color or Color3.fromRGB(200, 220, 255)
		btn.TextXAlignment   = Enum.TextXAlignment.Left
		btn.RichText         = false
		btn.LayoutOrder      = layoutOrder
		btn.ZIndex           = 2
		btn.Parent           = choiceFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		local pad = Instance.new("UIPadding", btn); pad.PaddingLeft = UDim.new(0, 10)
		btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(30, 50, 100) end)
		btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(18, 28, 55) end)
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
			local color = isAction and Color3.fromRGB(150, 210, 255) or Color3.fromRGB(160, 160, 160)
			makeChoiceBtn(choice.text, idx, color, function()
				if choice.action == "CLOSE" then
					closeDialogue()
				elseif choice.action == "ACCEPT" or choice.action == "CLAIM" then
					closeDialogue()
					task.spawn(function()
						local ok, _ = NetClient.Request("Trainer.QuestAction.Request", {
							action  = choice.action,
							questId = choice.questId,
						})
						if not ok then
							warn("[TrainerController] Quest action failed:", choice.action)
						end
					end)
				end
			end)
		end
	end

	-- 텍스트 클릭 시 타이핑 스킵
	local boxBtn = Instance.new("TextButton")
	boxBtn.Size                 = UDim2.new(1, 0, 0, 80)
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

-- 퀘스트 트래커 → HUDUI 통합 패널에 위임 (겹침 방지)
local TRAINER_QUEST_SLOT = 100  -- 사이드퀘스트 ID (튜토리얼 등과 구별)

local function showQuestTracker(data)
	UIManager.updateSideQuest(TRAINER_QUEST_SLOT, data)
end

function TrainerController.Init()
	if initialized then return end
	initialized = true

	-- 서버에서 대화 오픈 이벤트 수신
	NetClient.On("Trainer.OpenDialogue", function(data)
		showTrainerDialogue(data)
	end)

	-- 퀘스트 인디케이터 상태 수신 (NPC 머리 위 ! / ?)
	NetClient.On("Trainer.SetIndicator", function(data)
		local state = data and data.state or "NONE"
		setIndicator(state)
	end)

	-- 퀘스트 트래커 수신 (화면 우측 진행 패널)
	NetClient.On("Trainer.QuestTracker", function(data)
		showQuestTracker(data)
	end)

	-- 클라이언트 초기화 시 서버에 현재 인디케이터 상태 요청
	-- (PlayerAdded에서 서버가 먼저 쏜 이벤트를 클라이언트가 못 받은 경우 복구)
	task.spawn(function()
		task.wait(5)  -- 서버 SaveService 로드(~4s) 완료 후 요청
		local success, data = NetClient.Request("Trainer.GetIndicator.Request", {})
		if success and type(data) == "table" and data.state then
			print("[TrainerController] GetIndicator 응답:", data.state)
			setIndicator(data.state)
		end
	end)

	print("[TrainerController] Initialized.")
end

return TrainerController
