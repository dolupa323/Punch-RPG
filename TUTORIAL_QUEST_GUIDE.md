# 🎓 튜토리얼 퀨스트 시스템 구현 가이드

> **버전**: 간단한 튜토리얼 전용  
> **대상**: 신규 플레이어만 (Level 1-10)  
> **맵**: 초원섬 기반  
> **예상 소요 시간**: 2-3시간

---

## 📍 개요

**전체 퀨스트 프레임워크 대신, 튜토리얼 퀨스트만 초간단 구현**

- 새 유저가 처음 게임 시작 시에만 자동으로 부여되는 선형 퀨스트
- 총 5개의 기본 튜토리얼 (자동 진행)
- 계층적 완료 (하나씩 차례로)
- 단순한 상태 추적 (완료/미완료)

---

## 🎮 튜토리얼 퀨스트 플로우 (초원섬)

```
Level 1 시작
│
├─ TUTORIAL_HARVEST
│  └─ 자원 노드 3번 수확
│  └─ 보상: WOOD×10
│
├─ TUTORIAL_CRAFT_PICKAXE (자동 진행)
│  └─ 돌 곡괭이 1개 제작
│  └─ 보상: XP+50
│
├─ TUTORIAL_BUILD_CAMPFIRE (자동 진행)
│  └─ 캠프파이어 건설 1개
│  └─ 보상: XP+100, TECHPOINT+1
│
├─ TUTORIAL_CAPTURE_DODO (자동 진행)
│  └─ 도도 1마리 포획
│  └─ 보상: XP+100, PAL_SPHERE×5
│
└─ TUTORIAL_COMPLETE (자동 진행)
   └─ 모든 튜토리얼 완료
   └─ 보상: XP+200, TECHPOINT+2, CHEST (골드+100)
```

---

## 💾 1단계: 데이터 생성

### 1.1 `TutorialQuestData.lua` 생성

**경로**: `src/ReplicatedStorage/Data/TutorialQuestData.lua`

```lua
-- TutorialQuestData.lua
-- 새 플레이어용 튜토리얼 퀨스트 (초원섬)

local TutorialQuestData = {
	{
		id = "TUTORIAL_HARVEST",
		name = "첫 수확",
		description = "나무나 돌을 3번 수확해보세요",
		objectives = {
			{
				type = "HARVEST",
				targetId = nil,        -- 모든 노드 가능
				count = 3,
			}
		},
		rewards = {
			xp = 0,
			techPoints = 0,
			items = {
				{ itemId = "WOOD", count = 10 },
			}
		},
		order = 1,                     -- 1번째 튜토리얼
	},
	{
		id = "TUTORIAL_CRAFT_PICKAXE",
		name = "돌 곡괭이 제작",
		description = "인벤토리에서 돌 곡괭이를 제작하세요",
		objectives = {
			{
				type = "CRAFT",
				targetId = "CRAFT_STONE_PICKAXE",
				count = 1,
			}
		},
		rewards = {
			xp = 50,
			techPoints = 0,
			items = {}
		},
		order = 2,
	},
	{
		id = "TUTORIAL_BUILD_CAMPFIRE",
		name = "캠프파이어 건설",
		description = "캠프파이어를 세우세요 (시야 확보 + 쿠킹)",
		objectives = {
			{
				type = "BUILD",
				targetId = "CAMPFIRE",
				count = 1,
			}
		},
		rewards = {
			xp = 100,
			techPoints = 1,
			items = {}
		},
		order = 3,
	},
	{
		id = "TUTORIAL_CAPTURE_DODO",
		name = "첫 팰 포획",
		description = "도도를 넝쿨 볼라로 포획해보세요",
		objectives = {
			{
				type = "CAPTURE",
				targetId = "DODO",
				count = 1,
			}
		},
		rewards = {
			xp = 100,
			techPoints = 0,
			items = {
				{ itemId = "PAL_SPHERE", count = 5 },
			}
		},
		order = 4,
	},
	{
		id = "TUTORIAL_COMPLETE",
		name = "튜토리얼 완료",
		description = "모든 튜토리얼을 완료했습니다!",
		objectives = {
			{
				type = "COMPLETE_ALL_TUTORIALS",
				targetId = nil,
				count = 1,
			}
		},
		rewards = {
			xp = 200,
			techPoints = 2,
			items = {
				{ itemId = "GOLD", count = 100 },
			}
		},
		order = 5,
	},
}

return TutorialQuestData
```

**작업량**: 20분

---

## ⚙️ 2단계: 간단한 서버 서비스

### 2.1 `TutorialQuestService.lua` 생성

**경로**: `src/ServerScriptService/Server/Services/TutorialQuestService.lua`

```lua
-- TutorialQuestService.lua
-- 튜토리얼 퀨스트 서비스 (간단한 버전)
-- 단순 상태 추적만 수행

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local TutorialQuestService = {}

-- Dependencies
local NetController
local SaveService
local InventoryService
local PlayerStatService

-- 튜토리얼 데이터 로드
local TutorialQuestData = require(ReplicatedStorage:WaitForChild("Data").TutorialQuestData)

-- State: [userId] = { [questId] = { completed = true/false, progress = N } }
local playerTutorials = {}

--========================================
-- Public API
--========================================

function TutorialQuestService.Init(_NetController, _SaveService, _InventoryService, _PlayerStatService)
	NetController = _NetController
	SaveService = _SaveService
	InventoryService = _InventoryService
	PlayerStatService = _PlayerStatService

	-- 플레이어 로그인 시 튜토리얼 상태 로드
	Players.PlayerAdded:Connect(function(player)
		TutorialQuestService._loadPlayerTutorials(player)
	end)

	print("[TutorialQuestService] Initialized")
end

--- 튜토리얼 상태 로드
function TutorialQuestService._loadPlayerTutorials(player: Player)
	local userId = player.UserId
	if not SaveService or not SaveService.getPlayerState then return end

	local state = SaveService.getPlayerState(userId)
	if state and state.tutorials then
		playerTutorials[userId] = state.tutorials
	else
		-- 새 플레이어: 튜토리얼 초기화
		playerTutorials[userId] = {}
		for _, quest in ipairs(TutorialQuestData) do
			playerTutorials[userId][quest.id] = {
				completed = false,
				progress = 0,
				claimedAt = nil,
			}
		end
		-- SaveService에 저장
		if state then
			state.tutorials = playerTutorials[userId]
		end
	end
end

--- 튜토리얼 진행도 조회
function TutorialQuestService.getTutorials(userId: number)
	return playerTutorials[userId] or {}
end

--- 특정 튜토리얼 진행도 업데이트
function TutorialQuestService.updateProgress(userId: number, questId: string, progressDelta: number)
	local tutorials = playerTutorials[userId]
	if not tutorials or not tutorials[questId] then return end

	if tutorials[questId].completed then return end

	tutorials[questId].progress = (tutorials[questId].progress or 0) + progressDelta

	-- 자동 완료 확인
	local questData = TutorialQuestService._getQuestData(questId)
	if questData and questData.objectives[1] then
		local targetCount = questData.objectives[1].count
		if tutorials[questId].progress >= targetCount then
			tutorials[questId].completed = true
			tutorials[questId].completedAt = os.time()

			-- 보상 지급
			TutorialQuestService._grantRewards(userId, questId)

			-- 클라이언트에 알림
			if NetController then
				NetController.Broadcast("Tutorial.Completed", { userId = userId, questId = questId })
			end
		end
	end
end

--- 보상 지급
function TutorialQuestService._grantRewards(userId: number, questId: string)
	local questData = TutorialQuestService._getQuestData(questId)
	if not questData then return end

	local rewards = questData.rewards

	-- XP 지급
	if rewards.xp and rewards.xp > 0 and PlayerStatService then
		PlayerStatService.addExp(userId, rewards.xp)
	end

	-- 기술 포인트 지급
	if rewards.techPoints and rewards.techPoints > 0 and PlayerStatService then
		PlayerStatService.addTechPoints(userId, rewards.techPoints)
	end

	-- 아이템 지급
	if rewards.items and InventoryService then
		for _, item in ipairs(rewards.items) do
			InventoryService.addItem(userId, item.itemId, item.count)
		end
	end
end

--- 모든 튜토리얼 완료 여부 확인
function TutorialQuestService.isAllCompleted(userId: number): boolean
	local tutorials = playerTutorials[userId] or {}
	for _, quest in ipairs(TutorialQuestData) do
		if not tutorials[quest.id] or not tutorials[quest.id].completed then
			return false
		end
	end
	return true
end

--- 퀘스트 데이터 조회
function TutorialQuestService._getQuestData(questId: string)
	for _, quest in ipairs(TutorialQuestData) do
		if quest.id == questId then return quest end
	end
	return nil
end

--- 콜백: 수확할 때마다 호출
function TutorialQuestService.onHarvest(userId: number)
	TutorialQuestService.updateProgress(userId, "TUTORIAL_HARVEST", 1)
end

--- 콜백: 제작할 때마다 호출
function TutorialQuestService.onCraft(userId: number, recipeId: string)
	if recipeId == "CRAFT_STONE_PICKAXE" then
		TutorialQuestService.updateProgress(userId, "TUTORIAL_CRAFT_PICKAXE", 1)
	end
end

--- 콜백: 건축할 때마다 호출
function TutorialQuestService.onBuild(userId: number, facilityId: string)
	if facilityId == "CAMPFIRE" then
		TutorialQuestService.updateProgress(userId, "TUTORIAL_BUILD_CAMPFIRE", 1)
	end
end

--- 콜백: 팰 포획할 때마다 호출
function TutorialQuestService.onCapture(userId: number, creatureId: string)
	if creatureId == "DODO" then
		TutorialQuestService.updateProgress(userId, "TUTORIAL_CAPTURE_DODO", 1)

		-- 마지막 튜토리얼 자동 완료
		TutorialQuestService.updateProgress(userId, "TUTORIAL_COMPLETE", 1)
	end
end

function TutorialQuestService.GetHandlers()
	return {
		["Tutorial.GetStatus.Request"] = function(player, payload)
			return { success = true, tutorials = TutorialQuestService.getTutorials(player.UserId) }
		end
	}
end

return TutorialQuestService
```

**작업량**: 1시간

---

## 🔌 3단계: 서버 초기화 및 연결

### 3.1 `ServerInit.lua` 수정

**경로**: `src/ServerScriptService/ServerInit.server.lua` (줄 ~360 이후)

```lua
-- TutorialQuestService 초기화
local TutorialQuestService = require(Services.TutorialQuestService)
TutorialQuestService.Init(NetController, SaveService, InventoryService, PlayerStatService)

-- TutorialQuestService 핸들러 등록
for command, handler in pairs(TutorialQuestService.GetHandlers()) do
	NetController.RegisterHandler(command, handler)
end

-- 다른 서비스에 콜백 연결
-- HarvestService
if HarvestService.SetTutorialCallback then
	HarvestService.SetTutorialCallback(function(userId)
		TutorialQuestService.onHarvest(userId)
	end)
end

-- CraftingService
if CraftingService.SetTutorialCallback then
	CraftingService.SetTutorialCallback(function(userId, recipeId)
		TutorialQuestService.onCraft(userId, recipeId)
	end)
end

-- BuildService
if BuildService.SetTutorialCallback then
	BuildService.SetTutorialCallback(function(userId, facilityId)
		TutorialQuestService.onBuild(userId, facilityId)
	end)
end

-- PartyService
if PartyService.SetTutorialCallback then
	PartyService.SetTutorialCallback(function(userId, creatureId)
		TutorialQuestService.onCapture(userId, creatureId)
	end)
end
```

**작업량**: 30분

---

### 3.2 기존 서비스에 콜백 추가

각 서비스 (HarvestService, CraftingService, BuildService, PartyService)에 다음 함수 추가:

```lua
-- HarvestService.lua에 추가
local tutorialCallback = nil

function HarvestService.SetTutorialCallback(_callback)
	tutorialCallback = _callback
end

-- hit() 함수 내에서 수확 완료 시
if tutorialCallback then
	tutorialCallback(userId)
end
```

**작업량**: 각 서비스당 10분, 총 40분

---

## 📱 4단계: 클라이언트 UI

### 4.1 `TutorialController.lua` 생성

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialController.lua`

```lua
-- TutorialController.lua
-- 튜토리얼 상태 관리 + UI 갱신

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local TutorialController = {}

-- State
local tutorials = {}
local listeners = {}

--========================================
-- Public API
--========================================

function TutorialController.Init()
	-- 서버에서 튜토리얼 상태 조회
	task.spawn(function()
		TutorialController.requestStatus(function()
			print("[TutorialController] Initialized")
		end)
	end)

	-- 서버 이벤트 수신
	NetClient.On("Tutorial.Completed", function(data)
		tutorials[data.questId] = { completed = true }
		for _, cb in ipairs(listeners.onCompleted or {}) do
			pcall(cb, data.questId)
		end
	end)
end

function TutorialController.requestStatus(callback)
	task.spawn(function()
		local ok, data = NetClient.Request("Tutorial.GetStatus.Request", {})
		if ok and data then
			tutorials = data.tutorials or {}
		end
		if callback then callback(ok) end
	end)
end

function TutorialController.getTutorials()
	return tutorials
end

function TutorialController.getProgress(questId: string)
	local quest = tutorials[questId]
	if not quest then return 0, 0 end
	return quest.progress or 0, quest.completed and 1 or 0
end

function TutorialController.onCompleted(callback)
	listeners.onCompleted = listeners.onCompleted or {}
	table.insert(listeners.onCompleted, callback)
end

return TutorialController
```

**작업량**: 30분

---

### 4.2 `TutorialUI.lua` 생성

**경로**: `src/StarterPlayer/StarterPlayerScripts/Client/UI/TutorialUI.lua`

```lua
-- TutorialUI.lua
-- 튜토리얼 진행도 띠 UI

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TutorialController = require(script.Parent.Parent.Controllers.TutorialController)

local TutorialUI = {}

-- UI Instances
local screenGui
local tutorialPanel
local progressInfo

function TutorialUI.Create(parent: ScreenGui)
	-- 패널 생성 (오른쪽 상단)
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TutorialGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui")

	tutorialPanel = Instance.new("Frame")
	tutorialPanel.Name = "TutorialPanel"
	tutorialPanel.Size = UDim2.new(0, 300, 0, 150)
	tutorialPanel.Position = UDim2.new(1, -320, 0, 20)
	tutorialPanel.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	tutorialPanel.BorderColor3 = Color3.fromRGB(100, 150, 255)
	tutorialPanel.BorderSizePixel = 2
	tutorialPanel.Parent = screenGui

	-- 제목
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 30)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.Text = "📖 튜토리얼"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Background Color3 = Color3.fromRGB(30, 30, 30)
	titleLabel.BorderSizePixel = 0
	titleLabel.TextSize = 16
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = tutorialPanel

	-- 진행도 정보
	progressInfo = Instance.new("TextLabel")
	progressInfo.Name = "ProgressInfo"
	progressInfo.Size = UDim2.new(1, -20, 1, -40)
	progressInfo.Position = UDim2.new(0, 10, 0, 35)
	progressInfo.Text = "로딩 중..."
	progressInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
	progressInfo.BackgroundTransparency = 1
	progressInfo.TextSize = 12
	progressInfo.Font = Enum.Font.Gotham
	progressInfo.TextXAlignment = Enum.TextXAlignment.Left
	progressInfo.TextYAlignment = Enum.TextYAlignment.Top
	progressInfo.TextWrapped = true
	progressInfo.Parent = tutorialPanel

	-- 튜토리얼 업데이트 이벤트
	TutorialController.onCompleted(function(questId)
		task.wait(0.5)
		TutorialUI.Update()
	end)

	task.wait(1)
	TutorialUI.Update()
end

function TutorialUI.Update()
	local tutorials = TutorialController.getTutorials()
	local totalCount = 5  -- 총 5개 튜토리얼
	local completedCount = 0

	local textLines = {}

	for questId, questState in pairs(tutorials) do
		if questState.completed then
			completedCount = completedCount + 1
			table.insert(textLines, "✅ " .. questId)
		else
			local progress, _ = TutorialController.getProgress(questId)
			table.insert(textLines, "⏳ " .. questId .. " (" .. tostring(progress) .. ")")
		end
	end

	local progressText = string.format("진행률: %d / %d\n\n%s",
		completedCount, totalCount,
		table.concat(textLines, "\n"))

	progressInfo.Text = progressText
end

function TutorialUI.Destroy()
	if screenGui then screenGui:Destroy() end
end

return TutorialUI
```

**작업량**: 40분

---

### 4.3 `ClientInit.lua` 수정

```lua
-- ClientInit.lua에 추가

local TutorialController = require(Controllers.TutorialController)
TutorialController.Init()

-- UI 생성 (UIManager 초기화 후)
local TutorialUI = require(Client.UI.TutorialUI)
TutorialUI.Create(script.Parent.Parent.PlayerGui)
```

**작업량**: 10분

---

## 📊 예상 소요 시간 (총 2.5-3시간)

| 작업                     | 시간           |
| ------------------------ | -------------- |
| TutorialQuestData.lua    | 20분           |
| TutorialQuestService.lua | 1시간          |
| ServerInit.lua 수정      | 30분           |
| 기존 서비스에 콜백 추가  | 40분           |
| TutorialController.lua   | 30분           |
| TutorialUI.lua           | 40분           |
| ClientInit.lua 수정      | 10분           |
| **총계**                 | **~2.5-3시간** |

---

## ✅ 구현 체크리스트

### 데이터

- [ ] TutorialQuestData.lua 생성 (5가지 기본 튜토리얼)

### 서버

- [ ] TutorialQuestService.lua 구현
- [ ] ServerInit.lua에 TutorialQuestService 추가
- [ ] HarvestService.SetTutorialCallback() 추가
- [ ] CraftingService.SetTutorialCallback() 추가
- [ ] BuildService.SetTutorialCallback() 추가
- [ ] PartyService.SetTutorialCallback() (팰 포획)

### 클라이언트

- [ ] TutorialController.lua 구현
- [ ] TutorialUI.lua 구현
- [ ] ClientInit.lua에 TutorialController 추가
- [ ] UI 동작 테스트

### 테스트

- [ ] 새 캐릭터로 게임 시작 시 튜토리얼 자동 부여
- [ ] 각 단계마다 진행도 시각화 확인
- [ ] 완료 시 보상 지급 확인

---

## 🎯 다음 단계

이 튜토리얼 퀨스트만 구현하면:

✅ **초원섬**: 신규 유저 온보딩 완료  
✅ **간단함**: 전체 퀨스트 프레임워크 없이도 작동  
✅ **확장 가능**: 나중에 필요 시 다른 퀨스트 추가 가능

---

**이 가이드만 따라 구현하면 2-3시간 안에 완료됩니다!**
