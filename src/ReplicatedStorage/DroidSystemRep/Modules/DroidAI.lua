-- DroidAI.lua  (ModuleScript)
-- All droid AI logic. Stateless functions operate on a per-droid state table.
-- Instantiate with DroidAI.new(model), then loadPath(), then startAI().
-- updateFacing(dt) is called every frame by DroidManager's single Heartbeat.

local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Debris             = game:GetService("Debris")
local Workspace          = game:GetService("Workspace")

local LaserSystem  = require(script.Parent:WaitForChild("LaserSystem"))
local DroidConfigs = require(script.Parent:WaitForChild("DroidConfigs"))

local DroidAI = {}
DroidAI.__index = DroidAI

local function distXZ(a, b)
	local d = a - b
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

local function readValue(model, name, className, default)
	local v = model:FindFirstChild(name)
	if v and v:IsA(className) then return v.Value end
	return default
end

local function findHumanoid(model)
	local h = model:FindFirstChildOfClass("Humanoid")
	if h then return h end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") then return d end
	end
end

-- ===== CONSTRUCTOR =====

function DroidAI.new(model)
	local droidTypeVal = model:FindFirstChild("droidType")
	local droidType    = droidTypeVal and droidTypeVal.Value or "B1Droid"
	local config       = DroidConfigs[droidType]
	if not config then
		warn("DroidAI: unknown droidType '" .. droidType .. "', falling back to B1Droid")
		config = DroidConfigs.B1Droid
	end

	local self = setmetatable({}, DroidAI)
	self.model  = model
	self.config = config
	self.dead   = false

	self.facingGoal        = nil
	self.currentLocomotion = nil
	self.currentTargetHrp  = nil
	self.lastShot          = 0
	self.lastKnown         = nil
	self.searchEndsAt      = nil
	self.pathParts         = nil

	self.droidName      = readValue(model, "droidName",      "StringValue", "")
	self.isHostile      = readValue(model, "isHostile",      "BoolValue",   false)
	self.loopPath       = readValue(model, "loopPath",       "BoolValue",   false)
	self.formationIndex = readValue(model, "formationIndex", "IntValue",    0)

	self.humanoid = findHumanoid(model) or error("DroidAI: Humanoid not found in " .. model.Name)
	self.rootPart = self.humanoid.RootPart
		or model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
	if not self.rootPart then error("DroidAI: HumanoidRootPart not found in " .. model.Name) end

	self.humanoid.WalkSpeed  = config.WALK_SPEED
	self.humanoid.MaxHealth  = config.MAX_HEALTH
	self.humanoid.Health     = config.MAX_HEALTH
	self.humanoid.AutoRotate = false
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	self.humanoid.JumpPower  = config.JUMP_POWER
	pcall(function() self.humanoid.UseJumpPower = true end)

	if model:GetAttribute("Faction") == nil then
		model:SetAttribute("Faction", config.FACTION)
	end

	local blaster = model:FindFirstChild("Blaster", true)
	self.barrel     = nil
	self.handle     = nil
	self.muzzleFlash = nil
	self.muzzleLight = nil
	self.fireSound   = nil
	if blaster then
		self.barrel = blaster:FindFirstChild("Barrel", true)
		self.handle = blaster:FindFirstChild("Handle", true)
		if self.barrel then
			self.muzzleFlash = self.barrel:FindFirstChild("MuzzleFlash")
			self.muzzleLight = self.barrel:FindFirstChild("Light")
		end
		if self.handle then
			self.fireSound = self.handle:FindFirstChild("Fire")
		end
	elseif self.isHostile then
		warn("DroidAI: hostile droid without Blaster —", model.Name)
	end

	local animator = self.humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = self.humanoid

	local function loadAnim(id)
		if not id or id == 0 then return nil end
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. id
		-- Must be in DataModel before server-side LoadAnimation or it fails intermittently
		a.Parent = animator
		local ok, track = pcall(function() return animator:LoadAnimation(a) end)
		return ok and track or nil
	end

	self.tracks = {
		Idle      = loadAnim(config.ANIM_IDS.Idle),
		Walk      = loadAnim(config.ANIM_IDS.Walk),
		Shoot     = loadAnim(config.ANIM_IDS.Shoot),
		Death     = loadAnim(config.ANIM_IDS.Death),
		DeathIdle = loadAnim(config.ANIM_IDS.DeathIdle),
	}
	if self.tracks.Idle      then self.tracks.Idle.Priority      = Enum.AnimationPriority.Idle     end
	if self.tracks.Walk      then self.tracks.Walk.Priority      = Enum.AnimationPriority.Movement end
	if self.tracks.Shoot     then self.tracks.Shoot.Priority     = Enum.AnimationPriority.Action   end
	if self.tracks.Death     then self.tracks.Death.Priority     = Enum.AnimationPriority.Action4  end
	if self.tracks.DeathIdle then self.tracks.DeathIdle.Priority = Enum.AnimationPriority.Action4  end
	if self.tracks.DeathIdle then self.tracks.DeathIdle.Looped   = true                             end

	local ws = model:FindFirstChild("WalkingSound", true)
	self.walkingSound = (ws and ws:IsA("Sound")) and ws or nil
	if self.walkingSound then self.walkingSound.Looped = true end

	self.cosFireAngle       = math.cos(math.rad(config.FIRE_ANGLE_DEG))
	self.facingOffsetCF     = CFrame.Angles(0, math.rad(config.FACING_OFFSET_DEG), 0)
	self.FACING_DEADZONE_RAD = math.rad(8)

	self.humanoid.Died:Connect(function() self:onDeath() end)

	return self
end

-- ===== PATH LOAD (yields — called inside task.spawn by manager) =====

function DroidAI:loadPath()
	if self.droidName == "" then return end
	local dsw = Workspace:WaitForChild("DroidSystemWorkspace", 10)
	if not dsw then return end
	local pathsRoot = dsw:WaitForChild("DroidPaths", 5)
	if not pathsRoot then return end
	local pathFolder = pathsRoot:WaitForChild(self.droidName, 5)
	if not pathFolder then return end

	local list = {}
	for _, child in ipairs(pathFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local n = tonumber(child.Name)
			if n then table.insert(list, { idx = n, part = child }) end
		end
	end
	table.sort(list, function(a, b) return a.idx < b.idx end)
	if #list > 0 then
		self.pathParts = {}
		for i, entry in ipairs(list) do self.pathParts[i] = entry.part end
	end
end

-- ===== FACING (called by manager Heartbeat — not per-droid) =====

function DroidAI:updateFacing(dt)
	if self.dead or not self.facingGoal then return end
	local rp = self.rootPart
	local lookVec = self.facingGoal - rp.Position
	lookVec = Vector3.new(lookVec.X, 0, lookVec.Z)
	if lookVec.Magnitude < 0.05 then return end
	lookVec = lookVec.Unit

	local f = (rp.CFrame * self.facingOffsetCF).LookVector
	f = Vector3.new(f.X, 0, f.Z)
	if f.Magnitude < 0.01 then return end
	f = f.Unit

	local dot   = math.clamp(f:Dot(lookVec), -1, 1)
	local angle = math.acos(dot)
	if angle < self.FACING_DEADZONE_RAD then return end

	local step = math.min(self.config.TURN_SPEED * dt, angle)
	local sign = (f.X * lookVec.Z - f.Z * lookVec.X) < 0 and 1 or -1
	local linVel = rp.AssemblyLinearVelocity
	rp.CFrame = rp.CFrame * CFrame.Angles(0, sign * step, 0)
	rp.AssemblyLinearVelocity = linVel
end

-- ===== FORMATION =====

-- ===== FORMATION =====
function DroidAI:formationPos(targetPos, prevPos)
	-- Se non c'è un offset o se è la posizione zero, va al bersaglio
	if not self.formationOffset then return targetPos end

	-- Se non abbiamo un prevPos (siamo all'inizio del path), consideriamo 
	-- come posizione di partenza quella in cui ci troviamo ora.
	local from = prevPos or self.rootPart.Position

	-- Calcoliamo la direzione dal punto di partenza al punto d'arrivo
	local dir = targetPos - from
	dir = Vector3.new(dir.X, 0, dir.Z) -- Ignoriamo l'altezza (Y) per calcolare la direzione orizzontale

	-- Se siamo già troppo vicini al target, non applichiamo l'offset
	-- per evitare che i droidi 'tremino' attorno alla posizione finale
	if dir.Magnitude < 0.5 then 
		return targetPos
	end

	-- Normalizziamo la direzione per avere un vettore di lunghezza 1
	dir = dir.Unit

	-- Calcoliamo il vettore che punta a destra rispetto alla direzione di marcia.
	-- Questo serve per distribuire i droidi lungo le colonne (asse X)
	local right = Vector3.new(dir.Z, 0, -dir.X)

	-- Applichiamo l'offset alla posizione finale (targetPos).
	-- formationOffset.X determina la posizione destra/sinistra (colonne)
	-- formationOffset.Z determina la posizione avanti/indietro (righe)
	-- Moltiplichiamo il vettore 'right' per l'offset orizzontale (X)
	-- Moltiplichiamo la direzione opposta ('-dir') per l'offset verticale (Z) per mandarli indietro
	local finalPos = targetPos + (right * self.formationOffset.X) - (dir * self.formationOffset.Z)

	return finalPos
end

-- ===== LOCOMOTION =====

function DroidAI:playLocomotion(name)
	if self.currentLocomotion == name then return end
	self.currentLocomotion = name
	for key, track in pairs(self.tracks) do
		if (key == "Idle" or key == "Walk") and track then
			if key == name then
				if not track.IsPlaying then track:Play(0.2) end
			else
				if track.IsPlaying then track:Stop(0.2) end
			end
		end
	end
	if self.walkingSound then
		if name == "Walk" then
			if not self.walkingSound.IsPlaying then self.walkingSound:Play() end
		else
			if self.walkingSound.IsPlaying then self.walkingSound:Stop() end
		end
	end
end

-- ===== TARGETING =====

function DroidAI:findTarget()
	local best, bestDist, bestHrp
	local origin = self.rootPart.Position
	local cfg    = self.config
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == cfg.TARGET_TEAM then
			local char = plr.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid")
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and hrp then
					local d = (hrp.Position - origin).Magnitude
					if d <= cfg.VISION_RANGE and (not best or d < bestDist) then
						best, bestDist, bestHrp = plr, d, hrp
					end
				end
			end
		end
	end
	return best, bestHrp, bestDist
end

function DroidAI:angleAlignedTo(targetPos)
	local toTarget = targetPos - self.rootPart.Position
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if toTarget.Magnitude < 0.01 then return true end
	local f = (self.rootPart.CFrame * self.facingOffsetCF).LookVector
	f = Vector3.new(f.X, 0, f.Z)
	if f.Magnitude < 0.01 then return false end
	return f.Unit:Dot(toTarget.Unit) >= self.cosFireAngle
end

-- ===== COMBAT =====

function DroidAI:tryFireAt(targetPosition)
	if not self.barrel then return end
	local now = os.clock()
	if now - self.lastShot < self.config.FIRE_COOLDOWN then return end
	self.lastShot = now

	local origin = self.barrel.Position
	local dir    = targetPosition - origin
	if dir.Magnitude < 0.01 then return end

	local cfg    = self.config
	if cfg.SPREAD_DEG > 0 then
		local maxRad = math.rad(cfg.SPREAD_DEG)
		dir = (CFrame.new(Vector3.zero, dir.Unit)
			* CFrame.Angles((math.random()*2-1)*maxRad, (math.random()*2-1)*maxRad, 0)).LookVector
	else
		dir = dir.Unit
	end

	if self.muzzleFlash and self.muzzleFlash:IsA("ParticleEmitter") then
		self.muzzleFlash:Emit(6)
	end
	if self.muzzleLight and self.muzzleLight:IsA("Light") then
		local saved = self.muzzleLight.Brightness
		self.muzzleLight.Enabled    = true
		self.muzzleLight.Brightness = math.max(saved, 4)
		task.delay(cfg.MUZZLE_FLASH_TIME, function()
			if self.muzzleLight then
				self.muzzleLight.Brightness = saved
				self.muzzleLight.Enabled    = false
			end
		end)
	end
	if self.fireSound and self.fireSound:IsA("Sound") then
		local s = self.fireSound:Clone()
		s.Parent = self.handle
		s:Play()
		Debris:AddItem(s, s.TimeLength > 0 and s.TimeLength + 0.1 or 2)
	end
	if self.tracks.Shoot and not self.tracks.Shoot.IsPlaying then
		self.tracks.Shoot:Play(0.05)
	end

	LaserSystem.Fire({
		origin         = origin,
		direction      = dir,
		shooter        = self.model,
		shooterFaction = cfg.FACTION,
		damage         = cfg.DAMAGE,
	})
end

function DroidAI:combatTick()
	if not self.isHostile then return false end
	local _, targetHrp, dist = self:findTarget()
	if not targetHrp then self.currentTargetHrp = nil; return false end
	self.currentTargetHrp = targetHrp
	if dist and dist <= self.config.ATTACK_RANGE and self:angleAlignedTo(targetHrp.Position) then
		self:tryFireAt(targetHrp.Position)
	end
	return true
end

-- ===== DEATH =====

function DroidAI:onDeath()
	if self.dead then return end
	self.dead = true

	for _, key in ipairs({ "Idle", "Walk", "Shoot" }) do
		local t = self.tracks[key]
		if t and t.IsPlaying then t:Stop(0.1) end
	end
	if self.walkingSound and self.walkingSound.IsPlaying then self.walkingSound:Stop() end

	self.humanoid.AutoRotate    = false
	self.humanoid.WalkSpeed     = 0
	self.humanoid.JumpPower     = 0
	self.humanoid.PlatformStand = true
	self.facingGoal = nil

	local blaster = self.model:FindFirstChild("Blaster", true)
	for _, p in ipairs(self.model:GetDescendants()) do
		if p:IsA("BasePart") and (not blaster or not p:IsDescendantOf(blaster)) then
			p.AssemblyLinearVelocity  = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
			p.Anchored  = true
			p.CanCollide = false
		end
	end

	task.spawn(function()
		if self.tracks.Death then
			self.tracks.Death:Play(0.1)
			if self.tracks.Death.Length > 0 then
				self.tracks.Death.Stopped:Wait()
			end
		end
		if self.tracks.DeathIdle then
			self.tracks.DeathIdle:Play(0.2)
		end
	end)

	Debris:AddItem(self.model, self.config.DEATH_LINGER)
end

-- ===== PATHFINDING =====

function DroidAI:walkToWithPathfinding(destPos)
	if self.dead then return end
	local cfg  = self.config
	local path = PathfindingService:CreatePath({
		AgentRadius  = cfg.AGENT_RADIUS,
		AgentHeight  = cfg.AGENT_HEIGHT,
		AgentCanJump = cfg.AGENT_CAN_JUMP,
	})

	local function travel()
		local ok = pcall(function() path:ComputeAsync(self.rootPart.Position, destPos) end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			self.humanoid:MoveTo(destPos)
			return false
		end
		local waypoints = path:GetWaypoints()
		for idx = 2, #waypoints do
			if self.dead then return true end
			local wp = waypoints[idx]
			if wp.Action == Enum.PathWaypointAction.Jump then
				self.humanoid.Jump = true
			end
			self.humanoid:MoveTo(wp.Position)

			local lastPos     = self.rootPart.Position
			local stuckTimer  = 0
			local moveThresh  = cfg.WALK_SPEED * cfg.REPATH_INTERVAL * 0.25
			while not self.dead do
				if distXZ(self.rootPart.Position, wp.Position) <= cfg.PF_WAYPOINT_REACH then break end
				self:combatTick()
				self.facingGoal = wp.Position
				self.humanoid:MoveTo(wp.Position)

				local airborne = self.humanoid.FloorMaterial == Enum.Material.Air
				local moved    = (self.rootPart.Position - lastPos).Magnitude
				if not airborne and moved < moveThresh then
					stuckTimer += cfg.REPATH_INTERVAL
					if stuckTimer >= cfg.PF_REPATH_TIMEOUT then return false end
				else
					stuckTimer = 0
				end
				lastPos = self.rootPart.Position
				task.wait(cfg.REPATH_INTERVAL)
			end
		end
		return true
	end

	for _ = 1, 3 do
		if self.dead then return end
		if travel() then return end
		task.wait(0.2)
	end
end

-- ===== AI LOOPS =====

function DroidAI:walkPath()
	if not self.pathParts or #self.pathParts == 0 then return end

	local startWp = self.pathParts[1]
	local finalWp = self.pathParts[#self.pathParts]
	if not startWp or not finalWp then return end

	self.isMarching = true
	self:playLocomotion("Walk")

	-- ====================================================================
	-- FIX FISICA ROBLOX: Forziamo l'Humanoid a superare i piccoli ostacoli
	-- ====================================================================
	self.humanoid.MaxSlopeAngle = 60      -- Permette di arrampicarsi su gradini più ripidi
	self.humanoid.AutoJumpEnabled = true  -- Il motore di Roblox proverà a farlo saltare da solo se si blocca

	-- Se i droidi continuano a strisciare i piedi, puoi scommentare la riga sotto
	-- per alzare leggermente il loro baricentro da terra (es. di 0.3 stud)
	-- self.humanoid.HipHeight = self.humanoid.HipHeight + 0.3 

	local offset = self.rootPart.Position - startWp.Position
	local targetInFormation = finalWp.Position + offset

	local reachDistance = self.config.PF_WAYPOINT_REACH or 4

	local lastPos = self.rootPart.Position
	local stuckTime = 0

	while not self.dead do
		local currentPos = self.rootPart.Position
		local dist = math.sqrt((currentPos.X - targetInFormation.X)^2 + (currentPos.Z - targetInFormation.Z)^2)

		if dist <= reachDistance then 
			break 
		end

		if self.combatTick then
			self:combatTick()
		end

		if self.config and self.config.WALK_SPEED then
			self.humanoid.WalkSpeed = self.config.WALK_SPEED
		else
			self.humanoid.WalkSpeed = 12
		end

		self.facingGoal = targetInFormation
		self.humanoid:MoveTo(targetInFormation)

		-- ====================================================================
		-- REATTIVITÀ ANTI-INCASTRO VELOCE (0.2 secondi)
		-- ====================================================================
		local distanceMoved = (currentPos - lastPos).Magnitude
		lastPos = currentPos

		-- Se il droide si muove pochissimo (sta sbattendo contro uno scalino)
		if distanceMoved < 0.4 then
			stuckTime = stuckTime + 0.1
			if stuckTime >= 0.2 then -- Reagisce subitissimo, senza far fermare il droide
				self.humanoid.Jump = true 
				stuckTime = 0
			end
		else
			stuckTime = 0
		end

		task.wait(0.1)
	end

	self.isMarching = false
	self.humanoid:MoveTo(self.rootPart.Position)

	if not self.dead and self.isHostile and self.huntMode then
		task.spawn(function()
			self:huntMode()
		end)
	end
end

function DroidAI:huntMode()
	local cfg = self.config
	while not self.dead do
		local _, targetHrp, dist = self:findTarget()
		if targetHrp then
			self.currentTargetHrp = targetHrp
			self.lastKnown   = targetHrp.Position
			self.searchEndsAt = nil
			self.facingGoal   = targetHrp.Position
			if self.isHostile and dist and dist <= cfg.ATTACK_RANGE and self:angleAlignedTo(targetHrp.Position) then
				self:tryFireAt(targetHrp.Position)
			end
			if dist and dist > cfg.MELEE_STOP_RANGE then
				self:playLocomotion("Walk")
				self:walkToWithPathfinding(targetHrp.Position)
			else
				self.humanoid:MoveTo(self.rootPart.Position)
				self:playLocomotion("Idle")
				task.wait(cfg.REPATH_INTERVAL)
			end
		else
			self.currentTargetHrp = nil
			if self.lastKnown then
				if distXZ(self.rootPart.Position, self.lastKnown) > cfg.WAYPOINT_REACH then
					self.facingGoal = self.lastKnown
					self:playLocomotion("Walk")
					self:walkToWithPathfinding(self.lastKnown)
				else
					self.searchEndsAt = self.searchEndsAt or (os.clock() + cfg.HUNT_SEARCH_TIME)
					self.humanoid:MoveTo(self.rootPart.Position)
					self:playLocomotion("Idle")
					self.facingGoal = nil
					if os.clock() >= self.searchEndsAt then
						self.lastKnown    = nil
						self.searchEndsAt = nil
					end
					task.wait(cfg.REPATH_INTERVAL)
				end
			else
				self.humanoid:MoveTo(self.rootPart.Position)
				self:playLocomotion("Idle")
				self.facingGoal = nil
				task.wait(cfg.REPATH_INTERVAL)
			end
		end
	end
end

-- Called by manager after loadPath()
function DroidAI:startAI()
	self:playLocomotion("Idle")
	task.spawn(function()
		if self.pathParts then self:walkPath() end
		if not self.dead then
			if self.isHostile then
				self:huntMode()
			else
				self:playLocomotion("Idle")
				self.humanoid:MoveTo(self.rootPart.Position)
				self.facingGoal = nil
			end
		end
	end)
end

return DroidAI
