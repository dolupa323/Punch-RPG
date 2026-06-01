-- TentUI.lua
-- 텐트 스폰 지정 확인 모달창

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Client = script.Parent.Parent
local NetClient = require(Client:WaitForChild("NetClient"))
local InputManager = require(Client:WaitForChild("InputManager"))
local UITheme = require(Client:WaitForChild("UI"):WaitForChild("UITheme"))
local Utils = require(Client:WaitForChild("UI"):WaitForChild("UIUtils"))
local WindowManager = require(Client:WaitForChild("Utils"):WaitForChild("WindowManager"))

local C_Base = UITheme.Colors
local C = {}
for k, v in pairs(C_Base) do C[k] = v end
C.BG_PANEL = Color3.fromRGB(10, 15, 25) -- Navy
C.BG_DARK = Color3.fromRGB(5, 5, 10)    -- Black
C.BG_SLOT = Color3.fromRGB(12, 12, 15) -- Near Black
C.GOLD = Color3.fromRGB(255, 255, 255)  -- Text White
C.GOLD_SEL = Color3.fromRGB(40, 80, 160) -- Accent Blue
C.BORDER = Color3.fromRGB(60, 85, 130)   -- Light Navy
C.BORDER_DIM = Color3.fromRGB(30, 45, 70)
C.BTN = Color3.fromRGB(40, 80, 160)      -- Action Buttons -> Navy

local F = UITheme.Fonts
local T = UITheme.Transp

local TentUI = {}

local UIManager = nil
local initialized = false
local isOpen = false
local screenGui = nil

TentUI.Refs = {
	Overlay = nil,
	Window = nil,
	BtnYes = nil,
	BtnNo = nil
}

function TentUI.Init(uiManager)
	if initialized then return end
	initialized = true
	UIManager = uiManager
	
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TentUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 150 -- 일반 창보다 위에
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local overlay = Utils.mkFrame({
		name = "Overlay", size = UDim2.fromScale(1, 1),
		bg = C.BG_OVERLAY, bgT = 1, parent = screenGui
	})
	TentUI.Refs.Overlay = overlay

	local win = Instance.new("CanvasGroup")
	win.Name = "Window"
	win.Size = UDim2.new(0, 360, 0, 180)
	win.Position = UDim2.fromScale(0.5, 0.5)
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.BackgroundColor3 = C.BG_PANEL
	win.BackgroundTransparency = T.PANEL
	win.Parent = overlay
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = win
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.BORDER
	stroke.Thickness = 1
	stroke.Parent = win
	
	TentUI.Refs.Window = win

	Utils.mkLabel({
		text = "스폰지점 설정",
		size = UDim2.new(1, 0, 0, 40), pos = UDim2.new(0, 0, 0, 10),
		font = F.TITLE, ts = 20, color = C.GOLD,
		parent = win
	})

	Utils.mkLabel({
		text = "이 텐트를 부활 지점으로 설정하시겠습니까?",
		size = UDim2.new(1, -40, 0, 60), pos = UDim2.new(0, 20, 0, 50),
		font = F.NORMAL, ts = 16, color = C.WHITE,
		parent = win
	})

	local btnArea = Utils.mkFrame({
		name = "BtnArea", size = UDim2.new(1, -40, 0, 45),
		pos = UDim2.new(0, 20, 1, -55), bgT = 1, parent = win
	})

	local btnNo = Utils.mkBtn({
		name = "BtnNo", text = "아니오", size = UDim2.new(0.48, 0, 1, 0),
		pos = UDim2.new(0, 0, 0, 0), bg = C.BTN_GRAY, font = F.TITLE, ts = 16,
		parent = btnArea
	})
	TentUI.Refs.BtnNo = btnNo

	local btnYes = Utils.mkBtn({
		name = "BtnYes", text = "예", size = UDim2.new(0.48, 0, 1, 0),
		pos = UDim2.new(0.52, 0, 0, 0), bg = C.BTN, font = F.TITLE, ts = 16, color = C.WHITE,
		parent = btnArea
	})
	TentUI.Refs.BtnYes = btnYes

	btnNo.MouseButton1Click:Connect(function()
		TentUI.Close()
	end)

	btnYes.MouseButton1Click:Connect(function()
		-- 스폰지점 설정 요청
		local ok, data = NetClient.Request("Tent.SetSpawn", {})
		if ok then
			if UIManager then UIManager.notify("스폰지점이 텐트로 설정되었습니다.", C.GREEN) end
		else
			if UIManager then UIManager.notify("스폰지점 설정에 실패했습니다.", C.RED) end
		end
		TentUI.Close()
	end)
end

function TentUI.Open()
	if not initialized then return end
	if isOpen then return end
	isOpen = true
	
	screenGui.Enabled = true
	InputManager.setUIOpen(true)
	
	-- 애니메이션
	TentUI.Refs.Overlay.BackgroundTransparency = 1
	TentUI.Refs.Window.Position = UDim2.new(0.5, 0, 0.5, 30)
	TentUI.Refs.Window.GroupTransparency = 1
	
	TweenService:Create(TentUI.Refs.Overlay, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
	TweenService:Create(TentUI.Refs.Window, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, 0),
		GroupTransparency = 0
	}):Play()
end

function TentUI.Close()
	if not isOpen then return end
	isOpen = false
	
	InputManager.setUIOpen(false)
	
	TweenService:Create(TentUI.Refs.Overlay, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
	local tw = TweenService:Create(TentUI.Refs.Window, TweenInfo.new(0.2), {
		Position = UDim2.new(0.5, 0, 0.5, 20),
		GroupTransparency = 1
	})
	tw:Play()
	
	tw.Completed:Connect(function()
		if not isOpen then
			screenGui.Enabled = false
			WindowManager.close("TENT_UI")
		end
	end)
end

function TentUI.IsOpen()
	return isOpen
end

return TentUI
