-- WeaponCrafterService.lua
-- 무기 장인 NPC 스크립트. Workspace에 "WeaponCrafter"라는 이름의 모델이 배치되면
-- 자동으로 제작 상호작용(ProximityPrompt)을 추가하고 무기 제작을 처리합니다.
-- 향후 여러 무기로 확장될 수 있도록 설계되었습니다.

local WeaponCrafterService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local InventoryService = require(ServerScriptService.Server.Services.InventoryService)
local NetController = nil

local initialized = false

local function setupNPC(npc)
	-- 기존 Prompt가 있으면 무시
	if npc:FindFirstChild("WeaponCrafterPrompt", true) then return end
	
	-- 모델이면 내부 파트를 찾고, 단일 파트(MeshPart 등)면 자신에게 직접 붙임
	local targetPart = npc:IsA("BasePart") and npc 
		or npc:FindFirstChild("HumanoidRootPart") 
		or npc.PrimaryPart 
		or npc:FindFirstChildWhichIsA("BasePart", true)
		
	if not targetPart then return end
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WeaponCrafterPrompt"
	prompt.ActionText = "무기 제작"
	prompt.ObjectText = "무기 장인"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	
	prompt.Parent = targetPart
	print("[WeaponCrafterService] NPC 발견 및 프롬프트 생성 완료: " .. npc.Name .. " (Parent: " .. targetPart.Name .. ")")
	
	prompt.Triggered:Connect(function(player)
		-- 상호작용 시 클라이언트에게 UI 오픈 요청
		if NetController then
			NetController.FireClient(player, "WeaponCrafter.OpenUI", {
				npcName = "WeaponCrafter"
			})
		end
	end)
end

function WeaponCrafterService.Init(netController)
	if initialized then return end
	initialized = true
	
	NetController = netController
	
	-- 기존에 배치된 NPC 찾기
	for _, child in ipairs(Workspace:GetDescendants()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and child.Name == "WeaponCrafter" then
			setupNPC(child)
		end
	end
	
	-- 나중에 추가되는 NPC 처리 (스트리밍 등 대비)
	Workspace.DescendantAdded:Connect(function(child)
		if (child:IsA("Model") or child:IsA("BasePart")) and child.Name == "WeaponCrafter" then
			-- 모델 내용물이 다 로드될 때까지 약간 대기
			task.defer(function()
				setupNPC(child)
			end)
		end
	end)
end

return WeaponCrafterService
