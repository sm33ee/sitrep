-- SITREP · Comms (ACT)
-- 1. Contact reports: one key press turns the picture into a single line for
--    party/raid chat — size, composition, distance, place, high-value target
--    and the engagement call.
-- 2. Shared picture: contacts are exchanged on an addon channel, so a group
--    knows who any member sees (who and whether in combat, not where).

local ADDON, ns = ...
local read = ns.read
local format, max, min = string.format, math.max, math.min

local C = {}
ns.Comms = C
C.PREFIX = "SITREP"
C.stats = { sent = 0, received = 0 }

---------------------------------------------------------------------------
-- Formatting helpers (also used by the HUD)
---------------------------------------------------------------------------
function C.RangeText(c)
	if c.exact and c.range then return format("%.0fy", c.range) end
	if c.lo and c.hi then
		if c.hi - c.lo <= 2 then return format("%.0fy", c.hi) end
		return format("%.0f-%.0fy", c.lo, c.hi)
	elseif c.lo and c.lo > 0 then
		return format(">%.0fy", c.lo)
	elseif c.range then
		return format("~%.0fy", c.range)
	end
	return "?"
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function autoChannel()
	if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end
C.AutoChannel = autoChannel

function C.Compose()
	local P, M = ns.P, ns.Model
	local pic = M.picture
	local recent, counts, order = {}, {}, {}
	local lo, hi = nil, nil
	for _, c in ipairs(M.byThreat) do
		if c.age and c.age < 15 then
			recent[#recent + 1] = c
			local cl = c.class or "UNKNOWN"
			if not counts[cl] then counts[cl] = 0; order[#order + 1] = cl end
			counts[cl] = counts[cl] + 1
			local cLo, cHi = c.lo or c.range, c.hi or c.range
			if cLo then lo = lo and min(lo, cLo) or cLo end
			if cHi then hi = hi and max(hi, cHi) or cHi end
		end
	end
	if #recent == 0 then return nil end
	table.sort(order, function(a, b) return counts[a] > counts[b] end)
	local comp = {}
	for _, cl in ipairs(order) do
		local name = ns.Data.NAME[cl] or "Unknown"
		comp[#comp + 1] = counts[cl] > 1 and (counts[cl] .. " " .. name) or name
	end
	local rangeText = "?"
	if lo and hi then rangeText = (hi - lo < 3) and format("%.0fy", hi) or format("%.0f-%.0fy", lo, hi) end
	local zone = read(GetRealZoneText) or "?"
	local sub = read(GetSubZoneText)
	if sub and sub ~= "" and sub ~= zone then zone = zone .. " - " .. sub end
	local hvt = ""
	local top = M.byPriority[1]
	if top and top.hvt then hvt = format("HVT %s %s | ", ns.Data.NAME[top.class] or "", top.name or "") end
	local tokens = {
		n = tostring(#recent),
		comp = table.concat(comp, ", "),
		range = rangeText,
		zone = zone,
		hvt = hvt,
		advice = ns.Data.ADVICE[pic.advice] and ns.Data.ADVICE[pic.advice].text or pic.advice,
		pwin = pic.pwin and format("P(win) %.0f%%", pic.pwin * 100) or "no estimate",
		ratio = pic.rho and format("%.1f:1", pic.rho) or "-",
	}
	local line = P.comms.template:gsub("{(%w+)}", function(k) return tokens[k] or "" end)
	return line
end

local function chatLocked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and read(C_ChatInfo.InChatMessagingLockdown) == true
end

function C.Report(override)
	local line = C.Compose()
	if not line then
		ns.print("no hostile contacts in the last 15 seconds.")
		return
	end
	local channel = override or (ns.P.comms.channel ~= "AUTO" and ns.P.comms.channel) or autoChannel()
	if not channel or channel == "SELF" or chatLocked() then
		ns.print("%s%s", chatLocked() and "(chat locked) " or "", line)
		return
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(send, line, channel)
	if not ok then ns.print("could not send to %s: %s", channel, tostring(err)) end
end

---------------------------------------------------------------------------
-- Shared picture over the addon channel
---------------------------------------------------------------------------
local function split(s, sep)
	local out, from = {}, 1
	while true do
		local a, b = s:find(sep, from, true)
		if not a then out[#out + 1] = s:sub(from) break end
		out[#out + 1] = s:sub(from, a - 1)
		from = b + 1
	end
	return out
end
C._split = split

-- C2: key, name, class, level, seconds since seen, in combat. (C1 carried a
-- position; older versions' messages are ignored.)
function C.Encode(c, now)
	return table.concat({ "C2", c.key, c.name or "?", c.class or "", tostring(c.level or 0),
		format("%.1f", now - (c.lastLive or now)), c.inCombat and "1" or "0" }, "\t")
end

function C.Decode(text)
	local f = split(text, "\t")
	if f[1] ~= "C2" or #f < 7 or f[2] == "" then return nil end
	return {
		key = f[2], name = f[3], class = f[4] ~= "" and f[4] or nil, level = tonumber(f[5]),
		age = tonumber(f[6]) or 0, combat = f[7] == "1",
	}
end

local function outgoingBlocked(channel)
	if chatLocked() then return true end
	local R = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
	if R then
		local blocked = read(R, channel)
		if blocked then return true end
	end
	return false
end

local tokens, lastShared = 0, {}
local function share(now, dt)
	local P = ns.P.comms
	tokens = min(P.shareRate * 2, tokens + dt * P.shareRate) -- bucket fills while idle
	local channel = autoChannel()
	if not (P.share and channel) then
		ns.Feed("net", "IDLE", P.share and "not in a group" or "sharing off")
		return
	end
	if outgoingBlocked(channel) then
		ns.Feed("net", "LOCKED", "client lockdown")
		return
	end
	ns.Feed("net", "LIVE", format("%d sent, %d received", C.stats.sent, C.stats.received))
	for _, c in ipairs(ns.Model.byThreat) do
		if tokens < 1 then break end
		-- each contact you see yourself, again every 4 s while you still see it
		if c.live then
			local last = lastShared[c.key]
			if not last or now - last.t > 4 then
				local ok = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, C.Encode(c, now), channel)
				if ok then
					tokens = tokens - 1
					C.stats.sent = C.stats.sent + 1
					lastShared[c.key] = { t = now }
				end
			end
		end
	end
end

local shareClock = 0
ns.On("SR_PICTURE", function(_, _, _, now)
	local dt = now - (shareClock > 0 and shareClock or now)
	shareClock = now
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then share(now, dt) end
end)

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if prefix ~= C.PREFIX then return end
	text, sender = ns.plain(text), ns.plain(sender)
	if not (text and sender) then return end
	local me = read(UnitName, "player")
	if me and Ambiguate and Ambiguate(sender, "short") == me then return end
	local msg = C.Decode(text)
	if not msg then return end
	C.stats.received = C.stats.received + 1
	ns.Sensors.Ingest(msg, sender, GetTime())
end)

ns.On("SR_LOGIN", function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, C.PREFIX)
	end
end)
