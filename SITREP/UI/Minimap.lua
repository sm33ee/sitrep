-- SITREP · Minimap
-- Blizzard's minimap in SITREP's look: square, framed like the HUD (border and
-- accent brackets), the zone above it (coloured by its PvP status), your
-- coordinates in its corner, zoom on the mouse wheel. Its size is a setting
-- (ui.mapSize). While the HUD is unlocked a handle covers it: drag it to move
-- the map, drag the grip in its bottom left corner to resize it. Never moved, it
-- keeps Blizzard's place.
-- The round border, compass, zone bar and zoom buttons are hidden while this is
-- on; switching it off brings them back (a /reload restores every detail).
-- Glass: the map's corners rounded (a mask, 12 px at any size), the map and the
-- zone strip over it on one glass pane, a fine ring round the map.
-- On the zone strip's right end: a "zen" switch for friendly zen on the plates
-- (plates.friendZen: only enemies, your group and your target keep their bar).
-- Frame names differ between clients: every part is looked up and skipped when
-- missing (/sitrep uidump lists what this client has).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format

local M = {}
ns.Minimap = M

-- the rounded masks: radius in px of the 256 px mask (tools/make_textures.py)
local MAP_RADII = { 26, 20, 15, 12, 9, 7, 5 }
M.CORNER = 12 -- px on screen

-- The mask whose corner is nearest M.CORNER px at this size.
function M.MaskFor(size)
	local want = M.CORNER * 256 / math.max(1, size or 180)
	local best
	for _, r in ipairs(MAP_RADII) do
		if not best or math.abs(r - want) < math.abs(best - want) then best = r end
	end
	return K.MEDIA .. "mapmask" .. best
end
local ROUND = "Textures\\MinimapMask"
-- Blizzard's decorations around the map (whichever this client has)
local DECOR_GLOBALS = { "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapBackdrop", "MinimapZoomIn",
	"MinimapZoomOut", "MinimapZoneTextButton", "MiniMapWorldMapButton", "MinimapToggleButton", "MinimapNorthTag" }
local DECOR_FIELDS = { { "MinimapCluster", "BorderTop" }, { "MinimapCluster", "ZoneTextButton" }, { "Minimap", "ZoomIn" },
	{ "Minimap", "ZoomOut" }, { "MinimapCluster", "Background" },
	-- (an invisible area in the map's corner that takes the mouse to show the zoom buttons)
	{ "Minimap", "ZoomHitArea" } }
local PVP_COLOR = { sanctuary = { 0.41, 0.8, 0.94 }, friendly = { 0.1, 1, 0.1 }, hostile = { 1, 0.1, 0.1 },
	contested = { 1, 0.7, 0 }, combat = { 1, 0.1, 0.1 }, arena = { 1, 0.1, 0.1 } }

M.MIN, M.MAX = 120, 700 -- size range (the console slider uses the same)

-- Blizzard's buttons round the map sit where the round map's rim was: on the square
-- map they go to its corners (back where they were when it is off).
-- { name, point on the button, point on the map, x, y, scale[, "head": on the zone strip] }
-- (names may be paths: Forever hangs most of them on MinimapCluster)
local CORNERS = {
	{ "GameTimeFrame", "TOPRIGHT", "TOPRIGHT", 2, 2, 0.75 },           -- calendar (Forever) / day-night (classic)
	{ "MinimapCluster.DielFrame", "TOPRIGHT", "TOPRIGHT", 0, -18, 0.5 }, -- day / night (Forever), under the calendar
	{ "MinimapCluster.IndicatorFrame", "TOPLEFT", "TOPLEFT", 2, -2, 0.85 }, -- new mail (Forever)
	{ "MinimapCluster.InstanceDifficulty", "TOPLEFT", "TOPLEFT", 0, -18, 0.6 },
	{ "MinimapCluster.Tracking", "BOTTOMLEFT", "BOTTOMLEFT", 2, 2, 1 }, -- tracking (Forever)
	{ "QueueStatusButton", "BOTTOMLEFT", "BOTTOMLEFT", 18, -4, 0.6 },  -- the group finder's eye
	{ "MiniMapMailFrame", "TOPLEFT", "TOPLEFT", -2, 2, 0.85 },         -- new mail
	{ "MiniMapTrackingFrame", "BOTTOMLEFT", "BOTTOMLEFT", -2, -2, 0.85 }, -- tracking (herbs, ores...)
	{ "MiniMapTracking", "BOTTOMLEFT", "BOTTOMLEFT", -2, -2, 0.85 },
	{ "MiniMapBattlefieldFrame", "BOTTOMLEFT", "BOTTOMLEFT", 24, -2, 0.85 },
	{ "MiniMapLFGFrame", "BOTTOMLEFT", "BOTTOMLEFT", 46, -2, 0.85 },
	{ "TimeManagerClockButton", "LEFT", "LEFT", 2, 0, 0.8, "head" },   -- the clock, in the zone strip
}
M.CORNERS = CORNERS

local function P() return ns.P and ns.P.ui end

-- A frame by its name or path ("MinimapCluster.DielFrame"), or nil.
function M.Find(path)
	local f = _G
	for part in path:gmatch("[^%.]+") do
		if type(f) ~= "table" then return nil end
		f = f == _G and _G[part] or rawget(f, part)
	end
	return type(f) == "table" and f ~= _G and f or nil
end

-- Put Blizzard's map buttons in the corners (on) or back (off).
local function corners(on)
	local map = _G.Minimap
	for _, c in ipairs(CORNERS) do
		local b = M.Find(c[1])
		if type(b) == "table" and b.SetPoint then
			if on then
				if not b.srPoints then
					b.srPoints, b.srScale = {}, read(b.GetScale, b) or 1
					for n = 1, (read(b.GetNumPoints, b) or 0) do b.srPoints[n] = { b:GetPoint(n) } end
				end
				b:ClearAllPoints()
				b:SetPoint(c[2], c[7] == "head" and M.frame.head or map, c[3], c[4], c[5])
				pcall(b.SetScale, b, c[6])
				pcall(b.SetFrameLevel, b, map:GetFrameLevel() + 8)
			elseif b.srPoints then
				b:ClearAllPoints()
				for _, pt in ipairs(b.srPoints) do pcall(b.SetPoint, b, unpack(pt)) end
				pcall(b.SetScale, b, b.srScale)
				b.srPoints = nil
			end
		end
	end
end
M.Corners = corners

local function decor()
	local list = {}
	for _, n in ipairs(DECOR_GLOBALS) do if type(_G[n]) == "table" then list[#list + 1] = _G[n] end end
	for _, pair in ipairs(DECOR_FIELDS) do
		local parent = _G[pair[1]]
		local v = type(parent) == "table" and rawget(parent, pair[2])
		if type(v) == "table" then list[#list + 1] = v end
	end
	return list
end
M.Decor = decor
M.NAMES = { globals = DECOR_GLOBALS, fields = DECOR_FIELDS }

local function build()
	local map = _G.Minimap
	if M.frame or type(map) ~= "table" then return end
	local f = CreateFrame("Frame", nil, map)
	f:SetPoint("TOPLEFT", -2, 2)
	f:SetPoint("BOTTOMRIGHT", 2, -2)
	f:SetFrameLevel(map:GetFrameLevel() + 5)
	K.Border(f, C.line2, 1, M.CORNER + 2)
	K.Brackets(f, 10, 2)
	-- one pane behind the map and the zone strip, on a frame of its own in the
	-- lowest strata (under the map's picture: nothing drawn on the map itself)
	do
		local pf = CreateFrame("Frame", nil, UIParent)
		pf:SetFrameStrata("BACKGROUND")
		pf:SetPoint("TOPLEFT", map, "TOPLEFT", -6, 6 + 16)
		pf:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 6, -6)
		f.pane = K.Backdrop(pf, C.bg, M.CORNER + 4)
		f.paneFrame = pf
	end
	-- the zone, on a strip above the map
	f.head = CreateFrame("Frame", nil, f)
	f.head:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
	f.head:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
	f.head:SetHeight(16)
	f.head.bg = K.Tex(f.head, "BACKGROUND", { C.bg[1], C.bg[2], C.bg[3], 0.85 })
	f.head.bg:SetAllPoints()
	f.zone = K.Font(f.head, 11, C.text, K.FONT, "OUTLINE")
	f.zone:SetPoint("CENTER")
	-- friendly zen on and off (bright: on)
	f.zen = CreateFrame("Button", nil, f.head)
	f.zen:SetSize(30, 16)
	f.zen:SetPoint("RIGHT", f.head, "RIGHT", -2, 0)
	f.zen.text = K.Font(f.zen, 10, C.text, K.FONT, "OUTLINE")
	f.zen.text:SetPoint("RIGHT", -2, 0)
	f.zen.text:SetText("zen")
	f.zen:RegisterForClicks("LeftButtonUp")
	f.zen:SetScript("OnClick", function()
		ns.P.plates.friendZen = not ns.P.plates.friendZen
		ns.Changed("plates.friendZen")
	end)
	K.Tooltip(f.zen, "Friendly zen", "Click: only enemies, your group and your target keep their nameplate bar; other friendly plates show the name over a thin health line. Click again: all bars.")
	-- your coordinates, in the bottom right corner
	f.coords = K.Font(f, 10, C.text, K.FONT, "OUTLINE")
	f.coords:SetPoint("BOTTOMRIGHT", -4, 4)
	-- while the HUD is unlocked: a handle to move it (kept by its top right corner,
	-- so it grows down and left) and a grip in the bottom left corner to resize it
	M.mover = K.Mover(map, "minimap", "MINIMAP", "TOPRIGHT")
	f.grip = CreateFrame("Frame", nil, M.mover)
	f.grip:SetSize(14, 14)
	f.grip:SetPoint("BOTTOMLEFT", 1, 1)
	f.grip:SetFrameLevel(M.mover:GetFrameLevel() + 2)
	f.grip.tex = K.Tex(f.grip, "OVERLAY", { 1, 1, 1, 0.5 })
	f.grip.tex:SetPoint("TOPLEFT", 3, -3)
	f.grip.tex:SetPoint("BOTTOMRIGHT", -3, 3)
	K.Tooltip(f.grip, "Minimap size", "Drag to resize. Lock the HUD to hide this.")
	K.DragResize(f.grip, -1, -1, M.MIN, M.MAX, function() return P().mapSize end, function(size, done)
		P().mapSize = size
		pcall(map.SetSize, map, size, size)
		M.mover.Place()
		if done then ns.Changed("ui.mapSize") end
	end)
	local acc = 0
	f:SetScript("OnUpdate", ns.Timed("minimap (f)", function(self, e)
		acc = acc + e
		if acc < 0.2 then return end
		acc = 0
		M.Refresh()
	end))
	M.frame = f
	M.PaintZen()
	-- zoom with the mouse wheel (unless the client does it already)
	if map.EnableMouseWheel and not (map.GetScript and map:GetScript("OnMouseWheel")) then
		map:EnableMouseWheel(true)
		map:SetScript("OnMouseWheel", function(self, delta)
			if not (P() and P().minimap) then return end
			local z, levels = read(self.GetZoom, self), read(self.GetZoomLevels, self)
			if not z then return end
			z = z + (delta > 0 and 1 or -1)
			if z >= 0 and (not levels or z < levels) then pcall(self.SetZoom, self, z) end
		end)
	end
end

-- The zen switch: mint while on, dim while off.
function M.PaintZen()
	local z = M.frame and M.frame.zen
	if not z then return end
	local on = ns.P and ns.P.plates and ns.P.plates.friendZen
	if on then z.text:SetTextColor(0.44, 0.94, 0.65) else z.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
	z.text:SetAlpha(on and 1 or 0.7)
end

-- Zone (PvP colour) and coordinates.
function M.Refresh()
	local f = M.frame
	if not (f and f:IsShown()) then return end
	f.zone:SetText(read(GetMinimapZoneText) or "")
	local pvp = read(GetZonePVPInfo)
	local c = PVP_COLOR[pvp or ""] or { 1, 0.85, 0.3 }
	f.zone:SetTextColor(c[1], c[2], c[3])
	local text = ""
	if P().mapCoords and C_Map and C_Map.GetBestMapForUnit then
		local id = read(C_Map.GetBestMapForUnit, "player")
		local pos = id and read(C_Map.GetPlayerMapPosition, id, "player")
		if type(pos) == "table" then
			local ok, x, y = pcall(pos.GetXY, pos)
			if ok and x and y and not ns.isSecret(x) and (x > 0 or y > 0) then text = format("%.1f, %.1f", x * 100, y * 100) end
		end
		-- the layer (the copy of this zone: Sensors.LayerScan), small and dim after them
		local L = ns.Sensors.layer
		if L.id and L.map == id then text = text .. format("  |cff8a9492L%s|r", tostring(L.id)) end
	end
	f.coords:SetText(text)
end

local function redraw(map)
	-- the map only redraws at its new size after a zoom change
	local z = read(map.GetZoom, map)
	if z then
		pcall(map.SetZoom, map, z > 0 and z - 1 or z + 1)
		pcall(map.SetZoom, map, z)
	end
end

function M.Apply()
	local map = _G.Minimap
	if type(map) ~= "table" or not P() then return end
	build()
	local on = P().minimap and ns.P.enabled
	if not M.origSize then
		local w = read(map.GetWidth, map)
		M.origSize = (w and w > 0) and w or 140
	end
	local size = on and P().mapSize or M.origSize
	if map.SetMaskTexture then pcall(map.SetMaskTexture, map, on and M.MaskFor(size) or ROUND) end
	pcall(map.SetSize, map, size, size)
	redraw(map)
	-- (Blizzard shows its zoom buttons again on mouse-over: Conceal keeps them hidden)
	for _, d in ipairs(decor()) do K.Conceal(d, on) end
	-- Blizzard's coordinates under the map (Forever): SITREP shows them in the corner
	K.Conceal(M.Find("MinimapCluster.MinimapContainer.PlayerCoords"), on and P().mapCoords or false)
	-- its own opacity while SITREP is on (also with the square look off)
	pcall(map.SetAlpha, map, ns.P.enabled and K.Opacity("minimap") or 1)
	K.Background(M.frame.head.bg, "minimap") -- (the zone strip)
	if M.frame.pane then
		-- glass: the pane carries the strip's background
		K.Background(M.frame.pane, "minimap")
		M.frame.paneFrame:SetShown(on)
		M.frame.paneFrame:SetAlpha(ns.P.enabled and K.Opacity("minimap") or 1)
		M.frame.head.bg:SetShown(false)
	end
	M.frame:SetShown(on)
	corners(on)
	if on then M.mover.Place() else M.mover.Restore() end
	M.mover:SetShown(on and not ns.P.hud.locked)
	if on then M.Refresh() end
end

ns.On("SR_LOGIN", function()
	M.Apply()
	-- the modern client lays its minimap out again after Edit Mode: keep SITREP's place
	if type(MinimapCluster) == "table" and type(MinimapCluster.Layout) == "function" then
		hooksecurefunc(MinimapCluster, "Layout", function() if M.mover and P().minimap and ns.P.enabled then M.mover.Place() end end)
	end
end)
ns.On("PLAYER_ENTERING_WORLD", function() if M.frame then M.Apply() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 3) == "ui." or key:sub(1, 4) == "hud." then M.Apply() end
	if key == "*" or key == "plates.friendZen" then M.PaintZen() end
end)
