-- SITREP · Nameplates
-- Blizzard's nameplates in SITREP's look. Measured on Forever with
-- /sitrep plateprobe: plates can be anchored to, parented to and recoloured, in
-- and out of combat, friendly and hostile; forbidden plates stay Blizzard's.
-- Blizzard repaints its health bar on every update, so the colour is put back
-- from a hook on its own colour function.
-- On each plate:
--   health bar  flat texture, thin dark border; on your target a second, larger
--               set of brackets further out, in the same friend/foe colour
--   colour      players: class colour; NPCs: red when its target is you, orange
--               when hostile, yellow when neutral, green when friendly, grey
--               when another player has tapped it
--   level       before the name, in its danger colour (grey, green, yellow,
--               orange, red; ?? red), + for elites, R for rares
--   position    the bar moves right and down by plates.shiftX / shiftY (Blizzard
--               lays it out left of centre, beside its level badge)
--   name        SITREP's condensed font, centred above the bar with the level, in full,
--               in the reaction's colour
--               (green friend, yellow neutral, red foe); enemy players also get a
--               red 4 px line on each side of the bar
--   tags        enemies: YOU (its target is you), HVT, HEALER;
--               friends: TARGETED n (enemy players on it)
--   cast bar    SITREP's: KICK window, grey when it cannot be interrupted
--   friends     plates of friends you have not targeted are 30 % see-through;
--               your target shows in full
--   distance    your target: yards right of it (exact for group members, else the
--               range bracket) and a 4 px marker right of its brackets, as tall as them, green within 10 yd, yellow
--               within 25, red within your longest spell, none beyond
--   range       enemies out of your spell reach and friends out of heal range: the
--               bar fades (your target's too), the name and tags stay readable
--   foe ring    enemy players: a solid coral ring hugging the bar, the one red frame
--               on any plate (friendly plates have none while hit: two red frames
--               could not be told apart in a fight)
--   mate ring   (plates.mateRing) your group's members: a party-blue ring round the
--               bar and the name in the same blue; never see-through (other friends
--               are, plates.friendOpacity)
--   beacon      the member whose party frame the mouse is on: drawn as your target,
--               and a green frame pulsing round the brackets; on UIParent, so never
--               faded with the plate
--   dispel orbs friendly plates: a small orb left of the bar for each kind of debuff
--               you can dispel on it, in that kind's colour (frames round a plate
--               mean target and enemy; a dispel is something to do, not a kind of unit)
--   group focus (plates.groupFocus) an enemy your group is on: a mint ring round
--               the bar, further out and stronger the more of you (you count too,
--               once someone else is on it), and a pill left of it with how many;
--               filled on the one most of you are on
--   zen         (plates.friendZen) only enemies, your group and your target keep
--               their bar; other friendly plates: a thin health line on the bar's
--               place, the name just above it, no level
--   NPCs        (plates.npcIcons, PlateNPC.lua) friendly NPCs: no bar, the name,
--               its title under it and an icon for what it does over it; their
--               names sky blue (NPC_NAME), apart from players' green
-- Size and stacking stay the client's (Forever has no API for them).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format, floor = string.format, math.floor

local N = {}
ns.Plates = N
N.skins = {}                                        -- [unit token] = skin
local byPlate = setmetatable({}, { __mode = "k" })  -- plate frame -> skin
local byUF = setmetatable({}, { __mode = "k" })     -- Blizzard UnitFrame -> skin
local hooked = false

N.THIN = 2 -- the zen health line, px
local SEL_GAP = 6 -- distance of the target brackets (and enemy side lines) from the bar
local FOE_GAP = 2 -- the enemy players' ring: right round the bar
local ORB, ORBS = 7, 3 -- the dispel orbs: size, how many at most
local PIP_W, PIP_H, PIP_GAP = 10, 3, 2 -- combo pips on your target's plate
local FOE = { 1, 0.36, 0.30 } -- its coral (the design's colour for danger)
-- your group's members: the game's party chat blue, for their ring and name
local MATE = { 0.67, 0.67, 1 }
N.MATE = MATE
local FADE_ALPHA = 0.45
-- friendly NPCs' names: the one colour no other mark uses (green is players, yellow
-- neutral, red and coral danger, mint group focus, gold quests, violet experience,
-- party blue your group)
local NPC_NAME = { 0.55, 0.78, 1 }
N.NPC_NAME = NPC_NAME
local COL_ON_YOU, COL_HOSTILE, COL_NEUTRAL, COL_FRIEND, COL_TAPPED =
	{ 1, 0.25, 0.20 }, { 1, 0.55, 0.15 }, { 1, 0.85, 0.30 }, { 0.35, 0.92, 0.42 }, { 0.5, 0.5, 0.5 }

local function P() return ns.P and ns.P.plates end
local KILL = { 1, 0.45, 0.1 } -- the kill window's colour

---------------------------------------------------------------------------
-- Level and its danger colour
---------------------------------------------------------------------------
-- The level below which a mob is grey (gives no experience) for your level.
local function grayLevel(me)
	if me <= 5 then return 0 end
	if me <= 39 then return me - 5 - floor(me / 10) end
	if me <= 59 then return me - 1 - floor(me / 5) end
	return me - 9
end

function N.LevelColor(lvl, me)
	if not lvl or lvl <= 0 then return 1, 0.25, 0.2 end -- ?? : far above you
	if GetCreatureDifficultyColor then
		local ok, c = pcall(GetCreatureDifficultyColor, lvl)
		if ok and type(c) == "table" and type(c.r) == "number" and not ns.isSecret(c.r) then return c.r, c.g, c.b end
	end
	me = me or ns.Sensors.self.level or lvl
	local d = lvl - me
	if d >= 5 then return 1, 0.1, 0.1 end
	if d >= 3 then return 1, 0.5, 0.25 end
	if d >= -2 then return 1, 0.82, 0 end
	if lvl > grayLevel(me) then return 0.25, 0.75, 0.25 end
	return 0.5, 0.5, 0.5
end

function N.LevelText(unit)
	local lvl = read(UnitLevel, unit)
	if lvl == nil then return "" end
	local cls = read(UnitClassification, unit)
	local suffix = (cls == "elite" or cls == "rareelite" or cls == "worldboss") and "+" or cls == "rare" and "R" or ""
	local r, g, b = N.LevelColor(lvl)
	return format("|cff%02x%02x%02x%s%s|r", floor(r * 255), floor(g * 255), floor(b * 255), lvl > 0 and tostring(lvl) or "??", suffix)
end

---------------------------------------------------------------------------
-- Blizzard's parts of a plate
---------------------------------------------------------------------------
local function field(t, path)
	local ok, v = pcall(function()
		for k in path:gmatch("[^%.]+") do t = t and t[k] end
		return t
	end)
	return ok and v or nil
end

local function partsOf(plate)
	local uf = field(plate, "UnitFrame")
	if type(uf) ~= "table" then return nil end
	for _, path in ipairs({ "healthBar", "HealthBarsContainer.healthBar", "HealthBar" }) do
		local hb = field(uf, path)
		if type(hb) == "table" and hb.SetStatusBarColor then
			-- the cast bar sits in a container on modern plates
			local function tbl(v) return type(v) == "table" and v or nil end
			local box = tbl(field(uf, "CastBarsContainer"))
			local cast = tbl(field(uf, "castBar")) or tbl(field(uf, "CastBar")) or (box and tbl(field(box, "castBar")))
			return uf, hb, tbl(field(uf, "name")), cast, box
		end
	end
	return nil
end

-- Blizzard's decorations that SITREP's look replaces: borders, backgrounds and
-- the level badge, found by their keys on the UnitFrame, the health bar and its
-- container (the names differ between clients). /sitrep platedump lists them all.
local DECOR = { "[Bb]order", "[Bb]ackground", "^bg", "^BG", "[Ll]evel" }
local function decorOf(uf, hb)
	local list, seen = {}, {}
	local fill = select(2, pcall(hb.GetStatusBarTexture, hb))
	local keep = { [hb] = true, [uf] = true }
	if fill then keep[fill] = true end
	for _, t in ipairs({ uf, hb, field(uf, "HealthBarsContainer") }) do
		if type(t) == "table" then
			local ok = pcall(function()
				for k, v in pairs(t) do
					if type(k) == "string" and type(v) == "table" and not keep[v] and not seen[v] and v.SetAlpha then
						for _, pat in ipairs(DECOR) do
							if k:find(pat) then seen[v] = true; list[#list + 1] = v; break end
						end
					end
				end
			end)
			if not ok then break end
		end
	end
	return list
end
N.DecorOf = decorOf

local function contactOf(unit)
	local key = ns.Sensors.UnitKey(unit)
	return key and ns.Sensors.contacts[key]
end

local function isFriend(unit) return read(UnitIsFriend, "player", unit) == true end

-- Distance dot on your target's plate, from the range checks (brackets, not yards):
--   green   close: within 10 yd (the nearest check the client answers; melee is
--           not measurable on its own)
--   yellow  within 25 yd
--   red     within your longest spell (harmful for enemies, helpful for friends)
--   none    beyond it, or no check answered
local DOT_GREEN, DOT_YELLOW, DOT_RED = { 0.25, 1, 0.35 }, { 1, 0.85, 0.15 }, { 1, 0.22, 0.15 }
N.DOT_CLOSE, N.DOT_MID = 10, 25
function N.DotColor(lo, hi, reach)
	if not hi or not reach or hi > reach or (lo and lo >= reach) then return nil end
	if hi <= N.DOT_CLOSE then return DOT_GREEN end
	if hi <= N.DOT_MID then return DOT_YELLOW end
	return DOT_RED
end

-- How far the plate's unit is, as well as the client lets us know: exact yards
-- for group members (their positions), else the bracket of the range checks
-- (harmful spells for enemies, helpful ones for friends). Returns the distance
-- (for Comms.RangeText) and your reach for it.
-- A fresh measurement from this tick is reused (the ally or contact record of
-- that very unit); everything else (mobs, friendly NPCs) is measured here.
function N.DistanceOf(unit, friend)
	local S = ns.Sensors
	if friend == nil then friend = isFriend(unit) end
	if friend then
		local reach = 0
		for _, r in ipairs(S.myHelpRanges or {}) do if r > reach then reach = r end end
		if reach == 0 then reach = 28 end -- only the interact checks
		local a = ns.Allies and ns.Allies.ForUnit(unit)
		if a and a.exact and a.range then return { exact = true, range = a.range, lo = a.range, hi = a.range }, reach end
		if a and a.live and a.unit == unit and (a.lo or a.hi) then return { lo = a.lo or 0, hi = a.hi }, reach end
		local lo, hi = S.MeasureRange(unit, nil, S.helpChecks)
		return { lo = lo, hi = hi }, reach
	end
	local reach = S.myReach or 28
	local c = contactOf(unit)
	if c and c.live and c.unit == unit and (c.lo or c.hi) then return { lo = c.lo or 0, hi = c.hi }, reach end
	local lo, hi = S.MeasureRange(unit)
	return { lo = lo, hi = hi }, reach
end

-- Beyond your reach (the range fade)? The same answer as DistanceOf's lo >= reach,
-- but a unit without a fresh record (mobs, friendly NPCs) costs one range check,
-- not the whole ladder.
function N.Far(unit, friend)
	local S = ns.Sensors
	if friend then
		local reach = 0
		for _, r in ipairs(S.myHelpRanges or {}) do if r > reach then reach = r end end
		if reach == 0 then reach = 28 end
		local a = ns.Allies and ns.Allies.ForUnit(unit)
		if a and a.exact and a.range then return a.range >= reach end
		if a and a.live and a.unit == unit and (a.lo or a.hi) then return (a.lo or 0) >= reach end
		return S.Beyond(unit, reach, S.helpChecks) == true
	end
	local reach = S.myReach or 28
	local c = contactOf(unit)
	if c and c.live and c.unit == unit and (c.lo or c.hi) then return (c.lo or 0) >= reach end
	return S.Beyond(unit, reach) == true
end

-- Group focus: how many of your group are on this enemy (Targeting.UpdateFocus).
-- Shown once someone besides you is on it. Strength 1 to 4: the ring 3 to 6 px out
-- from the bar (outside an enemy player's coral ring, up to your target's
-- brackets), thicker and stronger.
local MINT = { 0.44, 0.94, 0.65 }
N.MINT = MINT
local function focusRing(s, lvl)
	local g = s.grp
	g.rings = g.rings or {}
	local r = g.rings[lvl]
	if not r then
		r = CreateFrame("Frame", nil, g)
		local o = 2 + lvl
		r:SetPoint("TOPLEFT", s, "TOPLEFT", -o, o)
		r:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", o, -o)
		K.Border(r, { MINT[1], MINT[2], MINT[3], 1 }, lvl >= 3 and 2 or 1, 4)
		r:SetAlpha(({ 0.45, 0.65, 0.85, 1 })[lvl])
		g.rings[lvl] = r
	end
	return r
end
function N.GroupFocus(s)
	local g = s.grp
	local TG = ns.Targeting
	local n, top = 0, false
	if P().groupFocus and not s.friend and s.guid and TG.focus then
		n = TG.focus[s.guid] or 0
		local others = n - ((TG.myTarget ~= nil and TG.myTarget == s.guid) and 1 or 0)
		if others < 1 then n = 0 end
		top = n > 0 and TG.focusTop == s.guid
	end
	if s.grpN == n and s.grpTop == top then return end
	s.grpN, s.grpTop = n, top
	if n == 0 then g:Hide() return end
	local lvl = math.min(n, 4)
	for i, r in pairs(g.rings or {}) do r:SetShown(i == lvl) end
	focusRing(s, lvl):Show()
	g.count:SetText(tostring(n))
	-- the one most of you are on: a filled pill; else mint on dark
	if top then
		g.pill:SetVertexColor(MINT[1], MINT[2], MINT[3], 1)
		g.count:SetTextColor(0.06, 0.12, 0.09)
	else
		g.pill:SetVertexColor(0.06, 0.08, 0.08, 0.85)
		g.count:SetTextColor(MINT[1], MINT[2], MINT[3])
	end
	g:Show()
end

-- Friendly zen (plates.friendZen): only enemies (players and mobs, neutral ones
-- too), your group and your target keep their bar; every other friendly plate
-- shows a thin health line on the bar's place (s.thin) and its name just above
-- it, without level. (A bar cannot be hidden
-- by its health: friendly players' health is secret on Forever, out of combat and
-- your own too, zenprobe 4.0.9 / 4.0.12; a curve could only guess its scale.)
function N.Zen(s)
	-- an NPC: who it is instead of a bar (PlateNPC)
	if ns.PlateNPC and ns.PlateNPC.On(s) then return true end
	if not (P().friendZen and s.friend and not s.isTarget) then return false end
	if N.Mate(s) then return false end
	return true
end

-- A member of your group (party or raid): the plate stands out among friends.
function N.Mate(s)
	if not (s.friend and s.isPlayer) then return false end
	return (read(UnitInParty, s.unit) or read(UnitInRaid, s.unit)) and true or false
end
-- See-through: a friend you have not targeted, unless one of your group.
function N.Faint(s) return s.friend and not s.isTarget and not s.mate end

-- The scale the client hands health curves is not measured (secret even for you):
-- 0 to 1 or 0 to 100. Health curves get their points on both: past 1.0001 the same
-- steps again at a hundred times the value (on a 0-1 scale it never gets there).
local SCALE_BOTH = 1.0001
N.SCALE_BOTH = SCALE_BOTH

-- Blizzard's own bar (its border, its highlight on the mouse-over) lies under
-- SITREP's and shows once SITREP's is gone: while zen, the health container and
-- every texture in it are see-through, each on its own (the border does not follow
-- its parents' alpha: zenprobe 4.0.11). Set again on every paint (Blizzard may set
-- them again); given back with the alpha each had.
local function textures(f, list, depth)
	local okR, regions = pcall(function() return { f:GetRegions() } end)
	for _, r in ipairs(okR and regions or {}) do
		-- (a secret alpha: left alone)
		local a = read(r.GetObjectType, r) == "Texture" and read(r.GetAlpha, r)
		if a then list[#list + 1] = { r, a } end
	end
	if depth < 3 then
		local okC, kids = pcall(function() return { f:GetChildren() } end)
		for _, k in ipairs(okC and kids or {}) do textures(k, list, depth + 1) end
	end
	return list
end
function N.ZenPaint(s)
	local box = s.uf and field(s.uf, "HealthBarsContainer")
	if type(box) ~= "table" or not box.SetAlpha then box = nil end
	if s.zenOn and box then
		if s.zenBox ~= box then s.zenTex = textures(box, {}, 0) end
		pcall(box.SetAlpha, box, 0)
		for _, t in ipairs(s.zenTex) do pcall(t[1].SetAlpha, t[1], 0) end
		s.zenBox = box
	elseif s.zenBox then
		pcall(s.zenBox.SetAlpha, s.zenBox, 1)
		for _, t in ipairs(s.zenTex or {}) do pcall(t[1].SetAlpha, t[1], t[2]) end
		s.zenBox, s.zenTex = nil, nil
	end
end

-- Why a friendly plate is or is not zen (/sitrep zenprobe).
function N.ZenWhy(s)
	local group = (read(UnitInParty, s.unit) or read(UnitInRaid, s.unit)) and true or false
	return format("friend %s, player %s, target %s, group %s, zen %s, Blizzard's bar hidden %s, bar alpha %s%s",
		tostring(s.friend), tostring(s.isPlayer), tostring(s.isTarget), tostring(group), tostring(N.Zen(s)),
		tostring(s.zenBox ~= nil), tostring(read(s.hb.GetAlpha, s.hb)), s.isBig and ", own bar" or "")
end

-- What still draws on a plate: every shown texture under it with some alpha
-- (/sitrep zenprobe, for the first zen plate).
function N.Visible(s)
	local out = {}
	local function walk(f, path, depth)
		if depth > 6 then return end
		local okR, regions = pcall(function() return { f:GetRegions() } end)
		for i, r in ipairs(okR and regions or {}) do
			if read(r.GetObjectType, r) == "Texture" and read(r.IsVisible, r) then
				local a = read(r.GetEffectiveAlpha, r) or read(r.GetAlpha, r)
				local vr, vg, vb, va = read(r.GetVertexColor, r)
				if a == nil or a > 0.01 then
					out[#out + 1] = format("%s#%d %s a%s vc %s %dx%d", path, i, tostring(read(r.GetDrawLayer, r)), a and format("%.2f", a) or "secret",
						va and format("%.2f", va) or "?", math.floor((read(r.GetWidth, r) or 0) + 0.5), math.floor((read(r.GetHeight, r) or 0) + 0.5))
				end
			end
		end
		local okC, kids = pcall(function() return { f:GetChildren() } end)
		for i, k in ipairs(okC and kids or {}) do
			if read(k.IsVisible, k) then
				local key
				for kk, v in pairs(f) do if rawequal(v, k) and type(kk) == "string" then key = kk break end end
				walk(k, path .. "." .. (key or ("[" .. i .. "]")), depth + 1)
			end
		end
	end
	walk(s:GetParent(), "plate", 0)
	return out
end

-- Friend (green), neutral (yellow) or foe (red), for the name and the bar's edge.
local REACT_FOE, REACT_NEUTRAL, REACT_FRIEND = { 1, 0.18, 0.12 }, { 1, 0.85, 0.15 }, { 0.20, 1, 0.32 }
function N.Reaction(unit, s)
	local friend, reaction
	if s then friend, reaction = s.friend, s.reaction
	else friend, reaction = isFriend(unit), read(UnitReaction, unit, "player") end
	if friend then return REACT_FRIEND end
	if reaction == 4 then return REACT_NEUTRAL end
	return REACT_FOE
end

-- Health colour for a plate's unit (s: its skin, whose facts this refresh already read).
function N.Color(unit, s)
	local isPlayer
	if s then isPlayer = s.isPlayer else isPlayer = read(UnitIsPlayer, unit) end
	local _, class = read(UnitClass, unit)
	if isPlayer ~= false and not class then
		local c = contactOf(unit)
		class = c and c.class
	end
	if isPlayer and class then return ns.Data.ClassColor(class) end
	if read(UnitIsTapDenied, unit) then return COL_TAPPED[1], COL_TAPPED[2], COL_TAPPED[3] end
	local reaction
	if s then reaction = s.reaction else reaction = read(UnitReaction, unit, "player") end
	local c
	if reaction and reaction <= 4 and ns.Targeting.Is(unit, "player") then c = COL_ON_YOU
	elseif reaction and reaction <= 3 then c = COL_HOSTILE
	elseif reaction == 4 then c = COL_NEUTRAL
	elseif reaction then c = COL_FRIEND
	else
		local friend
		if s then friend = s.friend else friend = isFriend(unit) end
		c = friend and COL_FRIEND or COL_HOSTILE
	end
	return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- The skin: SITREP's frame on a plate
---------------------------------------------------------------------------
-- Per frame, only while there is something to animate (a cast): with no cast the
-- plate has no OnUpdate at all.
-- (measured by /sitrep perf; its time includes the plate's cast bar)
local plateUpdate = ns.Timed("plates: animation", function(self)
	local busy = false
	if self.cast:IsShown() then self.castUpdate(self); busy = true end
	if not busy then self:SetScript("OnUpdate", nil); self.awake = false end
end)
local function wake(s)
	if not s.awake then s.awake = true; s:SetScript("OnUpdate", plateUpdate) end
end

local function build(plate, hb)
	local s = CreateFrame("Frame", nil, plate)
	s:SetPoint("TOPLEFT", hb, "TOPLEFT")
	s:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT")
	s:SetFrameLevel(hb:GetFrameLevel() + 2)
	K.Border(s, { 0, 0, 0, 0.9 }, 1, 0)
	-- SITREP's own bar, used when the plates are bigger than the game draws them
	-- (plates.scale; Forever has no size setting and draws plates at about half
	-- size): over Blizzard's (invisible then), under SITREP's border and text
	s.big = CreateFrame("StatusBar", nil, plate)
	s.big:SetAllPoints(s)
	s.big:SetFrameLevel(hb:GetFrameLevel() + 1)
	s.big:SetStatusBarTexture(K.WHITE)
	s.big.bg = s.big:CreateTexture(nil, "BACKGROUND")
	s.big.bg:SetAllPoints()
	s.big.bg:SetColorTexture(0.07, 0.09, 0.09, 0.9)
	s.big:Hide()
	-- group focus: rings (made when needed) and the count left of the bar
	s.grp = CreateFrame("Frame", nil, s)
	s.grp:SetAllPoints(s)
	s.grp.pill = K.Backdrop(s.grp, { 0.06, 0.08, 0.08, 0.85 }, 4, { shadow = false })
	local pr = K.Region(s.grp.pill)
	pr:ClearAllPoints()
	pr:SetPoint("RIGHT", s, "LEFT", -(SEL_GAP + 3), 0)
	pr:SetSize(16, 12)
	s.grp.count = s.grp:CreateFontString(nil, "OVERLAY")
	K.ApplyFont(s.grp.count, K.FONT, 9, "")
	s.grp.count:SetPoint("CENTER", pr, "CENTER", 0, 0)
	s.grp:Hide()
	-- zen: a thin health line across the bar's middle (the client's values as they
	-- are, secret or not)
	s.thin = CreateFrame("StatusBar", nil, s)
	s.thin:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.thin:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.thin:SetHeight(N.THIN)
	s.thin:SetStatusBarTexture(K.WHITE)
	s.thin.bg = s.thin:CreateTexture(nil, "BACKGROUND")
	s.thin.bg:SetAllPoints()
	s.thin.bg:SetColorTexture(0.07, 0.09, 0.09, 0.7)
	s.thin:Hide()
	-- heals on their way (UI/Heals.lua): one overlay for Blizzard's bar, held by
	-- SITREP's frame; one for SITREP's own bar
	s.healN = ns.Heals.Attach(hb, nil, nil, s, false)
	s.healB = ns.Heals.Attach(s.big, nil, nil, nil, false)
	-- the dark track behind the fill (Blizzard's background is hidden): on the bar
	-- itself, below its fill
	s.track = hb:CreateTexture(nil, "BACKGROUND", nil, -8)
	s.track:SetAllPoints(hb)
	s.track:SetColorTexture(0.07, 0.09, 0.09, 0.9)
	-- your target: a second, larger set of brackets further out, same colour
	s.sel = CreateFrame("Frame", nil, s)
	s.sel:SetPoint("TOPLEFT", -SEL_GAP, SEL_GAP)
	s.sel:SetPoint("BOTTOMRIGHT", SEL_GAP, -SEL_GAP)
	s.sel.parts = K.Brackets(s.sel, 14, 3, 1, 10, true) -- coloured per plate, friend or foe
	s.sel:Hide()
	-- friendly plates: being hit, and something you can dispel
	-- enemy players: a solid coral ring hugging the bar (N.FoeRing)
	s.foe = CreateFrame("Frame", nil, s)
	s.foe:SetPoint("TOPLEFT", -FOE_GAP, FOE_GAP)
	s.foe:SetPoint("BOTTOMRIGHT", FOE_GAP, -FOE_GAP)
	K.Border(s.foe, { FOE[1], FOE[2], FOE[3], 1 }, 2, 4)
	-- (the client fades plates you have not selected: the ring stays solid)
	if s.foe.SetIgnoreParentAlpha then pcall(s.foe.SetIgnoreParentAlpha, s.foe, true) end
	s.foe:Hide()
	-- your group's members: the same ring in party blue (N.Mate)
	s.mateRing = CreateFrame("Frame", nil, s)
	s.mateRing:SetPoint("TOPLEFT", -FOE_GAP, FOE_GAP)
	s.mateRing:SetPoint("BOTTOMRIGHT", FOE_GAP, -FOE_GAP)
	K.Border(s.mateRing, { MATE[1], MATE[2], MATE[3], 1 }, 2, 4)
	if s.mateRing.SetIgnoreParentAlpha then pcall(s.mateRing.SetIgnoreParentAlpha, s.mateRing, true) end
	s.mateRing:Hide()
	-- friendly plates: what you can dispel, as orbs left of the bar (s.disp: shown
	-- while there is any, .plain: known for certain; N.PaintDispel)
	s.disp = CreateFrame("Frame", nil, s)
	s.disp:SetAllPoints(s)
	s.disp.orbs = {}
	for i = 1, ORBS do
		local o = CreateFrame("Frame", nil, s.disp)
		o:SetSize(ORB + 2, ORB + 2)
		o:SetPoint("RIGHT", s, "LEFT", -5 - (i - 1) * (ORB + 4), 0)
		o.ring = K.Disc(o, "BORDER", ORB + 2)
		o.ring:SetPoint("CENTER")
		o.ring:SetVertexColor(0, 0, 0, 0.75)
		o.dot = K.Disc(o, "ARTWORK", ORB)
		o.dot:SetPoint("CENTER")
		o:Hide()
		s.disp.orbs[i] = o
	end
	s.disp:Hide()
	-- enemy healers: their mana, a thin blue bar under the plate (the client's values
	-- as they are, secret or not)
	s.mana = CreateFrame("StatusBar", nil, s)
	s.mana:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -1)
	s.mana:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -1)
	s.mana:SetHeight(2)
	s.mana:SetStatusBarTexture(K.WHITE)
	s.mana:SetStatusBarColor(0.3, 0.6, 1)
	s.mana.bg = s.mana:CreateTexture(nil, "BACKGROUND")
	s.mana.bg:SetAllPoints()
	s.mana.bg:SetColorTexture(0, 0, 0, 0.7)
	s.mana:Hide()
	-- enemy players in your reach and under plates.killPct health: a pulsing orange
	-- frame (N.Kill)
	s.kill = CreateFrame("Frame", nil, s)
	s.kill:SetPoint("TOPLEFT", -SEL_GAP - 3, SEL_GAP + 3)
	s.kill:SetPoint("BOTTOMRIGHT", SEL_GAP + 3, -SEL_GAP - 3)
	K.Border(s.kill, { KILL[1], KILL[2], KILL[3], 1 }, 2)
	local ag = s.kill.CreateAnimationGroup and s.kill:CreateAnimationGroup()
	if ag then
		local a = ag:CreateAnimation("Alpha")
		if a.SetFromAlpha then a:SetFromAlpha(1); a:SetToAlpha(0.3) end
		if a.SetDuration then a:SetDuration(0.35) end
		if ag.SetLooping then ag:SetLooping("BOUNCE") end
		s.kill.pulse = ag
	end
	s.kill:Hide()
	-- the member whose frame the mouse is on: a green frame pulsing round its
	-- brackets, always at full colour (N.Beacon). Not in the plate: on UIParent, anchored to it, so no
	-- fading of the plate reaches it (out of line of sight, out of range) and it
	-- draws over the other plates
	s.beacon = CreateFrame("Frame", nil, UIParent)
	s.beacon:SetFrameStrata("LOW")
	s.beacon:SetPoint("TOPLEFT", s, "TOPLEFT", -SEL_GAP - 4, SEL_GAP + 4)
	s.beacon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", SEL_GAP + 4, -SEL_GAP - 4)
	K.Border(s.beacon, { REACT_FRIEND[1], REACT_FRIEND[2], REACT_FRIEND[3], 1 }, 2, 4)
	local bg = s.beacon.CreateAnimationGroup and s.beacon:CreateAnimationGroup()
	if bg then
		-- (it pulses in size, never in alpha: full colour all the time)
		local a = bg:CreateAnimation("Scale")
		if a.SetScaleFrom then a:SetScaleFrom(1, 1); a:SetScaleTo(1.12, 1.25)
		elseif a.SetScale then a:SetScale(1.12, 1.25) end
		if a.SetOrigin then a:SetOrigin("CENTER", 0, 0) end
		if a.SetDuration then a:SetDuration(0.45) end
		if bg.SetLooping then bg:SetLooping("BOUNCE") end
		s.beacon.pulse = bg
	end
	s.beacon:Hide()
	-- text above the bar, one line centred over it: level, full name, tags; drawn
	-- over the brackets and side lines (placed by N.PlaceText)
	s.text = CreateFrame("Frame", nil, s)
	s.text:SetAllPoints(s)
	s.text:SetFrameLevel(s:GetFrameLevel() + 6)
	s.name = K.Font(s.text, 11, C.text, K.FONT, "OUTLINE")
	s.name:SetJustifyH("CENTER")
	if s.name.SetWordWrap then s.name:SetWordWrap(false) end
	N.PlaceText(s, false)
	-- your target: a 4 px distance marker right of the brackets, as tall as they are
	s.dot = s.text:CreateTexture(nil, "OVERLAY")
	s.dot:SetTexture(K.WHITE)
	s.dot:SetWidth(4)
	s.dot:SetPoint("TOPLEFT", s, "TOPRIGHT", SEL_GAP + 3, SEL_GAP)
	s.dot:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", SEL_GAP + 3, -SEL_GAP)
	s.dot:Hide()
	-- and the yards beside it
	s.distText = K.Font(s.text, 9, C.text, K.FONT, "OUTLINE")
	s.distText:SetPoint("LEFT", s, "RIGHT", SEL_GAP + 3 + 4 + 3, 0)
	s.distText:Hide()
	-- SITREP's cast bar under the plate
	ns.Units.CastBar(s, s, 10)
	-- below the target brackets, like the text above them
	s.cast:ClearAllPoints()
	s.cast:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -(SEL_GAP + 2))
	s.cast:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -(SEL_GAP + 2))
	-- your combo points on your target's plate: five pips under its brackets
	s.combo = CreateFrame("Frame", nil, s)
	s.combo:SetSize(5 * PIP_W + 4 * PIP_GAP, PIP_H)
	s.combo:SetPoint("TOP", s, "BOTTOM", 0, -(SEL_GAP + 3))
	s.combo.pips = {}
	for i = 1, 5 do
		local p = K.Tex(s.combo, "OVERLAY", { 1, 1, 1, 0.15 })
		p:SetSize(PIP_W, PIP_H)
		p:SetPoint("LEFT", s.combo, "LEFT", (i - 1) * (PIP_W + PIP_GAP), 0)
		s.combo.pips[i] = p
	end
	s.combo:Hide()
	K.ApplyFont(s.castText, K.FONT, 8, "OUTLINE")
	K.ApplyFont(s.castKick, K.FONT, 8, "OUTLINE")
	s:SetScript("OnUpdate", nil) -- woken by a cast or a hit (see wake)
	return s
end

-- "<level> <name> <tags>" (level and tags carry their own colour codes). A secret
-- name is handed to the font string as it is.
local function setLine(fs, unit, level, tags)
	local pre = level ~= "" and (level .. " ") or ""
	local post = tags ~= "" and ("  " .. tags) or ""
	local v = read(GetUnitName, unit, false)
	if v then
		local line = pre .. v .. post
		if fs.line ~= line then fs.line = line; fs:SetText(line) end
		return
	end
	fs.line = nil
	if pcall(function() fs:SetFormattedText("%s%s%s", pre, GetUnitName(unit, false), post) end) then return end
	if not pcall(function() fs:SetText(GetUnitName(unit, false)) end) then fs:SetText(pre .. post) end
end

-- Modern plates round the bar's ends with a mask on its fill: SITREP's bar is
-- square, so the masks come off (and go back on when the plate is given back).
local function unmask(s)
	local okF, fill = pcall(s.hb.GetStatusBarTexture, s.hb)
	if not okF or type(fill) ~= "table" or not fill.GetNumMaskTextures or fill == s.unmasked then return end
	s.unmasked = fill
	local okN, n = pcall(fill.GetNumMaskTextures, fill)
	if not okN or ns.isSecret(n) or type(n) ~= "number" then return end
	for i = n, 1, -1 do
		local okM, m = pcall(fill.GetMaskTexture, fill, i)
		if okM and m and pcall(fill.RemoveMaskTexture, fill, m) then
			s.masks[#s.masks + 1] = { fill, m }
		end
	end
end

-- Out of range: the bar (with its track and border) fades, the text does not.
-- A friend you have not targeted: Blizzard's plate (with the bar inside it), the
-- bar's border and the cast bar go see-through; level, name and tags do not.
local function faintAlpha(s) return s.faint and (P().friendOpacity or 0.7) or 1 end

local function applyFade(s)
	-- zen: the thin line instead of the bar, faded like it
	s.thin:SetShown(s.zenOn and not s.svc and true or false)
	if s.zenOn then s.thin:SetAlpha((s.far and FADE_ALPHA or 1) * faintAlpha(s)) end
	local a = s.zen and 0 or s.far and FADE_ALPHA or 1
	if s.isBig then
		pcall(s.hb.SetAlpha, s.hb, 0) -- (SITREP's own bar shows the health)
		s.big:SetAlpha(a * faintAlpha(s)) -- (Blizzard's frame fades friends; SITREP's bar is not in it)
	else
		pcall(s.hb.SetAlpha, s.hb, a)
	end
	local b = s.zenOn and 0 or a * faintAlpha(s)
	for i = 1, 4 do s.border[i]:SetAlpha(b) end
end

local function paintHealth(s)
	local hb = s.hb
	pcall(hb.SetStatusBarTexture, hb, K.WHITE)
	unmask(s)
	applyFade(s)
	pcall(hb.SetStatusBarColor, hb, N.Color(s.unit, s))
	if s.isBig then pcall(s.big.SetStatusBarColor, s.big, N.Color(s.unit, s)) end
	if s.zenOn then pcall(s.thin.SetStatusBarColor, s.thin, N.Color(s.unit, s)) end
	if s.zenOn or s.zenBox then N.ZenPaint(s) end
end

-- Heals on their way, on whichever bar shows (plates.heals).
function N.Heals(s)
	local on = P().heals
	local use = s.isBig and s.healB or s.healN
	local other = s.isBig and s.healN or s.healB
	ns.Heals.FeedTo(other, nil)
	ns.Heals.FeedTo(use, on and s.unit or nil)
	-- out of range the prediction fades with the bar
	use.clip:SetAlpha(s.zen and 0 or s.far and FADE_ALPHA or 1)
end

-- SITREP's own bar: the unit's health as the client gives it (secret values too:
-- the bar takes them as they are).
function N.Health(s)
	N.Heals(s)
	local unit = s.unit
	if s.zenOn then
		pcall(function()
			s.thin:SetMinMaxValues(0, UnitHealthMax(unit))
			s.thin:SetValue(UnitHealth(unit))
		end)
	end
	if not s.isBig then return end
	pcall(function()
		s.big:SetMinMaxValues(0, UnitHealthMax(unit))
		s.big:SetValue(UnitHealth(unit))
	end)
end

-- The plate's size (plates.scale). At 1 SITREP's look lies on Blizzard's bar as
-- before. Otherwise it is centred on it, scaled, with SITREP's own bar: name,
-- level, brackets, cast bar and marker grow with it.
-- In combat, friendly players you have not targeted shrink (plates.friendCombatScale):
-- the enemies stand out in a crowd. SITREP's own bar then shows them, smaller.
-- With enemy players about, mobs shrink too (plates.mobPvpScale), less than
-- friends and at full strength in their own colours (friends: see-through, class
-- colours): your target and a mob on you keep their size.
local pvpAt, pvpNear = -1, false
function N.EnemyPlayersNear()
	local now = GetTime()
	if now - pvpAt < 0.5 then return pvpNear end
	pvpAt, pvpNear = now, false
	for u, s in pairs(N.skins) do
		if s.active and s.unit == u and s.isPlayer == true and s.friend == false and not read(UnitIsDeadOrGhost, u) then
			pvpNear = true
			break
		end
	end
	return pvpNear
end
function N.SizeFor(s)
	local sz = P().scale or 1
	if s.friend and s.isPlayer and not s.isTarget and InCombatLockdown() then
		sz = sz * (P().friendCombatScale or 1)
	elseif s.isPlayer == false and s.friend == false and not s.isTarget and (P().mobPvpScale or 1) < 1 and N.EnemyPlayersNear()
		and not ns.Targeting.Is(s.unit, "player") then
		sz = sz * P().mobPvpScale
	end
	return sz
end
function N.Size(s)
	local sz = N.SizeFor(s)
	local big = math.abs(sz - 1) > 0.001
	-- (the bar's size, asked every 2 s: asking makes the client lay the plate out)
	local w, h = s.hbW, s.hbH
	local now = GetTime()
	if not w or now - (s.hbAt or 0) >= 2 then
		w, h = read(s.hb.GetWidth, s.hb), read(s.hb.GetHeight, s.hb)
		if not (w and w > 0) then w = 96 end
		if not (h and h > 0) then h = 10 end
		s.hbW, s.hbH, s.hbAt = w, h, now
	end
	if not big then sz, w, h = 1, 0, 0 end
	if s.sizeKey and s.sizeSz == sz and s.sizeW == w and s.sizeH == h then return end
	s.sizeKey, s.sizeSz, s.sizeW, s.sizeH = true, sz, w, h
	s.isBig = big
	s:ClearAllPoints()
	if big then
		s:SetScale(sz)
		s:SetPoint("CENTER", s.hb, "CENTER", 0, 0)
		s:SetSize(w, h)
		s.big:Show()
		s.track:Hide()
		N.Health(s)
	else
		s:SetScale(1)
		s:SetPoint("TOPLEFT", s.hb, "TOPLEFT")
		s:SetPoint("BOTTOMRIGHT", s.hb, "BOTTOMRIGHT")
		s.big:Hide()
		s.track:Show()
	end
end

local function hideBlizzard(s)
	-- a plate showing only its name (no bar): Blizzard's name stays, ours steps aside
	local okB, barShown = pcall(s.hb.IsShown, s.hb)
	local bar = not okB or barShown ~= false
	-- friendly plates you have not targeted are 30 % see-through (setting: plates.friendOpacity;
	-- a new key, so the 10 % of 3.21.2 does not stick) - all but the text
	local a = faintAlpha(s)
	s:SetAlpha(bar and 1 or 0)
	-- one of your group: the party-blue ring (it ignores the plate's alpha: none on a name-only plate)
	s.mateRing:SetShown(bar and P().mateRing ~= false and s.mate and not s.zenOn or false)
	if s.uf then pcall(s.uf.SetAlpha, s.uf, a) end
	s.cast:SetAlpha(a)
	applyFade(s)
	-- the side lines mark enemy players only (they ignore the alpha above)
	if s.bname then pcall(s.bname.SetAlpha, s.bname, bar and 0 or 1) end
	for _, d in ipairs(s.decor or {}) do pcall(d.SetAlpha, d, 0) end
	s.track:SetShown(bar and not s.zen)
	if N.Wants(s.unit, "cast", s.friend) then
		-- the container is faded out (Blizzard animates the bar's own alpha); the bar hidden
		if s.bcastBox then pcall(s.bcastBox.SetAlpha, s.bcastBox, 0) end
		if s.bcast then pcall(s.bcast.Hide, s.bcast) end
	elseif s.bcastBox then
		pcall(s.bcastBox.SetAlpha, s.bcastBox, 1)
	end
end

-- Blizzard lays the bar out left of centre (room for its level badge, now hidden)
-- and a little high: SITREP moves it by plates.shiftX / shiftY. Its own anchors are
-- remembered and put back when the plate is given back; when Blizzard lays the bar
-- out again, the new anchors become the ones that are shifted.
local function anchors(f)
	local okN, n = pcall(f.GetNumPoints, f)
	if not okN or type(n) ~= "number" or ns.isSecret(n) or n == 0 then return nil end
	local pts = {}
	for i = 1, n do
		local ok, a, rel, b, x, y = pcall(f.GetPoint, f, i)
		if not ok or ns.isSecret(x) or ns.isSecret(y) then return nil end
		pts[i] = { a, rel, b, x or 0, y or 0 }
	end
	return pts
end
local function same(p1, p2)
	if not (p1 and p2) or #p1 ~= #p2 then return false end
	for i = 1, #p1 do
		for k = 1, 5 do if p1[i][k] ~= p2[i][k] then return false end end
	end
	return true
end
local function setAnchors(f, pts, dx, dy)
	f:ClearAllPoints()
	for _, q in ipairs(pts) do f:SetPoint(q[1], q[2], q[3], q[4] + dx, q[5] + dy) end
end
-- (the bar's anchors as they were set last: no tables built when nothing changed;
-- a secret anchor errors in the comparison and counts as changed)
local function sameAnchors(f, pts)
	local n = f:GetNumPoints()
	if n ~= #pts then return false end
	for i = 1, n do
		local a, rel, b, x, y = f:GetPoint(i)
		local q = pts[i]
		if a ~= q[1] or rel ~= q[2] or b ~= q[3] or (x or 0) ~= q[4] or (y or 0) ~= q[5] then return false end
	end
	return true
end
local function unchanged(f, pts)
	local ok, same = pcall(sameAnchors, f, pts)
	return ok and same == true
end
function N.Shift(s)
	local p = P()
	local dx, dy = p.shiftX or 0, p.shiftY or 0
	if dx == 0 and dy == 0 and not s.shifted then return end
	if s.shifted and s.shiftDX == dx and s.shiftDY == dy and unchanged(s.hb, s.shifted) then return end
	local now = anchors(s.hb)
	if not now then return end
	if not same(now, s.shifted) then s.orig = now end -- Blizzard's own (laid out again)
	if dx == 0 and dy == 0 then
		if s.shifted then pcall(setAnchors, s.hb, s.orig, 0, 0); s.shifted = nil end
		return
	end
	local want = {}
	for i, q in ipairs(s.orig) do want[i] = { q[1], q[2], q[3], q[4] + dx, q[5] + dy } end
	if same(now, want) then return end
	if pcall(setAnchors, s.hb, s.orig, dx, dy) then s.shifted, s.shiftDX, s.shiftDY = want, dx, dy end
end
local function unshift(s)
	if s.shifted and s.orig then pcall(setAnchors, s.hb, s.orig, 0, 0) end
	s.shifted, s.orig = nil, nil
end

-- The text sits close over the bar, and moves up clear of the brackets on your target.
local TEXT_GAP = 3
function N.PlaceText(s, isTarget)
	local gap = s.svc and "npc" or s.zenOn and "zen" or isTarget and SEL_GAP + 2 or TEXT_GAP
	if s.textGap == gap then return end
	s.textGap = gap
	s.name:ClearAllPoints()
	if s.svc then
		s.name:SetPoint("CENTER", s, "CENTER", 0, 0) -- an NPC: the name where the bar was
	elseif s.zenOn then
		s.name:SetPoint("BOTTOM", s.thin, "TOP", 0, 2) -- zen: just above the thin line
	else
		s.name:SetPoint("BOTTOM", s, "TOP", 0, gap) -- no width limit: the full name shows
	end
end

-- Your target's distance: the marker in its colour and the yards beside it
-- (dim when beyond your reach; nothing when no check answered).
-- Your combo points (rogues, druids) on your target's plate: lit pips in amber, the
-- rest faint; none while you have none. The cast bar moves down under them.
local COMBO = { 1, 0.83, 0.37 }
function N.Combo(s)
	local me = ns.Sensors.self
	local cp = 0
	if P().combo ~= false and (me.class == "ROGUE" or me.class == "DRUID") and read(UnitIsUnit, s.unit, "target") == true then
		cp = read(GetComboPoints, "player", "target") or 0
	end
	local show = cp > 0
	if show then
		for i, p in ipairs(s.combo.pips) do
			if i <= cp then p:SetVertexColor(COMBO[1], COMBO[2], COMBO[3], 1) else p:SetVertexColor(1, 1, 1, 0.15) end
		end
	end
	if show ~= (s.combo:IsShown() and true or false) then
		s.combo:SetShown(show)
		local y = -(SEL_GAP + 2) - (show and (PIP_H + 4) or 0)
		s.cast:ClearAllPoints()
		s.cast:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, y)
		s.cast:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, y)
	end
end

function N.PaintDot(s, isTarget)
	if not (isTarget and P().dot) then s.dot:Hide(); s.distText:Hide() return end
	local d, reach = N.DistanceOf(s.unit)
	local c = N.DotColor(d.lo, d.hi, reach)
	if c then s.dot:SetVertexColor(c[1], c[2], c[3], 1); s.dot:Show() else s.dot:Hide() end
	local text = ns.Comms.RangeText(d)
	if text == "?" then s.distText:Hide() return end
	s.distText:SetText(text)
	if c then s.distText:SetTextColor(c[1], c[2], c[3], 1) else s.distText:SetTextColor(0.55, 0.6, 0.6, 1) end
	s.distText:Show()
end

-- Should this plate's unit get SITREP's look (and this part of it)?
function N.Wants(unit, part, friend)
	local p = P()
	if not (p and p.enabled and ns.P.enabled) then return false end
	if friend == nil then friend = isFriend(unit) end
	if friend then if not p.friendly then return false end
	elseif not p.enemy then return false end
	return part == nil or p[part] ~= false
end

---------------------------------------------------------------------------
-- Aggro radar (levelling): a hostile mob notices you within about 20 yd at your
-- level, a yard more for each level it has over you, a yard less for each below
-- (at least 5, at most 45; "??": 45). With the range checks: AGGRO in orange
-- within AGGRO_WARN yards of that edge, in red inside it. Only while the mob is
-- not fighting yet.
local AGGRO_BASE, AGGRO_MIN, AGGRO_MAX, AGGRO_WARN = 20, 5, 45, 8
function N.AggroRadius(mobLevel, myLevel)
	if not mobLevel or mobLevel <= 0 then return AGGRO_MAX end
	local r = AGGRO_BASE + (mobLevel - (myLevel or mobLevel))
	return math.max(AGGRO_MIN, math.min(AGGRO_MAX, r))
end
function N.Aggro(s)
	s.aggro = nil
	if not (P().aggroRadar and s.isPlayer == false and not s.friend and s.reaction and s.reaction <= 3) then return nil end
	local unit = s.unit
	if read(UnitAffectingCombat, unit) or read(UnitIsDeadOrGhost, unit) or read(UnitIsTapDenied, unit) then return nil end
	local r = N.AggroRadius(read(UnitLevel, unit), ns.Sensors.self.level)
	local S = ns.Sensors
	if S.Beyond(unit, r + AGGRO_WARN) ~= false then return nil end
	s.aggro = S.Beyond(unit, r) == false and "in" or "near"
	return s.aggro
end

-- Enemy healers' mana: plain, a known healer or a healing class with mana showing.
local MANA_LOW = 0.15
local function feedMana(s)
	s.mana:SetMinMaxValues(0, UnitPowerMax(s.unit, 0))
	s.mana:SetValue(UnitPower(s.unit, 0))
end
function N.Mana(s)
	local show = false
	s.manaLow = nil
	if P().enemyMana and s.isPlayer and not s.friend then
		local c = s.guid and ns.Sensors.contacts[s.guid]
		local _, class = read(UnitClass, s.unit)
		class = class or (c and c.class)
		local healer = ns.Targeting.IsHealer(c) or ns.Targeting.HEAL_CLASS[class or ""]
		if healer and read(UnitPowerType, s.unit) ~= 1 and read(UnitPowerType, s.unit) ~= 3 then
			show = pcall(feedMana, s)
			local m, mx = read(UnitPower, s.unit, 0), read(UnitPowerMax, s.unit, 0)
			if m and mx and mx > 0 then s.manaLow = m / mx <= MANA_LOW end
		end
	end
	s.mana:SetShown(show)
end

---------------------------------------------------------------------------
-- Kill window: an enemy player in your reach, under plates.killPct health. With
-- plain health SITREP decides; with secret health (in combat) the client does:
-- a colour curve on its health percent gives the frame's colour, see-through above
-- the threshold, so SITREP never reads the value.
local killCurve, killCurvePct
local function curve(pct)
	if killCurvePct == pct then return killCurve end
	killCurvePct, killCurve = pct, false
	local CU = C_CurveUtil
	if not (CU and CU.CreateColorCurve and CreateColor) then return false end
	local ok, c = pcall(function()
		local cv = CU.CreateColorCurve()
		local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
		if step then cv:SetType(step) end
		cv:AddPoint(0, CreateColor(KILL[1], KILL[2], KILL[3], 1))
		cv:AddPoint(pct, CreateColor(KILL[1], KILL[2], KILL[3], 0))
		-- (the same on a 0-100 scale: see SCALE_BOTH)
		cv:AddPoint(SCALE_BOTH, CreateColor(KILL[1], KILL[2], KILL[3], 1))
		cv:AddPoint(pct * 100, CreateColor(KILL[1], KILL[2], KILL[3], 0))
		return cv
	end)
	killCurve = ok and c or false
	return killCurve
end
N.KillCurve = curve
-- (the client paints the border from the curve; false when it cannot)
local function paintKillSecret(s, cv)
	local col = UnitHealthPercent(s.unit, false, cv)
	local r, g, b, a = col:GetRGBA()
	for i = 1, 4 do s.kill.border[i]:SetVertexColor(r, g, b, a) end
end
function N.Kill(s)
	local p = P()
	local show, painted = false, false
	if p.killWindow and s.isPlayer and not s.friend and s.active then
		local c = s.guid and ns.Sensors.contacts[s.guid]
		local inReach
		if c and c.live then inReach = c.inMyReach else inReach = not s.far end
		if inReach then
			local pct = (p.killPct or 20) / 100
			local h, m = read(UnitHealth, s.unit), read(UnitHealthMax, s.unit)
			if h and m and m > 0 then
				show = h / m <= pct
			else
				local cv = UnitHealthPercent and curve(pct)
				if cv and pcall(paintKillSecret, s, cv) then show, painted = true, true end
			end
		end
	end
	if show and not painted then s.kill.border:SetColor(KILL[1], KILL[2], KILL[3], 1) end
	if show ~= (s.kill:IsShown() and true or false) then
		s.kill:SetShown(show)
		if s.kill.pulse then if show then s.kill.pulse:Play() else s.kill.pulse:Stop() end end
	end
	s.killing = show and not painted -- (plain: known to be under the threshold)
end

-- /sitrep perf: the parts of a plate's refresh, each on its own line
for _, name in ipairs({ "Reaction", "LevelText", "Shift", "Size", "Health", "PaintDot", "Far", "Color", "Marked" }) do
	N[name] = ns.Timed("plates: " .. name, N[name])
end
setLine = ns.Timed("plates: name line", setLine)
paintHealth = ns.Timed("plates: paint health", paintHealth)
hideBlizzard = ns.Timed("plates: hide Blizzard's", hideBlizzard)
-- The orbs: one per kind you can dispel (readable), or one the client colours
-- (locked: transparent when nothing can be dispelled, so its dark rim goes too).
N.PaintDispel = ns.Timed("plates: dispel orbs", function(s, unit)
	local d = s.disp
	local n = 0
	d.plain = false
	if ns.P.frames.dispelGlow and ns.Auras and read(UnitExists, unit) then
		local kind, a, b = ns.Auras.Removables(unit)
		if kind == "plain" then
			d.plain = true
			for i = 1, math.min(#a, ORBS) do
				local c = a[i]
				d.orbs[i].dot:SetVertexColor(c[1], c[2], c[3], 1)
				d.orbs[i].ring:Show()
				n = i
			end
		elseif kind == "client" and ns.Auras.ClientColor(d.orbs[1].dot, unit, a, b) then
			d.orbs[1].ring:Hide()
			n = 1
		end
	end
	for i = 1, ORBS do d.orbs[i]:SetShown(i <= n) end
	d:SetShown(n > 0)
end)

-- A tag on the name line: a glyph with at most a number (Kit.Glyph: a shape and a
-- colour say it from the corner of the eye), or a short word.
local GLASS_TAG = { -- kind = { glyph, r, g, b }
	you = { "you", 1, 0.48, 0.42 }, healer = { "healer", 0.44, 0.94, 0.65 }, rare = { "rare", 0.85, 0.87, 0.91 },
	aggroIn = { "aggro", 1, 0.48, 0.42 }, aggroNear = { "aggro", 1, 0.72, 0.30 }, quest = { "quest", 1, 0.83, 0.37 },
	locked = { "locked", 0.73, 0.64, 1 }, targeted = { "you", 1, 0.48, 0.42 },
}
local GLASS_WORD = { owner = { "owner", "ff5c4d" }, hvt = { "HVT", "6ff0a6" }, faker = { "fake", "ffb84d" }, oom = { "OOM", "8fd3f2" } }
-- A tag: its glyph (with its number, where it has one) or its short word, coloured.
function N.Tag(kind, arg)
	-- (the plate being refreshed keeps which kinds it shows: the hover legend)
	if N.curKinds then N.curKinds[#N.curKinds + 1] = kind end
	local g = GLASS_TAG[kind]
	if g then
		local glyph = K.Glyph(g[1], g[2], g[3], g[4], 10)
		if arg then return format("%s|cff%02x%02x%02x%s|r", glyph, floor(g[2] * 255), floor(g[3] * 255), floor(g[4] * 255), arg) end
		return glyph
	end
	local w = GLASS_WORD[kind]
	if w then return "|cff" .. w[2] .. w[1] .. "|r" end
	return nil
end

-- Level, name, tags, target border, range fade and dispel border.
N.tagsBuf = {}
function N.Refresh(s)
	local unit, p = s.unit, P()
	-- the unit's facts, read once here for everything below (and Blizzard's hooks)
	local friend = isFriend(unit)
	s.friend, s.isPlayer, s.reaction = friend, read(UnitIsPlayer, unit), read(UnitReaction, unit, "player")
	local isTarget = N.Marked(unit, s) -- (your target, or the member whose frame the mouse is on)
	s.isTarget = isTarget
	s.mate = N.Mate(s)
	-- friendly plates: what you can dispel
	if friend and p.borders then N.PaintDispel(s, unit) else s.disp:Hide() end
	s.zenOn = N.Zen(s)
	s.zen = s.zenOn -- (the bar, its track and border gone: applyFade)
	s.svc = s.zenOn and ns.PlateNPC ~= nil and ns.PlateNPC.On(s) -- (not even the thin line)
	-- friend or foe at a glance: the name and the brackets in the reaction's colour
	-- (the bar itself keeps the class colour for players)
	local rc = N.Reaction(unit, s)
	if friend and s.isPlayer == false and read(UnitPlayerControlled, unit) ~= true then rc = NPC_NAME end
	for _, t in ipairs(s.sel.parts) do t:SetVertexColor(rc[1], rc[2], rc[3], 1) end
	if s.mate and P().mateRing ~= false then rc = MATE end -- (the brackets stay friend green)
	s.name:SetTextColor(rc[1], rc[2], rc[3])
	-- tags
	local tags = wipe(N.tagsBuf)
	s.kinds = s.kinds and wipe(s.kinds) or {}
	N.curKinds = s.kinds
	s.toughShown = nil
	if p.tags then
		if friend then
			if s.isPlayer then ns.Sensors.Tough(unit, s.guid) end
			local a = ns.Allies and ns.Allies.ForUnit(unit)
			if a and (a.focus or 0) > 0 then tags[#tags + 1] = N.Tag("targeted", a.focus) end
		else
			local c = contactOf(unit)
			if ns.Targeting.Is(unit, "player") then tags[#tags + 1] = N.Tag("you") end
			-- the owner of the pet you have targeted (click their plate to target them)
			local owner = ns.Targeting.petOwner
			if owner and s.isPlayer then
				local nm = read(GetUnitName, unit, false)
				if ns.Targeting.SameName(nm, owner) then tags[#tags + 1] = N.Tag("owner") end
			end
			if c and c.hvt then tags[#tags + 1] = N.Tag("hvt") end
			if ns.Targeting.IsHealer(c) or read(UnitGroupRolesAssigned, unit) == "HEALER" then tags[#tags + 1] = N.Tag("healer") end
			-- toughness: its health against its class and level
			local ratio, z = ns.Sensors.Tough(unit, s.guid)
			if c then c.tough = ratio end
			local tl, tr, tg, tb = ns.Sensors.ToughLabel(z)
			if tl then
				s.toughShown = true
				tl = tl == "LOW" and "HP-" or tl == "HIGH" and "HP+" or "HP++"
				tags[#tags + 1] = format("|cff%02x%02x%02x%s|r", floor(tr * 255), floor(tg * 255), floor(tb * 255), tl)
			end
			-- your interrupt locked its school; it fakes its casts
			local key = c and c.key or s.guid
			local lock = ns.Incoming.LockLeft(key)
			if lock then tags[#tags + 1] = N.Tag("locked", math.ceil(lock) .. "s") end
			if ns.Incoming.IsFaker(key) then tags[#tags + 1] = N.Tag("faker") end
		end
	end
	-- a rare NPC: RARE, and the alarm the first time it is seen
	if s.isPlayer == false then
		local cls = read(UnitClassification, unit)
		s.rare = cls == "rare" or cls == "rareelite"
		if s.rare then
			if p.tags then tags[#tags + 1] = N.Tag("rare") end
			if ns.HUD and ns.HUD.RareSeen then ns.HUD.RareSeen(unit, s.guid) end
		end
	end
	-- levelling: about to pull it
	local aggro = N.Aggro(s)
	if aggro then tags[#tags + 1] = N.Tag(aggro == "in" and "aggroIn" or "aggroNear") end
	-- an enemy healer nearly out of mana
	N.Mana(s)
	if s.manaLow and p.tags then tags[#tags + 1] = N.Tag("oom") end
	-- an NPC your quests need: a gold "!" with the count still open
	if p.questMobs and s.isPlayer == false and ns.Quests then
		local objective, title, count = ns.Quests.MobOf(unit, s.guid)
		if objective or title then tags[#tags + 1] = N.Tag("quest", count and (count:gsub("%s", ""))) end
	end
	N.curKinds = nil
	setLine(s.name, unit, p.level and not s.zenOn and N.LevelText(unit) or "", table.concat(tags, " "))
	N.Shift(s)
	N.Size(s)
	N.Health(s)
	s.sel:SetShown(isTarget)
	N.Beacon(s)
	N.PlaceText(s, isTarget)
	N.PaintDot(s, isTarget)
	if ns.PlateNPC then pcall(ns.PlateNPC.Paint, s) end
	-- (over the name line: after it is placed; never allowed to break the refresh)
	if ns.PlateAuras then pcall(ns.PlateAuras.Place, s) end
	s.faint = N.Faint(s)
	-- range: beyond your longest spell (helpful for friends, harmful for enemies)
	-- the bar fades; the same distance as the target's marker, for every plate
	s.far = p.rangeFade and N.Far(unit, friend) or false
	N.Kill(s)
	N.GroupFocus(s)
	N.Combo(s)
	-- an enemy player: the coral ring
	s.foe:SetShown(P().foeRing ~= false and not s.friend and s.isPlayer == true)
	paintHealth(s)
	hideBlizzard(s)
end

local function hook()
	if hooked then return end
	hooked = true
	if type(CompactUnitFrame_UpdateHealthColor) == "function" then
		-- runs inside Blizzard's update: never let an error escape into it
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(uf)
			local s = byUF[uf]
			if s and s.active then pcall(paintHealth, s) end
		end)
	end
	if type(CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", function(uf)
			local s = byUF[uf]
			if s and s.active then pcall(hideBlizzard, s) end
		end)
	end
end

-- Give the plate back to Blizzard.
local function detach(s)
	if not s.active then return end
	s.active = false
	s:Hide()
	if s.unit and N.skins[s.unit] == s then N.skins[s.unit] = nil end
	if ns.PlateAuras then pcall(ns.PlateAuras.Release, s) end
	if ns.PlateNPC then pcall(ns.PlateNPC.Release, s) end
	-- zen undone: Blizzard's bar back
	s.zenOn, s.zen = false, false
	s.thin:Hide()
	-- (the frame goes to another unit: its group focus worked out again)
	s.grp:Hide()
	s.grpN, s.grpTop = nil, nil
	pcall(N.ZenPaint, s)
	if s.origTex then pcall(s.hb.SetStatusBarTexture, s.hb, s.origTex) end
	if s.bname then pcall(s.bname.SetAlpha, s.bname, 1) end
	if s.bcastBox then pcall(s.bcastBox.SetAlpha, s.bcastBox, 1) end
	for _, d in ipairs(s.decor or {}) do pcall(d.SetAlpha, d, 1) end
	for _, m in ipairs(s.masks or {}) do pcall(m[1].AddMaskTexture, m[1], m[2]) end
	s.masks = {}
	s.track:Hide()
	unshift(s)
	pcall(s.hb.SetAlpha, s.hb, 1)
	if s.uf then pcall(s.uf.SetAlpha, s.uf, 1) end
	s.faint = false
	s:SetAlpha(1)
	s.big:Hide()
	s.kill:Hide()
	if s.kill.pulse then s.kill.pulse:Stop() end
	s.mana:Hide()
	s.mateRing:Hide()
	s.mate = nil
	s.beacon:Hide()
	if s.beacon.pulse then s.beacon.pulse:Stop() end
	s.isBig, s.sizeKey = false, nil
	ns.Heals.FeedTo(s.healN, nil)
	ns.Heals.FeedTo(s.healB, nil)
	if s.uf and type(CompactUnitFrame_UpdateHealthColor) == "function" then pcall(CompactUnitFrame_UpdateHealthColor, s.uf) end
end

function N.Attach(unit)
	local old = N.skins[unit]
	if old then detach(old) end
	if not N.Wants(unit) or not C_NamePlate then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate or ns.isSecret(plate) then return nil end
	if plate.IsForbidden then
		local okF, forbidden = pcall(plate.IsForbidden, plate)
		if not okF or forbidden then return nil end
	end
	-- a plate frame keeps its parts when the game hands it to the next unit: found once
	local s = byPlate[plate]
	local uf, hb, bname, bcast, bcastBox
	if s and s.uf then uf, hb, bname, bcast, bcastBox = s.uf, s.hb, s.bname, s.bcast, s.bcastBox
	else uf, hb, bname, bcast, bcastBox = partsOf(plate) end
	if not hb then return nil end
	if not s then
		s = build(plate, hb)
		byPlate[plate] = s
		local okT, tex = pcall(function() return hb:GetStatusBarTexture():GetTexture() end)
		s.origTex = okT and not ns.isSecret(tex) and tex or nil
		if bcast and bcast.HookScript then
			-- Blizzard shows its own cast bar on every cast; SITREP's replaces it
			pcall(bcast.HookScript, bcast, "OnShow", function(self)
				local sk = byPlate[plate]
				if sk and sk.active and N.Wants(sk.unit, "cast") then self:Hide() end
			end)
		end
	end
	hook()
	-- the game hands a plate frame leaving the screen to a new unit, often before it
	-- says the old one is gone (all the time with "show nameplates off-screen"):
	-- the old unit must stop pointing at this skin
	if s.unit and s.unit ~= unit and N.skins[s.unit] == s then N.skins[s.unit] = nil end
	s.unit, s.uf, s.hb, s.bname, s.bcast, s.bcastBox = unit, uf, hb, bname, bcast, bcastBox
	if s.decorOf ~= uf then s.decor, s.decorOf = decorOf(uf, hb), uf end
	s.masks = s.masks or {}
	s.guid = read(UnitGUID, unit)
	if ns.Quests then ns.Quests.ForgetMob(unit) end
	byUF[uf] = s
	N.skins[unit] = s
	s.active = true
	s:Show()
	N.Refresh(s)
	s.drawnAt = GetTime()
	if P().cast then ns.Units.UpdateCast(s, unit); wake(s) else s.cast:Hide() end
	return s
end

function N.Detach(unit)
	local s = N.skins[unit]
	if not s then return end
	-- (a skin taken over by another unit since: only forget the old name for it)
	if s.unit == unit then detach(s) else N.skins[unit] = nil end
end

-- The skins and the units they show now (an entry left by a reused frame is skipped).
local function current()
	local out = {}
	for unit, s in pairs(N.skins) do if s.unit == unit and s.active then out[unit] = s end end
	return out
end
N.Current = current

-- Settings changed: re-dress every plate on screen.
function N.ApplyAll()
	for u in pairs(ns.Sensors._plates or {}) do N.Attach(u) end
	for u, s in pairs(N.skins) do
		if not (ns.Sensors._plates or {})[u] then
			if s.unit == u then detach(s) else N.skins[u] = nil end
		end
	end
end

---------------------------------------------------------------------------
-- The plates' size: the game's own setting (SITREP's look sits on the plates and
-- scales with them). Touched only once you change it, out of combat only.
-- the size settings clients have had (each one that exists here is set)
local SCALE_CVARS = { "nameplateGlobalScale", "NamePlateHorizontalScale", "NamePlateVerticalScale" }
N.SCALE_CVARS = SCALE_CVARS
local function getCVar(k)
	if C_CVar and C_CVar.GetCVar then local ok, v = pcall(C_CVar.GetCVar, k) if ok then return v end end
	if GetCVar then local ok, v = pcall(GetCVar, k) if ok then return v end end
	return nil
end
local function setCVar(k, v)
	if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, k, v) end
	if SetCVar then return pcall(SetCVar, k, v) end
	return false
end
N.GetCVar = getCVar
function N.ApplyScale()
	if InCombatLockdown() then N.scalePending = true return end
	local want = (P().enabled and ns.P.enabled) and (P().scale or 1) or 1
	if want == 1 and not (SITREP_DB and SITREP_DB.plateScaleSet) then return end
	N.scaleSet = {}
	for _, k in ipairs(SCALE_CVARS) do
		if getCVar(k) ~= nil and setCVar(k, tostring(want)) then N.scaleSet[#N.scaleSet + 1] = k end
	end
	if SITREP_DB then SITREP_DB.plateScaleSet = want ~= 1 or nil end
end

-- How far plates reach (plates.reach, yards; 0: the game's own): the client's
-- nameplateMaxDistance. RESTING since 4.7.6: on Forever plates end at about
-- 28-30 yd whatever it is set to (measured at 80, 4.7.5: FOREVER-API.md), so the
-- choice is off the Nameplates page and its command and default are gone; with
-- no plates.reach the game's own value (kept in SITREP_DB.plateReachOrig) goes
-- back at the next login. Should a later Forever release lift the cap: put
-- reach = 0 back into the defaults and the dropdown back on the page.
-- Out of combat only (protected).
N.REACH_CVAR = "nameplateMaxDistance"
function N.ApplyReach()
	if InCombatLockdown() then N.reachPending = true return end
	local want = (P().enabled and ns.P.enabled) and (P().reach or 0) or 0
	local db = SITREP_DB
	if not db then return end
	local cur = getCVar(N.REACH_CVAR)
	if cur == nil then return end -- (this client has no such setting)
	if want > 0 then
		if db.plateReachOrig == nil then db.plateReachOrig = cur end
		if tonumber(cur) ~= want then
			setCVar(N.REACH_CVAR, tostring(want))
			if ns.Spawns then ns.Spawns.reach = 0 end -- (measured again from here)
		end
	elseif db.plateReachOrig ~= nil then
		setCVar(N.REACH_CVAR, db.plateReachOrig)
		db.plateReachOrig = nil
		if ns.Spawns then ns.Spawns.reach = 0 end
	end
end

ns.On("SR_LOGIN", function() N.ApplyScale(); N.ApplyReach() end)
ns.On("PLAYER_REGEN_ENABLED", function()
	if N.scalePending then N.scalePending = false; N.ApplyScale() end
	if N.reachPending then N.reachPending = false; N.ApplyReach() end
end)

-- Events
---------------------------------------------------------------------------
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) N.Attach(unit) end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) N.Detach(unit) end)
ns.On("FORBIDDEN_NAME_PLATE_UNIT_ADDED", function(_, unit) N.Detach(unit) end)

-- Which plates are redrawn in full on a tick: a time budget, spent by priority.
-- The cost grows with the plates on screen (a town, the middle of a battleground),
-- not with the map: so SITREP gives itself a budget per tick and spends it on the
-- plates that matter most, each wanting a redraw this often (seconds):
--   0     your target, an enemy that just started targeting you
--   0.15  enemy players on you, in reach of you, closing, healers, the HVT
--   0.3   other enemy players
--   0.5   friendly players in combat (heal range, TARGETED n), mobs on you
--   1.5   friendly players out of combat, mobs, friendly NPCs (2 out of combat)
-- When there is more to do than the budget allows, the plates most overdue for
-- their own interval come first (a low priority plate waiting long enough beats a
-- high one that was just drawn), so nothing starves. Your target is drawn every
-- tick whatever the budget. Health, heals, casts and the target mark come by event
-- in between, outside the budget.
N.BUDGET_MS = 0.4 -- per tick (ten ticks a second: at most ~4 ms a second)
N.MIN_PER_TICK = 2 -- drawn per tick even over budget (a slow frame must not stall them)
N.stats = { drawn = 0, deferred = 0, maxLate = 0 }
local clock = debugprofilestop or function() return GetTime() * 1000 end
local queue = {}

function N.Interval(s, combat)
	if s.urgent or s.isTarget then return 0 end
	if s.isPlayer and not s.friend then
		local c = s.guid and ns.Sensors.contacts[s.guid]
		if c and (c.targetingMe or c.inTheirReach or c.inMyReach or c.closing or c.healer or c.hvt) then return 0.15 end
		return 0.3
	end
	if s.friend and s.isPlayer then return combat and 0.5 or 1.5 end
	if combat and not s.friend then return 0.5 end
	-- hostile mobs while you walk among them (the aggro radar: 0.4 s is 3 yd at a run)
	if not combat and not s.friend and s.reaction and s.reaction <= 3 and P().aggroRadar then return 0.4 end
	return combat and 1.5 or 2
end

local function byLateness(a, b) return a.late > b.late end
function N.Tick(now)
	now = now or GetTime()
	local combat = InCombatLockdown() or (ns.Sensors.self and ns.Sensors.self.combat) or false
	local n = 0
	for unit, s in pairs(N.skins) do
		if s.unit == unit and s.active then
			local iv = N.Interval(s, combat)
			local since = now - (s.drawnAt or 0)
			if since >= iv then
				-- how overdue, in its own intervals (0: due every tick)
				s.late = iv > 0 and since / iv or math.huge
				n = n + 1
				queue[n] = s
			end
		end
	end
	for i = #queue, n + 1, -1 do queue[i] = nil end
	if n > 1 then table.sort(queue, byLateness) end
	local st = N.stats
	local t0 = clock()
	local drawn = 0
	for i = 1, n do
		local s = queue[i]
		if s.late ~= math.huge and drawn >= N.MIN_PER_TICK and clock() - t0 >= N.BUDGET_MS then
			st.deferred = st.deferred + (n - i + 1)
			break
		end
		if read(UnitExists, s.unit) then
			local late = now - (s.drawnAt or now)
			if late > st.maxLate and s.drawnAt then st.maxLate = late end
			local ok, err = pcall(N.Refresh, s)
			if not ok then ns.error(err) end
			s.drawnAt, s.urgent = now, nil
			drawn = drawn + 1
		end
	end
	st.drawn = st.drawn + drawn
	for i = 1, n do queue[i] = nil end
end
ns.On("SR_TICK", function() N.Tick() end)
ns.On("SR_LOCKOUT", function(_, key)
	for unit, s in pairs(N.skins) do
		if s.unit == unit and s.guid == key then s.urgent = true end
	end
end)
ns.On("SR_TARGETED", function(_, c)
	local s = c.unit and N.skins[c.unit]
	if s then s.urgent = true end
end)

-- A plate drawn as your target's: your target, or the unit whose frame the mouse is
-- on (N.highlight: hovering a party member's frame finds its plate at a glance).
local function hovered(unit, s)
	local h = N.highlight
	if not h then return false end
	if read(UnitIsUnit, unit, h) == true then return true end
	local g = read(UnitGUID, h) -- (the comparison may be secret in combat: the GUID)
	return g ~= nil and s.guid == g
end
local function marked(unit, s)
	if read(UnitIsUnit, unit, "target") == true then return true end
	return hovered(unit, s)
end
N.Hovered = hovered

-- The plate of the member whose frame the mouse is on: on top of the target's look,
-- the beacon pulsing round it (s.beacon).
function N.Beacon(s)
	local on = hovered(s.unit, s) and true or false
	if on ~= (s.beacon:IsShown() and true or false) then
		s.beacon:SetShown(on)
		if s.beacon.pulse then if on then s.beacon.pulse:Play() else s.beacon.pulse:Stop() end end
	end
end

N.Marked = marked

local function paintTargets()
	for unit, s in pairs(current()) do
		local isTarget = marked(unit, s)
		s.isTarget = isTarget
		N.Size(s)
		s.sel:SetShown(isTarget)
		N.Beacon(s)
		N.PlaceText(s, isTarget)
		N.PaintDot(s, isTarget)
		if ns.PlateAuras then pcall(ns.PlateAuras.Place, s) end -- (your target's a little larger)
		s.faint = N.Faint(s)
		hideBlizzard(s)
		-- zen (and an NPC's look) ends on your target and starts again when it is not
		if (s.friend or s.isPlayer == false) and N.Zen(s) ~= (s.zenOn or false) then N.Refresh(s) end
	end
end
ns.On("PLAYER_TARGET_CHANGED", paintTargets)
-- someone joins or leaves your group: their ring (and zen bar) comes or goes
ns.On("GROUP_ROSTER_UPDATE", function()
	for _, s in pairs(current()) do
		if s.friend and (N.Zen(s) ~= (s.zenOn or false) or N.Mate(s) ~= (s.mate or false)) then N.Refresh(s) end
	end
end)
-- into and out of combat: friendly players shrink and grow back
local function resizeAll()
	for unit, s in pairs(N.skins) do
		if s.unit == unit and s.active then
			local ok, err = pcall(N.Size, s)
			if not ok then ns.error(err) end
			pcall(hideBlizzard, s)
		end
	end
end
ns.On("PLAYER_REGEN_DISABLED", resizeAll)
ns.On("PLAYER_REGEN_ENABLED", resizeAll)

-- Draw this unit's plate as a target's while the mouse is on its frame (nil: stop).
function N.Highlight(unit)
	N.highlight = unit
	paintTargets()
end

for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
	ns.On(e, function(_, unit)
		local s = N.skins[unit]
		if s and s.unit == unit and P().cast then ns.Units.UpdateCast(s, unit); wake(s) end
	end)
end

-- The health as it changes (SITREP's own bar when bigger) and heals on their way
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION" }) do
	ns.On(e, function(_, unit)
		local s = N.skins[unit]
		if s and s.unit == unit and s.active then
			N.Health(s)
			if s.isPlayer and not s.friend then N.Kill(s) end
		end
	end)
end

-- mana as it changes, on the plates that show it
ns.On("UNIT_POWER_UPDATE", function(_, unit)
	local s = N.skins[unit]
	if s and s.unit == unit and s.active and s.mana:IsShown() then pcall(feedMana, s) end
end)

ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 7) == "plates." then N.ApplyAll(); N.ApplyScale(); N.ApplyReach() end
end)

-- combo points change, or your target does: the target's plate again
local function comboAll()
	for u, s in pairs(N.skins) do
		if s.active and s.unit == u then N.Combo(s) end
	end
end
ns.On("PLAYER_TARGET_CHANGED", comboAll)
ns.On("UNIT_POWER_UPDATE", function(_, unit) if unit == "player" then comboAll() end end)
ns.On("PLAYER_COMBO_POINTS", comboAll)
