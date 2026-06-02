-- DismantleService.lua
-- 무기 분해 NPC 상호작용 및 서버 분해 처리 서비스
-- [100% Server-Authoritative & Durango Style Premium Recycler]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local RecipeData = require(DataFolder:WaitForChild("RecipeData"))
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local DismantleService = {}

--========================================
-- Dependencies
--========================================
local initialized = false
local NetController = nil
local InventoryService = nil
local DataService = nil

--========================================
-- Internal Helpers
--========================================

-- 아이템 ID에 대응하는 원본 무기 제작 레시피를 찾고 분해 반환 재료(50%)를 계산하는 함수
local function calculateDismantleMaterials(itemId: string)
	local returnedMaterials = {}
	local foundRecipe = nil
	
	-- 1. RecipeData에서 무기 제작법 탐색
	for _, recipe in ipairs(RecipeData) do
		if recipe.category == "WEAPON" and recipe.outputs then
			for _, output in ipairs(recipe.outputs) do
				if output.itemId == itemId then
					foundRecipe = recipe
					break
				end
			end
		end
		if foundRecipe then break end
	end
	
	-- 2. 레시피가 존재하면 50% 반환 (소수점 버림, 최소 1개 보장)
	if foundRecipe and foundRecipe.inputs then
		for _, input in ipairs(foundRecipe.inputs) do
			local returnCount = math.max(1, math.floor(input.count * 0.5))
			table.insert(returnedMaterials, {
				itemId = input.itemId,
				count = returnCount
			})
		end
	else
		-- 3. 혹시 모를 레시피 미등록 무기에 대한 폴백 재료 지급 (슬라임 점액 3개)
		table.insert(returnedMaterials, {
			itemId = "SLIME_MUCUS",
			count = 3
		})
	end
	
	return returnedMaterials
end

-- NPC ProximityPrompt 자동 생성 함수
local function setupNPC(npc)
	if npc:FindFirstChild("DismantleMasterPrompt", true) then return end
	
	local targetPart = npc:IsA("BasePart") and npc 
		or npc:FindFirstChild("HumanoidRootPart") 
		or npc.PrimaryPart 
		or npc:FindFirstChildWhichIsA("BasePart", true)
		
	if not targetPart then return end
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DismantleMasterPrompt"
	prompt.ActionText = "무기 분해"
	prompt.ObjectText = "무기 분해사"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Enabled = true
	
	prompt.Parent = targetPart
	print("[DismantleService] 무기 분해 NPC 프롬프트 생성 완료: " .. npc.Name .. " (Parent: " .. targetPart.Name .. ")")
	
	prompt.Triggered:Connect(function(player)
		if NetController then
			NetController.FireClient(player, "Dismantle.OpenUI")
			print("[DismantleService] Sent Dismantle.OpenUI to " .. player.Name)
		end
	end)
end

--========================================
-- Network Commands Handlers
--========================================

local function handleDismantleRequest(player: Player, payload: any)
	if not payload or not payload.slot then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local userId = player.UserId
	local slot = tonumber(payload.slot)
	
	if not slot or slot < 1 or slot > Balance.MAX_INV_SLOTS then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_SLOT }
	end
	
	-- 1. 인벤토리 조회
	local inv = InventoryService.getInventory(userId)
	if not inv then
		return { success = false, errorCode = "NOT_LOADED" }
	end
	
	local slotData = inv.slots[slot]
	if not slotData then
		return { success = false, errorCode = Enums.ErrorCode.SLOT_EMPTY }
	end
	
	-- 2. 아이템 정보 검증
	local itemInfo = DataService.getItem(slotData.itemId)
	if not itemInfo then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
	end
	
	-- 무기 타입만 분해 가능 가드
	if itemInfo.type ~= "WEAPON" then
		return { success = false, errorCode = "NOT_A_WEAPON", message = "무기 종류만 분해할 수 있습니다." }
	end
	
	-- 장착 중인 장비는 장착 슬롯(Hand 등)에 있으며, slots 리스트의 일반 슬롯에 있는 무기만 분해 가능하므로,
	-- 장착 중인 HAND 상태의 무기는 자연적으로 안전하게 분해에서 제외됩니다.
	
	-- 3. 반환 재료 계산 및 인벤토리 수용 한계량 검증
	local materials = calculateDismantleMaterials(slotData.itemId)
	
	-- 임시 시뮬레이션: 무기가 삭제되어 1칸 비워지는 보너스를 포함하여 반환될 재료들을 담을 수 있는지 가상 테스트
	-- (분해 완료 시 무기가 담겨있던 슬롯이 빈 슬롯이 되므로 여유 계산 시 1칸 확보를 더해줍니다.)
	local emptyCount = InventoryService.getEmptySlotCount(userId) + 1
	
	-- 슬롯이 충분한지 확인
	local fitsInInventory = true
	for _, mat in ipairs(materials) do
		-- 해당 재료를 기존 스택에 욱여넣을 수 없어서 새로운 빈 슬롯이 필요하게 될 경우
		if not InventoryService.canAdd(userId, mat.itemId, mat.count) then
			-- 빈 슬롯 1개를 확보하여 가상 적용
			emptyCount = emptyCount - 1
			if emptyCount < 0 then
				fitsInInventory = false
				break
			end
		end
	end
	
	if not fitsInInventory then
		return { success = false, errorCode = Enums.ErrorCode.INV_FULL, message = "인벤토리 공간이 부족하여 분해를 취소합니다." }
	end
	
	-- 4. 무기 파기 처리 (Atomic)
	local removed = InventoryService.removeItemFromSlot(userId, slot, 1)
	if removed <= 0 then
		return { success = false, errorCode = "REMOVE_FAILED" }
	end
	
	-- 5. 재료 지급 처리 (Atomic)
	local displayMaterials = {}
	for _, mat in ipairs(materials) do
		local added, remaining = InventoryService.addItem(userId, mat.itemId, mat.count)
		local matData = DataService.getItem(mat.itemId)
		table.insert(displayMaterials, {
			itemId = mat.itemId,
			name = matData and matData.name or mat.itemId,
			count = added
		})
	end
	
	-- 클라이언트 이펙트 및 메시지 통보
	if NetController then
		local formattedList = {}
		for _, m in ipairs(displayMaterials) do
			table.insert(formattedList, string.format("[%s x%d]", m.name, m.count))
		end
		NetController.FireClient(player, "Notify.Message", {
			text = string.format("🔨 무기를 분해하여 %s 재료를 획득했습니다!", table.concat(formattedList, ", ")),
			color = "GOLD"
		})
	end
	
	print(string.format("[DismantleService] User %d dismantled weapon %s in slot %d.", userId, slotData.itemId, slot))
	return { success = true, data = { materials = displayMaterials } }
end

--========================================
-- Public API: Init
--========================================

function DismantleService.Init(netController)
	if initialized then return end
	initialized = true
	
	NetController = netController
	InventoryService = require(ServerScriptService.Server.Services.InventoryService)
	DataService = require(ServerScriptService.Server.Services.DataService)
	
	-- Workspace 내의 기존 분해 NPC 자동 스캔
	for _, child in ipairs(Workspace:GetDescendants()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and (child.Name == "DismantleMaster" or child.Name == "분해스승" or child.Name == "무기 분해" or child.Name == "무기분해") then
			setupNPC(child)
		end
	end
	
	-- 런타임에 동적으로 노드가 추가될 때 처리 (스트리밍 및 지연 로드 대응)
	Workspace.DescendantAdded:Connect(function(child)
		if (child:IsA("Model") or child:IsA("BasePart")) and (child.Name == "DismantleMaster" or child.Name == "분해스승" or child.Name == "무기 분해" or child.Name == "무기분해") then
			task.defer(function()
				setupNPC(child)
			end)
		end
	end)
	
	print("[DismantleService] initialized and bound NPC scanner")
end

function DismantleService.GetHandlers()
	return {
		["Dismantle.Request"] = handleDismantleRequest
	}
end

return DismantleService
