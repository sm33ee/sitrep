-- SITREP · On the way: your other quests while you go for one (quests.nearby)
-- While you navigate to a quest, the others make themselves known when they are
-- close or on your way:
--   flash    a mob another quest still needs (its objective open: Quests.MobOf)
--            appearing on a plate: the plate pulses gold for FLASH_TIME (each one
--            once); the quest arrow says for FOR_TIME what it is for ("Kobold for
--            'Koboldplage' (5 to go)"), once a minute per kind of mob
--   arrow    a second line under the quest arrow, with a little arrow of its own:
--            the other quest whose place costs the least detour on your way
--            ("+ Koboldplage · 120 yd · +40 s"); shown when that is little (at most
--            DETOUR_S seconds or DETOUR_SHARE of the way) or it is right by you
--            (NEAR yards). A click: navigate to it instead
--   tracker  quests whose place is within NEAR yards: a mint bar at their row's
--            left edge
-- No quest navigated to: every quest counts as another (the flash and the bars).
-- On the ground only (same map); a flight is not weighed for a detour.
--
-- Self-contained, to take out in one go: this file and its line in the TOC, its
-- switch on the Quests page with its default (quests.nearby), and its block in
-- tests/run.lua.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local Q = ns.Quests
local read = ns.read
local format, floor, sin, pi = string.format, math.floor, math.sin, math.pi

local QN = {}
ns.QuestNearby = QN
local FLASH_TIME, PULSES = 1.6, 3
local FOR_TIME, FOR_AGAIN = 4, 60
local NEAR = 150         -- yards: "right by you"
local DETOUR_S, DETOUR_SHARE = 45, 0.2
local GOLD, MINT = { 1, 0.82, 0.3 }, { 0.44, 0.94, 0.65 }
QN.NEAR = NEAR

local function P() return ns.P and ns.P.quests end
local function on() return P() and P().nearby ~= false and ns.P.enabled end

---------------------------------------------------------------------------
-- The flash on a plate
---------------------------------------------------------------------------
local flashing = {} -- [skin] = started
local flashedGuid = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
	local now = GetTime()
	local any = false
	for s, at in pairs(flashing) do
		local t = now - at
		local f = s.srFlash
		if t >= FLASH_TIME or not s.active then
			if f then f:Hide() end
			flashing[s] = nil
		else
			any = true
			-- PULSES soft pulses, fading out over the last one
			local a = 0.5 + 0.5 * sin(t / FLASH_TIME * PULSES * 2 * pi - pi / 2)
			f:SetAlpha(a * (1 - t / FLASH_TIME * 0.4))
		end
	end
	if not any then driver:Hide() end
end)

local function flashFrame(s)
	if s.srFlash then return s.srFlash end
	local f = CreateFrame("Frame", nil, s)
	f:SetPoint("TOPLEFT", s, "TOPLEFT", -5, 18) -- (round the bar and the name over it)
	f:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 5, -5)
	f.fill = K.Tex(f, "BACKGROUND", { GOLD[1], GOLD[2], GOLD[3], 0.18 })
	f.fill:SetAllPoints()
	f.ring = K.Border(f, { GOLD[1], GOLD[2], GOLD[3], 1 }, 2, 6)
	f:Hide()
	s.srFlash = f
	return f
end

function QN.Flash(s)
	local f = flashFrame(s)
	f:SetAlpha(0)
	f:Show()
	flashing[s] = GetTime()
	driver:Show()
end
QN.flashing = flashing

-- What another quest wants of this unit: its quest and objective (nil: nothing
-- open, or the quest you navigate to).
function QN.OtherQuestOf(unit, guid)
	local objective, title = Q.MobOf(unit, guid)
	if not objective then return nil end
	local q, n = Q.Match(objective, title)
	if not (q and n) or q.id == Q.selectedId then return nil end
	local o = q.objectives[n]
	if not o or o.done then return nil end
	return q, o
end

local toldAt = {} -- [npcID or name] = when the arrow said it
function QN.PlateAdded(unit)
	if not on() then return end
	local s = ns.Plates and ns.Plates.skins[unit]
	local guid = read(UnitGUID, unit)
	if not (s and guid) or flashedGuid[guid] or read(UnitIsPlayer, unit) ~= false then return end
	local q, o = QN.OtherQuestOf(unit, guid)
	if not q then return end
	flashedGuid[guid] = true
	QN.Flash(s)
	-- the arrow says what it is for (once a minute per kind of mob)
	local key = Q.NpcID(guid) or read(UnitName, unit)
	local now = GetTime()
	if key and (not toldAt[key] or now - toldAt[key] > FOR_AGAIN) then
		toldAt[key] = now
		local left = o.need and o.have and (o.need - o.have) or nil
		QN.Say(format("%s for \"%s\"%s", tostring(read(UnitName, unit) or "?"), q.title or "?", left and format(" (%d to go)", left) or ""))
	end
end

---------------------------------------------------------------------------
-- The arrow's second line
---------------------------------------------------------------------------
local function arrowParts()
	local f = ns.QuestArrow and ns.QuestArrow.frame
	if not f then return nil end
	if f.qnLine then return f end
	f.qnLine = K.Font(f, 9, MINT, K.FONT, "OUTLINE")
	f.qnLine:SetPoint("TOP", f.kind, "BOTTOM", 6, -4)
	f.qnPointer = f:CreateTexture(nil, "OVERLAY")
	f.qnPointer:SetTexture(K.MEDIA .. "glyph_up")
	f.qnPointer:SetSize(10, 10)
	f.qnPointer:SetPoint("RIGHT", f.qnLine, "LEFT", -3, 0)
	f.qnPointer:SetVertexColor(MINT[1], MINT[2], MINT[3])
	f.qnSay = K.Font(f, 9, GOLD, K.FONT, "OUTLINE")
	f.qnSay:SetPoint("TOP", f.qnLine, "BOTTOM", -6, -2)
	-- a click on the line: navigate to that quest instead
	f.qnButton = CreateFrame("Button", nil, f)
	f.qnButton:SetPoint("TOPLEFT", f.qnPointer, "TOPLEFT", -2, 2)
	f.qnButton:SetPoint("BOTTOMRIGHT", f.qnLine, "BOTTOMRIGHT", 2, -2)
	f.qnButton:SetScript("OnClick", function() if QN.offer then Q.Select(QN.offer.id) end end)
	return f
end

function QN.Say(text)
	local f = arrowParts()
	if not f then return end
	f.qnSay:SetText(text)
	f.qnSay:Show()
	QN.saidAt = GetTime()
end

-- yards between two points on one map (nil: not the same map, or its size unknown)
local function yards(a, b)
	if not (a and b and a.map == b.map) then return nil end
	local w, h = Q.MapSize(a.map)
	if not w then return nil end
	local dx, dy = (b.x - a.x) * w, (b.y - a.y) * h
	return math.sqrt(dx * dx + dy * dy)
end
QN.Yards = yards

-- The other quest worth taking on the way to the one you navigate to: { id, title,
-- yards (from you), extra (seconds of detour), near } or nil.
function QN.Offer(here, focus, list)
	if not (here and focus and focus.target) then return nil end
	local t = focus.target
	local speed = ns.Travel and ns.Travel.Speed() or 7
	local winding = ns.Travel and ns.Travel.WINDING or 1.25
	local base = yards(here, t)
	local best
	for _, q in ipairs(list or {}) do
		local o = q.target
		if q.id ~= focus.id and o and not q.failed then
			local toIt = yards(here, o)
			if toIt then
				local near = toIt <= NEAR
				local extra
				if base then
					local onward = yards(o, t)
					if onward then extra = (toIt + onward - base) * winding / speed end
				end
				local fine = near or (extra and base and extra <= math.max(DETOUR_S, base * winding / speed * DETOUR_SHARE))
				if fine and (not best or (extra or 0) < (best.extra or 0) or (near and not best.near)) then
					best = { id = q.id, title = q.title, yards = toIt, extra = extra, near = near, target = o }
				end
			end
		end
	end
	return best
end

local lastOffer = 0
function QN.ForgetOffer() lastOffer = 0 end -- (worked out again at the next look)
function QN.ArrowLine()
	local f = arrowParts()
	if not f then return end
	local now = GetTime()
	if f.qnSay:IsShown() and QN.saidAt and now - QN.saidAt > FOR_TIME then f.qnSay:Hide() end
	if not (on() and f:IsShown() and ns.QuestArrow.quest) then
		f.qnLine:Hide(); f.qnPointer:Hide(); f.qnButton:Hide()
		return
	end
	local here = Q.Here()
	if now - lastOffer >= 1 then
		lastOffer = now
		local list = (ns.QuestTracker and ns.QuestTracker.list) or Q.Sorted(P().sort)
		QN.offer = QN.Offer(here, ns.QuestArrow.quest, list)
	end
	local o = QN.offer
	if not o then
		f.qnLine:Hide(); f.qnPointer:Hide(); f.qnButton:Hide()
		return
	end
	local yd = here and yards(here, o.target) or o.yards
	f.qnLine:SetText(format("+ %s · %d yd%s", o.title or "?", floor((yd or 0) + 0.5),
		o.extra and o.extra >= 1 and format(" · +%d s", floor(o.extra + 0.5)) or ""))
	f.qnLine:Show(); f.qnButton:Show()
	-- its little arrow: where it lies as you face
	local _, bearing = Q.Vector(here, o.target)
	local facing = ns.QuestArrow.Facing()
	if bearing and facing then
		f.qnPointer:SetRotation(ns.QuestArrow.Wrap(bearing - facing))
		f.qnPointer:Show()
	else
		f.qnPointer:Hide()
	end
end

---------------------------------------------------------------------------
-- The tracker's bars
---------------------------------------------------------------------------
function QN.TrackerBars()
	local T = ns.QuestTracker
	if not (T and T.frame) then return end
	for _, r in ipairs(T.frame.rows or {}) do
		local q = r:IsShown() and r.quest
		local near = on() and q and q.id ~= Q.selectedId and q.yards and q.yards <= NEAR and not q.failed
		if near and not r.srNear then
			r.srNear = r:CreateTexture(nil, "ARTWORK")
			r.srNear:SetPoint("TOPLEFT", 3, 0); r.srNear:SetPoint("BOTTOMLEFT", 3, 0)
			r.srNear:SetWidth(2)
			r.srNear:SetColorTexture(MINT[1], MINT[2], MINT[3], 0.9)
		end
		if r.srNear then r.srNear:SetShown(near and true or false) end
	end
end

ns.On("SR_LOGIN", function()
	if ns.QuestArrow then hooksecurefunc(ns.QuestArrow, "Update", QN.ArrowLine) end
	if ns.QuestTracker and ns.QuestTracker.Refresh then hooksecurefunc(ns.QuestTracker, "Refresh", QN.TrackerBars) end
end)
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
	-- (after the plate is dressed and its quest looked up)
	C_Timer.After(0, function() QN.PlateAdded(unit) end)
end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
	local s = ns.Plates and ns.Plates.skins[unit]
	if s and s.srFlash then s.srFlash:Hide(); flashing[s] = nil end
end)
