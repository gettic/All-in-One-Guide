# All-in-One Guide

One leveling guide addon with one guide window and a waypoint arrow. It can hold many guides as guide packs, so you only need one guide addon in game.

Made for WoW Forever (interface 16001). Version: 0.1.0-beta.1.

## What you get in this beta

This is a beta. It has two demo routes:

| Route | Faction | Levels |
|---|---|---|
| Elwynn Forest (Northshire to Goldshire) | Alliance | about 1-6 |
| Durotar (Valley of Trials to Razor Hill) | Horde | about 1-6 |

- Both routes include each class's starting letter, and neither one grinds.
- The guide follows the game itself (quest log, finished quests, level, bags, position). It only remembers which step you are on, and your skips.
- The guide window shows the current step and the next ones. The arrow points to the spot. It turns green when you face it, yellow to the side and red behind. It shows the distance in yards.
- Quest facts come from the Warcraft Wiki and are not yet confirmed on WoW Forever. If a step looks wrong, please report it.
- Texts are in English and Danish.

## Install

Use your addon manager and switch it to the **beta channel** for All-in-One Guide. Then install or update as usual. To go back to normal releases, switch the channel back to stable.

The addon is one folder, `AllinOneGuide`. Nothing leaves your PC.

## Use it

The first time you log in, the addon opens the guide that fits your character and says so in one chat line. Above level 6, or if no guide fits, it tells you how to pick one.

- `/aog` opens or closes the guide window. Esc never closes it.
- Drag the title bar to move the window. The padlock locks it. The minus button switches to a small window.
- Right-click the title bar (or click the menu button) for small mode, lock, quiet mode, the arrow, less motion, background opacity and reset positions.
- Right-click a hint to put it off for later, hide it on this character, or hide hints like it.

## Slash commands

| Command | What it does |
|---|---|
| `/aog` | Open or close the guide window |
| `/aog help` | Show the main commands (`/aog help all` shows every one) |
| `/aog guide elwynn` or `/aog guide durotar` | Open a guide by hand |
| `/aog skip` | Skip the current step (it is remembered) |
| `/aog back` | Go back one step |
| `/aog resetpos` | Put the window and the arrow back in their start places |
| `/aog lang en`, `da` or `auto` | Choose English, Danish or follow the game (takes a reload) |
| `/aog status` | One line with version, client, self-test result and switched-off features |
| `/aog selftest` | The addon checks itself (`/aog selftest full` checks more) |
| `/aog debug on`, `off` | Switch the debug log on or off (`/aog debug` shows it) |
| `/aog error` | Details of the last error |

## Report a mistake

1. Run `/aog selftest`, then `/aog status`. Copy the lines they show.
2. Open a new issue with the **Addon bug** form: https://github.com/gettic/All-in-One-Guide/issues/new/choose
3. Paste the lines and say what you saw.

The issue page is public. The lines from the addon hold no character, realm or guild names. Please don't add them yourself. If the addon hit an error, `/aog error` shows the details to paste.

## Your data

Nothing is sent anywhere. The addon saves its settings and your progress in `AllinOneGuideDB` (account) and `AllinOneGuideCharDB` (per character). If loading fails twice in a row, it starts once in safe mode (defaults, saved data untouched).

## For people who change the code

| Folder | What is in it |
|---|---|
| `AllinOneGuide\` | The addon. Load order is in `AllinOneGuide_Forever.toc` |
| `AllinOneGuide\Routes\` | Compiled guide packs. Generated: never edit by hand |
| `packs-src\` | Readable guide pack sources. The format is in `packs-src\FORMAT.md` |
| `tools\` | The pack checker and the build script |
| `art-src\` | Scripts that draw the addon's own art (`MANIFEST.md` lists it) |
| `.github\ISSUE_TEMPLATE\` | The bug report form |

- **Build a pack:** edit a file in `packs-src\`, then run `powershell -NoProfile -File tools\build.ps1`. It needs LuaJIT (`luajit` on the PATH, or `-LuaJit <path>`). The checker runs first, then the compiled files are written to `AllinOneGuide\Routes\`. `-Check` writes nothing and fails if a compiled file is out of date.
- **Checks:** the Lua is checked with luacheck, and the addon is run against a fake game world in offline test scenarios. Both are kept by the maintainer and are not in this repo.
- **Facts in packs:** every fact has a source. Ones from the Warcraft Wiki are marked `wiki`.

## Credits

Quest facts (ids, coordinates, levels) in the demo routes come from the [Warcraft Wiki](https://warcraft.wiki.gg), by its contributors, under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The facts are restated in our own words; no wiki text or images are copied. The full list of pages is in `AllinOneGuide\CREDITS.txt`.

World of Warcraft and its content are trademarks and copyrights of Blizzard Entertainment. This addon is not made or endorsed by Blizzard Entertainment.

## Licence

All-in-One Guide, Copyright (C) 2026 gettic. Free software under the GNU General Public License, version 3 or (at your option) any later version (GPL-3.0-or-later). See `LICENSE`. There is no warranty. The source for each release is the matching tag at https://github.com/gettic/All-in-One-Guide.
