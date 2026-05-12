local Settings = {
	-- **There are a lot of things you have to do to setup the menu**
	-- **If you need help contact us on discord: @zoethegamemaker*
	
	-- READ SETUP INSTRUCTIONS: https://docs.google.com/document/d/1cLTnBGScDxi0SR4TMshag5xmNv7RZKvCQoIPd0sZdwk/edit?usp=sharing
	
	
	--~~~~~~~[Main Group Config]~~~~~~~~~~~
	["MainGroup"] = {
		id = 32870033, -- Group ID of the main group
		displayName = "The Galactic Republic", -- Display name of the main group
		teamName = "Republic", -- Team name of the main group (Case sensitive)
		mainTeamOverName = "REPUBLIC", -- The name of the groups assosiated with the main group (All caps is recommended)
		Image = 83622990862252, -- Image ID for the main group
		Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 255))
		};
	};
	
	
	["CivilianGroup"] = {
		everyoneCanJoin = false; -- True = All players can join / False = Only players who are not in the main group can join
		displayName = "Civilian", -- Display name of civilian group
		teamName = "Civilian", -- Team name of the civilian group (Case sensitive)
		civilianImageID = 0, -- Image ID for the civilian class. !!! Leaving it at 0 will display a blue gradient !!!
		FriendlyNonTeamOverName = "CIVILIAN", -- The overarching term for the civilian team
		Image = 83622990862252, -- Image ID for the main group
		Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
		};
	};
	
	["HostileGroup"] = {
		everyoneCanJoin = true; -- True = All players can join / False = Only players who are not in the main group can join
		displayName = "Hostile", -- Display name of civilian group
		teamName = "Raider", -- Team name of the civilian group (Case sensitive)
		civilianImageID = 0, -- Image ID for the civilian class. !!! Leaving it at 0 will display a blue gradient !!!
		FriendlyNonTeamOverName = "HOSTILES", -- The overarching term for the civilian team
		Image = 83622990862252, -- Image ID for the main group
		Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 0, 0))
		};
	};
	
	--~~~~~~~[Divisional Group Setups]~~~~~~~~~~~
	["DivisionalGroups"] = {
		
		["501st Legion"] = { -- Name this whatever you want
			id = 208329432, -- Group ID of the main group
			displayName = "501st Legion", -- Display name of the main group
			teamName = "Republic", -- Team name of the this group (Case sensitive)
			friendly = true, -- Is team friendly with the main group?
			Image = 81929201655010, 
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 85, 255))
			};
		};
		["Coruscant Guard"] = { -- Name this whatever you want
			id = 207431414, -- Group ID of the main group
			displayName = "Coruscant Guard", -- Display name of the main group
			teamName = "Republic", -- Team name of the this group (Case sensitive)
			friendly = true,
			Image = 103903597904818, -- Is team friendly with the main group?
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(132, 0, 2))
			};
		};
		["Red Guard"] = { -- Name this whatever you want
			id = 499679524, -- Group ID of the main group
			displayName = "Red Guard", -- Display name of the main group
			teamName = "Republic", -- Team name of the this group (Case sensitive)
			friendly = true,
			Image = 117586727977068, -- Is team friendly with the main group?
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(186, 57, 59))
			};
		};
		["212th Attack Battalion"] = { -- Name this whatever you want
			id = 1027256856, -- Group ID of the main group
			displayName = "212th Attack Battalion", -- Display name of the main group
			teamName = "Republic", -- Team name of the this group (Case sensitive)
			friendly = true,
			Image =  82086737621689, -- Is team friendly with the main group?
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 85, 0))
			};
		};
	};
	
	--~~~~~~~[Gamepass Class Setups]~~~~~~~~~~~
	["Gamepasses"] = {
		["B1 Raider"] = { -- Name this whatever you want
			GamepassId = 1452348706, -- Gamepass ID required to spawn as this class
			displayName = "B1 Raider", -- Display name of the main group
			customImageID = 0, -- Add a custom image for this gamepass | Leaving it 0 will use the gamepass image
			teamName = "Raider", -- Team name of the this group (Case sensitive)
			friendly = false; -- Is team friendly with the main group?
			
		};
	};
	
	
	--~~~~~~~~~~~~~~~~~[Menu Configurations]~~~~~~~~~~~~~~~~~~~~
	
	--~~~~~~~[Shop]~~~~~~~~~~~
	["GamepassItems"] = {

		["DH17"] = { -- Name this whatever you want
			GamepassId = 1279011849, -- Gamepass ID required to spawn as this class
			Title = "[PISTOL!] DH17", -- Display name of the main group
			Description = "Another rebel-style pistol used mostly in the outer rim. A very powerful automatice side-weapon.", -- Team name of the this group (Case sensitive)
			Price = 199,
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 93, 255))
			}
		};
		["A280C"] = { -- Name this whatever you want
			GamepassId = 1278105056, -- Gamepass ID required to spawn as this class
			Title = "[BLASTER!] A280C", -- Display name of the main group
			Description = "A powerfull rebel-style blaster issued to ARF troopers and rebel forces.", -- Team name of the this group (Case sensitive)
			Price = 399,
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 229, 57))
			}
		};
		["DC15X"] = { -- Name this whatever you want
			GamepassId = 1316765035, -- Gamepass ID required to spawn as this class
			Title = "[🎯SNIPER!] DC15X", -- Display name of the main group
			Description = "Perfect for taking out targets from afar. Press X to activate the scope!", -- Team name of the this group (Case sensitive)
			Price = 599,
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 234))
			}
		};
		["Z6"] = { -- Name this whatever you want
			GamepassId = 1277489615, -- Gamepass ID required to spawn as this class
			Title = "[MINIGUN!] Z6 ROTARY BLASTER", -- Display name of the main group
			Description = "A mass destruction weapon issued only to the most strong and skilled trooper. It can shoot to 10 beams per second.", -- Team name of the this group (Case sensitive)
			Price = 799,
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
			}
		};
		["Cloak"] = { -- Name this whatever you want
			GamepassId = 1278884013, -- Gamepass ID required to spawn as this class
			Title = "[INVISIBILITY!] CLOAK", -- Display name of the main group
			Description = "The invisibility cloak makes you almost invisibile, run super fast but it lowers your HPs to 25 so BE CAREFUL!", -- Team name of the this group (Case sensitive)
			Price = 299,
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(147, 0, 220))
			}
		};
		["Boombox"] = { -- Name this whatever you want
			GamepassId = 1346814850, -- Gamepass ID required to spawn as this class
			Title = "[🎶MUSIC] BOOMBOX", -- Display name of the main group
			Description = "The boombox allowes you to play music in game as much as you want!", -- Team name of the this group (Case sensitive)
			Price = 59,
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(208, 170, 46))
			}
		};
	};
	
	--~~~~~~~[Credits]~~~~~~~~~~~
	["Credits"] = {
		["boolymat"] = "Main Developer (GFX, Backend and Frontend, Building)", -- Username | Role
		["Max1Boom"] = "Developer (Animations, Building & Backend)",
	};
}

return Settings
