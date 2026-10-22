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
An app the user put in the sidebar to open its own Timeline.

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

**Metric**:
The resource a chart or table shows: CPU, Memory, Disk, Energy, Network, GPU, and Score for groups.

**Other**:
The sum of every app that does not get its own colour in the chart.

**Top during peaks**:
The five apps that contribute most to the chart's busiest buckets; they get colours.

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

**Preset**:
A named set of rule thresholds computed for this Mac: Relaxed, Balanced, Strict; Custom when the user edited a value.

**Severity**:
Info, warning or critical; only warning and critical use yellow and red.

## Window

**Inspector**:
The trailing pane that shows the selected app or process.

**Event lane**:
The strip above the chart with markers for pressure (▲), thermal (◆) and alert (●) events.
