-- SITREP · Quest items in the quest tracker
-- A quest that comes with an item to use (GetQuestLogSpecialItemInfo) gets its
-- icon left of its row in the tracker: click to use it, its cooldown on it, its
-- tooltip on hover. Using an item is a protected action: the icons are secure
-- buttons (type "item"), and the game lets no addon move, show, hide or re-aim them
-- in combat. So they are set out of combat only, placed on the screen where their
-- rows are (not anchored to the rows: the tracker must stay free to change), and
-- while one shows, the tracker keeps its layout through combat (texts still
-- update: QuestTracker.CombatTexts); after combat it is sorted again.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read

local QI = {}
ns.QuestItems = QI
QI.buttons = {}
local SIZE, GAP = 22, 4

local function clickEdge()
	return GetCVar and GetCVar("ActionButtonUseKeyDown") == "1" and "AnyDown" or "AnyUp"
end

local function button(i)
	local b = QI.buttons[i]
	if b then return b end
	b = CreateFrame("Button", "SITREP_QuestItem" .. i, UIParent, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:RegisterForClicks(clickEdge())
	b:SetAttribute("type", "item")
	b.bg = K.Backdrop(b, C.bg, 8, { shadow = false })
	b.bg:SetAllPoints()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	K.Border(b, C.line2)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints(b.icon)
	b.count = K.Font(b, 10, C.text, K.FONT, "OUTLINE")
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	b:HookScript("OnEnter", function(self)
		if not (GameTooltip and self.link) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	b:Hide()
	QI.buttons[i] = b
	return b
end

-- The item a quest comes with: link, icon, charges (nil: none).
function QI.ItemOf(q)
	if not (GetQuestLogSpecialItemInfo and q.index) then return nil end
	local link, icon, charges = read(GetQuestLogSpecialItemInfo, q.index)
	if type(link) ~= "string" then return nil end
	return link, icon, charges
end

-- Is any icon showing (the tracker then keeps its layout in combat)?
function QI.Active()
	for _, b in ipairs(QI.buttons) do if b:IsShown() then return true end end
	return false
end

-- Put the icons by the tracker's rows (out of combat only).
function QI.Place(rows, frame)
	if InCombatLockdown() then return end
	local n = 0
	local ui = read(UIParent.GetEffectiveScale, UIParent) or 1
	if frame and frame:IsShown() then
		for _, r in ipairs(rows) do
			local q = r:IsShown() and r.quest
			local link, icon, charges
			if q then link, icon, charges = QI.ItemOf(q) end
			if link then
				n = n + 1
				local b = button(n)
				local id = link:match("item:(%d+)")
				b:SetAttribute("item", id and ("item:" .. id) or link)
				b.link = link
				b.icon:SetTexture(icon)
				b.count:SetText(type(charges) == "number" and charges > 1 and tostring(charges) or "")
				-- as large as the tracker is (the same effective scale as the row: then
				-- the row's own coordinates are the button's), left of the row's top
				local eff = read(r.GetEffectiveScale, r) or ui
				b:SetScale(eff / ui)
				local x, y = read(r.GetLeft, r), read(r.GetTop, r)
				b:ClearAllPoints()
				if x and y then b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x - GAP - 6, y) end
				b.questIndex = q.index
				local cs, cdur = read(GetQuestLogSpecialItemCooldown, q.index)
				if cs and cdur and cdur > 0 then pcall(b.cd.SetCooldown, b.cd, cs, cdur) else pcall(b.cd.Clear, b.cd) end
				b:Show()
			end
		end
	end
	for i = n + 1, #QI.buttons do
		local b = QI.buttons[i]
		b:Hide()
		b:SetAttribute("item", nil)
		b.link, b.questIndex = nil, nil
	end
end

-- cooldowns tick on (also in combat: the cooldown widget is not protected)
ns.On("BAG_UPDATE_COOLDOWN", function()
	for _, b in ipairs(QI.buttons) do
		if b:IsShown() and b.questIndex then
			local cs, cdur = read(GetQuestLogSpecialItemCooldown, b.questIndex)
			if cs and cdur and cdur > 0 then pcall(b.cd.SetCooldown, b.cd, cs, cdur) end
		end
	end
end)
