-- SITREP · Target frame

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read, plain = ns.read, ns.plain
local format, min, max, floor, abs = string.format, math.min, math.max, math.floor, math.abs
local F = ns.Frames
local U = ns.Units
local TG = ns.Targeting
local newBar, castBar, ticks = U.NewBar, U.CastBar, U.Ticks
local feedBar, healthText, percentText, nameText = U.FeedBar, U.HealthText, U.PercentText, U.NameText
local powerColor, curveColor, updateCast = U.PowerColor, U.CurveColor, U.UpdateCast
local HP_GREEN, HP_ORANGE, HP_RED = U.HP_COLORS.green, U.HP_COLORS.orange, U.HP_COLORS.red
local frameShell = F.Shell

-- Fire control: can I hit it, should I, what is it doing? Range strip against
-- my spells and its reach, cast bar with the KICK window, execute marker, combo
-- pips, threat and HVT, who else is on it (ALLIES, HEALERS / TARGETED BY),
-- matchup verdict, my record against its class, and whom it targets (with that
-- one's health; click it to target it).

---------------------------------------------------------------------------
-- TARGET
---------------------------------------------------------------------------
local target -- the frame (also F.target)
local STRIP_LABEL = 0
local ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local TOT_TRACK = 0.16 -- opacity of the green track behind the target's-target health

local function buildTarget()
	local P = ns.P.frames
	local W = P.width
	local f = frameShell("target", "target", "TARGET", { "CENTER", "CENTER", 260, -190 })
	target = f
	F.target = f
	-- (top down: name, health, power, cast bar, combo pips, range strip, intel line,
	-- its target; each below the one before, so taller text cannot overlap)
	f:SetHeight(142)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(16, 16)
	f.icon:SetPoint("TOPLEFT", 8, -18)
	f.name = K.Font(f, 14, C.text)
	f.name:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.name:SetPoint("RIGHT", f, "RIGHT", -60, 0)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false)
	f.level = K.Font(f, 11, C.dim, K.FONT, "")
	f.level:SetPoint("TOPRIGHT", -8, -20)
	f.raid = f:CreateTexture(nil, "OVERLAY")
	f.raid:SetSize(14, 14)
	f.raid:SetPoint("RIGHT", f.level, "LEFT", -4, 0)
	f.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

	f.hp = newBar(f, 16, 1)
	U.Ghost(f.hp, 1, 1, 1, 0.45) -- (glass: the damage just dealt, lit)
	f.hp:SetPoint("TOPLEFT", 8, -40)
	f.hp:SetPoint("TOPRIGHT", -8, -40)
	ns.Heals.Attach(f.hp) -- incoming heals on the target, yours and others'
	f.hpTicks = ticks(f.hp, { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 }, 0.35)
	f.exec = K.Tex(f.hp, "OVERLAY", { 1, 0.85, 0.2, 1 })
	f.exec:SetWidth(2)
	f.execLabel = K.Font(f.hp, 9, { 1, 0.85, 0.2, 1 }, K.FONT, "OUTLINE")
	f.hpText = K.Font(f.hp, 12, C.text, K.FONT, "OUTLINE")
	f.hpText:SetPoint("RIGHT", -6, 0)
	f.pctText = K.Font(f.hp, 12, C.text, K.FONT, "OUTLINE")
	f.pctText:SetPoint("CENTER")

	f.power = newBar(f, 4, 1)
	f.power:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -2)
	f.power:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -2)

	-- cast bar; last quarter of an interruptible cast: brighter, bright edge, KICK
	castBar(f, f.power, 12)

	-- combo pips (rogues and druids)
	f.pips = {}
	for i = 1, 5 do
		local p = K.Tex(f, "ARTWORK")
		p:SetSize(14, 4)
		p:SetPoint("TOPRIGHT", f.power, "BOTTOMRIGHT", -(5 - i) * 17, -18)
		f.pips[i] = p
	end

	-- range strip: its bracket, its reach (red), my spell ranges (accent lines)
	local strip = CreateFrame("Frame", nil, f)
	strip:SetHeight(12)
	strip:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", STRIP_LABEL, -32)
	strip:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", -78, -32)
	strip.bg = K.Tex(strip, "BACKGROUND", C.raised)
	strip.bg:SetAllPoints()
	strip.zone = K.Tex(strip, "BORDER", { 1, 0.25, 0.25, 0.18 })
	strip.zone:SetPoint("TOPLEFT"); strip.zone:SetPoint("BOTTOMLEFT")
	strip.bar = K.Tex(strip, "ARTWORK", nil, 1)
	strip.bar:SetHeight(6)
	strip.lines = {}
	-- a fixed 0-40 yd scale: ticks every 5 yd, taller every 10
	strip.ticks = {}
	for yd = 5, 35, 5 do
		local t = K.Tex(strip, "BORDER", { 1, 1, 1, yd % 10 == 0 and 0.22 or 0.12 }, 1)
		t:SetSize(1, yd % 10 == 0 and 12 or 6)
		t.yd = yd
		strip.ticks[#strip.ticks + 1] = t
	end
	strip.info = K.Font(f, 11, C.text, K.FONT, "")
	strip.info:SetPoint("LEFT", strip, "RIGHT", 6, 0)
	f.strip = strip

	-- the matchup and its advice: under the range strip (and its yards), not on it
	f.intel = K.Font(f, 10.5, C.dim, K.FONT, "")
	f.intel:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -5)
	f.intel:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.intel:SetWordWrap(false)
	f.intel:SetJustifyH("LEFT")
	f.tot = K.Font(f, 11, C.text, K.FONT, "")
	f.tot:SetPoint("BOTTOMLEFT", 8, 9)
	-- its target's health: a slim bar under the name
	f.totHp = newBar(f, 4, 2)
	f.totHp:SetPoint("BOTTOMLEFT", 8, 4)
	f.totHp:SetWidth(140)
	-- the usual dark background, and over it a faint green track across the full
	-- width, so the empty part still shows where full health was. Its own layer,
	-- drawn with the client's solid-colour call (alpha in the colour itself).
	f.totHp.track = f.totHp:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.totHp.track:SetAllPoints()
	if f.totHp.track.SetColorTexture then
		f.totHp.track:SetColorTexture(HP_GREEN[1], HP_GREEN[2], HP_GREEN[3], TOT_TRACK)
	else
		f.totHp.track:SetTexture(K.WHITE)
		f.totHp.track:SetVertexColor(HP_GREEN[1], HP_GREEN[2], HP_GREEN[3], TOT_TRACK)
	end
	f.totHp.cap = K.Tex(f.totHp, "BORDER", { HP_GREEN[1], HP_GREEN[2], HP_GREEN[3], 0.35 })
	f.totHp.cap:SetWidth(1)
	f.totHp.cap:SetPoint("TOPRIGHT"); f.totHp.cap:SetPoint("BOTTOMRIGHT")
	f.totHp:Hide()
	f.record = K.Font(f, 10.5, C.dim, K.FONT, "")
	f.record:SetPoint("BOTTOMRIGHT", -8, 8)

	-- Click "its target" to target it. "targettarget" is a fixed unit token, so
	-- this works in combat too.
	local tb = CreateFrame("Button", "SITREP_TargetTargetButton", f, "SecureUnitButtonTemplate")
	tb:SetPoint("BOTTOMLEFT", 4, 3)
	tb:SetSize(150, 18)
	tb:SetFrameLevel(f:GetFrameLevel() + 5)
	tb:SetAttribute("unit", "targettarget")
	tb:SetAttribute("type1", "target")
	tb:SetAttribute("type2", "togglemenu")
	tb:RegisterForClicks("AnyUp")
	tb.hl = K.Tex(tb, "BACKGROUND", { 1, 1, 1, 0.07 })
	tb.hl:SetAllPoints()
	tb.hl:Hide()
	tb:HookScript("OnEnter", function(self)
		-- (no target of its own: nothing to click, nothing lights up)
		if read(UnitExists, "targettarget") ~= true then return end
		self.hl:Show()
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
			GameTooltip:SetText("Click to target its target", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	tb:HookScript("OnLeave", function(self) self.hl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
	f.totButton = tb

	-- A pet: "Pet of Varok" in place of the title; click it to target the owner.
	-- A secure button runs a /targetexact macro, which can be set out of combat
	-- only: it is set when you target the pet, and emptied when combat starts (an
	-- old name must not stay clickable); in combat the owner's plate is marked.
	local ob = CreateFrame("Button", "SITREP_PetOwnerButton", f, "SecureActionButtonTemplate")
	ob:SetPoint("TOPLEFT", 4, -2)
	ob:SetSize(170, 14)
	ob:SetFrameLevel(f:GetFrameLevel() + 5)
	ob:SetAttribute("type1", "macro")
	ob:SetAttribute("macrotext1", "")
	ob:RegisterForClicks(GetCVar and GetCVar("ActionButtonUseKeyDown") == "1" and "AnyDown" or "AnyUp")
	ob.hl = K.Tex(ob, "BACKGROUND", { 1, 1, 1, 0.07 })
	ob.hl:SetAllPoints()
	ob.hl:Hide()
	ob:HookScript("OnEnter", function(self)
		local owner = TG.petOwner
		if not owner then return end
		self.hl:Show()
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			if InCombatLockdown() then
				GameTooltip:SetText(owner .. ": click their plate", 1, 1, 1)
				GameTooltip:AddLine("(marked OWNER; the frame cannot target in combat)", 0.6, 0.65, 0.65)
			else
				GameTooltip:SetText("Click to target " .. owner, 1, 1, 1)
			end
			GameTooltip:Show()
		end
	end)
	ob:HookScript("OnLeave", function(self) self.hl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
	f.ownerButton = ob
	f.titleText = f.title:GetText()

	f.hpTicks.Layout(W - 16)
	K.Paint(function(r, g, b) f.title:SetTextColor(r, g, b) end)
end
F.BuildTarget = buildTarget

local function targetContact()
	local key = ns.Sensors.UnitKey("target")
	return key and ns.Sensors.contacts[key]
end

local function recordText(class)
	if not class then return "" end
	local parts = {}
	local d = ns.db.log.duels[class]
	if d and (d.w + d.l) > 0 then parts[#parts + 1] = format("DUELS %d-%d", d.w, d.l) end
	local w, l = 0, 0
	for _, e in ipairs(ns.db.log.engagements) do
		if e.kind ~= "duel" and e.comp and e.comp[class] then
			if e.outcome == "WIN" then w = w + 1 elseif e.outcome == "LOSS" then l = l + 1 end
		end
	end
	if w + l > 0 then parts[#parts + 1] = format("FIGHTS %d-%d", w, l) end
	return table.concat(parts, "  ")
end
F.RecordText = recordText

-- The title: "Pet of <owner>" for a pet (coral when an enemy's), else the frame's.
local PET_COL = { 1, 0.36, 0.30 }
local function petTitle(f)
	local owner = read(UnitExists, "target") and TG.petOwner or nil
	if owner then
		f.title:SetText("Pet of " .. owner)
		if ns.Sensors.IsEnemy("target") then f.title:SetTextColor(PET_COL[1], PET_COL[2], PET_COL[3]) else f.title:SetTextColor(K.Accent()) end
	elseif f.title:GetText() ~= f.titleText then
		f.title:SetText(f.titleText)
		f.title:SetTextColor(K.Accent())
	end
	-- (the click: out of combat only)
	local ob = f.ownerButton
	if ob and not InCombatLockdown() then ob:SetAttribute("macrotext1", owner and ("/targetexact " .. owner) or "") end
end
F.PetTitle = petTitle

-- The matchup against an enemy player and the advice for its class ("MATCHUP x1.00
-- EVEN · EARTH SHOCK AT 20"), or nil (the target frame and the hover window).
function F.IntelText(unit)
	if not ns.P.frames.intel then return nil end
	if read(UnitIsPlayer, unit) ~= true or not ns.Sensors.IsEnemy(unit) then return nil end
	local _, class = read(UnitClass, unit)
	if not class then return nil end
	local me = ns.Sensors.self
	local m = ns.P.threat.matrix[me.class or "WARRIOR"]
	m = m and m[class] or 1
	local verdict = m >= 1.15 and "|cffff5555DANGEROUS|r" or m <= 0.9 and "|cff5cff8dFAVOURABLE|r" or "EVEN"
	local R = ns.Data.REACH[class] or ns.Data.REACH_DEFAULT
	return format("MATCHUP x%.2f %s  ·  %s", m, verdict, R.note:upper())
end

local function updateTargetBody()
	local f = target
	if not f then return end
	petTitle(f)
	local exists = read(UnitExists, "target")
	if not exists then
		ns.Heals.Feed(f.hp, nil)
		-- unlocked with nothing targeted: a placeholder to position
		f.name:SetText("NO TARGET"); f.name:SetTextColor(unpack(C.faint))
		f.cast:Hide(); f.tags:SetText(""); f.intel:SetText(""); f.record:SetText(""); f.tot:SetText(""); f.totHp:Hide()
		return
	end
	local P = ns.P.frames
	local me = ns.Sensors.self
	local _, class = read(UnitClass, "target")
	local isPlayer = read(UnitIsPlayer, "target")
	local hostile = ns.Sensors.IsEnemy("target") -- players, pets and NPCs
	local reaction = read(UnitReaction, "target", "player")

	-- identity
	nameText(f.name, "target")
	local cr, cg, cb
	if isPlayer and class then cr, cg, cb = ns.Data.ClassColor(class)
	elseif reaction then
		if reaction <= 3 then cr, cg, cb = 1, 0.28, 0.22 elseif reaction == 4 then cr, cg, cb = 1, 0.62, 0.15 else cr, cg, cb = 0.35, 0.92, 0.42 end
	else cr, cg, cb = 0.8, 0.8, 0.8 end
	if read(UnitIsTapDenied, "target") then cr, cg, cb = 0.5, 0.5, 0.5 end
	f.name:SetTextColor(cr, cg, cb)
	local tc = isPlayer and CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
	if tc then
		f.icon:SetTexture(ICONS); f.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]); f.icon:SetVertexColor(1, 1, 1); f.icon:Show()
	else
		f.icon:SetTexture(K.WHITE); f.icon:SetTexCoord(0, 1, 0, 1); f.icon:SetVertexColor(cr, cg, cb); f.icon:Show()
	end
	-- level only when it tells you something
	local lvl = read(UnitLevel, "target")
	local cls = read(UnitClassification, "target")
	local lv = ""
	if lvl and lvl <= 0 then lv = "|cffff4040??|r"
	elseif lvl and me.level and lvl ~= me.level then
		local d = lvl - me.level
		lv = format(d >= 3 and "|cffff6040%d|r" or d <= -3 and "|cff8a9492%d|r" or "%d", lvl)
	end
	if cls == "elite" or cls == "rareelite" or cls == "worldboss" then lv = lv .. " |cffffd040ELITE|r"
	elseif cls == "rare" then lv = lv .. " |cffc0c0ffRARE|r" end
	f.level:SetText(lv)
	local idx = read(GetRaidTargetIndex, "target")
	if idx and SetRaidTargetIconTexture then SetRaidTargetIconTexture(f.raid, idx); f.raid:Show() else f.raid:Hide() end

	-- health and power
	feedBar(f.hp, UnitHealth, UnitHealthMax, "target")
	f.hp:SetStatusBarColor(cr * 0.85, cg * 0.85, cb * 0.85)
	ns.Heals.Feed(f.hp, "target")
	healthText(f.hpText, "target")
	percentText(f.pctText, "target")
	feedBar(f.power, UnitPower, UnitPowerMax, "target")
	f.power:SetStatusBarColor(powerColor("target"))
	local ex = ns.Data.EXECUTE[me.class]
	local w = f.hp:GetWidth() > 0 and f.hp:GetWidth() or (P.width - 16)
	if P.execute and ex and hostile then
		f.exec:ClearAllPoints()
		f.exec:SetPoint("TOPLEFT", f.hp, "TOPLEFT", floor(w * ex.pct / 100), 0)
		f.exec:SetPoint("BOTTOMLEFT", f.hp, "BOTTOMLEFT", floor(w * ex.pct / 100), 0)
		f.execLabel:ClearAllPoints()
		f.execLabel:SetPoint("BOTTOMLEFT", f.exec, "TOPRIGHT", 2, -9)
		f.execLabel:SetText(ex.short)
		f.exec:Show(); f.execLabel:Show()
	else
		f.exec:Hide(); f.execLabel:Hide()
	end

	updateCast(f, "target")

	-- combo pips
	local showPips = me.class == "ROGUE" or me.class == "DRUID"
	local cp = showPips and read(GetComboPoints, "player", "target") or 0
	for i, p in ipairs(f.pips) do
		p:SetShown(showPips)
		if i <= cp then p:SetVertexColor(1, 0.85, 0.2, 1) else p:SetVertexColor(1, 1, 1, 0.12) end
	end

	-- range strip: enemies against my harmful spells, allies against my helpful ones
	local S_ = ns.Sensors
	local friendly = not hostile and (read(UnitIsFriend, "player", "target") or false)
	local ladder = friendly and S_.helpChecks or S_.checks
	local c = hostile and targetContact() or nil
	local ally = not hostile and ns.Allies and ns.Allies.ForUnit("target") or nil
	local lo, hi, range
	if c then lo, hi, range = c.lo, c.hi, c.range
	elseif ally then lo, hi, range = ally.lo, ally.hi, ally.range -- exact for group members
	else
		lo, hi = S_.MeasureRange("target", nil, ladder)
		range = S_.RangeEstimate(lo, hi, nil)
	end
	f.stripMode = friendly and "help" or "harm"
	local s = f.strip
	s:SetShown(P.strip)
	s.info:SetShown(P.strip)
	if P.strip then
		local maxR = 40 -- the overview always spans 0-40 yd
		local sw = s:GetWidth() > 0 and s:GetWidth() or (P.width - 16 - 78)
		local function x(yd) return min(max(yd or 0, 0), maxR) / maxR * sw end
		for _, t in ipairs(s.ticks) do
			t:ClearAllPoints()
			t:SetPoint("LEFT", s, "LEFT", x(t.yd), 0)
		end
		local R = ns.Data.REACH[class] or ns.Data.REACH_DEFAULT
		s.zone:SetShown(hostile and isPlayer and true or false)
		s.zone:SetWidth(max(1, x(R.threat)))
		s.zone:SetVertexColor(1, 0.25, 0.25, c and c.inTheirReach and 0.36 or 0.16)
		local x0, x1
		if lo and hi then x0, x1 = x(lo), x(hi)
		elseif lo and lo > 0 then x0, x1 = x(lo), sw
		elseif range then x0, x1 = x(range) - 2, x(range) + 2 end
		if x0 then
			s.bar:ClearAllPoints()
			s.bar:SetPoint("LEFT", s, "LEFT", x0, 0)
			s.bar:SetWidth(max(3, x1 - x0))
			s.bar:SetVertexColor(cr, cg, cb, 1)
			s.bar:Show()
		else
			s.bar:Hide()
		end
		-- my spell lines: accent for harmful (enemy), green for helpful (ally)
		local mine = friendly and (S_.myHelpRanges or {}) or (S_.myRanges or { 5 })
		local lr, lg, lb = K.Accent()
		if friendly then lr, lg, lb = 0.35, 0.92, 0.42 end
		for i, yd in ipairs(mine) do
			local ln = s.lines[i]
			if not ln then
				ln = K.Tex(s, "OVERLAY")
				ln:SetWidth(1)
				s.lines[i] = ln
			end
			ln:SetVertexColor(lr, lg, lb, 0.8)
			ln:ClearAllPoints()
			ln:SetPoint("TOPLEFT", s, "TOPLEFT", x(yd), 0)
			ln:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", x(yd), 0)
			ln:SetShown(yd <= maxR)
		end
		for i = #mine + 1, #s.lines do s.lines[i]:Hide() end
		-- which of the relevant spells reach it right now
		local reach, nSpells = 0, 0
		for _, chk in ipairs(ladder or {}) do
			if chk.kind == "spell" then
				nSpells = nSpells + 1
				if hi and chk.max >= hi then reach = reach + 1 end
			end
		end
		local rate = ""
		if c and c.closing then rate = format(c.closing < 0 and " |cffff5555<<%.0f|r" or " |cff8a9492>>%.0f|r", abs(c.closing)) end
		local rt = ns.Comms.RangeText({ lo = lo, hi = hi, range = range, exact = ally and ally.exact })
		local count = nSpells > 0 and format("  |cff%s%d/%d|r", reach > 0 and "5cff8d" or "8a9492", reach, nSpells) or ""
		s.info:SetText(rt .. rate .. count)
	end

	-- tags: HVT, threat, targeting me
	local tags = {}
	if c and c.hvt then tags[#tags + 1] = "|cff5cff8dHVT|r" end
	if c then tags[#tags + 1] = format("THREAT %.0f", c.threat or 0) end
	if hostile and not isPlayer then tags[#tags + 1] = "NPC" end
	-- not attackable is not friendly: a dead enemy player cannot be attacked either
	-- (it said ALLY); a friend by the client's answer, else by faction
	if not hostile and isPlayer then
		local friend = read(UnitIsFriend, "player", "target")
		if friend == nil then
			local fac = read(UnitFactionGroup, "target")
			friend = fac ~= nil and fac == me.faction
		end
		if friend then tags[#tags + 1] = "|cff5cff8dALLY|r"
		elseif read(UnitIsDeadOrGhost, "target") then tags[#tags + 1] = "|cff8a9492DEAD|r" end
	end
	-- who else is on it
	if P.targetCounts then
		local al = TG.AlliesOn("target")
		if al > 0 then tags[#tags + 1] = format("|cff5cff8dALLIES %d|r", al) end
		if hostile then
			local eh = TG.EnemiesOn("target", true)
			if eh > 0 then tags[#tags + 1] = format("|cffffa040HEALERS %d|r", eh) end
		else
			local en = TG.EnemiesOn("target", false)
			if en > 0 then tags[#tags + 1] = format("|cffff5555TARGETED BY %d|r", en) end
		end
	end
	local line = table.concat(tags, "  ")
	-- keep the line short enough for the frame: the threat number goes first
	if #line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") > 34 and c then
		for i, t in ipairs(tags) do if t:find("^THREAT") then table.remove(tags, i) break end end
		line = table.concat(tags, "  ")
	end
	f.tags:SetText(line)

	-- intel: matchup verdict and what it can do to you
	if P.intel and hostile and isPlayer and class then
		f.intel:SetText(F.IntelText("target") or "")
		f.record:SetText(recordText(class))
	else
		f.intel:SetText("")
		f.record:SetText("")
	end

	-- whom it is targeting, and how healthy that one is
	local hasTot = read(UnitExists, "targettarget")
	if hasTot and ns.P.frames.totHealth then
		f.totHp:SetShown(feedBar(f.totHp, UnitHealth, UnitHealthMax, "targettarget"))
		if read(UnitIsDeadOrGhost, "targettarget") then
			f.totHp:SetStatusBarColor(0.4, 0.42, 0.42)
		elseif not curveColor(f.totHp, "targettarget") then
			local h, m = read(UnitHealth, "targettarget"), read(UnitHealthMax, "targettarget")
			if h and m and m > 0 then
				local fr = h / m
				local c = fr > 0.75 and HP_GREEN or fr >= 0.5 and HP_ORANGE or HP_RED
				f.totHp:SetStatusBarColor(c[1], c[2], c[3])
			end
		end
	else
		f.totHp:Hide()
	end
	if hasTot then
		local onMe = read(UnitIsUnit, "targettarget", "player")
		if onMe then
			f.tot:SetText(">> YOU")
			f.tot:SetTextColor(1, 0.33, 0.33)
		else
			-- players in their class colour with the class short; NPCs by reaction
			local _, tcls = read(UnitClass, "targettarget")
			local isP = read(UnitIsPlayer, "targettarget")
			local tag = isP and tcls and ns.Data.SHORT[tcls] and ("  |cff8a9492" .. ns.Data.SHORT[tcls] .. "|r") or ""
			local n = read(GetUnitName, "targettarget", false)
			if n then f.tot:SetText(">> " .. n .. tag)
			elseif not pcall(function() f.tot:SetFormattedText(">> %s%s", UnitName("targettarget"), tag) end) then f.tot:SetText("") end
			if isP and tcls then
				f.tot:SetTextColor(ns.Data.ClassColor(tcls))
			else
				local r = read(UnitReaction, "targettarget", "player")
				if r and r <= 3 then f.tot:SetTextColor(1, 0.28, 0.22)
				elseif r == 4 then f.tot:SetTextColor(1, 0.62, 0.15)
				elseif r then f.tot:SetTextColor(0.35, 0.92, 0.42)
				else f.tot:SetTextColor(unpack(C.text)) end
			end
		end
	else
		f.tot:SetText("")
	end
end

-- Glass: the pane (and its ring and flash edge) ends under the last row that has
-- something; the frame itself, a secure button, keeps its size (it may not change
-- in combat): a little below a short pane still targets. Rows top down, with the
-- pane's bottom under each: health and power, cast bar, combo pips, range strip,
-- intel line, its target (and the record).
local PANE = { base = 70, cast = 85, pips = 92, strip = 108, intel = 126, full = 142 }
F.PANE = PANE
local function fitPane(f)
	local h = PANE.base
	local exists = read(UnitExists, "target")
	if not exists then h = PANE.full
	else
		if f.cast:IsShown() then h = PANE.cast end
		if f.pips[1]:IsShown() then h = PANE.pips end
		if f.strip:IsShown() then h = PANE.strip end
		if (f.intel:GetText() or "") ~= "" then h = PANE.intel end
		if (f.tot:GetText() or "") ~= "" or (f.record:GetText() or "") ~= "" or f.totHp:IsShown() then h = PANE.full end
	end
	if f.paneH == h then return end
	f.paneH = h
	for _, r in ipairs({ K.Region(f.bg), f.border and f.border.box }) do
		if r then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
			r:SetHeight(h)
		end
	end
	f.flash:ClearAllPoints()
	f.flash:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -12)
	f.flash:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -(h - 12))
end
F.FitPane = fitPane

local function updateTarget()
	updateTargetBody()
	if target then fitPane(target) end
end
F.UpdateTarget = updateTarget

-- /sitrep tot: what the client reports for the target's-target bar, layer by layer.
function F.DumpTot()
	local f = target
	if not (f and f.totHp) then ns.print("tot: no target frame") return end
	local function rgba(t)
		if not t then return "none" end
		local ok, r, g, b, a = pcall(t.GetVertexColor, t)
		local okA, al = pcall(t.GetAlpha, t)
		if not ok then return "unreadable" end
		return format("rgb %.2f %.2f %.2f  vertex alpha %.2f  alpha %.2f  shown %s", plain(r) or -1, plain(g) or -1, plain(b) or -1,
			plain(a) or -1, okA and plain(al) or -1, tostring(t.IsShown and t:IsShown()))
	end
	local b = f.totHp
	ns.print("tot bar: shown %s, width %s, frame alpha %s", tostring(b:IsShown()), tostring(plain(b:GetWidth())), tostring(plain(b:GetAlpha())))
	ns.print("  background: %s", rgba(b.bg))
	ns.print("  green track: %s", rgba(b.track))
	ns.print("  end mark: %s", rgba(b.cap))
	ns.print("  health fill: %s", rgba(b:GetStatusBarTexture()))
	local ok, lo, hi = pcall(b.GetMinMaxValues, b)
	local okV, v = pcall(b.GetValue, b)
	ns.print("  values: %s / %s..%s", okV and tostring(plain(v) or "<secret>") or "?", ok and tostring(plain(lo) or "<secret>") or "?", ok and tostring(plain(hi) or "<secret>") or "?")
end

-- combat starts: the owner click emptied (it cannot change in combat; an old name
-- must not stay clickable for the next pet); after it, set again
ns.On("PLAYER_REGEN_DISABLED", function()
	if target and target.ownerButton then target.ownerButton:SetAttribute("macrotext1", "") end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if target then petTitle(target) end end)
ns.On("PLAYER_TARGET_CHANGED", function() if target then petTitle(target) end end)
