local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnConfig = require(Shared:WaitForChild("Config"):WaitForChild("SpawnConfig"))

local BGMController = {}

local initialized = false
local zoneSound = nil
local currentZoneName = nil
local zonePollAccumulator = 0

local ZONE_CHANNEL_NAME = "ZoneBGMChannel"
local ZONE_VOLUME = 0.02
-- 소스 Sound의 Volume 프로퍼티(마스터링 보정값)를 최종 재생 볼륨에 반영하기 위한 스케일.
-- 기준값 0.5일 때 ZONE_VOLUME(0.02)이 되도록 환산한다.
-- (SNOW_BGM/CAVE_BGM/DESERT_BGM처럼 원본이 작게 마스터링되어 Volume=8로 보정해둔 트랙은
--  이 스케일을 곱해야 실제로도 크게 들린다 - 그동안 SoundId만 복사하고 Volume은 무시해서
--  모든 존이 항상 ZONE_VOLUME으로만 재생되던 버그가 있었다)
local ZONE_VOLUME_REFERENCE = 0.5
local ZONE_VOLUME_SCALE = ZONE_VOLUME / ZONE_VOLUME_REFERENCE
local FADE_TIME = 0.6
local ZONE_POLL_INTERVAL = 1.0

local ZONE_SOUND_NAMES = {
	-- New RPG World Zones
	CHEONGUN = "TOWN_BGM",                 -- 청운촌 (스타팅 마을)
	SLIME_HABITAT = "FOREST_BGM",          -- 슬라임 서식지
	HORNEDLARVAZONE = "FOREST_BGM",        -- 애벌레의 숲 (대문자 변환 대응)
	STUMP_ZONE = "FOREST_BGM",             -- 스텀프의 땅
	STUMP_KING_ZONE = "BOSS_BGM",          -- 스텀프 킹의 안식처 (보스 구역 공용 브금)
	CYCLOPS_BAT_ZONE = "CAVE_BGM",         -- 박쥐의 언덕
	SMALL_GOLEM_ZONE = "CAVE_BGM",         -- 스산한 동굴
	EERIE_CAVE = "CAVE_BGM",               -- 스산한 동굴
	SPIDER_ZONE = "CAVE_BGM",              -- 거미구역
	POISON_NEST = "CAVE_BGM",              -- 맹독 둥지
	SAMURAI_ZONE = "SAMURAI_BGM",          -- 멸망한 동쪽의 나라
	DEATH_SNOW_MOUNTAIN = "SNOW_BGM",      -- 죽음의 설산
	SKY_ISLAND = "SKY_BGM",                -- 하늘섬
	BLUE_FLAME_KNIGHT_ZONE = "BOSS_BGM",-- 푸른 신념 (최종 보스)
	DESERTGUARDIANZONE = "BOSS_BGM",     -- 사막의 수호자 구역 (BOSS_BGM)
	VOLCANIC_FIELD = "LAVA_BGM",           -- 화산 분지 (용암슬라임/파이어맨 구역)
	UNDERWATER_CITY = "UNDERWATER_CITY_BGM", -- 클레이온 (수중도시)
	DEEP_ABYSS = "UNDERWATER_CITY_BGM",     -- 심연의 협곡 (수중도시 사냥터, 본토와 동일 브금 사용)
	KRAKEN_ZONE = "BOSS_BGM",              -- 크라켄의 심연
	ABYSS_GUARDIAN_ZONE = "BOSS_BGM",      -- 수호자의 성소
	POSEIDON_ZONE = "BOSS_BGM",            -- 포세이돈의 궁전

	-- Legacy Zones
	GRASSLAND = "FOREST_BGM",
	TROPICAL = "HARBOR_BGM",
	DESERT = "DESERT_BGM",
	SNOW = "SNOW_BGM",
	SNOWFIELD = "SNOW_BGM",
	SNOWLAND = "SNOW_BGM",
	SNOWY = "SNOW_BGM",
}

local function findSoundSourceByName(soundName: string): Sound?
	local direct = SoundService:FindFirstChild(soundName)
	if direct and direct:IsA("Sound") then
		return direct
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local found = assets:FindFirstChild(soundName, true)
		if found and found:IsA("Sound") then
			return found
		end
	end

	warn("[BGMController] BGM Asset not found in game tree: " .. tostring(soundName))
	return nil
end

local function ensureZoneChannel(): Sound?
	if zoneSound and zoneSound.Parent then
		return zoneSound
	end

	zoneSound = SoundService:FindFirstChild(ZONE_CHANNEL_NAME)
	if not zoneSound or not zoneSound:IsA("Sound") then
		zoneSound = Instance.new("Sound")
		zoneSound.Name = ZONE_CHANNEL_NAME
		zoneSound.Parent = SoundService
	end

	zoneSound.Volume = 0
	zoneSound.Looped = true
	zoneSound.RollOffMaxDistance = 10000
	return zoneSound
end

local function tweenVolume(sound: Sound, volume: number)
	local tween = TweenService:Create(sound, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = volume,
	})
	tween:Play()
	return tween
end

local function stopZoneBGM()
	local sound = zoneSound
	if not sound or not sound.Parent then
		return
	end
	print("[BGMController] stopZoneBGM")
	tweenVolume(sound, 0)
	task.delay(FADE_TIME + 0.05, function()
		if sound.Parent and not currentZoneName then
			sound:Stop()
		end
	end)
end

local function playZoneBGM(zoneName: string?)
	if not zoneName then
		currentZoneName = nil
		stopZoneBGM()
		return
	end

	local soundName = ZONE_SOUND_NAMES[string.upper(zoneName)] or (string.upper(zoneName) .. "_BGM")
	local source = findSoundSourceByName(soundName)
	if not source then
		-- currentZoneName을 갱신하지 않아야 다음 폴링에서 다시 시도한다.
		-- (여기서 zoneName을 세팅해버리면 애셋 스트리밍 지연 등으로 최초 탐색이 실패했을 때
		--  영구히 재시도하지 않는 버그가 발생한다 - 죽음의 설산 SNOW_BGM 미재생 버그 원인)
		stopZoneBGM()
		return
	end

	currentZoneName = zoneName

	print("[BGMController] playZoneBGM - Zone:", zoneName, "Sound:", soundName)

	local sound = ensureZoneChannel()
	if not sound then
		return
	end

	local nextSoundId = source.SoundId
	if sound.SoundId ~= nextSoundId then
		sound.SoundId = nextSoundId
		if sound.IsPlaying then
			sound:Stop()
		end
	end

	if not sound.IsPlaying then
		sound:Play()
	end

	local targetVolume = (source.Volume or ZONE_VOLUME_REFERENCE) * ZONE_VOLUME_SCALE
	tweenVolume(sound, targetVolume)
end

local function refreshZoneBGM()
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local nextZone = SpawnConfig.GetZoneAtPosition(hrp.Position)
	if not nextZone then
		local minDistance = math.huge
		local nearestZone = "CHEONGUN"
		local px, pz = hrp.Position.X, hrp.Position.Z
		for _, zoneName in ipairs(SpawnConfig.GetAllZoneNames()) do
			local zone = SpawnConfig.GetZoneInfo(zoneName)
			if zone and zone.min and zone.max then
				local dx = math.max(zone.min.X - px, 0, px - zone.max.X)
				local dz = math.max(zone.min.Y - pz, 0, pz - zone.max.Y)
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < minDistance then
					minDistance = dist
					nearestZone = zoneName
				end
			end
		end
		nextZone = nearestZone
	end

	if nextZone == currentZoneName then
		return
	end

	playZoneBGM(nextZone)
end

function BGMController.Init()
	if initialized then
		return
	end
	initialized = true
	print("[BGMController] BGMController Init start")

	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			refreshZoneBGM()
		end)
	end)

	RunService.Heartbeat:Connect(function(dt)
		zonePollAccumulator += dt
		if zonePollAccumulator < ZONE_POLL_INTERVAL then
			return
		end
		zonePollAccumulator = 0
		refreshZoneBGM()
	end)

	task.defer(function()
		refreshZoneBGM()
	end)
end

return BGMController
