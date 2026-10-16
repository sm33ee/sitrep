-- SITREP · Targeting
-- Who targets whom, counted for the frames and plates:
--   TG.Is(a, b)          is a's target b? (true / false / nil when the client hides it)
--   TG.TargetedBy(unit)  enemy players on a unit (you: from the contacts; others: from Allies)
--   TG.HealersOnMe()     friendly players on you who heal (role, class, or healing you now)
--   TG.AlliesOn(unit)    friendly players whose target the unit is
--   TG.EnemiesOn(unit, healersOnly)  enemy players on it (or only their healers)
--   TG.MobsOnMe()        enemy NPCs whose target is you
--   TG.PetOwner(unit)    a pet's (minion's, guardian's) owner's name, from the
--                        client's own tooltip line ("Varok's Pet"); TG.petOwner:
--                        your target's, kept from the moment you target it
--   TG.focus[guid]       how many of your group (you too) have that unit as their
--                        target; TG.focusTop the one most of you are on (from 2),
--                        TG.myTarget yours (TG.UpdateFocus, once a tick)
--   TG.stats             how the client answered the comparisons (plain / secret / refused),
--                        for the after-combat report
-- Only units SITREP can see count: nameplates, group, target, focus, mouseover.

local ADDON, ns = ...
local read = ns.read

local TG = {}
ns.Targeting = TG

-- Friendly healers on you: friendly players (your group, friendly plates) whose
-- target is you and who heal - by their group role (battlegrounds assign
-- them), else by a class that can heal, or because they are casting a heal on
-- you right now (whatever their role). For a flag carrier: how much help is on you.
local HEAL_CLASS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
TG.HEAL_CLASS = HEAL_CLASS

-- "Is a's target b?" - and a tally of how the client answered, for the fight
-- report: in combat the client may hide unit comparisons (secret) too.
TG.stats = { plain = 0, secret = 0, err = 0 }
local function targets(a, b)
	local ok, v = pcall(UnitIsUnit, a .. "target", b)
	local st = TG.stats
	if not ok then st.err = st.err + 1 return nil end
	if ns.isSecret(v) then st.secret = st.secret + 1 return nil end
	st.plain = st.plain + 1
	return v == true
end
TG.Is = targets

-- Enemy NPCs whose target is you (levelling: how many mobs are on you). From
-- the nameplates on screen and your target/focus; no option needed.
-- (asked every tick over every plate: whether its target is you comes first, one
-- call, and the rest only for the few that are on you)
local mobSeen = {}
local function mobOnMe(u, n)
	if not targets(u, "player") then return n end
	local key = read(UnitGUID, u) or u
	if not mobSeen[key] and read(UnitIsPlayer, u) == false and ns.Sensors.IsEnemy(u) and not read(UnitIsUnit, u, "player") then
		mobSeen[key] = true
		n = n + 1
	end
	return n
end
function TG.MobsOnMe()
	wipe(mobSeen)
	local n = 0
	for u in pairs(ns.Sensors._plates or {}) do n = mobOnMe(u, n) end
	n = mobOnMe("target", n)
	return mobOnMe("focus", n)
end
-- Friendly players on you: how many heal (role, class, or healing you now), and
-- how many in all. One pass (asked every tick over everyone on a friendly plate).
function TG.OnMe()
	local healers, all = 0, 0
	for _, a in ipairs(ns.Allies and ns.Allies.list or {}) do
		local u = a.live and a.unit
		if u and targets(u, "player") then
			all = all + 1
			local healing = false
			local okH, inc = pcall(UnitGetIncomingHeals, "player", u)
			if okH and not ns.isSecret(inc) and type(inc) == "number" and inc > 0 then healing = true end
			if not healing then
				local role = read(UnitGroupRolesAssigned, u)
				if role == "HEALER" then healing = true
				elseif (role == nil or role == "NONE") and HEAL_CLASS[a.class or ""] then healing = true end
			end
			if healing then healers = healers + 1 end
		end
	end
	return healers, all
end
function TG.HealersOnMe() return (TG.OnMe()) end

-- Who else is on your target. Friendly players (your group, friendly plates)
-- whose target it is; and enemy players whose target it is - for an enemy
-- target those are its teammates, so a healing class or one seen healing it
-- is counted as its healer; for a friendly target they are its attackers.
-- A pet's owner: the client writes it into the unit's tooltip in its own words
-- (UNITNAME_TITLE_PET "%s's Pet", German "Begleiter von %s", minions, guardians...);
-- each of those formats becomes a pattern that gives the name back.
local OWNER_FORMATS = { "UNITNAME_TITLE_PET", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_COMPANION",
	"UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_SQUIRE" }
local ownerPatterns
local function patterns()
	if ownerPatterns then return ownerPatterns end
	ownerPatterns = {}
	for _, g in ipairs(OWNER_FORMATS) do
		local f = _G[g]
		if type(f) == "string" and f:find("%s", 1, true) then
			local p = f:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", "(.+)")
			ownerPatterns[#ownerPatterns + 1] = "^" .. p .. "$"
		end
	end
	if #ownerPatterns == 0 then ownerPatterns = { "^(.+)'s Pet$", "^(.+)'s Minion$", "^(.+)'s Guardian$" } end
	return ownerPatterns
end
function TG.PetOwner(unit)
	if read(UnitIsPlayer, unit) ~= false or read(UnitPlayerControlled, unit) ~= true then return nil end
	local T = C_TooltipInfo and C_TooltipInfo.GetUnit
	if not T then return nil end
	local ok, data = pcall(T, unit)
	if not (ok and type(data) == "table") or ns.isSecret(data) or type(data.lines) ~= "table" then return nil end
	for i = 2, math.min(#data.lines, 4) do
		local text = ns.plain(data.lines[i] and data.lines[i].leftText)
		if type(text) == "string" then
			for _, p in ipairs(patterns()) do
				local name = text:match(p)
				if name then return name end
			end
		end
	end
	return nil
end
ns.On("PLAYER_TARGET_CHANGED", function() TG.petOwner = TG.PetOwner("target") end)

-- Is this the same player? Forever's players have two names ("Aldric Hale"),
-- unique together; a realm may follow after "-". Whether every API gives both
-- names is not measured: one name that is the other's first word counts too.
function TG.SameName(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	a, b = a:match("^([^%-]+)") or a, b:match("^([^%-]+)") or b
	if a == b then return true end
	if #a > #b then a, b = b, a end
	return b:sub(1, #a + 1) == a .. " "
end

-- Your group's targets, by GUID (plain where a comparison may not be: the GUID
-- of a unit's target can be read when "is it that unit" is secret). One pass over
-- the group a tick; a plate then looks its count up.
TG.focus = {}
function TG.UpdateFocus()
	local f = TG.focus
	for k in pairs(f) do f[k] = nil end
	TG.focusTop = nil
	TG.myTarget = read(UnitGUID, "target")
	if not (IsInGroup and IsInGroup()) then return end
	local raid = IsInRaid and IsInRaid()
	local n = (raid and read(GetNumGroupMembers) or read(GetNumSubgroupMembers)) or 0
	local prefix = raid and "raid" or "party"
	local function add(u)
		local g = read(UnitGUID, u .. "target")
		if g then f[g] = (f[g] or 0) + 1 end
	end
	for i = 1, n do
		local u = prefix .. i
		-- (the raid's list has you in it too)
		if not (raid and read(UnitIsUnit, u, "player")) then add(u) end
	end
	-- you: your target
	local mine = TG.myTarget
	if mine then f[mine] = (f[mine] or 0) + 1 end
	local best = 1
	for g, c in pairs(f) do
		if c > best then best, TG.focusTop = c, g end
	end
end
ns.On("SR_TICK", function() TG.UpdateFocus() end)

function TG.AlliesOn(unit)
	local n = 0
	for _, a in ipairs(ns.Allies and ns.Allies.list or {}) do
		local u = a.live and a.unit
		if u and targets(u, unit) and not read(UnitIsUnit, u, unit) then n = n + 1 end
	end
	return n
end

function TG.EnemiesOn(unit, healersOnly)
	local n = 0
	for _, c in ipairs(ns.Model.byThreat) do
		local u = c.live and c.unit
		if u and not c.npc and not read(UnitIsUnit, u, unit) and targets(u, unit) then
			if healersOnly then
				-- seen healing it once: a healer for the rest of the session
				local okH, inc = pcall(UnitGetIncomingHeals, unit, u)
				if okH and not ns.isSecret(inc) and type(inc) == "number" and inc > 0 then c.healer = true end
				if TG.IsHealer(c) or HEAL_CLASS[c.class or ""] then n = n + 1 end
			else
				n = n + 1
			end
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Healers by what they do. No combat log: but a heal on an enemy (UNIT_COMBAT
-- "HEAL", the amount plain) arrives the moment the healer's cast lands, and that
-- enemy's cast ends then (UNIT_SPELLCAST_SUCCEEDED). When exactly one other enemy
-- finished a cast within CAST_WINDOW before a heal, that is a point for it;
-- HEAL_POINTS points: a healer, for the rest of the session (by its key, so it
-- stays one after its contact is forgotten). Self-heals do not count (a potion,
-- a bandage, a paladin's own Holy Light); several casters at once: no point.
---------------------------------------------------------------------------
local CAST_WINDOW, HEAL_POINTS = 0.35, 2
local recentCasts = {} -- { key, t }, newest last
local lastHeal = {}    -- [key] = { t, amount }: one heal seen through two tokens counts once
TG.healPoints = {}
TG.knownHealers = {}
TG.healStats = { heals = 0, matched = 0, ambiguous = 0, alone = 0 }

local function enemyKey(unit)
	if unit == "player" or unit == "pet" then return nil end
	local key = ns.Sensors.UnitKey(unit)
	local c = key and ns.Sensors.contacts[key]
	if not c or c.npc then return nil end
	return key, c
end

function TG.IsHealer(c)
	return c ~= nil and (c.healer or TG.knownHealers[c.key or ""] == true)
end

function TG.CastDone(unit, now)
	local key = enemyKey(unit)
	if not key then return end
	now = now or GetTime()
	recentCasts[#recentCasts + 1] = { key, now }
	while recentCasts[1] and now - recentCasts[1][2] > CAST_WINDOW * 4 do table.remove(recentCasts, 1) end
end

function TG.HealSeen(unit, amount, now)
	local key = enemyKey(unit)
	if not key then return end
	now = now or GetTime()
	local last = lastHeal[key]
	if last and now - last[1] < 0.05 and last[2] == amount then return end
	lastHeal[key] = { now, amount }
	local st = TG.healStats
	st.heals = st.heals + 1
	local who, n = nil, 0
	for i = #recentCasts, 1, -1 do
		local cast = recentCasts[i]
		if now - cast[2] > CAST_WINDOW then break end
		if cast[1] ~= key and cast[1] ~= who then who, n = cast[1], n + 1 end
	end
	if n == 0 then st.alone = st.alone + 1 return end
	if n > 1 then st.ambiguous = st.ambiguous + 1 return end
	st.matched = st.matched + 1
	local pts = (TG.healPoints[who] or 0) + 1
	TG.healPoints[who] = pts
	if pts >= HEAL_POINTS and not TG.knownHealers[who] then
		TG.knownHealers[who] = true
		local c = ns.Sensors.contacts[who]
		if c then c.healer = true end
		ns.Fire("SR_HEALER", who, c)
	end
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit) TG.CastDone(unit) end)
ns.On("UNIT_COMBAT", function(_, unit, action, _, amount)
	if action == "HEAL" then TG.HealSeen(unit, amount) end
end)
ns.On("PLAYER_ENTERING_WORLD", function() wipe(recentCasts); wipe(lastHeal) end)

-- Enemy players targeting a unit right now (that you can see: plates, targets).
function TG.TargetedBy(unit)
	if unit == "player" then
		local n = 0
		for _, c in ipairs(ns.Model.byThreat) do if c.live and c.targetingMe and not c.npc then n = n + 1 end end
		return n
	end
	local a = ns.Allies and ns.Allies.ForUnit(unit)
	return a and a.focus or 0
end
