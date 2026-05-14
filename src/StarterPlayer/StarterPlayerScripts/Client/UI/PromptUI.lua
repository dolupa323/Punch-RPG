-- PromptUI.lua
-- 커스텀 ProximityPrompt UI (투명 유리 스타일)

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)

-- Local Color Override for Navy + Black Theme (Match Equipment/Inventory)
local C_Base = Theme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(15, 20, 30) -- Deep Navy/Black
C.BG_DARK = Color3.fromRGB(5, 5, 10)
C.BG_SLOT = Color3.fromRGB(240, 240, 245) -- Key Icon White
C.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(40, 60, 90)

local F = Theme.Fonts
local T = Theme.Transp

local PromptUI = {}
local initialized = false

local function createPromptUI(prompt, inputType, gui)
	local frame = Utils.mkFrame({
		name = "PromptFrame",
		size = UDim2.new(0, 220, 0, 56),
		bg = C.BG_PANEL,
		bgT = 0.15, -- More solid like the screenshot
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER_DIM,
		useCanvas = true,
		parent = gui
	})
	
	-- 입력키 아이콘
	local inputIcon = Instance.new("Frame")
	inputIcon.Size = UDim2.new(0, 36, 0, 36)
	inputIcon.Position = UDim2.new(0, 10, 0.5, 0)
	inputIcon.AnchorPoint = Vector2.new(0, 0.5)
	inputIcon.BackgroundColor3 = C.BG_SLOT -- White background for key
	inputIcon.BackgroundTransparency = 0
	inputIcon.Parent = frame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = inputIcon
	
	local keyText = Utils.mkLabel({
		text = prompt.KeyboardKeyCode.Name,
		ts = 18,
		font = F.TITLE,
		color = Color3.fromRGB(30, 30, 40), -- Dark text on white key
		parent = inputIcon
	})
	
	-- 텍스트 내용
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -52, 1, 0)
	content.Position = UDim2.new(0, 47, 0, 0)
	content.BackgroundTransparency = 1
	content.Parent = frame
	
	local objLabel = Utils.mkLabel({
		text = UILocalizer.Localize(prompt.ObjectText),
		ts = 13,
		pos = UDim2.new(0, 0, 0.3, 0),
		anchor = Vector2.new(0, 0.5),
		ax = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(180, 190, 210), -- Muted blue/gray
		parent = content
	})
	
	local actLabel = Utils.mkLabel({
		text = UILocalizer.Localize(prompt.ActionText),
		ts = 18,
		font = F.TITLE,
		pos = UDim2.new(0, 0, 0.7, 0),
		anchor = Vector2.new(0, 0.5),
		ax = Enum.TextXAlignment.Left,
		color = C.WHITE,
		parent = content
	})
	
	-- 가독성을 위한 크기 자동 조정
	local function updateSize()
		local textWidth = math.max(objLabel.TextBounds.X, actLabel.TextBounds.X)
		frame.Size = UDim2.new(0, textWidth + 70, 0, 50)
	end

	local function refreshLocalizedPromptText()
		objLabel.Text = UILocalizer.Localize(prompt.ObjectText)
		actLabel.Text = UILocalizer.Localize(prompt.ActionText)
		updateSize()
	end
	updateSize()

	prompt:GetPropertyChangedSignal("ObjectText"):Connect(refreshLocalizedPromptText)
	prompt:GetPropertyChangedSignal("ActionText"):Connect(refreshLocalizedPromptText)
	
	-- 진행률 (Hold 특성용)
	if prompt.HoldDuration > 0 then
		local progressBG = Instance.new("Frame")
		progressBG.Size = UDim2.new(1, 0, 0, 2)
		progressBG.Position = UDim2.new(0, 0, 1, 0)
		progressBG.AnchorPoint = Vector2.new(0, 1)
		progressBG.BackgroundColor3 = C.WHITE
		progressBG.BackgroundTransparency = 0.8
		progressBG.BorderSizePixel = 0
		progressBG.Parent = frame
		
		local progressFill = Instance.new("Frame")
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = C.GOLD or Color3.fromRGB(255, 210, 60)
		progressFill.BorderSizePixel = 0
		progressFill.Parent = progressBG
		
		prompt.PromptButtonHoldBegan:Connect(function()
			TweenService:Create(progressFill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)}):Play()
		end)
		
		prompt.PromptButtonHoldEnded:Connect(function()
			TweenService:Create(progressFill, TweenInfo.new(0.2), {Size = UDim2.new(0, 0, 1, 0)}):Play()
		end)
	end
	
	return frame
end

function PromptUI.Init()
	if initialized then return end
	initialized = true

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
		
		local gui = Instance.new("BillboardGui")
		gui.Name = "PromptGui"
		gui.AlwaysOnTop = true
		gui.Size = UDim2.new(0, 250, 0, 80)
		gui.SizeOffset = Vector2.new(0, 0.2) -- 아이템에 아주 가깝게 더 조정 (0.5 -> 0.2)
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui.Adornee = prompt.Parent
		
		local frame = createPromptUI(prompt, inputType, gui)
		
		-- 애니메이션
		frame.GroupTransparency = 1
		TweenService:Create(frame, TweenInfo.new(0.2), {GroupTransparency = 0}):Play()
		
		local conn
		conn = prompt.PromptHidden:Connect(function()
			conn:Disconnect()
			gui:Destroy()
		end)
	end)
end

return PromptUI
