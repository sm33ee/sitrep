-- SITREP · UI Kit
-- A small widget set drawn entirely from flat textures and lines, so the HUD and
-- the console share one look: dark glass panels, 1px hairlines, accent-coloured
-- corner brackets, pill toggles, custom sliders and dropdowns.

local ADDON, ns = ...
local format, min, max = string.format, math.min, math.max
local K = {}
ns.Kit = K

K.WHITE = "Interface\\Buttons\\WHITE8X8"
K.DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- One look (4.3): soft rounded panels of dark glass with a soft shadow, DM Sans,
-- sentence case, glyphs instead of words on the plates, glass that is lighter out
-- of combat and denser in it. (The "tactical" look of up to 3.59 is gone: hairlines,
-- corner brackets, Arial Narrow, capitals.)
K.C = {
	bg     = { 0.070, 0.086, 0.094, 0.78 },
	panel  = { 0.085, 0.100, 0.110, 0.94 },
	raised = { 0.130, 0.150, 0.160, 1.00 },
	hover  = { 0.175, 0.200, 0.210, 1.00 },
	line   = { 1, 1, 1, 0.06 },
	line2  = { 1, 1, 1, 0.12 },
	text   = { 0.93, 0.95, 0.945, 1 },
	dim    = { 0.60, 0.65, 0.635, 1 },
	faint  = { 0.40, 0.45, 0.44, 1 },
	red    = { 1.00, 0.48, 0.42, 1 },
}
K.MEDIA = "Interface\\AddOns\\SITREP\\Media\\"
K.FONT = K.MEDIA .. "Fonts\\DMSans-Medium.ttf"
K.FONT_UI = K.MEDIA .. "Fonts\\DMSans-Regular.ttf"
K.FONT_BOLD = K.MEDIA .. "Fonts\\DMSans-Bold.ttf"
K.FONT_SCALE = 0.94 -- DM Sans reads larger than the game's fonts at the same size

function K.Accent()
	local a = ns.Data.ACCENTS[ns.P and ns.P.hud.accent or "nvg"] or ns.Data.ACCENTS.nvg
	return a[1], a[2], a[3]
end

-- Anything drawn in the accent colour registers a painter; changing the theme
-- repaints them all.
local painters = {}
function K.Paint(fn)
	painters[#painters + 1] = fn
	fn(K.Accent())
	return fn
end
function K.Repaint()
	local r, g, b = K.Accent()
	for i = 1, #painters do painters[i](r, g, b) end
end
ns.On("SR_CONFIG", function(_, key) if key == "*" or key == "hud.accent" then K.Repaint() end end)

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
function K.Tex(parent, layer, c, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	t:SetTexture(K.WHITE)
	if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
	return t
end

---------------------------------------------------------------------------
-- Glass: rounded shapes from 64 x 64 textures cut into nine (corners keep their
-- size, edges and middle stretch), so a panel of any size has round corners.
---------------------------------------------------------------------------
local RADII = { 4, 8, 12 }
local function radiusFile(r)
	local best = RADII[1]
	for _, v in ipairs(RADII) do if v <= r then best = v end end
	return best
end
local NINE = { -- name, texcoords (as fractions of the corner c), anchors
	"TL", "T", "TR", "L", "C", "R", "BL", "B", "BR",
}
-- Nine textures of `file` (corner `corner` texture px = UI px) on `parent`, round
-- the box `box` (a region they follow), grown by `outset` px on every side.
local function nine(parent, layer, sub, file, corner, outset, box)
	local c = corner / 64
	local p = {}
	for _, n in ipairs(NINE) do
		local t = parent:CreateTexture(nil, layer, nil, sub)
		t:SetTexture(file)
		if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false); pcall(t.SetTexelSnappingBias, t, 0) end
		p[n] = t
	end
	p.TL:SetTexCoord(0, c, 0, c); p.T:SetTexCoord(c, 1 - c, 0, c); p.TR:SetTexCoord(1 - c, 1, 0, c)
	p.L:SetTexCoord(0, c, c, 1 - c); p.C:SetTexCoord(c, 1 - c, c, 1 - c); p.R:SetTexCoord(1 - c, 1, c, 1 - c)
	p.BL:SetTexCoord(0, c, 1 - c, 1); p.B:SetTexCoord(c, 1 - c, 1 - c, 1); p.BR:SetTexCoord(1 - c, 1, 1 - c, 1)
	for _, n in ipairs({ "TL", "TR", "BL", "BR" }) do p[n]:SetSize(corner, corner) end
	p.TL:SetPoint("TOPLEFT", box, "TOPLEFT", -outset, outset)
	p.TR:SetPoint("TOPRIGHT", box, "TOPRIGHT", outset, outset)
	p.BL:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -outset, -outset)
	p.BR:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", outset, -outset)
	p.T:SetPoint("TOPLEFT", p.TL, "TOPRIGHT"); p.T:SetPoint("BOTTOMRIGHT", p.TR, "BOTTOMLEFT")
	p.B:SetPoint("TOPLEFT", p.BL, "TOPRIGHT"); p.B:SetPoint("BOTTOMRIGHT", p.BR, "BOTTOMLEFT")
	p.L:SetPoint("TOPLEFT", p.TL, "BOTTOMLEFT"); p.L:SetPoint("BOTTOMRIGHT", p.BL, "TOPRIGHT")
	p.R:SetPoint("TOPLEFT", p.TR, "BOTTOMLEFT"); p.R:SetPoint("BOTTOMRIGHT", p.BR, "TOPRIGHT")
	p.C:SetPoint("TOPLEFT", p.TL, "BOTTOMRIGHT"); p.C:SetPoint("BOTTOMRIGHT", p.BR, "TOPLEFT")
	return p
end
K.Nine = nine

-- A group of textures that answers like one texture (colour, alpha, shown).
local Group = {}
Group.__index = Group
local function group(list) return setmetatable({ parts = list, r = 1, g = 1, b = 1, a = 1, mul = 1 }, Group) end
function Group:apply()
	for _, t in ipairs(self.parts) do t:SetVertexColor(self.r, self.g, self.b, self.a * self.mul) end
	if self.shadow then
		for _, t in ipairs(self.shadow) do t:SetVertexColor(0, 0, 0, 0.38 * self.a * self.mul) end
	end
end
function Group:SetVertexColor(r, g, b, a)
	-- a colour the client keeps secret (dispel types in combat): straight to the
	-- parts, as it is (widgets take secrets; nothing kept to compute with)
	if ns.isSecret(r) or ns.isSecret(a) then
		for _, t in ipairs(self.parts) do t:SetVertexColor(r, g, b, a) end
		return
	end
	self.r, self.g, self.b, self.a = r or 1, g or 1, b or 1, a or 1
	self:apply()
end
Group.SetColorTexture = Group.SetVertexColor
function Group:GetVertexColor() return self.r, self.g, self.b, self.a end
function Group:SetAlpha(a)
	for _, t in ipairs(self.parts) do t:SetAlpha(a) end
	for _, t in ipairs(self.shadow or {}) do t:SetAlpha(a) end
end
function Group:SetShown(on)
	for _, t in ipairs(self.parts) do t:SetShown(on) end
	for _, t in ipairs(self.shadow or {}) do t:SetShown(on) end
	self.shown = on and true or false
end
function Group:Show() self:SetShown(true) end
function Group:Hide() self:SetShown(false) end
function Group:IsShown() return self.shown ~= false end
function Group:SetTexture() end
function Group:SetDrawLayer() end
-- position: the box the shape follows
function Group:SetAllPoints(...) if self.box then self.box:SetAllPoints(...) end end
function Group:SetPoint(...) if self.box then self.box:SetPoint(...) end end
function Group:ClearAllPoints() if self.box then self.box:ClearAllPoints() end end
function Group:SetSize(...) if self.box then self.box:SetSize(...) end end
function Group:SetWidth(...) if self.box then self.box:SetWidth(...) end end
function Group:SetHeight(...) if self.box then self.box:SetHeight(...) end end
K.Group = group
-- What another region may be anchored to: a glass pane's box, or the texture itself.
function K.Region(x) return type(x) == "table" and x.box or x end

-- Glass that is lighter out of combat and denser in it: every backdrop made with
-- mood = true follows K.mood (calm CALM, in combat 1).
local moody = setmetatable({}, { __mode = "k" })
K.CALM = 0.7
K.mood = 1
function K.SetMood(inCombat)
	K.mood = inCombat and 1 or K.CALM
	for g in pairs(moody) do g.mul = K.mood; g:apply() end
end
ns.On("PLAYER_REGEN_DISABLED", function() K.SetMood(true) end)
ns.On("PLAYER_REGEN_ENABLED", function() K.SetMood(false) end)
ns.On("SR_LOGIN", function() K.SetMood(InCombatLockdown()) end)

-- A panel's background: a rounded pane (radius r, default 12) with a soft shadow
-- (opts.shadow ~= false) that answers like a texture. Covers its parent
-- (SetAllPoints) unless moved. opts.mood: follows calm / combat.
function K.Backdrop(parent, c, r, opts)
	opts = opts or {}
	c = c or K.C.bg
	r = radiusFile(r or 12)
	local box = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
	box:SetColorTexture(0, 0, 0, 0)
	box:SetAllPoints()
	local p = nine(parent, "BACKGROUND", opts.sub or -6, K.MEDIA .. "fill" .. r, r, 0, box)
	local list = {}
	for _, n in ipairs(NINE) do list[#list + 1] = p[n] end
	local g = group(list)
	g.box = box
	if opts.shadow ~= false then
		local sp = nine(parent, "BACKGROUND", -7, K.MEDIA .. "shadow", 24, 12, box)
		g.shadow = {}
		for _, n in ipairs(NINE) do g.shadow[#g.shadow + 1] = sp[n] end
	end
	if opts.mood then moody[g] = true; g.mul = K.mood end
	g:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	return g
end

-- Glyphs: small shapes said in a line of text (|T escapes), coloured.
K.GLYPHS = { you = "diamond", healer = "plus", kill = "ring", casting = "dot", aggro = "triangle", rare = "star",
	locked = "lock", quest = "bang" }
function K.Glyph(kind, r, g, b, size)
	local file = K.GLYPHS[kind] or kind
	size = size or 11
	return format("|T%sglyph_%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t", K.MEDIA, file, size, size,
		math.floor((r or 1) * 255), math.floor((g or 1) * 255), math.floor((b or 1) * 255))
end

function K.Disc(parent, layer, size, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	t:SetTexture(K.DISC)
	t:SetSize(size, size)
	return t
end

---------------------------------------------------------------------------
-- Fonts that can write every name. Arial Narrow and Friz Quadrata only carry
-- Latin glyphs, so Cyrillic, Korean and Chinese names came out as boxes. A font
-- family keeps our face for Latin text and switches file per alphabet; the other
-- alphabets are borrowed from Blizzard's own font objects, so they use exactly
-- the files this client ships.
---------------------------------------------------------------------------
local ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
local ALPHABET_FALLBACK = {
	korean = "Fonts\\2002.TTF", simplifiedchinese = "Fonts\\ARKai_T.ttf",
	traditionalchinese = "Fonts\\blei00d.TTF", russian = "Fonts\\FRIZQT___CYR.TTF",
}
local families, familyCount = {}, 0

-- The file a Blizzard font object uses for an alphabet: from the first of `refs`
-- (objects or global names) that is a font family and has one. The chat's font
-- object comes first where there is one: on every client it can write every name
-- the chat shows (a German client's other objects may have no Chinese face).
local REFS = { "ChatFontNormal", "GameFontHighlight", "GameFontNormal", "NumberFontNormal", "SystemFont_Shadow_Med1" }
local function fileFor(ref, alphabet)
	local ok, fo = pcall(ref.GetFontObjectForAlphabet, ref, alphabet)
	if not (ok and type(fo) == "table" and fo.GetFont) then return nil end
	local okF, file = pcall(fo.GetFont, fo)
	return okF and type(file) == "string" and file ~= "" and file or nil
end
local function alphabetFile(refs, alphabet)
	for _, r in ipairs(refs) do
		local ref = type(r) == "string" and _G[r] or r
		if type(ref) == "table" and ref.GetFontObjectForAlphabet then
			local file = fileFor(ref, alphabet)
			-- (an object that answers its Latin face for every alphabet is no family)
			if file and (alphabet == "roman" or file ~= fileFor(ref, "roman")) then return file end
		end
	end
	return ALPHABET_FALLBACK[alphabet]
end
-- A font object for (face, size, flags) covering every alphabet, or nil. ref: a
-- font object to borrow the other alphabets from first (the chat's, say).
function K.Family(font, size, flags, ref)
	if not CreateFontFamily then return nil end
	flags = flags or ""
	local key = font .. "|" .. size .. "|" .. flags .. "|" .. tostring(ref and (ref.GetName and ref:GetName() or ref) or "")
	local cached = families[key]
	if cached ~= nil then return cached or nil end
	-- Cyrillic in the same style (Arial Narrow: Blizzard's number font, Friz: its
	-- text font); Korean and Chinese from the chat's font first: the faces this
	-- client surely has (a German client's other fonts may point at files it lacks)
	local style = font == "Fonts\\ARIALN.TTF" and "NumberFontNormal" or font == "Fonts\\FRIZQT__.TTF" and "GameFontHighlight" or nil
	local styled, cjk = {}, {}
	if ref then styled[1], cjk[1] = ref, ref end
	if style then styled[#styled + 1] = style end
	cjk[#cjk + 1] = "ChatFontNormal"
	for _, r in ipairs(REFS) do styled[#styled + 1] = r; cjk[#cjk + 1] = r end
	local members = {}
	for _, a in ipairs(ALPHABETS) do
		local file = a == "roman" and font or alphabetFile(a == "russian" and styled or cjk, a)
		if file then members[#members + 1] = { alphabet = a, file = file, height = size, flags = flags } end
	end
	familyCount = familyCount + 1
	local ok, fo = pcall(CreateFontFamily, "SITREP_Font" .. familyCount, members)
	families[key] = ok and fo or false
	return families[key] or nil
end

-- (capitals were the old look's: text stays as it is; K.Case makes sentence case)
function K.Upper(s) return s end

-- Glass writes in sentence case: words in capitals ("TARGETED BY 2") become
-- lower case ("Targeted by 2"), the first one capitalised; abbreviations keep
-- their capitals; names (mixed case) and colour codes are left alone.
local ACRONYMS = { HVT = true, HP = true, OOM = true, PVP = true, AOE = true, XP = true, NPC = true, EST = true,
	TTL = true, DPS = true, HK = true, GCD = true, CC = true, AFK = true, DND = true, ID = true, UI = true, HUD = true,
	LOS = true, EP = true, PWIN = true, SITREP = true, OK = true, AAR = true, II = true, III = true, IV = true }
K.ACRONYMS = ACRONYMS
function K.Case(s)
	if type(s) ~= "string" or ns.isSecret(s) or not s:find("%u%u") then return s end
	local codes = {}
	s = s:gsub("|[cC]%x%x%x%x%x%x%x%x", function(code) codes[#codes + 1] = code return "\1" end)
	s = s:gsub("|[Tt][^|]*|[Tt]", function(code) codes[#codes + 1] = code return "\1" end)
	local src = s
	s = s:gsub("()(%a+)", function(at, word)
		if #word < 2 or word:find("%l") or ACRONYMS[word] then return word end
		-- the first word, and the first after a separator (· : . ! ?), capitalised
		local before = src:sub(1, at - 1):match("([^%s\1])[%s\1]*$")
		local low = word:lower()
		if not before or before:find("[:%.!%?\183]") then low = low:sub(1, 1):upper() .. low:sub(2) end
		return low
	end)
	local i = 0
	return (s:gsub("\1", function() i = i + 1 return codes[i] end))
end

local function applyFont(fs, font, size, flags)
	size = size * K.FONT_SCALE
	local fam = K.Family(font, size, flags)
	if not (fam and pcall(fs.SetFontObject, fs, fam)) then fs:SetFont(font, size, flags or "") end
end
K.ApplyFont = applyFont

function K.Font(parent, size, c, font, flags, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	applyFont(fs, font or K.FONT, size or 12, flags or "")
	c = c or K.C.text
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	fs:SetShadowColor(0, 0, 0, 0.8)
	fs:SetShadowOffset(1, -1)
	local set = fs.SetText
	fs.SetText = function(self, text, ...) return set(self, K.Case(text), ...) end
	return fs
end

function K.Border(f, c, t, radius)
	t = t or 1
	c = c or K.C.line2
	if radius ~= 0 then
		-- a rounded ring (radius 0: straight lines); b[1..4] (top,
		-- bottom, left, right) still answer like the
		-- four lines did (colour, alpha)
		local r = radiusFile(radius or 8)
		local box = f:CreateTexture(nil, "BORDER")
		box:SetColorTexture(0, 0, 0, 0)
		box:SetAllPoints()
		local p = nine(f, "BORDER", nil, K.MEDIA .. "ring" .. r .. "_" .. math.min(3, math.max(1, math.floor(t + 0.5))), r, 0, box)
		local b = { group({ p.TL, p.T, p.TR }), group({ p.BL, p.B, p.BR }), group({ p.L }), group({ p.R }) }
		for i = 1, 4 do b[i]:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
		function b.SetColor(_, r_, g_, bl, a) for i = 1, 4 do b[i]:SetVertexColor(r_, g_, bl, a or 1) end end
		b.box = box -- (what the ring follows: re-anchor it to resize the ring)
		f.border = b
		return b
	end
	local b = {}
	for i = 1, 4 do b[i] = K.Tex(f, "BORDER", c) end
	b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("TOPRIGHT"); b[1]:SetHeight(t)
	b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(t)
	b[3]:SetPoint("TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT"); b[3]:SetWidth(t)
	b[4]:SetPoint("TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(t)
	function b.SetColor(_, r, g, bl, a) for i = 1, 4 do b[i]:SetVertexColor(r, g, bl, a or 1) end end
	f.border = b
	return b
end

-- No corner brackets in this look: K.Brackets(f) gives none (an empty list), and
-- brackets the caller colours (a target's mark: fixed) are a soft rounded ring.
function K.Brackets(f, len, thick, alpha, across, fixed)
	if not fixed then f.brackets = {} return f.brackets end
	local save = f.border
	local b = K.Border(f, { 1, 1, 1, alpha or 0.9 }, thick or 2, 4)
	f.border = save
	f.brackets = { b[1], b[2], b[3], b[4] }
	return f.brackets
end

-- "Being hit" borders (unit frames, party, plates): full for a second after the
-- last hit, then fading out over one and a half. f.hit is the border, f.hitAt
-- the time of the last hit. Returns whether it is still showing.
K.HIT_HOLD, K.HIT_FADE = 1.0, 1.5
function K.FadeHit(f, now)
	if not f.hitAt then return false end
	local t = now - f.hitAt
	if t < K.HIT_HOLD then f.hit:SetAlpha(1)
	elseif t < K.HIT_HOLD + K.HIT_FADE then f.hit:SetAlpha(1 - (t - K.HIT_HOLD) / K.HIT_FADE)
	else f.hit:SetAlpha(0); f.hitAt = nil; return false end
	return true
end

function K.Panel(parent, w, h, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", opts.name, parent)
	if w then f:SetSize(w, h) end
	f.bg = K.Backdrop(f, opts.color or K.C.bg, opts.radius, { mood = opts.mood })
	K.Border(f, opts.border or K.C.line, nil, opts.radius or 12)
	if opts.brackets ~= false then K.Brackets(f, opts.bracketLen, opts.bracketThick) end
	return f
end

-- Subtle scanline texture over a region (every 3rd pixel row slightly darker).
function K.Scanlines(f, rows, alpha)
	local lines = {}
	for i = 1, rows do
		local t = K.Tex(f, "BACKGROUND", { 0, 0, 0, alpha or 0.18 }, 1)
		t:SetHeight(1)
		t:SetPoint("LEFT"); t:SetPoint("RIGHT")
		t:SetPoint("TOP", f, "TOP", 0, -i * 3)
		lines[i] = t
	end
	return lines
end

function K.Tooltip(f, title, body)
	f:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if body then GameTooltip:AddLine(body, 0.75, 0.8, 0.78, true) end
		GameTooltip:Show()
	end)
	f:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

---------------------------------------------------------------------------
-- Controls. Each control exposes :Refresh() which re-reads its getter.
---------------------------------------------------------------------------
function K.Header(parent, text, sub)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(sub and 38 or 22)
	local tick = K.Tex(f, "ARTWORK")
	tick:SetSize(3, 14)
	tick:SetPoint("TOPLEFT", 0, -3)
	K.Paint(function(r, g, b) tick:SetVertexColor(r, g, b, 1) end)
	local t = K.Font(f, 14, K.C.text, K.FONT, "")
	t:SetPoint("TOPLEFT", 10, -2)
	t:SetText(K.Upper(text))
	if sub then
		local s = K.Font(f, 11, K.C.dim)
		s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
		s:SetText(sub)
	end
	local rule = K.Tex(f, "ARTWORK", K.C.line)
	rule:SetHeight(1)
	rule:SetPoint("LEFT", t, "RIGHT", 10, 0)
	rule:SetPoint("RIGHT")
	return f
end

function K.Button(parent, text, w, h, onClick, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 120, h or 24)
	b.bg = K.Backdrop(b, K.C.raised, 8, { shadow = false })
	K.Border(b, K.C.line2)
	b.label = K.Font(b, 12, K.C.text)
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b.primary = primary
	K.Paint(function(r, g, bl)
		b.ar, b.ag, b.ab = r, g, bl
		if b.primary then
			b.bg:SetVertexColor(r * 0.28, g * 0.28, bl * 0.28, 1)
			b.border:SetColor(r, g, bl, 0.8)
			b.label:SetTextColor(r, g, bl)
		end
	end)
	b:SetScript("OnEnter", function(self)
		self.border:SetColor(self.ar, self.ag, self.ab, 1)
		if not self.primary then self.bg:SetVertexColor(unpack(K.C.hover)) end
	end)
	b:SetScript("OnLeave", function(self)
		if self.primary then self.border:SetColor(self.ar, self.ag, self.ab, 0.8)
		else self.border:SetColor(unpack(K.C.line2)); self.bg:SetVertexColor(unpack(K.C.raised)) end
	end)
	b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
	b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
	b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
	return b
end

function K.Toggle(parent, label, desc, get, set, width)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(width or 300, desc and 34 or 22)
	local track = CreateFrame("Frame", nil, f)
	track:SetSize(30, 14)
	track:SetPoint("TOPLEFT", 0, -3)
	track.bg = K.Backdrop(track, K.C.raised, 4, { shadow = false })
	K.Border(track, K.C.line2, nil, 4)
	local knob = K.Tex(track, "ARTWORK", K.C.dim)
	knob:SetSize(12, 10)
	f.label = K.Font(f, 12, K.C.text)
	f.label:SetPoint("TOPLEFT", track, "TOPRIGHT", 10, 0)
	f.label:SetText(label)
	if desc then
		f.desc = K.Font(f, 10.5, K.C.dim)
		f.desc:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -3)
		f.desc:SetPoint("RIGHT", f, "RIGHT")
		f.desc:SetJustifyH("LEFT")
		f.desc:SetText(desc)
	end
	-- Called once the column has given the toggle its width: wrap the description.
	function f:Relayout()
		if not self.desc then return end
		self.desc:SetWidth(self:GetWidth() - 40)
		self:SetHeight(24 + math.max(12, self.desc:GetStringHeight()))
	end
	function f:Refresh()
		local on = get() and true or false
		local r, g, b = K.Accent()
		knob:ClearAllPoints()
		if on then
			knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
			knob:SetVertexColor(r, g, b, 1)
			track.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 1)
			track.border:SetColor(r, g, b, 0.7)
		else
			knob:SetPoint("LEFT", track, "LEFT", 2, 0)
			knob:SetVertexColor(unpack(K.C.dim))
			track.bg:SetVertexColor(unpack(K.C.raised))
			track.border:SetColor(unpack(K.C.line2))
		end
	end
	f:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
		if PlaySound and SOUNDKIT then PlaySound(get() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
	end)
	f:SetScript("OnEnter", function() f.label:SetTextColor(1, 1, 1) end)
	f:SetScript("OnLeave", function() f.label:SetTextColor(unpack(K.C.text)) end)
	K.Paint(function() f:Refresh() end)
	return f
end

local function snap(v, lo, hi, step)
	v = math.floor((v - lo) / step + 0.5) * step + lo
	if v < lo then v = lo elseif v > hi then v = hi end
	return v
end

function K.Slider(parent, label, lo, hi, step, get, set, fmt, width)
	local f = CreateFrame("Frame", nil, parent)
	width = width or 300
	f:SetSize(width, 38)
	f.label = K.Font(f, 12, K.C.text)
	f.label:SetPoint("TOPLEFT")
	f.label:SetText(label)
	f.value = K.Font(f, 12, K.C.text, K.FONT, "")
	f.value:SetPoint("TOPRIGHT")
	K.Paint(function(r, g, b) f.value:SetTextColor(r, g, b) end)

	local track = CreateFrame("Button", nil, f)
	track:SetHeight(14)
	track:SetPoint("TOPLEFT", 0, -18)
	track:SetPoint("TOPRIGHT", 0, -18)
	local rail = K.Tex(track, "BACKGROUND", K.C.raised)
	rail:SetHeight(4)
	rail:SetPoint("LEFT"); rail:SetPoint("RIGHT")
	local fill = K.Tex(track, "ARTWORK")
	fill:SetHeight(4)
	fill:SetPoint("LEFT")
	local thumb = K.Tex(track, "OVERLAY", K.C.text)
	thumb:SetSize(6, 14)
	-- tick marks every quarter
	local ticks = {}
	for i = 0, 4 do
		local t = K.Tex(track, "BACKGROUND", K.C.line2, 1)
		t:SetSize(1, 8)
		ticks[i] = t
	end
	function f:Relayout()
		width = self:GetWidth()
		for i = 0, 4 do
			ticks[i]:ClearAllPoints()
			ticks[i]:SetPoint("CENTER", track, "LEFT", (width - 1) * i / 4, 0)
		end
	end
	f:Relayout()
	K.Paint(function(r, g, b) fill:SetVertexColor(r, g, b, 0.9) end)

	function f:Refresh()
		local v = get()
		local frac = (v - lo) / (hi - lo)
		local w = math.max(1, frac * (track:GetWidth() > 0 and track:GetWidth() or width))
		fill:SetWidth(w)
		thumb:ClearAllPoints()
		thumb:SetPoint("CENTER", track, "LEFT", w, 0)
		f.value:SetText(fmt and fmt(v) or tostring(v))
	end
	local function fromCursor()
		local x = GetCursorPosition() / track:GetEffectiveScale()
		local left, w = track:GetLeft(), track:GetWidth()
		if not left or w <= 0 then return end
		local v = snap(lo + (x - left) / w * (hi - lo), lo, hi, step)
		if v ~= get() then set(v) end
		f:Refresh()
	end
	track:SetScript("OnMouseDown", function(self)
		self:SetScript("OnUpdate", fromCursor)
		fromCursor()
	end)
	track:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	track:EnableMouseWheel(true)
	track:SetScript("OnMouseWheel", function(_, d)
		set(snap(get() + d * step, lo, hi, step))
		f:Refresh()
	end)
	track:SetScript("OnEnter", function() thumb:SetVertexColor(K.Accent()) end)
	track:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(K.C.text)) end)
	f:SetScript("OnShow", f.Refresh)
	return f
end

-- Shared popup for every dropdown.
local menu
local function getMenu()
	if menu then return menu end
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:Hide()
	menu = K.Panel(catcher, 160, 20, { color = K.C.panel, brackets = false })
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
	menu.catcher, menu.rows = catcher, {}
	catcher:SetScript("OnClick", function() catcher:Hide() end)
	return menu
end

K.DROPDOWN_ROWS = 14 -- longer lists open in columns
function K.Dropdown(parent, label, options, get, set, width)
	local f = CreateFrame("Frame", nil, parent)
	width = width or 300
	f:SetSize(width, 44)
	f.label = K.Font(f, 12, K.C.text)
	f.label:SetPoint("TOPLEFT")
	f.label:SetText(label)
	local b = CreateFrame("Button", nil, f)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", 0, -18)
	b:SetPoint("TOPRIGHT", 0, -18)
	b.bg = K.Backdrop(b, K.C.raised, 8, { shadow = false })
	K.Border(b, K.C.line2)
	b.text = K.Font(b, 12, K.C.text)
	b.text:SetPoint("LEFT", 8, 0)
	local caret = K.Font(b, 10, K.C.dim)
	caret:SetPoint("RIGHT", -8, 0)
	caret:SetText("v")
	b:SetScript("OnEnter", function() b.border:SetColor(K.Accent()) end)
	b:SetScript("OnLeave", function() b.border:SetColor(unpack(K.C.line2)) end)

	-- options: { { value, label }, ... } or a function returning them; an entry
	-- { header = "TEXT" } is a heading (not selectable). A long list opens in columns.
	local function opts() return type(options) == "function" and options() or options end
	local function textFor(v)
		for _, o in ipairs(opts()) do if not o.header and o[1] == v then return o[2] end end
		return tostring(v)
	end
	function f:Refresh() b.text:SetText(textFor(get())) end

	f.button = b
	b:SetScript("OnClick", function()
		local m = getMenu()
		f.menu = m
		m:ClearAllPoints()
		m:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
		local list = opts()
		local cols = math.ceil(#list / K.DROPDOWN_ROWS)
		local perCol = math.ceil(#list / cols)
		local colW = b:GetWidth()
		m:SetWidth(colW * cols)
		for _, row in ipairs(m.rows) do row:Hide() end
		for i, o in ipairs(list) do
			local row = m.rows[i]
			if not row then
				row = CreateFrame("Button", nil, m)
				row:SetHeight(20)
				row.hl = K.Tex(row, "BACKGROUND", K.C.hover)
				row.hl:SetAllPoints()
				row.hl:Hide()
				row.text = K.Font(row, 12, K.C.text)
				row.text:SetPoint("LEFT", 8, 0)
				row:SetScript("OnEnter", function(self) self.hl:Show() end)
				row:SetScript("OnLeave", function(self) self.hl:Hide() end)
				m.rows[i] = row
			end
			local col, r = math.floor((i - 1) / perCol), (i - 1) % perCol
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 1 + col * colW, -1 - r * 20)
			row:SetWidth(colW - 2)
			if o.header then
				row.text:SetText(o.header)
				row.text:SetTextColor(unpack(K.C.faint))
				row:EnableMouse(false)
				row:SetScript("OnClick", nil)
			else
				row.text:SetText(o[2])
				if o[1] == get() then row.text:SetTextColor(K.Accent()) else row.text:SetTextColor(unpack(K.C.text)) end
				row:EnableMouse(true)
				row:SetScript("OnClick", function()
					set(o[1])
					f:Refresh()
					m.catcher:Hide()
				end)
			end
			row:Show()
		end
		m:SetHeight(perCol * 20 + 2)
		m.catcher:Show()
	end)
	return f
end

-- Row of colour chips (accent picker).
function K.Chips(parent, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(420, 44)
	local chips = {}
	for i, key in ipairs(ns.Data.ACCENT_ORDER) do
		local a = ns.Data.ACCENTS[key]
		local c = CreateFrame("Button", nil, f)
		c:SetSize(78, 40)
		c:SetPoint("LEFT", (i - 1) * 84, 0)
		c.bg = K.Backdrop(c, K.C.raised, 8, { shadow = false })
		K.Border(c, K.C.line2)
		local sw = K.Tex(c, "ARTWORK", { a[1], a[2], a[3], 1 })
		sw:SetSize(78 - 12, 6)
		sw:SetPoint("TOP", 0, -7)
		local t = K.Font(c, 11, K.C.dim)
		t:SetPoint("BOTTOM", 0, 8)
		t:SetText(a.name)
		c.key, c.text = key, t
		c:SetScript("OnClick", function() set(key); f:Refresh() end)
		chips[i] = c
	end
	function f:Refresh()
		for _, c in ipairs(chips) do
			local a = ns.Data.ACCENTS[c.key]
			if get() == c.key then
				c.border:SetColor(a[1], a[2], a[3], 1)
				c.text:SetTextColor(a[1], a[2], a[3])
			else
				c.border:SetColor(unpack(K.C.line2))
				c.text:SetTextColor(unpack(K.C.dim))
			end
		end
	end
	return f
end

function K.EditBox(parent, w, h, multi)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(w, h)
	holder.bg = K.Backdrop(holder, K.C.raised, 8, { shadow = false })
	K.Border(holder, K.C.line2)
	local e = CreateFrame("EditBox", nil, holder)
	e:SetMultiLine(multi and true or false)
	e:SetAutoFocus(false)
	applyFont(e, K.FONT, 12, "") -- names pasted into templates may be in any alphabet
	e:SetTextColor(unpack(K.C.text))
	e:SetPoint("TOPLEFT", 6, -4)
	e:SetPoint("BOTTOMRIGHT", -6, 4)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function() holder.border:SetColor(K.Accent()) end)
	e:SetScript("OnEditFocusLost", function() holder.border:SetColor(unpack(K.C.line2)) end)
	holder.edit = e
	return holder
end

-- A spell's full tooltip beside a row whose name is cut off: the client's own
-- tooltip (full name, rank, description), then the ID and where it came from.
function K.SpellTip(owner, it, extra)
	if not (GameTooltip and it) then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local ok = it.id and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, it.id)
	if not ok then
		GameTooltip:SetText(it.name or "?", 1, 1, 1)
		if it.sub then GameTooltip:AddLine(it.sub, 0.6, 0.6, 0.6) end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s  ·  ID %s%s", it.name or "?", tostring(it.id or "?"), it.src and ("  ·  " .. it.src) or ""), 0.55, 0.8, 1)
	for _, line in ipairs(extra or {}) do GameTooltip:AddLine(line, 0.75, 0.8, 0.78, true) end
	GameTooltip:Show()
end

-- Suggestions under an edit box while you type (the spell library).
--   provider(text) -> { { id, name, sub, icon, src }, ... }
--   onPick(entry)  -> called with the chosen entry (the box shows "Name (ID)")
--   deep(text, cb) -> optional slow search; cb(results, fraction, done)
-- Eight rows at a time; the mouse wheel and Up / Down scroll through all of
-- them, Enter picks the highlighted one, Escape closes.
local SUGGEST_ROWS = 8
function K.Suggest(holder, provider, onPick, deep)
	local e = holder.edit
	local pop = K.Panel(UIParent, holder:GetWidth(), 20, { color = K.C.panel, brackets = false })
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -2)
	pop:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -2)
	pop:Hide()
	pop.rows, pop.items, pop.hi, pop.offset = {}, {}, 1, 0
	-- scrollbar: a thin track with a thumb sized to what is visible
	pop.track = K.Tex(pop, "ARTWORK", K.C.raised)
	pop.track:SetWidth(3)
	pop.thumb = K.Tex(pop, "OVERLAY")
	pop.thumb:SetWidth(3)
	K.Paint(function(r, g, b) pop.thumb:SetVertexColor(r, g, b, 0.9) end)

	local function row(i)
		local r = pop.rows[i]
		if r then return r end
		r = CreateFrame("Button", nil, pop)
		r:SetHeight(20)
		r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
		r:SetPoint("TOPRIGHT", -7, -1 - (i - 1) * 20)
		r.hl = K.Tex(r, "BACKGROUND", K.C.hover)
		r.hl:SetAllPoints()
		r.hl:Hide()
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 4, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = K.Font(r, 11, K.C.text)
		r.name:SetPoint("LEFT", 24, 0)
		r.name:SetPoint("RIGHT", -96, 0)
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		r.meta = K.Font(r, 9.5, K.C.dim, K.FONT, "")
		r.meta:SetPoint("RIGHT", -4, 0)
		r:EnableMouseWheel(true)
		r:SetScript("OnMouseWheel", function(_, d) pop:Scroll(-d) end)
		r:SetScript("OnEnter", function(self)
			if not self.item then return end
			pop.hi = self.itemIndex
			pop:Paint()
			K.SpellTip(self, self.item)
		end)
		r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		pop.rows[i] = r
		return r
	end
	local function pick(it)
		e:SetText(format("%s (%d)", it.name, it.id))
		pop:Hide()
		if onPick then onPick(it) end
	end
	pop.Pick = pick

	function pop:Paint()
		for _, r in ipairs(self.rows) do r.hl:SetShown(r:IsShown() and r.item ~= nil and r.itemIndex == self.hi) end
	end

	-- Draw the visible window of matches, then the summary / full-search line.
	function pop:Render()
		local items, total = self.items, #self.items
		local view = min(total, SUGGEST_ROWS)
		self.offset = max(0, min(self.offset, total - view))
		for i = 1, view do
			local r, idx = row(i), self.offset + i
			local it = items[idx]
			r.item, r.itemIndex = it, idx
			r.icon:SetTexture(it.icon)
			r.name:SetText(it.sub and format("%s  |cff8a9492%s|r", it.name, it.sub) or it.name)
			r.meta:SetText(format("%d  ·  %s", it.id, it.src))
			r:SetScript("OnClick", function() pick(it) end)
			r:Show()
		end
		local shown = view
		local line = self.line
		if total > SUGGEST_ROWS then
			local range = format("%d found  ·  %d-%d", total, self.offset + 1, self.offset + view)
			line = line and (line .. "  ·  " .. range) or ("|cff8a9492" .. range .. "  ·  scroll for more|r")
		end
		if line then
			shown = view + 1
			local r = row(shown)
			r.item, r.itemIndex = nil, nil
			r.icon:SetTexture(nil)
			r.name:SetText(line)
			r.meta:SetText("")
			r:SetScript("OnClick", function() if self.line and self.lineIsDeep and self.onDeep then self.onDeep() end end)
			r:Show()
		end
		for i = shown + 1, #self.rows do self.rows[i]:Hide() end
		self:SetHeight(max(1, shown) * 20 + 2)
		-- scrollbar over the match rows only
		local scroll = total > SUGGEST_ROWS
		self.track:SetShown(scroll); self.thumb:SetShown(scroll)
		if scroll then
			local h = view * 20
			self.track:ClearAllPoints()
			self.track:SetPoint("TOPRIGHT", -2, -1)
			self.track:SetHeight(h)
			local th = max(8, h * view / total)
			self.thumb:ClearAllPoints()
			self.thumb:SetPoint("TOPRIGHT", -2, -1 - (h - th) * self.offset / (total - view))
			self.thumb:SetHeight(th)
		end
		self:SetShown(shown > 0)
		self:Paint()
	end

	function pop:Scroll(delta)
		self.offset = self.offset + delta
		self:Render()
	end

	-- keep the highlighted match inside the visible window
	local function follow()
		if pop.hi <= pop.offset then pop.offset = pop.hi - 1
		elseif pop.hi > pop.offset + SUGGEST_ROWS then pop.offset = pop.hi - SUGGEST_ROWS end
		pop:Render()
	end

	function pop:Fill(items, line, lineIsDeep)
		self.items, self.line, self.lineIsDeep = items, line, lineIsDeep
		self.hi = min(self.hi, max(1, #items))
		self:Render()
	end

	local function refresh()
		if pop.disabled and pop.disabled() then pop:Hide() return end
		local text = e:GetText() or ""
		local q = text:gsub("^%s+", ""):gsub("%s+$", "")
		pop.hi, pop.offset = 1, 0
		local offer = deep and #q >= 3 and not tonumber(q)
		pop:Fill(provider(text), offer and format("|cff8a9492search all spells for \"%s\"…|r", q) or nil, offer)
	end
	pop.Refresh = refresh
	pop.onDeep = function()
		local q = (e:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local base = provider(q)
		deep(q, function(results, frac, done)
			local merged, have = {}, {}
			for _, it in ipairs(base) do merged[#merged + 1] = it; have[it.id] = true end
			for _, it in ipairs(results) do if not have[it.id] then merged[#merged + 1] = it end end
			pop:Fill(merged, done and format("|cff8a9492all spells searched: %d found|r", #results)
				or format("|cff8a9492searching all spells… %d%%|r", math.floor(frac * 100)), false)
		end)
	end
	pop:EnableMouseWheel(true)
	pop:SetScript("OnMouseWheel", function(_, d) pop:Scroll(-d) end)
	e:HookScript("OnTextChanged", function(_, user) if user then refresh() end end)
	e:HookScript("OnEditFocusLost", function()
		if not (pop.IsMouseOver and pop:IsMouseOver()) then pop:Hide() end
	end)
	e:HookScript("OnEscapePressed", function() pop:Hide() end)
	if e.SetAltArrowKeyMode then e:SetAltArrowKeyMode(false) end
	e:HookScript("OnArrowPressed", function(_, key)
		if not pop:IsShown() or #pop.items == 0 then return end
		if key == "DOWN" then pop.hi = min(#pop.items, pop.hi + 1)
		elseif key == "UP" then pop.hi = max(1, pop.hi - 1) end
		follow()
	end)
	-- Enter picks the highlighted match first (the box's own Enter still runs after)
	local own = e:GetScript("OnEnterPressed")
	e:SetScript("OnEnterPressed", function(self)
		if pop:IsShown() and pop.items[pop.hi] then pick(pop.items[pop.hi]) return end
		if own then own(self) end
	end)
	holder.suggest = pop
	return pop
end

-- An element's own opacity (Layout page), 1 when it has none.
function K.Opacity(id)
	local t = ns.P and ns.P.hud.frameAlpha
	return t and t[id] or 1
end

-- Paint an element's background in its own background opacity (Layout page).
-- a: the opacity to use instead (bars keep theirs in P.bars).
function K.Background(tex, id, a)
	if type(tex) ~= "table" then return end
	if a == nil then
		local t = ns.P and ns.P.hud.bgAlpha
		a = t and t[id]
		if a == nil then a = K.C.bg[4] end
	end
	tex:SetVertexColor(K.C.bg[1], K.C.bg[2], K.C.bg[3], a)
end

-- Make a frame draggable while the HUD is unlocked; remembers its position.
-- The gaze layout: what you act on close round your character, where your eyes
-- are anyway: you and your target side by side under it, the cast alert above
-- its head, your emergency items beside you. (Out of combat: these hold secure
-- buttons.) Everything stays movable as before.
ns.Layout = {}
function ns.Layout.Gaze()
	if InCombatLockdown() then ns.print("after the fight: frames with buttons cannot move in combat.") return false end
	local pos = ns.P.hud.pos
	local w = ns.P.frames.width or 300
	pos.player = { "BOTTOMRIGHT", "BOTTOM", -8, 190 }
	pos.target = { "BOTTOMLEFT", "BOTTOM", 8, 190 }
	pos.emergency = { "BOTTOMRIGHT", "BOTTOM", -(w + 22), 196 }
	pos.castAlert = { "CENTER", "CENTER", 0, 110 }
	ns.Changed("*")
	ns.print("arranged round your character: you, your target, the cast alert, your emergency items.")
	return true
end

local movables = {}
function K.Movable(f, id, default)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	-- frames holding secure buttons cannot move in combat
	f:SetScript("OnDragStart", function(self) if not ns.P.hud.locked and not InCombatLockdown() then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		ns.P.hud.pos[id] = { p, rp, x, y }
	end)
	-- while the HUD is unlocked a grip lies over the whole frame: buttons on it
	-- (the emergency items, the party members) would take the drag
	local g = CreateFrame("Frame", nil, f)
	g:SetAllPoints(f)
	g:EnableMouse(true)
	g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", function() local fn = f:GetScript("OnDragStart") if fn then fn(f) end end)
	g:SetScript("OnDragStop", function() local fn = f:GetScript("OnDragStop") if fn then fn(f) end end)
	g:Hide()
	f.srGrip = g
	movables[#movables + 1] = f
	K.ShowGrips()
	function f:RestorePosition()
		local pos = ns.P.hud.pos[id] or default
		self:ClearAllPoints()
		self:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	end
end

-- The grips: over every movable frame while the HUD is unlocked (above its buttons).
function K.ShowGrips()
	local show = ns.P and ns.P.hud and not ns.P.hud.locked or false
	for _, f in ipairs(movables) do
		local g = f.srGrip
		if show then g:SetFrameLevel((ns.read(f.GetFrameLevel, f) or 0) + 30) end
		g:SetShown(show)
	end
end
ns.On("SR_CONFIG", function(_, key) if key == "*" or key == "hud.locked" then K.ShowGrips() end end)
ns.On("SR_LOGIN", function() K.ShowGrips() end)

-- Hide one of Blizzard's frames for as long as SITREP replaces it (concealed =
-- true), or give it back (false). Out of combat it is hidden for real, so its
-- buttons take no clicks; in combat only its alpha changes (some of these frames
-- cannot be hidden then). Blizzard showing it again on its own is undone.
-- Giving back shows it only if it was shown before; a frame SITREP never hid is
-- left alone.
-- (a frame the game protects may not be hidden by an addon in combat: it may)
local function mayHide(f)
	if not InCombatLockdown() then return true end
	return not (f.IsProtected and ns.read(f.IsProtected, f))
end
local concealed = {} -- every frame concealed now (hidden for real once combat ends)

function K.Conceal(f, concealed_)
	if type(f) ~= "table" or (not concealed_ and not f.srConcealed) then return end
	-- Blizzard's own state, kept until it is really given back (in combat only the
	-- alpha returns, so the frame still looks hidden then)
	if concealed_ and f.srWasShown == nil then f.srWasShown = ns.read(f.IsShown, f) ~= false end
	f.srConcealed = concealed_
	concealed[f] = concealed_ or nil
	if not f.srConcealHook then
		f.srConcealHook = true
		-- Blizzard shows it again: hidden again. A protected frame shown in combat
		-- can only be made invisible then; it would still take clicks, so it is
		-- hidden for real the moment combat ends (see below)
		local function again(self)
			if self.srConcealed then
				self:SetAlpha(0)
				if mayHide(self) then self:Hide() end
			end
		end
		-- frames tell when they are shown; textures only through their Show method
		if f.HookScript then pcall(f.HookScript, f, "OnShow", again) else pcall(hooksecurefunc, f, "Show", again) end
	end
	pcall(f.SetAlpha, f, concealed_ and 0 or 1)
	if concealed_ then
		if mayHide(f) then pcall(f.Hide, f) end
	elseif not InCombatLockdown() then
		if f.srWasShown then pcall(f.Show, f) end
		f.srWasShown = nil
	end
end

-- Make one of Blizzard's frames invisible and click-through without hiding it.
-- For frames Blizzard's secure code depends on (the bag bar, the micro buttons):
-- hiding them runs their scripts from SITREP's code, and from then on they carry
-- SITREP's taint; in combat the game then refuses their protected actions (seen:
-- a potion from the bags, "SetPassThroughButtons" blocked). Alpha and mouse run no
-- script. The mouse of protected frames changes out of combat only (after it).
local faded = {}
local function eachFrame(f, fn, depth, deepest)
	fn(f)
	if depth >= (deepest or 3) then return end
	local ok, kids = pcall(function() return { f:GetChildren() } end)
	for _, k in ipairs(ok and kids or {}) do eachFrame(k, fn, depth + 1, deepest) end
end
local function fadeMouse(f)
	local on = f.srFaded
	eachFrame(f, function(x)
		if not x.EnableMouse then return end
		if on then
			if x.srFadeMouse == nil then x.srFadeMouse = ns.read(x.IsMouseEnabled, x) and true or false end
			pcall(x.EnableMouse, x, false)
		elseif x.srFadeMouse ~= nil then
			pcall(x.EnableMouse, x, x.srFadeMouse)
			x.srFadeMouse = nil
		end
	end, 0, f.srFadeDepth)
end
-- deep: how many levels of its parts lose the mouse too (default 3; the modern unit
-- frames hide their health bars and portrait five levels down, each with a tooltip)
function K.Fade(f, fade, deep)
	if type(f) ~= "table" or (not fade and not f.srFaded) then return end
	if deep then f.srFadeDepth = deep end
	f.srFaded = fade or nil
	faded[f] = true
	if not f.srFadeHook and f.HookScript then
		f.srFadeHook = true
		-- Blizzard shows it again (Edit Mode, its own updates): invisible again
		pcall(f.HookScript, f, "OnShow", function(self) if self.srFaded then self:SetAlpha(0) end end)
	end
	pcall(f.SetAlpha, f, fade and 0 or 1)
	if InCombatLockdown() and ns.read(f.IsProtected, f) then return end -- (the mouse: after combat)
	fadeMouse(f)
	if not fade then faded[f] = nil end
end
ns.On("PLAYER_REGEN_ENABLED", function()
	for f in pairs(faded) do
		pcall(f.SetAlpha, f, f.srFaded and 0 or 1)
		fadeMouse(f)
		if not f.srFaded then faded[f] = nil end
	end
end)

-- Combat over: concealed frames Blizzard showed meanwhile are hidden for real
-- (an invisible frame still takes the clicks meant for what lies under it).
function K.ConcealSweep()
	for f in pairs(concealed) do
		if f.srConcealed and ns.read(f.IsShown, f) then
			pcall(f.SetAlpha, f, 0)
			pcall(f.Hide, f)
		end
	end
end
ns.On("PLAYER_REGEN_ENABLED", function() K.ConcealSweep() end)

-- A drag grip that resizes something square: dragging it away from the frame's
-- centre makes it bigger. sx / sy: which way is "away" (-1 left/down, 1
-- right/up). get() returns the size now; set(size, done) applies it (done on release).
function K.DragResize(grip, sx, sy, lo, hi, get, set)
	grip:EnableMouse(true)
	grip:SetScript("OnMouseDown", function(self)
		local x, y = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		self.start = { x = x / scale, y = y / scale, size = get() }
	end)
	grip:SetScript("OnUpdate", function(self)
		local s = self.start
		if not s then return end
		local x, y = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		local dx, dy = (x / scale - s.x) * sx, (y / scale - s.y) * sy
		local d = math.abs(dx) >= math.abs(dy) and dx or dy -- the axis moved most
		self.size = math.max(lo, math.min(hi, math.floor(s.size + d + 0.5)))
		set(self.size, false)
	end)
	grip:SetScript("OnMouseUp", function(self)
		if not self.start then return end
		self.start = nil
		set(self.size or get(), true)
	end)
end

-- Move one of Blizzard's frames (minimap, chat) the way SITREP's own frames move:
-- while the HUD is unlocked a handle covers it; drag the handle to move it. The
-- place is kept in hud.pos[id] as an offset of its corner from the same corner
-- of the screen, so it grows away from that corner. Returns the handle:
--   h.Place()    put the frame where it was dragged (nothing if never dragged)
--   h.Restore()  give the frame Blizzard's place back
function K.Mover(target, id, label, corner)
	local h = CreateFrame("Frame", nil, UIParent)
	h:SetFrameStrata("DIALOG")
	h:SetAllPoints(target)
	h.bg = K.Tex(h, "BACKGROUND", { 0.36, 1, 0.55, 0.12 })
	h.bg:SetAllPoints()
	K.Border(h, { 0.36, 1, 0.55, 0.7 })
	h.label = K.Font(h, 11, K.C.text, K.FONT, "OUTLINE")
	h.label:SetPoint("CENTER")
	h.label:SetText(label .. "\ndrag to move")
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	h:Hide()
	local function ratio() return target:GetEffectiveScale() / UIParent:GetEffectiveScale() end
	local function at(f, r) -- the corner of f, in UIParent's units
		local x = corner:find("RIGHT") and f:GetRight() or f:GetLeft()
		local y = corner:find("TOP") and f:GetTop() or f:GetBottom()
		return x * r, y * r
	end
	local function keepOriginal()
		if h.orig then return end
		h.orig = {}
		for i = 1, (ns.read(target.GetNumPoints, target) or 0) do h.orig[i] = { target:GetPoint(i) } end
	end
	function h.Place()
		local pos = ns.P.hud.pos[id]
		if not pos then h.Restore() return end
		keepOriginal()
		local r = ratio()
		target:ClearAllPoints()
		target:SetPoint(corner, UIParent, corner, pos[3] / r, pos[4] / r)
	end
	function h.Restore()
		if not h.orig then return end
		target:ClearAllPoints()
		for _, p in ipairs(h.orig) do pcall(target.SetPoint, target, unpack(p)) end
		h.orig = nil
	end
	h:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		keepOriginal()
		pcall(target.SetMovable, target, true)
		target:StartMoving()
	end)
	h:SetScript("OnDragStop", function()
		target:StopMovingOrSizing()
		local fx, fy = at(target, ratio())
		local ux, uy = at(UIParent, 1)
		ns.P.hud.pos[id] = { corner, corner, fx - ux, fy - uy }
		h.Place()
	end)
	return h
end
