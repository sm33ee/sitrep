-- SITREP · Menu
-- Blizzard's row of micro buttons (character, spellbook, talents, quest log,
-- social, map, game menu...) folded into one movable MENU button, which also
-- shows your latency. Click it: a list opens above it with every window the
-- client has, in the game's own words, each with its key binding, and Friends with
-- how many are online (also beside the MENU label, with a green dot). The list
-- entries are secure clicks on Blizzard's own buttons, and the list opens and
-- closes in the secure environment, so it works in combat too (an addon calling
-- those windows itself would be blocked there).
-- Blizzard's buttons stay where they are, invisible and click-through (ui.hideMicro;
-- not hidden: K.Fade).

local ADDON, ns = ...
local K = ns.Kit
local C = K.C
local read = ns.read
local format, floor = string.format, math.floor

local MM = {}
ns.MicroMenu = MM

-- { Blizzard's button, its name (global string), English fallback, key binding }
local ENTRIES = {
	{ "CharacterMicroButton", "CHARACTER_BUTTON", "Character", "TOGGLECHARACTER0" },
	{ "SpellbookMicroButton", "SPELLBOOK", "Spellbook", "TOGGLESPELLBOOK" },
	{ "TalentMicroButton", "TALENTS", "Talents", "TOGGLETALENTS" },
	{ "PlayerSpellsMicroButton", "TALENTS", "Talents", "TOGGLETALENTS" },
	{ "ProfessionMicroButton", "PROFESSIONS_BUTTON", "Professions", "TOGGLEPROFESSIONBOOK" },
	{ "AchievementMicroButton", "ACHIEVEMENT_BUTTON", "Achievements", "TOGGLEACHIEVEMENT" },
	{ "QuestLogMicroButton", "QUESTLOG_BUTTON", "Quest Log", "TOGGLEQUESTLOG" },
	{ "GuildMicroButton", "GUILD_AND_COMMUNITIES", "Guild & Communities", "TOGGLEGUILDTAB" },
	{ "SocialsMicroButton", "SOCIAL_BUTTON", "Social", "TOGGLESOCIAL" },
	{ "LFDMicroButton", "DUNGEONS_BUTTON", "Group Finder", "TOGGLEGROUPFINDER" },
	{ "LFGMicroButton", "LFG_BUTTON", "Looking for Group", "TOGGLELFG" },
	{ "PVPMicroButton", "PLAYER_V_PLAYER", "Player vs. Player", "TOGGLECHARACTER4" },
	{ "CollectionsMicroButton", "COLLECTIONS", "Collections", "TOGGLECOLLECTIONS" },
	{ "EJMicroButton", "ENCOUNTER_JOURNAL", "Adventure Guide", "TOGGLEENCOUNTERJOURNAL" },
	{ "WorldMapMicroButton", "WORLDMAP_BUTTON", "World Map", "TOGGLEWORLDMAP" },
	{ "MainMenuMicroButton", "MAINMENU_BUTTON", "Game Menu", "TOGGLEGAMEMENU" },
	{ "HelpMicroButton", "HELP_BUTTON", "Help", nil },
}
local CONTAINERS = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" }
MM.NAMES = { entries = ENTRIES, containers = CONTAINERS }
local ROW_H, LIST_W = 20, 190

local function P() return ns.P and ns.P.ui end

-- Friends: clients without a social micro button open the friends list from a
-- button next to the chat (hidden with the quiet chat). The list gets an entry of
-- its own then, clicking this stand-in (the friends list is not a secure window).
local friendsProxy = CreateFrame("Button", "SITREP_FriendsProxy", UIParent)
friendsProxy:Hide()
friendsProxy:SetScript("OnClick", function()
	if ToggleFriendsFrame then pcall(ToggleFriendsFrame, 1) end
end)
MM.friendsProxy = friendsProxy

-- The micro buttons this client has, in order (and Friends, see above). An entry
-- with friends = true shows how many friends are online.
function MM.Entries()
	local list, social = {}, false
	-- a button Blizzard itself keeps hidden on this client is not offered. Forever has
	-- both TalentMicroButton and PlayerSpellsMicroButton; since mid-October 2026 the
	-- newer one opens the spellbook (reported), the older one the talent trees: the
	-- older one is "Talents", the newer one only where there is no older one. The
	-- spellbook is just "Spellbook" (the client's own name for its button says
	-- spellbook and professions; professions have their own entry)
	local older = _G.TalentMicroButton
	local hasOlder = type(older) == "table" and read(older.IsShown, older) ~= false
	for _, e in ipairs(ENTRIES) do
		local b = _G[e[1]]
		local offered = type(b) == "table" and read(b.IsShown, b) ~= false and not (hasOlder and e[1] == "PlayerSpellsMicroButton")
		if offered then
			local label = _G[e[2]]
			local isSocial = e[4] == "TOGGLESOCIAL"
			social = social or isSocial
			list[#list + 1] = { button = b, label = type(label) == "string" and label or e[3], binding = e[4], friends = isSocial }
		end
	end
	if not social then
		local at = #list + 1
		for i, e in ipairs(list) do if e.binding == "TOGGLEWORLDMAP" then at = i break end end
		table.insert(list, at, { button = friendsProxy, label = type(_G.FRIENDS) == "string" and _G.FRIENDS or "Friends",
			binding = "TOGGLESOCIAL", friends = true, proxy = true })
	end
	return list
end

-- Friends online: in the game, on Battle.net, and their sum.
function MM.FriendsOnline()
	local wow
	if C_FriendList and C_FriendList.GetNumOnlineFriends then wow = read(C_FriendList.GetNumOnlineFriends) end
	if not wow and GetNumFriends then local _, on = read(GetNumFriends) wow = on end
	local _, bn = read(BNGetNumFriends)
	wow, bn = wow or 0, bn or 0
	return wow + bn, wow, bn
end

-- Secure clicks fire on key down or key up, as the game's setting says; a click
-- registered for both would open and close the window at once.
local function clickEvent()
	return GetCVar and GetCVar("ActionButtonUseKeyDown") == "1" and "AnyDown" or "AnyUp"
end

local function latency()
	local _, _, home, world = read(GetNetStats)
	local ms = world and world > 0 and world or home
	return ms and floor(ms) or nil
end
MM.Latency = latency

local function latencyColor(ms)
	if not ms then return "8a9493" end
	if ms < 120 then return "5cff8d" elseif ms < 250 then return "ffa040" end
	return "ff5555"
end

local function build()
	if MM.button then return end
	-- the list: a secure frame (it holds secure buttons), opened by the MENU button
	local list = CreateFrame("Frame", "SITREP_MenuList", UIParent, "SecureFrameTemplate")
	list:SetFrameStrata("DIALOG")
	list:SetWidth(LIST_W)
	list.bg = K.Backdrop(list, C.panel, 12)
	list.bg:SetAllPoints()
	K.Border(list, C.line2, nil, 12)
	K.Brackets(list, 8, 2)
	list:Hide()
	MM.list = list
	list.rows = {}
	for i, e in ipairs(MM.Entries()) do
		local r = CreateFrame("Button", "SITREP_MenuEntry" .. i, list, "SecureActionButtonTemplate")
		r:SetSize(LIST_W - 8, ROW_H)
		r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
		if e.binding == "TOGGLEGAMEMENU" then
			-- Blizzard's game-menu button acts on the release of the mouse button only
			r:SetAttribute("useOnKeyDown", false)
			r:RegisterForClicks("AnyUp")
		else
			r:RegisterForClicks(clickEvent())
		end
		r:SetAttribute("type", "click")
		r:SetAttribute("clickbutton", e.button)
		r.hl = K.Tex(r, "BACKGROUND", C.hover)
		r.hl:SetAllPoints()
		r.hl:SetAlpha(0)
		r.label = K.Font(r, 11, C.text, nil, "")
		r.label:SetPoint("LEFT", 8, 0)
		r.label:SetText(e.label)
		r.key = K.Font(r, 10, C.faint, K.FONT, "")
		r.key:SetPoint("RIGHT", -6, 0)
		r.binding, r.friends = e.binding, e.friends
		r:HookScript("OnEnter", function(self) self.hl:SetAlpha(1) end)
		r:HookScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
		-- close the list after the click (in the secure environment: works in combat).
		-- A wrap's post-body runs only when its pre-body returns a message (until
		-- 4.11.5 the pre-body returned nothing: the list stayed open)
		if SecureHandlerWrapScript then
			SecureHandlerWrapScript(r, "OnClick", list, [=[ return button, "close" ]=], [=[ owner:Hide() ]=])
		end
		list.rows[i] = r
	end
	list:SetHeight(#list.rows * ROW_H + 8)

	-- the MENU button: opens and closes the list (secure snippet)
	local b = CreateFrame("Button", "SITREP_MenuButton", UIParent, "SecureHandlerClickTemplate")
	b:SetSize(108, 22)
	b:SetFrameStrata("MEDIUM")
	b.bg = K.Backdrop(b, C.bg, 8, { mood = true })
	b.bg:SetAllPoints()
	K.Border(b, C.line)
	K.Brackets(b, 6, 2)
	b.text = K.Font(b, 11, C.text, K.FONT, "")
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetText("MENU")
	b.ms = K.Font(b, 10, C.dim, K.FONT, "")
	b.ms:SetPoint("RIGHT", -7, 0)
	-- friends online: a green dot and how many
	b.friends = K.Font(b, 10, C.text, K.FONT, "")
	b.friends:SetPoint("LEFT", b.text, "RIGHT", 14, 0)
	b.dot = K.Tex(b, "OVERLAY", { 0.36, 1, 0.55, 1 })
	b.dot:SetSize(5, 5)
	b.dot:SetPoint("RIGHT", b.friends, "LEFT", -3, 0)
	b.unlock = K.Tex(b, "OVERLAY", { 1, 1, 1, 0.04 })
	b.unlock:SetAllPoints()
	b:RegisterForClicks("LeftButtonUp")
	b:SetFrameRef("list", list)
	b:SetAttribute("_onclick", [=[
		local list = self:GetFrameRef("list")
		if list:IsShown() then list:Hide() else list:Show() end
	]=])
	list:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 4)
	b:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Menu", 1, 1, 1)
		local _, _, home, world = read(GetNetStats)
		if home then GameTooltip:AddLine(format("Latency: home %d ms, world %d ms", home, world or home), 0.75, 0.8, 0.78) end
		local fps = read(GetFramerate)
		if fps then GameTooltip:AddLine(format("Frame rate: %.0f fps", fps), 0.75, 0.8, 0.78) end
		local all, wow, bn = MM.FriendsOnline()
		GameTooltip:AddLine(format("Friends online: %d  (in the game %d, Battle.net %d)", all, wow, bn), 0.36, 1, 0.55)
		GameTooltip:AddLine("Click: character, spellbook, talents, quest log, map and more.", 0.52, 0.58, 0.57, true)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	K.Movable(b, "menu", { "BOTTOMRIGHT", "BOTTOMRIGHT", -370, 8 })
	-- the latency, every 5 s
	local acc = 5
	b:SetScript("OnUpdate", ns.Timed("menu: latency (b)", function(self, e)
		acc = acc + e
		if acc < 5 then return end
		acc = 0
		local ms = latency()
		self.ms:SetText(ms and format("|cff%s%d MS|r", latencyColor(ms), ms) or "")
	end))
	MM.button = b
end

-- Key bindings change: the list shows them as they are (and the friends row how
-- many are online).
function MM.RefreshKeys()
	local online = MM.FriendsOnline()
	for _, r in ipairs(MM.list and MM.list.rows or {}) do
		local key = r.binding and read(GetBindingKey, r.binding)
		key = key and (GetBindingText and read(GetBindingText, key, "KEY_") or key) or ""
		if r.friends then
			r.key:SetText(format("|cff5cff8d%d online|r%s", online, key ~= "" and ("  " .. key) or ""))
		else
			r.key:SetText(key)
		end
	end
	if MM.button then
		MM.button.friends:SetText(tostring(online))
		MM.button.dot:SetShown(online > 0)
		MM.button.friends:SetTextColor(online > 0 and 0.36 or C.dim[1], online > 0 and 1 or C.dim[2], online > 0 and 0.55 or C.dim[3])
	end
end

function MM.Apply()
	if InCombatLockdown() then MM.pending = true return end
	build()
	local on = P().menu and ns.P.enabled and not ns.hudHidden and true or false
	local b = MM.button
	b:SetShown(on)
	if not on then MM.list:Hide() end
	b:RestorePosition()
	local scale = ns.P.hud.scale * (ns.P.hud.frameScale.menu or 1)
	b:SetScale(scale)
	MM.list:SetScale(scale)
	b:SetAlpha(K.Opacity("menu"))
	K.Background(b.bg, "menu")
	b.unlock:SetShown(not ns.P.hud.locked)
	local hide = on and P().hideMicro or false
	-- faded, not hidden: hiding Blizzard's micro buttons from here taints them (K.Fade)
	for _, e in ipairs(MM.Entries()) do if not e.proxy then K.Fade(e.button, hide) end end
	for _, n in ipairs(CONTAINERS) do
		local f = _G[n]
		-- (the classic bag bar shares a container with the micro buttons: keep that one)
		if type(f) == "table" and n ~= "MicroButtonAndBagsBar" then K.Fade(f, hide) end
	end
	MM.RefreshKeys()
end

ns.On("SR_LOGIN", function()
	MM.Apply()
	-- ask the server for the friends list (the count comes with FRIENDLIST_UPDATE)
	if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end)
ns.On("UPDATE_BINDINGS", function() MM.RefreshKeys() end)
for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED" }) do
	ns.On(e, function() MM.RefreshKeys() end)
end
ns.On("PLAYER_REGEN_ENABLED", function() if MM.pending then MM.pending = false; MM.Apply() end end)
ns.On("SR_CONFIG", function(_, key)
	if key == "*" or key == "enabled" or key == "ui.menu" or key == "ui.hideMicro" or key:sub(1, 4) == "hud." then MM.Apply() end
end)
