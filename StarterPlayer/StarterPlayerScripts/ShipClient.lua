-- ShipClient.lua
-- Posizione: StarterPlayer/StarterPlayerScripts/ShipClient
--
-- Un singolo LocalScript che gestisce per qualsiasi nave:
--   - Controllo di volo (Cruise / Hover) e camera (CameraPart / ZoomPart)
--   - Apertura/chiusura ali (N)  e sparo (LMB)
--   - HUD "miracoloso" (reticle reattivo, throttle arc, altimetro,
--     reload bar, modulo info nave, scanline + vignetta)
--
-- Una nave e' identificata come un Model che ha un VehicleSeat e una
-- CameraPart figlia. Tutta la config arriva dagli Attributes del Model:
--   Damage / MaxSpeed / FireSound / ReloadSpeed / CanHover

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local Workspace          = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local mouse       = LocalPlayer:GetMouse()
local camera      = Workspace.CurrentCamera

local FlightEvents = ReplicatedStorage:WaitForChild("FlightEvents")
local ShipEvent    = FlightEvents:WaitForChild("ShipEvent")

-- ============================================================================
-- COLORS / VISUAL TOKENS
-- ============================================================================
local PALETTE = {
	bg          = Color3.fromRGB(8, 12, 18),
	panel       = Color3.fromRGB(14, 22, 30),
	primary     = Color3.fromRGB(124, 220, 255),   -- cyan
	primaryDim  = Color3.fromRGB(52, 110, 138),
	accent      = Color3.fromRGB(255, 200, 87),    -- amber
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
		Parent   = parent,
		Color    = color,
		Transparency = transparency or NumberSequence.new(0),
		Rotation = rotation or 0,
	})
end

-- Costruisce un ScreenGui completo e ritorna le maniglie a ogni componente.
local function buildHud()
	local gui = new("ScreenGui", {
		Name           = "ShipHUD",
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		DisplayOrder   = 10,
		Enabled        = false,
		Parent         = PlayerGui,
	})

	-- ---- Vignette (gradient-only, niente asset dependency)
	local vignetteFrame = new("Frame", {
		Name                   = "VignetteFrame",
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

	-- Outer rotating ring
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

	-- Inner solid ring (target indicator)
	local innerRing = new("Frame", {
		Name                   = "InnerRing",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(54, 54),
		BackgroundTransparency = 1,
		Parent                 = reticle,
	})
	stroke(innerRing, PALETTE.primary, 1.5, 0.1)
	corner(innerRing, 999)

	-- Center dot
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

	-- Tick marks (N/E/S/W)
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
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0, 0),
			Size                   = UDim2.fromOffset(2, 14),
			BackgroundColor3       = PALETTE.primary,
			BorderSizePixel        = 0,
			Parent                 = tick,
		})
		new("Frame", {
			AnchorPoint            = Vector2.new(0.5, 1),
			Position               = UDim2.new(0.5, 0, 1, 0),
			Size                   = UDim2.fromOffset(2, 14),
			BackgroundColor3       = PALETTE.primary,
			BorderSizePixel        = 0,
			Parent                 = tick,
		})
	end

	-- Reload arc (under the reticle, fills clockwise via UIGradient offset)
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
			NumberSequenceKeypoint.new(0,    0),
			NumberSequenceKeypoint.new(0.001, 0),
			NumberSequenceKeypoint.new(0.002, 1),
			NumberSequenceKeypoint.new(1,    1),
		}),
		Rotation = -90,
	})

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

	-- Accent bar on the left side of the card
	local accentBar = new("Frame", {
		Size              = UDim2.new(0, 3, 1, -16),
		Position          = UDim2.new(0, 0, 0, 8),
		BackgroundColor3  = PALETTE.primary,
		BorderSizePixel   = 0,
		Parent            = infoCard,
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

	-- Mode chip
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
		Text                   = "CRUISE",
		Parent                 = modeChip,
	})

	-- Hover badge (only when CanHover is on)
	local hoverChip = new("Frame", {
		Name                   = "HoverChip",
		AnchorPoint            = Vector2.new(0, 1),
		Position               = UDim2.new(0, 136, 1, -10),
		Size                   = UDim2.fromOffset(90, 22),
		BackgroundColor3       = PALETTE.accent,
		BackgroundTransparency = 0.9,
		BorderSizePixel        = 0,
		Visible                = false,
		Parent                 = infoCard,
	})
	corner(hoverChip, 3)
	stroke(hoverChip, PALETTE.accent, 1, 0.4)
	new("TextLabel", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 11,
		TextColor3             = PALETTE.accent,
		Text                   = "HOVER [N]",
		Parent                 = hoverChip,
	})

	-- ---- TOP-LEFT (sotto InfoCard): Boost gauge -------------------------
	local boostCard = new("Frame", {
		Name                   = "Boost",
		Position               = UDim2.fromOffset(28, 28 + 96 + 8),
		Size                   = UDim2.fromOffset(280, 28),
		BackgroundColor3       = PALETTE.panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel        = 0,
		Parent                 = gui,
	})
	corner(boostCard, 4)
	stroke(boostCard, PALETTE.primaryDim, 1, 0.3)

	new("TextLabel", {
		Position               = UDim2.fromOffset(12, 8),
		Size                   = UDim2.fromOffset(60, 14),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 10,
		TextColor3             = PALETTE.textDim,
		TextXAlignment         = Enum.TextXAlignment.Left,
		Text                   = "BOOST",
		Parent                 = boostCard,
	})

	local boostBarBg = new("Frame", {
		Position               = UDim2.fromOffset(72, 10),
		Size                   = UDim2.new(1, -84, 0, 8),
		BackgroundColor3       = PALETTE.bg,
		BorderSizePixel        = 0,
		Parent                 = boostCard,
	})
	corner(boostBarBg, 3)

	local boostBarFill = new("Frame", {
		Size                   = UDim2.new(1, 0, 1, 0),
		BackgroundColor3       = PALETTE.accent,
		BorderSizePixel        = 0,
		Parent                 = boostBarBg,
	})
	corner(boostBarFill, 3)

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

	-- Speed fill bar
	local speedBarBg = new("Frame", {
		Position               = UDim2.fromOffset(14, 60),
		Size                   = UDim2.new(1, -28, 0, 4),
		BackgroundColor3       = PALETTE.bg,
		BorderSizePixel        = 0,
		Parent                 = speedCard,
	})
	corner(speedBarBg, 2)
	local speedBarFill = new("Frame", {
		Size                   = UDim2.new(0, 0, 1, 0),
		BackgroundColor3       = PALETTE.primary,
		BorderSizePixel        = 0,
		Parent                 = speedBarBg,
	})
	corner(speedBarFill, 2)
	gradient(speedBarFill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, PALETTE.primary),
		ColorSequenceKeypoint.new(1, PALETTE.accent),
	}))

	-- ---- RIGHT (above Altitude): Controls / keybinds --------------------
	-- Card piu' STRETTA (180) ma piu' ALTA (260) con righe piu' grandi e
	-- testo piu' leggibile. Sta sopra l'altimetro con un gap di 12.
	local ctrlCard = new("Frame", {
		Name                   = "Controls",
		AnchorPoint            = Vector2.new(1, 1),
		Position               = UDim2.new(1, -28, 1, -28 - 240 - 12),
		Size                   = UDim2.fromOffset(180, 314),  -- aumentato per ospitare V e SHIFT
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

	-- Linea di separazione sottile sotto il titolo
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
		Parent          = controlsRowContainer,
		Padding         = UDim.new(0, 3),
		SortOrder       = Enum.SortOrder.LayoutOrder,
		FillDirection   = Enum.FillDirection.Vertical,
	})

	local function controlRow(order, keyText, actionText)
		local row = new("Frame", {
			Name                   = "Row_" .. keyText,
			Size                   = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder            = order,
			Parent                 = controlsRowContainer,
		})

		-- Tasto: pill scuro con bordo cyan, piu' compatto in larghezza
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

	controlRow(1,  "R",     "Engine")
	controlRow(2,  "W S",   "Accel/Brake")
	controlRow(3,  "A D",   "Roll")
	controlRow(4,  "Q E",   "Down/Up")
	local qeRow = nil  -- riga Q/E ora sempre visibile (vale anche in flight)
	controlRow(5,  "SHIFT", "Boost")
	controlRow(6,  "V",     "Free Cam")
	controlRow(7,  "N",     "Toggle Mode")
	controlRow(8,  "LMB",   "Fire")
	controlRow(9,  "RMB",   "Zoom Aim")
	controlRow(10, "WHEEL", "Cam Zoom")

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

	-- Vertical ladder/track
	local altTrack = new("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.new(0.5, 0, 0, 28),
		Size                   = UDim2.new(0, 4, 1, -42),
		BackgroundColor3       = PALETTE.bg,
		BorderSizePixel        = 0,
		Parent                 = altCard,
	})
	corner(altTrack, 2)

	local altNeedle = new("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.new(0.5, 0, 0.5, 0),
		Size                   = UDim2.new(0, 24, 0, 2),
		BackgroundColor3       = PALETTE.primary,
		BorderSizePixel        = 0,
		Parent                 = altTrack,
	})

	-- Tick marks down the side of the track
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
		Position               = UDim2.fromOffset(14, 22),
		Size                   = UDim2.new(1, -28, 0, 6),
		BackgroundColor3       = PALETTE.bg,
		BorderSizePixel        = 0,
		Parent                 = thrCard,
	})
	corner(thrBarBg, 3)

	-- Center notch for "zero" throttle
	new("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.new(0.5, 0, 0, -2),
		Size                   = UDim2.fromOffset(1, 10),
		BackgroundColor3       = PALETTE.textDim,
		BorderSizePixel        = 0,
		Parent                 = thrBarBg,
	})

	local thrFill = new("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.new(0.5, 0, 0.5, 0),
		Size                   = UDim2.fromScale(0, 1),
		BackgroundColor3       = PALETTE.primary,
		BorderSizePixel        = 0,
		Parent                 = thrBarBg,
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
		Gui            = gui,
		Reticle        = reticle,
		OuterRing      = outerRing,
		InnerRing      = innerRing,
		ReloadGradient = reloadGradient,
		ShipLabel      = shipLabel,
		SubLabel       = subLabel,
		ModeChip       = modeChip,
		ModeLabel      = modeLabel,
		HoverChip      = hoverChip,
		SpeedValue     = speedValue,
		SpeedBarFill   = speedBarFill,
		AltValue       = altValue,
		AltNeedle      = altNeedle,
		AltTrack       = altTrack,
		ThrFill        = thrFill,
		Pitch          = pitchValue,
		Roll           = rollValue,
		Heading        = headingValue,
		Dmg            = dmgValue,
		HitFlash       = hitFlash,
		ControlsCard   = ctrlCard,
		QERow          = qeRow,
		BoostFill      = boostBarFill,
	}
end

local HUD = buildHud()

-- ============================================================================
-- HUD HELPERS  (animazioni, reattivita')
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

local CRUISE_SPEED_FACTOR = 0.5    -- W in cruise = 50% MaxSpeed
local FULL_SPEED_FACTOR   = 1.0
local HOVER_HORIZ_FACTOR  = 0.4    -- velocita' WASD in hover come % di MaxSpeed
local HOVER_HORIZ_CAP     = 80
local HOVER_VERT_SPEED    = 45     -- studs/sec Q/E
local FLIGHT_CHASE_BACK   = 22     -- offset chase-cam dietro la nave se manca CameraPart
local FLIGHT_CHASE_UP     = 7
local AIM_TURN_SMOOTH     = 8      -- snappy ma non instantaneo

-- Boost / afterburner (Shift)
local BOOST_MULTIPLIER    = 1.7    -- moltiplicatore di fullMax quando attivo
local BOOST_DRAIN_PER_SEC = 0.35   -- gauge drain (1.0 gauge = piena)
local BOOST_REGEN_PER_SEC = 0.18   -- gauge regen quando rilasciato
local BOOST_MIN_TO_START  = 0.10   -- soglia per attivare boost
local BOOST_FOV_BONUS     = 12     -- FOV extra a boost pieno
local BASE_FOV            = 70     -- FOV "a regime"

-- Camera recoil (kick quando si spara)
local RECOIL_KICK_BACK    = 0.5    -- studs di kick indietro per colpo
local RECOIL_KICK_PITCH   = 0.018  -- radianti di kick verso l'alto per colpo
local RECOIL_DECAY        = 11     -- lambda damping del recoil verso zero
local RECOIL_MAX_BACK     = 2.5    -- cap del kick accumulato
local RECOIL_MAX_PITCH    = 0.09

-- Free cam (V per toggle chase <-> free orbit)
-- In free cam la nave mantiene la rotta corrente (heading bloccato), il mouse
-- ruota la camera attorno alla nave (yaw + pitch), il wheel regola la distanza.
-- Per tornare a sterzare col mouse, ripremi V.
local FREE_MIN_DIST       = 12
local FREE_MAX_DIST       = 80
local FREE_DEFAULT_DIST   = 28
local FREE_MOUSE_SENS     = 0.005   -- rad / pixel

local state = {
	ship           = nil,
	seat           = nil,
	primary        = nil,
	gyro           = nil,
	velocity       = nil,
	camPart        = nil,
	zoomPart       = nil,

	-- mode: "hover" | "flight" (zoomMode e' separato; e' la mira RMB)
	mode           = "flight",
	sfoils         = false,

	-- engine master switch (premi R per avviare/spegnere)
	engineOn       = false,

	-- flight
	currentSpeed   = 0,
	rollAngle      = 0,
	chaseDistance  = 0,         -- mouse wheel in flight
	aimCFrame      = nil,       -- target CFrame del gyro, lerped per fluidita'

	-- hover (free orbit camera around ship)
	hoverYaw       = 0,
	hoverPitch     = -0.15,
	hoverDistance  = 28,
	heldHeading    = nil,       -- CFrame da mantenere quando WASD = 0

	-- zoom / aim
	zoomMode       = false,

	-- camera view (chase <-> free orbit) -- gestito con V
	camView        = "chase",         -- "chase" | "free"
	freeYaw        = 0,
	freePitch      = -0.15,
	freeDistance   = FREE_DEFAULT_DIST,

	-- camera recoil (decay per-frame)
	recoilBack     = 0,
	recoilPitch    = 0,

	-- boost / afterburner (hold Shift)
	boost          = 1,               -- 0..1 gauge
	boostActive    = false,
	boostFactor    = 1,                -- 1..BOOST_MULTIPLIER (smoothed)

	-- shooting
	shooting       = false,
	lastShot       = -math.huge,

	config = { Damage = 30, MaxSpeed = 150, ReloadSpeed = 0.18, CanHover = false, FireSound = "" },
}

local MIN_CHASE, MAX_CHASE = -10, 80
local MIN_HOVER, MAX_HOVER = 12, 70

local function readShipConfig(ship)
	state.config.Damage      = ship:GetAttribute("Damage")      or 30
	state.config.MaxSpeed    = ship:GetAttribute("MaxSpeed")    or 150
	state.config.ReloadSpeed = ship:GetAttribute("ReloadSpeed") or 0.18
	state.config.CanHover    = ship:GetAttribute("CanHover")    or false
	state.config.FireSound   = ship:GetAttribute("FireSound")   or ""
end

-- ----------------------------------------------------------------------------
-- Input helpers: leggiamo la tastiera direttamente (NIENTE VehicleSeat.Throttle
-- o .Steer) cosi' l'orientamento del seat non puo' invertire i comandi.
-- ----------------------------------------------------------------------------
local function key(k) return UserInputService:IsKeyDown(k) end
local function axis(pos, neg)
	return (key(pos) and 1 or 0) - (key(neg) and 1 or 0)
end

local function readMoveInput()
	return
		axis(Enum.KeyCode.W, Enum.KeyCode.S),  -- throttle  (W=+1, S=-1)
		axis(Enum.KeyCode.D, Enum.KeyCode.A),  -- right   (D=+1, A=-1)
		axis(Enum.KeyCode.E, Enum.KeyCode.Q)   -- up      (E=+1, Q=-1)
end

-- ----------------------------------------------------------------------------
local function setMouseLocked(locked)
	if locked then
		UserInputService.MouseBehavior  = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior  = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function setMode(newMode)
	if state.mode == newMode then return end
	state.mode = newMode
	if newMode == "hover" then
		-- Inizializza yaw/pitch dalla direzione attuale della nave cosi'
		-- l'orbital cam parte allineata col muso.
		if state.primary then
			local look = state.primary.CFrame.LookVector
			state.hoverYaw   = math.atan2(-look.X, -look.Z)
			state.hoverPitch = -0.15
			state.heldHeading = state.primary.CFrame
		end
		setMouseLocked(true)
	else
		state.heldHeading = nil
		state.rollAngle   = 0
		setMouseLocked(false)
	end
end

local function startFlight(ship, seat)
	state.ship      = ship
	state.seat      = seat
	state.primary   = ship.PrimaryPart or ship:FindFirstChildWhichIsA("BasePart")
	state.camPart    = ship:FindFirstChild("CameraPart",  true)
	state.zoomPart   = ship:FindFirstChild("ZoomPart",    true)
	state.gyro      = state.primary and state.primary:WaitForChild("ShipGyro",     2)
	state.velocity  = state.primary and state.primary:WaitForChild("ShipVelocity", 2)
	state.sfoils    = false
	state.engineOn  = false
	state.currentSpeed = 0
	state.rollAngle = 0
	state.chaseDistance = 0
	state.aimCFrame = state.primary and state.primary.CFrame or nil
	state.zoomMode  = false
	state.lastShot  = -math.huge

	-- reset vista/boost/recoil ad ogni entrata
	state.camView      = "chase"
	state.freeYaw      = 0
	state.freePitch    = -0.15
	state.freeDistance = FREE_DEFAULT_DIST
	state.recoilBack   = 0
	state.recoilPitch  = 0
	state.boost        = 1
	state.boostActive  = false
	state.boostFactor  = 1

	readShipConfig(ship)

	-- HUD: setup + reveal
	HUD.ShipLabel.Text = ship.Name:upper()
	HUD.SubLabel.Text  = "STARFIGHTER  /  ONLINE  /  PILOT: " .. LocalPlayer.Name:upper()
	HUD.Dmg.Text       = string.format("%d", state.config.Damage)
	HUD.HoverChip.Visible = state.config.CanHover
	HUD.Gui.Enabled       = true

	-- Reveal animation (telemetry slides in)
	for _, name in ipairs({ "InfoCard", "Speed", "Altitude", "Throttle", "Telemetry", "Controls", "Boost" }) do
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

	-- Mode iniziale: hover se supportata, altrimenti volo diretto
	state.mode = nil
	setMode(state.config.CanHover and "hover" or "flight")
end

local function stopFlight()
	if state.seat == nil then return end
	camera.CameraType   = Enum.CameraType.Custom
	camera.FieldOfView  = BASE_FOV  -- ripristina FOV (potrebbe essere alterato da cockpit/boost)
	mouse.TargetFilter  = nil
	setMouseLocked(false)
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.CameraOffset = Vector3.zero end
	state.boostActive = false

	-- HUD fade out
	for _, name in ipairs({ "InfoCard", "Speed", "Altitude", "Throttle", "Telemetry", "Controls", "Boost" }) do
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
end

-- ============================================================================
-- RENDER LOOP
-- ============================================================================

local outerSpin       = 0
local replicateAccum  = 0

-- Smooth-lerp helper resistente al framerate
local function damp(current, target, lambda, dt)
	return current + (target - current) * (1 - math.exp(-lambda * dt))
end

RunService.RenderStepped:Connect(function(dt)
	-- Animazione costante: outer ring spin
	outerSpin = (outerSpin + dt * 36) % 360
	HUD.OuterRing.Rotation = outerSpin

	-- Reload arc progress
	if state.ship then
		local since = os.clock() - state.lastShot
		local pct   = math.clamp(since / math.max(state.config.ReloadSpeed, 0.01), 0, 1)
		HUD.ReloadGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,                       0),
			NumberSequenceKeypoint.new(math.max(pct, 0.001),    0),
			NumberSequenceKeypoint.new(math.min(pct + 0.001, 1), 1),
			NumberSequenceKeypoint.new(1,                       1),
		})
	end

	-- Detect seat changes
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
	local zoomPart = state.zoomPart
	local camPart  = state.camPart

	-- Decay del camera recoil verso zero (frame-rate independent)
	state.recoilBack  = damp(state.recoilBack,  0, RECOIL_DECAY, dt)
	state.recoilPitch = damp(state.recoilPitch, 0, RECOIL_DECAY, dt)

	-- Regen del boost gauge (sempre attivo quando NON stai boostando)
	if not state.boostActive and state.boost < 1 then
		state.boost = math.min(1, state.boost + BOOST_REGEN_PER_SEC * dt)
	end

	-- Smoothing del boost factor verso il target (per FOV/velocita' senza scatti)
	local targetBoostFactor = (state.boostActive and state.boost > 0)
		and (1 + (BOOST_MULTIPLIER - 1) * math.clamp(state.boost, 0, 1))
		or 1
	state.boostFactor = damp(state.boostFactor, targetBoostFactor, 8, dt)

	if state.zoomMode and zoomPart then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame     = zoomPart.CFrame
	elseif state.mode == "hover" then
		-- Camera orbitale liberamente controllabile col mouse (LockCenter)
		local shipPos = state.primary.Position
		local rot     = CFrame.Angles(0, state.hoverYaw, 0) * CFrame.Angles(state.hoverPitch, 0, 0)
		local offset  = rot * Vector3.new(0, 0, state.hoverDistance)
		local camPos  = shipPos + Vector3.new(0, 2, 0) + offset
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame     = CFrame.lookAt(camPos, shipPos + Vector3.new(0, 2, 0))
	elseif state.camView == "free" then
		-- Free cam: orbita liberamente attorno alla nave (yaw/pitch col mouse,
		-- wheel per la distanza). La nave NON segue piu' il cursore in questa
		-- modalita': mantiene l'ultimo heading (impostato sotto in PHYSICS).
		local shipPos = state.primary.Position
		local rot     = CFrame.Angles(0, state.freeYaw, 0) * CFrame.Angles(state.freePitch, 0, 0)
		local offset  = rot * Vector3.new(0, 0, state.freeDistance)
		local camPos  = shipPos + Vector3.new(0, 2, 0) + offset
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame     = CFrame.lookAt(camPos, shipPos + Vector3.new(0, 2, 0))
	else
		-- Camera chase: la CameraPart E' la camera. Usiamo la sua CFrame
		-- completa (posizione + orientazione). Il wheel-zoom scorre lungo
		-- l'asse +Z locale della CameraPart (verso il dietro in Roblox).
		camera.CameraType = Enum.CameraType.Scriptable
		if camPart then
			camera.CFrame = camPart.CFrame * CFrame.new(0, 0, state.chaseDistance)
		else
			-- Fallback se manca CameraPart: chase generico dietro la nave.
			local shipPos = state.primary.Position
			local shipFwd = state.primary.CFrame.LookVector
			local shipUp  = state.primary.CFrame.UpVector
			local camPos  = shipPos
				- shipFwd * (FLIGHT_CHASE_BACK + state.chaseDistance)
				+ shipUp  * FLIGHT_CHASE_UP
			camera.CFrame = CFrame.lookAt(camPos, shipPos + shipFwd * 200, shipUp)
		end
	end

	-- Camera recoil + boost FOV: applicati sopra qualsiasi base CFrame scelta.
	-- Recoil: kick indietro lungo +Z locale (la camera "rincula") + pitch in alto.
	if state.recoilBack ~= 0 or state.recoilPitch ~= 0 then
		camera.CFrame = camera.CFrame
			* CFrame.new(0, 0, state.recoilBack)
			* CFrame.Angles(state.recoilPitch, 0, 0)
	end

	-- FOV: boost allarga il FOV. Free cam tiene il BASE_FOV.
	local boostFov  = (state.boostFactor - 1) / math.max(BOOST_MULTIPLIER - 1, 0.001) * BOOST_FOV_BONUS
	camera.FieldOfView = BASE_FOV + boostFov

	mouse.TargetFilter = state.ship

	-- ========================================================================
	-- PHYSICS
	-- ========================================================================
	local fwdInput, rgtInput, vertInput = readMoveInput()
	local maxSpeed = math.max(state.config.MaxSpeed, 1)

	-- Motore SPENTO: HUD throttle vuota e velocita' a zero. Salta i body movers.
	if not state.engineOn then
		state.currentSpeed = 0
		HUD.ThrFill.Size = UDim2.new(0, 0, 1, 0)

	elseif state.mode == "hover" then
		-- Movimento WASD relativo al forward piatto della camera; Q/E vertical
		local camFwd   = camera.CFrame.LookVector
		local flatFwd  = Vector3.new(camFwd.X, 0, camFwd.Z)
		if flatFwd.Magnitude < 0.05 then
			flatFwd = Vector3.new(0, 0, -1)
		end
		flatFwd = flatFwd.Unit
		-- right = forward x up (Roblox: forward (0,0,-1), up (0,1,0) -> right (+1,0,0))
		local flatRgt = Vector3.new(-flatFwd.Z, 0, flatFwd.X)

		local moveDir = flatFwd * fwdInput + flatRgt * rgtInput
		local moving  = moveDir.Magnitude > 0.05
		local hSpeed  = math.min(maxSpeed * HOVER_HORIZ_FACTOR, HOVER_HORIZ_CAP)
		local horiz   = moving and moveDir.Unit * hSpeed or Vector3.zero
		local vert    = vertInput * HOVER_VERT_SPEED

		-- Hold posizione (Y=0 mantiene quota contro gravita') quando inerte
		state.velocity.Velocity = horiz + Vector3.new(0, vert, 0)

		-- Heading: la nave ruota verso la direzione di volo solo quando spingi
		-- WASD. Senza input mantiene l'ultimo heading (cosi' ti guardi attorno
		-- liberamente). BodyGyro.CFrame ignora la position, solo la rotazione.
		-- NOTA: il modello e' costruito col "muso" sul -LookVector del
		-- PrimaryPart. Per far avanzare il muso allineato a moveDir, il
		-- LookVector deve puntare al CONTRARIO di moveDir.
		if moving then
			state.heldHeading = CFrame.lookAt(Vector3.zero, -moveDir.Unit)
		end
		if state.heldHeading then
			state.gyro.CFrame = state.heldHeading
		else
			state.gyro.CFrame = state.primary.CFrame
		end

		-- Speed display (visivo)
		state.currentSpeed = state.velocity.Velocity.Magnitude

		-- Throttle bar: forward axis
		HUD.ThrFill.AnchorPoint = Vector2.new(fwdInput >= 0 and 0 or 1, 0.5)
		HUD.ThrFill.Position    = UDim2.new(0.5, 0, 0.5, 0)
		HUD.ThrFill.Size        = UDim2.new(0.5 * math.abs(fwdInput), 0, 1, 0)
		HUD.ThrFill.BackgroundColor3 = fwdInput >= 0 and PALETTE.primary or PALETTE.accent
	else
		-- FLIGHT mode -----------------------------------------------------
		-- Comportamento "inerziale":
		--   W  = accelera (la velocita' sale verso fullMax)
		--   S  = frena   (la velocita' scende verso 0, mai negativa)
		--   nessuno dei due = mantiene la velocita' corrente (drift)
		--   Q/E = spinta verticale up/down sempre attiva in volo
		--   Shift = boost: moltiplica fullMax per state.boostFactor (drena gauge)
		local baseFullMax = maxSpeed * (state.sfoils and FULL_SPEED_FACTOR or CRUISE_SPEED_FACTOR)
		local fullMax     = baseFullMax * state.boostFactor
		local accelRate   = maxSpeed * 0.7 * state.boostFactor
		local brakeRate   = maxSpeed * 1.4

		-- Drain del boost gauge (regen e' gestito fuori dal ramo flight cosi'
		-- ricarica anche in hover / engine off).
		if state.boostActive and state.boost > 0 then
			state.boost = math.max(0, state.boost - BOOST_DRAIN_PER_SEC * dt)
			if state.boost <= 0 then state.boostActive = false end
		end

		if fwdInput > 0 then
			state.currentSpeed = state.currentSpeed + accelRate * dt
		elseif fwdInput < 0 then
			state.currentSpeed = state.currentSpeed - brakeRate * dt
		end
		state.currentSpeed = math.clamp(state.currentSpeed, 0, fullMax)

		-- Roll da A/D: positivo = banking a destra (D)
		if rgtInput ~= 0 then
			state.rollAngle = state.rollAngle - rgtInput * 0.18
			state.rollAngle = math.clamp(state.rollAngle, -1.2, 1.2)
		else
			local a = state.rollAngle
			state.rollAngle = a - math.sign(a) * math.min(math.abs(a), dt * 4)
		end

		-- Aim verso il cursore in chase. In free cam invece l'heading e'
		-- BLOCCATO: la nave mantiene la rotazione corrente cosi' il mouse
		-- e' libero di orbitare la camera senza far virare la nave.
		local targetCFrame
		if state.camView == "free" then
			-- Tieni l'heading attuale (con piccolo lerp che lo agganciera' al
			-- gyro). Niente roll mentre ti guardi attorno.
			targetCFrame = state.primary.CFrame
		else
			local targetPos = mouse.Hit.Position
			if mouse.Target == nil then
				targetPos = camera.CFrame.Position + (mouse.UnitRay.Direction * 2000)
			end
			local aimDir     = (targetPos - state.primary.Position).Unit
			-- Il muso del modello e' sul -LookVector del PrimaryPart, quindi
			-- il LookVector deve puntare al CONTRARIO del cursore.
			local baseCFrame = CFrame.lookAt(state.primary.Position, state.primary.Position - aimDir)
			targetCFrame     = baseCFrame * CFrame.Angles(0, 0, state.rollAngle)
		end

		-- Smoothing: il setpoint del gyro si avvicina al target con un lerp
		-- frame-rate independent (lambda = "velocita' di inseguimento").
		-- Lambda alto = sterzata reattiva, basso = pesante/elegante.
		local AIM_LAMBDA = 6
		if not state.aimCFrame then
			state.aimCFrame = state.primary.CFrame
		end
		-- Ricostruiamo il CFrame target attorno alla posizione attuale (il
		-- gyro usa solo la rotazione, ma il Lerp di CFrame interpola anche
		-- la posizione: la teniamo allineata cosi' il blend e' pulito).
		local rotOnly = targetCFrame - targetCFrame.Position
		local desired = CFrame.new(state.primary.Position) * rotOnly
		state.aimCFrame = state.aimCFrame:Lerp(desired, 1 - math.exp(-AIM_LAMBDA * dt))
		state.gyro.CFrame = state.aimCFrame

		-- Velocita': avanti lungo il muso (-LookVector) + verticale Q/E.
		local forwardVel = -state.primary.CFrame.LookVector * state.currentSpeed
		local verticalVel = Vector3.new(0, vertInput * HOVER_VERT_SPEED, 0)
		state.velocity.Velocity = forwardVel + verticalVel

		-- Throttle bar: percentuale della velocita' attuale rispetto al massimo
		local thrPct = state.currentSpeed / math.max(fullMax, 1)
		HUD.ThrFill.AnchorPoint = Vector2.new(0, 0.5)
		HUD.ThrFill.Position    = UDim2.new(0.5, 0, 0.5, 0)
		HUD.ThrFill.Size        = UDim2.new(0.5 * thrPct, 0, 1, 0)
		HUD.ThrFill.BackgroundColor3 = PALETTE.primary
	end

	-- Replica setpoint al server ~10Hz (backup, se la network ownership zoppica)
	replicateAccum = replicateAccum + dt
	if state.engineOn and replicateAccum >= 0.1 then
		replicateAccum = 0
		ShipEvent:FireServer("DrivePhysics", {
			CFrame   = state.gyro.CFrame,
			Velocity = state.velocity.Velocity,
		})
	end

	-- ========================================================================
	-- HUD UPDATES
	-- ========================================================================
	HUD.SpeedValue.Text  = string.format("%d", math.floor(math.abs(state.currentSpeed) + 0.5))
	HUD.SpeedBarFill.Size = UDim2.new(math.clamp(math.abs(state.currentSpeed) / maxSpeed, 0, 1), 0, 1, 0)

	-- Altitude
	local altY = state.primary.Position.Y
	HUD.AltValue.Text = string.format("%d", math.floor(altY))
	local clampedY = math.clamp(altY, -500, 1500)
	local norm = 1 - (clampedY + 500) / 2000
	HUD.AltNeedle.Position = UDim2.new(0.5, 0, norm, 0)

	-- Telemetry
	local look  = state.primary.CFrame.LookVector
	local right = state.primary.CFrame.RightVector
	HUD.Pitch.Text   = string.format("%+.0f°", math.deg(math.asin(math.clamp(look.Y, -1, 1))))
	HUD.Roll.Text    = string.format("%+.0f°", math.deg(math.asin(math.clamp(right.Y, -1, 1))))
	HUD.Heading.Text = string.format("%03d°",  (math.deg(math.atan2(-look.X, -look.Z)) + 360) % 360)

	-- Mode chip (mostra anche vista cockpit e stato boost)
	local newMode
	if not state.engineOn then
		newMode = "ENGINE OFF"
		HUD.ModeChip.BackgroundColor3 = PALETTE.danger
	elseif state.mode == "hover" then
		newMode = "HOVER"
		HUD.ModeChip.BackgroundColor3 = PALETTE.accent
	elseif state.sfoils then
		newMode = "FULL THROTTLE"
		HUD.ModeChip.BackgroundColor3 = PALETTE.good
	else
		newMode = "CRUISE"
		HUD.ModeChip.BackgroundColor3 = PALETTE.primary
	end
	if state.mode == "flight" and state.camView == "free" then
		newMode = newMode .. " · FREE CAM"
	end
	if state.boostActive and state.boost > 0 then
		newMode = newMode .. " · BOOST"
		HUD.ModeChip.BackgroundColor3 = PALETTE.accent
	end
	if HUD.ModeLabel.Text ~= newMode then
		HUD.ModeLabel.Text = newMode
	end

	-- Boost bar fill + colore (cyan piena, ambra in scarica, rosso a secco)
	HUD.BoostFill.Size = UDim2.new(math.clamp(state.boost, 0, 1), 0, 1, 0)
	if state.boost <= 0.001 then
		HUD.BoostFill.BackgroundColor3 = PALETTE.danger
	elseif state.boostActive then
		HUD.BoostFill.BackgroundColor3 = PALETTE.accent
	else
		HUD.BoostFill.BackgroundColor3 = PALETTE.primary
	end

	-- Reticle: in hover non aiming col cursore, smorziamo il reticolo
	HUD.Reticle.Visible = (state.mode == "flight")
end)

-- ============================================================================
-- INPUT
-- ============================================================================

local function tryShoot()
	if not state.ship or not state.primary then return end
	if state.mode == "hover" then return end  -- in hover non si spara
	local now = os.clock()
	if now - state.lastShot < state.config.ReloadSpeed then return end
	state.lastShot = now

	-- In free cam non si mira col mouse (e' bloccato a orbitare la camera):
	-- i proiettili escono lungo il muso (-LookVector del PrimaryPart).
	local dir
	if state.camView == "free" then
		dir = (-state.primary.CFrame.LookVector).Unit
	else
		local targetPos = mouse.Hit.Position
		if mouse.Target == nil then
			targetPos = camera.CFrame.Position + (mouse.UnitRay.Direction * 2000)
		end
		dir = (targetPos - state.primary.Position).Unit
	end
	ShipEvent:FireServer("Shoot", { Direction = dir })
	pulseRingOnFire()

	-- Camera recoil: piccola scossa indietro + leggero pitch in alto.
	-- Si accumula sui colpi rapidi (capped) e decade nel render loop.
	state.recoilBack  = math.min(state.recoilBack  + RECOIL_KICK_BACK,  RECOIL_MAX_BACK)
	state.recoilPitch = math.min(state.recoilPitch + RECOIL_KICK_PITCH, RECOIL_MAX_PITCH)
end

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
		if state.ship then state.zoomMode = true end

	elseif input.KeyCode == Enum.KeyCode.R then
		if not state.ship then return end
		state.engineOn = not state.engineOn
		if not state.engineOn then
			state.currentSpeed = 0
		else
			-- Riaggancia il setpoint del gyro alla posizione corrente cosi'
			-- non c'e' un "salto" dal vecchio aim al nuovo all'accensione.
			state.aimCFrame = state.primary and state.primary.CFrame or nil
		end
		ShipEvent:FireServer("EngineToggle", { State = state.engineOn })

	elseif input.KeyCode == Enum.KeyCode.V then
		-- Toggle vista: chase <-> free orbit. Solo in flight (hover ha gia' free orbit).
		if not state.ship or state.mode ~= "flight" then return end
		if state.camView == "free" then
			state.camView = "chase"
			setMouseLocked(false)
		else
			-- Inizializza yaw/pitch dall'orientamento attuale della nave cosi'
			-- la camera non "salta" entrando in free cam. La nave ha il muso
			-- sul -LookVector, quindi guardiamo nella direzione opposta.
			if state.primary then
				local look = -state.primary.CFrame.LookVector
				state.freeYaw   = math.atan2(-look.X, -look.Z)
				state.freePitch = -0.15
			end
			state.camView = "free"
			setMouseLocked(true)
		end

	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		-- Hold Shift = boost (afterburner). Si attiva solo sopra la soglia minima
		-- e drena finche' tenuto premuto o finche' la gauge si svuota.
		if not state.ship or state.mode ~= "flight" or not state.engineOn then return end
		if state.boost >= BOOST_MIN_TO_START then
			state.boostActive = true
		end

	elseif input.KeyCode == Enum.KeyCode.N then
		if not state.ship then return end
		if state.config.CanHover then
			-- N alterna hover <-> flight; in flight apriamo le S-foils
			if state.mode == "hover" then
				setMode("flight")
				state.sfoils = true
				ShipEvent:FireServer("ToggleSfoils", { State = true })
			else
				setMode("hover")
				state.sfoils = false
				ShipEvent:FireServer("ToggleSfoils", { State = false })
			end
		else
			-- Niente hover: N alterna solo le S-foils
			state.sfoils = not state.sfoils
			ShipEvent:FireServer("ToggleSfoils", { State = state.sfoils })
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		state.shooting = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		state.zoomMode = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		state.boostActive = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not state.ship then return end

	-- Mouse delta -> orbital camera in hover OR in free cam (entrambe usano
	-- LockCenter quindi il delta arriva pulito).
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if state.mode == "hover" then
			state.hoverYaw   = state.hoverYaw   - input.Delta.X * 0.005
			state.hoverPitch = math.clamp(state.hoverPitch - input.Delta.Y * 0.005, -1.45, 1.45)
			return
		elseif state.camView == "free" then
			state.freeYaw   = state.freeYaw   - input.Delta.X * FREE_MOUSE_SENS
			state.freePitch = math.clamp(state.freePitch - input.Delta.Y * FREE_MOUSE_SENS, -1.45, 1.45)
			return
		end
	end

	-- Mouse wheel: hover -> orbit dist, free -> free dist, chase -> chase dist
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if state.mode == "hover" then
			state.hoverDistance = math.clamp(
				state.hoverDistance - input.Position.Z * 4, MIN_HOVER, MAX_HOVER
			)
		elseif state.camView == "free" then
			state.freeDistance = math.clamp(
				state.freeDistance - input.Position.Z * 4, FREE_MIN_DIST, FREE_MAX_DIST
			)
		else
			state.chaseDistance = math.clamp(
				state.chaseDistance - input.Position.Z * 4, MIN_CHASE, MAX_CHASE
			)
		end
	end
end)

-- ============================================================================
-- Quando il personaggio si rispawna, puliamo lo stato.
-- ============================================================================
LocalPlayer.CharacterAdded:Connect(function()
	stopFlight()
end)
