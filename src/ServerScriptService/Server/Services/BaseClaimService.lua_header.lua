-- BaseClaimService.lua
-- 베이스 영역 관리 시스템 (Phase 7-2)
-- 플레이어 베이스 영역 설정 및 자동화 범위 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local BaseClaimService = {}

local PORTAL_NAME = "Portal_Tropical"
local PORTAL_RESTRICTION_MARGIN = Balance.PORTAL_RESTRICTION_MARGIN or 18

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
