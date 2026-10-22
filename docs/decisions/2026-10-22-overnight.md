# Decisions made overnight, 2026-10-22

The user was asleep from 02:37. For each decision: the goal, the options, my recommendation, the opinion of an independent Opus subagent, and the call. Nothing here was installed, merged or pushed.

## D1. Order of the overnight work

- **Goal:** use the night on the work with the most value that needs no user action.
- **Options:**
  1. Disk writes first, then daemon CPU, then nettop pty, then the M3 plan draft.
  2. M3 plan draft first (unblocks the next milestone), then the daemon fixes.
  3. Daemon CPU first (2.7 % vs the 2 % target), then disk writes.
- **My recommendation:** 1. The disk writes (340 KB/s, over the macOS daily limit) wear the SSD every hour the daemon runs; the others cost only CPU or convenience.
- **Opus opinion:** option 1, with two conditions: find the root cause before fixing (2.1 GB dirtied vs 10 MB/h growth points to write amplification, which may also explain some CPU, so re-measure CPU after the write fix), and run the M3 plan draft in parallel, not last.
- **Call:** option 1 with both conditions. The scope later grew to M3 to M5 (the user's answer at 02:45), so the order is: disk-write fix in its own worktree, in parallel with writing and building M3; then daemon CPU (re-measured after the write fix) and the nettop pty; then M4, then M5.

## D2. Where the daemon fixes live

- **Goal:** keep M2 reviewable while fixing M1 daemon problems found during M2.
- **Options:**
  1. A separate branch per fix (`fix/amxd-disk-writes`, ...) cut from `feat/m2-window`, merged into `feat/m2-window` after review.
  2. Commit straight onto `feat/m2-window`.
  3. Branch from `feat/m1-data` (the M1 branch), so M1 gets the fix before it merges.
- **My recommendation:** 1. Isolated worktree builds do not collide with the Task 11 work in the main checkout, each fix gets its own review, and merging into `feat/m2-window` is a local, reversible step.
- **Opus opinion:** option 1, not 3: M2 changed `Daemon.swift`, `Nettop.swift` and `XPCService.swift`, and the installed daemon is M2 code, so fixes cut from `feat/m1-data` would target code that does not run. Condition: `feat/m1-data` must not merge to main alone.
- **Call:** option 1. M1 and M2 merge into local `main` together (the user allowed local merges, no push).

## D3. Visual evidence for the UI review

- **Goal:** let reviewers judge the real UI, not only the code, while the user sleeps.
- **Options:**
  1. The user grants Screen Recording and UI control to Claude; I capture only the app's window (`screencapture -l <windowID>`) and drive it with System Events.
  2. A debug-only snapshot hook inside the app (renders its own window to PNG).
  3. Code-only review until the morning.
- **My recommendation:** 1, if the user can grant it now; else 3. The in-app snapshot probe (option 2) did not fire its capture with the window in the background, and glass would not render faithfully anyway.
- **Opus opinion:** not asked: the user granted the permissions at 02:49, which settled the choice.
- **Call:** option 1. Only the app window is captured; screenshots are deleted after each review; no other app is driven.

## D4. Milestone 3 open decisions (M3-D1 to M3-D18)

- **Goal:** settle every choice the spec leaves open for Groups, attribution, the CLI and MCP, so M3 can be built tonight.
- **Options and recommendations:** the plan lists 2-3 options and a recommendation for each (the milestone plan (removed; see git history), "Open decisions").
- **Opus opinion:** agrees with 16, disagrees on D10 (hand-written stdio server instead of swift-sdk) and D14 (follows D10), and adds conditions to D1, D2, D3, D6, D11, D12, D18.
- **Call:** the plan's recommendations, with all of Opus's conditions, and D10 = hand-written stdio server. Listed in the plan's "Final decisions" section.
- **D10 reasoning (this reverses your earlier choice of swift-sdk):** you accepted the SDK because it would save a lot of work. The facts tonight say it does not: a tools-only MCP server needs four JSON-RPC methods (~80-150 lines), the SDK glue is about the same size, the SDK is pre-1.0 (0.12.1), and SwiftPM resolves swift-nio and a `swift-docc-plugin` pinned to `branch: main`. Your policy is "a package only when it removes a lot of work". Cost if wrong: swapping to the SDK later replaces one file (`MCPHandler.swift`).
- **Cost if wrong (others):** each is local to one task; see the plan.

## D5. UI pass 1 (toolbar, search, palette, legend, Live)

- **Goal:** remove the toolbar overflow (») the user called "ugly and confusing", and fix what the first screenshot pass found, the native way.
- **Inputs:** design scout, a UI critic's proposal and an Opus designer's challenge to it; the user wants a search field.
- **Options and calls:**
  - Toolbar. (1) Range segmented in the centre, Metric as a pop-up; (2) Metric segmented in the centre, Range as a pop-up in a compact trailing group (Range, filter, Inspector, search). My pick and call: **(2)**. The user flips Metric often and sets Range once; the trailing group keeps the pop-up out of the way.
  - Search placement. (1) top of the sidebar; (2) trailing toolbar field; (3) content header. Critic: (1); challenger: (2). Call: **(2)**, with ⌘F (Edit > Find). The HIG puts sidebar search where it filters the sidebar itself; ours filters the tables, and a sidebar field vanishes when the sidebar is hidden. Search matches app name, process name, path and exact PID; it filters the tables and Pinned Apps, not the chart (totals stay true), and shows a count ("3 of 112 apps").
  - Legend. (1) hidden (the table shows the same dots); (2) one line. Call: **(2)**: the table re-sorts, scrolls and is filtered by search, so it is not a legend.
  - Palette. System colours with well-separated hues; **red and yellow are reserved for severity** (pressure and thermal markers: yellow = warning, red = critical, shape = kind), so apps never look like alerts. Call: as stated (challenger's rule).
  - Live x-domain. Fixed 5 min, **backfilled from the raw tier** so Live does not open 95 % empty. Call: as stated.
  - Ranges use only recorded time (average, x-domain, subtitle "since <date>"); Pin column removed (pin glyph after the name, Process > Pin App ⌃⌘T); app icons in the App column; window and column minimum sizes measured at 1.774 px/pt so » never shows, with or without the inspector.
- **Cost if wrong:** each item is a small, separate view change; the screenshots after the pass show the result.

## D6. Daemon commit and checkpoint cadence (disk-write fix)

- **Goal:** stay well under the macOS disk-write limit (24.86 KB/s) with acceptable data freshness and loss on crash.
- **Options (ticks per commit / checkpoint; measured KB/s):** 1/1 min 24.0; 1/5 min 19.9; 2/5 min 15.2; 3/5 min 13.6; 12/5 min 10.6. Rows reach the DB up to ticks × 5 s late; a daemon crash loses the uncommitted ticks; with `synchronous=NORMAL` a power loss can lose up to one checkpoint interval at any batch size.
- **My recommendation:** 3/5 min: 45 % headroom under the limit for build days with high process churn; 10 s lag is below the app's 15 s reload.
- **Opus opinion:** keep 3/5 min, but only with a fix: the app's history "Exited" rule (`last_seen` older than now − 70 s) loses its margin with 10 s commit lag, so live processes can flash "Exited" about once a minute in a third of daemon runs. Derive the threshold from the cadence (60 + 5 s × (3 + 1) + 5 = 80 s). If the threshold must not change, choose 2/5 min. Run the bench once at a higher churn (10,000 new processes/h).
- **Call:** 3/5 min, with the derived threshold (`exitSlack = 60 + AMX.tick × (AMX.ticksPerCommit + 1) + 5`) as a merge condition, and the high-churn bench run before install.
- **Cost if wrong:** rows up to 10 s late; up to 5 min of history lost on a power cut; one constant to change.

## D7. Disk writes at high process churn

- **Goal:** decide whether the disk-write fix is enough before deploy.
- **Facts:** 13.6 KB/s at the realistic load (2,700 new processes/h); 24.9 KB/s at a stress load of 10,000/h; the macOS limit is 24.86 KB/s averaged over 24 h; the rest is mostly the `processes` table.
- **Options:** (1) accept now, park further work with a trigger; (2) cut `processes` writes now (index, end updates, AUTOINCREMENT, `system_samples` WITHOUT ROWID), each a table rebuild; (3) adaptive commit cadence.
- **My recommendation:** (1).
- **Opus opinion:** (1). Live churn (~3,140/h) maps to ~14.3 KB/s; 20 KB/s needs ~6,800/h sustained for 24 h. (3) makes latency depend on load; (2) has no evidence yet. Condition: the harness did not run tier retention (150 min warm-up), so measure the live daemon over 24 h after deploy (`ri_diskio_byteswritten` or the next diagnostic report); if the 24 h average is above 20 KB/s, do (2), starting with `idx_processes_last_seen` and the end updates.
- **Call:** (1) with that condition and trigger, recorded as a follow-up.
- **First live measurement (04:02 to 04:10, amxd's own `disk_w` rows):** the old daemon wrote about 600 KB/s. The fixed daemon writes about 2 MB at each 5-minute checkpoint and nothing between, about 7 KB/s. The WAL grows 7.6 KB/s, which agrees. One burst of about 96 MB at 04:01 was the one-time removal of the excess free pages. The 24 h average is still open.

## D8. Search placement, revisited (overflow while searching)

- **Goal:** keep the toolbar free of the overflow chevron in every state.
- **Fact from UI pass 1:** the trailing toolbar search (D5) expands while active and pushes the toolbar into overflow below ~1200 pt (minimum is 1020 pt).
- **Options:** (a) raise the minimum width to 1200 pt; (b) accept overflow while searching; (c) a fixed-width search toolbar item (needs an AppKit `NSSearchToolbarItem` wrapper); (d) move search to the top of the sidebar (`.searchable(placement: .sidebar)`).
- **My recommendation:** (a): simplest.
- **Opus opinion:** (d): it takes no toolbar width, keeps the 1020 pt minimum, and matches the layout you like; ⌘F first shows the sidebar if hidden. (a) costs 180 pt always for a temporary state; (b) brings back the chevron you dislike; (c) needs AppKit glue. Condition: check on macOS 26 that ⌘F focuses the sidebar field, else fall back to (b).
- **Call:** (d), with that check (fallback (a), not (b), because you dislike the chevron). This changes the D5 search placement.

## D9. UI pass 2 list

- **Goal:** fix what the pass-1 screenshots still show.
- **Options:** my list (i)-(vii) in local notes, each keep/drop.
- **Opus opinion and call (taken as given):** (i) hover bubble: apps by value, Other last, hide 0.0 %, total on top; (ii) event lane: cluster markers closer than ~12 pt into one with a count coloured by the highest severity, show warning and higher by default, info events in the cluster's hover list; (iii) one peak definition (max chart-bucket value) in the inspector, the Timeline and the Apps tables, so a process peak is never above its app's; (iv) Quit / Force Quit in a solid bottom bar of the inspector (`.safeAreaInset(edge: .bottom)`, bar material, divider); (v) inspector processes: running first, then the top 20 exited by average, then "Show All N"; (vi) draw the last chart bucket; (vii) subtitle in the locale's format without repeating the range ("Since 11:06 PM", "Since Yesterday, 11:06 PM", "Since 21 Oct"); plus: search dims chart series that do not match; fewer x ticks in the inspector chart; no more leading row marks; check the palette under a protanopia filter.

## D10. Milestone 4 open decisions (M4-D1 to M4-D18)

- **Goal:** settle the M4 plan (alerts, notifications, menu bar item, Settings, glossary) so that it can run without the owner.
- **Options and my recommendations:** the "Decisions" section of plans/2026-10-22-m4-alerts-menubar.md. Each decision has options and a recommendation.
- **Research:** local notes (notifications and login items for a self-signed app are not confirmed by any source; MenuBarExtra window reopen and `openSettings` have known macOS 26 problems).
- **Opus opinion:** local notes. It agrees on 17 of 18. It differs on D5: sustained CPU should be 80 % for 30 min, because at 5 min every long build gives a notification. Pre-flight: start alert polling at app level, not in the window; probe the app lifetime chain first (new Task 0); the memory-jump check needs a 30 s wait before the allocation.
- **Call:** all recommendations, with the Opus conditions. D5: keep the spec value (80 % for 5 min, which the owner approved), but re-arm per app only after 60 min, so one long build gives one alert. The morning report asks the owner to choose 5 or 30 min. Task 0 probes the app lifetime chain and fixes each fallback before the UI tasks.
- **Cost if wrong:** D5 is one settings default. A failed Task 0 probe changes the menu bar task to `NSStatusItem`.

## D11. UI pass 3 list and its timing

- **Goal:** fix what the pass-2 screenshots still show, without merge conflicts with the M3 view tasks.
- **Options:** the ranked list in local notes (Opus review of the pass-2 screenshots); run pass 3 now on feat/m2-window, or after M3 Tasks 10 and 11 on the M3 branch.
- **My recommendation:** take items 1 to 8 and the "would not do" list as given; profile the Live CPU first; run pass 3 after M3 Tasks 10 and 11, on the M3 branch, because those tasks edit the same views (sidebar, inspector, toolbar).
- **Opus opinion:** the review itself ranks the toolbar overflow with the inspector open (1320 pt) first and app CPU in Live (25 to 43 % of a core) second; it advises against a 1360 pt minimum width and a custom overflow menu.
- **Call:** as recommended. The CPU profile runs now (read-only); the pass-3 changes start when M3 Task 11 is complete.
- **Cost if wrong:** pass 3 starts a few hours later.

## D12. Live CPU fixes: order and split

- **Goal:** bring Live to the targets (app under 5 %, amxd under 3 %) and cut idle daemon CPU (2.6 %, target 2 %).
- **Evidence:** local notes (screen locked, so app numbers are a lower limit): app 17 % and amxd 15 % in Live; the app rebuilds all 300 snapshots each second; amxd reads `translated`, path and name for every process every second.
- **Options:** (1) one task for app and daemon after M3 Task 11; (2) daemon fixes now in their own worktree (files no M3 task touches), app fixes with UI pass 3 after Task 11 (the same files as Task 10).
- **My recommendation and call:** (2). The profile ranks the fixes; fix 4 (stop Live polling while the window is not visible) goes with the app fixes. Getting amxd under 3 % needs a root `sample` of amxd, which needs sudo outside the helper: "needs owner".
- **Opus opinion:** not asked separately; the profile is an Opus report and ranks the same split by file.
- **Cost if wrong:** one merge of the daemon branch.

## D13. Milestone 5 open decisions (M5-D1 to M5-D17)

- **Goal:** settle the M5 plan (Disk, Disk Map, Hardware) so that it can run without the owner.
- **Options and my recommendations:** the "Decisions" section of plans/2026-10-22-m5-disk-hardware.md.
- **Opus opinion:** local notes. It agrees on 15 of 17, with conditions. D6: if the user-side SMART read fails, fall back to `smart_status` from `system_profiler`, not a root XPC call. D13: cut fans (one RPM reading on a screen read on open tells nothing). Pre-flight: Disk Live must not wake the daemon's 1 s tick; the key filter must drop GUID and UID keys; a TCC prompt may block a scan, so probe it first with a timer.
- **Call:** all recommendations with the Opus conditions, and both Opus differences (D6, D13). Interactive checks of the Disk, Disk Map and Hardware screens go to the morning list; each task gets an unattended check instead.
- **Cost if wrong:** D6 shows less SMART detail; fans can return in a later pass.

## D14: Live CPU after the one-peak ruling

- **Goal:** app CPU in Live at about 5 % of one core with the window shown, with one peak definition (a 1 s spike shows at full height).
- **Facts:** before 19.6 %; after the fix round with 1 s buckets 8.8 % (run noise about 1.5 points); with 3 s buckets 5.4 to 6.1 % (rejected in D12: 3 s means hide 1 s spikes). Screen locked, so this is a lower limit.
- **Options:** (a) accept 8.8 % now and merge, follow-up later; (b) 3 s max-per-bucket chart; (c) redraw the chart every 2 s with 1 s data; (d) a smaller daemon snapshot (protocol change).
- **My recommendation:** (a), then (c).
- **Opus opinion** (independent): (a). Reject (b): a stack of maxima that never occurred together overstates the scale and disagrees with the inspector. (c) alone gives about 6.5 %. A cheaper hot spot: `stacked` walks about 1,500 tracks each second; per-second per-app sums kept by `LiveTracks.append` save about 0.6 to 1 point. Measure with the screen on against a reference reading, before more work. The daemon (6.2 % under Live polling) is the larger lever.
- **Call:** (a). Merge now. Follow-up after M5, in this order: measure with the screen on, then incremental `stacked`, then (c) at 2 s, then (d) only if still over 5 %. Also from the re-review: the Live gate now matches the main window by identifier ("main"), so Settings does not keep Live polling.

## D15: Force Quit scope

- **Goal:** no privilege escalation through the root daemon's `signal` call.
- **Facts:** the daemon signals any pid > 1 for any local user who opens the app; no caller check (XPCService `signal`). Signalling other users' and root processes should need an admin password.
- **Options:** (a) same uid only: the daemon compares the XPC caller's effective uid with the target's uid and refuses with EPERM; (b) same uid or the admin group; (c) same uid free, others with an admin password through Authorization Services.
- **My recommendation:** (a) now, (c) as a follow-up.
- **Opus opinion:** (a), keep the daemon path because (c) needs it; map EPERM to a clear message in the app; bump the XPC protocol to 3 in the same change, so an old daemon without the check shows "out of date".
- **Call:** (a) with the EPERM message "This process belongs to another user." and protocol version 3. (c) is a follow-up.

## D16: Third-party notices

- **Goal:** meet the MIT terms for the ported code, GRDB and the glossary without a file the spec rules out.
- **Options:** (a) full MIT texts in Packaging/Credits.html (ships in the app), a README section that points to it, and each one-line header extended with "See Packaging/Credits.html"; (b) a THIRD_PARTY_NOTICES file.
- **My recommendation:** (a).
- **Opus opinion:** (a); spec line 21 asks for the full notice in each header, so record the pointer header as a spec change; add GRDB, which is missing from Credits.html.
- **Call:** (a), and spec line 21 changes to the pointer form.

## D17: Release fix round scope

- **Goal:** clear the release blockers of the production readiness review tonight.
- **Options:** (a) blockers only; (b) blockers and the should-fix items; (c) all, including deferred items.
- **My recommendation:** (b).
- **Opus opinion:** (b); rename the `-wal` and `-shm` files with a corrupt DB; keep "uninstall keeps the DB unless PURGE=1" (spec §11) and print each kept item; one commit per blocker with `make test` after each; the "Open Helper Settings" button is the one item to cut if time is short.
- **Call:** (b). Deferred with notes: clock-jump guards for rollup and retention, `processes` pruning against the size cap (needs 7 days of data), a 72 h soak, the parent and child view and the temperature display (spec gaps), the D15 (c) password path, the license (owner).

## D18: Which apps get colours in the Timeline chart

- **Goal:** the Timeline must show which apps caused a slow period. On a real 24H CPU view the grey "Other" band held most of every spike, because the top 5 is ranked by the average over the whole range.
- **Options:** A. keep the range average; B. rank by contribution in the busiest buckets (total above the range's 90th percentile); C. keep A, break "Other" into its top processes in the hover bubble, and recompute the top 5 for a dragged span; D. B plus the hover breakdown of C.
- **My recommendation:** D.
- **Opus opinion:** D. Do drag-to-recompute later. Risks: the chart's top 5 can differ from the table's order (label the legend "Top during peaks"); a flat range makes B equal to A (test it); keep a tie-break so colours stay stable between refreshes.
- **Call:** D, with the legend label, the flat-range test and the tie-break. Drag-to-recompute is not built.
- **Cost if wrong:** the chart and the table disagree on the order and users read it as a bug.

## D19: Live table order

- **Goal:** rows must not move under the pointer in Live (the table re-sorts every second).
- **Options:** A. keep re-sorting; B. pause re-sorting while the pointer is over the table, values update in place, a visible "Sorting paused" hint; C. re-sort at most every 5 s; D. sort Live by name by default.
- **My recommendation:** B.
- **Opus opinion:** B. Resume when the pointer leaves, even with a row selected; keep the selected row visible after the re-sort; add new processes at the bottom while paused; make the hint easy to see.
- **Call:** B with those four conditions.
- **Cost if wrong:** a paused table can look frozen.

## D20: Scope of the UI review fix wave (window captures of 0.5.0, 2026-10-22 late morning)

- **Goal:** fix what the first real look at the installed app found, without new features.
- **Call:** fix 19 reviewer findings and 4 field findings in three parallel tasks by area (Timeline, System screens, shell), plan `the milestone plan (removed; see git history)`. Not in scope: drag-to-recompute the top 5, a VoiceOver audio graph, the daemon and app CPU profile (D14 follow-up, next). Dark-mode captures need a relaunch with `-AppleInterfaceStyle Dark`; the system appearance is not changed.
- **Cost if wrong:** some polish items wait for a later pass.

## D21: The inspector does not resize the window (user call)

- **Goal:** opening the inspector should feel native.
- **Before:** `WindowFit` grew a narrow window by the inspector's width before the panel opened, so the toolbar never overflowed. The user found this strange.
- **Call (user, 2026-10-22):** never resize the window for the inspector or the Score segment. The inspector takes its width from the content area, as in Apple's apps. The Metric control turns into a menu picker when the segmented control does not fit, so no toolbar item hides behind the overflow chevron. A minimum content width stops the panes from collapsing.
- **Cost if wrong:** a narrow window shows a compact Metric menu instead of segments.

## D22: Spike ranking uses excess weight (amends D18)

- **Goal:** a short spike must give its cause a colour.
- **Evidence:** the review of D18 as built showed that with a flat baseline, a spike in fewer than 10 % of the buckets moves the 90th percentile to the baseline, so the order falls back to the average; at 24H a 5-minute spike needs about 29 times the baseline to win.
- **Options:** A. keep the 90th-percentile cut; B. weight each bucket by how far its total is above the median total, and rank by the weighted contribution (flat range: all weights 0, so the range average); C. rank by each app's highest bucket.
- **Call:** B. It keeps D18's intent, needs no cut-off, and the flat-range case falls back to the average by itself. C would colour any app with one noisy bucket. Not sent to Opus again: it refines D18, which Opus already supported, and the evidence is a measured limit.
- **Also (D18 colours):** two apps that share a stored colour slot are resolved by the smaller app key, not by rank, so colours do not swap every Live second.
- **Cost if wrong:** one large bucket can outweigh a steady heavy app in the colour choice; the table still ranks by average.

## D23: The inspector is a pane inside the content area

- **Goal:** meet D21 (the inspector never resizes the window).
- **Evidence:** measured in a dev build: SwiftUI's `.inspector` grows any window narrower than 1,320 pt (closed minimum 760 pt plus twice the inspector's 280 pt) before it opens, whatever minimum the app sets.
- **Options:** A. keep `.inspector` and accept growth below 1,320 pt; B. keep `.inspector` with smaller minimums (growth still below about 1,140 pt); C. a trailing pane inside the detail area with a draggable divider, material background (`.regularMaterial`), the same toolbar button and shortcut; the content area shrinks instead.
- **Call:** C. It is the only option that meets the user's call in D21. Not sent to Opus: the user decided the behaviour; this only chooses how to build it.
- **Cost if wrong:** the pane needs its own divider and width memory, which `.inspector` gave for free.

## D24: Event markers use one native popover for hover and click

- **Goal:** the user's call: hovering and clicking an event marker showed different pop-ups. The user wants them to look exactly the same, with the native popover and no customisation.
- **Evidence:** the hover showed a custom glass bubble (`hoverBubble()`, caption font, one line per event); the click showed a system `.popover` with `EventList` (body font, messages).
- **Call (user):** hover and click show the same native `.popover` with the same content and default system styling (no custom font, background, glass or corner radius). Hover opens it and leaving the marker closes it; a click keeps it open until a click outside or Esc. The custom hover bubble for events is removed.
- **Value bubbles (user, later):** the Timeline and Disk value bubbles also become native popovers if they can follow the pointer without flicker. Probe order: SwiftUI `.popover` with a moving `attachmentAnchor`; then AppKit `NSPopover` with its `positioningRect` updated while shown. If neither follows without flicker, keep the bubbles and record the evidence. Native `.help` tooltips stay.
- **Cost if wrong:** a popover that opens on hover can be noisy when the pointer crosses the lane; if so, add the system tooltip delay.

## D25: Menu bar item with a CPU sparkline (user call)

- **Goal:** a more useful menu bar item. Research: local notes.
- **Options:** A. text only (as now); B. native `MenuBarExtra` with a template sparkline image plus the numbers, two tiles in the popover; C. `NSStatusItem` with drawn widgets.
- **Call (user):** B. The label is a template image (24x12 pt CPU sparkline of the last 60 samples plus the CPU and memory pressure numbers), so light, dark and tint stay correct; pressure is not shown by colour. The popover gets two tiles (CPU with the same sparkline, Memory Pressure with its level word) above Top Apps and Recent Alerts. No custom glass or styling on the tiles (the user wants native views). One setting: "Text only" or "Text + chart". Cadence unchanged: 5 s closed, 1 s open. No third-party code, so no MIT notice is needed.
- **Cost if wrong:** about 120 lines in the MenuBar folder and Settings.

## D26: Hover hints on every icon and button (user call)

- **Goal:** when the pointer rests on an icon or a button for 3 s, a small hint says what it does.
- **Call:** the native tooltip (`.help`) on every icon-only control, toolbar item, sidebar footer button, inspector action, table hover button and menu bar control, with text that says the action (for example "Show the inspector", "Pin Safari to the sidebar"). Hints use the system tooltip delay (about 1 s), as other Mac apps do (user call, revised from 3 s). No custom hint views (ADR 0009).
- **Cost if wrong:** 3 s is longer than the system default (about 1 s); the value is one line to change.

## D27: Smooth Live chart and appearance setting (user calls)

- **Smooth Live chart:** the Live chart jumped each second. Call: monotone curve interpolation on the Live marks, plus a linear one-second slide of the time axis when a point arrives, only if the app still meets the Live CPU target of D14 (at most 5 % average); else interpolation only, with the numbers in the report. Built with the D14 work, because both change the Live chart.
- **Appearance:** Settings > General > Appearance: System (default, follows the macOS light or dark setting as it changes), Light, Dark. It sets `NSApp.appearance`, so every window, the Settings window and the menu bar popover follow it.

## D28: Sidebar items can be reordered by drag and drop (user call)

- **Goal:** the user reorders the items of the Monitor section (Timeline, Apps, Alerts) and of the System section (Disk, Disk Map, Hardware) by drag and drop.
- **Call:** native `List` reordering (`.onMove`) inside each section only; a drag never moves an item to another section. The order is stored per section in the app's defaults; a missing or unknown item falls back to the default order, and new items in later versions go to the end. Groups and Pinned Apps are out of scope (groups keep their own order).
- **Cost if wrong:** small; the default order stays one reset away (a "Reset Sidebar Order" command is not added unless asked).

## D29: Alert rule details the spec table does not give

- **Units:** GB and MB in alert rules are binary (2^30, 2^20 bytes), as in the memory rules.
- **Boundaries:** every rule fires at its threshold (`>=`; free space at or below its percent).
- **Ranges:** CPU and memory ranges scale with the Mac; the new rules have fixed ranges (for example disk writes 1 to 1,000 GB per hour, free space 1 to 50 %).
- **Presets and switches:** choosing a preset sets thresholds only; each rule's on/off switch stays as the user left it, and turning a switch on or off does not change the picker to Custom. A new install has every rule on.
- **Held rules start fresh:** an app whose samples were all zero needs a full new window of load before a held rule (CPU, network, energy, GPU) alerts.
- **CPU row:** shows % of all cores with one decimal, and writes only on a real edit, so an old value (80 % of one core) keeps its stored value.
- **Disk writes over gaps:** the hour total of an app survives ticks where the app has no live process, so bursty short-lived writers are caught.

## D30: Hardware core squares show live usage (user idea)

- **Goal:** the core squares on the Hardware screen show what each core does now.
- **Call:** CPU squares: each square is one core, filled with the accent colour at an opacity that follows that core's usage (0 % is the plain grey square, 100 % is the full accent colour); per-core usage comes from `host_processor_info` in the app (no root), sampled every 2 s only while the Hardware screen shows. Cores map to the Super and Performance groups through `hw.perflevelN` (logical CPU counts and order); if the order cannot be proved, squares fill in index order and the screen says nothing more. GPU squares: macOS reports no per-core GPU use, so the number of lit squares follows total GPU utilisation (40 % of 16 lights 6). Each square has a hint ("Performance core 3: 42 %"). No red or yellow: those mean warning and critical only.
- **Cost if wrong:** about 2 s of sampling work while the screen shows; none when hidden.

## D31: Timeline and Apps become one Apps screen (user call)

- **Goal:** one sidebar entry for the app list over a range; the two screens differed only by the chart.
- **Call:** the sidebar's Monitor section has **Apps** and **Alerts**. Apps shows the chart (event lane, top 5 and Other) above one table; **Show Chart** (toolbar toggle and View menu item, on by default, saved) hides the chart. The one table keeps process expansion, sorting, the hover link to the chart band and the inspector path, and gains the Trend sparkline column (one shared scale per metric) and the Pin column; columns can be hidden with the native column menu. Pinned apps still open their own chart view. Window title "Apps". Command-number shortcuts follow the new order. Links that opened the Timeline at a time (alerts, notifications) open Apps at that time.
- **Cost if wrong:** one screen to split again; the old Apps code is deleted, git keeps it.

## D32: The inspector is a bento of native cards (user call)

- **Goal:** a richer, calmer inspector than a plain list of sections.
- **Call:** a scroll view with `GroupBox` cards in a `Grid` (bento): a header card (icon, name, path), two small tiles (Average, Peak), a full-width chart card, an About card beside a Peak Process card, an Alerts card, a Processes card (Running and Exited; a selectable `List` inside, so arrow keys still move the selection), and the actions (Show Processes, Pin, Quit, Force Quit) at the bottom. The group summary uses the same cards. Default `GroupBox` look; no glass on content cards (glass is for the control layer). Section titles say "Alerts", never "Events" or "Warnings".
- **Cost if wrong:** layout only; the data and actions stay the same.

## D33: Sidebar and list refinements (user picks)

- **Collapsible sections:** Groups and Pinned Apps collapse with the native section disclosure; the state is saved.
- **Add Group footer:** an "Add Group" button at the bottom of the sidebar and File > New Group (⌘⇧N) replace the "+" in the Groups header; an empty Groups section is hidden, so the footer is the one way to add the first group. Alert rows in Today and Yesterday show the time only (the section names the day).
- **Alerts badge:** the count uses the default look; it becomes prominent (`.badgeProminence(.increased)`) only while a critical alert is unread.
- **Alerts by day:** the Alerts list groups rows under Today, Yesterday and Earlier. A Dismiss action hides an alert; "Show Dismissed" (toolbar toggle and View menu) shows them again, dimmed. Dismissed ids are kept by the app (the daemon stays the only database writer), newest 10,000.
- **Row menus and swipe:** every app row and alert row has its actions in a right-click menu (app rows: Show in Inspector, Pin or Unpin; alert rows: Show in Apps, Dismiss or Restore); a trackpad swipe left on an alert dismisses it.
- Not built: hiding sidebar items, search scopes.

## D34: Hide Quiet icon and cheaper Trend lines

- **Icon (user ask):** Hide Quiet System Processes uses `moon.zzz` (idle processes put to sleep) instead of the generic filter lines.
- **Trend column:** each row draws its sparkline as one path (`SparklineShape`, shared with the menu bar) instead of a chart per row, because Live measured 6 to 6.5 % CPU with the Trend column on the Apps screen (target 5 %).

## D35: Sidebar button after the traffic lights

- **Problem (user ask):** the system sidebar toggle sat in the toolbar and went into the overflow menu at normal widths, so hiding the sidebar took 2 clicks.
- **Call:** remove the system toggle and add one "Hide Sidebar" / "Show Sidebar" button (`sidebar.left`) at the navigation placement, directly after the window buttons. It sends `toggleSidebar(_:)`, so the native animation and the View menu item stay the same. The window width does not change.
- **Checked:** one click hides and one click shows the sidebar; the window stays 1300 pt wide; nothing goes into the overflow menu.

## D36: Search as a toolbar icon (user pick)

- **Call:** search moves from the top of the sidebar to the trailing end of the toolbar as a magnifier that expands into the full field on click or ⌘F (`.searchToolbarBehavior(.minimize)`). It takes one icon of width until it is used.

## D37: Inspector pills (user pick)

- **Call:** a segmented control at the top of the inspector switches between Overview (the cards) and Processes (Running and Exited, Force Quit). Each view is short, so the pane does not scroll far. This replaces the single scroll of D32. Opening the inspector at a process selects Processes.

## D38: Calendar screen (user pick)

- **Call:** a Calendar item in Monitor shows Day, Week or Month as cells shaded by the chosen metric, summed over all apps per hour or per day, with ‹ Today › steps. A click opens Apps at that hour or day. One accent scale; no red or yellow.
- **No Year view:** history keeps 90 days, so a year would be mostly empty.
- **Day value:** a Month cell shows the mean of its hours, not the sum: each metric is a level or a rate, so a sum of hours has no useful unit. Hours with no data are left out, so a partial today compares with full days.
- **Screen type:** Calendar shows no app rows, so it acts like a System screen (no search, inspector, Hide Quiet or Live polling) and keeps only Metric in the toolbar. View > Calendar is ⌘6. A saved sidebar order gets Calendar at the end of Monitor.
- **Show in Apps** (from a cell or an alert) always opens a window that ends now.

## D39: Range menu groups and steps (user pick; steps replaced by D40)

- **Call:** the Range menu splits Live, the short ranges and the long ranges with dividers. Back and forward arrows step the shown window by one range length (not in Live, not past the present or past 90 days); a Now item returns to the present, and the menu title shows when the window is in the past.

## D40: Range popover replaces the arrows (user ask)

- **Problem:** the user found the back and forward arrows next to Range not intuitive.
- **Options:** keep the arrows; a menu of quick ranges only; a popover with quick ranges and a custom From and To (the common pattern in metrics dashboards).
- **Call:** a popover on the Range button: From and To date pickers (inside the 90 days of history, up to now) with Apply, and the quick ranges with dividers. The arrows and the step offset are removed. Text expressions, recent ranges, search and time zones are left out: for one Mac's 90 days they add little.
- **Calendar keeps ‹ Today ›:** that control is the pattern the user asked for on that screen.

## D41: Search magnifier and inspector below the toolbar (user asks)

- **Search:** macOS has no API to keep the toolbar search collapsed, and with free width the system shows the full field. So the toolbar's last item is a magnifier; a click or ⌘F swaps in the system field, and cancel with an empty query swaps the magnifier back. A background view hosts the field, so the swap does not rebuild the screen.
- **Inspector pane:** its material stays inside the safe area, so it starts below the toolbar and the toolbar keeps one colour across the window.

## D42: Hover highlight and solid toolbar (user asks)

- **Hover:** hovering an app without a band of its own dims every band (Other too) and draws that app's series as a line in `AppPalette.hover` (`Color.primary`), a colour reserved for hover and never given to an app. Before, the chart only dimmed the coloured bands, so it looked all grey.
- **Toolbar:** the window toolbar draws a solid background (`toolbarBackgroundVisibility(.visible)`), so it keeps one colour over the content and the inspector pane in light and dark.

## D43: Chosen app colour (user pick)

- **Control:** a split button (swatch and chevron menu) in the inspector header and a Colour submenu on app rows. Choices are system colours without red, yellow, pink and the hover colour; None returns the app to automatic.
- **Meaning:** a chosen colour also keeps the app as its own band in the chart, after the top 5, even when it is not in the top 5. Stored in the app.
- **Open:** an automatic colour can equal a colour the user chose for another app.

## D44: Inspector functions (user picks)

- **Selected app:** Compared to Usual (this range against the same hours of the 7 days before, from the hour tier; needs 2 days), Launch History (process starts and quits), Alert Rules (per-app mute and thresholds, kept by the daemon so they work while the app is closed), and a Files pill (open files and sockets from the daemon). Pills: Overview, Processes, Files.
- **No app selected:** System Health (worst memory pressure and most swap in the range, thermal state and uptime now), Biggest Changes (against the previous range of the same length), and alert counts by rule with Show in Alerts.
- **Privacy:** Files shows only the user's own processes, the same rule as Quit; another account's open files are private.
- **Protocol:** XPC protocol 5; the daemon needs the matching install.

## D45: Capture review fixes

- Calendar: no-data cells are outlines; today is marked. Hardware: plain names for system keys, readable core counts, tiles sized to content. Disk: one x domain for all charts, legend above the plot. Inspector: one-line app name; a disabled Quit button with its reason as help.
- Not changed: the marker legend stays grey (its shapes stand for both severities); Apply already is the default button (it looked grey only in an inactive window); orange stays an app colour (the palette keeps 32° of hue from yellow, measured).

## D46: Chart crash and crash audit

- **Crash:** the app closed a few seconds after launch when the pointer rested on a table row. The hover line (D42) used a plain colour next to the chart's colour scale, and Charts traps in layout on that. Fix: the hover line and area use the scale, and the hover entry stays in the scale's domain at all times.
- **Audit:** three reviewers read the Charts code, the app and core code, and the daemon, XPC and SQLite paths. Fixed: duplicate list ids in the Files pill, overflow in rule fields and volume sizes, reversed or zero-width Disk axes, label and key collisions, a non-Gregorian calendar unwrap, a settings message (`-1e400`) that aborted the daemon, the same in `amx mcp`, clock steps (monotonic rate clocks, rollup watermarks, empty-bucket jumps), full-disk retention order, a zero row after each daemon start, and an open-files read cap.
- **Open (user call):** the local signing key is imported so that `codesign` needs no prompt; any process of the same user can therefore sign as the app and pass the XPC pin. Closing this means a prompt for each signing.

## D47: Energy flow screen (user pick)

- A System screen "Energy": a live band diagram from Adapter and Battery to the Mac and on to the top 5 apps and Other, band width in watts, updated each second while shown; a 5-minute system power chart below. App watts are the Mac's watts times the app's energy share (an estimate). Missing values show "Not available", not 0 W. Desktops without power data show only shares.

## D48: Live toggle and start settings (user asks)

- **Live:** a toggle before Range and Range > Live (⌘L) turn Live on and back off to the range before it; the quick ranges keep ⌥⌘1 to ⌥⌘5. The compact toolbar now starts below 900 pt of detail so nothing overflows.
- **Start:** Settings > General has "Open at" (Last Screen by default) and "Time range at open" (Last Used by default). The app now remembers the last screen and range.
