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
	MELEE_STOP_RANGE  = 6,            -- si ferma solo se quasi addosso al target (per non sovrapporsi)
	WALK_SPEED        = 10,
	MAX_HEALTH        = 60,
	REPATH_INTERVAL   = 0.5,          -- ogni quanto aggiornare il MoveTo
	TURN_SPEED        = 6,            -- velocità rotazione verso il target (lerp factor per secondo)
	FIRE_ANGLE_DEG    = 25,           -- angolo max tra forward del droide e direzione target per poter sparare
	FACING_OFFSET_DEG = 180,          -- offset rotazione attorno a Y per compensare rig "girati":
	                                  --   * 0   = rig R15/R6 standard (mesh guarda verso LookVector di HRP)
	                                  --   * 180 = rig Mixamo / Hips che guarda nel verso opposto (default qui)
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

-- ============ FACING LOOP ================
-- Heartbeat dedicato alla rotazione: il droide deve sempre guardare il target,
-- sia mentre cammina sia da fermo. Disabilito AutoRotate del Humanoid per evitare
-- che combatta con questa rotazione manuale quando ci si muove di traverso.
humanoid.AutoRotate = false

local currentTargetHrp -- aggiornato dal main loop

local cosFireAngle    = math.cos(math.rad(CONFIG.FIRE_ANGLE_DEG))
local facingOffsetRad = math.rad(CONFIG.FACING_OFFSET_DEG)
local facingOffsetCF  = CFrame.Angles(0, facingOffsetRad, 0)

-- "Front reale" del droide = LookVector di HRP ruotato dell'offset configurato.
local function realForward()
	return (rootPart.CFrame * facingOffsetCF).LookVector
end

local function angleAlignedToTarget()
	if not currentTargetHrp then return false end
	local toTarget = currentTargetHrp.Position - rootPart.Position
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if toTarget.Magnitude < 0.01 then return true end
	local forward = realForward()
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 0.01 then return false end
	return forward.Unit:Dot(toTarget.Unit) >= cosFireAngle
end

RunService.Heartbeat:Connect(function(dt)
	if dead or not currentTargetHrp or not currentTargetHrp.Parent then return end
	local targetPos = currentTargetHrp.Position
	local lookPos   = Vector3.new(targetPos.X, rootPart.Position.Y, targetPos.Z)
	if (lookPos - rootPart.Position).Magnitude < 0.05 then return end
	-- vogliamo che la mesh (front reale) guardi il target: contro-ruotiamo l'offset sul goal
	local goal  = CFrame.lookAt(rootPart.Position, lookPos) * facingOffsetCF:Inverse()
	local alpha = math.clamp(CONFIG.TURN_SPEED * dt, 0, 1)
	rootPart.CFrame = rootPart.CFrame:Lerp(goal, alpha)
end)

-- ============ MAIN LOOP =================
task.spawn(function()
	while not dead and humanoid.Health > 0 do
		local _, targetHrp, dist = findTarget()
		currentTargetHrp = targetHrp

		if targetHrp then
			-- avanza verso il target SEMPRE: il droide cammina e spara insieme
			if dist > CONFIG.MELEE_STOP_RANGE then
				humanoid:MoveTo(targetHrp.Position)
				playLocomotion("Walk")
			else
				-- praticamente addosso, evita di pestare il player
				humanoid:MoveTo(rootPart.Position)
				playLocomotion("Idle")
			end

			-- spara solo se è girato verso il target (no fuoco "alle spalle")
			if dist <= CONFIG.ATTACK_RANGE and fireEvent and angleAlignedToTarget() then
				if tracks.Shoot and not tracks.Shoot.IsPlaying then
					tracks.Shoot:Play(0.05)
				end
				fireEvent:Fire(targetHrp.Position)
			end
		else
			-- nessun target: fermo, in idle
			humanoid:MoveTo(rootPart.Position)
			playLocomotion("Idle")
		end

		task.wait(CONFIG.REPATH_INTERVAL)
	end
end)

-- avvia in idle
playLocomotion("Idle")
