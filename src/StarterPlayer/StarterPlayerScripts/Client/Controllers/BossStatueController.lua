-- BossStatueController.lua
-- LevelArt/start/Boss 석상 상호작용 및 대화 UI 컨트롤러

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UITheme = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local Utils = require(Client:WaitForChild("UI"):WaitForChild("UIUtils"))

local BossStatueController = {}
local initialized = false
local player = Players.LocalPlayer

-- UI Refs
local dialogueGui = nil
local dialogueFrame = nil
local contentLabel = nil
local closeConnection = nil

-- Local Color Style (Navy Glassmorphism matching RPG HUD)
local BG_COLOR = Color3.fromRGB(15, 20, 30)
local BORDER_COLOR = Color3.fromRGB(60, 85, 130)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local GOLD_COLOR = Color3.fromRGB(255, 220, 120)
local HINT_COLOR = Color3.fromRGB(150, 170, 200)

-- Responsive size calculation
local function updateLayout()
	if not dialogueFrame then return end
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
	
	if vp.X < 800 then
		-- Mobile layout
		dialogueFrame.Size = UDim2.new(0.9, 0, 0, 110)
		dialogueFrame.Position = UDim2.new(0.5, 0, 0.95, -10)
	else
		-- PC layout
		dialogueFrame.Size = UDim2.new(0, 500, 0, 130)
		dialogueFrame.Position = UDim2.new(0.5, 0, 0.88, -20)
	end
end

-- Create Dialogue UI
local function ensureDialogueUI()
	if dialogueGui and dialogueGui.Parent then return end
	
	local playerGui = player:WaitForChild("PlayerGui")
	dialogueGui = Instance.new("ScreenGui")
	dialogueGui.Name = "BossStatueDialogueGui"
	dialogueGui.ResetOnSpawn = false
	dialogueGui.IgnoreGuiInset = true
	dialogueGui.DisplayOrder = 15000
	dialogueGui.Enabled = false
	dialogueGui.Parent = playerGui
	
	-- Fullscreen click catcher to close dialog
	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "ClickCatcher"
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.Text = ""
	clickCatcher.Parent = dialogueGui
	clickCatcher.MouseButton1Click:Connect(function()
		BossStatueController.CloseDialogue()
	end)
	
	-- Dialogue Panel Frame
	dialogueFrame = Instance.new("CanvasGroup")
	dialogueFrame.Name = "DialogueFrame"
	dialogueFrame.AnchorPoint = Vector2.new(0.5, 1)
	dialogueFrame.BackgroundColor3 = BG_COLOR
	dialogueFrame.BackgroundTransparency = 0.2
	dialogueFrame.BorderSizePixel = 0
	dialogueFrame.Visible = false
	dialogueFrame.Parent = dialogueGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = dialogueFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER_COLOR
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = dialogueFrame
	
	-- Speaker Name
	local speakerLabel = Instance.new("TextLabel")
	speakerLabel.Name = "SpeakerLabel"
	speakerLabel.Size = UDim2.new(1, -40, 0, 30)
	speakerLabel.Position = UDim2.new(0, 20, 0, 12)
	speakerLabel.BackgroundTransparency = 1
	speakerLabel.Text = "석상"
	speakerLabel.TextColor3 = GOLD_COLOR
	speakerLabel.Font = Enum.Font.GothamBold
	speakerLabel.TextSize = 18
	speakerLabel.TextXAlignment = Enum.TextXAlignment.Left
	speakerLabel.Parent = dialogueFrame
	
	-- Dialogue Content Text
	contentLabel = Instance.new("TextLabel")
	contentLabel.Name = "ContentLabel"
	contentLabel.Size = UDim2.new(1, -40, 0, 50)
	contentLabel.Position = UDim2.new(0, 20, 0, 42)
	contentLabel.BackgroundTransparency = 1
	contentLabel.Text = ""
	contentLabel.TextColor3 = TEXT_COLOR
	contentLabel.Font = Enum.Font.Gotham
	contentLabel.TextSize = 17
	contentLabel.TextWrapped = true
	contentLabel.TextXAlignment = Enum.TextXAlignment.Left
	contentLabel.TextYAlignment = Enum.TextYAlignment.Top
	contentLabel.Parent = dialogueFrame
	
	-- Close Hint
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "HintLabel"
	hintLabel.Size = UDim2.new(1, -40, 0, 20)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -18)
	hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Text = "클릭 또는 [R]키를 눌러 닫기"
	hintLabel.TextColor3 = HINT_COLOR
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = 12
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Parent = dialogueFrame
	
	updateLayout()
	
	-- Watch viewport changes
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
	end
end

-- Open Dialogue Window
function BossStatueController.ShowDialogue(text)
	ensureDialogueUI()
	
	dialogueGui.Enabled = true
	contentLabel.Text = text
	dialogueFrame.Visible = true
	
	-- Slide-up & Fade-in animation
	dialogueFrame.GroupTransparency = 1
	local origPos = dialogueFrame.Position
	dialogueFrame.Position = origPos + UDim2.new(0, 0, 0, 20)
	
	TweenService:Create(dialogueFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = origPos
	}):Play()
	
	-- Bind input to close
	if closeConnection then
		closeConnection:Disconnect()
	end
	
	closeConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
			BossStatueController.CloseDialogue()
		end
	end)
end

-- Close Dialogue Window
function BossStatueController.CloseDialogue()
	if closeConnection then
		closeConnection:Disconnect()
		closeConnection = nil
	end
	
	if dialogueFrame and dialogueFrame.Visible then
		local origPos = dialogueFrame.Position
		local fade = TweenService:Create(dialogueFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
			Position = origPos + UDim2.new(0, 0, 0, 15)
		})
		fade:Play()
		fade.Completed:Connect(function()
			dialogueFrame.Visible = false
			dialogueFrame.Position = origPos -- Restore position
			if dialogueGui then
				dialogueGui.Enabled = false
			end
		end)
	else
		if dialogueGui then
			dialogueGui.Enabled = false
		end
	end
end

-- Setup Statue Interaction
local function setupStatue(bossModel: Instance)
	print("[BossStatueController] Setting up statue interaction for: " .. bossModel:GetFullName())
	
	-- Wait for the pedestal part (Base2) to stream in/load (usually holds the base of the statue)
	local base2 = bossModel:WaitForChild("Base2", 8)
	
	local lowestY = math.huge
	if base2 and base2:IsA("BasePart") then
		lowestY = base2.Position.Y - (base2.Size.Y / 2)
	else
		-- Fallback to scanning all currently loaded parts if Base2 is missing
		for _, desc in ipairs(bossModel:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name ~= "StatueInteractPart" then
				local partBottomY = desc.Position.Y - (desc.Size.Y / 2)
				if partBottomY < lowestY then
					lowestY = partBottomY
				end
			end
		end
	end
	
	-- Secondary Raycast fallback check to ensure it doesn't float
	local cf = bossModel:GetPivot()
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = {bossModel}
	if player.Character then
		table.insert(excludeList, player.Character)
	end
	raycastParams.FilterDescendantsInstances = excludeList
	
	local rayOrigin = Vector3.new(cf.Position.X, cf.Position.Y, cf.Position.Z)
	local rayDirection = Vector3.new(0, -150, 0)
	
	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if raycastResult then
		-- Use the lower of either the pedestal bottom or raycasted ground level
		local rayY = raycastResult.Position.Y
		if lowestY == math.huge or rayY < lowestY then
			lowestY = rayY
		end
	elseif lowestY == math.huge then
		lowestY = cf.Position.Y
	end
	
	-- Place the interaction part exactly at the bottom Y level (offset slightly to rest on pedestal/ground surface)
	local bottomPos = Vector3.new(cf.Position.X, lowestY + 0.1, cf.Position.Z)
	
	-- Create an invisible interact part at the bottom
	local interactPart = bossModel:FindFirstChild("StatueInteractPart")
	if not interactPart then
		interactPart = Instance.new("Part")
		interactPart.Name = "StatueInteractPart"
		interactPart.Size = Vector3.new(6, 0.4, 6) -- Thin flat footprint close to the ground
		interactPart.CFrame = CFrame.new(bottomPos)
		interactPart.Transparency = 1
		interactPart.CanCollide = false
		interactPart.Anchored = true
		interactPart.Parent = bossModel
	else
		interactPart.Size = Vector3.new(6, 0.4, 6)
		interactPart.CFrame = CFrame.new(bottomPos)
	end
	
	-- Create ProximityPrompt inside the interact part
	local prompt = interactPart:FindFirstChild("StatuePrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StatuePrompt"
		prompt.ActionText = "읽기"
		prompt.ObjectText = "석상"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = interactPart
		
		prompt.Triggered:Connect(function(playerTriggered)
			if playerTriggered == player then
				BossStatueController.ShowDialogue("가장 높은곳에 도달해보시게나... 라고 적혀있다")
			end
		end)
	end
end

-- Scan and wait for the model
local function findAndSetup()
	local levelArt = workspace:FindFirstChild("LevelArt")
	if levelArt then
		local startFolder = levelArt:FindFirstChild("start")
		if startFolder then
			local boss = startFolder:FindFirstChild("Boss")
			if boss then
				setupStatue(boss)
				return true
			end
		end
	end
	return false
end

function BossStatueController.Init()
	if initialized then return end
	initialized = true
	
	-- Initial scan
	task.spawn(function()
		local attempts = 0
		while attempts < 100 do
			if findAndSetup() then
				break
			end
			attempts = attempts + 1
			task.wait(1)
		end
	end)
	
	-- Listen for descendant changes to handle StreamingEnabled loading
	workspace.DescendantAdded:Connect(function(desc)
		if desc.Name == "Boss" then
			task.defer(function()
				if desc.Parent and desc.Parent.Name == "start" and desc.Parent.Parent and desc.Parent.Parent.Name == "LevelArt" then
					setupStatue(desc)
				end
			end)
		end
	end)
	
	print("[BossStatueController] Initialized successfully")
end

return BossStatueController
