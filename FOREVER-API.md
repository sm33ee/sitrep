# World of Warcraft: Forever, as an addon sees it

What the client gives addons and where it stops, as found while building SITREP.
Interface 16001: a modern (Midnight-era) client running a classic-style PvP realm,
with Midnight's addon restrictions switched on.

How sure each fact is:
- **measured**: seen in the live client or its beta, mostly through a SITREP probe
  (the commands at the end) or the blocked-action log;
- **wiki**: from warcraft.wiki.gg, not contradicted so far;
- **unconfirmed**: assumed from other clients; SITREP checks before it relies on it.

How SITREP works around each limit is in `DEVELOPING.md` (section "Working within
the client"). The test emulator (`tests/wow_mock.lua`) enforces many of these rules
as code.

---

## 1. Secret values

Many values turn "secret" in combat: health, power, aura data, sometimes names and
spell names, unit comparisons, cast times. (measured)

- A secret throws when addon code compares it (`==`, `<`), tests it (`if x`,
  `x and y`, `x or y`), does arithmetic with it or joins it into a string.
- It may be handed to widgets as it is: `StatusBar:SetValue/SetMinMaxValues`,
  `FontString:SetText`, `Texture:SetTexture`, `C_CurveUtil.EvaluateColorFromBoolean`
  (a secret yes/no turned into a colour or alpha), `UnitHealthPercent(unit, true,
  curve)`, `StatusBar:SetTimerDuration`.
- `FontString:SetFormattedText` with secrets: works in places, not relied on.
- **Friendly players' health on their plates is secret out of combat too**
  (measured, zenprobe 4.0.9: five strangers in town, all `secret / secret`).
  Whether one is at full health can only be shown, not known. A curve on
  `UnitHealthPercent` could hide a full bar, but its scale is unknown (below);
  friendly zen therefore decides by who it is (enemy, group, target), not by health.
- Out of combat almost everything is plain again.
- `UnitIsUnit` (who targets whom) stayed plain in a measured open-world fight
  (112 plain, 0 secret); it may be secret elsewhere.
- Your own mana read as secret at times (shift probe: `mana nil / 662`).
- **Health in combat through a curve**: `UnitHealthPercent(unit, usePredicted,
  curve)` evaluates a colour curve on the health percent inside the client; the
  kill window paints its border with the result (secret, shown as it is). Forever
  has it and `C_CurveUtil.CreateColorCurve` (measured, ideaprobe); that the percent
  runs 0 to 1: unconfirmed, and not measurable (`UnitHealthPercent("player")` is
  secret too, zenprobe 4.0.12). Friendly zen behaved as if it ran 0 to 100 (bars
  shown only before the health was known, gone at the first update, hurt or not).
  SITREP's health curves (unit frame colours, kill window) have their steps on both
  scales (SCALE_BOTH).

## 2. Protected actions, taint and secure frames

**Protected in combat**
- `CheckInteractDistance` and `C_Item.IsItemInRange`: in combat only about
  enemies; asked about anyone else it is a blocked action ("Interface action failed
  because of an AddOn"). (wiki: retail 10.2.0, hotfix 2023-12-11; measured: 16
  blocked calls before SITREP respected it, 0 after)
- Nameplate settings (CVars) cannot be set in combat. (unconfirmed, respected)
- Secure frames (action buttons, secure buttons, frames holding or anchoring them)
  may not be shown, hidden, moved, resized or given new attributes by addon code in
  combat. (measured)
- In combat no addon can choose what a click or a key press targets. (by design)

**A frame that a secure frame is anchored to becomes protected itself.** (measured:
a status bar with a secure button anchored to it got "BLOCKED StatusBar:Show()" on
every cast)

**Taint through Blizzard's own frames** (measured)
- Opening the bags from addon code (`ToggleAllBags`) taints the bag windows. The
  game then refuses using an item from them, in and out of combat ("SITREP was
  blocked", `UseContainerItem`; 14x `SetPassThroughButtons` blocked).
- Hiding Blizzard frames from addon code runs their `OnHide` scripts under the
  addon's name: frames the game's secure code relies on (bag bar, micro buttons)
  carry that taint. Changing alpha or mouse runs no script.
- A secure click on Blizzard's own button (`type = "click"`) runs its code
  untainted: the clean way to open bags, spellbook, talents and so on, in combat too.

**Secure clicks**
- Secure action buttons fire on key down or key up as the CVar
  `ActionButtonUseKeyDown` says (1 on Forever). Registering both fires twice: a
  toggle opens and closes at once.
- Blizzard's game-menu button reacts on release only (unconfirmed: fixed by an entry
  that acts on release; awaiting the player's test).
- Restricted snippets (`SecureHandlerClickTemplate`, `SecureHandlerWrapScript`)
  can show and hide secure frames in combat.

**"AllowedWhenUntainted"** on a function in the wiki concerns secret *arguments*
(only Blizzard's code may pass secrets); plain calls from addons are not affected.

- **Secure buttons in combat**: alpha and their own child textures may change; Show,
  Hide, moving and attributes may not. A visibility state driver
  (`RegisterStateDriver(f, "visibility", "[combat] show; hide")`) lets the game show
  them in combat (the emergency items). (the first: measured with the quest item
  icons; the driver: standard, unconfirmed on Forever)

## 3. Not available to addons

- **The combat log** (`C_CombatLog.IsCombatLogRestricted` is true). No "spell X hit
  you", no enemy cooldowns from it. (measured)
- **Where an enemy is**: nameplates are restricted regions; their screen position
  cannot be measured ("Can't measure restricted regions"). No direction to any enemy.
  (measured)
- **Auras in combat**: every list and lookup refused, the `UNIT_AURA` payload
  secret, instance probes error. Blizzard's own buff bar icons stay readable until
  the bar redraws. (measured)
- **Nameplate size**: no size CVar on Forever (`nameplateGlobalScale`,
  `NamePlateHorizontalScale`, `NamePlateVerticalScale` all nil; the client does not
  list its CVars). The game scales the plate frame itself. (measured)
- **The plate's click area** cannot be changed. (by design)
- **Other players' quest progress**: only what addons tell each other. (by design)

## 4. Units, distances and positions

- **Player names**: Forever's players have two names ("Aldric Hale"), unique
  together (told by the player, 2026-10-14). Names may hold a space: parse them with
  `(.+)`, never `%S+`; compare them with `Targeting.SameName`.
  `/targetexact Aldric Hale` targets that player; a wrong second name
  (`/targetexact Aldric Foo`) targets no one. (measured, 2026-10-14) Whether every
  other API (`UnitName`, chat senders) gives both names: unmeasured.

- **Spell range**: `C_Spell.IsSpellInRange` with harmful and helpful spellbook
  spells gives brackets; melee spells answer "in range" at any distance. (measured)
- **Interact distances**: `CheckInteractDistance` index 3 (duel) answers at about
  10 yd, 4 (follow) at 28 yd; the wiki says duel 7, trade 8. All five indices answered
  true at melee range. (measured, rangeprobe)
- **Item range** (`C_Item.IsItemInRange`): only items of this era are known; items of
  later expansions have no name. Harm items answer nil for friends; Zorbin's
  Ultra-Shrinker (18904, 35 yd) answered for a friend; known on Forever: 10645 (20 yd),
  835 and 7734 (30 yd), 18904 (35 yd). (measured)
- **`UnitPosition`**: your own position in the open world (x = north axis, y = west
  axis) and group members'. Not in instances, never enemies. (measured)
- **Map positions**: `C_Map.GetPlayerMapPosition(map, "player")` for your zone's map
  and the maps that cover it (the continent); nil for others. (measured)
- **`GetPlayerFacing`**: available (radians, counter-clockwise from north). (measured)
- **Height**: `UnitPosition`'s third return is always 0: no floors, no caves under
  the ground. `IsIndoors()` tells inside (caves, buildings) from outside; a cave
  has no map of its own (it stays the zone's map, type 3). (measured, ideaprobe)
- **Flight paths**: `C_TaxiMap.GetTaxiNodesForMap(map)` gives every flight point of
  the continent with its place on that map (outside 0..1 for the far ones), even
  away from a flight master; whether you know one is not in it (its `state` is nil):
  learned at the flight master (`NumTaxiNodes`, `TaxiNodeName`, `TaxiNodeGetType`:
  CURRENT / REACHABLE). `UnitOnTaxi` exists. (measured, ideaprobe)
- **Creature GUIDs**: `Creature-0-server-instance-zoneUID-npcID-spawnUID`. On retail
  the last six hex digits of the spawn UID are the spawn second on the server clock
  (`GetServerTime`) modulo 2^23, and the zoneUID tells copies (layers) of a zone
  apart. Whether Forever counts the same way: unconfirmed (ideaprobe). Secret in
  instances. (wiki and addon practice)
- **Enemy heals**: a heal shows as `UNIT_COMBAT` "HEAL" on the healed unit; its
  healer's `UNIT_SPELLCAST_SUCCEEDED` arrives at the same moment. Whether both come
  for enemies on plates: unconfirmed (ideaprobe).
- **Your own casts** (`UNIT_SPELLCAST_SUCCEEDED` for player and pet, with the spell
  ID): plain on Midnight; the kick trainer relies on it. (wiki; unconfirmed on
  Forever)
- **Maximum health of players**: plain out of combat (measured); Midnight keeps
  `UnitHealthMax` plain for players in combat too (wiki). The toughness averages
  are learned from it.
- **Enemy power**: `UnitPower` / `UnitPowerMax` of enemies, plain or secret:
  unconfirmed (ideaprobe); a status bar takes either.
- **`UNIT_COMBAT`**: amount, flag (CRITICAL...) and school stay plain in combat
  (1 physical, 8 nature). (measured)
- **Casts**: `UnitCastingInfo(unit)` works for plate units; name and times may be
  secret in combat. The times are returns 4 and 5. A mob often takes its target a
  moment *after* its cast starts. (measured)
- **Weapon imbues**: `GetWeaponEnchantInfo`, plus the timer line in the weapon's
  tooltip. (measured)
- **Spell costs**: `C_Spell.GetSpellPowerCost` lists entries per power type with
  `requiredAuraID` / `hasRequiredAura`; an equipped item may add a lowered entry.
  Druid forms on Forever: Bear Form 115 mana (55 %), Aquatic Form 16 (20 %) at level
  16. (measured)

## 5. Nameplates

- Can be anchored to, parented to and restyled, in and out of combat. Parts:
  `UnitFrame.HealthBarsContainer.healthBar` (a mask on its fill rounds the ends),
  `UnitFrame.CastBarsContainer.castBar`, `UnitFrame.name`, `LevelFrame`,
  `PlayerLevelDiffFrame`, `AurasFrame`, `ClassificationFrame`. (measured, platedump)
- Blizzard repaints the bar in `CompactUnitFrame_UpdateHealthColor` (can be hooked).
  (measured)
- **Never anchor a frame from outside a plate to a part of it** (a line from the
  player frame to a plate errored on hover). (measured)
- **Frames are reused**: the frame of a plate leaving the screen is handed to a new
  unit, often before `NAME_PLATE_UNIT_REMOVED` for the old one; constantly with
  "show nameplates off-screen". (measured)
- **Scale**: the plate frame is scaled 0.512 with UI scale 0.64: the health bar is
  about 49 x 5 px on screen. (measured, platesize)
- Friendly plates in instances may be forbidden to addons. (wiki)
- **Unit tooltips**: reported through `TooltipDataProcessor.AddTooltipPostCall(
  Enum.TooltipDataType.Unit, fn)` (classic: `OnTooltipSetUnit`). A world unit's
  tooltip is owned by UIParent or WorldFrame; unit frames own theirs. The mouse
  leaving a unit sends no event. (measured)

## 6. Quests

- **Positions**: the game's pins come per map: `C_QuestLog.GetQuestsOnMap(map)`. A
  quest handed in on another continent has its pin only on that continent's map
  (Blizzard's own marker showed it; seen with a delivery from Darnassus to
  Menethil). Ask your map, the ones above it, and every continent
  (`C_Map.GetMapChildrenInfo(world, 2)`). `C_Map.GetMapInfoAtPosition` names the zone
  at a point. (measured: the marker; the pin list per map: unconfirmed, see
  questprobe)
- `C_QuestLog.GetNextWaypoint`, `GetNextWaypointForMap`, `QuestPOIGetIconInfo`,
  `C_Map.GetMapWorldSize`: whether Forever answers is unconfirmed (questprobe).
- **Delivery quests** (no objectives) count as complete from the start. (measured)
- **The classic quest list** (`GetQuestLogTitle`) leaves out quests under a collapsed
  zone header; `GetNumQuestLogEntries` still counts them as its second return.
  At login the whole log appears at once, often after an empty look. (measured)
- **Texts and reward**: the log answers for its selected quest only
  (`GetQuestLogQuestText`, `GetQuestLogRewardXP`): select it for the moment of
  reading (classic `SelectQuestLogEntry`, modern `C_QuestLog.SetSelectedQuest`) and
  put the player's selection back. (unconfirmed on Forever: questprobe)
- **Quest items**: `GetQuestLogSpecialItemInfo(logIndex)` and
  `GetQuestLogSpecialItemCooldown(logIndex)`. (unconfirmed)
- **Links**: `GetQuestLink` (classic: by log line; modern: by quest ID). (unconfirmed)
- **Experience per kill**: `CHAT_MSG_COMBAT_XP_GAIN` ("X dies, you gain 87 experience");
  plain outside instances (unconfirmed). The quest value learns your pace from it.
- **Group quests**: `GetQuestLogTitle`'s third return / `C_QuestLog.GetInfo().suggestedGroup`
  (more than 1: a group quest). (unconfirmed)
- **Quest mobs**: the unit's tooltip data (`C_TooltipInfo.GetUnit`, lines of type
  `QuestTitle` / `QuestObjective`) names the quest and the objective for mobs whose
  kill or loot counts; without it, the mob's name inside an open objective's text.
  Whether Forever's tooltip data carries the quest lines is unconfirmed (`/sitrep
  doctor`: "quest mobs on the plates now"). The answer is the same for every NPC of
  one kind: the NPC ID is the sixth part of its GUID.

## 7. Forever's interface frames

Found with `/sitrep uidump`, `/sitrep mouse`, `/sitrep mapdump`. (measured)

- **Main bar**: `MainActionBar` (not `MainMenuBar`); it takes the mouse, so left
  empty it swallows clicks where the bar was. Its art hangs on it under keys
  (`ActionBarPageNumber`, `BorderArt`, `EndCaps`); buttons have `RightDivider` etc.
  Action buttons: `icon`, `IconMask`, `SlotArt`, `SlotBackground`, `HotKey`, `Count`,
  `Name`, `Border`, `NormalTexture`. 118 action buttons in all.
- **Dividers between the main bar's buttons**: unnamed child frames of
  `MainActionBar` (a pool, no key), each with `TopEdge` / `BottomEdge` / `Center`
  in the `UI-HUD-ActionBar-Frame-Divider-ThreeSlice-*` atlases; Blizzard makes them
  again when it lays the bar out (a cold start, Edit Mode). Each button sits in its
  own `MainActionBarButtonContainerN`. (measured, barprobe 4.1.5)
- **Micro menu**: `MicroMenuContainer`, `MicroMenu`, `MicroButtonAndBagsBar`. Buttons:
  Character, Spellbook, PlayerSpells ("Specialization & Talents") **and** Talent, Profession,
  Achievement, QuestLog, Guild, LFD, Collections, EJ, MainMenu, Help. No Socials, LFG,
  PVP or WorldMap micro button. Friends: `QuickJoinToastButton` by the chat;
  `ToggleFriendsFrame`, `C_FriendList`, `BNGetNumFriends` exist.
  Seit Mitte Oktober 2026 (Meldung des Testers, 4.9.10): `PlayerSpellsMicroButton` öffnet das
  Zauberbuch, `TalentMicroButton` die Talentbäume. Der Text von `SpellbookMicroButton` lautet im
  deutschen Client „Zauberbuch und Berufe“.
- **Bags**: `BagsBar`, `MainMenuBarBackpackButton`, `CharacterBag0..3Slot`,
  `CharacterReagentBag0Slot`, `BagBarExpandToggle`; combined backpack.
- **Experience**: `MainStatusTrackingBarContainer`, `SecondaryStatusTrackingBarContainer`,
  `StatusTrackingBarManager`.
- **Chat**: `ChatFrame1..10` with `Background`, `ButtonFrame`, `Tab`, `EditBox`
  (`Left/Mid/Right`) and the textures in `CHAT_FRAME_TEXTURES`; `ChatFrameMenuButton`,
  `ChatFrameChannelButton`, `QuickJoinToastButton`, voice buttons;
  `FCF_SetChatWindowFontSize`, `FCF_RestorePositionAndDimensions`, `FCFTab_UpdateAlpha`.
  Blizzard fades the chat background in on every mouse-over and sets the font after
  login.
- **Minimap**: `Minimap` inside `MinimapCluster.MinimapContainer`; on the cluster:
  `BorderTop`, `ZoneTextButton`, `Tracking`, `IndicatorFrame` (mail, crafting orders),
  `InstanceDifficulty`, `DielFrame` (the day/night moon), and
  `MinimapContainer.PlayerCoords` (coordinates under the map). `GameTimeFrame` is the
  calendar; `TimeManagerClockButton` the clock; `Minimap.ZoomHitArea` an invisible
  40x40 area in the map's corner that takes the mouse; `QueueStatusButton` the group
  finder's eye; `ExpansionLandingPageMinimapButton`, `AddonCompartmentFrame`.
  `SetMaskTexture` works (square map).
- **UI scale**: with `useUiScale` 0 the client scales the interface to
  768 / screen height (0.64 at 1200 px).

## 8. The client otherwise

- **Fonts for other alphabets**: on the German client the chat writes Chinese names,
  but a font family built from `GameFontHighlight`'s alphabets showed boxes for
  them (measured: the folded chat's preview). SITREP's families take Korean and
  Chinese from `ChatFontNormal` first. A chat window's own `GetFontObject()` is no
  family: it answers its Latin face for every alphabet (measured: boxes again), so
  an object like that is passed over. (measured)
- A face set on a font string itself (`SetFont`) wins over a font object set on it
  later: `SetFontObject(family)` after `SetFont` changes nothing, and the string keeps
  writing boxes (measured: the chat preview, 4.0.5). A string that should use a
  family never gets `SetFont` first; the tests count every such call.
- **The chat dock** (`GeneralDockManager`, the docked windows' tabs): Blizzard
  anchors it over the general chat window and anchors it again in `FCF_DockUpdate`
  and friends; a switch of tabs may run them without moving it. (partly measured)

- Registering an event the client does not know throws. (measured)
- SavedVariables are written on `/reload` and logout. The beta did not load them on a
  cold start. (measured)
- New files in the TOC load only on a full restart, not on `/reload`. (measured)
- Chat: `ChatFrame_ContainsMessageGroup(cf, group)` says whether a window shows a
  chat type; chat message text may be secret. (measured: the function; secrecy:
  unconfirmed)
- Addon messages: `C_ChatInfo.SendAddonMessage` to PARTY / RAID / INSTANCE_CHAT,
  255 characters. (measured)

## The probes

Each writes a report to the saved variables (`SITREP_DB.reports.<name>`, on
`/reload`): the evidence behind the "measured" facts.

| Command | Tells |
|---|---|
| `/sitrep doctor` | all of the below that can be checked at once, as OK / WARN / FAIL |
| `/sitrep perf` | what SITREP costs per frame, by part |
| `/sitrep plateprobe` | whether plates can be restyled (in and out of combat) |
| `/sitrep platedump` | every part of a plate |
| `/sitrep platesize` | nameplate size settings, a plate's real size |
| `/sitrep rangeprobe` | interact distances, item range checks per step |
| `/sitrep auraprobe` | which aura questions still answer in combat |
| `/sitrep castprobe` | each hostile cast: casting, attackable, its target (plain or secret) |
| `/sitrep zenprobe` | your and your group's health (plain or secret); each friendly plate: friend, player, target, group, zen, Blizzard's bar hidden; what still draws on the first zen plate |
| `/sitrep barprobe` | every texture on a few action buttons: its key, layer, shown, alpha, atlas or file |
| `/sitrep plateauras` | each plate's own aura frame: shown, scale, icons shown per row (debuffs, buffs, crowd control), an icon's parts |
| `/sitrep ideaprobe` | enemy heals and casts by token, creatures' spawn age and layer, enemy power, target speed, newer APIs |
| `/sitrep shiftprobe` | every cost entry of the druid forms |
| `/sitrep questprobe` | quest APIs, pins per map, texts, a few quests |
| `/sitrep uidump` | Blizzard's interface frames (bars, bags, chat, minimap, micro menu) |
| `/sitrep mapdump` | every part on and round the minimap |
| `/sitrep mouse` | what takes the mouse where it is |
| (always) `blocked` | every blocked or forbidden action, with the function |

## NPC-Tooltip (gemessen 2026-10-16, `/sitrep npcprobe`, 4.7.0)

`C_TooltipInfo.GetUnit` liefert für NPCs lesbare Zeilen (nicht geheim). Beispiel Kara Adams:
1 `[type 2]` Name · 2 `[type 0]` „Schildmacherin“ · 3 „Stufe 25“ · 4 „Stormwind“ · 5 „PvP“.
Der Titel steht **ohne** spitze Klammern in Zeile 2 (Classic-Form). Die Minimap-Tracking-Texturen
(`Interface\Minimap\Tracking\*`) und `Interface\GossipFrame\VendorGossipIcon` gibt es im Client.

## Plaketten-Reichweite und Respawn (gemessen 2026-10-16, `/sitrep spawns`, 4.7.5)

- `nameplateMaxDistance` lässt sich auf 80 setzen (steht dann in config-cache.wtf), aber Plaketten
  erschienen trotzdem höchstens bei etwa 28–30 yd (die Prüfung mit 30 yd schlug bei keiner neu
  erschienenen Plakette an). Forever begrenzt die Reichweite also selbst. Die Messung zeigt nur bis
  35 yd: Darüber gibt es keine Gegenstände, die die Entfernung prüfen.
- Die Spawn-Sekunde in Kreatur-GUIDs stimmt: 11 Mob-Arten bekamen plausible Respawn-Zeiten
  (Westfall/Rotkammgebirge, Median 24 s bis 4:34). Die Spannweite ist groß (15 s bis über 10 min),
  vermutlich weil verschiedene Spawnpunkte zusammengezählt werden oder Forever bei vielen
  Spielern schneller respawnen lässt.

## Weltkarte (bestätigt 2026-10-16, 4.9.3)

Die Erkundungs-Overlays der Zonenkarte (weiche Ränder) liegen über allem, was ein Addon auf der
Leinwand (`WorldMapFrame:GetCanvas()`) in derselben Strata zeichnet, auch bei hohem Frame-Level.
Eine Strata über der der Karte zeigt die Markierungen vollständig.

## Beute-Fenster (gemessen 2026-10-16, `/sitrep lootprobe`, 4.10.2)

Forever nutzt das moderne Beute-Fenster (`LootFrame.ScrollBox`, keine `LootButtonN`). Die Elemente
liefern `GetSlotIndex`. `GetLootSlotInfo` meldet `isQuestItem = false` und `questID = nil` auch für
Gegenstände, die ein Questziel braucht (gesehen: Geiferzahnschnauze für Westfall-Eintopf).
Quest-Gegenstände erkennt SITREP darum am Namen in den Zielen des Questlogs (4.10.3).

## Quest lines of a unit's tooltip in a group (measured 2026-10-16, `/sitrep npcprobe`, 4.11.5)

`C_TooltipInfo.GetUnit` lists, under the `QuestTitle` line (type 17), each group member's part: a
`QuestPlayer` line (type 18) with the player's name, then their `QuestObjective` lines (type 8) — the
player's own part too, under their own name, and in no fixed order. The first objective line is
therefore not necessarily yours: SITREP reads the lines per owner (`Quests.TipQuestLines`) and takes
your counts from your quest log.
