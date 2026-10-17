-- SITREP · Raid frames
-- Up to 40 members in glass cells, one column per raid group in use (side by side,
-- the frame as wide as the raid), five cells each. A cell says only what a raid
-- needs at a glance:
--   health     the bar fills the cell in the member's class colour (dimmed), the
--              missing part dark glass; heals on their way on it (Heals)
--   name       short (no realm), white; DEAD, GHOST or OFFLINE in its place
--   dispel     orbs in the bottom right corner, one per kind you can remove
--   aggro      a coral rim while something is on them (UnitThreatSituation)
--   target     your target: a bright rim round its cell
--   range      beyond your heals: the cell fades
--   raid mark  the skull, cross... top right
-- Clicks: left targets, right opens the unit menu; the mouse on a cell lights the
-- member's nameplate (Plates.Highlight). Each cell is a secure unit button for
-- raidN, shown by the client while that unit exists (unit watch); where a cell
-- sits (its group's column) changes only out of combat. In combat a member who
-- moved keeps the old place until it is over; the cell shows the right person.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format
local F = ns.Frames
local U = ns.Units

local MAX, GROUPS, PER = 40, 8, 5
local CELL_W, CELL_H, GAP = 70, 32, 3
local AGGRO = { 1, 0.36, 0.30 } -- coral: the design's colour for danger
local DIM = 0.62 -- the class colour on the bar, dimmed: the white name stays readable
local FAR_ALPHA, OFF_ALPHA = 0.4, 0.35

local raid -- the header (F.raid); its cells F.raidCells[1..40]
F.raidCells = {}

-- Short name: no realm.
local function shortName(fs, unit)
	local n = read(GetUnitName, unit, false)
	if n then fs:SetText((n:gsub("%-.*$", ""))) return end
	if not pcall(function() fs:SetText(UnitName(unit)) end) then fs:SetText("?") end
end

local function buildCell(i)
	local unit = "raid" .. i
	local f = CreateFrame("Button", "SITREP_raid" .. i .. "Frame", raid, "SecureUnitButtonTemplate")
	f:SetSize(CELL_W, CELL_H)
	f.bg = K.Backdrop(f, C.bg, 4, { shadow = false })
	f.bg:SetAllPoints()
	f:SetAttribute("unit", unit)
	f:SetAttribute("type1", "target")
	f:SetAttribute("type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f.unit, f.index = unit, i
	f:HookScript("OnEnter", function(self) if ns.Plates then ns.Plates.Highlight(self.unit) end end)
	f:HookScript("OnLeave", function() if ns.Plates then ns.Plates.Highlight(nil) end end)
	-- the health: the whole cell, 2 px in
	f.hp = U.NewBar(f, CELL_H - 4, 1)
	f.hp:SetPoint("TOPLEFT", 2, -2)
	f.hp:SetPoint("BOTTOMRIGHT", -2, 2)
	f.hp.bg:SetVertexColor(0.07, 0.09, 0.09, 0.9)
	ns.Heals.Attach(f.hp)
	-- text over the bar
	f.over = CreateFrame("Frame", nil, f)
	f.over:SetAllPoints()
	f.over:SetFrameLevel(f:GetFrameLevel() + 4)
	f.name = K.Font(f.over, 10, C.text, K.FONT, "OUTLINE")
	f.name:SetPoint("LEFT", 5, 3)
	f.name:SetPoint("RIGHT", -5, 3)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false)
	f.state = K.Font(f.over, 8, C.dim, K.FONT, "OUTLINE")
	f.state:SetPoint("BOTTOMLEFT", 5, 4)
	-- the raid mark, top right
	f.mark = f.over:CreateTexture(nil, "OVERLAY")
	f.mark:SetSize(11, 11)
	f.mark:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	f.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.mark:Hide()
	-- dispel orbs, bottom right
	f.orbs = U.Orbs(f.over, 2, 6, function(o, j) o:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3 - (j - 1) * 9, 3) end)
	-- rims: aggro (coral) and your target (bright), over everything
	f.aggro = CreateFrame("Frame", nil, f)
	f.aggro:SetAllPoints()
	f.aggro:SetFrameLevel(f:GetFrameLevel() + 6)
	K.Border(f.aggro, { AGGRO[1], AGGRO[2], AGGRO[3], 1 }, 2, 4)
	f.aggro:Hide()
	f.sel = CreateFrame("Frame", nil, f)
	f.sel:SetPoint("TOPLEFT", -2, 2)
	f.sel:SetPoint("BOTTOMRIGHT", 2, -2)
	f.sel:SetFrameLevel(f:GetFrameLevel() + 7)
	K.Border(f.sel, { C.text[1], C.text[2], C.text[3], 1 }, 1, 4)
	f.sel:Hide()
	f:Hide()
	return f
end

function F.BuildRaid()
	if raid then return end
	local c = CreateFrame("Frame", "SITREP_raidFrame", UIParent)
	c:SetSize(GROUPS * (CELL_W + GAP) - GAP, 16)
	c:SetFrameStrata("MEDIUM")
	c:EnableMouse(true) -- the header is the drag handle
	K.Movable(c, "raid", { "TOPLEFT", "TOPLEFT", 40, -240 })
	c.title = K.Font(c, 10, C.dim, K.FONT, "")
	c.title:SetPoint("BOTTOMLEFT", 2, 3)
	c.title:SetText("RAID")
	c.status = K.Font(c, 10, C.dim, K.FONT, "")
	c.status:SetPoint("BOTTOMRIGHT", -2, 3)
	c.unlock = K.Tex(c, "OVERLAY", { 1, 1, 1, 0.04 })
	c.unlock:SetAllPoints()
	K.Paint(function(r, g, b) c.title:SetTextColor(r, g, b) end)
	-- the group numbers over their columns
	c.groups = {}
	for g = 1, GROUPS do
		local t = K.Font(c, 9, C.faint, K.FONT, "")
		t:SetPoint("BOTTOM", c, "BOTTOMLEFT", (g - 1) * (CELL_W + GAP) + CELL_W / 2, -12)
		t:SetText(tostring(g))
		t:Hide()
		c.groups[g] = t
	end
	raid = c
	F.raid = c
	for i = 1, MAX do F.raidCells[i] = buildCell(i) end
	F.PlaceRaid()
end

-- Who is in which group: raidN's subgroup (GetRaidRosterInfo), nil when no one.
local function groupOf(i)
	local ok, _, _, sub = pcall(GetRaidRosterInfo, i)
	sub = ok and ns.plain(sub) or nil
	return type(sub) == "number" and sub or nil
end

-- Each cell in its group's column, members of a group top down in raid order.
-- Only groups with someone in them get a column, side by side: the frame is as
-- wide as the raid needs (no raid, placing it: groups 1 and 2). Out of combat only
-- (secure frames, and the header holding them); in combat it waits for the end.
local pendingPlace
local function colX(col) return (col - 1) * (CELL_W + GAP) end
function F.PlaceRaid()
	if not raid then return end
	if InCombatLockdown() then pendingPlace = true return end
	-- who is in which group, and where in it
	local groupAt, rowAt, rows, used = {}, {}, {}, {}
	for i in ipairs(F.raidCells) do
		-- (no one at raidN: where it would be in order; placing the frames shows it)
		local sub = groupOf(i)
		local g = sub or math.min(GROUPS, math.ceil(i / PER))
		local r = (rows[g] or 0) + 1
		if r > PER then -- (a full group: the next with room, never off the grid)
			for h = 1, GROUPS do if (rows[h] or 0) < PER then g, r = h, (rows[h] or 0) + 1 break end end
		end
		rows[g] = r
		groupAt[i], rowAt[i] = g, r
		if sub then used[g] = true end
	end
	-- the columns: the groups in use, in order
	local cols, colOf = {}, {}
	for g = 1, GROUPS do if used[g] then cols[#cols + 1] = g end end
	if #cols == 0 then cols = { 1, 2 } end
	for c, g in ipairs(cols) do colOf[g] = c end
	for i, f in ipairs(F.raidCells) do
		-- (a cell of an empty group: hidden; after the last column, should it fill in combat)
		local col = colOf[groupAt[i]] or (#cols + 1)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", raid, "BOTTOMLEFT", colX(col), -(rowAt[i] - 1) * (CELL_H + GAP) - 14)
	end
	-- the header exactly as wide as the columns (one column: the short count)
	raid:SetWidth(colX(#cols + 1) - GAP)
	for g, t in ipairs(raid.groups) do
		t:ClearAllPoints()
		t:SetPoint("BOTTOM", raid, "BOTTOMLEFT", colX(colOf[g] or 1) + CELL_W / 2, -12)
	end
	F.raidGroups, F.raidColumns = used, #cols
end

-- What the raid frames see (/sitrep raidprobe): each member's group as the client
-- gives it, the columns and the width, where each cell sits.
function F.RaidProbe()
	ns.Capture("raidprobe", function()
		ns.print("in raid %s, members %s, frames on %s, combat %s", tostring(IsInRaid and IsInRaid()), tostring(read(GetNumGroupMembers)),
			tostring(ns.P.frames.raid), tostring(InCombatLockdown()))
		if not raid then ns.print("no raid frame built") return end
		for i = 1, MAX do
			local ok, name, rank, sub = pcall(GetRaidRosterInfo, i)
			if ok and name ~= nil then
				local f = F.raidCells[i]
				local _, _, _, x, y = f:GetPoint(1)
				ns.print("  raid%d %s: group %s%s, cell shown %s at %s/%s", i, ns.isSecret(name) and "(secret name)" or tostring(name),
					ns.isSecret(sub) and "secret" or tostring(sub), groupOf(i) and "" or " (not readable: placed by order)",
					tostring(f:IsShown()), tostring(x), tostring(y))
			end
		end
		ns.print("columns %s, width %s (a column: %d), groups in use: %s", tostring(F.raidColumns), tostring(read(raid.GetWidth, raid)), CELL_W + GAP,
			(function() local t = {} for g = 1, GROUPS do if F.raidGroups and F.raidGroups[g] then t[#t + 1] = g end end return table.concat(t, ", ") end)())
	end)
end

-- One cell: health, name, state, marks, rims, range.
local function updateCell(f)
	local unit = f.unit
	if not read(UnitExists, unit) then
		ns.Heals.Feed(f.hp, nil)
		if f:IsShown() then -- (placing them: a placeholder)
			f.name:SetText("RAID " .. f.index); f.name:SetTextColor(unpack(C.faint))
			f.state:SetText(""); f.hp:SetValue(0)
			f.aggro:Hide(); f.sel:Hide(); f.mark:Hide(); f.orbs:Hide()
			f:SetAlpha(1)
		end
		return false
	end
	local _, cls = read(UnitClass, unit)
	local online = read(UnitIsConnected, unit) ~= false
	local dead = read(UnitIsDeadOrGhost, unit)
	shortName(f.name, unit)
	U.FeedBar(f.hp, UnitHealth, UnitHealthMax, unit)
	if dead or not online then
		f.hp:SetStatusBarColor(0.30, 0.32, 0.32)
		f.name:SetTextColor(unpack(C.dim))
		f.state:SetText(not online and "OFFLINE" or read(UnitIsGhost, unit) and "GHOST" or "DEAD")
		ns.Heals.Feed(f.hp, nil)
	else
		local r, g, b = 0.5, 0.55, 0.55
		if cls then r, g, b = ns.Data.ClassColor(cls) end
		f.hp:SetStatusBarColor(r * DIM, g * DIM, b * DIM)
		f.name:SetTextColor(unpack(C.text))
		f.state:SetText("")
		ns.Heals.Feed(f.hp, unit)
	end
	-- something on them
	local threat = online and not dead and read(UnitThreatSituation, unit) or nil
	f.aggro:SetShown(type(threat) == "number" and threat >= 2)
	-- your target
	f.sel:SetShown(read(UnitIsUnit, unit, "target") == true)
	-- the raid mark
	local mark = read(GetRaidTargetIndex, unit)
	if mark and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(f.mark, mark)
		f.mark:Show()
	else
		f.mark:Hide()
	end
	U.PaintOrbs(f.orbs, unit)
	-- beyond your heals (or offline): faded
	local inHeal
	local a = ns.Allies and ns.Allies.ForUnit(unit)
	if a and a.inHeal ~= nil then inHeal = a.inHeal
	else
		local inRange, checked = read(UnitInRange, unit)
		if checked ~= false and inRange ~= nil then inHeal = inRange and true or false end
	end
	f:SetAlpha((not online and OFF_ALPHA) or (inHeal == false and FAR_ALPHA) or 1)
	return true, inHeal ~= false and online and not dead
end
F.UpdateRaidCell = updateCell

function F.UpdateRaid()
	if not (raid and raid:IsShown()) then return end
	local n, near = 0, 0
	for _, f in ipairs(F.raidCells) do
		local here, ok = updateCell(f)
		if here then
			n = n + 1
			if ok then near = near + 1 end
		end
	end
	-- (one column: only the numbers, the words would not fit beside the title)
	local narrow = (F.raidColumns or 2) < 2
	raid.status:SetText(n > 0 and format(narrow and "%d/%d" or "%d/%d IN HEAL RANGE", near, n) or "")
	for g, t in ipairs(raid.groups) do t:SetShown(F.raidGroups and F.raidGroups[g] and n > 0 or false) end
end

-- Shown or not, and placed (F.Apply: out of combat).
function F.ApplyRaid()
	if not raid then return end
	local P, H = ns.P.frames, ns.P.hud
	raid:SetScale(H.scale * (H.frameScale.raid or 1))
	raid:SetAlpha(K.Opacity("raid"))
	raid:RestorePosition()
	raid.unlock:SetShown(not H.locked)
	for _, f in ipairs(F.raidCells) do K.Background(f.bg, "raid") end
	if P.raid and ns.P.enabled and not ns.hudHidden then
		if not H.locked and ns.Config and ns.Config.IsOpen() then
			-- placing it: the header and two groups of placeholders
			pcall(UnregisterStateDriver, raid, "visibility")
			raid:Show()
			for i, f in ipairs(F.raidCells) do
				pcall(UnregisterUnitWatch, f)
				f:SetShown(i <= 2 * PER or read(UnitExists, f.unit) == true)
			end
		else
			if not pcall(RegisterStateDriver, raid, "visibility", "[group:raid] show; hide") then raid:SetShown(IsInRaid and IsInRaid() or false) end
			for _, f in ipairs(F.raidCells) do pcall(RegisterUnitWatch, f) end
		end
	else
		pcall(UnregisterStateDriver, raid, "visibility")
		raid:Hide()
		for _, f in ipairs(F.raidCells) do pcall(UnregisterUnitWatch, f); f:Hide() end
	end
	F.PlaceRaid()
	F.UpdateRaid()
end

-- someone joins, leaves or changes group: their places (after combat if need be)
ns.On("GROUP_ROSTER_UPDATE", function() F.PlaceRaid(); F.UpdateRaid() end)
ns.On("PLAYER_REGEN_ENABLED", function()
	if pendingPlace then pendingPlace = false; F.PlaceRaid() end
end)
ns.On("PLAYER_TARGET_CHANGED", function() F.UpdateRaid() end)
ns.On("RAID_TARGET_UPDATE", function() F.UpdateRaid() end)

-- a member's health, aura or threat: just their cell
local function cellOf(unit)
	local i = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$"))
	return i and F.raidCells[i] or nil
end
F.RaidCell = cellOf
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_CONNECTION", "UNIT_HEAL_PREDICTION" }) do
	ns.On(e, function(_, unit)
		local f = cellOf(unit)
		if f and raid and raid:IsShown() then updateCell(f) end
	end)
end
-- the rest (range, names): twice a second is plenty for 40 cells
local acc = 0
ns.On("SR_TICK", function(_, dt)
	acc = acc + (dt or 0)
	if acc < 0.5 then return end
	acc = 0
	F.UpdateRaid()
end)
