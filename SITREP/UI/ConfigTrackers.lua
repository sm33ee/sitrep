-- SITREP · Console pages: Trackers

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local format, max, min = string.format, math.max, math.min
local Cfg = ns.Config
local kit = Cfg.kit
local newPage = kit.newPage
local fp = kit.fp

-- 13 TRACKERS: your own spell icons, placed anywhere
---------------------------------------------------------------------------
local LIST_ROWS = 5
local KIND_SHORT = { cd = "ON CD", target = "ON TGT", self = "ON ME", weapon = "ON WPN" }
local KIND_SHORT_INV = { cd = "NOT ON CD", target = "NOT ON TGT", self = "NOT ON ME", weapon = "NOT ON WPN" }

local function buildTrackers()
	local T = ns.Trackers
	local p = newPage("Trackers", "Your spells as icons: on cooldown, on your target, on you (or, inverted, NOT). Place each one anywhere.")
	local half = (p.colW - 12) / 2

	-- the selected item, and a setter that redraws and saves
	local function sel() return T.Selected() end
	local function getS(k, d) return function() local it = sel(); return it and it[k] or d end end
	local function setS(k) return function(v) local it = sel(); if it then it[k] = v; T.Changed() end end end

	-- column 1: add, list, modes ----------------------------------------
	p:Place(K.Toggle(p, "Show tracker icons", nil, function() return ns.P.trackers.enabled end,
		function(v) ns.P.trackers.enabled = v; T.Changed() end), 1, 6)
	local al = K.Font(p, 10, C.dim, K.FONT, "")
	al:SetText("ADD A SPELL  ·  TYPE TO SEARCH (NAME OR ID)")
	al:SetHeight(12)
	p:Place(al, 1, 4)
	local box = K.EditBox(p, p.colW, 24)
	box.fixedWidth = true
	p:Place(box, 1, 6)
	local msg = K.Font(p, 10, C.dim, K.FONT, "")
	msg:SetHeight(12)
	local function add(kind)
		local it, err = T.Add(box.edit:GetText(), kind)
		if it then
			box.edit:SetText("")
			msg:SetTextColor(unpack(C.dim))
			msg:SetText(format("added %s (%s)", it.name or "?", T.KIND_LABEL[kind]:lower()))
		else
			msg:SetTextColor(1, 0.4, 0.35)
			msg:SetText(err)
		end
		p:Refresh()
	end
	local bw = (p.colW - 4) / 2
	local bCd = K.Button(p, "+ Cooldown", bw, 22, function() add("cd") end, true)
	bCd.fixedWidth = true
	p:Place(bCd, 1, 4)
	local bTg = K.Button(p, "+ On target", bw, 22, function() add("target") end)
	bTg:SetPoint("LEFT", bCd, "RIGHT", 4, 0)
	local bMe = K.Button(p, "+ On me", bw, 22, function() add("self") end)
	bMe.fixedWidth = true
	p:Place(bMe, 1, 4)
	local bWp = K.Button(p, "+ On weapon", bw, 22, function() add("weapon") end)
	bWp:SetPoint("LEFT", bMe, "RIGHT", 4, 0)
	p.addButtons = { cd = bCd, target = bTg, self = bMe, weapon = bWp }
	p.addBox = box
	msg:SetWidth(p.colW)
	msg:SetJustifyH("LEFT")
	p:Place(msg, 1, 8)
	-- the spell library: suggestions while typing, slow search on request
	K.Suggest(box, function(t) return T.Lib.Search(t) end, function(it)
		msg:SetTextColor(unpack(C.dim))
		msg:SetText(format("%s (%d): now choose a kind above", it.name, it.id))
	end, T.Lib.Deep)

	-- the list, a page of rows at a time
	local lh = CreateFrame("Frame", nil, p)
	lh:SetHeight(16)
	lh.t = K.Font(lh, 10, C.dim, K.FONT, "")
	lh.t:SetPoint("LEFT")
	lh.n = K.Font(lh, 10, C.dim, K.FONT, "")
	lh.n:SetPoint("RIGHT", -58, 0)
	local first = 1
	local prev = K.Button(lh, "<", 24, 16, function() first = max(1, first - LIST_ROWS); p:Refresh() end)
	prev:SetPoint("RIGHT", -28, 0)
	local nxt = K.Button(lh, ">", 24, 16, function()
		if first + LIST_ROWS <= #T.Mine() then first = first + LIST_ROWS end
		p:Refresh()
	end)
	nxt:SetPoint("RIGHT", 0, 0)
	p:Place(lh, 1, 4)
	local list = CreateFrame("Frame", nil, p)
	list:SetHeight(LIST_ROWS * 22)
	list.rows = {}
	for i = 1, LIST_ROWS do
		local r = CreateFrame("Button", nil, list)
		r:SetHeight(20)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
		r:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
		r.bg = K.Tex(r, "BACKGROUND", C.raised)
		r.bg:SetAllPoints()
		r.bar = K.Tex(r, "ARTWORK")
		r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 6, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = K.Font(r, 11, C.text)
		r.name:SetPoint("LEFT", 28, 0)
		r.name:SetPoint("RIGHT", -64, 0)
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		r.kind = K.Font(r, 9.5, C.dim, K.FONT, "")
		r.kind:SetPoint("RIGHT", -6, 0)
		r:SetScript("OnClick", function(self)
			T.selected = self.itemId
			T.Refresh()
			p:Refresh()
		end)
		-- the full name (and what it watches) when it is cut off
		r:SetScript("OnEnter", function(self)
			local it = self.itemId and T.Get(self.itemId)
			if not it then return end
			local extra = { T.LabelFor(it), T.CombatHow(it) }
			if it.aura or it.auraId then extra[#extra + 1] = "looks for: " .. (it.aura or "") .. (it.auraId and format(" (%d)", it.auraId) or "") end
			K.SpellTip(self, { id = it.spell, name = it.name or T.SpellName(it.spell) }, extra)
		end)
		r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		list.rows[i] = r
	end
	function list:Refresh()
		-- only this character's icons; the others' are counted, not listed
		local items = T.Mine()
		local others = #T.Items() - #items
		if first > #items then first = max(1, #items - LIST_ROWS + 1) end
		lh.t:SetText(others > 0 and format("YOUR ICONS  |cff5c6563+%d OTHER CLASSES|r", others) or "YOUR ICONS")
		lh.n:SetText(#items > LIST_ROWS and format("%d-%d of %d", first, min(#items, first + LIST_ROWS - 1), #items) or tostring(#items))
		local ar, ag, ab = K.Accent()
		for i, r in ipairs(self.rows) do
			local it = items[first + i - 1]
			if it then
				r.itemId = it.id
				local f = T.icons[it.id]
				r.icon:SetTexture(f and f.icon:GetTexture() or "Interface\\Icons\\INV_Misc_QuestionMark")
				r.name:SetText(it.name or T.SpellName(it.spell) or ("#" .. it.spell))
				r.kind:SetText((it.invert and KIND_SHORT_INV or KIND_SHORT)[it.kind])
				local b = T.BORDER[it.border]
				if b then r.bar:SetVertexColor(b[1], b[2], b[3], 1); r.bar:Show() else r.bar:Hide() end
				r.bg:SetVertexColor(unpack(it.id == T.selected and { ar * 0.25, ag * 0.25, ab * 0.25, 1 } or C.raised))
				r.name:SetTextColor(unpack(it.id == T.selected and { ar, ag, ab, 1 } or C.text))
				r:Show()
			else
				r.itemId = nil
				r:Hide()
			end
		end
	end
	p:Place(list, 1, 10)

	p:Place(K.Toggle(p, "Layout mode", "Every icon shows, labelled. Drag them anywhere; click one to edit it.",
		function() return T.editing end, function(v) T.SetEditing(v); p:Refresh() end), 1, 6)
	p:Place(K.Toggle(p, "Keep in macros", "Survives restarts (the beta forgets addon settings): uses a few general macros.",
		function() return ns.P.trackers.mirror end, function(v) T.SetMirror(v); p:Refresh() end), 1, 2)
	local mnote = K.Font(p, 10, C.faint, K.FONT, "")
	mnote:SetHeight(24)
	mnote:SetWidth(p.colW)
	mnote:SetJustifyH("LEFT")
	p:Place(mnote, 1)

	-- column 2: the selected icon ---------------------------------------
	local ed = {}   -- widgets shown only with a selection
	local title = K.Font(p, 13, C.text)
	title:SetWidth(p.colW - 112)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	p:Place(title, 2, 2)
	local sub = K.Font(p, 10, C.dim, K.FONT, "")
	p:Place(sub, 2, 10)
	-- whose icon: this class (default), this character, or everyone; click to change
	local SCOPES = { "class", "char", "all" }
	ed.scope = K.Button(p, "THIS CLASS", 108, 18, function()
		local it = sel()
		if not it then return end
		local cur = it.scope or "class"
		for i, s in ipairs(SCOPES) do if s == cur then it.scope = SCOPES[i % #SCOPES + 1] break end end
		local class, char = T.Me()
		it.class, it.char = it.class or class, it.char or char
		T.Changed()
		p:Refresh()
	end)
	ed.scope:SetPoint("TOPRIGHT", p, "TOPLEFT", 2 * p.colW + 30, -50)
	K.ApplyFont(ed.scope.label, K.FONT, 10, "")
	K.Tooltip(ed.scope, "Who sees this icon", "THIS CLASS: every character of its class\nTHIS CHARACTER: only the one that made it\nALL CHARACTERS: everyone\nClick to change.")
	local none = K.Font(p, 11, C.faint)
	none:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
	none:SetText("Add a spell, or click one in the list\nor on screen (layout mode) to edit it.")
	none:SetJustifyH("LEFT")

	local function px(v) return format("%dpx", v) end
	ed.size = K.Slider(p, "Size", 16, 192, 2, getS("size", 36), setS("size"), px, half)
	ed.size.fixedWidth = true
	p:Place(ed.size, 2, 4)
	ed.alpha = K.Slider(p, "Opacity", 0.1, 1, 0.05, getS("alpha", 1), setS("alpha"), fp, half)
	ed.alpha:SetPoint("LEFT", ed.size, "RIGHT", 12, 0)
	p.widgets[#p.widgets + 1] = ed.alpha
	ed.x = K.Slider(p, "X", -960, 960, 1, getS("x", 0), setS("x"), px, half)
	ed.x.fixedWidth = true
	p:Place(ed.x, 2, 4)
	ed.y = K.Slider(p, "Y", -540, 540, 1, getS("y", 0), setS("y"), px, half)
	ed.y:SetPoint("LEFT", ed.x, "RIGHT", 12, 0)
	p.widgets[#p.widgets + 1] = ed.y
	ed.border = K.Dropdown(p, "Importance border", { { "none", "None" }, { "red", "Red" }, { "orange", "Orange" }, { "green", "Green" } },
		getS("border", "none"), setS("border"), half)
	ed.border.fixedWidth = true
	p:Place(ed.border, 2, 4)
	ed.when = K.Dropdown(p, "Show", { { "always", "Always" }, { "combat", "In combat" }, { "nocombat", "Out of combat" } },
		getS("when", "always"), setS("when"), half)
	ed.when:SetPoint("LEFT", ed.border, "RIGHT", 12, 0)
	p.widgets[#p.widgets + 1] = ed.when
	-- invert: the opposite condition (ready / on the target / on me)
	ed.invert = p:Place(K.Toggle(p, "Invert", nil, function() local it = sel(); return it and it.invert or false end,
		function(v) local it = sel(); if it then it.invert = v; T.Changed(); p:Refresh() end end), 2, 6)
	-- kind-specific widgets, stacked under the invert toggle in OnRefresh
	local showOpts = { { "cd", "While on cooldown" }, { "always", "Always (dim on cooldown)" } }
	ed.show = K.Dropdown(p, "Cooldown icon shows", showOpts, getS("show", "cd"), setS("show"), p.colW)
	ed.warn = K.Slider(p, "Also show when less than", 0, 60, 1, getS("warn", 0), setS("warn"),
		function(v) return v == 0 and "only when it is gone" or format("%ds left", v) end, p.colW)
	ed.target = K.Dropdown(p, "On which target", { { "enemy", "Enemies" }, { "friend", "Friends" }, { "any", "Any" } },
		getS("targetType", "enemy"), setS("targetType"), p.colW)
	ed.hand = K.Dropdown(p, "Which weapon", { { "main", "Main hand" }, { "off", "Off hand" }, { "either", "Either hand" } },
		getS("hand", "main"), setS("hand"), p.colW)
	-- the aura to look for when its name differs from the spell's
	ed.aura = CreateFrame("Frame", nil, p)
	ed.aura:SetSize(p.colW, 42)
	ed.aura.t = K.Font(ed.aura, 12, C.text)
	ed.aura.t:SetPoint("TOPLEFT")
	ed.aura.t:SetText("Look for this buff instead (name or ID)")
	ed.aura.box = K.EditBox(ed.aura, p.colW, 22)
	ed.aura.box:SetPoint("TOPLEFT", 0, -18)
	local ae = ed.aura.box.edit
	local function saveAura(self)
		local it = sel()
		if not it then return end
		local v = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		-- "Waffenzunge (319778)" from the suggestions, a plain name, or an ID
		if it.kind == "weapon" then
			it.aura, it.auraId = v ~= "" and v or nil, nil -- text to find on the weapon's tooltip
			T.Changed()
			return
		end
		local id = T.Lib.IdIn(v)
		local name = v:match("^(.-)%s*%(%d+%)%s*$") or (not tonumber(v) and v ~= "" and v) or nil
		it.aura, it.auraId = name ~= "" and name or nil, id
		T.Changed()
	end
	ae:SetScript("OnEnterPressed", function(self) saveAura(self); self:ClearFocus() end)
	ae:SetScript("OnEditFocusLost", function(self) saveAura(self); ed.aura.box.border:SetColor(unpack(C.line2)) end)
	-- suggestions: buffs and debuffs first (on you, on your target, seen), then spells
	K.Suggest(ed.aura.box, function(t) return T.Lib.Search(t, { auras = true }) end, function() saveAura(ae) end, T.Lib.Deep)
	-- a weapon icon's field is free text from the weapon's tooltip: no spell suggestions
	ed.aura.box.suggest.disabled = function() local it = sel(); return it and it.kind == "weapon" end
	ed.hits = K.Toggle(p, "Count charges on melee hits", nil,
		function() local it = sel(); return it and T.CountsHits(it) or false end,
		function(v) local it = sel(); if it then it.countHits = v; T.Changed() end end, p.colW)
	ed.source = K.Toggle(p, "Count it from anyone (not only yours)", nil,
		function() local it = sel(); return it and it.anySource or false end,
		function(v) local it = sel(); if it then it.anySource = v; T.Changed() end end, p.colW)
	for _, w in ipairs({ ed.show, ed.warn, ed.target, ed.hand, ed.source, ed.hits }) do p.widgets[#p.widgets + 1] = w end
	ed.dup = K.Button(p, "Duplicate", 90, 22, function() if sel() then T.Duplicate(sel().id); p:Refresh() end end)
	ed.rem = K.Button(p, "Remove", 90, 22, function() if sel() then T.Remove(sel().id); p:Refresh() end end)
	ed.rem:SetPoint("LEFT", ed.dup, "RIGHT", 6, 0)
	p.editor = ed

	function p:OnRefresh()
		local it = sel()
		for _, w in pairs(ed) do w:SetShown(it ~= nil) end
		none:SetShown(it == nil)
		title:SetShown(it ~= nil); sub:SetShown(it ~= nil)
		if it then
			title:SetText(it.name or T.SpellName(it.spell) or ("#" .. it.spell))
			title:SetTextColor(K.Accent())
			sub:SetText(T.LabelFor(it) .. format("  ·  SPELL %d", it.spell))
			local scope = it.scope or "class"
			-- the class in your client's language when it has the table, else SITREP's name
			local loc = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and it.class and LOCALIZED_CLASS_NAMES_MALE[it.class]
			local cls = it.class and (type(loc) == "string" and loc or ns.Data.NAME[it.class] or it.class)
			ed.scope.label:SetText(scope == "class" and cls and ("ONLY " .. cls:upper()) or T.SCOPE_LABEL[scope])
			local KIND_INV = { cd = "Invert: show while NOT on cooldown", target = "Invert: show while NOT on the target",
				self = "Invert: show while NOT on me", weapon = "Invert: show while NOT on the weapon" }
			ed.invert.label:SetText(KIND_INV[it.kind])
			showOpts[1][2] = it.invert and "While NOT on cooldown" or "While on cooldown"
			ed.show:Refresh()
			-- what this kind needs, top to bottom
			local stack = {}
			if it.kind == "cd" then stack[#stack + 1] = ed.show end
			if it.kind ~= "cd" and it.invert then stack[#stack + 1] = ed.warn end -- early warning belongs to "NOT on"
			if it.kind == "target" then stack[#stack + 1] = ed.target end
			if it.kind == "weapon" then
				stack[#stack + 1] = ed.hand
				stack[#stack + 1] = ed.aura
			end
			ed.aura.t:SetText(it.kind == "weapon" and "Only if its tooltip line says (optional)" or "Look for this buff instead (name or ID)")
			if it.kind == "target" or it.kind == "self" then
				stack[#stack + 1] = ed.aura
				stack[#stack + 1] = ed.source
			end
			if it.kind == "self" then stack[#stack + 1] = ed.hits end
			stack[#stack + 1] = ed.dup
			for _, w in ipairs({ ed.show, ed.warn, ed.target, ed.hand, ed.aura, ed.source, ed.hits }) do w:Hide() end
			local prev = ed.invert
			for _, w in ipairs(stack) do
				w:ClearAllPoints()
				w:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, w == ed.dup and -8 or -4)
				w:Show()
				prev = w
			end
			if not ae:HasFocus() then
				ae:SetText(it.aura and it.auraId and format("%s (%d)", it.aura, it.auraId) or it.aura or (it.auraId and tostring(it.auraId)) or "")
			end
		end
		list:Refresh()
		local m = T.mirror
		mnote:SetText(ns.P.trackers.mirror and m.note or "off: the list is gone after a restart (or use Export profile in Intel Log)")
	end
	p.list, p.listHead = list, lh
	return p
end

Cfg.AddPage(140, "trackers", "Trackers", buildTrackers)
