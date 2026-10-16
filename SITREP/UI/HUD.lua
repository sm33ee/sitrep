-- SITREP · HUD
-- Movable modules and an alert layer (envelope, threat board and allies: HUDContacts.lua):
--   ENVELOPE  every contact on a range tape: its distance bracket, the zone it can
--             hit you from, your own weapon ranges, closure rate, time to reach
--   CONTACTS  threat board, most dangerous first, with range and tags
--   ENGAGE    Lanchester tug-of-war bar, force ratio, P(win), the call
--   PRESSURE  incoming DPS, shadow health, time-to-live, 10 s sparkline

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local max = math.max
local format = string.format

local H = {}
ns.HUD = H
H.modules = {}
H.hidden = false

local function classColor(class) return ns.Data.ClassColor(class) end

local function sound(kit)
	if not (ns.P.alerts.sound and PlaySound and SOUNDKIT) then return end
	local id = SOUNDKIT[kit]
	if id then pcall(PlaySound, id, "Master") end
end

local function shortNum(v)
	if not v then return "-" end
	if v >= 10000 then return format("%.0fk", v / 1000) end
	if v >= 1000 then return format("%.1fk", v / 1000) end
	return format("%.0f", v)
end
H.shortNum = shortNum
H.Sound, H.ClassColor = sound, classColor

local function moduleFrame(id, w, h, title, default)
	local f = K.Panel(UIParent, w, h, { name = "SITREP_" .. id, bracketLen = 9, mood = true })
	f:SetFrameStrata("MEDIUM")
	K.Movable(f, id, default)
	f.title = K.Font(f, 10, C.dim, K.FONT, "")
	f.title:SetPoint("TOPLEFT", 8, -6)
	f.title:SetText(title)
	f.status = K.Font(f, 10, C.dim, K.FONT, "")
	f.status:SetPoint("TOPRIGHT", -8, -6)
	-- "drag me" overlay while unlocked
	f.unlock = K.Tex(f, "OVERLAY", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	f.unlockText = K.Font(f, 10, C.dim, K.FONT, "")
	f.unlockText:SetPoint("BOTTOMRIGHT", -6, 4)
	f.unlockText:SetText("DRAG")
	H.modules[id] = f
	return f
end
H.ModuleFrame = moduleFrame

---------------------------------------------------------------------------
-- ENGAGE
---------------------------------------------------------------------------
local engage

local function buildEngage()
	local f = moduleFrame("engage", 300, 92, "ENGAGEMENT", { "BOTTOMRIGHT", "BOTTOMRIGHT", -250, 110 })
	engage = f
	f.advice = K.Font(f, 26, C.text, K.FONT, "")
	f.advice:SetPoint("TOPLEFT", 10, -20)
	f.ratio = K.Font(f, 12, C.text, K.FONT, "")
	f.ratio:SetPoint("TOPRIGHT", -10, -22)
	f.pwin = K.Font(f, 12, C.text, K.FONT, "")
	f.pwin:SetPoint("TOPRIGHT", f.ratio, "BOTTOMRIGHT", 0, -3)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(8)
	bar:SetPoint("BOTTOMLEFT", 10, 22)
	bar:SetPoint("BOTTOMRIGHT", -10, 22)
	f.bar = bar
	f.friend = K.Tex(bar, "ARTWORK")
	f.friend:SetPoint("TOPLEFT"); f.friend:SetPoint("BOTTOMLEFT")
	f.foe = K.Tex(bar, "ARTWORK", { 1, 0.3, 0.3, 0.85 })
	f.foe:SetPoint("TOPRIGHT"); f.foe:SetPoint("BOTTOMRIGHT")
	K.Paint(function(r, g, b) f.friend:SetVertexColor(r, g, b, 0.9) end)
	f.ticks = {}
	for i = 1, 3 do
		local t = K.Tex(bar, "OVERLAY", { 1, 1, 1, 0.55 })
		t:SetSize(1, 14)
		f.ticks[i] = t
	end
	f.mid = K.Tex(bar, "OVERLAY", { 0, 0, 0, 0.9 })
	f.mid:SetSize(2, 12)
	f.mid:SetPoint("CENTER")
	f.forces = K.Font(f, 10, C.dim, K.FONT, "")
	f.forces:SetPoint("BOTTOMLEFT", 10, 7)
	f.losses = K.Font(f, 10, C.dim, K.FONT, "")
	f.losses:SetPoint("BOTTOMRIGHT", -10, 7)
end

local function updateEngage(pic)
	local f = engage
	if not (f and f:IsShown()) then return end
	local a = ns.Data.ADVICE[pic.advice] or ns.Data.ADVICE.CLEAR
	f.advice:SetText(a.text)
	f.advice:SetTextColor(a[1], a[2], a[3])
	local w = f.bar:GetWidth()
	if w <= 0 then w = 280 end
	local share = (pic.pF + pic.pH) > 0 and pic.pF / (pic.pF + pic.pH) or 1
	f.friend:SetWidth(max(1, w * share))
	f.foe:SetWidth(max(1, w * (1 - share)))
	f.foe:SetShown(pic.nH >= 0.05)
	local E = ns.P.engage
	for i, at in ipairs({ E.holdAt, E.contestAt, E.engageAt }) do
		f.ticks[i]:ClearAllPoints()
		f.ticks[i]:SetPoint("CENTER", f.bar, "LEFT", w * at / (1 + at), 0)
	end
	if pic.rho then
		f.ratio:SetText(format("RATIO  %.2f : 1", pic.rho))
		f.pwin:SetText(format("P(WIN)  %.0f%%", pic.pwin * 100))
		f.losses:SetText(format("EXP. LOSSES  %.1f", pic.losses))
	else
		f.ratio:SetText("RATIO  -")
		f.pwin:SetText("P(WIN)  -")
		f.losses:SetText("")
	end
	f.forces:SetText(format("FRIENDLY %d   HOSTILE %.1f", pic.nF, pic.nH))
	if pic.duel then
		f.status:SetText(format("DUEL  k %.2f  n %d", ns.P.duel.k, ns.P.duel.n or 0))
		f.status:SetTextColor(K.Accent())
	else
		f.status:SetText(format("k %.2f  n %d", E.k, E.n or 0))
		f.status:SetTextColor(unpack(C.dim))
	end
end

---------------------------------------------------------------------------
-- PRESSURE
---------------------------------------------------------------------------
local pressure

local function buildPressure()
	local f = moduleFrame("pressure", 300, 84, "INCOMING PRESSURE", { "BOTTOMRIGHT", "BOTTOMRIGHT", -250, 20 })
	pressure = f
	f.dps = K.Font(f, 22, C.text, K.FONT, "")
	f.dps:SetPoint("TOPLEFT", 10, -20)
	f.unit = K.Font(f, 10, C.dim, K.FONT, "")
	f.unit:SetPoint("BOTTOMLEFT", f.dps, "BOTTOMRIGHT", 4, 3)
	f.unit:SetText("DPS IN")
	f.ttl = K.Font(f, 12, C.text, K.FONT, "")
	f.ttl:SetPoint("TOPRIGHT", -10, -22)
	f.hps = K.Font(f, 10, C.dim, K.FONT, "")
	f.hps:SetPoint("TOPRIGHT", f.ttl, "BOTTOMRIGHT", 0, -3)
	-- sparkline
	f.spark = {}
	local sw = 280 / 20
	for i = 1, 20 do
		local t = K.Tex(f, "ARTWORK")
		t:SetWidth(sw - 2)
		t:SetPoint("BOTTOMLEFT", 10 + (i - 1) * sw, 18)
		f.spark[i] = t
	end
	K.Paint(function(r, g, b) for i, t in ipairs(f.spark) do t:SetVertexColor(r, g, b, 0.25 + 0.6 * i / 20) end end)
	f.hpBack = K.Tex(f, "ARTWORK", C.raised)
	f.hpBack:SetHeight(4)
	f.hpBack:SetPoint("BOTTOMLEFT", 10, 8)
	f.hpBack:SetPoint("BOTTOMRIGHT", -10, 8)
	f.hpFill = K.Tex(f, "OVERLAY", { 0.35, 0.95, 0.5, 0.9 })
	f.hpFill:SetHeight(4)
	f.hpFill:SetPoint("BOTTOMLEFT", 10, 8)
end

local function updatePressure()
	local f = pressure
	if not (f and f:IsShown()) then return end
	local R, P = ns.Pressure, ns.P.pressure
	f.dps:SetText(shortNum(R.dpsShort or 0))
	-- orange / red when the damage rate would empty your health fast
	local lvl = R.Level(R.dpsShort)
	local lc = R.LEVEL_COLOR[lvl]
	if lc then f.dps:SetTextColor(lc[1], lc[2], lc[3]) else f.dps:SetTextColor(unpack(C.text)) end
	f.level = lvl
	f.hps:SetText(format("HEAL IN %s   OUT %s", shortNum(R.hps or 0), shortNum(R.outDps or 0)))
	if R.ttl and R.ttl < 60 then
		f.ttl:SetText(format("TTL  %.1fs", R.ttl))
		if R.ttl < P.ttlWarn then f.ttl:SetTextColor(1, 0.3, 0.3) else f.ttl:SetTextColor(unpack(C.text)) end
	else
		f.ttl:SetText("TTL  --")
		f.ttl:SetTextColor(unpack(C.dim))
	end
	local peak = 1
	for i = 1, 20 do peak = max(peak, R.spark[i] or 0) end
	local ar, ag, ab = K.Accent()
	for i = 1, 20 do
		local bar = f.spark[i]
		bar:SetHeight(max(1, 24 * (R.spark[i] or 0) / peak))
		-- each bar covers 0.5 s: its damage x 2 is that moment's damage per second
		local c = R.LEVEL_COLOR[R.Level((R.spark[i] or 0) * 2)]
		if c then bar:SetVertexColor(c[1], c[2], c[3], 0.95)
		else bar:SetVertexColor(ar, ag, ab, 0.25 + 0.6 * i / 20) end
	end
	local frac = R.HealthFrac()
	f.hpFill:SetWidth(max(1, (f:GetWidth() - 20) * frac))
	if frac < 0.35 then f.hpFill:SetVertexColor(1, 0.3, 0.3, 0.95) else f.hpFill:SetVertexColor(0.35, 0.95, 0.5, 0.9) end
	f.status:SetText(R.synced and "HP LIVE" or format("HP EST %.0f%%", frac * 100))
end

---------------------------------------------------------------------------
-- Alerts: banner, screen-edge flash, after-action card
---------------------------------------------------------------------------
H.BANNER_RADIUS = 12 -- the banner pane's corners (glass)
local banner, flash, aar

local function buildAlerts()
	banner = CreateFrame("Frame", "SITREP_Banner", UIParent)
	banner:SetSize(600, 40)
	banner:SetFrameStrata("HIGH")
	-- movable like the HUD (Layout: "Alert banner"); unlocked, a sample to place
	K.Movable(banner, "banner", { "TOP", "TOP", 0, -170 })
	banner:RestorePosition()
	banner.bg = K.Backdrop(banner, { 0, 0, 0, 0.55 }, H.BANNER_RADIUS)
	banner.bg:SetPoint("TOPLEFT", 60, 0); banner.bg:SetPoint("BOTTOMRIGHT", -60, 0)
	-- the coloured line under it; in glass it stops where the corners start to round
	-- (placed when shown: the skin may change after this is built)
	banner.edge = K.Tex(banner, "ARTWORK")
	banner.edge:SetHeight(1)
	banner.text = K.Font(banner, 18, C.text, K.FONT, "OUTLINE")
	banner.text:SetPoint("CENTER")
	banner:Hide()
	banner:SetScript("OnUpdate", ns.Timed("hud (banner)", function(self)
		if self.placing then return end
		local t = GetTime() - self.shown
		if t > 2.6 then self:Hide() return end
		self:SetAlpha((self.base or 1) * (t < 2 and 1 or 1 - (t - 2) / 0.6))
	end))

	flash = CreateFrame("Frame", nil, UIParent)
	flash:SetAllPoints(UIParent)
	flash:SetFrameStrata("BACKGROUND")
	flash.edges = {}
	for _, s in ipairs({ { "TOPLEFT", "TOPRIGHT", "VERTICAL", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", "VERTICAL", false },
		{ "TOPLEFT", "BOTTOMLEFT", "HORIZONTAL", false }, { "TOPRIGHT", "BOTTOMRIGHT", "HORIZONTAL", true } }) do
		local t = flash:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(K.WHITE)
		t:SetPoint(s[1]); t:SetPoint(s[2])
		if s[3] == "VERTICAL" then t:SetHeight(90) else t:SetWidth(90) end
		t.dir, t.flip = s[3], s[4]
		flash.edges[#flash.edges + 1] = t
	end
	flash:Hide()
	flash:SetScript("OnUpdate", ns.Timed("hud (flash)", function(self)
		local t = GetTime() - self.shown
		if t > 0.9 then self:Hide() return end
		self:SetAlpha(1 - t / 0.9)
	end))

	aar = K.Panel(UIParent, 300, 74, { name = "SITREP_AAR" })
	aar:SetFrameStrata("MEDIUM")
	aar:Hide()
	aar.title = K.Font(aar, 10, C.dim, K.FONT, "")
	aar.title:SetPoint("TOPLEFT", 8, -6)
	aar.outcome = K.Font(aar, 18, C.text, K.FONT, "")
	aar.outcome:SetPoint("TOPLEFT", 8, -20)
	aar.line1 = K.Font(aar, 11, C.text, K.FONT, "")
	aar.line1:SetPoint("TOPLEFT", 8, -44)
	aar.line2 = K.Font(aar, 10, C.dim, K.FONT, "")
	aar.line2:SetPoint("TOPLEFT", 8, -58)
	aar.line3 = K.Font(aar, 10, { 0.72, 0.66, 1, 1 }, K.FONT, "")
	aar.line3:SetPoint("TOPLEFT", 8, -72)
	aar:SetScript("OnUpdate", ns.Timed("hud (aar)", function(self)
		local t = GetTime() - self.shown
		if t > 9 then self:Hide() return end
		self:SetAlpha(t < 8 and 1 or 1 - (t - 8))
	end))
end

function H.Banner(text, r, g, b)
	if not (banner and ns.P.alerts.banner) then return end
	banner.text:SetText(text)
	banner.text:SetTextColor(r or 1, g or 1, b or 1)
	banner.edge:SetVertexColor(r or 1, g or 1, b or 1, 0.9)
	local inset = H.BANNER_RADIUS
	banner.edge:ClearAllPoints()
	banner.edge:SetPoint("BOTTOMLEFT", K.Region(banner.bg), "BOTTOMLEFT", inset, 0)
	banner.edge:SetPoint("BOTTOMRIGHT", K.Region(banner.bg), "BOTTOMRIGHT", -inset, 0)
	banner.edge:SetAlpha(1)
	banner.shown = GetTime()
	banner:SetAlpha(banner.base or 1)
	banner:Show()
end

-- Its size, opacity, background and place; while the HUD is unlocked a sample shows
-- to drag (the real alerts take over again when locked).
function H.ApplyBanner()
	if not banner then return end
	local P = ns.P.hud
	banner:SetScale(P.scale * (P.frameScale.banner or 1))
	banner.base = K.Opacity("banner")
	K.Background(banner.bg, "banner")
	banner:RestorePosition()
	if not P.locked and ns.P.enabled then
		banner.placing = true
		H.Banner("Alert banner  ·  drag to move", K.Accent())
		banner.placing = true
		banner:Show()
	elseif banner.placing then
		banner.placing = false
		banner:Hide()
	end
end

function H.Flash(r, g, b)
	if not (flash and ns.P.alerts.flash) then return end
	for _, t in ipairs(flash.edges) do
		local c0, c1 = CreateColor and CreateColor(r, g, b, 0.55), CreateColor and CreateColor(r, g, b, 0)
		if c0 and t.SetGradient then
			if t.flip then t:SetGradient(t.dir, c1, c0) else t:SetGradient(t.dir, c0, c1) end
		else
			t:SetVertexColor(r, g, b, 0.3)
		end
	end
	flash.shown = GetTime()
	flash:SetAlpha(1)
	flash:Show()
end

function H.ShowAAR(r)
	if not (aar and ns.P.log.aarPopup) then return end
	local col = r.outcome == "WIN" and { K.Accent() } or r.outcome == "LOSS" and { 1, 0.33, 0.33 } or { 1, 0.72, 0.2 }
	if r.kind == "duel" then
		aar.title:SetText(format("DUEL  ·  vs %s", r.opponent or "?"))
		aar.outcome:SetText(format("DUEL %s  %.0fs", r.outcome, r.dur or 0))
	else
		aar.title:SetText(format("AFTER ACTION  ·  %s", (r.sub ~= "" and r.sub) or r.zone or ""))
		aar.outcome:SetText(format("%s  %.0fs", r.outcome, r.dur or 0))
	end
	aar.outcome:SetTextColor(col[1], col[2], col[3])
	local comp = {}
	for cl, n in pairs(r.comp or {}) do comp[#comp + 1] = (n > 1 and n .. " " or "") .. (ns.Data.NAME[cl] or cl) end
	aar.line1:SetText("vs " .. (#comp > 0 and table.concat(comp, ", ") or "unknown"))
	aar.line2:SetText(format("predicted %s   taken %s   peak %s dps   HK %d",
		r.p and format("%.0f%%", r.p * 100) or "-", shortNum(r.dmg), shortNum(r.peak), r.hk or 0))
	local kicks = ns.Incoming and ns.Incoming.KickLine(r.kicks)
	aar.line3:SetText(kicks or "")
	aar:SetHeight(kicks and 88 or 74)
	aar:ClearAllPoints()
	if engage and engage:IsShown() then aar:SetPoint("BOTTOM", engage, "TOP", 0, 8) else aar:SetPoint("CENTER", 0, -160) end
	aar.shown = GetTime()
	aar:SetAlpha(1)
	aar:Show()
end

---------------------------------------------------------------------------
-- Alert rules
---------------------------------------------------------------------------
local lastNew, newBurst = 0, 0
-- "45s", "4m", "2h10m": how long something has been around.
function H.Since(sec)
	if sec < 60 then return format("%ds", sec) end
	if sec < 3600 then return format("%dm", math.floor(sec / 60)) end
	return format("%dh%02dm", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

-- Another copy of this zone (Sensors.LayerScan): a short line, once.
ns.On("SR_LAYER", function(_, new, old)
	if not (ns.P.alerts.layer and ns.P.enabled) then return end
	H.Banner(format("NEW LAYER  ·  %s", tostring(new)), 0.6, 0.85, 1)
	sound("RAID_WARNING")
end)

-- An enemy went into stealth close to you (Sensors.StealthCheck): AoE now. If it
-- was further off than your AoE reaches, a second warning when it could be in it
-- (moving in stealth at up to STEALTH_SPEED yd/s), unless it shows up again.
local AOE, STEALTH_SPEED = 10, 6
ns.On("SR_STEALTH", function(_, c, yards)
	if not (ns.P.alerts.stealth and ns.P.enabled) then return end
	local who = format("%s %s", (ns.Data.NAME[c.class] or ""):upper(), c.name or "")
	H.Banner(format("STEALTH  ·  %s  ·  %d YD  ·  AOE!", who, yards or 0), 0.75, 0.45, 1)
	H.Flash(0.75, 0.45, 1)
	sound("RAID_WARNING")
	if yards and yards > AOE then
		local gone = GetTime()
		C_Timer.After((yards - AOE) / STEALTH_SPEED, function()
			if c.lastLive and c.lastLive > gone then return end
			H.Banner(format("%s COULD BE ON YOU  ·  AOE!", who), 0.75, 0.45, 1)
			sound("RAID_WARNING")
		end)
	end
end)

-- An enemy found healing (Targeting: heals that land as its cast ends).
ns.On("SR_HEALER", function(_, key, c)
	if not (ns.P.alerts.healer and ns.P.enabled) then return end
	H.Banner(format("HEALER  ·  %s %s", (c and ns.Data.NAME[c.class] or ""):upper(), c and c.name or ""), 0.36, 1, 0.55)
end)

-- A rare NPC on a plate (UI/Plates.lua): banner, a pale flash and a sound, once per
-- rare in RARE_AGAIN seconds (it may wander off its plate and back).
local RARE_AGAIN = 300
local rareSeen = {}
function H.RareSeen(unit, key, name, level)
	if not (ns.P.alerts.rare and ns.P.enabled) then return end
	local read = ns.read
	key = key or (unit and read(GetUnitName, unit, false)) or unit
	if not key then return end
	local now = GetTime()
	if rareSeen[key] and now - rareSeen[key] < RARE_AGAIN then return end
	rareSeen[key] = now
	name = name or (unit and read(GetUnitName, unit, false))
	level = level or (unit and read(UnitLevel, unit))
	local age = unit and ns.Sensors.SpawnAge(read(UnitGUID, unit))
	H.Banner(format("RARE  ·  %s%s%s", name or "?", level and level > 0 and format(" (%d)", level) or "",
		age and ("  ·  UP " .. H.Since(age)) or ""), 0.78, 0.82, 1)
	H.Flash(0.78, 0.82, 1)
	sound("RAID_WARNING")
end

ns.On("SR_NEW_CONTACT", function(_, c)
	if not (ns.P.alerts.newContact and banner) or ns.hudHidden then return end
	local now = GetTime()
	if now - lastNew < 1.5 then
		newBurst = newBurst + 1
		H.Banner(format("%d NEW CONTACTS", newBurst + 1), 1, 0.85, 0.3)
	else
		newBurst = 0
		local r, g, b = classColor(c.class)
		local rt = (c.lo or c.hi or c.range) and ns.Comms.RangeText(c)
		H.Banner(format("CONTACT  ·  %s %s%s", (ns.Data.NAME[c.class] or "HOSTILE"):upper(),
			c.level and (c.level > 0 and c.level or "??") or "",
			rt and ("  ·  " .. rt) or ""), r, g, b)
		sound("MAP_PING")
	end
	lastNew = now
end)

ns.On("SR_HVT", function(_, c)
	if not ns.P.alerts.hvt then return end
	H.Banner(format("HVT  ·  %s %s", (ns.Data.NAME[c.class] or ""):upper(), c.name or ""), K.Accent())
	sound("RAID_WARNING")
end)

ns.On("SR_TARGETED", function(_, c)
	if not ns.P.alerts.targeted then return end
	H.Banner(format("TARGETED BY %s %s", (ns.Data.NAME[c.class] or "HOSTILE"):upper(), c.name or ""), 1, 0.3, 0.3)
	H.Flash(1, 0.2, 0.2)
	sound("TELL_MESSAGE")
end)

ns.On("SR_SPIKE", function(_, pct)
	if not ns.P.alerts.spike then return end
	H.Banner(format("SPIKE  -%.0f%% IN 1.5s", pct), 1, 0.3, 0.55)
	H.Flash(1, 0.15, 0.4)
	sound("ALARM_CLOCK_WARNING_3")
end)

ns.On("SR_CLOSING", function(_, c)
	if not ns.P.alerts.closing then return end
	H.Banner(format("%s CLOSING  ·  IN REACH IN %.1fs", (ns.Data.NAME[c.class] or "HOSTILE"):upper(), c.ttr or 0), 1, 0.72, 0.2)
	sound("RAID_WARNING")
end)

ns.On("SR_ADVICE", function(_, advice)
	if advice == "DEFEND" and ns.P.alerts.ttl then
		local a = ns.Data.ADVICE.DEFEND
		H.Banner("DEFEND  ·  TIME TO LIVE " .. format("%.1fs", ns.Pressure.ttl or 0), a[1], a[2], a[3])
	elseif advice == "BREAK" and ns.Sensors.self.combat then
		local a = ns.Data.ADVICE.BREAK
		H.Banner("BREAK CONTACT  ·  OUTNUMBERED", a[1], a[2], a[3])
	end
end)

ns.On("SR_AAR", function(_, r) H.ShowAAR(r) end)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local pendingApply, pendingRebuild
function H.Apply()
	local P = ns.P.hud
	H.ApplyBanner()
	local show = { envelope = P.envelope, board = P.board, engage = P.engage, pressure = P.pressure, allies = P.allies }
	for id, f in pairs(H.modules) do
		-- board and allies hold secure click buttons: they may only change out of combat
		if (id == "board" or id == "allies") and InCombatLockdown() then pendingApply = true else
		f:SetScale(P.scale * (P.frameScale[id] or 1))
		K.Background(f.bg, id)
		f.baseAlpha = P.alpha * K.Opacity(id)
		f:SetAlpha(H.Faded(id) and 0 or f.baseAlpha)
		f:RestorePosition()
		f:SetShown(show[id] and not ns.hudHidden and ns.P.enabled)
		f:EnableMouse(not P.locked)
		f.unlock:SetShown(not P.locked)
		f.unlockText:SetShown(not P.locked)
		end
	end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if pendingRebuild then local w = pendingRebuild; pendingRebuild = false; H.Rebuild(w) end
	if pendingApply then pendingApply = false; H.Apply() end
end)

---------------------------------------------------------------------------
-- Auto-hide: a module set to "only with enemy players around" fades out while
-- the picture holds no enemy player. It stays visible while you place things
-- (HUD unlocked or console open). Fading uses alpha only, which is allowed in
-- combat even for frames that hold secure buttons.
---------------------------------------------------------------------------
function H.EnemiesAround()
	for _, c in ipairs(ns.Model.byThreat) do
		if not c.npc then return true end
	end
	return false
end

function H.Faded(id)
	local P = ns.P.hud
	if not P.locked or (ns.Config and ns.Config.IsOpen()) then return false end
	-- the allies panel stays out of sight while there is nobody to show
	if id == "allies" and ns.Allies and #ns.Allies.list == 0 then return true end
	if not (P.autoHide and P.autoHide[id]) then return false end
	return not H.EnemiesAround()
end

local fader = CreateFrame("Frame")
local function fadeTo(f, want, k)
	local a = f:GetAlpha()
	if math.abs(a - want) > 0.01 then f:SetAlpha(a + (want - a) * k) elseif a ~= want then f:SetAlpha(want) end
end
-- The wanted alphas are worked out on each tick (and when a setting changes); the
-- fader runs per frame only while some panel is still on its way there. (Close
-- enough is there: the client keeps an alpha in 1/255 steps, so GetAlpha does not
-- hand back exactly what was set.)
local want = {}
local function wantAlphas()
	if not ns.P then return end
	local busy = false
	for id, f in pairs(H.modules) do
		local a = H.Faded(id) and 0 or ns.P.hud.alpha * K.Opacity(id)
		want[f] = a
		if math.abs(f:GetAlpha() - a) > 0.01 then busy = true end
	end
	local pf = ns.Frames and ns.Frames.frames.player
	if pf then
		local a = H.Faded("player") and 0 or K.Opacity("player")
		want[pf] = a
		if math.abs(pf:GetAlpha() - a) > 0.01 then busy = true end
	end
	if busy then fader:Show() end
end
H.WantAlphas = wantAlphas
fader:SetScript("OnUpdate", ns.Timed("hud (fader)", function(self, elapsed)
	local k = math.min(1, elapsed * 8)
	local busy = false
	for f, a in pairs(want) do
		fadeTo(f, a, k)
		if math.abs(f:GetAlpha() - a) > 0.01 then busy = true end
	end
	if not busy then self:Hide() end
end))
ns.On("SR_TICK", wantAlphas)
ns.On("SR_CONFIG", wantAlphas)
-- a faded player frame must not catch clicks (only changeable out of combat)
ns.On("SR_PICTURE", function()
	local pf = ns.Frames and ns.Frames.frames.player
	if pf and not InCombatLockdown() then pf:EnableMouse(not H.Faded("player")) end
end)

function H.Toggle()
	ns.hudHidden = not ns.hudHidden
	H.Apply()
	ns.print("HUD %s.", ns.hudHidden and "hidden" or "shown")
end

function H.Build()
	H.BuildEnvelope()
	H.BuildBoard()
	H.BuildAllies()
	buildEngage()
	buildPressure()
	buildAlerts()
	H.Apply()
end

function H.Rebuild(which)
	-- Size-dependent modules are rebuilt from scratch; frames are recycled by hiding.
	if (which == "board" or which == "allies") and InCombatLockdown() then pendingRebuild = which return end
	local f = H.modules[which]
	if f then f:Hide(); H.modules[which] = nil end
	if which == "envelope" then H.BuildEnvelope() elseif which == "board" then H.BuildBoard() elseif which == "allies" then H.BuildAllies() end
	H.Apply()
end

ns.On("SR_LOGIN", function() H.Build() end)

ns.On("SR_ALLIES", function(_, list)
	if ns.hudHidden then return end
	H.UpdateAllies(list)
end)

ns.On("SR_PICTURE", function(_, list, pic)
	if ns.hudHidden then return end
	H.UpdateEnvelope(list)
	H.UpdateBoard(list)
	updateEngage(pic)
	updatePressure()
end)

ns.On("SR_CONFIG", function(_, key)
	if not H.modules.envelope then return end
	if key == "hud.envelopeLanes" then H.Rebuild("envelope")
	elseif key == "hud.boardRows" then H.Rebuild("board")
	elseif key == "hud.alliesRows" then H.Rebuild("allies")
	else H.Apply() end
end)
