-- EquipController.lua
-- 클라이언트 장착 예측 및 관리 (Equip Prediction)
-- 서버 응답 전 시각적 피드백 선제공

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)

local EquipController = {}

--========================================
-- Private State
--========================================
local player = Players.LocalPlayer
local currentPreviewModel = nil
local lastPredictedItemId = nil

--========================================
-- Private Functions
--========================================

local function getHeldModelName(itemId: string): string
	local itemData = DataHelper.GetData("ItemData", itemId)
	if itemData and itemData.modelName and itemData.modelName ~= "" then
		return itemData.modelName
	end
	local itemType = itemData and itemData.type or ""
	if itemType == "FOOD" then
		return "BERRY_PROP"
	end
	return "POUCH"
end

--- 아이템 모델 템플릿 찾기 (EquipService와 동일 로직)
local function findModelTemplate(itemId: string)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end

	local modelName = getHeldModelName(itemId)
	
	local folders = {assets:FindFirstChild("ItemModels"), assets:FindFirstChild("Models"), assets}
	for _, folder in ipairs(folders) do
		if not folder then continue end
		local found = folder:FindFirstChild(modelName, true)
		if found then return found end
		if modelName ~= itemId then
			found = folder:FindFirstChild(itemId, true)
		end
		if found then return found end
	end
	
	return nil
end

--========================================
-- Public API
--========================================

--- 서버 응답 전 로컬에서 아이템 모델 미리 보여주기
function EquipController.predictEquip(itemId: string)
	if lastPredictedItemId == itemId then return end
	lastPredictedItemId = itemId
	
	local char = player.Character
	if not char then return end
	
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand then return end
	
	-- 기존 프리뷰 제거
	EquipController.clearPreview()
	
	if not itemId or itemId == "" then return end
	
	-- 템플릿 찾기
	local template = findModelTemplate(itemId)
	if not template then return end
	
	-- 프리뷰 모델 생성
	local preview = template:Clone()
	if preview:IsA("Tool") then
		local handle = preview:FindFirstChild("Handle")
		if handle then
			-- Tool이면 Handle을 기준으로 붙임 (단순화를 위해 Handle만 혹은 전체 모델링)
			preview = handle
		end
	end
	
	if not preview:IsA("BasePart") and not preview:IsA("Model") then return end

	local attachPart = if preview:IsA("Model") then (preview.PrimaryPart or preview:FindFirstChildWhichIsA("BasePart", true)) else preview
	if not attachPart or not attachPart:IsA("BasePart") then
		if preview.Destroy then
			preview:Destroy()
		end
		return
	end

	-- 물리 및 상호작용 비활성화
	for _, p in ipairs(preview:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			p.Anchored = false
			p.CollisionGroup = "Items"
			p.Transparency = 0.3 -- 예측 모델임을 알리기 위해 살짝 투명하게 처리 (선택 사항)
		elseif p:IsA("Script") or p:IsA("LocalScript") then
			p.Disabled = true
		elseif p:IsA("BodyMover") or p:IsA("Constraint") then
			p:Destroy()
		end
	end

	if preview:IsA("Model") then
		for _, p in ipairs(preview:GetDescendants()) do
			if p:IsA("BasePart") and p ~= attachPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "PreviewWeld"
				weld.Part0 = attachPart
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	
	preview.Name = "EquipPreview"
	preview.Parent = char

	if not attachPart or not attachPart:IsA("BasePart") then
		preview:Destroy()
		return
	end
	
	-- 손에 부착 (Weld)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = attachPart
	weld.Parent = preview
	
	-- 초기 위치 설정 (대략적인 위치, 서버에서 진짜 Tool이 오면 보정됨)
	if preview:IsA("Model") then
		preview:PivotTo(hand.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	else
		preview.CFrame = hand.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	end
	
	currentPreviewModel = preview
end

--- 프리뷰 제거 (서버에서 진짜 모델이 왔거나 장착 해제 시)
function EquipController.clearPreview()
	if currentPreviewModel then
		currentPreviewModel:Destroy()
		currentPreviewModel = nil
	end
	lastPredictedItemId = nil
end

function EquipController.Init()
	-- 서버에서 진짜 Tool이 장착되면 프리뷰를 제거하는 감시 로직
	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				-- 진짜 툴이 들어오면 프리뷰 제거
				EquipController.clearPreview()
			end
		end)
	end)
	
	if player.Character then
		player.Character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				EquipController.clearPreview()
			end
		end)
	end
	
	print("[EquipController] Initialized")
end

return EquipController
