-- InteractUI.lua
-- 상호작용 및 건축 가이드 프롬프트 (Original Minimal Style)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local InteractUI = {}

InteractUI.Refs = {
	PromptFrame = nil,
	PromptLabel = nil,
	PromptDurabilityFrame = nil,
	PromptDurabilityFill = nil,
	PromptDurabilityLabel = nil,
	BuildPrompt = nil,
}

function InteractUI.SetVisible(visible)
	if InteractUI.Refs.PromptFrame then
		InteractUI.Refs.PromptFrame.Visible = visible
	end
end

function InteractUI.SetBuildVisible(visible)
	if InteractUI.Refs.BuildPrompt then
		InteractUI.Refs.BuildPrompt.Visible = visible
	end
end

function InteractUI.UpdatePrompt(text)
	if InteractUI.Refs.PromptLabel then
		InteractUI.Refs.PromptLabel.Text = text
		InteractUI.Refs.PromptLabel.RichText = true
	end
end

function InteractUI.SetDurabilityVisible(visible)
	if InteractUI.Refs.PromptDurabilityFrame then
		InteractUI.Refs.PromptDurabilityFrame.Visible = visible
	end
end

function InteractUI.UpdateDurability(current, max)
	local frame = InteractUI.Refs.PromptDurabilityFrame
	local fill = InteractUI.Refs.PromptDurabilityFill
	local label = InteractUI.Refs.PromptDurabilityLabel
	if not frame or not fill or not label then return end

	local maxValue = math.max(max or 1, 1)
	local ratio = math.clamp((current or 0) / maxValue, 0, 1)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	label.Text = UILocalizer.Localize(string.format("내구도 %d%%", math.floor(ratio * 100)))

	if ratio < 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(210, 80, 80)
	elseif ratio < 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(220, 150, 70)
	else
		fill.BackgroundColor3 = Color3.fromRGB(90, 190, 110)
	end
end

function InteractUI.Init(parent, isMobile)
	local isSmall = isMobile
	
	-- Interaction Prompt (Center Bottom)
	local prompt = Utils.mkFrame({
		name = "InteractPrompt",
		size = UDim2.new(0, 260, 0, 84),
		pos = UDim2.new(0.5, 0, 0.75, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 30,
		stroke = false,
		vis = false,
		parent = parent
	})
	InteractUI.Refs.PromptFrame = prompt
	
	local pLabel = Utils.mkLabel({
		text = UILocalizer.Localize("[Z] 상호작용"),
		size = UDim2.new(1, -20, 0, 42),
		pos = UDim2.new(0.5, 0, 0, 8),
		anchor = Vector2.new(0.5, 0),
		ts = 17,
		font = F.TITLE,
		color = C.WHITE,
		rich = true,
		parent = prompt
	})
	InteractUI.Refs.PromptLabel = pLabel

	local hpWrap = Utils.mkFrame({
		name = "PromptDurability",
		size = UDim2.new(1, -20, 0, 16),
		pos = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
		bg = Color3.fromRGB(45, 45, 50),
		r = 5,
		vis = false,
		parent = prompt
	})

	local hpFill = Utils.mkFrame({
		name = "Fill",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(90, 190, 110),
		r = 5,
		parent = hpWrap
	})

	local hpLabel = Utils.mkLabel({
		text = UILocalizer.Localize("내구도 100%"),
		size = UDim2.new(1, 0, 1, 0),
		ts = 11,
		font = F.BODY,
		color = C.WHITE,
		parent = hpWrap
	})

	InteractUI.Refs.PromptDurabilityFrame = hpWrap
	InteractUI.Refs.PromptDurabilityFill = hpFill
	InteractUI.Refs.PromptDurabilityLabel = hpLabel

	-- Build Controls Guide (Bottom Left)
	-- Higher ZIndex to stay above HUD but subtle
	local build = Utils.mkFrame({
		name = "BuildPrompt",
		size = UDim2.new(0, 200, 0, 110),
		pos = UDim2.new(0.02, 0, isSmall and 0.8 or 0.85, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 8,
		stroke = false,
		vis = false,
		parent = parent
	})
	InteractUI.Refs.BuildPrompt = build
	
	local listLayer = Instance.new("UIListLayout")
	listLayer.Padding = UDim.new(0, 4); listLayer.HorizontalAlignment = Enum.HorizontalAlignment.Left; listLayer.Parent = build
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 15); p.PaddingTop = UDim.new(0, 12); p.Parent = build

	Utils.mkLabel({text = UILocalizer.Localize("🛠️ 건축 컨트롤"), ts = 16, font=F.TITLE, color = C.GOLD_SEL, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = UILocalizer.Localize("LMB : 배치 확정"), ts = 14, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = UILocalizer.Localize("R : 시설 회전"), ts = 14, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = UILocalizer.Localize("X : 건축 취소"), ts = 14, color = Color3.fromRGB(255, 100, 100), ax = Enum.TextXAlignment.Left, parent = build})
end

return InteractUI
