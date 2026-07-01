-- TeleportFade.lua
-- 순간이동 시 화면 페이드아웃 → 이동 → 페이드인 처리

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")

local TeleportFade = {}

local FADE_OUT_TIME = 0.35
local FADE_IN_TIME  = 0.45

local function getFadeSG()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing  = playerGui:FindFirstChild("TeleportFadeSG")
	if existing then return existing end

	local sg = Instance.new("ScreenGui")
	sg.Name           = "TeleportFadeSG"
	sg.ResetOnSpawn   = false
	sg.DisplayOrder   = 999        -- 모든 UI 위
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent         = playerGui

	local frame = Instance.new("Frame")
	frame.Name                 = "Overlay"
	frame.Size                 = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3     = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel      = 0
	frame.ZIndex               = 1
	frame.Parent               = sg

	return sg
end

-- fn: 페이드아웃 후 실행할 함수 (내부에서 teleport 수행)
-- 반환값: fn()의 반환값
function TeleportFade.execute(fn)
	local sg    = getFadeSG()
	local frame = sg:FindFirstChild("Overlay")

	-- 페이드 아웃
	local outTween = TweenService:Create(
		frame,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	outTween:Play()
	outTween.Completed:Wait()

	-- 텔레포트 실행
	local result = fn()

	-- 서버 처리 대기
	task.wait(0.15)

	-- 페이드 인
	local inTween = TweenService:Create(
		frame,
		TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	inTween:Play()
	inTween.Completed:Wait()

	return result
end

return TeleportFade
