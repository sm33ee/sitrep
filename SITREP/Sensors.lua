-- SITREP · Sensors (OBSERVE)
-- Builds the contact picture: every hostile player the client lets us see, with
-- a range bracket and a closure rate. No directions: the client gives addons
-- none, and estimating them from distances alone was not reliable enough.
--
--   Range   = intersection of every range check the client answers. Each "in
--             range of a 30 yd spell" caps the interval, each "out of range of a
--             20 yd spell" floors it. Range checks stay plain in combat.
--   Closure = yards per second from the moments a contact crosses a range-check
--             boundary (each crossing is an exact distance at a known time).
--   Self    = your position (for exact distances to group members).

local ADDON, ns = ...
local read, present = ns.read, ns.present
local min, max, floor = math.min, math.max, math.floor
local SWEEP_EVERY = 1 -- seconds between sweeps of the 40 plate tokens
local pairs, ipairs, wipe = pairs, ipairs, wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local S = {}
ns.Sensors = S
S.contacts = {}          -- key -> contact
S.list = {}              -- contacts as an array, rebuilt each tick
S.self = {}              -- own state: x, y, inst, class, level, faction, combat
S.stats = { plates = 0, rangeAsked = 0, rangeAnswered = 0, plateEvents = 0, swept = 0 }

-- Every nameplate on screen. Friend or foe is decided on each tick, not when the
-- plate appears: a duel, a PvP flag or a faction change flips a unit mid-fight.
local plates, friendPlates = {}, {}
-- What each plate's unit is ("hostile", "friend": a friendly player, "other"),
-- asked again every KIND_KEEP seconds, or at once when the plate shows someone
-- else (its GUID), a duel starts or ends or a unit changes sides; enemies every
-- tick. Forty plates in a town, each asked half a dozen questions ten times a
-- second, otherwise.
local plateKinds = {} -- [unit] = { guid, kind, at }
local KIND_KEEP = 0.5
local checks = {}


---------------------------------------------------------------------------
-- Range checks, rebuilt from the spellbook whenever it changes.
---------------------------------------------------------------------------
local helpChecks = {}
S.helpChecks = helpChecks

-- Keep one spell per range; prefer the one with no minimum range.
local function addByMax(byMax, id, s)
	local mx, mn = ns.plain(s.maxRange), ns.plain(s.minRange) or 0
	-- Melee abilities report 0-0 and answer "in range" at any distance.
	if mx and mx > 5 and mx <= 45 and (not byMax[mx] or mn < byMax[mx].min) then
		byMax[mx] = { kind = "spell", id = id, min = mn, max = mx, name = s.name }
	end
end

-- Items with a fixed range, which the client checks against units (Data.lua ->
-- RANGE_ITEMS: LibRangeCheck's Classic Era / Forever tables, harm and friend): with
-- them the bracket narrows to 5 yd steps. Per step only the first two items this
-- client knows are asked (it knows an item once C_Item.GetItemNameByID answers;
-- data loads on request, so steps still missing are retried for a minute). An
-- item that stays silent anyway is dropped. /sitrep rangeprobe shows what answers.
--
-- Protected in combat (since 10.2, hotfixed): the item checks and
-- CheckInteractDistance may be asked about ENEMIES only while in combat. Asking
-- about anyone else is a blocked action ("Interface action failed because of an
-- AddOn"), so in combat measureRange uses them for units you can attack and
-- spells alone for everyone else.
local ITEM_GIVE_UP = 25    -- silent answers (while other checks answered) before an item is dropped
local ITEMS_PER_STEP = 2   -- items asked per step of yards
local ITEM_RETRY, ITEM_RETRIES = 5, 12 -- seconds between retries for steps whose items still load

-- The first items of a step this client knows; asks the client to load the others.
local function knownItems(ids)
	local nameOf = C_Item and C_Item.GetItemNameByID
	local load = C_Item and C_Item.RequestLoadItemDataByID
	local out, unloaded = {}, false
	for _, id in ipairs(ids) do
		if nameOf and read(nameOf, id) then
			out[#out + 1] = id
			if #out >= ITEMS_PER_STEP then break end
		else
			if load then pcall(load, id) end
			unloaded = true
		end
	end
	return out, unloaded
end
S.KnownItems = knownItems

function S.ItemRangeFn()
	return (C_Item and C_Item.IsItemInRange) or _G.IsItemInRange
end

-- Two ladders: harmful spells range-check enemies, helpful spells (heals, buffs,
-- cleanses) range-check allies. Both get the 10 and 28 yd interact checks, and
-- the item checks.
function S.BuildRangeChecks()
	wipe(checks)
	wipe(helpChecks)
	S.ladderGen = S.ladderGen + 1
	local P = ns.P.sensors
	local book = C_SpellBook
	if P.useSpellRange and book and book.GetNumSpellBookSkillLines and C_Spell and C_Spell.IsSpellInRange then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		local byMax, byMaxHelp = {}, {}
		for line = 1, read(book.GetNumSpellBookSkillLines) or 0 do
			local info = read(book.GetSpellBookSkillLineInfo, line)
			local first, count = info and ns.plain(info.itemIndexOffset), info and ns.plain(info.numSpellBookItems)
			if first and count then
				for slot = first + 1, first + count do
					local item = read(book.GetSpellBookItemInfo, slot, bank)
					local id = item and ns.plain(item.spellID)
					if id and not item.isPassive then
						local harmful = read(book.IsSpellBookItemHarmful, slot, bank)
						local helpful = not harmful and read(book.IsSpellBookItemHelpful, slot, bank)
						if harmful or helpful then
							local s = read(C_Spell.GetSpellInfo, id)
							if s then addByMax(harmful and byMax or byMaxHelp, id, s) end
						end
					end
				end
			end
		end
		for _, c in pairs(byMax) do checks[#checks + 1] = c end
		for _, c in pairs(byMaxHelp) do helpChecks[#helpChecks + 1] = c end
	end
	if P.useInteract then
		for _, list in ipairs({ checks, helpChecks }) do
			list[#list + 1] = { kind = "interact", idx = 3, min = 0, max = 10, name = "duel distance" }
			list[#list + 1] = { kind = "interact", idx = 4, min = 0, max = 28, name = "follow distance" }
		end
	end
	local itemFn = S.ItemRangeFn()
	S.itemsPending = false
	if P.useItemRange and itemFn then
		for kind, list in pairs({ harm = checks, friend = helpChecks }) do
			for yd, ids in pairs(ns.Data.RANGE_ITEMS[kind]) do
				local use, unloaded = knownItems(ids)
				if #use < ITEMS_PER_STEP and unloaded then S.itemsPending = true end
				for _, id in ipairs(use) do
					list[#list + 1] = { kind = "item", id = id, fn = itemFn, min = 0, max = yd, name = "item " .. id }
				end
			end
		end
	end
	table.sort(checks, function(a, b) return a.max < b.max end)
	table.sort(helpChecks, function(a, b) return a.max < b.max end)
	S.checks = checks
	-- My support reach: every helpful spell range.
	local help = {}
	for _, c in ipairs(helpChecks) do if c.kind == "spell" then help[#help + 1] = c.max end end
	S.myHelpRanges = help
	-- My own weapon reach: every harmful spell range, plus melee.
	local mine = { 5 }
	for _, c in ipairs(checks) do if c.kind == "spell" then mine[#mine + 1] = c.max end end
	S.myRanges = mine
	S.myReach = mine[#mine]
end

-- The ladder in steps: its no-minimum checks grouped by range (one step: every
-- check that reaches N yards), in the list's order (nearest first); the checks
-- with a minimum range apart. Built once per ladder (rebuilt with it).
local stepCache = setmetatable({}, { __mode = "k" }) -- [list] = { gen, steps, ranged }
S.ladderGen = 0
local function stepsOf(list)
	local c = stepCache[list]
	if c and c.gen == S.ladderGen and c.n == #list then return c.steps, c.ranged end
	local steps, ranged = {}, {}
	for i = 1, #list do
		local ch = list[i]
		if ch.min == 0 then
			local last = steps[#steps]
			if last and last.max == ch.max then last[#last + 1] = ch
			else steps[#steps + 1] = { max = ch.max, ch } end
		else
			ranged[#ranged + 1] = ch
		end
	end
	stepCache[list] = { gen = S.ladderGen, n = #list, steps = steps, ranged = ranged }
	return steps, ranged
end

local function ask(c, unit)
	if c.kind == "spell" then return read(C_Spell.IsSpellInRange, c.id, unit) end
	if c.kind == "item" then return read(c.fn, c.id, unit) end
	return read(CheckInteractDistance, unit, c.idx)
end

-- One step: its checks until one answers. true in range, false out, nil silent.
local silentBuf = {}
local function askStep(step, unit, protectedOK, st)
	for i = 1, #step do
		local c = step[i]
		if not c.dead and (c.kind == "spell" or protectedOK) then
			local r = ask(c, unit)
			st.rangeAsked = st.rangeAsked + 1
			if r ~= nil then
				st.rangeAnswered = st.rangeAnswered + 1
				if c.kind == "item" then c.heard = true end
				return r == true or r == 1
			elseif c.kind == "item" and not c.heard then
				silentBuf[#silentBuf + 1] = c
			end
		end
	end
	return nil
end

-- Returns lo, hi (yards). hi is nil when nothing capped the distance.
-- list defaults to the harmful ladder; pass S.helpChecks for allies.
-- The steps are searched by halving (a unit inside 20 yd is inside 25 and 30 too):
-- about five questions for twenty-odd steps, instead of all of them for a unit far
-- away. A step that does not answer is left out of the search.
local cand = {}
local function measureRange(unit, ceiling, list)
	local lo, hi = 0, ceiling
	local st = S.stats
	list = list or checks
	-- interact and item checks: anyone out of combat, only enemies in combat (see above)
	local protectedOK = not InCombatLockdown() or read(UnitCanAttack, "player", unit) == true
	local steps, ranged = stepsOf(list)
	wipe(silentBuf)
	local answered = false
	local n = 0
	for i = 1, #steps do
		if not (ceiling and steps[i].max >= ceiling) then n = n + 1; cand[n] = i end
	end
	for i = #cand, n + 1, -1 do cand[i] = nil end
	local L, R = 1, n
	while L <= R do
		local m = floor((L + R) / 2)
		local step = steps[cand[m]]
		local r = askStep(step, unit, protectedOK, st)
		if r == nil then
			table.remove(cand, m)
			R = R - 1
		else
			answered = true
			if r then
				if not hi or step.max < hi then hi = step.max end
				R = m - 1
			else
				if step.max > lo then lo = step.max end
				L = m + 1
			end
		end
	end
	-- checks with a minimum range: inside one narrows both ends
	for i = 1, #ranged do
		local c = ranged[i]
		if not c.dead and (c.kind == "spell" or protectedOK) and not (hi and c.min >= hi) and c.max > lo then
			local r = ask(c, unit)
			st.rangeAsked = st.rangeAsked + 1
			if r ~= nil then
				st.rangeAnswered = st.rangeAnswered + 1
				answered = true
				if c.kind == "item" then c.heard = true end
				if r == true or r == 1 then
					if not hi or c.max < hi then hi = c.max end
					if c.min > lo then lo = c.min end
				end
			elseif c.kind == "item" and not c.heard then
				silentBuf[#silentBuf + 1] = c
			end
		end
	end
	-- an item that stays silent while other checks answer is not known to this client
	if answered then
		for i = 1, #silentBuf do
			local c = silentBuf[i]
			c.nils = (c.nils or 0) + 1
			if c.nils >= ITEM_GIVE_UP then c.dead = true end
		end
	end
	if hi and lo > hi then lo = hi end
	return lo, hi
end
S.MeasureRange = measureRange

-- Is the unit beyond `reach` yards? For the plates' range fade, which needs only
-- that: the checks reaching at least that far are asked, nearest first, and the
-- first answer decides (out of one: beyond; inside one: not, the farther ones say
-- the same). Usually one call instead of the whole ladder. nil: nothing answered.
function S.Beyond(unit, reach, list)
	list = list or checks
	local protectedOK
	for i = 1, #list do
		local c = list[i]
		if c.max >= reach and c.min == 0 and not c.dead then
			if c.kind ~= "spell" and protectedOK == nil then
				protectedOK = not InCombatLockdown() or read(UnitCanAttack, "player", unit) == true
			end
			if c.kind == "spell" or protectedOK then
				local r
				if c.kind == "spell" then r = read(C_Spell.IsSpellInRange, c.id, unit)
				elseif c.kind == "item" then r = read(c.fn, c.id, unit)
				else r = read(CheckInteractDistance, unit, c.idx) end
				if r ~= nil then return not (r == true or r == 1) end
			end
		end
	end
	return nil
end

-- One distance for plotting. With an upper bound it is the bracket midpoint;
-- with only a floor ("beyond 28 yd") it keeps a previous estimate that still fits,
-- else floor + 5. Friendly units only answer the interact checks, so a floor
-- without a ceiling is common past 28 yd.
local function rangeEstimate(lo, hi, prev)
	if hi then return (lo + hi) / 2 end
	if lo and lo > 0 then
		if prev and prev >= lo then return prev end
		return lo + 5
	end
	return prev
end
S.RangeEstimate = rangeEstimate

---------------------------------------------------------------------------
-- Own state
---------------------------------------------------------------------------
local function updateSelf()
	local me = S.self
	-- UnitPosition returns the north axis first, then the west axis (measured on
	-- Forever: Redridge reads -9448, -2252). x = north, y = west throughout SITREP.
	local x, y, _, inst = read(UnitPosition, "player")
	me.x, me.y, me.inst = x, y, inst
	local _, class = read(UnitClass, "player")
	me.class = class or me.class
	me.level = read(UnitLevel, "player") or me.level or 60
	me.faction = read(UnitFactionGroup, "player") or me.faction
	me.combat = read(UnitAffectingCombat, "player") or false
	me.guid = me.guid or read(UnitGUID, "player")
end
S.UpdateSelf = updateSelf

---------------------------------------------------------------------------
-- Classification
---------------------------------------------------------------------------
-- Can you fight it? Players, pets and NPCs alike (what the unit frames need).
local function isEnemy(unit)
	if read(UnitExists, unit) == false then return false end
	if read(UnitIsDeadOrGhost, unit) then return false end
	local can = read(UnitCanAttack, "player", unit)
	if can ~= nil then return can end
	local enemy = read(UnitIsEnemy, "player", unit)
	if enemy ~= nil then return enemy end
	local fac = read(UnitFactionGroup, unit)
	return fac ~= nil and S.self.faction ~= nil and fac ~= S.self.faction
end
S.IsEnemy = isEnemy

-- A hostile contact for the picture: enemy players (NPCs only when switched on).
local function isHostile(unit)
	if read(UnitIsPlayer, unit) == false and not ns.P.sensors.npcs then return false end
	return isEnemy(unit)
end
S.IsHostile = isHostile

-- (the GUID read on this tick, for Allies: not asked twice)
S.plateGUID = {}
function S.PlateKind(unit, now)
	local guid = read(UnitGUID, unit)
	S.plateGUID[unit] = guid
	local k = plateKinds[unit]
	-- (enemies are asked every tick; a friend only whether you may attack it now: a
	-- duel starts without an event)
	if k and guid and k.guid == guid and now - k.at < KIND_KEEP and k.kind ~= "hostile"
		and not (k.kind == "friend" and read(UnitCanAttack, "player", unit)) then
		return k.kind
	end
	local kind = "other"
	if isHostile(unit) then kind = "hostile"
	elseif read(UnitIsPlayer, unit) and read(UnitIsFriend, "player", unit) then kind = "friend" end
	if not k then k = {}; plateKinds[unit] = k end
	k.guid, k.kind, k.at = guid, kind, now
	return kind
end

---------------------------------------------------------------------------
-- What a creature's GUID tells: Creature-0-server-instance-zoneUID-npcID-spawnUID.
-- The last six hex digits of the spawn UID are the second the creature spawned,
-- counted on the server's clock modulo 2^23 (about 97 days): with the server's
-- time that is how long it has been up. The zoneUID names the copy of the zone
-- (the layer): another one on the same map means you changed layers.
---------------------------------------------------------------------------
local WRAP = 2 ^ 23
function S.GuidParts(guid)
	if type(guid) ~= "string" then return nil end
	local kind, zone, npc, spawn = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-(%d+)%-(%x+)$")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(zone), tonumber(npc), spawn
end
-- Seconds since the creature spawned (nil: not a creature, or no plausible answer).
function S.SpawnAge(guid, serverNow)
	local _, _, spawn = S.GuidParts(guid)
	if not spawn or #spawn < 6 then return nil end
	serverNow = serverNow or (GetServerTime and GetServerTime())
	if not serverNow then return nil end
	local at = tonumber(spawn:sub(-6), 16) % WRAP
	local age = (serverNow % WRAP - at) % WRAP
	if age > 86400 then return nil end -- (over a day: this client may not count that way)
	return age
end

-- The layer, from the creatures on the plates (asked once a second): the zoneUID
-- most of them share. Another one on the same map, seen on at least LAYER_MIN
-- creatures: SR_LAYER (new, old). A new map starts over without a word.
S.layer = { map = nil, id = nil }
local LAYER_MIN = 3
local layerVotes = {}
function S.LayerScan()
	local map = C_Map and C_Map.GetBestMapForUnit and read(C_Map.GetBestMapForUnit, "player")
	wipe(layerVotes)
	local best, bestN = nil, 0
	for _, guid in pairs(S.plateGUID) do
		local zone = S.GuidParts(guid)
		if zone then
			local n = (layerVotes[zone] or 0) + 1
			layerVotes[zone] = n
			if n > bestN then best, bestN = zone, n end
		end
	end
	local L = S.layer
	if not best then return end
	if map ~= L.map then
		L.map, L.id = map, best
	elseif best ~= L.id and bestN >= LAYER_MIN then
		local old = L.id
		L.id = best
		ns.Fire("SR_LAYER", best, old)
	elseif not L.id then
		L.id = best
	end
end

---------------------------------------------------------------------------
-- Toughness: a player's maximum health against what players of that class and
-- level have, learned from everyone SITREP sees (both factions; enemies on their
-- plates, and your group, your target and whoever is under the mouse). Kept in
-- SITREP_DB.toughness as one entry per class and level: a running mean and spread
-- (no single values; at most 9 classes x 60 levels). The newest TOUGH_KEEP count
-- most, so the averages follow gear over the months.
-- Each player counts once in SEEN_DAYS days (SITREP_DB.toughSeen: GUID and day),
-- not once per session: the same few players met again and again would make the
-- average theirs.
-- Too few of a class at that exact level: its neighbours up to NEAR_LV levels away
-- help, each scaled to the level asked for (health grows about as level^GROWTH),
-- nearer levels weighing more. So a mark shows after a handful of meetings.
-- The averages are learned WITHOUT health buffs (Data.HEALTH_BUFFS, taken off when
-- the aura data can be read: out of combat); a player is judged with the health
-- they have, buffs and all: they are that much tougher in the fight. Labels go by
-- the spread: more than one spread below the mean LOW, above HIGH, two above VERY
-- HIGH. Druids in a form that changes health are not counted. Racials work like
-- buffs: the tauren's Endurance (+5 % health) is taken off for the averages
-- (Data.HEALTH_RACIAL).
-- Why a player was not counted (health hidden, buffs unreadable, a form) is kept
-- per player for the session: /sitrep tough.
---------------------------------------------------------------------------
local TOUGH_MIN, TOUGH_KEEP, SEEN_DAYS, NEAR_LV, GROWTH = 8, 400, 7, 4, 1.3
S.TOUGH_MIN, S.SEEN_DAYS, S.NEAR_LV = TOUGH_MIN, SEEN_DAYS, NEAR_LV
S.toughSeen, S.hpMaxOf, S.toughWhy = {}, {}, {}
local function toughBook()
	local db = ns.db
	if not db then return nil end
	db.toughness = db.toughness or {}
	return db.toughness
end
local function today()
	local t = read(GetServerTime) or (time and time()) or 0
	return math.floor(t / 86400)
end
-- counted in the last SEEN_DAYS days (also before this session)?
local function seenLately(guid)
	if S.toughSeen[guid] then return true end
	local db = ns.db
	local at = db and db.toughSeen and db.toughSeen[guid]
	return at ~= nil and today() - at < SEEN_DAYS
end
S.ToughSeenLately = seenLately
-- (old entries go at login)
function S.ToughForget()
	local db = ns.db
	if not (db and db.toughSeen) then return end
	local d = today()
	for guid, at in pairs(db.toughSeen) do if d - at >= SEEN_DAYS then db.toughSeen[guid] = nil end end
end
-- The health buffs on a unit: unbuffed health, and whether the auras could be read.
function S.Unbuffed(unit, hpMax)
	local U = C_UnitAuras
	if not (U and U.GetUnitAuraInstanceIDs and U.GetAuraDataByAuraInstanceID) then return hpMax, false end
	local ok, ids = pcall(U.GetUnitAuraInstanceIDs, unit, "HELPFUL")
	if not ok or type(ids) ~= "table" or ns.isSecret(ids) then return hpMax, false end
	local flat, pct = 0, 0
	for i = 1, #ids do
		local okD, d = pcall(U.GetAuraDataByAuraInstanceID, unit, ids[i])
		local id = okD and type(d) == "table" and not ns.isSecret(d) and ns.plain(d.spellId)
		local b = id and ns.Data.HEALTH_BUFFS[id]
		if b then
			flat = flat + (b.stam or 0) * 10 + (b.hp or 0)
			pct = pct + (b.pct or 0)
		end
	end
	return (hpMax - flat) / (1 + pct), true
end
function S.ToughSample(guid, class, level, hpMax)
	if not (guid and class and level and level > 0 and hpMax and hpMax > 0) then return end
	if seenLately(guid) then
		if not S.toughSeen[guid] then S.toughWhy[guid] = "known" end
		return
	end
	S.toughSeen[guid] = true
	S.toughWhy[guid] = "counted"
	local book = toughBook()
	if not book then return end
	ns.db.toughSeen = ns.db.toughSeen or {}
	ns.db.toughSeen[guid] = today()
	local key = class .. ":" .. level
	local e = book[key] or { n = 0, mean = 0, var = 0 }
	book[key] = e
	e.n = math.min(e.n + 1, TOUGH_KEEP)
	local a = 1 / e.n
	local d = hpMax - e.mean
	e.mean = e.mean + a * d
	e.var = (1 - a) * ((e.var or 0) + a * d * d) -- (the spread, weighted like the mean)
end
-- What players of a class have at a level: mean, spread, how many, and "exact"
-- (that level alone) or "near" (with its neighbours, scaled); nil: too few yet.
function S.ToughBase(class, level)
	local book = toughBook()
	if not (book and class and level and level > 0) then return nil end
	local e = book[class .. ":" .. level]
	if e and e.n >= TOUGH_MIN and e.mean > 0 then return e.mean, math.sqrt(e.var or 0), e.n, "exact" end
	local W, S1, S2, N = 0, 0, 0, 0
	for d = -NEAR_LV, NEAR_LV do
		local l = level + d
		local b = l > 0 and book[class .. ":" .. l]
		if b and b.n > 0 and b.mean > 0 then
			local k = (level / l) ^ GROWTH
			local w = b.n * (1 - math.abs(d) / (NEAR_LV + 1))
			local m = b.mean * k
			W, N = W + w, N + b.n
			S1 = S1 + w * m
			S2 = S2 + w * ((b.var or 0) * k * k + m * m)
		end
	end
	if N < TOUGH_MIN or W <= 0 then return nil end
	local mean = S1 / W
	return mean, math.sqrt(math.max(0, S2 / W - mean * mean)), N, "near"
end
-- hpMax over the average of its class and level, and how many spreads off it is
-- (nil: too few seen yet).
function S.ToughRatio(class, level, hpMax)
	if not hpMax then return nil end
	local mean, sd = S.ToughBase(class, level)
	if not mean then return nil end
	if sd < mean * 0.03 then sd = mean * 0.03 end -- (a handful of near-equal players: no spread to speak of)
	return hpMax / mean, (hpMax - mean) / sd
end
-- "LOW" / nil (about average) / "HIGH" / "VERY HIGH", with a colour; by the spread.
function S.ToughLabel(z)
	if not z then return nil end
	if z < -1 then return "LOW", 0.6, 0.72, 0.9 end
	if z <= 1 then return nil end
	if z <= 2 then return "HIGH", 1, 0.62, 0.25 end
	return "VERY HIGH", 1, 0.3, 0.25
end
-- A player: its sample once (plain values, without its health buffs), then its
-- ratio and spreads with the health it has now.
local SHIFTED = { [1] = true, [3] = true } -- a druid in bear (rage) or cat (energy) form
function S.Tough(unit, guid)
	local _, class = read(UnitClass, unit)
	local hp = read(UnitHealthMax, unit)
	if guid and hp then S.hpMaxOf[guid] = hp end
	hp = hp or (guid and S.hpMaxOf[guid])
	local level = read(UnitLevel, unit)
	if guid and not S.toughSeen[guid] then
		if not hp then S.toughWhy[guid] = S.toughWhy[guid] or "health"
		elseif class == "DRUID" and SHIFTED[read(UnitPowerType, unit) or 0] then S.toughWhy[guid] = "form"
		else
			local base, read_ = S.Unbuffed(unit, hp)
			local _, race = read(UnitRace, unit)
			base = base / (ns.Data.HEALTH_RACIAL[race or ""] or 1)
			if read_ then S.ToughSample(guid, class, level, base) else S.toughWhy[guid] = "auras" end
		end
	end
	if not hp then return nil end
	return S.ToughRatio(class, level, hp)
end
-- Players SITREP has no plate for: your group, your target, the one under the mouse.
function S.ToughUnit(unit)
	if read(UnitIsPlayer, unit) ~= true or read(UnitIsUnit, unit, "player") == true then return end
	local guid = read(UnitGUID, unit)
	if guid and not S.toughSeen[guid] then S.Tough(unit, guid) end
end
local groupAt = 0
ns.On("SR_TICK", function()
	local now = GetTime()
	if now - groupAt < 5 or not (IsInGroup and IsInGroup()) then return end
	groupAt = now
	local raid = IsInRaid and IsInRaid()
	for i = 1, raid and 40 or 4 do S.ToughUnit((raid and "raid" or "party") .. i) end
end)
ns.On("PLAYER_TARGET_CHANGED", function() S.ToughUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() S.ToughUnit("mouseover") end)
ns.On("SR_LOGIN", function() S.ToughForget() end)

-- /sitrep tough: what was counted this session and why not, what is known per class.
local WHY = { counted = "counted", known = "already counted in the last %d days", health = "health hidden by the client",
	auras = "buffs unreadable (counted later, out of combat)", form = "druid in a form" }
function S.ToughReport()
	ns.Capture("tough", function()
		local tally, n = {}, 0
		for _, why in pairs(S.toughWhy) do tally[why] = (tally[why] or 0) + 1; n = n + 1 end
		ns.print("toughness: %d players met this session", n)
		for _, why in ipairs({ "counted", "known", "health", "auras", "form" }) do
			if tally[why] then ns.print("  %d %s", tally[why], string.format(WHY[why], SEEN_DAYS)) end
		end
		local classes, list = {}, {}
		for key, e in pairs(toughBook() or {}) do
			local c, l = key:match("^(%u+):(%d+)$")
			if c then
				local t = classes[c] or { n = 0, lv = {} }
				classes[c] = t
				t.n = t.n + e.n
				t.lv[#t.lv + 1] = tonumber(l)
			end
		end
		for c in pairs(classes) do list[#list + 1] = c end
		table.sort(list)
		if #list == 0 then ns.print("nothing learned yet") end
		for _, c in ipairs(list) do
			local t = classes[c]
			table.sort(t.lv)
			ns.print("  %s: %d seen, levels %s", c, t.n, table.concat(t.lv, " "))
		end
		local _, class = read(UnitClass, "player")
		local lvl = read(UnitLevel, "player")
		local mean, _, cnt, how = S.ToughBase(class, lvl)
		local r = S.MyTough()
		if r then ns.print("you: HP %+.0f%% against %d %s players %s", (r - 1) * 100, cnt, tostring(class),
			how == "exact" and ("of level " .. lvl) or ("around level " .. lvl))
		else ns.print("you: not enough %s players near level %s yet (%d needed)", tostring(class), tostring(lvl), TOUGH_MIN) end
		local seen = 0
		for _ in pairs(ns.db and ns.db.toughSeen or {}) do seen = seen + 1 end
		ns.print("players remembered (each counts once in %d days): %d", SEEN_DAYS, seen)
	end)
end

-- Yours, against your own class and level.
function S.MyTough()
	local _, class = read(UnitClass, "player")
	return S.ToughRatio(class, read(UnitLevel, "player"), read(UnitHealthMax, "player"))
end

local function unitKey(unit)
	local guid = read(UnitGUID, unit)
	if guid then return guid end
	local name = read(GetUnitName, unit, true)
	if name then return "N:" .. name end
	-- Identity fully secret: track the unit token itself (stable while its plate lives).
	return "U:" .. unit
end
S.UnitKey = unitKey

---------------------------------------------------------------------------
-- Closure rate. Brackets are coarse (0-10, 10-20, 20-28 …), but the moment a
-- contact moves into a neighbouring bracket it is exactly on the shared
-- boundary. Two crossings give a speed: negative = closing on you.
---------------------------------------------------------------------------
local CLOSURE_WINDOW = 5    -- seconds two crossings may be apart
local CLOSURE_STALE = 3     -- seconds without a crossing before the rate is dropped

local function trackClosure(c, pl, ph, lo, hi, now)
	local b
	if hi and pl and hi <= pl then b = hi        -- moved inward; the nearest boundary crossed is its new ceiling
	elseif ph and lo and lo >= ph then b = lo    -- moved outward; past its old ceiling
	end
	if not b then return end
	local last = c.cross
	if last and now - last.t <= CLOSURE_WINDOW and now - last.t > 0.1 and b ~= last.d then
		c.closing = (b - last.d) / (now - last.t)
		c.closingAt = now
	end
	c.cross = c.cross or {}
	c.cross.t, c.cross.d = now, b
end
S.TrackClosure = trackClosure

---------------------------------------------------------------------------
-- Observation
---------------------------------------------------------------------------
local tickSeen = {}

function S.Observe(unit, source, now, light)
	if not isHostile(unit) then return end
	local key = unitKey(unit)
	if not key or tickSeen[key] then return end
	tickSeen[key] = true

	local c = S.contacts[key]
	local isNew = not c
	if isNew then
		c = { key = key, first = now }
		S.contacts[key] = c
	end
	c.last, c.net, c.source = now, nil, source
	c.name = read(GetUnitName, unit, false) or c.name or "Unknown"
	c.fullName = read(GetUnitName, unit, true) or c.fullName -- with realm, for exact targeting
	local _, class = read(UnitClass, unit)
	c.class = class or c.class
	c.level = read(UnitLevel, unit) or c.level
	c.npc = read(UnitIsPlayer, unit) == false
	c.guild = read(GetGuildInfo, unit) or c.guild
	c.faction = read(UnitFactionGroup, unit) or c.faction

	if light then return c, isNew end -- sighted through a group member: identity only

	c.unit, c.lastLive = unit, now
	c.inCombat = read(UnitAffectingCombat, unit) or false
	c.targetingMe = read(UnitIsUnit, unit .. "target", "player") or false
	c.casting = present(UnitCastingInfo, unit) or present(UnitChannelInfo, unit)

	local lo, hi = measureRange(unit, source == "plate" and ns.P.sensors.plateRange or nil)
	trackClosure(c, c.lo, c.hi, lo, hi, now)
	c.lo, c.hi = lo, hi
	c.range = rangeEstimate(lo, hi, c.range)
	return c, isNew
end

-- A contact reported over the addon channel by a group member: who, not where
-- (its distance from them says nothing about its distance from you).
function S.Ingest(msg, sender, now)
	local c = S.contacts[msg.key]
	if c and c.lastLive and now - c.lastLive < 2 then return end -- our own eyes win
	local isNew = not c
	if isNew then
		c = { key = msg.key, first = now }
		S.contacts[msg.key] = c
	end
	c.name, c.class, c.level = msg.name, msg.class, msg.level
	c.last, c.net, c.unit = now - (msg.age or 0), sender, nil
	if isNew then c.range, c.lo, c.hi = nil, nil, nil end
	c.targetingMe, c.casting, c.inCombat = false, false, msg.combat
	if isNew then ns.Fire("SR_NEW_CONTACT", c) end
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
local EXTRA = { "target", "focus", "mouseover", "targettarget", "pettarget" }
local PLATE_TOKENS = {}
for i = 1, 40 do PLATE_TOKENS[i] = "nameplate" .. i end

local function groupTargets(now)
	if not (ns.P.sensors.groupTargets and IsInGroup and IsInGroup()) then return end
	local raid = IsInRaid()
	local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	local prefix = raid and "raid" or "party"
	for i = 1, n do
		local c, isNew = S.Observe(prefix .. i .. "target", "ally", now, true)
		if isNew then ns.Fire("SR_NEW_CONTACT", c) end
	end
end

function S.Tick()
	local now = GetTime()
	local P = ns.P.sensors
	local me = S.self
	updateSelf()
	wipe(tickSeen)
	local st = S.stats
	st.rangeAsked, st.rangeAnswered, st.plates = 0, 0, 0

	-- Sweep the plate tokens directly, once a second: on Forever the add event can
	-- arrive before the unit is populated, so events alone may miss plates. Drop
	-- tokens that went away (every tick).
	if now - (S.lastSweep or 0) >= SWEEP_EVERY then
		S.lastSweep = now
		for i = 1, 40 do
			local u = PLATE_TOKENS[i]
			if not plates[u] and read(UnitExists, u) then plates[u] = true; st.swept = st.swept + 1 end
		end
	end
	for u in pairs(plates) do
		if read(UnitExists, u) == false then plates[u] = nil; S.plateGUID[u] = nil end
	end

	wipe(friendPlates)
	for unit in pairs(plates) do
		local kind = S.PlateKind(unit, now)
		if kind == "hostile" then
			st.plates = st.plates + 1
			local c, isNew = S.Observe(unit, "plate", now)
			if isNew then ns.Fire("SR_NEW_CONTACT", c) end
		elseif kind == "friend" then
			friendPlates[#friendPlates + 1] = unit
		end
	end
	for _, unit in ipairs(EXTRA) do
		local c, isNew = S.Observe(unit, unit, now)
		if isNew then ns.Fire("SR_NEW_CONTACT", c) end
	end
	groupTargets(now)

	-- Age and forget everything we are not looking at right now.
	local list = wipe(S.list)
	for key, c in pairs(S.contacts) do
		local age = now - c.last
		if age > P.memory then
			S.contacts[key] = nil
		else
			c.age = age
			c.live = c.lastLive ~= nil and (now - c.lastLive) < 1.0 and not c.net
			if not c.live then
				c.unit = nil
				c.targetingMe, c.casting = false, false
			end
			if c.closingAt and (now - c.closingAt > CLOSURE_STALE or not c.live) then c.closing, c.closingAt = nil, nil end
			list[#list + 1] = c
		end
	end

	if now - (S.layerAt or 0) >= 1 then
		S.layerAt = now
		local okL, errL = pcall(S.LayerScan)
		if not okL then ns.error(errL) end
	end
	local okFeeds, feedErr = pcall(S.UpdateFeeds) -- status reporting must never stop the picture
	if not okFeeds then ns.error(feedErr) end
	ns.Fire("SR_SENSED", list, now)
end

---------------------------------------------------------------------------
-- Friendly force, for the engagement calculus.
---------------------------------------------------------------------------
local friendly = {}
-- (the entries are reused from tick to tick: forty friendly plates in a town)
local function friend(n, class, level, hp, unit)
	local f = friendly[n]
	if not f then f = {}; friendly[n] = f end
	f.class, f.level, f.hp, f.unit = class, level, hp, unit
end
function S.Friendlies()
	local me = S.self
	local n = 1
	friend(1, me.class, me.level, ns.Pressure and ns.Pressure.HealthFrac() or 1, "player")
	if IsInGroup and IsInGroup() then
		local raid = IsInRaid()
		local members = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
		local prefix = raid and "raid" or "party"
		for i = 1, members do
			local u = prefix .. i
			-- a group member you are dueling is not on your side
			if not read(UnitIsUnit, u, "player") and read(UnitInRange, u) and not read(UnitIsDeadOrGhost, u)
				and not read(UnitCanAttack, "player", u) then
				local _, class = read(UnitClass, u)
				local h, m = read(UnitHealth, u), read(UnitHealthMax, u)
				n = n + 1
				friend(n, class, read(UnitLevel, u), (h and m and m > 0) and h / m or 1, u)
			end
		end
	end
	-- friendly plates outside the group: class and level from the allies' records
	-- (the last tick's; Allies reads them), not asked again here
	local A = ns.Allies
	for _, unit in ipairs(friendPlates) do
		local a = A and A.ForUnit(unit)
		if a then
			if not a.group then n = n + 1; friend(n, a.class, a.level, 1, unit) end
		elseif not (read(UnitInParty, unit) or read(UnitInRaid, unit)) then
			local _, class = read(UnitClass, unit)
			n = n + 1
			friend(n, class, read(UnitLevel, unit), 1, unit)
		end
	end
	for i = #friendly, n + 1, -1 do friendly[i] = nil end
	return friendly
end

---------------------------------------------------------------------------
-- Sensor health
---------------------------------------------------------------------------
function S.UpdateFeeds()
	local st, me = S.stats, S.self
	ns.Feed("plates", C_NamePlate and "LIVE" or "DARK", st.plates .. " hostile plates")
	if st.rangeAsked > 0 then
		local r = st.rangeAnswered / st.rangeAsked
		ns.Feed("range", r > 0.6 and "LIVE" or r > 0 and "PARTIAL" or "SECRET",
			string.format("%d checks, %.0f%% answered", #checks, r * 100))
	elseif not ns.feeds.range then
		ns.Feed("range", "IDLE", #checks .. " checks armed")
	end
	ns.Feed("position", me.x and "LIVE" or "DARK", me.x and "exact group distances" or "restricted here")

	local tgt = read(UnitExists, "target")
	if tgt then
		local ok, h = pcall(UnitHealth, "target")
		ns.Feed("health", not ok and "DARK" or ns.isSecret(h) and "SECRET" or "LIVE", ns.isSecret(h) and "bars only, no maths" or "")
		local ok2, n = pcall(UnitName, "target")
		ns.Feed("identity", ok2 and not ns.isSecret(n) and "LIVE" or "SECRET")
	end
	local secretAuras = C_Secrets and read(C_Secrets.ShouldAurasBeSecret)
	ns.Feed("auras", secretAuras and "LOCKED" or "LIVE", secretAuras and "locked in combat" or "")
	local restricted = C_CombatLog and read(C_CombatLog.IsCombatLogRestricted)
	if restricted == nil then restricted = not (CombatLogGetCurrentEventInfo) end
	ns.Feed("combatlog", restricted and "DARK" or "LIVE", restricted and "not needed" or "")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Forbidden plates (ones the client keeps from addons) announce themselves with
-- their own events. Their unit tokens still work for identity and range checks,
-- even though their screen position cannot be read.
local function plateAdded(_, unit)
	plates[unit] = true
	S.stats.plateEvents = S.stats.plateEvents + 1
end
ns.On("NAME_PLATE_UNIT_ADDED", plateAdded)
ns.On("FORBIDDEN_NAME_PLATE_UNIT_ADDED", plateAdded)
ns.On("FORBIDDEN_NAME_PLATE_UNIT_REMOVED", function(_, unit) plates[unit] = nil; plateKinds[unit] = nil end)
---------------------------------------------------------------------------
-- Stealth: a plate gone is far away, dead, or no longer seen. An enemy rogue,
-- druid or night elf whose plate goes while it is close, alive and was seen just
-- now has gone into stealth (or vanished): SR_STEALTH (contact, yards), for an AoE.
-- With "show nameplates off-screen" a plate leaves only for those reasons; without
-- it turning the camera hides plates too, so then only an enemy that targets you
-- or is your target counts. Confirmed after STEALTH_CONFIRM s: a plate handed
-- straight to the same unit again (frames are reused) is no stealth.
---------------------------------------------------------------------------
local STEALTH_NEAR, STEALTH_CONFIRM = 30, 0.4
local STEALTHY = { ROGUE = true, DRUID = true }
function S.StealthCheck(unit, now)
	local key = S.plateGUID[unit] or unitKey(unit)
	local c = key and S.contacts[key]
	if not c or c.npc or not c.lastLive or now - c.lastLive > 1 then return nil end
	local _, race = read(UnitRace, unit)
	if not (STEALTHY[c.class or ""] or race == "NightElf") then return nil end
	if read(UnitIsDeadOrGhost, unit) or read(UnitIsDeadOrGhost, "player") then return nil end
	local d = c.hi or c.range
	if not d or d > STEALTH_NEAR then return nil end
	local offscreen = GetCVar and GetCVar("nameplateShowOffscreen") == "1"
	if not (offscreen or c.targetingMe or read(UnitIsUnit, unit, "target")) then return nil end
	local gone = now
	C_Timer.After(STEALTH_CONFIRM, function()
		if c.lastLive and c.lastLive > gone then return end -- seen again: a reused plate
		ns.Fire("SR_STEALTH", c, d)
	end)
	return c
end

ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
	if ns.P and ns.P.alerts.stealth then
		local ok, err = pcall(S.StealthCheck, unit, GetTime())
		if not ok then ns.error(err) end
	end
	plates[unit] = nil; plateKinds[unit] = nil; S.plateGUID[unit] = nil
end)
for _, e in ipairs({ "DUEL_REQUESTED", "DUEL_FINISHED", "UNIT_FACTION" }) do
	ns.On(e, function() wipe(plateKinds) end)
end

ns.On("SPELLS_CHANGED", function() if ns.P then S.BuildRangeChecks() end end)
-- range items whose data was still loading: picked up again, out of combat, for a minute
ns.On("SR_TICK", function()
	if not (S.itemsPending and ns.P) or InCombatLockdown() then return end
	local now = GetTime()
	if (S.itemRetries or 0) >= ITEM_RETRIES or now - (S.itemRetryAt or 0) < ITEM_RETRY then return end
	S.itemRetries, S.itemRetryAt = (S.itemRetries or 0) + 1, now
	S.BuildRangeChecks()
end)
ns.On("SR_LOGIN", function()
	updateSelf()
	S.BuildRangeChecks()
	ns.Feed("damage", ns.knownEvents.UNIT_COMBAT and "LIVE" or "DARK", "UNIT_COMBAT amounts")
	ns.Feed("combatlog", "DARK", "not needed")
end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "sensors.useSpellRange" or key == "sensors.useInteract" or key == "sensors.useItemRange" then S.BuildRangeChecks() end
end)
ns.On("PLAYER_ENTERING_WORLD", function()
	wipe(plates); wipe(friendPlates); wipe(plateKinds); wipe(S.contacts)
end)
ns.On("SR_TICK", function() S.Tick() end)

-- Test hooks
S._plates, S._friendPlates = plates, friendPlates
S._plateKinds = plateKinds
