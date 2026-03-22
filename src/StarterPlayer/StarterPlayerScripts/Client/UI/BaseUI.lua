-- BaseUI.lua
-- 베이스 관리 UI (거점 이름 변경, 확장, 정보 확인)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local BaseUI = {}
BaseUI.Refs = {}

local currentUIManager = nil
local currentBaseInfo = nil

function BaseUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager
	
	-- 메인 프레임 (Window 스타일)
	local window = Utils.mkWindow({
		name = "BaseMenu",
		size = UDim2.new(0, 400, 0, 350),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.4,
		stroke = 1,
		strokeC = C.BORDER,
		vis = false,
		parent = parent,
	})
	BaseUI.Refs.Frame = window
	
	-- 헤더
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, 0, 0, 50),
		bg = C.BG_HEADER,
		parent = window
	})
	
	Utils.mkLabel({
		text = "⛺ 거점 관리",
		size = UDim2.new(1, -50, 1, 0),
		pos = UDim2.new(0, 15, 0, 0),
		ts = 20,
		font = F.TITLE,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = header
	})
	
	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 40, 0, 40),
		pos = UDim2.new(1, -5, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bgT = 1,
		ts = 20,
		font = F.TITLE,
		color = C.WHITE,
		fn = function() UIManager.closeBaseMenu() end,
		parent = header
	})
	
	local content = Utils.mkFrame({
		name = "Content",
		size = UDim2.new(1, -30, 1, -65),
		pos = UDim2.new(0, 15, 0, 55),
		bgT = 1,
		parent = window
	})
	
	-- 거점 이름 영역
	Utils.mkLabel({
		text = "거점 명칭",
		size = UDim2.new(1, 0, 0, 20),
		ts = 14,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = content
	})
	
	local nameInputBg = Instance.new("Frame")
	nameInputBg.Size = UDim2.new(1, 0, 0, 40)
	nameInputBg.Position = UDim2.new(0, 0, 0, 25)
	nameInputBg.BackgroundColor3 = C.BG_SLOT
	nameInputBg.BorderSizePixel = 0
	nameInputBg.Parent = content
	local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 6); cor.Parent = nameInputBg
	
	local nameInput = Instance.new("TextBox")
	nameInput.Size = UDim2.new(1, -20, 1, 0)
	nameInput.Position = UDim2.new(0, 10, 0, 0)
	nameInput.BackgroundTransparency = 1
	nameInput.Text = "새로운 거점"
	nameInput.PlaceholderText = "거점 이름을 입력하세요"
	nameInput.TextColor3 = C.WHITE
	nameInput.TextSize = 18
	nameInput.Font = F.BODY
	nameInput.TextXAlignment = Enum.TextXAlignment.Left
	nameInput.Parent = nameInputBg
	BaseUI.Refs.NameInput = nameInput
	
	nameInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local BaseController = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.BaseController)
			local success, err = BaseController.requestRename(nameInput.Text)
			if success then
				UIManager.notify("거점 이름이 변경되었습니다.")
			else
				UIManager.notify("이름 변경 실패: " .. tostring(err))
			end
		end
	end)
	
	-- 정보 영역
	local infoBox = Utils.mkFrame({
		name = "InfoBox",
		size = UDim2.new(1, 0, 0, 80),
		pos = UDim2.new(0, 0, 0, 80),
		bg = C.BG_DARK,
		r = 6,
		parent = content
	})
	
	BaseUI.Refs.LevelLabel = Utils.mkLabel({
		text = "거점 레벨: 1",
		size = UDim2.new(0.5, -10, 0, 30),
		pos = UDim2.new(0, 10, 0, 10),
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = infoBox
	})
	
	BaseUI.Refs.RadiusLabel = Utils.mkLabel({
		text = "보호 반경: 30m",
		size = UDim2.new(0.5, -10, 0, 30),
		pos = UDim2.new(0, 10, 0, 40),
		ts = 16,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = infoBox
	})
	
	-- 확장 버튼
	local expandBtn = Utils.mkBtn({
		text = "반경 확장 (Level Up)",
		size = UDim2.new(1, 0, 0, 50),
		pos = UDim2.new(0, 0, 1, -60),
		bg = C.GOLD,
		color = C.BG_DARK,
		ts = 18,
		font = F.TITLE,
		r = 8,
		fn = function()
			local BaseController = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.BaseController)
			local success, err = BaseController.requestExpand()
			if success then
				UIManager.notify("거점이 확장되었습니다!")
				-- 정보 갱신을 위해 다시 요청
				local info = BaseController.getBaseInfo()
				if info then BaseUI.Refresh(info) end
			else
				UIManager.notify("확장 불가: " .. tostring(err))
			end
		end,
		parent = content
	})
	BaseUI.Refs.ExpandBtn = expandBtn
end

function BaseUI.SetVisible(visible)
	if BaseUI.Refs.Frame then
		BaseUI.Refs.Frame.Visible = visible
	end
end

function BaseUI.Refresh(info)
	currentBaseInfo = info
	if BaseUI.Refs.NameInput then
		BaseUI.Refs.NameInput.Text = info.name or "거점"
	end
	if BaseUI.Refs.LevelLabel then
		BaseUI.Refs.LevelLabel.Text = "거점 레벨: " .. tostring(info.level or 1)
	end
	if BaseUI.Refs.RadiusLabel then
		BaseUI.Refs.RadiusLabel.Text = "보호 반경: " .. tostring(info.radius or 30) .. "m"
	end
end

return BaseUI
