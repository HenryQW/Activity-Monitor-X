---
title: Privacy
description: What Activity Monitor X records, where it keeps it, and who can read it.
---

AMX sends nothing anywhere. It has no account, no analytics and no network calls of its own. The helper, the app and `amx` keep the history on your Mac.

## What the helper records

For each process: its name, the path of its program, its owner, and its numbers for CPU, memory, disk, energy, network and GPU. For the Mac: the system numbers and the events (memory pressure, thermal state and alerts). The helper does not read the contents of files, windows or network traffic.

## How long it keeps it

- Raw samples: 24 hours.
- Minute averages: 30 days.
- Hour averages: 90 days.

A size cap limits the database: 2 GB by default. Change it in Settings > Recording. When the database passes the cap, the helper deletes the oldest history first.

## Where it is

| Item | Path |
| --- | --- |
| History database | `/Library/Application Support/ActivityMonitorX/history.sqlite` |
| Helper settings | `/Library/Application Support/ActivityMonitorX/settings.json` |
| Your process groups | `~/Library/Application Support/ActivityMonitorX/groups.json` |
| App settings | `defaults read com.henryqw.activitymonitorx` |

## Who can read it

- **The helper** runs as root and is the only process that writes the database.
- **The app and `amx`** read the database without root, so every user account on this Mac can read it. They talk to the helper over XPC, and the helper accepts only callers that are signed with the same certificate as itself.
- **An AI client** that you connect to `amx mcp` can read the history, with the names and paths of your processes. Connect only clients that you trust with that data.
- **The open files** of a process show in the inspector only for your own processes.

## Logs

The helper and the app write to the macOS unified log. To read the last 10 minutes:

```sh
log show --predicate 'subsystem BEGINSWITH "com.henryqw.activitymonitorx"' --last 10m
```
