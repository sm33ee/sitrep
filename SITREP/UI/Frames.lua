-- SITREP · Unit frames: shell and wiring
-- The frames themselves live in their own files:
--   FramePlayer.lua   your frame (survivability), popping numbers, cost preview
--   FrameTarget.lua   your target (fire control), its target's health
--   FrameGroup.lua    your pet, your target's pet, the party
-- Building blocks they share (bars, cast bar, health colours, highlights) are
-- in Units.lua; who-targets-whom counts in Targeting.lua.
-- This file: the frame shell every frame starts from, the hit/heal flash,
-- Blizzard's frames faded out, showing and hiding (F.Apply), and the events.
--
-- Frames: F.player, F.target, F.pet, F.tpet, F.party (+ F.partyMembers[1..4]),
-- and F.frames[id] for every frame with a shell (player, target, pet, targetpet).
-- The frames are click-to-target buttons (secure): size, position and showing
-- change only out of combat (F.Apply waits for the end of combat).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read, plain = ns.read, ns.plain
local min, max = math.min, math.max

local F = {}
ns.Frames = F
F.frames = {}
F.partyMembers = {}

local U = ns.Units
local feedBar, healthText, percentText, updateCast = U.FeedBar, U.HealthText, U.PercentText, U.UpdateCast

local function frameShell(id, unit, title, default)
	local P = ns.P.frames
	local f = CreateFrame("Button", "SITREP_" .. id .. "Frame", UIParent, "SecureUnitButtonTemplate")
	f:SetSize(P.width, 10)
	f:SetFrameStrata("MEDIUM")
	f.bg = K.Backdrop(f, C.bg, 12, { mood = true })
	f.bg:SetAllPoints()
	K.Border(f, C.line, nil, 12)
	K.Brackets(f, 9, 2)
	f:SetAttribute("unit", unit)
	f:SetAttribute("type1", "target")
	f:SetAttribute("type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f.unit = unit
	K.Movable(f, id, default)
	-- hit / heal flash: a full-height edge on the left
	f.flash = K.Tex(f, "OVERLAY")
	-- (inside the rounded corners: a short bar on the left edge)
	f.flash:SetPoint("TOPLEFT", 0, -12); f.flash:SetPoint("BOTTOMLEFT", 0, 12)
	f.flash:SetWidth(3)
	f.flash:SetAlpha(0)
	f.title = K.Font(f, 10, C.dim, K.FONT, "")
	f.title:SetPoint("TOPLEFT", 8, -6)
	f.title:SetText(title)
	f.tags = K.Font(f, 10, C.dim, K.FONT, "")
	f.tags:SetPoint("TOPRIGHT", -8, -6)
	f.unlock = K.Tex(f, "OVERLAY", { 1, 1, 1, 0.04 })
	f.unlock:SetAllPoints()
	F.frames[id] = f
	return f
end
F.Shell = frameShell

local function flash(f, r, g, b, strength)
	if not (f and ns.P.frames.flash) then return end
	f.flash:SetVertexColor(r, g, b, 1)
	f.flashT = GetTime()
	f.flashS = min(1, max(0.35, strength or 0.5))
	f.flash:SetAlpha(f.flashS)
	if not f.flashing then
		f.flashing = true
		f:SetScript("OnUpdate", function(self)
			local t = GetTime() - self.flashT
			if t > 0.45 then self.flash:SetAlpha(0); self.flashing = false; self:SetScript("OnUpdate", self.castUpdate) return end
			self.flash:SetAlpha(self.flashS * (1 - t / 0.45))
			if self.castUpdate then self.castUpdate(self) end
		end)
	end
end
F.Flash = flash

---------------------------------------------------------------------------
-- Blizzard frames: faded out and click-through while SITREP's are on, all their
-- parts too (their portrait and bars showed their tooltips through: K.Fade, deep).
-- Only alpha and mouse are touched; no secure attributes are written.
---------------------------------------------------------------------------
local pendingBlizzard
-- Parts of Blizzard's raid-style members that ignore their parent's alpha: fading
-- the frame leaves them on screen (raidprobe 4.11.5: a targeted member's selection
-- highlight floating where Blizzard's raid frame would be). Each made see-through
-- on its own (texture alpha: allowed in combat too), and given back as it was.
local function looseParts(frame, hide)
	if type(frame) ~= "table" or not frame.GetRegions then return end
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	for _, r in ipairs(ok and regions or {}) do
		if r.srLoose or ns.read(r.IsIgnoringParentAlpha, r) == true then
			if not r.srLoose then r.srLoose = ns.read(r.GetAlpha, r) or 1 end
			pcall(r.SetAlpha, r, hide and 0 or r.srLoose)
		end
	end
end
local function raidMembers(fn)
	for g = 1, 8 do for m = 1, 5 do fn(_G["CompactRaidGroup" .. g .. "Member" .. m]) end end
	for i = 1, 40 do fn(_G["CompactRaidFrame" .. i]) end
end
local function applyBlizzard()
	local P = ns.P.frames
	local hidePlayer = P.hideBlizzard and P.player and ns.P.enabled
	local hideTarget = P.hideBlizzard and P.target and ns.P.enabled
	local hidePet = P.hideBlizzard and P.pet and ns.P.enabled
	local hideParty = P.hideBlizzard and P.party and ns.P.enabled
	local hideRaid = P.hideBlizzard and P.raid and ns.P.enabled
	if InCombatLockdown() then pendingBlizzard = true end
	local function set(frame, hide)
		if type(frame) ~= "table" then return end
		-- (shown again: one that was never faded stays as it is)
		if hide or frame.srFaded then K.Fade(frame, hide and true or false, 6) end
	end
	set(_G.PlayerFrame, hidePlayer)
	set(_G.TargetFrame, hideTarget)
	set(_G.TargetFrameToT, hideTarget)
	-- Blizzard's pet frame hangs off its player frame: faded with it, so when
	-- SITREP's pet frame is off it must ignore its parent's alpha to stay visible
	local pf = _G.PetFrame
	if pf then
		if pf.SetIgnoreParentAlpha then pcall(pf.SetIgnoreParentAlpha, pf, hidePlayer and not hidePet) end
		set(pf, hidePet)
	end
	-- Blizzard's party frames, both styles (each member is its own clickable frame)
	set(_G.PartyFrame, hideParty)
	set(_G.CompactPartyFrame, hideParty)
	for i = 1, 5 do
		set(_G["CompactPartyFrameMember" .. i], hideParty)
		looseParts(_G["CompactPartyFrameMember" .. i], hideParty)
		local pm = _G.PartyFrame and _G.PartyFrame["MemberFrame" .. i]
		if type(pm) == "table" then set(pm, hideParty) end
	end
	-- Blizzard's raid frames (members made later: faded again on every roster
	-- change, after combat if need be); not its side panel: the raid leader's tools
	-- (ready check, marks) live there
	set(_G.CompactRaidFrameContainer, hideRaid)
	raidMembers(function(f) looseParts(f, hideRaid) end)
	F.blizzardHidden = { player = hidePlayer, target = hideTarget, pet = hidePet, party = hideParty, raid = hideRaid }
end
F.ApplyBlizzard = applyBlizzard

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local pendingApply
function F.Apply()
	local player, target, pet, tpet, party = F.player, F.target, F.pet, F.tpet, F.party
	if not player then return end
	if InCombatLockdown() then pendingApply = true return end -- secure frames: change only out of combat
	local P, H = ns.P.frames, ns.P.hud
	for id, f in pairs(F.frames) do
		f:SetWidth(P.width)
		f.hpTicks.Layout(P.width - 16)
		f:SetScale(H.scale * (H.frameScale[id] or 1))
		if id ~= "player" then f:SetAlpha(K.Opacity(id)) end -- (the player frame fades: UI/HUD.lua)
		K.Background(f.bg, id)
		f:RestorePosition()
		f.unlock:SetShown(not H.locked)
	end
	player:SetShown(P.player and ns.P.enabled and not ns.hudHidden)
	if P.target and ns.P.enabled and not ns.hudHidden then
		if not H.locked and ns.Config and ns.Config.IsOpen() then
			pcall(UnregisterUnitWatch, target)
			target:Show() -- placing it: visible while the console is open and the HUD unlocked
		else
			pcall(RegisterUnitWatch, target) -- otherwise only while you have a target
		end
	else
		pcall(UnregisterUnitWatch, target)
		target:Hide()
	end
	-- pet frames: only while the pet exists (or while placing them)
	for _, pf in ipairs({ { pet, P.pet }, { tpet, P.targetPet } }) do
		local f, on = pf[1], pf[2]
		if on and ns.P.enabled and not ns.hudHidden then
			if not H.locked and ns.Config and ns.Config.IsOpen() then
				pcall(UnregisterUnitWatch, f)
				f:Show()
			else
				pcall(RegisterUnitWatch, f)
			end
		else
			pcall(UnregisterUnitWatch, f)
			f:Hide()
		end
	end
	-- party: the header only in a group (state driver), each member only while it exists
	party:SetWidth(P.width)
	party:SetScale(H.scale * (H.frameScale.party or 1))
	party:SetAlpha(K.Opacity("party"))
	party:RestorePosition()
	party.unlock:SetShown(not H.locked)
	for _, m in ipairs(F.partyMembers) do
		K.Background(m.bg, "party")
		m:SetWidth(P.width)
		m.hpTicks.Layout(P.width - 16)
	end
	F.PartyLayout(P.partyCompact)
	if P.party and ns.P.enabled and not ns.hudHidden then
		if not H.locked and ns.Config and ns.Config.IsOpen() then
			pcall(UnregisterStateDriver, party, "visibility")
			party:Show()
			for _, m in ipairs(F.partyMembers) do pcall(UnregisterUnitWatch, m); m:Show() end
		else
			-- (in a raid the raid frames take over: FrameRaid)
			if not pcall(RegisterStateDriver, party, "visibility", "[group:raid] hide; [group] show; hide") then
				party:SetShown(not (IsInRaid and IsInRaid()))
			end
			for _, m in ipairs(F.partyMembers) do pcall(RegisterUnitWatch, m) end
		end
	else
		pcall(UnregisterStateDriver, party, "visibility")
		party:Hide()
		for _, m in ipairs(F.partyMembers) do pcall(UnregisterUnitWatch, m); m:Hide() end
	end
	if F.ApplyRaid then F.ApplyRaid() end
	applyBlizzard()
end

function F.Build()
	F.BuildPlayer()
	F.HookTooltip()
	F.BuildTarget()
	F.BuildPet()
	F.BuildParty()
	if F.BuildRaid then F.BuildRaid() end
	F.Apply()
	if _G.TargetFrame and hooksecurefunc then
		-- Blizzard re-shows its target frame on every new target; keep it faded.
		pcall(hooksecurefunc, _G.TargetFrame, "Show", function(self)
			if F.blizzardHidden and F.blizzardHidden.target then pcall(self.SetAlpha, self, 0) end
		end)
	end
end

ns.On("SR_LOGIN", function() F.Build() end)

-- The target frame is refreshed whether or not it is visible yet: the client's
-- unit watch may show it a moment after the target changes.
local TICK = { "UpdatePlayer", "UpdateCost", "UpdateTarget", "UpdatePet", "UpdateTargetPet", "UpdateParty" }
local timed = {} -- (each its own line in /sitrep perf)
for _, name in ipairs(TICK) do timed[name] = ns.Timed("frames: " .. name, function() return F[name]() end) end
ns.On("SR_TICK", function()
	if not F.player then return end
	-- each frame on its own: one that fails must not freeze the others
	for _, name in ipairs(TICK) do
		local ok, err = pcall(timed[name])
		if not ok then ns.error(err) end
	end
end)

ns.On("GROUP_ROSTER_UPDATE", function()
	if F.party then F.UpdateParty() end
	-- (Blizzard makes group and raid members as they join: faded too)
	if F.blizzardHidden and (F.blizzardHidden.raid or F.blizzardHidden.party) then applyBlizzard() end
end)

-- a pet summoned, dismissed or swapped (yours, or your target's)
ns.On("UNIT_PET", function(_, unit)
	if unit == "player" and F.pet then F.UpdatePet() end
	if unit == "target" and F.tpet then F.UpdateTargetPet() end
end)

ns.On("PLAYER_TARGET_CHANGED", function()
	if F.target then F.UpdateTarget() end
	if F.tpet then F.UpdateTargetPet() end
	if ns.Targeting then ns.Targeting.UpdateFocus() end -- (how many are on it, you too)
	for _, m in ipairs(F.partyMembers or {}) do F.MemberTarget(m) end -- (mint: your target too)
end)
-- a member of your group targets something else: the line in their frame
ns.On("UNIT_TARGET", function(_, unit)
	local m = F.PartyMember and F.PartyMember(unit)
	if not m then return end
	-- (the counts change for every member's line)
	if ns.Targeting then ns.Targeting.UpdateFocus() end
	for _, o in ipairs(F.partyMembers) do F.MemberTarget(o) end
end)

local function onUnitHealth(_, unit)
	local player, target, pet, tpet = F.player, F.target, F.pet, F.tpet
	local partyMember = F.PartyMember
	if unit == "player" and player and player:IsShown() then
		feedBar(player.hp, UnitHealth, UnitHealthMax, "player")
		F.PlayerHealthColor(player.hp)
		healthText(player.hpText, "player")
		ns.Heals.Feed(player.hp, "player")
	elseif unit == "target" and target then
		feedBar(target.hp, UnitHealth, UnitHealthMax, "target")
		healthText(target.hpText, "target")
		percentText(target.pctText, "target")
		ns.Heals.Feed(target.hp, "target")
	elseif unit == "targetpet" and tpet then
		F.UpdateTargetPet()
	elseif partyMember(unit) then
		F.UpdateMember(partyMember(unit))
	elseif unit == "pet" and pet then
		feedBar(pet.hp, UnitHealth, UnitHealthMax, "pet")
		F.PetHealthColor(pet.hp, "pet")
		healthText(pet.hpText, "pet")
		percentText(pet.pctText, "pet")
		ns.Heals.Feed(pet.hp, "pet")
	end
end
ns.On("UNIT_HEALTH", onUnitHealth)
ns.On("UNIT_MAXHEALTH", onUnitHealth)
-- a heal starts, lands or is cancelled
ns.On("UNIT_HEAL_PREDICTION", function(_, unit)
	local player, target, pet, tpet = F.player, F.target, F.pet, F.tpet
	local partyMember = F.PartyMember
	if unit == "player" and player then ns.Heals.Feed(player.hp, "player") end
	if unit == "target" and target then ns.Heals.Feed(target.hp, "target") end
	if unit == "pet" and pet then ns.Heals.Feed(pet.hp, "pet") end
	if unit == "targetpet" and tpet then ns.Heals.Feed(tpet.hp, "targetpet") end
	if partyMember(unit) then ns.Heals.Feed(partyMember(unit).hp, unit) end
	if ns.HUD and ns.HUD.FeedRowHeals then ns.HUD.FeedRowHeals(unit) end
end)

for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
	ns.On(e, function(_, unit)
		local target, pet, tpet, partyMember = F.target, F.pet, F.tpet, F.PartyMember
		if unit == "target" and target then
			updateCast(target, "target")
			if F.FitPane then F.FitPane(target) end -- (glass: the pane grows with the cast bar)
		elseif unit == "pet" and pet then updateCast(pet, "pet")
		elseif unit == "targetpet" and tpet then updateCast(tpet, "targetpet")
		elseif partyMember(unit) then updateCast(partyMember(unit), unit) end
	end)
end

ns.On("UNIT_COMBAT", function(_, unit, action, flag, amount)
	local player, pet, tpet, partyMember = F.player, F.pet, F.tpet, F.PartyMember
	if not player then return end
	local f = (unit == "player" and player) or (unit == "pet" and pet) or (unit == "targetpet" and tpet) or partyMember(unit)
	if not f then return end
	if f == player and (action == "WOUND" or action == "HEAL") then
		local crit = not ns.isSecret(flag) and type(flag) == "string" and flag:find("CRITICAL", 1, true) ~= nil
		F.Pop(f, action == "WOUND" and "dmg" or "heal", amount, crit)
	end
	amount = plain(amount)
	local m = unit == "player" and ns.Pressure.max or read(UnitHealthMax, unit)
	local strength = (type(amount) == "number" and m and m > 0) and amount / m * 4 or 0.5
	if action == "WOUND" then flash(f, 1, 0.2, 0.2, strength)
	elseif action == "HEAL" then flash(f, 0.3, 1, 0.45, strength) end
	-- anything but a heal or a resource gain means someone attacked it (misses too)
	if action ~= "HEAL" and action ~= "ENERGIZE" and (f == player or f.index) then U.Attacked(f) end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	if pendingApply then pendingApply = false; F.Apply() end
	if pendingBlizzard then pendingBlizzard = false; applyBlizzard() end
end)

ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key:sub(1, 7) == "frames." or key:sub(1, 4) == "hud." or key == "enabled" then F.Apply() end
end)
ns.On("SR_CONSOLE", function() F.Apply() end)
