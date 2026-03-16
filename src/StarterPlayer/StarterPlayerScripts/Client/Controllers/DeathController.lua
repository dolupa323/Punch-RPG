-- DeathController.lua
-- 사망 이벤트 처리 및 UI 연동

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local UIManager = require(Client.UIManager)
local UILocalizer = require(Client.Localization.UILocalizer)

local DeathController = {}

-- Private State
local initialized = false
local deathUI = nil -- { container, title, lossLabel, countdownLabel }

--========================================
-- Public API
--========================================

function DeathController.Init()
	if initialized then return end
	
	-- 서버로부터 사망 이벤트 수신
	NetClient.On("Player.Died", function(data)
		local delayTime = data.respawnDelay or 5
		DeathController.showDeathScreen(delayTime)
	end)
	
	-- 서버로부터 리스폰 완료 이벤트 수신
	NetClient.On("Player.Respawned", function(data)
		DeathController.hideDeathScreen()
	end)
	
	initialized = true
	print("[DeathController] Initialized")
end

function DeathController.showDeathScreen(delayTime)
	-- UI가 아직 준비되지 않았으면 UIManager를 통해 가져옴
	if not deathUI then
		deathUI = UIManager.getDeathUI()
	end
	
	if not deathUI then return end
	
	local container = deathUI.container
	container.Visible = true
	container.GroupTransparency = 1
	
	-- 모든 열려있는 창 닫기 (UIManager 연동)
	UIManager.closeAll()
	
	-- 페이드 인
	TweenService:Create(container, TweenInfo.new(1), { GroupTransparency = 0 }):Play()
	
	-- 카운트다운 루프
	task.spawn(function()
		local remaining = delayTime
		while remaining > 0 and container.Visible do
			deathUI.countdownLabel.Text = UILocalizer.Localize(string.format("%d초 후 부활합니다", math.ceil(remaining)))
			task.wait(1)
			remaining -= 1
		end
		if container.Visible then
			deathUI.countdownLabel.Text = UILocalizer.Localize("리스폰 중...")
		end
	end)
end

function DeathController.hideDeathScreen()
	if not deathUI then return end
	
	local container = deathUI.container
	if not container.Visible then return end
	
	-- 페이드 아웃
	local tween = TweenService:Create(container, TweenInfo.new(0.5), { GroupTransparency = 1 })
	tween.Completed:Connect(function()
		container.Visible = false
	end)
	tween:Play()
end

return DeathController
