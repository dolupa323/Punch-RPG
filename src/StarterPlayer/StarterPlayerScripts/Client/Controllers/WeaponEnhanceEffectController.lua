-- WeaponEnhanceEffectController.lua
-- Assets/VFX/SwordAura 파티클 클론 기반, 강화 단계별 색·강도 조절

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local WeaponEnhanceEffectController = {}

local EFFECT_TAG   = "WEE_v3"
local currentLevel = 0
local darkThread   = nil

-- ============================================================
-- SwordAura 원본
-- ============================================================
local function getSwordAura()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx    = assets and assets:FindFirstChild("VFX")
	return vfx and vfx:FindFirstChild("SwordAura")
end

-- ============================================================
-- 강화 단계 티어
-- 모든 색에 화이트계열 혼합 (c2가 항상 밝은 색)
-- 네온 파트 없음 - 파티클 + PointLight + Highlight만 사용
-- ============================================================
-- 단색 ColorSequence (c2 없음, 흰색 섞임 없음)
local function makeSolidCS(c)
	return ColorSequence.new(c)
end

local TIERS = {
	-- 단색 파티클 색상, 흰색 혼합 없음
	-- +8  금빛
	[8] = {
		color = Color3.fromRGB(255, 200, 40),
		layerCount = 1,
		rateMult = 1.0, sizeMult = 1.0, speedMult = 1.0,
		lightColor  = Color3.fromRGB(255, 220, 100),
		lightBright = 1.2, lightRange = 10,
		hlFill    = Color3.fromRGB(255, 200, 60),
		hlOutline = Color3.fromRGB(255, 250, 180),
		hlFillT   = 0.80,
	},
	-- +9  청록
	[9] = {
		color = Color3.fromRGB(0, 210, 190),
		layerCount = 1,
		rateMult = 1.4, sizeMult = 1.15, speedMult = 1.1,
		lightColor  = Color3.fromRGB(0, 220, 210),
		lightBright = 1.6, lightRange = 12,
		hlFill    = Color3.fromRGB(0, 200, 190),
		hlOutline = Color3.fromRGB(180, 255, 250),
		hlFillT   = 0.75,
	},
	-- +10 파랑
	[10] = {
		color = Color3.fromRGB(50, 110, 255),
		layerCount = 2,
		rateMult = 1.8, sizeMult = 1.30, speedMult = 1.2,
		lightColor  = Color3.fromRGB(70, 130, 255),
		lightBright = 2.0, lightRange = 14,
		hlFill    = Color3.fromRGB(50, 110, 255),
		hlOutline = Color3.fromRGB(190, 215, 255),
		hlFillT   = 0.68,
	},
	-- +11 에메랄드
	[11] = {
		color = Color3.fromRGB(0, 200, 90),
		layerCount = 2,
		rateMult = 2.2, sizeMult = 1.50, speedMult = 1.3,
		lightColor  = Color3.fromRGB(0, 210, 110),
		lightBright = 2.5, lightRange = 15,
		hlFill    = Color3.fromRGB(0, 190, 90),
		hlOutline = Color3.fromRGB(180, 255, 210),
		hlFillT   = 0.62,
	},
	-- +12 오렌지
	[12] = {
		color = Color3.fromRGB(255, 120, 0),
		layerCount = 2,
		rateMult = 2.7, sizeMult = 1.70, speedMult = 1.4,
		lightColor  = Color3.fromRGB(255, 140, 0),
		lightBright = 3.0, lightRange = 17,
		hlFill    = Color3.fromRGB(255, 120, 0),
		hlOutline = Color3.fromRGB(255, 235, 170),
		hlFillT   = 0.55,
	},
	-- +13 불꽃빨강
	[13] = {
		color = Color3.fromRGB(255, 40, 0),
		layerCount = 3,
		rateMult = 3.4, sizeMult = 2.00, speedMult = 1.55,
		lightColor  = Color3.fromRGB(255, 70, 0),
		lightBright = 4.0, lightRange = 20,
		hlFill    = Color3.fromRGB(255, 40, 0),
		hlOutline = Color3.fromRGB(255, 190, 140),
		hlFillT   = 0.45,
	},
	-- +14 순수백 (신성)
	[14] = {
		color = Color3.fromRGB(230, 245, 255),
		layerCount = 3,
		rateMult = 4.2, sizeMult = 2.35, speedMult = 1.75,
		lightColor  = Color3.fromRGB(255, 255, 255),
		lightBright = 5.0, lightRange = 24,
		hlFill    = Color3.fromRGB(225, 240, 255),
		hlOutline = Color3.fromRGB(255, 255, 255),
		hlFillT   = 0.35,
	},
	-- +15 골드+화이트
	[15] = {
		color  = Color3.fromRGB(255, 220, 80),   -- 골드
		color2 = Color3.fromRGB(255, 255, 220),  -- 화이트
		layerCount = 4,
		rateMult = 6.0, sizeMult = 2.80, speedMult = 2.0,
		lightColor  = Color3.fromRGB(255, 230, 120),
		lightBright = 1.5, lightRange = 16,
		hlFill    = Color3.fromRGB(255, 210, 60),
		hlOutline = Color3.fromRGB(255, 255, 200),
		hlFillT   = 0.25,
	},
}

-- +15 어둠 색상 순환 (Highlight/Light용 — 파티클과 별개)
local DARK_CYCLE = {
	Color3.fromRGB(8,   8,  12),
	Color3.fromRGB(20, 10,  30),
	Color3.fromRGB(40,  0,  60),
	Color3.fromRGB(15, 15,  20),
	Color3.fromRGB(50,  0,  70),
	Color3.fromRGB(10,  8,  15),
}

-- ============================================================
-- NumberSequence / NumberRange 배율
-- ============================================================
local function scaleNS(ns, mult)
	local kps = {}
	for _, kp in ipairs(ns.Keypoints) do
		table.insert(kps, NumberSequenceKeypoint.new(
			kp.Time,
			math.clamp(kp.Value * mult, 0, 9999),
			math.clamp(kp.Envelope * mult, 0, 9999)
		))
	end
	return NumberSequence.new(kps)
end

local function scaleNR(nr, mult)
	return NumberRange.new(nr.Min * mult, nr.Max * mult)
end


-- ============================================================
-- 기존 이펙트 제거
-- ============================================================
local function clearEffects(handle)
	for _, ch in ipairs(handle:GetChildren()) do
		if ch:GetAttribute(EFFECT_TAG) then ch:Destroy() end
	end
	local acc = handle.Parent
	if acc and acc:IsA("Accessory") then
		for _, ch in ipairs(acc:GetChildren()) do
			if ch:GetAttribute(EFFECT_TAG) then ch:Destroy() end
		end
	end
end

-- ============================================================
-- PointLight (약한 주변광, 그림자 OFF)
-- ============================================================
local function createLight(handle, tier)
	local light = Instance.new("PointLight")
	light.Brightness = tier.lightBright
	light.Range      = tier.lightRange
	light.Color      = tier.lightColor
	light.Shadows    = false
	light:SetAttribute(EFFECT_TAG, true)
	light.Parent = handle

	local base = tier.lightBright
	task.spawn(function()
		while light.Parent do
			TweenService:Create(light, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Brightness = base * 0.5 }):Play()
			task.wait(1.0)
			TweenService:Create(light, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Brightness = base * 1.3 }):Play()
			task.wait(1.0)
		end
	end)
	return light
end

-- ============================================================
-- Highlight
-- ============================================================
local function createHighlight(acc, tier)
	local hl = Instance.new("Highlight")
	hl.FillColor           = tier.hlFill
	hl.OutlineColor        = tier.hlOutline
	hl.FillTransparency    = tier.hlFillT
	hl.OutlineTransparency = 0.1
	hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee             = acc
	hl:SetAttribute(EFFECT_TAG, true)
	hl.Parent = acc
	return hl
end

-- ============================================================
-- SwordAura 파티클 1레이어 클론
-- Color만 교체, LightEmission은 원본 유지 (검정 네모 아티팩트 방지)
-- ============================================================
local function cloneAuraLayer(swordAura, handle, tier, layerIdx)
	local cs
	if tier.keepOriginalColor then
		cs = nil
	elseif tier.color2 then
		-- 두 색 교차 (골드+화이트 등)
		local c1 = tier.color
		local c2 = tier.color2
		cs = ColorSequence.new{
			ColorSequenceKeypoint.new(0,    c1),
			ColorSequenceKeypoint.new(0.40, c2),
			ColorSequenceKeypoint.new(0.60, c1),
			ColorSequenceKeypoint.new(1,    c2),
		}
	else
		cs = makeSolidCS(tier.color)
	end

	local lSizeMult  = tier.sizeMult  * (1 + (layerIdx - 1) * 0.20)
	local lRateMult  = tier.rateMult  * math.max(0.50, 1 - (layerIdx - 1) * 0.18)
	local lSpeedMult = tier.speedMult * (1 + (layerIdx - 1) * 0.08)
	local lifeMult   = 1 + (tier.rateMult - 1) * 0.10

	for _, child in ipairs(swordAura:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local pe = child:Clone()

			-- keepOriginalColor이면 Color 교체 안 함 (원본 텍스처/색 유지)
			if not tier.keepOriginalColor then
				pe.Color = cs
			end
			pe.Rate     = math.clamp(pe.Rate * lRateMult, 1, 3000)
			pe.Size     = scaleNS(pe.Size, lSizeMult)
			pe.Speed    = scaleNR(pe.Speed, lSpeedMult)
			pe.Lifetime = scaleNR(pe.Lifetime, lifeMult)

			pe.Name = ("AuraL%d_%s"):format(layerIdx, child.Name)
			pe:SetAttribute(EFFECT_TAG, true)
			pe.Parent = handle
		end
	end
end

-- ============================================================
-- +15 어둠 Highlight/Light 색상 순환
-- ============================================================
local function startDarkCycle(hl, light)
	if darkThread then task.cancel(darkThread); darkThread = nil end
	darkThread = task.spawn(function()
		local idx = 1
		while hl and hl.Parent do
			local c  = DARK_CYCLE[idx]
			local cn = DARK_CYCLE[(idx % #DARK_CYCLE) + 1]
			TweenService:Create(hl,    TweenInfo.new(0.8, Enum.EasingStyle.Sine),
				{ FillColor = c, OutlineColor = cn }):Play()
			TweenService:Create(light, TweenInfo.new(0.8, Enum.EasingStyle.Sine),
				{ Color = cn }):Play()
			idx = (idx % #DARK_CYCLE) + 1
			task.wait(0.85)
		end
	end)
end

-- ============================================================
-- 티어 조회
-- ============================================================
local function getTier(level)
	if level < 8 then return nil end
	local best = nil
	for k in pairs(TIERS) do
		if k <= level and (not best or k > best) then best = k end
	end
	return best and TIERS[best] or nil
end

local function findWeaponAccessory(char)
	for _, ch in ipairs(char:GetChildren()) do
		if ch:IsA("Accessory") and ch:GetAttribute("IsWeaponAccessory") then
			return ch
		end
	end
end

local function getHandLevel()
	local ok, IC = pcall(require, script.Parent:WaitForChild("InventoryController"))
	if not ok or not IC then return 0 end
	local eq   = IC.getEquipment()
	local hand = eq and eq.HAND
	if not hand then return 0 end
	return (hand.attributes and tonumber(hand.attributes.enhanceLevel)) or 0
end

-- ============================================================
-- 이펙트 적용
-- ============================================================
local function applyEffect(char, level)
	local acc = findWeaponAccessory(char)
	if not acc then return end
	local handle = acc:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end

	clearEffects(handle)
	if darkThread then task.cancel(darkThread); darkThread = nil end

	if level < 8 then return end
	local tier = getTier(level)
	if not tier then return end

	local swordAura = getSwordAura()
	if not swordAura then
		warn("[WeaponEnhanceEffect] Assets/VFX/SwordAura 없음")
		return
	end

	for i = 1, tier.layerCount do
		cloneAuraLayer(swordAura, handle, tier, i)
	end

	local light = createLight(handle, tier)
	local hl    = createHighlight(acc, tier)

	if tier.dark then
		startDarkCycle(hl, light)
	end

	print(("[WeaponEnhanceEffect] +%d 적용 (%d레이어)"):format(level, tier.layerCount))
end

-- ============================================================
-- 갱신
-- ============================================================
local function refresh()
	local char = localPlayer.Character
	if not char then return end
	local level = getHandLevel()
	if level == currentLevel then return end
	currentLevel = level
	applyEffect(char, level)
end

local function onCharAdded(char)
	currentLevel = -1
	task.spawn(function()
		-- 장비 데이터가 로드될 때까지 최대 15초간 재시도
		local waited = 0
		repeat
			task.wait(1.0)
			waited += 1
			refresh()
		until currentLevel >= 0 or waited >= 15

		char.ChildAdded:Connect(function(child)
			if child:IsA("Accessory") then
				task.wait(0.5)
				currentLevel = -1
				refresh()
			end
		end)

		char.ChildRemoved:Connect(function(child)
			if child:IsA("Accessory") and child:GetAttribute("IsWeaponAccessory") then
				currentLevel = 0
				if darkThread then task.cancel(darkThread); darkThread = nil end
			end
		end)
	end)
end

-- ============================================================
-- Init
-- ============================================================
function WeaponEnhanceEffectController.Init()
	task.spawn(function()
		local ok, IC = pcall(require, script.Parent:WaitForChild("InventoryController"))
		if ok and IC and IC.onChanged then
			IC.onChanged(refresh)
		end
	end)

	localPlayer.CharacterAdded:Connect(onCharAdded)
	if localPlayer.Character then onCharAdded(localPlayer.Character) end

	print("[WeaponEnhanceEffectController] Initialized")
end

return WeaponEnhanceEffectController
