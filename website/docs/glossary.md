---
title: Glossary
description: The words that Activity Monitor X uses, each with one meaning.
---

## Processes and apps

- **Process:** One running instance of a program, known by its PID and its start time together.
- **Program:** The path of the executable that a process runs.
- **App:** What the tables and charts show: the responsible app of a process, or the process itself when it has none.
- **Responsible app:** The app that macOS holds responsible for a process, for example the app that started a helper process. A terminal app is never a responsible app.
- **Terminal app:** An app whose child processes keep their own identity. By default: Terminal, iTerm, Ghostty and rootshell. Settings > Recording lists them.
- **Quiet system process:** A process under `/System`, `/usr` (not `/usr/local`), `/bin` or `/sbin` whose average for the metric is very small. It is hidden by default and counts in Other.
- **Group:** A set of apps that you make, chosen by rules (all, any, not) on the name, bundle ID, path or team ID.
- **Pinned app:** An app that you put in the sidebar, with its own chart and processes.

## Time and data

- **Sample:** One set of values for a process or for the Mac, at one time.
- **Tier:** One step of the stored history: raw (5 seconds), minute or hour.
- **Range:** The time that you look at: Live (the last 5 minutes, updated each second), 1H, 24H, 7D, 30D or 90D.
- **Span:** A part of the range that you select on the chart.
- **Metric:** What a chart or table shows: CPU, Memory, Disk, Energy, Network or GPU, and Score for groups.
- **Usual:** The typical value of an app for the time shown, as an hourly mean, beside its average.
- **Other:** The sum of all apps that do not have their own colour in the chart.
- **Top during peaks:** The five apps that add most to the busiest times of the chart. They get their own colours.
- **Period:** What the Calendar shows at one time: a day or a week of hours, or a month of days.

## Alerts

- **Event:** A recorded moment: a step in memory pressure, a change of thermal state, or an alert.
- **Rule:** One alert condition, with its threshold, the time that the value must stay past it, and the time before it alerts again.
- **Alert:** An event that a rule writes when a value passes its threshold.
- **Severity:** Info, warning or critical. Only warning (yellow) and critical (red) have a colour.
- **Preset:** A set of rule values that AMX calculates for your Mac: Relaxed, Balanced or Strict. Custom, after you edit a value.
- **System CPU rule:** The rule on the CPU of all cores: warning at 70%, critical at 90%, for 5 minutes by default. It also sets the colour of CPU in the Calendar and the menu bar.

## Window

- **Inspector:** The pane at the right that shows the details of what you selected. With nothing selected, it shows a summary.
- **Event lane:** The strip above the chart with marks for pressure (▲), thermal (◆) and alert (●) events.
- **Range bar:** The bar above the chart with the ranges (1H to 90D) and Custom.
- **Footer:** The strip at the bottom of the screen with the trend and the system numbers of the metric.
- **Preview card:** The card that shows when you hover a chart, a cell or an item.
- **Menu bar item:** CPU over memory pressure as two small numbers in the menu bar, with a dot for an unread alert.
- **Energy flow:** The Energy diagram: watts from the power adapter and the battery into the Mac, then to the top apps and Other.

## Disk and Hardware

- **Activity:** The Disk pane with the read and write charts, the disks and the volumes.
- **Space:** The Disk pane that scans a volume or folder and shows what uses its space, as a map and a table.
- **Inventory:** The Hardware table of what the Mac has and what is connected to it.
- **Chip:** The Hardware drawing of the chip of the Mac: its CPU cores, its GPU and its memory, each filled to its use.
