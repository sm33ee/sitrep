-- SITREP · Data
-- Doctrine tables. Every number here is a default the player can retune in the
-- console; they encode level-60 matchups, not measurements.

local ADDON, ns = ...
local D = {}
ns.Data = D

D.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
D.SHORT = {
	WARRIOR = "WAR", PALADIN = "PAL", HUNTER = "HUN", ROGUE = "ROG", PRIEST = "PRI",
	SHAMAN = "SHA", MAGE = "MAG", WARLOCK = "WLK", DRUID = "DRU",
}
D.NAME = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- Fallback colours if RAID_CLASS_COLORS is missing.
D.COLOR = {
	WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
	ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
	MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1.00, 0.49, 0.04 },
}

function D.ClassColor(class)
	local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	c = D.COLOR[class]
	if c then return c[1], c[2], c[3] end
	return 0.7, 0.7, 0.7
end

-- Raw combat power of a class in a mixed group fight (1.0 = baseline).
D.POWER = {
	WARRIOR = 1.00, PALADIN = 0.95, HUNTER = 1.00, ROGUE = 1.05, PRIEST = 1.00,
	SHAMAN = 1.00, MAGE = 1.05, WARLOCK = 1.05, DRUID = 0.95,
}

-- MATRIX[me][them]: how much more dangerous "them" is to "me" than an average
-- opponent. Rows are the defender. Kiting casters punish melee without gap closers,
-- warlocks shut rogues down, rogues open on cloth, and so on.
D.MATRIX = {
	WARRIOR = { WARRIOR = 1.00, PALADIN = 1.05, HUNTER = 1.20, ROGUE = 1.10, PRIEST = 1.10, SHAMAN = 1.10, MAGE = 1.35, WARLOCK = 1.25, DRUID = 1.15 },
	PALADIN = { WARRIOR = 0.95, PALADIN = 1.00, HUNTER = 1.00, ROGUE = 0.90, PRIEST = 0.95, SHAMAN = 1.05, MAGE = 1.05, WARLOCK = 1.10, DRUID = 0.90 },
	HUNTER  = { WARRIOR = 0.90, PALADIN = 1.05, HUNTER = 1.00, ROGUE = 1.20, PRIEST = 1.00, SHAMAN = 1.10, MAGE = 1.10, WARLOCK = 1.10, DRUID = 1.05 },
	ROGUE   = { WARRIOR = 1.05, PALADIN = 1.15, HUNTER = 1.00, ROGUE = 1.00, PRIEST = 1.15, SHAMAN = 1.05, MAGE = 1.00, WARLOCK = 1.25, DRUID = 1.05 },
	PRIEST  = { WARRIOR = 1.05, PALADIN = 1.00, HUNTER = 1.05, ROGUE = 1.15, PRIEST = 1.00, SHAMAN = 1.00, MAGE = 1.05, WARLOCK = 1.10, DRUID = 0.95 },
	SHAMAN  = { WARRIOR = 1.00, PALADIN = 1.00, HUNTER = 1.00, ROGUE = 1.05, PRIEST = 1.05, SHAMAN = 1.00, MAGE = 1.10, WARLOCK = 1.10, DRUID = 1.00 },
	MAGE    = { WARRIOR = 0.85, PALADIN = 1.00, HUNTER = 1.15, ROGUE = 1.20, PRIEST = 1.10, SHAMAN = 1.10, MAGE = 1.00, WARLOCK = 1.15, DRUID = 1.05 },
	WARLOCK = { WARRIOR = 0.90, PALADIN = 1.00, HUNTER = 1.10, ROGUE = 0.80, PRIEST = 1.10, SHAMAN = 1.05, MAGE = 1.05, WARLOCK = 1.00, DRUID = 1.10 },
	DRUID   = { WARRIOR = 1.00, PALADIN = 1.05, HUNTER = 1.05, ROGUE = 1.05, PRIEST = 1.05, SHAMAN = 1.00, MAGE = 1.00, WARLOCK = 1.00, DRUID = 1.00 },
}

-- High-value-target worth: what killing this class removes from the enemy force.
-- Healers first, then force multipliers, then damage.
D.HVT = {
	PRIEST = 1.50, SHAMAN = 1.35, PALADIN = 1.30, DRUID = 1.25, MAGE = 1.20,
	WARLOCK = 1.15, HUNTER = 1.00, WARRIOR = 1.00, ROGUE = 0.85,
}

-- How quickly the class goes down under focus fire (armour and escape tools).
D.EXPOSURE = {
	PRIEST = 1.25, MAGE = 1.20, WARLOCK = 1.20, DRUID = 1.00, ROGUE = 1.00,
	HUNTER = 1.00, SHAMAN = 1.00, PALADIN = 0.80, WARRIOR = 0.85,
}

-- Weapon engagement zones: how far each class can hurt you (yards, level cap).
-- reach = sustained damage range; threat = the distance at which it becomes
-- dangerous, counting gap closers and control (a warrior inside 25 yd can Charge).
D.REACH = {
	WARRIOR = { reach = 5,  threat = 25, note = "Charge / Intercept from 8-25 yd" },
	ROGUE   = { reach = 5,  threat = 8,  note = "melee; Sprint and stealth openers" },
	PALADIN = { reach = 5,  threat = 10, note = "Hammer of Justice at 10 yd" },
	HUNTER  = { reach = 35, threat = 35, note = "shots 8-35 yd; dead zone inside 8" },
	MAGE    = { reach = 30, threat = 30, note = "Frost Nova at 10, Fire Blast at 20" },
	WARLOCK = { reach = 30, threat = 30, note = "Fear at 20, DoTs at 30" },
	PRIEST  = { reach = 30, threat = 30, note = "Psychic Scream at 8" },
	SHAMAN  = { reach = 30, threat = 30, note = "Earth Shock at 20" },
	DRUID   = { reach = 30, threat = 30, note = "casters 30; cat and bear melee" },
}
D.REACH_DEFAULT = { reach = 30, threat = 30, note = "unknown class" }

-- Finishers that only work below a health threshold: marked on the target's bar.
D.EXECUTE = {
	WARRIOR = { pct = 20, short = "EXECUTE" },
	PALADIN = { pct = 20, short = "WRATH" },
}

-- Accent themes for the HUD and console.
D.ACCENTS = {
	nvg     = { name = "Night Vision", 0.36, 1.00, 0.55 },
	amber   = { name = "Amber CRT",    1.00, 0.72, 0.20 },
	arctic  = { name = "Arctic",       0.40, 0.85, 1.00 },
	crimson = { name = "Crimson",      1.00, 0.33, 0.33 },
	ghost   = { name = "Ghost",        0.85, 0.87, 0.90 },
}
D.ACCENT_ORDER = { "nvg", "amber", "arctic", "crimson", "ghost" }

-- Advice states, strongest to weakest, with their colours.
D.ADVICE = {
	CLEAR   = { text = "CLEAR",   0.55, 0.60, 0.62 },
	ENGAGE  = { text = "ENGAGE",  0.36, 1.00, 0.55 },
	CONTEST = { text = "CONTEST", 1.00, 0.85, 0.30 },
	HOLD    = { text = "HOLD",    1.00, 0.55, 0.20 },
	BREAK   = { text = "BREAK",   1.00, 0.30, 0.30 },
	DEFEND  = { text = "DEFEND",  1.00, 0.20, 0.55 },
}

-- Buffs that raise a player's maximum health (Sensors: toughness). stam: stamina
-- (10 health each), hp: health, pct: a share of the whole. The averages are learned
-- without them; a player who has them counts as tougher in the fight, as he is.
D.HEALTH_BUFFS = {
	[1243] = { stam = 3 }, [1244] = { stam = 8 }, [1245] = { stam = 20 }, [2791] = { stam = 32 },   -- Power Word: Fortitude
	[10937] = { stam = 43 }, [10938] = { stam = 54 }, [21562] = { stam = 43 }, [21564] = { stam = 54 }, -- (and Prayer of Fortitude)
	[5232] = { stam = 2 }, [6756] = { stam = 4 }, [5234] = { stam = 6 }, [8907] = { stam = 8 },          -- Mark of the Wild
	[9884] = { stam = 10 }, [9885] = { stam = 12 }, [21849] = { stam = 10 }, [21850] = { stam = 12 },   -- (and Gift of the Wild)
	[6307] = { stam = 3 }, [7804] = { stam = 9 }, [7805] = { stam = 21 }, [11766] = { stam = 30 }, [11767] = { stam = 42 }, -- Blood Pact
	[3593] = { hp = 120 },        -- Elixir of Fortitude
	[25804] = { stam = 15 },      -- Rumsey Rum Black Label
	[15366] = { stam = 15 },      -- Songflower Serenade
	[24425] = { pct = 0.15 },     -- Spirit of Zandalar
	[22818] = { pct = 0.15 },     -- Mol'dar's Moxie
	[23725] = { pct = 0.15 },     -- Lifegiving Gem
	[12975] = { pct = 0.30 },     -- Last Stand
}

-- Racials that raise maximum health (by the race's file name): its factor.
D.HEALTH_RACIAL = { Tauren = 1.05 } -- Endurance

-- Interrupts (Incoming.lua: kick trainer, lockouts): the first rank's spell ID (its
-- name covers every rank), how long the school stays locked, the cooldown.
D.INTERRUPTS = {
	{ id = 1766, lock = 5, cd = 10 },              -- Kick
	{ id = 6552, lock = 4, cd = 10 },              -- Pummel
	{ id = 72, lock = 6, cd = 12 },                -- Shield Bash
	{ id = 2139, lock = 10, cd = 30 },             -- Counterspell
	{ id = 8042, lock = 2, cd = 6 },               -- Earth Shock
	{ id = 16979, lock = 4, cd = 15 },             -- Feral Charge
	{ id = 19244, lock = 6, cd = 24, pet = true }, -- Spell Lock (felhunter)
	{ id = 19647, lock = 8, cd = 24, pet = true }, -- Spell Lock, rank 2
}

-- Emergency items (UI/Emergency.lua), strongest first: healthstones (with the
-- warlock's talent ranks) and healing potions, the battleground draughts among them.
D.EMERGENCY = {
	healthstone = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 },
	potion = { 13446, 17348, 18839, 3928, 17349, 1710, 929, 4596, 858, 118 },
}

-- Items with a fixed range, for range checks (C_Item.IsItemInRange): the Classic
-- Era / Forever tables of LibRangeCheck-3.0 (WeakAuras, MIT licence), by yards.
-- harm: checked against enemies; friend: against friendly units. Sensors keeps the
-- ones this client knows (two per step) and ignores the rest.
D.RANGE_ITEMS = {
	harm = {
		[5] = {
			8149, 15826, 16308, 17117, 22259, 22432, 206466, 208760, 208855, 209027, 209057, 213036, 221199, 225943,
		},
		[10] = {
			9606, 9618, 9619, 9620, 9621, 10699, 17626, 17689, 226472,
		},
		[15] = {
			4559,
		},
		[20] = {
			1191, 2012, 4388, 10645, 13892, 17757, 18209, 22048, 202251, 227936, 232344,
		},
		[25] = {
			13289,
		},
		[30] = {
			835, 1404, 1434, 1444, 1472, 1704, 1854, 1914, 1995, 2091, 3434, 3441, 4479, 4480,
			4481, 4941, 5079, 5457, 6436, 7344, 7734, 9328, 9394, 10588, 10716, 10720, 11170, 11522,
			11565, 12288, 12646, 12647, 13213, 13509, 13514, 17202, 17310, 20084, 20908, 21038, 21713, 22200,
			22206, 22218, 220649, 228576, 233226,
		},
		[35] = {
			1258, 1399, 1402, 8688, 18904, 220568, 233216,
		},
		[40] = {
			4945, 8348, 191414, 208773, 208843, 209047,
		},
		[45] = {
			221316,
		},
		[100] = {
			5418, 17162, 23715, 23718, 23719, 23721, 23722, 227685,
		},
	},
	friend = {
		[5] = {
			1970, 8149, 15826, 16308, 16991, 17117, 20403, 22259, 208855, 209027, 209057, 213036, 221199, 225943,
		},
		[10] = {
			17626, 17689, 21267, 23164, 226207, 226208, 226209, 226210, 226211, 226212, 226213, 226214,
		},
		[15] = {
			1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529, 14530, 19066, 19067, 19068, 19307,
			20065, 20066, 20067, 20232, 20234, 20235, 20237, 20243, 20244, 23684, 232433,
		},
		[20] = {
			12450, 12451, 12455, 12457, 12458, 12460, 17757, 21519, 219963, 219965, 219983, 219984, 219985, 219986,
			219987, 219988, 219989, 219990, 219991, 219992, 219993, 219994, 219995, 219996, 219997, 219998, 220053, 220054,
			220055, 220056, 220057, 220058, 220059, 220060, 220061, 220062, 220063, 220064, 220065, 220066, 220067, 220068,
			220069, 220070, 220071, 220072, 220073, 220074, 220075, 220076, 220077, 220078, 220079, 220080, 220081, 220082,
			220083, 220084, 220085, 220086, 220087, 220088, 220089, 220090, 220091, 220092, 220093, 220094, 220095, 220096,
			220097, 220098, 220099, 220100, 220101, 220102, 220103, 220104, 220105, 220106, 220792, 223168, 223171, 224806,
			224893, 231298, 231836, 232344,
		},
		[25] = {
			13289,
		},
		[30] = {
			954, 955, 1180, 1181, 1477, 1478, 1711, 1712, 1851, 1912, 2289, 2290, 2948, 3012,
			3013, 4381, 4419, 4421, 4422, 4424, 4425, 4426, 4444, 5232, 5613, 6452, 6453, 10305,
			10306, 10307, 10308, 10309, 10310, 11563, 11564, 11567, 16892, 16893, 16895, 16896, 17202, 17310,
			18637, 19440, 20908, 21038, 21713, 22200, 22206, 22218,
		},
		[35] = {
			18904,
		},
		[40] = {
			1713, 5205, 5323, 8346, 11562, 18640, 18662, 213349, 216500, 216503, 216517, 216607, 230280,
		},
		[45] = {
			221316,
		},
		[50] = {
			221315,
		},
		[100] = {
			5418, 17162, 23715, 23718, 23719, 23721, 23722, 227685,
		},
	},
}
