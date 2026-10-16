-- SITREP · Quest tracker
-- Your quests in SITREP's look, nearest first (or by zone, or by level): the
-- level in its difficulty colour, the title, how far (~ when learned rather than
-- given by the client, or the zone it is in), and the objectives still open with
-- their counts (and, small at the right, how many each group member running
-- SITREP still needs: QuestShare.lua). Finished quests say TURN IN. Click a quest to navigate to it (the
-- arrow, UI/QuestArrow.lua), click again to stop; right-click opens the quest log
-- at it; shift-click puts its link into the chat. The order is looked at again every 2 s, not while the mouse is over the
-- list. The 3 quests accepted last stand on top under NEW, a thin line under
-- them. Clicking the header folds it to the quest you navigate to, or the nearest
-- one while none is chosen (- / +).
-- Blizzard's own quest tracker is hidden while this one is on.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local Q = ns.Quests
local format, floor, min = string.format, math.floor, math.min

local QT = {}
ns.QuestTracker = QT

local W = 250
local TITLE_H, OBJ_H, PAD = 15, 12, 4
-- objective lines a quest shows: all of them (open first, then the done ones, dim);
-- more than this (no quest known has): the last line says how many more
local MAX_OBJ = 8
local DONE_GREY = 0.42
local RECENT = 3 -- quests accepted last, shown on top
local STORY_MAX = 450 -- characters of a quest's story in the tooltip
local BLIZZ = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" }
QT.NAMES = BLIZZ
local SORT_LABEL = { distance = "NEAREST FIRST", zone = "BY ZONE", level = "BY LEVEL" }

local function P() return ns.P and ns.P.quests end

local function hex(r, g, b) return format("%02x%02x%02x", floor(r * 255), floor(g * 255), floor(b * 255)) end

-- "Kobold Vermin slain: 3/8" -> "3/8 Kobold Vermin slain"
local function objectiveText(o)
	local name = o.text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%d+%s*/%s*%d+%s*", "")
	if o.have and o.need then return format("%d/%d %s", o.have, o.need, name) end
	return name
end
QT.ObjectiveText = objectiveText

-- The group on one objective: "Aldwi 5 · Bero" (a name alone, green: done; else
-- how many that member still needs).
function QT.PartyText(members, index)
	local parts = {}
	for _, m in ipairs(members) do
		local c = m.counts[index]
		local name = m.name:sub(1, 5)
		if m.complete or (c and c[1] >= c[2]) then
			parts[#parts + 1] = "|cff5cff8d" .. name .. "|r"
		elseif c then
			parts[#parts + 1] = format("%s |cffe0e8e5%d|r", name, c[2] - c[1])
		end
	end
	return table.concat(parts, " · ")
end

-- How far, as the row shows it.
-- 1234 -> "1.2k", 87 -> "87"
function QT.Short(v)
	if v >= 1000 then return format("%.1fk", v / 1000) end
	return format("%d", math.floor(v + 0.5))
end

function QT.DistanceText(q)
	if q.yards then
		local approx = q.target and q.target.kind ~= "exact" and "~" or ""
		return format("%s%d YD", approx, floor(q.yards + 0.5))
	end
	if q.elsewhere then return K.Upper and K.Upper(q.elsewhere) or q.elsewhere:upper() end
	return ""
end

local function newRow(f, i)
	local r = CreateFrame("Button", nil, f)
	r:SetWidth(W - 12)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.hl = K.Tex(r, "BACKGROUND", C.hover)
	r.hl:SetAllPoints()
	r.hl:SetAlpha(0)
	r.sel = K.Tex(r, "ARTWORK")
	r.sel:SetPoint("TOPLEFT"); r.sel:SetPoint("BOTTOMLEFT"); r.sel:SetWidth(2)
	K.Paint(function(rr, g, b) r.sel:SetVertexColor(rr, g, b, 1) end)
	r.lvl = K.Font(r, 11, C.text, K.FONT, "")
	r.lvl:SetPoint("TOPLEFT", 6, -2)
	r.lvl:SetWidth(20)
	r.lvl:SetJustifyH("LEFT")
	r.dist = K.Font(r, 10, C.dim, K.FONT, "")
	r.dist:SetPoint("TOPRIGHT", -2, -2)
	r.dist:SetJustifyH("RIGHT")
	r.title = K.Font(r, 11, C.text, K.FONT, "")
	r.title:SetPoint("TOPLEFT", r.lvl, "TOPRIGHT", 2, 0)
	r.title:SetPoint("RIGHT", r.dist, "LEFT", -6, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.obj, r.party, r.objIdx = {}, {}, {}
	for n = 1, MAX_OBJ do
		-- the group's progress on this objective, small, at the line's right end
		local p = K.Font(r, 8, C.dim, K.FONT, "")
		p:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -TITLE_H - (n - 1) * OBJ_H - 1)
		p:SetJustifyH("RIGHT")
		r.party[n] = p
		local o = K.Font(r, 10, C.dim, K.FONT, "")
		o:SetPoint("TOPLEFT", 28, -TITLE_H - (n - 1) * OBJ_H)
		o:SetPoint("RIGHT", p, "LEFT", -4, 0)
		o:SetJustifyH("LEFT")
		o:SetWordWrap(false)
		r.obj[n] = o
	end
	r:SetScript("OnClick", function(self, button)
		local q = self.quest
		if not q then return end
		if button == "RightButton" then Q.Open(q) return end
		if IsShiftKeyDown and IsShiftKeyDown() then Q.Link(q) return end -- (its link in the chat)
		Q.Select(Q.selectedId ~= q.id and q.id or nil)
	end)
	r:SetScript("OnEnter", function(self)
		self.hl:SetAlpha(1)
		local q = self.quest
		if not (q and GameTooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(q.title, 1, 1, 1)
		-- the experience, the task, then the story (long stories cut)
		local desc, task, xp = Q.Text(q)
		if xp then
			local mx = ns.read(UnitXPMax, "player")
			local share = mx and mx > 0 and format("  (%.0f%% of this level)", xp / mx * 100) or ""
			GameTooltip:AddLine(format("%d XP%s", xp, share), 0.58, 0.42, 1)
		end
		local v = self.value
		if v then
			local r_, g_, b_ = 0.7, 0.62, 1
			if v.rating == "great" then r_, g_, b_ = 0.36, 1, 0.55 elseif v.rating == "poor" then r_, g_, b_ = 1, 0.48, 0.36 end
			GameTooltip:AddLine(format("about %.0f min (way %.0f, work %.0f): %s XP a minute; killing mobs: %s%s", v.minutes,
				v.travel / 60, v.work / 60, QT.Short(v.xpm), QT.Short(v.base), v.rating == "poor" and "  - not worth it" or
				v.rating == "great" and "  - worth it" or ""), r_, g_, b_, true)
			if (v.killXP or 0) > 0 then
				GameTooltip:AddLine(format("counts the kills on the way too: about %s XP", QT.Short(v.killXP)), 0.7, 0.62, 1, true)
			end
			if (v.near or 0) > 0 then
				GameTooltip:AddLine(format("%d more quest%s close by: the way is shared", v.near, v.near > 1 and "s" or ""), 0.7, 0.62, 1, true)
			end
			if v.almost then GameTooltip:AddLine("almost done: worth finishing", 0.36, 1, 0.55, true) end
			-- drop rates learned for its items (Drops.lua)
			local q = self.quest
			for n, o in ipairs(q and not q.complete and q.objectives or {}) do
				-- (all four: "ns.Drops and f()" would keep only the first, 4.9.12's broken tooltip)
				local kpi, K, H, from
				if ns.Drops then kpi, K, H, from = ns.Drops.KillsPerItem(q.id, n) end
				if kpi and not o.done then
					GameTooltip:AddLine(format("%s: about 1 in %.1f kills of %s (%d from %d seen)", ns.Questbook.BareText(o.text) or o.text,
						kpi, table.concat(from, ", "), H, K), 0.75, 0.8, 0.78, true)
				end
			end
			-- flights not planned: this character's flight points are not known yet
			if ns.Travel and ns.P.quests.travel and not v.plan and not ns.Travel.Checked() and (not q.yards or q.yards > 600) then
				GameTooltip:AddLine(ns.Travel.HINT, 0.55, 0.8, 1, true)
			end
			local pl = v.plan
			if pl then
				GameTooltip:AddLine(format("way: fly %s to %s (%s%s), then %d yd%s", pl.from, pl.to, ns.Travel.Clock(pl.fly), pl.learned and "" or " est.",
					floor(pl.walkOn + 0.5), pl.direct and format(": %s instead of %s", ns.Travel.Clock(pl.total), ns.Travel.Clock(pl.direct)) or ""),
					0.55, 0.8, 1, true)
			end
		end
		if task and task ~= "" then GameTooltip:AddLine(task, 0.95, 0.92, 0.8, true) end
		if desc and desc ~= "" then
			if #desc > STORY_MAX then desc = desc:sub(1, STORY_MAX):gsub("%s+%S*$", "") .. " ..." end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(desc, 0.62, 0.66, 0.64, true)
			GameTooltip:AddLine(" ")
		end
		for _, o in ipairs(q.objectives) do
			local c = o.done and 0.45 or 0.85
			GameTooltip:AddLine(objectiveText(o), c, c, c)
		end
		-- the group (members running SITREP)
		for _, m in ipairs(ns.QuestShare and type(q.id) == "number" and ns.QuestShare.ForQuest(q.id) or {}) do
			local counts = {}
			for _, c in ipairs(m.counts) do counts[#counts + 1] = format("%d/%d", c[1], c[2]) end
			GameTooltip:AddLine(format("%s: %s", m.name, m.complete and "done" or table.concat(counts, "  ")), 0.36, 0.75, 1)
		end
		local kind = q.target and q.target.kind
		local ch = q.target and q.target.choice
		if ch and ch.of > 1 and ns.Travel then
			GameTooltip:AddLine(format("The quickest of %d places known for it: about %s%s%s", ch.of, ns.Travel.Clock(ch.time), ch.byAir and " by air" or " on foot",
				ch.next and format(" (the next: about %s)", ns.Travel.Clock(ch.next)) or ""), 0.55, 0.8, 1, true)
		end
		local where = kind == "exact" and "Position from the game."
			or kind == "learned" and "Position learned: where your counters went up."
			or kind == "spot" and "A spawn spot of its mobs (learned)."
			or kind == "seen" and "Where its mobs were seen in passing (the bestiary)."
			or kind == "turnin" and "Where it was handed in before."
			or kind == "giver" and "Where you accepted it (most quests are handed in there)."
			or "No position yet: SITREP learns it when an objective counts up."
		GameTooltip:AddLine(where, 0.52, 0.58, 0.57, true)
		GameTooltip:AddLine("Click: navigate here (click again to stop). Right-click: quest log. Shift-click: its link in the chat.", 0.52, 0.58, 0.57, true)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0); if GameTooltip then GameTooltip:Hide() end end)
	f.rows[i] = r
	return r
end

local function build()
	if QT.frame then return end
	local f = CreateFrame("Frame", "SITREP_Quests", UIParent)
	f:SetSize(W, 40)
	f:SetFrameStrata("LOW")
	f.bg = K.Backdrop(f, { C.bg[1], C.bg[2], C.bg[3], 0.72 }, 12, { mood = true })
	f.bg:SetAllPoints()
	K.Border(f, C.line, nil, 12)
	K.Brackets(f, 8, 2)
	f.head = K.Font(f, 11, C.text, K.FONT, "")
	f.head:SetPoint("TOPLEFT", 8, -6)
	K.Paint(function(r, g, b) f.head:SetTextColor(r, g, b) end)
	-- the header folds the list to the quest you navigate to (and back)
	f.toggle = K.Font(f, 13, C.dim, K.FONT, "")
	f.toggle:SetPoint("TOPRIGHT", -8, -3)
	f.sort = K.Font(f, 9, C.faint, K.FONT, "")
	f.sort:SetPoint("RIGHT", f.toggle, "LEFT", -6, -1)
	local hb = CreateFrame("Button", nil, f)
	hb:SetPoint("TOPLEFT"); hb:SetPoint("TOPRIGHT")
	hb:SetHeight(20)
	hb:RegisterForClicks("LeftButtonUp")
	hb:SetScript("OnClick", function() QT.Toggle() end)
	-- (dragging the header still moves the tracker while the HUD is unlocked)
	hb:RegisterForDrag("LeftButton")
	hb:SetScript("OnDragStart", function() local fn = f:GetScript("OnDragStart") if fn then fn(f) end end)
	hb:SetScript("OnDragStop", function() local fn = f:GetScript("OnDragStop") if fn then fn(f) end end)
	K.Tooltip(hb, "Quests", "Click: only the quest you navigate to, or all of them again. A key binding does it too.")
	f.headButton = hb
	f.unlock = K.Tex(f, "OVERLAY", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	-- the quests accepted last: a small NEW label over them, a thin line under them
	f.newLabel = K.Font(f, 9, C.faint, K.FONT, "")
	f.newLabel:SetText("NEW")
	f.newLabel:Hide()
	f.newLine = K.Tex(f, "ARTWORK", C.line2)
	f.newLine:SetHeight(1)
	f.newLine:Hide()
	f.rows = {}
	f:EnableMouse(true)
	K.Movable(f, "quests", { "RIGHT", "RIGHT", -24, 60 })
	-- dropped somewhere else: the quest items' icons follow
	local dropped = f:GetScript("OnDragStop")
	f:SetScript("OnDragStop", function(self) if dropped then dropped(self) end QT.Refresh() end)
	local acc = 0
	f:SetScript("OnUpdate", ns.Timed("quest tracker (f)", function(self, e)
		acc = acc + e
		if acc < 2 then return end
		acc = 0
		if not (self.IsMouseOver and self:IsMouseOver()) then QT.Refresh() end
	end))
	QT.frame = f
end

-- In combat with a quest item's icon showing (UI/QuestItems.lua: secure buttons,
-- not to be moved then) the layout stays as it is; the rows' texts still update.
function QT.CombatTexts()
	local byId = {}
	for _, q in ipairs(Q.Sorted(P().sort)) do byId[q.id] = q end
	for _, r in ipairs(QT.frame.rows) do
		local q = r:IsShown() and r.quest and byId[r.quest.id]
		if q then
			r.quest = q
			for k = 1, MAX_OBJ do
				local o = r.objIdx[k] and q.objectives[r.objIdx[k]]
				if o and r.obj[k]:IsShown() then r.obj[k]:SetText(objectiveText(o)) end
			end
			r.dist:SetText(QT.DistanceText(q))
		end
	end
end

function QT.Refresh()
	local f = QT.frame
	if not (f and QT.on) then return end
	if InCombatLockdown() and ns.QuestItems and ns.QuestItems.Active() then return QT.CombatTexts() end
	local P_ = P()
	-- in combat the list folds into its header, dimmed (the quests can wait; after
	-- the fight it opens again)
	if P_.combatFold and InCombatLockdown() then
		f.head:SetText(format("QUESTS  %d", #(QT.list or {})))
		for _, r in ipairs(f.rows) do r:Hide() end
		f.newLabel:Hide(); f.newLine:Hide()
		f.sort:SetText("")
		f:SetHeight(26)
		f:SetAlpha(K.Opacity("quests") * 0.6)
		QT.folded = true
		return
	end
	if QT.folded then QT.folded = false; f:SetAlpha(K.Opacity("quests")) end
	local list = Q.Sorted(P_.sort)
	QT.list = list
	-- navigate to the nearest quest by itself (option), when nothing is chosen
	if P_.autoNearest and not Q.selectedId then
		for _, q in ipairs(list) do if q.target then Q.selectedId = q.id break end end
	end
	f.head:SetText(format("QUESTS  %d", #list))
	-- folded: only the quest you navigate to; none chosen: the nearest one (whatever
	-- the order; without known distances the first in it)
	if P_.collapsed then
		local pick, label
		for _, q in ipairs(list) do if q.id == Q.selectedId then pick, label = q, "CHOSEN ONLY" end end
		if not pick then
			for _, q in ipairs(list) do if q.yards and (not pick or q.yards < pick.yards) then pick = q end end
			pick, label = pick or list[1], "NEAREST"
		end
		list = { pick }
		f.sort:SetText(pick and label or "")
		f.toggle:SetText("+")
	else
		f.sort:SetText(SORT_LABEL[P_.sort] or "")
		f.toggle:SetText("-")
	end
	-- the quests accepted last, on top under NEW (not again in the list below)
	local fresh = {}
	if not P_.collapsed then
		local byId = {}
		for _, q in ipairs(list) do byId[q.id] = q end
		for _, id in ipairs(Q.Recent(RECENT)) do if byId[id] then fresh[#fresh + 1] = byId[id] end end
		if #fresh > 0 then
			local skip, rest = {}, {}
			for _, q in ipairs(fresh) do skip[q.id] = true end
			for _, q in ipairs(list) do if not skip[q.id] then rest[#rest + 1] = q end end
			list = rest
		end
	end
	local me = ns.Sensors.self.level
	local n = 0
	local function row(q, y)
		n = n + 1
		local r = f.rows[n] or newRow(f, n)
		r.quest = q
		local lr, lg, lb = ns.Plates.LevelColor(q.level, me)
		r.lvl:SetText(q.level and tostring(q.level) or "")
		r.lvl:SetTextColor(lr, lg, lb)
		r.title:SetText(q.title)
		local open = 0
		if q.complete then
			r.title:SetTextColor(0.36, 1, 0.55)
			r.obj[1]:SetText("|cff5cff8dTURN IN|r")
			open = 1
		elseif q.failed then
			r.title:SetTextColor(1, 0.33, 0.33)
			r.obj[1]:SetText("|cffff5555FAILED|r")
			open = 1
		else
			r.title:SetTextColor(C.text[1], C.text[2], C.text[3])
			local members = ns.QuestShare and type(q.id) == "number" and ns.QuestShare.ForQuest(q.id) or {}
			-- open ones first, then the done ones (dim): every objective shows
			local order = {}
			for j, o in ipairs(q.objectives) do if not o.done then order[#order + 1] = j end end
			for j, o in ipairs(q.objectives) do if o.done then order[#order + 1] = j end end
			for i, j in ipairs(order) do
				local o = q.objectives[j]
				if open == MAX_OBJ - 1 and #order > MAX_OBJ then
					open = open + 1
					r.obj[open]:SetText(format("+%d more (hover the quest)", #order - i + 1))
					r.obj[open]:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
					r.objIdx[open] = nil
					r.party[open]:SetText("")
					break
				end
				open = open + 1
				r.obj[open]:SetText(objectiveText(o))
				if o.done then r.obj[open]:SetTextColor(DONE_GREY, DONE_GREY, DONE_GREY)
				else r.obj[open]:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
				r.objIdx[open] = j
				r.party[open]:SetText(o.done and "" or QT.PartyText(members, j))
			end
		end
		for k = 1, MAX_OBJ do
			r.obj[k]:SetShown(k <= open)
			if k > open or q.complete or q.failed then r.party[k]:SetText("") end
		end
		r.dist:SetText(QT.DistanceText(q))
		r.dist:SetTextColor(q.target and q.target.kind == "exact" and C.text[1] or C.dim[1], C.dim[2], C.dim[3])
		-- worth it? experience per minute after the distance; a poor one greyed
		local v = P_.value and not q.failed and Q.Value(q, QT.list) or nil
		r.value = v
		-- almost done: a mark after the title
		if not q.complete and not q.failed and Q.Almost(q) then
			r.title:SetText(q.title .. "  |cff5cff8dalmost done|r")
		end
		if v then
			local hex = v.rating == "great" and "5cff8d" or v.rating == "poor" and "ff7a5c" or "b39cff"
			local d = r.dist:GetText() or ""
			r.dist:SetText(format("%s%s|cff%s%s/m|r", d, d ~= "" and "  " or "", hex, QT.Short(v.xpm)))
			if v.rating == "poor" then r.title:SetTextColor(0.55, 0.57, 0.56) end
		end
		r.sel:SetShown(Q.selectedId == q.id)
		local h = TITLE_H + open * OBJ_H + PAD
		r:SetHeight(h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -y)
		r:Show()
		return y + h
	end
	local y = 22
	f.newLabel:SetShown(#fresh > 0)
	f.newLine:SetShown(#fresh > 0 and #list > 0)
	if #fresh > 0 then
		f.newLabel:ClearAllPoints()
		f.newLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -y)
		y = y + 12
		for _, q in ipairs(fresh) do y = row(q, y) end
		f.newLine:ClearAllPoints()
		f.newLine:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(y + 2))
		f.newLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -(y + 2))
		y = y + 6
	end
	for i = 1, min(#list, P_.rows) do y = row(list[i], y) end
	local shown = n
	QT.fresh = fresh
	for i = shown + 1, #f.rows do f.rows[i]:Hide(); f.rows[i].quest = nil end
	f:SetHeight(y + 4)
	-- empty: only while placing it (folded, the header stays: it unfolds the list)
	f:SetShown(#list + #fresh > 0 or P_.collapsed or not ns.P.hud.locked)
	-- the quest items' icons by their rows
	if ns.QuestItems then ns.QuestItems.Place(f.rows, f) end
end

-- All quests, or only the one you navigate to.
function QT.Toggle()
	P().collapsed = not P().collapsed
	ns.Changed("quests.collapsed")
end
function SITREP_ToggleQuestList() if ns.P then QT.Toggle() end end

function QT.Apply()
	if InCombatLockdown() then QT.pending = true return end
	build()
	local P_ = P()
	local on = P_.tracker and ns.P.enabled and not ns.hudHidden and true or false
	QT.on = on
	local f = QT.frame
	f:SetShown(on)
	f:RestorePosition()
	f:SetScale(ns.P.hud.scale * (ns.P.hud.frameScale.quests or 1))
	f:SetAlpha(K.Opacity("quests"))
	K.Background(f.bg, "quests")
	f.unlock:SetShown(not ns.P.hud.locked)
	for _, n in ipairs(BLIZZ) do K.Conceal(type(_G[n]) == "table" and _G[n] or nil, on and P_.hideBlizz) end
	if on then QT.Refresh() elseif ns.QuestItems then ns.QuestItems.Place({}, nil) end
end

ns.On("SR_LOGIN", function() QT.Apply() end)
ns.On("SR_QUESTS", function() QT.Refresh() end)
ns.On("PLAYER_REGEN_ENABLED", function()
	if QT.pending then QT.pending = false; QT.Apply() else QT.Refresh() end -- (sorted again after combat)
end)
ns.On("PLAYER_REGEN_DISABLED", function() QT.Refresh() end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 7) == "quests." or key:sub(1, 4) == "hud." then QT.Apply() end
end)
