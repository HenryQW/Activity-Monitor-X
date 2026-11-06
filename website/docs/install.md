---
title: Install
description: Install Activity Monitor X and its helper with one line in Terminal, or with Homebrew, and remove it again.
---

## Requirements

- macOS 26 or later, on a Mac with Apple silicon.
- An administrator account. The helper records as root, so the install asks for your password one time.

## Install with one line

Open Terminal (press ⌘ Space, type Terminal, press Return), paste this line and press Return:

```sh
curl -fsSL https://amx.henry.wang/install.sh | sh
```

The script downloads the latest release and checks that the release certificate signed it. It copies Activity Monitor X to `/Applications`. Then it asks for your administrator password and installs the helper:

- It copies `amxd` to `/Library/PrivilegedHelperTools` and `amx` to `/usr/local/bin`, both owned by root.
- It checks the signature of each copy again, after the copy.
- It writes the launchd property list to `/Library/LaunchDaemons` and starts the helper.

At the end, it opens the app. macOS does not block a copy that `curl` downloads, so you need no other step. Read the script first at [install.sh](/install.sh) if you like.

To update, run the same line again. It replaces the app and the helper and keeps the history.

## Why the helper is not inside the app

The helper runs as root (see [How it works](/how-it-works)). Any program that runs as you can change the files in `/Applications/Activity Monitor X.app`. If root ran the helper from the app, such a program could replace it and run its own code as root, with no password. So the install puts the helper in `/Library/PrivilegedHelperTools`, a folder that only root can change, and root never runs code from the app.

## Other ways to install

Use the one line above if you can. These ways are for special cases.

### Homebrew

```sh
brew trust --tap henryqw/tap && brew install --cask henryqw/tap/amx
```

Homebrew loads a cask from a tap that is not official only after you trust the tap. The first part of the command does that. The cask removes the quarantine flag, so the app opens at once. It installs the helper in the same way as the script, and asks for your administrator password for that step. `brew upgrade --cask amx` installs a new release.

### Disk image

Each release has `AMX.dmg` on the [releases page](https://github.com/HenryQW/Activity-Monitor-X/releases). If you only drag the app to Applications, the helper is not installed and the app shows no data. The disk image has "Read me first.txt", which gives the one line above.

### Build from source

See [Build from source](/build).

## The amx command

`amx` reads the history from Terminal and runs the MCP server (see [amx and MCP](/cli)). The script installs it in `/usr/local/bin`, and Homebrew links it into its own `bin` folder.

## Permissions

- **Notifications:** the app asks one time to show a notification for each new alert.
- **Full Disk Access (optional):** the Space pane on the Disk screen lists the folders that macOS does not let it read, with a button that opens the Full Disk Access settings. Give access to the app to see into those folders.

## Uninstall

If you installed with Homebrew, run `brew uninstall --cask amx`. It stops the helper and removes the app, the helper and its property list.

If you installed with the script, run these lines in Terminal:

```sh
sudo launchctl bootout system/com.henryqw.activitymonitorx.daemon
sudo rm -f /Library/LaunchDaemons/com.henryqw.activitymonitorx.daemon.plist /Library/PrivilegedHelperTools/amxd /usr/local/bin/amx
rm -rf "/Applications/Activity Monitor X.app"
```

The history database stays in `/Library/Application Support/ActivityMonitorX`. To remove it too, run `sudo rm -rf "/Library/Application Support/ActivityMonitorX"`.
