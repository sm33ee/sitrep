-- SITREP · Trackers: icons, drawing, wiring

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read, plain = ns.read, ns.plain
local format, floor, max = string.format, math.floor, math.max
local issecrettable = _G.issecrettable or function() return false end
local T = ns.Trackers
local spellName, spellIcon = T.SpellName, T.SpellIcon
local inCombat, cooldownState, weaponState, auraState = T.InCombat, T.CooldownState, T.WeaponState, T.AuraState
local BORDER, Oracle = T.BORDER, T.Oracle

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function savePosition(f)
	local it = T.Get(f.itemId)
	local cx, cy = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (it and cx and ux) then return end
	it.x, it.y = floor(cx - ux + 0.5), floor(cy - uy + 0.5)
	T.Changed()
end

local function makeIcon(item)
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	f.itemId = item.id
	f.bg = K.Tex(f, "BACKGROUND", { 0, 0, 0, 0.7 })
	f.bg:SetPoint("TOPLEFT", -1, 1)
	f.bg:SetPoint("BOTTOMRIGHT", 1, -1)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	K.Border(f, C.line2)
	-- importance: a 2 px border just outside the icon
	f.imp = CreateFrame("Frame", nil, f)
	f.imp:SetPoint("TOPLEFT", -3, 3)
	f.imp:SetPoint("BOTTOMRIGHT", 3, -3)
	K.Border(f.imp, { 1, 1, 1, 1 }, 2)
	f.imp:Hide()
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
	if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
	f.time = K.Font(f, 14, C.text, K.FONT, "OUTLINE", "OVERLAY")
	f.time:SetPoint("CENTER", 0, 0)
	f.mark = K.Font(f, 11, { 1, 0.85, 0.3, 1 }, K.FONT, "OUTLINE", "OVERLAY")
	f.mark:SetPoint("TOPRIGHT", -1, -1)
	-- layout mode: a label under the icon, and a bracket on the selected one
	f.label = K.Font(f, 9.5, C.dim, K.FONT, "")
	f.label:SetPoint("TOP", f, "BOTTOM", 0, -3)
	f.label:Hide()
	f.sel = CreateFrame("Frame", nil, f)
	f.sel:SetPoint("TOPLEFT", -6, 6)
	f.sel:SetPoint("BOTTOMRIGHT", 6, -6)
	K.Brackets(f.sel, 7, 2)
	f.sel:Hide()
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if T.editing and not InCombatLockdown() then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition(self)
		T.Layout(T.Get(self.itemId))
	end)
	f:SetScript("OnMouseDown", function(self)
		if not T.editing then return end
		T.selected = self.itemId
		T.Refresh()
		if ns.Config and ns.Config.RefreshTrackers then ns.Config.RefreshTrackers() end
	end)
	f:Hide()
	T.icons[item.id] = f
	return f
end

-- Size, place, opacity and border from the item's settings.
function T.Layout(item)
	if not item then return end
	-- older lists: the cooldown mode "while ready" is now the invert toggle
	if item.show == "ready" then item.show, item.invert = "cd", true end
	local f = T.icons[item.id] or makeIcon(item)
	f:SetSize(item.size, item.size)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", item.x, item.y)
	f.icon:SetTexture(spellIcon(item.spell))
	local fsz = max(9, floor(item.size * 0.36))
	if f.fontSize ~= fsz then f.fontSize = fsz; K.ApplyFont(f.time, K.FONT, fsz, "OUTLINE") end
	local b = BORDER[item.border]
	if b then f.imp.border:SetColor(b[1], b[2], b[3], 1); f.imp:Show() else f.imp:Hide() end
	f.label:SetText((item.name or spellName(item.spell) or "?") .. "\n" .. T.LabelFor(item))
	f:EnableMouse(T.editing)
end


---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function timeText(left)
	if not left or left <= 0 or left == math.huge then return "" end
	if left >= 3600 then return format("%dh", floor(left / 3600 + 0.5)) end
	if left >= 60 then return format("%dm", floor(left / 60 + 0.5)) end
	if left >= 10 then return format("%d", floor(left + 0.5)) end
	return format("%.1f", left)
end
T.TimeText = timeText

local function whenOK(item)
	if item.when == "combat" then return inCombat() end
	if item.when == "nocombat" then return not inCombat() end
	return true
end

-- Decide and draw one icon. Returns whether it is shown.
local function drawItem(item, now)
	local f = T.icons[item.id]
	if not f then T.Layout(item); f = T.icons[item.id] end
	local show, left, unsure, dim, client, chargesLeft = false, nil, false, false, nil, nil
	f.endsAt = nil

	if item.kind == "cd" then
		local onCD, ends, st, du, how = cooldownState(item, now)
		if onCD then
			if how == "plain" or (how == "est" and st and du) then
				f.cd:SetCooldown(st, du)
			elseif C_Spell.GetSpellCooldownDuration and f.cd.SetCooldownFromDurationObject then
				local d = read(C_Spell.GetSpellCooldownDuration, item.spell)
				if d then pcall(f.cd.SetCooldownFromDurationObject, f.cd, d) end
			end
			f.endsAt = ends
			left = ends and ends - now
			unsure = how == "est"
		elseif f.cd.Clear then
			f.cd:Clear()
		end
		if item.show == "always" then
			show, dim = true, onCD
		elseif item.invert then
			show, left, unsure = not onCD, nil, false     -- ready
		else
			show = onCD
		end
	else
		if f.cd.Clear then f.cd:Clear() end
		local unit = item.kind == "target" and "target" or "player"
		local relevant = read(UnitExists, unit) and not read(UnitIsDeadOrGhost, unit)
		if relevant and item.kind == "target" then
			local enemy = ns.Sensors.IsEnemy("target")
			if item.targetType == "enemy" then relevant = enemy
			elseif item.targetType == "friend" then relevant = not enemy end
		end
		if relevant then
			local ex
			if item.kind == "weapon" then ex, unsure = weaponState(item, now)
			else ex, unsure, client, chargesLeft = auraState(item, unit, now) end
			if client then
				show = true -- shown; its visibility comes from the client below
			elseif not item.invert then
				if ex then                                    -- it is there: show it, with its time
					show = true
					if ex ~= math.huge then left, f.endsAt = ex - now, ex end
				end
			elseif not ex then
				show = true                                   -- NOT there (or believed gone)
			elseif ex ~= math.huge and (item.warn or 0) > 0 and ex - now <= item.warn then
				show, left = true, ex - now                   -- about to run out
				f.endsAt = ex
			end
		end
	end

	show = show and whenOK(item)
	if T.editing then
		f:SetAlpha(show and item.alpha or max(0.35, item.alpha * 0.5))
		f.label:Show()
		f.sel:SetShown(T.selected == item.id)
		f:Show()
	else
		f.label:Hide(); f.sel:Hide()
		f:SetAlpha(item.alpha * (dim and 0.45 or 1))
		f:SetShown(show)
	end
	f.icon:SetDesaturated(dim)
	f.time:SetText(show and (chargesLeft and tostring(chargesLeft) or timeText(left)) or "")
	if chargesLeft then f.endsAt = nil end -- the number is charges, not a timer
	f.mark:SetText((show and unsure) and "?" or "")
	f.shownState, f.unsure, f.clientDecides = show, unsure, client ~= nil
	-- in combat: note every change of an aura icon, and how it was decided
	if T.combatLog and item.kind ~= "cd" and item.kind ~= "weapon" then
		local unitB = item.kind == "target" and "target" or "player"
		local sum = Oracle.BarSummary(unitB)
		if sum ~= T["lastBar" .. unitB] then
			T["lastBar" .. unitB] = sum
			if #T.combatLog < 60 then T.combatLog[#T.combatLog + 1] = format("+%.1fs  Blizzard's %s icons: %s", now - T.combatStart, unitB, sum) end
		end
	end
	local st = Oracle.fight[item.id]
	if T.combatLog and st and st.answers and st.answers ~= f.logAnswers then
		f.logAnswers = st.answers
		if #T.combatLog < 60 then
			T.combatLog[#T.combatLog + 1] = format("+%.1fs  %s lookups: %s", now - T.combatStart, item.name or tostring(item.spell), st.answers)
		end
	end
	if T.combatLog and item.kind ~= "cd" and (f.logShow ~= show or f.logHow ~= T.how[item.id]) then
		f.logShow, f.logHow = show, T.how[item.id]
		local line = format("+%.1fs  %s (%s): %s  via %s%s", now - T.combatStart, item.name or tostring(item.spell), T.LabelFor(item),
			show and "SHOWN" or "hidden", tostring(T.how[item.id] or (item.kind == "weapon" and "weapon data" or "?")), unsure and " (?)" or "")
		if #T.combatLog < 60 then T.combatLog[#T.combatLog + 1] = line end
	end
	-- the client alone knows the answer: let it set the icon's opacity
	if client and show and not T.editing then
		local pr = client.probe
		local trueMeansThere = pr.present == "true"
		local visibleWhenThere = not item.invert
		local aTrue = (trueMeansThere == visibleWhenThere) and item.alpha or 0
		local aFalse = (trueMeansThere == visibleWhenThere) and 0 or item.alpha
		local painted = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and CreateColor and pcall(function()
			local c = C_CurveUtil.EvaluateColorFromBoolean(client.value, CreateColor(1, 1, 1, aTrue), CreateColor(1, 1, 1, aFalse))
			local _, _, _, a = c:GetRGBA()
			f:SetAlpha(a)
		end)
		if not painted then
			-- the client would not hand the answer to the frame: estimate as before
			f:SetAlpha(item.alpha); f.clientDecides = false
			f.mark:SetText("?")
		end
	end
	return show
end
T.DrawItem = drawItem

function T.Refresh()
	if not ns.P then return end
	local on = ns.P.enabled and ns.P.trackers.enabled and not ns.hudHidden
	local now = GetTime()
	for _, item in ipairs(T.Items()) do
		if on and T.ForMe(item) then drawItem(item, now)
		elseif T.icons[item.id] then T.icons[item.id]:Hide() end
	end
end


-- Smooth timers between sensor ticks.
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", ns.Timed("trackers: icons (ticker)", function(_, e)
	acc = acc + e
	if acc < 0.1 then return end
	acc = 0
	local now = GetTime()
	for _, f in pairs(T.icons) do
		if f.endsAt and f.shownState and f:IsShown() then f.time:SetText(timeText(f.endsAt - now)) end
	end
end))


-- after a fight (TrackerAuras and TrackerMirror have done their part) and at its start
ns.On("PLAYER_REGEN_ENABLED", function() T.Refresh() end)
ns.On("PLAYER_REGEN_DISABLED", function() T.Refresh() end)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local lastMaintain = 0
ns.On("SR_TICK", function()
	-- out of combat, once a second: learn which aura questions work (see Oracle)
	local now = GetTime()
	if not InCombatLockdown() and now - lastMaintain >= 1 then
		lastMaintain = now
		pcall(Oracle.Maintain, now)
	end
	T.Refresh()
end)
ns.On("SPELL_UPDATE_COOLDOWN", function() T.Refresh() end)
ns.On("PLAYER_TARGET_CHANGED", function() T.Refresh() end)
ns.On("UNIT_AURA", function(_, unit) if unit == "player" or unit == "target" then T.Refresh() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 9) == "trackers." or key == "hud.locked" then T.LayoutAll() end
end)
ns.On("SR_CONSOLE", function(_, open)
	-- leaving the console ends layout mode
	if not open and T.editing then T.SetEditing(false) end
end)

