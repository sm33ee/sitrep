-- SITREP · Questbook: what a quest was, kept for your next character; a route from it
-- Quests.lua learns where a quest is given and where its counters go up, but only
-- while the quest is in your log. When you hand one in, the questbook keeps it for
-- the whole account (SITREP_DB.questbook[questID]):
--   t, lv, xp   its title, level and the experience it gave
--   g           where it was given ({ map, x, y }: where you stood when you took it)
--   o           per objective: its text (counts left out) and the middle of where
--               its counter went up
--   h           where it was handed in (where you stood)
--   n           how often it was handed in (by any of your characters)
-- A few hundred bytes a quest.
-- The route (/sitrep route): on the map you are on, what to do in what order:
-- quests in the book this character has not done and may take (its level up to
-- LEVEL_UP over yours), to be picked up at their giver; the quests in your log with
-- a known place; each objective with a known place; then the hand-in (the book's,
-- else the giver). Always the nearest stop that may come next (a quest is picked
-- up before its objectives, the hand-in comes after them): a quick route, not the
-- shortest there is. The arrow can lead along it (Quests: the first stop's quest
-- selected).
--
-- Self-contained, to take out in one go: this file and its line in the TOC, the
-- "route" command in Core.lua, the hand-in place in Quests.Target, and its block
-- in tests/run.lua.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format = string.format

local QB = {}
ns.Questbook = QB
local LEVEL_UP = 2 -- quests up to this many levels over yours go on the route
local MAX_STOPS = 12

local function book()
	if not SITREP_DB then return {} end
	SITREP_DB.questbook = SITREP_DB.questbook or {}
	return SITREP_DB.questbook
end
QB.Book = book

local function pt(p) return p and p.map and { map = p.map, x = p.x, y = p.y } or nil end
local function bareText(t) return type(t) == "string" and (t:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("[:%s]*%d+%s*/%s*%d+%s*$", "")) or nil end
QB.BareText = bareText

-- A quest handed in: kept with what Quests.lua learned of it while it was in the log.
function QB.TurnedIn(id, xp)
	id = tonumber(plain(id))
	if not id then return end
	local Q = ns.Quests
	local e = book()[id] or { n = 0 }
	book()[id] = e
	local data = Q.Store()[id] or {}
	local q
	for _, x in ipairs(Q.List()) do if x.id == id then q = x break end end
	e.t = (q and q.title) or data.title or e.t
	e.lv = (q and q.level) or e.lv
	xp = tonumber(plain(xp))
	if xp and xp > 0 then e.xp = xp end
	e.g = pt(data.giver) or e.g
	e.o = e.o or {}
	for n, samples in pairs(data.obj or {}) do
		local m = Q.Middle(samples)
		if m then e.o[n] = { map = m.map, x = m.x, y = m.y, text = e.o[n] and e.o[n].text } end
	end
	if q then
		for n, o in ipairs(q.objectives) do
			e.o[n] = e.o[n] or {}
			e.o[n].text = bareText(o.text) or e.o[n].text
		end
	end
	e.h = pt(Q.Here()) or e.h
	e.n = (e.n or 0) + 1
end

-- Where a quest was handed in before ({ map, x, y, kind = "turnin" }), or nil.
function QB.HandIn(id)
	local e = SITREP_DB and SITREP_DB.questbook and SITREP_DB.questbook[id]
	if not (e and e.h) then return nil end
	return { map = e.h.map, x = e.h.x, y = e.h.y, kind = "turnin" }
end

local function doneBefore(id)
	local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
	return f and read(f, id) == true or false
end

-- The stops on this map: { kind ("pickup"/"objective"/"turnin"), id, title, text,
-- map, x, y, xp, after = { stops that must come first } }.
function QB.Stops(map)
	local Q = ns.Quests
	local stops = {}
	local function add(s)
		if s.map ~= map then return nil end
		stops[#stops + 1] = s
		return s
	end
	local me = read(UnitLevel, "player") or 1
	local inLog = {}
	for _, q in ipairs(Q.List()) do
		inLog[q.id] = true
		if not q.failed then
			local e = book()[q.id]
			local data = Q.Store()[q.id] or {}
			local before = {}
			if not q.complete then
				for n, o in ipairs(q.objectives) do
					if not o.done then
						local m = (data.obj and data.obj[n] and Q.Middle(data.obj[n], map))
							or (e and e.o and e.o[n] and e.o[n].map and e.o[n])
						if m then
							local s = add({ kind = "objective", id = q.id, title = q.title, text = bareText(o.text), map = m.map, x = m.x, y = m.y })
							if s then before[#before + 1] = s end
						end
					end
				end
			end
			local h = (e and e.h) or (#q.objectives > 0 and data.giver)
			if h then add({ kind = "turnin", id = q.id, title = q.title, map = h.map, x = h.x, y = h.y, xp = e and e.xp, after = before }) end
		end
	end
	for id, e in pairs(book()) do
		if not inLog[id] and e.g and e.g.map == map and not doneBefore(id) and (not e.lv or e.lv <= me + LEVEL_UP) then
			local pick = add({ kind = "pickup", id = id, title = e.t, map = e.g.map, x = e.g.x, y = e.g.y, lv = e.lv })
			local before = {}
			for _, o in pairs(e.o or {}) do
				if o.map then
					local s = add({ kind = "objective", id = id, title = e.t, text = o.text, map = o.map, x = o.x, y = o.y, after = { pick } })
					if s then before[#before + 1] = s end
				end
			end
			before[#before + 1] = pick
			local h = e.h or e.g
			add({ kind = "turnin", id = id, title = e.t, map = h.map, x = h.x, y = h.y, xp = e.xp, after = before })
		end
	end
	return stops
end

-- The route from where you are: the nearest stop that may come next, each time.
-- { stops in order (each with .yards from the one before), total yards, total xp }.
function QB.Route(here)
	here = here or ns.Quests.Here()
	if not here then return nil end
	local w, h = ns.Quests.MapSize(here.map)
	w, h = w or 1000, h or 1000
	local open, done, route = QB.Stops(here.map), {}, {}
	local at = here
	local total, xp = 0, 0
	while #route < MAX_STOPS do
		local best, bestD, bestI
		for i, s in ipairs(open) do
			local ready = true
			for _, b in ipairs(s.after or {}) do if not done[b] then ready = false break end end
			if ready then
				local dx, dy = (s.x - at.x) * w, (s.y - at.y) * h
				local d = math.sqrt(dx * dx + dy * dy)
				if not bestD or d < bestD then best, bestD, bestI = s, d, i end
			end
		end
		if not best then break end
		table.remove(open, bestI)
		done[best] = true
		best.yards = bestD
		route[#route + 1] = best
		total = total + bestD
		xp = xp + (best.kind == "turnin" and best.xp or 0)
		at = best
	end
	return { stops = route, yards = total, xp = xp }
end

local WORD = { pickup = "pick up", objective = "do", turnin = "hand in" }
-- /sitrep route [go]: the route in the chat; "go": the arrow to its first quest.
function QB.Report(arg)
	ns.Capture("route", function()
		local r = QB.Route()
		if not r then ns.print("route: where you are is not known here") return end
		if #r.stops == 0 then
			ns.print("route: nothing known on this map yet (the questbook fills as you hand quests in: %d so far)", (function()
				local n = 0
				for _ in pairs(book()) do n = n + 1 end
				return n
			end)())
			return
		end
		ns.print("route on this map: %d stops, about %.0f yd, %s XP from hand-ins", #r.stops, r.yards, r.xp > 0 and tostring(r.xp) or "?")
		for i, s in ipairs(r.stops) do
			ns.print("  %d. %s %s%s  (%.0f yd)", i, WORD[s.kind], s.title or ("#" .. s.id),
				s.kind == "objective" and s.text and (": " .. s.text) or "", s.yards)
		end
		if arg == "go" then
			local first = r.stops[1]
			local inLog = false
			for _, q in ipairs(ns.Quests.List()) do if q.id == first.id then inLog = true end end
			if inLog then ns.Quests.Select(first.id); ns.print("the arrow leads to %s", first.title or "?")
			else ns.print("the first stop is a quest to pick up: walk to its giver (%.0f yd)", first.yards) end
		end
	end)
end

ns.On("QUEST_TURNED_IN", function(_, id, xp) QB.TurnedIn(id, xp) end)
