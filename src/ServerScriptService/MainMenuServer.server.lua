-- MainMenuServer.lua (Versione 3.0 – Zombie Attack Style)
-- FLOW: Scelta Reggimento -> Morph + Spawn Venator -> Voto Mappa -> Teleport
-- RIMOSSI: CivilianGroup, HostileGroup (disabilitato), scelta Base/Border
-- AGGIUNTI: Sistema voto mappe, TeleportService

local Players            = game:GetService("Players")
local Teams              = game:GetService("Teams")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TeleportService    = game:GetService("TeleportService")

local MainMenuRP = ReplicatedStorage:WaitForChild("MainMenuRP")

local function loadSettingsModule()
	if MainMenuRP:FindFirstChild("Settings") then
		local ok, mod = pcall(function() return require(MainMenuRP.Settings) end)
		if ok and mod then return mod end
	end
	local gc = ReplicatedStorage:FindFirstChild("group_config")
	if gc then
		local ok2, mod2 = pcall(function() return require(gc) end)
		if ok2 and mod2 then return mod2 end
	end
	error("[MainMenuServer] Impossibile trovare Settings o group_config.")
end

local Settings     = loadSettingsModule()
local MorphHandler = require(game.ServerScriptService:WaitForChild("MorphHandler"))

-- MapConfig
local MapConfig
do
	local ok, mod = pcall(function()
		return require(MainMenuRP:WaitForChild("MapConfig"))
	end)
	if ok and mod then
		MapConfig = mod
	else
		warn("[MainMenuServer] MapConfig non trovato, voting disabilitato.")
		MapConfig = { Maps = {}, VOTE_DURATION = 30 }
	end
end

-- Remotes folder
local Remotes = MainMenuRP:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = MainMenuRP

local function ensureEvent(name)
	return Remotes:FindFirstChild(name) or (function()
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = Remotes
		return re
	end)()
end

local function ensureFunction(name)
	return Remotes:FindFirstChild(name) or (function()
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = Remotes
		return rf
	end)()
end

-- Morph remotes
local MorphPlrRE     = ensureEvent("MorphPlr")
local MorphPlrUnitRE = ensureEvent("MorphPlrUnit")
local MorphPlrGRE    = ensureEvent("MorphPlrG")
local GetUnitsRF     = ensureFunction("GetUnits")

-- Voting remotes
local VoteMapRE      = ensureEvent("VoteMap")
local VoteUpdateRE   = ensureEvent("VoteUpdate")
local StartVotingRE  = ensureEvent("StartVoting")
local MapSelectedRE  = ensureEvent("MapSelected")

-- ================= CONFIG =================
local COOLDOWN_SECONDS   = 5
local ENABLE_DEBUG       = true
local ENFORCE_MEMBERSHIP = false
-- ==========================================

local function dbg(fmt, ...)
	if ENABLE_DEBUG then
		print(("[MainMenuServer] " .. fmt):format(...))
	end
end

-- ================= ALIAS INDEX =================
local aliasIndex = {}
local teamNameUsage = {}
local teamNameToDisplayList = {}

local function countTeamName(teamName, displayName)
	if not teamName then return end
	local lower = teamName:lower()
	teamNameUsage[lower] = (teamNameUsage[lower] or 0) + 1
	teamNameToDisplayList[lower] = teamNameToDisplayList[lower] or {}
	table.insert(teamNameToDisplayList[lower], displayName)
end

local function addEntry(displayName, teamName, groupId)
	if not displayName then return end
	aliasIndex[displayName:lower()] = {
		displayName = displayName,
		folderName  = displayName,
		groupId     = (typeof(groupId) == "number") and groupId or nil,
		isCivilian  = false,
		isHostile   = false,
		teamName    = teamName
	}
end

-- Build index (senza CivilianGroup e HostileGroup)
if Settings.MainGroup then
	countTeamName(Settings.MainGroup.teamName, Settings.MainGroup.displayName)
end
if Settings.DivisionalGroups then
	for _, data in pairs(Settings.DivisionalGroups) do
		countTeamName(data.teamName, data.displayName)
	end
end
if Settings.Gamepasses then
	for _, gp in pairs(Settings.Gamepasses) do
		if gp.displayName and gp.teamName then
			countTeamName(gp.teamName, gp.displayName)
		end
	end
end

if Settings.MainGroup then
	addEntry(Settings.MainGroup.displayName, Settings.MainGroup.teamName, Settings.MainGroup.id)
end
if Settings.DivisionalGroups then
	for _, data in pairs(Settings.DivisionalGroups) do
		addEntry(data.displayName, data.teamName, data.id)
	end
end
if Settings.Gamepasses then
	for _, gp in pairs(Settings.Gamepasses) do
		if gp.displayName and #gp.displayName > 0 then
			addEntry(gp.displayName, gp.teamName, nil)
		end
	end
end

-- Alias unici
for teamLower, count in pairs(teamNameUsage) do
	if count == 1 then
		local list = teamNameToDisplayList[teamLower]
		if list and list[1] then
			local displayLower = list[1]:lower()
			if aliasIndex[displayLower] then
				aliasIndex[teamLower] = aliasIndex[displayLower]
			end
		end
	end
end

local function resolveEntry(name)
	if type(name) ~= "string" then return nil, "invalid" end
	local lower = name:lower()
	local entry = aliasIndex[lower]
	if entry then return entry end
	if teamNameUsage[lower] and teamNameUsage[lower] > 1 then
		return nil, "ambiguous"
	end
	return nil, "notfound"
end

-- ================= TEAM / COOLDOWN =================
local morphCooldown = {}
local lastMorphByUserId = {}

local function setPlayerTeam(plr, teamName)
	if not teamName then return end
	local t = Teams:FindFirstChild(teamName)
	if t then
		plr.Team = t
		plr.Neutral = false
	end
end

local function canMorph(plr)
	local now = os.clock()
	local last = morphCooldown[plr.UserId]
	if not last or (now - last) > COOLDOWN_SECONDS then
		morphCooldown[plr.UserId] = now
		return true
	end
	return false
end

-- =============== FORWARD DECLARATION ===============
local onPlayerSpawned -- defined below in voting section

local function applyEntry(plr, entry, option, unitName)
	if not entry then return end
	if not canMorph(plr) then
		dbg("Cooldown attivo per %s", plr.Name)
		return
	end

	if ENFORCE_MEMBERSHIP and entry.groupId then
		local ok, rank = pcall(function() return plr:GetRankInGroup(entry.groupId) end)
		if not ok or type(rank) ~= "number" or rank <= 0 then
			dbg("Blocco morph: %s non è nel gruppo %s", plr.Name, tostring(entry.groupId))
			return
		end
	end

	setPlayerTeam(plr, entry.teamName)

	dbg("Applico morph: player=%s folder=%s groupId=%s unit=%s",
		plr.Name, entry.folderName, tostring(entry.groupId), tostring(unitName))

	-- Spawn sempre su Venator (option=1, no Base/Border)
	MorphHandler.ApplyMorphAndTeleport(plr, entry.folderName, entry.groupId, 1, false, false, unitName)

	lastMorphByUserId[plr.UserId] = {
		folderName = entry.folderName,
		groupId    = entry.groupId,
		option     = 1,
		isCivilian = false,
		isHostile  = false,
		unitName   = unitName,
		teamName   = entry.teamName
	}

	-- Segna il player come spawnato
	if onPlayerSpawned then
		onPlayerSpawned(plr)
	end
end

-- Respawn reapply
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		task.spawn(function()
			-- Wait for avatar appearance to finish loading before reapplying morph,
			-- otherwise Roblox avatar load overwrites the shirt/pants.
			char:WaitForChild("Humanoid", 10)
			char:WaitForChild("HumanoidRootPart", 10)
			task.wait(1)
			local rec = lastMorphByUserId[plr.UserId]
			if rec then
				dbg("Reapply morph a respawn per %s (%s, unit=%s)", plr.Name, rec.folderName, tostring(rec.unitName))
				setPlayerTeam(plr, rec.teamName)
				MorphHandler.ApplyMorphAndTeleport(plr, rec.folderName, rec.groupId, 1, false, false, rec.unitName)
			end
		end)
	end)
end)

-- =============== MAP VOTING SYSTEM ===============
local spawnedPlayers = {}
local votingActive = false
local votingStartTime = 0
local playerVotes = {}
local mapVoteCounts = {}

local function getVoteCounts()
	local counts = {}
	for i = 1, #MapConfig.Maps do
		counts[i] = mapVoteCounts[i] or 0
	end
	return counts
end

local function broadcastVoteUpdate()
	local counts = getVoteCounts()
	for _, plr in ipairs(Players:GetPlayers()) do
		if spawnedPlayers[plr.UserId] then
			VoteUpdateRE:FireClient(plr, counts)
		end
	end
end

local function selectWinningMap()
	local counts = getVoteCounts()
	local maxVotes = 0
	for _, c in ipairs(counts) do
		if c > maxVotes then maxVotes = c end
	end
	local tied = {}
	for i, c in ipairs(counts) do
		if c == maxVotes then
			table.insert(tied, i)
		end
	end
	if #tied == 0 then
		return math.random(1, #MapConfig.Maps)
	end
	return tied[math.random(1, #tied)]
end

local function teleportAllToMap(mapIndex)
	local mapData = MapConfig.Maps[mapIndex]
	if not mapData then
		warn("[MainMenuServer] Mappa non valida index:", mapIndex)
		return
	end

	-- Notifica i client
	for _, plr in ipairs(Players:GetPlayers()) do
		if spawnedPlayers[plr.UserId] then
			MapSelectedRE:FireClient(plr, mapData.name, mapData.placeId)
		end
	end

	task.wait(3)

	local playersToTeleport = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if spawnedPlayers[plr.UserId] then
			table.insert(playersToTeleport, plr)
		end
	end

	if #playersToTeleport == 0 then
		warn("[MainMenuServer] Nessun player da teleportare.")
		return
	end

	dbg("Teleporting %d players to %s (PlaceId=%s)", #playersToTeleport, mapData.name, tostring(mapData.placeId))

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(mapData.placeId, playersToTeleport)
	end)
	if not ok then
		warn("[MainMenuServer] Errore teleport:", err)
	end
end

local function startVotingRound()
	if votingActive then return end
	if #MapConfig.Maps == 0 then
		warn("[MainMenuServer] Nessuna mappa configurata.")
		return
	end

	votingActive = true
	votingStartTime = os.clock()
	playerVotes = {}
	mapVoteCounts = {}

	dbg("Voting iniziato! Durata: %d secondi", MapConfig.VOTE_DURATION)

	local mapList = {}
	for i, m in ipairs(MapConfig.Maps) do
		mapList[i] = { name = m.name, imageId = m.imageId, index = i }
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if spawnedPlayers[plr.UserId] then
			StartVotingRE:FireClient(plr, mapList, MapConfig.VOTE_DURATION)
		end
	end

	task.delay(MapConfig.VOTE_DURATION, function()
		if not votingActive then return end
		votingActive = false
		local winnerIndex = selectWinningMap()
		dbg("Mappa vincente: %s (index %d)", MapConfig.Maps[winnerIndex].name, winnerIndex)
		teleportAllToMap(winnerIndex)
	end)
end

onPlayerSpawned = function(plr)
	dbg("Player spawned: %s", plr.Name)
	spawnedPlayers[plr.UserId] = plr

	if votingActive then
		dbg("Player %s entrato durante votazione attiva", plr.Name)
		local mapList = {}
		for i, m in ipairs(MapConfig.Maps) do
			mapList[i] = { name = m.name, imageId = m.imageId, index = i }
		end
		local remaining = math.max(0, MapConfig.VOTE_DURATION - (os.clock() - votingStartTime))
		StartVotingRE:FireClient(plr, mapList, remaining)
		VoteUpdateRE:FireClient(plr, getVoteCounts())
		return
	end

	-- Primo player: avvia voting dopo 5 secondi
	local count = 0
	for _ in pairs(spawnedPlayers) do count = count + 1 end
	dbg("Numero player spawnati: %d", count)
	if count == 1 then
		dbg("Primo player spawnato, avvio countdown voto (5s)")
		task.delay(5, function()
			if not votingActive then
				startVotingRound()
			end
		end)
	end
end

-- Gestione voto
VoteMapRE.OnServerEvent:Connect(function(plr, mapIndex)
	dbg("Ricevuto voto da %s per mapIndex %s", plr.Name, tostring(mapIndex))
	if not votingActive then 
		dbg("Voto ignorato: votazione non attiva")
		return 
	end
	if not spawnedPlayers[plr.UserId] then 
		dbg("Voto ignorato: player non registrato come spawnato")
		return 
	end
	if type(mapIndex) ~= "number" then return end
	mapIndex = math.floor(mapIndex)
	if mapIndex < 1 or mapIndex > #MapConfig.Maps then 
		dbg("Voto ignorato: index fuori range")
		return 
	end

	local prev = playerVotes[plr.UserId]
	if prev then
		mapVoteCounts[prev] = math.max(0, (mapVoteCounts[prev] or 0) - 1)
	end

	playerVotes[plr.UserId] = mapIndex
	mapVoteCounts[mapIndex] = (mapVoteCounts[mapIndex] or 0) + 1

	dbg("Player %s ha votato per %s (index %d)", plr.Name, MapConfig.Maps[mapIndex].name, mapIndex)
	broadcastVoteUpdate()
end)

-- Pulizia
Players.PlayerRemoving:Connect(function(plr)
	morphCooldown[plr.UserId] = nil
	lastMorphByUserId[plr.UserId] = nil
	local prev = playerVotes[plr.UserId]
	if prev then
		mapVoteCounts[prev] = math.max(0, (mapVoteCounts[prev] or 0) - 1)
		playerVotes[plr.UserId] = nil
	end
	spawnedPlayers[plr.UserId] = nil
	if votingActive then broadcastVoteUpdate() end
end)

-- =============== MORPH REMOTES ===============

GetUnitsRF.OnServerInvoke = function(plr, displayName)
	if type(displayName) ~= "string" then return {} end
	local entry = resolveEntry(displayName)
	if not entry then return {} end
	local units = {}
	local ok, list = pcall(function()
		return MorphHandler.GetUnitsFor(plr, entry.folderName, entry.groupId)
	end)
	if ok and type(list) == "table" then
		units = list
	end
	return units
end

MorphPlrRE.OnServerEvent:Connect(function(plr, displayName, option)
	if type(displayName) ~= "string" then return end
	local entry, reason = resolveEntry(displayName)
	if not entry then
		if reason == "ambiguous" then
			local list = teamNameToDisplayList[displayName:lower()]
			warn(("[MainMenuServer] Nome '%s' ambiguo. Usa: %s")
				:format(displayName, list and table.concat(list, ", ") or "N/A"))
		else
			warn("[MainMenuServer] DisplayName non trovato:", displayName)
		end
		return
	end
	applyEntry(plr, entry, 1, nil)
end)

MorphPlrUnitRE.OnServerEvent:Connect(function(plr, displayName, option, unitName)
	if type(displayName) ~= "string" then return end
	if unitName ~= nil and type(unitName) ~= "string" then unitName = nil end
	local entry = resolveEntry(displayName)
	if not entry then return end
	applyEntry(plr, entry, 1, unitName)
end)

MorphPlrGRE.OnServerEvent:Connect(function(plr, displayName)
	if type(displayName) ~= "string" then return end
	local entry, reason = resolveEntry(displayName)
	if not entry then
		warn("[MainMenuServer] Gamepass displayName invalido:", displayName, reason)
		return
	end
	local gpId
	if Settings.Gamepasses then
		for _, gp in pairs(Settings.Gamepasses) do
			if gp.displayName == entry.displayName then
				gpId = gp.GamepassId
				break
			end
		end
	end
	if gpId then
		local owns = false
		local ok = pcall(function() owns = MarketplaceService:UserOwnsGamePassAsync(plr.UserId, gpId) end)
		if not ok or not owns then
			dbg("Player %s non possiede gamepass %s", plr.Name, tostring(gpId))
			return
		end
	end
	applyEntry(plr, entry, 1, nil)
end)

dbg("MainMenuServer v3.0 inizializzato (Zombie Attack Style).")