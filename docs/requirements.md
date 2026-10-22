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
- **WIN-3** (user) Search is a magnifier at the end of the toolbar; a click or ⌘F opens the system field (D36, D41).
- **WIN-4** (user) The toolbar has one solid colour; the inspector starts below it (D41, D42).
- **WIN-5** (user) Live is a Start Live (play) / Pause Live (pause) button and ⌘L; Pause returns to the range before Live (D48).
- **WIN-6** (user) Start Live and Pause Live do not reload the screen: the chart fades over when Live data is ready (D51).
- **WIN-7** (user) Range is a popover with From/To pickers and the quick ranges with dividers (D40).
- **WIN-8** (user) Search and the Inspector button are on every screen and work on what the screen lists (D50).
- **WIN-9** (user) Every icon and button has a hover hint (D26).
- **WIN-10** No toolbar item goes into the overflow: below 900 pt of detail width, Metric is a menu (D21, D48).

## INS: Inspector

- **INS-1** (user) Pills: Overview | Processes | Files (D37, D44).
- **INS-2** (user) Overview, Files and the screen inspectors are grouped forms with stock margins, headers and rows (D53, D54).
- **INS-3** (user) With an app: Compared to Usual, Launch History, Alert Rules, Files (D44).
- **INS-4** (user) With no app: System Health, Top Apps, Biggest Changes, alert counts (D44).
- **INS-5** Files shows only the user's own processes (D44).

## COL: Colours and chart

- **COL-1** Red and yellow mean warning and critical only; app colours never use them.
- **COL-2** (user) A chosen app colour keeps the app as its own band in every chart (D43).
- **COL-3** (user) The colour dot is the colour control, in the app list and the inspector: a click opens the colours and None; on hover a chosen colour shows a cross, and only a click on the cross removes the colour. The app row's right-click menu keeps a Colour submenu for keyboard and VoiceOver (D54, D56).
- **COL-4** (user) Hovering an app with no band draws its line and area in the hover colour, which no app gets (D42).

## SCR: Screens

- **SCR-1** (user) Calendar: Day, Week and Month cells, no Year view (D38).
- **SCR-2** (user) Energy: a live band diagram from the power sources to the top apps (D47).
- **SCR-3** (user) Sidebar items reorder by drag inside their section (D28).

## SET: Settings and menu bar item

- **SET-1** (user) Settings > General has "Open at" and "Time range at open" (D48).
- **SET-2** (user) Settings > General > Appearance: System, Light, Dark (D27).
- **SET-3** (user) The menu bar item shows a CPU sparkline; its menu actions have icons (D25, D54).

## BLD: Build and platform

- **BLD-1** (user) Build, sign and install run without prompts (D52).
- **BLD-2** Scroll bars are stock; their width follows the system "Show scroll bars" setting, not the app (D54).
