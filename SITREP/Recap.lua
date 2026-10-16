-- SITREP · Death recap: who killed you, without the combat log
-- Forever gives addons no combat log, so the game's own death recap is gone. But
-- three things stay plain in a fight: every hit on you (UNIT_COMBAT: amount,
-- school, critical), who targets you, and which casts on you just ended
-- (Incoming). The recap keeps the last KEEP seconds of all of it and, when you die
-- or lose a duel, gives each hit to its likeliest source:
--   physical: an enemy in melee range of you that targets you (a hunter: from
--             range), less so one in melee range that does not;
--   a spell:  the enemy whose cast on you ended just before (the bolt in flight),
--             else casters that target you (DoTs, instants);
--   nothing that fits: the mobs on you, or unknown.
-- Then: the share per source, the biggest hit, how much hit you while you could
-- not act, whether your emergency items were ready and unused, and a tip or two.
-- Kept in SITREP_DB.log.deaths (the last DEATHS); UI/RecapPanel.lua shows it.
-- Bus: SR_RECAP(recap).

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format, max = string.format, math.max

local RC = {}
ns.Recap = RC
local KEEP = 30          -- seconds of history
local FLIGHT = 1.6       -- a bolt lands at most this long after its cast ends
local CALM = 8           -- seconds without a hit: the fight before does not count
local DEATHS = 20        -- recaps kept
RC.hits, RC.snaps, RC.landed = {}, {}, {}

local SCHOOL = { [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost", [32] = "Shadow", [64] = "Arcane" }
RC.SCHOOL = SCHOOL
local CASTER = { MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true, PALADIN = true, HUNTER = true }
local MELEE = { ROGUE = true, WARRIOR = true, PALADIN = true, DRUID = true, SHAMAN = true }

local function trim(list, now)
	while list[1] and now - list[1].t > KEEP do table.remove(list, 1) end
end

-- a hit or a heal on you
ns.On("UNIT_COMBAT", function(_, unit, action, flag, amount, school)
	if unit ~= "player" then return end
	amount = plain(amount)
	if type(amount) ~= "number" or amount <= 0 then return end
	if action ~= "WOUND" and action ~= "HEAL" then return end
	local now = GetTime()
	RC.hits[#RC.hits + 1] = { t = now, heal = action == "HEAL", amount = amount, school = plain(school) or 1,
		crit = plain(flag) == "CRITICAL" }
	trim(RC.hits, now)
end)

-- a cast on you ended (Incoming knows which casts are on you)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
	local I = ns.Incoming
	local c = I and I.casts and I.casts[unit]
	if not c or c.onMe == false then return end
	local now = GetTime()
	RC.landed[#RC.landed + 1] = { t = now, key = ns.Sensors.UnitKey(unit), sure = c.onMe == true,
		spell = type(c.name) == "string" and not ns.isSecret(c.name) and c.name or nil }
	trim(RC.landed, now)
end)

-- the picture, every tick while something is going on
ns.On("SR_PICTURE", function(_, list, _, now)
	local me = ns.Sensors.self
	local last = RC.hits[#RC.hits]
	if not (me.combat or (last and now - last.t < CALM)) then return end
	local enemies = {}
	for _, c in ipairs(list) do
		if c.live then
			enemies[#enemies + 1] = { key = c.key, name = c.name, class = c.class, npc = c.npc, targetingMe = c.targetingMe,
				lo = c.lo, hi = c.hi }
		end
	end
	local em = false
	for _, b in ipairs(ns.Emergency and ns.Emergency.buttons or {}) do if b.hot then em = true end end
	RC.snaps[#RC.snaps + 1] = { t = now, hp = ns.Pressure.HealthFrac(), enemies = enemies, emergency = em,
		cc = ns.Frames and ns.Frames.frames.player and ns.Frames.frames.player.locActive or false,
		mobs = ns.Targeting.MobsOnMe() }
	trim(RC.snaps, now)
end)

-- The snapshot at (or just before) t.
local function snapAt(t)
	local best
	for _, s in ipairs(RC.snaps) do
		if s.t <= t + 0.05 then best = s else break end
	end
	return best or RC.snaps[1]
end

-- How likely each enemy dealt this hit: { [key] = weight }; "mobs" for the mobs on you.
function RC.Weights(hit, snap)
	local w = {}
	if not snap then return w end
	local physical = hit.school == 1
	for _, e in ipairs(snap.enemies) do
		local x = 0
		local melee = e.hi ~= nil and e.hi <= 8
		if physical then
			if e.targetingMe and melee then x = 3
			elseif melee then x = 1
			elseif e.targetingMe and e.class == "HUNTER" then x = 2
			elseif e.targetingMe then x = 0.2 end
		else
			for _, l in ipairs(RC.landed) do
				if l.key == e.key and hit.t - l.t >= -0.15 and hit.t - l.t <= FLIGHT then x = max(x, l.sure and 4 or 2) end
			end
			if x == 0 and e.targetingMe and CASTER[e.class or ""] then x = 1
			elseif x == 0 and e.targetingMe then x = 0.2 end
		end
		if e.npc then x = x * 0.8 end
		if x > 0 then w[e.key] = (w[e.key] or 0) + x end
	end
	if (snap.mobs or 0) > 0 then
		local any = false
		for _, v in pairs(w) do if v >= 1 then any = true end end
		if not any then w.mobs = snap.mobs * (physical and 2 or 0.5) end
	end
	return w
end

-- Build the recap of the fight that just ended at `now` (death or a lost duel).
function RC.Build(now, how)
	now = now or GetTime()
	-- the fight: back from now to the first hit after a calm of CALM seconds
	local first = nil
	for i = #RC.hits, 1, -1 do
		local h = RC.hits[i]
		if not h.heal then
			if first and first.t - h.t > CALM then break end
			first = h
		end
	end
	if not first then return nil end
	local names = {}
	for _, s in ipairs(RC.snaps) do
		for _, e in ipairs(s.enemies) do names[e.key] = { name = e.name, class = e.class, npc = e.npc } end
	end
	local src, total, healIn, ccDmg, last3 = {}, 0, 0, 0, 0
	local biggest
	for _, h in ipairs(RC.hits) do
		if h.t >= first.t and h.t <= now + 0.1 then
			if h.heal then
				healIn = healIn + h.amount
			else
				total = total + h.amount
				if now - h.t <= 3 then last3 = last3 + h.amount end
				local snap = snapAt(h.t)
				if snap and snap.cc then ccDmg = ccDmg + h.amount end
				local w = RC.Weights(h, snap)
				local sum = 0
				for _, v in pairs(w) do sum = sum + v end
				local who = nil
				if sum == 0 then
					w, sum = { unknown = 1 }, 1
				end
				local top = 0
				for k, v in pairs(w) do
					local s = src[k] or { key = k, dmg = 0, hits = 0, schools = {} }
					src[k] = s
					local part = h.amount * v / sum
					s.dmg = s.dmg + part
					s.hits = s.hits + v / sum
					s.schools[h.school] = (s.schools[h.school] or 0) + part
					if v > top then top, who = v, k end
				end
				if not biggest or h.amount > biggest.amount then
					biggest = { amount = h.amount, school = h.school, crit = h.crit, who = who, before = now - h.t }
				end
			end
		end
	end
	if total <= 0 then return nil end
	local list = {}
	for k, s in pairs(src) do
		local n = names[k]
		s.name = k == "mobs" and "Mobs" or k == "unknown" and "Unknown" or (n and n.name) or "?"
		s.class = n and n.class
		s.npc = n and n.npc
		s.share = s.dmg / total
		local bestSchool, bestAmt = nil, 0
		for sc, a in pairs(s.schools) do if a > bestAmt then bestSchool, bestAmt = sc, a end end
		s.school = bestSchool
		s.schools = nil
		list[#list + 1] = s
	end
	table.sort(list, function(a, b) return a.dmg > b.dmg end)
	-- the emergency items: ready below the threshold, still ready when it ended
	local readySeen, readyAtEnd = false, false
	for _, s in ipairs(RC.snaps) do
		if s.t >= first.t and s.emergency then readySeen = true end
	end
	local lastSnap = RC.snaps[#RC.snaps]
	readyAtEnd = lastSnap and lastSnap.emergency or false
	local z, sub = read(GetRealZoneText), read(GetSubZoneText)
	local r = {
		at = read(time) or 0, how = how or "death", dur = now - first.t, total = total, healIn = healIn,
		sources = list, biggest = biggest, ccShare = ccDmg / total, burst = last3 / total,
		emergencyUnused = readySeen and readyAtEnd, zone = sub ~= "" and sub or z,
	}
	if biggest and biggest.who and src[biggest.who] then biggest.name = src[biggest.who].name end
	r.durability = RC.Durability()
	r.tips = RC.Tips(r)
	return r
end

-- Your most worn piece of armour, in % (nil: nothing that wears). Each death
-- costs 10 % of it.
function RC.Durability()
	if not GetInventoryItemDurability then return nil end
	local low
	for slot = 1, 18 do
		local cur, mx = read(GetInventoryItemDurability, slot)
		if cur and mx and mx > 0 then
			local pct = cur / mx * 100
			if not low or pct < low then low = pct end
		end
	end
	return low
end

-- One or two lessons from a recap.
function RC.Tips(r)
	local tips = {}
	if r.emergencyUnused then tips[#tips + 1] = "Your healing potion or healthstone was ready at low health and not used." end
	if r.ccShare >= 0.35 then
		tips[#tips + 1] = format("%.0f%% of the damage hit you while you could not act: break the control sooner (trinket, Escape Artist).", r.ccShare * 100)
	end
	local top = r.sources[1]
	if top and top.share >= 0.5 and #tips < 2 then
		local who = top.name ~= "?" and top.name or (ns.Data.NAME[top.class or ""] or "one enemy")
		if top.school == 1 and MELEE[top.class or ""] then
			tips[#tips + 1] = format("%s dealt %.0f%% in melee: keep them off you (slow, root, distance).", who, top.share * 100)
		elseif top.school and top.school ~= 1 then
			tips[#tips + 1] = format("%s dealt %.0f%% with spells: interrupt them or break line of sight.", who, top.share * 100)
		end
	end
	if r.burst >= 0.5 and #tips < 2 then
		tips[#tips + 1] = format("%.0f%% of it came in the last 3 s: a burst. Use your defensive before it, not after.", r.burst * 100)
	end
	return tips
end

local function store(r)
	local log = ns.db and ns.db.log
	if not log then return end
	log.deaths = log.deaths or {}
	table.insert(log.deaths, 1, r)
	for i = #log.deaths, DEATHS + 1, -1 do log.deaths[i] = nil end
end

function RC.Finish(how)
	local r = RC.Build(GetTime(), how)
	if not r then return nil end
	RC.last = r
	store(r)
	ns.Fire("SR_RECAP", r)
	return r
end

ns.On("PLAYER_DEAD", function() RC.Finish("death") end)
ns.On("SR_DUEL_RESULT", function(_, res) if res and not res.won then RC.Finish("duel") end end)
ns.On("PLAYER_ENTERING_WORLD", function() wipe(RC.hits); wipe(RC.snaps); wipe(RC.landed) end)
