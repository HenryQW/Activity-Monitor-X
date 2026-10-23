# Requirements

What must be true now. Where this file and the spec differ, this file wins: it holds the changes made after the spec.

- **This file:** what. Edit a line in place when a requirement changes; never keep a replaced line.
- **Decision log** (`docs/decisions/`): why, with the options. Append only. Each line here names its D-number.
- **ADRs** (`docs/adr/`): why, for the few choices that are hard to reverse.

Rules:

- Read this file before a UI change. Do not break a line without the user's approval.
- Add or edit the line in the same commit as the change.
- IDs are stable: a new line takes the next free number in its area; a removed line's ID is not used again.
- "(user)" marks a requirement the user asked for or picked.

## WIN: Window and toolbar

- **WIN-1** (user) The window never resizes itself, for the inspector or the toolbar (D21).
- **WIN-2** (user) The sidebar button comes directly after the window buttons (D35).
- **WIN-3** (user) Search is a magnifier at the end of the toolbar; a click or ⌘F opens the system field. An empty field closes back to the magnifier when it loses focus (Escape, a click elsewhere); a query keeps it open (D36, D41, D58).
- **WIN-4** (user) The toolbar has one solid colour; the inspector starts below it (D41, D42).
- **WIN-5** (user) Live is the first segment of the range bar and ⌘L: choosing Live starts it; choosing Live again, or ⌘L, returns to the range before Live; another segment shows that range (D48, D58).
- **WIN-6** (user) Start Live and Pause Live do not reload the screen: the chart fades over when Live data is ready (D51).
- **WIN-7** (user) The range bar has the segments Live, 1H, 24H, 7D, 30D, 90D, the shown window as text, and Custom…, a popover with From/To pickers and Apply; a custom window checks no segment (D40, D58).
- **WIN-8** (user) Search and the Inspector button are on every screen and work on what the screen lists (D50).
- **WIN-9** (user) Every icon and button has a hover hint (D26).
- **WIN-10** (user) No toolbar item goes into the overflow: below 840 pt of detail width (1050 pt while the search field is open), Metric is a pop-up that names the metric (D21, D48, D58).
- **WIN-11** (user) Apps, pinned apps, groups and Disk have the range bar above the content; Calendar, Alerts and the other System screens do not. The time range is not in the toolbar or the window subtitle. In a narrow bar the window text goes first, then the segments become a pop-up (D58).
- **WIN-12** (user) The toolbar groups its items into capsules; Quit and Info are one action group; the other view options are in a More menu (D60).
- **WIN-13** (user) A footer under the chart shows the system values of the metric now and in the range; totals from bucket means read "About" (D60).
- **WIN-14** (user) Hover hints and action labels say the action and the result where space permits (D60).
- **WIN-15** (user) A chart span selection shows a capsule with Zoom Out and Clear Selection; the subtitle names the view filter (D60).

## INS: Inspector

- **INS-1** (user) Pills: Overview | Processes | Files (D37, D44).
- **INS-2** (user) Overview, Files and the screen inspectors are grouped forms with stock margins, headers and rows (D53, D54).
- **INS-3** (user) With an app: Average with the usual value beside it (the usual is an hourly mean, so Peak has none), Peak, Launch History, Alert Rules, Files (D44, D60).
- **INS-4** (user) With no app: System Health, Top Apps, Biggest Changes, alert counts (D44).
- **INS-5** Files shows only the user's own processes (D44).
- **INS-6** (user) With nothing selected, Calendar, Hardware and Disk show a short summary of the screen; the Calendar alert count comes from the history of the period (D50, D60).
- **INS-7** (user) A click on a Launch History run or an inspector alert selects that time on the chart; Launch History shows runs as bars, each also an accessibility button (D60).
- **INS-8** (user) An action row under the header: Pin, Show in Finder, Alert Rules…, Quit…; Force Quit is in the Quit confirmation (D60).
- **INS-9** (user) Live numbers (inspector Average and Peak, popover gauges) roll to the new value; no animation with Reduce Motion (D60).

## COL: Colours and chart

- **COL-1** Red and yellow mean warning and critical only; app colours never use them.
- **COL-2** (user) A chosen app colour keeps the app as its own band in every chart (D43).
- **COL-3** (user) The colour dot is the colour control, in the app list and the inspector: a click opens the colours and None; on hover a chosen colour shows a cross, and only a click on the cross removes the colour. The app row's right-click menu keeps a Colour submenu for keyboard and VoiceOver (D54, D56).
- **COL-4** (user) Hovering an app with no band draws its line and area in the hover colour, which no app gets (D42).
- **COL-5** (user) Chart hover values show in a bubble inside the chart that takes no pointer events, so it never flickers (D24, D58).
- **COL-6** (user) The app selected in the inspector stays emphasised in the chart (others at 0.5) while no row is hovered (D60).
- **COL-7** (user) Disk Space colours files by kind, with a dot legend (D60).
- **COL-8** (user) A sparkline draws its part above the alert threshold in yellow, with a dashed threshold line (D60).
- **COL-9** (user) Low-space bars use the warning yellow, not an app colour (D60).

## SCR: Screens

- **SCR-1** (user) Calendar: Day, Week and Month cells, no Year view (D38).
- **SCR-2** (user) Energy: a live band diagram from the power sources to the top 5 apps and Other. A click on an app selects it and opens it into its top processes and a process Other (the app's watts by each process's share); a second click folds it; one app is open at a time (D47, D58).
- **SCR-3** (user) Sidebar items reorder by drag inside their section (D28).
- **SCR-4** (user) Energy: a right-click on an app has Show in Inspector, Show in Apps, Keep in Flow or Remove from Flow, Pin or Unpin, and Colour; on a process, Show in Inspector (D58).
- **SCR-5** (user) Energy: a kept app has its own band while it runs, also outside the top 5; Sort (Watts or Name, stored, Watts by default) orders the app bands, with Other last (D58).
- **SCR-6** (user) Apps table: a process row's text starts under its app's name (D58).
- **SCR-7** (user) Alerts: a Dismiss All text button in the toolbar and View > Dismiss All Alerts dismiss the alerts shown (search applies), with no confirmation, because Restore exists (D58).
- **SCR-8** (user) Disk has Activity | Space pills; Disk Map is the Space pane, and Show in Space opens a volume there. View shortcuts: Hardware ⌘4, Calendar ⌘5, Energy ⌘6 (D60).
- **SCR-9** (user) Apps table: optional PID and User columns; the table stores only the hidden columns (D60).
- **SCR-10** (user) Thermal, swap and low-disk alerts name a likely cause, as memory pressure does (D60).
- **SCR-11** (user) Live keeps the last data when the helper is lost and says "Helper not reachable. Data as of" the time (D60).

## SET: Settings and menu bar item

- **SET-1** (user) Settings > General has "Window opens with" and "Time range at open" (D48, D58).
- **SET-2** (user) Settings > General > Appearance: System, Light, Dark (D27).
- **SET-3** (user) The menu bar item shows a CPU sparkline; its menu actions have icons in one column, so the titles line up (D25, D54, D58).
- **SET-4** (user) Settings > Alerts "Banners for": Critical Only (default) or All Alerts; warnings arrive passive (D60).
- **SET-5** (user) The menu bar item adds a template warning glyph while an unread alert exists; the popover shows that alert on top and CPU and Memory Pressure as gauges with the number centred (D60).

## BLD: Build and platform

- **BLD-1** (user) Build, sign and install run without prompts (D52).
- **BLD-2** Scroll bars are stock; their width follows the system "Show scroll bars" setting, not the app (D54).
