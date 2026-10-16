-- SITREP · The preset layout from a saved profile
-- Prints ns.PRESET (Core.lua) made from a SavedVariables file: every setting of its
-- profile that differs from the bare defaults (ns.Defaults), positions rounded to a
-- tenth. Left out: what is the player's own rather than a layout (their trackers,
-- what SITREP learned of their play, their message template) and editor states
-- (SKIP). Run from the repo root:
--   luajit tools/preset_from_saved.lua "<WTF>/Account/<account>/SavedVariables/SITREP.lua"
-- and put what it prints in place of ns.PRESET in SITREP/Core.lua.

package.path = "tests/?.lua;" .. package.path
local W = require("wow_mock")
local ns = {}
for line in io.lines("SITREP/SITREP.toc") do
	if line ~= "" and not line:match("^##") then
		local chunk = assert(loadfile("SITREP/" .. line:gsub("\\", "/")))
		chunk("SITREP", ns)
	end
end

-- the saved file, in a table of its own (not the emulator's SITREP_DB)
local env = {}
local saved = assert(loadfile(assert(arg[1], "the SavedVariables file, please"), "t", env))
if setfenv then setfenv(saved, env) end
saved()
local profile = assert(env.SITREP_DB and env.SITREP_DB.profile, "no profile in that file")
local defaults = ns.Defaults()

local SKIP = { trackers = true, engage = true, comms = true, ["ui.barEdit"] = true, ["ui.layoutEdit"] = true,
	["quests.mapBrush"] = true, ["quests.mapTrails"] = true }
local function round(v) return math.floor(v * 10 + 0.5) / 10 end
local function same(a, b)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-9 end
	return a == b
end
-- what of `p` differs from `d` (only keys the defaults know: anything else is pruned)
local function diff(p, d, path)
	local out, any = {}, false
	for k, dv in pairs(d) do
		local pv = p[k]
		local here = path and (path .. "." .. tostring(k)) or tostring(k)
		if pv ~= nil and not SKIP[here] then
			if type(dv) == "table" and type(pv) == "table" then
				local sub = diff(pv, dv, here)
				if sub then out[k], any = sub, true end
			elseif not same(pv, dv) then
				out[k], any = pv, true
			end
		end
	end
	-- (positions: a table the defaults leave empty, every entry is a difference; but
	-- not a bar's place SITREP noted itself, never moved: TOPLEFT of the screen's
	-- BOTTOMLEFT, as Blizzard laid it out)
	if next(d) == nil then
		for k, pv in pairs(p) do
			local auto = type(pv) == "table" and pv[1] == "TOPLEFT" and pv[2] == "BOTTOMLEFT"
			if not auto then out[k], any = pv, true end
		end
	end
	return any and out or nil
end

local function literal(v, indent)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) == "number" then return tostring(v == math.floor(v) and v or round(v)) end
	if type(v) ~= "table" then return tostring(v) end
	-- a position: { point, relativePoint, x, y } on one line
	if #v > 0 then
		local parts = {}
		for i, x in ipairs(v) do parts[i] = literal(x, indent) end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local pad = string.rep("\t", indent + 1)
	local lines = {}
	for _, k in ipairs(keys) do
		local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. literal(k, 0) .. "]")
		lines[#lines + 1] = pad .. key .. " = " .. literal(v[k], indent + 1) .. ","
	end
	return "{\n" .. table.concat(lines, "\n") .. "\n" .. string.rep("\t", indent) .. "}"
end

io.write("ns.PRESET = ", literal(diff(profile, defaults) or {}, 0), "\n")
