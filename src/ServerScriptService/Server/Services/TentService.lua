-- TentService.lua
-- 텐트 모델에 상호작용(ProximityPrompt)을 추가하고, 스폰 지점 지정 처리를 담당합니다.

local TentService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerLifeService = nil
local NetController = nil

local initialized = false
local lastInteractedTent = {}

local function _attachNpcLabel(root: BasePart, name: string, role: string)
	if not root or root:FindFirstChild("NpcLabel") then return end
	local label = Instance.new("BillboardGui")
	label.Name = "NpcLabel"
	label.Size = UDim2.new(0, 200, 0, 50)
	label.StudsOffset = Vector3.new(0, 0.5, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = 80
	label.Parent = root

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.SourceSansBold
	text.TextColor3 = Color3.fromRGB(255, 233, 184)
	text.TextStrokeTransparency = 0.35
	text.Text = string.format("%s\n%s", name, role)
	text.Parent = label
end

local function setupTent(tent)
	if tent:FindFirstChild("TentSpawnPrompt", true) then return end

	local cframe, size = tent:GetBoundingBox()
	
	local promptPart = Instance.new("Part")
	promptPart.Name = "PromptHitbox"
	promptPart.Size = Vector3.new(math.max(size.X, 4), math.max(size.Y, 4), math.max(size.Z, 4))
	promptPart.CFrame = cframe + Vector3.new(0, 4, 0)
	promptPart.Transparency = 1
	promptPart.CanCollide = false
	promptPart.Anchored = true
	promptPart.Parent = tent

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TentSpawnPrompt"
	prompt.ActionText = "해당 캠프에서 스폰"
	prompt.ObjectText = "캠프"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 15
	
	prompt.Parent = promptPart
	_attachNpcLabel(promptPart, "Tent", "해당 캠프에서 스폰")
	print(string.format("[TentService] 텐트 발견 및 프롬프트 생성 완료: %s | Hitbox 좌표: (%.1f, %.1f, %.1f)", tent.Name, promptPart.Position.X, promptPart.Position.Y, promptPart.Position.Z))
	
	prompt.Triggered:Connect(function(player)
		lastInteractedTent[player.UserId] = tent
		if NetController then
			NetController.FireClient(player, "Tent.OpenUI", {})
		end
	end)
end

function TentService.Init(netController)
	if initialized then return end
	initialized = true
	
	NetController = netController
	PlayerLifeService = require(ServerScriptService.Server.Services.PlayerLifeService)
	
	-- 기존에 배치된 텐트 모두 찾기 (위치 무관)
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "Tent" and (desc:IsA("Model") or desc:IsA("BasePart")) then
			setupTent(desc)
		end
	end
	
	-- 나중에 추가되는 텐트 대비
	Workspace.DescendantAdded:Connect(function(child)
		if (child:IsA("Model") or child:IsA("BasePart")) and child.Name == "Tent" then
			task.defer(function()
				setupTent(child)
			end)
		end
	end)
	
	-- 클라이언트로부터 스폰 설정 수락 패킷 수신
	NetController.RegisterHandler("Tent.SetSpawn", function(player, payload)
		local userId = player.UserId
		local targetTent = lastInteractedTent[userId]
		
		if not targetTent or not targetTent.Parent then
			return { success = false, errorCode = "NO_TENT" }
		end
		
		local cframe = targetTent:IsA("Model") and targetTent:GetBoundingBox() or targetTent.CFrame
		local pos = cframe.Position
		local structId = string.format("StaticTent:%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z)
		
		-- 플레이어의 선호 스폰 지점을 특수 ID로 저장
		if PlayerLifeService.setPreferredRespawn then
			local success = PlayerLifeService.setPreferredRespawn(userId, structId)
			if success then
				print(string.format("[TentService] %s 님의 스폰 지점이 특정 텐트(%s)로 설정되었습니다.", player.Name, structId))
				return { success = true }
			else
				return { success = false, errorCode = "SAVE_FAILED" }
			end
		end
		
		return { success = false, errorCode = "INTERNAL_ERROR" }
	end)
end

return TentService
