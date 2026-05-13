-- AvatarService.lua
-- 아바타 원소 검술 RPG: 원소 선택, 실물 나무검(Accessory) 장착 및 서버 타격 권한 판정
-- [100% Server-Authoritative & Real Accessory-Based Weapon System]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
-- [MODIFIED] DEFERRED require to BREAK CIRCULAR DEPENDENCY CYCLE WITH EQUIPSERVICE
local InventoryService = nil -- Dynamically populated during runtime Init() to unlock module load!

local AvatarService = {}
local playerElements = {} -- playerUserId -> "Fire" / "Water" / "Earth"

local function ensureRemoteEvent(name)
	local parts = string.split(name, ".")
	local parent = ReplicatedStorage
	for i, partName in ipairs(parts) do
		local found = parent:FindFirstChild(partName)
		if not found then
			if i == #parts then found = Instance.new("RemoteEvent") else found = Instance.new("Folder") end
			found.Name = partName
			found.Parent = parent
		end
		parent = found
	end
	return parent
end

-- 캐릭터에 무기 액세서리 (Accessory) 정밀 실시간 장착 함수
local function equipWeaponAccessory(player, weaponName)
	local char = player.Character
	if not char then return end

	-- [대분류 기반 구조 검색] ReplicatedStorage/Assets/ItemModels/Weapons/...
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local itemModelsFolder = assetsFolder and assetsFolder:FindFirstChild("ItemModels")
	local weaponsFolder = itemModelsFolder and itemModelsFolder:FindFirstChild("Weapons")
	local weaponAsset = nil

	local function cleanStr(s)
		return string.gsub(string.gsub(tostring(s), "%s+", ""), "_", ""):lower()
	end

	-- Phase 1: Smart Search within the Weapons folder directly!
	if weaponsFolder then
		weaponAsset = weaponsFolder:FindFirstChild(weaponName) -- Exact match try first
		if not weaponAsset then
			-- Case-insensitive & underscore insensitive SMART LOCAL SEARCH
			local targetClean = cleanStr(weaponName)
			for _, child in ipairs(weaponsFolder:GetChildren()) do
				if cleanStr(child.Name) == targetClean and (child:IsA("Accessory") or child:IsA("Model") or child:IsA("Tool")) then
					weaponAsset = child
					break
				end
			end
		end
	end

	-- Phase 2: If STILL not found, then resort to Heavy Global Search Failsafe
	if not weaponAsset then
		warn(string.format("[AvatarService] Asset '%s' not found in LOCAL Weapons folder. Initiating HEAVY global search...", weaponName))
		
		local targetClean = cleanStr(weaponName)
		
		-- Scan all of ReplicatedStorage
		for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
			local descClean = cleanStr(desc.Name)
			if descClean == targetClean and (desc:IsA("Accessory") or desc:IsA("Model") or desc:IsA("Tool")) then
				weaponAsset = desc
				print(string.format("[AvatarService] FOUND '%s' via ReplicatedStorage scan: %s", weaponName, desc:GetFullName()))
				break
			end
		end
		
		-- Scan Workspace just in case
		if not weaponAsset then
			for _, desc in ipairs(game.Workspace:GetDescendants()) do
				local descClean = cleanStr(desc.Name)
				if descClean == targetClean and (desc:IsA("Accessory") or desc:IsA("Model") or desc:IsA("Tool")) and not desc:IsDescendantOf(game.Players) then
					weaponAsset = desc
					print(string.format("[AvatarService] FOUND '%s' via Workspace scan: %s", weaponName, desc:GetFullName()))
					break
				end
			end
		end
	end

	-- [MODIFIED] Log absolute failure if nowhere to be found
	if not weaponAsset then
		warn(string.format("[AvatarService] CRITICAL ERROR: Asset '%s' could not be located ANYWHERE in ReplicatedStorage or Workspace!", weaponName))
		return
	end

	-- Re-verify that what we found can be used as an Accessory (or convert if Model/Tool)
	if weaponAsset then
		-- [MODIFIED] Clears ANY previous weapon marked with IsWeaponAccessory to prevent visual overlapping stack
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Accessory") and child:GetAttribute("IsWeaponAccessory") == true then
				child:Destroy()
			end
		end

		local rawClone = weaponAsset:Clone()
		local clone = nil
		
		-- [MODIFIED: DYNAMIC ADAPTATION] Convert Model/Tool to Accessory if necessary
		if rawClone:IsA("Accessory") then
			clone = rawClone
		else
			warn(string.format("[AvatarService] Wrapping non-accessory '%s' (%s) into an Accessory container dynamically.", weaponName, rawClone.ClassName))
			clone = Instance.new("Accessory")
			clone.Name = weaponName
			
			local candidateHandle = rawClone:FindFirstChild("Handle") or rawClone:FindFirstChildWhichIsA("BasePart")
			if candidateHandle then
				candidateHandle.Name = "Handle" -- Ensure consistent name for engine attachment
				-- Migrate children
				for _, child in ipairs(rawClone:GetChildren()) do
					child.Parent = clone
				end
				rawClone:Destroy() -- Cleanup old shell
			else
				warn("[AvatarService] ABORTING RENDER: No handle detected in dynamic adapter.")
				rawClone:Destroy()
				return
			end
		end

		clone:SetAttribute("IsWeaponAccessory", true) -- Tag this accessory for easy management!
		local handle = clone:FindFirstChild("Handle")
		
		-- 1. 물리 오류 방지 가드 (코드에서 강제로 충돌 및 고정 해제)
		if handle and handle:IsA("BasePart") then
			handle.CanCollide = false
			handle.Anchored = false
			
			-- 2. 구형/충돌 스튜디오 Weld 찌꺼기 제거
			for _, child in ipairs(handle:GetChildren()) do
				if child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D") then
					child:Destroy()
				end
			end
		end

		-- 3. 캐릭터 손 부위 물리적 결합을 위해 리깅 로딩 완료 대기 (최대 10초 대기)
		local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if not rightHand then
			local startTime = tick()
			while not rightHand and (tick() - startTime) < 10 and char.Parent do
				task.wait(0.1)
				rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
			end
		end
		
		if not rightHand then
			warn(string.format("[AvatarService] CRITICAL ABORT: Failed to find RightHand for %s after 10s timeout! Cannot equip %s.", player.Name, weaponName))
			return -- Stop processing if no hand exists to prevent client desync and floating parts
		end

		-- 4. 손 어태치먼트 자동 검사 & 동적 복구 공정
		if rightHand then
			local gripAttach = rightHand:FindFirstChild("RightGripAttachment")
			if not gripAttach then
				warn(string.format("[AvatarService] WARNING: RightGripAttachment is missing in %s's hand! Creating one automatically.", player.Name))
				gripAttach = Instance.new("Attachment")
				gripAttach.Name = "RightGripAttachment"
				-- R6 손 끝 보정 오프셋 적용
				if rightHand.Name == "Right Arm" then
					gripAttach.CFrame = CFrame.new(0, -1, 0)
				end
				gripAttach.Parent = rightHand
			end
		end

		-- [Accessory 기반 무기 장착]
		-- 공식 API인 Humanoid:AddAccessory()를 사용하여 RightGripAttachment 결합을 엔진 수준에서 보장합니다!
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:AddAccessory(clone)
		else
			clone.Parent = char
		end

		-- [초강력 울트라 예외 방어코드 (ULTRA FAILSAFE)]
		-- AddAccessory가 내부 엔진 지연/클래식 캐릭터 구조 오류로 자동 용접(AccessoryWeld)을 누락한 경우,
		-- 손 결합점에 직접 완벽한 오프셋 Weld를 동적 수동 빌드하여 100% 손 장착을 보장합니다.
		task.defer(function()
			if clone.Parent and handle and handle.Parent then
				local existingWeld = handle:FindFirstChildOfClass("Weld") 
					or handle:FindFirstChild("AccessoryWeld") 
					or handle:FindFirstChildOfClass("WeldConstraint")
				
				if not existingWeld then
					local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
					if rightHand then
						local handAttach = rightHand:FindFirstChild("RightGripAttachment")
						local handleAttach = handle:FindFirstChild("RightGripAttachment")
						
						local weld = Instance.new("Weld")
						weld.Name = "AccessoryWeld"
						weld.Part0 = handle
						weld.Part1 = rightHand
						
						-- 두 어태치먼트의 상대 오프셋 계산 적용
						if handAttach and handleAttach then
							weld.C0 = handleAttach.CFrame
							weld.C1 = handAttach.CFrame
						else
							weld.C0 = CFrame.new(0, 0, 0)
							weld.C1 = CFrame.new(0, -1, 0) -- R6 기본 끝단 하강 보정 오프셋
						end
						weld.Parent = handle
						print(string.format("[AvatarService] [ULTRA FAILSAFE] Manually created and aligned AccessoryWeld for %s's %s!", player.Name, weaponName))
					end
				end
			end
		end)

		print(string.format("[AvatarService] Real Weapon Accessory [%s] successfully equipped via AddAccessory onto %s's Character!", weaponName, player.Name))
	else
		warn(string.format("[AvatarService] Accessory [%s] not found in ReplicatedStorage.Assets.ItemModels.Weapons! (Please ensure it is an Accessory Instance in Studio!)", weaponName))
	end
end

-- [MODIFIED] Exported publicly for EquipService usage
AvatarService.equipWeaponAccessory = equipWeaponAccessory

function AvatarService.Init()
	print("[AvatarService] Initializing Avatar Element Core Service...")
	
	-- [MODIFIED] Perform lazy-require here to shatter dependency cycles once all modules are loaded!
	if not InventoryService then
		InventoryService = require(Services:WaitForChild("InventoryService"))
	end

	local selectRemote = ensureRemoteEvent("Avatar.SelectElement.Request")
	local attackRemote = ensureRemoteEvent("Avatar.Attack.Request")
	local vfxRemote = ensureRemoteEvent("Avatar.VFX.Hit")
	local openRemote = ensureRemoteEvent("Avatar.OpenSelectionUI")

	-- [속성 선택 스승 NPC 및 원소제단 바인딩 공정]
	task.spawn(function()
		local masters = {
			{ name = "WaterMaster", koreanName = "물 스승", element = "Water", action = "대화하기", object = "수선(Water)의 길" },
			{ name = "FireMaster", koreanName = "불 스승", element = "Fire", action = "대화하기", object = "화선(Fire)의 길" },
			{ name = "EarthMaster", koreanName = "흙 스승", element = "Earth", action = "대화하기", object = "토선(Earth)의 길" }
		}

		local function cleanString(str)
			if not str then return "" end
			return string.lower(string.gsub(str, "%s+", ""))
		end

		local function findNPC(name, koreanName)
			local cleanName = cleanString(name)
			local cleanKorean = cleanString(koreanName)
			
			-- 1차 루트 검색 (공백 제거 비교)
			for _, child in ipairs(workspace:GetChildren()) do
				if child:IsA("Model") then
					local cleanChildName = cleanString(child.Name)
					if cleanChildName == cleanName or cleanChildName == cleanKorean then
						return child
					end
				end
			end
			
			-- 2차 재귀 검색 (공백 제거 비교)
			for _, child in ipairs(workspace:GetDescendants()) do
				if child:IsA("Model") then
					local cleanChildName = cleanString(child.Name)
					if cleanChildName == cleanName or cleanChildName == cleanKorean then
						return child
					end
				end
			end
			
			-- 3차 부분 일치 검색 (Failsafe)
			for _, child in ipairs(workspace:GetDescendants()) do
				if child:IsA("Model") then
					local cleanChildName = cleanString(child.Name)
					if string.find(cleanChildName, "master") or string.find(cleanChildName, "스승") or string.find(cleanChildName, "npc") then
						if string.find(cleanChildName, string.lower(name)) 
							or (string.find(cleanChildName, "fire") and name == "FireMaster")
							or (string.find(cleanChildName, "earth") and name == "EarthMaster")
							or (string.find(cleanChildName, "water") and name == "WaterMaster")
							or (string.find(cleanChildName, "불") and name == "FireMaster")
							or (string.find(cleanChildName, "흙") and name == "EarthMaster")
							or (string.find(cleanChildName, "물") and name == "WaterMaster") then
							return child
						end
					end
				end
			end
			
			return nil
		end

		-- 디버깅용: 워크스페이스 내 모든 모델 이름 출력해서 스승 후보 탐색
		task.spawn(function()
			task.wait(2)
			local foundModels = {}
			for _, child in ipairs(workspace:GetDescendants()) do
				if child:IsA("Model") then
					local lowerName = string.lower(child.Name)
					if string.find(lowerName, "master") or string.find(lowerName, "스승") or string.find(lowerName, "npc") then
						table.insert(foundModels, string.format("'%s'", child.Name))
					end
				end
			end
			print("[AvatarService] Found potential NPC models in Workspace: " .. table.concat(foundModels, ", "))
		end)

		print(string.format("[AvatarService] [DIAGNOSTIC] Initiating binding sequence for %d Master NPCs...", #masters))

		for _, m in ipairs(masters) do
			task.spawn(function()
				print(string.format("[AvatarService] [DIAGNOSTIC] Binding thread started for NPC: %s (%s)", m.name, m.element))
				
				-- 영어 이름 또는 한국어 이름으로 스튜디오 워크스페이스 배치 찾기 (비동기 안전 확보)
				local npc = findNPC(m.name, m.koreanName)
				if not npc then
					local start = os.clock()
					while os.clock() - start < 10 do
						task.wait(0.5)
						npc = findNPC(m.name, m.koreanName)
						if npc then break end
					end
				end

				if npc then
					print(string.format("[AvatarService] [DIAGNOSTIC] Successfully found NPC model in Workspace: '%s'", npc.Name))
					
					-- 모델 내부의 실제 물리 파트(BasePart) 검색 (ProximityPrompt 부모용) - 눈높이인 Head를 최우선으로 지정
					local targetPart = npc:FindFirstChild("Head")
						or npc.PrimaryPart 
						or npc:FindFirstChild("HumanoidRootPart") 
						or npc:FindFirstChild("Torso") 
						or npc:FindFirstChildOfClass("BasePart")
						
					if not targetPart then
						for _, desc in ipairs(npc:GetDescendants()) do
							if desc:IsA("BasePart") then
								targetPart = desc
								break
							end
						end
					end

					-- 기존 레거시 프롬프트 충돌 방지를 위해 완벽 소거
					local oldPrompt = npc:FindFirstChild("DialoguePrompt", true) or npc:FindFirstChildOfClass("ProximityPrompt")
					if oldPrompt then 
						oldPrompt:Destroy() 
						print(string.format("[AvatarService] [DIAGNOSTIC] Cleared old ProximityPrompt from NPC '%s'", npc.Name))
					end

					local prompt = Instance.new("ProximityPrompt")
					prompt.Name = "DialoguePrompt"
					prompt.ActionText = m.koreanName .. "과 " .. m.action
					prompt.ObjectText = m.object
					prompt.HoldDuration = 0.5
					prompt.MaxActivationDistance = 12
					prompt.RequiresLineOfSight = false
					prompt.Enabled = true
					
					if targetPart then
						prompt.Parent = targetPart
						print(string.format("[AvatarService] [DIAGNOSTIC] Successfully bound ProximityPrompt to part '%s' inside NPC '%s'! Position: %s", targetPart.Name, npc.Name, tostring(targetPart.Position)))
					else
						prompt.Parent = npc
						warn(string.format("[AvatarService] [DIAGNOSTIC] WARNING: No BasePart found in NPC '%s'. Parented to Model.", npc.Name))
					end

					prompt.Triggered:Connect(function(user)
						openRemote:FireClient(user, m.element)
						print(string.format("[AvatarService] NPC %s triggered by player: %s. Sent OpenSelectionUI with element: %s", m.koreanName, user.Name, m.element))
					end)
				else
					warn(string.format("[AvatarService] [DIAGNOSTIC] FAILED: Master NPC '%s' ('%s') was NOT found in Workspace after 10s wait!", m.koreanName, m.name))
				end
			end)
		end

		-- 레거시 원소제단 폴백 지원
		local altar = workspace:FindFirstChild("AltarOfElements") 
			or workspace:FindFirstChild("ElementAltar") 
			or workspace:FindFirstChild("Altar", true)

		if altar then
			print(string.format("[AvatarService] Found fallback altar in Workspace: %s", altar:GetFullName()))
			local prompt = altar:FindFirstChildOfClass("ProximityPrompt") or altar:FindFirstChild("ElementSelectPrompt", true)
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "ElementSelectPrompt"
				prompt.ActionText = "속성 선택 (Choose Element)"
				prompt.ObjectText = "원소 제단 (Altar of Elements)"
				prompt.HoldDuration = 0.5
				prompt.MaxActivationDistance = 12
				prompt.Parent = altar:IsA("Model") and (altar.PrimaryPart or altar:FindFirstChildOfClass("BasePart")) or altar
			end

			prompt.Triggered:Connect(function(user)
				openRemote:FireClient(user) -- element 없이 발송 시 기존 전체선택 카드 UI 노출
				print(string.format("[AvatarService] Fallback Altar triggered by player: %s. Sent OpenSelectionUI.", user.Name))
			end)
		end
	end)

	-- 1. 원소 속성 선택 리모트 수신 ➡️ 실물 Knuckle Accessory 장착 연동
	selectRemote.OnServerEvent:Connect(function(player, data)
		if not data or not data.element then return end
		local element = data.element
		
		-- [Data-Driven 직업 검증] ClassData에 속성이 등록되어 있는지 동적으로 확인!
		local classData = DataService.getById("ClassData", element)
		if not classData then return end

		local userId = player.UserId
		playerElements[userId] = element

		player:SetAttribute("Element", element)

		-- [MODIFIED] Removed redundant force-equipping of WoodenStaff. 
		-- The weapon is now loaded organically via the Inventory integration on Spawn!
		local currentWep = player:GetAttribute("EquippedWeapon") or "WOODEN_STAFF"

		print(string.format("[AvatarService] Player %s chosen Element: %s", player.Name, element))
		selectRemote:FireClient(player, {success = true, element = element, weapon = currentWep})
	end)

	-- 2. 플레이어 캐릭터 리스폰(Respawn) 시 무기 액세서리 자동 재장착 핸들링
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			task.wait(0.5) -- Wait for rig assembly
			
			-- [MODIFIED] Integrate with real inventory data! Fetch weapon from actual inventory Hand slot
			local inv = InventoryService.getOrCreateInventory(player.UserId)
			local weaponId = inv and inv.equipment and inv.equipment.HAND and inv.equipment.HAND.itemId
			
			-- Fallback to last recorded attribute only if not found in equipment
			if not weaponId then
				weaponId = player:GetAttribute("EquippedWeapon")
			end

			-- [MODIFIED] Ensure we have a non-empty string and render
			if weaponId and weaponId ~= "" then
				-- Ensure synchronization
				player:SetAttribute("EquippedWeapon", weaponId)
				equipWeaponAccessory(player, weaponId)
				print(string.format("[AvatarService] Spawning %s with persisted weapon: %s", player.Name, weaponId))
			end
		end)
	end)

	-- Bind the logic to existing players if in studio or live rejoin
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			if player.Character then
				task.wait(0.5) -- Stabilization wait
				local inv = InventoryService.getOrCreateInventory(player.UserId)
				local weaponId = inv and inv.equipment and inv.equipment.HAND and inv.equipment.HAND.itemId
				if weaponId and weaponId ~= "" then
					player:SetAttribute("EquippedWeapon", weaponId)
					equipWeaponAccessory(player, weaponId)
				end
			end
		end)
	end

	-- 3. 기본 공격 (LMB) 타격 사거리 및 판정 수신
	attackRemote.OnServerEvent:Connect(function(player, data)
		local userId = player.UserId
		local element = playerElements[userId] or player:GetAttribute("Element")

		local targetModel = data and data.targetModel
		if not targetModel or not targetModel:FindFirstChild("Humanoid") then return end

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local targetHrp = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart

		if hrp and targetHrp then
			local distance = (hrp.Position - targetHrp.Position).Magnitude
			if distance <= 18 then -- [상향] 사거리 12 -> 18 스터드 물리 판정 확대
				-- [Data-Driven 무기 대미지 데이터화]
				-- [최종 고도화] 스텟/치명타 연동 대미지 공식 가동 (PlayerStatService 동적 연동)
				local finalDamage = weaponData and weaponData.baseDamage or 10
				
				-- 1. 스탯 보너스 (공격력 배율) 적용
				local success, PlayerStatService = pcall(function()
					return require(ServerScriptService.Server.Services.PlayerStatService)
				end)
				
				local isCritical = false
				if success and PlayerStatService then
					local calc = PlayerStatService.GetCalculatedStats(userId)
					local attackMult = calc.attackMult or 1.0
					
					-- 무기 데미지 * 스탯 공격력 %
					finalDamage = finalDamage * attackMult
					
					-- 2. 대미지 난수 편차 (Variance) 적용 (±15%)
					local variance = 0.15
					finalDamage = finalDamage * (1 + (math.random() * 2 - 1) * variance)
					
					-- 3. 치명타(Critical) 판정 가동!
					local critChance = calc.critChance or 0
					local critDamageMult = calc.critDamageMult or 0
					
					-- [Failsafe] 기본 치명타 확률 보정 (1% 라도 주는 경우)
					if critChance > 0 and math.random() < critChance then
						isCritical = true
						finalDamage = finalDamage * (1.5 + critDamageMult) -- 기본 크확 1.5배
					end
				end
				
				-- [Data-Driven 클래스/속성 효과 가변 계산]
				local classData = DataService.getById("ClassData", element or "")
				if classData and classData.onHit then
					if classData.onHit.damageModifier then
						finalDamage = finalDamage * classData.onHit.damageModifier
					end
					if classData.onHit.effects then
						for _, eff in ipairs(classData.onHit.effects) do
							local targetObj = eff.target == "Target" and targetModel or player
							if eff.name == "BurnTicks" then
								targetObj:SetAttribute("BurnTicks", eff.value)
							else
								local currentVal = targetObj:GetAttribute(eff.name) or 0
								local newVal = currentVal + eff.value
								if eff.maxClamp then newVal = math.clamp(newVal, 0, eff.maxClamp) end
								targetObj:SetAttribute(eff.name, newVal)
							end
						end
					end
				end

				local dmgTotal = math.max(1, math.floor(finalDamage))
				print(string.format("[AvatarService] Combat Hit Request (Multi-Hit Activated): Player %s -> %s | TotalDmg=%d | Crit=%s", player.Name, targetModel.Name, dmgTotal, tostring(isCritical)))

				-- [디렉티브 반영] 기본 공격 다단히트 배분 조율 (1타: 2대, 2타: 1대, 3타: 1대)
				local comboIndex = data and data.combo or 1
				local numHits = 1
				if comboIndex == 1 then
					numHits = 2
				elseif comboIndex == 2 or comboIndex == 3 then
					numHits = 1
				else
					numHits = 1 -- Fallback
				end
				
				local baseDmg = math.max(1, math.floor(dmgTotal / numHits))
				local lastDmg = math.max(1, dmgTotal - (baseDmg * (numHits - 1)))

				task.spawn(function()
					local hum = targetModel:FindFirstChild("Humanoid")
					for i = 1, numHits do
						if not targetModel or not hum or hum.Health <= 0 then break end
						
						local curDmg = (i == numHits) and lastDmg or baseDmg
						-- 시각적 명시성을 위해 1타 시점에만 Critical 판정을 표시
						local isCurCrit = (i == 1) and isCritical or false 
						
						hum:TakeDamage(curDmg)
						
						-- 각 틱마다 VFX/대미지 숫자를 뿌려주어 타격 쾌감 극대화
						pcall(function()
							-- 타격 좌표에 약간의 난수를 부여해 다단히트 숫자가 겹치지 않고 예쁘게 흩뿌려지도록 처리
							local hitPos = targetHrp.Position + Vector3.new((math.random() - 0.5) * 2.5, (math.random() - 0.5) * 2.5, (math.random() - 0.5) * 2.5)
							vfxRemote:FireAllClients({
								target = targetModel,
								element = element or "None",
								position = hitPos,
								damage = curDmg,
								isCritical = isCurCrit
							})
						end)
						
						if i < numHits then
							task.wait(0.06) -- 초고속 타다닥 타격 딜레이 (60ms)
						end
					end
				end)
			end
		end
	end)
end

return AvatarService
