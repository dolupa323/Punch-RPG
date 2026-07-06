-- WeaponEnhanceEffectController.lua
-- Assets/VFX/Purple(Attachment+Beam+ParticleEmitter) 클론 기반, 강화 단계별 색상 조절

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local WeaponEnhanceEffectController = {}

local EFFECT_TAG   = "WEE_v4"
local currentLevel = 0

-- ============================================================
-- Purple 이펙트 원본 (Attachment + Beam*5 + ParticleEmitter)
-- ============================================================
local function getAuraTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx    = assets and assets:FindFirstChild("VFX")
	return vfx and vfx:FindFirstChild("Purple")
end

-- ============================================================
-- 강화 단계 티어
-- Purple 이펙트의 Color만 티어별로 교체하여 사용
-- ============================================================
-- 단색 ColorSequence
local function makeSolidCS(c)
	return ColorSequence.new(c)
end

-- 티어별 색상. 크기 배율은 강화 레벨에 따라 applyEffect에서 별도 계산
local TIERS = {
	[8]  = { color = Color3.fromRGB(160, 60, 220) },  -- 보라
	[9]  = { color = Color3.fromRGB(255, 200, 40) },  -- 금빛
	[10] = { color = Color3.fromRGB(0, 210, 190) },   -- 청록
	[11] = { color = Color3.fromRGB(50, 110, 255) },  -- 파랑
	[12] = { color = Color3.fromRGB(0, 200, 90) },    -- 에메랄드
	[13] = { color = Color3.fromRGB(255, 120, 0) },   -- 오렌지
	[14] = { color = Color3.fromRGB(255, 40, 0) },    -- 불꽃빨강
	[15] = { color = Color3.fromRGB(255, 255, 255) }, -- 순수백 (+16~+50도 동일)
}

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
local function createLight(handle, tier, sizeMult)
	local light = Instance.new("PointLight")
	light.Brightness = 1.5
	light.Range      = 12 * sizeMult
	light.Color      = tier.color
	light.Shadows    = false
	light:SetAttribute(EFFECT_TAG, true)
	light.Parent = handle
	return light
end

-- ============================================================
-- Highlight
-- ============================================================
local function createHighlight(acc, tier)
	local hl = Instance.new("Highlight")
	hl.FillColor           = tier.color
	hl.OutlineColor        = tier.color
	hl.FillTransparency    = 0.75
	hl.OutlineTransparency = 0.1
	hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee             = acc
	hl:SetAttribute(EFFECT_TAG, true)
	hl.Parent = acc
	return hl
end

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

-- ============================================================
-- Purple 이펙트 클론 - Attachment0/Attachment1 참조가 깨지지 않도록
-- Part 전체를 통째로 복제한 뒤 Handle에 용접, Color만 교체
-- sizeMult로 Attachment 배치 간격/Beam 두께/Particle 크기를 함께 확대
-- ============================================================
local function cloneAuraLayer(auraTemplate, handle, tier, sizeMult)
	local carrier = auraTemplate:Clone()
	carrier.Anchored   = false
	carrier.CanCollide = false
	carrier.CanQuery   = false
	carrier.CanTouch   = false
	carrier.Massless   = true
	carrier.Transparency = 1
	-- Purple 템플릿의 빔 배열은 로컬 X축을 따라 배치돼 있고, 무기 Handle의 긴 축(날 방향)은 로컬 Z축이므로 90도 보정
	carrier.CFrame = handle.CFrame * CFrame.Angles(0, math.rad(90), 0)
	carrier:SetAttribute(EFFECT_TAG, true)
	carrier.Parent = handle

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = carrier
	weld.Parent = carrier

	local cs = makeSolidCS(tier.color)
	for _, obj in ipairs(carrier:GetDescendants()) do
		if obj:IsA("Attachment") then
			obj.CFrame = obj.CFrame.Rotation + obj.CFrame.Position * sizeMult
		elseif obj:IsA("Beam") then
			obj.Color  = cs
			obj.Width0 = obj.Width0 * sizeMult
			obj.Width1 = obj.Width1 * sizeMult
		elseif obj:IsA("ParticleEmitter") then
			obj.Color = cs
			obj.Size  = scaleNS(obj.Size, sizeMult)
		end
	end
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
-- 반환값: 이펙트가 (무/유 상관없이) 실제로 적용됐는지 여부.
-- false면 무기 Accessory가 아직 캐릭터에 붙지 않은 것이므로 refresh()가 재시도해야 함
local function applyEffect(char, level)
	local acc = findWeaponAccessory(char)
	if not acc then return false end
	local handle = acc:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return false end

	clearEffects(handle)

	if level < 8 then return true end
	local tier = getTier(level)
	if not tier then return true end

	local auraTemplate = getAuraTemplate()
	if not auraTemplate then
		warn("[WeaponEnhanceEffect] Assets/VFX/Purple 없음")
		return false
	end

	-- 강화 수치가 오를수록 이펙트 전체 크기가 완만하게 커짐 (+8: 1.0배 ~ +50: 약 2.3배)
	local sizeMult = 1 + math.min(level - 8, 42) * 0.03

	cloneAuraLayer(auraTemplate, handle, tier, sizeMult)
	createLight(handle, tier, sizeMult)
	createHighlight(acc, tier)

	print(("[WeaponEnhanceEffect] +%d 적용"):format(level))
	return true
end

-- ============================================================
-- 갱신
-- ============================================================
local function refresh()
	local char = localPlayer.Character
	if not char then return end
	local level = getHandLevel()
	if level == currentLevel then return end
	if applyEffect(char, level) then
		currentLevel = level
	end
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
