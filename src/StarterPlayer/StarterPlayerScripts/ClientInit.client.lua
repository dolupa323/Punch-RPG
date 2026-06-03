-- ClientInit.client.lua
-- 클라이언트 초기화 스크립트 (Clean RPG Architecture)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")
local SkillController = require(Controllers:WaitForChild("SkillController"))
local WorldDropController = require(Controllers:WaitForChild("WorldDropController"))

local NetClient = require(Client:WaitForChild("NetClient"))
local InputManager = require(Client:WaitForChild("InputManager"))
local UIManager = require(Client:WaitForChild("UIManager"))
local PremiumShopUI = require(Client:WaitForChild("UI"):WaitForChild("PremiumShopUI"))
local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))
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
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
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

	local function refreshPremiumShopIfOpen()
		if PremiumShopUI and PremiumShopUI.Refs and PremiumShopUI.Refs.Frame and PremiumShopUI.Refs.Frame.Visible then
			PremiumShopUI.Refresh(UIManager.getItemIcon)
		end
	end

	mkBtn("골드 +50만", Color3.fromRGB(185, 155, 80), function()
		NetClient.Request("Shop.Admin.GrantGold.Request", { amount = 500000 })
	end)

	mkBtn("패스 적용", Color3.fromRGB(90, 140, 220), function()
		local ok, data = NetClient.Request("GamePass.DebugForceApply.Request", { gamePassId = 1864732763 })
		if ok then
			UIManager.notify("드랍률 2배 패스를 강제 적용했습니다.", Color3.fromRGB(120, 190, 255))
			refreshPremiumShopIfOpen()
		else
			UIManager.notify("패스 적용에 실패했습니다.", Color3.fromRGB(255, 120, 120))
		end
	end)

	mkBtn("패스 기능해제", Color3.fromRGB(80, 80, 95), function()
		local ok, data = NetClient.Request("GamePass.DebugForceDisable.Request", { gamePassId = 1864732763 })
		if ok then
			UIManager.notify("드랍률 2배 패스를 해제했습니다.", Color3.fromRGB(180, 180, 200))
			refreshPremiumShopIfOpen()
		else
			UIManager.notify("패스 해제에 실패했습니다.", Color3.fromRGB(255, 120, 120))
		end
	end)

	mkBtn("튜토리얼 초기화", Color3.fromRGB(85, 115, 180), function()
		local ok, data = NetClient.Request("Tutorial.Admin.Reset.Request", {})
		if ok and data then
			UIManager.updateTutorialStatus(data)
			UIManager.notify("튜토리얼 진행 단계를 초기화했습니다.", Color3.fromRGB(150, 190, 255))
		else
			UIManager.notify("튜토리얼 초기화에 실패했습니다.", Color3.fromRGB(255, 120, 120))
		end
	end)

	mkBtn("기사의 혼 +100", Color3.fromRGB(100, 150, 200), function()
		NetClient.Request("Admin.GiveItem.Request", { itemId = "GHOST_KNIGHT_SOUL", count = 100 })
	end)

	mkBtn("마법사의 혼 +100", Color3.fromRGB(150, 100, 200), function()
		NetClient.Request("Admin.GiveItem.Request", { itemId = "GHOST_WIZARD_SOUL", count = 100 })
	end)

	mkBtn("기사의 긍지 +100", Color3.fromRGB(200, 150, 100), function()
		NetClient.Request("Admin.GiveItem.Request", { itemId = "GHOST_GIANT_PRIDE", count = 100 })
	end)

	mkBtn("푸른 화염 +100", Color3.fromRGB(80, 180, 220), function()
		NetClient.Request("Admin.GiveItem.Request", { itemId = "BLUE_FIRE", count = 100 })
	end)


	mkBtn("레벨 50 설정", Color3.fromRGB(100, 120, 180), function()
		NetClient.Request("Admin.SetLevel.Request", { level = 50 })
	end)
	
	mkBtn("속성: 불(Fire)", Color3.fromRGB(200, 80, 80), function()
		NetClient.Request("Admin.SetElement.Request", { element = "Fire" })
		UIManager.notify("불(Fire) 속성으로 변경 요청", Color3.new(1, 0.5, 0.5))
	end)
	
	mkBtn("속성: 물(Water)", Color3.fromRGB(80, 120, 200), function()
		NetClient.Request("Admin.SetElement.Request", { element = "Water" })
		UIManager.notify("물(Water) 속성으로 변경 요청", Color3.new(0.5, 0.7, 1))
	end)
	
	mkBtn("속성: 어둠(Dark)", Color3.fromRGB(138, 43, 226), function()
		NetClient.Request("Admin.SetElement.Request", { element = "Dark" })
		UIManager.notify("어둠(Dark) 속성으로 변경 요청", Color3.new(0.6, 0.2, 0.8))
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
					-- print(string.format("[ClientInit] Controller '%s' auto-initialized successfully.", child.Name))
				end
			end
		end
	end

	-- UIManager 초기화 (HUD, 인벤토리 등 UI 생성)
	UIManager.Init()
	
	-- 기본 카메라 줌아웃 한계 설정 (전체 유저 공통 적용)
	player.CameraMaxZoomDistance = Balance.CAM_MAX_ZOOM or 45
	player.CameraMinZoomDistance = Balance.CAM_MIN_ZOOM or 0.5
	
	-- 어드민 패널 생성
	createAdminPanel()

	print("[ClientInit] Client successfully initialized in RPG mode.")
end

-- 실행
task.spawn(init)
