-- DeathUI.lua
-- 사망 스크린 UI (You Died 스크린)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local DeathUI = {}

function DeathUI.create(parent)
	-- 최상위 캔버스 그룹 (페이드 인/아웃용)
	local container = Utils.mkFrame({
		name = "DeathOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0.05, 0, 0), -- 매우 어두운 붉은 검은색
		bgT = 1, -- 처음엔 투명 (애니메이션으로 조절)
		useCanvas = true,
		z = 1000,
		vis = false,
		parent = parent
	})

	-- "의식을 잃었습니다" (Died)
	local title = Utils.mkLabel({
		name = "DeathTitle",
		size = UDim2.new(1, 0, 0, 50),
		pos = UDim2.new(0.5, 0, 0.4, 0),
		anchor = Vector2.new(0.5, 0.5),
		text = "의식을 잃었습니다",
		color = C.RED,
		ts = 40,
		bold = true,
		parent = container
	})

	-- 손실 안내
	local lossLabel = Utils.mkLabel({
		name = "LossLabel",
		size = UDim2.new(1, 0, 0, 30),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		text = "가방 안의 아이템 일부를 잃어버렸습니다.",
		color = C.GRAY,
		ts = 18,
		parent = container
	})

	-- 카운트다운
	local countdownLabel = Utils.mkLabel({
		name = "CountdownLabel",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0.65, 0),
		anchor = Vector2.new(0.5, 0.5),
		text = "부활 대기 중...",
		color = C.WHITE,
		ts = 22,
		font = F.NUM,
		parent = container
	})

	return {
		container = container,
		title = title,
		lossLabel = lossLabel,
		countdownLabel = countdownLabel
	}
end

return DeathUI
