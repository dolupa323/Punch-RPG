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

local function removeLegacyElementMasters()
	local targetNames = {
		WaterMaster = true,
		FireMaster = true,
		DarkMaster = true,
		["물 스승"] = true,
		["불 스승"] = true,
		["어둠 스승"] = true,
	}

	for _, inst in ipairs(workspace:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and targetNames[inst.Name] then
			inst:Destroy()
		end
	end
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
	print("[AvatarService] Initializing Avatar Combat Service...")
	
	-- [MODIFIED] Perform lazy-require here to shatter dependency cycles once all modules are loaded!
	if not InventoryService then
		InventoryService = require(Services:WaitForChild("InventoryService"))
	end

	removeLegacyElementMasters()

	local attackRemote = ensureRemoteEvent("Avatar.Attack.Request")
	local vfxRemote = ensureRemoteEvent("Avatar.VFX.Hit")
	ensureRemoteEvent("Avatar.OpenSelectionUI")
	ensureRemoteEvent("Avatar.SelectElement.Request")

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

		local targetModel = data and data.targetModel
		if not targetModel or not targetModel:FindFirstChild("Humanoid") then return end

		-- PvP 차단: 타겟이 플레이어 캐릭터면 무시
		if Players:GetPlayerFromCharacter(targetModel) then return end

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local targetHrp = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart

		if hrp and targetHrp then
			local distance = (hrp.Position - targetHrp.Position).Magnitude
			if distance <= 18 then -- [상향] 사거리 12 -> 18 스터드 물리 판정 확대
				-- [Data-Driven 무기 대미지 데이터화]
				-- [최종 고도화] 스텟/치명타 연동 대미지 공식 가동 (PlayerStatService 동적 연동)
				local equipment = InventoryService and InventoryService.getEquipment(userId)
				local equippedWeapon = equipment and equipment.HAND
				local weaponBase = equippedWeapon and DataService.getItem(equippedWeapon.itemId)
				local weaponDmg = weaponBase and (weaponBase.damage or weaponBase.baseDamage) or 0
				local baseDamage = weaponDmg
				
				if equippedWeapon then
					local quality = (equippedWeapon.attributes and equippedWeapon.attributes.quality) or 100
					baseDamage = math.floor(baseDamage * (quality / 100))
				end
				
				-- Apply +15% damage bonus per enhancement level
				local enhanceLevel = equippedWeapon and equippedWeapon.attributes and equippedWeapon.attributes.enhanceLevel or 0
				local DataHelper = require(game:GetService("ReplicatedStorage").Shared.Util.DataHelper)
				local bonusRate = DataHelper.GetEnhanceBonusRate(weaponBase and weaponBase.rarity or "COMMON")
				local finalDamage = baseDamage * (1 + enhanceLevel * bonusRate)
				
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
				
				local dmgTotal = math.max(1, math.floor(finalDamage))
				print(string.format("[AvatarService] Combat Hit Request: Player %s -> %s | TotalDmg=%d | Crit=%s", player.Name, targetModel.Name, dmgTotal, tostring(isCritical)))

				-- [디렉티브 반영] 기본 공격 다단히트 배분 조율: 정직하게 1타격당 1회 데미지 적용
				local comboIndex = data and data.combo or 1
				local numHits = 1
				
				local baseDmg = dmgTotal
				local lastDmg = dmgTotal

				task.spawn(function()
					local hum = targetModel:FindFirstChild("Humanoid")
					for i = 1, numHits do
						if not targetModel or not hum or hum.Health <= 0 then break end
						
						local curDmg = (i == numHits) and lastDmg or baseDmg
						local isCurCrit = (i == 1) and isCritical or false 
						-- [기획 보강]: creator 태그 생성하여 킬러 플레이어 추적 보장!
						local tag = hum:FindFirstChild("creator")
						if tag then tag:Destroy() end
						
						tag = Instance.new("ObjectValue")
						tag.Name = "creator"
						tag.Value = player
						tag.Parent = hum
						game:GetService("Debris"):AddItem(tag, 4) -- 4초간 안전하게 유지
						
						-- Apply player vs monster level difference damage scaling
						local finalCurDmg = curDmg
						local mobLevel = targetModel:GetAttribute("Level") or 1
						local playerLevel = 1
						if PlayerStatService and PlayerStatService.getLevel then
							playerLevel = PlayerStatService.getLevel(player.UserId) or 1
						end

						if playerLevel > mobLevel then
							local diff = playerLevel - mobLevel
							finalCurDmg = finalCurDmg * (1 + (diff * 0.05))
						elseif playerLevel < mobLevel then
							local diff = mobLevel - playerLevel
							finalCurDmg = finalCurDmg * math.max(0.01, 1 - diff * 0.1)
						end
						finalCurDmg = math.max(1, math.floor(finalCurDmg + 0.5))

						hum:TakeDamage(finalCurDmg)
						
						-- Sync visual damage for clients
						curDmg = finalCurDmg
						
						-- [XP Granting] 처치 시 경험치 지급 로직 직접 구현 (래거시 의존성 제거)
						if hum.Health <= 0 then
							local xpReward = targetModel:GetAttribute("XPReward") or 25
							if PlayerStatService and PlayerStatService.grantActionXP then
								local mobId = targetModel:GetAttribute("MobId") or targetModel.Name
								PlayerStatService.grantActionXP(player.UserId, xpReward, {
									source = "CREATURE_KILL",
									actionKey = "MOB:" .. tostring(mobId),
									disableDiminishing = true -- [밸런스 보장]: 몬스터 처치 경험치는 반복 획득 시에도 감쇠율 면제! 100% RAW 지급 보장!
								})
								print(string.format("[AvatarService] Player %s killed %s! XP Granted (Full): %d", player.Name, targetModel.Name, xpReward))
							end
						end
						
						-- 각 틱마다 VFX/대미지 숫자를 뿌려주어 타격 쾌감 극대화
						pcall(function()
							-- 타격 좌표에 약간의 난수를 부여해 다단히트 숫자가 겹치지 않고 예쁘게 흩뿌려지도록 처리
							local hitPos = targetHrp.Position + Vector3.new((math.random() - 0.5) * 2.5, (math.random() - 0.5) * 2.5, (math.random() - 0.5) * 2.5)
							-- VFX(이펙트)는 모든 클라이언트에게 전송 (damage 제외)
							vfxRemote:FireAllClients({
								target = targetModel,
								element = "None",
								position = hitPos,
								hideVfx = false,
							})
							-- 데미지 숫자는 공격한 플레이어 본인에게만 전송
							vfxRemote:FireClient(player, {
								target = targetModel,
								element = "None",
								position = hitPos,
								damage = curDmg,
								isCritical = isCurCrit,
								hideVfx = true, -- VFX는 이미 위에서 전송했으므로 중복 생성 방지
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
