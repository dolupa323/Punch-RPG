-- RuneAuraController.lua
-- 유지형 액티브 룬 오라 시각화 컨트롤러

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))

local RuneAuraController = {}

local initialized = false
local player = Players.LocalPlayer

local activeAura = nil

local auraStyleByElement = {
	Fire = {
		orbSize = 0.82,
		transparency = 0.05,
		lightRange = 12,
		lightBrightness = 3.8,
		trailLifetime = 0.10,
		trailTransparency = 0.05,
		bobAmplitude = 1.1,
		glowColor = Color3.fromRGB(255, 95, 35),
	},
	Water = {
		orbSize = 0.96,
		transparency = 0.25,
		lightRange = 10,
		lightBrightness = 2.3,
		trailLifetime = 0.24,
		trailTransparency = 0.22,
		bobAmplitude = 0.45,
		glowColor = Color3.fromRGB(70, 180, 255),
	},
	Dark = {
		orbSize = 0.72,
		transparency = 0.12,
		lightRange = 7,
		lightBrightness = 1.1,
		trailLifetime = 0.32,
		trailTransparency = 0.28,
		bobAmplitude = 0.70,
		glowColor = Color3.fromRGB(120, 55, 210),
	},
	Default = {
		orbSize = 0.78,
		transparency = 0.12,
		lightRange = 9,
		lightBrightness = 2.0,
		trailLifetime = 0.18,
		trailTransparency = 0.15,
		bobAmplitude = 0.65,
		glowColor = Color3.fromRGB(255, 255, 255),
	},
}

local function getAuraStyle(itemData)
	return auraStyleByElement[itemData and itemData.element] or auraStyleByElement.Default
end

local function destroyActiveAura()
	if not activeAura then return end

	if activeAura.conn then
		activeAura.conn:Disconnect()
		activeAura.conn = nil
	end

	if activeAura.folder then
		activeAura.folder:Destroy()
		activeAura.folder = nil
	end

	activeAura = nil
end

local function makeOrb(folder: Folder, style, index: number, vfxTemplate: Instance?)
	local orb = Instance.new("Part")
	orb.Name = string.format("AuraOrb_%d", index)
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(style.orbSize, style.orbSize, style.orbSize)
	orb.Material = Enum.Material.Neon
	orb.Color = style.glowColor
	orb.Transparency = vfxTemplate and 1.0 or style.transparency -- [FIX] VFX가 있으면 기존 구체를 투명하게 처리
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = style.glowColor
	light.Range = style.lightRange
	light.Brightness = style.lightBrightness
	light.Enabled = (vfxTemplate == nil) -- [FIX] VFX가 있으면 기본 라이트 비활성화
	light.Parent = orb

	-- [FIX] 지정된 VFX 에셋 복제 및 웰드 부착
	if vfxTemplate then
		local vfxClone = vfxTemplate:Clone()
		vfxClone.Name = "VFX"
		if vfxClone:IsA("Model") then
			vfxClone:PivotTo(orb.CFrame)
			for _, desc in ipairs(vfxClone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CanCollide = false
					desc.CanQuery = false
					desc.CanTouch = false
					desc.Anchored = false
					
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = orb
					weld.Part1 = desc
					weld.Parent = desc
				end
			end
		elseif vfxClone:IsA("BasePart") then
			vfxClone.CFrame = orb.CFrame
			vfxClone.CanCollide = false
			vfxClone.CanQuery = false
			vfxClone.CanTouch = false
			vfxClone.Anchored = false
			
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = orb
			weld.Part1 = vfxClone
			weld.Parent = vfxClone
		end
		vfxClone.Parent = orb
	end

	return orb
end

local function startAura(data)
	if type(data) ~= "table" or type(data.itemId) ~= "string" then
		return
	end

	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local dataFolder = game:GetService("ReplicatedStorage"):WaitForChild("Data")
	local itemDataModule = require(dataFolder:WaitForChild("ItemData"))

	local itemData
	for _, it in ipairs(itemDataModule) do
		if it.id == data.itemId then
			itemData = it
			break
		end
	end
	if not itemData then
		return
	end

	destroyActiveAura()

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local color = itemData.auraColor or Color3.fromRGB(255, 255, 255)
	local style = getAuraStyle(itemData)
	style = {
		orbSize = style.orbSize,
		transparency = style.transparency,
		lightRange = style.lightRange,
		lightBrightness = style.lightBrightness,
		trailLifetime = style.trailLifetime,
		trailTransparency = style.trailTransparency,
		bobAmplitude = style.bobAmplitude,
		glowColor = itemData.auraColor or style.glowColor,
	}
	local orbCount = math.max(1, tonumber(itemData.auraOrbCount) or 3)
	local radius = tonumber(data.radius or itemData.auraRadius) or 8
	local duration = tonumber(data.duration or itemData.auraDuration) or 8
	local orbitSpeed = tonumber(itemData.auraOrbitSpeed) or 2

	-- [FIX] Assets/VFX/Cast/Aura_속성명 에셋 유무 확인
	local vfxTemplate = nil
	local vfxFolder = assets and assets:FindFirstChild("VFX")
	local castFolder = vfxFolder and vfxFolder:FindFirstChild("Cast")
	if castFolder and (itemData.element == "Fire" or itemData.element == "Water" or itemData.element == "Dark") then
		vfxTemplate = castFolder:FindFirstChild("Aura_" .. itemData.element)
	end

	local folder = Instance.new("Folder")
	folder.Name = "__RuneAuraVisuals"
	folder.Parent = workspace

	local orbs = {}
	for i = 1, orbCount do
		orbs[i] = makeOrb(folder, style, i, vfxTemplate)

		-- [FIX] 지정된 VFX 에셋이 없을 때만 기본 꼬리(Trail)를 생성하여 투명성 보장
		if not vfxTemplate then
			local backAttachment = Instance.new("Attachment")
			backAttachment.Name = "TrailBack"
			backAttachment.Position = Vector3.new(-0.3, 0, 0)
			backAttachment.Parent = orbs[i]

			local frontAttachment = Instance.new("Attachment")
			frontAttachment.Name = "TrailFront"
			frontAttachment.Position = Vector3.new(0.3, 0, 0)
			frontAttachment.Parent = orbs[i]

			local trail = Instance.new("Trail")
			trail.Attachment0 = backAttachment
			trail.Attachment1 = frontAttachment
			trail.Color = ColorSequence.new(style.glowColor)
			trail.Lifetime = style.trailLifetime
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, style.trailTransparency),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Parent = orbs[i]
		end
	end

	activeAura = {
		itemId = data.itemId,
		folder = folder,
		orbs = orbs,
		startTime = os.clock(),
		duration = duration,
		radius = radius,
		orbitSpeed = orbitSpeed,
	}

	activeAura.conn = RunService.RenderStepped:Connect(function()
		local currentChar = player.Character
		local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
		local hum = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
		if not currentChar or not currentHrp or not hum or hum.Health <= 0 then
			destroyActiveAura()
			return
		end

		if os.clock() - activeAura.startTime >= activeAura.duration then
			destroyActiveAura()
			return
		end

		local elapsed = os.clock() - activeAura.startTime
		local baseAngle = elapsed * activeAura.orbitSpeed
		local count = math.max(1, #activeAura.orbs)
		for index, orb in ipairs(activeAura.orbs) do
			if orb and orb.Parent then
				local offsetAngle = baseAngle + ((index - 1) * ((math.pi * 2) / count))
				local yOffset = math.sin(elapsed * 2 + index) * style.bobAmplitude + 0.8
				local pos = currentHrp.Position + Vector3.new(
					math.cos(offsetAngle) * activeAura.radius,
					yOffset,
					math.sin(offsetAngle) * activeAura.radius
				)
				local pulse = 1 + (math.sin(elapsed * 5 + index) * 0.08)
				orb.Size = Vector3.new(style.orbSize * pulse, style.orbSize * pulse, style.orbSize * pulse)
				orb.CFrame = CFrame.new(pos)
			end
		end
	end)
end

local function stopAura(data)
	if not activeAura then return end
	if type(data) == "table" and type(data.itemId) == "string" and activeAura.itemId ~= data.itemId then
		return
	end
	destroyActiveAura()
end

function RuneAuraController.Init()
	if initialized then return end
	initialized = true

	NetClient.On("Rune.Aura.Start", startAura)
	NetClient.On("Rune.Aura.Stop", stopAura)

	player.CharacterAdded:Connect(function()
		destroyActiveAura()
	end)

	print("[RuneAuraController] Initialized")
end

return RuneAuraController
