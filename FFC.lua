local shared = odh_shared_plugins

if not shared or type(shared.CreateTab) ~= "function" then
	warn("[Firefly Timer] Load through the current Overdrive H plugin menu.")
	return
end

local ok, my_own_tab = pcall(function()
	return shared.CreateTab("Firefly Timer", "/Devon67retro/Test/refs/heads/main/icon")
end)

if not ok or not my_own_tab then
	warn("[Firefly Timer] CreateTab failed: " .. tostring(my_own_tab))
	return
end

local ok2, my_own_section = pcall(function()
	return my_own_tab:AddSection("Firefly Timer", "Countdown + auto jump")
end)

if not ok2 or not my_own_section then
	warn("[Firefly Timer] AddSection failed: " .. tostring(my_own_section))
	return
end

my_own_section:AddLabel("Made by: SANGUINE ⚡⚡ ")
my_own_section:AddParagraph("Firefly Timer", "Jumps at 0.24s remaining, second jump 0.50s later.")

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
local LocalPlayer = Players.LocalPlayer
local pg = LocalPlayer:WaitForChild("PlayerGui")

for _, name in ipairs({"FireflySettingsGui", "FireflyTimerGui", "FireflyCooldownGui"}) do
	local old = pg:FindFirstChild(name)
	if old then old:Destroy() end
end

local countdownDuration = 2.5
local frameSize = UDim2.new(0, 100, 0, 50)
local framePosition = UDim2.new(0.5, -50, 0.5, -100)
local cdFontSize = 48

local enabled = false
local firstJumpTiming = 0.24
local secondJumpTiming = 0.50

local isCountingDown = false
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
	cdFrame.Size = UDim2.new(0, 150, 0, 60)
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
	if not enabled then return false end
	if not isCountingDown then return false end
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
		if not enabled then
			if countdownConnection then countdownConnection:Disconnect() countdownConnection = nil end
			frame.Visible = false
			isCountingDown = false
			return
		end
		timeLeft -= deltaTime
		if timeLeft <= 0 then
			timeLeft = 0
			label.Text = "0.0"
			frame.Visible = false
			isCountingDown = false
			if countdownConnection then countdownConnection:Disconnect() countdownConnection = nil end
			return
		end
		if isCountingDown and not jumpTriggered and timeLeft <= firstJumpTiming then
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

my_own_section:AddToggle("Enable Firefly Timer", function(bool)
	enabled = bool

	if bool then
		buildGui()
		buildCooldownGui()
		hookTool()
		shared.Notify("Firefly Timer enabled", 2)
	else
		unhookTool()
		shared.Notify("Firefly Timer disabled", 2)
	end
end)

print("[Firefly Timer] Loaded successfully")
