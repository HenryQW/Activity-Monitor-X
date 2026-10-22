# A root daemon is the only writer of the history database

`amxd` runs as a root LaunchDaemon and is the only process that writes `history.sqlite`; the app and `amx` open it read-only and use XPC for live data and process actions. Without root, macOS hides the statistics of processes the user does not own (for example `WindowServer`, `mds_stores`), and recording must continue while the app is closed or nobody is logged in. One writer also keeps SQLite locking and disk writes simple. Spec §4, §7.
