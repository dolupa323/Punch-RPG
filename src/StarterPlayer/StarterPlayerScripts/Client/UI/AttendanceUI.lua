-- AttendanceUI.lua
-- 시즌 출석 보상 UI (게임 접속 시 자동으로 뜨는 출석체크 그리드)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Utils = require(script.Parent:WaitForChild("UIUtils"))
local UILocalizer = require(script.Parent.Parent:WaitForChild("Localization"):WaitForChild("UILocalizer"))
local NetClient = require(script.Parent.Parent:WaitForChild("NetClient"))
local DataHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local AttendanceRewardData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("AttendanceRewardData"))

-- [색상 통일] 인벤토리/제작/포탈 등과 동일한 네이비+블루 팔레트
local RC = {
	BG_PANEL   = Color3.fromRGB(10, 15, 25),
	BG_SLOT    = Color3.fromRGB(15, 20, 35),
	BG_SLOT_ON = Color3.fromRGB(20, 40, 75), -- 오늘/수령가능 강조
	BG_SLOT_OK = Color3.fromRGB(20, 55, 35), -- 수령완료
	TEXT       = Color3.fromRGB(255, 255, 255),
	TEXT_DIM   = Color3.fromRGB(150, 160, 180),
	ACCENT     = Color3.fromRGB(40, 80, 160),
	ACCENT_H   = Color3.fromRGB(60, 100, 180),
	BORDER     = Color3.fromRGB(60, 85, 130),
	SPECIAL    = Color3.fromRGB(210, 170, 60),
	GREEN      = Color3.fromRGB(90, 200, 110),
}

local AttendanceUI = {}
local UI_MANAGER = nil
local currentData = nil -- { seasonName, totalDays, loginDays, claimedDay }

AttendanceUI.Refs = {
	Frame = nil,
	Main = nil,
	Grid = nil,
	ProgressLabel = nil,
	ClaimBtn = nil,
}

function AttendanceUI.SetVisible(visible)
	if AttendanceUI.Refs.Frame then
		AttendanceUI.Refs.Frame.Visible = visible
	end
end

local function clearGrid()
	if not AttendanceUI.Refs.Grid then return end
	for _, child in ipairs(AttendanceUI.Refs.Grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--- 일차 셀 하나의 보상 미리보기 텍스트/아이콘 구성
local function describeDayReward(day)
	local reward = AttendanceRewardData.GetDayReward(day)
	if not reward then return "", "" end

	local parts = {}
	local icon = ""
	if reward.items and reward.items[1] then
		local first = reward.items[1]
		local itemData = DataHelper.GetData("ItemData", first.itemId)
		icon = UI_MANAGER and UI_MANAGER.getItemIcon(first.itemId) or ""
		table.insert(parts, string.format("%s x%d", (itemData and itemData.name) or first.itemId, first.count))
	end
	if reward.gold and reward.gold > 0 then
		table.insert(parts, string.format("골드 x%d", reward.gold))
		if icon == "" then icon = UI_MANAGER and UI_MANAGER.getItemIcon("Icon_Gold") or "" end
	end

	return table.concat(parts, "\n"), icon
end

local function makeDayCell(parent, day, data)
	local loginDays = data.loginDays
	local claimedDay = data.claimedDay

	local isClaimed = day <= claimedDay
	local isClaimable = (day == claimedDay + 1) and (day <= loginDays)
	local reward = AttendanceRewardData.GetDayReward(day)
	local isSpecial = reward and reward.special == true

	local bg = RC.BG_SLOT
	local border = RC.BORDER
	if isClaimed then
		bg = RC.BG_SLOT_OK
		border = RC.GREEN
	elseif isClaimable then
		bg = RC.BG_SLOT_ON
		border = RC.ACCENT_H
	elseif isSpecial then
		border = RC.SPECIAL
	end

	local cell = Utils.mkFrame({
		name = "Day" .. day,
		size = UDim2.new(1, 0, 1, 0),
		bg = bg,
		bgT = 0.05,
		r = 8,
		stroke = isClaimable and 2 or 1,
		strokeC = border,
		parent = parent,
	})

	Utils.mkLabel({
		text = UILocalizer.Localize(tostring(day) .. "일차"),
		size = UDim2.new(1, -6, 0, 18),
		pos = UDim2.new(0.5, 0, 0, 4),
		anchor = Vector2.new(0.5, 0),
		ts = 12,
		bold = true,
		color = isClaimed and RC.TEXT_DIM or RC.TEXT,
		parent = cell,
	})

	if isClaimable then
		local todayTag = Utils.mkFrame({
			name = "TodayTag",
			size = UDim2.new(0, 34, 0, 16),
			pos = UDim2.new(1, -4, 0, 4),
			anchor = Vector2.new(1, 0),
			bg = RC.ACCENT_H,
			bgT = 0,
			r = 4,
			parent = cell,
		})
		Utils.mkLabel({
			text = UILocalizer.Localize("오늘"),
			size = UDim2.new(1, 0, 1, 0),
			ts = 10,
			bold = true,
			color = RC.TEXT,
			parent = todayTag,
		})
	end

	local rewardText, iconImg = describeDayReward(day)

	if isClaimed then
		Utils.mkLabel({
			text = "✔",
			size = UDim2.new(1, 0, 0, 34),
			pos = UDim2.new(0.5, 0, 0.5, 4),
			anchor = Vector2.new(0.5, 0.5),
			ts = 28,
			color = RC.GREEN,
			parent = cell,
		})
	elseif iconImg ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, 32, 0, 32)
		icon.Position = UDim2.new(0.5, 0, 0.5, -6)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Image = iconImg
		icon.Parent = cell
	end

	Utils.mkLabel({
		text = rewardText,
		size = UDim2.new(1, -6, 0, 30),
		pos = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		ts = 10,
		color = isClaimed and RC.TEXT_DIM or RC.TEXT_DIM,
		wrap = true,
		parent = cell,
	})

	return cell
end

function AttendanceUI.Refresh(data)
	if data then
		currentData = data
	end
	if not currentData or not AttendanceUI.Refs.Grid then return end

	clearGrid()

	for day = 1, currentData.totalDays do
		local cell = makeDayCell(AttendanceUI.Refs.Grid, day, currentData)
		cell.LayoutOrder = day
	end

	if AttendanceUI.Refs.ProgressLabel then
		AttendanceUI.Refs.ProgressLabel.Text = UILocalizer.Localize(string.format("진행도 %d / %d", currentData.claimedDay, currentData.totalDays))
	end

	if AttendanceUI.Refs.ClaimBtn then
		local canClaim = currentData.claimedDay < currentData.loginDays
		AttendanceUI.Refs.ClaimBtn.Text = UILocalizer.Localize(canClaim and "보상 수령" or "출석 완료")
		local color = canClaim and RC.ACCENT or RC.BG_SLOT
		Utils.setBtnState(AttendanceUI.Refs.ClaimBtn, color, canClaim and 0.05 or 0.4)
		AttendanceUI.Refs.ClaimBtn.Active = canClaim
		AttendanceUI.Refs.ClaimBtn.AutoButtonColor = canClaim
	end
end

local function requestClaim()
	-- [주의] NetClient.Request는 서버 응답의 "data" 필드만 언랩해서 두 번째 값으로 돌려준다.
	-- 서버(RuneStoneService.handleClaim)가 data = { attendance = ..., reward = ... } 형태로
	-- 담아 보내므로, 여기서도 그 평평한 구조 그대로 꺼내 써야 함.
	task.spawn(function()
		local ok, res = NetClient.Request("Attendance.Claim.Request", {})
		if ok and res and res.attendance then
			AttendanceUI.Refresh(res.attendance)
			if res.reward and UI_MANAGER and UI_MANAGER.showRuneStoneReward then
				UI_MANAGER.showRuneStoneReward({ items = res.reward.items, gold = res.reward.gold })
			end
		elseif UI_MANAGER and UI_MANAGER.notify then
			UI_MANAGER.notify(UILocalizer.Localize("보상 수령에 실패했습니다."), Color3.fromRGB(255, 100, 100))
		end
	end)
end

function AttendanceUI.Init(parent, UIManager)
	UI_MANAGER = UIManager

	AttendanceUI.Refs.Frame = Utils.mkFrame({
		name = "Attendance",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.5,
		vis = false,
		parent = parent,
	})

	local main = Utils.mkWindow({
		name = "Main",
		-- [반응형] 모바일/PC 분기 없이 화면 비율 기반 크기 + 최대 크기 제한만으로 동일한 레이아웃 유지
		size = UDim2.new(0.85, 0, 0.85, 0),
		maxSize = Vector2.new(680, 620),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = RC.BG_PANEL,
		stroke = 2,
		strokeC = RC.BORDER,
		r = 10,
		parent = AttendanceUI.Refs.Frame,
	})
	main.ClipsDescendants = true -- 내부 셀 테두리가 둥근 모서리 밖으로 잘려 보이는 것 방지
	AttendanceUI.Refs.Main = main

	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, -30, 0, 50),
		pos = UDim2.new(0, 15, 0, 10),
		bgT = 1,
		parent = main,
	})

	Utils.mkLabel({
		text = UILocalizer.Localize(AttendanceRewardData.SEASON_NAME),
		size = UDim2.new(1, -40, 1, 0),
		ts = 20,
		bold = true,
		color = RC.TEXT,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})

	Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 32, 0, 32),
		pos = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		bgT = 1,
		isNegative = true,
		hbg = Color3.fromRGB(65, 65, 75),
		color = RC.TEXT,
		ts = 22,
		fn = function()
			if UI_MANAGER and UI_MANAGER.closeAttendance then
				UI_MANAGER.closeAttendance()
			else
				AttendanceUI.SetVisible(false)
			end
		end,
		parent = header,
	})

	local columns = 7
	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Name = "GridScroll"
	gridScroll.Size = UDim2.new(1, -30, 1, -130)
	gridScroll.Position = UDim2.new(0, 15, 0, 66)
	gridScroll.BackgroundTransparency = 1
	gridScroll.BorderSizePixel = 0
	gridScroll.ScrollBarThickness = 4
	gridScroll.ScrollBarImageColor3 = RC.BORDER
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridScroll.CanvasSize = UDim2.new()
	gridScroll.ClipsDescendants = true
	gridScroll.Parent = main

	-- [테두리 잘림 방지] 셀이 컨테이너 폭을 정확히 100% 채우면 테두리(UIStroke)의
	-- 바깥쪽 절반이 ClipsDescendants 경계에 걸려 잘려 보인다. 사방에 여유 패딩을 둬서
	-- 셀 스트로크가 클리핑 경계에 닿지 않게 한다.
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingLeft = UDim.new(0, 4)
	gridPadding.PaddingRight = UDim.new(0, 4)
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingBottom = UDim.new(0, 4)
	gridPadding.Parent = gridScroll

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.CellSize = UDim2.new(1 / columns, -8 * (columns - 1) / columns, 0, 84)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridScroll
	AttendanceUI.Refs.Grid = gridScroll

	local footer = Utils.mkFrame({
		name = "Footer",
		size = UDim2.new(1, -30, 0, 50),
		pos = UDim2.new(0, 15, 1, -60),
		bgT = 1,
		parent = main,
	})

	AttendanceUI.Refs.ProgressLabel = Utils.mkLabel({
		text = "",
		size = UDim2.new(0.5, 0, 1, 0),
		ts = 15,
		color = RC.TEXT_DIM,
		ax = Enum.TextXAlignment.Left,
		parent = footer,
	})

	AttendanceUI.Refs.ClaimBtn = Utils.mkBtn({
		name = "ClaimBtn",
		text = UILocalizer.Localize("보상 수령"),
		size = UDim2.new(0, 170, 1, 0),
		pos = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		bg = RC.ACCENT,
		hbg = RC.ACCENT_H,
		color = RC.TEXT,
		ts = 16,
		font = Theme.Fonts.TITLE,
		r = 9,
		fn = requestClaim,
		parent = footer,
	})
end

return AttendanceUI
