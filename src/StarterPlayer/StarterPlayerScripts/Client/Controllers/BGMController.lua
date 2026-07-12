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
local FADE_TIME = 0.6
local ZONE_POLL_INTERVAL = 1.0

local ZONE_SOUND_NAMES = {
	-- New RPG World Zones
	CHEONGUN = "TOWN_BGM",                 -- 청운촌 (스타팅 마을)
	SLIME_HABITAT = "FOREST_BGM",          -- 슬라임 서식지
	HORNEDLARVAZONE = "FOREST_BGM",        -- 애벌레의 숲 (대문자 변환 대응)
	STUMP_ZONE = "FOREST_BGM",             -- 스텀프의 땅
	STUMP_KING_ZONE = "FOREST_BGM",        -- 스텀프 킹의 안식처
	CYCLOPS_BAT_ZONE = "FOREST_BGM",       -- 박쥐의 언덕
	SMALL_GOLEM_ZONE = "CAVE_BGM",         -- 스산한 동굴
	EERIE_CAVE = "CAVE_BGM",               -- 스산한 동굴
	SPIDER_ZONE = "CAVE_BGM",              -- 거미구역
	POISON_NEST = "CAVE_BGM",              -- 맹독 둥지
	SAMURAI_ZONE = "SAMURAI_BGM",          -- 멸망한 동쪽의 나라
	DEATH_SNOW_MOUNTAIN = "SNOW_BGM",      -- 죽음의 설산
	SKY_ISLAND = "SKY_BGM",                -- 하늘섬
	BLUE_FLAME_KNIGHT_ZONE = "BOSS_BGM",-- 푸른 신념 (최종 보스)
	DESERTGUARDIANZONE = "BOSS_BGM",     -- 사막의 수호자 구역 (BOSS_BGM)
	DEEPABYSS_NORTH_POSEIDON = "BOSS_BGM", -- 수중도시 포세이돈 레이드방

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
	currentZoneName = zoneName

	if not zoneName then
		stopZoneBGM()
		return
	end

	local soundName = ZONE_SOUND_NAMES[string.upper(zoneName)] or (string.upper(zoneName) .. "_BGM")
	local source = findSoundSourceByName(soundName)
	if not source then
		stopZoneBGM()
		return
	end

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
	tweenVolume(sound, ZONE_VOLUME)
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
