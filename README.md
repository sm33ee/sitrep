# SITREP

A calm glass HUD for **World of Warcraft: Forever** (client interface 16001). It replaces
Blizzard's frames with quiet, rounded glass panes that stay out of the way when nothing
happens and get clear when it counts, and it learns the world as you play: where quests
are, how you get there fastest, where mobs spawn, how often they drop what you need.

Built for Forever's *secret-value* client: no combat log, many values hidden in combat.
SITREP works with what the client still gives and says so where it cannot.

**Download: [SITREP.zip](https://github.com/sm33ee/sitrep/releases/latest/download/SITREP.zip)** (the newest version)

> **Deutsch:** SITREP ist ein ruhiges Glas-HUD für WoW: Forever, mit eigenen Rahmen,
> Namensplaketten, Chat und einer Quest-Navigation, die beim Spielen lernt: wo Quests
> liegen, ob Fliegen schneller ist, wo Mobs spawnen und wie oft sie Quest-Gegenstände
> droppen. Installation und Befehle unten.

## Features

**Frames and HUD**
- Player, target (grows with what it shows), pet, focus and party frames in glass; buffs
  above, debuffs below the target; party members with their target, dispel orbs and a
  compact mode
- Raid frames for up to 40: one column per group in use, class colour, dispel orbs, aggro
  and target rims, faded out of heal range
- Your focus in magenta everywhere: its frame, a ring on its plate, an alert when it
  casts; shift-click a frame or a key (mouse over a plate) to set it
- Nameplates: role-based colours, a coral ring for enemy players, a blue one for your
  group, group focus rings, dispel orbs, combo points, auras over the name, a calm "zen"
  mode for friendly players
- Friendly NPCs: no bar, their title and an icon for what they do (repair, inn, flight
  master, trainer, vendor...)
- A hover window next to the mouse instead of the tooltip: race/class, guild, NPC title,
  dispellable debuffs, quest objectives, what your group still needs, where a mob was seen
- Chat, minimap, action bars (empty slots hidden), XP lines (also for hunter pets), a
  folded MENU button, alert banner, emergency items, a small button for the test
  client's issue reporter; every element movable and scalable

**Quests**
- Quest tracker with every objective, a worth-it rating (XP per minute against grinding,
  including kills on the way, learned drop rates and nearby quests), "almost done" marks
- A quest arrow that picks the quickest of all places it knows for a quest (the game's
  point, where your counters went up, spawn spots of its mobs), on foot or by flight path
- Learned ways (walked, swum, drawn by hand on the world map: water, rough terrain, no way
  through) so the arrow leads round mountains and lakes
- On the world map: spawn spots of the chosen quest's mobs with respawn times and drop
  rates, flight points (known or still to unlock), the ways you know
- Other quests on the way: plates of mobs another quest needs flash, the arrow offers a
  quest with little detour, nearby quests get a mark in the tracker
- Quest items marked in the loot window and in your bags
- Bestiary: every mob you pass, where, and which quests want it; told when a new quest
  needs a mob you have seen before
- Questbook and route: quests handed in are kept for your account; `/sitrep route`
  suggests an order on the next character

Everything learned is kept for your whole account (all characters).

## Installation

1. Download **[SITREP.zip](https://github.com/sm33ee/sitrep/releases/latest/download/SITREP.zip)**
   (always the newest version; older ones are in the [Releases](https://github.com/sm33ee/sitrep/releases)).
2. Unpack it into `World of Warcraft/_classic_beta_/Interface/AddOns/` so that there is a
   folder `AddOns/SITREP` with `SITREP.toc` in it.
3. Start the game (a full restart after the first install or after an update that adds
   files), and type `/sitrep` for the settings.

New installs start with a ready layout; `/sitrep reset` goes back to it.

## Commands

| Command | What it does |
|---|---|
| `/sitrep` | open the settings |
| `/sitrep lock` / `unlock` | lock or move HUD elements |
| `/sitrep quest` | navigate to the nearest quest (again: stop) |
| `/sitrep route [go]` | an order for the quests on this map |
| `/sitrep mobs [name]` | the bestiary |
| `/sitrep spots [all]` | grinding spots: where mobs come back fastest |
| `/sitrep drops` | learned drop rates of quest items |
| `/sitrep ways` / `ways export` / `ways import` | learned ways, and sharing them |
| `/sitrep chat` / `chat dock` | fold the chat; dock stray chat windows |
| `/sitrep doctor` | check what SITREP needs from the client (the first thing to run) |
| `/sitrep perf [seconds]` | what SITREP costs per frame |
| `/sitrep reset` | back to the default layout |

More diagnostics (`/sitrep …probe`) are listed in the console's help.

## Feedback

Bugs and ideas: open an issue. Many diagnostics write a report you can send along: run
the probe, then `/reload`; the report is in
`WTF/Account/<account>/SavedVariables/SITREP.lua`.

## Development

The addon is plain Lua, tested headless against an emulator of the client:

```
luajit tests/run.lua
luajit tests/glass.lua
luajit tests/bench.lua
```

`DEVELOPING.md` describes the modules, `FOREVER-API.md` what the Forever client allows
(measured in game).

## License

MIT, see [LICENSE](LICENSE).
