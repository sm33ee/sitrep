-- SITREP · Travel: flight paths for the quest arrow
-- Is it quicker to fly? The client gives every flight point of a continent with its
-- place on any map of it (C_TaxiMap.GetTaxiNodesForMap); which ones you know is
-- learned at the flight master (TAXIMAP_OPENED, per character), and how long a
-- flight takes is learned from your flights (account-wide; until then it is
-- guessed from the distance). A way by air: walk (or ride) to a known flight
-- point, fly, walk on to the quest; taken when it is clearly quicker than going
-- straight there. The arrow then points at the flight master ("FLY TO ..."), says
-- what to take there, and the quest tracker counts the way with it.
--
-- Self-contained, to take out again in one go: this file and its line in the TOC,
-- Which flight points a character knows only the flight master's window says (it
-- lists all of them at once): a character SITREP has not seen at one plans no
-- flights. That is said where it matters (at login, the quest tracker's tooltip,
-- the world map) rather than kept quiet. Kept per character by its GUID (two
-- characters may share a first name on Forever).
--
-- the call in UI/QuestArrow.lua (ns.Travel.Plan), the one in Quests.lua (Q.Value),
-- the "Flight paths" switch on the Quests page and its default quests.travel, its
-- doctor line, and its block in tests/run.lua.

local ADDON, ns = ...
local read = ns.read
local floor, sqrt = math.floor, math.sqrt
local format = string.format

local TR = {}
ns.Travel = TR
local RUN = 7            -- yards a second on foot
local FLY = 30           -- yards a second a flight covers, straight line (guess until learned)
local OVERHEAD = 20      -- seconds at the flight master and getting off
local WINDING = 1.25     -- a way on the ground is about this much longer than the straight line (roads, hills)
TR.WINDING = WINDING
local QUICKER = 0.8      -- flying must take at most this share of going straight there
local SAVE_MIN = 45      -- ... and save at least this many seconds
local PLAN_EVERY = 2     -- seconds between plans for the same target

local function P() return ns.P and ns.P.quests end
local function book()
	local db = ns.db
	if not db then return nil end
	db.flight = db.flight or { known = {}, times = {} }
	db.flight.known = db.flight.known or {}
	db.flight.times = db.flight.times or {}
	return db.flight
end
local function byName()
	local name, realm = read(UnitName, "player"), read(GetRealmName)
	return tostring(name) .. "-" .. tostring(realm)
end
local function me()
	local guid = read(UnitGUID, "player")
	return type(guid) == "string" and guid or byName()
end

-- The flight points you know (this character): { [name] = true }.
function TR.Known()
	local b = book()
	if not b then return {} end
	local key = me()
	if not b.known[key] then
		-- (kept under the first name and realm before 4.9.17: moved to the GUID)
		local old = byName()
		b.known[key] = b.known[old] or {}
		if old ~= key then b.known[old] = nil end
	end
	return b.known[key]
end

-- Has this character been seen at a flight master (so its flight points are known)?
function TR.Checked()
	local b = book()
	if not b then return false end
	b.checked = b.checked or {}
	return b.checked[me()] == true or next(TR.Known()) ~= nil
end
TR.HINT = "SITREP does not know this character's flight points yet: talk to any flight master once (it lists all you have), and the quest arrow plans flights."


-- Every flight point placed on a map: { { name, x, y } } (cached per map).
local nodeCache = {}
function TR.Nodes(map)
	if nodeCache[map] then return nodeCache[map] end
	local out = {}
	local TM = C_TaxiMap
	if TM and TM.GetTaxiNodesForMap and map then
		local ok, nodes = pcall(TM.GetTaxiNodesForMap, map)
		if ok and type(nodes) == "table" then
			for _, n in ipairs(nodes) do
				local name, pos = ns.plain(n.name), n.position
				local x, y = pos and ns.plain(pos.x), pos and ns.plain(pos.y)
				if type(name) == "string" and type(x) == "number" and type(y) == "number" then
					out[#out + 1] = { name = name, x = x, y = y, faction = ns.plain(n.faction) }
				end
			end
		end
	end
	if #out > 0 then nodeCache[map] = out end -- (an empty answer is asked again: the client may not have them yet)
	return out
end

local function yards(map, x0, y0, x1, y1)
	local w, h = ns.Quests.MapSize(map)
	if not w then return nil end
	local dx, dy = (x1 - x0) * w, (y1 - y0) * h
	return sqrt(dx * dx + dy * dy)
end

local function nodeOn(map, name)
	for _, n in ipairs(TR.Nodes(map)) do if n.name == name then return n end end
	return nil
end

-- Seconds a flight from one point to another takes: learned, or guessed from the
-- straight distance on a map that has both.
function TR.FlightTime(from, to, map)
	local b = book()
	local learned = b and b.times[from .. ">" .. to]
	if learned then return learned, true end
	local a, c = nodeOn(map, from), nodeOn(map, to)
	local d = a and c and yards(map, a.x, a.y, c.x, c.y)
	return d and d / FLY * 1.3 or nil, false
end

-- How fast you go on the ground now: your run speed as the client says (on a
-- mount: the mount's), else the riding speed learned while mounted, else on foot.
-- (Until 4.9.18 the riding speed was used on foot too: walking looked quicker.)
function TR.Speed()
	local ok, _, run = pcall(function() return GetUnitSpeed("player") end)
	if ok and type(run) == "number" and not ns.isSecret(run) and run > 0 then return run end
	if IsMounted and read(IsMounted) and ns.Quests.rideSpeed then return ns.Quests.rideSpeed end
	return RUN
end

-- The quickest way by air to a target, or nil: going there on the ground is as quick.
-- Ways on the ground count WINDING times their straight line (until 4.9.18 the
-- straight line itself: through the mountains, walking looked quicker than it is).
-- { from, to, total (s), walkTo (yd), walkOn (yd), fly (s), learned, direct (s or nil), fromNode = { map, x, y } }
-- why (a table, for /sitrep flyprobe): filled with what was weighed.
local planCache = {}
function TR.Plan(here, target, why)
	if not (P() and P().travel and here and target and target.map) then
		if why then why.reason = not (P() and P().travel) and "flight paths are off (Quests page)" or "no place for you or the quest" end
		return nil
	end
	local known = TR.Known()
	if not next(known) then
		if why then why.reason = "no flight points known for this character" end
		return nil
	end
	local cx, cy = floor(here.x * 100), floor(here.y * 100)
	local ck = here.map .. ":" .. cx .. ":" .. cy .. ">" .. target.map .. ":" .. floor(target.x * 1000) .. ":" .. floor(target.y * 1000)
	local c = planCache[ck]
	local now = GetTime()
	if c and now - c.at < PLAN_EVERY and not why then return c.plan end
	local speed = TR.Speed()
	local straight = ns.Quests.Vector(here, target)
	local direct = straight and straight * WINDING / speed or nil
	if why then why.speed, why.straight, why.direct, why.tried = speed, straight, direct, {} end
	local best
	for _, s in ipairs(TR.Nodes(here.map)) do
		if known[s.name] then
			local walkTo = yards(here.map, here.x, here.y, s.x, s.y)
			if walkTo then
				for _, e in ipairs(TR.Nodes(target.map)) do
					if known[e.name] and e.name ~= s.name then
						local walkOn = yards(target.map, e.x, e.y, target.x, target.y)
						local fly, learned = TR.FlightTime(s.name, e.name, here.map)
						if why then why.tried[#why.tried + 1] = { from = s.name, to = e.name, walkTo = walkTo, walkOn = walkOn, fly = fly } end
						if walkOn and fly then
							local total = (walkTo + walkOn) * WINDING / speed + fly + OVERHEAD
							if not best or total < best.total then
								best = { from = s.name, to = e.name, total = total, walkTo = walkTo, walkOn = walkOn, fly = fly, learned = learned,
									direct = direct, fromNode = { map = here.map, x = s.x, y = s.y } }
							end
						end
					end
				end
			end
		end
	end
	if why then why.best = best end
	if best and direct and not (best.total <= direct * QUICKER and direct - best.total >= SAVE_MIN) then
		if why then why.reason = format("flying (%s) is not quick enough against the ground (%s): it must take at most %d%% of it and save %d s",
			TR.Clock(best.total), TR.Clock(direct), QUICKER * 100, SAVE_MIN) end
		best = nil
	elseif why and not best then
		why.reason = "no pair of known flight points with a place on these maps"
	end
	planCache[ck] = { at = now, plan = best }
	return best
end

-- /sitrep flyprobe: why the arrow does or does not lead to a flight master, for the
-- quest you navigate to.
function TR.Probe()
	ns.Capture("flyprobe", function()
		local q = ns.Quests.Selected()
		local here = ns.Quests.Here()
		if not q or not q.target then ns.print("flyprobe: choose a quest with a place first (click it in the tracker)") return end
		local why = {}
		local plan = TR.Plan(here, q.target, why)
		local known = {}
		for name in pairs(TR.Known()) do known[#known + 1] = name end
		table.sort(known)
		ns.print("flyprobe: %s; you on map %s, it on map %s; flight points known: %s", q.title or "?", tostring(here and here.map), tostring(q.target.map),
			#known > 0 and table.concat(known, ", ") or "none")
		if why.speed then
			ns.print("  on the ground: %.1f yd/s, straight %s yd, about %s (x%.2f for the way's bends)", why.speed,
				why.straight and floor(why.straight) or "?", why.direct and TR.Clock(why.direct) or "?", WINDING)
		end
		for _, t in ipairs(why.tried or {}) do
			ns.print("  %s > %s: walk to it %s yd, fly %s, walk on %s yd", t.from, t.to, t.walkTo and floor(t.walkTo) or "?",
				t.fly and TR.Clock(t.fly) or "?", t.walkOn and floor(t.walkOn) or "?")
		end
		if plan then ns.print("  -> fly: %s to %s, %s in all", plan.from, plan.to, TR.Clock(plan.total))
		else ns.print("  -> no flight: %s", tostring(why.reason or "?")) end
	end)
end

---------------------------------------------------------------------------
-- Learning: the flight points you know, how long flights take
---------------------------------------------------------------------------
local atMaster -- the flight point you stand at (the flight master's window open)
ns.On("TAXIMAP_OPENED", function()
	local known = TR.Known()
	local b = book()
	if b then b.checked = b.checked or {}; b.checked[me()] = true end
	atMaster = nil
	local n = NumTaxiNodes and read(NumTaxiNodes) or 0
	for i = 1, n do
		local name, kind = read(TaxiNodeName, i), read(TaxiNodeGetType, i)
		if type(name) == "string" and (kind == "CURRENT" or kind == "REACHABLE") then known[name] = true end
		if kind == "CURRENT" then atMaster = name end
	end
end)

local flight -- { from, at }: in the air
-- the flight point nearest a place (your position on landing)
local function nearestNode(here)
	local best, bd
	for _, n in ipairs(TR.Nodes(here.map)) do
		local d = yards(here.map, here.x, here.y, n.x, n.y)
		if d and (not bd or d < bd) then best, bd = n, d end
	end
	return best and bd and bd < 120 and best.name or nil
end
function TR.Watch(now)
	local onTaxi = UnitOnTaxi and read(UnitOnTaxi, "player")
	now = now or GetTime()
	if onTaxi and not flight then
		flight = { from = atMaster, at = now }
	elseif not onTaxi and flight then
		local here = ns.Quests.Here()
		local to = here and nearestNode(here)
		local b = book()
		if b and flight.from and to and to ~= flight.from then
			local key = flight.from .. ">" .. to
			local dur = now - flight.at
			local old = b.times[key]
			b.times[key] = old and (old * 0.7 + dur * 0.3) or dur
			TR.Known()[to] = true
		end
		flight = nil
	end
end
ns.On("SR_TICK", function() if P() and P().travel then TR.Watch() end end)
function TR.InFlight() return flight ~= nil end
ns.On("PLAYER_ENTERING_WORLD", function() wipe(nodeCache); wipe(planCache) end)

-- once a session, a little after login: the hint, for a character past its first levels
ns.On("SR_LOGIN", function()
	C_Timer.After(12, function()
		if P() and P().travel and not TR.Checked() and (read(UnitLevel, "player") or 1) >= 10 then ns.print(TR.HINT) end
	end)
end)

-- "2:10"
function TR.Clock(sec) return string.format("%d:%02d", floor(sec / 60), floor(sec % 60)) end
