-- SITREP · Core
-- Event bus, secret-value guards, settings, slash commands, profile export.
--
-- Doctrine: every value read from the client passes through ns.read / ns.plain.
-- On Forever (Midnight restrictions) health, auras and some identity fields can be
-- "secret": comparing, branching on or doing arithmetic with one throws. The guards
-- turn a secret into nil, so every caller already handles "unknown".

local ADDON, ns = ...
_G.SITREP = ns
ns.VERSION = "4.11.5"

local pcall, type, pairs, ipairs, select, tostring = pcall, type, pairs, ipairs, select, tostring
local format = string.format

---------------------------------------------------------------------------
-- Secret-value guards
---------------------------------------------------------------------------
local issecret = _G.issecretvalue or function() return false end

local function plain(v)
	if issecret(v) then return nil end
	return v
end
ns.plain = plain
ns.isSecret = function(v) return issecret(v) == true end

-- Call a client function without letting a throw or a secret escape.
-- The unit questions asked thousands of times a second answer with one value:
-- for those only that value is checked. (Testing the others for nil is not an
-- option: a secret cannot be compared.)
local SINGLE = {}
for _, name in ipairs({ "UnitExists", "UnitIsPlayer", "UnitIsFriend", "UnitIsEnemy", "UnitCanAttack", "UnitIsUnit",
	"UnitIsDeadOrGhost", "UnitLevel", "UnitGUID", "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax",
	"UnitAffectingCombat", "UnitReaction", "UnitIsTapDenied", "UnitClassification", "UnitGroupRolesAssigned",
	"UnitIsPVP", "GetUnitName", "InCombatLockdown", "IsInGroup", "IsInRaid", "IsResting", "CheckInteractDistance" }) do
	local fn = _G[name]
	if type(fn) == "function" then SINGLE[fn] = true end
end

function ns.read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return nil end
	if SINGLE[fn] then return plain(a) end
	return plain(a), plain(b), plain(c), plain(d)
end

-- True when the call returned something (secret or not). Used for "is casting":
-- a secret spell name still proves a cast exists.
function ns.present(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	if not ok then return false end
	return issecret(v) or v ~= nil
end

---------------------------------------------------------------------------
-- Output and error containment
---------------------------------------------------------------------------
local PREFIX = "|cff5cff8dSITREP|r "
function ns.print(msg, ...)
	if select("#", ...) > 0 then msg = format(msg, ...) end
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(PREFIX .. msg)
end

-- The client stops delivering Lua errors after 100 per session. A handler that
-- throws every tick would burn that in seconds and hide every other addon's
-- errors, so each distinct error is reported once and then only counted.
local errorSeen = {}
function ns.error(err)
	err = tostring(err)
	local n = (errorSeen[err] or 0) + 1
	errorSeen[err] = n
	if n == 1 then
		ns.print("|cffff5555internal error|r %s", err)
		-- Keep the first distinct errors on disk (written on /reload or logout).
		if SITREP_DB then
			SITREP_DB.errors = SITREP_DB.errors or {}
			if #SITREP_DB.errors < 20 then SITREP_DB.errors[#SITREP_DB.errors + 1] = err end
		end
	end
end
ns.errorCounts = errorSeen

---------------------------------------------------------------------------
-- Event bus. Client events and internal "SR_" messages share one dispatcher.
---------------------------------------------------------------------------
local bus = CreateFrame("Frame")
local handlers = {}
ns.knownEvents = {}

-- Measuring (/sitrep perf, Perf.lua): while ns.perf is a table, every bus handler
-- and every ns.Timed function adds its time there: ns.perf[label] = { n, ms, max, kb }
-- (kb: the memory it took, garbage the collector has to clear later; roughly, as a
-- collection running inside a handler hides what it took). Off (nil), nothing is
-- measured and nothing costs.
ns.perf = nil
local owners = {} -- [handler] = the file that registered it
local clock = debugprofilestop or function() return 0 end
local memory = function() return 0 end
if collectgarbage and pcall(collectgarbage, "count") then memory = function() return collectgarbage("count") end end
local function addTime(label, ms, kb)
	local r = ns.perf[label]
	if not r then r = { n = 0, ms = 0, max = 0, kb = 0 }; ns.perf[label] = r end
	r.n, r.ms = r.n + 1, r.ms + ms
	if kb and kb > 0 then r.kb = r.kb + kb end
	if ms > r.max then r.max = ms end
end
ns.AddTime = addTime

-- Times are a handler's own: a handler that fires another event (the sensor tick
-- fires the picture, the picture the allies) does not count the time of the
-- handlers it set off, those are counted under their own name. (inner: the time
-- spent in measured code below the one running.)
local inner, innerKB = 0, 0
local function done(label, t0, kb0, outer, outerKB, ok, ...)
	local spent = clock() - t0
	local took = memory() - kb0
	if took < 0 then took = 0 end -- (a collection ran)
	addTime(label, spent - inner, took - innerKB)
	inner, innerKB = outer + spent, outerKB + took
	return ok, ...
end
-- (returns pcall's results: ok, then the function's own)
local function measure(label, fn, ...)
	local outer, outerKB = inner, innerKB
	inner, innerKB = 0, 0
	local kb0 = memory()
	local t0 = clock()
	return done(label, t0, kb0, outer, outerKB, pcall(fn, ...))
end

local function rethrow(ok, ...)
	if not ok then error((...), 0) end
	return ...
end
-- Wrap a function so /sitrep perf can see its time (an OnUpdate script, say, or a
-- part of a bigger job: it returns what the function returns).
function ns.Timed(label, fn)
	return function(...)
		if not ns.perf then return fn(...) end
		return rethrow(measure(label, fn, ...))
	end
end

local function ownerFile()
	local s = debugstack and debugstack(3, 1, 0) or ""
	return s:match("SITREP[/\\]([%w_/\\]+)%.lua") or "?"
end

function ns.On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		if event:sub(1, 3) ~= "SR_" then
			-- Registering an event the client does not know throws on Forever.
			ns.knownEvents[event] = pcall(bus.RegisterEvent, bus, event)
		end
	end
	list[#list + 1] = fn
	owners[fn] = ownerFile()
end

function ns.Fire(event, ...)
	local list = handlers[event]
	if not list then return end
	if ns.perf then
		for i = 1, #list do
			local ok, err = measure(event .. " @" .. tostring(owners[list[i]]), list[i], event, ...)
			if not ok then ns.error(err) end
		end
		return
	end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then ns.error(err) end
	end
end

bus:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

-- Sensor clock: one tick drives the whole pipeline. SR_TICK_PRE runs the
-- measurements the model reads (pressure), then SR_TICK senses → scores → draws.
local acc = 0
bus:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	local P = ns.P
	if not P or not P.enabled then return end
	if acc >= 1 / P.sensors.rate then
		local dt = acc
		acc = 0
		ns.Fire("SR_TICK_PRE", dt)
		ns.Fire("SR_TICK", dt)
	end
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = copy(v) end
	return out
end
ns.copy = copy

local function fill(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			fill(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
ns.fill = fill

-- Settings of features that were removed (the radar scope, directions, the first
-- friendly-plate opacity) stay in the saved file until dropped: keys the defaults
-- no longer have go. Tables keyed by class, position or icon are left alone.
local OPEN = { ["hud.pos"] = true, ["threat.matrix"] = true, ["threat.power"] = true, ["threat.hvt"] = true, trackers = true }
local function prune(dst, def, path)
	for k, v in pairs(dst) do
		local p = path and (path .. "." .. k) or k
		if def[k] == nil then
			dst[k] = nil
		elseif type(v) == "table" and type(def[k]) == "table" and not OPEN[p] then
			prune(v, def[k], p)
		end
	end
	return dst
end
ns.prune = prune

-- Data.lua supplies the doctrine tables (matrix, powers, HVT values).
function ns.Defaults()
	local D = ns.Data
	return {
		enabled = true,
		hud = {
			locked = true, scale = 1.0, alpha = 1.0, accent = "nvg", consoleScale = 1.0,
			envelope = true, board = true, engage = true, pressure = true, allies = true, alliesRows = 5,
			envelopeLanes = 6, envelopeRange = 40,
			-- per-module size, multiplied with the global scale
			frameScale = { envelope = 1, board = 1, engage = 1, pressure = 1, player = 1, target = 1, allies = 1, pet = 1, targetpet = 1, party = 1,
				bags = 1, menu = 1, quests = 1, questArrow = 1, castAlert = 1, hoverInfo = 1, chat = 1, emergency = 1, recap = 1, banner = 1 },
			-- each element's own opacity (Layout page); HUD modules multiply it with alpha
			frameAlpha = { envelope = 1, board = 1, engage = 1, pressure = 1, player = 1, target = 1, allies = 1, pet = 1,
				targetpet = 1, party = 1, bags = 1, menu = 1, quests = 1, questArrow = 1, minimap = 1, chat = 1, castAlert = 1, hoverInfo = 1, emergency = 1, recap = 1, banner = 1 },
			-- each element's background opacity (Layout page): today's look by default; the
			-- chat a light glass pane
			bgAlpha = { envelope = 0.92, board = 0.92, engage = 0.92, pressure = 0.92, allies = 0.92, player = 0.92,
				target = 0.92, pet = 0.92, targetpet = 0.92, party = 0.92, bags = 0.92, menu = 0.92, quests = 0.72,
				minimap = 0.85, chat = 0.45, castAlert = 0.55, hoverInfo = 0.92, emergency = 0.92, recap = 0.92, banner = 0.55 },
			-- fade a module out while no enemy player is in the picture
			autoHide = { envelope = false, board = false, engage = false, pressure = false, player = false, allies = false },
			boardRows = 6, showHealth = true,
			pos = {},
		},
		sensors = {
			rate = 5, memory = 45, npcs = false, groupTargets = true,
			plateRange = 41, useSpellRange = true, useInteract = true, useItemRange = true,
		},
		threat = {
			targetingMe = 1.8, casting = 1.3, inCombat = 1.15, closing = 1.25, inReach = 1.2,
			levelBase = 1.12, falloff = 30, hvtMin = 60,
			matrix = copy(D.MATRIX), power = copy(D.POWER), hvt = copy(D.HVT),
		},
		engage = {
			k = 2.2, bias = 0, autoCal = true, lr = 0.05, radius = 45,
			engageAt = 1.5, contestAt = 0.9, holdAt = 0.6,
			n = 0, brier = 0,
		},
		duel = { k = 2.2, bias = 0, n = 0, brier = 0 },
		-- warnPct / dangerPct: incoming damage per second as % of your max health
		-- (5 % = dead from full in 20 s, 10 % = in 10 s)
		pressure = { short = 3, long = 10, spikePct = 35, ttlWarn = 4, warnPct = 5, dangerPct = 10 },
		frames = {
			player = true, target = true, pet = true, targetPet = true, party = true, hitGlow = true, dispelGlow = true, costPreview = true, totHealth = true, healersOnMe = true, targetCounts = true, mobsOnMe = true, popNumbers = true, hideBlizzard = true, width = 264,
			execute = true, strip = true, intel = true, flash = true,
			myDebuffs = true, targetAuras = true, burst = true, burstMax = 15, druidMana = true,
			emergency = true, emergencyPct = 35,
		},
		plates = {
			enabled = true, enemy = true, friendly = true, level = true, tags = true, cast = true, rangeFade = true, borders = true, dot = true, friendOpacity = 0.7, shiftX = 12, shiftY = -4,
			hoverInfo = true, hoverWhere = "frame", hoverLegend = true, incoming = true, scale = 1, heals = true, questMobs = true, friendCombatScale = 0.6, mobPvpScale = 0.75, friendZen = false, npcIcons = true, groupFocus = true, foeRing = true, mateRing = true, combo = true, auras = true, auraScale = 1, killWindow = true, killPct = 20, aggroRadar = true, enemyMana = true,
		},
		-- the game's own interface in SITREP's style (UI/Minimap, XP, Bags, Chat)
		ui = {
			minimap = true, mapSize = 180, mapCoords = true, xp = true, hideBlizzXP = true,
			bags = true, hideBagBar = true, chat = true, chatSize = 11, chatFade = 20,
			bars = true, barArt = true, barMacroNames = false, barRange = true, barHideEmpty = true, menu = true, hideMicro = true,
			barLayout = true, barEdit = "main", layoutEdit = "player", chatCollapsed = false, chatFoldTo = "auto", chatPreview = true,
			chatGlass = false, -- (4.1: the chat's glass pane given once to profiles from before)
		},
		-- each action bar's layout (UI/BarLayout): size, gap between buttons, buttons per row
		bars = {
			main = { scale = 1, gap = 6, cols = 12, alpha = 1, bg = 0.92 }, bottomleft = { scale = 1, gap = 6, cols = 12, alpha = 1, bg = 0.92 },
			bottomright = { scale = 1, gap = 6, cols = 12, alpha = 1, bg = 0.92 }, right = { scale = 1, gap = 6, cols = 1, alpha = 1, bg = 0.92 },
			left = { scale = 1, gap = 6, cols = 1, alpha = 1, bg = 0.92 }, bar5 = { scale = 1, gap = 6, cols = 12, alpha = 1, bg = 0.92 },
			bar6 = { scale = 1, gap = 6, cols = 12, alpha = 1, bg = 0.92 }, bar7 = { scale = 1, gap = 6, cols = 12, alpha = 1, bg = 0.92 },
			pet = { scale = 1, gap = 6, cols = 10, alpha = 1, bg = 0.92 }, stance = { scale = 1, gap = 6, cols = 10, alpha = 1, bg = 0.92 },
		},
		-- quest tracker and navigation arrow (Quests, UI/QuestTracker, UI/QuestArrow)
		quests = { tracker = true, hideBlizz = true, arrow = true, learn = true, autoNearest = false, rows = 8, sort = "distance",
			collapsed = false, value = true, trails = true, travel = true, combatFold = true, questMap = true, mapTrails = false, mapFlights = true, mapBrush = 1, nearby = true },
		comms = {
			channel = "AUTO", share = true, shareRate = 2,
			template = "[SITREP] {n} hostile: {comp} | {range} | {zone} | {hvt}{advice} ({pwin})",
		},
		alerts = {
			sound = true, flash = true, banner = true,
			newContact = true, hvt = true, targeted = true, spike = true, ttl = true, closing = true, incoming = true, rare = true, layer = true, healer = true, stealth = true,
		},
		log = { keep = 60, aarPopup = true, recapPopup = true },
		-- your own spell icons: cooldowns, missing on target, missing on you
		trackers = { enabled = true, items = {}, nextId = 1, mirror = false, learned = {} }, -- schema set by Trackers
	}
end

-- The layout a new profile starts with (and /sitrep reset goes back to): the
-- maintainer's own, taken from their saved settings on 2026-10-16 (4.11.2) with
-- tools/preset_from_saved.lua. Only
-- settings and places a player chose: no learned values (engagement calibration,
-- tracker spells), no places SITREP worked out itself (bars never moved), no
-- window states. On top of ns.Defaults(), which stays the bare doctrine.
ns.PRESET = {
	bars = {
		bottomleft = {
			gap = 8,
			scale = 0.5,
		},
		bottomright = {
			scale = 0.8,
		},
		main = {
			gap = 12,
			scale = 0.6,
		},
		right = {
			cols = 3,
			gap = 0,
			scale = 0.6,
		},
	},
	frames = {
		width = 280,
	},
	hud = {
		allies = false,
		alpha = 0.7,
		bgAlpha = {
			party = 0.8,
			player = 0.8,
			quests = 0.8,
		},
		board = false,
		engage = false,
		envelope = false,
		frameAlpha = {
			party = 0.7,
			questArrow = 0.8,
			target = 0.8,
		},
		frameScale = {
			party = 0.8,
			pet = 0.6,
			player = 0.8,
			questArrow = 0.7,
			quests = 1.2,
			target = 0.9,
		},
		pos = {
			allies = { "TOPLEFT", "TOPLEFT", 11.4, -174.0 },
			bags = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2.8, 5.2 },
			banner = { "TOP", "TOP", -24.7, -52.4 },
			bar_bar7 = { "CENTER", "CENTER", 145.3, -99.5 },
			bar_bottomleft = { "BOTTOMLEFT", "BOTTOMLEFT", 3.0, 27.7 },
			bar_bottomright = { "BOTTOM", "BOTTOM", 13.3, 3.8 },
			bar_main = { "BOTTOMLEFT", "BOTTOMLEFT", 3.4, 3.8 },
			bar_right = { "TOPRIGHT", "TOPRIGHT", 0, -141.2 },
			bar_stance = { "BOTTOMLEFT", "BOTTOMLEFT", 3.0, 51.5 },
			board = { "LEFT", "LEFT", 0, -100.3 },
			castAlert = { "CENTER", "CENTER", -9.4, -11.5 },
			chat = { "BOTTOMLEFT", "BOTTOMLEFT", 9.0, 122.0 },
			emergency = { "CENTER", "CENTER", -69.4, -104.9 },
			engage = { "TOP", "TOP", -183.7, -8.3 },
			envelope = { "CENTER", "CENTER", -234.0, -100.7 },
			hoverInfo = { "CENTER", "CENTER", 198.3, 119.3 },
			menu = { "BOTTOMRIGHT", "BOTTOMRIGHT", -117.5, 4.3 },
			minimap = { "TOPRIGHT", "TOPRIGHT", -8.1, -24.4 },
			pet = { "CENTER", "CENTER", -277.9, 2.3 },
			player = { "CENTER", "CENTER", -244.9, 72.5 },
			pressure = { "LEFT", "LEFT", 255.4, -86.4 },
			questArrow = { "TOPRIGHT", "TOPRIGHT", -328.7, -141.6 },
			quests = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2.1, 49.4 },
			recap = { "CENTER", "CENTER", -11.9, 71.6 },
			scope = { "BOTTOMRIGHT", "BOTTOMRIGHT", -55.9, 114.0 },
			target = { "CENTER", "CENTER", 241.3, -93.8 },
			targetpet = { "RIGHT", "RIGHT", -78.3, -76.8 },
		},
		pressure = false,
		scale = 0.9,
	},
	plates = {
		friendZen = true,
		hoverWhere = "mouse",
		scale = 1.2,
	},
	sensors = {
		plateRange = 50,
		rate = 10,
	},
	ui = {
		chatGlass = true,
		chatSize = 14,
	},
}

-- A new profile: the defaults with the preset laid over them.
local function overlay(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" and #v == 0 then overlay(dst[k], v)
		else dst[k] = type(v) == "table" and copy(v) or v end
	end
	return dst
end
function ns.NewProfile() return overlay(ns.Defaults(), ns.PRESET) end

function ns.ResetProfile()
	SITREP_DB.profile = ns.NewProfile()
	ns.P = SITREP_DB.profile
	ns.Fire("SR_CONFIG", "*")
end

-- Tell every module a setting changed. key is "section.field" or "*".
function ns.Changed(key)
	ns.Fire("SR_CONFIG", key or "*")
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	SITREP_DB = SITREP_DB or {}
	local db = SITREP_DB
	local defaults = ns.Defaults()
	-- a first start: the preset layout (ns.PRESET); after that, only new keys fill in
	db.profile = prune(fill(db.profile or ns.NewProfile(), defaults), defaults)
	db.log = db.log or {}
	db.log.engagements = db.log.engagements or {}
	db.log.heat = db.log.heat or {}
	db.log.duels = db.log.duels or {} -- [opponent class] = { w = wins, l = losses }
	ns.db, ns.P = db, db.profile
	ns.Fire("SR_READY")
end)

ns.On("PLAYER_LOGIN", function()
	if not ns.P then return end -- ADDON_LOADED never came: nothing to run on
	ns.Fire("SR_LOGIN")
	ns.print("v%s ready. |cffaaaaaa/sitrep|r opens the console.", ns.VERSION)
end)

---------------------------------------------------------------------------
-- Sensor health: which data feeds this client is actually giving us.
---------------------------------------------------------------------------
ns.feeds = {}
ns.FEED_ORDER = { "plates", "identity", "range", "position", "health", "damage", "auras", "combatlog", "net" }
ns.FEED_LABEL = {
	plates = "Nameplates", identity = "Unit identity", range = "Range checks",
	position = "Own position", health = "Enemy health", damage = "Damage numbers", auras = "Auras",
	combatlog = "Combat log", net = "Addon net",
}
function ns.Feed(id, state, note)
	local f = ns.feeds[id]
	if not f then f = {}; ns.feeds[id] = f end
	f.state, f.note = state, note
end

---------------------------------------------------------------------------
-- Reports: what a diagnostic command prints is also kept in SITREP_DB.reports
-- (written to disk on /reload or logout), since game chat cannot be copied.
---------------------------------------------------------------------------
-- quiet: the lines only go to the report, not to the chat.
function ns.Capture(name, fn, quiet)
	local lines, print_ = {}, ns.print
	ns.print = function(msg, ...)
		local text = select("#", ...) > 0 and format(msg, ...) or tostring(msg)
		lines[#lines + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		if not quiet then print_(msg, ...) end
	end
	local ok, err = pcall(fn)
	ns.print = print_
	if not ok then ns.error(err) end
	if SITREP_DB then
		SITREP_DB.reports = SITREP_DB.reports or {}
		SITREP_DB.reports[name] = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", version = ns.VERSION, lines = lines }
	end
	return lines
end

---------------------------------------------------------------------------
-- Profile export / import (also a manual backup while the beta forgets
-- SavedVariables between sessions).
---------------------------------------------------------------------------
local E = C_EncodingUtil
function ns.ExportProfile()
	if not (E and E.SerializeCBOR and E.EncodeBase64) then return nil, "encoding API missing" end
	local ok, blob = pcall(E.SerializeCBOR, ns.P)
	if not ok then return nil, blob end
	if E.CompressString then
		local ok2, z = pcall(E.CompressString, blob)
		if ok2 and z then blob = z end
	end
	return "SR1:" .. E.EncodeBase64(blob)
end

function ns.ImportProfile(str)
	if not (E and E.DeserializeCBOR and E.DecodeBase64) then return false, "encoding API missing" end
	str = (str or ""):gsub("%s", "")
	if str:sub(1, 4) ~= "SR1:" then return false, "not a SITREP profile string" end
	local ok, blob = pcall(E.DecodeBase64, str:sub(5))
	if not ok or not blob then return false, "bad base64" end
	if E.DecompressString then
		local ok2, raw = pcall(E.DecompressString, blob)
		if ok2 and raw then blob = raw end
	end
	local ok3, t = pcall(E.DeserializeCBOR, blob)
	if not ok3 or type(t) ~= "table" then return false, "corrupt profile" end
	SITREP_DB.profile = fill(t, ns.Defaults())
	ns.P = SITREP_DB.profile
	ns.Changed("*")
	return true
end

---------------------------------------------------------------------------
-- Slash commands and key bindings
---------------------------------------------------------------------------
_G.BINDING_HEADER_SITREP = "SITREP"
_G.BINDING_NAME_SITREP_REPORT = "Broadcast contact report"
_G.BINDING_NAME_SITREP_HUD = "Toggle tactical HUD"
_G.BINDING_NAME_SITREP_CONFIG = "Open SITREP console"
_G.BINDING_NAME_SITREP_QUESTNAV = "Navigate to the nearest quest / stop"
_G.BINDING_NAME_SITREP_QUESTLIST = "Quest tracker: only the chosen quest / all"
_G.BINDING_NAME_SITREP_CHAT = "Fold the chat away / show it"

-- Navigate to the nearest quest with a known place, or stop navigating.
function SITREP_QuestNav()
	local Q = ns.Quests
	if not (Q and ns.P) then return end
	if Q.selectedId then Q.Select(nil) return end
	for _, q in ipairs(Q.Sorted("distance")) do
		if q.target then Q.Select(q.id) ns.print("navigating to %s", q.title) return end
	end
	ns.print("no quest with a known place yet (SITREP learns it when an objective counts up)")
end

function _G.SITREP_Report(channel) if ns.Comms then ns.Comms.Report(channel) end end
function _G.SITREP_ToggleHUD() if ns.HUD then ns.HUD.Toggle() end end
function _G.SITREP_ToggleConfig() if ns.Config then ns.Config.Toggle() end end

local HELP = {
	"/sitrep — open the console",
	"/sitrep report [party|raid|say|guild] — broadcast a contact report",
	"/sitrep hud — show or hide the HUD",
	"/sitrep lock | unlock — lock HUD modules in place",
	"/sitrep sensors — print which data feeds this client gives",
	"/sitrep reset — restore every setting to doctrine defaults",
	"/sitrep debug — record 15 s of sensor diagnostics (then /reload to save them)",
	"/sitrep trackers — open the tracker icons page",
	"/sitrep buffs — list your buffs (exact names and IDs) and weapon enchants",
	"/sitrep weapon — what the client reports about your weapon enchants (raw)",
	"/sitrep tot — what the client reports for the target's-target health bar (colours, values)",
	"/sitrep auraprobe — which aura questions this client still answers in combat",
	"/sitrep rangeprobe — which item range checks answer for your target (precise distance out of combat)",
	"/sitrep quest — navigate to the nearest quest (again: stop)",
	"/sitrep quests — quest tracker: only the quest you navigate to, or all again",
	"/sitrep chat — fold the chat away (only tabs with new messages stay), or show it again",
	"/sitrep chat dock — every chat window pulled out of the tab bar back in as a tab",
	"/sitrep spawns — how long mobs took to come back (learned), and how far plates reach",
	"/sitrep ways — the ways walked (all characters): what this session noted, what is kept per map; export / import: share them (joined with yours)",
	"/sitrep mobs [name] — the bestiary: every mob seen (all characters), where, and which quests want it",
	"/sitrep flyprobe — why the quest arrow does or does not lead to a flight master (the quest you navigate to)",
	"/sitrep mapprobe — what lies on the world map's canvas (strata, levels): for marks hidden under the map",
	"/sitrep lootprobe — the loot window as the game has it (open one first): which slots are quest items",
	"/sitrep drops — how many kills each quest item took (learned, all characters)",
	"/sitrep spots — grinding spots on this map: where mobs come back fastest (all: every map)",
	"/sitrep npcprobe — the tooltip lines of your target and of the unit under the mouse, as the client gives them (NPC titles)",
	"/sitrep tough — how well geared players are (health against class and level): what was counted, what is known",
	"/sitrep route — what to do on this map in what order: quests your characters handed in before, and the ones in your log (go: the arrow to the first)",
	"/sitrep questprobe — what this client tells about quests and where they are",
	"/sitrep doctor — check everything SITREP needs from the game, and its own state (the first thing to run)",
	"/sitrep perf [seconds] — measure what SITREP costs per frame (default 60 s; /sitrep perf stop)",
	"/sitrep platesize — the nameplate size settings this client has, and a plate's real size",
	"/sitrep mapdump — every part on and round the minimap (to place stray buttons)",
	"/sitrep mouse — what takes the mouse where it is (an invisible frame over something?)",
	"/sitrep shiftprobe — what the client says about the druid forms' mana costs",
	"/sitrep castprobe — record 2 minutes of enemy casts and what SITREP made of them (then /reload)",
	"/sitrep recap — show the last death recap again",
	"/sitrep kicks — your interrupts this session: landed, missed, reaction, fakes seen",
	"/sitrep ideaprobe [stop] — 90 s: enemy heals and casts, creatures' spawn age and layer, enemy power (then /reload)",
	"/sitrep uidump — which of Blizzard's minimap, experience, bag, chat, action bar and micro menu frames this client has",
	"/sitrep platedump — list the parts of your target's nameplate (or the first on screen)",
	"/sitrep plateprobe — can SITREP restyle nameplates here (friendly and hostile)? Run near plates, in and out of combat",
}

SLASH_SITREP1, SLASH_SITREP2 = "/sitrep", "/sr"
SlashCmdList.SITREP = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if not ns.P then return end
	if cmd == "" or cmd == "config" then
		SITREP_ToggleConfig()
	elseif cmd == "report" then
		SITREP_Report(arg ~= "" and arg:upper() or nil)
	elseif cmd == "hud" then
		SITREP_ToggleHUD()
	elseif cmd == "lock" or cmd == "unlock" then
		ns.P.hud.locked = (cmd == "lock")
		ns.Changed("hud.locked")
		ns.print("HUD %s.", cmd == "lock" and "locked" or "unlocked: drag modules to move them")
	elseif cmd == "sensors" then
		for _, id in ipairs(ns.FEED_ORDER) do
			local f = ns.feeds[id]
			ns.print("%-16s %s %s", ns.FEED_LABEL[id], f and f.state or "?", f and f.note or "")
		end
	elseif cmd == "debug" then
		ns.Debug.Start()
	elseif cmd == "store" then
		-- the body of a settings macro: clicking it should explain, not do anything
		ns.print("this macro keeps your SITREP tracker icons across restarts (the beta client forgets addon settings). Keep it while you want them kept; switch it off in /sitrep trackers.")
	elseif cmd == "buffs" then
		if ns.Trackers then ns.Capture("buffs", ns.Trackers.DumpBuffs); ns.print("saved; /reload writes it to disk.") end
	elseif cmd == "rangeprobe" then
		if ns.Debug then ns.Debug.RangeProbe() end
	elseif cmd == "quest" then
		SITREP_QuestNav()
	elseif cmd == "quests" then
		SITREP_ToggleQuestList()
	elseif cmd == "chat" and arg == "dock" then
		local n = ns.Chat and ns.Chat.DockAll() or 0
		ns.print(n > 0 and "%d chat window(s) back in the tab bar." or "No chat window outside the tab bar.", n)
	elseif cmd == "chat" then
		SITREP_ToggleChat()
	elseif cmd == "questprobe" then
		if ns.Quests then ns.Quests.Probe() end
	elseif cmd == "doctor" then
		if ns.Doctor then ns.Doctor.Run() end
	elseif cmd == "perf" then
		if ns.Perf then
			if arg == "stop" then ns.Perf.Stop() else ns.Perf.Start(arg ~= "" and arg or nil) end
		end
	elseif cmd == "zenprobe" then
		if ns.Debug then ns.Debug.ZenProbe() end
	elseif cmd == "platesize" then
		if ns.Debug then ns.Debug.PlateSize() end
	elseif cmd == "mapdump" then
		if ns.Debug then ns.Debug.MapDump() end
	elseif cmd == "plateauras" then
		if ns.PlateAuras then ns.PlateAuras.Probe() end
	elseif cmd == "spawns" then
		if ns.Spawns then ns.Spawns.Report() end
	elseif cmd == "mobs" then
		if ns.Bestiary then ns.Bestiary.Report(arg) end
	elseif cmd == "flyprobe" then
		if ns.Travel then ns.Travel.Probe() end
	elseif cmd == "mapprobe" then
		if ns.QuestMap then ns.QuestMap.Probe() end
	elseif cmd == "ways" then
		if ns.Trails then
			if arg == "export" or arg == "import" then ns.Trails.Window(arg) else ns.Trails.Report() end
		end
	elseif cmd == "lootprobe" then
		if ns.Drops then ns.Drops.LootProbe() end
	elseif cmd == "drops" then
		if ns.Drops then ns.Drops.Report() end
	elseif cmd == "spots" then
		if ns.Spawns then ns.Spawns.SpotsReport(arg) end
	elseif cmd == "npcprobe" then
		ns.PlateHover.Probe()
	elseif cmd == "tough" then
		ns.Sensors.ToughReport()
	elseif cmd == "route" then
		if ns.Questbook then ns.Questbook.Report(arg) end
	elseif cmd == "barprobe" then
		if ns.Debug then ns.Debug.BarProbe() end
	elseif cmd == "mouse" then
		if ns.Debug then ns.Debug.MouseProbe() end
	elseif cmd == "shiftprobe" then
		if ns.Debug then ns.Debug.ShiftProbe() end
	elseif cmd == "kicks" then
		local I = ns.Incoming
		ns.print("this session: %s", I and I.KickLine(I.session) or "no interrupts yet")
		for key, f in pairs(I and I.fakes or {}) do
			local c = ns.Sensors.contacts[key]
			if f >= 2 then ns.print("  %s faked %d casts", c and c.name or key, f) end
		end
	elseif cmd == "recap" then
		local last = ns.Recap and (ns.Recap.last or (ns.db.log.deaths and ns.db.log.deaths[1]))
		if last and ns.RecapPanel then ns.RecapPanel.Show(last) else ns.print("no death recap yet.") end
	elseif cmd == "ideaprobe" then
		if ns.Debug then ns.Debug.IdeaProbe(arg) end
	elseif cmd == "castprobe" then
		if ns.Incoming then ns.Incoming.Probe()
		else ns.print("casts on you are not loaded: new files need a full restart of the game (not /reload).") end
	elseif cmd == "uidump" then
		if ns.Debug then ns.Debug.UIDump() end
	elseif cmd == "platedump" then
		if ns.Debug then ns.Debug.PlateDump() end
	elseif cmd == "plateprobe" then
		if ns.Debug then ns.Debug.PlateProbe() end
	elseif cmd == "auraprobe" then
		if ns.Trackers then ns.Capture("auraprobe", ns.Trackers.DumpOracle); ns.print("saved; /reload writes it to disk.") end
	elseif cmd == "tot" then
		if ns.Frames then ns.Capture("tot", ns.Frames.DumpTot); ns.print("saved; /reload writes it to disk.") end
	elseif cmd == "weapon" then
		if ns.Trackers then ns.Capture("weapon", ns.Trackers.DumpWeapon); ns.print("saved; /reload writes it to disk.") end
	elseif cmd == "trackers" then
		if ns.Config then ns.Config.Open("trackers") end
	elseif cmd == "reset" then
		ns.ResetProfile()
		ns.print("settings reset to the defaults (the preset layout).")
	else
		for _, line in ipairs(HELP) do ns.print(line) end
	end
end
