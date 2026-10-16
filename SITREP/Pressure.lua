-- SITREP · Pressure (DECIDE)
-- Incoming damage rate, spike detection and time-to-live, built on UNIT_COMBAT.
-- On Forever the player's health turns secret in combat, but UNIT_COMBAT amounts
-- stay plain. So health is tracked as a "shadow": the last plain reading, minus
-- damage taken, plus healing received. It snaps back to truth whenever the client
-- shows plain health again.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local max, min, floor = math.max, math.min, math.floor

local R = {}
ns.Pressure = R
R.spark = {}               -- 20 buckets of 0.5 s: last 10 seconds of incoming damage
R.fight = { dmg = 0, heal = 0, peak = 0, out = 0 }

local inc, heals, out = {}, {}, {} -- ring logs: { t, amount } pairs, flat
local lastSpike = 0

local function push(log, t, v)
	log[#log + 1] = t
	log[#log + 1] = v
end

local function prune(log, horizon)
	local n, keep = #log, 0
	for i = 1, n, 2 do
		if log[i] >= horizon then
			keep = keep + 1
			log[keep * 2 - 1], log[keep * 2] = log[i], log[i + 1]
		end
	end
	for i = keep * 2 + 1, n do log[i] = nil end
end

local function sumSince(log, since)
	local s = 0
	for i = 1, #log, 2 do
		if log[i] >= since then s = s + log[i + 1] end
	end
	return s
end
R._sumSince, R._push, R._prune = sumSince, push, prune

function R.HealthFrac()
	if R.max and R.max > 0 and R.shadow then return min(1, max(0, R.shadow / R.max)) end
	return 1
end

local function sync()
	local m = read(UnitHealthMax, "player")
	if m and m > 0 then R.max = m end
	local h = read(UnitHealth, "player")
	if h then
		R.shadow, R.synced = h, true
	else
		R.synced = false
	end
end

ns.On("UNIT_COMBAT", function(_, unit, action, _, amount)
	amount = plain(amount)
	if type(amount) ~= "number" or amount <= 0 then return end
	local now = GetTime()
	if unit == "player" then
		if action == "WOUND" then
			push(inc, now, amount)
			R.fight.dmg = R.fight.dmg + amount
			if R.shadow then R.shadow = max(0, R.shadow - amount) end
		elseif action == "HEAL" then
			push(heals, now, amount)
			R.fight.heal = R.fight.heal + amount
			if R.shadow then R.shadow = min(R.max or R.shadow + amount, R.shadow + amount) end
		end
	elseif unit == "target" and action == "WOUND" then
		push(out, now, amount)
		R.fight.out = R.fight.out + amount
	end
end)

function R.Update(now)
	local P = ns.P.pressure
	local horizon = now - max(P.long, 10)
	prune(inc, horizon); prune(heals, horizon); prune(out, horizon)
	sync()

	R.dpsShort = sumSince(inc, now - P.short) / P.short
	R.dpsLong = sumSince(inc, now - P.long) / P.long
	R.hps = sumSince(heals, now - P.short) / P.short
	R.outDps = sumSince(out, now - P.short) / P.short
	if R.dpsShort > R.fight.peak then R.fight.peak = R.dpsShort end

	local net = R.dpsShort - R.hps
	R.ttl = (net > 0 and R.shadow) and R.shadow / net or nil

	-- Spike: more than spikePct% of max health inside 1.5 seconds.
	local burst = sumSince(inc, now - 1.5)
	R.burstPct = R.max and R.max > 0 and burst / R.max * 100 or 0
	if R.burstPct >= P.spikePct and now - lastSpike > 3 then
		lastSpike = now
		ns.Fire("SR_SPIKE", R.burstPct, burst)
	end

	local spark = R.spark
	for b = 1, 20 do spark[b] = 0 end
	for i = 1, #inc, 2 do
		local b = 20 - floor((now - inc[i]) / 0.5)
		if b >= 1 and b <= 20 then spark[b] = spark[b] + inc[i + 1] end
	end
end

-- How hard you are being hit: "calm", "warn" or "danger", judged as damage per
-- second against your maximum health, so it scales with your gear.
R.LEVEL_COLOR = { warn = { 1.00, 0.62, 0.15 }, danger = { 1.00, 0.30, 0.30 } }
function R.Level(dps)
	if not (dps and dps > 0 and R.max and R.max > 0) then return "calm" end
	local pct = dps / R.max * 100
	local P = ns.P.pressure
	if pct >= P.dangerPct then return "danger" end
	if pct >= P.warnPct then return "warn" end
	return "calm"
end

ns.On("SR_TICK_PRE", function() R.Update(GetTime()) end)

ns.On("PLAYER_REGEN_DISABLED", function()
	local f = R.fight
	f.dmg, f.heal, f.peak, f.out, f.start = 0, 0, 0, 0, GetTime()
end)

ns.On("SR_LOGIN", sync)
