-- SITREP · After-Action Review
-- Every fight that had hostile players in it is logged: where, against what,
-- the force ratio we predicted, and how it went. Wins (an honorable kill without
-- dying) and losses (death) are fed back into the engagement model, so its
-- P(win) curve converges on how YOU actually fight. Contact sightings per
-- subzone build a heat map of where the enemy operates.
--
-- Duels are logged separately. A duel ends with neither a kill nor a death, so
-- the result comes from the client's own system message ("X has defeated Y in a
-- duel"), matched with the localized global strings. Duels train their own P(win)
-- curve and build a win/loss record per opponent class.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local max = math.max

local A = {}
ns.AAR = A
A.session = { contacts = 0, wins = 0, losses = 0, breaks = 0, duelWins = 0, duelLosses = 0 }

local rec, finalizeAt

local function zone()
	local z = read(GetRealZoneText) or "?"
	local s = read(GetSubZoneText) or ""
	return z, s
end

local function short(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "short") end
	return (name:gsub("%-.*$", ""))
end

local function newRecord()
	local z, s = zone()
	return { t = read(time) or 0, start = GetTime(), zone = z, sub = s, sumX = 0, nX = 0, maxH = 0, maxF = 1,
		classes = {}, hk = 0, died = false }
end

---------------------------------------------------------------------------
-- Duel detection
---------------------------------------------------------------------------
-- You can only duel your own faction, so an attackable player of your own
-- faction that we can see right now is a duel opponent.
function A.DuelOpponent()
	local mine = ns.Sensors.self.faction
	if not mine then return nil end
	for _, c in pairs(ns.Sensors.contacts) do
		if c.live and not c.npc and c.faction == mine then return c end
	end
	return nil
end

function A.InDuel()
	return A.DuelOpponent() ~= nil
end

-- Turn a client format string ("%1$s has defeated %2$s in a duel") into a Lua
-- pattern plus the argument order of its captures.
local function toPattern(fmt)
	local order, n = {}, 0
	fmt = fmt:gsub("%%(%d)%$s", function(i) return "\1" .. i .. "\1" end)
	fmt = fmt:gsub("%%s", function() n = n + 1; return "\1" .. n .. "\1" end)
	fmt = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	fmt = fmt:gsub("\1(%d)\1", function(i) order[#order + 1] = tonumber(i); return "(.+)" end)
	return "^" .. fmt .. "$", order
end
A._toPattern = toPattern

-- In both strings argument 1 is the winner and argument 2 the loser.
local DUEL_PATTERNS
local function duelPatterns()
	if DUEL_PATTERNS then return DUEL_PATTERNS end
	DUEL_PATTERNS = {}
	local formats = {
		_G.DUEL_WINNER_KNOCKOUT or "%1$s has defeated %2$s in a duel",
		_G.DUEL_WINNER_RETREAT or "%2$s has fled from %1$s in a duel",
	}
	for _, f in ipairs(formats) do
		local pat, order = toPattern(f)
		DUEL_PATTERNS[#DUEL_PATTERNS + 1] = { pat = pat, order = order }
	end
	return DUEL_PATTERNS
end

-- Returns winner, loser (short names) if the text is a duel result.
function A.ParseDuel(text)
	for _, p in ipairs(duelPatterns()) do
		local caps = { text:match(p.pat) }
		if #caps == #p.order and #caps > 0 then
			local args = {}
			for k, i in ipairs(p.order) do args[i] = caps[k] end
			return short(args[1]), short(args[2])
		end
	end
	return nil
end

local function classOf(name, fallback)
	for _, c in pairs(ns.Sensors.contacts) do
		if c.name and short(c.name) == name then return c.class end
	end
	return fallback
end

ns.On("CHAT_MSG_SYSTEM", function(_, text)
	text = plain(text)
	if type(text) ~= "string" then return end
	local winner, loser = A.ParseDuel(text)
	if not winner then return end
	local me = read(UnitName, "player")
	if not me or (winner ~= me and loser ~= me) then return end -- someone else's duel
	local won = winner == me
	local opponent = won and loser or winner
	local result = { won = won, opponent = opponent, class = classOf(opponent, rec and rec.duel and rec.duel.class) }
	ns.Fire("SR_DUEL_RESULT", result)
	if rec then
		rec.duelResult = result
	else
		-- Over before combat began (a forfeit or a flee): log it on its own.
		rec = newRecord()
		rec.duelResult, rec.standalone = result, true
		A.Finalize()
	end
end)

---------------------------------------------------------------------------
-- Engagement recording
---------------------------------------------------------------------------
ns.On("SR_NEW_CONTACT", function(_, c)
	A.session.contacts = A.session.contacts + 1
	local z, s = zone()
	local key = s ~= "" and (z .. " / " .. s) or z
	local heat = ns.db.log.heat
	heat[key] = (heat[key] or 0) + 1
end)

ns.On("PLAYER_REGEN_DISABLED", function()
	if rec and finalizeAt then A.Finalize() end
	rec = newRecord()
	ns.Fire("SR_COMBAT_START", rec)
end)

ns.On("SR_PICTURE", function(_, list, pic)
	if not rec or finalizeAt then return end
	if pic.x then
		rec.sumX, rec.nX = rec.sumX + pic.x, rec.nX + 1
		rec.maxH = max(rec.maxH, pic.nH)
		rec.maxF = max(rec.maxF, pic.nF)
		rec.firstP = rec.firstP or pic.pwin
	end
	local opp = A.DuelOpponent()
	if opp then rec.duel = { name = opp.name, class = opp.class } end
	for i = 1, #list do
		local c = list[i]
		if c.age < 5 and c.class then rec.classes[c.key] = c.class end
	end
end)

ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function()
	if rec then rec.hk = rec.hk + 1 end
end)

ns.On("PLAYER_DEAD", function()
	if rec then rec.died = true end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	if rec then finalizeAt = GetTime() + 2 end -- wait for late honor and duel messages
end)

ns.On("SR_TICK", function()
	if finalizeAt and GetTime() >= finalizeAt then A.Finalize() end
end)

local function recordDuel(r)
	local res = r.duelResult
	r.kind = "duel"
	r.opponent, r.oppClass = res.opponent, res.class or (r.duel and r.duel.class)
	if res.won then r.outcome, r.y = "WIN", 1 else r.outcome, r.y = "LOSS", 0 end
	if r.x then r.p = ns.Model.Calibrate(r.x, r.y, "duel") end
	local s = A.session
	if res.won then s.duelWins = s.duelWins + 1 else s.duelLosses = s.duelLosses + 1 end
	if r.oppClass then
		local book = ns.db.log.duels
		local e = book[r.oppClass] or { w = 0, l = 0 }
		book[r.oppClass] = e
		if res.won then e.w = e.w + 1 else e.l = e.l + 1 end
	end
end

function A.Finalize()
	local r = rec
	if not r then return end
	-- A duel whose result has not arrived yet gets one more short wait.
	if r.duel and not r.duelResult and not r.awaitingDuel then
		r.awaitingDuel = true
		finalizeAt = GetTime() + 3
		return
	end
	rec, finalizeAt = nil, nil
	if r.nX == 0 and not r.duelResult then return end -- no hostile players seen: a PvE fight
	local fight = ns.Pressure.fight
	r.dur = GetTime() - r.start
	if r.standalone then r.dmg, r.healIn, r.peak = 0, 0, 0
	else r.dmg, r.healIn, r.peak = fight.dmg, fight.heal, fight.peak end
	r.x = r.nX > 0 and r.sumX / r.nX or nil
	local comp = {}
	for _, cl in pairs(r.classes) do comp[cl] = (comp[cl] or 0) + 1 end
	r.comp, r.classes = comp, nil

	if r.duelResult then
		recordDuel(r)
	elseif r.duel then
		r.kind, r.outcome = "duel", "BREAK" -- no result: out of bounds or cancelled
		A.session.breaks = A.session.breaks + 1
	else
		if r.died then r.outcome, r.y = "LOSS", 0
		elseif r.hk > 0 then r.outcome, r.y = "WIN", 1
		else r.outcome = "BREAK" end
		if r.y and r.x then r.p = ns.Model.Calibrate(r.x, r.y) end
		local s = A.session
		if r.outcome == "WIN" then s.wins = s.wins + 1 elseif r.outcome == "LOSS" then s.losses = s.losses + 1 else s.breaks = s.breaks + 1 end
	end
	r.duel, r.duelResult, r.awaitingDuel, r.standalone = nil, nil, nil, nil
	-- the kick trainer's count for this fight
	local k = ns.Incoming and ns.Incoming.fight
	if k and k.landed + k.missed + k.fakes > 0 then r.kicks = { landed = k.landed, react = k.react, missed = k.missed, fakes = k.fakes } end

	local log = ns.db.log.engagements
	table.insert(log, 1, r)
	for i = #log, ns.P.log.keep + 1, -1 do log[i] = nil end
	ns.Fire("SR_AAR", r)
end
