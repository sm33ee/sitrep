-- SITREP · Trackers: the list kept in macros

local ADDON, ns = ...
local K = ns.Kit
local read = ns.read
local format, floor, max = string.format, math.floor, math.max
local issecrettable = _G.issecrettable or function() return false end
local T = ns.Trackers
local spellName = T.SpellName

---------------------------------------------------------------------------
-- Settings mirror in macros (opt-in).
-- The beta writes SavedVariables on exit but never loads them, so every
-- restart starts from defaults. A macro created through the API survives a
-- restart, so the tracker list is kept in up to MIRROR_MACROS general macros,
-- named per character. Rules:
--   * reading always comes first: nothing is written until the macro list has
--     been read (it can arrive after login);
--   * settings that did load from SavedVariables win over the macro;
--   * macros cannot be edited in combat: a pending write waits for it to end;
--   * the body is a real slash command, so clicking the macro explains itself.
---------------------------------------------------------------------------
local MIRROR_DATA, MIRROR_MACROS = 225, 8
local MIRROR_ICON = "INV_Misc_Gear_01"
local mirror = { ready = false, found = 0, restored = 0, wrote = 0, note = "off" }
T.mirror = mirror

local function mirrorName(i)
	local who = tostring(read(UnitName, "player") or "") .. "-" .. tostring(read(GetRealmName) or "")
	local h = 5381
	for c = 1, #who do h = (h * 33 + who:byte(c)) % 2147483647 end
	return format("SRT%08x%d", h, i)
end
T.MirrorName = mirrorName

local KIND_CODE = { cd = "c", target = "t", self = "s", weapon = "w" }
local CODE_KIND = { c = "cd", t = "target", s = "self", w = "weapon" }
local HAND_CODE = { main = "m", off = "o", either = "b" }
local CODE_HAND = { m = "main", o = "off", b = "either" }

-- Aura names may hold any character; the separators are escaped.
local function esc(v) return (tostring(v or ""):gsub("[%%,;|]", function(c) return format("%%%02X", c:byte()) end)) end
local function unesc(v) return (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
-- split keeping empty fields ("a,,b" -> "a", "", "b")
local function split(str, sep)
	local out, from = {}, 1
	while true do
		local i = str:find(sep, from, true)
		if not i then out[#out + 1] = str:sub(from) return out end
		out[#out + 1] = str:sub(from, i - 1)
		from = i + 1
	end
end
local BORDER_CODE = { none = "n", red = "r", orange = "o", green = "g" }
local CODE_BORDER = { n = "none", r = "red", o = "orange", g = "green" }
local WHEN_CODE = { always = "a", combat = "c", nocombat = "o" }
local CODE_WHEN = { a = "always", c = "combat", o = "nocombat" }
local SCOPE_CODE = { class = "c", char = "h", all = "a" }
local CLASS_NUM = {}
for i, c in ipairs(ns.Data.CLASSES) do CLASS_NUM[c] = i end
local CODE_SCOPE = { c = "class", h = "char", a = "all" }
local OPT_CODE = { cd = "c", ready = "r", always = "a", enemy = "e", friend = "f", any = "y" }
local CODE_OPT = { c = "cd", r = "ready", a = "always", e = "enemy", f = "friend", y = "any" } -- "r": older lists

-- One line of plain characters: "1|on|c,6552,-110,160,36,100,r,0,a,c,0;..."
function T.Encode()
	local P = ns.P.trackers
	local parts = {}
	for _, it in ipairs(P.items) do
		local opt = it.kind == "cd" and (it.show or "cd") or it.kind == "target" and (it.targetType or "enemy") or "any"
		local fields = {
			KIND_CODE[it.kind], it.spell, floor(it.x), floor(it.y), floor(it.size), floor(it.alpha * 100 + 0.5),
			BORDER_CODE[it.border or "none"] or "n", floor(it.warn or 0), WHEN_CODE[it.when or "always"] or "a",
			OPT_CODE[opt] or "c", it.anySource and 1 or 0, it.invert and 1 or 0,
			it.kind == "weapon" and (HAND_CODE[it.hand or "main"] or "m") or "", esc(it.aura), it.auraId or "",
			it.countHits == true and "1" or it.countHits == false and "0" or "",
			-- whose icon, short: scope letter + class number ("c6": a shaman's), and
			-- the character only for "this character" icons
			(SCOPE_CODE[it.scope or "class"] or "c") .. (CLASS_NUM[it.class or ""] or ""),
			it.scope == "char" and esc(it.char) or "",
		}
		-- empty fields at the end are left out (Decode reads them as empty)
		while fields[#fields] == "" do fields[#fields] = nil end
		parts[#parts + 1] = table.concat(fields, ",")
	end
	return "2|" .. (P.enabled and "1" or "0") .. "|" .. table.concat(parts, ";")
end

function T.Decode(s)
	local v, en, body = (s or ""):match("^(%d+)|([01])|(.*)$")
	if v ~= "1" and v ~= "2" then return nil end
	local items = {}
	for chunk in body:gmatch("[^;]+") do
		local f = split(chunk, ",")
		local kind = CODE_KIND[f[1]]
		local spell = tonumber(f[2])
		if kind and spell and #f >= 11 then
			local it = {
				kind = kind, spell = spell, x = tonumber(f[3]) or 0, y = tonumber(f[4]) or 0,
				size = tonumber(f[5]) or 36, alpha = (tonumber(f[6]) or 100) / 100,
				border = CODE_BORDER[f[7]] or "none", warn = tonumber(f[8]) or 0, when = CODE_WHEN[f[9]] or "always",
				anySource = f[11] == "1",
			}
			local opt = CODE_OPT[f[10]]
			if kind == "cd" then it.show = opt or "cd" elseif kind == "target" then it.targetType = opt or "enemy" end
			it.invert = f[12] == "1"
			if it.show == "ready" then it.show, it.invert = "cd", true end
			-- version 1 aura icons showed while MISSING by default: same behaviour now is inverted
			if v == "1" and kind ~= "cd" then it.invert = not it.invert end
			if kind == "weapon" then it.hand = CODE_HAND[f[13] or ""] or "main" end
			if f[14] and f[14] ~= "" then it.aura = unesc(f[14]) end
			it.auraId = tonumber(f[15] or "")
			if f[16] == "1" then it.countHits = true elseif f[16] == "0" then it.countHits = false end
			-- whose icon (lists before 3.20 have none: claimed by the first class that knows it)
			local sc, cn = (f[17] or ""):match("^(%a?)(%d*)$")
			it.scope = CODE_SCOPE[sc or ""] or "class"
			it.class = ns.Data.CLASSES[tonumber(cn or "") or 0]
			if f[18] and f[18] ~= "" then it.char = unesc(f[18]) end
			it.name = spellName(spell)
			items[#items + 1] = it
		end
	end
	return { enabled = en == "1", items = items }
end

local function macroAPI()
	return CreateMacro and EditMacro and DeleteMacro and GetMacroBody and GetMacroIndexByName and true or false
end

local function readMirror()
	if not macroAPI() then return nil end
	local parts, n = {}, nil
	for i = 1, MIRROR_MACROS do
		local ok, idx = pcall(GetMacroIndexByName, mirrorName(i))
		if ok and idx and idx > 0 then
			local okB, body = pcall(GetMacroBody, idx)
			local k, total, data = tostring(okB and body or ""):match("^/sitrep store (%d+)/(%d+) (.-)%s*$")
			k, total = tonumber(k), tonumber(total)
			if k and data then parts[k], n = data, total end
		end
	end
	if not n then return nil end
	for i = 1, n do if not parts[i] then return nil end end -- incomplete: ignore
	return table.concat(parts, "", 1, n)
end

local function deleteMirror()
	if not macroAPI() then return end
	for i = MIRROR_MACROS, 1, -1 do
		local ok, idx = pcall(GetMacroIndexByName, mirrorName(i))
		if ok and idx and idx > 0 then pcall(DeleteMacro, idx) end
	end
end

local pendingWrite, writeAt = false, nil
local function writeMirror()
	pendingWrite, writeAt = false, nil
	local P = ns.P.trackers
	if not (P.mirror and mirror.ready) then return end
	if not macroAPI() then mirror.note = "this client has no macro API" return end
	if InCombatLockdown() then pendingWrite = true; mirror.note = "waiting for combat to end" return end
	local s = T.Encode()
	if #s > MIRROR_DATA * MIRROR_MACROS then mirror.note = "too many icons for the macros; the last saved copy was kept" return end
	local n = max(1, math.ceil(#s / MIRROR_DATA))
	for i = 1, MIRROR_MACROS do
		local name = mirrorName(i)
		local ok, idx = pcall(GetMacroIndexByName, name)
		idx = ok and idx or 0
		if i <= n then
			local body = format("/sitrep store %d/%d %s", i, n, s:sub((i - 1) * MIRROR_DATA + 1, i * MIRROR_DATA))
			if idx > 0 then
				pcall(EditMacro, idx, nil, nil, body)
			else
				local okC, made = pcall(CreateMacro, name, MIRROR_ICON, body, nil)
				if not okC or not made then mirror.note = "could not create a macro (are all general macro slots full?)" return end
			end
		elseif idx > 0 then
			pcall(DeleteMacro, idx)
		end
	end
	mirror.wrote = #s
	mirror.note = format("%d icons kept in %d macro%s", #P.items, n, n == 1 and "" or "s")
end
T.WriteMirror = writeMirror

function T.PersistSoon()
	if not (ns.P.trackers.mirror and mirror.ready) then return end
	writeAt = GetTime() + 1 -- debounce: dragging and sliders change a lot at once
end

function T.SetMirror(on)
	ns.P.trackers.mirror = on and true or false
	if on then
		mirror.ready = true
		writeMirror()
	elseif InCombatLockdown() then
		mirror.deleteAfterCombat = true
		mirror.note = "the macros go when combat ends"
	else
		deleteMirror()
		mirror.note = "off; macros removed"
	end
end

-- Read the macros once the client has them; restore if nothing else did.
local function mirrorLogin(final)
	if mirror.ready then return end
	local s = readMirror()
	if s then
		mirror.found = #s
		local P = ns.P.trackers
		P.mirror = true -- the macros existing is the opt-in
		if #P.items == 0 then
			local d = T.Decode(s)
			if d then
				for _, it in ipairs(d.items) do
					it.id = P.nextId
					P.nextId = P.nextId + 1
					P.items[#P.items + 1] = it
				end
				P.enabled = d.enabled
				P.schema = 2 -- Decode already speaks the current meaning
				mirror.restored = #d.items
				ns.print("restored %d tracker icon%s from your macros.", #d.items, #d.items == 1 and "" or "s")
			end
		end
		mirror.note = format("%d icons kept in macros", #P.items)
	end
	if s or final then
		mirror.ready = true
		T.LayoutAll()
	end
end
T.MirrorLogin = mirrorLogin

local loginAt
ns.On("SR_LOGIN", function()
	loginAt = GetTime()
	T.Migrate() -- before anything is restored from the macros
	mirrorLogin(false)
	T.LayoutAll()
end)
ns.On("UPDATE_MACROS", function() mirrorLogin(false) end)

-- one frame drives the debounced write and the "macros never came" deadline
local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", ns.Timed("trackers: mirror (clock)", function()
	local now = GetTime()
	if loginAt and not mirror.ready and now - loginAt > 5 then mirrorLogin(true) end
	if writeAt and now >= writeAt then writeMirror() end
end))

ns.On("PLAYER_REGEN_ENABLED", function()
	if pendingWrite then writeMirror() end
	if mirror.deleteAfterCombat then mirror.deleteAfterCombat = nil; deleteMirror(); mirror.note = "off; macros removed" end
end)
