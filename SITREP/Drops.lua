-- SITREP · Drops: how many kills a quest item takes, learned
-- Forever has no database to look drop rates up in, so SITREP counts them:
--   kills   every kill the client gives you experience for ("Defias-Schmugglerin
--           stirbt, Ihr bekommt 87 Erfahrung"): yours and your group's (each
--           member with the quest may loot its quest item), counted for every
--           item objective still open in your log, by the mob's name
--   items   an item objective's counter going up (Quests: SR_OBJECTIVE_UP) is
--           the corpse you looted last (the loot window says whose it is) or,
--           without that, the kill before it: that mob gets the items
-- Mobs that never gave the item are not its source and do not count. Kept for the
-- account per quest and objective (SITREP_DB.drops["questID:n"] = { text, mobs =
-- { [name] = { k kills, h items } } }), so your next character knows them.
-- Kills per item: few kills say little, so the guess starts at Quests' old one
-- (PRIOR kills per item) and moves to what was seen as kills come in: items per
-- kill = (items + PRIOR_W / PRIOR) / (kills + PRIOR_W).
-- Grey mobs give no experience: their kills are not seen. Corpses you leave
-- unlooted count as kills without items: the rate comes out worse than it is.
--
-- In the loot window, a quest's item is marked (LootMark): a gold frame and a "!"
-- on its icon, and beside its name what you have of it ("4/10", "done" in grey
-- when the objective is full); an item that starts a quest gets a star and "starts
-- a quest". The game says it per slot (GetLootSlotInfo: isQuestItem, questID,
-- isActive), and Forever does not always (reported, 4.10.1): an item an objective
-- in your log names counts as one anyway.
-- The same in your bags (BagMark): the gold frame and the "!" (inside the icon's
-- corner there), gold also when the objective is full (grey was hard to see among
-- the bag's slots), a star for an item that starts a quest. A frame of SITREP's own over Blizzard's button, made out of combat only;
-- Blizzard's button itself is not touched (its bags taint easily: FOREVER-API). Both loot windows: the classic one (LootButton1..4, by their slot)
-- and the modern one (LootFrame's scroll box). /sitrep lootprobe: what is there.
--
-- Self-contained, to take out in one go: this file and its line in the TOC, the
-- "drops" and "lootprobe" commands in Core.lua, its calls in Quests.Value and the quest tracker's
-- tooltip, and its block in tests/run.lua.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format = string.format

local D = {}
ns.Drops = D
local PRIOR, PRIOR_W = 1.6, 4 -- kills per item before anything is seen, and how many kills it weighs
local HIT_WINDOW = 120         -- seconds a kill or a loot stays the item's likely source
D.PRIOR, D.PRIOR_W = PRIOR, PRIOR_W

local function book()
	if not SITREP_DB then return {} end
	SITREP_DB.drops = SITREP_DB.drops or {}
	return SITREP_DB.drops
end
D.Book = book

-- The mob's name in an experience message, from the client's own words for it.
local killPattern
local function escape(s) return (s:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")) end
function D.KillName(text)
	text = plain(text)
	if type(text) ~= "string" then return nil end
	if not killPattern then
		local fmt = rawget(_G, "COMBATLOG_XPGAIN_FIRSTPERSON")
		local after = type(fmt) == "string" and fmt:match("^%%s(.-)%%d")
		killPattern = after and ("^(.-)" .. escape(after)) or false
	end
	local name = killPattern and text:match(killPattern)
	-- (clients without the string: German and English)
	name = name or text:match("^(.-) stirbt, ") or text:match("^(.-) dies, you gain ")
	return name ~= "" and name or nil
end

-- An item objective (things to collect, not to kill)?
local function isItem(o)
	if o.kind then return o.kind == "item" end
	local t = (o.text or ""):lower()
	return not (t:find("slain", 1, true) or t:find("getötet", 1, true))
end
D.IsItem = isItem

local lastKill, lastLoot -- { name, at }
-- A kill: one more try at every open item objective.
function D.Kill(name, now)
	if not name then return end
	now = now or GetTime()
	lastKill = { name = name, at = now }
	for _, q in ipairs(ns.Quests.List()) do
		if not q.complete and not q.failed then
			for n, o in ipairs(q.objectives) do
				if not o.done and isItem(o) then
					local key = q.id .. ":" .. n
					local e = book()[key] or { mobs = {} }
					book()[key] = e
					e.text = ns.Questbook and ns.Questbook.BareText(o.text) or o.text
					local m = e.mobs[name] or { k = 0, h = 0 }
					e.mobs[name] = m
					m.k = m.k + 1
				end
			end
		end
	end
end

-- An item objective's counter went up: the items go to the mob looted (or killed) last.
function D.Items(questID, n, delta, q, now)
	now = now or GetTime()
	local o = q and q.objectives and q.objectives[n]
	if o and not isItem(o) then return end
	local src = (lastLoot and now - lastLoot.at <= HIT_WINDOW and lastLoot)
		or (lastKill and now - lastKill.at <= HIT_WINDOW and lastKill)
	if not src then return end
	local e = book()[questID .. ":" .. n]
	local m = e and e.mobs[src.name]
	if not m then return end -- (no kill of it was counted while the objective was open)
	m.h = m.h + (delta or 1)
	if m.h > m.k then m.k = m.h end -- (looted a kill whose message was missed)
end

-- Kills per item for an objective: the guess, the kills and items it rests on,
-- and the mobs that gave it (nil: no data yet).
function D.KillsPerItem(questID, n)
	local e = SITREP_DB and SITREP_DB.drops and SITREP_DB.drops[questID .. ":" .. n]
	if not e then return nil end
	local K, H, from = 0, 0, {}
	for name, m in pairs(e.mobs) do
		if m.h > 0 then K, H = K + m.k, H + m.h; from[#from + 1] = name end
	end
	if H == 0 then return nil end
	table.sort(from)
	local perKill = (H + PRIOR_W / PRIOR) / (K + PRIOR_W)
	return 1 / perKill, K, H, from
end

-- Which corpse the loot window shows: its name, from the units seen lately.
local names = {}
local nameCount = 0
local function remember(unit)
	local guid, name = read(UnitGUID, unit), read(UnitName, unit)
	if type(guid) ~= "string" or type(name) ~= "string" or names[guid] then return end
	if nameCount > 300 then wipe(names); nameCount = 0 end
	names[guid] = name
	nameCount = nameCount + 1
end
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) remember(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() remember("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() remember("mouseover") end)
ns.On("LOOT_OPENED", function()
	local info = rawget(_G, "GetLootSourceInfo")
	if not (info and GetNumLootItems) then return end
	for slot = 1, read(GetNumLootItems) or 0 do
		local guid = read(info, slot)
		local name = guid and names[guid]
		if name then lastLoot = { name = name, at = GetTime() } return end
	end
end)
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(_, text) D.Kill(D.KillName(text)) end)
ns.On("SR_OBJECTIVE_UP", function(_, questID, n, delta, q) D.Items(questID, n, delta, q) end)

---------------------------------------------------------------------------
-- Marks in the loot window
---------------------------------------------------------------------------
-- (the Kit loads after this file: taken when used)
local GOLD, GREY = { 1, 0.82, 0.3 }, { 0.55, 0.57, 0.56 }

-- What a slot holds, as the game says: name, a quest's item?, its quest, starts one?
local function slotInfo(slot)
	if not GetLootSlotInfo then return nil end
	local ok, _, name, _, _, _, _, isQuest, questID, isActive = pcall(GetLootSlotInfo, slot)
	if not ok or type(name) ~= "string" then return nil end
	isQuest = plain(isQuest) == true
	questID = tonumber(plain(questID))
	return name, isQuest, questID, plain(isActive)
end
D.SlotInfo = slotInfo

-- An item's objective in your log: have, need (nil: no objective names it).
function D.ItemProgress(name, questID)
	for _, q in ipairs(ns.Quests.List()) do
		if not questID or q.id == questID then
			for _, o in ipairs(q.objectives) do
				local bare = ns.Questbook and ns.Questbook.BareText(o.text) or o.text
				if bare == name or (o.text or ""):find(name, 1, true) then return o.have, o.need, o.done end
			end
		end
	end
	return nil
end

-- The loot window's buttons, with the slot each shows: { { button, slot } }.
function D.LootButtons()
	local out = {}
	for i = 1, 8 do
		local b = _G["LootButton" .. i]
		if type(b) == "table" and b.IsShown and b:IsShown() and b.slot then out[#out + 1] = { b, b.slot } end
	end
	local sb = _G.LootFrame and _G.LootFrame.ScrollBox
	if #out == 0 and type(sb) == "table" and sb.ForEachFrame then
		pcall(sb.ForEachFrame, sb, function(f)
			local slot = f.GetSlotIndex and f:GetSlotIndex() or (f.GetElementData and (f:GetElementData() or {}).slotIndex)
			if slot then out[#out + 1] = { f, slot } end
		end)
	end
	return out
end

-- One button's mark: shown for a quest's item (or one that starts a quest), gone otherwise.
local function markOf(b)
	if b.srQuest then return b.srQuest end
	local K = ns.Kit
	local icon = rawget(b, "Item") or b
	local name = rawget(b, "Text") or (b.GetName and b:GetName() and _G[b:GetName() .. "Text"])
	local m = CreateFrame("Frame", nil, icon)
	m:SetAllPoints(icon)
	m:SetFrameLevel((icon:GetFrameLevel() or 1) + 5)
	m.border = K.Border(m, GOLD, 2, 0)
	m.bang = m:CreateTexture(nil, "OVERLAY")
	m.bang:SetSize(16, 16)
	m.bang:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 12, 4) -- (outside the icon's corner: 4.10.3 sat 8 px further in)
	m.text = K.Font(m, 10, GOLD, K.FONT, "OUTLINE")
	if type(name) == "table" and name.GetObjectType then m.text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
	else m.text:SetPoint("LEFT", icon, "RIGHT", 6, -10) end
	b.srQuest = m
	return m
end

function D.MarkLoot()
	local K = ns.Kit
	for _, e in ipairs(D.LootButtons()) do
		local b, slot = e[1], e[2]
		local name, isQuest, questID, isActive = slotInfo(slot)
		-- (the game's flag, or an objective in your log that names it)
		if name and not isQuest and D.ItemProgress(name) then isQuest = true end
		if name and isQuest then
			local m = markOf(b)
			local starts = questID and isActive == false
			if starts then
				m.bang:SetTexture(K.MEDIA .. "glyph_star")
				m.text:SetText("starts a quest")
				m.border:SetColor(GOLD[1], GOLD[2], GOLD[3], 1)
				m.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
			else
				m.bang:SetTexture(K.MEDIA .. "glyph_bang")
				local have, need, done = D.ItemProgress(name, questID)
				local full = done or (have and need and have >= need)
				local c = full and GREY or GOLD
				m.border:SetColor(c[1], c[2], c[3], 1)
				m.text:SetText(full and "done" or (have and need and format("%d/%d", have, need)) or "quest item")
				m.text:SetTextColor(c[1], c[2], c[3])
			end
			m.bang:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
			m.slot = slot
			m:Show()
		elseif b.srQuest then
			b.srQuest:Hide()
		end
	end
end
local function markSoon()
	D.MarkLoot()
	-- (the window fills its buttons on the same event, maybe a frame later: again just after)
	if C_Timer then
		C_Timer.After(0.05, D.MarkLoot)
		C_Timer.After(0.25, D.MarkLoot)
	end
end
ns.On("LOOT_OPENED", markSoon)
ns.On("LOOT_SLOT_CHANGED", markSoon)
ns.On("LOOT_SLOT_CLEARED", markSoon)
ns.On("SR_LOGIN", function()
	-- the classic window's pages
	if type(_G.LootFrame_Update) == "function" then hooksecurefunc("LootFrame_Update", D.MarkLoot) end
end)

---------------------------------------------------------------------------
-- Marks in the bags
---------------------------------------------------------------------------
-- What a bag slot holds: name, a quest's item (the game's flag)?, its quest, starts one?
local function bagSlotInfo(bag, slot)
	local CC = C_Container
	if not (CC and CC.GetContainerItemInfo) then return nil end
	local ok, info = pcall(CC.GetContainerItemInfo, bag, slot)
	if not ok or type(info) ~= "table" then return nil end
	local link = plain(info.hyperlink)
	local name = type(link) == "string" and link:match("%[(.-)%]") or nil
	if not name and info.itemID and C_Item and C_Item.GetItemNameByID then name = plain(C_Item.GetItemNameByID(info.itemID)) end
	if type(name) ~= "string" then return nil end
	local isQuest, questID, isActive = false, nil, nil
	if CC.GetContainerItemQuestInfo then
		local okQ, q = pcall(CC.GetContainerItemQuestInfo, bag, slot)
		if okQ and type(q) == "table" then
			isQuest, questID, isActive = plain(q.isQuestItem) == true, tonumber(plain(q.questID)), plain(q.isActive)
		end
	end
	return name, isQuest, questID, isActive
end
D.BagSlotInfo = bagSlotInfo

-- The bag windows' item buttons shown: { button } (combined backpack and single bags,
-- modern and classic).
function D.BagButtons()
	local out = {}
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, f in ipairs(frames) do
		if type(f) == "table" and f.IsShown and f:IsShown() then
			if f.EnumerateValidItems then
				pcall(function() for _, b in f:EnumerateValidItems() do out[#out + 1] = b end end)
			elseif type(rawget(f, "Items")) == "table" then
				for _, b in ipairs(f.Items) do out[#out + 1] = b end
			elseif f.GetName and f:GetName() then
				for j = 1, 40 do
					local b = _G[f:GetName() .. "Item" .. j]
					if b then out[#out + 1] = b end
				end
			end
		end
	end
	return out
end

local function bagMarkOf(b)
	if b.srBagQuest then return b.srBagQuest end
	if InCombatLockdown() then return nil end -- (made out of combat only)
	local K = ns.Kit
	local m = CreateFrame("Frame", nil, b)
	m:SetAllPoints(b)
	m:SetFrameLevel((b:GetFrameLevel() or 1) + 3)
	m.border = K.Border(m, GOLD, 2, 0)
	m.bang = m:CreateTexture(nil, "OVERLAY")
	m.bang:SetSize(14, 14)
	m.bang:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1) -- (inside the icon: the bag's slots sit close together)
	b.srBagQuest = m
	return m
end

function D.MarkBags()
	local K = ns.Kit
	for _, b in ipairs(D.BagButtons()) do
		local bag = b.GetBagID and b:GetBagID() or (b.GetParent and b:GetParent() and b:GetParent().GetID and b:GetParent():GetID())
		local slot = b.GetID and b:GetID()
		local name, isQuest, questID, isActive
		if bag and slot then name, isQuest, questID, isActive = bagSlotInfo(bag, slot) end
		local have, need, done
		if name then have, need, done = D.ItemProgress(name, questID) end
		if name and (isQuest or have) then
			local m = bagMarkOf(b)
			if m then
				local starts = questID and isActive == false
				local full = not starts and (done or (have and need and have >= need))
				local c = GOLD -- (also when full: grey hid among the bag's slots)
				m.bang:SetTexture(K.MEDIA .. (starts and "glyph_star" or "glyph_bang"))
				m.bang:SetVertexColor(c[1], c[2], c[3])
				m.border:SetColor(c[1], c[2], c[3], 1)
				m.full, m.starts = full, starts
				m:Show()
			end
		elseif b.srBagQuest then
			b.srBagQuest:Hide()
		end
	end
end
local bagPending = false
local function bagsSoon()
	if bagPending then return end
	bagPending = true
	C_Timer.After(0.1, function() bagPending = false; D.MarkBags() end)
end
ns.On("BAG_UPDATE_DELAYED", bagsSoon)
ns.On("QUEST_LOG_UPDATE", bagsSoon)
ns.On("SR_LOGIN", function()
	-- the bag windows draw their items when opened: marked then
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, f in ipairs(frames) do
		if type(f) == "table" and f.HookScript then
			f:HookScript("OnShow", bagsSoon)
			if type(f.UpdateItems) == "function" then hooksecurefunc(f, "UpdateItems", bagsSoon) end
		end
	end
end)

-- /sitrep lootprobe: the loot window as the game has it.
function D.LootProbe()
	ns.Capture("lootprobe", function()
		local n = read(GetNumLootItems) or 0
		ns.print("lootprobe: %d slots; classic buttons %s, modern list %s", n, tostring(_G.LootButton1 ~= nil),
			tostring(_G.LootFrame ~= nil and _G.LootFrame.ScrollBox ~= nil))
		for slot = 1, n do
			local name, isQuest, questID, isActive = slotInfo(slot)
			local have, need = D.ItemProgress(name or "")
			ns.print("  %d: %s, quest item (the game) %s, quest %s, active %s; an objective names it: %s", slot, tostring(name), tostring(isQuest),
				tostring(questID), tostring(isActive), have and format("yes (%s/%s)", tostring(have), tostring(need)) or "no")
		end
		local shown = D.LootButtons()
		ns.print("buttons found: %d%s", #shown, #shown > 0 and format(" (the first: %s, slot %s, marked %s)", tostring(shown[1][1].GetName and shown[1][1]:GetName()),
			tostring(shown[1][2]), tostring(shown[1][1].srQuest and shown[1][1].srQuest:IsShown())) or "")
	end)
end

-- /sitrep drops: what was learned for the quests in your log.
function D.Report()
	ns.Capture("drops", function()
		local any = false
		for _, q in ipairs(ns.Quests.List()) do
			for n, o in ipairs(q.objectives) do
				if isItem(o) then
					local kpi, K, H, from = D.KillsPerItem(q.id, n)
					if kpi then
						any = true
						ns.print("%s: %s: about 1 in %.1f kills (%d items from %d kills of %s)", q.title, ns.Questbook.BareText(o.text) or o.text,
							kpi, H, K, table.concat(from, ", "))
					end
				end
			end
		end
		local n = 0
		for _ in pairs(book()) do n = n + 1 end
		if not any then ns.print("drops: nothing learned for the quests in your log yet") end
		ns.print("drop rates known for %d quest objectives (all characters)", n)
	end)
end
