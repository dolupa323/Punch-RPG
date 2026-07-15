-- DropRateInfoService.lua
-- citizen_01("척척박사") NPC: 몬스터별 아이템 드롭률을 안내하는 정보 NPC
-- 퀘스트를 주지 않으며, 상호작용 시 드롭률 표를 조회할 수 있는 대화만 제공한다.

local DropRateInfoService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropTableData = require(ReplicatedStorage.Data.DropTableData)
local ItemData       = require(ReplicatedStorage.Data.ItemData)

local NetController = nil
local initialized   = false

local NPC_MODEL_NAME = "citizen_01"
local NPC_TITLE       = "척척박사"   -- 이름
local NPC_ROLE         = "드롭률 확인" -- 머리 위 역할 텍스트

-- 안내할 몬스터 목록 (표시 순서 = 진행 순서). dropTableId는 DropTableData의 키와 일치해야 함.
local MOB_LIST = {
	{ dropTableId = "SLIME",            displayName = "슬라임" },
	{ dropTableId = "HORNEDLARVA",       displayName = "뿔 애벌레" },
	{ dropTableId = "STUMP",             displayName = "스텀프" },
	{ dropTableId = "CYCLOPSBAT",        displayName = "사이클롭스 박쥐" },
	{ dropTableId = "SMALLGOLEM",        displayName = "작은 골렘" },
	{ dropTableId = "STUMPKING",         displayName = "스텀프 킹" },
	{ dropTableId = "SPIDER",            displayName = "거미" },
	{ dropTableId = "SAMURAI",           displayName = "사무라이" },
	{ dropTableId = "ICEKNIGHT",         displayName = "얼음 기사" },
	{ dropTableId = "ICEDRAGON",         displayName = "아이스 드래곤" },
	{ dropTableId = "LAVASLIME",         displayName = "용암 슬라임" },
	{ dropTableId = "FIREMAN",           displayName = "파이어맨" },
	{ dropTableId = "GHOSTKNIGHT",       displayName = "유령기사" },
	{ dropTableId = "GIANTGHOSTKNIGHT",  displayName = "유령기사(거인)" },
	{ dropTableId = "GHOSTWIZARD",       displayName = "유령 마법사" },
	{ dropTableId = "BLUEFLAMEKNIGHT",   displayName = "푸른 불꽃 기사" },
	{ dropTableId = "DESERTGUARDIAN",    displayName = "사막의 수호자" },
	{ dropTableId = "ABYSSGUARDIAN",     displayName = "심연의 수호자" },
	{ dropTableId = "KRAKEN",            displayName = "크라켄" },
	{ dropTableId = "KRAKEN",            displayName = "포세이돈" }, -- 정식 드롭 테이블 확정 전까지 크라켄과 동일 드롭 재사용
	{ dropTableId = "JELLYFISH",         displayName = "젤리피쉬" },
}

-- itemId -> itemName 조회 테이블 (1회 구축)
local ITEM_NAME_BY_ID = {}
for _, item in ipairs(ItemData) do
	if item.id then
		ITEM_NAME_BY_ID[item.id] = item.name or item.id
	end
end

-- 드롭률 표 데이터 (1회 구축, 이후 재사용)
local dropRows = nil
local function _buildDropRows()
	if dropRows then return dropRows end
	dropRows = {}

	for _, mob in ipairs(MOB_LIST) do
		local table_ = DropTableData[mob.dropTableId]
		if table_ then
			for i, entry in ipairs(table_) do
				local itemName = ITEM_NAME_BY_ID[entry.itemId] or entry.itemId
				table.insert(dropRows, {
					monster    = (i == 1) and mob.displayName or "",
					item       = itemName,
					chance     = math.floor((entry.chance or 0) * 1000 + 0.5) / 10, -- 소수점 1자리 %
					groupFirst = (i == 1),
				})
			end
		end
	end

	return dropRows
end

local function handleGetTable(player, payload)
	return { success = true, rows = _buildDropRows() }
end

local function handleOpen(player)
	if not NetController then return end
	NetController.FireClient(player, "DropInfo.OpenDialogue", {
		npcName  = NPC_TITLE,
		dialogue = "어서 오게, 여행자. 나는 이 근방의 몬스터들을 죄다 연구해온 척척박사라네. 무엇이 알고 싶나?",
		choices  = {
			{ text = "아이템 드롭률을 알고 싶습니다.", action = "SHOW_DROPTABLE" },
			{ text = "아무것도 아닙니다.", action = "CLOSE" },
		},
	})
end

function DropRateInfoService.Init(netController)
	if initialized then return end
	initialized = true
	NetController = netController

	task.defer(function()
		local npcFolder = workspace:WaitForChild("NPC", 30)
		if not npcFolder then warn("[DropRateInfoService] NPC folder not found"); return end

		local model = npcFolder:WaitForChild(NPC_MODEL_NAME, 30)
		if not model then warn("[DropRateInfoService] " .. NPC_MODEL_NAME .. " NPC not found"); return end

		local rootPart = model:FindFirstChild("HumanoidRootPart")
			or model:WaitForChild("HumanoidRootPart", 15)
		if not rootPart then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then rootPart = d; break end
			end
		end
		if not rootPart then warn("[DropRateInfoService] " .. NPC_MODEL_NAME .. " has no root part"); return end

		-- 머리 위 안내 라벨: 다른 NPC(강화소/분해소 등)와 동일하게 NpcLabel(BillboardGui)만
		-- 생성해두고, 실제 "[ 역할 ] 이름" 서식과 언어별 번역은 NPCLabelController가 담당한다.
		local labelAnchor = model:FindFirstChild("Head") or rootPart
		if not labelAnchor:FindFirstChild("NpcLabel") then
			local label = Instance.new("BillboardGui")
			label.Name         = "NpcLabel"
			label.Size         = UDim2.new(0, 200, 0, 50)
			label.StudsOffset  = Vector3.new(0, 3, 0)
			label.AlwaysOnTop  = true
			label.MaxDistance  = 80
			label.Parent       = labelAnchor

			local text = Instance.new("TextLabel")
			text.Size                   = UDim2.new(1, 0, 1, 0)
			text.BackgroundTransparency = 1
			text.TextScaled             = true
			text.Font                   = Enum.Font.SourceSansBold
			text.TextColor3             = Color3.fromRGB(255, 233, 184)
			text.TextStrokeTransparency = 0.35
			text.Text                   = string.format("%s\n%s", NPC_MODEL_NAME, NPC_ROLE)
			text.Parent                 = label
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name                  = "DropInfoPrompt"
		prompt.ActionText            = "대화하기"
		prompt.ObjectText            = NPC_TITLE
		prompt.KeyboardKeyCode       = Enum.KeyCode.E
		prompt.HoldDuration          = 0.3
		prompt.RequiresLineOfSight   = false
		prompt.MaxActivationDistance = 10
		prompt.Parent                = rootPart

		prompt.Triggered:Connect(function(player)
			handleOpen(player)
		end)

		print("[DropRateInfoService] " .. NPC_MODEL_NAME .. " (" .. NPC_TITLE .. ") NPC prompt registered.")
	end)
end

function DropRateInfoService.GetHandlers()
	return {
		["DropInfo.GetTable.Request"] = handleGetTable,
	}
end

return DropRateInfoService
