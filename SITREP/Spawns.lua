-- SITREP · Spawns: how long mobs take to come back, learned; and how far plates reach
-- Respawn times: no combat log, so a mob is seen dying where SITREP sees it (its
-- plate, your target): its kind (the NPC ID from its GUID), the copy of the zone
-- (the GUID's zoneUID: the layer), the map and where you stood, and the server
-- time. A creature of the same kind that appears later on a plate tells when it
-- spawned (Sensors.SpawnAge: the GUID's spawn second): one that spawned after a
-- death of its kind in the same copy of the zone, near where you were then, came
-- back after (spawn - death) seconds. Each kind keeps its last KEEP times
-- (SITREP_DB.spawns[npcID] = { name, t = { seconds, ... }, n = count }): a few
-- bytes a kind. /sitrep spawns lists them (the middle value, the spread, how many).
-- Whether Forever's GUIDs carry the spawn second as retail's do is not measured:
-- impossible times (under MIN or over MAX seconds) are not kept.
-- Grinding spots: each death and each respawn time also go to the piece of the
-- map where it happened, about CELL x CELL yards (SITREP_DB.spawnSpots[map][cell]
-- = { k kills seen, n respawns, t = { the last KEEP times }, x, y the middle of
-- the kills, lo, hi their levels, kinds = { [npcID] = name } }). /sitrep spots
-- ranks the pieces of a map by how fast their mobs come back (at least SPOT_MIN
-- respawns seen), and says which are grey or too high for you: where to grind.
-- Plate reach: the client's plate distance (nameplateMaxDistance) and the one it
-- really draws at may differ. When a plate appears its unit is just inside the
-- reach: the range checks say how far it is at least; the farthest of those since
-- login is about the reach (/sitrep spawns says it too).
--
-- Self-contained, to take out in one go: this file and its line in the TOC, the
-- "spawns" and "spots" commands in Core.lua, and its block in tests/run.lua.

local ADDON, ns = ...
local read = ns.read

local SP = {}
ns.Spawns = SP
local KEEP = 12           -- times kept per kind
local MIN, MAX = 15, 3600 -- seconds: a respawn time outside this is not one
local NEAR = 0.06         -- map units: how close the spawn must be seen to where the death was (about 100 yd)
local DEATH_KEEP = 3600   -- seconds a death waits for its mob to come back
local CELL = 100          -- yards: a grinding spot's side
local SPOT_MIN = 3        -- respawns seen before a spot is ranked
local SPOTS_SHOWN = 8
SP.KEEP, SP.MIN, SP.MAX, SP.CELL, SP.SPOT_MIN = KEEP, MIN, MAX, CELL, SPOT_MIN

local deaths = {}   -- { npc, zone, map, x, y, at, name, matched }
local dead = {}     -- [guid] = true: its death is noted
local seen = {}     -- [guid] = true: its spawn was looked at
SP.deaths = deaths

local function db()
	SITREP_DB.spawns = SITREP_DB.spawns or {}
	return SITREP_DB.spawns
end

local function now() return read(GetServerTime) or math.floor(GetTime()) end

-- Where you are: the map and your place on it.
local function here()
	local map = C_Map and C_Map.GetBestMapForUnit and read(C_Map.GetBestMapForUnit, "player")
	if not map then return nil end
	local pos = read(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" then return map end
	local ok, x, y = pcall(pos.GetXY, pos)
	if ok and type(x) == "number" and not ns.isSecret(x) then return map, x, y end
	return map
end

-- The piece of the map a place is in (CELL yards a side; a twentieth of the map
-- when its size is not known), and its entry.
function SP.CellOf(map, x, y)
	-- (both sizes: "ns.Quests and f()" keeps only the first; until 4.9.13 every spot
	-- went to the coarse grid for that: SP.Regrid moves them)
	local w, h
	if ns.Quests then w, h = ns.Quests.MapSize(map) end
	if w and h then return math.floor(x * w / CELL) .. ":" .. math.floor(y * h / CELL) end
	return "m" .. math.floor(x * 20) .. ":" .. math.floor(y * 20)
end

-- Spots kept on the coarse grid ("m...") while the map's size is known: onto the
-- yard grid, by where their kills were (joined with a spot already there).
function SP.Regrid()
	for map, cells in pairs(SITREP_DB and SITREP_DB.spawnSpots or {}) do
		local moves = {}
		for key, sp in pairs(cells) do
			if type(key) == "string" and key:sub(1, 1) == "m" and sp.x and sp.y then
				local new = SP.CellOf(map, sp.x, sp.y)
				if new:sub(1, 1) ~= "m" then moves[#moves + 1] = { key, new } end
			end
		end
		for _, mv in ipairs(moves) do
			local sp, into = cells[mv[1]], cells[mv[2]]
			cells[mv[1]] = nil
			if not into then
				cells[mv[2]] = sp
			else
				local k = (into.k or 0) + (sp.k or 0)
				if k > 0 and sp.x and into.x then
					into.x = (into.x * (into.k or 0) + sp.x * (sp.k or 0)) / k
					into.y = (into.y * (into.k or 0) + sp.y * (sp.k or 0)) / k
				end
				into.k, into.n = k, (into.n or 0) + (sp.n or 0)
				for _, t in ipairs(sp.t or {}) do into.t[#into.t + 1] = t end
				while #into.t > KEEP do table.remove(into.t, 1) end
				for npc, name in pairs(sp.kinds or {}) do into.kinds[npc] = name end
				if sp.lo then into.lo, into.hi = math.min(into.lo or sp.lo, sp.lo), math.max(into.hi or sp.hi, sp.hi) end
			end
		end
	end
end
ns.On("SR_LOGIN", function() SP.Regrid() end)
local function spot(map, x, y)
	if not (map and x and y and SITREP_DB) then return nil end
	SITREP_DB.spawnSpots = SITREP_DB.spawnSpots or {}
	local m = SITREP_DB.spawnSpots[map] or {}
	SITREP_DB.spawnSpots[map] = m
	local key = SP.CellOf(map, x, y)
	m[key] = m[key] or { k = 0, n = 0, t = {}, kinds = {} }
	return m[key]
end

-- A mob seen dead: noted once.
function SP.Died(unit)
	-- (asked on every health change: whether it is dead first, one call)
	if read(UnitIsDead, unit) ~= true then return end
	local guid = read(UnitGUID, unit)
	if not guid or dead[guid] then return end
	if read(UnitIsPlayer, unit) ~= false then return end
	local zone, npc = ns.Sensors.GuidParts(guid)
	if not npc then return end
	dead[guid] = true
	local map, x, y = here()
	local t = now()
	-- (deaths too old to wait for go)
	for i = #deaths, 1, -1 do if t - deaths[i].at > DEATH_KEEP then table.remove(deaths, i) end end
	local name, level = read(UnitName, unit), read(UnitLevel, unit)
	deaths[#deaths + 1] = { npc = npc, zone = zone, map = map, x = x, y = y, at = t, name = name }
	-- its spot: one kill more, where they die, their levels and kinds
	local sp = spot(map, x, y)
	if sp then
		sp.k = sp.k + 1
		sp.x = (sp.x or x) + (x - (sp.x or x)) / sp.k
		sp.y = (sp.y or y) + (y - (sp.y or y)) / sp.k
		if type(level) == "number" and level > 0 then
			sp.lo, sp.hi = math.min(sp.lo or level, level), math.max(sp.hi or level, level)
		end
		if type(name) == "string" then sp.kinds[npc] = name end
	end
end

-- A creature seen: if it spawned after a death of its kind there, that is a respawn time.
function SP.Seen(unit)
	local guid = read(UnitGUID, unit)
	if not guid or seen[guid] then return end
	seen[guid] = true
	local zone, npc = ns.Sensors.GuidParts(guid)
	if not npc then return end
	local age = ns.Sensors.SpawnAge(guid)
	if not age then return end
	local spawnAt = now() - age
	local map, x, y = here()
	-- the latest death of its kind before it spawned, in the same copy of the zone, near
	local best
	for _, d in ipairs(deaths) do
		if not d.matched and d.npc == npc and d.zone == zone and d.map == map and d.at < spawnAt then
			local near = not (d.x and x) or (math.abs(d.x - x) <= NEAR and math.abs(d.y - y) <= NEAR)
			if near and (not best or d.at > best.at) then best = d end
		end
	end
	if not best then return end
	local secs = spawnAt - best.at
	if secs < MIN or secs > MAX then return end
	best.matched = true
	local e = db()[npc] or { t = {}, n = 0 }
	db()[npc] = e
	e.name = best.name or e.name
	e.t[#e.t + 1] = secs
	while #e.t > KEEP do table.remove(e.t, 1) end
	e.n = (e.n or 0) + 1
	-- and at its spot
	local sp = spot(best.map, best.x, best.y)
	if sp then
		sp.t[#sp.t + 1] = secs
		while #sp.t > KEEP do table.remove(sp.t, 1) end
		sp.n = sp.n + 1
	end
	ns.Fire("SR_RESPAWN", npc, secs)
end

-- What is known for a kind: the middle time, the shortest and longest, how many.
function SP.For(npc)
	local e = SITREP_DB and SITREP_DB.spawns and SITREP_DB.spawns[npc]
	if not (e and #e.t > 0) then return nil end
	local s = {}
	for i, v in ipairs(e.t) do s[i] = v end
	table.sort(s)
	return s[math.floor((#s + 1) / 2)], s[1], s[#s], e.n, e.name
end

-- Plate reach: when a plate appears, how far its unit is at least.
SP.reach = 0
function SP.PlateAdded(unit)
	local lo = ns.Sensors.MeasureRange and select(1, ns.Sensors.MeasureRange(unit, 100))
	if type(lo) == "number" and lo > SP.reach then SP.reach = lo end
	SP.Seen(unit)
end

local function middleOf(t)
	local s = {}
	for i, v in ipairs(t) do s[i] = v end
	table.sort(s)
	return s[math.floor((#s + 1) / 2)]
end

-- The spots of a map with enough respawns seen, fastest first:
-- { { key, spot, mid (seconds), fit ("ok" / "grey" / "high") }, ... }.
function SP.Spots(map)
	local out = {}
	local me = read(UnitLevel, "player") or 1
	for key, sp in pairs(SITREP_DB and SITREP_DB.spawnSpots and SITREP_DB.spawnSpots[map] or {}) do
		if sp.n >= SPOT_MIN and #sp.t > 0 then
			local fit = "ok"
			if sp.hi and ns.XP and ns.XP.MobXP(sp.hi, me) == 0 then fit = "grey"
			elseif sp.lo and sp.lo > me + 3 then fit = "high" end
			out[#out + 1] = { key = key, spot = sp, mid = middleOf(sp.t), fit = fit }
		end
	end
	table.sort(out, function(a, b)
		if (a.fit == "ok") ~= (b.fit == "ok") then return a.fit == "ok" end
		if a.mid ~= b.mid then return a.mid < b.mid end
		return a.spot.k > b.spot.k
	end)
	return out
end

local function mins(s) return s >= 60 and string.format("%d:%02d", math.floor(s / 60), s % 60) or (s .. "s") end
-- /sitrep spawns
function SP.Report()
	ns.Capture("spawns", function()
		local cvar = GetCVar and GetCVar("nameplateMaxDistance")
		local mine = ns.P and ns.P.plates and ns.P.plates.reach or 0
		ns.print("plates: the client's distance %s%s, the farthest a plate appeared since it was set: at least %d yd",
			tostring(cvar), mine > 0 and " (set by SITREP)" or "", SP.reach)
		local list = {}
		for npc, e in pairs(SITREP_DB.spawns or {}) do list[#list + 1] = npc end
		table.sort(list, function(a, b) return (SITREP_DB.spawns[a].n or 0) > (SITREP_DB.spawns[b].n or 0) end)
		if #list == 0 then ns.print("respawn times: none yet (a mob seen dying, and one of its kind seen fresh nearby later)") end
		for _, npc in ipairs(list) do
			local mid, lo, hi, n, name = SP.For(npc)
			if mid then
				ns.print("  %s (%d): about %s (%s to %s), %d seen", tostring(name or "?"), npc, mins(mid), mins(lo), mins(hi), n)
			end
		end
		ns.print("waiting: %d deaths whose mob has not come back yet", #deaths)
	end)
end

-- /sitrep spots [all]: the grinding spots of this map (all: of every map).
function SP.SpotsReport(arg)
	ns.Capture("spots", function()
		local maps = {}
		if arg == "all" then
			for map in pairs(SITREP_DB.spawnSpots or {}) do maps[#maps + 1] = map end
			table.sort(maps)
		else
			local map = here()
			if not map then ns.print("spots: where you are is not known here") return end
			maps[1] = map
		end
		local any = false
		for _, map in ipairs(maps) do
			local list = SP.Spots(map)
			if #list > 0 then
				any = true
				local mname = ns.Quests and ns.Quests.MapName(map)
				ns.print("grinding spots in %s (fastest respawns first):", tostring(mname or map))
				for i, e in ipairs(list) do
					if i > SPOTS_SHOWN then break end
					local sp, names = e.spot, {}
					for _, nm in pairs(sp.kinds) do names[#names + 1] = nm end
					table.sort(names)
					local lv = sp.lo and (sp.lo == sp.hi and tostring(sp.lo) or (sp.lo .. "-" .. sp.hi)) or "?"
					ns.print("  %d. %.0f, %.0f  %s (level %s): back after about %s; %d respawns, %d kills seen%s", i,
						(sp.x or 0) * 100, (sp.y or 0) * 100, table.concat(names, ", "), lv, mins(e.mid), sp.n, sp.k,
						e.fit == "grey" and "  - grey for you" or e.fit == "high" and "  - above you" or "")
				end
			end
		end
		if not any then
			ns.print("spots: none ranked yet here (a spot needs %d respawns seen: kill there and stay a while)", SPOT_MIN)
		end
	end)
end

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) SP.PlateAdded(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() SP.Seen("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() SP.Seen("mouseover") end)
ns.On("UNIT_HEALTH", function(_, unit)
	if unit == "target" or (type(unit) == "string" and unit:find("^nameplate")) then SP.Died(unit) end
end)
-- (a plate goes when its mob dies: a last look)
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) SP.Died(unit) end)
