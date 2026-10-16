-- SITREP · Flight recorder
-- Two recorders. The automatic one keeps the last few snapshots in SITREP_DB.diag
-- whenever something is on screen, so any /reload or logout leaves evidence on disk.
-- /sitrep debug records what every stage of the pipeline sees for 15 seconds:
-- each nameplate's raw answers (secret or not), the hostility verdict, range,
-- closure, what the envelope drew, and any internal errors. It prints a summary and
-- stores the samples in SITREP_DB.debug, which the client writes to
-- WTF/Account/<account>/SavedVariables/SITREP.lua on /reload or logout.

local ADDON, ns = ...
local format = string.format

local Dbg = {}
ns.Debug = Dbg

-- "true" / "false" / "nil" / "SECRET" / "ERR" / value, for any call; never throws.
local function probe(fn, ...)
	if type(fn) ~= "function" then return "n/a" end
	local ok, v = pcall(fn, ...)
	if not ok then return "ERR:" .. tostring(v):sub(1, 80) end
	if ns.isSecret(v) then return "SECRET" end
	if v == nil then return "nil" end
	return tostring(v)
end

local function plateInfo(unit)
	if not C_NamePlate then return "no C_NamePlate" end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok then return "ERR:" .. tostring(plate):sub(1, 80) end
	if ns.isSecret(plate) then return "SECRET" end
	if not plate then return "nil" end
	if plate.IsForbidden and plate:IsForbidden() then return "forbidden" end
	return "plate"
end

local function sampleUnit(unit, S)
	local lo, hi = S.MeasureRange(unit, nil)
	return {
		unit = unit,
		exists = probe(UnitExists, unit),
		isPlayer = probe(UnitIsPlayer, unit),
		canAttack = probe(UnitCanAttack, "player", unit),
		isEnemy = probe(UnitIsEnemy, "player", unit),
		isFriend = probe(UnitIsFriend, "player", unit),
		faction = probe(UnitFactionGroup, unit),
		dead = probe(UnitIsDeadOrGhost, unit),
		guid = probe(UnitGUID, unit),
		name = probe(GetUnitName, unit, false),
		class = probe(function(u) return select(2, UnitClass(u)) end, unit),
		level = probe(UnitLevel, unit),
		key = tostring(S.UnitKey(unit)),
		hostile = tostring(S.IsHostile(unit)),
		range = format("%s-%s", tostring(lo), tostring(hi)),
		plate = plateInfo(unit),
	}
end

local rec, ticks
local function snapshot(start, maxUnits)
	local S, H = ns.Sensors, ns.HUD
	local me = S.self
	local env = H and H.modules and H.modules.envelope
	local shownLanes = 0
	if env and env.lanes then
		for _, l in ipairs(env.lanes) do if l:IsShown() then shownLanes = shownLanes + 1 end end
	end
	local s = {
		t = format("%.1f", GetTime() - start),
		position = probe(function() local x, y = UnitPosition("player"); return x and format("%.1f,%.1f", x, y) end),
		myFaction = tostring(me.faction),
		platesSeen = 0,
		contacts = 0, live = 0,
		envelopeShown = env and tostring(env:IsShown()) or "no envelope",
		lanesShown = shownLanes,
		myReach = S.myReach,
		hudHidden = tostring(ns.hudHidden),
		enabled = tostring(ns.P.enabled),
		ticks = Dbg.counts.tick, pictures = Dbg.counts.picture, -- is the pipeline running at all?
		plateEvents = S.stats.plateEvents, swept = S.stats.swept,
		forbiddenEventKnown = tostring(ns.knownEvents.FORBIDDEN_NAME_PLATE_UNIT_ADDED),
		allies = ns.Allies and format("%d tracked, group positions exact %d, withheld %d", #ns.Allies.list, ns.Allies.stats.exact, ns.Allies.stats.noExact) or "n/a",
		auras = ns.Auras and format("ids %d/%d locked, data plain %d cached %d locked %d, timer obj %d plain %d, colour client %d plain %d",
			ns.Auras.stats.idsPlain, ns.Auras.stats.idsLocked, ns.Auras.stats.dataPlain, ns.Auras.stats.dataCached, ns.Auras.stats.dataLocked,
			ns.Auras.stats.timerObject, ns.Auras.stats.timerPlain, ns.Auras.stats.colorClient, ns.Auras.stats.colorPlain) or "n/a",
		units = {}, contactList = {},
	}
	for unit in pairs(S._plates) do
		s.platesSeen = s.platesSeen + 1
		if #s.units < maxUnits then s.units[#s.units + 1] = sampleUnit(unit, S) end
	end
	if ns.read(UnitExists, "target") then s.target = sampleUnit("target", S) end
	for _, c in ipairs(S.list) do
		s.contacts = s.contacts + 1
		if c.live then s.live = s.live + 1 end
		if #s.contactList < 5 then
			s.contactList[#s.contactList + 1] = format("%s %s src=%s live=%s lo=%s hi=%s closing=%s range=%s",
				tostring(c.class), tostring(c.level), tostring(c.source), tostring(c.live), tostring(c.lo), tostring(c.hi),
				c.closing and format("%.1f", c.closing) or "nil", c.range and format("%.0f", c.range) or "nil")
		end
	end
	return s
end

local function sample()
	local s = snapshot(rec.start, 6)
	rec.samples[#rec.samples + 1] = s
	return s
end

local function finish()
	rec.errors = {}
	for e, n in pairs(ns.errorCounts) do rec.errors[#rec.errors + 1] = n .. "x " .. e end
	rec.events = {}
	for e, ok in pairs(ns.knownEvents) do if not ok then rec.events[#rec.events + 1] = e .. " (unknown to client)" end end
	rec.cvars = {
		nameplateShowEnemies = probe(GetCVar, "nameplateShowEnemies"),
		nameplateShowAll = probe(GetCVar, "nameplateShowAll"),
		nameplateMaxDistance = probe(GetCVar, "nameplateMaxDistance"),
		cameraFov = probe(GetCVar, "cameraFov"),
	}
	SITREP_DB.debug = rec
	local last = rec.samples[#rec.samples] or {}
	ns.print("debug: done. %d samples. Last: plates %s, contacts %s (live %s), envelope lanes %s.",
		#rec.samples, tostring(last.platesSeen), tostring(last.contacts), tostring(last.live), tostring(last.lanesShown))
	if #rec.errors > 0 then ns.print("debug: %d internal error(s), first: %s", #rec.errors, rec.errors[1]) end
	ns.print("debug: type |cffffff00/reload|r now so the client writes the recording to disk.")
	rec, ticks = nil, nil
end

function Dbg.Start()
	if rec then ns.print("debug: already recording.") return end
	local version, build, _, iface = GetBuildInfo()
	rec = { start = GetTime(), client = format("%s.%s (%s)", tostring(version), tostring(build), tostring(iface)),
		addon = ns.VERSION, npcs = tostring(ns.P.sensors.npcs), samples = {} }
	ticks = 0
	ns.print("debug: recording for 15 seconds. Stand where enemies are visible (nameplates on) and target one.")
	local ok, s = pcall(sample)
	if ok then
		ns.print("debug: now: %d plates, %d contacts, %d envelope lanes, position %s.",
			s.platesSeen, s.contacts, s.lanesShown, s.position)
	else
		rec.sampleError = tostring(s)
		ns.print("debug: sampling failed: %s", tostring(s))
	end
	C_Timer.NewTicker(1, Dbg.Step, 15)
end

-- The recorder runs on its own timer so it still reports if the pipeline stalls.
Dbg.counts = { tick = 0, picture = 0 }
ns.On("SR_TICK", function() Dbg.counts.tick = Dbg.counts.tick + 1 end)
ns.On("SR_PICTURE", function() Dbg.counts.picture = Dbg.counts.picture + 1 end)

-- Automatic recorder: a snapshot every 5 s while contacts, plates or NPC dots exist.
local lastAuto = 0
ns.On("SR_PICTURE", function(_, list)
	local now = GetTime()
	if now - lastAuto < 5 then return end
	if #list == 0 and next(ns.Sensors._plates) == nil then return end
	lastAuto = now
	local ok, s = pcall(snapshot, now, 3)
	local d = SITREP_DB.diag
	if not d then
		local version, build, _, iface = GetBuildInfo()
		d = { client = format("%s.%s (%s)", tostring(version), tostring(build), tostring(iface)), samples = {} }
		SITREP_DB.diag = d
	end
	d.addon, d.updated = ns.VERSION, date and date("%Y-%m-%d %H:%M:%S") or tostring(now)
	d.locale = GetLocale and GetLocale() or "?"
	table.insert(d.samples, 1, ok and s or { error = tostring(s) })
	for i = #d.samples, 5, -1 do d.samples[i] = nil end
end)

function Dbg.Step()
	if not rec then return end
	ticks = ticks + 1
	local ok, err = pcall(sample)
	if not ok then rec.sampleError = tostring(err) end
	if ticks >= 15 then finish() end
end

---------------------------------------------------------------------------
-- /sitrep plateprobe: can SITREP restyle nameplates on this client?
-- For each plate on screen (friendly and hostile) it tries, and records:
--   plate      what GetNamePlateForUnit hands out (plate / forbidden / nil)
--   frame      whether Blizzard's UnitFrame and its health bar can be found
--   anchor     a SITREP marker anchored above the plate
--   child      a SITREP frame parented to the plate
--   colour     the health bar recoloured in SITREP's green (read back)
--   texture    the health bar given SITREP's flat texture
--   name       whether the plate's name text is readable
-- The marker and the restyle stay on screen for 6 s so you can see them, then
-- everything is put back; "plateprobe_after" says whether the client had
-- already overwritten the colour by then (a restyle would then need a hook),
-- and how often Blizzard's nameplate update functions ran.
-- Run out of combat, it arms one more run 2 s into your next fight.
---------------------------------------------------------------------------
local PROBE_SHOW = 6
local probeArmed, probeHooked = false, false
local hookCalls = {}

local function count(name) return function() hookCalls[name] = (hookCalls[name] or 0) + 1 end end

local function hookBlizzard()
	if probeHooked then return end
	probeHooked = true
	local hooks = {}
	for _, fn in ipairs({ "CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateName", "CompactUnitFrame_UpdateHealthBorder" }) do
		if type(_G[fn]) == "function" then
			hooks[#hooks + 1] = fn .. (pcall(hooksecurefunc, fn, count(fn)) and "" or " (hook failed)")
		end
	end
	local drv = _G.NamePlateDriverFrame
	if drv and type(drv.OnNamePlateAdded) == "function" then
		hooks[#hooks + 1] = "NamePlateDriverFrame.OnNamePlateAdded" .. (pcall(hooksecurefunc, drv, "OnNamePlateAdded", count("OnNamePlateAdded")) and "" or " (hook failed)")
	end
	return hooks
end

local function try(fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return false, "ERR:" .. tostring(a):gsub("\n.*", ""):sub(1, 70) end
	return true, a, b, c
end

local function healthBarOf(plate)
	local ok, uf = pcall(function() return plate.UnitFrame end)
	if not ok then return nil, nil, "ERR reading UnitFrame" end
	if not uf then return nil, nil, "no UnitFrame" end
	for _, path in ipairs({ "healthBar", "HealthBarsContainer.healthBar", "HealthBar" }) do
		local okP, hb = pcall(function()
			local t = uf
			for k in path:gmatch("[^%.]+") do t = t and t[k] end
			return t
		end)
		if okP and type(hb) == "table" and hb.SetStatusBarColor then return uf, hb, path end
	end
	return uf, nil, "no health bar found"
end

local markers = {}
local function marker(i)
	local m = markers[i]
	if not m then
		m = CreateFrame("Frame", nil, UIParent)
		m:SetSize(46, 14)
		m:SetFrameStrata("HIGH")
		m.bg = m:CreateTexture(nil, "BACKGROUND")
		m.bg:SetAllPoints()
		m.bg:SetColorTexture(0.03, 0.05, 0.05, 0.85)
		if ns.Kit then ns.Kit.Border(m, { 0.36, 1, 0.55, 1 }, 1) end
		m.text = m:CreateFontString(nil, "OVERLAY")
		m.text:SetFont(ns.Kit and ns.Kit.FONT or "Fonts\\FRIZQT__.TTF", 9, "")
		m.text:SetPoint("CENTER")
		m.text:SetTextColor(0.36, 1, 0.55, 1)
		m.text:SetText("SITREP")
		markers[i] = m
	end
	return m
end

local restore = {}
local function probePlate(i, unit)
	local friend = ns.read(UnitIsFriend, "player", unit)
	local isPlayer = ns.read(UnitIsPlayer, unit)
	local who = format("%s %s %s", unit, friend == true and "FRIEND" or friend == false and "FOE" or "?", isPlayer == true and "player" or isPlayer == false and "npc" or "?")
	local r = { who }
	local ok, plate = try(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok then r[#r + 1] = "plate " .. plate; return table.concat(r, "  ") end
	if not plate then
		-- forbidden plates are only handed out on request, and then unusable
		local okF, fp = try(C_NamePlate.GetNamePlateForUnit, unit, true)
		r[#r + 1] = okF and fp and "plate=forbidden(only with includeForbidden)" or "plate=nil"
		return table.concat(r, "  ")
	end
	local forbidden = plate.IsForbidden and select(2, try(plate.IsForbidden, plate))
	if forbidden == true then r[#r + 1] = "plate=FORBIDDEN"; return table.concat(r, "  ") end
	r[#r + 1] = "plate=ok"

	-- our own marker above it
	local m = marker(i)
	m:ClearAllPoints()
	local okA, errA = try(m.SetPoint, m, "BOTTOM", plate, "TOP", 0, 2)
	m:SetShown(okA)
	r[#r + 1] = "anchor=" .. (okA and "ok" or errA)

	-- a frame of ours inside the plate
	local okC, child = try(CreateFrame, "Frame", nil, plate)
	r[#r + 1] = "child=" .. (okC and "ok" or child)
	if okC and child then child:Hide() end

	-- Blizzard's health bar: our colour and texture
	local uf, hb, path = healthBarOf(plate)
	if not hb then r[#r + 1] = "healthbar=" .. tostring(path) else
		r[#r + 1] = "healthbar=" .. path
		local okG, cr, cg, cb = try(hb.GetStatusBarColor, hb)
		local okS, errS = try(hb.SetStatusBarColor, hb, 0.36, 1, 0.55)
		local okR, rr, rg = try(hb.GetStatusBarColor, hb)
		local took = okR and not ns.isSecret(rr) and type(rr) == "number" and math.abs(rr - 0.36) < 0.02 and math.abs(rg - 1) < 0.02
		r[#r + 1] = "colour=" .. (okS and (took and "ok" or "set, not read back") or errS)
		local okT, oldTex = try(function() return hb:GetStatusBarTexture():GetTexture() end)
		local okW, errW = try(hb.SetStatusBarTexture, hb, ns.Kit and ns.Kit.WHITE or "Interface\\Buttons\\WHITE8X8")
		r[#r + 1] = "texture=" .. (okW and "ok" or errW)
		restore[#restore + 1] = { hb = hb, color = okG and not ns.isSecret(cr) and cr and { cr, cg, cb }, tex = okT and not ns.isSecret(oldTex) and oldTex, unit = unit }
	end
	if uf then
		local okN, nm = try(function() return uf.name and uf.name:GetText() end)
		r[#r + 1] = "name=" .. (not okN and nm or nm == nil and "none" or ns.isSecret(nm) and "SECRET" or "readable")
	end
	return table.concat(r, "  ")
end

local function plateUnits()
	local units = {}
	for u in pairs(ns.Sensors._plates or {}) do units[#units + 1] = u end
	table.sort(units)
	return units
end

function Dbg.PlateProbe(name)
	name = name or (InCombatLockdown() and "plateprobe_combat" or "plateprobe")
	wipe(restore)
	local hooks
	ns.Capture(name, function()
		local inst, kind = ns.read(IsInInstance)
		ns.print("plate probe (%s): combat %s, instance %s", name, tostring(InCombatLockdown()), inst and tostring(kind) or "no")
		local cv = function(k) local v = ns.read(GetCVar, k); return v == nil and "?" or tostring(v) end
		ns.print("cvars: enemies %s, friends %s, friendly NPCs %s", cv("nameplateShowEnemies"), cv("nameplateShowFriends"), cv("nameplateShowFriendlyNPCs"))
		local api = {}
		for _, k in ipairs({ "GetNamePlates", "SetNamePlateFriendlySize", "SetNamePlateEnemySize", "SetNamePlateFriendlyClickThrough" }) do
			api[#api + 1] = k .. "=" .. (C_NamePlate and type(C_NamePlate[k]) == "function" and "yes" or "no")
		end
		ns.print("api: %s, driver %s", table.concat(api, " "), _G.NamePlateDriverFrame and "yes" or "no")
		if C_NamePlate and C_NamePlate.GetNamePlates then
			local okA, all = try(C_NamePlate.GetNamePlates)
			local okF, withF = try(C_NamePlate.GetNamePlates, true)
			ns.print("plates: %s usable, %s with forbidden", okA and type(all) == "table" and #all or "?", okF and type(withF) == "table" and #withF or "?")
		end
		hooks = hookBlizzard()
		if hooks then ns.print("hooks: %s", #hooks > 0 and table.concat(hooks, ", ") or "none of Blizzard's nameplate functions exist") end
		wipe(hookCalls)
		local units, friends = plateUnits(), 0
		if #units == 0 then ns.print("no nameplates on screen: stand near players or mobs and run it again") end
		for i, u in ipairs(units) do
			if i > 10 then ns.print("(%d more plates not probed)", #units - 10) break end
			if ns.read(UnitIsFriend, "player", u) == true then friends = friends + 1 end
			ns.print("%s", probePlate(i, u))
		end
		if friends == 0 then ns.print("no friendly plates: turn on friendly nameplates (Shift+V) near other players to test them") end
	end)
	ns.print("SITREP markers and green bars show for %d s; then /reload writes the report.", PROBE_SHOW)
	if not InCombatLockdown() and not probeArmed then
		probeArmed = true
		ns.print("armed: it runs once more 2 s into your next fight.")
	end
	C_Timer.After(PROBE_SHOW, function()
		ns.Capture(name .. "_after", function()
			for _, x in ipairs(restore) do
				local okR, rr, rg = try(x.hb.GetStatusBarColor, x.hb)
				local kept = okR and not ns.isSecret(rr) and type(rr) == "number" and math.abs(rr - 0.36) < 0.02 and math.abs(rg - 1) < 0.02
				ns.print("%s: our colour %s after %d s", x.unit, kept and "still there" or "overwritten by the client", PROBE_SHOW)
				if x.color then try(x.hb.SetStatusBarColor, x.hb, x.color[1], x.color[2], x.color[3]) end
				if x.tex then try(x.hb.SetStatusBarTexture, x.hb, x.tex) end
			end
			local calls = {}
			for k, n in pairs(hookCalls) do calls[#calls + 1] = k .. " " .. n .. "x" end
			table.sort(calls)
			ns.print("Blizzard updates in %d s: %s", PROBE_SHOW, #calls > 0 and table.concat(calls, ", ") or "none seen")
			for _, m in ipairs(markers) do m:Hide() end
		end)
	end)
end

ns.On("PLAYER_REGEN_DISABLED", function()
	if not probeArmed then return end
	probeArmed = false
	C_Timer.After(2, function()
		if InCombatLockdown() then Dbg.PlateProbe("plateprobe_combat") end
	end)
end)

---------------------------------------------------------------------------
-- /sitrep platedump: the parts of one nameplate (your target's, else the first
-- on screen): every keyed frame, texture and text on its UnitFrame, two levels
-- deep, with type, shown, alpha, layer and texture or text. Tells which of
-- Blizzard's pieces SITREP's look still has to hide on this client.
---------------------------------------------------------------------------
local function describe(v)
	local okT, ot = pcall(v.GetObjectType, v)
	if not okT then return nil end
	local bits = { tostring(ot) }
	local okS, shown = pcall(v.IsShown, v)
	bits[#bits + 1] = okS and (shown and "shown" or "hidden") or "?"
	local okA, a = pcall(v.GetAlpha, v)
	if okA and not ns.isSecret(a) and type(a) == "number" then bits[#bits + 1] = format("a%.2f", a) end
	if ot == "Texture" then
		local okL, layer, sub = pcall(v.GetDrawLayer, v)
		if okL then bits[#bits + 1] = tostring(layer) .. "/" .. tostring(sub) end
		local okAt, atlas = pcall(v.GetAtlas, v)
		local okTx, tex = pcall(v.GetTexture, v)
		local t = okAt and atlas or okTx and tex
		if t and not ns.isSecret(t) then bits[#bits + 1] = tostring(t) end
	elseif ot == "FontString" then
		local okX, txt = pcall(v.GetText, v)
		bits[#bits + 1] = okX and (ns.isSecret(txt) and "SECRET" or format("%q", tostring(txt))) or "?"
	end
	return table.concat(bits, " ")
end

local function walk(t, path, depth, seen)
	local keys = {}
	local ok = pcall(function() for k, v in pairs(t) do if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end end end)
	if not ok then ns.print("%s: cannot be read", path) return end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = t[k]
		if not seen[v] then
			seen[v] = true
			local d = describe(v)
			if d then
				ns.print("%s.%s  %s", path, k, d)
				-- the health bar is followed deeper: its border and background live in there
				local deep = (path .. "." .. k):find("ealthBar") and 4 or 2
				if depth < deep and not d:find("^Texture") and not d:find("^FontString") and not d:find("^Animation") then walk(v, path .. "." .. k, depth + 1, seen) end
			end
		end
	end
	-- a status bar's fill, and the masks on it
	local okF, fill = pcall(function() return t:GetStatusBarTexture() end)
	if okF and type(fill) == "table" then
		local okN, n = pcall(fill.GetNumMaskTextures, fill)
		ns.print("%s:fill  %s  masks %s", path, describe(fill) or "?", okN and tostring(n) or "?")
		seen[fill] = true
	end
	-- regions without a key (textures drawn straight on the frame)
	local okR, regions = pcall(function() return { t:GetRegions() } end)
	if okR and regions then
		local n = 0
		for _, r in ipairs(regions) do
			if not seen[r] then
				seen[r] = true
				n = n + 1
				ns.print("%s:region%d  %s", path, n, describe(r) or "?")
			end
		end
	end
end

-- /sitrep uidump: which of Blizzard's interface frames this client has (the
-- minimap decorations, experience bars, bag bar and chat parts SITREP restyles).
function Dbg.UIDump()
	ns.Capture("uidump", function()
		local function has(name) return type(_G[name]) == "table" end
		local function list(title, names)
			local yes, no = {}, {}
			for _, n in ipairs(names) do if has(n) then yes[#yes + 1] = n else no[#no + 1] = n end end
			ns.print("%s: %s | missing: %s", title, #yes > 0 and table.concat(yes, " ") or "-", #no > 0 and table.concat(no, " ") or "-")
		end
		local map = _G.Minimap
		ns.print("Minimap: %s  mask %s  zoom %s  size %s", tostring(type(map) == "table"),
			tostring(type(map) == "table" and map.SetMaskTexture ~= nil), tostring(ns.read(map and map.GetZoom, map)),
			tostring(ns.read(map and map.GetWidth, map)))
		if ns.Minimap then
			list("map decor", ns.Minimap.NAMES.globals)
			for _, pair in ipairs(ns.Minimap.NAMES.fields) do
				local parent = _G[pair[1]]
				ns.print("  %s.%s %s", pair[1], pair[2], tostring(type(parent) == "table" and type(rawget(parent, pair[2])) == "table"))
			end
		end
		if ns.XP then list("xp bars", ns.XP.NAMES) end
		if ns.Bags then
			list("bag bar", ns.Bags.NAMES.bar)
			list("bag buttons", ns.Bags.NAMES.buttons)
			local free, total = ns.Bags.Free()
			ns.print("bags: %s of %s free  C_Container %s  ToggleAllBags %s", tostring(free), tostring(total),
				tostring(type(C_Container) == "table"), tostring(type(ToggleAllBags) == "function"))
		end
		list("chat", { "ChatFrame1", "ChatFrame1Background", "ChatFrame1ButtonFrame", "ChatFrame1Tab", "ChatFrame1EditBox",
			"ChatFrame1EditBoxLeft", "ChatFrame1EditBoxMid", "ChatFrame1EditBoxRight", "ChatFrameMenuButton",
			"ChatFrameChannelButton", "QuickJoinToastButton" })
		if ns.Chat then
			local tex = {}
			for _, sfx in ipairs(ns.Chat.NAMES.textures) do tex[#tex + 1] = "ChatFrame1" .. sfx end
			list("chat textures", tex)
			list("chat buttons", ns.Chat.NAMES.shared)
		end
		if ns.ActionBars then
			local n = #ns.ActionBars.Buttons()
			local b = _G.ActionButton1
			local parts = {}
			if type(b) == "table" then
				for _, k in ipairs({ "icon", "IconMask", "SlotArt", "SlotBackground", "HotKey", "Count", "Name", "Border", "NormalTexture" }) do
					if type(rawget(b, k)) == "table" then parts[#parts + 1] = k end
				end
			end
			ns.print("action buttons: %d  ActionButton1 parts: %s", n, #parts > 0 and table.concat(parts, " ") or "-")
			list("bar art", ns.ActionBars.NAMES.art)
			-- every part of Blizzard's bar frames (what still shows can be named from here)
			for _, n in ipairs(ns.ActionBars.NAMES.containers) do
				local c = _G[n]
				if type(c) == "table" then
					local keys = {}
					for k, v in pairs(c) do
						if type(k) == "string" and type(v) == "table" and v.GetObjectType then
							local shown = ns.read(v.IsShown, v)
							keys[#keys + 1] = format("%s%s%s", k, ns.ActionBars.ArtKey(k) and "*" or "", shown and "" or "(hidden)")
						end
					end
					table.sort(keys)
					local nreg = select("#", c:GetRegions())
					ns.print("  %s: %d textures/texts; parts: %s", n, nreg, #keys > 0 and table.concat(keys, " ") or "-")
				end
			end
		end
		if ns.MicroMenu then
			local names = {}
			for _, e in ipairs(ns.MicroMenu.NAMES.entries) do names[#names + 1] = e[1] end
			list("micro buttons", names)
			list("micro containers", ns.MicroMenu.NAMES.containers)
			local all, wow, bn = ns.MicroMenu.FriendsOnline()
			ns.print("friends: online %d (game %d, Battle.net %d)  ToggleFriendsFrame %s  C_FriendList %s  QuickJoinToastButton %s",
				all, wow, bn, tostring(type(ToggleFriendsFrame) == "function"), tostring(type(C_FriendList) == "table"),
				tostring(type(_G.QuickJoinToastButton) == "table"))
			ns.print("secure handlers: WrapScript %s  ActionButtonUseKeyDown %s", tostring(type(SecureHandlerWrapScript) == "function"),
				tostring(GetCVar and GetCVar("ActionButtonUseKeyDown")))
		end
		ns.print("chat: CHAT_FRAME_TEXTURES %s  FCF_SetChatWindowFontSize %s  FCF_RestorePositionAndDimensions %s  FCFTab_UpdateAlpha %s",
			tostring(type(_G.CHAT_FRAME_TEXTURES) == "table"), tostring(type(_G.FCF_SetChatWindowFontSize) == "function"),
			tostring(type(_G.FCF_RestorePositionAndDimensions) == "function"), tostring(type(_G.FCFTab_UpdateAlpha) == "function"))
		ns.print("chat: windows %s  tab alpha %s/%s", tostring(_G.NUM_CHAT_WINDOWS), tostring(_G.CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA),
			tostring(_G.CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA))
		ns.print("xp: %s / %s  rested %s  level %s of %s", tostring(ns.read(UnitXP, "player")), tostring(ns.read(UnitXPMax, "player")),
			tostring(ns.read(GetXPExhaustion)), tostring(ns.read(UnitLevel, "player")), tostring(ns.read(GetMaxPlayerLevel)))
	end)
	ns.print("saved; /reload writes it to disk.")
end

-- /sitrep shiftprobe: what the client tells about the druid forms' costs (every
-- cost entry of each form, what the marker makes of it, your mana).
function Dbg.ShiftProbe()
	ns.Capture("shiftprobe", function()
		local api = C_Spell and C_Spell.GetSpellPowerCost
		local function d(v) if v == nil then return "nil" elseif ns.isSecret(v) then return "secret" end return tostring(v) end
		ns.print("forms: %s, active %s, mana %s / %s", d(ns.read(GetNumShapeshiftForms)), d(ns.read(GetShapeshiftForm)),
			d(ns.read(UnitPower, "player", 0)), d(ns.read(UnitPowerMax, "player", 0)))
		for i = 1, (ns.read(GetNumShapeshiftForms) or 0) do
			local _, active, _, id = ns.read(GetShapeshiftFormInfo, i)
			local name = id and C_Spell and C_Spell.GetSpellName and ns.read(C_Spell.GetSpellName, id)
			ns.print("form %d: spell %s %s%s, the marker uses %s", i, d(id), d(name), active and " (active)" or "",
				d(ns.Frames.SpellCost and ns.Frames.SpellCost(id, 0)))
			local ok, costs = pcall(api, id)
			if ok and type(costs) == "table" and not ns.isSecret(costs) then
				for n, c in ipairs(costs) do
					ns.print("  cost %d: type %s cost %s min %s percent %s perSec %s requiredAura %s has %s", n, d(c.type), d(c.cost),
						d(c.minCost), d(c.costPercent), d(c.costPerSec), d(c.requiredAuraID), d(c.hasRequiredAura))
				end
			else
				ns.print("  costs: %s", ok and d(costs) or "error")
			end
		end
	end)
	ns.print("saved; /reload writes it to disk.")
end

-- /sitrep mouse: what takes the mouse where it is now (to find an invisible frame
-- lying over something): name (or its key on its parent), kind, layer, alpha, shown.
local function nameOf(f)
	local n = f.GetName and f:GetName()
	if n then return n end
	local parent = f.GetParent and f:GetParent()
	if parent then
		for k, v in pairs(parent) do if v == f and type(k) == "string" then return nameOf(parent) .. "." .. k end end
		return nameOf(parent) .. ".?"
	end
	return "?"
end
Dbg.NameOf = nameOf

function Dbg.MouseProbe()
	ns.Capture("mouse", function()
		local list = {}
		if GetMouseFoci then
			local ok, t = pcall(GetMouseFoci)
			if ok and type(t) == "table" then list = t end
		elseif GetMouseFocus then
			local ok, f = pcall(GetMouseFocus)
			if ok and f then list = { f } end
		end
		if #list == 0 then ns.print("nothing under the mouse takes clicks (the world)") end
		for _, f in ipairs(list) do
			local okN, name = pcall(nameOf, f)
			ns.print("%s  %s  strata %s level %s  alpha %.2f  shown %s  protected %s", okN and name or "?",
				tostring(ns.read(f.GetObjectType, f)), tostring(ns.read(f.GetFrameStrata, f)), tostring(ns.read(f.GetFrameLevel, f)),
				ns.read(f.GetEffectiveAlpha, f) or ns.read(f.GetAlpha, f) or -1, tostring(ns.read(f.IsShown, f)),
				tostring(ns.read(f.IsProtected, f)))
		end
	end)
	ns.print("saved; /reload writes it to disk.")
end

-- /sitrep mapdump: every part on and round the minimap (Blizzard's and other
-- addons'): name, kind, shown, size, where it is anchored, its text.
function Dbg.MapDump()
	ns.Capture("mapdump", function()
		local map, cluster = _G.Minimap, _G.MinimapCluster
		local done = {}
		local function show(f, depth)
			if done[f] then return end
			done[f] = true
			local okN, name = pcall(nameOf, f)
			local kind = ns.read(f.GetObjectType, f) or "?"
			local p, rel, rp, x, y
			if f.GetPoint then
				local ok
				ok, p, rel, rp, x, y = pcall(f.GetPoint, f, 1)
				if not ok then p = nil end
			end
			local relName = rel and select(2, pcall(nameOf, rel)) or "-"
			local text = kind == "FontString" and ns.read(f.GetText, f) or nil
			ns.print("%s%s  %s  %s  %sx%s  at %s %s %s %s,%s%s", string.rep("  ", depth), okN and name or "?", kind,
				ns.read(f.IsShown, f) and "shown" or "hidden", tostring(math.floor((ns.read(f.GetWidth, f) or 0) + 0.5)),
				tostring(math.floor((ns.read(f.GetHeight, f) or 0) + 0.5)), tostring(p), tostring(relName), tostring(rp),
				tostring(x and math.floor(x + 0.5)), tostring(y and math.floor(y + 0.5)), text and ('  "' .. tostring(text) .. '"') or "")
		end
		local function walk(f, depth)
			if type(f) ~= "table" or depth > 2 then return end
			show(f, depth)
			local ok, kids = pcall(function() return { f:GetChildren() } end)
			for _, k in ipairs(ok and kids or {}) do walk(k, depth + 1) end
			local okR, regions = pcall(function() return { f:GetRegions() } end)
			for _, r in ipairs(okR and regions or {}) do
				if ns.read(r.GetObjectType, r) == "FontString" or depth == 0 then show(r, depth + 1) end
			end
		end
		walk(cluster, 0)
		walk(map, 0)
		-- frames elsewhere that hang on the map (other addons' clocks, coordinates...)
		local ok, kids = pcall(function() return { UIParent:GetChildren() } end)
		for _, k in ipairs(ok and kids or {}) do
			local okP, _, rel = pcall(k.GetPoint, k, 1)
			if okP and (rel == map or rel == cluster) then walk(k, 0) end
		end
	end)
	ns.print("saved; /reload writes it to disk.")
end

-- /sitrep platesize: which nameplate size settings this client has, what they are,
-- and how big a plate really is (to make the size slider work where it does not).
-- /sitrep zenprobe: each friendly player's plate, and why it is (not) name-only.
function Dbg.ZenProbe()
	ns.Capture("zenprobe", function()
		local N = ns.Plates
		ns.print("friendly zen: %s, in combat: %s", tostring(ns.P.plates.friendZen), tostring(InCombatLockdown()))
		-- the scale the client's health percent runs on (curves assume 0 to 1)
		local okP, pct = pcall(UnitHealthPercent, "player")
		ns.print("UnitHealthPercent(player) = %s, health %s / %s", okP and (ns.isSecret(pct) and "secret" or tostring(pct)) or "error",
			tostring(ns.read(UnitHealth, "player")), tostring(ns.read(UnitHealthMax, "player")))
		-- your group: is their health readable (party1-4, or the raid)?
		local function hp(u)
			local h, m = UnitHealth(u), UnitHealthMax(u)
			local function show(v) if ns.isSecret(v) then return "secret" end return tostring(v) end
			return show(h) .. " / " .. show(m)
		end
		local members = {}
		for i = 1, 40 do
			local u = (IsInRaid and IsInRaid()) and ("raid" .. i) or (i <= 4 and ("party" .. i) or nil)
			if u and ns.read(UnitExists, u) then members[#members + 1] = u .. " " .. hp(u) end
		end
		ns.print("you: %s; your group: %s", hp("player"), #members > 0 and table.concat(members, ", ") or "nobody")
		local n, shown = 0, false
		for unit, s in pairs(N.Current()) do
			if s.friend then
				n = n + 1
				ns.print("%s %s: %s", unit, tostring(ns.read(GetUnitName, unit, false) or "?"), N.ZenWhy(s))
				-- the first zen plate: everything that still draws on it
				if s.zenOn and not shown then
					shown = true
					for _, line in ipairs(N.Visible(s)) do ns.print("    %s", line) end
				end
			end
		end
		if n == 0 then ns.print("no friendly plate on screen (Shift+V shows them)") end
	end)
end

-- /sitrep barprobe: every texture on a few action buttons, with what shows it
-- (Blizzard's art showing through SITREP's look: which part, which alpha).
function Dbg.BarProbe()
	ns.Capture("barprobe", function()
		local read = ns.read
		for _, name in ipairs({ "ActionButton1", "ActionButton2", "MultiBarBottomLeftButton1", "PetActionButton1" }) do
			local b = _G[name]
			if type(b) == "table" then
				local keys = {}
				for k, v in pairs(b) do if type(k) == "string" and type(v) == "table" then keys[v] = k end end
				local nt = b.GetNormalTexture and read(b.GetNormalTexture, b)
				if nt then keys[nt] = keys[nt] or "(normal texture)" end
				ns.print("%s: shown %s, alpha %s", name, tostring(read(b.IsShown, b)), tostring(read(b.GetAlpha, b)))
				local ok, regions = pcall(function() return { b:GetRegions() } end)
				for i, r in ipairs(ok and regions or {}) do
					if read(r.GetObjectType, r) == "Texture" then
						local _, _, _, va = read(r.GetVertexColor, r)
						local atlas = r.GetAtlas and read(r.GetAtlas, r)
						ns.print("  #%d %s %s shown %s alpha %s vc %s %s", i, keys[r] or "?", tostring(read(r.GetDrawLayer, r)),
							tostring(read(r.IsShown, r)), tostring(read(r.GetAlpha, r)), tostring(va),
							atlas and ("atlas " .. tostring(atlas)) or ("file " .. tostring(read(r.GetTexture, r))))
					end
				end
			end
		end
		-- everything else that draws there: the bars' frames and the buttons' child
		-- frames, every visible texture with some alpha (SITREP's own skipped)
		ns.print("== visible textures round the bars (not SITREP's)")
		local seen, n = {}, 0
		local function walk(f, path, depth)
			if seen[f] or depth > 5 or n > 120 then return end
			seen[f] = true
			local keys = {}
			for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then keys[v] = k end end
			local ok, regions = pcall(function() return { f:GetRegions() } end)
			for i, r in ipairs(ok and regions or {}) do
				local key = keys[r]
				if read(r.GetObjectType, r) == "Texture" and read(r.IsVisible, r) and not (key and key:find("^sr")) then
					local a = read(r.GetEffectiveAlpha, r) or read(r.GetAlpha, r)
					if a == nil or a > 0.05 then
						n = n + 1
						local atlas = r.GetAtlas and read(r.GetAtlas, r)
						ns.print("  %s.%s %s alpha %s %dx%d %s", path, key or ("#" .. i), tostring(read(r.GetDrawLayer, r)),
							a and string.format("%.2f", a) or "secret", math.floor((read(r.GetWidth, r) or 0) + 0.5),
							math.floor((read(r.GetHeight, r) or 0) + 0.5), atlas and ("atlas " .. atlas) or ("file " .. tostring(read(r.GetTexture, r))))
					end
				end
			end
			local okC, kids = pcall(function() return { f:GetChildren() } end)
			for i, k in ipairs(okC and kids or {}) do
				if read(k.IsVisible, k) then
					local kn = keys[k] or (k.GetName and read(k.GetName, k)) or ("[" .. i .. "]")
					walk(k, path .. "." .. kn, depth + 1)
				end
			end
		end
		for _, name in ipairs({ "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
			"MultiBarLeft", "StanceBar", "ActionButton1", "MultiBarBottomLeftButton1" }) do
			local f = _G[name]
			if type(f) == "table" and read(f.IsVisible, f) then walk(f, name, 0) end
		end
		if n == 0 then ns.print("  (none)") end
	end)
end

function Dbg.PlateSize()
	ns.Capture("platesize", function()
		local N = ns.Plates
		local function v(k) return tostring(N.GetCVar(k)) end
		ns.print("slider: %s, SITREP set: %s", tostring(ns.P.plates.scale), N.scaleSet and table.concat(N.scaleSet, " ") or "nothing yet")
		for _, k in ipairs(N.SCALE_CVARS) do ns.print("  %s = %s", k, v(k)) end
		ns.print("ui: uiScale %s, useUiScale %s, UIParent scale %s", v("uiScale"), v("useUiScale"),
			tostring(ns.read(UIParent.GetEffectiveScale, UIParent)))
		-- every setting with "nameplate" in its name, as the client lists them
		local all = C_Console and C_Console.GetAllCommands and ns.read(C_Console.GetAllCommands)
		if type(all) == "table" then
			local names = {}
			for _, c in ipairs(all) do
				local n = type(c) == "table" and c.command
				if type(n) == "string" and n:lower():find("nameplate", 1, true) then names[#names + 1] = n end
			end
			table.sort(names)
			for _, n in ipairs(names) do ns.print("  cvar %s = %s", n, v(n)) end
		else
			ns.print("  (the client does not list its settings)")
		end
		-- a plate on screen, as big as it is
		for unit, s in pairs(N.Current()) do
			local plate, uf, hb = s:GetParent(), s.uf, s.hb
			local function size(f)
				if not f then return "-" end
				return string.format("%sx%s scale %s eff %s", tostring(ns.read(f.GetWidth, f)), tostring(ns.read(f.GetHeight, f)),
					tostring(ns.read(f.GetScale, f)), tostring(ns.read(f.GetEffectiveScale, f)))
			end
			ns.print("%s: plate %s; UnitFrame %s; bar %s", unit, size(plate), size(uf), size(hb))
			break
		end
	end)
	ns.print("saved; /reload writes it to disk.")
end

function Dbg.PlateDump()
	ns.Capture("platedump", function()
		-- your target's plate, else the first one this client hands out
		local pick, plate
		local units = {}
		for u in pairs(ns.Sensors._plates or {}) do units[#units + 1] = u end
		table.sort(units, function(a, b)
			local ta, tb = ns.read(UnitIsUnit, a, "target") == true, ns.read(UnitIsUnit, b, "target") == true
			if ta ~= tb then return ta end
			return a < b
		end)
		for _, u in ipairs(units) do
			local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, u)
			if ok and p and not ns.isSecret(p) then pick, plate = u, p break end
		end
		if not pick then ns.print(#units == 0 and "no nameplate on screen" or "no usable nameplate (all forbidden)") return end
		local okU, uf = pcall(function() return plate.UnitFrame end)
		ns.print("plate dump: %s (%s)", pick, tostring(ns.read(GetUnitName, pick, false)))
		if not okU or not uf then ns.print("no UnitFrame") return end
		walk(uf, "UnitFrame", 1, { [uf] = true })
	end)
	ns.print("saved; /reload writes it to disk.")
end

---------------------------------------------------------------------------
-- "Interface-Aktion auf Grund eines Addons fehlgeschlagen" / "Interface action
-- failed because of an AddOn": the client blocked a protected action because
-- addon code was involved. It names the function it blocked; SITREP keeps the
-- last 30 (time, function, in combat or not) in reports.blocked, saved on
-- /reload. Each function is mentioned in chat once per session.
---------------------------------------------------------------------------
local BLOCKED_KEEP = 30
local mentioned = {}
local function onBlocked(kind)
	return function(_, addon, fn)
		addon, fn = tostring(addon or "?"), tostring(fn or "?")
		local combat = InCombatLockdown and InCombatLockdown() and "in combat" or "out of combat"
		local line = format("%s %s %s: %s (%s)", date and date("%H:%M:%S") or "?", kind, addon, fn, combat)
		if SITREP_DB then
			SITREP_DB.reports = SITREP_DB.reports or {}
			local r = SITREP_DB.reports.blocked
			if not r then
				r = { at = "", version = ns.VERSION, lines = {} }
				SITREP_DB.reports.blocked = r
			end
			r.at, r.version = date and date("%Y-%m-%d %H:%M:%S") or "?", ns.VERSION
			table.insert(r.lines, 1, line)
			for i = #r.lines, BLOCKED_KEEP + 1, -1 do r.lines[i] = nil end
		end
		Dbg.lastBlocked = line
		-- this session's, for /sitrep doctor
		Dbg.session = Dbg.session or {}
		table.insert(Dbg.session, { kind = kind, addon = addon, fn = fn, combat = combat })
		if not mentioned[addon .. fn] then
			mentioned[addon .. fn] = true
			ns.print("the client blocked %s (%s, %s); saved for /reload as reports.blocked.", fn, addon, combat)
		end
	end
end
ns.On("ADDON_ACTION_BLOCKED", onBlocked("BLOCKED"))
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked("FORBIDDEN"))

---------------------------------------------------------------------------
-- /sitrep rangeprobe: which item range checks this client answers for your
-- target, and whether they agree with your spell checks. Run it near an enemy
-- or a mob at different distances, out of combat; it runs once more 2 s into
-- your next fight (items against enemies are expected to be refused there).
-- Report: reports.rangeprobe (and rangeprobe_combat).
---------------------------------------------------------------------------
local rangeArmed = false

local function answerText(ok, v)
	if not ok then return "ERR" end
	if ns.isSecret(v) then return "SECRET" end
	if v == nil then return "nil" end
	return tostring(v)
end

function Dbg.RangeProbe(name)
	name = name or (InCombatLockdown() and "rangeprobe_combat" or "rangeprobe")
	local S = ns.Sensors
	ns.Capture(name, function()
		local fn = S.ItemRangeFn()
		ns.print("range probe (%s): combat %s; item check %s, C_Item.IsItemInRange %s, IsItemInRange %s",
			name, tostring(InCombatLockdown()), fn and "found" or "MISSING",
			C_Item and C_Item.IsItemInRange and "yes" or "no", _G.IsItemInRange and "yes" or "no")
		if not ns.read(UnitExists, "target") then ns.print("no target: target an enemy or a mob and run it again") return end
		local hostile = S.IsEnemy("target")
		ns.print("target: %s, %s, level %s", tostring(ns.read(GetUnitName, "target", false)), hostile and "enemy" or "not hostile",
			tostring(ns.read(UnitLevel, "target")))
		-- the protected checks may only be asked about enemies in combat
		local mayAsk = not InCombatLockdown() or ns.read(UnitCanAttack, "player", "target") == true
		if not mayAsk then ns.print("in combat and not an enemy: interact and item checks are protected, skipped") end
		-- every interact distance the client knows (their yards differ between clients)
		if mayAsk then
			local yards = { "achievement 28", "trade 8-11", "duel 7-10", "follow 28", "pet duel 7" }
			for idx = 1, 5 do
				local ok, v = pcall(CheckInteractDistance, "target", idx)
				ns.print("  interact %d (%s): %s", idx, yards[idx], answerText(ok, v))
			end
		end
		-- what the spell and interact checks say
		local spellLo, spellHi = 0, nil
		for _, c in ipairs(hostile and S.checks or S.helpChecks) do
			if c.kind == "spell" or (c.kind == "interact" and mayAsk) then
				local ok, v
				if c.kind == "spell" then ok, v = pcall(C_Spell.IsSpellInRange, c.id, "target")
				else ok, v = pcall(CheckInteractDistance, "target", c.idx) end
				ns.print("  %-24s %3d yd: %s", tostring(c.name):sub(1, 24), c.max, answerText(ok, v))
				if ok and not ns.isSecret(v) then
					if v == true or v == 1 then spellHi = spellHi and math.min(spellHi, c.max) or c.max
					elseif v ~= nil and c.min == 0 then spellLo = math.max(spellLo, c.max) end
				end
			end
		end
		ns.print("spell checks alone: %s", ns.Comms.RangeText({ lo = spellLo, hi = spellHi }))
		-- the items, per step of yards: how many this client knows, and the answers of the ones in use
		local kind = hostile and "harm" or "friend"
		local list = hostile and S.checks or S.helpChecks
		local steps = {}
		for yd in pairs(ns.Data.RANGE_ITEMS[kind]) do steps[#steps + 1] = yd end
		table.sort(steps)
		local nameOf = C_Item and C_Item.GetItemNameByID
		local itLo, itHi, answering, contra = 0, nil, 0, 0
		ns.print("%s items (%s):", kind, hostile and "against enemies" or "against friends")
		for _, yd in ipairs(steps) do
			local ids = ns.Data.RANGE_ITEMS[kind][yd]
			local known = 0
			for _, id in ipairs(ids) do if nameOf and ns.read(nameOf, id) then known = known + 1 end end
			local parts, stepAnswered = {}, false
			for _, c in ipairs(list) do
				if c.kind == "item" and c.max == yd then
					local ok, v = false, nil
					if fn and mayAsk then ok, v = pcall(fn, c.id, "target") end
					local nm = nameOf and ns.read(nameOf, c.id) or "?"
					parts[#parts + 1] = format("%d %s=%s", c.id, tostring(nm):sub(1, 18), answerText(ok, v))
					if ok and not ns.isSecret(v) and v ~= nil and not stepAnswered then
						stepAnswered = true
						local inR = v == true or v == 1
						if inR then itHi = itHi and math.min(itHi, yd) or yd else itLo = math.max(itLo, yd) end
						if inR and spellLo > yd then contra = contra + 1 end
						if not inR and spellHi and spellHi <= yd then contra = contra + 1 end
					end
				end
			end
			if stepAnswered then answering = answering + 1 end
			ns.print("  %3d yd: %d of %d known; %s", yd, known, #ids, #parts > 0 and table.concat(parts, ", ") or "none in use")
		end
		ns.print("item steps answering: %d of %d; items alone: %s; disagreements with spells: %d", answering, #steps,
			answering > 0 and ns.Comms.RangeText({ lo = itLo, hi = itHi }) or "-", contra)
		local lo, hi = S.MeasureRange("target", nil, hostile and S.checks or S.helpChecks)
		ns.print("SITREP's bracket now: %s", ns.Comms.RangeText({ lo = lo, hi = hi }))
	end)
	ns.print("saved; /reload writes it to disk.")
	if not InCombatLockdown() and not rangeArmed then
		rangeArmed = true
		ns.print("armed: it runs once more 2 s into your next fight.")
	end
end

ns.On("PLAYER_REGEN_DISABLED", function()
	if not rangeArmed then return end
	rangeArmed = false
	C_Timer.After(2, function()
		if InCombatLockdown() then Dbg.RangeProbe("rangeprobe_combat") end
	end)
end)

---------------------------------------------------------------------------
-- /sitrep ideaprobe: does this client give what the newer ideas need? For 90 s:
--   UNIT_COMBAT and UNIT_SPELLCAST_SUCCEEDED by kind of unit token (do enemies on
--   plates send them? plain or secret?), heals matched to a healer's cast,
--   creatures' GUIDs (spawn age, layer), enemy players' power (plain or secret),
--   your target's speed, and whether C_DamageMeter and the restriction states exist.
-- Writes the report "ideaprobe" (on /reload). Stand among mobs, then fight or duel.
---------------------------------------------------------------------------
local IDEA_SECONDS = 90
local idea -- the running probe
local function tokenKind(unit)
	if type(unit) ~= "string" then return "?" end
	return unit:match("^(%a+)") or unit
end
local function plainOrSecret(v)
	if ns.isSecret(v) then return "secret" end
	return v == nil and "nil" or "plain"
end
local function tally(t, key) t[key] = (t[key] or 0) + 1 end

ns.On("UNIT_COMBAT", function(_, unit, action, _, amount)
	if not idea then return end
	tally(idea.combat, tokenKind(unit) .. " " .. tostring(action) .. " (amount " .. plainOrSecret(amount) .. ")")
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if not idea then return end
	tally(idea.casts, tokenKind(unit) .. " (spell " .. plainOrSecret(spellID) .. ")")
end)

local function ideaSample()
	if not idea then return end
	local S, read = ns.Sensors, ns.read
	local now = GetServerTime and GetServerTime()
	for unit in pairs(S._plates or {}) do
		local guid = read(UnitGUID, unit)
		if guid and not idea.guids[guid] and idea.nGuids < 12 then
			local zone, npc, spawn = S.GuidParts(guid)
			if zone then
				idea.guids[guid] = true
				idea.nGuids = idea.nGuids + 1
				local name = read(GetUnitName, unit, false)
				idea.creatures[#idea.creatures + 1] = format("%s (npc %d): spawn %s, zone %d, age %s", tostring(name), npc, spawn, zone,
					tostring(S.SpawnAge(guid, now)))
			end
		end
		if read(UnitIsPlayer, unit) and S.IsEnemy(unit) then
			local _, ptype = pcall(UnitPowerType, unit)
			local _, power = pcall(UnitPower, unit, 0)
			local _, powerMax = pcall(UnitPowerMax, unit, 0)
			local key = format("type %s, power %s, max %s, in combat %s", plainOrSecret(ptype), plainOrSecret(power),
				plainOrSecret(powerMax), tostring(InCombatLockdown()))
			tally(idea.power, key)
		end
	end
	-- caves and floors: indoors, the height, the map you are on
	local indoors = _G.IsIndoors and read(_G.IsIndoors)
	local _, _, z = read(UnitPosition, "player")
	local map = C_Map and C_Map.GetBestMapForUnit and read(C_Map.GetBestMapForUnit, "player")
	local info = map and C_Map.GetMapInfo and read(C_Map.GetMapInfo, map)
	tally(idea.place, format("indoors %s, height %s, map %s (%s, type %s)", tostring(indoors), z == nil and "nil" or (z == 0 and "0" or "plain"),
		tostring(map), type(info) == "table" and tostring(info.name) or "?", type(info) == "table" and tostring(info.mapType) or "?"))
	if read(UnitExists, "target") and _G.GetUnitSpeed then
		local ok, v = pcall(_G.GetUnitSpeed, "target")
		tally(idea.speed, ok and plainOrSecret(v) or "error")
	end
end

function Dbg.IdeaProbe(arg)
	if arg == "stop" then
		if idea then Dbg.IdeaFinish() else ns.print("no idea probe running") end
		return
	end
	idea = { combat = {}, casts = {}, power = {}, speed = {}, creatures = {}, guids = {}, nGuids = 0, place = {},
	}
	idea.ticker = C_Timer and C_Timer.NewTicker and C_Timer.NewTicker(2, ideaSample)
	ideaSample()
	C_Timer.After(IDEA_SECONDS, function() if idea then Dbg.IdeaFinish() end end)
	ns.print("idea probe: %d s. Stand among mobs, then fight or duel someone; /sitrep ideaprobe stop ends it.", IDEA_SECONDS)
end

function Dbg.IdeaFinish()
	local r = idea
	idea = nil
	if r.ticker and r.ticker.Cancel then r.ticker:Cancel() end
	local function dump(title, t)
		ns.print("== %s", title)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys)
		if #keys == 0 then ns.print("  (none)") end
		for _, k in ipairs(keys) do ns.print("  %4dx %s", t[k], k) end
	end
	ns.Capture("ideaprobe", function()
		ns.print("SITREP %s, %s", ns.VERSION, date and date("%Y-%m-%d %H:%M") or "")
		dump("UNIT_COMBAT by token", r.combat)
		dump("UNIT_SPELLCAST_SUCCEEDED by token", r.casts)
		local hs = ns.Targeting and ns.Targeting.healStats
		if hs then
			ns.print("== heals on enemies: %d seen, %d matched to one caster, %d to several, %d with no cast near (since login)",
				hs.heals, hs.matched, hs.ambiguous, hs.alone)
			local n = 0
			for _ in pairs(ns.Targeting.knownHealers) do n = n + 1 end
			ns.print("  healers found: %d", n)
		end
		ns.print("== creatures (GUID: spawn age in seconds, zone = layer)")
		if #r.creatures == 0 then ns.print("  (none)") end
		for _, line in ipairs(r.creatures) do ns.print("  %s", line) end
		ns.print("  server time %s, layer now %s on map %s", tostring(GetServerTime and GetServerTime()),
			tostring(ns.Sensors.layer.id), tostring(ns.Sensors.layer.map))
		dump("enemy players' power (UnitPowerType, UnitPower, UnitPowerMax)", r.power)
		dump("GetUnitSpeed on your target", r.speed)
		dump("where you are (walk into a cave or a building during the probe)", r.place)
		local TM = _G.C_TaxiMap
		ns.print("== flight paths: C_TaxiMap %s, GetTaxiNodesForMap %s, GetAllTaxiNodes %s, NumTaxiNodes %s, UnitOnTaxi %s",
			tostring(TM ~= nil), tostring(TM and TM.GetTaxiNodesForMap ~= nil), tostring(TM and TM.GetAllTaxiNodes ~= nil),
			tostring(_G.NumTaxiNodes ~= nil), tostring(_G.UnitOnTaxi ~= nil))
		local here = ns.Quests.Here()
		if TM and TM.GetTaxiNodesForMap and here then
			local ok, nodes = pcall(TM.GetTaxiNodesForMap, here.map)
			ns.print("  nodes on this map: %s", ok and type(nodes) == "table" and tostring(#nodes) or ("error: " .. tostring(nodes)))
			if ok and type(nodes) == "table" then
				for i = 1, math.min(5, #nodes) do
					local n = nodes[i]
					ns.print("  %s at %s, %s (state %s)", tostring(n.name), tostring(n.position and n.position.x), tostring(n.position and n.position.y), tostring(n.state))
				end
			end
		end
		ns.print("== APIs: C_DamageMeter %s, C_RestrictedActions %s, GetRestrictedActionStatus %s, UnitHealthPercent %s, C_CurveUtil.CreateColorCurve %s",
			tostring(_G.C_DamageMeter ~= nil), tostring(_G.C_RestrictedActions ~= nil), tostring(_G.GetRestrictedActionStatus ~= nil),
			tostring(UnitHealthPercent ~= nil), tostring(C_CurveUtil ~= nil and C_CurveUtil.CreateColorCurve ~= nil))
	end, true)
	ns.print("idea probe done: /reload, then tell me (report ideaprobe).")
end
