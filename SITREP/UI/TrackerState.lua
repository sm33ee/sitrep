-- SITREP · Trackers: casts, cooldowns, weapon imbues

local ADDON, ns = ...
local K = ns.Kit
local read, plain = ns.read, ns.plain
local max = math.max
local issecrettable = _G.issecrettable or function() return false end
local T = ns.Trackers
local spellName, learned, secretAny = T.SpellName, T.Learned, T.SecretAny
local GCD = T.GCD

---------------------------------------------------------------------------
-- State: own casts (for estimates in combat)
---------------------------------------------------------------------------
local casts = {}        -- [spellName] = time of your last successful cast
local castsOn = {}      -- [spellName .. "@" .. targetKey] = time
local sentTo = {}       -- [castGUID] = target name from UNIT_SPELLCAST_SENT
local lastEnd = {}      -- [spellID] = cooldown end from the last plain reading
local known = {}        -- [item.id] = { [targetKey] = expires (plain reading) }
local pendingImbue = {} -- [spellID] = { at, mh = {id, exp}, oh = {id, exp} } right after you cast it
T._casts, T._castsOn, T._known = casts, castsOn, known

local function inCombat()
	return (InCombatLockdown and InCombatLockdown()) or read(UnitAffectingCombat, "player") == true
end

local function targetKey(unit)
	return ns.Sensors.UnitKey(unit)
end

ns.On("UNIT_SPELLCAST_SENT", function(_, unit, targetName, castGUID)
	if unit ~= "player" then return end
	local g, n = plain(castGUID), plain(targetName)
	if g then sentTo[g] = n or "" end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
	if unit ~= "player" then return end
	local id = plain(spellID)
	local name = id and spellName(id)
	if not name then return end -- secret: nothing we can attribute
	local now = GetTime()
	casts[name] = now
	-- an imbue: note both hands now, so the change shows which enchant it gives
	for _, it in ipairs(T.Items()) do
		if it.kind == "weapon" and (it.name or spellName(it.spell)) == name then
			local w = T.WeaponInfo() or {}
			pendingImbue[it.spell] = { at = now, mh = w.mh, oh = w.oh }
		end
	end
	-- where it went: your target, unless the cast was sent to yourself or nobody
	local g = plain(castGUID)
	local to = g and sentTo[g]
	if g then sentTo[g] = nil end
	local me = read(UnitName, "player")
	local toSelf = (to == nil and not read(UnitExists, "target")) or to == "" or (to and me and to == me)
	if toSelf then castsOn[name .. "@" .. (targetKey("player") or "player")] = now
	elseif read(UnitExists, "target") then castsOn[name .. "@" .. (targetKey("target") or "?")] = now end
	T.Refresh()
end)

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
-- Returns onCD, endTime (nil when unknown), start, duration, how ("plain" |
-- "client" | "est"). "client": secret numbers, the swipe comes from the client.
local function cooldownState(item, now)
	local id = item.spell
	local c = C_Spell and C_Spell.GetSpellCooldown and select(2, pcall(C_Spell.GetSpellCooldown, id))
	if type(c) == "table" and not issecrettable(c) then
		local st, du, en = plain(c.startTime), plain(c.duration), c.isEnabled
		if st and du then
			if du > GCD and en ~= false then
				local L = learned(id)
				if not L.cd or math.abs(L.cd - du) > 0.5 then L.cd = du end
				lastEnd[id] = st + du
				return true, st + du, st, du, "plain"
			end
			lastEnd[id] = nil
			return false
		end
	end
	-- secret: our own cast and a known length, or the last plain reading
	local L = ns.P.trackers.learned[id]
	local len = L and L.cd
	if not len and GetSpellBaseCooldown then
		local ms = read(GetSpellBaseCooldown, id)
		if ms and ms > GCD * 1000 then len = ms / 1000 end
	end
	local cast = casts[item.name or spellName(id) or ""]
	if cast and len and now < cast + len then return true, cast + len, cast, len, "est" end
	if lastEnd[id] and now < lastEnd[id] then return true, lastEnd[id], nil, nil, "est" end
	return false
end


---------------------------------------------------------------------------
-- Weapon enchants (temporary imbues: Flametongue, Windfury, poisons, oils)
---------------------------------------------------------------------------
local function weaponInfo()
	if not GetWeaponEnchantInfo then return nil end
	local ok, hasMH, mhExp, _, mhID, hasOH, ohExp, _, ohID = pcall(GetWeaponEnchantInfo)
	if not ok then return nil end
	hasMH, mhExp, mhID, hasOH, ohExp, ohID = plain(hasMH), plain(mhExp), plain(mhID), plain(hasOH), plain(ohExp), plain(ohID)
	if hasMH == nil and hasOH == nil then return nil end -- secret: unreadable
	return {
		mh = hasMH and { id = mhID, exp = (mhExp or 0) / 1000 } or nil,
		oh = hasOH and { id = ohID, exp = (ohExp or 0) / 1000 } or nil,
	}
end
T.WeaponInfo = weaponInfo

-- After you cast an imbue, the hand that changed tells which enchant it gives.
local function learnImbue(spell, w, now)
	local p = pendingImbue[spell]
	if not p then return end
	if now - p.at > 3 then pendingImbue[spell] = nil return end
	for _, hand in ipairs({ "mh", "oh" }) do
		local h, before = w[hand], p[hand]
		if h and (not before or before.id ~= h.id or h.exp > (before.exp or 0) + 2) then
			local L = learned(spell)
			L.enchant, L.dur = h.id, h.exp
			pendingImbue[spell] = nil
			return
		end
	end
end

-- The weapon's tooltip, the second place an imbue shows up: a line ending in
-- its time left, e.g. "Flammenzunge 3 (29 Min.)" / "Flametongue 3 (30 min)".
-- Returns { text, exp }, false (readable, none there), or nil (unreadable).
local SLOT = { main = 16, off = 17 }
local function unitSeconds(u)
	u = (u or ""):lower()
	if u:find("^std") or u:find("^h") or u:find("^stunde") then return 3600 end
	if u:find("^m") then return 60 end
	if u:find("^s") then return 1 end
	return 60
end
-- The tooltip's lines as plain strings, or nil when the client will not say.
local function tooltipLines(slot)
	local TI = C_TooltipInfo
	if not (TI and TI.GetInventoryItem) then return nil end
	local ok, data = pcall(TI.GetInventoryItem, "player", slot)
	if not ok or type(data) ~= "table" or secretAny(data) then return nil end
	local okL, lines = pcall(function() return data.lines end)
	if not okL or type(lines) ~= "table" or secretAny(lines) then return nil end
	return lines
end
T.TooltipLines = tooltipLines
local function tooltipEnchant(slot, want)
	local lines = tooltipLines(slot)
	if not lines then return nil end
	for _, l in ipairs(lines) do
		local t = type(l) == "table" and plain(l.leftText)
		if type(t) == "string" then
			local n, u = t:match("%((%d+)%s*([^%)%d]*)%)%s*$")
			if n and (not want or want == "" or t:lower():find(want:lower(), 1, true)) then
				return { text = t, exp = tonumber(n) * unitSeconds(u) }
			end
		end
	end
	return false
end
T.TooltipEnchant = tooltipEnchant

-- Returns expires (nil = not on), unsure, and which source answered.
local function weaponState(item, now)
	local hand = item.hand or "main"
	local w = weaponInfo()
	if w then
		learnImbue(item.spell, w, now)
		-- the learned enchant only tells two imbues apart when both hands have one
		local L = ns.P.trackers.learned[item.spell]
		local want = hand == "either" and w.mh and w.oh and L and L.enchant or nil
		local function on(h) if h and (not want or h.id == want) then return now + max(0, h.exp) end end
		local e = (hand ~= "off" and on(w.mh)) or (hand ~= "main" and on(w.oh)) or nil
		if e then return e, false, "enchant info" end
	end
	-- the weapon's tooltip (also when the enchant info says nothing)
	local readable = w ~= nil
	for _, h in ipairs(hand == "either" and { "main", "off" } or { hand }) do
		local r = tooltipEnchant(SLOT[h], item.aura)
		if r then return now + r.exp, false, "tooltip" end
		if r == false then readable = true end
	end
	if readable then return nil, false, "none" end
	-- unreadable: your own cast and the learned length
	local cast = casts[item.name or spellName(item.spell) or ""]
	local L = ns.P.trackers.learned[item.spell]
	if cast and L and L.dur and now < cast + L.dur then return cast + L.dur, true, "estimate" end
	return nil, true, "unreadable"
end
T.WeaponState = weaponState

-- /sitrep weapon: everything the client says about your weapon enchants.
function T.DumpWeapon()
	local function show(v)
		if issecretvalue and issecretvalue(v) then return "<secret>" end
		return tostring(v)
	end
	if not GetWeaponEnchantInfo then ns.print("weapon: this client has no GetWeaponEnchantInfo")
	else
		local r = { pcall(GetWeaponEnchantInfo) }
		if not r[1] then ns.print("weapon: GetWeaponEnchantInfo failed: %s", show(r[2]))
		else
			ns.print("weapon enchant info: main hand %s, %s ms, %s charges, enchant %s  |  off hand %s, %s ms, %s charges, enchant %s",
				show(r[2]), show(r[3]), show(r[4]), show(r[5]), show(r[6]), show(r[7]), show(r[8]), show(r[9]))
		end
	end
	for _, h in ipairs({ "main", "off" }) do
		local lines = tooltipLines(SLOT[h])
		if not lines then
			ns.print("%s hand tooltip: not readable", h)
		else
			local timed = {}
			for _, l in ipairs(lines) do
				local t = type(l) == "table" and plain(l.leftText)
				if type(t) == "string" and t:find("%(%d+[^%)]*%)%s*$") then timed[#timed + 1] = "\"" .. t .. "\"" end
			end
			ns.print("%s hand tooltip: %d lines; with a timer: %s", h, #lines, #timed > 0 and table.concat(timed, ", ") or "none")
		end
	end
	local now = GetTime()
	for _, it in ipairs(T.Items()) do
		if it.kind == "weapon" then
			local e, unsure, src = weaponState(it, now)
			local L = ns.P.trackers.learned[it.spell]
			ns.print("tracker %s (%s hand): %s via %s%s%s", it.name or tostring(it.spell), it.hand or "main",
				e and ("ON, " .. T.TimeText(e - now) .. " left") or "NOT ON", src, unsure and " (?)" or "",
				L and L.enchant and (", learned enchant " .. L.enchant) or "")
		end
	end
end

-- /sitrep buffs: what the client calls your buffs and weapon enchants right now.
function T.DumpBuffs()
	local ids = ns.Auras.AuraIDs("player", "HELPFUL")
	if not ids then ns.print("buffs: locked by the client right now (combat?). Try again out of combat.") return end
	ns.print("your buffs (name · spell ID) — use the name or ID in \"Look for this buff instead\":")
	for _, aid in ipairs(ids) do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", aid)
		if ok and type(a) == "table" and not issecrettable(a) then
			ns.print("  %s · %s", tostring(plain(a.name)), tostring(plain(a.spellId)))
		end
	end
	local w = weaponInfo()
	if w and (w.mh or w.oh) then
		for hand, label in pairs({ mh = "main hand", oh = "off hand" }) do
			local h = w[hand]
			if h then ns.print("  weapon enchant, %s: enchant %s, %s left", label, tostring(h.id), T.TimeText(h.exp)) end
		end
	else
		ns.print("  no temporary weapon enchant (or the client does not report it; /sitrep weapon shows the raw data)")
	end
end

T.InCombat, T.TargetKey, T.CooldownState, T.WeaponState = inCombat, targetKey, cooldownState, weaponState
