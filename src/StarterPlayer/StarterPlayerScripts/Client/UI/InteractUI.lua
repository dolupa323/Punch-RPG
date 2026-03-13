-- InteractUI.lua
-- 상호작용 및 건축 가이드 프롬프트 (Original Minimal Style)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local InteractUI = {}

InteractUI.Refs = {
	PromptFrame = nil,
	PromptLabel = nil,
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

function InteractUI.Init(parent, isMobile)
	local isSmall = isMobile
	
	-- Interaction Prompt (Center Bottom)
	local prompt = Utils.mkFrame({
		name = "InteractPrompt",
		size = UDim2.new(0, 240, 0, 60),
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
		text = "[Z] 상호작용",
		ts = 18,
		font = F.TITLE,
		color = C.WHITE,
		rich = true,
		parent = prompt
	})
	InteractUI.Refs.PromptLabel = pLabel

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

	Utils.mkLabel({text = "🛠️ 건축 컨트롤", ts = 16, font=F.TITLE, color = C.GOLD_SEL, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = "LMB : 배치 확정", ts = 14, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = "R : 시설 회전", ts = 14, color = C.WHITE, ax = Enum.TextXAlignment.Left, parent = build})
	Utils.mkLabel({text = "X : 건축 취소", ts = 14, color = Color3.fromRGB(255, 100, 100), ax = Enum.TextXAlignment.Left, parent = build})
end

return InteractUI
