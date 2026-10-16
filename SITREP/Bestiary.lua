-- SITREP · Bestiary: every mob seen, where, and which quests want it
-- Just by passing: a mob is noted when its plate appears, you target it or the
-- mouse is on it; each one (its GUID: one spawn) once a session. Kept for the
-- account (SITREP_DB.bestiary[npcID]):
--   n        its name          lo, hi   its levels seen      e  1: elite, 2: rare
--   s        how often seen (capped at SEEN_MAX)
--   m        where: [map][cell] = times seen there; cells of Spawns.CELL yards (the
--            place you stood: its plate shows within about 30 yd), at most
--            MAX_CELLS a map per mob (the rarest go)
-- Hostile and neutral mobs only (friendly NPCs have their titles, PlateNPC; small
-- critters are left out): a city adds nothing.
-- Quests: which mobs a quest wants comes from their tooltips (Quests.LearnMob,
-- kept for the account) and, for one to kill, from its objective's own words
-- ("Kobold getötet: 0/8": Kobold). So a quest just accepted already knows where
-- its mobs are if any of your characters passed them: you are told (QUEST_ACCEPTED),
-- the quest's places include them (Quests.Candidates: the arrow leads there), the
-- hover window says where a mob was seen and what it is wanted for.
-- Cost: one table look per plate that appears (the GUID seen already: done); where
-- you stand is worked out once a second, not per mob.
--
-- Self-contained, to take out in one go: this file and its line in the TOC, the
-- "mobs" command in Core.lua, its calls in Quests.Candidates and PlateHover, and its
-- block in tests/run.lua.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format, floor = string.format, math.floor

local B = {}
ns.Bestiary = B
local MAX_CELLS = 30   -- cells kept per mob and map
local SEEN_MAX = 9999
local GUIDS_MAX = 5000 -- GUIDs remembered this session before starting again
B.MAX_CELLS = MAX_CELLS

local function book()
	if not SITREP_DB then return {} end
	SITREP_DB.bestiary = SITREP_DB.bestiary or {}
	return SITREP_DB.bestiary
end
B.Book = book

-- where you stand: map and cell, once a second
local where -- { map, cell }
ns.On("SR_TICK", function()
	local now = GetTime()
	if where and now - where.at < 1 then return end
	local here = ns.Quests and ns.Quests.Here()
	where = here and ns.Spawns and { map = here.map, cell = ns.Spawns.CellOf(here.map, here.x, here.y), at = now } or { at = now }
end)
function B.SetWhere(map, cell) where = { map = map, cell = cell, at = GetTime() } end -- (tests)

-- names, lower case, to their NPC IDs (built once, kept up to date)
local byName
local function nameIndex()
	if byName then return byName end
	byName = {}
	for npc, e in pairs(book()) do if e.n then byName[e.n:lower()] = npc end end
	return byName
end
function B.ByName(name)
	return type(name) == "string" and nameIndex()[name:lower()] or nil
end

local seen, seenCount = {}, 0
-- A unit seen: noted once per spawn.
function B.Seen(unit)
	local guid = read(UnitGUID, unit)
	if type(guid) ~= "string" or seen[guid] then return end
	local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind ~= "Creature" or not npc then return end
	if seenCount >= GUIDS_MAX then wipe(seen); seenCount = 0 end
	seen[guid] = true
	seenCount = seenCount + 1
	local react = read(UnitReaction, unit, "player")
	if not react or react > 4 then return end -- (friendly: not a mob)
	local cls = read(UnitClassification, unit)
	if cls == "minus" or cls == "trivial" then return end -- (critters)
	npc = tonumber(npc)
	local b = book()
	local e = b[npc]
	if not e then
		e = { s = 0, m = {} }
		b[npc] = e
	end
	local name = read(UnitName, unit)
	if type(name) == "string" and name ~= "" and e.n ~= name then
		e.n = name
		if byName then byName[name:lower()] = npc end
	end
	local lv = read(UnitLevel, unit)
	if type(lv) == "number" and lv > 0 then e.lo, e.hi = math.min(e.lo or lv, lv), math.max(e.hi or lv, lv) end
	if cls == "elite" or cls == "worldboss" then e.e = 1 elseif cls == "rare" or cls == "rareelite" then e.e = 2 end
	if e.s < SEEN_MAX then e.s = e.s + 1 end
	if where and where.cell then
		local cells = e.m[where.map]
		if not cells then cells = {}; e.m[where.map] = cells end
		if cells[where.cell] then
			cells[where.cell] = cells[where.cell] + 1
		else
			-- a new cell: the rarest goes when there are too many
			local n, rarest, rk = 0, nil, nil
			for k, c in pairs(cells) do
				n = n + 1
				if not rarest or c < rarest then rarest, rk = c, k end
			end
			if n >= MAX_CELLS and rk then cells[rk] = nil end
			cells[where.cell] = 1
		end
	end
end

-- The middle of a cell on its map (0..1), from its key.
local function cellCenter(map, key)
	local cx, cy = key:match("^(%d+):(%d+)$")
	if cx then
		local w, h = ns.Quests.MapSize(map)
		if not (w and h) then return nil end
		local size = ns.Spawns and ns.Spawns.CELL or 100
		return (tonumber(cx) + 0.5) * size / w, (tonumber(cy) + 0.5) * size / h
	end
	cx, cy = key:match("^m(%d+):(%d+)$")
	if cx then return (tonumber(cx) + 0.5) / 20, (tonumber(cy) + 0.5) / 20 end
	return nil
end
B.CellCenter = cellCenter

-- Where a mob was seen: { { map, x, y, c = times } }, most seen first.
function B.Places(npc)
	local e = book()[npc]
	local out = {}
	for map, cells in pairs(e and e.m or {}) do
		for key, c in pairs(cells) do
			local x, y = cellCenter(map, key)
			if x then out[#out + 1] = { map = map, x = x, y = y, c = c } end
		end
	end
	table.sort(out, function(a, b) return a.c > b.c end)
	return out
end

-- A kill objective's mob, from its words: "Kobold getötet: 0/8", "Kobold Vermin slain: 3/8".
function B.ObjectiveMob(text)
	text = plain(text)
	if type(text) ~= "string" then return nil end
	local bare = (ns.Questbook and ns.Questbook.BareText(text)) or text
	bare = bare:gsub("%s+getötet$", ""):gsub("%s+slain$", ""):gsub("%s+killed$", ""):gsub("%s+besiegt$", ""):gsub("%s+erschlagen$", "")
	return bare ~= "" and bare or nil
end

-- The mobs a quest's open objectives want: { [n] = { [npcID] = true } }.
function B.MobsFor(q)
	local out = {}
	local qm = SITREP_DB and SITREP_DB.questMobs and SITREP_DB.questMobs[q.id] or {}
	for npc, e in pairs(qm) do
		out[e.n] = out[e.n] or {}
		out[e.n][npc] = true
	end
	for n, o in ipairs(q.objectives or {}) do
		local isKill = o.kind == "monster" or (not o.kind and (o.text or ""):lower():find("getötet", 1, true) or (o.text or ""):lower():find("slain", 1, true))
		if isKill then
			local npc = B.ByName(B.ObjectiveMob(o.text))
			if npc then
				out[n] = out[n] or {}
				out[n][npc] = true
			end
		end
	end
	return out
end

-- The quests that want a mob: { { id, title, n, mine (in your log) } }.
function B.QuestsOf(npc)
	local out, inLog = {}, {}
	for _, q in ipairs(ns.Quests.List()) do inLog[q.id] = q end
	local done = {}
	for id, mobs in pairs(SITREP_DB and SITREP_DB.questMobs or {}) do
		local e = mobs[npc]
		if e then
			local q = inLog[id]
			local title = q and q.title or (SITREP_DB.questbook and SITREP_DB.questbook[id] and SITREP_DB.questbook[id].t)
				or (ns.Quests.Store()[id] and ns.Quests.Store()[id].title)
			out[#out + 1] = { id = id, title = title, n = e.n, mine = q ~= nil }
			done[id] = true
		end
	end
	-- (your quests whose kill objective names it)
	local name = book()[npc] and book()[npc].n
	for id, q in pairs(inLog) do
		if not done[id] and name then
			for n, o in ipairs(q.objectives) do
				if B.ObjectiveMob(o.text) == name then out[#out + 1] = { id = id, title = q.title, n = n, mine = true } break end
			end
		end
	end
	table.sort(out, function(a, b) if a.mine ~= b.mine then return a.mine end return (a.title or "") < (b.title or "") end)
	return out
end

-- "seen 34x in 5 places (Westfall, Elwynn)": for the hover window.
function B.Line(npc)
	local e = book()[npc]
	if not e then return nil end
	local places, maps = 0, {}
	for map, cells in pairs(e.m or {}) do
		for _ in pairs(cells) do places = places + 1 end
		maps[#maps + 1] = ns.Quests.MapName(map) or tostring(map)
	end
	table.sort(maps)
	local line = format("seen %dx%s", e.s or 0, places > 0 and format(" in %d place%s (%s)", places, places == 1 and "" or "s", table.concat(maps, ", ")) or "")
	local qs = B.QuestsOf(npc)
	if #qs > 0 then
		local names = {}
		for i, q in ipairs(qs) do
			if i > 3 then names[#names + 1] = "..." break end
			names[#names + 1] = (q.title or ("#" .. q.id)) .. (q.mine and "" or " (before)")
		end
		line = line .. "\nfor: " .. table.concat(names, ", ")
	end
	return line
end

-- A quest accepted: its mobs already seen? Said once.
local told = {}
function B.Tell(q)
	if told[q.id] then return end
	told[q.id] = true
	for _, mobs in pairs(B.MobsFor(q)) do
		for npc in pairs(mobs) do
			local e = book()[npc]
			local places = B.Places(npc)
			if e and #places > 0 then
				local maps, seenMap = {}, {}
				for _, p in ipairs(places) do
					if not seenMap[p.map] then seenMap[p.map] = true; maps[#maps + 1] = ns.Quests.MapName(p.map) or tostring(p.map) end
				end
				ns.print("For \"%s\": %s seen before in %s (%d place%s); the arrow knows where.", q.title or "?", e.n or "?",
					table.concat(maps, ", "), #places, #places == 1 and "" or "s")
			end
		end
	end
end
ns.On("QUEST_ACCEPTED", function(_, a, b)
	-- (the quest's ID: the second argument on classic clients, the first on modern ones)
	local id = tonumber(plain(b)) or tonumber(plain(a))
	C_Timer.After(1, function()
		for _, q in ipairs(ns.Quests.List()) do if q.id == id then B.Tell(q) end end
	end)
end)

-- /sitrep mobs <name>: what is known of mobs whose name has it.
function B.Report(arg)
	ns.Capture("mobs", function()
		local want = type(arg) == "string" and arg:lower() or ""
		local list = {}
		for npc, e in pairs(book()) do
			if e.n and (want == "" or e.n:lower():find(want, 1, true)) then list[#list + 1] = npc end
		end
		table.sort(list, function(a, b) return (book()[a].s or 0) > (book()[b].s or 0) end)
		local total = 0
		for _ in pairs(book()) do total = total + 1 end
		ns.print("bestiary: %d kinds of mobs known (all characters)%s", total, want ~= "" and format("; %d named like \"%s\"", #list, arg) or "")
		for i, npc in ipairs(list) do
			if i > 10 then ns.print("  ... %d more", #list - 10) break end
			local e = book()[npc]
			local lv = e.lo and (e.lo == e.hi and tostring(e.lo) or (e.lo .. "-" .. e.hi)) or "?"
			ns.print("  %s (level %s%s): %s", e.n, lv, e.e == 1 and ", elite" or e.e == 2 and ", rare" or "", (B.Line(npc) or ""):gsub("\n", "; "))
			for j, p in ipairs(B.Places(npc)) do
				if j > 3 then break end
				ns.print("      %s %.0f, %.0f (%dx)", ns.Quests.MapName(p.map) or tostring(p.map), p.x * 100, p.y * 100, p.c)
			end
		end
	end)
end

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) B.Seen(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() B.Seen("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() B.Seen("mouseover") end)
