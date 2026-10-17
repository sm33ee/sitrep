-- A crowded town in the emulator: what each part of SITREP costs per tick, and the
-- garbage it makes. Run from the repo root:  luajit tests/bench.lua [seconds]
-- The emulator's calls cost differently from the client's: compare parts and
-- versions with each other, not with the game's numbers.
package.path = "tests/?.lua;" .. package.path
local W = require("wow_mock")
local ns = {}
for line in io.lines("SITREP/SITREP.toc") do
	if line ~= "" and not line:match("^##") then assert(loadfile("SITREP/" .. line:gsub("\\", "/")))("SITREP", ns) end
end
local S = W.scenario
S.me = { x = 0, y = 0, facing = 0, inst = 1 }
S.units.player = { name = "Ardan", guid = "Player-1-0001", class = "DRUID", level = 30, hostile = false, faction = "Alliance", hp = 4000, hpMax = 4000, dist = 0 }
W.Fire("ADDON_LOADED", "SITREP")
W.Fire("PLAYER_LOGIN")
W.Fire("SPELLS_CHANGED")
W.Update(0.25)

-- Blizzard-like plates (as in run.lua): a UnitFrame with a health bar, name, cast bar
local plates = {}
C_NamePlate.GetNamePlateForUnit = function(unit)
	local u = S.units[unit]
	if not (u and u.screenX) then return nil end
	local p = plates[unit]
	if not p then
		p = CreateFrame("Frame")
		local uf = CreateFrame("Frame", nil, p)
		uf.healthBar = CreateFrame("StatusBar", nil, uf)
		uf.name = uf:CreateFontString()
		uf.CastBarsContainer = CreateFrame("Frame", nil, uf)
		uf.CastBarsContainer.castBar = CreateFrame("StatusBar", nil, uf.CastBarsContainer)
		uf.healthBar.border = CreateFrame("Frame", nil, uf.healthBar)
		uf.LevelFrame = CreateFrame("Frame", nil, uf)
		p.UnitFrame = uf
		plates[unit] = p
	end
	return p
end
CompactUnitFrame_UpdateHealthColor = function(uf) uf.healthBar:SetStatusBarColor(0, 0, 1) end
ns.P.sensors.rate = 10 -- as in the game

-- 40 plates: 25 friendly players, 10 friendly NPCs, 5 enemy players
local classes = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
for i = 1, 40 do
	local u = { name = "Unit" .. i, level = 20 + i % 10, hp = 3000, hpMax = 3000, dist = 5 + (i * 7) % 50, screenX = 100 + i * 40 }
	if i <= 25 then
		u.guid, u.class, u.isPlayer, u.hostile, u.faction, u.reaction = "Player-1-" .. (1000 + i), classes[i % 8 + 1], true, false, "Alliance", 5
	elseif i <= 35 then
		u.guid, u.isPlayer, u.hostile, u.reaction = "Creature-0-1-0-1-" .. (68 + i), false, false, 5
	else
		u.guid, u.class, u.isPlayer, u.hostile, u.faction = "Player-2-" .. (2000 + i), classes[i % 8 + 1], true, true, "Horde"
	end
	S.units["nameplate" .. i] = u
	W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
end
S.units.target = S.units.nameplate3

local n = 0
for _ in pairs(ns.Plates.Current()) do n = n + 1 end
print("plates drawn: " .. n)
local secs = tonumber(arg and arg[1]) or 30
local FPS = 40
W.Update(1)
collectgarbage("collect")
ns.perf = {}
local t0, kb0 = os.clock(), collectgarbage("count")
for _ = 1, secs * FPS do W.Update(1 / FPS) end
local wall = (os.clock() - t0) * 1000
local list, total, garbage = {}, 0, 0
for label, d in pairs(ns.perf) do list[#list + 1] = { label, d }; total = total + d.ms; garbage = garbage + d.kb end
ns.perf = nil
table.sort(list, function(a, b) return a[2].ms > b[2].ms end)
print(string.format("%d s at %d fps, 40 plates: SITREP %.2f ms/s, %.3f ms per frame, garbage %.0f KB/s (emulator total %.0f ms)",
	secs, FPS, total / secs, total / (secs * FPS), garbage / secs, wall))
for i = 1, math.min(22, #list) do
	local l, d = list[i][1], list[i][2]
	print(string.format("  %-42s %6d %8.2f ms/s %7.4f avg %7.1f KB/s", l, d.n, d.ms / secs, d.ms / d.n, d.kb / secs))
end
