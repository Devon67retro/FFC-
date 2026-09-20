local shared = odh_shared_plugins

local my_own_tab = shared.CreateTab("Firefly Timer", "")
local my_own_section = my_own_tab:AddSection("Firefly Timer", "Auto Jump + cooldown tracker")

my_own_section:AddLabel("Made by: SANGUINE 🤤🤤")
my_own_section:AddParagraph("Firefly Timer", "Open the settings GUI to configure Auto Jump and Firefly Timer.")

local ENV
if getgenv then ENV = getgenv() else ENV = _G end

if ENV.__FireflyConnections then
	for _, conn in ipairs(ENV.__FireflyConnections) do
		pcall(function() conn:Disconnect() end)
	end
end
ENV.__FireflyConnections = {}

if ENV.__FireflyJumpThread then
	pcall(function() task.cancel(ENV.__FireflyJumpThread) end)
	ENV.__FireflyJumpThread = nil
end

pcall(function()
	local CAS = game:GetService("ContextActionService")
	CAS:UnbindAction("FireflyAutoJump")
end)

local MY_ID = tick() .. math.random(1000, 9999)
ENV.__FireflyInstanceID = MY_ID

local function isCurrent()
	return ENV.__FireflyInstanceID == MY_ID
end

local function regConn(conn)
	if conn then table.insert(ENV.__FireflyConnections, conn) end
	return conn
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local pg = LocalPlayer:WaitForChild("PlayerGui")

for _, name in ipairs({"FireflySettingsGui", "FireflyTimerGui", "FireflyCooldownGui"}) do
	local old = pg:FindFirstChild(name)
	if old then old:Destroy() end
end

local countdownDuration = 2.5
local frameSize = UDim2.new(0, 100, 0, 50)
local framePosition = UDim2.new(0.5, -50, 0.5, -100)
local cdFontSize = 22

local enabled = false
local autoJumpEnabled = false
local firstJumpTiming = 0.24
local secondJumpTiming = 0.50

local isCountingDown = false
local fireflyActive = false
local countdownConnection = nil
local toolConnection = nil
local screenGui, frame, label, stroke, corner

local cdScreenGui, cdFrame, cdLabel
local cooldownConnection = nil
local blockConnection = nil
local isOnCooldown = false

local jumpTriggered = false
local jumpActionBound = false
local roundRewardsHooked = false

local backpackAddedConn, charAddedConn
local backpackWatchConn, characterWatchConn

local function buildGui()
	if screenGui then return end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FireflyTimerGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = pg

	frame = Instance.new("Frame")
	frame.Name = "TimerFrame"
	frame.Size = frameSize
	frame.Position = framePosition
	frame.BackgroundTransparency = 0.7
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screenGui

	stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 0, 0)
	stroke.Thickness = 1
	stroke.Parent = frame

	label = Instance.new("TextLabel")
	label.Name = "CountdownLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = tostring(countdownDuration)
	label.Parent = frame

	corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
end

local function buildCooldownGui()
	if cdScreenGui then return end
	cdScreenGui = Instance.new("ScreenGui")
	cdScreenGui.Name = "FireflyCooldownGui"
	cdScreenGui.ResetOnSpawn = false
	cdScreenGui.Parent = pg

	cdFrame = Instance.new("Frame")
	cdFrame.Name = "CooldownFrame"
	cdFrame.Size = UDim2.new(0, 110, 0, 28)
	cdFrame.Position = UDim2.new(0, 20, 0.5, 0)
	cdFrame.BackgroundTransparency = 1
	cdFrame.BorderSizePixel = 0
	cdFrame.Active = true
	cdFrame.Visible = false
	cdFrame.Parent = cdScreenGui

	cdLabel = Instance.new("TextLabel")
	cdLabel.Name = "CooldownLabel"
	cdLabel.Size = UDim2.new(1, 0, 1, 0)
	cdLabel.BackgroundTransparency = 1
	cdLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	cdLabel.TextSize = cdFontSize
	cdLabel.Font = Enum.Font.GothamBold
	cdLabel.TextXAlignment = Enum.TextXAlignment.Left
	cdLabel.Text = "0.0"
	cdLabel.Parent = cdFrame

	local dragging, dragStart, startPos
	cdFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = cdFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	cdFrame.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				local delta = input.Position - dragStart
				cdFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
	end)
end

local function bindJumpAction()
	if jumpActionBound then
		ContextActionService:UnbindAction("FireflyAutoJump")
		jumpActionBound = false
	end
	ContextActionService:BindAction("FireflyAutoJump", function(actionName, inputState)
		if inputState == Enum.UserInputState.Begin then
			local char = LocalPlayer.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Jump = true
				end
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Space)
	jumpActionBound = true
end

local function unbindJumpAction()
	if not jumpActionBound then return end
	ContextActionService:UnbindAction("FireflyAutoJump")
	jumpActionBound = false
end

local function fireJump()
	if not isCurrent() then return false end
	local char = LocalPlayer.Character
	if not char then return false end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	humanoid.Jump = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	return true
end

local function fireTwoJumps()
	fireJump()
	if ENV.__FireflyJumpThread then
		pcall(function() task.cancel(ENV.__FireflyJumpThread) end)
		ENV.__FireflyJumpThread = nil
	end
	ENV.__FireflyJumpThread = task.delay(secondJumpTiming, function()
		if not isCurrent() then return end
		fireJump()
		ENV.__FireflyJumpThread = nil
	end)
end

local function startCountdown()
	if not enabled then return end
	buildGui()
	if countdownConnection then countdownConnection:Disconnect() countdownConnection = nil end

	jumpTriggered = false
	isCountingDown = true
	frame.Visible = true
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.7
	stroke.Color = Color3.fromRGB(255, 0, 0)
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = string.format("%.1f", countdownDuration)

	local timeLeft = countdownDuration
	countdownConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not isCurrent() then
			if countdownConnection then countdownConnection:Disconnect() countdownConnection = nil end
			return
		end
		timeLeft -= deltaTime
		if timeLeft <= 0 then
			timeLeft = 0
			label.Text = "0.0"
			frame.Visible = false
			isCountingDown = false
			fireflyActive = false
			if countdownConnection then countdownConnection:Disconnect() countdownConnection = nil end
			return
		end
		if autoJumpEnabled and isCountingDown and not jumpTriggered and timeLeft <= firstJumpTiming then
			jumpTriggered = true
			fireTwoJumps()
		end
		label.Text = string.format("%.1f", timeLeft)
	end)
	regConn(countdownConnection)
end

local function startCooldownPanel()
	buildCooldownGui()
	if cooldownConnection then cooldownConnection:Disconnect() cooldownConnection = nil end
	cdFrame.Visible = true
	cdLabel.Text = "0.0"
	local elapsed = 0
	cooldownConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not isCurrent() then
			if cooldownConnection then cooldownConnection:Disconnect() cooldownConnection = nil end
			return
		end
		elapsed += deltaTime
		if elapsed >= 16 then
			elapsed = 16
			cdLabel.Text = "Active"
			if cooldownConnection then cooldownConnection:Disconnect() cooldownConnection = nil end
			return
		end
		cdLabel.Text = string.format("%.1f", elapsed)
	end)
	regConn(cooldownConnection)
end

local function startBlockTimer()
	isOnCooldown = true
	if blockConnection then blockConnection:Disconnect() blockConnection = nil end
	local elapsed = 0
	blockConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not isCurrent() then
			if blockConnection then blockConnection:Disconnect() blockConnection = nil end
			return
		end
		elapsed += deltaTime
		if elapsed >= 16 then
			isOnCooldown = false
			if blockConnection then blockConnection:Disconnect() blockConnection = nil end
		end
	end)
	regConn(blockConnection)
end

local function connectToTool(tool)
	if toolConnection then toolConnection:Disconnect() toolConnection = nil end
	toolConnection = tool.Activated:Connect(function()
		if not isCurrent() then return end
		if not enabled then return end
		if isOnCooldown then return end
		fireflyActive = true
		startCountdown()
		startCooldownPanel()
		startBlockTimer()
	end)
	regConn(toolConnection)
end

local function resetCooldown()
	if cooldownConnection then cooldownConnection:Disconnect() cooldownConnection = nil end
	if blockConnection then blockConnection:Disconnect() blockConnection = nil end
	isOnCooldown = false
	if cdLabel then cdLabel.Text = "Active" end
	if cdFrame then cdFrame.Visible = true end
end

local function hookRoundRewards()
	if roundRewardsHooked then return end
	local rp = game:GetService("ReplicatedStorage")
	local remotes = rp:FindFirstChild("Remotes")
	local gameplay = remotes and remotes:FindFirstChild("Gameplay")
	local remote = gameplay and gameplay:FindFirstChild("GetLastRoundRewards")
	if not remote then return end

	if hookfunction then
		local ok = pcall(function()
			local old
			old = hookfunction(remote.InvokeServer, function(self, ...)
				pcall(resetCooldown)
				return old(self, ...)
			end)
		end)
		if ok then
			roundRewardsHooked = true
			return
		end
	end

	if hookmetamethod and getrawmetatable and getnamecallmethod and setreadonly and newcclosure then
		local ok = pcall(function()
			local mt = getrawmetatable(game)
			local oldNamecall = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				if self == remote and getnamecallmethod() == "InvokeServer" then
					pcall(resetCooldown)
				end
				return oldNamecall(self, ...)
			end)
			setreadonly(mt, true)
		end)
		if ok then
			roundRewardsHooked = true
		end
	end
end

local function unhookTool()
	if toolConnection then toolConnection:Disconnect() toolConnection = nil end
	if countdownConnection then countdownConnection:Disconnect() countdownConnection = nil end
	if cooldownConnection then cooldownConnection:Disconnect() cooldownConnection = nil end
	if blockConnection then blockConnection:Disconnect() blockConnection = nil end
	if backpackAddedConn then backpackAddedConn:Disconnect() backpackAddedConn = nil end
	if charAddedConn then charAddedConn:Disconnect() charAddedConn = nil end
	if backpackWatchConn then backpackWatchConn:Disconnect() backpackWatchConn = nil end
	if characterWatchConn then characterWatchConn:Disconnect() characterWatchConn = nil end
	if ENV.__FireflyJumpThread then
		pcall(function() task.cancel(ENV.__FireflyJumpThread) end)
		ENV.__FireflyJumpThread = nil
	end
	unbindJumpAction()
	roundRewardsHooked = false
	if frame then frame.Visible = false end
	if cdFrame then cdFrame.Visible = false end
	isCountingDown = false
	isOnCooldown = false
	fireflyActive = false
end

local function hookTool()
	unhookTool()
	local function watchContainer(container)
		if not container then return nil end
		local tool = container:FindFirstChild("Fireflies")
		if tool then connectToTool(tool) end
		return container.ChildAdded:Connect(function(child)
			if child.Name == "Fireflies" then connectToTool(child) end
		end)
	end
	backpackWatchConn = watchContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
	characterWatchConn = watchContainer(LocalPlayer.Character)
	backpackAddedConn = LocalPlayer.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			if backpackWatchConn then backpackWatchConn:Disconnect() end
			backpackWatchConn = watchContainer(child)
		end
	end)
	charAddedConn = LocalPlayer.CharacterAdded:Connect(function(char)
		resetCooldown()
		if characterWatchConn then characterWatchConn:Disconnect() end
		characterWatchConn = watchContainer(char)
	end)
	bindJumpAction()
	hookRoundRewards()
	task.spawn(function()
		for _ = 1, 20 do
			if roundRewardsHooked then break end
			hookRoundRewards()
			task.wait(0.5)
		end
	end)
end

local settingsGui, settingsOuter, settingsBody
local isMinimized = false
local enableBtn = nil

local function createSlider(parent, yPos, labelText, minVal, maxVal, defaultVal, onChange)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -28, 0, 52)
	container.Position = UDim2.new(0, 14, 0, yPos)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Text = labelText .. ": " .. string.format("%.2f", defaultVal)
	title.TextColor3 = Color3.fromRGB(235, 235, 235)
	title.TextSize = 15
	title.Font = Enum.Font.Gotham
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = container

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 14)
	bar.Position = UDim2.new(0, 0, 0, 26)
	bar.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
	bar.BorderSizePixel = 0
	bar.Parent = container
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 7)
	bc.Parent = bar

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new((defaultVal - minVal) / (maxVal - minVal), 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 7)
	fc.Parent = fill

	local dragging = false
	local function updateFromX(xPos)
		local rel = (xPos - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
		rel = math.clamp(rel, 0, 1)
		local val = minVal + rel * (maxVal - minVal)
		val = math.floor(val * 100 + 0.5) / 100
		fill.Size = UDim2.new(rel, 0, 1, 0)
		title.Text = labelText .. ": " .. string.format("%.2f", val)
		onChange(val)
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return title
end

local function buildSettingsGui()
	if settingsGui then return settingsGui end

	settingsGui = Instance.new("ScreenGui")
	settingsGui.Name = "FireflySettingsGui"
	settingsGui.ResetOnSpawn = false
	settingsGui.Parent = pg

	settingsOuter = Instance.new("Frame")
	settingsOuter.Name = "Outer"
	settingsOuter.Size = UDim2.new(0, 320, 0, 220)
	settingsOuter.Position = UDim2.new(0.5, -160, 0.3, 0)
	settingsOuter.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	settingsOuter.BorderSizePixel = 0
	settingsOuter.Active = true
	settingsOuter.Visible = false
	settingsOuter.Parent = settingsGui
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(0, 10)
	oc.Parent = settingsOuter

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 34)
	titleBar.BackgroundColor3 = Color3.fromRGB(48, 48, 54)
	titleBar.BorderSizePixel = 0
	titleBar.Active = true
	titleBar.Parent = settingsOuter
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 10)
	tc.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -50, 1, 0)
	titleLabel.Position = UDim2.new(0, 14, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Firefly Timer Settings"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 16
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	local minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Size = UDim2.new(0, 24, 0, 24)
	minimizeBtn.Position = UDim2.new(1, -30, 0, 5)
	minimizeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	minimizeBtn.Text = "—"
	minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	minimizeBtn.TextSize = 16
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.BorderSizePixel = 0
	minimizeBtn.AutoButtonColor = false
	minimizeBtn.Parent = titleBar
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0, 6)
	mc.Parent = minimizeBtn

	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = settingsOuter.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	titleBar.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				local delta = input.Position - dragStart
				settingsOuter.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
	end)

	minimizeBtn.MouseButton1Click:Connect(function()
		isMinimized = not isMinimized
		if isMinimized then
			settingsBody.Visible = false
			settingsOuter.Size = UDim2.new(0, 320, 0, 34)
			minimizeBtn.Text = "+"
		else
			settingsBody.Visible = true
			settingsOuter.Size = UDim2.new(0, 320, 0, 220)
			minimizeBtn.Text = "—"
		end
	end)

	settingsBody = Instance.new("Frame")
	settingsBody.Name = "Body"
	settingsBody.Size = UDim2.new(1, 0, 1, -34)
	settingsBody.Position = UDim2.new(0, 0, 0, 34)
	settingsBody.BackgroundTransparency = 1
	settingsBody.Parent = settingsOuter

	enableBtn = Instance.new("TextButton")
	enableBtn.Size = UDim2.new(1, -28, 0, 40)
	enableBtn.Position = UDim2.new(0, 14, 0, 12)
	enableBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
	enableBtn.Text = "Firefly Timer: OFF"
	enableBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	enableBtn.TextSize = 16
	enableBtn.Font = Enum.Font.GothamBold
	enableBtn.BorderSizePixel = 0
	enableBtn.AutoButtonColor = false
	enableBtn.Parent = settingsBody
	local ebc = Instance.new("UICorner")
	ebc.CornerRadius = UDim.new(0, 8)
	ebc.Parent = enableBtn

	enableBtn.MouseButton1Click:Connect(function()
		enabled = not enabled
		if enabled then
			enableBtn.Text = "Firefly Timer: ON"
			enableBtn.BackgroundColor3 = Color3.fromRGB(70, 180, 70)
			buildGui()
			buildCooldownGui()
			hookTool()
		else
			enableBtn.Text = "Firefly Timer: OFF"
			enableBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
			unhookTool()
		end
	end)

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(1, -28, 0, 40)
	toggleBtn.Position = UDim2.new(0, 14, 0, 62)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
	toggleBtn.Text = "Auto Jump: OFF"
	toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleBtn.TextSize = 16
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.BorderSizePixel = 0
	toggleBtn.AutoButtonColor = false
	toggleBtn.Parent = settingsBody
	local tgc = Instance.new("UICorner")
	tgc.CornerRadius = UDim.new(0, 8)
	tgc.Parent = toggleBtn

	toggleBtn.MouseButton1Click:Connect(function()
		autoJumpEnabled = not autoJumpEnabled
		if autoJumpEnabled then
			toggleBtn.Text = "Auto Jump: ON"
			toggleBtn.BackgroundColor3 = Color3.fromRGB(70, 180, 70)
		else
			toggleBtn.Text = "Auto Jump: OFF"
			toggleBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
		end
	end)

	createSlider(settingsBody, 112, "Cooldown Font Size", 8, 48, cdFontSize, function(v)
		cdFontSize = math.floor(v + 0.5)
		if cdLabel then cdLabel.TextSize = cdFontSize end
	end)

	return settingsGui
end

my_own_section:AddToggle("Open Firefly Settings", function(bool)
	buildSettingsGui()
	settingsGui.Enabled = true
	settingsOuter.Visible = bool
end)
