-- DataHelper.lua
-- 클라이언트와 서버에서 공통으로 사용하는 데이터 조회 유틸리티

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = ReplicatedStorage:WaitForChild("Data")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = ReplicatedStorage:WaitForChild("Data")

local DataHelper = {}

-- 로컬 캐시 (맵 형태로 변환된 데이터)
local tableCache = {}

--- 특정 테이블 조회 및 캐싱
function DataHelper.GetTable(tableName: string)
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
			end
		else
			-- 2. 배열 형태면 ID 기반 맵으로 변환
			for _, record in ipairs(rawData) do
				if record.id then
					mapData[record.id] = record
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

return DataHelper
