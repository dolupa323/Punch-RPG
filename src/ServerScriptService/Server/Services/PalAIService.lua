-- PalAIService.lua
-- 베이스 배치된 팰의 AI 및 시각적 표현 관리 (Phase 7-5)
-- 팰의 이동, 애니메이션, 작업 상태를 제어하며 시각적 피드백 제공

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local PalAIService = {}

-- Dependencies
local initialized = false
local NetController = nil
local CreatureService = nil
local DataService = nil
local PalboxService = nil
local BuildService = nil

--========================================
-- Internal State
--========================================
-- 베이스 팰 엔티티 데이터 { [palUID] = { model = Model, instanceId = GUID, ownerId = number, task = nil } }
local basePals = {}

--========================================
-- Internal Helpers
--========================================

--- 팰 모델 스폰 (CreatureService 활용)
local function spawnPalModel(userId: number, palUID: string, spawnPosition: Vector3)
	if not CreatureService or not PalboxService then return nil end
	
	local palData = PalboxService.getPal(userId, palUID)
	if not palData then return nil end
	
	-- CreatureService.spawn은 야생 크리처 용이므로, 팰 전용 스폰 로직 필요
	-- 임시로 spawn을 사용하되, AI 로직은 우리가 덮어씌움
	local instanceId = CreatureService.spawn(palData.creatureId, spawnPosition)
	if not instanceId then return nil end
	
	local creature = CreatureService.getCreatureRuntime(instanceId)
	if not creature then return nil end
	
	-- 팰 속성 설정 (야생 AI 업데이트 루프에서 예외 처리되도록 함)
	creature.model:SetAttribute("IsBasePal", true)
	creature.model:SetAttribute("PalUID", palUID)
	creature.model:SetAttribute("OwnerId", userId)
	
	-- 기본 스탯 반영
	creature.humanoid.WalkSpeed = palData.stats and palData.stats.speed or 16
	
	return instanceId, creature
end

--========================================
-- Public API
--========================================

function PalAIService.Init(_NetController, _CreatureService, _DataService, _PalboxService, _BuildService)
	if initialized then return end
	
	NetController = _NetController
	CreatureService = _CreatureService
	DataService = _DataService
	PalboxService = _PalboxService
	BuildService = _BuildService
	
	initialized = true
	
	-- Heartbeat 연결 (작업 프로세싱)
	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function(dt)
		PalAIService.tick(dt)
	end)
	
	print("[PalAIService] Initialized with Heartbeat")
end

--- 시설에 배치된 팰의 엔티티를 베이스에 소환
function PalAIService.onPalAssigned(userId: number, palUID: string, structureId: string)
	if basePals[palUID] then return end
	
	local struct = BuildService and BuildService.get(structureId)
	if not struct then return end
	
	-- 시설 주변에 스폰
	local spawnPos = struct.position + Vector3.new(5, 2, 5)
	
	local instanceId, creature = spawnPalModel(userId, palUID, spawnPos)
	if instanceId then
		basePals[palUID] = {
			instanceId = instanceId,
			palUID = palUID,
			ownerId = userId,
			model = creature.model,
			humanoid = creature.humanoid,
			rootPart = creature.rootPart,
			currentTask = nil,
		}
		print(string.format("[PalAIService] Spawned working Pal %s at facility %s", palUID, structureId))
	end
end

--- 시설에서 팰이 해제될 때 엔티티 제거
function PalAIService.onPalUnassigned(palUID: string)
	local pal = basePals[palUID]
	if not pal then return end
	
	if CreatureService then
		CreatureService.removeCreature(pal.instanceId)
	end
	
	basePals[palUID] = nil
	print(string.format("[PalAIService] Removed working Pal model %s", palUID))
end

--- 팰에게 작업 명령 부여
function PalAIService.assignTask(palUID: string, taskType: string, targetPos: Vector3, duration: number, onComplete: () -> ())
	local pal = basePals[palUID]
	if not pal then 
		-- 모델이 없으면 즉시 완료 처리 (폴백)
		if onComplete then onComplete() end
		return 
	end
	
	-- 이미 같은 작업을 하고 있으면 무시
	if pal.currentTask and pal.currentTask.type == taskType and pal.currentTask.targetPos == targetPos then
		return
	end
	
	local creature = CreatureService.getCreatureRuntime(pal.instanceId)
	if not creature then return end
	
	-- AI 상태 변경 (TASK 상테는 CreatureService에서 처리하도록 추가 필요)
	creature.state = "TASK"
	creature.targetPosition = targetPos
	creature.model:SetAttribute("State", "TASK")
	creature.model:SetAttribute("TaskType", taskType)
	
	pal.currentTask = {
		type = taskType,
		targetPos = targetPos,
		startTime = tick(),
		duration = duration,
		onComplete = onComplete
	}
	
	print(string.format("[PalAIService] assigned task %s to Pal %s", taskType, palUID))
end

--- 팰 상태 체크 (도착 여부 등)
function PalAIService.isPalAt(palUID: string, position: Vector3, tolerance: number): boolean
	local pal = basePals[palUID]
	if not pal or not pal.rootPart then return true end -- 모델 없으면 그냥 통과 (시뮬레이션 유지)
	
	local dist = (pal.rootPart.Position - position).Magnitude
	return dist <= (tolerance or 5)
end

--- 팰 업데이트 (Heartbeat 등에서 호출 가능)
function PalAIService.tick(dt: number)
	local now = tick()
	for palUID, pal in pairs(basePals) do
		if pal.currentTask then
			-- 목적지 도착 확인
			if PalAIService.isPalAt(palUID, pal.currentTask.targetPos) then
				-- 작업 수행 시간 대기
				if not pal.currentTask.arrivalTime then
					pal.currentTask.arrivalTime = now
					-- 작업 애니메이션 트리거 (클라이언트)
					if NetController then
						NetController.FireAllClients("Pal.Action.Play", { 
							palUID = palUID, 
							action = pal.currentTask.type 
						})
					end
				elseif (now - pal.currentTask.arrivalTime) >= pal.currentTask.duration then
					-- 작업 완료
					local callback = pal.currentTask.onComplete
					pal.currentTask = nil
					
					-- 보상/결과 처리
					if callback then callback() end
				end
			end
		end
	end
end

return PalAIService
