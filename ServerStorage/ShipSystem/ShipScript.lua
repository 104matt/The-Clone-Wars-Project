-- ShipScript.lua  (Script per-nave)  -- DEBUG BUILD --
-- Base: commit 663b986 (audio completo, raycast laser, health/shields).
-- Aggiunte: Faction/fuoco amico, Converge per-cannone, wingtip trails.
--
-- Struttura attesa del Model nave:
--   VehicleSeat                  unico modo per salire (ProximityPrompt)
--   CameraPart                   anchor camera inseguimento
--   ZoomPart                     anchor camera mira
--   Laser1, Laser2, ...          canne dei cannoni (auto-detect)
--   LeftWing, RightWing          ali chiuse  (Hangar)
--   OpenLeftWing, OpenRightWing  ali aperte  (Combat) - wingtip trails qui dentro
--   TrailPart (x N)              sfoil trails aggiuntivi (opzionali)
--   Engine, Engine1...           parti motore (engine trail auto)
--
-- Attributi sul Model (Properties -> Attributes):
--   Damage           (number)   default 30
--   MaxSpeed         (number)   default 150
--   ReloadSpeed      (number)   default 0.18
--   CanHover         (boolean)  default false
--   Faction          (string)   default "Republic"  <- evita fuoco amico
--   CannonsPerShot   (number)   default 0 (tutti simultanei)
--   MaxHealth        (number)   default 100
--   MaxShields       (number)   default 100
--   ShieldRegenDelay (number)   default 4
--   ShieldRegenRate  (number)   default 20
--
-- SUONI (Attribute = ID numerico o "rbxassetid://..."):
--   GetInSound / TurnOn / TurnOff / FireSound / ShipSound / HyperdriveSound

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

local ship = script.Parent
print("[DBG] ShipScript avviato su:", ship:GetFullName())

-- ============================================================================
-- FlightEvents / ShipEvent
-- ============================================================================
print("[DBG] In attesa di FlightEvents...")
local FlightEvents = ReplicatedStorage:WaitForChild("FlightEvents")
print("[DBG] FlightEvents OK")
local ShipEvent = FlightEvents:WaitForChild("ShipEvent")
print("[DBG] ShipEvent OK")

-- LaserBolt: cerca prima FlightEvents/<NomeNave>/LaserBolt, poi globale.
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
if laserTemplate then
	print("[DBG] LaserBolt trovato:", laserTemplate:GetFullName())
else
	warn("[DBG] LaserBolt non trovato, riprovo in background...")
	task.spawn(function()
		for _ = 1, 30 do
			task.wait(0.5)
			laserTemplate = resolveLaserTemplate()
			if laserTemplate then
				print("[DBG] LaserBolt trovato (ritardato):", laserTemplate:GetFullName())
				return
			end
		end
		warn(("[ShipScript] %s: nessun LaserBolt trovato."):format(ship.Name))
	end)
end

local fireSound, turnOnSound, turnOffSound, getInSound, shipSound, hyperdriveSound
local playOneShot  -- forward declaration (usata da setEngine, definita dopo makeSound)

-- ============================================================================
-- CONFIG
-- ============================================================================
local function attr(name, default)
	local v = ship:GetAttribute(name)
	if v == nil then return default end
	return v
end

-- Default suoni per nave. Usati se l'Attribute non e' impostato.
local SHIP_SOUND_DEFAULTS = {
	["ARC-170"] = {
		GetInSound      = 105966537536689,
		TurnOn          = 90765152008789,
		TurnOff         = 79557556820924,
		FireSound       = 97781007184418,
		ShipSound       = 89291410626502,
		HyperdriveSound = 86925955851170,
	},
}

local function toSoundId(v)
	if v == nil or v == "" then return "" end
	if typeof(v) == "number" then return "rbxassetid://" .. v end
	local s = tostring(v)
	if s:match("^rbxassetid://") then return s end
	if s:match("^%d+$")           then return "rbxassetid://" .. s end
	return s
end

local function soundAttr(name)
	local v = ship:GetAttribute(name)
	if v == nil or v == "" then
		local d = SHIP_SOUND_DEFAULTS[ship.Name]
		if d then v = d[name] end
	end
	return toSoundId(v)
end

local CONFIG = {
	Damage          = attr("Damage",      30),
	MaxSpeed        = attr("MaxSpeed",    150),
	ReloadSpeed     = attr("ReloadSpeed", 0.18),
	CanHover        = attr("CanHover",    false),
	Faction         = attr("Faction",     "Republic"),
	FireSound       = soundAttr("FireSound"),
	GetInSound      = soundAttr("GetInSound"),
	TurnOn          = soundAttr("TurnOn"),
	TurnOff         = soundAttr("TurnOff"),
	ShipSound       = soundAttr("ShipSound"),
	HyperdriveSound = soundAttr("HyperdriveSound"),
}

print(("[DBG] CONFIG: Faction=%s Damage=%s MaxSpeed=%s ReloadSpeed=%s"):format(
	tostring(CONFIG.Faction), tostring(CONFIG.Damage),
	tostring(CONFIG.MaxSpeed), tostring(CONFIG.ReloadSpeed)
))

ship:GetAttributeChangedSignal("Damage"):Connect(function()      CONFIG.Damage      = attr("Damage", 30)        end)
ship:GetAttributeChangedSignal("MaxSpeed"):Connect(function()    CONFIG.MaxSpeed    = attr("MaxSpeed", 150)     end)
ship:GetAttributeChangedSignal("ReloadSpeed"):Connect(function() CONFIG.ReloadSpeed = attr("ReloadSpeed", 0.18) end)
ship:GetAttributeChangedSignal("CanHover"):Connect(function()    CONFIG.CanHover    = attr("CanHover", false)   end)
ship:GetAttributeChangedSignal("Faction"):Connect(function()     CONFIG.Faction     = attr("Faction", "Republic") end)

local function bindSoundAttr(attrName, target)
	ship:GetAttributeChangedSignal(attrName):Connect(function()
		CONFIG[attrName] = soundAttr(attrName)
		if target() then target().SoundId = CONFIG[attrName] end
	end)
end
bindSoundAttr("FireSound",       function() return fireSound end)
bindSoundAttr("GetInSound",      function() return getInSound end)
bindSoundAttr("TurnOn",          function() return turnOnSound end)
bindSoundAttr("TurnOff",         function() return turnOffSound end)
bindSoundAttr("ShipSound",       function() return shipSound end)
bindSoundAttr("HyperdriveSound", function() return hyperdriveSound end)

-- ============================================================================
-- RESOLVE PARTS
-- ============================================================================
print("[DBG] Cerco VehicleSeat...")
local vehicleSeat = ship:FindFirstChildWhichIsA("VehicleSeat", true)
if not vehicleSeat then
	error("[DBG] ERRORE FATALE: VehicleSeat non trovato in " .. ship:GetFullName())
end
print("[DBG] VehicleSeat:", vehicleSeat:GetFullName())

local cameraPart = ship:FindFirstChild("CameraPart", true)
local zoomPart   = ship:FindFirstChild("ZoomPart",   true)
local leftWing   = ship:FindFirstChild("LeftWing",      true)
local rightWing  = ship:FindFirstChild("RightWing",     true)
local openLeft   = ship:FindFirstChild("OpenLeftWing",  true)
local openRight  = ship:FindFirstChild("OpenRightWing", true)

print(("[DBG] CameraPart=%s ZoomPart=%s LeftWing=%s RightWing=%s OpenLeft=%s OpenRight=%s"):format(
	tostring(cameraPart~=nil), tostring(zoomPart~=nil),
	tostring(leftWing~=nil),   tostring(rightWing~=nil),
	tostring(openLeft~=nil),   tostring(openRight~=nil)
))

-- Cannoni: auto-detect Laser1, Laser2, Laser3, ...
local cannons = {}
do
	local i = 1
	while true do
		local c = ship:FindFirstChild("Laser" .. i, true)
		if not c then break end
		table.insert(cannons, c)
		i = i + 1
	end
end
local cannonIndex = 0
print("[DBG] Cannoni trovati:", #cannons)

if not ship.PrimaryPart then
	print("[DBG] PrimaryPart non impostato, uso VehicleSeat o primo BasePart")
	ship.PrimaryPart = (vehicleSeat:IsA("BasePart") and vehicleSeat)
		or ship:FindFirstChildWhichIsA("BasePart")
end
local primary = ship.PrimaryPart
if not primary then
	error("[DBG] ERRORE FATALE: PrimaryPart impossibile da determinare in " .. ship:GetFullName())
end
print("[DBG] PrimaryPart:", primary:GetFullName())

-- ============================================================================
-- WELD MODEL
-- ============================================================================
print("[DBG] Avvio weld...")
local weldCount = 0
local function ensureWeldedTo(root)
	root.Anchored = true
	for _, p in ipairs(ship:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			if not p:FindFirstChildOfClass("WeldConstraint") then
				local w = Instance.new("WeldConstraint")
				w.Part0  = root
				w.Part1  = p
				w.Parent = p
				weldCount = weldCount + 1
			end
			p.Anchored = false
		end
	end
end
ensureWeldedTo(primary)
print("[DBG] Weld OK:", weldCount, "vincoli creati")
primary.Anchored = true

-- ============================================================================
-- VEHICLE SEAT TUNING
-- ============================================================================
vehicleSeat.MaxSpeed       = CONFIG.MaxSpeed
vehicleSeat.TurnSpeed      = 0.4
vehicleSeat.Torque         = 10
vehicleSeat.HeadsUpDisplay = false
vehicleSeat.Disabled       = true
print("[DBG] VehicleSeat configurato, Disabled=true")

-- ============================================================================
-- BODY MOVERS
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
	g.P         = 1800
	g.D         = 900
	g.CFrame    = primary.CFrame
end)
local shipVelocity = ensureMover("ShipVelocity", "BodyVelocity", function(v)
	v.MaxForce = Vector3.new(0, 0, 0)
	v.Velocity = Vector3.zero
end)
print("[DBG] BodyGyro + BodyVelocity creati")

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

-- Wingtip trails: Trail/ParticleEmitter dentro OpenLeftWing/OpenRightWing.
-- ON in Combat (sfoils aperte), OFF in Hangar.
local wingtipTrails = {}
local function collectWingtipTrails()
	for _, group in ipairs({ openLeft, openRight }) do
		if group then
			for _, d in ipairs(group:GetDescendants()) do
				if d:IsA("Trail") or d:IsA("ParticleEmitter") then
					table.insert(wingtipTrails, d)
				end
			end
		end
	end
end
collectWingtipTrails()
print("[DBG] Wingtip trails:", #wingtipTrails)

local function setWingtipTrails(on)
	for _, t in ipairs(wingtipTrails) do t.Enabled = on end
end

-- open=true  -> ali aperte (Combat): OpenLeft/Right visibili, Left/Right nascosti
-- open=false -> ali chiuse (Hangar): Left/Right visibili, OpenLeft/Right nascosti
local function updateWings(open)
	setGroupTransparency(leftWing,  open and 1 or 0)
	setGroupTransparency(rightWing, open and 1 or 0)
	setGroupTransparency(openLeft,  open and 0 or 1)
	setGroupTransparency(openRight, open and 0 or 1)
	setWingtipTrails(open)
end
updateWings(false)  -- default: Hangar (ali chiuse)

-- ============================================================================
-- SFOIL TRAILS  (Part "TrailPart" nel modello, opzionali)
-- ============================================================================
local sfoilTrails = {}
local SFOIL_TRAIL_SPAN_FRAC = 0.45
local SFOIL_TRAIL_LIFETIME  = 0.45
local SFOIL_TRAIL_WIDTH     = 0.6
local SFOIL_TRAIL_FACECAM   = true

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
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(220, 240, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(150, 200, 255)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.05),
		NumberSequenceKeypoint.new(0.35, 0.4),
		NumberSequenceKeypoint.new(1,    1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, SFOIL_TRAIL_WIDTH),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Lifetime       = SFOIL_TRAIL_LIFETIME
	trail.MinLength      = 0
	trail.MaxLength      = 0
	trail.LightEmission  = 1
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
	for _, t in ipairs(sfoilTrails) do t.Enabled = enabled end
end
print("[DBG] SfoilTrails (TrailPart):", #sfoilTrails)

-- ============================================================================
-- ENGINE TRAIL  (Part "Engine*" nel modello)
-- ============================================================================
local engineTrails = {}
local function isEnginePart(p)
	if not p:IsA("BasePart") then return false end
	local n = p.Name
	return n == "Engine" or n:match("^Engine") ~= nil
end
local function buildEngineTrail(part)
	local sz = part.Size
	local at0 = part:FindFirstChild("EngineTrailA0")
	if not at0 then
		at0 = Instance.new("Attachment")
		at0.Name   = "EngineTrailA0"
		at0.Parent = part
	end
	at0.Position = Vector3.new(0, sz.Y / 2 * 0.7, sz.Z / 2)
	local at1 = part:FindFirstChild("EngineTrailA1")
	if not at1 then
		at1 = Instance.new("Attachment")
		at1.Name   = "EngineTrailA1"
		at1.Parent = part
	end
	at1.Position = Vector3.new(0, -sz.Y / 2 * 0.7, sz.Z / 2)
	local trail = part:FindFirstChild("EngineTrail")
	if not trail or not trail:IsA("Trail") then
		if trail then trail:Destroy() end
		trail      = Instance.new("Trail")
		trail.Name = "EngineTrail"
		trail.Parent = part
	end
	trail.Attachment0 = at0
	trail.Attachment1 = at1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(170, 235, 255)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80,  160, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(30,   60, 180)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.05),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1,   1),
	})
	trail.WidthScale = NumberSequence.new({
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
print("[DBG] Engine trails:", #engineTrails)

-- ============================================================================
-- ENGINE STATE
-- ============================================================================
local engineOn = false
local function setEngine(on)
	print("[DBG] setEngine:", on, "(era:", engineOn, ")")
	if engineOn == on then return end
	engineOn = on
	if on then
		primary.Anchored      = false
		shipGyro.CFrame       = primary.CFrame
		shipGyro.MaxTorque    = Vector3.new(math.huge, math.huge, math.huge)
		shipVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		shipVelocity.Velocity = Vector3.zero
		for _, t in ipairs(engineTrails) do t.Enabled = true end
		playOneShot(turnOnSound)
		if shipSound and shipSound.SoundId ~= "" and not shipSound.IsPlaying then
			shipSound:Play()
		end
		print("[DBG] Motore ACCESO")
	else
		shipVelocity.Velocity = Vector3.zero
		shipVelocity.MaxForce = Vector3.new(0, 0, 0)
		shipGyro.MaxTorque    = Vector3.new(0, 0, 0)
		primary.Anchored      = true
		for _, t in ipairs(engineTrails) do t.Enabled = false end
		if shipSound and shipSound.IsPlaying then shipSound:Stop() end
		playOneShot(turnOffSound)
		print("[DBG] Motore SPENTO")
	end
end

-- ============================================================================
-- SOUNDS
-- ============================================================================
local function makeSound(name, soundId, opts)
	opts = opts or {}
	local s = primary:FindFirstChild(name)
	if not s or not s:IsA("Sound") then
		if s then s:Destroy() end
		s        = Instance.new("Sound")
		s.Name   = name
		s.Parent = primary
	end
	s.SoundId              = soundId or ""
	s.Volume               = opts.Volume or 1
	s.Looped               = opts.Looped or false
	s.RollOffMode          = opts.RollOffMode or Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance   = opts.MinDist or 10
	s.RollOffMaxDistance   = opts.MaxDist or 250
	return s
end

fireSound       = makeSound("FireSound",       CONFIG.FireSound,       { Volume = 1 })
getInSound      = makeSound("GetInSound",      CONFIG.GetInSound,      { Volume = 0.9, MaxDist = 60 })
turnOnSound     = makeSound("TurnOn",          CONFIG.TurnOn,          { Volume = 1 })
turnOffSound    = makeSound("TurnOff",         CONFIG.TurnOff,         { Volume = 1 })
shipSound       = makeSound("ShipSound",       CONFIG.ShipSound,       { Volume = 0.6, Looped = true, MaxDist = 400 })
hyperdriveSound = makeSound("HyperdriveSound", CONFIG.HyperdriveSound, { Volume = 1,   MaxDist = 350 })

print(("[DBG] Suoni: FireSound=%s TurnOn=%s GetInSound=%s ShipSound=%s"):format(
	tostring(fireSound.SoundId ~= ""), tostring(turnOnSound.SoundId ~= ""),
	tostring(getInSound.SoundId ~= ""), tostring(shipSound.SoundId ~= "")
))

-- Definisce playOneShot (usata da setEngine sopra tramite forward decl.)
playOneShot = function(s)
	if s and s.SoundId ~= "" then
		s.TimePosition = 0
		s:Play()
	end
end

-- ============================================================================
-- ENTRY: ProximityPrompt
-- ============================================================================
local prompt = vehicleSeat:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.Parent = vehicleSeat
	print("[DBG] ProximityPrompt creato")
else
	print("[DBG] ProximityPrompt esistente trovato")
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
	print("[DBG] Prompt triggerato da:", player.Name, "| Occupant:", tostring(vehicleSeat.Occupant))
	if vehicleSeat.Occupant then return end
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then warn("[DBG] Humanoid non trovato per", player.Name); return end
	entryArmed = true
	vehicleSeat:Sit(hum)
	print("[DBG] :Sit() chiamato per", player.Name)
	task.delay(0.5, function() entryArmed = false end)
end)

-- ============================================================================
-- OCCUPANT CHANGE
-- ============================================================================
local function onEnter()
	local occupant = vehicleSeat.Occupant
	local player   = occupant and game:GetService("Players"):GetPlayerFromCharacter(occupant.Parent)
	print("[DBG] onEnter: player =", tostring(player and player.Name))
	if player then
		local ok, err = pcall(function() primary:SetNetworkOwner(player) end)
		if not ok then warn("[DBG] SetNetworkOwner fallito:", err) end
	end
	setEngine(false)
	-- Avvio in Hangar: ali CHIUSE
	updateWings(false)
	setSfoilTrails(false)
	playOneShot(getInSound)
	prompt.Enabled = false
	print("[DBG] Ingresso completato")
end

local function onExit()
	print("[DBG] onExit")
	setEngine(false)
	pcall(function() primary:SetNetworkOwner(nil) end)
	updateWings(false)
	setSfoilTrails(false)
	prompt.Enabled = true
	print("[DBG] Uscita completata")
end

vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = vehicleSeat.Occupant
	print("[DBG] Occupant cambiato:", tostring(occupant), "| entryArmed:", entryArmed)
	if occupant and not entryArmed then
		warn("[DBG] Seduta senza prompt! Espello.")
		local hrp = occupant.Parent and occupant.Parent:FindFirstChild("HumanoidRootPart")
		vehicleSeat:Sit(nil)
		if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0, 4, 0) end
		return
	end
	if occupant then onEnter() else onExit() end
end)

-- ============================================================================
-- SHIP HEALTH / SHIELDS
-- ============================================================================
local MAX_HEALTH         = attr("MaxHealth",        100)
local MAX_SHIELDS        = attr("MaxShields",       100)
local SHIELD_REGEN_DELAY = attr("ShieldRegenDelay", 4)
local SHIELD_REGEN_RATE  = attr("ShieldRegenRate",  20)

ship:SetAttribute("MaxHealth",      MAX_HEALTH)
ship:SetAttribute("MaxShields",     MAX_SHIELDS)
ship:SetAttribute("CurrentHealth",  MAX_HEALTH)
ship:SetAttribute("CurrentShields", MAX_SHIELDS)

local lastHitClock    = -math.huge
local lastShieldsSeen = MAX_SHIELDS
local lastHealthSeen  = MAX_HEALTH

ship:GetAttributeChangedSignal("CurrentShields"):Connect(function()
	local v = ship:GetAttribute("CurrentShields") or 0
	if v < lastShieldsSeen then lastHitClock = os.clock() end
	lastShieldsSeen = v
end)
ship:GetAttributeChangedSignal("CurrentHealth"):Connect(function()
	local v = ship:GetAttribute("CurrentHealth") or 0
	if v < lastHealthSeen then lastHitClock = os.clock() end
	lastHealthSeen = v
end)

task.spawn(function()
	while ship.Parent do
		task.wait(0.25)
		if os.clock() - lastHitClock >= SHIELD_REGEN_DELAY then
			local s    = ship:GetAttribute("CurrentShields") or 0
			local maxS = ship:GetAttribute("MaxShields") or MAX_SHIELDS
			if s < maxS then
				ship:SetAttribute("CurrentShields", math.min(maxS, s + SHIELD_REGEN_RATE * 0.25))
			end
		end
	end
end)

print("[DBG] ========== ShipScript inizializzazione COMPLETATA:", ship.Name, "==========")

-- ============================================================================
-- SHOOTING  (raycast, come 663b986)
-- ============================================================================
local LASER_SPEED    = 750
local LASER_LIFETIME = 5
local lastShot       = 0
local BULLETS_FOLDER_NAME = "ShipBullets"

local function getBulletsFolder()
	local f = Workspace:FindFirstChild(BULLETS_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name   = BULLETS_FOLDER_NAME
		f.Parent = Workspace
	end
	return f
end

local function findShipModelFrom(hitInstance)
	local m = hitInstance:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildWhichIsA("VehicleSeat", true) then return m end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") or nil
	end
	return nil
end

local function spawnLaser(originPos, direction)
	if not laserTemplate or not laserTemplate:IsA("BasePart") then
		laserTemplate = resolveLaserTemplate()
	end
	if not laserTemplate or not laserTemplate:IsA("BasePart") then
		warn("[ShipScript] LaserBolt non trovato.")
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
			local now  = os.clock()
			local dt   = now - lastTime
			lastTime   = now
			local step = direction * LASER_SPEED * dt
			local hit  = Workspace:Raycast(laser.Position, step, rayParams)

			if hit then
				laser.CFrame = CFrame.lookAt(hit.Position, hit.Position + direction)

				-- Fuoco amico: salta modelli della stessa fazione
				local hitModel = hit.Instance:FindFirstAncestorOfClass("Model")
				if hitModel and hitModel:GetAttribute("Faction") == CONFIG.Faction then
					-- Passthrough (non distruggiamo il laser qui, usciremo dal loop)
					laser:Destroy()
					return
				end

				-- Danno a nave (scudi -> scafo)
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
					-- Danno a player a piedi (Humanoid)
					local model = hit.Instance:FindFirstAncestorOfClass("Model")
					if model and model:GetAttribute("Faction") ~= CONFIG.Faction then
						local hum = model:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then
							hum:TakeDamage(CONFIG.Damage)
						end
					end
				end

				-- Flash d'impatto
				local exp = Instance.new("Explosion")
				exp.Position                  = hit.Position
				exp.BlastRadius               = 0
				exp.BlastPressure             = 0
				exp.DestroyJointRadiusPercent = 0
				exp.Visible                   = true
				exp.Parent                    = Workspace
				break
			end

			laser.CFrame = laser.CFrame + step
			task.wait()
		end

		if laser.Parent then laser:Destroy() end
	end)
end

-- ============================================================================
-- SHIPEV ENT HANDLER
-- ============================================================================
ShipEvent.OnServerEvent:Connect(function(player, action, data)
	print("[DBG] ShipEvent:", action, "da", player.Name)
	if typeof(data) ~= "table" then
		warn("[DBG] data non e' table:", typeof(data)); return
	end
	if vehicleSeat.Occupant == nil then
		warn("[DBG] Nessun Occupant, ignoro"); return
	end
	if vehicleSeat.Occupant.Parent ~= player.Character then
		warn("[DBG] Player non pilota questa nave"); return
	end

	if action == "Shoot" then
		local now = os.clock()
		if now - lastShot < CONFIG.ReloadSpeed then return end
		lastShot = now

		-- Direzione per-cannone: usa Converge (gimbal) se disponibile, poi Direction, poi muso.
		local function dirFrom(originPos)
			if typeof(data.Converge) == "Vector3" then
				local d = (data.Converge - originPos)
				if d.Magnitude > 0.01 then return d.Unit end
			end
			if typeof(data.Direction) == "Vector3" then
				return data.Direction.Unit
			end
			return -primary.CFrame.LookVector
		end

		if #cannons > 0 then
			local perShot = ship:GetAttribute("CannonsPerShot") or 0
			if perShot <= 0 or perShot >= #cannons then
				for _, c in ipairs(cannons) do
					spawnLaser(c.Position, dirFrom(c.Position))
				end
			else
				for _ = 1, perShot do
					cannonIndex = (cannonIndex % #cannons) + 1
					spawnLaser(cannons[cannonIndex].Position, dirFrom(cannons[cannonIndex].Position))
				end
			end
		else
			local fb = primary.Position + primary.CFrame.LookVector * 8
			spawnLaser(fb, dirFrom(fb))
		end
		if fireSound and fireSound.SoundId ~= "" then fireSound:Play() end

	elseif action == "ToggleSfoils" then
		-- State=true  -> Combat  (ali aperte, trails ON)
		-- State=false -> Hangar  (ali chiuse, trails OFF)
		local combat = (data.State == true)
		print("[DBG] ToggleSfoils: combat =", combat)
		updateWings(combat)
		setSfoilTrails(combat)
		if combat then
			playOneShot(hyperdriveSound)  -- suono "apertura ali"
		end

	elseif action == "EngineToggle" then
		print("[DBG] EngineToggle:", data.State)
		setEngine(data.State == true)

	elseif action == "DrivePhysics" then
		if typeof(data.CFrame) == "CFrame" then
			shipGyro.CFrame = data.CFrame
		end
		if typeof(data.Velocity) == "Vector3" then
			shipVelocity.Velocity = data.Velocity
		end
	end
end)
