# AGENTS.md

Activity Monitor X: a root daemon (`amxd`) records per-process history in SQLite; a SwiftUI app (macOS 26, Liquid Glass) and a CLI/MCP server (`amx`) read it. Read this file first; open the spec only for the section you need.

## Where things are

| Need | File |
|---|---|
| What must be true now (wins over the spec) | `docs/requirements.md` |
| What to build (original design) | `docs/specs/2026-10-21-activity-monitor-x-design.md` (§4 architecture, §5 sampling, §6 storage, §7 XPC, §8 UI, §9 alerts) |
| Why it is built this way | `docs/adr/` (one decision per file) |
| How the app should feel (design language and principles) | `DESIGN.md` |
| Words and their meaning | `GLOSSARY.md` |
| Full decision log (D1 and later, with options and evidence) | `docs/decisions/2026-10-22-overnight.md` |
| Active plans (deleted when done; git keeps them) | `docs/plans/` |
| Resumable state (git-ignored) | `.context/progress.md` and the local work ledgers (git-ignored, kept out of the repo) |

Code: `Sources/AMXCore` (models, schema, queries, rules; no UI), `Sources/CAMX` (C shim), `Sources/amxd` (daemon, only DB writer), `Sources/ActivityMonitorX` (app), `Sources/amx` (CLI, MCP). Tests: `Tests/AMXCoreTests`.

## Build and test

- `make test`: the only way to run tests (it passes the Swift Testing plugin path).
- `make app`: builds and signs `.build/Activity Monitor X.app` (needs `make cert` once).
- Signing runs without a prompt (D52): `codesign` has standing access to the key, so builds and installs run unattended. If macOS ever asks, click "Always Allow" once.
- `make install-app`: copies the app to `/Applications`, no root.
- `make install`: daemon + CLI + app; needs the user's sudo password. Agents never run it; ask the user.
- Linker "search path ... not found" warnings are harmless toolchain noise.

## Toolchain traps (Command Line Tools only, no Xcode)

- No SwiftUI macro plugin: `@State`, `@Entry`, `#Preview` do not compile. Use `private let _x = State(initialValue: ...)` and `_x.wrappedValue` (see any view). `@Observable`, `@Bindable`, `@AppStorage`, `@Environment` work.
- `ViewThatFits` does not work inside toolbar items; measure width instead.
- SwiftUI `.inspector` grows the window; the inspector is an in-content pane (ADR 0007).
- In agent worktrees plain `git` may be refused; use `/usr/bin/git`.
- A `MenuBarExtra` alone does not keep a SwiftUI app running: `applicationShouldTerminateAfterLastWindowClosed` returns false while the item shows.
- Notifications and login items need the app run from its bundle with the signing identifier equal to the bundle ID; dev builds (other ID) have both off.
- `windowToolbarStyle` is ignored on the `Settings` scene; Liquid Glass on toolbar, sidebar and popovers is automatic.

## Rules for changes

- Every change is committed. Work on a branch (or an agent worktree branch) and merge it into the integration branch only after review and acceptance; commit small, one concern per commit. No uncommitted work at the end of a task.
- Smallest change that follows the existing code; match comment density and naming.
- Read `DESIGN.md` before a UI change. Specific design rules are requirement lines; change `DESIGN.md` only when the design language changes.
- Native SwiftUI and AppKit components with default styling first; no custom fonts or backgrounds on popovers, tiles or cards (user call, D24, D25). Every popover and hover preview is Liquid Glass, whatever its size: native popovers by default, the shared `PreviewCard` with `.glassEffect` (user call, D65).
- Colours: red and yellow mean warning and critical only; app colours never use them. App colours are stable per app (`appColorSlots`).
- Every interactive control has an accessibility name; destructive actions have text buttons.
- The window never resizes itself (no growth for the inspector or toolbar).
- Docs, plans, reports and UI copy: ASD-STE100 Simplified Technical English, no em or en dashes.
- Hover hints and action labels say the action and the result where space permits ("Quit Safari and close its windows", not "Quit").
- A requirement that changes or is new: add or edit its line in `docs/requirements.md` in the same commit (rules at the top of that file).
- New decision: add a `D<n>` entry to the decision log; add an ADR only if it is hard to reverse, surprising and a real trade-off.

## Running and checking the app

- To launch a build for a check, run `make run-dev` in the background: it builds "Activity Monitor X Dev" (bundle ID `com.henryqw.activitymonitorx.dev`, so the Dock and Spotlight never open it instead of the installed app), waits until no other dev build runs, and unregisters it when it quits. Quit it by PID (`pgrep -f "Activity Monitor X Dev.app"`), never `pkill -x`. The daemon accepts the dev ID only after the next `make install`; before that a dev build gets no live data.
- Drive the app through System Events accessibility (`AXPress`, `selected` of outline rows, `size of window 1`); it works in the background. CGEvent clicks do not land. Re-resolve `window 1 of process` each time: stored references break when the title changes.
- Screenshots: window only (`screencapture -x -o -l <window id>`, id from `CGWindowListCopyWindowInfo`); never the full screen; delete after review.
- Dark mode check: relaunch with `--args -AppleInterfaceStyle Dark`; never change the system appearance.
- The database is `/Library/Application Support/ActivityMonitorX/history.sqlite` (readable with `sqlite3 -readonly`).

## Never

`git push` without the user's go-ahead; sudo; launchctl; keychain changes; system settings changes; deleting outside the repo.
