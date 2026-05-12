-- Simple Loading Screen (graphic version preserved) + safe logic
-- Fixes:
--  1) DOES NOT disable other ScreenGuis (prevents MainMenu not coming back due to race conditions)
--  2) Still blocks clicks using a full-screen Active frame
--  3) Adds a failsafe timeout so you can't get permanently stuck

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================
-- COLORS / GRADIENTS (yours)
-- =========================
local gradient_fill_color = ColorSequence.new{
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(143, 143, 143)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(143, 143, 143)),
}
local gradient_bg_color = ColorSequence.new{
	ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 56, 56)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(52, 52, 52))
}
local gradient_bg2_color = ColorSequence.new{
	ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 0, 0))
}

-- =========================
-- SHOW ONLY ONCE (safer)
-- =========================
if playerGui:GetAttribute("LoadedOnce") then
	return
end
playerGui:SetAttribute("LoadedOnce", true)

-- (Optional) keep your global flag if other scripts still rely on it,
-- but it's better to not depend on _G for core flow.
_G.firstJoin = true

-- Remove any previous loading screen
local old = playerGui:FindFirstChild("SimpleLoadingScreen")
if old then old:Destroy() end

-- =========================
-- CREATE GUI (yours)
-- =========================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SimpleLoadingScreen"
screenGui.DisplayOrder = 1000
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Container (kept from your script)
local canvasGroup = Instance.new("Frame")
canvasGroup.Name = "CanvasGroup"
canvasGroup.BackgroundTransparency = 1
canvasGroup.Size = UDim2.new(1,0,1,0)
canvasGroup.Position = UDim2.new(0,0,0,0)
canvasGroup.Parent = screenGui

-- Background full screen: this blocks input so players can't click GUIs behind it
local bg = Instance.new("Frame")
bg.BackgroundColor3 = Color3.fromRGB(121, 121, 121)
bg.BackgroundTransparency = 0
bg.Size = UDim2.new(1,0,1,0)
bg.Position = UDim2.new(0,0,0,0)
bg.AnchorPoint = Vector2.new(0,0)
bg.Parent = canvasGroup
bg.Active = true
bg.Selectable = true

local UIGradientBG = Instance.new("UIGradient")
UIGradientBG.Color = gradient_bg2_color
UIGradientBG.Rotation = -90
UIGradientBG.Parent = bg

-- Logo (yours)
local repLogo = Instance.new("ImageLabel")
repLogo.Size = UDim2.new(0.15,0,0.25,0)
repLogo.AnchorPoint = Vector2.new(0.5,0.5)
repLogo.Position = UDim2.new(0.5,0,0.4,0)
repLogo.BackgroundTransparency = 1
repLogo.ImageTransparency = 0.1
repLogo.ScaleType = Enum.ScaleType.Fit
repLogo.Image = "rbxassetid://15431835245"
repLogo.Parent = bg

local UIGradientLogo = Instance.new("UIGradient")
UIGradientLogo.Color = gradient_fill_color
UIGradientLogo.Rotation = 90
UIGradientLogo.Parent = repLogo

-- Loading bar (yours)
local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(0.5,0,0.05,0)
barBack.Position = UDim2.new(0.25,0,0.75,0)
barBack.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
barBack.BackgroundTransparency = 0.3
barBack.BorderSizePixel = 0
barBack.Parent = bg

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.new(1, 1, 1)
UIStroke.Thickness = 2.5
UIStroke.Parent = barBack

local UIGradient2  = Instance.new("UIGradient")
UIGradient2.Color = gradient_bg_color
UIGradient2.Rotation = 90
UIGradient2.Parent = barBack

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(5,0)
UICorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0,0,1,0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
barFill.BackgroundTransparency = 0.3
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local UIGradient  = Instance.new("UIGradient")
UIGradient.Color = gradient_fill_color
UIGradient.Rotation = 90
UIGradient.Parent = barFill

local UICorner2 = Instance.new("UICorner")
UICorner2.CornerRadius = UDim.new(5,0)
UICorner2.Parent = barFill

-- Text (yours)
local text = Instance.new("TextLabel")
text.Text = "Loading 0% - ..."
text.Size = UDim2.new(0.5,0,0.06,0)
text.Position = UDim2.new(0.25,0,0.68,0)
text.BackgroundTransparency = 1
text.TextColor3 = Color3.new(1,1,1)
text.Font = Enum.Font.GothamMedium
text.TextSize = 28
text.Parent = bg

local differentText = Instance.new("TextLabel")
differentText.Text = "T H E  G A L A C T I C  R E P U B L I C"
differentText.Size = UDim2.new(0.5,0,0.06,0)
differentText.Position = UDim2.new(0.25,0,0.1,0)
differentText.BackgroundTransparency = 1
differentText.TextColor3 = Color3.new(1,1,1)
differentText.Font = Enum.Font.GothamMedium
differentText.TextSize = 28
differentText.Parent = bg

-- =========================
-- ANIMATIONS (yours)
-- =========================
local rotationSpeed = 180
local repRotation = 0
RunService.RenderStepped:Connect(function(dt)
	repRotation = (repRotation + rotationSpeed * dt) % 360
	repLogo.Rotation = repRotation
end)

-- =========================
-- StartBackgroundNPC BoolValue (yours, but safer)
-- =========================
local function ensureStartBackgroundNPC()
	local v = ReplicatedStorage:FindFirstChild("StartBackgroundNPC")
	if not v then
		v = Instance.new("BoolValue")
		v.Name = "StartBackgroundNPC"
		v.Value = false
		v.Parent = ReplicatedStorage
	end
	return v
end

local startBackgroundNPC = ensureStartBackgroundNPC()

-- =========================
-- ENDING / DESTROY (yours + failsafe)
-- =========================
local function slideUpAndDestroy(callback)
	local tween = TweenService:Create(
		bg,
		TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{Position = UDim2.new(0,0,-1,0)}
	)
	tween:Play()
	task.wait(0.8) -- Failsafe wait
	if callback then callback() end
end

local finished = false
local function endLoading()
	if finished then return end
	finished = true

	-- Trigger NPCs
	startBackgroundNPC.Value = true

	-- Wait 2 frames
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()

	local function forceMainMenuOn()
		local menu = playerGui:FindFirstChild("MainMenu") or playerGui:FindFirstChild("MainMenu", true)
		if menu and menu:IsA("ScreenGui") then
			menu.Enabled = true
		end

		-- Also force menu camera if your menu uses a Scriptable camera
		local cam = workspace.CurrentCamera
		local part = workspace:FindFirstChild("MainMenuWorkspace")
			and workspace.MainMenuWorkspace:FindFirstChild("Camera")
			and workspace.MainMenuWorkspace.Camera:FindFirstChild("MainCamera")

		if cam and part then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = part.CFrame
		end
	end

	-- Call it a few times to win race conditions (Reduced from 30 to 10 for speed)
	for i = 1, 10 do
		forceMainMenuOn()
		RunService.Heartbeat:Wait()
	end
	
	slideUpAndDestroy(function()
		if screenGui.Parent then
			screenGui:Destroy()
		end
	end)
	
end

-- =========================
-- PROGRESS SIMULATION (stable: loop-based)
-- =========================
local loadingSteps = {
	"Rep Storage",
	"Ranks & Groups",
	"Inventory",
	"Player Data",
	"Finishing Up"
}

local LOADING_DURATION = 4.0 

task.spawn(function()
	print("[LoadingScreen] Simulazione avviata")
	local steps = 100
	for i = 0, steps do
		if finished then break end
		
		local percent = i / steps
		barFill.Size = UDim2.new(percent, 0, 1, 0)
		
		local stepIndex = math.clamp(math.floor(percent * (#loadingSteps - 1)) + 1, 1, #loadingSteps)
		text.Text = string.upper(string.format("Loading %d%% - %s", math.floor(percent * 100), loadingSteps[stepIndex]))
		
		if i % 20 == 0 then
			print("[LoadingScreen] Progresso:", i, "%")
		end

		-- Calcola quanto tempo aspettare per ogni step
		local stepTime = LOADING_DURATION / steps
		local elapsed = 0
		while elapsed < stepTime do
			elapsed += RunService.Heartbeat:Wait()
		end
	end
	
	if not finished then
		print("[LoadingScreen] Fine loop, chiusura...")
		endLoading()
	end
end)

-- FAILSAFE: Ensure the screen disappears even if something hangs
task.delay(LOADING_DURATION + 10, function()
	if not finished then
		warn("[LoadingScreen] FAILSAFE TRIGGERED")
		endLoading()
	end
end)