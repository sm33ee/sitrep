-- SITREP · Quest map: what SITREP has learned, drawn on the world map
-- Three layers on the map's canvas (they zoom with it; their text and icons keep
-- one size):
--   quest    (quests.questMap) the quest you navigate to (Quests.Select: a click
--            in the tracker):
--              spots   the spawn spots (Spawns: CELL yards a side) of the mobs its
--                      open objectives need: coral for mobs to kill, gold for mobs
--                      that drop its items; fainter where few kills were seen; the
--                      respawn time on each
--              places  where its counters went up (Quests' learned places): a
--                      mint ring with the objective's number
--              legend  top left: the quest and, per open objective, its mobs with
--                      how fast they come back and, for items, how many kills one
--                      takes; under it what the marks on the map mean
--            Hovering a spot, a place or a flight point says more (QM.Tip): the
--            mobs and their levels, the objective, the respawn's spread, the kills
--            seen there, the drop rate and the kills still to go, how far it is.
--            The marks take the mouse's moves only, not its clicks: the map works
--            as before under them. The one hovered comes forward (its ring full,
--            its fill stronger, a glow round it; a flight point grows), the
--            others step back (QM.Focus).
--            Which mobs: those a mob's tooltip named for the objective
--            (Quests.LearnMob, kept for the account) and those that dropped its
--            items (Drops). A quest new to every character of yours shows little.
--   ways     (quests.mapTrails, off: a debug view; the "Walked ways" button on the
--            map, with a brush to fix them by hand: see the buttons below) the
--            ground Trails knows, in its route blocks (about 20-50 yd):
--            mint walked outside, cyan swum (slower for the route), orange rough
--            terrain and dark red no way through (both drawn by hand), lavender
--            inside (caves, buildings), the doors between them yellow. Where the
--            arrow can lead you round.
--   flights  (quests.mapFlights) every flight point of your faction on the map
--            (the client knows them all): the flight master's icon, no label (its
--            name, known or not and how far, when the mouse is on it); dim where
--            this character has not been (Travel learns that at a flight master:
--            open one once with a character new to SITREP).
--
-- Self-contained, to take out in one go: this file and its line in the TOC, its
-- switches on the Quests page with their defaults (quests.questMap, mapTrails,
-- mapFlights), and its block in tests/run.lua.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format

local QM = {}
ns.QuestMap = QM
local KILL_COL, ITEM_COL, PLACE_COL = { 1, 0.36, 0.30 }, { 1, 0.82, 0.30 }, { 0.44, 0.94, 0.65 }
local SPOT_ALPHA = 0.30
local PLACE_YD = 30 -- the ring round a learned place: yards across
local LEGEND_W = 330
-- Over the map: one strata above the map's own, levels within it. The map draws
-- its explored areas (soft-edged overlays) over anything at its strata: the ways
-- looked faded towards the south (screenshot, 4.9.2, frame levels alone). The
-- canvas still clips them to the map.
local LEVEL = { ways = 10, quest = 20, places = 25, flights = 30, panel = 100 }
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local function above(wm)
	local s = wm and read(wm.GetFrameStrata, wm)
	for i, name in ipairs(STRATA) do
		if name == s then return STRATA[math.min(i + 1, #STRATA)] end
	end
	return "FULLSCREEN"
end
QM.Above = above
-- a frame of ours on the map: its strata over the map's, its level in it
local function lift(f, level)
	local wm = rawget(_G, "WorldMapFrame")
	f:SetFrameStrata(above(wm))
	f:SetFrameLevel(level)
end

local function P() return ns.P and ns.P.quests end
local function on() return P() and P().questMap ~= false and ns.P.enabled end

local function mins(s) return format("%d:%02d", math.floor(s / 60), s % 60) end
local function middle(t)
	local s = {}
	for i, v in ipairs(t) do s[i] = v end
	table.sort(s)
	return s[math.floor((#s + 1) / 2)]
end
local function npcByName(name)
	for npc, e in pairs(SITREP_DB and SITREP_DB.spawns or {}) do if e.name == name then return npc end end
	return nil
end

-- Per objective the mobs it needs: [n] = { [name] = npcID, or true when only the name is known }.
function QM.MobsOf(q)
	local out = {}
	local qm = SITREP_DB and SITREP_DB.questMobs and SITREP_DB.questMobs[q.id]
	for npc, e in pairs(qm or {}) do
		if e.name then
			out[e.n] = out[e.n] or {}
			out[e.n][e.name] = npc
		end
	end
	for n in ipairs(q.objectives) do
		local from = ns.Drops and select(4, ns.Drops.KillsPerItem(q.id, n))
		for _, name in ipairs(from or {}) do
			out[n] = out[n] or {}
			if out[n][name] == nil then out[n][name] = true end
		end
	end
	return out
end

-- What to draw for a quest on a map: { spots, places, lines }.
function QM.Data(q, map)
	local mobs = QM.MobsOf(q)
	local w, h = ns.Quests.MapSize(map)
	local half = (ns.Spawns and ns.Spawns.CELL or 100) / 2
	local rx, ry = w and half / w or 0.025, h and half / h or 0.025
	local cells = SITREP_DB and SITREP_DB.spawnSpots and SITREP_DB.spawnSpots[map] or {}
	local data = ns.Quests.Store()[q.id]
	local spots, places, lines = {}, {}, {}
	for n, o in ipairs(q.objectives) do
		if not o.done and not q.complete then
			local byName = mobs[n] or {}
			local item = ns.Drops and ns.Drops.IsItem(o) or false
			for _, sp in pairs(cells) do
				for _, name in pairs(sp.kinds) do
					if byName[name] and sp.x then
						spots[#spots + 1] = { x = sp.x, y = sp.y, rx = rx, ry = ry, n = n, item = item, name = name, k = sp.k,
							mid = #sp.t > 0 and middle(sp.t) or nil, cell = sp, text = o.text,
							left = o.need and o.have and math.max(0, o.need - o.have) or nil }
						break
					end
				end
			end
			-- no spawn spot of its mobs here yet: where they were seen in passing (Bestiary), faint
			local any = false
			for _, sp in ipairs(spots) do if sp.n == n then any = true break end end
			if not any and ns.Bestiary then
				for npc in pairs((ns.Bestiary.MobsFor(q))[n] or {}) do
					local e = ns.Bestiary.Book()[npc]
					for _, p in ipairs(ns.Bestiary.Places(npc)) do
						if p.map == map then
							spots[#spots + 1] = { x = p.x, y = p.y, rx = rx, ry = ry, n = n, item = item, name = e and e.n, k = 0, seenOnly = p.c,
								cell = { kinds = { [npc] = e and e.n }, k = 0, n = 0, t = {}, lo = e and e.lo, hi = e and e.hi }, text = o.text,
								left = o.need and o.have and math.max(0, o.need - o.have) or nil }
						end
					end
				end
			end
			local m = data and data.obj and data.obj[n] and ns.Quests.Middle(data.obj[n], map)
			if m then
				local seen = 0
				for _, sample in ipairs(data.obj[n]) do if sample.map == map then seen = seen + 1 end end
				places[#places + 1] = { x = m.x, y = m.y, n = n, rx = w and PLACE_YD / 2 / w or 0.012, ry = h and PLACE_YD / 2 / h or 0.012,
					text = o.text, seen = seen }
			end
			-- the legend: its mobs, how fast they come back, how often it drops
			local parts = {}
			for name, npc in pairs(byName) do
				local id = type(npc) == "number" and npc or npcByName(name)
				local mid = id and ns.Spawns and ns.Spawns.For(id)
				parts[#parts + 1] = mid and format("%s (back ~%s)", name, mins(mid)) or name
			end
			table.sort(parts)
			local kpi = item and ns.Drops and ns.Drops.KillsPerItem(q.id, n)
			lines[#lines + 1] = { n = n, item = item, text = o.text, mobs = table.concat(parts, ", "),
				drop = kpi and format("1 in %.1f kills", kpi) or nil }
		end
	end
	return { spots = spots, places = places, lines = lines }
end

-- A mark that shows its tooltip on hover but lets clicks through to the map (a
-- client without those switches: no tooltip rather than a map that stops working).
function QM.Hoverable(f)
	if not (f.SetMouseMotionEnabled and f.SetMouseClickEnabled) then return end
	f:SetMouseMotionEnabled(true)
	f:SetMouseClickEnabled(false)
	f:SetScript("OnEnter", function(self) QM.Tip(self); QM.Focus(self) end)
	f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end; QM.Focus(nil) end)
end

-- The hovered mark forward, the others back (nil: all as they were).
local RING_REST, RING_HOVER, RING_BACK = 0.8, 1, 0.35
local FILL_HOVER, FILL_BACK = 2.2, 0.5 -- the fill's alpha, times its own
local GROW = 1.3                        -- a flight point's icon, hovered
local function paintMark(f, state)
	local col, a = f.col, f.fill
	if not col then return end
	local ring = state == "hover" and RING_HOVER or state == "back" and RING_BACK or RING_REST
	local fill = state == "hover" and math.min(0.75, a * FILL_HOVER) or state == "back" and a * FILL_BACK or a
	f.ring:SetVertexColor(col[1], col[2], col[3], ring)
	f.disc:SetVertexColor(col[1], col[2], col[3], fill)
	f.glow:SetShown(state == "hover")
	f.text:SetAlpha(state == "back" and 0.5 or 1)
end
local function paintFlight(f, state)
	local inner = f.inner
	if not inner.baseScale then return end
	inner:SetScale(inner.baseScale * (state == "hover" and GROW or 1))
	f:SetAlpha(state == "back" and 0.5 or 1)
end
function QM.Focus(hovered)
	QM.focused = hovered
	local markOf = hovered and (hovered.owner or hovered)
	for _, f in ipairs(QM.pool) do
		if f:IsShown() then paintMark(f, not hovered and "rest" or f == markOf and "hover" or "back") end
	end
	for _, f in ipairs(QM.flightPool) do
		if f:IsShown() then paintFlight(f, not hovered and "rest" or f == markOf and "hover" or "back") end
	end
end

-- The quest you navigate to, from your log.
local function chosen()
	local id = ns.Quests.selectedId
	if not id then return nil end
	for _, q in ipairs(ns.Quests.List()) do if q.id == id then return q end end
	return nil
end

local function canvasOf(wm)
	local ok, c = pcall(function() return wm.GetCanvas and wm:GetCanvas() end)
	if ok and type(c) == "table" then return c end
	return wm.ScrollContainer and wm.ScrollContainer.Child
end

-- A mark on the canvas: a disc, a ring round it, a label that keeps its size.
QM.pool = {}
local function mark(canvas, i)
	local f = QM.pool[i]
	if not f then
		f = CreateFrame("Frame", nil, canvas)
		f.disc = K.Disc(f, "ARTWORK", 10)
		f.disc:ClearAllPoints()
		f.disc:SetAllPoints()
		f.ring = f:CreateTexture(nil, "OVERLAY")
		f.ring:SetTexture(K.MEDIA .. "glyph_ring")
		f.ring:SetAllPoints()
		-- the glow round a hovered mark: the ring again, larger and faint
		f.glow = f:CreateTexture(nil, "BORDER")
		f.glow:SetTexture(K.MEDIA .. "glyph_ring")
		f.glow:SetPoint("CENTER")
		f.glow:Hide()
		f.label = CreateFrame("Frame", nil, f)
		f.label:SetSize(1, 1)
		f.label:SetPoint("CENTER")
		f.text = K.Font(f.label, 11, C.text, K.FONT, "OUTLINE")
		f.text:SetPoint("CENTER")
		QM.Hoverable(f)
		QM.pool[i] = f
	end
	if f:GetParent() ~= canvas then f:SetParent(canvas) end
	lift(f, LEVEL.quest)
	return f
end

-- The legend: a small icon in the map's top left; the box with the quest, its
-- objectives and what the marks mean opens while the mouse is on the icon. The box
-- is made of rows (each its own font string, its mark as a texture of its own):
-- inline textures in a wrapping text sat a line too low on Forever, and wrapped
-- lines lost their indent.
local LEGEND_ICON = 24
local function legend(wm)
	if QM.legend then return QM.legend end
	local host = wm.ScrollContainer or wm
	local ic = CreateFrame("Frame", nil, host)
	lift(ic, LEVEL.panel)
	ic:SetSize(LEGEND_ICON, LEGEND_ICON)
	ic:SetPoint("TOPLEFT", host, "TOPLEFT", 10, -10)
	ic.bg = K.Backdrop(ic, C.bg, LEGEND_ICON / 2)
	ic.bg:SetAllPoints()
	ic.glyph = ic:CreateTexture(nil, "OVERLAY")
	ic.glyph:SetTexture(K.MEDIA .. "glyph_menu")
	ic.glyph:SetSize(14, 14)
	ic.glyph:SetPoint("CENTER")
	ic.glyph:SetVertexColor(C.text[1], C.text[2], C.text[3], 1)
	ic:Hide()
	local f = CreateFrame("Frame", nil, host)
	lift(f, LEVEL.panel + 2)
	f:SetPoint("TOPLEFT", ic, "BOTTOMLEFT", 0, -4)
	f:SetWidth(LEGEND_W)
	f.bg = K.Backdrop(f, C.bg, 10)
	f.bg:SetAllPoints()
	f.title = K.Font(f, 12, C.text, K.FONT_BOLD or K.FONT, "")
	f.title:SetPoint("TOPLEFT", 10, -8)
	f.title:SetWidth(LEGEND_W - 20)
	f.title:SetJustifyH("LEFT")
	f.rows = {}
	f:Hide()
	if ic.SetMouseMotionEnabled then ic:SetMouseMotionEnabled(true) else ic:EnableMouse(true) end
	if ic.SetMouseClickEnabled then ic:SetMouseClickEnabled(false) end -- (clicks: the map's)
	ic:SetScript("OnEnter", function() if f.filled then f:Show() end end)
	ic:SetScript("OnLeave", function() f:Hide() end)
	f.icon = ic
	QM.legend = f
	return f
end

-- Fill the box: rows { text, indent = px, glyph = colour (a ring before it) }.
local ROW_GAP, GLYPH = 3, 11
local function fillLegend(f, title, rows)
	f.title:SetText(title or "")
	local y = -8 - 16 - 5
	local all = {}
	for i, r in ipairs(rows) do
		local row = f.rows[i]
		if not row then
			row = {}
			row.text = K.Font(f, 10.5, C.text, K.FONT, "")
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(true)
			row.glyph = f:CreateTexture(nil, "OVERLAY")
			row.glyph:SetTexture(K.MEDIA .. "glyph_ring")
			row.glyph:SetSize(GLYPH, GLYPH)
			f.rows[i] = row
		end
		local x = 10 + (r.indent or 0)
		if r.glyph then
			row.glyph:ClearAllPoints()
			row.glyph:SetPoint("TOPLEFT", x, y - 1)
			row.glyph:SetVertexColor(r.glyph[1], r.glyph[2], r.glyph[3], 1)
			row.glyph:Show()
			x = x + GLYPH + 5
		else
			row.glyph:Hide()
		end
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", x, y)
		row.text:SetWidth(LEGEND_W - 10 - x)
		row.text:SetText(r.text or "")
		row.text:Show()
		y = y - (read(row.text.GetStringHeight, row.text) or 13) - (r.gapAfter or ROW_GAP)
		all[#all + 1] = r.text or ""
	end
	for i = #rows + 1, #f.rows do f.rows[i].text:Hide(); f.rows[i].glyph:Hide() end
	f:SetHeight(-y + 8)
	f.text = table.concat(all, "\n") -- (what it says, in one string: tests, probes)
	f.filled = true
end
QM.FillLegend = fillLegend

local function hex(c) return format("%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end

-- The open world map: the map shown, its canvas and size, its zoom (nil: closed).
local function mapContext()
	local wm = rawget(_G, "WorldMapFrame")
	if not (wm and ns.P.enabled and read(wm.IsShown, wm)) then return nil end
	local map = wm.GetMapID and read(wm.GetMapID, wm)
	local canvas = canvasOf(wm)
	if not (map and canvas) then return nil end
	local scale = (wm.GetCanvasScale and read(wm.GetCanvasScale, wm)) or 1
	return { wm = wm, map = map, canvas = canvas, cw = read(canvas.GetWidth, canvas) or 0, ch = read(canvas.GetHeight, canvas) or 0,
		scale = scale > 0 and scale or 1 }
end
QM.Context = mapContext

---------------------------------------------------------------------------
-- The quest layer
---------------------------------------------------------------------------
local function hideQuest()
	for _, f in ipairs(QM.pool) do f:Hide() end
	if QM.legend then QM.legend:Hide(); QM.legend.icon:Hide(); QM.legend.filled = false end
	QM.used = 0
end

function QM.DrawQuest(cx)
	local q = cx and on() and chosen()
	if not q then hideQuest() return end
	local canvas, cw, ch = cx.canvas, cx.cw, cx.ch
	local d = QM.Data(q, cx.map)
	local i = 0
	local function put(x, y, rx, ry, col, alpha, text)
		i = i + 1
		local f = mark(canvas, i)
		f:ClearAllPoints()
		f:SetPoint("CENTER", canvas, "TOPLEFT", x * cw, -y * ch)
		f:SetSize(math.max(8, rx * 2 * cw), math.max(8, ry * 2 * ch))
		f.col, f.fill = col, alpha
		f.glow:SetSize(math.max(8, rx * 2 * cw) * 1.35, math.max(8, ry * 2 * ch) * 1.35)
		f.glow:SetVertexColor(col[1], col[2], col[3], 0.45)
		paintMark(f, "rest")
		f.text:SetText(text or "")
		f.label:SetScale(1 / cx.scale)
		f:Show()
		return f
	end
	for _, sp in ipairs(d.spots) do
		-- fainter where few kills were seen
		local a = sp.seenOnly and SPOT_ALPHA * 0.3 or SPOT_ALPHA * (0.5 + 0.5 * math.min(1, (sp.k or 0) / 10))
		local f = put(sp.x, sp.y, sp.rx, sp.ry, sp.item and ITEM_COL or KILL_COL, a, sp.mid and ("~" .. mins(sp.mid)) or sp.seenOnly and "seen" or "")
		f.info = { kind = "spot", spot = sp, quest = q, map = cx.map }
		lift(f, LEVEL.quest)
	end
	for _, pl in ipairs(d.places) do
		local f = put(pl.x, pl.y, pl.rx, pl.ry, PLACE_COL, 0.12, tostring(pl.n))
		f.info = { kind = "place", place = pl, quest = q, map = cx.map }
		lift(f, LEVEL.places) -- (small: over the spawn spots, not under them)
	end
	for j = i + 1, #QM.pool do QM.pool[j]:Hide() end
	QM.used = i
	-- the legend: the icon on the map, the box while the mouse is on it
	local lg = legend(cx.wm)
	local rows = {}
	local dim = format("|cff%s%%s|r", hex(C.dim))
	for _, l in ipairs(d.lines) do
		local col = l.item and ITEM_COL or KILL_COL
		rows[#rows + 1] = { text = format("|cff%s%d|r  %s", hex(col), l.n, l.text or ""), gapAfter = 1 }
		if l.mobs ~= "" then rows[#rows + 1] = { text = l.mobs, indent = 14, gapAfter = 1 } end
		if l.drop then rows[#rows + 1] = { text = format("|cff%s%s|r", hex(ITEM_COL), l.drop), indent = 14, gapAfter = 1 } end
		rows[#rows].gapAfter = 6
	end
	if q.complete then rows[#rows + 1] = { text = "Ready to hand in.", gapAfter = 6 } end
	if #d.spots == 0 and not q.complete then
		rows[#rows + 1] = { text = format(dim, "No spawn spots of its mobs known on this map yet: kill them here (and look at them: their tooltip says what they are for)."), gapAfter = 6 }
	end
	-- what the marks mean (hover one for more)
	if #d.spots > 0 or #d.places > 0 then
		local has = {}
		for _, sp in ipairs(d.spots) do has[sp.seenOnly and "seen" or sp.item and "item" or "kill"] = true end
		if has.kill then rows[#rows + 1] = { glyph = KILL_COL, text = format(dim, "where the mobs to kill spawn (~ back after)") } end
		if has.item then rows[#rows + 1] = { glyph = ITEM_COL, text = format(dim, "where the mobs that drop its items spawn") } end
		if has.seen then rows[#rows + 1] = { indent = GLYPH + 5, text = format(dim, "faint, \"seen\": where its mobs were seen in passing") } end
		if #d.places > 0 then rows[#rows + 1] = { glyph = PLACE_COL, text = format(dim, "1, 2...: where your counter for that objective went up") } end
		rows[#rows + 1] = { text = format(dim, "Hover a mark for more.") }
	end
	fillLegend(lg, q.title, rows)
	lg.icon:Show()
end

---------------------------------------------------------------------------
-- The tooltip of a mark on the map
---------------------------------------------------------------------------
-- yards from you to a point on the map shown (nil: you are on another map)
local function yardsTo(map, x, y)
	local here = ns.Quests.Here()
	if not (here and here.map == map) then return nil end
	return (ns.Quests.Vector(here, { map = map, x = x, y = y }))
end

function QM.Tip(f)
	local i = f.info
	if not (i and GameTooltip) then return end
	local dim, text = C.dim, C.text
	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	if i.kind == "spot" then
		local s, cell = i.spot, i.spot.cell
		local col = s.item and ITEM_COL or KILL_COL
		local names = {}
		for _, nm in pairs(cell.kinds or {}) do names[#names + 1] = nm end
		table.sort(names)
		GameTooltip:SetText(#names > 0 and table.concat(names, ", ") or (s.name or "?"), col[1], col[2], col[3])
		if cell.lo then
			local me = read(UnitLevel, "player") or 1
			local lv = cell.lo == cell.hi and tostring(cell.lo) or (cell.lo .. "-" .. cell.hi)
			local note = (ns.XP and cell.hi and ns.XP.MobXP(cell.hi, me) == 0) and "  (grey for you)" or (cell.lo > me + 3 and "  (above you)" or "")
			GameTooltip:AddLine("Level " .. lv .. note, text[1], text[2], text[3])
		end
		GameTooltip:AddLine(format("Objective %d: %s", s.n, s.text or "?"), dim[1], dim[2], dim[3], true)
		if s.seenOnly then
			GameTooltip:AddLine(format("Seen here %dx in passing: not fought here yet", s.seenOnly), text[1], text[2], text[3], true)
		elseif cell.t and #cell.t > 0 then
			local lo, hi = math.huge, 0
			for _, v in ipairs(cell.t) do lo, hi = math.min(lo, v), math.max(hi, v) end
			GameTooltip:AddLine(format("Back after about %s (%s to %s), %d respawn%s measured", mins(s.mid), mins(lo), mins(hi), cell.n, cell.n == 1 and "" or "s"),
				text[1], text[2], text[3])
		else
			GameTooltip:AddLine("Respawn not measured here yet", dim[1], dim[2], dim[3])
		end
		if not s.seenOnly then GameTooltip:AddLine(format("%d kill%s seen here", cell.k or 0, cell.k == 1 and "" or "s"), dim[1], dim[2], dim[3]) end
		if s.item and ns.Drops then
			local kpi, K, H = ns.Drops.KillsPerItem(i.quest.id, s.n)
			if kpi then
				GameTooltip:AddLine(format("Drops it about 1 in %.1f kills (%d from %d)", kpi, H, K), ITEM_COL[1], ITEM_COL[2], ITEM_COL[3])
				if s.left and s.left > 0 then
					GameTooltip:AddLine(format("%d to go: about %d more kills", s.left, math.ceil(s.left * kpi)), text[1], text[2], text[3])
				end
			else
				GameTooltip:AddLine("Drop rate not learned yet", dim[1], dim[2], dim[3])
			end
		elseif s.left and s.left > 0 then
			GameTooltip:AddLine(format("%d to go", s.left), text[1], text[2], text[3])
		end
		local yd = yardsTo(i.map, s.x, s.y)
		if yd then GameTooltip:AddLine(format("%d yd from you", math.floor(yd + 0.5)), dim[1], dim[2], dim[3]) end
	elseif i.kind == "place" then
		local p = i.place
		GameTooltip:SetText(format("Objective %d", p.n), PLACE_COL[1], PLACE_COL[2], PLACE_COL[3])
		GameTooltip:AddLine(p.text or "?", text[1], text[2], text[3], true)
		GameTooltip:AddLine(format("Your counter went up here %d time%s (the middle of them)", p.seen or 0, p.seen == 1 and "" or "s"), dim[1], dim[2], dim[3], true)
		local yd = yardsTo(i.map, p.x, p.y)
		if yd then GameTooltip:AddLine(format("%d yd from you", math.floor(yd + 0.5)), dim[1], dim[2], dim[3]) end
	elseif i.kind == "flight" then
		GameTooltip:SetText(i.name, text[1], text[2], text[3])
		if i.mine then
			GameTooltip:AddLine("Known: you can fly here", PLACE_COL[1], PLACE_COL[2], PLACE_COL[3])
		elseif i.unknown then
			GameTooltip:AddLine(ns.Travel.HINT, dim[1], dim[2], dim[3], true)
		else
			GameTooltip:AddLine("Not unlocked yet with this character: talk to its flight master", ITEM_COL[1], ITEM_COL[2], ITEM_COL[3], true)
		end
		local yd = yardsTo(i.map, i.x, i.y)
		if yd then GameTooltip:AddLine(format("%d yd from you", math.floor(yd + 0.5)), dim[1], dim[2], dim[3]) end
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The ways layer: Trails' known ground, row by row of route blocks (a run of
-- blocks side by side is one texture: a few hundred for a zone, not thousands)
---------------------------------------------------------------------------
local OUT_COL, IN_COL, DOOR_COL = { 0.44, 0.94, 0.65, 0.60 }, { 0.72, 0.58, 1, 0.70 }, { 1, 0.85, 0.30, 1 }
local WATER_COL = { 0.25, 0.80, 1, 0.65 }
local TERRAIN_COL = { 1, 0.55, 0.15, 0.70 }
local BLOCKED_COL = { 0.75, 0.10, 0.15, 0.80 }
QM.trailTex = {}
local function hideTrails()
	for _, t in ipairs(QM.trailTex) do t:Hide() end
	QM.trailUsed, QM.trailKey = 0, nil
end

function QM.DrawTrails(cx)
	local T = ns.Trails
	if not (cx and P() and P().mapTrails and T) then hideTrails() return end
	local key = cx.map .. ":" .. cx.cw .. ":" .. cx.ch
	if key == QM.trailKey then return end -- (drawn already: zooming moves the canvas, not the blocks)
	QM.trailKey = key
	local holder = QM.trailHolder
	if not holder then
		holder = CreateFrame("Frame", nil, cx.canvas)
		QM.trailHolder = holder
	end
	if holder:GetParent() ~= cx.canvas then holder:SetParent(cx.canvas) end
	holder:ClearAllPoints()
	holder:SetAllPoints(cx.canvas)
	lift(holder, LEVEL.ways)
	holder:Show()
	local G = T.N / T.B
	local i = 0
	local function rect(x, y, w, h, col)
		i = i + 1
		local t = QM.trailTex[i]
		if not t then t = holder:CreateTexture(nil, "ARTWORK"); QM.trailTex[i] = t end
		t:SetColorTexture(col[1], col[2], col[3], col[4])
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", cx.canvas, "TOPLEFT", x * cx.cw, -y * cx.ch)
		t:SetSize(math.max(1, w * cx.cw), math.max(1, h * cx.ch))
		t:Show()
	end
	-- terrain and blocked cover a block alone: ground or water walked there since is
	-- not shown under them (the route goes by them too)
	local covered = {}
	for _, l in ipairs({ T.TerrainLayer(cx.map), T.BlockedLayer(cx.map) }) do
		for k in pairs(T.Blocks(l)) do covered[k] = true end
	end
	for _, layer in ipairs({ { T.Layer(cx.map, false), OUT_COL, true }, { T.WaterLayer(cx.map), WATER_COL, true }, { T.Layer(cx.map, true), IN_COL },
		{ T.TerrainLayer(cx.map), TERRAIN_COL }, { T.BlockedLayer(cx.map), BLOCKED_COL } }) do
		local rows = {}
		for k in pairs(T.Blocks(layer[1])) do
			if not (layer[3] and covered[k]) then
			local by, bx = math.floor(k / G), k % G
			rows[by] = rows[by] or {}
			rows[by][#rows[by] + 1] = bx
			end
		end
		for by, list in pairs(rows) do
			table.sort(list)
			local start, prev = list[1], list[1]
			for j = 2, #list + 1 do
				local bx = list[j]
				if bx ~= prev + 1 then
					rect(start / G, by / G, (prev - start + 1) / G, 1 / G, layer[2])
					start = bx
				end
				prev = bx
			end
		end
	end
	-- the doors: where you went inside or out
	for k in pairs(T.Doors(cx.map)) do
		local y, x = math.floor(k / T.N), k % T.N
		rect((x - 1) / T.N, (y - 1) / T.N, 3 / T.N, 3 / T.N, DOOR_COL)
	end
	for j = i + 1, #QM.trailTex do QM.trailTex[j]:Hide() end
	QM.trailUsed = i
end

---------------------------------------------------------------------------
-- The flights layer
---------------------------------------------------------------------------
local FLIGHT_ICON = "Interface\\Minimap\\Tracking\\FlightMaster"
local FLIGHT_SIZE = 18
QM.flightPool = {}
local function hideFlights()
	for _, f in ipairs(QM.flightPool) do f:Hide() end
	QM.flightUsed = 0
end
-- A flight point of the other faction? (the client says its faction where it knows one)
local function otherFaction(node)
	local F = Enum and Enum.FlightPathFaction
	if not (F and type(node.faction) == "number") then return false end
	local mine = read(UnitFactionGroup, "player")
	if node.faction == F.Horde then return mine ~= "Horde" end
	if node.faction == F.Alliance then return mine ~= "Alliance" end
	return false
end

function QM.DrawFlights(cx)
	local TR = ns.Travel
	if not (cx and P() and P().mapFlights ~= false and TR) then hideFlights() return end
	local known = TR.Known()
	local checked = TR.Checked() -- (not seen at a flight master yet: which it has is not known)
	local i = 0
	for _, node in ipairs(TR.Nodes(cx.map)) do
		if node.x >= 0 and node.x <= 1 and node.y >= 0 and node.y <= 1 and not otherFaction(node) then
			i = i + 1
			local f = QM.flightPool[i]
			if not f then
				f = CreateFrame("Frame", nil, cx.canvas)
				f:SetSize(1, 1)
				f.inner = CreateFrame("Frame", nil, f)
				f.inner:SetSize(FLIGHT_SIZE, FLIGHT_SIZE)
				f.inner:SetPoint("CENTER")
				f.icon = f.inner:CreateTexture(nil, "OVERLAY")
				f.icon:SetTexture(FLIGHT_ICON)
				f.icon:SetAllPoints()
				QM.Hoverable(f.inner)
				f.inner.owner = f
				QM.flightPool[i] = f
			end
			if f:GetParent() ~= cx.canvas then f:SetParent(cx.canvas) end
			lift(f, LEVEL.flights)
			f:ClearAllPoints()
			f:SetPoint("CENTER", cx.canvas, "TOPLEFT", node.x * cx.cw, -node.y * cx.ch)
			f.inner.baseScale = 1 / cx.scale
			f.inner:SetScale(f.inner.baseScale)
			f:SetAlpha(1)
			local mine = known[node.name] and true or false
			f.mine = mine
			pcall(f.icon.SetDesaturated, f.icon, not mine)
			f.icon:SetAlpha(mine and 1 or 0.6)
			f.node = node.name
			f.inner.info = { kind = "flight", name = node.name, mine = mine, unknown = not checked, x = node.x, y = node.y, map = cx.map }
			f:Show()
		end
	end
	for j = i + 1, #QM.flightPool do QM.flightPool[j]:Hide() end
	QM.flightUsed = i
end

---------------------------------------------------------------------------
-- The buttons on the map: "Walked ways" (the debug view on and off) and, while it
-- is on, a brush to draw the ways by hand (Trails.EditBlock): "Walk" ground,
-- "Water" to swim (also for ways noted before 4.9.4 told swimming apart),
-- "Terrain" rough (the route goes round when that is quicker), "Blocked" no way
-- through (the route never goes there), "Erase" all of it; "Undo" takes the
-- last stroke back. Hold the left button and paint. The brush's size: the "1x1"
-- button (1, 3, 5 or 9 blocks a side; click: larger, right-click: smaller; kept in
-- quests.mapBrush); Shift: one ring wider. A frame in the tool's colour follows
-- the mouse: what the brush takes. While a brush is chosen the map does not pan
-- (its wheel still zooms); choose it again to put it down.
---------------------------------------------------------------------------
local SIZES = { 1, 3, 5, 9 }
QM.SIZES = SIZES
-- the brush's reach: blocks on each side of the one under the mouse
local function reach()
	local size = P() and P().mapBrush or 1
	return math.floor(size / 2) + ((IsShiftKeyDown and IsShiftKeyDown()) and 1 or 0)
end
local TOOL_COL = { walk = OUT_COL, water = WATER_COL, terrain = TERRAIN_COL, blocked = { 1, 0.35, 0.35 }, erase = KILL_COL }
local TOOLS = { { "walk", "Walk", 50 }, { "water", "Water", 56 }, { "terrain", "Terrain", 64 }, { "blocked", "Blocked", 66 }, { "erase", "Erase", 56 } }
QM.undo = {}
local UNDO_KEEP = 30

local function pill(host, text, w, onClick)
	local b = CreateFrame("Button", nil, host)
	b:SetSize(w, 22)
	lift(b, LEVEL.panel)
	b.bg = K.Backdrop(b, C.bg, 8)
	b.bg:SetAllPoints()
	b.text = K.Font(b, 10.5, C.text, K.FONT, "")
	b.text:SetPoint("CENTER")
	b.text:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end
local function tint(b, col)
	if col then b.text:SetTextColor(col[1], col[2], col[3]) else b.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
end

-- Where the mouse is on the map shown (0..1 each way), or nil.
function QM.Cursor(wm)
	if wm.GetNormalizedCursorPosition then
		local ok, x, y = pcall(wm.GetNormalizedCursorPosition, wm)
		if ok and type(x) == "number" and type(y) == "number" then return x, y end
	end
	local canvas = canvasOf(wm)
	if not (canvas and GetCursorPosition) then return nil end
	local cx, cy = GetCursorPosition()
	local es = read(canvas.GetEffectiveScale, canvas) or 1
	local left, top = read(canvas.GetLeft, canvas), read(canvas.GetTop, canvas)
	local w, h = read(canvas.GetWidth, canvas), read(canvas.GetHeight, canvas)
	if not (left and top and w and h and w > 0 and h > 0) then return nil end
	return (cx / es - left) / w, (top - cy / es) / h
end

-- One dab of the brush where the mouse is (each block once a stroke).
function QM.Paint(cx)
	local T = ns.Trails
	if not (cx and QM.tool and T) then return end
	local x, y = QM.Cursor(cx.wm)
	if not x or x < 0 or y < 0 or x > 1 or y > 1 then return end
	local G = T.N / T.B
	local bx, by = math.floor(x * G), math.floor(y * G)
	local r = reach()
	local stroke = QM.stroke
	for dy = -r, r do
		for dx = -r, r do
			local key = (by + dy) * G + bx + dx
			if not stroke.seen[key] then
				stroke.seen[key] = true
				for _, c in ipairs(T.EditBlock(cx.map, bx + dx, by + dy, QM.tool)) do stroke.changes[#stroke.changes + 1] = c end
			end
		end
	end
	QM.trailKey = nil
	QM.DrawTrails(cx)
end

-- The frame that shows what the brush takes, under the mouse.
function QM.Preview(cx)
	local T = ns.Trails
	local f = QM.preview
	local x, y
	if cx and QM.tool and T then x, y = QM.Cursor(cx.wm) end
	if not x or x < 0 or y < 0 or x > 1 or y > 1 then
		if f then f:Hide() end
		return
	end
	if not f then
		f = CreateFrame("Frame", nil, cx.canvas)
		f.edges = {}
		for i = 1, 4 do f.edges[i] = f:CreateTexture(nil, "OVERLAY") end
		f.edges[1]:SetPoint("TOPLEFT"); f.edges[1]:SetPoint("TOPRIGHT")
		f.edges[2]:SetPoint("BOTTOMLEFT"); f.edges[2]:SetPoint("BOTTOMRIGHT")
		f.edges[3]:SetPoint("TOPLEFT"); f.edges[3]:SetPoint("BOTTOMLEFT")
		f.edges[4]:SetPoint("TOPRIGHT"); f.edges[4]:SetPoint("BOTTOMRIGHT")
		QM.preview = f
	end
	if f:GetParent() ~= cx.canvas then f:SetParent(cx.canvas) end
	lift(f, LEVEL.flights + 5)
	local G = T.N / T.B
	local r = reach()
	local bx, by = math.floor(x * G), math.floor(y * G)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", cx.canvas, "TOPLEFT", (bx - r) / G * cx.cw, -(by - r) / G * cx.ch)
	f:SetSize((2 * r + 1) / G * cx.cw, (2 * r + 1) / G * cx.ch)
	local col = TOOL_COL[QM.tool] or C.text
	local px = 2 / cx.scale -- (2 px on screen, whatever the zoom)
	for i, t in ipairs(f.edges) do
		t:SetColorTexture(col[1], col[2], col[3], 0.95)
		if i <= 2 then t:SetHeight(px) else t:SetWidth(px) end
	end
	f.r = r
	f:Show()
end

local function brush(cx)
	local b = QM.brush
	if not b then
		local host = cx.wm.ScrollContainer or cx.wm
		b = CreateFrame("Frame", nil, host)
		b:SetAllPoints(host)
		lift(b, LEVEL.panel - 10) -- (under the buttons and the legend)
		b:SetScript("OnMouseDown", function(_, button)
			if button ~= "LeftButton" then return end
			QM.stroke = { seen = {}, changes = {} }
			QM.Paint(mapContext())
		end)
		b:SetScript("OnMouseUp", function()
			local st = QM.stroke
			QM.stroke = nil
			if st and #st.changes > 0 then
				table.insert(QM.undo, st.changes)
				while #QM.undo > UNDO_KEEP do table.remove(QM.undo, 1) end
				QM.Button(mapContext())
			end
		end)
		local acc = 0
		b:SetScript("OnUpdate", function(_, e)
			acc = acc + e
			if acc < 0.05 then return end
			acc = 0
			local cx = mapContext()
			QM.Preview(cx)
			if QM.stroke then QM.Paint(cx) end
		end)
		QM.brush = b
	end
	return b
end

function QM.Button(cx)
	local function hideAll()
		if QM.button then QM.button:Hide() end
		for _, b in pairs(QM.tools or {}) do b:Hide() end
		if QM.undoB then QM.undoB:Hide() end
		if QM.sizeB then QM.sizeB:Hide() end
		if QM.preview then QM.preview:Hide() end
		if QM.brush then QM.brush:Hide() end
	end
	if not cx then hideAll() return end
	local host = cx.wm.ScrollContainer or cx.wm
	if not QM.button then
		QM.button = pill(host, "Walked ways", 104, function()
			P().mapTrails = not P().mapTrails
			if not P().mapTrails then QM.tool = nil end
			ns.Changed("quests.mapTrails")
		end)
		QM.button:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 10, 10)
		local function choose(tool) return function()
			QM.tool = QM.tool ~= tool and tool or nil
			QM.Button(mapContext())
		end end
		QM.tools = {}
		local prev = QM.button
		for _, t in ipairs(TOOLS) do
			local b = pill(host, t[2], t[3], choose(t[1]))
			b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
			QM.tools[t[1]] = b
			prev = b
		end
		QM.toWater, QM.erase = QM.tools.water, QM.tools.erase -- (older names)
		QM.undoB = pill(host, "Undo", 56, function()
			local last = table.remove(QM.undo)
			if last and ns.Trails then ns.Trails.Undo(last) end
			QM.trailKey = nil
			QM.Draw()
		end)
		-- the brush's size: click larger, right-click smaller
		QM.sizeB = pill(host, "1x1", 44, function(_, button)
			local cur = P().mapBrush or 1
			local i = 1
			for j, v in ipairs(SIZES) do if v == cur then i = j end end
			i = button == "RightButton" and math.max(1, i - 1) or math.min(#SIZES, i + 1)
			P().mapBrush = SIZES[i]
			QM.Button(mapContext())
		end)
		QM.sizeB:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		QM.sizeB:SetPoint("LEFT", prev, "RIGHT", 6, 0)
		QM.undoB:SetPoint("LEFT", QM.sizeB, "RIGHT", 6, 0)
	end
	local ways = P() and P().mapTrails
	if not ways then QM.tool = nil end
	tint(QM.button, ways and PLACE_COL or nil)
	QM.button:Show()
	for tool, b in pairs(QM.tools) do
		b:SetShown(ways and true or false)
		tint(b, QM.tool == tool and TOOL_COL[tool] or nil)
	end
	QM.undoB:SetShown(ways and true or false)
	local size = P() and P().mapBrush or 1
	QM.sizeB.text:SetText(size .. "x" .. size)
	QM.sizeB:SetShown(ways and true or false)
	tint(QM.undoB, #QM.undo > 0 and C.text or nil)
	local b = brush(cx)
	b:SetShown(QM.tool ~= nil)
	b:EnableMouse(QM.tool ~= nil)
	if not QM.tool and QM.preview then QM.preview:Hide() end -- (the brush's update stops with it)
end

-- /sitrep mapprobe: what lies on the map's canvas (strata and level), and ours.
function QM.Probe()
	ns.Capture("mapprobe", function()
		local wm = rawget(_G, "WorldMapFrame")
		if not wm then ns.print("no world map loaded (open it once)") return end
		local canvas = canvasOf(wm)
		ns.print("map %s: strata %s level %s, shown %s; canvas level %s, clips %s; ours: %s",
			tostring(wm.GetMapID and read(wm.GetMapID, wm)), tostring(read(wm.GetFrameStrata, wm)), tostring(read(wm.GetFrameLevel, wm)),
			tostring(read(wm.IsShown, wm)), tostring(canvas and read(canvas.GetFrameLevel, canvas)),
			tostring(wm.ScrollContainer and read(wm.ScrollContainer.DoesClipChildren, wm.ScrollContainer)), above(wm))
		local ok, kids = pcall(function() return { canvas:GetChildren() } end)
		local n = 0
		for _, k in ipairs(ok and kids or {}) do
			n = n + 1
			if n > 40 then ns.print("  ... %d more", #kids - 40) break end
			local key
			for kk, v in pairs(wm) do if rawequal(v, k) and type(kk) == "string" then key = kk break end end
			local tmpl = rawget(k, "pinTemplate")
			ns.print("  %s%s: %s %s level %s, shown %s, %dx%d", tostring(key or tmpl or "?"), k == QM.trailHolder and " (SITREP ways)" or "",
				tostring(read(k.GetObjectType, k)), tostring(read(k.GetFrameStrata, k)), tostring(read(k.GetFrameLevel, k)),
				tostring(read(k.IsShown, k)), math.floor(read(k.GetWidth, k) or 0), math.floor(read(k.GetHeight, k) or 0))
		end
	end)
end

function QM.Hide()
	hideQuest()
	hideTrails()
	hideFlights()
	QM.tool, QM.stroke = nil, nil
	QM.Button(nil)
end

-- Draw it all again (the map opened, changed or zoomed, another quest chosen, new data).
function QM.Draw()
	local cx = mapContext()
	if not cx then QM.Hide() return end
	QM.DrawQuest(cx)
	QM.DrawTrails(cx)
	QM.DrawFlights(cx)
	QM.Button(cx)
end

-- The world map is Blizzard's own addon, loaded when first needed.
function QM.Hook()
	local wm = rawget(_G, "WorldMapFrame")
	if QM.hooked or type(wm) ~= "table" or not wm.HookScript then return end
	QM.hooked = true
	wm:HookScript("OnShow", function() QM.trailKey = nil; QM.Draw() end) -- (ways walked since: drawn again)
	wm:HookScript("OnHide", function() QM.Hide() end)
	for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged", "OnCanvasSizeChanged" }) do
		if type(wm[method]) == "function" then pcall(hooksecurefunc, wm, method, function() QM.Draw() end) end
	end
end

ns.On("SR_LOGIN", function() QM.Hook() end)
ns.On("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then QM.Hook() end end)
local function redraw()
	local wm = rawget(_G, "WorldMapFrame")
	if wm and read(wm.IsShown, wm) then QM.Draw() end
end
ns.On("SR_QUESTS", redraw)
ns.On("SR_RESPAWN", redraw)
ns.On("TAXIMAP_OPENED", redraw)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 7) == "quests." then QM.trailKey = nil; redraw() end
end)
