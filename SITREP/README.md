# SITREP — tactical awareness for World of Warcraft: Forever PvP

Engagement envelope, threat board, Lanchester engagement calculus and an incoming-pressure
gauge, built for Forever's secret-value client. No combat log needed.

## Install
Copy this folder to `World of Warcraft/_classic_beta_/Interface/AddOns/SITREP`
(the beta folder; the launch folder name may differ). Interface 16001.

## Use
- `/sitrep` opens the console. `/sitrep help` lists commands.
- Key Bindings → AddOns → *Broadcast contact report* sends a one-line report to your group.
- Unlock the HUD in the console (Overview → Lock HUD) and drag the modules into place.
- Display: which modules show, and which only appear while enemy players are around.
- Layout: global scale and opacity, unlock to drag, reset all positions; then pick any
  element (HUD modules, unit frames, minimap, chat, bag and MENU buttons, quest tracker
  and arrow, each action bar) from one list and adjust it next to it: its size (the
  minimap in px; the chat: the whole chat, windows, tabs and input, and its text size; a bar also its gap and buttons per row), its
  opacity (10-100 %; HUD modules: times the HUD opacity; the player frame and the HUD
  modules fade out to it and in to it when they auto-hide), its background opacity
  (0-100 %, today's look by default; a bar's button tiles, the minimap's zone strip; the
  chat has none by default: above 0 it gets a flat background of SITREP's own behind the
  quiet chat), and "Reset its position" for that one element alone.

## Why an envelope and not a radar
Forever blocks addons from measuring nameplate positions ("Can't measure restricted
regions") and offers no unit coordinates or camera direction, so no addon can know where an
enemy is. It can know how far away each enemy is (range checks stay readable in combat) and
how fast that distance changes. The ENVELOPE module shows exactly that:
- one lane per contact, its distance bracket on a 0–40 yd tape
- the zone its class can hit you from (shaded; Data.lua → REACH), your own spell ranges (lines)
- closure rate in yards per second, from the moments it crosses a range boundary
- "REACH IN 1.8s" while it closes, "IN ITS REACH" once it can hit you; an early-warning alert
SITREP shows distances only, no directions: the client gives addons none, and estimating
them from range brackets alone (10 yd steps) was tried and was not reliable enough.

Distances come from range checks: your spells (harmful ones for enemies, helpful ones for
friends), the 10 and 28 yd interact checks, and items with fixed ranges in 5 yd steps from
5 to 45 yd (LibRangeCheck's tables for Classic Era and Forever; per step SITREP asks the
first two items this client knows). The items narrow a bracket to 5 yards, melee range
included. The interact and item checks are protected in combat: the
client allows them on enemies only, so in combat friends are measured by your spells
alone (asking about them would be a blocked action, "Interface action failed because of
an AddOn"). Items a client does not know are dropped on their own. Group members are exact (their positions). `/sitrep rangeprobe` shows
which items answer for your target and whether they agree with your spells.

## Unit frames
SITREP's own player and target frames replace Blizzard's (faded and click-through; switch
back under Console → Unit Frames). Left-click targets, right-click opens the unit menu.
- Player — survivability: your level (and a softly pulsing zZZ while resting in an inn or
  city), TARGETED BY n (enemy players targeting you right now), MOBS n (enemy NPCs whose target is you; levelling), HEALERS n (friendly players targeting you who heal: by their group role, a healing class when no role is set, or because they are casting a heal on you right now; useful as flag carrier; when none of them heals it reads ALLIES n, every friendly player targeting you; when the header gets long, PVP and then COMBAT give way), health (client-drawn even while secret), shields and incoming heals,
  crowd control shown as a red border around the health bar with "STUNNED 2.1s" in its middle, while the health turns light grey on dark grey so it stays readable, exposure ("IN REACH OF 2 · 1 CLOSING"), incoming
  DPS and time-to-live, PvP flag countdown, red/green hit and heal flash.
- Target — fire control: range strip (its bracket vs your spell lines and its reach) with how
  many of your spells reach it, cast bar (client-timed), execute line at 20 % for warriors
  and paladins, combo pips for rogues and druids, threat and HVT, matchup verdict, what its
  class can do to you, your duel and fight record against its class, who else is on it (ALLIES n: friendly players targeting it; for an enemy HEALERS n: its teammates targeting it that heal, by class or seen healing it; for a friend TARGETED BY n: enemy players on it), and whom it targets, with a slim health bar for that one (green / orange / red) on a shallow green track that marks full health.
- Auras: your debuffs under the player frame, outlined when your class can remove them; the
  target's buffs (outlined when you can purge them, "!" for big defensives, listed first) and
  debuffs (yours bright). Borders by type: blue magic, purple curse, brown disease, green
  poison, orange enrage. In combat the client may lock aura data: then the border and the
  outline are coloured by the client itself, and a fully locked list says so.
- Short buffs on the target (burst and defensive cooldowns, at most 15 s by default) glow gold
  and are listed right after big defensives.
- Range strip: 0-40 yd scale. Enemies are measured with your harmful spells, allies with your
  helpful ones (heals often reach farther), with your spell ranges as lines.
- Pet — your hunter's or warlock's pet (any pet), shown only while you have one: name and
  family, health (green, orange below 50 %, red below 25 %) with incoming heals, power,
  its cast bar (progress only: it is your own pet, nothing to kick), COMBAT/DEAD, hit and
  heal flashes, and what it is attacking (click that line to target it). Blizzard's pet
  frame is faded with the others; with SITREP's pet frame off it stays visible.
- Target's pet — the pet of whoever you target, under the target frame, shown only while
  it exists: the same layout, name coloured by friend or foe, its distance (harmful spells
  for an enemy pet, helpful ones for a friendly pet), and an enemy pet's casts get the
  bright last quarter and KICK (a Succubus's Seduction, a Felhunter's channel).
- Party — one frame per party member, stacked under a PARTY header (shown only in a
  group, each member only while it exists): name and edge in class colour, health
  (green / orange / red, like yours) with incoming heals, power, cast bar, exact distance
  coloured by your heal range (the frame fades when out of it), DEAD / GHOST / OFFLINE,
  TARGETED BY n when enemy players target them, and their debuffs with the ones you can remove
  first and outlined. The header counts who is in heal range ("2/3 IN HEAL RANGE"). Click
  to target, right-click for the menu. Blizzard's party frames (both styles) are faded.
- Cost preview: while you hover a spell (action bar, spellbook, SITREP's lists) or cast one,
  the part of your mana (or rage / energy) it takes lights up on your power bar in a lighter
  blue — red when you do not have enough, with the missing part shown faded past the end.
  If the client hides your power in combat, it still says whether you have enough.
- Druids: in Bear or Cat Form a thin mana bar sits under rage or energy. The mana a shift
  costs is marked on it (shifting into your current form again, for powershifting); in
  caster form the mark sits on the mana bar at your cheapest form. The mark is white
  (half opacity) while you can afford it, red when not. Costs come from the client, so they follow your mana pool.
  Hovering or casting a mana spell while in a form shows its cost on that mana bar (the
  cost preview, light blue or red), rage and energy abilities on the main bar as usual.
- Damage and heal numbers: every hit you take pops up in red just right of your health
  bar's centre, every heal in green just left of it (1.2k style). Each new number pushes the older ones
  up; they rise and fade within a second, criticals pop bigger, at most five per side.
  The amounts come from UNIT_COMBAT, which stays readable in combat. Switch: Unit Frames.
- Highlights on your frame and every party frame:
  - red border while it is being attacked (any hit, miss, dodge or parry against it), held
    for a second after the last one, then fading out over 1.5 s;
  - a pulsing border in the debuff's colour (blue magic, purple curse, green poison, brown
    disease) while it carries a debuff your class can dispel. In combat, when the client
    locks aura data, the client's own list of what you can dispel decides and colours it.
  Both can be switched off under Unit Frames.
- "Targeted by" counts enemy players SITREP can see (nameplates, targets) whose target is
  that person right now; enemies without a visible nameplate cannot be counted.
- Left out: portraits, your own name, rest/XP, faction crests, same-level badges.

## Heal prediction
Heals on their way are drawn as a translucent extension of the health bar, starting where
the health ends and stopping at full health: on the player, target, pet and party frames, and
the health lines of the allies and contacts rows (enemy healers too).
- Your own heal (brighter): the **lowest** amount its tooltip promises — "heals for 812 to
  944" counts as 812 — so the bar never promises more than the heal surely brings. Read from
  the spell description in any client language ("to", "bis", "à", "до", "-").
- Other healers' heals (paler, after yours): the client's own prediction for their casts.
- In combat the client may hide the numbers (secret values). The bars still draw them, but
  then SITREP cannot swap in the lowest amount, so your part shows the client's figure.
- Updates the moment a heal starts, lands or is cancelled (UNIT_HEAL_PREDICTION).

## Allies
The ALLIES panel is the friendly picture. Group members get exact distances from the
client's positions (no traffic); if the client withholds them, they fall back to range
checks. Other friendly players (friendly nameplates, target, hover) are ranged with your
helpful spells. Each row: distance coloured by your heal range (green inside, red outside,
orange unsure), health with incoming heals, IN/OUT OF HEAL RANGE, and TARGETED BY n when
enemies target them. Rows are click-to-target. The panel stays out of sight while there are
no allies.

Group sharing: each contact you see is announced to your group (who, class, level, in
combat), not where: its distance from you says nothing about its distance from them.

## Trackers (your own spell icons)
Console → Trackers (or `/sitrep trackers`). Add a spell by its name as your client writes it
(German names on a German client) or by spell ID, as one of three kinds:
- **Cooldown** — shows while the spell is on cooldown, with the swipe and the time left
  (or always, dimmed on cooldown). The global cooldown is ignored.
- **On target** — shows while the aura (Corruption, Hunter's Mark, Sunder…) is on your
  target, with its time left; enemies, friends or any target; only yours or from anyone.
- **On me** — shows while the buff is on you, with its time left (from anyone, or only yours).
- **On weapon** — shows while a temporary weapon enchant is on (Flametongue, Windfury,
  poisons, oils), main hand, off hand or either, with its time left. Imbues are item
  enchantments, not spells or buffs, so no spell search finds them. SITREP reads them from
  two places: the client's weapon-enchant data, and the weapon's tooltip (the line with the
  timer, e.g. "Flammenzunge 3 (29 Min.)"). Optionally give a text that line must contain.

Every icon belongs to the class that made it: other classes neither see it on screen nor in
the console's list (the list header counts them). The button beside the icon's name in the
editor switches between ONLY <CLASS> (default), THIS CHARACTER and ALL CHARACTERS. Icons
from lists before 3.20 are claimed by the first class that knows the spell; until then
they stay hidden. The macro copy keeps whose icon it is.
  With both hands imbued, the enchant learned from your cast tells yours apart.
  `/sitrep weapon` prints what the client reports, raw.

**Searching for spells**: both the "add a spell" box and the buff field suggest matches
while you type (from two letters, case-insensitive): your spellbook with every rank, the
auras on you and your target right now (their exact names), auras SITREP has seen, an exact
spell name or a spell ID. Each line shows icon, name, rank, ID and where it was found;
eight lines at a time, the mouse wheel and arrow keys scroll through all of them (a thin
scrollbar and "28 found · 9-16" show where you are), Enter picks, the box then holds "Name (ID)". Hovering a line shows the spell's full tooltip
(full name, rank, description) with its ID and source; the icon list does the same. The last line, "search all spells
for …", walks every spell the client knows in the background (a few seconds, live progress)
and adds what it finds.

**Look for this buff instead** (On target / On me): when a spell puts a buff with another
name on you ("Waffe der Flammenzunge" → "Waffenzunge"), type that buff's name or ID.
`/sitrep buffs` lists your buffs exactly as the client names them (with IDs) and your
weapon enchants.

**Invert** (per icon) turns each around: NOT on cooldown, NOT on the target, NOT on me.
Inverted aura icons can also show shortly before the aura runs out ("also show when less
than N s left", with the time remaining) — a refresh reminder.

Each icon has its own place (drag it in layout mode, or set X / Y), size (16-96 px),
opacity, an optional importance border (red, orange, green) and when it may show (always,
in combat, out of combat).

In combat the client refuses addons every aura list and every aura's data. SITREP gets
around that by asking narrower questions the client may still answer:
- buffs Blizzard never hides are read directly, in combat too (exact);
- for an aura that was already up before the fight, SITREP asks about that very instance
  ("is it still there?") through calls the client keeps answering for timers and filters.
  Which calls work, and what their answers mean, is not assumed: out of combat SITREP asks
  each one about an aura it can see and one it watched vanish, and keeps only those whose
  answers differ. In combat: a plain answer is used directly; a yes/no answered only
  secretly is handed to the client, which then shows or hides the icon itself (SITREP never
  sees the answer); one that fails is dropped. A buff dispelled, cancelled or run out
  mid-fight is then shown exactly.
- Blizzard's own buff bar keeps updating in combat: while your buff's icon there stays
  readable (until Blizzard redraws that button), it says exactly whether the buff is on you;
- buffs with charges (Lightning Shield: 3) are counted down on the hits you take: physical
  hits only (melee swings and physical attacks; misses, dodges, parries and spells do not
  count, a recast fills it up again). Ranged physical hits look the same and are counted
  too. "ON ME" icons show the charges left. Per icon: "Count charges on melee hits".
- otherwise: your own casts and the lengths measured earlier, marked "?" (a recast in
  combat starts a new instance the client will not name).
`/sitrep auraprobe` shows what was learned; hovering an icon in the list says how it is
kept up to date in combat.

**Keep in macros**: the beta forgets addon settings at every restart. Switched on, the icon
list is kept in a few of your general macros (named SRT… per character, one per ~225
characters of settings, at most eight). At login SITREP reads them back when nothing else
did. Clicking such a macro only prints what it is for. Export profile (Intel Log) keeps
everything as a copy/paste string as well.

## Casts on you

The combat log is closed to addons on Forever, so "this spell hit you" cannot be read.
What can be: a hostile unit with a plate starts a cast or a channel while its target is
you (most spells go to the caster's target). SITREP looks the moment a cast starts, when
the caster switches its target, when its plate appears mid-cast, and 10 times a second
while a hostile cast runs (mobs often take their target a moment after starting).
- **The caster's plate:** a bold red box round the whole plate (name, bar and cast bar),
  pulsing, with a faint red fill and ON YOU beside it; drawn above other plates and
  never dimmed with the plate. To target the caster, click its plate: in combat the game
  lets no addon choose what a click targets, but the plate is the game's own button.
- **Flash message:** "Grimmzahn casts Schattenblitz on you!" above the middle of the
  screen, for any hostile caster that is not your current target (mobs too; your
  target's cast bar is in front of you anyway): the caster in its class colour (mobs
  red), the spell, "on you!" in red, on a dark band; 2 s, then it fades. The same caster
  at most every 1.5 s. A sound for enemy players. Movable while the HUD is unlocked; on
  the Layout page as "Cast alert" (size, opacity, background). Alerts page: on/off, Test.
- When the client keeps "is its target me" secret (in combat, sometimes), the box still
  shows (the client decides it from its own answer); the flash then does not know.
Switches: Nameplates (Casters at you: red box), Alerts.
`/sitrep castprobe` records two minutes of enemy casts and what SITREP made of each
(casting, can attack, its target is me: plain or secret) into the report `castprobe`.

## Nameplates

Blizzard's nameplates in SITREP's look, friendly and hostile (console: Nameplates):
- **Bar:** flat, on a dark track, thin dark border. Blizzard's border, background, level
  badge and the mask that rounds the bar's ends are hidden (found by their key names;
  `/sitrep platedump` lists every part of your target's plate if one still shows).
  Blizzard lays the bar out left of centre and a little high; SITREP moves it right 12 px
  and down 4 px (sliders on the page) and puts Blizzard's layout back when switched off.
- **Colour:** class colour for players; mobs red when their target is you, orange hostile,
  yellow neutral, green friendly, grey when tapped by someone else. Blizzard repaints its
  bar on every update; SITREP re-applies its colour from a hook on that update.
- **Text:** one line centred over the bar, in full (no cut-off): the level in its danger
  colour (grey, green, yellow, orange, red; ?? red; + elite, R rare), the name in the
  friend (green), neutral (yellow) or foe (red) colour, then the tags: YOU, HVT, HEALER on
  enemies, TARGETED n on friends. Close over the bar; on your target it moves up clear of
  the brackets.
- **Enemy players:** a solid red 4 px line on each side, lined up with the target brackets
  and never dimmed by the client.
- **Your target:** larger corner brackets in its friend/foe colour, its distance in yards
  beside them (exact for group members, else the range bracket like 20-28y), and a 4 px
  distance marker, as tall as the brackets: green within 10 yd (the closest check the
  client answers; melee range itself cannot be measured), yellow within 25 yd, red within
  your longest spell (helpful ones for friends), none beyond.
- **Friends you have not targeted:** bar, border and cast bar 70 % opaque (slider), level
  and name solid. A friend you target shows in full.
- **Cast bar:** SITREP's (KICK window, grey when it cannot be interrupted) under the bar, as
  wide as it; Blizzard's (in its cast bar container on Forever) is hidden.
- **Range:** a unit beyond your longest spell (harmful ones for enemies and mobs, helpful
  ones for friends) gets a faded bar, on every plate (also your target), measured the same
  way as the target's distance marker; the text stays fully visible.
- **Friendly plates:** red border while being hit, the debuff colour when you can dispel it.
- **Heals on their way:** like on the unit frames, a translucent extension of the health
  bar: incoming heals, yours (its lowest promised amount) brighter on top; secret amounts
  in combat drawn as the client gives them; fades with the bar out of range.
- **Size:** a slider for all plates. Forever has no nameplate size setting and draws the
  plates at about half size: away from 100 % SITREP draws its own health bar (the game's
  health values, secret ones too), centred on Blizzard's (invisible then), and scales its
  whole look with it (name, level, brackets, cast bar, marker). Where a client has the
  game's own size settings, they are set too (out of combat). The click area stays the
  game's. `/sitrep platesize` lists the settings and a plate's real size.
- **Party members:** the mouse on a member's frame draws its plate as your target's.
- **Hovering a unit:** a window of its own (Layout: "Hover info"; placed like the HUD)
  shows the unit under the mouse instead of Blizzard's tooltip: name and level, race and
  class (or type and rank), guild, and for a quest NPC the objective and the quest. Or,
  chosen on the Nameplates page, on the plate itself: what the plate does not say already
  shows in its bar while the mouse is over it: a player's race and class (in its class colour), an NPC's beast
  family or creature type and its rank (Elite, Rare, Boss). Blizzard's unit tooltip at
  the side of the screen is left out then; hold Shift to see it anyway. Units without a
  SITREP plate, and unit frames, keep Blizzard's tooltip. An NPC that is part of one of
  your quests also gets a yellow line over its name: the objective (count first) and the
  quest (from the client's own tooltip lines where it has them, else the NPC's name in
  an open objective).

Size, stacking and which plates show stay the game's settings. Forbidden plates (often
friendly plates in instances) stay Blizzard's. A plate showing only a name keeps Blizzard's.

### Blocked actions
When the client says "Interface action failed because of an AddOn", it names the protected
function it blocked. SITREP keeps the last 30 (time, function, in combat or not) in the
saved report `blocked` and mentions each function once per session in chat.

### Probe

`/sitrep plateprobe` checks whether SITREP may restyle nameplates on this client, for
friendly and hostile plates. For each plate on screen it anchors a small SITREP marker
above it, parents a frame to it, recolours Blizzard's health bar in SITREP green and gives
it the flat texture, and records which of these work (and which plates are forbidden).
Everything shows for 6 s and is then put back; the report says whether the client had
overwritten the colour by then and how often Blizzard's nameplate updates ran. Run out of
combat, it arms one more run 2 s into the next fight. Reports: `plateprobe`,
`plateprobe_after`, `plateprobe_combat` in the saved variables after `/reload`.

## Interface (minimap, experience, bags, chat, action bars, menu)

The game's own interface in SITREP's look (console: Interface; each part can be
switched off and is then Blizzard's again, `/reload` restores every detail):
- **Minimap:** square, with the HUD's border and corner brackets. The zone sits on a strip
  above it in its PvP colour (blue sanctuary, green friendly, orange contested, red
  hostile), your coordinates in the bottom right, zoom on the mouse wheel. Size 120-320 px
  (slider, or the grip in its bottom left corner). The round border, compass, zone bar
  and zoom buttons are hidden; Blizzard's buttons round the map (day / night, mail,
  tracking, battleground, the day / night moon, instance difficulty, the group finder's eye)
  move to its corners, the clock into the zone strip; Blizzard's coordinates under the
  map are hidden while SITREP's show in its corner.
  `/sitrep mapdump` lists every part on and round the map (to place one that strays).
- **Experience:** a 2 px line along the bottom of your player frame: violet experience,
  rested experience ahead of it in faint blue. Hover it for the numbers. Not shown at the
  level cap. Blizzard's experience bar is hidden (and the reputation bar sharing its strip).
- **Bags:** one movable button (unlock the HUD to drag it) with a bag icon and the free
  slots: `FREE 10/54`, orange under 10, red under 5. Click opens all bags; right-click shows
  Blizzard's bag bar to swap bags, right-click again hides it.
- **Chat:** no background, no button column, tabs only while the mouse is over the chat,
  then as flat dark plates with an accent line under the selected one (a new message
  blinks an accent bar on its tab)
  (Blizzard fades the background back in on mouse-over; SITREP keeps it hidden), text
  11 pt with an outline (the game's chat font, so every alphabet still shows; applied
  again whenever Blizzard sets its own size), lines fading after 20 s (both sliders). The
  input line is a flat field drawn under the typed text.
- **Chat folded away:** the - / + button over the chat's right corner (also a key binding,
  `/sitrep chat`, or the Interface page) folds the chat: its messages out of sight and out
  of the mouse's way, only the tabs of windows with new messages showing, with how many
  (the button shows the total, e.g. +3). New means whispers, group, raid, guild, officer,
  say and yell; not the public channels, not your own messages. The last 3 messages of these
  kinds (your replies too, read or not) show as lines where the chat's top is, oldest
  first, in their chat colour (option on the Interface page); clicking a line or a tab
  unfolds the chat at that window; hovering where the chat is shows all tabs. The input line moves up
  under the preview lines (or the tabs) while folded; the chat stays folded while you
  type, so you answer from the preview.
- **Moving the minimap and the chat:** unlock the HUD (Layout page or `/sitrep unlock`):
  a green handle covers each; drag it. The minimap keeps its top right corner (it grows
  down and left), the chat its bottom left corner; the docked chat windows follow the
  main one. "Reset all positions" or "Reset its position" on the Layout page, or switching the part off, puts them back
  at Blizzard's place.

- **Action bars** (console: Bars & Menu), in SITREP's look: the icon cropped
  square on a dark tile with a thin border, Blizzard's frame and rounded mask off, flat
  highlight, pressed and active states in the accent colour, key bindings and charges in
  the HUD font, macro names hidden (option). A red veil lies over a button whose spell
  does not reach your target. The bar art (gryphons, backgrounds, border, end caps, the
  page switch, the dividers between buttons) is gone; paging by key still works.
  Switching the skin off takes effect after `/reload`. The druid/stealth/stance bonus bar
  of classic clients gets the same skin and sits exactly over the main bar.
- **Bar layout:** each bar (main, bottom left/right, the right bars, pet, stance) with its
  own size, gap between buttons and buttons per row: pick the bar in the console, set
  the three sliders. Unlock the HUD to drag a bar by its green handle. The buttons stay
  Blizzard's (their bar still decides when they show; paging stays the game's): SITREP
  anchors them to a holder of its own, out of combat only (a change made in combat waits
  for its end). A bar starts where Blizzard had it, with Blizzard's 6 px gap; Edit Mode
  laying a bar out again is undone. Blizzard's own bar frames, empty then, take no mouse
  (they used to swallow clicks where the bars had been). Reset positions (Layout page) puts the bars back at
  Blizzard's place; switching the layout off gives every button Blizzard's anchors back.
- **MENU button** (movable like the HUD): Blizzard's micro buttons folded into one button
  that also shows your latency (green, orange over 120 ms, red over 250 ms; hover for
  home and world latency and frame rate). Click it: a list of every window the client has
  (character, spellbook, talents, quest log, social, map, game menu...) in the game's own
  words, each with its key binding, and Friends (with how many are online; on clients
  without a social micro button it is an entry of its own: the friends button by the
  chat is hidden with the quiet chat). Your online friends also show on the MENU
  button itself, a green dot and the count (hover: in the game and on Battle.net).
  The entries are secure clicks on Blizzard's own
  buttons and the list opens and closes in the secure environment, so it works in combat.

`/sitrep uidump` lists which of Blizzard's frames this client has, for a part that does
not apply (report `uidump` after `/reload`).

## Quests

Your quest log, nearest first, and an arrow to the quest you choose (console: Quests).
- **Tracker** (replaces Blizzard's quest tracker; movable like the HUD): the level in its
  difficulty colour, the title, how far it is (`~360 YD`, or the zone when it lies on
  another map) and the objectives still open with their counts (`5/8 Kobold Vermin
  slain`). Finished quests say TURN IN. Order: nearest first (quests without a known
  place after them, those in your zone first), or by zone, or by level. It re-sorts every
  2 s, but not while your mouse is over it. Click a quest to navigate to it, click again
  to stop; right-click opens the quest log at it; shift-click puts its link into the chat
  (into the open input line, else a new one). A quest that comes with an item to use has
  its icon left of its row: click to use it (a secure button), with its cooldown,
  charges and tooltip. The game lets no addon move such a button in combat, so while one
  shows the tracker keeps its layout through combat (counts still update) and sorts
  again after it. Hovering a quest shows the experience it
  gives (and how much of your level that is), its task, its story (cut after 450
  characters), its objectives and where its place comes from. The 3 quests accepted
  last stand on top under NEW (a thin line under them), not again in the list. Group
  members who run SITREP share their counts: small, at each objective's right end, how
  many each still needs (a green name: done), up to 5 members; the tooltip lists them in
  full. Click the header (- / +) to fold the
  tracker to only the quest you navigate to (none chosen: the nearest one, NEAREST), and
  back; also a key binding, `/sitrep quests`, or the Quests page.
- **Arrow** (movable): turns toward the chosen quest as you turn, with the yards under it;
  in the accent colour when you face it (within 15 degrees). ARRIVED within 10 yards;
  IN WESTFALL when it lies on another map; right-click stops navigating. A key binding
  (Key Bindings > AddOns) and `/sitrep quest` navigate to the nearest quest, or stop.
- **Where a quest is:** the game's own quest position where the client gives one (exact,
  no ~): its waypoint, or its pin on your map, the maps above it, or any continent (a
  quest handed in across the sea shows its zone, e.g. WETLANDS). Otherwise SITREP learns it: where your objective counters went up (the middle of
  the last 6 places, per objective), and for a finished quest with objectives where you accepted it
  (most are handed in there; a delivery is not: no guess for it). No place known: no
  distance and no arrow. `~` marks a learned place. A quest you have not
  progressed yet has no place. Learned places are kept in the saved variables; the beta
  forgets those on a cold start, so they are relearned then.
- `/sitrep questprobe` reports what this client tells about quests: which quest API it
  has, whether it gives quest positions, the map size in yards, your facing, and the
  first eight quests with their objectives (report `questprobe` after `/reload`).

## When something does not work
`/sitrep doctor` checks everything SITREP needs from the game and its own state, and
names what is missing or broken (count in the chat; details in the report `doctor`
after `/reload`). `/sitrep perf [seconds]` measures what SITREP costs per frame (for
busy places like battlegrounds; report `perf`).

## Duels
A visible, attackable player of your own faction is a duel opponent. During a duel the
engagement bar uses a separate duel curve, and the result is read from the client's
"X has defeated Y in a duel" message (localized). Duels are tagged DUEL in the Intel Log,
train only the duel curve, and build a win/loss record per opponent class.

## Files
Logic in the folder's root (sensors, model, pressure, comms, after-action, allies,
targeting, diagnostics), drawing in `UI/` (HUD, unit frames, auras, nameplates,
minimap, experience, bags, chat, quests, trackers, console), each job in its own file. `DEVELOPING.md` next to this folder
maps every file, the events between them, the data they share and what the
Forever client allows.

## Tests
From the parent folder: `luajit tests/run.lua` (1266 scenario checks against a client emulator; `lua5.5 tests/run.lua` too).

## Known limits
Not yet confirmed in the live client. The beta does not load SavedVariables (Blizzard bug):
use Intel Log → Export profile as a backup.
