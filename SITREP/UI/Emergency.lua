-- SITREP · Emergency items: a healthstone and a healing potion at hand
-- In combat two buttons: the best healthstone and the best healing potion in your
-- bags (Data.EMERGENCY). Dim while you are fine; when your health falls under
-- frames.emergencyPct and the item is ready, it lights up and pulses: one click
-- uses it. Using an item is protected: the buttons are secure (type "item"), their
-- item is chosen out of combat only (after the fight again, bags change), and the
-- game shows them in combat by itself (a visibility driver: an addon may not show
-- or hide them then). In combat only their alpha and their own textures change.
-- Placed like any element while the HUD is unlocked (Layout: "Emergency items").

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read

local EM = {}
ns.Emergency = EM
EM.buttons = {}
local SIZE, GAP = 36, 6
local DIM = 0.35
local KINDS = { "healthstone", "potion" }
local DRIVER = "[combat] show; hide"

local function P() return ns.P.frames end

local function clickEdge()
	return GetCVar and GetCVar("ActionButtonUseKeyDown") == "1" and "AnyDown" or "AnyUp"
end

-- The items in your bags: { [itemID] = true }.
function EM.InBags()
	local have = {}
	local CC = C_Container
	local slotsOf = (CC and CC.GetContainerNumSlots) or _G.GetContainerNumSlots
	local idOf = (CC and CC.GetContainerItemID) or _G.GetContainerItemID
	if not (slotsOf and idOf) then return have end
	for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
		for slot = 1, read(slotsOf, bag) or 0 do
			local id = read(idOf, bag, slot)
			if id then have[id] = true end
		end
	end
	return have
end

-- The strongest item of a kind you carry and can use (nil: none).
function EM.Best(kind, have)
	local usable = (C_Item and C_Item.IsUsableItem) or _G.IsUsableItem
	for _, id in ipairs(ns.Data.EMERGENCY[kind]) do
		if have[id] and (not usable or read(usable, id) ~= false) then return id end
	end
	return nil
end

local function count(id)
	local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	return fn and read(fn, id) or 0
end

local function cooldown(id)
	local fn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
	if not fn then return nil end
	local start, dur = read(fn, id)
	return start, dur
end

local function build()
	if EM.holder then return end
	local h = CreateFrame("Frame", "SITREP_Emergency", UIParent)
	h:SetSize(SIZE * 2 + GAP, SIZE)
	h:SetFrameStrata("MEDIUM")
	h.bg = K.Backdrop(h, C.bg, 12)
	h.bg:ClearAllPoints()
	h.bg:SetPoint("TOPLEFT", -4, 4)
	h.bg:SetPoint("BOTTOMRIGHT", 4, -4)
	h.unlock = K.Tex(h, "OVERLAY", { 1, 1, 1, 0.06 })
	h.unlock:SetAllPoints()
	for i, kind in ipairs(KINDS) do
		local b = CreateFrame("Button", "SITREP_Emergency" .. i, h, "SecureActionButtonTemplate")
		b:SetSize(SIZE, SIZE)
		b:SetPoint("LEFT", h, "LEFT", (i - 1) * (SIZE + GAP), 0)
		b:RegisterForClicks(clickEdge())
		b:SetAttribute("type", "item")
		b.kind = kind
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		K.Border(b, C.line2)
		b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints(b.icon)
		b.count = K.Font(b, 11, C.text, K.FONT, "OUTLINE")
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		-- lit: a pulsing border round it (a frame of its own, not the secure button's alpha)
		b.glow = CreateFrame("Frame", nil, b)
		b.glow:SetPoint("TOPLEFT", -3, 3)
		b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
		K.Border(b.glow, { 0.35, 1, 0.45, 1 }, 2)
		b.glow:Hide()
		local ag = b.glow.CreateAnimationGroup and b.glow:CreateAnimationGroup()
		if ag then
			local a = ag:CreateAnimation("Alpha")
			if a.SetFromAlpha then a:SetFromAlpha(1); a:SetToAlpha(0.25) end
			if a.SetDuration then a:SetDuration(0.45) end
			if ag.SetLooping then ag:SetLooping("BOUNCE") end
			b.pulse = ag
		end
		b:HookScript("OnEnter", function(self)
			if not (GameTooltip and self.itemID) then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
			GameTooltip:Show()
		end)
		b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		EM.buttons[i] = b
	end
	K.Movable(h, "emergency", { "CENTER", "CENTER", -260, -140 })
	EM.holder = h
end

-- Choose the items (out of combat), place, size and show the holder.
function EM.Apply()
	if InCombatLockdown() then EM.pending = true return end
	build()
	local h = EM.holder
	local H = ns.P.hud
	local on = P().emergency and ns.P.enabled and not ns.hudHidden
	local have = EM.InBags()
	local any = false
	for _, b in ipairs(EM.buttons) do
		local id = on and EM.Best(b.kind, have) or nil
		b.itemID = id
		b:SetAttribute("item", id and ("item:" .. id) or nil)
		local icon = id and C_Item and C_Item.GetItemIconByID and read(C_Item.GetItemIconByID, id)
		b.icon:SetTexture(icon or "Interface\\Icons\\INV_Potion_54")
		b.icon:SetDesaturated(not id)
		b:SetShown(id ~= nil or not H.locked)
		any = any or id ~= nil
	end
	h:SetScale(H.scale * (H.frameScale.emergency or 1))
	h:SetAlpha(K.Opacity("emergency"))
	K.Background(h.bg, "emergency")
	h:RestorePosition()
	h.unlock:SetShown(not H.locked)
	h:EnableMouse(not H.locked)
	-- placing it (HUD unlocked): on screen now; else the game shows it in combat
	if UnregisterStateDriver then UnregisterStateDriver(h, "visibility") end
	if on and not H.locked then
		h:Show()
	elseif on and any and RegisterStateDriver then
		RegisterStateDriver(h, "visibility", DRIVER)
	else
		h:Hide()
	end
	EM.Update()
end

-- Light up what you need now (in combat too: alpha and textures only).
function EM.Update()
	if not EM.holder then return end
	local frac = ns.Pressure and ns.Pressure.HealthFrac() or 1
	local low = frac <= (P().emergencyPct or 35) / 100
	local now = GetTime()
	for _, b in ipairs(EM.buttons) do
		local id = b.itemID
		local n = id and count(id) or 0
		local start, dur = nil, nil
		if id then start, dur = cooldown(id) end
		local cooling = start and dur and dur > 1.5 and start + dur > now
		if cooling then pcall(b.cd.SetCooldown, b.cd, start, dur) else pcall(b.cd.Clear, b.cd) end
		b.count:SetText(n > 1 and tostring(n) or "")
		b.icon:SetDesaturated(n == 0)
		local hot = id ~= nil and n > 0 and not cooling and low
		b:SetAlpha(hot and 1 or DIM)
		if hot ~= b.hot then
			b.hot = hot
			b.glow:SetShown(hot)
			if b.pulse then if hot then b.pulse:Play() else b.pulse:Stop() end end
		end
	end
end

ns.On("SR_LOGIN", function() EM.Apply() end)
ns.On("SR_TICK", function() EM.Update() end)
ns.On("UNIT_HEALTH", function(_, unit) if unit == "player" then EM.Update() end end)
ns.On("BAG_UPDATE_DELAYED", function() if InCombatLockdown() then EM.pending = true else EM.Apply() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if EM.pending then EM.pending = false; EM.Apply() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 4) == "hud." or key:sub(1, 7) == "frames." then EM.Apply() end
end)
