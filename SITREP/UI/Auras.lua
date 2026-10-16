-- SITREP · Auras on the unit frames
--
--   Player frame  your debuffs. Outlined in the accent colour when YOUR class can
--                 remove that type; the rest are dimmed. Removable first.
--   Target frame  enemy: its buffs (outlined when you can purge them, red when it
--                 is a big defensive, gold glow when it lasts only seconds: the
--                 cooldowns that win fights) and its debuffs (yours bright).
--                 Ally: its debuffs, outlined when you can cleanse them.
--                 Its buffs over the frame, its debuffs under it.
--
-- Every border is coloured by dispel type: blue magic, purple curse, brown
-- disease, green poison, orange enrage.
--
-- Forever locks aura data in combat ("Auras cannot be accessed when secret").
-- So each aura goes down a chain and stops at the first path that works:
--   1. plain data            icon, timer, stacks, type: all read and cached by ID
--   2. cache                 an aura seen before combat keeps what we learned
--   3. client-rendered       timer from a duration object, border and "can I
--                            remove it" from GetAuraDispelTypeColor with colour
--                            curves; the addon never sees the type itself
--   4. locked                a dark slot marked "?", never a guess
-- Which paths worked is counted in Auras.stats for the diagnostics.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read, plain = ns.read, ns.plain
local floor = math.floor
local issecrettable = _G.issecrettable or function() return false end

local A = {}
ns.Auras = A
A.stats = { idsPlain = 0, idsLocked = 0, dataPlain = 0, dataCached = 0, dataLocked = 0,
	timerObject = 0, timerPlain = 0, colorClient = 0, colorPlain = 0 }

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

---------------------------------------------------------------------------
-- Doctrine: dispel types and who removes what (level-60 kits).
---------------------------------------------------------------------------
local D = ns.Data
D.DISPEL_COLOR = {
	Magic = { 0.20, 0.60, 1.00 }, Curse = { 0.64, 0.19, 0.79 }, Disease = { 0.60, 0.40, 0.00 },
	Poison = { 0.00, 0.60, 0.00 }, Enrage = { 1.00, 0.45, 0.10 }, none = { 0.25, 0.27, 0.28 },
}
-- Dispel type ids as the client numbers them for colour curves.
D.DISPEL_ID = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Enrage = 9 }
-- Removing a debuff from yourself or an ally.
D.CLEANSE = {
	PRIEST = { Magic = true, Disease = true },
	PALADIN = { Magic = true, Poison = true, Disease = true },
	SHAMAN = { Poison = true, Disease = true },
	DRUID = { Curse = true, Poison = true },
	MAGE = { Curse = true },
	WARLOCK = { Magic = true }, -- Felhunter: Devour Magic
}
-- Stripping a buff from an enemy.
D.PURGE = {
	PRIEST = { Magic = true },   -- Dispel Magic
	SHAMAN = { Magic = true },   -- Purge
	WARLOCK = { Magic = true },  -- Felhunter: Devour Magic
	HUNTER = { Enrage = true },  -- Tranquilizing Shot
}

---------------------------------------------------------------------------
-- Colour curves: let the client map a (possibly secret) dispel type to a colour.
---------------------------------------------------------------------------
local curves = {}

local function makeCurve(colorFor)
	local CU = C_CurveUtil
	if not (CU and CU.CreateColorCurve and CreateColor) then return nil end
	local ok, curve = pcall(function()
		local c = CU.CreateColorCurve()
		local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
		if step then c:SetType(step) end
		c:AddPoint(0, CreateColor(0, 0, 0, 0))
		local ids = {}
		for name, id in pairs(D.DISPEL_ID) do ids[#ids + 1] = { id, name } end
		table.sort(ids, function(a, b) return a[1] < b[1] end)
		for _, e in ipairs(ids) do
			local col = colorFor(e[2])
			c:AddPoint(e[1], CreateColor(col[1], col[2], col[3], col[4] or 1))
		end
		return c
	end)
	return ok and curve or nil
end

local function rebuildCurves()
	local class = ns.Sensors.self.class
	local ar, ag, ab = K.Accent()
	local none = { 0, 0, 0, 0 }
	curves.type = makeCurve(function(name) return D.DISPEL_COLOR[name] or D.DISPEL_COLOR.none end)
	local cleanse, purge = D.CLEANSE[class] or {}, D.PURGE[class] or {}
	curves.cleanse = makeCurve(function(name) return cleanse[name] and { ar, ag, ab, 1 } or none end)
	curves.purge = makeCurve(function(name) return purge[name] and { ar, ag, ab, 1 } or none end)
	-- the debuff's own colour when you can remove it, transparent when not
	curves.cleanseType = makeCurve(function(name)
		return cleanse[name] and (D.DISPEL_COLOR[name] or D.DISPEL_COLOR.none) or none
	end)
	curves.class = class
end
A.RebuildCurves = rebuildCurves

-- Paint a texture from the client's verdict on an aura's dispel type.
local function clientColor(tex, unit, id, curve)
	if not (curve and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor) then return false end
	return pcall(function() tex:SetVertexColor(C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve):GetRGBA()) end)
end

---------------------------------------------------------------------------
-- Reading auras
---------------------------------------------------------------------------
local cache = {} -- [auraInstanceID] = { icon, dispel, spellId, mine, stealable, name }

-- Aura instance IDs for a unit and filter, or nil when the client locks the list.
local function auraIDs(unit, filter)
	local U = C_UnitAuras
	if not U then return nil end
	if U.GetUnitAuraInstanceIDs then
		local ok, ids = pcall(U.GetUnitAuraInstanceIDs, unit, filter)
		if ok and type(ids) == "table" and not issecrettable(ids) then
			local out = {}
			for i = 1, #ids do
				local id = plain(ids[i])
				if id then out[#out + 1] = id end
			end
			return out
		end
	end
	-- Older path: walk by index (also fills the cache while data is readable).
	if U.GetAuraDataByIndex then
		local out = {}
		for i = 1, 40 do
			local ok, d = pcall(U.GetAuraDataByIndex, unit, i, filter)
			if not ok then return #out > 0 and out or nil end
			if not d then break end
			local id = not issecrettable(d) and plain(d.auraInstanceID)
			if id then out[#out + 1] = id end
		end
		return out
	end
	return nil
end
A.AuraIDs = auraIDs

-- Plain facts about one aura, from the client if it allows, else from the cache.
local function auraFacts(unit, id)
	local U = C_UnitAuras
	local ok, d = pcall(U.GetAuraDataByAuraInstanceID, unit, id)
	if ok and type(d) == "table" and not issecrettable(d) then
		local icon = plain(d.icon)
		if icon then
			local f = cache[id] or {}
			f.icon, f.dispel, f.spellId = icon, plain(d.dispelName), plain(d.spellId)
			f.name = plain(d.name)
			f.stacks = plain(d.applications) or 0
			f.duration, f.expires = plain(d.duration), plain(d.expirationTime)
			local src = plain(d.sourceUnit)
			f.mine = src == "player" or src == "pet" or plain(d.isFromPlayerOrPlayerPet) == true
			f.stealable = plain(d.isStealable) == true
			f.plain = true
			cache[id] = f
			A.stats.dataPlain = A.stats.dataPlain + 1
			return f
		end
	end
	local f = cache[id]
	if f then
		f.plain = false
		A.stats.dataCached = A.stats.dataCached + 1
		return f
	end
	A.stats.dataLocked = A.stats.dataLocked + 1
	return nil
end

A.ClientColor = clientColor

-- Does the unit carry a debuff you can remove? Returns
--   "plain", colour            when SITREP can read it (colour of that debuff's type),
--   "client", auraID, curve    when the data is locked: the client paints it,
--   nil                        when not (or your class removes nothing).
-- Locked data: the client's own "HARMFUL|RAID" list (what you can dispel) is
-- asked first; failing that, the first debuff is coloured by the client and
-- shows only if it is removable.
-- A.Removables: the same, with every kind you can remove when readable:
--   "plain", { colour, ... }   one colour per kind (Curse, Poison, ...), in the order found
function A.Removables(unit)
	local class = ns.Sensors.self.class
	local t = D.CLEANSE[class]
	if not t then return nil end
	local ids = auraIDs(unit, "HARMFUL")
	local locked, out, seen = nil, nil, nil
	for _, id in ipairs(ids or {}) do
		local f = auraFacts(unit, id) -- plain, or from the cache (a dispel type never changes)
		if f and f.dispel then
			if t[f.dispel] and not (seen and seen[f.dispel]) then
				out, seen = out or {}, seen or {}
				seen[f.dispel] = true
				out[#out + 1] = D.DISPEL_COLOR[f.dispel] or D.DISPEL_COLOR.none
			end
		elseif not f then
			locked = locked or id
		end
	end
	if out then return "plain", out end
	if ids and not locked then return nil end
	local raid = auraIDs(unit, "HARMFUL|RAID")
	if raid then
		if raid[1] and curves.type then return "client", raid[1], curves.type end
		return nil
	end
	if locked and curves.cleanseType then return "client", locked, curves.cleanseType end
	return nil
end
-- The debuffs on a unit you can remove, readable ones only: { { name, dispel }, ... }
-- (locked data: none; the dispel orb on its plate still shows what the client knows).
function A.RemovableAuras(unit)
	local t = D.CLEANSE[ns.Sensors.self.class]
	local out = {}
	if not t then return out end
	for _, id in ipairs(auraIDs(unit, "HARMFUL") or {}) do
		local f = auraFacts(unit, id)
		if f and f.dispel and t[f.dispel] then out[#out + 1] = { name = f.name, dispel = f.dispel } end
	end
	return out
end

function A.Removable(unit)
	local kind, a, b = A.Removables(unit)
	if kind == "plain" then return "plain", a[1] end
	return kind, a, b
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
local timerFonts = {}
-- Countdown text sized to the icon: 9 on a 22 px icon, 8 on 18 px.
function A.TimerFont(size)
	if timerFonts[size] then return timerFonts[size] end
	if not CreateFont then return nil end
	local name = "SITREP_AuraTimer" .. size
	local ok, fo = pcall(CreateFont, name)
	if not ok or not fo then return nil end
	fo:SetFont(K.FONT, size >= 22 and 9 or 8, "OUTLINE")
	timerFonts[size] = name
	return name
end
local function newSlot(parent, size)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(size, size)
	-- short buff (burst or defensive cooldown): a gold halo behind everything
	s.burst = K.Tex(s, "BACKGROUND", { 1, 0.78, 0.2, 0.75 }, -2)
	s.burst:SetPoint("TOPLEFT", -5, 5)
	s.burst:SetPoint("BOTTOMRIGHT", 5, -5)
	s.burst:Hide()
	-- removal outline sits outside the type border
	s.can = CreateFrame("Frame", nil, s)
	s.can:SetPoint("TOPLEFT", -3, 3)
	s.can:SetPoint("BOTTOMRIGHT", 3, -3)
	K.Border(s.can, { 1, 1, 1, 1 }, 2)
	s.border = K.Tex(s, "BACKGROUND")
	s.border:SetPoint("TOPLEFT", -1, 1)
	s.border:SetPoint("BOTTOMRIGHT", 1, -1)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetAllPoints()
	s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
	s.cd:SetAllPoints()
	if s.cd.SetDrawEdge then s.cd:SetDrawEdge(false) end
	if s.cd.SetReverse then s.cd:SetReverse(true) end
	-- a smaller countdown than the client's default
	local font = A.TimerFont(size)
	if font and s.cd.SetCountdownFont then pcall(s.cd.SetCountdownFont, s.cd, font) end
	s.timerSize = size
	s.count = K.Font(s, 10, C.text, K.FONT, "OUTLINE", "OVERLAY")
	s.count:SetPoint("BOTTOMRIGHT", 1, 0)
	s.big = K.Font(s, 12, { 1, 0.3, 0.2, 1 }, K.FONT, "OUTLINE", "OVERLAY")
	s.big:SetPoint("TOPLEFT", 1, 1)
	s:EnableMouse(true)
	s:SetScript("OnEnter", function(self)
		if not (GameTooltip and self.unit and self.id) then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		local ok = GameTooltip.SetUnitAuraByAuraInstanceID and pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.id)
		if not ok then GameTooltip:SetText(self.label or "Aura", 1, 1, 1) end
		if self.removable then GameTooltip:AddLine("You can remove this.", K.Accent()) end
		GameTooltip:Show()
	end)
	s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	s:Hide()
	return s
end

-- mode: "cleanse" (debuffs on you or an ally), "purge" (an enemy's buffs),
--       "mine" (debuffs on an enemy: yours bright)
-- Total length of an aura in seconds (0 = permanent), or nil when secret.
local function totalDuration(unit, id, f)
	if f and f.plain and f.duration then return f.duration end
	local U = C_UnitAuras
	if U.GetAuraBaseDuration then
		local d = read(U.GetAuraBaseDuration, unit, id)
		if type(d) == "number" then return d end
	end
	local obj = U.GetAuraDuration and read(U.GetAuraDuration, unit, id)
	if obj then
		local ok, t = pcall(function() return obj:GetTotalDuration() end)
		t = ok and plain(t)
		if type(t) == "number" then return t end
	end
	return f and f.duration or nil
end
A.TotalDuration = totalDuration

local function isBurst(unit, id, f)
	local t = totalDuration(unit, id, f)
	return t ~= nil and t > 0 and t <= ns.P.frames.burstMax
end

local function fillSlot(s, unit, id, f, mode, class)
	s.unit, s.id = unit, id
	s.label = f and f.name
	-- icon
	s.icon:SetTexture(f and f.icon or QUESTION)
	s.icon:SetDesaturated(not f)
	-- timer: the client's duration object first, plain numbers second
	local timed = false
	local dur = C_UnitAuras.GetAuraDuration and read(C_UnitAuras.GetAuraDuration, unit, id)
	if dur and s.cd.SetCooldownFromDurationObject and pcall(s.cd.SetCooldownFromDurationObject, s.cd, dur) then
		timed = true
		A.stats.timerObject = A.stats.timerObject + 1
	elseif f and f.plain and f.duration and f.duration > 0 and f.expires then
		s.cd:SetCooldown(f.expires - f.duration, f.duration)
		timed = true
		A.stats.timerPlain = A.stats.timerPlain + 1
	end
	if not timed and s.cd.Clear then s.cd:Clear() end
	s.count:SetText(f and f.stacks and f.stacks > 1 and f.stacks or "")

	-- type border and "can I remove it"
	local removable
	local table_ = mode == "purge" and (D.PURGE[class] or {}) or (D.CLEANSE[class] or {})
	if f and f.plain then
		local col = D.DISPEL_COLOR[f.dispel or "none"] or D.DISPEL_COLOR.none
		s.border:SetVertexColor(col[1], col[2], col[3], 1)
		removable = (mode == "cleanse" or mode == "purge") and f.dispel and table_[f.dispel] or false
		if mode == "purge" and class == "MAGE" and f.stealable then removable = true end
		local ar, ag, ab = K.Accent()
		s.can.border:SetColor(ar, ag, ab, removable and 1 or 0)
		A.stats.colorPlain = A.stats.colorPlain + 1
	else
		-- secret: the client colours both from the type it alone can see
		if clientColor(s.border, unit, id, curves.type) then
			A.stats.colorClient = A.stats.colorClient + 1
		else
			local n = D.DISPEL_COLOR.none
			s.border:SetVertexColor(n[1], n[2], n[3], 1)
		end
		local curve = mode == "purge" and curves.purge or mode == "cleanse" and curves.cleanse or nil
		local painted = false
		if curve then
			painted = true
			for i = 1, 4 do
				if not clientColor(s.can.border[i], unit, id, curve) then painted = false break end
			end
		end
		if not painted then s.can.border:SetColor(0, 0, 0, 0) end
		removable = nil -- unknown to the addon; the outline (if any) is the client's answer
	end
	s.removable = removable

	-- emphasis
	local big = false
	if mode == "purge" and f and f.spellId and C_UnitAuras.AuraIsBigDefensive then
		big = read(C_UnitAuras.AuraIsBigDefensive, f.spellId) == true
	end
	s.big:SetText(big and "!" or "")
	if big then s.border:SetVertexColor(1, 0.25, 0.15, 1) end
	local burst = (mode == "purge" or mode == "none") and ns.P.frames.burst and isBurst(unit, id, f) or false
	s.burst:SetShown(burst)
	s.isBurst = burst
	if mode == "mine" then s:SetAlpha(f and f.mine and 1 or (f and 0.5 or 0.8))
	elseif removable == false then s:SetAlpha(0.7)
	else s:SetAlpha(1) end
	s:Show()
	return removable, big
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function newRow(parent, size, n)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(n * (size + 4), size + 6)
	row.slots = {}
	for i = 1, n do
		local s = newSlot(row, size)
		s:SetPoint("LEFT", (i - 1) * (size + 4) + 3, 0)
		row.slots[i] = s
	end
	row.locked = K.Font(row, 10, C.faint, K.FONT, "")
	row.locked:SetPoint("LEFT", 3, 0)
	row.locked:SetText("AURAS LOCKED BY THE CLIENT")
	row.locked:Hide()
	return row
end

-- Fill a row; returns how many slots were used.
local function fillRow(row, unit, filter, mode)
	local class = ns.Sensors.self.class
	local ids = auraIDs(unit, filter)
	if not ids then
		A.stats.idsLocked = A.stats.idsLocked + 1
		for _, s in ipairs(row.slots) do s:Hide() end
		row.locked:Show()
		return 0
	end
	A.stats.idsPlain = A.stats.idsPlain + 1
	row.locked:Hide()
	-- read everything first so removable / big defensive / mine can lead
	local items = {}
	for _, id in ipairs(ids) do items[#items + 1] = { id = id, f = auraFacts(unit, id) } end
	local function rank(it)
		local f = it.f
		if not (f and f.plain) then return 1 end
		if mode == "purge" or mode == "none" then
			local big = f.spellId and C_UnitAuras.AuraIsBigDefensive and read(C_UnitAuras.AuraIsBigDefensive, f.spellId)
			if big then return 0 end
			if ns.P.frames.burst and f.duration and f.duration > 0 and f.duration <= ns.P.frames.burstMax then return 0.25 end
			local t = D.PURGE[class] or {}
			return (mode == "purge" and f.dispel and t[f.dispel]) and 0.5 or 2
		elseif mode == "mine" then
			return f.mine and 0 or 2
		end
		local t = D.CLEANSE[class] or {}
		return (f.dispel and t[f.dispel]) and 0 or 2
	end
	for i, it in ipairs(items) do it.order, it.rank = i, rank(it) end
	table.sort(items, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.order < b.order end)
	local n = 0
	for i, s in ipairs(row.slots) do
		local it = items[i]
		if it then fillSlot(s, unit, it.id, it.f, mode, class); n = n + 1 else s:Hide() end
	end
	return n
end
A.FillRow = fillRow

---------------------------------------------------------------------------
-- Wiring onto the unit frames
---------------------------------------------------------------------------
local rows = {}

function A.Build()
	local Fr = ns.Frames.frames
	if not (Fr.player and Fr.target) then return end
	local P = ns.P.frames
	local perRow = floor((P.width + 4) / 26)
	rows.player = newRow(Fr.player, 22, perRow)
	rows.player:SetPoint("TOPLEFT", Fr.player, "BOTTOMLEFT", -3, -4)
	-- the target's debuffs right under its pane, which ends under its last row
	-- (FrameTarget's FitPane): they move up and down with it; its buffs over the
	-- pane (its top stays where it is). Both about 4 px off the glass (a row has
	-- 3 px of air above and below its icons).
	local pane = Fr.target.bg and K.Region(Fr.target.bg) or Fr.target
	rows.targetDebuffs = newRow(Fr.target, 22, perRow)
	rows.targetDebuffs:SetPoint("TOPLEFT", pane, "BOTTOMLEFT", -3, -1)
	rows.targetBuffs = newRow(Fr.target, 18, floor((P.width + 4) / 22))
	rows.targetBuffs:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", -3, 1)
	-- party members: debuffs inside each frame, the ones you can remove first
	for i, m in ipairs(ns.Frames.partyMembers or {}) do
		local r = newRow(m, 15, 8)
		r:SetPoint("TOPLEFT", m, "TOPLEFT", 5, -48)
		rows["party" .. i] = r
	end
	A.rows = rows
	rebuildCurves()
end

function A.Update(which)
	if not rows.player then return end
	local P = ns.P.frames
	if curves.class ~= ns.Sensors.self.class then rebuildCurves() end
	if (which == nil or which == "player") then
		local show = P.myDebuffs and ns.Frames.frames.player:IsShown()
		rows.player:SetShown(show)
		if show then fillRow(rows.player, "player", "HARMFUL", "cleanse") end
		ns.Units.PaintDispel(ns.Frames.frames.player, "player")
	end
	if (which == nil or which == "target") then
		local exists = read(UnitExists, "target")
		local show = P.targetAuras and exists -- rows live inside the target frame and hide with it
		rows.targetDebuffs:SetShown(show and true or false)
		rows.targetBuffs:SetShown(show and true or false)
		if show then
			if ns.Sensors.IsEnemy("target") then -- enemy players, pets and NPCs
				fillRow(rows.targetDebuffs, "target", "HARMFUL", "mine")
				fillRow(rows.targetBuffs, "target", "HELPFUL", "purge")
			else
				fillRow(rows.targetDebuffs, "target", "HARMFUL", "cleanse")
				fillRow(rows.targetBuffs, "target", "HELPFUL", "none")
			end
		end
	end
	for i = 1, 4 do
		local unit, r = "party" .. i, rows["party" .. i]
		if r and (which == nil or which == unit) then
			local show = P.party and read(UnitExists, unit) and true or false
			r:SetShown(show)
			if show then fillRow(r, unit, "HARMFUL", "cleanse") end
			local m = ns.Frames.partyMembers[i]
			ns.Units.PaintDispel(m, unit)
			if m and m.orbs then ns.Units.PaintOrbs(m.orbs, unit) end
		end
	end
end

ns.On("SR_LOGIN", function() A.Build(); A.Update() end)
ns.On("SR_TICK", function() A.Update() end)
ns.On("PLAYER_TARGET_CHANGED", function() A.Update("target") end)
ns.On("UNIT_AURA", function(_, unit)
	if unit == "player" then A.Update("player") elseif unit == "target" then A.Update("target")
	elseif type(unit) == "string" and unit:match("^party%d$") then A.Update(unit) end
end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "hud.accent" then rebuildCurves() end
	if rows.player then A.Update() end
end)
