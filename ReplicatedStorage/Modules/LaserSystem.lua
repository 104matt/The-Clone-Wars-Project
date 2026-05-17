-- LaserSystem.lua  (ModuleScript)
-- Posizione: ReplicatedStorage/Modules/LaserSystem
--
-- Sistema laser condiviso che usa template Part custom:
--   ReplicatedStorage.Modules.LaserBolt    -> Part viaggiante del laser
--   ReplicatedStorage.Modules.LaserImpact  -> Part dell'impatto (particle/light/sound)
--
-- Tutte le Part vengono parentate a Workspace.LaserBeams per tenere pulito Workspace.
--
-- Uso: local LaserSystem = require(ReplicatedStorage.Modules.LaserSystem)
--      LaserSystem.Fire({ origin = barrel.Position, direction = dir, shooter = droidModel })

local LaserSystem = {}

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

-- ================= CONFIG =================
local BOLT_SPEED         = 600       -- studs/sec
local MAX_RANGE          = 500
local DEFAULT_DAMAGE     = 12
local IMPACT_LIFETIME    = 0.6
local BEAMS_FOLDER_NAME  = "LaserBeams"

-- ============ TEMPLATES ==================
local modulesFolder  = ReplicatedStorage:WaitForChild("Modules")
local boltTemplate   = modulesFolder:WaitForChild("LaserBolt")
local impactTemplate = modulesFolder:WaitForChild("LaserImpact")

assert(boltTemplate:IsA("BasePart"),   "ReplicatedStorage.Modules.LaserBolt deve essere un BasePart.")
assert(impactTemplate:IsA("BasePart"), "ReplicatedStorage.Modules.LaserImpact deve essere un BasePart.")

-- ============ HELPERS ====================
local function getBeamsFolder()
	local folder = Workspace:FindFirstChild(BEAMS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name   = BEAMS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function spawnImpact(position, normal)
	local impact = impactTemplate:Clone()
	impact.Anchored   = true
	impact.CanCollide = false
	impact.CanQuery   = false
	impact.CanTouch   = false
	impact.CFrame     = CFrame.lookAt(position, position + normal)
	impact.Parent     = getBeamsFolder()

	for _, child in ipairs(impact:GetDescendants()) do
		if child:IsA("ParticleEmitter") then
			child:Emit(child:GetAttribute("EmitCount") or 18)
		elseif child:IsA("Sound") then
			child:Play()
		end
	end

	Debris:AddItem(impact, IMPACT_LIFETIME)
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
--   origin    = Vector3   (obbligatorio)
--   direction = Vector3   (obbligatorio, normalizzata internamente)
--   shooter   = Model?    (ignorato dal raycast)
--   damage    = number?   (default 12)
--   ignore    = {Instance}? lista extra di Instance da ignorare
--   onHit     = function(raycastResult)?
-- }
function LaserSystem.Fire(opts)
	assert(opts and opts.origin and opts.direction, "LaserSystem.Fire: origin e direction obbligatori")

	local damage    = opts.damage or DEFAULT_DAMAGE
	local direction = opts.direction.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { opts.shooter, getBeamsFolder() }
	if opts.ignore then
		for _, v in ipairs(opts.ignore) do table.insert(ignore, v) end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local result = Workspace:Raycast(opts.origin, direction * MAX_RANGE, params)

	local endPos     = result and result.Position or (opts.origin + direction * MAX_RANGE)
	local totalDist  = (endPos - opts.origin).Magnitude
	local travelTime = math.max(totalDist / BOLT_SPEED, 0.02)

	local bolt = boltTemplate:Clone()
	bolt.Anchored   = true
	bolt.CanCollide = false
	bolt.CanQuery   = false
	bolt.CanTouch   = false
	bolt.CFrame     = CFrame.lookAt(opts.origin, endPos)
	bolt.Parent     = getBeamsFolder()

	local tween = TweenService:Create(
		bolt,
		TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(endPos, endPos + direction) }
	)
	tween:Play()

	task.spawn(function()
		tween.Completed:Wait()
		if result then
			spawnImpact(result.Position, result.Normal)
			applyDamage(result.Instance, damage, opts.shooter)
			if opts.onHit then opts.onHit(result) end
		end
		bolt:Destroy()
	end)

	return result
end

return LaserSystem
