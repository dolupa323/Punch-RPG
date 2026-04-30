-- TutorialUI.lua
-- 튜토리얼 메시지 및 UI 강조(Blink) 연출 모듈

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialUI = {}
local guideLabel = nil
local activeBlinks = {}

--========================================
-- Private Helpers
--========================================

local function createGuideUI()
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialGuideGui"
	screen.DisplayOrder = 9999 -- 최상단 출력
	screen.ResetOnSpawn = false
	screen.Parent = playerGui
	
	local frame = Instance.new("CanvasGroup")
	frame.Name = "MessageFrame"
	frame.Size = UDim2.new(0.6, 0, 0, 80)
	frame.Position = UDim2.new(0.5, 0, 0.85, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Visible = false -- 시작 전에는 숨김
	frame.Parent = screen
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	
	guideLabel = Instance.new("TextLabel")
	guideLabel.Name = "GuideLabel"
	guideLabel.Size = UDim2.new(0.95, 0, 0.8, 0)
	guideLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	guideLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	guideLabel.BackgroundTransparency = 1
	guideLabel.Font = Enum.Font.GothamBold
	guideLabel.TextSize = 22
	guideLabel.TextColor3 = Color3.new(1, 1, 1)
	guideLabel.Text = ""
	guideLabel.TextWrapped = true
	guideLabel.Parent = frame
	
	return screen
end

function TutorialUI.Init(mainGui, isMobile)
	if not guideLabel then createGuideUI() end
end

function TutorialUI.SetMessage(text)
	if not guideLabel then createGuideUI() end
	guideLabel.Text = text
	
	local frame = guideLabel.Parent
	if text == "" then
		frame.Visible = false
	else
		frame.Visible = true
		-- 나타나기 애니메이션
		frame.GroupTransparency = 1
		TweenService:Create(frame, TweenInfo.new(0.3), {GroupTransparency = 0}):Play()
	end
end

function TutorialUI.BlinkElement(element)
	if not element or activeBlinks[element] then return end
	
	-- 강조용 오버레이 생성 (원본 UI를 직접 건드리지 않고 위에 덧씌움)
	local highlight = Instance.new("Frame")
	highlight.Name = "TutorialHighlight"
	highlight.Size = UDim2.new(1.1, 0, 1.1, 0)
	highlight.Position = UDim2.new(0.5, 0, 0.5, 0)
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.BackgroundColor3 = Color3.fromRGB(255, 255, 0) -- 밝은 노란색
	highlight.BackgroundTransparency = 0.5
	highlight.ZIndex = element.ZIndex + 10
	highlight.Parent = element
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = highlight
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 3
	stroke.Parent = highlight

	local info = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(highlight, info, {
		BackgroundTransparency = 0.9,
		Size = UDim2.new(1.3, 0, 1.3, 0)
	})
	tween:Play()
	
	activeBlinks[element] = {
		highlight = highlight,
		tween = tween
	}
end

local focusElement = nil

function TutorialUI.SetFocusElement(element)
	if focusElement == element then return end
	
	TutorialUI.StopAllBlinks()
	focusElement = element
	
	if element then
		TutorialUI.BlinkElement(element)
	end
end

function TutorialUI.StopAllBlinks()
	for element, data in pairs(activeBlinks) do
		if data.tween then data.tween:Cancel() end
		if data.highlight then data.highlight:Destroy() end
	end
	activeBlinks = {}
	focusElement = nil
end

return TutorialUI
