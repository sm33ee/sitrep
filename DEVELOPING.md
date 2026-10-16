# Developing SITREP

The map for whoever maintains this addon next (mostly an AI working without the
history of earlier sessions). Read this first; it is kept current with the code.
`SITREP/README.md` is the player-facing description of every feature.

## The client: World of Warcraft: Forever

Interface 16001: a modern (Midnight-era) client running a classic-style PvP realm,
with Midnight's addon restrictions switched on. **What it gives addons and where it
stops is in `FOREVER-API.md`**, by topic, each fact marked measured / wiki /
unconfirmed. Read it before touching anything that talks to the client.

Rules that follow from it:
1. **Secrets.** Read through `ns.read(fn, ...)`, `ns.plain(v)`, `ns.isSecret(v)`;
   check secrecy first, then the type. Never compare, test, add or join a value that
   may be secret; hand it to a widget as it is. Never `x and a or b` with x maybe
   secret; `a, b = cond and pcall(f)` keeps only pcall's first value (a test guards it).
2. **Combat.** No `CheckInteractDistance` / `C_Item.IsItemInRange` on non-enemies;
   no Show/Hide/move/attribute change of secure frames or of frames secure frames
   hang on; no nameplate CVars. Defer to `PLAYER_REGEN_ENABLED`.
3. **Taint.** Never open or hide Blizzard's frames from SITREP's code where the game's
   secure code relies on them: secure clicks on Blizzard's buttons, `K.Fade` (alpha,
   mouse) instead of hiding.
4. **Nameplates.** Draw on the plate, never anchor outside frames to it; go through
   `Plates.Current()` (frames are reused).
5. **Unknown names.** Every Blizzard frame or function is looked up and skipped when
   missing; a probe (`/sitrep ...`) finds the real names.

### Working within the client

Where SITREP does what, for each limit:
- **Range**: brackets from spells and `CheckInteractDistance` (10 / 28 yd) plus the
  item tables in `Data.lua -> RANGE_ITEMS` (LibRangeCheck-3.0's Classic Era / Forever
  tables); `Sensors.measureRange` respects the combat rule, `S.KnownItems` asks the
  first two known items per step.
- **Auras in combat**: `UI/TrackerAuras.lua` (oracle learned out of combat, Blizzard's
  buff bar icons, charge counting).
- **Casts on you** (no combat log): `Incoming.lua`, hostile plate units casting while
  their target is you, looked at again 10x a second while a cast runs; a secret answer
  drives the plate box's alpha through `C_CurveUtil.EvaluateColorFromBoolean`.
- **Blizzard frames replaced**: `K.Conceal` (hidden out of combat, faded in combat,
  hidden for real after it by `K.ConcealSweep`, given back only if shown before) for
  frames no secure code relies on; `K.Fade` for bags and micro buttons; `K.Mover`
  moves Blizzard frames by a corner (`hud.pos[id]`). Skins on a Blizzard widget are
  its own textures in a low layer (a child frame would draw over its text).
- **Bags**: a secure click on `MainMenuBarBackpackButton` (`UI/Bags.lua`).
- **Menu**: secure clicks on the micro buttons, a secure snippet opens and closes the
  list (`UI/MicroMenu.lua`); entries register the click edge the CVar names.
- **Action bars**: buttons keep their Blizzard parent and are anchored to SITREP
  holders out of combat (`UI/BarLayout.lua`, `b.srOrig` to give back); the bar
  frames' mouse is off while the layout is on (`BarLayout.Containers`).
- **Quest items**: secure item buttons placed on the screen by their rows, not hung on
  them; the tracker keeps its layout in combat while one shows (`UI/QuestItems.lua`).
- **Chat**: Blizzard's windows stay the engine, SITREP draws the rest (`UI/Chat.lua`).
  The font is applied again from a hook on `FCF_SetChatWindowFontSize`; folded
  windows go to alpha 0 without mouse (Blizzard's dock shows and hides them itself);
  Blizzard's tab alphas are all 1 while on and SITREP fades the tab bar
  (`GeneralDockManager`) itself; an unread tab ignores its parent's alpha. Blizzard's
  chat buttons are reparented into SITREP's bar (given back when off); a secret
  message text goes to its own font string.
- **Plates**: one skin per frame (`byPlate`), `N.skins[unit]` cleaned on reuse,
  `Plates.Current()`; bigger plates draw SITREP's own bar (`Plates.Size`, `s.big`,
  fed `UnitHealth` as given).
- **Quest positions**: `Quests.MapsToAsk` (your map, above it, every continent),
  `Quests.Vector` across zones on the continent's map; learned places otherwise.
- **Druid shift mark**: the form you were in last, Aquatic Form while swimming, else
  the dearest combat form; the lowest cost entry that applies now.
- **Hover info**: `TooltipDataProcessor` post-call hides Blizzard's world-unit tooltip
  when SITREP shows the unit; the mouse leaving is looked for at 10 Hz.
- **Blocked actions** are logged by SITREP (`reports.blocked`, `Debug.lua`): the first
  thing to read when the player reports "Interface action failed".

## Layout

One addon, `SITREP/`, loaded in TOC order. Root files are logic, `UI/` draws.
Line counts are roughly current; keep files under ~600 lines (split by job when
one grows past that).

| Lines | File | Job |
|---:|---|---|
| 529 | Core.lua | event bus (timed per handler while measuring), `ns.Timed`, secret guards (`ns.read`), settings + defaults, pruning, slash commands, `ns.Capture` reports |
| 195 | Data.lua | doctrine tables: classes, colours, matrix, HVT, reach, execute; range items |
| 524 | Sensors.lua | contacts from plates/target/focus/group targets, range brackets, closure, own state |
| 197 | Model.lua | envelope, threat score, priority/HVT, Lanchester engagement, calibration |
| 131 | Pressure.lua | incoming DPS, spikes, shadow health, time-to-live |
| 204 | Comms.lua | addon channel sharing, contact reports, range text |
| 231 | AAR.lua | after-action records, duels, heat by subzone |
| 142 | Allies.lua | friendly players: exact or bracketed distance, heal range, focus count |
| 115 | Targeting.lua | who targets whom: TARGETED BY, HEALERS, ALLIES, MOBS |
| 148 | Incoming.lua | casts on you: hostile plate units casting while targeting you; kick trainer, lockouts, fakes (`ns.Incoming`) |
| 246 | Recap.lua | death recap without the combat log: hits on you given to their likeliest source, tips (`ns.Recap`) |
| 150 | Spawns.lua | respawn times learned (a death seen, one of its kind seen fresh nearby: the GUID's spawn second) and the plates' real reach; /sitrep spawns (`ns.Spawns`) |
| 556 | Quests.lua | quest log (modern or classic API), quest places (exact / learned / giver), distance + bearing, learning, `/sitrep questprobe` |
| 290 | Trails.lua | learned paths: walked cells per map, outside and inside (doors), A* for the quest arrow; self-contained, see its header to remove it (`ns.Trails`) |
| 184 | Travel.lua | flight paths for the quest arrow: known points, learned flight times, fly-or-go plan; self-contained (`ns.Travel`) |
| 121 | QuestShare.lua | quest counts shared with group members running SITREP (`ns.QuestShare`) |
| 201 | Questbook.lua | quests handed in kept for the account (giver, objective places, hand-in, XP); `/sitrep route`: nearest-next route on this map; self-contained (`ns.Questbook`) |
| 164 | Drops.lua | quest item drop rates learned: kills per mob while an item objective is open, items to the corpse looted or kill before; kills per item for `Quests.Value`; `/sitrep drops` (`ns.Drops`) |
| 278 | Bestiary.lua | every hostile/neutral mob seen (plate, target, mouse; once per spawn): name, levels, where (100 yd cells, 30 a map), quests that want it (tooltips, kill objectives' words); told on accepting a quest; places for the quest arrow; `/sitrep mobs` (`ns.Bestiary`) |
| 253 | UI/QuestMap.lua | the chosen quest on the world map: spawn spots of its mobs (coral kill, gold item) with respawn times, learned places, a legend with drop rates (`ns.QuestMap`) |
| 260 | UI/QuestNearby.lua | other quests on the way: a plate whose mob another quest needs flashes, the arrow offers the quest with little detour (click: go there), quests close by get a mint bar in the tracker (`ns.QuestNearby`) |
| 850 | Debug.lua | flight recorder, `/sitrep debug`, plate probe/dump/size, ui/map dump, mouse, shift probe, blocked-action log |
| 208 | Doctor.lua | `/sitrep doctor`: every check of what SITREP needs from the client and of its own state (`ns.Doctor`) |
| 95 | Perf.lua | `/sitrep perf`: SITREP's cost per frame by bus handler and timed loop, fps, memory (`ns.Perf`) |
| 986 | UI/Kit.lua | flat widget set: textures, fonts, borders, brackets, controls, suggest popup, movable, `K.Conceal`, `K.Fade`, `K.DragResize`, `K.Mover`, `K.Opacity`, `K.Background` |
| 128 | UI/Heals.lua | heal prediction overlay (`ns.Heals`; `Attach(bar, ..., host, keep)`, `FeedTo(overlay, unit)` for bars not SITREP's) |
| 487 | UI/HUD.lua | HUD shell: module frames, engagement bar, pressure gauge, alerts, auto-hide, wiring |
| 533 | UI/HUDContacts.lua | envelope, threat board, allies panel |
| 350 | UI/Units.lua | unit building blocks: bars, secret-safe texts, cast bar + KICK, health colours, highlights |
| 310 | UI/Frames.lua | unit frame shell, Blizzard frames faded, `F.Apply`, event wiring |
| 590 | UI/FramePlayer.lua | player frame, popping numbers, cost preview |
| 446 | UI/FrameTarget.lua | target frame, range strip, target-of-target |
| 362 | UI/FrameGroup.lua | pet, target's pet, party |
| 497 | UI/Auras.lua | debuff/buff rows, dispel/purge logic (`A.Removable`) |
| 821 | UI/Plates.lua | nameplate restyle; own bar when bigger (`Plates.Size`), reused frames (`Plates.Current`), highlight (`ns.Plates`) |
| 276 | UI/PlateHover.lua | hover info window (or on the plate) instead of Blizzard's unit tooltip (`ns.PlateHover`) |
| 177 | UI/Incoming.lua | casts on you shown: pulsing red box on the caster's plate, flash message (`ns.IncomingUI`) |
| 189 | UI/Emergency.lua | healthstone and healing potion buttons in combat, lit at low health (`ns.Emergency`) |
| 143 | UI/RecapPanel.lua | the death recap on screen, `/sitrep recap` (`ns.RecapPanel`) |
| 232 | UI/Minimap.lua | square minimap, zone + coordinates, move handle, resize grip (`ns.Minimap`) |
| 107 | UI/XP.lua | experience line on the player frame (`ns.XP`) |
| 143 | UI/Bags.lua | bag button: free slots, opens the bags (secure click on Blizzard's backpack), shows the bag bar (`ns.Bags`) |
| 150 | UI/PlateAuras.lua | the game's own aura frame on each plate placed over the name and dressed (icons cropped, thin edge, HUD timer); /sitrep plateauras (`ns.PlateAuras`) |
| 916 | UI/Chat.lua | the chat: glass pane, tabs, input, Blizzard's buttons in a bar, presence fading, unread counts, folding with the last 3 lines (links work), Enter unfolds while typing, move handle (`ns.Chat`) |
| 369 | UI/QuestTracker.lua | quest tracker: nearest first, NEW (accepted last), group progress, fold to one quest, shift-click link (`ns.QuestTracker`) |
| 118 | UI/QuestItems.lua | quest items' secure use buttons by the tracker's rows; the tracker's layout kept in combat (`ns.QuestItems`) |
| 155 | UI/QuestArrow.lua | navigation arrow (lines turned by bearing - facing) (`ns.QuestArrow`) |
| 245 | UI/ActionBars.lua | action button skin, bar art, out-of-range veil (`ns.ActionBars`) |
| 232 | UI/BarLayout.lua | bars on SITREP holders: position, size, gap, buttons per row; Blizzard's bar frames without mouse (`ns.BarLayout`) |
| 271 | UI/MicroMenu.lua | MENU button: secure list of Blizzard's micro buttons, friends online, latency (`ns.MicroMenu`) |
| 256 | UI/Trackers.lua | tracker model: items, spells, ownership (class/character) |
| 145 | UI/TrackerLibrary.lua | spell search for the console fields |
| 258 | UI/TrackerState.lua | own casts, cooldowns, weapon imbues |
| 510 | UI/TrackerAuras.lua | aura state in and out of combat (oracle, buff bar, charge counting), fight report |
| 256 | UI/TrackerMirror.lua | list encode/decode, macro mirror |
| 287 | UI/TrackerIcons.lua | tracker icons: drawing, timers, wiring |
| 351 | UI/Config.lua | console window, navigation, page kit, `Cfg.AddPage` |
| 449 | UI/ConfigPicture.lua | pages: Overview, Sensors, Threat Model, Matchup Matrix, Engagement |
| 524 | UI/ConfigSettings.lua | pages: Pressure, Comms, Alerts, Display, Layout, Unit Frames, Nameplates, Interface, Quests, Bars & Menu |
| 182 | UI/ConfigLog.lua | page: Intel Log |
| 327 | UI/ConfigTrackers.lua | page: Trackers |

Modules are tables on the namespace: `ns.Sensors`, `ns.Model`, `ns.Pressure`,
`ns.Comms`, `ns.AAR`, `ns.Allies`, `ns.Targeting`, `ns.Incoming`, `ns.Debug`, `ns.Kit`, `ns.Heals`,
`ns.HUD`, `ns.Units`, `ns.Frames`, `ns.Auras`, `ns.Plates`, `ns.PlateHover`, `ns.Minimap`, `ns.XP`,
`ns.Bags`, `ns.Chat` (also `ns.ChatFold`), `ns.Quests`, `ns.QuestShare`, `ns.QuestTracker`, `ns.QuestItems`, `ns.QuestArrow`, `ns.ActionBars`, `ns.BarLayout`, `ns.MicroMenu`, `ns.Trackers`,
`ns.Config`. The namespace is also the global `SITREP`.

**Splitting rule.** A file captures what it needs from earlier files as locals at
load (`local newBar = ns.Units.NewBar`). Anything a *later* file defines is reached
at call time through the module table (`F.UpdatePlayer()`), never captured at load.
The test "every name the code reads exists" catches a name left behind by a move.

## The pipeline

`Core.lua` runs one clock (`P.sensors.rate`, default 5 Hz):

```
SR_TICK_PRE(dt)   Pressure: incoming damage windows, shadow health
SR_TICK(dt)       Sensors.Tick -> SR_SENSED(list, now) -> Model -> SR_PICTURE(byThreat, pic, now)
                  then Frames, Plates, Trackers, Auras, AAR, Debug refresh
SR_PICTURE        Allies.Tick -> SR_ALLIES(list, now); HUD draws; Comms shares
```

Bus events (`ns.On(name, fn)`, `ns.Fire(name, ...)`; handlers run in load order, each in pcall):

| Event | Arguments | From | Used by |
|---|---|---|---|
| SR_READY | | Core (profile loaded) | (nothing yet) |
| SR_LOGIN | | Core (PLAYER_LOGIN) | builds: HUD, Frames, Auras, Config stub, mirror |
| SR_CONFIG | key (`"section.field"` or `"*"`) | `ns.Changed` | every module re-applies |
| SR_TICK_PRE / SR_TICK | dt | Core clock | see above |
| SR_SENSED | contacts list, now | Sensors | Model |
| SR_PICTURE | Model.byThreat, picture, now | Model | HUD, Allies, Comms, AAR, Debug |
| SR_ALLIES | allies list, now | Allies | HUD |
| SR_NEW_CONTACT | contact | Sensors | HUD banner, AAR |
| SR_HVT / SR_TARGETED / SR_CLOSING | contact | Model | HUD alerts |
| SR_ADVICE | advice, previous | Model | HUD |
| SR_SPIKE | burst %, amount | Pressure | HUD |
| SR_COMBAT_START | record | AAR (fight begins) | (nothing yet) |
| SR_AAR | record | AAR (fight ends) | HUD after-action card |
| SR_CONSOLE | open (bool) | Config | Frames, Trackers |
| SR_INCOMING / SR_INCOMING_CHANGED | cast / | Incoming (a cast known to be on you starts / any change) | IncomingUI |
| SR_QUESTS | | Quests (log looked at again, navigation chosen or stopped) | QuestTracker, QuestArrow |

## Data shapes

- **Contact** (`ns.Sensors.contacts[key]`, key = GUID or `"N:"..name` or `"U:"..token`):
  `name, fullName, class, level, npc, faction, guild, unit` (token while seen),
  `lo, hi` (yd bracket), `range` (estimate), `closing` (yd/s, negative = closer),
  `live, age, last, lastLive, source`, `inCombat, targetingMe, casting`;
  Model adds `inTheirReach, inMyReach, ttr, threat, priority, hvt`; Targeting may set `healer`.
- **Ally** (`ns.Allies.list`, `ns.Allies.ForUnit(unit)`): `name, class, level, unit,
  group, exact, range, lo, hi, inHeal` (true/false/nil), `focus` (enemies on it), `dead, live`.
- **Picture** (`ns.Model.picture`): `rho, pwin, losses, advice` (CLEAR, ENGAGE,
  CONTEST, HOLD, BREAK, DEFEND), `nF, nH, pF, pH, x, duel`.
- **Pressure** (`ns.Pressure`): `dpsShort, dpsLong, hps, ttl, shadow, max, burstPct, spark, fight`.
- **Tracker item** (`ns.P.trackers.items[i]`): `id, kind` (cd/target/self/weapon),
  `spell, name, invert, x, y, size, alpha, border, when, warn, show, targetType,
  anySource, hand, aura, auraId, countHits, scope` (class/char/all), `class, char`.
- **Quest** (`ns.Quests.List()` / `Sorted(how)`): `id, title, level, index` (log line),
  `zone, complete, failed, objectives = { text, done, have, need }`; Sorted adds
  `target = { map, x, y, kind }` (kind exact / learned / giver; x, y on the zone map
  0..1), `yards` (nil when the map size is unknown or the place is on another map),
  `bearing` (radians counter-clockwise from north, like `GetPlayerFacing`), `elsewhere`
  (zone name), `here`. Learned places: `SITREP_DB.quests[id] = { title, giver = {map,x,y},
  obj = { [objective] = { {map,x,y}, ... last 6 } } }`. Navigation: `ns.Quests.selectedId`.
- **Layout elements** (console Layout page, `layoutElements` in UI/ConfigSettings.lua):
  everything with a place in `hud.pos`; size in `hud.frameScale[id]` (HUD modules,
  unit frames, bags, menu, quests, questArrow, castAlert, hoverInfo, chat: the whole
  chat via `Chat.Scale`), the minimap's in `ui.mapSize`, the
  chat's text in `ui.chatSize`, a bar's in `P.bars[id]`. Opacity in
  `hud.frameAlpha[id]` (read with `K.Opacity(id)`; HUD modules multiply it with
  `hud.alpha`, and the fader in UI/HUD.lua fades them and the player frame to it), a
  bar's in `P.bars[id].alpha`. Background opacity in `hud.bgAlpha[id]` (painted with
  `K.Background(tex, id)` on the element's `bg` texture: vertex colour `C.bg` with that
  alpha), a bar's in `P.bars[id].bg` (its buttons' `srTile`, `BarLayout.Tiles`). A new
  element with a background paints it with `K.Background` in its Apply. A new movable element is
  added to that list. `K.Dropdown` takes a list or a function, `{ header = "..." }`
  entries as headings, and opens a list longer than `K.DROPDOWN_ROWS` in columns.
- **Bar layout** (`ns.P.bars[id]`, id main/bottomleft/bottomright/right/left/bar5-7/pet/stance):
  `scale, gap` (button units, so it scales with the bar), `cols`; place in `hud.pos["bar_"..id]`.
- **Settings**: `ns.P` = `SITREP_DB.profile`, sections as in `ns.Defaults()`
  (Core.lua). Keys missing from the defaults are pruned at load, except the open
  tables `hud.pos`, `threat.matrix/power/hvt` and `trackers`.
- **Preset**: a first start (no saved profile) and `/sitrep reset` get
  `ns.NewProfile()` = `ns.Defaults()` with `ns.PRESET` laid over it (the
  maintainer's layout: scales, opacities, places, bar sizes). The defaults stay the
  bare doctrine; tests start from them. Every preset key must exist in the defaults
  (a test checks), or pruning drops it at the next login.

## Adding or changing a feature

1. Defaults: add the setting to `ns.Defaults()` in Core.lua (it is filled into old
   profiles automatically; a renamed key starts fresh).
2. Code: put it in the file whose job it is (table above); a new job gets a new
   file in the TOC. Read client values through `ns.read`; draw secret ones through
   widgets; protected frames (unit frames, board/ally rows) change only out of combat.
3. Console: a control on the right page in `UI/Config*.lua`; every page must fit
   (tested). A new page: `Cfg.AddPage(order, id, label, build)`.
4. Tests: a block in `tests/run.lua` (wrap it in `do ... end`: the main chunk is near
   Lua's 200-locals limit). The emulator is `tests/wow_mock.lua` (`W.scenario.units`,
   `W.Fire`, `W.Update(dt)`, `W.Secret(v)` makes a secret).
5. Docs: README.md for players; this file when structure, events or client facts change.
6. Version: `ns.VERSION` in Core.lua and `## Version` in SITREP.toc, together.

## Testing

```
luajit tests/run.lua      # Lua 5.1 semantics, like the client
lua5.5 tests/run.lua      # catches 5.1-only assumptions
luajit tests/glass.lua    # a first start (the preset layout) and the look's shapes, in a client of its own
```

Both must pass. Besides behaviour, the suite guards: no stray globals, no bus
errors, no name read that nothing defines (uses `luajit -bl`), every console page
fits, no multi-value `and pcall(`, no screen/mouse measuring outside the two
allowed places, secret values never compared in the paths it drives.

`luajit tests/bench.lua [seconds]` runs a crowded town (40 plates) through the
emulator and prints what `/sitrep perf` would. The emulator's calls cost (and
allocate) differently from the client's: use it to compare versions and to find
work done too often, not for the game's numbers.

Profiling: the emulator's own frame loop dominates wall time, so compare work with
`debug.sethook` sampling under `lua5.5`, counting samples with a SITREP function on
the stack, against the installed previous version.

## Diagnostics in the game

Chat cannot be copied out of the game, so reports go to the saved variables:
`WTF/Account/<account>/SavedVariables/SITREP.lua`, written on `/reload` (readable
from this machine: the client's folder is `/Applications/World of Warcraft/_classic_beta_`).
`SITREP_DB.reports.<name>` holds each probe's report, `reports.blocked` every blocked
or forbidden action, `SITREP_DB.errors` the last Lua errors, `SITREP_DB.diag` the
flight recorder.

- **`/sitrep doctor` first**: every check in one go (frames and functions SITREP
  relies on, blocked actions and errors of this session, secure buttons set as they
  should be, secret-value counts, plates, quests, group channel). OK / WARN / FAIL /
  INFO per line; the chat gets the count and the problems. A new feature that relies
  on the client adds its check to `Doctor.lua` (`check(section, fn)`).
- **`/sitrep perf [seconds]`**: SITREP's cost per frame, by bus handler ("event
  @file") and by every loop wrapped in `ns.Timed` (a new `OnUpdate` gets wrapped:
  `f:SetScript("OnUpdate", ns.Timed("label", function ... end))`), plus fps, combat
  time, plates, contacts, memory. Under 0.5 ms per frame is fine, under 1.5 ms
  noticeable in a crowd. Meant for battlegrounds. Each line is that part's own
  time (a handler that fires another event does not include the handlers it set
  off), so the lines add up to the total. The last column is the garbage each
  part makes (KB per second; the collector clears it at its own cost).
- **Per-tick work scales with plates.** The sensor tick runs about 10 times a
  second and a town has 40 plates: work per plate per tick adds up fast. Plates are
  redrawn in full within a time budget per tick (`N.Tick`, `N.BUDGET_MS`), by
  priority (`N.Interval`: target and an enemy that just targeted you every tick,
  enemies on you / in reach / healers 0.15 s, other enemy players 0.3 s, friends
  and mobs 0.5 s in combat, 1.5-2 s out of it), most overdue first, at least
  `N.MIN_PER_TICK` per tick; `/sitrep perf` reports redraws and waits. Friendly
  plates outside the group are measured by `Allies` every 0.75 s in combat, 2 s
  out of it (`a.nextAt`);
  what a plate's unit is (enemy, friendly player, other) is kept half a second
  (`S.PlateKind`; enemies every tick, a friend re-checked for a duel); the range
  fade asks one range check (`S.Beyond`), not the whole ladder;
  `S.MeasureRange` searches the ladder's steps by halving (about five questions,
  not twenty-odd for a unit far away); quest pins per map are kept ten seconds
  (`Quests.lua` `pinsOn`, forgotten on every quest event); quest mobs are asked
  once per NPC ID (`Q.MobOf`), forgotten on every quest event. Parts of a job can get
  their own perf line: `x = ns.Timed("label", x)` passes the return values on.
  Events (health, heals, casts, target) fill in between. Keep new per-plate work
  on those beats, not on every tick.
- **`/sitrep ideaprobe`** (90 s): whether the client gives what the newer
  features rest on: enemy heals and casts per token (healer detection), creatures'
  spawn age and layer (GUIDs), enemy power (healers' mana), target speed, newer APIs.
- The single probes (what each measures: `FOREVER-API.md`, "The probes").

## The look

One look (since 4.3; the "tactical" skin of up to 3.59 is gone, with `hud.skin`):
rounded panes of dark glass with a soft shadow, DM Sans (`Media/Fonts`, SIL Open
Font License), sentence case, glyphs instead of words on the plates, glass lighter
out of combat (`K.SetMood`), the quest list folded in combat, a ghost of the health
just lost behind your and your target's bar. Tests compare texts case-blind where
the case is the look's (`W.has`), and colours of shapes through `W.vc` (a glass
shape is a group of textures).

Build every panel through the Kit:
- `K.Backdrop(frame, colour, radius, { mood, shadow })`: a panel's background, a
  nine-piece rounded pane answering like one texture (a secret colour goes to its
  parts as it is). Anchor other regions to it with `K.Region(bg)`.
- `K.Border(frame, colour, thickness, radius)`: a rounded ring (radius 0: straight
  lines; `b.box` is what it follows), `b[1..4]` and `b:SetColor`. `K.Brackets`:
  none, unless the caller colours them (a soft ring).
- Texts from `K.Font` are put in sentence case (`K.Case`: words in capitals,
  abbreviations in `K.ACRONYMS` kept). `K.Upper` keeps the case as it is.
- Plate tags through `Plates.N.Tag(kind, arg)`; glyphs `K.Glyph(kind, r, g, b)` (a
  `|T` escape).
- The textures are made by `tools/make_textures.py` (rounded fills and rings at
  radius 4/8/12, the shadow, the glyphs): run it after changing a shape.
- New files under `Media/` load only on a full restart of the game.

## Delivering

- Install: replace only the `SITREP` folder in
  `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/`. Never touch
  other addons (e.g. ForeverPvP); the `_retail_` copy is an old version, leave it.
- Package: `SITREP-<version>.zip` of the `SITREP` folder in the project root,
  replacing the previous zip.
- The tester plays a German client and reads changes in the game; tell them what
  changed, whether `/reload` suffices (a new file in the TOC needs a restart), and
  what to check.
- The showcase page is `showcase/sitrep.html` (published as an artifact).
