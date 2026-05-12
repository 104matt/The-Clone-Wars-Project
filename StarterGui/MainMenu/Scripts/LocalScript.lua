-- LocalScript.lua (Versione 3.0 – Zombie Attack Style)
-- FLOW: Home -> Play -> Scelta Reggimento -> Morph+Spawn -> Voto Mappa -> Teleport
-- RIMOSSI: ChooseLocation, ChooseUnit, CivilianGroup, HostileGroup
-- AGGIUNTI: Lucchetti sui reggimenti, GameSelect UI con voto mappe

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService       = game:GetService("GroupService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Durate
local SCREEN_FADE_OUT_TIME = 0.35
local SCREEN_FADE_IN_TIME  = 0.60
local POST_REMOTE_DELAY    = 0.10
local DEBUG = true
local function dprint(...) if DEBUG then print("[MainMenuClient]", ...) end end

-- UI base
local MainMenu      = script.Parent.Parent
local Home          = MainMenu:WaitForChild("Home")
local Play          = MainMenu:WaitForChild("Play")
local Credits       = MainMenu:WaitForChild("Credits")
local Shop          = MainMenu:WaitForChild("Shop")
local SettingsFrame = MainMenu:WaitForChild("Settings")
-- Flow frames
local GameSelectUI = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("GameSelectUI")
local GameSelect   = GameSelectUI:WaitForChild("GameSelect")

local GameSelectMainFrame = GameSelect:WaitForChild("MainFrame")
local MapTemplate         = GameSelectMainFrame:WaitForChild("MapTemplate")
MapTemplate.Visible = false
GameSelectUI.Enabled = false
GameSelect.Visible = true

-- Camera
local Camera = workspace.CurrentCamera
local CustomPart = workspace:WaitForChild("MainMenuWorkspace")
	:WaitForChild("Camera")
	:WaitForChild("MainCamera")

local function setCameraToCustomPart()
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame     = CustomPart.CFrame
end
local function resetCameraToPlayer()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if hum then
		Camera.CameraType    = Enum.CameraType.Custom
		Camera.CameraSubject = hum
	end
end

-- Settings
local SettingsModule
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("MainMenuRP"):WaitForChild("Settings"))
	end)
	if not ok then
		local gc = ReplicatedStorage:FindFirstChild("group_config")
		if gc then
			local ok2, mod2 = pcall(function() return require(gc) end)
			if ok2 then SettingsModule = mod2 end
		end
	else
		SettingsModule = mod
	end
end
if not SettingsModule then
	warn("[MainMenuClient] SettingsModule non trovato. Stop.")
	return
end

-- Remotes
local RemotesRoot        = ReplicatedStorage:WaitForChild("MainMenuRP"):WaitForChild("Remotes")
local RemoteMorphPlr     = RemotesRoot:WaitForChild("MorphPlr")
local RemoteMorphPlrG    = RemotesRoot:WaitForChild("MorphPlrG")

-- Voting remotes
local VoteMapRE     = RemotesRoot:WaitForChild("VoteMap")
local VoteUpdateRE  = RemotesRoot:WaitForChild("VoteUpdate")
local StartVotingRE = RemotesRoot:WaitForChild("StartVoting")
local MapSelectedRE = RemotesRoot:WaitForChild("MapSelected")

------------------------------------------------------------
-- Utils grafica / dati
------------------------------------------------------------
local function normalizeToColorSequence(source)
	if not source then return nil end
	local t = typeof(source)
	if t == "ColorSequence" then
		return source
	elseif t == "Color3" then
		return ColorSequence.new(source)
	elseif t == "table" then
		local r = source.R or source.r
		local g = source.G or source.g
		local b = source.B or source.b
		if r and g and b then
			return ColorSequence.new(Color3.fromRGB(r,g,b))
		end
		if source.Keypoints then
			local ok, seq = pcall(function() return ColorSequence.new(source.Keypoints) end)
			if ok then return seq end
		end
	elseif t == "string" then
		local hex = source:match("^#(%x%x%x%x%x%x)$")
		if hex then
			return ColorSequence.new(Color3.fromRGB(
				tonumber(hex:sub(1,2),16),
				tonumber(hex:sub(3,4),16),
				tonumber(hex:sub(5,6),16)
				))
		end
	end
	return nil
end

local function applyGradientColor(templateClone, colorSource)
	local seq = normalizeToColorSequence(colorSource)
	if not seq then return end
	local gradient = templateClone:FindFirstChild("TeamGradient", true)
	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = seq
	end
end

local function getPreferredImageId(entry)
	if not entry then return nil end
	return entry.Image or entry.image or entry.ImageId or entry.imageId or entry.ImageID or entry.customImageID or entry.icon
end

local function setDivImage(templateClone, imageIdOrUrl)
	if not imageIdOrUrl then return end
	local divImage = templateClone:FindFirstChild("DivImage", true)
	if not divImage or not divImage:IsA("ImageLabel") then return end
	if tostring(imageIdOrUrl):match("^https?://") then
		divImage.Image = imageIdOrUrl
	else
		local numeric = tonumber(imageIdOrUrl)
		if numeric then
			divImage.Image = "rbxassetid://" .. numeric
		elseif tostring(imageIdOrUrl):match("^rbxassetid://") then
			divImage.Image = imageIdOrUrl
		end
	end
end

------------------------------------------------------------
-- Selection controller (scaling immediato + eventuale stroke)
------------------------------------------------------------
local function setStrokeColor(button, color)
	if not button then return end
	local stroke = button:FindFirstChildWhichIsA("UIStroke", true)
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = button
	end
	stroke.Color = color
end

local function createSelectionController(buttons, options)
	options = options or {}
	local current
	local strokeInactive = options.strokeInactive or Color3.fromRGB(130,130,130)
	local strokeActive   = options.strokeActive   or Color3.new(1,1,1)
	local scale          = options.scale or 1.08
	local useStroke      = options.useStroke
	local origSizes = {}

	for _, b in ipairs(buttons) do
		origSizes[b] = b.Size
		if useStroke then
			setStrokeColor(b, strokeInactive)
		end
	end

	local function apply(btn, selected)
		local base = origSizes[btn]
		if not base then return end
		if selected then
			btn.Size = UDim2.new(base.X.Scale * scale, base.X.Offset, base.Y.Scale * scale, base.Y.Offset)
			if useStroke then setStrokeColor(btn, strokeActive) end
		else
			btn.Size = base
			if useStroke then setStrokeColor(btn, strokeInactive) end
		end
	end

	local function setSelected(btn)
		if current == btn then return end
		for _, b in ipairs(buttons) do
			apply(b, b == btn)
		end
		current = btn
		return btn
	end

	return setSelected
end

------------------------------------------------------------
-- Black screen transition
------------------------------------------------------------
local TransitionGui, BlackFrame
local function ensureTransitionGui()
	if TransitionGui and TransitionGui.Parent then return end
	local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
	TransitionGui = pg:FindFirstChild("TransitionGui")
	if not TransitionGui then
		TransitionGui = Instance.new("ScreenGui")
		TransitionGui.Name = "TransitionGui"
		TransitionGui.DisplayOrder = 9999
		TransitionGui.IgnoreGuiInset = true
		TransitionGui.ResetOnSpawn = false
		TransitionGui.Parent = pg
	end
	BlackFrame = TransitionGui:FindFirstChild("BlackFade")
	if not BlackFrame then
		BlackFrame = Instance.new("Frame")
		BlackFrame.Name = "BlackFade"
		BlackFrame.Size = UDim2.new(1,0,1,0)
		BlackFrame.BackgroundColor3 = Color3.new(0,0,0)
		BlackFrame.BackgroundTransparency = 1
		BlackFrame.ZIndex = 10
		BlackFrame.Parent = TransitionGui
	end
end

local function tweenBlack(from, to, dur)
	ensureTransitionGui()
	BlackFrame.BackgroundTransparency = from
	local tw = TweenService:Create(
		BlackFrame,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = to}
	)
	tw:Play()
	return tw
end

local function fadeScreenAndSpawn(remoteCall)
	local outTw = tweenBlack(1,0,SCREEN_FADE_OUT_TIME)
	outTw.Completed:Wait()
	remoteCall()
	task.wait(POST_REMOTE_DELAY)
	resetCameraToPlayer()
	MainMenu.Enabled = false
	local inTw = tweenBlack(0,1,SCREEN_FADE_IN_TIME)
	inTw.Completed:Wait()
end

------------------------------------------------------------
-- Panel visibility
------------------------------------------------------------
local function showPanel(target)
	Play.Visible          = (target == Play)
	Credits.Visible       = (target == Credits)
	Shop.Visible          = (target == Shop)
	SettingsFrame.Visible = (target == SettingsFrame)
	if target then setCameraToCustomPart() end
end

-- Home buttons
local homeButtons = { Home.Play, Home.Credits, Home.Shop, Home.Settings }
local selectHomeButton = createSelectionController(homeButtons, {
	scale=1.10, useStroke=false
})
Home.Play.MouseButton1Click:Connect(function() 
	showPanel(Play); 
	selectHomeButton(Home.Play) 
end)
Home.Credits.MouseButton1Click:Connect(function() 
	showPanel(Credits); 
	selectHomeButton(Home.Credits) 
end)
Home.Shop.MouseButton1Click:Connect(function() 
	showPanel(Shop); 
	selectHomeButton(Home.Shop) 
end)
Home.Settings.MouseButton1Click:Connect(function() 
	showPanel(SettingsFrame); 
	selectHomeButton(Home.Settings) 
end)

-- Play tabs
local playTabs = { Play.Gamepasses, Play.Teams }
local selectPlayTab = createSelectionController(playTabs, {
	scale=1.10, useStroke=true,
	strokeInactive=Color3.fromRGB(120,120,120),
	strokeActive=Color3.fromRGB(255,255,255)
})
Play.Gamepasses.MouseButton1Click:Connect(function()
	Play.GamepassesFrame.Visible = true
	Play.TeamsFrame.Visible      = false
	selectPlayTab(Play.Gamepasses)
	setCameraToCustomPart()
end)
Play.Teams.MouseButton1Click:Connect(function()
	Play.GamepassesFrame.Visible = false
	Play.TeamsFrame.Visible      = true
	selectPlayTab(Play.Teams)
	setCameraToCustomPart()
end)
Play.GamepassesFrame.Visible = false
Play.TeamsFrame.Visible      = true

------------------------------------------------------------
-- Credits population
------------------------------------------------------------
do
	local template = Credits:WaitForChild("GamepassesFrame"):WaitForChild("Template")
	for username, role in pairs(SettingsModule.Credits or {}) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent  = template.Parent
		clone.Text    = "@"..username.." - "..role
	end
end

------------------------------------------------------------
-- Shop Gamepasses display
------------------------------------------------------------
do
	local template = Shop.GamepassesFrame:WaitForChild("Template")
	for name, item in pairs(SettingsModule.GamepassItems or {}) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent  = template.Parent
		clone.GTitle.Text = item.Title or name
		clone.GDesc.Text  = item.Description or "N/A"
		clone.GPrice.Text = "R$ " .. tostring(item.Price or 0)
		if clone:FindFirstChild("UIGradient") then
			local seq = normalizeToColorSequence(item.Color)
			if seq then clone.UIGradient.Color = seq end
		end
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(item.GamepassId, Enum.InfoType.GamePass)
		end)
		if success and info then
			clone.GImage.Image = "rbxassetid://"..tostring(info.IconImageAssetId)
		else
			clone.GImage.Image = "rbxassetid://0"
		end
		clone.MouseButton1Click:Connect(function()
			MarketplaceService:PromptGamePassPurchase(LocalPlayer, item.GamepassId)
		end)
	end
end

-- Group icon util
local function safeGetGroupIcon(groupId)
	if type(groupId) ~= "number" then return nil end
	local ok, info = pcall(function() return GroupService:GetGroupInfoAsync(groupId) end)
	if ok and info and info.EmblemUrl then
		return info.EmblemUrl
	end
	return nil
end

------------------------------------------------------------
-- Helpers click
------------------------------------------------------------
local clickDebounce = false
local function withDebounce(fn)
	return function(...)
		if clickDebounce then return end
		clickDebounce = true
		local ok, err = pcall(fn, ...)
		if not ok then warn("[MainMenuClient] Handler error:", err) end
		task.delay(0.25, function() clickDebounce=false end)
	end
end

------------------------------------------------------------
-- Lock overlay per reggimenti bloccati
------------------------------------------------------------
local function addLockOverlay(button)
	-- Icona lucchetto sopra il pulsante
	local lock = button:FindFirstChild("LockOverlay")
	if lock then return end -- già presente

	lock = Instance.new("ImageLabel")
	lock.Name = "LockOverlay"
	lock.Size = UDim2.new(0, 40, 0, 40)
	lock.Position = UDim2.new(0.5, -20, 0.5, -20)
	lock.BackgroundTransparency = 1
	lock.Image = "rbxassetid://6031071053" -- icona lucchetto standard Roblox
	lock.ImageColor3 = Color3.fromRGB(200, 200, 200)
	lock.ZIndex = button.ZIndex + 10
	lock.Parent = button

	-- Overlay scuro semi-trasparente
	local overlay = Instance.new("Frame")
	overlay.Name = "LockDarkOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex = button.ZIndex + 5
	overlay.Parent = button

	-- Copia UICorner se presente
	local corner = button:FindFirstChildWhichIsA("UICorner")
	if corner then
		local c2 = corner:Clone()
		c2.Parent = overlay
	end
end

------------------------------------------------------------
-- Create team button con supporto lucchetto
------------------------------------------------------------
local function createTeamButton(parentFrame, overName, displayName, settingsEntry, onClick, locked)
	local template = parentFrame:WaitForChild("Template")
	local clone    = template:Clone()
	clone.Visible  = true
	clone.Parent   = parentFrame
	clone.OverLbl.Text      = overName or "REGIMENT"
	clone.DisplayName.Text  = displayName

	local explicitImage = getPreferredImageId(settingsEntry)
	if not explicitImage and settingsEntry and settingsEntry.id then
		explicitImage = safeGetGroupIcon(settingsEntry.id)
	end
	setDivImage(clone, explicitImage)

	if settingsEntry and settingsEntry.Color then
		applyGradientColor(clone, settingsEntry.Color)
	end

	if locked then
		-- Mostra lucchetto, non cliccabile
		addLockOverlay(clone)
		clone.MouseButton1Click:Connect(function()
			-- Non fa niente – bloccato
		end)
	else
		clone.MouseButton1Click:Connect(withDebounce(function()
			onClick(clone)
		end))
	end
end

------------------------------------------------------------
-- Team selection (NUOVO: tutti visibili, lucchetto se non nel gruppo)
------------------------------------------------------------
local teamsFrame = Play:WaitForChild("TeamsFrame")
teamsFrame.Visible = true

-- MainGroup: SEMPRE cliccabile da tutti (clone standard)
do
	local mg = SettingsModule.MainGroup
	if mg then
		createTeamButton(
			teamsFrame,
			mg.mainTeamOverName or mg.teamName,
			mg.displayName,
			mg,
			function()
				teamsFrame.Visible = false
				Play.Gamepasses.Visible      = false
				Play.Teams.Visible           = false
				Play.GamepassesFrame.Visible = false
				Play.TeamsFrame.Visible      = false
				fadeScreenAndSpawn(function()
					RemoteMorphPlr:FireServer(mg.displayName, 1)
				end)
			end,
			false -- mai bloccato
		)
	end
end

-- DivisionalGroups: visibili a TUTTI, bloccati se non nel gruppo
do
	for _, div in pairs(SettingsModule.DivisionalGroups or {}) do
		local isInGroup = false
		if div.id then
			local ok, result = pcall(function() return LocalPlayer:IsInGroup(div.id) end)
			if ok then isInGroup = result end
		end

		createTeamButton(
			teamsFrame,
			div.friendly and (SettingsModule.MainGroup and SettingsModule.MainGroup.mainTeamOverName or "ALLY") or "REGIMENT",
			div.displayName,
			div,
			function()
				teamsFrame.Visible = false
				Play.Gamepasses.Visible      = false
				Play.Teams.Visible           = false
				Play.GamepassesFrame.Visible = false
				Play.TeamsFrame.Visible      = false
				fadeScreenAndSpawn(function()
					RemoteMorphPlr:FireServer(div.displayName, 1)
				end)
			end,
			not isInGroup -- bloccato se NON è nel gruppo
		)
	end
end

-- Gamepasses: visibili a TUTTI
do
	local gpFrame = Play:WaitForChild("GamepassesFrame")
	for _, gp in pairs(SettingsModule.Gamepasses or {}) do
		createTeamButton(
			gpFrame,
			gp.friendly and (SettingsModule.MainGroup and SettingsModule.MainGroup.mainTeamOverName or "ALLY") or "SPECIAL",
			gp.displayName,
			gp,
			function()
				local owns = false
				pcall(function()
					owns = MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, gp.GamepassId)
				end)
				teamsFrame.Visible = false
				Play.Gamepasses.Visible      = false
				Play.Teams.Visible           = false
				Play.GamepassesFrame.Visible = false
				Play.TeamsFrame.Visible      = false
				if owns then
					fadeScreenAndSpawn(function()
						RemoteMorphPlrG:FireServer(gp.displayName)
					end)
				else
					MarketplaceService:PromptGamePassPurchase(LocalPlayer, gp.GamepassId)
				end
			end,
			false -- mai bloccato, tutti possono cliccare
		)
	end
end

------------------------------------------------------------
-- GameSelect: Map Voting UI
------------------------------------------------------------
local mapButtons = {} -- mapIndex -> button clone
local currentVote = nil
local votingCountdownConn = nil

local function clearMapButtons()
	for _, btn in pairs(mapButtons) do
		if btn and btn.Parent then btn:Destroy() end
	end
	mapButtons = {}
	currentVote = nil
end

local function updateVoteCounts(counts)
	for i, btn in pairs(mapButtons) do
		local votesLabel = btn:FindFirstChild("MapVotes")
		if votesLabel and votesLabel:IsA("TextLabel") then
			votesLabel.Text = tostring(counts[i] or 0)
		end
	end
end

local function highlightSelectedMap(selectedIndex)
	for i, btn in pairs(mapButtons) do
		local stroke = btn:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			if i == selectedIndex then
				stroke.Color = Color3.fromRGB(0, 170, 255)
				stroke.Thickness = 3
			else
				stroke.Color = Color3.fromRGB(100, 100, 100)
				stroke.Thickness = 1
			end
		end
	end
end

local function showGameSelect(mapList, duration)
	dprint("Mostra GameSelect, durata:", duration)
	clearMapButtons()
	GameSelectUI.Enabled = true
	GameSelect.Visible = true

	-- Crea un pulsante per ogni mappa
	for _, mapData in ipairs(mapList) do
		local clone = MapTemplate:Clone()
		clone.Visible = true
		clone.Parent = GameSelectMainFrame

		local nameLabel = clone:FindFirstChild("MapName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = mapData.name
		end

		local thumbnail = clone:FindFirstChild("MapThumbnail")
		if thumbnail and thumbnail:IsA("ImageLabel") then
			thumbnail.Image = mapData.imageId or "rbxassetid://0"
		end

		local votesLabel = clone:FindFirstChild("MapVotes")
		if votesLabel and votesLabel:IsA("TextLabel") then
			votesLabel.Text = "0"
		end

		local idx = mapData.index
		clone.MouseButton1Click:Connect(function()
			if currentVote == idx then return end
			currentVote = idx
			VoteMapRE:FireServer(idx)
			highlightSelectedMap(idx)
			dprint("Votato per:", mapData.name)
		end)

		mapButtons[idx] = clone
	end

	-- Countdown (opzionale: puoi aggiungere un TextLabel per il timer)
	if votingCountdownConn then
		votingCountdownConn:Disconnect()
		votingCountdownConn = nil
	end

	local endTime = os.clock() + duration
	-- Se esiste un TimerLabel nel GameSelect, aggiornalo
	local timerLabel = GameSelect:FindFirstChild("TimerLabel", true)
	if timerLabel and timerLabel:IsA("TextLabel") then
		votingCountdownConn = RunService.RenderStepped:Connect(function()
			local remaining = math.max(0, math.ceil(endTime - os.clock()))
			timerLabel.Text = tostring(remaining) .. "s"
			if remaining <= 0 and votingCountdownConn then
				votingCountdownConn:Disconnect()
				votingCountdownConn = nil
			end
		end)
	end
end

-- Ricevi inizio voting dal server
StartVotingRE.OnClientEvent:Connect(function(mapList, duration)
	dprint("Ricevuto StartVoting dal server, mappe:", #mapList, "durata:", duration)
	showGameSelect(mapList, duration)
end)

-- Ricevi aggiornamento voti dal server
VoteUpdateRE.OnClientEvent:Connect(function(counts)
	dprint("Ricevuto VoteUpdate dal server")
	if type(counts) == "table" then
		updateVoteCounts(counts)
	end
end)

-- Ricevi mappa selezionata
MapSelectedRE.OnClientEvent:Connect(function(mapName, placeId)
	dprint("Ricevuto MapSelected dal server:", mapName, placeId)
	-- Evidenzia la mappa vincente
	for i, btn in pairs(mapButtons) do
		local nameLabel = btn:FindFirstChild("MapName")
		if nameLabel and nameLabel:IsA("TextLabel") and nameLabel.Text == mapName then
			local stroke = btn:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = Color3.fromRGB(0, 255, 0)
				stroke.Thickness = 4
			end
		end
	end

	-- Disabilita interazione
	if votingCountdownConn then
		votingCountdownConn:Disconnect()
		votingCountdownConn = nil
	end

	-- Il teleport avviene dal server, il client mostra solo il feedback
	local timerLabel = GameSelect:FindFirstChild("TimerLabel", true)
	if timerLabel and timerLabel:IsA("TextLabel") then
		timerLabel.Text = "Teleporting to " .. mapName .. "..."
	end
end)

------------------------------------------------------------
-- Camera setup iniziale
------------------------------------------------------------
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
if playerGui:GetAttribute("LoadedOnce") == false then
	_G.firstJoin = true
end
print(_G.SetCamera)
print(_G.firstJoin)
if _G.firstJoin or _G.SetCamera then
	_G.firstJoin = false
	setCameraToCustomPart()
end
print(_G.firstJoin)

MainMenu:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not MainMenu.Enabled then
		resetCameraToPlayer()
	end
end)