-- SITREP · Bags
-- One movable button instead of Blizzard's bag bar: a bag icon and how many
-- slots are free (orange under 10, red under 5). Click opens all bags (a secure
-- click on Blizzard's backpack button, so the bags carry no taint of SITREP's);
-- right-click shows Blizzard's bag bar again for a moment, to swap bags (it
-- hides again on the next right-click). With the button off, the bag bar is
-- Blizzard's as before.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format

local B = {}
ns.Bags = B

-- Blizzard's bag bar: one frame on the modern client, single buttons on older ones
local BAR = { "BagsBar" }
local BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "BagBarExpandToggle" }
B.NAMES = { bar = BAR, buttons = BUTTONS }
local ICON = "Interface\\Buttons\\Button-Backpack-Up"

local function P() return ns.P and ns.P.ui end

-- Free and total slots in your bags (backpack and the bag slots).
function B.Free()
	local CC = C_Container
	local getFree = (CC and CC.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
	local getSlots = (CC and CC.GetContainerNumSlots) or _G.GetContainerNumSlots
	if not (getFree and getSlots) then return nil end
	local free, total = 0, 0
	for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
		free = free + (read(getFree, bag) or 0)
		total = total + (read(getSlots, bag) or 0)
	end
	return free, total
end

local function bagParts()
	local list = {}
	for _, n in ipairs(BAR) do if type(_G[n]) == "table" then list[#list + 1] = _G[n] end end
	if #list == 0 then
		for _, n in ipairs(BUTTONS) do if type(_G[n]) == "table" then list[#list + 1] = _G[n] end end
	end
	return list
end
B.Parts = bagParts

-- Blizzard's bag bar shown or hidden.
local function showBlizzard(show)
	-- faded, not hidden: hiding Blizzard's bag bar from here would taint it (K.Fade)
	for _, f in ipairs(bagParts()) do K.Fade(f, not show) end
end

local function build()
	if B.button then return end
	-- A click opens the bags through Blizzard's own backpack button (a secure click):
	-- bags opened by an addon's code carry its taint, and in combat the game then
	-- refuses their protected actions (drinking a potion from them: blocked).
	local backpack = _G.MainMenuBarBackpackButton
	local b = CreateFrame("Button", "SITREP_BagButton", UIParent, backpack and "SecureActionButtonTemplate" or nil)
	b:SetSize(112, 22)
	b:SetFrameStrata("MEDIUM")
	b.bg = K.Backdrop(b, C.bg, 8, { mood = true })
	b.bg:SetAllPoints()
	K.Border(b, C.line)
	K.Brackets(b, 6, 2)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 4, 0)
	b.icon:SetTexture(ICON)
	b.text = K.Font(b, 11, C.text, K.FONT, "")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	b.unlock = K.Tex(b, "OVERLAY", { 1, 1, 1, 0.04 })
	b.unlock:SetAllPoints()
	-- secure clicks fire on key down or up as the game's setting says (once)
	local edge = GetCVar and GetCVar("ActionButtonUseKeyDown") == "1" and "Down" or "Up"
	b:RegisterForClicks("LeftButton" .. edge, "RightButton" .. edge)
	local function rightClick()
		B.barShown = not B.barShown
		showBlizzard(B.barShown or not (P().hideBagBar))
	end
	if backpack then
		b:SetAttribute("type1", "click")
		b:SetAttribute("clickbutton1", backpack)
		b:HookScript("OnClick", function(_, button) if button == "RightButton" then rightClick() end end)
	else
		b:SetScript("OnClick", function(_, button)
			if button == "RightButton" then rightClick()
			elseif ToggleAllBags then pcall(ToggleAllBags) end
		end)
	end
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		local free, total = B.Free()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(free and format("Bags: %d of %d slots free", free, total) or "Bags", 1, 1, 1)
		GameTooltip:AddLine("Click: open your bags", 0.75, 0.8, 0.78)
		GameTooltip:AddLine("Right-click: show the bag bar (swap bags)", 0.75, 0.8, 0.78)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	K.Movable(b, "bags", { "BOTTOMRIGHT", "BOTTOMRIGHT", -250, 8 })
	B.button = b
end

function B.Refresh()
	local b = B.button
	if not (b and b:IsShown()) then return end
	local free, total = B.Free()
	if not free then b.text:SetText("BAGS") return end
	local hex = free < 5 and "ff5555" or free < 10 and "ffa040" or "e0e8e5"
	b.text:SetText(format("FREE |cff%s%d|r/%d", hex, free, total))
end

function B.Apply()
	if InCombatLockdown() then B.pending = true return end
	build()
	local on = P().bags and ns.P.enabled and not ns.hudHidden
	local b = B.button
	b:SetShown(on)
	b:RestorePosition()
	b:SetScale(ns.P.hud.scale * (ns.P.hud.frameScale.bags or 1))
	b:SetAlpha(K.Opacity("bags"))
	K.Background(b.bg, "bags")
	b.unlock:SetShown(not ns.P.hud.locked)
	b:EnableMouse(true)
	B.barShown = false
	showBlizzard(not (on and P().hideBagBar))
	B.Refresh()
end

ns.On("SR_LOGIN", function() B.Apply() end)
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_ENTERING_WORLD" }) do ns.On(e, function() B.Refresh() end) end
ns.On("PLAYER_REGEN_ENABLED", function()
	if B.pending then B.pending = false; B.Apply() return end
	-- (the bag bar's mouse comes back after combat: K.Fade)
end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 3) == "ui." or key:sub(1, 4) == "hud." then B.Apply() end
end)
