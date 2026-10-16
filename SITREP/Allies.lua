-- SITREP · Allies (the friendly picture)
--
-- Group members: exact distance from the client's positions (UnitPosition), with
-- no traffic and no guessing. If Forever withholds a member's position, that
-- member falls back to range checks automatically.
--
-- Everyone else friendly (friendly nameplates, your target, whoever you hover):
-- distance from your helpful spells' range checks.
--
-- Per ally: whether they are inside your heal range, and how many enemies are
-- targeting them right now ("focused"), so you see who is being trained.

local ADDON, ns = ...
local read = ns.read
local sqrt, max = math.sqrt, math.max

local A = {}
ns.Allies = A
A.byKey = {}
A.list = {}
A.stats = { exact = 0, noExact = 0 }

local KEEP = 10 -- seconds a non-group ally stays after it was last seen
-- Someone on a friendly plate (not in your group) is measured every BEAT seconds,
-- not on every tick: a crowded town has forty of them. In combat often enough for
-- the heal range, out of combat seldom. In between they only count as still
-- there. Group members, your target, focus and mouseover: every tick.
local BEAT_COMBAT, BEAT_CALM = 0.75, 2
A.BEAT_COMBAT, A.BEAT_CALM = BEAT_COMBAT, BEAT_CALM
local seen = {}

local function healMax()
	local m
	for _, r in ipairs(ns.Sensors.myHelpRanges or {}) do m = max(m or 0, r) end
	return m
end

-- plate: a token from the sensors' friendly plates (a friendly player already)
-- (its own line in /sitrep perf)
A.Measure = ns.Timed("allies: range checks", function(...) return ns.Sensors.MeasureRange(...) end)

local function observe(unit, now, group, order, plate)
	local S = ns.Sensors
	local key
	if plate then
		-- a friendly player's plate: the GUID the sensors read on this tick
		key = S.plateGUID[unit] or S.UnitKey(unit)
		if key == S.self.guid or (key and key:sub(1, 2) == "U:" and read(UnitIsUnit, unit, "player")) then return end
	else
		if not read(UnitExists, unit) or read(UnitIsUnit, unit, "player") then return end
		local isPlayer = read(UnitIsPlayer, unit)
		if isPlayer == false then return end
		if S.IsHostile(unit) then return end
	end
	key = key or S.UnitKey(unit)
	if not key then return end
	local a = A.byKey[key]
	if seen[key] then
		-- seen already as your target, focus or mouseover: plate lookups want the plate's token
		if plate and a and not a.group then a.unit = unit end
		return
	end
	seen[key] = true
	if plate and a and not a.group and a.nextAt and now < a.nextAt then
		a.unit, a.live, a.last, a.lastLive, a.focus = unit, true, now, now, 0
		return a
	end
	if not a then a = { key = key, first = now }; A.byKey[key] = a end
	a.unit, a.group, a.order = unit, group, order or 99
	local beat = (InCombatLockdown() or (S.self and S.self.combat)) and BEAT_COMBAT or BEAT_CALM
	a.nextAt = plate and now + beat * (0.75 + math.random() * 0.5) or nil
	a.name = read(GetUnitName, unit, false) or a.name or "Unknown"
	a.fullName = read(GetUnitName, unit, true) or a.fullName
	local _, class = read(UnitClass, unit)
	a.class = class or a.class
	a.level = read(UnitLevel, unit) or a.level
	a.dead = read(UnitIsDeadOrGhost, unit) == true
	a.live, a.last, a.lastLive = true, now, now
	a.focus = 0

	local me = S.self
	local x, y, _, inst
	if group then x, y, _, inst = read(UnitPosition, unit) end
	if x and me.x and inst == me.inst then
		-- exact: straight from the client
		a.exact = true
		A.stats.exact = A.stats.exact + 1
		local dx, dy = x - me.x, y - me.y
		a.range, a.lo, a.hi = sqrt(dx * dx + dy * dy), nil, nil
	else
		a.exact = false
		if group then A.stats.noExact = A.stats.noExact + 1 end
		local lo, hi = A.Measure(unit, nil, S.helpChecks)
		S.TrackClosure(a, a.lo, a.hi, lo, hi, now)
		a.lo, a.hi = lo, hi
		a.range = S.RangeEstimate(lo, hi, a.range)
	end

	-- inside my heal range? exact when we can be, else from the bracket
	local hm = healMax()
	if hm then
		if a.exact then a.inHeal = a.range <= hm
		elseif a.hi and a.hi <= hm then a.inHeal = true
		elseif a.lo and a.lo > hm then a.inHeal = false
		else a.inHeal = nil end -- the bracket straddles your heal range
	else
		a.inHeal = nil
	end
	return a
end

local function groupUnits(now)
	if not (IsInGroup and IsInGroup()) then return end
	local raid = IsInRaid()
	local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	local prefix = raid and "raid" or "party"
	for i = 1, n do observe(prefix .. i, now, true, i) end
end

-- group first in roster order (stable rows to click), then others by distance
local function byRow(x, y)
	if x.group ~= y.group then return x.group end
	if x.group then return x.order < y.order end
	return (x.range or 99) < (y.range or 99)
end

function A.Tick(now)
	local S = ns.Sensors
	A.stats.exact, A.stats.noExact = 0, 0
	for k in pairs(seen) do seen[k] = nil end
	groupUnits(now)
	observe("target", now, false)
	observe("focus", now, false)
	observe("mouseover", now, false)
	for _, unit in ipairs(S._friendPlates) do observe(unit, now, false, nil, true) end

	local list = A.list
	for i = #list, 1, -1 do list[i] = nil end
	for key, a in pairs(A.byKey) do
		if not seen[key] then
			a.live = false
			-- group members leave with the group; others fade after a while
			if a.group or now - (a.last or 0) > KEEP then
				A.byKey[key] = nil
			end
		end
		if A.byKey[key] then
			list[#list + 1] = a
		end
	end

	-- focus: how many enemies have each ally as their target
	for _, c in ipairs(ns.Model.byThreat) do
		if c.live and c.unit and not c.npc then
			for _, a in ipairs(list) do
				if a.live and a.unit and read(UnitIsUnit, c.unit .. "target", a.unit) then a.focus = a.focus + 1 end
			end
		end
	end

	table.sort(list, byRow)
	ns.Fire("SR_ALLIES", list, now)
end

-- The ally record for a unit token (e.g. "target"), if it is one.
function A.ForUnit(unit)
	local key = ns.Sensors.UnitKey(unit)
	return key and A.byKey[key]
end

ns.On("SR_PICTURE", function(_, _, _, now) A.Tick(now) end)
ns.On("PLAYER_ENTERING_WORLD", function() for k in pairs(A.byKey) do A.byKey[k] = nil end end)
