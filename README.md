# All-in-One Guide

One leveling guide addon with one guide window and a waypoint arrow. It can hold many guides as guide packs, so you only need one guide addon in game.

Made for WoW Forever (interface 16001). Version: 0.2 (beta).

## What you get in this beta

This is a beta. It has two demo routes:

| Route | Faction | Levels |
|---|---|---|
| Elwynn Forest (Northshire to Goldshire) | Alliance | about 1-6 |
| Durotar (Valley of Trials to Razor Hill) | Horde | about 1-6 |

- Both routes include each class's starting letter, and neither one grinds.
- The guide follows the game itself (quest log, finished quests, level, bags, position). It only remembers which step you are on, and your skips.
- The guide window shows the step to do now at the top, with the next steps under it. The arrow points to the spot.
- Quest facts come from the Warcraft Wiki, CMaNGOS and ForeverDB (see [Credits](#credits)). They are not yet all confirmed on WoW Forever. If a step looks wrong, please [report it](#report-a-mistake).
- Texts are in English and Danish.

## What's in v0.2

| Part | What it does |
|---|---|
| Steps | Optional steps never block. Some steps can be done in any order. Steps that need a higher level say "in 2 levels" and return when you get there. Quests that don't exist on WoW Forever are skipped by themselves. |
| "Only if you have it" steps | Some optional steps show only while an item is in your bags (for example "use the book if a kobold drops it"). If you loot it later, the step comes back. Optional turn-in and objective lines show only once their quest is in your quest log. In Elwynn, one short optional step (about 3 minutes, skip it any time) kills more kobold vermin until the Nibbled-On Book drops, because it starts a quest chain worth about 1,700 XP. |
| Skips | Skip a step, or say you're not doing a quest (its follow-ups drop out too). The Undo button or `/aog undo` takes back your last skips. |
| Item button | Above the window, to the right of the target button (on the left when it is the only one). It holds the quest item the step needs, or your hearthstone. It also shows an item that starts a quest (like the Nibbled-On Book) as soon as it is in your bags, with a yellow "!". It is offered on the steps before the step that uses it and shortly after, not only on that step. Click it to open the quest (you still press Accept); a plain mouse click works, also with the game's "cast on key down" option on. While you farm for such an item, it shows "Farming for: {item}". You click it; the addon never uses anything by itself. In combat it stays as it is and catches up right after. Setting: Guide window > "Item button" (on by default). `/aog selftest` says why the button is hidden. |
| Step notes | A short dim line under the current step's goals says why the guide does it. At most two lines; a longer note ends in "..." and the whole text is in the step's tooltip. When the window can't grow (in combat, at the top of the screen), the note waits. Setting: Steps > "Step notes" (on by default). |
| Item pictures | The guide window shows an item's own game icon on the current step only, never on the next-step lines or in step tooltips. The icon is a small tile at the left of the note line under the step (like the kill X on goal lines), and at the left of the step text only when that line has no step icon (next to the 3D view). Goal lines show the item icon instead of the small square. The item's name in the step text and the note is a coloured name: hover it to see the game's item tooltip (clicking does nothing). Items a step only names in its text (like the Nibbled-On Book) get their picture too, and so do items new in WoW Forever. Setting: Steps > "Item pictures" (on by default). Item names come from the game, or from CMaNGOS (GPL) data before the game has loaded the item. |
| "Use it now" reminders | The step button glows (and gently pulses) when the target is in range, when you are at the spot, or right after you loot the item. In the menu: off, glow, glow and text, or glow, text and sound (sound is off unless you pick it). |
| Hints | Hearthstone (ready now or in N minutes; a warning if it is set to another inn than the route expects) and flight paths (new one here, one you lack, which place to pick on the flight map). Known flight paths are remembered per character. |
| Arrow | One arrow for everything: your corpse after you release, then a spot another addon asks for, then a spot you picked, then the step. It turns green when you face it, yellow to the side and red behind, and shows distance as walk time or yards. |
| Smart arrow | When the spot is inside a building, cave or city, the arrow first leads to the middle of the door, cave mouth or gate. See [Smart arrow](#smart-arrow). |
| Path line | The way the arrow leads you (through doors and cave mouths, or straight when there is no door) shows as dots on the world map and the minimap. See [Path line](#path-line). |
| Corpse arrow | Right after you release, the arrow points to your corpse, also when the graveyard is in the next zone. There is no corpse arrow when the corpse is on another continent. |
| Quest items | Tells you when a looted item starts a quest, and gives advice for each quest item in your bags. See [Quest items](#quest-items). |
| First Aid | With First Aid learned, optional lines say what bandages to make and when to train. See [First Aid](#first-aid). |
| Map pins | Pins for the current step only (an any-order group's other open stops too, at most 12) on the world map and the minimap, in the same colours as the step icons. Minimap pins follow you smoothly as you move. Click one to point the arrow there. Each kind can be turned off in the menu. |
| Guide window | One window with the zone, the current step, the next steps, info chips and a progress bar, in a black and red look with rounded corners. See [The guide window](#the-guide-window). |
| Target button | An extra button that targets the mob your step names (English game only). See [Target button](#target-button). |
| Quest giver check | If a quest NPC doesn't offer a quest the guide wants, the guide skips it for now. See [Quest giver check](#quest-giver-check). |
| Time left | A chip shows how long the rest of the guide should take. It learns your own pace. |
| "On the way" goals | Kill and loot goals you can do while walking show under the current step. See [On the way goals](#on-the-way-goals). |
| NPC talk helper | In an NPC's quest list, quests your route takes get a small tag and the rest can be faded. See [NPC talk helper](#npc-talk-helper). |
| Tooltip step line | Mobs, NPCs and objects that are part of your current step get one line on their tooltip. See [Tooltip step line](#tooltip-step-line). |
| Guide menu | One window for guides, settings, quest items, reports and About. See [The guide menu](#the-guide-menu). |
| 3D view | The NPC or mob of your current step turns as a 3D model, by default inside the guide window. See [3D view](#3d-view). |
| Mob areas | On kill and collect steps the arrow leads you to the nearest spot where the mobs spawn and you haven't cleared yet. See [Mob areas](#mob-areas). |
| Ghost | Walking as a ghost doesn't tick travel steps. |
| Full quest log | Shows which quests the route doesn't need. |
| Travel steps | Fly, hearthstone, get a flight path, set your hearthstone, learn, train, use an item, notes, and grind as a last resort. |

The route packs for levels 1-20 are not in this beta yet.

### The guide window

From the top:

- The zone.
- The current step: the 3D view on its left, the verb in colour, "for <quest>", the place with coords and distance, and its goals underneath. The goal to do now is marked red.
- The next steps (3 by default; the bottom edge or "Next steps shown" changes it). Each is one line: a framed tag in the step's colour (TURN IN, ACCEPT, KILL, GO TO ...), what it is about, and the coords at the right. A long name is cut with "...". Hover a line for the NPC and the place. Each line is a bit fainter than the one above.
- Info chips: guide, level / XP and time left.
- Back, a progress bar ("step 14 / 53 · 26 %") and next.

How it behaves:

- A tall step makes the window grow up (its bottom edge stays). It shrinks back on the next step. Changing the window size or "Next steps shown" keeps the top of the window on screen.
- Finished goals fold into one "3 done" line (click to open). A goal that just finished flashes green first.
- Drag the right edge to make it wider or narrower, the bottom edge to show more or fewer coming steps, or the bottom-right corner to change both. Not while locked or in combat, and not in small mode. Size is saved per character.
- Default background opacity is 90 % (Settings > Guide window: "Background").
- The window looks the same in and out of combat. It stays put at login, also when its scale isn't 100 %.

### Target button

- English game only. Setting: Settings > Guide window > "Target button" (on by default), and its own key binding.
- A button above the window, on the left (the item button is to its right). When you press it, it targets the mob the step names (`/targetexact`).
- Its tooltip says "Click to target it (when it's in range)".
- It never targets by itself and only changes outside fights.
- Mob names come from CMaNGOS data (GPL).

### Quest giver check

- Setting: Settings > Steps > "Skip quests not offered yet" (on by default).
- When you talk to a quest NPC and a quest the guide wants isn't in their list, the guide skips that quest and its follow-ups for now and shows a short notice. It brings the quest back when it may be ready.
- The guide knows the levels of most route quests (CMaNGOS data), so grey quests of an overlevelled character are never marked "not offered yet".
- The notice's menu has "Show it again", and "Report" fills in a report draft that you send yourself.
- The quest comes back by itself when the NPC offers it later, after a level up (only if you are near), or after a hand-in that may unlock it.

### On the way goals

- Kill and loot goals you can do while walking show under the current step with a live count (for example 3/8) and a kill, loot or use icon.
- At most 3 lines show, then "+n more on the way". Hover the step to see them all.
- Finished parts get a tick and stay until the whole goal is done.
- A goal stops showing when you reach the step that does the same work, and hides while its quest isn't in your log.
- Only quest progress is counted, never kills from the combat log.
- A walk is not skipped just because the "as you go" goal right after it is already done.

### NPC talk helper

- In an NPC's quest list (gossip and quest greeting), quests your route takes get a small tag: "Route: step 14", "Turn in: step 9" or "In a later guide". Quests not on your route are faded.
- Under the accept window one line says "On your route: step 14, ~450 XP", "Not on your route", "Skipped on your route: ..." or "Not on this route: in <guide>".
- Hints only. It never clicks, accepts or closes anything, and every quest stays clickable.
- Setting: Settings > Steps > "Mark route quests at NPCs": Off, Mark, or Mark and dim (default).
- Addons that replace or reskin the quest and gossip windows may hide the tags or the line. Nothing breaks.

### Tooltip step line

- Hover a mob, NPC or object that is part of your current step and its tooltip gets a last line, for example "Step: Kobold Vermin slain 4/10", "On the way: Young Wolf slain 0/4" or "Step: Accept <quest>". A finished goal says "(done)".
- It matches by the NPC id in the step or by the goal's name. Loot-only goals show only when the step names the mob.
- If the tooltip already shows the quest (the game's own quest lines, or Questie is installed), the line is short: "Part of your step" or "Do this on the way".
- Hints only. Nothing else happens on hover.
- Setting: Settings > Steps > "Step line on tooltips": Off, Short (no counts) or With counts (default).

### The guide menu

Open it with `/aog`, right-click the minimap button, left-click the menu button in the guide window's title bar, or "Open guide menu" in the options menu. It opens on the page you used last. Pages:

| Page | What it has |
|---|---|
| Guides | Every installed guide as a card with its levels, steps and how far you got. **Switch** changes guide. Search, and Alliance / Horde / Coming soon filters. Guides still being written show as "Coming in vX". |
| Settings | General, Guide window, Arrow, Map pins, Steps and Advanced, with sliders and drop-downs. |
| Quest items | Advice for each quest item in your bags. |
| Report a mistake | See [Report a mistake](#report-a-mistake). |
| About | Version, licence, links and credits. |

Options > AddOns > All-in-One Guide has one button that opens the guide menu. The small options menu is short; the rest is in Settings.

Settings that move the guide window (width, scale, follow UI scale, "Reset this page" on Guide window, `/aog resetpos`) wait until a fight is over and say so in chat, so the step button stays in place.

### Smart arrow

The smart arrow is on by default. Switch it in the arrow's right-click menu or on the Arrow settings page.

- While it leads to a door, cave mouth or gate first, the arrow is light blue. Under it is a line like "Through the abbey door", and "Goal: 214 yd".
- The arrow gives one short pulse when you pass a door (not with "Stop flashing and pulsing", and not when it points straight).
- "Point straight at the goal" in the arrow's right-click menu turns it off for that one spot.
- It knows these places so far: Northshire Abbey, Echo Ridge Mine, Fargodeep Mine, Jasperlode Mine, the Goldshire inn, the Den and Burning Blade Coven in the Valley of Trials, Dustwind Cave, Skull Rock, the Razor Hill inn, and the main gates of Stormwind and Orgrimmar. Their positions are first estimates and get better as testers check them.
- It only shows the way. It never moves your character.

### Path line

- The arrow's way (through doors and cave mouths to the goal, or a straight line when there is no door) shows as a dotted line on the world map and a solid line on the minimap. The solid line is easy to tell apart from the dotted loop round mob areas.
- While you are led round a mob area, the minimap line from you to the next loop point is solid like every other go-to line. Only the loop itself is dots, and they stay steady while you walk.
- The minimap line follows its zoom, rotation and shape (square minimaps too) and stops at its edge.
- Two switches in Settings > Map pins: "Path line on the world map" and "Path line on the minimap". Both are on by default.

### 3D view

- The NPC or mob of your current step shows as a 3D model, by default inside the guide window: a square at the top left of the current step, with the step text beside it. Steps without a model show a small "No 3D model for this step" card.
- Drag it to turn the model, use the mouse wheel to zoom, double-click to reset, right-click for options.
- Settings > Guide window: "Show the 3D view", "3D view position" (inside the window, left, right, below or free; Shift+drag it when free), "3D view size" and "Hide the 3D view in combat" (on by default; this applies to the outside positions, inside the window it stays during fights).
- Switch it on or off with the options menu or `/aog model`.

### Mob areas

- On kill and collect steps the arrow points at the nearest spot where the mobs spawn that you haven't cleared yet (you were there and walked away). The arrow is orange and says "Kill as you go: spot 2 of 6". The path line follows it.
- A cleared spot turns grey until its mobs respawn. The respawn time is an estimate, shown with "~".
- Dots for the spots show on the world map and the minimap (Settings > Map pins: "Spawn spots on the world map" and "Spawn spots on the minimap", both on by default).
- In combat the arrow keeps its spot.
- Settings > Arrow: "Lead me round mob areas" (on by default) and "Spawn spot order": Mixed (default: the guide's loop, with its "spot 1 of 6" counter, wherever a step has one; spots where it has none), Nearest spot, or Loop. In the arrow's right-click menu: "Lead me round the mob area" on or off, "Spawn spot order: {mode}" (changes the order), and "Point at the middle instead".
- When every spot is cleared, the arrow says "All cleared: they respawn here in ~N min".
- Loops so far: the Northshire kobolds (the camp and Echo Ridge), and the Valley of Trials boars and vile familiars.
- Spawn spots and respawn times come from CMaNGOS classic-db (GPL), so WoW Forever's spawns may differ a little.

### Quest items

- When you loot an item that starts a quest, the hint line says "This starts a quest: right-click it". When the guide knows the quest, it also says where to hand it in and the XP. This shows once per item and character.
- After login and on a level-up, the guide gives one piece of advice for each quest item in your bags: **Do it now**, **Keep for later**, **Bank it** (it can't be got again), **Safe to delete** (quest done, or grey and it drops again) or **Keep it** (unknown). An item whose quest is in your log is never called safe to delete.
- The full list is on the guide menu's "Quest items" page.
- The guide never uses, moves or deletes items. You do that yourself.

### First Aid

With First Aid learned, the guide shows optional lines under the current step, for example:

- "Optional: make 12 Linen Bandage (First Aid 10 to 22)", when your cloth allows it;
- "Optional: train Journeyman First Aid at the trainer in ...", when you reach a training point.

The skill caps and costs are not yet checked on WoW Forever. The guide never crafts or trains for you. Turn the lines off with General > "First Aid steps".

## Install

Use your addon manager and switch it to the **beta channel** for All-in-One Guide. Then install or update as usual. To go back to normal releases, switch the channel back to stable.

The addon is one folder, `AllinOneGuide`. It sends nothing itself (see [Your data](#your-data)).

## Use it

The first time you log in, the addon opens the guide only if it starts where your character starts. Otherwise the window says no guide is open and lists the guides you can open. If a longer route for your start is installed later, a character on the demo guide is asked once whether to switch (progress comes along).

If v0.1 gave a character the guide for another start area (for example a gnome on the Elwynn guide) and it hasn't been started, it is closed once at login with a chat line, and the right guide opens (or the list of guides shows). Guides you opened yourself, or made progress in, are never closed.

- `/aog` opens the [guide menu](#the-guide-menu). `/aog show` shows or hides the guide window. Esc never closes the guide window.
- Drag the title bar to move the window. The padlock locks it. The minus button switches to a small window (the current step and one next line).
- The menu button in the title bar: left-click opens the guide menu, right-click opens the options menu (also on a right-click of the title bar): open guide menu, choose a guide, settings, report a mistake, small mode, lock, quiet mode and a few more.
- Hover a step for its quest, zone, coordinates and why it waits. Click it to point the arrow there. Shift-click puts the quest link into an open chat box (it is never sent). Ctrl-click opens the map there.
- Right-click a step for skip, make current, not doing this quest, point the arrow here, or copy a `/way` line.
- Right-click the arrow for skip, hide until the next step, clear a picked spot, smart arrow, lock, size, opacity, click-through and arrival sound (off). The mouse wheel changes its size. Alt+drag moves it while it is locked.
- Right-click a hint for "Later" (1 hour, this session, tomorrow), or to hide it on this character or hide hints like it.

### Minimap button

A button on the minimap. Drag it around the minimap. It follows square and other minimap shapes from minimap addons. Left-click shows or hides the guide, right-click opens the guide menu. `/aog minimap` shows or hides the button. With a minimap button-bar addon (one that collects the buttons of other addons), the guide's button goes into that bar. Without one, the button stays on the minimap with its own name, so bars that collect named minimap buttons can take it. If another addon already provides a data-broker display, the guide shows up there too.

### Look of the windows

The guide menu, dialogs, copy box and menus are almost solid, so they are easy to read over a bright world. The guide menu opens on top of the game's Options window.

### Settings

`/aog config` opens the Settings pages in the guide menu: General, Guide window, Arrow, Map pins, Steps and Advanced. Each setting has a tooltip with its default. Sliders take the mouse wheel only after you click them once (until then the wheel scrolls the page). "Reset this page" resets only that page. Among them: language, use the guide on this character, hide it in battlegrounds and raids, First Aid steps, which chat window gets messages, window size, steps shown, text size (-4 to +4, default +2; the window keeps its top-left corner while you drag it), text font (see [Text font](#text-font)), high contrast, colour-blind colours and the smart arrow.

### Text font

Settings > Guide window > "Text font" sets the guide's font:

| Choice | What it is |
|---|---|
| Open Sans (default) | A clean, modern font. |
| Easy-read (dyslexia) | A font made to be easier to read with dyslexia. It is wider, so long steps are cut sooner. |
| Classic | WoW's own Friz Quadrata. |

Game languages with other alphabets (Russian, Korean, Chinese) keep the game's own font.

### Language

Choose English, Dansk or "Same as the game" under General > Language, or with `/aog lang`. The game doesn't let addons reload the UI, so type `/reload` yourself to switch.

### Key bindings

Under "All-in-One Guide" in the game's key binding page: show or hide, next, previous, skip, use the step's item, target the step's mob, arrow on or off, and menu. The addon sets no keys itself.

### Other addons

If you also run Questie, TomTom, Guidelime or Mapster, one quiet hint says so, once. If Questie draws its own pins, the hint has a button to hide ours. If the Gear Set addon is installed, the options menu has "Link with Gear Set" (on by default). Other addons can read the current step through the read-only `AllinOneGuide.API` (version 1) and can point the arrow with it.

`/way 45.2 61.8` (or `/way <map id> x y name`, `/way clear`) points the arrow. If another addon already has `/way`, ours stays off and `/aog way` works instead.

## Slash commands

| Command | What it does |
|---|---|
| `/aog` | Open the guide menu |
| `/aog show` | Show or hide the guide window |
| `/aog guides` | Open the guide list in the guide menu |
| `/aog help` | Show the main commands (`/aog help all` shows every one) |
| `/aog guide` | List the guides. `/aog guide elwynn` or `/aog guide durotar` opens one |
| `/aog skip` | Skip the current step (it is remembered) |
| `/aog undo` | Take back your last skips |
| `/aog back` | Go back one step |
| `/aog way 45.2 61.8` | Point the arrow at a spot (same as `/way`) |
| `/aog hub` | Open the guide menu (same as `/aog`) |
| `/aog report` | Open Report a mistake |
| `/aog config` | Open the settings |
| `/aog minimap` | Show or hide the minimap button |
| `/aog model` | Show or hide the 3D view |
| `/aog where` | Print your map id, zone and position, the selected quest's id and your target's NPC or object id |
| `/aog restore` | Put back the saved-data backup (asks first; then type `/reload`) |
| `/aog resetpos` | Put the window and the arrow back in their start places |
| `/aog lang en`, `da` or `auto` | Choose English, Danish or follow the game (then type `/reload`) |
| `/aog status` | One line with version, client, self-test result and switched-off features |
| `/aog selftest` | The addon checks itself (`/aog selftest full` checks more) |
| `/aog debug on`, `off` | Switch the debug log on or off (`/aog debug` shows it) |
| `/aog error` | Details of the last error |

## Report a mistake

1. Open the Report page (`/aog report`, or "Report a mistake" in the options menu).
2. Pick what is wrong ("Wrong place on the map", "Wrong order", "Quest isn't there", "Step doesn't tick", "Text is wrong", "Dangerous spot" or "Something else") and which step (the current one or one of the last three). Add a note if you like. You can add the NPC you target. `/aog where` helps.
3. Press **Send**. The report is saved, and the Addon Manager (v0.21.0 or newer) sends it the next time the game is closed. It becomes a public GitHub issue. You can turn this off in the Addon Manager's settings ("Send guide reports").

You can also copy the report and paste it in a new issue with the **Mistake report** form: https://github.com/gettic/All-in-One-Guide/issues/new/choose

Saved reports wait in the outbox (up to 40). If the outbox is full with reports from this session, it says so.

- If the guide is open but has no step to pick, the page says so.
- Reports are public on GitHub. The report holds no character name, realm or other personal data, so please don't write names in the note.
- Your map position is in the report unless you tick "Leave out my location".
- The last 20 reports are kept so you can copy one again.

For a bug in the addon itself, use the **Addon bug** form: run `/aog selftest`, then `/aog status`, and paste the lines. If the addon hit an error, `/aog error` shows the details.

## Your data

The addon itself sends nothing. Only reports you press **Send** on are sent, by the Addon Manager. The addon saves its settings and your progress in `AllinOneGuideDB` (account) and `AllinOneGuideCharDB` (per character). Before saved data is updated to a new version, a backup is made; `/aog restore` puts it back, and it goes away by itself a few logins later. If a character gets a paid name change, the guide asks once whether to move the old name's progress to it ("Move" or "Start fresh"). If loading fails twice in a row, the addon starts once in safe mode (defaults, saved data untouched). Numbers and dates follow the language.

## For people who change the code

| Folder | What is in it |
|---|---|
| `AllinOneGuide\` | The addon. Load order is in `AllinOneGuide_Forever.toc` |
| `AllinOneGuide\Routes\` | Compiled guide packs and smart arrow data (`Connectors.lua`). Generated: never edit by hand |
| `packs-src\` | Readable guide pack sources. The format is in `packs-src\FORMAT.md` |
| `packs-src\connectors\` | Smart arrow doors, caves and gates per area (FORMAT.md section 8) |
| `tools\` | The pack checker, the build script, the connector tool (`connectors.lua`), the text checker (`textlint.lua`), `packdiff.lua`, `recmerge.lua` and the data importer (`import\`) |
| `art-src\` | Scripts that draw the addon's own art (`MANIFEST.md` lists it) |
| `.github\ISSUE_TEMPLATE\` | The bug report and mistake report forms |

- **Build a pack:** edit a file in `packs-src\`, then run `powershell -NoProfile -File tools\build.ps1`. It needs LuaJIT (`luajit` on the PATH, or `-LuaJit <path>`). The checker runs first, then the compiled files are written to `AllinOneGuide\Routes\`. `-Check` writes nothing and fails if a compiled file is out of date.
- **Checks:** the Lua is checked with luacheck, and the addon is run against a fake game world in offline test scenarios. Both are kept by the maintainer and are not in this repo.
- **Pack format:** guide pack format 2 is in `packs-src\FORMAT.md`. Conditions can test bag items (`item=<id>`, only on optional steps) and First Aid skill (`skill=firstaid>=50`). `tools\packcheck.lua` also warns about route mistakes (turn-in before accept, full log, hearth before setting it, the same dungeon too often). `tools\textlint.lua` checks our own texts (length, banned words, signs of copied text); a pack can set `strict = true` to make its findings errors.
- **Trial build:** `tools\build.lua --out <folder>` builds to another folder and skips packs that aren't in the `.toc` yet. `--all` builds them too.
- **Importer:** `tools\import` reads other projects' data as data only and keeps a record only when its licence and origin allow it (`--provenance <file>`).
- **Facts in packs:** every fact has a source. Ones from the Warcraft Wiki are marked `wiki`.

## Credits

Quest facts (ids, coordinates, levels) in the demo routes come from the [Warcraft Wiki](https://warcraft.wiki.gg), by its contributors, under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The facts are restated in our own words; no wiki text or images are copied. The full list of pages is in `AllinOneGuide\CREDITS.txt`.

[CMaNGOS classic-db](https://github.com/cmangos/classic-db), GPL-3.0: some NPC positions, quest giver and turn-in ids, creature spawn areas (grid-snapped), city gate object positions (smart arrow), quest item ids and loot / vendor sources, and model display ids were checked against or derived from this database. Game facts in it come from World of Warcraft, (c) Blizzard Entertainment; they are not covered by our GPL licence and are used only as reference facts in a free, non-commercial addon. Not affiliated with or endorsed by CMaNGOS or Blizzard.

[ForeverDB](https://foreverdb.net/): some quest ids, levels, XP, prerequisites, NPC ids and quest item ids for quests only on WoW Forever, used as reference facts. ForeverDB states no licence for its data; no texts were copied. Not affiliated with ForeverDB or Blizzard.

Fonts: [Open Sans](https://github.com/googlefonts/opensans) (Copyright 2020 The Open Sans Project Authors) and a renamed copy of [OpenDyslexic](https://github.com/antijingoist/opendyslexic) by Abbie Gonzalez (shown as "Easy-read"; the original name is reserved, so our copy has its own). Both are under the SIL Open Font License 1.1; the notices are in `AllinOneGuide\media\fonts\OFL.txt`.

World of Warcraft and its content are trademarks and copyrights of Blizzard Entertainment. This addon is not made or endorsed by Blizzard Entertainment.

## Licence

All-in-One Guide, Copyright (C) 2026 gettic. Free software under the GNU General Public License, version 3 or (at your option) any later version (GPL-3.0-or-later). See `LICENSE`. There is no warranty. The source for each release is the matching tag at https://github.com/gettic/All-in-One-Guide.
