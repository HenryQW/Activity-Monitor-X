---
title: Why Activity Monitor X
description: The problem Activity Monitor X solves, and what it shows.
---

Your Mac was slow an hour ago. Now it is fast again, and a live view of the processes shows only the present. The cause is gone, and you cannot see it.

Activity Monitor X (AMX) records what each process does all the time, and keeps that history for 90 days. After a slow period, one screen shows when it happened and which apps caused it.

## What AMX records

A helper, `amxd`, runs as root. Every 5 seconds it records CPU, memory, disk, energy, network and GPU for each process, also for system processes and for processes of other users. It records while the app is closed and while nobody is logged in. [How it works](/how-it-works) tells more.

## What the app shows

| Screen | What it shows |
| --- | --- |
| Apps | A chart above an app table, for one metric and one time range, from Live (the last 5 minutes) to 90 days. |
| Calendar | The metric for each hour or day, as a grid of cells for a day, a week or a month, with the busiest app in each cell. |
| Alerts | The alerts that the rules wrote. An alert about the Mac names a likely cause. |
| Groups | Your own sets of apps, chosen by rules on the name, bundle ID, path or team ID. |
| Disk | Activity: read and write charts, disks and volumes. Space: a map of what uses the space of a volume or folder. |
| Energy | Live watts from the power adapter and the battery to the top apps. |
| Hardware | The chip, memory, drives, displays and devices of the Mac. |

The menu bar item shows CPU and memory pressure as two small numbers, and a dot while an alert is unread. The `amx` command gives the same history to scripts and to AI clients through an MCP server. See [amx and MCP](/cli).

## What AMX does not do

AMX does not send your data anywhere. The history stays on your Mac. See [Privacy](/privacy). AMX does not change a process, except when you choose Quit or Force Quit, and it asks you first.

## Open source

AMX is free and open source under the [MIT license](https://github.com/HenryQW/amx/blob/main/LICENSE). The source code is on [GitHub](https://github.com/HenryQW/amx). The notices for the third-party code are in the About window of the app.

## Next

- [How it works](/how-it-works): from a sample to a chart.
- [Install](/install) AMX and approve its helper.
- [Glossary](/glossary): the words that AMX uses.
