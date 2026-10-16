-- SITREP · Quest arrow
-- While you navigate to a quest (click it in the quest tracker), an arrow turns
-- toward it as you turn, with the distance under it: a chevron of lines in the
-- accent colour when you face it (within 15 degrees), light grey otherwise. ~
-- before the yards: the place is learned or where you accepted the quest, not
-- given by the game. ARRIVED within 10 yards; IN <ZONE> when it lies on another
-- map. Movable like the HUD; right-click stops navigating.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local Q = ns.Quests
local read = ns.read
local format, floor, cos, sin, abs, pi = string.format, math.floor, math.cos, math.sin, math.abs, math.pi

local QA = {}
ns.QuestArrow = QA

local ARRIVED = 10    -- yards
local FACING = 0.26   -- radians (15 degrees): "you face it"
-- the chevron, pointing up (0, 1 = ahead), in pixels from its centre
local SHAPE = { { 0, 22, -17, -16 }, { 0, 22, 17, -16 }, { -17, -16, 0, -6 }, { 17, -16, 0, -6 } }
local KIND = { exact = "QUEST POSITION", learned = "LEARNED AREA", spot = "SPAWN SPOT", seen = "SEEN HERE", giver = "WHERE YOU GOT IT", turnin = "HAND IN" }

local function P() return ns.P and ns.P.quests end

local function wrap(a)
	while a > pi do a = a - 2 * pi end
	while a < -pi do a = a + 2 * pi end
	return a
end
QA.Wrap = wrap
-- Which way you face (radians; nil: not known): for the arrows beside this one.
function QA.Facing()
	local f = read(GetPlayerFacing)
	return type(f) == "number" and f or nil
end

-- Turn the chevron: angle counter-clockwise from straight ahead.
local function point(f, angle, r, g, b)
	local c, s = cos(angle), sin(angle)
	for i, seg in ipairs(SHAPE) do
		local l = f.lines[i]
		local x1, y1, x2, y2 = seg[1], seg[2], seg[3], seg[4]
		l:SetStartPoint("CENTER", f.pointer, x1 * c - y1 * s, x1 * s + y1 * c)
		l:SetEndPoint("CENTER", f.pointer, x2 * c - y2 * s, x2 * s + y2 * c)
		l:SetColorTexture(r, g, b, 1)
	end
	f.angle = angle
end
QA.Point = point

local function build()
	if QA.frame then return end
	local f = CreateFrame("Frame", "SITREP_QuestArrow", UIParent)
	f:SetSize(160, 100)
	f:SetFrameStrata("MEDIUM")
	f.pointer = CreateFrame("Frame", nil, f)
	f.pointer:SetSize(56, 56)
	f.pointer:SetPoint("TOP", 0, 0)
	f.lines = {}
	for i = 1, #SHAPE do
		local l = f.pointer:CreateLine(nil, "ARTWORK")
		l:SetThickness(3)
		f.lines[i] = l
	end
	f.dist = K.Font(f, 15, C.text, K.FONT, "OUTLINE")
	f.dist:SetPoint("TOP", f.pointer, "BOTTOM", 0, -2)
	f.title = K.Font(f, 10, C.dim, K.FONT, "OUTLINE")
	f.title:SetPoint("TOP", f.dist, "BOTTOM", 0, -2)
	f.title:SetWidth(160)
	f.title:SetWordWrap(false)
	f.kind = K.Font(f, 8, C.faint, K.FONT, "OUTLINE")
	f.kind:SetPoint("TOP", f.title, "BOTTOM", 0, -1)
	f.unlock = K.Tex(f, "BACKGROUND", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	f:EnableMouse(true)
	f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then Q.Select(nil) end end)
	K.Tooltip(f, "Quest navigation", "Right-click: stop navigating. Click another quest in the tracker to switch.")
	K.Movable(f, "questArrow", { "TOP", "TOP", 0, -110 })
	local acc = 0
	f:SetScript("OnUpdate", ns.Timed("quest arrow (f)", function(self, e)
		acc = acc + e
		if acc < 0.05 then return end
		acc = 0
		QA.Update()
	end))
	QA.frame = f
end

-- The quest being navigated to, looked up again when the quests change.
function QA.Retarget()
	QA.quest = Q.Selected()
	QA.Apply()
end

-- One look: where you are, where it is, which way you face.
function QA.Update()
	local f, q = QA.frame, QA.quest
	if not (f and q and f:IsShown()) then return end
	local here = Q.Here()
	-- which of its places: asked again every second (you move: another may be nearer;
	-- Quests keeps its choice while you stay put)
	local now = GetTime()
	if here and q.objectives and now - (QA.placeAt or 0) >= 1 then
		QA.placeAt = now
		q.target = Q.Target(q, here) or q.target
	end
	local t = q.target
	f.title:SetText(q.title)
	f.kind:SetText(t and KIND[t.kind] or "")
	local function noArrow(text)
		f.pointer:Hide()
		f.dist:SetText(text)
	end
	if not t then f:Hide() return end -- (nothing known to point at: no arrow)
	-- by air when that is clearly quicker (Travel.lua): to the flight master first
	local plan = ns.Travel and ns.Travel.Plan(here, t)
	if plan then
		f.kind:SetText((KIND[t.kind] or "") .. "  ·  FLY " .. K.Upper(plan.to) .. "  ·  " .. ns.Travel.Clock(plan.total))
		if _G.UnitOnTaxi and read(_G.UnitOnTaxi, "player") then return noArrow("IN FLIGHT") end
		local fy, fb = Q.Vector(here, plan.fromNode)
		if fy and fy < ARRIVED * 2 then return noArrow("TAKE THE FLIGHT TO " .. K.Upper(plan.to)) end
		if not fb then return noArrow("FLY FROM " .. K.Upper(plan.from)) end
		f.dist:SetText(fy and format("TO %s  %d YD", K.Upper(plan.from), floor(fy + 0.5)) or K.Upper(plan.from))
		local facing = read(GetPlayerFacing)
		if type(facing) ~= "number" then f.pointer:Hide() return end
		local rel = wrap(fb - facing)
		f.pointer:Show()
		if abs(rel) < FACING then point(f, rel, K.Accent()) else point(f, rel, C.text[1], C.text[2], C.text[3]) end
		return
	end
	-- (a target on your continent's map still gets a direction; across the sea: its zone)
	local yards, bearing = Q.Vector(here, t)
	-- along a way you have walked when the straight line is unknown ground (Trails.lua)
	local via = ns.Trails and ns.Trails.Waypoint(here, t, _G.IsIndoors and read(_G.IsIndoors))
	if via then bearing = select(2, Q.Vector(here, via)) or bearing end
	f.kind:SetText(t and KIND[t.kind] and (KIND[t.kind] .. (via and (via.door and "  ·  ENTRANCE" or "  ·  PATH") or "")) or "")
	if not bearing then
		if here and t.map ~= here.map then return noArrow("IN " .. K.Upper(t.zone or Q.MapName(t.map) or "ANOTHER ZONE")) end
		return noArrow("")
	end
	local approx = t.kind ~= "exact" and "~" or ""
	if yards and yards < ARRIVED then
		f.pointer:Hide()
		local r, g, b = K.Accent()
		f.dist:SetText(format("|cff%02x%02x%02xARRIVED|r", floor(r * 255), floor(g * 255), floor(b * 255)))
		return
	end
	f.dist:SetText(yards and format("%s%d YD", approx, floor(yards + 0.5)) or "")
	local facing = read(GetPlayerFacing)
	if type(facing) ~= "number" then f.pointer:Hide() return end
	local rel = wrap(bearing - facing)
	f.pointer:Show()
	if abs(rel) < FACING then point(f, rel, K.Accent()) else point(f, rel, C.text[1], C.text[2], C.text[3]) end
end

function QA.Apply()
	if InCombatLockdown() and not QA.frame then QA.pending = true return end
	build()
	local f = QA.frame
	local on = P().arrow and ns.P.enabled and not ns.hudHidden
		and ((QA.quest ~= nil and QA.quest.target ~= nil) or not ns.P.hud.locked)
	f:SetShown(on and true or false)
	if not InCombatLockdown() then
		f:RestorePosition()
		f:SetScale(ns.P.hud.scale * (ns.P.hud.frameScale.questArrow or 1))
		f:SetAlpha(K.Opacity("questArrow"))
	end
	f.unlock:SetShown(not ns.P.hud.locked)
	if on and not QA.quest then
		-- placing it: show what it looks like
		f.pointer:Show()
		point(f, 0, K.Accent())
		f.dist:SetText("120 YD")
		f.title:SetText("Quest navigation")
		f.kind:SetText("CLICK A QUEST TO NAVIGATE")
	end
	QA.Update()
end

ns.On("SR_LOGIN", function() QA.Retarget() end)
ns.On("SR_QUESTS", function() QA.Retarget() end)
ns.On("PLAYER_REGEN_ENABLED", function() if QA.pending then QA.pending = false; QA.Apply() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 7) == "quests." or key:sub(1, 4) == "hud." then QA.Retarget() end
end)
