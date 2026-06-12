-- LevelTriggerService.lua
-- 레벨 특정 파트 도달(터치) 감지 및 보상 지급 시스템

local LevelTriggerService = {}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local initialized = false
local touchDebounces = {} -- userId -> lastTouchTime

-- 보상 지급 함수
local function grantSteadfastReward(player)
	local userId = player.UserId
	
	-- 중복 지급 방지 체크 (소장 스킬북 및 스킬 해금 상태 스캔)
	local SaveService = require(game:GetService("ServerScriptService").Server.Services.SaveService)
	local InventoryService = require(game:GetService("ServerScriptService").Server.Services.InventoryService)
	local state = SaveService and SaveService.getPlayerState(userId)
	if not state then return end

	local hasSteadfastBookOrSkill = false
	if state.skillBooks then
		for _, bid in ipairs(state.skillBooks) do
			if bid == "BOOK_STEADFAST" then
				hasSteadfastBookOrSkill = true
				break
			end
		end
	end
	
	if not hasSteadfastBookOrSkill and state.unlockedSkills and state.unlockedSkills["SKILL_RUNE_STEADFAST"] then
		hasSteadfastBookOrSkill = true
	end
	
	-- 이미 보유하거나 배운 경우 조용히 처리 (스킵)
	if hasSteadfastBookOrSkill then
		return
	end
	
	-- 부동심 스킬북 지급
	local added, remaining = InventoryService.addItem(userId, "BOOK_STEADFAST", 1)
	local NetController = require(game:GetService("ServerScriptService").Server.Controllers.NetController)
	
	if added > 0 then
		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text = "가장 높은 곳에 침착하게 도달하여 [부동심 스킬북]을 획득했습니다!",
				color = "GOLD"
			})
		end
		print(string.format("[LevelTriggerService] Granted BOOK_STEADFAST to player %s (%d)", player.Name, userId))
	else
		if NetController then
			NetController.FireClient(player, "Notify.Message", {
				text = "인벤토리가 가득 차서 [부동심 스킬북]을 획득하지 못했습니다. 인벤토리를 비우고 다시 시도해 주세요.",
				color = "RED"
			})
		end
	end
end

-- 터치 리스너 셋업
local function setupTouchTrigger()
	task.spawn(function()
		-- 지연 기동을 부여하여 오브젝트들이 로딩될 시간을 보장합니다.
		task.wait(1.5)
		
		local targetPart = nil
		
		-- 1순위: 가장 유력한 경로인 Workspace/LevelArt/Set_Dressing/Rocks/first 직접 탐색
		local levelArt = Workspace:FindFirstChild("LevelArt")
		local setDressing = levelArt and levelArt:FindFirstChild("Set_Dressing")
		local rocks = setDressing and setDressing:FindFirstChild("Rocks")
		targetPart = rocks and rocks:FindFirstChild("first")
		
		-- 2순위: 찾지 못했을 경우 전체 워크스페이스 하위에서 MeshPart이고 이름이 "first"인 개체 검색 (동적 복구)
		if not targetPart then
			local function scanRecursive(parent)
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("MeshPart") and child.Name == "first" then
						return child
					end
					local found = scanRecursive(child)
					if found then return found end
				end
				return nil
			end
			targetPart = scanRecursive(Workspace)
		end
		
		if not targetPart then
			warn("[LevelTriggerService] 'first' MeshPart could not be found anywhere in Workspace! Touch trigger initialization failed.")
			return
		end
		
		-- [중요] Touched 이벤트가 정상 작동하도록 강제로 CanTouch 플래그를 참으로 설정합니다.
		targetPart.CanTouch = true
		
		print(string.format("[LevelTriggerService] Successfully locked Touch trigger to MeshPart: %s", targetPart:GetFullName()))
		
		-- 터치 감지
		targetPart.Touched:Connect(function(hit)
			local char = hit.Parent
			if not char then return end
			
			-- Humanoid 존재 여부 추가 검증 (플레이어/캐릭터 판정 강화)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end
			
			local player = Players:GetPlayerFromCharacter(char)
			if not player then return end
			
			local userId = player.UserId
			local now = os.clock()
			
			-- 디바운스 적용 (3초 쿨다운)
			if touchDebounces[userId] and now - touchDebounces[userId] < 3.0 then
				return
			end
			touchDebounces[userId] = now
			
			print(string.format("[LevelTriggerService] Player %s touched the top rock 'first'!", player.Name))
			
			-- 보상 지급 시도
			grantSteadfastReward(player)
		end)
	end)
end

function LevelTriggerService.Init()
	if initialized then return end
	initialized = true
	
	setupTouchTrigger()
	
	-- 플레이어 접속 해제 시 디바운스 정리
	Players.PlayerRemoving:Connect(function(player)
		touchDebounces[player.UserId] = nil
	end)
	
	print("[LevelTriggerService] System successfully initialized.")
end

return LevelTriggerService
