-- Headless scenario tests for SITREP.  Run from the repo root:
--   luajit tests/run.lua        (Lua 5.1 semantics, like the client)
--   lua tests/run.lua           (Lua 5.4, catches 5.1-only assumptions)

package.path = "tests/?.lua;" .. package.path
local before = {}
for k in pairs(_G) do before[k] = true end
local W = require("wow_mock")
for k in pairs(_G) do before[k] = true end -- mock globals are not the addon's

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed = passed + 1
	else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end

---------------------------------------------------------------------------
-- Load the addon in TOC order
---------------------------------------------------------------------------
local ns = {}
local toc = {}
for line in io.lines("SITREP/SITREP.toc") do
	if line ~= "" and not line:match("^##") then toc[#toc + 1] = line:gsub("\\", "/") end
end
for _, file in ipairs(toc) do
	local chunk = assert(loadfile("SITREP/" .. file))
	chunk("SITREP", ns)
end
check("all TOC files loaded", #toc == 62, #toc)
;(function()
	-- a first start: the preset layout over the doctrine defaults (which stay bare)
	local np, d = ns.NewProfile(), ns.Defaults()
	local PR = ns.PRESET
	check("new profile: the preset layout", np.plates.friendZen == PR.plates.friendZen and np.plates.scale == PR.plates.scale
		and np.plates.hoverWhere == PR.plates.hoverWhere and np.hud.pos.chat[1] == PR.hud.pos.chat[1]
		and np.bars.main.scale == PR.bars.main.scale and np.bars.main.cols == 12 and np.hud.frameScale.player == PR.hud.frameScale.player
		and np.hud.frameScale.target == PR.hud.frameScale.target and np.hud.frameScale.allies == 1 and np.ui.chatGlass == PR.ui.chatGlass)
	check("the preset: a layout, nothing of the player's own (trackers, learned values, editor states)", PR.trackers == nil and PR.engage == nil
		and PR.comms == nil and not (PR.ui and (PR.ui.barEdit or PR.ui.layoutEdit)) and not (PR.quests and (PR.quests.mapTrails or PR.quests.mapBrush)))
	check("...the defaults themselves unchanged", d.plates.friendZen == false and d.hud.pos.chat == nil and d.bars.main.scale == 1)
	check("...the preset's tables copied, not shared", ns.NewProfile().hud.pos.chat ~= np.hud.pos.chat)
	-- every preset key is one the defaults know (else pruning drops it at the next login)
	local bad = {}
	local function known(p, def, path)
		for k, v in pairs(p) do
			local here = path .. "." .. k
			if def[k] == nil and path ~= "P.hud.pos" then bad[#bad + 1] = here
			elseif type(v) == "table" and type(def[k]) == "table" and #v == 0 then known(v, def[k], here) end
		end
	end
	known(ns.PRESET, d, "P")
	check("...every preset key known to the defaults", #bad == 0, table.concat(bad, ", "))
end)()

local S = W.scenario
-- wiping contacts by hand (as the tests do) must also drop their tracks
local function wipeContacts(C_) for k in pairs(C_) do C_[k] = nil end end
S.me = { x = 0, y = 0, facing = 0, inst = 1 }
S.units.player = { name = "Tobi", guid = "Player-1-0001", class = "MAGE", level = 60, hostile = false, faction = "Alliance", hp = 4000, hpMax = 4000, dist = 0 }

-- (a profile of its own: the preset layout is for a first start)
SITREP_DB = { profile = {} }
W.Fire("ADDON_LOADED", "SITREP")
W.Fire("PLAYER_LOGIN")
W.Fire("SPELLS_CHANGED")
check("profile created", ns.P and ns.P.sensors and ns.P.threat.matrix.MAGE.ROGUE == 1.20)
check("login printed", (W.prints[1] and W.prints[1]:find("ready")) or (W.prints[2] and W.prints[2]:find("ready")), W.prints[1])
check("a character whose flight points SITREP does not know: told how to fix it", table.concat(W.prints, "\n"):find("flight points yet", 1, true))

-- Range ladder built from the spellbook: Frost Nova (0-0) must be excluded.
local maxes = {}
for _, c in ipairs(ns.Sensors.checks) do if c.kind ~= "item" then maxes[#maxes + 1] = c.max end end
check("range ladder from spellbook + interact", table.concat(maxes, ",") == "10,20,28,30,35", table.concat(maxes, ","))

---------------------------------------------------------------------------
-- Scenario 1: a rogue closing on the right, a priest hanging back on the left
---------------------------------------------------------------------------
S.units.nameplate1 = { name = "Vex", guid = "Player-2-00A1", class = "ROGUE", level = 60, isPlayer = true, hostile = true,
	faction = "Horde", dist = 15, screenX = 1920 * 0.75, combat = false, hp = 3000, hpMax = 3000 }
S.units.nameplate2 = { name = "Aldwin", guid = "Player-2-00B2", class = "PRIEST", level = 60, isPlayer = true, hostile = true,
	faction = "Horde", dist = 33, screenX = 1920 * 0.30, casting = true, hp = 3500, hpMax = 3500 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")

local newContacts, hvts, advice = 0, {}, {}
ns.On("SR_NEW_CONTACT", function() newContacts = newContacts + 1 end)
ns.On("SR_HVT", function(_, c) hvts[#hvts + 1] = c.name end)
ns.On("SR_ADVICE", function(_, a) advice[#advice + 1] = a end)

W.Update(0.25)
local C = ns.Sensors.contacts
local rogue, priest = C["Player-2-00A1"], C["Player-2-00B2"]
check("two contacts", rogue and priest)
check("two new-contact events", newContacts == 2, newContacts)
check("rogue range bracket 10-20", rogue.lo == 10 and rogue.hi == 20, (rogue.lo or "nil") .. "-" .. (rogue.hi or "nil"))
check("priest range bracket 30-35", priest.lo == 30 and priest.hi == 35, (priest.lo or "nil") .. "-" .. (priest.hi or "nil"))
check("priest flagged casting", priest.casting == true)

local M = ns.Model
check("rogue is top threat (closer, matchup 1.20)", M.byThreat[1] == rogue)
check("priest is top priority", M.byPriority[1] == priest)
check("priest designated HVT", priest.hvt and hvts[1] == "Aldwin", priest.priority)
local pic = M.picture
check("1 v 2: advice BREAK", pic.advice == "BREAK", pic.advice)
check("ratio < 0.5", pic.rho and pic.rho < 0.5, pic.rho)
check("P(win) < 20%", pic.pwin and pic.pwin < 0.2, pic.pwin)

-- Lanchester sanity: 3 v 2 of identical units is 2.25:1
do
	local P = ns.copy(ns.P)
	P.threat.power = setmetatable({}, { __index = function() return 1 end })
	P.threat.matrix = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 1 end }) end })
	local me = { class = "X", level = 60 }
	local f = { { class = "X", level = 60, hp = 1 }, { class = "X", level = 60, hp = 1 }, { class = "X", level = 60, hp = 1 } }
	local h = { { class = "X", level = 60, age = 0, range = 10 }, { class = "X", level = 60, age = 0, range = 10 } }
	local e = M.Engagement(f, h, me, P)
	check("Lanchester 3v2 = 2.25", near(e.rho, 2.25, 1e-9), e.rho)
	check("3v2 survivors = 3*sqrt(1-1/2.25)", near(e.losses, 3 * (1 - math.sqrt(1 - 1 / 2.25)), 1e-9), e.losses)
	check("3v2 advice ENGAGE", e.advice == "ENGAGE")
	local even = M.Engagement({ f[1] }, { h[1] }, me, P)
	check("1v1 even = 50%", near(even.pwin, 0.5, 1e-9), even.pwin)
end

---------------------------------------------------------------------------
-- Scenario 2: targeted, then the rogue drops off the plates and we move
---------------------------------------------------------------------------
local targeted = 0
ns.On("SR_TARGETED", function() targeted = targeted + 1 end)
S.units.nameplate1.targetingMe = true
W.Update(0.25)
check("targeted event fires once", targeted == 1, targeted)
check("targeting multiplies threat", rogue.threat > 100, rogue.threat)
W.Update(0.25)
check("targeted event not repeated", targeted == 1, targeted)

S.units.nameplate1 = nil -- the plate token stops existing when the plate goes
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
S.me.x = 10 -- walked 10 yards north
W.Update(1.2)
W.Update(0.25)
check("rogue now a last known position", rogue.live == false and rogue.unit == nil)
check("lost contact keeps its last distance", rogue.range == 15, rogue.range)
check("LKP loses the targeting flag", rogue.targetingMe == false)

-- Memory expiry
ns.P.sensors.memory = 10
for _ = 1, 50 do W.Update(0.25) end
check("rogue forgotten after memory span", C["Player-2-00A1"] == nil)
check("priest still live", C["Player-2-00B2"] ~= nil)
ns.P.sensors.memory = 45

---------------------------------------------------------------------------
-- Scenario 3: the client goes secret (combat)
---------------------------------------------------------------------------
S.me.combat = true
S.units.player.combat = true
S.secret = { health = true, name = true, hostile = true, cast = true }
S.units.nameplate3 = { name = "Grunk", guid = "Player-2-00C3", class = "WARRIOR", level = 58, isPlayer = true, hostile = true,
	faction = "Horde", dist = 8, screenX = 960, casting = true, hp = 5000, hpMax = 5000 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
W.Fire("PLAYER_REGEN_DISABLED")
local okTick, err = pcall(W.Update, 0.25)
check("tick survives secret health/name/hostility", okTick, err)
local war = C["Player-2-00C3"]
check("secret UnitCanAttack falls back to UnitIsEnemy", war ~= nil)
check("secret name becomes Unknown, keyed by GUID", war and war.name == "Unknown")
check("secret cast still counts as casting", war and war.casting == true)
check("feed: health SECRET when targeted", true)
S.units.target = S.units.nameplate3
W.Update(0.25)
check("health feed reports SECRET", ns.feeds.health and ns.feeds.health.state == "SECRET", ns.feeds.health and ns.feeds.health.state)
check("aura feed LOCKED in combat", ns.feeds.auras.state == "LOCKED")
check("combat log feed DARK", ns.feeds.combatlog.state == "DARK")
S.units.target = nil

-- Pressure: shadow health while real health is secret
local R = ns.Pressure
check("shadow seeded from last plain reading", R.shadow == 4000, R.shadow)
local spikes = 0
ns.On("SR_SPIKE", function() spikes = spikes + 1 end)
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 900, 1)
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 900, 1)
W.Fire("UNIT_COMBAT", "player", "HEAL", "", 300, 1)
W.Fire("UNIT_COMBAT", "player", "WOUND", "", W.Secret(), 1) -- secret amount must be ignored
W.Update(0.25)
check("shadow = 4000 - 1800 + 300", R.shadow == 2500, R.shadow)
check("not synced while secret", R.synced == false)
check("spike fired (1800 of 4000 in 1.5s = 45%)", spikes == 1, spikes)
check("dps short window", near(R.dpsShort, 1800 / 3, 1e-6), R.dpsShort)
check("ttl = shadow / (dps - hps)", near(R.ttl, 2500 / (600 - 100), 1e-6), R.ttl)
check("advice DEFEND when ttl < 4s? (5s -> no)", M.picture.advice ~= "DEFEND")
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 1500, 1)
W.Update(0.25)
check("advice DEFEND once ttl drops", M.picture.advice == "DEFEND", M.picture.advice .. " ttl=" .. tostring(R.ttl))

---------------------------------------------------------------------------
-- Scenario 4: after-action review and calibration
---------------------------------------------------------------------------
local aars = {}
ns.On("SR_AAR", function(_, r) aars[#aars + 1] = r end)
local k0 = ns.P.engage.k
W.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Grunk dies, honorable kill")
S.me.combat, S.units.player.combat, S.secret = false, false, nil
W.Fire("PLAYER_REGEN_ENABLED")
W.Update(1)
check("AAR waits for late honor messages", #aars == 0)
W.Update(1.5)
check("AAR produced", #aars == 1)
local r = aars[1]
check("outcome WIN via honorable kill", r and r.outcome == "WIN", r and r.outcome)
check("damage taken recorded", r and r.dmg == 3300, r and r.dmg)
check("calibration counted", ns.P.engage.n == 1)
check("underdog win raises bias or k moves", ns.P.engage.k ~= k0 or ns.P.engage.bias ~= 0)
check("engagement logged", ns.db.log.engagements[1] == r)
check("heat map has Tarren Mill", (ns.db.log.heat["Hillsbrad Foothills / Tarren Mill"] or 0) >= 3)
check("shadow resyncs to plain health", R.synced == true and R.shadow == 4000)

-- A PvE fight (no hostile players) is not logged.
S.units.nameplate2, S.units.nameplate3 = nil, nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2"); W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
wipeContacts(C)
W.Fire("PLAYER_REGEN_DISABLED"); W.Update(0.5); W.Fire("PLAYER_REGEN_ENABLED"); W.Update(3)
check("PvE fight not logged", #aars == 1, #aars)

-- Calibration maths: repeated wins at even odds pull P(win) at x=0 upward.
do
	local E = ns.P.engage
	E.k, E.bias, E.n, E.brier = 2.2, 0, 0, 0
	for _ = 1, 40 do M.Calibrate(0, 1) end
	check("bias learns a winning streak", E.bias > 0.5, E.bias)
	check("brier tracks error", E.brier > 0 and E.brier < 0.25, E.brier)
	E.k, E.bias, E.n, E.brier = 2.2, 0, 0, 0
end

---------------------------------------------------------------------------
-- Scenario 5: comms
---------------------------------------------------------------------------
S.units.nameplate4 = { name = "Kael", guid = "Player-2-00D4", class = "MAGE", level = 60, isPlayer = true, hostile = true,
	faction = "Horde", dist = 25, screenX = 1500 }
S.units.nameplate5 = { name = "Brom", guid = "Player-2-00E5", class = "MAGE", level = 60, isPlayer = true, hostile = true,
	faction = "Horde", dist = 27, screenX = 1600 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
W.Update(0.25)
local line = ns.Comms.Compose()
check("report composes", line and line:find("2 hostile: 2 Mage", 1, true), line)
check("report has range and zone", line and line:find("20-28y", 1, true) and line:find("Tarren Mill", 1, true), line)
local nPrints = #W.prints
ns.Comms.Report()
check("solo report stays local", #W.chat == 0 and #W.prints == nPrints + 1)
S.group.n = 2
S.units.party1 = { name = "Ally", class = "WARRIOR", level = 60, hp = 5000, hpMax = 5000, dist = 5 }
S.units.party2 = { name = "Ally2", class = "PRIEST", level = 60, hp = 3000, hpMax = 3000, dist = 12 }
ns.Comms.Report()
check("group report goes to PARTY", W.chat[1] and W.chat[1].channel == "PARTY", W.chat[1] and W.chat[1].channel)
S.chatLockdown = true
ns.Comms.Report()
check("chat lockdown keeps report local", #W.chat == 1)
S.chatLockdown = false

W.Update(0.25)
check("friendlies counted (3)", M.picture.nF == 3, M.picture.nF)
check("addon messages shared", #W.addonMsgs >= 1, #W.addonMsgs)
local sent = W.addonMsgs[1]
check("prefix SITREP on PARTY", sent and sent.prefix == "SITREP" and sent.channel == "PARTY")
local dec = ns.Comms.Decode(sent.msg)
check("encode/decode round trip", dec and dec.class == "MAGE" and dec.key:find("Player%-2"))
check("shared contacts carry no position", sent and not sent.msg:find("^C1") and select(2, sent.msg:gsub("\t", "")) == 6, sent and sent.msg)

-- A groupmate reports a warlock we cannot see.
local old = table.concat({ "C1", "Player-2-00F7", "Oldver", "WARLOCK", "60", "1.0", "20.0", "1", "0.5", "1" }, "\t")
check("old position messages are ignored", ns.Comms.Decode(old) == nil)
local msg = table.concat({ "C2", "Player-2-00F6", "Mortis", "WARLOCK", "60", "0.5", "1" }, "\t")
W.Fire("CHAT_MSG_ADDON", "SITREP", msg, "PARTY", "Ally-Realm")
W.Update(0.25)
local lock = C["Player-2-00F6"]
check("net contact ingested", lock and lock.net == "Ally-Realm")
check("net contact: who, no distance", lock and lock.class == "WARLOCK" and lock.range == nil and lock.inCombat == true)
check("net contact is not live", lock and lock.live == false)
local mine = #W.addonMsgs
W.Fire("CHAT_MSG_ADDON", "SITREP", msg, "PARTY", "Tobi")
check("own echo ignored", true)
W.Fire("CHAT_MSG_ADDON", "OTHER", "garbage", "PARTY", "X")
check("foreign prefix ignored", ns.Comms.stats.received == 1, ns.Comms.stats.received)

---------------------------------------------------------------------------
-- Scenario 5b: duels
---------------------------------------------------------------------------
-- Clear the battlefield: no group, no hostiles.
S.group.n = 0
for _, u in ipairs({ "nameplate4", "nameplate5" }) do S.units[u] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", u) end
wipeContacts(C)
W.Update(0.25)

-- A same-faction player walks up: friendly plate, counted on our side.
S.units.nameplate6 = { name = "Garrick", guid = "Player-1-0066", class = "PALADIN", level = 60, isPlayer = true, hostile = false,
	faction = "Alliance", dist = 8, screenX = 960, hp = 4500, hpMax = 4500 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
W.Update(0.25)
check("friendly plate is not a contact", C["Player-1-0066"] == nil)
check("friendly plate counts as friendly force", M.picture.nF == 2, M.picture.nF)
check("no duel before it starts", ns.AAR.InDuel() == false)

-- The duel starts: the same plate turns attackable without being re-added.
S.units.nameplate6.hostile = true
W.Update(0.25)
local garrick = C["Player-1-0066"]
check("plate reclassified as hostile mid-fight", garrick ~= nil and garrick.live)
check("duel opponent no longer counted as friendly", M.picture.nF == 1, M.picture.nF)
check("duel detected from same-faction contact", ns.AAR.InDuel() and M.picture.duel == true)
local groupK, groupN = ns.P.engage.k, ns.P.engage.n
ns.P.duel.bias = 1.5
W.Update(0.25)
local pic = M.picture
check("duel P(win) uses the duel curve", near(pic.pwin, 1 / (1 + math.exp(-(ns.P.duel.k * pic.x + 1.5))), 1e-9), pic.pwin)
ns.P.duel.bias = 0

-- Fight, win by knockout.
local nAar = #aars
S.me.combat, S.units.player.combat = true, true
W.Fire("PLAYER_REGEN_DISABLED")
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 700, 1)
for _ = 1, 8 do W.Update(0.25) end
W.Fire("CHAT_MSG_SYSTEM", "Tobi has defeated Garrick in a duel")
S.units.nameplate6.hostile = false
S.me.combat, S.units.player.combat = false, false
W.Fire("PLAYER_REGEN_ENABLED")
W.Update(2.5)
local d = aars[#aars]
check("duel AAR produced", #aars == nAar + 1, #aars - nAar)
check("tagged as a duel win vs Garrick", d.kind == "duel" and d.outcome == "WIN" and d.opponent == "Garrick", tostring(d.kind) .. " " .. tostring(d.outcome))
check("opponent class recorded", d.oppClass == "PALADIN", d.oppClass)
check("duel curve trained", ns.P.duel.n == 1 and d.p ~= nil)
check("group curve untouched by the duel", ns.P.engage.n == groupN and ns.P.engage.k == groupK)
check("per-class record: 1-0 vs Paladin", ns.db.log.duels.PALADIN and ns.db.log.duels.PALADIN.w == 1 and ns.db.log.duels.PALADIN.l == 0)
check("no honorable kill needed", d.hk == 0)

-- Results that arrive outside combat are logged on their own.
W.Fire("CHAT_MSG_SYSTEM", "Garrick has fled from Tobi in a duel")
check("flee counts as a win", aars[#aars].outcome == "WIN" and ns.db.log.duels.PALADIN.w == 2)
check("standalone duel carries no stale damage", aars[#aars].dmg == 0)
W.Fire("CHAT_MSG_SYSTEM", "Garrick-Stormrage has defeated Tobi in a duel")
check("loss recorded (realm suffix stripped)", aars[#aars].outcome == "LOSS" and ns.db.log.duels.PALADIN.l == 1)
local before3 = #aars
W.Fire("CHAT_MSG_SYSTEM", "Foo has defeated Bar in a duel")
W.Fire("CHAT_MSG_SYSTEM", "You have been awarded 12 honor.")
check("other people's duels and other messages ignored", #aars == before3)
check("session duel tally", ns.AAR.session.duelWins == 2 and ns.AAR.session.duelLosses == 1)

-- A duel that ends without a result message (out of bounds) is a duel BREAK.
S.units.nameplate6.hostile = true
W.Update(0.25)
S.me.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
for _ = 1, 4 do W.Update(0.25) end
S.units.nameplate6.hostile, S.me.combat = false, false
W.Fire("PLAYER_REGEN_ENABLED")
W.Update(2.5)
check("waits for a late duel result", aars[#aars] ~= nil and #aars == before3)
W.Update(3.5)
check("no result: duel BREAK, nothing trained", aars[#aars].kind == "duel" and aars[#aars].outcome == "BREAK" and ns.P.duel.n == 1)

-- Localized pattern building copes with magic characters.
local pat, order = ns.AAR._toPattern("%2$s (Duell) wurde von %1$s besiegt.")
local a, b = ("Garrick (Duell) wurde von Tobi besiegt."):match(pat)
check("pattern handles reordered args and punctuation", a == "Garrick" and b == "Tobi" and order[1] == 2 and order[2] == 1)

-- Dueling a groupmate: they leave the friendly force.
S.units.nameplate6 = nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate6")
wipeContacts(C)
S.group.n = 1
S.units.party1 = { name = "Ally", class = "WARRIOR", level = 60, hp = 5000, hpMax = 5000, dist = 5, hostile = true, faction = "Alliance" }
W.Update(0.25)
check("groupmate you are dueling is not friendly", M.picture.nF == 1, M.picture.nF)
S.units.party1.hostile = false
W.Update(0.25)
check("groupmate back on your side after the duel", M.picture.nF == 2, M.picture.nF)
S.group.n = 0

---------------------------------------------------------------------------
-- Scenario 6: instances hide position and facing
---------------------------------------------------------------------------
S.me.noPosition, S.me.facing = true, nil
local ok6, err6 = pcall(W.Update, 0.25)
check("tick without position/facing", ok6, err6)
check("position feed DARK", ns.feeds.position.state == "DARK")
S.me.noPosition, S.me.facing = nil, 0

---------------------------------------------------------------------------
-- UI: console pages, HUD, slash commands, profile round trip
---------------------------------------------------------------------------
ns.Config.Toggle()
for _, id in ipairs({ "overview", "sensors", "threat", "matrix", "engage", "pressure", "comms", "alerts", "display", "layout", "frames", "log" }) do
	local okp, errp = pcall(ns.Config._open, id)
	check("console page " .. id, okp, errp)
end
for _ = 1, 4 do W.Update(0.25) end -- live pages refresh
ns.P.hud.accent = "amber"; ns.Changed("hud.accent")
ns.P.hud.envelopeLanes = 8; ns.Changed("hud.envelopeLanes")
ns.P.hud.boardRows = 8; ns.Changed("hud.boardRows")
ns.P.hud.envelopeRange = 35
local okU, errU = pcall(W.Update, 0.25)
check("HUD survives theme, lane and range changes", okU, errU)
check("envelope rebuilt with 8 lanes", #ns.HUD.modules.envelope.lanes == 8)
ns.P.hud.envelopeRange, ns.P.hud.envelopeLanes = 40, 6; ns.Changed("hud.envelopeLanes")
ns.Fire("SR_NEW_CONTACT", { class = "MAGE", level = 60, rel = 0.5, lo = 20, hi = 28 })
ns.Fire("SR_SPIKE", 42)
W.Update(3)
check("banner and flash expire", true)

for _, cmd in ipairs({ "help", "sensors", "lock", "unlock", "hud", "hud", "report" }) do
	local okc, errc = pcall(SlashCmdList.SITREP, cmd)
	check("/sitrep " .. cmd, okc, errc)
end
-- ENVELOPE: a rogue runs in at 7 y/s from 38 yd, then backs off.
wipeContacts(C)
local env = ns.HUD.modules.envelope
S.me.x, S.me.y, S.me.facing = 0, 0, 0
local rogueU = { name = "Kesh", guid = "Player-2-0200", class = "ROGUE", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 38, screenX = 960 }
S.units.nameplate20 = rogueU
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate20")
local closingAlerts = 0
ns.On("SR_CLOSING", function() closingAlerts = closingAlerts + 1 end)
W.Update(0.25)
local kesh = C["Player-2-0200"]
check("envelope: contact in lane 1 (HVT marked *)", env.lanes[1].contact == kesh and env.lanes[1].label:GetText():find("^Rog"), env.lanes[1].label:GetText())
check("envelope: no closure from a single reading", kesh.closing == nil)
local sawRate, minTtr
for _ = 1, 18 do
	rogueU.dist = math.max(4, rogueU.dist - 1.75) -- 7 y/s at 4 updates a second
	W.Update(0.25)
	if kesh.closing and not sawRate then sawRate = kesh.closing end
	if kesh.ttr then minTtr = math.min(minTtr or 99, kesh.ttr) end
end
check("closure measured from boundary crossings (~ -7 y/s)", sawRate and sawRate < -5 and sawRate > -10, sawRate)
check("time to reach estimated while closing", minTtr and minTtr <= 3, minTtr)
check("one early-warning alert", closingAlerts == 1, closingAlerts)
check("rogue inside its reach once at 4 yd", kesh.inTheirReach == true and kesh.inMyReach == true)
check("lane says IN ITS REACH", W.has(env.lanes[1].sub:GetText(), "IN ITS REACH"), env.lanes[1].sub:GetText())
check("status counts it", W.has(env.status:GetText(), "THEIRS 1"), env.status:GetText())
check("closing raises threat", kesh.threat > 0 and ns.P.threat.closing > 1)
-- backs off: rate turns positive, the warning re-arms, then the rate goes stale
for _ = 1, 8 do rogueU.dist = rogueU.dist + 1.75; W.Update(0.25) end
check("opening shows a positive rate", kesh.closing and kesh.closing > 0, kesh.closing)
check("warning re-armed after opening", kesh.warnedClosing == nil)
W.Update(3.5)
check("rate dropped when no boundary is crossed", kesh.closing == nil)
-- a warrior standing at 24 yd is inside its Charge reach (25); a mage at 33 is outside its 30
S.units.nameplate21 = { name = "Brug", guid = "Player-2-0210", class = "WARRIOR", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 24, screenX = 960 }
S.units.nameplate22 = { name = "Ilsa", guid = "Player-2-0220", class = "MAGE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 33, screenX = 960 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate21"); W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate22")
W.Update(0.25)
check("warrior at 24 yd: inside Charge reach", C["Player-2-0210"].inTheirReach == true)
check("mage at 30-35 yd: outside its 30 yd reach", C["Player-2-0220"].inTheirReach == false)
local wlane
for _, l in ipairs(env.lanes) do if l.contact == C["Player-2-0210"] then wlane = l end end
check("warrior lane shades 25 of 40 yd", wlane and near(wlane.zone:GetWidth(), env.trackW * 25 / 40, 1e-9), wlane and wlane.zone:GetWidth())
local shownLines = 0
for _, l in ipairs(env.myLines) do if l:IsShown() then shownLines = shownLines + 1 end end
check("my weapon ranges drawn (melee, 20, 30, 35)", shownLines == 4 and ns.Sensors.myReach == 35, shownLines)
for _, u in ipairs({ "nameplate20", "nameplate21", "nameplate22" }) do S.units[u] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", u) end
wipeContacts(C)
W.Update(0.25)
check("empty envelope says NO CONTACT", env.empty:IsShown())

-- Plates the add event never announced are found by the sweep.
S.units.nameplate11 = { name = "Silent", guid = "Player-2-0111", class = "SHAMAN", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 18, screenX = 1400 }
local events0 = ns.Sensors.stats.plateEvents
W.Update(1) -- the sweep runs once a second
check("sweep finds a plate without NAME_PLATE_UNIT_ADDED", C["Player-2-0111"] ~= nil and ns.Sensors.stats.plateEvents == events0)
local silent = C["Player-2-0111"]
check("contact kept with range, no direction", silent and silent.range and silent.rel == nil and silent.az == nil)
check("no direction: still in the envelope", env.lanes[1].contact == silent and env.lanes[1].info:GetText():find("10-20y", 1, true), env.lanes[1].info:GetText())

-- Forbidden enemy plates: announced by their own event, no position, still ranged.
wipeContacts(C)
S.units.nameplate11 = nil
S.units.nameplate12 = { name = "Veiled", guid = "Player-2-0122", class = "WARLOCK", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 24, screenX = 1000, forbidden = true }
W.Fire("FORBIDDEN_NAME_PLATE_UNIT_ADDED", "nameplate12")
W.Update(0.25)
local veiled = C["Player-2-0122"]
check("forbidden plate becomes a contact", veiled ~= nil and veiled.live)
check("forbidden plate: no direction", veiled.rel == nil and veiled.az == nil)
check("forbidden contact in the envelope", env.lanes[1].contact == veiled and env.lanes[1].label:GetText():find("^Wlk"))
S.units.nameplate12 = nil
W.Fire("FORBIDDEN_NAME_PLATE_UNIT_REMOVED", "nameplate12")
S.units.nameplate11 = { name = "Silent", guid = "Player-2-0111", class = "SHAMAN", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 18, screenX = 1400 }

-- Forever's real restriction: nameplates cannot be measured. Nothing is read from
-- the screen or the mouse; without estimates there is simply no direction.
wipeContacts(C)
S.units.nameplate11 = nil
S.restrictMeasure = true
S.me.x, S.me.y, S.me.facing = 0, 0, 0
S.units.nameplate13 = { name = "Brakka", guid = "Player-2-0133", class = "ROGUE", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 18, screenX = 1440 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate13")
W.Update(0.25)
local brakka = C["Player-2-0133"]
check("restricted plate: contact live without direction", brakka and brakka.live and brakka.rel == nil)
check("restricted plate: still in the envelope", env.lanes[1].contact == brakka)
S.units.mouseover, S.cursorX = S.units.nameplate13, 1440
W.Update(0.25)
check("hovering gives no direction", brakka.rel == nil and brakka.az == nil)
local ar1 = ns.HUD.modules.board.rows[1]
S.units.mouseover, S.cursorX, S.restrictMeasure = nil, nil, nil
S.units.nameplate13 = nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate13")
wipeContacts(C)
W.Update(0.25)
S.units.nameplate11 = { name = "Silent", guid = "Player-2-0111", class = "SHAMAN", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 18, screenX = 1400 }

-- UnitPosition: north axis first (Redridge reads -9448, -2252 on Forever).
S.me.x, S.me.y = -9448.2, -2251.9
W.Update(0.25)
check("own position: x = north axis, y = west axis", ns.Sensors.self.x == -9448.2 and ns.Sensors.self.y == -2251.9)
S.me.x, S.me.y = 0, 0
W.Update(0.25)

-- "a and b and pcall(f)" keeps only pcall's FIRST value: never unpack several from it.
for _, file in ipairs(toc) do
	local src = io.open("SITREP/" .. file):read("*a")
	for line in src:gmatch("[^\n]+") do
		if line:match("local%s+[%w_]+%s*,%s*[%w_]+[%w_, ]*=[^=].-%f[%w]and%s+pcall%(") then
			check(file .. ": no multi-value 'and pcall(' (only the first value survives)", false, line)
		end
		-- the same for any call: "local a, b = x and f()" (4.9.12: the tracker's tooltip broke
		-- off, spots fell to the coarse grid); "local a, b = x and f(1), y and f(2)" is two
		-- expressions and fine
		local rhs = line:match("^%s*local%s+[%w_]+%s*,%s*[%w_, ]+=%s*(.*)$")
		if rhs and rhs:match("^[%w_%.]+%s+and%s+[%w_%.:]+%b()%s*$") then
			check(file .. ": no multi-value 'x and f()' (only the first value survives)", false, line)
		end
	end
end

-- No source file reads the screen or the mouse for directions any more.
for _, file in ipairs(toc) do
	local src = io.open("SITREP/" .. file):read("*a")
	for _, banned in ipairs({ "GetCursorPosition", "GetCenter", "GetMouseFoci", "GetPlayerFacing", "ns.TMA" }) do
		-- (the config sliders may follow the cursor while you drag them)
		-- (sliders follow the cursor while dragged; tracker icons measure themselves when you drop them)
		-- (the quest arrow turns with you; the quest probe reports the facing)
		-- (/sitrep mouse names what takes the mouse)
		-- (the hover window may open next to the mouse: placing, not a direction)
		-- (the world map's brush paints where the mouse is on the map)
		local own = ((file == "UI/Kit.lua" or file == "UI/PlateHover.lua" or file == "UI/QuestMap.lua") and banned == "GetCursorPosition")
			or (file == "UI/TrackerIcons.lua" and banned == "GetCenter")
			or (file == "Debug.lua" and banned == "GetMouseFoci")
			or ((file == "UI/QuestArrow.lua" or file == "Quests.lua") and banned == "GetPlayerFacing")
		if src:find(banned, 1, true) and not own then check(file .. " does not use " .. banned, false) end
	end
end
S.units.target = nil
wipeContacts(C)
-- An enemy known only beyond 28 yd: shown as ">28y", estimated at 33.
S.units.mouseover, S.cursorX, S.mouseFocus, S.units.target = nil, nil, nil, nil
local far = { name = "Faraway", guid = "Player-2-0999", class = "MAGE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 50 }
S.units.target = far
W.Update(0.25)
local fc = C["Player-2-0999"]
check("enemy beyond every check: range floor shown", fc and ns.Comms.RangeText(fc) == ">35y" and fc.range == 40, fc and (ns.Comms.RangeText(fc) .. " " .. tostring(fc.range)))
S.units.target = nil
wipeContacts(C)
S.me.facing = 0
W.Update(3.5)

-- UNIT FRAMES ------------------------------------------------------------------
local PF, TF = _G.SITREP_playerFrame, _G.SITREP_targetFrame
check("player and target frames built", PF ~= nil and TF ~= nil)
check("Blizzard frames faded out", PlayerFrame:GetAlpha() == 0 and TargetFrame:GetAlpha() == 0 and TargetFrameToT:GetAlpha() == 0)
check("Blizzard frames click-through", PlayerFrame._mouse == false and TargetFrame._mouse == false)
;(function()
	-- their parts too, levels down (the modern frames: portrait and bars with their own tooltips)
	local deep = PlayerFrame
	for _ = 1, 5 do deep = CreateFrame("Frame", nil, deep); deep._mouse = true end
	ns.Frames.ApplyBlizzard()
	check("Blizzard frames: their parts five levels down take no mouse either (no tooltips through)", deep._mouse == false)
	ns.P.frames.hideBlizzard = false; ns.Frames.ApplyBlizzard()
	check("...given back", deep._mouse == true)
	ns.P.frames.hideBlizzard = true; ns.Frames.ApplyBlizzard()
end)()
ns.P.frames.hideBlizzard = false; ns.Changed("frames.hideBlizzard")
check("Blizzard frames restored when switched off", PlayerFrame:GetAlpha() == 1 and PlayerFrame._mouse == true)
ns.P.frames.hideBlizzard = true; ns.Changed("frames.hideBlizzard")
TargetFrame:Show()
check("Blizzard's target frame stays faded when it re-shows", TargetFrame:GetAlpha() == 0)
ns.P.hud.locked = true; ns.Changed("hud.locked")
check("locked: target frame follows the target through a unit watch", W.unitWatch[TF] == true)

-- player frame, plain health
wipeContacts(C)
S.units.player.hp, S.units.player.hpMax, S.units.player.pvp = 3000, 4000, true
S.pvpTimer = 272000
W.Update(0.25)
check("player health text", PF.hpText:GetText() == "3.0K", PF.hpText:GetText())
check("player health percent", PF.pctText:GetText() == "75%", PF.pctText:GetText())
check("PvP flag with its countdown", W.has(PF.tags:GetText(), "PVP 4:32"), PF.tags:GetText())
S.pvpTimer = nil
-- secret health in combat: raw value handed to the font string, estimate for percent
S.me.combat, S.units.player.combat = true, true
S.secret = { health = true }
W.Update(0.25)
check("secret health still shown (client renders it)", ns.isSecret(PF.hpText:GetText()))
check("percent falls back to the shadow estimate", PF.pctText:GetText():find("^~%d+%%$"), PF.pctText:GetText())
S.secret = nil
S.me.combat, S.units.player.combat = false, false
-- loss of control
S.loc = { displayText = "Stunned", timeRemaining = 2.14 }
W.Update(0.25)
check("loss of control strip", PF.loc:IsShown() and PF.loc.text:GetText() == "Stunned" and PF.loc.time:GetText() == "2.1s", PF.loc.text:GetText())
S.loc = nil
W.Update(0.25)
check("strip clears when control returns", not PF.loc:IsShown())
-- crowd control keeps your health readable: light grey on dark grey, red border
S.units.player.hp = 1200
S.loc = { displayText = "Stunned", timeRemaining = 3 }
W.Update(0.25)
local cc = PF.hp._sbColor
check("CC: health fill light grey (not red on red)", cc and cc[1] > 0.75 and math.abs(cc[1] - cc[2]) < 0.05 and math.abs(cc[2] - cc[3]) < 0.05, cc and table.concat(cc, ","))
check("CC: the empty part dark grey, strong contrast", W.vc(PF.hp.bg)[1] < 0.2 and (cc[1] - W.vc(PF.hp.bg)[1]) > 0.5)
check("CC: a red border marks it", PF.loc.border and W.vc(PF.loc.border[1])[1] == 1 and W.vc(PF.loc.border[1])[2] < 0.4)
check("CC: no solid cover over the health", PF.loc.bg == nil)
S.loc = nil
W.Update(0.25)
check("CC over: health colours return (red below 50 %)", PF.hp._sbColor[1] == 1 and PF.hp._sbColor[2] < 0.5, table.concat(PF.hp._sbColor, ","))
S.units.player.hp = 4000
W.Update(0.25)
-- exposure: a warrior at 24 yd has you inside its Charge reach
S.units.nameplate30 = { name = "Brug", guid = "Player-2-0300", class = "WARRIOR", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 24, screenX = 960, hp = 5000, hpMax = 5000, powerType = 1, casting = true, targetingMe = true }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate30")
W.Update(0.25)
check("exposure on the player frame", PF.line:GetText():find("In reach of %d"), PF.line:GetText())
-- hit flash
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 900, 1)
check("hit flash", PF.flash:GetAlpha() > 0)
W.Update(0.5)

-- target frame: the warrior, seen by a warrior (execute marker), with a record against warriors
S.units.target = S.units.nameplate30
S.units.player.class = "WARRIOR"
ns.db.log.duels.WARRIOR = { w = 4, l = 2 }
W.Fire("PLAYER_TARGET_CHANGED")
W.Update(0.25)
check("target name and class colour", TF.name:GetText() == "Brug")
check("same level shows no badge, lower shows dim", TF.level:GetText() ~= nil)
check("execute marker for a warrior", TF.exec:IsShown() and TF.execLabel:GetText() == "Execute")
check("cast bar shown from the duration object", TF.cast:IsShown())
check("range strip: bracket and spells in range", TF.strip.info:GetText():find("20-28y", 1, true) and TF.strip.info:GetText():find("2/3", 1, true), TF.strip.info:GetText())
check("matchup verdict for warrior vs warrior", W.has(TF.intel:GetText(), "MATCHUP x1.00 EVEN"), TF.intel:GetText())
check("duel record against its class", W.has(TF.record:GetText(), "DUELS 4-2"), TF.record:GetText())
check("targeting me", W.has(TF.tot:GetText(), ">> YOU"))
check("threat tag", W.has(TF.tags:GetText(), "THREAT"))
check("no combo pips for a warrior", not TF.pips[1]:IsShown())
S.units.player.class, S.combo = "ROGUE", 3
W.Update(0.25)
check("combo pips for a rogue", TF.pips[1]:IsShown())
check("no execute marker for a rogue", not TF.exec:IsShown())
check("rogue vs warrior verdict", TF.intel:GetText():find("x1.05", 1, true), TF.intel:GetText())
S.units.player.class, S.combo = "MAGE", nil
-- a friendly player target: no intel, tagged ALLY
S.units.target = { name = "Buddy", guid = "Player-1-0400", class = "PRIEST", level = 30, isPlayer = true, hostile = false, faction = "Alliance", dist = 9 }
W.Fire("PLAYER_TARGET_CHANGED")
check("ally target: tagged, no intel", W.has(TF.tags:GetText(), "ALLY") and TF.intel:GetText() == "")
check("target frame: the intel line under the range strip, not on it", ({ TF.intel:GetPoint(1) })[2] == TF.strip
	and ({ TF.intel:GetPoint(1) })[3] == "BOTTOMLEFT" and TF:GetHeight() >= 142)
-- a dead enemy player (no longer attackable): not an ally
S.units.target = { name = "Gegner", guid = "Player-1-0401", class = "ROGUE", level = 30, isPlayer = true, hostile = true, dead = true, faction = "Horde", dist = 9 }
W.Fire("PLAYER_TARGET_CHANGED")
check("dead enemy player: DEAD, not ALLY", not W.has(TF.tags:GetText(), "ALLY") and W.has(TF.tags:GetText(), "DEAD"), TF.tags:GetText())
;(function()
	-- an enemy player's pet: "Pet of <owner>" for the title, a click targets the owner
	local TG = ns.Targeting
	S.units.target = { name = "Wolf", guid = "Pet-0-1-0-1-7-1", isPlayer = false, hostile = true, owner = "Varok", level = 30, dist = 9 }
	W.Fire("PLAYER_TARGET_CHANGED")
	local ob = TF.ownerButton
	check("enemy pet: Pet of <owner> as the title, in coral", TG.petOwner == "Varok" and TF.title:GetText():find("Pet of Varok", 1, true)
		and TF.title._tc[1] == 1 and TF.title._tc[2] < 0.5, TF.title:GetText())
	check("...a click targets the owner (out of combat)", ob:GetAttribute("type1") == "macro" and ob:GetAttribute("macrotext1") == "/targetexact Varok")
	-- a minion, in the client's other words
	S.units.target = { name = "Wichtel", guid = "Pet-0-1-0-1-8-1", isPlayer = false, hostile = true, owner = "Mortis", ownerTitle = UNITNAME_TITLE_MINION }
	W.Fire("PLAYER_TARGET_CHANGED")
	check("...a minion too", TG.petOwner == "Mortis" and ob:GetAttribute("macrotext1") == "/targetexact Mortis")
	-- Forever: two names, unique together
	S.units.target = { name = "Kater", guid = "Pet-0-1-0-1-9-2", isPlayer = false, hostile = true, owner = "Aldric Hale" }
	W.Fire("PLAYER_TARGET_CHANGED")
	check("two names: the whole name, the click targets it", TG.petOwner == "Aldric Hale" and TF.title:GetText():find("Pet of Aldric Hale", 1, true)
		and ob:GetAttribute("macrotext1") == "/targetexact Aldric Hale")
	check("same player: both names, with a realm, or one the other's first word", TG.SameName("Aldric Hale", "Aldric Hale-Forever")
		and TG.SameName("Aldric", "Aldric Hale") and not TG.SameName("Aldric Hale", "Aldric Halo") and not TG.SameName("Ald", "Aldric Hale"))
	S.units.target = { name = "Wichtel", guid = "Pet-0-1-0-1-8-1", isPlayer = false, hostile = true, owner = "Mortis", ownerTitle = UNITNAME_TITLE_MINION }
	W.Fire("PLAYER_TARGET_CHANGED")
	-- combat: the click emptied (it cannot change then), the owner's plate marked instead
	W.Fire("PLAYER_REGEN_DISABLED")
	check("combat starts: the owner click emptied", ob:GetAttribute("macrotext1") == "")
	W.Fire("PLAYER_REGEN_ENABLED")
	check("after it: set again", ob:GetAttribute("macrotext1") == "/targetexact Mortis")
	-- an NPC (no owner): the title back, nothing to click
	S.units.target = { name = "Kobold", guid = "Creature-0-1-0-1-9-1", isPlayer = false, hostile = true, level = 5 }
	W.Fire("PLAYER_TARGET_CHANGED")
	check("not a pet: the frame's own title, no click", TG.petOwner == nil and TF.title:GetText() == TF.titleText
		and ob:GetAttribute("macrotext1") == "")
	-- a secret tooltip: no owner, no error
	S.secret = { tooltip = true }
	S.units.target = { name = "Wolf", guid = "Pet-0-1-0-1-7-2", isPlayer = false, hostile = true, owner = "Varok" }
	W.Fire("PLAYER_TARGET_CHANGED")
	check("tooltip secret: no owner, nothing breaks", TG.petOwner == nil)
	S.secret = nil
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
end)()
-- unlocked: the target frame stays visible for placement; locked: back on the unit watch
S.units.target = nil
ns.P.hud.locked = false; ns.Changed("hud.locked")
check("unlocked: target frame shown without a target", TF:IsShown() and W.unitWatch[TF] == nil)
W.Update(0.25)
check("placeholder text", TF.name:GetText() == "No target")
ns.P.hud.locked = true; ns.Changed("hud.locked")
check("locked: unit watch again", W.unitWatch[TF] == true)
-- changes in combat wait for the end of combat (secure frames)
S.me.combat = true
ns.P.frames.width = 300; ns.Changed("frames.width")
check("no secure changes in combat", PF:GetWidth() == 264, PF:GetWidth())
S.me.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
check("applied after combat", PF:GetWidth() == 300, PF:GetWidth())
ns.P.frames.width = 264; ns.Changed("frames.width")
S.units.nameplate30 = nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate30")
wipeContacts(C)
ns.db.log.duels.WARRIOR = nil
W.Update(0.25)

-- Request 1: own health colour, green > 75 %, orange 50-75 %, red < 50 %.
local HC = ns.Units.HP_COLORS
local function pfColor() return PF.hp._sbColor end
local function same(c, want) return c and near(c[1], want[1], 1e-9) and near(c[2], want[2], 1e-9) and near(c[3], want[3], 1e-9) end
for _, case in ipairs({ { 3500, "green" }, { 3001, "green" }, { 3000, "orange" }, { 2000, "orange" }, { 1999, "red" }, { 400, "red" } }) do
	S.units.player.hp = case[1]
	W.Update(0.25)
	check(format and string.format("health %d/4000 is %s", case[1], case[2]) or case[2], same(pfColor(), HC[case[2]]), pfColor() and table.concat(pfColor(), ","))
end
-- in combat with secret health the estimate decides (shadow: 4000 - 2500 = 1500 -> 37.5 % -> red)
S.units.player.hp = 4000
W.Update(0.25)
S.me.combat, S.units.player.combat = true, true
S.secret = { health = true }
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 2500, 1)
W.Update(0.25)
check("secret health: colour from the estimate (red)", same(pfColor(), HC.red), pfColor() and table.concat(pfColor(), ","))
S.secret = nil
S.me.combat, S.units.player.combat = false, false
W.Fire("PLAYER_REGEN_ENABLED")
W.Update(0.25)

-- Request 2: clicking a contact row targets that player.
local BR = ns.HUD.modules.board.rows
local function rowFor(name) for _, r in ipairs(BR) do if r:IsShown() and r:GetAlpha() > 0 and r.name:GetText() and r.name:GetText():find(name, 1, true) then return r end end end
wipeContacts(C)
S.units.nameplate31 = { name = "Kesh", guid = "Player-2-0310", class = "ROGUE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 8, screenX = 960 }
S.units.nameplate32 = { name = "Ilsa", guid = "Player-2-0320", class = "MAGE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 38, screenX = 960 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate31"); W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate32")
W.Update(0.25)
local rk, ri = rowFor("Kesh"), rowFor("Ilsa")
check("each row targets its own player", rk and ri and rk.click:GetAttribute("macrotext1") == "/targetexact Kesh" and ri.click:GetAttribute("macrotext1") == "/targetexact Ilsa"
	and rk.click:GetAttribute("type1") == "macro" and rk.click:IsShown())
check("Kesh (closer) ranks first out of combat", BR[1] == rk)
-- combat: the mage closes in and outranks the rogue; rows must not move
S.me.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
S.units.nameplate32.dist, S.units.nameplate32.targetingMe, S.units.nameplate32.casting = 4, true, true
S.units.nameplate31.dist = 39
W.Update(0.25)
check("threat order flipped in the model", ns.Model.byThreat[1].name == "Ilsa")
check("in combat the rows keep their players", BR[1].name:GetText():find("Kesh", 1, true) and BR[1].click:GetAttribute("macrotext1") == "/targetexact Kesh")
check("so the click still matches the row", rowFor("Ilsa").click:GetAttribute("macrotext1") == "/targetexact Ilsa")
-- a new enemy in combat fills a free row, tagged NEW, not clickable yet
S.units.nameplate33 = { name = "Brug", guid = "Player-2-0330", class = "WARRIOR", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 20, screenX = 960 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate33")
W.Update(0.25)
local rb = rowFor("Brug")
check("new contact in combat: NEW, no click yet", rb and W.has(rb.tags:GetText(), "NEW") and not rb.click:IsShown())
-- after combat: re-sorted, everything clickable
S.me.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Update(0.25)
check("after combat: threat order again", BR[1].name:GetText():find("Ilsa", 1, true))
rb = rowFor("Brug")
check("after combat: the new contact is clickable", rb and rb.click:IsShown() and rb.click:GetAttribute("macrotext1") == "/targetexact Brug")
-- secret identity: falls back to the unit token
wipeContacts(C)
S.secret = { guid = true, name = true }
W.Update(0.25)
local tokRow
for _, r in ipairs(BR) do if r:IsShown() and r.click:GetAttribute("type1") == "target" then tokRow = r end end
check("secret identity: row targets the unit token", tokRow and (tokRow.click:GetAttribute("unit") or ""):find("^nameplate"))
S.secret = nil
for _, u in ipairs({ "nameplate31", "nameplate32", "nameplate33" }) do S.units[u] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", u) end
wipeContacts(C)
W.Update(0.25)

-- Request 3: clicking its target targets it.
local tb = TF.totButton
check("its-target button: secure, targets targettarget", tb and tb:GetAttribute("unit") == "targettarget" and tb:GetAttribute("type1") == "target")
;(function()
	-- nothing lights up over it when the target has no target of its own
	local saved = S.units.targettarget
	S.units.targettarget = nil
	tb._scripts.OnEnter(tb)
	check("its-target button: no target of its own, no highlight", not tb.hl:IsShown())
	tb._scripts.OnLeave(tb)
	S.units.targettarget = { name = "Mira", guid = "Player-1-TT1", isPlayer = true, class = "MAGE", level = 30 }
	tb._scripts.OnEnter(tb)
	check("...with one: the highlight", tb.hl:IsShown())
	tb._scripts.OnLeave(tb)
	S.units.targettarget = saved
end)()

-- AURAS ------------------------------------------------------------------------
local AR = ns.Auras.rows
local DC = ns.Data.DISPEL_COLOR
local function vc(t) return W.vc(t) end
local function colorIs(t, c) local v = vc(t); return v and near(v[1], c[1], 1e-9) and near(v[2], c[2], 1e-9) and near(v[3], c[3], 1e-9) end
local function outlined(slot) local v = vc(slot.can.border[1]); return v and v[4] > 0.5 end
S.units.player.class = "PRIEST"   -- cleanses Magic and Disease, purges Magic
S.auras = { player = {
	{ id = 101, harmful = true, icon = "poison.blp", dispel = "Poison", name = "Deadly Poison", stacks = 3 },
	{ id = 102, harmful = true, icon = "poly.blp", dispel = "Magic", name = "Polymorph" },
	{ id = 103, harmful = true, icon = "curse.blp", dispel = "Curse", name = "Curse of Agony" },
} }
W.Update(0.25)
local ps = AR.player.slots
check("your debuffs shown", ps[1]:IsShown() and ps[2]:IsShown() and ps[3]:IsShown() and not ps[4]:IsShown())
check("removable first: Polymorph (magic) leads for a priest", ps[1].id == 102, ps[1].id)
check("removable outlined", outlined(ps[1]) and ps[1].removable == true)
check("not removable: no outline, dimmed", not outlined(ps[2]) and ps[2].removable == false and ps[2]:GetAlpha() < 1)
check("border by type: magic blue", colorIs(ps[1].border, DC.Magic))
check("stacks shown", ps[2].count:GetText() == 3 or ps[3].count:GetText() == 3)
-- in combat the data locks: cached auras keep their facts, a new one goes through the client
S.secret = { auras = true }
table.insert(S.auras.player, { id = 104, harmful = true, icon = "plague.blp", dispel = "Disease", name = "Devouring Plague" })
W.Fire("UNIT_AURA", "player")
local s104
for _, sl in ipairs(ps) do if sl:IsShown() and sl.id == 104 then s104 = sl end end
check("locked aura: cached ones keep their icon", ps[1].icon and ns.Auras.stats.dataCached > 0)
check("locked new aura: question icon, client-coloured border (disease)", s104 and colorIs(s104.border, DC.Disease))
check("locked new aura: the client lights the outline (priest cleanses disease)", s104 and outlined(s104) and s104.removable == nil)
check("client colour path counted", ns.Auras.stats.colorClient > 0)
-- the list itself locked: say so, never guess
S.secret = { auraList = true }
W.Fire("UNIT_AURA", "player")
check("locked list: marker shown, no slots", AR.player.locked:IsShown() and not ps[1]:IsShown())
S.secret = nil
W.Fire("UNIT_AURA", "player")
check("unlocked again", not AR.player.locked:IsShown() and ps[1]:IsShown())

-- enemy target: buffs you can purge outlined, big defensive first and marked, your debuffs bright
S.units.target = { name = "Hal", guid = "Player-2-0500", class = "PALADIN", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 12 }
S.auras.target = {
	{ id = 201, harmful = false, icon = "bom.blp", dispel = "Magic", name = "Blessing of Might" },
	{ id = 202, harmful = false, icon = "ds.blp", dispel = "Magic", name = "Divine Shield", spellId = 642 },
	{ id = 203, harmful = false, icon = "aura.blp", name = "Devotion Aura" },
	{ id = 211, harmful = true, icon = "swp.blp", dispel = "Magic", name = "Shadow Word: Pain", source = "player" },
	{ id = 212, harmful = true, icon = "hamstring.blp", name = "Hamstring", source = "party1" },
}
W.Fire("PLAYER_TARGET_CHANGED")
local tb, td = AR.targetBuffs.slots, AR.targetDebuffs.slots
check("enemy buffs: big defensive first, marked !", tb[1].id == 202 and tb[1].big:GetText() == "!")
check("big defensive bordered red", colorIs(tb[1].border, { 1, 0.25, 0.15 }))
check("purgeable magic buff outlined", tb[2].id == 201 and outlined(tb[2]))
check("non-dispellable buff not outlined", tb[3].id == 203 and not outlined(tb[3]))
check("your debuff on it first and bright", td[1].id == 211 and td[1]:GetAlpha() == 1)
check("someone else's debuff dimmed", td[2].id == 212 and td[2]:GetAlpha() < 1)
check("debuffs on an enemy: never a removal outline", not outlined(td[1]))
-- ally target: debuffs outlined when you can cleanse them, buffs never
S.units.target = { name = "Buddy", guid = "Player-1-0600", class = "WARRIOR", level = 30, isPlayer = true, hostile = false, faction = "Alliance", dist = 9 }
S.auras.target = {
	{ id = 301, harmful = true, icon = "fear.blp", dispel = "Magic", name = "Fear" },
	{ id = 302, harmful = false, icon = "pws.blp", dispel = "Magic", name = "Power Word: Shield" },
}
W.Fire("PLAYER_TARGET_CHANGED")
check("ally debuff you can cleanse: outlined", td[1].id == 301 and outlined(td[1]))
check("ally buff: no outline", tb[1].id == 302 and not outlined(tb[1]))
-- a mage sees an enemy's stealable buffs? (vanilla: mages purge nothing; stealable flag honoured if the client sets it)
-- switches
ns.P.frames.myDebuffs = false; ns.Changed("frames.myDebuffs")
check("your debuffs can be switched off", not AR.player:IsShown())
ns.P.frames.myDebuffs = true; ns.Changed("frames.myDebuffs")
S.units.target, S.auras = nil, nil
S.units.player.class = "MAGE"
W.Fire("PLAYER_TARGET_CHANGED")
W.Update(0.25)
check("no target: target aura rows hidden", not AR.targetBuffs:IsShown())

-- REQUESTS (2.4) -----------------------------------------------------------------
-- 3. No target, no target frame (console closed, HUD locked).
if ns.Config.IsOpen() then ns.Config.Toggle() end
ns.P.hud.locked = true; ns.Changed("hud.locked")
S.units.target = nil
W.Update(0.25)
check("no target: target frame hidden", not TF:IsShown())
S.units.target = { name = "Hal", guid = "Player-2-0700", class = "PALADIN", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 12 }
W.Update(0.25)
check("target: frame shown", TF:IsShown())
S.units.target = nil
W.Update(0.25)
check("target lost: frame hidden again", not TF:IsShown())
ns.Config.Toggle()
ns.P.hud.locked = false; ns.Changed("hud.locked")
W.Update(0.25)
check("console open and HUD unlocked: shown for placing", TF:IsShown())
ns.Config.Toggle()
W.Update(0.25)
check("console closed: hidden again without a target", not TF:IsShown())
ns.P.hud.locked = true; ns.Changed("hud.locked")

-- 1. Its target in class colour, with the class short.
local healer = { name = "Mordente Whitewolf", guid = "Player-1-0800", class = "PALADIN", level = 20, isPlayer = true, hostile = false, faction = "Alliance", dist = 20 }
S.units.target = { name = "Kesh", guid = "Player-2-0810", class = "ROGUE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 12, targetOf = healer }
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
local pr, pg, pb = ns.Data.ClassColor("PALADIN")
local tc = TF.tot._tc
check("its target in class colour (paladin pink)", tc and near(tc[1], pr, 1e-9) and near(tc[2], pg, 1e-9) and near(tc[3], pb, 1e-9))
S.units.target.targetingMe = true
W.Update(0.25)
check("its target is you: red", TF.tot:GetText():lower() == ">> you" and TF.tot._tc[1] == 1, TF.tot:GetText())
S.units.target.targetingMe = nil
W.Update(0.25)
check("its target named with class short", TF.tot:GetText():find(">> Mordente Whitewolf", 1, true) and W.has(TF.tot:GetText(), "PAL"), TF.tot:GetText())
-- 2. Smaller aura timers.
check("aura timer font: 9 on 22 px icons", ns.Auras.rows.player.slots[1].cd._cdFont == "SITREP_AuraTimer22")
check("aura timer font: 8 on 18 px icons", ns.Auras.rows.targetBuffs.slots[1].cd._cdFont == "SITREP_AuraTimer18")

-- 4. Cast bar: amber, bright with KICK in its last quarter, grey when it cannot be interrupted.
local CA = ns.Units.CAST
local function castColor() return TF.cast._sbColor end
local function sameC(c, w) return c and near(c[1], w[1], 1e-9) and near(c[2], w[2], 1e-9) and near(c[3], w[3], 1e-9) end
local caster = S.units.target
caster.casting, caster.castStart, caster.castEnd = true, W.now * 1000 - 1000, W.now * 1000 + 1000
W.Fire("UNIT_SPELLCAST_START", "target"); W.Update(0.01)
check("cast at ~50%: normal amber, no KICK", TF.cast:IsShown() and sameC(castColor(), CA.normal) and not TF.castKick:IsShown(), castColor() and table.concat(castColor(), ","))
W.Update(0.6)
check("cast past 75%: highlighted, KICK", sameC(castColor(), CA.hot) and TF.castKick:IsShown() and TF.castGlow:IsShown())
caster.notInt = true
W.Fire("UNIT_SPELLCAST_START", "target"); W.Update(0.01)
check("not interruptible: grey, never KICK", sameC(castColor(), CA.locked) and not TF.castKick:IsShown())
caster.notInt = false
S.secret = { cast = true }
W.Fire("UNIT_SPELLCAST_START", "target"); W.Update(0.01)
check("interruptibility secret: the client colours it", sameC(castColor(), CA.locked) and not TF.castKick:IsShown())
S.secret = nil
caster.casting = false
W.Fire("UNIT_SPELLCAST_STOP", "target"); W.Update(0.01)
check("cast over: bar hidden", not TF.cast:IsShown())
S.units.target = nil
W.Update(0.25)

-- REQUESTS (2.5) -----------------------------------------------------------------
-- 1. Short buffs (burst / defensive) glow gold and lead after big defensives.
S.units.player.class = "PRIEST"
S.units.target = { name = "Thrag", guid = "Player-2-0900", class = "WARRIOR", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 12 }
S.auras = { target = {
	{ id = 401, harmful = false, icon = "bshout.blp", name = "Battle Shout", duration = 120 },
	{ id = 402, harmful = false, icon = "reck.blp", name = "Recklessness", duration = 15 },
	{ id = 403, harmful = false, icon = "fort.blp", dispel = "Magic", name = "Power Word: Fortitude", duration = 1800 },
	{ id = 404, harmful = false, icon = "aura.blp", name = "Retribution Aura", duration = 0 },
} }
W.Update(0.25) -- let the sensors pick up the class change
W.Fire("PLAYER_TARGET_CHANGED")
local tbS = ns.Auras.rows.targetBuffs.slots
check("short buff first, with a gold glow", tbS[1].id == 402 and tbS[1].burst:IsShown())
check("long and permanent buffs: no glow", not tbS[2].burst:IsShown() and not tbS[3].burst:IsShown() and not tbS[4].burst:IsShown())
check("purgeable buff next", tbS[2].id == 403)
ns.P.frames.burstMax = 10
W.Fire("PLAYER_TARGET_CHANGED")
check("threshold respected (15 s > 10 s: no glow)", not tbS[1].burst:IsShown() or tbS[1].id ~= 402)
ns.P.frames.burstMax = 15
-- locked aura data: the client's base duration still tells
S.secret = { auras = true }
table.insert(S.auras.target, { id = 405, harmful = false, icon = "sw.blp", name = "Shield Wall", duration = 10 })
W.Fire("UNIT_AURA", "target")
local swGlow
for _, sl in ipairs(tbS) do if sl:IsShown() and sl.id == 405 then swGlow = sl.burst:IsShown() end end
check("locked aura: glow from the client's base duration", swGlow == true)
S.secret, S.auras = nil, nil
S.units.player.class = "MAGE"

-- 4. Range strip: enemies by harmful spells, allies by helpful ones, on a 0-40 yd scale.
W.Fire("SPELLS_CHANGED")
local function nonItem(list) local n = 0 for _, c in ipairs(list) do if c.kind ~= "item" then n = n + 1 end end return n end
check("helpful ladder built separately", nonItem(ns.Sensors.helpChecks) == 3 and ns.Sensors.myHelpRanges[1] == 40, nonItem(ns.Sensors.helpChecks))
check("harmful ladder unchanged", nonItem(ns.Sensors.checks) == 5)
wipeContacts(C)
S.units.target = { name = "Raider", guid = "Player-2-0910", class = "MAGE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 34 }
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
check("enemy at 34 yd: harmful bracket and spells", TF.strip.info:GetText():find("30-35y", 1, true) and TF.strip.info:GetText():find("1/3", 1, true), TF.strip.info:GetText())
S.units.target = { name = "Medic", guid = "Player-1-0920", class = "PRIEST", level = 30, isPlayer = true, hostile = false, faction = "Alliance", dist = 34 }
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
check("ally at 34 yd: helpful bracket (heal reaches 40)", TF.strip.info:GetText():find("28-40y", 1, true) and TF.strip.info:GetText():find("1/1", 1, true), TF.strip.info:GetText())
check("ally: spell lines green", TF.strip.lines[1]._vc and W.vc(TF.strip.lines[1])[2] > 0.9 and W.vc(TF.strip.lines[1])[1] < 0.5)
check("0-40 yd scale ticks", #TF.strip.ticks == 7)
S.units.target = nil
W.Update(0.25)

-- 3. Per-frame size on top of the global scale.
ns.P.hud.scale = 1.2
ns.P.hud.frameScale.board, ns.P.hud.frameScale.player = 1.5, 0.8
ns.Changed("hud.frameScale")
check("board at 150% of the HUD scale", near(ns.HUD.modules.board:GetScale(), 1.8, 1e-9), ns.HUD.modules.board:GetScale())
check("player frame at 80% of the HUD scale", near(PF:GetScale(), 0.96, 1e-9), PF:GetScale())
check("others follow the HUD scale", near(ns.HUD.modules.engage:GetScale(), 1.2, 1e-9))
ns.P.hud.scale, ns.P.hud.frameScale.board, ns.P.hud.frameScale.player = 1, 1, 1
ns.Changed("hud.frameScale")

-- 2. Only with enemy players around.
if ns.Config.IsOpen() then ns.Config.Toggle() end
ns.P.hud.locked = true
ns.P.hud.autoHide.envelope, ns.P.hud.autoHide.player = true, true
ns.Changed("hud.autoHide")
for k in pairs(S.units) do if k:match("^nameplate") then S.units[k] = nil end end -- nobody around
wipeContacts(C)
for _ = 1, 8 do W.Update(0.1) end
local ENV = ns.HUD.modules.envelope
check("no enemies: envelope faded out", ENV:GetAlpha() < 0.05, ENV:GetAlpha())
check("no enemies: player frame faded, click-through", PF:GetAlpha() < 0.05 and PF._mouse == false)
check("modules not set to auto-hide stay", ns.HUD.modules.engage:GetAlpha() > 0.95)
S.units.nameplate40 = { name = "Gor", guid = "Player-2-0940", class = "WARRIOR", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 30, screenX = 960 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate40")
for _ = 1, 8 do W.Update(0.1) end
check("enemy player appears: envelope fades in", ENV:GetAlpha() > 0.95, ENV:GetAlpha())
check("player frame back and clickable", PF:GetAlpha() > 0.95 and PF._mouse == true)
S.units.nameplate40 = nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate40")
wipeContacts(C)
ns.P.hud.locked = false
for _ = 1, 8 do W.Update(0.1) end
check("unlocked for placing: stays visible", ENV:GetAlpha() > 0.95)
ns.P.hud.locked = true
ns.P.hud.autoHide.envelope, ns.P.hud.autoHide.player = false, false
ns.Changed("hud.autoHide")
for _ = 1, 8 do W.Update(0.1) end

-- NAMES IN ANY ALPHABET (2.5.1) ---------------------------------------------------
local K_ = ns.Kit
local fam = K_.Family(K_.FONT, 14, "")
local byAlpha = {}
for _, m in ipairs(fam and fam._members or {}) do byAlpha[m.alphabet] = m.file end
check("font family: our face for Latin", byAlpha.roman == K_.FONT)
check("font family: Cyrillic from the chat's font (DM Sans has none)", byAlpha.russian == "Fonts\\CHAT_CYR.TTF", byAlpha.russian)
check("font family: Korean and Chinese from the chat's font (faces this client surely has)", byAlpha.korean == "Fonts\\CHAT_KO.TTF"
	and byAlpha.simplifiedchinese == "Fonts\\CHAT_ZH.TTF" and byAlpha.traditionalchinese == "Fonts\\CHAT_TW.TTF", byAlpha.korean)
check("Friz face borrows from the Friz family", (function() for _, m in ipairs(K_.Family("Fonts\\FRIZQT__.TTF", 12, "")._members) do if m.alphabet == "russian" then return m.file == "Fonts\\FRIZQT___CYR.TTF" end end end)())
check("families are reused, not recreated", K_.Family(K_.FONT, 14, "") == fam)
;(function()
	-- an object that answers its Latin face for every alphabet is skipped (no family)
	local ffam = K_.Family("Fonts\\FAKE.TTF", 13, "", ChatFrame1:GetFontObject())
	local fzh
	for _, m in ipairs(ffam._members) do if m.alphabet == "simplifiedchinese" then fzh = m.file end end
	check("font family: an object without other alphabets is passed over", fzh == "Fonts\\CHAT_ZH.TTF", fzh)
end)()
check("the target's name uses a family", TF.name._fontObj ~= nil and TF.name._fontObj._members ~= nil)
for _, nm in ipairs({ "Владимир", "김철수", "李小龙", "Jürgen", "Weißfuß" }) do
	S.units.target = { name = nm, guid = "Player-9-" .. nm, class = "MAGE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 20 }
	W.Fire("PLAYER_TARGET_CHANGED")
	check("target name kept exactly: " .. nm, TF.name:GetText() == nm, TF.name:GetText())
end
S.units.target = nil
W.Update(0.25)
check("upper(): text kept as it is (sentence case is K.Case's)", K_.Upper("Stunned") == "Stunned")
check("upper(): German left intact", K_.Upper("Betäubt") == "Betäubt")
check("upper(): Cyrillic left intact", K_.Upper("Оглушение") == "Оглушение")
S.loc = { displayText = "Betäubt", timeRemaining = 1.5 }
W.Update(0.25)
check("loss of control text not mangled", PF.loc.text:GetText() == "Betäubt", PF.loc.text:GetText())
S.loc = nil
W.Update(0.25)

-- PRESSURE LEVELS (2.6) -----------------------------------------------------------
local PR = ns.Pressure
S.units.player.hp, S.units.player.hpMax = 4000, 4000
W.Update(0.25)
check("level: 150 dps on 4000 hp is calm (3.75 %/s)", PR.Level(150) == "calm")
check("level: 250 dps is orange (6.25 %/s)", PR.Level(250) == "warn")
check("level: 500 dps is red (12.5 %/s)", PR.Level(500) == "danger")
ns.P.pressure.warnPct = 8
check("thresholds follow the settings", PR.Level(250) == "calm")
ns.P.pressure.warnPct = 5
local PG = ns.HUD.modules.pressure
-- a burst: 400 damage inside one half-second bucket = 800 dps = 20 %/s -> red bar
S.me.combat, S.units.player.combat = true, true
W.Fire("PLAYER_REGEN_DISABLED")
W.Fire("UNIT_COMBAT", "player", "WOUND", "", 400, 1)
W.Update(0.25)
local lastBar = PG.spark[20]._vc
check("hard-hit moment: its bar turns red", lastBar and lastBar[1] == 1 and lastBar[2] < 0.35, lastBar and table.concat(lastBar, ","))
local calmBar = PG.spark[5]._vc
local acR, acG, acB = ns.Kit.Accent()
check("quiet moments keep the accent colour", calmBar and near(calmBar[1], acR, 1e-9) and near(calmBar[2], acG, 1e-9) and near(calmBar[3], acB, 1e-9))
-- short-window rate 400 / 3 s = 133 dps = 3.3 %/s: the number stays neutral
check("DPS number neutral below the threshold", PG.level == "calm", PG.level)
for _ = 1, 3 do W.Fire("UNIT_COMBAT", "player", "WOUND", "", 400, 1) end
W.Update(0.25)
check("DPS number orange or red once the rate climbs", PG.level == "warn" or PG.level == "danger", PG.level)
check("player frame colours its DPS IN too", PF.line:GetText():find("|cffff", 1, true) and W.has(PF.line:GetText(), "DPS IN"))
S.me.combat, S.units.player.combat = false, false
W.Fire("PLAYER_REGEN_ENABLED")
W.Update(11)
-- clearer exposure wording
check("exposure wording", W.has(PF.line:GetText(), "OUT OF ENEMY REACH"), PF.line:GetText())

-- ALLIES (2.9) ---------------------------------------------------------------------
local AL = ns.Allies
for k in pairs(S.units) do if k:match("^nameplate") then S.units[k] = nil end end
wipeContacts(C)
S.units.target, S.units.mouseover = nil, nil
S.me.x, S.me.y, S.me.facing = 0, 0, 0
S.group.n = 0
W.Update(0.25)
check("no allies: panel kept out of sight", #AL.list == 0 and ns.HUD.Faded("allies"))
-- a party: a priest 11 yd away (north-north-east), a warrior 45 yd behind
S.group.n = 2
S.units.party1 = { name = "Mordente Whitewolf", guid = "Player-1-1100", class = "PRIEST", level = 30, isPlayer = true, hostile = false, faction = "Alliance", wx = 10, wy = -5, hp = 3000, hpMax = 3000 }
S.units.party2 = { name = "Tank", guid = "Player-1-1200", class = "WARRIOR", level = 30, isPlayer = true, hostile = false, faction = "Alliance", wx = -45, wy = 0, hp = 5000, hpMax = 5000 }
W.Update(0.25); W.Update(0.25)
local m1 = AL.byKey["Player-1-1100"]
check("group member: exact position from the client", m1 and m1.exact and near(m1.range, math.sqrt(125), 1e-9))
check("exact distance text", ns.Comms.RangeText(m1) == "11y", ns.Comms.RangeText(m1))
check("in heal range (Flash Heal 40)", m1.inHeal == true)
check("45 yd: out of heal range", AL.byKey["Player-1-1200"].inHeal == false)
check("panel visible with allies", not ns.HUD.Faded("allies"))
local AP = ns.HUD.modules.allies
local ar = AP.rows[1]
check("roster order: party1 first", ar.name:GetText() == "Mordente Whitewolf")
check("distance green: in heal range", ar.where._tc and ar.where._tc[2] > 0.9, ar.where._tc and ar.where._tc[2])
check("tag: in heal range", W.has(ar.tags:GetText(), "IN HEAL RANGE"))
check("second row: out of heal range, red distance", W.has(AP.rows[2].tags:GetText(), "OUT OF HEAL RANGE") and AP.rows[2].where._tc[1] == 1 and AP.rows[2].where._tc[2] < 0.5)
check("click a row: target that ally", ar.click:GetAttribute("macrotext1") == "/targetexact Mordente Whitewolf")
-- an enemy trains the priest
S.units.nameplate51 = { name = "Hunter", guid = "Player-2-1300", class = "ROGUE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 20, screenX = 960, targetOf = S.units.party1 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate51")
W.Update(0.25); W.Update(0.25)
check("focus counted", m1.focus == 1, m1.focus)
check("row shows TARGETED BY 1", W.has(ar.tags:GetText(), "TARGETED BY 1"))
check("panel header counts targeted allies", AP.status:GetText():lower() == "1 targeted", AP.status:GetText())
-- a friendly player outside the group, seen on a friendly nameplate
S.restrictMeasure = true -- as on Forever: friendly plates give no direction either
S.units.nameplate52 = { name = "Stranger", guid = "Player-1-1400", class = "MAGE", level = 30, isPlayer = true, hostile = false, faction = "Alliance", dist = 25, screenX = 960 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate52")
W.Update(0.25)
local st = AL.byKey["Player-1-1400"]
check("non-group ally: listed after the group", st and AL.list[3] == st)
check("non-group ally: bracket from helpful spells", ns.Comms.RangeText(st) == "10-28y", ns.Comms.RangeText(st))
S.restrictMeasure = nil
;(function()
	-- a friendly plate is measured about once a second, still counted on every tick in between
	local realMR, asked = ns.Sensors.MeasureRange, 0
	ns.Sensors.MeasureRange = function(unit, ...)
		if unit == "nameplate52" then asked = asked + 1 end
		return realMR(unit, ...)
	end
	st.nextAt = GetTime() + 0.6
	W.Update(0.25); W.Update(0.25)
	check("non-group ally: not measured before its beat", asked == 0 and st.live and st.unit == "nameplate52", asked)
	W.Update(0.25)
	check("...measured again when its beat comes", asked >= 1 and st.nextAt > GetTime(), asked)
	ns.Sensors.MeasureRange = realMR
end)()
-- target frame on a friendly group member: exact distance and arrow
S.units.target = S.units.party1
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
check("target frame: ally's exact distance", TF.strip.info:GetText():find("^11y"), TF.strip.info:GetText())
S.units.target = nil
-- the client withholds group positions: members fall back to estimates
S.restrictGroupPos = true
W.Update(0.25)
check("withheld: member falls back to the bracket", not m1.exact and ns.Comms.RangeText(m1) == "10-28y", ns.Comms.RangeText(m1))
check("withheld: counted for the diagnostics", AL.stats.noExact == 2 and AL.stats.exact == 0)
S.restrictGroupPos = nil
-- leaving the group
S.group.n = 0
S.units.nameplate51, S.units.nameplate52 = nil, nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate51"); W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate52")
W.Update(0.25)
check("group members drop when you leave", AL.byKey["Player-1-1100"] == nil)
W.Update(11)
check("others fade after 10 s", #AL.list == 0)
S.units.party1, S.units.party2 = nil, nil
wipeContacts(C)
W.Update(0.25)



-- PET FRAME (3.3) -------------------------------------------------------------------
local PET = ns.Frames.frames.pet
check("pet frame built", PET ~= nil and PET.hp and PET.cast and PET.power)
check("pet frame shown only with a pet (unit watch)", W.unitWatch[PET] == true)
check("pet frame clicks target your pet", PET:GetAttribute("unit") == "pet" and PET:GetAttribute("type1") == "target")
check("Blizzard pet frame faded too", PetFrame:GetAlpha() == 0 and PetFrame._ignoreParentAlpha == false)
-- a hunter's wolf, hurt, fighting a rogue
local rogueT = { name = "Stabby", guid = "Player-2-6100", class = "ROGUE", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 12, hp = 3000, hpMax = 3000 }
S.units.pet = { name = "Wuffi", guid = "Pet-0-1-0-1-1-6000", level = 60, isPlayer = false, hostile = false, faction = "Alliance",
	family = "Wolf", hp = 300, hpMax = 1000, power = 50, powerMax = 100, powerType = 2, combat = true, targetOf = rogueT }
W.Fire("UNIT_PET", "player")
check("pet name", PET.name:GetText() == "Wuffi", PET.name:GetText())
check("pet family shown (level equal to yours: hidden)", PET.level:GetText() == "Wolf", PET.level:GetText())
check("pet health fed from the client", PET.hp._value == 300 and PET.hp._max == 1000)
check("pet health colour: orange below 50 %", PET.hp._sbColor and PET.hp._sbColor[1] == 1 and PET.hp._sbColor[2] > 0.5)
check("pet power fed", PET.power._value == 50 and PET.power._max == 100)
check("pet in combat tagged", W.has(PET.tags:GetText(), "COMBAT"))
check("what it attacks, in class colour", PET.ptt:GetText() == ">> Stabby" and PET.ptt._tc and near(PET.ptt._tc[1], ns.Data.ClassColor("ROGUE")), PET.ptt:GetText())
check("click its target: pettarget", PET.pttButton:GetAttribute("unit") == "pettarget")
-- health changes arrive by event, before the next tick
S.units.pet.hp = 200
W.Fire("UNIT_HEALTH", "pet")
check("pet health event: redrawn at once, red below 25 %", PET.hp._value == 200 and PET.hp._sbColor[2] < 0.5)
-- a warlock's imp style cast: progress bar, never KICK (it is your own pet)
local tnow = GetTime() * 1000
S.units.pet.casting, S.units.pet.castName, S.units.pet.castStart, S.units.pet.castEnd = true, "Feuerblitz", tnow - 1800, tnow + 200
W.Fire("UNIT_SPELLCAST_START", "pet")
check("pet cast bar shown with the spell", PET.cast:IsShown() and PET.castText:GetText() == "Feuerblitz", PET.castText:GetText())
PET.castUpdate(PET)
check("own pet's cast: never KICK, own colour", not PET.castKick:IsShown() and PET.cast._sbColor[3] == 1, PET.cast._sbColor and PET.cast._sbColor[3])
S.units.pet.casting = nil
W.Fire("UNIT_SPELLCAST_STOP", "pet")
check("pet cast bar hidden after the cast", not PET.cast:IsShown())
-- heals on the pet
S.units.pet.incHeal = 250
W.Fire("UNIT_HEAL_PREDICTION", "pet")
check("heals on the pet drawn", PET.hp.heal.all:IsShown() and PET.hp.heal.all._value == 250)
-- hit flash
W.Fire("UNIT_COMBAT", "pet", "WOUND", 0, 150, 1)
check("pet hit flash", PET.flash:GetAlpha() > 0)
-- dead pet
S.units.pet.dead = true
W.Update(0.25)
check("dead pet tagged", W.has(PET.tags:GetText(), "DEAD"))
-- dismissed
S.units.pet = nil
W.Fire("UNIT_PET", "player")
check("no pet: overlays cleared", not PET.hp.heal.all:IsShown() and not PET.cast:IsShown())
-- pet frame off: Blizzard's pet frame comes back although the player frame stays faded
ns.P.frames.pet = false; ns.Changed("frames.pet")
check("pet frame off: hidden and unwatched", not PET:IsShown() and not W.unitWatch[PET])
check("pet frame off: Blizzard's pet frame visible despite its faded parent", PetFrame:GetAlpha() == 1 and PetFrame._ignoreParentAlpha == true)
ns.P.frames.pet = true; ns.Changed("frames.pet")
check("pet frame on again", W.unitWatch[PET] == true and PetFrame:GetAlpha() == 0)
check("pet frame scale setting", ns.P.hud.frameScale.pet == 1)
W.Update(0.25)

-- TARGET'S PET (3.4) ----------------------------------------------------------------
local TPET = ns.Frames.frames.targetpet
check("target's pet frame built", TPET ~= nil and TPET.hp and TPET.cast and TPET.dist)
check("target's pet: shown only while it exists", W.unitWatch[TPET] == true and TPET:GetAttribute("unit") == "targetpet")
-- an enemy hunter targeted; its cat is on you, 15 yd away
local hunterT = { name = "Pewpew", guid = "Player-2-6200", class = "HUNTER", level = 60, isPlayer = true, hostile = true,
	faction = "Horde", dist = 25, hp = 3000, hpMax = 3000 }
S.units.target = hunterT
S.units.targetpet = { name = "Krallchen", guid = "Pet-0-1-0-1-2-6201", level = 58, isPlayer = false, hostile = true, faction = "Horde",
	reaction = 2, family = "Cat", hp = 900, hpMax = 1200, dist = 15, combat = true, targetOf = S.units.player }
W.Fire("PLAYER_TARGET_CHANGED")
check("target's pet name, hostile red", TPET.name:GetText() == "Krallchen" and TPET.name._tc and TPET.name._tc[1] == 1 and TPET.name._tc[2] < 0.5, TPET.name:GetText())
check("family and level (differs from yours)", TPET.level:GetText() == "Cat  58", TPET.level:GetText())
check("target's pet health fed", TPET.hp._value == 900 and TPET.hp._max == 1200)
check("target's pet distance from your harmful spells", TPET.dist:GetText() == "10-20y", TPET.dist:GetText())
check("target's pet attacking you", TPET.ptt:GetText():lower() == ">> you")
check("click its target: targetpettarget", TPET.pttButton:GetAttribute("unit") == "targetpettarget")
-- an enemy pet's cast can be kicked
local tn = GetTime() * 1000
S.units.targetpet.casting, S.units.targetpet.castName, S.units.targetpet.castStart, S.units.targetpet.castEnd = true, "Verführung", tn - 1800, tn + 200
W.Update(0.25)
TPET.castUpdate(TPET)
check("enemy pet's cast: KICK in its last quarter", TPET.cast:IsShown() and TPET.castKick:IsShown(), TPET.castText:GetText())
S.units.targetpet.casting = nil
W.Update(0.25)
check("cast over: bar hidden", not TPET.cast:IsShown())
-- a friendly target's pet: green name, helpful-spell distance, no KICK
S.units.target = { name = "Buddy", guid = "Player-1-6300", class = "WARLOCK", level = 60, isPlayer = true, hostile = false, faction = "Alliance", dist = 20 }
S.units.targetpet = { name = "Blubb", guid = "Pet-0-1-0-1-3-6301", level = 60, isPlayer = false, hostile = false, faction = "Alliance",
	reaction = 5, family = "Voidwalker", hp = 2000, hpMax = 2000, dist = 30, casting = true, castName = "Opferung", castStart = tn - 1900, castEnd = tn + 100 }
W.Fire("PLAYER_TARGET_CHANGED")
TPET.castUpdate(TPET)
check("friendly target's pet: green name", TPET.name._tc and TPET.name._tc[2] > 0.9)
check("friendly target's pet: distance from helpful spells", TPET.dist:GetText() == "28-40y", TPET.dist:GetText())
check("friendly pet's cast: no KICK", TPET.cast:IsShown() and not TPET.castKick:IsShown())
-- a target without a pet
S.units.targetpet = nil
W.Fire("PLAYER_TARGET_CHANGED")
check("no pet on the target: overlays cleared", not TPET.cast:IsShown() and not TPET.hp.heal.all:IsShown())
ns.P.frames.targetPet = false; ns.Changed("frames.targetPet")
check("target's pet frame off: hidden and unwatched", not TPET:IsShown() and not W.unitWatch[TPET])
ns.P.frames.targetPet = true; ns.Changed("frames.targetPet")
check("target's pet frame on again", W.unitWatch[TPET] == true)
-- targeting an enemy pet itself: the target frame treats it as an enemy (NPC tag, harmful ranges)
S.units.target = { name = "Krallchen", guid = "Pet-0-1-0-1-2-6201", level = 58, isPlayer = false, hostile = true, faction = "Horde",
	reaction = 2, family = "Cat", hp = 900, hpMax = 1200, dist = 15 }
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
check("enemy pet as target: NPC tag and harmful range", W.has(TF.tags:GetText(), "NPC") and TF.strip.info:GetText():find("^10%-20y"), TF.tags:GetText() .. " | " .. TF.strip.info:GetText())
check("enemy pet not on the contacts board (players only by default)", C["Pet-0-1-0-1-2-6201"] == nil)
S.units.target = nil
W.Fire("PLAYER_TARGET_CHANGED")
wipeContacts(C)
W.Update(0.25)

-- PARTY FRAMES (3.5) ----------------------------------------------------------------
local PH, PM = ns.Frames.party, ns.Frames.partyMembers
check("party frames built: header and 4 members", PH ~= nil and #PM == 4)
check("party header shown only in a group", W.stateDrivers[PH] and W.stateDrivers[PH].visibility == "[group] show; hide")
check("each member shown only while it exists", W.unitWatch[PM[1]] and W.unitWatch[PM[4]] and PM[3]:GetAttribute("unit") == "party3")
check("click a member to target it, right-click for its menu", PM[1]:GetAttribute("type1") == "target" and PM[1]:GetAttribute("type2") == "togglemenu")
check("Blizzard party frames faded", CompactPartyFrame:GetAlpha() == 0 and CompactPartyFrameMember1:GetAlpha() == 0 and PartyFrame.MemberFrame1:GetAlpha() == 0)
S.units.player.class = "PRIEST" -- cleanses Magic and Disease
S.group.n = 3
S.units.party1 = { name = "Mordente", guid = "Player-1-7100", class = "PALADIN", level = 60, isPlayer = true, hostile = false, faction = "Alliance",
	wx = 10, wy = 0, hp = 1500, hpMax = 3000, power = 40, powerMax = 100, incHeal = 600 }
S.units.party2 = { name = "Faraway", guid = "Player-1-7200", class = "MAGE", level = 60, isPlayer = true, hostile = false, faction = "Alliance",
	wx = 50, wy = 0, hp = 2900, hpMax = 3000 }
S.units.party3 = { name = "Gone", guid = "Player-1-7300", class = "ROGUE", level = 60, isPlayer = true, hostile = false, faction = "Alliance",
	wx = 5, wy = 0, hp = 0, hpMax = 3000, dead = true }
S.auras = S.auras or {}
S.auras.party1 = {
	{ id = 701, harmful = true, icon = "fear.blp", dispel = "Curse", name = "Curse of Tongues" },
	{ id = 702, harmful = true, icon = "poly.blp", dispel = "Magic", name = "Polymorph" },
}
W.Fire("GROUP_ROSTER_UPDATE")
W.Update(0.25); W.Update(0.25)
local m1, m2, m3 = PM[1], PM[2], PM[3]
check("member name in class colour", m1.name:GetText() == "Mordente" and m1.name._tc and near(m1.name._tc[1], ns.Data.ClassColor("PALADIN")))
check("class edge on the left", m1.edge._vc and near(W.vc(m1.edge)[1], ns.Data.ClassColor("PALADIN")))
check("member health fed", m1.hp._value == 1500 and m1.hp._max == 3000)
check("member health colour: orange at 50 %", m1.hp._sbColor and near(m1.hp._sbColor[1], ns.Units.HP_COLORS.orange[1]) and near(m1.hp._sbColor[2], ns.Units.HP_COLORS.orange[2]))
check("member power fed", m1.power._value == 40)
check("incoming heals on a member", m1.hp.heal.all:IsShown() and m1.hp.heal.all._value == 600)
check("exact distance, green: in heal range", m1.dist:GetText() == "10y" and m1.dist._tc[2] > 0.9, m1.dist:GetText())
check("in range: full opacity", m1:GetAlpha() == 1)
check("out of heal range: red distance, frame faded", m2.dist:GetText() == "50y" and m2.dist._tc[1] == 1 and m2:GetAlpha() < 0.6, m2.dist:GetText())
check("dead member tagged, grey bar", W.has(m3.tags:GetText(), "DEAD") and m3.hp._sbColor[1] < 0.5)
check("header counts who is in heal range", PH.status:GetText():lower() == "2/3 in heal range", PH.status:GetText())
local pr = ns.Auras.rows.party1
check("member debuffs: the one you can remove first (magic for a priest), outlined", pr:IsShown() and pr.slots[1].id == 702 and outlined(pr.slots[1]), pr.slots[1].id)
check("not removable: no outline", pr.slots[2].id == 701 and not outlined(pr.slots[2]))
-- an enemy trains the paladin
S.units.nameplate70 = { name = "Hunter", guid = "Player-2-7400", class = "ROGUE", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 20, targetOf = S.units.party1 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate70")
W.Update(0.25); W.Update(0.25)
check("TARGETED BY when enemy players target a member", W.has(m1.tags:GetText(), "TARGETED BY 1"), m1.tags:GetText())
-- events redraw at once
S.units.party1.hp = 600
W.Fire("UNIT_HEALTH", "party1")
check("health event redraws the member, red below 50 %", m1.hp._value == 600 and near(m1.hp._sbColor[1], ns.Units.HP_COLORS.red[1]) and m1.hp._sbColor[2] < 0.5)
local tq = GetTime() * 1000
S.units.party1.casting, S.units.party1.castName, S.units.party1.castStart, S.units.party1.castEnd = true, "Lichtblitz", tq - 1800, tq + 200
W.Fire("UNIT_SPELLCAST_START", "party1")
m1.castUpdate(m1)
check("member cast bar: progress, no KICK (a friend)", m1.cast:IsShown() and m1.castText:GetText() == "Lichtblitz" and not m1.castKick:IsShown())
S.units.party1.casting = nil
W.Fire("UNIT_SPELLCAST_STOP", "party1")
W.Fire("UNIT_COMBAT", "party1", "WOUND", 0, 300, 1)
check("member hit flash", m1.flash:GetAlpha() > 0)
-- offline
S.units.party2.offline = true
W.Update(0.25)
check("offline member: tagged and faded", W.has(m2.tags:GetText(), "OFFLINE") and m2:GetAlpha() < 0.5)
-- switched off
ns.P.frames.party = false; ns.Changed("frames.party")
check("party frames off: hidden, no state driver, unwatched", not PH:IsShown() and not W.stateDrivers[PH].visibility and not W.unitWatch[PM[1]])
check("party frames off: Blizzard's back", CompactPartyFrame:GetAlpha() == 1)
ns.P.frames.party = true; ns.Changed("frames.party")
check("party frames on again", W.stateDrivers[PH].visibility ~= nil and W.unitWatch[PM[1]])
S.units.nameplate70 = nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate70")
S.units.party1, S.units.party2, S.units.party3, S.group.n = nil, nil, nil, 0
S.auras.party1 = nil
S.units.player.class = "MAGE"
W.Fire("GROUP_ROSTER_UPDATE")
wipeContacts(C)
W.Update(11)

-- PLAYER LEVEL, REST, HIGHLIGHTS, TARGETED (3.6) ------------------------------------
local PFx = ns.Frames.frames.player
W.Update(0.25)
check("player frame: your level beside YOU", PFx.lvl:GetText() == "60", PFx.lvl:GetText())
check("not resting: no zZZ", not PFx.rest:IsShown())
S.me.resting = true
W.Update(0.25)
check("resting: zZZ", PFx.rest:IsShown() and PFx.rest:GetText() == "zZZ")
S.me.resting = nil
W.Update(0.25)
check("left the inn: zZZ gone", not PFx.rest:IsShown())
-- attacked: red border, held a second, then fading out
W.Fire("UNIT_COMBAT", "player", "WOUND", 0, 200, 1)
check("hit: red highlight on", PFx.hit:GetAlpha() == 1)
W.Update(0.5)
check("held while the hits keep coming", PFx.hit:GetAlpha() == 1)
W.Update(1.25)
check("then fading", PFx.hit:GetAlpha() > 0 and PFx.hit:GetAlpha() < 1, PFx.hit:GetAlpha())
W.Update(1.0)
check("gone 1.5 s after", PFx.hit:GetAlpha() == 0)
W.Fire("UNIT_COMBAT", "player", "DODGE", 0, 0, 1)
check("a dodged attack counts too", PFx.hit:GetAlpha() == 1)
W.Update(3)
W.Fire("UNIT_COMBAT", "player", "HEAL", 0, 300, 1)
check("a heal is not an attack", PFx.hit:GetAlpha() == 0)
ns.P.frames.hitGlow = false
W.Fire("UNIT_COMBAT", "player", "WOUND", 0, 200, 1)
check("highlight switch off", PFx.hit:GetAlpha() == 0)
ns.P.frames.hitGlow = true
-- targeted by enemy players
S.units.nameplate71 = { name = "Eyes", guid = "Player-2-7500", class = "WARLOCK", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 25, targetingMe = true }
S.units.nameplate72 = { name = "More", guid = "Player-2-7600", class = "MAGE", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 30, targetingMe = true }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate71"); W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate72")
W.Update(0.25); W.Update(0.25)
check("player frame: TARGETED BY 2", W.has(PFx.tags:GetText(), "TARGETED BY 2"), PFx.tags:GetText())
S.units.nameplate71, S.units.nameplate72 = nil, nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate71"); W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate72")
W.Update(1.5)
check("nobody targeting: tag gone", not W.has(PFx.tags:GetText(), "TARGETED"), PFx.tags:GetText())
-- a debuff you can dispel: border in its colour
S.units.player.class = "PRIEST" -- Magic and Disease
S.auras = S.auras or {}
S.auras.player = { { id = 801, harmful = true, icon = "c.blp", dispel = "Curse", name = "Curse of Weakness" } }
W.Update(0.25)
check("curse on a priest: nothing to dispel, no border", not PFx.disp:IsShown())
table.insert(S.auras.player, { id = 802, harmful = true, icon = "m.blp", dispel = "Magic", name = "Frost Nova" })
W.Fire("UNIT_AURA", "player")
check("magic on a priest: border in magic blue", PFx.disp:IsShown() and near(W.vc(PFx.disp.border[1])[3], ns.Data.DISPEL_COLOR.Magic[3]) and near(W.vc(PFx.disp.border[1])[1], ns.Data.DISPEL_COLOR.Magic[1]))
local a1 = PFx.disp:GetAlpha()
W.Update(0.15)
check("the border pulses", PFx.disp:GetAlpha() ~= a1)
-- in combat the data is locked: the client's own list of what you can dispel decides
S.auras.player = { { id = 803, harmful = true, icon = "d.blp", dispel = "Disease", name = "Plague", canDispel = true } }
S.secret = { auras = true }
W.Fire("UNIT_AURA", "player")
check("locked: the client colours the border (disease brown)", PFx.disp:IsShown() and near(W.vc(PFx.disp.border[1])[1], ns.Data.DISPEL_COLOR.Disease[1]) and W.vc(PFx.disp.border[1])[4] > 0.5)
S.auras.player = { { id = 804, harmful = true, icon = "p.blp", dispel = "Poison", name = "Poison" } }
W.Fire("UNIT_AURA", "player")
check("locked, nothing you can dispel: no border", not PFx.disp:IsShown() or W.vc(PFx.disp.border[1])[4] == 0)
S.secret = nil
S.auras.player = {}
W.Fire("UNIT_AURA", "player")
check("debuff gone: border gone", not PFx.disp:IsShown())
-- party members: the same highlights
S.group.n = 1
S.units.party1 = { name = "Pal", guid = "Player-1-7700", class = "PALADIN", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 8, wy = 0, hp = 2000, hpMax = 3000 }
S.auras.party1 = { { id = 805, harmful = true, icon = "m.blp", dispel = "Magic", name = "Hammer of Justice" } }
W.Fire("GROUP_ROSTER_UPDATE"); W.Update(0.25)
local pm1 = ns.Frames.partyMembers[1]
check("party member: dispel border (magic)", pm1.disp:IsShown() and near(W.vc(pm1.disp.border[1])[3], ns.Data.DISPEL_COLOR.Magic[3]))
W.Fire("UNIT_COMBAT", "party1", "WOUND", 0, 300, 1)
check("party member attacked: red highlight", pm1.hit:GetAlpha() == 1)
ns.P.frames.dispelGlow = false
W.Fire("UNIT_AURA", "party1")
check("dispel highlight switch off", not pm1.disp:IsShown())
ns.P.frames.dispelGlow = true
S.units.party1, S.group.n, S.auras.party1 = nil, 0, nil
S.units.player.class = "MAGE"
W.Fire("GROUP_ROSTER_UPDATE")
wipeContacts(C)
W.Update(3)

-- TRACKERS (3.7) --------------------------------------------------------------------
local TR = ns.Trackers
check("tracker defaults: on, empty, macros off", ns.P.trackers.enabled and #TR.Items() == 0 and not ns.P.trackers.mirror)
local cs, err0 = TR.Add("Gegenzauber", "cd")
check("add a cooldown by its German name", cs and cs.spell == 2139 and cs.name == "Gegenzauber", err0)
local bad, err1 = TR.Add("Feuerwerk", "cd")
check("unknown spell: refused with a reason", bad == nil and err1:find("Feuerwerk", 1, true))
check("add by spell ID too", TR.Resolve("172") == 172)
local csf = TR.icons[cs.id]
check("icon built with the spell's texture", csf and csf.icon:GetTexture() == "cs.blp")
-- ready: hidden; on cooldown: shown with the time left and a swipe
W.Update(0.25)
check("ready: cooldown icon hidden", not csf:IsShown())
S.cooldowns[2139] = { start = GetTime() - 4, duration = 24 }
W.Fire("SPELL_UPDATE_COOLDOWN"); W.Update(0.25)
check("on cooldown: shown", csf:IsShown(), csf:IsShown())
check("time left on it", csf.time:GetText() == "20", csf.time:GetText())
check("swipe from the client's numbers", csf.cd._cdDur == 24)
check("cooldown length learned", ns.P.trackers.learned[2139].cd == 24)
S.cooldowns[2139] = { start = GetTime(), duration = 1.5 }
W.Fire("SPELL_UPDATE_COOLDOWN")
check("global cooldown is not the spell's cooldown", not csf:IsShown())
cs.invert = true; TR.Changed()
check("inverted cooldown: shown while NOT on cooldown", csf:IsShown() and csf.time:GetText() == "")
S.cooldowns[2139] = { start = GetTime() - 1, duration = 24 }; TR.Changed()
check("inverted cooldown: hidden while on cooldown", not csf:IsShown())
check("labels: ON COOLDOWN / NOT ON COOLDOWN", TR.LabelFor(cs) == "NOT ON COOLDOWN" and TR.LabelFor({ kind = "cd" }) == "ON COOLDOWN")
cs.invert = false
cs.show = "always"; TR.Changed()
check("mode 'always': shown, dimmed on cooldown", csf:IsShown() and csf.icon._desat == true and csf:GetAlpha() < 0.6)
cs.show = "cd"; TR.Changed()
-- in combat the numbers are secret: your own cast and the learned length decide
S.me.combat = true
S.secret = { cooldowns = true }
S.cooldowns[2139] = nil
W.Fire("SPELL_UPDATE_COOLDOWN"); W.Update(30)
check("secret, not cast: hidden", not csf:IsShown())
W.Fire("UNIT_SPELLCAST_SENT", "player", "Stabby", "Cast-1", 2139)
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2139)
W.Update(0.25)
check("secret: shown from your cast, marked as estimated", csf:IsShown() and csf.mark:GetText() == "?" and csf.cd._cdDur == 24)
W.Update(24)
check("estimate ends with the learned cooldown", not csf:IsShown())
S.secret = nil
S.me.combat = false
-- per-icon look: size, opacity, importance border
cs.size, cs.alpha, cs.border = 48, 0.7, "red"
S.cooldowns[2139] = { start = GetTime(), duration = 24 }
TR.Changed()
check("size applied", csf._w == 48 and csf._h == 48)
check("opacity applied", near(csf:GetAlpha(), 0.7))
check("red importance border", csf.imp:IsShown() and W.vc(csf.imp.border[1])[1] == 1 and W.vc(csf.imp.border[1])[2] < 0.3)
cs.border = "none"; TR.Changed()
check("no border", not csf.imp:IsShown())
cs.when = "combat"; TR.Changed()
check("'in combat' icon hidden out of combat", not csf:IsShown())
cs.when = "always"; TR.Changed()

-- on target: your Corruption on an enemy. By default the icon shows while it IS
-- on the target; the first block tests the inverted "NOT on target" icon.
local cor = TR.Add("Verderbnis", "target")
local corf = TR.icons[cor.id]
check("new target icon: not inverted, labelled ON TARGET", cor.invert == false and TR.LabelFor(cor) == "ON TARGET")
cor.invert = true
S.units.target = { name = "Dummy", guid = "Player-2-8000", class = "WARRIOR", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 20 }
S.auras = S.auras or {}
S.auras.target = {}
W.Fire("PLAYER_TARGET_CHANGED")
check("enemy without your Corruption: icon shows", corf:IsShown())
S.auras.target = { { id = 901, harmful = true, name = "Verderbnis", spellId = 172, source = "player", duration = 18 } }
W.Fire("UNIT_AURA", "target")
check("your Corruption on it: hidden (9 s left, warn at 3)", not corf:IsShown())
check("aura duration learned", ns.P.trackers.learned[172].dur == 18)
cor.warn = 10; TR.Changed()
check("inside the warning window: shown with the time left", corf:IsShown() and corf.time:GetText() == "9.0", corf.time:GetText())
cor.warn = 3; TR.Changed()
S.auras.target = { { id = 902, harmful = true, name = "Verderbnis", spellId = 172, source = "party1", duration = 18 } }
W.Fire("UNIT_AURA", "target")
check("someone else's Corruption does not count (only yours)", corf:IsShown())
cor.anySource = true; TR.Changed()
check("...unless 'count it from anyone' is on", not corf:IsShown())
cor.anySource = false
S.auras.target = { { id = 903, harmful = true, name = "Verderbnis", spellId = 172, source = "player", duration = 18 } }
TR.Changed()
cor.invert = false; TR.Changed()
check("target icon (default): shown while your Corruption IS on it, with its time", corf:IsShown() and corf.time:GetText() == "9.0", corf.time:GetText())
S.auras.target = {}
W.Fire("UNIT_AURA", "target")
check("target icon (default): hidden when it is NOT on the target", not corf:IsShown())
cor.invert = true
S.auras.target = { { id = 903, harmful = true, name = "Verderbnis", spellId = 172, source = "player", duration = 18 } }
TR.Changed()
-- combat: auras locked; the last reading carries, then our own cast
S.me.combat = true
S.secret = { auras = true }
W.Fire("UNIT_AURA", "target")
check("locked: still up from the last reading", not corf:IsShown())
W.Update(9.5)
check("locked: last reading ran out, shown as believed missing", corf:IsShown() and corf.mark:GetText() == "?")
W.Fire("UNIT_SPELLCAST_SENT", "player", "Dummy", "Cast-2", 172)
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 172)
check("locked: your cast on it counts for the learned 18 s", not corf:IsShown())
W.Update(15.5)
check("locked: inside the warning window again, with '?'", corf:IsShown() and corf.mark:GetText() == "?" and corf.time:GetText() ~= "")
S.secret = nil
S.me.combat = false
S.units.target = { name = "Buddy", guid = "Player-1-8100", class = "PRIEST", level = 60, isPlayer = true, hostile = false, faction = "Alliance", dist = 10 }
S.auras.target = {}
W.Fire("PLAYER_TARGET_CHANGED")
check("friendly target with an 'enemies' icon: hidden", not corf:IsShown())
S.units.target = nil
W.Fire("PLAYER_TARGET_CHANGED")
check("no target: hidden", not corf:IsShown())

-- on me: Arcane Intellect, from anyone (inverted first: NOT on me)
local ai = TR.Add("Arkane Intelligenz", "self")
local aif = TR.icons[ai.id]
ai.invert = true
S.auras.player = {}
W.Update(0.25)
check("buff missing on you: icon shows", aif:IsShown())
S.auras.player = { { id = 904, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "party2", duration = 1800 } }
W.Fire("UNIT_AURA", "player")
check("buff on you (cast by someone else): hidden", not aif:IsShown())
ai.invert = false; TR.Changed()
check("self icon (default): shown while the buff IS on you", aif:IsShown() and aif.time:GetText() == "15m", aif.time:GetText())
S.auras.player = {}
W.Fire("UNIT_AURA", "player")
check("self icon (default): hidden while it is NOT on you", not aif:IsShown())
ai.invert = true; TR.Changed()

-- layout mode: all visible, labelled, draggable; dropping saves the spot
TR.SetEditing(true)
check("layout mode: every icon visible and labelled", csf:IsShown() and corf:IsShown() and aif:IsShown() and csf.label:IsShown())
UIParent._cx, UIParent._cy = 960, 540
csf._cx, csf._cy = 960 + 300, 540 - 120
csf._scripts.OnDragStop(csf)
check("drag and drop: position saved", cs.x == 300 and cs.y == -120, cs.x .. "," .. cs.y)
csf._scripts.OnMouseDown(csf)
check("click an icon to select it", TR.selected == cs.id)
TR.SetEditing(false)
check("layout mode off: back to its rules", not corf:IsShown() == (S.units.target == nil))

-- the console page
ns.Config.Open("trackers")
local TP = ns.Config._page and ns.Config._page("trackers")
check("trackers page opens", TP ~= nil and TP:IsShown())
TP.addBox.edit:SetText("Gegenzauber")
TP.addButtons.target._scripts.OnClick(TP.addButtons.target)
local last = TR.Items()[#TR.Items()]
check("add from the page", #TR.Items() == 4 and last.kind == "target" and TR.selected == last.id)
check("editor shows the aura settings for it (no early warning until inverted)", not TP.editor.warn:IsShown() and TP.editor.target:IsShown() and not TP.editor.show:IsShown())
TR.selected = cs.id; TP:Refresh()
check("a cooldown's editor shows its mode instead", TP.editor.show:IsShown() and not TP.editor.warn:IsShown())
check("invert toggle named for the kind", TP.editor.invert:IsShown() and W.has(TP.editor.invert.label:GetText(), "not on cooldown"))
TR.selected = last.id; TP:Refresh()
TP.editor.invert._scripts.OnClick(TP.editor.invert)
check("invert from the page: on, early-warning slider appears",
	last.invert == true and TP.editor.warn:IsShown())
local foundRow
for _, r in ipairs(TP.list.rows) do if r.itemId == last.id then foundRow = r end end
check("list row shows the inverted kind", foundRow and foundRow.kind:GetText():lower() == "not on tgt", foundRow and foundRow.kind:GetText())
TR.Remove(last.id)
check("remove", #TR.Items() == 3 and TR.icons[last.id] == nil)
ns.Config.Toggle()

-- keep the list in macros
local code = TR.Encode()
local back = TR.Decode(code)
check("encode/decode round trip", back and #back.items == 3 and back.items[1].spell == 2139 and back.items[1].x == 300 and back.items[2].warn == 3 and back.items[3].anySource == true)
local back2 = TR.Decode(TR.Encode())
check("invert survives the macro copy", back2.items[2].invert == cor.invert and back2.items[1].invert == false and back2.items[3].invert == ai.invert)
local old = TR.Decode("1|1|c,2139,0,0,36,100,n,0,a,r,0")
check("older lists: 'while ready' becomes NOT on cooldown", old.items[1].invert == true and old.items[1].show == "cd")
local old2 = TR.Decode("1|1|t,172,0,0,36,100,n,3,a,e,0;s,1459,0,0,36,100,n,0,a,y,1,1")
check("older lists: a 'missing' aura icon keeps showing while missing (now inverted)", old2.items[1].invert == true and old2.items[2].invert == false)
-- a profile from 3.7.0/3.7.1 (no schema): aura icons flipped once, cooldowns untouched
local saved = ns.P.trackers.items
ns.P.trackers.items = { { id = 900, kind = "target", spell = 172, x = 0, y = 0, size = 36, alpha = 1, border = "none", invert = false },
	{ id = 901, kind = "cd", spell = 2139, x = 0, y = 0, size = 36, alpha = 1, border = "none", invert = false } }
ns.P.trackers.schema = nil
TR.Migrate(); TR.Migrate()
check("old profile migrated once", ns.P.trackers.items[1].invert == true and ns.P.trackers.items[2].invert == false and ns.P.trackers.schema == 2)
ns.P.trackers.items = saved
TR.LayoutAll()
TR.SetMirror(true)
local mname = TR.MirrorName(1)
local mi = GetMacroIndexByName(mname)
check("macros on: one general macro written", mi > 0 and W.macros[mi].body:find("^/sitrep store 1/1 2|1|c,2139,"), W.macros[mi] and W.macros[mi].body)
check("macro name per character, short", #mname <= 16)
for i = 1, 30 do TR.Add("Gegenzauber", "cd") end
W.Update(1.5)
check("a long list spreads over several macros", GetMacroIndexByName(TR.MirrorName(2)) > 0)
-- "restart": settings gone, macros remain
local keepN = #TR.Items()
ns.P.trackers.items, ns.P.trackers.mirror = {}, false
TR.mirror.ready = false
TR.MirrorLogin(false)
check("restart: icons restored from the macros", #TR.Items() == keepN and ns.P.trackers.mirror == true, #TR.Items())
check("restored icons keep their place", TR.Items()[1].x == 300)
-- in combat a write waits
S.me.combat = true
TR.Items()[1].size = 40; TR.Changed()
W.Update(1.5)
check("in combat: the write waits", TR.mirror.note:find("combat", 1, true))
S.me.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
check("after combat: written", not TR.mirror.note:find("combat", 1, true))
TR.SetMirror(false)
check("macros off: removed", GetMacroIndexByName(TR.MirrorName(1)) == 0 and GetMacroIndexByName(TR.MirrorName(2)) == 0)
local np = #W.prints
SlashCmdList.SITREP("store 1/1 x")
check("clicking the macro explains itself", W.prints[#W.prints]:find("tracker icons", 1, true) and #W.prints == np + 1)
-- clean up
for _, it in ipairs(TR.Items()) do if TR.icons[it.id] then TR.icons[it.id]:Hide() end end
ns.P.trackers.items = {}
TR.LayoutAll()
S.cooldowns[2139] = nil
S.auras.player, S.auras.target = nil, nil
W.Update(0.25)

-- TRACKERS: weapon imbues and buffs with another name (3.8) -------------------------
local TR2 = ns.Trackers
S.auras = S.auras or {}
S.auras.player = {}
-- the case from the field: "Waffe der Flammenzunge" puts a buff called "Waffenzunge" on you
local ft = TR2.Add("Waffe der Flammenzunge", "self")
ft.invert = true; TR2.Changed()
local ftf = TR2.icons[ft.id]
check("NOT on me: shown while neither is there", ftf:IsShown())
S.auras.player = { { id = 950, harmful = false, name = "Waffenzunge", spellId = 319778, source = "player", duration = 1800 } }
W.Fire("UNIT_AURA", "player")
check("buff with another name: not recognised by the spell's name alone", ftf:IsShown())
ft.aura = "Waffenzunge"; TR2.Changed()
check("'look for this buff instead': recognised, hidden", not ftf:IsShown())
check("its ID is learned from the name", ft.auraId == 319778)
-- the weapon kind: read from the client's weapon-enchant data
local fw = TR2.Add("Waffe der Flammenzunge", "weapon")
fw.invert = true; TR2.Changed()
local fwf = TR2.icons[fw.id]
S.weapon = nil
W.Update(0.25)
check("NOT on weapon: shown without an imbue", fwf:IsShown())
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 8024)
S.weapon = { mh = { id = 5, ms = 1800000 } }
W.Update(0.25)
check("imbued: hidden", not fwf:IsShown())
check("the enchant it gives is learned from your cast", ns.P.trackers.learned[8024].enchant == 5 and ns.P.trackers.learned[8024].dur == 1800)
fw.invert = false; TR2.Changed()
check("ON weapon: shown with its time", fwf:IsShown() and fwf.time:GetText() == "30m", fwf.time:GetText())
S.weapon = { mh = { id = 7, ms = 600000 } } -- a different imbue (e.g. Windfury)
W.Update(0.25)
check("main hand: any imbue on it counts (no ID needed)", fwf:IsShown())
fw.hand = "either"; S.weapon = { mh = { id = 7, ms = 600000 }, oh = { id = 9, ms = 600000 } }; TR2.Changed()
check("both hands imbued with others: the learned ID tells them apart", not fwf:IsShown())
S.weapon = { mh = { id = 7, ms = 600000 }, oh = { id = 5, ms = 600000 } }; TR2.Changed()
check("...and finds yours on the off hand", fwf:IsShown())
fw.hand = "main"
S.weapon = { mh = { id = 5, ms = 600000 } }
fw.hand = "off"; TR2.Changed()
check("off hand only: the main hand's imbue does not count", not fwf:IsShown())
fw.hand = "either"; TR2.Changed()
check("either hand: counts", fwf:IsShown())
-- unreadable (combat): your cast and the learned length decide, marked "?"
S.me.combat = true
S.secret = { weapon = true, tooltip = true }
W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", 8024)
W.Update(0.25)
check("unreadable: estimated from your cast, '?'", fwf:IsShown() and fwf.mark:GetText() == "?")
S.secret = nil
S.me.combat = false
-- /sitrep buffs
local np2 = #W.prints
SlashCmdList.SITREP("buffs")
local out = table.concat(W.prints, "\n", np2 + 1)
check("/sitrep buffs lists names and IDs", out:find("Waffenzunge · 319778", 1, true), out)
check("/sitrep buffs lists the weapon enchant", out:find("main hand: enchant 5", 1, true), out)
-- the macro copy keeps the hand and the buff name (separators escaped)
ft.aura, ft.auraId = "Foo, Bar; Baz|Qux", nil
local rt = TR2.Decode(TR2.Encode())
local rft, rfw
for _, it in ipairs(rt.items) do
	if it.kind == "self" and it.spell == 8024 then rft = it end
	if it.kind == "weapon" then rfw = it end
end
check("macro copy keeps the buff name, separators and all", rft and rft.aura == "Foo, Bar; Baz|Qux", rft and rft.aura)
check("macro copy keeps the weapon hand", rfw and rfw.hand == "either")
ft.aura = "Waffenzunge"
-- the page: the weapon kind's editor, and the buff field
ns.Config.Open("trackers")
local TP2 = ns.Config._page("trackers")
check("page: '+ On weapon' button", TP2.addButtons.weapon ~= nil)
TR2.selected = fw.id; TP2:Refresh()
check("weapon icon: hand choice, and a tooltip-text field instead of the buff field", TP2.editor.hand:IsShown() and TP2.editor.aura:IsShown() and TP2.editor.aura.t:GetText():find("tooltip", 1, true))
TP2.editor.aura.box.edit:SetText("Flamm")
TP2.editor.aura.box.edit._scripts.OnTextChanged(TP2.editor.aura.box.edit, true)
check("weapon text field: no spell suggestions", not TP2.editor.aura.box.suggest:IsShown())
TR2.selected = ft.id; TP2:Refresh()
check("self icon: buff field with its name", TP2.editor.aura:IsShown() and TP2.editor.aura.box.edit:GetText() == "Waffenzunge")
TP2.editor.aura.box.edit:SetText("319778")
TP2.editor.aura.box.edit._scripts.OnEnterPressed(TP2.editor.aura.box.edit)
check("typing an ID in the buff field", ft.auraId == 319778 and ft.aura == nil)
ns.Config.Toggle()
for _, it in ipairs(TR2.Items()) do if TR2.icons[it.id] then TR2.icons[it.id]:Hide() end end
ns.P.trackers.items = {}
TR2.LayoutAll()
S.weapon, S.auras.player = nil, nil
W.Update(0.25)

-- WEAPON IMBUES: the weapon's tooltip as a second source (3.9.3) ------------------
do
	local TR3 = ns.Trackers
	local w = TR3.Add("Waffe der Flammenzunge", "weapon")
	local wf = TR3.icons[w.id]
	-- the enchant info says nothing, but the tooltip shows the imbue
	S.weapon = nil
	S.weaponTip = { [16] = { "Krummsäbel", "Schaden: 20 - 40", "Flammenzunge 3 (29 Min.)", "Haltbarkeit 50 / 50" } }
	W.Update(0.25)
	check("tooltip fallback: the imbue is found on the weapon's tooltip", wf:IsShown() and wf.time:GetText() == "29m", wf.time:GetText())
	local _, _, src = TR3.WeaponState(w, GetTime())
	check("...and says where it came from", src == "tooltip")
	S.weaponTip = { [16] = { "Krummsäbel", "Flametongue 3 (45 sec)" } }
	W.Update(0.25)
	check("English tooltips and seconds", wf.time:GetText() == "45", wf.time:GetText())
	S.weaponTip = { [16] = { "Krummsäbel", "Flammenzunge 3 (1 Std.)" } }
	check("German hours", TR3.TooltipEnchant(16).exp == 3600)
	-- only a matching line when a text is given
	S.weaponTip = { [16] = { "Krummsäbel", "Windzorn 2 (20 Min.)" } }
	w.aura = "Flammenzunge"; TR3.Changed()
	check("with a text: another imbue's line does not count", not wf:IsShown())
	S.weaponTip = { [16] = { "Krummsäbel", "Flammenzunge 2 (20 Min.)" } }
	W.Update(0.25)
	check("with a text: the matching line counts", wf:IsShown())
	w.aura = nil
	-- nothing anywhere: NOT on weapon
	S.weaponTip = { [16] = { "Krummsäbel" } }
	w.invert = true; TR3.Changed()
	check("no imbue anywhere: NOT on weapon shows", wf:IsShown() and wf.mark:GetText() == "")
	-- /sitrep weapon prints the raw data
	S.weapon = { mh = { id = 5, ms = 1740000 } }
	S.weaponTip = { [16] = { "Krummsäbel", "Flammenzunge 3 (29 Min.)" } }
	local np3 = #W.prints
	SlashCmdList.SITREP("weapon")
	local out3 = table.concat(W.prints, "\n", np3 + 1)
	check("/sitrep weapon: raw enchant info", out3:find("main hand true, 1740000 ms", 1, true) and out3:find("enchant 5", 1, true), out3)
	check("/sitrep weapon: the tooltip's timer line", out3:find("\"Flammenzunge 3 (29 Min.)\"", 1, true), out3)
	check("/sitrep weapon: each weapon tracker's verdict", out3:find("tracker Waffe der Flammenzunge (main hand): ON", 1, true) and out3:find("via enchant info", 1, true), out3)
	S.secret = { weapon = true }
	np3 = #W.prints
	SlashCmdList.SITREP("weapon")
	check("/sitrep weapon marks secret values", table.concat(W.prints, "\n", np3 + 1):find("<secret>", 1, true))
	S.secret = nil
	TR3.Remove(w.id)
	S.weapon, S.weaponTip = nil, nil
end

-- SPELL LIBRARY: searchable fields (3.9) --------------------------------------------
do
local LB = ns.Trackers.Lib
local r1 = LB.Search("Frost")
local names = {}
for _, e in ipairs(r1) do names[#names + 1] = e.name .. "/" .. e.src end
check("spellbook search: Frostbolt and Frost Nova from your book", #r1 >= 2 and r1[1].src == "BOOK" and table.concat(names, ","):find("Frostbolt/BOOK", 1, true) and table.concat(names, ","):find("Frost Nova/BOOK", 1, true), table.concat(names, ","))
check("one letter: no suggestions yet", #LB.Search("F") == 0)
local r2 = LB.Search("8024")
check("an ID finds its spell, with its rank", r2[1] and r2[1].id == 8024 and r2[1].name == "Waffe der Flammenzunge" and r2[1].sub == "Rang 1" and r2[1].src == "ID")
check("'Name (ID)' is understood", LB.IdIn("Waffe der Flammenzunge (8024)") == 8024 and ns.Trackers.Resolve("Waffe der Flammenzunge (8024)") == 8024)
S.auras = S.auras or {}
S.auras.player = { { id = 960, harmful = false, name = "Waffenzunge", spellId = 319778, source = "player", duration = 1800 } }
local r3 = LB.Search("waffenz", { auras = true })
check("buffs on you are found by their exact name (case-insensitive)", r3[1] and r3[1].id == 319778 and r3[1].src == "ON YOU", r3[1] and (r3[1].name .. "/" .. r3[1].src))
check("buffs read once are remembered as SEEN", LB.seen[319778] == "Waffenzunge")
S.auras.player = {}
local r4 = LB.Search("waffenz", { auras = true })
check("...and still suggested after they are gone", r4[1] and r4[1].id == 319778 and r4[1].src == "SEEN")
-- every spell the client knows, in the background
local savedMax, savedStep = LB.DEEP_MAX, LB.DEEP_STEP
LB.DEEP_MAX, LB.DEEP_STEP = 350000, 50000
local deepRes, deepFrac, deepDone
check("full search needs 3 letters", LB.Deep("zu", function() end) == false)
LB.Deep("zunge", function(res, frac, done) deepRes, deepFrac, deepDone = res, frac, done end)
W.Update(0.02)
check("full search runs in steps (no freeze)", deepFrac and deepFrac < 1 and not deepDone, deepFrac)
for _ = 1, 10 do W.Update(0.02) end
local found = {}
for _, e in ipairs(deepRes or {}) do found[e.id] = e.src end
check("full search finds both 'zunge' spells", deepDone and found[8024] == "ALL" and found[319778] == "ALL")
-- the page: type, see suggestions, pick, add
ns.Config.Open("trackers")
local TP3 = ns.Config._page("trackers")
local eb = TP3.addBox.edit
eb:SetText("Waffe der Flammenzunge")
eb._scripts.OnTextChanged(eb, true)
local pop = TP3.addBox.suggest
check("typing shows suggestions", pop:IsShown() and pop.rows[1]:IsShown() and pop.rows[1].meta:GetText():find("8024", 1, true), pop.rows[1] and pop.rows[1].meta:GetText())
check("suggestion shows the rank", pop.rows[1].name:GetText():find("Rang 1", 1, true))
check("last line offers the full search", pop.rows[2] and pop.rows[2].name:GetText():find("search all spells", 1, true))
pop.rows[1]._scripts.OnClick(pop.rows[1])
check("picking fills 'Name (ID)'", eb:GetText() == "Waffe der Flammenzunge (8024)" and not pop:IsShown(), eb:GetText())
TP3.addButtons.weapon._scripts.OnClick(TP3.addButtons.weapon)
local lastIt = ns.Trackers.Items()[#ns.Trackers.Items()]
check("then '+ On weapon' adds exactly that spell", lastIt.spell == 8024 and lastIt.kind == "weapon")
-- keyboard: arrows and Enter
eb:SetText("Frost")
eb._scripts.OnTextChanged(eb, true)
eb._scripts.OnArrowPressed(eb, "DOWN")
eb._scripts.OnEnterPressed(eb)
check("arrow down + Enter picks the second match", eb:GetText():find("Frost Nova", 1, true) or eb:GetText():find("Frostbolt", 1, true), eb:GetText())
-- the full search from the popup
eb:SetText("zunge")
eb._scripts.OnTextChanged(eb, true)
local n0 = 0
for _, r in ipairs(pop.rows) do if r:IsShown() then n0 = n0 + 1 end end
local deepRow = pop.rows[n0]
deepRow._scripts.OnClick(deepRow)
for _ = 1, 10 do W.Update(0.02) end
local lastShown
for _, r in ipairs(pop.rows) do if r:IsShown() then lastShown = r end end
check("popup: full search results with a summary line", lastShown.name:GetText():find("all spells searched", 1, true), lastShown.name:GetText())
-- the buff field: buffs first
ns.Trackers.selected = nil
local me2 = ns.Trackers.Add("Waffe der Flammenzunge", "self")
TP3:Refresh()
S.auras.player = { { id = 961, harmful = false, name = "Waffenzunge", spellId = 319778, source = "player", duration = 1800 } }
local ab = TP3.editor.aura.box
ab.edit:SetText("Waffenz")
ab.edit._scripts.OnTextChanged(ab.edit, true)
check("buff field suggests the buff on you first", W.has(ab.suggest.rows[1].meta:GetText(), "ON YOU"), ab.suggest.rows[1].meta:GetText())
ab.suggest.rows[1]._scripts.OnClick(ab.suggest.rows[1])
check("picking sets the buff by name and ID", me2.aura == "Waffenzunge" and me2.auraId == 319778)
TP3:Refresh()
check("the field shows 'Name (ID)'", ab.edit:GetText() == "Waffenzunge (319778)", ab.edit:GetText())
ns.Config.Toggle()
LB.DEEP_MAX, LB.DEEP_STEP = savedMax, savedStep
for _, it in ipairs(ns.Trackers.Items()) do if ns.Trackers.icons[it.id] then ns.Trackers.icons[it.id]:Hide() end end
ns.P.trackers.items = {}
ns.Trackers.LayoutAll()
S.auras.player = nil
W.Update(0.25)

end

-- SUGGESTIONS SCROLL (3.9.1) -------------------------------------------------------
do
	local many = {}
	for i = 1, 28 do many[i] = { id = 10000 + i, name = "Flammenzunge " .. i, icon = "x.blp", src = "ALL" } end
	local box = ns.Kit.EditBox(UIParent, 260, 24)
	local picked
	local sp = ns.Kit.Suggest(box, function() return many end, function(it) picked = it end, nil)
	box.edit:SetText("Flammenzunge")
	box.edit._scripts.OnTextChanged(box.edit, true)
	local function visible() local n = 0 for _, r in ipairs(sp.rows) do if r:IsShown() and r.item then n = n + 1 end end return n end
	check("28 matches: 8 rows at a time", visible() == 8 and sp.rows[1].item.id == 10001)
	check("summary line says how many and which", sp.rows[9]:IsShown() and sp.rows[9].name:GetText():find("28 found", 1, true) and sp.rows[9].name:GetText():find("1-8", 1, true), sp.rows[9].name:GetText())
	check("scrollbar shown", sp.thumb:IsShown() and sp.track:IsShown())
	sp._scripts.OnMouseWheel(sp, -1)
	check("mouse wheel scrolls down one", sp.rows[1].item.id == 10002 and sp.rows[9].name:GetText():find("2-9", 1, true))
	sp.rows[3]._scripts.OnMouseWheel(sp.rows[3], -1)
	check("...also over a row", sp.rows[1].item.id == 10003)
	for _ = 1, 40 do sp._scripts.OnMouseWheel(sp, -1) end
	check("stops at the last match", sp.rows[8].item.id == 10028 and sp.rows[1].item.id == 10021)
	for _ = 1, 40 do sp._scripts.OnMouseWheel(sp, 1) end
	check("back to the top", sp.rows[1].item.id == 10001)
	for _ = 1, 9 do box.edit._scripts.OnArrowPressed(box.edit, "DOWN") end
	check("arrow keys scroll along with the highlight", sp.hi == 10 and sp.rows[8].item.id == 10010 and sp.rows[8].hl:IsShown())
	sp.rows[8]._scripts.OnClick(sp.rows[8])
	check("clicking a scrolled row picks that match", picked and picked.id == 10010 and box.edit:GetText() == "Flammenzunge 10 (10010)")
	box.edit:SetText("Flammenzunge")
	box.edit._scripts.OnTextChanged(box.edit, true)
	for _ = 1, 27 do box.edit._scripts.OnArrowPressed(box.edit, "DOWN") end
	box.edit._scripts.OnEnterPressed(box.edit)
	check("Enter picks the 28th", picked.id == 10028)
	box.edit:SetText("Flammenzunge")
	box.edit._scripts.OnTextChanged(box.edit, true)
	many[3].name = "Waffe der Flammenzunge mit einem sehr langen Namen"
	many[3].id = 8024
	sp.rows[3]._scripts.OnEnter(sp.rows[3])
	check("hover: the spell's own tooltip with its full name", GameTooltip.spell == 8024 and GameTooltip:Text():find("Waffe der Flammenzunge", 1, true))
	check("hover: ID and source under it", GameTooltip:Text():find("ID 8024", 1, true) and GameTooltip:Text():find("ALL", 1, true), GameTooltip:Text())
	check("hover also highlights the row", sp.hi == 3)
	sp.rows[3]._scripts.OnLeave(sp.rows[3])
	many = { many[1], many[2] }
	box.edit._scripts.OnTextChanged(box.edit, true)
	check("few matches: no scrollbar", not sp.thumb:IsShown())
	-- the icon list in the console: full name on hover too
	local li = ns.Trackers.Add("Waffe der Flammenzunge", "self")
	li.aura, li.auraId = "Waffenzunge", 319778
	ns.Config.Open("trackers")
	local LP = ns.Config._page("trackers")
	LP:Refresh()
	local lrow
	for _, r in ipairs(LP.list.rows) do if r.itemId == li.id then lrow = r end end
	lrow._scripts.OnEnter(lrow)
	check("icon list: full name, kind and watched buff on hover", GameTooltip.spell == 8024 and GameTooltip:Text():find("ON ME", 1, true) and GameTooltip:Text():find("Waffenzunge (319778)", 1, true), GameTooltip:Text())
	ns.Config.Toggle()
	ns.Trackers.Remove(li.id)
end

-- COST PREVIEW on the power bar (3.10) ----------------------------------------------
do
	local PF2 = ns.Frames.frames.player
	local me = S.units.player
	me.power, me.powerMax, me.powerType = 500, 1000, 0
	W.Update(0.25)
	check("nothing hovered: no cost shown", not PF2.cost:IsShown())
	-- hover Frostbolt (120 mana) on the action bar
	S.actions = { [1] = { "spell", 116 } }
	GameTooltip:SetAction(1); GameTooltip:Show()
	check("hovering a spell: its cost lit on the power bar", PF2.cost:IsShown() and PF2.cost._value == 120 and PF2.cost._max == 1000)
	check("enough mana: lighter blue", PF2.cost._sbColor[3] == 1 and PF2.cost._sbColor[1] < 0.7 and not PF2.costIsShort)
	GameTooltip:Hide()
	check("tooltip gone: cost gone", not PF2.cost:IsShown())
	-- not enough mana: red, with the missing part past the bar
	me.power = 80
	GameTooltip:SetSpellByID(116); GameTooltip:Show()
	check("not enough mana: red", PF2.cost:IsShown() and PF2.cost._sbColor[1] == 1 and PF2.cost._sbColor[2] < 0.3 and PF2.costIsShort)
	check("the missing 40 shown past the end", PF2.costShort:IsShown() and PF2.costShort._value == 40)
	GameTooltip:Hide()
	-- while casting it, the cost stays lit
	me.power = 500
	me.casting, me.castSpell, me.castName, me.castStart, me.castEnd = true, 116, "Frostbolt", GetTime() * 1000, GetTime() * 1000 + 2500
	W.Fire("UNIT_SPELLCAST_START", "player")
	check("casting: cost shown", PF2.cost:IsShown() and PF2.costSpell == 116)
	me.casting = nil
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-20", 116)
	check("cast done: cost gone", not PF2.cost:IsShown())
	-- your power secret in combat: the client says whether it is enough
	S.secret = { power = true }
	local realPower = UnitPower
	UnitPower = function(u) if u == "player" then return W.Secret() end return realPower(u) end
	me.power = 50
	GameTooltip:SetSpellByID(116); GameTooltip:Show()
	check("secret power: still red when the client says it is not enough", PF2.cost:IsShown() and PF2.costIsShort == true and not PF2.costShort:IsShown())
	GameTooltip:Hide()
	UnitPower = realPower
	S.secret = nil
	-- a spell with no cost, or switched off
	GameTooltip:SetSpellByID(2139); GameTooltip:Show()
	check("a spell without a mana cost: nothing", not PF2.cost:IsShown())
	GameTooltip:Hide()
	ns.P.frames.costPreview = false
	GameTooltip:SetSpellByID(116); GameTooltip:Show()
	check("switched off: nothing", not PF2.cost:IsShown())
	GameTooltip:Hide()
	ns.P.frames.costPreview = true
	me.power, me.powerMax, S.actions = nil, nil, nil
end

-- Every console page fits inside the window (no widget past the bottom).
do
	ns.Config.Open("overview")
	local CONTENT_H = 560 - 64 - 40
	for _, id in ipairs({ "overview", "sensors", "threat", "matrix", "engage", "pressure", "comms", "alerts", "display", "layout", "frames", "plates", "interface", "quests", "bars", "log", "trackers" }) do
		ns.Config._open(id)
		local pg = ns.Config._page(id)
		check("console page holds what is on it (taller: it scrolls): " .. id, pg and pg:GetHeight() >= math.max(pg.y[1], pg.y[2]) and pg.scroller,
			pg and (pg.y[1] .. " / " .. pg.y[2] .. " in " .. pg:GetHeight()))
	end
	;(function()
		ns.Config._open("plates")
		local pg = ns.Config._page("plates")
		local sf = pg.scroller
		sf._h = CONTENT_H
		pg:SetHeight(CONTENT_H + 200)
		pg:ScrollTo(0)
		check("a tall page: shown through its scroll frame, at the top", sf:IsShown() and pg:IsShown() and sf._scrollChild == pg and pg:Scroll() == 0)
		sf:GetScript("OnMouseWheel")(sf, -1)
		check("the wheel scrolls down", pg:Scroll() == 48, pg:Scroll())
		for _ = 1, 10 do sf:GetScript("OnMouseWheel")(sf, -1) end
		check("...not past the end", pg:Scroll() == 200, pg:Scroll())
		for _ = 1, 10 do sf:GetScript("OnMouseWheel")(sf, 1) end
		check("...nor above the top", pg:Scroll() == 0)
		ns.Config._open("overview")
		check("another page: this one hidden with its scroll frame", not sf:IsShown() and not pg:IsShown())
		pg:Grow()
	end)()
	ns.Config.Toggle()
end

-- TARGET'S TARGET HEALTH (3.11) ---------------------------------------------------
do
	local TFt = ns.Frames.frames.target
	local healer = { name = "Heilchen", guid = "Player-2-9100", class = "PRIEST", level = 60, isPlayer = true, hostile = true,
		faction = "Horde", hp = 1200, hpMax = 3000, dist = 30 }
	S.units.target = { name = "Brute", guid = "Player-2-9000", class = "WARRIOR", level = 60, isPlayer = true, hostile = true,
		faction = "Horde", dist = 10, hp = 4000, hpMax = 4000, targetOf = healer }
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
	check("its target's name shown", TFt.tot:GetText():find("Heilchen", 1, true), TFt.tot:GetText())
	check("its target's health: a slim bar", TFt.totHp:IsShown() and TFt.totHp._value == 1200 and TFt.totHp._max == 3000)
	check("the bar keeps the usual dark background", TFt.totHp.bg._vc and W.vc(TFt.totHp.bg)[2] < 0.2)
	check("a faint green track on its own layer (solid colour with low alpha)", TFt.totHp.track._color and TFt.totHp.track._color[2] > 0.8 and near(TFt.totHp.track._color[4], 0.16))
	local np4 = #W.prints
	SlashCmdList.SITREP("tot")
	local o4 = table.concat(W.prints, "\n", np4 + 1)
	check("/sitrep tot reports each layer", o4:find("background:", 1, true) and o4:find("green track:", 1, true) and o4:find("values: 1200", 1, true), o4)
	check("coloured by health: red below 50 %", near(TFt.totHp._sbColor[1], ns.Units.HP_COLORS.red[1]) and TFt.totHp._sbColor[2] < 0.5)
	healer.hp = 2900
	W.Update(0.25)
	check("updates: green above 75 %", TFt.totHp._value == 2900 and TFt.totHp._sbColor[2] > 0.8)
	S.secret = { health = true }
	W.Update(0.25)
	check("secret health: the bar still draws", TFt.totHp:IsShown())
	S.secret = nil
	-- the field case: your target channels in combat, its "not interruptible" flag secret
	local errs0 = 0
	for _, n in pairs(ns.errorCounts) do errs0 = errs0 + n end
	local tc = GetTime() * 1000
	S.units.target.channeling, S.units.target.castStart, S.units.target.castEnd = true, tc, tc + 3000
	S.secret = { cast = true }
	healer.hp = 900
	W.Fire("UNIT_SPELLCAST_CHANNEL_START", "target")
	W.Update(0.25)
	local errs1 = 0
	for _, n in pairs(ns.errorCounts) do errs1 = errs1 + n end
	check("a channel with a secret flag: no error", errs1 == errs0, errs1 - errs0)
	-- The emulator cannot refuse a true/false test on a secret (to Lua it is a table),
	-- so guard the source: the cast's raw flags are never tested with and / or / not / if.
	local src = io.open("SITREP/UI/Frames.lua"):read("*a")
	local bad = {}
	for line in src:gmatch("[^\n]+") do
		if not line:match("^%s*%-%-") and (line:match("[%w_]+%s+and%s+r[78]%f[%W]") or line:match("%f[%w]r[78]%s+or%f[%W]")
			or line:match("not%s+r[78]%f[%W]") or line:match("if%s+r[78]%f[%W]")) then bad[#bad + 1] = line end
	end
	check("no true/false test on the cast's raw flags (secret in combat)", #bad == 0, table.concat(bad, " | "))
	check("...the cast bar shows it", TFt.cast:IsShown())
	check("...and the rest of the frame keeps updating (its target's bar follows)", TFt.totHp._value == 900, TFt.totHp._value)
	S.secret = nil
	S.units.target.channeling = nil
	W.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
	S.units.target.targetOf = nil
	W.Update(0.25)
	check("no target of its own: no bar", not TFt.totHp:IsShown())
	S.units.target.targetOf = healer
	ns.P.frames.totHealth = false
	W.Update(0.25)
	check("switched off: no bar", not TFt.totHp:IsShown())
	ns.P.frames.totHealth = true
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
	check("no target: no bar", not TFt.totHp:IsShown())
	wipeContacts(C)
end

-- BUFFS IN COMBAT: learned yes/no questions (3.12) -----------------------------------
do
	local TRc = ns.Trackers
	local O = TRc.Oracle
	S.auras = S.auras or {}
	-- out of combat: Arcane Intellect on you, plus a buff that then ends
	S.auras.player = { { id = 971, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "party2", duration = 1800 },
		{ id = 972, harmful = false, name = "Kurzer Buff", spellId = 5555, source = "player", duration = 10 } }
	local ai = TRc.Add("Arkane Intelligenz", "self")
	ai.invert = true; TRc.Changed()               -- "NOT on me"
	local aif = TRc.icons[ai.id]
	W.Update(1.1)
	table.remove(S.auras.player, 2)                -- the short buff ends: an instance seen vanish
	W.Update(1.1); W.Update(1.1)
	check("out of combat: checks learned", O.calibratedAt ~= nil)
	check("learned: 'filtered out' tells there from gone", O.probes.filtered.ok and O.probes.filtered.present == "false" and O.probes.filtered.absent == "true")
	check("learned: the duration object tells them apart", O.probes.duration.ok and O.probes.duration.present == "some" and O.probes.duration.absent == "nil")
	check("rejected: a question that answers the same both ways", not O.probes.secrecy.ok)
	check("used an instance that really ended", O.retired[#O.retired] == 972)
	check("buff on you: NOT-on-me icon hidden", not aif:IsShown())
	-- the fight: every aura list and every aura's data refused
	S.me.combat = true
	S.secret = { auras = true, auraList = true }
	W.Update(0.25)
	check("combat, buff still on: hidden, and exact (no '?')", not aif:IsShown() and aif.mark:GetText() == "")
	-- an enemy priest dispels it
	S.auras.player = {}
	W.Fire("UNIT_AURA", "player")
	check("dispelled mid-fight: the icon fires at once", aif:IsShown())
	check("...exactly, not as a guess (no '?')", aif.mark:GetText() == "", aif.mark:GetText())
	-- you rebuff yourself in combat: estimated from your cast (the new instance is unknown)
	ns.P.trackers.learned[1459] = { dur = 1800 }
	W.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-30", 1459)
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-30", 1459)
	check("recast in combat: hidden again (estimated)", not aif:IsShown())
	S.secret = nil
	S.me.combat = false
	-- a client whose questions all go silent in combat: back to the estimate
	S.auras.player = { { id = 973, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 1800 } }
	W.Update(1.1)
	O.calibratedAt = nil
	W.Update(1.1)
	-- a client that answers only SECRETLY in combat: the client itself shows or hides the icon
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracle = true }
	W.Update(0.25)
	check("secret answer: kept, the client decides", not O.probes.filtered.combatBad and O.probes.filtered.combatAnswer == "secret" and aif.clientDecides)
	check("buff still there: the client hides the icon (opacity 0)", aif:IsShown() and aif:GetAlpha() == 0, aif:GetAlpha())
	S.auras.player = {}
	W.Fire("UNIT_AURA", "player")
	check("dispelled: the client shows it (full opacity)", aif:IsShown() and aif:GetAlpha() == ai.alpha, aif:GetAlpha())
	check("...without a '?'", aif.mark:GetText() == "")
	check("the console says the client decides", ns.Trackers.CombatHow(ai):find("by the client itself", 1, true), ns.Trackers.CombatHow(ai))
	S.secret = nil
	S.me.combat = false
	-- a client that answers nothing at all in combat: estimated, marked "?"
	S.auras.player = { { id = 975, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 1800 } }
	W.Update(1.1)
	O.calibratedAt = nil
	W.Update(1.1)
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracle = true, oracleErr = true }
	W.Update(30)
	check("no question answers in combat: estimated, marked '?'", (not aif:IsShown()) or aif.mark:GetText() == "?")
	check("...and the questions are dropped", O.probes.filtered.combatBad and O.probes.duration.combatBad)
	S.secret = nil
	S.me.combat = false
	-- buffs the client never hides: read directly, also in combat
	S.neverSecret = { [1459] = true }
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracle = true }
	S.auras.player = {}
	W.Update(0.25)
	check("never-hidden buff gone in combat: exact", aif:IsShown() and aif.mark:GetText() == "")
	S.auras.player = { { id = 974, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "party3", duration = 1800 } }
	W.Update(0.25)
	check("never-hidden buff back (from someone else): exact", not aif:IsShown())
	check("the console explains it (proven in this fight)", TRc.CombatHow(ai):find("the client answered", 1, true), TRc.CombatHow(ai))
	check("...and the report keeps what the spell answered in combat", O.direct[1459] and O.direct[1459].secret == "false" and O.direct[1459].read == "aura" and O.direct[1459].worked)
	S.secret, S.neverSecret = nil, nil
	S.me.combat = false
	W.Update(1.1)
	local np5 = #W.prints
	SlashCmdList.SITREP("auraprobe")
	local o5 = table.concat(W.prints, "\n", np5 + 1)
	check("/sitrep auraprobe lists the questions and verdicts", o5:find("IsAuraFilteredOutByInstanceID", 1, true) and o5:find("usable", 1, true), o5)
	local rep = SITREP_DB.reports and SITREP_DB.reports.auraprobe
	local repText = rep and table.concat(rep.lines, "\n") or ""
	check("...and keeps it for the disk (game chat cannot be copied)", rep and #rep.lines >= 5 and repText:find("IsAuraFilteredOutByInstanceID", 1, true) and not repText:find("|c", 1, true), repText)
	-- after a fight it is kept automatically, with each icon's combat mode
	S.me.combat = true; W.Update(0.25)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	local auto = SITREP_DB.reports.auraprobe_after_combat
	local autoText = auto and table.concat(auto.lines, "\n") or ""
	check("after combat: the checks are saved without a command", autoText:find("in combat it answered", 1, true) and autoText:find("Arkane Intelligenz (NOT ON ME)", 1, true), autoText)
	check("after combat: a timeline of the fight", autoText:find("timeline of the fight", 1, true), autoText)
	TRc.Remove(ai.id)
	S.auras.player = nil
	W.Update(0.25)
end

-- BUFFS IN COMBAT: spell lookups, refused while there, nil once gone (3.12.4) ------
do
	local TRl = ns.Trackers
	local O = TRl.Oracle
	ns.P.trackers.trust = {}
	S.auras = S.auras or {}
	S.auras.player = { { id = 990, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600 } }
	local ls = TRl.Add("Arkane Intelligenz", "self")
	ls.invert = true; TRl.Changed()
	local lsf = TRl.icons[ls.id]
	W.Update(1.1)
	-- the fight: lists, data and instance questions all refused (as on Forever)
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracleErr = true, oracle = true }
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Update(0.25)
	check("in combat, buff there: lookups refused, icon hidden", not lsf:IsShown() and O.fight[ls.id] and O.fight[ls.id].refused.GetPlayerAuraBySpellID)
	check("a refused lookup is trusted from now on", ns.P.trackers.trust.GetPlayerAuraBySpellID == true)
	-- its charges are used up: the buff drops mid-fight
	S.auras.player = {}
	W.Fire("UNIT_AURA", "player")
	check("buff gone mid-fight: refused -> plain nil, the icon fires", lsf:IsShown(), TRl.how[ls.id])
	check("...decided by the lookups", TRl.how[ls.id] == "spell lookup (gone)", TRl.how[ls.id])
	-- recast in the fight: refused again -> there
	S.auras.player = { { id = 991, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600 } }
	W.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-40", 1459)
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-40", 1459)
	W.Update(0.25)
	check("recast in the fight: hidden again", not lsf:IsShown())
	S.me.combat = false
	S.secret = nil
	W.Fire("PLAYER_REGEN_ENABLED")
	local tl = table.concat(SITREP_DB.reports.auraprobe_after_combat.lines, "\n")
	check("the timeline logs each lookup's answers", tl:find("lookups: GetPlayerAuraBySpellID=err", 1, true) and tl:find("GetPlayerAuraBySpellID=nil", 1, true), tl)
	check("the timeline logs the icon firing", tl:find("(NOT ON ME): SHOWN  via spell lookup (gone)", 1, true), tl)
	-- a client whose lookups refuse everything: no false alarm, the estimate stays
	ns.P.trackers.trust = {}
	W.Update(1.1)
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracleErr = true, oracle = true, lookupsErr = true }
	W.Fire("PLAYER_REGEN_DISABLED")
	S.auras.player = {}
	W.Fire("UNIT_AURA", "player")
	check("lookups that always refuse: no false alarm (estimate)", TRl.how[ls.id] == "estimate", TRl.how[ls.id])
	S.me.combat = false
	S.secret = nil
	W.Fire("PLAYER_REGEN_ENABLED")
	TRl.Remove(ls.id)
	S.auras.player = nil
	ns.P.trackers.trust = {}
	W.Update(0.25)
end

-- BUFFS IN COMBAT: Blizzard's own buff icons (3.12.5) -------------------------------
do
	local TRb = ns.Trackers
	BuffFrame = W.buffBar -- Blizzard's buff bar, as on Forever
	ns.P.trackers.trust = {}
	S.auras = S.auras or {}
	S.auras.player = { { id = 995, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600, icon = "ai_buff.blp" } }
	local bb = TRb.Add("Arkane Intelligenz", "self")
	bb.invert = true; TRb.Changed()
	local bbf = TRb.icons[bb.id]
	W.Update(1.1)
	check("out of combat: the aura's own icon is learned", ns.P.trackers.learned[1459].auraIcon == "ai_buff.blp")
	check("out of combat: Blizzard's bar shows that icon (verified)", ns.P.trackers.learned[1459].barOk == true)
	-- Forever in combat: every aura call refused, the spell lookups say nil regardless
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracleErr = true, oracle = true, lookupsNil = true }
	ns.P.trackers.trust = {}
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Update(0.25)
	check("in combat, buff there: found on Blizzard's buff bar, icon hidden", not bbf:IsShown() and TRb.how[bb.id] == "Blizzard's icons", TRb.how[bb.id])
	S.auras.player = {} -- the shield's charges are used up
	W.Fire("UNIT_AURA", "player")
	check("buff gone mid-fight: gone from the bar, the icon fires", bbf:IsShown() and TRb.how[bb.id] == "Blizzard's icons (gone)", TRb.how[bb.id])
	check("...exactly (no '?')", bbf.mark:GetText() == "")
	-- another button redrawn (secret), yours still readable: still exact
	S.auras.player = { { id = 998, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600, icon = "ai_buff.blp" },
		{ id = 999, harmful = false, name = "Proc", spellId = 7777, source = "player", duration = 10, icon = "proc.blp" } }
	local realGet2 = W.buffBar.GetChildren
	W.buffBar.GetChildren = function()
		local a = CreateFrame("Button"); a.Icon = a:CreateTexture(); a.Icon.GetTextureFileID = function() return "ai_buff.blp" end
		local b = CreateFrame("Button"); b.Icon = b:CreateTexture(); b.Icon.GetTextureFileID = function() return W.Secret() end
		return a, b
	end
	W.Update(0.25)
	check("one other button secret, yours readable: still exact", not bbf:IsShown() and TRb.how[bb.id] == "Blizzard's icons", TRb.how[bb.id])
	W.buffBar.GetChildren = realGet2
	-- Blizzard's icons secret too: no guess, the estimate stays
	S.auras.player = { { id = 996, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600, icon = "ai_buff.blp" } }
	S.secret.buffbar = true
	W.Update(0.25)
	check("Blizzard's icons secret: back to the estimate", TRb.how[bb.id] == "estimate", TRb.how[bb.id])
	S.me.combat = false
	S.secret = nil
	W.Fire("PLAYER_REGEN_ENABLED")
	local tlb = table.concat(SITREP_DB.reports.auraprobe_after_combat.lines, "\n")
	check("the timeline logs what Blizzard's bar showed", tlb:find("Blizzard's player icons: 1 shown, 1 icons readable, 0 secret", 1, true) and tlb:find("1 secret", 1, true), tlb)
	-- a bar whose icons never match the aura's (verified false): never trusted, no false alarm
	S.auras.player = { { id = 997, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600, icon = "ai_buff.blp" } }
	local realGet = W.buffBar.GetChildren
	W.buffBar.GetChildren = function()
		local btn = CreateFrame("Button")
		btn.Icon = btn:CreateTexture()
		btn.Icon.GetTextureFileID = function() return 123456 end -- another form of the same icon
		return btn
	end
	W.Update(1.1)
	check("icons that do not match the aura's: not verified", ns.P.trackers.learned[1459].barOk == false)
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracleErr = true, oracle = true, lookupsNil = true }
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Update(0.25)
	check("...so in combat they are not used (estimate, no false alarm)", TRb.how[bb.id] == "estimate" and not bbf:IsShown(), TRb.how[bb.id])
	S.me.combat = false
	S.secret = nil
	W.Fire("PLAYER_REGEN_ENABLED")
	W.buffBar.GetChildren = realGet
	BuffFrame = nil
	TRb.Remove(bb.id)
	S.auras.player = nil
	W.Update(0.25)
end

-- LIGHTNING SHIELD: charges counted down on physical hits (3.13) -------------------
do
	local TRh = ns.Trackers
	BuffFrame = W.buffBar
	ns.P.trackers.trust = {}
	S.auras = S.auras or {}
	S.auras.player = { { id = 1001, harmful = false, name = "Arkane Intelligenz", spellId = 1459, source = "player", duration = 600, icon = "ls.blp", stacks = 3 } }
	local nm = TRh.Add("Arkane Intelligenz", "self")  -- stands in for Blitzschlagschild
	nm.invert = true; TRh.Changed()                    -- NOT ON ME
	local on = TRh.Add("Arkane Intelligenz", "self")   -- ON ME, shows the charges
	local nmf, onf = TRh.icons[nm.id], TRh.icons[on.id]
	W.Update(1.1)
	check("out of combat: 3 charges learned", ns.P.trackers.learned[1459].charges == 3)
	check("a buff with charges counts hits by default", TRh.CountsHits(nm) and TRh.CountsHits(on))
	-- Forever in combat: aura data refused, lookups nil, Blizzard's icon secret after the first redraw
	S.me.combat = true
	S.secret = { auras = true, auraList = true, oracleErr = true, oracle = true, lookupsNil = true, buffbar = true }
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Update(0.25)
	check("in combat: the charge count decides", TRh.how[nm.id] == "charge count", TRh.how[nm.id])
	check("ON ME shows 3 charges", onf:IsShown() and onf.time:GetText() == "3", onf.time:GetText())
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1)      -- a melee hit
	check("melee hit: 2 left", onf.time:GetText() == "2", onf.time:GetText())
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", 300, 4)      -- a fire spell
	W.Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)        -- dodged
	W.Fire("UNIT_COMBAT", "player", "MISS", "", 0, 1)         -- missed
	check("spells, dodges and misses do not count", onf.time:GetText() == "2", onf.time:GetText())
	check("NOT ON ME still hidden", not nmf:IsShown())
	W.Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 200, 1)
	W.Fire("UNIT_COMBAT", "player", "WOUND", "BLOCK", 50, 1)  -- blocked: still a hit
	check("third physical hit: the shield is gone, NOT ON ME fires", nmf:IsShown() and not onf:IsShown())
	check("...without a '?' (the school was readable)", nmf.mark:GetText() == "")
	-- you recast it mid-fight: full again
	W.Update(0.1)
	W.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-50", 1459)
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-50", 1459)
	W.Update(0.1)
	check("recast: 3 charges again", onf:IsShown() and onf.time:GetText() == "3" and not nmf:IsShown(), onf.time:GetText())
	-- a school the client hides: counted anyway, marked "?"
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", 100, W.Secret())
	check("unreadable school: counted, marked '?'", onf.time:GetText() == "2" and onf.mark:GetText() == "?")
	S.me.combat = false
	S.secret = nil
	W.Fire("PLAYER_REGEN_ENABLED")
	local tlh = table.concat(SITREP_DB.reports.auraprobe_after_combat.lines, "\n")
	check("timeline logs each hit with its school", tlh:find("hit on you: 120, school 1 (physical)", 1, true) and tlh:find("school 4", 1, true) and tlh:find("2 charges left", 1, true), tlh)
	-- switched off: no counting
	nm.countHits = false; TRh.Changed()
	check("charge counting can be switched off per icon", not TRh.CountsHits(nm))
	local back = TRh.Decode(TRh.Encode())
	local foundOff
	for _, it in ipairs(back.items) do if it.invert and it.spell == 1459 and it.countHits == false then foundOff = true end end
	check("the macro copy keeps that switch", foundOff)
	TRh.Remove(nm.id); TRh.Remove(on.id)
	BuffFrame = nil
	S.auras.player = nil
	W.Update(0.25)
end

-- HEALERS ON YOU (3.14) --------------------------------------------------------------
do
	local PFh2 = ns.Frames.frames.player
	S.group.n = 4
	S.units.party1 = { name = "Priesterin", guid = "Player-1-9501", class = "PRIEST", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 10, wy = 0, hp = 3000, hpMax = 3000, targetingMe = true, role = "HEALER" }
	S.units.party2 = { name = "Krieger", guid = "Player-1-9502", class = "WARRIOR", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 8, wy = 0, hp = 5000, hpMax = 5000, targetingMe = true }
	S.units.party3 = { name = "Vergelter", guid = "Player-1-9503", class = "PALADIN", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 12, wy = 0, hp = 4000, hpMax = 4000, targetingMe = true, role = "DAMAGER" }
	S.units.party4 = { name = "Druidin", guid = "Player-1-9504", class = "DRUID", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 15, wy = 0, hp = 3500, hpMax = 3500 }
	W.Fire("GROUP_ROSTER_UPDATE")
	W.Update(0.25); W.Update(0.25)
	check("one healer targets you: HEALERS 1", W.has(PFh2.tags:GetText(), "HEALERS 1"), PFh2.tags:GetText())
	check("a warrior targeting you is no healer; a druid not targeting you does not count", ns.Targeting.HealersOnMe() == 1)
	check("healers on you: HEALERS shown instead of ALLIES", ns.Targeting.AlliesOn("player") == 3 and not W.has(PFh2.tags:GetText(), "ALLIES"), PFh2.tags:GetText())
	-- the retribution paladin starts healing you: counts, whatever its role
	S.units.player.incHealBy = { party3 = 800 }
	W.Update(0.25)
	check("a damage dealer casting a heal on you counts", ns.Targeting.HealersOnMe() == 2 and W.has(PFh2.tags:GetText(), "HEALERS 2"), PFh2.tags:GetText())
	S.units.player.incHealBy = nil
	-- no role assigned (open world): healing classes count
	S.units.party4.targetingMe = true
	W.Update(0.25)
	check("no role set: a druid targeting you counts", ns.Targeting.HealersOnMe() == 2)
	-- a long header: PVP gives way first, then COMBAT; the counts stay
	S.me.combat = true
	local realPvp, realTB = UnitIsPVP, ns.Targeting.TargetedBy
	UnitIsPVP = function() return true end
	ns.Targeting.TargetedBy = function() return 2 end
	local realMax = ns.Frames.PLAYER_TAGS_MAX
	ns.Frames.PLAYER_TAGS_MAX = 26 -- a narrow frame
	W.Update(0.25)
	local line = PFh2.tags:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	check("long header: counts kept, PVP dropped", W.has(line, "TARGETED BY 2") and W.has(line, "HEALERS 2") and W.has(line, "MOBS") == nil and not W.has(line, "PVP"), line)
	check("...and it fits", #line <= ns.Frames.PLAYER_TAGS_MAX, #line .. ": " .. line)
	UnitIsPVP, ns.Targeting.TargetedBy, ns.Frames.PLAYER_TAGS_MAX = realPvp, realTB, realMax
	S.me.combat = false
	W.Update(0.25)
	-- nobody on you heals: every friendly player on you, as ALLIES
	S.units.party1.targetingMe, S.units.party3.targetingMe, S.units.party4.targetingMe = false, false, false
	W.Update(0.25)
	check("no healer on you: ALLIES 1 (the warrior)", W.has(PFh2.tags:GetText(), "ALLIES 1") and not W.has(PFh2.tags:GetText(), "HEALERS"), PFh2.tags:GetText())
	ns.P.frames.healersOnMe = false
	W.Update(0.25)
	check("switched off: no tag", not W.has(PFh2.tags:GetText(), "HEALERS") and not W.has(PFh2.tags:GetText(), "ALLIES"))
	ns.P.frames.healersOnMe = true
	S.units.party1, S.units.party2, S.units.party3, S.units.party4, S.group.n = nil, nil, nil, nil, 0
	W.Fire("GROUP_ROSTER_UPDATE")
	W.Update(11)
	check("alone: no tag", not W.has(PFh2.tags:GetText(), "HEALERS"))
end

-- WHO IS ON YOUR TARGET (3.15) -------------------------------------------------------
do
	local TFw = ns.Frames.frames.target
	local foe = { name = "Fahnentraeger", guid = "Player-2-9601", class = "WARRIOR", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 20, hp = 5000, hpMax = 5000 }
	S.units.target = foe
	-- two of yours on it (party), one friendly stranger on a plate too
	S.group.n = 2
	S.units.party1 = { name = "Eins", guid = "Player-1-9611", class = "ROGUE", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 5, wy = 0, targetOf = foe }
	S.units.party2 = { name = "Zwei", guid = "Player-1-9612", class = "MAGE", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 9, wy = 0 }
	S.units.nameplate80 = { name = "Fremder", guid = "Player-1-9613", class = "HUNTER", level = 60, isPlayer = true, hostile = false, faction = "Alliance", dist = 25, screenX = 900, targetOf = foe }
	-- its teammates: a priest healing it, a shaman (healing class) and a rogue on it
	S.units.nameplate81 = { name = "Heilerin", guid = "Player-2-9621", class = "PRIEST", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 30, screenX = 1000, targetOf = foe }
	S.units.nameplate82 = { name = "Schamane", guid = "Player-2-9622", class = "SHAMAN", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 30, screenX = 1100, targetOf = foe }
	S.units.nameplate83 = { name = "Schurke", guid = "Player-2-9623", class = "ROGUE", level = 60, isPlayer = true, hostile = true, faction = "Horde", dist = 10, screenX = 1200, targetOf = foe }
	for i = 80, 83 do W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
	W.Fire("GROUP_ROSTER_UPDATE"); W.Fire("PLAYER_TARGET_CHANGED")
	W.Update(0.25); W.Update(0.25)
	check("allies on your enemy target: 2 (group and a friendly plate)", ns.Targeting.AlliesOn("target") == 2, ns.Targeting.AlliesOn("target"))
	check("enemy healers on it: priest and shaman, not the rogue", ns.Targeting.EnemiesOn("target", true) == 2, ns.Targeting.EnemiesOn("target", true))
	check("target frame shows both", W.has(TFw.tags:GetText(), "ALLIES 2") and W.has(TFw.tags:GetText(), "HEALERS 2"), TFw.tags:GetText())
	-- a hybrid seen healing it counts, whatever its class
	S.units.nameplate83.class = "WARRIOR"
	S.units.target.incHealBy = { nameplate83 = 500 }
	W.Update(0.25)
	check("anyone seen healing it counts as a healer", ns.Targeting.EnemiesOn("target", true) == 3)
	S.units.target.incHealBy = nil
	-- a friendly target: the enemies on it instead
	local buddy = S.units.party2
	S.units.target = buddy
	S.units.nameplate83.targetOf, S.units.nameplate81.targetOf = buddy, buddy
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
	check("friendly target: enemies on it shown as TARGETED BY", W.has(TFw.tags:GetText(), "TARGETED BY 2"), TFw.tags:GetText())
	check("...and no enemy healers count", not W.has(TFw.tags:GetText(), "HEALERS"))
	ns.P.frames.targetCounts = false
	W.Update(0.25)
	check("switched off: no counts", not W.has(TFw.tags:GetText(), "TARGETED BY"))
	ns.P.frames.targetCounts = true
	for i = 80, 83 do S.units["nameplate" .. i] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
	S.units.party1, S.units.party2, S.group.n, S.units.target = nil, nil, 0, nil
	W.Fire("GROUP_ROSTER_UPDATE"); W.Fire("PLAYER_TARGET_CHANGED")
	wipeContacts(C)
	W.Update(11)
end

-- LEVELLING: mobs on you, allies on your mob (3.16) ---------------------------------
do
	local PFm, TFm = ns.Frames.frames.player, ns.Frames.frames.target
	local wolf = { name = "Wolf", guid = "Creature-0-1-0-1-299-0001", class = "WARRIOR", level = 10, isPlayer = false, hostile = true, reaction = 2, dist = 5, screenX = 900, targetingMe = true, hp = 300, hpMax = 300 }
	local wolf2 = { name = "Wolf", guid = "Creature-0-1-0-1-299-0002", class = "WARRIOR", level = 10, isPlayer = false, hostile = true, reaction = 2, dist = 8, screenX = 950, targetingMe = true, hp = 300, hpMax = 300 }
	local bear = { name = "Baer", guid = "Creature-0-1-0-1-822-0003", class = "WARRIOR", level = 11, isPlayer = false, hostile = true, reaction = 2, dist = 15, screenX = 1000, hp = 400, hpMax = 400 }
	S.units.nameplate90, S.units.nameplate91, S.units.nameplate92 = wolf, wolf2, bear
	for i = 90, 92 do W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
	S.units.target = wolf
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
	check("two mobs on you: MOBS 2 (your target counted once)", ns.Targeting.MobsOnMe() == 2 and W.has(PFm.tags:GetText(), "MOBS 2"), PFm.tags:GetText())
	check("a mob not on you does not count", true)
	-- someone else hits your wolf
	S.group.n = 1
	S.units.party1 = { name = "Helfer", guid = "Player-1-9701", class = "WARRIOR", level = 10, isPlayer = true, hostile = false, faction = "Alliance", wx = 4, wy = 0, targetOf = wolf }
	W.Fire("GROUP_ROSTER_UPDATE"); W.Update(0.25); W.Update(0.25)
	check("NPC target: ALLIES 1 when someone else is on it", W.has(TFm.tags:GetText(), "ALLIES 1"), TFm.tags:GetText())
	-- the client hides the comparisons in combat: counted as secret, no false numbers
	S.me.combat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	local realUIU = UnitIsUnit
	UnitIsUnit = function(a, b) if tostring(a):find("target$") then return W.Secret() end return realUIU(a, b) end
	W.Update(0.25)
	check("secret comparisons: no wrong counts", ns.Targeting.MobsOnMe() == 0 and not W.has(PFm.tags:GetText(), "MOBS"))
	check("...and tallied for the report", ns.Targeting.stats.secret > 0)
	UnitIsUnit = realUIU
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	ns.P.frames.mobsOnMe = false; W.Update(0.25)
	check("MOBS switched off", not W.has(PFm.tags:GetText(), "MOBS"))
	ns.P.frames.mobsOnMe = true
	for i = 90, 92 do S.units["nameplate" .. i] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
	S.units.party1, S.group.n, S.units.target = nil, 0, nil
	W.Fire("GROUP_ROSTER_UPDATE"); W.Fire("PLAYER_TARGET_CHANGED")
	wipeContacts(C)
	W.Update(11)
end

-- POPPING NUMBERS (3.17) ------------------------------------------------------------
do
	local PF = ns.Frames.frames.player
	check("pop host on the player frame", PF.pops ~= nil)
	local d, h = PF.pops.sides.dmg, PF.pops.sides.heal
	W.Update(2)
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", 1234, 1)
	check("damage pops, shortened", #d == 1 and d[1].text:GetText() == "-1.2k" and d[1]:IsShown(), d[1] and d[1].text:GetText())
	check("...in red", d[1].text._tc[1] == 1 and d[1].text._tc[2] < 0.5)
	W.Fire("UNIT_COMBAT", "player", "HEAL", "CRITICAL", 850, 2)
	check("heal pops on the other side", #h == 1 and h[1].text:GetText() == "+850", h[1] and h[1].text:GetText())
	check("a critical pops bigger", h[1].crit and h[1]._scale > d[1]._scale)
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", 300, 1)
	check("a new number pushes the older one up", d[1].base > d[2].base and d[2].base == 0)
	for _ = 1, 6 do W.Fire("UNIT_COMBAT", "player", "WOUND", "", 100, 1) end
	check("at most five per side", #d == 5)
	W.Update(0.3)
	check("it settles to normal size", d[#d]._scale == 1)
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", W.Secret(80), 1)
	local tx = d[5].text:GetText()
	check("a secret amount still pops (handed to the font string)", #d == 5 and (ns.isSecret(tx) or tostring(tx):find("secret", 1, true) ~= nil), tostring(tx))
	W.Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)
	W.Fire("UNIT_COMBAT", "party1", "WOUND", "", 500, 1)
	check("misses and other units: no number", #d == 5 and #h == 1)
	W.Update(1.2)
	check("numbers fade out and are recycled", #d == 0 and #h == 0)
	ns.P.frames.popNumbers = false
	W.Fire("UNIT_COMBAT", "player", "WOUND", "", 500, 1)
	check("switched off: no numbers", #d == 0)
	ns.P.frames.popNumbers = true
	check("short numbers", ns.Units.ShortNum(950) == "950" and ns.Units.ShortNum(12600) == "13k" and ns.Units.ShortNum(2500000) == "2.5m")
end

-- NAMEPLATE PROBE (3.18) -----------------------------------------------------------
do
	S.units.nameplate95 = { name = "Wolf", guid = "Creature-0-1-95", class = "WARRIOR", level = 10, isPlayer = false, hostile = true, wx = 8, wy = 0, screenX = 900 }
	S.units.nameplate96 = { name = "Freundin", guid = "Player-1-9601", class = "PRIEST", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 6, wy = 0, screenX = 1000 }
	S.units.nameplate97 = { name = "Verboten", guid = "Player-1-9701", class = "MAGE", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 7, wy = 0, screenX = 1100, forbidden = true }
	for i = 95, 97 do W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
	local realGet, bars = C_NamePlate.GetNamePlateForUnit, {}
	C_NamePlate.GetNamePlateForUnit = function(unit, includeForbidden)
		local p = realGet(unit)
		if p and not (p.IsForbidden and p:IsForbidden()) then
			bars[unit] = bars[unit] or CreateFrame("StatusBar")
			p.UnitFrame = { HealthBarsContainer = { healthBar = bars[unit] }, name = p:CreateFontString() }
			p.UnitFrame.name:SetText("Name")
		end
		return p
	end
	CompactUnitFrame_UpdateHealthColor = function() end
	SlashCmdList.SITREP("plateprobe")
	local rep = SITREP_DB.reports.plateprobe
	local text = rep and table.concat(rep.lines, "\n") or ""
	check("plate probe saved", rep ~= nil and #rep.lines > 4, text)
	check("hostile plate: anchored, recoloured, retextured", text:find("nameplate95 FOE npc  plate=ok  anchor=ok  child=ok  healthbar=HealthBarsContainer.healthBar  colour=ok  texture=ok  name=readable") ~= nil, text)
	check("friendly player plate probed too", text:find("nameplate96 FRIEND player  plate=ok", 1, true) ~= nil)
	check("forbidden plate reported, not touched", text:find("nameplate97 FRIEND player  plate=FORBIDDEN", 1, true) ~= nil)
	check("Blizzard's update function hooked", text:find("hooks: CompactUnitFrame_UpdateHealthColor", 1, true) ~= nil, text)
	local after = SITREP_DB.reports.plateprobe_after
	check("after the show: colour check and Blizzard updates", after and table.concat(after.lines, "\n"):find("our colour still there", 1, true) ~= nil)
	-- armed: once more in the next fight
	S.me.combat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	check("armed probe runs in combat", SITREP_DB.reports.plateprobe_combat ~= nil and SITREP_DB.reports.plateprobe_combat.lines[1]:find("combat true", 1, true) ~= nil)
	SITREP_DB.reports.plateprobe_combat = nil
	W.Fire("PLAYER_REGEN_DISABLED")
	check("...only once", SITREP_DB.reports.plateprobe_combat == nil)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	-- no plates at all
	C_NamePlate.GetNamePlateForUnit = realGet
	CompactUnitFrame_UpdateHealthColor = nil
	for i = 95, 97 do S.units["nameplate" .. i] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
	SlashCmdList.SITREP("plateprobe")
	check("no plates: says so", table.concat(SITREP_DB.reports.plateprobe.lines, "\n"):find("no nameplates on screen", 1, true) ~= nil)
	W.Update(11)
end

-- NAMEPLATES (3.19) ----------------------------------------------------------------
do
	local N = ns.Plates
	-- danger colours (no client colour function in the emulator: SITREP's own)
	local function rgb(...) return string.format("%.2f,%.2f,%.2f", ...) end
	check("level: far above you is red", rgb(N.LevelColor(66, 60)) == "1.00,0.10,0.10")
	check("level: +3 orange", rgb(N.LevelColor(63, 60)) == "1.00,0.50,0.25")
	check("level: same yellow", rgb(N.LevelColor(60, 60)) == "1.00,0.82,0.00")
	check("level: lower green", rgb(N.LevelColor(54, 60)) == "0.25,0.75,0.25")
	check("level: grey below the grey level", rgb(N.LevelColor(50, 60)) == "0.50,0.50,0.50" and rgb(N.LevelColor(20, 30)) == "0.50,0.50,0.50")
	check("level: ?? red", rgb(N.LevelColor(-1, 60)) == "1.00,0.25,0.20")

	-- Blizzard-like plates: a UnitFrame with a health bar, a name and a cast bar
	local realGet, plates = C_NamePlate.GetNamePlateForUnit, {}
	C_NamePlate.GetNamePlateForUnit = function(unit)
		local u = S.units[unit]
		if not (u and u.screenX) or u.forbidden then return nil end
		local p = plates[unit]
		if not p then
			p = CreateFrame("Frame")
			local uf = CreateFrame("Frame", nil, p)
			uf.healthBar = CreateFrame("StatusBar", nil, uf)
			uf.name = uf:CreateFontString()
			uf.CastBarsContainer = CreateFrame("Frame", nil, uf)                 -- as on Forever
			uf.CastBarsContainer.castBar = CreateFrame("StatusBar", nil, uf.CastBarsContainer)
			uf.healthBar.border = CreateFrame("Frame", nil, uf.healthBar)        -- Blizzard's rounded border
			uf.healthBar.bgTexture = uf.healthBar:CreateTexture()                -- and its background
			uf.healthBar:GetStatusBarTexture():AddMaskTexture(uf.healthBar:CreateTexture()) -- rounded ends
			uf.LevelFrame = CreateFrame("Frame", nil, uf)                        -- the level badge
			uf.LevelFrame.levelText = uf.LevelFrame:CreateFontString()
			uf.LevelFrame.levelText:SetText("12")
			uf.selectionHighlight = uf:CreateTexture()                          -- must stay
			p.UnitFrame = uf
			plates[unit] = p
		end
		return p
	end
	CompactUnitFrame_UpdateHealthColor = function(uf) uf.healthBar:SetStatusBarColor(0, 0, 1) end -- Blizzard's own colour
	S.units.nameplate80 = { name = "Grimmzahn", guid = "Creature-0-1-80", class = "WARRIOR", level = 63, classification = "elite", isPlayer = false, hostile = true, reaction = 2, wx = 6, wy = 0, screenX = 800, targetingMe = true }
	S.units.nameplate81 = { name = "Heilerin", guid = "Player-1-8101", class = "PRIEST", level = 60, isPlayer = true, hostile = false, reaction = 5, faction = "Alliance", wx = 9, wy = 0, screenX = 900 }
	S.units.nameplate82 = { name = "Frostmagier", guid = "Player-1-8201", class = "MAGE", level = -1, isPlayer = true, hostile = true, reaction = 1, faction = "Horde", wx = 20, wy = 0, screenX = 1000 }
	S.units.nameplate83 = { name = "Verboten", guid = "Player-1-8301", class = "MAGE", level = 60, isPlayer = true, hostile = false, faction = "Alliance", wx = 7, wy = 0, screenX = 1100, forbidden = true }
	for i = 80, 83 do W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
	W.Update(0.25)
	local mob, friend, mage = N.skins.nameplate80, N.skins.nameplate81, N.skins.nameplate82
	check("plates dressed: mob, friend, enemy player", mob and friend and mage and true)
	check("forbidden plate left to Blizzard", N.skins.nameplate83 == nil)
	local function col(s) local c = s.hb._sbColor or {} return rgb(c[1] or -1, c[2] or -1, c[3] or -1) end
	check("mob on you: red", col(mob) == "1.00,0.25,0.20", col(mob))
	CompactUnitFrame_UpdateHealthColor(mob.uf)
	check("Blizzard repaints: SITREP's colour comes back", col(mob) == "1.00,0.25,0.20", col(mob))
	check("enemy player: class colour", col(mage) == rgb(ns.Data.ClassColor("MAGE")), col(mage))
	check("friend: class colour", col(friend) == rgb(ns.Data.ClassColor("PRIEST")))
	local line = mob.name:GetText()
	check("one line: level (danger colour, + elite), full name, tags", line:find("^|cffff7f3f63%+|r Grimmzahn  ") ~= nil, line)
	check("?? for a skull level", mage.name:GetText():find("??", 1, true) ~= nil)
	check("name in SITREP's font, Blizzard's hidden", mob.uf.name:GetAlpha() == 0)
	check("centred, no width limit", mob.name._justifyH == nil or mob.name._justifyH == "CENTER")
	check("Blizzard's border, background and level badge hidden", mob.uf.healthBar.border:GetAlpha() == 0 and mob.uf.healthBar.bgTexture:GetAlpha() == 0 and mob.uf.LevelFrame:GetAlpha() == 0)
	check("...its selection highlight kept, SITREP's track shown", mob.uf.selectionHighlight:GetAlpha() == 1 and mob.track:IsShown())
	check("rounded-end mask taken off the fill", mob.hb:GetStatusBarTexture():GetNumMaskTextures() == 0)
	SlashCmdList.SITREP("platedump")
	local dump = table.concat(SITREP_DB.reports.platedump.lines, "\n")
	check("plate dump lists Blizzard's parts", dump:find("UnitFrame.LevelFrame  Frame", 1, true) ~= nil and dump:find("UnitFrame.healthBar.border", 1, true) ~= nil
		and dump:find('levelText  FontString shown a1.00 "12"', 1, true) ~= nil and dump:find("UnitFrame.healthBar:fill", 1, true) ~= nil, dump)
	local function tc(fs) local c = fs._tc or {} return rgb(c[1] or -1, c[2] or -1, c[3] or -1) end
	check("friend or foe: names green and red", tc(friend.name) == "0.20,1.00,0.32" and tc(mage.name) == "1.00,0.18,0.12", tc(friend.name) .. " / " .. tc(mage.name))
	check("enemy players marked by the coral ring (not mobs, not friends)", mage.foe:IsShown() and not mob.foe:IsShown() and not friend.foe:IsShown())
	check("tag: the 'you' glyph on the mob targeting you", mob.name:GetText():find("glyph_diamond", 1, true) ~= nil, mob.name:GetText())
	-- HOVERING A PLATE (3.38): race and class in the bar, instead of Blizzard's tooltip
	;(function()
		local PH = ns.PlateHover
		ns.P.plates.hoverWhere = "plate" -- (these checks: the info on the plate; the window further down)
		S.units.nameplate81.race = "Zwergin"
		S.units.nameplate80.creatureType = "Humanoid"
		S.units.mouseover = S.units.nameplate81
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		local r, g, b = ns.Data.ClassColor("PRIEST")
		local hexc = string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
		check("hover a player: race and class (class colour) in its bar", friend.hover and friend.hover:IsShown()
			and friend.hover:GetText():lower() == ("Zwergin |cff" .. hexc .. "PRIEST|r"):lower(), friend.hover and friend.hover:GetText())
		check("...in the middle of the bar", ({ friend.hover:GetPoint(1) })[2] == friend)
		-- Blizzard's tooltip for it: left out
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetUnit("mouseover")
		check("Blizzard's unit tooltip left out", not GameTooltip:IsShown())
		S.shift = true
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetUnit("mouseover")
		check("Shift: Blizzard's tooltip after all", GameTooltip:IsShown())
		S.shift = false
		GameTooltip:Hide()
		GameTooltip:SetOwner(ns.Frames.frames.target, "ANCHOR_NONE")
		GameTooltip:SetUnit("mouseover")
		check("hovering a unit frame: its tooltip stays", GameTooltip:IsShown())
		GameTooltip:Hide()
		-- an NPC: creature type and rank
		S.units.mouseover = S.units.nameplate80
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		check("hover an NPC: type and rank", mob.hover:GetText() == "Humanoid · Elite" and mob.hover:IsShown(), mob.hover:GetText())
		check("...the one hovered before is cleared", not friend.hover:IsShown())
		S.units.nameplate80.family = "Wolf"
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		check("a beast: its family", mob.hover:GetText() == "Wolf · Elite")
		S.units.nameplate80.family = nil
		-- the mouse leaves (no event): cleared
		S.units.mouseover = nil
		W.Update(0.2)
		check("mouse gone: cleared", not mob.hover:IsShown())
		-- a unit without a SITREP plate: Blizzard's tooltip stays
		S.units.mouseover = { name = "Fern", isPlayer = true, class = "MAGE" }
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetUnit("mouseover")
		check("no plate for it: Blizzard's tooltip stays", GameTooltip:IsShown())
		GameTooltip:Hide()
		-- secret race: left out, class still there
		S.secret = { race = true }
		S.units.mouseover = S.units.nameplate81
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		check("secret race left out", friend.hover:GetText():lower() == ("|cff" .. hexc .. "PRIEST|r"):lower(), friend.hover:GetText())
		S.secret = nil
		-- off: no text, Blizzard's tooltip
		ns.P.plates.hoverInfo = false; ns.Changed("plates.hoverInfo")
		check("off: nothing in the bar", not friend.hover:IsShown())
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetUnit("mouseover")
		check("off: Blizzard's tooltip", GameTooltip:IsShown())
		GameTooltip:Hide()
		ns.P.plates.hoverInfo = true; ns.Changed("plates.hoverInfo")
		S.units.mouseover = nil
		W.Update(0.2)

		-- the window (the default): any unit under the mouse, nothing on the plates
		ns.P.plates.hoverWhere = "frame"; ns.Changed("plates.hoverWhere")
		local f = PH.frame
		S.units.mouseover = S.units.nameplate81
		S.units.nameplate81.guild = "Die Wächter"
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		check("hover window: name, level, race and class, guild", f:IsShown() and f.name:GetText() == "Heilerin"
			and f.level:GetText() == "60" and f.info:GetText():find("Zwergin", 1, true) and f.guild:GetText() == "<Die Wächter>",
			f.info:GetText())
		check("...nothing on the plate then", not friend.hover:IsShown())
		;(function()
			-- a long race name wraps, the window grows; what you can dispel on it, with its orb
			local realRem, realH = ns.Auras.RemovableAuras, f.info.GetStringHeight
			ns.Auras.RemovableAuras = function() return { { name = "Hex of Weakness", dispel = "Curse" }, { name = nil, dispel = "Poison" } } end
			S.units.nameplate81.race = "Himmelsgeborene des Hohen Ordens"
			f.info.GetStringHeight = function() return 26 end
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			local dt = f.dispel:GetText()
			check("hover window: a long race wraps (as wide as the window), the window grows", f.info._w == 240 - 16
				and f:GetHeight() >= 24 + 26 + 7 + 13, f:GetHeight())
			check("hover window: what you can dispel, an orb in its colour and the name (else the kind)", dt:find("Dispel", 1, true)
				and dt:find("Hex of Weakness", 1, true) and dt:find("Poison", 1, true) and dt:find("glyph_dot", 1, true), dt)
			ns.Auras.RemovableAuras = function() return {} end
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			check("...nothing to dispel: no line", f.dispel:GetText() == "")
			ns.Auras.RemovableAuras, f.info.GetStringHeight = realRem, realH
			S.units.nameplate81.race = "Zwergin"
			W.Fire("UPDATE_MOUSEOVER_UNIT")
		end)()
		;(function()
			-- an enemy player: the matchup, and a legend of the marks its plate shows
			S.units.mouseover = S.units.nameplate82
			N.Refresh(mage)
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			local it, lg = f.intel:GetText(), f.legend:GetText()
			check("hover an enemy player: matchup and advice", W.has(it, "MATCHUP") and f.intel:IsShown(), it)
			check("...a legend of its plate's marks: the coral ring", lg:find("enemy player", 1, true) and lg:find("glyph_ring", 1, true), lg)
			check("...lines one under the other, the window as tall as they are", ({ f.intel:GetPoint(1) })[2] ~= nil
				and f:GetHeight() > 60, f:GetHeight())
			ns.P.plates.hoverLegend = false
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			check("legend off: none", f.legend:GetText() == "" and not f.legend:IsShown())
			ns.P.plates.hoverLegend = true
			-- a friend: no matchup line
			S.units.mouseover = S.units.nameplate81
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			check("hover a friend: no matchup, its empty lines hidden", f.intel:GetText() == "" and not f.intel:IsShown())
			-- the client answering nil for an emptied line: still no room kept for it
			local h1 = f:GetHeight()
			local realGT = f.intel.GetText
			f.intel.GetText = function() return nil end
			ns.PlateHover.Layout(f)
			check("an empty line answering nil: no room kept, the window as tall as before", f:GetHeight() == h1 and not f.intel:IsShown(), f:GetHeight())
			f.intel.GetText = realGT
		end)()
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetUnit("mouseover")
		check("...and no Blizzard tooltip", not GameTooltip:IsShown())
		-- a unit without a SITREP plate: the window too
		S.units.mouseover = { name = "Fern", isPlayer = true, class = "MAGE", level = 20, race = "Gnom" }
		W.Fire("UPDATE_MOUSEOVER_UNIT")
		check("a unit without a plate: the window too", f:IsShown() and f.name:GetText() == "Fern" and f.info:GetText():find("Gnom", 1, true))
		S.units.mouseover = nil
		W.Update(0.2)
		check("mouse gone: the window goes", not f:IsShown())
		;(function()
			-- next to the mouse: opened below right of it, staying there while you hover that unit
			ns.P.plates.hoverWhere = "mouse"; ns.Changed("plates.hoverWhere")
			S.cursorX = 600
			S.units.mouseover = S.units.nameplate81
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			local p1 = { f:GetPoint(1) }
			local es = f:GetEffectiveScale()
			check("next to the mouse: below right of it, a little away", f:IsShown() and p1[1] == "TOPLEFT" and p1[2] == UIParent
				and math.abs(p1[4] - (600 / es + 28)) < 1e-6 and math.abs(p1[5] - (540 / es - 28)) < 1e-6, tostring(p1[4]) .. " " .. tostring(p1[5]))
			S.cursorX = 700
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			check("...it stays while the mouse is on that unit", ({ f:GetPoint(1) })[4] == p1[4])
			S.units.mouseover = S.units.nameplate82
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			check("...another unit: opened by the mouse again", ({ f:GetPoint(1) })[4] ~= p1[4])
			-- at the right edge: turned to the left of the mouse
			S.units.mouseover = nil
			W.Update(0.2)
			S.cursorX = 1900
			S.units.mouseover = S.units.nameplate81
			W.Fire("UPDATE_MOUSEOVER_UNIT")
			local p2 = { f:GetPoint(1) }
			check("at the screen's right edge: left of the mouse", p2[4] < 1900 / f:GetEffectiveScale(), tostring(p2[4]))
			S.units.mouseover, S.cursorX = nil, nil
			W.Update(0.2)
			ns.P.plates.hoverWhere = "frame"; ns.Changed("plates.hoverWhere")
		end)()
		-- placing it: unlocked, a sample shows
		ns.P.hud.locked = false; ns.Changed("hud.locked")
		check("unlocked: a sample to place", f:IsShown() and f.name:GetText() == "Hover info")
		ns.P.hud.locked = true; ns.Changed("hud.locked")
		check("locked: gone", not f:IsShown())
		S.units.nameplate81.guild = nil

		-- heals on their way, on the plate's bar
		local fu = S.units.nameplate81
		fu.hp, fu.hpMax, fu.incHeal, fu.incHealMine = 1000, 3000, 600, 400
		W.Fire("UNIT_HEAL_PREDICTION", "nameplate81")
		check("plate: heals on their way on Blizzard's bar (all, yours on top)", friend.healN.all:IsShown() and friend.healN.all:GetValue() == 600
			and friend.healN.mine:IsShown() and friend.healN.mine:GetValue() == 400 and not friend.healB.all:IsShown())
		check("...held by SITREP's frame, nothing of SITREP's in Blizzard's bar", friend.healN.clip:GetParent() == friend and friend.hb.heal == nil)
		S.secret = { heals = true }
		W.Fire("UNIT_HEAL_PREDICTION", "nameplate81")
		check("...secret amounts (in combat): drawn as the client gives them", friend.healN.all:IsShown() and issecretvalue(friend.healN.all:GetValue()))
		S.secret = nil
		ns.P.plates.scale = 2; ns.Changed("plates.scale")
		W.Fire("UNIT_HEAL_PREDICTION", "nameplate81")
		check("bigger plates: the heals on SITREP's own bar", friend.healB.all:IsShown() and friend.healB.all:GetValue() == 600
			and not friend.healN.all:IsShown())
		ns.P.plates.scale = 1; ns.Changed("plates.scale")
		ns.P.plates.heals = false; ns.Changed("plates.heals")
		check("heals off: none on the plate", not friend.healN.all:IsShown() and not friend.healB.all:IsShown())
		ns.P.plates.heals = true; ns.Changed("plates.heals")
		fu.incHeal, fu.incHealMine = nil, nil
		W.Fire("UNIT_HEAL_PREDICTION", "nameplate81")
		check("no heals coming: nothing", not friend.healN.all:IsShown())
		-- bigger plates: SITREP's own bar, centred on Blizzard's, its whole look scaled
		ns.P.plates.scale = 2; ns.Changed("plates.scale")
		check("bigger plates: SITREP's own bar shows, Blizzard's invisible", mob.isBig and mob.big:IsShown() and mob.hb:GetAlpha() == 0)
		check("...SITREP's look scaled and centred on Blizzard's bar", mob:GetScale() == 2 and ({ mob:GetPoint(1) })[1] == "CENTER"
			and ({ mob:GetPoint(1) })[2] == mob.hb)
		S.units.nameplate80.hp, S.units.nameplate80.hpMax = 3000, 4000
		W.Fire("UNIT_HEALTH", "nameplate80")
		check("...the health on SITREP's bar", mob.big:GetValue() == 3000 and select(2, mob.big:GetMinMaxValues()) == 4000,
			tostring(mob.big:GetValue()))
		check("...in SITREP's colour", mob.big._sbColor and mob.big._sbColor[1] == 1 and mob.big._sbColor[2] < 0.3)
		local wx = S.units.nameplate80.wx
		S.units.nameplate80.wx = 300 -- (far beyond every spell)
		ns.Plates.Refresh(mob)
		check("...out of range: SITREP's bar fades, Blizzard's stays invisible", mob.far and mob.big:GetAlpha() < 1 and mob.hb:GetAlpha() == 0,
			tostring(mob.far) .. " " .. mob.big:GetAlpha())
		S.units.nameplate80.wx = wx
		ns.Plates.Refresh(mob)
		ns.P.plates.scale = 1; ns.Changed("plates.scale")
		check("back to 100 %: on Blizzard's bar as before", not mob.big:IsShown() and mob:GetScale() == 1
			and ({ mob:GetPoint(1) })[1] == "TOPLEFT" and mob.hb:GetAlpha() > 0)
		-- the mouse on a party member's frame: its plate drawn as your target's
		S.units.party1 = S.units.nameplate81
		local m = ns.Frames.partyMembers[1]
		check("before: the member's plate not marked", not friend.sel:IsShown())
		m._scripts.OnEnter(m)
		check("hovering the member's frame: its plate gets the target brackets", friend.sel:IsShown() and not mage.sel:IsShown())
		ns.Plates.Refresh(friend) -- (the plates' regular update)
		check("...and keeps them while the mouse stays", friend.sel:IsShown())
		m._scripts.OnLeave(m)
		check("mouse off its frame: as before", not friend.sel:IsShown())
		S.units.party1 = nil
	end)()
	-- A PLATE FRAME REUSED FOR ANOTHER PLAYER (3.41.1): the game hands the frame of a
	-- plate leaving the screen to a new unit, often before it says the old one is
	-- gone (very often with "show nameplates off-screen")
	;(function()
		local N = ns.Plates
		S.units.nameplate90 = { name = "Fremder", guid = "Player-1-9001", class = "ROGUE", level = 60, isPlayer = true, hostile = true,
			reaction = 1, faction = "Horde", wx = 15, wy = 0, screenX = 950 }
		local frame = plates.nameplate82                -- the enemy mage's plate frame...
		plates.nameplate90 = frame                      -- ...now shows the rogue
		W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate90")  -- (the game: new unit first)
		local s = N.skins.nameplate90
		check("reused frame: the skin now belongs to the new unit", s and s.unit == "nameplate90" and s.active)
		check("...and the old unit no longer points at it", N.skins.nameplate82 ~= s)
		-- you target the mage (its plate is gone): the rogue's plate must not light up
		S.units.target = S.units.nameplate82
		W.Fire("PLAYER_TARGET_CHANGED")
		check("targeting the old unit: no target brackets on the reused plate", not s.sel:IsShown())
		-- the game now says the mage's plate is gone: the rogue's plate stays SITREP's
		plates.nameplate82 = nil
		W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate82")
		check("old unit removed later: the new unit keeps its skin", N.skins.nameplate90 == s and s.active and s:IsShown())
		-- casts and hovering go by what the frame shows now, not the old name for it
		S.units.nameplate82.casting, S.units.nameplate82.targetingMe = true, true
		ns.Incoming.casts.nameplate82 = { unit = "nameplate82", onMe = true, raw = true }
		ns.IncomingUI.Plates()
		check("a cast of the old unit: no red box on the reused plate", not (s.inc and s.inc:IsShown()))
		ns.Incoming.casts.nameplate82 = nil
		S.units.nameplate82.casting, S.units.nameplate82.targetingMe = false, nil
		S.units.target = S.units.nameplate90
		W.Fire("PLAYER_TARGET_CHANGED")
		check("targeting the new unit: its plate lights up", s.sel:IsShown())
		S.units.target = nil
		W.Fire("PLAYER_TARGET_CHANGED")
		-- back as it was for the tests after this
		W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate90")
		plates.nameplate90, S.units.nameplate90 = nil, nil
		plates.nameplate82 = frame
		W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate82")
		mage = N.skins.nameplate82
	end)()
	-- CASTS ON YOU (3.39/3.40): an enemy casting at you, also one you have not targeted
	;(function()
		local I, UI = ns.Incoming, ns.IncomingUI
		local banners = {}
		local realBanner = ns.HUD.Banner
		ns.HUD.Banner = function(text, ...) banners[#banners + 1] = text; return realBanner(text, ...) end
		local blocked0 = W.blockedCalls
		local mageU, mobU = S.units.nameplate82, S.units.nameplate80
		local function start(u, unit, name, ms)
			u.casting, u.castName = true, name or u.castName
			u.castStart, u.castEnd = W.now * 1000, W.now * 1000 + (ms or 2500)
			W.Fire("UNIT_SPELLCAST_START", unit)
		end
		local function stop(u, unit) u.casting = false; W.Fire("UNIT_SPELLCAST_STOP", unit) end
		S.units.target = nil
		mageU.targetingMe = true
		S.me.combat = true
		start(mageU, "nameplate82", "Frostbolt")
		check("an enemy casting at you: known", I.casts.nameplate82 and I.casts.nameplate82.onMe == true)
		local m = mage.inc
		check("its plate: a red box round the whole plate, ON YOU beside it", m and m:IsShown() and m:GetAlpha() == 1
			and m.text:GetText():lower() == "on you" and m.box.fill:IsShown())
		check("...drawn above other plates, never dimmed with the plate", m._strata == "HIGH" and m._ignoreParentAlpha == true)
		W.Update(0.1)
		local a1 = m.box:GetAlpha()
		W.Update(0.13)
		check("...pulsing", m.box:GetAlpha() ~= a1 and m.box:GetAlpha() >= 0.55 and m.box:GetAlpha() <= 1, a1 .. " " .. m.box:GetAlpha())
		local al = UI.alert
		check("flash: <caster> casts <spell> on you! (not your target)", al and al:IsShown() and al.who:GetText():find("Frostmagier|r casts", 1, true)
			and al.spell:GetText() == "Frostbolt" and al.tail:GetText() == "on you!", al and al.who:GetText())
		local r, g, b = ns.Data.ClassColor("MAGE")
		check("...the caster in its class colour", al.who:GetText():find(string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)), 1, true))
		-- a mob too: its own box and its own flash (red name)
		start(mobU, "nameplate80", "Schattenblitz", 3000)
		check("a mob casting at you: its box and the flash", mob.inc and mob.inc:IsShown() and al.who:GetText() == "|cffff3f33Grimmzahn|r casts"
			and al.spell:GetText() == "Schattenblitz", al.who:GetText())
		-- the same caster again within 1.5 s: no new flash
		local shownAt = al.shown
		stop(mobU, "nameplate80")
		W.Update(0.5)
		start(mobU, "nameplate80", "Schattenblitz", 3000)
		check("same caster again within 1.5 s: no new flash", al.shown == shownAt)
		-- 2 s, then it fades
		al.shown = GetTime() - 2.25
		W.Update(0.01)
		check("after 2 s it fades", al:IsShown() and al:GetAlpha() < 0.6 and al:GetAlpha() > 0.4, al:GetAlpha())
		al.shown = GetTime() - 3
		W.Update(0.01)
		check("...then gone", not al:IsShown())
		stop(mobU, "nameplate80")
		start(mobU, "nameplate80", "Schattenblitz", 3000)
		stop(mageU, "nameplate82")
		check("cast over: its box gone, the other stays", not mage.inc:IsShown() and mob.inc:IsShown())
		stop(mobU, "nameplate80")
		check("none left: no boxes", not mob.inc:IsShown())
		-- the caster switches its target to you mid-cast (an event)
		mageU.targetingMe = false
		start(mageU, "nameplate82")
		check("casting at someone else: no box", I.casts.nameplate82 == nil and not mage.inc:IsShown())
		mageU.targetingMe = true
		W.Fire("UNIT_TARGET", "nameplate82")
		check("switches to you mid-cast: box", mage.inc:IsShown())
		stop(mageU, "nameplate82")
		-- a mob takes you as its target a moment after starting its cast (seen on Forever)
		mobU.targetingMe = false
		start(mobU, "nameplate80", "Schattenblitz", 3000)
		check("cast starts at someone else: nothing yet, but watched", I.casts.nameplate80 == nil and I.watched.nameplate80)
		mobU.targetingMe = true -- (no UNIT_TARGET event: the target just is you now)
		W.Update(0.15)
		check("...turns to you mid-cast: box", I.casts.nameplate80 and mob.inc:IsShown())
		stop(mobU, "nameplate80")
		check("cast over: no longer watched", not I.watched.nameplate80 and not mob.inc:IsShown())
		W.Update(0.15)
		check("nothing watched: the re-check rests", not I.watcher:IsShown())
		-- your own target casting at you: the box, no flash (its cast bar is in front of you)
		S.units.target = mageU
		al:Hide()
		for k in pairs(UI.lastBanner) do UI.lastBanner[k] = nil end
		start(mageU, "nameplate82")
		check("your target at you: box, no flash", mage.inc:IsShown() and not al:IsShown())
		stop(mageU, "nameplate82")
		S.units.target = nil
		-- a friend casting with its target on you: not hostile, nothing
		local friendU = S.units.nameplate81
		friendU.targetingMe, friendU.casting = true, true
		W.Fire("UNIT_SPELLCAST_START", "nameplate81")
		check("a friend: nothing", I.casts.nameplate81 == nil)
		friendU.targetingMe, friendU.casting = nil, false
		-- secret "is its target me": the box from the client's own answer
		S.secret = { isUnit = true }
		for k in pairs(UI.lastBanner) do UI.lastBanner[k] = nil end
		al:Hide()
		start(mageU, "nameplate82")
		check("secret: the box, from the client's own answer", mage.inc:IsShown() and mage.inc:GetAlpha() == 1)
		check("secret: no flash (unknown to SITREP)", not al:IsShown())
		mageU.targetingMe = false
		W.Fire("UNIT_TARGET", "nameplate82")
		check("secret and not you: the client hides the box", mage.inc:GetAlpha() == 0)
		S.secret = nil
		mageU.targetingMe = true
		stop(mageU, "nameplate82")
		-- the cast probe records what SITREP made of it
		SlashCmdList.SITREP("castprobe")
		start(mageU, "nameplate82")
		local probe = table.concat(SITREP_DB.reports.castprobe.lines, "\n")
		check("cast probe: setup and each cast with its answers", probe:find("setup: display loaded", 1, true)
			and probe:find("UNIT_SPELLCAST_START nameplate82: casting Frostbolt (cast), times", 1, true)
			and probe:find("can attack true, its target is me true", 1, true) and probe:find("plate box SHOWN", 1, true), probe)
		stop(mageU, "nameplate82")
		check("all in combat, nothing blocked", W.blockedCalls == blocked0, table.concat(W.blockedLog, ", "))
		S.me.combat = false
		-- a secret spell name: in the flash as it is
		S.secret = { cast = true }
		for k in pairs(UI.lastBanner) do UI.lastBanner[k] = nil end
		start(mageU, "nameplate82")
		check("secret spell name: flash shows it as it is", al:IsShown() and issecretvalue(al.spell:GetText()))
		S.secret = nil
		stop(mageU, "nameplate82")
		-- placing it: shown while the HUD is unlocked, sized on the Layout page
		al:Hide()
		ns.P.hud.locked = false; ns.Changed("hud.locked")
		check("unlocked: the flash shows to be placed", al:IsShown() and al.spell:GetText() == "Schattenblitz" and al.unlock:IsShown())
		ns.P.hud.frameScale.castAlert = 1.3; ns.Changed("hud.frameScale")
		check("its size from the Layout page", al:GetScale() == ns.P.hud.scale * 1.3)
		ns.P.hud.frameScale.castAlert = 1
		ns.P.hud.locked = true; ns.Changed("hud.locked")
		check("locked: gone again", not al:IsShown())
		-- switched off
		ns.P.alerts.incoming = false
		for k in pairs(UI.lastBanner) do UI.lastBanner[k] = nil end
		start(mageU, "nameplate82")
		check("alert off: no flash", not al:IsShown())
		ns.P.alerts.incoming = true
		stop(mageU, "nameplate82")
		ns.P.plates.incoming = false; ns.Changed("plates.incoming")
		start(mageU, "nameplate82")
		check("off: no box", not mage.inc:IsShown())
		ns.P.plates.incoming = true
		stop(mageU, "nameplate82")
		mageU.targetingMe = nil
		ns.Changed("plates.incoming")
		ns.HUD.Banner = realBanner
	end)()
	-- the bar moves right and down from where Blizzard put it, and back when given back
	do
		local hb = friend.hb
		hb._pts = { { "TOPLEFT", friend.uf, "TOPLEFT", 4, -20 }, { "TOPRIGHT", friend.uf, "TOPRIGHT", -26, -20 } }
		hb.GetNumPoints = function(self) return #self._pts end
		hb.GetPoint = function(self, i) local q = self._pts[i]; return q[1], q[2], q[3], q[4], q[5] end
		hb.ClearAllPoints = function(self) self._pts = {} end
		hb.SetPoint = function(self, a, rel, b, x, y) self._pts[#self._pts + 1] = { a, rel, b, x, y } end
		friend.shifted, friend.orig = nil, nil
		N.Refresh(friend)
		check("bar shifted right 12, down 4", hb._pts[1][4] == 16 and hb._pts[1][5] == -24 and hb._pts[2][4] == -14, hb._pts[1][4] .. "," .. hb._pts[1][5])
		N.Refresh(friend)
		check("...once, not again on every refresh", hb._pts[1][4] == 16)
		ns.P.plates.shiftX = 0; N.Refresh(friend)
		check("the shift is a setting", hb._pts[1][4] == 4 and hb._pts[1][5] == -24)
		ns.P.plates.shiftX, ns.P.plates.shiftY = 0, 0; N.Refresh(friend)
		check("no shift: Blizzard's own anchors", hb._pts[1][4] == 4 and hb._pts[1][5] == -20)
		ns.P.plates.shiftX, ns.P.plates.shiftY = 12, -4; N.Refresh(friend)
		-- Blizzard lays the bar out again: its new anchors are the ones shifted
		hb._pts = { { "TOPLEFT", friend.uf, "TOPLEFT", 0, -10 } }
		N.Refresh(friend)
		check("Blizzard's new layout is shifted, not the old", hb._pts[1][4] == 12 and hb._pts[1][5] == -14)
		friend.hbAnchors = hb
	end
	friend.hb:Hide(); N.Refresh(friend)
	check("name-only plate: Blizzard's name stays, SITREP's steps aside", friend:GetAlpha() == 0 and friend.uf.name:GetAlpha() == 1 and not friend.foe:IsShown())
	friend.hb:Show(); N.Refresh(friend)
	check("...and back with the bar", friend:GetAlpha() == 1 and friend.uf.name:GetAlpha() == 0)
	-- friends you have not targeted stay faint; your target in full; enemies untouched
	local function near(a, b) return math.abs(a - b) < 0.001 end
	check("friend, not targeted: bar 30 % see-through", near(friend.uf:GetAlpha(), 0.7) and near(friend.border[1]:GetAlpha(), 0.7) and near(friend.cast:GetAlpha(), 0.7), friend.uf:GetAlpha())
	check("...its level and name not", friend:GetAlpha() == 1 and friend.text:GetAlpha() == 1)
	check("enemies: full", mage:GetAlpha() == 1 and mob:GetAlpha() == 1)
	S.units.target = S.units.nameplate81
	W.Fire("PLAYER_TARGET_CHANGED")
	check("friend you target: full at once", friend.uf:GetAlpha() == 1 and friend.border[1]:GetAlpha() == 1)
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
	check("...see-through again when you target something else", near(friend.uf:GetAlpha(), 0.7))
	ns.P.plates.friendOpacity = 0.5; N.Refresh(friend)
	check("the opacity is a setting", near(friend.uf:GetAlpha(), 0.5))
	ns.P.plates.friendOpacity = 0.7; N.Refresh(friend)
	-- friendly zen: only enemies, your group and your target keep their bar
	;(function()
		N.Refresh(friend)
		check("zen off by default: the bar", not friend.zenOn and friend.track:IsShown())
		local gap0 = friend.textGap
		-- Blizzard's health container, with a border that does not follow its parents' alpha
		local box = CreateFrame("Frame", nil, friend.uf)
		local bborder = box:CreateTexture()
		bborder:SetAlpha(0.8)
		local hadBox = rawget(friend.uf, "HealthBarsContainer")
		friend.uf.HealthBarsContainer = box
		ns.P.plates.friendZen = true; ns.Changed("plates.friendZen")
		check("zen: a friendly player has no bar, no track, no border", friend.zenOn and (friend.isBig and friend.big or friend.hb):GetAlpha() == 0
			and not friend.track:IsShown() and friend.border[1]:GetAlpha() == 0)
		check("zen: Blizzard's container and each texture in it see-through", box:GetAlpha() == 0 and bborder:GetAlpha() == 0)
		local green = N.Reaction("nameplate81", friend)
		local np = friend.name._points[#friend.name._points]
		check("zen: the name stays green, no level, just above the thin line", friend.name._tc[1] == green[1] and friend.name._tc[2] == green[2]
			and not friend.name.line:find("60", 1, true) and friend.textGap == "zen" and np[1] == "BOTTOM" and np[2] == friend.thin and np[3] == "TOP",
			friend.name.line)
		local cr = N.Color("nameplate81", friend)
		check("zen: a thin health line in the class colour, see-through like the friend's bar", friend.thin:IsShown() and friend.thin._h == N.THIN
			and friend.thin._sbColor[1] == cr and math.abs(friend.thin:GetAlpha() - (ns.P.plates.friendOpacity or 0.7)) < 1e-6)
		local fu = S.units.nameplate81
		local hp0 = fu.hp
		fu.hp = math.floor((fu.hpMax or 100) / 2)
		W.Fire("UNIT_HEALTH", "nameplate81")
		check("...it follows the health", friend.thin:GetValue() == fu.hp, tostring(friend.thin:GetValue()))
		fu.hp = hp0
		W.Fire("UNIT_HEALTH", "nameplate81")
		check("zen: the name stays readable", friend:GetAlpha() == 1 and friend.name:GetAlpha() == 1 and friend.text:GetAlpha() == 1)
		check("enemies keep their bar", not mage.zenOn and not mob.zenOn and mage.track:IsShown())
		-- your target
		S.units.target = S.units.nameplate81
		W.Fire("PLAYER_TARGET_CHANGED")
		check("your target: the full plate with its level, the name above the bar", not friend.zenOn and friend.track:IsShown() and not friend.thin:IsShown()
			and friend.name.line:find("60", 1, true) and friend.textGap ~= "zen")
		check("...Blizzard's bar back, each texture with its own alpha", box:GetAlpha() == 1 and bborder:GetAlpha() == 0.8)
		S.units.target = nil
		W.Fire("PLAYER_TARGET_CHANGED")
		check("...and zen again once it is not", friend.zenOn and friend.textGap == "zen")
		-- your group
		local realInParty = UnitInParty
		UnitInParty = function(u) return u == "nameplate81" end
		W.Fire("GROUP_ROSTER_UPDATE")
		check("joins your group: the bar at once", not friend.zenOn and friend.track:IsShown())
		UnitInParty = realInParty
		W.Fire("GROUP_ROSTER_UPDATE")
		check("leaves it: zen again", friend.zenOn)
		local n0 = #W.prints
		SlashCmdList.SITREP("zenprobe")
		local dump = table.concat(W.prints, "\n", n0 + 1)
		check("zenprobe: each friendly plate and why", dump:find("friendly zen: true", 1, true) and dump:find("group false, zen true, Blizzard's bar hidden true", 1, true), dump)
		ns.P.plates.friendZen = false; ns.Changed("plates.friendZen")
		check("zen off: the bar, the border, the name above it", not friend.zenOn and friend.track:IsShown() and friend.border[1]:GetAlpha() > 0 and not friend.thin:IsShown()
			and friend.textGap == gap0 and box:GetAlpha() == 1)
		friend.uf.HealthBarsContainer = hadBox
		N.Refresh(friend)
	end)()
	-- group focus: an enemy your group is on, ring and count by how many
	;(function()
		local TG = ns.Targeting
		local saved = { n = S.group.n, p1 = S.units.party1, p2 = S.units.party2, t = S.units.target }
		local mageU, mobU = S.units.nameplate82, S.units.nameplate80
		S.group.n = 2
		S.units.party1 = { name = "Mira", guid = "Player-1-7001", isPlayer = true, hostile = false, targetOf = mageU }
		S.units.party2 = { name = "Brannik", guid = "Player-1-7002", isPlayer = true, hostile = false }
		S.units.target = nil
		local function refresh() TG.UpdateFocus(); N.Refresh(mage); N.Refresh(mob); N.Refresh(friend) end
		local function ring(sk) for i, r in pairs(sk.grp.rings or {}) do if r:IsShown() then return i end end end
		refresh()
		check("group focus: one of you on it: a faint ring, 1", mage.grp:IsShown() and mage.grp.count:GetText() == "1" and ring(mage) == 1
			and not mob.grp:IsShown())
		S.units.party2.targetOf = mageU
		refresh()
		check("two of you: a wider ring, the pill filled (most of you are on it)", mage.grp.count:GetText() == "2" and ring(mage) == 2
			and W.vc(mage.grp.pill)[2] > 0.9 and mage.grp.count._tc[1] < 0.1)
		S.units.target = mageU
		refresh()
		check("you too: three, wider still", mage.grp.count:GetText() == "3" and ring(mage) == 3)
		local r3 = mage.grp.rings[3]
		check("...outside the coral ring, inside your target's brackets", ({ r3:GetPoint(1) })[4] == -5 and ({ r3:GetPoint(1) })[4] >= -6)
		S.units.party1.targetOf, S.units.party2.targetOf = mobU, mobU
		refresh()
		check("only you on it: no mark (your own target has its brackets)", not mage.grp:IsShown())
		check("the others moved on: their target marked, filled", mob.grp:IsShown() and mob.grp.count:GetText() == "2"
			and mob.grp.count._tc[1] < 0.1)
		check("friends never", not friend.grp:IsShown())
		ns.P.plates.groupFocus = false; ns.Changed("plates.groupFocus")
		refresh()
		check("group focus off: no marks", not mob.grp:IsShown())
		ns.P.plates.groupFocus = true; ns.Changed("plates.groupFocus")
		S.group.n, S.units.party1, S.units.party2, S.units.target = saved.n, saved.p1, saved.p2, saved.t
		refresh()
	end)()
	-- your target gets the accent border
	S.units.target = S.units.nameplate82
	W.Fire("PLAYER_TARGET_CHANGED")
	check("text close over the bar, clear of the brackets on your target", mage.textGap == 8 and mob.textGap == 3, mage.textGap .. " / " .. mob.textGap)
	check("target: larger brackets on your target only, in its friend/foe colour", mage.sel:IsShown() and not mob.sel:IsShown()
		and W.vc(mage.sel.parts[1])[1] == 1 and W.vc(mage.sel.parts[1])[2] < 0.5)
	-- the distance dot on your target only
	local realMR = ns.Sensors.MeasureRange
	local function dotAt(lo, hi)
		ns.Sensors.MeasureRange = function() return lo, hi end
		-- a tracked enemy's plate reuses the contact's bracket from this tick
		local ct = ns.Sensors.contacts[ns.Sensors.UnitKey("nameplate82")]
		if ct then ct.lo, ct.hi = lo, hi end
		N.Refresh(mage)
		return mage.dot:IsShown() and rgb(W.vc(mage.dot)[1], W.vc(mage.dot)[2], W.vc(mage.dot)[3]) or "none"
	end
	local reach = ns.Sensors.myReach
	ns.Sensors.myReach = 36
	check("dot: close is green", dotAt(0, 10) == "0.25,1.00,0.35")
	check("dot: within 25 yellow", dotAt(10, 20) == "1.00,0.85,0.15")
	check("dot: max range red", dotAt(28, 36) == "1.00,0.22,0.15")
	check("dot: out of range none", dotAt(36, nil) == "none" and dotAt(0, nil) == "none")
	dotAt(20, 28)
	check("distance in yards beside it, in the marker's colour", mage.distText:IsShown() and mage.distText:GetText() == "20-28y" and mage.distText._tc[1] == 1)
	dotAt(36, nil)
	check("beyond your reach: the floor, dimmed", mage.distText:GetText() == ">36y" and mage.distText._tc[1] < 0.6)
	dotAt(0, nil)
	check("no check answered: no number", not mage.distText:IsShown())
	dotAt(0, 10)
	check("dot: only on your target", not mob.dot:IsShown())
	ns.P.plates.dot = false; N.Refresh(mage)
	check("dot: switch", not mage.dot:IsShown())
	ns.P.plates.dot = true
	ns.Sensors.MeasureRange, ns.Sensors.myReach = realMR, reach
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
	check("dot: gone with the target", not mage.dot:IsShown() and not mage.distText:IsShown())
	-- a group member: exact yards from the client's positions
	local realFor = ns.Allies.ForUnit
	ns.Allies.ForUnit = function() return { exact = true, range = 13.6 } end
	S.units.target = S.units.nameplate81
	W.Fire("PLAYER_TARGET_CHANGED")
	check("group member: exact yards", friend.distText:GetText() == "14y" and friend.dot:IsShown(), friend.distText:GetText())
	ns.Allies.ForUnit = realFor
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
	-- casts: SITREP's bar, Blizzard's stays hidden
	S.units.nameplate82.casting, S.units.nameplate82.castStart, S.units.nameplate82.castEnd = true, 0, 3000000
	W.Fire("UNIT_SPELLCAST_START", "nameplate82")
	check("SITREP cast bar on the plate", mage.cast:IsShown())
	mage.uf.CastBarsContainer.castBar:Show()
	check("Blizzard's plate cast bar (in its container) hidden", not mage.uf.CastBarsContainer.castBar:IsShown() and mage.uf.CastBarsContainer:GetAlpha() == 0)
	S.units.nameplate82.casting = nil
	W.Fire("UNIT_SPELLCAST_STOP", "nameplate82")
	check("cast ends", not mage.cast:IsShown())
	-- out of reach: the plate fades
	local c = ns.Sensors.contacts[ns.Sensors.UnitKey("nameplate82")]
	if c then c.lo, c.hi = 35, nil; N.Refresh(mage) end -- beyond your longest harmful spell (35)
	check("enemy out of your reach: its bar fades", c and mage.hb:GetAlpha() < 1 and mage.border[1]:GetAlpha() < 1, c and mage.hb:GetAlpha())
	check("...its name and tags stay fully visible", mage:GetAlpha() == 1 and mage.uf:GetAlpha() == 1)
	S.units.target = S.units.nameplate82
	W.Fire("PLAYER_TARGET_CHANGED"); N.Refresh(mage)
	check("...also while it is your target", mage.sel:IsShown() and mage.hb:GetAlpha() < 1)
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
	c.lo, c.hi = 20, 28; N.Refresh(mage)
	check("back in reach: full bar", mage.hb:GetAlpha() == 1)
	-- a mob (no contact: NPCs are not tracked) and a friend: measured on the plate itself
	local realMR, realBeyond = ns.Sensors.MeasureRange, ns.Sensors.Beyond
	ns.Sensors.MeasureRange = function() return 40, nil end
	ns.Sensors.Beyond = function() return true end
	N.Refresh(mob)
	check("a mob beyond your spells fades too", mob.hb:GetAlpha() < 1)
	local realFor = ns.Allies.ForUnit
	ns.Allies.ForUnit = function() return nil end
	N.Refresh(friend)
	check("a friend beyond your heals fades too", friend.hb:GetAlpha() < 1)
	ns.Sensors.MeasureRange = function() return 10, 20 end
	ns.Sensors.Beyond = function() return false end
	N.Refresh(mob); N.Refresh(friend)
	check("...both full again in range", mob.hb:GetAlpha() == 1 and friend.hb:GetAlpha() == 1)
	ns.Sensors.MeasureRange, ns.Allies.ForUnit, ns.Sensors.Beyond = realMR, realFor, realBeyond
	-- the range fade asks one check where it can, and agrees with the whole ladder
	do
		local S_ = ns.Sensors
		local reach = S_.myReach or 28
		local saved = mob.unit and S.units[mob.unit] and S.units[mob.unit].dist
		local agree, answered = true, 0
		for _, d in ipairs({ 5, reach - 1, reach + 2, 60 }) do
			S.units[mob.unit].dist = d
			local lo = S_.MeasureRange(mob.unit)
			local b = S_.Beyond(mob.unit, reach)
			if b ~= nil then answered = answered + 1 end
			if b ~= nil and b ~= (lo ~= nil and lo >= reach) then agree = false end
		end
		S.units[mob.unit].dist = saved
		check("range fade: one check agrees with the whole ladder", agree and answered == 4, answered)
	end
	-- in combat, friendly players shrink (their own bar); your target among them does not
	;(function()
		local savedCombat = S.me.combat
		S.me.combat = false
		N.Refresh(friend)
		check("friends out of combat: the game's size", friend:GetScale() == 1 and not friend.big:IsShown())
		S.me.combat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		check("friends in combat: smaller, on SITREP's own bar", math.abs(friend:GetScale() - 0.6) < 1e-6 and friend.big:IsShown(), friend:GetScale())
		check("...enemies keep their size", mage:GetScale() == 1)
		S.units.target = S.units[friend.unit]
		W.Fire("PLAYER_TARGET_CHANGED")
		check("...a friend you target: full size", friend:GetScale() == 1, friend:GetScale())
		S.units.target = nil
		W.Fire("PLAYER_TARGET_CHANGED")
		S.me.combat = false
		W.Fire("PLAYER_REGEN_ENABLED")
		check("...after combat: back to the game's size", friend:GetScale() == 1 and not friend.big:IsShown())
		S.me.combat = savedCombat
	end)()
	-- kill window: an enemy player in your reach under 20 % health
	;(function()
		local mu = S.units[mage.unit]
		local savedHp, savedMax, savedSecret = mu.hp, mu.hpMax, S.secret
		local c_ = ns.Sensors.contacts[mage.guid] or {}
		ns.Sensors.contacts[mage.guid] = c_
		c_.live, c_.inMyReach = true, true
		mu.hp, mu.hpMax = 500, 3000
		N.Refresh(mage)
		check("kill window: an enemy player under 20 % in reach pulses", mage.kill:IsShown())
		mu.hp = 2000
		N.Kill(mage)
		check("...above 20 %: none", not mage.kill:IsShown())
		mu.hp = 500
		c_.inMyReach = false
		N.Kill(mage)
		check("...out of your reach: none", not mage.kill:IsShown())
		c_.inMyReach = true
		-- secret health (in combat): the client's colour curve decides, SITREP never reads it
		S.secret = { health = true }
		N.Kill(mage)
		local a1 = select(4, mage.kill.border[1]:GetVertexColor())
		mu.hp = 2000
		N.Kill(mage)
		local a2 = select(4, mage.kill.border[1]:GetVertexColor())
		check("kill window with secret health: painted by the client (seen under, clear above)", mage.kill:IsShown() and a1 == 1 and a2 == 0, tostring(a1) .. " " .. tostring(a2))
		S.secret = savedSecret
		N.Kill(friend)
		check("...never on friends", not friend.kill:IsShown())
		ns.P.plates.killWindow = false
		mu.hp = 500
		N.Kill(mage)
		check("...switched off: none", not mage.kill:IsShown())
		ns.P.plates.killWindow = true
		mu.hp, mu.hpMax = savedHp, savedMax
		N.Kill(mage)
	end)()
	-- a rare NPC: RARE on its plate, an alarm once
	;(function()
		local mu = S.units[mob.unit]
		local savedCls = mu.classification
		local H, banners = ns.HUD, {}
		local realBanner = H.Banner
		H.Banner = function(text, ...) banners[#banners + 1] = text return realBanner(text, ...) end
		mu.classification = "rare"
		N.Refresh(mob)
		check("rare: the star on its plate", (mob.name:GetText() or ""):find("glyph_star", 1, true) ~= nil, mob.name:GetText())
		check("rare: an alarm with its name", #banners == 1 and banners[1]:find("RARE", 1, true) and banners[1]:find(mu.name, 1, true), banners[1])
		N.Refresh(mob)
		check("rare: the alarm once, not on every redraw", #banners == 1, #banners)
		mu.classification = savedCls
		N.Refresh(mob)
		H.Banner = realBanner
	end)()
	-- aggro radar and enemy healers' mana
	;(function()
		local mu = S.units[mob.unit]
		local saved = { lvl = mu.level, wx = mu.wx, wy = mu.wy, combat = mu.combat, reaction = mu.reaction, meCombat = S.me.combat }
		mu.wy = S.me.y
		check("aggro radius: 20 yd at your level, a yard per level, 5..45", N.AggroRadius(60, 60) == 20 and N.AggroRadius(63, 60) == 23
			and N.AggroRadius(30, 60) == 5 and N.AggroRadius(-1, 60) == 45 and N.AggroRadius(90, 60) == 45)
		S.me.combat = false
		mu.reaction, mu.combat, mu.level = 2, false, ns.Sensors.self.level
		mu.wx = S.me.x + 60
		N.Refresh(mob)
		check("aggro radar: far away, nothing", not (mob.name:GetText() or ""):find("AGGRO", 1, true), mob.name:GetText())
		mu.wx = S.me.x + 25
		N.Refresh(mob)
		check("aggro radar: close to its aggro range: the triangle in amber", (mob.name:GetText() or ""):find("glyph_triangle:10:10:0:0:32:32:0:32:0:32:255:183:76", 1, true) ~= nil, mob.name:GetText())
		mu.wx = S.me.x + 9
		N.Refresh(mob)
		check("aggro radar: inside it: the triangle in coral", (mob.name:GetText() or ""):find("glyph_triangle:10:10:0:0:32:32:0:32:0:32:255:122:107", 1, true) ~= nil, mob.name:GetText())
		mu.combat = true
		N.Refresh(mob)
		check("aggro radar: already fighting: nothing", not (mob.name:GetText() or ""):find("AGGRO", 1, true))
		check("aggro radar: hostile mobs drawn often while you walk", N.Interval({ isPlayer = false, friend = false, reaction = 2 }, false) == 0.4)
		mu.level, mu.wx, mu.wy, mu.combat, mu.reaction, S.me.combat = saved.lvl, saved.wx, saved.wy, saved.combat, saved.reaction, saved.meCombat
		N.Refresh(mob)
		-- an enemy priest: its mana under the plate, OOM when nearly empty
		local pu = S.units[mage.unit]
		local savedClass, savedPow, savedMax = pu.class, pu.power, pu.powerMax
		pu.class, pu.power, pu.powerMax = "PRIEST", 3000, 4000
		N.Refresh(mage)
		check("enemy healer: its mana under the plate", mage.mana:IsShown() and mage.mana:GetValue() == 3000, mage.mana:GetValue())
		pu.power = 300
		W.Fire("UNIT_POWER_UPDATE", mage.unit, "MANA")
		check("...follows its mana", mage.mana:GetValue() == 300)
		N.Refresh(mage)
		check("...OOM when nearly empty", (mage.name:GetText() or ""):find("OOM", 1, true) ~= nil, mage.name:GetText())
		pu.class = "ROGUE"
		N.Refresh(mage)
		check("...not on a rogue", not mage.mana:IsShown())
		pu.class, pu.power, pu.powerMax = savedClass, savedPow, savedMax
		N.Refresh(mage)
	end)()
	-- quest mobs: a gold "!" with what is still open
	;(function()
		local Q = ns.Quests
		local savedQuests, savedName = S.quests, S.units[mob.unit].name
		S.units[mob.unit].name = "Kobold Vermin"
		S.quests = { { id = 101, title = "Kobold Camp Cleanup", level = 7, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 3/8" } } } }
		W.Fire("QUEST_LOG_UPDATE")
		N.Refresh(mob)
		check("quest mob: a gold ! and the count on its plate", (mob.name:GetText() or ""):find("glyph_bang", 1, true) ~= nil and (mob.name:GetText() or ""):find("3/8", 1, true) ~= nil, mob.name:GetText())
		check("quest mob: the NPC's ID from its GUID", Q.NpcID("Creature-0-1-0-1-68-0000ABCD") == 68 and Q.NpcID("Player-1-0001") == nil)
		-- asked once per kind of NPC, until the quest log changes
		local realFor, asked = Q.ForUnit, 0
		Q.ForUnit = function(...) asked = asked + 1 return realFor(...) end
		N.Refresh(mob); N.Refresh(mob)
		check("quest mob: kept, not asked again", asked == 0, asked)
		S.quests[1].objectives[1][1] = "Kobold Vermin slain: 4/8"
		W.Fire("QUEST_LOG_UPDATE")
		N.Refresh(mob)
		check("...the log changes: asked again, the new count", asked == 1 and (mob.name:GetText() or ""):find("glyph_bang", 1, true) ~= nil and (mob.name:GetText() or ""):find("4/8", 1, true) ~= nil, mob.name:GetText())
		Q.ForUnit = realFor
		-- from the client's tooltip data (loot from a mob: its name is not in the objective)
		local savedTip, savedEnum = C_TooltipInfo.GetUnit, Enum.TooltipDataLineType
		Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17 }
		C_TooltipInfo.GetUnit = function() return { lines = { { type = 0, leftText = "Kobold Vermin" },
			{ type = 17, leftText = "Wolves Across the Border" }, { type = 8, leftText = " - Tough Wolf Meat: 2/8" } } } end
		W.Fire("QUEST_LOG_UPDATE")
		N.Refresh(mob)
		check("quest mob: from the tooltip data too", (mob.name:GetText() or ""):find("glyph_bang", 1, true) ~= nil and (mob.name:GetText() or ""):find("2/8", 1, true) ~= nil, mob.name:GetText())
		-- in a group the tooltip shows the members' progress too: only yours counts as yours
		local me = UnitName("player")
		local savedN, savedP1 = S.group.n, S.units.party1
		S.group.n = 1
		S.units.party1 = { name = "Mira", guid = "Player-1-M1", isPlayer = true, class = "MAGE", level = 7 }
		Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
		S.quests = { { id = 101, title = "Kobold Camp Cleanup", level = 7, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 4/8" } } } }
		local tip
		C_TooltipInfo.GetUnit = function() return { lines = tip } end
		-- yours first, then a plain line with a member's name and theirs
		tip = { { type = 2, leftText = "Kobold Vermin" }, { type = 17, leftText = "Kobold Camp Cleanup" }, { type = 8, leftText = " - Kobold Vermin slain: 3/8" },
			{ type = 0, leftText = "Mira" }, { type = 8, leftText = " - Kobold Vermin slain: 6/8" } }
		local r = Q.TipQuestLines(tip)
		check("tooltip in a group: yours and the member's apart", r.mine:find("3/8", 1, true) and #r.party == 1 and r.party[1].name == "Mira"
			and r.party[1].text:find("6/8", 1, true))
		-- the member's lines first (their own line type), yours after your name
		tip = { { type = 17, leftText = "Kobold Camp Cleanup" }, { type = 18, leftText = "Mira" }, { type = 8, leftText = " - Kobold Vermin slain: 6/8" },
			{ type = 18, leftText = me }, { type = 8, leftText = " - Kobold Vermin slain: 3/8" } }
		r = Q.TipQuestLines(tip)
		check("...the member's first: still yours is yours", r.mine and r.mine:find("3/8", 1, true) and r.party[1].text:find("6/8", 1, true), r.mine)
		-- your count from your log (the tooltip's may lag or be a member's)
		W.Fire("QUEST_LOG_UPDATE")
		N.Refresh(mob)
		check("quest mob in a group: your own count on its plate (4/8), not Mira's 6/8", (mob.name:GetText() or ""):find("4/8", 1, true) ~= nil
			and not (mob.name:GetText() or ""):find("6/8", 1, true), mob.name:GetText())
		S.units.mouseover = S.units[mob.unit]
		ns.PlateHover.Fill("mouseover")
		local hf = ns.PlateHover.frame
		check("hover: your count, and the group line from the tooltip (Mira still needs 2)", hf.quest:GetText():find("4/8", 1, true)
			and (hf.group:GetText() or ""):find("Mira |cffe0e8e52|r", 1, true), hf.quest:GetText() .. " | " .. tostring(hf.group:GetText()))
		-- only Mira still needs it: not yours (no "!"), the hover says it is the group's
		tip = { { type = 17, leftText = "Kobold Camp Cleanup" }, { type = 18, leftText = "Mira" }, { type = 8, leftText = " - Kobold Vermin slain: 6/8" } }
		W.Fire("QUEST_LOG_UPDATE")
		N.Refresh(mob)
		check("only a member needs it: no '!' on its plate", not (mob.name:GetText() or ""):find("glyph_bang", 1, true), mob.name:GetText())
		ns.PlateHover.Fill("mouseover")
		check("...the hover: the quest and the member's need", hf.quest:GetText() == "" and hf.questTitle:GetText() == "Kobold Camp Cleanup"
			and (hf.group:GetText() or ""):find("Mira", 1, true), hf.questTitle:GetText())
		ns.PlateHover.Fill(nil)
		S.units.mouseover = nil
		S.group.n, S.units.party1 = savedN, savedP1
		C_TooltipInfo.GetUnit, Enum.TooltipDataLineType = savedTip, savedEnum
		-- not a quest mob: nothing; switched off: nothing
		S.quests = {}
		W.Fire("QUEST_LOG_UPDATE")
		N.Refresh(mob)
		check("not a quest mob: no !", not (mob.name:GetText() or ""):find("!", 1, true), mob.name:GetText())
		S.quests = { { id = 101, title = "Kobold Camp Cleanup", level = 7, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 3/8" } } } }
		W.Fire("QUEST_LOG_UPDATE")
		ns.P.plates.questMobs = false
		N.Refresh(mob)
		check("quest mobs off: no !", not (mob.name:GetText() or ""):find("!", 1, true), mob.name:GetText())
		ns.P.plates.questMobs = true
		S.quests, S.units[mob.unit].name = savedQuests, savedName
		W.Fire("QUEST_LOG_UPDATE")
	end)()
	-- plates are redrawn by priority within a time budget, not every tick; the target's every tick
	;(function()
	local live = {}
	for u, sk in pairs(N.Current()) do live[#live + 1] = sk end
	if #live > 0 then
		local real, n = N.Refresh, {}
		N.Refresh = function(sk) n[sk] = (n[sk] or 0) + 1 end
		local now = GetTime()
		for _, sk in ipairs(live) do sk.drawnAt, sk.isTarget, sk.urgent = now, false, nil end
		N.Tick(now + 0.05)
		local any = false
		for _ in pairs(n) do any = true end
		check("plates: none redrawn before its interval", not any)
		local sk1 = live[1]
		sk1.drawnAt = now - 5
		N.Tick(now)
		check("plates: redrawn when its interval is up", n[sk1] == 1 and sk1.drawnAt == now)
		-- an enemy that starts targeting you: its plate at once
		local sk = live[#live]
		ns.Fire("SR_TARGETED", { unit = sk.unit })
		N.Tick(now)
		check("plates: an enemy targeting you redrawn at once", n[sk] == 1 and not sk.urgent)
		-- your target: every tick
		sk.isTarget = true
		N.Tick(now); N.Tick(now)
		check("plates: your target every tick", n[sk] == 3)
		sk.isTarget = false
		-- over budget: the most overdue first, the rest wait (but at least MIN_PER_TICK are drawn)
		local budget = N.BUDGET_MS
		N.BUDGET_MS = 0
		for k in pairs(n) do n[k] = nil end
		for i, s_ in ipairs(live) do s_.drawnAt = now - 10 - i end -- (the last the most overdue)
		local combat = InCombatLockdown() or ns.Sensors.self.combat or false
		local lateBefore = {}
		for _, s_ in ipairs(live) do lateBefore[s_] = (now - s_.drawnAt) / math.max(N.Interval(s_, combat), 1e-9) end
		local d0 = N.stats.deferred
		N.Tick(now)
		local drawn = 0
		for _ in pairs(n) do drawn = drawn + 1 end
		-- the drawn ones are the most overdue for their own interval
		local lateOf = function(s_) return lateBefore[s_] end
		local worstWaiting, bestDrawn = 0, math.huge
		for _, s_ in ipairs(live) do
			if n[s_] then bestDrawn = math.min(bestDrawn, lateOf(s_)) else worstWaiting = math.max(worstWaiting, lateOf(s_)) end
		end
		check("plates: over budget only the minimum, the most overdue", drawn == math.min(#live, N.MIN_PER_TICK) and bestDrawn >= worstWaiting, drawn)
		check("...the rest counted as waiting", N.stats.deferred - d0 == #live - drawn)
		N.BUDGET_MS = budget
		N.Refresh = real
	end
	end)()
	-- a friend is hit: no red frame on its plate (the only red frame marks enemy players)
	W.Fire("UNIT_COMBAT", "nameplate81", "WOUND", "", 300, 1)
	check("friendly plate hit: no red frame", friend.hit == nil and not friend.foe:IsShown())
	;(function()
		-- what you can dispel on a friend: orbs left of the bar, one per kind, in its colour
		local real, glow = ns.Auras.Removables, ns.P.frames.dispelGlow
		ns.P.frames.dispelGlow = true
		local CUR, POI = ns.Data.DISPEL_COLOR.Curse, ns.Data.DISPEL_COLOR.Poison
		ns.Auras.Removables = function() return "plain", { CUR, POI } end
		N.Refresh(friend)
		local o = friend.disp.orbs
		check("dispel: an orb per kind, in its colour, left of the bar", friend.disp:IsShown() and o[1]:IsShown() and o[2]:IsShown()
			and not o[3]:IsShown() and W.vc(o[1].dot)[1] == CUR[1] and W.vc(o[2].dot)[2] == POI[2]
			and ({ o[1]:GetPoint(1) })[1] == "RIGHT" and ({ o[1]:GetPoint(1) })[3] == "LEFT")
		check("...no frame round the plate", friend.disp.border == nil)
		ns.Auras.Removables = function() return nil end
		N.Refresh(friend)
		check("...nothing to dispel: no orbs", not friend.disp:IsShown() and not o[1]:IsShown())
		ns.Auras.Removables, ns.P.frames.dispelGlow = real, glow
		N.Refresh(friend)
	end)()
	N.Refresh(mage); N.Refresh(mob)
	check("enemy player: the coral ring round the bar, solid", mage.foe:IsShown() and mage.foe._ignoreParentAlpha == true
		and ({ mage.foe:GetPoint(1) })[2] == -2)
	check("...not on mobs", not mob.foe:IsShown())
	ns.P.plates.foeRing = false; N.Refresh(mage)
	check("...a setting", not mage.foe:IsShown())
	ns.P.plates.foeRing = true; N.Refresh(mage)
	;(function()
		-- the game's aura frame on a plate: one row over the name, icons in SITREP's look
		local uf = mage.uf
		local af = CreateFrame("Frame", nil, uf)
		af:SetPoint("BOTTOMLEFT", uf, "TOPLEFT", 0, 20)
		local row = CreateFrame("Frame", nil, af)
		af.DebuffListFrame = row
		local icon = CreateFrame("Frame", nil, row)
		icon.Icon = icon:CreateTexture()
		icon.Border = icon:CreateTexture()
		icon.Cooldown = CreateFrame("Cooldown", nil, icon)
		uf.AurasFrame = af
		local saved = S.units.target
		S.units.target = nil
		W.Fire("PLAYER_TARGET_CHANGED")
		N.Refresh(mage)
		local p1 = { af:GetPoint(1) }
		check("plate auras: one row right over the name", p1[1] == "BOTTOM" and p1[2] == mage.name and p1[3] == "TOP", tostring(p1[2]))
		check("...icons cropped, Blizzard's frame off, a thin dark edge", icon.Icon._coord and icon.Icon._coord[1] == 0.08
			and icon.Border:GetAlpha() == 0 and icon.srEdge ~= nil)
		local sc = af:GetScale()
		S.units.target = S.units.nameplate82
		W.Fire("PLAYER_TARGET_CHANGED")
		check("...your target's a little larger", af:GetScale() > sc, tostring(af:GetScale()))
		-- Blizzard places it itself: over the name again
		af:SetPoint("BOTTOMLEFT", uf, "TOPLEFT", 0, 20)
		check("...placed again when Blizzard moves it", ({ af:GetPoint(af:GetNumPoints()) })[2] == mage.name)
		local n0 = #W.prints
		SlashCmdList.SITREP("plateauras")
		local rep = table.concat(W.prints, "\n", n0 + 1)
		check("/sitrep plateauras: what each plate shows", rep:find("nameplate82 foe", 1, true) and rep:find("Debuff", 1, true), rep)
		ns.P.plates.auras = false; ns.Changed("plates.auras")
		check("off: Blizzard's place and size back", ({ af:GetPoint(1) })[2] == uf and af:GetScale() == 1)
		ns.P.plates.auras = true; ns.Changed("plates.auras")
		-- in combat a plate's parts may not be measured: the refresh goes on all the same
		ns.PlateAuras.Release(mage)
		af.GetPoint = function() error("Frame:GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
		N.Refresh(mage)
		check("plate auras: Blizzard's place unreadable (combat): still placed, the plate's refresh finished",
			({ rawget(af, "_points")[#rawget(af, "_points")] })[1][2] == mage.name and mage.track:IsShown())
		ns.P.plates.auras = false; ns.Changed("plates.auras")
		check("...and off: back over its own name", af:GetScale() == 1)
		ns.P.plates.auras = true; ns.Changed("plates.auras")
		af.GetPoint = nil
		uf.AurasFrame = nil
		S.units.target = saved
		W.Fire("PLAYER_TARGET_CHANGED")
	end)()
	;(function()
		-- your combo points on your target's plate
		local me = ns.Sensors.self
		local cls, saved = me.class, S.units.target
		me.class, S.combo, S.units.target = "ROGUE", 3, S.units.nameplate82
		N.Refresh(mage)
		local pp = mage.combo.pips
		check("combo points: pips under your target's plate, 3 lit", mage.combo:IsShown() and W.vc(pp[3])[4] == 1 and W.vc(pp[4])[4] < 0.5
			and ({ mage.cast:GetPoint(1) })[5] < -8, tostring(({ mage.cast:GetPoint(1) })[5]))
		check("...not on other plates", not mob.combo:IsShown())
		S.combo = 0
		W.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
		check("...none: no pips, the cast bar back up", not mage.combo:IsShown() and ({ mage.cast:GetPoint(1) })[5] == -8)
		me.class, S.combo, S.units.target = "MAGE", 2, saved
		N.Refresh(mage)
		check("...not for a mage", not mage.combo:IsShown())
		me.class, S.combo = cls, nil
	end)()
	;(function()
		-- you target an enemy's pet: the owner's plate says OWNER
		local mu = S.units.nameplate82
		local saved = S.units.target
		S.units.target = { name = "Wolf", guid = "Pet-0-1-0-1-7-9", isPlayer = false, hostile = true, owner = mu.name }
		W.Fire("PLAYER_TARGET_CHANGED")
		N.Refresh(mage)
		check("the pet's owner: OWNER on their plate", W.has(mage.name.line, "OWNER"), mage.name.line)
		S.units.target = saved
		W.Fire("PLAYER_TARGET_CHANGED")
		N.Refresh(mage)
		check("...gone once you target something else", not W.has(mage.name.line, "OWNER"))
	end)()
	;(function()
		-- enemy players about: mobs smaller (not your target, not one on you), friends unchanged
		local sc = ns.P.plates.scale or 1
		local onMe = S.units.nameplate80.targetingMe
		S.units.nameplate80.targetingMe = nil
		W.Update(0.6)
		mob.isTarget = false
		check("enemy players near: a mob smaller", N.EnemyPlayersNear() and math.abs(N.SizeFor(mob) - sc * ns.P.plates.mobPvpScale) < 1e-6,
			tostring(N.SizeFor(mob)))
		check("...an enemy player not", N.SizeFor(mage) == sc)
		S.units.nameplate80.targetingMe = true
		check("...a mob on you keeps its size", N.SizeFor(mob) == sc)
		S.units.nameplate80.targetingMe = nil
		ns.P.plates.mobPvpScale = 1
		check("...a setting (1: unchanged)", N.SizeFor(mob) == sc)
		ns.P.plates.mobPvpScale = 0.75
		S.units.nameplate82.dead = true
		W.Update(0.6)
		check("the enemy player dead: mobs back to size", not N.EnemyPlayersNear() and N.SizeFor(mob) == sc)
		S.units.nameplate82.dead = nil
		S.units.nameplate80.targetingMe = onMe
		W.Update(0.6)
	end)()
	-- settings
	ns.P.plates.friendly = false; ns.Changed("plates.friendly")
	check("given back: Blizzard's anchors restored", friend.hbAnchors._pts[1][4] == 0 and friend.hbAnchors._pts[1][5] == -10)
	check("friendly plates off: given back to Blizzard", N.skins.nameplate81 == nil and friend.uf.name:GetAlpha() == 1 and not friend:IsShown() and friend.uf:GetAlpha() == 1
		and friend.uf.CastBarsContainer:GetAlpha() == 1 and friend.uf.LevelFrame:GetAlpha() == 1 and friend.uf.healthBar.border:GetAlpha() == 1 and not friend.track:IsShown()
		and friend.hb:GetStatusBarTexture():GetNumMaskTextures() == 1)
	check("...enemy plates stay", N.skins.nameplate80 ~= nil)
	ns.P.plates.friendly = true; ns.Changed("plates.friendly")
	check("friendly plates back on", N.skins.nameplate81 ~= nil)
	ns.P.plates.enabled = false; ns.Changed("plates.enabled")
	check("all off: no skins", next(N.skins) == nil and col(mob) == "0.00,0.00,1.00", col(mob))
	ns.P.plates.enabled = true; ns.Changed("plates.enabled")
	check("all on again", N.skins.nameplate80 ~= nil)
	-- a plate going away
	S.units.nameplate80 = nil
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate80")
	check("removed plate: skin released", N.skins.nameplate80 == nil and not mob.active)
	for i = 81, 83 do S.units["nameplate" .. i] = nil; W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
	check("all plates gone", next(N.skins) == nil)
	C_NamePlate.GetNamePlateForUnit = realGet
	CompactUnitFrame_UpdateHealthColor = nil
	W.Update(11)
end

-- TRACKERS PER CLASS / CHARACTER (3.20) -------------------------------------------
do
	local TR = ns.Trackers
	local saved, savedSel = ns.P.trackers.items, TR.selected
	ns.P.trackers.items = {}
	local me = S.units.player
	TR.SetEditing(true) -- layout mode: every icon this character may see is shown
	local it = TR.Add("Gegenzauber", "cd")
	check("new icon: claimed by this class and character", it.class == "MAGE" and it.char == "Tobi-Forever" and it.scope == "class")
	TR.Refresh()
	check("shown for its class", TR.icons[it.id]:IsShown() and #TR.Mine() == 1)
	-- log in a warrior
	me.class, me.name = "WARRIOR", "Brocken"
	TR.Refresh()
	check("another class: hidden", not TR.icons[it.id]:IsShown() and #TR.Mine() == 0)
	-- another mage: shown again (class scope)
	me.class = "MAGE"
	TR.Refresh()
	check("another character of the class: shown", TR.icons[it.id]:IsShown())
	it.scope = "char"; TR.Refresh()
	check("this character only: hidden for the other mage", not TR.icons[it.id]:IsShown())
	it.scope = "all"; me.class = "WARRIOR"; TR.Refresh()
	check("all characters: shown even for the warrior", TR.icons[it.id]:IsShown())
	me.class, me.name = "MAGE", "Tobi"
	-- icons from older lists carry no class: the first class that knows the spell takes it
	local legacy = TR.Add("Gegenzauber", "cd")
	legacy.class, legacy.char, legacy.scope = nil, nil, nil
	IsPlayerSpell = function() return false end
	me.class = "WARRIOR"
	TR.Refresh()
	check("unclaimed icon, spell unknown: hidden, still unclaimed", not TR.icons[legacy.id]:IsShown() and legacy.class == nil)
	IsPlayerSpell = function() return true end
	me.class = "MAGE"
	TR.Refresh()
	check("unclaimed icon, spell known: claimed by this class", TR.icons[legacy.id]:IsShown() and legacy.class == "MAGE")
	IsPlayerSpell = nil
	-- the macro copy keeps whose icon it is
	it.scope, it.class, it.char = "char", "MAGE", "Tobi-Forever"
	local back = TR.Decode(TR.Encode())
	check("macro copy: scope, class and character survive", back.items[1].scope == "char" and back.items[1].class == "MAGE" and back.items[1].char == "Tobi-Forever"
		and back.items[2].scope == "class" and back.items[2].class == "MAGE")
	local old = TR.Decode("2|1|c,2139,0,0,36,100,n,0,a,c,0,0")
	check("older macro copies: unclaimed", old.items[1].class == nil and old.items[1].scope == "class")
	-- the console: only this character's icons, the others counted; the scope button cycles
	it.scope, it.class = "class", "WARRIOR"
	ns.Config.Open("trackers")
	local TP = ns.Config._page("trackers")
	TR.selected = legacy.id
	TP:Refresh()
	local listed = 0
	for _, r in ipairs(TP.list.rows) do if r:IsShown() then listed = listed + 1 end end
	check("console lists only this class's icons", listed == 1)
	check("...and counts the others", W.has(TP.listHead.t:GetText(), "+1 OTHER CLASSES") ~= nil, TP.listHead.t:GetText())
	check("scope button names the class", W.has(TP.editor.scope.label:GetText(), "ONLY") ~= nil, TP.editor.scope.label:GetText())
	TP.editor.scope._scripts.OnClick(TP.editor.scope)
	check("click: this character", legacy.scope == "char" and TP.editor.scope.label:GetText():lower() == "this character")
	TP.editor.scope._scripts.OnClick(TP.editor.scope)
	check("click: all characters", legacy.scope == "all")
	TP.editor.scope._scripts.OnClick(TP.editor.scope)
	check("click: back to the class", legacy.scope == "class")
	ns.Config.Toggle()
	TR.SetEditing(false)
	for _, x in ipairs(ns.P.trackers.items) do if TR.icons[x.id] then TR.icons[x.id]:Hide(); TR.icons[x.id] = nil end end
	ns.P.trackers.items, TR.selected = saved, savedSel
	TR.LayoutAll()
end

-- OBSOLETE SETTINGS (3.23) ---------------------------------------------------------
do
	local D = ns.Defaults()
	local old = ns.fill({
		hud = { scope = true, scopeSize = 220, northUp = false, pos = { player = { "CENTER", 10, 20 } }, frameScale = { scope = 1.2, player = 1.1 } },
		sensors = { fov = 90, rate = 7 },
		plates = { friendAlpha = 0.1 },
		threat = { matrix = { MAGE = { ROGUE = 1.4 } } },
		trackers = { items = { { id = 1, spell = 2139 } }, schema = 2, mirror = true },
		radar = { on = true },
	}, D)
	ns.prune(old, D)
	check("removed settings dropped", old.hud.scope == nil and old.hud.scopeSize == nil and old.hud.northUp == nil
		and old.sensors.fov == nil and old.plates.friendAlpha == nil and old.radar == nil and old.hud.frameScale.scope == nil)
	check("current settings kept", old.sensors.rate == 7 and old.hud.frameScale.player == 1.1 and old.plates.friendOpacity == 0.7)
	check("positions, matrix and trackers left alone", old.hud.pos.player[2] == 10 and old.threat.matrix.MAGE.ROGUE == 1.4
		and old.trackers.schema == 2 and #old.trackers.items == 1)
end

-- BLOCKED ACTIONS (3.23.1) -----------------------------------------------------------
do
	local n0 = #W.prints
	W.Fire("ADDON_ACTION_BLOCKED", "SITREP", "UNKNOWN()")
	W.Fire("ADDON_ACTION_BLOCKED", "SITREP", "UNKNOWN()")
	W.Fire("ADDON_ACTION_FORBIDDEN", "SITREP", "CompactPartyFrame:Hide()")
	local r = SITREP_DB.reports.blocked
	check("blocked actions saved, newest first", r and #r.lines == 3 and r.lines[1]:find("FORBIDDEN SITREP: CompactPartyFrame:Hide%(%) %(out of combat%)") ~= nil, r and r.lines[1])
	check("...mentioned in chat once per function", #W.prints - n0 == 2, #W.prints - n0)
	for _ = 1, 40 do W.Fire("ADDON_ACTION_BLOCKED", "SITREP", "UNKNOWN()") end
	check("...the last 30 kept", #r.lines == 30)
	SITREP_DB.reports.blocked = nil
end

-- ITEM RANGE CHECKS (3.25) ---------------------------------------------------------
do
	local Sn = ns.Sensors
	-- this client knows a few items of the Forever tables: 5, 15, 25 and 35 yd (harm and friend)
	W.rangeItems = { [8149] = 5, [4559] = 15, [1251] = 15, [13289] = 25, [18904] = 35 }
	Sn.BuildRangeChecks()
	S.units.target = { name = "Wolf", guid = "Creature-0-9-1", class = "WARRIOR", level = 10, isPlayer = false, hostile = true, dist = 13 }
	local lo, hi = Sn.MeasureRange("target")
	check("out of combat: items narrow the bracket (13 yd -> 10-15)", lo == 10 and hi == 15, lo .. "-" .. tostring(hi))
	S.units.target.dist = 3
	lo, hi = Sn.MeasureRange("target")
	check("...melee range measurable (3 yd -> 0-5)", lo == 0 and hi == 5, lo .. "-" .. tostring(hi))
	S.units.target.dist = 22
	S.me.combat = true
	lo, hi = Sn.MeasureRange("target")
	check("in combat: items still answer for enemies (22 yd -> 20-25)", lo == 20 and hi == 25, lo .. "-" .. tostring(hi))
	-- a friend in combat: the protected checks are not asked at all (spells only)
	local blocked0 = W.blockedCalls
	local ally = { name = "Freund", guid = "Player-1-7777", class = "PRIEST", level = 60, isPlayer = true, hostile = false, faction = "Alliance", dist = 13 }
	S.units.party3 = ally
	lo, hi = Sn.MeasureRange("party3", nil, Sn.helpChecks)
	check("friend in combat: no protected check asked (no blocked action)", W.blockedCalls == blocked0, W.blockedCalls - blocked0)
	check("...spells only for it (13 yd -> 0-40)", hi == 40, lo .. "-" .. tostring(hi))
	S.me.combat = false
	lo, hi = Sn.MeasureRange("party3", nil, Sn.helpChecks)
	check("friend out of combat: interact and items again (13 yd -> 10-15)", lo == 10 and hi == 15, lo .. "-" .. tostring(hi))
	S.units.party3 = nil
	-- items this client does not know are dropped after a while
	for _ = 1, 30 do Sn.MeasureRange("target") end
	local used = {}
	for _, c in ipairs(Sn.checks) do if c.kind == "item" then used[#used + 1] = c.id end end
	table.sort(used)
	check("only items the client knows are asked", table.concat(used, ",") == "4559,8149,13289,18904", table.concat(used, ","))
	-- the probe
	SlashCmdList.SITREP("rangeprobe")
	local rep = table.concat(SITREP_DB.reports.rangeprobe.lines, "\n")
	check("range probe: items listed per step with answers", rep:find(" 25 yd: 1 of 1 known; 13289 Item 13289=", 1, true) ~= nil and rep:find("item steps answering: 4 of 10", 1, true) ~= nil, rep)
	check("...and SITREP's bracket", rep:find("SITREP's bracket now: 20-25y", 1, true) ~= nil, rep)
	ns.P.sensors.useItemRange = false; ns.Changed("sensors.useItemRange")
	lo, hi = Sn.MeasureRange("target")
	check("switched off: spells and interact only", lo == 20 and hi == 28)
	ns.P.sensors.useItemRange = true
	W.rangeItems = nil
	Sn.BuildRangeChecks()
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
end

-- DRUIDS: MANA IN FORMS, SHIFT COST (3.28) ------------------------------------------
do
	local PFd = ns.Frames.frames.player
	local me = S.units.player
	local saved = { class = me.class, powerType = me.powerType, power = me.power, powerMax = me.powerMax }
	W.otherSpells[#W.otherSpells + 1] = { id = 5487, name = "Bärengestalt", cost = 520 }
	W.otherSpells[#W.otherSpells + 1] = { id = 768, name = "Katzengestalt", cost = 480 }
	me.class = "DRUID"
	-- in Cat Form: energy on the power bar, mana under it, the cat's cost marked
	S.forms = { { spell = 5487 }, { spell = 768, active = true } }
	me.powerType, me.power, me.powerMax, me.mana, me.manaMax = 3, 80, 100, 600, 2000
	W.Update(0.25)
	check("cat form: mana bar under the energy", PFd.mana:IsShown() and PFd.mana._value == 600 and PFd.mana._max == 2000, tostring(PFd.mana._value))
	check("...the cat's shift cost marked, white at half opacity while affordable", PFd.manaTick:IsShown() and W.vc(PFd.manaTick)[2] == 1 and W.vc(PFd.manaTick)[3] == 1 and W.vc(PFd.manaTick)[4] == 0.5 and not PFd.powerTick:IsShown())
	me.mana = 300
	W.Update(0.25)
	check("...red when the mana is not enough", W.vc(PFd.manaTick)[1] == 1 and W.vc(PFd.manaTick)[2] < 0.3)
	-- hovering a mana spell in a form: its cost on the mana bar, not on the energy bar
	W.otherSpells[#W.otherSpells + 1] = { id = 5185, name = "Heilende Berührung", cost = 250 }
	ns.Frames.SetCostHover(5185)
	check("cat form, mana spell hovered: cost on the mana bar", PFd.manaCost:IsShown() and PFd.manaCost._value == 250 and not PFd.cost:IsShown())
	check("...affordable: light blue", PFd.manaCost._sbColor[3] > 0.9 and not PFd.manaCostShort:IsShown())
	me.mana = 100
	ns.Frames.UpdateCost()
	check("...not affordable: red, and the missing part shown", PFd.manaCost._sbColor[3] < 0.5 and PFd.manaCostShort:IsShown())
	ns.Frames.SetCostHover(nil)
	check("...gone when the mouse leaves", not PFd.manaCost:IsShown())
	W.otherSpells[#W.otherSpells] = nil
	me.mana = 300
	W.Update(0.25)
	-- shifting into Bear Form: the bar is redrawn the moment the type changes
	S.forms[2].active, S.forms[1].active = nil, true
	me.powerType, me.power, me.powerMax = 0, 1500, 2000
	W.Update(0.25)
	me.powerType, me.power, me.powerMax = 1, 0, 100 -- the client switches to rage
	W.Fire("UNIT_DISPLAYPOWER", "player")
	check("bear form: rage bar empty at once, no stale mana fill", PFd.power._value == 0 and PFd.power._max == 100, tostring(PFd.power._value) .. "/" .. tostring(PFd.power._max))
	check("...in rage colour", PFd.power._sbColor and PFd.power._sbColor[1] == 1 and PFd.power._sbColor[3] < 0.5)
	-- hovering the bear form (a mana cost) while in rage: no cost drawn against the rage bar
	ns.Frames.SetCostHover(5487)
	check("...a form's mana cost is not drawn on the rage bar", not PFd.cost:IsShown())
	ns.Frames.SetCostHover(nil)
	S.forms[1].active = nil
	-- caster form: the power bar is the mana; the form you were in last marked on it
	S.forms[2].active = nil
	me.powerType, me.power, me.powerMax = 0, 600, 2000
	W.Update(0.25)
	check("caster form: no extra bar, the next shift marked on the mana bar", not PFd.mana:IsShown() and PFd.powerTick:IsShown() and not PFd.manaTick:IsShown())
	check("caster form: the form you were in last (bear)", select(2, ns.Frames.FormCosts()) == 520, select(2, ns.Frames.FormCosts()))
	-- Aquatic Form (cheap, rarely used) does not pull the mark to the left (seen at level 16)
	W.otherSpells[#W.otherSpells + 1] = { id = 1066, name = "Wassergestalt", cost = 16 }
	S.forms[3] = { spell = 1066 }
	ns.Frames.lastFormSpell = nil
	check("never shifted: the dearest combat form, not Aquatic Form", select(2, ns.Frames.FormCosts()) == 520)
	S.swimming = true
	check("swimming: Aquatic Form", select(2, ns.Frames.FormCosts()) == 16)
	S.swimming = nil
	S.forms[3] = nil
	W.otherSpells[#W.otherSpells] = nil
	ns.P.frames.druidMana = false
	W.Update(0.25)
	check("switched off: no mana bar, no marks", not PFd.mana:IsShown() and not PFd.powerTick:IsShown())
	ns.P.frames.druidMana = true
	-- other classes never see it
	me.class, S.forms = "MAGE", nil
	me.powerType = 3
	W.Update(0.25)
	check("not a druid: nothing", not PFd.mana:IsShown() and not PFd.manaTick:IsShown() and not PFd.powerTick:IsShown())
	me.class, me.powerType, me.power, me.powerMax, me.mana, me.manaMax = saved.class, saved.powerType, saved.power, saved.powerMax, nil, nil
	W.otherSpells[#W.otherSpells] = nil; W.otherSpells[#W.otherSpells] = nil
	W.Update(0.25)
	check("druid mana bar is slim (2 px)", PFd.mana._h == 2)
end

-- HEAL PREDICTION (3.2) -------------------------------------------------------------
local HP = ns.Heals
check("lowest heal, German", HP.ParseMin("Heilt ein freundliches Ziel um 812 bis 944 Punkte.") == 812)
check("lowest heal, English", HP.ParseMin("Heals a friendly target for 1,204 to 1,398.") == 1204)
check("lowest heal, French", HP.ParseMin("Rend 812 à 944 points de vie à une cible alliée.") == 812)
check("lowest heal, Russian", HP.ParseMin("Восстанавливает 812 до 944 ед. здоровья.") == 812)
check("lowest heal, dash", HP.ParseMin("Heals 812-944 health.") == 812)
check("lowest heal: other numbers skipped", HP.ParseMin("Heals 3 nearby allies for 500 to 600 over 6 sec.") == 500)
check("no range in the text: nothing", HP.ParseMin("Heals the target for 450 over 15 sec.") == nil)
check("empty text: nothing", HP.ParseMin("") == nil and HP.ParseMin(nil) == nil)

wipeContacts(C)
for k in pairs(S.units) do if k:match("^nameplate") then S.units[k] = nil end end
S.group.n = 1
local pal = { name = "Healme", guid = "Player-1-5000", class = "PALADIN", level = 60, isPlayer = true, hostile = false,
	faction = "Alliance", wx = 8, wy = 0, hp = 2000, hpMax = 5000 }
S.units.party1 = pal
S.units.target = pal
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
local TFh = ns.Frames.frames.target
local hh = TFh.hp.heal
check("target frame has a heal overlay", hh and hh.all and hh.mine)
check("no heals coming: nothing drawn", not hh.all:IsShown() and not hh.mine:IsShown())
-- you cast Flash Heal on it; the client predicts 900, the tooltip says 812 to 944
pal.incHeal, pal.incHealMine = 900, 900
S.units.player.casting, S.units.player.castSpell, S.units.player.castName = true, 2061, "Flash Heal"
W.Update(0.25)
check("your heal: the lowest amount (812), not the client's 900", hh.mine:IsShown() and hh.mine._value == 812, hh.mine._value)
check("drawn against max health", hh.mine._max == 5000)
check("all heals = yours only", hh.all._value == 812, hh.all._value)
-- a second healer adds 600
pal.incHeal = 1500
W.Fire("UNIT_HEAL_PREDICTION", "target")
check("heal event redraws at once (no tick)", hh.all._value == 1412, hh.all._value)
check("yours on top, brighter", hh.mine._value == 812 and hh.mine:GetFrameLevel() >= hh.all:GetFrameLevel())
-- only the other healer
pal.incHeal, pal.incHealMine = 600, 0
S.units.player.casting = nil
W.Update(0.25)
check("others' heal only: the client's prediction", hh.all._value == 600 and not hh.mine:IsShown(), hh.all._value)
-- your heal without a range in its text: the client's number
pal.incHeal, pal.incHealMine = 900, 900
S.units.player.casting, S.units.player.castSpell = true, 133 -- a spell with no description in the emulator
W.Update(0.25)
check("no tooltip range: the client's number", hh.mine._value == 900, hh.mine._value)
-- in combat the numbers can be secret: the client's values go straight to the bars
S.secret = { heals = true }
W.Update(0.25)
check("secret heals still drawn", hh.all:IsShown() and hh.mine:IsShown() and issecretvalue(hh.all._value))
S.secret = nil
-- allies panel row and the player frame use the same overlay
W.Update(0.25)
local arh = ns.HUD.modules.allies.rows[1]
check("allies row: heal overlay fed", arh.hp.heal and arh.hp.heal.all:IsShown() and arh.hp.heal.all._value == 900, arh.hp.heal and arh.hp.heal.all._value)
pal.incHeal, pal.incHealMine = 300, 0
W.Fire("UNIT_HEAL_PREDICTION", "party1")
check("allies row: redrawn on the heal event", arh.hp.heal.all._value == 300, arh.hp.heal.all._value)
S.units.player.incHeal = 400
W.Update(0.25)
local PFh = ns.Frames.frames.player.hp.heal
check("player frame: incoming heals on the health bar", PFh and PFh.all:IsShown() and PFh.all._value == 400)
S.units.player.incHeal, S.units.player.casting, S.units.player.castSpell, S.units.player.castName = nil, nil, nil, nil
pal.incHeal, pal.incHealMine = nil, nil
S.units.target, S.units.party1, S.group.n = nil, nil, 0
W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.25)
check("no target: overlay cleared", not hh.all:IsShown() and not hh.mine:IsShown())
W.Update(11)

-- Automatic diagnostics land in the saved variables without any command.
W.Update(5.1)
local diag = SITREP_DB.diag
check("auto diagnostics stored", diag and #diag.samples >= 1 and diag.locale == "deDE")
local d1 = diag and diag.samples[#diag.samples]
check("diag sample lists contacts", d1 and d1.position ~= nil and d1.contactList[1] ~= nil, d1 and tostring(#d1.contactList))
ns.error("synthetic failure for the test")
check("internal errors persisted", SITREP_DB.errors and SITREP_DB.errors[#SITREP_DB.errors] == "synthetic failure for the test")
ns.errorCounts["synthetic failure for the test"] = nil
S.units.nameplate11 = nil
wipeContacts(C)
W.Update(0.25)

-- Flight recorder
S.units.nameplate7 = { name = "Rook", guid = "Player-2-0077", class = "HUNTER", level = 30, isPlayer = true, hostile = true,
	faction = "Horde", dist = 22, screenX = 1100 }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
W.Update(0.25)
local okd, errd = pcall(SlashCmdList.SITREP, "debug")
check("/sitrep debug starts", okd, errd)
for _ = 1, 15 do W.Update(0.25); W.RunTickers() end
local dbg = SITREP_DB.debug
check("recorder saved 16 samples", dbg and #dbg.samples == 16, dbg and #dbg.samples)
local s1 = dbg and dbg.samples[1]
local u1 = s1 and s1.units[1]
check("recorder captured the plate pipeline", u1 and u1.hostile == "true" and u1.range == "20-28", u1 and (u1.hostile .. " " .. u1.range))
check("recorder saw the pipeline running", s1 and s1.ticks > 0 and s1.pictures > 0)
check("recorder saw an envelope lane drawn", dbg and dbg.samples[#dbg.samples].lanesShown >= 1)
check("recorder told the user to /reload", W.prints[#W.prints]:find("/reload", 1, true))

-- Identity fully secret: the contact is kept under its unit token.
S.secret = { guid = true, name = true }
W.Update(0.25)
local tokenContact = C["U:nameplate7"]
check("secret GUID and name: contact kept by unit token", tokenContact ~= nil and tokenContact.name == "Unknown")
S.secret = nil
S.units.nameplate7 = nil
W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate7")

-- INTERFACE: MINIMAP, EXPERIENCE, BAGS, CHAT (3.29) ----------------------------------
do
	S.me.combat = false
	local U = ns.P.ui
	-- minimap: square, sized, Blizzard's decor hidden, zone and coordinates shown
	local MM = ns.Minimap
	check("minimap: rounded mask", (Minimap._mask or ""):find("mapmask", 1, true), Minimap._mask)
	check("minimap: sized from the setting", Minimap._w == U.mapSize and Minimap._h == U.mapSize, tostring(Minimap._w))
	check("minimap: round border hidden", MinimapCompassTexture:IsShown() == false and MinimapCluster.BorderTop:IsShown() == false)
	check("minimap: zoom buttons hidden", Minimap.ZoomIn:IsShown() == false)
	Minimap.ZoomIn:Show() -- Blizzard shows it on mouse-over
	check("...and stay hidden when Blizzard shows them", Minimap.ZoomIn:IsShown() == false and Minimap.ZoomIn:GetAlpha() == 0)
	MM.Refresh()
	check("minimap: zone shown", MM.frame.zone:GetText() == "Brachland", MM.frame.zone:GetText())
	check("minimap: zone in its PvP colour (contested: orange)", MM.frame.zone._tc[1] == 1 and MM.frame.zone._tc[2] == 0.7)
	check("minimap: coordinates", MM.frame.coords:GetText():sub(1, 10) == "52.3, 41.8", MM.frame.coords:GetText())
	U.mapCoords = false; MM.Refresh()
	check("coordinates off: none", MM.frame.coords:GetText() == "")
	U.mapCoords = true
	-- mouse wheel zoom
	Minimap._zoom = 2
	Minimap._scripts.OnMouseWheel(Minimap, 1)
	check("wheel up zooms in", Minimap._zoom == 3, Minimap._zoom)
	Minimap._zoom = 0
	Minimap._scripts.OnMouseWheel(Minimap, -1)
	check("wheel cannot zoom out past 0", Minimap._zoom == 0)
	-- the grip: only while the HUD is unlocked; dragging resizes and saves
	check("grip hidden while the HUD is locked", ns.P.hud.locked and not MM.frame.grip:IsVisible())
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	check("grip shown while unlocked", MM.frame.grip:IsVisible())
	local grip = MM.frame.grip
	S.cursorX = 500
	grip._scripts.OnMouseDown(grip)
	S.cursorX = 440 -- 60 px left: bigger (the grip sits bottom left)
	grip._scripts.OnUpdate(grip, 0.1)
	grip._scripts.OnMouseUp(grip)
	check("dragging the grip resizes the map", U.mapSize == 240 and Minimap._w == 240, U.mapSize)
	S.cursorX = 500
	grip._scripts.OnMouseDown(grip)
	S.cursorX = 900
	grip._scripts.OnUpdate(grip, 0.1)
	grip._scripts.OnMouseUp(grip)
	check("...within its range", U.mapSize == MM.MIN, U.mapSize)
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	U.mapSize = 180
	-- off: round again, original size, decor back
	U.minimap = false; ns.Changed("ui.minimap")
	check("minimap off: round mask back", Minimap._mask == "Textures\\MinimapMask")
	check("minimap off: original size", Minimap._w == 140, Minimap._w)
	check("minimap off: decor back", MinimapCompassTexture:IsShown() and MinimapCompassTexture:GetAlpha() == 1)
	check("minimap off: frame hidden", not MM.frame:IsShown())
	U.minimap = true; ns.Changed("ui.minimap")
	check("minimap on again", Minimap._w == 180 and MM.frame:IsShown())

	-- experience: a line on the player frame, rested ahead of it
	local X = ns.XP
	S.me.xp, S.me.xpMax, S.me.rested, S.me.maxLevel = 1200, 4800, 900, 70
	W.Fire("PLAYER_XP_UPDATE", "player")
	check("xp line shown", X.bar:IsShown())
	check("xp line: experience", X.bar:GetValue() == 1200 and select(2, X.bar:GetMinMaxValues()) == 4800)
	check("xp line: rested ahead of it", X.bar.rested:GetValue() == 2100, X.bar.rested:GetValue())
	S.me.rested = 9000; W.Fire("UPDATE_EXHAUSTION")
	check("rested stops at the end of the level", X.bar.rested:GetValue() == 4800)
	X.bar.hover._scripts.OnEnter(X.bar.hover)
	check("hover: numbers", GameTooltip:Text():find("1200 / 4800", 1, true) and GameTooltip:Text():find("Rested 9000", 1, true), GameTooltip:Text())
	X.bar.hover._scripts.OnLeave(X.bar.hover)
	check("Blizzard's xp bar hidden", MainStatusTrackingBarContainer:IsShown() == false)
	S.me.maxLevel = 60 -- the test character is 60
	W.Fire("PLAYER_LEVEL_UP")
	check("at the level cap: no xp line", not X.bar:IsShown())
	S.me.maxLevel = 70; W.Fire("PLAYER_XP_UPDATE", "player")
	U.xp = false; ns.Changed("ui.xp")
	check("xp off: no line, Blizzard's bar back", not X.bar:IsShown() and MainStatusTrackingBarContainer:IsShown())
	U.xp = true; ns.Changed("ui.xp")
	check("xp on again", X.bar:IsShown() and not MainStatusTrackingBarContainer:IsShown())
	S.me.rested, S.me.maxLevel = nil, nil

	-- a hunter's pet: its experience on a line along the pet frame's bottom
	local savedPet = S.units.pet
	S.units.pet = { name = "Wuffi", guid = "Pet-0-1-0-1-1-6000", level = 20, isPlayer = false, hp = 500, hpMax = 500 }
	S.petXP = { 300, 1200 }
	W.Fire("UNIT_PET", "player")
	check("pet xp line under the pet frame", X.petBar and X.petBar:IsShown() and X.petBar:GetValue() == 300
		and select(2, X.petBar:GetMinMaxValues()) == 1200 and X.petBar:GetParent() == ns.Frames.pet)
	S.petXP = { 900, 1200 }; W.Fire("UNIT_PET_EXPERIENCE", "player")
	check("pet xp: follows its gains", X.petBar:GetValue() == 900)
	X.petBar.hover._scripts.OnEnter(X.petBar.hover)
	check("pet xp hover: numbers", GameTooltip:Text():find("900 / 1200", 1, true), GameTooltip:Text())
	X.petBar.hover._scripts.OnLeave(X.petBar.hover)
	S.petXP = { 0, 0 }; W.Fire("UNIT_PET_EXPERIENCE", "player")
	check("a pet that does not learn (a warlock's): no line", not X.petBar:IsShown())
	S.units.pet, S.petXP = savedPet, nil
	W.Fire("UNIT_PET", "player")

	-- bags: free slots, click opens, right-click shows the bag bar
	local B = ns.Bags
	W.Fire("BAG_UPDATE_DELAYED")
	check("bag button shown", B.button:IsShown())
	check("bag button: free slots", B.button.text:GetText():find("10|r/54", 1, true), B.button.text:GetText())
	-- Blizzard's bag bar: invisible and click-through, not hidden (hiding it from an
	-- addon taints the bags: a potion from them was then blocked in combat)
	local function barGone() return BagsBar:GetAlpha() == 0 and BagsBar:IsMouseEnabled() == false
		and MainMenuBarBackpackButton:IsMouseEnabled() == false end
	local function barBack() return BagsBar:GetAlpha() == 1 and BagsBar:IsMouseEnabled() == true
		and MainMenuBarBackpackButton:IsMouseEnabled() == true end
	check("Blizzard's bag bar invisible and click-through (not hidden)", barGone() and BagsBar:IsShown())
	-- a click opens the bags through Blizzard's backpack button (a secure click)
	local bb = B.button
	check("click: a secure click on Blizzard's backpack button", bb:GetAttribute("type1") == "click"
		and bb:GetAttribute("clickbutton1") == MainMenuBarBackpackButton)
	bb:GetAttribute("clickbutton1"):Click() -- (what the secure click does)
	check("...which opens the bags", W.bagsToggled == 1, W.bagsToggled)
	bb._scripts.OnClick(bb, "RightButton")
	check("right-click shows the bag bar", barBack())
	bb._scripts.OnClick(bb, "RightButton")
	check("...and hides it again", barGone())
	S.bags = { { 2, 16 }, { 1, 14 } }
	W.Fire("BAG_UPDATE_DELAYED")
	check("few free: red", bb.text:GetText():find("ff5555", 1, true), bb.text:GetText())
	S.bags = { { 7, 16 } }
	W.Fire("BAG_UPDATE_DELAYED")
	check("under 10 free: orange", bb.text:GetText():find("ffa040", 1, true), bb.text:GetText())
	S.bags = nil
	U.bags = false; ns.Changed("ui.bags")
	check("bags off: no button, Blizzard's bar back", not bb:IsShown() and barBack())
	U.bags = true; ns.Changed("ui.bags")
	S.me.combat = true
	BagsBar._protected = true -- (in case it is: its mouse may only change after combat)
	bb._scripts.OnClick(bb, "RightButton")
	check("in combat: the bag bar shows at once, its mouse after combat", BagsBar:GetAlpha() == 1 and BagsBar:IsMouseEnabled() == false)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	check("...after combat: clickable", barBack())
	BagsBar._protected = nil
	bb._scripts.OnClick(bb, "RightButton")
	check("then gone again on right-click", barGone())

	-- chat: SITREP draws it, Blizzard's windows stay the engine
	local cf = ChatFrame2
	check("chat: text size with an outline, the game's font kept", cf._font[2] == U.chatSize and cf._font[3] == "OUTLINE"
		and cf._font[1] == "Fonts\\ARIALN.TTF")
	check("chat: Blizzard's background gone, SITREP's pane behind each window", ChatFrame2Background:GetAlpha() == 0
		and ChatFrame2.srShell and ChatFrame2.srShell:IsShown() and ChatFrame1.srShell:IsShown())
	check("chat: no fading (the pane holds the messages)", cf._fading == false)
	check("chat: Blizzard's button column gone, its menu button in SITREP's bar with SITREP's icon", ChatFrame2ButtonFrame:GetAlpha() == 0
		and ChatFrameMenuButton:GetParent() == ns.Chat.bar and ChatFrameMenuButton.srIcon:IsShown() and ns.Chat.bar:IsShown())
	check("chat: Blizzard's tab alphas all 1 (SITREP fades the tab bar)", CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA == 1 and ChatFrame2Tab.noMouseAlpha == 1)
	check("chat: input line in SITREP's style", ChatFrame2EditBoxMid:GetAlpha() == 0 and ChatFrame2EditBox.srSkin:IsShown())
	check("chat: goes right to the screen's edge (no room kept for Blizzard's buttons)", ChatFrame1._clamp[1] == ns.Chat.CLAMP[1]
		and ChatFrame1._clamp[1] > -35 and ChatFrame2._clamp[3] == ns.Chat.CLAMP[3])
	U.chatSize = 9; ns.Changed("ui.chatSize")
	check("chat: size follows the setting", cf._font[2] == 9)
	U.chat = false; ns.Changed("ui.chat")
	check("chat off: size, background, tab alphas and fading back", cf._font[2] == 14 and cf._font[3] == "" and ChatFrame2Background:GetAlpha() == 1
		and CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA == 0.2 and cf._visible == 120 and cf._fading == true and not ChatFrame2EditBox.srSkin:IsShown())
	check("chat off: Blizzard's room by the edge back", ChatFrame1._clamp[1] == -35 and ChatFrame1._clamp[4] == -50)
	check("chat off: Blizzard's button back where it was, no pane, no bar", ChatFrameMenuButton:GetParent() == UIParent
		and not ChatFrameMenuButton.srIcon:IsShown() and not ChatFrame2.srShell:IsShown() and not ns.Chat.bar:IsShown())
	U.chat, U.chatSize = true, 11; ns.Changed("ui.chat")

	-- moving: the minimap and the chat get a handle while the HUD is unlocked
	local mapMover, chatMover = ns.Minimap.mover, ns.Chat.mover
	check("movers hidden while the HUD is locked", not mapMover:IsShown() and not chatMover:IsShown())
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	check("unlocked: a handle on the map and on the chat", mapMover:IsShown() and chatMover:IsShown())
	check("the resize grip sits on the map's handle", MM.frame.grip:GetParent() == mapMover)
	Minimap._x, Minimap._y = 1700, 840 -- dropped near the top right (right edge 1880, top 1020)
	mapMover._scripts.OnDragStart(mapMover)
	mapMover._scripts.OnDragStop(mapMover)
	local mp = ns.P.hud.pos.minimap
	check("map: place kept by its top right corner", mp and mp[1] == "TOPRIGHT" and mp[3] == -40 and mp[4] == -60,
		mp and table.concat({ tostring(mp[3]), tostring(mp[4]) }, ","))
	local p1 = { Minimap:GetPoint(1) }
	check("map: anchored there", p1[1] == "TOPRIGHT" and p1[2] == UIParent and p1[4] == -40 and p1[5] == -60)
	MinimapCluster.Layout = function() Minimap:ClearAllPoints(); Minimap:SetPoint("CENTER", MinimapCluster, "CENTER", 0, 0) end
	ChatFrame1._x, ChatFrame1._y = 400, 300
	chatMover._scripts.OnDragStart(chatMover)
	chatMover._scripts.OnDragStop(chatMover)
	local cp = ns.P.hud.pos.chat
	check("chat: place kept by its bottom left corner", cp and cp[1] == "BOTTOMLEFT" and cp[3] == 400 and cp[4] == 300)
	FCF_RestorePositionAndDimensions(ChatFrame1) -- Blizzard puts it back at its saved place
	local c1 = { ChatFrame1:GetPoint(1) }
	check("chat: stays where it was dragged after Blizzard's restore", c1[1] == "BOTTOMLEFT" and c1[4] == 400 and c1[5] == 300,
		tostring(c1[4]))
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	check("locked again: handles gone, places kept", not chatMover:IsShown() and ns.P.hud.pos.chat ~= nil)
	U.chat = false; ns.Changed("ui.chat")
	c1 = { ChatFrame1:GetPoint(1) }
	check("chat off: Blizzard's place back", c1[1] == "BOTTOMLEFT" and c1[4] == 32 and c1[5] == 95, tostring(c1[4]))
	U.chat = true; ns.Changed("ui.chat")
	c1 = { ChatFrame1:GetPoint(1) }
	check("chat on: SITREP's place again", c1[4] == 400)
	ns.P.hud.pos = {}; ns.Changed("hud.pos") -- Layout: reset positions
	c1 = { ChatFrame1:GetPoint(1) }
	check("reset positions: chat back at Blizzard's place", c1[4] == 32 and ns.P.hud.pos.chat == nil)
	Minimap._x, Minimap._y = nil, nil

	-- chat: Blizzard fading the window in on mouse-over does not bring it back
	W.ChatHover(ChatFrame2)
	check("hover: background stays hidden (textures too)", not ChatFrame2Background:IsShown() and not ChatFrame2TopLeftTexture:IsShown())
	check("hover: button column stays hidden", not ChatFrame2ButtonFrame:IsShown())
	check("tabs: Blizzard's per-tab alpha 1 too (SITREP fades them)", ChatFrame2Tab.noMouseAlpha == 1)
	-- Blizzard setting its size again (login, size menu): SITREP's size stays, Blizzard's is what comes back
	FCF_SetChatWindowFontSize(nil, ChatFrame2, 16)
	check("Blizzard's size call: SITREP's size on top", ChatFrame2._font[2] == U.chatSize and ChatFrame2._font[3] == "OUTLINE")
	U.chat = false; ns.Changed("ui.chat")
	check("...and off gives back the size Blizzard set last", ChatFrame2._font[2] == 16, ChatFrame2._font[2])
	check("off: background and tabs back", ChatFrame2Background:IsShown() and ChatFrame2Background:GetAlpha() == 1
		and ChatFrame2Tab.noMouseAlpha == 0.2)
	U.chat = true; ns.Changed("ui.chat")
	FCF_SetChatWindowFontSize(nil, ChatFrame2, 14)
	-- the input field lies under the text: textures of the edit box, in its background layer
	local skin = ChatFrame2EditBox.srSkin
	local skinBox = ns.Kit.Region(skin.bg)
	check("input field drawn behind the typed text", skinBox:GetParent() == ChatFrame2EditBox and skinBox._kind == "Texture")

	-- tabs: Blizzard's art off, SITREP's plate on, a line under the selected one
	check("tabs: Blizzard's art hidden", ChatFrame1TabLeft:GetAlpha() == 0 and ChatFrame2TabSelectedMiddle:GetAlpha() == 0)
	check("tabs: SITREP's plate behind the name", ChatFrame2Tab.srPlate:IsShown() and ChatFrame2TabText:GetAlpha() == 1)
	check("tabs: line under the selected tab only", ChatFrame1Tab.srLine:IsShown() and not ChatFrame2Tab.srLine:IsShown())
	FCF_Tab_OnClick(ChatFrame2Tab)
	check("switching tabs moves the line", ChatFrame2Tab.srLine:IsShown() and not ChatFrame1Tab.srLine:IsShown())
	FCF_Tab_OnClick(ChatFrame1Tab)
	check("new-message glow: an accent bar on the plate", ChatFrame2TabGlow:GetTexture() == "Interface\\Buttons\\WHITE8X8"
		and ({ ChatFrame2TabGlow:GetPoint(1) })[2] == ChatFrame2Tab.srPlate)
	U.chat = false; ns.Changed("ui.chat")
	check("chat off: Blizzard's tabs back", ChatFrame1TabLeft:GetAlpha() == 1 and not ChatFrame1Tab.srPlate:IsShown()
		and ChatFrame2TabGlow:GetTexture() == "Interface\\ChatFrame\\ChatFrameTab-NewMessage"
		and ({ ChatFrame2TabGlow:GetPoint(1) })[2] == ChatFrame2Tab)
	U.chat = true; ns.Changed("ui.chat")

	-- the console page and the dump
	ns.Config.Open("interface")
	check("interface page opens", ns.Config._page("interface") ~= nil)
	ns.Config.Toggle()
	local n0 = #W.prints
	SlashCmdList.SITREP("uidump")
	local dump = table.concat(W.prints, "\n", n0 + 1)
	check("uidump lists the frames", dump:find("map decor:", 1, true) and dump:find("bag bar: BagsBar", 1, true)
		and dump:find("10 of 54 free", 1, true), dump)
	-- SITREP off: everything Blizzard's again
	ns.P.enabled = false; ns.Changed("enabled")
	check("SITREP off: minimap round", Minimap._mask == "Textures\\MinimapMask")
	check("SITREP off: Blizzard's bags", not B.button:IsShown() and BagsBar:IsShown() and BagsBar:GetAlpha() == 1)
	check("SITREP off: chat as it was", cf._font[2] == 14)
	check("SITREP off: Blizzard's xp bar", MainStatusTrackingBarContainer:IsShown())
	ns.P.enabled = true; ns.Changed("enabled")
end

-- QUESTS: TRACKER, LEARNED PLACES, NAVIGATION ARROW (3.30) ---------------------------
do
	S.me.combat = false
	local Q, QT, QA = ns.Quests, ns.QuestTracker, ns.QuestArrow
	S.mapId, S.mapPos, S.me.facing = 1429, { 0.50, 0.50 }, 0
	S.quests = {
		{ id = 101, title = "Kobold Camp Cleanup", level = 7, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 3/8" } } },
		{ id = 102, title = "Wolves Across the Border", level = 6, zone = "Elwynn Forest", objectives = { { "Tough Wolf Meat: 2/8" } } },
		{ id = 103, title = "Report to Goldshire", level = 5, zone = "Elwynn Forest", objectives = {}, complete = true },
		{ id = 104, title = "The Defias Brotherhood", level = 14, zone = "Westfall", objectives = { { "Defias Messenger slain: 0/1" } } },
	}
	W.Fire("QUEST_LOG_UPDATE")
	check("quest list from the classic log", #Q.List() == 4 and Q.List()[1].zone == "Elwynn Forest")
	check("objective counts read from the text", Q.List()[1].objectives[1].have == 3 and Q.List()[1].objectives[1].need == 8)
	check("finished quest is complete", Q.List()[3].complete)
	check("objective text: count first", QT.ObjectiveText(Q.List()[1].objectives[1]) == "3/8 Kobold Vermin slain")
	check("tracker shown, Blizzard's hidden", QT.frame:IsShown() and not QuestWatchFrame:IsShown())
	check("no places known yet: no distances", QT.frame.rows[1].dist:GetText() == "")
	check("arrow hidden: nothing to navigate to", not QA.frame:IsShown())

	-- learning: a counter goes up where you stand
	S.mapPos = { 0.60, 0.50 }
	S.quests[1].objectives[1][1] = "Kobold Vermin slain: 4/8"
	W.Fire("QUEST_LOG_UPDATE")
	local learned = Q.Store()[101]
	check("progress learned at your place", learned and learned.obj[1][1].x == 0.60, learned and learned.obj and #learned.obj[1])
	S.mapPos = { 0.64, 0.50 }
	S.quests[1].objectives[1][1] = "Kobold Vermin slain: 5/8"
	W.Fire("QUEST_LOG_UPDATE")
	-- accepting: where you stand is where the quest giver is
	S.mapPos = { 0.40, 0.70 }
	table.insert(S.quests, { id = 105, title = "Princess Must Die!", level = 9, zone = "Elwynn Forest", objectives = { { "Princess slain: 0/1" } } })
	W.Fire("QUEST_ACCEPTED", 5, 105)
	check("accepted: giver place kept", Q.Store()[105] and Q.Store()[105].giver.y == 0.70)
	-- collapsing a zone header hides quests from the list: nothing forgotten, nothing "accepted"
	S.questCollapsed = { ["Elwynn Forest"] = true }
	W.Fire("QUEST_LOG_UPDATE")
	S.questCollapsed = nil
	W.Now = nil
	W.now = W.now + 10 -- long after the last accept
	W.Fire("QUEST_LOG_UPDATE")
	check("collapsed header: learned places kept", Q.Store()[101] ~= nil and Q.Store()[105].giver.y == 0.70)

	-- where each quest leads, and the order
	S.mapPos = { 0.50, 0.50 }
	local list = Q.Sorted("distance")
	local byId = {}
	for _, q in ipairs(list) do byId[q.id] = q end
	local t = byId[101].target
	check("learned target: the middle of the places", t.kind == "learned" and math.abs(t.x - 0.62) < 1e-9, t and t.x)
	check("distance in yards from the map size (0.12 of 3000 yd)", math.abs(byId[101].yards - 360) < 0.01, byId[101].yards)
	check("bearing: east is a quarter turn clockwise", math.abs(byId[101].bearing + math.pi / 2) < 1e-9, byId[101].bearing)
	check("nearest first, unknown places last", list[1].id == 101 and list[#list].yards == nil, list[1].id)
	check("no place, no target: the Westfall quest", byId[104].target == nil)
	-- the client's own position wins (modern clients)
	S.questWaypoints = { [104] = { 1436, 0.5, 0.5 } }
	list = Q.Sorted("distance")
	for _, q in ipairs(list) do byId[q.id] = q end
	check("client's position used when it gives one", byId[104].target.kind == "exact" and byId[104].elsewhere == "Westfall")
	check("...on another map: no yards, the zone instead", byId[104].yards == nil and QT.DistanceText(byId[104]):lower() == "westfall")
	check("learned distances marked ~", QT.DistanceText(byId[101]):lower() == "~360 yd", QT.DistanceText(byId[101]))
	check("sort by level", Q.Sorted("level")[1].id == 103)
	-- without map sizes the direction still works
	S.mapSize = false
	check("no map size: no yards, still a direction", select(1, Q.Vector({ map = 9, x = 0, y = 0 }, { map = 9, x = 0, y = -1 })) == nil
		and select(2, Q.Vector({ map = 9, x = 0, y = 0 }, { map = 9, x = 0, y = -1 })) == 0)
	S.mapSize = nil

	-- the tracker shows it
	ns.QuestTracker.Refresh()
	-- the quest accepted in this test stands on top under NEW; the list follows
	check("NEW: the quest accepted last on top, the line under it", QT.frame.rows[1].quest.id == 105 and QT.frame.newLabel:IsShown()
		and QT.frame.newLine:IsShown())
	local row1 = QT.frame.rows[2]
	check("tracker: nearest first in the list with its distance", row1.quest.id == 101 and row1.dist:GetText():lower() == "~360 yd",
		row1.quest and row1.quest.id)
	check("tracker: open objective with its count", row1.obj[1]:GetText() == "5/8 Kobold Vermin slain")
	local done
	for _, r in ipairs(QT.frame.rows) do if r.quest and r.quest.id == 103 then done = r end end
	check("tracker: finished quest says TURN IN", done and W.has(done.obj[1]:GetText(), "TURN IN"))
	row1._scripts.OnClick(row1, "RightButton")
	check("right-click opens the quest log at it", W.questLogOpened[#W.questLogOpened] == row1.quest.index)

	-- navigating: click a quest, the arrow turns as you turn
	row1._scripts.OnClick(row1, "LeftButton")
	check("click: navigating to it", Q.selectedId == 101 and QA.frame:IsShown())
	check("tracker marks it", row1.sel:IsShown())
	QA.Update()
	check("arrow: distance", QA.frame.dist:GetText():lower() == "~360 yd", QA.frame.dist:GetText())
	check("arrow: what the place is", QA.frame.kind:GetText():lower() == "learned area")
	check("facing north, quest east: arrow points right", math.abs(QA.frame.angle + math.pi / 2) < 1e-9)
	local tip = QA.frame.lines[1]._from
	check("...the tip drawn to the right", tip[1] > 21 and math.abs(tip[2]) < 1e-6, tip[1] .. "," .. tip[2])
	S.me.facing = -math.pi / 2 -- facing east
	QA.Update()
	check("facing it: straight ahead, in the accent colour", math.abs(QA.frame.angle) < 1e-9
		and QA.frame.lines[1]._color[2] == select(2, ns.Kit.Accent()))
	S.me.facing = math.pi / 2 -- facing west: the quest is behind you, light grey
	QA.Update()
	check("behind you: arrow points back, not in the accent colour", math.abs(math.abs(QA.frame.angle) - math.pi) < 1e-9
		and QA.frame.lines[1]._color[1] == ns.Kit.C.text[1])
	S.me.facing = math.pi -- facing south: east is to your left
	QA.Update()
	check("facing south, quest east: arrow points left", math.abs(QA.frame.angle - math.pi / 2) < 1e-9 and QA.frame.lines[1]._from[1] < -21)
	S.me.facing = nil
	QA.Update()
	check("facing unknown: distance only", not QA.frame.pointer:IsShown() and QA.frame.dist:GetText():lower() == "~360 yd")
	S.me.facing = 0
	S.mapPos = { 0.621, 0.50 }
	QA.Update()
	check("there: ARRIVED", W.has(QA.frame.dist:GetText(), "ARRIVED") and not QA.frame.pointer:IsShown())
	S.mapPos = { 0.50, 0.50 }
	QA.frame._scripts.OnMouseUp(QA.frame, "RightButton")
	check("right-click the arrow: stop", Q.selectedId == nil and not QA.frame:IsShown())
	-- the key binding: nearest quest with a known place, again to stop
	SITREP_QuestNav()
	check("binding: navigates to the nearest", Q.selectedId == 101)
	SITREP_QuestNav()
	check("binding again: stops", Q.selectedId == nil)
	-- finished: back to where you got it
	S.quests[1].objectives[1] = { "Kobold Vermin slain: 8/8", true }
	W.Fire("QUEST_LOG_UPDATE")
	local q101
	for _, q in ipairs(Q.Sorted("distance")) do if q.id == 101 then q101 = q end end
	check("finished without a known giver: no place", q101.complete and q101.target == nil)
	Q.Store()[101].giver = { map = 1429, x = 0.5, y = 0.6 }
	for _, q in ipairs(Q.Sorted("distance")) do if q.id == 101 then q101 = q end end
	check("finished: leads back to where you got it", q101.target.kind == "giver" and math.abs(q101.yards - 200) < 0.01)
	-- handed in: forgotten
	Q.Select(101)
	table.remove(S.quests, 1)
	W.Fire("QUEST_TURNED_IN", 101)
	check("handed in: place forgotten, navigation stops", Q.Store()[101] == nil and Q.selectedId == nil)
	-- off
	ns.P.quests.tracker = false; ns.Changed("quests.tracker")
	check("tracker off: Blizzard's back", not QT.frame:IsShown() and QuestWatchFrame:IsShown())
	ns.P.quests.tracker = true; ns.Changed("quests.tracker")
	ns.Config.Open("quests")
	check("quests page opens", ns.Config._page("quests") ~= nil)
	ns.Config.Toggle()
	local n0 = #W.prints
	SlashCmdList.SITREP("questprobe")
	local dump = table.concat(W.prints, "\n", n0 + 1)
	check("questprobe reports", dump:find("GetQuestLogTitle yes", 1, true) and dump:find("map size 3000 x 2000 yd", 1, true)
		and dump:find("[102] Wolves Across the Border", 1, true), dump)
	S.quests, S.questWaypoints, S.mapId, S.mapPos, S.me.facing = nil, nil, nil, nil, nil
	W.Fire("QUEST_LOG_UPDATE")
end

-- ACTION BARS AND MENU (3.31) -----------------------------------------------------
do
	S.me.combat = false
	local U, AB, MM = ns.P.ui, ns.ActionBars, ns.MicroMenu
	-- a secure snippet, run the way the client runs it (self / owner are the frames)
	local function snippet(code, env)
		local fn
		if setfenv then fn = assert(loadstring(code)); setfenv(fn, env) else fn = assert(load(code, "snippet", "t", env)) end
		fn()
	end
	-- the skin
	local b = ActionButton1
	check("icon cropped square", b.icon._coord and b.icon._coord[1] == 0.08 and b.icon._coord[4] == 0.92)
	check("rounded mask off", b.icon:GetNumMaskTextures() == 0)
	check("Blizzard's frame off", b:GetNormalTexture():GetAlpha() == 0 and b.SlotArt:GetAlpha() == 0)
	b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2") -- Blizzard's update sets it again
	check("...and stays off when Blizzard sets it again", b:GetNormalTexture():GetAlpha() == 0)
	b:GetNormalTexture():SetAlpha(0.5) -- (modern buttons: Blizzard sets the texture's own alpha)
	check("...also when Blizzard sets the texture's alpha itself", b:GetNormalTexture():GetAlpha() == 0)
;(function()
		local n0 = #W.prints
		SlashCmdList.SITREP("barprobe")
		check("barprobe: the textures on the buttons", table.concat(W.prints, "\n", n0 + 1):find("ActionButton1: shown", 1, true))
	end)()
	check("pet buttons: second frame off too", PetActionButton1NormalTexture2:GetAlpha() == 0)
	check("flat states", b:GetHighlightTexture():GetTexture() == "Interface\\Buttons\\WHITE8X8"
		and b:GetCheckedTexture():GetTexture() == "Interface\\Buttons\\WHITE8X8")
	check("key binding in the HUD font", b.HotKey._font and b.HotKey._font[1] == ns.Kit.FONT)
	check("macro names hidden", b.Name:GetAlpha() == 0)
	U.barMacroNames = true; ns.Changed("ui.barMacroNames")
	check("macro names on", b.Name:GetAlpha() == 1)
	U.barMacroNames = false; ns.Changed("ui.barMacroNames")
	check("bar art hidden", not MainMenuBarLeftEndCap:IsShown() and not ActionBarUpButton:IsShown())
	;(function()
		-- the dividers between the main bar's buttons: frames from a pool, no key of their own
		local function divider()
			local d = CreateFrame("Frame", nil, MainActionBar)
			d.Center = d:CreateTexture()
			d.Center.GetAtlas = function() return "!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-Center" end
			return d
		end
		local d1 = divider()
		ns.Changed("ui.barArt")
		check("bar art: the dividers between the buttons hidden", not d1:IsShown() and d1:GetAlpha() == 0)
		-- Blizzard lays the bar out again (Edit Mode, a cold start): new dividers, hidden too
		local d2 = divider()
		MainActionBar:UpdateGridLayout()
		check("...also the ones Blizzard makes when it lays the bar out again", not d2:IsShown())
	end)()
	-- range
	S.actions = { [1] = { "spell", 116 }, [2] = { "spell", 133 } }
	S.actionRange = { [1] = false, [2] = true }
	S.savedTarget = S.units.target
	S.units.target = nil
	AB.UpdateRange()
	check("no target: no veil, nothing asked", not ActionButton1.srRange:IsShown())
	S.units.target = { name = "Dummy", guid = "Creature-0-1-0-1-9-1", isPlayer = false, hostile = true, dist = 30 }
	AB.UpdateRange()
	check("out of range: red veil", ActionButton1.srRange:IsShown() and not ActionButton2.srRange:IsShown())
	S.actionRange = { [1] = 0 }
	AB.UpdateRange()
	check("older clients' 0 counts as out of range", ActionButton1.srRange:IsShown())
	S.actionRange = { [1] = nil }
	AB.UpdateRange()
	check("no range to check: no veil", not ActionButton1.srRange:IsShown())
	S.actionRange = { [1] = false }
	U.barRange = false; ns.Changed("ui.barRange")
	check("range tint off: no veil", not ActionButton1.srRange:IsShown())
	U.barRange = true; ns.Changed("ui.barRange")
	S.units.target, S.savedTarget = S.savedTarget, nil
	check("empty slot: no veil", not ActionButton3.srRange:IsShown())
	S.actions, S.actionRange = nil, nil
	-- empty slots: invisible until something is dragged
	;(function()
		S.actions = { [1] = { "spell", 116 }, [62] = { "item", 6948 } }
		S.petActions = { [1] = { "Attack" } }
		W.Fire("ACTIONBAR_SLOT_CHANGED", 1)
		check("slot change: waits a frame (Blizzard's buttons update first)", AB.dirty == true)
		W.Update(0.01)
		check("empty slots invisible, filled ones and pet actions shown", ActionButton1:GetAlpha() == 1 and ActionButton2:GetAlpha() == 0
			and MultiBarBottomLeftButton2:GetAlpha() == 1 and MultiBarBottomLeftButton1:GetAlpha() == 0
			and PetActionButton1:GetAlpha() == 1 and PetActionButton2:GetAlpha() == 0 and BonusActionButton1:GetAlpha() == 1)
		S.cursor = { "spell", 3, "spell", 133 }
		W.Fire("CURSOR_CHANGED")
		W.Update(0.01)
		check("dragging a spell: every slot shows", ActionButton2:GetAlpha() == 1 and MultiBarBottomLeftButton1:GetAlpha() == 1)
		S.actions[2] = { "spell", 133 }
		S.cursor = nil
		W.Fire("ACTIONBAR_SLOT_CHANGED", 2)
		W.Fire("CURSOR_CHANGED")
		W.Update(0.01)
		check("dropped: the new slot stays, the other empties go", ActionButton2:GetAlpha() == 1 and ActionButton3:GetAlpha() == 0)
		-- no cursor event on this client: the range tick notices the drag
		S.cursor = { "item", 6948 }
		W.Update(0.25)
		check("without cursor events: shown within a tick", ActionButton3:GetAlpha() == 1)
		S.cursor = nil
		W.Update(0.25)
		U.barHideEmpty = false; ns.Changed("ui.barHideEmpty")
		check("option off: empty slots shown", ActionButton3:GetAlpha() == 1)
		U.barHideEmpty = true; ns.Changed("ui.barHideEmpty")
		check("option on again: hidden", ActionButton3:GetAlpha() == 0)
		-- the bar layout keeps the bar's opacity apart from the hidden empties
		check("an empty slot's own alpha is not taken for the bar's", (ActionButton3.srOrig == nil or ActionButton3.srOrig.alpha ~= 0))
		S.actions, S.petActions = nil, nil
		W.Update(0.01)
	end)()

	-- the menu
	local mb, list = MM.button, MM.list
	check("MENU button shown, Blizzard's micro buttons invisible and click-through (not hidden: taint)", mb:IsShown()
		and CharacterMicroButton:GetAlpha() == 0 and CharacterMicroButton:IsMouseEnabled() == false and CharacterMicroButton:IsShown()
		and MicroMenuContainer:GetAlpha() == 0)
	;(function()
		local gm
		for _, r in ipairs(list.rows) do if r.binding == "TOGGLEGAMEMENU" then gm = r end end
		check("game menu entry: acts on the release (Blizzard's button wants that)", gm and gm:GetAttribute("useOnKeyDown") == false
			and gm._clicks[1] == "AnyUp")
		-- Forever has both talent buttons: the older one opens the talent trees (the newer
		-- one the spellbook, since mid-October): "Talente" is the older one
		PlayerSpellsMicroButton = CreateFrame("Button", "PlayerSpellsMicroButton", UIParent)
		local names, labels = {}, {}
		for _, e in ipairs(MM.Entries()) do names[#names + 1] = e.button:GetName() or "proxy"; labels[e.button:GetName() or "proxy"] = e.label end
		local joined = table.concat(names, ",")
		check("talents only once: the talent trees' button, called Talente", joined:find("TalentMicroButton", 1, true)
			and not joined:find("PlayerSpellsMicroButton", 1, true) and labels.TalentMicroButton == "Talente", joined)
		check("the spellbook just Zauberbuch (not the client's 'and abilities/professions')", labels.SpellbookMicroButton == "Zauberbuch", labels.SpellbookMicroButton)
		-- a client without the older one: the newer one is Talente
		TalentMicroButton:Hide()
		names = {}
		for _, e in ipairs(MM.Entries()) do names[#names + 1] = e.button:GetName() or "proxy" end
		joined = table.concat(names, ",")
		check("no talent trees' button (hidden: not offered): the newer one", not joined:find("TalentMicroButton", 1, true) and joined:find("PlayerSpellsMicroButton", 1, true), joined)
		TalentMicroButton:Show()
		PlayerSpellsMicroButton = nil
	end)()
	check("one entry per micro button this client has", #list.rows == 8, #list.rows)
	local e1 = list.rows[1]
	check("entry: secure click on Blizzard's button", e1:GetAttribute("type") == "click" and e1:GetAttribute("clickbutton") == CharacterMicroButton)
	check("entry: the game's own name and the key", e1.label:GetText() == "Charakterinfo" and e1.key:GetText() == "C")
	check("entry fires on key down only, as the game's setting says", #e1._clicks == 1 and e1._clicks[1] == "AnyDown")
	check("help has no binding", list.rows[8].key:GetText() == "")
	-- open the list (secure snippet), pick an entry, the list closes (secure snippet)
	check("MENU opens the list through its frame ref", mb._refs.list == list)
	list:Hide()
	snippet(mb:GetAttribute("_onclick"), { self = mb })
	check("click MENU: list opens", list:IsShown())
	e1:GetAttribute("clickbutton"):Click() -- what the secure click does
	local wrap
	for _, w in ipairs(W.wraps) do if w.frame == e1 then wrap = w end end
	snippet(wrap.post, { self = e1, owner = list })
	check("picking an entry clicks Blizzard's button and closes the list", W.microClicks[1] == "CharacterMicroButton" and not list:IsShown())
	snippet(mb:GetAttribute("_onclick"), { self = mb })
	snippet(mb:GetAttribute("_onclick"), { self = mb })
	check("click MENU twice: open, closed", not list:IsShown())
	-- friends: online count on the button, on the social row
	check("MENU: friends online beside the label", mb.friends:GetText() == "5" and mb.dot:IsShown())
	local socialRow
	for _, r in ipairs(list.rows) do if r.binding == "TOGGLESOCIAL" then socialRow = r end end
	check("the social row: how many online", socialRow and socialRow.key:GetText():find("5 online", 1, true), socialRow and socialRow.key:GetText())
	S.friendsOnline, S.bnOnline = 0, 0
	W.Fire("FRIENDLIST_UPDATE")
	check("nobody online: 0, no dot", mb.friends:GetText() == "0" and not mb.dot:IsShown())
	S.friendsOnline, S.bnOnline = nil, nil
	W.Fire("BN_FRIEND_ACCOUNT_ONLINE")
	mb._scripts.OnEnter(mb)
	check("MENU tooltip: friends in the game and on Battle.net", GameTooltip:Text():find("Friends online: 5  (in the game 3, Battle.net 2)", 1, true))
	mb._scripts.OnLeave(mb)
	check("the friends list asked for at login", W.friendsAsked)
	-- a client without a social micro button (Forever: friends sit by the chat): an entry of its own
	local social = SocialsMicroButton
	SocialsMicroButton = nil
	local entries = MM.Entries()
	local fe, mapAt, feAt
	for i, e in ipairs(entries) do
		if e.proxy then fe, feAt = e, i end
		if e.binding == "TOGGLEWORLDMAP" then mapAt = i end
	end
	check("no social button: a Friends entry, before the map", fe and fe.friends and feAt == mapAt - 1 and fe.label == "Friends")
	fe.button:Click()
	check("...it opens the friends list", W.friendsOpened == 1)
	check("...and its stand-in is not hidden away with Blizzard's buttons", fe.button._concealed == nil and fe.button.srConcealed == nil)
	SocialsMicroButton = social
	-- latency on the button
	S.latency = 300
	mb._scripts.OnUpdate(mb, 5)
	check("latency shown, red when high", W.has(mb.ms:GetText(), "300 MS") and mb.ms:GetText():find("ff5555", 1, true), mb.ms:GetText())
	S.latency = nil
	mb._scripts.OnUpdate(mb, 5)
	check("...green when low", mb.ms:GetText():find("5cff8d", 1, true))
	-- off: Blizzard's buttons back
	U.menu = false; ns.Changed("ui.menu")
	check("menu off: Blizzard's micro buttons back", not mb:IsShown() and CharacterMicroButton:GetAlpha() == 1
		and CharacterMicroButton.srFadeMouse == nil and not CharacterMicroButton.srFaded and MicroMenuContainer:GetAlpha() == 1)
	U.menu = true; ns.Changed("ui.menu")
	-- in combat nothing secure changes
	S.me.combat = true
	U.menu = false; ns.Changed("ui.menu")
	check("in combat: the menu waits", mb:IsShown())
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	check("...and follows after combat", not mb:IsShown())
	U.menu = true; ns.Changed("ui.menu")
	ns.Config.Open("bars")
	check("bars page opens", ns.Config._page("bars") ~= nil)
	ns.Config.Toggle()
	local n0 = #W.prints
	SlashCmdList.SITREP("uidump")
	local dump = table.concat(W.prints, "\n", n0 + 1)
	check("uidump: buttons and micro buttons", dump:find("action buttons: 46", 1, true)
		and dump:find("MainActionBar: ", 1, true) and dump:find("ActionBarPageNumber*(hidden)", 1, true) and dump:find("micro buttons: CharacterMicroButton", 1, true), dump)
end

-- BAR ART ON MODERN CLIENTS, BAR LAYOUT (3.32) ---------------------------------------
do
	S.me.combat = false
	local BL = ns.BarLayout
	-- the modern main bar's art, found by its keys
	check("page switch hidden", not MainActionBar.ActionBarPageNumber:IsShown())
	check("border and end caps hidden", not MainActionBar.BorderArt:IsShown() and not MainActionBar.EndCaps:IsShown())
	check("other parts of the bar stay", MainActionBar.QuickKeybindGlow:IsShown())
	check("dividers between the buttons hidden", not ActionButton1.RightDivider:IsShown())
	check("art keys", ns.ActionBars.ArtKey("ActionBarPageNumber") and ns.ActionBars.ArtKey("LeftEndCap")
		and not ns.ActionBars.ArtKey("ActionButtons") and not ns.ActionBars.ArtKey("QuickKeybindGlow"))

	-- the layout starts where Blizzard had the first button
	local pos = ns.P.hud.pos.bar_main
	check("main bar placed where Blizzard had it", pos and pos[1] == "TOPLEFT" and pos[3] == 500 and pos[4] == 76,
		pos and (pos[3] .. "," .. pos[4]))
	local h = BL.holders.main
	local function at(b) local p = { b:GetPoint(1) } return p[2], p[4], p[5] end
	local rel, x, y = at(ActionButton2)
	check("buttons on SITREP's holder, Blizzard's spacing", rel == h and x == 42 and y == 0, tostring(x))
	ns.P.bars.main.gap = 2; ns.Changed("bars.main")
	rel, x = at(ActionButton2)
	check("gap adjustable", x == 38, x)
	ns.P.bars.main.cols = 6; ns.Changed("bars.main")
	rel, x, y = at(ActionButton7)
	check("buttons per row: 6 makes two rows", x == 0 and y == -38, x .. "," .. y)
	check("holder sized to the grid", h:GetWidth() == 226 and h:GetHeight() == 74, h:GetWidth() .. "x" .. h:GetHeight())
	ns.P.bars.main.scale = 0.8; ns.Changed("bars.main")
	check("size adjustable", ActionButton1:GetScale() == 0.8 and math.abs(h:GetWidth() - 226 * 0.8) < 1e-9)
	-- Blizzard lays the bar out again (Edit Mode): SITREP's grid again
	MainActionBar:UpdateGridLayout()
	rel = at(ActionButton2)
	check("Blizzard's relayout undone", rel == h)
	-- combat: waits
	S.me.combat = true
	ns.P.bars.main.gap = 10; ns.Changed("bars.main")
	rel, x = at(ActionButton2)
	check("in combat: buttons not touched", x == 38)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	rel, x = at(ActionButton2)
	check("...placed after combat", x == 46, x)
	-- dragging: a handle only while the HUD is unlocked
	check("locked: the holder is invisible and takes no clicks", not h.label:IsShown() and h._mouse == false)
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	check("unlocked: a handle to drag the bar", h.label:IsShown() and h._mouse == true)
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	check("druid forms (classic bonus bar): same spot as the main bar", ({ BonusActionButton2:GetPoint(1) })[2] == h
		and ({ BonusActionButton2:GetPoint(1) })[4] == 46 and BonusActionButton2:GetScale() == ActionButton2:GetScale())
	check("...and the same skin, its art hidden", BonusActionButton1.srSkin and not BonusActionBarTexture0:IsShown())
	check("other bars too", BL.holders.bottomleft ~= nil and ({ ActionButton1:GetPoint(1) })[2] == h
		and ({ MultiBarBottomLeftButton2:GetPoint(1) })[2] == BL.holders.bottomleft)
	-- the bars this client has, for the console
	local opts = {}
	for _, o in ipairs(BL.Options()) do opts[#opts + 1] = o[1] end
	check("console lists the bars this client has", table.concat(opts, ",") == "main,bottomleft,pet", table.concat(opts, ","))
	-- off: Blizzard's anchors and size back
	ns.P.ui.barLayout = false; ns.Changed("ui.barLayout")
	local p2 = { ActionButton2:GetPoint(1) }
	check("off: Blizzard's place back", p2[2] == UIParent and p2[4] == 542 and ActionButton2:GetScale() == 1, tostring(p2[4]))
	check("off: holder gone", not h:IsShown())
	ns.P.ui.barLayout = true
	ns.P.bars.main.gap, ns.P.bars.main.cols, ns.P.bars.main.scale = 6, 12, 1
	ns.Changed("ui.barLayout")
	-- reset positions: back to where Blizzard has the bar
	ns.P.hud.pos = {}; ns.Changed("hud.pos")
	check("reset positions: placed at Blizzard's place again", ns.P.hud.pos.bar_main and ns.P.hud.pos.bar_main[3] == 500)
end

-- LAYOUT PAGE: PICK AN ELEMENT, ADJUST IT (3.33) ---------------------------------------
-- (a function of its own: the main chunk is near Lua's 200-locals limit)
;(function()
	S.me.combat = false
	ns.Config.Open("layout")
	local pg = ns.Config._page("layout")
	local ctl = pg.ctl
	local function shown(...)
		local out = {}
		for _, k in ipairs({ "size", "map", "chat", "alpha", "bg", "gap", "cols", "reset" }) do if ctl[k]:IsShown() then out[#out + 1] = k end end
		return table.concat(out, ",")
	end
	check("starts on the player frame: size and reset", ns.P.ui.layoutEdit == "player" and shown() == "size,alpha,bg,reset", shown())
	ctl.Select("bags")
	check("bag button: size and reset", shown() == "size,alpha,bg,reset")
	ctl.setSize(1.5)
	check("bag button size", ns.P.hud.frameScale.bags == 1.5 and ns.Bags.button:GetScale() == ns.P.hud.scale * 1.5)
	ctl.Select("menu"); ctl.setSize(0.8)
	check("MENU button size, list too", ns.MicroMenu.button:GetScale() == ns.P.hud.scale * 0.8 and ns.MicroMenu.list:GetScale() == ns.P.hud.scale * 0.8)
	ctl.Select("quests"); ctl.setSize(1.2)
	check("quest tracker size", ns.QuestTracker.frame:GetScale() == ns.P.hud.scale * 1.2)
	ctl.Select("bar_main")
	check("a bar: size, gap, buttons per row", shown() == "size,alpha,bg,gap,cols,reset", shown())
	ctl.setSize(0.9)
	check("bar size goes to the bar", ns.P.bars.main.scale == 0.9 and ActionButton1:GetScale() == 0.9)
	ctl.Select("minimap")
	check("minimap: its own size in px", shown() == "map,alpha,bg,reset", shown())
	ctl.Select("chat")
	check("chat: size of the whole chat, its text size", shown() == "size,chat,alpha,bg,reset", shown())
	-- stacked under the picker, no holes
	local _, _, _, x1, y1 = ctl.size:GetPoint(1)
	local _, _, _, x2, y2 = ctl.reset:GetPoint(1)
	check("controls stacked under the picker", y1 == -ctl.top and y2 < y1 and x1 == x2, y1 .. " " .. y2)
	-- the whole chat's size: windows, tabs, input, the tab bar, SITREP's chat parts
	ctl.setSize(1.6)
	check("chat size: windows, tabs and input lines", ChatFrame1:GetScale() == 1.6 and ChatFrame2:GetScale() == 1.6
		and ChatFrame2Tab:GetScale() == 1.6 and ChatFrame1EditBox:GetScale() == 1.6)
	check("...and SITREP's button bar and preview with it", ns.Chat.bar:GetScale() == 1.6 and ns.Chat.preview:GetScale() == 1.6)
	ctl.setSize(1)
	check("back to 1", ChatFrame1:GetScale() == 1 and ChatFrame2Tab:GetScale() == 1)
	check("page fits with any element", pg.y[2] <= 560 - 64 - 40)
	ctl.Select("bar_main")
	check("...also with a bar's seven controls", pg.y[2] <= 560 - 64 - 40, pg.y[2])
	-- background opacity: each element on its own, today's look by default
	local function bgA(tex) if tex.parts then return tex.a end return tex._vc and tex._vc[4] end
	check("defaults: today's backgrounds", bgA(ns.Bags.button.bg) == 0.92 and bgA(ns.QuestTracker.frame.bg) == 0.72
		and bgA(ActionButton1.srTile) == 0.92)
	ctl.setBg(0.3)
	check("bar background: the tiles of that bar", bgA(ActionButton1.srTile) == 0.3 and bgA(BonusActionButton1.srTile) == 0.3
		and bgA(MultiBarBottomLeftButton1.srTile) == 0.92)
	ctl.setBg(0.92)
	ctl.Select("quests"); ctl.setBg(0.2)
	check("quest tracker background", bgA(ns.QuestTracker.frame.bg) == 0.2 and ns.QuestTracker.frame:GetAlpha() == 1)
	ctl.Select("board"); ctl.setBg(0.4)
	check("HUD module background", bgA(ns.HUD.modules.board.bg) == 0.4)
	ctl.Select("target"); ctl.setBg(0.5)
	check("unit frame background", bgA(ns.Frames.frames.target.bg) == 0.5)
	ctl.Select("party"); ctl.setBg(0.5)
	check("party: every member", bgA(ns.Frames.partyMembers[1].bg) == 0.5 and bgA(ns.Frames.partyMembers[4].bg) == 0.5)
	ctl.Select("minimap"); ctl.setBg(0)
	check("minimap: the zone strip", bgA(ns.Minimap.frame.head.bg) == 0)
	ctl.Select("chat")
	local CHa = ns.Chat
	check("chat: a light pane by default", ChatFrame1.srShell:IsShown() and ns.P.hud.bgAlpha.chat == 0.45
		and math.abs(bgA(ChatFrame2.srShell) - CHa.PaneAlpha(CHa.presence)) < 1e-6, bgA(ChatFrame2.srShell))
	ctl.setBg(0.7)
	check("chat: the pane's opacity is a setting", math.abs(bgA(ChatFrame2.srShell) - CHa.PaneAlpha(CHa.presence)) < 1e-6
		and CHa.PaneAlpha(0) == 0.7)
	ctl.setBg(0)
	check("chat: 0, no pane", not ChatFrame1.srShell:IsShown())
	ctl.setBg(0.45)
	ctl.Select("questArrow")
	check("quest arrow: no background to set", not ctl.bg:IsShown())
	for k, v in pairs({ quests = 0.72, board = 0.92, target = 0.92, party = 0.92, minimap = 0.85 }) do ns.P.hud.bgAlpha[k] = v end
	ns.Changed("hud.bgAlpha")
	ctl.Select("bar_main")
	-- opacity: each element on its own
	S.actions = { [1] = { "spell", 116 }, [12] = { "spell", 133 }, [61] = { "spell", 2050 } }
	ctl.setAlpha(0.5)
	check("bar opacity: every button of the bar", ns.P.bars.main.alpha == 0.5 and ActionButton1:GetAlpha() == 0.5
		and ActionButton12:GetAlpha() == 0.5 and BonusActionButton1:GetAlpha() == 0.5 and MultiBarBottomLeftButton1:GetAlpha() == 1)
	ctl.setAlpha(1)
	S.actions = nil
	ns.ActionBars.UpdateEmpty()
	ctl.Select("bags"); ctl.setAlpha(0.6)
	check("bag button opacity", ns.Bags.button:GetAlpha() == 0.6)
	ctl.Select("menu"); ctl.setAlpha(0.7)
	check("MENU button opacity", ns.MicroMenu.button:GetAlpha() == 0.7)
	ctl.Select("quests"); ctl.setAlpha(0.8)
	check("quest tracker opacity", ns.QuestTracker.frame:GetAlpha() == 0.8)
	ctl.Select("minimap"); ctl.setAlpha(0.75)
	check("minimap opacity", Minimap:GetAlpha() == 0.75)
	ctl.Select("chat"); ctl.setAlpha(0.65)
	check("chat opacity, every window", ChatFrame1:GetAlpha() == 0.65 and ChatFrame2:GetAlpha() == 0.65)
	ctl.Select("target"); ctl.setAlpha(0.55)
	check("target frame opacity", ns.Frames.frames.target:GetAlpha() == 0.55)
	ctl.Select("party"); ctl.setAlpha(0.45)
	check("party frames opacity", ns.Frames.party:GetAlpha() == 0.45)
	-- the player frame and the HUD modules fade (auto-hide): their opacity is where they fade to
	ctl.Select("player"); ctl.setAlpha(0.5)
	W.Update(1)
	check("player frame fades to its own opacity", math.abs(ns.Frames.frames.player:GetAlpha() - 0.5) < 0.02,
		ns.Frames.frames.player:GetAlpha())
	ctl.Select("board"); ctl.setAlpha(0.5)
	W.Update(1)
	local board = ns.HUD.modules.board
	check("HUD module: its opacity times the HUD opacity", math.abs(board:GetAlpha() - 0.5 * ns.P.hud.alpha) < 0.02, board:GetAlpha())
	-- SITREP off: the game's own frames whole again
	ns.P.enabled = false; ns.Changed("enabled")
	check("SITREP off: minimap and chat fully opaque", Minimap:GetAlpha() == 1 and ChatFrame1:GetAlpha() == 1)
	ns.P.enabled = true; ns.Changed("enabled")
	for k in pairs(ns.P.hud.frameAlpha) do ns.P.hud.frameAlpha[k] = 1 end
	ns.Changed("hud.frameAlpha")
	ctl.Select("bar_main")
	-- reset one position, not the others
	ns.P.hud.pos.bags = { "CENTER", "CENTER", 10, 10 }
	ns.P.hud.pos.menu = { "CENTER", "CENTER", 20, 20 }
	ctl.Select("bags")
	ctl.reset._scripts.OnClick(ctl.reset)
	check("reset its position: only this one", ns.P.hud.pos.bags == nil and ns.P.hud.pos.menu ~= nil)
	-- the element list: grouped under headings, in columns (it is long)
	ctl.pick.button._scripts.OnClick(ctl.pick.button)
	local m = ctl.pick.menu
	local rows = {}
	for _, r in ipairs(m.rows) do if r:IsShown() then rows[#rows + 1] = r end end
	check("element list: headings first in each group", rows[1].text:GetText() == "HUD" and rows[1]._mouse == false)
	-- 23 entries: two columns of 12, the second starting at the top again
	local perCol = math.ceil(#rows / math.ceil(#rows / 14))
	local p1, top2 = { rows[1]:GetPoint(1) }, { rows[perCol + 1]:GetPoint(1) }
	check("long list: second column", #rows > 14 and top2[2] > p1[2] and top2[3] == p1[3], #rows)
	local qrow
	for _, r in ipairs(rows) do if r.text:GetText() == "Quest arrow" then qrow = r end end
	qrow._scripts.OnClick(qrow)
	check("picking from the list selects it", ns.P.ui.layoutEdit == "questArrow" and ctl.pick.button.text:GetText() == "Quest arrow")
	ctl.Select("player")
	ns.P.hud.frameScale.bags, ns.P.hud.frameScale.menu, ns.P.hud.frameScale.quests, ns.P.bars.main.scale = 1, 1, 1, 1
	ns.P.hud.pos.menu = nil
	ns.Changed("hud.frameScale"); ns.Changed("bars.main")
	ns.Config.Toggle()
end)()

-- FOLDING: QUEST TRACKER TO THE CHOSEN QUEST, CHAT TO ITS NEW-MESSAGE TABS (3.35) --------
;(function()
	S.me.combat = false
	local Q, QT, CF = ns.Quests, ns.QuestTracker, ns.ChatFold
	-- quest tracker
	S.mapId, S.mapPos, S.me.facing = 1429, { 0.5, 0.5 }, 0
	S.quests = {
		{ id = 201, title = "Wolves", level = 6, zone = "Elwynn Forest", objectives = { { "Wolf slain: 1/8" } } },
		{ id = 202, title = "Kobolds", level = 7, zone = "Elwynn Forest", objectives = { { "Kobold slain: 2/8" } } },
		{ id = 203, title = "Report", level = 5, zone = "Elwynn Forest", objectives = {}, complete = true },
	}
	W.Fire("QUEST_LOG_UPDATE")
	local f = QT.frame
	local function rows() local n = 0 for _, r in ipairs(f.rows) do if r:IsShown() then n = n + 1 end end return n end
	check("all quests listed, header says -", rows() == 3 and f.toggle:GetText() == "-")
	f.headButton._scripts.OnClick(f.headButton)
	check("header click folds: none chosen, the nearest one", ns.P.quests.collapsed and rows() == 1 and f:IsShown()
		and f.rows[1].quest.id == Q.Sorted("distance")[1].id and f.sort:GetText():lower() == "nearest" and f.toggle:GetText() == "+")
	-- with places known: the nearest by distance, whatever the order
	ns.P.quests.sort = "level"
	Q.Store()[201] = { obj = { { { map = 1429, x = 0.9, y = 0.5 } } } }
	Q.Store()[202] = { obj = { { { map = 1429, x = 0.55, y = 0.5 } } } }
	QT.Refresh()
	check("folded, none chosen: the nearest by distance (also when sorted by level)", rows() == 1 and f.rows[1].quest.id == 202,
		f.rows[1].quest and f.rows[1].quest.id)
	ns.P.quests.sort = "distance"
	S.quests = {}
	W.Fire("QUEST_LOG_UPDATE")
	check("folded, no quests at all: only the header", rows() == 0 and f:IsShown() and f:GetHeight() == 26, f:GetHeight())
	S.quests = {
		{ id = 201, title = "Wolves", level = 6, zone = "Elwynn Forest", objectives = { { "Wolf slain: 1/8" } } },
		{ id = 202, title = "Kobolds", level = 7, zone = "Elwynn Forest", objectives = { { "Kobold slain: 2/8" } } },
		{ id = 203, title = "Report", level = 5, zone = "Elwynn Forest", objectives = {}, complete = true },
	}
	W.Fire("QUEST_LOG_UPDATE")
	Q.Select(202)
	check("folded: only the quest you navigate to", rows() == 1 and f.rows[1].quest.id == 202 and f.sort:GetText():lower() == "chosen only")
	SITREP_ToggleQuestList()
	check("binding unfolds: all again", not ns.P.quests.collapsed and rows() == 3)
	SlashCmdList.SITREP("quests")
	check("/sitrep quests folds", ns.P.quests.collapsed and rows() == 1)
	SlashCmdList.SITREP("quests")
	check("header drag still moves the tracker", f.headButton._scripts.OnDragStart ~= nil)
	-- shift-click a quest: its link into the chat (into the open input line, else a new one)
	local wolvesRow
	for _, r in ipairs(f.rows) do if r:IsShown() and r.quest and r.quest.id == 201 then wolvesRow = r end end
	S.shift = true
	S.chatOpen = true
	local selBefore = Q.selectedId
	wolvesRow._scripts.OnClick(wolvesRow, "LeftButton")
	check("shift-click: the quest's link into the open input line", W.chatInserted[#W.chatInserted]
		and W.chatInserted[#W.chatInserted]:find("|Hquest:201:6|h[Wolves]|h", 1, true) and Q.selectedId == selBefore,
		W.chatInserted[#W.chatInserted])
	S.chatOpen = false
	wolvesRow._scripts.OnClick(wolvesRow, "LeftButton")
	check("...no input line open: a new one with the link", W.chatOpenWith and W.chatOpenWith:find("[Wolves]", 1, true))
	S.shift = false
	-- hovering a quest: its task and its story; the quest log keeps your selection
	S.quests[1].task = "Bring 8 Tough Wolf Meat to Bauer Alois."
	S.quests[1].desc = string.rep("Die Wölfe reißen unsere Schafe. ", 30)
	S.quests[1].xp = 1200
	SelectQuestLogEntry(4) -- what you had selected in the quest log
	local wolves
	for _, r in ipairs(f.rows) do if r.quest and r.quest.id == 201 then wolves = r end end
	wolves._scripts.OnEnter(wolves)
	local tip = GameTooltip:Text()
	check("hover: the task", tip:find("Bring 8 Tough Wolf Meat", 1, true))
	check("hover: shift-click puts its link in the chat (said so)", tip:find("Shift-click: its link in the chat", 1, true))
	check("hover: the experience, and its share of the level", tip:find("1200 XP  (25% of this level)", 1, true), tip)
	check("hover: the story, long ones cut", tip:find("Die Wölfe reißen", 1, true) and tip:find(" ...", 1, true)
		and #tip < #S.quests[1].desc + 400)
	check("the quest log keeps your selection", GetQuestLogSelection() == 4)
	wolves._scripts.OnLeave(wolves)
	local calls = #W.questLogOpened
	wolves._scripts.OnEnter(wolves)
	check("texts read once per quest", #W.questLogOpened == calls)
	wolves._scripts.OnLeave(wolves)
	Q.Select(nil)
	S.quests, S.mapId, S.mapPos, S.me.facing = nil, nil, nil, nil
	W.Fire("QUEST_LOG_UPDATE")

	-- chat (folding up: the mock's chat sits at the bottom of the screen)
	ns.P.ui.chatFoldTo = "up"; ns.Changed("ui.chatFoldTo")
	local CH = ns.Chat
	local fb = CH.foldBtn
	check("the fold button in the bar, its arrow the way it folds", fb:GetParent() == CH.bar and fb.srIcon:GetTexture():find("glyph_up", 1, true))
	fb._scripts.OnClick(fb)
	check("folded: messages out of sight and out of the mouse's way", ns.P.ui.chatCollapsed and ChatFrame1:GetAlpha() == 0
		and ChatFrame1._mouse == false and ChatFrame2:GetAlpha() == 0)
	check("folded up: the arrow points back out", fb.srIcon:GetTexture():find("glyph_down", 1, true))
	check("folded: no unread, no counts", not ChatFrame1Tab.srBadge:IsShown() and not ChatFrame2Tab.srBadge:IsShown())
	W.Fire("CHAT_MSG_WHISPER", "hi", "Freund-Realm")
	check("a whisper: its window's tab counts it and stays in sight", ChatFrame2Tab.srBadge:GetText() == "1"
		and ChatFrame2Tab._ignoreParentAlpha == true and ChatFrame2Tab:GetAlpha() == 1 and not ChatFrame1Tab.srBadge:IsShown())
	W.Fire("CHAT_MSG_CHANNEL", "WTS stuff", "Händler")
	check("public channels do not count", not ChatFrame1Tab.srBadge:IsShown())
	W.Fire("CHAT_MSG_GUILD", "moin", "Gildi")
	W.Fire("CHAT_MSG_GUILD", "na", "Gildi")
	check("guild: the general window, two", ChatFrame1Tab.srBadge:GetText() == "2")
	local me = UnitName("player")
	W.Fire("CHAT_MSG_SAY", "hello", me)
	check("your own messages do not count", ChatFrame1Tab.srBadge:GetText() == "2")
	ns.P.ui.chatPreview = false; ns.Changed("ui.chatPreview")
	check("preview off: tabs only", not CH.preview:IsShown())
	ns.P.ui.chatPreview = true; ns.Changed("ui.chatPreview")
	-- the last 3 lines the selected window showed (all it shows: a public channel too), oldest first
	local pv = CH.preview
	pv._w = 600 -- (as wide as the chat)
	local function line(i) local l = pv.lines[i] return l:IsShown() and tostring(l.text:GetText()) or "-" end
	SELECTED_CHAT_FRAME = ChatFrame1
	ChatFrame1:AddMessage("[2. Handel] [Händler]: WTS stuff", 1, 0.75, 0.75)
	ChatFrame1:AddMessage("[Gilde] [Gildi]: moin", 0.25, 1, 0.25)
	ChatFrame1:AddMessage("[Gilde] [Gildi]: na", 0.25, 1, 0.25)
	ChatFrame1:AddMessage("[" .. me .. "]: hello", 1, 1, 1)
	check("preview: the selected window's last 3 lines, oldest first", pv:IsShown() and line(1) == "[Gilde] [Gildi]: moin"
		and line(2) == "[Gilde] [Gildi]: na" and line(3) == "[" .. me .. "]: hello", line(1) .. " | " .. line(2) .. " | " .. line(3))
	check("preview: in the line's own colour", pv.lines[2].text._tc[1] == 0.25 and pv.lines[3].text._tc[1] == 1)
	local pill = ns.Kit.Region(pv.lines[2].bg)
	check("preview: each line on a pill as wide as its text", pill._w and pill._w == pv.lines[2].text:GetStringWidth() + 14, tostring(pill._w))
	ChatFrame1:AddMessage("[2. Handel] [Händler]: WTS more", 1, 0.75, 0.75)
	check("everything the tab shows counts (a public channel too)", line(3) == "[2. Handel] [Händler]: WTS more" and line(1) == "[Gilde] [Gildi]: na")
	local secret = W.Secret("geheim")
	ChatFrame1:AddMessage(secret, 1, 1, 1)
	check("a secret line: shown as it is, no error", pv.lines[3].text:GetText() == secret)
	-- another tab: its own last lines
	ChatFrame2:AddMessage("[Mira] flüstert: bin gleich da", 1, 0.5, 1)
	SELECTED_CHAT_FRAME = ChatFrame2
	CH.Layout()
	check("another tab selected: its own last lines", line(1) == "[Mira] flüstert: bin gleich da" and line(2) == "-")
	SELECTED_CHAT_FRAME = ChatFrame1
	CH.Layout()
	-- folded up: the input line under the three lines
	local ip = { ChatFrame1EditBox:GetPoint(1) }
	check("folded up: input line under the three preview lines", ip[1] == "TOPLEFT" and ip[2] == ChatFrame1 and ip[5] == -2 - 3 * 18, tostring(ip[5]))
	-- a link in a preview line: clicked as in the chat, the chat stays folded
	local refs = {}
	local realRef = _G.SetItemRef
	_G.SetItemRef = function(link) refs[#refs + 1] = link end
	local l2 = pv.lines[2]
	l2._scripts.OnHyperlinkClick(l2, "item:6948", "[Ruhestein]", "LeftButton")
	l2._scripts.OnMouseUp(l2, "LeftButton")
	check("preview link: handled like the chat's, still folded", refs[1] == "item:6948" and ns.P.ui.chatCollapsed)
	_G.SetItemRef = realRef
	-- Enter while folded: unfolded while typing, folded back after
	local eb = ChatFrame1EditBox
	eb._scripts.OnEditFocusGained(eb)
	check("typing: the chat unfolds", CH.peek and ChatFrame1:GetAlpha() == 1 and ns.P.ui.chatCollapsed and not pv:IsShown()
		and eb.srSkin.ring:IsShown())
	check("typing: the input line back at Blizzard's place", ({ eb:GetPoint(1) })[3] == "BOTTOMLEFT")
	eb._scripts.OnEditFocusLost(eb)
	check("sent: folded again, what the tab got is seen", not CH.peek and ChatFrame1:GetAlpha() == 0 and pv:IsShown()
		and not ChatFrame1Tab.srBadge:IsShown() and ChatFrame2Tab.srBadge:GetText() == "1" and not eb.srSkin.ring:IsShown())
	-- a click beside a link: that tab, unfolded
	l2.linkAt = nil
	l2._scripts.OnMouseUp(l2, "LeftButton")
	check("preview click beside a link: unfolded at that tab", not ns.P.ui.chatCollapsed and not pv:IsShown() and SELECTED_CHAT_FRAME == ChatFrame1)
	ip = { ChatFrame1EditBox:GetPoint(1) }
	local ip2 = { ChatFrame1EditBox:GetPoint(2) }
	check("unfolded: input line back at Blizzard's place", ip[1] == "TOPLEFT" and ip[3] == "BOTTOMLEFT" and ip[5] == -2
		and ip2[1] == "TOPRIGHT" and ip2[3] == "BOTTOMRIGHT" and ChatFrame1EditBox:GetNumPoints() == 2, tostring(ip[3]))
	local dp = { GeneralDockManager:GetPoint(1) }
	local dp2 = { GeneralDockManager:GetPoint(2) }
	check("unfolded: tabs over the chat, room for the bar at their right end", dp[1] == "BOTTOMLEFT" and dp[3] == "TOPLEFT" and dp[5] == 6
		and dp2[1] == "BOTTOMRIGHT" and dp2[4] == -(CH.barW + 6))
	check("the bar at the tab row's right end", ({ CH.bar:GetPoint(1) })[2] == GeneralDockManager)
	-- unfolded: a message for another tab counts, one for the tab you see does not
	W.Fire("CHAT_MSG_GUILD", "da?", "Gildi")
	check("unfolded: the tab you see does not count", not ChatFrame1Tab.srBadge:IsShown())
	W.Fire("CHAT_MSG_WHISPER", "noch da?", "Freund")
	check("unfolded: another tab counts", ChatFrame2Tab.srBadge:GetText() == "2")
	FCF_Tab_OnClick(ChatFrame2Tab)
	check("its tab selected: read", not ChatFrame2Tab.srBadge:IsShown() and ChatFrame2Tab._ignoreParentAlpha == false)
	FCF_Tab_OnClick(ChatFrame1Tab)
	-- folding down (a chat in the lower half): the lines at its bottom, the tabs right over them
	ChatFrame1:AddMessage("[Passant] sagt: ok", 1, 1, 1)
	ns.P.ui.chatFoldTo = "down"
	SITREP_ToggleChat()
	local pp = { pv:GetPoint(1) }
	check("folding down: the lines at the chat's bottom", pp[1] == "BOTTOMLEFT" and pp[2] == ChatFrame1, tostring(pp[1]))
	check("folding down: the newest line lowest", ({ pv.lines[3]:GetPoint(1) })[5] == 0 and ({ pv.lines[1]:GetPoint(1) })[5] == 36)
	dp = { GeneralDockManager:GetPoint(1) }
	check("folding down: the tabs over the last lines", dp[1] == "BOTTOMLEFT" and dp[3] == "BOTTOMLEFT" and dp[5] == 4 + 3 * 18,
		tostring(dp[3]) .. " " .. tostring(dp[5]))
	check("folding down: the input line stays below", ({ ChatFrame1EditBox:GetPoint(1) })[3] == "BOTTOMLEFT")
	check("folded down: the arrow points back up", fb.srIcon:GetTexture():find("glyph_up", 1, true))
	FCF_DockUpdate()
	check("Blizzard places the tab bar again: still over the lines", ({ GeneralDockManager:GetPoint(1) })[3] == "BOTTOMLEFT")
	CH.lines[ChatFrame1] = nil
	SITREP_ToggleChat(); SITREP_ToggleChat()
	check("folded down with no lines: the tabs right at the bottom", ({ GeneralDockManager:GetPoint(1) })[5] == 4)
	ChatFrame1:AddMessage("[Gilde] [Gildi]: wieder da", 0.25, 1, 0.25)
	check("a new line: the tabs move up over it", ({ GeneralDockManager:GetPoint(1) })[5] == 4 + 18)
	local pfam = pv.lines[1].text._fontObj
	local pzh
	for _, m in ipairs(pfam and pfam._members or {}) do if m.alphabet == "simplifiedchinese" then pzh = m.file end end
	check("the preview line in the chat's font family (Chinese from the chat's own font)", pzh == "Fonts\\CHAT_ZH.TTF", pzh)
	ns.P.ui.chatFoldTo = "auto"; ns.Changed("ui.chatFoldTo")
	check("auto: a chat in the lower half folds down", CH.FoldsDown())
	ns.P.ui.chatFoldTo = "up"; ns.Changed("ui.chatFoldTo")
	-- clicking a tab unfolds the chat there
	FCF_Tab_OnClick(ChatFrame2Tab)
	check("tab click unfolds", not ns.P.ui.chatCollapsed and ChatFrame1:GetAlpha() == 1 and ChatFrame1._mouse == true)
	FCF_Tab_OnClick(ChatFrame1Tab)
	-- presence: tabs, input line and bar with the mouse, fading out slowly after
	local hover = true
	ChatFrame1.IsMouseOver = function() return hover end
	W.Update(0.06); W.Update(0.2)
	check("mouse on the chat: tabs, bar and input line there", CH.presence == 1 and GeneralDockManager:GetAlpha() == 1
		and CH.bar:GetAlpha() == 1 and ChatFrame1EditBox:GetAlpha() == 1)
	hover = false
	W.Update(0.06); W.Update(CH.HOLD - 0.2)
	check("mouse gone: they stay a moment", CH.presence == 1)
	W.Update(0.3); W.Update(CH.FADE_OUT / 2)
	check("...then fade out slowly", CH.presence > 0 and CH.presence < 1, tostring(CH.presence))
	for _ = 1, 10 do W.Update(0.3) end
	check("...until gone (the pane and messages stay)", CH.presence == 0 and GeneralDockManager:GetAlpha() == 0 and CH.bar:GetAlpha() == 0
		and ChatFrame1EditBox:GetAlpha() == 0 and ChatFrame1:GetAlpha() == 1 and ChatFrame1.srShell:IsShown())
	W.Fire("CHAT_MSG_WHISPER", "psst", "Freund")
	check("an unread tab stays in sight while the tab bar is faded", ChatFrame2Tab._ignoreParentAlpha == true and ChatFrame2Tab:GetAlpha() == 1)
	ChatFrame1EditBox.HasFocus = function() return true end
	W.Update(0.06); W.Update(0.2)
	check("typing: all there again", CH.presence == 1)
	ChatFrame1EditBox.HasFocus = nil
	ChatFrame1.IsMouseOver = nil
	FCF_Tab_OnClick(ChatFrame2Tab); FCF_Tab_OnClick(ChatFrame1Tab)
	-- folded: each preview line fades a while after it came; the mouse brings them back
	ns.P.ui.chatFoldTo, ns.P.ui.chatFade = "down", 20
	CH.lines[ChatFrame1] = nil
	SITREP_ToggleChat()
	W.Update(0.06); W.Update(5)
	ChatFrame1:AddMessage("[Gilde] [Gildi]: eins", 0.25, 1, 0.25)
	W.Update(12)
	ChatFrame1:AddMessage("[Gilde] [Gildi]: zwei", 0.25, 1, 0.25)
	W.Update(0.06)
	check("folded, the parts gone: both lines there while new", CH.presence == 0 and line(1) == "[Gilde] [Gildi]: eins"
		and line(2) == "[Gilde] [Gildi]: zwei" and pv.lines[1]:GetAlpha() == 1)
	W.Update(9)
	check("after the fade time: the older line fading, the newer still there", pv.lines[1]:GetAlpha() > 0 and pv.lines[1]:GetAlpha() < 1
		and pv.lines[2]:GetAlpha() == 1, tostring(pv.lines[1]:GetAlpha()))
	W.Update(2)
	check("faded out: gone, the tabs right over the line left", line(1) == "[Gilde] [Gildi]: zwei" and line(2) == "-"
		and ({ GeneralDockManager:GetPoint(1) })[5] == 4 + 18, ({ GeneralDockManager:GetPoint(1) })[5])
	W.Update(12)
	check("all faded: no lines, the tabs at the bottom", not pv:IsShown() and ({ GeneralDockManager:GetPoint(1) })[5] == 4)
	ChatFrame1.IsMouseOver = function() return true end
	W.Update(0.06); W.Update(0.2)
	check("the mouse on the chat: the last lines back", line(1) == "[Gilde] [Gildi]: eins" and line(2) == "[Gilde] [Gildi]: zwei"
		and pv.lines[1]:GetAlpha() == 1)
	ChatFrame1.IsMouseOver = nil
	ChatFrame1:AddMessage("[Gilde] [Gildi]: drei", 0.25, 1, 0.25)
	for _ = 1, 4 do W.Update(1) end
	check("the mouse gone: only the new line stays", line(1) == "[Gilde] [Gildi]: drei" and line(2) == "-")
	SITREP_ToggleChat()
	ns.P.ui.chatFoldTo = "up"
	-- SITREP's chat off: no folding, everything Blizzard's
	SITREP_ToggleChat()
	ns.P.ui.chat = false; ns.Changed("ui.chat")
	check("chat off: messages, tabs and input line as Blizzard has them", ChatFrame1:GetAlpha() == 1 and not CH.bar:IsShown()
		and GeneralDockManager:GetAlpha() == 1 and not pv:IsShown() and GeneralDockManager:GetNumPoints() == 2
		and ({ GeneralDockManager:GetPoint(2) })[4] == 0)
	ns.P.ui.chat = true; ns.Changed("ui.chat")
	check("chat on again: still folded", ChatFrame1:GetAlpha() == 0)
	SlashCmdList.SITREP("chat")
	check("/sitrep chat unfolds", not ns.P.ui.chatCollapsed and ChatFrame1:GetAlpha() == 1)
	-- a tab dragged off by accident: /sitrep chat dock puts it back
	local docked = {}
	_G.FCF_DockFrame = function(f) docked[#docked + 1] = f; f.isDocked = true end
	ChatFrame2.isDocked = false
	local n0 = #W.prints
	SlashCmdList.SITREP("chat dock")
	check("/sitrep chat dock: the window pulled out back in the tab bar", docked[1] == ChatFrame2 and #docked == 1
		and W.prints[n0 + 1]:find("1 chat window", 1, true), tostring(W.prints[n0 + 1]))
	SlashCmdList.SITREP("chat dock")
	check("...nothing left outside: says so", #docked == 1 and W.prints[#W.prints]:find("No chat window", 1, true))
	_G.FCF_DockFrame, ChatFrame2.isDocked = nil, nil
	ns.Config.Open("interface")
	check("interface page still fits", ns.Config._page("interface").y[2] <= 560 - 64 - 40, ns.Config._page("interface").y[2])
	ns.Config.Open("quests")
	check("quests page still fits", ns.Config._page("quests").y[1] <= 560 - 64 - 40)
	ns.Config.Toggle()
end)()

-- QUESTS ACCEPTED LAST, QUEST NPCS, MINIMAP BUTTONS, CLICKS, IDOL (3.42) ----------------
;(function()
	S.me.combat = false
	local Q, QT = ns.Quests, ns.QuestTracker
	-- the 3 quests accepted last on top under NEW, newest first, not again below
	S.mapId, S.mapPos = 1429, { 0.5, 0.5 }
	S.quests = {
		{ id = 301, title = "Alt eins", level = 5, zone = "Elwynn Forest", objectives = { { "Wolf slain: 1/8" } } },
	}
	W.Fire("QUEST_LOG_UPDATE")
	for i, title in ipairs({ "Neu A", "Neu B", "Neu C", "Neu D" }) do
		table.insert(S.quests, { id = 310 + i, title = title, level = 6, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 0/8" } } })
		W.Fire("QUEST_ACCEPTED", #S.quests, 310 + i)
	end
	QT.Refresh()
	local rows = {}
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() then rows[#rows + 1] = r.quest.id end end
	check("NEW: the 3 accepted last, newest first", rows[1] == 314 and rows[2] == 313 and rows[3] == 312, table.concat(rows, ","))
	check("...under a NEW label, a line before the rest", QT.frame.newLabel:IsShown() and QT.frame.newLine:IsShown())
	local seen = {}
	for _, id in ipairs(rows) do seen[id] = (seen[id] or 0) + 1 end
	check("...and not twice", seen[314] == 1 and seen[311] == 1 and seen[301] == 1)
	ns.P.quests.collapsed = true; ns.Changed("quests.collapsed")
	check("folded: no NEW section", not QT.frame.newLabel:IsShown())
	ns.P.quests.collapsed = false; ns.Changed("quests.collapsed")

	-- hovering an NPC that is part of a quest: the objective and the quest over its name
	local N, PH = ns.Plates, ns.PlateHover
	S.units.nameplate95 = { name = "Kobold Vermin", guid = "Creature-0-1-95", level = 6, isPlayer = false, hostile = true, reaction = 2,
		wx = 8, wy = 0, screenX = 700, creatureType = "Humanoid" }
	local realGet = C_NamePlate.GetNamePlateForUnit
	local plate = CreateFrame("Frame")
	local uf = CreateFrame("Frame", nil, plate)
	uf.healthBar = CreateFrame("StatusBar", nil, uf)
	uf.name = uf:CreateFontString()
	plate.UnitFrame = uf
	C_NamePlate.GetNamePlateForUnit = function(unit) if unit == "nameplate95" or unit == "mouseover" then return plate end return realGet(unit) end
	W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate95")
	local s = N.skins.nameplate95
	S.units.mouseover = S.units.nameplate95
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	local hf = PH.frame
	check("hover a quest NPC: the objective (count first) and the quest in the hover window", hf:IsShown()
		and hf.quest:GetText() == "! 0/8 Kobold Vermin slain" and hf.questTitle:GetText() == "Neu A", hf.quest:GetText())
	check("alone (no group): no group line", not hf.group:IsShown())
	-- in a group, members with SITREP share their counts: what they still need of it
	local savedN, savedParty = S.group.n, ns.QuestShare.party
	S.group.n = 2
	ns.QuestShare.party = { Mira = { [311] = { counts = { { 3, 8 } } } }, Bob = { [311] = { counts = { { 8, 8 } } } } }
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	local gt = hf.group:GetText() or ""
	check("group line: Mira still needs 5, Bob is done (green)", hf.group:IsShown() and gt:find("Mira |cffe0e8e55|r", 1, true)
		and gt:find("|cff5cff8dBob|r", 1, true), gt)
	check("the quest matched by its objective, counts aside", select(2, ns.Quests.Match("Kobold Vermin slain: 5/8", "Neu A")) == 1)
	ns.QuestShare.party = { Mira = { [999] = { counts = { { 1, 4 } } } } }
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("members on other quests only: no group line", not hf.group:IsShown())
	S.group.n, ns.QuestShare.party = savedN, savedParty
	ns.P.plates.hoverWhere = "plate"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("on the plate instead: the quest line over its name", s and s.hoverQuest and s.hoverQuest:IsShown()
		and s.hoverQuest:GetText():find("! 0/8 Kobold Vermin slain", 1, true), s and s.hoverQuest and s.hoverQuest:GetText())
	S.units.nameplate95.name = "Murloc"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("an NPC no quest needs: no quest line", not s.hoverQuest:IsShown())
	-- an NPC's title from the client's tooltip ("<Schmied>"): on its plate line and in the window
	S.units.nameplate95.title = "Schmied"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("on the plate: the NPC's title first", s.hover and s.hover:GetText():find("<Schmied>", 1, true) == 1,
		s.hover and s.hover:GetText())
	ns.P.plates.hoverWhere = "frame"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("in the window: the NPC's title on the guild line", hf.guild:GetText() == "<Schmied>" and hf.guild:IsShown(), hf.guild:GetText())
	-- Classic's tooltips write the title bare
	S.units.nameplate95.title = nil
	S.units.nameplate95.tipLine2 = "Waffenschmied"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("a bare title (Classic's tooltip): shown too", hf.guild:GetText() == "<Waffenschmied>", hf.guild:GetText())
	S.units.nameplate95.tipLine2 = "Humanoid"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("its creature type under the name: no title", hf.guild:GetText() == "", hf.guild:GetText())
	local n0n = #W.prints
	SlashCmdList.SITREP("npcprobe")
	local rep = table.concat(W.prints, "\n", n0n + 1)
	check("/sitrep npcprobe: the mouseover's tooltip lines", rep:find("mouseover: 2 lines", 1, true) and rep:find("2 [type nil] Humanoid", 1, true), rep)
	S.units.nameplate95.tipLine2 = "Stufe 6 Humanoid"
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("a tooltip line that is no title: no guild line", hf.guild:GetText() == "" and not hf.guild:IsShown(), hf.guild:GetText())
	S.units.nameplate95.tipLine2 = nil
	S.units.mouseover = nil
	W.Update(0.2)
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate95")
	C_NamePlate.GetNamePlateForUnit = realGet
	S.units.nameplate95 = nil
	S.quests, S.mapId, S.mapPos = nil, nil, nil
	W.Fire("QUEST_LOG_UPDATE")

	-- the day / night button and the mail icon in the square map's corners
	local p = { GameTimeFrame:GetPoint(1) }
	check("day / night button in the map's top right corner", p[1] == "TOPRIGHT" and p[2] == Minimap and p[3] == "TOPRIGHT")
	check("mail in the top left corner", ({ MiniMapMailFrame:GetPoint(1) })[3] == "TOPLEFT")
	ns.P.ui.minimap = false; ns.Changed("ui.minimap")
	p = { GameTimeFrame:GetPoint(1) }
	check("round map again: back where Blizzard had it", p[1] == "CENTER" and p[4] == 52 and GameTimeFrame:GetScale() == 1)
	ns.P.ui.minimap = true; ns.Changed("ui.minimap")

	-- Blizzard shows a hidden part again in combat: no invisible frame left taking clicks
	local blocked0 = W.blockedCalls
	local plain = CreateFrame("Frame", "SITREP_TestPlain", UIParent)
	local prot = CreateFrame("Frame", "SITREP_TestProtected", UIParent)
	prot._protected = true
	ns.Kit.Conceal(plain, true)
	ns.Kit.Conceal(prot, true)
	S.me.combat = true
	setmetatable(plain, getmetatable(plain)) -- (Blizzard's own code shows them)
	rawset(prot, "_shown", true); prot._scripts.OnShow(prot)
	plain._shown = true; plain._scripts.OnShow(plain)
	check("in combat: a frame that is not protected is hidden right away", not plain:IsShown())
	check("in combat: a protected one only goes invisible (the game's rule)", prot:IsShown() and prot:GetAlpha() == 0)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	check("combat over: hidden for real (no invisible frame over the UI)", not prot:IsShown() and W.blockedCalls == blocked0)
	ns.Kit.Conceal(plain, false); ns.Kit.Conceal(prot, false)

	-- /sitrep mouse names what takes the mouse
	S.mouseFocus = ns.Bags.button
	SlashCmdList.SITREP("mouse")
	local dump = table.concat(SITREP_DB.reports.mouse.lines, "\n")
	check("/sitrep mouse: the frame under the mouse, its layer and alpha", dump:find("SITREP_BagButton", 1, true) and dump:find("alpha", 1, true), dump)
	S.mouseFocus = nil

	-- druid: an idol lowers the shift cost; the client lists both costs
	local catSpell = 768
	local spell = W.anySpell and W.anySpell(catSpell)
	local F = ns.Frames
	local idol = { { type = 0, cost = 300, requiredAuraID = 0, hasRequiredAura = false },
		{ type = 0, cost = 210, requiredAuraID = 99999, hasRequiredAura = true } }
	local realCost = C_Spell.GetSpellPowerCost
	C_Spell.GetSpellPowerCost = function(id) if id == catSpell then return idol end return realCost(id) end
	check("idol: the lowered cost is what you pay", F.SpellCost(catSpell, 0) == 210, F.SpellCost(catSpell, 0))
	idol[2].hasRequiredAura = false
	check("costs are kept a moment (asked every tick)", F.SpellCost(catSpell, 0) == 210)
	W.Fire("PLAYER_EQUIPMENT_CHANGED", 18, false)
	check("idol not equipped: the plain cost", F.SpellCost(catSpell, 0) == 300)
	idol[1], idol[2] = { type = 0, cost = 210, requiredAuraID = 99999, hasRequiredAura = true }, { type = 0, cost = 300, requiredAuraID = 0, hasRequiredAura = false }
	W.Fire("PLAYER_EQUIPMENT_CHANGED", 18, true)
	check("whatever order the client lists them in", F.SpellCost(catSpell, 0) == 210)
	S.forms = { { spell = catSpell, active = false } }
	SlashCmdList.SITREP("shiftprobe")
	local sp = table.concat(SITREP_DB.reports.shiftprobe.lines, "\n")
	check("/sitrep shiftprobe: each cost entry and what the marker uses", sp:find("the marker uses 210", 1, true)
		and sp:find("cost 2: type 0 cost 300", 1, true), sp)
	S.forms = nil
	C_Spell.GetSpellPowerCost = realCost
end)()

-- QUEST PROGRESS OF THE GROUP, THE CLOCK, THE MAP DUMP (3.43) ---------------------------
;(function()
	S.me.combat = false
	local QS, QT = ns.QuestShare, ns.QuestTracker
	local savedGroup = S.group
	S.group = { n = 2, names = { Aldwin = true, Bero = true } }
	S.mapId, S.mapPos = 1429, { 0.5, 0.5 }
	S.quests = { { id = 401, title = "Kobolde", level = 6, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 3/8" } } } }
	local n0 = #W.addonMsgs
	W.Fire("QUEST_LOG_UPDATE")
	W.Update(0.25)
	local out = {}
	for i = n0 + 1, #W.addonMsgs do out[#out + 1] = W.addonMsgs[i].msg end
	check("your progress goes to the group", table.concat(out, "|"):find("Q1\t401\t3/8", 1, true) and W.addonMsgs[#W.addonMsgs].channel == "PARTY",
		table.concat(out, "|"))
	-- theirs comes back: how many each still needs, small at the objective's right
	W.Fire("CHAT_MSG_ADDON", "SITREP", "Q1\t401\t5/8", "PARTY", "Aldwin-Realm")
	W.Fire("CHAT_MSG_ADDON", "SITREP", "Q1\t401\t8/8", "PARTY", "Bero-Realm")
	QT.Refresh()
	local row
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() and r.quest.id == 401 then row = r end end
	local txt = row and row.party[1]:GetText() or ""
	check("tracker: Aldwin still needs 3, Bero is done (green)", txt:find("Aldwi |cffe0e8e53|r", 1, true) and txt:find("|cff5cff8dBero|r", 1, true), txt)
	row._scripts.OnEnter(row)
	check("tooltip: the group in full", GameTooltip:Text():find("Aldwin: 5/8", 1, true) and GameTooltip:Text():find("Bero: 8/8", 1, true))
	row._scripts.OnLeave(row)
	-- a change of yours: only that is sent again
	n0 = #W.addonMsgs
	S.quests[1].objectives[1][1] = "Kobold Vermin slain: 4/8"
	W.Fire("QUEST_LOG_UPDATE")
	W.Update(0.25)
	check("a change: sent again", W.addonMsgs[#W.addonMsgs].msg == "Q1\t401\t4/8" and #W.addonMsgs == n0 + 1)
	-- someone drops the quest; someone leaves the group
	W.Fire("CHAT_MSG_ADDON", "SITREP", "Q1\t401\t-", "PARTY", "Bero-Realm")
	check("a member drops the quest: gone from the line", not (QS.party.Bero and QS.party.Bero[401]))
	S.group.names.Aldwin = nil
	W.Fire("GROUP_ROSTER_UPDATE")
	check("a member leaves: forgotten", QS.party.Aldwin == nil)
	-- someone joins: the whole log goes out again
	n0 = #W.addonMsgs
	S.group = { n = 3, names = { Bero = true, Cara = true } }
	W.Fire("GROUP_ROSTER_UPDATE")
	W.Update(0.25)
	check("someone joins: your log again", #W.addonMsgs > n0 and W.addonMsgs[#W.addonMsgs].msg:find("Q1\t401", 1, true))
	S.group = savedGroup
	W.Fire("GROUP_ROSTER_UPDATE")
	check("no group: nothing kept", next(QS.party) == nil)
	S.quests, S.mapId, S.mapPos = nil, nil, nil
	W.Fire("QUEST_LOG_UPDATE")

	-- the clock in the zone strip over the map (not on the coordinates under it)
	local p = { TimeManagerClockButton:GetPoint(1) }
	check("clock: in the zone strip, left", p[1] == "LEFT" and p[2] == ns.Minimap.frame.head, tostring(p[2]))

	-- /sitrep mapdump: the parts on and round the map
	SlashCmdList.SITREP("mapdump")
	local dump = table.concat(SITREP_DB.reports.mapdump.lines, "\n")
	check("map dump lists the buttons and where they hang", dump:find("GameTimeFrame", 1, true) and dump:find("TimeManagerClockButton", 1, true)
		and dump:find("at TOPRIGHT Minimap TOPRIGHT", 1, true), dump)
end)()

-- WHAT /sitrep mouse AND mapdump FOUND ON FOREVER (3.43.1) ------------------------------
;(function()
	S.me.combat = false
	-- MainActionBar, empty once SITREP holds the buttons, took the clicks there
	check("Blizzard's main bar frame takes no mouse while SITREP holds its buttons", MainActionBar:IsMouseEnabled() == false)
	ns.P.ui.barLayout = false; ns.Changed("ui.barLayout")
	check("layout off: as it was", MainActionBar:IsMouseEnabled() == true)
	ns.P.ui.barLayout = true; ns.Changed("ui.barLayout")
	MainActionBar:EnableMouse(true) -- (Edit Mode, say)
	MainActionBar:UpdateGridLayout()
	check("Blizzard lays the bar out again: no mouse again", MainActionBar:IsMouseEnabled() == false)
	-- the day / night moon, mail, tracking: on the map's corners; Blizzard's coordinates hidden
	local p = { MinimapCluster.DielFrame:GetPoint(1) }
	check("day / night (MinimapCluster.DielFrame) in the top right corner, under the calendar", p[1] == "TOPRIGHT" and p[2] == Minimap
		and p[5] == -18, tostring(p[2]))
	check("mail and tracking in the left corners", ({ MinimapCluster.IndicatorFrame:GetPoint(1) })[1] == "TOPLEFT"
		and ({ MinimapCluster.Tracking:GetPoint(1) })[1] == "BOTTOMLEFT")
	check("Blizzard's coordinates under the map hidden (SITREP's in the corner)", not MinimapCluster.MinimapContainer.PlayerCoords:IsShown())
	check("the invisible zoom area in the corner gone", not Minimap.ZoomHitArea:IsShown())
	ns.P.ui.mapCoords = false; ns.Changed("ui.mapCoords")
	check("SITREP's coordinates off: Blizzard's back", MinimapCluster.MinimapContainer.PlayerCoords:IsShown())
	ns.P.ui.mapCoords = true; ns.Changed("ui.mapCoords")
	ns.P.ui.minimap = false; ns.Changed("ui.minimap")
	p = { MinimapCluster.DielFrame:GetPoint(1) }
	check("round map again: the moon back where Blizzard had it", p[1] == "CENTER" and p[2] == MinimapCluster and p[4] == 63)
	ns.P.ui.minimap = true; ns.Changed("ui.minimap")
end)()

-- SIZES AFTER THE CLIENT PATCH (3.44): wider ranges, nameplates, the console ----------
;(function()
	S.me.combat = false
	-- the plates' size: the game's own setting, out of combat only
	ns.P.plates.scale = 1.6; ns.Changed("plates.scale")
	check("nameplate size: the game's setting", W.cvars.nameplateGlobalScale == "1.6", W.cvars.nameplateGlobalScale)
	local blocked0 = W.blockedCalls
	S.me.combat = true
	ns.P.plates.scale = 2; ns.Changed("plates.scale")
	check("in combat: waits (the setting is protected then)", W.cvars.nameplateGlobalScale == "1.6" and W.blockedCalls == blocked0)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	check("...after combat: set", W.cvars.nameplateGlobalScale == "2")
	ns.P.plates.scale = 1; ns.Changed("plates.scale")
	check("back to 1: the game's default again", W.cvars.nameplateGlobalScale == "1")
	-- a client without nameplateGlobalScale (Forever?): the horizontal and vertical ones
	S.cvarsMissing = { nameplateGlobalScale = true }
	W.cvars = {}
	ns.P.plates.scale = 1.8; ns.Changed("plates.scale")
	check("no global size setting: the horizontal and vertical ones", W.cvars.NamePlateHorizontalScale == "1.8"
		and W.cvars.NamePlateVerticalScale == "1.8" and W.cvars.nameplateGlobalScale == nil)
	SlashCmdList.SITREP("platesize")
	local dump = table.concat(SITREP_DB.reports.platesize.lines, "\n")
	check("/sitrep platesize: what SITREP set, the client's nameplate settings", dump:find("SITREP set: NamePlateHorizontalScale NamePlateVerticalScale", 1, true)
		and dump:find("cvar NamePlateVerticalScale = 1.8", 1, true) and not dump:find("cvar nameplateGlobalScale", 1, true), dump)
	ns.P.plates.scale = 1; ns.Changed("plates.scale")
	S.cvarsMissing = nil
	-- the console itself
	ns.Config.Open("layout")
	ns.P.hud.consoleScale = 1.5; ns.Changed("hud.consoleScale")
	check("console size", SITREP_Console:GetScale() == 1.5)
	ns.P.hud.consoleScale = 1; ns.Changed("hud.consoleScale")
	ns.Config.Toggle()
	-- wide enough: an element can be 4x, the HUD 3x, the map 700 px
	ns.P.hud.frameScale.player = 3.5; ns.Changed("hud.frameScale")
	check("an element at 350 %", ns.Frames.frames.player:GetScale() == 3.5 * ns.P.hud.scale)
	ns.P.hud.frameScale.player = 1; ns.Changed("hud.frameScale")
	check("map up to 700 px", ns.Minimap.MAX == 700)
end)()

-- QUEST ITEMS IN THE TRACKER (3.46) --------------------------------------------------------
;(function()
	S.me.combat = false
	local QT, QI = ns.QuestTracker, ns.QuestItems
	local blocked0 = W.blockedCalls
	S.mapId, S.mapPos = 1429, { 0.5, 0.5 }
	S.quests = {
		{ id = 601, title = "Ohne Gegenstand", level = 8, zone = "Elwynn Forest", objectives = { { "Wolf slain: 1/8" } } },
		{ id = 602, title = "Fackeln legen", level = 9, zone = "Elwynn Forest", objectives = { { "Zelt verbrannt: 0/4" } },
			item = { "|cffffffff|Hitem:12345::::::::|h[Fackel]|h|r", 135432, 3 }, itemCD = { W.now, 30 } },
	}
	W.Fire("QUEST_LOG_UPDATE")
	QT.Refresh()
	local b = QI.buttons[1]
	check("a quest with an item: a clickable icon (secure: use the item)", b and b:IsShown() and b:GetAttribute("type") == "item"
		and b:GetAttribute("item") == "item:12345")
	check("...its icon, charges and cooldown", b.icon:GetTexture() == 135432 and b.count:GetText() == "3" and b.cd._cdDur == 30)
	local row
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() and r.quest.id == 602 then row = r end end
	local p = { b:GetPoint(1) }
	check("...placed left of its row, on the screen (not hung on the row)", p[1] == "TOPRIGHT" and p[2] == UIParent
		and p[4] == (row:GetLeft() - 10) and p[5] == row:GetTop(), tostring(p[4]))
	check("only that quest has one", not (QI.buttons[2] and QI.buttons[2]:IsShown()))
	-- in combat: the layout stays (the icon may not move), the texts update
	S.me.combat = true
	local order = {}
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() then order[#order + 1] = r.quest.id end end
	S.quests[2].objectives[1][1] = "Zelt verbrannt: 2/4"
	table.insert(S.quests, 1, { id = 603, title = "Neu im Kampf", level = 9, zone = "Elwynn Forest", objectives = { { "X: 0/1" } } })
	W.Fire("QUEST_LOG_UPDATE")
	QT.Refresh()
	local now = {}
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() then now[#now + 1] = r.quest.id end end
	check("in combat: the rows stay where they are", table.concat(now, ",") == table.concat(order, ","), table.concat(now, ","))
	check("...their counts still update", row.obj[1]:GetText() == "2/4 Zelt verbrannt")
	check("...nothing blocked", W.blockedCalls == blocked0, table.concat(W.blockedLog, ", "))
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	now = {}
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() then now[#now + 1] = r.quest.id end end
	check("after combat: sorted again, the new quest in", table.concat(now, ","):find("603", 1, true))
	-- the item quest gone: no icon
	table.remove(S.quests, 3)
	W.Fire("QUEST_LOG_UPDATE")
	QT.Refresh()
	check("no item quest left: no icon", not b:IsShown() and b:GetAttribute("item") == nil)
	S.quests, S.mapId, S.mapPos = nil, nil, nil
	W.Fire("QUEST_LOG_UPDATE")
end)()

-- WHERE A QUEST LEADS: THE GAME'S PINS ON EVERY CONTINENT, NO GUESS FOR DELIVERIES (3.47.1)
;(function()
	S.me.combat = false
	local Q, QT, QA = ns.Quests, ns.QuestTracker, ns.QuestArrow
	S.mapId, S.mapPos = 1457, { 0.32, 0.84 } -- Darnassus
	S.quests = {}
	W.Fire("QUEST_LOG_UPDATE")
	-- "Der geistesabwesende Ausgrabungsleiter": a delivery (nothing to do), accepted here
	S.quests = { { id = 942, title = "Der geistesabwesende Ausgrabungsleiter", level = 15, zone = "Darnassus", objectives = {}, complete = true } }
	W.Fire("QUEST_ACCEPTED", 1, 942)
	local function find(id) for _, q in ipairs(Q.Sorted("distance")) do if q.id == id then return q end end end
	local q = find(942)
	check("a delivery with no pin known: no target (not where you got it)", q.target == nil and q.yards == nil,
		q.target and q.target.kind)
	QT.Refresh()
	local row
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() and r.quest.id == 942 then row = r end end
	check("...the tracker shows no distance", row and row.dist:GetText() == "")
	Q.Select(942)
	check("...and no arrow", not QA.frame:IsShown())
	-- the game's pin for it on the other continent (Menethil: Wetlands)
	S.questPins = { [1415] = { { questID = 942, x = 0.43, y = 0.38 } } }
	S.zoneAt = { [1415] = "Sumpfland" }
	q = find(942)
	check("pins are kept a while (the client builds them anew on each call)", q.target == nil)
	W.Fire("QUEST_LOG_UPDATE") -- (the log changes: pins asked again)
	q = find(942)
	check("the game's pin on another continent: found", q.target and q.target.kind == "exact" and q.target.map == 1415, q.target and q.target.map)
	check("...shown as its zone (no yards across the sea)", q.yards == nil and QT.DistanceText(q):lower() == "sumpfland", QT.DistanceText(q))
	W.Fire("QUEST_LOG_UPDATE")
	QA.Update()
	check("...the arrow names the zone", QA.frame:IsShown() and QA.frame.dist:GetText():lower() == "in sumpfland", QA.frame.dist:GetText())
	-- a pin on your own continent's map: yards and a direction across zones
	S.questPins = { [1414] = { { questID = 942, x = 0.45, y = 0.25 } } }
	S.mapPosOn = { [1414] = { 0.40, 0.20 } } -- (Darnassus on Kalimdor's map)
	ns.Quests.ForgetPins()
	q = find(942)
	check("a pin on your continent's map: yards and a direction", q.target.map == 1414 and q.yards and q.yards > 0 and q.bearing ~= nil,
		tostring(q.yards))
	Q.Select(nil)
	S.questPins, S.zoneAt, S.mapPosOn, S.quests, S.mapId, S.mapPos = nil, nil, nil, nil, nil, nil
	W.Fire("QUEST_LOG_UPDATE")
end)()

-- /sitrep doctor AND /sitrep perf (3.48) ------------------------------------------------
;(function()
	S.me.combat = false
	-- the doctor: every check, the count, the problems
	local n0 = #W.prints
	SlashCmdList.SITREP("doctor")
	local chat = table.concat(W.prints, "\n", n0 + 1)
	local report = table.concat(SITREP_DB.reports.doctor.lines, "\n")
	check("doctor: a count in the chat", chat:find("doctor: %d+ OK, %d+ WARN, %d+ FAIL") ~= nil, chat)
	check("doctor: every section in the report", report:find("== blizzard frames", 1, true) and report:find("== secure buttons", 1, true)
		and report:find("== nameplates", 1, true) and report:find("== quests", 1, true))
	check("doctor: the bag button is a secure click", report:find("[OK] bag button: a secure click on Blizzard's backpack", 1, true))
	check("doctor: the MENU list's entries", report:find("[OK] MENU list: 8 entries, 0 without their secure click", 1, true), report)
	check("doctor: no stale plates", report:find("[OK] stale plate entries", 1, true))
	check("doctor: the bar frames take no clicks", report:find("[OK] Blizzard's empty bar frames take no clicks", 1, true))
	check("doctor: blocked actions of this session named (the test fired some)", report:find("[FAIL] actions the client blocked for SITREP", 1, true)
		and chat:find("[FAIL] actions the client blocked for SITREP", 1, true))
	-- a problem it must find: the main bar frame taking clicks again
	MainActionBar:EnableMouse(true)
	SlashCmdList.SITREP("doctor")
	report = table.concat(SITREP_DB.reports.doctor.lines, "\n")
	check("doctor finds a frame swallowing clicks", report:find("[FAIL] Blizzard's empty bar frames take no clicks: NOT MainActionBar", 1, true))
	MainActionBar:EnableMouse(false)
	-- and a bag button that lost its secure click
	local bb = ns.Bags.button
	bb:SetAttribute("type1", nil)
	SlashCmdList.SITREP("doctor")
	report = table.concat(SITREP_DB.reports.doctor.lines, "\n")
	check("doctor finds a bag button without its secure click", report:find("[FAIL] bag button: NOT set", 1, true))
	bb:SetAttribute("type1", "click")

	-- perf: measures the bus by file and the wrapped loops, then a verdict
	SlashCmdList.SITREP("perf 60")
	check("perf: measuring", ns.perf ~= nil and ns.Perf.run ~= nil)
	W.Update(0.3)
	W.Update(0.3)
	n0 = #W.prints
	SlashCmdList.SITREP("perf stop")
	check("perf stopped: nothing measured any more", ns.perf == nil)
	local pr = table.concat(SITREP_DB.reports.perf.lines, "\n")
	check("perf: the cost per frame and a verdict", pr:find("SITREP: [%d%.]+ ms per second, [%d%.]+ ms per frame: ") ~= nil, pr)
	check("perf: bus handlers by file", pr:find("SR_TICK @Sensors", 1, true) ~= nil or W.has(pr, "SR_TICK @UI/") ~= nil, pr)
	check("perf: the wrapped loops (an OnUpdate by its label)", pr:find("%a %(%a[%w%.]*%)%s") ~= nil, pr)
	check("perf: one line in the chat", table.concat(W.prints, "\n", n0 + 1):find("SITREP costs [%d%.]+ ms per frame") ~= nil)
	check("perf: verdicts", ns.Perf.Verdict(0.2) == "fine" and ns.Perf.Verdict(1) == "noticeable in a crowd" and ns.Perf.Verdict(3) == "too much")
end)()

;(function()
	-- perf counts each handler's own time: one that fires another event does not include the other's
	local function spin(ms) local t = os.clock() + ms / 1000 while os.clock() < t do end end
	ns.On("SR_TEST_INNER", function() spin(20) end)
	ns.On("SR_TEST_OUTER", function() spin(2); ns.Fire("SR_TEST_INNER") end)
	ns.perf = {}
	ns.Fire("SR_TEST_OUTER")
	local outer, inner
	for label, d in pairs(ns.perf) do
		if label:find("^SR_TEST_OUTER") then outer = d.ms elseif label:find("^SR_TEST_INNER") then inner = d.ms end
	end
	ns.perf = nil
	check("perf: a handler's own time, not the handlers it set off", outer and inner and inner >= 15 and outer < 10, tostring(outer) .. " " .. tostring(inner))

	local N = ns.Plates
	local C_ = ns.Sensors.contacts
	C_["Player-2-9990"] = { targetingMe = true }
	check("plates: priorities", N.Interval({ isTarget = true }) == 0 and N.Interval({ urgent = true }) == 0
		and N.Interval({ isPlayer = true, friend = false, guid = "Player-2-9990" }) == 0.15
		and N.Interval({ isPlayer = true, friend = false }) == 0.3
		and N.Interval({ isPlayer = true, friend = true }, true) == 0.5 and N.Interval({ isPlayer = true, friend = true }, false) == 1.5
		and N.Interval({ isPlayer = false, friend = false }, true) == 0.5 and N.Interval({ isPlayer = false, friend = true }, false) == 2)
	C_["Player-2-9990"] = nil
end)()

;(function()
	-- what a plate's unit is: kept half a second, asked again for someone else on the plate
	local S_ = ns.Sensors
	S.units.nameplate77 = { name = "Passant", guid = "Player-1-7700", class = "MAGE", level = 30, isPlayer = true, hostile = false, faction = "Alliance", dist = 20, screenX = 700 }
	local t = GetTime()
	check("plate kind: a friendly player", S_.PlateKind("nameplate77", t) == "friend")
	local realFriend, asked = UnitIsFriend, 0
	UnitIsFriend = function(...) asked = asked + 1 return realFriend(...) end
	check("...kept: not asked again at once", S_.PlateKind("nameplate77", t + 0.1) == "friend" and asked == 0, asked)
	S.units.nameplate77.hostile = true
	check("...a duel starts: hostile at once", S_.PlateKind("nameplate77", t + 0.2) == "hostile")
	S.units.nameplate77 = { name = "Orc", guid = "Player-2-7701", class = "ROGUE", level = 30, isPlayer = true, hostile = true, faction = "Horde", dist = 20, screenX = 700 }
	check("...someone else on the plate: asked again", S_.PlateKind("nameplate77", t + 0.3) == "hostile")
	S.units.nameplate77 = { name = "Wache", guid = "Creature-0-1-0-1-68-7702", isPlayer = false, hostile = false, reaction = 5, dist = 20, screenX = 700 }
	check("...a guard: other", S_.PlateKind("nameplate77", t + 0.35) == "other")
	UnitIsFriend = realFriend
	S.units.nameplate77 = nil
	S_._plateKinds.nameplate77 = nil
end)()

;(function()
	-- the range ladder searched by halving: the same bracket as asking every check, with fewer questions
	local S_ = ns.Sensors
	local function linear(unit, list)
		local lo, hi = 0, nil
		for _, c in ipairs(list) do
			if not c.dead then
				local r
				if c.kind == "spell" then r = C_Spell.IsSpellInRange(c.id, unit)
				elseif c.kind == "item" then r = c.fn(c.id, unit)
				else r = CheckInteractDistance(unit, c.idx) end
				if r == true or r == 1 then
					if not hi or c.max < hi then hi = c.max end
					if c.min > lo then lo = c.min end
				elseif r ~= nil and c.min == 0 and c.max > lo then lo = c.max end
			end
		end
		if hi and lo > hi then lo = hi end
		return lo, hi
	end
	S.me.combat = false
	-- a long ladder like the game's: two items per 5 yd step, one silent; a spell with a minimum range
	local long = {}
	local function inRange(max) return function(_, unit) return S.units[unit].dist <= max end end
	for yd = 5, 45, 5 do
		long[#long + 1] = { kind = "item", id = yd, fn = inRange(yd), min = 0, max = yd }
		long[#long + 1] = { kind = "item", id = 1000 + yd, fn = function() return nil end, min = 0, max = yd }
	end
	long[#long + 1] = { kind = "item", id = 75, min = 8, max = 35, -- (a check with a minimum range, like Auto Shot's 8-35)
		fn = function(_, unit) local d = S.units[unit].dist return d >= 8 and d <= 35 end }
	table.sort(long, function(a, b) return a.max < b.max end)
	local same, fewer, n = true, true, 0
	for _, hostile in ipairs({ true, false, "long" }) do
		for d = 1, 60, 3 do
			S.units.nameplate78 = { name = "Probe", guid = "Player-1-7800", class = "MAGE", level = 30, isPlayer = true, hostile = hostile,
				faction = hostile and "Horde" or "Alliance", dist = d, screenX = 700 }
			local list = hostile == "long" and long or hostile and S_.checks or S_.helpChecks
			if hostile == "long" then S.units.nameplate78.hostile = true; S.units.nameplate78.faction = "Horde" end
			local a0 = S_.stats.rangeAsked
			local lo, hi = S_.MeasureRange("nameplate78", nil, list)
			local asked = S_.stats.rangeAsked - a0
			local llo, lhi = linear("nameplate78", list)
			if lo ~= llo or hi ~= lhi then same = false; print("  range mismatch", hostile, d, lo, hi, llo, lhi) end
			if asked > #list then fewer = false end
			n = n + 1
		end
	end
	check("range by halving: the same bracket as every check (" .. n .. " distances, both ladders)", same)
	-- far away: a handful of questions, not the whole ladder
	S.units.nameplate78.dist = 80
	local a0 = S_.stats.rangeAsked
	S_.MeasureRange("nameplate78", nil, long)
	local asked = S_.stats.rangeAsked - a0
	check("range by halving: far away asks few checks", fewer and asked <= 8, asked .. " of " .. #long)
	S.units.nameplate78 = nil
end)()

;(function()
	-- a cast whose interruptibility is secret: the client paints its colour once per cast, not 20 times a second
	if not CreateColor then return end
	local host = CreateFrame("Frame", nil, UIParent)
	ns.Units.CastBar(host, host, 10)
	host.cast:Show()
	host.castNotInt, host.castNotIntRaw, host.castIntPainted = nil, W.Secret(true), nil
	local real, asked = C_CurveUtil.EvaluateColorFromBoolean, 0
	C_CurveUtil.EvaluateColorFromBoolean = function(...) asked = asked + 1 return real(...) end
	for _ = 1, 5 do ns.Units.PaintCast(host) end
	check("secret interruptibility: painted once per cast", asked == 1, asked)
	host.castIntPainted = nil -- (a new cast)
	ns.Units.PaintCast(host)
	check("...and again for the next cast", asked == 2, asked)
	C_CurveUtil.EvaluateColorFromBoolean = real
end)()

;(function()
	-- emergency items: the best healthstone and potion in your bags, lit when your health is low
	local EM = ns.Emergency
	S.me.combat = false
	S.items = { [5509] = 1, [929] = 3, [118] = 5 }
	W.Fire("BAG_UPDATE_DELAYED")
	local hs, pot = EM.buttons[1], EM.buttons[2]
	check("emergency: the best healthstone and potion", hs.itemID == 5509 and pot.itemID == 929 and pot:GetAttribute("item") == "item:929"
		and pot:GetAttribute("type") == "item", tostring(pot.itemID))
	check("emergency: shown by the game in combat only (a visibility driver)", W.stateDrivers[EM.holder] and W.stateDrivers[EM.holder].visibility == "[combat] show; hide")
	local pu = S.units.player
	local savedHp = pu.hp
	pu.hp = pu.hpMax
	W.Update(0.25)
	check("emergency: dim while you are fine", pot:GetAlpha() < 1 and not pot.glow:IsShown())
	pu.hp = math.floor(pu.hpMax * 0.2)
	W.Update(0.25)
	check("emergency: low health, ready: lit and pulsing", pot:GetAlpha() == 1 and pot.glow:IsShown() and pot.count:GetText() == "3",
		tostring(pot:GetAlpha()) .. " " .. tostring(ns.Pressure.HealthFrac()) .. " " .. tostring(pot.count:GetText()))
	S.itemCD = { [929] = { GetTime() - 5, 120 } }
	EM.Update()
	check("emergency: on cooldown: not lit", pot:GetAlpha() < 1 and not pot.glow:IsShown())
	S.itemCD = nil
	-- one you cannot use yet: the next one down
	S.unusable = { [929] = true }
	W.Fire("BAG_UPDATE_DELAYED")
	check("emergency: an item you cannot use yet is skipped", pot.itemID == 118, tostring(pot.itemID))
	S.unusable = nil
	-- bags change in combat: chosen after the fight
	S.me.combat = true
	S.items[13446] = 2
	W.Fire("BAG_UPDATE_DELAYED")
	check("emergency: not re-chosen in combat", pot.itemID == 118)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	check("...after the fight", pot.itemID == 13446, tostring(pot.itemID))
	-- placing it: on screen with the HUD unlocked
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	check("emergency: shown while placing", EM.holder:IsShown() and not W.stateDrivers[EM.holder].visibility)
	-- the buttons cover the holder: a grip over them takes the drag
	local grip = EM.holder.srGrip
	check("emergency: a grip over the buttons while unlocked", grip:IsShown() and grip:GetFrameLevel() > EM.buttons[1]:GetFrameLevel())
	EM.holder._x, EM.holder._y = 640, 300
	grip._scripts.OnDragStart(grip)
	grip._scripts.OnDragStop(grip)
	check("emergency: dragged by its grip, the place kept", ns.P.hud.pos.emergency ~= nil)
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	check("emergency: locked, the grip gone (the buttons take clicks)", not grip:IsShown())
	-- off
	ns.P.frames.emergency = false; ns.Changed("frames.emergency")
	check("emergency off: hidden, no item", not EM.holder:IsShown() and pot.itemID == nil)
	ns.P.frames.emergency = true; ns.Changed("frames.emergency")
	pu.hp, S.items = savedHp, nil
	W.Fire("BAG_UPDATE_DELAYED")
end)()

;(function()
	local S_, TG = ns.Sensors, ns.Targeting
	-- spawn age from a creature's GUID: the last six hex digits are its spawn second (mod 2^23)
	local now = 1760000000
	local at = (now - 245) % 2 ^ 23
	local guid = string.format("Creature-0-4170-0-1519-299-%04X%06X", 0x1234, at)
	check("GUID: zone (layer), NPC, spawn", select(1, S_.GuidParts(guid)) == 1519 and select(2, S_.GuidParts(guid)) == 299)
	check("spawn age: 245 s", S_.SpawnAge(guid, now) == 245, tostring(S_.SpawnAge(guid, now)))
	check("spawn age: none for players", S_.SpawnAge("Player-1-0001", now) == nil)
	check("since: 45s, 4m, 2h05m", ns.HUD.Since(45) == "45s" and ns.HUD.Since(245) == "4m" and ns.HUD.Since(7500) == "2h05m")
	;(function()
		-- respawn times: a mob seen dying, one of its kind seen fresh nearby later
		local SP = ns.Spawns
		local function guidAt(zone, npc, spawnAt, n)
			return string.format("Creature-0-4170-0-%d-%d-%04X%06X", zone, npc, n, spawnAt % 2 ^ 23)
		end
		local T0 = 1760500000
		S.serverTime, S.mapId, S.mapPos = T0, 1429, { 0.5, 0.5 }
		S.units.nameplate90 = { name = "Kobold Vermin", guid = guidAt(1519, 6, T0 - 900, 1), isPlayer = false, hostile = true, dead = true, dist = 10 }
		W.Fire("UNIT_HEALTH", "nameplate90")
		W.Fire("UNIT_HEALTH", "nameplate90")
		check("a mob dies: noted once", #SP.deaths == 1 and SP.deaths[1].npc == 6 and SP.deaths[1].at == T0)
		-- 7 minutes later a fresh one of its kind, spawned 5 minutes after the death, near
		S.serverTime = T0 + 420
		S.units.nameplate91 = { name = "Kobold Vermin", guid = guidAt(1519, 6, T0 + 300, 2), isPlayer = false, hostile = true, dist = 34 }
		W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate91")
		local mid, lo, hi, n, name = SP.For(6)
		check("...and back: 5 minutes after it died", mid == 300 and n == 1 and name == "Kobold Vermin", tostring(mid))
		check("plate reach: how far a plate appeared at least", SP.reach > 0, SP.reach)
		-- another copy of the zone (a layer), or a death already matched: no time
		S.units.nameplate90 = { name = "Kobold Vermin", guid = guidAt(1519, 6, T0, 3), isPlayer = false, hostile = true, dead = true, dist = 10 }
		W.Fire("UNIT_HEALTH", "nameplate90")
		S.serverTime = T0 + 900
		S.units.nameplate92 = { name = "Kobold Vermin", guid = guidAt(1600, 6, T0 + 600, 4), isPlayer = false, hostile = true, dist = 20 }
		W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate92")
		check("another layer: not counted", select(4, SP.For(6)) == 1)
		-- far from where it died: not counted
		S.mapPos = { 0.8, 0.8 }
		S.units.nameplate93 = { name = "Kobold Vermin", guid = guidAt(1519, 6, T0 + 610, 5), isPlayer = false, hostile = true, dist = 20 }
		W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate93")
		check("seen far from the death: not counted", select(4, SP.For(6)) == 1)
		S.mapPos = { 0.5, 0.5 }
		local n0 = #W.prints
		SlashCmdList.SITREP("spawns")
		local rep = table.concat(W.prints, "\n", n0 + 1)
		check("/sitrep spawns: plate reach and respawn times", rep:find("farthest a plate appeared", 1, true) and rep:find("Kobold Vermin (6): about 5:00", 1, true), rep)
		-- grinding spots: each kill and respawn also at its piece of the map
		local sp = SITREP_DB.spawnSpots and SITREP_DB.spawnSpots[1429] and SITREP_DB.spawnSpots[1429][SP.CellOf(1429, 0.5, 0.5)]
		check("spots: the kills and the respawn at their piece of the map", sp and sp.k == 2 and sp.n == 1 and sp.kinds[6] == "Kobold Vermin",
			sp and (sp.k .. " " .. sp.n))
		for i = 1, 2 do
			local tDeath = T0 + 1000 * i
			S.serverTime = tDeath
			S.units.nameplate90 = { name = "Kobold Vermin", guid = guidAt(1519, 6, tDeath - 300, 10 + i), level = 6, isPlayer = false, hostile = true, dead = true, dist = 10 }
			W.Fire("UNIT_HEALTH", "nameplate90")
			S.serverTime = tDeath + 200
			S.units.nameplate91 = { name = "Kobold Vermin", guid = guidAt(1519, 6, tDeath + 60, 20 + i), level = 6, isPlayer = false, hostile = true, dist = 30 }
			W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate91")
		end
		check("spots: three respawns seen there, ranked", #SP.Spots(1429) == 1 and SP.Spots(1429)[1].mid == 60, #SP.Spots(1429))
		n0 = #W.prints
		SlashCmdList.SITREP("spots")
		rep = table.concat(W.prints, "\n", n0 + 1)
		check("/sitrep spots: where, what, how fast; grey ones marked", rep:find("grinding spots in", 1, true)
			and rep:find("Kobold Vermin (level 6): back after about 1:00; 3 respawns, 4 kills seen  - grey for you", 1, true), rep)
		SITREP_DB.spawnSpots = nil
		for _, u in ipairs({ "nameplate90", "nameplate91", "nameplate92", "nameplate93" }) do S.units[u] = nil end
		S.serverTime, S.mapId, S.mapPos = nil, nil, nil
		SITREP_DB.spawns = nil
	end)()
	-- the layer: most creatures on the plates share a zoneUID; another one on the same map fires SR_LAYER
	local layers = {}
	ns.On("SR_LAYER", function(_, new, old) layers[#layers + 1] = { new, old } end)
	local savedGUID = S_.plateGUID
	S_.plateGUID = { nameplate90 = "Creature-0-1-0-100-5-0000000001", nameplate91 = "Creature-0-1-0-100-6-0000000002" }
	S_.layer.map, S_.layer.id = nil, nil
	S_.LayerScan()
	local map0 = S_.layer.map
	check("layer: learned without a word", S_.layer.id == 100 and #layers == 0)
	S_.plateGUID = { a = "Creature-0-1-0-200-5-0000000001", b = "Creature-0-1-0-200-6-0000000002", c = "Creature-0-1-0-200-7-0000000003" }
	S_.LayerScan()
	check("layer: changed on the same map: SR_LAYER", #layers == 1 and layers[1][1] == 200 and layers[1][2] == 100 and S_.layer.map == map0)
	S_.plateGUID = savedGUID
	-- healers by what they do: a heal on an enemy as another enemy's cast ends
	local C_ = S_.contacts
	C_["Player-2-H1"] = { key = "Player-2-H1", class = "PRIEST", live = true }
	C_["Player-2-W1"] = { key = "Player-2-W1", class = "WARRIOR", live = true }
	local realKey = S_.UnitKey
	S_.UnitKey = function(unit) return unit == "nameplate95" and "Player-2-H1" or unit == "nameplate96" and "Player-2-W1" or realKey(unit) end
	local found = {}
	ns.On("SR_HEALER", function(_, key) found[#found + 1] = key end)
	TG.CastDone("nameplate95", 100); TG.HealSeen("nameplate96", 900, 100.1)
	check("healer: one heal matched to the caster, not yet a healer", TG.healPoints["Player-2-H1"] == 1 and not TG.IsHealer(C_["Player-2-H1"]))
	TG.HealSeen("nameplate96", 900, 100.12)
	check("...the same heal through a second token counts once", TG.healPoints["Player-2-H1"] == 1)
	TG.CastDone("nameplate95", 103); TG.HealSeen("nameplate96", 950, 103.2)
	check("...the second: a healer (HEALER on its plate, SR_HEALER)", TG.IsHealer(C_["Player-2-H1"]) and found[1] == "Player-2-H1")
	TG.CastDone("nameplate96", 110); TG.HealSeen("nameplate96", 500, 110.1)
	check("self-heals do not count (a potion, a bandage)", (TG.healPoints["Player-2-W1"] or 0) == 0)
	TG.HealSeen("nameplate96", 500, 120)
	check("a heal with no cast near: no point", (TG.healPoints["Player-2-W1"] or 0) == 0 and TG.healStats.alone >= 1)
	C_["Player-2-H1"] = nil
	check("a healer stays one after its contact is forgotten", TG.IsHealer({ key = "Player-2-H1" }))
	S_.UnitKey = realKey
	C_["Player-2-W1"] = nil
	TG.knownHealers["Player-2-H1"], TG.healPoints["Player-2-H1"] = nil, nil
	-- the idea probe writes its report
	SlashCmdList.SITREP("ideaprobe")
	W.Fire("UNIT_COMBAT", "nameplate1", "HEAL", "", 300, 1)
	SlashCmdList.SITREP("ideaprobe stop")
	local rep = table.concat(SITREP_DB.reports.ideaprobe.lines, "\n")
	check("idea probe: report with every section", rep:find("UNIT_COMBAT by token", 1, true) and rep:find("== creatures", 1, true)
		and rep:find("== APIs: C_DamageMeter", 1, true), rep)
end)()

;(function()
	-- the death recap: each hit to its likeliest source
	local RC = ns.Recap
	wipe(RC.hits); wipe(RC.snaps); wipe(RC.landed)
	local t0 = GetTime()
	for i = 0, 10 do
		RC.snaps[#RC.snaps + 1] = { t = t0 + i, hp = 0.5, mobs = 0, emergency = false, cc = i >= 6 and i <= 8, enemies = {
			{ key = "Player-2-V", name = "Vex", class = "ROGUE", targetingMe = true, lo = 0, hi = 5 },
			{ key = "Player-2-A", name = "Aldwin", class = "MAGE", targetingMe = true, lo = 20, hi = 25 } } }
	end
	for i = 1, 8 do RC.hits[#RC.hits + 1] = { t = t0 + i, amount = 300, school = 1 } end
	RC.hits[#RC.hits + 1] = { t = t0 + 3, amount = 900, school = 16 }
	RC.hits[#RC.hits + 1] = { t = t0 + 9.6, amount = 1840, school = 16, crit = true }
	RC.hits[#RC.hits + 1] = { t = t0 + 5, amount = 400, heal = true }
	table.sort(RC.hits, function(a, b) return a.t < b.t end)
	RC.landed = { { t = t0 + 2.2, key = "Player-2-A", sure = true }, { t = t0 + 9.0, key = "Player-2-A", sure = true } }
	local r = RC.Build(t0 + 10, "death")
	local by = {}
	for _, src in ipairs(r.sources) do by[src.name] = src end
	check("recap: the fight's length, damage and healing", math.abs(r.dur - 9) < 1e-6 and r.total == 5140 and r.healIn == 400, r.dur .. " " .. r.total)
	check("recap: melee hits to the rogue in melee range, bolts to the mage whose cast just ended",
		by.Vex and by.Aldwin and math.abs(by.Vex.dmg - 2381) < 2 and math.abs(by.Aldwin.dmg - 2759) < 2 and r.sources[1].name == "Aldwin",
		by.Vex and (by.Vex.dmg .. " / " .. by.Aldwin.dmg))
	check("recap: their main school", by.Vex.school == 1 and by.Aldwin.school == 16)
	check("recap: the biggest hit, from whom, how long before", r.biggest.amount == 1840 and r.biggest.crit and r.biggest.name == "Aldwin"
		and math.abs(r.biggest.before - 0.4) < 1e-6)
	check("recap: the share that hit you while you could not act", math.abs(r.ccShare - 900 / 5140) < 1e-6, r.ccShare)
	check("recap: a tip from it", r.tips[1] and r.tips[1]:find("Aldwin dealt 54%% with spells", 1) ~= nil, r.tips[1])
	-- the emergency items ready and unused: the first tip
	for _, sn in ipairs(RC.snaps) do sn.emergency = true end
	r = RC.Build(t0 + 10, "death")
	check("recap: emergency items ready and unused", r.emergencyUnused and r.tips[1]:find("potion", 1, true) ~= nil, r.tips[1])
	-- death: stored and shown; a lost duel too
	ns.P.log.recapPopup = true
	local got
	ns.On("SR_RECAP", function(_, rr) got = rr end)
	-- (the same fight, as if it ended just now)
	local shift = GetTime() + 0.5 - (t0 + 10)
	for _, list in ipairs({ RC.hits, RC.snaps, RC.landed }) do for _, e in ipairs(list) do e.t = e.t + shift end end
	W.Fire("PLAYER_DEAD")
	check("recap on death: built, kept, shown", got and got.how == "death" and ns.db.log.deaths[1] == got and ns.RecapPanel.frame:IsShown()
		and ns.RecapPanel.frame.head:GetText():find("Dead after", 1, true))
	ns.RecapPanel.frame:Hide()
	SlashCmdList.SITREP("recap")
	check("/sitrep recap shows it again", ns.RecapPanel.frame:IsShown())
	ns.Fire("SR_DUEL_RESULT", { won = false, opponent = "Vex" })
	check("recap after a lost duel", got.how == "duel" and W.has(ns.RecapPanel.frame.title:GetText(), "DUEL LOST"))
	ns.RecapPanel.frame:Hide()
	-- an unknown source when nothing fits
	wipe(RC.snaps); wipe(RC.landed); wipe(RC.hits)
	RC.hits[1] = { t = t0, amount = 500, school = 32 }
	r = RC.Build(t0 + 1)
	check("recap: nothing fits: unknown", r.sources[1].name == "Unknown" and r.sources[1].share == 1)
	wipe(RC.hits)
	-- from the client's events: hits on you, their school, critical
	W.Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 700, 4)
	check("recap: a hit on you recorded with school and crit", RC.hits[1] and RC.hits[1].amount == 700 and RC.hits[1].school == 4 and RC.hits[1].crit)
	wipe(RC.hits)
end)()

;(function()
	-- stealth: an enemy rogue close by, whose plate goes while it is alive: AoE
	local fired = {}
	ns.On("SR_STEALTH", function(_, c, d) fired[#fired + 1] = { c = c, d = d } end)
	local savedCombat = S.me.combat
	S.me.combat = false
	local function rogue(dist, class)
		S.units.nameplate97 = { name = "Vex", guid = "Player-2-0097", class = class or "ROGUE", level = 60, isPlayer = true, hostile = true,
			faction = "Horde", dist = dist, screenX = 900, targetOf = S.units.player }
		W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate97")
		W.Update(0.25)
	end
	rogue(12)
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate97")
	check("stealth: a rogue's plate gone 12 yd away: SR_STEALTH", #fired == 1 and fired[1].c.class == "ROGUE" and fired[1].d >= 12 and fired[1].d <= 20, fired[1] and fired[1].d)
	S.units.nameplate97 = nil
	W.Update(2)
	rogue(12, "WARRIOR")
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate97")
	check("...a warrior: no", #fired == 1)
	S.units.nameplate97 = nil
	W.Update(2)
	rogue(12)
	S.units.nameplate97.dead = true
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate97")
	check("...a dead rogue: no", #fired == 1)
	S.units.nameplate97 = nil
	W.Update(2)
	ns.P.alerts.stealth = false
	rogue(12)
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate97")
	check("...switched off: no", #fired == 1)
	ns.P.alerts.stealth = true
	S.units.nameplate97 = nil
	W.Update(2)
	S.me.combat = savedCombat
end)()

;(function()
	-- kick trainer and lockouts
	local I, S_ = ns.Incoming, ns.Sensors
	I.BuildInterrupts()
	local C_ = S_.contacts
	C_["Player-2-K1"] = { key = "Player-2-K1", class = "MAGE", name = "Aldwin", live = true }
	local realKey = S_.UnitKey
	S_.UnitKey = function(unit) return unit == "nameplate98" and "Player-2-K1" or realKey(unit) end
	I.fight = { landed = 0, react = 0, missed = 0, fakes = 0 }
	I.EnemyStart("nameplate98", 100)
	I.KickCast("player", 2139, 100.6)
	I.EnemyBroken("nameplate98", 100.65)
	check("kick: yours landed, its school locked for the lockout (Counterspell 10 s)", I.fight.landed == 1 and math.abs(I.fight.react - 0.6) < 1e-6
		and math.abs(I.LockLeft("Player-2-K1", 105) - 5.6) < 1e-6, tostring(I.LockLeft("Player-2-K1", 105)))
	check("...gone when it runs out", I.LockLeft("Player-2-K1", 111) == nil)
	-- the interrupt reported before your cast
	I.EnemyStart("nameplate98", 200)
	I.EnemyBroken("nameplate98", 200.5)
	I.KickCast("player", 2139, 200.6)
	check("kick: the interrupt reported first still counts", I.fight.landed == 2)
	-- a cast broken off early that no interrupt explains: a fake; three of them: FAKER
	I.Settle(201)
	check("...and is no fake", I.fight.fakes == 0, I.fight.fakes)
	for i = 1, 3 do
		I.EnemyStart("nameplate98", 300 + i * 10)
		I.EnemyBroken("nameplate98", 300.4 + i * 10)
		I.Settle(301 + i * 10)
	end
	check("fakes: counted, FAKER after three", I.fight.fakes == 3 and I.IsFaker("Player-2-K1"))
	check("kick line", I.KickLine(I.fight) == "Kicks 2 of 2  ·  avg 0.60 s  ·  3 fakes", I.KickLine(I.fight))
	check("not an interrupt: nothing", I.InterruptOf(116) == nil and I.InterruptOf(2139) ~= nil)
	S_.UnitKey = realKey
	C_["Player-2-K1"] = nil
	I.locks["Player-2-K1"], I.fakes["Player-2-K1"] = nil, nil

	-- toughness: health against the average of its class and level, judged by the spread
	-- (players met earlier in the tests count too now: a clean start for this class)
	ns.db.toughness["ROGUE:60"] = nil
	for i, hp in ipairs({ 2800, 2900, 3000, 3100, 3200, 2800, 2900, 3000, 3100, 3200 }) do S_.ToughSample("Player-1-T" .. i, "ROGUE", 60, hp) end
	S_.ToughSample("Player-1-T1", "ROGUE", 60, 9999) -- (the same player again: once)
	local ratio, z = S_.ToughRatio("ROGUE", 60, 3000)
	check("toughness: the average of its class and level", math.abs(ratio - 1) < 1e-9 and math.abs(z) < 1e-9, ratio)
	check("toughness: by the spread: LOW, HIGH, VERY HIGH, about average nothing",
		S_.ToughLabel(select(2, S_.ToughRatio("ROGUE", 60, 2800))) == "LOW" and S_.ToughLabel(select(2, S_.ToughRatio("ROGUE", 60, 3200))) == "HIGH"
		and S_.ToughLabel(select(2, S_.ToughRatio("ROGUE", 60, 3600))) == "VERY HIGH" and S_.ToughLabel(select(2, S_.ToughRatio("ROGUE", 60, 3100))) == nil)
	check("toughness: too few seen yet: nothing", S_.ToughRatio("PALADIN", 60, 4000) == nil)
	local e = ns.db.toughness["ROGUE:60"]
	check("toughness: kept as one mean and spread per class and level", e.n == 10 and math.abs(math.sqrt(e.var) - 141.42) < 0.1, math.sqrt(e.var))
	-- health buffs are taken off before a player counts towards the averages
	S.units.nameplate99 = { name = "Buffed", guid = "Player-1-T99", class = "ROGUE", level = 60, isPlayer = true, hostile = false, hpMax = 3540, hp = 3540 }
	S.auras = S.auras or {}
	S.auras.nameplate99 = { { id = 991, spellId = 10938, name = "Power Word: Fortitude" }, { id = 992, spellId = 24425, name = "Spirit of Zandalar" } }
	local base, ok = S_.Unbuffed("nameplate99", 3540)
	check("toughness: Fortitude (54 stamina) and Zandalar (15 %) taken off", ok and math.abs(base - 3000 / 1.15) < 1e-6, base)
	local r99, z99 = S_.Tough("nameplate99", "Player-1-T99")
	check("...but judged with the health it has, buffs and all", math.abs(r99 - 3540 / ns.db.toughness["ROGUE:60"].mean) < 1e-9 and z99 > 2)
	-- a tauren (Endurance, +5 %): counted without it
	local n0 = ns.db.toughness["WARRIOR:60"] and ns.db.toughness["WARRIOR:60"].n or 0
	S.units.nameplate99 = { name = "Moo", guid = "Player-2-T98", class = "WARRIOR", race = "Tauren", level = 60, isPlayer = true, hostile = true, hpMax = 4200, hp = 4200 }
	S.auras.nameplate99 = {}
	S_.Tough("nameplate99", "Player-2-T98")
	local w = ns.db.toughness["WARRIOR:60"]
	check("toughness: a tauren's Endurance taken off for the averages", w and w.n == n0 + 1 and (n0 > 0 or math.abs(w.mean - 4000) < 1e-6), w and w.mean)
	S.units.nameplate99, S.auras.nameplate99 = nil, nil
	-- each player once in a week, also across sessions (the same few met again would make the average theirs)
	local m0 = ns.db.toughness["MAGE:30"] and ns.db.toughness["MAGE:30"].n or 0
	S_.ToughSample("Player-1-W1", "MAGE", 30, 1500)
	S_.toughSeen["Player-1-W1"] = nil -- (a new session)
	S_.ToughSample("Player-1-W1", "MAGE", 30, 1500)
	check("toughness: the same player in a new session: not again", ns.db.toughness["MAGE:30"].n == m0 + 1 and S_.toughWhy["Player-1-W1"] == "known")
	ns.db.toughSeen["Player-1-W1"] = ns.db.toughSeen["Player-1-W1"] - 8
	S_.toughSeen["Player-1-W1"] = nil
	S_.ToughSample("Player-1-W1", "MAGE", 30, 1500)
	check("...a week later: counted again (gear changes)", ns.db.toughness["MAGE:30"].n == m0 + 2)
	-- too few at that level: the levels around it help, scaled to it
	ns.db.toughness["HUNTER:14"] = { n = 4, mean = 368, var = 400 }
	ns.db.toughness["HUNTER:15"] = { n = 3, mean = 395, var = 400 }
	ns.db.toughness["HUNTER:13"] = { n = 2, mean = 340, var = 400 }
	local mean, _, cnt, how = S_.ToughBase("HUNTER", 14)
	check("toughness: neighbours pooled (4 + 3 + 2 seen), about the level's own", how == "near" and cnt == 9 and mean > 360 and mean < 376, mean)
	check("...a hunter at 14 with 450 health: HP+ or more", S_.ToughLabel(select(2, S_.ToughRatio("HUNTER", 14, 450))) ~= nil)
	check("...levels too far away do not help", S_.ToughBase("HUNTER", 25) == nil)
	-- group members, your target and the one under the mouse are counted too (no plate needed)
	S.units.mouseover = { name = "Hovered", guid = "Player-1-MO1", class = "PRIEST", level = 42, isPlayer = true, hostile = false, hpMax = 2000, hp = 2000 }
	S.auras = S.auras or {}; S.auras.mouseover = {}
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	check("toughness: the player under the mouse counted", S_.toughWhy["Player-1-MO1"] == "counted")
	S.units.mouseover, S.auras.mouseover = nil, nil
	local n0p = #W.prints
	SlashCmdList.SITREP("tough")
	local rep = table.concat(W.prints, "\n", n0p + 1)
	check("/sitrep tough: counted, why not, per class", rep:find("players met this session", 1, true) and rep:find("levels 13 14 15", 1, true)
		and rep:find("health hidden by the client", 1, true) and rep:find("players remembered", 1, true), rep)

	-- experience: Classic's formula, kills to the next level
	local X = ns.XP
	check("xp per kill: same level, above, below, grey, elite", X.MobXP(30, 30) == 195 and X.MobXP(32, 30) == 225 and X.MobXP(25, 30) == 99
		and X.MobXP(22, 30) == 0 and X.MobXP(30, 30, true) == 390, X.MobXP(25, 30))
	local pu = S.units.player
	local savedLvl, savedRested = pu.level, S.me.rested
	pu.level, S.me.rested = 30, 600
	check("level up in: with rested experience", X.KillsToLevel(30) == 16, tostring(X.KillsToLevel(30)))
	pu.level, S.me.rested = savedLvl, savedRested
	check("level up in: nothing at the level cap", X.KillsToLevel(60) == nil)

	-- durability: the most worn piece
	S.durability = { [5] = { 20, 100 }, [7] = { 80, 100 } }
	check("durability: the most worn piece", ns.Recap.Durability() == 20)
	S.durability = nil
end)()

;(function()
	-- is a quest worth it? experience per minute against killing mobs, at your own pace
	local Q = ns.Quests
	ns.db.pace = { sec = 30, n = 0 }
	-- your pace, learned from the kills that gave experience
	Q.KillXP("Kobold Vermin stirbt, Ihr bekommt 100 Erfahrung.", 1000)
	Q.KillXP("Kobold Vermin stirbt, Ihr bekommt 100 Erfahrung. (+50 Erfahrung Erholt-Bonus)", 1020)
	Q.KillXP("Kobold Vermin stirbt, Ihr bekommt 100 Erfahrung.", 1400) -- (a break between: not counted)
	check("pace: seconds per kill learned, breaks left out", math.abs(ns.db.pace.sec - 29) < 1e-9 and ns.db.pace.xp == 100, ns.db.pace.sec)
	ns.db.pace.sec = 30
	check("pace: killing mobs: 200 XP a minute", math.abs(Q.GrindRate() - 200) < 1e-9, Q.GrindRate())
	local function quest(t) local q = { id = t.id, title = "Q", level = t.level, objectives = t.objectives or {}, complete = t.complete, yards = t.yards, group = t.group }
		return q end
	local realText = Q.Text
	Q.Text = function(q) return nil, nil, q.xpReward end
	-- 8 kills left, 210 yd away: (30 s + 240 s) = 4.5 min for 1350 XP and 8 kills of
	-- 100: 2150 XP, 478 a minute: worth it (killing mobs: 200)
	local q1 = quest({ id = 1, level = ns.Sensors.self.level, yards = 210, objectives = { { text = "Kobold Vermin slain: 0/8", have = 0, need = 8, kind = "monster" } } })
	q1.xpReward = 1350
	local v = Q.Value(q1)
	check("value: the way at a run plus the kills left; the kills' experience counts", math.abs(v.minutes - 4.5) < 1e-9
		and math.abs(v.xpm - 2150 / 4.5) < 1e-9 and v.killXP == 800 and v.rating == "great", v.minutes .. " " .. v.xpm)
	-- the same as a group quest, alone: 2.5 times the work (10.5 min)
	q1.group = true
	check("value: a group quest alone takes 2.5 times the work", math.abs(Q.Value(q1).minutes - 10.5) < 1e-9, Q.Value(q1).minutes)
	check("...still all right with its kills counted (milder than before)", Q.Value(q1).rating == "ok", Q.Value(q1).xpm)
	q1.group = nil
	-- far away, a thing to do and a small reward: not worth it (3000 yd at a run: 7 min)
	local q3 = quest({ id = 3, yards = 3000, objectives = { { text = "Talk to Marshal", have = 0, need = 1 } } })
	q3.xpReward = 300
	check("value: far, little to gain: not worth it", Q.Value(q3).rating == "poor", Q.Value(q3).xpm)
	-- almost done: 13 of 15 collected: never poor, marked
	local q4 = quest({ id = 4, yards = 3000, objectives = { { text = "Feathers: 13/15", have = 13, need = 15, kind = "item" } } })
	q4.xpReward = 100
	check("almost done: most counts reached", Q.Almost(q4) and math.abs(Q.Progress(q4) - 13 / 15) < 1e-9)
	check("almost done: not rated poor", Q.Value(q4).almost and Q.Value(q4).rating ~= "poor", Q.Value(q4).rating)
	check("half way: not almost done", not Q.Almost(quest({ objectives = { { text = "x", have = 4, need = 8 } } })))
	-- quests close together share the way: two more within 150 yd of this one's place
	local realSize = Q.MapSize
	Q.MapSize = function() return 1000, 1000 end
	q3.target = { map = 7, x = 0.50, y = 0.50 }
	local list = { q3, { id = 5, objectives = {}, target = { map = 7, x = 0.55, y = 0.55 } },
		{ id = 6, objectives = {}, target = { map = 7, x = 0.45, y = 0.50 } }, { id = 7, objectives = {}, target = { map = 7, x = 0.90, y = 0.90 } } }
	local alone, shared = Q.Value(q3), Q.Value(q3, list)
	check("close together: the way shared by three (one is far)", shared.near == 2 and math.abs(shared.travel - alone.travel / 3) < 1e-9, shared.near)
	check("...which makes it worth more", shared.xpm > alone.xpm * 2)
	Q.MapSize = realSize
	q3.target = nil
	-- ready to hand in: only the way, worth it
	local q2 = quest({ id = 2, complete = true, yards = 420 })
	q2.xpReward = 900
	check("value: ready to hand in: worth it", Q.Value(q2).rating == "great")
	-- riding: the way goes faster
	Q.rideSpeed = 14
	check("value: riding speed learned is used", math.abs(Q.Value(q1).travel - 15) < 1e-9)
	Q.rideSpeed = nil
	S.me.mounted, S.me.speed = true, 11.2
	W.Update(0.25)
	check("riding speed learned while mounted", Q.rideSpeed == 11.2)
	S.me.mounted, S.me.speed, Q.rideSpeed = nil, nil, nil
	Q.Text = realText
	ns.db.pace = nil
end)()

;(function()
	-- how far plates reach (plates.reach): the game's setting, its own value given back
	local N = ns.Plates
	SITREP_DB.plateReachOrig = nil
	W.cvars.nameplateMaxDistance = "45"
	ns.P.plates.reach = 60; ns.Changed("plates.reach")
	check("reach: set to 60 yd, the game's 45 kept", W.cvars.nameplateMaxDistance == "60" and SITREP_DB.plateReachOrig == "45", W.cvars.nameplateMaxDistance)
	ns.P.plates.reach = 80; ns.Changed("plates.reach")
	check("...changed again: the first value still kept", W.cvars.nameplateMaxDistance == "80" and SITREP_DB.plateReachOrig == "45")
	ns.P.plates.reach = 0; ns.Changed("plates.reach")
	check("...the game's own again: 45 back", W.cvars.nameplateMaxDistance == "45" and SITREP_DB.plateReachOrig == nil, W.cvars.nameplateMaxDistance)
	-- in combat the setting is protected: after it
	S.me.combat = true
	ns.P.plates.reach = 50; ns.Changed("plates.reach")
	check("reach in combat: waits", W.cvars.nameplateMaxDistance == "45" and N.reachPending)
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	check("...set after it", W.cvars.nameplateMaxDistance == "50", W.cvars.nameplateMaxDistance)
	local n0 = #W.prints
	SlashCmdList.SITREP("spawns")
	check("/sitrep spawns: says SITREP set it", table.concat(W.prints, "\n", n0 + 1):find("50 (set by SITREP)", 1, true))
	-- resting (4.7.6): no plates.reach in the profile any more: the game's own value back
	ns.P.plates.reach = nil; ns.Changed("plates.reach")
	check("reach resting: the game's 45 back once the setting is gone", W.cvars.nameplateMaxDistance == "45" and SITREP_DB.plateReachOrig == nil, W.cvars.nameplateMaxDistance)
	W.cvars.nameplateMaxDistance = nil
end)()

;(function()
	-- NPC plates (PlateNPC.lua): no bar, the name, its title under it, an icon for what it does
	local N, NP = ns.Plates, ns.PlateNPC
	check("icons: by the words in the title (trainers first)", NP.Icon("Rüstungsschmied"):find("Repair", 1, true)
		and NP.Icon("Schmiedekunstlehrer"):find("Profession", 1, true) and NP.Icon("Kriegerlehrerin"):find("Class", 1, true)
		and NP.Icon("Greifenmeister"):find("FlightMaster", 1, true) and NP.Icon("Gastwirtin"):find("Innkeeper", 1, true)
		and NP.Icon("Tierausbilder"):find("StableMaster", 1, true) and NP.Icon("Gemischtwaren"):find("Vendor", 1, true)
		and NP.Icon("Flight Master"):find("FlightMaster", 1, true) and NP.Icon("Stadtwache") == nil)
	-- the titles Forever's NPCs really have (npcprobe and the titles learned, 4.7.0)
	local want = { Kellnerin = "Food", Handwerksfrau = "Vendor", Pfeilmacherin = "Vendor", ["Bergbau- und Schmiedekunstbedarf"] = "Repair",
		Gemischtwaren = "Vendor", Schildmacherin = "Repair", ["Rüstungsschmied"] = "Repair", ["Lieferant für Köder und Angelzubehör"] = "Vendor",
		Schneiderbedarf = "Vendor", Gastwirtin = "Innkeeper", Stallmeister = "StableMaster",
		-- (npcprobe 4.11.0: a smith's supplies repair; ranks of a profession teach)
		Schmiedekunstbedarf = "Repair", Schmiedekunstgeselle = "Profession", Schmiedekunstexperte = "Profession",
		Schneiderfachmann = "Profession", Schneidergeselle = "Profession", Verzauberkunstexperte = "Profession",
		["Kräuterkundelehrerin"] = "Profession", ["Kräuterkundebedarfslieferantin"] = "Vendor", Florist = "Vendor",
		Greifenmeister = "FlightMaster", ["Käsemeister"] = "Food", ["Panzerrüstungshändler"] = "Repair",
		Magielehrerin = "Class", Portallehrerin = "Class", Meistermagier = "Class", Waffenmeister = "Class",
		["Axthändler"] = "Repair", ["Robenhändlerin"] = "Repair", Schneidereimuster = "Vendor" }
	check("icons: a barber is no beer", NP.Icon("Barbier") == nil and NP.Icon("Hexenmeisterlehrer"):find("Class", 1, true))
	local wrong = {}
	for title, icon in pairs(want) do if not (NP.Icon(title) or ""):find(icon, 1, true) then wrong[#wrong + 1] = title .. " " .. tostring(NP.Icon(title)) end end
	check("icons: every title seen on Forever so far has its icon (supplies are no smith)", #wrong == 0, table.concat(wrong, ", "))
	SITREP_DB.npcTitles = nil
	local realGet = C_NamePlate.GetNamePlateForUnit
	local plates = {}
	local function plateFor(unit, u)
		S.units[unit] = u
		local plate = CreateFrame("Frame")
		local uf = CreateFrame("Frame", nil, plate)
		uf.healthBar = CreateFrame("StatusBar", nil, uf)
		uf.name = uf:CreateFontString()
		plate.UnitFrame = uf
		plates[unit] = plate
		W.Fire("NAME_PLATE_UNIT_ADDED", unit)
		return N.skins[unit]
	end
	C_NamePlate.GetNamePlateForUnit = function(unit) return plates[unit] or realGet(unit) end
	local smith = plateFor("nameplate97", { name = "Thor", guid = "Creature-0-1-0-1-1234-00000000A1", level = 30, isPlayer = false,
		hostile = false, reaction = 5, wx = 10, wy = 0, screenX = 600, creatureType = "Humanoid", title = "Rüstungsschmied", hp = 900, hpMax = 900 })
	check("a friendly NPC: no bar, no thin line", smith and smith.svc and smith.zenOn and not smith.thin:IsShown(), smith and tostring(smith.svc))
	check("...its title under the name, the repair icon over it", smith.npcTitle:IsShown() and smith.npcTitle:GetText() == "<Rüstungsschmied>"
		and smith.npcIcon:IsShown() and smith.npcIcon._tex:find("Repair", 1, true), smith.npcTitle:GetText())
	check("...the name where the bar was", ({ smith.name:GetPoint(1) })[1] == "CENTER")
	check("a friendly NPC's name: sky blue (players are green)", smith.name._tc and math.abs(smith.name._tc[1] - 0.55) < 1e-6
		and math.abs(smith.name._tc[3] - 1) < 1e-6, smith.name._tc and smith.name._tc[1])
	check("its title kept for the account (by kind of NPC)", SITREP_DB.npcTitles and SITREP_DB.npcTitles[1234] == "Rüstungsschmied")
	-- your target: its full plate
	S.units.target = S.units.nameplate97
	W.Fire("PLAYER_TARGET_CHANGED")
	local ip = { smith.npcIcon:GetPoint(1) }
	check("targeted: the full plate again, its icon left of the bar", not smith.svc and not smith.zenOn and smith.npcIcon:IsShown()
		and ip[1] == "RIGHT" and ip[2] == smith and ip[3] == "LEFT" and not smith.npcTitle:IsShown(), tostring(ip[1]))
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
	ip = { smith.npcIcon:GetPoint(1) }
	check("...and its NPC look back after (the icon over the name again)", smith.svc and smith.npcIcon:IsShown() and ip[1] == "BOTTOM" and ip[2] == smith.name)
	-- a targeted NPC without an icon (a guard): nothing beside its bar
	local guard = plateFor("nameplate95", { name = "Wache", guid = "Creature-0-1-0-1-4567-00000000A4", level = 30, isPlayer = false,
		hostile = false, reaction = 5, wx = 9, wy = 0, screenX = 640, creatureType = "Humanoid", hp = 900, hpMax = 900 })
	S.units.target = S.units.nameplate95
	W.Fire("PLAYER_TARGET_CHANGED")
	check("a targeted guard (no title): no icon", not guard.npcIcon:IsShown())
	S.units.target = nil
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate95"); S.units.nameplate95 = nil
	-- neutral: a goblin trader yes, a boar no
	local goblin = plateFor("nameplate98", { name = "Krix", guid = "Creature-0-1-0-1-2345-00000000A2", level = 40, isPlayer = false,
		hostile = true, reaction = 4, wx = 12, wy = 0, screenX = 650, title = "Handwerkswaren", hp = 900, hpMax = 900 })
	local boar = plateFor("nameplate96", { name = "Eber", guid = "Creature-0-1-0-1-3456-00000000A3", level = 8, isPlayer = false,
		hostile = true, reaction = 4, wx = 14, wy = 0, screenX = 700, creatureType = "Wildtier", hp = 100, hpMax = 100 })
	check("a neutral trader: its NPC look (the trader's bag)", goblin.svc and goblin.npcIcon._tex:find("Vendor", 1, true))
	check("a neutral boar: its bar as before", not boar.svc and not boar.zenOn and not boar.npcIcon:IsShown())
	check("...and its name in the neutral yellow, not the NPC blue", boar.name._tc and boar.name._tc[3] < 0.5, boar.name._tc and boar.name._tc[3])
	-- switched off: every NPC its bar back
	ns.P.plates.npcIcons = false; ns.Changed("plates.npcIcons")
	check("switched off: bars back, no icons", not smith.svc and not smith.zenOn and not smith.npcIcon:IsShown() and not goblin.svc)
	ns.P.plates.npcIcons = true; ns.Changed("plates.npcIcons")
	for _, u in ipairs({ "nameplate96", "nameplate97", "nameplate98" }) do W.Fire("NAME_PLATE_UNIT_REMOVED", u); S.units[u] = nil end
	check("a plate gone: nothing of it left", not smith.active and not smith.npcIcon:IsShown())
	C_NamePlate.GetNamePlateForUnit = realGet
	SITREP_DB.npcTitles = nil
	wipe(NP.cache); wipe(NP.tries)
end)()

;(function()
	-- spots on the yard grid (100 yd); those kept on the coarse grid until 4.9.13 move there
	local SP, Q = ns.Spawns, ns.Quests
	local realSize = Q.MapSize
	Q.MapSize = function() return 2000, 1000 end
	check("spots: cells of 100 yd when the map's size is known", SP.CellOf(9700, 0.5, 0.5) == "10:5", SP.CellOf(9700, 0.5, 0.5))
	SITREP_DB.spawnSpots = { [9700] = {
		["m10:10"] = { k = 4, n = 2, t = { 60, 70 }, x = 0.51, y = 0.51, kinds = { [95] = "Defias" }, lo = 14, hi = 14 },
		["10:5"] = { k = 4, n = 1, t = { 80 }, x = 0.53, y = 0.53, kinds = { [96] = "Wolf" }, lo = 12, hi = 13 } } }
	SP.Regrid()
	local cells = SITREP_DB.spawnSpots[9700]
	local c = cells["10:5"]
	check("regrid: the coarse spot joined with the one on the yard grid", cells["m10:10"] == nil and c.k == 8 and c.n == 3 and #c.t == 3
		and c.kinds[95] and c.kinds[96] and c.lo == 12 and c.hi == 14 and math.abs(c.x - 0.52) < 1e-9, c and c.k)
	SITREP_DB.spawnSpots = nil
	Q.MapSize = realSize
end)()

;(function()
	-- drop rates (Drops.lua): kills of each mob while an item objective is open, and the items it gave
	local D, Q = ns.Drops, ns.Quests
	SITREP_DB.drops = nil
	local savedPace = ns.db.pace
	S.mapId, S.mapPos = 1429, { 0.5, 0.5 }
	S.quests = { { id = 501, title = "Rote Kopftücher", level = 15, zone = "Westfall", objectives = { { "Rotes Kopftuch: 0/10", kind = "item" } } },
		{ id = 502, title = "Kobolde", level = 15, zone = "Westfall", objectives = { { "Kobold Vermin slain: 0/8" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	check("drops: the mob's name from the experience message (rested too)", D.KillName("Defias-Schmugglerin stirbt, Ihr bekommt 87 Erfahrung.") == "Defias-Schmugglerin"
		and D.KillName("Wolf stirbt, Ihr bekommt 50 Erfahrung. (+25 Erfahrung Erholt-Bonus)") == "Wolf")
	local function kill(name) W.Fire("CHAT_MSG_COMBAT_XP_GAIN", name .. " stirbt, Ihr bekommt 87 Erfahrung.") end
	local function items(have) S.quests[1].objectives[1][1] = "Rotes Kopftuch: " .. have .. "/10"; W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4) end
	kill("Defias-Schmugglerin"); kill("Defias-Schmugglerin"); kill("Wolf"); kill("Defias-Schmugglerin")
	items(1)
	local e = SITREP_DB.drops and SITREP_DB.drops["501:1"]
	check("drops: kills counted per mob for the open item objective; the item to the kill before it", e and e.mobs["Defias-Schmugglerin"].k == 3
		and e.mobs["Defias-Schmugglerin"].h == 1 and e.mobs.Wolf.k == 1 and e.mobs.Wolf.h == 0, e and e.text)
	check("drops: kill objectives are not item objectives", SITREP_DB.drops["502:1"] == nil)
	local kpi, K, H, from = D.KillsPerItem(501, 1)
	check("drops: 1 item from 3 kills, with the starting guess: 2.0 kills per item; the wolf is no source", math.abs(kpi - 2) < 1e-9 and K == 3 and H == 1
		and #from == 1 and from[1] == "Defias-Schmugglerin", kpi)
	-- the loot window says whose corpse it was: that one gets the item, not the kill before
	S.units.target = { name = "Defias-Schmugglerin", guid = "Creature-0-1-0-1-95-00000000B1", isPlayer = false, hostile = true, dead = true }
	W.Fire("PLAYER_TARGET_CHANGED")
	kill("Defias-Schmugglerin"); kill("Wolf")
	S.loot = { "Creature-0-1-0-1-95-00000000B1" }
	W.Fire("LOOT_OPENED")
	items(2)
	check("drops: the item to the corpse looted (not the wolf killed last)", e.mobs["Defias-Schmugglerin"].h == 2 and e.mobs.Wolf.h == 0, e.mobs.Wolf.h)
	-- the quest's worth uses it: 8 left at 30 s a kill and the kills per item learned
	ns.db.pace = { sec = 30, n = 0 }
	local realText = Q.Text
	Q.Text = function() return nil, nil, 900 end
	local q = Q.List()[1]
	local v = Q.Value(q)
	kpi = D.KillsPerItem(501, 1)
	check("value: the kills per item learned, not the old 1.6", math.abs(v.work - 8 * 30 * kpi) < 1e-6 and math.abs(kpi - 1.6) > 0.05, v.work)
	-- the tracker's tooltip with it: complete (4.9.12 broke off there: only the first of its four values)
	ns.P.quests.value = true
	ns.QuestTracker.Refresh()
	local row
	for _, r in ipairs(ns.QuestTracker.frame.rows) do if r:IsShown() and r.quest and r.quest.id == 501 then row = r end end
	local ok = row and pcall(row._scripts.OnEnter, row)
	local tip = GameTooltip:Text()
	check("tracker tooltip with a drop rate: complete, the rate in it", ok and tip:find("Rotes Kopftuch: about 1 in", 1, true) and tip:find("Click: navigate here", 1, true), tip)
	if row then row._scripts.OnLeave(row) end
	Q.Text = realText
	local n0 = #W.prints
	SlashCmdList.SITREP("drops")
	check("/sitrep drops: per quest item", table.concat(W.prints, "\n", n0 + 1):find("Rotes Kopftuch: about 1 in", 1, true), table.concat(W.prints, "\n", n0 + 1))
	S.quests, S.loot, S.units.target, S.mapId, S.mapPos = nil, nil, nil, nil, nil
	ns.db.pace = savedPace
	SITREP_DB.drops = nil
	W.Fire("PLAYER_TARGET_CHANGED"); W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- the quest on the world map (UI/QuestMap.lua): its mobs' spawn spots, respawn and drop rates
	local QM, Q = ns.QuestMap, ns.Quests
	local realSize = Q.MapSize
	Q.MapSize = function() return 1000, 1000 end
	-- the world map: Blizzard's addon, loaded on demand
	local wm = CreateFrame("Frame")
	wm.ScrollContainer = CreateFrame("Frame", nil, wm)
	local canvas = CreateFrame("Frame", nil, wm.ScrollContainer)
	canvas:SetSize(1000, 700)
	wm.ScrollContainer.Child = canvas
	local mapID, cscale = 1429, 1
	function wm:GetMapID() return mapID end
	function wm:GetCanvas() return canvas end
	function wm:GetCanvasScale() return cscale end
	function wm:OnMapChanged() end
	wm:Hide()
	_G.WorldMapFrame = wm
	W.Fire("ADDON_LOADED", "Blizzard_WorldMap")
	check("quest map: hooked into the world map once it loads", QM.hooked)
	-- what is known: a spot of the quest's mob, one of another mob, its respawn and drop rate
	SITREP_DB.spawnSpots = { [1429] = {
		["550:550"] = { k = 12, n = 3, t = { 50, 60, 70 }, x = 0.55, y = 0.55, kinds = { [95] = "Defias-Schmugglerin" } },
		["100:100"] = { k = 4, n = 3, t = { 30, 30, 30 }, x = 0.10, y = 0.10, kinds = { [6] = "Kobold Vermin" } } } }
	SITREP_DB.spawns = { [95] = { name = "Defias-Schmugglerin", t = { 60 }, n = 1 } }
	SITREP_DB.questMobs = { [601] = { [95] = { n = 1, name = "Defias-Schmugglerin" } } }
	SITREP_DB.drops = { ["601:1"] = { text = "Rotes Kopftuch", mobs = { ["Defias-Schmugglerin"] = { k = 12, h = 5 } } } }
	S.quests = { { id = 601, title = "Rote Kopftücher", level = 15, zone = "Westfall", objectives = { { "Rotes Kopftuch: 3/10", kind = "item" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	Q.Select(601)
	wm:Show(); wm._scripts.OnShow(wm)
	local f = QM.pool[1]
	local pt = f and { f:GetPoint(1) }
	check("quest map: one spot, the quest's mob's (the kobolds' left out)", QM.used == 1 and f:IsShown(), QM.used)
	check("...on the canvas where they die, 100 yd across, gold (they drop its item)", pt and pt[2] == canvas and pt[4] == 550 and math.abs(pt[5] + 385) < 1e-6
		and math.abs(f:GetWidth() - 100) < 1e-6 and f.ring._vc and f.ring._vc[3] < 0.5, pt and (pt[4] .. "," .. pt[5]))
	check("...its respawn time on it", f.text:GetText() == "~1:00", f.text:GetText())
	-- hovering it: more (and the map still gets the clicks)
	check("spot: takes the mouse's moves, not its clicks", f._motion == true and f._clickable == false)
	local restRing, restFill = f.ring._vc[4], f.disc._vc[4]
	f._scripts.OnEnter(f)
	check("hovered: its ring full, its fill stronger, a glow round it", f.ring._vc[4] == 1 and f.disc._vc[4] > restFill * 1.5 and f.glow:IsShown()
		and restRing < 1, f.ring._vc[4])
	local tip = GameTooltip:Text()
	check("spot tooltip: the mob, the objective, the respawn's spread, kills seen, drop rate, kills to go",
		tip:find("Defias-Schmugglerin", 1, true) and tip:find("Objective 1: Rotes Kopftuch: 3/10", 1, true)
		and tip:find("Back after about 1:00 (0:50 to 1:10), 3 respawns measured", 1, true) and tip:find("12 kills seen here", 1, true)
		and tip:find("Drops it about 1 in 2.1 kills (5 from 12)", 1, true) and tip:find("7 to go: about 15 more kills", 1, true), tip)
	f._scripts.OnLeave(f)
	check("...and back as it was", f.ring._vc[4] == restRing and math.abs(f.disc._vc[4] - restFill) < 1e-9 and not f.glow:IsShown())
	-- where its counter went up (a mint ring): over the spawn spots, not under them
	Q.Store()[601] = { title = "Rote Kopftücher", obj = { [1] = { { map = 1429, x = 0.56, y = 0.56 } } } }
	QM.Draw()
	local spotF, placeF
	for j = 1, QM.used do
		local m = QM.pool[j]
		if m.info and m.info.kind == "spot" then spotF = m elseif m.info and m.info.kind == "place" then placeF = m end
	end
	check("the mint ring lies over the spawn spot", spotF and placeF and placeF:GetFrameLevel() > spotF:GetFrameLevel()
		and placeF:GetFrameStrata() == spotF:GetFrameStrata(), placeF and placeF:GetFrameLevel())
	Q.Store()[601] = nil
	QM.Draw()
	local body = QM.legend and QM.legend.body:GetText() or ""
	check("legend: the quest, its mob, how fast it comes back, how many kills an item takes", QM.legend:IsShown() and QM.legend.title:GetText() == "Rote Kopftücher"
		and body:find("Defias-Schmugglerin (back ~1:00)", 1, true) and body:find("1 in 2.", 1, true), body)
	check("legend: what the marks mean (only those shown: here the gold ones)", body:find("where the mobs that drop its items spawn", 1, true)
		and not body:find("where the mobs to kill spawn", 1, true) and body:find("Hover a mark for more", 1, true), body)
	check("chosen in the tracker: the game tracks it too (its map marks it)", W.superTracked == 601, tostring(W.superTracked))
	-- zoomed in: the marks zoom with the map, their text keeps its size
	cscale = 2; wm:OnMapChanged()
	check("zoomed: the label stays one size", math.abs(QM.pool[1].label:GetScale() - 0.5) < 1e-6)
	-- another map open: nothing of it there
	mapID = 1436; wm:OnMapChanged()
	check("another map: no spots, the legend says so", QM.used == 0 and (QM.legend.body:GetText() or ""):find("No spawn spots", 1, true))
	-- no quest chosen: nothing on the map
	mapID = 1429
	Q.Select(nil)
	check("no quest chosen: nothing on the map", QM.used == 0 and not QM.legend:IsShown())
	check("...and the game tracks none", W.superTracked == 0)
	-- switched off
	Q.Select(601)
	ns.P.quests.questMap = false; ns.Changed("quests.questMap")
	check("switched off: nothing on the map", QM.used == 0)
	ns.P.quests.questMap = true; ns.Changed("quests.questMap")
	-- the map closes: its marks go
	wm:Hide(); wm._scripts.OnHide(wm)
	check("map closed: marks gone", not QM.pool[1]:IsShown() and not QM.legend:IsShown())
	Q.Select(nil)
	S.quests = nil
	SITREP_DB.spawnSpots, SITREP_DB.spawns, SITREP_DB.questMobs, SITREP_DB.drops = nil, nil, nil, nil
	Q.MapSize = realSize
	_G.WorldMapFrame = nil
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- ways: noted even when the client keeps your speed secret; counted per session; shared and joined
	local T = ns.Trails
	T.Forget()
	ns.P.quests.trails = true
	S.mapId, S.mapPos = 9400, { 0.30, 0.30 }
	local st0 = { samples = T.stats.samples, unreadable = T.stats.unreadable, cells = T.stats.cells }
	S.secret = S.secret or {}
	S.me.speed = 7
	S.secret.speed = true
	for i = 1, 4 do S.mapPos = { 0.30 + i * 0.01, 0.30 }; W.Update(0.6) end
	S.secret.speed = nil
	check("ways: with the speed kept secret (in combat) still noted", T.Walked(9400, 130, 120) and T.stats.unreadable - st0.unreadable >= 4,
		T.stats.unreadable - st0.unreadable)
	check("ways: this session's new cells counted", T.stats.cells - st0.cells >= 4, T.stats.cells - st0.cells)
	S.me.speed = nil
	-- a door and the inside layer, then share it all
	T.Record(nil)
	T.Record({ map = 9400, x = 0.50, y = 0.50 }, false)
	T.Record({ map = 9400, x = 0.51, y = 0.50 }, true)
	local text = T.Export()
	check("export: one text, empty runs packed", text:sub(1, #T.PREFIX) == T.PREFIX and text:sub(-4) == ":END" and text:find("9400=", 1, true)
		and text:find("9400i=", 1, true) and text:find("D9400=", 1, true) and text:find("!", 1, true) and #text < 600, #text)
	-- someone else's: forget ours, import theirs, then ours again: joined
	T.Forget()
	T.Record(nil)
	T.Record({ map = 9400, x = 0.80, y = 0.80 }, false)
	local added, doors = T.Import(text)
	check("import: their cells and doors joined with ours", added and added >= 6 and doors == 1 and T.Walked(9400, 130, 120) and T.Walked(9400, 320, 320)
		and T.IsDoor(9400, 204, 200), tostring(added))
	local again = T.Import(text)
	check("import twice: nothing new", again == 0, again)
	check("import: a cut-off text is refused", T.Import(text:sub(1, -10)) == nil and select(2, T.Import("hello")):find("not SITREP", 1, true))
	check("imported cells kept (saved with yours)", ns.db.trails[9400] ~= nil)
	-- the windows
	SlashCmdList.SITREP("ways export")
	check("/sitrep ways export: a window with the text to copy", T.win:IsShown() and T.win.box.edit:GetText():sub(1, #T.PREFIX) == T.PREFIX and not T.win.ok:IsShown())
	SlashCmdList.SITREP("ways import")
	T.win.box.edit:SetText(text)
	T.win.ok._scripts.OnClick(T.win.ok)
	check("/sitrep ways import: pasted and joined, the window closes", not T.win:IsShown())
	local n0 = #W.prints
	SlashCmdList.SITREP("ways")
	local rep = table.concat(W.prints, "\n", n0 + 1)
	check("/sitrep ways: samples, why not, cells per map", rep:find("speed kept secret", 1, true) and rep:find("cells in", 1, true), rep)
	T.Forget()
	S.mapId, S.mapPos = nil, nil
end)()

;(function()
	-- water: cells swum go to their own layer; the route weighs swimming across against walking round
	local T, Q = ns.Trails, ns.Quests
	local realSize = Q.MapSize
	Q.MapSize = function() return 1000, 1000 end -- (blocks of 10 yd)
	T.Forget()
	ns.P.quests.trails = true
	-- swimming, sampled
	S.mapId, S.mapPos, S.me.speed, S.swimming = 9500, { 0.70, 0.70 }, 4.7, true
	local sw0 = T.stats.swimming
	for i = 1, 4 do S.mapPos = { 0.70 + i * 0.01, 0.70 }; W.Update(0.6) end
	S.swimming, S.me.speed = nil, nil
	check("water: swum cells in the water layer, not the dry one", T.Walked(T.WaterLayer(9500), 290, 280) and not T.Walked(9500, 290, 280)
		and T.stats.swimming - sw0 >= 4, T.stats.swimming - sw0)
	check("water: Classic's swim speed when the client does not say (about 1.5 times slower)", math.abs(T.SwimFactor() - 7 / 4.72) < 1e-9)
	-- a lake: swum straight across (y 0.50), a dry way round it close by (y 0.45)
	local function walk(x0, y0, x1, y1, swim)
		T.Record(nil)
		local n = math.floor(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) * 200)
		for i = 0, n do T.Record({ map = 9500, x = x0 + (x1 - x0) * i / n, y = y0 + (y1 - y0) * i / n }, false, swim) end
	end
	walk(0.12, 0.50, 0.48, 0.50, true)
	walk(0.10, 0.50, 0.10, 0.45); walk(0.10, 0.45, 0.50, 0.45); walk(0.50, 0.45, 0.50, 0.50)
	walk(0.10, 0.50, 0.12, 0.50); walk(0.48, 0.50, 0.50, 0.50)
	check("water: the lake's middle is water to swim, the shore is not", T.Wet(9500, 30, 50) and not T.Wet(9500, 10, 50))
	local wp = T.Waypoint({ map = 9500, x = 0.105, y = 0.505 }, { map = 9500, x = 0.505, y = 0.505 })
	check("water: walking round (500 yd) beats swimming across (400 yd, about 590 on foot): the arrow leads round",
		wp and wp.kind == "path" and wp.y < 0.49, wp and (wp.x .. "," .. wp.y))
	-- the way round far away (y 0.30: 800 yd): swim
	T.Forget()
	walk(0.12, 0.50, 0.48, 0.50, true)
	walk(0.10, 0.50, 0.10, 0.30); walk(0.10, 0.30, 0.50, 0.30); walk(0.50, 0.30, 0.50, 0.50)
	walk(0.10, 0.50, 0.12, 0.50); walk(0.48, 0.50, 0.50, 0.50)
	wp = T.Waypoint({ map = 9500, x = 0.105, y = 0.505 }, { map = 9500, x = 0.505, y = 0.505 }, false)
	check("water: the way round much longer: straight across (swim)", wp == nil or wp.y > 0.49, wp and (wp.x .. "," .. wp.y))
	-- walking on water (Water Walking): neither ground nor water: not noted
	T.Forget()
	S.auras = S.auras or {}
	S.auras.player = { { id = 4601, spellId = 546, name = "Wasserwandeln" } }
	S.mapId, S.mapPos, S.me.speed = 9500, { 0.20, 0.80 }, 7
	local ow0 = T.stats.onWater
	for i = 1, 3 do S.mapPos = { 0.20 + i * 0.01, 0.80 }; W.Update(0.6) end
	check("water walking: nothing noted (it is not ground)", not T.Walked(9500, 88, 320) and not T.Walked(T.WaterLayer(9500), 88, 320)
		and T.stats.onWater - ow0 >= 3, T.stats.onWater - ow0)
	-- in combat the auras are hidden (Forever: every lookup nil): the state from before holds
	S.secret = S.secret or {}
	S.secret.auras, S.secret.lookupsNil, S.me.combat = true, true, true
	check("water walking in combat (lookups answer nil): still known", T.OnWater() == true)
	S.secret.auras, S.secret.lookupsNil, S.me.combat = nil, nil, false
	S.auras.player = nil
	check("...and gone when the buff is", T.OnWater() == false)
	S.me.speed = nil
	walk(0.12, 0.50, 0.48, 0.50, true)
	-- shared too
	check("water: exported with the rest", T.Export():find("9500w=", 1, true))
	T.Forget()
	Q.MapSize = realSize
	S.mapId, S.mapPos = nil, nil
end)()

;(function()
	-- drawn by hand: ground, water, terrain to avoid (whole route blocks); the route goes round terrain
	local T, Q = ns.Trails, ns.Quests
	local realSize = Q.MapSize
	Q.MapSize = function() return 1000, 1000 end
	T.Forget()
	local ch = T.EditBlock(9600, 70, 70, "walk")
	check("walk: the whole block walked (16 cells)", #ch == 16 and T.Walked(9600, 280, 280) and T.Walked(9600, 283, 283))
	ch = T.EditBlock(9600, 70, 70, "water")
	check("water over it: water, no longer dry", T.Walked(T.WaterLayer(9600), 281, 282) and not T.Walked(9600, 281, 282))
	T.Undo(ch)
	check("undone: dry again", T.Walked(9600, 281, 282) and not T.Walked(T.WaterLayer(9600), 281, 282))
	T.EditBlock(9600, 70, 70, "terrain")
	check("terrain: rough, alone in its block (the ground there goes)", T.Rough(9600, 70, 70) and not T.Blocked(9600, 70, 70) and not T.Walked(9600, 281, 282))
	T.EditBlock(9600, 70, 70, "blocked")
	check("blocked over it: no way through (no longer rough)", T.Blocked(9600, 70, 70) and not T.Rough(9600, 70, 70))
	T.EditBlock(9600, 70, 70, "water")
	T.EditBlock(9600, 70, 70, "walk")
	check("walk over water: both (a bridge), the one pair that may share a block", T.Walked(9600, 281, 282) and T.Walked(T.WaterLayer(9600), 281, 282)
		and not T.Blocked(9600, 70, 70))
	T.EditBlock(9600, 70, 70, "erase")
	check("erase: all of it gone", not T.Blocked(9600, 70, 70) and not T.Walked(9600, 281, 282))
	-- a straight known way, a way round close by, terrain drawn across the straight one
	local function walk(x0, y0, x1, y1)
		T.Record(nil)
		local n = math.floor(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) * 200)
		for i = 0, n do T.Record({ map = 9600, x = x0 + (x1 - x0) * i / n, y = y0 + (y1 - y0) * i / n }) end
	end
	walk(0.10, 0.50, 0.50, 0.50)
	walk(0.10, 0.50, 0.10, 0.44); walk(0.10, 0.44, 0.50, 0.44); walk(0.50, 0.44, 0.50, 0.50)
	local here, goal = { map = 9600, x = 0.105, y = 0.505 }, { map = 9600, x = 0.505, y = 0.505 }
	check("no terrain: the straight known way, straight on", T.Waypoint(here, goal) == nil)
	T.ForgetRoute()
	-- a thin strip of rough terrain: crossing it (20 yd at 3 times) is quicker than going round
	for by = 48, 52 do T.EditBlock(9600, 30, by, "terrain") end
	check("a thin rough strip: straight on through it", T.Waypoint(here, goal) == nil)
	-- a wide rough area (210 yd at 3 times: 820 against about 500 round): round
	T.ForgetRoute()
	for bx = 20, 40 do for by = 48, 52 do T.EditBlock(9600, bx, by, "terrain") end end
	local wp = T.Waypoint(here, goal)
	check("a wide rough area: the arrow leads round", wp and wp.kind == "path" and wp.y < 0.49, wp and (wp.x .. "," .. wp.y))
	-- no way through, even a thin strip: round
	for bx = 20, 40 do for by = 48, 52 do T.EditBlock(9600, bx, by, "erase") end end
	walk(0.10, 0.50, 0.50, 0.50)
	T.ForgetRoute()
	for by = 48, 52 do T.EditBlock(9600, 30, by, "blocked") end
	wp = T.Waypoint(here, goal)
	check("blocked across it (a thin strip): the arrow leads round", wp and wp.kind == "path" and wp.y < 0.49, wp and (wp.x .. "," .. wp.y))
	check("terrain and blocked: exported with the rest", T.Export():find("9600b=", 1, true))
	T.Forget()
	Q.MapSize = realSize
end)()

;(function()
	-- the world map's other layers: the ways walked (a debug view, with its button) and the flight points
	local QM, T, TR = ns.QuestMap, ns.Trails, ns.Travel
	local wm = CreateFrame("Frame")
	wm.ScrollContainer = CreateFrame("Frame", nil, wm)
	local canvas = CreateFrame("Frame", nil, wm.ScrollContainer)
	canvas:SetSize(1000, 700)
	wm.ScrollContainer.Child = canvas
	local mapID = 9300
	function wm:GetMapID() return mapID end
	function wm:GetCanvas() return canvas end
	function wm:GetCanvasScale() return 2 end
	function wm:OnMapChanged() end
	wm:Hide()
	_G.WorldMapFrame = wm
	QM.hooked = false
	W.Fire("ADDON_LOADED", "Blizzard_WorldMap")
	-- a way walked straight east on map 9300 (cells 40..160 of row 80: route blocks 10..40 of row 20)
	T.Forget()
	T.Record(nil)
	for x = 10, 40, 2 do T.Record({ map = 9300, x = x / 100, y = 0.20 }) end
	ns.P.quests.mapTrails = false
	wm:Show(); wm._scripts.OnShow(wm)
	check("ways: off by default (a debug view), its button on the map", (QM.trailUsed or 0) == 0 and QM.button and QM.button:IsShown())
	QM.button._scripts.OnClick(QM.button)
	check("the button turns it on", ns.P.quests.mapTrails == true)
	local t = QM.trailTex[1]
	local pt = t and { t:GetPoint(1) }
	check("ways: one strata above the map's (its explored areas lay over them)", QM.trailHolder:GetFrameStrata() == "HIGH")
	local n0p = #W.prints
	SlashCmdList.SITREP("mapprobe")
	check("/sitrep mapprobe: the map and what lies on its canvas", table.concat(W.prints, "\n", n0p + 1):find("(SITREP ways)", 1, true), table.concat(W.prints, "\n", n0p + 1))
	check("ways: the walked line as one run of blocks, where and as wide as walked", QM.trailUsed == 1 and pt[2] == canvas
		and math.abs(pt[4] - 100) < 1e-6 and math.abs(pt[5] + 140) < 1e-6 and math.abs(t:GetWidth() - 310) < 1e-6, QM.trailUsed)
	-- inside (a cave) in blue, a door in yellow
	T.Record(nil)
	T.Record({ map = 9300, x = 0.60, y = 0.60 }, false)
	T.Record({ map = 9300, x = 0.61, y = 0.60 }, true)
	QM.trailKey = nil; QM.Draw()
	local blue, yellow = false, false
	for j = 1, QM.trailUsed do
		local c = QM.trailTex[j]._color or {}
		if c[3] == 1 and c[1] > 0.6 and c[2] < 0.7 then blue = true end -- (lavender)
		if c[1] == 1 and c[3] < 0.5 then yellow = true end
	end
	check("ways: inside lavender, the door yellow", blue and yellow, QM.trailUsed)
	-- blocked drawn, then walked through anyway: the map shows it blocked alone
	T.EditBlock(9300, 25, 20, "blocked")
	T.Record(nil)
	for x = 250, 262, 2 do T.Record({ map = 9300, x = x / 1000, y = 0.205 }) end
	QM.trailKey = nil; QM.Draw()
	local overlap = false
	for j = 1, QM.trailUsed do
		local t = QM.trailTex[j]
		local c, p = t._color or {}, { t:GetPoint(1) }
		if c[1] and c[1] < 0.5 and c[2] > 0.9 and p[4] <= 250 and p[4] + t:GetWidth() >= 260 then overlap = true end
	end
	check("blocked and ground in one block: the map shows it blocked alone", not overlap and T.Walked(9300, 101, 82))
	T.EditBlock(9300, 25, 20, "erase")
	-- the brush: old ways that are water, painted over
	check("ways on: the brush buttons show (walk, water, terrain, erase, undo)", QM.tools.walk:IsShown() and QM.tools.terrain:IsShown()
		and QM.toWater:IsShown() and QM.erase:IsShown() and QM.undoB:IsShown())
	local mx, my = 0.15, 0.205
	function wm:GetNormalizedCursorPosition() return mx, my end
	QM.toWater._scripts.OnClick(QM.toWater)
	check("-> Water chosen: the brush takes the mouse", QM.tool == "water" and QM.brush:IsShown() and QM.brush:IsMouseEnabled())
	QM.brush._scripts.OnMouseDown(QM.brush, "LeftButton")
	mx = 0.16
	QM.brush._scripts.OnUpdate(QM.brush, 0.1)
	QM.brush._scripts.OnMouseUp(QM.brush, "LeftButton")
	check("painted to water: dry cells moved to the water layer", T.Walked(T.WaterLayer(9300), 60, 80) and not T.Walked(9300, 60, 80)
		and T.Walked(T.WaterLayer(9300), 64, 80) and T.Walked(9300, 70, 80) and #QM.undo == 1, #QM.undo)
	QM.undoB._scripts.OnClick(QM.undoB)
	check("Undo: dry again", T.Walked(9300, 60, 80) and not T.Walked(T.WaterLayer(9300), 60, 80) and #QM.undo == 0)
	QM.erase._scripts.OnClick(QM.erase)
	check("Erase chosen (the other put down)", QM.tool == "erase")
	mx = 0.25
	QM.brush._scripts.OnMouseDown(QM.brush, "LeftButton")
	QM.brush._scripts.OnMouseUp(QM.brush, "LeftButton")
	check("erased: the block's cells gone", not T.Walked(9300, 100, 80) and not T.Walked(9300, 103, 80) and T.Walked(9300, 104, 80))
	T.Save()
	check("an erased row empties nothing else; saved", ns.db.trails[9300][80] ~= nil)
	-- brush sizes: click larger, right-click smaller; the preview frame under the mouse
	check("brush size: 1x1 at first", QM.sizeB:IsShown() and QM.sizeB.text:GetText() == "1x1")
	QM.sizeB._scripts.OnClick(QM.sizeB, "LeftButton")
	check("click: 3x3", ns.P.quests.mapBrush == 3 and QM.sizeB.text:GetText() == "3x3")
	mx, my = 0.355, 0.205
	QM.brush._scripts.OnUpdate(QM.brush, 0.1)
	check("preview: a frame in the tool's colour, 3 blocks wide, round the mouse's block", QM.preview:IsShown() and math.abs(QM.preview:GetWidth() - 30) < 1e-6
		and QM.preview.edges[1]._color[1] > 0.9 and QM.preview.edges[1]._color[2] < 0.5, QM.preview:GetWidth())
	QM.brush._scripts.OnMouseDown(QM.brush, "LeftButton")
	QM.brush._scripts.OnMouseUp(QM.brush, "LeftButton")
	check("a 3x3 dab: the blocks either side erased too", not T.Walked(9300, 136, 80) and not T.Walked(9300, 147, 80) and T.Walked(9300, 148, 80))
	QM.sizeB._scripts.OnClick(QM.sizeB, "LeftButton"); QM.sizeB._scripts.OnClick(QM.sizeB, "LeftButton"); QM.sizeB._scripts.OnClick(QM.sizeB, "LeftButton")
	check("at most 9x9", ns.P.quests.mapBrush == 9)
	QM.sizeB._scripts.OnClick(QM.sizeB, "RightButton")
	check("right-click: smaller (5x5)", ns.P.quests.mapBrush == 5)
	ns.P.quests.mapBrush = 1
	QM.erase._scripts.OnClick(QM.erase)
	check("chosen again: put down, the map pans again", QM.tool == nil and not QM.brush:IsShown())
	check("...and the preview goes at once", not QM.preview:IsShown())
	QM.button._scripts.OnClick(QM.button)
	check("...and off again: gone", ns.P.quests.mapTrails == false and QM.trailUsed == 0 and not QM.toWater:IsShown())
	T.Forget()
	-- flight points: this character's, one it has not been to, one off this map
	ns.db.flight = nil
	S.taxiNodes = { [9300] = { { "Stormwind, Elwynn", 0.30, 0.20 }, { "Späherkuppe, Westfall", 0.50, 0.60 }, { "Far Away, Elsewhere", 1.40, 0.50 } } }
	TR.Known()["Stormwind, Elwynn"] = true
	QM.Draw()
	local mine, new
	for j = 1, QM.flightUsed do
		local f = QM.flightPool[j]
		if f.node == "Stormwind, Elwynn" then mine = f elseif f.node == "Späherkuppe, Westfall" then new = f end
	end
	check("flights: the points on this map (not the far one)", QM.flightUsed == 2, QM.flightUsed)
	check("...the one you know: bright, its name", mine and mine.mine and mine.text:GetText() == "Stormwind" and not mine.icon._desat)
	check("...the one you have not been to: dim, \"new\"", new and not new.mine and new.icon._desat and new.text:GetText():find("Späherkuppe", 1, true)
		and new.text:GetText():find("new", 1, true), new and new.text:GetText())
	check("...the icons keep one size when zoomed", math.abs(mine.inner:GetScale() - 0.5) < 1e-6)
	new.inner._scripts.OnEnter(new.inner)
	check("a hovered flight point grows, the others step back", math.abs(new.inner:GetScale() - 0.5 * 1.3) < 1e-9 and mine:GetAlpha() == 0.5
		and new:GetAlpha() == 1)
	check("flight point tooltip: not unlocked yet", GameTooltip:Text():find("Späherkuppe, Westfall", 1, true) and GameTooltip:Text():find("Not unlocked yet", 1, true), GameTooltip:Text())
	mine.inner._scripts.OnEnter(mine.inner)
	check("...and a known one: you can fly there", GameTooltip:Text():find("Known: you can fly here", 1, true))
	mine.inner._scripts.OnLeave(mine.inner)
	check("...all back as they were", math.abs(new.inner:GetScale() - 0.5) < 1e-9 and mine:GetAlpha() == 1)
	-- a character never seen at a flight master: not "new" everywhere, but "?" and how to fix it
	ns.db.flight = nil
	QM.Draw()
	local any = QM.flightPool[1]
	check("flights unknown for this character: '?', not 'new'", any.text:GetText():find("?", 1, true) and not any.text:GetText():find("new", 1, true), any.text:GetText())
	any.inner._scripts.OnEnter(any.inner)
	check("...its tooltip says to talk to a flight master once", GameTooltip:Text():find("talk to any flight master once", 1, true), GameTooltip:Text())
	any.inner._scripts.OnLeave(any.inner)
	-- flight points kept under the first name (before 4.9.17): moved to the character's GUID
	local oldKey = tostring(UnitName("player")) .. "-" .. tostring(GetRealmName())
	ns.db.flight = { known = { [oldKey] = { ["Stormwind, Elwynn"] = true } }, times = {} }
	check("flight points under the old name: moved to the GUID", TR.Known()["Stormwind, Elwynn"] and ns.db.flight.known[oldKey] == nil
		and ns.db.flight.known[UnitGUID("player")] ~= nil and TR.Checked())
	ns.P.quests.mapFlights = false; ns.Changed("quests.mapFlights")
	check("flights off: none", QM.flightUsed == 0)
	ns.P.quests.mapFlights = true; ns.Changed("quests.mapFlights")
	wm:Hide(); wm._scripts.OnHide(wm)
	check("map closed: the button and the points go", not QM.button:IsShown() and not QM.flightPool[1]:IsShown())
	S.taxiNodes, ns.db.flight = nil, nil
	_G.WorldMapFrame = nil
end)()

;(function()
	-- a mob's tooltip names the objective it is for: kept for the account (the quest map finds its spots by it)
	local Q = ns.Quests
	SITREP_DB.questMobs = nil
	S.quests = { { id = 602, title = "Kobolde", level = 5, zone = "Elwynn Forest", objectives = { { "Kobold Vermin slain: 0/8" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	Q.ForgetMobs()
	S.units.nameplate94 = { name = "Kobold Vermin", guid = "Creature-0-1-0-1-6-0000000C01", isPlayer = false, hostile = true }
	Q.MobOf("nameplate94", S.units.nameplate94.guid)
	local m = SITREP_DB.questMobs and SITREP_DB.questMobs[602] and SITREP_DB.questMobs[602][6]
	check("quest mobs: learned from its tooltip (objective 1, by NPC)", m and m.n == 1 and m.name == "Kobold Vermin", m and m.name)
	S.units.nameplate94, S.quests, SITREP_DB.questMobs = nil, nil, nil
	Q.ForgetMobs()
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- a quest with several places: the one you get to quickest (on foot or by air), not the game's one point
	local Q, TR = ns.Quests, ns.Travel
	local realSize = Q.MapSize
	Q.MapSize = function() return 3000, 2000 end
	Q.ForgetPins()
	S.mapId, S.mapPos = 9800, { 0.11, 0.10 }
	-- the game's point: the far farm area; learned: one near you, one far (two groups, not their middle)
	S.questPins = { [9800] = { { questID = 801, x = 0.85, y = 0.85 } } }
	S.quests = { { id = 801, title = "Farmen", level = 15, zone = "Westfall", objectives = { { "Kopftuch: 1/10", kind = "item" } } } }
	Q.Store()[801] = { title = "Farmen", obj = { [1] = { { map = 9800, x = 0.15, y = 0.12 }, { map = 9800, x = 0.155, y = 0.125 },
		{ map = 9800, x = 0.85, y = 0.86 } } } }
	local q = Q.List()[1]
	local cands = Q.Candidates(q, Q.Here(), { map = 9800, x = 0.85, y = 0.85, kind = "exact" })
	check("places: the game's point and two learned groups (not their middle)", #cands == 3, #cands)
	local t = Q.Target(q, Q.Here())
	check("on foot: the near farm area, not the game's far point", t and t.kind == "learned" and t.x < 0.2 and t.choice and t.choice.of == 3
		and not t.choice.byAir, t and (t.kind .. " " .. t.x))
	-- by air: a spawn spot beside a flight point you know beats an area halfway on foot
	Q.ForgetPins()
	S.questPins = nil
	S.taxiNodes = { [9800] = { { "Ost", 0.10, 0.10 }, { "West", 0.90, 0.90 } } }
	ns.db.flight = { known = { [UnitGUID("player")] = { Ost = true, West = true } }, times = {} }
	S.quests = { { id = 802, title = "Weit", level = 15, zone = "Westfall", objectives = { { "Zahn: 0/5", kind = "item" } } } }
	Q.Store()[802] = { title = "Weit", obj = { [1] = { { map = 9800, x = 0.50, y = 0.50 } } } }
	SITREP_DB.questMobs = { [802] = { [95] = { n = 1, name = "Geiferzahn" } } }
	SITREP_DB.spawnSpots = { [9800] = { a = { k = 5, n = 0, t = {}, x = 0.88, y = 0.88, kinds = { [95] = "Geiferzahn" } } } }
	Q.ForgetSpotIndex() -- (in the game: within half a minute)
	q = Q.List()[1]
	t = Q.Target(q, Q.Here())
	check("by air: the spawn spot by the far flight point (about 2:40 against 4:15 on foot)", t and t.kind == "spot" and t.x > 0.85 and t.choice.byAir
		and t.choice.next and t.choice.time < t.choice.next, t and (t.kind .. " " .. t.x .. " " .. tostring(t.choice and t.choice.time)))
	-- the tracker's tooltip says so
	ns.QuestTracker.Refresh()
	local row
	for _, r in ipairs(ns.QuestTracker.frame.rows) do if r:IsShown() and r.quest and r.quest.id == 802 then row = r end end
	if row then row._scripts.OnEnter(row) end
	check("tracker tooltip: the quickest of the places known, by air, the next", row and GameTooltip:Text():find("The quickest of 2 places known for it", 1, true)
		and GameTooltip:Text():find("by air", 1, true) and GameTooltip:Text():find("A spawn spot of its mobs", 1, true), row and GameTooltip:Text())
	if row then row._scripts.OnLeave(row) end
	-- the arrow follows you: run to the other area and it points there (asked again every second)
	local QA = ns.QuestArrow
	if QA and QA.frame then
		S.quests = { { id = 803, title = "Zwei Flächen", level = 15, zone = "Westfall", objectives = { { "Fell: 0/6", kind = "item" } } } }
		Q.Store()[803] = { title = "Zwei Flächen", obj = { [1] = { { map = 9800, x = 0.15, y = 0.12 }, { map = 9800, x = 0.85, y = 0.86 } } } }
		ns.db.flight = nil
		S.mapPos = { 0.11, 0.10 }
		W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
		Q.Select(803)
		W.Update(1.2)
		check("arrow: the area near you", QA.quest and QA.quest.target and QA.quest.target.x < 0.2, QA.quest and QA.quest.target and QA.quest.target.x)
		S.mapPos = { 0.80, 0.82 }
		W.Update(1.2)
		check("...run to the other one: it points there", QA.quest.target.x > 0.8, QA.quest.target.x)
		-- halfway back, both about as far: it stays (no swinging between them)
		S.mapPos = { 0.49, 0.48 }
		W.Update(6)
		check("...halfway, both about as near: it stays with the last one", QA.quest.target.x > 0.8, QA.quest.target.x)
		Q.Select(nil)
		Q.Store()[803] = nil
	end
	-- what it costs: 3000 spawn spots, 20 quests, the tracker's look every two seconds
	local cells = {}
	for i = 1, 3000 do cells["c" .. i] = { k = 3, n = 1, t = { 60 }, x = (i % 97) / 97, y = (i % 89) / 89, kinds = { [1000 + i % 50] = "Mob" .. (i % 50) } } end
	SITREP_DB.spawnSpots = { [9800] = cells }
	SITREP_DB.questMobs = {}
	S.quests = {}
	for i = 1, 20 do
		S.quests[i] = { id = 900 + i, title = "Q" .. i, level = 15, zone = "Westfall", objectives = { { "Ding: 0/8", kind = "item" } } }
		SITREP_DB.questMobs[900 + i] = { [1000 + i] = { n = 1, name = "Mob" .. i } }
		Q.Store()[900 + i] = { obj = { [1] = { { map = 9800, x = 0.2, y = 0.2 }, { map = 9800, x = 0.7, y = 0.7 } } } }
	end
	Q.ForgetSpotIndex(); Q.ForgetChoices()
	local t0 = os.clock()
	Q.Sorted("distance")
	local first = (os.clock() - t0) * 1000
	t0 = os.clock()
	for _ = 1, 10 do Q.Sorted("distance") end
	local again = (os.clock() - t0) * 100
	Q.ForgetChoices() -- (the choices worked out again, the spots' index kept: every few seconds)
	t0 = os.clock()
	Q.Sorted("distance")
	local rechoose = (os.clock() - t0) * 1000
	check(string.format("places: 20 quests and 3000 spots cost little (first look %.1f ms, choosing again %.1f ms, then %.2f ms each)", first, rechoose, again),
		first < 60 and rechoose < 15 and again < 10, first)
	for i = 1, 20 do Q.Store()[900 + i] = nil end
	Q.ForgetSpotIndex()
	Q.Store()[801], Q.Store()[802] = nil, nil
	S.quests, S.taxiNodes, S.mapId, S.mapPos = nil, nil, nil, nil
	ns.db.flight, SITREP_DB.questMobs, SITREP_DB.spawnSpots = nil, nil, nil
	Q.MapSize = realSize
	Q.ForgetPins()
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- the bestiary (Bestiary.lua): every mob seen, where, and which quests want it
	local B, Q, SP = ns.Bestiary, ns.Quests, ns.Spawns
	local realSize = Q.MapSize
	Q.MapSize = function() return 2000, 2000 end -- (cells of 100 yd: 20 a side)
	SITREP_DB.bestiary = nil
	S.mapId, S.mapPos = 9900, { 0.52, 0.52 }
	W.Update(1.1) -- (where you stand: once a second)
	local function plate(unit, u) S.units[unit] = u; W.Fire("NAME_PLATE_UNIT_ADDED", unit); W.Fire("NAME_PLATE_UNIT_REMOVED", unit); S.units[unit] = nil end
	plate("nameplate80", { name = "Koboldläufer", guid = "Creature-0-1-0-1-777-00000000E1", level = 7, isPlayer = false, hostile = true, reaction = 2 })
	plate("nameplate80", { name = "Koboldläufer", guid = "Creature-0-1-0-1-777-00000000E1", level = 7, isPlayer = false, hostile = true, reaction = 2 })
	plate("nameplate81", { name = "Koboldläufer", guid = "Creature-0-1-0-1-777-00000000E2", level = 8, isPlayer = false, hostile = true, reaction = 2 })
	plate("nameplate82", { name = "Stadtwache", guid = "Creature-0-1-0-1-778-00000000E3", level = 30, isPlayer = false, hostile = false, reaction = 5 })
	plate("nameplate83", { name = "Ratte", guid = "Creature-0-1-0-1-779-00000000E4", level = 1, isPlayer = false, hostile = false, reaction = 4, classification = "minus" })
	local e = SITREP_DB.bestiary and SITREP_DB.bestiary[777]
	check("bestiary: a mob seen, each one once (2 kobolds), its levels, where", e and e.n == "Koboldläufer" and e.s == 2 and e.lo == 7 and e.hi == 8
		and e.m[9900] and e.m[9900]["10:10"] == 2, e and e.s)
	check("bestiary: friendly NPCs and critters not kept", SITREP_DB.bestiary[778] == nil and SITREP_DB.bestiary[779] == nil)
	check("bestiary: by name", B.ByName("koboldläufer") == 777)
	-- at most MAX_CELLS cells a map: the rarest go
	for i = 1, B.MAX_CELLS + 2 do
		B.SetWhere(9900, i .. ":1")
		plate("nameplate84", { name = "Koboldläufer", guid = "Creature-0-1-0-1-777-0000001" .. i, level = 7, isPlayer = false, hostile = true, reaction = 2 })
	end
	local n = 0
	for _ in pairs(e.m[9900]) do n = n + 1 end
	check("bestiary: at most 30 cells a map, the most seen kept", n == B.MAX_CELLS and e.m[9900]["10:10"] == 2, n)
	-- a kill objective's mob from its words
	check("objective's mob: German and English", B.ObjectiveMob("Koboldläufer getötet: 0/8") == "Koboldläufer" and B.ObjectiveMob("Kobold Vermin slain: 3/8") == "Kobold Vermin")
	-- a quest accepted that wants it: told where it was seen; its places include them
	for k in pairs(e.m[9900]) do if k ~= "10:10" then e.m[9900][k] = nil end end
	e.m[9900]["2:2"] = 1
	S.mapPos = { 0.12, 0.12 }
	W.Update(1.1)
	S.quests = { { id = 990, title = "Koboldplage", level = 8, zone = "Elwynn", objectives = { { "Koboldläufer getötet: 0/8" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	local n0 = #W.prints
	W.Fire("QUEST_ACCEPTED", 1, 990)
	local said = table.concat(W.prints, "\n", n0 + 1)
	check("quest accepted: told its mob was seen before, where", said:find("For \"Koboldplage\": Koboldläufer seen before", 1, true) and said:find("2 places", 1, true), said)
	Q.ForgetChoices()
	local q = Q.List()[1]
	local t = Q.Target(q, Q.Here())
	check("its place: where its mob was seen (the nearest), before ever fighting it", t and t.kind == "seen" and t.x < 0.2, t and (t.kind .. " " .. t.x))
	check("the mob knows its quest", B.QuestsOf(777)[1] and B.QuestsOf(777)[1].title == "Koboldplage")
	-- the hover window says it
	S.units.mouseover = { name = "Koboldläufer", guid = "Creature-0-1-0-1-777-00000000E9", level = 7, isPlayer = false, hostile = true, reaction = 2 }
	ns.PlateHover.Fill("mouseover")
	local line = ns.PlateHover.frame.seen:GetText() or ""
	check("hover: how often and where seen, and for which quest", line:find("seen ", 1, true) and line:find("2 places", 1, true) and line:find("for: Koboldplage", 1, true), line)
	ns.PlateHover.Fill(nil)
	S.units.mouseover = nil
	n0 = #W.prints
	SlashCmdList.SITREP("mobs kobold")
	local rep = table.concat(W.prints, "\n", n0 + 1)
	check("/sitrep mobs: by name, its levels, where", rep:find("Koboldläufer (level 7-8)", 1, true) and rep:find("(2x)", 1, true), rep)
	S.quests, S.mapId, S.mapPos = nil, nil, nil
	SITREP_DB.bestiary = nil
	Q.MapSize = realSize
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	W.Update(3.5) -- (a quest just accepted: the next ones in the log would count as accepted too)
end)()

;(function()
	-- quest items marked in the loot window (Drops: LootMark)
	local D = ns.Drops
	S.quests = { { id = 701, title = "Kopftücher", level = 15, zone = "Westfall", objectives = { { "Rotes Kopftuch: 4/10", kind = "item" } } },
		{ id = 702, title = "Federn", level = 15, zone = "Westfall", objectives = { { "Feder: 5/5", true, kind = "item" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	-- the classic window: four buttons, each with the slot it shows
	local buttons = {}
	for i = 1, 4 do
		local b = CreateFrame("Button", "LootButton" .. i, UIParent)
		b:SetSize(37, 37)
		local t = b:CreateFontString("LootButton" .. i .. "Text")
		_G["LootButton" .. i .. "Text"] = t
		b.slot = i
		buttons[i] = b
	end
	buttons[4]:Hide()
	S.lootSlots = { { "Rotes Kopftuch", quest = nil, active = nil }, { "Leinenstoff" }, { "Ein alter Brief", quest = 750, active = false }, { "Feder" } }
	for i, l in ipairs(S.lootSlots) do if l[1] == "Rotes Kopftuch" or l[1] == "Feder" then l.questItem = true end end
	-- (the mock's slot info: a quest's item has a quest flag)
	local realInfo = GetLootSlotInfo
	GetLootSlotInfo = function(slot)
		local l = S.lootSlots[slot]
		if not l then return nil end
		return "icon.blp", l[1], 1, nil, 1, false, (l.questItem or l.quest ~= nil), l.quest, l.active
	end
	buttons[4]:Show()
	W.Fire("LOOT_OPENED")
	local m1, m2, m3, m4 = buttons[1].srQuest, buttons[2].srQuest, buttons[3].srQuest, buttons[4].srQuest
	check("loot: a quest's item marked, what you have of it beside its name", m1 and m1:IsShown() and m1.text:GetText() == "4/10"
		and m1.bang._tex:find("glyph_bang", 1, true), m1 and m1.text:GetText())
	check("loot: an ordinary item not marked", m2 == nil or not m2:IsShown())
	check("loot: an item that starts a quest: a star, says so", m3 and m3:IsShown() and m3.text:GetText() == "starts a quest" and m3.bang._tex:find("glyph_star", 1, true))
	check("loot: an objective already full: done, grey", m4 and m4.text:GetText() == "done" and m4.text._tc and m4.text._tc[1] < 0.6, m4 and m4.text:GetText())
	-- the game does not flag it (Forever, reported): an objective naming it is enough
	S.lootSlots[1].questItem = nil
	W.Fire("LOOT_OPENED")
	check("loot: not flagged by the game, but an objective names it: marked", buttons[1].srQuest:IsShown() and buttons[1].srQuest.text:GetText() == "4/10")
	-- the slot taken, the button shows another item: its mark follows
	S.lootSlots[1] = { "Leinenstoff" }
	W.Fire("LOOT_SLOT_CLEARED", 1)
	check("loot: the button now shows an ordinary item: its mark gone", not buttons[1].srQuest:IsShown())
	local n0 = #W.prints
	SlashCmdList.SITREP("lootprobe")
	local rep = table.concat(W.prints, "\n", n0 + 1)
	check("/sitrep lootprobe: the slots and which are quest items", rep:find("4 slots", 1, true) and rep:find("Ein alter Brief, quest item (the game) true, quest 750, active false", 1, true)
		and rep:find("buttons found: 4", 1, true), rep)
	GetLootSlotInfo = realInfo
	for i = 1, 4 do buttons[i]:Hide(); _G["LootButton" .. i] = nil; _G["LootButton" .. i .. "Text"] = nil end
	-- the same in the bags (the combined backpack): a gold frame and "!" inside the icon
	local bagFrame = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
	_G.ContainerFrameCombinedBags = bagFrame
	local items = {}
	for i = 1, 4 do
		local b = CreateFrame("Button", nil, bagFrame)
		b:SetSize(37, 37)
		b:SetID(i)
		function b:GetBagID() return 0 end
		items[i] = b
	end
	function bagFrame:EnumerateValidItems() return ipairs(items) end
	S.bagItems = { [0] = { { "Rotes Kopftuch" }, { "Leinenstoff" }, { "Ein alter Brief", quest = 750, active = false }, { "Feder" } } }
	W.Fire("BAG_UPDATE_DELAYED")
	local b1, b2, b3, b4 = items[1].srBagQuest, items[2].srBagQuest, items[3].srBagQuest, items[4].srBagQuest
	check("bags: a quest's item (named by an objective) marked: gold, '!' inside the icon", b1 and b1:IsShown() and b1.bang._tex:find("glyph_bang", 1, true)
		and ({ b1.bang:GetPoint(1) })[4] < 0 and not b1.full)
	check("bags: an ordinary item not marked", b2 == nil or not b2:IsShown())
	check("bags: an item that starts a quest: a star", b3 and b3:IsShown() and b3.starts and b3.bang._tex:find("glyph_star", 1, true))
	check("bags: an objective already full: still gold (grey hid among the slots)", b4 and b4:IsShown() and b4.full and b4.bang._vc[1] > 0.9)
	-- in combat no frame is made (Blizzard's bags taint easily): later
	local fresh = CreateFrame("Button", nil, bagFrame)
	fresh:SetID(5); function fresh:GetBagID() return 0 end
	items[5] = fresh
	S.bagItems[0][5] = { "Rotes Kopftuch" }
	S.me.combat = true
	W.Fire("BAG_UPDATE_DELAYED")
	check("bags: in combat no new mark made", fresh.srBagQuest == nil)
	S.me.combat = false
	W.Fire("BAG_UPDATE_DELAYED")
	check("...after it, it is", fresh.srBagQuest and fresh.srBagQuest:IsShown())
	bagFrame:Hide()
	_G.ContainerFrameCombinedBags, S.bagItems = nil, nil
	S.lootSlots, S.quests = nil, nil
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- the tracker shows every objective (four items: four lines; done ones dim, after the open ones)
	local QT = ns.QuestTracker
	S.quests = { { id = 1201, title = "Vier Dinge", level = 15, zone = "Westfall", objectives = {
		{ "Feder: 5/5", true, kind = "item" }, { "Zahn: 1/4", kind = "item" }, { "Fell: 0/6", kind = "item" }, { "Kralle: 2/3", kind = "item" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	QT.Refresh()
	local row
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() and r.quest and r.quest.id == 1201 then row = r end end
	local shown = 0
	for k = 1, #row.obj do if row.obj[k]:IsShown() then shown = shown + 1 end end
	check("tracker: all four objectives shown", shown == 4, shown)
	check("...the open ones first, the done one last and dim", row.obj[1]:GetText():find("Zahn", 1, true) and row.obj[4]:GetText():find("Feder", 1, true)
		and row.obj[4]._tc[1] < row.obj[1]._tc[1] + 0.001 and row.obj[4]._tc[1] < 0.5, row.obj[4]:GetText())
	-- far too many (none known): the last line says how many more
	local many = {}
	for i = 1, 11 do many[i] = { "Ding " .. i .. ": 0/1", kind = "item" } end
	S.quests = { { id = 1202, title = "Viel zu viel", level = 15, zone = "Westfall", objectives = many } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	QT.Refresh()
	for _, r in ipairs(QT.frame.rows) do if r:IsShown() and r.quest and r.quest.id == 1202 then row = r end end
	check("tracker: more than eight: the last line says how many more", row.obj[8]:IsShown() and row.obj[8]:GetText():find("+4 more", 1, true), row.obj[8]:GetText())
	S.quests = nil
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- other quests on the way (UI/QuestNearby.lua)
	local QN, Q, N, QA, QT = ns.QuestNearby, ns.Quests, ns.Plates, ns.QuestArrow, ns.QuestTracker
	local realSize = Q.MapSize
	Q.MapSize = function() return 1000, 1000 end
	S.mapId, S.mapPos = 9950, { 0.10, 0.10 }
	S.quests = { { id = 1301, title = "Wölfe", level = 10, zone = "Elwynn", objectives = { { "Wolf slain: 0/5" } } },
		{ id = 1302, title = "Koboldplage", level = 10, zone = "Elwynn", objectives = { { "Kobold Vermin slain: 2/8" } } } }
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	Q.ForgetMobs()
	Q.Select(1301)
	-- a mob the other quest needs: its plate flashes, the arrow says what it is for
	local realGet = C_NamePlate.GetNamePlateForUnit
	local plates = {}
	local function plateFor(unit, u)
		S.units[unit] = u
		local plate = CreateFrame("Frame")
		local uf = CreateFrame("Frame", nil, plate)
		uf.healthBar = CreateFrame("StatusBar", nil, uf)
		uf.name = uf:CreateFontString()
		plate.UnitFrame = uf
		plates[unit] = plate
		W.Fire("NAME_PLATE_UNIT_ADDED", unit)
		return N.skins[unit]
	end
	C_NamePlate.GetNamePlateForUnit = function(unit) return plates[unit] or realGet(unit) end
	if QA.frame then QA.frame:Show() end
	local kob = plateFor("nameplate70", { name = "Kobold Vermin", guid = "Creature-0-1-0-1-6-00000000F1", level = 5, isPlayer = false, hostile = true, reaction = 2 })
	check("another quest's mob: its plate flashes", kob and kob.srFlash and kob.srFlash:IsShown() and QN.flashing[kob] ~= nil)
	W.Update(0.4)
	check("...pulsing", kob.srFlash:GetAlpha() > 0)
	check("...the arrow says what it is for", QA.frame and (QA.frame.qnSay:GetText() or ""):find("Kobold Vermin for \"Koboldplage\" (6 to go)", 1, true), QA.frame and QA.frame.qnSay:GetText())
	W.Update(1.5)
	check("...for a moment only", not kob.srFlash:IsShown())
	local wolf = plateFor("nameplate71", { name = "Wolf", guid = "Creature-0-1-0-1-7-00000000F2", level = 5, isPlayer = false, hostile = true, reaction = 2 })
	check("the quest you navigate to: its mobs do not flash", not (wolf.srFlash and wolf.srFlash:IsShown()))
	W.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate70")
	kob = plateFor("nameplate70", { name = "Kobold Vermin", guid = "Creature-0-1-0-1-6-00000000F1", level = 5, isPlayer = false, hostile = true, reaction = 2 })
	check("the same one again: no second flash", not (kob.srFlash and kob.srFlash:IsShown()))
	for _, u in ipairs({ "nameplate70", "nameplate71" }) do W.Fire("NAME_PLATE_UNIT_REMOVED", u); S.units[u] = nil end
	C_NamePlate.GetNamePlateForUnit = realGet
	-- on the way: the other quest with little detour
	local here = { map = 9950, x = 0.10, y = 0.10 }
	local focus = { id = 1, title = "Ziel", target = { map = 9950, x = 0.50, y = 0.10 } }
	local list = { focus, { id = 2, title = "Unterwegs", target = { map = 9950, x = 0.30, y = 0.12 } },
		{ id = 3, title = "Abseits", target = { map = 9950, x = 0.30, y = 0.60 } } }
	local offer = QN.Offer(here, focus, list)
	check("on the way: the quest with little detour, not the one far off it", offer and offer.id == 2 and offer.extra < 1 and not offer.near, offer and offer.id)
	list[2] = nil
	check("...nothing on the way: none offered", QN.Offer(here, focus, list) == nil)
	list[2] = { id = 4, title = "Daneben", target = { map = 9950, x = 0.10, y = 0.22 } }
	offer = QN.Offer(here, focus, list)
	check("...right by you (120 yd), even off the way: offered", offer and offer.id == 4 and offer.near, offer and offer.id)
	-- the arrow's second line, and a click on it
	if QA.frame then
		local realHere = Q.Here
		Q.Here = function() return here end
		QA.quest = focus
		QA.frame:Show()
		QT.list = { focus, { id = 1302, title = "Koboldplage", target = { map = 9950, x = 0.30, y = 0.12 } } }
		QN.ForgetOffer()
		QN.ArrowLine()
		check("arrow: '+ Koboldplage · 201 yd'", QA.frame.qnLine:IsShown() and QA.frame.qnLine:GetText():find("+ Koboldplage · 201 yd", 1, true), QA.frame.qnLine:GetText())
		QA.frame.qnButton._scripts.OnClick(QA.frame.qnButton)
		check("...a click: navigate there instead", Q.selectedId == 1302)
		Q.Here = realHere
		QA.quest = nil
	end
	-- the tracker: quests close by get a mint bar
	S.questPins = { [9950] = { { questID = 1302, x = 0.12, y = 0.11 }, { questID = 1301, x = 0.9, y = 0.9 } } }
	Q.ForgetPins()
	Q.Select(1301)
	QT.Refresh()
	local nearRow, farRow
	for _, r in ipairs(QT.frame.rows) do
		if r:IsShown() and r.quest and r.quest.id == 1302 then nearRow = r elseif r:IsShown() and r.quest and r.quest.id == 1301 then farRow = r end
	end
	check("tracker: a quest close by gets a mint bar, the far one not", nearRow and nearRow.srNear and nearRow.srNear:IsShown()
		and not (farRow and farRow.srNear and farRow.srNear:IsShown()))
	Q.Select(nil)
	S.quests, S.questPins, S.mapId, S.mapPos = nil, nil, nil, nil
	Q.MapSize = realSize
	Q.ForgetPins()
	if QA.frame then QA.frame:Hide() end
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	W.Update(3.5)
end)()

;(function()
	-- the questbook (Questbook.lua): a quest handed in is kept for the account; a route from it
	local Q, QB = ns.Quests, ns.Questbook
	local realSize = Q.MapSize
	Q.MapSize = function() return 1000, 1000 end
	SITREP_DB.questbook = nil
	S.mapId, S.mapPos = 1429, { 0.55, 0.45 }
	S.quests = { { id = 401, title = "Wolf Hunt", level = 5, zone = "Elwynn Forest", objectives = { { "Wolf slain: 5/5", true } } } }
	Q.Store()[401] = { title = "Wolf Hunt", giver = { map = 1429, x = 0.5, y = 0.5 },
		obj = { [1] = { { map = 1429, x = 0.60, y = 0.5 }, { map = 1429, x = 0.62, y = 0.5 } } } }
	W.Fire("QUEST_TURNED_IN", 401, 450, 0)
	local e = SITREP_DB.questbook and SITREP_DB.questbook[401]
	check("questbook: a quest handed in is kept (title, xp, giver, hand-in, times)", e and e.t == "Wolf Hunt" and e.xp == 450 and e.n == 1
		and e.g.x == 0.5 and e.h.x == 0.55 and e.h.y == 0.45, e and e.t)
	check("questbook: each objective's middle place and its text without counts", e and e.o[1] and math.abs(e.o[1].x - 0.61) < 1e-9
		and e.o[1].text == "Wolf slain", e and e.o[1] and e.o[1].text)
	S.quests = {}
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
	-- another quest, one already done on this character, one far above your level
	local B = QB.Book()
	B[402] = { t = "Kobold Camp", lv = 5, xp = 300, n = 1, g = { map = 1429, x = 0.3, y = 0.5 }, o = { [1] = { map = 1429, x = 0.25, y = 0.5, text = "Kobold slain" } },
		h = { map = 1429, x = 0.3, y = 0.5 } }
	B[403] = { t = "Done Already", lv = 5, n = 1, g = { map = 1429, x = 0.5, y = 0.52 } }
	B[404] = { t = "Too Hard", lv = 99, n = 1, g = { map = 1429, x = 0.5, y = 0.51 } }
	B[405] = { t = "Elsewhere", lv = 5, n = 1, g = { map = 12, x = 0.5, y = 0.5 } }
	S.questsDone = { [403] = true }
	local r = QB.Route({ map = 1429, x = 0.5, y = 0.5 })
	local order, pos = {}, {}
	for i, st in ipairs(r.stops) do order[i] = st.kind .. st.id; pos[st.kind .. st.id] = i end
	check("route: starts at the nearest giver", order[1] == "pickup401", table.concat(order, " "))
	check("route: picked up, done, handed in, in that order, for each quest", pos.pickup401 < pos.objective401 and pos.objective401 < pos.turnin401
		and pos.pickup402 < pos.objective402 and pos.objective402 < pos.turnin402, table.concat(order, " "))
	check("route: not quests done before, too high, or on another map", not (pos.pickup403 or pos.pickup404 or pos.pickup405), table.concat(order, " "))
	check("route: the experience from the hand-ins", r.xp == 750, r.xp)
	-- a quest in your log ready to hand in: the arrow goes where it was handed in before
	S.quests = { { id = 402, title = "Kobold Camp", level = 5, zone = "Elwynn Forest", objectives = { { "Kobold slain: 8/8", true } }, complete = true } }
	local q = Q.List()[1]
	local t = Q.Target(q, { map = 1429, x = 0.5, y = 0.5 })
	check("hand-in known from the questbook: the arrow leads there", t and t.kind == "turnin" and t.x == 0.3, t and t.kind)
	local n0 = #W.prints
	S.mapPos = { 0.5, 0.5 }
	SlashCmdList.SITREP("route")
	local rep = table.concat(W.prints, "\n", n0 + 1)
	check("/sitrep route: the stops in order", rep:find("route on this map", 1, true) and rep:find("hand in Kobold Camp", 1, true), rep)
	S.quests, S.questsDone, S.mapId, S.mapPos = nil, nil, nil, nil
	SITREP_DB.questbook = nil
	Q.Store()[401] = nil
	Q.MapSize = realSize
	W.Fire("QUEST_LOG_UPDATE"); W.Update(0.4)
end)()

;(function()
	-- learned paths (Trails.lua): record where you walk, route the arrow along it
	local T = ns.Trails
	T.Forget()
	-- a row as a bit string and back
	local set = { [0] = true, [5] = true, [6] = true, [399] = true }
	local text = T.EncodeRow(set)
	local back = T.DecodeRow(text)
	check("trails: a row as 67 characters and back", #text == 67 and back[0] and back[5] and back[6] and back[399] and not back[1])
	-- walk an L: up from (0.10, 0.50) to (0.10, 0.20), then right to (0.40, 0.20)
	local MAP = 9001
	T.Record(nil)
	for y = 50, 20, -2 do T.Record({ map = MAP, x = 0.10, y = y / 100 }) end
	for x = 10, 40, 2 do T.Record({ map = MAP, x = x / 100, y = 0.20 }) end
	check("trails: the way between samples is walked too", T.Walked(MAP, 40, 150) and T.Walked(MAP, 40, 199) and T.Walked(MAP, 100, 80))
	check("trails: ground never walked is not", not T.Walked(MAP, 100, 200))
	-- the quest straight to the east over unknown ground: the arrow goes up the known way
	ns.P.quests.trails = true
	local here, target = { map = MAP, x = 0.10, y = 0.50 }, { map = MAP, x = 0.40, y = 0.20 }
	local wp = T.Waypoint(here, target)
	check("trails: unknown ground in between: the arrow follows the walked way (up it, about 50 yd ahead)", wp and wp.kind == "path"
		and math.abs(wp.x - 0.10) < 0.03 and wp.y < 0.49 and wp.y > 0.44, wp and (wp.x .. ", " .. wp.y))
	check("trails: the route goes round (up, then across: about 1500 yd, not 1080 straight)", wp and wp.yards > 1300 and wp.yards < 1700, wp and wp.yards)
	-- small gaps and a path beside it still count as known ground
	check("trails: a block next to a walked one is known ground", T.Known(MAP, 11, 40) and T.Known(MAP, 9, 40) and not T.Known(MAP, 14, 40))
	-- standing at the corner, the target is in a straight walked line: straight at it
	check("trails: a walked straight line: straight at the target", T.Waypoint({ map = MAP, x = 0.10, y = 0.20 }, target) == nil)
	-- no walked way near the target: straight at it
	check("trails: no known way there: straight at it", T.Waypoint(here, { map = MAP, x = 0.90, y = 0.90 }) == nil)
	-- another map: not routed
	check("trails: only on the same map", T.Waypoint(here, { map = MAP + 1, x = 0.4, y = 0.2 }) == nil)
	-- kept for the account
	T.Save()
	local maps, cells, chars = T.Size()
	check("trails: saved as bit strings per row, a few KB", ns.db.trails[MAP] and #ns.db.trails[MAP][200] == 67 and maps == 1 and cells > 100 and chars < 10000,
		maps .. " " .. cells .. " " .. chars)
	ns.P.quests.trails = false
	check("trails: switched off: straight at the target", T.Waypoint(here, target) == nil)
	ns.P.quests.trails = true
	-- a cave: east outside to its mouth at (0.30, 0.70), then inside north to (0.30, 0.56)
	local CAVE = 9002
	T.Record(nil)
	for x = 10, 30, 2 do T.Record({ map = CAVE, x = x / 100, y = 0.70 }, false) end
	for y = 70, 56, -2 do T.Record({ map = CAVE, x = 0.30, y = y / 100 }, true) end
	check("caves: going in marks the door, walked in both layers", T.IsDoor(CAVE, 120, 280) and T.Walked(CAVE, 120, 280)
		and T.Walked(T.Layer(CAVE, true), 120, 280), tostring(T.IsDoor(CAVE, 120, 280)))
	check("caves: the inside is its own layer", T.Walked(T.Layer(CAVE, true), 120, 240) and not T.Walked(CAVE, 120, 240))
	-- the quest in the cave, standing outside at the start: the arrow leads to the mouth
	local wp2 = T.Waypoint({ map = CAVE, x = 0.28, y = 0.70 }, { map = CAVE, x = 0.27, y = 0.57 }, false)
	check("caves: from outside the arrow leads to the entrance (not through the rock)", wp2 and wp2.door and math.abs(wp2.x - 0.30) < 0.01
		and math.abs(wp2.y - 0.70) < 0.01, wp2 and (wp2.x .. ", " .. wp2.y .. " door " .. tostring(wp2.door)))
	-- inside, the target ahead in a straight walked line: straight at it
	check("caves: inside, a straight walked line: straight at it", T.Waypoint({ map = CAVE, x = 0.30, y = 0.66 }, { map = CAVE, x = 0.30, y = 0.57 }, true) == nil)
	T.Forget()
end)()

;(function()
	-- party frames: how well geared each member is (health against class and level)
	local S_, F = ns.Sensors, ns.Frames
	for i = 1, 10 do S_.ToughSample("Player-1-PR" .. i, "PALADIN", 33, i % 2 == 0 and 950 or 1050) end
	local savedN, savedP1 = S.group.n, S.units.party1
	S.group.n = 1
	S.units.party1 = { name = "Heila", guid = "Player-1-PRX", class = "PALADIN", level = 33, isPlayer = true, hostile = false, faction = "Alliance",
		hp = 1300, hpMax = 1300, wx = 5, wy = 0 }
	local f = F.partyMembers[1]
	F.UpdateMember(f)
	-- (she counts towards the average too: 1300 against (10 x 1000 + 1300) / 11)
	check("party frame: HP +27% (well geared), not in grey", (f.tags:GetText() or ""):find("HP +27%", 1, true) ~= nil
		and (f.tags:GetText() or ""):find("8c9993", 1, true) == nil, f.tags:GetText())
	S.units.party1.hpMax, S.units.party1.hp = 1000, 1000
	S_.hpMaxOf["Player-1-PRX"] = nil
	F.UpdateMember(f)
	check("...about average: grey", (f.tags:GetText() or ""):find("HP -3%", 1, true) ~= nil and (f.tags:GetText() or ""):find("8c9993", 1, true) ~= nil, f.tags:GetText())
	S.group.n, S.units.party1 = savedN, savedP1
	F.UpdateMember(f)
end)()

;(function()
	-- flight paths (Travel.lua): fly when it is clearly quicker
	local TR = ns.Travel
	local MAP = 9100 -- (3000 x 2000 yd in the emulator)
	S.taxiNodes = { [MAP] = { { "Ost", 0.10, 0.10 }, { "West", 0.90, 0.90 }, { "Mitte", 0.50, 0.50 } } }
	ns.db.flight = nil
	local here, target = { map = MAP, x = 0.11, y = 0.10 }, { map = MAP, x = 0.88, y = 0.88 }
	check("travel: no flight points known yet: no plan", TR.Plan(here, target) == nil)
	-- at the flight master: what this character knows
	S.taxiOpen = { { "Ost", "CURRENT" }, { "West", "REACHABLE" }, { "Mitte", "NONE" } }
	W.Fire("TAXIMAP_OPENED")
	check("travel: the known flight points learned", TR.Known().Ost and TR.Known().West and not TR.Known().Mitte)
	local plan = TR.Plan(here, target)
	check("travel: far away: walk to Ost, fly to West, walk on", plan and plan.from == "Ost" and plan.to == "West" and not plan.learned
		and plan.total < plan.direct * 0.8, plan and (plan.total .. " vs " .. tostring(plan.direct)))
	check("travel: close by: no flight", TR.Plan(here, { map = MAP, x = 0.15, y = 0.12 }) == nil)
	-- on foot after riding: the riding speed is not your speed now (4.9.17 took it: walking looked quicker)
	ns.Quests.rideSpeed = 14
	check("travel: on foot, the riding speed learned is not used", TR.Speed() == 7)
	S.me.mounted = true
	check("travel: mounted: the riding speed", TR.Speed() == 14)
	S.me.mounted, ns.Quests.rideSpeed = nil, nil
	-- the ground's way is longer than the straight line
	local why = {}
	TR.Plan(here, { map = MAP, x = 0.15, y = 0.12 }, why)
	check("travel: the way on the ground counts its bends (1.25 times the straight line)", why.direct and math.abs(why.direct - why.straight * 1.25 / 7) < 1e-6
		and why.reason:find("not quick enough", 1, true), why.reason)
	-- /sitrep flyprobe: why (for the quest you navigate to)
	local realSel, realHere = ns.Quests.Selected, ns.Quests.Here
	ns.Quests.Selected = function() return { title = "Far", target = target } end
	ns.Quests.Here = function() return here end
	local n0 = #W.prints
	SlashCmdList.SITREP("flyprobe")
	local rep = table.concat(W.prints, "\n", n0 + 1)
	check("/sitrep flyprobe: what was weighed and the outcome", rep:find("Ost > West", 1, true) and rep:find("-> fly: Ost to West", 1, true), rep)
	ns.Quests.Selected, ns.Quests.Here = realSel, realHere
	-- a flight: how long it took is learned
	S.me.onTaxi = true
	TR.Watch(1000)
	S.me.onTaxi = false
	local savedMap, savedPos = S.mapId, S.mapPos
	S.mapId, S.mapPos = MAP, { 0.90, 0.90 }
	TR.Watch(1090)
	check("travel: the flight's time learned (90 s)", ns.db.flight.times["Ost>West"] == 90 and select(2, TR.FlightTime("Ost", "West", MAP)) == true)
	S.mapId, S.mapPos = savedMap, savedPos
	-- the arrow leads to the flight master
	local Q, QA = ns.Quests, ns.QuestArrow
	if QA and QA.frame then
		local realHere, realPlan = Q.Here, TR.Plan
		Q.Here = function() return here end
		QA.quest = { title = "Far", target = target }
		QA.frame:Show()
		S.facing = 0
		QA.Update()
		check("travel: the arrow says where to fly", W.has(QA.frame.kind:GetText(), "FLY WEST") ~= nil
			and W.has(QA.frame.dist:GetText(), "TO OST") ~= nil, QA.frame.kind:GetText() .. " | " .. QA.frame.dist:GetText())
		Q.Here = realHere
		QA.quest = nil
		QA.frame:Hide()
	end
	S.taxiNodes, S.taxiOpen, ns.db.flight = nil, nil, nil
end)()

local exported, why = ns.ExportProfile()
check("export degrades without C_EncodingUtil", exported == nil and why == "encoding API missing")
SlashCmdList.SITREP("reset")
check("reset restores doctrine", ns.P.hud.accent == "nvg" and ns.P.hud.envelopeLanes == 6)
W.Update(0.25)

---------------------------------------------------------------------------
-- Hygiene
---------------------------------------------------------------------------
-- Protected checks asked about a friend in combat are blocked actions in the
-- client ("Interface action failed because of an AddOn"): none in the whole run.
check("no blocked actions in the whole run", W.blockedCalls == 0, W.blockedCalls .. " " .. table.concat(W.blockedLog, ", "))

local errs = {}
for e, n in pairs(ns.errorCounts) do errs[#errs + 1] = n .. "x " .. e end
check("no internal errors caught by the bus", #errs == 0, table.concat(errs, "\n      "))

-- Every name the code reads without defining it must be a client global (known to
-- the emulator, or listed below as client-only): a name left behind by a move
-- between files, or a typo, fails here instead of in the game. Uses luajit's
-- bytecode listing; skipped where luajit is missing.
local CLIENT_ONLY = {
	AbbreviateLargeNumbers = 1, C_EncodingUtil = 1, ChatFrame1 = 1, CombatLogGetCurrentEventInfo = 1,
	CompactUnitFrame_UpdateHealthColor = 1, CompactUnitFrame_UpdateName = 1, CurveConstants = 1, GetCreatureDifficultyColor = 1,
	GetMacroSpell = 1, IsInInstance = 1, IsPlayerSpell = 1, IsSpellKnown = 1, LOCALIZED_CLASS_NAMES_MALE = 1, PowerBarColor = 1,
	RAID_CLASS_COLORS = 1, SendChatMessage = 1, UnitCreatureType = 1, UnitHealthPercent = 1, issecrettable = 1,
	CreateVector2D = 1, QuestPOIGetIconInfo = 1, QuestMapFrame_OpenToQuestDetails = 1, QuestLogFrame = 1, ToggleQuestLog = 1,
	QuestLog_SetSelection = 1, QuestLog_Update = 1, GetNumFriends = 1, GetMouseFocus = 1,
	SITREP = 1, SITREP_DB = 1, SITREP_Report = 1, SITREP_QuestNav = 1, SITREP_ToggleChat = 1, SITREP_ToggleQuestList = 1, SITREP_ToggleConfig = 1, SITREP_ToggleHUD = 1,
}
local probe = io.popen("command -v luajit 2>/dev/null")
local hasLuajit = probe and (probe:read("*l") or "") ~= ""
if probe then probe:close() end
if hasLuajit then
	local unknown = {}
	for _, file in ipairs(toc) do
		local list = io.popen("luajit -bl 'SITREP/" .. file .. "'")
		for line in list:lines() do
			local name = line:match('GGET.-;%s*"([%w_]+)"')
			if name and before[name] == nil and not CLIENT_ONLY[name] then unknown[#unknown + 1] = file .. ": " .. name end
		end
		list:close()
	end
	check("every name the code reads exists (no leftovers from moves, no typos)", #unknown == 0, table.concat(unknown, ", "))
	check("no font family set on a string with a face of its own (the game keeps the face: boxes)", not W.familyIgnored, (function() local o = {} for k, v in pairs(W.familyWhere or {}) do o[#o + 1] = k .. " x" .. v end return table.concat(o, ", ") end)())
end

local allowed = {
	SITREP = true, SITREP_DB = true, SITREP_Report = true, SITREP_QuestNav = true, SITREP_ToggleHUD = true, SITREP_ToggleConfig = true,
	SLASH_SITREP1 = true, SLASH_SITREP2 = true,
}
local leaks = {}
for k in pairs(_G) do
	if not before[k] and not allowed[k] and not tostring(k):match("^BINDING_") and not tostring(k):match("^SITREP_") then
		leaks[#leaks + 1] = tostring(k)
	end
end
check("no stray globals", #leaks == 0, table.concat(leaks, ", "))

print(string.format("\n%d passed, %d failed  (%s)", passed, failed, _VERSION .. (jit and (" / " .. jit.version) or "")))
os.exit(failed == 0 and 0 or 1)
