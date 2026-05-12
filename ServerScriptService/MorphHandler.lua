-- MorphHandler.lua (VERSION 1.5 DEBUG – Unit Selection deep logging)
-- Differenze rispetto alla 1.5 precedente:
--  * Aggiunto UNIT_DEBUG per tracciare raccolta varianti/unit.
--  * Log dettagliato in GetUnitsFor, chooseVariant, collectUnitNames.
--  * Ogni passaggio stampato con prefisso [MorphHandler][UNIT]
--  * Nessun cambiamento funzionale salvo logging.
--  * Facile disattivare rimettendo UNIT_DEBUG = false.

local MorphHandler = {}

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local Lighting            = game:GetService("Lighting")
local MarketplaceService  = game:GetService("MarketplaceService")

-- ================= CONFIG =================
local LOG                   = false              -- log generici (teleport ecc.)
local ENABLE_VARIANT_DEBUG  = false              -- debug vecchia logica variant
local ALLOW_LOWEST_FALLBACK = false
local CLEAN_HEAD_ON_HELMET  = true
local REMOVE_ACCESSORIES    = true
local SPAWN_Y_OFFSET        = 3
local SPAWN_ROOT_PATH       = {"MainMenuWorkspace", "Spawns" }
local SPAWN_KEYS            = { Border="Border", Base="Base", Civilian="Civilian", Hostile="Hostile", Venator="Venator" }
local VENATOR_SPAWN_NAMES   = { "Spawn1", "Spawn2", "Spawn3" }

-- === NUOVO FLAG DEBUG UNIT ===
local UNIT_DEBUG            = false               -- METTI false per spegnere i log unit
-- ==========================================

-- ================= GAMEPASS / SUPPORTER TOOLS =================
local GAMEPASS_TOOLS = {
	{ id = 1279011849, name = "DH17" },
	{ id = 1277489615, name = "Z6" },
	{ id = 1278884013, name = "Cloak" },
	{ id = 1278105056, name = "A280C" },
	{ id = 1316765035, name = "DC15X" },
	{ id = 1346814850, name = "BoomBox" },
}

local SUPPORTER_TOOLS = {
	[2499199420] = { "Z6", "Jetpack" },
	[3242403282] = { "Z6", "Jetpack" },
	[2318491334] = { "Z6", "Jetpack" },
}
-- ==============================================================

local function log(fmt, ...)
	if LOG then
		print(("[MorphHandler] " .. fmt):format(...))
	end
end

local function udbg(fmt, ...)
	if UNIT_DEBUG then
		print(("[MorphHandler][UNIT] " .. fmt):format(...))
	end
end

local function getMorphsRoot()
	local mm = ReplicatedStorage:FindFirstChild("MainMenuRP")
	assert(mm, "[MorphHandler] ReplicatedStorage.MainMenuRP non trovato")
	local morphs = mm:FindFirstChild("Morphs")
	assert(morphs, "[MorphHandler] MainMenuRP.Morphs non trovato")
	return morphs
end

-- ================= RIG SUPPORT =================
local R6_BODY_SET = {
	Head=true, Torso=true, ["Left Arm"]=true, ["Right Arm"]=true,
	["Left Leg"]=true, ["Right Leg"]=true, HumanoidRootPart=true
}
local R15_BODY_SET = {
	Head=true, UpperTorso=true, LowerTorso=true,
	LeftUpperArm=true, LeftLowerArm=true, LeftHand=true,
	RightUpperArm=true, RightLowerArm=true, RightHand=true,
	LeftUpperLeg=true, LeftLowerLeg=true, LeftFoot=true,
	RightUpperLeg=true, RightLowerLeg=true, RightFoot=true,
	HumanoidRootPart=true
}
local R6_TO_R15 = {
	["Left Arm"]="LeftUpperArm",
	["Right Arm"]="RightUpperArm",
	["Left Leg"]="LeftUpperLeg",
	["Right Leg"]="RightUpperLeg",
	Torso="UpperTorso",
	Head="Head"
}

local function getRigType(character)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	return hum and hum.RigType or Enum.HumanoidRigType.R6
end

local function mapBodyForRig(name, rigType)
	if rigType == Enum.HumanoidRigType.R6 then return name end
	return R6_TO_R15[name] or name
end

local function findCharacterPart(character, bodyName, rigType)
	local mapped = mapBodyForRig(bodyName, rigType)
	local p = character:FindFirstChild(mapped, true)
	if not (p and p:IsA("BasePart")) then return nil end
	if rigType == Enum.HumanoidRigType.R6 then
		return R6_BODY_SET[p.Name] and p or nil
	else
		return R15_BODY_SET[p.Name] and p or nil
	end
end

-- ================= CLEAR / TOOLS =================
local function clearPreviousMorphPieces(character)
	for _, obj in ipairs(character:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("IsMorphModel") then
			obj:Destroy()
		end
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.Transparency = 0
	end
end

local function clearMorphTools(player)
	if not player then return end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("IsMorphTool") then tool:Destroy() end
		end
	end
	local sg = player:FindFirstChildOfClass("StarterGear")
	if sg then
		for _, tool in ipairs(sg:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("IsMorphTool") then tool:Destroy() end
		end
	end
end

-- ================= STRIP / WELD =================
local function stripUnsafe(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end
end

local function firstBasePart(inst)
	if inst:IsA("BasePart") then return inst end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function getRootForContainer(model)
	if model:IsA("Model") then
		local mid = model:FindFirstChild("Middle")
		if mid and mid:IsA("BasePart") then model.PrimaryPart = mid; return mid end
		if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
		local any = firstBasePart(model)
		if any then model.PrimaryPart = any end
		return any
	elseif model:IsA("BasePart") then
		return model
	else
		return firstBasePart(model)
	end
end

local function WeldObject(character, sourceModel, bodyPart)
	local clone = sourceModel:Clone()
	stripUnsafe(clone)
	if character:FindFirstChild(sourceModel.Name) then
		character[sourceModel.Name]:Destroy()
	end
	local root = getRootForContainer(clone)
	if not root then
		warn("[MorphHandler] Nessun BasePart in '"..sourceModel.Name.."'")
		return
	end
	if clone:IsA("Model") then
		clone:SetPrimaryPartCFrame(bodyPart.CFrame)
	else
		root.CFrame = bodyPart.CFrame
	end
	clone.Parent = character
	local function fixPart(bp)
		bp.Anchored = false
		bp.CanCollide = false
		bp.Massless = true
	end
	if clone:IsA("BasePart") then fixPart(clone) end
	for _, bp in ipairs(clone:GetDescendants()) do
		if bp:IsA("BasePart") then fixPart(bp) end
	end
	fixPart(root)

	if CLEAN_HEAD_ON_HELMET and sourceModel.Name:lower() == "helmet" then
		local head = character:FindFirstChild("Head")
		if head then head.Transparency = 1 end
	end

	if clone:IsA("Model") then
		for _, p in ipairs(clone:GetChildren()) do
			if p:IsA("BasePart") and p ~= root then
				local W = Instance.new("Weld")
				W.Part0 = root
				W.Part1 = p
				W.C0 = root.CFrame:Inverse() * root.CFrame
				W.C1 = p.CFrame:Inverse() * root.CFrame
				W.Parent = root
			end
		end
	end

	local weldToBody = Instance.new("Weld")
	weldToBody.Part0 = bodyPart
	weldToBody.Part1 = root
	weldToBody.C0 = CFrame.new()
	weldToBody.C1 = root.CFrame:Inverse() * bodyPart.CFrame
	weldToBody.Parent = bodyPart

	clone:SetAttribute("IsMorphModel", true)
end

-- ================= CLOTHING / TOOLS =================
local function applyClothing(character, morphGroup)
	-- Cerca ricorsivamente nei discendenti del variant
	local newShirt = morphGroup:FindFirstChildWhichIsA("Shirt", true)
	local newPants = morphGroup:FindFirstChildWhichIsA("Pants", true)

	local oldShirt = character:FindFirstChildOfClass("Shirt")
	local oldPants = character:FindFirstChildOfClass("Pants")

	-- Shirt
	if newShirt and newShirt:IsA("Shirt") then
		if oldShirt then oldShirt:Destroy() end
		local clone = newShirt:Clone()
		clone.Name = "Shirt"
		clone.Parent = character
	else
		udbg("applyClothing: nessuna Shirt trovata nel variant; mantengo quella attuale")
	end

	-- Pants
	if newPants and newPants:IsA("Pants") then
		if oldPants then oldPants:Destroy() end
		local clone = newPants:Clone()
		clone.Name = "Pants"
		clone.Parent = character
	else
		udbg("applyClothing: nessun Pants trovato nel variant; mantengo quello attuale")
	end
end

local function getRankNumberFromInstance(obj)
	if not obj then return nil end
	local rankObj = obj:FindFirstChild("Rank")
	if rankObj and rankObj:IsA("ValueBase") and typeof(rankObj.Value) == "number" then
		return rankObj.Value
	end
	local attr = obj:GetAttribute("Rank")
	if typeof(attr) == "number" then return attr end
	return nil
end

local function giveTools(player, morphGroup, playerRank)
	clearMorphTools(player)
	for _, v in ipairs(morphGroup:GetChildren()) do
		if v:IsA("Tool") then
			local required = getRankNumberFromInstance(v)
			if required and playerRank < required then
				log("Skip tool %s (playerRank %d < required %d)", v.Name, playerRank, required)
			else
				local t1 = v:Clone()
				t1:SetAttribute("IsMorphTool", true)
				t1.Parent = player.Backpack
				local sg = player:FindFirstChildOfClass("StarterGear")
				if sg then
					local t2 = v:Clone()
					t2:SetAttribute("IsMorphTool", true)
					t2.Parent = sg
				end
			end
		end
	end
end

-- ================= GAMEPASS / SUPPORTER GIVE =================
local function getToolSourceRoot()
	-- Tool originali in Lighting
	return Lighting
end

local function playerHasTool(player, toolName)
	if not player or not toolName then return false end

	local backpack = player:FindFirstChild("Backpack")
	if backpack and backpack:FindFirstChild(toolName) then
		return true
	end

	local char = player.Character
	if char and char:FindFirstChild(toolName) then
		return true
	end

	local sg = player:FindFirstChildOfClass("StarterGear")
	if sg and sg:FindFirstChild(toolName) then
		return true
	end

	return false
end

local function giveToolByName(player, toolName, markAsMorphTool)
	if not player or not toolName then return false end
	if playerHasTool(player, toolName) then return true end

	local srcRoot = getToolSourceRoot()
	local tool = srcRoot and srcRoot:FindFirstChild(toolName)
	if not (tool and tool:IsA("Tool")) then
		warn(("[MorphHandler] Tool '%s' non trovato in Lighting"):format(toolName))
		return false
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		local t1 = tool:Clone()
		if markAsMorphTool then
			t1:SetAttribute("IsMorphTool", true)
		end
		t1.Parent = backpack
	end

	local sg = player:FindFirstChildOfClass("StarterGear")
	if sg then
		local t2 = tool:Clone()
		if markAsMorphTool then
			t2:SetAttribute("IsMorphTool", true)
		end
		t2.Parent = sg
	end

	return true
end

local function giveOwnedGamepassTools_Server(player)
	for _, gp in ipairs(GAMEPASS_TOOLS) do
		local ok, hasPass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gp.id)
		end)
		if ok and hasPass then
			-- NON marcato IsMorphTool: deve restare indipendente dalla morph
			giveToolByName(player, gp.name, false)
		end
	end
end

local function giveSupporterTools_Server(player)
	local tools = SUPPORTER_TOOLS[player.UserId]
	if not tools then return end
	for _, toolName in ipairs(tools) do
		-- NON marcato IsMorphTool: deve restare indipendente dalla morph
		giveToolByName(player, toolName, false)
	end
end

-- ================= UNIT / VARIANT SELECTION =================
local function collectVariantsByRank(teamFolder, playerRank)
	local list = {}
	for _, ch in ipairs(teamFolder:GetChildren()) do
		if (ch:IsA("Folder") or ch:IsA("Model")) then
			local r = getRankNumberFromInstance(ch)
			if r ~= nil then
				if r == playerRank then
					table.insert(list, ch)
				else
					udbg("Scarto variante '%s' (Rank=%s diverso da PlayerRank=%s)", ch.Name, tostring(r), tostring(playerRank))
				end
			else
				udbg("Variante '%s' senza Rank -> ignorata", ch.Name)
			end
		end
	end
	return list
end

local function getUnitNameFromVariant(variantFolder)
	local sv = variantFolder:FindFirstChild("Unit")
	if sv and sv:IsA("StringValue") and sv.Value ~= "" then
		return sv.Value
	end
	local attr = variantFolder:GetAttribute("Unit")
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end
	return nil
end

local function collectUnitNames(teamFolder, playerRank)
	udbg("Raccolgo Unit per Rank=%s in folder '%s'", tostring(playerRank), teamFolder.Name)
	local variants = collectVariantsByRank(teamFolder, playerRank)
	udbg("Tot varianti candidate con rank esatto: %d", #variants)
	local names = {}
	local seen = {}
	for _, var in ipairs(variants) do
		local nm = getUnitNameFromVariant(var)
		udbg("  Variante '%s' -> Unit='%s'", var.Name, tostring(nm))
		if nm and nm ~= "" then
			if not seen[nm] then
				seen[nm] = true
				table.insert(names, nm)
			else
				udbg("    (Duplicato Unit '%s' ignorato)", nm)
			end
		end
	end
	table.sort(names)
	udbg("Lista finale unit per rank %s: [%s]", tostring(playerRank), table.concat(names, ", "))
	return names
end

local function chooseVariant(teamFolder, playerRank, unitName)
	udbg("chooseVariant start folder='%s' rank=%s unitName='%s'", teamFolder.Name, tostring(playerRank), tostring(unitName))
	local candidates = collectVariantsByRank(teamFolder, playerRank)
	udbg("Candidati dopo filtraggio rank: %d", #candidates)
	if #candidates == 0 then
		udbg("Nessun candidato per rank %s. Cerco il rank più basso disponibile...", tostring(playerRank))
		local allVariants = teamFolder:GetChildren()
		local bestVar = nil
		local minRank = math.huge
		for _, v in ipairs(allVariants) do
			if v:IsA("Folder") or v:IsA("Model") then
				local r = getRankNumberFromInstance(v)
				if r ~= nil and r < minRank then
					minRank = r
					bestVar = v
				end
			end
		end
		if bestVar then
			udbg("Fallback al rank più basso trovato: %s (Rank=%d)", bestVar.Name, minRank)
			return bestVar
		end
		udbg("Nessuna variante trovata in assoluto in '%s'", teamFolder.Name)
		return nil
	end
	if unitName then
		for _, var in ipairs(candidates) do
			local nm = getUnitNameFromVariant(var)
			if nm == unitName then
				udbg("Scelta variante per unit match esatto: %s (Unit=%s)", var.Name, nm)
				return var
			end
		end
		udbg("Unit richiesta '%s' non trovata fra i candidati -> fallback", unitName)
	end

	if #candidates == 1 then
		udbg("Un solo candidato; scelgo '%s'", candidates[1].Name)
		return candidates[1]
	end

	table.sort(candidates, function(a,b)
		local ua = getUnitNameFromVariant(a) or a.Name
		local ub = getUnitNameFromVariant(b) or b.Name
		return ua:lower() < ub:lower()
	end)
	local chosen = candidates[1]
	udbg("Più candidati, scelgo primo dopo sort: '%s' (Unit=%s)", chosen.Name, tostring(getUnitNameFromVariant(chosen)))
	return chosen
end

function MorphHandler.GetUnitsFor(player, folderName, groupId)
	local result = {}
	udbg("GetUnitsFor player=%s folder='%s' groupId=%s", player and player.Name or "?", tostring(folderName), tostring(groupId))
	local root = getMorphsRoot()
	local teamFolder = root:FindFirstChild(folderName)
	if not teamFolder then
		udbg("Folder morph '%s' non trovato", tostring(folderName))
		return result
	end
	local playerRank = 0
	if groupId and typeof(groupId)=="number" and player then
		local ok, r = pcall(function() return player:GetRankInGroup(groupId) end)
		if ok and type(r)=="number" then playerRank = r end
	end
	udbg("PlayerRank calcolato: %d", playerRank)
	result = collectUnitNames(teamFolder, playerRank)
	if #result == 0 then
		udbg("Nessuna Unit trovata (possibile: rank mismatch, mancato StringValue 'Unit', o varianti senza rank).")
	end
	return result
end

-- ================= APPLY PIECES =================
local SUPPORTED_CONTAINERS = {
	Leg1="Left Leg", Leg2="Right Leg",
	Arm1="Left Arm", Arm2="Right Arm",
	Chest="Torso", Helmet="Head",
	["Left Arm"]="Left Arm", ["Right Arm"]="Right Arm",
	["Left Leg"]="Left Leg", ["Right Leg"]="Right Leg",
	["Torso"]="Torso", ["Head"]="Head",
}

local function tryWeldContainer(character, rigType, morphGroup, playerRank, containerName, bodyName)
	if not morphGroup then return false end
	local part = morphGroup:FindFirstChild(containerName)
	if not part then return false end
	local required = getRankNumberFromInstance(part)
	if required and playerRank < required then
		log("Skip piece %s (playerRank %d < required %d)", containerName, playerRank, required)
		return false
	end
	local body = findCharacterPart(character, bodyName, rigType)
	if not body then
		log("Body part '%s' non trovata per '%s'", bodyName, containerName)
		return false
	end
	WeldObject(character, part, body)
	return true
end

-- ================= RANK =================
local function getPlayerRankInGroupId(player, groupId)
	if typeof(groupId) ~= "number" then return 0 end
	local ok, rank = pcall(function() return player:GetRankInGroup(groupId) end)
	if not ok or type(rank) ~= "number" then return 0 end
	if ENABLE_VARIANT_DEBUG then
		print(string.format("[MorphHandler][Rank] Player=%s GroupID=%d Rank=%d", player.Name, groupId, rank))
	end
	return rank
end

-- ================= CORE APPLY =================
function MorphHandler.ApplyMorph(character, folderName, groupId, unitName)
	if not character or not character.Parent then return false end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return false end

	if groupId ~= nil and typeof(groupId) ~= "number" then
		warn(("[MorphHandler] groupId NON numerico (%s) -> nil"):format(tostring(groupId)))
		groupId = nil
	end

	log("ApplyMorph START folder='%s' groupId=%s unit='%s'", tostring(folderName), tostring(groupId), tostring(unitName))

	clearPreviousMorphPieces(character)
	clearMorphTools(player)

	if REMOVE_ACCESSORIES then
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then pcall(function() hum:RemoveAccessories() end) end
	end

	local root = getMorphsRoot()
	local teamFolder = root:FindFirstChild(folderName)
	if not teamFolder then
		warn("[MorphHandler] Folder morph non trovata:", folderName)
		return false
	end

	local playerRank = getPlayerRankInGroupId(player, groupId)
	local morphGroup = chooseVariant(teamFolder, playerRank, unitName)

	if not morphGroup then
		log("Nessuna variante valida (rank=%d unit=%s) per '%s'.", playerRank, tostring(unitName), folderName)
		return false
	end

	local rigType = getRigType(character)
	for containerName, bodyName in pairs(SUPPORTED_CONTAINERS) do
		tryWeldContainer(character, rigType, morphGroup, playerRank, containerName, bodyName)
	end

	applyClothing(character, morphGroup)
	giveTools(player, morphGroup, playerRank)

	-- Gamepass/supporter tools: sempre, indipendenti dalla morph
	giveOwnedGamepassTools_Server(player)
	giveSupporterTools_Server(player)

	log("Applied morph %s -> variant '%s' (rank=%d unit=%s)", player.Name, morphGroup.Name, playerRank, tostring(unitName))
	return true
end

function MorphHandler.ApplyMorphToPlayer(player, folderName, groupId, unitName)
	if not player or not player.Character then return false end
	return MorphHandler.ApplyMorph(player.Character, folderName, groupId, unitName)
end

-- (player, folderName, groupId, option, isCivilian, isHostile, unitName)
function MorphHandler.ApplyMorphAndTeleport(player, folderName, groupId, option, isCivilian, isHostile, unitName)
	if not player or not player.Character then return false end
	option      = option or 1
	isCivilian  = isCivilian or false
	isHostile   = isHostile or false

	MorphHandler.ApplyMorph(player.Character, folderName, groupId, unitName)

	if isHostile then
		-- Hostile: prova spawn Hostile, fallback Venator
		local node = workspace
		for _, seg in ipairs(SPAWN_ROOT_PATH) do
			node = node:FindFirstChild(seg)
			if not node then break end
		end
		if node and node:FindFirstChild("Hostile") then
			MorphHandler.TeleportPlayer(player, SPAWN_KEYS.Hostile)
		else
			MorphHandler.TeleportPlayerToVenator(player)
		end
	else
		-- Tutti gli altri: spawn su Venator (Spawn1/Spawn2/Spawn3)
		MorphHandler.TeleportPlayerToVenator(player)
	end
end

function MorphHandler.ClearMorph(character)
	if not character then return end
	local player = Players:GetPlayerFromCharacter(character)
	if player then clearMorphTools(player) end
	clearPreviousMorphPieces(character)
end

function MorphHandler.DebugListVariants(player, folderName, groupId)
	local root = getMorphsRoot()
	local teamFolder = root:FindFirstChild(folderName)
	if not teamFolder then
		print("Folder morph non trovata:", folderName)
		return
	end
	local rank = 0
	if player then rank = getPlayerRankInGroupId(player, groupId) end
	print("=== DebugListVariants:", folderName, "PlayerRank:", rank, "GroupId:", groupId, "===")
	local variants = teamFolder:GetChildren()
	for _, v in ipairs(variants) do
		if v:IsA("Folder") or v:IsA("Model") then
			local r = getRankNumberFromInstance(v)
			local u = getUnitNameFromVariant(v)
			print(string.format("  Variant=%s Rank=%s Unit=%s", v.Name, tostring(r), tostring(u)))
		end
	end
	print("=== Fine DebugListVariants ===")
end

-- TELEPORT
local function getSpawnsRoot()
	local node = workspace
	for _, name in ipairs(SPAWN_ROOT_PATH) do
		node = node:FindFirstChild(name)
		if not node then
			warn("[MorphHandler] Spawns root mancante segmento:", name)
			return nil
		end
	end
	return node
end

local function gatherSpawnParts(container)
	if not container then return {} end
	if container:IsA("BasePart") then return {container} end
	local parts = {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	return parts
end

local function pickSpawnPart(node)
	local parts = gatherSpawnParts(node)
	if #parts == 0 then return nil end
	return parts[math.random(1, #parts)]
end

function MorphHandler.TeleportPlayer(player, spawnKey)
	if not player or not player.Character then return false end
	if not SPAWN_KEYS[spawnKey] then
		warn("[MorphHandler] SpawnKey invalida:", tostring(spawnKey))
		return false
	end
	local root = getSpawnsRoot()
	if not root then return false end
	local node = root:FindFirstChild(spawnKey)
	if not node then
		warn("[MorphHandler] Nodo spawn '"..spawnKey.."' non trovato")
		return false
	end
	local part = pickSpawnPart(node)
	if not part then
		warn("[MorphHandler] Nessun BasePart nello spawn '"..spawnKey.."'")
		return false
	end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) then return false end
	hum.Sit = false
	hum.PlatformStand = false
	hrp.CFrame = part.CFrame + Vector3.new(0, SPAWN_Y_OFFSET, 0)
	hrp.AssemblyLinearVelocity  = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	log("Teleported %s to %s", player.Name, spawnKey)
	return true
end

-- Teleport su Venator: scelta random tra Spawn1, Spawn2, Spawn3
function MorphHandler.TeleportPlayerToVenator(player)
	if not player or not player.Character then return false end
	local root = getSpawnsRoot()
	if not root then
		warn("[MorphHandler] Spawns root non trovato per Venator")
		return false
	end
	-- Raccogli tutte le spawn parts dai Venator spawns
	local allParts = {}
	for _, spawnName in ipairs(VENATOR_SPAWN_NAMES) do
		local node = root:FindFirstChild(spawnName)
		if node then
			local parts = gatherSpawnParts(node)
			for _, p in ipairs(parts) do
				table.insert(allParts, p)
			end
		end
	end
	if #allParts == 0 then
		warn("[MorphHandler] Nessun spawn Venator trovato (Spawn1/Spawn2/Spawn3)")
		return false
	end
	local part = allParts[math.random(1, #allParts)]
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) then return false end
	hum.Sit = false
	hum.PlatformStand = false
	hrp.CFrame = part.CFrame + Vector3.new(0, SPAWN_Y_OFFSET, 0)
	hrp.AssemblyLinearVelocity  = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	log("Teleported %s to Venator spawn", player.Name)
	return true
end

MorphHandler.SPAWN_KEYS = SPAWN_KEYS
MorphHandler.VENATOR_SPAWN_NAMES = VENATOR_SPAWN_NAMES

return MorphHandler