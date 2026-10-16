-- SITREP · Quest progress shared with the group
-- The client tells an addon nothing about other players' quest counts. Group
-- members who run SITREP tell each other: each sends its own counts over the
-- addon channel (prefix SITREP) when they change, and its whole log when someone
-- joins. Received: QS.party[name][questID] = { counts = { { have, need }, ... },
-- complete }. The quest tracker shows them per objective (up to 5 members).
-- Message: "Q1 <tab> questID <tab> have/need,have/need[ <tab> c]"; "-" instead of
-- the counts: the quest is gone from that log.

local ADDON, ns = ...
local read, plain = ns.read, ns.plain
local format = string.format

local QS = {}
ns.QuestShare = QS
QS.party = {}
QS.MAX = 5            -- members shown per objective
local PER_TICK = 2    -- messages sent per tick at most
local sent = {}       -- [questID] = what was sent last
local queue = {}

local function encode(q)
	local parts = {}
	for i, o in ipairs(q.objectives) do
		local need = o.need or 1
		parts[i] = format("%d/%d", o.have or (o.done and need or 0), need)
	end
	return table.concat(parts, ",") .. (q.complete and "\tc" or "")
end
QS.Encode = encode

-- Queue what changed (all: everything, for someone who just joined).
function QS.Sync(all)
	if not (ns.Comms and ns.Comms.AutoChannel()) then return end
	local seen = {}
	for _, q in ipairs(ns.Quests.List()) do
		if type(q.id) == "number" then
			local body = encode(q)
			seen[q.id] = true
			if all or sent[q.id] ~= body then
				queue[#queue + 1] = format("Q1\t%d\t%s", q.id, body)
				sent[q.id] = body
			end
		end
	end
	for id in pairs(sent) do
		if not seen[id] then
			queue[#queue + 1] = format("Q1\t%d\t-", id)
			sent[id] = nil
		end
	end
end

local function flush()
	if #queue == 0 then return end
	local channel = ns.Comms.AutoChannel()
	if not channel then queue = {} return end
	local L = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	if L and read(L) then return end
	for _ = 1, PER_TICK do
		local msg = table.remove(queue, 1)
		if not msg then break end
		pcall(C_ChatInfo.SendAddonMessage, ns.Comms.PREFIX, msg, channel)
	end
end

local function short(name) return Ambiguate and Ambiguate(name, "short") or (name:gsub("%-.*$", "")) end

function QS.Receive(text, sender)
	text, sender = plain(text), plain(sender)
	if type(text) ~= "string" or type(sender) ~= "string" or text:sub(1, 3) ~= "Q1\t" then return false end
	local who = short(sender)
	if who == read(UnitName, "player") then return true end
	local id, body, flag = text:match("^Q1\t(%d+)\t([^\t]*)\t?(.*)$")
	id = tonumber(id)
	if not id then return true end
	QS.party[who] = QS.party[who] or {}
	if body == "-" then
		QS.party[who][id] = nil
	else
		local counts = {}
		for have, need in body:gmatch("(%d+)/(%d+)") do counts[#counts + 1] = { tonumber(have), tonumber(need) } end
		QS.party[who][id] = { counts = counts, complete = flag == "c" }
	end
	ns.Fire("SR_QUESTS")
	return true
end

-- Group members with this quest: { { name, counts, complete }, ... }, by name, up to 5.
function QS.ForQuest(id)
	local list = {}
	for name, quests in pairs(QS.party) do
		local q = quests[id]
		if q then list[#list + 1] = { name = name, counts = q.counts, complete = q.complete } end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	while #list > QS.MAX do table.remove(list) end
	return list
end

-- Members who left the group are forgotten; someone new gets the whole log.
local members = 0
ns.On("GROUP_ROSTER_UPDATE", function()
	local inGroup = ns.Comms and ns.Comms.AutoChannel()
	if not inGroup then
		QS.party, sent, queue, members = {}, {}, {}, 0
		ns.Fire("SR_QUESTS")
		return
	end
	for name in pairs(QS.party) do
		if not (read(UnitInParty, name) or read(UnitInRaid, name)) then QS.party[name] = nil end
	end
	local n = read(GetNumGroupMembers) or 0
	if n > members then QS.Sync(true) end
	members = n
end)
ns.On("SR_QUESTS", function() QS.Sync(false) end)
ns.On("SR_TICK", function() flush() end)
ns.On("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
	if prefix == (ns.Comms and ns.Comms.PREFIX) then QS.Receive(text, sender) end
end)
