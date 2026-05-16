-- LaserBolt.lua  (ModuleScript)
-- Posizione: ReplicatedStorage/Modules/LaserBolt
-- Modulo riutilizzabile per beam laser stile Star Wars.
-- Uso: local LaserBolt = require(ReplicatedStorage.Modules.LaserBolt)
--      LaserBolt.Fire({ origin = barrel.Position, direction = dir, shooter = droideModel, color = Color3.fromRGB(255,40,40) })

local LaserBolt = {}

local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

-- ================= CONFIG =================
local BOLT_SPEED         = 600       -- studs/sec
local BOLT_LENGTH        = 5         -- studs (lunghezza visuale del raggio)
local BOLT_THICKNESS     = 0.18
local MAX_RANGE          = 500
local DEFAULT_DAMAGE     = 12
local CIS_COLOR          = Color3.fromRGB(255, 40, 40)   -- rosso droidi CIS
local IMPACT_LIFETIME    = 0.6

-- ============ HELPERS ====================
local function makeBolt(color)
	local p = Instance.new("Part")
	p.Name              = "LaserBolt"
	p.Size              = Vector3.new(BOLT_THICKNESS, BOLT_THICKNESS, BOLT_LENGTH)
	p.Material          = Enum.Material.Neon
	p.Color             = color
	p.CanCollide        = false
	p.CanQuery          = false
	p.CanTouch          = false
	p.Anchored          = true
	p.CastShadow        = false
	p.TopSurface        = Enum.SurfaceType.Smooth
	p.BottomSurface     = Enum.SurfaceType.Smooth

	local glow = Instance.new("PointLight")
	glow.Color          = color
	glow.Range          = 8
	glow.Brightness     = 2
	glow.Parent         = p

	return p
end

local function spawnImpact(position, normal, color)
	-- Particle burst + suono + flash alla collisione.
	local attach = Instance.new("Part")
	attach.Name         = "LaserImpact"
	attach.Size         = Vector3.new(0.1, 0.1, 0.1)
	attach.Transparency = 1
	attach.Anchored     = true
	attach.CanCollide   = false
	attach.CanQuery     = false
	attach.CanTouch     = false
	attach.CFrame       = CFrame.lookAt(position, position + normal)
	attach.Parent       = Workspace

	local light = Instance.new("PointLight")
	light.Color         = color
	light.Range         = 10
	light.Brightness    = 3
	light.Parent        = attach

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture     = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color       = ColorSequence.new(color)
	emitter.Size        = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime    = NumberRange.new(0.15, 0.35)
	emitter.Speed       = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate        = 0
	emitter.LightEmission = 1
	emitter.Parent      = attach
	emitter:Emit(18)

	-- breve flash della luce
	TweenService:Create(light, TweenInfo.new(IMPACT_LIFETIME), { Brightness = 0, Range = 0 }):Play()

	Debris:AddItem(attach, IMPACT_LIFETIME)
end

local function applyDamage(hitInstance, damage, shooter)
	if not hitInstance then return end
	local model = hitInstance:FindFirstAncestorOfClass("Model")
	if not model or model == shooter then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(damage)
	end
end

-- ============ API =========================
-- opts: {
--   origin       = Vector3   (obbligatorio)
--   direction    = Vector3   (direzione, sarà normalizzata)
--   shooter      = Model     (modello da ignorare nel raycast, es. il droide)
--   color        = Color3?   (default rosso CIS)
--   damage       = number?   (default 12)
--   ignore       = {Instance}? lista di Instance da ignorare oltre allo shooter
--   onHit        = function(raycastResult)? callback opzionale
-- }
function LaserBolt.Fire(opts)
	assert(opts and opts.origin and opts.direction, "LaserBolt.Fire: origin e direction obbligatori")

	local color     = opts.color or CIS_COLOR
	local damage    = opts.damage or DEFAULT_DAMAGE
	local direction = opts.direction.Unit

	-- Raycast per trovare il punto di impatto.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { opts.shooter }
	if opts.ignore then
		for _, v in ipairs(opts.ignore) do table.insert(ignore, v) end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local result = Workspace:Raycast(opts.origin, direction * MAX_RANGE, params)

	local endPos      = result and result.Position or (opts.origin + direction * MAX_RANGE)
	local totalDist   = (endPos - opts.origin).Magnitude
	local travelTime  = math.max(totalDist / BOLT_SPEED, 0.02)

	-- Crea il bolt e fallo viaggiare.
	local bolt = makeBolt(color)
	bolt.CFrame = CFrame.lookAt(opts.origin, endPos)
	bolt.Parent = Workspace

	local tween = TweenService:Create(
		bolt,
		TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(endPos, endPos + direction) }
	)
	tween:Play()

	task.spawn(function()
		tween.Completed:Wait()
		if result then
			spawnImpact(result.Position, result.Normal, color)
			applyDamage(result.Instance, damage, opts.shooter)
			if opts.onHit then
				opts.onHit(result)
			end
		end
		bolt:Destroy()
	end)

	return result
end

return LaserBolt
