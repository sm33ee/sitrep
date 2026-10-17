-- SITREP · Casts on you, shown (logic: Incoming.lua)
--   the caster's plate:  a bold red box round the whole plate (name, bar, cast
--                         bar), pulsing, with a faint red fill and ON YOU beside
--                         it; drawn above other plates and never dimmed with the
--                         plate. Also when "is its target me" is secret: the
--                         client decides the box's alpha from its own answer.
--                         To target the caster, click its plate (in combat the
--                         game lets no addon choose what a click targets).
--   a flash message:      "Grimmzahn casts Schattenblitz on you!" above the middle
--                         of the screen, for any hostile caster that is not your
--                         target (mobs too), at most every 1.5 s per caster; 2 s,
--                         then it fades. A sound for enemy players. Movable, and on
--                         the Layout page (castAlert). alerts.incoming.
--   your focus casting:   the same line for an enemy focus (not your target) that
--                         starts a cast, the name in magenta (K.FOCUS) and "kick!"
--                         when it can be interrupted. alerts.focusCast. A cast of
--                         your focus on you: the line above, its name in magenta.
-- Nothing here is anchored outside the plate: plates are restricted regions on
-- Forever (an outside frame anchored to one errors).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local I = ns.Incoming
local format = string.format

local UI = {}
ns.IncomingUI = UI

local RED = { 1, 0.25, 0.2 }
local GAP = 7           -- how far the box stands off the plate
local ALERT_EVERY = 1.5 -- seconds per caster
local HOLD, FADE = 2, 0.5
local lastBanner = {}   -- [caster] = when its last alert showed
UI.lastBanner = lastBanner

---------------------------------------------------------------------------
-- The caster's plate
---------------------------------------------------------------------------
local function marker(s)
	if s.inc then return s.inc end
	local m = CreateFrame("Frame", nil, s)
	m:SetPoint("TOPLEFT", s, "TOPLEFT", -GAP, GAP + 14) -- (the name line above the bar)
	m:SetPoint("BOTTOMRIGHT", s.cast, "BOTTOMRIGHT", GAP, -GAP)
	m:SetFrameStrata("HIGH") -- above other plates
	if m.SetIgnoreParentAlpha then pcall(m.SetIgnoreParentAlpha, m, true) end -- (the client dims plates)
	-- the box: its own frame, so its pulse multiplies with m's alpha (which may
	-- come from a secret answer)
	m.box = CreateFrame("Frame", nil, m)
	m.box:SetAllPoints()
	m.box.fill = K.Tex(m.box, "BACKGROUND", { RED[1], RED[2], RED[3], 0.12 })
	m.box.fill:SetAllPoints()
	K.Border(m.box, { RED[1], RED[2], RED[3], 1 }, 3)
	m.text = K.Font(m.box, 11, { RED[1], RED[2], RED[3], 1 }, K.FONT, "OUTLINE")
	m.text:SetPoint("LEFT", m, "RIGHT", 4, 0)
	m.text:SetText("ON YOU")
	m:SetScript("OnUpdate", ns.Timed("casts (m)", function(self)
		self.box:SetAlpha(0.55 + 0.45 * math.abs(math.sin(GetTime() * 5)))
	end))
	m:Hide()
	s.inc = m
	return m
end
UI.Marker = marker

function UI.Plates()
	local on = ns.P.plates.incoming and ns.P.plates.enabled and ns.P.enabled
	for unit, s in pairs(ns.Plates.Current()) do
		local c = on and I.casts[unit] or nil
		if not c then
			if s.inc then s.inc:Hide() end
		else
			local m = marker(s)
			m:Show()
			if c.onMe == true then
				m:SetAlpha(1)
			else
				-- secret: the client picks the alpha from its own answer
				local painted = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and CreateColor and pcall(function()
					local col = C_CurveUtil.EvaluateColorFromBoolean(c.raw, CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
					local _, _, _, a = col:GetRGBA()
					m:SetAlpha(a)
				end)
				if not painted then m:Hide() end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The flash message: "X casts Y on you!" for a caster that is not your target
---------------------------------------------------------------------------
local function hex(r, g, b) return format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end

local function buildAlert()
	if UI.alert then return UI.alert end
	local f = CreateFrame("Frame", "SITREP_CastAlert", UIParent)
	f:SetSize(420, 30)
	f:SetFrameStrata("HIGH")
	-- the spell in the middle; who before it, "on you!" after it (the spell's name
	-- may be a secret value: a font string of its own, never joined with text)
	f.spell = K.Font(f, 16, C.text, nil, "OUTLINE")
	f.spell:SetPoint("CENTER", 0, 0)
	f.who = K.Font(f, 16, C.text, nil, "OUTLINE")
	f.who:SetPoint("RIGHT", f.spell, "LEFT", -6, 0)
	f.tail = K.Font(f, 16, { RED[1], RED[2], RED[3], 1 }, K.FONT, "OUTLINE")
	f.tail:SetPoint("LEFT", f.spell, "RIGHT", 6, 0)
	f.tail:SetText("on you!")
	-- a dark band behind the line
	f.bg = K.Backdrop(f, { C.bg[1], C.bg[2], C.bg[3], 0.55 }, 12)
	f.bg:ClearAllPoints()
	f.bg:SetPoint("TOP", 0, 0)
	f.bg:SetPoint("BOTTOM", 0, 0)
	f.bg:SetPoint("LEFT", f.who, "LEFT", -14, 0)
	f.bg:SetPoint("RIGHT", f.tail, "RIGHT", 14, 0)
	f.edge = K.Tex(f, "BORDER", { RED[1], RED[2], RED[3], 0.9 })
	f.edge:SetHeight(2)
	f.edge:SetPoint("BOTTOMLEFT", K.Region(f.bg), "BOTTOMLEFT")
	f.edge:SetPoint("BOTTOMRIGHT", K.Region(f.bg), "BOTTOMRIGHT")
	f.edge:SetAlpha(0) -- (the pane says it, no line under it)
	f.unlock = K.Tex(f, "OVERLAY", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	f:SetScript("OnUpdate", ns.Timed("casts (f)", function(self)
		if self.placing then self:SetAlpha(K.Opacity("castAlert")) return end
		local t = GetTime() - (self.shown or 0)
		if t > HOLD + FADE then self:Hide() return end
		self:SetAlpha(K.Opacity("castAlert") * (t < HOLD and 1 or 1 - (t - HOLD) / FADE))
	end))
	K.Movable(f, "castAlert", { "TOP", "TOP", 0, -170 })
	f:Hide()
	UI.alert = f
	return f
end

-- The line "who casts spell on you!" centred as a whole in the frame (the spell sits
-- in the middle of it; a secret spell name cannot be measured: then as it is).
local function centre(f)
	local okW, ww = pcall(f.who.GetStringWidth, f.who)
	local okT, tw = pcall(f.tail.GetStringWidth, f.tail)
	local x = 0
	if okW and okT and type(ww) == "number" and type(tw) == "number" and not ns.isSecret(ww) and not ns.isSecret(tw) then x = (ww - tw) / 2 end
	f.spell:ClearAllPoints()
	f.spell:SetPoint("CENTER", x, 0)
end
UI.CentreAlert = centre

-- Show it for one cast (c.focus: your focus's; c.tail: the words after the spell).
function UI.Alert(c)
	local f = buildAlert()
	local r, g, b = RED[1], RED[2], RED[3]
	if c.player then r, g, b = ns.Data.ClassColor(c.class) end
	if c.focus then r, g, b = K.FOCUS[1], K.FOCUS[2], K.FOCUS[3] end
	f.who:SetText("|cff" .. hex(r, g, b) .. (c.caster or "Someone") .. "|r casts")
	local tc = c.focus and c.tail and K.FOCUS or RED
	f.tail:SetTextColor(tc[1], tc[2], tc[3], 1)
	f.tail:SetText(c.tail or "on you!")
	f.spell:SetText(c.name) -- (as the client gave it)
	centre(f)
	f.shown = GetTime()
	f.placing = false
	f:SetAlpha(K.Opacity("castAlert"))
	f:Show()
end

-- Size, opacity, background and place (Layout page); shown while placing it.
function UI.ApplyAlert()
	local f = buildAlert()
	local H = ns.P.hud
	f:SetScale(H.scale * (H.frameScale.castAlert or 1))
	K.Background(f.bg, "castAlert")
	f:RestorePosition()
	f.unlock:SetShown(not H.locked)
	f:EnableMouse(not H.locked)
	if not H.locked and ns.P.alerts.incoming and ns.P.enabled then
		f.placing = true
		f.who:SetText("|cffff3f33Grimmzahn|r casts")
		f.spell:SetText("Schattenblitz")
		centre(f)
		f:Show()
	elseif f.placing then
		f.placing = false
		f:Hide()
	end
end

ns.On("SR_INCOMING", function(_, c)
	if not (ns.P.alerts.incoming and ns.P.enabled) or c.isTarget then return end
	-- (your focus: its name in magenta)
	if c.unit and ns.read(UnitIsUnit, c.unit, "focus") == true then c.focus = true end
	local key = c.caster or c.unit
	local now = GetTime()
	if lastBanner[key] and now - lastBanner[key] < ALERT_EVERY then return end
	lastBanner[key] = now
	UI.Alert(c)
	if c.player then ns.HUD.Sound("RAID_WARNING") end
end)

-- Your focus starts a cast: the line, when it is an enemy and not your target (that
-- one's cast is on the target frame). At you: the line above says it already.
function UI.FocusCast(unit)
	if unit ~= "focus" or not (ns.P.alerts.focusCast and ns.P.enabled) then return end
	local read = ns.read
	if read(UnitExists, "focus") ~= true or read(UnitIsUnit, "focus", "target") == true then return end
	if not ns.Sensors.IsEnemy("focus") or read(UnitIsUnit, "focustarget", "player") == true then return end
	local now = GetTime()
	if lastBanner.focus and now - lastBanner.focus < ALERT_EVERY then return end
	lastBanner.focus = now
	local channel = not ns.present(UnitCastingInfo, "focus")
	local info = channel and UnitChannelInfo or UnitCastingInfo
	local ok, spell, _, _, _, _, _, r7, r8 = pcall(info, "focus")
	if not ok or spell == nil then return end
	local notInt
	if channel then notInt = r7 else notInt = r8 end
	local _, cls = read(UnitClass, "focus")
	UI.Alert({ focus = true, player = read(UnitIsPlayer, "focus") == true, class = cls,
		caster = read(GetUnitName, "focus", false) or "Your focus", name = spell,
		-- (interruptible for certain: kick!; not, or secret: nothing after the spell)
		tail = (not ns.isSecret(notInt) and notInt == false) and "kick!" or "" })
	if read(UnitIsPlayer, "focus") == true then ns.HUD.Sound("RAID_WARNING") end
end
ns.On("UNIT_SPELLCAST_START", function(_, unit) UI.FocusCast(unit) end)
ns.On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit) UI.FocusCast(unit) end)

ns.On("SR_LOGIN", function() UI.Plates(); UI.ApplyAlert() end)
ns.On("SR_INCOMING_CHANGED", function() UI.Plates() end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 7) == "plates." then UI.Plates() end
	if key == "*" or key == "enabled" or key:sub(1, 4) == "hud." or key == "alerts.incoming" then UI.ApplyAlert() end
end)
