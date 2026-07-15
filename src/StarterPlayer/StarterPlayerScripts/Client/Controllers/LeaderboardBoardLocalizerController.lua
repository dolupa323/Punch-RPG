-- LeaderboardBoardLocalizerController.lua
-- Workspace.NewWorldMap.LeaderBoard.leaderboard1/2 게시판의 제목(Display)만 클라이언트
-- 언어에 맞게 로컬라이징한다. 순위 행에 들어가는 유저 닉네임은 고유값이므로 절대 건드리지 않는다.

local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local UILocalizer = require(Client:WaitForChild("Localization"):WaitForChild("UILocalizer"))

local LeaderboardBoardLocalizerController = {}
local initialized = false

local BOARD_NAMES = { "leaderboard1", "leaderboard2" }

-- 서버가 아직 채우기 전 원본 플레이스홀더 문구 (이 상태에서는 로컬라이징하지 않고 서버가 채울 때까지 대기)
local PLACEHOLDER_TEXTS = {
	["Top Robux!"] = true,
	["Top Time Played!"] = true,
	[""] = true,
}

local function findDisplayLabel(model: Instance): TextLabel?
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local gui = part:FindFirstChildOfClass("SurfaceGui")
			if gui then
				local frame = gui:FindFirstChild("Frame")
				local display = frame and frame:FindFirstChild("Display")
				if display and display:IsA("TextLabel") then
					return display
				end
			end
		end
	end
	return nil
end

local function localizeBoard(model: Instance)
	local display = findDisplayLabel(model)
	if not display then return end

	local conn
	local function apply()
		if PLACEHOLDER_TEXTS[display.Text] then
			return -- 서버가 아직 제목을 안 채웠음 - 다음 변경을 계속 기다림
		end
		if conn then
			conn:Disconnect()
			conn = nil
		end
		display.Text = UILocalizer.Localize(display.Text)
	end

	apply() -- 이미 서버가 채워둔 상태라면 즉시 처리
	if display.Text ~= "" and not PLACEHOLDER_TEXTS[display.Text] then
		return -- apply()에서 이미 처리 완료, 감시 불필요
	end

	conn = display:GetPropertyChangedSignal("Text"):Connect(apply)
end

function LeaderboardBoardLocalizerController.Init()
	if initialized then return end
	initialized = true

	for _, name in ipairs(BOARD_NAMES) do
		task.spawn(function()
			local ok, folder = pcall(function()
				return Workspace:WaitForChild("NewWorldMap", 30):WaitForChild("LeaderBoard", 30)
			end)
			if not ok or not folder then return end
			local model = folder:WaitForChild(name, 30)
			if model then
				localizeBoard(model)
			end
		end)
	end

	print("[LeaderboardBoardLocalizerController] Initialized")
end

return LeaderboardBoardLocalizerController
