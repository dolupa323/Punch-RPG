-- SkillController.lua
-- 클라이언트 스킬 트리 컨트롤러
-- 서버 SkillService와 연동하여 해금 상태 관리 및 UI 데이터 제공

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Controllers = script.Parent
local ClientScripts = Controllers.Parent

local NetClient = require(ClientScripts:WaitForChild("NetClient"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))

local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data:WaitForChild("SkillTreeData"))

local SkillController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 상태 캐시
local unlockedSkills = {}    -- { [skillId] = true }
local combatTreeId = nil     -- "SWORD" | "BOW" | "AXE" | nil
local spAvailable = 0
local spSpent = 0
local activeSkillSlots = { "", "", "", "" }
local playerLevel = 1
local skillBooks = {}
local equippedPassives = {}

-- 액티브 스킬 쿨다운 (클라이언트 예측)
local DEV_NO_COOLDOWN = false -- ★ 개발용 노쿨 해제 (원래대로 복구)
local skillCooldowns = {}     -- { [skillId] = endTime (tick) }
local skillGCD = 0            -- 글로벌 쿨다운 종료 시각

-- 이벤트 리스너
local listeners = {
	skillDataUpdated = {},
	cooldownUpdated = {},
}

--========================================
-- Internal
--========================================

local function _fireListeners()
	for _, cb in ipairs(listeners.skillDataUpdated) do
		pcall(cb)
	end
end

local function _fireCooldownListeners()
	for _, cb in ipairs(listeners.cooldownUpdated) do
		pcall(cb)
	end
end

--========================================
-- Public API: Cache Access
--========================================

function SkillController.getUnlockedSkills()
	return unlockedSkills
end

function SkillController.getCombatTreeId()
	return combatTreeId
end

function SkillController.getSPAvailable()
	return spAvailable
end

function SkillController.getSPSpent()
	return spSpent
end

function SkillController.getActiveSkillSlots()
	return activeSkillSlots
end

function SkillController.getPlayerLevel()
	return playerLevel
end

function SkillController.getSkillBooks()
	return skillBooks
end

function SkillController.getEquippedPassives()
	return equippedPassives
end

function SkillController.isSkillUnlocked(skillId: string): boolean
	return unlockedSkills[skillId] == true
end

--- 스킬 해금 가능 여부 체크 (로컬 판단)
function SkillController.canUnlock(skillId: string): (boolean, string?)
	local skill = SkillTreeData.GetSkill(skillId)
	if not skill then return false, "SKILL_NOT_FOUND" end
	if unlockedSkills[skillId] then return false, "ALREADY_UNLOCKED" end

	-- 레벨 체크
	if playerLevel < skill.reqLevel then return false, "LEVEL_TOO_LOW" end

	-- 건축은 SP 불요
	if skill.type ~= "BUILD_TIER" then
		-- 전투 계열 택1 체크
		local treeId = SkillTreeData.GetTreeIdForSkill(skillId)
		if treeId and SkillTreeData.IsCombatTree(treeId) then
			if combatTreeId and combatTreeId ~= treeId then
				return false, "TREE_LOCKED"
			end
		end
		-- SP 체크
		if spAvailable < skill.spCost then return false, "NOT_ENOUGH_SP" end
	end

	-- 선행 체크
	if skill.prereqs and #skill.prereqs > 0 then
		for _, pid in ipairs(skill.prereqs) do
			if not unlockedSkills[pid] then
				return false, "PREREQS_NOT_MET"
			end
		end
	end

	return true, nil
end

--========================================
-- Server Requests
--========================================

--- 서버에서 스킬 데이터 전체 조회
function SkillController.requestData(callback: ((boolean) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.GetData.Request", {})
		if ok and data then
			unlockedSkills = data.unlockedSkills or {}
			combatTreeId = data.combatTreeId
			spAvailable = data.spAvailable or 0
			spSpent = data.spSpent or 0
			activeSkillSlots = data.activeSkillSlots or { "", "", "", "" }
			playerLevel = data.level or 1
			equippedPassives = data.equippedPassives or {}
			skillBooks = data.skillBooks or {}
			_fireListeners()
		end
		if callback then callback(ok) end
	end)
end

--- 스킬 해금 요청
function SkillController.requestUnlock(skillId: string, callback: ((boolean, string?) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.Unlock.Request", { skillId = skillId })
		if ok and data then
			-- 로컬 캐시 즉시 반영
			unlockedSkills[skillId] = true
			if data.spRemaining ~= nil then
				spAvailable = data.spRemaining
			end
			if data.combatTreeId then
				combatTreeId = data.combatTreeId
			end
			local skill = SkillTreeData.GetSkill(skillId)
			if skill then
				spSpent = spSpent + skill.spCost
			end
			_fireListeners()
		end
		if callback then
			callback(ok, (not ok and data) and tostring(data.errorCode or "UNKNOWN") or nil)
		end
	end)
end

--- 액티브 스킬 슬롯 설정
function SkillController.requestSetSlot(slotIndex: number, skillId: string?, callback: ((boolean) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.SetSlot.Request", { slot = slotIndex, skillId = skillId })
		if ok and data and data.activeSkillSlots then
			activeSkillSlots = data.activeSkillSlots
			_fireListeners()
		end
		if callback then callback(ok) end
	end)
end

--========================================
-- Active Skill Usage (RUNE System)
--========================================

--- 룬 슬롯 이름(RUNE1, RUNE2, RUNE3)으로 스킬 사용
function SkillController.useSkill(slotName: string)
	-- 1. 슬롯 인덱스 매핑
	local slotIndex = nil
	if slotName == "RUNE1" then slotIndex = 1
	elseif slotName == "RUNE2" then slotIndex = 2
	elseif slotName == "RUNE3" then slotIndex = 3
	end
	if not slotIndex then return end
	
	-- 2. 장착된 스킬 ID 확인 (Skill Tree 또는 자동 장착된 룬 스킬)
	local skillId = activeSkillSlots[slotIndex]
	if not skillId or skillId == "" then return end
	
	-- 3. 패시브 룬 시전 차단
	local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
	local itemProfile = nil
	local baseItemId = string.gsub(skillId, "^SKILL_", "")
	if baseItemId == "ROCK" then
		baseItemId = "NIGHT"
	end
	
	for _, it in ipairs(ItemData) do
		if it.id == baseItemId or it.id == skillId then
			itemProfile = it
			break
		end
	end
	if itemProfile and itemProfile.runeType == "PASSIVE" then
		return
	end
	
	-- 2. 로컬 쿨다운 프리체크
	local now = tick()
	if not DEV_NO_COOLDOWN then
		if skillGCD > now then return end
		if skillCooldowns[skillId] and skillCooldowns[skillId] > now then return end
	end
	
	-- 3. 캐릭터 조준 방향 계산 (LookVector)
	local lp = game:GetService("Players").LocalPlayer
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local aimDirection = nil
	local lookVec = Vector3.new(0, 0, -1)
	if hrp then
		lookVec = hrp.CFrame.LookVector
		aimDirection = { x = lookVec.X, y = lookVec.Y, z = lookVec.Z }
	end

	-- 3.5. [클라이언트 선호출] 로컬 사전 애니메이션 사운드 VFX 즉시 발생
	if hrp and not (itemProfile and itemProfile.runeMode == "AURA") then
		local targetCFrame = CFrame.new(hrp.Position, hrp.Position + lookVec)
		local AvatarController = require(Controllers:WaitForChild("AvatarController"))
		if AvatarController and AvatarController.playSkillCast then
			AvatarController.playSkillCast(skillId, hrp, targetCFrame)
		end
	end

	-- 4. 서버 요청
	task.spawn(function()
		local payload = { 
			slot = slotName, 
			itemId = skillId,
			aimDirection = aimDirection
		}
		
		local ok, data = NetClient.Request("Skill.Use.Request", payload)
		
		if ok and data then
			-- 서버에서 받은 쿨다운으로 보정
			if data.cooldown then
				skillCooldowns[skillId] = tick() + data.cooldown
				skillGCD = tick() + 0.5 -- Global Cooldown
			end
		else
			-- 실패 시 로컬 쿨다운 롤백
			skillCooldowns[skillId] = nil
			skillGCD = 0
			
			-- 에러 피드백
			local errorCode = data
			local UIManager = require(ClientScripts:WaitForChild("UIManager"))
			if UIManager and UIManager.notify then
				local msg = "스킬을 사용할 수 없습니다."
				if errorCode == "COOLDOWN" then msg = "재사용 대기 중입니다."
				elseif errorCode == "NOT_EQUIPPED" then msg = "룬이 장착되어 있지 않습니다."
				elseif errorCode == "NOT_ENOUGH_STAMINA" then msg = "마나가 부족합니다."
				elseif errorCode == "INVALID_GROUND" then msg = "나무나 바위 위에서는 사용할 수 없습니다."
				end
				UIManager.notify(msg, Color3.fromRGB(255, 140, 140))
			end
		end
		_fireCooldownListeners()
	end)
end

--- 슬롯 인덱스(1, 2, 3)로 스킬 사용 (UI 및 모바일 대응)
function SkillController.useSkillIndex(slotIndex: number)
	local slotName = "RUNE" .. slotIndex
	SkillController.useSkill(slotName)
end

--- 특정 스킬 잔여 쿨다운 조회 (초)
function SkillController.getSkillCooldownRemaining(skillId: string): number
	local cd = skillCooldowns[skillId]
	if not cd then return 0 end
	local remaining = cd - tick()
	return remaining > 0 and remaining or 0
end

--- 슬롯별 쿨다운 조회
function SkillController.getSlotCooldownRemaining(slotIndex: number): number
	local skillId = activeSkillSlots[slotIndex]
	if not skillId or skillId == "" then return 0 end
	return SkillController.getSkillCooldownRemaining(skillId)
end

--- 룬 슬롯 쿨다운 조회 (액티브 스킬 및 룬 장비 호환)
function SkillController.getRuneCooldownRemaining(slotIndex: number): number
	-- 1. 신규 액티브 스킬 슬롯(스킬북/트리 배운 스킬 장착용) 우선 확인
	if activeSkillSlots and activeSkillSlots[slotIndex] and activeSkillSlots[slotIndex] ~= "" then
		local skillId = activeSkillSlots[slotIndex]
		local cd = SkillController.getSkillCooldownRemaining(skillId)
		if cd > 0 then
			return cd
		end
	end

	-- 2. 레거시 룬 장착 아이템 쿨다운 폴백
	local equipment = InventoryController.getEquipment()
	local slotKey = "RUNE" .. slotIndex
	local eqItem = equipment[slotKey]
	if not eqItem or not eqItem.itemId then return 0 end
	return SkillController.getSkillCooldownRemaining(eqItem.itemId)
end

--- 패시브 룬 스킬이 장착되어 있는지 확인
function SkillController.hasPassiveRuneEquipped(skillId: string): boolean
	for k, v in pairs(equippedPassives) do
		if v == skillId then
			return true
		end
	end
	return false
end

--- 특정 스킬이 사용 가능한지 체크
function SkillController.canUseSkill(skillId: string): boolean
	return SkillController.getSkillCooldownRemaining(skillId) <= 0
end

--========================================
-- Event Listeners
--========================================

function SkillController.onSkillDataUpdated(callback: () -> ())
	table.insert(listeners.skillDataUpdated, callback)
end

function SkillController.onCooldownUpdated(callback: () -> ())
	table.insert(listeners.cooldownUpdated, callback)
end

--========================================
-- [DEV] SP 초기화
--========================================

function SkillController.requestReset(callback: ((boolean) -> ())?)
	task.spawn(function()
		print("[SkillController] Requesting SP reset...")
		local ok, data = NetClient.Request("Skill.Reset.Request", {})
		print("[SkillController] Reset response:", ok, data)
		if ok and data then
			unlockedSkills = data.unlockedSkills or {}
			combatTreeId = data.combatTreeId
			spAvailable = data.spAvailable or 0
			spSpent = data.spSpent or 0
			activeSkillSlots = data.activeSkillSlots or { "", "", "", "" }
			playerLevel = data.level or 1
			_fireListeners()
			
			local UIManager = require(ClientScripts:WaitForChild("UIManager"))
			if UIManager and UIManager.notify then
				UIManager.notify("스킬 트리 초기화 완료! 소모 SP가 모두 환급되었습니다.", Color3.fromRGB(100, 255, 100))
			end
		else
			if data == "NO_ITEM" or (type(data) == "table" and data.errorCode == "NO_ITEM") then
				local UIManager = require(ClientScripts:WaitForChild("UIManager"))
				if UIManager and UIManager.notify then
					UIManager.notify("스킬초기화권이 필요합니다.", Color3.fromRGB(255, 120, 120))
				end
				if callback then callback(false) end
				return
			end
			
			local UIManager = require(ClientScripts:WaitForChild("UIManager"))
			if UIManager and UIManager.notify then
				local errMsg = "스킬 초기화에 실패했습니다."
				if type(data) == "table" and data.message then
					errMsg = data.message
				elseif type(data) == "string" then
					errMsg = data
				end
				UIManager.notify(errMsg, Color3.fromRGB(255, 120, 120))
			end
		end
		if callback then callback(ok) end
	end)
end

--- 스킬북 학습 요청
function SkillController.requestLearnBook(bookItemId: string, callback: ((boolean, string?) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.LearnBook.Request", { bookItemId = bookItemId })
		if ok then
			unlockedSkills = data.unlockedSkills or unlockedSkills
			skillBooks = data.skillBooks or skillBooks
			_fireListeners()
			if callback then callback(true, nil) end
		else
			if callback then callback(false, tostring(data or "UNKNOWN")) end
		end
	end)
end

--- 패시브 스킬 장착 요청
function SkillController.requestEquipPassive(skillId: string, slot: number, callback: ((boolean, string?) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.EquipPassive.Request", { skillId = skillId, slot = slot })
		if ok and data then
			-- ok가 true이면 서버에서 성공 처리됨 (data는 result.data 즉 { equippedPassives = ... })
			if data.equippedPassives then
				equippedPassives = data.equippedPassives
				_fireListeners()
			end
			if callback then callback(true, nil) end
		else
			if callback then callback(false, tostring(data or "UNKNOWN")) end
		end
	end)
end

--- 패시브 스킬 해제 요청
function SkillController.requestUnequipPassive(slot: number, callback: ((boolean, string?) -> ())?)
	task.spawn(function()
		local ok, data = NetClient.Request("Skill.UnequipPassive.Request", { slot = slot })
		if ok and data then
			if data.equippedPassives then
				equippedPassives = data.equippedPassives
				_fireListeners()
			end
			if callback then callback(true, nil) end
		else
			if callback then callback(false, tostring(data or "UNKNOWN")) end
		end
	end)
end



--========================================
-- Init
--========================================

function SkillController.Init()
	if initialized then return end
	initialized = true

	-- 초기 데이터 로드 (재시도 포함 — 서버 SaveService 로딩 대기 대응)
	task.spawn(function()
		local player = game:GetService("Players").LocalPlayer
		while not player:GetAttribute("DataLoaded") do task.wait(0.2) end
		
		for _attempt = 1, 15 do
			local ok, data = NetClient.Request("Skill.GetData.Request", {})
			if ok and data then
				unlockedSkills = data.unlockedSkills or {}
				combatTreeId = data.combatTreeId
				spAvailable = data.spAvailable or 0
				spSpent = data.spSpent or 0
				activeSkillSlots = data.activeSkillSlots or { "", "", "", "" }
				playerLevel = data.level or 1
				skillBooks = data.skillBooks or {}
				equippedPassives = data.equippedPassives or {}
				_fireListeners()
				local player = game:GetService("Players").LocalPlayer
				if player then player:SetAttribute("SkillLoaded", true) end
				break
			end
			task.wait(2)
		end
	end)

	-- Key Bindings (Q, E, R, T)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		
		if input.KeyCode == Enum.KeyCode.E then
			SkillController.useSkill("RUNE1")
		elseif input.KeyCode == Enum.KeyCode.R then
			SkillController.useSkill("RUNE2")
		elseif input.KeyCode == Enum.KeyCode.T then
			SkillController.useSkill("RUNE3")
		end
	end)
	
	NetClient.On("Skill.Data.Updated", function(data)
		if data then
			unlockedSkills = data.unlockedSkills or {}
			combatTreeId = data.combatTreeId
			spAvailable = data.spAvailable or 0
			spSpent = data.spSpent or 0
			activeSkillSlots = data.activeSkillSlots or { "", "", "", "" }
			playerLevel = data.level or 1
			skillBooks = data.skillBooks or {}
			equippedPassives = data.equippedPassives or {}
			_fireListeners()
			print("[SkillController] Received Skill.Data.Updated and refreshed local cache!")
		end
	end)

	print("[SkillController] Initialized with RUNE bindings (E, R, T)")
end

return SkillController
