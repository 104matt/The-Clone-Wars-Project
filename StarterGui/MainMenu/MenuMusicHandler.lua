local menuGui = script.Parent -- Lo script deve essere dentro la ScreenGui del menu
local music = menuGui:FindFirstChild("MenuMusic")

-- Add these two Sound objects under menuGui (or anywhere under script.Parent)
local hoverSoundTemplate = menuGui:FindFirstChild("HoverSound")
local selectSoundTemplate = menuGui:FindFirstChild("SelectSound")

local fadeTime = 1.5      -- Durata del fade in/out in secondi
local fadeSteps = 30      -- Numero di step del fade
local targetVolume = 0.5  -- Volume massimo della musica (regola come vuoi)

local function fadeIn(sound)
	if not sound then return end
	sound.Volume = 0
	sound:Play()
	for i = 1, fadeSteps do
		sound.Volume = targetVolume * (i / fadeSteps)
		task.wait(fadeTime / fadeSteps)
	end
	sound.Volume = targetVolume
end

local function fadeOut(sound)
	if not sound then return end
	local initialVolume = sound.Volume
	for i = fadeSteps, 1, -1 do
		sound.Volume = initialVolume * (i / fadeSteps)
		task.wait(fadeTime / fadeSteps)
	end
	sound.Volume = 0
	sound:Stop()
end

-- Safely play UI sounds (clone so rapid hovers/clicks don't cut off the sound)
local function playUiSound(soundTemplate)
	if not soundTemplate or not soundTemplate:IsA("Sound") then return end
	local s = soundTemplate:Clone()
	s.Parent = soundTemplate.Parent
	s.Ended:Connect(function()
		s:Destroy()
	end)
	s:Play()
end

-- Connect hover/click to all buttons under menuGui (including nested)
local function hookButton(btn)
	if not btn:IsA("GuiButton") then return end

	-- Hover
	btn.MouseEnter:Connect(function()
		-- optional: only play when menu is visible
		if menuGui.Enabled then
			playUiSound(hoverSoundTemplate)
		end
	end)

	-- Select (mouse/touch click)
	btn.Activated:Connect(function()
		if menuGui.Enabled then
			playUiSound(selectSoundTemplate)
		end
	end)
end

-- Hook existing buttons
for _, d in ipairs(menuGui:GetDescendants()) do
	if d:IsA("GuiButton") then
		hookButton(d)
	end
end

-- Hook buttons added later
menuGui.DescendantAdded:Connect(function(d)
	if d:IsA("GuiButton") then
		hookButton(d)
	end
end)

menuGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if music then
		if menuGui.Enabled then
			if not music.IsPlaying then
				fadeIn(music)
			end
		else
			if music.IsPlaying then
				fadeOut(music)
			end
		end
	end
end)

-- Avvia la musica con fade-in se il menu è inizialmente visibile
if menuGui.Enabled and music and not music.IsPlaying then
	fadeIn(music)
end