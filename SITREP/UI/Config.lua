-- SITREP · Console
-- The configuration window: the frame, the page navigation, and the kit every
-- page is built with. Each page is built the first time it is opened. Every
-- control writes straight into the profile and calls ns.Changed(key) so the
-- running modules pick it up without a reload.
--
-- The pages live in their own files and register themselves with Cfg.AddPage:
--   ConfigPicture.lua    Overview, Sensors, Threat Model, Matchup Matrix, Engagement
--   ConfigSettings.lua   Pressure, Comms, Alerts, Display, Layout, Unit Frames, Nameplates
--   ConfigLog.lua        Intel Log
--   ConfigTrackers.lua   Trackers
-- A page: local p = newPage(title, subtitle); p:Place(widget, column, gap) stacks
-- widgets in two columns. A page taller than the window scrolls (mouse wheel; a
-- thin thumb on the right shows where you are).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local format, floor, max, min = string.format, math.floor, math.max, math.min

local Cfg = {}
ns.Config = Cfg

local W, H, NAV = 800, 560, 190
Cfg.W, Cfg.H, Cfg.NAV = W, H, NAV
Cfg.GLASS = 0.80 -- the console's opacity
Cfg.NAV_STEP = 27 -- one nav button per page: 17 pages fill the nav (470 px)
local win, pages, navButtons, current = nil, {}, {}, nil

local function set(section, key)
	return function(v)
		ns.P[section][key] = v
		ns.Changed(section .. "." .. key)
	end
end
local function get(section, key) return function() return ns.P[section][key] end end
local function f2(v) return format("%.2f", v) end
local function fx(v) return format("x%.2f", v) end
local function fs(v) return format("%.0fs", v) end
local function fy(v) return format("%.0fy", v) end
local function fp(v) return format("%.0f%%", v * 100) end

---------------------------------------------------------------------------
-- Page scaffolding: two columns that stack widgets top-down.
---------------------------------------------------------------------------
local SCROLL_STEP = 48

-- The page scrolls inside the content area: the scroll frame is what shows and
-- hides, the page (its scroll child) is as tall as what is placed on it.
local function scroller(p)
	local sf = CreateFrame("ScrollFrame", nil, win.content)
	sf:SetAllPoints()
	p:SetParent(sf)
	p:SetWidth(W - NAV - 22 - 30)
	p:SetHeight(1)
	sf:SetScrollChild(p)
	local thumb = K.Tex(win.content, "OVERLAY", C.line2)
	thumb:SetWidth(3)
	thumb:Hide()
	local function range()
		local h, view = p:GetHeight() or 0, sf:GetHeight() or 0
		return math.max(0, h - view), h, view
	end
	function p:ScrollTo(y)
		local most, h, view = range()
		y = max(0, min(most, y or 0))
		sf:SetVerticalScroll(y)
		thumb:SetShown(most > 0 and sf:IsShown())
		if most > 0 then
			local th = max(24, view * view / h)
			thumb:SetHeight(th)
			thumb:ClearAllPoints()
			thumb:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 16, -(view - th) * y / most)
		end
	end
	function p:Scroll() return sf:GetVerticalScroll() or 0 end
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) p:ScrollTo(p:Scroll() - d * SCROLL_STEP) end)
	sf:SetScript("OnShow", function() p:ScrollTo(p:Scroll()) end)
	sf:SetScript("OnHide", function() thumb:Hide() end)
	sf:Hide()
	-- the page shows and hides with its scroll frame
	function p:SetShown(v) sf:SetShown(v) end
	function p:Show() sf:Show() end
	function p:Hide() sf:Hide() end
	function p:IsShown() return sf:IsShown() end
	p.scroller = sf
end

local function newPage(title, sub)
	local p = CreateFrame("Frame", nil, win.content)
	scroller(p)
	p.widgets = {}
	p.y = { 0, 0 }
	local hdr = K.Header(p, title, sub)
	hdr:SetPoint("TOPLEFT", 0, 0)
	hdr:SetPoint("TOPRIGHT", 0, 0)
	p.y[1], p.y[2] = 52, 52
	p.colW = (W - NAV - 60 - 30) / 2
	function p:Place(w, col, gap)
		col = col or 1
		w:SetPoint("TOPLEFT", self, "TOPLEFT", (col - 1) * (self.colW + 30), -self.y[col])
		if w.SetWidth and not w.fixedWidth then w:SetWidth(self.colW) end
		if w.Relayout then w:Relayout() end
		self.y[col] = self.y[col] + w:GetHeight() + (gap or 10)
		self:Grow()
		if w.Refresh then self.widgets[#self.widgets + 1] = w end
		return w
	end
	-- the page as tall as its taller column (after Place, or after moving y by hand)
	function p:Grow()
		self:SetHeight(max(self.y[1], self.y[2]))
	end
	function p:Refresh()
		for _, w in ipairs(self.widgets) do if w.Refresh then w:Refresh() end end
		if self.OnRefresh then self:OnRefresh() end
	end
	return p
end

local function statePill(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(62, 16)
	f.bg = K.Tex(f, "BACKGROUND", C.raised)
	f.bg:SetAllPoints()
	K.Border(f, C.line2)
	f.text = K.Font(f, 10, C.text, K.FONT, "")
	f.text:SetPoint("CENTER")
	local COL = {
		LIVE = { K.Accent() }, PARTIAL = { 1, 0.8, 0.3 }, SECRET = { 1, 0.55, 0.2 }, LOCKED = { 1, 0.55, 0.2 },
		DARK = { 0.9, 0.3, 0.3 }, IDLE = { 0.5, 0.55, 0.55 },
	}
	function f:SetState(s)
		local c = COL[s] or COL.IDLE
		if s == "LIVE" then c = { K.Accent() } end
		self.text:SetText(s or "?")
		self.text:SetTextColor(c[1], c[2], c[3])
		self.border:SetColor(c[1], c[2], c[3], 0.6)
		self.bg:SetVertexColor(c[1] * 0.15, c[2] * 0.15, c[3] * 0.15, 1)
	end
	return f
end

local function sensorGrid(p, col)
	local box = CreateFrame("Frame", nil, p)
	box:SetHeight(#ns.FEED_ORDER * 22 + 4)
	box.rows = {}
	for i, id in ipairs(ns.FEED_ORDER) do
		local pill = statePill(box)
		pill:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
		local label = K.Font(box, 12, C.text)
		label:SetPoint("LEFT", pill, "RIGHT", 10, 0)
		label:SetText(ns.FEED_LABEL[id])
		local note = K.Font(box, 10.5, C.dim)
		note:SetPoint("LEFT", pill, "RIGHT", 130, 0)
		box.rows[id] = { pill = pill, note = note }
	end
	function box:Refresh()
		for id, r in pairs(self.rows) do
			local fd = ns.feeds[id]
			r.pill:SetState(fd and fd.state or "IDLE")
			r.note:SetText(fd and fd.note or "")
		end
	end
	return p:Place(box, col)
end

---------------------------------------------------------------------------
-- Line graph helper (drawn with Line objects).
---------------------------------------------------------------------------
local function graph(parent, w, h, segments)
	local g = CreateFrame("Frame", nil, parent)
	g:SetSize(w, h)
	g.fixedWidth = true
	g.bg = K.Tex(g, "BACKGROUND", { 0.02, 0.03, 0.03, 0.9 })
	g.bg:SetAllPoints()
	K.Border(g, C.line)
	for i = 1, 3 do
		local t = K.Tex(g, "BORDER", C.line)
		t:SetHeight(1)
		t:SetPoint("LEFT"); t:SetPoint("RIGHT")
		t:SetPoint("TOP", 0, -h * i / 4)
	end
	g.lines = {}
	for i = 1, segments do
		local l = g:CreateLine(nil, "ARTWORK")
		l:SetThickness(2)
		g.lines[i] = l
	end
	K.Paint(function(r, gg, b) for _, l in ipairs(g.lines) do l:SetColorTexture(r, gg, b, 0.95) end end)
	-- fn(t) → 0..1 for t in 0..1
	function g:Plot(fn)
		local px, py
		for i = 0, segments do
			local x, y = w * i / segments, h * max(0, min(1, fn(i / segments)))
			if i > 0 then
				local l = self.lines[i]
				l:SetStartPoint("BOTTOMLEFT", self, px, py)
				l:SetEndPoint("BOTTOMLEFT", self, x, y)
			end
			px, py = x, y
		end
	end
	return g
end

---------------------------------------------------------------------------

-- What the page files build with.
Cfg.kit = {
	set = set, get = get, newPage = newPage,
	f2 = f2, fx = fx, fs = fs, fy = fy, fp = fp,
	statePill = statePill, sensorGrid = sensorGrid, graph = graph,
}

-- Pages register themselves: Cfg.AddPage(order, id, label, build). The order
-- sets their place in the navigation (and their number).
local SECTIONS = {}
function Cfg.AddPage(order, id, label, buildFn)
	SECTIONS[#SECTIONS + 1] = { id, label, buildFn, order = order }
	table.sort(SECTIONS, function(a, b) return a.order < b.order end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function openPage(id)
	for _, s in ipairs(SECTIONS) do
		local page = pages[s[1]]
		if s[1] == id and not page then
			page = s[3]()
			pages[id] = page
		end
		if page then page:SetShown(s[1] == id) end
		local b = navButtons[s[1]]
		b.active = s[1] == id
		b:Paint()
	end
	current = id
	pages[id]:Refresh()
end

local function build()
	-- (a little see-through: the world shows faintly behind the console)
	win = K.Panel(UIParent, W, H, { name = "SITREP_Console", color = { 0.028, 0.036, 0.04, Cfg.GLASS }, bracketLen = 16, bracketThick = 2, radius = 12 })
	win:SetPoint("CENTER")
	win:SetScale(ns.P.hud.consoleScale or 1)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:Hide()
	win:SetScript("OnShow", function() ns.Fire("SR_CONSOLE", true) end)
	win:SetScript("OnHide", function() ns.Fire("SR_CONSOLE", false) end)
	if UISpecialFrames then table.insert(UISpecialFrames, "SITREP_Console") end
	K.Scanlines(win, floor(H / 3), 0.10)

	-- Title bar
	local logo = K.Font(win, 22, C.text, K.FONT, "")
	logo:SetPoint("TOPLEFT", 20, -14)
	logo:SetText("SITREP")
	K.Paint(function(r, g, b) logo:SetTextColor(r, g, b) end)
	local tag = K.Font(win, 11, C.dim, K.FONT, "")
	tag:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 3)
	tag:SetText("//  TACTICAL AWARENESS CONSOLE   v" .. ns.VERSION)
	local close = K.Button(win, "X", 24, 22, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", -12, -12)
	local rule = K.Tex(win, "ARTWORK", C.line)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 12, -48); rule:SetPoint("TOPRIGHT", -12, -48)

	-- Nav
	local nav = CreateFrame("Frame", nil, win)
	nav:SetPoint("TOPLEFT", 12, -56)
	nav:SetPoint("BOTTOMLEFT", 12, 34)
	nav:SetWidth(NAV - 12)
	nav.bg = K.Tex(nav, "BACKGROUND", { 0, 0, 0, 0.25 })
	nav.bg:SetAllPoints()
	for i, s in ipairs(SECTIONS) do
		local b = CreateFrame("Button", nil, nav)
		b:SetHeight(Cfg.NAV_STEP - 2)
		b:SetPoint("TOPLEFT", 0, -6 - (i - 1) * Cfg.NAV_STEP)
		b:SetPoint("TOPRIGHT", 0, -6 - (i - 1) * Cfg.NAV_STEP)
		b.hl = K.Tex(b, "BACKGROUND", C.hover)
		b.hl:SetAllPoints()
		b.bar = K.Tex(b, "ARTWORK")
		b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
		b.num = K.Font(b, 10, C.faint, K.FONT, "")
		b.num:SetPoint("LEFT", 14, 0)
		b.num:SetText(format("%02d", i))
		b.text = K.Font(b, 13, C.text)
		b.text:SetPoint("LEFT", 40, 0)
		b.text:SetText(s[2])
		function b:Paint()
			local r, g, bl = K.Accent()
			self.hl:SetShown(self.active or self.hover)
			self.hl:SetAlpha(self.active and 0.9 or 0.5)
			self.bar:SetShown(self.active)
			self.bar:SetVertexColor(r, g, bl, 1)
			if self.active then self.text:SetTextColor(r, g, bl); self.num:SetTextColor(r, g, bl, 0.7)
			else self.text:SetTextColor(unpack(C.text)); self.num:SetTextColor(unpack(C.faint)) end
		end
		b:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
		b:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
		b:SetScript("OnClick", function() openPage(s[1]) end)
		navButtons[s[1]] = b
		K.Paint(function() b:Paint() end)
	end

	-- Content
	win.content = CreateFrame("Frame", nil, win)
	win.content:SetPoint("TOPLEFT", NAV + 22, -64)
	win.content:SetPoint("BOTTOMRIGHT", -30, 40)

	-- Footer: live status line
	local foot = K.Tex(win, "ARTWORK", C.line)
	foot:SetHeight(1)
	foot:SetPoint("BOTTOMLEFT", 12, 28); foot:SetPoint("BOTTOMRIGHT", -12, 28)
	win.status = K.Font(win, 10, C.dim, K.FONT, "")
	win.status:SetPoint("BOTTOMLEFT", 20, 10)
	win.hint = K.Font(win, 10, C.faint, K.FONT, "")
	win.hint:SetPoint("BOTTOMRIGHT", -20, 10)
	win.hint:SetText("/sitrep  ·  ESC closes  ·  changes apply live")
	win.dot = K.Disc(win, "OVERLAY", 7)
	win.dot:SetPoint("RIGHT", win.status, "LEFT", -5, 0)

	local acc = 0
	win:SetScript("OnUpdate", ns.Timed("console (win)", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		local pic, n = ns.Model.picture, #ns.Model.byThreat
		local live = 0
		for _, fd in pairs(ns.feeds) do if fd.state == "LIVE" then live = live + 1 end end
		win.status:SetText(format("%s   ·   %d CONTACTS   ·   %s   ·   %d FEEDS LIVE",
			ns.P.enabled and "ONLINE" or "STANDBY", n, (ns.Data.ADVICE[pic.advice] or ns.Data.ADVICE.CLEAR).text, live))
		local r, g, b = K.Accent()
		if not ns.P.enabled then r, g, b = 0.5, 0.5, 0.5 end
		win.dot:SetVertexColor(r, g, b, (GetTime() % 1) < 0.5 and 1 or 0.35)
		local page = current and pages[current]
		if page and page.live then page:Refresh() end
	end))
end

Cfg._open = function(id) openPage(id) end -- test hook
Cfg._page = function(id) return pages[id] end -- test hook

function Cfg.RefreshAll()
	for _, p in pairs(pages) do p:Refresh() end
end

function Cfg.IsOpen() return win ~= nil and win:IsShown() end

-- Open the console on a page (e.g. /sitrep trackers).
function Cfg.Open(id)
	if not win then build() end
	win:Show()
	openPage(id)
end

function Cfg.RefreshTrackers()
	if pages.trackers and pages.trackers:IsShown() then pages.trackers:Refresh() end
end

function Cfg.Toggle()
	if not win then build() end
	if win:IsShown() then win:Hide() return end
	win:Show()
	openPage(current or "overview")
end

-- Stub in the game's own Options > AddOns list that opens the console.
ns.On("SR_LOGIN", function()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local stub = CreateFrame("Frame")
	local t = K.Font(stub, 20, C.text, K.FONT, "")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("SITREP")
	K.Paint(function(r, g, b) t:SetTextColor(r, g, b) end)
	local s = K.Font(stub, 12, C.dim)
	s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
	s:SetText("All settings live in the tactical console.")
	local b = K.Button(stub, "Open SITREP console", 180, 26, function()
		if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel) end
		Cfg.Toggle()
	end, true)
	b:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -14)
	local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, stub, "SITREP")
	if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end)

ns.On("SR_CONFIG", function(_, key)
	if win and (key == "*" or key == "hud.consoleScale") then win:SetScale(ns.P.hud.consoleScale or 1) end
	if key == "*" and win and current then pages[current]:Refresh() end
	if key == "hud.accent" and current then pages[current]:Refresh() end
end)

