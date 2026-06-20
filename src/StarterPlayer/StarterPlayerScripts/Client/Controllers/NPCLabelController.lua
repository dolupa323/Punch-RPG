-- NPCLabelController.lua
-- 서버에서 생성한 NpcLabel(BillboardGui)을 클라이언트 국가(언어)에 맞게 실시간 로컬라이징하는 컨트롤러
-- StreamingEnabled 환경에서도 완벽히 작동하며, 권한 및 복제 레이스 컨디션이 발생하지 않는 가장 안전한 방식입니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Client = script.Parent.Parent
local LocaleService = require(Client:WaitForChild("Localization"):WaitForChild("LocaleService"))

local NPCLabelController = {}
local initialized = false

local function getNPCRole(npc: Instance): (string?, string?)
	local name = npc.Name
	local npcId = npc:GetAttribute("NPCId") or ""
	local npcType = npc:GetAttribute("NPCType") or ""

	-- 1. 무기 제작
	if name == "WeaponCrafter" or npcId == "WeaponCrafter" then
		return "대장간", "Forge"
	end

	-- 2. 무기 강화
	if name == "EnhanceMaster" or name == "강화스승" or name == "무기 강화" or npcId == "EnhanceMaster" then
		return "강화소", "Upgrade"
	end

	-- 3. 무기 분해
	if name == "DismantleMaster" or name == "분해스승" or name == "무기 분해" or name == "무기분해" or npcId == "DismantleMaster" then
		return "분해소", "Dismantle"
	end

	-- 4. 상점
	if npcType == "shop" or name == "GENERAL_STORE" or name == "TOOL_SHOP" or name == "FOOD_SHOP" or name == "BUILDING_SHOP" or name == "MERCHANT" or name == "Merchant" or string.find(string.lower(name), "shop") or string.find(string.lower(name), "merchant") then
		return "상점", "Shop"
	end

	-- 5. 의원 (콘닥터 등 의사 NPC 보너스 지원)
	if name == "Con_Doctor" or npcId == "Con_Doctor" then
		return "의원", "Doctor"
	end

	-- 6. 룬스톤 (일일보상)
	if name == "RuneStone" or npcId == "RuneStone" then
		return "일일보상", "Daily Reward"
	end

	-- 7. 텐트 (스폰지점 설정)
	if name == "Tent" or npcId == "Tent" then
		return "캠프", "Camp"
	end

	return nil, nil
end

local function localizeBillboard(billboard: BillboardGui)
	local textLabel = billboard:FindFirstChildOfClass("TextLabel")
	if not textLabel then return end

	local adornee = billboard.Adornee or billboard.Parent
	if not adornee then return end

	-- adornee부터 시작해 상위 NPC 모델을 찾습니다.
	local npc = adornee
	while npc and npc ~= Workspace do
		if npc:IsA("Model") and (npc.Parent.Name == "NPC" or npc.Parent.Name == "NPCs" or npc.Name == "Con_Doctor" or npc.Name == "RuneStone" or npc.Name == "Tent") then
			break
		end
		npc = npc.Parent
	end

	-- 폴더가 불확실하면 상위 모델이나 자기 자신 모델 판단
	if not npc or npc == Workspace then
		npc = adornee:IsA("Model") and adornee or adornee.Parent
	end

	if not npc or npc == Workspace then return end

	local isKorean = LocaleService.IsKorean()
	local krRole, enRole = getNPCRole(npc)
	if not krRole then return end

	local roleText = isKorean and krRole or enRole

	-- 이름 및 호칭 한글/영어 매핑
	local displayName = npc:GetAttribute("DisplayName") or npc.Name
	if displayName == "WeaponCrafter" then
		displayName = isKorean and "무기 장인" or "Weapon Crafter"
	elseif displayName == "EnhanceMaster" or displayName == "강화스승" then
		displayName = isKorean and "강화 장인" or "Enhance Artisan"
	elseif displayName == "DismantleMaster" or displayName == "분해스승" then
		displayName = isKorean and "분해 장인" or "Dismantle Artisan"
	elseif displayName == "Con_Doctor" then
		displayName = isKorean and "의원 콘닥터" or "Doctor Con"
	elseif displayName == "GENERAL_STORE" then
		displayName = isKorean and "상인 톰" or "Merchant Tom"
	elseif displayName == "TOOL_SHOP" then
		displayName = isKorean and "대장장이 한스" or "Blacksmith Hans"
	elseif displayName == "FOOD_SHOP" then
		displayName = isKorean and "요리사 루시" or "Chef Lucy"
	elseif displayName == "BUILDING_SHOP" then
		displayName = isKorean and "건축가 벤" or "Architect Ben"
	elseif displayName == "Merchant" or displayName == "잡화상" then
		displayName = isKorean and "잡화상" or "General Merchant"
	elseif displayName == "RuneStone" then
		displayName = isKorean and "룬스톤" or "Rune Stone"
	elseif displayName == "Tent" then
		displayName = isKorean and "해당 캠프에서 스폰" or "Spawn at this Camp"
	end

	-- 고급 텍스트 스타일링 적용 (RichText 활성화)
	textLabel.RichText = true
	textLabel.Text = string.format("<font color=\"#FFD700\"><b>[ %s ]</b></font>\n<font color=\"#F0F0F0\">%s</font>", roleText, displayName)

	-- 고양이나 소형 오브젝트 오프셋 보정
	if adornee.Name == "Cat" then
		billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	end
end

function NPCLabelController.Init()
	if initialized then return end
	initialized = true

	-- 1. 워크스페이스 내에 생성되거나 복제되는 NpcLabel 실시간 모니터링
	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("BillboardGui") and desc.Name == "NpcLabel" then
			task.defer(localizeBillboard, desc)
		end
	end)

	-- 2. 기존에 이미 복제된 NpcLabel 한 번에 처리
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BillboardGui") and desc.Name == "NpcLabel" then
			task.spawn(localizeBillboard, desc)
		end
	end

	print("[NPCLabelController] Client NPC BillboardGuis translation system initialized.")
end

return NPCLabelController
