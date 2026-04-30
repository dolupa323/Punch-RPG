-- TutorialController.lua
-- 선형적 튜토리얼 연출, 행동 감지 및 월드 포인터 컨트롤러

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local UIManager = require(Client.UIManager)

local TutorialController = {}
local currentStepData = nil
local activeCheckers = {}
local initialized = false

-- 3D Guide (Highlight)
local currentHighlight = nil
local highlightConn = nil

--========================================
-- Helper: 3D Guide (Pointer)
--========================================

local function clearPointer()
	if highlightConn then highlightConn:Disconnect(); highlightConn = nil end
	if currentHighlight then currentHighlight:Destroy(); currentHighlight = nil end
end

local function updatePointer(condition, targets)
	clearPointer()
	
	if condition ~= "GATHER" then return end
	
	-- 주변의 자원 노드 찾기
	highlightConn = RunService.Heartbeat:Connect(function()
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		
		local nodes = workspace:FindFirstChild("ResourceNodes")
		if not nodes then return end
		
		local closestNode = nil
		local minDist = 30 -- 인식 반경
		
		for _, node in ipairs(nodes:GetChildren()) do
			local nodeId = node:GetAttribute("NodeId")
			if targets[nodeId] then
				local dist = (node:GetPivot().Position - hrp.Position).Magnitude
				if dist < minDist then
					minDist = dist
					closestNode = node
				end
			end
		end
		
		-- 하이라이트 업데이트
		if closestNode then
			if not currentHighlight then
				currentHighlight = Instance.new("Highlight")
				currentHighlight.FillColor = Color3.fromRGB(100, 200, 255)
				currentHighlight.OutlineColor = Color3.new(1, 1, 1)
				currentHighlight.FillTransparency = 0.4
				currentHighlight.Parent = closestNode
			elseif currentHighlight.Parent ~= closestNode then
				currentHighlight.Parent = closestNode
			end
		else
			if currentHighlight then currentHighlight.Parent = nil end
		end
	end)
end

--========================================
-- Helper: Condition Checkers
--========================================

local function stopCheckers()
	for _, checker in pairs(activeCheckers) do
		if type(checker) == "function" then
			checker()
		elseif typeof(checker) == "RBXScriptConnection" then
			checker:Disconnect()
		end
	end
	activeCheckers = {}
	UIManager.stopAllBlinks()
	clearPointer()
end

local function requestComplete()
	if not currentStepData or not currentStepData.stepIndex then return end
	NetClient.Request("Tutorial.Step.Complete.Request", { stepIndex = currentStepData.stepIndex })
end

-- [MOVE] 이동 감지
local function startMoveCheck()
	local player = Players.LocalPlayer
	activeCheckers.Move = RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			stopCheckers()
			requestComplete()
		end
	end)
end

-- [MENU_OPEN] 메뉴 버튼 클릭 감지
local function startMenuCheck()
	local conn
	conn = UIManager.OnMenuOpened:Connect(function()
		conn:Disconnect()
		stopCheckers()
		requestComplete()
	end)
	activeCheckers.Menu = conn
end

-- [INVENTORY_OPEN] 인벤토리 클릭 감지
local function startInventoryCheck()
	local conn
	conn = UIManager.OnInventoryOpened:Connect(function()
		conn:Disconnect()
		stopCheckers()
		requestComplete()
	end)
	activeCheckers.Inventory = conn
end

-- [GATHER] 채집 감지
local function startGatherCheck(targets)
	local InventoryController = require(Client.Controllers.InventoryController)
	local conn
	conn = InventoryController.onChanged(function()
		local allCleared = true
		local counts = InventoryController.getItemCounts()
		
		-- 진행 상황 로그 출력 (디버그용)
		print("[Tutorial] Gathering Progress:")
		for itemId, count in pairs(targets) do
			local current = counts[itemId] or 0
			print(string.format(" - %s: %d/%d", itemId, current, count))
			if current < count then
				allCleared = false
			end
		end
		
		if allCleared then
			print("[Tutorial] Gathering Complete! Requesting next step...")
			if conn and conn.Disconnect then
				conn:Disconnect()
			end
			stopCheckers()
			requestComplete()
		end
	end)
	activeCheckers.Gather = conn
	
	-- 3D 포인터 활성화
	updatePointer("GATHER", targets)
end

-- [CRAFT] 제작 완료 감지
local function startCraftCheck(recipeId)
	local CraftController = require(Client.Controllers.CraftController)
	local conn
	
	-- [Smart Blink] 제작 단계 전용 동적 강조 로직
	local blinkConn
	local lastFocus = ""
	blinkConn = RunService.Heartbeat:Connect(function()
		local currentFocus = ""
		if UIManager.isInventoryVisible() then
			if not UIManager.isCraftingTabVisible() then
				currentFocus = "QuickCraftTab"
			elseif UIManager.getSelectedRecipeId() ~= recipeId then
				currentFocus = "Recipe:" .. recipeId
			else
				currentFocus = "CraftStartButton"
			end
		elseif UIManager.isMenuOpen() then
			currentFocus = "InventoryTabButton"
		else
			currentFocus = "MenuButton"
		end
		
		if lastFocus ~= currentFocus then
			lastFocus = currentFocus
			UIManager.setFocusUIElement(currentFocus)
		end
	end)

	conn = CraftController.onCompleted(function(rid)
		if rid == recipeId then
			if blinkConn then blinkConn:Disconnect() end
			conn:Disconnect()
			stopCheckers()
			requestComplete()
		end
	end)
	activeCheckers.Craft = {
		Disconnect = function()
			if blinkConn then blinkConn:Disconnect() end
			if conn then conn:Disconnect() end
		end
	}
end

-- [BUILD] 건설 완료 감지
local function startBuildCheck(facilityId)
	local BuildController = require(Client.Controllers.BuildController)
	local RunService = game:GetService("RunService")
	local conn
	
	-- [Smart Blink] 건설 단계 전용 동적 강조 로직
	local blinkConn
	local lastFocus = ""
	blinkConn = RunService.Heartbeat:Connect(function()
		-- 건설 배치 모드(Ghost 모드) 중에는 가이드를 일시 중단하여 유저가 지면 클릭에 집중하게 함
		if BuildController.isPlacing() then
			if lastFocus ~= "PLACING" then
				lastFocus = "PLACING"
				UIManager.setFocusUIElement(nil)
			end
			return
		end

		local currentFocus = ""
		if UIManager.isBuildOpen() then
			if UIManager.getSelectedBuildCategory() ~= "BUILD_T0" then
				currentFocus = "BuildCat:BUILD_T0"
			elseif UIManager.getSelectedBuildId() ~= facilityId then
				currentFocus = "Facility:" .. facilityId
			else
				currentFocus = "Btn"
			end
		elseif UIManager.isMenuOpen() then
			currentFocus = "BuildTabButton"
		else
			currentFocus = "MenuButton"
		end
		
		if lastFocus ~= currentFocus then
			lastFocus = currentFocus
			UIManager.setFocusUIElement(currentFocus ~= "" and currentFocus or nil)
		end
	end)

	conn = BuildController.onCompleted(function(fid)
		if fid == facilityId then
			if blinkConn then blinkConn:Disconnect() end
			conn:Disconnect()
			stopCheckers()
			requestComplete()
		end
	end)
	
	activeCheckers.Build = {
		Disconnect = function()
			if blinkConn then blinkConn:Disconnect() end
			if conn then conn:Disconnect() end
		end
	}
end

--========================================
-- Core Logic
--========================================

function TutorialController.UpdateStep(data)
	stopCheckers()
	currentStepData = data
	
	if not data or data.completed or not data.stepData then
		UIManager.hideTutorialGuide()
		return
	end

	local step = data.stepData
	UIManager.showTutorialGuide(step.message)

	-- UI 강조 (깜빡임)
	if step.targetUI then
		UIManager.blinkUIElement(step.targetUI)
	end

	-- 자동 다음 단계 이동 (메시지만 있는 경우)
	if step.duration and not step.condition then
		task.delay(step.duration, function()
			if currentStepData == data then
				requestComplete()
			end
		end)
		return
	end

	-- 조건 감지 시작
	if step.condition == "MOVE" then
		startMoveCheck()
	elseif step.condition == "MENU_OPEN" then
		startMenuCheck()
	elseif step.condition == "INVENTORY_OPEN" then
		startInventoryCheck()
	elseif step.condition == "GATHER" then
		startGatherCheck(step.targets)
	elseif step.condition == "CRAFT" then
		startCraftCheck(step.targetRecipe)
	elseif step.condition == "BUILD" then
		startBuildCheck(step.targetFacility)
	end
end

function TutorialController.Init()
	if initialized then return end
	
	NetClient.On("Tutorial.Step.Update", function(data)
		TutorialController.UpdateStep(data)
	end)

	-- 초기 상태 로드
	task.spawn(function()
		local ok, result = NetClient.Request("Tutorial.GetStatus.Request", {})
		if ok and result and result.data then
			if result.data.stepIndex > 0 and not result.data.completed then
				local TutorialData = require(ReplicatedStorage.Data.TutorialData)
				local stepData = TutorialData.Steps[result.data.stepIndex]
				TutorialController.UpdateStep({
					stepIndex = result.data.stepIndex,
					completed = result.data.completed,
					stepData = stepData
				})
			end
		end
	end)

	initialized = true
	print("[TutorialController] Initialized with 3D Guide")
end

return TutorialController
