-- HazardService.lua
-- 아바타 검술 RPG: 월드 위험지대(Lava 등) 감지 및 데미지 연동 서버 서비스
-- Server-Authoritative & Integrated with Defense / Debuff system

local HazardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local NetController = nil
local DebuffService = nil

local initialized = false
local lavaParts = {}

local RAW_LAVA_DAMAGE = 15 -- 1초당 입히는 기본 데미지량
local CHECK_INTERVAL = 1.0

-- 디테일한 경로 체크: Cave 모델 하위의 Lava 파트인지 검증 (상위 조상 중 Cave 모델이 있는지 확인)
local function isLavaInCave(desc)
	if desc.Name == "Lava" and desc:IsA("BasePart") then
		local ancestor = desc.Parent
		local pathTrace = desc.Name
		while ancestor and ancestor ~= Workspace do
			pathTrace = ancestor.Name .. " -> " .. pathTrace
			if ancestor.Name == "Cave" and ancestor:IsA("Model") then
				print(string.format("[HazardService] Cave Lava 검증 성공: %s (경로: %s)", desc:GetFullName(), pathTrace))
				return true
			end
			ancestor = ancestor.Parent
		end
		print(string.format("[HazardService] Cave Lava 검증 실패 (조상 중 Cave 모델 없음): %s (경로: %s)", desc:GetFullName(), pathTrace))
	end
	return false
end

local function addLavaPart(part)
	if not table.find(lavaParts, part) then
		table.insert(lavaParts, part)
		print(string.format("[HazardService] Lava 파트 등록 완료: %s", part:GetFullName()))
	end
end

function HazardService.Init(netController)
	if initialized then return end
	initialized = true

	NetController = netController
	
	-- 지연 로딩을 통한 의존성 해결 및 순환 참조 방지
	local ServerService = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
	DebuffService = require(ServerService:WaitForChild("DebuffService"))

	print("[HazardService] 1차 기존 Lava 파트 스캔 시작...")
	-- 1. 기존에 이미 배치된 Lava 파트 스캔
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "Lava" then
			print(string.format("[HazardService] 발견된 Lava 파트: %s, 클래스: %s", desc:GetFullName(), desc.ClassName))
			if isLavaInCave(desc) then
				addLavaPart(desc)
			end
		end
	end
	print(string.format("[HazardService] 1차 스캔 완료. 등록된 Lava 파트 개수: %d", #lavaParts))

	-- 2. 동적으로 로드되거나 생성되는 Lava 파트 감지 리스너
	Workspace.DescendantAdded:Connect(function(desc)
		task.defer(function()
			if desc.Name == "Lava" then
				print(string.format("[HazardService] 동적 발견된 Lava 파트: %s", desc:GetFullName()))
				if isLavaInCave(desc) then
					addLavaPart(desc)
				end
			end
		end)
	end)

	-- 3. 주기적 플레이어 충돌 감지 및 데미지/디버프 연동 루프
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)

			-- 파괴/제거된 Lava 파트 클린업
			for i = #lavaParts, 1, -1 do
				local p = lavaParts[i]
				if not p or not p.Parent then
					print(string.format("[HazardService] 제거된 Lava 파트 클린업: index %d", i))
					table.remove(lavaParts, i)
				end
			end

			if #lavaParts == 0 then
				-- 등록된 용암 파트가 없을 때 감지 건너뜀
				continue
			end

			-- 접속중인 플레이어 전체 검사
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")

				if hrp and hum and hum.Health > 0 then
					local overlapParams = OverlapParams.new()
					overlapParams.FilterType = Enum.RaycastFilterType.Include
					overlapParams.FilterDescendantsInstances = lavaParts

					local centerCFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
					local boxSize = Vector3.new(3, 5, 3)

					local touchingParts = Workspace:GetPartBoundsInBox(centerCFrame, boxSize, overlapParams)
					if #touchingParts > 0 then
						-- Lava에 닿음! 데미지 공식 연동 (방어력 적용)
						local defense = tonumber(char:GetAttribute("Defense")) or 0
						local finalDamage = RAW_LAVA_DAMAGE * (100 / (100 + defense))
						finalDamage = math.max(1, math.floor(finalDamage + 0.5))

						-- 데미지 적용
						hum:TakeDamage(finalDamage)

						-- 화상 디버프(BURNING) 적용
						if DebuffService and DebuffService.applyDebuff then
							DebuffService.applyDebuff(player.UserId, "BURNING")
							print(string.format("[HazardService] %s 플레이어에게 BURNING 디버프 적용 요청 완료", player.Name))
						else
							warn("[HazardService] DebuffService 또는 applyDebuff 함수가 존재하지 않습니다.")
						end

						-- [데미지 로직 연동] 플레이어 피격 연출 및 floating damage text 연동 전송
						if NetController then
							NetController.FireClient(player, "Combat.Player.Hit", {
								damage = finalDamage,
								sourcePos = touchingParts[1] and touchingParts[1].Position or hrp.Position
							})
							print(string.format("[HazardService] %s 플레이어에게 Combat.Player.Hit 이벤트 발송 완료 (Damage: %d)", player.Name, finalDamage))
						else
							warn("[HazardService] NetController가 정의되어 있지 않아 이벤트를 발송하지 못했습니다.")
						end

						print(string.format("[HazardService] Lava Damage: Player %s (Defense: %d) took %d dmg (Lava)", player.Name, defense, finalDamage))
					end
				end
			end
		end
	end)

	print("[HazardService] Initialized successfully")
end

return HazardService
