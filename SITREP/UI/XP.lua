-- SITREP · Experience
-- A thin XP line along the bottom edge of your player frame: experience in
-- violet, rested experience ahead of it in a fainter blue. Hovering it shows the
-- numbers. At the level cap (or with experience switched off) it is not there.
-- A hunter's pet learns too: the same line along the bottom of the pet frame
-- (GetPetExperience), while it has a level to reach.
-- Blizzard's own experience bar can be faded out (ui.hideBlizzXP); on the
-- modern client it shares its strip with reputation, which goes with it.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format, min = string.format, math.min

local X = {}
ns.XP = X

local XP_COL, RESTED_COL = { 0.58, 0.42, 1.0, 0.95 }, { 0.30, 0.55, 1.0, 0.45 }
-- Blizzard's experience bars on the various clients
local BLIZZ = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
	"MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }

X.NAMES = BLIZZ

local function P() return ns.P and ns.P.ui end

-- Experience for a kill (Classic's formula, alone): (5 x mob level + 45), 5 % more
-- per level the mob has over you (at most 4 levels), less the further below you
-- it is (ZD: the "zero difference" by your level), nothing once it is grey; elites
-- twice that. With rested experience each kill gives as much again.
local ZD = { { 7, 5 }, { 9, 6 }, { 11, 7 }, { 15, 8 }, { 19, 9 }, { 29, 11 }, { 39, 12 }, { 44, 13 }, { 49, 14 }, { 54, 15 }, { 59, 16 } }
local function zeroDiff(level)
	for _, z in ipairs(ZD) do if level <= z[1] then return z[2] end end
	return 17
end
local function grey(level)
	if level <= 5 then return 0 end
	if level <= 39 then return level - 5 - math.floor(level / 10) end
	if level <= 59 then return level - 1 - math.floor(level / 5) end
	return level - 9
end
function X.MobXP(mob, me, elite)
	if not (mob and me) or mob <= 0 then return 0 end
	if mob <= grey(me) then return 0 end
	local base = mob * 5 + 45
	local xp
	if mob >= me then xp = base * (1 + 0.05 * math.min(mob - me, 4))
	else xp = base * (1 - (me - mob) / zeroDiff(me)) end
	if elite then xp = xp * 2 end
	return math.max(0, math.floor(xp))
end
-- How many of these until your next level (nil: none would do, or at the cap).
function X.KillsToLevel(mob, elite)
	local me = read(UnitLevel, "player")
	local cur, need = read(UnitXP, "player"), read(UnitXPMax, "player")
	if not (me and cur and need and need > 0) then return nil end
	if GetMaxPlayerLevel and me >= (read(GetMaxPlayerLevel) or 60) then return nil end
	local per = X.MobXP(mob, me, elite)
	if per <= 0 then return nil end
	local rested = read(GetXPExhaustion) or 0
	local left, n = need - cur, 0
	while left > 0 and n < 100000 do
		local bonus = math.min(per, rested)
		rested = rested - bonus
		left = left - per - bonus
		n = n + 1
	end
	return n
end

local function build()
	local pf = ns.Frames and ns.Frames.player
	if X.bar or not pf then return end
	local b = CreateFrame("StatusBar", nil, pf)
	b:SetStatusBarTexture(K.WHITE)
	b:SetHeight(2)
	b:SetFrameLevel(pf:GetFrameLevel() + 3)
	b:SetStatusBarColor(XP_COL[1], XP_COL[2], XP_COL[3], XP_COL[4])
	b.bg = K.Tex(b, "BACKGROUND", { 1, 1, 1, 0.06 })
	b.bg:SetAllPoints()
	-- rested: from the end of the experience, as far as it reaches
	b.rested = CreateFrame("StatusBar", nil, b)
	b.rested:SetStatusBarTexture(K.WHITE)
	b.rested:SetAllPoints()
	b.rested:SetFrameLevel(b:GetFrameLevel() - 1)
	b.rested:SetStatusBarColor(RESTED_COL[1], RESTED_COL[2], RESTED_COL[3], RESTED_COL[4])
	-- a slightly taller strip to hover (the line itself is only 2 px)
	b.hover = CreateFrame("Frame", nil, pf)
	b.hover:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, -1)
	b.hover:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 4)
	b.hover:SetFrameLevel(pf:GetFrameLevel() + 4)
	b.hover:EnableMouse(true)
	b.hover:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		local cur, mx, rested = X.Values()
		if not cur then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(format("Experience %d / %d  (%.0f%%)", cur, mx, cur / mx * 100), 1, 1, 1)
		GameTooltip:AddLine(format("%d to the next level", mx - cur), 0.75, 0.8, 0.78)
		if rested and rested > 0 then GameTooltip:AddLine(format("Rested %d  (%.0f%% of a level)", rested, rested / mx * 100), 0.3, 0.55, 1) end
		GameTooltip:Show()
	end)
	b.hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	X.bar = b
	X.Place()
end

-- On the frame's bottom edge; in glass from where its corners start to round, like
-- the line under the banner.
X.RADIUS = 12 -- the player frame's corners (UI/Frames)
function X.Place()
	local b, pf = X.bar, ns.Frames and ns.Frames.player
	if not (b and pf) or b.placed then return end
	b.placed = true
	local inset, lift = X.RADIUS, 0
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", inset, lift)
	b:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -inset, lift)
end

-- Current and needed experience and rested experience, or nil at the cap.
function X.Values()
	if read(IsXPUserDisabled) then return nil end
	local mx = read(UnitXPMax, "player")
	if not mx or mx <= 0 then return nil end
	local lvl, cap = read(UnitLevel, "player"), read(GetMaxPlayerLevel)
	if lvl and cap and lvl >= cap then return nil end
	return read(UnitXP, "player") or 0, mx, read(GetXPExhaustion) or 0
end

function X.Refresh()
	local b = X.bar
	if not b then return end
	X.Place()
	local on = P() and P().xp and ns.P.enabled and ns.Frames.player:IsShown()
	local cur, mx, rested = X.Values()
	local show = on and cur ~= nil or false
	b:SetShown(show)
	b.hover:SetShown(show)
	if not show then return end
	b:SetMinMaxValues(0, mx)
	b:SetValue(cur)
	b.rested:SetMinMaxValues(0, mx)
	b.rested:SetValue(min(mx, cur + (rested or 0)))
end

local function fadeBlizzard()
	local hide = P() and P().xp and P().hideBlizzXP and ns.P.enabled
	for _, n in ipairs(BLIZZ) do
		local f = _G[n]
		K.Conceal(type(f) == "table" and f or nil, hide)
	end
end

function X.Apply()
	build()
	fadeBlizzard()
	X.Refresh()
	X.RefreshPet()
end

-- The pet's line: like yours, without rested experience.
local function buildPet()
	local pf = ns.Frames and ns.Frames.pet
	if X.petBar or not pf then return end
	local b = CreateFrame("StatusBar", nil, pf)
	b:SetStatusBarTexture(K.WHITE)
	b:SetHeight(2)
	b:SetFrameLevel(pf:GetFrameLevel() + 3)
	b:SetStatusBarColor(XP_COL[1], XP_COL[2], XP_COL[3], XP_COL[4])
	b.bg = K.Tex(b, "BACKGROUND", { 1, 1, 1, 0.06 })
	b.bg:SetAllPoints()
	b:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT", X.RADIUS, 0)
	b:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -X.RADIUS, 0)
	b.hover = CreateFrame("Frame", nil, pf)
	b.hover:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, -1)
	b.hover:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 4)
	b.hover:SetFrameLevel(pf:GetFrameLevel() + 6) -- (over the button that targets what it attacks)
	b.hover:EnableMouse(true)
	b.hover:SetScript("OnEnter", function(self)
		local cur, mx = X.PetValues()
		if not (GameTooltip and cur) then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(format("Pet experience %d / %d  (%.0f%%)", cur, mx, cur / mx * 100), 1, 1, 1)
		GameTooltip:AddLine(format("%d to its next level", mx - cur), 0.75, 0.8, 0.78)
		GameTooltip:Show()
	end)
	b.hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	X.petBar = b
end

-- The pet's experience and what it needs, or nil (no pet, or one that does not learn).
function X.PetValues()
	if not GetPetExperience or read(UnitExists, "pet") ~= true then return nil end
	local cur, mx = read(GetPetExperience)
	if type(cur) ~= "number" or type(mx) ~= "number" or mx <= 0 then return nil end
	return cur, mx
end

function X.RefreshPet()
	buildPet()
	local b = X.petBar
	if not b then return end
	local cur, mx = X.PetValues()
	local show = P() and P().xp and ns.P.enabled and cur ~= nil or false
	b:SetShown(show)
	b.hover:SetShown(show)
	if not show then return end
	b:SetMinMaxValues(0, mx)
	b:SetValue(cur)
end

ns.On("SR_LOGIN", function() X.Apply() end)
for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do ns.On(e, function() X.Refresh() end) end
ns.On("UNIT_PET_EXPERIENCE", function() X.RefreshPet() end)
ns.On("UNIT_PET", function(_, unit) if unit == "player" then X.RefreshPet() end end)
ns.On("UNIT_LEVEL", function(_, unit) if unit == "pet" then X.RefreshPet() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 3) == "ui." or key:sub(1, 7) == "frames." then X.Apply() end
end)
