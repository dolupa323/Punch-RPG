-- SkillController.lua
-- 클라이언트 스킬 트리 컨트롤러
-- 서버 SkillService와 연동하여 해금 상태 관리 및 UI 데이터 제공

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)

local SkillController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 상태 캐시
local unlockedSkills = {}    -- { [skillId] = true }
local combatTreeId = nil     -- "SPEAR" | "BOW" | "AXE" | nil
local spAvailable = 0
local spSpent = 0
local activeSkillSlots = { nil, nil, nil }
local playerLevel = 1

-- 이벤트 리스너
local listeners = {
	skillDataUpdated = {},
}

--========================================
-- Internal
--========================================

local function _fireListeners()
	for _, cb in ipairs(listeners.skillDataUpdated) do
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
			activeSkillSlots = data.activeSkillSlots or { nil, nil, nil }
			playerLevel = data.level or 1
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
-- Event Listeners
--========================================

function SkillController.onSkillDataUpdated(callback: () -> ())
	table.insert(listeners.skillDataUpdated, callback)
end

--========================================
-- Init
--========================================

function SkillController.Init()
	if initialized then return end
	initialized = true

	-- 초기 데이터 로드 (재시도 포함 — 서버 SaveService 로딩 대기 대응)
	task.spawn(function()
		for _attempt = 1, 5 do
			local ok, data = NetClient.Request("Skill.GetData.Request", {})
			if ok and data then
				unlockedSkills = data.unlockedSkills or {}
				combatTreeId = data.combatTreeId
				spAvailable = data.spAvailable or 0
				spSpent = data.spSpent or 0
				activeSkillSlots = data.activeSkillSlots or { nil, nil, nil }
				playerLevel = data.level or 1
				_fireListeners()
				break
			end
			task.wait(2)
		end
	end)

	print("[SkillController] Initialized")
end

return SkillController
