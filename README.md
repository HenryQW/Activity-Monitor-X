# Activity Monitor X

Activity Monitor X records what each process on your Mac does, and keeps that history. A root helper (`amxd`) samples CPU, memory, disk, energy, network and GPU for every process. A SwiftUI app shows the history on one Apps screen (a chart above an app table) and in the menu bar. The app also has alerts, process groups, a disk map and a hardware view. The `amx` command line tool gives the same history to scripts and to AI clients through an MCP server.

Docs: [amx.henry.wang](https://amx.henry.wang). License: [MIT](LICENSE).

## Requirements

- macOS 26 or later
- Apple silicon
- To build from source: Command Line Tools (`xcode-select --install`). Xcode is not necessary.

## Install

Download [AMX.dmg](https://github.com/HenryQW/amx/releases/latest/download/AMX.dmg) and drag the app to `/Applications`, or install it with Homebrew:

```sh
brew trust --tap henryqw/tap && brew install --cask henryqw/tap/amx
```

Activity Monitor X has no Developer ID signature, so macOS blocks a downloaded copy at first. Run `xattr -dr com.apple.quarantine "/Applications/Activity Monitor X.app"`, or click Open Anyway in System Settings > Privacy & Security.

To build from source:

1. Run `make cert` one time. It adds a self-signed, trusted code-signing certificate to your login keychain. macOS asks for your login password.
2. Run `make install`. It builds and signs the app, with the helper and `amx` inside, and copies it to `/Applications`. It links `amx` into `/usr/local/bin` if that folder is writable; if not, it prints the command. It does not ask for an administrator password.

Open `Activity Monitor X` from `/Applications`. At its first launch, the app registers the helper, and macOS asks you to allow it. Turn on Activity Monitor X in System Settings > General > Login Items & Extensions, under Allow in the Background. The app shows this step and an **Open Login Items Settings** button until you do it. Recording starts when the helper starts. It continues when the app is closed and when nobody is logged in.

## What is installed where

| Item | Path |
|---|---|
| App | `/Applications/Activity Monitor X.app` |
| Helper | `/Applications/Activity Monitor X.app/Contents/MacOS/amxd` |
| Helper launchd property list | `/Applications/Activity Monitor X.app/Contents/Library/LaunchDaemons/com.henryqw.activitymonitorx.daemon.plist` |
| CLI | `/Applications/Activity Monitor X.app/Contents/MacOS/amx`, linked from `/usr/local/bin/amx` (`make install`) or the Homebrew `bin` folder (the cask) |
| History database and helper settings | `/Library/Application Support/ActivityMonitorX/` |
| Process groups | `~/Library/Application Support/ActivityMonitorX/groups.json` |
| App settings | `defaults read com.henryqw.activitymonitorx` |

The helper writes its messages to the unified log (see Troubleshooting).

## Permissions

- **Allow in the Background.** The app registers the helper with launchd through `SMAppService`. macOS runs it only after you turn on Activity Monitor X in System Settings > General > Login Items & Extensions.
- **Root helper.** `amxd` runs as root. Without root, macOS hides the statistics of processes that you do not own, such as `WindowServer`, `mds_stores` and `backupd`. The app and `amx` talk to the helper over XPC. The helper only accepts callers that are signed with the same certificate as the helper.
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
      "command": "/Applications/Activity Monitor X.app/Contents/MacOS/amx",
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
- Settings > Helper in the app shows the helper status, uptime and database path. When the helper waits for approval or is out of date, it has a button that opens Login Items. Turn Activity Monitor X off and on again there to restart the helper.
- Read the logs of the last 10 minutes:

  ```
  log show --predicate 'subsystem BEGINSWITH "com.henryqw.activitymonitorx"' --last 10m
  ```

- If the database is corrupt, the helper sets it aside as `history.sqlite.corrupt-<time>` in the same folder and starts a new database. The old history stays in the set-aside file.

## Uninstall

1. Quit Activity Monitor X.
2. In System Settings > General > Login Items & Extensions, turn off Activity Monitor X under Allow in the Background. The helper stops.
3. Move the app to the Trash, or run `brew uninstall --cask amx`. If you linked `amx`, run `rm /usr/local/bin/amx`.

`make uninstall` prints these steps. It keeps the history database, your groups, the app settings, the login item and the certificate, and prints the command that removes each kept item. After step 2, `make uninstall PURGE=1` also removes the history database and the helper settings (it asks for an administrator password). `brew uninstall --zap --cask amx` removes your groups and the app settings.

## Development

| Task | Command |
|---|---|
| Build | `make build` |
| Run the tests | `make test` |
| Build, sign and install the app | `make install` |
| Make the disk image | `make dmg` |
| Make the release signing identity (one time) | `Scripts/make-release-cert.sh` |
| Make a release | Push a tag `v<VERSION>`; `.github/workflows/release.yml` builds and publishes it |
| Run the docs site | `cd website && pnpm install && pnpm dev` |

The version is in `VERSION`. A release is signed in CI with the release identity from the secrets `RELEASE_CERT_P12` and `RELEASE_CERT_PASSWORD`; the secret `TAP_TOKEN` lets it update the cask in HenryQW/homebrew-tap. The docs site (`website/`) is built by Cloudflare from this repository; the app build (`Sources/`) does not include it.

## Third-party code

Some source files and the process glossary come from an MIT-licensed open source project. The history database uses GRDB.swift. Both use the MIT License. The full notices are in `Packaging/Credits.html`.

## License

[MIT](LICENSE) © 2026 Henry Wang.
