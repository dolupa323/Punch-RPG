-- RaidBossData.lua
-- 레이드 보스별 전용 체력바 UI 구성 데이터 (배율, 테마 색상, 그라데이션)

local RaidBossData = {
	["DesertGuardian"] = {
		mobModelName = "DesertGuardian",
		displayName = "사막의 수호자",
		segments = 31, -- 스크린샷과 동일하게 x31 세그먼트로 구성
		themeColor = Color3.fromRGB(255, 215, 0), -- 골드 테마
		hpGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 230, 50)), -- 연두/라임색
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 240, 60)), -- 연한 노란초록
			ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 200, 30)) -- 초록색
		}),
		underfillColor = Color3.fromRGB(220, 90, 40) -- 다크 오렌지 데미지 잔상
	},
	
	["BlueFlameKnight"] = {
		mobModelName = "BlueFlameKnight",
		displayName = "푸른 불꽃 기사",
		segments = 15,
		themeColor = Color3.fromRGB(80, 160, 255), -- 청색 테마
		hpGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 200, 255)), -- 밝은 하늘색
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(50, 120, 240)), -- 파란색
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 40, 180)) -- 진청색
		}),
		underfillColor = Color3.fromRGB(25, 75, 160) -- 네이비 데미지 잔상
	},
}

return RaidBossData
