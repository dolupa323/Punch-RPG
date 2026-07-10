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

	["AbyssGuardian"] = {
		mobModelName = "AbyssGuardian",
		displayName = "심연의 수호자",
		segments = 31,
		themeColor = Color3.fromRGB(230, 40, 40), -- 붉은 테마
		hpGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 70)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(230, 40, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 10, 10))
		}),
		underfillColor = Color3.fromRGB(90, 10, 10) -- 짙은 적색 데미지 잔상
	},

	["Kraken"] = {
		mobModelName = "Kraken",
		displayName = "크라켄",
		segments = 20,
		themeColor = Color3.fromRGB(120, 90, 200), -- 짙은 심해 자주색 테마 (모델 맨틀 색과 통일)
		hpGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 130, 230)), -- 밝은 보라
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 200, 190)), -- 생체발광 청록
			ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 30, 70)) -- 짙은 남보라
		}),
		underfillColor = Color3.fromRGB(35, 25, 55) -- 어두운 자주 데미지 잔상
	},
}

return RaidBossData
