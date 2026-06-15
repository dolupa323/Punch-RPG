-- UILocalizer.lua
-- UI 텍스트 한/영 자동 로컬라이징

local LocaleService = require(script.Parent:WaitForChild("LocaleService"))

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
	["INVENTORY [Tab]"] = "INVENTORY [Tab]",
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
	["설원"] = "Snowy",
	["동물을 선택하세요."] = "Select a creature.",
	["동물 정보 및 연구 보너스\n[연구 완료 시 상시 효과가 적용됩니다]"] = "Creature info and research bonus\n[Permanent effect applies when research is complete]",
	["장착 시 플레이어 효과"] = "Effect While Equipped",
	["업그레이드 상시 효과"] = "Permanent Upgrade Effect",
	["연구 보너스 정보가 없습니다.\n(추후 업데이트 예정)"] = "No research bonus info.\n(Coming soon)",
	["[장착 보너스 비활성]\n준비 중인 기능입니다."] = "[Equipment bonus disabled]\nFeature in preparation.",
	["섬 상점"] = "Island Shop",
	["상점"] = "Shop",
	["경매장"] = "Auction House",
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
	["[Z] 상호작용"] = "[R] Interact",
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
	["[ INV: Tab ]"] = "[ INV: Tab ]",
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
	["기초 작업대 제작"] = "Basic Workbench Crafting",
	["나무 쪼개기"] = "Wood Splitting",
	["나무쪼개기"] = "Wood Splitting",
	["판재"] = "Plank",
	["돌도끼"] = "Stone Axe",
	["돌곡괭이"] = "Stone Pickaxe",
	["뼈검"] = "Bone Sword",
	["가죽옷"] = "Leather Armor",
	["깃털 투구"] = "Feather Helmet",
	["통나무를 가공해 만든 기본 건축/제작 자재."] = "A basic processed material made from logs for building and crafting.",
	["통나무를 쪼개어 판재로 가공합니다."] = "Split logs into planks.",
	["부활 지점이 설정되었습니다."] = "Respawn point has been set.",
	["줍기"] = "Pick Up",
	["사용"] = "Use",
	["대화"] = "Talk",
	["상호작용"] = "Interact",
	["[Z] 사용"] = "[R] Use",
	["[Z] 대화"] = "[R] Talk",
	["[Z] 상호작용"] = "[R] Interact",
	["[Z] 상호"] = "[R] Interact",
	["[R] 대화"] = "[R] Talk",
	["[R] 상호작용"] = "[R] Interact",
	["[R] 사용"] = "[R] Use",
	["[T] 해체"] = "[T] Dismantle",
	["이안"] = "Ian",
	["선배 무전"] = "Senior Radio",
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
	["인벤토리 칸"] = "Inventory Slots",
	["작업 속도"] = "Work Speed",
	["공격력"] = "Attack",
	["방어력"] = "Defense",
	["완료"] = "Complete",
	["진행중"] = "In Progress",
	["튜토리얼 퀘스트"] = "Tutorial Quest",
	["튜토리얼 완료"] = "Tutorial Complete",
	["보상이 지급되었습니다"] = "Rewards have been granted",
	["획득:"] = "Obtained:",
	["완료 보상:"] = "Completion Reward:",
	["챕터 보상:"] = "Chapter Reward:",
	["목표:"] = "Objective:",
	["다음 튜토리얼 목표 진행 중"] = "Proceeding to the next tutorial objective",
	["박스를 클릭해 완료"] = "Click the panel to complete",
	["R 또는 클릭으로 다음"] = "Press R or click to continue",
	["[R] 무전 수신"] = "[R] Radio Incoming",
	["비상 무전기"] = "Emergency Radio",

	-- Tutorial step text/command/tip
	["잔돌 1개, 나뭇가지 1개부터 챙기기"] = "Gather 1 Small Stone and 1 Branch first",
	["주변에서 SMALL_STONE 1개 + BRANCH 1개 줍기"] = "Pick up 1 Small Stone + 1 Branch nearby",
	["쓸만한 게 보이면 일단 주워라. 너무 멀리 가지 말고 주변부터 훑어."] = "Pick up anything useful first. Do not go too far; search nearby.",
	["조잡한 돌도끼 제작"] = "Craft a Crude Stone Axe",
	["인벤토리 제작 탭에서 CRAFT_CRUDE_STONE_AXE 제작"] = "Craft CRAFT_CRUDE_STONE_AXE in the Inventory Craft tab",
	["가방을 열어서 도구를 제작해. 부족한 재료는 주변에서 마저 챙기고."] = "Open your bag and craft the tool. Gather any missing materials nearby.",
	["나무 자원 확보"] = "Secure wood resources",
	["WOOD 또는 LOG 1개 이상 확보"] = "Obtain at least 1 WOOD or LOG",
	["너무 굵은 나무에 욕심내지 말고, 만만한 걸로 하나만 먼저 챙겨."] = "Do not go for large trees yet; get an easy one first.",
	["식량 확보를 위한 사냥"] = "Hunt for food",
	["DODO 1마리 처치"] = "Kill 1 DODO",
	["한두 번 치고 거리를 벌려. 무식하게 맞서 싸우지 말고 치고 빠지라고."] = "Hit once or twice and back off. Do not trade blows; strike and retreat.",
	["밤 대비 온기 거점 만들기"] = "Build a warm base for night",
	["CAMPFIRE 1개 설치"] = "Place 1 CAMPFIRE",
	["평평하고 시야가 트인 곳에 설치해. 나중에 도망칠 때 길 막히지 않게 조심하고."] = "Place it on flat open ground so your escape path stays clear.",
	["고기 1개 조리"] = "Cook 1 meat",
	["CRAFT_COOKED_MEAT 제작"] = "Craft CRAFT_COOKED_MEAT",
	["불이 꺼지지 않게 장작 잘 확인하고. 든든하게 먹어둬."] = "Keep the fire going with fuel. Eat well before moving on.",
	["거점 중심점 확보"] = "Secure your base anchor point",
	["CAMP_TOTEM 1개 설치"] = "Place 1 CAMP_TOTEM",
	["앞으로 돌아다니기 편하도록 중간 지점에 세우는 게 좋을 거다."] = "Place it near a central route for easier movement later.",
	["수면/복귀 지점 확보"] = "Secure sleep/respawn point",
	["LEAN_TO 1개 설치"] = "Place 1 LEAN_TO",
	["모닥불 온기가 닿도록 너무 멀지 않게 세우고, 길은 막지 마라."] = "Place it close enough to the campfire warmth and do not block paths.",

	-- Radio/tutorial dialogue lines
	["좋아, 그 정도면 됐다."] = "Good. That is enough.",
	["좋아, 재료는 모았군."] = "Good, you gathered the materials.",
	["좋아, 장작이든 통나무든 하나만 먼저 가져와."] = "Good. Bring either firewood or a log first.",
	["좋아, 잡았군. 바로 불 피울 준비 해."] = "Good, you got it. Get ready to light a fire.",
	["좋아, 불 붙었다. 이제 고기 굽자."] = "Good, the fire is lit. Now cook meat.",
	["좋아, 거점 잡혔다. 마지막으로 잠자리 만든다."] = "Good, your base is set. Build your shelter last.",
	["끝났다. 이제부터가 진짜 생존의 시작이다."] = "Done. Now the real survival begins.",
	["제작"] = "Crafting",
	["선택한 대상을 제작합니다."] = "Craft the selected target.",
	["<font color=\"#E63232\">✗ 기술 트리에서 해금 필요</font>"] = "<font color=\"#E63232\">✗ Unlock required in Tech Tree</font>",
	["<font color=\"#E63232\">기술 트리(K)에서 해금이 필요합니다.</font>"] = "<font color=\"#E63232\">Unlock required in Tech Tree (K).</font>",
	["<font color='#ff6464'>[미해금] 기술 연구가 필요합니다.</font>"] = "<font color='#ff6464'>[LOCKED] Tech research required.</font>",

	-- NPC Shops
	["상인 톰"] = "Merchant Tom",
	["대장장이 한스"] = "Blacksmith Hans",
	["요리사 루시"] = "Chef Lucy",
	["건축가 벤"] = "Architect Ben",
	["잡화상"] = "General Merchant",
	["기본 물품을 판매하는 상점입니다."] = "A shop that sells basic items.",
	["각종 도구와 무기를 판매합니다."] = "A shop that sells various tools and weapons.",
	["음식과 물약을 판매합니다."] = "A shop that sells food and potions.",
	["건축 재료와 설계도를 판매합니다."] = "A shop that sells building materials and blueprints.",
	["각종 전리품과 재료를 매입하며, 유용한 잡화를 판매합니다."] = "Buys loot and materials, and sells useful general goods.",
	
	-- Rune Stone Claims
	["룬스톤의 힘은 이미 모두 소진되었습니다."] = "The runestone's power has been fully depleted.",
	["먼저 속성을 선택한 뒤 다시 시도하세요."] = "Please select an element first and try again.",
	["인벤토리가 가득 찼습니다."] = "Inventory is full.",
	["일일보상"] = "Daily Reward",
	["이미 오늘의 일일보상을 수령했습니다."] = "You have already claimed today's daily reward.",
	["일일보상으로 강화 하락방지권과 100골드를 획득했습니다!"] = "Obtained 1 Enhancement Protection Scroll and 100 Gold as daily reward!",


	-- Item Names
	["불씨"] = "Fire Ember",
	["물방울"] = "Water Droplet",
	["짙은 밤"] = "Dark Night",
	["나뭇가지"] = "Branch",
	["슬라임 점액"] = "Slime Mucus",
	["뿔 애벌레의 뿔"] = "Horned Larva Horn",
	["박쥐의 송곳니"] = "Bat Fang",
	["골렘의 돌조각"] = "Golem Stone Fragment",
	["나무 골렘의 영혼조각"] = "Wood Golem Soul Fragment",
	["잔돌"] = "Small Stone",
	["돌"] = "Stone",
	["나무"] = "Wood",
	["섬유"] = "Fiber",
	["야생 베리"] = "Wild Berry",
	["고기완자"] = "Meatball",
	["코코넛 구이"] = "Roasted Coconut",
	["대추야자 열매"] = "Date Fruit",
	["대추야자 구이"] = "Roasted Date",
	["기초 HP 포션"] = "Basic HP Potion",
	["기초 MP 포션"] = "Basic MP Potion",
	["통나무"] = "Log",
	["부싯돌"] = "Flint",
	["사막나무 통나무"] = "Desert Log",
	["사막 갈대"] = "Desert Reed",
	["청동 광석"] = "Bronze Ore",
	["튼튼한 풀잎"] = "Tough Leaf",
	["수지"] = "Resin",
	["철광석"] = "Iron Ore",
	["석탄"] = "Coal",
	["청동 주괴"] = "Bronze Ingot",
	["철 주괴"] = "Iron Ingot",
	["금광석"] = "Gold Ore",
	["조잡한 돌도끼"] = "Crude Stone Axe",
	["조잡한 돌곡괭이"] = "Crude Stone Pickaxe",
	["돌도끼"] = "Stone Axe",
	["돌곡괭이"] = "Stone Pickaxe",
	["뼈검"] = "Bone Sword",
	["돌 낫"] = "Stone Sickle",
	["횃불"] = "Torch",
	["말랑봉"] = "Soft Club",
	["각창"] = "Gakchang",
	["송곳니의 창"] = "Fang Spear",
	["아이언 스태프"] = "Iron Staff",
	["포이즌 스피어"] = "Poison Spear",
	["나이트 스피어"] = "Knight Spear",
	["소울 스태프"] = "Soul Staff",
	["저스티스 스피어"] = "Spear of Justice",
	["블루파이어"] = "Bluefire",
	["나무 몽둥이"] = "Wooden Club",
	["나무 활"] = "Wooden Bow",
	["돌 화살"] = "Stone Arrow",
	["돌 괭이"] = "Stone Hoe",
	["청동 곡괭이"] = "Bronze Pickaxe",
	["청동 도끼"] = "Bronze Axe",
	["청동 검"] = "Bronze Sword",
	["청동 활"] = "Bronze Bow",
	["철 곡괭이"] = "Iron Pickaxe",

	-- Stats Panel
	["귀걸이"] = "Earring",
	["목걸이"] = "Necklace",
	["반지 1"] = "Ring 1",
	["반지 2"] = "Ring 2",
	["스탯"] = "Stats",
	["전투력"] = "Combat Power",
	["치명타 확률"] = "Crit Chance",
	["치명타 피해"] = "Crit Damage",
	["이동 속도"] = "Move Speed",
	["체력"] = "Health",

	-- Enhancement UI
	["[ 공격력 스펙 변화 ]"] = "[ Attack Stat Changes ]",
	["강화 단계"] = "Enhancement Level",
	["무기 공격력"] = "Weapon Attack",
	["[ 강화 요건 및 확률 ]"] = "[ Upgrade Requirements & Chance ]",
	["성공 확률"] = "Success Rate",
	["실패 패널티"] = "Failure Penalty",
	["필요 골드"] = "Required Gold",
	["최대 강화 단계(+50)에 도달했습니다!"] = "Reached maximum enhancement level (+50)!",
	["더 이상 강화를 진행할 수 없습니다."] = "Cannot upgrade any further.",
	["강화 완료"] = "Upgrade Complete",
	["골드 부족"] = "Insufficient Gold",
	["무기 선택 필요"] = "Weapon Selection Required",
	["강화할 무기를 선택하세요"] = "Select a weapon to upgrade",
	["무기를 선택하면 공격력 및 강화 스펙 변화가 표시됩니다."] = "Select a weapon to display attack and enhancement changes.",
	["소지한 골드와 강화 성공률을 여기에 표시합니다."] = "Gold and success rates will be shown here.",
	["하락 방지권 선택"] = "Select Protection Scroll",
	["없음"] = "None",
	["선택"] = "Select",
	["강화 시도"] = "Attempt Upgrade",
	["하락방지권 없음"] = "No Protection Scroll",
	["하락방지권이 없습니다.\n계속 강화하시겠습니까?"] = "You have no protection scroll.\nDo you want to continue?",
	["현재 무기 공격력"] = "Current Weapon Attack",
	["강화 비용"] = "Enhancement Cost",
	["무기를 선택하면 공격력이 표시됩니다."] = "Select a weapon to display its attack power.",
	["성공 확률과 강화 비용을 여기에 표시합니다."] = "Success rate and enhancement cost will be shown here.",
	["실패 시 무기의 강화가 내려갑니다."] = "Enhancement level drops on failure.",
	["보유"] = "Owned",
	["적용 중"] = "Applied",
	["강화 진행 중..."] = "Upgrading...",


	["강화할 무기를 선택해야 합니다."] = "You must select a weapon to enhance.",
	["골드가 부족합니다."] = "Not enough gold.",
	["이미 최대 강화 단계입니다."] = "Already at max enhancement level.",
	["서버 통신 오류가 발생했습니다."] = "Server communication error occurred.",

	-- Dismantle UI
	["무기 분해소 (Dismantle Recycler)"] = "Dismantle Recycler",
	["분해할 무기를 목록에서 선택하세요."] = "Select a weapon from the list to dismantle.",
	["분해 시 100% 반환 재료 (50% 비율)"] = "Dismantle Materials (50% Refund Ratio)",
	["무기 분해 실행"] = "Dismantle Weapon",
	["분해 가동 중..."] = "Dismantling...",
	["가방이 꽉 차서 재료를 반환받을 공간이 없습니다."] = "Inventory is full. No space to receive materials.",
	["정말로 <font color='#FF4040'>%s</font> 무기를 분해하시겠습니까?<br/>분해한 장비는 복구할 수 없으며 원본 재료의 50%%를 돌려받습니다."] = "Are you sure you want to dismantle <font color='#FF4040'>%s</font>?<br/>Dismantled equipment cannot be recovered and returns 50%% of original materials.",

	-- Shop & Premium Shop UI
	["교역상 판매 물품"] = "Trader Goods",
	["이 상점은 매입만 합니다."] = "This shop only buys.",
	["교역상이 판매하는 물품입니다."] = "Items sold by the trader.",
	["구매할 수 있는 물품이 없습니다."] = "No items available to purchase.",
	["내 아이템 판매"] = "Sell My Items",
	["거의 모든 전리품을 판매할 수 있습니다."] = "You can sell almost any loot.",
	["상점이 매입하는 아이템 목록입니다."] = "Items this shop will buy.",
	["판매 가능한 아이템이 없습니다."] = "No items available to sell.",
	["수량 선택"] = "Select Quantity",
	["구매하기"] = "Buy",
	["보유중"] = "Owned",
	["구매 불가"] = "Cannot Buy",
	["인벤토리 칸이 이미 최대입니다."] = "Inventory slots are already maxed.",
	["이미 보유한 패스입니다."] = "You already own this pass.",
	["게임 플레이에 직접 도움이 되는 상품을 구매할 수 있습니다."] = "You can purchase items that directly help your gameplay.",
	["설명이 없습니다."] = "No description available.",
	["상품"] = "Product",
	["수량 입력"] = "Enter Amount",

	-- Product Config
	["드랍률 2배 패스"] = "Double Drop Rate Pass",
	["몬스터 처치 보상 드롭률이 영구적으로 2배 증가합니다."] = "Permanently doubles the drop rate from monster kills.",
	["초보자 스타터 팩"] = "Starter Support Pack",
	["일정 레벨 이하에서만 구매할 수 있는 초보자 지원 팩입니다."] = "A beginner support pack purchasable only below a certain level.",
	["인벤토리 확장권"] = "Inventory Expansion Scroll",
	["인벤토리 최대 칸 수가 30칸 증가합니다."] = "Increases maximum inventory slots by 30.",
	["하락 방지권"] = "Enhancement Protection Scroll",
	["강화 실패 시 등급 하락을 막아주는 주문서입니다."] = "A scroll that prevents enhancement level from dropping on failure.",
	["하락 방지권 10개"] = "Enhancement Protection Scroll x10",
	["강화 실패 시 등급 하락을 막아주는 주문서 10개가 지급됩니다."] = "Provides 10 scrolls that prevent enhancement level from dropping.",
	["100Gold"] = "100 Gold",
	["골드 100이 지급됩니다."] = "Grants 100 Gold.",
	["1000Gold"] = "1000 Gold",
	["골드 1000이 지급됩니다."] = "Grants 1000 Gold.",
	["제작 즉시 완료"] = "Instant Crafting",
	["진행 중인 제작 작업을 즉시 완료합니다."] = "Instantly completes the in-progress crafting work.",

	-- Tamed creatures, traits, options
	["생명"] = "HP",
	["이동속도"] = "Move Speed",
	["공격"] = "Attack",
	["레벨"] = "Level",
	["방어"] = "Defense",
	["속도"] = "Speed",
	["과감함"] = "Bold",
	["소심함"] = "Timid",
	["신중함"] = "Careful",
	["경솔함"] = "Reckless",
	["민첩함"] = "Agile",
	["둔감함"] = "Sluggish",
	["강인함"] = "Hardy",
	["나약함"] = "Frail",
	["간이제작"] = "Simple Crafting",
	["동물 관리"] = "Manage Creatures",
	["정렬"] = "Sort",
	["소환가능"] = "Summonable",
	["소환하기"] = "Summon",
	["풀어주기"] = "Release",
	["회수하기"] = "Recall",
	["기절 (소환 불가)"] = "Fainted (Cannot Summon)",
	["길들인 동물이 없습니다.\n크리처를 포획하고 상자를 사용하세요."] = "No tamed creatures.\nCapture creatures and use boxes.",
	["점프"] = "Jump",
	["대쉬"] = "Dash",
	["품질"] = "Quality",
	["버프"] = "Buff",
	["데버프"] = "Debuff",

	-- Interact/Build UI
	["블럭 건축"] = "Block Build",
	["LMB : 블럭 배치"] = "LMB: Place Block",
	["무기/도구 공격 : 블럭 파괴"] = "Weapon/Tool Attack: Destroy Block",
	["X : 배치 취소"] = "X: Cancel Placement",
	["🛠️ 건축 컨트롤"] = "🛠️ Build Controls",
	["LMB : 배치 확정"] = "LMB: Confirm Placement",
	["R : 시설 회전"] = "R: Rotate Structure",
	["X : 건축 취소"] = "X: Cancel Build",
	["체력"] = "Health",

	-- Mobs & Items
	["슬라임"] = "Slime",
	["뿔 애벌레"] = "Horned Larva",
	["스텀프"] = "Stump",
	["목월도"] = "Mogwoldo",

	-- NPCs
	["속성 스승"] = "Element Master",
	["어둠 스승"] = "Dark Master",
	["강화스승"] = "Enhance Master",
	["무기제작"] = "Weapon Crafter",
	["무기 장인"] = "Weapon Crafter",
	["콘닥터"] = "Con Doctor",
	["비상 무전기"] = "Emergency Radio",

	-- Interact prompts
	["[R] 채집"] = "[R] Gather",
	["[R] 대화"] = "[R] Talk",
	["[R] 사용"] = "[R] Use",
	["[T] 해체"] = "[T] Dismantle",
	["[R] 공룡 메뉴"] = "[R] Creature Menu",
	["[R] 무전 수신"] = "[R] Radio Incoming",
	["[R] 상호작용"] = "[R] Interact",

	-- Totem UI & general base
	["영토 확장"] = "Expand Territory",
	["확장 방향 닫기"] = "Close Expansion Directions",
	["보호 상태: 활성"] = "Protection State: Active",
	["보호 상태: 비활성"] = "Protection State: Inactive",
	["유지비 만료: 현재 약탈 가능 상태"] = "Upkeep Expired: Looting Allowed",
	["영역 확인"] = "Check Territory",
	["새로고침"] = "Refresh",
	["확장 방향 선택"] = "Select Expansion Direction",
	["북쪽 확장"] = "Expand North",
	["서쪽 확장"] = "Expand West",
	["동쪽 확장"] = "Expand East",
	["남쪽 확장"] = "Expand South",

	-- Storage UI
	["보관함"] = "Storage",
	["보관함 아이템"] = "Storage Items",
	["내 소지품"] = "My Inventory",
	["골드 인출"] = "Withdraw Gold",
	["골드 보관"] = "Deposit Gold",
	["아이템과 별도로 보관되는 골드입니다."] = "Gold stored separately from items.",
	["아이템 정보"] = "Item Info",
	["슬롯 위에 마우스를 올리면 정보를 볼 수 있습니다."] = "Hover over a slot to view details.",
	["빈 슬롯"] = "Empty Slot",

	-- Premium Shop
	["게임 패스"] = "Game Pass",
	["게임 플레이에 직접 도움이 되는 상품을 구매할 수 있습니다."] = "You can purchase items that directly help your gameplay.",

	-- Skill Tree / Rune
	["룬 시스템"] = "Rune System",
	["스킬"] = "Skill",
	["룬 슬롯 1"] = "Rune Slot 1",
	["룬 슬롯 2"] = "Rune Slot 2",
	["룬 슬롯 3" ] = "Rune Slot 3",
	["인벤토리에서 룬을 드래그해 장착하세요.\n더블클릭 또는 우클릭하여 해제할 수 있습니다."] = "Drag runes from inventory to equip them.\nDouble-click or right-click to unequip.",

	-- Tent / Spawn
	["스폰지점 설정"] = "Set Respawn Point",
	["이 텐트를 부활 지점으로 설정하시겠습니까?"] = "Set this tent as your respawn point?",
	["예"] = "Yes",
	["아니오"] = "No",
	["스폰지점이 텐트로 설정되었습니다."] = "Respawn point set to tent.",
	["스폰지점 설정에 실패했습니다."] = "Failed to set respawn point.",

	-- Tech UI
	["기초 생존 및 건축"] = "Basic Survival & Build",
	["부락의 발전"] = "Settlement Progression",
	["기초 방어구"] = "Basic Armor",
	["본격 수렵"] = "Active Hunting",
	["나무 활"] = "Wooden Bow",
	["나무 건축 숙련"] = "Wood Build Mastery",
	["흑요석 가공"] = "Obsidian Crafting",
	["돌 용광로"] = "Stone Furnace",
	["청동 제련"] = "Bronze Smelting",
	["청동기 작업대"] = "Bronze Workbench",
	["청동 도구"] = "Bronze Tools",
	["청동 무기 및 갑옷"] = "Bronze Weapons & Armor",
	["대형 보관함"] = "Large Storage Box",
	["철 용광로"] = "Iron Furnace",
	["석조 건축"] = "Stone Build",
	["철기 작업대"] = "Iron Workbench",
	["철제 도구 및 무기"] = "Iron Tools & Weapons",
	["SP: "] = "SP: ",
	["선행 필요: "] = "Prerequisite: ",
	["아바타 아앙의 전설: 검술 RPG"] = "Legend of Avatar Aang: Sword RPG",
	["숙명의 원소 속성을 선택하여 검의 지배자가 되십시오"] = "Choose your destined element and become the master of the sword",
	["물의 스승"] = "Master of Water",
	["“세상은 언제나 변한다.\n강한 자가 살아남는 것이 아니라, 흐름을 아는 자가 살아남는다.\n자, 선택하라. 너는 물처럼 변하고, 다시 일어설 수 있느냐?”"] = "“The world always changes.\nIt is not the strongest that survives, but the one who understands the flow.\nChoose. Can you become like water and rise again?”",
	["불의 스승"] = "Master of Fire",
	["“내 힘을 받는 순간, 너는 더 이상 뒤로 물러설 수 없다.\n적을 베고, 어둠을 태우고, 네 길을 스스로 밝혀라.\n자, 선택하라. 너의 심장은 불타고 있느냐?”"] = "“The moment you receive my power, you can no longer turn back.\nStrike down your enemies, burn the darkness, and light your own path.\nChoose. Is your heart burning?”",
	["어둠의 스승"] = "Master of Darkness",
	["“빛은 필연적으로 그림자를 드리운다.\n모두가 빛을 우러러볼 때, 어둠은 묵묵히 모든 것을 삼킨다.\n자, 선택하라. 너는 기꺼이 심연 속으로 걸어갈 수 있느냐?”"] = "“Light inevitably casts a shadow.\nWhile everyone looks up to the light, darkness silently consumes all.\nChoose. Are you willing to walk into the abyss?”",
	["예 (Choose)"] = "Yes (Choose)",
	["아니오 (Cancel)"] = "No (Cancel)",
	["근접전/생존"] = "Melee / Survival",
	["도구/무기"] = "Tools / Weapons",
	["건축/설비"] = "Build / Facilities",
	["포획/이동"] = "Catch / Move",
	["이 레시피와 시설을 활성화합니다."] = "Activates this recipe and structure.",
	["레벨 부족: Lv.%d 필요"] = "Required: Lv.%d",
	["필요 자원:"] = "Required Resources:",
	["자원 부족"] = "Insufficient Resources",
	["[ 룬 분류 ]"] = "[ Rune Type ]",
	["[ 장착 효과 ]"] = "[ Equip Effect ]",
	["액티브 (Active)"] = "Active",
	["패시브 (Passive)"] = "Passive",
	["[ 원소 속성 ]"] = "[ Element ]",
	["치명타 확률 +%d%%"] = "Crit Chance +%d%%",
	["최대 체력 +%d"] = "Max HP +%d",
	["공격력 +%d"] = "Attack +%d",
	["공격 속도 +5% / 스킬 재사용 대기시간 -5%"] = "Attack Speed +5% / Skill Cooldown -5%",
	["최대 체력 증가"] = "Increase Max HP",
	["공격력 증가"] = "Increase Attack",
	["액티브 스킬 '파이어볼' 개방"] = "Unlocks Active Skill 'Fireball'",
	["화염 속성 액티브 스킬 가동"] = "Activates Fire Active Skill",
	["물 속성 액티브 스킬 가동"] = "Activates Water Active Skill",
	["어둠 속성 액티브 스킬 가동"] = "Activates Dark Active Skill",
	["플레이어 주변을 도는 화염 오라"] = "Flame Aura rotating around player",
	["플레이어 주변을 도는 파도 오라"] = "Wave Aura rotating around player",
	["플레이어 주변을 도는 그림자 오라"] = "Shadow Aura rotating around player",
	["범위 내 적에게 지속 피해"] = "Continuous damage to enemies in range",
	["장착 시 숨겨진 효과 발동"] = "Triggers hidden effects when equipped",
	["%s 룬"] = "%s Rune",
	["속성: "] = "Attributes: ",
	["품질: %d / 100"] = "Quality: %d / 100",
	["보유 골드: %d\n상점, 토템 유지비, 거래에 사용하는 화폐입니다."] = "Held Gold: %d\nCurrency used for shops, totem upkeep, and trading.",
	["보관 골드: %d"] = "Stored Gold: %d",
	["소지 골드: %d"] = "Held Gold: %d",
	["골드: 0"] = "Gold: 0",
}

local EN_TO_KO = {}
for ko, en in pairs(KO_TO_EN) do
	EN_TO_KO[en] = ko
end

local EN_TO_KO_OVERRIDES = {
	["INVENTORY [Tab]"] = "인벤토리 [Tab]",
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
	["Slots"] = "칸",
	["Amount"] = "수량",
	["[R] Use"] = "[R] 사용",
	["Chapter Reward:"] = "챕터 보상:",
	["[T] Dismantle"] = "[T] 해체",
	["Ian"] = "이안",
	["Senior Radio"] = "선배 무전",
	["Blueprint Details"] = "설계도 상세",
	["No research bonus info.\n(Coming soon)"] = "연구 보너스 정보가 없습니다.\n(추후 업데이트 예정)",
	["[Equipment bonus disabled]\nFeature in preparation."] = "[장착 보너스 비활성]\n준비 중인 기능입니다.",
	["A useful item for survival and crafting."] = "생존과 제작에 유용한 아이템입니다.",
	["A structure used for survival and base progression."] = "생존과 거점 발전에 사용되는 시설입니다.",
	["A creature found on the island."] = "섬에서 발견되는 생물입니다.",
	["Wood Splitting"] = "나무 쪼개기",
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
	text = string.gsub(text, "^튜토리얼 퀘스트 %((%d+)%/(%d+)%)$", "Tutorial Quest (%1/%2)")
	text = string.gsub(text, "^진행도:%s*(%d+)%s*/%s*(%d+)$", "Progress: %1 / %2")
	text = string.gsub(text, "^단계:%s*(%d+)%s*/%s*(%d+)$", "Step: %1 / %2")
	text = string.gsub(text, "^목표:%s*(.+)$", "Objective: %1")

	-- Totem UI patterns
	text = string.gsub(text, "^보호 상태:%s*(.+)$", "Protection: %1")
	text = string.gsub(text, "^효과 유지 기간:%s*(.+)$", "Upkeep: %1")
	text = string.gsub(text, "^보호 범위:%s*(.+)$", "Range: %1")
	text = string.gsub(text, "^보유 골드:%s*(%d+)$", "Gold: %1")
	text = string.gsub(text, "^보관 골드:%s*(%d+)$", "Stored Gold: %1")
	text = string.gsub(text, "^소지 골드:%s*(%d+)$", "Held Gold: %1")
	text = string.gsub(text, "^확장 상태: 북 (.-) / 남 (.-) / 동 (.-) / 서 (.-)\n다음 확장: (.+)$", "Expansion: N %1 / S %2 / E %3 / W %4\nNext: %5")
	text = string.gsub(text, "^([%d]+)일%s*([%d]+)시간$", "%1d %2h")
	text = string.gsub(text, "^([%d]+)시간%s*([%d]+)분$", "%1h %2m")
	text = string.gsub(text, "^([%d]+)분$", "%1m")
	text = string.gsub(text, "^재배치 포인트 사용 %((%d+)%s*남음%)$", "Use relocation points (%1 left)")
	text = string.gsub(text, "^(%d+)일 유지 ~ (%d+)%s*Gold$", "Upkeep %1 Day(s) ~ %2 Gold")
	
	-- Rune Stone Claims
	text = string.gsub(text, "^액티브 룬 %[(.+)%]을 획득했습니다%! %((%d+)%/(%d+)%)$", "Acquired Active Rune [%1]! (%2/%3)")
	text = string.gsub(text, "^액티브 룬 %[(.+)%]을 획득했습니다%! %(누적 (%d+)회 획득%)$", "Acquired Active Rune [%1]! (Accumulated %2 claims)")
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
	text = string.gsub(text, "^Tutorial Quest %((%d+)%/(%d+)%)$", "튜토리얼 퀘스트 (%1/%2)")
	text = string.gsub(text, "^Progress:%s*(%d+)%s*/%s*(%d+)$", "진행도: %1 / %2")
	text = string.gsub(text, "^Step:%s*(%d+)%s*/%s*(%d+)$", "단계: %1 / %2")
	text = string.gsub(text, "^Objective:%s*(.+)$", "목표: %1")
	text = string.gsub(text, "^A useful item for survival and crafting%.?$", "생존과 제작에 유용한 아이템입니다.")
	text = string.gsub(text, "^A structure used for survival and base progression%.?$", "생존과 거점 발전에 사용되는 시설입니다.")
	text = string.gsub(text, "^A creature found on the island%.?$", "섬에서 발견되는 생물입니다.")

	-- Totem UI patterns
	text = string.gsub(text, "^Protection:%s*(.+)$", "보호 상태: %1")
	text = string.gsub(text, "^Upkeep:%s*(.+)$", "효과 유지 기간: %1")
	text = string.gsub(text, "^Range:%s*(.+)$", "보호 범위: %1")
	text = string.gsub(text, "^Gold:%s*(%d+)$", "보유 골드: %1")
	text = string.gsub(text, "^Stored Gold:%s*(%d+)$", "보관 골드: %1")
	text = string.gsub(text, "^Held Gold:%s*(%d+)$", "소지 골드: %1")
	text = string.gsub(text, "^Expansion: N (.-) / S (.-) / E (.-) / W (.-)\nNext: (.+)$", "확장 상태: 북 %1 / 남 %2 / 동 %3 / 서 %4\n다음 확장: %5")
	text = string.gsub(text, "^([%d]+)d%s*([%d]+)h$", "%1일 %2시간")
	text = string.gsub(text, "^([%d]+)h%s*([%d]+)m$", "%1시간 %2분")
	text = string.gsub(text, "^([%d]+)m$", "%1분")
	text = string.gsub(text, "^Use relocation points %((%d+) left%)$", "재배치 포인트 사용 (%1 남음)")
	text = string.gsub(text, "^Upkeep (%d+) Day%(s%) ~ (%d+) Gold$", "%1일 유지 ~ %2 Gold")
	
	-- Rune Stone Claims
	text = string.gsub(text, "^Acquired Active Rune %[(.+)%]%! %((%d+)%/(%d+)%)$", "액티브 룬 [%1]을 획득했습니다! (%2/%3)")
	text = string.gsub(text, "^Acquired Active Rune %[(.+)%]%! %(Accumulated (%d+) claims%)$", "액티브 룬 [%1]을 획득했습니다! (누적 %2회 획득)")
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

	if fieldName == "name" or fieldName == "npcName" then
		-- 사전 정의 번역이 있으면 적용, 없으면 기본 영어 가공(titleFromId)
		local localized = KO_TO_EN[src]
		if localized then
			return localized
		end
		return titleFromId(fieldName == "npcName" and (dataId .. "_NPC") or dataId)
	end

	if fieldName == "description" then
		local localized = KO_TO_EN[src]
		if localized then
			return localized
		end
		-- Fallbacks
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

function UILocalizer.GetBothNames(tableName: string, dataId: string, sourceText: string?): (string, string)
	if not sourceText or sourceText == "" then
		return "", ""
	end
	
	local nameKo = sourceText
	local nameEn = KO_TO_EN[sourceText]
	if not nameEn then
		if tableName == "ItemData" then
			nameEn = titleFromId(dataId)
		else
			nameEn = sourceText
		end
	end
	
	return nameKo, nameEn
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

