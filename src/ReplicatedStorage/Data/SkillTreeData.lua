-- SkillTreeData.lua
-- 스킬 트리 데이터 정의 (전투 택1 + 건축 자동해금)
-- 전투 계열: SPEAR, BOW, AXE (택 1)
-- 건축 계열: BUILD (SP 불요, 레벨 자동 해금)

local SkillTreeData = {}

--========================================
-- 스킬 트리 탭 정의
--========================================
SkillTreeData.TABS = {
	{ id = "SPEAR", name = "창술 연마", isCombat = true },
	{ id = "BOW",   name = "궁술 연마", isCombat = true },
	{ id = "AXE",   name = "도끼 연마", isCombat = true },
	{ id = "BUILD", name = "건축 연구", isCombat = false },
}

-- 전투 계열 ID 목록 (택1 잠금용)
SkillTreeData.COMBAT_TREE_IDS = { "SPEAR", "BOW", "AXE" }

--========================================
-- 스킬 타입
--========================================
-- PASSIVE: 무기 장착 시 자동 적용
-- ACTIVE: 슬롯 장착 후 발동
-- BUILD_TIER: SP 불요, 레벨 도달 시 자동 해금

--========================================
-- 창술 연마 (SPEAR) — 총 32 SP
--========================================
SkillTreeData.SPEAR = {
	-- 패시브 5개
	{
		id = "SPEAR_P1",
		name = "창술 수련 I",
		type = "PASSIVE",
		icon = "PASSIVE_SPEAR",
		reqLevel = 3,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.08 },
		},
		description = "창 공격력 +8%",
	},
	{
		id = "SPEAR_P2",
		name = "창술 수련 II",
		type = "PASSIVE",
		icon = "PASSIVE_SPEAR",
		reqLevel = 10,
		spCost = 3,
		prereqs = { "SPEAR_P1" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.12 },
		},
		description = "창 공격력 +12%",
	},
	{
		id = "SPEAR_P3",
		name = "창술 숙련",
		type = "PASSIVE",
		icon = "PASSIVE_SPEAR",
		reqLevel = 20,
		spCost = 5,
		prereqs = { "SPEAR_P2" },
		effects = {
			{ stat = "CRIT_CHANCE", value = 0.08 },
		},
		description = "창 치명타율 +8%",
	},
	{
		id = "SPEAR_P4",
		name = "창술 전문화",
		type = "PASSIVE",
		icon = "PASSIVE_SPEAR",
		reqLevel = 35,
		spCost = 6,
		prereqs = { "SPEAR_P3" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.15 },
		},
		description = "창 공격력 +15%",
	},
	{
		id = "SPEAR_P5",
		name = "창술 대가",
		type = "PASSIVE",
		icon = "PASSIVE_SPEAR",
		reqLevel = 45,
		spCost = 8,
		prereqs = { "SPEAR_P4" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.20 },
			{ stat = "CRIT_DAMAGE_MULT", value = 0.25 },
		},
		description = "창 공격력 +20%, 치명타 데미지 +25%",
	},
	-- 액티브 3개
	{
		id = "SPEAR_A1",
		name = "강타",
		type = "ACTIVE",
		icon = "ACTIVE_SPEAR_STRIKE",
		reqLevel = 8,
		spCost = 2,
		prereqs = { "SPEAR_P1" },
		cooldown = 12,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 1.80 },
		},
		description = "전방 강력 찌르기, 기본 공격력 180%",
	},
	{
		id = "SPEAR_A2",
		name = "돌진",
		type = "ACTIVE",
		icon = "ACTIVE_SPEAR_CHARGE",
		reqLevel = 25,
		spCost = 3,
		prereqs = { "SPEAR_P3" },
		cooldown = 18,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 2.00 },
			{ stat = "SLOW_DURATION", value = 1.5 },
		},
		description = "전방 8스터드 돌진, 200%, 1.5초 둔화",
	},
	{
		id = "SPEAR_A3",
		name = "난무",
		type = "ACTIVE",
		icon = "ACTIVE_SPEAR_FLURRY",
		reqLevel = 40,
		spCost = 3,
		prereqs = { "SPEAR_P4" },
		cooldown = 30,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 4 },
			{ stat = "SKILL_DAMAGE_MULT", value = 1.00 },
			{ stat = "SKILL_FINAL_HIT_MULT", value = 2.00 },
		},
		description = "1.2초간 4회 연속 찌르기, 각 100%, 마지막 200%",
	},
}

--========================================
-- 궁술 연마 (BOW) — 총 32 SP
--========================================
SkillTreeData.BOW = {
	-- 패시브 5개
	{
		id = "BOW_P1",
		name = "궁술 수련 I",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 3,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.05 },
		},
		description = "활 공격력 +5%",
	},
	{
		id = "BOW_P2",
		name = "궁술 수련 II",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 10,
		spCost = 3,
		prereqs = { "BOW_P1" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.08 },
		},
		description = "활 공격력 +8%",
	},
	{
		id = "BOW_P3",
		name = "궁술 숙련",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 20,
		spCost = 5,
		prereqs = { "BOW_P2" },
		effects = {
			{ stat = "CRIT_CHANCE", value = 0.08 },
		},
		description = "활 치명타율 +8%",
	},
	{
		id = "BOW_P4",
		name = "궁술 전문화",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 35,
		spCost = 6,
		prereqs = { "BOW_P3" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.10 },
		},
		description = "활 공격력 +10%",
	},
	{
		id = "BOW_P5",
		name = "궁술 대가",
		type = "PASSIVE",
		icon = "PASSIVE_BOW",
		reqLevel = 45,
		spCost = 8,
		prereqs = { "BOW_P4" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.15 },
			{ stat = "NO_ARROW_CONSUME", value = 1 },
		},
		description = "활 공격력 +15%, 화살 소모 없음",
	},
	-- 액티브 3개
	{
		id = "BOW_A1",
		name = "강사",
		type = "ACTIVE",
		icon = "ACTIVE_BOW_POWER",
		reqLevel = 8,
		spCost = 2,
		prereqs = { "BOW_P1" },
		cooldown = 14,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 2.00 },
			{ stat = "STAGGER_DURATION", value = 1.5 },
			{ stat = "SKILL_CHARGE_TIME", value = 1.5 },
		},
		description = "1.5초 충전, 200%, 1.5초 경직",
	},
	{
		id = "BOW_A2",
		name = "속사",
		type = "ACTIVE",
		icon = "ACTIVE_BOW_RAPID",
		reqLevel = 25,
		spCost = 3,
		prereqs = { "BOW_P3" },
		cooldown = 20,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 3 },
			{ stat = "SKILL_DAMAGE_MULT", value = 0.70 },
		},
		description = "0.8초간 3발 연속 사격, 각 70%",
	},
	{
		id = "BOW_A3",
		name = "폭렬 사격",
		type = "ACTIVE",
		icon = "ACTIVE_BOW_EXPLOSIVE",
		reqLevel = 40,
		spCost = 3,
		prereqs = { "BOW_P4" },
		cooldown = 35,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 1.60 },
			{ stat = "SKILL_AOE_RADIUS", value = 5 },
			{ stat = "SKILL_DOT_DURATION", value = 3 },
			{ stat = "SKILL_DOT_TICK_PCT", value = 0.03 },
		},
		description = "폭발 화살, 5스터드 범위 160%, 3초 화상(틱당 3%)",
	},
}

--========================================
-- 도끼 연마 (AXE) — 총 32 SP
--========================================
SkillTreeData.AXE = {
	-- 패시브 5개
	{
		id = "AXE_P1",
		name = "도끼 수련 I",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 3,
		spCost = 2,
		prereqs = {},
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.08 },
		},
		description = "도끼 공격력 +8%",
	},
	{
		id = "AXE_P2",
		name = "도끼 수련 II",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 10,
		spCost = 3,
		prereqs = { "AXE_P1" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.12 },
		},
		description = "도끼 공격력 +12%",
	},
	{
		id = "AXE_P3",
		name = "도끼 숙련",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 20,
		spCost = 5,
		prereqs = { "AXE_P2" },
		effects = {
			{ stat = "CRIT_CHANCE", value = 0.10 },
		},
		description = "도끼 치명타율 +10%",
	},
	{
		id = "AXE_P4",
		name = "도끼 전문화",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 35,
		spCost = 6,
		prereqs = { "AXE_P3" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.15 },
		},
		description = "도끼 공격력 +15%",
	},
	{
		id = "AXE_P5",
		name = "도끼 대가",
		type = "PASSIVE",
		icon = "PASSIVE_AXE",
		reqLevel = 45,
		spCost = 8,
		prereqs = { "AXE_P4" },
		effects = {
			{ stat = "DAMAGE_MULT", value = 0.20 },
			{ stat = "HEAL_ON_HIT_CHANCE", value = 0.10 },
			{ stat = "HEAL_ON_HIT_PCT", value = 0.03 },
		},
		description = "도끼 공격력 +20%, 평타 적중 10% 확률로 최대HP 3% 회복",
	},
	-- 액티브 3개
	{
		id = "AXE_A1",
		name = "내려찍기",
		type = "ACTIVE",
		icon = "ACTIVE_AXE_SLAM",
		reqLevel = 8,
		spCost = 2,
		prereqs = { "AXE_P1" },
		cooldown = 12,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 2.20 },
			{ stat = "SLOW_DURATION", value = 2 },
			{ stat = "SLOW_AMOUNT", value = 0.30 },
		},
		description = "수직 타격, 220%, 2초 둔화(-30%)",
	},
	{
		id = "AXE_A2",
		name = "회전 베기",
		type = "ACTIVE",
		icon = "ACTIVE_AXE_SPIN",
		reqLevel = 25,
		spCost = 3,
		prereqs = { "AXE_P3" },
		cooldown = 22,
		effects = {
			{ stat = "SKILL_DAMAGE_MULT", value = 1.60 },
			{ stat = "SKILL_AOE_RADIUS", value = 6 },
		},
		description = "360도 6스터드 범위, 160%",
	},
	{
		id = "AXE_A3",
		name = "도끼 폭풍",
		type = "ACTIVE",
		icon = "ACTIVE_AXE_STORM",
		reqLevel = 40,
		spCost = 3,
		prereqs = { "AXE_P4" },
		cooldown = 35,
		effects = {
			{ stat = "SKILL_MULTI_HIT", value = 3 },
			{ stat = "SKILL_DAMAGE_MULT", value = 1.40 },
			{ stat = "STUN_DURATION", value = 1.5 },
		},
		description = "2초간 3회 회전, 각 140%, 마지막 기절 1.5초",
	},
}

--========================================
-- 건축 연구 (BUILD) — SP 불요, 레벨 자동 해금
--========================================
SkillTreeData.BUILD = {
	{
		id = "BUILD_T0",
		name = "기초 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 1,
		spCost = 0,
		prereqs = {},
		effects = {},
		description = "캠프파이어, 임시 침대 등 기본 구조물",
	},
	{
		id = "BUILD_T1",
		name = "초급 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 10,
		spCost = 0,
		prereqs = { "BUILD_T0" },
		effects = {},
		description = "추후 기획 반영 예정",
	},
	{
		id = "BUILD_T2",
		name = "중급 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 20,
		spCost = 0,
		prereqs = { "BUILD_T1" },
		effects = {},
		description = "추후 기획 반영 예정",
	},
	{
		id = "BUILD_T3",
		name = "고급 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 30,
		spCost = 0,
		prereqs = { "BUILD_T2" },
		effects = {},
		description = "추후 기획 반영 예정",
	},
	{
		id = "BUILD_T4",
		name = "마스터 건축",
		type = "BUILD_TIER",
		icon = "BUILD_TIER",
		reqLevel = 40,
		spCost = 0,
		prereqs = { "BUILD_T3" },
		effects = {},
		description = "추후 기획 반영 예정",
	},
}

--========================================
-- 유틸리티 함수
--========================================

--- 스킬 ID로 스킬 데이터 조회
function SkillTreeData.GetSkill(skillId: string)
	for _, treeId in ipairs({ "SPEAR", "BOW", "AXE", "BUILD" }) do
		local tree = SkillTreeData[treeId]
		if tree then
			for _, skill in ipairs(tree) do
				if skill.id == skillId then
					return skill, treeId
				end
			end
		end
	end
	return nil, nil
end

--- 특정 트리의 전체 SP 비용 합산
function SkillTreeData.GetTreeTotalCost(treeId: string): number
	local tree = SkillTreeData[treeId]
	if not tree then return 0 end
	local total = 0
	for _, skill in ipairs(tree) do
		total = total + (skill.spCost or 0)
	end
	return total
end

--- 스킬 ID가 속한 트리 ID 반환
function SkillTreeData.GetTreeIdForSkill(skillId: string): string?
	for _, treeId in ipairs({ "SPEAR", "BOW", "AXE", "BUILD" }) do
		local tree = SkillTreeData[treeId]
		if tree then
			for _, skill in ipairs(tree) do
				if skill.id == skillId then
					return treeId
				end
			end
		end
	end
	return nil
end

--- 트리가 전투 계열인지 확인
function SkillTreeData.IsCombatTree(treeId: string): boolean
	for _, tab in ipairs(SkillTreeData.TABS) do
		if tab.id == treeId then
			return tab.isCombat == true
		end
	end
	return false
end

return SkillTreeData
