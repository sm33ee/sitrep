-- SITREP · Chat
-- Blizzard's chat windows stay the engine (messages, filters, channels, tab
-- settings, links); everything you see is SITREP's (ui.chat):
--   look      each window on a light glass pane (Layout: chat background), the
--             game's chat font in ui.chatSize with an outline (every alphabet
--             still shows), no fading; tabs as flat plates with an accent line
--             under the selected one; the input line as a glass field with an
--             accent ring while you type
--   buttons   Blizzard's chat buttons (channels, voice, menu) moved into a small
--             glass bar at the right end of the tab row, with SITREP's icons, and
--             the fold button; the rest of Blizzard's button column is gone
--   presence  tabs, input line and button bar show while the mouse is over the
--             chat or you type, and fade out slowly after (unread tabs stay)
--   unread    a window that got whispers, group, raid, guild, officer, say or
--             yell messages you have not seen (not your own, not public
--             channels) keeps its tab in sight, with how many
--   fold      (ui.chatCollapsed) the messages out of sight and out of the mouse's
--             way; the last 3 lines the selected tab showed (all it shows) stay,
--             each on a small glass pill, links in them clickable, a click beside
--             a link opens that tab. Each line fades ui.chatFade seconds after it
--             came (all back while the mouse is on the chat or you type). It folds towards where the chat is
--             (ui.chatFoldTo: auto / up / down): down, the lines at its bottom and
--             the tabs right over them; up, the tabs where they are and the lines
--             under them. Pressing Enter unfolds it while you type; it folds back
--             after. The fold button, a key binding and /sitrep chat fold it.
--   move      while the HUD is unlocked a handle covers the main window
-- Everything goes back as it was when switched off (a /reload restores every detail).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format = string.format

local CH = {}
ns.Chat = CH
ns.ChatFold = CH -- (the old name)

local orig = {}     -- [chat frame] = its font and fading before
local unread = {}   -- [chat frame] = new messages not seen yet
local lines = setmetatable({}, { __mode = "k" }) -- [chat frame] = its last lines shown, oldest first
CH.lines, CH.unread = lines, unread
local PREVIEW_LINES, LINE_H = 3, 18
CH.LINE_H = LINE_H
local FADE_IN, HOLD, FADE_OUT = 0.15, 1.5, 1.5 -- presence: seconds
CH.HOLD, CH.FADE_OUT = HOLD, FADE_OUT
local HOVER_BRIGHT = 0.12 -- the pane a little denser while the mouse is on it
local LINE_FADE = 2 -- seconds a folded preview line takes to fade out

-- the window's background and border textures (the client lists them; this is
-- the list for clients that do not)
local TEXTURES = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture", "ButtonFrameBackground", "ButtonFrameTopLeftTexture",
	"ButtonFrameBottomLeftTexture", "ButtonFrameTopRightTexture", "ButtonFrameBottomRightTexture", "ButtonFrameLeftTexture",
	"ButtonFrameRightTexture", "ButtonFrameBottomTexture", "ButtonFrameTopTexture" }
-- Blizzard's buttons that move into SITREP's bar (in this order), with their icon
local BAR = { { "ChatFrameChannelButton", "hash", "Channels" }, { "ChatFrameToggleVoiceMuteButton", "mic", "Microphone" },
	{ "ChatFrameToggleVoiceDeafenButton", "speaker", "Voice chat sound" }, { "ChatFrameMenuButton", "menu", "Chat menu" } }
-- and the ones that just go
local GONE = { "QuickJoinToastButton" }
local SHARED = {}
for _, b in ipairs(BAR) do SHARED[#SHARED + 1] = b[1] end
for _, n in ipairs(GONE) do SHARED[#SHARED + 1] = n end
CH.NAMES = { textures = TEXTURES, shared = SHARED, bar = BAR }

-- chat events that count as new, and the chat group each belongs to
local EVENTS = { "WHISPER", "BN_WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
	"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "SAY", "YELL" }
CH.EVENTS = EVENTS
-- Blizzard's tab alphas: all 1 while SITREP's presence fades the tabs
local TAB_ALPHAS = { "CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA", "CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA",
	"CHAT_FRAME_TAB_ALERTING_MOUSEOVER_ALPHA", "CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA",
	"CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA", "CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA" }

local function P() return ns.P and ns.P.ui end
local function isOn() return P() and P().chat and ns.P.enabled and true or false end
CH.IsOn = isOn

local wins -- the windows, with their input lines (made again by CH.Apply)
local function frames()
	local list = {}
	for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if type(cf) == "table" then
			local eb = _G["ChatFrame" .. i .. "EditBox"]
			list[#list + 1] = { i = i, cf = cf, eb = type(eb) == "table" and eb or nil }
		end
	end
	wins = list
	return list
end
CH.Frames = frames
local function cached() return wins or frames() end

local function part(i, suffix) local v = _G["ChatFrame" .. i .. suffix] return type(v) == "table" and v or nil end
local function dock() local d = _G.GeneralDockManager return type(d) == "table" and d.SetPoint and d or nil end

local function textures()
	local list = type(_G.CHAT_FRAME_TEXTURES) == "table" and _G.CHAT_FRAME_TEXTURES or {}
	local seen, out = {}, {}
	for _, l in ipairs({ list, TEXTURES }) do
		for _, sfx in ipairs(l) do if not seen[sfx] then seen[sfx] = true; out[#out + 1] = sfx end end
	end
	return out
end

-- The window whose tab is selected (its lines are the preview's).
local function selected()
	local cf = _G.SELECTED_CHAT_FRAME
	if type(cf) ~= "table" then cf = _G.ChatFrame1 end
	return cf
end
CH.Selected = selected
-- Is this window's tab the selected one (in the dock, or a window of its own)?
local function isSelected(cf)
	if rawget(cf, "isDocked") == false then return true end
	local d = _G.GENERAL_CHAT_DOCK
	if d and type(_G.FCFDock_GetSelectedWindow) == "function" then
		local ok, sel = pcall(_G.FCFDock_GetSelectedWindow, d)
		if ok and sel then return sel == cf end
	end
	return selected() == cf
end

-- Folded: the messages out of sight (not while you type: CH.peek).
function CH.Folded() return isOn() and P().chatCollapsed and not CH.peek or false end
CH.Hidden = CH.Folded -- (the old name)

-- Which way it folds: down (to its bottom) or up (to its top).
function CH.FoldsDown()
	local mode = P().chatFoldTo or "auto"
	if mode == "down" then return true end
	if mode == "up" then return false end
	local cf = _G.ChatFrame1
	local top, bottom = read(cf.GetTop, cf), read(cf.GetBottom, cf)
	local h = read(UIParent.GetHeight, UIParent)
	return top ~= nil and bottom ~= nil and h ~= nil and (top + bottom) / 2 < h / 2
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local function remember(cf)
	if orig[cf] then return orig[cf] end
	local okF, font, size, flags = pcall(cf.GetFont, cf)
	local o = { font = okF and font or nil, size = okF and size or nil, flags = okF and flags or nil,
		fadeTime = read(cf.GetTimeVisible, cf), fading = read(cf.GetFading, cf) }
	orig[cf] = o
	return o
end

-- Text size with an outline (also after Blizzard sets its own size).
local function applyFont(cf)
	local o = orig[cf]
	if not (o and o.font and o.size) then return end
	if isOn() then pcall(cf.SetFont, cf, o.font, P().chatSize, "OUTLINE")
	else pcall(cf.SetFont, cf, o.font, o.size, o.flags) end
end

---------------------------------------------------------------------------
-- The pane behind each window, the input line, the tabs
---------------------------------------------------------------------------
local function paneAlpha(p)
	local base = ns.P.hud.bgAlpha.chat or 0.45
	return math.min(1, base + (base > 0 and HOVER_BRIGHT * (p or 0) or 0))
end
CH.PaneAlpha = paneAlpha

local function pane(cf, on)
	if on and not cf.srShell then
		cf.srShell = K.Backdrop(cf, C.bg, 12, { shadow = false, sub = -7 })
		local r = K.Region(cf.srShell)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", cf, "TOPLEFT", -8, 6)
		r:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 8, -6)
	end
	local s = cf.srShell
	if not s then return end
	K.Background(s, nil, paneAlpha(CH.presence))
	local show = on and (ns.P.hud.bgAlpha.chat or 0.45) > 0
	if s.SetShown then s:SetShown(show) end
	if K.Region(s) ~= s then K.Region(s):SetShown(show) end
end

-- The input line: Blizzard's textures off, a glass field with an accent ring while
-- you type. Drawn on the edit box itself (its background layers), so the typed
-- text stays on top.
local function styleEditBox(i, on)
	local eb = part(i, "EditBox")
	if not eb then return end
	for _, s in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
		local t = part(i, "EditBox" .. s) or rawget(eb, s)
		if type(t) == "table" then pcall(t.SetAlpha, t, on and 0 or 1) end
	end
	if on and not eb.srSkin then
		local bg = K.Backdrop(eb, { 0.10, 0.12, 0.13, 0.78 }, 8, { shadow = false })
		local r = K.Region(bg)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", eb, "TOPLEFT", 2, -3)
		r:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -2, 3)
		local ring = CreateFrame("Frame", nil, eb)
		ring:SetPoint("TOPLEFT", r, "TOPLEFT")
		ring:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT")
		local ar, ag, ab = K.Accent()
		K.Border(ring, { ar, ag, ab, 0.45 }, 1, 8)
		ring:Hide()
		local skin = { bg = bg, ring = ring, shown = true }
		function skin.SetShown(_, v)
			skin.shown = v and true or false
			if bg.SetShown then bg:SetShown(v) end
			if r ~= bg then r:SetShown(v) end
			if not v then ring:Hide() end
		end
		function skin.IsShown() return skin.shown end
		eb.srSkin = skin
		-- typing: the ring; and a folded chat unfolds while you type (CH.peek)
		if eb.HookScript then
			eb:HookScript("OnEditFocusGained", function(self)
				if self.srSkin and self.srSkin.shown then self.srSkin.ring:Show() end
				CH.Typing(true)
			end)
			eb:HookScript("OnEditFocusLost", function(self)
				if self.srSkin then self.srSkin.ring:Hide() end
				CH.Typing(false)
			end)
		end
	end
	if eb.srSkin then eb.srSkin:SetShown(on) end
end

-- A tab in SITREP's look: Blizzard's art off, a flat plate around the name, an
-- accent line under the selected tab, Blizzard's new-message glow turned into an
-- accent bar over the plate, and SITREP's count of unread messages beside it.
local function styleTab(i, cf, on)
	local tab = part(i, "Tab")
	if not tab then return end
	local text = part(i, "TabText") or rawget(tab, "Text") or (tab.GetFontString and read(tab.GetFontString, tab))
	local glow = part(i, "TabGlow") or rawget(tab, "glow")
	if not tab.srArt then
		tab.srArt = {}
		local ok, regions = pcall(function() return { tab:GetRegions() } end)
		for _, r in ipairs(ok and regions or {}) do
			if r ~= glow and read(r.GetObjectType, r) == "Texture" then tab.srArt[#tab.srArt + 1] = r end
		end
		if type(text) == "table" then
			local plate = K.Tex(tab, "BACKGROUND", { C.bg[1], C.bg[2], C.bg[3], 0.8 }, -8)
			plate:SetPoint("TOPLEFT", text, "TOPLEFT", -8, 4)
			plate:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 8, -4)
			local line = K.Tex(tab, "BORDER", nil, 1)
			line:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT")
			line:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT")
			line:SetHeight(2)
			K.Paint(function(r, g, b) line:SetVertexColor(r, g, b, 1) end)
			tab.srPlate, tab.srLine = plate, line
			-- unread: how many, in the accent colour
			local badge = K.Font(tab, 10, C.text, K.FONT, "OUTLINE")
			badge:SetPoint("LEFT", plate, "RIGHT", 3, 0)
			K.Paint(function(r, g, b) badge:SetTextColor(r, g, b) end)
			badge:Hide()
			tab.srBadge = badge
		end
		if type(glow) == "table" then
			tab.srGlow = { glow = glow, tex = read(glow.GetTexture, glow), points = {} }
			for n = 1, (read(glow.GetNumPoints, glow) or 0) do tab.srGlow.points[n] = { glow:GetPoint(n) } end
		end
	end
	for _, r in ipairs(tab.srArt) do pcall(r.SetAlpha, r, on and 0 or 1) end
	if tab.srPlate then
		tab.srPlate:SetShown(on)
		tab.srLine:SetShown(on and isSelected(cf))
	end
	local g = tab.srGlow
	if g and on and not g.styled and tab.srPlate then
		g.styled = true
		g.glow:SetTexture(K.WHITE)
		g.glow:ClearAllPoints()
		g.glow:SetPoint("TOPLEFT", tab.srPlate, "TOPLEFT")
		g.glow:SetPoint("TOPRIGHT", tab.srPlate, "TOPRIGHT")
		g.glow:SetHeight(2)
		local r, gg, b = K.Accent()
		g.glow:SetVertexColor(r, gg, b, 1)
	elseif g and not on and g.styled then
		g.styled = false
		if g.tex then g.glow:SetTexture(g.tex) end
		g.glow:SetVertexColor(1, 1, 1, 1)
		g.glow:ClearAllPoints()
		for _, pt in ipairs(g.points) do pcall(g.glow.SetPoint, g.glow, unpack(pt)) end
	end
end

-- Blizzard's tab alphas: 1 while on (SITREP's presence fades the tab bar), back after.
local origAlphas
local function tabAlphas(on)
	if not origAlphas then
		origAlphas = {}
		for _, n in ipairs(TAB_ALPHAS) do origAlphas[n] = _G[n] end
	end
	for _, n in ipairs(TAB_ALPHAS) do
		if origAlphas[n] ~= nil then _G[n] = on and 1 or origAlphas[n] end
	end
	for _, w in ipairs(frames()) do
		local tab = part(w.i, "Tab")
		if tab then
			if tab.srNoMouse == nil then tab.srNoMouse = rawget(tab, "noMouseAlpha") or false end
			if tab.srNoMouse then tab.noMouseAlpha = on and 1 or tab.srNoMouse end
		end
	end
end

-- The selected line and the unread counts on the tabs. An unread tab ignores the
-- tab bar's fading: it stays in sight.
function CH.UpdateTabs()
	local on = isOn()
	for _, w in ipairs(frames()) do
		local tab = part(w.i, "Tab")
		if tab then
			if tab.srLine then tab.srLine:SetShown(on and isSelected(w.cf)) end
			local n = on and unread[w.cf] or 0
			if tab.srBadge then
				tab.srBadge:SetText(n > 0 and tostring(n) or "")
				tab.srBadge:SetShown(n > 0)
			end
			if tab.SetIgnoreParentAlpha then pcall(tab.SetIgnoreParentAlpha, tab, n > 0) end
			if n > 0 then pcall(tab.SetAlpha, tab, 1) end
		end
	end
end

---------------------------------------------------------------------------
-- The button bar: Blizzard's chat buttons in a glass bar at the tab row's end
---------------------------------------------------------------------------
local BTN_W, BTN_H, BTN_GAP = 24, 20, 2

local function hideArt(b)
	if b.srArtHidden then return end
	b.srArtHidden = true
	local function zero(self)
		if not self.srInBar then return end
		for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
			local t = self[getter] and read(self[getter], self)
			if type(t) == "table" then pcall(t.SetAlpha, t, 0) end
		end
		local ok, regions = pcall(function() return { self:GetRegions() } end)
		for _, r in ipairs(ok and regions or {}) do
			if r ~= self.srIcon and r ~= self.srHover and read(r.GetObjectType, r) == "Texture" then pcall(r.SetAlpha, r, 0) end
		end
	end
	b.srZero = zero
	-- Blizzard changes the art with the state (voice muted or not): off again
	for _, fn in ipairs({ "SetNormalTexture", "SetNormalAtlas", "SetPushedTexture", "SetPushedAtlas", "SetHighlightTexture",
		"SetHighlightAtlas" }) do
		if b[fn] then pcall(hooksecurefunc, b, fn, zero) end
	end
end

local function icon(b, kind)
	if not b.srIcon then
		b.srHover = K.Backdrop(b, { 1, 1, 1, 0.10 }, 4, { shadow = false })
		if b.srHover.SetShown then b.srHover:SetShown(false) end
		if K.Region(b.srHover) ~= b.srHover then K.Region(b.srHover):Hide() end
		b.srIcon = b:CreateTexture(nil, "OVERLAY")
		b.srIcon:SetSize(14, 14)
		b.srIcon:SetPoint("CENTER")
		b.srIcon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 1)
		if b.HookScript then
			b:HookScript("OnEnter", function(self) if self.srInBar then self.srIcon:SetVertexColor(C.text[1], C.text[2], C.text[3], 1) end end)
			b:HookScript("OnLeave", function(self) if self.srInBar then self.srIcon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 1) end end)
		end
	end
	b.srIcon:SetTexture(K.MEDIA .. "glyph_" .. kind)
	b.srIcon:Show()
end

-- Blizzard's button into the bar (its place, parent and size kept to give back).
local function take(b, kind)
	if not b.srOrig then
		local pts = {}
		for n = 1, (read(b.GetNumPoints, b) or 0) do pts[n] = { b:GetPoint(n) } end
		b.srOrig = { parent = b:GetParent(), points = pts, w = read(b.GetWidth, b), h = read(b.GetHeight, b) }
	end
	b.srInBar = true
	pcall(b.SetParent, b, CH.bar)
	pcall(b.SetSize, b, BTN_W, BTN_H)
	hideArt(b)
	icon(b, kind)
	b.srZero(b)
end
local function giveBack(b)
	local o = b.srOrig
	if not o then return end
	b.srInBar = false
	pcall(b.SetParent, b, o.parent)
	b:ClearAllPoints()
	for _, pt in ipairs(o.points) do pcall(b.SetPoint, b, unpack(pt)) end
	if o.w and o.h then pcall(b.SetSize, b, o.w, o.h) end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local t = b[getter] and read(b[getter], b)
		if type(t) == "table" then pcall(t.SetAlpha, t, 1) end
	end
	local ok, regions = pcall(function() return { b:GetRegions() } end)
	for _, r in ipairs(ok and regions or {}) do
		if r ~= b.srIcon and r ~= b.srHover and read(r.GetObjectType, r) == "Texture" then pcall(r.SetAlpha, r, 1) end
	end
	if b.srIcon then b.srIcon:Hide() end
	b.srOrig = nil
end

-- The buttons the bar shows (Blizzard hides the voice ones out of voice chat), right to left.
function CH.LayoutBar()
	local bar = CH.bar
	if not bar then return end
	local list = {}
	for _, d in ipairs(BAR) do
		local b = _G[d[1]]
		if type(b) == "table" and b.srInBar and read(b.IsShown, b) ~= false then list[#list + 1] = b end
	end
	list[#list + 1] = CH.foldBtn
	local x = 3
	for _, b in ipairs(list) do
		b:ClearAllPoints()
		b:SetPoint("LEFT", bar, "LEFT", x, 0)
		x = x + BTN_W + BTN_GAP
	end
	CH.barW = x - BTN_GAP + 3
	bar:SetSize(CH.barW, BTN_H + 6)
end

---------------------------------------------------------------------------
-- Presence: tabs, input line and button bar with the mouse or while you type
---------------------------------------------------------------------------
CH.presence = 1
-- (plain answers: called directly, the caller catches an error)
local function hovering()
	for _, w in ipairs(cached()) do
		local cf = w.cf
		-- (the window, the tab row over it, the input line under it)
		if cf:IsShown() and cf:IsMouseOver(40, -40, -12, 12) then return true end
	end
	local bar, pv = CH.bar, CH.preview
	return (bar and bar:IsShown() and bar:IsMouseOver()) or (pv and pv:IsShown() and pv:IsMouseOver()) or false
end
local function typing()
	for _, w in ipairs(cached()) do
		local eb = w.eb
		if eb and eb:HasFocus() then return true end
	end
	return false
end
local function seen()
	local ok, yes = pcall(function() return hovering() or typing() end)
	return ok and yes
end

-- The parts at presence p (0: out of sight, 1: all there). inputs: only the input
-- lines (set again while nothing changes: Blizzard sets them itself).
function CH.ShowParts(p, inputs)
	CH.presence = p
	local on = isOn()
	local a = on and p or 1
	if inputs then
		for _, w in ipairs(cached()) do
			local eb = w.eb
			if eb then pcall(eb.SetAlpha, eb, (on and read(eb.HasFocus, eb)) and 1 or a) end
		end
		return
	end
	local d = dock()
	if d then pcall(d.SetAlpha, d, a) end
	if CH.bar then CH.bar:SetAlpha(a) end
	for _, w in ipairs(cached()) do
		local eb = w.eb
		if eb then pcall(eb.SetAlpha, eb, (on and read(eb.HasFocus, eb)) and 1 or a) end
		-- a window of its own: its tab is not in the tab bar
		if rawget(w.cf, "isDocked") == false then
			local tab = part(w.i, "Tab")
			if tab then pcall(tab.SetAlpha, tab, (unread[w.cf] or 0) > 0 and 1 or a) end
		end
		if on and w.cf.srShell then K.Background(w.cf.srShell, nil, paneAlpha(p)) end
	end
end

-- Every frame while it changes; the mouse looked at 20 times a second, and the
-- parts set again then too (Blizzard sets the input line's alpha itself when you
-- start and stop typing).
local acc = 0
local function drive(_, e)
	if not isOn() then return end
	acc = acc + e
	local now = GetTime()
	local tick = acc >= 0.05
	if tick then
		acc = 0
		if seen() then CH.lastSeen = now end
		CH.FadeLines(now)
	end
	local want = (now - (CH.lastSeen or -100)) <= HOLD and 1 or 0
	local p = CH.presence
	if p == want then
		if tick then CH.ShowParts(p, true) end
		return
	end
	if want > p then p = math.min(1, p + e / FADE_IN) else p = math.max(0, p - e / FADE_OUT) end
	CH.ShowParts(p)
	CH.FadeLines(now) -- (the folded lines come and go with the parts)
end
CH.Drive = drive

---------------------------------------------------------------------------
-- Folding: the preview lines, and where tabs, input line and bar go
---------------------------------------------------------------------------
-- A line in the chat's own font as a family: names in other alphabets borrow the
-- client's fonts for them. A face set on the string itself (SetFont) wins over
-- any font object set later, so a line never gets one while a family can be had.
local function face(l, font, size)
	local fam = K.Family(font, size, "OUTLINE")
	if fam and not l.text.srOwnFace and pcall(l.text.SetFontObject, l.text, fam) then return end
	l.text:SetFont(font, size, "OUTLINE")
	l.text.srOwnFace = true
end

-- The preview: the selected window's last lines, oldest first (the newest nearest
-- the fold). A line is shown as the window got it (a secret value passed on).
-- How much of a preview line shows: 1 while it is new (or the parts are there),
-- fading over LINE_FADE seconds once it is ui.chatFade seconds old.
local function lineAlpha(m, now)
	local age = now - (m.at or now)
	local fade = P().chatFade or 20
	local a = age <= fade and 1 or math.max(0, 1 - (age - fade) / LINE_FADE)
	return math.max(a, CH.presence or 0)
end
CH.LineAlpha = lineAlpha

-- The lines still showing (oldest first; the newest are the last to fade).
local function live(list, now)
	local out = {}
	for _, m in ipairs(list) do if lineAlpha(m, now) > 0 then out[#out + 1] = m end end
	return out
end

local function preview(folded)
	local pv = CH.preview
	if not pv then return 0 end
	local cf = selected()
	local list = live(folded and P().chatPreview and lines[cf] or {}, GetTime())
	local n = math.min(#list, PREVIEW_LINES)
	local font = select(1, read(ChatFrame1.GetFont, ChatFrame1)) or K.FONT
	local size = P().chatSize
	local down = CH.FoldsDown()
	pv:ClearAllPoints()
	if down then
		pv:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMLEFT", 0, 2)
		pv:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", 0, 2)
	else
		pv:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", 0, -2)
		pv:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", 0, -2)
	end
	pv:SetHeight(math.max(1, n * LINE_H))
	for i = 1, PREVIEW_LINES do
		local l = pv.lines[i]
		local m = list[#list - n + i]
		l:SetShown(i <= n)
		l:ClearAllPoints()
		local y = down and (n - i) * LINE_H or -(i - 1) * LINE_H
		local anchor = down and "BOTTOM" or "TOP"
		l:SetPoint(anchor .. "LEFT", pv, anchor .. "LEFT", 0, y)
		l:SetPoint(anchor .. "RIGHT", pv, anchor .. "RIGHT", 0, y)
		if i <= n and m then
			face(l, font, size)
			l.text:SetText(m.text)
			l.text:SetTextColor(m.r or 1, m.g or 1, m.b or 1)
			l.cf = cf
			l.entry = m
			l:SetAlpha(lineAlpha(m, GetTime()))
			-- the pill as wide as the text (full width when the width is not readable)
			local w = read(l.text.GetStringWidth, l.text)
			local full = read(pv.GetWidth, pv)
			local r = K.Region(l.bg)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
			r:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, 0)
			r:SetWidth((w and full and w + 14 < full) and (w + 14) or (full or 300))
		end
	end
	pv:SetShown(n > 0)
	return n
end
CH.Preview = preview

-- Folded: each preview line's fade; a line gone (or back with the mouse) lays
-- the fold out again, so the tabs stay right over the lines that show.
function CH.FadeLines(now)
	if not (CH.Folded() and CH.preview and P().chatPreview) then return end
	local n = #live(lines[selected()] or {}, now)
	if math.min(n, PREVIEW_LINES) ~= (CH.lastLines or 0) then CH.Layout() return end
	for _, l in ipairs(CH.preview.lines) do
		if l.entry and l:IsShown() then l:SetAlpha(lineAlpha(l.entry, now)) end
	end
end

-- The tab row: over the chat; folded down, right over the last lines. Its right
-- end leaves room for the button bar. Blizzard's own place is kept to give back.
local function keepPoints(f)
	local pts = {}
	for n = 1, (read(f.GetNumPoints, f) or 0) do pts[n] = { f:GetPoint(n) } end
	return pts
end
local function placeTabs(on, folded, n)
	local d = dock()
	if not d then return end
	if on then
		d.srPoints = d.srPoints or keepPoints(d)
		local y = (folded and CH.FoldsDown()) and (4 + n * LINE_H) or nil
		local w = (CH.barW or 0) + 6
		d:ClearAllPoints()
		if y then
			d:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMLEFT", 0, y)
			d:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", -w, y)
		else
			d:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 6)
			d:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", -w, 6)
		end
		CH.tabsDown = y ~= nil
	elseif d.srPoints then
		d:ClearAllPoints()
		for _, pt in ipairs(d.srPoints) do pcall(d.SetPoint, d, unpack(pt)) end
		d.srPoints = nil
		CH.tabsDown = false
	end
	-- the bar at the tab row's right end
	if CH.bar then
		CH.bar:ClearAllPoints()
		if d then CH.bar:SetPoint("BOTTOMLEFT", d, "BOTTOMRIGHT", 6, -3) end
		CH.bar:SetShown(on)
	end
end

-- The input lines: folded up, under the preview lines; otherwise Blizzard's place.
local function placeInputs(folded, n)
	local up = folded and not CH.FoldsDown()
	for _, w in ipairs(frames()) do
		local eb = part(w.i, "EditBox")
		if eb then
			if up then
				eb.srPoints = eb.srPoints or keepPoints(eb)
				local y = -2 - n * LINE_H
				eb:ClearAllPoints()
				eb:SetPoint("TOPLEFT", w.cf, "TOPLEFT", -5, y)
				eb:SetPoint("TOPRIGHT", w.cf, "TOPRIGHT", 5, y)
			elseif eb.srPoints then
				eb:ClearAllPoints()
				for _, pt in ipairs(eb.srPoints) do pcall(eb.SetPoint, eb, unpack(pt)) end
				eb.srPoints = nil
			end
		end
	end
end

-- Everything that follows the fold, set together (also on every new preview line).
function CH.Layout()
	local on, folded = isOn(), CH.Folded()
	local n = preview(folded)
	CH.lastLines = n
	placeInputs(folded, n)
	placeTabs(on, folded, n)
	if CH.foldBtn then
		local down = CH.FoldsDown()
		-- the arrow points the way it will go: towards the fold, or back out of it
		local kind = P().chatCollapsed and (down and "up" or "down") or (down and "down" or "up")
		CH.foldBtn.srIcon:SetTexture(K.MEDIA .. "glyph_" .. kind)
	end
	return n
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------
-- How close a window may go to the screen's edges: Blizzard keeps room for its
-- button column on the left (about 35 px); SITREP's chat has none, only its pane,
-- the tab row over it and the input line under it.
local CLAMP = { -9, 9, 34, -38 } -- left, right, top, bottom
local function clamp(cf, on)
	if not cf.SetClampRectInsets then return end
	if on then
		if not cf.srClamp then cf.srClamp = { read(cf.GetClampRectInsets, cf) } end
		pcall(cf.SetClampRectInsets, cf, unpack(CLAMP))
	elseif cf.srClamp then
		if #cf.srClamp == 4 then pcall(cf.SetClampRectInsets, cf, unpack(cf.srClamp)) end
		cf.srClamp = nil
	end
end
CH.CLAMP = CLAMP

-- The whole chat's size (Layout: Chat): windows, tabs, input lines, tab bar and
-- SITREP's parts. Touched only once it is not 1 (or SITREP changed it before).
function CH.Scale()
	local want = ns.P.enabled and (ns.P.hud.frameScale.chat or 1) or 1
	if want == 1 and not CH.scaled then return end
	CH.scaled = want ~= 1
	local function set(f) if type(f) == "table" and f.SetScale then pcall(f.SetScale, f, want) end end
	for _, w in ipairs(frames()) do
		set(w.cf)
		set(part(w.i, "Tab"))
		set(part(w.i, "EditBox"))
	end
	set(dock())
	set(CH.bar)
	set(CH.preview)
	CH.scale = want
	if CH.mover then CH.mover.Place() end
end

function CH.Apply()
	if not P() then return end
	frames()
	CH.Scale()
	local on = isOn()
	local folded = CH.Folded()
	tabAlphas(on)
	for _, w in ipairs(frames()) do
		local i, cf = w.i, w.cf
		local o = remember(cf)
		applyFont(cf)
		-- Blizzard's background, borders, button column and scroll bar: gone while on
		for _, sfx in ipairs(textures()) do
			local t = part(i, sfx)
			if t then K.Conceal(t, on) end
		end
		K.Conceal(part(i, "ButtonFrame") or rawget(cf, "buttonFrame"), on)
		K.Conceal(rawget(cf, "ScrollBar"), on)
		K.Conceal(rawget(cf, "ScrollToBottomButton"), on)
		-- messages stay (the pane holds them); off: Blizzard's fading back
		if on then
			pcall(cf.SetFading, cf, false)
		else
			if o.fading ~= nil then pcall(cf.SetFading, cf, o.fading) end
			if o.fadeTime then pcall(cf.SetTimeVisible, cf, o.fadeTime) end
		end
		pane(cf, on)
		clamp(cf, on)
		styleEditBox(i, on)
		styleTab(i, cf, on)
		-- folded: out of sight and out of the mouse's way
		if folded then
			pcall(cf.SetAlpha, cf, 0)
			pcall(cf.EnableMouse, cf, false)
			pcall(cf.EnableMouseWheel, cf, false)
			cf.srFolded = true
		else
			if cf.srFolded then
				cf.srFolded = nil
				pcall(cf.EnableMouse, cf, true)
				pcall(cf.EnableMouseWheel, cf, true)
			end
			-- its own opacity while SITREP is on (also with SITREP's chat off)
			pcall(cf.SetAlpha, cf, ns.P.enabled and K.Opacity("chat") or 1)
		end
	end
	-- Blizzard's chat buttons: into the bar, or back
	for _, d in ipairs(BAR) do
		local b = _G[d[1]]
		if type(b) == "table" then if on then take(b, d[2]) else giveBack(b) end end
	end
	for _, n in ipairs(GONE) do K.Conceal(_G[n], on) end
	if CH.bar then
		CH.bar:SetShown(on)
		CH.LayoutBar()
	end
	-- moving the main window (the docked ones follow it)
	if CH.mover then
		if on then CH.mover.Place() else CH.mover.Restore() end
		CH.mover:SetShown(on and not ns.P.hud.locked)
	end
	CH.Layout()
	CH.UpdateTabs()
	CH.ShowParts(on and CH.presence or 1)
end

---------------------------------------------------------------------------
-- Folding, typing, unread
---------------------------------------------------------------------------
function CH.Set(folded)
	P().chatCollapsed = folded and true or false
	CH.peek = false
	-- unfolded: what the selected tab got is seen now
	if not folded then unread[selected()] = nil end
	ns.Changed("ui.chatCollapsed")
end
function CH.Toggle() CH.Set(not P().chatCollapsed) end

-- Every chat window pulled out of the tab bar (a tab dragged off by accident)
-- back into it, as a tab beside the others (/sitrep chat dock). Returns how many.
function CH.DockAll()
	if type(_G.FCF_DockFrame) ~= "function" then return 0 end
	local n = 0
	for _, w in ipairs(frames()) do
		local cf = w.cf
		if cf ~= _G.ChatFrame1 and not rawget(cf, "isDocked") and read(cf.IsShown, cf) then
			if pcall(_G.FCF_DockFrame, cf) then n = n + 1 end
		end
	end
	if n > 0 then CH.Apply() end
	return n
end
function SITREP_ToggleChat() if ns.P then CH.Toggle() end end

-- Enter while folded: unfolded while you type, folded back after.
function CH.Typing(on)
	if not (isOn() and P().chatCollapsed) then CH.peek = false return end
	if on and not CH.peek then
		CH.peek = true
		CH.Apply()
	elseif not on and CH.peek then
		CH.peek = false
		unread[selected()] = nil
		CH.Apply()
	end
end

local function shows(cf, group)
	if type(_G.ChatFrame_ContainsMessageGroup) == "function" then
		local ok, yes = pcall(_G.ChatFrame_ContainsMessageGroup, cf, group)
		if ok then return yes and true or false end
	end
	for _, g in ipairs(rawget(cf, "messageTypeList") or {}) do if g == group then return true end end
	return false
end

-- A new message: unread in every window that shows it, unless you see it there
-- (that window's tab selected, the chat not folded) or it is your own.
local function message(event, text, sender)
	if not isOn() then return end
	local who = ns.plain(sender)
	local short = type(who) == "string" and (who:match("^([^%-]+)") or who) or nil
	if short ~= nil and short == read(UnitName, "player") then return end
	local group = event:sub(10)
	local windows = {}
	for _, w in ipairs(frames()) do if shows(w.cf, group) then windows[#windows + 1] = w.cf end end
	if #windows == 0 and _G.ChatFrame1 then windows[1] = ChatFrame1 end
	local folded = CH.Folded()
	for _, cf in ipairs(windows) do
		if folded or cf ~= selected() then unread[cf] = (unread[cf] or 0) + 1 end
	end
	CH.UpdateTabs()
end
CH.Message = message

-- A line a chat window shows (its AddMessage, after it): kept, the last few.
local function shown(cf, text, r, g, b)
	if text == nil then return end
	local list = lines[cf]
	if not list then list = {}; lines[cf] = list end
	list[#list + 1] = { text = text, r = ns.plain(r), g = ns.plain(g), b = ns.plain(b), at = GetTime() }
	while #list > PREVIEW_LINES do table.remove(list, 1) end
	if CH.Folded() and cf == selected() then CH.Layout() end
end
CH.Shown = shown

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function build()
	if CH.bar or type(_G.ChatFrame1) ~= "table" then return end
	-- the button bar (Blizzard's buttons join it in Apply)
	local bar = CreateFrame("Frame", "SITREP_ChatBar", UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar.bg = K.Backdrop(bar, { C.bg[1], C.bg[2], C.bg[3], 0.6 }, 8, { shadow = false })
	CH.bar = bar
	local fb = CreateFrame("Button", "SITREP_ChatFold", bar)
	fb:SetSize(BTN_W, BTN_H)
	fb.srInBar = true
	icon(fb, "down")
	fb:RegisterForClicks("LeftButtonUp")
	fb:SetScript("OnClick", function() CH.Toggle() end)
	K.Tooltip(fb, "Chat", "Click: fold the chat away (the last 3 lines and tabs with new messages stay) or show it again. A key binding and /sitrep chat do it too.")
	CH.foldBtn = fb
	-- the voice buttons come and go with voice chat: the bar follows
	for _, d in ipairs(BAR) do
		local b = _G[d[1]]
		if type(b) == "table" and b.HookScript then
			b:HookScript("OnShow", function() if b.srInBar then CH.LayoutBar() end end)
			b:HookScript("OnHide", function() if b.srInBar then CH.LayoutBar() end end)
		end
	end
	-- the preview lines; links in them work, a click beside a link opens that tab
	local pv = CreateFrame("Frame", "SITREP_ChatPreview", UIParent)
	pv:SetFrameStrata("MEDIUM")
	pv.lines = {}
	for i = 1, PREVIEW_LINES do
		local l = CreateFrame("Frame", nil, pv)
		l:SetHeight(LINE_H - 1)
		l.bg = K.Backdrop(l, { C.bg[1], C.bg[2], C.bg[3], 0.55 }, 8, { shadow = false })
		-- (a plain font string: chat lines keep their own case)
		l.text = l:CreateFontString(nil, "OVERLAY")
		face(l, select(1, read(ChatFrame1.GetFont, ChatFrame1)) or K.FONT, P().chatSize)
		l.text:SetPoint("LEFT", 7, 0)
		l.text:SetPoint("RIGHT", -7, 0)
		l.text:SetJustifyH("LEFT")
		l.text:SetWordWrap(false)
		l:EnableMouse(true)
		if l.SetHyperlinksEnabled then pcall(l.SetHyperlinksEnabled, l, true) end
		l:SetScript("OnHyperlinkClick", function(self, link, text, button)
			self.linkAt = GetTime()
			if type(_G.SetItemRef) == "function" then pcall(_G.SetItemRef, link, text, button, self.cf or ChatFrame1) end
		end)
		l:SetScript("OnHyperlinkEnter", function(self, link)
			if not GameTooltip then return end
			pcall(function()
				GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
				GameTooltip:SetHyperlink(link)
				GameTooltip:Show()
			end)
		end)
		l:SetScript("OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		-- (after the link's own click, if it was one: then nothing more)
		l:SetScript("OnMouseUp", function(self)
			local at = GetTime()
			local function open()
				if self.linkAt == at then return end
				local tab = self.cf and _G[(self.cf:GetName() or "") .. "Tab"]
				if tab and type(_G.FCF_Tab_OnClick) == "function" then pcall(_G.FCF_Tab_OnClick, tab, "LeftButton") end
				CH.Set(false)
			end
			if C_Timer and C_Timer.After then C_Timer.After(0, open) else open() end
		end)
		pv.lines[i] = l
	end
	pv:Hide()
	CH.preview = pv
	-- the presence driver
	CH.driver = CreateFrame("Frame")
	CH.driver:SetScript("OnUpdate", ns.Timed("chat (presence)", drive))
	-- Blizzard places its tab bar again (a window docked or undocked): that is its
	-- place now, SITREP's goes on top
	for _, fn in ipairs({ "FCF_DockUpdate", "FCF_UpdateDockPosition" }) do
		if type(_G[fn]) == "function" then
			hooksecurefunc(fn, function()
				local d = dock()
				if not (d and isOn()) then return end
				d.srPoints = keepPoints(d)
				CH.Layout()
			end)
		end
	end
	-- a tab clicked: read; folded, it unfolds there
	for _, fn in ipairs({ "FCF_Tab_OnClick", "FCFDock_SelectWindow", "FCF_SelectDockFrame" }) do
		if type(_G[fn]) == "function" then
			hooksecurefunc(fn, function()
				if not isOn() then return end
				if fn == "FCF_Tab_OnClick" and P().chatCollapsed then CH.Set(false) return end
				if not CH.Folded() then unread[selected()] = nil end
				CH.UpdateTabs()
				if CH.Folded() then CH.Layout() end
			end)
		end
	end
	-- Blizzard sets the size again (its chat settings, the size menu): that becomes
	-- the size to give back, SITREP's goes on top again
	if type(_G.FCF_SetChatWindowFontSize) == "function" then
		hooksecurefunc("FCF_SetChatWindowFontSize", function(_, cf, size)
			cf = cf or (_G.FCF_GetCurrentChatFrame and _G.FCF_GetCurrentChatFrame())
			if type(cf) ~= "table" or not orig[cf] then return end
			if type(size) == "number" then orig[cf].size = size end
			applyFont(cf)
		end)
	end
	-- Blizzard sets the room for its buttons again (a window moved, docked, its
	-- button side changed): SITREP's again
	for _, fn in ipairs({ "FCF_UpdateButtonSide", "FCF_DockUpdate" }) do
		if type(_G[fn]) == "function" then
			hooksecurefunc(fn, function()
				if not isOn() then return end
				for _, w in ipairs(cached()) do clamp(w.cf, true) end
			end)
		end
	end
	-- and puts the window back at its saved place
	if type(_G.FCF_RestorePositionAndDimensions) == "function" then
		hooksecurefunc("FCF_RestorePositionAndDimensions", function(cf)
			if cf == _G.ChatFrame1 and CH.mover and isOn() then CH.mover.Place() end
		end)
	end
end

-- every line each window shows (hooked after Blizzard's: nothing changes in it)
local hooked = setmetatable({}, { __mode = "k" })
function CH.HookWindows()
	for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if type(cf) == "table" and type(cf.AddMessage) == "function" and not hooked[cf] then
			hooked[cf] = true
			hooksecurefunc(cf, "AddMessage", function(self, text, r, g, b) shown(self, text, r, g, b) end)
		end
	end
end

ns.On("SR_LOGIN", function()
	if type(_G.ChatFrame1) ~= "table" then return end
	-- 4.1: the chat sits on a glass pane now; a profile from before had none (0)
	if not P().chatGlass then
		P().chatGlass = true
		if (ns.P.hud.bgAlpha.chat or 0) == 0 then ns.P.hud.bgAlpha.chat = 0.45 end
	end
	if not CH.mover then CH.mover = K.Mover(ChatFrame1, "chat", "CHAT", "BOTTOMLEFT") end
	build()
	CH.HookWindows()
	CH.Apply()
end)
ns.On("UPDATE_CHAT_WINDOWS", function() CH.HookWindows() end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
	ns.On(e, function() if CH.mover then CH.Apply() end end)
end
for _, g in ipairs(EVENTS) do
	ns.On("CHAT_MSG_" .. g, function(event, text, sender) message(event, text, sender) end)
end
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key:sub(1, 3) == "ui." or key:sub(1, 4) == "hud." then CH.Apply() end
end)
