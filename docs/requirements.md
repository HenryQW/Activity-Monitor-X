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
- **WIN-4** (user) The toolbar has no background: content runs under it with the scroll edge effect; a glass title pill at the leading side shows the screen's icon, title (at most 240 pt, truncated) and subtitle, icon only below 700 pt of detail; item groups are system glass capsules at the trailing edge (D66).
- **WIN-5** (user) Live is one round, icon-only glass button in the toolbar, before the item capsules, on the screens with a range bar: play when paused (regular glass), pause while Live runs (accent-tinted, never red or yellow); label Live with value On or Off; ⌘L. It starts Live; Live again, or ⌘L, returns to the range before Live; a segment shows that range (D48, D58, D66).
- **WIN-6** (user) Start Live and Pause Live do not reload the screen: the chart fades over when Live data is ready (D51).
- **WIN-7** (user) The range bar has 1H, 24H, 7D, 30D, 90D, the shown window as short text, and Custom…, a popover with From/To pickers and Apply. The short text: "Since 8:50 PM" (1H, 24H today), "Since yesterday, 8:50 PM", "Since 16 Oct" (7D and longer); a custom window as an interval with shared parts left out ("22 to 23 Oct"); a custom window inside one day that is not today names the day ("20 Oct, 3:40 to 4:40 PM"); "Live" while Live runs. The full window is in the hint and accessibility value. Live and a custom window check no segment (D40, D58, D66).
- **WIN-8** (user) Search and the Inspector button are on every screen and work on what the screen lists (D50).
- **WIN-9** (user) Every icon and button has a hover hint (D26).
- **WIN-10** (user) No toolbar item goes into the overflow: Metric shows its segments while the detail width fits the title pill, the segments and the item capsules (measured, 16 pt hysteresis), else a pop-up that names the metric (D21, D48, D58, D66).
- **WIN-11** (user) Apps, pinned apps, groups and Disk have the range bar as a floating glass capsule at the top of the content column, as wide as its content; Calendar, Alerts and the other System screens do not. The time range is not in the toolbar. As the column narrows, the window text goes first, then the segments become a pop-up. The Calendar bar fits any column width the same way: its title shortens, then goes; Show becomes an icon, then the period a pop-up; ‹ Today › stays whole; nothing is clipped (D58, D66).
- **WIN-12** (user) The toolbar groups its items into capsules; Quit and Info are one action group; the other view options are in a More menu (D60).
- **WIN-13** (user) A floating glass footer across the content column shows the system values of the metric now and in the range; the table scrolls under it; totals from bucket means read "About" (D60, D66).
- **WIN-14** (user) Hover hints and action labels say the action and the result where space permits (D60).
- **WIN-15** (user) Every chart screen (Apps, pinned apps, groups, Disk Activity) has a vertical glass zoom pill on the chart's trailing edge: Zoom In above Zoom Out, 32 pt hit areas. Zoom In makes the selected span the range, or with no span the next narrower range (90D, 30D, 7D, 24H, 1H) around the shown window; Zoom Out the next wider range. A button that cannot act (1H, 90D, Live) is disabled, not hidden. Hints name the result ("Zoom in to 24 hours around 22 Oct"). Clear Selection is a separate small glass button by the selection. View > Zoom In (⌘]) and Zoom Out (⌘[) act on the chart; the subtitle names the view filter. A zoom whose window ends now returns to the quick range (its segment checked, following the clock) (D60, D66).
- **WIN-16** (user) Every menu item uses a system SF Symbol when one represents it accurately, none when no symbol fits; toggles have a symbol and their checkmark; Pin and Unpin are `pin` and `pin.slash` everywhere. A pinned app row has a right-click menu with icons (Show in Inspector, Show in Finder, Colour, Alert Rules…, Unpin App from Sidebar, Quit…) and on hover a pin.slash button that unpins at once (D63, D66).
- **WIN-17** (user) One window background; the inspector is a floating glass panel inset 8 pt with 16 pt corners, starting 8 pt below the toolbar row (the sidebar is the system's). Level 1 is the toolbar row and the panels; level 2 is the content controls as glass capsules in the content column (range bar, zoom pill, Clear Selection, footer, Calendar bar, Space capsules); level 3 is the data, never glass. Spacing is 8, 12 or 16 pt only (D66).
- **WIN-18** (user) The one primary action of a screen is prominent: the toolbar Live button while Live runs (accent-tinted glass, never red or yellow), and an empty state's single action (D66).
- **WIN-19** (user) Hover hints show after the pointer rests 1 s (the app's own tooltip delay, never a system setting); a sidebar row whose name can truncate has a hint with the full name (D66).
- **WIN-20** (user) A pinned app shows its bundle's display name; the executable name or bundle ID shows only when no bundle names it (D66).

## INS: Inspector

- **INS-1** (user) Pills: Overview | Processes | Files (D37, D44).
- **INS-2** (user) Overview, Files and the screen inspectors are grouped forms with stock headers and rows inside the floating glass inspector panel; its scroll bars are always thin overlay scrollers (D53, D54, D66).
- **INS-3** (user) With an app: Average with the usual value beside it (the usual is an hourly mean, so Peak has none), Peak, Launch History, Alert Rules, Files (D44, D60).
- **INS-4** (user) With no app: System Health, Top Apps, Biggest Changes, alert counts (D44).
- **INS-5** Files shows only the user's own processes (D44).
- **INS-6** (user) With nothing selected, Calendar, Hardware and Disk show a short summary of the screen; the Calendar alert count comes from the history of the period (D50, D60).
- **INS-7** (user) A click on a Launch History run or an inspector alert selects that time on the chart; Launch History shows runs as bars, each also an accessibility button (D60).
- **INS-8** (user) An action row under the header: Pin, Show in Finder, Alert Rules…, Quit…; Force Quit is in the Quit confirmation (D60).
- **INS-9** (user) Inspector Average and Peak roll to the new value only after a change the user made (app, span); a Live tick swaps the number with no animation; the popover gauges do not animate (D60, D67).

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

- **SCR-1** (user) Calendar: Day, Week and Month cells, no Year view. Double-click zooms Month to Week to Day to Hour; Escape, the period strip and View > Zoom Out (⌘[) zoom out; View > Zoom In is ⌘]. A Back button in the toolbar (chevron only, between the Sidebar button and the title pill) returns one level up with its selection; it is always there on Calendar and disabled in Month, so nothing appears or moves; its hint names the result ("Go back to October"). The title pill's subtitle names where you are ("Week of 20 Oct"). The mouse back button and a swipe do the same (D38, D63, D66).
- **SCR-2** (user) Energy: a live band diagram from the power sources to the top 5 apps and Other. A click on an app selects it and opens it into its top processes and a process Other (the app's watts by each process's share); a second click folds it; one app is open at a time. The bands animate only after a user change (open or fold, keep or remove, sort); a Live tick swaps them (D47, D58, D67).
- **SCR-3** (user) Sidebar items reorder by drag inside their section (D28).
- **SCR-4** (user) Energy: a right-click on an app has Show in Inspector, Show in Apps, Keep in Flow or Remove from Flow, Pin or Unpin, and Colour; on a process, Show in Inspector (D58).
- **SCR-5** (user) Energy: a kept app has its own band while it runs, also outside the top 5; Sort (Watts or Name, stored, Watts by default) orders the app bands, with Other last (D58).
- **SCR-6** (user) Apps table: a process row's text starts under its app's name (D58).
- **SCR-7** (user) Alerts: a Dismiss All text button in the toolbar and View > Dismiss All Alerts dismiss the alerts shown (search applies), with no confirmation, because Restore exists (D58).
- **SCR-8** (user) Disk has Activity | Space pills; Disk Map is the Space pane, and Show in Space opens a volume there. View shortcuts: Hardware ⌘4, Calendar ⌘5, Energy ⌘6 Choosing a volume or folder in Space scans it at once; a shown map of the same target is kept; Rescan scans again (D60, D64).
- **SCR-9** (user) Apps table: optional PID and User columns; the table stores only the hidden columns (D60).
- **SCR-10** (user) Thermal, swap and low-disk alerts name a likely cause, as memory pressure does (D60).
- **SCR-11** (user) Live keeps the last data when the helper is lost and says "Helper not reachable. Data as of" the time (D60).
- **SCR-12** (user) Space shows scan progress with a system progress bar: determinate for a volume (scanned bytes of used space), indeterminate for a folder; the text gives items and bytes so far, with Stop beside it (D64).
- **SCR-13** (user) The Space item menu (table and treemap) has Open, Open With, Quick Look | Show in Finder, Get Info, Open in Terminal | Copy Path, Copy Name | Rename…, Move to Trash, each with an icon; items that do not apply are hidden; Move to Trash asks nothing (the Trash restores); a failed action shows the system's error (D64).

## CAL: Calendar and time zone

- **CAL-1** (user) The grid is gapless with hairline separators and square cells; no week number at the left of a row; the Week cell at the right stays. A 1.5 pt stepped line in a quiet system colour marks where the month changes; the first of a month names its month ("1 Oct") (D63).
- **CAL-2** (user) Today has a neutral fill, weekends a light tint; today wins on a weekend (D63).
- **CAL-3** (user) Selection is the accent, hover is grey. A drag across cells draws one outline around the span, not one border per cell; shift-click and the Extend Selection action extend it. In Day and Hour the unit is the bar (5-minute line in Day, minute line in Hour): hover greys the bar, a click selects it, a drag selects a span of bars, with no cell outline; selected bars have an accent tint (D63).
- **CAL-4** (user) Each cell shows its mean, one line per bucket and the busiest app; the busiest app follows the Metric and the Show pop-up (Busiest App, All Apps, a group) (D63).
- **CAL-5** (user) Status colour in cells: CPU follows the system CPU rule (SET-7) on the Mac's CPU, not the apps shown; level lines show only with no search or group filter. Memory follows the recorded memory pressure level, with counts at every bucket size. Other metrics have none (D63).
- **CAL-6** (user) The inspector for one cell has the date title only; a span is compared with the span before it; a bar or span of bars (Day, Hour) shows its time, mean, peak, lines and top apps, with no comparison (D63).
- **CAL-7** (user) The hover preview is the shared preview card: large for a day or block, compact for an hour or line; in Day and Hour the preview names the hovered bar (D63).
- **CAL-8** (user) A compact pop-up beside the period strip shows the zone abbreviation ("HKT"), or with a forced zone "PDT, 15 h behind". A forced zone applies to every screen's dates and day boundaries, is stored, and the range bar names it; chart axes follow the forced zone; compact Calendar bars show the abbreviation only (D63).
- **CAL-9** (user) Week, Day and the preview can add hour labels for other zones; the hour gutter keeps one fixed width whatever the number of zones, so the grid never moves when a zone is added or removed (D63, D66).
- **CAL-10** (user) Hover previews across the app use the one shared preview card; it takes no pointer events and its text is also in the host's accessibility value (D63).
- **CAL-11** (user) Left and Right move the selected bar in Day and Hour, with Shift they extend the span; VoiceOver steps through a cell's bars and selects each; double-click on a Day bar opens that Hour (D66).
- **CAL-12** (user) The Month, Week and Day grids fit the content column at every width and never run under the inspector: cells shrink and drop detail by width (busiest app name, its peak, the counts, the mean and "No data"); the day number or hour and the lines stay (D66).
- **COL-10** (user) Every floating panel, capsule, popover and hover preview, whatever its size, is Liquid Glass (D65, D66).

## MOT: Motion

- **MOT-1** (user) One helper decides every animation: `.smooth` only, 0.15 to 0.3 s, no bounce, interruptible; frequent actions (sidebar clicks, hover, Live ticks, Calendar steps) get no added motion; with Reduce Motion or Low Power Mode a move, scale or glass morph becomes a short fade or a cut (D67).
- **MOT-2** (user) A range change keeps the old chart until the new data is ready (a spinner only after 0.5 s), then cross-fades once; Start and Pause Live cross-fade; chart marks never interpolate (D67).
- **MOT-3** (user) Calendar zoom grows the new period out of the double-clicked point, and zoom out shrinks back to the point that level began from; with Reduce Motion a fade (D67).
- **MOT-4** (user) Pinning and unpinning a sidebar row, and an alert coming in, dismissed or restored, fade (0.2 s); a search does not animate the list (D67).
- **MOT-5** (user) Footer figures roll to the new value only after a change the user made (metric, range, span), once its data has loaded; a Live tick, a reload of the same range and the app's own readings swap with no animation (D67).
- **MOT-6** (user) App and process rows animate in, out and to new places (0.25 s) only for a user action: sort, pin, opening an app, the idle row, the Hide Quiet toggle. Typing in search, Live launches, quits and value ticks change rows with no animation (D67).
- **MOT-7** (user) Revealing an app from outside the table (Alerts, Calendar, a preview, the inspector) and sorting scroll its row into view with a 0.3 s smooth animation; with Reduce Motion or Low Power Mode the view jumps (D67).

## SET: Settings and menu bar item

- **SET-1** (user) Settings > General has "Window opens with" and "Time range at open" (D48, D58).
- **SET-2** (user) Settings > General > Appearance: System, Light, Dark (D27).
- **SET-3** (user) The menu bar item shows a CPU sparkline. Its menu is a real system menu: every row has the native highlight, keyboard navigation, type-to-select and VoiceOver, with no custom row component or hover fill. Every action and alert row shows its icon, also on macOS 27, where menus hide icons by default; each row has a hover hint that says its action (D25, D54, D58, D68, D69).
- **SET-4** (user) Settings > Alerts "Banners for": Critical Only (default) or All Alerts; warnings arrive passive (D60).
- **SET-5** (user) The menu bar item adds a template warning glyph while an unread alert exists. The menu shows, from the top: CPU and Memory Pressure as gauges with the number centred, in one row with no highlight; the newest unread alert; Top Apps (app icon, name, CPU and memory in right-aligned columns); Recent Alerts (severity symbol, subject, message and time below). Each gauge ring is tinted by level, green normal, yellow warning, red critical (Memory Pressure by the system's pressure level, CPU by the system CPU rule, green when the rule is off). A Top Apps row opens Apps with that app selected. The menu CPU sparkline is yellow over the system CPU warning level (SET-7). Live top apps are read from the helper only while the menu is open. The menu follows the system appearance, as menu bar menus do. System CPU alerts follow the same glyph and passive rules (D60, D63, D69).
- **SET-6** (user) Settings > General has First day of week, "Follow System" by default (D63).
- **SET-7** (user) Settings > Alerts has a System CPU rule: CPU of all cores, warning 70 % and critical 90 % held for 5 min by default, editable, on or off; it names the top app as a likely cause (D63).
- **SET-8** (user) Settings > General has a Terminal pop-up (installed terminal apps, default Terminal) used by Open in Terminal (D64).

## BLD: Build and platform

- **BLD-1** (user) Build, sign and install run without prompts (D52).
- **BLD-2** Scroll bars are stock and follow the system "Show scroll bars" setting, except the inspector panel, whose scroll bars are always overlay (INS-2) (D54, D66).
