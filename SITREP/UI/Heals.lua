-- SITREP · Heal prediction (ns.Heals)

local ADDON, ns = ...
local K = ns.Kit
local plain = ns.plain

---------------------------------------------------------------------------
-- Heal prediction: heals on their way, drawn as a translucent extension of a
-- health bar, starting where the health ends and clipped at full health.
--   - your own heal: the LOWEST amount its tooltip promises ("812 to 944" ->
--     812), so the bar never promises more than the heal surely brings;
--   - everyone else's: the client's own prediction for their casts.
-- Both parts are status bars anchored to the end of the health fill, so secret
-- values (in combat) still draw: nothing is added up in Lua then, and the
-- client's numbers are shown as they are.
---------------------------------------------------------------------------
local Heals = { stats = { plain = 0, secret = 0, lowest = 0 } }
ns.Heals = Heals
local minCache = {}

-- The lowest amount in a spell description, in any client language: the first
-- pair of numbers joined by a short word or dash ("812 to 944", "812 bis 944",
-- "812 à 944", "812 до 944", "812-944", "812~944").
function Heals.ParseMin(desc)
	if type(desc) ~= "string" or desc == "" then return nil end
	local prevN, prevE
	for s, num, e in desc:gmatch("()(%d[%d%.,]*)()") do
		local n = tonumber((num:gsub("[%.,]+$", ""):gsub("[%.,]", "")))
		if prevN and n then
			local gap = desc:sub(prevE, s - 1)
			if #gap >= 1 and #gap <= 8 and not gap:find("[%.,;:%%%(%)]") and n >= prevN and prevN > 0 then
				return prevN
			end
		end
		prevN, prevE = n, e
	end
	return nil
end

-- Lowest amount of the heal you are casting right now (nil if unknown).
function Heals.MyCastMin()
	local spellID = select(10, pcall(UnitCastingInfo, "player")) -- 9th return, after pcall's ok
	spellID = ns.plain(spellID)
	if type(spellID) ~= "number" then return nil end
	if minCache[spellID] == nil then
		local api = C_Spell and C_Spell.GetSpellDescription
		local desc = api and ns.read(api, spellID)
		if not desc or desc == "" then return nil end -- not loaded yet: ask again later
		minCache[spellID] = Heals.ParseMin(desc) or false
	end
	return minCache[spellID] or nil
end

-- Give a health bar its prediction overlay (once). host: the frame that holds it
-- (default the bar; on a nameplate SITREP's own frame, so nothing of SITREP's hangs
-- in Blizzard's bar). keep = false: the overlay is only returned, not stored on
-- the bar (a bar that is not SITREP's).
function Heals.Attach(hp, mineColor, allColor, host, keep)
	local clip = CreateFrame("Frame", nil, host or hp)
	clip:SetAllPoints(hp)
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end -- never past full health
	clip:SetFrameLevel(hp:GetFrameLevel() + 1)
	local fill = hp:GetStatusBarTexture()
	local function seg(level, c)
		local b = CreateFrame("StatusBar", nil, clip)
		b:SetStatusBarTexture(K.WHITE)
		b:SetStatusBarColor(c[1], c[2], c[3], c[4])
		b:SetPoint("TOPLEFT", fill, "TOPRIGHT")
		b:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
		b:SetWidth(math.max(1, hp:GetWidth()))
		b:SetFrameLevel(clip:GetFrameLevel() + level)
		b:Hide()
		return b
	end
	-- all incoming heals underneath, yours on top (brighter): the part beyond
	-- yours is other healers'
	local all = seg(1, allColor or { 0.30, 0.85, 0.75, 0.38 })
	local mine = seg(2, mineColor or { 0.45, 1.00, 0.55, 0.60 })
	-- (the clip has the bar's size: its own size event, not a hook on the bar)
	clip:SetScript("OnSizeChanged", function(_, w)
		if w and w > 0 then all:SetWidth(w); mine:SetWidth(w) end
	end)
	local h = { all = all, mine = mine, clip = clip }
	if keep ~= false then hp.heal = h end
	return h
end

-- Update a bar's prediction for a unit.
function Heals.Feed(hp, unit) return Heals.FeedTo(hp.heal, unit) end

-- Update an overlay (from Heals.Attach) for a unit.
function Heals.FeedTo(h, unit)
	if not h then return end
	if not unit then h.all:Hide(); h.mine:Hide(); return end
	local okT, total = pcall(UnitGetIncomingHeals, unit)
	local okM, mineC = pcall(UnitGetIncomingHeals, unit, "player")
	if not okT then h.all:Hide(); h.mine:Hide(); return end
	if not okM then mineC = 0 end
	local pt, pm = ns.plain(total), ns.plain(mineC)
	-- a secret can be neither tested nor compared: ask isSecret, never "== nil"
	if not ns.isSecret(total) and not ns.isSecret(mineC) then
		-- plain numbers: swap your share for the lowest amount your spell promises
		pt, pm = pt or 0, pm or 0
		local m = pm
		if m > 0 then
			local lo = Heals.MyCastMin()
			if lo and lo < m and lo >= m * 0.25 then m = lo; Heals.stats.lowest = Heals.stats.lowest + 1 end
		end
		local all = math.max(0, pt - pm) + m
		Heals.stats.plain = Heals.stats.plain + 1
		local ok = pcall(function()
			local hm = UnitHealthMax(unit)
			h.all:SetMinMaxValues(0, hm); h.all:SetValue(all)
			h.mine:SetMinMaxValues(0, hm); h.mine:SetValue(m)
		end)
		h.all:SetShown(ok and all > 0)
		h.mine:SetShown(ok and m > 0)
	else
		-- secret (in combat): the client's own numbers, straight into the bars
		Heals.stats.secret = Heals.stats.secret + 1
		local ok = pcall(function()
			local hm = UnitHealthMax(unit)
			h.all:SetMinMaxValues(0, hm); h.all:SetValue(total)
			h.mine:SetMinMaxValues(0, hm); h.mine:SetValue(mineC)
		end)
		h.all:SetShown(ok); h.mine:SetShown(ok)
	end
end
