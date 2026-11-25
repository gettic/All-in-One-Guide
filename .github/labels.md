<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Issue labels

The labels the issue forms and the guide-fixer use. They are made by hand on GitHub (Issues > Labels) the
first time; this file is the list to copy from. The report types match `ns.Report.TYPES` in
`AllinOneGuide/Data/Report.lua` and the drop-down in `ISSUE_TEMPLATE/mistake-report.yml`.

| Label | Colour | Meaning |
|---|---|---|
| `bug` | `#d73a4a` | Something in the addon doesn't work (addon-bug form). |
| `guide-report` | `#0e8a16` | A wrong guide step (mistake-report form). |
| `needs-triage` | `#ededed` | Not looked at yet. |
| `needs-evidence` | `#fbca04` | We asked the reporter for more (a screenshot, the report line). |
| `confirmed` | `#1d76db` | Checked: the step really is wrong. |
| `fixed-in-release` | `#5319e7` | The fix is in a published release (the guide-fixer closes it then). |
| `cannot-reproduce` | `#cfd3d7` | We couldn't find the problem. |
| `duplicate` | `#cfd3d7` | Already reported. |
| `type:coords` | `#c5def5` | Wrong place on the map. |
| `type:order` | `#c5def5` | Wrong order. |
| `type:missing` | `#c5def5` | Quest isn't there on WoW Forever. |
| `type:notick` | `#c5def5` | The step doesn't tick. |
| `type:text` | `#c5def5` | The text is wrong. |
| `type:danger` | `#c5def5` | A dangerous spot (elites, guards, a fall). |
| `type:other` | `#c5def5` | Something else. |
| `lang:da` | `#bfdadc` | About the Danish texts. |
