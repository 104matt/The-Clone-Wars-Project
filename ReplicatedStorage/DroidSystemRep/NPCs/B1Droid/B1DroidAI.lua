-- B1DroidAI.lua  (Script - server)
-- Posizione: dentro il modello del droide (B1Droid/B1DroidAI).
-- La logica è generica e riusabile per altri droidi (B2, Droideka, ecc.):
-- basta clonare il modello e cambiare gli ANIM_IDS / la mesh. Il tool/sotto-
-- modello dell'arma deve chiamarsi "Blaster".
--
-- Setup richiesto sul modello del droide:
--   * Humanoid nel rig (HumanoidRootPart consigliato come PrimaryPart).
--   * Sotto-modello/Tool chiamato "Blaster" con:
--       - Barrel        (BasePart, punto di uscita laser)
--       - Handle        (BasePart, parent dei suoni)
--       - MuzzleFlash   (ParticleEmitter, opzionale, dentro Barrel)
--       - Light         (PointLight, opzionale, dentro Barrel)
--       - Fire          (Sound, opzionale, dentro Handle)
--   * StringValue "droidName"  -> matcha un folder in Workspace.DroidSystemWorkspace.DroidPaths
--   * BoolValue   "isHostile"  -> true = spara ai player Republic in vista
--   * BoolValue   "loopPath"   -> true = al termine del path riparte dal waypoint 1
--
-- Workspace richiesto:
--   Workspace.DroidSystemWorkspace.DroidPaths.<droidName>/
--     contenente BasePart anchored numerate ("1", "2", "3", ...) come waypoint.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local Workspace          = game:GetService("Workspace")
local Debris             = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")

local LaserSystem = require(ReplicatedStorage:WaitForChild("DroidSystemRep")
	:WaitForChild("Modules"):WaitForChild("LaserSystem"))

-- ================= CONFIG =================
local CONFIG = {
	TARGET_TEAM        = "Republic",
	VISION_RANGE       = 120,
	ATTACK_RANGE       = 90,
	MELEE_STOP_RANGE   = 6,
	WALK_SPEED         = 10,
	MAX_HEALTH         = 60,

	WAYPOINT_REACH     = 4,
	REPATH_INTERVAL    = 0.4,

	-- pathfinding
	AGENT_RADIUS       = 3,
	AGENT_HEIGHT       = 5,
	AGENT_CAN_JUMP     = true,        -- il PathfindingService può inserire salti SOLO quando strettamente necessario
	JUMP_POWER         = 18,          -- molto basso: i droidi non sono ginnasti
	PF_WAYPOINT_REACH  = 2,           -- soglia di "raggiunto" per i sotto-waypoint del PathfindingService
	PF_REPATH_TIMEOUT  = 1.0,         -- secondi senza avanzare prima di ricalcolare

	-- fazione (per evitare friendly fire)
	FACTION            = "CIS",

	TURN_SPEED         = 6,
	FIRE_ANGLE_DEG     = 25,
	FACING_OFFSET_DEG  = 180,

	FIRE_COOLDOWN      = 0.6,
	SPREAD_DEG         = 4,
	DAMAGE             = 12,
	MUZZLE_FLASH_TIME  = 0.06,

	HUNT_SEARCH_TIME   = 6,

	DEATH_LINGER       = 5,
	ANIM_IDS = {
		Idle      = 71786808734277,
		Walk      = 116506508382029,
		Shoot     = 71786808734277,
		Death     = 72048211070113,
		DeathIdle = 81779316393547,
	},
}

-- ================= SETUP =================
local droid = script.Parent
if not droid:IsA("Model") then
	error("B1DroidAI: deve essere figlio di un Model (il droide).")
end

local function findHumanoid(model)
	local h = model:FindFirstChildOfClass("Humanoid")
	if h then return h end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") then return d end
	end
end

local humanoid = findHumanoid(droid) or error("B1DroidAI: Humanoid non trovato.")
local rootPart = humanoid.RootPart
	or droid:FindFirstChild("HumanoidRootPart", true)
	or droid.PrimaryPart
if not rootPart then error("B1DroidAI: HumanoidRootPart non trovato.") end

humanoid.WalkSpeed  = CONFIG.WALK_SPEED
humanoid.MaxHealth  = CONFIG.MAX_HEALTH
humanoid.Health     = CONFIG.MAX_HEALTH
humanoid.AutoRotate = false
-- Permetti al droide di saltare SOLO quando il PathfindingService lo richiede esplicitamente.
-- JumpPower è volutamente basso: niente saltelli da NBA player.
humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
humanoid.JumpPower  = CONFIG.JUMP_POWER
-- UseJumpPower esiste solo nei rig moderni; pcall per essere safe su rig vecchi.
pcall(function() humanoid.UseJumpPower = true end)

-- Imposta la fazione del modello (usata da LaserSystem per evitare fuoco amico).
if droid:GetAttribute("Faction") == nil then
	droid:SetAttribute("Faction", CONFIG.FACTION)
end

local function readValue(name, className, default)
	local v = droid:FindFirstChild(name)
	if v and v:IsA(className) then return v.Value end
	return default
end
local droidName = readValue("droidName", "StringValue", "")
local isHostile = readValue("isHostile", "BoolValue",  false)
local loopPath  = readValue("loopPath",  "BoolValue",  false)

-- ----- Blaster -----
local blaster = droid:FindFirstChild("Blaster", true)
local barrel, handle, muzzleFlash, muzzleLight, fireSound
if blaster then
	barrel = blaster:FindFirstChild("Barrel", true)
	handle = blaster:FindFirstChild("Handle", true)
	if barrel then
		muzzleFlash = barrel:FindFirstChild("MuzzleFlash")
		muzzleLight = barrel:FindFirstChild("Light")
	end
	if handle then
		fireSound = handle:FindFirstChild("Fire")
	end
elseif isHostile then
	warn("B1DroidAI: droide ostile senza 'Blaster' nel modello — non sparerà.")
end

-- ----- Path -----
local pathParts -- array ordinato di BasePart waypoint, oppure nil
do
	local dsw = Workspace:FindFirstChild("DroidSystemWorkspace")
	if not dsw then
		warn(("[%s] Workspace.DroidSystemWorkspace mancante."):format(droid.Name))
	end
	local pathsRoot = dsw and dsw:FindFirstChild("DroidPaths")
	if dsw and not pathsRoot then
		warn(("[%s] DroidSystemWorkspace.DroidPaths mancante."):format(droid.Name))
	end
	if droidName == "" then
		warn(("[%s] StringValue 'droidName' assente o vuoto: nessun path verrà seguito."):format(droid.Name))
	end
	local pathFolder = pathsRoot and droidName ~= "" and pathsRoot:FindFirstChild(droidName)
	if pathsRoot and droidName ~= "" and not pathFolder then
		warn(("[%s] DroidPaths non contiene un folder chiamato '%s'."):format(droid.Name, droidName))
	end
	if pathFolder then
		local list = {}
		for _, child in ipairs(pathFolder:GetChildren()) do
			if child:IsA("BasePart") then
				local n = tonumber(child.Name)
				if n then table.insert(list, { idx = n, part = child }) end
			end
		end
		table.sort(list, function(a, b) return a.idx < b.idx end)
		if #list > 0 then
			pathParts = {}
			for i, entry in ipairs(list) do pathParts[i] = entry.part end
			print(("[%s] Path '%s' caricato con %d waypoint."):format(droid.Name, droidName, #pathParts))
		else
			warn(("[%s] Path '%s' trovato ma senza BasePart numerate (es. '1', '2', ...)."):format(droid.Name, droidName))
		end
	end
end

-- ============ ANIMAZIONI ==================
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
animator.Parent = humanoid

local function loadAnim(id)
	if not id or id == 0 then return nil end
	local a = Instance.new("Animation")
	a.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok then warn("B1DroidAI: anim load fail", id, track); return nil end
	return track
end

local tracks = {
	Idle      = loadAnim(CONFIG.ANIM_IDS.Idle),
	Walk      = loadAnim(CONFIG.ANIM_IDS.Walk),
	Shoot     = loadAnim(CONFIG.ANIM_IDS.Shoot),
	Death     = loadAnim(CONFIG.ANIM_IDS.Death),
	DeathIdle = loadAnim(CONFIG.ANIM_IDS.DeathIdle),
}
if tracks.Idle      then tracks.Idle.Priority      = Enum.AnimationPriority.Idle     end
if tracks.Walk      then tracks.Walk.Priority      = Enum.AnimationPriority.Movement end
if tracks.Shoot     then tracks.Shoot.Priority     = Enum.AnimationPriority.Action   end
if tracks.Death     then tracks.Death.Priority     = Enum.AnimationPriority.Action4  end
if tracks.DeathIdle then tracks.DeathIdle.Priority = Enum.AnimationPriority.Action4  end
if tracks.DeathIdle then tracks.DeathIdle.Looped   = true                             end

-- ----- WalkingSound (opzionale) -----
-- Se nel modello del droide esiste un Sound chiamato "WalkingSound", lo
-- riproduciamo in loop mentre cammina e lo fermiamo quando si ferma/idle.
-- Se non esiste, semplicemente non lo riproduciamo (nessun warning).
local walkingSound = droid:FindFirstChild("WalkingSound", true)
if walkingSound and walkingSound:IsA("Sound") then
	walkingSound.Looped = true
else
	walkingSound = nil
end

local currentLocomotion
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
	-- Sync del WalkingSound con lo stato di locomozione
	if walkingSound then
		if name == "Walk" then
			if not walkingSound.IsPlaying then walkingSound:Play() end
		else
			if walkingSound.IsPlaying then walkingSound:Stop() end
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

-- ============ FACING ====================
local cosFireAngle    = math.cos(math.rad(CONFIG.FIRE_ANGLE_DEG))
local facingOffsetCF  = CFrame.Angles(0, math.rad(CONFIG.FACING_OFFSET_DEG), 0)

local function realForward()
	return (rootPart.CFrame * facingOffsetCF).LookVector
end

local function angleAlignedTo(targetPos)
	local toTarget = targetPos - rootPart.Position
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if toTarget.Magnitude < 0.01 then return true end
	local f = realForward()
	f = Vector3.new(f.X, 0, f.Z)
	if f.Magnitude < 0.01 then return false end
	return f.Unit:Dot(toTarget.Unit) >= cosFireAngle
end

local facingGoal -- Vector3? — se nil non ruotare attivamente
local dead = false

-- Tolleranza angolare: sotto questa, non riscriviamo la CFrame (così non
-- interferiamo con il movimento del Humanoid durante una camminata dritta).
local FACING_DEADZONE_RAD = math.rad(8)

RunService.Heartbeat:Connect(function(dt)
	if dead or not facingGoal then return end
	local lookVec = facingGoal - rootPart.Position
	lookVec = Vector3.new(lookVec.X, 0, lookVec.Z)
	if lookVec.Magnitude < 0.05 then return end
	lookVec = lookVec.Unit

	local f = realForward()
	f = Vector3.new(f.X, 0, f.Z)
	if f.Magnitude < 0.01 then return end
	f = f.Unit

	local dot = math.clamp(f:Dot(lookVec), -1, 1)
	local angle = math.acos(dot)
	if angle < FACING_DEADZONE_RAD then return end -- già allineato a sufficienza

	-- ruota di "step" verso il goal, non oltre l'angolo residuo
	local step = math.min(CONFIG.TURN_SPEED * dt, angle)
	-- direzione di rotazione (segno) dal cross product Y
	local sign = (f.X * lookVec.Z - f.Z * lookVec.X) < 0 and 1 or -1

	local linVel = rootPart.AssemblyLinearVelocity
	rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, sign * step, 0)
	rootPart.AssemblyLinearVelocity = linVel
end)

-- ============ BLASTER ===================
local lastShot = 0

local function applySpread(direction)
	if CONFIG.SPREAD_DEG <= 0 then return direction end
	local maxRad = math.rad(CONFIG.SPREAD_DEG)
	local yaw   = (math.random() * 2 - 1) * maxRad
	local pitch = (math.random() * 2 - 1) * maxRad
	return (CFrame.new(Vector3.zero, direction) * CFrame.Angles(pitch, yaw, 0)).LookVector
end

local function playMuzzle()
	if muzzleFlash and muzzleFlash:IsA("ParticleEmitter") then
		muzzleFlash:Emit(6)
	end
	if muzzleLight and muzzleLight:IsA("Light") then
		local saved = muzzleLight.Brightness
		muzzleLight.Enabled    = true
		muzzleLight.Brightness = math.max(saved, 4)
		task.delay(CONFIG.MUZZLE_FLASH_TIME, function()
			if muzzleLight then
				muzzleLight.Brightness = saved
				muzzleLight.Enabled    = false
			end
		end)
	end
	if fireSound and fireSound:IsA("Sound") then
		local s = fireSound:Clone()
		s.Parent = handle
		s:Play()
		Debris:AddItem(s, s.TimeLength > 0 and s.TimeLength + 0.1 or 2)
	end
end

local function tryFireAt(targetPosition)
	if not barrel then return end
	local now = os.clock()
	if now - lastShot < CONFIG.FIRE_COOLDOWN then return end
	lastShot = now

	local origin = barrel.Position
	local dir    = targetPosition - origin
	if dir.Magnitude < 0.01 then return end
	dir = applySpread(dir.Unit)

	playMuzzle()
	if tracks.Shoot and not tracks.Shoot.IsPlaying then
		tracks.Shoot:Play(0.05)
	end

	LaserSystem.Fire({
		origin         = origin,
		direction      = dir,
		shooter        = droid,
		shooterFaction = CONFIG.FACTION,
		damage         = CONFIG.DAMAGE,
	})
end

-- ============ DEATH =====================
local function isUnderBlaster(part)
	if not blaster then return false end
	return part:IsDescendantOf(blaster)
end

local function freezeRig()
	-- ancora le BasePart del rig così spinte/proiettili non spostano il cadavere.
	-- Eccezione: NON ancorare le Part del Blaster, altrimenti l'arma resta sospesa
	-- in aria mentre la mano scende durante la death animation.
	for _, p in ipairs(droid:GetDescendants()) do
		if p:IsA("BasePart") and not isUnderBlaster(p) then
			p.AssemblyLinearVelocity  = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
			p.Anchored = true
			-- collisioni off così i player non lo urtano accidentalmente
			p.CanCollide = false
		end
	end
end

local function onDeath()
	if dead then return end
	dead = true

	for _, key in ipairs({ "Idle", "Walk", "Shoot" }) do
		local t = tracks[key]
		if t and t.IsPlaying then t:Stop(0.1) end
	end
	if walkingSound and walkingSound.IsPlaying then walkingSound:Stop() end

	humanoid.AutoRotate    = false
	humanoid.WalkSpeed     = 0
	humanoid.JumpPower     = 0
	humanoid.PlatformStand = true
	facingGoal = nil

	-- Freeze immediato: niente spinte/rotolamenti durante la death animation.
	-- L'animazione Death anima le Motor6D del rig rispetto all'HRP, quindi la
	-- "caduta" si vede comunque anche con le Part anchored.
	freezeRig()

	task.spawn(function()
		if tracks.Death then
			tracks.Death:Play(0.1)
			if tracks.Death.Length > 0 then
				tracks.Death.Stopped:Wait()
			end
		end
		if tracks.DeathIdle then
			tracks.DeathIdle:Play(0.2)
		end
	end)

	Debris:AddItem(droid, CONFIG.DEATH_LINGER)
end
humanoid.Died:Connect(onDeath)

-- ============ MAIN LOOP =================
local function distXZ(a, b)
	local d = a - b
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

local currentTargetHrp

-- Cerca un bersaglio e (se hostile + allineato + in range) spara.
-- Restituisce true se c'è un target valido.
local function combatTick()
	if not isHostile then return false end
	local _, targetHrp, dist = findTarget()
	if not targetHrp then
		currentTargetHrp = nil
		return false
	end
	currentTargetHrp = targetHrp
	if dist and dist <= CONFIG.ATTACK_RANGE and angleAlignedTo(targetHrp.Position) then
		tryFireAt(targetHrp.Position)
	end
	return true
end

-- ====== PATHFINDING HELPER ======
-- Cammina fino a destPos usando PathfindingService, aggirando ostacoli e salendo
-- scalini. Ritorna quando arriva, quando muore, o quando rinuncia (dopo retry).
local function walkToWithPathfinding(destPos)
	if dead then return end

	local path = PathfindingService:CreatePath({
		AgentRadius  = CONFIG.AGENT_RADIUS,
		AgentHeight  = CONFIG.AGENT_HEIGHT,
		AgentCanJump = CONFIG.AGENT_CAN_JUMP,
	})

	local function travel()
		local ok = pcall(function()
			path:ComputeAsync(rootPart.Position, destPos)
		end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			-- fallback: MoveTo diretto
			humanoid:MoveTo(destPos)
			return false
		end

		local waypoints = path:GetWaypoints()
		for idx = 2, #waypoints do -- 1 è la posizione corrente
			if dead then return true end
			local wp = waypoints[idx]
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(wp.Position)

			local lastPos = rootPart.Position
			local stuckTimer = 0
			-- soglia di spostamento per essere considerato "in movimento":
			-- WalkSpeed * intervallo * fattore. Sotto questa soglia il droide è fermo.
			local moveThreshold = CONFIG.WALK_SPEED * CONFIG.REPATH_INTERVAL * 0.25
			while not dead do
				local d = (rootPart.Position - wp.Position)
				d = math.sqrt(d.X * d.X + d.Z * d.Z)
				if d <= CONFIG.PF_WAYPOINT_REACH then break end

				-- Combat opportunistico DURANTE il path: il droide non si gira verso il
				-- player. Continua a guardare il prossimo waypoint; spara SOLO se il
				-- player capita nell'arco di tiro davanti a lui (gestito in combatTick
				-- tramite angleAlignedTo). Niente face-tracking finché non finisce il path.
				combatTick()
				facingGoal = wp.Position

				-- Re-emetti MoveTo: dopo un salto (o un timeout interno del Humanoid)
				-- la direzione di movimento può azzerarsi e il droide "cammina nel vuoto".
				humanoid:MoveTo(wp.Position)

				-- Stuck detection: non contare come "stuck" se siamo in aria (es. dopo
				-- un salto). Aspetta di tornare a terra prima di rivalutare.
				-- NB: niente auto-jump per sbloccarsi — i droidi saltano solo se il
				-- PathfindingService inserisce esplicitamente un waypoint Jump.
				local airborne = humanoid.FloorMaterial == Enum.Material.Air
				local moved = (rootPart.Position - lastPos).Magnitude
				if not airborne and moved < moveThreshold then
					stuckTimer = stuckTimer + CONFIG.REPATH_INTERVAL
					if stuckTimer >= CONFIG.PF_REPATH_TIMEOUT then
						return false -- richiede ricalcolo
					end
				else
					stuckTimer = 0
				end
				lastPos = rootPart.Position

				task.wait(CONFIG.REPATH_INTERVAL)
			end
		end
		return true
	end

	-- prova fino a 3 volte con ricalcolo se si incastra
	for _ = 1, 3 do
		if dead then return end
		if travel() then return end
		task.wait(0.2)
	end
end

-- ====== STATE: PATH FOLLOWING ======
local function walkPath()
	local i = 1
	while not dead and pathParts and i <= #pathParts do
		local wp = pathParts[i]
		if wp and wp.Parent then
			playLocomotion("Walk")
			facingGoal = wp.Position
			walkToWithPathfinding(wp.Position)
		end

		i = i + 1
		if i > #pathParts and loopPath then i = 1 end
	end
end

-- ====== STATE: HUNT MODE (post-path) ======
local function huntMode()
	local lastKnown
	local searchEndsAt
	while not dead do
		local _, targetHrp, dist = findTarget()
		if targetHrp then
			currentTargetHrp = targetHrp
			lastKnown = targetHrp.Position
			searchEndsAt = nil
			facingGoal = targetHrp.Position
			if isHostile and dist and dist <= CONFIG.ATTACK_RANGE and angleAlignedTo(targetHrp.Position) then
				tryFireAt(targetHrp.Position)
			end
			if dist and dist > CONFIG.MELEE_STOP_RANGE then
				playLocomotion("Walk")
				walkToWithPathfinding(targetHrp.Position)
			else
				humanoid:MoveTo(rootPart.Position)
				playLocomotion("Idle")
				task.wait(CONFIG.REPATH_INTERVAL)
			end
		else
			currentTargetHrp = nil
			if lastKnown then
				if distXZ(rootPart.Position, lastKnown) > CONFIG.WAYPOINT_REACH then
					facingGoal = lastKnown
					playLocomotion("Walk")
					walkToWithPathfinding(lastKnown)
				else
					searchEndsAt = searchEndsAt or (os.clock() + CONFIG.HUNT_SEARCH_TIME)
					humanoid:MoveTo(rootPart.Position)
					playLocomotion("Idle")
					facingGoal = nil
					if os.clock() >= searchEndsAt then
						lastKnown = nil
						searchEndsAt = nil
					end
					task.wait(CONFIG.REPATH_INTERVAL)
				end
			else
				humanoid:MoveTo(rootPart.Position)
				playLocomotion("Idle")
				facingGoal = nil
				task.wait(CONFIG.REPATH_INTERVAL)
			end
		end
	end
end

task.spawn(function()
	if pathParts then
		walkPath()
	end
	if not dead then
		if isHostile then
			huntMode()
		else
			playLocomotion("Idle")
			humanoid:MoveTo(rootPart.Position)
			facingGoal = nil
		end
	end
end)

playLocomotion("Idle")
