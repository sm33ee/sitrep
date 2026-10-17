-- SITREP · Console pages: settings (pressure, comms, alerts, display, layout, frames, nameplates, interface, quests, bars & menu)

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local format, max = string.format, math.max
local Cfg = ns.Config
local W, NAV = Cfg.W, Cfg.NAV
local kit = Cfg.kit
local set, get, newPage = kit.set, kit.get, kit.newPage
local f2, fs, fy, fp = kit.f2, kit.fs, kit.fy, kit.fp

-- 06 PRESSURE
---------------------------------------------------------------------------
local function buildPressure()
	local p = newPage("Pressure", "Incoming damage from UNIT_COMBAT; shadow health keeps a time-to-live while real health is secret.")
	p:Place(K.Slider(p, "Short window", 1, 6, 0.5, get("pressure", "short"), set("pressure", "short"), function(v) return format("%.1fs", v) end), 1)
	p:Place(K.Slider(p, "Long window", 5, 20, 1, get("pressure", "long"), set("pressure", "long"), fs), 1)
	local function pctFmt(v) return format("%.0f%%/s  (full in %.0fs)", v, 100 / v) end
	p:Place(K.Slider(p, "Orange from damage per second of", 2, 20, 1, get("pressure", "warnPct"), set("pressure", "warnPct"), pctFmt), 1)
	p:Place(K.Slider(p, "Red from damage per second of", 4, 30, 1, get("pressure", "dangerPct"), set("pressure", "dangerPct"), pctFmt), 1)
	p:Place(K.Slider(p, "Spike: % of max health in 1.5s", 10, 60, 1, get("pressure", "spikePct"), set("pressure", "spikePct"), function(v) return v .. "%" end), 2)
	p:Place(K.Slider(p, "DEFEND when time-to-live below", 2, 10, 0.5, get("pressure", "ttlWarn"), set("pressure", "ttlWarn"), function(v) return format("%.1fs", v) end), 2)
	local note = K.Font(p, 11, C.dim)
	note:SetJustifyH("LEFT")
	note:SetHeight(80)
	note:SetText("Shadow health = last plain reading - damage taken + healing received. It resyncs every time the client shows plain health again (out of combat). Absorbs and overheal are the main sources of drift; the gauge marks the value EST while it is running on the shadow.")
	p.y[1] = max(p.y[1], p.y[2]) + 10
	note:SetWidth(W - NAV - 60)
	note.fixedWidth = true
	p:Place(note, 1)
	return p
end

---------------------------------------------------------------------------
-- 07 COMMS
---------------------------------------------------------------------------
local CHANNELS = {
	{ "AUTO", "Auto (instance > raid > party)" }, { "PARTY", "Party" }, { "RAID", "Raid" },
	{ "INSTANCE_CHAT", "Instance" }, { "GUILD", "Guild" }, { "SAY", "Say" }, { "SELF", "Only me (chat frame)" },
}

local function buildComms()
	local p = newPage("Comms", "Contact reports on a key press, and a shared picture over the addon channel.")
	p:Place(K.Dropdown(p, "Report channel", CHANNELS, get("comms", "channel"), set("comms", "channel")), 1)
	p:Place(K.Toggle(p, "Share contacts with group", "Your sightings appear on your group's HUDs, theirs on yours.", get("comms", "share"), set("comms", "share")), 2)
	p:Place(K.Slider(p, "Share rate", 0.5, 5, 0.5, get("comms", "shareRate"), set("comms", "shareRate"), function(v) return format("%.1f msg/s", v) end), 2)

	p.y[1] = max(p.y[1], p.y[2]) + 4
	local tl = K.Font(p, 12, C.text)
	tl:SetText("Report template")
	p:Place(tl, 1, 4)
	local box = K.EditBox(p, W - NAV - 60, 26)
	box.fixedWidth = true
	p:Place(box, 1, 4)
	local tokens = K.Font(p, 10, C.dim, K.FONT, "")
	tokens:SetText("{n} {comp} {range} {zone} {hvt} {advice} {pwin} {ratio}")
	p:Place(tokens, 1, 14)
	local pl = K.Font(p, 10, C.dim, K.FONT, "")
	pl:SetText("PREVIEW")
	p:Place(pl, 1, 4)
	local preview = K.Panel(p, W - NAV - 60, 44, { color = { 0, 0, 0, 0.5 }, bracketLen = 6 })
	preview.fixedWidth = true
	preview.text = K.Font(preview, 12, { 1, 0.5, 0.25, 1 })
	preview.text:SetPoint("TOPLEFT", 10, -8)
	preview.text:SetPoint("BOTTOMRIGHT", -10, 8)
	preview.text:SetJustifyH("LEFT")
	p:Place(preview, 1, 12)
	local send = K.Button(p, "Send report now", 150, 24, function() ns.Comms.Report() end, true)
	send.fixedWidth = true
	p:Place(send, 1)

	local e = box.edit
	e:SetScript("OnTextChanged", function(self, user)
		if user then
			ns.P.comms.template = self:GetText()
			p:OnRefresh()
		end
	end)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	function p:OnRefresh()
		if not e:HasFocus() then e:SetText(ns.P.comms.template) end
		local line = ns.Comms.Compose()
		if not line then
			-- A stand-in picture so the template can be edited with nothing around.
			line = ns.P.comms.template:gsub("{(%w+)}", {
				n = "3", comp = "2 Rogue, Priest", range = "20-28y", zone = "Hillsbrad Foothills - Tarren Mill",
				hvt = "HVT Priest Aldwin | ", advice = "CONTEST", pwin = "P(win) 54%", ratio = "1.1:1",
			})
		end
		preview.text:SetText(line)
	end
	p.live = true
	return p
end

---------------------------------------------------------------------------
-- 08 ALERTS
---------------------------------------------------------------------------
local function buildAlerts()
	local p = newPage("Alerts", "What interrupts you, and how.")
	p:Place(K.Toggle(p, "Banner", "Short line under the top of the screen.", get("alerts", "banner"), set("alerts", "banner")), 1)
	p:Place(K.Toggle(p, "Screen-edge flash", "Red vignette when targeted or spiked.", get("alerts", "flash"), set("alerts", "flash")), 1)
	p:Place(K.Toggle(p, "Sound", nil, get("alerts", "sound"), set("alerts", "sound")), 1)
	p:Place(K.Toggle(p, "Emergency items in combat", "Your best healthstone and healing potion beside you; lit when your health is low and they are ready. Click to use. Place them in Layout.",
		get("frames", "emergency"), set("frames", "emergency")), 1)
	p:Place(K.Slider(p, "Light them up under", 10, 80, 5, get("frames", "emergencyPct"), set("frames", "emergencyPct"), function(v) return v .. "% health" end), 1)
	p:Place(K.Toggle(p, "Death recap", "After you die or lose a duel: who dealt how much, the biggest hit, a tip or two. /sitrep recap shows the last one again.",
		get("log", "recapPopup"), set("log", "recapPopup")), 1)
	local tests = {
		{ "newContact", "New contact", function() ns.Fire("SR_NEW_CONTACT", { class = "MAGE", level = 60, lo = 20, hi = 28 }) end },
		{ "hvt", "HVT designated", function() ns.Fire("SR_HVT", { class = "PRIEST", name = "Aldwin" }) end },
		{ "targeted", "Targeted by a hostile", function() ns.Fire("SR_TARGETED", { class = "ROGUE", name = "Vex" }) end },
		{ "incoming", "Cast on you (not your target)", function()
			ns.Fire("SR_INCOMING", { player = true, class = "MAGE", caster = "Aldwin", name = "Frostbolt", unit = "test" .. GetTime() })
		end },
		{ "focusCast", "Your focus casts (not your target)", function()
			ns.IncomingUI.Alert({ focus = true, player = true, class = "PRIEST", caster = "Aldwin", name = "Greater Heal", tail = "kick!" })
		end },
		{ "spike", "Damage spike", function() ns.Fire("SR_SPIKE", 42) end },
		{ "closing", "Closing: in reach within 3 s", function() ns.Fire("SR_CLOSING", { class = "WARRIOR", ttr = 1.8 }) end },
		{ "ttl", "DEFEND (time-to-live)", function() ns.HUD.Banner("DEFEND  ·  TIME TO LIVE 3.1s", 1, 0.2, 0.55) end },
		{ "rare", "Rare mob on a plate", function() ns.HUD.RareSeen(nil, "test" .. GetTime(), "Silberzahn", 24) end },
		{ "healer", "Enemy found healing", function() ns.Fire("SR_HEALER", "test", { class = "PRIEST", name = "Aldwin" }) end },
		{ "layer", "Layer changed", function() ns.Fire("SR_LAYER", 4711, 815) end },
		{ "stealth", "Stealth near you: AoE", function() ns.Fire("SR_STEALTH", { class = "ROGUE", name = "Vex", key = "test" }, 12) end },
	}
	for _, t in ipairs(tests) do
		local row = CreateFrame("Frame", nil, p)
		row:SetHeight(24)
		local tg = K.Toggle(row, t[2], nil, get("alerts", t[1]), set("alerts", t[1]), p.colW - 70)
		tg:SetPoint("TOPLEFT")
		local b = K.Button(row, "Test", 56, 20, t[3])
		b:SetPoint("TOPRIGHT")
		function row:Refresh() tg:Refresh() end
		p:Place(row, 2, 6)
	end
	return p
end

---------------------------------------------------------------------------
-- 09 DISPLAY
---------------------------------------------------------------------------
local function buildDisplay()
	local p = newPage("Display", "Theme, which modules are on screen, and when.")
	local arrange = K.Button(p, "Round your character", 180, 22, function() ns.Layout.Gaze() end)
	arrange.fixedWidth = true
	p:Place(arrange, 1, 8)
	K.Tooltip(arrange, "Round your character", "You, your target, the cast alert and your emergency items close round your character, where your eyes are anyway. Out of combat.")
	local chips = K.Chips(p, get("hud", "accent"), set("hud", "accent"))
	chips.fixedWidth = true
	p:Place(chips, 1, 8)
	p.y[2] = p.y[1]
	p:Place(K.Slider(p, "Envelope range", 30, 45, 5, get("hud", "envelopeRange"), set("hud", "envelopeRange"), fy), 1)
	p:Place(K.Slider(p, "Envelope lanes", 3, 8, 1, get("hud", "envelopeLanes"), set("hud", "envelopeLanes")), 1)
	p:Place(K.Slider(p, "Threat board rows", 3, 10, 1, get("hud", "boardRows"), set("hud", "boardRows")), 1)
	p:Place(K.Slider(p, "Allies rows", 3, 10, 1, get("hud", "alliesRows"), set("hud", "alliesRows")), 1)
	p:Place(K.Toggle(p, "Envelope", nil, get("hud", "envelope"), set("hud", "envelope")), 2, 4)
	p:Place(K.Toggle(p, "Threat board", nil, get("hud", "board"), set("hud", "board")), 2, 4)
	p:Place(K.Toggle(p, "Engagement bar", nil, get("hud", "engage"), set("hud", "engage")), 2, 4)
	p:Place(K.Toggle(p, "Pressure gauge", nil, get("hud", "pressure"), set("hud", "pressure")), 2, 4)
	p:Place(K.Toggle(p, "Allies", nil, get("hud", "allies"), set("hud", "allies")), 2, 8)
	p:Place(K.Toggle(p, "Enemy health bars", nil, get("hud", "showHealth"), set("hud", "showHealth")), 1)
	-- auto-hide: fade a module out while no enemy player is in the picture
	local ah = K.Font(p, 10, C.dim, K.FONT, "")
	ah:SetText("ONLY WITH ENEMY PLAYERS AROUND")
	p:Place(ah, 2, 6)
	for _, m in ipairs({ { "envelope", "Envelope" }, { "board", "Threat board" }, { "engage", "Engagement bar" },
		{ "pressure", "Pressure gauge" }, { "allies", "Allies" }, { "player", "Player frame" } }) do
		p:Place(K.Toggle(p, m[2], nil, function() return ns.P.hud.autoHide[m[1]] end, function(v)
			ns.P.hud.autoHide[m[1]] = v
			ns.Changed("hud.autoHide")
		end), 2, 2)
	end
	return p
end

---------------------------------------------------------------------------
-- LAYOUT
---------------------------------------------------------------------------
-- Everything that can be placed, by group: { id, label, kind }. kind: "scale"
-- (hud.frameScale[id]), "map" (ui.mapSize), "chat" (ui.chatSize), "bar" (P.bars).
local HUD_ELEMENTS = { { "envelope", "Envelope" }, { "board", "Threat board" }, { "engage", "Engagement bar" },
	{ "pressure", "Pressure gauge" }, { "allies", "Allies" } }
local FRAME_ELEMENTS = { { "player", "Player frame" }, { "target", "Target frame" }, { "pet", "Pet frame" },
	{ "targetpet", "Target's pet" }, { "focus", "Focus frame" }, { "party", "Party frames" }, { "raid", "Raid frames" } }
local UI_ELEMENTS = { { "minimap", "Minimap", "map" }, { "chat", "Chat", "chat" }, { "bags", "Bag button" },
	{ "menu", "MENU button" }, { "quests", "Quest tracker" }, { "questArrow", "Quest arrow", "scale", true },
	{ "castAlert", "Cast alert" }, { "banner", "Alert banner" }, { "hoverInfo", "Hover info" }, { "emergency", "Emergency items" }, { "recap", "Death recap" } }

local function layoutElements()
	local out = { { header = "HUD" } }
	for _, e in ipairs(HUD_ELEMENTS) do out[#out + 1] = { e[1], e[2], kind = "scale" } end
	out[#out + 1] = { header = "UNIT FRAMES" }
	for _, e in ipairs(FRAME_ELEMENTS) do out[#out + 1] = { e[1], e[2], kind = "scale" } end
	out[#out + 1] = { header = "INTERFACE" }
	for _, e in ipairs(UI_ELEMENTS) do out[#out + 1] = { e[1], e[2], kind = e[3] or "scale", nobg = e[4] } end
	local bars = ns.BarLayout and ns.BarLayout.Options() or {}
	if #bars > 0 then
		out[#out + 1] = { header = "ACTION BARS" }
		for _, b in ipairs(bars) do out[#out + 1] = { "bar_" .. b[1], b[2], kind = "bar", bar = b[1] } end
	end
	return out
end

local HINT = {
	scale = "Drag it while the HUD is unlocked. Its size is multiplied with the HUD scale (HUD modules: its opacity with the HUD opacity too).",
	map = "Drag its handle while the HUD is unlocked; the grip in its corner resizes it too.",
	chat = "Size: the whole chat (windows, tabs, input). Drag its handle while the HUD is unlocked. Background 0 % = none.",
	bar = "Drag its handle while the HUD is unlocked. Changes made in combat wait for its end.",
}

local function buildLayout()
	local p = newPage("Layout", "Size and opacity of everything, and each element on its own: pick it, then adjust it.")
	-- everything at once
	-- (wide ranges: a client patch made the whole interface much smaller)
	p:Place(K.Slider(p, "HUD scale (everything)", 0.5, 3, 0.05, get("hud", "scale"), set("hud", "scale"), f2), 1)
	p:Place(K.Slider(p, "Console size", 0.6, 2.5, 0.05, get("hud", "consoleScale"), set("hud", "consoleScale"), fp), 1)
	p:Place(K.Slider(p, "HUD opacity", 0.3, 1, 0.05, get("hud", "alpha"), set("hud", "alpha"), fp), 1)
	p:Place(K.Toggle(p, "Unlocked: drag elements", "Every element shows a handle while unlocked. Also /sitrep unlock.",
		function() return not ns.P.hud.locked end, function(v)
			ns.P.hud.locked = not v
			ns.Changed("hud.locked")
		end), 1)
	local rp = K.Button(p, "Reset all positions", 160, 22, function()
		ns.P.hud.pos = {}
		ns.Changed("hud.pos")
	end)
	rp.fixedWidth = true
	p:Place(rp, 1)

	-- one element: pick it, the controls that apply to it appear under it
	local function current()
		local id = ns.P.ui.layoutEdit
		for _, e in ipairs(layoutElements()) do if not e.header and e[1] == id then return e end end
		return { "player", "Player frame", kind = "scale" }
	end
	local ctl = {}
	p.ctl = ctl
	local function scaleOf(e)
		if e.kind == "bar" then return ns.P.bars[e.bar].scale end
		return ns.P.hud.frameScale[e[1]] or 1
	end
	ctl.setSize = function(v)
		local e = current()
		if e.kind == "bar" then
			ns.P.bars[e.bar].scale = v
			ns.Changed("bars." .. e.bar)
		else
			ns.P.hud.frameScale[e[1]] = v
			ns.Changed("hud.frameScale")
		end
	end
	local function barSet(key)
		return function(v)
			local e = current()
			ns.P.bars[e.bar][key] = v
			ns.Changed("bars." .. e.bar)
		end
	end
	local function barGet(key) return function() local e = current() return e.bar and ns.P.bars[e.bar][key] or 0 end end
	ctl.size = K.Slider(p, "Size", 0.5, 4, 0.05, function() return scaleOf(current()) end, ctl.setSize, fp)
	ctl.setAlpha = function(v)
		local e = current()
		if e.kind == "bar" then
			ns.P.bars[e.bar].alpha = v
			ns.Changed("bars." .. e.bar)
		else
			ns.P.hud.frameAlpha[e[1]] = v
			ns.Changed("hud.frameAlpha")
		end
	end
	ctl.alpha = K.Slider(p, "Opacity", 0.1, 1, 0.05, function()
		local e = current()
		if e.kind == "bar" then return ns.P.bars[e.bar].alpha end
		return ns.P.hud.frameAlpha[e[1]] or 1
	end, ctl.setAlpha, fp)
	ctl.setBg = function(v)
		local e = current()
		if e.kind == "bar" then
			ns.P.bars[e.bar].bg = v
			ns.Changed("bars." .. e.bar)
		else
			ns.P.hud.bgAlpha[e[1]] = v
			ns.Changed("hud.bgAlpha")
		end
	end
	ctl.bg = K.Slider(p, "Background", 0, 1, 0.05, function()
		local e = current()
		if e.kind == "bar" then return ns.P.bars[e.bar].bg end
		return ns.P.hud.bgAlpha[e[1]] or 0
	end, ctl.setBg, fp)
	ctl.map = K.Slider(p, "Map size", ns.Minimap.MIN, ns.Minimap.MAX, 10, get("ui", "mapSize"), set("ui", "mapSize"),
		function(v) return v .. "px" end)
	ctl.chat = K.Slider(p, "Chat text size", 8, 30, 1, get("ui", "chatSize"), set("ui", "chatSize"), function(v) return v .. "pt" end)
	ctl.gap = K.Slider(p, "Gap between buttons", 0, 16, 1, barGet("gap"), barSet("gap"), function(v) return v .. "px" end)
	ctl.cols = K.Slider(p, "Buttons per row", 1, 12, 1, barGet("cols"), barSet("cols"), function(v) return tostring(v) end)
	ctl.reset = K.Button(p, "Reset its position", 160, 22, function()
		ns.P.hud.pos[current()[1]] = nil
		ns.Changed("hud.pos")
	end)
	ctl.reset.fixedWidth = true
	ctl.hint = K.Font(p, 10.5, C.dim)
	ctl.hint:SetJustifyH("LEFT")
	ctl.hint:SetHeight(44)
	local order = { "size", "map", "chat", "alpha", "bg", "gap", "cols", "reset", "hint" }
	local pick
	local function show(e)
		local kind = e.kind
		return {
			size = kind == "scale" or kind == "bar" or kind == "chat", map = kind == "map", chat = kind == "chat", alpha = true, bg = not e.nobg,
			gap = kind == "bar", cols = kind == "bar", reset = true, hint = true,
		}
	end
	-- stack the controls that apply under the picker
	local function restack()
		local e = current()
		local vis = show(e)
		ctl.hint:SetText(HINT[e.kind] or HINT.scale)
		local y = ctl.top
		for _, k in ipairs(order) do
			local w = ctl[k]
			w:SetShown(vis[k])
			if vis[k] then
				w:ClearAllPoints()
				w:SetPoint("TOPLEFT", p, "TOPLEFT", p.colW + 30, -y)
				y = y + w:GetHeight() + 10
				if w.Refresh then w:Refresh() end
			end
		end
		p.y[2] = y
	end
	ctl.Select = function(id)
		ns.P.ui.layoutEdit = id
		pick:Refresh()
		restack()
	end
	pick = K.Dropdown(p, "Element", layoutElements, get("ui", "layoutEdit"), ctl.Select)
	ctl.pick = pick
	p:Place(pick, 2)
	ctl.top = p.y[2]
	for _, k in ipairs(order) do p:Place(ctl[k], 2) end
	p.OnRefresh = restack
	restack()
	return p
end

---------------------------------------------------------------------------
-- 10 UNIT FRAMES
---------------------------------------------------------------------------
local function buildFrames()
	local p = newPage("Unit Frames", "Your frames, your target's, pets and party: what each shows, and how.")
	local function tog(col, label, key, desc)
		p:Place(K.Toggle(p, label, desc, get("frames", key), set("frames", key)), col, col == 1 and 6 or nil)
	end
	-- two short switches side by side
	local function pair(l1, k1, l2, k2)
		local half = (p.colW - 8) / 2
		local t1 = K.Toggle(p, l1, nil, get("frames", k1), set("frames", k1), half)
		t1.fixedWidth = true
		p:Place(t1, 1, 6)
		local t2 = K.Toggle(p, l2, nil, get("frames", k2), set("frames", k2), half)
		t2:SetPoint("LEFT", t1, "RIGHT", 8, 0)
		p.widgets[#p.widgets + 1] = t2
	end
	-- column 1: which frames, and what goes on them
	pair("Player frame", "player", "Target frame", "target")
	pair("Pet frame", "pet", "Target's pet", "targetPet")
	tog(1, "Focus frame", "focus", "Your focus in a glass pane: health, power, its cast (KICK for enemies), distance and what it has targeted. Shown while you have a focus.")
	pair("Party frames", "party", "Hide Blizzard's", "hideBlizzard")
	tog(1, "Hit and heal flash", "flash")
	tog(1, "Execute marker", "execute")
	tog(1, "Range strip on the target", "strip")
	tog(1, "Intel line on the target", "intel")
	tog(1, "Allies and healers on you (player frame)", "healersOnMe")
	tog(1, "Who is on your target (allies, healers)", "targetCounts")
	tog(1, "Mobs on you (player frame)", "mobsOnMe")
	tog(1, "Druids: mana in forms, shift cost", "druidMana")
	tog(1, "Your debuffs", "myDebuffs", "Outlined when you can remove them.")
	tog(1, "Raid frames", "raid", "In a raid, instead of the party frames: every member in a glass cell, one column per group. Class colour, dispel orbs, a coral rim on aggro, faded out of heal range.")
	tog(1, "Party: compact", "partyCompact", "Each member as a slim row: the name, a thin health bar and the class colour at the side. Debuffs, power, casts, distance and their target step aside (dispel orbs stay). Changes out of combat.")
	tog(1, "Party: each member's target", "partyTarget", "In each party frame, bottom right: what they have targeted (red hostile, yellow neutral, green friendly, mint your target too) and, from 2 on, how many of you are on it. Click it to target it as well.")
	tog(1, "Target's buffs and debuffs", "targetAuras", "Purgeable buffs outlined.")
	-- column 2: size and the highlights
	p:Place(K.Slider(p, "Frame width", 220, 640, 4, get("frames", "width"), set("frames", "width"), function(v) return v .. "px" end), 2)
	tog(2, "Under attack highlight", "hitGlow", "Red border while being attacked.")
	tog(2, "Dispel highlight", "dispelGlow", "Border when you can dispel something; on party frames also an orb right of the frame for each kind (poison, curse, magic, disease).")
	tog(2, "Cost preview on your power bar", "costPreview", "Hovered or casting spell: blue, red if short.")
	tog(2, "Damage and heal numbers on you", "popNumbers")
	tog(2, "Health bar for its target", "totHealth")
	p:Place(K.Slider(p, "Highlight its buffs lasting at most", 5, 30, 1, get("frames", "burstMax"), set("frames", "burstMax"), function(v) return v .. "s" end), 2)
	local rp = K.Button(p, "Reset frame positions", 160, 22, function()
		for _, id in ipairs({ "player", "target", "pet", "targetpet", "focus", "party", "raid" }) do ns.P.hud.pos[id] = nil end
		ns.Changed("frames.pos")
	end)
	rp.fixedWidth = true
	p:Place(rp, 2, 10)
	local legend = K.Font(p, 10.5, C.dim)
	legend:SetJustifyH("LEFT")
	legend:SetHeight(56)
	legend:SetText("|cff3399ffMagic|r  |cffa330c9Curse|r  |cff996600Disease|r  |cff00a000Poison|r  |cffff7319Enrage|r\nBright outline: you can remove it.  |cffff4026!|r big defensive.  |cffffc733Gold glow|r: a short buff (burst or defensive).\nIf the client locks aura data in combat, it colours the border and outline itself; a locked slot shows ?.")
	p:Place(legend, 2)
	return p
end

---------------------------------------------------------------------------
-- NAMEPLATES
---------------------------------------------------------------------------
local function buildPlates()
	local p = newPage("Nameplates", "Blizzard's nameplates in SITREP's look, friendly and hostile.")
	local function tog(col, label, key, desc)
		p:Place(K.Toggle(p, label, desc, get("plates", key), set("plates", key)), col)
	end
	tog(1, "SITREP nameplates", "enabled", "Off: Blizzard's own plates, untouched.")
	tog(1, "Enemy plates", "enemy", "Class colour for players; mobs red when on you, orange hostile, yellow neutral.")
	tog(1, "Friendly plates", "friendly", "Class colour. Friendly plates need Shift+V (or Options > Nameplates). Plates the client forbids to addons (often friendly plates in instances) stay Blizzard's.")
	p:Place(K.Slider(p, "Size of the nameplates", 0.5, 3, 0.05, get("plates", "scale"), set("plates", "scale"), fp), 1)
	local half = (p.colW - 12) / 2
	-- friendly players you have not targeted: see-through (not your group), and smaller in combat
	local fo = K.Slider(p, "Friends: opacity", 0.05, 1, 0.05, get("plates", "friendOpacity"), set("plates", "friendOpacity"), fp, half)
	fo.fixedWidth = true
	p:Place(fo, 1)
	local fcs = K.Slider(p, "Friends in combat", 0.3, 1, 0.05, get("plates", "friendCombatScale"), set("plates", "friendCombatScale"), fp, half)
	fcs:SetPoint("LEFT", fo, "RIGHT", 12, 0)
	p.widgets[#p.widgets + 1] = fcs
	-- mobs while enemy players are about (smaller, but not see-through like friends)
	p:Place(K.Slider(p, "Mobs near enemy players", 0.3, 1, 0.05, get("plates", "mobPvpScale"), set("plates", "mobPvpScale"), fp), 1)
	local sx = K.Slider(p, "Move right", -40, 40, 1, get("plates", "shiftX"), set("plates", "shiftX"), function(v) return v .. "px" end, half)
	sx.fixedWidth = true
	p:Place(sx, 1)
	local sy = K.Slider(p, "Move up", -30, 30, 1, get("plates", "shiftY"), set("plates", "shiftY"), function(v) return v .. "px" end, half)
	sy:SetPoint("LEFT", sx, "RIGHT", 12, 0)
	p.widgets[#p.widgets + 1] = sy
	tog(1, "Level in its danger colour", "level", "Grey, green, yellow, orange, red; ?? for far above you, + elite.")
	-- column 2: two short switches side by side
	local function pair(l1, k1, d1, l2, k2, d2)
		local hw = (p.colW - 8) / 2
		local t1 = K.Toggle(p, l1, d1, get("plates", k1), set("plates", k1), hw)
		t1.fixedWidth = true
		p:Place(t1, 2)
		local t2 = K.Toggle(p, l2, d2, get("plates", k2), set("plates", k2), hw)
		t2:SetPoint("TOPLEFT", t1, "TOPRIGHT", 8, 0)
		p.widgets[#p.widgets + 1] = t2
		-- the taller of the two decides where the next row starts
		local extra = (t2:GetHeight() or 0) - (t1:GetHeight() or 0)
		if extra > 0 then p.y[2] = p.y[2] + extra; p:Grow() end
	end
	pair("Tags", "tags", "YOU, HVT, HEALER, OOM on enemies; TARGETED n on friends; RARE, AGGRO on mobs.",
		"SITREP cast bar", "cast", "KICK window, grey when it cannot be interrupted.")
	pair("Quest mobs", "questMobs", "A gold ! with what is still open (3/8) on NPCs your quests need.",
		"Aggro radar", "aggroRadar", "AGGRO on hostile mobs you are about to pull: orange close to their aggro range, red inside it (about 20 yd, more for higher levels).")
	pair("Healers' mana", "enemyMana", "Enemy healers: a thin blue bar under their plate; OOM when nearly empty.",
		"Kill window", "killWindow", "Enemy players in your reach under 20 % health: a pulsing orange frame.")
	pair("Fade out of range", "rangeFade", "Enemies beyond your spells, friends beyond your heals.",
		"Distance on target", "dot", "Yards (exact for group members) and a marker: green 10, yellow 25, red in reach.")
	pair("Dispel orbs", "borders", "Friendly plates: an orb left of the bar in the colour of each debuff you can dispel.",
		"Heals on the bar", "heals", "Heals on their way, on the health bar.")
	tog(2, "Auras over the name", "auras", "The game's own auras on each plate (your debuffs, important buffs, crowd control) in one row over the name, in SITREP's look.")
	p:Place(K.Slider(p, "Aura size", 0.5, 2, 0.05, get("plates", "auraScale"), set("plates", "auraScale"), fp), 2)
	tog(2, "Combo points on your target", "combo", "Rogues and druids: your combo points as pips under your target's plate.")
	tog(2, "Enemy players: coral ring", "foeRing", "A solid coral ring round every enemy player's bar: the one red frame on the plates.")
	tog(2, "Your focus: magenta ring", "focusRing", "Your focus's plate: a magenta ring round the bar (the colour of your focus everywhere: its frame, its cast alerts).")
	tog(2, "Your group: blue ring", "mateRing", "Your party and raid members: a ring in party-chat blue round the bar and their name in the same blue, so they stand out among other friends.")
	tog(2, "Group focus", "groupFocus", "An enemy your group is on: a mint ring round its plate, wider the more of you, and how many beside it (filled: the one most of you are on).")
	tog(2, "Friendly zen", "friendZen", "Only enemies, your group and your target keep their bar. Every other friendly plate: the name over a thin health line.")
	tog(2, "NPCs: icon and title", "npcIcons", "Friendly NPCs (and neutral traders) without a bar: the name, its title under it and an icon for what it does (repair, inn, flight, bank...). Turn on friendly NPC plates in the game's options to see them.")
	tog(2, "Casters at you: red box", "incoming", "A pulsing red box round the plate of a hostile casting at you. Click the plate to target it.")
	tog(2, "Hover info instead of the tooltip", "hoverInfo", "Race and class, guild, quest objectives, how long a mob is up, while the mouse is over a unit (Shift: Blizzard's tooltip).")
	tog(2, "Legend in the hover info", "hoverLegend", "Every mark the hovered unit's plate shows (rings, orbs, tags), with what it means.")
	p:Place(K.Dropdown(p, "Hover info shows", { { "frame", "In a window of its own (Layout)" },
		{ "mouse", "Next to the mouse (stays where it opened)" }, { "plate", "On the nameplate" } },
		get("plates", "hoverWhere"), set("plates", "hoverWhere")), 1)
	return p
end

---------------------------------------------------------------------------
-- 12b INTERFACE
---------------------------------------------------------------------------
local function buildInterface()
	local p = newPage("Interface", "The game's own minimap, experience, bags and chat in SITREP's look.")
	local function tog(col, label, key, desc)
		p:Place(K.Toggle(p, label, desc, get("ui", key), set("ui", key)), col)
	end
	tog(1, "Square minimap", "minimap", "Framed like the HUD, zone above it in its PvP colour, zoom on the mouse wheel.")
	p:Place(K.Slider(p, "Minimap size", ns.Minimap.MIN, ns.Minimap.MAX, 10, get("ui", "mapSize"), set("ui", "mapSize"), function(v) return v .. "px" end), 1)
	tog(1, "Coordinates on the minimap", "mapCoords", "Your position on the zone map, bottom right.")
	tog(1, "Experience on your player frame", "xp", "A thin line along its bottom edge, rested ahead of it. Hover it for numbers.")
	tog(1, "Hide Blizzard's experience bar", "hideBlizzXP", "With it goes the reputation bar that shares its strip.")
	p:Place(K.Dropdown(p, "Chat folds", { { "auto", "Towards where it is (top half: up)" }, { "up", "Up (lines at its top)" },
		{ "down", "Down (lines at its bottom)" } }, get("ui", "chatFoldTo"), set("ui", "chatFoldTo")), 1)
	tog(2, "Bag button", "bags", "Free slots at a glance; click opens your bags. Move it like the HUD (unlock in Layout).")
	tog(2, "Hide Blizzard's bag bar", "hideBagBar", "Right-click the bag button to show it for swapping bags.")
	tog(2, "SITREP chat", "chat", "On a glass pane; tabs, input line and buttons show with the mouse or while you type. Its pane: Layout, Chat.")
	tog(2, "Last 3 lines when folded", "chatPreview", "The last 3 lines the chat tab you have open showed (everything it shows); links in them work.")
	p:Place(K.Slider(p, "Folded lines fade after", 5, 120, 5, get("ui", "chatFade"), set("ui", "chatFade"), fs), 2)
	tog(2, "Chat folded away", "chatCollapsed", "Tabs with unread messages stay (with how many); Enter unfolds it while you type. The arrow by the tabs, a key binding or /sitrep chat.")
	p:Place(K.Slider(p, "Chat text size", 8, 30, 1, get("ui", "chatSize"), set("ui", "chatSize"), function(v) return v .. "pt" end), 2)
	local note = K.Font(p, 10.5, C.dim)
	note:SetJustifyH("LEFT")
	note:SetHeight(44)
	note:SetText("The minimap keeps its place from Edit Mode. Switching a part off restores it; /reload restores every detail.")
	p:Place(note, 2)
	return p
end

---------------------------------------------------------------------------
-- 12c QUESTS
---------------------------------------------------------------------------
local SORTS = { { "distance", "Nearest first" }, { "zone", "Your zone first" }, { "level", "Lowest level first" } }
local function buildQuests()
	local p = newPage("Quests", "Your quests nearest first, and an arrow to the one you choose.")
	local function tog(col, label, key, desc)
		p:Place(K.Toggle(p, label, desc, get("quests", key), set("quests", key)), col)
	end
	tog(1, "SITREP quest tracker", "tracker", "Click a quest to navigate to it, right-click for the quest log. Move it like the HUD.")
	tog(1, "Hide Blizzard's quest tracker", "hideBlizz", "While SITREP's is on.")
	tog(1, "Only the quest you navigate to", "collapsed", "Folds the tracker to it (none chosen: the nearest). Click the tracker's header, or a key binding, to switch.")
	p:Place(K.Dropdown(p, "Order", SORTS, get("quests", "sort"), set("quests", "sort")), 1)
	p:Place(K.Slider(p, "Quests shown", 3, 15, 1, get("quests", "rows"), set("quests", "rows"), function(v) return tostring(v) end), 1)
	tog(2, "Navigation arrow", "arrow", "Turns toward the chosen quest as you turn, with the distance. Right-click it to stop.")
	tog(2, "Navigate to the nearest quest by itself", "autoNearest", "When none is chosen. A key binding does it on demand.")
	tog(2, "Learn quest places", "learn", "Where your objective counters go up, and where you accept quests.")
	tog(2, "Learned paths", "trails", "Remembers where you walk (all your characters) and leads the arrow along those ways when the straight line is unknown ground: round mountains, into caves you have been in.")
	tog(2, "Flight paths", "travel", "When flying is clearly quicker, the arrow leads to the flight master and says where to fly. Learns the flight points you know and how long flights take.")
	tog(2, "Quest on the world map", "questMap", "The quest you navigate to: where its mobs spawn (coral: to kill, gold: they drop its items), how fast they come back, how many kills an item takes, and where its counters went up.")
	tog(2, "Other quests on the way", "nearby", "A plate whose mob another quest still needs flashes gold; the quest arrow offers a quest with little detour on your way (click: go there); quests close by get a mint bar in the tracker.")
	tog(2, "World map: flight points", "mapFlights", "Every flight point of your faction on the world map; dim where this character has not been yet. Its name and how far it is when the mouse is on it.")
	tog(2, "World map: walked ways (debug)", "mapTrails", "The ground the arrow knows from your walks (all characters): mint walked, cyan swum, orange rough terrain, dark red no way through, lavender inside, doors yellow. On the map: a button, and a brush to draw ways, water and terrain by hand.")
	tog(2, "Worth it? (XP a minute)", "value", "Each quest's experience per minute from the way, what is left to do and your own pace, against killing mobs: green worth it, grey not.")
	local note = K.Font(p, 10.5, C.dim)
	note:SetJustifyH("LEFT")
	note:SetHeight(70)
	note:SetText("Places: the game's own quest position where it gives one; else where you made progress (~ in front of the yards), and for finished quests where you accepted them. /sitrep questprobe shows what this client tells.")
	p:Place(note, 2)
	return p
end

---------------------------------------------------------------------------
-- 12d BARS & MENU
---------------------------------------------------------------------------
local function buildBars()
	local p = newPage("Bars & Menu", "Blizzard's action bars in SITREP's look, and its micro buttons folded into one MENU button.")
	local function tog(col, label, key, desc)
		p:Place(K.Toggle(p, label, desc, get("ui", key), set("ui", key)), col)
	end
	tog(1, "Action bar skin", "bars", "Square icons on dark tiles, thin borders, flat highlights, the HUD font. Off: /reload.")
	tog(1, "Remove the bar art", "barArt", "Gryphons, bar backgrounds and the page arrows (paging by key still works).")
	tog(1, "Red when out of range", "barRange", "A red veil over a button whose spell does not reach your target.")
	tog(1, "Macro names", "barMacroNames", "The name of a macro under its icon.")
	tog(1, "Hide empty slots", "barHideEmpty", "They show while you drag a spell, item or macro, so you can drop it there.")
	tog(1, "MENU button", "menu", "Character, spellbook, talents, quest log, map and more in one list; works in combat.")
	tog(1, "Hide Blizzard's micro buttons", "hideMicro", "While the MENU button is on.")
	-- layout: one bar at a time
	tog(2, "Move, size and space the bars", "barLayout", "Unlock the HUD (Layout page) to drag a bar. Changes made in combat wait for its end.")
	local function bar() return ns.P.bars[ns.P.ui.barEdit] or ns.P.bars.main end
	local function barSet(key)
		return function(v)
			bar()[key] = v
			ns.Changed("bars." .. ns.P.ui.barEdit)
		end
	end
	local sliders = {}
	p:Place(K.Dropdown(p, "Bar", ns.BarLayout.Options(), get("ui", "barEdit"), function(v)
		ns.P.ui.barEdit = v
		for _, w in ipairs(sliders) do w:Refresh() end
	end), 2)
	sliders[1] = K.Slider(p, "Size", 0.5, 4, 0.05, function() return bar().scale end, barSet("scale"), fp)
	sliders[2] = K.Slider(p, "Gap between buttons", 0, 16, 1, function() return bar().gap end, barSet("gap"), function(v) return v .. "px" end)
	sliders[3] = K.Slider(p, "Buttons per row", 1, 12, 1, function() return bar().cols end, barSet("cols"), function(v) return tostring(v) end)
	for _, w in ipairs(sliders) do p:Place(w, 2) end
	return p
end

---------------------------------------------------------------------------

Cfg.AddPage(60, "pressure", "Pressure", buildPressure)
Cfg.AddPage(70, "comms", "Comms", buildComms)
Cfg.AddPage(80, "alerts", "Alerts", buildAlerts)
Cfg.AddPage(90, "display", "Display", buildDisplay)
Cfg.AddPage(100, "layout", "Layout", buildLayout)
Cfg.AddPage(110, "frames", "Unit Frames", buildFrames)
Cfg.AddPage(120, "plates", "Nameplates", buildPlates)
Cfg.AddPage(125, "interface", "Interface", buildInterface)
Cfg.AddPage(127, "quests", "Quests", buildQuests)
Cfg.AddPage(128, "bars", "Bars & Menu", buildBars)
