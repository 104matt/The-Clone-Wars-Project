-- DroidConfigs.lua
-- All droid type configs indexed by droidType string value on model.
-- Add new types by copying B1Droid block and adjusting values.
return {
	B1Droid = {
		TARGET_TEAM       = "Republic",
		VISION_RANGE      = 250,
		ATTACK_RANGE      = 230,
		MELEE_STOP_RANGE  = 6,
		WALK_SPEED        = 10,
		MAX_HEALTH        = 60,

		WAYPOINT_REACH    = 4,
		REPATH_INTERVAL   = 0.4,

		AGENT_RADIUS      = 3,
		AGENT_HEIGHT      = 5,
		AGENT_CAN_JUMP    = true,
		JUMP_POWER        = 18,
		PF_WAYPOINT_REACH = 5,
		PF_REPATH_TIMEOUT = 1.0,

		FACTION           = "CIS",
		TURN_SPEED        = 6,
		FIRE_ANGLE_DEG    = 25,
		FACING_OFFSET_DEG = 180,

		FIRE_COOLDOWN     = 0.85,
		SPREAD_DEG        = 7,
		DAMAGE            = 4,
		MUZZLE_FLASH_TIME = 0.06,

		HUNT_SEARCH_TIME  = 6,
		DEATH_LINGER      = 5,
		FORMATION_SPACING = 3.5,

		ANIM_IDS = {
			Idle      = 71786808734277,
			Walk      = 116506508382029,
			Shoot     = 71786808734277,
			Death     = 128750172535810,
			DeathIdle = 138596493803688,
		},
	},
	B2Droid = {
		TARGET_TEAM       = "Republic",
		VISION_RANGE      = 120,
		ATTACK_RANGE      = 90,
		MELEE_STOP_RANGE  = 6,
		WALK_SPEED        = 10,
		MAX_HEALTH        = 60,

		WAYPOINT_REACH    = 4,
		REPATH_INTERVAL   = 0.4,

		AGENT_RADIUS      = 3,
		AGENT_HEIGHT      = 5,
		AGENT_CAN_JUMP    = true,
		JUMP_POWER        = 18,
		PF_WAYPOINT_REACH = 5,
		PF_REPATH_TIMEOUT = 1.0,

		FACTION           = "CIS",
		TURN_SPEED        = 6,
		FIRE_ANGLE_DEG    = 25,
		FACING_OFFSET_DEG = 180,

		FIRE_COOLDOWN     = 1,
		SPREAD_DEG        = 5,
		DAMAGE            = 6,
		MUZZLE_FLASH_TIME = 0.06,

		HUNT_SEARCH_TIME  = 6,
		DEATH_LINGER      = 5,
		FORMATION_SPACING = 3.5,

		ANIM_IDS = {
			Idle      = 115814928314982,
			Walk      = 89884636264584,
			Shoot     = 71786808734277,
			Death     = 74088471536291,
			DeathIdle = 131806719224812,
		},
	},
	
	

	-- Droideka = { ... },
}
