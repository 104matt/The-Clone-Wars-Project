-- ShipScript.lua  (Script per-nave)
-- Posizione: una copia di questo Script va piazzata DENTRO ogni Model nave
-- in Workspace (es. Workspace.arc170.ShipScript).
--
-- Struttura attesa del Model nave:
--   VehicleSeat                  unico modo per salire (ProximityPrompt)
--   CameraPart                   anchor camera inseguimento
--   ZoomPart                     anchor camera mira
--   Laser1, Laser2               canne dei cannoni
--   LeftWing, RightWing          ali chiuse  (Part o Model)
--   OpenLeftWing, OpenRightWing  ali aperte  (Part o Model)
--
-- Configurazione della nave: Attributi sul Model (Properties -> Attributes):
--   Damage      (number)    danno per colpo                  default 30
--   MaxSpeed    (number)    velocita' massima in volo        default 150
--   FireSound   (string)    "rbxassetid://..." del cannone   default vuoto
--   ReloadSpeed (number)    secondi tra le raffiche          default 0.18
--   CanHover    (boolean)   abilita modalita' hover (N)      default false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

local ship          = script.Parent
local FlightEvents  = ReplicatedStorage:WaitForChild("FlightEvents")
local ShipEvent     = FlightEvents:WaitForChild("ShipEvent")

-- LaserBolt template lookup, PER-NAVE:
--   FlightEvents.<NomeModelloNave>.LaserBolt   (preferito)
--   FlightEvents.LaserBolt                     (fallback legacy / globale)
-- "NomeModelloNave" e' una Folder o Model dentro FlightEvents con stesso
-- nome del Model nave (es. "ARC-170"). Dentro deve esserci una BasePart
-- chiamata "LaserBolt".
local function resolveLaserTemplate()
	local perShip = FlightEvents:FindFirstChild(ship.Name)
	if perShip then
		local lb = perShip:FindFirstChild("LaserBolt")
		if lb and lb:IsA("BasePart") then return lb end
	end
	local globalLb = FlightEvents:FindFirstChild("LaserBolt")
	if globalLb and globalLb:IsA("BasePart") then return globalLb end
	return nil
end

local laserTemplate = resolveLaserTemplate()
if not laserTemplate then
	-- Riprova in modo asincrono: il template potrebbe arrivare dopo l'avvio.
	task.spawn(function()
		for _ = 1, 30 do
			task.wait(0.5)
			laserTemplate = resolveLaserTemplate()
			if laserTemplate then return end
		end
		warn(("[ShipScript] %s: nessun LaserBolt trovato in FlightEvents.%s o FlightEvents.LaserBolt.")
			:format(ship.Name, ship.Name))
	end)
end

local fireSound -- forward declaration: assegnata in fondo allo script

-- ============================================================================
-- CONFIG  (letta dagli Attributi del Model, con default sensati)
-- ============================================================================
local function attr(name, default)
	local v = ship:GetAttribute(name)
	if v == nil then return default end
	return v
end

local CONFIG = {
	Damage      = attr("Damage", 30),
	MaxSpeed    = attr("MaxSpeed", 150),
	FireSound   = attr("FireSound", ""),
	ReloadSpeed = attr("ReloadSpeed", 0.18),
	CanHover    = attr("CanHover", false),
}

-- Aggiorna live se uno modifica gli attributi in Studio
ship:GetAttributeChangedSignal("Damage"):Connect(function()      CONFIG.Damage      = attr("Damage", 30)       end)
ship:GetAttributeChangedSignal("MaxSpeed"):Connect(function()    CONFIG.MaxSpeed    = attr("MaxSpeed", 150)    end)
ship:GetAttributeChangedSignal("ReloadSpeed"):Connect(function() CONFIG.ReloadSpeed = attr("ReloadSpeed", 0.18) end)
ship:GetAttributeChangedSignal("CanHover"):Connect(function()    CONFIG.CanHover    = attr("CanHover", false)  end)
ship:GetAttributeChangedSignal("FireSound"):Connect(function()
	CONFIG.FireSound = attr("FireSound", "")
	if fireSound then fireSound.SoundId = CONFIG.FireSound end
end)

-- ============================================================================
-- RESOLVE PARTS
-- ============================================================================
local vehicleSeat = ship:FindFirstChildWhichIsA("VehicleSeat", true)
assert(vehicleSeat, ("[ShipScript] %s: VehicleSeat mancante."):format(ship.Name))

local cameraPart = ship:FindFirstChild("CameraPart", true)
local zoomPart   = ship:FindFirstChild("ZoomPart",   true)
local laser1     = ship:FindFirstChild("Laser1",     true)
local laser2     = ship:FindFirstChild("Laser2",     true)
local leftWing   = ship:FindFirstChild("LeftWing",      true)
local rightWing  = ship:FindFirstChild("RightWing",     true)
local openLeft   = ship:FindFirstChild("OpenLeftWing",  true)
local openRight  = ship:FindFirstChild("OpenRightWing", true)

if not ship.PrimaryPart then
	ship.PrimaryPart = (vehicleSeat:IsA("BasePart") and vehicleSeat)
		or ship:FindFirstChildWhichIsA("BasePart")
end
local primary = ship.PrimaryPart
assert(primary, ("[ShipScript] %s: PrimaryPart impossibile da determinare."):format(ship.Name))

-- ============================================================================
-- WELD MODEL
-- ============================================================================
local function ensureWeldedTo(root)
	root.Anchored = true
	for _, p in ipairs(ship:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			if not p:FindFirstChildOfClass("WeldConstraint") then
				local w = Instance.new("WeldConstraint")
				w.Part0  = root
				w.Part1  = p
				w.Parent = p
			end
			p.Anchored = false
		end
	end
end
ensureWeldedTo(primary)

-- Inizio: nave ferma (anchored). Diventa unanchored solo quando un pilota sale.
primary.Anchored = true

-- ============================================================================
-- VEHICLE SEAT TUNING
-- ============================================================================
vehicleSeat.MaxSpeed        = CONFIG.MaxSpeed
vehicleSeat.TurnSpeed       = 0.4
vehicleSeat.Torque          = 10
vehicleSeat.HeadsUpDisplay  = false  -- niente cerchio "Hold E" di default
-- Disabilitiamo la guida nativa del VehicleSeat: il client gestisce la fisica
-- via ShipGyro/ShipVelocity. Il giocatore puo' comunque sedersi.
vehicleSeat.Disabled        = true

-- ============================================================================
-- BODY MOVERS  (creati una volta, manipolati dal client durante il volo)
-- ============================================================================
local function ensureMover(name, class, setup)
	local m = primary:FindFirstChild(name)
	if not m or not m:IsA(class) then
		if m then m:Destroy() end
		m = Instance.new(class)
		m.Name   = name
		m.Parent = primary
	end
	setup(m)
	return m
end

local shipGyro = ensureMover("ShipGyro", "BodyGyro", function(g)
	g.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	-- P piu' basso e D piu' alto = movimento meno snappy, piu' fluido.
	-- Combinato col CFrame:Lerp del setpoint sul client da' una sterzata morbida.
	g.P         = 1800
	g.D         = 900
	g.CFrame    = primary.CFrame
end)

local shipVelocity = ensureMover("ShipVelocity", "BodyVelocity", function(v)
	v.MaxForce = Vector3.new(0, 0, 0) -- spento finche' nessuno pilota
	v.Velocity = Vector3.zero
end)

-- ============================================================================
-- WINGS
-- ============================================================================
local function setGroupTransparency(group, t)
	if not group then return end
	if group:IsA("BasePart") then group.Transparency = t end
	for _, d in ipairs(group:GetDescendants()) do
		if d:IsA("BasePart") then d.Transparency = t end
	end
end

local function updateWings(open)
	setGroupTransparency(leftWing,  open and 1 or 0)
	setGroupTransparency(rightWing, open and 1 or 0)
	setGroupTransparency(openLeft,  open and 0 or 1)
	setGroupTransparency(openRight, open and 0 or 1)
end
updateWings(false)

-- ============================================================================
-- ENGINE TRAIL
-- Cerchiamo nel modello ogni BasePart il cui nome inizia con "Engine"
-- (es. Engine, Engine1, EngineLeft) e ci attacchiamo un Trail visibile solo
-- a motore acceso. Se non ne trovi, il sistema resta silente.
-- ============================================================================
local engineTrails = {}

local function isEnginePart(p)
	if not p:IsA("BasePart") then return false end
	local n = p.Name
	return n == "Engine" or n:match("^Engine") ~= nil
end

local function buildEngineTrail(part)
	-- 2 attachments verticali sul retro della part (back face: local +Z)
	local sz = part.Size
	local at0 = part:FindFirstChild("EngineTrailA0")
	if not at0 then
		at0 = Instance.new("Attachment")
		at0.Name     = "EngineTrailA0"
		at0.Parent   = part
	end
	at0.Position = Vector3.new(0,  sz.Y / 2 * 0.7, sz.Z / 2)

	local at1 = part:FindFirstChild("EngineTrailA1")
	if not at1 then
		at1 = Instance.new("Attachment")
		at1.Name     = "EngineTrailA1"
		at1.Parent   = part
	end
	at1.Position = Vector3.new(0, -sz.Y / 2 * 0.7, sz.Z / 2)

	local trail = part:FindFirstChild("EngineTrail")
	if not trail or not trail:IsA("Trail") then
		if trail then trail:Destroy() end
		trail        = Instance.new("Trail")
		trail.Name   = "EngineTrail"
		trail.Parent = part
	end
	trail.Attachment0    = at0
	trail.Attachment1    = at1
	trail.Color          = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 235, 255)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30,  60, 180)),
	})
	trail.Transparency   = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.05),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1,   1),
	})
	trail.WidthScale     = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Lifetime       = 0.55
	trail.MinLength      = 0
	trail.MaxLength      = 0
	trail.LightEmission  = 1
	trail.LightInfluence = 0
	trail.FaceCamera     = true
	trail.Enabled        = false
	return trail
end

for _, d in ipairs(ship:GetDescendants()) do
	if isEnginePart(d) then
		table.insert(engineTrails, buildEngineTrail(d))
	end
end

-- ============================================================================
-- SFOIL TRAILS  (Part chiamate "TrailPart" nel modello)
-- Si accendono quando si APRONO le S-foils (esci da cruise). In cruise restano
-- spente. Tipico effetto X-wing / ARC-170 quando si va in full throttle.
-- ============================================================================
local sfoilTrails = {}

-- Tuning del trail stile film: scia bianca sottile e breve, molto luminosa.
-- Se non ti torna, regola questi numeri in cima alla funzione.
local SFOIL_TRAIL_SPAN_FRAC = 0.45  -- distanza tra i due Attachment (0..1 della Y della part). Piu' alto = scia piu' "spessa"
local SFOIL_TRAIL_LIFETIME  = 0.45  -- durata della scia (s). Piu' alto = scia piu' lunga
local SFOIL_TRAIL_WIDTH     = 0.6   -- WidthScale di partenza
local SFOIL_TRAIL_FACECAM   = true  -- guarda sempre la camera (look "movie")

local function buildSfoilTrail(part)
	local sz  = part.Size
	local at0 = part:FindFirstChild("SfoilTrailA0")
	if not at0 then
		at0 = Instance.new("Attachment")
		at0.Name   = "SfoilTrailA0"
		at0.Parent = part
	end
	at0.Position = Vector3.new(0,  sz.Y / 2 * SFOIL_TRAIL_SPAN_FRAC, sz.Z / 2)

	local at1 = part:FindFirstChild("SfoilTrailA1")
	if not at1 then
		at1 = Instance.new("Attachment")
		at1.Name   = "SfoilTrailA1"
		at1.Parent = part
	end
	at1.Position = Vector3.new(0, -sz.Y / 2 * SFOIL_TRAIL_SPAN_FRAC, sz.Z / 2)

	local trail = part:FindFirstChild("SfoilTrail")
	if not trail or not trail:IsA("Trail") then
		if trail then trail:Destroy() end
		trail        = Instance.new("Trail")
		trail.Name   = "SfoilTrail"
		trail.Parent = part
	end
	trail.Attachment0 = at0
	trail.Attachment1 = at1

	-- Colore: pure white core con velo cyan tenue verso la coda
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(220, 240, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(150, 200, 255)),
	})

	-- Transparency: parte quasi opaca, sfuma rapidamente a invisibile
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.05),
		NumberSequenceKeypoint.new(0.35, 0.4),
		NumberSequenceKeypoint.new(1,    1),
	})

	-- WidthScale: triangolare, parte sottile e finisce a punta
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, SFOIL_TRAIL_WIDTH),
		NumberSequenceKeypoint.new(1, 0),
	})

	trail.Lifetime       = SFOIL_TRAIL_LIFETIME
	trail.MinLength      = 0
	trail.MaxLength      = 0
	trail.LightEmission  = 1            -- pieno glow (richiesto per il look "cinema")
	trail.LightInfluence = 0
	trail.FaceCamera     = SFOIL_TRAIL_FACECAM
	trail.Enabled        = false
	return trail
end

for _, d in ipairs(ship:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "TrailPart" then
		table.insert(sfoilTrails, buildSfoilTrail(d))
	end
end

local function setSfoilTrails(enabled)
	for _, t in ipairs(sfoilTrails) do
		t.Enabled = enabled
	end
end

-- ============================================================================
-- ENGINE STATE
-- ============================================================================
local engineOn = false

local function setEngine(on)
	if engineOn == on then return end
	engineOn = on
	if on then
		primary.Anchored      = false
		shipGyro.CFrame       = primary.CFrame
		shipGyro.MaxTorque    = Vector3.new(math.huge, math.huge, math.huge)
		shipVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		shipVelocity.Velocity = Vector3.zero
		for _, t in ipairs(engineTrails) do t.Enabled = true end
	else
		shipVelocity.Velocity = Vector3.zero
		shipVelocity.MaxForce = Vector3.new(0, 0, 0)
		shipGyro.MaxTorque    = Vector3.new(0, 0, 0)
		primary.Anchored      = true
		for _, t in ipairs(engineTrails) do t.Enabled = false end
	end
end

-- ============================================================================
-- FIRE SOUND
-- ============================================================================
do
	local s = primary:FindFirstChild("FireSound")
	if not s or not s:IsA("Sound") then
		if s then s:Destroy() end
		s = Instance.new("Sound")
		s.Name   = "FireSound"
		s.Volume = 1
		s.Parent = primary
	end
	s.SoundId = CONFIG.FireSound
	fireSound = s
end

-- ============================================================================
-- ENTRY: solo via ProximityPrompt
-- ============================================================================
local prompt = vehicleSeat:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.Parent = vehicleSeat
end
prompt.ActionText            = "Pilot"
prompt.ObjectText            = ship.Name
prompt.KeyboardKeyCode       = Enum.KeyCode.E
prompt.HoldDuration          = 0
prompt.MaxActivationDistance = 14
prompt.RequiresLineOfSight   = false
prompt.Enabled               = true

local entryArmed = false

prompt.Triggered:Connect(function(player)
	if vehicleSeat.Occupant then return end
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	entryArmed = true
	vehicleSeat:Sit(hum)
	task.delay(0.5, function() entryArmed = false end)
end)

-- ============================================================================
-- OCCUPANT CHANGE: gestisce anchored, body movers, ali, network ownership
-- ============================================================================
local function onEnter()
	-- Restituiamo l'ownership al pilota cosi' il volo client-side e' fluido.
	local occupant = vehicleSeat.Occupant
	local player   = occupant and game:GetService("Players"):GetPlayerFromCharacter(occupant.Parent)
	if player then
		pcall(function() primary:SetNetworkOwner(player) end)
	end
	-- Motore spento all'ingresso: la nave resta ferma finche' il pilota non
	-- preme R (gestito dal client tramite ShipEvent "EngineToggle").
	setEngine(false)
	prompt.Enabled = false
end

local function onExit()
	setEngine(false)
	pcall(function() primary:SetNetworkOwner(nil) end)
	updateWings(false)
	setSfoilTrails(false)
	prompt.Enabled = true
end

vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = vehicleSeat.Occupant
	if occupant and not entryArmed then
		-- Qualcuno ha "toccato" il sedile senza usare il prompt: lo cacciamo.
		local hrp = occupant.Parent and occupant.Parent:FindFirstChild("HumanoidRootPart")
		vehicleSeat:Sit(nil)
		if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0, 4, 0) end
		return
	end
	if occupant then
		onEnter()
	else
		onExit()
	end
end)

-- ============================================================================
-- SHIP HEALTH / SHIELDS
-- ============================================================================
-- Stato di vita della nave, replicato al client tramite Attributi:
--   MaxHealth, MaxShields            -> tetto (lettura)
--   CurrentHealth, CurrentShields    -> stato vivo (server scrive, client legge)
-- Tuning live: modificabile da Studio come Attributes del Model.
local MAX_HEALTH         = attr("MaxHealth",        100)
local MAX_SHIELDS        = attr("MaxShields",       100)
local SHIELD_REGEN_DELAY = attr("ShieldRegenDelay", 4)   -- s dopo l'ultimo hit
local SHIELD_REGEN_RATE  = attr("ShieldRegenRate",  20)  -- punti/s

ship:SetAttribute("MaxHealth",      MAX_HEALTH)
ship:SetAttribute("MaxShields",     MAX_SHIELDS)
ship:SetAttribute("CurrentHealth",  MAX_HEALTH)
ship:SetAttribute("CurrentShields", MAX_SHIELDS)

local lastHitClock = -math.huge
local lastShieldsSeen = MAX_SHIELDS
local lastHealthSeen  = MAX_HEALTH

-- Quando un'altra nave/colpo riduce i nostri scudi o scafo via Attribute,
-- consideriamo il momento come "ultimo hit" -> blocca regen per SHIELD_REGEN_DELAY.
ship:GetAttributeChangedSignal("CurrentShields"):Connect(function()
	local v = ship:GetAttribute("CurrentShields") or 0
	if v < lastShieldsSeen then lastHitClock = os.clock() end
	lastShieldsSeen = v
end)
ship:GetAttributeChangedSignal("CurrentHealth"):Connect(function()
	local v = ship:GetAttribute("CurrentHealth") or 0
	if v < lastHealthSeen then lastHitClock = os.clock() end
	lastHealthSeen = v
	if v <= 0 then
		-- TODO: morte/esplosione nave. Per ora la nave resta, da implementare.
		-- (lasciamo i scudi/HP a 0 finche' non si rigenerano dopo il delay).
	end
end)

-- Regen scudi: se da SHIELD_REGEN_DELAY non c'e' stato un hit, ricarica.
task.spawn(function()
	while ship.Parent do
		task.wait(0.25)
		local now = os.clock()
		if now - lastHitClock >= SHIELD_REGEN_DELAY then
			local s = ship:GetAttribute("CurrentShields") or 0
			local maxS = ship:GetAttribute("MaxShields") or MAX_SHIELDS
			if s < maxS then
				ship:SetAttribute("CurrentShields", math.min(maxS, s + SHIELD_REGEN_RATE * 0.25))
			end
		end
	end
end)

-- ============================================================================
-- SHOOTING
-- ============================================================================
local LASER_SPEED         = 750
local LASER_LIFETIME      = 5
local lastShot            = 0
local BULLETS_FOLDER_NAME = "ShipBullets"

local function getBulletsFolder()
	local f = Workspace:FindFirstChild(BULLETS_FOLDER_NAME)
	if not f then
		f        = Instance.new("Folder")
		f.Name   = BULLETS_FOLDER_NAME
		f.Parent = Workspace
	end
	return f
end

-- Risale dalla part colpita al Model "nave" (cerca un VehicleSeat tra i
-- discendenti). Se trovato e diverso da noi, applichiamo danno alla nave.
local function findShipModelFrom(hitInstance)
	local m = hitInstance:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildWhichIsA("VehicleSeat", true) then return m end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") or nil
	end
	return nil
end

local function spawnLaser(originPos, direction)
	-- Lazy-resolve template se aggiunto dopo l'avvio
	if not laserTemplate or not laserTemplate:IsA("BasePart") then
		laserTemplate = resolveLaserTemplate()
	end
	if not laserTemplate or not laserTemplate:IsA("BasePart") then
		warn(("[ShipScript] %s: LaserBolt non trovato (FlightEvents.%s.LaserBolt)."):format(ship.Name, ship.Name))
		return
	end
	if direction.Magnitude < 1e-3 or direction.X ~= direction.X then return end

	local laser = laserTemplate:Clone()
	laser.Name       = "ShipLaser"
	laser.Anchored   = true
	laser.CanCollide = false
	laser.CanQuery   = false
	laser.CanTouch   = false
	laser.CFrame     = CFrame.lookAt(originPos, originPos + direction)
	laser.Parent     = getBulletsFolder()

	task.spawn(function()
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { ship, getBulletsFolder() }
		rayParams.IgnoreWater = true

		local startTime = os.clock()
		local lastTime  = startTime

		while laser.Parent and (os.clock() - startTime) < LASER_LIFETIME do
			local now = os.clock()
			local dt  = now - lastTime
			lastTime  = now

			local step = direction * LASER_SPEED * dt
			local hit  = workspace:Raycast(laser.Position, step, rayParams)
			if hit then
				laser.CFrame = CFrame.lookAt(hit.Position, hit.Position + direction)
				-- 1) Nave colpita: danno a scudi -> scafo via Attributes.
				-- Il suo ShipScript ascolta CurrentHealth/Shields e replica all'HUD.
				local hitShip = findShipModelFrom(hit.Instance)
				if hitShip and hitShip ~= ship then
					local s    = hitShip:GetAttribute("CurrentShields") or 0
					local h    = hitShip:GetAttribute("CurrentHealth")  or 0
					local left = CONFIG.Damage
					if s > 0 then
						local absorbed = math.min(s, left)
						hitShip:SetAttribute("CurrentShields", s - absorbed)
						left = left - absorbed
					end
					if left > 0 then
						hitShip:SetAttribute("CurrentHealth", math.max(0, h - left))
					end
				else
					-- 2) Player a piedi (Humanoid)
					local model = hit.Instance:FindFirstAncestorOfClass("Model")
					local hum   = model and model:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						hum:TakeDamage(CONFIG.Damage)
					end
				end
				break
			end

			laser.CFrame = laser.CFrame + step
			task.wait()
		end

		if laser.Parent then laser:Destroy() end
	end)
end

ShipEvent.OnServerEvent:Connect(function(player, action, data)
	if typeof(data) ~= "table" then return end
	if vehicleSeat.Occupant == nil then return end
	local pilotChar = vehicleSeat.Occupant.Parent
	if pilotChar ~= player.Character then return end -- non sta pilotando questa nave

	if action == "Shoot" then
		if typeof(data.Direction) ~= "Vector3" then return end
		local now = os.clock()
		if now - lastShot < CONFIG.ReloadSpeed then return end
		lastShot = now

		local dir = data.Direction.Unit
		local fired = false
		if laser1 then spawnLaser(laser1.Position, dir); fired = true end
		if laser2 then spawnLaser(laser2.Position, dir); fired = true end
		if not fired then
			spawnLaser(primary.Position + primary.CFrame.LookVector * 8, dir)
		end
		if fireSound and fireSound.SoundId ~= "" then
			fireSound:Play()
		end

	elseif action == "ToggleSfoils" then
		local open = data.State == true
		updateWings(open)
		-- Sfoil trails accese solo a foils APERTE (= esci da cruise)
		setSfoilTrails(open)

	elseif action == "EngineToggle" then
		setEngine(data.State == true)

	elseif action == "DrivePhysics" then
		-- Il client invia setpoint per BodyGyro/BodyVelocity. Lavorando con
		-- network ownership corretta questi sarebbero gia' replicati, ma
		-- li sincronizziamo come backup per gli osservatori.
		if typeof(data.CFrame) == "CFrame" then
			shipGyro.CFrame = data.CFrame
		end
		if typeof(data.Velocity) == "Vector3" then
			shipVelocity.Velocity = data.Velocity
		end
	end
end)
