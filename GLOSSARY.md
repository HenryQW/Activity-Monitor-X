# Activity Monitor X

Recorded history of what each process on one Mac does, shown by app, by group and over time.

## Processes and apps

**Process**:
One running instance, identified by its PID and start time together.
_Avoid_: task, PID (alone)

**Program**:
The executable path that processes run.
_Avoid_: binary, command

**App**:
The unit the user sees in tables and charts: the responsible app of a process, or the process itself when it has none.
_Avoid_: application bundle, owner

**Responsible app**:
The app that macOS holds responsible for a process (for example the app that launched a helper); terminal apps are never responsible apps.

**Terminal app**:
An app whose child processes keep their own identity instead of grouping under it (default: Terminal, iTerm, Ghostty, rootshell).

**Quiet system process**:
A process under `/System`, `/usr` (not `/usr/local`), `/bin` or `/sbin` whose average for the current metric is below a small threshold; hidden by default and counted in Other.

**Group**:
A user-defined set of apps chosen by a rule tree (ALL, ANY, NOT over name, bundle ID, path, team ID).
_Avoid_: category, tag

**Pinned app**:
An app the user put in the sidebar to open its own chart and processes.

## Time and data

**Sample**:
One set of values for a process or the system at one tick.

**Tier**:
One resolution of stored history: raw (5 s), minute, hour.

**Bucket**:
One time slot of a tier or of a chart.

**Range**:
The time the user looks at: Live (last 5 min, 1 s updates), 1H, 24H, 7D, 30D, 90D.

**Span**:
A part of the range the user selected on the chart.

**Usual**:
An app's typical value for the time shown, as an hourly mean, beside its average; Peak has no usual value, and Live shows none.

**Period**:
What the Calendar shows at once: a day or a week of hours, or a month of days, each cell the metric summed over all apps.
_Avoid_: range (that is what Apps shows)

**Metric**:
The resource a chart or table shows: CPU, Memory, Disk, Energy, Network, GPU, and Score for groups.

**Other**:
The sum of every app that does not get its own colour in the chart.

**Top during peaks**:
The five apps that contribute most to the chart's busiest buckets; they get colours.

**Chosen colour**:
A colour the user gave an app; the app shows in it and gets its own band in every chart, also when it is not in the top five.

## Alerts

**Event**:
A recorded moment: a pressure step, a thermal change, an alert or an insight.

**Alert**:
An event written when a rule's threshold is crossed.
_Avoid_: warning (that is a severity), notification (that is how an alert is shown)

**Insight**:
An event that explains a pattern, such as steady memory growth.

**Rule**:
One alert condition with its threshold, hold time and re-alert period.

**System CPU rule**:
The rule on the CPU of all cores (warning 70 %, critical 90 %, for 5 min by default); it also sets the status colour of CPU in Calendar cells, on the Hardware chip and in the menu bar.

**Preset**:
A named set of rule thresholds computed for this Mac: Relaxed, Balanced, Strict; Custom when the user edited a value.

**Severity**:
Info, warning or critical; only warning and critical use yellow and red.

## Window

**Inspector**:
The trailing pane that shows what the screen has selected: an app or process, a Calendar cell, a disk or volume, a Space item or a Hardware row. With nothing selected it shows a summary or a hint.

**Search**:
The toolbar field. Each screen filters what it lists: apps on Apps, Alerts, Calendar and Energy; disks and volumes on Disk Activity; items on Space; rows on Hardware.

**Event lane**:
The strip above the chart with markers for pressure (▲), thermal (◆) and alert (●) events.

**Energy flow**:
The Energy screen's band diagram: watts from the adapter and the battery into the Mac, and the Mac's watts split over its top five apps, the apps the user keeps in the flow, and Other, by their share of energy impact right now.

**Level**:
One of the three layers of the window. Level 1 is the window chrome (the toolbar row, the sidebar and the inspector panels); level 2 is the content controls that float in the content column; level 3 is the data, never glass.
_Avoid_: layer, z-order

**Title pill**:
The glass capsule at the leading side of the toolbar with the screen's icon, title and subtitle.

**Range bar**:
The level 2 capsule above the chart with the range segments (1H to 90D), the shown window as short text, and Custom….

**Zoom pill**:
The vertical level 2 capsule on a chart's trailing edge with Zoom In and Zoom Out.

**Footer**:
The level 2 glass strip across the content column with the trend line and the system figures of the metric (Apps), or the power figures (Energy).
_Avoid_: status bar

**Calendar bar**:
The level 2 capsules above the Calendar grid: the period choice (Day, Week, Month), the time zone, Show and the steps.
_Avoid_: Calendar strip

**Card**:
A titled inspector section that opens and closes, with a summary at the right of its first row.

**Preview card**:
The one hover readout (`PreviewCard`), compact or large, used by every screen.
_Avoid_: tooltip (that is a hover hint)

**Hover hint**:
The system help text of a control, shown after the pointer rests 1 s; it says the action and the result.

**Menu bar item**:
CPU over memory pressure as two small numbers in the menu bar, with the alert dot at their left; a click opens its system menu.

## Disk and Hardware

**Activity**:
The Disk pane with the read and write charts, the physical disks as cells, and the volume and APFS container tables.

**Space**:
The Disk pane that scans a volume or folder and shows what uses its space as a treemap and a table.
_Avoid_: Disk Map (the old screen name)

**Inventory**:
The Hardware table of what the Mac has and what is connected, by thing, in the system's own words.

**Thing**:
An item of the inventory that is a real object (a drive, a device, a display, a volume); only a thing has an icon. A set of values or a group is not a thing.

**Chip**:
The Hardware drawing of the Mac's chip: a `cpu` symbol per core, GPU cores as lane blocks, and one `memorychip`, each filled to its use.
_Avoid_: board (the earlier motherboard drawing)

**Part**:
A piece of hardware the app draws or selects: a CPU cluster, the GPU, memory, a volume, a display, the battery.

**Drawn part**:
The one shared drawing of a part where no system symbol shows it (flash chips for a drive, the battery, a display); the same on every screen.

**Part cell**:
The cell (`partCell`) around a drawn part or a fact, with its name and one fact; a light system fill and an accent outline while selected.

