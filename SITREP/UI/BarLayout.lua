-- SITREP · Bar layout
-- Each action bar where you want it, as large as you want, with the gap and the
-- buttons per row you choose (P.bars[id] = { scale, gap, cols }; ui.barLayout).
-- The buttons stay Blizzard's (their bar still decides when they show, and the
-- paging stays the game's): SITREP only anchors them to a holder of its own, one
-- per bar, in a grid. Action buttons are secure: they are placed out of combat
-- only (a change made in combat waits for its end). The holder starts where
-- Blizzard had the bar's first button, so switching this on moves nothing but the
-- gaps; unlock the HUD to drag a bar. Blizzard laying its bars out again (Edit
-- Mode) is undone. Switched off, every button goes back to Blizzard's anchors.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format, ceil, min = string.format, math.ceil, math.min

local BL = {}
ns.BarLayout = BL

-- { id, label, button prefixes (the first one this client has), count, Blizzard's bar frames,
--   buttons shown in place of these (classic clients: the bonus bar of druid forms,
--   stealth and stances lies over the main bar) }
local BARS = {
	{ "main", "Main bar", { "ActionButton" }, 12, { "MainActionBar", "MainMenuBar" }, "BonusActionButton" },
	{ "bottomleft", "Bottom left", { "MultiBarBottomLeftButton" }, 12, { "MultiBarBottomLeft" } },
	{ "bottomright", "Bottom right", { "MultiBarBottomRightButton" }, 12, { "MultiBarBottomRight" } },
	{ "right", "Right", { "MultiBarRightButton" }, 12, { "MultiBarRight" } },
	{ "left", "Right 2", { "MultiBarLeftButton" }, 12, { "MultiBarLeft" } },
	{ "bar5", "Bar 5", { "MultiBar5Button" }, 12, { "MultiBar5" } },
	{ "bar6", "Bar 6", { "MultiBar6Button" }, 12, { "MultiBar6" } },
	{ "bar7", "Bar 7", { "MultiBar7Button" }, 12, { "MultiBar7" } },
	{ "pet", "Pet bar", { "PetActionButton" }, 10, { "PetActionBar", "PetActionBarFrame" } },
	{ "stance", "Stance bar", { "StanceButton", "ShapeshiftButton" }, 10, { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" } },
}
BL.BARS = BARS
BL.holders = {}

local function P() return ns.P and ns.P.ui end

-- The buttons of one bar, in order.
function BL.Buttons(def)
	for _, prefix in ipairs(def[3]) do
		if type(_G[prefix .. "1"]) == "table" then
			local list = {}
			for i = 1, def[4] do
				local b = _G[prefix .. i]
				if type(b) == "table" then list[#list + 1] = b end
			end
			return list
		end
	end
	return {}
end

-- The buttons shown in place of a bar's own (the classic bonus bar), if any.
function BL.Overlay(def)
	local list = {}
	if def[6] then
		for i = 1, def[4] do
			local b = _G[def[6] .. i]
			if type(b) == "table" then list[#list + 1] = b end
		end
	end
	return list
end

-- The bars this client has: { id = label } in order, for the console.
function BL.Options()
	local out = {}
	for _, def in ipairs(BARS) do
		if #BL.Buttons(def) > 0 then out[#out + 1] = { def[1], def[2] } end
	end
	return out
end

local function keepOriginal(b)
	if b.srOrig then return end
	local pts = {}
	for n = 1, (read(b.GetNumPoints, b) or 0) do pts[n] = { b:GetPoint(n) } end
	b.srOrig = { points = pts, scale = read(b.GetScale, b) or 1, -- alpha: not the 0 of an empty slot SITREP hides
		alpha = b.srAlpha or (not b.srHidden and read(b.GetAlpha, b)) or 1 }
end

local function restore(b)
	local o = b.srOrig
	if not o then return end
	b:ClearAllPoints()
	for _, pt in ipairs(o.points) do pcall(b.SetPoint, b, unpack(pt)) end
	b:SetScale(o.scale)
	b.srAlpha = o.alpha
	if ns.ActionBars then ns.ActionBars.Show(b) else b:SetAlpha(o.alpha) end
	b.srOrig = nil
end

-- How much one unit of a button is on the screen, in UIParent's units.
local function unit(b, scale)
	local parent = b:GetParent()
	local pe = parent and read(parent.GetEffectiveScale, parent) or 1
	return pe * scale / (read(UIParent.GetEffectiveScale, UIParent) or 1)
end

local function holder(def)
	local h = BL.holders[def[1]]
	if h then return h end
	h = CreateFrame("Frame", "SITREP_Bar_" .. def[1], UIParent)
	h:SetFrameStrata("HIGH")
	h:SetSize(10, 10)
	h.bg = K.Tex(h, "BACKGROUND", { 0.36, 1, 0.55, 0.12 })
	h.bg:SetAllPoints()
	h.edges = K.Border(h, { 0.36, 1, 0.55, 0.7 })
	h.label = K.Font(h, 11, C.text, K.FONT, "OUTLINE")
	h.label:SetPoint("CENTER")
	h.label:SetText(K.Upper(def[2]))
	K.Movable(h, "bar_" .. def[1], { "CENTER", "CENTER", 0, 0 })
	BL.holders[def[1]] = h
	return h
end

-- Show the holder as a drag handle (HUD unlocked) or not at all.
local function handle(h, show)
	h.bg:SetShown(show)
	for i = 1, 4 do h.edges[i]:SetShown(show) end
	h.label:SetShown(show)
	h:EnableMouse(show)
end

-- One bar: buttons in a grid on the holder.
function BL.Layout(def)
	local buttons = BL.Buttons(def)
	if #buttons == 0 then return end
	local c = ns.P.bars[def[1]]
	local h = holder(def)
	local first = buttons[1]
	local id = "bar_" .. def[1]
	-- never placed: start where Blizzard has the first button
	if not ns.P.hud.pos[id] then
		restore(first)
		local x, y = read(first.GetLeft, first), read(first.GetTop, first)
		if x and y then
			local u = unit(first, read(first.GetScale, first) or 1)
			ns.P.hud.pos[id] = { "TOPLEFT", "BOTTOMLEFT", x * u, y * u }
		end
	end
	h:RestorePosition()
	local size = read(first.GetWidth, first) or 36
	local cols = min(c.cols, #buttons)
	local rows = ceil(#buttons / cols)
	local function place(b, i)
		keepOriginal(b)
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		b:SetScale(c.scale)
		b.srAlpha = c.alpha or 1 -- (an empty slot stays invisible: ActionBars)
		if ns.ActionBars then ns.ActionBars.Show(b) else b:SetAlpha(b.srAlpha) end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", h, "TOPLEFT", col * (size + c.gap), -row * (size + c.gap))
	end
	for i, b in ipairs(buttons) do place(b, i) end
	-- the buttons that take these buttons' place (same slot, same spot)
	for i, b in ipairs(BL.Overlay(def)) do place(b, i) end
	local u = unit(first, c.scale)
	h:SetSize((cols * size + (cols - 1) * c.gap) * u, (rows * size + (rows - 1) * c.gap) * u)
	handle(h, not ns.P.hud.locked and (first:IsVisible() or def[1] == "main"))
	h:Show()
end

-- The tiles under a bar's buttons in its background opacity (with or without the layout).
function BL.Tiles(def)
	local a = ns.P.bars[def[1]].bg
	for _, list in ipairs({ BL.Buttons(def), BL.Overlay(def) }) do
		for _, b in ipairs(list) do if b.srTile then K.Background(b.srTile, nil, a) end end
	end
end

-- Blizzard's own bar frames stay where the game put them, empty once SITREP
-- holds the buttons, and (MainActionBar on Forever) still take the mouse there:
-- clicks meant for what lies under them were lost. While the layout is on they
-- take none (their buttons, now on SITREP's holders, still do); off: as they were.
function BL.Containers(on)
	for _, def in ipairs(BARS) do
		for _, n in ipairs(def[5]) do
			local bar = _G[n]
			if type(bar) == "table" and bar.EnableMouse then
				if on then
					if bar.srMouse == nil then bar.srMouse = read(bar.IsMouseEnabled, bar) and true or false end
					pcall(bar.EnableMouse, bar, false)
				elseif bar.srMouse ~= nil then
					pcall(bar.EnableMouse, bar, bar.srMouse)
					bar.srMouse = nil
				end
			end
		end
	end
end

function BL.Apply()
	if InCombatLockdown() then BL.pending = true return end
	local on = P().barLayout and ns.P.enabled
	for _, def in ipairs(BARS) do
		BL.Tiles(def)
		if on then
			BL.Layout(def)
		else
			for _, b in ipairs(BL.Buttons(def)) do restore(b) end
			for _, b in ipairs(BL.Overlay(def)) do restore(b) end
			if BL.holders[def[1]] then BL.holders[def[1]]:Hide() end
		end
	end
	BL.Containers(on and true or false)
end

-- Blizzard lays a bar out again (Edit Mode, settings): SITREP's grid again.
local hooked = false
local function hookBlizzard()
	if hooked then return end
	hooked = true
	for _, def in ipairs(BARS) do
		for _, n in ipairs(def[5]) do
			local bar = _G[n]
			if type(bar) == "table" and type(bar.UpdateGridLayout) == "function" then
				hooksecurefunc(bar, "UpdateGridLayout", function()
					if not (P() and P().barLayout and ns.P.enabled) then return end
					if InCombatLockdown() then BL.pending = true else BL.Layout(def); BL.Containers(true) end
				end)
			end
		end
	end
end

ns.On("SR_LOGIN", function() hookBlizzard(); BL.Apply() end)
ns.On("PLAYER_ENTERING_WORLD", function() if hooked then BL.Apply() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if BL.pending then BL.pending = false; BL.Apply() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 5) == "bars." or key == "ui.barLayout" or key:sub(1, 4) == "hud." then BL.Apply() end
end)
