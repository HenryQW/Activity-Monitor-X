# Activity Monitor X

Activity Monitor X records what each process on your Mac does, and keeps that history. A root helper (`amxd`) samples CPU, memory, disk, energy, network and GPU for every process. A SwiftUI app shows the history on one Apps screen (a chart above an app table) and in the menu bar. The app also has alerts, process groups, a disk map and a hardware view. The `amx` command line tool gives the same history to scripts and to AI clients through an MCP server.

## Requirements

- macOS 26 or later
- Apple silicon
- Command Line Tools (Xcode is not necessary)

## Build and test

```
make build
make test
```

## Install

1. Run `make cert` one time. It adds a self-signed, trusted code-signing certificate to your login keychain. macOS asks for your login password.
2. Run `make install`. It builds and signs the binaries. It asks for your administrator password. Then it installs `amxd` as a LaunchDaemon, `amx` in `/usr/local/bin`, and the app in `/Applications`.

Open `Activity Monitor X` from `/Applications`. Recording starts when the helper starts. It continues when the app is closed and when nobody is logged in.

## What is installed where

| Item | Path |
|---|---|
| App | `/Applications/Activity Monitor X.app` |
| Helper | `/usr/local/libexec/amxd` |
| Helper LaunchDaemon | `/Library/LaunchDaemons/com.henryqw.activitymonitorx.daemon.plist` |
| CLI | `/usr/local/bin/amx` |
| History database and helper settings | `/Library/Application Support/ActivityMonitorX/` |
| Helper log | `/Library/Logs/ActivityMonitorX/amxd.log` |
| Process groups | `~/Library/Application Support/ActivityMonitorX/groups.json` |
| App settings | `defaults read com.henryqw.activitymonitorx` |

## Permissions

- **Administrator password.** `make install` needs it to put files in system folders and to load the LaunchDaemon.
- **Root helper.** `amxd` runs as root. Without root, macOS hides the statistics of processes that you do not own, such as `WindowServer`, `mds_stores` and `backupd`. The app and `amx` talk to the helper over XPC. The helper only accepts callers that are signed with your certificate.
- **Full Disk Access (optional).** The Disk Map shows the folders that macOS refuses to read, and has a button for the Full Disk Access settings. Give access to the app to see those folders.
- **Notifications.** The app asks for permission to show a notification for each new alert.

## Privacy

- The helper stores per-process samples: the process name, the path of the executable, the owner, and the numbers for CPU, memory, disk, energy, network and GPU.
- The helper keeps raw samples for 24 hours, minute averages for 30 days, and hour averages for 90 days.
- A size cap limits the database. The default is 2 GB. Change it in Settings > Recording. When the database passes the cap, the helper deletes the oldest history first.
- The helper, the app and `amx` do not send this data to any server.
- `amx mcp` gives this data to the AI client that you connect to it. That client can see the names and paths of your processes. Connect only clients that you trust with that data.

## MCP setup

`amx mcp` is an MCP server on standard input and output. Add it to your AI client with a configuration like this. The exact file and key names depend on the client.

```json
{
  "mcpServers": {
    "activity-monitor-x": {
      "command": "/usr/local/bin/amx",
      "args": ["mcp"]
    }
  }
}
```

Tools (`amx tools`):

| Tool | What it does |
|---|---|
| `top_apps` | Apps ranked by their average over a time window |
| `app_history` | One app's series over a time window |
| `events` | Alert events in a time window |
| `summarize` | A summary of a time window |
| `list_groups` | Your process groups |
| `group_summary` | One group's series and member apps |
| `query` | One read-only SQLite statement on the history database |

Use `amx call <tool> '<json-object>'` to run a tool from the shell.

## Troubleshooting

- `amx ping` asks the helper for its status. It fails if the helper does not run.
- `amx stats` prints the row count of each table and the database size.
- Settings > Helper in the app shows the helper status, uptime and database path. It shows the install command when the helper is out of date.
- Read the logs of the last 10 minutes:

  ```
  log show --predicate 'subsystem BEGINSWITH "com.henryqw.activitymonitorx"' --last 10m
  ```

- If the database is corrupt, the helper sets it aside as `history.sqlite.corrupt-<time>` in the same folder and starts a new database. The old history stays in the set-aside file.

## Uninstall

```
make uninstall
make uninstall PURGE=1
```

`make uninstall` removes the helper, the LaunchDaemon, `amx`, the app and the helper log folder. It keeps the history database, your groups, the app settings, the login item and the certificate. It prints the command that removes each kept item. `make uninstall PURGE=1` also removes the history database and the helper settings.

## Third-party code

Some source files and the process glossary come from an MIT-licensed open source project. The history database uses GRDB.swift. Both use the MIT License. The full notices are in `Packaging/Credits.html`.

## License

The owner has not chosen a license yet.
