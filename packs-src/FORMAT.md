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
    joins = { pack = "normal-alliance", step = "wfl-acc-1" },   -- v0.2.5: where the player goes on when this ends
                                        -- (optional route = "<route id>", cond = "<condition>"; or a list of these:
                                        -- the first whose cond fits wins). "Play next" opens it at that step.
    mustDoSkip = { [1234] = "it's in the next stretch" },        -- v0.2.5 (rare): waive a must-do quest here
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
| `text`, `da` | short step text in our own words (verb + target + count + place), English and Danish. `{quest}` is replaced by the quest name from the game (fallback: `qname`). `{item:<id>}` is replaced by the item's name with its icon in front (see "Item tokens"). No `|`, no line breaks. |
| `flags` | list of words: `elite`, `group`, `deadly`, `ahStep`, `tradeStep`, `extra`, `future`, `noAutoAccept`, `walk`, `leaveArea`, `grind` |
| `cond` | when the step applies (grammar, section 5). Checked while playing, so ids stay the same for every character. |
| `src` | where the facts come from: `own, rec, lookup, wiki, client, questie, forevdb, codex, cmangos, lpdb, att, legacy`. Steps with no looked-up fact (e.g. `level` steps, our own route choices) use `own` and need no `seen`. |
| `seen`, `confirmed` | when the fact was looked up (`YYYY-MM`); `confirmed = false` until the recorder / reports confirm it on Forever |
| `obj` | objective step: which quest objectives count (`{ 1, 2 }`; empty = all) |
| `any` | objective group: done when any `any` of the listed objectives are done |
| `override` | goal grammar: the step is also done when this is true (e.g. `done=812 or inlog=813`) |
| `whileUntil` | background goal: shown next to the current step until the step with this id is reached; there it must be done. **Hand-over:** when that step is an `objective` step of the same quest that covers the goal's objectives (its `obj` is empty, or holds each of the goal's), the goal just stops showing there (that step shows the same counts at its spot) |
| `onWay` | (source only) travel side goals of a step: "kill / loot this on the way". A list of entries `{ id, quest, obj, any, item, count, useItem, text, da, cond, flags, src, seen, confirmed, qname, whileUntil }`. The build writes each entry as an `objective` row (`useitem` with `useItem`) **right before** the step, id `<step id>.<entry id>`, the entry's `whileUntil` or the default (the first later step of the same quest that is a covering `objective` step, i.e. a hand-over, or its `turnin`), and the extra key `onWay=<step id>`. Not on `fly` / `hearth` steps. The window shows each goal's objectives with live counts and a kill / loot / use icon (at most 3 lines, then "+n more on the way"); a goal whose quest isn't in the log hides until it is. Kills without a quest objective are never counted (no combat log). |
| `leadsTo` | travel step (`goto`): auto-skips when the step it leads to is already done (empty = the next non-travel step) |
| `why` | required on every `grind` step and every return to a zone left earlier (route rules) |
| `level` | `level` step: the level to reach |
| `item`, `count` | objective step without a quest objective: have `count` of `item` in the bags |
| `useItem`, `targetNpc`, `model`, `useWhen`, `classQuest` | accepted and kept (used from v0.2 on) |
| `model` (v0.3) | a creature **display id** only (a whole number above 0), for the 3D viewer when the NPC data is wrong or missing. NPC ids go in `npc` / `targetNpc`. The viewer shows, in order: `model`, `targetNpc`, `npc`. The display-id fallback for pack NPCs is generated by `tools/model_ids.lua` into `AllinOneGuide/Data/ModelIds.lua` |
| target button (2026-11-26) | an `objective` step's `npc` and any `targetNpc` name the mob the target button targets (`/targetexact <name>`, English clients). The names are generated by `tools/mob_names.lua` into `AllinOneGuide/Data/MobNames.lua` (creature names only); rerun it after adding mobs |
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
| `waits` (v0.2.5) | on an `accept` (or `objective`) step: what the quest makes you wait for: `escort`, `timed`, `event` (scripted event / spawn wave), `respawn` (one NPC / object others also need). The window counts it down (a timed quest's timer while it runs; "wait up to N min" for the others) |
| `waitMin` (v0.2.5) | `escort` / `event` / `respawn`: wait up to this many minutes (1-60, needed) |
| `timeLimit` (v0.2.5) | `timed`: the quest's own timer in minutes (1-180, needed); packcheck warns on a hearth / fly / ride leg while it runs and when the steps' `estMin` from accept to turn-in add up to more. `tools\data\quest-waits.lua` lists the known timed quests (CMaNGOS LimitTime) and escorts: a route step for one without `waits` gets a warning |

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

### Item tokens (beta.9, item pictures)

The addon puts the item's own game icon before the item's name in the current step's text by itself when the step
names the item in a field (`item`, `useItem`, a `useitem` step's `item`, `item=<id>` in `cond`) and the text uses the
item's real English name (`Data\ItemNames.lua`, or the game's name). Write a token only where that isn't so: the text
names an item that has no field, or calls it something else than its real name.

- Form: `{item:<id>}` with a number above 0, e.g. `text = "Use the {item:247834} to start {quest}"`. It becomes the
  item's name (the game's, else `Data\ItemNames.lua`, else "item") with its icon; hovering shows the item's tooltip.
- In `text` and `da` (the same tokens in both); not in `why`, `qname` or other fields.
- Checks: packcheck errors on a malformed token (`{item}`, `{item:abc}`, `{item:0}`) and on `da` with other tokens
  than `text`; the 90-character rule and textlint count a token as the item's name (12 characters when unknown).
- After adding items, run `luajit tools/item_names.lua <ClassicDB.sql>` so `Data\ItemNames.lua` knows their names
  (Forever-only items aren't in CMaNGOS: the game's name is used).

## 3. Compiled file (`<pack folder>\Routes\<file>.lua`)

From v0.2.5 the packs ship in their own LoadOnDemand addons next to the guide: `AllinOneGuide_Alliance\` and
`AllinOneGuide_Horde\`, listed in `tools\data\pack-folders.lua` (a pack not listed there doesn't ship). The build writes
each folder's `.toc` (`<folder>_Forever.toc`: LoadOnDemand, `Dependencies: AllinOneGuide`, `X-AOG-Packs: <ids>`),
LICENSE and CREDITS.txt, and the index `AllinOneGuide\Data\KnownPacks.lua` (which pack is in which folder). The guide
loads only the folder a character needs. A compiled pack file is plain data and nothing else (tos T29): the build's
scan fails on any other code, `\ddd` escapes or long encoded-looking runs. Must-do quests (`tools\data\must-do.lua`):
a pack of the quest's faction whose levels overlap gets a warning without it; in the build's chain check (every
shipped pack of a faction) a must-do quest no pack has is an error, and so is a `joins` target that isn't built.

```lua
-- (SPDX header, wiki line, "compiled by tools\build.ps1 from packs-src\elwynn.lua; do not edit")
-- row fields: id|type|quest|npc|map|x|y|r|text|da|flags|cond|src|extra
local AOG = AllinOneGuide
if not (AOG and AOG.RegisterPack) then return end
AOG.RegisterPack({ id = "demo-elwynn", ... header ... }, {
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

- `ns.Packs.Register(header, routes)` is the only entry point (pack addons reach it through the public
  `AllinOneGuide.RegisterPack(header, routes)`). Headers are read at login; rows are decoded only
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
`da` text with different `{placeholders}` than `text`, a `whileUntil` / `leadsTo` target that isn't a later step,
an `onWay` on a `fly` / `hearth` step, an `onWay` entry without `id` / `text` / (`quest` or `item`), an item-only
entry without `whileUntil`, a quest with no later covering objective or turn-in step, an `onWay` goal whose quest has
no accept step before it. Route lint warns at more than 3 `onWay` goals on one step, an explicit `whileUntil` on an
objective step that doesn't cover the goal (due there, not handed over), a quest already riding along as another
background goal, and an `onWay` goal with its own spot.
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
| `inside` | the room this point is in (nil = outdoors). A door is two points: one inside, one outside, linked. The arrow aims at the middle between them (when both are on one map), so place them on one line straight through the middle of the doorway (cave mouth), about the same distance from it on each side |
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

## 9. Hunt paths (v0.3)

A kill / collect step (`objective`, `useitem`, `grind`) may carry a loop of points round the area where its mobs
usually spawn. Once the player is in the area (inside the step's `r`, or near a loop point) the arrow leads round
the loop, point by point, until the step is done; in combat it holds its point. Display only: our own static data.

```lua
{ id = "eln-obj-7", type = "objective", quest = 7, npc = 6, map = 1429, x = 50.0, y = 36.6, r = 30,
  path = "auto" },                                    -- filled from packs-src\paths\<pack id>.lua by the build
  path = { { 49.7, 36.1 }, { 49.4, 35.2 }, { 47.1, 35.6 } }, pathSrc = "hand",   -- or written by hand
  path = false,                                       -- checked: one target, no loop
```

| Field | Meaning |
|---|---|
| `path` | 3-12 `{ x, y }` points in percent on the step's map (a closed loop), `"auto"`, or `false` |
| `pathSrc` | `"gen"` (made by `tools\import\huntpath.lua`) or `"hand"`; needed with a point list |
| `pathOpen` | `true`: a there-and-back line (the arrow turns round at the ends) instead of a loop |
| `pathR` | yards that count as "reached" per point (5-30, default 12) |

In a row: `path=49.7:36.1,49.4:35.2,...` (`-` for false), `pathSrc=gen`, `pathOpen=1`, `pathR=15`. Older addons
ignore these keys.

`packs-src\paths\<pack id>.lua` (data only) holds `steps = { ["<step id>"] = { src = "gen", points = { ... } } }`.
`luajit tools/import/huntpath.lua --sql <local cmangos classic-db dump> packs-src/<pack>.lua` writes it from bare
spawn positions (never waypoints or other guides' points): spawns near the step spot and in its connector room, the
biggest cluster, group middles snapped to a 10 yd grid, ordered as a short loop. A step whose spawns give no loop
is reported: write `path = false` there.

Checks (`tools\pathcheck.lua`, run by packcheck and the build): errors for a `path` on another step type, an
unfilled `"auto"`, not 3-12 points, a point outside 0-100, no step spot, `pathSrc` missing, `pathR` outside 5-30,
a point more than 250 yd from the step spot, a leg over 120 yd, a point in another connector room than the step
spot, a point inside a `known-exploits.lua` `places` circle (`places = { { map, x, y, r yards } }`); warnings for
a loop over 600 yd (least travel) and two points closer than 5 yd.

## 10. Spawn spots (v0.3)

Kill / collect steps whose mob (`targetNpc` or `npc`) has spawn spots on the step's map get a "nearest spot" arrow
(setting `huntMode`: `auto` keeps the step's loop, hand-made or generated, and uses spots only where there is no
loop; `spots` prefers spots over any loop; `loops` only loops). Display only:
static data plus the player's own position.

`packs-src\spots\<pack id>.lua` (data only), one list per mob and map, nearest to the route's steps first:

```lua
return { pack = "demo-elwynn", formatVersion = 1, license = "GPL-3.0-or-later",
  targets = { ["6@1429"] = { { 49.7, 36.1, 180 }, ... } } }   -- { x %, y %, respawn seconds }
```

`luajit tools/import/spots.lua --sql <local cmangos classic-db dump> packs-src/<pack>.lua` writes it from bare
creature spawn rows (position and `spawntimesecsmin`): spawns within 400 yd of the pack's steps for that mob, grouped
within 20 yd, middles snapped to 5 yd, 2-40 spots per mob, respawn = the group's median clamped to 120-900 s (300 s
when unknown); spots inside a `known-exploits.lua` place are dropped. Only creatures, never gameobjects or waypoints.
The build compiles every file to `AllinOneGuide\Routes\Spots.lua` (`"x,y,r;..."` with x / y in 0.1 % and r in 10 s);
`--check` fails when the compiled file is out of date. Respawn times are estimates: the addon always shows them with
"~" and never in combat.