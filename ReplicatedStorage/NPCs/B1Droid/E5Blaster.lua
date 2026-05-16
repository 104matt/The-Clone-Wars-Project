-- E5Blaster.lua  (Script - server)
-- Posizione: dentro il modello E5 del B1Droid (E5/E5Blaster)
--
-- Gestisce il fuoco del fucile E5:
--  - raycast + beam laser dal Barrel tramite il modulo LaserBolt
--  - MuzzleFlash + Light al colpo
--  - suono Fire dalla Handle
--
-- Espone un BindableEvent "Fire" dentro E5 che l'AI chiama:
--   E5.Fire:Fire(targetPosition)   -- targetPosition: Vector3 nel mondo

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local LaserBolt = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LaserBolt"))

-- ================= CONFIG =================
local FIRE_COOLDOWN     = 0.6         -- secondi tra un colpo e l'altro
local SPREAD_DEG        = 4           -- accuratezza droide (più alto = peggio mira)
local DAMAGE            = 12
local MUZZLE_FLASH_TIME = 0.06

-- ================= SETUP =================
local E5     = script.Parent
local Barrel = E5:WaitForChild("Barrel")
local Handle = E5:WaitForChild("Handle")

local MuzzleFlash = Barrel:FindFirstChild("MuzzleFlash")   -- ParticleEmitter
local MuzzleLight = Barrel:FindFirstChild("Light")         -- PointLight (opzionale)
local FireSound   = Handle:FindFirstChild("Fire")          -- Sound

-- BindableEvent che permette all'AI di chiedere il fuoco.
local fireEvent = E5:FindFirstChild("Fire")
if not fireEvent or not fireEvent:IsA("BindableEvent") then
	fireEvent = Instance.new("BindableEvent")
	fireEvent.Name   = "Fire"
	fireEvent.Parent = E5
end

local lastShot = 0

local function applySpread(direction)
	if SPREAD_DEG <= 0 then return direction end
	local maxRad = math.rad(SPREAD_DEG)
	local yaw   = (math.random() * 2 - 1) * maxRad
	local pitch = (math.random() * 2 - 1) * maxRad
	return (CFrame.new(Vector3.zero, direction) * CFrame.Angles(pitch, yaw, 0)).LookVector
end

local function playMuzzle()
	if MuzzleFlash and MuzzleFlash:IsA("ParticleEmitter") then
		MuzzleFlash:Emit(6)
	end
	if MuzzleLight and MuzzleLight:IsA("Light") then
		local saved = MuzzleLight.Brightness
		MuzzleLight.Enabled    = true
		MuzzleLight.Brightness = math.max(saved, 4)
		task.delay(MUZZLE_FLASH_TIME, function()
			if MuzzleLight then
				MuzzleLight.Brightness = saved
				MuzzleLight.Enabled    = false
			end
		end)
	end
	if FireSound and FireSound:IsA("Sound") then
		-- clona così colpi rapidi non si tagliano a vicenda
		local s = FireSound:Clone()
		s.Parent = Handle
		s:Play()
		Debris:AddItem(s, s.TimeLength > 0 and s.TimeLength + 0.1 or 2)
	end
end

local function fireAt(targetPosition)
	local now = os.clock()
	if now - lastShot < FIRE_COOLDOWN then return end
	lastShot = now

	local origin = Barrel.Position
	local dir    = (targetPosition - origin)
	if dir.Magnitude < 0.01 then return end
	dir = applySpread(dir.Unit)

	playMuzzle()

	local shooterModel = E5:FindFirstAncestorOfClass("Model")
	LaserBolt.Fire({
		origin    = origin,
		direction = dir,
		shooter   = shooterModel,
		damage    = DAMAGE,
	})
end

fireEvent.Event:Connect(fireAt)
