-- NameTagScaleController.lua
-- 플레이어 머리 위 네임태그(닉네임+레벨)가 카메라 줌 거리에 상관없이 항상 동일한
-- "화면 픽셀 크기"로 고정 표시되는 BillboardGui 기본 동작 때문에, 줌아웃해서
-- 캐릭터가 작게 보일 때는 네임태그만 상대적으로 과하게 크게 보이는 문제를 보정한다.
-- 카메라와의 실제 거리를 기준으로 UIScale을 적용해 원근감 있게 자연스럽게 작아지도록 한다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local NameTagScaleController = {}

-- [수정] 이전에는 BASE_DISTANCE/distance 비율식을 썼는데, 기준 거리가 너무 가까워서
-- 평소 즐겨 쓰는 "적당히 가까운" 줌 거리에서도 이미 축소가 시작되어 오히려 너무
-- 작아지는 역효과가 났다. 이제는 구간을 나눠서, NEAR_DISTANCE 이내(평소 플레이하는
-- 가까운/보통 줌 범위)에서는 원래 크기(1.0)를 절대 건드리지 않고, 그 이상 멀어질
-- 때만(최대 줌아웃까지) 선형으로 줄어들도록 한다.
local NEAR_DISTANCE = 20 -- 이 거리까지는 원래 크기(1.0) 그대로 유지
local FAR_DISTANCE = Balance.CAM_MAX_ZOOM or 45 -- 이 거리(최대 줌아웃)에서 MIN_SCALE까지 축소
local MIN_SCALE = 0.3
local MAX_SCALE = 1.0
local UPDATE_INTERVAL = 0.1

local function getScale(distance: number): number
	if distance <= NEAR_DISTANCE then
		return MAX_SCALE
	end
	if distance >= FAR_DISTANCE then
		return MIN_SCALE
	end
	local t = (distance - NEAR_DISTANCE) / (FAR_DISTANCE - NEAR_DISTANCE)
	return MAX_SCALE - t * (MAX_SCALE - MIN_SCALE)
end

-- [실측 확인] BillboardGui에 직접 붙인 UIScale은 값(Scale)은 정상적으로 바뀌는데도
-- 실제 화면에는 전혀 반영되지 않았다 (execute_luau로 확인: 거리 45에서 Scale=0.3인데
-- 실제 스크린샷상 텍스트 크기는 줄지 않음). UIScale은 BillboardGui 자신의 월드 앵커
-- 크기가 아니라 그 내부 자식들의 "상대 레이아웃"에만 적용되는 것으로 보인다.
-- 그래서 BillboardGui.Size의 실제 Offset 값 자체를 매 프레임 직접 줄이는 방식으로 바꿨다.
local BASE_SIZE = Vector2.new(220, 36)

function NameTagScaleController.Init()
	local accumulated = 0

	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < UPDATE_INTERVAL then
			return
		end
		accumulated = 0

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position

		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local head = char and char:FindFirstChild("Head")
			local billboard = head and head:FindFirstChild("PlayerNameTag")
			if billboard then
				local distance = (head.Position - camPos).Magnitude
				local scale = getScale(distance)
				billboard.Size = UDim2.new(0, BASE_SIZE.X * scale, 0, BASE_SIZE.Y * scale)
			end
		end
	end)
end

return NameTagScaleController
