# Activity Monitor X: design

Date: 2026-10-21. Status: draft for review.

## 1. Goal

A local, native macOS app that records the resource use of every process (system processes included) all the time, keeps one year of history, and answers one question fast: **"what made my Mac slow, and when?"** An MCP server gives Claude Code the same answers.

Success criteria:

- After a slow period, one screen (Timeline) shows when it happened and which apps caused it.
- History goes back 90 days (decided 2026-10-21; was 1 year). Recording continues when the app is closed and when no user is logged in.
- Root-owned processes (`WindowServer`, `mds_stores`, `backupd`, ...) are recorded.
- The UI feels native to macOS 26+ and uses Liquid Glass the way the HIG says.
- Claude Code can query history, apps, groups and events through MCP.

## 2. Decisions and constraints

| Topic | Decision |
|---|---|
| Codebase | New, lean repo. Some files derive from an MIT-licensed project. They keep a one-line header that points to `Packaging/Credits.html`, which holds the full notices (that project and GRDB.swift). No `THIRD_PARTY.md`. |
| Platform | macOS 26+, Apple silicon. Swift 6, SwiftUI, Swift Charts. |
| Toolchain | SwiftPM with the Command Line Tools (macOS 27 SDK). Xcode is not required. A Liquid Glass type-check probe (`glassEffect`, `backgroundExtensionEffect`) passed on this Mac. |
| Dependencies | Policy: system frameworks and the standard library first; add a package when it removes a lot of work, never for small gains. Database: GRDB.swift, exact `7.11.1` (verified to build and test with the Command Line Tools). Queries are typed (GRDB records and query interface) by default; plain SQL through GRDB SQL interpolation only for window functions, `INSERT … SELECT … ON CONFLICT` rollups, batched deletes and PRAGMAs, each with a test. MCP server: official `modelcontextprotocol/swift-sdk` (0.12.1; pre-1.0, pin the exact version). `amx` parses its arguments by hand (re-check in M3). Rejected on 2026-10-21: DuckDB (no cross-process reader while writing), SwiftData/Core Data, `sqlite-data` (9 transitive packages), Lighter (inactive). |
| Name | Activity Monitor X. Bundle ID `com.henryqw.activitymonitorx`. |
| Signing | One self-signed code-signing certificate in the login keychain. Gives a stable identity for the XPC peer check. No Apple developer account. |

## 3. Scope

**In v1:** per-process CPU, memory, disk I/O, energy, network, GPU; system memory pressure, swap, thermal state, temperatures (SMC), disk throughput and latency; app grouping of helper processes; user groups with a rule tree (ALL/ANY/NOT); alerts and insights (sustained CPU, memory growth / leaks, pressure spike with its cause, sudden memory jumps, sustained thermal state); process glossary; process deep dive (parent/child, run history); Quit / Force Quit for any process; Disk tab (I/O, latency, volumes, APFS, SMART); Disk Map treemap; Hardware tab (inventory and overview); menu bar item; MCP server.

**Not in v1:** in-app AI (Ask), Data Explorer / Analytics / export (MCP `query` covers them), network scan and adapter details, Memory Inspector, open files, trace viewer and export, codesign sheet, ANE power, notch hiding, Sparkle updates, localisation, App Intents, onboarding flow (one "install helper" prompt only).

## 4. Architecture

```
            launchd (root)                         user session
 ┌──────────────────────────────┐      ┌───────────────────────────────┐
 │ amxd                         │ XPC  │ ActivityMonitorX.app          │
 │  sampler (5 s, 1 s if live)  │◄────►│  window + menu bar            │
 │  nettop stream               │      │  notifications                │
 │  rollups, retention, rules   │      │  Disk Map scan (FDA optional) │
 │  writer ─────────┐           │      └──────────────┬────────────────┘
 └──────────────────┼───────────┘                     │ read-only
                    ▼                                 ▼
     /Library/Application Support/ActivityMonitorX/history.sqlite (WAL)
                    ▲ read-only
            ┌───────┴────────┐
            │ amx (CLI, MCP) │   reads ~/Library/Application Support/ActivityMonitorX/groups.json
            └────────────────┘
```

| Unit | Job | Depends on |
|---|---|---|
| `AMXCore` (library) | Models, schema and migrations, queries, rollup math, app attribution, group rule matcher, insight rules. No UI. | GRDB, `CAMX` |
| `CAMX` (C shim) | `libproc`, `rusage_info_v6`, mach and sysctl helpers, SMC access. | system |
| `amxd` (root daemon) | Only writer of the database. Samples, writes, rolls up, trims, evaluates alert and insight rules into `events`. Serves XPC. | `AMXCore` |
| `ActivityMonitorX.app` | UI. Reads the database read-only. Uses XPC for live data and process actions. Stores `groups.json`. Posts notifications for new `events` rows. | `AMXCore` |
| `amx` (CLI) | Read-only queries; `amx mcp` is the MCP server over stdio. | `AMXCore` |

## 5. Data collection (`amxd`)

- **Tick:** every 5 s. While at least one XPC client subscribes to live data, every 1 s; rows are still written at 5 s (averaged).
- **Processes:** `proc_listpids` + `proc_pid_rusage` (v6) + `proc_pidinfo`. CPU from CPU-time deltas; memory = physical footprint; disk = bytes read/written deltas; energy = estimate (`cpu% × (translated ? 1.2 : 1) + wakeups/s × 0.1`), because `ri_billed_energy` is often 0; GPU % from per-process GPU time.
- **Network:** one long-running `/usr/bin/nettop -P -x -J bytes_in,bytes_out -L 0 -s 5`; each block starts with a `time,,bytes_in,bytes_out,` header; rows carry cumulative bytes per `name.pid`. Restart it 2 s after it exits.
- **System:** CPU, memory used, compressed, swap, memory pressure level and %, thermal state, SMC temperatures, disk throughput / IOPS / latency, free space of the startup volume (statfs, purgeable not included).
- **Identity:** a process is `(pid, start_time)`. A "program" is the executable path. Its **app** is the app of its responsible process (private `responsibility_get_pid_responsible_for_pid` in libquarantine, looked up with `dlsym`, resolved by `amxd` at first sight), except when that app is a terminal (an editable list; default Terminal, iTerm, Ghostty, rootshell); otherwise, or when the call is missing or fails, it is the outermost `.app` bundle on the path; processes outside any bundle are their own app. Rows recorded before this rule keep their path-based app. Code-signing team ID is read once per path and cached (needed by group rules).
- **Sparse writes:** write a process row only when it moved past small jitter thresholds since its last row (about 94% of processes are idle). Readers carry the last value forward.
- **Events:** pressure steps (with the top memory user at that moment), thermal state changes, alert rule hits, insight findings.

## 6. Storage

Tables (all timestamps Unix seconds, UTC):

- `processes(id, pid, start_time, name, path, app_path, app_name, bundle_id, team_id, uid, first_seen, last_seen)`
- `process_samples(ts, process_id, cpu, mem, disk_r, disk_w, energy, gpu, net_in, net_out)`: raw tier, key `(ts, process_id)`.
- `process_minute`, `process_hour`: same columns as avg + max per bucket, key `(bucket, process_id)`.
- `system_samples`, `system_minute`, `system_hour`: system metrics, avg + max (+ min where useful). `disk_free` has `_avg` and `_max` and no `_min` (the generic rollup; the chart uses `_avg`).
- `events(id, ts, kind, severity, process_id NULL, rule, message, value)`.

Retention: raw 24 h, minute 30 days, hour 90 days. A size cap (default 2 GB, set in Settings) drops the oldest rolled-up data, finest tier first; it never deletes raw rows that a tier still needs. Rollup and trim run every minute on the daemon's serial queue (after the write), which keeps the rollup's completeness margin safe.

**Tiers are sparse, like the raw tier (decided 2026-10-21).** A live process gets a minute or hour row only when that bucket differs from its last written row in the same tier (same thresholds as the raw gate), or when the last written row is older than a heartbeat (minute tier 60 min, hour tier 24 h). Readers carry a process's last row forward until the next row or the process's `last_seen`. Both tiers are computed from raw hold segments (the hour tier does not read the minute tier). System rows stay dense (one per bucket). All processes are kept, system processes included.

`last_seen` is open (+∞) while a process lives. When it ends, `amxd` writes the first tick of the last minute it was seen, with the first tick of the next minute. Readers take an open process to the first tick of the writer's last minute (from `system_samples`), which is the same value; a new writer first closes the processes that the previous one left open.

**Disk writes (decided 2026-10-22).** macOS flags a daemon that writes more than ~24 KB/s averaged over a day. SQLite writes whole 4 KB pages, once to the WAL at each commit and again to the database at each checkpoint, so the cost is the number of pages that each commit changes, not the rows. Therefore:

- Process tables are keyed time first (`WITHOUT ROWID`), so a tick or a rolled bucket appends at the right edge and retention deletes at the left edge. They have no index or foreign key that starts with `process_id`, because such an index puts each row of a tick on a different page.
- `last_seen` is not updated every minute for each live process (see above).
- `amxd` commits every 3 ticks (a row reaches the database up to 10 s after its tick; a crash loses up to the last 2 ticks) and checkpoints every 5 min (`synchronous=NORMAL`: a power loss can lose up to 5 min).
- Rollup keeps up to 8 MB of free pages for the next inserts and vacuums only the excess.

Measured with the replay harness in `DiskWriteTests` (1,500 live processes, 2,700 new per hour, 36 raw rows/s): 359 KB/s before, 13.6 KB/s after.

Size estimate (measured: ~1,160 live processes, ~63 active per minute): minute tier ≈ 0.4 GB for 30 days, hour tier ≈ 0.05 GB for 90 days, raw ≈ 0.25 GB; verified by the M1 measurement. A dense design was measured at ≈ 6.5 GB and rejected.

## 7. XPC channel

- Mach service `com.henryqw.activitymonitorx.daemon`, declared in the launchd plist.
- `amxd` calls `NSXPCConnection.setCodeSigningRequirement` with `(identifier "com.henryqw.activitymonitorx" or identifier "com.henryqw.activitymonitorx.amx") and certificate leaf = H"<sha1 of amxd's own leaf cert>"`. Other callers are refused. If `amxd` itself is unsigned, it refuses all XPC (fail closed).
- Operations: `subscribeLive` / `unsubscribeLive` (1 s snapshots), `signal(pid, SIGTERM|SIGKILL)`, `ping` (version, uptime, DB path).
- `signal` refuses pid 0, pid 1, `kernel_task`, and `amxd` itself. The app confirms every Quit / Force Quit with the user first.

## 8. UI

**HIG rules applied.** Liquid Glass only on the functional layer: floating sidebar, toolbar, inspector, popovers, sheets. The content layer (charts, tables) uses no glass and extends under the sidebar with `backgroundExtensionEffect`. Standard SwiftUI components first; custom glass only on the chart's hover bubble. Window title names the view, not the app. All commands in the menu bar with shortcuts; toolbar is customisable; sidebar icons follow the system accent colour; group colours carry meaning only.

**Window:** `NavigationSplitView` with a floating glass sidebar, content, and an inspector: a trailing pane inside the content area with a draggable divider and a material background. Opening it shrinks the content and never resizes the window (D21, D23).

Sidebar:

- **Monitor:** Timeline (default), Apps, Alerts (badge = unread count).
- **Groups:** one item per user group (colour dot, current footprint score badge), "+" opens the editor sheet.
- **System:** Disk, Disk Map, Hardware.
- **Pinned Apps:** apps the user pins.

Screens:

- **Timeline:** toolbar range control (Live, 1H, 24H, 7D, 30D, 90D) and metric control (CPU, Memory, Disk, Energy, Network, GPU). Chart = **stacked areas for the top 5 apps in the visible range + Other**; app colours are stable across views. Event lane on top (pressure ▲, thermal ◆, alert ●). Hover rule with a glass value bubble. Drag selects a span. Below: native `Table` of apps ranked for the span (or the whole range), expandable to processes, sortable, columns can hide. Live = last 5 min, 1 s updates over XPC.
- **Hide Quiet System Processes** (toolbar toggle and View menu item, on by default, saved): a process whose executable is under `/System/`, `/usr/` (not `/usr/local/`), `/bin/` or `/sbin/` is hidden from tables, the Apps screen and the top-5 choice while its average for the current metric and range is below: CPU 1 % of a core, memory 100 MB, disk and network 100 KB/s, energy 1, GPU 1 %. Hidden values add to Other, so totals stay true. A busy system process always shows. The inspector is not filtered.
- **Apps:** all apps seen in the range, totals and a sparkline each; pin action.
- **Group detail:** same layout as Timeline, scoped to the group. Metric control adds **Score** (CPU + memory as % of this Mac). Table = members with share of group.
- **Alerts:** one list of alerts and insights, newest first, severity symbol. Click opens Timeline at that time with the app selected.
- **Inspector:** selected app or process. Single-area history charts for the range, peak process and PID, glossary text, alerts in span, parent/child processes and run history, actions: Show Processes, Pin, Quit, Force Quit.
- **Disk:** throughput, IOPS, latency, utilisation, free space history (purgeable not included); volumes, APFS containers, SMART health. Live on Disk is read in the app, not over XPC.
- **Disk Map:** storage treemap of a chosen folder or volume. Works without Full Disk Access; shows which folders were refused and how to grant access.
- **Hardware:** inventory tree and drawn overview. Read on open and on Refresh only.
- **Group editor (sheet):** name, symbol, colour, rule tree (ALL/ANY/NOT over name, bundle ID, path, team ID), live list of matching processes.
- **Settings:** standard Settings scene: size cap, alert thresholds, terminal apps, launch at login, helper status and install command.

**Menu bar:** one status item (CPU + memory pressure readout). Popover shows top apps now and the last alerts; it refreshes at 1 Hz only while open. Opens the window.

**Notifications:** the app posts one notification per new alert `events` row; click opens Alerts.

## 9. Alerts and insights

Rules run in `amxd` and write `events`, so they work while the app is closed. Each rule has its own on/off switch and values, editable in Settings.

**Presets (decided 2026-10-22, user).** Settings has a preset picker: **Relaxed**, **Balanced** (default), **Strict**, and **Custom**. A preset computes concrete values for this Mac from its core count, memory size and boot volume size, and writes them to `settings.json`; the daemon reads only the concrete values. Editing any value switches the picker to Custom. A new install applies Balanced; an existing `settings.json` without a preset keeps its values as Custom.

| Rule (per app unless marked) | Relaxed | Balanced | Strict | Re-alert |
|---|---|---|---|---|
| Sustained CPU: the app's processes together, share of all cores, held | 50 %, 10 min | 25 %, 5 min | 12 %, 3 min | 60 min per app |
| Memory growth (per process): steady growth (r² at least 0.9) over 30 min, still growing in the last 5 min | 5 % of RAM | 2.5 % of RAM | 1.25 % of RAM | once per process |
| Memory jump (per process): footprint step within 50 s | 12 % of RAM | 6 % of RAM | 3 % of RAM | 30 min per process |
| Memory pressure (system) | critical | warning | warning | 60 min |
| Thermal state (system), held | critical, 5 min | serious, 5 min | serious, 2 min | on change |
| Disk writes in one hour | 50 GB | 20 GB | 10 GB | 60 min per app |
| Network in + out, held 5 min | 50 MB/s | 10 MB/s | 2 MB/s | 60 min per app |
| Energy impact, held 10 min | 500 | 300 | 150 | 60 min per app |
| GPU, held 5 min | 80 % | 50 % | 30 % | 60 min per app |
| Swap used (system) | 100 % of RAM | 50 % of RAM | 25 % of RAM | 60 min |
| Free space on the boot volume (system) | below 5 % | below 10 % | below 15 % | 24 h |

Units in `settings.json` stay as the daemon uses them (CPU in % of one core, so a preset writes share × core count; bytes and bytes per second for disk and network, % of RAM for swap, % of the boot volume for free space), and the allowed ranges of each value scale with the Mac so that every preset is valid on any core count and memory size. Values in the table are rounded for display; the calibration (13 h of history on a 15-core, 48 GB Mac: Balanced gives about 12 alerts on a heavy developer day, most from pressure and energy) against recorded history is in `docs/research/alert-presets-calibration.md`.

Rule details kept from v1:
- Rules for memory run per process, not per app, because helpers start and end all the time; the message names the app.
- Memory pressure records the likely cause: the process that grew most in the last 10 min, else the largest footprint.
- Thermal: a fan-speed drift rule is not possible; we record no fan speed.

## 10. MCP and CLI (`amx`)

`amx` reads the database read-only and `groups.json`. `amx mcp` serves these tools:

| Tool | Returns |
|---|---|
| `summarize(from, to)` | System overview for the span: peaks, pressure, top apps per metric, events. |
| `top_apps(from, to, metric, limit)` | Ranked apps with totals. |
| `app_history(app, from, to, metric)` | Time series at the tier that covers the span. |
| `events(from, to, kind?)` | Alerts, insights, pressure and thermal events. |
| `list_groups()` | Groups with rules and current score. |
| `group_summary(group, from, to)` | Group series and member shares. |
| `query(sql)` | Read-only SQL over documented views. |

## 11. Install

`make install` (asks for `sudo` once): builds release, signs with the self-signed certificate, copies the app to `/Applications`, `amxd` to `/usr/local/libexec/`, the plist to `/Library/LaunchDaemons/`, and runs `launchctl bootstrap system`. `make uninstall` reverses it; it keeps the database unless `PURGE=1`. A one-time `make cert` creates the certificate.

## 12. Testing

`make test` runs Swift Testing (the Command Line Tools have no XCTest; Swift Testing needs `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`, verified on this Mac). One test target for `AMXCore`, one for `amx`. Tests cover observable behaviour only:

- Rollup math and tier boundaries; retention and size-cap trimming.
- Sparse-write gate and carry-forward on read.
- App attribution from paths (nested helper `.app`, no bundle), and from the responsible process (terminal exception, missing symbol, exited parent).
- Group rule matching (ALL/ANY/NOT).
- Top-5 + Other totals equal the system total for a span.
- `signal` refuses protected PIDs.
- Each MCP tool on a small fixture database.

UI: build, run, and screenshot each screen in light and dark mode; compare with the approved mockups (local design notes).

## 13. Milestones

Each milestone gets its own implementation plan.

1. **Data:** package layout, `CAMX`, `amxd` sampler, schema, rollups, retention, install scripts, certificate, XPC `ping`/`signal`. Verify DB growth over 1 h.
2. **Window:** shell, Timeline (stacked chart, table, span selection), Apps, inspector, live via XPC.
3. **Groups and MCP:** responsible-app attribution (§5 Identity), team-ID backfill, group store, matcher, editor sheet, group detail, `amx` CLI and MCP tools.
4. **Alerts and menu bar:** rules, events, Alerts screen, notifications, menu bar item, Settings.
5. **System:** Disk, Disk Map, Hardware.

## 14. Risks

- Rewriting solved parts (PID reuse, app attribution, energy on Apple silicon, `nettop` parsing, retention). Mitigation: read the platform documentation and probe each part before writing ours.
- Database size: estimate only; milestone 1 measures it.
- `ri_billed_energy` is often 0 on some hardware. Energy column may be sparse.
- Self-signed certificate: if it is deleted or expires, the XPC check fails. `make cert` recreates it and `make install` re-signs.
- The database is world-readable (0644): any local user can read process names and usage. Acceptable on a single-user Mac.
