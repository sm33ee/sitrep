-- SITREP · Console pages: Intel Log

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local format, floor, max, log = string.format, math.floor, math.max, math.log
local Cfg = ns.Config
local kit = Cfg.kit
local newPage = kit.newPage

-- 11 INTEL LOG
---------------------------------------------------------------------------
local function buildLog()
	local p = newPage("Intel Log", "After-action reviews and where the enemy has been seen.")
	local list = CreateFrame("Frame", nil, p)
	list:SetHeight(8 * 20)
	list.rows = {}
	for i = 1, 8 do
		local r = CreateFrame("Frame", nil, list)
		r:SetHeight(18)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
		r:SetPoint("TOPRIGHT", 0, -(i - 1) * 20)
		r.bg = K.Tex(r, "BACKGROUND", C.raised)
		r.bg:SetAllPoints()
		r.bg:SetAlpha(i % 2 == 0 and 0.35 or 0.6)
		r.o = K.Font(r, 11, C.text, K.FONT, "")
		r.o:SetPoint("LEFT", 6, 0)
		r.o:SetWidth(44)
		r.o:SetJustifyH("LEFT")
		r.z = K.Font(r, 11, C.text)
		r.z:SetPoint("LEFT", 52, 0)
		r.z:SetWidth(170)
		r.z:SetJustifyH("LEFT")
		r.z:SetWordWrap(false)
		r.s = K.Font(r, 10, C.dim, K.FONT, "")
		r.s:SetPoint("RIGHT", -6, 0)
		list.rows[i] = r
	end
	function list:Refresh()
		local log = ns.db.log.engagements
		for i, r in ipairs(self.rows) do
			local e = log[i]
			if e then
				local col = e.outcome == "WIN" and { K.Accent() } or e.outcome == "LOSS" and { 1, 0.33, 0.33 } or { 1, 0.72, 0.2 }
				r.o:SetText(e.outcome)
				r.o:SetTextColor(col[1], col[2], col[3])
				local pred = e.p and format("pred %.0f%%", e.p * 100) or ""
				if e.kind == "duel" then
					r.z:SetText("|cff8a9492DUEL|r  vs " .. (e.opponent or "?"))
					r.s:SetText(format("%s  %.0fs  %s", ns.Data.NAME[e.oppClass] or "", e.dur or 0, pred))
				else
					r.z:SetText((e.sub and e.sub ~= "") and e.sub or e.zone or "?")
					local n = 0
					for _, k in pairs(e.comp or {}) do n = n + k end
					r.s:SetText(format("%d hostile  %.0fs  %s", n, e.dur or 0, pred))
				end
				r:Show()
			else
				r:Hide()
			end
		end
	end
	local lt = K.Font(p, 10, C.dim, K.FONT, "")
	lt:SetText("RECENT ENGAGEMENTS")
	p:Place(lt, 1, 6)
	p:Place(list, 1, 14)

	-- Duel record per opponent class: a 3 x 3 grid of W-L and win rate.
	local dt = K.Font(p, 10, C.dim, K.FONT, "")
	dt:SetText("DUEL RECORD BY OPPONENT CLASS")
	p:Place(dt, 1, 6)
	local duels = CreateFrame("Frame", nil, p)
	duels:SetHeight(3 * 22)
	duels.cells = {}
	for i, class in ipairs(ns.Data.CLASSES) do
		local cell = CreateFrame("Frame", nil, duels)
		cell:SetSize(p.colW / 3 - 3, 20)
		cell:SetPoint("TOPLEFT", ((i - 1) % 3) * (p.colW / 3), -floor((i - 1) / 3) * 22)
		cell.bg = K.Tex(cell, "BACKGROUND", C.raised)
		cell.bg:SetAllPoints()
		cell.bar = K.Tex(cell, "BACKGROUND", nil, 1)
		cell.bar:SetPoint("TOPLEFT"); cell.bar:SetPoint("BOTTOMLEFT")
		K.Paint(function(r, g, b) cell.bar:SetVertexColor(r, g, b, 0.22) end)
		cell.n = K.Font(cell, 11, C.text)
		cell.n:SetPoint("LEFT", 5, 0)
		cell.n:SetText(ns.Data.SHORT[class])
		cell.n:SetTextColor(ns.Data.ClassColor(class))
		cell.v = K.Font(cell, 11, C.text, K.FONT, "")
		cell.v:SetPoint("RIGHT", -5, 0)
		duels.cells[class] = cell
	end
	function duels:Refresh()
		local book = ns.db.log.duels
		for class, cell in pairs(self.cells) do
			local e = book[class]
			local n = e and (e.w + e.l) or 0
			if n > 0 then
				cell.v:SetText(format("%d-%d  %.0f%%", e.w, e.l, e.w / n * 100))
				cell.v:SetTextColor(unpack(C.text))
				cell.bar:SetWidth(max(1, cell:GetWidth() * e.w / n))
				cell.bar:Show()
			else
				cell.v:SetText("-")
				cell.v:SetTextColor(unpack(C.faint))
				cell.bar:Hide()
			end
		end
	end
	p:Place(duels, 1)

	local ht = K.Font(p, 10, C.dim, K.FONT, "")
	ht:SetText("CONTACT HEAT BY SUBZONE")
	p:Place(ht, 2, 6)
	local heat = CreateFrame("Frame", nil, p)
	heat:SetHeight(8 * 22)
	heat.rows = {}
	for i = 1, 8 do
		local r = CreateFrame("Frame", nil, heat)
		r:SetHeight(20)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
		r:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
		r.bar = K.Tex(r, "BACKGROUND")
		r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
		K.Paint(function(rr, g, b) r.bar:SetVertexColor(rr, g, b, 0.22) end)
		r.t = K.Font(r, 11, C.text)
		r.t:SetPoint("LEFT", 6, 0)
		r.t:SetWidth(200)
		r.t:SetJustifyH("LEFT")
		r.t:SetWordWrap(false)
		r.n = K.Font(r, 11, C.text, K.FONT, "")
		r.n:SetPoint("RIGHT", -6, 0)
		heat.rows[i] = r
	end
	function heat:Refresh()
		local arr = {}
		for k, v in pairs(ns.db.log.heat) do arr[#arr + 1] = { k, v } end
		table.sort(arr, function(a, b) return a[2] > b[2] end)
		local top = arr[1] and arr[1][2] or 1
		for i, r in ipairs(self.rows) do
			local e = arr[i]
			if e then
				r.t:SetText(e[1])
				r.n:SetText(e[2])
				r.bar:SetWidth(max(2, (p.colW) * e[2] / top))
				r:Show()
			else
				r:Hide()
			end
		end
	end
	p:Place(heat, 2, 14)

	local box = K.EditBox(p, p.colW, 60, true)
	box.fixedWidth = true
	local exp_ = K.Button(p, "Export profile", 110, 22, function()
		local s, err = ns.ExportProfile()
		box.edit:SetText(s or ("export failed: " .. tostring(err)))
		box.edit:HighlightText()
		box.edit:SetFocus()
	end)
	exp_.fixedWidth = true
	local imp = K.Button(p, "Import", 70, 22, function()
		local ok, err = ns.ImportProfile(box.edit:GetText())
		ns.print(ok and "profile imported." or ("import failed: " .. tostring(err)))
		if ok then Cfg.RefreshAll() end
	end)
	imp.fixedWidth = true
	local clr = K.Button(p, "Clear log", 80, 22, function()
		ns.db.log.engagements, ns.db.log.heat, ns.db.log.duels = {}, {}, {}
		p:Refresh()
	end)
	clr.fixedWidth = true
	p:Place(exp_, 2, 6)
	imp:SetPoint("LEFT", exp_, "RIGHT", 6, 0)
	clr:SetPoint("LEFT", imp, "RIGHT", 6, 0)
	p:Place(box, 2)
	return p
end

---------------------------------------------------------------------------

Cfg.AddPage(130, "log", "Intel Log", buildLog)
