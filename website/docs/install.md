---
title: Install
description: Download Activity Monitor X or install it with Homebrew, open it, and approve its helper.
---

## Requirements

- macOS 26 or later, on a Mac with Apple silicon.

## Download

Download [AMX.dmg](https://github.com/HenryQW/amx/releases/latest/download/AMX.dmg), the latest release. Open it and drag Activity Monitor X to Applications. Each release, with its notes, is on the [releases page](https://github.com/HenryQW/amx/releases).

## Homebrew

```sh
brew trust --tap henryqw/tap && brew install --cask henryqw/tap/amx
```

Homebrew loads a cask from a tap that is not official only after you trust the tap. The first part of the command does that. `brew upgrade --cask amx` installs a new release.

## Build from source

See [Build from source](/build).

## Open AMX the first time

AMX has no Developer ID signature and Apple does not notarize it. So macOS blocks a downloaded copy at the first launch, with a message that it cannot check the app. Do one of these, after each download or upgrade:

- In Terminal, remove the quarantine flag that the download added:

```sh
xattr -dr com.apple.quarantine "/Applications/Activity Monitor X.app"
```

- Or open AMX one time, then go to System Settings > Privacy & Security, and click Open Anyway next to the message about Activity Monitor X.

A build from source has no quarantine flag, so it opens at once.

## Approve the helper

The helper, `amxd`, is inside the app. It runs as root and records the history (see [How it works](/how-it-works)). At the first launch, the app registers the helper with macOS, and macOS asks you to approve it one time:

1. Open System Settings > General > Login Items & Extensions.
2. Under Allow in the Background, turn on Activity Monitor X.

Until you approve the helper, the app shows no live data. After that, the helper starts with the Mac and records also while the app is closed.

## The amx command

`amx` reads the history from Terminal and runs the MCP server (see [amx and MCP](/cli)). Homebrew links it for you. If you installed from the disk image, link it yourself:

```sh
sudo mkdir -p /usr/local/bin
sudo ln -sf "/Applications/Activity Monitor X.app/Contents/MacOS/amx" /usr/local/bin/amx
```

## Permissions

- **Notifications:** the app asks one time to show a notification for each new alert.
- **Full Disk Access (optional):** the Space pane on the Disk screen lists the folders that macOS does not let it read, with a button that opens the Full Disk Access settings. Give access to the app to see into those folders.
