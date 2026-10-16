-- SITREP · Casts on you
-- The combat log is closed to addons on Forever, so "this spell was cast on you"
-- cannot be read. What can be: a hostile unit with a plate starts a cast or a
-- channel, and its target is you; most spells go to the caster's target. Looked
-- at the moment a cast starts, when the caster changes its target, when its plate
-- appears mid-cast, and 10 times a second while a hostile cast runs (mobs often
-- take their target a moment after starting); gone when the cast ends.
--   I.casts[unit] = { unit, onMe (true, or nil when the client keeps it secret),
--     raw (the answer as the client gave it), name and icon (may be secret), startMS,
--     endMS, channel, caster, fullName (with realm), class, player, isTarget }
-- A secret "is its target me" still drives the plate's marker (the client turns
-- it into an alpha); counts and the banner need a plain answer.
-- Bus: SR_INCOMING(cast) once per cast known to be on you; SR_INCOMING_CHANGED.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format = string.format

local I = {}
ns.Incoming = I
I.casts = {}
-- hostile casts being watched (their target is looked at again while they run:
-- mobs often take their target a moment after the cast has started)
local watched = {}
I.watched = watched
local RECHECK_EVERY = 0.1

local function isPlate(unit) return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil end

-- /sitrep castprobe: every hostile cast start and what SITREP made of it, for two
-- minutes, straight into the saved report castprobe (written on /reload).
local probeUntil = 0
local function desc(v)
	if v == nil then return "nil" end
	if ns.isSecret(v) then return "secret" end
	return tostring(v)
end
local function note(fmt, ...)
	if GetTime() > probeUntil or not SITREP_DB then return end
	local r = SITREP_DB.reports and SITREP_DB.reports.castprobe
	if not r then return end
	if #r.lines >= 200 then return end
	r.lines[#r.lines + 1] = format("%s  " .. fmt, date("%H:%M:%S"), ...)
end
I.Note = note

function I.Probe()
	SITREP_DB.reports = SITREP_DB.reports or {}
	SITREP_DB.reports.castprobe = { at = date("%Y-%m-%d %H:%M:%S"), version = ns.VERSION, lines = {} }
	probeUntil = GetTime() + 120
	local ui = ns.IncomingUI
	local lines = SITREP_DB.reports.castprobe.lines
	lines[1] = format("setup: display %s, plates.incoming %s, alerts.incoming %s", ui and "loaded" or "MISSING",
		tostring(ns.P.plates.incoming), tostring(ns.P.alerts.incoming))
	ns.print("cast probe: recording enemy casts for 2 minutes; let something cast at you, then /reload.")
end

local function clear(unit)
	if I.casts[unit] then
		I.casts[unit] = nil
		ns.Fire("SR_INCOMING_CHANGED")
	end
end
I.Clear = clear

-- Look at one plate unit: casting at you or not.
function I.Look(unit, event)
	if not isPlate(unit) then return end
	local was = I.casts[unit]
	local channel = false
	local ok, name, _, icon, startMS, endMS = pcall(UnitCastingInfo, unit)
	if not (ok and name ~= nil) then
		channel = true
		ok, name, _, icon, startMS, endMS = pcall(UnitChannelInfo, unit)
	end
	local casting = ok and name ~= nil
	local okA, attack = pcall(UnitCanAttack, "player", unit)
	local okT, raw = pcall(UnitIsUnit, unit .. "target", "player")
	local hostileCast = casting and plain(attack) == true
	watched[unit] = hostileCast or nil
	if hostileCast and I.watcher then I.watcher:Show() end
	-- looking again: only a change of "on me" counts (and is noted)
	if event == "RECHECK" then
		local now = okT and raw ~= nil and plain(raw) or false
		local before = was and was.onMe
		if was and now ~= false and ns.isSecret(raw) == ns.isSecret(was.raw) and now == before then return end
		if not was and now == false then return end
	end
	if casting or event ~= "NAME_PLATE_UNIT_ADDED" then
		note("%s %s: casting %s (%s), times %s-%s, can attack %s, its target is me %s", tostring(event), unit,
			casting and desc(name) or "no", channel and "channel" or "cast", desc(startMS), desc(endMS),
			okA and desc(attack) or "error", okT and desc(raw) or "error")
	end
	if not casting or plain(attack) ~= true then return clear(unit) end
	if not okT or raw == nil then return clear(unit) end
	local onMe = plain(raw)
	if onMe == false then return clear(unit) end
	local _, class = read(UnitClass, unit)
	local c = {
		unit = unit, onMe = onMe, raw = raw, name = name, icon = icon, startMS = plain(startMS), endMS = plain(endMS),
		channel = channel, caster = read(GetUnitName, unit, false), fullName = read(GetUnitName, unit, true), class = class,
		player = read(UnitIsPlayer, unit) == true,
		isTarget = read(UnitIsUnit, unit, "target") == true,
	}
	I.casts[unit] = c
	if onMe == true and not (was and was.onMe == true) then ns.Fire("SR_INCOMING", c) end
	ns.Fire("SR_INCOMING_CHANGED")
	local s = ns.Plates and ns.Plates.Current()[unit]
	note("  -> on me (%s): %d known on me, plate box %s", onMe == true and "plain" or "secret: the client decides the box",
		#I.Mine(), s and s.inc and (s.inc:IsShown() and "SHOWN" or "hidden") or "no SITREP plate")
end

-- The casts known to be on you, the one landing first first.
function I.Mine()
	local list, nowMS = {}, GetTime() * 1000
	for unit, c in pairs(I.casts) do
		if c.onMe == true then
			if c.endMS and c.endMS < nowMS - 500 then I.casts[unit] = nil else list[#list + 1] = c end
		end
	end
	table.sort(list, function(a, b) return (a.endMS or math.huge) < (b.endMS or math.huge) end)
	return list
end

-- while hostile casts run: look at their target again
I.watcher = CreateFrame("Frame")
I.watcher:Hide()
local acc = 0
I.watcher:SetScript("OnUpdate", ns.Timed("casts: re-check (I.watcher)", function(self, e)
	acc = acc + e
	if acc < RECHECK_EVERY then return end
	acc = 0
	if not next(watched) then self:Hide() return end
	for unit in pairs(watched) do I.Look(unit, "RECHECK") end
end))

for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED" }) do
	ns.On(e, function(event, unit) I.Look(unit, event) end)
end
for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"NAME_PLATE_UNIT_REMOVED" }) do
	ns.On(e, function(_, unit)
		if isPlate(unit) then
			watched[unit] = nil
			clear(unit)
		end
	end)
end

---------------------------------------------------------------------------
-- Kick trainer and lockouts. Your own casts are plain: an interrupt of yours
-- (Data.INTERRUPTS, by spell ID or by name for every rank) that lands within
-- KICK_MATCH s of a hostile cast being interrupted was yours: the caster's school
-- is locked for the spell's lockout (I.locks[key], LOCKED on its plate), and the
-- trainer counts your reaction (from its cast start). A hostile cast that went
-- through while your interrupt was ready and in range: a missed kick. A hostile
-- cast broken off early that no interrupt of yours explains: a fake (I.fakes[key];
-- FAKER on a plate after FAKER_AT of them). Per fight (I.fight, into the after
-- action review) and per session (/sitrep kicks).
---------------------------------------------------------------------------
local KICK_MATCH, FAKE_EARLY, FAKER_AT = 0.4, 1.0, 3
I.locks, I.fakes = {}, {}
local function newStats() return { landed = 0, react = 0, missed = 0, fakes = 0 } end
I.fight, I.session = newStats(), newStats()
local byId, byName = {}, {}
local started = {}      -- [key] = { t, key }: hostile player casts running (one per caster,
                        -- whichever of its tokens reports: plate, target, focus)
local myKick            -- { t, entry }: your last interrupt
local enemyBroke = {}   -- { t, unit, key, start }: hostile casts interrupted lately

local function spellName(id)
	local info = C_Spell and C_Spell.GetSpellInfo and read(C_Spell.GetSpellInfo, id)
	return type(info) == "table" and info.name or nil
end
function I.BuildInterrupts()
	wipe(byId); wipe(byName)
	for _, e in ipairs(ns.Data.INTERRUPTS) do
		byId[e.id] = e
		local n = spellName(e.id)
		if n then byName[n] = e end
	end
end
function I.InterruptOf(spellID)
	if not spellID then return nil end
	return byId[spellID] or byName[spellName(spellID) or ""]
end
-- Your interrupt, if you know one (for "ready and in range").
function I.MyInterrupt()
	local known = IsPlayerSpell or IsSpellKnown
	for _, e in ipairs(ns.Data.INTERRUPTS) do
		if not e.pet and known and read(known, e.id) then return e end
	end
	return nil
end

local function hostilePlayer(unit)
	if unit == "player" or unit == "pet" then return nil end
	local key = ns.Sensors.UnitKey(unit)
	local c = key and ns.Sensors.contacts[key]
	if not c or c.npc then return nil end
	return key, c
end

local function credit(kick, broke)
	local e = kick.entry
	I.locks[broke.key] = { untilT = kick.t + e.lock, lock = e.lock }
	for _, st in ipairs({ I.fight, I.session }) do
		st.landed = st.landed + 1
		st.react = st.react + math.max(0, kick.t - broke.start)
	end
	broke.mine = true
	ns.Fire("SR_LOCKOUT", broke.key, e.lock)
end

function I.KickCast(unit, spellID, now)
	local e = I.InterruptOf(spellID)
	if not e then return end
	now = now or GetTime()
	myKick = { t = now, entry = e }
	-- the hostile cast it broke may have been reported first
	for _, b in ipairs(enemyBroke) do
		if not b.mine and math.abs(now - b.t) <= KICK_MATCH then credit(myKick, b) return end
	end
end

function I.EnemyStart(unit, now)
	local key = hostilePlayer(unit)
	if not key then return end
	local was = started[key]
	now = now or GetTime()
	if was and now - was.t < 0.1 then return end -- the same start through another token
	started[key] = { t = now, key = key }
end

function I.EnemyBroken(unit, now)
	local key = hostilePlayer(unit)
	local s = key and started[key]
	if key then started[key] = nil end
	if not s then return end
	now = now or GetTime()
	local b = { t = now, unit = unit, key = s.key, start = s.t }
	enemyBroke[#enemyBroke + 1] = b
	while enemyBroke[1] and now - enemyBroke[1].t > 2 do table.remove(enemyBroke, 1) end
	if myKick and math.abs(now - myKick.t) <= KICK_MATCH then credit(myKick, b) return end
	-- not ours (yet): broken off early is a fake, unless our interrupt follows in a
	-- moment (I.Settle decides once KICK_MATCH has passed)
	b.early = now - s.t <= FAKE_EARLY
end

-- Interrupts broken off early that no interrupt of yours explained: fakes.
function I.Settle(now)
	now = now or GetTime()
	for _, b in ipairs(enemyBroke) do
		if b.early and not b.mine and not b.settled and now - b.t > KICK_MATCH then
			b.settled = true
			I.fakes[b.key] = (I.fakes[b.key] or 0) + 1
			I.fight.fakes, I.session.fakes = I.fight.fakes + 1, I.session.fakes + 1
		end
	end
end
ns.On("SR_TICK", function() I.Settle() end)

function I.EnemyDone(unit, now)
	local key = hostilePlayer(unit)
	local s = key and started[key]
	if key then started[key] = nil end
	if not s then return end
	now = now or GetTime()
	-- went through: was your interrupt ready and in range?
	local e = I.MyInterrupt()
	if not e then return end
	local ready = not myKick or now - myKick.t >= e.cd
	local inRange = C_Spell and C_Spell.IsSpellInRange and read(C_Spell.IsSpellInRange, e.id, unit) == true
	if ready and inRange then I.fight.missed, I.session.missed = I.fight.missed + 1, I.session.missed + 1 end
end

-- LOCKED n s on a plate (nil: none)
function I.LockLeft(key, now)
	local l = key and I.locks[key]
	if not l then return nil end
	local left = l.untilT - (now or GetTime())
	if left <= 0 then I.locks[key] = nil return nil end
	return left
end
function I.IsFaker(key) return key ~= nil and (I.fakes[key] or 0) >= FAKER_AT end

-- "Kicks 3 of 5 · Ø 0.62 s · 2 fakes" (nil: nothing to say)
function I.KickLine(st)
	if not st or st.landed + st.missed + st.fakes == 0 then return nil end
	local parts = { format("Kicks %d of %d", st.landed, st.landed + st.missed) }
	if st.landed > 0 then parts[#parts + 1] = format("avg %.2f s", st.react / st.landed) end
	if st.fakes > 0 then parts[#parts + 1] = format("%d fake%s", st.fakes, st.fakes == 1 and "" or "s") end
	return table.concat(parts, "  ·  ")
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if unit == "player" or unit == "pet" then I.KickCast(unit, plain(spellID)) else I.EnemyDone(unit) end
end)
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START" }) do
	ns.On(e, function(_, unit) I.EnemyStart(unit) end)
end
ns.On("UNIT_SPELLCAST_INTERRUPTED", function(_, unit) I.EnemyBroken(unit) end)
ns.On("UNIT_SPELLCAST_FAILED", function(_, unit)
	local key = hostilePlayer(unit)
	if key then started[key] = nil end
end)
ns.On("PLAYER_REGEN_DISABLED", function() I.fight = newStats() end)
ns.On("SPELLS_CHANGED", function() I.BuildInterrupts() end)
ns.On("SR_LOGIN", function() I.BuildInterrupts() end)
