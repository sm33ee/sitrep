-- SITREP · Blizzard's issue reporter (test clients) as a small glass button
-- The client's own reporter is a box of its own in the top left (PTR_IssueReporter,
-- unnamed in UIParent, mouseprobe 4.12.0): a title, an info button and its "Bug"
-- button under it. SITREP makes the box see-through and click-through and puts a
-- movable glass button in its place; a click is a click on "Bug". Nothing of it is
-- protected: all this in combat too. Windows the reporter opens later are seen all
-- the same (their own alpha). ui.reporter; off: the box given back as it was.

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read

local R = {}
ns.Reporter = R

local function P() return ns.P and ns.P.ui end
local function original() return rawget(_G, "PTR_IssueReporter") end
local function bugButton() return rawget(_G, "Bug") end

-- The reporter's parts SITREP hides: the box as a whole (its alpha, held at 0 when
-- Blizzard's own updates set it again: 4.12.0 showed the box still there with only
-- its parts see-through), its own textures and texts, and its frames known at that
-- moment (border, body, info button, the bug button), all click-through.
local parts -- { [region or frame] = its alpha before }
local rootAlpha
local function collect(o)
	parts = {}
	rootAlpha = read(o.GetAlpha, o) or 1
	local okR, regions = pcall(function() return { o:GetRegions() } end)
	for _, r in ipairs(okR and regions or {}) do parts[r] = read(r.GetAlpha, r) or 1 end
	for _, k in ipairs({ o.Border, o.Body, o.InfoButton, bugButton() }) do
		if type(k) == "table" then parts[k] = read(k.GetAlpha, k) or 1 end
	end
end

local holding -- (inside our own SetAlpha: the hook leaves it alone)
local function conceal(on)
	local o = original()
	if not o then return end
	if on and not parts then collect(o) end
	if not parts then return end
	for f, a in pairs(parts) do
		pcall(f.SetAlpha, f, on and 0 or a)
		if f.EnableMouse then pcall(f.EnableMouse, f, not on) end
	end
	holding = true
	pcall(o.SetAlpha, o, on and 0 or rootAlpha or 1)
	holding = false
	pcall(o.EnableMouse, o, not on)
	R.concealed = on
	if not on then parts = nil end
	if on and not o.srReporterHook then
		o.srReporterHook = true
		-- (Blizzard shows it again or sets its alpha: see-through again)
		if o.HookScript then pcall(o.HookScript, o, "OnShow", function() if R.concealed then conceal(true) end end) end
		if hooksecurefunc then
			pcall(hooksecurefunc, o, "SetAlpha", function(self)
				if R.concealed and not holding then holding = true; pcall(self.SetAlpha, self, 0); holding = false end
			end)
		end
	end
end

-- A window the reporter opens inside its box (made after SITREP hid the box): seen
-- all the same, whatever the box's alpha.
local function freeNew()
	local o = original()
	if not (o and parts) then return end
	local okK, kids = pcall(function() return { o:GetChildren() } end)
	for _, k in ipairs(okK and kids or {}) do
		if not parts[k] and k.SetIgnoreParentAlpha then pcall(k.SetIgnoreParentAlpha, k, true) end
	end
end
R.FreeNew = freeNew

local function build()
	if R.button then return R.button end
	local b = CreateFrame("Button", "SITREP_ReporterButton", UIParent)
	b:SetSize(74, 22)
	b:SetFrameStrata("MEDIUM")
	b.bg = K.Backdrop(b, C.bg, 8, { mood = true })
	b.bg:SetAllPoints()
	K.Border(b, C.line)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(12, 12)
	b.icon:SetPoint("LEFT", 7, 0)
	b.icon:SetTexture(K.MEDIA .. "glyph_bang")
	b.icon:SetVertexColor(1, 0.83, 0.37, 1)
	b.text = K.Font(b, 11, C.text, K.FONT, "")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	b.text:SetText("REPORT")
	b.unlock = K.Tex(b, "OVERLAY", { 1, 1, 1, 0.04 })
	b.unlock:SetAllPoints()
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function()
		local bug = bugButton()
		if bug and bug.Click then pcall(bug.Click, bug) end
		freeNew()
		if C_Timer and C_Timer.After then C_Timer.After(0.2, freeNew) end
	end)
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Report a bug", 1, 1, 1)
		GameTooltip:AddLine("Blizzard's issue reporter of this test client. Move it like the HUD (unlock in Layout).", 0.75, 0.8, 0.78, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	K.Movable(b, "reporter", { "TOPLEFT", "TOPLEFT", 40, -40 })
	b:Hide()
	R.button = b
	return b
end

-- On when the client has a reporter and SITREP's button is wanted; else Blizzard's.
function R.Apply()
	local o = original()
	local on = o ~= nil and P() and P().reporter ~= false and ns.P.enabled and not ns.hudHidden or false
	if not o and not R.button then return end
	local b = build()
	if on then
		b:RestorePosition()
		b:SetScale(ns.P.hud.scale * (ns.P.hud.frameScale.reporter or 1))
		b:SetAlpha(K.Opacity("reporter"))
		K.Background(b.bg, "reporter")
		b.unlock:SetShown(not ns.P.hud.locked)
	end
	b:SetShown(on)
	if on then conceal(true) elseif R.concealed then conceal(false) end
end

-- Blizzard puts its box back when a report is done (4.12.0, mouseprobe: the box
-- taking the mouse again, its rim seen): kept hidden, looked at twice a second.
-- (The report window is none of these parts: it stays as Blizzard shows it.)
function R.Keep()
	local o = original()
	if not (R.concealed and o and parts) then return end
	for f in pairs(parts) do
		if (read(f.GetAlpha, f) or 0) > 0 then pcall(f.SetAlpha, f, 0) end
		if f.IsIgnoringParentAlpha and read(f.IsIgnoringParentAlpha, f) == true then pcall(f.SetIgnoreParentAlpha, f, false) end
		if f.IsMouseEnabled and read(f.IsMouseEnabled, f) == true then pcall(f.EnableMouse, f, false) end
	end
	if (read(o.GetAlpha, o) or 0) > 0 then holding = true; pcall(o.SetAlpha, o, 0); holding = false end
	if o.IsMouseEnabled and read(o.IsMouseEnabled, o) == true then pcall(o.EnableMouse, o, false) end
end
local acc = 0
ns.On("SR_TICK", function(_, dt)
	if not R.concealed then return end
	acc = acc + (dt or 0)
	if acc < 0.5 then return end
	acc = 0
	R.Keep()
end)

ns.On("SR_LOGIN", function() R.Apply() end)
-- (the reporter may load after SITREP)
ns.On("ADDON_LOADED", function() if not R.concealed and original() then R.Apply() end end)
ns.On("PLAYER_ENTERING_WORLD", function() R.Apply() end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 3) == "ui." or key:sub(1, 4) == "hud." then R.Apply() end
end)
