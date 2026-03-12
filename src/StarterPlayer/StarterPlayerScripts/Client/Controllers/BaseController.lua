-- BaseController.lua
-- 베이스 관리 컨트롤러 (거점 토템 상호작용 및 UI 연동)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)

local BaseController = {}

--========================================
-- Public API
--========================================

--- 거점 정보 요청
function BaseController.getBaseInfo()
	local ok, result = NetClient.Request("Base.Get.Request")
	if ok and result.success then
		return result.data
	end
	return nil
end

--- 거점 이름 변경 요청
function BaseController.requestRename(newName: string)
	local ok, result = NetClient.Request("Base.Rename.Request", { name = newName })
	return ok and result.success, result and result.errorCode
end

--- 거점 반경 확장 요청
function BaseController.requestExpand()
	local ok, result = NetClient.Request("Base.Expand.Request")
	return ok and result.success, result and result.errorCode
end

--- 거점 UI 열기
function BaseController.openBaseMenu()
	local UIManager = require(Client.UIManager)
	local info = BaseController.getBaseInfo()
	if info then
		UIManager.openBaseMenu(info)
	else
		UIManager.notify("거점 정보를 불러올 수 없습니다.")
	end
end

return BaseController
