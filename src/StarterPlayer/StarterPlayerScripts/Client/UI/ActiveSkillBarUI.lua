-- ActiveSkillBarUI.lua
-- 액티브 스킬 바 HUD (핫바 위 3슬롯)
-- 키: Q / Z / X (또는 모바일 터치)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)

local Client = script.Parent.Parent
local UI = script.Parent
local Theme = require(UI.UITheme)
local Utils = require(UI.UIUtils)

local Controllers = Client:WaitForChild("Controllers")
local SkillController = require(Controllers.SkillController)

local C = Theme.Colors
local F = Theme.Fonts

local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local ActiveSkillBarUI = {}

--========================================
-- Constants
--========================================
local SLOT_SIZE = isMobile and 52 or 44
local SLOT_GAP = 6
local BAR_BOTTOM_OFFSET = isMobile and -115 or -90 -- 핫바 위쪽에 배치
local KEY_LABELS = { "Q", "F", "V" }
local COOLDOWN_COLOR = Color3.fromRGB(0, 0, 0)
local READY_FLASH_COLOR = Color3.fromRGB(255, 225, 90)

--========================================
-- Refs
--========================================
local barFrame
local slotRefs = {} -- { [1..3] = { frame, icon, cooldownOverlay, cooldownText, keyLabel, glowStroke } }
local updateConnection

--========================================
-- Icon Helper (SkillTreeUI 동일 패턴)
--========================================
local SkillIcons = nil
do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		SkillIcons = assets:FindFirstChild("SkillIcons")
	end
end

local function _getIconImage(iconName)
	if not SkillIcons or not iconName then return nil end
	local asset = SkillIcons:FindFirstChild(iconName)
	if not asset then return nil end
	if asset:IsA("Decal") or asset:IsA("Texture") then return asset.Texture end
	if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then return asset.Image end
	if asset:IsA("StringValue") then return asset.Value end
	return nil
end

--========================================
-- Create UI
--========================================
local function createBar(parent)
	local totalWidth = SLOT_SIZE * 3 + SLOT_GAP * 2
	
	barFrame = Utils.mkFrame({
		name = "ActiveSkillBar",
		size = UDim2.new(0, totalWidth, 0, SLOT_SIZE + 16),
		pos = UDim2.new(0.5, 0, 1, BAR_BOTTOM_OFFSET),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = parent,
	})
	
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, SLOT_GAP)
	list.Parent = barFrame
	
	for i = 1, 3 do
		local slotFrame = Utils.mkFrame({
			name = "SkillSlot" .. i,
			size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
			bg = C.BG_SLOT,
			bgT = 0.35,
			r = 6,
			stroke = 1.5,
			strokeC = C.BORDER_DIM,
			parent = barFrame,
		})
		
		-- 아이콘
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.75, 0, 0.75, 0)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ImageTransparency = 0
		icon.ZIndex = 2
		icon.Parent = slotFrame
		
		-- 쿨다운 오버레이 (검은 반투명 스윕)
		local cdOverlay = Utils.mkFrame({
			name = "CooldownOverlay",
			size = UDim2.new(1, 0, 0, 0), -- 높이가 쿨다운 비율에 따라 변함
			pos = UDim2.new(0, 0, 1, 0),
			anchor = Vector2.new(0, 1),
			bg = COOLDOWN_COLOR,
			bgT = 0.45,
			r = false,
			parent = slotFrame,
		})
		cdOverlay.ZIndex = 3
		cdOverlay.ClipsDescendants = true
		
		-- 쿨다운 남은 시간 텍스트
		local cdText = Utils.mkLabel({
			name = "CDText",
			size = UDim2.new(1, 0, 1, 0),
			text = "",
			ts = isMobile and 16 or 13,
			font = F.TITLE,
			color = C.WHITE,
			parent = slotFrame,
		})
		cdText.ZIndex = 4
		
		-- 키 라벨 (좌측 상단)
		local keyLabel = Utils.mkLabel({
			name = "KeyLabel",
			size = UDim2.new(0, 14, 0, 14),
			pos = UDim2.new(0, 2, 0, 1),
			text = KEY_LABELS[i],
			ts = isMobile and 11 or 9,
			font = F.TITLE,
			color = C.GRAY,
			ax = Enum.TextXAlignment.Left,
			ay = Enum.TextYAlignment.Top,
			parent = slotFrame,
		})
		keyLabel.ZIndex = 5
		if isMobile then keyLabel.Visible = false end
		
		-- 터치 버튼 (모바일)
		if isMobile then
			local touchBtn = Instance.new("TextButton")
			touchBtn.Name = "TouchBtn"
			touchBtn.Size = UDim2.new(1, 0, 1, 0)
			touchBtn.BackgroundTransparency = 1
			touchBtn.Text = ""
			touchBtn.ZIndex = 10
			touchBtn.Parent = slotFrame
			touchBtn.MouseButton1Click:Connect(function()
				SkillController.useSkillBySlot(i, _getCurrentTarget())
			end)
		end
		
		-- 글로우 스트로크 (스킬 준비 시 반짝)
		local glowStroke = slotFrame:FindFirstChildOfClass("UIStroke")
		
		slotRefs[i] = {
			frame = slotFrame,
			icon = icon,
			cooldownOverlay = cdOverlay,
			cooldownText = cdText,
			keyLabel = keyLabel,
			glowStroke = glowStroke,
			wasOnCooldown = false,
		}
	end
end

--========================================
-- Target Helper (전투 중인 크리처 조회)
--========================================
local function _getCurrentTarget(): string?
	-- CombatController의 현재 타겟을 참조 (없으면 nil)
	local ok, CombatController = pcall(function()
		return require(Controllers.CombatController)
	end)
	if ok and CombatController and CombatController.getCurrentTarget then
		return CombatController.getCurrentTarget()
	end
	return nil
end

--========================================
-- Update Loop
--========================================
local function refreshSlots()
	local slots = SkillController.getActiveSkillSlots()
	
	for i = 1, 3 do
		local ref = slotRefs[i]
		if not ref then continue end
		
		local skillId = slots[i]
		
		if skillId then
			-- 스킬 데이터 조회
			local skill = SkillTreeData.GetSkill(skillId)
			if skill then
				-- 아이콘 설정
				local img = _getIconImage(skill.icon)
				if img then
					ref.icon.Image = img
					ref.icon.ImageTransparency = 0
				else
					ref.icon.Image = ""
					ref.icon.ImageTransparency = 0.5
				end
				
				-- 쿨다운 업데이트
				local remaining = SkillController.getSlotCooldownRemaining(i)
				if remaining > 0 then
					local ratio = math.clamp(remaining / skill.cooldown, 0, 1)
					ref.cooldownOverlay.Size = UDim2.new(1, 0, ratio, 0)
					ref.cooldownText.Text = tostring(math.ceil(remaining))
					ref.icon.ImageTransparency = 0.5
					ref.wasOnCooldown = true
					
					-- 보더 어둡게
					if ref.glowStroke then
						ref.glowStroke.Color = C.BORDER_DIM
					end
				else
					ref.cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
					ref.cooldownText.Text = ""
					ref.icon.ImageTransparency = 0
					
					-- 쿨다운 끝났을 때 반짝 효과
					if ref.wasOnCooldown then
						ref.wasOnCooldown = false
						if ref.glowStroke then
							ref.glowStroke.Color = READY_FLASH_COLOR
							TweenService:Create(ref.glowStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Color = C.BORDER,
							}):Play()
						end
					else
						if ref.glowStroke then
							ref.glowStroke.Color = C.BORDER
						end
					end
				end
				
				ref.frame.Visible = true
			else
				ref.frame.Visible = false
			end
		else
			-- 빈 슬롯
			ref.icon.Image = ""
			ref.icon.ImageTransparency = 0.8
			ref.cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
			ref.cooldownText.Text = ""
			ref.frame.Visible = true
			ref.frame.BackgroundTransparency = 0.7
			if ref.glowStroke then
				ref.glowStroke.Color = C.BORDER_DIM
			end
		end
	end
end

--========================================
-- Public API
--========================================

function ActiveSkillBarUI.Init(parent)
	createBar(parent)
	
	-- 슬롯 데이터 변경 시 리프레시
	SkillController.onSkillDataUpdated(function()
		refreshSlots()
	end)
	
	-- 쿨다운 변경 시 리프레시
	SkillController.onCooldownUpdated(function()
		refreshSlots()
	end)
	
	-- 주기적 쿨다운 UI 업데이트 (0.1초 간격)
	updateConnection = RunService.Heartbeat:Connect(function()
		-- 쿨다운 중인 슬롯만 업데이트
		local slots = SkillController.getActiveSkillSlots()
		for i = 1, 3 do
			local ref = slotRefs[i]
			local skillId = slots[i]
			if ref and skillId then
				local remaining = SkillController.getSlotCooldownRemaining(i)
				if remaining > 0 then
					local skill = SkillTreeData.GetSkill(skillId)
					if skill then
						local ratio = math.clamp(remaining / skill.cooldown, 0, 1)
						ref.cooldownOverlay.Size = UDim2.new(1, 0, ratio, 0)
						ref.cooldownText.Text = tostring(math.ceil(remaining))
						ref.icon.ImageTransparency = 0.5
					end
				elseif ref.wasOnCooldown then
					-- 쿨다운 방금 끝남
					ref.cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
					ref.cooldownText.Text = ""
					ref.icon.ImageTransparency = 0
					ref.wasOnCooldown = false
					if ref.glowStroke then
						ref.glowStroke.Color = READY_FLASH_COLOR
						TweenService:Create(ref.glowStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Color = C.BORDER,
						}):Play()
					end
				end
			end
		end
	end)
	
	-- 초기 리프레시
	task.defer(refreshSlots)
end

--- 스킬 바 표시/숨기기
function ActiveSkillBarUI.SetVisible(visible: boolean)
	if barFrame then
		barFrame.Visible = visible
	end
end

--- 키 입력으로 스킬 사용 (ClientInit에서 호출)
function ActiveSkillBarUI.UseSlot(slotIndex: number)
	SkillController.useSkillBySlot(slotIndex, _getCurrentTarget())
end

return ActiveSkillBarUI
