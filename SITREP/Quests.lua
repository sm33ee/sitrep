-- SITREP · Quests
-- Your quest log as one list, whichever quest API the client has (the modern
-- C_QuestLog or the classic GetQuestLogTitle family), and where each quest
-- leads you:
--   exact    the client's own quest position (waypoint / map pin), if it has one
--   learned  where your objective counters went up (SITREP learns it as you play:
--            the average of the last places, per objective)
--   giver    for a finished quest with objectives: where you accepted it (most
--            are handed in there; one with nothing to do, a delivery, is not:
--            no guess for it)
-- Positions are zone-map positions (0..1) with the map ID. Distance in yards
-- needs the map's size in yards from the client; direction only needs the map's
-- shape (zone maps are 3:2), so the arrow can point even when the yards are unknown.
-- Learned places are kept in SITREP_DB.quests (lost when the beta forgets saved
-- variables).

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format, sqrt, atan2, abs = string.format, math.sqrt, math.atan2 or math.atan, math.abs
local tonumber = tonumber

local Q = {}
ns.Quests = Q

local texts = {}        -- [quest id] = { desc, task, xp }: quest texts read (Q.Text)
local SAMPLES = 6        -- places kept per objective
local ASPECT = 1.5       -- zone maps are 3:2 (for direction when the size is unknown)

local function store()
	if not SITREP_DB then return {} end
	SITREP_DB.quests = SITREP_DB.quests or {}
	return SITREP_DB.quests
end
Q.Store = store

---------------------------------------------------------------------------
-- Reading the quest log
---------------------------------------------------------------------------
-- "Kobold Vermin slain: 3/8" -> 3, 8
local function counts(text)
	if type(text) ~= "string" then return nil end
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	return tonumber(have), tonumber(need)
end
Q.Counts = counts

-- kind: "monster", "item", "object", "event" ... as the client says (nil: unknown)
local function objective(text, finished, have, need, kind)
	if not (have and need) then have, need = counts(text) end
	return { text = (text or ""):gsub("^%s+", ""), done = finished and true or false, have = have, need = need,
		kind = type(kind) == "string" and kind or nil }
end

local function modernList()
	local CQ = C_QuestLog
	local n = read(CQ.GetNumQuestLogEntries)
	local list, zone = {}, nil
	for i = 1, (n or 0) do
		local info = read(CQ.GetInfo, i)
		if type(info) == "table" then
			if info.isHeader then
				zone = info.title
			elseif not info.isHidden and info.questID then
				local q = { id = info.questID, title = info.title or "?", level = info.level, index = i, zone = zone, objectives = {},
					group = type(info.suggestedGroup) == "number" and info.suggestedGroup > 1 or nil }
				for _, o in ipairs(read(CQ.GetQuestObjectives, info.questID) or {}) do
					q.objectives[#q.objectives + 1] = objective(o.text, o.finished, o.numFulfilled, o.numRequired, o.type)
				end
				q.complete = read(CQ.IsComplete, info.questID) == true or info.isComplete == true or info.isComplete == 1
				list[#list + 1] = q
			end
		end
	end
	return list
end

local function classicList()
	local n = read(GetNumQuestLogEntries)
	local list, zone = {}, nil
	for i = 1, (n or 0) do
		local ok, title, level, suggestedGroup, isHeader, _, isComplete, _, id = pcall(GetQuestLogTitle, i)
		if ok and title then
			if isHeader then
				zone = title
			else
				local q = { id = id or ("i" .. i), title = title, level = level, index = i, zone = zone, objectives = {},
					group = type(suggestedGroup) == "number" and suggestedGroup > 1 or nil }
				for j = 1, (read(GetNumQuestLeaderBoards, i) or 0) do
					local okL, text, kind, finished = pcall(GetQuestLogLeaderBoard, j, i)
					if okL then q.objectives[#q.objectives + 1] = objective(text, finished, nil, nil, kind) end
				end
				local all = #q.objectives > 0
				for _, o in ipairs(q.objectives) do if not o.done then all = false end end
				q.complete = isComplete == 1 or isComplete == true or all
				q.failed = isComplete == -1
				list[#list + 1] = q
			end
		end
	end
	return list
end

-- The quests in your log: { id, title, level, index, zone, complete, objectives }.
function Q.List()
	if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then return modernList() end
	if GetNumQuestLogEntries and GetQuestLogTitle then return classicList() end
	return {}
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
-- Where you are: { map, x, y } on your zone map.
function Q.Here()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local map = read(C_Map.GetBestMapForUnit, "player")
	if not map then return nil end
	local pos = read(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" then return nil end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok or type(x) ~= "number" or ns.isSecret(x) or (x == 0 and y == 0) then return nil end
	return { map = map, x = x, y = y }
end

-- A map's size in yards (cached), or nil when the client does not say.
local sizes = {}
function Q.MapSize(map)
	local s = sizes[map]
	if s ~= nil then return s and s[1], s and s[2] end
	local w, h
	if C_Map.GetMapWorldSize then w, h = read(C_Map.GetMapWorldSize, map) end
	if not (w and w > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local ok, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
		local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))
		if ok and ok2 and type(a) == "table" and type(b) == "table" then
			local okA, ax, ay = pcall(a.GetXY, a)
			local okB, bx, by = pcall(b.GetXY, b)
			if okA and okB and ax and bx then w, h = abs(bx - ax), abs(by - ay) end
			-- world axes run the other way round on some clients: the longer side is the width
			if w and h and h > w then w, h = h, w end
		end
	end
	sizes[map] = (w and w > 0 and h and h > 0) and { w, h } or false
	return sizes[map] and w or nil, sizes[map] and h or nil
end

-- From where you are to a point: yards (nil if the map size is unknown) and the
-- bearing (radians, counter-clockwise from north, like the game's facing).
-- Both nil when the point is on another map.
function Q.Vector(here, to)
	if not (here and to) then return nil end
	if here.map ~= to.map then
		-- the target on a larger map (the continent): where you are on that map, if it
		-- covers you (on another continent it does not: then nil)
		local pos = C_Map and C_Map.GetPlayerMapPosition and read(C_Map.GetPlayerMapPosition, to.map, "player")
		if type(pos) ~= "table" then return nil end
		local ok, x, y = pcall(pos.GetXY, pos)
		if not ok or type(x) ~= "number" or ns.isSecret(x) or (x == 0 and y == 0) then return nil end
		here = { map = to.map, x = x, y = y }
	end
	local w, h = Q.MapSize(here.map)
	local east = (to.x - here.x) * (w or ASPECT)
	local north = -(to.y - here.y) * (h or 1)
	local yards = w and sqrt(east * east + north * north) or nil
	return yards, atan2(-east, north)
end

-- The name of a map (for "in Westfall" when a quest is elsewhere).
function Q.MapName(map)
	local info = C_Map and C_Map.GetMapInfo and read(C_Map.GetMapInfo, map)
	return type(info) == "table" and info.name or nil
end

---------------------------------------------------------------------------
-- Where a quest leads
---------------------------------------------------------------------------
-- The client's own position for the quest, if it has one.
-- The maps worth asking for quest pins: yours, the ones above it (zone,
-- continent), and every continent (a quest handed in on another continent: its
-- pin is on that continent's map, as the game's own marker shows it).
local mapsCache = {} -- [map] = the maps to ask from there (the map tree does not change)
local function mapsToAsk(here)
	local from = here and here.map
	if from and mapsCache[from] then return mapsCache[from] end
	local list, seen = {}, {}
	local function add(m) if m and not seen[m] then seen[m] = true; list[#list + 1] = m end end
	local world
	local m = here and here.map
	while m do
		add(m)
		local info = C_Map.GetMapInfo and read(C_Map.GetMapInfo, m)
		if type(info) ~= "table" then break end
		if info.mapType == 1 or not info.parentMapID or info.parentMapID == 0 then world = m break end -- (the world)
		m = info.parentMapID
	end
	if world and C_Map.GetMapChildrenInfo then
		for _, c in ipairs(read(C_Map.GetMapChildrenInfo, world, 2) or {}) do -- (2: continents)
			if type(c) == "table" then add(c.mapID) end
		end
	end
	if from and world then mapsCache[from] = list end
	return list
end
Q.MapsToAsk = mapsToAsk

-- The quest pins on a map, by quest: asked at most every PIN_KEEP seconds (the
-- client builds a table per quest on each call, and the tracker asks every two
-- seconds for every quest), at once again when the quest log changes.
local pinCache = {} -- [map] = { at, byId = { [questID] = { x, y, zone } } }
local PIN_KEEP = 10
local function pinsOn(map)
	local now = GetTime()
	local c = pinCache[map]
	if c and now - c.at < PIN_KEEP then return c.byId end
	local byId = {}
	for _, pin in ipairs(read(C_QuestLog.GetQuestsOnMap, map) or {}) do
		if type(pin) == "table" and pin.questID and pin.x and pin.y then byId[pin.questID] = { x = pin.x, y = pin.y } end
	end
	pinCache[map] = { at = now, byId = byId }
	return byId
end
function Q.ForgetPins() wipe(pinCache); if Q.ForgetChoices then Q.ForgetChoices() end end

-- Where on a continent's map a point lies: the zone's name ("Wetlands").
local function zoneAt(map, x, y)
	local info = C_Map and C_Map.GetMapInfoAtPosition and read(C_Map.GetMapInfoAtPosition, map, x, y)
	return type(info) == "table" and info.name or nil
end

local function exact(q, here)
	local CQ = C_QuestLog
	if type(q.id) ~= "number" or not CQ then return nil end
	if CQ.GetNextWaypoint then
		local map, x, y = read(CQ.GetNextWaypoint, q.id)
		if map and x and y then return { map = map, x = x, y = y, kind = "exact" } end
	end
	if here and CQ.GetNextWaypointForMap then
		local x, y = read(CQ.GetNextWaypointForMap, q.id, here.map)
		if type(x) == "number" and type(y) == "number" then return { map = here.map, x = x, y = y, kind = "exact" } end
	end
	if CQ.GetQuestsOnMap then
		for _, map in ipairs(mapsToAsk(here)) do
			local pin = pinsOn(map)[q.id]
			if pin then
				local t = { map = map, x = pin.x, y = pin.y, kind = "exact" }
				if not (here and map == here.map) then
					if pin.zone == nil then pin.zone = zoneAt(map, pin.x, pin.y) or false end
					t.zone = pin.zone or nil
				end
				return t
			end
		end
	end
	if here and QuestPOIGetIconInfo then
		local _, x, y = read(QuestPOIGetIconInfo, q.id)
		if type(x) == "number" and type(y) == "number" then return { map = here.map, x = x, y = y, kind = "exact" } end
	end
	return nil
end

-- The middle of the places kept for one objective (the last few count most:
-- they are where you are progressing now).
local function middle(samples, map)
	local n, x, y, onMap = 0, 0, 0, nil
	for _, s in ipairs(samples) do
		if not map or s.map == map then n, x, y, onMap = n + 1, x + s.x, y + s.y, s.map end
	end
	if n == 0 then return nil end
	return { map = onMap, x = x / n, y = y / n }
end
Q.Middle = middle

---------------------------------------------------------------------------
-- Which of a quest's places: the game gives one point per map (for a quest with
-- several areas to farm, the one nearest you as it sees it), and SITREP knows
-- more: where your counters went up (in groups of CLUSTER_YD: two areas are two
-- places, not their middle between them), and the spawn spots of the mobs its
-- open objectives need (Quests.LearnMob; for items also those that dropped them,
-- Drops). Of all these the one you get to quickest wins, on foot or by air
-- (Travel): a farm area beside a flight point you know beats one nearer you on
-- the map but a long walk away. Kept a few seconds per quest (CHOOSE_KEEP) while
-- you stay within CHOOSE_MOVE yards.
---------------------------------------------------------------------------
local CLUSTER_YD, CHOOSE_KEEP, CHOOSE_MOVE, RUN_YDS = 150, 5, 40, 7
local function clusters(points)
	local out = {}
	for _, s in ipairs(points) do
		local w, h = Q.MapSize(s.map)
		local placed
		for _, c in ipairs(out) do
			if c.map == s.map then
				local dx, dy = (s.x - c.x) * (w or 3000), (s.y - c.y) * (h or 2000)
				if dx * dx + dy * dy <= CLUSTER_YD * CLUSTER_YD then
					c.n = c.n + 1
					c.x, c.y = c.x + (s.x - c.x) / c.n, c.y + (s.y - c.y) / c.n
					placed = true
					break
				end
			end
		end
		if not placed then out[#out + 1] = { map = s.map, x = s.x, y = s.y, n = 1 } end
	end
	return out
end
Q.Clusters = clusters

-- The spawn spots by mob (NPC and name), built again at most every INDEX_KEEP
-- seconds: thousands of them in time, asked for every quest in the tracker.
local INDEX_KEEP = 30
local spotIndex, spotIndexAt
local function spotsOf()
	local now = GetTime()
	if spotIndex and now - spotIndexAt < INDEX_KEEP then return spotIndex end
	local byNpc, byName = {}, {}
	for map, cells in pairs(SITREP_DB and SITREP_DB.spawnSpots or {}) do
		for _, sp in pairs(cells) do
			if sp.x then
				local p = { map = map, x = sp.x, y = sp.y }
				for npc, nm in pairs(sp.kinds or {}) do
					byNpc[npc] = byNpc[npc] or {}
					table.insert(byNpc[npc], p)
					if type(nm) == "string" then
						byName[nm] = byName[nm] or {}
						table.insert(byName[nm], p)
					end
				end
			end
		end
	end
	spotIndex, spotIndexAt = { npc = byNpc, name = byName }, now
	return spotIndex
end
function Q.ForgetSpotIndex() spotIndex = nil end

-- Every place an open quest may lead to: { map, x, y, kind ("exact"/"learned"/"spot"), n }.
function Q.Candidates(q, here, game)
	local list = {}
	if game then list[1] = game end
	local data = store()[q.id] or {}
	local mobs = SITREP_DB and SITREP_DB.questMobs and SITREP_DB.questMobs[q.id] or {}
	for n, o in ipairs(q.objectives) do
		if not o.done then
			for _, c in ipairs(clusters(data.obj and data.obj[n] or {})) do
				list[#list + 1] = { map = c.map, x = c.x, y = c.y, kind = "learned", n = n, seen = c.n }
			end
			-- its mobs' spawn spots (by NPC from their tooltips; by name for what dropped its items)
			local names = {}
			if ns.Drops then
				local _, _, _, from = ns.Drops.KillsPerItem(q.id, n)
				for _, nm in ipairs(from or {}) do names[nm] = true end
			end
			local idx, spots, taken = spotsOf(), {}, {}
			local function add(list)
				for _, p in ipairs(list or {}) do
					if not taken[p] then taken[p] = true; spots[#spots + 1] = p end
				end
			end
			for npc, e in pairs(mobs) do if e.n == n then add(idx.npc[npc]) end end
			for nm in pairs(names) do add(idx.name[nm]) end
			for _, c in ipairs(clusters(spots)) do
				list[#list + 1] = { map = c.map, x = c.x, y = c.y, kind = "spot", n = n }
			end
			-- where its mobs were seen in passing (Bestiary): before you ever fought them
			if #spots == 0 and ns.Bestiary then
				local seenAt = {}
				for npc in pairs((ns.Bestiary.MobsFor(q))[n] or {}) do
					for _, p in ipairs(ns.Bestiary.Places(npc)) do seenAt[#seenAt + 1] = p end
				end
				for _, c in ipairs(clusters(seenAt)) do
					list[#list + 1] = { map = c.map, x = c.x, y = c.y, kind = "seen", n = n }
				end
			end
		end
	end
	return list
end

-- How long it takes from here to a place: by air when that is quicker (its plan), else
-- on the ground; nil: not known (another continent, no flight).
function Q.TimeTo(here, t)
	local plan = ns.Travel and ns.Travel.Plan(here, t)
	if plan then return plan.total, plan end
	local yd = Q.Vector(here, t)
	if not yd then return nil end
	local speed = ns.Travel and ns.Travel.Speed() or RUN_YDS
	return yd * (ns.Travel and ns.Travel.WINDING or 1.25) / speed
end

local chosen = {} -- [questID] = { at, map, x, y, target }
-- the choice kept for a quest, if still good here (false: none to keep)
local function kept(q, here)
	local c = chosen[q.id]
	if not (c and c.map == here.map and GetTime() - c.at < CHOOSE_KEEP) then return false end
	local w, h = Q.MapSize(here.map)
	local dx, dy = (here.x - c.x) * (w or 3000), (here.y - c.y) * (h or 2000)
	if dx * dx + dy * dy >= CHOOSE_MOVE * CHOOSE_MOVE then return false end
	return true, c.target
end
-- The place chosen last per quest (kept when the choices are forgotten): another
-- place takes over only when it is clearly quicker (SWITCH_S seconds, or SWITCH_SHARE
-- of the time), so the arrow does not swing between two about as near.
local lastPick = {}
local SWITCH_S, SWITCH_SHARE = 5, 0.1
local function samePlace(a, b) return a and b and a.map == b.map and math.abs(a.x - b.x) < 0.004 and math.abs(a.y - b.y) < 0.004 end
local function choose(q, here, cands)
	local best, bestT, nextT
	local prev, prevCand, prevT = lastPick[q.id], nil, nil
	for _, cand in ipairs(cands) do
		local tm, plan = Q.TimeTo(here, cand)
		if tm and samePlace(cand, prev) then prevCand, prevT = cand, tm; prevCand.byAir = plan ~= nil end
		if tm then
			if not bestT or tm < bestT then
				nextT = bestT
				best, bestT = cand, tm
				best.byAir = plan ~= nil
			elseif not nextT or tm < nextT then
				nextT = tm
			end
		end
	end
	-- (the last one, unless this one is clearly quicker)
	if best and prevCand and prevCand ~= best and prevT - bestT < math.max(SWITCH_S, bestT * SWITCH_SHARE) then
		nextT = bestT
		best, bestT = prevCand, prevT
	end
	if best then
		best.choice = { of = #cands, time = bestT, next = nextT, byAir = best.byAir }
		lastPick[q.id] = { map = best.map, x = best.x, y = best.y }
	end
	chosen[q.id] = { at = GetTime(), map = here.map, x = here.x, y = here.y, target = best }
	return best
end
function Q.ForgetChoices() wipe(chosen) end

-- Where the quest leads now: { map, x, y, kind } or nil.
function Q.Target(q, here)
	local t = exact(q, here)
	local data = store()[q.id] or {}
	if not q.complete and here then
		local ok, keptTarget = kept(q, here)
		if ok then
			if keptTarget then return keptTarget end
		else
			local cands = Q.Candidates(q, here, t)
			if #cands > 1 then
				local best = choose(q, here, cands)
				if best then return best end
			else
				chosen[q.id] = { at = GetTime(), map = here.map, x = here.x, y = here.y, target = nil }
			end
		end
	end
	if t then return t end
	if q.complete then
		-- most quests that sent you to do something are handed in where you got them;
		-- a quest with nothing to do (deliver, talk to someone) is handed in elsewhere:
		-- no guess then. Handed in before (the questbook, by any of your characters): there.
		local h = ns.Questbook and ns.Questbook.HandIn(q.id)
		if h then return h end
		if data.giver and #q.objectives > 0 then return { map = data.giver.map, x = data.giver.x, y = data.giver.y, kind = "giver" } end
		return nil
	end
	-- the first objective still open with places learned (on this map if it has any)
	for n, o in ipairs(q.objectives) do
		local samples = data.obj and data.obj[n]
		if not o.done and samples and #samples > 0 then
			local p = (here and middle(samples, here.map)) or middle(samples)
			if p then p.kind = "learned"; return p end
		end
	end
	return nil
end

-- The quest list with distances and directions, sorted (ui: "distance", "zone", "level").
function Q.Sorted(how)
	local here = Q.Here()
	local list = Q.List()
	local hereZone = here and Q.MapName(here.map)
	for _, q in ipairs(list) do
		q.target = Q.Target(q, here)
		q.yards, q.bearing = Q.Vector(here, q.target)
		q.elsewhere = q.target and here and q.target.map ~= here.map and not q.yards
			and (q.target.zone or Q.MapName(q.target.map)) or nil
		q.here = (q.target and here and q.target.map == here.map) or (hereZone ~= nil and q.zone == hereZone)
	end
	local function lvl(q) return q.level or 0 end
	table.sort(list, function(a, b)
		if how == "level" then
			if lvl(a) ~= lvl(b) then return lvl(a) < lvl(b) end
		elseif how == "zone" then
			if a.here ~= b.here then return a.here end
			if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
		else
			-- nearest first; quests without a distance after them (in this zone first)
			if (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
			if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
			if a.here ~= b.here then return a.here end
		end
		if a.complete ~= b.complete then return a.complete end
		if lvl(a) ~= lvl(b) then return lvl(a) < lvl(b) end
		return (a.title or "") < (b.title or "")
	end)
	return list, here
end

---------------------------------------------------------------------------
-- Learning: where counters go up, where quests are accepted
---------------------------------------------------------------------------
local last           -- [quest id] = { [objective] = count } from the last look
local lastCount      -- quests in the log at the last look
local acceptedAt = -100
Q.learned = 0

-- How many quests are in the log (also those under a collapsed zone header, which
-- the classic list leaves out).
local function questCount()
	local fn = (C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries) or GetNumQuestLogEntries
	local _, n = read(fn)
	return n
end

function Q.Learn()
	if not (ns.P and ns.P.quests.learn) then return end
	local list = Q.List()
	local here = Q.Here()
	local now = {}
	local db = store()
	local count = questCount()
	-- a quest showing up counts as accepted only right after the client said so, or
	-- when a log that held quests holds more (expanding a collapsed zone header shows
	-- quests too; at login the whole log shows up at once, often after an empty look)
	local accepting = GetTime() - acceptedAt < 3 or (count and lastCount and lastCount > 0 and count > lastCount)
	for _, q in ipairs(list) do
		local c = {}
		for n, o in ipairs(q.objectives) do c[n] = o.have or (o.done and 1 or 0) end
		now[q.id] = c
		if last then
			local before = last[q.id]
			if not before and accepting then
				-- new in the log: accepted now, here (from the quest giver standing by)
				db[q.id] = db[q.id] or {}
				if here then db[q.id].giver = { map = here.map, x = here.x, y = here.y } end
				db[q.id].title = q.title
				SITREP_DB.questSeq = (SITREP_DB.questSeq or 0) + 1
				db[q.id].accepted = SITREP_DB.questSeq
				Q.learned = Q.learned + 1
			elseif before then
				for n, v in pairs(c) do
					if v > (before[n] or 0) then
						-- (Drops: what gave it)
						ns.Fire("SR_OBJECTIVE_UP", q.id, n, v - (before[n] or 0), q)
						if here then
							db[q.id] = db[q.id] or { title = q.title }
							local d = db[q.id]
							d.obj = d.obj or {}
							d.obj[n] = d.obj[n] or {}
							table.insert(d.obj[n], { map = here.map, x = here.x, y = here.y })
							while #d.obj[n] > SAMPLES do table.remove(d.obj[n], 1) end
							Q.learned = Q.learned + 1
						end
					end
				end
			end
		end
	end
	-- gone from the list: handed in or abandoned only if the log holds fewer quests
	-- (else it is under a collapsed header: keep it)
	if last then
		local fewer = count and lastCount and count < lastCount
		for id, c in pairs(last) do
			if not now[id] then
				if fewer then
					db[id] = nil
					texts[id] = nil
					if Q.selectedId == id then Q.selectedId = nil end
				else
					now[id] = c
				end
			end
		end
	end
	last, lastCount = now, count
	ns.Fire("SR_QUESTS")
end

-- The quests accepted last (still in the log), newest first: up to n ids.
function Q.Recent(n)
	local list = {}
	for id, d in pairs(store()) do if type(d) == "table" and d.accepted then list[#list + 1] = { id = id, at = d.accepted } end end
	table.sort(list, function(a, b) return a.at > b.at end)
	local out = {}
	for i = 1, math.min(n, #list) do out[i] = list[i].id end
	return out
end

-- Is this NPC part of one of your quests, and what for? Returns the objective's
-- text and the quest's title, or nil. The client's own tooltip lines first (they
-- know drops too); else the NPC's name inside an open objective ("Kobold Vermin
-- slain: 3/8").
-- In a group the tooltip lists the members' progress too: a line naming a member
-- (its own line type, QuestPlayer, or a plain line with a member's name) and their
-- objective lines under it. Only lines under no other name are yours (until 4.11.5
-- the first objective line was taken, whoever's: a member's count showed as yours).
-- Their lines come back third ({ { name, text } }); a mob only the group still needs:
-- nil, nil, those lines, the quest's title.
local function groupNames()
	local out = {}
	if not (IsInGroup and IsInGroup()) then return out end
	local raid = IsInRaid and IsInRaid()
	for i = 1, raid and 40 or 4 do
		local nm = read(UnitName, (raid and "raid" or "party") .. i)
		if type(nm) == "string" and nm ~= "" then out[#out + 1] = nm end
	end
	return out
end
local function sameName(a, b)
	if ns.Targeting and ns.Targeting.SameName then return ns.Targeting.SameName(a, b) end
	return a == b
end
-- The quest lines of a unit's tooltip, read: { title, mine (your first objective),
-- mineSeen, party = { { name, text } } } (nil: no quest lines).
function Q.TipQuestLines(lines)
	local kinds = Enum and Enum.TooltipDataLineType or {}
	local me = read(UnitName, "player")
	local members = groupNames()
	local r = { party = {} }
	local owner -- nil: yours
	for _, l in ipairs(lines) do
		local kind, text = plain(l.type), plain(l.leftText)
		if type(text) == "string" then
			local bare = text:match("^%s*(.-)%s*$")
			if kind == kinds.QuestTitle then
				r.title = r.title or text
				owner = nil
			elseif kinds.QuestPlayer and kind == kinds.QuestPlayer then
				owner = not (me and sameName(bare, me)) and bare or nil
			elseif kind == kinds.QuestObjective then
				if owner then r.party[#r.party + 1] = { name = owner, text = text }
				else r.mineSeen = true; r.mine = r.mine or text end
			elseif r.title then
				for _, nm in ipairs(members) do
					if sameName(bare, nm) then owner = nm break end
				end
				if me and sameName(bare, me) then owner = nil end
			end
		end
	end
	if not (r.title or r.mineSeen or #r.party > 0) then return nil end
	return r
end
function Q.ForUnit(unit)
	if read(UnitIsPlayer, unit) == true then return nil end
	local T = C_TooltipInfo and C_TooltipInfo.GetUnit
	local kinds = Enum and Enum.TooltipDataLineType
	if T and kinds and kinds.QuestObjective then
		local ok, data = pcall(T, unit)
		if ok and type(data) == "table" and not ns.isSecret(data) and type(data.lines) == "table" then
			local r = Q.TipQuestLines(data.lines)
			if r then
				-- yours (or a quest with no objective lines at all, as a loot quest shows)
				if r.mine or (r.title and #r.party == 0) then return r.mine, r.title, r.party end
				-- only the group's lines: not yours to do
				return nil, nil, r.party, r.title
			end
		end
	end
	local name = read(UnitName, unit)
	if type(name) ~= "string" or name == "" then return nil end
	local lname = name:lower()
	for _, q in ipairs(Q.List()) do
		for _, o in ipairs(q.objectives) do
			if not o.done and o.text:lower():find(lname, 1, true) then return o.text, q.title end
		end
	end
	return nil
end

-- Which quest in your log and which of its objectives a tooltip's lines mean
-- (Q.ForUnit's objective and title): the quest and the objective's number, or nil.
-- Counts left out when comparing ("3/8" in one, "4/8" in the other).
local function bare(t) return type(t) == "string" and t:lower():gsub("[%d/:%s%-]", "") or nil end
function Q.Match(objective, title)
	local bo = bare(objective)
	local fallback
	for _, q in ipairs(Q.List()) do
		if not title or q.title == title then
			for n, o in ipairs(q.objectives) do
				if bo and bare(o.text) == bo then return q, n end
			end
			if title and not fallback then fallback = q end
		end
	end
	return fallback, nil
end

-- Navigate to a quest (nil: stop). The arrow and the tracker follow. Kept for the
-- character across a reload (ns.db.chosenQuest[guid]; Q.RestoreChoice).
function Q.Select(id)
	Q.selectedId = id
	local g = ns.db and read(UnitGUID, "player")
	if g then
		ns.db.chosenQuest = ns.db.chosenQuest or {}
		ns.db.chosenQuest[g] = id
	end
	Q.ShowOnMap(id)
	ns.Fire("SR_QUESTS")
end

-- After a login or reload: the quest chosen before, once the log has it (the log
-- fills a moment after login). Gone from the log meanwhile: nothing chosen.
function Q.RestoreChoice()
	if Q.restored or Q.selectedId then Q.restored = true return end
	local g = ns.db and read(UnitGUID, "player")
	local id = g and ns.db.chosenQuest and ns.db.chosenQuest[g]
	if not id then Q.restored = true return end
	local list = Q.List()
	if #list == 0 then return end -- (not filled yet: the next update)
	Q.restored = true
	for _, q in ipairs(list) do
		if q.id == id then Q.Select(id) return end
	end
	ns.db.chosenQuest[g] = nil
end

-- The game's own choice follows the tracker's: the quest it tracks (its map marks
-- that one: super tracking) and the quest log's selection (the map's quest list),
-- so the world map shows the quest you navigate to. Nothing chosen: none tracked.
function Q.ShowOnMap(id)
	local ST = C_SuperTrack
	if ST and ST.SetSuperTrackedQuestID then pcall(ST.SetSuperTrackedQuestID, type(id) == "number" and id or 0) end
	if type(id) ~= "number" then return end
	local CQ = C_QuestLog
	if CQ and CQ.SetSelectedQuest then
		pcall(CQ.SetSelectedQuest, id)
	elseif SelectQuestLogEntry then
		for _, q in ipairs(Q.List()) do
			if q.id == id and q.index then pcall(SelectQuestLogEntry, q.index) break end
		end
	end
end

function Q.Selected()
	local id = Q.selectedId
	if not id or not ns.P then return nil end
	for _, q in ipairs(Q.Sorted(ns.P.quests.sort)) do if q.id == id then return q end end
	return nil
end

-- A quest's texts: its story, its task ("Bring 8 Tough Wolf Meat to ...") and
-- the experience it gives (nil when the client does not say), or nil. The quest log answers for its selected quest only: the quest is
-- selected for the moment of reading and your selection put back. Kept per quest
-- (in texts, declared at the top).
function Q.Text(q)
	local t = texts[q.id]
	if t then return t.desc, t.task, t.xp end
	local desc, task, xp
	local CQ = C_QuestLog
	if CQ and CQ.SetSelectedQuest and CQ.GetSelectedQuest and type(q.id) == "number" then
		local prev = read(CQ.GetSelectedQuest)
		pcall(CQ.SetSelectedQuest, q.id)
		desc, task = read(GetQuestLogQuestText, q.index)
		xp = read(GetQuestLogRewardXP, q.id)
		if prev then pcall(CQ.SetSelectedQuest, prev) end
	elseif SelectQuestLogEntry and GetQuestLogQuestText and q.index then
		local prev = read(GetQuestLogSelection)
		pcall(SelectQuestLogEntry, q.index)
		desc, task = read(GetQuestLogQuestText)
		xp = read(GetQuestLogRewardXP)
		if prev and prev > 0 then pcall(SelectQuestLogEntry, prev) end
	end
	-- (empty: not loaded yet; asked again next time rather than kept empty)
	if type(desc) ~= "string" or desc == "" then desc = nil end
	if type(task) ~= "string" or task == "" then task = nil end
	if type(xp) ~= "number" or xp <= 0 then xp = nil end
	if desc or task or xp then texts[q.id] = { desc = desc, task = task, xp = xp } end
	return desc, task, xp
end

-- Put the quest's link into the chat: into the open input line, else a new one
-- with it. The modern quest API wants the quest's ID, the classic one its log line.
-- Without a link from the client: "[title]" as text.
function Q.Link(q)
	local link
	if GetQuestLink then
		local modern = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries
		local key = modern and q.id or q.index
		if key then link = read(GetQuestLink, key) end
	end
	if type(link) ~= "string" or link == "" then link = "[" .. tostring(q.title) .. "]" end
	if ChatEdit_InsertLink and read(ChatEdit_InsertLink, link) then return link end
	if ChatFrame_OpenChat then pcall(ChatFrame_OpenChat, link) end
	return link
end

-- The quest log at this quest.
function Q.Open(q)
	if QuestMapFrame_OpenToQuestDetails and type(q.id) == "number" then
		pcall(QuestMapFrame_OpenToQuestDetails, q.id)
		return
	end
	if QuestLogFrame and not QuestLogFrame:IsShown() and ToggleQuestLog then pcall(ToggleQuestLog) end
	if SelectQuestLogEntry then pcall(SelectQuestLogEntry, q.index) end
	if QuestLog_SetSelection then pcall(QuestLog_SetSelection, q.index) end
	if QuestLog_Update then pcall(QuestLog_Update) end
end

-- Is an NPC part of one of your quests (to kill, to loot from, to talk to)? For the
-- nameplates: asked once per kind of NPC (the ID in its GUID: every Kobold Vermin
-- is the same answer), kept until the quest log changes (a kill counted, a quest
-- done). Without a GUID the plate's token is the key (forgotten when the plate
-- goes). Returns the objective's text, the quest's title, and "have/need" if the
-- text counts.
local mobCache = {}
function Q.NpcID(guid)
	return type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
end
-- Which mobs a quest's objectives need, kept for the account once a mob's tooltip
-- said so (SITREP_DB.questMobs[questID][npcID] = { n = objective, name }): the
-- quest map (UI/QuestMap) finds their spawn spots by it.
function Q.LearnMob(questID, n, npc, name)
	if not (SITREP_DB and questID and n and npc) then return end
	SITREP_DB.questMobs = SITREP_DB.questMobs or {}
	local m = SITREP_DB.questMobs[questID] or {}
	SITREP_DB.questMobs[questID] = m
	m[npc] = { n = n, name = type(name) == "string" and name or (m[npc] and m[npc].name) }
end
-- Your own count of an objective a tooltip names: from your quest log (the tooltip
-- may show a group member's), else the words' own numbers.
function Q.MyCounts(objective, title)
	local q, n = Q.Match(objective, title)
	local o = q and n and q.objectives[n]
	if o and o.have and o.need then return o.have, o.need end
	return counts(objective)
end
function Q.MobOf(unit, guid)
	local npc = Q.NpcID(guid)
	local key = npc or ("U:" .. unit)
	local c = mobCache[key]
	if c == nil then
		local objective, title = Q.ForUnit(unit)
		local have, need
		if objective then have, need = Q.MyCounts(objective, title) end
		c = (objective or title) and { objective, title, have and need and format("%d/%d", have, need) or nil } or false
		mobCache[key] = c
		if c and objective and npc then
			local q, n = Q.Match(objective, title)
			if q and n then Q.LearnMob(q.id, n, npc, read(UnitName, unit)) end
		end
	end
	if c then return c[1], c[2], c[3] end
	return nil
end
function Q.ForgetMob(unit) mobCache["U:" .. unit] = nil end
function Q.ForgetMobs() wipe(mobCache) end

---------------------------------------------------------------------------
-- Is a quest worth it? Its experience per minute against what killing mobs gives
-- you. Your own pace is learned: the seconds between kills that gave experience
-- (gaps over PACE_GAP s are travel or a break: left out) and the experience per
-- kill, both kept across sessions (SITREP_DB.pace); your riding speed is learned
-- when you ride. A quest's time: the way there at your speed, plus per open
-- objective what is left times your seconds per kill (things to collect: the kills
-- per item learned (Drops.lua), else 1.6 each; anything else a minute); a group quest
-- alone takes 2.5 times as long, one 3 or more levels above you a quarter longer
-- per level. Ready to hand in: only the way. Its experience: the reward plus what
-- the kills on the way give (they count for the quest and for you). Quests close
-- together share the way: each of the others whose place is within NEAR_YD of
-- this one's takes a share of it (at most SHARE_MAX of them). Almost done (ALMOST
-- of its counts reached): worth ALMOST_UP more and never "poor" (a few kills
-- from a reward). Rated against killing mobs: "poor" under POOR of it, "great"
-- over GREAT times it.
---------------------------------------------------------------------------
local PACE_GAP, PACE_DEFAULT, RUN, POOR, GREAT = 120, 30, 7, 0.4, 1.5
local NEAR_YD, SHARE_MAX, ALMOST, ALMOST_UP = 150, 3, 0.66, 1.25
Q.NEAR_YD, Q.ALMOST = NEAR_YD, ALMOST
local lastKillAt
local function pace()
	local db = ns.db
	if not db then return { sec = PACE_DEFAULT } end
	db.pace = db.pace or { sec = PACE_DEFAULT, n = 0 }
	return db.pace
end
Q.Pace = pace
-- a kill that gave experience ("X dies, you gain 87 experience. (+43 Rested bonus)")
function Q.KillXP(text, now)
	text = plain(text)
	if type(text) ~= "string" then return end
	local xp = tonumber(text:match("(%d+)"))
	if not xp or xp <= 0 then return end
	now = now or GetTime()
	local p = pace()
	p.n = (p.n or 0) + 1
	p.xp = p.xp and (p.xp + (xp - p.xp) * 0.15) or xp
	if lastKillAt and now - lastKillAt <= PACE_GAP then
		p.sec = (p.sec or PACE_DEFAULT) + ((now - lastKillAt) - (p.sec or PACE_DEFAULT)) * 0.1
	end
	lastKillAt = now
end
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(_, text) Q.KillXP(text) end)
-- riding speed, learned while mounted (yards per second)
ns.On("SR_TICK", function()
	if not (IsMounted and read(IsMounted)) then return end
	local v = GetUnitSpeed and read(GetUnitSpeed, "player")
	if v and v > RUN and v <= 30 then Q.rideSpeed = math.max(Q.rideSpeed or 0, v) end
end)

-- What killing mobs gives you a minute (the yardstick).
function Q.GrindRate()
	local p = pace()
	local me = read(UnitLevel, "player") or 1
	local xp = p.xp or (ns.XP and ns.XP.MobXP(me, me)) or (me * 5 + 45)
	return xp / (p.sec or PACE_DEFAULT) * 60
end

local function isKill(o)
	if o.kind then return o.kind == "monster" end
	local t = o.text:lower()
	return t:find("slain", 1, true) ~= nil or t:find("getötet", 1, true) ~= nil
end

-- How far along a quest is: its counts reached, 0..1 (nil: nothing to count).
function Q.Progress(q)
	local have, need = 0, 0
	for _, o in ipairs(q.objectives or {}) do
		if o.need and o.need > 0 then
			need = need + o.need
			have = have + (o.done and o.need or math.min(o.have or 0, o.need))
		end
	end
	return need > 0 and have / need or nil
end
-- Almost done: not yet, but most of its counts reached.
function Q.Almost(q)
	if q.complete or q.failed then return false end
	local p = Q.Progress(q)
	return p ~= nil and p >= ALMOST and p < 1
end

-- How many other quests in the list lead to a place near this one's.
function Q.Neighbours(q, list)
	local t = q.target
	if not (t and list) then return 0 end
	local w, h = Q.MapSize(t.map)
	if not w then return 0 end
	local n = 0
	for _, o in ipairs(list) do
		local u = o ~= q and not o.failed and o.target
		if u and u.map == t.map then
			local dx, dy = (u.x - t.x) * w, (u.y - t.y) * h
			if dx * dx + dy * dy <= NEAR_YD * NEAR_YD then n = n + 1 end
		end
	end
	return n
end

-- { xp, minutes, xpm, base, rating ("poor"/"ok"/"great"), travel, work, killXP,
-- near, almost } or nil. list: the other quests (for the shared way).
function Q.Value(q, list)
	local _, _, xp = Q.Text(q)
	if not xp then return nil end
	local p = pace()
	local sec = p.sec or PACE_DEFAULT
	local speed = Q.rideSpeed or RUN
	local travel = (q.yards or 900) / speed
	-- by air, when that is quicker (Travel.lua)
	local plan = ns.Travel and q.target and ns.Travel.Plan(Q.Here(), q.target)
	if plan then travel = plan.total end
	-- the way shared with the quests near it
	local near = math.min(Q.Neighbours(q, list), SHARE_MAX)
	travel = travel / (1 + near)
	local work, kills = 0, 0
	if q.complete then
		work = 15
	else
		for n, o in ipairs(q.objectives) do
			if not o.done then
				local left = math.max(1, (o.need or 1) - (o.have or 0))
				if isKill(o) then work = work + left * sec; kills = kills + left
				elseif o.kind == "item" or (o.need and o.need > 1) then
					local per = ns.Drops and ns.Drops.KillsPerItem(q.id, n) or 1.6
					work = work + left * sec * per; kills = kills + left * per
				else work = work + 60 end
			end
		end
		if q.group and not (IsInGroup and IsInGroup()) then work = work * 2.5 end
		local me = read(UnitLevel, "player")
		local over = me and q.level and q.level - me or 0
		if over >= 3 then work = work * (1 + 0.25 * (over - 2)) end
	end
	local me = read(UnitLevel, "player") or 1
	local killXP = kills * (p.xp or (ns.XP and ns.XP.MobXP(me, me)) or (me * 5 + 45))
	local minutes = (travel + work) / 60
	local xpm = (xp + killXP) / math.max(minutes, 0.25)
	local base = Q.GrindRate()
	local almost = Q.Almost(q)
	local score = almost and xpm * ALMOST_UP or xpm
	local rating = q.complete and "great" or score > base * GREAT and "great" or (score < base * POOR and not almost) and "poor" or "ok"
	return { xp = xp, minutes = minutes, xpm = xpm, base = base, rating = rating, travel = travel, work = work, plan = plan,
		killXP = killXP, near = near, almost = almost }
end

-- a level up changes every quest's experience: read them again
ns.On("PLAYER_LEVEL_UP", function() wipe(texts) end)

-- quests change: look again (the client sends several events per change)
local pending = false
local function soon()
	if pending then return end
	pending = true
	C_Timer.After(0.3, function() pending = false; Q.Learn() end)
end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED" }) do
	ns.On(e, function(_, unit)
		if e == "QUEST_ACCEPTED" then acceptedAt = GetTime() end
		Q.ForgetPins()
		Q.ForgetMobs()
		if e ~= "UNIT_QUEST_LOG_CHANGED" or unit == "player" then soon() end
	end)
end
ns.On("SR_LOGIN", function() Q.Learn(); Q.RestoreChoice() end)
ns.On("QUEST_LOG_UPDATE", function() if not Q.restored then Q.RestoreChoice() end end)

-- /sitrep questprobe: what this client tells about quests and where they are.
function Q.Probe()
	ns.Capture("questprobe", function()
		local CQ = C_QuestLog or {}
		local function has(v) return v ~= nil and "yes" or "no" end
		ns.print("quest log: C_QuestLog.GetInfo %s  GetQuestLogTitle %s  GetQuestObjectives %s  GetQuestLogLeaderBoard %s",
			has(CQ.GetInfo), has(GetQuestLogTitle), has(CQ.GetQuestObjectives), has(GetQuestLogLeaderBoard))
		ns.print("positions: GetNextWaypoint %s  GetQuestsOnMap %s  QuestPOIGetIconInfo %s  GetDistanceSqToQuest %s",
			has(CQ.GetNextWaypoint), has(CQ.GetQuestsOnMap), has(QuestPOIGetIconInfo), has(CQ.GetDistanceSqToQuest))
		local here = Q.Here()
		local w, h
		if here then w, h = Q.MapSize(here.map) end
		ns.print("you: map %s  at %s  map size %s  facing %s  UnitPosition %s",
			tostring(here and here.map), here and format("%.3f, %.3f", here.x, here.y) or "?",
			w and format("%.0f x %.0f yd", w, h) or "unknown", tostring(read(GetPlayerFacing)), tostring(read(UnitPosition, "player")))
		ns.print("Blizzard: QuestWatchFrame %s  ObjectiveTrackerFrame %s  WatchFrame %s  QuestLogFrame %s  QuestMapFrame %s",
			has(_G.QuestWatchFrame), has(_G.ObjectiveTrackerFrame), has(_G.WatchFrame), has(_G.QuestLogFrame), has(_G.QuestMapFrame))
		-- the game's quest pins on the maps SITREP asks (yours, above it, every continent)
		if CQ.GetQuestsOnMap then
			for _, map in ipairs(mapsToAsk(here)) do
				local ids = {}
				for _, pin in ipairs(read(CQ.GetQuestsOnMap, map) or {}) do
					if type(pin) == "table" then ids[#ids + 1] = tostring(pin.questID) end
				end
				ns.print("pins on %s (%s): %s", tostring(map), tostring(Q.MapName(map)), #ids > 0 and table.concat(ids, " ") or "-")
			end
		end
		local exactN = 0
		for i, q in ipairs(Q.List()) do
			local t = exact(q, here)
			if t then exactN = exactN + 1 end
			if i <= 8 then
				local objs = {}
				for _, o in ipairs(q.objectives) do objs[#objs + 1] = format("%s/%s%s", tostring(o.have), tostring(o.need), o.done and "+" or "") end
				local dsq = CQ.GetDistanceSqToQuest and type(q.id) == "number" and read(CQ.GetDistanceSqToQuest, q.id)
				ns.print("  [%s] %s (lvl %s) %s  obj %s  exact %s  distSq %s", tostring(q.id), tostring(q.title), tostring(q.level),
					q.complete and "COMPLETE" or "", table.concat(objs, " "),
					t and format("%s %.3f,%.3f", tostring(t.map), t.x, t.y) or "-", tostring(dsq))
			end
		end
		local first = Q.List()[1]
		if first then
			local desc, task = Q.Text(first)
			local _, _, xp = Q.Text(first)
			ns.print("texts of [%s]: task %s chars, story %s chars, xp %s (SetSelectedQuest %s, GetQuestLogQuestText %s, GetQuestLogRewardXP %s)",
				tostring(first.id), task and #task or "none", desc and #desc or "none", tostring(xp), has(CQ.SetSelectedQuest),
				has(GetQuestLogQuestText), has(GetQuestLogRewardXP))
		end
		ns.print("quests with an exact position from the client: %d; learned places: %d quests", exactN,
			(function() local n = 0 for _ in pairs(store()) do n = n + 1 end return n end)())
	end)
	ns.print("saved; /reload writes it to disk.")
end
