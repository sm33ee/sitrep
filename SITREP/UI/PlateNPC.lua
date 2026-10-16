-- SITREP · NPC plates: who they are, not how healthy (plates.npcIcons)
-- A friendly NPC's health tells you nothing: its plate loses its bar (as in zen,
-- Plates.Zen) and shows its name, under it its title ("<Rüstungsschmied>"), and
-- over it an icon for what it does: the game's own tracking icons (repair,
-- innkeeper, flight master, banker, auctioneer, stable master, class and
-- profession trainer, food and drink, reagents, poisons, battlemaster) or a
-- trader's bag. Neutral NPCs only when they have a title (a goblin trader, not
-- a boar). Your target keeps its full plate, with the icon left of its bar. The plates themselves are the
-- client's: turn friendly NPC plates on in the game's options to see them all,
-- off to have none.
-- The title is the line under the name in the client's tooltip (PlateHover.Title),
-- read once per kind of NPC and kept for the account (SITREP_DB.npcTitles[npcID]),
-- so it shows at once the next time. What a title means goes by words in it
-- (German and English): ICONS, in order (a "Schmiedekunstlehrer" is a trainer).
--
-- Self-contained, to take out in one go: this file and its line in the TOC, its
-- two calls in Plates.lua (Zen, Refresh), its switch on the Nameplates page with
-- its default (plates.npcIcons), and its block in tests/run.lua.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read

local NP = {}
ns.PlateNPC = NP
local ICON = 22   -- px
local TRIES = 2   -- tooltip reads per kind before "no title" (the client may not have it yet)

local T = "Interface\\Minimap\\Tracking\\"
local VENDOR = "Interface\\GossipFrame\\VendorGossipIcon"
local CLASS_WORDS = { "krieger", "magier", "magie", "portal", "priester", "schurke", "druide", "jäger", "hexenmeister", "paladin", "schamane",
	"warrior", "mage", "priest", "rogue", "druid", "hunter", "warlock", "shaman" }
-- { words, icon }: the first that has a word in the title wins
local ICONS = {
	{ { "greifen", "windreiter", "hippogryph", "flugmeister", "flight", "gryphon", "wind rider" }, T .. "FlightMaster" },
	{ { "gastwirt", "innkeeper" }, T .. "Innkeeper" },
	{ { "bankier", "banker", "bank" }, T .. "Banker" },
	{ { "auktion", "auction" }, T .. "Auctioneer" },
	{ { "stallmeister", "stable" }, T .. "StableMaster" },
	{ { "kampfmeister", "kriegsmeister", "battlemaster" }, T .. "BattleMaster" },
	{ { "gift", "poison" }, T .. "Poisons" },
	{ { "reagenz", "reagent" }, T .. "Reagents" },
	{ { "bäcker", "metzger", "koch", "speis", "getränk", "wein", "brau", "bier", "schank", "obst", "käse", "kellner",
		"baker", "butcher", "food", "drink", "wine", "brew", "bartender", "fruit", "cheese", "cook", "waiter", "waitress" }, T .. "Food" },
	-- supplies before the smiths: "Bergbau- und Schmiedekunstbedarf" sells, it does not repair
	{ { "bedarf", "zubehör", "supplies" }, VENDOR },
	{ { "schmied", "smith", "rüstung", "armor", "armour", "waffe", "weapon", "reparatur", "repair",
		"schild", "shield", "bogen", "bowyer", "axt", "schwert", "dolch", "keule", "streitkolben", "stabhändler", "roben" }, T .. "Repair" },
	{ { "händler", "handel", "handwerk", "waren", "lieferant", "verkäufer", "rüstmeister", "pfeil", "munition", "macher",
		"florist", "muster", "vendor", "merchant", "goods", "trader", "trade", "quartermaster", "arrow", "ammo", "maker" }, VENDOR },
}
NP.ICONS = ICONS

local function has(text, words)
	for _, w in ipairs(words) do if text:find(w, 1, true) then return true end end
	return false
end
-- The icon for a title, or nil (a title with no known word: the title alone).
-- a profession's name in a title, and the ranks its trainers are named by on
-- Forever ("Schmiedekunstgeselle", "Verzauberkunstexperte", "Schneiderfachmann"
-- teach; npcprobe 4.11.0): a profession's word with a rank is its trainer
local PROFESSIONS = { "schmiedekunst", "schneider", "verzauberkunst", "alchemie", "alchimie", "ingenieur", "lederverarbeit",
	"kürschner", "bergbau", "kräuterkunde", "kochkunst", "angel", "erste hilfe",
	"blacksmith", "tailor", "enchant", "alchem", "engineer", "leatherwork", "skinn", "mining", "herbal", "cook", "fishing", "first aid" }
local RANKS = { "geselle", "gesellin", "experte", "expertin", "fachmann", "fachfrau", "meister",
	"journeyman", "expert", "artisan", "master" }
-- a smith's supplies: they repair too (Kaita Deepforge, "Schmiedekunstbedarf")
local SMITH_SUPPLIES = { "schmiedekunstbedarf", "schmiedebedarf", "blacksmithing supplies" }

function NP.Icon(title)
	if type(title) ~= "string" then return nil end
	local t = title:lower()
	-- trainers first: a pet trainer, a class trainer, else a profession's
	if has(t, { "lehrer", "trainer", "ausbilder" }) then
		if has(t, { "tier", "pet" }) then return T .. "StableMaster" end
		if has(t, CLASS_WORDS) then return T .. "Class" end
		return T .. "Profession"
	end
	-- (words inside others: a barber is no beer)
	if has(t, { "barbier", "barber" }) then return nil end
	-- a weapon master teaches weapons; a master of a class teaches it ("Meistermagier")
	if has(t, { "waffenmeister", "weapon master" }) then return T .. "Class" end
	if has(t, CLASS_WORDS) and has(t, { "meister", "master" }) and not has(t, { "hexenmeister" }) then return T .. "Class" end
	if has(t, SMITH_SUPPLIES) then return T .. "Repair" end
	if has(t, PROFESSIONS) and has(t, RANKS) then return T .. "Profession" end
	for _, rule in ipairs(ICONS) do
		if has(t, rule[1]) then return rule[2] end
	end
	return nil
end

local function P() return ns.P and ns.P.plates end

-- Its title: kept per kind of NPC (this session, and for the account when it has one).
NP.cache, NP.tries = {}, {}
function NP.Title(s)
	local _, npc = ns.Sensors.GuidParts(s.guid)
	if npc then
		local c = NP.cache[npc]
		if c ~= nil then return c or nil end
		local kept = SITREP_DB and SITREP_DB.npcTitles and SITREP_DB.npcTitles[npc]
		if kept then NP.cache[npc] = kept return kept end
	end
	local title = ns.PlateHover and ns.PlateHover.Title(s.unit)
	if npc then
		if title then
			NP.cache[npc] = title
			if SITREP_DB then
				SITREP_DB.npcTitles = SITREP_DB.npcTitles or {}
				SITREP_DB.npcTitles[npc] = title
			end
		else
			NP.tries[npc] = (NP.tries[npc] or 0) + 1
			if NP.tries[npc] >= TRIES then NP.cache[npc] = false end
		end
	end
	return title
end

-- This plate an NPC's (no bar)? A friendly NPC, or a neutral one with a title; not
-- your target (anyTarget: your target too, for its icon beside the bar).
function NP.On(s, anyTarget)
	local p = P()
	if not p or p.npcIcons == false or s.isPlayer ~= false or (s.isTarget and not anyTarget) then return false end
	if (s.reaction or 0) < 4 or read(UnitPlayerControlled, s.unit) == true then return false end
	if s.friend then return true end
	return NP.Title(s) ~= nil
end

-- The icon: over the name, or left of the bar (outside your target's brackets).
local SIDE_GAP = 10
local function place(s, side)
	if s.npcIconAt == side then return end
	s.npcIconAt = side
	s.npcIcon:ClearAllPoints()
	if side == "side" then s.npcIcon:SetPoint("RIGHT", s, "LEFT", -SIDE_GAP, 0)
	else s.npcIcon:SetPoint("BOTTOM", s.name, "TOP", 0, 2) end
end

-- The icon over the name and the title under it (s.svc: Plates.Refresh decided);
-- your target: its full plate, the icon left of the bar.
function NP.Paint(s)
	if not s.npcIcon then
		local host = s.text or s
		s.npcIcon = host:CreateTexture(nil, "ARTWORK")
		s.npcIcon:SetSize(ICON, ICON)
		s.npcTitle = K.Font(host, 9, { 0.62, 0.72, 0.82, 1 }, K.FONT, "OUTLINE") -- (the name's blue, dimmed)
		s.npcTitle:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
	end
	if not s.svc then
		s.npcTitle:Hide()
		local icon = s.isTarget and NP.On(s, true) and NP.Icon(NP.Title(s))
		if icon then
			place(s, "side")
			s.npcIcon:SetTexture(icon)
		end
		s.npcIcon:SetShown(icon and true or false)
		return
	end
	place(s, "top")
	local title = NP.Title(s)
	local icon = NP.Icon(title)
	s.npcTitle:SetText(title and ("<" .. title .. ">") or "")
	s.npcTitle:SetShown(title ~= nil)
	if icon then s.npcIcon:SetTexture(icon) end
	s.npcIcon:SetShown(icon ~= nil)
end

-- The plate goes to another unit: nothing of this left on it.
function NP.Release(s)
	if s.npcIcon then s.npcIcon:Hide(); s.npcTitle:Hide() end
	s.svc = false
end
