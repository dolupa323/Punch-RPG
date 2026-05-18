-- ClientInit.client.lua
-- 클라이언트 초기화 스크립트 (Clean RPG Architecture)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")
local SkillController = require(Controllers.SkillController)
local WorldDropController = require(Controllers.WorldDropController)

local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UIManager = require(Client.UIManager)
local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local player = Players.LocalPlayer

--========================================
-- 어드민 패널 (개발/테스트용)
--========================================
local function createAdminPanel()
	local function checkIsAdmin(userId)
		return RunService:IsStudio() or Balance.ADMIN_IDS[userId] == true
	end

	if not checkIsAdmin(player.UserId) then
		return
	end

	-- 카메라 줌 설정
	player.CameraMaxZoomDistance = 1000 
	player.CameraMinZoomDistance = Balance.CAM_MIN_ZOOM or 0.5
	
	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:FindFirstChild("AdminPanelUI") then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminPanelUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.Parent = playerGui

	local frame = Instance.new("ScrollingFrame")
	frame.Name = "AdminPanel"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -50, 0, 80)
	frame.Size = UDim2.new(0, 220, 0, 300)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	frame.BackgroundTransparency = 0.2
	frame.Visible = false
	frame.Parent = gui
	
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(185, 155, 80)
	stroke.Thickness = 1.5

	local list = Instance.new("UIListLayout", frame)
	list.Padding = UDim.new(0, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local pad = Instance.new("UIPadding", frame)
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "AdminToggle"
	toggleBtn.Size = UDim2.new(0, 40, 0, 40)
	toggleBtn.Position = UDim2.new(1, -5, 0, 80)
	toggleBtn.AnchorPoint = Vector2.new(1, 0)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	toggleBtn.Text = "ADM"
	toggleBtn.TextColor3 = Color3.fromRGB(255, 220, 120)
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.Parent = gui
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

	toggleBtn.MouseButton1Click:Connect(function()
		frame.Visible = not frame.Visible
	end)

	local function mkBtn(text, color, fn)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 32)
		btn.BackgroundColor3 = color
		btn.Text = text
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.Parent = frame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		btn.MouseButton1Click:Connect(fn)
		return btn
	end

	mkBtn("골드 +5000", Color3.fromRGB(185, 155, 80), function()
		NetClient.Request("Shop.Admin.GrantGold.Request", { amount = 5000 })
	end)

	mkBtn("레벨 50 설정", Color3.fromRGB(100, 120, 180), function()
		NetClient.Request("Admin.SetLevel.Request", { level = 50 })
	end)

	mkBtn("완전 초기화 (!)", Color3.fromRGB(180, 60, 60), function()
		-- 마케팅/테스트용 초기화 로직 (필요 시 구현)
		UIManager.notify("초기화 요청됨", Color3.new(1, 1, 1))
	end)
end

--========================================
-- 메인 초기화 루틴
--========================================
local function init()
	-- Network 초기화 (RemoteFunction/Event 바인딩)
	NetClient.Init()

	-- [All Controllers Auto-Initialization]
	-- Controllers 디렉토리 내의 모든 모듈 중 Init() 함수가 구현된 대상을 자동 감지하여 일제히 안전(pcall) 기동
	-- 이를 통해 Inventory, Craft, Shop, Interact 등 누락되어 있던 핵심 비동기 통신 시스템들을 완벽히 활성화합니다.
	for _, child in ipairs(Controllers:GetChildren()) do
		if child:IsA("ModuleScript") then
			local success, controller = pcall(require, child)
			if success and type(controller) == "table" and type(controller.Init) == "function" then
				local ok, err = pcall(function() controller.Init() end)
				if not ok then
					warn(string.format("[ClientInit] Failed to initialize controller '%s': %s", child.Name, tostring(err)))
				else
					print(string.format("[ClientInit] Controller '%s' auto-initialized successfully.", child.Name))
				end
			end
		end
	end

	-- UIManager 초기화 (HUD, 인벤토리 등 UI 생성)
	UIManager.Init()
	
	-- 어드민 패널 생성
	createAdminPanel()

	print("[ClientInit] Client successfully initialized in RPG mode.")
end

-- 실행
task.spawn(init)
