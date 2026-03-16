-- UILocalizer.lua
-- UI 텍스트 한/영 자동 로컬라이징

local LocaleService = require(script.Parent.LocaleService)

local UILocalizer = {}
local observedInstances = setmetatable({}, { __mode = "k" })
local localizingInstances = setmetatable({}, { __mode = "k" })

local function titleFromId(id: string?): string
	local raw = tostring(id or "")
	if raw == "" then
		return raw
	end

	local words = string.split(string.lower(raw), "_")
	for i, w in ipairs(words) do
		if #w > 0 then
			words[i] = string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2)
		end
	end

	local title = table.concat(words, " ")
	title = string.gsub(title, "Trex", "T-Rex")
	title = string.gsub(title, "Hp", "HP")
	return title
end

local KO_TO_EN = {
	["INVENTORY [B]"] = "INVENTORY [B]",
	["CRAFTING"] = "CRAFTING",
	["ITEM DETAILS"] = "ITEM DETAILS",
	["SELECT ITEM"] = "SELECT ITEM",
	["Description"] = "Description",
	["수량 입력"] = "Enter Amount",
	["확인"] = "Confirm",
	["취소"] = "Cancel",
	["잠김"] = "Locked",
	["재료 부족"] = "Insufficient Materials",
	["제작 시작"] = "Start Crafting",
	["건축 시작"] = "Start Building",
	["CRAFTING TOOLS [C]"] = "CRAFTING TOOLS [C]",
	["RECIPE INFO"] = "RECIPE INFO",
	["NAME"] = "NAME",
	["[ MATS REQUIRED ]"] = "[ MATERIALS REQUIRED ]",
	["BLUEPRINTS [C]"] = "BLUEPRINTS [C]",
	["설계도 상세"] = "Blueprint Details",
	["시설을 선택하세요"] = "Select a Structure",
	["건설 하기"] = "Build",
	["[미해금] 기술 연구가 필요합니다."] = "[LOCKED] Tech research required.",
	["EQUIPMENT [E]"] = "EQUIPMENT [E]",
	["보유 포인트: 0"] = "Points: 0",
	["적용"] = "Apply",
	["초기화"] = "Reset",
	["아이템 이름"] = "Item Name",
	["정보"] = "Info",
	["[ 세트 효과 ]"] = "[ Set Effect ]",
	["JOURNAL [P]"] = "JOURNAL [P]",
	["전체"] = "All",
	["초원"] = "Grassland",
	["열대"] = "Tropical",
	["사막"] = "Desert",
	["툰드라"] = "Tundra",
	["동물을 선택하세요."] = "Select a creature.",
	["동물 정보 및 연구 보너스\n[연구 완료 시 상시 효과가 적용됩니다]"] = "Creature info and research bonus\n[Permanent effect applies when research is complete]",
	["장착 시 플레이어 효과"] = "Effect While Equipped",
	["업그레이드 상시 효과"] = "Permanent Upgrade Effect",
	["연구 보너스 정보가 없습니다.\n(추후 업데이트 예정)"] = "No research bonus info.\n(Coming soon)",
	["[장착 보너스 비활성]\n준비 중인 기능입니다."] = "[Equipment bonus disabled]\nFeature in preparation.",
	["섬 상점"] = "Island Shop",
	["구매"] = "Buy",
	["판매"] = "Sell",
	["보관함"] = "Storage",
	["보관함 아이템"] = "Storage Items",
	["내 소지품"] = "My Inventory",
	["제작"] = "Crafting",
	["품목"] = "Items",
	["진행 및 완료"] = "In Progress / Complete",
	["맡김 제작 : 0초"] = "Queued Craft: 0s",
	["수령"] = "Collect",
	["[Z] 상호작용"] = "[Z] Interact",
	["내구도 100%"] = "Durability 100%",
	["🛠️ 건축 컨트롤"] = "🛠️ Build Controls",
	["LMB : 배치 확정"] = "LMB : Confirm Placement",
	["R : 시설 회전"] = "R : Rotate Structure",
	["X : 건축 취소"] = "X : Cancel Build",
	["▲ 레벨업 가능"] = "▲ Level Up Available",
	["채집 중..."] = "Gathering...",
	["의식을 잃었습니다"] = "You Lost Consciousness",
	["가방 안의 아이템 일부를 잃어버렸습니다."] = "You lost some items from your bag.",
	["부활 대기 중..."] = "Waiting to Respawn...",
	["  ⚙ KNOWLEDGE TREE"] = "  ⚙ KNOWLEDGE TREE",
	["해당 노드 정보"] = "Node Info",
	["이름"] = "Name",
	["설명"] = "Description",
	["RESEARCH"] = "RESEARCH",
	["조건 미충족"] = "Requirements Not Met",
	["자원 부족"] = "Insufficient Resources",
	["연구 시작"] = "Start Research",
	["연구 완료!"] = "Research Complete!",
	["[ INV: B ]"] = "[ INV: B ]",
	["[ BUILD: C ]"] = "[ BUILD: C ]",
	["[ CHAR: E ]"] = "[ CHAR: E ]",
	["[ LOG: P ]"] = "[ LOG: P ]",
	["거점 관리"] = "Base Management",
	["거점 명칭"] = "Base Name",
	["새로운 거점"] = "New Base",
	["거점 이름을 입력하세요"] = "Enter base name",
	["거점 레벨: 1"] = "Base Level: 1",
	["보호 반경: 30m"] = "Protection Radius: 30m",
	["반경 확장 (Level Up)"] = "Expand Radius (Level Up)",
	["의식을 잃었습니다"] = "You Lost Consciousness",
	["가방 안의 아이템 일부를 잃어버렸습니다."] = "You lost some items from your bag.",
	["부활 대기 중..."] = "Waiting to Respawn...",
	["잠김 (해금 필요)"] = "Locked (Unlock required)",
	["기술 트리(K)에서 해금이 필요합니다."] = "Requires unlock in Tech Tree (K).",
	["[ 필요 재료 ]"] = "[ Required Materials ]",
	["거점"] = "Base",
	["이 위치에는 건설할 수 없습니다."] = "You cannot build at this location.",
	["건설 실패"] = "Build failed",
	["강화 포인트가 부족합니다."] = "Not enough stat points.",
	["빈 슬롯이 없습니다."] = "No empty slot available.",
	["시설에 접근했습니다. (제작은 인벤토리[I]에서 가능합니다)"] = "Facility opened. (Crafting is available in Inventory [I])",
	["기술 해금이 필요합니다."] = "Tech unlock required.",
	["구매 완료!"] = "Purchase complete!",
	["판매 완료!"] = "Sale complete!",
	["판매 실패"] = "Sale failed",
	["제작 의뢰 완료!"] = "Craft order placed!",
	["수령 완료!"] = "Collected successfully!",
	["레벨업!"] = "Level Up!",
	["능력치 강화 성공!"] = "Stat upgrade successful!",
	["도구 및 장비 제작은 인벤토리[I]의 제작 탭에서 가능합니다."] = "Tools and equipment can be crafted in Inventory [I] > Crafting.",
	["부활 지점이 설정되었습니다."] = "Respawn point has been set.",
	["줍기"] = "Pick Up",
	["사용"] = "Use",
	["대화"] = "Talk",
	["상호작용"] = "Interact",
	["[Z] 사용"] = "[Z] Use",
	["[Z] 대화"] = "[Z] Talk",
	["[Z] 상호작용"] = "[Z] Interact",
	["[Z] 상호"] = "[Z] Interact",
	["[R] 사용"] = "[R] Use",
	["생명력 (Health)"] = "Health",
	["기력 (Stamina)"] = "Stamina",
	["허기 (Hunger)"] = "Hunger",
	["❤️ 생명력 (Health)"] = "❤️ Health",
	["⚡ 기력 (Stamina)"] = "⚡ Stamina",
	["🍖 허기 (Hunger)"] = "🍖 Hunger",
	["캐릭터의 생존력을 나타냅니다.\n0이 되면 사망하여 리스폰됩니다.\n음식이나 치료제로 회복할 수 있습니다."] = "Shows your survivability.\nIf it reaches 0, you die and respawn.\nRecover it with food or healing items.",
	["구르기, 달리기, 수영 등 활동 시 소모됩니다.\n소모된 기력은 가만히 있으면 자동으로 회복됩니다."] = "Consumed by actions like rolling, running, and swimming.\nStamina regenerates automatically while resting.",
	["시간이 지남에 따라 점차 감소합니다.\n배고픔이 0이 되면 체력이 서서히 감소합니다.\n다양한 음식을 먹어 채워야 합니다."] = "Decreases gradually over time.\nIf it reaches 0, health slowly drains.\nEat food to restore it.",
	["피냄새"] = "Blood Scent",
	["사냥 후 피냄새가 나서 포식자가"] = "After hunting, your blood scent attracts predators",
	["리스폰 중..."] = "Respawning...",
	["시설"] = "Structure",
	["기초 건축"] = "Basic Building",
	["머리"] = "Head",
	["한벌옷"] = "Suit",
	["상의"] = "Top",
	["하의"] = "Bottom",
	["도구/무기"] = "Tool/Weapon",
	["최대 체력"] = "Max Health",
	["최대 스태미나"] = "Max Stamina",
	["최대 소지 무게"] = "Max Carry Weight",
	["작업 속도"] = "Work Speed",
	["공격력"] = "Attack",
	["방어력"] = "Defense",
	["완료"] = "Complete",
	["제작"] = "Crafting",
	["선택한 대상을 제작합니다."] = "Craft the selected target.",
	["<font color=\"#E63232\">✗ 기술 트리에서 해금 필요</font>"] = "<font color=\"#E63232\">✗ Unlock required in Tech Tree</font>",
	["<font color=\"#E63232\">기술 트리(K)에서 해금이 필요합니다.</font>"] = "<font color=\"#E63232\">Unlock required in Tech Tree (K).</font>",
	["<font color='#ff6464'>[미해금] 기술 연구가 필요합니다.</font>"] = "<font color='#ff6464'>[LOCKED] Tech research required.</font>",
}

local EN_TO_KO = {}
for ko, en in pairs(KO_TO_EN) do
	EN_TO_KO[en] = ko
end

local EN_TO_KO_OVERRIDES = {
	["INVENTORY [B]"] = "인벤토리 [B]",
	["CRAFTING"] = "제작",
	["ITEM DETAILS"] = "아이템 상세",
	["SELECT ITEM"] = "아이템 선택",
	["EQUIPMENT [E]"] = "장비 [E]",
	["JOURNAL [P]"] = "도감 [P]",
	["Description"] = "설명",
	["Name"] = "이름",
	["Info"] = "정보",
	["Build"] = "건설",
	["Start Crafting"] = "제작 시작",
	["Start Building"] = "건축 시작",
	["Pick Up"] = "줍기",
	["Use"] = "사용",
	["Storage"] = "보관함",
	["Item Name"] = "아이템 이름",
	["[ Set Effect ]"] = "[ 세트 효과 ]",
	["[ Required Materials ]"] = "[ 필요 재료 ]",
	["[ MATERIALS REQUIRED ]"] = "[ 필요 재료 ]",
	["Weight"] = "무게",
	["Amount"] = "수량",
	["[R] Use"] = "[R] 사용",
	["Blueprint Details"] = "설계도 상세",
	["No research bonus info.\n(Coming soon)"] = "연구 보너스 정보가 없습니다.\n(추후 업데이트 예정)",
	["[Equipment bonus disabled]\nFeature in preparation."] = "[장착 보너스 비활성]\n준비 중인 기능입니다.",
	["A useful item for survival and crafting."] = "생존과 제작에 유용한 아이템입니다.",
	["A structure used for survival and base progression."] = "생존과 거점 발전에 사용되는 시설입니다.",
	["A creature found on the island."] = "섬에서 발견되는 생물입니다.",
}

for en, ko in pairs(EN_TO_KO_OVERRIDES) do
	EN_TO_KO[en] = ko
end

local function localizePatternsToEnglish(text: string): string
	text = string.gsub(text, "등급:", "Rarity:")
	text = string.gsub(text, "방어력:", "Defense:")
	text = string.gsub(text, "내구도:", "Durability:")
	text = string.gsub(text, "^건설 실패:%s*(.+)$", "Build failed: %1")
	text = string.gsub(text, "^제작 완료:%s*(.+)$", "Craft complete: %1")
	text = string.gsub(text, "^🛠️ 제작 완료:%s*(.+)$", "🛠️ Craft complete: %1")
	text = string.gsub(text, "^📦 제작 완료:%s*수거 가능$", "📦 Craft complete: Ready to collect")
	text = string.gsub(text, "^강화 실패:%s*(.+)$", "Upgrade failed: %1")
	text = string.gsub(text, "^제작 실패:%s*(.+)$", "Craft failed: %1")
	text = string.gsub(text, "^구매 실패:%s*(.+)$", "Purchase failed: %1")
	text = string.gsub(text, "^수령 실패:%s*(.+)$", "Collect failed: %1")
	text = string.gsub(text, "^채집할 수 없는 상태입니다:%s*(.+)$", "Cannot gather now: %1")
	text = string.gsub(text, "^대상과 너무 멉니다%.?$", "Target is too far away.")
	text = string.gsub(text, "^도구가 파손되어 기능을 상실했습니다!$", "Tool is broken and unusable!")
	text = string.gsub(text, "^무기가 파손되어 공격할 수 없습니다!$", "Weapon is broken and cannot attack!")
	text = string.gsub(text, "^나무를 베려면 도끼를 장착해야 합니다!$", "Equip an axe to chop trees!")
	text = string.gsub(text, "^채광을 하려면 곡괭이를 장착해야 합니다!$", "Equip a pickaxe to mine rocks!")
	text = string.gsub(text, "^이 작업을 하기에 적합한 도구가 아닙니다%.?$", "This tool is not suitable for this action.")
	text = string.gsub(text, "^제작 취소됨$", "Crafting cancelled")
	text = string.gsub(text, "^획득:%s*(.+)%sx(%d+)$", "Obtained: %1 x%2")
	text = string.gsub(text, "^([%d]+)초 후 부활합니다$", "Respawning in %1s")
	text = string.gsub(text, "^%(최대:%s*(%d+)%)$", "(Max: %1)")
	text = string.gsub(text, "^맡김 제작%s*:%s*(%d+)초$", "Queued Craft: %1s")
	text = string.gsub(text, "^✅ 필요 자원\n(.+)$", "✅ Required Resources\n%1")
	text = string.gsub(text, "^💰 자원 부족\n(.+)$", "💰 Insufficient Resources\n%1")
	text = string.gsub(text, "^무게:%s*([%d%.]+)$", "Weight: %1")
	text = string.gsub(text, "^수량:%s*(%d+)$", "Amount: %1")
	text = string.gsub(text, "^보관함 아이템$", "Storage Items")
	text = string.gsub(text, "^내 소지품$", "My Inventory")
	text = string.gsub(text, "^보유 포인트:%s*(%d+)$", "Points: %1")
	text = string.gsub(text, "^남은 강화 포인트:%s*(%d+)$", "Unspent Points: %1")
	text = string.gsub(text, "^거점 레벨:%s*(%d+)$", "Base Level: %1")
	text = string.gsub(text, "^보호 반경:%s*(%d+)m$", "Protection Radius: %1m")
	text = string.gsub(text, "^내구도%s*(%d+)%%$", "Durability %1%%")
	text = string.gsub(text, "^내구도%s*(%d+)%/(%d+)$", "Durability %1/%2")
	text = string.gsub(text, "^SP:%s*(%d+)$", "SP: %1")
	text = string.gsub(text, "^💰%s*(%d+)$", "💰 %1")
	text = string.gsub(text, "^거점 이름이 변경되었습니다%.?$", "Base name changed.")
	text = string.gsub(text, "^거점이 확장되었습니다!$", "Base expanded!")
	text = string.gsub(text, "^확장 불가:%s*(.+)$", "Cannot expand: %1")
	text = string.gsub(text, "^이름 변경 실패:%s*(.+)$", "Rename failed: %1")
	text = string.gsub(text, "^거점 명칭$", "Base Name")
	text = string.gsub(text, "^새로운 거점$", "New Base")
	text = string.gsub(text, "^거점 이름을 입력하세요$", "Enter base name")
	text = string.gsub(text, "^반경 확장 %(Level Up%)$", "Expand Radius (Level Up)")
	text = string.gsub(text, "^제작 완료!$", "Craft Complete!")
	text = string.gsub(text, "^(.+)%s제작 완료!$", "%1 Craft complete!")
	text = string.gsub(text, "^제작이 취소되었습니다%.?$", "Crafting was cancelled.")
	text = string.gsub(text, "^제작 중 %((%d+)s%)$", "Crafting (%1s)")
	text = string.gsub(text, "^제작 중 %((%d+)초%)$", "Crafting (%1s)")
	return text
end

local function localizePatternsToKorean(text: string): string
	text = string.gsub(text, "Rarity:", "등급:")
	text = string.gsub(text, "Defense:", "방어력:")
	text = string.gsub(text, "Durability:", "내구도:")
	text = string.gsub(text, "^Build failed:%s*(.+)$", "건설 실패: %1")
	text = string.gsub(text, "^Craft complete:%s*(.+)$", "제작 완료: %1")
	text = string.gsub(text, "^🛠️ Craft complete:%s*(.+)$", "🛠️ 제작 완료: %1")
	text = string.gsub(text, "^📦 Craft complete:%s*Ready to collect$", "📦 제작 완료: 수거 가능")
	text = string.gsub(text, "^Upgrade failed:%s*(.+)$", "강화 실패: %1")
	text = string.gsub(text, "^Craft failed:%s*(.+)$", "제작 실패: %1")
	text = string.gsub(text, "^Purchase failed:%s*(.+)$", "구매 실패: %1")
	text = string.gsub(text, "^Collect failed:%s*(.+)$", "수령 실패: %1")
	text = string.gsub(text, "^Cannot gather now:%s*(.+)$", "채집할 수 없는 상태입니다: %1")
	text = string.gsub(text, "^Target is too far away%.?$", "대상과 너무 멉니다.")
	text = string.gsub(text, "^Tool is broken and unusable!$", "도구가 파손되어 기능을 상실했습니다!")
	text = string.gsub(text, "^Weapon is broken and cannot attack!$", "무기가 파손되어 공격할 수 없습니다!")
	text = string.gsub(text, "^Equip an axe to chop trees!$", "나무를 베려면 도끼를 장착해야 합니다!")
	text = string.gsub(text, "^Equip a pickaxe to mine rocks!$", "채광을 하려면 곡괭이를 장착해야 합니다!")
	text = string.gsub(text, "^This tool is not suitable for this action%.?$", "이 작업을 하기에 적합한 도구가 아닙니다.")
	text = string.gsub(text, "^Crafting cancelled$", "제작 취소됨")
	text = string.gsub(text, "^Obtained:%s*(.+)%sx(%d+)$", "획득: %1 x%2")
	text = string.gsub(text, "^Respawning in ([%d]+)s$", "%1초 후 부활합니다")
	text = string.gsub(text, "^%(Max:%s*(%d+)%)$", "(최대: %1)")
	text = string.gsub(text, "^Queued Craft:%s*(%d+)s$", "맡김 제작 : %1초")
	text = string.gsub(text, "^✅ Required Resources\n(.+)$", "✅ 필요 자원\n%1")
	text = string.gsub(text, "^💰 Insufficient Resources\n(.+)$", "💰 자원 부족\n%1")
	text = string.gsub(text, "^Weight:%s*([%d%.]+)$", "무게: %1")
	text = string.gsub(text, "^Amount:%s*(%d+)$", "수량: %1")
	text = string.gsub(text, "^Storage Items$", "보관함 아이템")
	text = string.gsub(text, "^My Inventory$", "내 소지품")
	text = string.gsub(text, "^Points:%s*(%d+)$", "보유 포인트: %1")
	text = string.gsub(text, "^Unspent Points:%s*(%d+)$", "남은 강화 포인트: %1")
	text = string.gsub(text, "^Base Level:%s*(%d+)$", "거점 레벨: %1")
	text = string.gsub(text, "^Protection Radius:%s*(%d+)m$", "보호 반경: %1m")
	text = string.gsub(text, "^Durability%s*(%d+)%%$", "내구도 %1%%")
	text = string.gsub(text, "^Durability%s*(%d+)%/(%d+)$", "내구도 %1/%2")
	text = string.gsub(text, "^SP:%s*(%d+)$", "SP: %1")
	text = string.gsub(text, "^💰%s*(%d+)$", "💰 %1")
	text = string.gsub(text, "^Base name changed%.?$", "거점 이름이 변경되었습니다.")
	text = string.gsub(text, "^Base expanded!$", "거점이 확장되었습니다!")
	text = string.gsub(text, "^Cannot expand:%s*(.+)$", "확장 불가: %1")
	text = string.gsub(text, "^Rename failed:%s*(.+)$", "이름 변경 실패: %1")
	text = string.gsub(text, "^Base Name$", "거점 명칭")
	text = string.gsub(text, "^New Base$", "새로운 거점")
	text = string.gsub(text, "^Enter base name$", "거점 이름을 입력하세요")
	text = string.gsub(text, "^Expand Radius %(Level Up%)$", "반경 확장 (Level Up)")
	text = string.gsub(text, "^Craft Complete!$", "제작 완료!")
	text = string.gsub(text, "^(.+)%sCraft complete!$", "%1 제작 완료!")
	text = string.gsub(text, "^Crafting was cancelled%.?$", "제작이 취소되었습니다.")
	text = string.gsub(text, "^Crafting %((%d+)s%)$", "제작 중 (%1s)")
	text = string.gsub(text, "^A useful item for survival and crafting%.?$", "생존과 제작에 유용한 아이템입니다.")
	text = string.gsub(text, "^A structure used for survival and base progression%.?$", "생존과 거점 발전에 사용되는 시설입니다.")
	text = string.gsub(text, "^A creature found on the island%.?$", "섬에서 발견되는 생물입니다.")
	return text
end

function UILocalizer.Localize(text: string?): string
	if text == nil then return "" end
	local src = tostring(text)
	if src == "" then return src end

	local lang = LocaleService.GetLanguage()
	if lang == "en" then
		return localizePatternsToEnglish(KO_TO_EN[src] or src)
	else
		return localizePatternsToKorean(EN_TO_KO[src] or src)
	end
end

function UILocalizer.LocalizeDataText(tableName: string, dataId: string, fieldName: string, sourceText: string?): string
	if sourceText == nil then
		return ""
	end

	local src = tostring(sourceText)
	if src == "" then
		return src
	end

	if LocaleService.GetLanguage() ~= "en" then
		return src
	end

	if fieldName == "name" then
		-- 데이터 레벨 번역이 없는 경우에도 최소한 영문 표기를 보장
		return titleFromId(dataId)
	end

	if fieldName == "description" then
		if tableName == "ItemData" then
			return "A useful item for survival and crafting."
		elseif tableName == "FacilityData" then
			return "A structure used for survival and base progression."
		elseif tableName == "CreatureData" then
			return "A creature found on the island."
		end
		return "Description available."
	end

	return UILocalizer.Localize(src)
end

local function applyLocalizedProperty(inst: Instance, propName: string)
	if localizingInstances[inst] then
		return
	end

	local raw = inst[propName]
	if type(raw) ~= "string" or raw == "" then
		return
	end

	local localized = UILocalizer.Localize(raw)
	if localized == raw then
		return
	end

	localizingInstances[inst] = true
	inst[propName] = localized
	localizingInstances[inst] = nil
end

local function localizeInstance(inst: Instance)
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		applyLocalizedProperty(inst, "Text")
		if inst:IsA("TextBox") then
			applyLocalizedProperty(inst, "PlaceholderText")
		end
	end
end

local function observeTextInstance(inst: Instance)
	if observedInstances[inst] then
		return
	end
	observedInstances[inst] = true

	localizeInstance(inst)

	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst:GetPropertyChangedSignal("Text"):Connect(function()
			localizeInstance(inst)
		end)
		if inst:IsA("TextBox") then
			inst:GetPropertyChangedSignal("PlaceholderText"):Connect(function()
				localizeInstance(inst)
			end)
		end
	end
end

function UILocalizer.LocalizeDescendants(root: Instance)
	if not root then return end
	observeTextInstance(root)
	for _, d in ipairs(root:GetDescendants()) do
		observeTextInstance(d)
	end
end

function UILocalizer.StartAuto(root: Instance)
	if not root then return end

	UILocalizer.LocalizeDescendants(root)

	root.DescendantAdded:Connect(function(inst)
		task.defer(function()
			observeTextInstance(inst)
		end)
	end)
end

return UILocalizer
