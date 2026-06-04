-- WaveManager.lua  (Script - server)
-- Posizione: ServerScriptService/WaveManager
--
-- Gestisce il ciclo delle ondate (Zombie Attack Mode) per i droidi CIS.
-- In QUESTO step NON spawna ancora droidi: imposta solo la prima wave e
-- struttura tutta la logica (config, ciclo, conteggio) pronta per lo spawn.
--
-- Legge/scrive due IntValue GIA' ESISTENTI nel place (non li crea):
--   ReplicatedStorage.DroidSystemRep.CurrentWave      (1..20)
--   ReplicatedStorage.DroidSystemRep.DroidsRemaining  (droidi vivi)
--
-- I droidi vivi vivranno in Workspace.HostileDroids (cartella creata a runtime).
-- Lo spawn vero peschera' dai punti in una cartella "DroidSpawns" (step futuro).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

-- ============================================================================
-- CONFIG
-- ============================================================================
local CONFIG = {
	MaxWaves       = 20,
	BossInterval   = 5,    -- wave 5,10,15,20 sono boss wave
	-- Droidi per wave: base che cresce, con bonus sulle boss wave.
	BaseDroids     = 6,
	PerWaveExtra   = 2,    -- +2 droidi per ogni wave
	BossExtra      = 8,    -- droidi extra durante una boss wave
	InterWaveDelay = 5,    -- secondi tra una wave clear e la successiva
}

-- TODO: quando implementeremo lo spawn, mettere a true per attivare
-- spawn dei droidi + conteggio basato sulla cartella HostileDroids.
local SPAWN_ENABLED = false

-- ============================================================================
-- RESOLVE VALUE (gia' esistenti)
-- ============================================================================
local rep             = ReplicatedStorage:WaitForChild("DroidSystemRep")
local currentWave     = rep:WaitForChild("CurrentWave")
local droidsRemaining = rep:WaitForChild("DroidsRemaining")

-- Cartella runtime dei droidi nemici vivi.
local function getHostileFolder()
	local f = Workspace:FindFirstChild("HostileDroids")
	if not f then
		f        = Instance.new("Folder")
		f.Name   = "HostileDroids"
		f.Parent = Workspace
	end
	return f
end
local hostileFolder = getHostileFolder()

-- ============================================================================
-- HELPERS
-- ============================================================================
local function isBossWave(wave)
	return wave > 0 and (wave % CONFIG.BossInterval == 0)
end

-- Quanti droidi prevede una data wave.
local function droidsForWave(wave)
	local count = CONFIG.BaseDroids + (wave - 1) * CONFIG.PerWaveExtra
	if isBossWave(wave) then
		count = count + CONFIG.BossExtra
	end
	return count
end

-- ============================================================================
-- WAVE LIFECYCLE
-- ============================================================================
local activeWave = 0

-- Avvia una wave: imposta i value e (in futuro) spawna i droidi.
local function startWave(wave)
	activeWave = wave
	local planned = droidsForWave(wave)

	currentWave.Value     = wave
	droidsRemaining.Value = planned

	local tag = isBossWave(wave) and "  [BOSS WAVE]" or ""
	print(("[WaveManager] === WAVE %d / %d ===%s"):format(wave, CONFIG.MaxWaves, tag))
	print(("[WaveManager] Droidi previsti: %d"):format(planned))

	if SPAWN_ENABLED then
		-- TODO (step successivo): spawnare `planned` droidi dai punti in
		-- DroidSpawns, parentandoli a Workspace.HostileDroids. Il conteggio
		-- DroidsRemaining sara' poi guidato da hostileFolder.ChildRemoved.
		-- spawnDroidsForWave(wave, planned, hostileFolder)
	else
		print("[WaveManager] (spawn disattivato) Questa wave DOVREBBE spawnare "
			.. planned .. " droidi B1 da DroidSpawns dentro Workspace.HostileDroids.")
		print("[WaveManager] DroidsRemaining impostato a " .. planned
			.. " a scopo indicativo per l'HUD.")
	end
end

-- Passa alla wave successiva (o termina al raggiungimento del massimo).
local function advanceWave()
	if activeWave >= CONFIG.MaxWaves then
		print("[WaveManager] Tutte le wave completate. Vittoria!")
		-- TODO: gestione fine raid (ricompense, ritorno al menu, ecc.)
		return
	end
	task.wait(CONFIG.InterWaveDelay)
	startWave(activeWave + 1)
end

-- Conteggio droidi vivi: quando lo spawn sara' attivo, DroidsRemaining segue
-- il numero di figli in HostileDroids, e a 0 si avanza di wave.
if SPAWN_ENABLED then
	hostileFolder.ChildRemoved:Connect(function()
		local alive = #hostileFolder:GetChildren()
		droidsRemaining.Value = alive
		if alive <= 0 and activeWave > 0 then
			print(("[WaveManager] Wave %d ripulita."):format(activeWave))
			task.spawn(advanceWave)
		end
	end)
end

-- ============================================================================
-- AVVIO
-- ============================================================================
-- TODO: in futuro StartWaves() verra' chiamato dal sistema raid (dopo l'intro
-- e il teleport sulla mappa), non automaticamente all'avvio del server.
local function startWaves()
	print("[WaveManager] Avvio sistema ondate.")
	startWave(1)
end

startWaves()
