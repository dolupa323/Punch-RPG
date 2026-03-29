-- SkillEffectController.lua
-- 액티브 스킬 사용 시 VFX, 사운드, 애니메이션 연출 담당 (클라이언트)
-- 서버 ActiveSkill.Used 브로드캐스트를 수신하여 이펙트 재생

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local NetClient = require(script.Parent.Parent.NetClient)
local AnimationManager = require(script.Parent.Parent.Utils.AnimationManager)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationIds = require(Shared.Config.AnimationIds)

local player = Players.LocalPlayer

local SkillEffectController = {}

--========================================
-- Constants
--========================================
local VFX_CAST_LIFETIME = 2.0    -- 시전 VFX 지속 시간
local VFX_HIT_LIFETIME = 1.5     -- 피격 VFX 지속 시간

--========================================
-- Asset Folders (lazy init)
--========================================
local assetsFolder = nil
local castVFXFolder = nil
local hitVFXFolder = nil
local castSoundFolder = nil
local hitSoundFolder = nil

local function ensureAssetFolders()
	if assetsFolder then return end
	assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then return end

	local skillVFX = assetsFolder:FindFirstChild("SkillVFX")
	if skillVFX then
		castVFXFolder = skillVFX:FindFirstChild("Cast")
		hitVFXFolder = skillVFX:FindFirstChild("Hit")
	end

	local skillSounds = assetsFolder:FindFirstChild("SkillSounds")
	if skillSounds then
		castSoundFolder = skillSounds:FindFirstChild("Cast")
		hitSoundFolder = skillSounds:FindFirstChild("Hit")
	end
end

--========================================
-- Internal Helpers
--========================================

--- 캐릭터 가져오기 (userId로)
local function getCharacterByUserId(userId: number): Model?
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer then return nil end
	return targetPlayer.Character
end

--- 크리처 모델 찾기 (instanceId로 — Attribute "InstanceId" 기반)
local function getCreatureModel(targetId: string): Model?
	local creaturesFolder = workspace:FindFirstChild("Creatures")
	if not creaturesFolder then return nil end
	for _, child in creaturesFolder:GetChildren() do
		if child:GetAttribute("InstanceId") == targetId then
			return child
		end
	end
	return nil
end

--- VFX 파트 스폰 및 자동 삭제
local function spawnVFX(template: Instance, parent: BasePart, lifetime: number)
	if not template or not parent then return end

	local vfx = template:Clone()

	-- Weld로 부착 (이동 중에도 따라감)
	if vfx:IsA("BasePart") then
		vfx.CFrame = parent.CFrame
		vfx.Anchored = false
		vfx.CanCollide = false
		vfx.CanQuery = false
		vfx.CanTouch = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = vfx
		weld.Part1 = parent
		weld.Parent = vfx
	end

	vfx.Parent = workspace

	-- ParticleEmitter Burst 발사
	for _, desc in vfx:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			local burstCount = desc:GetAttribute("BurstCount")
			if burstCount then
				desc:Emit(burstCount)
			else
				desc.Enabled = true
				task.delay(lifetime * 0.6, function()
					if desc and desc.Parent then
						desc.Enabled = false
					end
				end)
			end
		end
	end

	Debris:AddItem(vfx, lifetime)
end

--- 사운드 재생 (원본 Clone → 파트에 부착 → Play → 자동 정리)
local function playSound(template: Sound, parent: BasePart)
	if not template or not parent then return end

	local sfx = template:Clone()
	sfx.Parent = parent
	sfx:Play()
	sfx.Ended:Once(function()
		if sfx and sfx.Parent then
			sfx:Destroy()
		end
	end)
end

--========================================
-- Effect Execution
--========================================

--- 캐릭터에서 장착 무기의 날(Blade) 파트 찾기
local function getWeaponBladePart(character: Model): BasePart?
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return nil end
	local handle = tool:FindFirstChild("Handle")
	if not handle then return nil end

	-- Handle이 아닌 가장 큰 가시적 파트 = 날
	local bestPart = nil
	local bestScore = 0
	for _, p in tool:GetDescendants() do
		if p:IsA("BasePart") and p ~= handle and p.Transparency < 0.85 then
			local dim = math.max(p.Size.X, p.Size.Y, p.Size.Z)
			local score = dim * (p.Size.X * p.Size.Y * p.Size.Z)
			if score > bestScore then
				bestScore = score
				bestPart = p
			end
		end
	end
	return bestPart or handle
end

--- VFX 템플릿 검색 (넘버링 지원: _Cast, _Cast01, _Cast02, ...)
local function findVFXTemplates(folder: Folder, baseName: string): { Instance }
	local results = {}
	-- 기본 이름 체크 (_Cast 또는 _Hit)
	local exact = folder:FindFirstChild(baseName)
	if exact then
		table.insert(results, exact)
	end
	-- 넘버링 체크 (_Cast01 ~ _Cast99)
	for i = 1, 99 do
		local numbered = folder:FindFirstChild(baseName .. string.format("%02d", i))
		if numbered then
			table.insert(results, numbered)
		else
			break
		end
	end
	return results
end

--- 스킬 이펙트 전체 실행
local function executeSkillEffects(userId: number, skillId: string, targetId: string?)
	ensureAssetFolders()

	local character = getCharacterByUserId(userId)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	-- 1. 애니메이션 재생 (load 후 직접 Play — IsPlaying 가드 우회)
	local animName = AnimationIds.SKILL_ANIM_MAP[skillId]
	if animName then
		local track = AnimationManager.load(humanoid, animName)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			track:Play(0.05)
		end
	end

	-- skillId(SWORD_A1 등) → 에셋 이름(SkillSword_Strike 등) 변환
	local assetName = animName -- 애니메이션 이름 = 에셋 이름 규칙

	-- 2. 시전 VFX → 무기 날(Blade)에 부착 (넘버링 지원: _Cast, _Cast01, _Cast02 ...)
	if castVFXFolder and assetName then
		local castTemplates = findVFXTemplates(castVFXFolder, assetName .. "_Cast")
		if #castTemplates > 0 then
			local bladePart = getWeaponBladePart(character)
			for _, tmpl in ipairs(castTemplates) do
				spawnVFX(tmpl, bladePart or hrp, VFX_CAST_LIFETIME)
			end
		end
	end

	-- 3. 시전 사운드 (캐릭터 기준 — 3D 사운드)
	if castSoundFolder and assetName then
		local castSoundTemplate = castSoundFolder:FindFirstChild(assetName .. "_Cast")
		if castSoundTemplate then
			playSound(castSoundTemplate, hrp)
		end
	end

	-- 4. 피격 VFX + 사운드 (타겟 기준)
	if targetId then
		local targetModel = getCreatureModel(targetId)
		if targetModel then
			local targetHrp = targetModel:FindFirstChild("HumanoidRootPart")
				or targetModel.PrimaryPart
				or targetModel:FindFirstChildWhichIsA("BasePart")

			if targetHrp and assetName then
				-- 피격 VFX (넘버링 지원: _Hit, _Hit01, _Hit02 ...)
				if hitVFXFolder then
					local hitTemplates = findVFXTemplates(hitVFXFolder, assetName .. "_Hit")
					for _, tmpl in ipairs(hitTemplates) do
						spawnVFX(tmpl, targetHrp, VFX_HIT_LIFETIME)
					end
				end

				-- 피격 사운드
				if hitSoundFolder then
					local hitSoundTemplate = hitSoundFolder:FindFirstChild(assetName .. "_Hit")
					if hitSoundTemplate then
						playSound(hitSoundTemplate, targetHrp)
					end
				end
			end
		end
	end
end

--========================================
-- Init
--========================================
local initialized = false

function SkillEffectController.Init()
	if initialized then return end
	initialized = true

	-- 서버 브로드캐스트 수신: 스킬 사용 이펙트
	NetClient.On("ActiveSkill.Used", function(data)
		if not data then return end
		local userId = data.userId
		local skillId = data.skillId
		local targetId = data.targetId

		if not userId or not skillId then return end

		task.spawn(function()
			executeSkillEffects(userId, skillId, targetId)
		end)
	end)

	print("[SkillEffectController] Initialized")
end

return SkillEffectController
