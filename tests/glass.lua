-- The glass skin (the default look), in a fresh client of its own: the main suite
-- (tests/run.lua) runs the tactical skin, whose texts and shapes it checks.
--   luajit tests/glass.lua      lua5.5 tests/glass.lua
package.path = "tests/?.lua;" .. package.path
local W = require("wow_mock")

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed = passed + 1
	else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local ns = {}
for line in io.lines("SITREP/SITREP.toc") do
	if line ~= "" and not line:match("^##") then assert(loadfile("SITREP/" .. line:gsub("\\", "/")))("SITREP", ns) end
end
local S = W.scenario
S.me = { x = 0, y = 0, facing = 0, inst = 1 }
S.units.player = { name = "Tobi", guid = "Player-1-0001", class = "DRUID", level = 34, hostile = false, faction = "Alliance", hp = 3620, hpMax = 3620, dist = 0 }
-- Blizzard-like plates
local plates = {}
C_NamePlate.GetNamePlateForUnit = function(unit)
	local u = S.units[unit]
	if not (u and u.screenX) then return nil end
	local p = plates[unit]
	if not p then
		p = CreateFrame("Frame")
		local uf = CreateFrame("Frame", nil, p)
		uf.healthBar = CreateFrame("StatusBar", nil, uf)
		uf.name = uf:CreateFontString()
		uf.CastBarsContainer = CreateFrame("Frame", nil, uf)
		uf.CastBarsContainer.castBar = CreateFrame("StatusBar", nil, uf.CastBarsContainer)
		p.UnitFrame = uf
		plates[unit] = p
	end
	return p
end
CompactUnitFrame_UpdateHealthColor = function() end

W.Fire("ADDON_LOADED", "SITREP")
W.Fire("PLAYER_LOGIN")
W.Fire("SPELLS_CHANGED")
W.Update(0.25)
local K = ns.Kit

check("one look: no skin setting left (the old one dropped from the profile)", ns.P.hud.skin == nil and K.Glass == nil)
check("glass: DM Sans from the addon's folder", K.FONT:find("Media\\Fonts\\DMSans", 1, true) ~= nil, K.FONT)
check("glass: the palette in K.C", math.abs(K.C.bg[4] - 0.78) < 1e-9 and math.abs(K.C.red[2] - 0.48) < 1e-9)

-- sentence case
check("case: capitals to a sentence", K.Case("TARGETED BY 2") == "Targeted by 2", K.Case("TARGETED BY 2"))
check("case: abbreviations stay", K.Case("HVT  ·  PRIEST Aldwin") == "HVT  ·  Priest Aldwin", K.Case("HVT  ·  PRIEST Aldwin"))
check("case: colour codes and names untouched", K.Case("|cffff5555IN REACH OF 2 ENEMIES|r") == "|cffff5555In reach of 2 enemies|r"
	and K.Case("Vex") == "Vex", K.Case("|cffff5555IN REACH OF 2 ENEMIES|r"))
check("case: a texture escape untouched", K.Case("|TInterface\\AddOns\\SITREP\\Media\\glyph_plus:10:10|t HEALER") ==
	"|TInterface\\AddOns\\SITREP\\Media\\glyph_plus:10:10|t Healer")
check("case: secret text passed as it is", K.Case(W.Secret("x")) ~= nil)
check("upper: glass keeps the case", K.Upper("in Sumpfland") == "in Sumpfland")
local fs = K.Font(UIParent, 12)
fs:SetText("OUT OF ENEMY REACH")
check("fonts write in sentence case", fs:GetText() == "Out of enemy reach", fs:GetText())

-- panels: rounded glass with a shadow; rings instead of hairlines; no brackets
local pane = K.Panel(UIParent, 200, 80, { mood = true })
check("panel: a rounded pane (nine pieces) with a shadow", type(pane.bg) == "table" and #pane.bg.parts == 9 and #pane.bg.shadow == 9
	and pane.bg.parts[1]:GetTexture():find("fill12", 1, true) ~= nil)
check("panel: no corner brackets", #(pane.brackets or {}) == 0)
check("panel: a ring answering like four lines", pane.border[1].parts and pane.border.SetColor ~= nil)
pane.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
check("pane: tinted as one", select(4, pane.bg.parts[5]:GetVertexColor()) == 0.8 * K.mood)
-- calm and combat
K.SetMood(false)
check("calm: the glass lighter", math.abs(select(4, pane.bg.parts[5]:GetVertexColor()) - 0.8 * K.CALM) < 1e-9)
K.SetMood(true)
check("combat: the glass dense", math.abs(select(4, pane.bg.parts[5]:GetVertexColor()) - 0.8) < 1e-9)
local flat = K.Border(CreateFrame("Frame", nil, UIParent), { 0, 0, 0, 1 }, 1, 0)
check("radius 0: straight lines in glass too", flat[1].SetHeight ~= nil and flat[1].parts == nil)

-- glyphs on the plates
local N = ns.Plates
check("tag: you is a coral diamond", N.Tag("you"):find("glyph_diamond", 1, true) ~= nil and N.Tag("you"):find(":255:122:107|t", 1, true) ~= nil, N.Tag("you"))
check("tag: healer a mint plus, a quest mob's count after its glyph", N.Tag("healer"):find("glyph_plus", 1, true) and N.Tag("quest", "3/8"):find("3/8", 1, true))
S.units.nameplate1 = { name = "Vex", guid = "Player-2-00A1", class = "ROGUE", level = 36, isPlayer = true, hostile = true, faction = "Horde",
	dist = 12, screenX = 900, hp = 1200, hpMax = 3500, targetingMe = true }
W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
W.Update(0.25)
local s = N.skins.nameplate1
N.Refresh(s)
check("plate: the glyph on the name line", s and (s.name:GetText() or ""):find("glyph_diamond", 1, true) ~= nil, s and s.name:GetText())
check("plate: no red side lines (gone with the old look): the coral ring marks enemy players", s and s.react == nil and s.foe:IsShown())

-- the ghost of damage just taken
local pf = ns.Frames.frames.player
check("player frame: a ghost behind the health", pf and pf.hp.ghost ~= nil)
local U = ns.Units
pf.hp:SetWidth(200)
U.FeedGhost(pf.hp, 1.0, 100)
U.FeedGhost(pf.hp, 0.6, 100)
check("ghost: the lost health stays lit", pf.hp.ghost:IsShown() and math.abs(pf.hp.ghost:GetWidth() - 200) < 1e-6, pf.hp.ghost:GetWidth())
U.StepGhosts(100.45 + 0.225)
check("ghost: then runs down", math.abs(pf.hp.ghost:GetWidth() - 160) < 1e-6, pf.hp.ghost:GetWidth())
U.StepGhosts(101.5)
check("ghost: gone once it caught up", not pf.hp.ghost:IsShown())
U.FeedGhost(pf.hp, 0.9, 102)
check("ghost: healing shows none", not pf.hp.ghost:IsShown())

-- the quest tracker folds in combat
local QT = ns.QuestTracker
S.quests = { { id = 1, title = "Bedrohung durch die Blackrock", level = 33, zone = "Rotkammgebirge", objectives = { { "Späher getötet: 3/8" } } } }
W.Fire("QUEST_LOG_UPDATE")
QT.Refresh()
S.me.combat = true
W.Fire("PLAYER_REGEN_DISABLED")
check("quests: folded into the header in combat", QT.folded and not QT.frame.rows[1]:IsShown())
S.me.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
check("quests: open again after it", not QT.folded and QT.frame.rows[1]:IsShown())

-- round your character
check("gaze layout", ns.Layout.Gaze() and ns.P.hud.pos.player[1] == "BOTTOMRIGHT" and ns.P.hud.pos.target[1] == "BOTTOMLEFT"
	and ns.P.hud.pos.castAlert[2] == "CENTER")
S.me.combat = true
check("gaze layout: not in combat", ns.Layout.Gaze() == false)
S.me.combat = false

-- the console builds in glass
ns.Config.Open("overview")
for _, id in ipairs({ "overview", "display", "layout", "frames", "plates", "quests", "alerts" }) do
	ns.Config._open(id)
	check("console page builds in glass: " .. id, ns.Config._page(id) ~= nil)
end

-- a smoke test: most of SITREP running in glass (errors and blocked actions are checked below)
;(function()
	S.group.n = 1
	S.units.party1 = { name = "Mira", guid = "Player-1-0002", class = "PRIEST", level = 34, isPlayer = true, hostile = false, faction = "Alliance",
		hp = 2000, hpMax = 2600, wx = 5, wy = 0 }
	W.Fire("GROUP_ROSTER_UPDATE")
	S.units.nameplate2 = { name = "Aldwin", guid = "Player-2-00B2", class = "MAGE", level = 35, isPlayer = true, hostile = true, faction = "Horde",
		dist = 28, screenX = 700, hp = 3000, hpMax = 3000, casting = true, targetingMe = true }
	S.units.nameplate3 = { name = "Späher", guid = "Creature-0-1-0-1-68-0000000001", isPlayer = false, hostile = true, reaction = 2, level = 33,
		dist = 25, screenX = 500, hp = 900, hpMax = 900, classification = "rare" }
	for _, u in ipairs({ "nameplate2", "nameplate3" }) do W.Fire("NAME_PLATE_UNIT_ADDED", u) end
	S.units.target = S.units.nameplate1
	W.Fire("PLAYER_TARGET_CHANGED")
	S.me.combat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Fire("UNIT_SPELLCAST_START", "nameplate2")
	for i = 1, 6 do
		W.Fire("UNIT_COMBAT", "player", "WOUND", i % 2 == 0 and "CRITICAL" or "", 300, i % 2 == 0 and 16 or 1)
		S.units.player.hp = S.units.player.hp - 300
		W.Fire("UNIT_HEALTH", "player")
		W.Update(0.25)
	end
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate2")
	W.Fire("PLAYER_DEAD")
	W.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "x")
	S.me.combat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Update(3)
	check("smoke: the death recap shown", ns.RecapPanel.frame and ns.RecapPanel.frame:IsShown())
	-- every console page, placing mode, the commands
	for _, id in ipairs({ "overview", "sensors", "threat", "matrix", "engage", "pressure", "comms", "alerts", "display", "layout", "frames",
		"plates", "interface", "quests", "bars", "log", "trackers" }) do
		ns.Config._open(id)
	end
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	W.Update(0.25)
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	for _, cmd in ipairs({ "doctor", "perf 5", "perf stop", "recap", "kicks", "ideaprobe stop" }) do SlashCmdList.SITREP(cmd) end
	ns.HUD.Banner("RARE  ·  SILBERZAHN (24)", 1, 1, 1)
	ns.Fire("SR_STEALTH", { class = "ROGUE", name = "Vex" }, 12)
	W.Update(1)
end)()

;(function()
	-- the console's display page refreshes (it holds a button without a Refresh)
	ns.Config._open("display")
	local ok, err = pcall(function() ns.Config._page("display"):Refresh() end)
	check("console: the display page refreshes", ok, err)
	-- the cast alert's line centred as a whole
	local IU = ns.IncomingUI
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	local f = IU.alert
	local okW, ww = pcall(f.who.GetStringWidth, f.who)
	local _, tw = pcall(f.tail.GetStringWidth, f.tail)
	local x
	for _, v in ipairs({ f.spell:GetPoint(1) }) do if type(v) == "number" then x = v break end end
	check("cast alert: the whole line centred", okW and math.abs(x - (ww - tw) / 2) < 1e-6, tostring(x))
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	-- the experience line inside the rounded corners
	local xb = ns.XP and ns.XP.bar
	if xb then
		local nums = {}
		for _, v in ipairs({ xb:GetPoint(1) }) do if type(v) == "number" then nums[#nums + 1] = v end end
		check("xp line: on the bottom edge, inside the rounded corners", nums[1] == 12 and nums[2] == 0, table.concat(nums, ","))
	end
end)()

;(function()
	-- the alert banner: movable; unlocked, a sample to drag
	local b = _G.SITREP_Banner
	ns.P.hud.locked = false; ns.Changed("hud.locked")
	check("banner: unlocked, a sample shows to place it", b:IsShown() and b.placing and W.has(b.text:GetText(), "drag to move"))
	b._x, b._y = 700, 600
	b.srGrip._scripts.OnDragStart(b.srGrip)
	b.srGrip._scripts.OnDragStop(b.srGrip)
	check("...dragged: its place kept", ns.P.hud.pos.banner ~= nil)
	W.Update(5)
	check("...the sample stays while placing", b:IsShown())
	ns.P.hud.locked = true; ns.Changed("hud.locked")
	check("...locked: gone (alerts show there again)", not b:IsShown() and not b.placing)
	ns.HUD.Banner("HVT  ·  DRUID Dularm", 0.4, 1, 0.6)
	check("...a real alert at the new place", b:IsShown() and ({ b:GetPoint(1) })[1] == ns.P.hud.pos.banner[1])
	ns.P.hud.pos.banner = nil
end)()

;(function()
	-- the console: a little see-through
	ns.Config.Open("overview")
	local cw = _G.SITREP_Console
	check("console: a little see-through", cw and W.vc(cw.bg)[4] < 0.95 and W.vc(cw.bg)[4] >= 0.79, cw and tostring(W.vc(cw.bg)[4]))
	ns.Config.Toggle()
end)()

;(function()
	-- the target frame's pane: as tall as what it shows (the frame itself keeps its size)
	local TF, PANE = ns.Frames.target, ns.Frames.PANE
	local saved = S.units.target
	S.units.target = { name = "Späher", guid = "Creature-0-1-0-1-68-0000000009", isPlayer = false, hostile = true, reaction = 2, level = 33,
		dist = 25, hp = 900, hpMax = 900 }
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.3)
	local box = ns.Kit.Region(TF.bg)
	check("target pane: a mob without its target, no intel: ends under the range strip", TF.paneH == PANE.strip and box._h == PANE.strip
		and TF.border.box._h == PANE.strip and TF:GetHeight() == 142, tostring(TF.paneH))
	S.units.target = { name = "Aldwin", guid = "Player-2-00B9", class = "MAGE", level = 35, isPlayer = true, hostile = true, faction = "Horde",
		dist = 28, hp = 3000, hpMax = 3000 }
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.3)
	check("...an enemy player with the matchup line: down to it", TF.paneH >= PANE.intel, tostring(TF.paneH))
	local pt = { ns.Auras.rows.targetDebuffs:GetPoint(1) }
	check("the target's debuffs hang under the pane, not the frame: they move with it", pt[2] == box and pt[3] == "BOTTOMLEFT", tostring(pt[2]))
	local pb = { ns.Auras.rows.targetBuffs:GetPoint(1) }
	check("...its buffs over the pane", pb[1] == "BOTTOMLEFT" and pb[2] == box and pb[3] == "TOPLEFT", tostring(pb[1]))
	S.units.target = saved
	W.Fire("PLAYER_TARGET_CHANGED"); W.Update(0.3)
end)()

;(function()
	-- the banner's coloured line stops where its corners start to round
	ns.P.alerts.banner = true
	ns.HUD.Banner("HVT  ·  DRUID Dularm", 0.4, 1, 0.6)
	local e = _G.SITREP_Banner and _G.SITREP_Banner.edge
	local l, r = e and e._points and e._points[#e._points - 1], e and e._points and e._points[#e._points]
	check("banner line: inside the rounded corners, shown", e and e:GetAlpha() == 1 and l and r and l[1] == "BOTTOMLEFT" and l[4] == ns.HUD.BANNER_RADIUS
		and r[1] == "BOTTOMRIGHT" and r[4] == -ns.HUD.BANNER_RADIUS, l and (tostring(l[4]) .. " " .. tostring(r[4])))
	-- the minimap: rounded corners, 12 px at any size, on a glass pane
	local MM = ns.Minimap
	check("minimap: a rounded mask (12 px at 180)", Minimap._mask == ns.Kit.MEDIA .. "mapmask15" and MM.frame.paneFrame:IsShown()
		and not MM.frame.head.bg:IsShown(), tostring(Minimap._mask))
	ns.P.ui.mapSize = 600; ns.Changed("ui.mapSize")
	check("minimap: bigger, a smaller radius in the mask (the corner stays 12 px)", Minimap._mask == ns.Kit.MEDIA .. "mapmask5", tostring(Minimap._mask))
	ns.P.ui.mapSize = 180; ns.Changed("ui.mapSize")
	ns.P.ui.minimap = false; ns.Changed("ui.minimap")
	check("minimap off: round again, no pane", Minimap._mask == "Textures\\MinimapMask" and not MM.frame.paneFrame:IsShown())
	ns.P.ui.minimap = true; ns.Changed("ui.minimap")
	-- the zen switch on the minimap's zone strip
	local z = ns.Minimap.frame and ns.Minimap.frame.zen
	local before = ns.P.plates.friendZen
	check("a first start: friendly zen on (the preset), the switch lit", before == true and z.text._tc[2] > 0.9)
	z:GetScript("OnClick")(z)
	check("minimap zen switch: off, the plates follow, the switch dim", ns.P.plates.friendZen == false and z.text._tc[2] < 0.9)
	z:GetScript("OnClick")(z)
	check("...and on again, lit", ns.P.plates.friendZen == true and z.text._tc[2] > 0.9)
end)()

W.Update(1)
check("glass: no blocked actions", W.blockedCalls == 0, W.blockedCalls .. " " .. table.concat(W.blockedLog, ", "))
local errs = {}
for e, n in pairs(ns.errorCounts) do errs[#errs + 1] = n .. "x " .. e end
check("glass: no internal errors", #errs == 0, table.concat(errs, "\n      "))

print(string.format("\n%d passed, %d failed  (glass, %s)", passed, failed, jit and jit.version or _VERSION))
os.exit(failed == 0 and 0 or 1)
