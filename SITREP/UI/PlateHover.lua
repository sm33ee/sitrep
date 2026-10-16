-- SITREP · Hovering a unit
-- What Blizzard's unit tooltip at the side of the screen says, said SITREP's way,
-- for as long as the mouse is over a unit in the world (plates.hoverInfo; hold
-- Shift for Blizzard's tooltip anyway). Where (plates.hoverWhere):
--   "frame"  a window of its own you place anywhere (Layout: "Hover info"): the
--            name (class or friend/foe colour) and level (difficulty colour),
--            race and class (an NPC: beast family or creature type and its rank),
--            the guild (an NPC: what it is, "<Schmied>", "<Gemischtwaren>"), an
--            enemy player's matchup and the advice for its class,
--            what of its debuffs you can dispel (an orb in the kind's colour and
--            its name), for a quest NPC the objective and the quest (and what
--            the group's members with SITREP still need of it), and a legend
--            of every mark its plate shows right now (plates.hoverLegend). Any
--            unit, with or without a plate. Long lines wrap (some of Forever's
--            races have long names); the window grows with them.
--   "mouse"  the same window, opened next to the mouse (below right of it, a little
--            away; turned round at the screen's edges) and staying there while
--            the mouse is on that unit
--   "plate"  on the unit's plate: race/class in its bar, the quest line over its
--            name; units without a SITREP plate keep Blizzard's tooltip.
-- Values the client keeps secret are left out (a secret name goes to its line as
-- it is).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local N = ns.Plates
local read = ns.read
local format = string.format

local PH = {}
ns.PlateHover = PH

local RANK = { elite = "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = "Boss" }

local function P() return ns.P and ns.P.plates end
local function on() return P() and P().enabled and P().hoverInfo and ns.P.enabled end

-- The plate (skin) of the unit under the mouse, if SITREP draws one.
function PH.SkinOfMouseover()
	if read(UnitExists, "mouseover") ~= true then return nil end
	for unit, s in pairs(N.Current()) do
		if read(UnitIsUnit, unit, "mouseover") == true then return s, unit end
	end
	-- (in combat the comparison may be secret: the client's own plate for it)
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "mouseover")
		if ok and plate and not ns.isSecret(plate) then
			for unit, s in pairs(N.Current()) do
				if s:GetParent() == plate then return s, unit end
			end
		end
	end
	return nil
end

local function hex(r, g, b) return format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end

-- "Nachtelf Druide" / "Wolf · Elite": what the plate does not say.
function PH.Info(unit)
	if read(UnitIsPlayer, unit) == true then
		local race = read(UnitRace, unit)
		local cls, file = read(UnitClass, unit)
		local parts = {}
		if type(race) == "string" then parts[#parts + 1] = race end
		if type(cls) == "string" then
			local r, g, b = ns.Data.ClassColor(file)
			parts[#parts + 1] = "|cff" .. hex(r, g, b) .. cls .. "|r"
		end
		-- toughness: its health against its class and level, and yours against yours
		local ratio = ns.Sensors.Tough(unit, read(UnitGUID, unit))
		if ratio and not read(UnitIsUnit, unit, "player") then
			local mine = ns.Sensors.MyTough()
			parts[#parts + 1] = format("|cff8a9492HP %+.0f%%%s|r", (ratio - 1) * 100, mine and format(" (you %+.0f%%)", (mine - 1) * 100) or "")
		end
		return #parts > 0 and table.concat(parts, " ") or nil
	end
	local kind = read(UnitCreatureFamily, unit) or read(UnitCreatureType, unit)
	local rank = RANK[read(UnitClassification, unit) or ""]
	if type(kind) ~= "string" then kind = nil end
	local parts = {}
	if kind then parts[#parts + 1] = kind end
	if rank then parts[#parts + 1] = rank end
	-- how many of it until your next level (hostile mobs that give experience)
	local cls = read(UnitClassification, unit)
	local react = read(UnitReaction, unit, "player")
	if react and react <= 4 then
		local n = ns.XP and ns.XP.KillsToLevel(read(UnitLevel, unit), cls == "elite" or cls == "rareelite" or cls == "worldboss")
		if n then parts[#parts + 1] = format("|cffb39cffLEVEL UP IN %d|r", n) end
	end
	-- how long it has been up (from its GUID)
	local age = ns.Sensors.SpawnAge(read(UnitGUID, unit))
	if age then parts[#parts + 1] = "|cff8a9492up " .. ns.HUD.Since(age) .. "|r" end
	return #parts > 0 and table.concat(parts, " · ") or nil
end

-- "Group: Mira 3 · Bob": what your group's members (those with SITREP: QuestShare)
-- still need of the objective a unit is for; a name in green is done. nil: no one shares it.
-- One member's line: what they still need of what ("Dagehtmir – 2 more Große
-- Geiferzahnschnauze"; a kill objective names the mob: "3 more Kobold"), or done.
local function thing(text)
	local t = ns.Bestiary and ns.Bestiary.ObjectiveMob(text)
		or (ns.Questbook and ns.Questbook.BareText(text)) or text
	return type(t) == "string" and t:gsub("^%s*%-%s*", "") or "?"
end
function PH.NeedLine(name, have, need, text)
	name = (name or "?"):match("^(%S+)") or name
	if have and need and have >= need then return format("  |cff5cff8d%s – done|r", name) end
	if have and need then return format("  %s – |cffe0e8e5%d more|r %s", name, need - have, thing(text)) end
	return "  " .. name
end
local GROUP = "|cff8a9492Group|r"

-- The group members' lines from the tooltip itself: for members without SITREP too.
function PH.TipGroup(party)
	if type(party) ~= "table" or #party == 0 then return nil end
	local lines = { GROUP }
	for _, p in ipairs(party) do
		local have, need = ns.Quests.Counts(p.text)
		lines[#lines + 1] = PH.NeedLine(p.name, have, need, p.text)
	end
	return table.concat(lines, "\n")
end

function PH.Group(objective, title)
	if not (ns.QuestShare and IsInGroup and IsInGroup()) then return nil end
	local q, n = ns.Quests.Match(objective, title)
	if not (q and n and type(q.id) == "number") then return nil end
	local members = ns.QuestShare.ForQuest(q.id)
	if #members == 0 then return nil end
	local text = q.objectives[n] and q.objectives[n].text or objective
	local lines = { GROUP }
	for _, m in ipairs(members) do
		local c = m.counts[n]
		if m.complete then lines[#lines + 1] = PH.NeedLine(m.name, 1, 1, text)
		elseif c then lines[#lines + 1] = PH.NeedLine(m.name, c[1], c[2], text) end
	end
	return #lines > 1 and table.concat(lines, "\n") or nil
end

-- An NPC's title ("Schmied", "Gemischtwaren"): the line under its name in the
-- client's tooltip. Modern tooltips put it in angle brackets; Classic's write it
-- bare, so a bare line counts too unless it is something else: the level line
-- (it has the level's digits or "??"), its creature type, a faction, a quest's
-- lines, a pet's owner. nil for players and NPCs without one. /sitrep npcprobe
-- shows the lines as the client gives them.
local QUEST_LINES
local function tipLines(unit)
	local T = C_TooltipInfo and C_TooltipInfo.GetUnit
	if not T then return nil end
	local ok, data = pcall(T, unit)
	if not (ok and type(data) == "table") or ns.isSecret(data) or type(data.lines) ~= "table" then return nil end
	return data.lines
end
local function clean(t)
	t = ns.plain(t)
	if type(t) ~= "string" then return nil end
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
	return t ~= "" and t or nil
end
function PH.Title(unit)
	if read(UnitIsPlayer, unit) ~= false then return nil end
	local lines = tipLines(unit)
	if not lines or #lines < 2 then return nil end
	local kinds = Enum and Enum.TooltipDataLineType
	if not QUEST_LINES and kinds then
		QUEST_LINES = {}
		for _, k in ipairs({ "QuestTitle", "QuestObjective", "QuestPlayer", "UnitOwner" }) do
			if kinds[k] then QUEST_LINES[kinds[k]] = true end
		end
	end
	local l = lines[2]
	local text = clean(l and l.leftText)
	if not text then return nil end
	local bracketed = text:match("^<(.+)>$")
	if bracketed then return bracketed end
	if QUEST_LINES and QUEST_LINES[ns.plain(l.type) or false] then return nil end
	if text:find("%d") or text:find("??", 1, true) then return nil end -- (the level line)
	if text == read(UnitCreatureType, unit) or text == read(UnitCreatureFamily, unit) then return nil end
	if text == read(UnitFactionGroup, unit) or text == clean(read(UnitName, unit)) then return nil end
	-- (the client's words for PvP and the factions, where it has them)
	for _, g in ipairs({ "PVP", "FACTION_ALLIANCE", "FACTION_HORDE" }) do if text == rawget(_G, g) then return nil end end
	if text == "Alliance" or text == "Horde" or text == "Allianz" then return nil end
	if read(UnitPlayerControlled, unit) == true then return nil end -- (a pet: its owner's line)
	return text
end

-- /sitrep npcprobe: the tooltip lines of your target and of the unit under the mouse.
function PH.Probe()
	ns.Capture("npcprobe", function()
		for _, unit in ipairs({ "target", "mouseover" }) do
			if read(UnitExists, unit) == true then
				local lines = tipLines(unit)
				ns.print("%s: %s, title: %s", unit, lines and (#lines .. " lines") or "no tooltip data (secret or missing)", tostring(PH.Title(unit)))
				-- the line types by name (the client's Enum.TooltipDataLineType)
				local typeName = {}
				for k, v in pairs(Enum and Enum.TooltipDataLineType or {}) do typeName[v] = k end
				for n, l in ipairs(lines or {}) do
					local t = ns.plain(l.type)
					ns.print("  %d [type %s%s] %s%s", n, tostring(t), typeName[t] and (" " .. typeName[t]) or "", tostring(clean(l.leftText)),
						clean(l.rightText) and ("  |  " .. clean(l.rightText)) or "")
				end
				-- how SITREP reads its quest lines: yours, the group's
				local r = lines and ns.Quests.TipQuestLines(lines)
				if r then
					local party = {}
					for _, p in ipairs(r.party) do party[#party + 1] = p.name .. ": " .. tostring(clean(p.text)) end
					local have, need
					if r.mine then have, need = ns.Quests.MyCounts(r.mine, r.title) end
					ns.print("  SITREP reads: quest %s; yours: %s (your log: %s); the group's: %s", tostring(r.title), tostring(r.mine and clean(r.mine)),
						have and need and (have .. "/" .. need) or "-", #party > 0 and table.concat(party, "; ") or "none")
				end
			else
				ns.print("%s: none", unit)
			end
		end
	end)
end

-- "Dispel ● Hex of Weakness ● Poison": the debuffs on a friend you can remove,
-- each with an orb in its kind's colour (as on its plate).
local KIND = { Magic = "Magic", Curse = "Curse", Disease = "Disease", Poison = "Poison", Enrage = "Enrage" }
function PH.Dispel(unit)
	if not (ns.Auras and ns.Auras.RemovableAuras) then return nil end
	if read(UnitIsFriend, "player", unit) ~= true then return nil end
	local list = ns.Auras.RemovableAuras(unit)
	if #list == 0 then return nil end
	local parts = {}
	for i, a in ipairs(list) do
		if i > 4 then parts[#parts + 1] = "|cff8a9492+" .. (#list - 4) .. "|r" break end
		local c = ns.Data.DISPEL_COLOR[a.dispel] or ns.Data.DISPEL_COLOR.none
		local name = type(a.name) == "string" and a.name or KIND[a.dispel] or a.dispel
		parts[#parts + 1] = K.Glyph("dot", c[1], c[2], c[3], 9) .. " " .. name
	end
	return "|cff8a9492Dispel|r  " .. table.concat(parts, "  ")
end

-- The marks its plate shows right now, each with what it means: rings, orbs and
-- tags (in the plate's own glyphs and words), one line each.
local RING = { foe = { 1, 0.36, 0.30 }, group = { 0.44, 0.94, 0.65 }, kill = { 1, 0.45, 0.1 }, mate = { 0.67, 0.67, 1 } }
local MEANS = {
	you = "targets you", targeted = "enemy players on this friend", healer = "a healer", hvt = "high-value target",
	oom = "healer nearly out of mana", faker = "fakes casts (stops them)", locked = "your kick locked a school",
	rare = "rare", aggroIn = "you are inside its aggro range", aggroNear = "nearly in its aggro range",
	quest = "your quests need it", owner = "owner of the pet you target",
}
function PH.Legend(unit)
	local s = PH.SkinOfMouseover()
	if not s then
		for u, sk in pairs(N.Current()) do if read(UnitIsUnit, u, unit) == true then s = sk break end end
	end
	if not (s and s.active) then return nil end
	local out = {}
	local function ring(c, text) out[#out + 1] = K.Glyph("ring", c[1], c[2], c[3], 10) .. "  " .. text end
	if s.foe and s.foe:IsShown() then ring(RING.foe, "enemy player") end
	if s.mateRing and s.mateRing:IsShown() then ring(RING.mate, "in your group") end
	if s.grp and s.grp:IsShown() and s.grpN then
		ring(RING.group, format("%d of your group on it%s", s.grpN, s.grpTop and ", the most of you" or ""))
	end
	if s.kill and s.kill:IsShown() then ring(RING.kill, format("kill window: under %d%%, in your reach", P().killPct or 20)) end
	if s.disp and s.disp:IsShown() then
		out[#out + 1] = K.Glyph("dot", 0.64, 0.19, 0.79, 10) .. "  something on it you can dispel"
	end
	for _, kind in ipairs(s.kinds or {}) do
		if MEANS[kind] then
			local icon = N.Tag(kind, kind == "targeted" and 1 or kind == "locked" and "" or nil)
			out[#out + 1] = (icon or "") .. "  " .. MEANS[kind]
		end
	end
	if s.toughShown then out[#out + 1] = "|cff8a9492HP±|r  its health against its class and level" end
	if s.mana and s.mana:IsShown() then out[#out + 1] = "|cff5aa0ff—|r  its mana" end
	return #out > 0 and table.concat(out, "\n") or nil
end

local function line(s)
	if s.hover then return s.hover end
	s.hover = K.Font(s.text, 9, C.text, K.FONT, "OUTLINE")
	s.hover:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.hover:Hide()
	-- a quest NPC: what it is for, above its name
	s.hoverQuest = K.Font(s.text, 10, { 1, 0.82, 0, 1 }, nil, "OUTLINE")
	s.hoverQuest:SetPoint("BOTTOM", s.name, "TOP", 0, 2)
	s.hoverQuest:Hide()
	return s.hover
end

local function hideOn(s)
	if s.hover then s.hover:Hide() end
	if s.hoverQuest then s.hoverQuest:Hide() end
end

-- Show it on the hovered plate, clear it on the one hovered before.
---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W_ = 240
local function buildWindow()
	if PH.frame then return PH.frame end
	local f = CreateFrame("Frame", "SITREP_HoverInfo", UIParent)
	f:SetSize(W_, 40)
	f:SetFrameStrata("HIGH")
	f.bg = K.Backdrop(f, C.bg, 12)
	f.bg:SetAllPoints()
	K.Border(f, C.line, nil, 12)
	K.Brackets(f, 7, 2)
	f.level = K.Font(f, 12, C.text, K.FONT, "OUTLINE")
	f.level:SetPoint("TOPLEFT", 8, -7)
	f.name = K.Font(f, 13, C.text, nil, "OUTLINE")
	f.name:SetPoint("LEFT", f.level, "RIGHT", 5, 0)
	f.name:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false)
	f.info = K.Font(f, 11, C.text, nil, "")
	f.info:SetPoint("TOPLEFT", 8, -24)
	f.info:SetWidth(W_ - 16)
	f.info:SetJustifyH("LEFT")
	f.info:SetWordWrap(true)
	f.guild = K.Font(f, 10, C.dim, nil, "")
	f.guild:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -3)
	-- an enemy player: the matchup and the advice
	f.intel = K.Font(f, 10, C.dim, nil, "")
	f.intel:SetWidth(W_ - 16)
	f.intel:SetJustifyH("LEFT")
	f.intel:SetWordWrap(true)
	-- the marks on its plate, explained
	f.legend = K.Font(f, 10, C.text, nil, "")
	f.legend:SetWidth(W_ - 16)
	f.legend:SetJustifyH("LEFT")
	f.legend:SetWordWrap(true)
	f.legend:SetSpacing(2)
	-- what you can dispel on it
	f.dispel = K.Font(f, 10, C.text, nil, "")
	f.dispel:SetPoint("TOPLEFT", f.guild, "BOTTOMLEFT", 0, -3)
	f.dispel:SetWidth(W_ - 16)
	f.dispel:SetJustifyH("LEFT")
	f.dispel:SetWordWrap(true)
	f.quest = K.Font(f, 11, { 1, 0.82, 0, 1 }, nil, "")
	f.quest:SetPoint("TOPLEFT", f.dispel, "BOTTOMLEFT", 0, -4)
	f.quest:SetWidth(W_ - 16)
	f.quest:SetJustifyH("LEFT")
	f.questTitle = K.Font(f, 10, C.dim, nil, "")
	f.questTitle:SetPoint("TOPLEFT", f.quest, "BOTTOMLEFT", 0, -2)
	f.group = K.Font(f, 10, C.text, nil, "")
	f.group:SetPoint("TOPLEFT", f.questTitle, "BOTTOMLEFT", 0, -2)
	f.group:SetWidth(W_ - 16)
	f.group:SetJustifyH("LEFT")
	f.group:SetWordWrap(true)
	-- the bestiary: how often and where seen, what it is wanted for
	f.seen = K.Font(f, 10, C.dim, nil, "")
	f.seen:SetPoint("TOPLEFT", f.group, "BOTTOMLEFT", 0, -2)
	f.seen:SetWidth(W_ - 16)
	f.seen:SetJustifyH("LEFT")
	f.seen:SetWordWrap(true)
	f.unlock = K.Tex(f, "OVERLAY", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	K.Movable(f, "hoverInfo", { "BOTTOMRIGHT", "BOTTOMRIGHT", -320, 220 })
	f:Hide()
	PH.frame = f
	return f
end

local function frameMode() return P() and P().hoverWhere ~= "plate" end
PH.FrameMode = frameMode

-- The lines that have something, one under the other, each as tall as it
-- wrapped; the window as tall as they are.
function PH.Layout(f)
	local function tall(fs, one) return math.max(one, read(fs.GetStringHeight, fs) or one) end
	local h, prev = 24, nil
	for _, row in ipairs({ { f.info, 0, 13 }, { f.guild, 3, 12 }, { f.intel, 3, 12 }, { f.dispel, 3, 12 },
		{ f.quest, 4, 13 }, { f.questTitle, 2, 12 }, { f.group, 2, 12 }, { f.seen, 4, 12 }, { f.legend, 6, 12 } }) do
		local fs, gap, one = row[1], row[2], row[3]
		-- (an emptied font string may answer nil instead of "")
		local t = fs:GetText()
		if t ~= nil and t ~= "" then
			fs:ClearAllPoints()
			if prev then fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap) else fs:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -24) end
			fs:Show()
			h = h + (prev and gap or 0) + tall(fs, one)
			prev = fs
		else
			fs:Hide()
		end
	end
	if not prev then h = h + 13 end
	f:SetHeight(h + 8)
end

-- "mouse": the window below right of the mouse, MOUSE_GAP away, turned to the left
-- or above where the screen ends. Placed once per unit: it stays while you hover it.
local MOUSE_GAP = 28
function PH.PlaceAtMouse(f, unit)
	local key = read(UnitGUID, unit) or read(GetUnitName, unit, false) or unit
	if PH.placedFor == key and f:IsShown() then return end
	PH.placedFor = key
	local cx, cy = GetCursorPosition()
	local es = read(f.GetEffectiveScale, f) or 1
	local us = read(UIParent.GetEffectiveScale, UIParent) or 1
	-- in the window's own units: the mouse, the screen, the window
	local x, y = cx / es, cy / es
	local sw = (read(UIParent.GetWidth, UIParent) or 1920) * us / es
	local w, h = read(f.GetWidth, f) or 240, read(f.GetHeight, f) or 60
	local gap = MOUSE_GAP
	local left = x + gap
	if left + w > sw then left = x - gap - w end
	local top = y - gap
	if top - h < 0 then top = y + gap + h end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(0, left), top)
end

-- Fill the window for a unit (nil: hide it).
function PH.Fill(unit)
	local f = buildWindow()
	if not unit then f:Hide(); PH.placedFor = nil return end
	-- the name: plain in its colour, or a secret name as the client gave it
	local r, g, b = 1, 1, 1
	if read(UnitIsPlayer, unit) == true then
		local _, file = read(UnitClass, unit)
		r, g, b = ns.Data.ClassColor(file)
	else
		local react = read(UnitReaction, unit, "player")
		if react then
			if react <= 3 then r, g, b = 1, 0.25, 0.2 elseif react == 4 then r, g, b = 1, 0.85, 0.2 else r, g, b = 0.3, 1, 0.4 end
			-- a friendly NPC: sky blue, as on its plate (players are green)
			if react >= 5 and read(UnitPlayerControlled, unit) ~= true then r, g, b = N.NPC_NAME[1], N.NPC_NAME[2], N.NPC_NAME[3] end
		end
	end
	if not pcall(function() f.name:SetText(GetUnitName(unit, false)) end) then f.name:SetText("") end
	f.name:SetTextColor(r, g, b)
	local lvl = read(UnitLevel, unit)
	if lvl then
		local lr, lg, lb = N.LevelColor(lvl)
		f.level:SetText(lvl > 0 and tostring(lvl) or "??")
		f.level:SetTextColor(lr, lg, lb)
	else
		f.level:SetText("")
	end
	f.info:SetText(PH.Info(unit) or "")
	local guild = read(UnitIsPlayer, unit) == true and read(GetGuildInfo, unit) or PH.Title(unit)
	f.guild:SetText(type(guild) == "string" and ("<" .. guild .. ">") or "")
	f.intel:SetText(ns.Frames.IntelText and ns.Frames.IntelText(unit) or "")
	f.dispel:SetText(PH.Dispel(unit) or "")
	local objective, title, party, groupTitle = ns.Quests.ForUnit(unit)
	if objective or title then
		-- your own count (your log), not one the tooltip shows for a member
		local have, need
		if objective then have, need = ns.Quests.MyCounts(objective, title) end
		local o = objective and ns.QuestTracker.ObjectiveText({ text = objective, have = have, need = need }) or ""
		f.quest:SetText("! " .. o)
		f.questTitle:SetText(title or "")
		f.group:SetText(PH.Group(objective, title) or PH.TipGroup(party) or "")
	elseif groupTitle then
		-- only the group still needs it
		f.quest:SetText("")
		f.questTitle:SetText(groupTitle)
		f.group:SetText(PH.TipGroup(party) or "")
	else
		f.quest:SetText("")
		f.questTitle:SetText("")
		f.group:SetText("")
	end
	local npc = ns.Bestiary and read(UnitIsPlayer, unit) == false and ns.Quests.NpcID(read(UnitGUID, unit))
	f.seen:SetText(npc and ns.Bestiary.Line(npc) or "")
	local legend = P().hoverLegend ~= false and PH.Legend(unit) or nil
	f.legend:SetText(legend or "")
	PH.Layout(f)
	if P().hoverWhere == "mouse" and not f.placing then PH.PlaceAtMouse(f, unit) end
	f.placing = false
	f:Show()
end

-- Size, opacity, background, place; shown while placing it.
function PH.ApplyWindow()
	local f = buildWindow()
	local H = ns.P.hud
	f:SetScale(H.scale * (H.frameScale.hoverInfo or 1))
	f:SetAlpha(K.Opacity("hoverInfo"))
	K.Background(f.bg, "hoverInfo")
	local atMouse = P().hoverWhere == "mouse"
	if not atMouse then f:RestorePosition() end
	f.unlock:SetShown(not H.locked and not atMouse)
	f:EnableMouse(not H.locked and not atMouse)
	-- (placing it: only where it has a place of its own)
	if not H.locked and on() and frameMode() and not atMouse then
		f.placing = true
		f.level:SetText("60"); f.level:SetTextColor(1, 0.82, 0)
		f.name:SetText("Hover info"); f.name:SetTextColor(1, 1, 1)
		f.info:SetText("Race and class, or type and rank")
		f.guild:SetText("<Guild>")
		f.intel:SetText(""); f.dispel:SetText(""); f.legend:SetText(""); f.group:SetText(""); f.seen:SetText("")
		f.quest:SetText("! 3/8 Kobold Vermin slain")
		f.questTitle:SetText("Kobold Camp Cleanup")
		PH.Layout(f)
		f:Show()
	elseif f.placing then
		f.placing = false
		f:Hide()
	end
end

function PH.Update()
	if frameMode() then
		-- the window: any unit under the mouse; nothing on the plates
		if PH.shown then hideOn(PH.shown); PH.shown = nil end
		local unit = on() and read(UnitExists, "mouseover") == true and "mouseover" or nil
		if PH.frame and PH.frame.placing then return end
		PH.Fill(unit)
		PH.watch:SetShown(unit ~= nil)
		return
	end
	if PH.frame and PH.frame:IsShown() and not PH.frame.placing then PH.frame:Hide() end
	local s, unit
	if on() then s, unit = PH.SkinOfMouseover() end
	if PH.shown and PH.shown ~= s then hideOn(PH.shown) end
	PH.shown = nil
	if not s then PH.watch:Hide() return end
	local text = PH.Info(unit)
	local title = PH.Title(unit)
	if title then text = "<" .. title .. ">" .. (text and ("  " .. text) or "") end
	local l = line(s)
	l:SetText(text or "")
	l:SetShown(text ~= nil)
	-- part of one of your quests: the objective and the quest
	local objective, title, party = ns.Quests.ForUnit(unit)
	if objective or title then
		local have, need
		if objective then have, need = ns.Quests.MyCounts(objective, title) end
		local o = objective and ns.QuestTracker.ObjectiveText({ text = objective, have = have, need = need }) or ""
		local group = PH.Group(objective, title) or PH.TipGroup(party)
		s.hoverQuest:SetText("! " .. o .. (title and ("  |cff9a9a9a" .. title .. "|r") or "") .. (group and ("\n" .. group) or ""))
		s.hoverQuest:Show()
	else
		s.hoverQuest:Hide()
	end
	PH.shown = s
	PH.watch:Show() -- until the mouse leaves it
end

-- Blizzard's tooltip for a unit in the world: left out when its plate says it.
local function tooltipUnit(tip)
	if tip ~= GameTooltip or not on() then return end
	if IsShiftKeyDown and IsShiftKeyDown() then return end
	local owner = tip.GetOwner and tip:GetOwner()
	if owner ~= UIParent and owner ~= WorldFrame then return end -- (unit frames keep theirs)
	if frameMode() then
		if read(UnitExists, "mouseover") ~= true then return end
	elseif not PH.SkinOfMouseover() then
		return
	end
	tip:Hide()
end
PH.TooltipUnit = tooltipUnit

-- the mouse leaving a unit sends no event: a light look while one is shown
PH.watch = CreateFrame("Frame")
PH.watch:Hide()
local acc = 0
PH.watch:SetScript("OnUpdate", ns.Timed("hover: watch (PH.watch)", function(_, e)
	acc = acc + e
	if acc < 0.1 then return end
	acc = 0
	if frameMode() then
		if read(UnitExists, "mouseover") ~= true and PH.frame and PH.frame:IsShown() and not PH.frame.placing then PH.Update() end
	elseif not PH.shown or PH.SkinOfMouseover() ~= PH.shown then
		PH.Update()
	end
end))

ns.On("SR_LOGIN", function()
	PH.ApplyWindow()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, tooltipUnit)
	elseif GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", tooltipUnit)
	end
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() PH.Update() end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 7) == "plates." or key:sub(1, 4) == "hud." then PH.ApplyWindow(); PH.Update() end
end)
