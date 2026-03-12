-- DamageUIController.lua
-- 타격 데미지 및 기절 수치 시각화 (Floating Damage Text)
-- Phase 11-5: 전투 피드백 강화

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local DamageUIController = {}

--========================================
-- Constants
--========================================
local COLORS = {
	NORMAL = Color3.fromRGB(255, 255, 255),  -- 흰색: 일반 데미지
	CRITICAL = Color3.fromRGB(255, 230, 0), -- 노란색: 크리티컬 (기능 확장 대비)
	TORPOR = Color3.fromRGB(180, 100, 255), -- 보라색: 기절 수치
	HEAL = Color3.fromRGB(100, 255, 100),   -- 초록색: 회복
}

local initialized = false

--========================================
-- Private Functions
--========================================

--- 대상 모델 찾기 (속성 기반 검색)
local function findTargetModel(targetId: string): Instance?
	local targetModel = nil
	
	-- 1. 월드 내 대상 검색 (속성 기반 검색으로 정확도 향상)
	for _, folderName in ipairs({"ActiveCreatures", "Creatures", "Facilities", "ResourceNodes"}) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			-- 먼저 이름으로 시도
			local found = folder:FindFirstChild(targetId)
			if found then 
				targetModel = found
				break 
			end
			
			-- 이름으로 못 찾으면 속성 전수 조사 (Streaming 대응)
			for _, child in ipairs(folder:GetChildren()) do
				if child:GetAttribute("InstanceId") == targetId or 
				   child:GetAttribute("NodeUID") == targetId or 
				   child:GetAttribute("StructureId") == targetId then
					targetModel = child
					break
				end
			end
			if targetModel then break end
		end
	end
	
	if not targetModel then 
		-- 마지막 수단: 전체 태그 검색 (ResourceNode 등)
		local CollectionService = game:GetService("CollectionService")
		for _, model in ipairs(CollectionService:GetTagged("ResourceNode")) do
			if model:GetAttribute("NodeUID") == targetId then
				targetModel = model
				break
			end
		end
	end
	
	return targetModel
end

--- 데미지 텍스트 생성 및 애니메이션
local function spawnDamageText(position: Vector3, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageIndicator"
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.Adornee = nil -- World Position 사용
	billboard.AlwaysOnTop = true
	-- 위치 오프셋 (머리 위쪽으로 살짝 띄움)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	
	-- 월드 위치 고정을 위해 보이지 않는 파트 생성
	local attachment = Instance.new("Part")
	attachment.Size = Vector3.new(0.1, 0.1, 0.1)
	attachment.Transparency = 1
	attachment.CanCollide = false
	attachment.Anchored = true
	attachment.Position = position
	attachment.Parent = workspace.CurrentCamera
	
	billboard.Parent = attachment
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Font = Enum.Font.LuckiestGuy -- 강조 느낌의 폰트
	label.TextSize = 24
	label.Parent = billboard
	
	-- 애니메이션: 위로 튀어오르며 페이드아웃
	local targetPos = position + Vector3.new(math.random(-2, 2), 4, math.random(-2, 2))
	local moveTween = TweenService:Create(attachment, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = targetPos
	})
	
	local fadeTween = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.3), {
		TextTransparency = 1,
		TextStrokeTransparency = 1
	})
	
	moveTween:Play()
	fadeTween:Play()
	
	task.delay(1, function()
		attachment:Destroy()
	end)
end

--========================================
-- Public API
--========================================

function DamageUIController.Init()
	if initialized then return end
	
	-- 1. 서버로부터 사냥/전투 타격 결과 수신
	NetClient.On("Combat.Hit.Result", function(data)
		-- data: { damage, torporDamage, killed, targetId }
		
		local targetModel = findTargetModel(data.targetId)
		if not targetModel then return end
		
		local spawnPos = targetModel:GetPivot().Position
		
		-- 일반 데미지 표시
		if data.damage and data.damage > 0 then
			spawnDamageText(spawnPos, string.format("%.0f", data.damage), COLORS.NORMAL)
		end
		
		-- 기절 수치 표시 (보라색)
		if data.torporDamage and data.torporDamage > 0 then
			task.wait(0.1) -- 겹치지 않게 살짝 딜레이
			spawnDamageText(spawnPos, string.format("%.0f", data.torporDamage), COLORS.TORPOR)
		end
	end)
	
	-- 2. 서버로부터 채집 타격 결과 수신
	NetClient.On("Harvest.Node.Hit", function(data)
		-- data: { nodeUID, remainingHits, maxHits, damage }
		if not data.damage or data.damage <= 0 then return end
		
		local targetModel = findTargetModel(data.nodeUID)
		if not targetModel then return end
		
		local spawnPos = targetModel:GetPivot().Position
		spawnDamageText(spawnPos, string.format("%.0f", data.damage), COLORS.NORMAL)
	end)
	
	initialized = true
	print("[DamageUIController] Initialized")
end

return DamageUIController
