-- ShipClient.lua
-- Posizione: StarterPlayer/StarterPlayerScripts/ShipClient
--
-- Controller di volo a DUE FASI per nave pesante (ARC-170).
--
--   FASE A - HANGAR / CRUISE  (stato di avvio di default)
--     * Ali chiuse, trail wingtip OFF, armi DISABILITATE.
--     * Velocita' massima bassa (HANGAR_SPEED) per manovrare in hangar.
--     * W/S = accelera/frena lungo il muso. A/D = virata piatta (yaw).
--     * Mouse NON sterza: camera orbita liberamente attorno alla nave (free look).
--
--   FASE B - COMBAT / THROTTLE  (premi N)
--     * Ali aperte in X, trail wingtip ON, armi abilitate, velocita' piena.
--     * Volo guidato dal mouse tramite crosshair virtuale su schermo.
--     * Auto-banking proporzionale alla velocita' di virata.
--     * Deriva inerziale: la velocita' insegue il muso (peso di un heavy fighter).
--     * Camera bloccata dietro la nave; C attiva free-look orbitale.
--     * Niente roll manuale (Q/E rimossi).
--
-- Lead indicator: proietta la posizione futura del bersaglio; il reticolo
-- centrale diventa verde quando e' allineato al lead (colpo garantito).
-- Convergenza: i raggi laser angolano verso il punto di convergenza;
-- gimbal assist sposta il convergence point verso il lead quando il
-- crosshair e' vicino ma non sopra.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local Workspace          = game:GetService("Workspace")
local GuiService         = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local mouse       = LocalPlayer:GetMouse()
local camera      = Workspace.CurrentCamera

local FlightEvents = ReplicatedStorage:WaitForChild("FlightEvents")
local ShipEvent    = FlightEvents:WaitForChild("ShipEvent")

-- Deve combaciare con LASER_SPEED in ShipScript per un lead corretto.
local LASER_SPEED = 750

-- ============================================================================
-- COSTANTI DI VOLO
-- ============================================================================
local HANGAR_SPEED      = 20      -- studs/sec max in hangar
local HANGAR_TURN_RATE  = 1.4     -- rad/sec yaw A/D in hangar
local HANGAR_ACCEL      = 30      -- accel/brake rate in hangar

local CROSSHAIR_MAX_R   = 230     -- pixel: deflessione massima crosshair
local CROSSHAIR_SENS    = 0.9     -- moltiplicatore sensibilita' mouse
local CROSSHAIR_RETURN  = 4.8     -- lambda ritorno al centro

local YAW_RATE          = 2.3     -- rad/sec alla deflessione massima
local PITCH_RATE        = 2.6
local MAX_PITCH         = math.rad(75)

local BANK_MAX          = math.rad(78)
local BANK_LAMBDA       = 6.2
local ROLL_RATE         = 4.4     -- rad/sec A/D in combat (dice roll)
local AIM_LAMBDA        = 9
local DRIFT_LAMBDA      = 3.8
local BANK_TURN_ASSIST  = 1.25    -- curva in base al bank (stile arcade)
local MIN_AUTHORITY     = 0.45    -- controllo minimo a bassa velocita'
local COMBAT_CRUISE_PCT = 0.38    -- throttle base in combat
local COMBAT_CRUISE_PULL = 0.9    -- ritorno verso cruise senza input
local INPUT_DEADZONE    = 0.08

local TARGET_RANGE      = 1500
local TARGET_CONE       = math.cos(math.rad(38))
local ALIGN_TOL_PX      = 26
local GIMBAL_TOL_PX     = 70
local DEFAULT_CONV_DIST = 800
local CANDIDATE_REFRESH = 0.35

local FLIGHT_CHASE_BACK = 22
local FLIGHT_CHASE_UP   = 7
local MIN_CHASE, MAX_CHASE = -10, 80
local MIN_HOVER, MAX_HOVER = 12, 70

-- Camera tuning (client-only feel)
local CAMERA_FOLLOW_STIFFNESS      = 42
local CAMERA_FOLLOW_DAMPING        = 14
local CAMERA_LOOK_STIFFNESS        = 30
local CAMERA_LOOK_DAMPING          = 12
local CAMERA_UP_LAMBDA             = 10
local CAMERA_ZOOM_BLEND_LAMBDA     = 16
local CAMERA_LOOK_AHEAD_BASE       = 160
local CAMERA_LOOK_AHEAD_SPEED_SCALE = 0.55
local CAMERA_LOOK_AHEAD_VEL_SCALE  = 0.2
local CAMERA_BANK_INFLUENCE        = 0.33
local CAMERA_BANK_MAX              = math.rad(20)
local CAMERA_BANK_MAX_RATE         = math.rad(260)
local CAMERA_GYRO_FILTER_LAMBDA    = 7
local CAMERA_MAX_ANGULAR_SPEED     = math.rad(170)
local CAMERA_MIN_PITCH             = math.rad(-58)
local CAMERA_MAX_PITCH             = math.rad(58)
local CAMERA_DEFAULT_LOOK_DISTANCE = 240

-- ============================================================================
-- COLORS / VISUAL TOKENS
-- ============================================================================
local PALETTE = {
	bg          = Color3.fromRGB(8, 12, 18),
	panel       = Color3.fromRGB(14, 22, 30),
	primary     = Color3.fromRGB(124, 220, 255),
	primaryDim  = Color3.fromRGB(52, 110, 138),
	accent      = Color3.fromRGB(255, 200, 87),
	danger      = Color3.fromRGB(255, 78, 78),
	good        = Color3.fromRGB(94, 240, 160),
	text        = Color3.fromRGB(230, 244, 255),
	textDim     = Color3.fromRGB(140, 170, 188),
}

-- ============================================================================
-- HUD BUILD
-- ============================================================================

local function new(class, props, children)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then inst[k] = v end
		end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	if props and props.Parent then inst.Parent = props.Parent end
	return inst
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Parent       = parent,
		Color        = color or PALETTE.primary,
		Thickness    = thickness or 1,
		Transparency = transparency or 0,
	})
end

local function corner(parent, radius)
	return new("UICorner", { Parent = parent, CornerRadius = UDim.new(0, radius or 6) })
end

local function gradient(parent, color, transparency, rotation)
	return new("UIGradient", {
		Parent       = parent,
		Color        = color,
		Transparency = transparency or NumberSequence.new(0),
		Rotation     = rotation or 0,
	})
end

local function buildHud()
	local gui = new("ScreenGui", {
		Name           = "ShipHUD",
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		DisplayOrder   = 10,
		Enabled        = false,
		Parent         = PlayerGui,
	})

	-- ---- Vignette
	local vignetteFrame = new("Frame", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel        = 0,
		ZIndex                 = 0,
		Parent                 = gui,
	})
	new("UIGradient", {
		Parent       = vignetteFrame,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    0),
			NumberSequenceKeypoint.new(0.35, 1),
			NumberSequenceKeypoint.new(0.65, 1),
			NumberSequenceKeypoint.new(1,    0),
		}),
		Rotation = 90,
	})

	-- ---- Reticle (center) -------------------------------------------------
	local reticle = new("Frame", {
		Name                   = "Reticle",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(180, 180),
		BackgroundTransparency = 1,
		Parent                 = gui,
	})

	local outerRing = new("Frame", {
		Name                   = "OuterRing",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent                 = reticle,
	})
	stroke(outerRing, PALETTE.primary, 1.2, 0.25)
	corner(outerRing, 999)
	new("UIGradient", {
		Parent       = outerRing:FindFirstChildOfClass("UIStroke"),
		Color        = ColorSequence.new(PALETTE.primary),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    0.1),
			NumberSequenceKeypoint.new(0.25, 1),
			NumberSequenceKeypoint.new(0.5,  0.1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1,    0.1),
		}),
	})

	local innerRing = new("Frame", {
		Name                   = "InnerRing",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(54, 54),
		BackgroundTransparency = 1,
		Parent                 = reticle,
	})
	local innerRingStroke = stroke(innerRing, PALETTE.primary, 1.5, 0.1)
	corner(innerRing, 999)

	local dot = new("Frame", {
		Name                   = "Dot",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(3, 3),
		BackgroundColor3       = PALETTE.text,
		BorderSizePixel        = 0,
		Parent                 = reticle,
	})
	corner(dot, 999)

	for i, rot in ipairs({0, 90, 180, 270}) do
		local tick = new("Frame", {
			Name                   = "Tick" .. i,
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromOffset(2, 96),
			BackgroundTransparency = 1,
			Rotation               = rot,
			Parent                 = reticle,
		})
		new("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, 0),
			Size             = UDim2.fromOffset(2, 14),
			BackgroundColor3 = PALETTE.primary,
			BorderSizePixel  = 0,
			Parent           = tick,
		})
		new("Frame", {
			AnchorPoint      = Vector2.new(0.5, 1),
			Position         = UDim2.new(0.5, 0, 1, 0),
			Size             = UDim2.fromOffset(2, 14),
			BackgroundColor3 = PALETTE.primary,
			BorderSizePixel  = 0,
			Parent           = tick,
		})
	end

	-- Reload arc
	local reloadFrame = new("Frame", {
		Name                   = "ReloadFrame",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(212, 212),
		BackgroundTransparency = 1,
		Parent                 = reticle,
	})
	local reloadStroke = stroke(reloadFrame, PALETTE.accent, 2, 0)
	corner(reloadFrame, 999)
	local reloadGradient = new("UIGradient", {
		Parent       = reloadStroke,
		Color        = ColorSequence.new(PALETTE.accent),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,     0),
			NumberSequenceKeypoint.new(0.001, 0),
			NumberSequenceKeypoint.new(0.002, 1),
			NumberSequenceKeypoint.new(1,     1),
		}),
		Rotation = -90,
	})

	-- ---- Crosshair virtuale (combat, segue deflessione mouse) -------------
	local crosshairElem = new("Frame", {
		Name                   = "Crosshair",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Visible                = false,
		ZIndex                 = 12,
		Parent                 = gui,
	})
	stroke(crosshairElem, PALETTE.accent, 1.5, 0)
	corner(crosshairElem, 999)
	new("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = UDim2.fromOffset(10, 1.5),
		BackgroundColor3 = PALETTE.accent,
		BorderSizePixel  = 0,
		ZIndex           = 12,
		Parent           = crosshairElem,
	})
	new("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = UDim2.fromOffset(1.5, 10),
		BackgroundColor3 = PALETTE.accent,
		BorderSizePixel  = 0,
		ZIndex           = 12,
		Parent           = crosshairElem,
	})

	-- ---- Lead indicator (posizione futura del bersaglio) ------------------
	local leadIndicator = new("Frame", {
		Name                   = "LeadIndicator",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Size                   = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Visible                = false,
		ZIndex                 = 11,
		Parent                 = gui,
	})
	local leadStroke = stroke(leadIndicator, PALETTE.primary, 2, 0)
	corner(leadIndicator, 999)

	-- ---- Target bounding box (4 linee) ------------------------------------
	local boxLines = {}
	for i = 1, 4 do
		boxLines[i] = new("Frame", {
			Name             = "BoxLine" .. i,
			BackgroundColor3 = PALETTE.primary,
			BorderSizePixel  = 0,
			Visible          = false,
			ZIndex           = 10,
			Parent           = gui,
		})
	end

	-- ---- TOP-LEFT: Ship info card ----------------------------------------
	local infoCard = new("Frame", {
		Name                   = "InfoCard",
		Position               = UDim2.fromOffset(28, 28),
		Size                   = UDim2.fromOffset(280, 96),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(infoCard, 4)
	stroke(infoCard, PALETTE.primaryDim, 1, 0.2)
	local accentBar = new("Frame", {
		Size             = UDim2.new(0, 3, 1, -16),
		Position         = UDim2.new(0, 0, 0, 8),
		BackgroundColor3 = PALETTE.primary,
		BorderSizePixel  = 0,
		Parent           = infoCard,
	})
	corner(accentBar, 2)
	local shipLabel = new("TextLabel", {
		Name                   = "ShipName",
		Position               = UDim2.fromOffset(16, 10),
		Size                   = UDim2.new(1, -28, 0, 22),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 18,
		TextColor3             = PALETTE.text,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "--",
		Parent                 = infoCard,
	})
	local subLabel = new("TextLabel", {
		Name                   = "Sub",
		Position               = UDim2.fromOffset(16, 32),
		Size                   = UDim2.new(1, -28, 0, 14),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.Gotham,
		TextSize               = 11,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "STARFIGHTER  /  ONLINE",
		Parent                 = infoCard,
	})
	local modeChip = new("Frame", {
		Name                   = "ModeChip",
		AnchorPoint            = Vector2.new(0, 1),
		Position               = UDim2.new(0, 16, 1, -10),
		Size                   = UDim2.fromOffset(110, 22),
		BackgroundColor3       = PALETTE.primary,
		BackgroundTransparency = 0.85,
		BorderSizePixel        = 0,
		Parent                 = infoCard,
	})
	corner(modeChip, 3)
	stroke(modeChip, PALETTE.primary, 1, 0.4)
	local modeLabel = new("TextLabel", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 11,
		TextColor3             = PALETTE.primary,
		Text                   = "HANGAR",
		Parent                 = modeChip,
	})

	-- ---- BOTTOM-LEFT: Speedometer ----------------------------------------
	local speedCard = new("Frame", {
		Name                   = "Speed",
		AnchorPoint            = Vector2.new(0, 1),
		Position               = UDim2.new(0, 28, 1, -28),
		Size                   = UDim2.fromOffset(260, 80),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(speedCard, 4)
	stroke(speedCard, PALETTE.primaryDim, 1, 0.3)
	new("TextLabel", {
		Position               = UDim2.fromOffset(14, 8),
		Size                   = UDim2.new(0, 80, 0, 12),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.Gotham,
		TextSize               = 10,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "VELOCITY",
		Parent                 = speedCard,
	})
	local speedValue = new("TextLabel", {
		Position               = UDim2.fromOffset(14, 22),
		Size                   = UDim2.new(0, 130, 0, 36),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 32,
		TextColor3             = PALETTE.text,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "0",
		Parent                 = speedCard,
	})
	new("TextLabel", {
		Position               = UDim2.fromOffset(150, 30),
		Size                   = UDim2.new(0, 60, 0, 20),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.Gotham,
		TextSize               = 11,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "STUDS/SEC",
		Parent                 = speedCard,
	})
	local speedBarBg = new("Frame", {
		Position         = UDim2.fromOffset(14, 60),
		Size             = UDim2.new(1, -28, 0, 4),
		BackgroundColor3 = PALETTE.bg,
		BorderSizePixel  = 0,
		Parent           = speedCard,
	})
	corner(speedBarBg, 2)
	local speedBarFill = new("Frame", {
		Size             = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = PALETTE.primary,
		BorderSizePixel  = 0,
		Parent           = speedBarBg,
	})
	corner(speedBarFill, 2)
	gradient(speedBarFill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, PALETTE.primary),
		ColorSequenceKeypoint.new(1, PALETTE.accent),
	}))

	-- ---- BOTTOM-RIGHT (sopra Altitude): Controls / keybinds --------------
	local ctrlCard = new("Frame", {
		Name                   = "Controls",
		AnchorPoint            = Vector2.new(1, 1),
		Position               = UDim2.new(1, -28, 1, -28 - 240 - 12),
		Size                   = UDim2.fromOffset(180, 280),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(ctrlCard, 4)
	stroke(ctrlCard, PALETTE.primaryDim, 1, 0.2)
	new("TextLabel", {
		Position               = UDim2.fromOffset(14, 10),
		Size                   = UDim2.new(1, -28, 0, 14),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 11,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "CONTROLS",
		Parent                 = ctrlCard,
	})
	new("Frame", {
		Position               = UDim2.fromOffset(14, 28),
		Size                   = UDim2.new(1, -28, 0, 1),
		BackgroundColor3       = PALETTE.primaryDim,
		BackgroundTransparency = 0.5,
		BorderSizePixel        = 0,
		Parent                 = ctrlCard,
	})
	local controlsRowContainer = new("Frame", {
		Position               = UDim2.fromOffset(10, 36),
		Size                   = UDim2.new(1, -20, 1, -46),
		BackgroundTransparency = 1,
		Parent                 = ctrlCard,
	})
	new("UIListLayout", {
		Parent        = controlsRowContainer,
		Padding       = UDim.new(0, 3),
		SortOrder     = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
	})

	local function controlRow(order, keyText, actionText)
		local row = new("Frame", {
			Size                   = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder            = order,
			Parent                 = controlsRowContainer,
		})
		local key = new("Frame", {
			Size                   = UDim2.new(0, 52, 1, 0),
			BackgroundColor3       = PALETTE.bg,
			BackgroundTransparency = 0.2,
			BorderSizePixel        = 0,
			Parent                 = row,
		})
		corner(key, 3)
		stroke(key, PALETTE.primary, 1, 0.4)
		new("TextLabel", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font                   = Enum.Font.GothamBold,
			TextSize               = 13,
			TextColor3             = PALETTE.primary,
			Text                   = keyText,
			Parent                 = key,
		})
		new("TextLabel", {
			Position               = UDim2.fromOffset(60, 0),
			Size                   = UDim2.new(1, -60, 1, 0),
			BackgroundTransparency = 1,
			Font                   = Enum.Font.GothamMedium,
			TextSize               = 13,
			TextColor3             = PALETTE.text,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Text                   = actionText,
			Parent                 = row,
		})
		return row
	end

	controlRow(1, "R",     "Engine")
	controlRow(2, "W S",   "Throttle")
	controlRow(3, "A D",   "Turn (Hangar)")
	controlRow(4, "N",     "Hangar/Combat")
	controlRow(5, "C",     "Camera")
	controlRow(6, "LMB",   "Fire")
	controlRow(7, "RMB",   "Zoom Aim")
	controlRow(8, "WHEEL", "Cam Zoom")

	-- ---- BOTTOM-RIGHT: Altitude ------------------------------------------
	local altCard = new("Frame", {
		Name                   = "Altitude",
		AnchorPoint            = Vector2.new(1, 1),
		Position               = UDim2.new(1, -28, 1, -28),
		Size                   = UDim2.fromOffset(120, 240),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(altCard, 4)
	stroke(altCard, PALETTE.primaryDim, 1, 0.3)
	new("TextLabel", {
		Position               = UDim2.fromOffset(14, 8),
		Size                   = UDim2.new(1, -28, 0, 12),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.Gotham,
		TextSize               = 10,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "ALT",
		Parent                 = altCard,
	})
	local altValue = new("TextLabel", {
		AnchorPoint            = Vector2.new(1, 0),
		Position               = UDim2.new(1, -14, 0, 6),
		Size                   = UDim2.new(0, 90, 0, 16),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 14,
		TextColor3             = PALETTE.text,
		TextXAlignment         = Enum.TextXAlignment.Right,
		Text                   = "0",
		Parent                 = altCard,
	})
	local altTrack = new("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.new(0.5, 0, 0, 28),
		Size             = UDim2.new(0, 4, 1, -42),
		BackgroundColor3 = PALETTE.bg,
		BorderSizePixel  = 0,
		Parent           = altCard,
	})
	corner(altTrack, 2)
	local altNeedle = new("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.new(0.5, 0, 0.5, 0),
		Size             = UDim2.fromOffset(24, 2),
		BackgroundColor3 = PALETTE.primary,
		BorderSizePixel  = 0,
		Parent           = altTrack,
	})
	for i = 0, 10 do
		local y = i / 10
		new("Frame", {
			AnchorPoint            = Vector2.new(0, 0.5),
			Position               = UDim2.new(1, 6, y, 0),
			Size                   = UDim2.fromOffset((i % 5 == 0) and 12 or 6, 1),
			BackgroundColor3       = PALETTE.textDim,
			BorderSizePixel        = 0,
			BackgroundTransparency = (i % 5 == 0) and 0 or 0.5,
			Parent                 = altTrack,
		})
	end

	-- ---- BOTTOM-CENTER: Throttle bar -------------------------------------
	local thrCard = new("Frame", {
		Name                   = "Throttle",
		AnchorPoint            = Vector2.new(0.5, 1),
		Position               = UDim2.new(0.5, 0, 1, -28),
		Size                   = UDim2.fromOffset(360, 36),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(thrCard, 4)
	stroke(thrCard, PALETTE.primaryDim, 1, 0.3)
	new("TextLabel", {
		Position               = UDim2.fromOffset(14, 4),
		Size                   = UDim2.new(0, 80, 0, 12),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.Gotham,
		TextSize               = 10,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "THROTTLE",
		Parent                 = thrCard,
	})
	local thrBarBg = new("Frame", {
		Position         = UDim2.fromOffset(14, 22),
		Size             = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = PALETTE.bg,
		BorderSizePixel  = 0,
		Parent           = thrCard,
	})
	corner(thrBarBg, 3)
	new("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0),
		Position         = UDim2.new(0.5, 0, 0, -2),
		Size             = UDim2.fromOffset(1, 10),
		BackgroundColor3 = PALETTE.textDim,
		BorderSizePixel  = 0,
		Parent           = thrBarBg,
	})
	local thrFill = new("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.new(0.5, 0, 0.5, 0),
		Size             = UDim2.fromScale(0, 1),
		BackgroundColor3 = PALETTE.primary,
		BorderSizePixel  = 0,
		Parent           = thrBarBg,
	})
	corner(thrFill, 3)

	-- ---- TOP-RIGHT: Telemetry  -------------------------------------------
	local teleCard = new("Frame", {
		Name                   = "Telemetry",
		AnchorPoint            = Vector2.new(1, 0),
		Position               = UDim2.new(1, -28, 0, 28),
		Size                   = UDim2.fromOffset(240, 96),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(teleCard, 4)
	stroke(teleCard, PALETTE.primaryDim, 1, 0.2)
	local function teleRow(y, label)
		new("TextLabel", {
			Position               = UDim2.fromOffset(14, y),
			Size                   = UDim2.new(0, 100, 0, 14),
			BackgroundTransparency = 1,
			Font                   = Enum.Font.Gotham,
			TextSize               = 11,
			TextColor3             = PALETTE.textDim,
			TextXAlignment         = Enum.TextXAlignment.Left,
			Text                   = label,
			Parent                 = teleCard,
		})
		return new("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.new(1, -14, 0, y),
			Size                   = UDim2.new(0, 120, 0, 14),
			BackgroundTransparency = 1,
			Font                   = Enum.Font.GothamBold,
			TextSize               = 12,
			TextColor3             = PALETTE.text,
			TextXAlignment         = Enum.TextXAlignment.Right,
			Text                   = "--",
			Parent                 = teleCard,
		})
	end
	local pitchValue   = teleRow(12, "PITCH")
	local rollValue    = teleRow(34, "ROLL")
	local headingValue = teleRow(56, "HEADING")
	local dmgValue     = teleRow(78, "DMG/SHOT")

	-- ---- Hit flash overlay -----------------------------------------------
	local hitFlash = new("Frame", {
		Name                   = "HitFlash",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = PALETTE.danger,
		BackgroundTransparency = 1,
		BorderSizePixel        = 0,
		ZIndex                 = 50,
		Parent                 = gui,
	})

	return {
		Gui             = gui,
		Reticle         = reticle,
		OuterRing       = outerRing,
		InnerRing       = innerRing,
		InnerRingStroke = innerRingStroke,
		ReloadGradient  = reloadGradient,
		ShipLabel       = shipLabel,
		SubLabel        = subLabel,
		ModeChip        = modeChip,
		ModeLabel       = modeLabel,
		SpeedValue      = speedValue,
		SpeedBarFill    = speedBarFill,
		AltValue        = altValue,
		AltNeedle       = altNeedle,
		AltTrack        = altTrack,
		ThrFill         = thrFill,
		Pitch           = pitchValue,
		Roll            = rollValue,
		Heading         = headingValue,
		Dmg             = dmgValue,
		HitFlash        = hitFlash,
		ControlsCard    = ctrlCard,
		-- Nuovi elementi combat
		Crosshair       = crosshairElem,
		LeadIndicator   = leadIndicator,
		LeadStroke      = leadStroke,
		BoxLines        = boxLines,
	}
end

local HUD = buildHud()

-- ============================================================================
-- HUD HELPERS
-- ============================================================================

local function tween(obj, t, props, style, dir)
	local ti = TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(obj, ti, props)
	tw:Play()
	return tw
end

local function pulseRingOnFire()
	tween(HUD.InnerRing, 0.08, { Size = UDim2.fromOffset(38, 38) })
	task.delay(0.09, function()
		tween(HUD.InnerRing, 0.18, { Size = UDim2.fromOffset(54, 54) })
	end)
end

local function flashHit()
	HUD.HitFlash.BackgroundTransparency = 0.55
	tween(HUD.HitFlash, 0.35, { BackgroundTransparency = 1 })
end

-- ============================================================================
-- SHIP DETECTION
-- ============================================================================

local function shipFromCharacter()
	local char = LocalPlayer.Character
	if not char then return nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil, nil end
	local seat = hum.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then return nil, nil end
	local model = seat:FindFirstAncestorOfClass("Model")
	if not model then return nil, nil end
	if not model:FindFirstChild("CameraPart") then return nil, nil end
	return model, seat
end

-- ============================================================================
-- FLIGHT STATE
-- ============================================================================

local state = {
	ship     = nil,
	seat     = nil,
	primary  = nil,
	gyro     = nil,
	velocity = nil,
	camPart  = nil,
	zoomPart = nil,

	-- "hangar" | "combat"
	mode     = "hangar",
	sfoils   = false,
	engineOn = false,

	-- Velocita' scalare corrente (studs/sec)
	currentSpeed = 0,

	-- Camera chase (scroll in combat)
	chaseDistance = 0,

	-- Camera orbita (hangar + combat free-look)
	hoverYaw      = 0,
	hoverPitch    = -0.15,
	hoverDistance = 28,
	freeLook      = false,

	-- Hangar: yaw della nave (integrato da A/D)
	hangarYaw = 0,

	-- Combat: Euler yaw/pitch del muso
	aimYaw   = 0,
	aimPitch = 0,
	bank     = 0,
	roll     = 0,  -- roll manuale A/D (accumulato, 360° libero)

	-- Combat: velocita' inerziale (drift)
	flightVel = Vector3.zero,

	-- Combat: CFrame interpolato del gyro
	aimCFrame = nil,

	-- Crosshair: deflessione pixel (Vector2)
	crosshairOffset = Vector2.zero,

	-- Targeting
	candidates     = {},
	target         = nil,
	leadWorld      = nil,
	leadScreen     = nil,
	aligned        = false,
	candidateTimer = 0,

	-- Zoom / aim RMB
	zoomMode = false,

	camera = {
		initialized  = false,
		position     = Vector3.zero,
		velocity     = Vector3.zero,
		lookPoint    = Vector3.zero,
		lookVelocity = Vector3.zero,
		upVector     = Vector3.yAxis,
		zoomAlpha    = 0,
		bankFiltered = 0,
		combatOffset = nil,
	},

	-- Shooting
	shooting = false,
	lastShot = -math.huge,

	config = {
		Damage      = 30,
		MaxSpeed    = 150,
		ReloadSpeed = 0.18,
		Faction     = "Republic",
		FireSound   = "",
	},
}

local function readShipConfig(ship)
	state.config.Damage      = ship:GetAttribute("Damage")      or 30
	state.config.MaxSpeed    = ship:GetAttribute("MaxSpeed")    or 150
	state.config.ReloadSpeed = ship:GetAttribute("ReloadSpeed") or 0.18
	state.config.Faction     = ship:GetAttribute("Faction")     or "Republic"
	state.config.FireSound   = ship:GetAttribute("FireSound")   or ""
end

-- ============================================================================
-- INPUT HELPERS
-- ============================================================================
local function key(k) return UserInputService:IsKeyDown(k) end
local function axis(pos, neg)
	return (key(pos) and 1 or 0) - (key(neg) and 1 or 0)
end

-- W/S = throttle, A/D = yaw (hangar) / non usato direttamente in combat
local function readMoveInput()
	return
		axis(Enum.KeyCode.W, Enum.KeyCode.S),
		axis(Enum.KeyCode.D, Enum.KeyCode.A)
end

local function setMouseLocked(locked)
	if locked then
		UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

-- ============================================================================
-- TARGETING
-- ============================================================================

local function refreshCandidates(shipFaction)
	local result = {}
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Humanoid") and inst.Health > 0 then
			local model = inst.Parent
			if model and model:IsA("Model") then
				local f = model:GetAttribute("Faction")
				if f and f ~= shipFaction then
					local root = model:FindFirstChild("HumanoidRootPart")
						or model:FindFirstChildWhichIsA("BasePart")
					if root then
						table.insert(result, { model = model, root = root })
					end
				end
			end
		end
	end
	return result
end

local function pickTarget(candidates, noseWorld, shipPos)
	local bestDot  = TARGET_CONE
	local bestDist = math.huge
	local best     = nil
	for _, c in ipairs(candidates) do
		local toTarget = (c.root.Position - shipPos)
		local dist = toTarget.Magnitude
		if dist <= TARGET_RANGE then
			local dot = toTarget.Unit:Dot(noseWorld)
			if dot >= TARGET_CONE then
				if dot > bestDot or (dot == bestDot and dist < bestDist) then
					bestDot  = dot
					bestDist = dist
					best     = c.model
				end
			end
		end
	end
	return best
end

local function worldToScreen(pos)
	local vpPos, onScreen = camera:WorldToViewportPoint(pos)
	if not onScreen then return nil end
	return Vector2.new(vpPos.X, vpPos.Y)
end

local function getModelScreenRect(model)
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok then return nil end
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local offsets = {
		Vector3.new( hx,  hy,  hz), Vector3.new(-hx,  hy,  hz),
		Vector3.new( hx, -hy,  hz), Vector3.new(-hx, -hy,  hz),
		Vector3.new( hx,  hy, -hz), Vector3.new(-hx,  hy, -hz),
		Vector3.new( hx, -hy, -hz), Vector3.new(-hx, -hy, -hz),
	}
	local minX, minY, maxX, maxY
	for _, off in ipairs(offsets) do
		local sp = worldToScreen(cf.Position + off)
		if sp then
			if not minX then
				minX, minY, maxX, maxY = sp.X, sp.Y, sp.X, sp.Y
			else
				if sp.X < minX then minX = sp.X end
				if sp.Y < minY then minY = sp.Y end
				if sp.X > maxX then maxX = sp.X end
				if sp.Y > maxY then maxY = sp.Y end
			end
		end
	end
	return minX, minY, maxX, maxY
end

local function hideTargetUI()
	for _, l in ipairs(HUD.BoxLines) do l.Visible = false end
	HUD.LeadIndicator.Visible = false
	state.target     = nil
	state.leadWorld  = nil
	state.leadScreen = nil
	state.aligned    = false
end

-- ============================================================================
-- MODALITA' DI VOLO
-- ============================================================================

local function setMode(newMode)
	if state.mode == newMode then return end
	state.mode = newMode

	-- Inizializza camera orbita dalla nave
	if state.primary then
		local look = state.primary.CFrame.LookVector
		state.hoverYaw   = math.atan2(-look.X, -look.Z)
		state.hoverPitch = -0.15
	end

	if newMode == "hangar" then
		state.freeLook        = false
		state.crosshairOffset = Vector2.zero
		if state.primary then
			local look = state.primary.CFrame.LookVector
			state.hangarYaw = math.atan2(look.X, look.Z)
		end
		HUD.Crosshair.Visible = false
		hideTargetUI()
		HUD.InnerRingStroke.Color = PALETTE.primary
	else -- "combat"
		state.aimYaw   = state.hangarYaw
		state.aimPitch = 0
		state.bank     = 0
		state.roll     = 0
		if state.primary then
			state.flightVel = state.primary.CFrame.LookVector * state.currentSpeed
			state.aimCFrame = state.primary.CFrame
		end
		HUD.Crosshair.Visible = true
	end
end

local function startFlight(ship, seat)
	state.ship      = ship
	state.seat      = seat
	state.primary   = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart")
	state.camPart   = ship:FindFirstChild("CameraPart", true)
	state.zoomPart  = ship:FindFirstChild("ZoomPart",   true)
	state.gyro      = state.primary and state.primary:WaitForChild("ShipGyro",     2)
	state.velocity  = state.primary and state.primary:WaitForChild("ShipVelocity", 2)

	state.sfoils          = false
	state.engineOn        = false
	state.currentSpeed    = 0
	state.chaseDistance   = 0
	state.crosshairOffset = Vector2.zero
	state.aimYaw          = 0
	state.aimPitch        = 0
	state.bank            = 0
	state.roll            = 0
	state.flightVel       = Vector3.zero
	state.aimCFrame       = state.primary and state.primary.CFrame or nil
	state.zoomMode        = false
	state.freeLook        = false
	state.lastShot        = -math.huge
	state.target          = nil
	state.leadWorld       = nil
	state.leadScreen      = nil
	state.aligned         = false
	state.candidateTimer  = 0
	state.candidates      = {}
	state.camera.initialized  = false
	state.camera.position     = Vector3.zero
	state.camera.velocity     = Vector3.zero
	state.camera.lookPoint    = Vector3.zero
	state.camera.lookVelocity = Vector3.zero
	state.camera.upVector     = Vector3.yAxis
	state.camera.zoomAlpha    = 0
	state.camera.bankFiltered = 0
	state.camera.combatOffset = nil

	readShipConfig(ship)

	if state.primary then
		local look = state.primary.CFrame.LookVector
		state.hangarYaw  = math.atan2(look.X, look.Z)
		state.hoverYaw   = math.atan2(-look.X, -look.Z)
		state.hoverPitch = -0.15
		state.hoverDistance = 28
		if state.camPart then
			state.camera.combatOffset = state.primary.CFrame:PointToObjectSpace(state.camPart.Position)
		end
	end

	-- HUD reveal
	HUD.ShipLabel.Text = ship.Name:upper()
	HUD.SubLabel.Text  = "STARFIGHTER  /  ONLINE  /  PILOT: " .. LocalPlayer.Name:upper()
	HUD.Dmg.Text       = string.format("%d", state.config.Damage)
	HUD.Gui.Enabled    = true

	for _, name in ipairs({ "InfoCard", "Speed", "Altitude", "Throttle", "Telemetry", "Controls" }) do
		local card = HUD.Gui:FindFirstChild(name)
		if card then
			local target = card.Position
			card.Position = target + UDim2.fromOffset(0, 24)
			card.BackgroundTransparency = 1
			tween(card, 0.4, { Position = target, BackgroundTransparency = 0.25 })
		end
	end
	HUD.Reticle.Size = UDim2.fromOffset(120, 120)
	tween(HUD.Reticle, 0.45, { Size = UDim2.fromOffset(180, 180) }, Enum.EasingStyle.Back)

	-- Avvio sempre in Hangar
	state.mode = nil
	setMode("hangar")
	setMouseLocked(true)
end

local function stopFlight()
	if state.seat == nil then return end
	camera.CameraType  = Enum.CameraType.Custom
	mouse.TargetFilter = nil
	setMouseLocked(false)

	HUD.Crosshair.Visible     = false
	HUD.LeadIndicator.Visible = false
	for _, l in ipairs(HUD.BoxLines) do l.Visible = false end

	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.CameraOffset = Vector3.zero end

	for _, name in ipairs({ "InfoCard", "Speed", "Altitude", "Throttle", "Telemetry", "Controls" }) do
		local card = HUD.Gui:FindFirstChild(name)
		if card then tween(card, 0.2, { BackgroundTransparency = 1 }) end
	end
	task.delay(0.25, function()
		if state.seat == nil then HUD.Gui.Enabled = false end
	end)

	state.ship     = nil
	state.seat     = nil
	state.primary  = nil
	state.gyro     = nil
	state.velocity = nil
	state.target   = nil
	state.camera.initialized  = false
	state.camera.velocity     = Vector3.zero
	state.camera.lookVelocity = Vector3.zero
end

local function smoothAlpha(lambda, dt)
	return 1 - math.exp(-math.max(lambda, 0) * math.max(dt, 0))
end

local function springStep(curr, vel, target, stiffness, damping, dt)
	local accel = (target - curr) * stiffness - vel * damping
	vel = vel + accel * dt
	curr = curr + vel * dt
	return curr, vel
end

local function safeUnit(v, fallback)
	local mag = v.Magnitude
	if mag > 1e-5 then
		return v / mag
	end
	return fallback
end

local function clampLookPitch(origin, target, minPitch, maxPitch)
	local dir = safeUnit(target - origin, Vector3.zAxis)
	local pitch = math.asin(math.clamp(dir.Y, -1, 1))
	pitch = math.clamp(pitch, minPitch, maxPitch)
	local yaw = math.atan2(dir.X, dir.Z)
	local cp = math.cos(pitch)
	local clampedDir = Vector3.new(math.sin(yaw) * cp, math.sin(pitch), math.cos(yaw) * cp)
	local dist = math.max((target - origin).Magnitude, CAMERA_DEFAULT_LOOK_DISTANCE)
	return origin + clampedDir * dist
end

local function limitDirectionChange(currentDir, targetDir, maxAngle)
	local from = safeUnit(currentDir, Vector3.zAxis)
	local to   = safeUnit(targetDir, from)
	local dot  = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return to
	end
	local t = math.clamp(maxAngle / angle, 0, 1)
	return safeUnit(from:Lerp(to, t), to)
end

-- ============================================================================
-- RENDER LOOP
-- ============================================================================

local outerSpin      = 0
local replicateAccum = 0

RunService.RenderStepped:Connect(function(dt)
	-- Rotazione outer ring
	outerSpin = (outerSpin + dt * 36) % 360
	HUD.OuterRing.Rotation = outerSpin

	-- Reload arc
	if state.ship then
		local since = os.clock() - state.lastShot
		local pct   = math.clamp(since / math.max(state.config.ReloadSpeed, 0.01), 0, 1)
		HUD.ReloadGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,                        0),
			NumberSequenceKeypoint.new(math.max(pct, 0.001),     0),
			NumberSequenceKeypoint.new(math.min(pct + 0.001, 1), 1),
			NumberSequenceKeypoint.new(1,                        1),
		})
	end

	-- Detect seat
	local detectedShip, detectedSeat = shipFromCharacter()
	if detectedShip and detectedShip ~= state.ship then
		startFlight(detectedShip, detectedSeat)
	elseif not detectedShip and state.ship then
		stopFlight()
	end

	if not state.ship or not state.primary then return end

	-- ========================================================================
	-- CAMERA
	-- ========================================================================
	local inHangar   = (state.mode == "hangar")
	local inFreeLook = (state.mode == "combat" and state.freeLook)
	local zoomPart   = state.zoomPart
	local shipPos    = state.primary.Position
	local profilePos, profileLook, profileUp

	if inHangar or inFreeLook then
		-- Orbita libera (profilo free-look/hangar)
		local pivot = shipPos + Vector3.new(0, 2, 0)
		local rot   = CFrame.Angles(0, state.hoverYaw, 0) * CFrame.Angles(state.hoverPitch, 0, 0)
		local offset = rot * Vector3.new(0, 0, state.hoverDistance)
		profilePos = pivot + offset
		profileLook = pivot
		profileUp = Vector3.yAxis
	else
		-- Combat chase indipendente da CameraPart.CFrame
		local refCF = state.aimCFrame or state.primary.CFrame
		local shipFwd = refCF.LookVector
		local shipUp  = refCF.UpVector

		if state.camera.combatOffset then
			profilePos = state.primary.CFrame:PointToWorldSpace(
				state.camera.combatOffset + Vector3.new(0, 0, state.chaseDistance)
			)
		else
			profilePos = shipPos
				- shipFwd * (FLIGHT_CHASE_BACK + state.chaseDistance)
				+ shipUp  * FLIGHT_CHASE_UP
		end

		local speedForLook = math.clamp(state.currentSpeed, 0, math.max(state.config.MaxSpeed, 1))
		profileLook = shipPos
			+ shipFwd * (CAMERA_LOOK_AHEAD_BASE + speedForLook * CAMERA_LOOK_AHEAD_SPEED_SCALE)
			+ state.flightVel * CAMERA_LOOK_AHEAD_VEL_SCALE

		local targetBank = math.clamp((state.roll + state.bank) * CAMERA_BANK_INFLUENCE, -CAMERA_BANK_MAX, CAMERA_BANK_MAX)
		local maxBankStep = CAMERA_BANK_MAX_RATE * dt
		local bankDelta = math.clamp(targetBank - state.camera.bankFiltered, -maxBankStep, maxBankStep)
		state.camera.bankFiltered = state.camera.bankFiltered + bankDelta
		state.camera.bankFiltered = state.camera.bankFiltered
			+ (targetBank - state.camera.bankFiltered) * smoothAlpha(CAMERA_GYRO_FILTER_LAMBDA, dt)

		local bankCF = CFrame.fromAxisAngle(shipFwd, state.camera.bankFiltered)
		profileUp = safeUnit(bankCF:VectorToWorldSpace(shipUp), shipUp)
	end

	local zoomTarget = (state.zoomMode and zoomPart) and 1 or 0
	state.camera.zoomAlpha = state.camera.zoomAlpha
		+ (zoomTarget - state.camera.zoomAlpha) * smoothAlpha(CAMERA_ZOOM_BLEND_LAMBDA, dt)
	if zoomPart and state.camera.zoomAlpha > 0.001 then
		local zPos  = zoomPart.Position
		local zLook = zPos + zoomPart.CFrame.LookVector * CAMERA_DEFAULT_LOOK_DISTANCE
		local zUp   = zoomPart.CFrame.UpVector
		profilePos  = profilePos:Lerp(zPos, state.camera.zoomAlpha)
		profileLook = profileLook:Lerp(zLook, state.camera.zoomAlpha)
		profileUp   = safeUnit(profileUp:Lerp(zUp, state.camera.zoomAlpha), zUp)
	end

	profileLook = clampLookPitch(profilePos, profileLook, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)

	if not state.camera.initialized then
		state.camera.initialized  = true
		state.camera.position     = profilePos
		state.camera.lookPoint    = profileLook
		state.camera.upVector     = profileUp
		state.camera.velocity     = Vector3.zero
		state.camera.lookVelocity = Vector3.zero
	end

	local currentDir = state.camera.lookPoint - state.camera.position
	local targetDir  = profileLook - profilePos
	local maxAngle   = CAMERA_MAX_ANGULAR_SPEED * dt
	local limitedDir = limitDirectionChange(currentDir, targetDir, maxAngle)
	local lookDist   = math.max(targetDir.Magnitude, CAMERA_DEFAULT_LOOK_DISTANCE)
	local limitedLook = profilePos + limitedDir * lookDist

	state.camera.position, state.camera.velocity = springStep(
		state.camera.position, state.camera.velocity, profilePos,
		CAMERA_FOLLOW_STIFFNESS, CAMERA_FOLLOW_DAMPING, dt
	)
	state.camera.lookPoint, state.camera.lookVelocity = springStep(
		state.camera.lookPoint, state.camera.lookVelocity, limitedLook,
		CAMERA_LOOK_STIFFNESS, CAMERA_LOOK_DAMPING, dt
	)
	state.camera.upVector = safeUnit(
		state.camera.upVector:Lerp(profileUp, smoothAlpha(CAMERA_UP_LAMBDA, dt)),
		profileUp
	)

	local lookTarget = state.camera.lookPoint
	if (lookTarget - state.camera.position).Magnitude < 1 then
		lookTarget = state.camera.position + limitedDir * CAMERA_DEFAULT_LOOK_DISTANCE
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(state.camera.position, lookTarget, state.camera.upVector)

	mouse.TargetFilter = state.ship

	-- ========================================================================
	-- PHYSICS
	-- ========================================================================
	local fwdInput, rgtInput = readMoveInput()
	local maxSpeed = math.max(state.config.MaxSpeed, 1)

	if not state.engineOn then
		state.currentSpeed = 0
		state.flightVel    = Vector3.zero
		HUD.ThrFill.Size   = UDim2.new(0, 0, 1, 0)

	elseif state.mode == "hangar" then
		-- ----------------------------------------------------------------
		-- HANGAR: W/S throttle, A/D yaw piatto, speed cap HANGAR_SPEED
		-- ----------------------------------------------------------------
		if fwdInput > 0 then
			state.currentSpeed = math.min(state.currentSpeed + HANGAR_ACCEL * dt, HANGAR_SPEED)
		elseif fwdInput < 0 then
			state.currentSpeed = math.max(state.currentSpeed - HANGAR_ACCEL * 1.5 * dt, 0)
		else
			state.currentSpeed = math.max(state.currentSpeed - HANGAR_ACCEL * 0.4 * dt, 0)
		end

		state.hangarYaw = state.hangarYaw + rgtInput * HANGAR_TURN_RATE * dt

		-- muso = +LookVector. hangarYaw=0 → muso verso +Z
		local noseDirFlat = Vector3.new(math.sin(state.hangarYaw), 0, math.cos(state.hangarYaw))
		if state.gyro then
			state.gyro.CFrame = CFrame.lookAt(Vector3.zero, noseDirFlat)
		end
		if state.velocity then
			state.velocity.Velocity = noseDirFlat * state.currentSpeed
		end

		local thrPct = state.currentSpeed / HANGAR_SPEED
		HUD.ThrFill.AnchorPoint      = Vector2.new(0, 0.5)
		HUD.ThrFill.Position         = UDim2.new(0.5, 0, 0.5, 0)
		HUD.ThrFill.Size             = UDim2.new(0.5 * thrPct, 0, 1, 0)
		HUD.ThrFill.BackgroundColor3 = PALETTE.primary

	else
		-- ----------------------------------------------------------------
		-- COMBAT: crosshair → yaw/pitch Euler → gyro, auto-bank, deriva
		-- ----------------------------------------------------------------
		local cruiseSpeed = maxSpeed * COMBAT_CRUISE_PCT
		if fwdInput > 0 then
			state.currentSpeed = math.min(state.currentSpeed + maxSpeed * 0.7 * dt, maxSpeed)
		elseif fwdInput < 0 then
			state.currentSpeed = math.max(state.currentSpeed - maxSpeed * 1.4 * dt, cruiseSpeed * 0.35)
		else
			local k = 1 - math.exp(-COMBAT_CRUISE_PULL * dt)
			state.currentSpeed = state.currentSpeed + (cruiseSpeed - state.currentSpeed) * k
		end

		-- Crosshair torna al centro
		state.crosshairOffset = state.crosshairOffset:Lerp(
			Vector2.zero, 1 - math.exp(-CROSSHAIR_RETURN * dt)
		)

		local speedRatio = math.clamp(state.currentSpeed / math.max(maxSpeed, 1), 0, 1)
		local authority  = MIN_AUTHORITY + (1 - MIN_AUTHORITY) * speedRatio
		local rollInput  = math.clamp(rgtInput + axis(Enum.KeyCode.E, Enum.KeyCode.Q), -1, 1)

		-- Roll manuale (A/D + Q/E) per barrel/dice roll
		state.roll = state.roll - rollInput * (ROLL_RATE * authority) * dt
		state.roll = math.atan2(math.sin(state.roll), math.cos(state.roll))

		-- Integra yaw/pitch dal crosshair (X negato: mouse destra → gira destra)
		local cxNorm = -state.crosshairOffset.X / CROSSHAIR_MAX_R
		local cyNorm =  state.crosshairOffset.Y / CROSSHAIR_MAX_R
		local function shaped(v)
			local a = math.abs(v)
			if a < INPUT_DEADZONE then return 0 end
			local t = (a - INPUT_DEADZONE) / (1 - INPUT_DEADZONE)
			return math.sign(v) * (t * t)
		end
		local yawInput   = shaped(cxNorm)
		local pitchInput = shaped(cyNorm)
		local prevAimYaw = state.aimYaw
		local bankTurn = math.sin(state.roll + state.bank) * BANK_TURN_ASSIST * math.max(speedRatio, 0.3)
		state.aimYaw   = state.aimYaw + (yawInput * YAW_RATE * authority + bankTurn) * dt
		state.aimPitch = math.clamp(state.aimPitch - pitchInput * PITCH_RATE * authority * dt, -MAX_PITCH, MAX_PITCH)

		-- Auto-bank proporzionale al yaw rate (si somma al roll manuale)
		local yawRate    = (state.aimYaw - prevAimYaw) / math.max(dt, 0.001)
		local targetBank = -(yawRate / YAW_RATE) * BANK_MAX
		state.bank = state.bank + (targetBank - state.bank) * (1 - math.exp(-BANK_LAMBDA * dt))
		state.bank = math.clamp(state.bank, -BANK_MAX, BANK_MAX)

		-- Direzione muso dai Euler
		local cy = math.cos(state.aimYaw)
		local sy = math.sin(state.aimYaw)
		local cp = math.cos(state.aimPitch)
		local sp = math.sin(state.aimPitch)
		local noseDir = Vector3.new(sy * cp, sp, cy * cp)

		-- Gyro: muso = +LookVector + roll manuale + auto-bank
		local baseCF    = CFrame.lookAt(Vector3.zero, noseDir)
		local targetCF  = baseCF * CFrame.Angles(0, 0, state.roll + state.bank)
		local desiredCF = CFrame.new(state.primary.Position) * (targetCF - targetCF.Position)

		if not state.aimCFrame then
			state.aimCFrame = state.primary.CFrame
		end
		state.aimCFrame = state.aimCFrame:Lerp(desiredCF, 1 - math.exp(-AIM_LAMBDA * dt))
		if state.gyro then
			state.gyro.CFrame = state.aimCFrame
		end

		-- Deriva inerziale
		local targetVel = noseDir * state.currentSpeed
		state.flightVel = state.flightVel:Lerp(targetVel, 1 - math.exp(-DRIFT_LAMBDA * dt))
		if state.velocity then
			state.velocity.Velocity = state.flightVel
		end

		local thrPct = state.currentSpeed / math.max(maxSpeed, 1)
		HUD.ThrFill.AnchorPoint      = Vector2.new(0, 0.5)
		HUD.ThrFill.Position         = UDim2.new(0.5, 0, 0.5, 0)
		HUD.ThrFill.Size             = UDim2.new(0.5 * thrPct, 0, 1, 0)
		HUD.ThrFill.BackgroundColor3 = PALETTE.primary

		-- ----------------------------------------------------------------
		-- TARGETING + LEAD INDICATOR
		-- ----------------------------------------------------------------
		state.candidateTimer = state.candidateTimer - dt
		if state.candidateTimer <= 0 then
			state.candidateTimer = CANDIDATE_REFRESH
			state.candidates = refreshCandidates(state.config.Faction)
		end

		-- Muso reale nel mondo (modello rovesciato: muso = -LookVector)
		local noseWorld = state.primary.CFrame.LookVector

		local newTarget = pickTarget(state.candidates, noseWorld, state.primary.Position)
		state.target = newTarget

		if state.target then
			local tRoot = state.target:FindFirstChild("HumanoidRootPart")
				or state.target:FindFirstChildWhichIsA("BasePart")

			if tRoot then
				local tPos  = tRoot.Position
				local tVel  = tRoot.AssemblyLinearVelocity
				local dist  = (tPos - state.primary.Position).Magnitude

				state.leadWorld  = tPos + tVel * (dist / LASER_SPEED)
				local leadSP     = worldToScreen(state.leadWorld)
				state.leadScreen = leadSP

				if leadSP then
					HUD.LeadIndicator.Visible  = true
					HUD.LeadIndicator.Position = UDim2.new(0, leadSP.X, 0, leadSP.Y)

					local vpSize   = camera.ViewportSize
					local center   = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
					state.aligned  = (leadSP - center).Magnitude < ALIGN_TOL_PX

					local aimColor = state.aligned and PALETTE.good or PALETTE.primary
					HUD.LeadStroke.Color      = aimColor
					HUD.InnerRingStroke.Color = aimColor
				else
					HUD.LeadIndicator.Visible = false
					HUD.InnerRingStroke.Color = PALETTE.primary
					state.aligned = false
				end

				-- Bounding box
				local minX, minY, maxX, maxY = getModelScreenRect(state.target)
				if minX then
					local pad = 6
					minX = minX - pad; minY = minY - pad
					maxX = maxX + pad; maxY = maxY + pad
					local w = maxX - minX
					local h = maxY - minY
					HUD.BoxLines[1].Position = UDim2.new(0, minX, 0, minY)
					HUD.BoxLines[1].Size     = UDim2.new(0, w, 0, 1.5)
					HUD.BoxLines[2].Position = UDim2.new(0, minX, 0, maxY)
					HUD.BoxLines[2].Size     = UDim2.new(0, w, 0, 1.5)
					HUD.BoxLines[3].Position = UDim2.new(0, minX, 0, minY)
					HUD.BoxLines[3].Size     = UDim2.new(0, 1.5, 0, h)
					HUD.BoxLines[4].Position = UDim2.new(0, maxX, 0, minY)
					HUD.BoxLines[4].Size     = UDim2.new(0, 1.5, 0, h)
					for _, l in ipairs(HUD.BoxLines) do l.Visible = true end
				else
					for _, l in ipairs(HUD.BoxLines) do l.Visible = false end
				end
			else
				hideTargetUI()
				HUD.InnerRingStroke.Color = PALETTE.primary
			end
		else
			hideTargetUI()
			HUD.InnerRingStroke.Color = PALETTE.primary
		end
	end

	-- Posizione crosshair UI
	if state.mode == "combat" and not state.freeLook then
		local vpSize = camera.ViewportSize
		HUD.Crosshair.Position = UDim2.new(
			0, vpSize.X * 0.5 + state.crosshairOffset.X,
			0, vpSize.Y * 0.5 + state.crosshairOffset.Y
		)
	end

	-- Replica setpoint al server ~10Hz
	replicateAccum = replicateAccum + dt
	if state.engineOn and replicateAccum >= 0.1 and state.gyro and state.velocity then
		replicateAccum = 0
		ShipEvent:FireServer("DrivePhysics", {
			CFrame   = state.gyro.CFrame,
			Velocity = state.velocity.Velocity,
		})
	end

	-- ========================================================================
	-- HUD UPDATES
	-- ========================================================================
	HUD.SpeedValue.Text   = string.format("%d", math.floor(math.abs(state.currentSpeed) + 0.5))
	HUD.SpeedBarFill.Size = UDim2.new(math.clamp(math.abs(state.currentSpeed) / maxSpeed, 0, 1), 0, 1, 0)

	local altY = state.primary.Position.Y
	HUD.AltValue.Text = string.format("%d", math.floor(altY))
	local clampedY = math.clamp(altY, -500, 1500)
	local norm = 1 - (clampedY + 500) / 2000
	HUD.AltNeedle.Position = UDim2.new(0.5, 0, norm, 0)

	local look  = state.primary.CFrame.LookVector
	local right = state.primary.CFrame.RightVector
	HUD.Pitch.Text   = string.format("%+.0f°", math.deg(math.asin(math.clamp(look.Y, -1, 1))))
	HUD.Roll.Text    = string.format("%+.0f°", math.deg(math.asin(math.clamp(right.Y, -1, 1))))
	HUD.Heading.Text = string.format("%03d°",  (math.deg(math.atan2(-look.X, -look.Z)) + 360) % 360)

	-- Mode chip
	local newMode
	if not state.engineOn then
		newMode = "ENGINE OFF"
		HUD.ModeChip.BackgroundColor3 = PALETTE.danger
	elseif state.mode == "hangar" then
		newMode = "HANGAR"
		HUD.ModeChip.BackgroundColor3 = PALETTE.primaryDim
	else
		newMode = "COMBAT"
		HUD.ModeChip.BackgroundColor3 = PALETTE.good
	end
	if HUD.ModeLabel.Text ~= newMode then
		HUD.ModeLabel.Text = newMode
	end

	-- Reticolo visibile solo in combat
	HUD.Reticle.Visible = (state.mode == "combat")
end)

-- ============================================================================
-- SHOOTING
-- ============================================================================

local function tryShoot()
	if not state.ship or not state.primary then return end
	if not state.engineOn then return end
	if state.mode ~= "combat" then return end

	local now = os.clock()
	if now - state.lastShot < state.config.ReloadSpeed then return end
	state.lastShot = now

	-- Punto di convergenza: lungo il muso, alla distanza del bersaglio
	local noseWorld = state.primary.CFrame.LookVector
	local convDist  = DEFAULT_CONV_DIST

	if state.target then
		local tRoot = state.target:FindFirstChild("HumanoidRootPart")
			or state.target:FindFirstChildWhichIsA("BasePart")
		if tRoot then
			convDist = (tRoot.Position - state.primary.Position).Magnitude
		end
	end

	local converge = state.primary.Position + noseWorld * convDist

	-- Gimbal assist: se il lead e' entro GIMBAL_TOL_PX dal centro schermo,
	-- spostiamo il convergence point verso il lead world
	if state.leadWorld and state.leadScreen then
		local vpSize = camera.ViewportSize
		local center = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
		local dist2D = (state.leadScreen - center).Magnitude
		if dist2D < GIMBAL_TOL_PX then
			local t = 1 - (dist2D / GIMBAL_TOL_PX)
			converge = converge:Lerp(state.leadWorld, t)
		end
	end

	ShipEvent:FireServer("Shoot", { Converge = converge })
	pulseRingOnFire()
end

-- ============================================================================
-- INPUT
-- ============================================================================

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not state.ship then return end
		state.shooting = true
		task.spawn(function()
			while state.shooting and state.ship do
				tryShoot()
				task.wait(0.02)
			end
		end)

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if state.ship and state.mode == "combat" then
			state.zoomMode = true
		end

	elseif input.KeyCode == Enum.KeyCode.R then
		if not state.ship then return end
		state.engineOn = not state.engineOn
		if not state.engineOn then
			state.currentSpeed = 0
			state.flightVel    = Vector3.zero
		else
			state.aimCFrame = state.primary and state.primary.CFrame or nil
		end
		ShipEvent:FireServer("EngineToggle", { State = state.engineOn })

	elseif input.KeyCode == Enum.KeyCode.N then
		if not state.ship then return end
		if state.mode == "hangar" then
			setMode("combat")
			state.sfoils = true
			ShipEvent:FireServer("ToggleSfoils", { State = true })
		else
			setMode("hangar")
			state.sfoils = false
			ShipEvent:FireServer("ToggleSfoils", { State = false })
		end

	elseif input.KeyCode == Enum.KeyCode.C then
		if not state.ship or state.mode ~= "combat" then return end
		state.freeLook = not state.freeLook
		if state.freeLook then
			local look = state.primary.CFrame.LookVector
			state.hoverYaw   = math.atan2(-look.X, -look.Z)
			state.hoverPitch = -0.15
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		state.shooting = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		state.zoomMode = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not state.ship then return end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local inHangar   = (state.mode == "hangar")
		local inFreeLook = (state.mode == "combat" and state.freeLook)

		if inHangar or inFreeLook then
			-- Orbita libera con mouse
			state.hoverYaw   = state.hoverYaw   - input.Delta.X * 0.005
			state.hoverPitch = math.clamp(state.hoverPitch - input.Delta.Y * 0.005, -1.45, 1.45)
		elseif state.mode == "combat" then
			-- Deflessione crosshair (X non negato: la negazione avviene in cxNorm)
			local newOffset = state.crosshairOffset
				+ Vector2.new(input.Delta.X, input.Delta.Y) * CROSSHAIR_SENS
			local mag = newOffset.Magnitude
			if mag > CROSSHAIR_MAX_R then
				newOffset = newOffset / mag * CROSSHAIR_MAX_R
			end
			state.crosshairOffset = newOffset
		end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if state.mode == "hangar" or (state.mode == "combat" and state.freeLook) then
			state.hoverDistance = math.clamp(
				state.hoverDistance - input.Position.Z * 4, MIN_HOVER, MAX_HOVER
			)
		else
			state.chaseDistance = math.clamp(
				state.chaseDistance - input.Position.Z * 4, MIN_CHASE, MAX_CHASE
			)
		end
	end
end)

-- ============================================================================
-- Respawn: pulizia stato
-- ============================================================================
LocalPlayer.CharacterAdded:Connect(function()
	stopFlight()
end)
