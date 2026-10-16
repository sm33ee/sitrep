-- SITREP · Console pages: the picture (overview, sensors, threat, matchups, engagement)

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local format, floor, max, min, exp, log = string.format, math.floor, math.max, math.min, math.exp, math.log
local Cfg = ns.Config
local W, NAV = Cfg.W, Cfg.NAV
local kit = Cfg.kit
local set, get, newPage = kit.set, kit.get, kit.newPage
local f2, fx, fs, fy = kit.f2, kit.fx, kit.fs, kit.fy
local sensorGrid, graph = kit.sensorGrid, kit.graph

-- 01 OVERVIEW
---------------------------------------------------------------------------
local function buildOverview()
	local p = newPage("Overview", "Observe, orient, decide, act: the loop SITREP runs five times a second.")
	p:Place(K.Toggle(p, "SITREP active", "Master switch for sensors, HUD and comms.", function() return ns.P.enabled end, function(v)
		ns.P.enabled = v
		ns.Changed("enabled")
	end), 1)
	p:Place(K.Toggle(p, "Lock HUD", "Unlock to drag the four HUD modules into place.", get("hud", "locked"), set("hud", "locked")), 2)

	-- OODA cards
	local cards = {}
	local labels = { "OBSERVE", "ORIENT", "DECIDE", "ACT" }
	local cw = (W - NAV - 60 - 3 * 10) / 4
	local row = CreateFrame("Frame", nil, p)
	row:SetHeight(96)
	for i, l in ipairs(labels) do
		local c = K.Panel(row, cw, 96, { color = C.panel, bracketLen = 7 })
		c:SetPoint("TOPLEFT", (i - 1) * (cw + 10), 0)
		local idx = K.Font(c, 10, C.faint, K.FONT, "")
		idx:SetPoint("TOPLEFT", 10, -8)
		idx:SetText(format("0%d", i))
		local t = K.Font(c, 12, C.dim, K.FONT, "")
		t:SetPoint("TOPLEFT", 10, -22)
		t:SetText(l)
		c.big = K.Font(c, 20, C.text, K.FONT, "")
		c.big:SetPoint("TOPLEFT", 10, -40)
		c.small = K.Font(c, 10.5, C.dim)
		c.small:SetPoint("TOPLEFT", 10, -66)
		c.small:SetWidth(cw - 16)
		c.small:SetJustifyH("LEFT")
		cards[i] = c
	end
	row.fixedWidth = true
	row:SetWidth(W - NAV - 60)
	p:Place(row, 1, 16)
	p.y[2] = p.y[1]

	sensorGrid(p, 1)
	local stats = K.Font(p, 12, C.text)
	stats:SetJustifyH("LEFT")
	stats:SetWidth(p.colW)
	stats:SetHeight(140)
	stats:SetJustifyV("TOP")
	p:Place(stats, 2)
	local b1 = K.Button(p, "Broadcast report", 150, 24, function() ns.Comms.Report() end, true)
	b1.fixedWidth = true
	p:Place(b1, 2, 8)
	local b2 = K.Button(p, "Preview alerts", 150, 24, function()
		ns.HUD.Banner("CONTACT  ·  ROGUE 60  ·  20-28y", ns.Data.ClassColor("ROGUE"))
		ns.HUD.Flash(1, 0.2, 0.2)
	end)
	b2.fixedWidth = true
	p:Place(b2, 2)

	function p:OnRefresh()
		local M = ns.Model
		local live, total = 0, 0
		for _, id in ipairs(ns.FEED_ORDER) do
			total = total + 1
			if ns.feeds[id] and ns.feeds[id].state == "LIVE" then live = live + 1 end
		end
		local n = #M.byThreat
		cards[1].big:SetText(format("%d", n))
		cards[1].small:SetText(format("contacts tracked\n%d of %d feeds live", live, total))
		local top = M.byThreat[1]
		cards[2].big:SetText(top and format("%.0f", top.threat) or "-")
		cards[2].small:SetText(top and format("top threat\n%s %s", ns.Data.NAME[top.class] or "", top.name or "") or "top threat\nnone")
		local pic = M.picture
		local a = ns.Data.ADVICE[pic.advice] or ns.Data.ADVICE.CLEAR
		cards[3].big:SetText(a.text)
		cards[3].big:SetTextColor(a[1], a[2], a[3])
		cards[3].small:SetText(pic.pwin and format("P(win) %.0f%%\nratio %.2f : 1", pic.pwin * 100, pic.rho) or "no hostile force\nin range")
		local cs = ns.Comms.stats
		cards[4].big:SetText(format("%d/%d", cs.sent, cs.received))
		cards[4].small:SetText("net sent / received\nreport key: see Key Bindings")
		local s, E = ns.AAR.session, ns.P.engage
		stats:SetText(format("|cff8a9492SESSION|r\nContacts sighted   %d\nWins / losses / breaks   %d / %d / %d\nDuels won / lost   %d / %d\n\n|cff8a9492MODEL|r\nk %.2f   bias %+.2f   fights %d\nBrier score   %s",
			s.contacts, s.wins, s.losses, s.breaks, s.duelWins, s.duelLosses, E.k, E.bias, E.n or 0, (E.n or 0) > 0 and format("%.3f", E.brier) or "-"))
	end
	p.live = true
	return p
end

---------------------------------------------------------------------------
-- 02 SENSORS
---------------------------------------------------------------------------
local function buildSensors()
	local p = newPage("Sensors", "What the client lets us see, and how hard we look.")
	p:Place(K.Slider(p, "Scan rate", 1, 10, 1, get("sensors", "rate"), set("sensors", "rate"), function(v) return v .. " Hz" end), 1)
	p:Place(K.Slider(p, "Contact memory", 10, 120, 5, get("sensors", "memory"), set("sensors", "memory"), fs), 1)
	p:Place(K.Slider(p, "Nameplate distance", 20, 60, 1, get("sensors", "plateRange"), set("sensors", "plateRange"), fy), 1)
	p:Place(K.Toggle(p, "Spellbook range checks", "Every harmful spell with a range becomes a range gate.", get("sensors", "useSpellRange"), set("sensors", "useSpellRange")), 2)
	p:Place(K.Toggle(p, "Interact-distance checks", "10 and 28 yard gates that work for any class.", get("sensors", "useInteract"), set("sensors", "useInteract")), 2)
	p:Place(K.Toggle(p, "Item range checks", "Distance to enemies in steps of a few yards, out of combat.", get("sensors", "useItemRange"), set("sensors", "useItemRange")), 2)
	p:Place(K.Toggle(p, "Sight through group targets", "Contacts your group targets join the picture.", get("sensors", "groupTargets"), set("sensors", "groupTargets")), 2)
	p:Place(K.Toggle(p, "Track hostile NPCs", "Guards and elites count as contacts.", get("sensors", "npcs"), set("sensors", "npcs")), 2)

	-- Range ladder: every armed gate on a 0-45 yd ruler.
	p.y[1] = max(p.y[1], p.y[2]) + 6
	local lad = CreateFrame("Frame", nil, p)
	lad.fixedWidth = true
	local LW = W - NAV - 60
	lad:SetSize(LW, 58)
	local lt = K.Font(lad, 10, C.dim, K.FONT, "")
	lt:SetPoint("TOPLEFT")
	lt:SetText("RANGE LADDER")
	local rule = K.Tex(lad, "ARTWORK", C.line2)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 0, -40); rule:SetPoint("TOPRIGHT", 0, -40)
	for yd = 0, 45, 5 do
		local t = K.Tex(lad, "ARTWORK", C.line2)
		t:SetSize(1, yd % 10 == 0 and 6 or 3)
		t:SetPoint("TOPLEFT", LW * yd / 45, -40)
		if yd % 10 == 0 then
			local n = K.Font(lad, 9, C.faint, K.FONT, "")
			n:SetPoint("TOP", t, "BOTTOM", 0, -2)
			n:SetText(yd)
		end
	end
	lad.marks = {}
	function lad:Refresh()
		for _, m in ipairs(self.marks) do m.t:Hide(); m.l:Hide() end
		for i, c in ipairs(ns.Sensors.checks or {}) do
			local m = self.marks[i]
			if not m then
				m = { t = K.Tex(self, "OVERLAY"), l = K.Font(self, 9, C.text, K.FONT, "") }
				K.Paint(function(r, g, b) m.t:SetVertexColor(r, g, b, 1) end)
				self.marks[i] = m
			end
			m.t:SetSize(2, 12)
			m.t:ClearAllPoints()
			m.t:SetPoint("BOTTOMLEFT", self, "TOPLEFT", LW * min(c.max, 45) / 45 - 1, -40)
			m.l:ClearAllPoints()
			m.l:SetPoint("BOTTOM", m.t, "TOP", 0, 2 + ((i % 2 == 0) and 10 or 0))
			m.l:SetText(format("%s %.0f", (c.name or ""):sub(1, 12), c.max))
			m.t:Show(); m.l:Show()
		end
	end
	p:Place(lad, 1, 14)
	local stat = K.Font(p, 11, C.dim, K.FONT, "")
	function stat:Refresh()
		local st = ns.Sensors.stats
		self:SetText(format("LAST TICK  %d hostile plates  ·  %d range queries  ·  %d answered", st.plates, st.rangeAsked, st.rangeAnswered))
	end
	p:Place(stat, 1)
	p.live = true
	return p
end

---------------------------------------------------------------------------
-- 03 THREAT MODEL
---------------------------------------------------------------------------
local function buildThreat()
	local p = newPage("Threat Model", "Threat = power × matchup × level × proximity × behaviour × freshness.")
	p:Place(K.Slider(p, "Targeting me", 1, 3, 0.05, get("threat", "targetingMe"), set("threat", "targetingMe"), fx), 1)
	p:Place(K.Slider(p, "Casting", 1, 2, 0.05, get("threat", "casting"), set("threat", "casting"), fx), 1)
	p:Place(K.Slider(p, "In combat", 1, 2, 0.05, get("threat", "inCombat"), set("threat", "inCombat"), fx), 1)
	p:Place(K.Slider(p, "Closing faster than 3 y/s", 1, 2, 0.05, get("threat", "closing"), set("threat", "closing"), fx), 1)
	p:Place(K.Slider(p, "Inside its reach", 1, 2, 0.05, get("threat", "inReach"), set("threat", "inReach"), fx), 1)
	p:Place(K.Slider(p, "Per level of difference", 1, 1.3, 0.01, get("threat", "levelBase"), set("threat", "levelBase"), fx), 1)
	p:Place(K.Slider(p, "HVT designation threshold", 0, 200, 5, get("threat", "hvtMin"), set("threat", "hvtMin")), 1)

	p:Place(K.Slider(p, "Proximity falloff", 10, 60, 1, get("threat", "falloff"), function(v)
		ns.P.threat.falloff = v
		ns.Changed("threat.falloff")
		p:OnRefresh()
	end, fy), 2)
	local g = graph(p, p.colW, 70, 30)
	p:Place(g, 2, 4)
	local gl = K.Font(p, 9, C.faint, K.FONT, "")
	gl:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -2)
	gl:SetText("weight vs distance, 0-60 yd")
	p.y[2] = p.y[2] + 12

	-- HVT worth per class: compact steppers.
	local hv = CreateFrame("Frame", nil, p)
	hv:SetHeight(5 * 24)
	hv.cells = {}
	for i, class in ipairs(ns.Data.CLASSES) do
		local col, rowi = (i - 1) % 2, floor((i - 1) / 2)
		local cell = CreateFrame("Frame", nil, hv)
		cell:SetSize(p.colW / 2 - 6, 22)
		cell:SetPoint("TOPLEFT", col * (p.colW / 2 + 2), -rowi * 24)
		cell.bg = K.Tex(cell, "BACKGROUND", C.raised)
		cell.bg:SetAllPoints()
		local n = K.Font(cell, 11, C.text)
		n:SetPoint("LEFT", 6, 0)
		n:SetText(ns.Data.NAME[class])
		n:SetTextColor(ns.Data.ClassColor(class))
		cell.v = K.Font(cell, 11, C.text, K.FONT, "")
		cell.v:SetPoint("RIGHT", -34, 0)
		local minus = K.Button(cell, "-", 14, 16, function() ns.P.threat.hvt[class] = max(0.5, ns.P.threat.hvt[class] - 0.05); ns.Changed("threat.hvt"); hv:Refresh() end)
		minus:SetPoint("RIGHT", -18, 0)
		local plus = K.Button(cell, "+", 14, 16, function() ns.P.threat.hvt[class] = min(2, ns.P.threat.hvt[class] + 0.05); ns.Changed("threat.hvt"); hv:Refresh() end)
		plus:SetPoint("RIGHT", -2, 0)
		hv.cells[class] = cell
	end
	function hv:Refresh()
		for class, cell in pairs(self.cells) do cell.v:SetText(format("%.2f", ns.P.threat.hvt[class])) end
	end
	local ht = K.Font(p, 10, C.dim, K.FONT, "")
	p.y[2] = p.y[2] + 4
	ht:SetText("HIGH-VALUE-TARGET WORTH")
	p:Place(ht, 2, 6)
	p:Place(hv, 2)

	function p:OnRefresh()
		local f = ns.P.threat.falloff
		g:Plot(function(t) return ns.Model.Proximity(t * 60, f) end)
	end
	return p
end

---------------------------------------------------------------------------
-- 04 MATCHUP MATRIX
---------------------------------------------------------------------------
local function heat(v)
	-- 0.7 cool (green) → 1.0 neutral → 1.4 hot (red)
	if v < 1 then
		local t = max(0, min(1, (1 - v) / 0.3))
		return 0.16 - 0.06 * t, 0.18 + 0.30 * t, 0.19 + 0.05 * t
	end
	local t = max(0, min(1, (v - 1) / 0.4))
	return 0.16 + 0.60 * t, 0.18 - 0.06 * t, 0.19 - 0.08 * t
end

local function buildMatrix()
	local p = newPage("Matchup Matrix", "How dangerous each class is to each defender. Click +0.05, right-click -0.05, wheel to nudge.")
	local classes = ns.Data.CLASSES
	local CELL, LBL = 38, 64
	local m = CreateFrame("Frame", nil, p)
	m.fixedWidth = true
	m:SetSize(LBL + CELL * 9 + 4, 20 + CELL * 9 + 4)
	m.cells, m.rowLbl, m.colLbl = {}, {}, {}
	local hl = K.Tex(m, "ARTWORK", { 1, 1, 1, 0.06 }, 3)
	local vl = K.Tex(m, "ARTWORK", { 1, 1, 1, 0.06 }, 3)
	hl:Hide(); vl:Hide()
	local top = 20
	local themLbl = K.Font(m, 9, C.faint, K.FONT, "")
	themLbl:SetPoint("TOPLEFT", LBL, 0)
	themLbl:SetText("ATTACKER  >")
	local youLbl = K.Font(m, 9, C.faint, K.FONT, "")
	youLbl:SetPoint("TOPLEFT", 0, 0)
	youLbl:SetText("DEFENDER  v")
	for j, them in ipairs(classes) do
		local l = K.Font(m, 10, C.text, K.FONT, "")
		l:SetPoint("BOTTOM", m, "TOPLEFT", LBL + (j - 0.5) * CELL, -top + 2)
		l:SetText(ns.Data.SHORT[them])
		l:SetTextColor(ns.Data.ClassColor(them))
		m.colLbl[j] = l
	end
	for i, me in ipairs(classes) do
		local l = K.Font(m, 11, C.text)
		l:SetPoint("RIGHT", m, "TOPLEFT", LBL - 8, -top - (i - 0.5) * CELL)
		l:SetText(ns.Data.NAME[me])
		l:SetTextColor(ns.Data.ClassColor(me))
		m.rowLbl[i] = l
		for j, them in ipairs(classes) do
			local b = CreateFrame("Button", nil, m)
			b:SetSize(CELL - 2, CELL - 2)
			b:SetPoint("TOPLEFT", LBL + (j - 1) * CELL, -top - (i - 1) * CELL)
			b.bg = K.Tex(b, "BACKGROUND")
			b.bg:SetAllPoints()
			b.v = K.Font(b, 11, C.text, K.FONT, "")
			b.v:SetPoint("CENTER")
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b:EnableMouseWheel(true)
			local function bump(d)
				local row = ns.P.threat.matrix[me]
				row[them] = max(0.5, min(2, floor((row[them] + d) * 100 + 0.5) / 100))
				ns.Changed("threat.matrix")
				m:Refresh()
			end
			b:SetScript("OnClick", function(_, button) bump(button == "RightButton" and -0.05 or 0.05) end)
			b:SetScript("OnMouseWheel", function(_, d) bump(d * 0.05) end)
			b:SetScript("OnEnter", function(self)
				hl:ClearAllPoints()
				hl:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -top - (i - 1) * CELL)
				hl:SetSize(LBL + CELL * 9, CELL - 2)
				vl:ClearAllPoints()
				vl:SetPoint("TOPLEFT", m, "TOPLEFT", LBL + (j - 1) * CELL, 0)
				vl:SetSize(CELL - 2, top + CELL * 9)
				hl:Show(); vl:Show()
				if GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(format("%s vs %s", ns.Data.NAME[me], ns.Data.NAME[them]), 1, 1, 1)
					local v = ns.P.threat.matrix[me][them]
					GameTooltip:AddLine(format("A %s is %.0f%% %s dangerous to a %s than an average opponent.", ns.Data.NAME[them],
						math.abs(v - 1) * 100, v >= 1 and "more" or "less", ns.Data.NAME[me]), 0.75, 0.8, 0.78, true)
					GameTooltip:Show()
				end
			end)
			b:SetScript("OnLeave", function() hl:Hide(); vl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
			m.cells[#m.cells + 1] = { b = b, me = me, them = them, i = i }
		end
	end
	-- Accent frame around your own row.
	local mine = CreateFrame("Frame", nil, m)
	mine:SetSize(CELL * 9 + 2, CELL + 2)
	K.Border(mine)
	K.Paint(function(r, g, b) mine.border:SetColor(r, g, b, 1) end)
	function m:Refresh()
		local M = ns.P.threat.matrix
		local myClass = ns.Sensors.self.class
		for _, c in ipairs(self.cells) do
			local v = M[c.me][c.them]
			c.b.bg:SetVertexColor(heat(v))
			c.b.v:SetText(format("%.2f", v))
			if v > 1.02 then c.b.v:SetTextColor(1, 0.85, 0.8) elseif v < 0.98 then c.b.v:SetTextColor(0.8, 1, 0.85) else c.b.v:SetTextColor(unpack(C.dim)) end
		end
		mine:Hide()
		for i, cl in ipairs(classes) do
			if cl == myClass then
				mine:ClearAllPoints()
				mine:SetPoint("TOPLEFT", m, "TOPLEFT", LBL - 2, -top - (i - 1) * CELL + 1)
				mine:Show()
			end
		end
	end
	p:Place(m, 1)

	-- Legend + reset, to the right of the grid.
	local side = CreateFrame("Frame", nil, p)
	side:SetSize(120, 200)
	side:SetPoint("TOPLEFT", p, "TOPLEFT", LBL + CELL * 9 + 24, -72)
	local lg = K.Font(side, 10, C.dim, K.FONT, "")
	lg:SetPoint("TOPLEFT")
	lg:SetText("LEGEND")
	for i = 0, 13 do
		local v = 0.7 + i * 0.05
		local t = K.Tex(side, "ARTWORK")
		t:SetSize(8, 8)
		t:SetPoint("TOPLEFT", i * 8, -16)
		t:SetVertexColor(heat(v))
	end
	local l1 = K.Font(side, 9, C.faint, K.FONT, "")
	l1:SetPoint("TOPLEFT", 0, -28)
	l1:SetText("0.70 safe     1.35 lethal")
	local you = K.Font(side, 10.5, C.dim)
	you:SetPoint("TOPLEFT", 0, -50)
	you:SetWidth(120)
	you:SetJustifyH("LEFT")
	you:SetText("Your row is framed. Only your row changes your own threat board; the whole matrix feeds the group engagement maths.")
	local reset = K.Button(side, "Reset matrix", 130, 22, function()
		ns.P.threat.matrix = ns.copy(ns.Data.MATRIX)
		ns.Changed("threat.matrix")
		m:Refresh()
	end)
	reset:SetPoint("TOPLEFT", 0, -150)
	reset:SetWidth(120)
	return p
end

---------------------------------------------------------------------------
-- 05 ENGAGEMENT
---------------------------------------------------------------------------
local function buildEngagement()
	local p = newPage("Engagement Calculus", "Lanchester square law: strength = N × Σ quality. P(win) = σ(k·ln ρ + b).")
	local function redraw() p:OnRefresh() end
	local function setR(key) return function(v) ns.P.engage[key] = v; ns.Changed("engage." .. key); redraw() end end
	p:Place(K.Slider(p, "ENGAGE at ratio ≥", 1, 3, 0.05, get("engage", "engageAt"), setR("engageAt"), f2), 1)
	p:Place(K.Slider(p, "CONTEST at ratio ≥", 0.5, 1.5, 0.05, get("engage", "contestAt"), setR("contestAt"), f2), 1)
	p:Place(K.Slider(p, "HOLD at ratio ≥", 0.2, 1, 0.05, get("engage", "holdAt"), setR("holdAt"), f2), 1)
	p:Place(K.Slider(p, "Engagement radius", 20, 80, 5, get("engage", "radius"), set("engage", "radius"), fy), 1)

	p:Place(K.Toggle(p, "Self-calibrate from fights", "Wins and losses nudge k and b by logistic regression.", get("engage", "autoCal"), set("engage", "autoCal")), 2)
	p:Place(K.Slider(p, "Learning rate", 0.01, 0.2, 0.01, get("engage", "lr"), set("engage", "lr"), f2), 2)
	local g = graph(p, p.colW, 110, 48)
	p:Place(g, 2, 2)
	-- band shading behind the curve
	g.bands = {}
	for i = 1, 4 do
		local t = K.Tex(g, "BACKGROUND", nil, 1)
		t:SetPoint("TOP"); t:SetPoint("BOTTOM")
		g.bands[i] = t
	end
	local axis = K.Font(p, 9, C.faint, K.FONT, "")
	axis:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -2)
	axis:SetText("ratio 0.25          1:1          4.0")
	p.y[2] = p.y[2] + 14
	local readout = K.Font(p, 12, C.text, K.FONT, "")
	readout:SetJustifyH("LEFT")
	readout:SetHeight(52)
	p:Place(readout, 2, 4)
	local reset = K.Button(p, "Reset calibration", 150, 22, function()
		local E, D = ns.P.engage, ns.Defaults().engage
		E.k, E.bias, E.n, E.brier = D.k, D.bias, 0, 0
		ns.Changed("engage.k")
		redraw()
	end)
	reset.fixedWidth = true
	p:Place(reset, 2)
	local resetDuel = K.Button(p, "Reset duel curve", 130, 22, function()
		local Dd, D = ns.P.duel, ns.Defaults().duel
		Dd.k, Dd.bias, Dd.n, Dd.brier = D.k, D.bias, 0, 0
		redraw()
	end)
	resetDuel:SetPoint("LEFT", reset, "RIGHT", 8, 0)

	function p:OnRefresh()
		local E = ns.P.engage
		-- x axis: ln ρ from ln 0.25 to ln 4
		local lo, hi = log(0.25), log(4)
		local function xOf(r) return (log(r) - lo) / (hi - lo) end
		g:Plot(function(t)
			local x = lo + t * (hi - lo)
			return 1 / (1 + exp(-(E.k * x + E.bias)))
		end)
		local edges = { 0, xOf(E.holdAt), xOf(E.contestAt), xOf(E.engageAt), 1 }
		local cols = { ns.Data.ADVICE.BREAK, ns.Data.ADVICE.HOLD, ns.Data.ADVICE.CONTEST, ns.Data.ADVICE.ENGAGE }
		local gw = g:GetWidth()
		for i = 1, 4 do
			local a, b = max(0, min(1, edges[i])), max(0, min(1, edges[i + 1]))
			local t = g.bands[i]
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", g, "TOPLEFT", gw * a, 0)
			t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", gw * a, 0)
			t:SetWidth(max(1, gw * (b - a)))
			t:SetVertexColor(cols[i][1], cols[i][2], cols[i][3], 0.10)
		end
		local Dd = ns.P.duel
		readout:SetText(format("GROUP  k %.2f   b %+.2f   fights %d   Brier %s\nDUEL   k %.2f   b %+.2f   duels %d   Brier %s\n|cff8a9492Brier 0.25 = coin flip. The curve shows the group model.|r",
			E.k, E.bias, E.n or 0, (E.n or 0) > 0 and format("%.3f", E.brier) or "-",
			Dd.k, Dd.bias, Dd.n or 0, (Dd.n or 0) > 0 and format("%.3f", Dd.brier) or "-"))
	end
	return p
end

---------------------------------------------------------------------------

Cfg.AddPage(10, "overview", "Overview", buildOverview)
Cfg.AddPage(20, "sensors", "Sensors", buildSensors)
Cfg.AddPage(30, "threat", "Threat Model", buildThreat)
Cfg.AddPage(40, "matrix", "Matchup Matrix", buildMatrix)
Cfg.AddPage(50, "engage", "Engagement", buildEngagement)
