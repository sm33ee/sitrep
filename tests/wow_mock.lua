-- Minimal World of Warcraft: Forever client emulator for running SITREP headless.
-- Frames accept any method (unknown ones are no-ops); the parts SITREP's logic
-- depends on (sizes, scripts, events, visibility, text) behave. Units, nameplates
-- and range checks are driven by a scenario table. Secret values throw on any
-- comparison or arithmetic, like the real client.

local M = {}
M.now = 1000
M.prints, M.chat, M.addonMsgs = {}, {}, {}
M.scenario = { units = {}, me = {}, group = {} }
M.objects = {}

---------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------
local SecretMT = {}
local function boom() error("attempt to use a secret value", 2) end
for _, k in ipairs({ "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__len", "__eq" }) do
	SecretMT[k] = boom
end
SecretMT.__index = boom
SecretMT.__tostring = function() return "<secret>" end
-- a secret may carry the real value, which only the emulated client may look at
M.secretOf = setmetatable({}, { __mode = "k" })
function M.Secret(v)
	local s = setmetatable({}, SecretMT)
	if v ~= nil then M.secretOf[s] = v end
	return s
end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SecretMT end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED",
	"NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "UNIT_COMBAT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"CHAT_MSG_ADDON", "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD", "GROUP_ROSTER_UPDATE",
	"CHAT_MSG_SYSTEM", "DUEL_REQUESTED", "DUEL_FINISHED", "FORBIDDEN_NAME_PLATE_UNIT_ADDED", "FORBIDDEN_NAME_PLATE_UNIT_REMOVED",
	"PLAYER_TARGET_CHANGED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_AURA", "UNIT_HEAL_PREDICTION", "UNIT_PET", "UPDATE_MACROS", "SPELL_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "PLAYER_XP_UPDATE", "UNIT_PET_EXPERIENCE", "UNIT_LEVEL", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "BAG_UPDATE", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "QUEST_LOG_UPDATE", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED", "UPDATE_BINDINGS",
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_SAY",
	"CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET",
	"BAG_UPDATE_COOLDOWN", "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED", "TAXIMAP_OPENED", "PLAYER_LOGOUT", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_SHAPESHIFT_FORMS", "UNIT_FACTION",
	"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "CURSOR_CHANGED", "PET_BAR_UPDATE",
	"UNIT_CONNECTION", "UNIT_THREAT_SITUATION_UPDATE", "RAID_TARGET_UPDATE" }) do
	KNOWN_EVENTS[e] = true
end
M.eventFrames = {}

local noop = function() end
local Methods = {}
-- Widget API methods are CamelCase; anything else is a plain field (nil if unset).
local Obj = { __index = function(_, k)
	if type(k) == "string" and k:match("^%u") then return Methods[k] or noop end
	return nil
end }

local function new(kind, parent)
	local o = setmetatable({ _kind = kind, _parent = parent, _scripts = {}, _shown = true }, Obj)
	M.objects[#M.objects + 1] = o
	return o
end

function Methods.SetSize(s, w, h) s._w, s._h = w, h end
function Methods.GetObjectType(s) return rawget(s, "_kind") end
function Methods.SetWidth(s, w) s._w = w end
function Methods.SetHeight(s, h) s._h = h end
function Methods.GetWidth(s) return rawget(s, "_w") or 100 end
function Methods.GetHeight(s) return rawget(s, "_h") or 20 end
-- edges: a frame placed with _x/_y (bottom left) and its size; the screen is UIParent
function Methods.GetLeft(s) return rawget(s, "_x") or 0 end
function Methods.GetBottom(s) return rawget(s, "_y") or 0 end
function Methods.GetRight(s) return (rawget(s, "_x") or 0) + s:GetWidth() end
function Methods.GetTop(s) return (rawget(s, "_y") or 0) + s:GetHeight() end
function Methods.GetNumPoints(s) return #(rawget(s, "_points") or {}) end
function Methods.ClearAllPoints(s) s._points = {} end
function Methods.GetCenter(s) return rawget(s, "_cx"), rawget(s, "_cy") end
function Methods.GetEffectiveScale() return 1 end
function Methods.GetFrameLevel(s) return rawget(s, "_level") or 1 end
function Methods.SetFrameLevel(s, l) s._level = l end
function Methods.SetClampRectInsets(s, l, r, t, b) s._clamp = { l, r, t, b } end
function Methods.GetClampRectInsets(s) local c = rawget(s, "_clamp") or { 0, 0, 0, 0 } return c[1], c[2], c[3], c[4] end
function Methods.GetStringHeight() return 12 end
-- a text's width: 7 px a visible character (colour codes left out)
function Methods.GetStringWidth(s)
	local t = rawget(s, "_text")
	if type(t) ~= "string" then return 0 end
	return #(t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 7
end
function Methods.IsForbidden() return false end
function Methods.GetName(s) return rawget(s, "_name") end
function Methods.GetParent(s) return rawget(s, "_parent") end
function Methods.SetParent(s, p) s._parent = p end
function Methods.SetScrollChild(s, c) s._scrollChild = c end
function Methods.SetVerticalScroll(s, y) s._vscroll = y end
function Methods.GetVerticalScroll(s) return rawget(s, "_vscroll") or 0 end
function Methods.IsPlaying() return false end
function Methods.HasFocus() return false end
function Methods.SetText(s, t) s._text = t end
function Methods.SetFormattedText(s, fmt, ...) s._text = string.format(fmt, ...) end -- throws on secrets, like an unsafe path would
function Methods.SetAlpha(s, a) s._alpha = a end
function Methods.GetAlpha(s) return rawget(s, "_alpha") or 1 end
function Methods.EnableMouse(s, v) s._mouse = v end
function Methods.IsMouseEnabled(s) return rawget(s, "_mouse") or false end
function Methods.GetText(s) return rawget(s, "_text") or "" end
-- OnShow / OnHide fire on a state change, as in the client
local function setShown(s, v)
	local was = rawget(s, "_shown")
	s._shown = v
	if was ~= v then
		local fn = s._scripts[v and "OnShow" or "OnHide"]
		if fn then fn(s) end
	end
end
-- Protected frames (secure templates, and any frame a secure frame is anchored
-- to) may not be shown or hidden by an addon in combat: a blocked action, counted
-- in M.blockedCalls (the client refuses it: nothing changes).
M.blockedLog = {}
local function blocked(s, what)
	if not (M.scenario.me.combat and (rawget(s, "_secure") or rawget(s, "_anchorProtected") or rawget(s, "_protected"))) then return false end
	if rawget(s, "_shown") == (what ~= "Hide") then return false end -- no change asked
	M.blockedCalls = M.blockedCalls + 1
	M.blockedLog[#M.blockedLog + 1] = tostring(rawget(s, "_name") or rawget(s, "_kind")) .. ":" .. what
	if os.getenv("TRACE_BLOCKED") then print(debug.traceback("BLOCKED " .. tostring(rawget(s, "_name")) .. ":" .. what, 2)) end
	return true
end
function Methods.Show(s) if not blocked(s, "Show") then setShown(s, true) end end
function Methods.Hide(s) if not blocked(s, "Hide") then setShown(s, false) end end
function Methods.SetShown(s, v) if not blocked(s, v and "Show" or "Hide") then setShown(s, v and true or false) end end
function Methods.IsProtected(s)
	local p = rawget(s, "_secure") or rawget(s, "_anchorProtected") or rawget(s, "_protected") or false
	return p and true or false, rawget(s, "_secure") and true or false
end
function Methods.SetAllPoints(s, rel)
	if type(rel) == "table" and rawget(s, "_secure") then rel._anchorProtected = true end
end
function Methods.IsShown(s) return s._shown end
function Methods.IsVisible(s)
	if not rawget(s, "_shown") then return false end
	local parent = rawget(s, "_parent")
	return parent == nil or parent:IsVisible()
end
function Methods.SetScript(s, name, fn) s._scripts[name] = fn end
function Methods.GetScript(s, name) return s._scripts[name] end
function Methods.HookScript(s, name, fn)
	local prev = s._scripts[name]
	s._scripts[name] = function(...) if prev then prev(...) end fn(...) end
end
function Methods.RegisterEvent(s, e)
	if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
	M.eventFrames[e] = M.eventFrames[e] or {}
	table.insert(M.eventFrames[e], s)
end
local function region(kind, s)
	local r = new(kind, s)
	s._regions = rawget(s, "_regions") or {}
	table.insert(s._regions, r)
	return r
end
function Methods.CreateTexture(s) return region("Texture", s) end
function Methods.CreateFontString(s) return region("FontString", s) end
function Methods.GetRegions(s) return unpack(rawget(s, "_regions") or {}) end
function Methods.GetChildren(s) return unpack(rawget(s, "_kids") or {}) end
function Methods.CreateLine(s) return new("Line", s) end
function Methods.SetStartPoint(s, _, _, x, y) s._from = { x, y } end
function Methods.SetEndPoint(s, _, _, x, y) s._to = { x, y } end
function Methods.CreateAnimationGroup(s) return new("AnimationGroup", s) end
function Methods.CreateAnimation(s) return new("Animation", s) end
function Methods.SetFont(s, path, size, flags)
	assert(type(path) == "string" and type(size) == "number", "SetFont needs path and size")
	s._font = { path, size, flags }
end
function Methods.SetPoint(s, point, ...)
	assert(type(point) == "string", "SetPoint needs a point name")
	local rel = ...
	if type(rel) == "table" then assert(getmetatable(rel) == Obj, "SetPoint relative frame must be a region") end
	if type(rel) == "table" and rawget(s, "_secure") then rel._anchorProtected = true end -- (see blocked)
	s._points = rawget(s, "_points") or {}
	table.insert(s._points, { point, ... })
	if #s._points > 5 then table.remove(s._points, 1) end -- a region holds at most a few
end
function Methods.GetPoint(s, i)
	local p = (rawget(s, "_points") or {})[i or 1]
	if p then return unpack(p) end
	return "CENTER", nil, "CENTER", 0, 0
end
function Methods.SetVertexColor(s, r, g, b, a)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetVertexColor needs numbers")
	s._vc = { r, g, b, a == nil and 1 or a }
end
function Methods.SetTextColor(s, r, g, b, a)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetTextColor needs numbers")
	s._tc = { r, g, b }
end
function Methods.SetStatusBarTexture() end
function Methods.SetCountdownFont(s, f) s._cdFont = f end
-- In the game a face set on the string itself (SetFont) wins over a font object
-- set later: a family set after it changes nothing (seen: boxes in the chat preview).
function Methods.SetFontObject(s, fo)
	if type(fo) == "table" and rawget(fo, "_members") and rawget(s, "_font") then
		M.familyIgnored = (M.familyIgnored or 0) + 1; M.familyWhere = M.familyWhere or {}; local w = debug.traceback("", 2):match("SITREP/[^\n]-:%d+") or "?"; M.familyWhere[w] = (M.familyWhere[w] or 0) + 1
	end
	s._fontObj = fo
end
function Methods.SetScale(s, v) s._scale = v end
function Methods.SetRotation(s, r) s._rot = r end
function Methods.SetIgnoreParentAlpha(s, v) s._ignoreParentAlpha = v end
function Methods.SetFrameStrata(s, v) s._strata = v end
function Methods.SetMouseMotionEnabled(s, v) s._motion = v end
function Methods.SetID(s, v) s._id = v end
function Methods.GetID(s) return rawget(s, "_id") or 0 end
function Methods.SetMouseClickEnabled(s, v) s._clickable = v end
function Methods.GetFrameStrata(s) return rawget(s, "_strata") or "MEDIUM" end
function Methods.SetCooldown(s, st, du) s._cdStart, s._cdDur, s._cdObj = st, du, nil end
function Methods.SetCooldownFromDurationObject(s, d) s._cdObj, s._cdStart, s._cdDur = d, nil, nil end
function Methods.Clear(s) s._cdStart, s._cdDur, s._cdObj = nil, nil, nil end
function Methods.SetTexture(s, t) s._tex = t end
function Methods.SetColorTexture(s, r, g, b, a) s._color = { r, g, b, a == nil and 1 or a } end
function Methods.GetVertexColor(s) local c = rawget(s, "_vc") or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Methods.GetValue(s) return rawget(s, "_value") end
function Methods.GetMinMaxValues(s) return rawget(s, "_min"), rawget(s, "_max") end
function Methods.GetTexture(s) return rawget(s, "_tex") end
-- mask textures on a texture (modern nameplates round their bars with one)
function Methods.AddMaskTexture(s, m) s._masks = s._masks or {}; table.insert(s._masks, m) end
function Methods.GetNumMaskTextures(s) return #(rawget(s, "_masks") or {}) end
function Methods.GetMaskTexture(s, i) return (rawget(s, "_masks") or {})[i] end
function Methods.RemoveMaskTexture(s, m)
	local l = rawget(s, "_masks") or {}
	for i = #l, 1, -1 do if l[i] == m then table.remove(l, i) end end
end
function Methods.SetDesaturated(s, v) s._desat = v end
function Methods.GetScale(s) return rawget(s, "_scale") or 1 end
function Methods.SetStatusBarColor(s, r, g, b, a) s._sbColor = { r, g, b, a == nil and 1 or a } end
function Methods.GetStatusBarColor(s) local c = rawget(s, "_sbColor") or {} return c[1], c[2], c[3] end
function Methods.SetAttribute(s, k, v) s._attr = rawget(s, "_attr") or {}; s._attr[k] = v end
function Methods.GetAttribute(s, k) local a = rawget(s, "_attr") return a and a[k] end
-- StatusBar accepts secrets (this is the sanctioned path).
function Methods.SetMinMaxValues(s, lo, hi) s._min, s._max = lo, hi end
function Methods.SetValue(s, v) s._value = v end
function Methods.GetStatusBarTexture(s)
	local t = rawget(s, "_fill")
	if not t then t = new("Texture", s); s._fill = t end
	return t
end

function CreateFrame(kind, name, parent, template)
	local f = new(kind, parent)
	if type(parent) == "table" then
		parent._kids = rawget(parent, "_kids") or {}
		table.insert(parent._kids, f)
	end
	f._name = name
	if type(template) == "string" and template:find("Secure") then f._secure = true end
	if name then _G[name] = f end
	return f
end

UIParent = new("Frame")
PlayerFrame, TargetFrame, TargetFrameToT = new("Button"), new("Button"), new("Button")
-- (Blizzard's unit frames take the mouse: click to target, hover for the tooltip)
PlayerFrame._mouse, TargetFrame._mouse, TargetFrameToT._mouse = true, true, true
PetFrame = new("Button") -- hangs off PlayerFrame in the client
PartyFrame, CompactPartyFrame = new("Frame"), new("Frame")
-- Blizzard's buff bar (only when a test asks for it: S.buffBar): one shown button
-- per helpful aura on you, each with an Icon. S.secret.buffbar: icons secret.
M.buffBar = new("Frame")
M.buffBar.GetChildren = function()
	local S_ = M.scenario
	local out = {}
	for _, a in ipairs(S_.auras and S_.auras.player or {}) do
		if not a.harmful then
			local b = new("Button")
			b.Icon = new("Texture", b)
			local icon = a.icon
			b.Icon.GetTextureFileID = function() if S_.secret and S_.secret.buffbar then return M.Secret() end return icon end
			out[#out + 1] = b
		end
	end
	return unpack(out)
end
for i = 1, 4 do PartyFrame["MemberFrame" .. i] = new("Button") end
for i = 1, 5 do _G["CompactPartyFrameMember" .. i] = new("Button") end
M.unitWatch = {}
function RegisterUnitWatch(f) M.unitWatch[f] = true end
M.stateDrivers = {}
function RegisterStateDriver(f, state, values) M.stateDrivers[f] = M.stateDrivers[f] or {}; M.stateDrivers[f][state] = values end
function UnregisterStateDriver(f, state) if M.stateDrivers[f] then M.stateDrivers[f][state] = nil end end
function CreateFont(name) local fo = new("Font"); _G[name] = fo; return fo end
-- Font families: one file per alphabet, as the client defines them
M.families = {}
function CreateFontFamily(name, members)
	local fo = new("Font")
	fo._members = members
	M.families[name] = fo
	_G[name] = fo
	return fo
end
local function blizzardFamily(files)
	local fo = new("Font")
	fo.GetFontObjectForAlphabet = function(_, alphabet)
		local f = new("Font"); f.GetFont = function() return files[alphabet], 12, "" end; return f
	end
	return fo
end
NumberFontNormal = blizzardFamily({ roman = "Fonts\\ARIALN.TTF", russian = "Fonts\\ARIALN_CYR.TTF", korean = "Fonts\\K_Damage.TTF",
	simplifiedchinese = "Fonts\\ARHei.ttf", traditionalchinese = "Fonts\\arheiuhk_bd.TTF" })
-- the chat's font (on a German client the only one with every alphabet, say)
ChatFontNormal = blizzardFamily({ roman = "Fonts\\ARIALN.TTF", russian = "Fonts\\CHAT_CYR.TTF", korean = "Fonts\\CHAT_KO.TTF",
	simplifiedchinese = "Fonts\\CHAT_ZH.TTF", traditionalchinese = "Fonts\\CHAT_TW.TTF" })
-- a chat window's own font object: no family (its Latin face for every alphabet, as on Forever)
local chatWindowFont = blizzardFamily({ roman = "Fonts\\ARIALN.TTF", russian = "Fonts\\ARIALN.TTF", korean = "Fonts\\ARIALN.TTF",
	simplifiedchinese = "Fonts\\ARIALN.TTF", traditionalchinese = "Fonts\\ARIALN.TTF" })
function Methods.GetFontObject(s) return rawget(s, "_fontObj") or (rawget(s, "_name") and rawget(s, "_name"):find("^ChatFrame") and chatWindowFont) or nil end
-- Blizzard places its chat dock again (tabs docked or switched): its own place
function FCF_DockUpdate()
	if GeneralDockManager then
		GeneralDockManager:ClearAllPoints()
		GeneralDockManager:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 6)
		GeneralDockManager:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 6)
	end
end
GameFontHighlight = blizzardFamily({ roman = "Fonts\\FRIZQT__.TTF", russian = "Fonts\\FRIZQT___CYR.TTF", korean = "Fonts\\2002.TTF",
	simplifiedchinese = "Fonts\\ARKai_T.ttf", traditionalchinese = "Fonts\\blei00d.TTF" })
function UnregisterUnitWatch(f) M.unitWatch[f] = nil end
function GetActionInfo(slot) local a = (M.scenario.actions or {})[slot]; if a then return a[1], a[2] end end
function hooksecurefunc(t, name, fn)
	if type(t) == "string" then t, name, fn = _G, t, name end
	local orig = t[name]
	t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
function AbbreviateNumbers(n)
	if issecretvalue(n) then error("AbbreviateNumbers: secret") end -- worst case: the client refuses
	if n >= 1000 then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end
UIParent._w, UIParent._h = 1920, 1080
WorldFrame = new("Frame")
DEFAULT_CHAT_FRAME = new("Frame")
function DEFAULT_CHAT_FRAME.AddMessage(_, msg) M.prints[#M.prints + 1] = msg end
GameTooltip = new("Frame")
-- the tooltip remembers what it shows: its lines and the spell it was given
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner) self.lines = {}; self.spell = nil; self.owner = owner end
function GameTooltip:GetOwner() return self.owner end
-- a unit's tooltip, and the calls addons put after it (modern clients)
M.tooltipPostCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) table.insert(M.tooltipPostCalls, { kind = kind, fn = fn }) end }
function GameTooltip:SetUnit(unit)
	self.unit = unit
	self:Show()
	for _, c in ipairs(M.tooltipPostCalls) do if c.kind == Enum.TooltipDataType.Unit then c.fn(self) end end
end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:SetText(t) self.lines = { tostring(t) } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
function GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " " .. tostring(b) end
function GameTooltip:SetSpellByID(id) self.spell = id; local s = M.anySpell and M.anySpell(id); self.lines = { s and s.name or ("spell " .. id) } end
function GameTooltip:Text() return table.concat(self.lines, "\n") end
SettingsPanel = new("Frame")
UISpecialFrames = {}

-- The colour of a texture, or of a glass shape (a group of textures: its first part).
-- Does the text say it? Case and colour codes aside (the look writes sentence case).
function M.has(s, lit)
	if type(s) ~= "string" then return nil end
	s = s:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return s:lower():find(lit:lower(), 1, true)
end
function M.vc(t) return rawget(t, "_vc") or (t.parts and t.parts[1] and rawget(t.parts[1], "_vc")) end

function M.Fire(event, ...)
	for _, f in ipairs(M.eventFrames[event] or {}) do
		local fn = f._scripts.OnEvent
		if fn then fn(f, event, ...) end
	end
end

-- Advance the clock; every visible frame's OnUpdate runs.
function M.Update(dt)
	M.now = M.now + dt
	-- unit watch: the client shows a watched frame only while its unit exists
	-- (the client's own secure code: not subject to the combat rule)
	for f in pairs(M.unitWatch) do setShown(f, UnitExists(f:GetAttribute("unit") or "") and true or false) end
	for i = 1, #M.objects do
		local o = M.objects[i]
		local fn = o._scripts.OnUpdate
		if fn and o:IsVisible() then fn(o, dt) end
	end
end

---------------------------------------------------------------------------
-- Globals and namespaces
---------------------------------------------------------------------------
function GetTime() return M.now end
-- flight paths: S.taxiNodes[map] = { { name, x, y } }; the flight master's window:
-- S.taxiOpen = { { name, kind } } ("CURRENT", "REACHABLE", "NONE"); S.me.onTaxi
C_TaxiMap = {
	GetTaxiNodesForMap = function(map)
		local out = {}
		for _, n in ipairs((M.scenario.taxiNodes or {})[map] or {}) do out[#out + 1] = { name = n[1], position = { x = n[2], y = n[3] } } end
		return out
	end,
	GetAllTaxiNodes = function() return {} end,
}
function NumTaxiNodes() return #(M.scenario.taxiOpen or {}) end
function TaxiNodeName(i) local n = (M.scenario.taxiOpen or {})[i] return n and n[1] end
function TaxiNodeGetType(i) local n = (M.scenario.taxiOpen or {})[i] return n and n[2] end
function UnitOnTaxi(unit) return unit == "player" and M.scenario.me.onTaxi or false end
-- riding: S.me.mounted, S.me.speed (yards per second; units: u.speed)
function IsMounted() return M.scenario.me.mounted or false end
function GetUnitSpeed(unit)
	if M.scenario.secret and M.scenario.secret.speed then return M.Secret() end -- (S.secret.speed: kept secret, as in combat)
	if unit == "player" then return M.scenario.me.speed or 0 end
	local u = M.scenario.units[unit]
	return u and u.speed or 0
end
-- equipment wear: S.durability = { [slot] = { cur, max } }
function GetInventoryItemDurability(slot)
	local d = (M.scenario.durability or {})[slot]
	if d then return d[1], d[2] end
end
-- the server's clock in whole seconds (S.serverTime: set it, else it runs with GetTime)
function GetServerTime() return M.scenario.serverTime or (1760000000 + math.floor(GetTime())) end
function date(fmt) return "2026-10-01 02:00:00" end
function time() return 1790000000 + math.floor(M.now) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
math.atan2 = math.atan2 -- stays nil under 5.4; SITREP must cope
function GetMouseFoci() return { M.scenario.mouseFocus or WorldFrame } end
function GetCursorPosition() return M.scenario.cursorX or 0, 540 end
function InCombatLockdown() return M.scenario.me.combat or false end
function PlaySound() end
SOUNDKIT = { RAID_WARNING = 8959, MAP_PING = 3175, TELL_MESSAGE = 3081, ALARM_CLOCK_WARNING_3 = 12889,
	IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function CreateColor(r, g, b, a)
	local col = { r = r, g = g, b = b, a = a == nil and 1 or a }
	function col:GetRGBA() return self.r, self.g, self.b, self.a end
	function col:GetRGB() return self.r, self.g, self.b end
	return col
end
C_CurveUtil = { EvaluateColorFromBoolean = function(b, yes, no)
	if issecretvalue(b) then
		local v = M.secretOf[b]
		if v == nil then return yes end -- no real value behind it: the emulator plays "true"
		return v and yes or no
	end
	return b and yes or no
end, CreateColorCurve = function()
	local c = { pts = {} }
	function c:SetType(t) self.type = t end
	function c:AddPoint(x, col) self.pts[#self.pts + 1] = { x, col } end
	function c:Evaluate(x) local best; for _, p in ipairs(self.pts) do if p[1] <= x then best = p[2] end end return best end
	return c
end }
CLASS_ICON_TCOORDS = { ROGUE = { 0.49, 0.74, 0, 0.25 }, PRIEST = { 0.49, 0.74, 0.25, 0.5 }, MAGE = { 0.25, 0.49, 0, 0.25 } }
SlashCmdList = {}
Enum = { SpellBookSpellBank = { Player = 0 }, TooltipDataType = { Unit = 2 } }
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) M.settingsCategory = name return { name = name } end,
	RegisterAddOnCategory = function() end,
}
function GetRealZoneText() return "Hillsbrad Foothills" end
function GetSubZoneText() return "Tarren Mill" end
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
function Ambiguate(name) return (name:gsub("%-.*$", "")) end

local S = M.scenario
-- A unit placed in the world (wx, wy) gets its distance from your position.
local function D(u)
	if u.wx then return math.sqrt((u.wx - S.me.x) ^ 2 + (u.wy - S.me.y) ^ 2) end
	return u.dist
end
M.D = D

local function U(unit)
	local base, suffix = unit:match("^(.-)(target)$")
	if unit ~= "target" and base and base ~= "" and S.units[base] then
		-- "<unit>target": we only model whether it is the player
		return S.units[base].targetingMe and S.units.player or S.units[base].targetOf
	end
	return S.units[unit]
end
M.U = U

local function val(u, k)
	local v = u and u[k]
	if S.secret and S.secret[k] then return M.Secret() end
	return v
end

function UnitExists(unit) return U(unit) ~= nil end
function UnitGUID(unit) return val(U(unit), "guid") end
function UnitName(unit) return val(U(unit), "name") end
function GetUnitName(unit) return val(U(unit), "name") end
function UnitClass(unit)
	local u = U(unit); if not u then return nil end
	local cls = val(u, "class")
	return cls, cls, 1
end
function UnitLevel(unit) return val(U(unit), "level") end
function UnitIsPlayer(unit) local u = U(unit); if not u then return false end return val(u, "isPlayer") ~= false end
function UnitCanAttack(_, unit) return val(U(unit), "hostile") or false end
function UnitIsEnemy(_, unit) local u = U(unit) return u and u.hostile or false end
-- power of the shown type; with type 0 asked while another shows: the mana (u.mana / u.manaMax)
function UnitPower(unit, t) local u = U(unit) if not u then return nil end
	if t == 0 and (u.powerType or 0) ~= 0 then return u.mana or 0 end
	return u.power or 100 end
function UnitPowerMax(unit, t) local u = U(unit) if not u then return nil end
	if t == 0 and (u.powerType or 0) ~= 0 then return u.manaMax or 100 end
	return u.powerMax or 100 end
-- druid forms: S.forms = { { spell = id, active = bool }, ... }
function GetNumShapeshiftForms() return S.forms and #S.forms or 0 end
function GetShapeshiftForm() for i, f in ipairs(S.forms or {}) do if f.active then return i end end return 0 end
function GetShapeshiftFormInfo(i) local f = (S.forms or {})[i]; if f then return "icon", f.active or false, true, f.spell end end
function UnitPowerType(unit) local u = U(unit) return u and (u.powerType or 0) end
function UnitCreatureFamily(unit) local u = U(unit) return u and u.family end
function UnitCreatureType(unit) local u = U(unit) return u and u.creatureType end
function UnitRace(unit)
	local u = U(unit); if not u then return nil end
	if S.secret and S.secret.race then return M.Secret("race"), "NightElf", 4 end
	return u.race, u.race, 4
end
function IsShiftKeyDown() return S.shift or false end
function UnitIsConnected(unit) local u = U(unit) if not u then return nil end return not u.offline end
function UnitIsGhost(unit) local u = U(unit) return u and u.ghost or false end
function UnitGroupRolesAssigned(unit) local u = U(unit) return u and u.role or "NONE" end
function IsResting() return S.me.resting or false end
function UnitGetTotalAbsorbs(unit) local u = U(unit) return u and (u.absorb or 0) end
-- all incoming heals, or only those cast by `healer` ("player" = you)
function UnitGetIncomingHeals(unit, healer)
	local u = U(unit); if not u then return nil end
	if S.secret and S.secret.heals then return M.Secret() end
	if healer == "player" then return u.incHealMine or 0 end
	if healer then return (u.incHealBy and u.incHealBy[healer]) or 0 end
	return u.incHeal or 0
end
function UnitIsPVP(unit) local u = U(unit) return u and u.pvp or false end
function IsPVPTimerRunning() return S.pvpTimer ~= nil end
function GetPVPTimer() return S.pvpTimer or 301000 end
function UnitClassification(unit) local u = U(unit) return u and (u.classification or "normal") end
function GetRaidTargetIndex(unit) local u = U(unit) return u and u.raidIcon end
function SetRaidTargetIconTexture() end
function GetComboPoints() return S.combo or 0 end
function UnitIsTapDenied() return false end
function UnitCastingDuration(unit) local u = U(unit); if u and u.casting then return { duration = true } end end
function UnitChannelDuration() return nil end
-- Auras: S.auras[unit] = { { id, harmful, icon, dispel, spellId, name, source, stacks, stealable } }
-- Spell lookups in combat (hypothesis under test): refused while the aura is
-- there, a plain nil once it is gone. S.secret.lookupsErr: always refused.
function M.lookup(unit, match, spellId)
	local S_ = M.scenario
	local found
	for _, a in ipairs(S_.auras and S_.auras[unit] or {}) do if match(a) then found = a end end
	local never = spellId and S_.neverSecret and S_.neverSecret[spellId]
	if S_.secret and S_.secret.auras and not never then
		if S_.secret.lookupsNil then return nil end -- measured on Forever: nil whenever secret
		if S_.secret.lookupsErr or found then error("Auras cannot be accessed when secret while tainted.") end
		return nil
	end
	if not found then return nil end
	return { auraInstanceID = found.id, spellId = found.spellId, name = found.name, sourceUnit = found.source,
		expirationTime = M.now + (found.duration or 600) / 2, duration = found.duration or 600 }
end
local LOCKED = "Auras cannot be accessed when secret while tainted."
local function findAura(unit, id) for _, a in ipairs(S.auras and S.auras[unit] or {}) do if a.id == id then return a end end end
local DISPEL_ID = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Enrage = 9 }
C_UnitAuras = {
	GetUnitAuraInstanceIDs = function(unit, filter)
		if S.secret and S.secret.auraList then error(LOCKED) end
		local out = {}
		for _, a in ipairs(S.auras and S.auras[unit] or {}) do
			-- "RAID": only what you can dispel (the scenario marks those canDispel)
			if ((filter:find("HARMFUL") and a.harmful) or (filter:find("HELPFUL") and not a.harmful))
				and (not filter:find("RAID") or a.canDispel) and (not filter:find("PLAYER") or a.source == "player") then out[#out + 1] = a.id end
		end
		return out
	end,
	GetAuraDataByAuraInstanceID = function(unit, id)
		if S.secret and S.secret.auras then error(LOCKED) end
		local a = findAura(unit, id); if not a then return nil end
		return { auraInstanceID = a.id, icon = a.icon, dispelName = a.dispel, spellId = a.spellId, name = a.name, applications = a.stacks or 0,
			duration = a.duration or 600, expirationTime = M.now + (a.duration or 600) / 2, sourceUnit = a.source, isStealable = a.stealable }
	end,
	GetAuraDuration = function(unit, id)
		if S.secret and S.secret.oracle then error(LOCKED) end
		if findAura(unit, id) then return { durationObject = true } end
	end,
	-- the narrow questions (see Trackers: Oracle). In combat (S.secret.auras) the
	-- data calls are refused; these keep answering unless S.secret.oracle.
	IsAuraFilteredOutByInstanceID = function(unit, id, filter)
		if S.secret and S.secret.oracleErr then error(LOCKED) end
		if S.secret and S.secret.oracle then return M.Secret(findAura(unit, id) == nil) end -- answered, but secretly
		return findAura(unit, id) == nil
	end,
	DoesAuraHaveExpirationTime = function(unit, id)
		if S.secret and S.secret.auras then error(LOCKED) end
		return findAura(unit, id) and true or nil
	end,
	GetPlayerAuraBySpellID = function(spellId) return M.lookup("player", function(a) return a.spellId == spellId end, spellId) end,
	GetUnitAuraBySpellID = function(unit, spellId) return M.lookup(unit, function(a) return a.spellId == spellId end, spellId) end,
	GetAuraDataBySpellName = function(unit, name) return M.lookup(unit, function(a) return a.name == name end) end,
	GetAuraBaseDuration = function(unit, id) local a = findAura(unit, id) return a and (a.duration or 600) end,
	GetAuraDispelTypeColor = function(unit, id, curve) local a = findAura(unit, id); return curve:Evaluate(a and DISPEL_ID[a.dispel] or 0) end,
	AuraIsBigDefensive = function(spellId) return spellId == 642 end, -- Divine Shield
}
C_LossOfControl = { GetActiveLossOfControlData = function(i) return S.loc end }
function UnitReaction(unit) local u = U(unit); if not u then return nil end
	if S.secret and S.secret.reaction then return M.Secret() end
	return u.reaction end
function UnitIsFriend(_, unit) local u = U(unit) return u and not u.hostile or false end
function UnitFactionGroup(unit) local u = U(unit) return u and u.faction end
function UnitIsDeadOrGhost(unit) local u = U(unit) return u and u.dead or false end
function UnitIsDead(unit) local u = U(unit) return u and u.dead or false end
function UnitPlayerControlled(unit) local u = U(unit) return u and (u.isPlayer or u.owner ~= nil) or false end
-- the client's pet title line (German client: "Begleiter von %s")
UNITNAME_TITLE_PET, UNITNAME_TITLE_MINION = "Begleiter von %s", "Diener von %s"
function UnitAffectingCombat(unit) local u = U(unit) return u and u.combat or false end
function UnitIsUnit(a, b)
	local ua, ub = U(a), U(b)
	-- S.secret.isUnit: the client keeps "is X's target me" secret (the real answer behind it)
	if S.secret and S.secret.isUnit and a:match("target$") then return M.Secret(ua ~= nil and ua == ub) end
	return ua ~= nil and ua == ub
end
function UnitCastingInfo(unit)
	local u = U(unit)
	if not (u and u.casting) then return nil end
	if S.secret and S.secret.cast then return M.Secret(), "", "", M.Secret(), M.Secret(), false, 1, M.Secret(), 116 end
	-- name, text, texture, startMS, endMS, isTradeSkill, castID, notInterruptible, spellID
	return u.castName or "Frostbolt", "", "", u.castStart, u.castEnd, false, 1, u.notInt or false, u.castSpell or 116
end
function UnitChannelInfo(unit)
	local u = U(unit)
	if not (u and u.channeling) then return nil end
	-- name, text, texture, startMS, endMS, isTradeSkill, notInterruptible, spellID
	local notInt = (S.secret and S.secret.cast) and M.Secret() or (u.notInt or false)
	return u.castName or "Channel", "", "", u.castStart, u.castEnd, false, notInt, u.castSpell or 5143
end
function GetGuildInfo(unit) local u = U(unit) return u and u.guild end
function UnitHealth(unit) local u = U(unit); if not u then return nil end if S.secret and S.secret.health then return M.Secret() end return u.hp end
function UnitHealthMax(unit) local u = U(unit); return u and u.hpMax end
function UnitInRange(unit) local u = U(unit) return u and (D(u) or 0) < 40 end
function UnitInParty(name) return S.group.names and S.group.names[name] or false end
function UnitInRaid() return nil end
function UnitPosition(unit)
	if unit == "player" then
		if S.me.noPosition then return nil end
		return S.me.x, S.me.y, 0, S.me.inst or 1 -- north axis first, as the client does
	end
	-- group members' positions (S.restrictGroupPos: the client withholds them)
	local u = U(unit)
	if u and u.wx and unit:match("^party") or (u and u.wx and unit:match("^raid")) then
		if S.restrictGroupPos then return nil end
		return u.wx, u.wy, 0, S.me.inst or 1
	end
	return nil
end
function GetPlayerFacing() return S.me.facing end
-- Protected in combat except for enemies (client 10.2 + hotfix): asking about
-- anyone else is a blocked action; the emulator counts them in M.blockedCalls.
M.blockedCalls = 0
local function protectedRange(u)
	if S.me.combat and not u.hostile then M.blockedCalls = M.blockedCalls + 1 return true end
end
M.ProtectedRange = protectedRange
function CheckInteractDistance(unit, idx)
	local u = U(unit); if not u then return nil end
	if protectedRange(u) then return nil end
	if S.secret and S.secret.range then return M.Secret() end
	return D(u) <= (idx == 3 and 10 or idx == 4 and 28 or 11)
end
function IsInGroup(cat) if cat == 2 then return S.group.instance or false end return S.group.n and S.group.n > 0 or false end
function IsInRaid() return S.group.raid or false end
-- name, rank, subgroup, level, class (localised), class file, zone, online, dead, role, master looter
function GetRaidRosterInfo(i)
	local u = S.units["raid" .. i]
	-- (an empty slot: no name, but a group all the same, as Forever answers)
	if not u then if S.group.raid and i <= 40 then return nil, 0, math.ceil(i / 5) end return nil end
	return u.name, u.rank or 0, u.subgroup or 1, u.level, u.class, u.class, nil, u.online ~= false, u.dead or false, u.role, false
end
function UnitThreatSituation(unit, mob) local u = U(unit) return u and u.threat or nil end
function GetNumGroupMembers() return S.group.n or 0 end
function GetNumSubgroupMembers() return S.group.n or 0 end

-- Spellbook: one skill line with a handful of ranged harmful spells.
M.spells = {
	{ id = 133, name = "Fireball", min = 0, max = 35 },
	{ id = 116, name = "Frostbolt", min = 0, max = 30, cost = 120 },
	{ id = 2136, name = "Fire Blast", min = 0, max = 20 },
	{ id = 122, name = "Frost Nova", min = 0, max = 0 },
	{ id = 2061, name = "Flash Heal", min = 0, max = 40, helpful = true,
		desc = "Heilt ein freundliches Ziel um 812 bis 944 Punkte." }, -- deDE client
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #M.spells } end,
	GetSpellBookItemInfo = function(slot) local s = M.spells[slot] return s and { spellID = s.id, isPassive = false } end,
	IsSpellBookItemHarmful = function(slot) local s = M.spells[slot] return s and not s.helpful end,
	IsSpellBookItemHelpful = function(slot) local s = M.spells[slot] return s and s.helpful or false end,
}
-- Spells outside the range ladder, known for lookups (German client names).
M.otherSpells = {
	{ id = 2139, name = "Gegenzauber", icon = "cs.blp", cd = 24 },
	{ id = 172, name = "Verderbnis", icon = "cor.blp" },
	{ id = 1459, name = "Arkane Intelligenz", icon = "ai.blp" },
	{ id = 8024, name = "Waffe der Flammenzunge", icon = "ft.blp", sub = "Rang 1" },
	{ id = 319778, name = "Waffenzunge", icon = "ftbuff.blp" },
}
-- weapon tooltips: S.weaponTip = { [16] = { "line", ... }, [17] = ... }
C_TooltipInfo = {
	-- a unit's tooltip: its name, and a pet's owner line in the client's words
	GetUnit = function(unit)
		local u = S.units[unit]
		if not u then return nil end
		if S.secret and S.secret.tooltip then return M.Secret() end
		local lines = { { leftText = u.name } }
		if u.owner then lines[2] = { leftText = (u.ownerTitle or UNITNAME_TITLE_PET):format(u.owner) } end
		if u.title then lines[2] = { leftText = "<" .. u.title .. ">" } end
		if u.tipLine2 then lines[2] = { leftText = u.tipLine2 } end
		return { lines = lines }
	end,
	GetInventoryItem = function(unit, slot)
		if S.secret and S.secret.tooltip then return M.Secret() end
		local lines = {}
		for i, t in ipairs((S.weaponTip or {})[slot] or { "Some Weapon" }) do lines[i] = { leftText = t } end
		return { lines = lines }
	end,
}
-- temporary weapon enchants: S.weapon = { mh = { id, ms }, oh = { id, ms } }
function GetWeaponEnchantInfo()
	local w = S.weapon or {}
	if S.secret and S.secret.weapon then local x = M.Secret() return x, x, x, x, x, x, x, x end
	local mh, oh = w.mh, w.oh
	return mh ~= nil, mh and mh.ms or 0, 0, mh and mh.id or 0, oh ~= nil, oh and oh.ms or 0, 0, oh and oh.id or 0
end
local function anySpell(q)
	for _, list in ipairs({ M.spells, M.otherSpells }) do
		for _, s in ipairs(list) do if s.id == q or s.name == q then return s end end
	end
end
M.anySpell = anySpell
S.cooldowns = {}
-- macros: { name, icon, body }
M.macros = {}
function GetMacroIndexByName(name) for i, m in ipairs(M.macros) do if m.name == name then return i end end return 0 end
function GetMacroBody(i) return M.macros[i] and M.macros[i].body end
function CreateMacro(name, icon, body) M.macros[#M.macros + 1] = { name = name, icon = icon, body = body } return #M.macros end
function EditMacro(i, name, icon, body) local m = M.macros[i]; if not m then return end if name then m.name = name end if body then m.body = body end return i end
function DeleteMacro(i) table.remove(M.macros, i) end
function GetRealmName() return "Forever" end
function GetSpellBaseCooldown(id) local s = anySpell(id) return s and (s.cd or 0) * 1000 or 0 end
C_Spell = {
	GetSpellName = function(id) local s = anySpell(id) return s and s.name end,
	GetSpellSubtext = function(id) local s = anySpell(id) return s and s.sub end,
	GetSpellPowerCost = function(id)
		local s = anySpell(id)
		if s and s.costs then return s.costs end -- (several entries: e.g. one lowered by an equipped item)
		if not (s and s.cost) then return {} end
		return { { type = 0, cost = s.cost, minCost = s.cost, hasRequiredAura = false, requiredAuraID = 0 } }
	end,
	IsSpellUsable = function(id)
		local s, u = anySpell(id), S.units.player
		local short = s and s.cost and (u.power or 100) < s.cost
		return not short, short or false
	end,
	GetSpellTexture = function(id) local s = anySpell(id) return s and (s.icon or "spell.blp") end,
	GetSpellCooldown = function(id)
		local c = S.cooldowns[id]
		if S.secret and S.secret.cooldowns then return { startTime = M.Secret(), duration = M.Secret(), isEnabled = M.Secret(), modRate = 1 } end
		if not c then return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } end
		return { startTime = c.start, duration = c.duration, isEnabled = true, modRate = 1 }
	end,
	GetSpellCooldownDuration = function(id) return { durationObject = true } end,
	GetSpellDescription = function(id)
		for _, s in ipairs(M.spells) do if s.id == id then return s.desc or "" end end
		return ""
	end,
	GetSpellInfo = function(id)
		local s = anySpell(id)
		if s then return { spellID = s.id, name = s.name, iconID = s.icon or "spell.blp", minRange = s.min, maxRange = s.max } end
	end,
	IsSpellInRange = function(id, unit)
		local u = U(unit); if not u then return nil end
		if S.secret and S.secret.range then return M.Secret() end
		for _, s in ipairs(M.spells) do
			if s.id == id then
				-- harmful spells only check enemies, helpful spells only allies
				if (s.helpful and u.hostile) or (not s.helpful and not u.hostile) then return nil end
				return D(u) <= s.max
			end
		end
	end,
}
-- Item range checks: only the items in M.rangeItems are known (others never
-- answer); against enemies the client refuses them in combat.
M.rangeItems = nil -- [itemID] = yards; nil = this client knows none
C_Item = {
	IsItemInRange = function(id, unit)
		local u = U(unit); if not u then return nil end
		if protectedRange(u) or not M.rangeItems or not M.rangeItems[id] then return nil end
		return D(u) <= M.rangeItems[id]
	end,
	RequestLoadItemDataByID = function() end,
	GetItemNameByID = function(id) return M.rangeItems and M.rangeItems[id] and ("Item " .. id) or nil end, -- known = loaded
	-- items in the bags: S.items = { [itemID] = count }; S.unusable = { [itemID] = true }
	GetItemCount = function(id) return (S.items or {})[id] or 0 end,
	IsUsableItem = function(id) return not (S.unusable and S.unusable[id]) end,
	GetItemIconByID = function(id) return "icon" .. id end,
}
-- health as a percent through a colour curve (S.secret.health: the value stays the client's)
function UnitHealthPercent(unit, usePredicted, curve)
	local u = U(unit); if not u or not u.hpMax then return nil end
	local pct = u.hp / u.hpMax * (S.hpScale or 1) -- (S.hpScale 100: a client counting 0-100)
	if curve then return curve:Evaluate(pct) end
	if S.secret and S.secret.health then return M.Secret() end
	return pct
end
C_NamePlate = {
	GetNamePlateForUnit = function(unit)
		local u = S.units[unit]
		if not (u and u.screenX) then return nil end
		local plate = new("Frame")
		if S.restrictMeasure then
			plate.GetCenter = function() error("NamePlate1:GetCenter(): Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
		end
		if u.forbidden then
			plate.IsForbidden = function() return true end
			plate.GetCenter = function() error("Attempt to access forbidden object from code tainted by an AddOn") end
		end
		plate._cx = (S.secret and S.secret.center) and M.Secret() or u.screenX
		plate._cy = 540
		return plate
	end,
}
C_Secrets = {
	ShouldAurasBeSecret = function() return S.me.combat or false end,
	ShouldSpellAuraBeSecret = function(id) return not (S.neverSecret and S.neverSecret[id]) end,
	ShouldUnitAuraInstanceBeSecret = function() return true end, -- tells nothing apart: must be rejected
}
C_CombatLog = { IsCombatLogRestricted = function() return true end }
C_ChatInfo = {
	RegisterAddonMessagePrefix = function(p) M.prefix = p return true end,
	SendAddonMessage = function(prefix, msg, channel)
		assert(#msg <= 255, "addon message too long: " .. #msg)
		M.addonMsgs[#M.addonMsgs + 1] = { prefix = prefix, msg = msg, channel = channel }
		return true
	end,
	InChatMessagingLockdown = function() return S.chatLockdown or false end,
	AreOutgoingAddonChatMessagesRestricted = function() return false end,
	SendChatMessage = function(msg, channel) M.chat[#M.chat + 1] = { msg = msg, channel = channel } end,
}
C_Timer = { After = function(_, fn) fn() end }
M.tickers = {}
function C_Timer.NewTicker(_, fn, n) M.tickers[#M.tickers + 1] = { fn = fn, left = n or math.huge } end
function M.RunTickers()
	for _, t in ipairs(M.tickers) do if t.left > 0 then t.left = t.left - 1; t.fn() end end
end
function GetLocale() return "deDE" end
function GetBuildInfo() return "1.60.1", "70009", "Oct 1 2026", 16001 end
M.cvars = {}
-- S.cvarsMissing[k]: this client has no such setting
local function knownCVar(k) return not (S.cvarsMissing and S.cvarsMissing[k]) end
function SetCVar(k, v)
	if S.me.combat and k:find("^nameplate") then M.blockedCalls = M.blockedCalls + 1 return end -- (protected in combat)
	M.cvars[k] = tostring(v)
end
C_CVar = {
	GetCVar = function(k) if knownCVar(k) then return GetCVar(k) end end,
	SetCVar = function(k, v) if knownCVar(k) then SetCVar(k, v) return true end return false end,
}
C_Console = { GetAllCommands = function()
	local out = {}
	for _, k in ipairs({ "nameplateGlobalScale", "NamePlateHorizontalScale", "NamePlateVerticalScale", "nameplateMaxDistance" }) do
		if knownCVar(k) then out[#out + 1] = { command = k, commandType = 0 } end
	end
	return out
end }
function GetCVar(k)
	if k == "ActionButtonUseKeyDown" then return S.keyDown or "1" end
	if M.cvars[k] ~= nil then return M.cvars[k] end
	return ({ nameplateShowEnemies = "1", nameplateMaxDistance = "41", cameraFov = "90", nameplateGlobalScale = "1",
		NamePlateHorizontalScale = "1", NamePlateVerticalScale = "1" })[k]
end
LE_PARTY_CATEGORY_INSTANCE = 2

---------------------------------------------------------------------------
-- The game's own interface: minimap, experience, bags, chat (UI/Minimap, XP,
-- Bags, Chat). S.me.xp / xpMax / rested / level / maxLevel; S.bags = { {free,
-- slots}, ... } for bags 0..4; S.zone / S.pvpZone; S.mapPos = { x, y }.
---------------------------------------------------------------------------
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap._w, Minimap._h, Minimap._zoom = 140, 140, 0
function Minimap:SetMaskTexture(t) self._mask = t end
function Minimap:GetZoom() return self._zoom end
function Minimap:SetZoom(z) self._zoom = z end
function Minimap:GetZoomLevels() return 6 end
Minimap.ZoomIn, Minimap.ZoomOut = new("Button"), new("Button")
MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster.BorderTop, MinimapCluster.ZoneTextButton = new("Frame"), new("Button")
MinimapCompassTexture = new("Texture")
function GetMinimapZoneText() return S.zone or "Brachland" end
function GetZonePVPInfo() return S.pvpZone or "contested" end
C_Map = {
	GetBestMapForUnit = function() return S.mapId or 1413 end,
	-- your position on a map: the one you are on, or one that covers you
	-- (S.mapPosOn[map]); any other map: none
	GetPlayerMapPosition = function(map)
		local p
		if map == nil or map == (S.mapId or 1413) then p = S.mapPos or { 0.523, 0.418 }
		elseif S.mapPosOn then p = S.mapPosOn[map] end
		if not p then return nil end
		return { GetXY = function() return p[1], p[2] end }
	end,
}
function UnitXP() return S.me.xp or 1200 end
-- an open loot window: S.loot = { the corpse's GUID per slot }
function GetNumLootItems() return S.lootSlots and #S.lootSlots or S.loot and #S.loot or 0 end
-- what is in the loot window: S.lootSlots = { { name, quest = questID, active = true/false (a quest's item / it starts one) } }
function GetLootSlotInfo(slot)
	local l = S.lootSlots and S.lootSlots[slot]
	if not l then return nil end
	return "icon.blp", l[1], 1, nil, 1, false, l.quest ~= nil, l.quest, l.active
end
function GetLootSourceInfo(slot) return S.loot and S.loot[slot], 1 end
-- a hunter pet's experience: S.petXP = { cur, max }
function GetPetExperience() local p = S.petXP or { 0, 0 } return p[1], p[2] end
function UnitXPMax() return S.me.xpMax or 4800 end
function GetXPExhaustion() return S.me.rested end
function GetMaxPlayerLevel() return S.me.maxLevel or 60 end
function IsXPUserDisabled() return false end
NUM_BAG_SLOTS = 4
local function bag(id) return (S.bags or { { 3, 16 }, { 5, 14 }, { 0, 14 }, { 2, 10 }, { 0, 0 } })[id + 1] or { 0, 0 } end
C_Container = {
	GetContainerNumFreeSlots = function(id) return bag(id)[1] end,
	GetContainerNumSlots = function(id) return bag(id)[2] end,
	-- S.items fill the backpack's first slots, one per item ID
	GetContainerItemID = function(id, slot)
		if id ~= 0 then return nil end
		local ids = {}
		for item in pairs(S.items or {}) do ids[#ids + 1] = item end
		table.sort(ids)
		return ids[slot]
	end,
	GetItemCooldown = function(id) local c = (S.itemCD or {})[id] if c then return c[1], c[2], 1 end return 0, 0, 1 end,
	-- the bag windows' items: S.bagItems[bag][slot] = { name, quest = questID, questItem = true, active = bool }
	GetContainerItemInfo = function(id, slot)
		local it = S.bagItems and S.bagItems[id] and S.bagItems[id][slot]
		if not it then return nil end
		return { iconFileID = 1, stackCount = 1, hyperlink = "|cffffffff|Hitem:1::::|h[" .. it[1] .. "]|h|r", itemID = 1 }
	end,
	GetContainerItemQuestInfo = function(id, slot)
		local it = S.bagItems and S.bagItems[id] and S.bagItems[id][slot]
		return { isQuestItem = it and (it.questItem or it.quest ~= nil) or false, questID = it and it.quest, isActive = it and it.active or false }
	end,
}
M.bagsToggled = 0
function ToggleAllBags() M.bagsToggled = M.bagsToggled + 1 end
BagsBar = CreateFrame("Frame", "BagsBar", UIParent)
BagsBar._mouse = true
-- Blizzard's backpack button (on the bag bar): its click opens the bags
MainMenuBarBackpackButton = CreateFrame("Button", "MainMenuBarBackpackButton", BagsBar)
MainMenuBarBackpackButton._mouse = true
MainMenuBarBackpackButton:SetScript("OnClick", function() ToggleAllBags() end)
MainStatusTrackingBarContainer = CreateFrame("Frame", "MainStatusTrackingBarContainer", UIParent)
NUM_CHAT_WINDOWS = 2
CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA, CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0.2, 0.4
ChatFrame1 = DEFAULT_CHAT_FRAME
ChatFrame1._name = "ChatFrame1"
ChatFrame2 = CreateFrame("Frame", "ChatFrame2", UIParent)
-- Blizzard's tab bar for the docked windows, over the general chat window
GeneralDockManager = CreateFrame("Frame", "GeneralDockManager", UIParent)
GeneralDockManager:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 6)
GeneralDockManager:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 6)
for i = 1, 2 do
	local cf = _G["ChatFrame" .. i]
	cf._font, cf._visible, cf._fading = { "Fonts\\ARIALN.TTF", 14, "" }, 120, true
	cf.GetFont = function(self) return self._font[1], self._font[2], self._font[3] end
	cf.GetTimeVisible = function(self) return self._visible end
	cf.SetTimeVisible = function(self, v) self._visible = v end
	cf.GetFading = function(self) return self._fading end
	cf.SetFading = function(self, v) self._fading = v end
	for _, part in ipairs({ "ButtonFrame", "Tab", "EditBox", "EditBoxLeft", "EditBoxMid", "EditBoxRight" }) do
		CreateFrame("Frame", "ChatFrame" .. i .. part, UIParent)
	end
	-- the window's background: textures tell nothing when shown (no scripts)
	for _, part in ipairs({ "Background", "TopLeftTexture" }) do
		local t = new("Texture", cf)
		t.HookScript = false
		_G["ChatFrame" .. i .. part] = t
	end
	local tab = _G["ChatFrame" .. i .. "Tab"]
	tab.noMouseAlpha = 0.2
	-- the tab's art (Blizzard's names), its name and its new-message glow
	for _, sfx in ipairs({ "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight" }) do
		_G["ChatFrame" .. i .. "Tab" .. sfx] = tab:CreateTexture()
	end
	_G["ChatFrame" .. i .. "TabText"] = tab:CreateFontString()
	local glow = tab:CreateTexture()
	glow:SetTexture("Interface\\ChatFrame\\ChatFrameTab-NewMessage")
	glow:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, -2)
	_G["ChatFrame" .. i .. "TabGlow"] = glow
end
ChatFrameMenuButton = CreateFrame("Button", "ChatFrameMenuButton", UIParent)
-- which chat groups each window shows: 1 the general one, 2 a whisper window
-- Blizzard's input lines sit under their window
for i = 1, 2 do
	local eb, cf = _G["ChatFrame" .. i .. "EditBox"], _G["ChatFrame" .. i]
	eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -5, -2)
	eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -2)
end
ChatFrame1.messageTypeList = { "SAY", "YELL", "GUILD", "PARTY", "PARTY_LEADER", "RAID", "CHANNEL" }
ChatFrame2.messageTypeList = { "WHISPER", "BN_WHISPER" }
ChatTypeInfo = { WHISPER = { r = 1, g = 0.5, b = 1 }, GUILD = { r = 0.25, g = 1, b = 0.25 }, SAY = { r = 1, g = 1, b = 1 } }
function ChatFrame_ContainsMessageGroup(cf, group)
	for _, g in ipairs(cf.messageTypeList or {}) do if g == group then return true end end
	return false
end
ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95)
-- Blizzard keeps room for its button column left of each window
ChatFrame1._clamp, ChatFrame2._clamp = { -35, 35, 26, -50 }, { -35, 35, 26, -50 }
-- Blizzard's own chat calls (the hooks SITREP puts on them)
SELECTED_CHAT_FRAME = ChatFrame1
function FCF_Tab_OnClick(tab) SELECTED_CHAT_FRAME = tab._chat end
ChatFrame1Tab._chat, ChatFrame2Tab._chat = ChatFrame1, ChatFrame2
function FCF_SetChatWindowFontSize(self, cf, size) cf:SetFont(cf._font[1], size, "") end
function FCF_RestorePositionAndDimensions(cf) cf:ClearAllPoints(); cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95) end
-- Blizzard fading the window back in on mouse-over: shows and fades every part
function M.ChatHover(cf)
	for _, sfx in ipairs({ "Background", "TopLeftTexture", "ButtonFrame" }) do
		local t = _G[cf:GetName() .. sfx]
		t:Show(); t:SetAlpha(0.25)
	end
end

---------------------------------------------------------------------------
-- Quests (the classic quest log; S.quests = { { id, title, level, zone,
-- objectives = { { "Kobold Vermin slain: 3/8", done }, ... }, complete }, ... }).
-- S.questCollapsed[zone]: that header collapsed (its quests not listed).
-- S.questWaypoints[id] = { map, x, y }: the client gives positions (modern API).
-- S.mapSize = false: the client does not tell map sizes.
---------------------------------------------------------------------------
local function questRows()
	local rows, zones, seen = {}, {}, {}
	for _, q in ipairs(S.quests or {}) do
		if not seen[q.zone] then seen[q.zone] = true; zones[#zones + 1] = q.zone end
	end
	for _, z in ipairs(zones) do
		rows[#rows + 1] = { header = true, title = z }
		if not (S.questCollapsed and S.questCollapsed[z]) then
			for _, q in ipairs(S.quests) do if q.zone == z then rows[#rows + 1] = q end end
		end
	end
	return rows
end
function GetNumQuestLogEntries() return #questRows(), #(S.quests or {}) end
function GetQuestLogTitle(i)
	local r = questRows()[i]
	if not r then return nil end
	if r.header then return r.title, 0, nil, true, false, nil, nil, nil end
	return r.title, r.level, nil, false, false, r.complete and 1 or nil, nil, r.id
end
function GetNumQuestLeaderBoards(i) local r = questRows()[i] return r and not r.header and #r.objectives or 0 end
function GetQuestLogLeaderBoard(j, i)
	local o = questRows()[i].objectives[j]
	return o[1], o.kind or "monster", o[2] or false -- ({ text, done, kind = "item" })
end
M.questLogOpened = {}
M.questSel = 0
-- a quest's item to use (q.item = { link, icon, charges }; q.itemCD = { start, duration })
function GetQuestLogSpecialItemInfo(i)
	local r = questRows()[i]
	if r and not r.header and r.item then return r.item[1], r.item[2], r.item[3] or 1, false end
end
function GetQuestLogSpecialItemCooldown(i)
	local r = questRows()[i]
	if r and not r.header and r.itemCD then return r.itemCD[1], r.itemCD[2], 1 end
	return 0, 0, 1
end
-- links: the classic log hands them out by log line
function GetQuestLink(i)
	local r = questRows()[i]
	if r and not r.header then return "|cffffff00|Hquest:" .. r.id .. ":" .. r.level .. "|h[" .. r.title .. "]|h|r" end
end
M.chatInserted = {}
M.chatOpenWith = nil
function ChatEdit_InsertLink(link)
	if not S.chatOpen then return false end
	M.chatInserted[#M.chatInserted + 1] = link
	return true
end
function ChatFrame_OpenChat(text) M.chatOpenWith = text end
function SelectQuestLogEntry(i) M.questLogOpened[#M.questLogOpened + 1] = i; M.questSel = i end
-- the quest the game tracks (its map marks it): M.superTracked
C_SuperTrack = { SetSuperTrackedQuestID = function(id) M.superTracked = id end, GetSuperTrackedQuestID = function() return M.superTracked or 0 end }
function GetQuestLogSelection() return M.questSel end
function GetQuestLogRewardXP()
	local r = questRows()[M.questSel]
	return r and not r.header and r.xp or 0
end
-- the selected quest's story and task
function GetQuestLogQuestText()
	local r = questRows()[M.questSel]
	if r and not r.header then return r.desc or "", r.task or "" end
end
C_QuestLog = {
	GetNextWaypoint = function(id)
		local w = S.questWaypoints and S.questWaypoints[id]
		if w then return w[1], w[2], w[3] end
	end,
}
C_Map.GetMapWorldSize = function() if S.mapSize == false then return nil end return 3000, 2000 end
-- the map tree: zones under continents under the world (1 world, 2 continent, 3 zone)
local MAPS = {
	[947] = { name = "Azeroth", mapType = 1, parentMapID = 0 },
	[1414] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
	[1415] = { name = "Östliche Königreiche", mapType = 2, parentMapID = 947 },
	[1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
	[1436] = { name = "Westfall", mapType = 3, parentMapID = 1415 },
	[1457] = { name = "Darnassus", mapType = 3, parentMapID = 1414 },
}
C_Map.GetMapInfo = function(id)
	local m = MAPS[id]
	if m then return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID } end
	return { mapID = id, name = "Map " .. id, mapType = 3, parentMapID = 0 }
end
C_Map.GetMapChildrenInfo = function(id, kind)
	local out = {}
	for mid, m in pairs(MAPS) do if m.parentMapID == id and (not kind or m.mapType == kind) then out[#out + 1] = { mapID = mid, name = m.name } end end
	table.sort(out, function(a, b) return a.mapID < b.mapID end)
	return out
end
-- the zone at a point of a continent: S.zoneAt[map] = name
C_Map.GetMapInfoAtPosition = function(map) local n = S.zoneAt and S.zoneAt[map] if n then return { name = n } end end
-- the game's quest pins on a map: S.questPins[map] = { { questID, x, y }, ... }
C_QuestLog.GetQuestsOnMap = function(map) return (S.questPins and S.questPins[map]) or {} end
-- quests this character has done: S.questsDone = { [id] = true }
C_QuestLog.IsQuestFlaggedCompleted = function(id) return (S.questsDone and S.questsDone[id]) or false end
IsQuestFlaggedCompleted = C_QuestLog.IsQuestFlaggedCompleted
QuestWatchFrame = CreateFrame("Frame", "QuestWatchFrame", UIParent)
-- Blizzard's buttons round the round minimap
-- Forever's parts on the minimap cluster (from /sitrep mapdump)
MinimapCluster.DielFrame = CreateFrame("Frame", nil, MinimapCluster)        -- day / night
MinimapCluster.DielFrame:SetPoint("CENTER", MinimapCluster, "CENTER", 63, 72)
MinimapCluster.IndicatorFrame = CreateFrame("Frame", nil, MinimapCluster)   -- mail
MinimapCluster.Tracking = CreateFrame("Frame", nil, MinimapCluster)
MinimapCluster.MinimapContainer = CreateFrame("Frame", nil, MinimapCluster)
MinimapCluster.MinimapContainer.PlayerCoords = CreateFrame("Frame", nil, MinimapCluster.MinimapContainer) -- coordinates under the map
Minimap.ZoomHitArea = CreateFrame("Frame", nil, Minimap)
Minimap.ZoomHitArea._mouse = true
TimeManagerClockButton = CreateFrame("Button", "TimeManagerClockButton", Minimap)
TimeManagerClockButton:SetPoint("CENTER", Minimap, "CENTER", 0, -75)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", MinimapCluster)
GameTimeFrame:SetPoint("CENTER", Minimap, "CENTER", 52, 52)
MiniMapMailFrame = CreateFrame("Frame", "MiniMapMailFrame", Minimap)
MiniMapMailFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 24, -37)

---------------------------------------------------------------------------
-- Action bars and micro buttons. S.actionRange[slot] = true/false (nil: no
-- range); S.actions are the slots with something on them (as for the tooltip).
---------------------------------------------------------------------------
-- button textures: one region per state, set again by Blizzard's updates
for _, st in ipairs({ "Normal", "Highlight", "Pushed", "Checked" }) do
	local field = "_" .. st:lower()
	Methods["Get" .. st .. "Texture"] = function(s)
		local t = rawget(s, field)
		if not t then t = new("Texture", s); s[field] = t end
		return t
	end
	Methods["Set" .. st .. "Texture"] = function(s, tex) s["Get" .. st .. "Texture"](s):SetTexture(tex) end
end
function Methods.SetTexCoord(s, ...) s._coord = { ... } end
function Methods.SetFrameRef(s, k, f) s._refs = rawget(s, "_refs") or {}; s._refs[k] = f end
function Methods.GetFrameRef(s, k) return (rawget(s, "_refs") or {})[k] end -- (in snippets)
function Methods.RegisterForClicks(s, ...) s._clicks = { ... } end
function Methods.Click(s, button) local fn = s._scripts.OnClick if fn then fn(s, button or "LeftButton", false) end end
-- the modern main bar: its art hangs on it under keys (page switch, border, end caps)
MainActionBar = CreateFrame("Frame", "MainActionBar", UIParent)
MainActionBar._mouse = true -- (on Forever it takes the mouse: seen with /sitrep mouse)
MainActionBar.ActionBarPageNumber = CreateFrame("Frame", nil, MainActionBar)
MainActionBar.BorderArt = MainActionBar:CreateTexture()
MainActionBar.EndCaps = CreateFrame("Frame", nil, MainActionBar)
MainActionBar.QuickKeybindGlow = CreateFrame("Frame", nil, MainActionBar) -- not art: stays
MainActionBar.ActionButtons = {}
-- Blizzard laying the bar out again (Edit Mode): a row, 6 px apart
function MainActionBar:UpdateGridLayout()
	for i, b in ipairs(self.ActionButtons) do
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (i - 1) * 42, 0)
	end
end
for _, bar in ipairs({ { "ActionButton", 12, 0 }, { "MultiBarBottomLeftButton", 12, 60 }, { "PetActionButton", 10 } }) do
	for i = 1, bar[2] do
		local name = bar[1] .. i
		local b = CreateFrame("CheckButton", name, bar[1] == "ActionButton" and MainActionBar or UIParent)
		b._w, b._h = 36, 36
		b._x, b._y = 500 + (i - 1) * 42, bar[1] == "ActionButton" and 40 or 90
		b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", b._x, b._y)
		if bar[1] == "ActionButton" then
			MainActionBar.ActionButtons[i] = b
			b.RightDivider = b:CreateTexture()
		end
		b.icon = b:CreateTexture()
		b.HotKey, b.Count, b.Name = b:CreateFontString(), b:CreateFontString(), b:CreateFontString()
		b.IconMask = b:CreateTexture()
		b.icon:AddMaskTexture(b.IconMask)
		b.SlotArt = b:CreateTexture()
		if bar[3] then b.action = bar[3] + i end
		b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
		if bar[1] == "PetActionButton" then _G[name .. "NormalTexture2"] = b:CreateTexture() end
	end
end
-- classic: the bonus bar (druid forms, stealth, stances) over the main bar
BonusActionBarFrame = CreateFrame("Frame", "BonusActionBarFrame", UIParent)
BonusActionBarTexture0 = BonusActionBarFrame:CreateTexture()
for i = 1, 12 do
	local b = CreateFrame("CheckButton", "BonusActionButton" .. i, BonusActionBarFrame)
	b._w, b._h = 36, 36
	b.icon = b:CreateTexture()
	b:SetPoint("BOTTOMLEFT", BonusActionBarFrame, "BOTTOMLEFT", (i - 1) * 42, 0)
end
MainMenuBarLeftEndCap, MainMenuBarRightEndCap = new("Texture"), new("Texture")
ActionBarUpButton = CreateFrame("Button", "ActionBarUpButton", UIParent)
function HasAction(slot) return (S.actions or {})[slot] ~= nil end
function IsActionInRange(slot) return (S.actionRange or {})[slot] end
function GetCursorInfo() if S.cursor then return unpack(S.cursor) end end
function GetPetActionInfo(i) return (S.petActions or {})[i] end
M.microClicks = {}
for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
	"SocialsMicroButton", "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton" }) do
	local b = CreateFrame("Button", n, UIParent)
	b:SetScript("OnClick", function() table.insert(M.microClicks, n) end)
end
MicroMenuContainer = CreateFrame("Frame", "MicroMenuContainer", UIParent)
CHARACTER_BUTTON, SPELLBOOK_ABILITIES_BUTTON, SPELLBOOK, TALENTS = "Charakterinfo", "Zauberbuch & Fähigkeiten", "Zauberbuch", "Talente"
function GetBindingKey(cmd) return ({ TOGGLECHARACTER0 = "C", TOGGLESPELLBOOK = "P", TOGGLEWORLDMAP = "M" })[cmd] end
function GetBindingText(key) return key end
function GetNetStats() return 0, 0, S.latency or 42, S.latency or 48 end
function GetFramerate() return S.fps or 60 end
function debugprofilestop() return os.clock() * 1000 end
-- (not a tail call: LuaJIT would drop this frame and shift the levels by one)
function debugstack(start)
	local s = debug.traceback("", (start or 1) + 1)
	return s
end
M.memKB = 2048
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage() return M.memKB end
function IsSwimming() return S.swimming or false end
-- friends: S.friendsOnline (in the game), S.bnOnline (Battle.net)
C_FriendList = { GetNumOnlineFriends = function() return S.friendsOnline or 3 end, ShowFriends = function() M.friendsAsked = true end }
function BNGetNumFriends() return 9, S.bnOnline or 2 end
M.friendsOpened = 0
function ToggleFriendsFrame() M.friendsOpened = M.friendsOpened + 1 end
-- secure snippets: kept so a test can run them the way the client would
M.wraps = {}
function SecureHandlerWrapScript(frame, script, header, pre, post)
	table.insert(M.wraps, { frame = frame, script = script, header = header, pre = pre, post = post })
end

return M
