-- DroidManager.lua (Script - ServerScriptService)
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DROID_TAG    = "CISDroid"
local INIT_STAGGER = 0   

-- === IMPOSTAZIONI FORMAZIONE ===
local DROIDS_PER_ROW = 4
local DROID_SPACING = 6 -- Studs di distanza tra un droide e l'altro
local droidSpawnCounter = 0 -- Conta i droidi per assegnare il posto in griglia

local DroidAI = require(ReplicatedStorage:WaitForChild("DroidSystemRep")
	:WaitForChild("Modules"):WaitForChild("DroidAI"))

local activeDroids = {}

RunService.Heartbeat:Connect(function(dt)
	for i = #activeDroids, 1, -1 do
		local state = activeDroids[i]
		if state.dead or not state.model.Parent then
			table.remove(activeDroids, i)
		else
			state:updateFacing(dt)
		end
	end
end)

local initQueue    = {}
local queueRunning = false

local function processQueue()
	if queueRunning then return end
	queueRunning = true
	task.spawn(function()
		while #initQueue > 0 do
			local model = table.remove(initQueue, 1)
			if model and model.Parent then
				local ok, err = pcall(function()
					local state = DroidAI.new(model)
					
					-- === CALCOLO DELLA POSIZIONE IN FORMAZIONE ===
					local col = droidSpawnCounter % DROIDS_PER_ROW
					local row = math.floor(droidSpawnCounter / DROIDS_PER_ROW)
					
					-- Calcola l'offset relativo al centro della formazione
					local offsetX = (col - (DROIDS_PER_ROW - 1) / 2) * DROID_SPACING
					local offsetZ = row * DROID_SPACING
					
					-- Assegniamo l'offset allo stato del droide prima di avviarlo
					state.formationOffset = Vector3.new(offsetX, 0, offsetZ)
					droidSpawnCounter = droidSpawnCounter + 1
					-- ==============================================

					state:loadPath()   
					state:startAI()
					table.insert(activeDroids, state)
				end)
				if not ok then
					warn("DroidManager: failed to init", model.Name, "—", err)
				end
			end
			task.wait(INIT_STAGGER)
		end
		queueRunning = false
	end)
end

local function registerDroid(model)
	if not model:IsA("Model") then return end

	-- Assegna ogni parte del droide al gruppo "Droids" così non si spingono
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Droids"
		end
	end

	table.insert(initQueue, model)
	processQueue()
end

for _, model in ipairs(CollectionService:GetTagged(DROID_TAG)) do
	registerDroid(model)
end

CollectionService:GetInstanceAddedSignal(DROID_TAG):Connect(registerDroid)