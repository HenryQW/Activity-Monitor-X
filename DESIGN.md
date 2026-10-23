# Design language

How Activity Monitor X should feel, and the ideas behind each screen. Specific rules (sizes, controls, colours, labels) are in `docs/requirements.md` with their IDs; the reasons are in the decision log. When a new screen or control is not covered there, decide it from this file.

## Character

Premium but calm. AMX is a quiet instrument: it records in the background and speaks only when something needs attention. Normal is quiet, with no colour and no motion. Data comes first, chrome second.

## Principles

1. **Native first.** System controls, fonts and materials with their default look. Custom drawing only where data needs it (charts, the Calendar grid, the treemap, sparklines), and then it uses system colours, fonts and hit areas so it reads as part of the system.
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

- The window has three parts: sidebar (where), content (the data), inspector pane (details of the selection, or a summary of the screen when nothing is selected).
- The toolbar holds the view controls in grouped capsules. Content controls that belong to the data (range bar, period strip) sit above the content, not in the toolbar.
- Glass is for controls that float over content (toolbar, the span capsule). Readouts and panes use a standard material, which keeps text readable over colour.
- Density is compact and aligned: grids are gapless with hairline separators, rows line up, no boxes for decoration.

## Type, numbers and motion

- System text styles only. Numbers that change use monospaced digits.
- Motion explains a change (a number rolls, Live fades in, energy flows) and never decorates. Chart marks and readouts do not move. Reduce Motion turns motion off.

## Voice

- Simplified Technical English, with no em or en dashes.
- Labels and hints say the action and the result, and name the real target ("Quit Safari and close its windows").
- Errors say what failed and what to do next. Alerts name a likely cause.
- Never name other apps or repos in the product or the repo.

## Changing this file

Change it only when the language changes: a new principle, a new colour role, a new interaction. A new size, control or label is a requirement line, not a line here.
