-- HitFeedbackController.lua
-- 플레이어 피격 연출 및 물리적 상태 보정
-- Phase 11-5: 전투 피드백 강화

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local HitFeedbackController = {}

-- Constant
local SHAKE_INTENSITY = 0.8
local SHAKE_DURATION = 0.15

local player = Players.LocalPlayer
local initialized = false

--========================================
-- Internal Functions
--========================================

--- 화면 흔들림 효과
local function playScreenShake(intensity)
	local cam = workspace.CurrentCamera
	if not cam then return end
	
	task.spawn(function()
		local startPos = Vector3.new(0, 0, 0)
		for i = 1, 6 do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)
			cam.CFrame = cam.CFrame * CFrame.new(offset)
			task.wait(0.02)
		end
	end)
end

--- 캐릭터 피격 흔들림 (채집 노드 흔들림과 유사한 연출)
local function playCharacterShake(sourcePos)
	local char = player.Character
	if not char or not char.PrimaryPart then return end
	
	local hrp = char.PrimaryPart
	local origPivot = char:GetPivot()
	
	task.spawn(function()
		-- 피격 방향으로부터 살짝 뒤로 튕김 (Recoil상향)
		local hitDir
		if sourcePos then
			hitDir = (hrp.Position - sourcePos).Unit
		else
			hitDir = -hrp.CFrame.LookVector
		end
		
		-- 1단계: 강한 반동 (0.4 -> 0.8 Studs)
		char:PivotTo(origPivot * CFrame.new(hitDir * 0.8))
		task.wait(0.04)
		-- 2단계: 복원 시 미세 진동 (0.15 -> 0.3 Studs)
		char:PivotTo(origPivot * CFrame.new(-hitDir * 0.3))
		task.wait(0.04)
		char:PivotTo(origPivot)
	end)
end

--- 캐릭터 상태 리셋 (드러눕는 현상 방지)
local function preventLyingDown()
	local char = player.Character
	if not char then return end
	
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	-- 매 프레임 GettingUp 상태로 리셋 시도 (물리 엔진에 의한 강제 눕기 방지)
	if humanoid:GetState() == Enum.HumanoidStateType.FallingDown or 
	   humanoid:GetState() == Enum.HumanoidStateType.Ragdoll or
	   humanoid:GetState() == Enum.HumanoidStateType.Landed then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

--========================================
-- Public API
--========================================

function HitFeedbackController.Init()
	if initialized then return end
	
	-- 서버로부터 피격 이벤트 수신
	NetClient.On("Combat.Player.Hit", function(data)
		print("[HitFeedbackController] Received hit! Damage:", data.damage)
		
		-- 1. 화면 흔들림
		playScreenShake(SHAKE_INTENSITY)
		
		-- 2. 캐릭터 흔들림 (소스 위치가 있을 때)
		if data.sourcePos then
			playCharacterShake(data.sourcePos)
		end
		
		-- 3. 피격 사운드 (임시)
		-- TODO: 사운드 시스템 추가
	end)
	
	-- 눕는 현상을 방지하기 위한 주기적 체크 부하가 적으므로 Heartbeat 사용
	RunService.Heartbeat:Connect(preventLyingDown)
	
	initialized = true
	print("[HitFeedbackController] Initialized")
end

return HitFeedbackController
