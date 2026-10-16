-- SITREP · /sitrep perf: how much SITREP costs
-- Measures for a while (default 60 s): every bus handler (by event and the file
-- that registered it) and every loop wrapped in ns.Timed (Core.lua), plus the frame
-- rate, time in combat, plates and contacts seen, and SITREP's memory. Written to the
-- report "perf" (on /reload); a one-line verdict goes to the chat. Meant for busy
-- places (a battleground with 40 plates), but works anywhere.
--   /sitrep perf [seconds]   /sitrep perf stop
-- Each line is that part's own time: a handler that sets off others (the sensor
-- tick fires the picture, the picture the allies) does not include theirs, so the
-- lines add up to the total.

local ADDON, ns = ...
local read = ns.read
local format, max, min, floor = string.format, math.max, math.min, math.floor

local PF = {}
ns.Perf = PF

-- per frame, what SITREP may cost: under 0.5 ms fine, under 1.5 ms noticeable in a
-- crowd, above that too much
local GOOD, OK = 0.5, 1.5

local function memKB()
	if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
	return GetAddOnMemoryUsage and read(GetAddOnMemoryUsage, ADDON) or nil
end

local watch = CreateFrame("Frame")
watch:Hide()
watch:SetScript("OnUpdate", function(_, e)
	local r = PF.run
	if not r then watch:Hide() return end
	r.frames = r.frames + 1
	local fps = read(GetFramerate)
	if fps then
		r.fpsSum, r.fpsN = r.fpsSum + fps, r.fpsN + 1
		r.fpsMin = r.fpsMin and min(r.fpsMin, fps) or fps
	end
	if InCombatLockdown() then r.combat = r.combat + e end
	local plates = 0
	for _ in pairs(ns.Plates and ns.Plates.Current() or {}) do plates = plates + 1 end
	r.plates = max(r.plates, plates)
	local contacts = 0
	for _ in pairs(ns.Sensors and ns.Sensors.contacts or {}) do contacts = contacts + 1 end
	r.contacts = max(r.contacts, contacts)
	if GetTime() >= r.stopAt then PF.Stop() end
end)

function PF.Start(seconds)
	seconds = tonumber(seconds) or 60
	seconds = max(5, min(600, seconds))
	ns.perf = {}
	if ns.Plates and ns.Plates.stats then
		local st = ns.Plates.stats
		st.drawn, st.deferred, st.maxLate = 0, 0, 0
	end
	PF.run = { t0 = GetTime(), stopAt = GetTime() + seconds, frames = 0, fpsSum = 0, fpsN = 0, combat = 0,
		plates = 0, contacts = 0, mem0 = memKB() }
	watch:Show()
	ns.print("measuring what SITREP costs for %d s (/sitrep perf stop ends it early) ...", seconds)
end

-- The verdict for a cost per frame.
function PF.Verdict(msPerFrame)
	if msPerFrame < GOOD then return "fine" end
	if msPerFrame < OK then return "noticeable in a crowd" end
	return "too much"
end

function PF.Stop()
	local r, data = PF.run, ns.perf
	if not r then ns.print("no measurement running (/sitrep perf [seconds])") return end
	PF.run, ns.perf = nil, nil
	watch:Hide()
	local secs = max(0.001, GetTime() - r.t0)
	local list, total, garbage = {}, 0, 0
	for label, d in pairs(data or {}) do
		list[#list + 1] = { label = label, n = d.n, ms = d.ms, max = d.max, kb = d.kb or 0 }
		total, garbage = total + d.ms, garbage + (d.kb or 0)
	end
	table.sort(list, function(a, b) return a.ms > b.ms end)
	local perSec = total / secs
	local perFrame = r.frames > 0 and total / r.frames or 0
	local fps = r.fpsN > 0 and r.fpsSum / r.fpsN or nil
	local mem1 = memKB()
	PF.last = { perSec = perSec, perFrame = perFrame, verdict = PF.Verdict(perFrame) }
	ns.Capture("perf", function()
		ns.print("measured %.0f s: %d frames, %s fps on average (lowest %s), %.0f s in combat, up to %d plates and %d contacts",
			secs, r.frames, fps and format("%.0f", fps) or "?", r.fpsMin and format("%.0f", r.fpsMin) or "?", r.combat, r.plates, r.contacts)
		ns.print("SITREP: %.2f ms per second, %.3f ms per frame: %s", perSec, perFrame, PF.last.verdict)
		if r.mem0 and mem1 then ns.print("memory: %.0f KB at the start, %.0f KB at the end", r.mem0, mem1) end
		ns.print("garbage made: about %.0f KB per second (the collector clears it, at its own cost)", garbage / secs)
		local pst = ns.Plates and ns.Plates.stats
		if pst then
			ns.print("plates: %.1f redrawn per second, %.1f per second left for a later tick (over the budget), longest gap between two redraws %.1f s",
				pst.drawn / secs, pst.deferred / secs, pst.maxLate)
		end
		ns.print("the most expensive (calls, total ms, ms per second, average ms, longest ms, KB per second):")
		for i = 1, min(25, #list) do
			local e = list[i]
			ns.print("  %-44s %6d %9.2f %7.3f %7.4f %7.3f %7.1f", e.label, e.n, e.ms, e.ms / secs, e.ms / max(1, e.n), e.max, e.kb / secs)
		end
	end, true)
	local top = list[1] and list[1].label or "-"
	ns.print("SITREP costs %.3f ms per frame (%s); most: %s. Details: /reload, report perf.", perFrame, PF.last.verdict, top)
end
