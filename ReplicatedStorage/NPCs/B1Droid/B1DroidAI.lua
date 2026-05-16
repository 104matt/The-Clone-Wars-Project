-- B1DroidAI.lua  (Script - server)
-- Posizione: dentro il modello B1Droid (B1Droid/B1DroidAI)
--
-- AI base per il droide B1 CIS in modalità Zombie Attack:
--   - cerca il player nemico (team Republic) più vicino
--   - cammina verso di lui mantenendo distanza di tiro
--   - spara via BindableEvent E5.Fire
--   - gestisce animazioni Idle / Walk / Shoot
--   - HP + morte con dissolvenza
--
-- Setup richiesto sul modello:
--   * Un Humanoid dentro il rig (sostituisce l'AnimationController).
--     - HumanoidRootPart come PrimaryPart del modello consigliato.
--     - WalkSpeed ~10 (impostato sotto in CONFIG).
--   * Un Tool/Model "E5" con dentro Barrel, Handle, ecc. e lo script E5Blaster.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

-- ================= CONFIG =================
local CONFIG = {
	TARGET_TEAM       = "Republic",   -- nome esatto del team bersaglio
	VISION_RANGE      = 120,          -- distanza max in cui il droide vede
	ATTACK_RANGE      = 90,           -- entra in fuoco se entro questa distanza
	PREFERRED_RANGE   = 50,           -- si ferma a sparare entro questa distanza
	WALK_SPEED        = 10,
	MAX_HEALTH        = 60,
	REPATH_INTERVAL   = 0.5,          -- ogni quanto aggiornare il MoveTo
	LOSS_OF_SIGHT_T   = 3,            -- secondi prima di tornare in idle se target perso
	DEATH_FADE_TIME   = 2,
	DEATH_LINGER      = 4,            -- secondi prima del Destroy
	ANIM_IDS = {
		Idle  = 71786808734277,
		Walk  = 116506508382029,
		Shoot = 71786808734277,       -- placeholder, da sostituire
		Death = 0,                    -- 0 = non caricato, fallback su dissolvenza
	},
}

-- ================= SETUP =================
local droid = script.Parent
if not droid:IsA("Model") then
	error("B1DroidAI: deve essere figlio di un Model (il droide).")
end

-- Trova Humanoid (può essere annidato dentro il rig "New object" o simili)
local humanoid = droid:FindFirstChildOfClass("Humanoid")
if not humanoid then
	for _, desc in ipairs(droid:GetDescendants()) do
		if desc:IsA("Humanoid") then humanoid = desc break end
	end
end
if not humanoid then
	error("B1DroidAI: Humanoid non trovato. Sostituisci AnimationController con Humanoid.")
end

local rootPart = humanoid.RootPart
	or droid:FindFirstChild("HumanoidRootPart", true)
	or droid.PrimaryPart
if not rootPart then
	error("B1DroidAI: HumanoidRootPart non trovato.")
end

humanoid.WalkSpeed = CONFIG.WALK_SPEED
humanoid.MaxHealth = CONFIG.MAX_HEALTH
humanoid.Health    = CONFIG.MAX_HEALTH

-- E5 + BindableEvent di fuoco
local e5 = droid:FindFirstChild("E5", true)
if not e5 then
	warn("B1DroidAI: E5 non trovato nel modello — il droide non sparerà.")
end
local fireEvent
if e5 then
	fireEvent = e5:WaitForChild("Fire", 5)
	if not fireEvent then
		warn("B1DroidAI: BindableEvent 'Fire' non trovato dentro E5 (lo script E5Blaster lo crea automaticamente).")
	end
end

-- ============ ANIMAZIONI ==================
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local function loadAnim(id)
	if not id or id == 0 then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok then
		warn("B1DroidAI: impossibile caricare animazione", id, track)
		return nil
	end
	return track
end

local tracks = {
	Idle  = loadAnim(CONFIG.ANIM_IDS.Idle),
	Walk  = loadAnim(CONFIG.ANIM_IDS.Walk),
	Shoot = loadAnim(CONFIG.ANIM_IDS.Shoot),
	Death = loadAnim(CONFIG.ANIM_IDS.Death),
}

if tracks.Idle  then tracks.Idle.Priority  = Enum.AnimationPriority.Idle      end
if tracks.Walk  then tracks.Walk.Priority  = Enum.AnimationPriority.Movement  end
if tracks.Shoot then tracks.Shoot.Priority = Enum.AnimationPriority.Action    end
if tracks.Death then tracks.Death.Priority = Enum.AnimationPriority.Action4   end

local currentLocomotion -- "Idle" / "Walk"

local function playLocomotion(name)
	if currentLocomotion == name then return end
	currentLocomotion = name
	for key, track in pairs(tracks) do
		if (key == "Idle" or key == "Walk") and track then
			if key == name then
				if not track.IsPlaying then track:Play(0.2) end
			else
				if track.IsPlaying then track:Stop(0.2) end
			end
		end
	end
end

-- ============ TARGETING ==================
local function isValidTarget(player)
	if not player.Team or player.Team.Name ~= CONFIG.TARGET_TEAM then return nil end
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not hrp then return nil end
	return hum, hrp
end

local function findTarget()
	local best, bestDist, bestHrp
	local origin = rootPart.Position
	for _, plr in ipairs(Players:GetPlayers()) do
		local hum, hrp = isValidTarget(plr)
		if hum and hrp then
			local d = (hrp.Position - origin).Magnitude
			if d <= CONFIG.VISION_RANGE and (not best or d < bestDist) then
				best, bestDist, bestHrp = plr, d, hrp
			end
		end
	end
	return best, bestHrp, bestDist
end

-- ============ DEATH =====================
local dead = false
local function onDeath()
	if dead then return end
	dead = true

	if tracks.Death then
		tracks.Death:Play(0.1)
	end

	-- ragdoll soft: lascia cadere disabilitando i motori principali e dissolve
	for _, p in ipairs(droid:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = p.CanCollide   -- noop, mantiene collisione attuale
			TweenService:Create(p, TweenInfo.new(CONFIG.DEATH_FADE_TIME), { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(droid, CONFIG.DEATH_LINGER)
end

humanoid.Died:Connect(onDeath)

-- ============ MAIN LOOP =================
local lastTargetSeen = 0
local lastShotAttempt = 0

task.spawn(function()
	while not dead and humanoid.Health > 0 do
		local _, targetHrp, dist = findTarget()
		local now = os.clock()

		if targetHrp then
			lastTargetSeen = now

			-- ruota verso il target (solo sull'asse Y)
			local lookPos = Vector3.new(targetHrp.Position.X, rootPart.Position.Y, targetHrp.Position.Z)
			rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.lookAt(rootPart.Position, lookPos), 0.25)

			if dist > CONFIG.PREFERRED_RANGE then
				-- avanza verso il target
				humanoid:MoveTo(targetHrp.Position)
				playLocomotion("Walk")
			else
				-- abbastanza vicino: fermati e spara
				humanoid:MoveTo(rootPart.Position)
				playLocomotion("Idle")
			end

			if dist <= CONFIG.ATTACK_RANGE and fireEvent then
				if tracks.Shoot and not tracks.Shoot.IsPlaying then
					tracks.Shoot:Play(0.05)
				end
				fireEvent:Fire(targetHrp.Position)
			end
		else
			-- nessun target: idle
			if now - lastTargetSeen > CONFIG.LOSS_OF_SIGHT_T then
				playLocomotion("Idle")
			end
		end

		task.wait(CONFIG.REPATH_INTERVAL)
	end
end)

-- avvia in idle
playLocomotion("Idle")
