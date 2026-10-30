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

## D32: The inspector is a bento of native cards (user call) (cards replaced by D53)

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

- **Live:** a Start Live (play) button before Range and Range > Start Live (⌘L) start Live; Pause Live (pause) returns to the range before it (user pick); the quick ranges keep ⌥⌘1 to ⌥⌘5. The compact toolbar now starts below 900 pt of detail so nothing overflows.
- **Start:** Settings > General has "Open at" (Last Screen by default) and "Time range at open" (Last Used by default). The app now remembers the last screen and range.

## D49: Signing asks before each use (user pick)

- **Problem:** the key was imported with `-T /usr/bin/codesign`, so any process of the same user could sign its own binary as the app and pass the daemon's XPC pin (found in the D46 audit).
- **Call:** `make cert` imports the key with no standing access; macOS asks before each signing. The existing key is re-imported from an export of the same identity, so the certificate (and the pin's leaf hash and the root helper's check) stays the same.
- **Cost:** one prompt per `codesign` call; agents cannot sign without the user, so unattended install loops stop at signing.

## D50: Search and inspector on every screen (user pick)

- Search and the Inspector button show on every screen and work on what the screen lists: apps (Apps, Alerts, Calendar, Energy), volumes and disks (Disk), files (Disk Map), rows (Hardware). The inspector shows the selection: a Calendar cell's top apps, an Energy app (the app inspector), a volume or disk, a file, a hardware row; with no selection, a short screen summary.
- The query stays between screens that search apps and is cleared when moving to or from Disk, Disk Map or Hardware. A Calendar click selects a cell; Show in Apps opens it.

## D51: Smooth Live start and inspector margins (user asks)

- **Live:** Start Live keeps the current chart until Live has its own data, then fades over; Pause Live shows the earlier range at once and refreshes it quietly. Live polls at once after Start Live. Live polls only while the window is visible, as before.
- **Margins:** every inspector box adds the inner margin of the system's grouped forms to the default `GroupBox` (its own inset left text too close to the edge).

## D52: Unattended signing again (user call, replaces D49)

- **Goal:** builds and installs run without the user (the agent loop signs and installs on its own).
- **Conflict:** any setup that lets the agent sign without a prompt lets every process of the same user sign too; the daemon's XPC pin and the root helper then trust such a binary. A prompt is the only thing that tells them apart.
- **Call:** `codesign` gets standing access to the key again (`make cert` imports with `-T /usr/bin/codesign`; for the current key, "Always Allow" once at the next prompt). Accepted risk on a single-user development Mac; the pin still keeps out other users and unsigned code, and the root helper still installs only binaries, never configuration.

## D53: Inspector as a grouped form (user pick, replaces the cards of D32)

- **Why:** the `GroupBox` cards had grey titles and tight rows, unlike the system's own grouped panes.
- **Call:** the Overview pill, the no-app summary and the screen inspectors are a native `Form` with `.formStyle(.grouped)`: one `Section` per former card, `LabeledContent` rows, stock headers, row height, separators and margins. Average and Peak are rows, not side-by-side tiles. The Processes and Files pills stay lists with keyboard selection. The pane keeps its material behind the sections.

## D54: Colour dot, Files form, menu icons, user request list (user asks)

- **Colour dot:** the dot before an app's icon, in the app list, Top Apps, Biggest Changes and the inspector header, is the one colour control (`AppColorDot`). A click opens the colours and None. While the pointer is on it, a chosen colour shows a cross at its corner, and only a click on the cross removes the colour. An app with no colour shows a ring under the pointer. The split button of D43 and its "last colour" are removed. The inspector's dot is 16 pt, the list's 12 pt.
- **Files pill:** a grouped form like Overview: the state and Refresh are one `LabeledContent` row, so Refresh lines up with the rows' trailing edge.
- **Scroll bars:** stock `NSScroller`s. With a mouse connected and "Show scroll bars: Automatically", macOS shows the wide legacy bars in every app. The app does not override this (no API in SwiftUI; an AppKit override would ignore the system setting). Content insets stay stock and already adapt to the bar.
- **Menu bar item:** Open, Settings and Quit have icons, as macOS 26 menus do.
- **User request list:** `docs/user-requests.md` lists every standing user request in one line with its D-number, so later changes do not undo them. Renamed `docs/requirements.md` (D55).

## D55: Requirements file (user ask)

- **Why:** the request list holds what must be true now, not decisions; its old name hid that, and the spec still claimed authority over changed UI.
- **Call:** `docs/user-requests.md` becomes `docs/requirements.md`: stable IDs by area (WIN, INS, COL, SCR, SET, BLD), edited in place, each line with its D-number, "(user)" on what the user asked for. It wins over the spec where they differ. The decision log stays the append-only why; ADRs stay for hard-to-reverse choices.

## D56: Optimisation pass (user approved criteria and batches)

- **Scope:** no new features and no visible change. Criteria, baseline and the four review reports are in the git-ignored `.context/review/`; batches A (idle CPU), B (table memory), C (queries), D (hot loops), E (daemon) and F (simplify) were approved.
- **User calls:** keep "Compared to Usual" and "Biggest Changes" for up to 1 h while the range and its settings stay the same (also across a Live visit; a change of range, window, metric, group or quiet filter recomputes them at once); keep the inner decoders of partly hand-edited alert rules; the WAL checkpoint waits only briefly for readers, so it cannot block the daemon queue and Live for seconds; keep the row Colour submenu for keyboard and VoiceOver (COL-3 edited); a colour change rebuilds only the chart bands from the tracks in memory, with a full reload while a load is in flight.
- **Not done:** the MCP `summarize` single read (agent-only, adds code). Risks for later: `processes` rows are kept 90 days and the size cap does not prune them (about 1.1 GB at the measured churn, so a 1 GB cap cannot be met); the app keeps reading a database that the daemon moved aside as corrupt.
- **Result (same scenarios as the baseline):** app on 24H with the window open 0.97 % to 0.38 % CPU; app memory on 24H settles at 110 to 160 MB, peaks on a reload 475 to 550 MB before and 275 to 365 MB after; the app table's row arrays fell from 62 MB to 28 KB (heap); the Other band build 8.1 ms to 0.43 ms (benchmark); daemon 0.85 % to 0.78 % CPU, about 1.1 s less CPU at each start. Live CPU was not compared: the measured Live window may not have been on screen. Final review: no high or medium defects; three low ones fixed (Live reset race, event times while Live starts, Calendar catch-up after the window shows again).

## D58: UI batch after the optimisation pass (user asks and picks)

- **Range bar (user pick):** the time range left the toolbar: a custom window made the Range button too wide. A range bar above the content (Live, 1H, 24H, 7D, 30D, 90D, the shown window, Custom…) is on Apps, pinned apps, groups and Disk. The range subtitle is gone. Metric becomes a pop-up that names the metric below 840 pt of detail width (1050 pt with the search field open), from measurements; with the search field open, a window of 800 pt or less still overflows.
- **Search:** an empty field closes back to the magnifier when it loses focus (`searchFocused`).
- **Energy (user picks):** a click opens an app into its top processes (a 4th column); right-click actions; Keep in Flow (stored per app key); Sort by watts or name. Show in Apps opens Apps in Live with the Energy metric.
- **Smaller asks:** Dismiss All on Alerts; "Open at" renamed "Window opens with"; process rows start under the app name; the menu bar actions' icons in one column.
- **Chart hover bubble:** the native popover that followed the pointer (D24) flickered when the pointer ran into it, so the bubble is back inside the chart, with no pointer events (the D24 fallback).
- **Design review:** research and a visual board (git-ignored `.context/board/`) wait for the user's picks; nothing from it is built yet.

## D60: Design review batch (user picks from the board)

- **Goal (user):** AMX looks premium but not flashy. Research on two native-design reference apps and on colour encoding went to a git-ignored visual board (`.context/board/`); the user picked or approved each card over 6 rounds.
- **Built:** chart bubble on a standard material; usual value beside Average and Peak; screen summaries with no selection; selected app emphasis; menu bar glyph and top unread line; Live keeps data when the helper is lost; yellow low-space bars; Launch History and alert rows select chart time; native digit roll (variant 2: least work per frame, system centred); passive warnings with "Banners for"; toolbar capsules with a Quit and Info group and a More menu; alert causes for thermal, swap and low disk (daemon); span capsule with Zoom Out and Clear Selection; inspector action row; Launch History run bars; popover gauges; metric footer; PID and User columns (daemon sends uid); Disk details grid (verified badge kept); Disk Map merged into Disk as Space with file-kind colours.
- **Colour (user pick A plus E glyphs):** identity colours stay; status yellow and red mark only values over a rule (sparkline over the threshold, low space). Heat scales on cells were ruled out.
- **Copy rule (user):** hints and labels say the action and the result where space permits (AGENTS.md).
- **R6 time zone (user pick):** a forced time zone applies to the whole app, not one view.
- **Not built:** desktop widget (user: no); R6 Calendar grid (approved in round 6 with the shared PreviewCard; being built); popover sparkline colour (needs a system CPU rule, user call); Threads and Ports columns (cost daemon reads, user call); Space right-click menu (user call).

## D63: R6 Calendar, shared preview card, app-wide time zone, system CPU rule (user picks)

- **R6 (user approved round 6):** gapless grid with hairlines, one outline for a drag span, zoom Month to Hour, large hover preview, weekend and today fills, first day of week setting, busiest app per Metric. The inspector day header lost its subheading: the toolbar and the strip already show metric, zone and Show (user).
- **Shared preview (user):** one `PreviewCard` for every hover readout, compact and large, instead of a Calendar-only preview. Used by the chart bubble, Disk charts, event list, Disk Map, Trend sparkline, Energy nodes, Launch History, Calendar.
- **Time zone (user pick: app-wide, not per view):** the app sets `NSTimeZone.default` and formats dates through an app overload of `Date.formatted` and the interval style, as no native global setting covers `FormatStyle`. Cost: a new `formatted` call outside these overloads shows system time; a zone change rebuilds the window (view state resets).
- **Status levels (user pick: system rules):** the first build invented CPU 50/80 % and Memory 80/90 % levels for cell colour, against DESIGN.md (status only over a rule). Options: a system CPU rule; colour by recorded alerts only; no colour. User chose a system CPU rule (defaults 70 % and 90 % of all cores for 5 min; presets Relaxed 80/95/10, Balanced 70/90/5, Strict 60/80/3) that also colours the popover sparkline; Memory uses the recorded pressure level.
- **Review:** Opus review of R6 found no High defects; 6 Medium and 6 Low fixed (interval formats, weekday reload, minute tier fallback, system zone change, DST span units, stale usual read, a11y for the drag).

## D64: Space acts on files (user asks)

- **Goal (user):** choosing a folder should scan without a second click; a scan shows progress; the item menu should offer what a file browser offers (the user asked for delete, rename, open in terminal and "as many options as possible").
- **Call:** a focused Finder-like set (Open, Open With, Quick Look, Show in Finder, Get Info, Open in Terminal, Copy Path, Copy Name, Rename…, Move to Trash), not every Finder item. Move to Trash, not delete: the Trash restores, so no confirmation, as in Finder. This ends the earlier code-only rule "a monitor does not delete files"; the app now moves user files to the Trash on an explicit menu choice only.
- **Terminal:** a Settings > General pop-up of installed terminal apps (default Terminal).
- **Not built:** the treemap does not fill in during a scan (the scanner reports counts only).

## D65: Popovers and previews are Liquid Glass (user pick)

- **Goal (user):** the hover preview looked too grey in light mode on `.regularMaterial` (D60 P1 had chosen a material so coloured bands would not refract through the text).
- **Options (real captures):** regular, thick and ultra-thick material (all grey), Liquid Glass (near-white, cells blur faintly), window colour with a shadow (best contrast).
- **Call (user):** Liquid Glass, for every popover and hover preview regardless of size. Native popovers are glass already; `PreviewCard` now uses `.glassEffect(.regular)` in both sizes. Supersedes the material part of D60 P1.
- **Cost if wrong:** secondary text over a busy, coloured area is a little weaker; one line to change in `PreviewCard`.

## D66: Floating design on every screen (user picks, board rounds 7 and 8)

- **Goal (user):** everything floats, as in a reference chat app; one window background; side panels float over it; a title pill with an icon; two floating levels plus data; the main action prominent; thin scroll bars in the inspector.
- **Built:** inspector as a floating glass panel on an 8/12/16 pt grid; toolbar with no background and a glass title pill; level 2 glass capsules (range bar, footer, span capsule, Calendar bar, Space capsules); Live as one prominent button (Live left the range bar segments); overlay scrollers in the inspector only.
- **System limits:** the sidebar stays the system's (no inset API); the inspector starts below the toolbar row (a full-height panel puts toolbar items glass on glass); level 2 uses regular glass (clear glass made footer figures unreadable); Space capsules sit above the split view (AppKit panes take no safe area bar).
- **Costs:** Metric becomes a pop-up below 1050 pt (was 840) to leave room for a 240 pt title; inspector scroll bars ignore the system "Always" setting; supersedes DESIGN.md "panes use a standard material".
- **Reviews:** Opus review found 2 High (docs not updated; scroller token missed rebuilt views) and 5 more; all fixed.

## D67: Motion follows Apple's guidance (user pick)

- **Goal (user):** subtle animation, not overdone; "follow Apple's advice".
- **Sources (fetched 2026-10-24):** HIG Motion (purposeful, optional, brief, cancellable; avoid motion on frequent interactions; no macOS durations); HIG Accessibility (Reduce Motion: fades instead of moves and scales, tighter springs, no blur animation); SwiftUI SDK (`.smooth` bounce 0, `.snappy` bounce 0.15, default 0.5 s). The 0.15 to 0.3 s band is our choice.
- **Call:** one `Motion` helper; built: chart cross-fade on range change and Live, Calendar zoom from the click point, pin and alert fades, Energy bands only on user changes. Numbers no longer roll on Live ticks (changes P9, INS-9). Not built: screen-switch and hover motion (frequent). Later, on the user's go (2026-10-26): footer roll, table rows and scroll to row, all only after user changes, and Low Power Mode as a second off switch.
- **Cost:** for about 0.1 s after a range change the old chart shows against the new range.

## D68: Menu bar popover uses system components only (user rule)

- **User rules:** reuse system components, no custom ones; the dials must show their level by colour.
- **Call:** the custom hover row was removed; rows are plain system buttons. A probe found no system button style that gives a hover highlight in a window-style menu bar popover (`.accessoryBarAction` and `List` rows have a resting fill; the others show none). The dials stay system `Gauge`s, tinted green, yellow, red by level (Memory Pressure: the system's level, as macOS shows it; CPU: the system CPU rule).
- **Open:** the only fully system way to get native hover, keyboard and highlight is a real menu (`.menuBarExtraStyle(.menu)`), which cannot show dials or the sparkline. User decision.

## D69: The menu bar item opens a real system menu (user pick)

- **Goal (user):** hover feedback on menu rows with system components only (D68 open item).
- **Options:** keep the window popover with no hover; a SwiftUI `.menu` style (no gauges); an `NSStatusItem` with an `NSMenu` whose first item hosts the gauges as a view.
- **Call (user):** the `NSMenu`. Native highlight, keyboard, type-to-select and VoiceOver on every row; the gauges and sparkline stay in the first item; live top apps poll only while the menu is open.
- **Findings:** macOS 27 hides menu item images by default; action and alert icons are set to show (SET-3). Menu bar menus follow the system appearance, not the app's Light/Dark setting (native behaviour, kept).
- **Cost if wrong:** about 250 lines in `StatusMenu.swift`; the window popover is in git (aa33ed2).

## D71: No glass in glass on level 2 (user rule)

- **Goal (user):** the Calendar bar showed bezels and a segment track inside its glass capsules; "we should not use glass in glass".
- **Probe:** every SwiftUI picker style and every `NSSegmentedControl` style draws its own track inside a glass capsule (the SDK has no borderless segment style; `borderShape` only changes corners). Pop-ups and buttons lose the bezel cleanly with `.buttonStyle(.borderless)`. Glass buttons in a `GlassEffectContainer` read as separate blue controls, unlike the toolbar.
- **Call:** keep the level 2 capsules (D66); inside them, borderless pop-ups and buttons with system dividers, and a choice of a few values as accessory-bar toggles (`CapsuleChoice`), which show the chosen value as a pill on the glass, as the toolbar Metric control does. Fixed: Calendar bar, range bar, Space actions capsule.
- **Not changed:** the inspector's View picker sits in the level 1 panel, as segmented controls sit in system sidebars and inspectors; the Live button tint on its toolbar item is not checked.
- **Cost if wrong:** the period and range choices lose the segment track; `CapsuleChoice` is about 20 lines.

## D70: Hardware overview as one board (user pick, HW3)

- **Goal (user):** a more fun hardware depiction, "mimicking an actual motherboard is one direction".
- **Options (board round 10):** HW1 die floorplan (S), HW2 chip package (M), HW3 the whole Mac as one board (L, needs 620 pt). Designer and main session recommended HW2.
- **Call (user):** HW3, with HW2 as the layout under 620 pt.
- **Rules:** use is a level in the accent colour (the app uses the accent for one-series data; selection is an outline, not a fill); macOS gives one GPU total, so one level line over neutral cells; the places of storage, connectors and battery and the count of two memory packages are invented, and the caption says "Diagram, not to scale"; one connector per connected display, not per port; the memory type only from `dimm_type`.
- **Review (Opus):** 1 High (cluster cells were not clickable: offsets do not size the stack), 3 Medium (static work and the decoration redrawn on each 2 s reading; low space only by colour; a click under a search lost its open rows), 5 Low; all fixed in the main session.
- **Process (user):** after a regression the user saw on Hardware, page work is no longer split across subagents.
- **Cost if wrong:** about 650 lines in `ChipDiagram`, `HardwareBoard` and `PackageLayout`; the old chip card is in git (61d14f6).
- **Later (user, 2026-10-26):** the board takes the full width and the package scales with it (cells, pitches and memory grow, text does not, up to 2.4 times); the caption "Diagram, not to scale…" was redundant and is gone; the memory size moved under the title and the purgeable note to the Storage hint.

## D72: Live board parts and status colours on Hardware (user requests)

- **Goal (user):** memory as two dynamic sticks; storage chips shaded by use, no bar; external drives; displays and battery as their real shapes, filled to brightness and charge; yellow and red at thresholds, not only the accent.
- **Data:** memory used from `HostReader.memory()` (the Apps footer's figure); charge from `PowerReader`; brightness from the private DisplayServices call `DisplayServicesGetBrightness`, loaded at run time (nil if missing). macOS has no public brightness call. An external display answers with an error: its brightness lives in the monitor (DDC), which macOS does not read back, so it shows no fill and the hint says so. Reading it over DDC needs private I2C calls and can upset some monitors: not built.
- **Thresholds:** the rules the app already has (system CPU rule for cores and GPU, the system's memory pressure level, low space and the free space alert); the battery's 20 % and 10 % are our choice (common low-battery levels; not checked against macOS).
- **Fix on the way:** the low-space rule flagged any volume with less free space than the Mac's memory, so an empty 8 GB drive was "low"; that clause now applies to the startup volume only (also on the Disk screen).
- **Cost if wrong:** one private call (`DisplayBrightness`, 20 lines); the rest is drawing in `ChipDiagram` and `HardwareBoard`.

## D73: Compact toolbar and inspector cards (user pick, board round 11)

- **Goal (user):** learn from a three-column reference app: compact buttons at the top, and a denser inspector.
- **Options:** TB1 one compact capsule of icon buttons; TB2 the title inline in the bar (would undo the D66 title pill); IN1 inspector sections as collapsible cards with summaries.
- **Call (user):** TB1 and IN1; keep the title pill.
- **Built:** TB1 as a system `ControlGroup` with the navigation style in one toolbar item (the default style stacked the buttons); Live stays apart, since a tinted Live inside the capsule would be glass in glass. IN1 as `CardSection`, a form section whose first row is the disclosure row (an empty section put its header smaller and out of place).
- **Correction:** the board said the toolbar's x button was Clear Selection; it is Quit for the selected app. Clear Selection is the chart's span button and stays on the chart (it clears the time span, not the app). Quit stays in the capsule; the user decides whether it moves.
- **Cost if wrong:** about 40 lines in `Toolbar.swift` and `CardSection.swift`; sections go back to `Section` by name.

## D74: Hardware board as chip glyphs and part cells (user pick, board rounds 12 to 16)

- **Goal (user):** a more space-efficient board than the motherboard look (D70, D72), where the battery and memory were too big and the displays too small.
- **Options:** round 12 motherboard layouts MB1 to MB3 (rejected: battery too big); round 13 SE1 package and part cells, SE2 one shelf, SE3 inside and connected; for memory, rounds 14 and 15 (ME1 to ME3, MF1 to MF3; MF2 kept as a backup); round 16 glyphs for cores, GPU and memory (GL1 to GL3), then three memory columns for GL1 (GL1a chips as label, GL1b two chips and the amount, GL1c one large chip).
- **Call (user):** SE1 with GL1c: CPU cores as `cpu` symbols, GPU cores as lane blocks in the same columns, one large `memorychip` symbol under "Memory" and its percent; part cells two to a row; cells under the chip stretch to its width; the same layout at every width, with no text fallback.
- **Built:** `ChipDiagram` draws the glyphs on one column grid (the empty column between clusters lines the GPU row up with the CPU row); the columns shrink from 17 to 9 pt to fit a narrow column. The narrow card with text details is removed. `HardwareBoard` is the chip and a `Grid` of cells in a `ViewThatFits` (side by side, else stacked). The drawn package, its buses, mounting holes and `PackageLayout` are removed. The column width is measured on the inventory table, which always takes the width it is offered.
- **Cost if wrong:** about 400 lines in `ChipDiagram.swift` and `HardwareBoard.swift`; the earlier board is in git (87fd8f9).

## D75: Inventory icons on things only, in one column (user pick)

- **Goal (user):** the inventory list had icons on some rows and not others, and the names did not line up.
- **Options:** A, Apple's rules in the tree: icons on things only, one fixed-width icon column; B, the System Information layout: a tree of things with the selected thing's values in a pane beside it.
- **Call (user):** A. B is cleaner but replaces the Value column and needs room for a second pane, which is short beside the inspector.
- **Built:** the parser sets a symbol only on a thing (an item with a real `_name`, or one of a set named by key); a raw `_name` and an unnamed item are sets of values. The symbol still passes down, so devices in "Not Connected" keep theirs. A section's one unnamed item that stands in for it takes the section's symbol. macOS gives no kind for a phone, so an iPhone keeps the Bluetooth symbol.
- **Cost if wrong:** about 20 lines in `HardwareInventory.swift`, `HardwareModel.swift` and the Name column.

## D76: Round 17 picks and one design per drawn part (user picks and rule)

- **Goal (user):** apply the Hardware rounds' thinking (the thing itself as the icon, no box on glass, no repeated words, one style for one job) to the other screens, each by its own character; and keep each custom icon one design across screens.
- **Options:** up to three per element on board round 17 (AL, FT, CT, CC, DT, DL, SP, EF, ER, IN, ST, SB); round 18 revised DT1 and DL2.
- **Call (user):** AL1 alerts as a table; FT1 one borderless metric strip; CT3 Calendar header as glyph cells; CC1 app icons in day cells, empty days blank; DT1 Activity | Space in the toolbar centre, two equal 84 pt segments; DL2 physical disks as cells, at most 3 in a row and more rows, with the volumes table under them; SP1 the path capsule with symbols, without the two text buttons; EF1 the ends of the flow as the things; ER2 the Energy row as a strip; IN2 the numbers in the inspector's chart card; ST1 alert rules as rows with a summary and a switch; SB1 pinned apps with their icons. Rule: a drawn part has one design on every screen (the Disk cells use the Hardware flash chips).
- **Cost if wrong:** each element is its own commit on `design/round17`.

## D77: Show Whole Range by the span line; native Disk segments

- **Goal (user):** the chart's lone glass x looked like a bug, far from the span it clears; the Disk segments forced to 168 pt broke the native look.
- **Options:** SC1 a text button after "Ranked for", SC2 a span token in the range bar, SC3 a tag on the selected band; DP1 native segments at their own width, DP2 icon segments, DP3 equal halves (custom).
- **Call (user):** SC1 and DP1.
- **Cost if wrong:** one commit each on `design/round17`.

## D78: Context menus on list items; Forget by a private call

- **Goal (user):** Bluetooth items offer Forget, Reconnect and more on a right click; every list item offers its useful actions.
- **Options:** a proposed list of menus per list (approved by the user); for Forget, a private IOBluetooth call (`remove`) or only a link to Bluetooth settings, as no public call removes a pairing.
- **Call (user):** the proposed list; Forget by the private call. Copy IP Address was dropped: the inventory has no address for an interface.
- **Cost if wrong:** a macOS update can remove the private call; Forget then shows an alert that sends the user to Bluetooth settings.

## D79: Hardware by thing (SG3)

- **Goal (user):** the physical drive under Storage; two monitors are wrongly folded under the GPU.
- **Options:** SG1 drives in Storage with their volumes, SG2 Drives and Volumes groups, SG3 SG1 with the drive drawing and used share.
- **Call (user):** SG3, and the same hierarchy elsewhere: a display is beside its GPU.
- **Cost if wrong:** the regroup is one function (`HardwareInventory.byThing`) over the raw output.

## D81: Menu bar item as two stacked numbers (MB2)

- **Goal (user):** improve the menu bar status display: it was about 150 pt wide, mixed two kinds of reading in one row, and the alert glyph moved the numbers.
- **Options:** MB1 two bars with no numbers, MB2 CPU over memory as small labelled numbers, MB3 a CPU line with its number and a memory bar.
- **Call (user):** MB2, with the alert dot in a fixed slot. The Text only and Text + chart setting goes; the CPU line stays in the menu.
- **Cost if wrong:** one view (`MenuBarLabel.image`).

## D82: Warning levels in the menu bar as coloured bars (WL3)

- **Goal (user):** warning numbers must be legible on a light menu bar: system yellow on it is 1.3:1 and system red 3:1, under the 4.5:1 that small text needs.
- **Options:** WL1 deeper amber and red on a light menu bar, WL2 a yellow or red badge behind the number, WL3 numbers in the menu bar's colour with a coloured bar before them.
- **Call (user):** WL3, with bars wide enough to read (4 pt).
- **Cost if wrong:** one view (`MenuBarLabel.content`).

## D83: Calendar CPU lines from the Mac's CPU (CB1)

- **Goal (user):** a line's height and its colour must agree. The height was the sum of the recorded processes; the colour was the Mac's CPU against the system CPU rule. The processes sum 15 to 45 % lower (short-lived processes, time between samples), so a short line was yellow and a taller one blue (27 Oct: 10:55 PM yellow at 585 %, 5:45 PM blue at 672 %).
- **Options:** CB1 lines from the Mac's CPU with every app shown; CB2 colour from the line's own height (a CPU alert can then have no yellow line); CB3 the processes as a solid line with a pale cap up to the Mac's CPU.
- **Call (user):** CB1. With a search or group the lines stay the apps shown (CAL-5). The preview shows the difference as "Not in any process".
- **Cost if wrong:** `HistoryReader.calendarBuckets` and its three callers in `CalendarModel`.

## D84: One footer on every screen (FT2)

- **Goal (user):** the glass strip at the bottom of Apps and Energy becomes a shared part of every screen, with a better layout.
- **Options:** FT1 the same system strip on every screen; FT2 the same strip with each screen's own figures, led by one visual that is the screen's own; FT3 FT2 plus CPU and memory now at the trailing end.
- **Call (user):** FT2, with an iconic visual per screen: Apps' trend, Calendar's heat grid, Alerts' 7 days by severity, the startup disk's chips, the chip's cores, the battery. The figures take equal columns, so no strip leaves an empty half. Calendar's fact cells move into the footer; Energy's Average and Peak give way to the power source, the battery and the top app.
- **Cost if wrong:** `ScreenFooter` and one small view per screen.

## D85: No incremental history reload on the Apps screen

- **Goal (user):** use less CPU on the Apps screen, where each timed reload reads the full range again.
- **Options:** read only the rows that are new since the last read (`docs/plans/2026-10-28-incremental-apps-reload.md`); keep the full read.
- **Evidence:** step 0 on a copy of the live database. The charts, ranking and sparklines cost 3 to 5 times the read and stay full. Release estimate of the saving: 0.27% of one core at 1H, 0.1% at 24H, 0.04% at 7D, and only while the window shows.
- **Call (user):** keep the full read. The saving is too small for a second read path that must give the same slices as the first.
- **Cost if wrong:** none now; the plan has the design and the risks if it is needed later.

## D86: Round 18 picks and the design file consolidated (user picks)

- **Goal (user):** record the picks of this round in `DESIGN.md`, so a new screen follows them without the conversation.
- **Picks:** LG2, a two-series chart's key after its title (COL-14). MW1, the menu bar menu leads with native gauge rings (SET-5). SP1, the Space footer as a small treemap in a row under the panes (WIN-13). Every inspector pill in the card language; Processes stays a list with card-style title rows, to keep selection and arrow keys (INS-10). Energy A: with an app open, the label columns keep their room and the sources move closer; a label drops its share before its name shortens (SCR-2).
- **Call (user):** each pick as named. `DESIGN.md` gains the label order, the same-number rule for status colour (D83), the card language on every pill, the chart key, the menu bar menu and the mockup tool.
- **Cost if wrong:** text only; each pick is one view.

## D87: Design audit choices (user picks)

- **Goal (user):** make the app meet `DESIGN.md` where the audit found a choice, not a fix.
- **Options and calls (user):** 19A every card has a summary (19B allowed none). 20B event markers by severity shape (20A an outline, 20C a badge). 21A SMART failing is a status (21B text only). 22A groups use the app colours (22B keep pink and grey). 23 spacing on the 4, 8, 12, 16 grid with `Layout.gap` for gaps inside a row (or every small gap to 8 pt). 24A weekends a neutral tint (24B keep indigo). 25A no title row on the Apps summary and the Space root (25B, the range or span there, was dropped: the range bar and the span line already show them).
- **Cost if wrong:** one view each; `GroupColor` lost two cases, which read as blue.


## D88: Native formats and one standard per quantity (user pick, batch A)

- **Goal (user):** use native Swift where the app has custom code, and show one thing one way on every screen.
- **Call (user):** build the audit's batch A, the items with no design choice. Disk space and transfer amounts in decimal units, as Finder; memory alone in binary units; alert thresholds for disk writes and network in decimal GB and MB (S1). Percent, watts, °C and ms through the system formats, one formatter per quantity on every screen (N1, N2, S4, S5). "No data" for a value with no reading; "Not available" only where macOS never gives one (S2, S14). One uptime style (S15). One pin control, one symbol per meaning (S17, S18). Shared helpers for copy, Show in Finder, failure alerts, the inspector title and dates (S19).
- **Not done:** the batch B items, which change what a screen looks like, wait for mockups. `DisclosureGroup` cards, chart selection in Launch History, `inflect` in String sites and Swift Charts for the small bar charts were dropped: no lines saved, or a requirement fixes the look.
- **Cost if wrong:** text only, except the rule thresholds: a stored binary value reads rounded down until it is edited.

## D89: Batch B, the standards that change a screen (user picks)

- **Goal (user):** finish the audit: one way for each thing on every screen, native where possible.
- **Call (user), from mockups:** S7 the system "No Results" view on every list a search empties. S8 A, an Energy summary in cards, and no title row on any summary. S9 A, a grey hover outline beside the accent selection. S10 trailing numbers, header sort on every table and one set of column words. S16 the Disk cell as the Hardware cell. S3 Title Case titles and sentence-case labels. S6 one alert row. S12 plain text buttons in cards. S11 Escape and ⌘[ up one folder in Space. S13 options as checkmark toggles. N3 `.copyable` for ⌘C. N4 `.fileImporter` for file choices.
- **Cost if wrong:** each is one view or one menu; no data changes.

## D90: Event markers as wide as a cluster (user pick)

- **Goal (user):** markers with counts crowded the lane and ran into each other.
- **Options:** A, a cluster as wide as its marker (32 pt); B, the count as a badge on the symbol, 20 pt clusters; C, fixed 40 pt slots.
- **Call (user):** A. The gap was 12 pt, but a marker with its count is about 30 pt wide.
- **Cost if wrong:** one value; fewer, larger clusters at wide ranges.
