-- SITREP · Auras on the plates
-- In combat Forever keeps aura data from addons (lists and lookups refused), but
-- the game's own aura frame on each plate (UnitFrame.AurasFrame: its debuff, buff
-- and crowd-control rows) is drawn by Blizzard's code and keeps working. So SITREP
-- does not read auras here: it places that frame and dresses its icons
-- (plates.auras):
--   place    one row centred right over the plate's name line, a little gap; the
--            same on every plate (your target's a little larger: plates.auraScale)
--   icons    square crop, Blizzard's frame off, a thin dark edge (the debuff's
--            type colour stays where Blizzard shows one), the time left in the
--            HUD font, stacks bottom right
-- Which auras show is Blizzard's choice (on retail: your own debuffs on every enemy,
-- important buffs and crowd control); /sitrep plateauras lists what each plate
-- shows, to see what Forever does.
--
-- Self-contained, to take out in one go: this file and its line in the TOC, the
-- "plateauras" command in Core.lua, its switches on the Nameplates page with their
-- defaults (plates.auras, plates.auraScale), and its block in tests/run.lua.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format

local PA = {}
ns.PlateAuras = PA
local GAP = 3          -- px between the name line and the row
local TARGET_UP = 1.25 -- your target's auras this much larger

local function P() return ns.P and ns.P.plates end
local function on() return P() and P().enabled and P().auras ~= false and ns.P.enabled end

local function aurasOf(s)
	local uf = s and s.uf
	local af = type(uf) == "table" and rawget(uf, "AurasFrame")
	return type(af) == "table" and af.SetPoint and af or nil
end

-- One icon of Blizzard's: dressed once (frames are reused for other auras: the look stays).
local function dress(b)
	if b.srDressed then return end
	local icon = rawget(b, "Icon") or rawget(b, "icon")
	if type(icon) ~= "table" or not icon.SetTexCoord then return end
	b.srDressed = true
	pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
	-- Blizzard's frame round the icon off; a thin dark edge instead
	for _, key in ipairs({ "Border", "border", "IconBorder" }) do
		local t = rawget(b, key)
		if type(t) == "table" and t.SetAlpha then pcall(t.SetAlpha, t, 0) end
	end
	b.srEdge = K.Border(b, { 0, 0, 0, 0.85 }, 1, 0)
	-- the time left and the stacks in the HUD font
	local cd = rawget(b, "Cooldown") or rawget(b, "cooldown")
	if type(cd) == "table" then
		if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, false) end
		local fo = ns.Auras and ns.Auras.TimerFont and ns.Auras.TimerFont(18)
		if fo and cd.SetCountdownFont then pcall(cd.SetCountdownFont, cd, fo) end
	end
	local cf = rawget(b, "CountFrame")
	local count = (type(cf) == "table" and rawget(cf, "Count")) or rawget(b, "Count") or rawget(b, "count")
	if type(count) == "table" and count.SetFont then
		pcall(count.SetFont, count, K.FONT, 9, "OUTLINE")
		pcall(count.ClearAllPoints, count)
		pcall(count.SetPoint, count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	end
end

-- Every icon in the frame's rows (to a few levels down).
local function eachIcon(f, fn, depth)
	depth = depth or 0
	if depth > 3 then return end
	local ok, kids = pcall(function() return { f:GetChildren() } end)
	for _, k in ipairs(ok and kids or {}) do
		if rawget(k, "Icon") or rawget(k, "icon") then fn(k) else eachIcon(k, fn, depth + 1) end
	end
end
PA.EachIcon = eachIcon

-- The row over the name; again whenever Blizzard places it itself.
local placing = false
function PA.Place(s)
	local af = aurasOf(s)
	if not af then return end
	if not af.srHooked then
		af.srHooked = true
		hooksecurefunc(af, "SetPoint", function(self)
			if placing or not self.srSkin then return end
			local sk = self.srSkin
			if sk.active and on() then PA.Place(sk) end
		end)
	end
	af.srSkin = s
	placing = true
	if on() then
		-- Blizzard's place, to give back: a plate's parts may not be measured in
		-- combat (GetPoint refused: that error broke the plate's refresh, 4.3.0);
		-- unread, it goes back over the name later (Release)
		af.srOrig = af.srOrig or (function()
			local pts = {}
			local ok = pcall(function()
				for n = 1, (read(af.GetNumPoints, af) or 0) do pts[n] = { af:GetPoint(n) } end
			end)
			return { points = ok and pts or nil, scale = read(af.GetScale, af) or 1 }
		end)()
		pcall(af.ClearAllPoints, af)
		pcall(af.SetPoint, af, "BOTTOM", s.name, "TOP", 0, GAP)
		local sc = (P().auraScale or 1) * (s.isTarget and TARGET_UP or 1)
		pcall(af.SetScale, af, af.srOrig.scale * sc)
		eachIcon(af, dress)
	elseif af.srOrig then
		PA.GiveBack(af, s)
	end
	placing = false
end

-- Blizzard's place and size back (its points if they could be read, else over its
-- own name, roughly where it keeps it).
function PA.GiveBack(af, s)
	local o = af.srOrig
	pcall(af.ClearAllPoints, af)
	if o.points and #o.points > 0 then
		for _, pt in ipairs(o.points) do pcall(af.SetPoint, af, unpack(pt)) end
	else
		local anchor = (s and s.bname) or (s and s.hb)
		if anchor then pcall(af.SetPoint, af, "BOTTOM", anchor, "TOP", 0, 2) end
	end
	pcall(af.SetScale, af, o.scale)
	af.srOrig = nil
end

-- The plate goes to another unit or SITREP lets it go: Blizzard's place back.
function PA.Release(s)
	local af = aurasOf(s)
	if not (af and af.srOrig) then return end
	placing = true
	PA.GiveBack(af, s)
	af.srSkin = nil
	placing = false
end

-- What Blizzard's aura frames show on each plate (/sitrep plateauras).
function PA.Probe()
	ns.Capture("plateauras", function()
		local n = 0
		for unit, s in pairs(ns.Plates.Current()) do
			n = n + 1
			local af = aurasOf(s)
			if not af then
				ns.print("%s: no AurasFrame", unit)
			else
				local rows = {}
				for _, key in ipairs({ "DebuffListFrame", "BuffListFrame", "CrowdControlListFrame", "LossOfControlFrame" }) do
					local row = rawget(af, key)
					if type(row) == "table" then
						local shown, total = 0, 0
						eachIcon(row, function(b)
							total = total + 1
							if read(b.IsShown, b) then shown = shown + 1 end
						end)
						rows[#rows + 1] = format("%s %d/%d", key:gsub("Frame$", ""):gsub("List$", ""), shown, total)
					end
				end
				local first
				eachIcon(af, function(b)
					if first then return end
					local keys = {}
					for k, v in pairs(b) do if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end end
					table.sort(keys)
					first = table.concat(keys, " ")
				end)
				ns.print("%s %s%s: shown %s, scale %.2f; %s", unit, s.friend and "friend" or "foe", s.isTarget and " (target)" or "",
					tostring(read(af.IsShown, af)), read(af.GetScale, af) or 0, table.concat(rows, ", "))
				if first then ns.print("    an icon's parts: %s", first) end
			end
		end
		if n == 0 then ns.print("no plates on screen") end
	end)
end

-- the plates' own refresh places it (a new unit, your target changed); new icons are dressed as auras come
ns.On("UNIT_AURA", function(_, unit)
	local s = ns.Plates and ns.Plates.skins[unit]
	if s and s.unit == unit and s.active and on() then
		local af = aurasOf(s)
		if af then eachIcon(af, dress) end
	end
end)
