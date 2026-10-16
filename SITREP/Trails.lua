-- SITREP · Trails: the ways you have walked, to route the quest arrow along
-- Addons get no terrain: no paths, no mountains, no caves. But you have walked
-- there: every half second while you move, the cell of the zone's map you are in
-- is marked (400 x 400 cells a map, about 5-12 yd each; the cells between two
-- samples too). For the route the map is coarser: blocks of 4 x 4 cells (about
-- 20-50 yd), and a block counts as known ground when it or a neighbour was walked
-- (a corridor round your ways, so small gaps and two paths side by side join up).
-- The arrow follows a known way only when that is worth it: the straight line to
-- the quest is mostly unknown ground, and a known way there is not much longer
-- (at most DETOUR times the straight distance). It then points at the spot about
-- LOOK yards ahead along that way (steady, not the next few yards), kept for
-- KEEP seconds; near the end of the way, straight at the quest.
-- Two layers per map: outside, and inside (IsIndoors: caves, buildings; the client
-- gives no height). Where you go from one to the other is a door (a cave's
-- mouth): the route may change layers only there, so it leads to the entrance
-- instead of through the rock, and the arrow says ENTRANCE.
-- Kept for the whole account (other characters use them too): SITREP_DB.trails
-- [layer][row] = the row's walked cells as a bit string (base64, 67 characters;
-- layer: the map's ID outside, "<map>i" inside), SITREP_DB.trailDoors[map][cell];
-- written at logout. A zone you level through is a few KB.
-- Water: cells where you swim (IsSwimming) go to a third layer, "<map>w", not to
-- the dry one. They are ground the route may take, but slower: a block with water
-- and no dry cell costs SWIM times its yards (your run speed over your swim speed,
-- as the client gives them; Classic's 7 against 4.72 when it does not). So where
-- the straight line to the quest crosses water you swam, the arrow weighs swimming
-- across against walking round and leads the quicker way.
-- Drawn by hand on the world map (the map's brush, a whole route block at a time;
-- quicker than walking every way): ground ("walk"), water, and two more layers:
--   terrain  "<map>x": rough, where you may get stuck (slopes, rocks, a mob camp):
--            the route takes it only when going round costs more: ROUGH times
--            its yards
--   blocked  "<map>b": no way through (cliffs, walls): the route never enters it,
--            and where the straight line to the quest crosses it the arrow leads
--            round (a longer way than usual, up to 4 times straight)
-- No heights: a bridge over a river is dry ground there (a block walked dry is
-- never water), which is right for the route: you cross it at full speed.
-- Walking on water (WATER_WALK: the shaman's Water Walking, its elixir, Levitate):
-- you are not swimming, yet not on ground: nothing is noted then (in combat the
-- client hides your auras: the state from before the fight holds).
-- A sample is taken every SAMPLE seconds while you move; when the client keeps
-- your speed to itself (secret, in combat), anyway: a sample where you stand
-- costs nothing. /sitrep ways counts this session's samples and why some were
-- not taken, and what is kept per map.
-- Sharing: /sitrep ways export puts every walked cell and door in one text (empty
-- runs packed: "!n!" for n empty characters) to copy; /sitrep ways import takes
-- such a text and adds it to yours (cells and doors joined: importing twice
-- changes nothing).
--
-- Self-contained, to take out again in one go: this file and its line in the TOC,
-- the one call in UI/QuestArrow.lua (ns.Trails.Waypoint), the "Learned paths"
-- switch on the Quests page and its default quests.trails, its doctor line, and
-- its block in tests/run.lua.

local ADDON, ns = ...
local read = ns.read
local floor, abs, max, min = math.floor, math.abs, math.max, math.min
local format = string.format

local T = {}
ns.Trails = T
local N = 400              -- cells per side of a map
local SAMPLE = 0.5         -- seconds between samples
local JUMP = 20            -- cells: farther than this between two samples is a jump (a portal, a taxi)
local B = 4                -- cells per block side (the route's grid: 100 x 100 blocks a map)
local G = 400 / 4          -- blocks per side
local NEAR_GOAL = 6        -- blocks: how far from the quest known ground may end the route
local MAX_STEPS = 12000    -- A* gives up after this many blocks
local LOOK = 50            -- yards ahead along the way the arrow points at
local DETOUR = 2.2         -- a known way at most this many times the straight distance
local KNOWN = 0.6          -- the straight line this much on known ground: go straight
local KEEP = 2             -- seconds a way point is kept
local SWIM = 7 / 4.72      -- how much slower swimming is (when the client does not say)
local ROUGH = 3            -- terrain drawn rough: this much slower than open ground
local WATER_WALK = { 546, 11319, 1706 } -- Water Walking (shaman), Elixir of Water Walking, Levitate
T.WATER_WALK = WATER_WALK
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHARS = math.ceil(N / 6)
T.N = N

local function P() return ns.P and ns.P.quests end
local grids = {}           -- [map] = { [y] = { [x] = true } }: decoded, in memory
local blocks = {}          -- [layer] = { [block] = true }: blocks with walked cells (routing)
local dirty = {}           -- [map] = { [y] = true }: rows changed since the last save

local function store()
	local db = ns.db
	if not db then return nil end
	db.trails = db.trails or {}
	return db.trails
end

-- One row's walked cells <-> a bit string.
function T.EncodeRow(set)
	local out = {}
	for i = 1, CHARS do
		local v = 0
		for k = 0, 5 do
			if set[(i - 1) * 6 + k] then v = v + 2 ^ k end
		end
		out[i] = B64:sub(v + 1, v + 1)
	end
	return table.concat(out)
end
function T.DecodeRow(text)
	local set = {}
	for i = 1, #text do
		local v = (B64:find(text:sub(i, i), 1, true) or 1) - 1
		for k = 0, 5 do
			if floor(v / 2 ^ k) % 2 == 1 then set[(i - 1) * 6 + k] = true end
		end
	end
	return set
end

-- The walked cells of a map (decoded from the saved variables once).
function T.Grid(map)
	local g = grids[map]
	if g then return g end
	g = {}
	local saved = store()
	for y, text in pairs(saved and saved[map] or {}) do g[tonumber(y)] = T.DecodeRow(text) end
	grids[map] = g
	return g
end

-- The layer's key: the map outside, "<map>i" inside.
function T.Layer(map, inside) return inside and (tostring(map) .. "i") or map end
-- The water layer's key: "<map>w"; rough terrain: "<map>x"; no way through: "<map>b".
function T.WaterLayer(map) return tostring(map) .. "w" end
function T.TerrainLayer(map) return tostring(map) .. "x" end
function T.BlockedLayer(map) return tostring(map) .. "b" end
-- How much slower swimming is than going on foot (or riding) right now, and
-- whether the client said (else Classic's).
function T.SwimFactor()
	local ok, cur, run, fly, swim = pcall(function() return GetUnitSpeed("player") end)
	if ok and not ns.isSecret(run) and not ns.isSecret(swim) and type(run) == "number" and type(swim) == "number" and swim > 0 and run > 0 then
		return math.max(1, math.min(4, run / swim)), true
	end
	return SWIM, false
end

function T.Walked(layer, x, y)
	local row = T.Grid(layer)[y]
	return row ~= nil and row[x] == true
end

T.stats = { samples = 0, moving = 0, unreadable = 0, noPlace = 0, taxi = 0, cells = 0, swimming = 0, onWater = 0 }

-- Walking on water now? (a buff that lets you). In combat Forever answers every
-- aura lookup with nil (measured): not asked then, the last answer holds.
local onWater = false
function T.OnWater()
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not get then return false end
	if InCombatLockdown() then return onWater end
	local all = true
	for _, id in ipairs(WATER_WALK) do
		local ok, a = pcall(get, id)
		if not ok or ns.isSecret(a) then all = false
		elseif a ~= nil then onWater = true return true end
	end
	if all then onWater = false end
	return onWater
end
local function mark(layer, x, y)
	if x < 0 or y < 0 or x >= N or y >= N then return end
	local g = T.Grid(layer)
	local row = g[y]
	if not row then row = {}; g[y] = row end
	if row[x] then return false end
	row[x] = true
	T.stats.cells = T.stats.cells + 1
	dirty[layer] = dirty[layer] or {}
	dirty[layer][y] = true
	if blocks[layer] then blocks[layer][floor(y / B) * G + floor(x / B)] = true end
	return true
end
-- A cell no longer walked (edited by hand).
local function unmark(layer, x, y)
	local row = T.Grid(layer)[y]
	if not (row and row[x]) then return false end
	row[x] = nil
	dirty[layer] = dirty[layer] or {}
	dirty[layer][y] = true
	blocks[layer] = nil -- (built again when asked)
	return true
end

-- Doors: cells where you went inside or out (SITREP_DB.trailDoors[map][cell]).
local function doors(map)
	local db = ns.db
	if not db then return {} end
	db.trailDoors = db.trailDoors or {}
	db.trailDoors[map] = db.trailDoors[map] or {}
	return db.trailDoors[map]
end
function T.IsDoor(map, x, y) return doors(map)[y * N + x] == true end
T.Doors = doors -- ([y * N + x] = true; the quest map draws them)
T.B = B

-- every cell on the line from (x0, y0) to (x1, y1)
local function line(x0, y0, x1, y1, fn)
	local dx, dy = abs(x1 - x0), abs(y1 - y0)
	local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
	local err = dx - dy
	while true do
		if fn(x0, y0) == false then return false end
		if x0 == x1 and y0 == y1 then return true end
		local e2 = 2 * err
		if e2 > -dy then err = err - dy; x0 = x0 + sx end
		if e2 < dx then err = err + dx; y0 = y0 + sy end
	end
end

local function cellOf(p) return floor(p.x * N), floor(p.y * N) end

-- Note where you are (and the way from the last sample); inside: in the inside layer;
-- swimming (outside): in the water layer. Going in or out between two samples: the
-- cell is a door, walked in both layers.
local last
function T.Record(here, inside, swimming)
	if not here then last = nil return end
	inside = inside and true or false
	local cx, cy = cellOf(here)
	local layer = (swimming and not inside) and T.WaterLayer(here.map) or T.Layer(here.map, inside)
	if last and last.map == here.map and max(abs(cx - last.x), abs(cy - last.y)) <= JUMP then
		line(last.x, last.y, cx, cy, function(x, y) mark(layer, x, y) end)
		if last.inside ~= inside then
			doors(here.map)[cy * N + cx] = true
			mark(T.Layer(here.map, last.inside), cx, cy)
		end
	else
		mark(layer, cx, cy)
	end
	last = { map = here.map, x = cx, y = cy, inside = inside }
end

local acc = 0
ns.On("SR_TICK", function(_, dt)
	if not (P() and P().trails) then return end
	acc = acc + (dt or 0)
	if acc < SAMPLE then return end
	acc = 0
	local st = T.stats
	st.samples = st.samples + 1
	-- standing still: nothing to note; a speed the client keeps secret: noted anyway
	local speed = GetUnitSpeed and read(GetUnitSpeed, "player")
	if speed == nil then st.unreadable = st.unreadable + 1
	elseif speed <= 0 then return
	else st.moving = st.moving + 1 end
	if _G.UnitOnTaxi and read(_G.UnitOnTaxi, "player") then st.taxi = st.taxi + 1; last = nil return end
	local here = ns.Quests.Here()
	if not here then st.noPlace = st.noPlace + 1 return end
	local swimming = _G.IsSwimming and read(_G.IsSwimming) == true
	if swimming then st.swimming = st.swimming + 1
	elseif T.OnWater() then st.onWater = st.onWater + 1; last = nil return end -- (on water: neither ground nor water to note)
	T.Record(here, _G.IsIndoors and read(_G.IsIndoors), swimming)
end)

-- Into the saved variables (at logout and /reload; also by hand: T.Save()).
function T.Save()
	local saved = store()
	if not saved then return end
	for map, ys in pairs(dirty) do
		saved[map] = saved[map] or {}
		local g = grids[map]
		for y in pairs(ys) do
			-- (a row emptied by hand goes)
			if g[y] and next(g[y]) then saved[map][y] = T.EncodeRow(g[y]) else saved[map][y] = nil; g[y] = nil end
		end
	end
	wipe(dirty)
end
ns.On("PLAYER_LOGOUT", function() T.Save() end)

---------------------------------------------------------------------------
-- Sharing: all walked cells and doors as one text, and back (joined with yours)
---------------------------------------------------------------------------
local EMPTY = B64:sub(1, 1) -- (a character with no walked cell in it)
local function pack(text)
	return (text:gsub(EMPTY .. EMPTY .. EMPTY .. "+", function(run) return "!" .. #run .. "!" end))
end
local function unpackRow(text)
	return (text:gsub("!(%d+)!", function(n) return EMPTY:rep(tonumber(n)) end))
end
T.PREFIX = "SITREP-WAYS:1:"
-- "SITREP-WAYS:1:" layer "=" y ":" row ("," ...) ";" ... ";D" map "=" cell ("," ...) ... ":END"
function T.Export()
	T.Save()
	local parts = {}
	local layers = {}
	for layer in pairs(store() or {}) do layers[#layers + 1] = layer end
	table.sort(layers, function(a, b) return tostring(a) < tostring(b) end)
	for _, layer in ipairs(layers) do
		local rows, ys = {}, {}
		for y in pairs(store()[layer]) do ys[#ys + 1] = tonumber(y) end
		table.sort(ys)
		for _, y in ipairs(ys) do
			local text = store()[layer][y] or store()[layer][tostring(y)]
			if text and text:find("[^" .. EMPTY .. "]") then rows[#rows + 1] = y .. ":" .. pack(text) end
		end
		if #rows > 0 then parts[#parts + 1] = tostring(layer) .. "=" .. table.concat(rows, ",") end
	end
	for map, cells in pairs(ns.db and ns.db.trailDoors or {}) do
		local list = {}
		for cell in pairs(cells) do list[#list + 1] = tostring(cell) end
		table.sort(list)
		if #list > 0 then parts[#parts + 1] = "D" .. tostring(map) .. "=" .. table.concat(list, ",") end
	end
	return T.PREFIX .. table.concat(parts, ";") .. ":END"
end

-- Join a shared text with yours: new cells and doors; nil and why when it is no such text.
function T.Import(text)
	if type(text) ~= "string" then return nil, "no text" end
	text = text:gsub("%s", "")
	if text:sub(1, #T.PREFIX) ~= T.PREFIX then return nil, "not SITREP's ways (it starts with " .. T.PREFIX .. ")" end
	if text:sub(-4) ~= ":END" then return nil, "cut off (the end is missing: copy all of it)" end
	local body = text:sub(#T.PREFIX + 1, -5)
	local added, doorsAdded = 0, 0
	local before = T.stats.cells
	for part in body:gmatch("[^;]+") do
		local key, list = part:match("^([^=]+)=(.*)$")
		if key and key:sub(1, 1) == "D" then
			local map = tonumber(key:sub(2)) or key:sub(2)
			local d = doors(map)
			for word in list:gmatch("[^,]+") do
				local cell = tonumber(word)
				if cell and not d[cell] then d[cell] = true; doorsAdded = doorsAdded + 1 end
			end
		elseif key then
			local layer = tonumber(key) or key
			for ys, row in list:gmatch("(%d+):([^,]+)") do
				local y = tonumber(ys)
				for x in pairs(T.DecodeRow(unpackRow(row))) do mark(layer, x, y) end
			end
		end
	end
	added = T.stats.cells - before
	T.stats.cells = before -- (imported, not walked this session)
	T.Save()
	T.ForgetRoute()
	return added, doorsAdded
end

-- /sitrep ways: this session's samples, and what is kept per map.
function T.Report()
	ns.Capture("ways", function()
		local st = T.stats
		ns.print("ways: %s; this session %d samples: %d moving, %d with the speed kept secret (noted anyway), %d without a place, %d on a flight, %d swimming, %d walking on water (not noted); %d new cells",
			P() and P().trails and "recording" or "OFF (Quests page: Learned paths)", st.samples, st.moving, st.unreadable, st.noPlace, st.taxi, st.swimming,
			st.onWater, st.cells)
		local swim, said = T.SwimFactor()
		ns.print("swimming is %.1f times slower than going on foot right now (%s)", swim, said and "the client's speeds" or "Classic's: the client did not say")
		local layers = {}
		for layer in pairs(store() or {}) do layers[#layers + 1] = layer end
		table.sort(layers, function(a, b) return tostring(a) < tostring(b) end)
		for _, layer in ipairs(layers) do
			local n, rows = 0, 0
			for _, row in pairs(T.Grid(layer)) do
				rows = rows + 1
				for _ in pairs(row) do n = n + 1 end
			end
			local map = tonumber(tostring(layer):match("^(%d+)"))
			local name = map and ns.Quests and ns.Quests.MapName(map)
			ns.print("  %s%s: %d cells in %d rows", tostring(name or layer),
				tostring(layer):find("i$") and " (inside)" or tostring(layer):find("w$") and " (water)"
				or tostring(layer):find("x$") and " (rough terrain)" or tostring(layer):find("b$") and " (no way through)" or "", n, rows)
		end
		if #layers == 0 then ns.print("  nothing kept yet") end
		ns.print("kept for the account (all characters); written at logout")
	end)
end

-- A window to copy the export from, or to paste one into (/sitrep ways export | import).
function T.Window(mode)
	local K = ns.Kit
	local w = T.win
	if not w then
		w = K.Panel(UIParent, 520, 300)
		w:SetPoint("CENTER")
		w:SetFrameStrata("DIALOG")
		w:EnableMouse(true)
		w.title = K.Font(w, 13, K.C.text, K.FONT, "")
		w.title:SetPoint("TOPLEFT", 14, -12)
		w.hint = K.Font(w, 10.5, K.C.dim, K.FONT, "")
		w.hint:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, -4)
		w.hint:SetWidth(490)
		w.hint:SetJustifyH("LEFT")
		w.box = K.EditBox(w, 492, 180, true)
		w.box:SetPoint("TOPLEFT", 14, -56)
		w.box.edit:SetMaxLetters(0)
		w.ok = K.Button(w, "Import", 110, 24, function()
			local added, doorsOrWhy = T.Import(w.box.edit:GetText())
			if added then
				ns.print("ways imported: %d new cells, %d new doors (joined with yours)", added, doorsOrWhy)
				w:Hide()
			else
				w.hint:SetText("|cffff7a5c" .. tostring(doorsOrWhy) .. "|r")
			end
		end, true)
		w.ok:SetPoint("BOTTOMRIGHT", -14, 12)
		w.close = K.Button(w, "Close", 90, 24, function() w:Hide() end)
		w.close:SetPoint("RIGHT", w.ok, "LEFT", -8, 0)
		T.win = w
	end
	w.mode = mode
	if mode == "export" then
		local text = T.Export()
		w.title:SetText("Share your walked ways")
		w.hint:SetText(format("%d characters. Click in the box, select all (Ctrl+A / Cmd+A), copy (Ctrl+C / Cmd+C), and send it to whoever wants it.", #text))
		w.box.edit:SetText(text)
		w.ok:Hide()
		w.box.edit:SetFocus()
		w.box.edit:HighlightText()
	else
		w.title:SetText("Add shared walked ways")
		w.hint:SetText("Paste a text from /sitrep ways export (Ctrl+V / Cmd+V) and press Import: its ways are joined with yours.")
		w.box.edit:SetText("")
		w.ok:Show()
		w.box.edit:SetFocus()
	end
	w:Show()
end

---------------------------------------------------------------------------
-- Editing by hand (the world map's brush): ways noted before water was told apart
-- (4.9.4) may be swims; anything may be wrong
---------------------------------------------------------------------------
-- One route block of a map, drawn by hand:
--   "walk"     ground: all its cells walked dry; terrain and blocked go, water
--              stays (a bridge over it: water and ground are the one pair that
--              may share a block)
--   "water"    water to swim: all its cells water; dry ground, terrain and
--              blocked go (ways walked before 4.9.4 told swimming apart)
--   "terrain"  rough: all its cells terrain; everything else outside goes
--   "blocked"  no way through: all its cells blocked; everything else outside goes
--   "erase"    every cell (dry, water, inside, terrain, blocked) and door in it out
-- Returns the changes (for T.Undo): { { layer, x, y, set } or { "door", map, cell } }.
local PAINT = {
	walk = { fill = "dry", clear = { "terrain", "blocked" } },
	water = { fill = "water", clear = { "dry", "terrain", "blocked" } },
	terrain = { fill = "terrain", clear = { "dry", "water", "blocked" } },
	blocked = { fill = "blocked", clear = { "dry", "water", "terrain" } },
	erase = { clear = { "dry", "water", "inside", "terrain", "blocked" } },
}
function T.EditBlock(map, bx, by, op)
	local how = PAINT[op]
	if not how or bx < 0 or by < 0 or bx >= G or by >= G then return {} end
	local changes, cells = {}, T.stats.cells
	local key = { dry = map, water = T.WaterLayer(map), inside = T.Layer(map, true), terrain = T.TerrainLayer(map), blocked = T.BlockedLayer(map) }
	local x0, y0 = bx * B, by * B
	for y = y0, y0 + B - 1 do
		for x = x0, x0 + B - 1 do
			for _, kind in ipairs(how.clear) do
				if unmark(key[kind], x, y) then changes[#changes + 1] = { key[kind], x, y, false } end
			end
			if how.fill and mark(key[how.fill], x, y) then changes[#changes + 1] = { key[how.fill], x, y, true } end
		end
	end
	if op == "erase" then
		local d = doors(map)
		for y = y0, y0 + B - 1 do
			for x = x0, x0 + B - 1 do
				local k = y * N + x
				if d[k] then d[k] = nil; changes[#changes + 1] = { "door", map, k } end
			end
		end
	end
	T.stats.cells = cells -- (edited, not walked)
	if #changes > 0 then T.ForgetRoute() end
	return changes
end

-- Take changes back (last first).
function T.Undo(changes)
	local cells = T.stats.cells
	for i = #changes, 1, -1 do
		local c = changes[i]
		if c[1] == "door" then doors(c[2])[c[3]] = true
		elseif c[4] then unmark(c[1], c[2], c[3])
		else mark(c[1], c[2], c[3]) end
	end
	T.stats.cells = cells
	T.ForgetRoute()
end

-- How much is kept: maps, walked cells, characters in the saved variables.
function T.Size()
	local saved = store() or {}
	local maps, cells, chars = 0, 0, 0
	for layer, rows in pairs(saved) do
		if type(layer) == "number" then maps = maps + 1 end
		for _, text in pairs(rows) do chars = chars + #text + 8 end
		for _, row in pairs(T.Grid(layer)) do for _ in pairs(row) do cells = cells + 1 end end
	end
	return maps, cells, chars
end

function T.Forget()
	local saved = store()
	if saved then wipe(saved) end
	if ns.db and ns.db.trailDoors then wipe(ns.db.trailDoors) end
	wipe(grids); wipe(dirty); wipe(blocks)
	last = nil
	if T.ForgetRoute then T.ForgetRoute() end
end

---------------------------------------------------------------------------
-- Routing
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Routing, on blocks of B x B cells
---------------------------------------------------------------------------
-- Blocks with walked cells, per layer (built from the cells once, kept up to date
-- by mark).
local function blockKey(bx, by) return by * G + bx end
function T.Blocks(layer)
	local b = blocks[layer]
	if b then return b end
	b = {}
	for y, row in pairs(T.Grid(layer)) do
		for x in pairs(row) do b[blockKey(floor(x / B), floor(y / B))] = true end
	end
	blocks[layer] = b
	return b
end

-- Known ground: the block or one of its neighbours walked (outside: or swum).
local function known(layer, bx, by)
	if bx < 0 or by < 0 or bx >= G or by >= G then return false end
	local b = T.Blocks(layer)
	local w = type(layer) == "number" and T.Blocks(T.WaterLayer(layer)) or nil
	for dy = -1, 1 do
		for dx = -1, 1 do
			local key = blockKey(bx + dx, by + dy)
			if b[key] or (w and w[key]) then return true end
		end
	end
	return false
end
T.Known = known
-- No way through / rough: a block drawn so (outside only).
local function blocked(map, bx, by)
	return T.Blocks(T.BlockedLayer(map))[blockKey(bx, by)] == true
end
T.Blocked = blocked
local function rough(map, bx, by)
	return T.Blocks(T.TerrainLayer(map))[blockKey(bx, by)] == true
end
T.Rough = rough

-- Water to swim (outside only): swum in, here or beside (the route's corridor
-- round a swim is water too), and no dry walked ground here or beside (a shore).
local function wet(map, bx, by)
	local w, d = T.Blocks(T.WaterLayer(map)), T.Blocks(map)
	local water = false
	for dy = -1, 1 do
		for dx = -1, 1 do
			local key = blockKey(bx + dx, by + dy)
			if d[key] then return false end
			if w[key] then water = true end
		end
	end
	return water
end
T.Wet = wet

-- Doors, by block.
local function doorBlocks(map)
	local out = {}
	for k in pairs(doors(map)) do out[blockKey(floor((k % N) / B), floor(floor(k / N) / B))] = true end
	return out
end

-- a binary heap of { f, bx, by, inside }
local function push(h, item)
	h[#h + 1] = item
	local i = #h
	while i > 1 do
		local p = floor(i / 2)
		if h[p][1] <= h[i][1] then break end
		h[p], h[i] = h[i], h[p]
		i = p
	end
end
local function pop(h)
	local top = h[1]
	local n = #h
	h[1] = h[n]
	h[n] = nil
	local i = 1
	while true do
		local l, r, s = 2 * i, 2 * i + 1, i
		if l < n and h[l][1] < h[s][1] then s = l end
		if r < n and h[r][1] < h[s][1] then s = r end
		if s == i then break end
		h[s], h[i] = h[i], h[s]
		i = s
	end
	return top
end

-- the size of a block in yards (the map's size; unknown: a common zone's)
local function blockYards(map)
	local w, h = ns.Quests.MapSize(map)
	return (w or 3000) / G, (h or 2000) / G
end

-- The shortest way over known ground, block by block ({ bx, by, inside } each),
-- from one block to another (nil: none). Layers change only at doors.
function T.Route(map, sx, sy, gx, gy, sIn, gIn)
	sIn, gIn = sIn and true or false, gIn and true or false
	local bw, bh = blockYards(map)
	local swim = (T.SwimFactor())
	local function dist(x0, y0, x1, y1)
		local dx, dy = (x1 - x0) * bw, (y1 - y0) * bh
		return math.sqrt(dx * dx + dy * dy)
	end
	local doorsHere = doorBlocks(map)
	local function sk(x, y, inside) return (inside and G * G or 0) + y * G + x end
	local start = sk(sx, sy, sIn)
	local open, g, from, closed = {}, { [start] = 0 }, {}, {}
	push(open, { dist(sx, sy, gx, gy), sx, sy, sIn })
	local steps = 0
	while #open > 0 do
		local cur = pop(open)
		local x, y, inside = cur[2], cur[3], cur[4]
		local k = sk(x, y, inside)
		if x == gx and y == gy and inside == gIn then
			local path = {}
			while k do
				local c = k % (G * G)
				table.insert(path, 1, { c % G, floor(c / G), k >= G * G })
				k = from[k]
			end
			return path, g[sk(gx, gy, gIn)]
		end
		if not closed[k] then
			closed[k] = true
			steps = steps + 1
			if steps > MAX_STEPS then return nil end
			local layer = T.Layer(map, inside)
			local function relax(nx, ny, nIn, cost)
				local nk = sk(nx, ny, nIn)
				if not closed[nk] and (not g[nk] or cost < g[nk]) then
					g[nk], from[nk] = cost, k
					push(open, { cost + dist(nx, ny, gx, gy), nx, ny, nIn })
				end
			end
			for dy = -1, 1 do
				for dx = -1, 1 do
					if (dx ~= 0 or dy ~= 0) and known(layer, x + dx, y + dy) and (inside or not blocked(map, x + dx, y + dy)) then
						-- (water: as many yards, but slower: its cost in yards on foot)
						local slow = 1
						if not inside then
							if rough(map, x + dx, y + dy) then slow = ROUGH elseif wet(map, x + dx, y + dy) then slow = swim end
						end
						relax(x + dx, y + dy, inside, g[k] + dist(x, y, x + dx, y + dy) * slow)
					end
				end
			end
			if doorsHere[blockKey(x, y)] then relax(x, y, not inside, g[k] + 1) end
		end
	end
	return nil
end

-- How much of the straight line from one block to another is known ground (0..1).
local function knownShare(layer, x0, y0, x1, y1)
	local n, k = 0, 0
	line(x0, y0, x1, y1, function(x, y)
		n = n + 1
		if known(layer, x, y) then k = k + 1 end
	end)
	return n > 0 and k / n or 1
end
T.KnownShare = knownShare

-- the known block nearest to (bx, by) within r blocks in a layer (nil: none)
local function nearestKnown(layer, bx, by, r)
	if known(layer, bx, by) then return bx, by, 0 end
	local best, rx, ry
	for dy = -r, r do
		for dx = -r, r do
			local d = dx * dx + dy * dy
			if d <= r * r and (not best or d < best) and known(layer, bx + dx, by + dy) then best, rx, ry = d, bx + dx, by + dy end
		end
	end
	return rx, ry, best
end

-- Where the quest arrow should point (a map point { map, x, y, kind = "path",
-- door = true when it is the way in or out, yards = the way's length }), or nil:
-- straight at the target. inside: are you indoors now.
local cache = {}
-- (the ways changed: the way point is worked out again)
function T.ForgetRoute() cache = {} end
function T.Waypoint(here, target, inside)
	if not (P() and P().trails and here and target and target.map == here.map) then return nil end
	inside = inside and true or false
	local map = here.map
	local sx, sy = floor(here.x * G), floor(here.y * G)
	local tx, ty = floor(target.x * G), floor(target.y * G)
	local now = GetTime()
	if cache.map == map and cache.tx == tx and cache.ty == ty and cache.inside == inside and now - cache.at < KEEP
		and math.abs(cache.sx - sx) <= 1 and math.abs(cache.sy - sy) <= 1 then
		return cache.wp
	end
	local wp = T.Plan(map, sx, sy, tx, ty, inside)
	cache = { map = map, sx = sx, sy = sy, tx = tx, ty = ty, inside = inside, at = now, wp = wp }
	return wp
end

function T.Plan(map, sx, sy, tx, ty, inside)
	local layer = T.Layer(map, inside)
	local bw, bh = blockYards(map)
	local function yards(x0, y0, x1, y1)
		local dx, dy = (x1 - x0) * bw, (y1 - y0) * bh
		return math.sqrt(dx * dx + dy * dy)
	end
	local straight = yards(sx, sy, tx, ty)
	if straight < LOOK then return nil end -- (nearly there)
	-- the target's layer: whichever has known ground nearer to it (outside if equal)
	local ox, oy, od = nearestKnown(map, tx, ty, NEAR_GOAL)
	local ix, iy, id = nearestKnown(T.Layer(map, true), tx, ty, NEAR_GOAL)
	local gIn = id ~= nil and (od == nil or id < od)
	local gx, gy = ox, oy
	if gIn then gx, gy = ix, iy end
	if not gx then return nil end -- no known ground near the quest
	-- water on the straight line (outside): swimming across is slower; its cost in
	-- yards on foot, to weigh against walking round
	-- water and rough terrain on it: slower; ground with no way through: never straight on
	local wetShare, roughShare, crossesTerrain = 0, 0, false
	if not inside then
		local n, w, r = 0, 0, 0
		line(sx, sy, tx, ty, function(x, y)
			n = n + 1
			if rough(map, x, y) then r = r + 1 elseif wet(map, x, y) then w = w + 1 end
			if blocked(map, x, y) then crossesTerrain = true end
		end)
		wetShare, roughShare = n > 0 and w / n or 0, n > 0 and r / n or 0
	end
	local straightCost = straight * (1 + ((T.SwimFactor()) - 1) * wetShare + (ROUGH - 1) * roughShare)
	local slowLine = wetShare > 0 or roughShare > 0
	if gIn == inside and not slowLine and not crossesTerrain and knownShare(layer, sx, sy, tx, ty) >= KNOWN then return nil end -- the straight line is known
	local ax, ay = nearestKnown(layer, sx, sy, 2)
	if not ax then return nil end
	local path, len = T.Route(map, ax, ay, gx, gy, inside, gIn)
	-- (round terrain to avoid: a longer way is still better than getting stuck)
	if not path or #path < 2 or len > straight * (crossesTerrain and 4 or DETOUR) then return nil end
	-- across the water is quicker than round it: straight on (swim)
	-- (the route that swims straight across costs about as much: a little slack)
	if slowLine and not crossesTerrain and gIn == inside and knownShare(layer, sx, sy, tx, ty) >= KNOWN and len >= straightCost * 0.95 then return nil end
	-- about LOOK yards along the way; a door within half as much again ends it
	-- there: that is where you go in or out
	local walked, pick, door = 0, path[#path], false
	for i = 2, #path do
		local a, c = path[i - 1], path[i]
		if c[3] ~= a[3] then pick, door = a, true break end
		walked = walked + yards(a[1], a[2], c[1], c[2])
		if walked >= LOOK then
			pick = c
			-- a door just ahead: lead to it instead
			for j = i + 1, #path do
				local d0, d1 = path[j - 1], path[j]
				if d1[3] ~= d0[3] then pick, door = d0, true break end
				if yards(c[1], c[2], d1[1], d1[2]) > LOOK * 0.5 then break end
			end
			break
		end
	end
	if not door and walked < LOOK then return nil end -- (the known way is shorter than that: straight on)
	return { map = map, x = (pick[1] + 0.5) / G, y = (pick[2] + 0.5) / G, kind = "path", door = door, yards = len }
end
