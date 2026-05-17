-- LaserSystem.lua  (ModuleScript)
-- Posizione: ReplicatedStorage/DroidSystemRep/Modules/LaserSystem
--
-- Sistema laser condiviso che usa template Part custom:
--   ReplicatedStorage.DroidSystemRep.Modules.LaserBolt    -> Part viaggiante del laser
--   ReplicatedStorage.DroidSystemRep.Modules.LaserImpact  -> Part dell'impatto
--
-- Tutte le Part runtime vengono parentate a Workspace.DroidSystemWorkspace.LaserBeams.
--
-- Uso: local LaserSystem = require(ReplicatedStorage.DroidSystemRep.Modules.LaserSystem)
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
local WORKSPACE_ROOT_NAME = "DroidSystemWorkspace"
local BEAMS_FOLDER_NAME   = "LaserBeams"

-- ============ TEMPLATES ==================
local droidSystemRep = ReplicatedStorage:WaitForChild("DroidSystemRep")
local modulesFolder  = droidSystemRep:WaitForChild("Modules")
local boltTemplate   = modulesFolder:WaitForChild("LaserBolt")
local impactTemplate = modulesFolder:WaitForChild("LaserImpact")

assert(boltTemplate:IsA("BasePart"),   "DroidSystemRep.Modules.LaserBolt deve essere un BasePart.")
assert(impactTemplate:IsA("BasePart"), "DroidSystemRep.Modules.LaserImpact deve essere un BasePart.")

-- ============ HELPERS ====================
local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name   = name
		f.Parent = parent
	end
	return f
end

local function getBeamsFolder()
	local root = ensureFolder(Workspace, WORKSPACE_ROOT_NAME)
	return ensureFolder(root, BEAMS_FOLDER_NAME)
end

local function spawnImpact(position, normal)
	local impact = impactTemplate:Clone()
	impact.Anchored   = true
	impact.CanCollide = false
	impact.CanQuery   = false
	impact.CanTouch   = false

	-- Orientiamo la Part in modo che la sua faccia Top (+Y) punti lungo la normale
	-- della superficie colpita. I ParticleEmitter usano EmissionDirection=Top di
	-- default, quindi le particelle escono perpendicolari al muro/pavimento/soffitto.
	local n = normal.Magnitude > 0 and normal.Unit or Vector3.yAxis
	local arbitrary = math.abs(n:Dot(Vector3.yAxis)) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local right = arbitrary:Cross(n).Unit
	local forward = n:Cross(right)
	impact.CFrame = CFrame.fromMatrix(position, right, n, -forward)
	impact.Parent = getBeamsFolder()

	for _, child in ipairs(impact:GetDescendants()) do
		if child:IsA("ParticleEmitter") then
			child:Emit(child:GetAttribute("EmitCount") or 18)
		elseif child:IsA("Sound") then
			child:Play()
		end
	end

	Debris:AddItem(impact, IMPACT_LIFETIME)
end

local function getFaction(model)
	if not model then return nil end
	return model:GetAttribute("Faction")
end

local function applyDamage(hitInstance, damage, shooter, shooterFaction)
	if not hitInstance then return end
	local model = hitInstance:FindFirstAncestorOfClass("Model")
	if not model or model == shooter then return end
	-- friendly fire: salta se stessa fazione
	if shooterFaction and getFaction(model) == shooterFaction then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(damage)
	end
end

-- ============ API =========================
-- opts: {
--   origin         = Vector3   (obbligatorio)
--   direction      = Vector3   (obbligatorio, normalizzata internamente)
--   shooter        = Model?    (ignorato dal raycast)
--   shooterFaction = string?   (es. "CIS"; il raycast passa attraverso modelli con
--                               attributo "Faction" uguale, evitando fuoco amico)
--   damage         = number?   (default 12)
--   ignore         = {Instance}? lista extra di Instance da ignorare
--   onHit          = function(raycastResult)?
-- }
function LaserSystem.Fire(opts)
	assert(opts and opts.origin and opts.direction, "LaserSystem.Fire: origin e direction obbligatori")

	local damage         = opts.damage or DEFAULT_DAMAGE
	local direction      = opts.direction.Unit
	local shooterFaction = opts.shooterFaction

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { opts.shooter, getBeamsFolder() }
	if opts.ignore then
		for _, v in ipairs(opts.ignore) do table.insert(ignore, v) end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	-- Raycast con "pass-through" sui compagni di fazione: se colpiamo un alleato,
	-- lo aggiungiamo al filtro e tiriamo di nuovo dal punto d'impatto.
	local function castFrom(pos, remainingRange)
		local r = Workspace:Raycast(pos, direction * remainingRange, params)
		while r and shooterFaction do
			local m = r.Instance and r.Instance:FindFirstAncestorOfClass("Model")
			if m and getFaction(m) == shooterFaction and m ~= opts.shooter then
				table.insert(ignore, m)
				params.FilterDescendantsInstances = ignore
				local consumed = (r.Position - pos).Magnitude
				pos = r.Position + direction * 0.05
				remainingRange = remainingRange - consumed - 0.05
				if remainingRange <= 0 then return nil end
				r = Workspace:Raycast(pos, direction * remainingRange, params)
			else
				break
			end
		end
		return r
	end
	local result = castFrom(opts.origin, MAX_RANGE)

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
			applyDamage(result.Instance, damage, opts.shooter, shooterFaction)
			if opts.onHit then opts.onHit(result) end
		end
		bolt:Destroy()
	end)

	return result
end

return LaserSystem
