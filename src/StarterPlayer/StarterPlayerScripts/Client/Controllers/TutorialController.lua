-- TutorialController.lua (QuestController Remastered)
-- 퀘스트 상태 수신 및 목표 안내 표시 (무전기 시스템 제거됨)

local NetClient = require(script.Parent.Parent.NetClient)
local UIManager = require(script.Parent.Parent.UIManager)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)

local TutorialController = {}

local initialized = false
local lastStatusSignature = nil
local lastStatus = nil

local STATUS_RETRY_MAX = 12
local STATUS_RETRY_INTERVAL = 0.5
local WARMUP_POLL_COUNT = 4
local WARMUP_POLL_INTERVAL = 3

local ItemData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
local itemNameById = {}

for _, item in ipairs(ItemData) do
	if type(item) == "table" and item.id then
		itemNameById[tostring(item.id)] = tostring(item.name or item.id)
	end
end

local function buildProgressSignature(progress)
	if type(progress) ~= "table" then return "" end
	local keys = {}
	for key in pairs(progress) do table.insert(keys, key) end
	table.sort(keys)
	local chunks = {}
	for _, key in ipairs(keys) do
		table.insert(chunks, tostring(key) .. ":" .. tostring(progress[key]))
	end
	return table.concat(chunks, "|")
end

local function buildStatusSignature(status)
	if type(status) ~= "table" then return "" end
	return table.concat({
		tostring(status.completed == true),
		tostring(status.active == true),
		tostring(status.questId or ""),
		tostring(status.stepReady == true),
		buildProgressSignature(status.progress),
	}, "#")
end

local function showStatus(status, force)
	if type(status) ~= "table" then return end

	local signature = buildStatusSignature(status)
	if not force and signature == lastStatusSignature then
		return
	end
	lastStatusSignature = signature
	lastStatus = status

	-- HUD 업데이트
	UIManager.updateTutorialStatus(status)
	UIManager.setTutorialVisible(status.active == true)

	-- 알림 (보상 등)
	if status.completed then
		UIManager.notify("임무를 완료했습니다! 보상을 확인하세요.", Color3.fromRGB(255, 210, 60))
	end
end

function TutorialController.Init()
	if initialized then return end

	NetClient.On("Tutorial.Step.Updated", function(data)
		showStatus(data, false)
	end)

	NetClient.On("Tutorial.Completed", function(data)
		showStatus(data, true)
	end)

	-- 초기 상태 확인 루프
	task.spawn(function()
		for poll = 1, WARMUP_POLL_COUNT do
			local fetched = false
			for _ = 1, STATUS_RETRY_MAX do
				local ok, data = NetClient.Request("Tutorial.GetStatus.Request", {})
				if ok then
					showStatus(data, true)
					fetched = true
					break
				end
				task.wait(STATUS_RETRY_INTERVAL)
			end
			if fetched then break end
			task.wait(WARMUP_POLL_INTERVAL)
		end
	end)

	initialized = true
	print("[QuestController] Initialized")
end

return TutorialController
