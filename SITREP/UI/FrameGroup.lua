-- SITREP · Pet and party frames

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format
local F = ns.Frames
local U = ns.Units
local TG = ns.Targeting
local newBar, castBar, ticks = U.NewBar, U.CastBar, U.Ticks
local feedBar, healthText, percentText, nameText = U.FeedBar, U.HealthText, U.PercentText, U.NameText
local powerColor, curveColor, updateCast = U.PowerColor, U.CurveColor, U.UpdateCast
local addHighlights = U.AddHighlights
local HP_GREEN, HP_ORANGE, HP_RED = U.HP_COLORS.green, U.HP_COLORS.orange, U.HP_COLORS.red
local frameShell = F.Shell

---------------------------------------------------------------------------
-- PETS: your own pet ("pet") and your target's pet ("targetpet"), each shown
-- only while it exists. Health with incoming heals, power, cast bar, what it
-- is attacking (click to target that). The target's pet also shows its
-- distance, and an enemy pet's cast gets the KICK treatment.
---------------------------------------------------------------------------
local pet, tpet -- the frames (also F.pet, F.tpet)

local function buildPetFrame(id, unit, title, default)
	local P = ns.P.frames
	local W = P.width
	local f = frameShell(id, unit, title, default)
	f:SetHeight(76)
	f.petUnit = unit
	f.petTarget = unit .. "target" -- "pettarget", "targetpettarget"

	f.name = K.Font(f, 12, C.text)
	f.name:SetPoint("TOPLEFT", 8, -18)
	f.name:SetPoint("RIGHT", f, "RIGHT", -70, 0)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false)
	f.level = K.Font(f, 10, C.dim, K.FONT, "")
	f.level:SetPoint("TOPRIGHT", -8, -19)

	f.hp = newBar(f, 14, 1)
	f.hp:SetPoint("TOPLEFT", 8, -34)
	f.hp:SetPoint("TOPRIGHT", -8, -34)
	ns.Heals.Attach(f.hp)
	f.hpTicks = ticks(f.hp, { 0.25, 0.5, 0.75 })
	f.hpText = K.Font(f.hp, 11, C.text, K.FONT, "OUTLINE")
	f.hpText:SetPoint("LEFT", 6, 0)
	f.pctText = K.Font(f.hp, 11, C.text, K.FONT, "OUTLINE")
	f.pctText:SetPoint("RIGHT", -6, 0)

	f.power = newBar(f, 4, 1)
	f.power:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -2)
	f.power:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -2)

	castBar(f, f.power, 10)

	-- what it is attacking; click to target that (fixed unit token: works in combat)
	f.ptt = K.Font(f, 10.5, C.text, K.FONT, "")
	f.ptt:SetPoint("BOTTOMLEFT", 8, 6)
	f.dist = K.Font(f, 10.5, C.dim, K.FONT, "")
	f.dist:SetPoint("BOTTOMRIGHT", -8, 6)
	local tb = CreateFrame("Button", "SITREP_" .. id .. "TargetButton", f, "SecureUnitButtonTemplate")
	tb:SetPoint("BOTTOMLEFT", 4, 2)
	tb:SetSize(170, 16)
	tb:SetFrameLevel(f:GetFrameLevel() + 5)
	tb:SetAttribute("unit", f.petTarget)
	tb:SetAttribute("type1", "target")
	tb:SetAttribute("type2", "togglemenu")
	tb:RegisterForClicks("AnyUp")
	tb.hl = K.Tex(tb, "BACKGROUND", { 1, 1, 1, 0.07 })
	tb.hl:SetAllPoints()
	tb.hl:Hide()
	tb:HookScript("OnEnter", function(self)
		-- (attacking nothing: nothing to click, nothing lights up)
		if read(UnitExists, f.petTarget) ~= true then return end
		self.hl:Show()
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
			GameTooltip:SetText("Click to target what this pet attacks", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	tb:HookScript("OnLeave", function(self) self.hl:Hide(); if GameTooltip then GameTooltip:Hide() end end)
	f.pttButton = tb

	f.hpTicks.Layout(W - 16)
	K.Paint(function(r, g, b) f.title:SetTextColor(r, g, b) end)
	return f
end

local function buildPet()
	pet = buildPetFrame("pet", "pet", "PET", { "CENTER", "CENTER", -260, -282 })
	tpet = buildPetFrame("targetpet", "targetpet", "TARGET'S PET", { "CENTER", "CENTER", 260, -302 })
	F.pet, F.tpet = pet, tpet
end
F.BuildPet = buildPet

-- Pet health colour: green, orange below 50 %, red below 25 % (plain only;
-- secret health keeps the last colour).
local function petHealthColor(bar, unit)
	local h, m = read(UnitHealth, unit), read(UnitHealthMax, unit)
	if not (h and m and m > 0) then return end
	local p = h / m
	if p >= 0.5 then bar:SetStatusBarColor(0.30, 0.85, 0.40)
	elseif p >= 0.25 then bar:SetStatusBarColor(1, 0.62, 0.15)
	else bar:SetStatusBarColor(1, 0.28, 0.22) end
end
F.PetHealthColor = petHealthColor

-- Players in class colour, NPCs by their reaction to you.
local function unitColor(fs, unit)
	local _, cls = read(UnitClass, unit)
	if read(UnitIsPlayer, unit) and cls then fs:SetTextColor(ns.Data.ClassColor(cls)) return end
	local r = read(UnitReaction, unit, "player")
	if r and r <= 3 then fs:SetTextColor(1, 0.28, 0.22)
	elseif r == 4 then fs:SetTextColor(1, 0.62, 0.15)
	elseif r then fs:SetTextColor(0.35, 0.92, 0.42)
	else fs:SetTextColor(unpack(C.text)) end
end

local function updatePetFrame(f)
	if not f then return end
	local unit = f.petUnit
	if not read(UnitExists, unit) then
		ns.Heals.Feed(f.hp, nil)
		f.cast:Hide()
		if not f:IsShown() then return end
		f.name:SetText("NO PET"); f.name:SetTextColor(unpack(C.faint)) -- placeholder while you place it
		f.level:SetText(""); f.tags:SetText(""); f.ptt:SetText(""); f.dist:SetText(""); f.hpText:SetText(""); f.pctText:SetText("")
		return
	end
	local own = unit == "pet"
	local hostile = not own and ns.Sensors.IsEnemy(unit)
	nameText(f.name, unit)
	if own then f.name:SetTextColor(unpack(C.text)) else unitColor(f.name, unit) end
	-- family ("Wolf", "Voidwalker") and level when it differs from yours
	local fam = read(UnitCreatureFamily, unit) or read(UnitCreatureType, unit)
	local lvl, myLvl = read(UnitLevel, unit), ns.Sensors.self.level
	local lv = lvl and myLvl and lvl ~= myLvl and tostring(lvl) or ""
	f.level:SetText(fam and (lv ~= "" and (fam .. "  " .. lv) or fam) or lv)

	feedBar(f.hp, UnitHealth, UnitHealthMax, unit)
	petHealthColor(f.hp, unit)
	ns.Heals.Feed(f.hp, unit)
	healthText(f.hpText, unit)
	percentText(f.pctText, unit)
	feedBar(f.power, UnitPower, UnitPowerMax, unit)
	f.power:SetStatusBarColor(powerColor(unit))
	-- your own or a friendly pet's cast: progress only; an enemy pet's: KICK
	f.ownCast = not hostile
	updateCast(f, unit)

	local tags = {}
	if read(UnitIsDeadOrGhost, unit) then tags[#tags + 1] = "|cffff5555DEAD|r"
	elseif read(UnitAffectingCombat, unit) then tags[#tags + 1] = "|cffff5555COMBAT|r" end
	f.tags:SetText(table.concat(tags, "  "))

	-- distance to the target's pet: harmful spells for an enemy pet, helpful for a friendly one
	if own then
		f.dist:SetText("")
	else
		local S = ns.Sensors
		local lo, hi = S.MeasureRange(unit, nil, not hostile and S.helpChecks or nil)
		f.dist:SetText((lo or hi) and ns.Comms.RangeText({ lo = lo, hi = hi, range = S.RangeEstimate(lo, hi) }) or "")
	end

	-- what it attacks
	local pt = f.petTarget
	if read(UnitExists, pt) then
		if read(UnitIsUnit, pt, "player") then
			f.ptt:SetText(">> YOU"); f.ptt:SetTextColor(1, 0.33, 0.33)
		else
			local n = read(GetUnitName, pt, false)
			if n then f.ptt:SetText(">> " .. n)
			elseif not pcall(function() f.ptt:SetFormattedText(">> %s", UnitName(pt)) end) then f.ptt:SetText("") end
			unitColor(f.ptt, pt)
		end
	else
		f.ptt:SetText("")
	end
end
local function updatePet() updatePetFrame(pet) end
local function updateTargetPet() updatePetFrame(tpet) end
F.UpdatePet, F.UpdateTargetPet = updatePet, updateTargetPet

---------------------------------------------------------------------------
-- PARTY: one frame per party member, stacked under a PARTY header. Shown only
-- in a group, each member only while it exists. Health (green / orange / red)
-- with incoming heals, power, cast bar, distance coloured by your heal range
-- (the whole frame fades when out of it), DEAD / OFFLINE, TARGETED BY n when
-- enemies target them, and debuffs with the ones you can remove first and
-- outlined (built by Auras.lua). Click to target, right-click for the menu.
---------------------------------------------------------------------------
local party
local MEMBER_H, MEMBER_GAP = 72, 7 -- room between members for the highlight borders
F.partyMembers = {}

local function buildParty()
	local P = ns.P.frames
	local W = P.width
	local c = CreateFrame("Frame", "SITREP_partyFrame", UIParent)
	c:SetSize(W, 16)
	c:SetFrameStrata("MEDIUM")
	c:EnableMouse(true) -- the header is the drag handle
	K.Movable(c, "party", { "TOPLEFT", "TOPLEFT", 40, -240 })
	c.title = K.Font(c, 10, C.dim, K.FONT, "")
	c.title:SetPoint("BOTTOMLEFT", 2, 3)
	c.title:SetText("PARTY")
	c.status = K.Font(c, 10, C.dim, K.FONT, "")
	c.status:SetPoint("BOTTOMRIGHT", -2, 3)
	c.unlock = K.Tex(c, "OVERLAY", { 1, 1, 1, 0.04 })
	c.unlock:SetAllPoints()
	K.Paint(function(r, g, b) c.title:SetTextColor(r, g, b) end)
	party = c
	F.party = c

	for i = 1, 4 do
		local unit = "party" .. i
		local f = CreateFrame("Button", "SITREP_party" .. i .. "Frame", c, "SecureUnitButtonTemplate")
		f:SetSize(W, MEMBER_H)
		f:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -(i - 1) * (MEMBER_H + MEMBER_GAP) - 3)
		f.bg = K.Backdrop(f, C.bg, 8, { mood = true })
		f.bg:SetAllPoints()
		K.Border(f, C.line)
		K.Brackets(f, 7, 2)
		f:SetAttribute("unit", unit)
		f:SetAttribute("type1", "target")
		f:SetAttribute("type2", "togglemenu")
		f:RegisterForClicks("AnyUp")
		f.unit, f.index = unit, i
		-- the mouse on a member's frame: its plate drawn as your target's
		f:HookScript("OnEnter", function(self) if ns.Plates then ns.Plates.Highlight(self.unit) end end)
		f:HookScript("OnLeave", function() if ns.Plates then ns.Plates.Highlight(nil) end end)
		-- what you can dispel on them: orbs right of the frame (Units.PaintOrbs)
		f.orbs = ns.Units.Orbs(f, 3, 9, function(o, j) o:SetPoint("LEFT", f, "RIGHT", 5 + (j - 1) * (9 + 5), 0) end)
		-- hit / heal flash and the class edge share the left side
		f.flash = K.Tex(f, "OVERLAY")
		f.flash:SetPoint("TOPLEFT"); f.flash:SetPoint("BOTTOMLEFT")
		f.flash:SetWidth(3)
		f.flash:SetAlpha(0)
		f.edge = K.Tex(f, "ARTWORK")
		f.edge:SetPoint("TOPLEFT"); f.edge:SetPoint("BOTTOMLEFT")
		f.edge:SetWidth(2)

		f.name = K.Font(f, 12, C.text)
		f.name:SetPoint("TOPLEFT", 8, -5)
		f.name:SetPoint("RIGHT", f, "RIGHT", -120, 0)
		f.name:SetJustifyH("LEFT")
		f.name:SetWordWrap(false)
		f.dist = K.Font(f, 11, C.text, K.FONT, "")
		f.dist:SetPoint("TOPRIGHT", -8, -6)
		f.tags = K.Font(f, 9.5, C.dim, K.FONT, "")
		f.tags:SetPoint("RIGHT", f.dist, "LEFT", -8, 0)

		f.hp = newBar(f, 14, 1)
		f.hp:SetPoint("TOPLEFT", 8, -20)
		f.hp:SetPoint("TOPRIGHT", -8, -20)
		ns.Heals.Attach(f.hp)
		f.hpTicks = ticks(f.hp, { 0.25, 0.5, 0.75 })
		f.hpText = K.Font(f.hp, 11, C.text, K.FONT, "OUTLINE")
		f.hpText:SetPoint("LEFT", 6, 0)
		f.pctText = K.Font(f.hp, 11, C.text, K.FONT, "OUTLINE")
		f.pctText:SetPoint("RIGHT", -6, 0)

		f.power = newBar(f, 3, 1)
		f.power:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -2)
		f.power:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -2)

		castBar(f, f.power, 6)
		f.ownCast = true -- a friend's cast: progress only
		addHighlights(f)

		f.hpTicks.Layout(W - 16)
		F.partyMembers[i] = f
	end
end
F.BuildParty = buildParty

-- Health colour like your own: green above 75 %, orange from 50 %, red below.
local function memberHealthColor(bar, unit)
	if curveColor(bar, unit) then return end
	local h, m = read(UnitHealth, unit), read(UnitHealthMax, unit)
	if not (h and m and m > 0) then return end
	local frac = h / m
	local c = frac > 0.75 and HP_GREEN or frac >= 0.5 and HP_ORANGE or HP_RED
	bar:SetStatusBarColor(c[1], c[2], c[3])
end

local HEAL_RANGE_COLOR = { [true] = { 0.35, 0.92, 0.42 }, [false] = { 1, 0.3, 0.25 } }

local function updateMember(f)
	local unit = f.unit
	if not read(UnitExists, unit) then
		ns.Heals.Feed(f.hp, nil)
		f.cast:Hide()
		if f:IsShown() then -- placeholder while you place the frames
			f.name:SetText("PARTY " .. f.index); f.name:SetTextColor(unpack(C.faint))
			f.dist:SetText(""); f.tags:SetText(""); f.hpText:SetText(""); f.pctText:SetText("")
			f.edge:SetVertexColor(unpack(C.faint))
			f:SetAlpha(1)
		end
		return
	end
	local _, cls = read(UnitClass, unit)
	local online = read(UnitIsConnected, unit) ~= false
	local dead = read(UnitIsDeadOrGhost, unit)
	nameText(f.name, unit)
	if cls then
		local r, g, b = ns.Data.ClassColor(cls)
		f.name:SetTextColor(r, g, b); f.edge:SetVertexColor(r, g, b)
	else
		f.name:SetTextColor(unpack(C.text)); f.edge:SetVertexColor(unpack(C.dim))
	end

	feedBar(f.hp, UnitHealth, UnitHealthMax, unit)
	if dead or not online then f.hp:SetStatusBarColor(0.4, 0.42, 0.42) else memberHealthColor(f.hp, unit) end
	ns.Heals.Feed(f.hp, online and not dead and unit or nil)
	healthText(f.hpText, unit)
	percentText(f.pctText, unit)
	feedBar(f.power, UnitPower, UnitPowerMax, unit)
	f.power:SetStatusBarColor(powerColor(unit))
	updateCast(f, unit)

	-- distance (exact from the client's positions for group members) and heal range
	local a = ns.Allies and ns.Allies.ForUnit(unit)
	if a and (a.range or a.lo or a.hi) then
		f.dist:SetText(ns.Comms.RangeText(a))
		local hc = HEAL_RANGE_COLOR[a.inHeal] or { 1, 0.65, 0.15 }
		f.dist:SetTextColor(hc[1], hc[2], hc[3])
	else
		f.dist:SetText("")
	end

	local tags = {}
	if not online then tags[#tags + 1] = "OFFLINE"
	elseif dead then tags[#tags + 1] = read(UnitIsGhost, unit) and "GHOST" or "|cffff5555DEAD|r" end
	local tb = TG.TargetedBy(unit)
	if tb > 0 then tags[#tags + 1] = format("|cffff5555TARGETED BY %d|r", tb) end
	-- how well geared: its health against its class and level (Sensors: toughness)
	if online and not dead then
		local ratio, z = ns.Sensors.Tough(unit, read(UnitGUID, unit))
		if ratio then
			local _, r, g, b = ns.Sensors.ToughLabel(z)
			r, g, b = r or 0.55, g or 0.6, b or 0.58
			tags[#tags + 1] = format("|cff%02x%02x%02xHP %+.0f%%|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), (ratio - 1) * 100)
		end
	end
	f.tags:SetText(table.concat(tags, "  "))

	-- out of your heal range or offline: faded (alpha is allowed in combat)
	f:SetAlpha((not online and 0.45) or (a and a.inHeal == false and 0.55) or 1)
end
F.UpdateMember = updateMember

local function updateParty()
	if not party then return end
	local inRange, n = 0, 0
	for _, f in ipairs(F.partyMembers) do
		updateMember(f)
		if read(UnitExists, f.unit) then
			n = n + 1
			local a = ns.Allies and ns.Allies.ForUnit(f.unit)
			if a and a.inHeal then inRange = inRange + 1 end
		end
	end
	party.status:SetText(n > 0 and format("%d/%d IN HEAL RANGE", inRange, n) or "")
end
F.UpdateParty = updateParty

local function partyMember(unit)
	local i = type(unit) == "string" and tonumber(unit:match("^party(%d)$"))
	return i and F.partyMembers[i] or nil
end
F.PartyMember = partyMember
