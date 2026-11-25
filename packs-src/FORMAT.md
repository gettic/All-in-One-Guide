<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 gettic -->
# All-in-One Guide pack format, version 1

This is the format of the guide packs. The readable **sources** live here in `packs-src\` (public, GPL-3.0-or-later).
`tools\build.ps1` compiles them into **readable rows** in the addon (`AllinOneGuide\Routes\*.lua`). The compiled
rows are never compressed, packed or encoded: one plain text line per step. `tools\packcheck.lua` checks both,
using the addon's own parser (`AllinOneGuide\Packs\Format.lua`, `Conditions.lua`).

Packs are **data, never code**. A source file is one Lua table and nothing else (the build loads it with an empty
environment, so it can't call anything). The addon never runs `loadstring`.

## 1. A source file

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- Contains facts from warcraft.wiki.gg (CC BY-SA 4.0), see CREDITS.txt
return {
    id = "demo-elwynn",                 -- pack id: lowercase letters, digits, "-"
    file = "Elwynn",                    -- compiled file name: AllinOneGuide\Routes\Elwynn.lua
    title = "Elwynn Forest 1-6", da = "Elwynn Forest 1-6",
    author = "All-in-One Guide",
    category = "leveling",              -- leveling | dungeon | profession | reputation | other
    kind = "route",
    faction = "Alliance",               -- Alliance | Horde | Neutral
    levels = { 1, 6 },
    conditions = "faction=Alliance",    -- who the pack is for (grammar, section 5)
    entry = "race=Human",               -- start-area entry condition (used from v0.3)
    formatVersion = 1, minFormat = 1,   -- format this pack is written in / oldest format that can read it
    version = "0.1.0",
    license = "GPL-3.0-or-later",
    source = "packs-src/elwynn.lua at the matching GitHub tag",
    credits = { "https://warcraft.wiki.gg/wiki/..." },   -- one URL per wiki page used
    renamedSteps = { ["eln-004"] = "eln-004a" },          -- old id -> new id (saves follow the rename)
    retiredSteps = { "eln-009" },                         -- ids that are gone; never used again
    blocks = {                                            -- shared step blocks for `include`
        letter = { { id = "acc", type = "accept", quest = "{q}", text = "Accept the letter" } },
    },
    routes = {
        { id = "normal", title = "Normal", da = "Normal", sections = {
            { title = "Northshire", da = "Northshire", steps = {
                { id = "eln-001", type = "accept", quest = 783, npc = 823, map = 1429, x = 48.2, y = 42.1,
                  text = "Accept {quest}", da = "Tag imod {quest}", src = "wiki", seen = "2026-11", confirmed = false },
                { include = "letter", id = "eln-war", params = { q = 1234 }, cond = "class=WARRIOR" },
            } },
        } },
    },
}
```

## 2. Step fields

| Field | Meaning |
|---|---|
| `id` | **stable** id, lowercase `a-z 0-9 - .`, unique in its route after includes are expanded; never the list position; never reused (see `retiredSteps`). `:` is reserved for detour ids (`<kind>:<id>:<n>`). |
| `type` | `accept`, `turnin`, `objective`, `goto`, `level` (v0.1). An unknown type is shown as a plain manual step. |
| `quest` | quest id (accept, turnin, objective) |
| `npc` | NPC id (who to talk to / what to kill); names are never stored, the step text says it in our words |
| `map`, `x`, `y` | `uiMapId` and coordinates in percent (0-100, at most 2 decimals). Optional on `accept`, `turnin`, `objective` and `level` steps: a step without them simply has no arrow (the text says where, e.g. "wolves around the valley"); it still ticks by itself. Required on `goto`. |
| `r` | radius in yards for `goto` / `leaveArea` (empty = 10). `r = 0` on a `goto` means no arrow and no auto-complete (the player moves on by hand); not needed on steps that have no spot. |
| `text`, `da` | short step text in our own words (verb + target + count + place), English and Danish. `{quest}` is replaced by the quest name from the game (fallback: `qname`). No `|`, no line breaks. |
| `flags` | list of words: `elite`, `group`, `deadly`, `ahStep`, `tradeStep`, `extra`, `future`, `noAutoAccept`, `walk`, `leaveArea`, `grind` |
| `cond` | when the step applies (grammar, section 5). Checked while playing, so ids stay the same for every character. |
| `src` | where the facts come from: `own, rec, lookup, wiki, client, questie, forevdb, codex, cmangos, lpdb, att, legacy`. Steps with no looked-up fact (e.g. `level` steps, our own route choices) use `own` and need no `seen`. |
| `seen`, `confirmed` | when the fact was looked up (`YYYY-MM`); `confirmed = false` until the recorder / reports confirm it on Forever |
| `obj` | objective step: which quest objectives count (`{ 1, 2 }`; empty = all) |
| `any` | objective group: done when any `any` of the listed objectives are done |
| `override` | goal grammar: the step is also done when this is true (e.g. `done=812 or inlog=813`) |
| `whileUntil` | background goal: shown next to the current step until the step with this id is reached; there it must be done |
| `leadsTo` | travel step (`goto`): auto-skips when the step it leads to is already done (empty = the next non-travel step) |
| `why` | required on every `grind` step and every return to a zone left earlier (route rules) |
| `level` | `level` step: the level to reach |
| `item`, `count` | objective step without a quest objective: have `count` of `item` in the bags |
| `useItem`, `targetNpc`, `model`, `useWhen`, `classQuest` | accepted and kept (used from v0.2 on) |
| `qname` | our short fallback name for the quest while the game hasn't loaded its name |
| `knownIssue` | accepted from v0.2 |

### Includes

`{ include = "<block>", id = "<prefix>", params = { ... }, cond = "..." }` expands the block in place. Every
expanded id is `<prefix>.<block step id>`; `{name}` in any block field is replaced by `params.name`; the include's
`cond` is joined to each step's with `and`. Includes may include other blocks, at most 4 deep. A missing block
is a build error. Block names are any Lua name (letters, digits, `_`; camelCase is fine); they never appear in
step ids. A `{name}` that is the whole field value keeps the parameter's type (`x = "{x}"` with `x = 50.4` gives
the number 50.4). Each expanded step's compiled row carries `inc=<block>@<params>` in `extra` (a trace for the
checker and bug reports; the addon ignores it).

The header `conditions` apply to the whole pack: they are not copied into each row's `cond`. The addon checks them
when it picks or lists packs for the character (v0.1: the faction-picked demo route).

## 3. Compiled file (`AllinOneGuide\Routes\<file>.lua`)

```lua
-- (SPDX header, wiki line, "compiled by tools\build.ps1 from packs-src\elwynn.lua; do not edit")
-- row fields: id|type|quest|npc|map|x|y|r|text|da|flags|cond|src|extra
local _, ns = ...
ns.Packs.Register({ id = "demo-elwynn", ... header ... }, {
    { id = "normal", title = "Normal", da = "Normal",
      sections = { "1|Northshire|Northshire" },          -- first row|title|da
      rows = {
        "eln-001|accept|783|823|1429|48.2|42.1||Accept {quest}|Tag imod {quest}||faction=Alliance|wiki|seen=2026-11;confirmed=0",
      } },
})
```

- The header is the source header without `routes`, `blocks`, `file` and `credits` (the credits are in
  `AllinOneGuide\CREDITS.txt`; the build fails when a URL is missing there).
- One string per step, 14 fields separated by `|`. Empty field = not set. Numbers are written plainly
  (`48.2`, no exponent). `flags` is comma-separated.
- `extra` holds the less common fields as `key=value;key=value` (keys sorted, lists comma-separated, booleans 1/0).
- Escaping in any field: `%` -> `%25`, `|` -> `%7C`, `;` -> `%3B`, `=` -> `%3D` (only in `extra` values),
  line breaks are not allowed. Nothing else is escaped; the checker fails on long encoded-looking strings.
- One row array per route; modes (from v0.3) are filter flags on the same rows. A mode gets its own route
  only where its path really differs.

## 4. Reading packs (addon side)

- `ns.Packs.Register(header, routes)` is the only entry point. Headers are read at login; rows are decoded only
  when a guide opens, a window at a time, through **one accessor** `ns.Packs.GetStep(route, index)` (frozen step
  tables). Nothing else reads rows.
- **Forward compatible:** a pack with `formatVersion` newer than the addon loads if `minFormat` is not newer;
  unknown fields are ignored, an unknown step type becomes a manual step, an unknown condition word makes the step
  "not applicable". A pack whose `minFormat` is newer is refused with "needs a newer All-in-One Guide".
- Saves keep progress by step id. On load, ids in `renamedSteps` are followed; skips of `retiredSteps` are kept
  in the save but ignored.
- Imported packs (v0.8) are stored as the pasted text, parsed into a cache kept in memory only.

## 5. Condition grammar (data, never Lua)

```
expr   := term { "or" term }
term   := factor { "and" factor }
factor := "not" factor | "(" expr ")" | atom
atom   := key "=" value { "," value }        -- any of the values
        | key (">=" | "<=" | ">" | "<") number
```

| Key | Values | Read from |
|---|---|---|
| `level` | number (`=`, `>=`, `<=`, `>`, `<`) | the player's level |
| `class` | class file names (`WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`, `WARLOCK`, `DRUID`) | client |
| `race` | race file names (`Human`, `Dwarf`, `NightElf`, `Gnome`, `Orc`, `Scourge`, `Tauren`, `Troll`, Forever races as the client names them) | client |
| `faction` | `Alliance`, `Horde`, `Neutral` | client |
| `sex` | `male`, `female` | client |
| `prof` | profession name | not read in v0.1: counts as true |
| `flag` | a named flag set by the player's mode / filters (`hardcore`, ...) | our settings |
| `spec`, `role` | reserved in format v1; count as true until v0.4 | - |
| goal words (only in `override` and checker goals): `done`, `inlog`, `ready`, `item` | `done=812`, `inlog=813`, `ready=813`, `item=750:3` | game state |

Conditions are parsed once and cached; they are evaluated while playing. A word the addon doesn't know makes
the step not applicable (packs from newer versions keep working).

## 6. Checks (`tools\packcheck.lua`)

Errors stop the build: duplicate or malformed ids (after includes), a missing block, include depth over 4, a
`renamedSteps` source that still exists or target that doesn't, a reused retired id, missing fields for the type,
coordinates outside 0-100, a condition that doesn't parse or uses an unknown word, a `src` not on the list, a `wiki`
fact without `seen` or without `confirmed`, a step text that doesn't start with a capital letter, a `grind` step or a zone return without `why`, a known-exploit id
(`packs-src\known-exploits.lua`), an encoded-looking string, a never-use word, a `|` or line break in a text,
`da` text with different `{placeholders}` than `text`, a `whileUntil` / `leadsTo` target that isn't a later step.
Reported (not errors in v0.1): total grind steps, travel per map in map percent, zone changes, backtracking, texts
over 90 characters, texts that don't start with a known verb.
