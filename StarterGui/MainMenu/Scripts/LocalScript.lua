-- MainMenuClient.lua (Unified Loading + Main Menu v4.1 - DEBUG BUILD)
-- ============================================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService       = game:GetService("GroupService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Lighting           = game:GetService("Lighting")
local TeleportService    = game:GetService("TeleportService")
local StarterGui         = game:GetService("StarterGui")
local ContentProvider    = game:GetService("ContentProvider")

-- ============================================================================
-- DEBUG HELPER  (leave enabled while testing)
-- ============================================================================
local function dbg(tag, msg)
	print(string.format("[MainMenu][%s] %s", tag, tostring(msg)))
end
local function dbgErr(tag, msg)
	warn(string.format("[MainMenu][%s] ERROR: %s", tag, tostring(msg)))
end

dbg("BOOT", "Script started")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
dbg("BOOT", "PlayerGui ready")

-- ============================================================================
-- RESPAWN-SAFE GUARD
-- If the script is re-instantiated (e.g. ResetOnSpawn=true on the parent
-- ScreenGui), we don't want to replay the loading screen. We do, however,
-- still want to re-attach camera, buttons, etc. The previous instance's
-- thread is dead by the time we get here; only the _G flags remain.
-- ============================================================================
-- If a stale loading screen exists in PlayerGui (from a killed previous
-- instance), nuke it so we don't end up with two of them stacked.
do
	local stale = PlayerGui:FindFirstChild("SimpleLoadingScreen")
	if stale then
		dbg("BOOT", "Killed orphan loading screen from previous instance")
		stale:Destroy()
	end
end

-- Optional: warn the user once if the parent ScreenGui is ResetOnSpawn=true
do
	local parentGui = script.Parent and script.Parent.Parent
	if parentGui and parentGui:IsA("ScreenGui") and parentGui.ResetOnSpawn then
		warn("[MainMenu] WARNING: " .. parentGui:GetFullName() ..
			".ResetOnSpawn = true — script will be killed on every respawn. " ..
			"Set ResetOnSpawn = false in Studio for stable behavior.")
	end
end

-- ============================================================================
-- CONFIG  (tune here)
-- ============================================================================
local VENATOR_PLACE_ID    = 0      -- TODO: set the Venator place ID
local VENATOR_MIN_RANK    = 2

local LOADING_COUNT_TARGET = 80
local LOADING_STEP_TIME    = 0.025
local LOADING_PHASE2_HOLD  = 0.6
local LOADING_PHASE3_HOLD  = 0.5
local LOADING_FADE_TIME    = 1.8     -- short fade that overlaps the *start* of the camera intro

local CAM_INTRO_TIME       = 13.0
local CAM_INTRO_STYLE      = Enum.EasingStyle.Quint
local CAM_INTRO_DIR        = Enum.EasingDirection.Out

-- ClickDetector activation distance (default Roblox is 32 — far too short for
-- a wide menu room). Setting high so the player can click from anywhere they
-- can see the buttons.
local BUTTON_CLICK_DISTANCE = 1024

local WOBBLE_FREQ_POS      = 0.30
local WOBBLE_FREQ_ROT      = 0.35
local WOBBLE_AMP_POS       = 0.04        -- studs (very subtle breathing)
local WOBBLE_AMP_ROT_DEG   = 0.08        -- degrees

local MOUSE_MAX_DEG        = 2.0
local MOUSE_LERP_SPEED     = 6.0

local DOF_FOCUS_DISTANCE   = 20
local DOF_IN_FOCUS_RADIUS  = 4
local DOF_FAR_INTENSITY    = 0.7
local DOF_NEAR_INTENSITY   = 0

local BUTTON_TWEEN_TIME    = 0.85
local PANEL_SLIDE_TIME     = 0.60
local BUTTON_PANEL_GAP     = 0.05      -- short pause between button move and panel slide
local SCREEN_WIPE_TIME     = 1.20
local WIPE_STAY_TIME       = 3.00

-- Raid intro (post-team-select): fade-out + StartCam->player camera tween,
-- timed exactly to ReplicatedStorage.MainMenuRP.IntroSound.TimeLength.
local RAID_FADE_TIME       = 1.5
local RAID_PRELOAD_TIMEOUT = 5.0
local RAID_FALLBACK_TIME   = 13.0

local function buttonCFrame(x, y, z, yawDeg)
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yawDeg or -35), 0)
end

local BUTTON_POS = {
	PlayButton = {
		Start = buttonCFrame(-2980.458, 3762.572, 3511.689, -35),
		End   = buttonCFrame(-2984.144, 3762.572, 3509.109, -35),
	},
	ShopButton = {
		Start = buttonCFrame(-2981.932, 3761.972, 3510.657, -35),
		End   = buttonCFrame(-2984.144, 3761.972, 3509.108, -35),
	},
	CreditsButton = {
		Start = buttonCFrame(-2982.014, 3761.115, 3510.600, -35),
		End   = buttonCFrame(-2984.144, 3761.115, 3509.108, -35),
	},
	SettingsButton = {
		Start = buttonCFrame(-2980.212, 3761.495, 3511.862, -35),
		End   = buttonCFrame(-2984.144, 3761.495, 3509.108, -35),
	},
}
local BUTTON_NAMES = { "PlayButton", "ShopButton", "CreditsButton", "SettingsButton" }

-- ============================================================================
-- PHASE 0 – LOADING SCREEN (must appear BEFORE any blocking WaitForChild)
-- ============================================================================
local function ensureStartBackgroundNPC()
	local v = ReplicatedStorage:FindFirstChild("StartBackgroundNPC")
	if not v then
		v = Instance.new("BoolValue")
		v.Name = "StartBackgroundNPC"
		v.Parent = ReplicatedStorage
	end
	return v
end

local function runLoadingScreen()
	dbg("LOADING", "Creating loading screen GUI")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SimpleLoadingScreen"
	screenGui.DisplayOrder = 10000
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui
	dbg("LOADING", "ScreenGui parented to PlayerGui")

	-- Background: full-screen image
	local bg = Instance.new("ImageLabel")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BorderSizePixel = 0
	bg.Image = "rbxassetid://101031937557194"
	bg.ScaleType = Enum.ScaleType.Crop
	bg.ImageTransparency = 0
	bg.Parent = screenGui

	-- Centered rotating Republic logo
	local repLogo = Instance.new("ImageLabel")
	repLogo.Size = UDim2.new(0.20, 0, 0.30, 0)
	repLogo.AnchorPoint = Vector2.new(0.5, 0.5)
	repLogo.Position = UDim2.fromScale(0.5, 0.45)
	repLogo.BackgroundTransparency = 1
	repLogo.ImageTransparency = 0
	repLogo.ScaleType = Enum.ScaleType.Fit
	repLogo.Image = "rbxassetid://126760808773309"
	repLogo.Parent = bg

	-- Status label (Montserrat Bold via FontFace, fallback SourceSansBold)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 0, 90)
	statusLabel.Position = UDim2.new(0, 0, 1, -140)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "PLEASE WAIT WHILST THE\nASSETS LOAD... 0"
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.TextSize = 28
	statusLabel.TextWrapped = true
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Font = Enum.Font.SourceSansBold -- fallback if FontFace unsupported
	local okFont = pcall(function()
		statusLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
	end)
	if not okFont then
		statusLabel.Font = Enum.Font.SourceSansBold
	end
	statusLabel.Parent = bg

	dbg("LOADING", "All UI elements created, starting rotation loop")

	-- Rotating logo
	local rot = 0
	local rotConn
	rotConn = RunService.RenderStepped:Connect(function(dt)
		if not bg.Parent then return end
		rot = (rot + 180 * dt) % 360
		repLogo.Rotation = rot
	end)

	-- Phase 1: animated counter
	dbg("LOADING", "Phase 1: counter (target=" .. LOADING_COUNT_TARGET .. ")")
	for i = 1, LOADING_COUNT_TARGET do
		statusLabel.Text = "PLEASE WAIT WHILST THE\nASSETS LOAD... " .. tostring(i)
		task.wait(LOADING_STEP_TIME)
	end

	-- Phase 2
	dbg("LOADING", "Phase 2: LOADING . . .")
	statusLabel.Text = "LOADING . . ."
	task.wait(LOADING_PHASE2_HOLD)

	-- Phase 3
	dbg("LOADING", "Phase 3: COMPLETED")
	statusLabel.Text = "COMPLETED"
	task.wait(LOADING_PHASE3_HOLD)

	ensureStartBackgroundNPC().Value = true

	-- Fade out (non-blocking — function returns immediately so the caller can
	-- start the camera intro in parallel with the fade).
	dbg("LOADING", "Starting slow fade out (non-blocking, " .. LOADING_FADE_TIME .. "s)")
	local info = TweenInfo.new(LOADING_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	TweenService:Create(bg,          info, {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
	TweenService:Create(repLogo,     info, {ImageTransparency = 1}):Play()
	TweenService:Create(statusLabel, info, {TextTransparency = 1}):Play()

	task.delay(LOADING_FADE_TIME + 0.1, function()
		if rotConn then rotConn:Disconnect() end
		if screenGui and screenGui.Parent then screenGui:Destroy() end
		dbg("LOADING", "Loading screen destroyed (fade complete)")
	end)
end

-- ============================================================================
-- PHASE 1 – Resolve workspace references (after loading screen is gone)
-- ============================================================================
local Camera = workspace.CurrentCamera

-- These WaitForChild calls block; safe to run after loading screen is shown
local function resolveWorkspace()
	dbg("REFS", "Waiting for MainMenuWorkspace...")
	local MMWorkspace  = workspace:WaitForChild("MainMenuWorkspace", 30)
	if not MMWorkspace then dbgErr("REFS", "MainMenuWorkspace not found!") return nil end
	dbg("REFS", "MainMenuWorkspace OK")

	local CameraFolder = MMWorkspace:WaitForChild("Camera", 10)
	if not CameraFolder then dbgErr("REFS", "Camera folder not found!") return nil end
	dbg("REFS", "Camera folder OK")

	local StartCamPart = CameraFolder:WaitForChild("StartCam", 10)
	local EndCamPart   = CameraFolder:WaitForChild("EndCam",   10)
	if not StartCamPart then dbgErr("REFS", "StartCam not found!") end
	if not EndCamPart   then dbgErr("REFS", "EndCam not found!")   end
	dbg("REFS", "StartCam=" .. tostring(StartCamPart) .. " EndCam=" .. tostring(EndCamPart))

	local UIFolder = MMWorkspace:WaitForChild("UI", 10)
	if not UIFolder then dbgErr("REFS", "UI folder not found!") end
	dbg("REFS", "UI folder=" .. tostring(UIFolder))

	return {
		MMWorkspace  = MMWorkspace,
		CameraFolder = CameraFolder,
		StartCamPart = StartCamPart,
		EndCamPart   = EndCamPart,
		UIFolder     = UIFolder,
	}
end

local function resolveMenuGui()
	dbg("REFS", "Resolving MainMenu panels...")
	local MainMenu = script.Parent.Parent
	dbg("REFS", "MainMenu = " .. tostring(MainMenu))

	local function safe(name)
		local v = MainMenu:FindFirstChild(name)
		if v then
			dbg("REFS", name .. " = OK")
		else
			dbgErr("REFS", name .. " NOT FOUND in MainMenu")
		end
		return v
	end

	local Play          = safe("Play")
	local Credits       = safe("Credits")
	local Shop          = safe("Shop")
	local SettingsFrame = safe("Settings")
	local Home          = MainMenu:FindFirstChild("Home")
	if Home then
		Home.Visible = false
		dbg("REFS", "Home hidden (replaced by workspace buttons)")
	else
		dbg("REFS", "Home not present (expected if already removed)")
	end

	return MainMenu, Play, Credits, Shop, SettingsFrame
end

local function resolveGameSelect()
	dbg("REFS", "Waiting for GameSelectUI...")
	local gsu = PlayerGui:WaitForChild("GameSelectUI", 30)
	if not gsu then dbgErr("REFS", "GameSelectUI not found!") return nil, nil, nil end
	dbg("REFS", "GameSelectUI OK")
	local gs = gsu:WaitForChild("GameSelect", 10)
	if not gs then dbgErr("REFS", "GameSelect not found!") return gsu, nil, nil end
	local gmf = gs:WaitForChild("MainFrame", 10)
	if not gmf then dbgErr("REFS", "GameSelect.MainFrame not found!") end
	dbg("REFS", "GameSelect refs OK")
	return gsu, gs, gmf
end

local function resolveSettings()
	dbg("REFS", "Loading SettingsModule...")
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("MainMenuRP", 10):WaitForChild("Settings", 10))
	end)
	if ok then
		dbg("REFS", "SettingsModule loaded OK")
		return mod
	else
		dbgErr("REFS", "SettingsModule failed: " .. tostring(mod))
		return nil
	end
end

local function resolveRemotes()
	dbg("REFS", "Waiting for Remotes...")
	local ok, root = pcall(function()
		return ReplicatedStorage:WaitForChild("MainMenuRP", 10):WaitForChild("Remotes", 10)
	end)
	if not ok or not root then dbgErr("REFS", "Remotes root not found") return nil end

	local function r(name)
		local v = root:WaitForChild(name, 10)
		if v then dbg("REFS", "Remote " .. name .. " OK") else dbgErr("REFS", "Remote " .. name .. " MISSING") end
		return v
	end

	return {
		MorphPlr  = r("MorphPlr"),
		MorphPlrG = r("MorphPlrG"),
		VoteMap   = r("VoteMap"),
		VoteUpdate= r("VoteUpdate"),
		StartVoting = r("StartVoting"),
		MapSelected = r("MapSelected"),
	}
end

local function resolveRaidIntroRefs()
	dbg("REFS", "Resolving raid intro refs (DeactivateUI / IntroSound)...")
	local mm = ReplicatedStorage:WaitForChild("MainMenuRP", 10)
	if not mm then dbgErr("REFS", "MainMenuRP missing for raid refs") return nil end
	local deact = mm:WaitForChild("DeactivateUI", 10)
	local sound = mm:WaitForChild("IntroSound", 10)
	if not deact then dbgErr("REFS", "DeactivateUI BoolValue missing") end
	if not sound then dbgErr("REFS", "IntroSound missing") end
	if not (deact and sound) then return nil end
	return { DeactivateUI = deact, IntroSound = sound }
end

-- ============================================================================
-- UNIFIED CAMERA LOOP (intro lerp + idle wobble + mouse parallax)
-- The intro and idle FX run in the SAME RenderStepped loop, so wobble and
-- mouse parallax are visible from the very first frame of the intro — no
-- perceived delay when the camera arrives at EndPos.
-- ============================================================================
local cameraConn
local cameraIntroDone = false

local function quintEaseOut(t)
	local k = 1 - t
	return 1 - k * k * k * k * k
end

local function startCameraLoop(StartCamPart, EndCamPart, doIntro)
	dbg("CAM", "Starting unified camera loop (intro=" .. tostring(doIntro) .. ")")

	local dof = Lighting:FindFirstChild("MenuDOF")
	if not dof then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "MenuDOF"
		dof.Parent = Lighting
	end
	dof.FocusDistance = DOF_FOCUS_DISTANCE
	dof.InFocusRadius = DOF_IN_FOCUS_RADIUS
	dof.FarIntensity  = DOF_FAR_INTENSITY
	dof.NearIntensity = DOF_NEAR_INTENSITY
	dof.Enabled = true

	if cameraConn then cameraConn:Disconnect() end
	Camera.CameraType = Enum.CameraType.Scriptable

	local startCF = StartCamPart.CFrame
	local endCF   = EndCamPart.CFrame
	local t0 = tick()
	cameraIntroDone = not doIntro

	local function readMouseTarget()
		local vp = Camera.ViewportSize
		local mp = UserInputService:GetMouseLocation()
		local nx = math.clamp((mp.X / math.max(vp.X, 1)) - 0.5, -0.5, 0.5) * 2
		local ny = math.clamp((mp.Y / math.max(vp.Y, 1)) - 0.5, -0.5, 0.5) * 2
		return -nx * math.rad(MOUSE_MAX_DEG), -ny * math.rad(MOUSE_MAX_DEG * 0.6)
	end
	local mX, mY = readMouseTarget()

	cameraConn = RunService.RenderStepped:Connect(function(dt)
		local t = tick() - t0

		-- Base CFrame: during intro lerps from StartCam to EndCam, then stays at EndCam
		local baseCFrame
		if doIntro and t < CAM_INTRO_TIME then
			local p = quintEaseOut(t / CAM_INTRO_TIME)
			baseCFrame = startCF:Lerp(endCF, p)
		else
			if doIntro and not cameraIntroDone then
				cameraIntroDone = true
				dbg("CAM", "Intro lerp finished")
			end
			baseCFrame = endCF
		end

		-- Wobble (always on, very subtle)
		local wobblePos = Vector3.new(
			math.sin(t * WOBBLE_FREQ_POS * math.pi * 2) * WOBBLE_AMP_POS,
			math.sin(t * WOBBLE_FREQ_POS * 0.7 * math.pi * 2) * WOBBLE_AMP_POS * 0.5,
			math.cos(t * WOBBLE_FREQ_POS * 0.9 * math.pi * 2) * WOBBLE_AMP_POS * 0.3
		)
		local wRotY = math.sin(t * WOBBLE_FREQ_ROT * math.pi * 2) * math.rad(WOBBLE_AMP_ROT_DEG)
		local wRotX = math.cos(t * WOBBLE_FREQ_ROT * 0.8 * math.pi * 2) * math.rad(WOBBLE_AMP_ROT_DEG * 0.6)

		-- Mouse parallax (always on)
		local targetMX, targetMY = readMouseTarget()
		local a = math.clamp(MOUSE_LERP_SPEED * dt, 0, 1)
		mX = mX + (targetMX - mX) * a
		mY = mY + (targetMY - mY) * a

		Camera.CFrame = baseCFrame
			* CFrame.new(wobblePos)
			* CFrame.Angles(wRotX + mY, wRotY + mX, 0)
	end)
end

-- Back-compat shims (used by lifecycle handlers below)
local function playCameraIntro(StartCamPart, EndCamPart)
	startCameraLoop(StartCamPart, EndCamPart, true)
	-- Block until intro is done so callers preserve their sequencing
	while not cameraIntroDone do task.wait() end
end

local function startMenuIdleCamera(EndCamPart)
	-- Re-entry from respawn: skip intro, jump straight to idle around EndCam
	startCameraLoop(EndCamPart, EndCamPart, false)
end

local function stopMenuIdleCamera()
	if cameraConn then cameraConn:Disconnect() cameraConn = nil end
	local dof = Lighting:FindFirstChild("MenuDOF")
	if dof then dof.Enabled = false end
end

local function resetCameraToPlayer()
	stopMenuIdleCamera()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if hum then
		Camera.CameraType    = Enum.CameraType.Custom
		Camera.CameraSubject = hum
	end
end

-- ============================================================================
-- WORKSPACE 3D BUTTONS
-- ============================================================================
local buttons = {}
local activeButton = nil
local buttonsLocked = true

local function setButtonInteractive(btnData, on)
	if btnData and btnData.clickDetector then
		btnData.clickDetector.MaxActivationDistance = (on and not buttonsLocked) and BUTTON_CLICK_DISTANCE or 0
	end
end

local function setButtonVisible(btnData, visible)
	if not btnData then return end
	if btnData.billboard then btnData.billboard.Enabled = visible end
	setButtonInteractive(btnData, visible)
end

local function tweenButtonTo(btnData, targetCFrame)
	if not (btnData and btnData.part) then return end
	local tw = TweenService:Create(
		btnData.part,
		TweenInfo.new(BUTTON_TWEEN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{CFrame = targetCFrame}
	)
	tw:Play()
	return tw
end

local panelHomePos = {}

local function slidePanelIn(panel)
	if not panel then return end
	panel.Visible = true
	local target = panelHomePos[panel] or panel.Position
	-- Start off-screen RIGHT and slide in to home position
	panel.Position = UDim2.new(target.X.Scale + 1.2, target.X.Offset, target.Y.Scale, target.Y.Offset)
	TweenService:Create(panel,
		TweenInfo.new(PANEL_SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Position = target}
	):Play()
end

local function slidePanelOut(panel)
	if not panel then return end
	local home = panelHomePos[panel] or panel.Position
	-- Slide off-screen to the RIGHT
	local off  = UDim2.new(home.X.Scale + 1.2, home.X.Offset, home.Y.Scale, home.Y.Offset)
	local tw = TweenService:Create(panel,
		TweenInfo.new(PANEL_SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{Position = off}
	)
	tw:Play()
	tw.Completed:Connect(function()
		panel.Visible = false
		panel.Position = home
	end)
end

local function showOldStyleNotification(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title    = title,
			Text     = text,
			Duration = 5,
		})
	end)
end

local function getMainGroupRank(settingsModule)
	local mg = settingsModule.MainGroup
	if not (mg and mg.id) then return 0 end
	local ok, rank = pcall(function() return LocalPlayer:GetRankInGroup(mg.id) end)
	return (ok and rank) or 0
end

local function handlePlayVenator(settingsModule)
	local rank = getMainGroupRank(settingsModule)
	dbg("VENATOR", "Player rank: " .. tostring(rank) .. " required: " .. tostring(VENATOR_MIN_RANK))
	if rank >= VENATOR_MIN_RANK then
		if VENATOR_PLACE_ID and VENATOR_PLACE_ID > 0 then
			TeleportService:Teleport(VENATOR_PLACE_ID, LocalPlayer)
		else
			dbgErr("VENATOR", "VENATOR_PLACE_ID is 0 – not teleporting")
			showOldStyleNotification("Venator", "Destination not configured yet.")
		end
	else
		showOldStyleNotification(
			"Access Denied",
			"You must be at least E2 to go directly to the Venator. Otherwise, board through the ship."
		)
	end
end

local function setPlayVenatorBillboardVisible(visible)
	-- Hide/show PlayVenator's billboard alongside the main 4 buttons.
	local pvData = buttons.__PlayVenator
	if pvData and pvData.billboard then
		pvData.billboard.Enabled = visible
	end
	if pvData and pvData.clickDetector then
		pvData.clickDetector.MaxActivationDistance =
			(visible and not buttonsLocked) and BUTTON_CLICK_DISTANCE or 0
	end
end

local openButtonDebounce = false
local function openButton(name, PANELS)
	-- Debounce: ClickDetector + nested TextButton may fire twice for the same click
	if openButtonDebounce then
		dbg("BUTTON", "openButton " .. name .. " ignored (debounce)")
		return
	end
	openButtonDebounce = true
	task.delay(0.30, function() openButtonDebounce = false end)

	dbg("BUTTON", "openButton: " .. name)
	local btnData = buttons[name]
	if not btnData then return end

	if activeButton == name then
		-- Toggle close: panel slides out FIRST, then button returns to start
		local capturedName = name
		slidePanelOut(btnData.panel)
		activeButton = nil
		task.delay(PANEL_SLIDE_TIME + BUTTON_PANEL_GAP, function()
			tweenButtonTo(btnData, BUTTON_POS[capturedName].Start)
			for _, other in ipairs(BUTTON_NAMES) do
				if other ~= capturedName then setButtonVisible(buttons[other], true) end
			end
			setPlayVenatorBillboardVisible(true)
		end)
		return
	end

	-- Closing previously-active panel (different button clicked):
	-- slide it out, return its button to start. Then proceed with new button.
	local switchDelay = 0
	if activeButton then
		local prev = buttons[activeButton]
		local prevName = activeButton
		if prev then
			slidePanelOut(prev.panel)
			task.delay(PANEL_SLIDE_TIME, function()
				tweenButtonTo(prev, BUTTON_POS[prevName].Start)
			end)
			switchDelay = PANEL_SLIDE_TIME + BUTTON_TWEEN_TIME + BUTTON_PANEL_GAP
		end
		activeButton = nil
	end

	activeButton = name
	local capturedName = name

	task.delay(switchDelay, function()
		if activeButton ~= capturedName then return end

		-- Hide everyone except the clicked one (including PlayVenator)
		for _, other in ipairs(BUTTON_NAMES) do
			if other ~= capturedName then setButtonVisible(buttons[other], false) end
		end
		setPlayVenatorBillboardVisible(false)

		tweenButtonTo(btnData, BUTTON_POS[capturedName].End)

		-- Slide panel in AFTER the button finishes its move (sequential, no overlap)
		task.delay(BUTTON_TWEEN_TIME + BUTTON_PANEL_GAP, function()
			if activeButton == capturedName then
				slidePanelIn(btnData.panel)
			end
		end)
	end)
end

local function unlockAllButtons()
	dbg("BUTTON", "Unlocking all buttons")
	buttonsLocked = false
	for _, name in ipairs(BUTTON_NAMES) do
		local d = buttons[name]
		if d and d.clickDetector then d.clickDetector.MaxActivationDistance = BUTTON_CLICK_DISTANCE end
	end
	local pv = buttons.__PlayVenator
	if pv and pv.clickDetector then pv.clickDetector.MaxActivationDistance = BUTTON_CLICK_DISTANCE end
end

local function lockAllButtons()
	buttonsLocked = true
	for _, name in ipairs(BUTTON_NAMES) do
		local d = buttons[name]
		if d and d.clickDetector then d.clickDetector.MaxActivationDistance = 0 end
	end
	local pv = buttons.__PlayVenator
	if pv and pv.clickDetector then pv.clickDetector.MaxActivationDistance = 0 end
end

local function resetButtonsToStart(PANELS)
	dbg("BUTTON", "Resetting buttons to start positions")
	activeButton = nil
	for _, name in ipairs(BUTTON_NAMES) do
		local d = buttons[name]
		if d and d.part and d.part:IsA("BasePart") then
			d.part.CFrame = BUTTON_POS[name].Start
		end
		if d then setButtonVisible(d, true) end
	end
	setPlayVenatorBillboardVisible(true)
	if PANELS then
		for _, panel in pairs(PANELS) do
			panel.Visible = false
			if panelHomePos[panel] then panel.Position = panelHomePos[panel] end
		end
	end
end

local function setupWorkspaceButtons(UIFolder, PANELS, settingsModule)
	dbg("BUTTON", "Setting up workspace buttons in: " .. tostring(UIFolder))
	for _, name in ipairs(BUTTON_NAMES) do
		local part = UIFolder:FindFirstChild(name)
		if not part then
			dbgErr("BUTTON", "Missing workspace button: " .. name)
			continue
		end
		dbg("BUTTON", "Found part: " .. name)

		local cd = part:FindFirstChildWhichIsA("ClickDetector")
		local bb = part:FindFirstChild("MainBillboard")
		dbg("BUTTON", name .. " -> ClickDetector=" .. tostring(cd) .. " MainBillboard=" .. tostring(bb))

		if part:IsA("BasePart") then
			part.Anchored = true
			part.CFrame = BUTTON_POS[name].Start
		end

		local data = {
			part          = part,
			clickDetector = cd,
			billboard     = bb,
			panel         = PANELS[name],
		}
		buttons[name] = data

		if cd then
			cd.MaxActivationDistance = 0
			local capturedName = name
			cd.MouseClick:Connect(function()
				if buttonsLocked then
					dbg("BUTTON", capturedName .. " clicked but locked")
					return
				end
				openButton(capturedName, PANELS)
			end)
		else
			dbgErr("BUTTON", "No ClickDetector on " .. name .. " – clicks won't work")
		end
	end

	-- PlayVenator (child of PlayButton)
	local playPart = buttons.PlayButton and buttons.PlayButton.part
	if playPart then
		local pv = playPart:FindFirstChild("PlayVenator")
		if pv then
			dbg("BUTTON", "PlayVenator found")
			local cd = pv:FindFirstChildWhichIsA("ClickDetector")
			local bb = pv:FindFirstChild("MainBillboard")
			if cd then
				cd.MaxActivationDistance = 0
				cd.MouseClick:Connect(function()
					if buttonsLocked then return end
					handlePlayVenator(settingsModule)
				end)
				buttons.__PlayVenator = { clickDetector = cd, billboard = bb, part = pv }
			else
				dbgErr("BUTTON", "PlayVenator has no ClickDetector")
			end
		else
			dbg("BUTTON", "PlayVenator child not found under PlayButton (ok if not set up yet)")
		end
	end
end

-- ============================================================================
-- BLACK SCREEN WIPE (preserved)
-- ============================================================================
local TransitionGui, BlackFrame
local function ensureTransitionGui()
	if TransitionGui and TransitionGui.Parent then return end
	TransitionGui = PlayerGui:FindFirstChild("TransitionGui")
	if not TransitionGui then
		TransitionGui = Instance.new("ScreenGui")
		TransitionGui.Name = "TransitionGui"
		TransitionGui.DisplayOrder = 9999
		TransitionGui.IgnoreGuiInset = true
		TransitionGui.ResetOnSpawn = false
		TransitionGui.Parent = PlayerGui
	end
	BlackFrame = TransitionGui:FindFirstChild("BlackFade")
	if not BlackFrame then
		BlackFrame = Instance.new("Frame")
		BlackFrame.Name = "BlackFade"
		BlackFrame.Size = UDim2.new(1, 0, 1, 0)
		BlackFrame.Position = UDim2.new(1, 0, 0, 0)
		BlackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
		BlackFrame.ZIndex = 10
		BlackFrame.Parent = TransitionGui
	end
end

local function tweenWipe(targetPos, dur)
	ensureTransitionGui()
	BlackFrame.BackgroundTransparency = 0
	local tw = TweenService:Create(BlackFrame,
		TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{Position = targetPos})
	tw:Play()
	return tw
end

-- ============================================================================
-- RAID INTRO FLOW (post-team-select)
--   Reuses the BlackFrame as the loading overlay. Owns the camera and music
--   transitions so they cannot race the menu's own handlers.
-- ============================================================================
local raidRefs        -- resolved during boot
local raidIntroActive = false  -- suppresses the lifecycle's resetCameraToPlayer

-- Forward-declare wsRefs so fadeScreenAndSpawn can see it (its `local`
-- declaration further down in the boot section will reuse this binding).
local wsRefs
local wsRefsReady = false
-- Forward-declare stopMusic (defined later in the boot section) so the
-- raid intro flow can fade music out without resolving it as a global.
local stopMusic = function() end

local function freezeLocalCharacter()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local saved = {
		WalkSpeed  = hum.WalkSpeed,
		JumpPower  = hum.JumpPower,
		JumpHeight = hum.JumpHeight,
		AutoRotate = hum.AutoRotate,
	}
	hum.WalkSpeed  = 0
	hum.JumpPower  = 0
	hum.JumpHeight = 0
	hum.AutoRotate = false
	return { humanoid = hum, saved = saved }
end

local function unfreezeLocalCharacter(freezeState)
	if not freezeState then return end
	local hum, saved = freezeState.humanoid, freezeState.saved
	if not (hum and hum.Parent and saved) then return end
	hum.WalkSpeed  = saved.WalkSpeed
	hum.JumpPower  = saved.JumpPower
	hum.JumpHeight = saved.JumpHeight
	hum.AutoRotate = saved.AutoRotate
end

local function resolveSoundDuration(sound)
	if sound.TimeLength and sound.TimeLength > 0 then return sound.TimeLength end
	pcall(function() ContentProvider:PreloadAsync({ sound }) end)
	local elapsed = 0
	while elapsed < RAID_PRELOAD_TIMEOUT and (not sound.TimeLength or sound.TimeLength <= 0) do
		task.wait(0.1); elapsed += 0.1
	end
	return (sound.TimeLength and sound.TimeLength > 0) and sound.TimeLength or RAID_FALLBACK_TIME
end

local function computePlayerCameraCFrame()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local head = char:FindFirstChild("Head")
		or char:FindFirstChild("HumanoidRootPart")
		or char:WaitForChild("HumanoidRootPart", 5)
	if not head then return Camera.CFrame end
	local subjectPos = head.Position
	local backDir    = -head.CFrame.LookVector
	local camPos     = subjectPos + backDir * 12 + Vector3.new(0, 2, 0)
	return CFrame.lookAt(camPos, subjectPos)
end

-- Triggers the raid intro from any state (boot with DeactivateUI=true, or
-- mid-menu when DeactivateUI flips). Disables menu music + menu camera,
-- parks camera on StartCam, freezes the player, plays IntroSound while
-- tweening camera StartCam -> player camera over the sound's full length,
-- then hands camera back and reveals RaidUI.
--
-- NOTE: this function does NOT fade any overlay; the caller is responsible
-- for whatever transition leads into it (the boot loading-screen fade, or
-- a quick black wipe from the menu).
local function triggerRaidIntro()
	if raidIntroActive or _G.__RaidIntroPlayed then return end
	if not (wsRefs and wsRefs.StartCamPart and raidRefs and raidRefs.IntroSound) then
		dbgErr("RAID", "Cannot start raid intro – missing wsRefs.StartCamPart or raidRefs")
		return
	end
	raidIntroActive = true
	_G.__RaidIntroPlayed = true
	dbg("RAID", "Starting raid intro (StartCam -> player camera)")

	-- Kill the menu music if it's playing.
	stopMusic()

	-- Stop menu camera idle loop, lock buttons, park camera on StartCam.
	stopMenuIdleCamera()
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame     = wsRefs.StartCamPart.CFrame

	-- Hide menu UI for the duration of the raid intro and beyond. The
	-- lifecycle handler will skip resetCameraToPlayer because
	-- raidIntroActive is true.
	local mmGui = script.Parent and script.Parent.Parent
	if mmGui and mmGui:IsA("ScreenGui") and mmGui.Enabled then
		mmGui.Enabled = false
	end

	-- Freeze the player so they can't move during the cinematic.
	local freezeState = freezeLocalCharacter()

	-- Preload audio and resolve its length.
	local introSound  = raidRefs.IntroSound:Clone()
	introSound.Name   = "IntroSound_Active"
	introSound.Parent = workspace
	local duration    = resolveSoundDuration(introSound)

	-- Sample camera endpoint once (player is frozen).
	local startCF = wsRefs.StartCamPart.CFrame
	local endCF   = computePlayerCameraCFrame()

	-- Audio + camera tween start together.
	introSound:Play()

	local t0   = tick()
	local done = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = tick() - t0
		local p = math.clamp(t / duration, 0, 1)
		Camera.CFrame = startCF:Lerp(endCF, quintEaseOut(p))
		if p >= 1 and not done then
			done = true
			conn:Disconnect()
		end
	end)
	while not done do task.wait() end

	-- Hand camera control back to the player.
	local char = LocalPlayer.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		Camera.CameraType    = Enum.CameraType.Custom
		Camera.CameraSubject = hum
	end

	unfreezeLocalCharacter(freezeState)

	-- Reveal RaidUI if it exists.
	local raidUI = PlayerGui:FindFirstChild("RaidUI")
	if raidUI and raidUI:IsA("ScreenGui") then
		raidUI.Enabled = true
	end

	task.delay(0.5, function() if introSound then introSound:Destroy() end end)
	raidIntroActive = false
end

local function fadeScreenAndSpawn(MainMenu, remoteCall)
	ensureTransitionGui()
	local outTw = tweenWipe(UDim2.new(0, 0, 0, 0), SCREEN_WIPE_TIME)
	outTw.Completed:Wait()
	remoteCall()
	task.wait(WIPE_STAY_TIME)
	resetCameraToPlayer()
	MainMenu.Enabled = false
	local inTw = tweenWipe(UDim2.new(1, 0, 0, 0), SCREEN_WIPE_TIME)
	inTw.Completed:Wait()
end

-- ============================================================================
-- LEGACY UTILITIES (gradient / image / selection / lock overlay)
-- ============================================================================
local function normalizeToColorSequence(source)
	if not source then return nil end
	local t = typeof(source)
	if t == "ColorSequence" then return source
	elseif t == "Color3" then return ColorSequence.new(source)
	elseif t == "table" then
		local r = source.R or source.r
		local g = source.G or source.g
		local b = source.B or source.b
		if r and g and b then return ColorSequence.new(Color3.fromRGB(r, g, b)) end
		if source.Keypoints then
			local ok, seq = pcall(function() return ColorSequence.new(source.Keypoints) end)
			if ok then return seq end
		end
	elseif t == "string" then
		local hex = source:match("^#(%x%x%x%x%x%x)$")
		if hex then
			return ColorSequence.new(Color3.fromRGB(
				tonumber(hex:sub(1, 2), 16),
				tonumber(hex:sub(3, 4), 16),
				tonumber(hex:sub(5, 6), 16)
				))
		end
	end
	return nil
end

local function applyGradientColor(templateClone, colorSource)
	local seq = normalizeToColorSequence(colorSource)
	if not seq then return end
	local gradient = templateClone:FindFirstChild("TeamGradient", true)
	if gradient and gradient:IsA("UIGradient") then gradient.Color = seq end
end

local function getPreferredImageId(entry)
	if not entry then return nil end
	return entry.Image or entry.image or entry.ImageId or entry.imageId
		or entry.ImageID or entry.customImageID or entry.icon
end

local function setDivImage(templateClone, imageIdOrUrl)
	if not imageIdOrUrl then return end
	local divImage = templateClone:FindFirstChild("DivImage", true)
	if not divImage or not divImage:IsA("ImageLabel") then return end
	if tostring(imageIdOrUrl):match("^https?://") then
		divImage.Image = imageIdOrUrl
	else
		local numeric = tonumber(imageIdOrUrl)
		if numeric then
			divImage.Image = "rbxassetid://" .. numeric
		elseif tostring(imageIdOrUrl):match("^rbxassetid://") then
			divImage.Image = imageIdOrUrl
		end
	end
end

local function setStrokeColor(button, color)
	if not button then return end
	local stroke = button:FindFirstChildWhichIsA("UIStroke", true)
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = button
	end
	stroke.Color = color
end

local function createSelectionController(buttonsList, options)
	options = options or {}
	local current
	local strokeInactive = options.strokeInactive or Color3.fromRGB(130, 130, 130)
	local strokeActive   = options.strokeActive   or Color3.new(1, 1, 1)
	local scale          = options.scale or 1.08
	local useStroke      = options.useStroke
	local origSizes = {}
	for _, b in ipairs(buttonsList) do
		origSizes[b] = b.Size
		if useStroke then setStrokeColor(b, strokeInactive) end
	end
	local function apply(btn, selected)
		local base = origSizes[btn]
		if not base then return end
		local target = selected
			and UDim2.new(base.X.Scale * scale, base.X.Offset, base.Y.Scale * scale, base.Y.Offset)
			or base
		TweenService:Create(btn,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = target}):Play()
		if useStroke then
			setStrokeColor(btn, selected and strokeActive or strokeInactive)
		end
	end
	return function(btn)
		if current == btn then return end
		for _, b in ipairs(buttonsList) do apply(b, b == btn) end
		current = btn
		return btn
	end
end

local function safeGetGroupIcon(groupId)
	if type(groupId) ~= "number" then return nil end
	local ok, info = pcall(function() return GroupService:GetGroupInfoAsync(groupId) end)
	if ok and info and info.EmblemUrl then return info.EmblemUrl end
	return nil
end

local function addLockOverlay(button)
	if button:FindFirstChild("LockOverlay") then return end
	local lock = Instance.new("ImageLabel")
	lock.Name = "LockOverlay"
	lock.Size = UDim2.new(0, 40, 0, 40)
	lock.Position = UDim2.new(0.5, -20, 0.5, -20)
	lock.BackgroundTransparency = 1
	lock.Image = "rbxassetid://6031071053"
	lock.ImageColor3 = Color3.fromRGB(200, 200, 200)
	lock.ZIndex = button.ZIndex + 10
	lock.Parent = button
	local overlay = Instance.new("Frame")
	overlay.Name = "LockDarkOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex = button.ZIndex + 5
	overlay.Parent = button
	local corner = button:FindFirstChildWhichIsA("UICorner")
	if corner then corner:Clone().Parent = overlay end
end

local clickDebounce = false
local function withDebounce(fn)
	return function(...)
		if clickDebounce then return end
		clickDebounce = true
		local ok, err = pcall(fn, ...)
		if not ok then dbgErr("CLICK", tostring(err)) end
		task.delay(0.25, function() clickDebounce = false end)
	end
end

-- ============================================================================
-- LEGACY: Play tabs / Credits / Shop / Teams / Voting
-- ============================================================================
local function setupPlayTabs(Play)
	dbg("SETUP", "Setting up Play tabs")
	local playTabs = { Play.Gamepasses, Play.Teams }
	local selectPlayTab = createSelectionController(playTabs, {
		scale = 1.10, useStroke = true,
		strokeInactive = Color3.fromRGB(120, 120, 120),
		strokeActive   = Color3.fromRGB(255, 255, 255),
	})
	Play.Gamepasses.MouseButton1Click:Connect(function()
		Play.GamepassesFrame.Visible = true
		Play.TeamsFrame.Visible      = false
		selectPlayTab(Play.Gamepasses)
	end)
	Play.Teams.MouseButton1Click:Connect(function()
		Play.GamepassesFrame.Visible = false
		Play.TeamsFrame.Visible      = true
		selectPlayTab(Play.Teams)
	end)
	Play.GamepassesFrame.Visible = false
	Play.TeamsFrame.Visible      = true
end

local function populateCredits(Credits, settingsModule)
	dbg("SETUP", "Populating credits")
	local template = Credits:WaitForChild("GamepassesFrame"):WaitForChild("Template")
	for username, role in pairs(settingsModule.Credits or {}) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent  = template.Parent
		clone.Text    = "@" .. username .. " - " .. role
	end
end

local function populateShop(Shop, settingsModule)
	dbg("SETUP", "Populating shop")
	local template = Shop.GamepassesFrame:WaitForChild("Template")
	for name, item in pairs(settingsModule.GamepassItems or {}) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent  = template.Parent
		clone.GTitle.Text = item.Title or name
		clone.GDesc.Text  = item.Description or "N/A"
		clone.GPrice.Text = "R$ " .. tostring(item.Price or 0)
		if clone:FindFirstChild("UIGradient") then
			local seq = normalizeToColorSequence(item.Color)
			if seq then clone.UIGradient.Color = seq end
		end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(item.GamepassId, Enum.InfoType.GamePass)
		end)
		clone.GImage.Image = (ok and info)
			and ("rbxassetid://" .. tostring(info.IconImageAssetId)) or "rbxassetid://0"
		clone.MouseButton1Click:Connect(function()
			MarketplaceService:PromptGamePassPurchase(LocalPlayer, item.GamepassId)
		end)
	end
end

local function populateTeams(Play, MainMenu, RemoteMorphPlr, RemoteMorphPlrG, settingsModule)
	dbg("SETUP", "Populating teams")
	local teamsFrame = Play:WaitForChild("TeamsFrame")
	teamsFrame.Visible = true

	local function createTeamButton(parentFrame, overName, displayName, settingsEntry, onClick, locked)
		local template = parentFrame:WaitForChild("Template")
		local clone    = template:Clone()
		clone.Visible  = true
		clone.Parent   = parentFrame
		clone.OverLbl.Text     = overName or "REGIMENT"
		clone.DisplayName.Text = displayName
		local explicitImage = getPreferredImageId(settingsEntry)
		if not explicitImage and settingsEntry and settingsEntry.id then
			explicitImage = safeGetGroupIcon(settingsEntry.id)
		end
		setDivImage(clone, explicitImage)
		if settingsEntry and settingsEntry.Color then applyGradientColor(clone, settingsEntry.Color) end
		if locked then
			addLockOverlay(clone)
			clone.MouseButton1Click:Connect(function() end)
		else
			clone.MouseButton1Click:Connect(withDebounce(function() onClick(clone) end))
		end
	end

	local mg = settingsModule.MainGroup
	if mg then
		createTeamButton(teamsFrame, mg.mainTeamOverName or mg.teamName, mg.displayName, mg,
			function()
				teamsFrame.Visible = false
				Play.GamepassesFrame.Visible = false
				Play.TeamsFrame.Visible      = false
				fadeScreenAndSpawn(MainMenu, function()
					RemoteMorphPlr:FireServer(mg.displayName, 1)
				end)
			end, false)
	end

	for _, div in pairs(settingsModule.DivisionalGroups or {}) do
		local isInGroup = false
		if div.id then
			local ok, result = pcall(function() return LocalPlayer:IsInGroup(div.id) end)
			if ok then isInGroup = result end
		end
		createTeamButton(teamsFrame,
			div.friendly and (settingsModule.MainGroup and settingsModule.MainGroup.mainTeamOverName or "ALLY") or "REGIMENT",
			div.displayName, div,
			function()
				teamsFrame.Visible = false
				Play.GamepassesFrame.Visible = false
				Play.TeamsFrame.Visible      = false
				fadeScreenAndSpawn(MainMenu, function()
					RemoteMorphPlr:FireServer(div.displayName, 1)
				end)
			end, not isInGroup)
	end

	local gpFrame = Play:WaitForChild("GamepassesFrame")
	for _, gp in pairs(settingsModule.Gamepasses or {}) do
		createTeamButton(gpFrame,
			gp.friendly and (settingsModule.MainGroup and settingsModule.MainGroup.mainTeamOverName or "ALLY") or "SPECIAL",
			gp.displayName, gp,
			function()
				local owns = false
				pcall(function()
					owns = MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, gp.GamepassId)
				end)
				teamsFrame.Visible = false
				Play.GamepassesFrame.Visible = false
				Play.TeamsFrame.Visible      = false
				if owns then
					fadeScreenAndSpawn(MainMenu, function()
						RemoteMorphPlrG:FireServer(gp.displayName)
					end)
				else
					MarketplaceService:PromptGamePassPurchase(LocalPlayer, gp.GamepassId)
				end
			end, false)
	end
end

local function setupVoting(GameSelectUI, GameSelect, GameSelectMainFrame, MapTemplate, Remotes)
	dbg("SETUP", "Setting up voting events")
	MapTemplate.Visible = false
	GameSelectUI.Enabled = false
	GameSelect.Visible = true

	local mapButtons = {}
	local currentVote = nil
	local votingCountdownConn = nil

	local function clearMapButtons()
		for _, btn in pairs(mapButtons) do if btn and btn.Parent then btn:Destroy() end end
		mapButtons = {}
		currentVote = nil
	end

	local function updateVoteCounts(counts)
		for i, btn in pairs(mapButtons) do
			local lbl = btn:FindFirstChild("MapVotes")
			if lbl and lbl:IsA("TextLabel") then lbl.Text = tostring(counts[i] or 0) end
		end
	end

	local function highlightSelectedMap(selectedIndex)
		for i, btn in pairs(mapButtons) do
			local stroke = btn:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = (i == selectedIndex) and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(100, 100, 100)
				stroke.Thickness = (i == selectedIndex) and 3 or 1
			end
		end
	end

	Remotes.StartVoting.OnClientEvent:Connect(function(mapList, duration)
		dbg("VOTE", "StartVoting received, maps: " .. tostring(#mapList))
		clearMapButtons()
		GameSelectUI.Enabled = true
		GameSelect.Visible = true
		for _, mapData in ipairs(mapList) do
			local clone = MapTemplate:Clone()
			clone.Visible = true
			clone.Parent = GameSelectMainFrame
			local nl = clone:FindFirstChild("MapName")
			if nl and nl:IsA("TextLabel") then nl.Text = mapData.name end
			local th = clone:FindFirstChild("MapThumbnail")
			if th and th:IsA("ImageLabel") then th.Image = mapData.imageId or "rbxassetid://0" end
			local vl = clone:FindFirstChild("MapVotes")
			if vl and vl:IsA("TextLabel") then vl.Text = "0" end
			local idx = mapData.index
			clone.MouseButton1Click:Connect(function()
				if currentVote == idx then return end
				currentVote = idx
				Remotes.VoteMap:FireServer(idx)
				highlightSelectedMap(idx)
			end)
			mapButtons[idx] = clone
		end
		if votingCountdownConn then votingCountdownConn:Disconnect() votingCountdownConn = nil end
		local endTime = os.clock() + duration
		local timerLabel = GameSelect:FindFirstChild("TimerLabel", true)
		if timerLabel and timerLabel:IsA("TextLabel") then
			votingCountdownConn = RunService.RenderStepped:Connect(function()
				local remaining = math.max(0, math.ceil(endTime - os.clock()))
				timerLabel.Text = tostring(remaining) .. "s"
				if remaining <= 0 and votingCountdownConn then
					votingCountdownConn:Disconnect()
					votingCountdownConn = nil
				end
			end)
		end
	end)

	Remotes.VoteUpdate.OnClientEvent:Connect(function(counts)
		if type(counts) == "table" then updateVoteCounts(counts) end
	end)

	Remotes.MapSelected.OnClientEvent:Connect(function(mapName, placeId)
		dbg("VOTE", "MapSelected: " .. tostring(mapName))
		for _, btn in pairs(mapButtons) do
			local nl = btn:FindFirstChild("MapName")
			if nl and nl:IsA("TextLabel") and nl.Text == mapName then
				local stroke = btn:FindFirstChildWhichIsA("UIStroke")
				if stroke then stroke.Color = Color3.fromRGB(0, 255, 0) stroke.Thickness = 4 end
			end
		end
		if votingCountdownConn then votingCountdownConn:Disconnect() votingCountdownConn = nil end
		local tl = GameSelect:FindFirstChild("TimerLabel", true)
		if tl and tl:IsA("TextLabel") then tl.Text = "Teleporting to " .. mapName .. "..." end
	end)
end

-- ============================================================================
-- BOOT SEQUENCE
-- ============================================================================
dbg("BOOT", "Starting boot sequence")

-- STEP 1: Show loading screen IMMEDIATELY (no blocking calls before this)
local isFirstLoad = not _G.__MainMenuLoadedOnce
dbg("BOOT", "isFirstLoad=" .. tostring(isFirstLoad))

-- ============================================================================
-- MENU MUSIC (owned by this script — independent of MainMenu.Enabled state)
-- Starts at the very first moment the player joins, keeps playing during the
-- loading screen, and resumes when the player returns to the menu.
-- ============================================================================
local MENU_MUSIC_VOLUME = 0.5
local MENU_MUSIC_FADE_STEPS = 30
local MENU_MUSIC_FADE_INTERVAL = 0.05

local menuMusicSound
local menuMusicFadeToken = 0

local function findMenuMusic()
	local mm = script.Parent and script.Parent.Parent
	if not mm then return nil end
	-- Try direct child first, then fall back to deep search (in case the user
	-- has it nested somewhere under MainMenu).
	local s = mm:FindFirstChild("MenuMusic")
	if s and s:IsA("Sound") then return s end
	for _, d in ipairs(mm:GetDescendants()) do
		if d:IsA("Sound") and d.Name == "MenuMusic" then return d end
	end
	return nil
end

local function fadeMusicTo(targetVolume)
	if not menuMusicSound then return end
	menuMusicFadeToken += 1
	local myToken = menuMusicFadeToken
	local startVol = menuMusicSound.Volume
	task.spawn(function()
		for i = 1, MENU_MUSIC_FADE_STEPS do
			if menuMusicFadeToken ~= myToken then return end
			menuMusicSound.Volume = startVol + (targetVolume - startVol) * (i / MENU_MUSIC_FADE_STEPS)
			task.wait(MENU_MUSIC_FADE_INTERVAL)
		end
		if menuMusicFadeToken == myToken then
			menuMusicSound.Volume = targetVolume
		end
	end)
end

local function ensureMusicPlaying()
	if not menuMusicSound then
		menuMusicSound = findMenuMusic()
		if not menuMusicSound then
			dbgErr("MUSIC", "MenuMusic Sound not found under MainMenu — cannot play menu music")
			return
		end
		dbg("MUSIC", "Found MenuMusic Sound: " .. menuMusicSound:GetFullName())
	end
	menuMusicSound.Looped = true
	if not menuMusicSound.IsPlaying then
		menuMusicSound.Volume = 0
		menuMusicSound:Play()
		dbg("MUSIC", "MenuMusic :Play() called")
		fadeMusicTo(MENU_MUSIC_VOLUME)
	end
end

-- Note: stopMusic is forward-declared near the raid intro flow above, so we
-- assign to it here rather than re-declaring (otherwise the early reference
-- in fadeScreenAndSpawn would see a stale no-op).
stopMusic = function()
	if menuMusicSound and menuMusicSound.IsPlaying then
		fadeMusicTo(0)
		local localSound = menuMusicSound
		local tokenAtRequest = menuMusicFadeToken
		task.delay(MENU_MUSIC_FADE_STEPS * MENU_MUSIC_FADE_INTERVAL + 0.1, function()
			if menuMusicFadeToken == tokenAtRequest and localSound then
				localSound:Stop()
			end
		end)
	end
end

-- Resolve raid intro refs NOW so we can decide whether to start the menu
-- music (if DeactivateUI is already true, we want zero menu music).
raidRefs = resolveRaidIntroRefs()
local function isRaidMode()
	return raidRefs and raidRefs.DeactivateUI and raidRefs.DeactivateUI.Value == true
end

-- Make sure MainMenu is enabled so any other UI consumers behave correctly.
-- (When raid mode is active, we leave it disabled — the player should never
-- see the menu UI in that case.)
do
	local mm = script.Parent and script.Parent.Parent
	if mm and mm:IsA("ScreenGui") then
		mm.Enabled = not isRaidMode()
	end
end

-- Kick off menu music NOW (first moment the player enters the game), UNLESS
-- we're in raid mode — the raid intro must run with no background music.
if not isRaidMode() then
	ensureMusicPlaying()
else
	dbg("BOOT", "DeactivateUI = true at boot; skipping menu music")
end

-- ============================================================================
-- UI SOUNDS (hover / click) -- replaces the deleted MenuMusicHandler.lua
-- ============================================================================
local function findUiSound(name)
	local mm = script.Parent and script.Parent.Parent
	if not mm then return nil end
	local s = mm:FindFirstChild(name)
	if s and s:IsA("Sound") then return s end
	for _, d in ipairs(mm:GetDescendants()) do
		if d:IsA("Sound") and d.Name == name then return d end
	end
	return nil
end

local hoverSoundTemplate  = findUiSound("HoverSound")
local selectSoundTemplate = findUiSound("SelectSound")

local function playUiSound(template)
	if not template or not template:IsA("Sound") then return end
	local s = template:Clone()
	s.Parent = template.Parent
	s.Ended:Connect(function() s:Destroy() end)
	s:Play()
end

local function hookUiButton(btn)
	if not btn:IsA("GuiButton") then return end
	btn.MouseEnter:Connect(function() playUiSound(hoverSoundTemplate) end)
	btn.Activated:Connect(function()  playUiSound(selectSoundTemplate) end)
end

do
	local mm = script.Parent and script.Parent.Parent
	if mm then
		for _, d in ipairs(mm:GetDescendants()) do
			if d:IsA("GuiButton") then hookUiButton(d) end
		end
		mm.DescendantAdded:Connect(function(d)
			if d:IsA("GuiButton") then hookUiButton(d) end
		end)
	end
end

-- Workspace resolution runs in PARALLEL with the loading screen so the camera
-- intro can start the instant the loading fade begins (no gap).
-- (wsRefs / wsRefsReady are forward-declared above near the raid intro flow.)
task.spawn(function()
	wsRefs = resolveWorkspace()
	if wsRefs and wsRefs.StartCamPart then
		Camera.CameraType = Enum.CameraType.Scriptable
		Camera.CFrame = wsRefs.StartCamPart.CFrame
		dbg("CAM", "Camera pre-parked on StartCam during loading")
	end
	wsRefsReady = true
end)

if isFirstLoad then
	-- IMPORTANT: set the flag AFTER loading completes, so that if the script
	-- gets killed mid-loading (e.g. respawn with ResetOnSpawn=true) the next
	-- instance will redo the loading screen instead of skipping it.
	runLoadingScreen()   -- returns the moment the fade tween starts (non-blocking fade)
	_G.__MainMenuLoadedOnce = true
	dbg("BOOT", "Loading screen fade started")
else
	dbg("BOOT", "Returning player – skip loading screen")
end

-- Make sure workspace refs are ready before continuing (should already be done
-- by now since we ran it in parallel for the full loading duration).
while not wsRefsReady do task.wait() end

if not wsRefs then
	dbgErr("BOOT", "Failed to resolve workspace – main menu will be limited")
end

-- START CAMERA INTRO IMMEDIATELY (parallel with the loading-screen fade-out
-- AND with the rest of the heavy setup below).
--
-- Two paths depending on DeactivateUI:
--   * isRaidMode() == true  -> after the loading screen finishes fading,
--                              run the raid intro (StartCam -> player camera
--                              synced to IntroSound). NO menu music, NO
--                              StartCam->EndCam menu sweep.
--   * isRaidMode() == false -> normal menu intro (StartCam -> EndCam with
--                              menu music). Also watch DeactivateUI so a
--                              later flip still triggers the raid intro.
if isRaidMode() and wsRefs and wsRefs.StartCamPart then
	-- The loading screen's fade-out is non-blocking, so by the time we get
	-- here `runLoadingScreen()` has just kicked it off. Starting the raid
	-- intro now means the IntroSound + camera tween run *as* the overlay
	-- fades, instead of after a black gap.
	dbg("CAM", "Raid mode active – starting raid intro as loading fade begins")
	task.spawn(triggerRaidIntro)
elseif isFirstLoad and wsRefs and wsRefs.StartCamPart and wsRefs.EndCamPart then
	task.spawn(function()
		dbg("CAM", "Starting camera intro (in parallel with fade and setup)")
		local ok, err = pcall(playCameraIntro, wsRefs.StartCamPart, wsRefs.EndCamPart)
		if not ok then dbgErr("CAM", "playCameraIntro: " .. tostring(err)) end
		dbg("CAM", "Starting idle camera")
		local ok2, err2 = pcall(startMenuIdleCamera, wsRefs.EndCamPart)
		if not ok2 then dbgErr("CAM", "startMenuIdleCamera: " .. tostring(err2)) end
	end)
elseif wsRefs and wsRefs.EndCamPart then
	-- Returning player: skip intro, go straight to idle camera
	task.spawn(function()
		pcall(startMenuIdleCamera, wsRefs.EndCamPart)
	end)
end

-- Watch DeactivateUI so a later flip (after the menu is already showing)
-- also triggers the raid intro instead of leaving the player stuck.
if raidRefs and raidRefs.DeactivateUI then
	raidRefs.DeactivateUI:GetPropertyChangedSignal("Value"):Connect(function()
		if raidRefs.DeactivateUI.Value and not raidIntroActive then
			dbg("RAID", "DeactivateUI flipped to true – running raid intro")
			task.spawn(triggerRaidIntro)
		end
	end)
end

dbg("BOOT", "Resolving GUI references...")
local MainMenu, Play, Credits, Shop, SettingsFrame = resolveMenuGui()

dbg("BOOT", "Building PANELS table...")
local PANELS = {
	PlayButton     = Play,
	ShopButton     = Shop,
	CreditsButton  = Credits,
	SettingsButton = SettingsFrame,
}
for _, panel in pairs(PANELS) do
	if panel then
		panelHomePos[panel] = panel.Position
		panel.Visible = false
	end
end
-- In raid mode the menu must stay hidden; otherwise enable as usual.
if MainMenu then MainMenu.Enabled = not isRaidMode() end

dbg("BOOT", "Resolving GameSelectUI...")
local GameSelectUI, GameSelect, GameSelectMainFrame = resolveGameSelect()

dbg("BOOT", "Resolving Settings and Remotes...")
local SettingsModule = resolveSettings()
local Remotes        = resolveRemotes()

-- STEP 3: Setup gameplay UI
if Play and Credits and Shop and SettingsFrame and SettingsModule then
	local ok, err = pcall(setupPlayTabs, Play)
	if not ok then dbgErr("SETUP", "setupPlayTabs: " .. tostring(err)) end

	ok, err = pcall(populateCredits, Credits, SettingsModule)
	if not ok then dbgErr("SETUP", "populateCredits: " .. tostring(err)) end

	ok, err = pcall(populateShop, Shop, SettingsModule)
	if not ok then dbgErr("SETUP", "populateShop: " .. tostring(err)) end

	if Remotes then
		ok, err = pcall(populateTeams, Play, MainMenu, Remotes.MorphPlr, Remotes.MorphPlrG, SettingsModule)
		if not ok then dbgErr("SETUP", "populateTeams: " .. tostring(err)) end
	end
end

if GameSelectUI and GameSelect and GameSelectMainFrame and Remotes then
	local mt = GameSelectMainFrame:FindFirstChild("MapTemplate")
	if mt then
		local ok, err = pcall(setupVoting, GameSelectUI, GameSelect, GameSelectMainFrame, mt, Remotes)
		if not ok then dbgErr("SETUP", "setupVoting: " .. tostring(err)) end
	else
		dbgErr("SETUP", "MapTemplate not found")
	end
end

-- STEP 4: Workspace 3D buttons
if wsRefs and wsRefs.UIFolder then
	local ok, err = pcall(setupWorkspaceButtons, wsRefs.UIFolder, PANELS, SettingsModule)
	if not ok then dbgErr("SETUP", "setupWorkspaceButtons: " .. tostring(err)) end
end

-- STEP 5: Camera intro already kicked off above (in parallel with this setup)

-- STEP 6: Unlock buttons (player can click them immediately; the intro tween
-- continues independently)
unlockAllButtons()
dbg("BOOT", "Buttons unlocked – menu ready")

-- STEP 7: Lifecycle (respawn)
if MainMenu then
	MainMenu:GetPropertyChangedSignal("Enabled"):Connect(function()
		if MainMenu.Enabled then
			dbg("LIFECYCLE", "MainMenu re-enabled – restoring menu state")
			resetButtonsToStart(PANELS)
			if wsRefs and wsRefs.EndCamPart then
				startMenuIdleCamera(wsRefs.EndCamPart)
			end
			unlockAllButtons()
			ensureMusicPlaying() -- resume music when back in menu
		else
			dbg("LIFECYCLE", "MainMenu disabled")
			lockAllButtons()
			-- During the raid intro, fadeScreenAndSpawn owns the camera
			-- (parked on StartCam under the black overlay). Resetting it
			-- here would yank the camera back to the player mid-intro.
			if not raidIntroActive then
				resetCameraToPlayer()
			end
			stopMusic() -- fade out when leaving menu
		end
	end)
end

dbg("BOOT", "=== Boot complete ===")