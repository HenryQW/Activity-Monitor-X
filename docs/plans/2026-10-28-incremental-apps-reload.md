# Incremental history reload on the Apps screen

Status: not built (user call, 2026-10-28, D85). Step 0 showed a saving too small for the risk. Kept as a record.

## Goal

A timed reload on the Apps screen reads only the rows that are new since the last read, not the full range.

## Now

- `HistoryModel.run()` checks every 15 s. `isStale` reloads when `HistorySource.reloadInterval` has passed: raw 15 s, minute 60 s, hour 300 s. A custom window never reloads.
- `reload()` reads the full window with `HistoryReader.tracks`, then calculates `QuietFilter.hidden`, `AppSeries.recordedStart`, `ranking`, `stacked`, `sparklines`, `reader.system` and `reader.events` over the full window. The baseline (range before, 7-day profile) is kept for 1 h.
- Rows in one read today: 1H 117k (raw), 24H 261k (minute), 7D 348k (hour). 46k processes in 24H.
- `sqlite3` scan times: 24H 21 ms, a 2-minute delta 0.4 ms, process metadata 9 ms, 7D 14 ms. The disabled `dayQueryUnderBudget` note: 880k rows, `tracks` 0.28 s in release (GRDB row fetch 0.19 s), `stacked` 0.007 s. Most of the cost is the row fetch and the Swift fold, not the SQL scan.

## Expected saving (estimate, not measured)

- 24H: about 0.1 s each 60 s, about 0.15% of one core. 1H: about 0.05 s each 15 s, about 0.3%. 7D: below 0.05%.
- Against 1.8% for the app, that is 0.1 to 0.3 points. The derived values stay full, so the saving is only the read.
- Recommendation: if step 0 confirms a saving below 0.2 points at 24H and 1H, do not build.

## Step 0: measure before building

1. Snapshot: `sqlite3 -readonly "$DB" ".backup <scratch>/snap.sqlite"`.
2. A temporary probe test (not committed), run with `make test`: on the snapshot, time a full reload (`tracks` + derived values + `system` + `events`) and the derived values alone, at 1H, 24H and 7D, median of 5. `make test` is a debug build; the note above shows debug at about 2.4 times release for the fold, so compare both parts in the same build.
3. Go when the read part, at its reload interval, is more than 0.2% of one core at 24H or 1H.

## Step 0 result (2026-10-28, debug build, snapshot of the live database, median of 5)

| Range | Tracks | Full read | Extend read | Derived values | system + events |
|---|---|---|---|---|---|
| 1H | 3k | 113 ms | 16 ms | 312 ms | 5 ms |
| 24H | 46k | 234 ms | 87 ms | 1305 ms | 5 ms |
| 7D | 254k | 674 ms | 411 ms | 3174 ms | 4 ms |

- The extend read is the metadata read over the window, the rows from `cut` and the slice trim. At 7D the metadata of 254k processes is most of it.
- The derived values cost 3 to 5 times the read, and they stay full. Debug overstates them most (`stacked` is about 30 times slower in debug, the read about 2.4 times).
- Release estimate, not measured: the saving is about 40 ms each 15 s at 1H (0.27% of one core), 60 ms each 60 s at 24H (0.1%), 110 ms each 300 s at 7D (0.04%).
- A 60 s sample of the installed app with its window covered showed 5 database samples: `windowShown` stops the timed reload, so the saving applies only while the window shows.
- Verdict: below the 0.2% go line at 24H and 7D, at the line at 1H. Do not build without a release measurement.

## Change (only after go)

1. `HistoryReader.extend(_ tracks: [ProcessTrack], source:from:to:loadedTo:metric:) -> [ProcessTrack]` next to `tracks`:
   - `cut` = `loadedTo - hold - exitSlack`, rounded down to the tier step (5 s, 60 s, 3600 s). Slices from rows before `cut` are final: their next row, `t + hold` and `lastSeen + 60` cannot change.
   - Read the process metadata again (9 ms): it adds new processes and updates `lastSeen`, `path` and app fields. Keep slices by `processID`.
   - Drop slices that start at or after `cut`, clip slices at the new `from`, fold rows in `[cut, to)` with the same `close` rule, drop tracks with no slices.
2. `HistoryModel.reload()`: keep the unscoped tracks and their end. Use `extend` only for a timed reload with the same key as the baseline (range, metric, scope, quiet filter), no custom window, and `loadedTo` inside the new window and not after now (a clock jump back reads in full). Else read in full.
3. Calculate `hidden` again after each extend: it is a set of track indices, so a set from an older array is wrong.
4. `system` and `events` stay full reads unless step 0 shows them as a real cost.

## Risks

- A wrong slice at `cut` gives a chart that is wrong with no error. Guard: the equality test below at every tier.
- The open minute or hour row changes until its bucket closes. The re-read from `cut` covers it, because `hold` is at least one bucket.
- A live process can look unseen for up to `exitSlack` (commit batches). That is why `cut` also subtracts `exitSlack`.
- 7D: `hold` is 25 h, so each reload still reads about 15% of the rows. The saving there is small.
- About 50 new lines and a second read path to keep equal to the first.

## Tests

- One test in `HistoryReaderTests`: for raw, minute and hour, `extend(tracks(w1), to: w2)` gives the same ids and slices as `tracks(w2)`. Fixture: a process that quits, one that starts after `cut`, one unseen for less than `exitSlack`, rows at `t + hold` exactly.

## Measure the saving (after build)

1. Step 0 probe again on the same snapshot: full against extend.
2. End to end: CPU time delta (`ps -o time= -p <pid>`) over 10 min, 3 runs before and 3 after, app on Apps at 24H and then 1H, window shown, nothing else changed. Report mean and spread, and RSS. Baseline: 1.82% CPU, 207 MB (Apps, All Apps, one 5-minute run).
3. Record the result as a `D<n>` entry in the decision log.
