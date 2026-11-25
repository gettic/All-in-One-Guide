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
| `type` | `accept`, `turnin`, `objective`, `goto`, `level` (v0.1); `learn`, `train`, `note`, `useitem`, `grind`, `fly`, `hearth`, `getfp`, `sethearth` (format 2, below). An unknown type is shown as a plain manual step. |
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

### Format 2 (v0.2)

Rows look the same as in format 1, so a pack using these writes `formatVersion = 2, minFormat = 1`: a v0.1 reader
shows the new types as plain manual steps and ignores the new keys.

| Type | Done when | Needs |
|---|---|---|
| `learn`, `train`, `note` | the player presses "next" (it ticks them as done, not skipped) | `text` |
| `useitem` | its quest objective is done (with `quest`), else "next" | `useItem` (v0.2 M2: the step button) |
| `grind` | the level is reached; shows a live XP goal line | `level`, `why` (last resort only) |
| `fly` | arrival within `r` (default 80) after the taxi lands, or "next" | `map`, `x`, `y`; `node` for the lint |
| `hearth` | arrival within `r` (default 100), or "next" | `map`, `x`, `y` |
| `getfp` | the taxi reader knows `node` (v0.2 M2), or "next" | `node` |
| `sethearth` | the bind location is `inn`, or it changed while the step was up, or "next" | `inn` (client language) |

| Field / flag | Meaning |
|---|---|
| `optional` (flag) | never blocks: passed over and shown as an "Optional:" goal line (at most 3 at once) |
| `anyOrder` | steps next to each other with the same `anyOrder` word can be done in any order; the nearest is shown first |
| `from` | where an accept comes from when it isn't an NPC (`item`, `object`); also quiets "turn-in before accept" |
| `pre` | quest ids this quest follows (`pre = { 783 }`): "not doing" a quest also drops its follow-ups |
| `xp` | the quest's XP (for the route test's XP model; `xp = 0` needs a `why`) |
| `estMin` | minutes the step takes (time estimates, v0.2 M5) |
| `node` | taxi node id (`fly`, `getfp`) |
| `inn` | the bind location the route expects (`sethearth`) |
| `spell` | spell id (`learn`, `train`) |
| `minLevel` | the step waits for this level: until then it shows "in N levels" and the route goes on; it comes back once the level is there |
| `dungeon` | a dungeon id; packcheck warns at more than 2 visits of the same dungeon in a row (the instance limit is a limit, not a target) |

Header extras: `startInn` (the hearthstone is already set at the start), `knownNodes` (taxi nodes known at the start),
`xpModel = true` (warn when the XP model doesn't reach a `minLevel`), `phase` (the WoW Forever content phase the
pack is written for, a number; it is copied into the compiled header, `tools\packdiff.lua` reports a change, the
addon doesn't act on it yet).

Players can also say "not doing" a quest (saved per character) and undo their last 10 skips this session
(`/aog undo`); quests the server says don't exist (asked twice, at most one request per 0.5 s, 60 per session) are
passed over as "not on WoW Forever" until the next game build.

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
| `item` (v0.2, also in `cond`) | `item=<id>` or `item=<id>:<count>` (count 1 or more): that many in the bags. Only on steps with the `optional` flag (packcheck error otherwise); the step rides along while the item is there and comes back if it's looted after the step was passed (up to 15 steps back) | bag count (`C_Item.GetItemCount`, read only) |
| `skill` (v0.2) | `skill=firstaid>=50`, `skill=firstaid<50` (also `>`, `<=`); only `firstaid` so far; not learned / unknown = false | skill line rank (`C_SkillInfo`, read only) |

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

Route lint (v0.2, `WARN` lines, never errors; facts from `tools\data\forever-facts.lua`, map ids from
`tools\data\maps.lua`): a turn-in before its accept, the quest log over its size minus 2, a quest with `xp = 0` and
no `why`, a level step more than 3 levels up with few hand-ins between, a grind without `why`, `hearth` before any
`sethearth` (or `startInn`), `fly` to a `node` before its `getfp` (or `knownNodes`), an unknown map id, the same
`dungeon` more than 2 visits in a row, and with `--previous <folder>` an id from the last release that is gone
without `retiredSteps` / `renamedSteps`.

### Text style lint (`tools\textlint.lua`, from v0.1.1)

Step `text`, `da` and `why` are also checked against `tools\data\textrules.lua`: at most 90 characters, no
never-use words, no `&`, no version numbers, no `%s`-style formats, and no signs of copied quest text (Blizzard
tokens such as `$N`, narration words, more than 2 sentences, quote marks, runs of capital letters). These are
warnings, unless the pack header says `strict = true`; then they are errors. The addon's own locale texts are
always checked (English / Danish key and `{field}` parity, a length cap per spot with 40 % more room for Danish),
and `tools\build.lua` fails on a locale error.

Optional header field: `strict = true` (text lint findings are errors for this pack).

## 7. Where facts come from (v0.2)

Every step names its source in `src` (section 2). Two of them come from our own tools:

- **`rec`**: the dev recorder in the addon (`/aog dev on`, then `/aog rec on`; never on for players). It notes where
  quests are taken and handed in, loot and gather spots, vendors, trainers and dungeon entrances: map id, x / y and
  the NPC / object id (only from NPC and object GUIDs, never a player, never a name). `/aog rec export` gives plain
  `AOGREC1 k=v;...` records (header record `h=1;v=<addon version>;c=<client>;cnt=<records>;pg=<i>/<n>`; record
  fields `k` (accept, turnin, loot, gather, merchant, trainer, entrance), `q`, `npc`, `obj`, `ins`, `from` (start
  item), `m`, `x`, `y` (0-100), `n` (sightings), `it` (item ids)). `tools\recmerge.lua` merges exports: median
  coordinates, `seen` = sightings, at least 2 sightings by default, far-apart sightings marked `spread`. A recorder
  fact in a step: `src = "rec"`, `seen = "YYYY-MM"`, and `confirmed = true` once it matches the route.
- **imported facts** (`questie`, `forevdb`, `codex`, `cmangos`): `tools\import\import.lua` reads another project's
  data dump as data only (nothing in it is ever run), keeps only sources whose exact SPDX licence id is on the
  allowed list and whose version is pinned, drops Wowhead-derived, non-consenting and "all rights reserved"
  records, never keeps names, and writes a facts file whose every record carries `src` and the source's `spdx`,
  plus a data manifest (source, pinned version, counts, `dataVersion`). Each real source needs the user's yes to
  download first.

Between pack versions, `tools\packdiff.lua <old> <new>` lists kept / changed / gone / new step ids, suggests
`renamedSteps` and `retiredSteps` entries, and fails on a reused retired id.

Players report mistakes with the **report string** (`AOGR2 ...`, one line, from the Hub's "Report a mistake" page):
it is built by `AllinOneGuide\Data\Report.lua` (its fields are listed in `AllinOneGuide\DB\Serializer.lua`, kind
`R2`, with an Adler-32 checksum) and pasted into the issue form (`.github\ISSUE_TEMPLATE\mistake-report.yml`). A
report names the pack, version, step id and step hash, so a fixed step can be found again after renames.

## 8. Connectors (smart arrow, v0.2)

`packs-src\connectors\<area>.lua` holds the points the smart arrow leads through (doors, cave mouths, ramps, bridges,
gates, the tram, paths) and the "rooms" you can only leave through them. One file per area; all areas form one
graph (links may cross files and maps on one continent). Data only, one returned table:

```lua
return {
    area = "elwynn", formatVersion = 1, license = "GPL-3.0-or-later",
    connectors = {
        { id = "nsh-abbey-door-in", map = 1429, x = 48.7, y = 41.9, r = 3, kind = "door", hint = "VIA_ABBEY_DOOR",
          inside = "nsh-abbey", link = { "nsh-abbey-door-out" }, src = "own", confirmed = false },
    },
    rooms = {
        { id = "nsh-abbey", map = 1429, indoor = true, subzone = "Northshire Abbey",
          poly = { { 48.3, 40.8 }, { 50.0, 40.8 }, { 50.0, 42.1 }, { 48.3, 42.1 } }, src = "own", confirmed = false },
    },
}
```

| Field | Meaning |
|---|---|
| `id` | lower-case letters, digits, `-`; unique over all areas (connectors and rooms) |
| `map`, `x`, `y` | uiMapID and percent (0-100), like steps |
| `r` | yards that count as "reached" (1-15); default by kind: door / stairs 3, cave / ramp / tram 5, gate / bridge 6, path 10 |
| `kind` | `door`, `cave`, `ramp`, `bridge`, `gate`, `tram`, `path`, `stairs` |
| `hint` | locale key of the line under the arrow ("Through the abbey door"); must exist in enUS and daDK; without it the kind's text (`VIA_KIND_*`) |
| `inside` | the room this point is in (nil = outdoors). A door is two points: one inside, one outside, linked |
| `link` | walkable neighbours, both ways. An entry may be `{ "id", cost = <yards>, oneWay = true }`; `oneWay` only for a safe drop a normal player walks off, never a jump or trick |
| `src`, `confirmed` | `"own"` (our own estimate or a tester's `/aog rec` recording) or `"cmangos"` (a bare position fact from CMaNGOS classic-db: a door / gate game object, or a cave's size from its dwellers' spawns on a 0.5 % grid; never paths or waypoints). Nothing is copied from other addons' waypoint data. `confirmed = true` once checked on Forever |
| room `poly` | 3+ corners in percent, not crossing itself; `indoor = true` also needs `IsIndoors()` (when the game answers) |
| room `subzone` | English name for the checker and people only; not shipped |

A whole walled city can be one room with `indoor = false` (its map's corners): you leave it through its gate.
A step may set `via = { "id", ... }` (forced points, also inline `{ map = 1429, x = 50.1, y = 39.0, hint = "VIA_KIND_PATH" }`)
or `via = false` (straight). In a row it is the extra key `via`: `-` for false, else comma-separated items, each a
connector id or `map/x/y[/HINT]`. The build also writes `room=<room id>` for every step whose spot lies in a
connector room (the addon then needn't test the outline for the goal). Step rules (`CC.StepCheck`, run by
packcheck and the build): a `via` id must exist; a spot inside a room needs a room with an exit; a `via` way
longer than 1.5x the straight line from the step before, with no `why`, is a warning.

`luajit tools/connectors.lua` checks the files (ids, links, rooms with an exit, no islands, map ids, ranges, kinds,
hint keys, one-way trick words from `known-exploits.lua`, `src = "own"`) and writes
`AllinOneGuide\Routes\Connectors.lua` (one `ns.SmartRoute.Register{...}` per area, without `subzone`, `src`,
`confirmed`); `--check` fails when that file is out of date.
