-- SITREP · HUD: the contact lists (envelope and threat board: enemies; allies: friends)

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local min, max, abs = math.min, math.max, math.abs
local format = string.format
local H = ns.HUD
local classColor, moduleFrame = H.ClassColor, H.ModuleFrame

---------------------------------------------------------------------------
-- ENVELOPE
-- Forever gives addons no direction to enemies, only distance. So the picture is
-- drawn the way fighter pilots read a missile fight: each contact's range bracket
-- against its weapon engagement zone (shaded) and yours (lines), with the closure
-- rate and the time until it can reach you.
---------------------------------------------------------------------------
local envelope
local LANE_H, LANE_GAP = 20, 3
local LABEL_W, INFO_W = 34, 74

local function buildEnvelope()
	local P = ns.P.hud
	local lanes = P.envelopeLanes
	local W = 300
	local trackW = W - LABEL_W - INFO_W - 16
	local f = moduleFrame("envelope", W, 40 + lanes * (LANE_H + LANE_GAP) + 22, "ENVELOPE", { "BOTTOMRIGHT", "BOTTOMRIGHT", -250, 300 })
	envelope = f
	f.trackW = trackW

	local track = CreateFrame("Frame", nil, f)
	track:SetPoint("TOPLEFT", 8 + LABEL_W, -22)
	track:SetSize(trackW, 14 + lanes * (LANE_H + LANE_GAP))
	f.track = track

	-- Axis: ticks every 5 yd, numbers every 10, and my reach as a bar under it.
	f.ticks, f.tickLabels = {}, {}
	for i = 0, 12 do
		local t = K.Tex(track, "BORDER", C.line2)
		t:SetSize(1, i % 2 == 0 and 5 or 3)
		f.ticks[i] = t
		if i % 2 == 0 then
			local l = K.Font(track, 9, C.faint, K.FONT, "")
			f.tickLabels[i] = l
		end
	end
	f.myBar = K.Tex(track, "ARTWORK")
	f.myBar:SetHeight(2)
	f.myBar:SetPoint("TOPLEFT", 0, -12)
	K.Paint(function(r, g, b) f.myBar:SetVertexColor(r, g, b, 0.9) end)
	f.myLines = {}

	f.lanes = {}
	for i = 1, lanes do
		local y = -14 - (i - 1) * (LANE_H + LANE_GAP)
		local lane = CreateFrame("Frame", nil, f)
		lane:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -22 + y)
		lane:SetSize(W - 16, LANE_H)
		lane.bg = K.Tex(lane, "BACKGROUND", C.raised)
		lane.bg:SetPoint("TOPLEFT", LABEL_W, 0)
		lane.bg:SetSize(trackW, LANE_H)
		lane.bg:SetAlpha(0.6)
		lane.zone = K.Tex(lane, "BORDER", { 1, 0.25, 0.25, 0.16 })
		lane.zone:SetPoint("TOPLEFT", LABEL_W, 0)
		lane.zone:SetHeight(LANE_H)
		lane.edge = K.Tex(lane, "ARTWORK")
		lane.edge:SetPoint("TOPLEFT", LABEL_W, 0)
		lane.edge:SetSize(2, LANE_H)
		lane.bar = K.Tex(lane, "ARTWORK", nil, 1)
		lane.bar:SetHeight(8)
		lane.more = K.Font(lane, 10, C.text, K.FONT, "OUTLINE")
		lane.label = K.Font(lane, 11, C.text, K.FONT, "")
		lane.label:SetPoint("LEFT", 0, 0)
		lane.label:SetWidth(LABEL_W - 4)
		lane.label:SetJustifyH("LEFT")
		lane.info = K.Font(lane, 11, C.text, K.FONT, "")
		lane.info:SetPoint("TOPRIGHT", 0, 1)
		lane.sub = K.Font(lane, 9, C.dim, K.FONT, "")
		lane.sub:SetPoint("BOTTOMRIGHT", 0, 0)
		lane:EnableMouse(true)
		lane:SetScript("OnEnter", function(self)
			local c = self.contact
			if not (c and GameTooltip) then return end
			local R = ns.Data.REACH[c.class] or ns.Data.REACH_DEFAULT
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(c.name or "Unknown", classColor(c.class))
			GameTooltip:AddLine(format("Level %s %s", c.level and (c.level > 0 and c.level or "??") or "?", ns.Data.NAME[c.class] or ""), 0.8, 0.8, 0.8)
			GameTooltip:AddDoubleLine("Distance", ns.Comms.RangeText(c), 0.6, 0.6, 0.6, 1, 1, 1)
			GameTooltip:AddDoubleLine("Its reach", format("%d yd", R.threat), 0.6, 0.6, 0.6, 1, 0.5, 0.5)
			GameTooltip:AddLine(R.note, 0.6, 0.6, 0.6, true)
			if c.closing then GameTooltip:AddDoubleLine("Closure", format("%+.1f yd/s", c.closing), 0.6, 0.6, 0.6, 1, 1, 1) end
			GameTooltip:Show()
		end)
		lane:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		f.lanes[i] = lane
	end

	f.empty = K.Font(f, 11, C.faint, K.FONT, "")
	f.empty:SetPoint("CENTER", 0, -6)
	f.empty:SetText("NO CONTACT")

	-- Legend
	local lg = K.Tex(f, "ARTWORK")
	lg:SetSize(10, 2)
	lg:SetPoint("BOTTOMLEFT", 8 + LABEL_W, 9)
	K.Paint(function(r, g, b) lg:SetVertexColor(r, g, b, 0.9) end)
	local lt = K.Font(f, 9, C.dim, K.FONT, "")
	lt:SetPoint("LEFT", lg, "RIGHT", 4, 0)
	lt:SetText("MY REACH")
	local zg = K.Tex(f, "ARTWORK", { 1, 0.25, 0.25, 0.5 })
	zg:SetSize(10, 6)
	zg:SetPoint("LEFT", lt, "RIGHT", 10, 0)
	local zt = K.Font(f, 9, C.dim, K.FONT, "")
	zt:SetPoint("LEFT", zg, "RIGHT", 4, 0)
	zt:SetText("THEIR REACH")
	local ct = K.Font(f, 9, C.dim, K.FONT, "")
	ct:SetPoint("LEFT", zt, "RIGHT", 10, 0)
	ct:SetText("<< CLOSING Y/S")
end

local function updateEnvelope(list)
	local f = envelope
	if not (f and f:IsShown()) then return end
	local maxR = ns.P.hud.envelopeRange
	local W = f.trackW
	local function x(yd) return min(max(yd or 0, 0), maxR) / maxR * W end

	-- axis
	for i = 0, 12 do
		local yd = i * 5
		local t = f.ticks[i]
		t:SetShown(yd <= maxR)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", f.track, "TOPLEFT", x(yd), -9 + (i % 2 == 0 and 0 or -2))
		local l = f.tickLabels[i]
		if l then
			l:SetShown(yd <= maxR)
			l:ClearAllPoints()
			l:SetPoint("BOTTOM", f.track, "TOPLEFT", x(yd), -8)
			l:SetText(yd)
		end
	end
	local mine = ns.Sensors.myRanges or { 5 }
	f.myBar:SetWidth(max(1, x(ns.Sensors.myReach or 5)))
	for i, yd in ipairs(mine) do
		local ln = f.myLines[i]
		if not ln then
			ln = K.Tex(f.track, "OVERLAY")
			K.Paint(function(r, g, b) ln:SetVertexColor(r, g, b, 0.35) end)
			f.myLines[i] = ln
		end
		ln:ClearAllPoints()
		ln:SetPoint("TOPLEFT", f.track, "TOPLEFT", x(yd), -14)
		ln:SetSize(1, #f.lanes * (LANE_H + LANE_GAP) - LANE_GAP)
		ln:SetShown(yd <= maxR)
	end
	for i = #mine + 1, #f.myLines do f.myLines[i]:Hide() end

	local inTheirs, inMine, closing = 0, 0, 0
	for _, c in ipairs(list) do
		if c.live then
			if c.inTheirReach then inTheirs = inTheirs + 1 end
			if c.inMyReach then inMine = inMine + 1 end
			if c.closing and c.closing <= -3 then closing = closing + 1 end
		end
	end

	for i, lane in ipairs(f.lanes) do
		local c = list[i]
		lane.contact = c
		if not c then
			lane:Hide()
		else
			local R = ns.Data.REACH[c.class] or ns.Data.REACH_DEFAULT
			local cr, cg, cb = classColor(c.class)
			lane.zone:SetWidth(max(1, x(R.threat)))
			lane.zone:SetVertexColor(1, 0.25, 0.25, c.inTheirReach and 0.30 or 0.13)
			-- the bracket: where it is, as precisely as the range checks allow
			local lo, hi = c.lo, c.hi
			local x0, x1
			if lo and hi then x0, x1 = x(lo), x(hi)
			elseif lo and lo > 0 then x0, x1 = x(lo), W
			elseif c.range then x0, x1 = x(c.range) - 2, x(c.range) + 2
			else x0, x1 = W - 4, W end
			lane.bar:ClearAllPoints()
			lane.bar:SetPoint("LEFT", lane, "LEFT", LABEL_W + x0, 0)
			lane.bar:SetWidth(max(3, x1 - x0))
			lane.bar:SetVertexColor(cr, cg, cb, c.live and 0.95 or 0.4)
			lane.more:SetShown(hi == nil and lo ~= nil and lo > 0)
			lane.more:ClearAllPoints()
			lane.more:SetPoint("RIGHT", lane, "LEFT", LABEL_W + W, 0)
			lane.more:SetText(">")
			-- left edge: targeting me (red) or HVT (accent)
			if c.targetingMe then lane.edge:SetVertexColor(1, 0.25, 0.25, 1); lane.edge:Show()
			elseif c.hvt then lane.edge:SetVertexColor(K.Accent()); lane.edge:Show()
			else lane.edge:Hide() end
			lane.label:SetText((ns.Data.SHORT[c.class] or "???") .. (c.hvt and "*" or ""))
			lane.label:SetTextColor(cr, cg, cb)
			local rate = ""
			if c.closing then
				rate = format(c.closing < 0 and "  |cffff5555<<%.0f|r" or "  |cff8a9492>>%.0f|r", abs(c.closing))
			end
			lane.info:SetText(ns.Comms.RangeText(c) .. rate)
			if c.inTheirReach and c.live then
				lane.sub:SetText("|cffff5555IN ITS REACH|r")
			elseif c.ttr then
				lane.sub:SetText(format("|cffffb833REACH IN %.1fs|r", c.ttr))
			elseif c.inMyReach and c.live then
				lane.sub:SetText("IN MY RANGE")
			elseif not c.live then
				lane.sub:SetText(c.net and ("NET " .. c.net) or format("LOST %.0fs", c.age or 0))
			else
				lane.sub:SetText("")
			end
			lane:SetAlpha(c.live and 1 or 0.65)
			lane:Show()
		end
	end
	f.empty:SetShown(#list == 0)
	f.status:SetText(format("THEIRS %d  MINE %d  CLOSING %d", inTheirs, inMine, closing))
	if inTheirs > 0 then f.status:SetTextColor(1, 0.4, 0.4) else f.status:SetTextColor(unpack(C.dim)) end
end

---------------------------------------------------------------------------
-- CONTACTS (threat board)
---------------------------------------------------------------------------
local board
local ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ROW_H = 26

local function newRow(parent, i)
	local r = CreateFrame("Frame", nil, parent)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 6, -20 - (i - 1) * (ROW_H + 2))
	r:SetPoint("TOPRIGHT", -6, -20 - (i - 1) * (ROW_H + 2))
	r.bg = K.Tex(r, "BACKGROUND", C.raised)
	r.bg:SetAllPoints()
	r.bg:SetAlpha(0.55)
	r.strip = K.Tex(r, "ARTWORK")
	r.strip:SetPoint("TOPLEFT"); r.strip:SetPoint("BOTTOMLEFT"); r.strip:SetWidth(2)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 6, 1)
	r.name = K.Font(r, 12, C.text)
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
	r.name:SetWidth(120)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.tags = K.Font(r, 9, C.dim, K.FONT, "")
	r.tags:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -1)
	r.where = K.Font(r, 12, C.text, K.FONT, "")
	r.where:SetPoint("TOPRIGHT", -6, -3)
	r.threat = K.Tex(r, "OVERLAY")
	r.threat:SetHeight(2)
	r.threat:SetPoint("BOTTOMLEFT", 2, 0)
	r.hp = CreateFrame("StatusBar", nil, r)
	r.hp:SetStatusBarTexture(K.WHITE)
	r.hp:SetHeight(2)
	r.hp:SetPoint("TOPLEFT", 2, 0)
	r.hp:SetPoint("TOPRIGHT", 0, 0)
	r.hp:SetStatusBarColor(0.35, 0.95, 0.5, 0.8)
	ns.Heals.Attach(r.hp)
	-- Click to target. Targeting is protected: the button's target can only be set
	-- out of combat, so in combat the rows keep their contacts (see displayList).
	r.click = CreateFrame("Button", nil, r, "SecureActionButtonTemplate")
	r.click:SetAllPoints()
	r.click:RegisterForClicks("AnyUp", "AnyDown")
	r.click:HookScript("OnEnter", function()
		r.bg:SetAlpha(0.95)
		if GameTooltip and r.clickName then
			GameTooltip:SetOwner(r, "ANCHOR_LEFT")
			GameTooltip:SetText("Click to target " .. r.clickName, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	r.click:HookScript("OnLeave", function()
		r.bg:SetAlpha(0.55)
		if GameTooltip then GameTooltip:Hide() end
	end)
	r.click:Hide()
	return r
end

-- Point a row's button at a contact. Only possible out of combat.
local function bindRow(r, c)
	if InCombatLockdown() then return end
	local name = c and (c.fullName or (c.name ~= "Unknown" and c.name)) or nil
	local id = c and (c.key .. "|" .. tostring(name)) or nil
	if r.clickId == id then return end
	r.clickId, r.clickKey, r.clickName = id, c and c.key, name
	local b = r.click
	if not c then b:Hide() return end
	if name then
		b:SetAttribute("type1", "macro")
		b:SetAttribute("macrotext1", "/targetexact " .. name)
	elseif c.unit then
		b:SetAttribute("type1", "target") -- identity secret: target its unit token
		b:SetAttribute("unit", c.unit)
		r.clickName = "this contact"
	else
		b:Hide()
		return
	end
	b:Show()
end

-- Which contact each row shows. Out of combat: threat order. In combat: every
-- contact keeps the row it had (stable track numbers, so a click can never land
-- on someone else); contacts first seen in combat fill free rows, tagged NEW.
-- state: one table per panel; lookup: key -> live record (contacts or allies).
local function displayList(list, rows, state, lookup)
	if not InCombatLockdown() then state.pinned = nil return list end
	local pinned = state.pinned
	if not pinned then
		pinned = { names = {} }
		for i = 1, #rows do pinned[i], pinned.names[i] = rows[i].clickKey, rows[i].clickName end
		state.pinned = pinned
	end
	local out, used = {}, {}
	for i = 1, #rows do
		local key = pinned[i]
		if key then
			local c = lookup[key]
			out[i] = c or { key = key, name = pinned.names[i], gone = true, threat = 0, age = 0 }
			used[key] = true
		end
	end
	local j = 1
	for i = 1, #rows do
		if not pinned[i] then
			while list[j] and used[list[j].key] do j = j + 1 end
			if list[j] then out[i] = list[j]; used[list[j].key] = true; j = j + 1 end
		end
	end
	return out
end
H.DisplayList = displayList

local boardPin = {}

local function buildBoard()
	local P = ns.P.hud
	local f = moduleFrame("board", 300, 26 + P.boardRows * (ROW_H + 2), "CONTACTS", { "BOTTOMRIGHT", "BOTTOMRIGHT", -250, 470 })
	board = f
	f.rows = {}
	for i = 1, P.boardRows do f.rows[i] = newRow(f, i) end
	f.empty = K.Font(f, 11, C.faint, K.FONT, "")
	f.empty:SetPoint("CENTER", 0, -6)
	f.empty:SetText("NO CONTACT")
end


local function threatColor(t)
	if t >= 70 then return 1, 0.33, 0.33 end
	if t >= 35 then return 1, 0.72, 0.2 end
	return K.Accent()
end

local function updateBoard(list)
	local f = board
	if not (f and f:IsShown()) then return end
	local rows = #f.rows
	local top = list[1] and list[1].threat or 0
	local scale = max(100, top)
	local rowW = f:GetWidth() - 14
	local fighting = InCombatLockdown()
	local display = displayList(list, f.rows, boardPin, ns.Sensors.contacts)
	for i = 1, rows do
		local r, c = f.rows[i], display[i]
		if c and c.gone then
			-- pinned contact no longer tracked: keep the row (and its click) in place
			r.name:SetText(c.name or "?")
			r.name:SetTextColor(unpack(C.faint))
			r.tags:SetText("LOST")
			r.where:SetText("")
			r.threat:SetWidth(1); r.hp:Hide()
			r:SetAlpha(0.45); r:Show()
		elseif c then
			local cr, cg, cb = classColor(c.class)
			local tc = CLASS_ICON_TCOORDS and c.class and CLASS_ICON_TCOORDS[c.class]
			if tc then
				r.icon:SetTexture(ICONS)
				r.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
				r.icon:SetVertexColor(1, 1, 1)
			else
				r.icon:SetTexture(K.WHITE)
				r.icon:SetTexCoord(0, 1, 0, 1)
				r.icon:SetVertexColor(cr, cg, cb)
			end
			local lvl = c.level and (c.level > 0 and tostring(c.level) or "??") or "?"
			r.name:SetText(format("%s |cff8a9492%s|r", c.name or "?", lvl))
			r.name:SetTextColor(cr, cg, cb)
			local tags = {}
			if c.targetingMe then tags[#tags + 1] = "|cffff5555>> YOU|r" end
			if c.hvt then tags[#tags + 1] = "|cff5cff8dHVT|r" end
			if c.casting then tags[#tags + 1] = "|cffffc040CAST|r" end
			if c.inCombat then tags[#tags + 1] = "COMBAT" end
			if not c.live then tags[#tags + 1] = c.net and ("NET " .. c.net) or format("LKP %.0fs", c.age or 0) end
			if fighting and r.clickKey ~= c.key then tags[#tags + 1] = "|cffffb833NEW|r" end -- clickable after combat
			r.tags:SetText(table.concat(tags, "  "))
			r.where:SetText(ns.Comms.RangeText(c))
			local tr, tg, tb = threatColor(c.threat)
			r.strip:SetVertexColor(tr, tg, tb, 1)
			r.threat:SetVertexColor(tr, tg, tb, 0.9)
			r.threat:SetWidth(max(1, rowW * min(1, c.threat / scale)))
			r:SetAlpha(c.live and 1 or 0.6)
			-- Health can be secret: hand it straight to the bar, never look at it.
			local shown = false
			if ns.P.hud.showHealth and c.live and c.unit then
				shown = pcall(function()
					r.hp:SetMinMaxValues(0, UnitHealthMax(c.unit))
					r.hp:SetValue(UnitHealth(c.unit))
				end)
			end
			r.hp:SetShown(shown)
			r.hpUnit = shown and c.unit or nil
			ns.Heals.Feed(r.hp, r.hpUnit) -- enemy healers' heals on it
			bindRow(r, c)
			r:Show()
		else
			bindRow(r, nil)
			if fighting then r:SetAlpha(0) else r:Hide() end -- no Show/Hide on secure parents in combat
		end
	end
	f.empty:SetShown(#list == 0)
	local hvt = ns.Model.byPriority[1]
	f.status:SetText(hvt and hvt.hvt and ("HVT  " .. (hvt.name or "?")) or format("%d TRACKED", #list))
	if hvt and hvt.hvt then f.status:SetTextColor(K.Accent()) else f.status:SetTextColor(unpack(C.dim)) end
end


---------------------------------------------------------------------------
-- ALLIES: the friendly picture. Group members exact, others by range checks.
-- colour shows heal range here (green inside, orange unsure, red outside).
---------------------------------------------------------------------------
local allies
local alliesPin = {}

local function buildAllies()
	local P = ns.P.hud
	local f = moduleFrame("allies", 300, 26 + P.alliesRows * (ROW_H + 2), "ALLIES", { "BOTTOMLEFT", "BOTTOMLEFT", 250, 300 })
	allies = f
	f.rows = {}
	for i = 1, P.alliesRows do
		local r = newRow(f, i)
		r.name:SetWidth(110)
		f.rows[i] = r
	end
	f.empty = K.Font(f, 11, C.faint, K.FONT, "")
	f.empty:SetPoint("CENTER", 0, -6)
	f.empty:SetText("NO ALLIES")
end

local HEAL_COLOR = { [true] = { 0.35, 0.92, 0.42 }, [false] = { 1, 0.3, 0.25 } }

local function updateAllies(list)
	local f = allies
	if not (f and f:IsShown()) then return end
	local fighting = InCombatLockdown()
	local display = displayList(list, f.rows, alliesPin, ns.Allies.byKey)
	local focused = 0
	for _, a in ipairs(list) do if a.focus and a.focus > 0 then focused = focused + 1 end end
	local rowW = f:GetWidth() - 14
	for i, r in ipairs(f.rows) do
		local a = display[i]
		if a and a.gone then
			r.name:SetText(a.name or "?"); r.name:SetTextColor(unpack(C.faint))
			r.tags:SetText("LEFT"); r.where:SetText("")
			r.threat:SetWidth(1); r.hp:Hide(); r:SetAlpha(0.45); r:Show()
		elseif a then
			local cr, cg, cb = classColor(a.class)
			local tc = CLASS_ICON_TCOORDS and a.class and CLASS_ICON_TCOORDS[a.class]
			if tc then r.icon:SetTexture(ICONS); r.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]); r.icon:SetVertexColor(1, 1, 1)
			else r.icon:SetTexture(K.WHITE); r.icon:SetTexCoord(0, 1, 0, 1); r.icon:SetVertexColor(cr, cg, cb) end
			r.name:SetText(a.name or "?")
			r.name:SetTextColor(cr, cg, cb)
			local tags = {}
			if a.focus and a.focus > 0 then tags[#tags + 1] = format("|cffff5555TARGETED BY %d|r", a.focus) end
			if a.dead then tags[#tags + 1] = "|cff8a9492DEAD|r"
			elseif a.inHeal == true then tags[#tags + 1] = "|cff5cff8dIN HEAL RANGE|r"
			elseif a.inHeal == false then tags[#tags + 1] = "|cffff8040OUT OF HEAL RANGE|r" end
			if not a.live then tags[#tags + 1] = format("LOST %.0fs", ns.read(GetTime) - (a.last or 0)) end
			r.tags:SetText(table.concat(tags, "  "))
			r.where:SetText(ns.Comms.RangeText(a))
			-- distance coloured by your heal range (green inside, red outside, orange unsure)
			local hc = HEAL_COLOR[a.inHeal] or { 1, 0.65, 0.15 }
			r.where:SetTextColor(hc[1], hc[2], hc[3])
			-- focus shows as the row's edge and bar: one third per enemy on them
			if a.focus and a.focus > 0 then
				r.strip:SetVertexColor(1, 0.3, 0.3, 1)
				r.threat:SetVertexColor(1, 0.3, 0.3, 0.9)
				r.threat:SetWidth(max(1, rowW * min(1, a.focus / 3)))
			else
				r.strip:SetVertexColor(K.Accent())
				r.threat:SetWidth(1)
			end
			-- health straight from the client (may be secret)
			local shown = a.live and a.unit and pcall(function()
				r.hp:SetMinMaxValues(0, UnitHealthMax(a.unit))
				r.hp:SetValue(UnitHealth(a.unit))
			end) or false
			r.hp:SetShown(shown)
			r.hpUnit = shown and a.unit or nil
			ns.Heals.Feed(r.hp, r.hpUnit) -- heals on their way, yours and others'
			r:SetAlpha(a.live and (a.dead and 0.5 or 1) or 0.6)
			bindRow(r, a)
			r:Show()
		else
			bindRow(r, nil)
			if fighting then r:SetAlpha(0) else r:Hide() end
		end
	end
	f.empty:SetShown(#list == 0)
	f.status:SetText(focused > 0 and format("%d TARGETED", focused) or format("%d TRACKED", #list))
	if focused > 0 then f.status:SetTextColor(1, 0.4, 0.4) else f.status:SetTextColor(unpack(C.dim)) end
end
H.UpdateAllies = updateAllies

-- A heal started, landed or was cancelled on a unit: redraw its rows at once.
function H.FeedRowHeals(unit)
	for _, f in ipairs({ board, allies }) do
		if f and f.rows then
			for _, r in ipairs(f.rows) do
				if r.hpUnit and (r.hpUnit == unit or ns.read(UnitIsUnit, r.hpUnit, unit)) then ns.Heals.Feed(r.hp, r.hpUnit) end
			end
		end
	end
end


H.BuildEnvelope, H.UpdateEnvelope = buildEnvelope, updateEnvelope
H.BuildBoard, H.UpdateBoard = buildBoard, updateBoard
H.BuildAllies, H.UpdateAllies = buildAllies, updateAllies
