-- ShipClient.lua
-- Posizione: StarterPlayer/StarterPlayerScripts/ShipClient
--
-- Controller di volo a DUE FASI per nave pesante (ARC-170):
--
--   FASE A - HANGAR / CRUISE (stato di avvio di default)
--     * Ali (S-foils) chiuse, trail di punta SPENTI, armi DISABILITATE.
--     * Velocita' massima molto bassa (HANGAR_SPEED) per manovrare in hangar.
--     * Controllo ESCLUSIVO con WASD: W/S avanti/indietro, A/D virata piatta.
--     * Camera libera (orbit): guardi attorno alla nave senza cambiare rotta.
--
--   FASE B - COMBAT / THROTTLE (si attiva con N)
--     * Apre le 4 ali in X, trail di punta ACCESI, armi abilitate.
--     * Velocita' da combattimento alta, volo guidato dal mouse.
--     * Auto-banking (roll automatico in virata) + deriva inerziale (peso).
--     * Camera bloccata dietro la nave; C alterna il "free-look".
--     * Niente roll manuale (Q/E rimossi).
--
-- Una nave e' un Model con VehicleSeat + CameraPart. La config arriva dagli
-- Attributes del Model: Damage / MaxSpeed / FireSound / ReloadSpeed / Faction.

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

-- Deve combaciare con LASER_SPEED in ShipScript (server) per un lead corretto.
local LASER_SPEED = 750

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

	-- ---- Reticle (center) = mirino del MUSO della nave --------------------
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

	-- Inner solid ring (cambia colore quando il muso e' allineato col lead)
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

	-- ---- Mouse virtual crosshair (cursore di sterzo, solo COMBAT) ----------
	local crosshair = new("Frame", {
		Name                   = "Crosshair",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Visible                = false,
		ZIndex                 = 6,
		Parent                 = gui,
	})
	local crosshairRing = new("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent                 = crosshair,
	})
	stroke(crosshairRing, PALETTE.text, 1.4, 0.15)
	corner(crosshairRing, 999)
	new("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(3, 3),
		BackgroundColor3       = PALETTE.text,
		BorderSizePixel        = 0,
		Parent                 = crosshair,
	})

	-- ---- Lead indicator (mira predittiva, solo COMBAT con bersaglio) ------
	local leadIndicator = new("Frame", {
		Name                   = "LeadIndicator",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(38, 38),
		BackgroundTransparency = 1,
		Visible                = false,
		ZIndex                 = 7,
		Parent                 = gui,
	})
	local leadStroke = stroke(leadIndicator, PALETTE.accent, 2, 0)
	corner(leadIndicator, 999)
	-- piccola crocetta interna
	for _, rot in ipairs({0, 90}) do
		new("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.5),
			Size                   = UDim2.fromOffset(2, 12),
			Rotation               = rot,
			BackgroundColor3       = PALETTE.accent,
			BorderSizePixel        = 0,
			Parent                 = leadIndicator,
		})
	end

	-- ---- Target bounding box (attorno al bersaglio agganciato) ------------
	local targetBox = new("Frame", {
		Name                   = "TargetBox",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromOffset(80, 80),
		BackgroundTransparency = 1,
		Visible                = false,
		ZIndex                 = 5,
		Parent                 = gui,
	})
	-- 4 staffe angolari
	local CORNER_DEFS = {
		{ ap = Vector2.new(0, 0), pos = UDim2.fromScale(0, 0),  sx = 1, sy = 1 },
		{ ap = Vector2.new(1, 0), pos = UDim2.fromScale(1, 0),  sx =-1, sy = 1 },
		{ ap = Vector2.new(0, 1), pos = UDim2.fromScale(0, 1),  sx = 1, sy =-1 },
		{ ap = Vector2.new(1, 1), pos = UDim2.fromScale(1, 1),  sx =-1, sy =-1 },
	}
	for i, d in ipairs(CORNER_DEFS) do
		local c = new("Frame", {
			Name                   = "Corner" .. i,
			AnchorPoint            = d.ap,
			Position               = d.pos,
			Size                   = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Parent                 = targetBox,
		})
		new("Frame", {  -- braccio orizzontale
			AnchorPoint            = d.ap,
			Position               = d.pos,
			Size                   = UDim2.fromOffset(14, 2),
			BackgroundColor3       = PALETTE.danger,
			BorderSizePixel        = 0,
			Parent                 = c,
		})
		new("Frame", {  -- braccio verticale
			AnchorPoint            = d.ap,
			Position               = d.pos,
			Size                   = UDim2.fromOffset(2, 14),
			BackgroundColor3       = PALETTE.danger,
			BorderSizePixel        = 0,
			Parent                 = c,
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
		Size                   = UDim2.fromOffset(130, 22),
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

	-- Hint chip ([N] = combat/hangar)
	local hoverChip = new("Frame", {
		Name                   = "HoverChip",
		AnchorPoint            = Vector2.new(0, 1),
		Position               = UDim2.new(0, 156, 1, -10),
		Size                   = UDim2.fromOffset(108, 22),
		BackgroundColor3       = PALETTE.accent,
		BackgroundTransparency = 0.9,
		BorderSizePixel        = 0,
		Visible                = true,
		Parent                 = infoCard,
	})
	corner(hoverChip, 3)
	stroke(hoverChip, PALETTE.accent, 1, 0.4)
	local hoverLabel = new("TextLabel", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font                   = Enum.Font.GothamBold,
		TextSize               = 11,
		TextColor3             = PALETTE.accent,
		Text                   = "S-FOILS [N]",
		Parent                 = hoverChip,
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
	local ctrlCard = new("Frame", {
		Name                   = "Controls",
		AnchorPoint            = Vector2.new(1, 1),
		Position               = UDim2.new(1, -28, 1, -28 - 240 - 12),
		Size                   = UDim2.fromOffset(196, 260),
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
			TextSize               = 12,
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
		Gui             = gui,
		Reticle         = reticle,
		OuterRing       = outerRing,
		InnerRing       = innerRing,
		InnerRingStroke = innerRingStroke,
		ReloadGradient  = reloadGradient,
		Crosshair       = crosshair,
		LeadIndicator   = leadIndicator,
		LeadStroke      = leadStroke,
		TargetBox       = targetBox,
		ShipLabel       = shipLabel,
		SubLabel        = subLabel,
		ModeChip        = modeChip,
		ModeLabel       = modeLabel,
		HoverChip       = hoverChip,
		HoverLabel      = hoverLabel,
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
-- TUNING
-- ============================================================================

-- Hangar / cruise
local HANGAR_SPEED      = 20      -- studs/sec cap (navigazione hangar)
local HANGAR_TURN_RATE  = 1.4     -- rad/sec di virata piatta (A/D)
local HANGAR_SPEED_LAMBDA = 4

-- Combat steering (mouse -> mirino virtuale)
local CROSSHAIR_MAX_R   = 300     -- px di deflessione massima dal centro
local CROSSHAIR_SENS    = 1.0
local CROSSHAIR_RETURN  = 3.0     -- auto-centratura per sec (=> auto-livellamento)
local YAW_RATE          = 2.1     -- rad/sec yaw a piena deflessione
local PITCH_RATE        = 1.7     -- rad/sec pitch a piena deflessione
local MAX_PITCH         = math.rad(80)  -- evita lookAt degenerate vicino alla verticale
local BANK_MAX          = math.rad(60)   -- roll massimo in virata
local BANK_LAMBDA       = 4
local AIM_LAMBDA        = 6       -- inseguimento del setpoint gyro

-- Heavy fighter: la velocita' insegue il muso con ritardo => deriva laterale.
-- Lambda BASSO = piu' inerzia/peso (ARC-170 e' un bombardiere pesante).
local DRIFT_LAMBDA      = 2.4

local FLIGHT_CHASE_BACK = 26      -- fallback se manca CameraPart
local FLIGHT_CHASE_UP   = 8

-- Targeting
local TARGET_RANGE      = 1500
local TARGET_CONE       = math.cos(math.rad(38))   -- cono frontale di aggancio
local ALIGN_TOL_PX      = 26      -- mirino "verde" (hit garantito)
local GIMBAL_TOL_PX     = 70      -- tolleranza magnetica del gimbal
local DEFAULT_CONV_DIST = 800     -- distanza di convergenza senza bersaglio
local CANDIDATE_REFRESH = 0.35    -- sec tra le scansioni dei bersagli

local MIN_CHASE, MAX_CHASE = -10, 80
local MIN_HOVER, MAX_HOVER = 12, 70

-- ============================================================================
-- FLIGHT STATE
-- ============================================================================

local state = {
	ship           = nil,
	seat           = nil,
	primary        = nil,
	gyro           = nil,
	velocity       = nil,
	camPart        = nil,
	zoomPart       = nil,

	-- mode: "hangar" | "combat"
	mode           = "hangar",

	engineOn       = false,

	-- comune
	currentSpeed   = 0,
	chaseDistance  = 0,

	-- hangar
	hangarYaw      = 0,

	-- combat steering
	crosshair      = Vector2.zero,
	aimYaw         = 0,
	aimPitch       = 0,
	bank           = 0,
	flightVel      = Vector3.zero,
	gyroCFrame     = nil,
	freeLook       = false,

	-- camera orbit (hangar + combat free-look)
	hoverYaw       = 0,
	hoverPitch     = -0.15,
	hoverDistance  = 28,

	-- zoom / aim
	zoomMode       = false,

	-- shooting
	shooting       = false,
	lastShot       = -math.huge,

	-- targeting
	candidates     = {},
	candRefresh    = 0,
	target         = nil,        -- {model, part, hum}
	targetDist     = 0,
	leadWorld      = nil,        -- Vector3 (lead predittivo)
	leadScreen     = nil,        -- Vector2 viewport coords
	aligned        = false,

	config = { Damage = 30, MaxSpeed = 150, ReloadSpeed = 0.18, Faction = "Republic", FireSound = "" },
}

local function readShipConfig(ship)
	state.config.Damage      = ship:GetAttribute("Damage")      or 30
	state.config.MaxSpeed    = ship:GetAttribute("MaxSpeed")    or 150
	state.config.ReloadSpeed = ship:GetAttribute("ReloadSpeed") or 0.18
	state.config.FireSound   = ship:GetAttribute("FireSound")   or ""
	-- Faction della nave: di default il pilota e' Republic; serve per scegliere
	-- come "nemici" i Model con Faction diversa (es. i droidi CIS).
	state.config.Faction     = ship:GetAttribute("Faction")
		or (LocalPlayer.Team and LocalPlayer.Team.Name)
		or "Republic"
end

-- ----------------------------------------------------------------------------
-- Input helpers: leggiamo la tastiera direttamente (NIENTE VehicleSeat.Throttle)
-- ----------------------------------------------------------------------------
local function key(k) return UserInputService:IsKeyDown(k) end
local function axis(pos, neg)
	return (key(pos) and 1 or 0) - (key(neg) and 1 or 0)
end

local function readMoveInput()
	return
		axis(Enum.KeyCode.W, Enum.KeyCode.S),  -- throttle  (W=+1, S=-1)
		axis(Enum.KeyCode.D, Enum.KeyCode.A)   -- right/yaw (D=+1, A=-1)
end

local function setMouseLocked(locked)
	if locked then
		UserInputService.MouseBehavior  = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior  = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

-- Direzione del muso dato yaw/pitch (il muso del modello e' sul -LookVector
-- del PrimaryPart; qui lavoriamo direttamente con la direzione del muso).
local function noseDirFromAngles(yaw, pitch)
	local cp = math.cos(pitch)
	return Vector3.new(
		-math.sin(yaw) * cp,
		 math.sin(pitch),
		-math.cos(yaw) * cp
	)
end

local function setMode(newMode)
	if state.mode == newMode then return end
	state.mode = newMode

	if not state.primary then return end
	local noseDir = -state.primary.CFrame.LookVector

	if newMode == "hangar" then
		state.hangarYaw  = math.atan2(-noseDir.X, -noseDir.Z)
		state.hoverYaw   = state.hangarYaw
		state.hoverPitch = -0.15
		state.bank       = 0
		state.freeLook   = false
		setMouseLocked(true)
	else -- combat
		state.aimYaw     = math.atan2(-noseDir.X, -noseDir.Z)
		state.aimPitch   = math.asin(math.clamp(noseDir.Y, -1, 1))
		state.crosshair  = Vector2.zero
		state.bank       = 0
		state.flightVel  = state.velocity and state.velocity.Velocity or Vector3.zero
		state.gyroCFrame = state.primary.CFrame
		state.freeLook   = false
		state.chaseDistance = 0
		state.hoverYaw   = state.aimYaw
		state.hoverPitch = -0.1
		setMouseLocked(true)
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
	state.engineOn  = false
	state.currentSpeed = 0
	state.chaseDistance = 0
	state.zoomMode  = false
	state.lastShot  = -math.huge
	state.target    = nil
	state.candidates = {}

	readShipConfig(ship)

	HUD.ShipLabel.Text = ship.Name:upper()
	HUD.SubLabel.Text  = "STARFIGHTER  /  ONLINE  /  PILOT: " .. LocalPlayer.Name:upper()
	HUD.Dmg.Text       = string.format("%d", state.config.Damage)
	HUD.Gui.Enabled    = true

	-- Reveal animation
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

	-- Avvio SEMPRE in hangar (ali chiuse, armi off, trail off).
	state.mode = nil
	setMode("hangar")
	-- assicura che il server tenga ali chiuse e trail spenti
	ShipEvent:FireServer("ToggleSfoils", { State = false })
end

local function stopFlight()
	if state.seat == nil then return end
	camera.CameraType = Enum.CameraType.Custom
	mouse.TargetFilter = nil
	setMouseLocked(false)
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.CameraOffset = Vector3.zero end

	HUD.Crosshair.Visible     = false
	HUD.LeadIndicator.Visible = false
	HUD.TargetBox.Visible     = false

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
end

-- ============================================================================
-- TARGETING
-- ============================================================================

local function refreshCandidates()
	local list = {}
	local myFaction = state.config.Faction
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Humanoid") and desc.Health > 0 then
			local m = desc.Parent
			if m and m:IsA("Model") and m ~= state.ship then
				local f = m:GetAttribute("Faction")
				if f ~= nil and f ~= myFaction then
					local part = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
						or m:FindFirstChildWhichIsA("BasePart")
					if part then
						table.insert(list, { model = m, part = part, hum = desc })
					end
				end
			end
		end
	end
	state.candidates = list
end

-- Sceglie il bersaglio piu' allineato col muso (entro range e cono frontale).
local function pickTarget(shooterPos, noseDir)
	local best, bestDot, bestDist
	for _, c in ipairs(state.candidates) do
		local part = c.part
		if part and part.Parent and c.hum and c.hum.Health > 0 then
			local to = part.Position - shooterPos
			local dist = to.Magnitude
			if dist > 1 and dist <= TARGET_RANGE then
				local d = noseDir:Dot(to.Unit)
				if d >= TARGET_CONE and (not best or d > bestDot) then
					best, bestDot, bestDist = c, d, dist
				end
			end
		end
	end
	return best, bestDist or 0
end

local function projectToScreen(worldPos)
	local v, onScreen = camera:WorldToViewportPoint(worldPos)
	return Vector2.new(v.X, v.Y), (onScreen and v.Z > 0), v.Z
end

-- ============================================================================
-- RENDER LOOP
-- ============================================================================

local outerSpin       = 0
local replicateAccum  = 0

local function damp(current, target, lambda, dt)
	return current + (target - current) * (1 - math.exp(-lambda * dt))
end

RunService.RenderStepped:Connect(function(dt)
	outerSpin = (outerSpin + dt * 36) % 360
	HUD.OuterRing.Rotation = outerSpin

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

	local maxSpeed = math.max(state.config.MaxSpeed, 1)
	local fwdInput, rgtInput = readMoveInput()

	-- ========================================================================
	-- PHYSICS  (solo a motore acceso)
	-- ========================================================================
	if not state.engineOn then
		state.currentSpeed = 0
		HUD.ThrFill.Size = UDim2.new(0, 0, 1, 0)

	elseif state.mode == "hangar" then
		-- Virata piatta + avanti/indietro lungo il muso. WASD esclusivo.
		state.hangarYaw = state.hangarYaw - rgtInput * HANGAR_TURN_RATE * dt
		local noseDir   = noseDirFromAngles(state.hangarYaw, 0)

		local targetSpeed = fwdInput * HANGAR_SPEED
		state.currentSpeed = damp(state.currentSpeed, targetSpeed, HANGAR_SPEED_LAMBDA, dt)
		-- niente componente verticale: la nave mantiene la quota
		state.velocity.Velocity = noseDir * state.currentSpeed

		-- Orientamento piatto e livellato (il PrimaryPart guarda al contrario del muso)
		local targetCF = CFrame.new(state.primary.Position)
			* CFrame.Angles(0, state.hangarYaw, 0)
			* CFrame.Angles(0, math.pi, 0)
		state.gyro.CFrame = targetCF

		HUD.ThrFill.AnchorPoint = Vector2.new(state.currentSpeed >= 0 and 0 or 1, 0.5)
		HUD.ThrFill.Position    = UDim2.new(0.5, 0, 0.5, 0)
		HUD.ThrFill.Size        = UDim2.new(0.5 * math.clamp(math.abs(state.currentSpeed) / HANGAR_SPEED, 0, 1), 0, 1, 0)
		HUD.ThrFill.BackgroundColor3 = state.currentSpeed >= 0 and PALETTE.primary or PALETTE.accent

	else
		-- COMBAT: volo guidato dal mouse + auto-bank + deriva inerziale.
		-- Auto-centratura del mirino => quando lasci il mouse, ritorna dritto.
		state.crosshair = state.crosshair * math.exp(-CROSSHAIR_RETURN * dt)

		local nx = math.clamp(state.crosshair.X / CROSSHAIR_MAX_R, -1, 1)
		local ny = math.clamp(state.crosshair.Y / CROSSHAIR_MAX_R, -1, 1)
		if state.freeLook then nx, ny = 0, 0 end

		-- Integra yaw/pitch del muso. Mirino a destra (nx>0) => muso a destra.
		state.aimYaw   = state.aimYaw   - nx * YAW_RATE   * dt
		state.aimPitch = math.clamp(state.aimPitch - ny * PITCH_RATE * dt, -MAX_PITCH, MAX_PITCH)

		-- Auto-banking: piu' stretta la virata, piu' profondo il roll.
		local bankTarget = nx * BANK_MAX
		state.bank = damp(state.bank, bankTarget, BANK_LAMBDA, dt)

		local noseDir   = noseDirFromAngles(state.aimYaw, state.aimPitch)
		local pos       = state.primary.Position
		-- orientamento del muso, livellato sul world-up, + roll di banking
		local oriented  = CFrame.lookAt(Vector3.zero, noseDir)
		local banked    = oriented * CFrame.Angles(0, 0, state.bank)
		-- il PrimaryPart guarda al contrario del muso (180 attorno all'up locale)
		local primaryTarget = CFrame.new(pos) * banked * CFrame.Angles(0, math.pi, 0)

		if not state.gyroCFrame then state.gyroCFrame = state.primary.CFrame end
		state.gyroCFrame = state.gyroCFrame:Lerp(primaryTarget, 1 - math.exp(-AIM_LAMBDA * dt))
		state.gyro.CFrame = state.gyroCFrame

		-- Throttle: accelera (W) / frena (S), altrimenti mantiene (drift).
		local accelRate = maxSpeed * 0.7
		local brakeRate = maxSpeed * 1.4
		if fwdInput > 0 then
			state.currentSpeed = state.currentSpeed + accelRate * dt
		elseif fwdInput < 0 then
			state.currentSpeed = state.currentSpeed - brakeRate * dt
		end
		state.currentSpeed = math.clamp(state.currentSpeed, 0, maxSpeed)

		-- Deriva inerziale: la velocita' insegue il muso REALE con ritardo.
		local noseActual = -state.primary.CFrame.LookVector
		local desiredVel = noseActual * state.currentSpeed
		state.flightVel  = state.flightVel:Lerp(desiredVel, 1 - math.exp(-DRIFT_LAMBDA * dt))
		state.velocity.Velocity = state.flightVel

		local thrPct = state.currentSpeed / maxSpeed
		HUD.ThrFill.AnchorPoint = Vector2.new(0, 0.5)
		HUD.ThrFill.Position    = UDim2.new(0.5, 0, 0.5, 0)
		HUD.ThrFill.Size        = UDim2.new(0.5 * thrPct, 0, 1, 0)
		HUD.ThrFill.BackgroundColor3 = PALETTE.primary
	end

	-- ========================================================================
	-- CAMERA
	-- ========================================================================
	if state.zoomMode and state.zoomPart and state.mode == "combat" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame     = state.zoomPart.CFrame
	elseif state.mode == "hangar" or (state.mode == "combat" and state.freeLook) then
		-- Camera orbitale libera attorno alla nave (mouse delta -> yaw/pitch)
		local shipPos = state.primary.Position
		local rot     = CFrame.Angles(0, state.hoverYaw, 0) * CFrame.Angles(state.hoverPitch, 0, 0)
		local offset  = rot * Vector3.new(0, 0, state.hoverDistance)
		local camPos  = shipPos + Vector3.new(0, 2, 0) + offset
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame     = CFrame.lookAt(camPos, shipPos + Vector3.new(0, 2, 0))
	else
		-- COMBAT locked: la CameraPart segue (e ruota con) la nave.
		camera.CameraType = Enum.CameraType.Scriptable
		if state.camPart then
			camera.CFrame = state.camPart.CFrame * CFrame.new(0, 0, state.chaseDistance)
		else
			local shipPos = state.primary.Position
			local shipFwd = state.primary.CFrame.LookVector
			local shipUp  = state.primary.CFrame.UpVector
			local camPos  = shipPos
				- shipFwd * (FLIGHT_CHASE_BACK + state.chaseDistance)
				+ shipUp  * FLIGHT_CHASE_UP
			camera.CFrame = CFrame.lookAt(camPos, shipPos + shipFwd * 200, shipUp)
		end
	end

	-- ========================================================================
	-- TARGETING + LEAD INDICATOR (solo combat)
	-- ========================================================================
	local inset    = GuiService:GetGuiInset()
	local vpSize   = camera.ViewportSize
	local vpCenter = vpSize / 2
	state.aligned  = false
	state.leadWorld, state.leadScreen = nil, nil

	if state.mode == "combat" then
		state.candRefresh = state.candRefresh - dt
		if state.candRefresh <= 0 then
			state.candRefresh = CANDIDATE_REFRESH
			refreshCandidates()
		end

		local noseActual = -state.primary.CFrame.LookVector
		local target, dist = pickTarget(state.primary.Position, noseActual)
		state.target, state.targetDist = target, dist

		if target then
			local part = target.part
			local tvel = part.AssemblyLinearVelocity
			-- Lead predittivo: dove sara' il bersaglio quando arriva il laser.
			local travel = dist / LASER_SPEED
			local lead   = part.Position + tvel * travel
			state.leadWorld = lead

			local leadVP, leadOnScreen = projectToScreen(lead)
			state.leadScreen = leadVP

			-- Bounding box: proietta gli 8 spigoli del modello.
			local cf, size = target.model:GetBoundingBox()
			local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
			local anyFront = false
			local hs = size / 2
			for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
				local cornerWorld = (cf * CFrame.new(sx * hs.X, sy * hs.Y, sz * hs.Z)).Position
				local p, _, depth = projectToScreen(cornerWorld)
				if depth > 0 then
					anyFront = true
					minX = math.min(minX, p.X); maxX = math.max(maxX, p.X)
					minY = math.min(minY, p.Y); maxY = math.max(maxY, p.Y)
				end
			end end end

			if anyFront then
				local bw = math.clamp(maxX - minX, 26, vpSize.X)
				local bh = math.clamp(maxY - minY, 26, vpSize.Y)
				HUD.TargetBox.Visible  = true
				HUD.TargetBox.Size     = UDim2.fromOffset(bw + 16, bh + 16)
				HUD.TargetBox.Position = UDim2.fromOffset(
					(minX + maxX) / 2 + inset.X,
					(minY + maxY) / 2 + inset.Y)
			else
				HUD.TargetBox.Visible = false
			end

			-- Lead reticle
			if leadOnScreen then
				HUD.LeadIndicator.Visible  = true
				HUD.LeadIndicator.Position = UDim2.fromOffset(leadVP.X + inset.X, leadVP.Y + inset.Y)
				-- Allineamento: muso (centro schermo) sopra il lead => hit garantito
				local gap = (leadVP - vpCenter).Magnitude
				state.aligned = gap < ALIGN_TOL_PX
			else
				HUD.LeadIndicator.Visible = false
			end
		else
			HUD.TargetBox.Visible     = false
			HUD.LeadIndicator.Visible = false
		end
	else
		HUD.TargetBox.Visible     = false
		HUD.LeadIndicator.Visible = false
	end

	-- Colore del mirino e del lead in base all'allineamento
	local crossColor = state.aligned and PALETTE.good or PALETTE.primary
	HUD.InnerRingStroke.Color = crossColor
	HUD.LeadStroke.Color      = state.aligned and PALETTE.good or PALETTE.accent

	-- Mirino virtuale del mouse (solo combat, non in free-look)
	if state.mode == "combat" and not state.freeLook then
		HUD.Crosshair.Visible  = true
		HUD.Crosshair.Position = UDim2.new(0.5, state.crosshair.X, 0.5, state.crosshair.Y)
	else
		HUD.Crosshair.Visible = false
	end

	-- ========================================================================
	-- REPLICATE setpoint al server (~10Hz, backup per gli osservatori)
	-- ========================================================================
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
	HUD.SpeedValue.Text   = string.format("%d", math.floor(math.abs(state.currentSpeed) + 0.5))
	HUD.SpeedBarFill.Size  = UDim2.new(math.clamp(math.abs(state.currentSpeed) / maxSpeed, 0, 1), 0, 1, 0)

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
		HUD.ModeChip.BackgroundColor3 = PALETTE.primary
	else
		newMode = state.freeLook and "COMBAT - FREELOOK" or "COMBAT"
		HUD.ModeChip.BackgroundColor3 = PALETTE.good
	end
	if HUD.ModeLabel.Text ~= newMode then
		HUD.ModeLabel.Text = newMode
	end

	HUD.Reticle.Visible = (state.mode == "combat")
end)

-- ============================================================================
-- SHOOTING
-- ============================================================================

local function tryShoot()
	if not state.ship or not state.primary then return end
	if state.mode ~= "combat" then return end  -- armi disabilitate in hangar
	if not state.engineOn then return end
	local now = os.clock()
	if now - state.lastShot < state.config.ReloadSpeed then return end
	state.lastShot = now

	-- Punto di convergenza: dove puntano (e si incrociano) le canne d'ala.
	local noseDir = -state.primary.CFrame.LookVector
	local convDist = (state.target and state.targetDist > 1) and state.targetDist or DEFAULT_CONV_DIST
	local converge = state.primary.Position + noseDir * convDist

	-- Gimbal aim-assist: se il mirino e' VICINO (ma non perfettamente sopra) al
	-- lead indicator, pieghiamo il punto di convergenza verso il lead.
	if state.target and state.leadWorld and state.leadScreen then
		local vpCenter = camera.ViewportSize / 2
		local gap = (state.leadScreen - vpCenter).Magnitude
		if gap < GIMBAL_TOL_PX then
			local t = 1 - math.clamp(gap / GIMBAL_TOL_PX, 0, 1)  -- 1 = perfettamente centrato
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
		if state.ship and state.mode == "combat" then state.zoomMode = true end

	elseif input.KeyCode == Enum.KeyCode.R then
		if not state.ship then return end
		state.engineOn = not state.engineOn
		if not state.engineOn then
			state.currentSpeed = 0
		else
			-- Riaggancia i setpoint alla posizione/velocita' correnti (niente salti).
			state.gyroCFrame = state.primary and state.primary.CFrame or nil
			state.flightVel  = state.velocity and state.velocity.Velocity or Vector3.zero
		end
		ShipEvent:FireServer("EngineToggle", { State = state.engineOn })

	elseif input.KeyCode == Enum.KeyCode.N then
		if not state.ship then return end
		-- N alterna Hangar <-> Combat (apre/chiude le S-foils, trail e armi).
		if state.mode == "hangar" then
			setMode("combat")
			ShipEvent:FireServer("ToggleSfoils", { State = true })
		else
			setMode("hangar")
			ShipEvent:FireServer("ToggleSfoils", { State = false })
		end

	elseif input.KeyCode == Enum.KeyCode.C then
		-- C: alterna la camera bloccata/free-look (solo in combat).
		if state.ship and state.mode == "combat" then
			state.freeLook = not state.freeLook
			if state.freeLook then
				-- parti la cam orbitale allineata col muso attuale
				local noseDir = -state.primary.CFrame.LookVector
				state.hoverYaw   = math.atan2(-noseDir.X, -noseDir.Z)
				state.hoverPitch = -0.1
			end
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
		if state.mode == "hangar" or (state.mode == "combat" and state.freeLook) then
			-- Camera orbitale libera (free look): non sterza la nave.
			state.hoverYaw   = state.hoverYaw   - input.Delta.X * 0.005
			state.hoverPitch = math.clamp(state.hoverPitch - input.Delta.Y * 0.005, -1.45, 1.45)
		elseif state.mode == "combat" then
			-- Sterzo: il mouse muove il mirino virtuale; la nave lo insegue.
			local c = state.crosshair + Vector2.new(input.Delta.X, input.Delta.Y) * CROSSHAIR_SENS
			if c.Magnitude > CROSSHAIR_MAX_R then
				c = c.Unit * CROSSHAIR_MAX_R
			end
			state.crosshair = c
		end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if state.mode == "combat" and not state.freeLook then
			state.chaseDistance = math.clamp(
				state.chaseDistance - input.Position.Z * 4, MIN_CHASE, MAX_CHASE)
		else
			state.hoverDistance = math.clamp(
				state.hoverDistance - input.Position.Z * 4, MIN_HOVER, MAX_HOVER)
		end
	end
end)

-- ============================================================================
-- Cleanup al respawn
-- ============================================================================
LocalPlayer.CharacterAdded:Connect(function()
	stopFlight()
end)
