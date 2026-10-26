# Design language

How Activity Monitor X should feel, and the ideas behind each screen. Specific rules (sizes, controls, colours, labels) are in `docs/requirements.md` with their IDs; the reasons are in the decision log. When a new screen or control is not covered there, decide it from this file.

## Character

Premium but calm. AMX is a quiet instrument: it records in the background and speaks only when something needs attention. Normal is quiet, with no colour and no motion. Data comes first, chrome second.

## Principles

1. **Native first.** System controls, fonts and materials with their default look. Custom drawing only where data needs it (charts, the Calendar grid, the treemap, sparklines, the Hardware board), and then it uses system colours, fonts and hit areas so it reads as part of the system. A drawing of a real thing looks like that thing: a system symbol where one exists (`cpu`, `memorychip`), a drawing in the symbol style only where none does. The parts of such a drawing may have a light system fill, as the clickable parts of the data they are; that is not a decorative box.
2. **Colour is information.** Three roles, never mixed:
   - Identity: which app. Each app keeps one colour everywhere, and app colours are never red or yellow.
   - Status: yellow for a warning, red for critical, only when a value is over a rule.
   - Interaction: the accent marks the selection, grey marks the hover.
   Colour is never the only cue; a shape or text goes with it.
3. **Overview first, details on demand.** The chart or grid gives the shape at a glance; a hover gives a preview; a click puts the full details in the inspector; a double-click goes one level deeper.
4. **Loud only for what matters.** Warnings arrive quietly, critical alerts interrupt. The menu bar item adds one glyph, not a colour.
5. **Stable.** The window never resizes itself, controls do not jump, numbers keep their column, an app keeps its colour, and a hover never changes the data.
6. **Honest data.** Missing data says so and is never a zero. An estimate says "About". A lost connection keeps the last data and says when it is from.
7. **Reachable without a mouse.** Every hover or drag action also has a menu item, a shortcut or an accessibility action.

## Interaction grammar

- Hover shows. Click selects. Double-click goes deeper. Drag selects a span, drawn as one rectangle. Right-click lists the actions on that thing.
- Selection (accent) and hover (grey) can show at the same time and never look alike.
- One preview component serves every hover readout, in a compact and a large size. A readout takes no pointer events, so it never flickers. A list that needs clicks or scroll is a real popover.

## Surfaces

- The window has one background. On it float the sidebar (where) and the inspector panel (details of the selection, or a summary of the screen); the content column (the data) lies between them. Opening the inspector shrinks the content column, never the window.
- Three levels. Level 1 is the window chrome: the toolbar row (a title pill with the screen's icon, title and subtitle, then the item capsules) and the panels. Level 2 is the content controls that belong to the data (range bar, span capsule, footer, Calendar bar, Space capsules): smaller glass capsules in the content column. Level 3 is the data: edge to edge, under levels 1 and 2 with a soft edge, never glass. Nothing important sits under a capsule at rest.
- One layout grid: 8 pt insets and gaps, 12 pt inside capsules, 16 pt panel corners.
- The one primary action of a screen is prominent; other buttons use the standard style.
- The toolbar holds the view controls in grouped capsules. Content controls that belong to the data (range bar, period strip) sit above the content, not in the toolbar.
- Glass is for everything that floats: toolbar items, the panels, level 2 capsules, every popover and hover preview. System glass only, so Reduce Transparency and Increase Contrast work. Glass never sits on glass: controls inside a glass capsule are borderless.
- Density is compact and aligned: grids are gapless with hairline separators, rows line up, no boxes for decoration. Parts shown side by side share one height.
- In a list, an icon names a thing (an app, a device, a volume), never a value or a group. Icons sit centred in one fixed-width column, and a row with none keeps the column empty, so the names at one level line up.

## Type, numbers and motion

- System text styles only. Numbers that change use monospaced digits.
- Motion explains a rare change the user caused (a zoom, a panel, a range, a pin, a dismiss) and never decorates. A frequent action gets no added motion: sidebar clicks, hover, Live ticks, Calendar steps.
- Numbers roll only after a change the user made; a Live tick swaps the number. Chart marks and readouts do not move.
- Curves are the system's smooth spring, short, with no bounce. Every animation can be interrupted; nothing makes the user wait.
- Reduce Motion turns a move, a scale or a glass morph into a short fade or a cut.

## Voice

- Simplified Technical English, with no em or en dashes.
- Labels and hints say the action and the result, and name the real target ("Quit Safari and close its windows").
- Errors say what failed and what to do next. Alerts name a likely cause.
- Never name other apps or repos in the product or the repo.

## Changing this file

Change it only when the language changes: a new principle, a new colour role, a new interaction. A new size, control or label is a requirement line, not a line here.
