-- SITREP · Model (ORIENT + DECIDE)
-- Scores each contact twice:
--   threat   — how dangerous it is to ME right now (matchup, level, distance,
--              whether it is targeting me or casting, freshness of the sighting)
--   priority — how much it is worth killing FIRST (healer value × how fast it
--              drops × whether we can reach it)
-- Then sizes up the whole fight with Lanchester's square law: a force's fighting
-- strength grows with the square of its numbers, so 3 v 2 is not 1.5:1 but 2.25:1.
-- The logistic mapping from force ratio to P(win) calibrates itself against the
-- fights you actually have (see AAR.lua). Duels keep their own curve: a 1v1 on
-- equal terms is a skill check and would skew the group-fight model.

local ADDON, ns = ...
local exp, log, sqrt, max = math.exp, math.log, math.sqrt, math.max
local sort, wipe = table.sort, wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local M = {}
ns.Model = M
M.byThreat, M.byPriority = {}, {}
M.picture = { rho = nil, pwin = nil, advice = "CLEAR", nF = 1, nH = 0, pF = 0, pH = 0, losses = 0 }

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
M.clamp = clamp

function M.LevelFactor(their, mine, base)
	if not their then return 1 end
	if their <= 0 then return 3 end -- "??": at least ten levels above
	return clamp(base ^ (their - (mine or 60)), 0.25, 3)
end

-- Proximity weight: 1 inside 5 yd, falling off exponentially; unknown range = 0.45.
function M.Proximity(range, falloff)
	if not range then return 0.45 end
	return exp(-max(0, range - 5) / falloff)
end

-- Weight of an old sighting: 1 when fresh, ~0.37 after a third of the memory span.
function M.Freshness(age, memory)
	return exp(-(age or 0) / max(1, memory / 3))
end

-- Engagement-zone geometry for one contact: can it hit me, can I hit it, and
-- how long until it can (from the closure rate).
function M.Envelope(c)
	local R = ns.Data.REACH[c.class] or ns.Data.REACH_DEFAULT
	local threatAt = R.threat
	local d = c.range
	-- Certain when the whole bracket is inside / outside; else judged by the estimate.
	if c.hi and c.hi <= threatAt then c.inTheirReach = true
	elseif c.lo and c.lo > threatAt then c.inTheirReach = false
	else c.inTheirReach = d ~= nil and d <= threatAt end
	local mine = ns.Sensors.myReach or 5
	if c.hi and c.hi <= mine then c.inMyReach = true
	elseif c.lo and c.lo > mine then c.inMyReach = false
	else c.inMyReach = d ~= nil and d <= mine end
	c.ttr = nil
	if c.closing and c.closing < -1 and d and not c.inTheirReach then
		c.ttr = (d - threatAt) / -c.closing
	end
	return c
end

function M.ScoreContact(c, me, P)
	local T = P.threat
	local class = c.class
	local lvl = M.LevelFactor(c.level, me.level, T.levelBase)
	local row = T.matrix[me.class or "WARRIOR"]
	local matchup = row and class and row[class] or 1
	local power = class and T.power[class] or 1
	local prox = M.Proximity(c.range, T.falloff)
	local fresh = M.Freshness(c.age, P.sensors.memory)
	local closingFast = c.closing and c.closing <= -3
	local behaviour = (c.targetingMe and T.targetingMe or 1) * (c.casting and T.casting or 1) * (c.inCombat and T.inCombat or 1)
		* (closingFast and T.closing or 1) * (c.inTheirReach and T.inReach or 1)
	c.threat = 100 * power * matchup * lvl * prox * behaviour * fresh

	local value = class and T.hvt[class] or 1
	local exposure = class and ns.Data.EXPOSURE[class] or 1
	local reach = c.live and 1 or 0.5
	c.priority = 100 * value * exposure * (1 / sqrt(lvl)) * (0.5 + 0.5 * prox) * reach * fresh
	return c
end

-- Lanchester square law with heterogeneous units: strength = N · Σq.
function M.Engagement(friends, hostiles, me, P)
	local T, E = P.threat, P.engage
	local sumF, nF = 0, 0
	local classesF = {}
	for i = 1, #friends do
		local f = friends[i]
		local q = (f.class and T.power[f.class] or 1) * M.LevelFactor(f.level, me.level, T.levelBase) * clamp(f.hp or 1, 0.05, 1)
		sumF, nF = sumF + q, nF + 1
		if f.class then classesF[#classesF + 1] = f.class end
	end
	local sumH, nH = 0, 0
	for i = 1, #hostiles do
		local h = hostiles[i]
		if not h.range or h.range <= E.radius then
			local w = M.Freshness(h.age, P.sensors.memory)
			-- Average matchup of this hostile against everyone on our side.
			local m, k = 0, 0
			for j = 1, #classesF do
				local row = T.matrix[classesF[j]]
				if row and h.class and row[h.class] then m, k = m + row[h.class], k + 1 end
			end
			m = k > 0 and m / k or 1
			-- a well geared enemy (more health than its class and level have on average) counts more
			local tough = h.tough and clamp(h.tough, 0.7, 1.5) or 1
			local q = (h.class and T.power[h.class] or 1) * M.LevelFactor(h.level, me.level, T.levelBase) * m * tough
			sumH, nH = sumH + q * w, nH + w
		end
	end
	local pic = M.picture
	local duel = ns.AAR and ns.AAR.InDuel() or false
	local cal = duel and P.duel or E
	pic.duel = duel
	pic.nF, pic.nH = nF, nH
	pic.pF, pic.pH = nF * sumF, nH * sumH
	if nH < 0.05 then
		pic.rho, pic.pwin, pic.losses, pic.x = nil, nil, 0, nil
		pic.advice = "CLEAR"
		return pic
	end
	local rho = pic.pF / max(pic.pH, 1e-6)
	local x = log(rho)
	pic.rho, pic.x = rho, x
	pic.pwin = 1 / (1 + exp(-(cal.k * x + cal.bias)))
	-- Square-law survivors if we win: A_end = A·sqrt(1 - 1/rho).
	pic.losses = rho > 1 and nF * (1 - sqrt(1 - 1 / rho)) or nF
	if rho >= E.engageAt then pic.advice = "ENGAGE"
	elseif rho >= E.contestAt then pic.advice = "CONTEST"
	elseif rho >= E.holdAt then pic.advice = "HOLD"
	else pic.advice = "BREAK" end
	return pic
end

-- One gradient step of logistic regression on a finished fight.
-- x = mean log force ratio during the fight, y = 1 win / 0 loss.
-- which = "duel" trains the duel curve; anything else the group-fight curve.
function M.Calibrate(x, y, which)
	local E = which == "duel" and ns.P.duel or ns.P.engage
	local G = ns.P.engage -- learning rate and the on/off switch are shared
	local p = 1 / (1 + exp(-(E.k * x + E.bias)))
	local err = y - p
	E.n = (E.n or 0) + 1
	E.brier = (E.brier or 0) + ((p - y) ^ 2 - (E.brier or 0)) / E.n
	if G.autoCal then
		E.k = clamp(E.k + G.lr * err * x, 0.5, 6)
		E.bias = clamp(E.bias + G.lr * err, -2, 2)
	end
	return p
end

local function byThreat(a, b) return a.threat > b.threat end
local function byPriority(a, b) return a.priority > b.priority end

ns.On("SR_SENSED", function(_, list, now)
	local P, me = ns.P, ns.Sensors.self
	local bt, bp = wipe(M.byThreat), wipe(M.byPriority)
	for i = 1, #list do
		M.Envelope(list[i])
		local c = M.ScoreContact(list[i], me, P)
		c.hvt = false
		bt[#bt + 1], bp[#bp + 1] = c, c
	end
	sort(bt, byThreat)
	sort(bp, byPriority)
	local top = bp[1]
	if top and top.live and top.priority >= P.threat.hvtMin then
		top.hvt = true
		if M.hvtKey ~= top.key then
			M.hvtKey = top.key
			ns.Fire("SR_HVT", top)
		end
	else
		M.hvtKey = nil
	end

	local pic = M.Engagement(ns.Sensors.Friendlies(), list, me, P)
	local pr = ns.Pressure
	if pr and me.combat and pr.ttl and pr.ttl < P.pressure.ttlWarn then pic.advice = "DEFEND" end
	if pic.advice ~= M.lastAdvice then
		ns.Fire("SR_ADVICE", pic.advice, M.lastAdvice)
		M.lastAdvice = pic.advice
	end
	for i = 1, #bt do
		local c = bt[i]
		if c.targetingMe and not c.wasTargeting then ns.Fire("SR_TARGETED", c) end
		c.wasTargeting = c.targetingMe
		-- Early warning: closing and inside its reach within 3 s. Re-arms once it opens out.
		if c.ttr and c.ttr <= 3 and not c.warnedClosing then
			c.warnedClosing = true
			ns.Fire("SR_CLOSING", c)
		elseif c.closing and c.closing > 1 then
			c.warnedClosing = nil
		end
	end
	ns.Fire("SR_PICTURE", M.byThreat, pic, now)
end)
