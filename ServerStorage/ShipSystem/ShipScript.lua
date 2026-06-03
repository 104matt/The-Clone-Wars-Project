-- ShipScript.lua  (Script per-nave)  -- DEBUG BUILD --
-- Ogni step critico stampa nell'Output. Cerca le righe [DBG] per capire dove si blocca.

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
print("[DBG] FlightEvents trovato:", FlightEvents:GetFullName())

local ShipEvent = FlightEvents:WaitForChild("ShipEvent")
print("[DBG] ShipEvent trovato:", ShipEvent:GetFullName())

local laserTemplate = FlightEvents:WaitForChild("LaserBolt", 5)
if laserTemplate then
	print("[DBG] LaserBolt trovato:", laserTemplate:GetFullName())
else
	warn("[DBG] LaserBolt NON trovato in FlightEvents (sparo senza proiettile visivo)")
end

local fireSound -- forward declaration

-- ============================================================================
-- CONFIG
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
	Faction     = attr("Faction", "Republic"),
}
print(("[DBG] CONFIG: Damage=%s MaxSpeed=%s ReloadSpeed=%s Faction=%s FireSound=%s"):format(
	tostring(CONFIG.Damage), tostring(CONFIG.MaxSpeed), tostring(CONFIG.ReloadSpeed),
	tostring(CONFIG.Faction), tostring(CONFIG.FireSound)
))

ship:GetAttributeChangedSignal("Damage"):Connect(function()      CONFIG.Damage      = attr("Damage", 30)        end)
ship:GetAttributeChangedSignal("MaxSpeed"):Connect(function()    CONFIG.MaxSpeed    = attr("MaxSpeed", 150)     end)
ship:GetAttributeChangedSignal("ReloadSpeed"):Connect(function() CONFIG.ReloadSpeed = attr("ReloadSpeed", 0.18) end)
ship:GetAttributeChangedSignal("CanHover"):Connect(function()    CONFIG.CanHover    = attr("CanHover", false)   end)
ship:GetAttributeChangedSignal("Faction"):Connect(function()     CONFIG.Faction     = attr("Faction", "Republic") end)
ship:GetAttributeChangedSignal("FireSound"):Connect(function()
	CONFIG.FireSound = attr("FireSound", "")
	if fireSound then fireSound.SoundId = CONFIG.FireSound end
end)

-- ============================================================================
-- RESOLVE PARTS
-- ============================================================================
print("[DBG] Cerco VehicleSeat...")
local vehicleSeat = ship:FindFirstChildWhichIsA("VehicleSeat", true)
if not vehicleSeat then
	error("[DBG] ERRORE FATALE: VehicleSeat non trovato in " .. ship:GetFullName())
end
print("[DBG] VehicleSeat trovato:", vehicleSeat:GetFullName())

local cameraPart = ship:FindFirstChild("CameraPart", true)
local zoomPart   = ship:FindFirstChild("ZoomPart",   true)
local laser1     = ship:FindFirstChild("Laser1",     true)
local laser2     = ship:FindFirstChild("Laser2",     true)
local leftWing   = ship:FindFirstChild("LeftWing",      true)
local rightWing  = ship:FindFirstChild("RightWing",     true)
local openLeft   = ship:FindFirstChild("OpenLeftWing",  true)
local openRight  = ship:FindFirstChild("OpenRightWing", true)

print(("[DBG] Parts trovati: CameraPart=%s ZoomPart=%s Laser1=%s Laser2=%s"):format(
	tostring(cameraPart ~= nil), tostring(zoomPart ~= nil),
	tostring(laser1 ~= nil),     tostring(laser2 ~= nil)
))
print(("[DBG] Wings: LeftWing=%s RightWing=%s OpenLeftWing=%s OpenRightWing=%s"):format(
	tostring(leftWing ~= nil), tostring(rightWing ~= nil),
	tostring(openLeft ~= nil), tostring(openRight ~= nil)
))

if not ship.PrimaryPart then
	print("[DBG] PrimaryPart non impostato, provo VehicleSeat o primo BasePart...")
	ship.PrimaryPart = (vehicleSeat:IsA("BasePart") and vehicleSeat)
		or ship:FindFirstChildWhichIsA("BasePart")
end
local primary = ship.PrimaryPart
if not primary then
	error("[DBG] ERRORE FATALE: PrimaryPart impossibile da determinare in " .. ship:GetFullName())
end
print("[DBG] PrimaryPart:", primary:GetFullName(), "| Classe:", primary.ClassName)

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
print(("[DBG] Weld completato: %d vincoli creati. primary.Anchored = %s"):format(
	weldCount, tostring(primary.Anchored)
))
primary.Anchored = true

-- ============================================================================
-- VEHICLE SEAT TUNING
-- ============================================================================
vehicleSeat.MaxSpeed       = CONFIG.MaxSpeed
vehicleSeat.TurnSpeed      = 0.4
vehicleSeat.Torque         = 10
vehicleSeat.HeadsUpDisplay = false
vehicleSeat.Disabled       = true
print("[DBG] VehicleSeat configurato. Disabled =", vehicleSeat.Disabled)

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
print("[DBG] BodyGyro e BodyVelocity creati in:", primary:GetFullName())

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
print("[DBG] Wingtip trails trovati:", #wingtipTrails)

local function setWingtipTrails(on)
	for _, t in ipairs(wingtipTrails) do t.Enabled = on end
end

local function updateWings(open)
	setGroupTransparency(leftWing,  open and 1 or 0)
	setGroupTransparency(rightWing, open and 1 or 0)
	setGroupTransparency(openLeft,  open and 0 or 1)
	setGroupTransparency(openRight, open and 0 or 1)
	setWingtipTrails(open)
end
updateWings(false)

-- ============================================================================
-- ENGINE TRAIL
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
	trail.Attachment0    = at0
	trail.Attachment1    = at1
	trail.Color          = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(170, 235, 255)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80,  160, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(30,   60, 180)),
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
		print("[DBG] Engine trail costruito per:", d:GetFullName())
	end
end
print("[DBG] Engine trails totali:", #engineTrails)

-- ============================================================================
-- ENGINE STATE
-- ============================================================================
local engineOn = false
local function setEngine(on)
	print("[DBG] setEngine chiamato:", on, "| engineOn era:", engineOn)
	if engineOn == on then return end
	engineOn = on
	if on then
		primary.Anchored      = false
		shipGyro.CFrame       = primary.CFrame
		shipGyro.MaxTorque    = Vector3.new(math.huge, math.huge, math.huge)
		shipVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		shipVelocity.Velocity = Vector3.zero
		for _, t in ipairs(engineTrails) do t.Enabled = true end
		print("[DBG] Motore ACCESO. primary.Anchored =", primary.Anchored)
	else
		shipVelocity.Velocity = Vector3.zero
		shipVelocity.MaxForce = Vector3.new(0, 0, 0)
		shipGyro.MaxTorque    = Vector3.new(0, 0, 0)
		primary.Anchored      = true
		for _, t in ipairs(engineTrails) do t.Enabled = false end
		print("[DBG] Motore SPENTO. primary.Anchored =", primary.Anchored)
	end
end

-- ============================================================================
-- FIRE SOUND
-- ============================================================================
do
	local s = primary:FindFirstChild("FireSound")
	if not s or not s:IsA("Sound") then
		if s then s:Destroy() end
		s        = Instance.new("Sound")
		s.Name   = "FireSound"
		s.Volume = 1
		s.Parent = primary
	end
	s.SoundId = CONFIG.FireSound
	fireSound = s
	print("[DBG] FireSound configurato. SoundId =", tostring(s.SoundId))
end

-- ============================================================================
-- ENTRY: ProximityPrompt
-- ============================================================================
local prompt = vehicleSeat:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	prompt        = Instance.new("ProximityPrompt")
	prompt.Parent = vehicleSeat
	print("[DBG] ProximityPrompt creato nel VehicleSeat")
else
	print("[DBG] ProximityPrompt esistente trovato:", prompt:GetFullName())
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
	print("[DBG] ProximityPrompt triggerato da:", player.Name,
		"| Occupant attuale:", tostring(vehicleSeat.Occupant))
	if vehicleSeat.Occupant then return end
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		warn("[DBG] Humanoid non trovato per", player.Name)
		return
	end
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
	print("[DBG] onEnter: occupant =", tostring(occupant), "| player =", tostring(player))
	if player then
		local ok, err = pcall(function() primary:SetNetworkOwner(player) end)
		print("[DBG] SetNetworkOwner ->", ok, err)
	end
	setEngine(false)
	prompt.Enabled = false
	print("[DBG] Ingresso completato. prompt.Enabled = false")
end

local function onExit()
	print("[DBG] onExit chiamato")
	setEngine(false)
	pcall(function() primary:SetNetworkOwner(nil) end)
	updateWings(false)
	prompt.Enabled = true
	print("[DBG] Uscita completata. prompt.Enabled = true")
end

vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = vehicleSeat.Occupant
	print("[DBG] Occupant cambiato:", tostring(occupant), "| entryArmed:", entryArmed)
	if occupant and not entryArmed then
		warn("[DBG] Qualcuno si e' seduto senza prompt! Lo espello.")
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

print("[DBG] ShipScript inizializzazione COMPLETATA per:", ship.Name)
print("[DBG] =====================================================")

-- ============================================================================
-- SHOOTING
-- ============================================================================
local LASER_SPEED    = 750
local LASER_LIFETIME = 5
local lastShot       = 0

local function spawnLaser(originPos, direction)
	if not laserTemplate or not laserTemplate:IsA("BasePart") then
		laserTemplate = FlightEvents:FindFirstChild("LaserBolt")
	end
	if not laserTemplate or not laserTemplate:IsA("BasePart") then
		warn("[DBG] FlightEvents.LaserBolt mancante.")
		return
	end
	local laser = laserTemplate:Clone()
	laser.Name       = "ShipLaser"
	laser.Anchored   = false
	laser.CanCollide = false
	laser.CanQuery   = false
	laser.CanTouch   = true
	laser.Massless   = true
	laser.CFrame     = CFrame.lookAt(originPos, originPos + direction)

	local att = laser:FindFirstChild("Tail")
	if not att or not att:IsA("Attachment") then
		att = laser:FindFirstChildOfClass("Attachment")
	end
	if not att then
		att        = Instance.new("Attachment")
		att.Name   = "VelocityAttachment"
		att.Parent = laser
	end
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0    = att
	lv.MaxForce       = math.huge
	lv.RelativeTo     = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = direction * LASER_SPEED
	lv.Parent         = laser
	laser.Parent      = Workspace

	local conn
	conn = laser.Touched:Connect(function(other)
		if other:IsDescendantOf(ship) then return end
		local model = other:FindFirstAncestorOfClass("Model")
		if not model then return end
		if model:GetAttribute("Faction") == CONFIG.Faction then return end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum:TakeDamage(CONFIG.Damage)
		end
		if conn then conn:Disconnect() end
		laser:Destroy()
	end)
	Debris:AddItem(laser, LASER_LIFETIME)
end

ShipEvent.OnServerEvent:Connect(function(player, action, data)
	print("[DBG] ShipEvent ricevuto: action =", action, "| player =", player.Name)
	if typeof(data) ~= "table" then
		warn("[DBG] data non e' una table:", typeof(data))
		return
	end
	if vehicleSeat.Occupant == nil then
		warn("[DBG] Nessun Occupant, ignoro evento")
		return
	end
	local pilotChar = vehicleSeat.Occupant.Parent
	if pilotChar ~= player.Character then
		warn("[DBG] Il player non sta pilotando questa nave")
		return
	end

	if action == "Shoot" then
		local now = os.clock()
		if now - lastShot < CONFIG.ReloadSpeed then return end
		lastShot = now

		local function dirFrom(originPos)
			if typeof(data.Converge) == "Vector3" then
				return (data.Converge - originPos).Unit
			elseif typeof(data.Direction) == "Vector3" then
				return data.Direction.Unit
			end
			return -primary.CFrame.LookVector
		end

		local fired = false
		if laser1 then spawnLaser(laser1.Position, dirFrom(laser1.Position)); fired = true end
		if laser2 then spawnLaser(laser2.Position, dirFrom(laser2.Position)); fired = true end
		if not fired then
			local fallback = primary.Position + primary.CFrame.LookVector * 8
			spawnLaser(fallback, dirFrom(fallback))
		end
		if fireSound and fireSound.SoundId ~= "" then
			fireSound:Play()
		end

	elseif action == "ToggleSfoils" then
		print("[DBG] ToggleSfoils:", data.State)
		updateWings(data.State == true)

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
