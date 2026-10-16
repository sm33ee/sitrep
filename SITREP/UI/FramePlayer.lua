-- SITREP · Player frame

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read, plain = ns.read, ns.plain
local format, min, max, floor = string.format, math.min, math.max, math.floor
local F = ns.Frames
local U = ns.Units
local TG = ns.Targeting
local newBar, ticks = U.NewBar, U.Ticks
local feedBar, healthText, percentText = U.FeedBar, U.HealthText, U.PercentText
local powerColor, curveColor = U.PowerColor, U.CurveColor
local addHighlights = U.AddHighlights
local HP_GREEN, HP_ORANGE, HP_RED = U.HP_COLORS.green, U.HP_COLORS.orange, U.HP_COLORS.red
local frameShell = F.Shell

-- Survivability: can I live through the next three seconds, and am I locked
-- down? Health with time-to-live, shields and incoming heals (drawn onto the
-- health bar), loss of control, who is on you (TARGETED BY, HEALERS / ALLIES,
-- MOBS), exposure, level and rest, popping damage and heal numbers, and the
-- cost preview on the power bar.
-- Left out on purpose: a 3D portrait, your own name, XP. None of them change a
-- decision in a fight.

---------------------------------------------------------------------------
-- Popping numbers on your own frame: damage you take pops in red right of the
-- bar's centre, heals in green left of it. Each new number pushes the older ones on its side
-- up; they rise and fade within a second. A critical pops bigger. The amounts
-- come from UNIT_COMBAT, which stays plain in combat; a secret amount is handed
-- to the font string as it is.
---------------------------------------------------------------------------
local POP_LIFE, POP_RISE, POP_STEP, POP_MAX = 1.1, 18, 15, 5 -- seconds, px, px, numbers per side
local POP_SIZE, POP_OFFSET = 17, 0.2 -- font size; distance from the bar's centre, as a share of its width
local POP_COLOR = { dmg = { 1, 0.34, 0.28 }, heal = { 0.40, 1, 0.52 } }
local popFree = {}


local function popPlace(host, p, now)
	local t = now - p.born
	local grow = p.crit and 1.7 or 1.35
	local scale = t < 0.12 and grow - (grow - 1) * t / 0.12 or 1
	local y = p.base + POP_RISE * min(1, t / POP_LIFE)
	local w = host:GetWidth()
	local x = max(40, (w and w > 0 and w or 248) * POP_OFFSET)
	if p.side == "heal" then x = -x end
	p:SetScale(scale)
	p:ClearAllPoints()
	p:SetPoint("CENTER", host, "CENTER", x / scale, y / scale)
	p:SetAlpha(t < POP_LIFE * 0.6 and 1 or max(0, 1 - (t - POP_LIFE * 0.6) / (POP_LIFE * 0.4)))
end

local function popRelease(p)
	p:Hide()
	popFree[#popFree + 1] = p
end

local function newPopHost(f)
	local host = CreateFrame("Frame", nil, f)
	host:SetPoint("TOPLEFT", f.hp, "TOPLEFT")
	host:SetPoint("BOTTOMRIGHT", f.hp, "BOTTOMRIGHT")
	host:SetFrameLevel(f:GetFrameLevel() + 9)
	host.sides = { dmg = {}, heal = {} }
	host:SetScript("OnUpdate", ns.Timed("player: numbers (host)", function(self)
		local now = GetTime()
		for _, list in pairs(self.sides) do
			for i = #list, 1, -1 do
				local p = list[i]
				if now - p.born >= POP_LIFE then
					table.remove(list, i)
					popRelease(p)
				else
					popPlace(self, p, now)
				end
			end
		end
	end))
	return host
end

-- One number: side "dmg" or "heal". Returns the pop (for tests) or nil.
function F.Pop(f, side, amount, crit)
	local host = f and f.pops
	if not (host and ns.P.frames.popNumbers) then return nil end
	local secret = ns.isSecret(amount)
	if not secret and (type(amount) ~= "number" or amount <= 0) then return nil end
	local list = host.sides[side]
	local p = table.remove(popFree)
	if not p then
		p = CreateFrame("Frame", nil, host)
		p:SetSize(1, 1)
		p.text = K.Font(p, POP_SIZE, C.text, K.FONT, "OUTLINE")
		p.text:SetPoint("CENTER")
	end
	p:SetParent(host)
	p:SetFrameLevel(host:GetFrameLevel() + 1)
	local c = POP_COLOR[side]
	p.text:SetTextColor(c[1], c[2], c[3], 1)
	local sign = side == "dmg" and "-" or "+"
	if secret then
		if not pcall(p.text.SetFormattedText, p.text, sign .. "%s", amount)
			and not pcall(p.text.SetText, p.text, amount) then
			popRelease(p)
			return nil
		end
	else
		p.text:SetText(sign .. U.ShortNum(amount))
	end
	-- the older ones on this side make room
	for _, o in ipairs(list) do o.base = o.base + POP_STEP end
	while #list >= POP_MAX do popRelease(table.remove(list, 1)) end
	p.side, p.crit, p.base, p.born = side, crit and true or false, 0, GetTime()
	list[#list + 1] = p
	popPlace(host, p, p.born)
	p:Show()
	return p
end

---------------------------------------------------------------------------
-- PLAYER
---------------------------------------------------------------------------
local player -- the frame (also F.player)
F.PLAYER_TAGS_MAX = 38 -- characters that fit beside YOU 60 zZZ

-- The cost preview's layer on a bar: what the spell uses, from the end of the
-- fill leftwards; what you are short of, from the end of the fill rightwards.
local function costLayer(bar, W)
	local clip = CreateFrame("Frame", nil, bar)
	clip:SetAllPoints(bar)
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end
	clip:SetFrameLevel(bar:GetFrameLevel() + 2)
	local fill = bar:GetStatusBarTexture()
	local cost = CreateFrame("StatusBar", nil, clip)
	cost:SetStatusBarTexture(K.WHITE)
	if cost.SetReverseFill then cost:SetReverseFill(true) end
	cost:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	cost:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	cost:SetWidth(max(1, W - 16))
	cost:Hide()
	local short = CreateFrame("StatusBar", nil, clip)
	short:SetStatusBarTexture(K.WHITE)
	short:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	short:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
	short:SetWidth(max(1, W - 16))
	short:Hide()
	return clip, cost, short
end

local function buildPlayer()
	local P = ns.P.frames
	local W = P.width
	local f = frameShell("player", "player", "YOU", { "CENTER", "CENTER", -260, -190 })
	player = f
	F.player = f
	f:SetHeight(86)
	-- your level, and zZZ while resting (inn or city)
	f.lvl = K.Font(f, 10, C.text, K.FONT, "")
	f.lvl:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
	f.rest = K.Font(f, 10, { 0.55, 0.75, 1, 1 }, K.FONT, "")
	f.rest:SetPoint("LEFT", f.lvl, "RIGHT", 6, 0)
	f.rest:SetText("zZZ")
	f.rest:Hide()
	addHighlights(f)

	f.hp = newBar(f, 18, 1)
	U.Ghost(f.hp) -- (glass: the last moment's damage, lit)
	f.hp:SetPoint("TOPLEFT", 8, -20)
	f.hp:SetPoint("TOPRIGHT", -8, -20)
	f.hpTicks = ticks(f.hp, { 0.25, 0.5, 0.75 })
	f.hpText = K.Font(f.hp, 13, C.text, K.FONT, "OUTLINE")
	f.hpText:SetPoint("LEFT", 6, 0)
	f.pctText = K.Font(f.hp, 13, C.text, K.FONT, "OUTLINE")
	f.pctText:SetPoint("RIGHT", -6, 0)

	-- incoming heals: a translucent extension of the health (see Kit: Heals)
	ns.Heals.Attach(f.hp)
	-- damage and heal numbers popping over the health bar
	f.pops = newPopHost(f)
	-- shields (white) as a hairline under the health bar
	f.absorb = newBar(f, 2, 1)
	f.absorb:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -1)
	f.absorb:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -1)
	f.absorb:SetStatusBarColor(0.9, 0.95, 1, 0.9)
	f.absorb.bg:SetAlpha(0)

	f.power = newBar(f, 6, 1)
	f.power:SetPoint("TOPLEFT", f.absorb, "BOTTOMLEFT", 0, -4)
	f.power:SetPoint("TOPRIGHT", f.absorb, "BOTTOMRIGHT", 0, -4)
	-- cost preview: what the hovered or casting spell would take off the bar
	f.costClip, f.cost, f.costShort = costLayer(f.power, W)
	-- druids: mana under rage or energy while shapeshifted, and the cost of a shift
	-- marked (on this bar, or on the power bar while it shows mana)
	f.mana = newBar(f, 2, 1)
	f.mana:SetPoint("TOPLEFT", f.power, "BOTTOMLEFT", 0, -2)
	f.mana:SetPoint("TOPRIGHT", f.power, "BOTTOMRIGHT", 0, -2)
	f.mana:SetStatusBarColor(powerColor("player", 0))
	f.mana:Hide()
	f.manaTick = K.Tex(f.mana, "OVERLAY", { 1, 1, 1, 1 })
	f.manaTick:SetWidth(2)
	f.manaTick:Hide()
	f.powerTick = K.Tex(f.power, "OVERLAY", { 1, 1, 1, 1 })
	f.powerTick:SetWidth(2)
	f.powerTick:Hide()
	-- a mana spell hovered or cast while shapeshifted: its cost on the mana bar
	f.manaClip, f.manaCost, f.manaCostShort = costLayer(f.mana, W)
	f.power:HookScript("OnSizeChanged", function(_, w)
		if w and w > 0 then f.cost:SetWidth(w); f.costShort:SetWidth(w); f.manaCost:SetWidth(w); f.manaCostShort:SetWidth(w) end
	end)

	-- loss of control: a red border around the health bar and the CC in its middle;
	-- the health itself turns light grey on dark grey (see playerHealthColor), so
	-- it stays readable however low it is
	f.loc = CreateFrame("Frame", nil, f)
	f.loc:SetPoint("TOPLEFT", f.hp, "TOPLEFT", -2, 2)
	f.loc:SetPoint("BOTTOMRIGHT", f.hp, "BOTTOMRIGHT", 2, -2)
	f.loc:SetFrameLevel(f.hp:GetFrameLevel() + 3)
	K.Border(f.loc, { 1, 0.28, 0.22, 1 }, 2)
	f.loc.text = K.Font(f.loc, 13, { 1, 1, 1, 1 }, K.FONT, "OUTLINE")
	f.loc.text:SetPoint("RIGHT", f.loc, "CENTER", -3, 0)
	f.loc.time = K.Font(f.loc, 13, { 1, 0.85, 0.45, 1 }, K.FONT, "OUTLINE")
	f.loc.time:SetPoint("LEFT", f.loc, "CENTER", 3, 0)
	f.loc:Hide()

	f.line = K.Font(f, 11, C.text, K.FONT, "")
	f.line:SetPoint("BOTTOMLEFT", 8, 8)
	f.ttl = K.Font(f, 11, C.text, K.FONT, "")
	f.ttl:SetPoint("BOTTOMRIGHT", -8, 8)

	f.hpTicks.Layout(W - 16)
	K.Paint(function(r, g, b) f.title:SetTextColor(r, g, b) end)
end
F.BuildPlayer = buildPlayer

local CC_FILL, CC_TRACK = { 0.82, 0.84, 0.84 }, { 0.16, 0.17, 0.17, 1 }
local function playerHealthColor(bar)
	-- crowd-controlled: greys with the strongest contrast instead of the usual colours
	if player and player.locActive then
		bar:SetStatusBarColor(CC_FILL[1], CC_FILL[2], CC_FILL[3])
		bar.bg:SetVertexColor(CC_TRACK[1], CC_TRACK[2], CC_TRACK[3], CC_TRACK[4])
		return
	end
	bar.bg:SetVertexColor(unpack(C.raised))
	if curveColor(bar, "player") then return end
	local h, m = read(UnitHealth, "player"), read(UnitHealthMax, "player")
	local frac = (h and m and m > 0) and h / m or ns.Pressure.HealthFrac()
	local c = frac > 0.75 and HP_GREEN or frac >= 0.5 and HP_ORANGE or HP_RED
	bar:SetStatusBarColor(c[1], c[2], c[3])
end
F.PlayerHealthColor = playerHealthColor

local function lossOfControl()
	local L = C_LossOfControl
	if not (L and L.GetActiveLossOfControlData) then return nil end
	local ok, d = pcall(L.GetActiveLossOfControlData, 1)
	if not ok or ns.isSecret(d) or not d then return nil end -- secret first: it cannot be tested
	return d
end

-- tags: who is on you, combat, PvP flag (with its countdown while it is running out).
-- The header is narrow: when the line gets long, PVP and then COMBAT give way.
-- (buffers reused: this runs several times a second)
local TAGS_EVERY = 0.25
local tagText, tagColor, tagLow, tagOut = {}, {}, {}, {}
function F.PlayerTags(f, me)
	local n = 0
	local function tag(text, color, droppable)
		n = n + 1
		tagText[n], tagColor[n], tagLow[n] = text, color or false, droppable or false
	end
	local tb = TG.TargetedBy("player")
	if tb > 0 then tag(format("TARGETED BY %d", tb), "ff5555") end
	if ns.P.frames.healersOnMe then
		-- the healers on you if there are any, else every friendly player on you
		local hc, al = TG.OnMe()
		if hc > 0 then tag(format("HEALERS %d", hc), "5cff8d")
		elseif al > 0 then tag(format("ALLIES %d", al), "5cff8d") end
	end
	if ns.P.frames.mobsOnMe then
		local mo = TG.MobsOnMe()
		if mo > 0 then tag(format("MOBS %d", mo), "ffa040") end
	end
	if me.combat then tag("COMBAT", "ff5555", 2) end
	if read(UnitIsPVP, "player") then
		local running = read(IsPVPTimerRunning)
		local ms = running and read(GetPVPTimer)
		tag(ms and ms > 0 and format("PVP %d:%02d", floor(ms / 60000), floor(ms / 1000) % 60) or "PVP", nil, 1)
	end
	local function plainLen()
		local len = 0
		for i = 1, n do if tagText[i] then len = len + #tagText[i] + 2 end end
		return len - 2
	end
	for rank = 1, 2 do
		if plainLen() <= F.PLAYER_TAGS_MAX then break end
		for i = 1, n do if tagLow[i] == rank then tagText[i] = false end end
	end
	local k = 0
	for i = 1, n do
		if tagText[i] then
			k = k + 1
			tagOut[k] = tagColor[i] and format("|cff%s%s|r", tagColor[i], tagText[i]) or tagText[i]
		end
	end
	for i = #tagOut, k + 1, -1 do tagOut[i] = nil end
	f.tags:SetText(table.concat(tagOut, "  "))
end

local function updatePlayer()
	local f = player
	if not (f and f:IsShown()) then return end
	local R, me = ns.Pressure, ns.Sensors.self
	feedBar(f.hp, UnitHealth, UnitHealthMax, "player")
	local frac = R.HealthFrac()
	playerHealthColor(f.hp)
	healthText(f.hpText, "player")
	if not percentText(f.pctText, "player") then
		f.pctText:SetText(format("~%.0f%%", frac * 100)) -- shadow estimate while real health is secret
	end
	f.absorb:SetShown(feedBar(f.absorb, UnitGetTotalAbsorbs, UnitHealthMax, "player"))
	ns.Heals.Feed(f.hp, "player")
	F.FeedPower(f)

	-- loss of control
	local d = lossOfControl()
	local was = f.locActive
	f.locActive = d ~= nil
	if d then
		if not pcall(function() f.loc.text:SetText(K.Upper(d.displayText or "LOCKED")) end) then f.loc.text:SetText("LOCKED") end
		local left = plain(d.timeRemaining)
		f.loc.time:SetText(left and format("%.1fs", left) or "")
		f.loc:Show()
	else
		f.loc:Hide()
	end
	if was ~= f.locActive then playerHealthColor(f.hp) end

	f.lvl:SetText(tostring(read(UnitLevel, "player") or ""))
	f.rest:SetShown(read(IsResting) == true)

	-- tags (who is on you: a look over every plate and ally) four times a second
	local now = GetTime()
	if now - (f.tagsAt or 0) >= TAGS_EVERY then
		f.tagsAt = now
		F.PlayerTags(f, me)
	end

	-- exposure from the envelope, and the pressure readout
	local exposed, closing = 0, 0
	for _, c in ipairs(ns.Model.byThreat) do
		if c.live and c.inTheirReach then exposed = exposed + 1 end
		if c.live and c.closing and c.closing <= -3 then closing = closing + 1 end
	end
	local parts = {}
	parts[#parts + 1] = exposed > 0 and format("|cffff5555IN REACH OF %d %s|r", exposed, exposed == 1 and "ENEMY" or "ENEMIES")
		or "|cff8a9492OUT OF ENEMY REACH|r"
	if closing > 0 then parts[#parts + 1] = format("|cffffb833%d CLOSING|r", closing) end
	if (R.dpsShort or 0) > 0 then
		local lvl = R.Level(R.dpsShort)
		local hex = lvl == "danger" and "ff4d4d" or lvl == "warn" and "ff9e26" or "e0e8e5"
		parts[#parts + 1] = format("|cff%s%s DPS IN|r", hex, ns.HUD.shortNum(R.dpsShort))
	end
	f.line:SetText(table.concat(parts, "  ·  "))
	if R.ttl and R.ttl < 30 then
		f.ttl:SetText(format("TTL %.1fs", R.ttl))
		if R.ttl < ns.P.pressure.ttlWarn then f.ttl:SetTextColor(1, 0.3, 0.3) else f.ttl:SetTextColor(unpack(C.text)) end
	else
		f.ttl:SetText("")
	end
end
F.UpdatePlayer = updatePlayer

---------------------------------------------------------------------------
-- Cost preview on your power bar: while you hover a spell (action bar,
-- spellbook, SITREP's lists) or cast one, the part of your mana it takes is
-- lit in a lighter blue; red when you do not have enough, with the missing
-- part shown faded past the end of the bar.
---------------------------------------------------------------------------
local COST_OK, COST_SHORT = { 0.62, 0.86, 1.00, 0.95 }, { 1.00, 0.25, 0.20, 0.95 }
local costState = { hover = nil, cast = nil }
F.costState = costState

-- What a spell costs in the power you are showing (mana, rage, energy), or in
-- ptype when given (0 = mana), or nil.
-- (asked every tick for each druid form and the hovered spell: kept for a second,
-- the client builds a new table on every call)
local costCache, costAt = {}, 0
local COST_KEEP = 1
local readCost
local function spellCost(id, ptype)
	if not id then return nil end
	ptype = ptype or read(UnitPowerType, "player") or 0
	local now = GetTime()
	if now - costAt > COST_KEEP then wipe(costCache); costAt = now end
	local byType = costCache[ptype]
	if not byType then byType = {}; costCache[ptype] = byType end
	local v = byType[id]
	if v == nil then v = readCost(id, ptype) or false; byType[id] = v end
	return v or nil
end
-- gear (an idol), talents or forms changed: the costs are asked again
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORMS" }) do
	ns.On(e, function() costAt = 0 end)
end
function readCost(id, ptype)
	local api = C_Spell and C_Spell.GetSpellPowerCost
	if not (api and id) then return nil end
	local ok, costs = pcall(api, id)
	if not ok or type(costs) ~= "table" or ns.isSecret(costs) then return nil end
	-- the client may list a spell's cost more than once: the plain cost and a lower
	-- one that applies while something is equipped or active (a druid idol lowering
	-- the shapeshift cost): the lowest that applies now is what you pay
	local best
	for _, c in ipairs(costs) do
		if type(c) == "table" then
			local t, amount = plain(c.type), plain(c.cost)
			local req, has = plain(c.requiredAuraID), plain(c.hasRequiredAura)
			if t == ptype and amount and amount > 0 and (not req or req == 0 or has) and (not best or amount < best) then best = amount end
		end
	end
	return best
end
F.SpellCost = spellCost

-- The power bar, always read for the type it shows: right after a shapeshift the
-- type changes (mana -> rage) and a value of the old type must not be drawn in
-- the new colour. Also run on the client's power events, not only on the tick.
function F.FeedPower(f)
	local pt = read(UnitPowerType, "player")
	pcall(function()
		f.power:SetMinMaxValues(0, UnitPowerMax("player", pt))
		f.power:SetValue(UnitPower("player", pt))
	end)
	f.power:SetStatusBarColor(powerColor("player", pt))
	F.UpdateShiftMana(f)
end

---------------------------------------------------------------------------
-- Druids: your mana while shapeshifted (a thin bar under rage or energy), and
-- the mana a shift costs marked on it: in a form, shifting into that form again
-- (powershifting); in caster form, your cheapest form. The mark is white (half
-- opacity), red while you cannot afford it. The costs are the client's own (they follow your mana pool).
---------------------------------------------------------------------------
local MANA = 0
local SHIFT_OK, SHIFT_SHORT = { 1, 1, 1, 0.5 }, { 1, 0.25, 0.2, 1 } -- white at half opacity; red when short

-- Mana cost of shifting into your current form, and of your cheapest form.
-- Forms only of use now and then: in caster form they count only when they apply
-- (Aquatic Form while you swim), or when they were your last form.
local UTILITY = { [1066] = "swim", [783] = "travel", [33943] = "fly", [40120] = "fly" }
F.lastFormSpell = nil -- the form you were in last (its spell)

-- The cost of the form you are in, and of the form you would take next from caster
-- form: the one you were in last, Aquatic Form while you swim, else the dearest of
-- the combat forms (the cheapest overall would be a form you rarely use).
function F.FormCosts()
	local current, planned, dearest
	local active = read(GetShapeshiftForm) or 0
	local swimming = read(IsSwimming) == true
	local costOf = {}
	for i = 1, read(GetNumShapeshiftForms) or 0 do
		local _, _, _, spellID = read(GetShapeshiftFormInfo, i)
		local cost = spellID and spellCost(spellID, MANA)
		if cost then
			costOf[spellID] = cost
			if i == active then current = cost; F.lastFormSpell = spellID end
			if UTILITY[spellID] == "swim" and swimming then planned = cost end
			if not UTILITY[spellID] and (not dearest or cost > dearest) then dearest = cost end
		end
	end
	planned = planned or (F.lastFormSpell and costOf[F.lastFormSpell]) or dearest
	if not planned then for _, c in pairs(costOf) do if not planned or c < planned then planned = c end end end
	return current, planned
end

local function placeTick(tick, bar, cost, maxMana, mana)
	if not (cost and maxMana and maxMana > 0) then tick:Hide() return end
	local w = bar:GetWidth()
	if not w or w <= 0 then w = ns.P.frames.width - 16 end
	local x = floor(w * min(1, cost / maxMana))
	tick:ClearAllPoints()
	tick:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
	tick:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
	local c = (mana and mana < cost) and SHIFT_SHORT or SHIFT_OK
	tick:SetVertexColor(c[1], c[2], c[3], c[4])
	tick:Show()
end

function F.UpdateShiftMana(f)
	local druid = ns.Sensors.self.class == "DRUID" and ns.P.frames.druidMana
	local ptype = read(UnitPowerType, "player")
	local shifted = druid and ptype ~= nil and ptype ~= MANA or false
	f.mana:SetShown(shifted)
	if not druid then f.manaTick:Hide(); f.powerTick:Hide() return end
	local current, planned = F.FormCosts()
	local cost = current or planned
	-- mana may be secret in combat: the bar takes it anyway; the mark needs plain numbers
	local maxMana, mana = read(UnitPowerMax, "player", MANA), read(UnitPower, "player", MANA)
	if shifted then
		pcall(function()
			f.mana:SetMinMaxValues(0, UnitPowerMax("player", MANA))
			f.mana:SetValue(UnitPower("player", MANA))
		end)
		placeTick(f.manaTick, f.mana, cost, maxMana, mana)
		f.powerTick:Hide()
	else
		f.manaTick:Hide()
		placeTick(f.powerTick, f.power, cost, maxMana, mana)
	end
end

-- Draw one cost on one bar (ptype: the power it is paid in). Returns whether
-- you are short of it, or nil when nothing is drawn.
local function drawCost(costBar, shortBar, id, cost, ptype, askClient)
	if not cost then costBar:Hide(); shortBar:Hide() return nil end
	local cur, mx = read(UnitPower, "player", ptype), read(UnitPowerMax, "player", ptype)
	local short
	if cur then
		short = cost > cur
	elseif askClient then
		-- your power is secret right now: the client says whether it is enough
		local ok, _, noPower = pcall(C_Spell.IsSpellUsable, id)
		short = ok and plain(noPower) == true
	end
	local c = short and COST_SHORT or COST_OK
	costBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
	local okC = pcall(function()
		costBar:SetMinMaxValues(0, UnitPowerMax("player", ptype))
		costBar:SetValue(cost)
	end)
	costBar:SetShown(okC)
	if short and cur and mx and mx > 0 then
		shortBar:SetStatusBarColor(1, 0.25, 0.2, 0.35)
		shortBar:SetMinMaxValues(0, mx)
		shortBar:SetValue(cost - cur)
		shortBar:Show()
	else
		shortBar:Hide()
	end
	return short or false
end

-- The hovered or casting spell's cost: on the power bar in the power it shows;
-- while a druid is shapeshifted, a mana spell's cost on the mana bar under it.
local function updateCost()
	local f = player
	if not (f and f.cost) then return end
	local id = ns.P.frames.costPreview and (costState.cast or costState.hover) or nil
	local ptype = read(UnitPowerType, "player")
	local cost = id and spellCost(id, ptype)
	local manaCost = id and ptype ~= 0 and f.mana:IsShown() and spellCost(id, 0) or nil
	local short = drawCost(f.cost, f.costShort, id, cost, ptype, true)
	local manaShort = drawCost(f.manaCost, f.manaCostShort, id, manaCost, 0, false)
	if short == nil and manaShort == nil then
		f.costSpell, f.costIsShort = nil, nil
	else
		f.costSpell, f.costIsShort = id, short or manaShort or false
	end
end
F.UpdateCost = updateCost

local function setHover(id)
	id = plain(id)
	if type(id) ~= "number" then id = nil end
	if costState.hover ~= id then costState.hover = id; updateCost() end
end
F.SetCostHover = setHover

-- The spell on an action button (directly, or through a macro).
local function actionSpell(slot)
	local kind, id = read(GetActionInfo, slot)
	if kind == "spell" then return id end
	if kind == "macro" and GetMacroSpell then return read(GetMacroSpell, id) end
	return nil
end

-- Which spell the tooltip is showing: action buttons, the spellbook, SITREP's lists.
local function hookTooltip()
	local tt = GameTooltip
	if not (tt and hooksecurefunc) then return end
	pcall(hooksecurefunc, tt, "SetSpellByID", function(_, id) setHover(id) end)
	pcall(hooksecurefunc, tt, "SetAction", function(_, slot) setHover(actionSpell(slot)) end)
	pcall(hooksecurefunc, tt, "SetSpellBookItem", function(_, slot, bank)
		local it = C_SpellBook and read(C_SpellBook.GetSpellBookItemInfo, slot, bank)
		setHover(type(it) == "table" and plain(it.spellID) or nil)
	end)
	if tt.HookScript then tt:HookScript("OnHide", function() setHover(nil) end) end
	-- newer clients describe every tooltip as data: catch spells however they are shown
	local TDP = _G.TooltipDataProcessor
	if TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
		pcall(TDP.AddTooltipPostCall, Enum.TooltipDataType.Spell, function(t, data)
			if t == tt and type(data) == "table" then setHover(data.id) end
		end)
	end
end
F.HookTooltip = hookTooltip

-- your own cast: its cost stays lit while it is being cast
local function castStart(_, unit)
	if unit ~= "player" then return end
	-- the spell ID: 9th value of a cast, 8th of a channel (pcall adds one in front)
	local id = select(10, pcall(UnitCastingInfo, "player"))
	if not plain(id) then id = select(9, pcall(UnitChannelInfo, "player")) end
	costState.cast = plain(id)
	updateCost()
end
local function castEnd(_, unit)
	if unit ~= "player" then return end
	costState.cast = nil
	updateCost()
end
ns.On("UNIT_SPELLCAST_START", castStart)
ns.On("UNIT_SPELLCAST_CHANNEL_START", castStart)
for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do ns.On(e, castEnd) end
ns.On("UNIT_POWER_UPDATE", function(_, unit)
	if unit ~= "player" or not player then return end
	F.FeedPower(player)
	if costState.cast or costState.hover then updateCost() end
end)
-- a shapeshift changes the power type: redraw at once (no stale fill in the new colour)
ns.On("UNIT_DISPLAYPOWER", function(_, unit)
	if unit ~= "player" or not player then return end
	F.FeedPower(player)
	updateCost()
end)

-- someone starts targeting you: the tags at once, not at their next quarter second
ns.On("SR_TARGETED", function() if player then player.tagsAt = 0 end end)
