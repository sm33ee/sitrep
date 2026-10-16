-- SITREP · Trackers
-- Your own spell icons, each placed anywhere on screen, each showing one thing:
--   cd      while the spell is on cooldown
--   target  while the aura is on your target (with the time it has left)
--   self    while the buff is on you (with the time it has left)
--   weapon  while a temporary weapon enchant is on (Flametongue, poisons, oils),
--           read from the client's weapon-enchant data, not from auras
-- Aura icons can watch a different aura than the spell's own name: some spells
-- put a buff with another name on you ("Waffe der Flammenzunge" -> "Waffenzunge").
-- Each can be inverted: while the spell is NOT on cooldown, while the aura is
-- NOT on your target, while the buff is NOT on you. Inverted aura icons can
-- also show shortly before the aura runs out ("warn").
-- Every icon has its own position, size, opacity, an optional importance border
-- (red / orange / green), and when it may show (always / in combat / out of combat).
--
-- What the client allows (measured on Forever):
--   Cooldowns: plain out of combat. In combat the numbers may be secret: the
--     swipe then comes from the client's duration object, and "is it on
--     cooldown?" from your own cast plus the cooldown length SITREP measured
--     earlier (or the spell's base cooldown).
--   Auras: unreadable in combat, even your own. Out of combat SITREP reads them
--     exactly. In combat it estimates from your own casts and the aura's
--     duration measured earlier, and marks the icon "?": it cannot see a dispel,
--     a resist or an early removal.
-- Settings: the beta forgets addon settings on restart, so the tracker list can
-- be mirrored into a few general macros (opt-in, TrackerMirror.lua).
--
-- Files:
--   Trackers.lua         this: the item model, spells, adding/removing, whose icon it is
--   TrackerLibrary.lua   the spell search behind the console's input fields
--   TrackerState.lua     your casts, cooldowns, weapon imbues
--   TrackerAuras.lua     auras, also in combat (the oracle, the buff bar, charge counting)
--   TrackerMirror.lua    the copy of the list in macros, encode/decode
--   TrackerIcons.lua     the icons: drawing, timers, wiring
-- Shared between them through T: T.SpellName/SpellIcon/Learned, T.GCD, T.state
-- (casts, cooldown ends, known auras), T.CooldownState/AuraState/WeaponState.

local ADDON, ns = ...
local K = ns.Kit
local read, plain = ns.read, ns.plain
local floor = math.floor
local issecrettable = _G.issecrettable or function() return false end
local function secretAny(v) return (issecretvalue and issecretvalue(v)) or issecrettable(v) end

local T = {}
ns.Trackers = T
T.icons = {}          -- [item.id] = icon frame
T.editing = false     -- layout mode: every icon visible, labelled, draggable
T.selected = nil      -- item id selected in the console

local KIND_LABEL = { cd = "ON COOLDOWN", target = "ON TARGET", self = "ON ME", weapon = "ON WEAPON" }
local KIND_LABEL_INV = { cd = "NOT ON COOLDOWN", target = "NOT ON TARGET", self = "NOT ON ME", weapon = "NOT ON WEAPON" }
T.KIND_LABEL = KIND_LABEL
function T.LabelFor(item) return (item.invert and KIND_LABEL_INV or KIND_LABEL)[item.kind] end
local BORDER = { red = { 1, 0.25, 0.20 }, orange = { 1, 0.62, 0.15 }, green = { 0.35, 0.92, 0.42 } }
T.BORDER = BORDER
local GCD = 1.6       -- anything shorter is the global cooldown, not the spell's own
T.GCD = GCD
T.SecretAny = secretAny

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
local nameCache = {}

local function spellName(id)
	if not id then return nil end
	if nameCache[id] == nil then
		local n = C_Spell and C_Spell.GetSpellName and read(C_Spell.GetSpellName, id)
		if not n and C_Spell and C_Spell.GetSpellInfo then
			local info = read(C_Spell.GetSpellInfo, id)
			n = type(info) == "table" and plain(info.name) or nil
		end
		nameCache[id] = n or false
	end
	return nameCache[id] or nil
end
T.SpellName = spellName

local function spellIcon(id)
	local tex = C_Spell and C_Spell.GetSpellTexture and read(C_Spell.GetSpellTexture, id)
	if tex then return tex end
	local info = C_Spell and C_Spell.GetSpellInfo and read(C_Spell.GetSpellInfo, id)
	return type(info) == "table" and plain(info.iconID) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
T.SpellIcon = spellIcon

-- A spell from what you typed: an ID, or a name as your client writes it
-- (German names on a German client). Returns spellID, name.
function T.Resolve(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	local query = tonumber(text) or tonumber(text:match("%((%d+)%)%s*$") or "") or text
	local info = C_Spell and C_Spell.GetSpellInfo and read(C_Spell.GetSpellInfo, query)
	if type(info) == "table" and plain(info.spellID) then return info.spellID, plain(info.name) or text end
	return nil
end

-- Lengths measured out of combat, so estimates in combat have numbers to use.
local function learned(id)
	local L = ns.P.trackers.learned
	L[id] = L[id] or {}
	return L[id]
end
T.Learned = learned


---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local DEFAULTS = {
	cd = { show = "cd", when = "always", warn = 0, invert = false },
	target = { targetType = "enemy", anySource = false, when = "always", warn = 3, invert = false },
	self = { anySource = true, when = "always", warn = 0, invert = false },
	weapon = { hand = "main", when = "always", warn = 0, invert = false },
}

function T.Items() return ns.P.trackers.items end

---------------------------------------------------------------------------
-- Whose icon is it? The tracker list is shared by every character, so each
-- icon remembers the class and character that made it, and shows for
--   class  every character of that class (the default)
--   char   only that character
--   all    every character
-- Icons from before 3.20 carry no class yet: the first character that knows
-- the spell claims them for its class; until then they stay hidden.
---------------------------------------------------------------------------
T.SCOPE_LABEL = { class = "THIS CLASS", char = "THIS CHARACTER", all = "ALL CHARACTERS" }
function T.Me()
	local _, class = ns.read(UnitClass, "player")
	local name, realm = ns.read(UnitName, "player"), ns.read(GetRealmName)
	return class, name and (name .. "-" .. (realm or "")) or nil
end

local function knows(spell)
	if type(IsPlayerSpell) == "function" then
		local ok, v = pcall(IsPlayerSpell, spell)
		if ok and not ns.isSecret(v) then
			if v then return true end
			if type(IsSpellKnown) == "function" then
				local ok2, v2 = pcall(IsSpellKnown, spell)
				return ok2 and v2 == true
			end
			return false
		end
	end
	return true -- the client cannot tell: do not hide it
end

function T.ForMe(item)
	local scope = item.scope or "class"
	if scope == "all" then return true end
	local class, char = T.Me()
	if not class then return true end -- not logged in far enough to know
	if scope == "char" then return item.char == nil or item.char == char end
	if item.class then return item.class == class end
	-- unclaimed (older lists): the first class that knows the spell takes it
	if knows(item.spell) then
		item.class, item.char = class, item.char or char
		return true
	end
	return false
end

-- The icons this character sees (and edits).
function T.Mine()
	local out = {}
	for _, it in ipairs(T.Items()) do if T.ForMe(it) then out[#out + 1] = it end end
	return out
end

function T.Get(id)
	for _, it in ipairs(T.Items()) do if it.id == id then return it end end
end

function T.Selected() return T.selected and T.Get(T.selected) or nil end

-- Add an icon for a spell. Returns the item, or nil and why.
function T.Add(text, kind)
	if not KIND_LABEL[kind] then return nil, "unknown kind" end
	local id, name = T.Resolve(text)
	if not id then return nil, "no spell called \"" .. tostring(text) .. "\" in your spellbook" end
	local P = ns.P.trackers
	local n = #P.items
	local item = {
		id = P.nextId, kind = kind, spell = id, name = name,
		x = (n % 6) * 44 - 110, y = 160 - floor(n / 6) * 44, size = 36, alpha = 1, border = "none",
		scope = "class",
	}
	item.class, item.char = T.Me()
	for k, v in pairs(DEFAULTS[kind]) do item[k] = v end
	P.nextId = P.nextId + 1
	P.items[#P.items + 1] = item
	T.selected = item.id
	T.Changed()
	return item
end

function T.Remove(id)
	local items = T.Items()
	for i, it in ipairs(items) do
		if it.id == id then
			table.remove(items, i)
			if T.icons[id] then T.icons[id]:Hide(); T.icons[id] = nil end
			if T.selected == id then T.selected = items[i] and items[i].id or (items[i - 1] and items[i - 1].id) end
			T.Changed()
			return true
		end
	end
end

function T.Duplicate(id)
	local src = T.Get(id)
	if not src then return nil end
	local P = ns.P.trackers
	local item = ns.copy(src)
	item.id, item.x, item.y = P.nextId, src.x + src.size + 6, src.y
	P.nextId = P.nextId + 1
	P.items[#P.items + 1] = item
	T.selected = item.id
	T.Changed()
	return item
end


-- Lists from 3.7.0/3.7.1: aura icons showed while MISSING unless inverted.
-- Keep what they did by flipping their invert once (schema 2).
function T.Migrate()
	local P = ns.P.trackers
	if P.schema == 2 then return end
	for _, it in ipairs(P.items) do
		if it.kind ~= "cd" then it.invert = not it.invert end
	end
	P.schema = 2
end

function T.LayoutAll()
	T.Migrate()
	for _, item in ipairs(T.Items()) do T.Layout(item) end
	-- icons of removed items (e.g. after an import)
	for id, f in pairs(T.icons) do if not T.Get(id) then f:Hide(); T.icons[id] = nil end end
	T.Refresh()
end

function T.SetEditing(on)
	T.editing = on and true or false
	T.LayoutAll()
end

-- Something about the tracker list changed: redraw and keep a copy.
function T.Changed()
	T.LayoutAll()
	T.PersistSoon()
end

