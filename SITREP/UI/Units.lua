-- SITREP · Units
-- Building blocks for anything that shows a unit (unit frames, nameplates):
-- bars and secret-safe texts, the cast bar with its KICK window, health
-- colours, and the highlight borders (being hit, something to dispel).
--
-- Everything that can be secret goes straight into a widget (status bars and
-- font strings accept secret values) inside pcall, and is never compared.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read, plain = ns.read, ns.plain
local format, min, max, floor = string.format, math.min, math.max, math.floor

local U = {}
ns.Units = U

local POWER_COLOR = {
	[0] = { 0.25, 0.55, 1.00 }, -- mana
	[1] = { 1.00, 0.25, 0.25 }, -- rage
	[2] = { 1.00, 0.55, 0.25 }, -- focus
	[3] = { 1.00, 0.88, 0.25 }, -- energy
}

-- The colour of a unit's power (or of power type t: 0 mana, 1 rage, 3 energy).
local function powerColor(unit, t)
	t = t or read(UnitPowerType, unit)
	local c = t and PowerBarColor and PowerBarColor[t]
	if c and c.r then return c.r, c.g, c.b end
	c = POWER_COLOR[t or 0] or POWER_COLOR[0]
	return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Secret-safe display helpers
---------------------------------------------------------------------------
-- Feed a bar straight from the client; works with secret values.
---------------------------------------------------------------------------
-- Glass: the health lost in the last moment stays lit behind the bar, then runs
-- down to it (GHOST_HOLD s, then GHOST_FALL s): a burst seen without reading a
-- number. Plain values only (with secret health there is no ghost).
---------------------------------------------------------------------------
local GHOST_HOLD, GHOST_FALL = 0.45, 0.45
local ghosts = {}
local ghostDriver = CreateFrame("Frame")
ghostDriver:Hide()
local function placeGhost(bar, frac)
	local w = bar:GetWidth()
	if not w or w <= 0 then bar.ghost:Hide() return end
	bar.ghost:SetWidth(math.max(0.01, w * frac))
	bar.ghost:Show()
end
-- A ghost behind a health bar; its colour (default coral: yours).
function U.Ghost(bar, r, g, b, a)
	local t = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
	t:SetTexture(K.WHITE)
	t:SetVertexColor(r or 1, g or 0.48, b or 0.42, a or 0.55)
	t:SetPoint("TOPLEFT")
	t:SetPoint("BOTTOMLEFT")
	t:Hide()
	bar.ghost = t
end
-- The bar's value now, as a share (plain, or nil when secret).
function U.FeedGhost(bar, frac, now)
	if not bar.ghost then return end
	if not frac then bar.ghostV, bar.ghostAt = nil, nil; bar.ghost:Hide(); ghosts[bar] = nil return end
	local g = bar.ghostV
	if not g or frac >= g then
		bar.ghostV, bar.ghostAt = frac, nil
		bar.ghost:Hide()
		ghosts[bar] = nil
		return
	end
	-- lower: the old value stays lit, then falls (a second drop meanwhile joins in)
	if not bar.ghostAt then bar.ghostAt, bar.ghostFrom = now or GetTime(), g end
	bar.ghostTo = frac
	placeGhost(bar, bar.ghostFrom)
	ghosts[bar] = true
	ghostDriver:Show()
end
function U.StepGhosts(now)
	local busy = false
	for bar in pairs(ghosts) do
		local t = now - bar.ghostAt
		if t >= GHOST_HOLD + GHOST_FALL then
			bar.ghostV, bar.ghostAt = bar.ghostTo, nil
			bar.ghost:Hide()
			ghosts[bar] = nil
		else
			local v = bar.ghostFrom
			if t > GHOST_HOLD then v = bar.ghostFrom + (bar.ghostTo - bar.ghostFrom) * (t - GHOST_HOLD) / GHOST_FALL end
			placeGhost(bar, v)
			busy = true
		end
	end
	return busy
end
ghostDriver:SetScript("OnUpdate", ns.Timed("units: ghost", function(self)
	if not U.StepGhosts(GetTime()) then self:Hide() end
end))

local function feedBar(bar, curFn, maxFn, unit)
	local ok = pcall(function()
		bar:SetMinMaxValues(0, maxFn(unit))
		bar:SetValue(curFn(unit))
	end)
	if bar.ghost then
		local c, m = read(curFn, unit), read(maxFn, unit)
		U.FeedGhost(bar, (c and m and m > 0) and c / m or nil)
	end
	return ok
end

-- Health as text: plain numbers are formatted here; secret ones are handed to
-- the client's own formatter and font string.
local function healthText(fs, unit)
	local h = read(UnitHealth, unit)
	if h then
		local abbrev = AbbreviateNumbers or AbbreviateLargeNumbers
		fs:SetText(abbrev and abbrev(h) or tostring(h))
		return true
	end
	if pcall(function() fs:SetText(AbbreviateNumbers(UnitHealth(unit))) end) then return true end
	if pcall(function() fs:SetText(UnitHealth(unit)) end) then return true end
	fs:SetText("")
	return false
end

local function percentText(fs, unit)
	local h, m = read(UnitHealth, unit), read(UnitHealthMax, unit)
	if h and m and m > 0 then fs:SetText(format("%.0f%%", h / m * 100)) return true end
	local scale = CurveConstants and CurveConstants.ScaleTo100
	if scale and pcall(function() fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, scale)) end) then return true end
	fs:SetText("")
	return false
end

local function nameText(fs, unit)
	local n = read(GetUnitName, unit, false)
	if n then fs:SetText(n) return end
	if not pcall(function() fs:SetText(UnitName(unit)) end) then fs:SetText("?") end
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
local function newBar(parent, h, layer)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture(K.WHITE)
	b:SetHeight(h)
	b.bg = K.Tex(b, "BACKGROUND", C.raised)
	b.bg:SetAllPoints()
	if layer then b:SetFrameLevel(parent:GetFrameLevel() + layer) end
	return b
end

-- Cast bar under `above`: client-timed through a duration object when the cast
-- is secret; for enemies a bright last quarter with KICK (see U.PaintCast).
local function castBar(f, above, h)
	f.cast = newBar(f, h, 2)
	f.cast:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -3)
	f.cast:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -3)
	f.cast:SetStatusBarColor(1, 0.72, 0.2, 0.95)
	f.castText = K.Font(f.cast, 10, C.text, K.FONT, "OUTLINE")
	f.castText:SetPoint("LEFT", 4, 0)
	f.castGlow = CreateFrame("Frame", nil, f.cast)
	f.castGlow:SetPoint("TOPLEFT", -1, 1)
	f.castGlow:SetPoint("BOTTOMRIGHT", 1, -1)
	K.Border(f.castGlow, { 1, 0.95, 0.6, 1 }, 1, 4)
	f.castKick = K.Font(f.cast, 10, { 1, 1, 1, 1 }, K.FONT, "OUTLINE")
	f.castKick:SetPoint("RIGHT", -4, 0)
	f.castKick:SetText("KICK")
	f.castGlow:Hide(); f.castKick:Hide()
	f.cast:Hide()
	-- plain start/end times animate here when the client gives them
	-- the bar moves every frame; its colour (amber, KICK, grey) only needs checking
	-- 20 times a second
	f.castUpdate = ns.Timed("cast bars", function(self)
		if not self.cast:IsShown() then return end
		local t = GetTime()
		if self.castEnd and not self.castTimed then
			self.cast:SetMinMaxValues(self.castStart, self.castEnd)
			self.cast:SetValue(min(t * 1000, self.castEnd))
		end
		-- (plain progress: 20 times a second; the client's colour curve, which hands
		-- back a new table each time: 10)
		if t - (self.castPaintAt or 0) >= (self.castEnd and 0.05 or 0.1) then
			self.castPaintAt = t
			U.PaintCast(self)
		end
	end)
	f:SetScript("OnUpdate", f.castUpdate)
end

-- Hairline ticks over a bar at the given fractions.
local function ticks(bar, fracs, alpha)
	local t = {}
	for i, f in ipairs(fracs) do
		local tx = K.Tex(bar, "OVERLAY", { 0, 0, 0, alpha or 0.55 })
		tx:SetWidth(1)
		tx:SetPoint("TOP"); tx:SetPoint("BOTTOM")
		tx.frac = f
		t[i] = tx
	end
	function t.Layout(w)
		for _, tx in ipairs(t) do
			tx:ClearAllPoints()
			tx:SetPoint("TOPLEFT", bar, "TOPLEFT", floor(w * tx.frac), 0)
			tx:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", floor(w * tx.frac), 0)
		end
	end
	return t
end

---------------------------------------------------------------------------
-- Highlights around a frame (player and party members):
--   red      while it is being attacked: lit on every hit or miss against it,
--            fading out 1.5 s after the last one;
--   coloured while it carries a debuff you can dispel, in that debuff's colour
--            (blue magic, purple curse, green poison, brown disease), pulsing.
---------------------------------------------------------------------------
local fxFrames = {}
local fx = CreateFrame("Frame")
fx:SetScript("OnUpdate", ns.Timed("units: fx (fx)", function()
	local now = GetTime()
	local pulse = 0.65 + 0.35 * math.sin(now * 5)
	for _, f in ipairs(fxFrames) do
		K.FadeHit(f, now)
		if f.disp:IsShown() then f.disp:SetAlpha(pulse) end
		if f.rest and f.rest:IsShown() then f.rest:SetAlpha(0.55 + 0.45 * math.sin(now * 1.6)) end
	end
end))

local function addHighlights(f)
	f.hit = CreateFrame("Frame", nil, f)
	f.hit:SetPoint("TOPLEFT", -3, 3)
	f.hit:SetPoint("BOTTOMRIGHT", 3, -3)
	f.hit:SetFrameLevel(f:GetFrameLevel() + 6)
	K.Border(f.hit, { 1, 0.22, 0.18, 1 }, 2)
	f.hit:SetAlpha(0)
	f.disp = CreateFrame("Frame", nil, f)
	f.disp:SetPoint("TOPLEFT", -1, 1)
	f.disp:SetPoint("BOTTOMRIGHT", 1, -1)
	f.disp:SetFrameLevel(f:GetFrameLevel() + 7)
	K.Border(f.disp, { 1, 1, 1, 1 }, 2)
	f.disp:Hide()
	fxFrames[#fxFrames + 1] = f
end

-- Someone swung at it (hit or not).
local function attacked(f)
	if not (f and f.hit and ns.P.frames.hitGlow) then return end
	f.hitAt = GetTime()
	f.hit:SetAlpha(1)
end

-- Border in the colour of a debuff you can dispel on this unit (see Auras.Removable).
function U.PaintDispel(f, unit)
	if not (f and f.disp) then return end
	if not (ns.P.frames.dispelGlow and ns.Auras and read(UnitExists, unit)) then f.disp:Hide() return end
	local kind, a, b = ns.Auras.Removable(unit)
	-- (plain: known to be something to dispel; client: only the client knows)
	f.disp.plain = kind == "plain"
	if kind == "plain" then
		f.disp.border:SetColor(a[1], a[2], a[3], 1)
		f.disp:Show()
	elseif kind == "client" then
		-- locked in combat: the client colours it (transparent when not dispellable)
		local ok = true
		for i = 1, 4 do ok = ns.Auras.ClientColor(f.disp.border[i], unit, a, b) and ok end
		f.disp:SetShown(ok)
	else
		f.disp:Hide()
	end
end

-- Health colours: green above 75 %, orange from 50 to 75 %, red below 50 %.
-- The client's colour curve can evaluate secret health itself; if that path is
-- not available, SITREP's plain estimate decides.
local HP_GREEN, HP_ORANGE, HP_RED = { 0.32, 0.90, 0.48 }, { 1.00, 0.62, 0.15 }, { 1.00, 0.30, 0.30 }
U.HP_COLORS = { green = HP_GREEN, orange = HP_ORANGE, red = HP_RED }
local hpCurve
local function curveColor(bar, unit)
	if hpCurve == nil then
		hpCurve = false
		local CU = C_CurveUtil
		local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
		if CU and CU.CreateColorCurve and step and CreateColor and UnitHealthPercent then
			pcall(function()
				local c = CU.CreateColorCurve()
				c:SetType(step)
				c:AddPoint(0, CreateColor(HP_RED[1], HP_RED[2], HP_RED[3]))
				c:AddPoint(0.5, CreateColor(HP_ORANGE[1], HP_ORANGE[2], HP_ORANGE[3]))
				c:AddPoint(0.75, CreateColor(HP_GREEN[1], HP_GREEN[2], HP_GREEN[3]))
				-- the same steps on a 0-100 scale (which one the client uses is not
				-- measured; see Plates' SCALE_BOTH)
				c:AddPoint(1.0001, CreateColor(HP_RED[1], HP_RED[2], HP_RED[3]))
				c:AddPoint(50, CreateColor(HP_ORANGE[1], HP_ORANGE[2], HP_ORANGE[3]))
				c:AddPoint(75, CreateColor(HP_GREEN[1], HP_GREEN[2], HP_GREEN[3]))
				hpCurve = c
			end)
		end
	end
	if not hpCurve then return false end
	return pcall(function() bar:SetStatusBarColor(UnitHealthPercent(unit, true, hpCurve):GetRGB()) end)
end

local CAST_NORMAL = { 1.00, 0.72, 0.20, 0.95 }
local CAST_HOT = { 1.00, 0.93, 0.45, 1.00 }
local CAST_LOCKED = { 0.55, 0.58, 0.60, 0.50 } -- cannot be interrupted
local KICK_AT = 0.75
local CAST_OWN = { 0.45, 0.75, 1.00, 0.95 }
U.CAST = { normal = CAST_NORMAL, hot = CAST_HOT, locked = CAST_LOCKED }

-- How far through its cast the target is (0..1), or nil when that is secret.
local function castProgress(f)
	if f.castEnd and f.castStart and f.castEnd > f.castStart then
		return min(1, max(0, (GetTime() * 1000 - f.castStart) / (f.castEnd - f.castStart)))
	end
	local d = f.castDur
	if d then
		local ok, p = pcall(function() return d:GetElapsedPercent() end)
		p = ok and plain(p)
		if type(p) == "number" then return p end
		local ok1, el = pcall(function() return d:GetElapsedDuration() end)
		local ok2, tot = pcall(function() return d:GetTotalDuration() end)
		el, tot = ok1 and plain(el), ok2 and plain(tot)
		if type(el) == "number" and type(tot) == "number" and tot > 0 then return el / tot end
	end
	return nil
end
U.CastProgress = castProgress

local function setCastColor(f, c) f.cast:SetStatusBarColor(c[1], c[2], c[3], c[4]) end

-- Colour the cast bar: grey when it cannot be interrupted, bright with KICK in its
-- last quarter. Secret answers are left to the client to colour.
-- (no closures, no new colours per call: this runs 10-20 times a second per cast
-- bar; the colours the client hands back are new tables, so the secret paths are
-- asked as seldom as they can be)
local lockedColor, normalColor
local function paintSecretInt(f)
	if not lockedColor then
		lockedColor = CreateColor(CAST_LOCKED[1], CAST_LOCKED[2], CAST_LOCKED[3], CAST_LOCKED[4])
		normalColor = CreateColor(CAST_NORMAL[1], CAST_NORMAL[2], CAST_NORMAL[3], CAST_NORMAL[4])
	end
	local c = C_CurveUtil.EvaluateColorFromBoolean(f.castNotIntRaw, lockedColor, normalColor)
	f.cast:SetStatusBarColor(c:GetRGBA())
end
local function paintCurve(f)
	f.cast:SetStatusBarColor(f.castDur:EvaluateElapsedPercent(f.castCurve):GetRGBA())
end

function U.PaintCast(f)
	local hot = false
	if f.ownCast then
		setCastColor(f, CAST_OWN) -- your own pet: progress only, nothing to kick
	elseif f.castNotInt == true then
		setCastColor(f, CAST_LOCKED)
	elseif f.castNotInt == nil and f.castNotIntRaw ~= nil then
		-- interruptibility secret: the client picks grey or amber from it (once per
		-- cast: it does not change while the cast lasts; a new cast clears castIntPainted)
		if not f.castIntPainted then
			local painted = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and CreateColor and pcall(paintSecretInt, f)
			if not painted then setCastColor(f, CAST_NORMAL) end
			f.castIntPainted = true
		end
	else
		local p = castProgress(f)
		if p then
			hot = p >= KICK_AT
			setCastColor(f, hot and CAST_HOT or CAST_NORMAL)
		elseif not (f.castDur and f.castDur.EvaluateElapsedPercent and f.castCurve and pcall(paintCurve, f)) then
			setCastColor(f, CAST_NORMAL) -- progress secret and no client curve: plain amber
		end
	end
	f.castHot = hot
	f.castGlow:SetShown(hot)
	f.castKick:SetShown(hot)
end

-- Client-side "last quarter" colour for casts whose progress is secret.
local function castCurve()
	local CU = C_CurveUtil
	if not (CU and CU.CreateColorCurve and CreateColor) then return nil end
	local ok, c = pcall(function()
		local curve = CU.CreateColorCurve()
		local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
		if step then curve:SetType(step) end
		curve:AddPoint(0, CreateColor(CAST_NORMAL[1], CAST_NORMAL[2], CAST_NORMAL[3], CAST_NORMAL[4]))
		curve:AddPoint(KICK_AT, CreateColor(CAST_HOT[1], CAST_HOT[2], CAST_HOT[3], CAST_HOT[4]))
		return curve
	end)
	return ok and c or nil
end

local function updateCast(f, unit)
	local castDur = read(UnitCastingDuration, unit)
	local chanDur = not castDur and read(UnitChannelDuration, unit) or nil
	local dur = castDur or chanDur
	local casting = ns.present(UnitCastingInfo, unit) or ns.present(UnitChannelInfo, unit)
	if not casting then f.cast:Hide(); f.castEnd, f.castDur = nil, nil return end
	local isChannel = not ns.present(UnitCastingInfo, unit)
	local info = isChannel and UnitChannelInfo or UnitCastingInfo
	-- name of the spell (may be secret: the font string shows it anyway)
	if not pcall(function() f.castText:SetText((info(unit))) end) then f.castText:SetText("CASTING") end
	-- start, end and "not interruptible" (8th return for casts, 7th for channels)
	local ok, _, _, _, startMS, endMS, _, r7, r8 = pcall(info, unit)
	local notInt
	-- no "x and a or b" here: that tests a, and a secret boolean cannot be tested
	if ok then
		if isChannel then notInt = r7 else notInt = r8 end
	end
	f.castStart, f.castEnd = ok and plain(startMS) or nil, ok and plain(endMS) or nil
	if ns.isSecret(notInt) then f.castNotInt, f.castNotIntRaw = nil, notInt
	else f.castNotInt, f.castNotIntRaw = notInt and true or false, nil end
	f.castDur = dur
	f.castCurve = f.castCurve or castCurve()
	f.castTimed = dur and f.cast.SetTimerDuration and pcall(f.cast.SetTimerDuration, f.cast, dur) or false
	if not f.castTimed and not f.castEnd then
		f.cast:SetMinMaxValues(0, 1); f.cast:SetValue(1) -- secret and untimed: a solid "casting" bar
	end
	f.cast:Show()
	f.castIntPainted = nil
	U.PaintCast(f)
end

-- 1234 -> "1.2k", 12500 -> "13k", 2500000 -> "2.5m"
local function shortNum(v)
	if v >= 1e6 then return format("%.1fm", v / 1e6) end
	if v >= 1e4 then return format("%.0fk", v / 1e3) end
	if v >= 1e3 then return format("%.1fk", v / 1e3) end
	return format("%d", floor(v + 0.5))
end

U.PowerColor = powerColor
U.FeedBar, U.HealthText, U.PercentText, U.NameText = feedBar, healthText, percentText, nameText
U.NewBar, U.CastBar, U.Ticks = newBar, castBar, ticks
U.AddHighlights, U.Attacked = addHighlights, attacked
U.CurveColor = curveColor
U.UpdateCast = updateCast
U.ShortNum = shortNum
