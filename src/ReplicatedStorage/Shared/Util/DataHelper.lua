-- DataHelper.lua
-- 클라이언트와 서버에서 공통으로 사용하는 데이터 조회 유틸리티

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Data = ReplicatedStorage:WaitForChild("Data")

local DataHelper = {}

-- 로컬 캐시 (맵 형태로 변환된 데이터)
local tableCache = {}
local clientLocalizer = nil
local localizerResolveAttempted = false
local clientLocaleService = nil
local localeServiceResolveAttempted = false
local cachedLanguage = nil

local function getClientLocalizer()
	if not RunService:IsClient() then
		return nil
	end

	if clientLocalizer then
		return clientLocalizer
	end
	if localizerResolveAttempted then
		return nil
	end
	localizerResolveAttempted = true

	local ok, resolved = pcall(function()
		local player = Players.LocalPlayer
		if not player then
			return nil
		end

		local playerScripts = player:WaitForChild("PlayerScripts")
		local clientFolder = playerScripts:WaitForChild("Client")
		local localizationFolder = clientFolder:WaitForChild("Localization")
		local moduleScript = localizationFolder:WaitForChild("UILocalizer")
		return require(moduleScript)
	end)

	if ok then
		clientLocalizer = resolved
	else
		warn("[DataHelper] Failed to resolve UILocalizer:", resolved)
		localizerResolveAttempted = false
	end

	return clientLocalizer
end

local function getClientLocaleService()
	if not RunService:IsClient() then
		return nil
	end

	if clientLocaleService then
		return clientLocaleService
	end
	if localeServiceResolveAttempted then
		return nil
	end
	localeServiceResolveAttempted = true

	local ok, resolved = pcall(function()
		local player = Players.LocalPlayer
		if not player then
			return nil
		end

		local playerScripts = player:WaitForChild("PlayerScripts")
		local clientFolder = playerScripts:WaitForChild("Client")
		local localizationFolder = clientFolder:WaitForChild("Localization")
		local moduleScript = localizationFolder:WaitForChild("LocaleService")
		return require(moduleScript)
	end)

	if ok then
		clientLocaleService = resolved
	else
		warn("[DataHelper] Failed to resolve LocaleService:", resolved)
		localeServiceResolveAttempted = false
	end

	return clientLocaleService
end

local function getCurrentClientLanguage(): string
	if not RunService:IsClient() then
		return "server"
	end

	local localeService = getClientLocaleService()
	if localeService and type(localeService.GetLanguage) == "function" then
		local ok, lang = pcall(localeService.GetLanguage)
		if ok and type(lang) == "string" and lang ~= "" then
			return lang
		end
	end

	return "ko"
end

local function localizeRecord(tableName: string, recordId: string, record: table)
	if not RunService:IsClient() then
		return record
	end

	local localizer = getClientLocalizer()
	if not localizer or type(localizer.LocalizeDataText) ~= "function" then
		return record
	end

	if type(record) ~= "table" then
		return record
	end

	local localized = table.clone(record)
	local id = record.id or recordId

	if localized.name ~= nil then
		localized.name = localizer.LocalizeDataText(tableName, tostring(id), "name", localized.name)
	end
	if localized.description ~= nil then
		localized.description = localizer.LocalizeDataText(tableName, tostring(id), "description", localized.description)
	end
	if localized.npcName ~= nil then
		localized.npcName = localizer.LocalizeDataText(tableName, tostring(id), "npcName", localized.npcName)
	end

	return localized
end

--- 특정 테이블 조회 및 캐싱
function DataHelper.GetTable(tableName: string)
	if RunService:IsClient() then
		local lang = getCurrentClientLanguage()
		if cachedLanguage and cachedLanguage ~= lang then
			tableCache = {}
		end
		cachedLanguage = lang
	end

	if tableCache[tableName] then
		return tableCache[tableName]
	end
	
	local module = Data:FindFirstChild(tableName)
	if module and module:IsA("ModuleScript") then
		local rawData = require(module)
		
		-- [최적화] 무거운 Validator 대신 효율적인 매핑 로직 수행
		-- 서버 Init에서 이미 검증되었으므로 클라이언트/서버 공히 신뢰함
		local mapData = {}
		
		-- 1. 이미 맵 형태인지 확인 (첫 번째 키가 문자열이고 값이 테이블인 경우)
		local firstKey, firstVal = next(rawData)
		if firstKey and type(firstKey) == "string" and type(firstVal) == "table" then
			mapData = rawData
			-- id 필드 보장
			for id, record in pairs(mapData) do
				if not record.id then record.id = id end
				mapData[id] = localizeRecord(tableName, id, record)
			end
		else
			-- 2. 배열 형태면 ID 기반 맵으로 변환
			for _, record in ipairs(rawData) do
				if record.id then
					mapData[record.id] = localizeRecord(tableName, record.id, record)
				end
			end
		end
		
		tableCache[tableName] = mapData
		return mapData
	end
	
	warn("[DataHelper] Table not found:", tableName)
	return nil
end

--- 특정 테이블에서 ID로 항목 조회
function DataHelper.GetData(tableName: string, id: string)
	local tbl = DataHelper.GetTable(tableName)
	if tbl then
		return tbl[id]
	end
	return nil
end

function DataHelper.GetEnhanceBonusRate(rarity)
	-- 강화 보너스율 평탄화를 위해 전 등급에 동일한 보너스율(0.15)을 적용하여 기댓값 일관성을 유지합니다.
	return 0.15
end

local WEAPON_TIERS = {
	"WOODEN_STAFF",
	"SoftClub",
	"Gakchang",
	"Mogwoldo",
	"POISON_HORN_SPEAR",
	"IronStaff",
	"KATANA",
	"FangSpear",
	"ICE_SWORD",
	"MAGMA_SWORD",
	"KNIGHT_SWORD",
	"SOUL_SWORD",
	"SWORD_OF_JUSTICE",
	"BLUE_FLAME_SWORD"
}

function DataHelper.GetQualityAdjustedWeaponDamage(itemId: string, quality: number): number
	local itemData = DataHelper.GetData("ItemData", itemId)
	if not itemData then
		return 0
	end

	local maxDmg = itemData.damage or 0
	local minDmg = 0

	-- 이전 티어 무기 찾기
	local tierIndex = nil
	for i, id in ipairs(WEAPON_TIERS) do
		if id == itemId then
			tierIndex = i
			break
		end
	end

	if tierIndex then
		if tierIndex == 1 then
			-- 첫 번째 무기(나무봉)는 본래 공격력의 50%를 최소 보정값으로 적용
			minDmg = math.floor(maxDmg * 0.5)
		else
			-- 이전 티어 무기의 품100 기준 공격력에서 10% 낮은 공격력
			local prevId = WEAPON_TIERS[tierIndex - 1]
			local prevItem = DataHelper.GetData("ItemData", prevId)
			local prevMaxDmg = prevItem and prevItem.damage or 0
			minDmg = math.floor(prevMaxDmg * 0.9)
		end
		-- 선형 보간 (Linear Interpolation)
		local adjustedDmg = minDmg + (maxDmg - minDmg) * (quality / 100)
		return math.floor(adjustedDmg)
	else
		-- 활성 13종 이외의 아이템(도구 등)은 기존의 0 ~ 원래 공격력 비례 방식 유지
		return math.floor(maxDmg * (quality / 100))
	end
end

function DataHelper.GetEnhanceCostMultiplier(rarity)
	local mults = {
		COMMON = 1.0,
		UNCOMMON = 1.5,
		RARE = 3.0,
		EPIC = 10.0,
		UNIQUE = 12.0,
		LEGENDARY = 15.0
	}
	return mults[rarity] or 1.0
end

-- [요청반영] 교환 가능/불가 구분 개념 자체를 없앰 — 실존하는 아이템이면 전부 교환 가능으로 취급.
function DataHelper.IsTradeable(itemId: string): boolean
	return DataHelper.GetData("ItemData", itemId) ~= nil
end

return DataHelper
