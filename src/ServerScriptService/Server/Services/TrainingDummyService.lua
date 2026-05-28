-- TrainingDummyService.lua
-- 시작 마을 허수아비(훈련용 더미) 시스템
-- Workspace/StartVillage/Training 폴더 하위의 "Training" MeshPart들을 자동 모델링하여
-- 플레이어가 타격 시 총합 대미지 및 DPS를 실시간으로 갱신 표기하고, 5초간 타격이 없으면 초기화합니다.

local TrainingDummyService = {}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local initialized = false
local dummies = {} -- Model -> DummyStateData Table

-- BillboardGui 생성 함수
local function createDummyUI(parentPart)
	local bb = Instance.new("BillboardGui")
	bb.Name = "DummyUI"
	bb.Size = UDim2.new(0, 140, 0, 50)
	bb.StudsOffset = Vector3.new(0, parentPart.Size.Y / 2 + 1.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 50
	
	-- 배경 패널
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	bg.BackgroundTransparency = 1 -- [완전 투명 처리]
	bg.BorderSizePixel = 0
	bg.Parent = bb
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg
	
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(35, 55, 115) -- [남색 테두리 보존하되 평소엔 투명]
	stroke.Transparency = 1 -- 평소에는 투명하게
	stroke.Parent = bg
	
	-- 타이틀 이름표
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.new(0, 0, 0.08, 0)
	title.BackgroundTransparency = 1
	title.Text = "훈련용 허수아비" -- [이모티콘 소거]
	title.TextColor3 = Color3.fromRGB(255, 240, 200)
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 13
	title.Parent = bg
	
	-- 수치 출력 라벨
	local stats = Instance.new("TextLabel")
	stats.Name = "StatsLabel"
	stats.Size = UDim2.new(1, 0, 0.45, 0)
	stats.Position = UDim2.new(0, 0, 0.48, 0)
	stats.BackgroundTransparency = 1
	stats.Text = "DMG: 0  |  DPS: 0" -- [대미지 -> DMG 교체]
	stats.TextColor3 = Color3.fromRGB(255, 255, 255)
	stats.Font = Enum.Font.SourceSansBold
	stats.TextSize = 12
	stats.Parent = bg
	
	bb.Parent = parentPart
	return stats
end

-- 허수아비 세팅 함수
local function setupDummy(meshPart)
	if meshPart:GetAttribute("IsDummyConfigured") then return end
	meshPart:SetAttribute("IsDummyConfigured", true)
	
	-- 물리 충돌 및 앵커링 확보 (움직이지 않고 공중에 잘 고정되게 함)
	meshPart.Anchored = true
	meshPart.CanCollide = true
	
	-- 1. 메쉬 파트를 포장할 Model 생성
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	model.Parent = meshPart.Parent
	
	-- 메쉬파트를 모델 하위로 이동
	meshPart.Parent = model
	model.PrimaryPart = meshPart
	
	-- 2. Humanoid 생성 및 세팅 (기존 Combat/Attack 시스템이 타격 대상으로 완벽 인식하도록 주입)
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 99999999
	hum.Health = hum.MaxHealth
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = model
	
	-- 3. BillboardGui UI 생성
	local statsLabel = createDummyUI(meshPart)
	
	-- 허수아비 상태 데이터 기록
	local state = {
		model = model,
		part = meshPart,
		humanoid = hum,
		statsLabel = statsLabel,
		totalDamage = 0,
		firstHitTime = nil,
		lastHitTime = 0,
		isResetting = false,
		playerHits = {} -- [ADDED] 플레이어 UserId -> 연속 타격 수 매핑
	}
	dummies[model] = state
	
	-- 몬스터 인식 Attribute 설정
	model:SetAttribute("MaxHealth", hum.MaxHealth)
	model:SetAttribute("CurrentHealth", hum.MaxHealth)
	model:SetAttribute("MobId", "TrainingDummy")
	
	-- 4. 데미지 감지 이벤트 연결
	local lastHealth = hum.MaxHealth
	hum.HealthChanged:Connect(function(health)
		if health < lastHealth then
			local damage = lastHealth - health
			lastHealth = hum.MaxHealth
			hum.Health = hum.MaxHealth -- 즉시 체력 풀피로 힐 (무한 타격 지원)
			
			local now = os.clock()
			
			-- 첫 타격 타이머 가동
			if not state.firstHitTime then
				state.firstHitTime = now
			end
			
			state.totalDamage = state.totalDamage + damage
			state.lastHitTime = now
			
			-- [연속 타격 트래킹 및 보상 로직]
			local creatorTag = hum:FindFirstChild("creator")
			local attacker = creatorTag and creatorTag.Value
			if attacker and attacker:IsA("Player") then
				local userId = attacker.UserId
				state.playerHits[userId] = (state.playerHits[userId] or 0) + 1
				local hits = state.playerHits[userId]
				
				-- 100회 도달 시 보상 지급 루틴 가동
				if hits == 100 then
					task.spawn(function()
						local InventoryService = require(game:GetService("ServerScriptService").Server.Services.InventoryService)
						
						-- 중복 획득 검사 함수 (인벤토리 및 장치창 전체 스캔)
						local function playerHasGritRune(uId)
							local inv = InventoryService.getInventory(uId)
							if not inv then return false end
							
							if inv.equipment then
								for _, equip in pairs(inv.equipment) do
									if equip and equip.itemId == "GRIT_RUNE" then
										return true
									end
								end
							end
							
							if inv.slots then
								for _, slotData in pairs(inv.slots) do
									if slotData and slotData.itemId == "GRIT_RUNE" then
										return true
									end
								end
							end
							
							return false
						end
						
						if not playerHasGritRune(userId) then
							local added, remaining = InventoryService.addItem(userId, "GRIT_RUNE", 1)
							local NetController = require(game:GetService("ServerScriptService").Server.Controllers.NetController)
							
							if added > 0 then
								if NetController then
									NetController.FireClient(attacker, "Notify.Message", {
										text = "축하합니다! 허수아비 100회 연속 타격으로 [근성]을 획득했습니다!",
										color = "GOLD"
									})
								end
								print(string.format("[TrainingDummyService] Granted GRIT_RUNE to player %s (%d)", attacker.Name, userId))
							else
								if NetController then
									NetController.FireClient(attacker, "Notify.Message", {
										text = "인벤토리가 가득 차서 [근성]을 획득하지 못했습니다. 인벤토리를 비우고 다시 시도해 주세요.",
										color = "RED"
									})
								end
								-- 획득 실패 시 다음 타격으로 다시 시도할 수 있도록 99타로 복구
								state.playerHits[userId] = 99
							end
						else
							-- 이미 보유한 경우 조용히 처리 (중복 획득 메시지 미출력)
							print(string.format("[TrainingDummyService] Player %s (%d) already has GRIT_RUNE. Silently skipping.", attacker.Name, userId))
						end
					end)
				end
			end
			
			-- 실시간 DPS 계산
			local elapsed = now - state.firstHitTime
			if elapsed < 0.1 then elapsed = 0.1 end -- 분모 0 방지
			local dps = math.floor(state.totalDamage / elapsed)
			
			-- UI 텍스트 업데이트
			statsLabel.Text = string.format("DMG: %d  |  DPS: %d", math.floor(state.totalDamage), dps) -- [대미지 -> DMG 교체]
			
			-- [실시간 대미지 연출] 타격 시 메쉬 파트가 붉게 빛남 (Highlight 연출)
			local highlight = state.model:FindFirstChild("HitHighlight")
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.Name = "HitHighlight"
				highlight.FillTransparency = 1
				highlight.OutlineTransparency = 1
				highlight.Parent = state.model
			end
			
			highlight.FillColor = Color3.fromRGB(255, 100, 100)
			highlight.FillTransparency = 0.5
			
			TweenService:Create(highlight, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false), {
				FillTransparency = 1
			}):Play()
			
			-- 5초 무타격 시 자동 리셋 루틴 작동
			if not state.isResetting then
				state.isResetting = true
				task.spawn(function()
					while os.clock() - state.lastHitTime < 5.0 do
						task.wait(0.5)
					end
					
					-- 5초 경과 시 초기화
					state.totalDamage = 0
					state.firstHitTime = nil
					state.isResetting = false
					state.playerHits = {} -- [ADDED] 연속 타격 횟수 초기화
					statsLabel.Text = "DMG: 0  |  DPS: 0" -- [대미지 -> DMG 교체]
					
					-- 초기화 완료 시 메쉬 파트가 부드러운 녹색으로 빛남
					local highlight = state.model:FindFirstChild("HitHighlight")
					if not highlight then
						highlight = Instance.new("Highlight")
						highlight.Name = "HitHighlight"
						highlight.OutlineTransparency = 1
						highlight.Parent = state.model
					end
					
					highlight.FillColor = Color3.fromRGB(80, 220, 100)
					highlight.FillTransparency = 0.5
					
					TweenService:Create(highlight, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false), {
						FillTransparency = 1
					}):Play()
					
					print(string.format("[TrainingDummyService] Dummy stats reset completed."))
				end)
			end
		end
	end)
end

-- NPC 스캔 및 폴더 내 모든 Training 메쉬 감지
local function scanDummies()
	local startVillage = Workspace:FindFirstChild("StartVillage")
	local trainingFolder = startVillage and startVillage:FindFirstChild("Training")
	
	if trainingFolder then
		for _, child in ipairs(trainingFolder:GetChildren()) do
			if child:IsA("MeshPart") and child.Name == "Training" then
				setupDummy(child)
			end
		end
		
		-- 스트리밍 대비 동적 노드 감지
		trainingFolder.ChildAdded:Connect(function(child)
			if child:IsA("MeshPart") and child.Name == "Training" then
				task.defer(function()
					setupDummy(child)
				end)
			end
		end)
		print("[TrainingDummyService] Scanning completed in StartVillage/Training folder.")
	else
		warn("[TrainingDummyService] 'Workspace/StartVillage/Training' folder not found yet. Awaiting folder...")
		-- 폴더가 나중에 생성되는 예외적인 케이스 대응
		task.spawn(function()
			local folder = Workspace:WaitForChild("StartVillage", 10)
			if folder then
				local tr = folder:WaitForChild("Training", 10)
				if tr then
					for _, child in ipairs(tr:GetChildren()) do
						if child:IsA("MeshPart") and child.Name == "Training" then
							setupDummy(child)
						end
					end
					tr.ChildAdded:Connect(function(child)
						if child:IsA("MeshPart") and child.Name == "Training" then
							task.defer(function()
								setupDummy(child)
							end)
						end
					end)
				end
			end
		end)
	end
end

function TrainingDummyService.Init(netController)
	if initialized then return end
	initialized = true
	
	scanDummies()
	print("[TrainingDummyService] System successfully initialized.")
end

return TrainingDummyService
