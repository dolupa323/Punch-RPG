-- PortalService.lua
-- 유니버스 내 다른 플레이스(Island_Tropical 등)로 이동하는 테스트 포털 서비스

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local PortalService = {}
local initialized = false

-- 테이블을 통해 포탈 이름과 해당 PlaceId 매핑 (사용자가 직접 입력 필요)
-- Island_Tropical의 PlaceId를 에셋 매니저에서 복사해서 숫자로 넣으세요.
local PORTAL_MAP = {
	["Portal_Tropical"] = 107341024431610,
	["Portal_Grassland"] = 0,
}

local debounces = {}

function PortalService.Init()
	if initialized then return end
	
	-- 서버 시작 시가 아니라, 주기적으로나 혹은 생성 시 바인딩할 수도 있지만,
	-- 테스트용이므로 Workspace의 포탈 오브젝트들을 바로 찾거나 대기합니다.
	for portalName, placeId in pairs(PORTAL_MAP) do
		-- 비동기로 스폰될 수도 있으므로 WaitForChild 대신 스레드 분리
		task.spawn(function()
			local portalObject = workspace:WaitForChild(portalName, 10) -- 10초 대기
			if portalObject then
				local function setupTouch(part)
					if part:IsA("BasePart") then
						part.Touched:Connect(function(hit)
							local character = hit.Parent
							local player = Players:GetPlayerFromCharacter(character)
							
							if player then
								if placeId == 0 then
									print("[PortalService] PlaceId가 설정되지 않았습니다. PortalService.lua를 수정하세요.")
									return
								end
								
								if debounces[player.UserId] and tick() - debounces[player.UserId] < 5 then
									return -- 5초 쿨타임
								end
								debounces[player.UserId] = tick()
								
								print(string.format("[PortalService] Teleporting player %s to PlaceId %d", player.Name, placeId))
								
								local success, err = pcall(function()
									TeleportService:TeleportAsync(placeId, {player})
								end)
								if not success then
									warn("[PortalService] Teleport failed:", err)
								end
							end
						end)
					end
				end
				
				-- 대상이 파트면 자신에게 연결, 모델이면 내부 모든 파트들에 연결
				setupTouch(portalObject)
				for _, descendant in ipairs(portalObject:GetDescendants()) do
					setupTouch(descendant)
				end
				
				print("[PortalService] Initialized portal:", portalName)
			end
		end)
	end
	
	initialized = true
	print("[PortalService] Initialized")
end

return PortalService
