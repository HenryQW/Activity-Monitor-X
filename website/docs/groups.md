---
title: Groups and pinned apps
description: Put the apps that you care about in the sidebar, alone or as a group chosen by rules.
---

The sidebar has two kinds of item that you make: **pinned apps** and **groups**. Each one opens a screen like [Apps](/apps), with a chart and a table, for only those apps.

## Pinned apps

- To pin an app, click the pin in its table row, click **Pin** in the inspector, or choose Process > Pin App to Sidebar.
- A pinned app shows under **Pinned Apps** in the sidebar with its icon and its bundle's name.
- To unpin, hover the row and click its button, or right-click the row and choose Unpin App from Sidebar. The right-click menu also has Show in Inspector, Show in Finder, Colour, Alert Rules… and Quit….
- Drag sidebar rows to change their order.

## Groups

A group is a set of apps that a rule chooses. Use it for a project, a set of tools, or all the apps of one company.

1. Click **Add Group** at the bottom of the sidebar.
2. Give the group a name, a symbol and a colour. Each group needs a name that no other group has.
3. Build the rule. Choose **All**, **Any** or **Not** "of the following are true", then add conditions:

   | Field | Operators |
   | --- | --- |
   | Name | is, contains, starts with |
   | Bundle ID | is, contains, starts with |
   | Path | is, contains, starts with |
   | Team ID | is, contains, starts with |

   Matches do not look at upper and lower case. **Add Group** inside the rule adds a nested set of conditions.
4. **Matching Processes** lists the processes of the last minute that the rule matches. Use it to check the rule.
5. Click **Save Group**.

A group screen has one more metric, **Score**. The score is the footprint of the group in percent of this Mac: half its share of the CPU of all cores, and half its share of the memory.

The Calendar **Show** pop-up can show one group, and `amx` has the tools `list_groups` and `group_summary` (see [amx and MCP](/cli)).

Groups are saved in `~/Library/Application Support/ActivityMonitorX/groups.json`. Group colours come from the app colours, so a group is never red or yellow: those colours mean warning and critical only.
