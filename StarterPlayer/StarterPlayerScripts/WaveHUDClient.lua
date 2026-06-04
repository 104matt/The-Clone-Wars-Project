-- WaveHUDClient.lua  (LocalScript)
-- Posizione: StarterPlayer/StarterPlayerScripts/WaveHUDClient
--
-- GESTISCE (non crea) l'HUD gia' presente in:
--   PlayerGui.MainMenu.WaveIndicator
-- leggendo in tempo reale i due IntValue gia' esistenti:
--   ReplicatedStorage.DroidSystemRep.CurrentWave      (1..20)
--   ReplicatedStorage.DroidSystemRep.DroidsRemaining  (droidi vivi)
--
-- Struttura UI attesa (creata a mano in Studio dall'utente):
--   WaveIndicator
--    └ HUDContainer  (Frame, con UIStroke per il flash)
--       ├ WaveLabel        (TextLabel, RichText)
--       ├ DroidsLabel      (TextLabel, RichText)
--       └ BossIntelFrame
--          └ BossIntelLabel (TextLabel)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local MAX_WAVES     = 20
local BOSS_INTERVAL = 5     -- boss alle wave 5, 10, 15, 20

local COL = {
	white   = Color3.fromRGB(255, 255, 255),
	cyan    = Color3.fromRGB(0, 210, 255),
	red     = Color3.fromRGB(255, 75, 75),
	green   = Color3.fromRGB(80, 240, 140),
	orange  = Color3.fromRGB(255, 170, 60),
	bossRed = Color3.fromRGB(255, 45, 45),
}

-- ============================================================================
-- RESOLVE UI (gia' esistente)
-- ============================================================================
local mainMenu      = PlayerGui:WaitForChild("MainMenu")
local waveIndicator = mainMenu:WaitForChild("WaveIndicator")
local container     = waveIndicator:WaitForChild("HUDContainer")
local waveLabel     = container:WaitForChild("WaveLabel")
local droidsLabel   = container:WaitForChild("DroidsLabel")
local bossFrame     = container:WaitForChild("BossIntelFrame")
local bossLabel     = bossFrame:WaitForChild("BossIntelLabel")
local containerStroke = container:FindFirstChildOfClass("UIStroke")  -- opzionale (flash)

-- Assicura RichText abilitato sui label che lo usano
waveLabel.RichText   = true
droidsLabel.RichText = true

-- ============================================================================
-- ANIMAZIONI / FLASH
-- ============================================================================
local function flashStroke()
	if not containerStroke then return end
	containerStroke.Transparency = 0
	TweenService:Create(containerStroke, TweenInfo.new(0.6), { Transparency = 0.15 }):Play()
end

local function flashLabel(label, color)
	local original = label.TextColor3
	label.TextColor3 = color
	TweenService:Create(label, TweenInfo.new(0.4), { TextColor3 = original }):Play()
end

-- ============================================================================
-- RENDER
-- ============================================================================
local function isBossWave(wave)
	return wave > 0 and (wave % BOSS_INTERVAL == 0)
end

local function renderWave(wave)
	wave = math.clamp(wave, 0, MAX_WAVES)
	-- es. WAVE 04 / 20 -> attuale bianca, "/ 20" ciano
	waveLabel.Text = string.format(
		'WAVE <font color="#FFFFFF">%02d</font> <font color="rgb(0,210,255)">/ %02d</font>',
		wave, MAX_WAVES
	)
	flashStroke()
end

local function renderDroids(count)
	if count and count > 0 then
		droidsLabel.TextColor3 = COL.red
		droidsLabel.Text = string.format('<font color="#FF4B4B">%d</font> DROIDS', count)
	else
		droidsLabel.TextColor3 = COL.green
		droidsLabel.Text = '<font color="rgb(80,240,140)">WAVE CLEARED</font>'
	end
end

local function renderBossIntel(wave)
	if isBossWave(wave) then
		bossLabel.TextColor3 = COL.bossRed
		bossLabel.Text       = "» BOSS WAVE ACTIVE"
		flashLabel(bossLabel, COL.white)
	else
		local nextBoss  = (math.floor((wave - 1) / BOSS_INTERVAL) + 1) * BOSS_INTERVAL
		local wavesLeft = math.max(nextBoss - wave, 0)
		bossLabel.TextColor3 = COL.orange
		if wavesLeft <= 0 then
			bossLabel.Text = "» NEXT BOSS IN: -- WAVES"
		else
			bossLabel.Text = string.format("» NEXT BOSS IN: %d WAVE%s",
				wavesLeft, wavesLeft == 1 and "" or "S")
		end
	end
end

-- ============================================================================
-- BINDING AI VALUE (gia' esistenti nel rep storage)
-- ============================================================================
task.spawn(function()
	local rep             = ReplicatedStorage:WaitForChild("DroidSystemRep")
	local currentWave     = rep:WaitForChild("CurrentWave")
	local droidsRemaining = rep:WaitForChild("DroidsRemaining")

	currentWave.Changed:Connect(function()
		renderWave(currentWave.Value)
		renderBossIntel(currentWave.Value)
	end)
	droidsRemaining.Changed:Connect(function()
		renderDroids(droidsRemaining.Value)
	end)

	-- Primo render con i valori correnti
	renderWave(currentWave.Value)
	renderDroids(droidsRemaining.Value)
	renderBossIntel(currentWave.Value)
end)
