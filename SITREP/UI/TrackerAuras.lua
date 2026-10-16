-- SITREP · Trackers: auras, also in combat

local ADDON, ns = ...
local K = ns.Kit
local read, plain = ns.read, ns.plain
local format = string.format
local issecrettable = _G.issecrettable or function() return false end
local T = ns.Trackers
local spellName, spellIcon, learned, secretAny = T.SpellName, T.SpellIcon, T.Learned, T.SecretAny
local castsOn, known, targetKey = T._castsOn, T._known, T.TargetKey

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------
-- Is the item's aura on the unit? Returns "up", expires (nil = permanent),
-- duration; "missing"; or nil when the client will not say (combat).
---------------------------------------------------------------------------
-- Auras in combat. The client refuses every aura list and every aura's data
-- then, but it may still answer narrower questions:
--   * per spell: buffs Blizzard never hides can be read directly;
--   * per aura instance (the ID one application of a buff carries until it
--     ends): "is this one still there?", through calls built for drawing
--     timers and filtering.
-- What those answers mean is not assumed. Out of combat, where SITREP sees
-- everything, it asks every question about an aura it can see is there and
-- one it watched vanish, and keeps the questions whose two answers differ.
-- In combat it asks only those; one that turns secret or fails is dropped.
-- A buff that is dispelled, cancelled or runs out mid-fight is then known
-- exactly, not estimated.
---------------------------------------------------------------------------
local Oracle = { probes = {}, retired = {}, seen = {}, calibratedAt = nil }
T.how = {} -- [item.id] = how its last answer was reached in combat
T.Oracle = Oracle
local PROBES = {
	{ key = "filtered", label = "IsAuraFilteredOutByInstanceID",
		ask = function(u, id, f) return C_UnitAuras.IsAuraFilteredOutByInstanceID(u, id, f) end },
	{ key = "duration", label = "GetAuraDuration", ask = function(u, id) return C_UnitAuras.GetAuraDuration(u, id) end },
	{ key = "expires", label = "DoesAuraHaveExpirationTime", ask = function(u, id) return C_UnitAuras.DoesAuraHaveExpirationTime(u, id) end },
	{ key = "secrecy", label = "ShouldUnitAuraInstanceBeSecret", ask = function(u, id) return C_Secrets.ShouldUnitAuraInstanceBeSecret(u, id) end },
	{ key = "data", label = "GetAuraDataByAuraInstanceID", ask = function(u, id) return C_UnitAuras.GetAuraDataByAuraInstanceID(u, id) end },
}
for _, pr in ipairs(PROBES) do Oracle.probes[pr.key] = pr end
Oracle.order = PROBES

-- An answer reduced to a class that can be compared: err, nil, true, false, some.
-- A secret answer counts as "some": it proves something came back, nothing more.
local function classify(ok, v)
	if not ok then return "err" end
	if issecretvalue and issecretvalue(v) then return "some" end
	if v == nil then return "nil" end
	if v == true then return "true" end
	if v == false then return "false" end
	return "some"
end
Oracle.Classify = classify

-- Out of combat: learn which questions tell "there" from "gone".
function Oracle.Calibrate(unit, presentId, filter, now)
	local gone = Oracle.retired[#Oracle.retired] or 2147480000 -- an instance we saw end, else one that never was
	for _, pr in ipairs(PROBES) do
		local aP = classify(pcall(pr.ask, unit, presentId, filter))
		local aA = classify(pcall(pr.ask, unit, gone, filter))
		pr.tested = true
		pr.present, pr.absent = aP, aA
		-- usable: both answers plain and different (a secret "some" is fine for "there")
		pr.ok = aP ~= aA and aP ~= "err" and aA ~= "err" and aA ~= "some"
		pr.combatBad = nil
	end
	Oracle.calibratedAt = now
end

-- Out of combat, now and then: note instances that ended, recalibrate.
function Oracle.Maintain(now)
	local ids = ns.Auras.AuraIDs("player", "HELPFUL")
	if not ids then return end
	local cur = {}
	for _, id in ipairs(ids) do cur[id] = true end
	for id in pairs(Oracle.seen) do
		if not cur[id] then
			Oracle.retired[#Oracle.retired + 1] = id
			if #Oracle.retired > 8 then table.remove(Oracle.retired, 1) end
		end
	end
	Oracle.seen = cur
	if ids[1] and (not Oracle.calibratedAt or now - Oracle.calibratedAt > 60) then
		Oracle.Calibrate("player", ids[1], "HELPFUL", now)
	end
end

-- In combat: is this instance still there? true / false; "secret" plus the
-- secret yes/no and the probe when only the client may look at the answer
-- (then the client draws the icon, see drawItem); nil when nothing answers.
local function isBoolProbe(pr)
	return (pr.present == "true" or pr.present == "false") and (pr.absent == "true" or pr.absent == "false")
end
function Oracle.Ask(unit, id, filter)
	local secretAnswer
	for _, pr in ipairs(PROBES) do
		if pr.ok and not pr.combatBad then
			local ok, v = pcall(pr.ask, unit, id, filter)
			local c = classify(ok, v)
			pr.combatAnswer = (ok and secretAny(v)) and "secret" or c
			if pr.combatAnswer ~= "secret" and c == pr.present then return true, pr.label end
			if pr.combatAnswer ~= "secret" and c == pr.absent then return false, pr.label end
			if pr.combatAnswer == "secret" and isBoolProbe(pr) then
				-- a secret yes/no: unreadable here, but the client can still act on it
				secretAnswer = secretAnswer or { value = v, probe = pr }
			else
				pr.combatBad = true -- answers differently in combat: stop asking it this session
			end
		end
	end
	if secretAnswer then return "secret", secretAnswer end
	return nil
end

-- Spells the client never hides: read directly, also in combat.
-- Returns true + expires, false, or nil (not such a spell / no answer).
-- What each spell answered in combat, for the report: [spellID] = { secret, read, class }
Oracle.direct = {}
local function answerOf(ok, v)
	if not ok then return "err" end
	if secretAny(v) then return "secret" end
	if v == nil then return "nil" end
	return type(v) == "table" and "aura" or tostring(v)
end
function Oracle.Direct(unit, spellId, mineOnly)
	if not (spellId and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return nil end
	local okS, s = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellId)
	local rec
	if InCombatLockdown() then
		rec = Oracle.direct[spellId] or {}
		Oracle.direct[spellId] = rec
		rec.secret = answerOf(okS, s)
		if rec.class == nil and C_Secrets.GetSpellAuraSecrecy then
			rec.class = answerOf(pcall(C_Secrets.GetSpellAuraSecrecy, spellId))
		end
	end
	if not okS or plain(s) ~= false then return nil end
	local get = unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID or C_UnitAuras.GetUnitAuraBySpellID
	if not get then return nil end
	local ok, a
	if unit == "player" then ok, a = pcall(get, spellId) else ok, a = pcall(get, unit, spellId) end
	if rec then rec.read = answerOf(ok, a); rec.worked = rec.worked or (ok and not secretAny(a)) end
	if not ok or secretAny(a) then return nil end
	if a == nil then return false end
	if type(a) ~= "table" then return nil end
	if mineOnly then
		local src = plain(a.sourceUnit)
		if src and src ~= "player" and src ~= "pet" then return false end
	end
	local ex = plain(a.expirationTime)
	return true, (ex and ex > 0) and ex or math.huge
end

-- Spell-based lookups in combat. They describe nothing about a buff that is
-- there (refused: an error or a secret), but may still say plainly "nothing"
-- once it is gone. So: an answer that was refused in this fight and is now a
-- plain nil means the buff has gone. A lookup that was ever refused for a buff
-- that was there is trusted from then on (also in later fights), since it
-- does not just answer nil to everything.
local SPELL_PROBES = {
	{ key = "GetPlayerAuraBySpellID", ask = function(unit, id) if unit == "player" then return C_UnitAuras.GetPlayerAuraBySpellID(id) end return C_UnitAuras.GetUnitAuraBySpellID(unit, id) end },
	{ key = "GetUnitAuraBySpellID", ask = function(unit, id) return C_UnitAuras.GetUnitAuraBySpellID(unit, id) end },
	{ key = "GetAuraDataBySpellName", ask = function(unit, id, name, filter) return C_UnitAuras.GetAuraDataBySpellName(unit, name, filter) end },
}
Oracle.spellProbes = SPELL_PROBES
Oracle.fight = {} -- [item.id] = { refused = { [key] = true }, last = "answers" }

function Oracle.SpellLookup(item, unit, id, name, filter)
	if not (C_UnitAuras and id) then return nil end
	local P = ns.P.trackers
	P.trust = P.trust or {}
	local st = Oracle.fight[item.id] or { refused = {} }
	Oracle.fight[item.id] = st
	local verdict, answers = nil, {}
	for _, pr in ipairs(SPELL_PROBES) do
		local ok, v = pcall(pr.ask, unit, id, name, filter)
		local a = answerOf(ok, v)
		answers[#answers + 1] = pr.key .. "=" .. a
		if a == "aura" then
			verdict = true -- readable and there
		elseif a == "err" or a == "secret" then
			st.refused[pr.key] = true
			P.trust[pr.key] = true
		elseif a == "nil" and verdict == nil and (st.refused[pr.key] or P.trust[pr.key]) then
			verdict = false -- refused before, plain nothing now: gone
		end
	end
	st.answers = table.concat(answers, " ")
	return verdict
end

-- Blizzard's own aura icons. Its buff bar (your buffs) and target frame (your
-- target's auras) keep updating in combat: Blizzard's code may read auras.
-- SITREP cannot, but it can look at what those frames show: which buttons are
-- up and which icon each one displays. When those icons stay readable, "is my
-- buff's icon on the bar?" answers "is my buff on me?" exactly.
local BAR_ROOT = { player = "BuffFrame", target = "TargetFrame" }
function Oracle.Bar(unit)
	local root = _G[BAR_ROOT[unit] or ""]
	if not (root and root.GetChildren) then return nil end
	local okV, vis = pcall(root.IsVisible, root)
	if not okV or plain(vis) ~= true then
		-- SITREP fades Blizzard's target frame (alpha 0); it still runs, so only "shown" matters there
		local okS, sh = pcall(root.IsShown, root)
		if not okS or plain(sh) ~= true then return nil end
	end
	local info = { n = 0, icons = {}, secret = 0 }
	local function scan(f, depth)
		if depth > 5 then return end
		local ok, kids = pcall(function() return { f:GetChildren() } end)
		if not ok then return end
		for _, c in ipairs(kids) do
			local icon = type(c) == "table" and (rawget(c, "Icon") or rawget(c, "icon"))
			if icon and type(icon) == "table" and icon.GetTexture then
				local okS, sh = pcall(c.IsShown, c)
				if okS and plain(sh) == true then
					info.n = info.n + 1
					local get = icon.GetTextureFileID or icon.GetTexture
					local okT, t = pcall(get, icon)
					if not okT or secretAny(t) then info.secret = info.secret + 1
					elseif t ~= nil then info.icons[tostring(t)] = true end
				end
			end
			scan(c, depth + 1)
		end
	end
	scan(root, 0)
	return info
end

-- Is this icon on Blizzard's frame for the unit? true / false, nil when unknown.
function Oracle.OnBar(unit, icon)
	if not icon then return nil end
	local info = Oracle.Bar(unit)
	if not info then return nil end
	-- its icon readable on any button: there. "Gone" needs every icon readable.
	if info.icons[tostring(icon)] then return true end
	if info.secret > 0 then return nil end
	if info.n > 0 or unit == "player" then return false end
	return nil
end

function Oracle.BarSummary(unit)
	local info = Oracle.Bar(unit)
	if not info then return "not visible" end
	local n = 0
	for _ in pairs(info.icons) do n = n + 1 end
	return format("%d shown, %d icons readable, %d secret", info.n, n, info.secret)
end

-- Charge counting is on for a buff that showed charges, unless switched off.
function T.CountsHits(item)
	if item.kind ~= "self" then return false end
	if item.countHits ~= nil then return item.countHits end
	local L = ns.P.trackers.learned[item.spell]
	return L ~= nil and (L.charges or 0) > 1
end

-- A hit on you: a charge less on every counted buff. Only hits (not misses,
-- dodges, parries) of physical damage (school 1: melee swings and physical
-- attacks); spells do not use these charges. A school the client hides is
-- counted anyway, and the icon marked "?".
local SCHOOL_PHYSICAL = 1
ns.On("UNIT_COMBAT", function(_, unit, action, flag, amount, school)
	if unit ~= "player" or action ~= "WOUND" then return end
	local sc = plain(school)
	local physical = sc == SCHOOL_PHYSICAL
	local unknown = sc == nil
	local now = GetTime()
	if T.combatLog and #T.combatLog < 60 then
		T.combatLog[#T.combatLog + 1] = format("+%.1fs  hit on you: %s, school %s%s", now - (T.combatStart or now),
			tostring(plain(amount) or "?"), unknown and "unreadable" or tostring(sc), physical and " (physical)" or "")
	end
	if not (physical or unknown) then return end
	local key = targetKey("player") or "player"
	for _, it in ipairs(T.Items()) do
		local rec = known[it.id]
		if rec and rec.charges and T.CountsHits(it) and rec.charges[key] and rec.charges[key] > 0 then
			rec.charges[key] = rec.charges[key] - 1
			if unknown then rec.chargeUnsure = true end
			if T.combatLog and #T.combatLog < 60 then
				T.combatLog[#T.combatLog + 1] = format("+%.1fs    %s: %d charge%s left", now - (T.combatStart or now),
					it.name or tostring(it.spell), rec.charges[key], rec.charges[key] == 1 and "" or "s")
			end
		end
	end
	T.Refresh()
end)

-- How an icon is kept up to date in combat, in words (console, /sitrep buffs).
function T.CombatHow(item)
	if item.kind == "cd" then return "cooldowns: the client's swipe, your casts for the rest" end
	if item.kind == "weapon" then return "weapon: enchant data / tooltip, else your cast" end
	local id = item.auraId or (not item.aura and item.spell)
	local okS, s
	if id and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then okS, s = pcall(C_Secrets.ShouldSpellAuraBeSecret, id) end
	local d = id and Oracle.direct[id]
	if d and d.worked then return "in combat: exact (the client answered for this buff in the last fight)" end
	local usable = {}
	for _, pr in ipairs(PROBES) do if pr.ok and not pr.combatBad then usable[#usable + 1] = pr.label end end
	for _, pr in ipairs(PROBES) do
		if pr.ok and pr.combatAnswer == "secret" and isBoolProbe(pr) then
			return "in combat: shown or hidden by the client itself (" .. pr.label .. " answers secretly), estimated after a recast"
		end
	end
	if #usable > 0 then return "in combat: exact while the aura from before the fight lasts (" .. usable[1] .. "), estimated after a recast" end
	if T.CountsHits(item) then return "in combat: Blizzard's buff icons while readable, then its charges counted down on the physical hits you take" end
	if T.how[item.id] and T.how[item.id]:find("Blizzard", 1, true) then return "in combat: exact (read from Blizzard's own buff icons)" end
	local trust = ns.P.trackers.trust
	if trust and next(trust) then return "in combat: spell lookups (a refusal that turns into a plain 'nothing' = gone), else estimated" end
	if d then return "in combat: estimated (in the last fight the client said: secret " .. tostring(d.secret) .. ", read " .. tostring(d.read) .. ")" end
	if not Oracle.calibratedAt then return "in combat: not tested yet (fight once with the buff on you)" end
	return "in combat: estimated (this client answers no aura question in combat)"
end

-- /sitrep auraprobe: what was learned.
function T.DumpOracle()
	ns.print("Blizzard's buff bar now: %s", Oracle.BarSummary("player"))
	for _, it in ipairs(T.Items()) do
		local L = ns.P.trackers.learned[it.spell]
		if it.kind == "self" or it.kind == "target" then
			ns.print("  %s: its icon %s on Blizzard's frame (checked out of combat)", it.name or tostring(it.spell),
				L and L.barOk == true and "found" or L and L.barOk == false and "NOT found" or "not checked yet")
		end
	end
	for id, d in pairs(Oracle.direct) do
		ns.print("spell %d (%s) in combat: secrecy class %s, 'secret now?' %s, direct read %s%s", id, spellName(id) or "?",
			tostring(d.class), tostring(d.secret), tostring(d.read), d.worked and "  -> works" or "")
	end
	if not Oracle.calibratedAt then
		ns.print("aura checks: not learned yet. Have any buff on you, out of combat, for a second.")
		return
	end
	ns.print("aura checks learned %.0fs ago (there / gone):", GetTime() - Oracle.calibratedAt)
	for _, pr in ipairs(PROBES) do
		local verdict
		if not pr.ok then verdict = "not usable"
		elseif pr.combatBad then verdict = "|cffff8040dropped in combat|r"
		elseif pr.combatAnswer == "secret" and isBoolProbe(pr) then verdict = "|cff5cff8dusable: the client decides|r"
		else verdict = "|cff5cff8dusable|r" end
		ns.print("  %s: %s / %s  ->  %s%s", pr.label, tostring(pr.present), tostring(pr.absent), verdict,
			pr.combatAnswer and ("  (in combat it answered: " .. pr.combatAnswer .. ")") or "  (not asked in combat yet)")
	end
end

local function findAura(unit, item, helpful, mineOnly)
	local A = ns.Auras
	local ids = A.AuraIDs(unit, (helpful and "HELPFUL" or "HARMFUL") .. (mineOnly and "|PLAYER" or ""))
	if not ids then return nil end
	-- the aura to look for: the one you named (or its ID), else the spell itself
	local wantId = item.auraId or (not item.aura and item.spell) or nil
	local name = item.aura or (not item.auraId and (item.name or spellName(item.spell))) or nil
	for _, aid in ipairs(ids) do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aid)
		if not ok or type(a) ~= "table" or issecrettable(a) then return nil end
		local sid, an = plain(a.spellId), plain(a.name)
		if sid == nil and an == nil then return nil end
		if sid and an and T.Lib then T.Lib.seen[sid] = an end
		if (wantId and sid == wantId) or (name and an == name) then
			-- found by name: remember its ID, which also works when names differ by rank
			if item.aura and sid and not item.auraId then item.auraId = sid; T.PersistSoon() end
			local ic = plain(a.icon)
			if ic then learned(item.spell).auraIcon = ic end -- to find it on Blizzard's frames in combat
			local dur, ex = plain(a.duration), plain(a.expirationTime)
			local apps = plain(a.applications)
			if dur and dur > 0 and ex and ex > 0 then return "up", ex, dur, aid, apps end
			return "up", nil, nil, aid, apps
		end
	end
	return "missing"
end

-- Returns expires (math.huge = permanent, nil = missing) and unsure.
local function auraState(item, unit, now)
	local key = targetKey(unit) or unit
	local helpful = unit == "player" or not ns.Sensors.IsEnemy(unit)
	local mineOnly = not item.anySource
	local state, ex, dur, aid, apps = findAura(unit, item, helpful, mineOnly)
	known[item.id] = known[item.id] or { inst = {}, seenAt = {}, charges = {} }
	local rec = known[item.id]
	if state == "up" then
		local Lr = learned(item.spell)
		if dur then Lr.dur = dur end
		-- charges (Lightning Shield: 3): the count to run down on hits in combat
		if apps and apps > 0 then
			rec.charges[key], rec.chargeSetAt = apps, now
			if apps > (Lr.charges or 0) then Lr.charges = apps end
		end
		rec[key] = ex or math.huge
		rec.inst[key], rec.seenAt[key] = aid, now
		-- check Blizzard's icons against the truth while we can see it: only a
		-- match proven here lets them decide in combat
		local ob = Oracle.OnBar(unit, Lr.auraIcon or spellIcon(item.auraId or item.spell))
		if ob ~= nil then Lr.barOk = ob end
		return rec[key], false
	elseif state == "missing" then
		rec[key], rec.inst[key], rec.charges[key] = nil, nil, nil
		return nil, false
	end
	local cast = castsOn[(item.name or spellName(item.spell) or "") .. "@" .. key]
	-- unreadable (combat). 1: a buff the client never hides
	local d, dex = Oracle.Direct(unit, item.auraId or (not item.aura and item.spell) or nil, mineOnly)
	if d == true then rec[key] = dex; T.how[item.id] = "direct read"; return dex, false end
	if d == false then rec[key] = nil; T.how[item.id] = "direct read"; return nil, false end
	T.how[item.id] = "estimate"
	-- 2: the very instance seen before the fight: still there?
	local inst = rec.inst[key]
	if inst then
		local there, info = Oracle.Ask(unit, inst, helpful and "HELPFUL" or "HARMFUL")
		if there ~= nil then T.how[item.id] = "instance check" end
		if there == "secret" then
			-- unless you recast it since (then the old instance says nothing about the new)
			if not (cast and cast >= (rec.seenAt[key] or 0)) then
				return nil, false, info
			end
		elseif there == true then
			rec.seenAt[key] = now
			local e = rec[key]
			if not e or e <= now then e = math.huge end -- still there past the time we knew: refreshed
			return e, false
		elseif there == false then
			-- gone (dispelled, cancelled, ran out); recast by you since? then that one is estimated
			rec[key], rec.inst[key] = nil, nil
			if not (cast and cast >= (rec.seenAt[key] or 0)) then return nil, false end
		end
	end
	-- 3: Blizzard's own icons for the unit (buff bar / target frame)
	local lookId = item.auraId or (not item.aura and item.spell) or nil
	local L0 = ns.P.trackers.learned[item.spell]
	local icon = (L0 and L0.auraIcon) or spellIcon(lookId or item.spell)
	local onBar -- (not "a and b or nil": a false answer must stay false)
	if L0 and L0.barOk then onBar = Oracle.OnBar(unit, icon) end
	if onBar ~= nil then
		T.how[item.id] = onBar and "Blizzard's icons" or "Blizzard's icons (gone)"
		if onBar then rec.seenAt[key] = now; return rec[key] and rec[key] > now and rec[key] or math.huge, false end
		if not (cast and cast >= (rec.seenAt[key] or 0)) then rec[key] = nil; return nil, false end
	end
	-- 4: charges run down by the hits you take (Lightning Shield and the like)
	local Lc = ns.P.trackers.learned[item.spell]
	if T.CountsHits(item) and unit == "player" then
		if cast and cast > (rec.chargeSetAt or 0) and Lc and (Lc.charges or 0) > 0 then
			rec.charges[key], rec.chargeSetAt = Lc.charges, cast -- your recast: full again
		end
		local c = rec.charges[key]
		if c then
			T.how[item.id] = "charge count"
			if c > 0 then return rec[key] and rec[key] > now and rec[key] or math.huge, rec.chargeUnsure, nil, c end
			rec[key] = nil
			return nil, rec.chargeUnsure
		end
	end
	-- 5: the spell lookups (refused while there, a plain nil once gone)
	local lookName = item.aura or item.name or spellName(item.spell)
	local v = Oracle.SpellLookup(item, unit, lookId, lookName, helpful and "HELPFUL" or "HARMFUL")
	if v == true then T.how[item.id] = "spell lookup"; rec.seenAt[key] = now; return rec[key] and rec[key] > now and rec[key] or math.huge, false end
	if v == false and not (cast and cast >= (rec.seenAt[key] or 0)) then
		T.how[item.id] = "spell lookup (gone)"
		rec[key] = nil
		return nil, false
	end
	T.how[item.id] = "estimate"
	-- 6: the last reading, or your own cast plus the known duration
	local e = rec[key]
	local L = ns.P.trackers.learned[item.spell]
	if cast and L and L.dur and (not e or cast + L.dur > e) then e = cast + L.dur end
	if e and e <= now then e = nil end
	return e, true
end


---------------------------------------------------------------------------
-- Fights: the report after each one, and a clean slate at the start
---------------------------------------------------------------------------
ns.On("PLAYER_REGEN_ENABLED", function()
	-- after every fight: keep what the aura checks answered (read on disk after /reload)
	if Oracle.calibratedAt then
		local loud = ns.print
		ns.print = function() end
		local ok = pcall(ns.Capture, "auraprobe_after_combat", T.DumpOracle)
		ns.print = loud
		local rep = ok and SITREP_DB and SITREP_DB.reports and SITREP_DB.reports.auraprobe_after_combat
		if rep and ns.Targeting.stats then
			local cs = ns.Targeting.stats
			rep.lines[#rep.lines + 1] = format("who-targets-whom checks in the fight: %d plain, %d secret, %d refused", cs.plain, cs.secret, cs.err)
		end
		if rep and T.combatLog then
			rep.lines[#rep.lines + 1] = "timeline of the fight:"
			for _, l in ipairs(T.combatLog) do rep.lines[#rep.lines + 1] = "  " .. l end
		end
		if rep then
			for _, it in ipairs(T.Mine()) do
				if it.kind ~= "cd" then
					rep.lines[#rep.lines + 1] = format("%s (%s): %s", it.name or tostring(it.spell), T.LabelFor(it), T.CombatHow(it))
				end
			end
		end
	end
end)
ns.On("PLAYER_REGEN_DISABLED", function()
	T.combatLog, T.combatStart = {}, GetTime()
	if ns.Targeting.stats then local cs = ns.Targeting.stats; cs.plain, cs.secret, cs.err = 0, 0, 0 end
	Oracle.fight = {}
	T.lastBarplayer, T.lastBartarget = nil, nil
	for _, rec in pairs(known) do rec.chargeUnsure = nil end
	for _, f in pairs(T.icons) do f.logShow, f.logHow, f.logAnswers = nil, nil, nil end
end)

T.AuraState = auraState
