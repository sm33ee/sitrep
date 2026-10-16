-- SITREP · /sitrep doctor: is everything SITREP needs there, and working?
-- One command that looks at what the separate probes look at, and at SITREP's own
-- state: the client's frames and functions SITREP relies on, blocked actions and
-- errors of this session, the secure buttons (set as they should be), how often
-- the client keeps values secret, plates, quests, the group channel. Each check is
-- OK, WARN (something missing or odd: a feature may not work), FAIL (broken) or
-- INFO. The chat gets the count and the WARN/FAIL lines; the report "doctor" (on
-- /reload) has every line. Read it first when something does not work.

local ADDON, ns = ...
local read = ns.read
local format = string.format

local Doc = {}
ns.Doctor = Doc

local function has(path)
	local f = _G
	for part in path:gmatch("[^%.]+") do
		if type(f) ~= "table" then return false end
		f = f == _G and _G[part] or rawget(f, part)
	end
	return f ~= nil and f ~= _G
end

-- The checks: { section, function(add) } where add(status, text, ...).
local CHECKS = {}
local function check(section, fn) CHECKS[#CHECKS + 1] = { section, fn } end
Doc.CHECKS = CHECKS

check("client", function(add)
	local v, build, _, iface = read(GetBuildInfo)
	add("INFO", "SITREP %s on client %s.%s (%s), locale %s", ns.VERSION, tostring(v), tostring(build), tostring(iface),
		tostring(read(GetLocale)))
	add(ns.P and ns.P.enabled and "OK" or "WARN", "SITREP switched %s", ns.P and ns.P.enabled and "on" or "off")
	local unknown = {}
	for e, ok in pairs(ns.knownEvents) do if not ok then unknown[#unknown + 1] = e end end
	table.sort(unknown)
	add(#unknown == 0 and "OK" or "INFO", "events the client does not know: %s", #unknown > 0 and table.concat(unknown, " ") or "none")
end)

check("this session", function(add)
	local errs, n = {}, 0
	for e, c in pairs(ns.errorCounts) do errs[#errs + 1] = format("%dx %s", c, e); n = n + c end
	add(n == 0 and "OK" or "FAIL", "internal errors: %d%s", n, n > 0 and (" - " .. table.concat(errs, " | ")) or "")
	local b = ns.Debug and ns.Debug.session or {}
	local mine = {}
	for _, e in ipairs(b) do if e.addon == ADDON then mine[#mine + 1] = format("%s %s (%s)", e.kind, e.fn, e.combat) end end
	add(#mine == 0 and "OK" or "FAIL", "actions the client blocked for SITREP: %d%s", #mine,
		#mine > 0 and (" - " .. table.concat(mine, " | ")) or "")
end)

check("secret values", function(add)
	local T = ns.Targeting and ns.Targeting.stats
	if T then add("INFO", "who-targets-whom checks: %s plain, %s secret, %s refused", tostring(T.plain), tostring(T.secret), tostring(T.err)) end
	local hs = ns.Targeting and ns.Targeting.healStats
	if hs then add("INFO", "heals on enemies: %d seen, %d matched to a healer's cast", hs.heals, hs.matched) end
	local H = ns.Heals and ns.Heals.stats
	if H then add("INFO", "heal predictions: %d plain, %d secret", H.plain, H.secret) end
	local mana = read(UnitPower, "player", 0)
	add("INFO", "your mana right now: %s", mana and "plain" or "secret or none")
end)

check("blizzard frames", function(add)
	local need = {
		{ "MainActionBar", "the action bar layout (or MainMenuBar on older clients)", "MainMenuBar" },
		{ "MainMenuBarBackpackButton", "the bag button (it clicks Blizzard's backpack)" },
		{ "BagsBar", "hiding the bag bar" },
		{ "MicroMenuContainer", "hiding the micro menu", "MicroMenu" },
		{ "Minimap", "the square minimap" },
		{ "MinimapCluster.DielFrame", "the day / night moon in the map's corner" },
		{ "ChatFrame1", "the chat" },
		{ "StatusTrackingBarManager", "hiding Blizzard's experience bar", "MainStatusTrackingBarContainer" },
		{ "TooltipDataProcessor", "the hover info instead of Blizzard's tooltip" },
		{ "C_NamePlate.GetNamePlateForUnit", "the nameplates" },
		{ "C_QuestLog.GetQuestsOnMap", "quest positions from the game" },
		{ "GetQuestLogSpecialItemInfo", "quest items in the tracker" },
		{ "C_ChatInfo.SendAddonMessage", "sharing with the group" },
		{ "C_CurveUtil.EvaluateColorFromBoolean", "showing secret yes/no answers (the red caster box)" },
		{ "UnitHealthPercent", "the kill window in combat (health through a colour curve)" },
		{ "C_Container.GetContainerItemID", "finding the emergency items in your bags", "GetContainerItemID" },
	}
	for _, n in ipairs(need) do
		local ok = has(n[1]) or (n[3] and has(n[3]))
		add(ok and "OK" or "WARN", "%s: %s", n[1], ok and "there" or ("MISSING - " .. n[2]))
	end
end)

check("secure buttons", function(add)
	local bag = ns.Bags and ns.Bags.button
	if bag and _G.MainMenuBarBackpackButton then
		local ok = bag:GetAttribute("type1") == "click" and bag:GetAttribute("clickbutton1") == _G.MainMenuBarBackpackButton
		add(ok and "OK" or "FAIL", "bag button: %s", ok and "a secure click on Blizzard's backpack" or "NOT set as a secure click (bags would carry SITREP's taint)")
	end
	local list = ns.MicroMenu and ns.MicroMenu.list
	if list then
		local rows, broken = 0, 0
		for _, r in ipairs(list.rows or {}) do
			rows = rows + 1
			if r:GetAttribute("type") ~= "click" or not r:GetAttribute("clickbutton") then broken = broken + 1 end
		end
		add(broken == 0 and rows > 0 and "OK" or "FAIL", "MENU list: %d entries, %d without their secure click", rows, broken)
	end
	local EM = ns.Emergency
	if EM and EM.holder then
		local names, broken = {}, 0
		for _, b in ipairs(EM.buttons) do
			if b.itemID then
				names[#names + 1] = tostring(b.itemID)
				if b:GetAttribute("type") ~= "item" or b:GetAttribute("item") ~= "item:" .. b.itemID then broken = broken + 1 end
			end
		end
		add(broken == 0 and "OK" or "FAIL", "emergency items: %s%s", #names > 0 and table.concat(names, ", ") or "none in your bags",
			broken > 0 and (" - " .. broken .. " without their item") or "")
	end
	local QI = ns.QuestItems
	if QI then
		local shown, broken = 0, 0
		for _, b in ipairs(QI.buttons) do
			if b:IsShown() then
				shown = shown + 1
				if b:GetAttribute("type") ~= "item" or not b:GetAttribute("item") then broken = broken + 1 end
			end
		end
		add(broken == 0 and "OK" or "FAIL", "quest item icons: %d shown, %d without their item", shown, broken)
	end
end)

check("clicks", function(add)
	-- Blizzard's bar frames lie where the bars were: with SITREP's layout on they must take no mouse
	if ns.P and ns.P.ui.barLayout and ns.P.enabled then
		local bad = {}
		for _, n in ipairs({ "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }) do
			local f = _G[n]
			if type(f) == "table" and f.IsMouseEnabled and read(f.IsMouseEnabled, f) and read(f.IsShown, f) then bad[#bad + 1] = n end
		end
		add(#bad == 0 and "OK" or "FAIL", "Blizzard's empty bar frames take no clicks%s", #bad > 0 and (": NOT " .. table.concat(bad, " ")) or "")
	end
	local hit = _G.Minimap and rawget(_G.Minimap, "ZoomHitArea")
	if hit and ns.P.ui.minimap then
		add(read(hit.IsShown, hit) and "WARN" or "OK", "the invisible zoom area in the map's corner: %s", read(hit.IsShown, hit) and "still there" or "gone")
	end
end)

check("nameplates", function(add)
	local N = ns.Plates
	if not N then return end
	local cur, stale = 0, 0
	for _ in pairs(N.Current()) do cur = cur + 1 end
	for unit, s in pairs(N.skins) do if s.unit ~= unit then stale = stale + 1 end end
	add("INFO", "plates drawn by SITREP now: %d", cur)
	add(stale == 0 and "OK" or "FAIL", "stale plate entries (a reused frame drawn as another unit's): %d", stale)
	local cvars = {}
	for _, k in ipairs(N.SCALE_CVARS) do if N.GetCVar(k) ~= nil then cvars[#cvars + 1] = k end end
	local qm = 0
	for unit, sk in pairs(N.Current()) do
		if sk.isPlayer == false and ns.Quests and ns.Quests.MobOf(unit, sk.guid) then qm = qm + 1 end
	end
	add("INFO", "quest mobs on the plates now: %d", qm)
	local curveOK = UnitHealthPercent and N.KillCurve and N.KillCurve(0.2) and true or false
	add(curveOK and "OK" or "WARN", "kill window with secret health (in combat): %s", curveOK and "the client's health curve is there"
		or "NO health curve: only where health is readable")
	add("INFO", "plate size: slider %.0f%%%s; the game's size settings: %s", (ns.P.plates.scale or 1) * 100,
		(ns.P.plates.scale or 1) ~= 1 and " (SITREP's own bar)" or "", #cvars > 0 and table.concat(cvars, " ") or "none (Forever)")
end)

check("quests", function(add)
	local Q = ns.Quests
	if not Q then return end
	local CQ = C_QuestLog or {}
	add("INFO", "quest log: %s API", (CQ.GetInfo and CQ.GetNumQuestLogEntries) and "modern" or (GetQuestLogTitle and "classic" or "NO"))
	local kinds, none, n = {}, 0, 0
	for _, q in ipairs(Q.Sorted("distance")) do
		n = n + 1
		if q.target then kinds[q.target.kind] = (kinds[q.target.kind] or 0) + 1 else none = none + 1 end
	end
	add("INFO", "%d quests: %d with the game's position, %d learned, %d where you got them, %d without a place", n,
		kinds.exact or 0, kinds.learned or 0, kinds.giver or 0, none)
	if ns.Trails then
		local maps, cells, chars = ns.Trails.Size()
		add("INFO", "learned paths: %d maps, %d cells walked, about %d KB kept", maps, cells, math.ceil(chars / 1024))
	end
	if ns.Travel then
		local known, times = 0, 0
		for _ in pairs(ns.Travel.Known()) do known = known + 1 end
		for _ in pairs(ns.db.flight and ns.db.flight.times or {}) do times = times + 1 end
		add("INFO", "flight paths: %d known to this character, %d flights timed", known, times)
	end
	local here = Q.Here()
	local w = here and Q.MapSize(here.map)
	add(w and "OK" or "WARN", "map size in yards: %s", w and "known (distances in yards)" or "unknown here (directions only)")
end)

check("group", function(add)
	local C = ns.Comms
	if not C then return end
	local ch = C.AutoChannel()
	add("INFO", "group channel: %s; contacts sent %d, received %d", ch or "none (not in a group)", C.stats.sent, C.stats.received)
	local n = 0
	for _ in pairs(ns.QuestShare and ns.QuestShare.party or {}) do n = n + 1 end
	add("INFO", "group members sharing quest progress: %d", n)
end)

check("range", function(add)
	local S, D = ns.Sensors, ns.Data
	if not (S and S.KnownItems and D and D.RANGE_ITEMS) then return end
	local steps, withItem = 0, 0
	for _, kind in ipairs({ "harm", "friend" }) do
		for _, ids in pairs(D.RANGE_ITEMS[kind] or {}) do
			steps = steps + 1
			local known = S.KnownItems(ids)
			if #known > 0 then withItem = withItem + 1 end
		end
	end
	add(withItem > 0 and "OK" or "WARN", "item range checks: %d of %d distance steps have an item this client knows", withItem, steps)
end)

-- Run every check; the report has every line, the chat the count and the problems.
function Doc.Run()
	local counts = { OK = 0, WARN = 0, FAIL = 0, INFO = 0 }
	local problems = {}
	ns.Capture("doctor", function()
		for _, c in ipairs(CHECKS) do
			ns.print("== %s", c[1])
			local ok, err = pcall(c[2], function(status, text, ...)
				local line = format(text, ...)
				counts[status] = (counts[status] or 0) + 1
				ns.print("[%s] %s", status, line)
				if status == "WARN" or status == "FAIL" then problems[#problems + 1] = format("[%s] %s", status, line) end
			end)
			if not ok then
				counts.FAIL = counts.FAIL + 1
				ns.print("[FAIL] the check itself failed: %s", tostring(err))
				problems[#problems + 1] = "[FAIL] check " .. c[1] .. ": " .. tostring(err)
			end
		end
	end, true)
	Doc.last = counts
	ns.print("doctor: %d OK, %d WARN, %d FAIL. Details: /reload, report doctor.", counts.OK, counts.WARN, counts.FAIL)
	for _, p in ipairs(problems) do ns.print("  %s", p) end
	return counts, problems
end
