---
title: amx and MCP
description: Read the history from Terminal, from scripts and from AI clients.
---

`amx` is the command line tool of AMX. It reads the same history as the app and does not change it. `amx mcp` gives the history to an AI client through MCP (Model Context Protocol). To put `amx` on your path, see [Install](/install#the-amx-command).

## Commands

| Command | What it does |
| --- | --- |
| `amx ping` | Asks the helper for its status. It fails if the helper does not run. |
| `amx stats` | Prints the row count of each table and the size of the database. |
| `amx tools` | Lists the tools, each with one line. |
| `amx call <tool> [<json-object>]` | Runs one tool and prints its result as JSON. |
| `amx mcp` | Runs the MCP server on standard input and output. |

`stats`, `call` and `mcp` take `--db <path>` to read another history database. `call` and `mcp` take `--groups <path>` to read another groups file.

```sh
amx call top_apps '{"metric":"memory","from":"-7d","limit":5}'
amx call app_history '{"app":"Safari","from":"-90m"}'
```

## Tools

| Tool | Arguments | What it gives |
| --- | --- | --- |
| `top_apps` | `from`, `to`, `metric`, `limit` (1 to 50, default 10) | Apps ranked by their average over the window, with their peak. |
| `app_history` | `app` (required), `from`, `to`, `metric` | The series of one app, at most 120 points. |
| `events` | `from`, `to`, `kind` | The events of the window, oldest first, at most 500. |
| `summarize` | `from`, `to` | System CPU, memory, pressure and thermal state, the top 3 apps of each metric, and the event counts. |
| `list_groups` | None | Your process groups and their rules. |
| `group_summary` | `group` (required), `from`, `to`, `metric` | The series of one group and its apps. |
| `query` | `sql` (required) | The result of one read-only SQLite statement on the history database, at most 1,000 rows. |

- **Times:** `from` and `to` take ISO 8601, Unix seconds, or a time before now: `now`, `-30s`, `-90m`, `-24h`, `-7d`. The window is the last 24 hours by default. Results give times in ISO 8601, UTC.
- **Metrics:** `cpu`, `memory`, `disk`, `network`, `energy`, `gpu` and `score` (the score of a group). The default is `cpu`, and `score` for `group_summary`.
- **Kinds:** `pressure`, `thermal` or `alert`.

The description of each tool in the MCP server gives the units and, for `query`, the tables and views.

## Connect an AI client

Add the MCP server to your AI client with a configuration like this. The exact file and key names depend on the client.

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

The client can then see the names and paths of your processes. Connect only clients that you trust with that data. See [Privacy](/privacy).
