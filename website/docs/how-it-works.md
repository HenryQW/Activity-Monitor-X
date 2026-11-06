---
title: How It Works
description: From a sample of each process to a chart in the app.
---

AMX does four things, in this order:

<ol class="flow">
  <li><b>The helper samples</b>Every process, every 5 seconds</li>
  <li><b>The database keeps</b>90 days of history on your Mac</li>
  <li><b>Rules check</b>An alert when a value passes a threshold</li>
  <li><b>The app shows</b>And <code>amx</code> answers</li>
</ol>

## 1. The helper samples every process

The helper, `amxd`, runs as root. Without root, macOS hides the numbers of processes that you do not own, such as `WindowServer`, `mds_stores` and `backupd`. The install puts it in a folder that only root can change, and launchd starts it (see [Install](/install#why-the-helper-is-not-inside-the-app)). It runs also when the app is closed and when nobody is logged in.

Every 5 seconds the helper reads, for each process:

- **CPU:** in % of one core.
- **Memory:** the physical footprint.
- **Disk:** the bytes read and written each second.
- **Energy:** an estimate of the energy impact, from the CPU use and the wakeups.
- **Network:** the bytes in and out each second.
- **GPU:** the share of GPU time.

It also reads the Mac as a whole: CPU, memory used, compressed memory, swap, memory pressure, thermal state, temperatures, disk throughput and latency, and the free space on the startup volume. While the app shows Live, the helper samples every second.

Each process belongs to one **app**: the app that macOS holds responsible for it. A helper process of Safari counts under Safari. A terminal app is not responsible for its children, so a command that you run in Terminal is its own app. Settings > Recording lists the terminal apps.

## 2. The database keeps the history

The helper is the only process that writes the history database. Most processes are idle most of the time, so the helper writes a row for a process only when its values change. The history goes to three tiers:

| Tier | Step | Kept for |
| --- | --- | --- |
| Raw | 5 seconds | 24 hours |
| Minute | 1 minute | 30 days |
| Hour | 1 hour | 90 days |

A size cap limits the database: 2 GB by default, from 1 to 50 GB in Settings > Recording. When the database passes the cap, the helper deletes the oldest history first.

## 3. Rules write alerts

The rules run in the helper, so they work while the app is closed. A rule writes an alert when a value passes its threshold:

- **For each app:** Sustained CPU, Memory Growth, Memory Jump, Disk Writes, Network, Energy Impact and GPU.
- **For the Mac:** System CPU, Memory Pressure, Thermal State, Swap Used and Free Disk Space. Each of these alerts names a likely cause, for example the process whose memory grew most.

Settings > Alerts has three presets: Relaxed, Balanced (the default) and Strict. A preset calculates the values for your Mac from its cores, its memory and the size of its startup volume. When you edit a value, the preset changes to Custom. To give one app its own values or to mute it, select the app and click Rules… in the inspector.

The app shows a notification for each new alert. By default, only a critical alert shows a banner. A warning goes to Notification Center without a banner.

## 4. The app shows the history

The app and `amx` read the database and do not change it. The app asks the helper over XPC (the macOS channel between processes) for the live data and to quit a process.

On the Apps screen, the chart shows the top apps of the busiest times in their own colours, and Other for the rest. Hover a point for a preview. Drag across the chart to select a span. Click an app for its details in the inspector: its chart, its processes and their open files.

If the helper stops, Live keeps the last data and says "Helper not reachable. Data as of" the time.

To read the same history from a script or an AI client, see [amx and MCP](/cli).
