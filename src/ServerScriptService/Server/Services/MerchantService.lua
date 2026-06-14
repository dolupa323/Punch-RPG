-- MerchantService.lua
-- 잡화상 NPC 상호작용 설정 서비스 (무기 제작, 강화 스승과 동일한 로직)

local MerchantService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local NetController = nil
local initialized = false

local function _attachNpcLabel(root: BasePart, name: string, role: string)
	if not root or root:FindFirstChild("NpcLabel") then return end
	local label = Instance.new("BillboardGui")
	label.Name = "NpcLabel"
	label.Size = UDim2.new(0, 200, 0, 50)
	label.StudsOffset = Vector3.new(0, 4.5, 0)
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

local function setupNPC(npc)
	-- 기존 Prompt가 있으면 무시
	if npc:FindFirstChild("MerchantPrompt", true) then return end
	
	local targetPart = npc:IsA("BasePart") and npc 
		or npc:FindFirstChild("HumanoidRootPart") 
		or npc.PrimaryPart 
		or npc:FindFirstChildWhichIsA("BasePart", true)
		
	if not targetPart then return end
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MerchantPrompt"
	prompt.ActionText = "상호작용"
	prompt.ObjectText = "잡화상"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	
	prompt.Parent = targetPart
	print("[MerchantService] NPC 발견 및 프롬프트 생성 완료: " .. npc.Name .. " (Parent: " .. targetPart.Name .. ")")
	
	_attachNpcLabel(targetPart, "Merchant", "상점")

	prompt.Triggered:Connect(function(player)
		-- 상호작용 시 클라이언트에게 상점 UI 오픈 요청
		if NetController then
			NetController.FireClient(player, "Shop.OpenUI", {
				shopId = "MERCHANT"
			})
		end
	end)
end

function MerchantService.Init(netController)
	if initialized then return end
	initialized = true
	
	NetController = netController
	
	-- 기존에 배치된 NPC 찾기 (이름 검사: Merchant 또는 잡화상)
	for _, child in ipairs(Workspace:GetDescendants()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and (child.Name == "Merchant" or child.Name == "잡화상") then
			setupNPC(child)
		end
	end
	
	-- 나중에 추가되는 NPC 처리 (스트리밍 등 대비)
	Workspace.DescendantAdded:Connect(function(child)
		if (child:IsA("Model") or child:IsA("BasePart")) and (child.Name == "Merchant" or child.Name == "잡화상") then
			task.defer(function()
				setupNPC(child)
			end)
		end
	end)
end

return MerchantService
