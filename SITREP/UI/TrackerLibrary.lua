-- SITREP · Trackers: spell library

local ADDON, ns = ...
local K = ns.Kit
local read, plain = ns.read, ns.plain
local min = math.min
local issecrettable = _G.issecrettable or function() return false end
local T = ns.Trackers
local spellName, spellIcon = T.SpellName, T.SpellIcon

---------------------------------------------------------------------------
-- Spell library: what the search fields suggest while you type.
--   BOOK    your spellbook (every rank), in your client's language
--   ON YOU / ON TGT  auras on you and your target right now (exact buff names)
--   SEEN    auras SITREP has read this session
--   ALL     on request: every spell the client knows, searched in the
--           background (a few seconds; nothing is stored afterwards)
---------------------------------------------------------------------------
local Lib = {}
T.Lib = Lib
Lib.DEEP_MAX, Lib.DEEP_STEP, Lib.LIMIT = 500000, 12000, 40
local seen = {} -- [spellID] = name
Lib.seen = seen

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- "Waffe der Flammenzunge (8024)" -> 8024; "8024" -> 8024
function Lib.IdIn(text)
	text = trim(text)
	return tonumber(text) or tonumber(text:match("%((%d+)%)%s*$") or "")
end

local function entry(id, src, name)
	name = name or spellName(id)
	if not name then return nil end
	local sub = C_Spell and C_Spell.GetSpellSubtext and read(C_Spell.GetSpellSubtext, id)
	return { id = id, name = name, sub = (sub and sub ~= "") and sub or nil, icon = spellIcon(id), src = src }
end
Lib.Entry = entry

-- Every spell in your spellbook (rebuilt when it changes).
local book
function Lib.Book()
	if book then return book end
	book = {}
	local B = C_SpellBook
	if not (B and B.GetNumSpellBookSkillLines) then return book end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for line = 1, read(B.GetNumSpellBookSkillLines) or 0 do
		local info = read(B.GetSpellBookSkillLineInfo, line)
		local first, count = info and plain(info.itemIndexOffset), info and plain(info.numSpellBookItems)
		for slot = (first or 0) + 1, (first or 0) + (count or 0) do
			local it = read(B.GetSpellBookItemInfo, slot, bank)
			local id = it and plain(it.spellID)
			if id then book[#book + 1] = id end
		end
	end
	return book
end
ns.On("SPELLS_CHANGED", function() book = nil end)

-- Auras on a unit right now, as (spellID, name) pairs; remembered as SEEN.
local function aurasOn(unit)
	local out = {}
	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		for _, aid in ipairs(ns.Auras.AuraIDs(unit, filter) or {}) do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aid)
			if ok and type(a) == "table" and not issecrettable(a) then
				local sid, an = plain(a.spellId), plain(a.name)
				if sid and an then out[#out + 1] = { sid, an }; seen[sid] = an end
			end
		end
	end
	return out
end
Lib.AurasOn = aurasOn
ns.On("UNIT_AURA", function(_, unit)
	if (unit == "player" or unit == "target") and not InCombatLockdown() then pcall(aurasOn, unit) end
end)

-- Matches for what was typed, best first. opts.auras: buffs before spells.
function Lib.Search(query, opts)
	query = trim(query)
	local out, have = {}, {}
	if #query < 2 and not tonumber(query) then return out end
	local q, qid = query:lower(), Lib.IdIn(query)
	local function consider(id, name, src)
		if have[id] or #out >= Lib.LIMIT then return end
		name = name or spellName(id)
		if (qid and id == qid) or (name and name:lower():find(q, 1, true)) then
			local e = entry(id, src, name)
			if e then have[id] = true; out[#out + 1] = e end
		end
	end
	if qid then consider(qid, nil, "ID") end
	-- the exact name as the client knows it (also spells outside your book)
	local info = not qid and C_Spell and C_Spell.GetSpellInfo and read(C_Spell.GetSpellInfo, query)
	if type(info) == "table" and plain(info.spellID) then consider(info.spellID, plain(info.name), "NAME") end
	local function fromBook() for _, id in ipairs(Lib.Book()) do consider(id, nil, "BOOK") end end
	local function fromAuras()
		for _, a in ipairs(aurasOn("player")) do consider(a[1], a[2], "ON YOU") end
		if read(UnitExists, "target") then for _, a in ipairs(aurasOn("target")) do consider(a[1], a[2], "ON TGT") end end
		for id, name in pairs(seen) do consider(id, name, "SEEN") end
	end
	if opts and opts.auras then fromAuras(); fromBook() else fromBook(); fromAuras() end
	-- exact names first, then names that start with it, then the rest (stable)
	for i, e in ipairs(out) do
		local n = e.name:lower()
		e.rank = (qid and e.id == qid and 0) or (n == q and 1) or (n:sub(1, #q) == q and 2) or 3
		e.order = i
	end
	table.sort(out, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.order < b.order end)
	return out
end

-- Every spell the client knows, in chunks per frame. cb(results, fraction, done).
local deep = { running = false }
Lib.deep = deep
function Lib.Deep(query, cb)
	query = trim(query)
	if #query < 3 then return false end
	deep.q, deep.cb, deep.next, deep.results, deep.running = query:lower(), cb, 1, {}, true
	return true
end
local deepDriver = CreateFrame("Frame")
deepDriver:SetScript("OnUpdate", ns.Timed("trackers: search (deepDriver)", function()
	if not deep.running then return end
	local getName = C_Spell and C_Spell.GetSpellName
	if not getName then deep.running = false return end
	local last = min(deep.next + Lib.DEEP_STEP - 1, Lib.DEEP_MAX)
	pcall(function()
		for id = deep.next, last do
			local n = getName(id)
			if type(n) == "string" and #deep.results < 60 and n:lower():find(deep.q, 1, true) then
				local e = entry(id, "ALL", n)
				if e then deep.results[#deep.results + 1] = e end
			end
		end
	end)
	deep.next = last + 1
	local done = deep.next > Lib.DEEP_MAX or #deep.results >= 60
	if done then deep.running = false end
	if deep.cb then pcall(deep.cb, deep.results, min(1, (deep.next - 1) / Lib.DEEP_MAX), done) end
end))

