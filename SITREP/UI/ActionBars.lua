-- SITREP · Action bars
-- Blizzard's action buttons in SITREP's look, where they are (Blizzard and Edit
-- Mode keep placing them; action buttons are secure and may not be moved by an
-- addon in combat): the icon cropped square on a dark tile with a thin border,
-- Blizzard's frame art and rounded mask off, flat highlight / pressed / active
-- states, key bindings and charges in the HUD font, macro names hidden (option),
-- and a red veil over a button whose spell does not reach your target.
-- Empty slots stay invisible until you hold a spell, item or macro on the cursor
-- (ui.barHideEmpty): only their alpha changes, which is allowed in combat too.
-- The bar art goes too (gryphons, backgrounds, page arrows; ui.barArt).
-- Every part is looked up by its name and skipped when missing. Switching the
-- skin off takes effect after /reload (Blizzard's art is put back by the game).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read

local AB = {}
ns.ActionBars = AB

-- button name prefixes and how many each bar has
local BARS = { { "ActionButton", 12 }, { "BonusActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 }, { "MultiBar6Button", 12 },
	{ "MultiBar7Button", 12 }, { "PetActionButton", 10 }, { "StanceButton", 10 }, { "ShapeshiftButton", 10 },
	{ "PossessButton", 2 } }
-- Blizzard's bar art (globals, then fields of the main bar)
local ART = { "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarTexture0", "MainMenuBarTexture1",
	"MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuBarArtFrameBackground", "MainMenuBarPageNumber",
	"ActionBarUpButton", "ActionBarDownButton", "SlidingActionBarTexture0", "SlidingActionBarTexture1", "StanceBarLeft",
	"StanceBarMiddle", "StanceBarRight", "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
	"PossessBackground1", "PossessBackground2", "BonusActionBarTexture0", "BonusActionBarTexture1", "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2",
	"MainMenuMaxLevelBar3" }
local ART_FIELDS = { { "MainMenuBar", "EndCaps" }, { "MainMenuBar", "BorderArt" }, { "MainMenuBar", "Background" },
	{ "MainMenuBar", "ActionBarPageNumber" }, { "MainMenuBarArtFrame", "LeftEndCap" }, { "MainMenuBarArtFrame", "RightEndCap" },
	{ "MainMenuBarArtFrame", "PageNumber" } }
-- The bars' own frames. Modern clients (the main bar is MainActionBar there) hang
-- their art on them under changing keys: every texture of the frame itself and
-- every part whose key looks like art (page switch, end caps, border, dividers)
-- goes. Their buttons and anything else stay.
local CONTAINERS = { "MainActionBar", "MainMenuBar", "MainMenuBarArtFrame", "BonusActionBarFrame", "MultiBarBottomLeft", "MultiBarBottomRight",
	"MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar" }
local ART_KEYS = { "PageNumber", "EndCap", "BorderArt", "Background", "Divider", "Art$", "Gryphon", "Wyvern" }
-- art on each button of the modern main bar
local BUTTON_ART = { "RightDivider", "BottomDivider", "LeftDivider", "TopDivider", "SlotArt", "SlotBackground", "FloatingBG" }
AB.NAMES = { bars = BARS, art = ART, artFields = ART_FIELDS, containers = CONTAINERS }
local RANGE_EVERY = 0.2 -- seconds

local function P() return ns.P and ns.P.ui end

local function sub(b, key, suffix)
	local v = rawget(b, key)
	if type(v) ~= "table" then v = _G[(b:GetName() or "") .. suffix] end
	return type(v) == "table" and v or nil
end

-- Every action button this client has.
function AB.Buttons()
	local list = {}
	for _, bar in ipairs(BARS) do
		for i = 1, bar[2] do
			local b = _G[bar[1] .. i]
			if type(b) == "table" then list[#list + 1] = b end
		end
	end
	return list
end

-- Blizzard's frame around the icon off, also when Blizzard sets it again: through
-- the button (SetNormalTexture / Atlas) or on the texture itself (the modern
-- buttons' NormalTexture: its atlas and alpha set directly).
local function zeroAlpha(t, a)
	if t.srOff and a ~= 0 then t:SetAlpha(0) end
end
local function off(t)
	if type(t) ~= "table" then return end
	t.srOff = true
	t:SetAlpha(0)
	if not t.srOffHook then
		t.srOffHook = true
		pcall(hooksecurefunc, t, "SetAlpha", zeroAlpha)
		for _, fn in ipairs({ "SetAtlas", "SetTexture", "Show" }) do
			if t[fn] then pcall(hooksecurefunc, t, fn, function(self) if self.srOff then self:SetAlpha(0) end end) end
		end
	end
end
local function hideNormal(b)
	off(b.GetNormalTexture and b:GetNormalTexture())
	off(rawget(b, "NormalTexture"))
	-- pet buttons draw a second frame
	local n2 = _G[(b:GetName() or "") .. "NormalTexture2"]
	if type(n2) == "table" then off(n2) end
end

local function flat(b, setter, getter, r, g, bl, a)
	if not b[setter] then return end
	pcall(b[setter], b, K.WHITE)
	local t = b[getter] and b[getter](b)
	if t then
		t:SetVertexColor(r, g, bl, a)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", 1, -1)
		t:SetPoint("BOTTOMRIGHT", -1, 1)
	end
end

function AB.Skin(b)
	if b.srSkin then return end
	b.srSkin = true
	local icon = sub(b, "icon", "Icon")
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local mask = rawget(b, "IconMask")
		if type(mask) == "table" and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, mask) end
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	-- the tile and its border
	local tile = K.Tex(b, "BACKGROUND", C.bg, -8)
	tile:SetAllPoints()
	b.srTile = tile
	local edges = {}
	for n = 1, 4 do edges[n] = K.Tex(b, "OVERLAY", C.line2, 7) end
	edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
	b.srEdges = edges
	-- Blizzard's art around the icon
	hideNormal(b)
	for _, fn in ipairs({ "SetNormalTexture", "SetNormalAtlas" }) do
		if b[fn] then pcall(hooksecurefunc, b, fn, hideNormal) end
	end
	for _, key in ipairs(BUTTON_ART) do
		local t = sub(b, key, key)
		if t then K.Conceal(t, true) end
	end
	-- flat states: hover, pressed, active (auto attack, stance, a spell being cast)
	local r, g, bl = K.Accent()
	flat(b, "SetHighlightTexture", "GetHighlightTexture", 1, 1, 1, 0.15)
	flat(b, "SetPushedTexture", "GetPushedTexture", r, g, bl, 0.35)
	flat(b, "SetCheckedTexture", "GetCheckedTexture", r, g, bl, 0.35)
	K.Paint(function(rr, gg, bb)
		for _, getter in ipairs({ "GetPushedTexture", "GetCheckedTexture" }) do
			local t = b[getter] and b[getter](b)
			if t then t:SetVertexColor(rr, gg, bb, 0.35) end
		end
	end)
	-- texts in the HUD font
	local hotkey = sub(b, "HotKey", "HotKey")
	if hotkey then
		hotkey:SetFont(K.FONT, 10, "OUTLINE")
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", -2, -3)
	end
	local count = sub(b, "Count", "Count")
	if count then
		count:SetFont(K.FONT, 11, "OUTLINE")
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", -2, 3)
	end
	local name = sub(b, "Name", "Name")
	if name then
		name:SetFont(K.FONT, 9, "OUTLINE")
		b.srName = name
	end
	-- out of range: a red veil over the icon
	b.srRange = K.Tex(b, "OVERLAY", { 1, 0.15, 0.15, 0.38 }, 6)
	b.srRange:SetPoint("TOPLEFT", 1, -1)
	b.srRange:SetPoint("BOTTOMRIGHT", -1, 1)
	b.srRange:Hide()
end

local function artKey(k)
	if type(k) ~= "string" then return false end
	for _, pat in ipairs(ART_KEYS) do if k:find(pat) then return true end end
	return false
end
AB.ArtKey = artKey

-- A divider between two buttons: a frame of the bar's with no key of its own (a
-- pool Blizzard fills again whenever it lays the bar out: Edit Mode, a cold start),
-- its parts drawn with the "Divider" atlases (barprobe, 4.1.5).
local function isDivider(k)
	for _, key in ipairs({ "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
		local t = rawget(k, key)
		if type(t) == "table" and t.GetAtlas then
			local a = read(t.GetAtlas, t)
			if type(a) == "string" and a:find("Divider") then return true end
		end
	end
	return false
end
AB.IsDivider = isDivider

-- Bar art: hidden while on (and when Blizzard shows it again).
local function art()
	local list, seen = {}, {}
	local function add(v) if type(v) == "table" and not seen[v] then seen[v] = true; list[#list + 1] = v end end
	for _, n in ipairs(ART) do add(_G[n]) end
	for _, pair in ipairs(ART_FIELDS) do
		local parent = _G[pair[1]]
		add(type(parent) == "table" and rawget(parent, pair[2]) or nil)
	end
	for _, n in ipairs(CONTAINERS) do
		local c = _G[n]
		if type(c) == "table" then
			local ok, regions = pcall(function() return { c:GetRegions() } end)
			for _, r in ipairs(ok and regions or {}) do
				if read(r.GetObjectType, r) == "Texture" then add(r) end
			end
			for k, v in pairs(c) do
				if artKey(k) and type(v) == "table" and v.GetObjectType then add(v) end
			end
			local okC, kids = pcall(function() return { c:GetChildren() } end)
			for _, k in ipairs(okC and kids or {}) do
				if isDivider(k) then add(k) end
			end
		end
	end
	return list
end
AB.Art = art

-- Blizzard lays a bar out again (new dividers from its pool): hidden again.
local artHooked = false
local function hookArt()
	if artHooked then return end
	artHooked = true
	for _, n in ipairs(CONTAINERS) do
		local c = _G[n]
		if type(c) == "table" then
			for _, fn in ipairs({ "UpdateDividers", "UpdateGridLayout" }) do
				if type(c[fn]) == "function" then
					pcall(hooksecurefunc, c, fn, function()
						if not (P() and P().bars and P().barArt and ns.P.enabled) then return end
						for _, f in ipairs(art()) do K.Conceal(f, true) end
					end)
				end
			end
		end
	end
end

-- The slot a button shows (bars page; pet and stance buttons have none).
local function slotOf(b)
	local a = rawget(b, "action")
	if type(a) ~= "number" then a = read(b.GetAttribute, b, "action") end
	return type(a) == "number" and a or nil
end

-- Empty slot: a bar button without an action, a pet button without a pet action.
-- Stance and possess buttons are Blizzard's to show or not.
function AB.Empty(b)
	local slot = slotOf(b)
	if slot then return not read(HasAction, slot) end
	local pet = tonumber(((b.GetName and b:GetName()) or ""):match("^PetActionButton(%d+)$"))
	if pet and GetPetActionInfo then return read(GetPetActionInfo, pet) == nil end
	return false
end

-- Something on the cursor that could go on a bar.
local function holding()
	return GetCursorInfo ~= nil and read(GetCursorInfo) ~= nil
end

-- A button at its alpha: the bar's (b.srAlpha, set by the bar layout), or none
-- while it is an empty slot and nothing is being dragged.
function AB.Show(b)
	local hide = AB.hideEmpty and not AB.holding and AB.Empty(b)
	b.srHidden = hide or nil
	b:SetAlpha(hide and 0 or (b.srAlpha or 1))
end

function AB.UpdateEmpty()
	AB.dirty = false
	AB.hideEmpty = P().barHideEmpty and AB.skinned or false
	AB.holding = holding()
	for _, b in ipairs(AB.buttons or {}) do AB.Show(b) end
end

-- Red veil on buttons whose action does not reach your target.
function AB.UpdateRange()
	local on = P().barRange and AB.skinned
	-- no target: nothing is out of range (the client answers nil for every slot),
	-- so the seventy-odd buttons are not asked; the marks go once
	if on and not read(UnitExists, "target") then
		if AB.rangeShown then
			for _, b in ipairs(AB.buttons or {}) do if b.srRange then b.srRange:Hide() end end
			AB.rangeShown = false
		end
		return
	end
	AB.rangeShown = true
	for _, b in ipairs(AB.buttons or {}) do
		if b.srRange then
			local out = false
			if on and b:IsVisible() then
				local slot = slotOf(b)
				if slot and read(HasAction, slot) then
					local v = read(IsActionInRange, slot) -- false / true (older clients: 0 / 1), nil: no range
					out = v == false or v == 0
				end
			end
			b.srRange:SetShown(out)
		end
	end
end

function AB.Apply()
	if InCombatLockdown() then AB.pending = true return end
	local on = P().bars and ns.P.enabled
	if on then
		AB.buttons = AB.Buttons()
		for _, b in ipairs(AB.buttons) do AB.Skin(b) end
		AB.skinned = true
		if ns.BarLayout then for _, def in ipairs(ns.BarLayout.BARS) do ns.BarLayout.Tiles(def) end end
	elseif AB.skinned then
		ns.print("action bar skin off: /reload puts Blizzard's look back.")
	end
	for _, b in ipairs(AB.buttons or {}) do
		if b.srName then b.srName:SetAlpha(P().barMacroNames and 1 or 0) end
	end
	hookArt()
	for _, f in ipairs(art()) do K.Conceal(f, on and P().barArt or false) end
	if not AB.ticker then
		AB.ticker = CreateFrame("Frame")
		local acc = 0
		AB.ticker:SetScript("OnUpdate", ns.Timed("bars: range (AB.ticker)", function(_, e)
			-- a slot or the cursor changed last frame (Blizzard has updated its buttons by now)
			if AB.dirty then AB.UpdateEmpty() end
			acc = acc + e
			if acc < RANGE_EVERY then return end
			acc = 0
			-- a client without the cursor events still shows the slots while dragging
			if AB.hideEmpty and holding() ~= AB.holding then AB.UpdateEmpty() end
			AB.UpdateRange()
		end))
	end
	AB.UpdateEmpty()
	AB.UpdateRange()
end

-- what changes which slots are empty, or whether something is being dragged
for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
	"UPDATE_VEHICLE_ACTIONBAR", "UPDATE_POSSESS_BAR", "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID",
	"CURSOR_CHANGED", "CURSOR_UPDATE", "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
	ns.On(ev, function() AB.dirty = true end)
end
ns.On("SR_LOGIN", function() AB.Apply() end)
ns.On("PLAYER_REGEN_ENABLED", function() if AB.pending then AB.pending = false; AB.Apply() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 6) == "ui.bar" then AB.Apply() end
end)
