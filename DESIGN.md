# Design language

How Activity Monitor X looks and behaves. This file gives the rules. `docs/requirements.md` gives the exact values per screen, by ID (WIN-17); the decision log gives the reasons, by number (D76). When a new screen or control is not covered there, decide it from this file. Where shared code applies a rule, the rule names it.

## Character

Premium but calm. AMX is a quiet instrument: it records in the background and speaks only when something needs attention. Normal is quiet, with no colour and no motion. Data comes first, chrome second.

## Principles

1. **Native first.** System controls, fonts, materials and symbols with their default look (ADR 0009). Custom drawing only where data needs it: charts, the Calendar grid, the treemap, sparklines, the Energy flow and the drawn parts. A custom drawing uses system colours, fonts and hit areas, so it reads as part of the system.
2. **The thing itself.** Show a thing as itself: its app icon, its system symbol or its drawn part. No box for decoration, no word said twice, one style for one job (D76).
3. **Colour is information.** Identity, status and interaction are separate roles (see Colour).
4. **Overview first, details on demand.** The chart or grid gives the shape at a glance; a hover gives a preview; a click puts the full details in the inspector; a double-click goes one level deeper.
5. **Loud only for what matters.** Warnings arrive quietly, critical alerts interrupt (SET-4). The menu bar item adds a dot for an unread alert, in a slot that is always there (SET-5).
6. **Stable.** The window never resizes itself (WIN-1). Controls do not jump, numbers keep their column, an app keeps its colour, and a hover never changes the data.
7. **Honest data.** Missing data says "No data" and is never a zero. An estimate says "About". A lost connection keeps the last data and says when it is from (SCR-11).
8. **Reachable without a mouse.** Every hover or drag action also has a menu item, a shortcut or an accessibility action.

## Interaction

- Hover shows. Click selects. Double-click goes deeper. Drag selects a span, drawn as one outline. Right-click lists the actions on that thing (see Context menus).
- Selection (accent) and hover (grey) can show at the same time and never look alike.
- Escape goes back: it clears a span, zooms out one level, or closes an empty search field.

## Layout grid and spacing

`Layout` names every value; a view does not type its own (WIN-17).

- Spacing is 4, 8, 12 or 16 pt only.
  - `Layout.gap`, 4 pt: inside one row or one block: an icon and its label, a value over its label, a symbol and its count.
  - `Layout.inset`, 8 pt: insets of panels and floating controls from their container, gaps between them and between cells, and padding inside a small tile (the Calendar fact cells).
  - `Layout.padding`, 12 pt: from the edge of a capsule, card, panel or cell to its content. No text is nearer an edge than this, except in a small tile.
  - `Layout.corner`, 16 pt: panel and footer corners, concentric with the window.
- `Layout.bar`, 40 pt, is the height of the toolbar row and of the level 2 bars.
- Not spacing, so not on the grid: an offset measured from another part (the zoom pill under a chart's title row, a process name under its app's name), the native menu's and the menu bar item's own metrics, and the inside of a drawn part.
- The window has one background. The sidebar is the system's. The inspector is a floating panel, inset 8 pt, that starts 8 pt below the toolbar row. Opening it shrinks the content column, never the window (ADR 0007).
- Density is compact and aligned: grids are gapless with hairline separators and rows line up. Parts shown side by side share one height (SCR-15, CAL-13).
- Content fits the column at every width. It drops detail first, then changes to a smaller form; it is never clipped and never goes under the inspector (WIN-10, WIN-11, CAL-12). No toolbar item goes into the overflow.
- A label gives way in a fixed order: a drawing gives up space before its labels do, a label drops its secondary value (a share) before its name shortens, and a name shortens in the middle (SCR-2).

## Levels

- **Level 1, the window chrome:** the toolbar row and the panels (sidebar, inspector).
- **Level 2, the content controls that belong to the data:** range bar, zoom pill, screen footer, Calendar bar, Space path. Each floats in the content column as its own glass capsule or bar (`floatingCapsule`, `floatingBar`). The time range is never in the toolbar (WIN-11).
- **Level 3, the data:** chart, table, grid, treemap, board. It runs edge to edge under levels 1 and 2 with the scroll edge effect, and is never glass. Nothing important sits under a capsule at rest: a chart keeps room for its zoom pill (`ChartZoom.width`).

## Materials

- Everything that floats is Liquid Glass, whatever its size: toolbar items, panels, level 2 controls, every popover and hover preview (COL-10, D65).
- System glass only (`.glassEffect(.regular)`), so Reduce Transparency and Increase Contrast work. Regular, not clear: clear glass made the figures unreadable (D66).
- No glass in glass (COL-11, D71). A capsule is the one glass under its controls: pop-ups and buttons in it are borderless, with a system divider where text would run together. A choice of a few values in a capsule is `CapsuleChoice`: the chosen value is a pill on the glass, with no track. A segmented picker never sits in a capsule; in a level 1 panel it can (the inspector's View picker).
- A toolbar item with its own glass (the title pill, Live) hides the shared item background.
- The data is never glass. A part cell has a light system fill, not glass.

## Colour

Three roles, never mixed (COL-1, D60):

- **Identity: which app.** The top apps during peaks get the five palette colours (`AppPalette`, ADR 0008). A chosen colour gives an app its own band in every chart (COL-2). An app keeps one colour slot everywhere (`appColorSlots`). App and group colours are the same set, never red, yellow, pink or grey (COL-1). Other is a light grey. The hover line of an app with no colour is the primary colour, which no app gets (COL-4).
- **Status: over a rule.** Yellow at a rule's warning level, red at its critical level, and only then: the system CPU rule (SET-7), memory pressure, low space (COL-9), the free space alert, the battery (COL-13), and SMART failing (critical, COL-16). Normal has no colour and no symbol ("Verified" is plain text). No heat scales (D60). Calendar weekends are a neutral tint, never a colour (CAL-2).
- **Interaction and level: the accent.** The accent marks the selection (an outline on a part or cell, a tint on a bar) and the level of one-series data (a core's use, a display's brightness, a sparkline). Grey marks the hover.

Rules:

- Colour is never the only cue: text or a shape goes with it ("low", a severity symbol).
- A status colour and the value it marks come from the same number, so a taller line is never the calmer one (CAL-5, D83).
- Drawn decoration (outlines, lanes, stands) uses system greys and label colours only (`PartStyle`, COL-12).
- The menu bar item's numbers keep the menu bar's own colour; a 4 pt bar before a number shows its level in yellow or red, as coloured text on a light menu bar is too faint (SET-3, D82). Colour (default) or Greyscale, where the bars and the alert dot take the menu bar's colour (D81).
- Exceptions, each a user call: the menu's gauges are green at normal (SET-5, D68); Dismiss All has the system destructive role in red (SCR-7). The Live button is accent-tinted, never a status colour (WIN-5).

## Typography and numbers

- System text styles only, no custom fonts. The one exception is the menu bar item: two lines of small fixed-size type, so it fits the menu bar (D81).
- Numbers that change use monospaced digits and keep their column. A number whose width can change keeps the width of its widest value ("100%" in the menu bar).
- Roles: the title pill is a headline over a subheadline; a figure is its value in `.title3` semibold over a caption label (`Figure`, `PreviewCard`); a cell is a semibold name over one secondary fact.

## Iconography

- An icon names a thing (an app, a device, a volume, a part), never a value, a set of values or a group (SCR-18, D75). In a list, icons sit centred in one fixed-width column; a row with no icon keeps the column empty, so the names at one level line up.
- Choose in this order: the app's own icon; a system SF Symbol that shows the thing accurately; a drawn part where no symbol does. A menu item has a symbol only when one fits (WIN-16).
- One symbol for one meaning. `Shell/Symbols.swift` gives each metric and each alert rule its symbol, for Calendar, Alerts and Settings. Pin and Unpin are `pin` and `pin.slash` everywhere.
- One drawing for one part, on every screen (SCR-19, D76). A screen that shows a part uses the shared drawing and does not draw its own:
  - `FlashChips` (`Shell/PartShapes.swift`): a drive, two chips for the startup disk and one for an external drive, filled from the bottom to the used share.
  - `BatteryShape` (`Shell/PartShapes.swift`): filled from the left to the charge, with a bolt while it charges.
  - The chip glyphs (`ChipDiagram`): a `cpu` symbol for each core, GPU cores as lane blocks, one `memorychip` (SCR-15).
  - The display (`HardwareBoard`): a laptop lid or a monitor on a stand, filled to its brightness (SCR-16).
- A list row uses the system symbol for a thing; a cell or a diagram uses the drawn part, in a part cell (`partCell`). The exception is a drive row in the Hardware inventory: it has the flash chips at the symbol's size (SCR-25).
- A drawn part is live: it fills to its value in the accent, or in a status colour at a rule's level (COL-12, COL-13). A reading does not animate.
- Names come from the system. Hardware labels and values use the system's own words and spelling (SCR-26); a built-in display has its system type name (SCR-14); an app has its bundle's display name (WIN-20). The app's own words and Title Case only where the system has none.
- Casing as System Settings: titles in Title Case (cards, sections, menus and their items, buttons, empty-state titles, rule names); row, field and figure labels in sentence case ("Swap used", "Launch at login").

## Components

### Toolbar

- No background: content runs under it with the scroll edge effect (WIN-4).
- Leading: the window buttons, the Sidebar button (on Calendar, the Back chevron in the same capsule, SCR-1), then the title pill with the screen's icon, title and subtitle. The subtitle says where you are; the content does not say it again.
- Centre: Metric as segments, or as a pop-up that names the metric where the segments do not fit (WIN-10). On Disk, Activity and Space as native segments (SCR-8).
- Trailing: the screen's own items, or Live as one round button on the screens with a range (WIN-5); then one compact capsule, a system control group, with Quit, Inspector, More and Search (WIN-21). View options are toggles in More.
- The one primary action of a screen is prominent: Live while it runs, or an empty state's single action (WIN-18). Other buttons use the standard style.

### Inspector

- A floating glass panel of grouped forms with stock headers and rows, and thin overlay scrollers (INS-2, BLD-2).
- Each titled section is a card that opens and closes (`CardSection`). Its first row has the disclosure arrow, 8 pt from the title, then the title and a summary at the right, so a closed card still says what matters. Open or closed is kept per title (INS-10).
- Every inspector and every pill speaks this card language; the pills may differ in content, not in style. A list that needs selection and arrow keys (Processes) stays a list, with card-style title rows (title, count at the right). A hint for a section is its footer, under the card (INS-10).
- With nothing selected, it gives a summary of the screen (INS-4, INS-6).
- With an app: who the app is, then an action row of small buttons with icon and word; Quit… always has its word (INS-8).

### Tables and lists

- Native tables for things in rows (Apps, Alerts, Volumes, containers, the Hardware inventory). The subject column starts with the icon column.
- A table inside a page that scrolls is as tall as its rows, at the standard row height, and scrolls with the page (SCR-8).
- No swipe actions: row actions are in the context menu (SCR-20).

### Context menus

- Every list item has a context menu where an action is useful (SCR-24, D78). Order: actions on the thing, its System Settings pane, then Copy and Show in Inspector; dividers between the groups.
- Each item has its symbol (`.labelStyle(.titleAndIcon)`) and a hover hint that says the action and the result. Items that do not apply are hidden, not disabled.
- An action that cannot be undone asks first and has "…" in its name (Quit…, Force Quit…, Forget…). An action that can be undone does not ask (Move to Trash, Dismiss All) (SCR-7, SCR-13).
- A failed action shows the system's error, or says what to do next.

### Popovers and hover previews

- One `PreviewCard` for every hover readout: compact (it fits its content, as a chart bubble) or large (380 pt wide). Glass in both sizes (CAL-10, D63, D65).
- A hover preview takes no pointer events, so it never flickers. Its text is also in the host's accessibility value. `previewBeside` puts it on the side with room, inside the window, and never over the hovered cell.
- A list that needs clicks or scrolling is a real system popover.
- Hover hints show after the pointer rests 1 s (WIN-19).

### Part cells

- `partCell` is the cell for a drawn part or a fact (Hardware, Disk, the Calendar month): 12 pt padding (8 pt in a small tile), the quinary system fill, and a 2 pt accent outline while it is selected.
- A cell is one button and one accessibility element, with a hint that says the action. Cells in a row share one height.

### Footer strips

- Every screen has one borderless glass strip across the content column (`ScreenFooter`, WIN-13): one visual that is the screen's own (a trend, the month, the drive, the chip, the battery), then each figure as its value over its label (`Figure`) in equal columns. Only the figures the screen does not already give. The content scrolls under it. Where the content is AppKit panes that take no safe area (Space), the strip is a row under them (D84).

### Charts

- Hover values are in a bubble inside the chart (COL-5). Chart marks never interpolate (MOT-2).
- A chart with more than one series has its key after the title, as a short sample of each series' mark (a line for lines, a square for bars) and its name, never over or under the axis (COL-14).
- Each chart screen has a vertical zoom pill on the chart's trailing edge. Show Whole Range is a text button after "Ranked for" under the chart (WIN-15, D77).
- A sparkline over its threshold is yellow, with a dashed threshold line (COL-8).
- An event marker's shape is its severity, as in Alerts (a triangle for a warning, an octagon for critical); its kind is in its hint and popover (COL-15).

### Menu bar menu

- A real system menu: native highlight, keyboard navigation, type-to-select and VoiceOver, with no custom rows or hover fills (SET-3).
- The levels come first, as native gauge rings in one row, each with its title and level word; then the newest unread alert, Top Apps in right-aligned columns under headings, and the alerts, one line each with the time below (SET-5).
- Every row shows its icon, also where the system hides menu icons (D69).

## Motion

All motion goes through `Motion` (MOT-1 to MOT-7, D67).

- Motion explains a rare change that the user caused (a zoom, a panel, a range, a pin, a dismiss) and never decorates. Frequent actions get no added motion: sidebar clicks, hover, Live ticks, Calendar steps, typing in search.
- `.smooth` only, 0.15 to 0.3 s, no bounce. Every animation can be interrupted; nothing makes the user wait.
- Numbers roll only after a change that the user made; a Live tick swaps the number. Chart marks and readouts do not move.
- With Reduce Motion or Low Power Mode, a move, a scale or a glass morph becomes a short fade or a cut.

## Copy

- ASD-STE100 Simplified Technical English in UI copy, docs and plans. No em dashes or en dashes.
- Never name other apps or repos in the product or the repo.
- Hover hints and action labels say the action and the result where space permits, and name the real target ("Quit Safari and close its windows", not "Quit") (WIN-14). Every icon and button has a hover hint (WIN-9).
- Errors say what failed and what to do next. Alerts name a likely cause (SCR-10).
- Say a fact once: no value or word that the title, the section or the row above already gives (SCR-17, SCR-23).

## Accessibility

- Every interactive control has an accessibility name. A destructive action has a text button.
- Hover-only content is also in an accessibility value; decoration in a drawing is hidden from VoiceOver (COL-12).
- Colour is never the only cue.
- System glass, fills and colours, so Reduce Transparency, Increase Contrast and both appearances work. With Increase Contrast, drawn outlines are stronger (`PartStyle.trace`).
- Keyboard and VoiceOver reach what the pointer reaches: arrow keys move a selection, shift extends it (CAL-11); a hover control also has a menu item (COL-3).

## Process for a UI change

- Read this file and `docs/requirements.md` before a UI change.
- Every UI fix gets up to 3 mockups for the user's approval before it is built, made with the visualize tool and shown inline in the conversation, not as offscreen renders or image files. The exception is a fix where the user gave the exact change. A bug with no visible design choice (a cut-off table, a flicker) is not a design change.
- Record the user's pick: a requirement line and a decision.
- One session builds one page; work on a page is not split across agents (D70).
- Change this file when the design language changes: a new principle, colour role, level, component or interaction. A new size, control or label is a requirement line.
