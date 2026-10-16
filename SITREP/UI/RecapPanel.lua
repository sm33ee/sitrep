-- SITREP · The death recap on screen (Recap.lua builds it)
-- After a death or a lost duel: how long it took, the share of each source with a
-- bar in its class colour, the biggest hit, how much hit you while you could not
-- act, and one or two tips. Click it away; it fades after HOLD seconds.
-- /sitrep recap shows the last one again. Placed like any element (Layout:
-- "Death recap"); log.recapPopup switches it.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local format = string.format

local RP = {}
ns.RecapPanel = RP
local W, ROWS, HOLD, FADE = 340, 4, 40, 2

local function short(v)
	if v >= 10000 then return format("%.0fk", v / 1000) end
	if v >= 1000 then return format("%.1fk", v / 1000) end
	return format("%d", v)
end

local function build()
	if RP.frame then return RP.frame end
	local f = K.Panel(UIParent, W, 100, { name = "SITREP_Recap" })
	f:SetFrameStrata("HIGH")
	f.title = K.Font(f, 10, C.dim, K.FONT, "")
	f.title:SetPoint("TOPLEFT", 10, -7)
	f.head = K.Font(f, 15, { 1, 0.4, 0.35, 1 }, K.FONT, "")
	f.head:SetPoint("TOPLEFT", 10, -20)
	f.sub = K.Font(f, 10, C.dim, K.FONT, "")
	f.sub:SetPoint("TOPLEFT", 10, -39)
	f.rows = {}
	for i = 1, ROWS do
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(W - 20, 14)
		r:SetPoint("TOPLEFT", 10, -54 - (i - 1) * 17)
		r.bar = K.Tex(r, "ARTWORK", { 1, 1, 1, 0.35 })
		r.bar:SetPoint("TOPLEFT")
		r.bar:SetPoint("BOTTOMLEFT")
		r.name = K.Font(r, 11, C.text, K.FONT, "")
		r.name:SetPoint("LEFT", 4, 0)
		r.pct = K.Font(r, 11, C.text, K.FONT, "")
		r.pct:SetPoint("RIGHT", -4, 0)
		f.rows[i] = r
	end
	f.big = K.Font(f, 10.5, C.text, K.FONT, "")
	f.big:SetJustifyH("LEFT")
	f.dura = K.Font(f, 10.5, C.text, K.FONT, "")
	f.dura:SetJustifyH("LEFT")
	f.tips = K.Font(f, 10.5, { 1, 0.82, 0.35, 1 }, K.FONT, "")
	f.tips:SetJustifyH("LEFT")
	f.tips:SetWidth(W - 20)
	if f.tips.SetWordWrap then f.tips:SetWordWrap(true) end
	f.unlock = K.Tex(f, "OVERLAY", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	f:EnableMouse(true)
	f:SetScript("OnMouseUp", function(self) if ns.P.hud.locked then self:Hide() end end)
	f:SetScript("OnUpdate", ns.Timed("recap (f)", function(self)
		if self.placing then return end
		local t = GetTime() - (self.shown or 0)
		if t > HOLD + FADE then self:Hide() return end
		self:SetAlpha(K.Opacity("recap") * (t < HOLD and 1 or 1 - (t - HOLD) / FADE))
	end))
	K.Movable(f, "recap", { "CENTER", "CENTER", 0, 120 })
	f:Hide()
	RP.frame = f
	return f
end

-- Fill and show one recap.
function RP.Show(r)
	if not r then return end
	local f = build()
	if r.how == "duel" then
		f.title:SetText("DUEL LOST  ·  RECAP")
	else
		f.title:SetText("DEATH RECAP  ·  " .. (r.zone or ""):upper())
	end
	f.head:SetText(format("%s after %.1f s", r.how == "duel" and "Lost" or "Dead", r.dur))
	f.sub:SetText(format("%s damage taken  ·  %s healed%s", short(r.total), short(r.healIn or 0),
		r.ccShare >= 0.05 and format("  ·  %.0f%% while you could not act", r.ccShare * 100) or ""))
	local y = -54
	for i, row in ipairs(f.rows) do
		local s = r.sources[i]
		if s then
			local cr, cg, cb = 0.6, 0.6, 0.6
			if s.class and not s.npc then cr, cg, cb = ns.Data.ClassColor(s.class) end
			row.bar:SetVertexColor(cr, cg, cb, 0.4)
			row.bar:SetWidth(math.max(1, (W - 20) * s.share))
			local school = s.school and ns.Recap.SCHOOL[s.school]
			row.name:SetText(format("%s%s", s.name, school and ("  |cff8a9492" .. school .. "|r") or ""))
			row.pct:SetText(format("%.0f%%  %s", s.share * 100, short(s.dmg)))
			row:Show()
			y = y - 17
		else
			row:Hide()
		end
	end
	local b = r.biggest
	f.big:ClearAllPoints()
	f.big:SetPoint("TOPLEFT", 10, y - 4)
	f.big:SetText(b and format("Biggest hit: %s %s%s%s, %.1f s before the end", short(b.amount), ns.Recap.SCHOOL[b.school] or "",
		b.crit and " (crit)" or "", b.name and (" from " .. b.name) or "", b.before) or "")
	-- your armour: how many more deaths before it breaks (when it gets low)
	local d = r.durability
	if d and d < 50 and r.how ~= "duel" then
		local left = math.floor(d / 10)
		f.dura:SetText(format("Armour %d%%: %s", math.floor(d), left > 0 and format("%d more death%s before it breaks", left, left == 1 and "" or "s")
			or "broken, repair it"))
		if d < 20 then f.dura:SetTextColor(1, 0.35, 0.3) else f.dura:SetTextColor(1, 0.72, 0.3) end
		f.dura:ClearAllPoints()
		f.dura:SetPoint("TOPLEFT", 10, y - 18)
		y = y - 14
	else
		f.dura:SetText("")
	end
	f.tips:ClearAllPoints()
	f.tips:SetPoint("TOPLEFT", 10, y - 20)
	f.tips:SetText(#r.tips > 0 and ("» " .. table.concat(r.tips, "\n» ")) or "")
	local th = #r.tips > 0 and (f.tips:GetStringHeight() or 14 * #r.tips) or 0
	f:SetHeight(-(y - 20) + th + 10)
	local H = ns.P.hud
	f:SetScale(H.scale * (H.frameScale.recap or 1))
	f:RestorePosition()
	f.shown, f.placing = GetTime(), false
	f:SetAlpha(K.Opacity("recap"))
	f:Show()
end

-- Placing it (HUD unlocked): a sample on screen.
function RP.Apply()
	local f = build()
	local H = ns.P.hud
	f:SetScale(H.scale * (H.frameScale.recap or 1))
	K.Background(f.bg, "recap")
	f:RestorePosition()
	f.unlock:SetShown(not H.locked)
	if not H.locked and ns.P.log.recapPopup and ns.P.enabled then
		RP.Show({ how = "death", zone = "Placing", dur = 11.2, total = 4300, healIn = 900, ccShare = 0.38, burst = 0.4,
			sources = { { name = "Vex", class = "ROGUE", share = 0.62, dmg = 2666, school = 1 },
				{ name = "Aldwin", class = "MAGE", share = 0.31, dmg = 1333, school = 16 } },
			biggest = { amount = 1840, school = 16, crit = true, name = "Aldwin", before = 0.4 },
			tips = { "Vex dealt 62% in melee: keep them off you (slow, root, distance)." } })
		f.placing = true
	elseif f.placing then
		f.placing = false
		f:Hide()
	end
end

ns.On("SR_RECAP", function(_, r)
	if ns.P.log.recapPopup and ns.P.enabled then RP.Show(r) end
end)
ns.On("SR_LOGIN", function() RP.Apply() end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 4) == "hud." or key == "log.recapPopup" then RP.Apply() end
end)
