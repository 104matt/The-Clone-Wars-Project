-- Simple Loading Screen (GRAFICA ORIGINALE RIPRISTINATA + FIX 1%)
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================
-- LOGICA ANTI-BLOCCO (Esecuzione Singola)
-- =========================
if _G.LoadingScreenExecuted then return end
_G.LoadingScreenExecuted = true

-- =========================
-- COLORI / GRADIENTI (ORIGINALI)
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
-- CREAZIONE GUI (IDENTICA ALLA TUA)
-- =========================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SimpleLoadingScreen"
screenGui.DisplayOrder = 10000 -- Molto alto per stare sopra a tutto
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local canvasGroup = Instance.new("Frame")
canvasGroup.Name = "CanvasGroup"
canvasGroup.BackgroundTransparency = 1
canvasGroup.Size = UDim2.new(1,0,1,0)
canvasGroup.Parent = screenGui

local bg = Instance.new("Frame")
bg.BackgroundColor3 = Color3.fromRGB(121, 121, 121)
bg.Size = UDim2.new(1,0,1,0)
bg.Active = true
bg.Parent = canvasGroup

local UIGradientBG = Instance.new("UIGradient")
UIGradientBG.Color = gradient_bg2_color
UIGradientBG.Rotation = -90
UIGradientBG.Parent = bg

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

local text = Instance.new("TextLabel")
text.Text = "LOADING 0% - ..."
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
-- ANIMAZIONI & NPC (ORIGINALI)
-- =========================
local rotationSpeed = 180
local repRotation = 0
RunService.RenderStepped:Connect(function(dt)
	if bg.Parent then
		repRotation = (repRotation + rotationSpeed * dt) % 360
		repLogo.Rotation = repRotation
	end
end)

local function ensureStartBackgroundNPC()
	local v = ReplicatedStorage:FindFirstChild("StartBackgroundNPC")
	if not v then
		v = Instance.new("BoolValue", ReplicatedStorage)
		v.Name = "StartBackgroundNPC"
	end
	return v
end

-- =========================
-- FUNZIONE DI CHIUSURA E MAIN MENU (CORRETTA)
-- =========================
local finished = false
local function endLoading()
	if finished then return end
	finished = true

	-- Attivazione NPC
	local startBackgroundNPC = ensureStartBackgroundNPC()
	startBackgroundNPC.Value = true

	-- LOGICA MENU PRINCIPALE (Assicura che appaia)
	local function forceMenu()
		local menu = playerGui:FindFirstChild("MainMenu", true)
		if menu and menu:IsA("ScreenGui") then
			menu.Enabled = true
		end
		
		-- Camera del Menu
		local cam = workspace.CurrentCamera
		local menuWorkspace = workspace:FindFirstChild("MainMenuWorkspace")
		local camPart = menuWorkspace and menuWorkspace:FindFirstChild("Camera") and menuWorkspace.Camera:FindFirstChild("MainCamera")
		
		if cam and camPart then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = camPart.CFrame
		end
	end

	-- Eseguiamo il trigger del menu più volte per sicurezza
	task.spawn(function()
		for i = 1, 5 do
			forceMenu()
			task.wait(0.1)
		end
	end)

	-- Animazione di uscita
	local tween = TweenService:Create(bg, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {Position = UDim2.new(0,0,-1,0)})
	tween:Play()
	tween.Completed:Connect(function()
		screenGui:Destroy()
	end)
end

-- =========================
-- LOOP DI CARICAMENTO (FIX PER IL BLOCCO 1%)
-- =========================
local loadingSteps = {"Rep Storage", "Ranks & Groups", "Inventory", "Player Data", "Finishing Up"}

task.spawn(function()
	-- Piccolo delay iniziale per evitare il freeze immediato all'1%
	task.wait(0.5) 
	
	local totalSteps = 100
	for i = 0, totalSteps do
		local percent = i / totalSteps
		
		-- Aggiornamento UI
		barFill.Size = UDim2.new(percent, 0, 1, 0)
		local stepIdx = math.clamp(math.floor(percent * (#loadingSteps - 1)) + 1, 1, #loadingSteps)
		text.Text = string.upper(string.format("Loading %d%% - %s", i, loadingSteps[stepIdx]))
		
		-- Velocità caricamento (4 secondi totali circa)
		task.wait(0.04) 
	end
	
	endLoading()
end)

-- FAILSAFE (15 secondi)
task.delay(15, function()
	if not finished then
		warn("Loading Screen Failsafe Triggered!")
		endLoading()
	end
end)