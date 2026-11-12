# Cleaning positions at import

A design, agreed with the author on 2026-11-12 after looking at the data together; **not built**.  It is TODO.md item 2, to be
built with the per-second arrays (item 3), so that the importer changes once and the database is rebuilt once.  The
measurements below were read-only queries on the author's database (1,112 activities, 6.2 M positions) and a pass of
`nch fit` over the 1,114 imported FIT files.

## What is wrong in the data

| Kind | How many | Example (file, local time of the fault) |
|---|---|---|
| **stale positions**: a position identical to the previous one (to the last semicircle) while the ride is moving; the device had no new fix and wrote the last one again, and the next step is about twice as long | 21,373 (0.4%) | `2021-06-21-chc.fit` from 07:08:33, the Farellones descent (about 50 km/h, which looked like 110–130 km/h) |
| **spikes**: one position far off, then back | rare | `2025-01-09-fun.fit` 07:28:09: 295 m out and 293 m back, as the rider stopped |
| **bursts**: several wrong positions in a row | rare | `2026-04-01-qmo.fit` 13:11:31: 316 m off, wrong for about 20 s |
| **a poor first fix**: the positions at the start are wrong until a jump that does not return | 6 of the 18 jumps over 100 m are in the first minute (all within 1–15 s of the start), against 6 in minutes 1 to 10 and 6 in all the rest | `2018-12-22-pco.fit` 15:14:39, 17 s after the start: 445 m |
| **sideways jumps of 10–35 m** near tall glass buildings | | `2025-01-09-fun.fit` 10:31:29–30 and 10:31:52 (UTC), round the Costanera Center |

Two of the five worst faults are round the Costanera Center (reflections; the shape is that of reflections, not of jamming,
which loses the fix, or of spoofing, which is wrong consistently).  Of 5.5 M one-second steps, 86 are 50 m or more longer than
the device's speed allows, and 16 are 100 m or more.

What looked like a "swirly mess" on the map round the Costanera Center was mostly the map's drawing: corner cutting
(`smooth_rounds`) turns each sharp zigzag of a few bad positions into a loop.  With `spread_m` and `smooth_rounds` at 0 the
track shows the spike and a few straight zigzags.

## What a threshold can and cannot do

The author asked for non-parametric filtering.  A test without any threshold exists for one kind (stale positions); for the
others a line has to be drawn somewhere.  What can be had:

* **Choose by consequence.**  What matters downstream are errors of tens of metres and more: cells are about 100 m, names
  look 700 m to 2 km away, climbs use gates 25 m each side.  A wobble of 10–20 m changes none of them (only the distance, by
  a few metres).  So the cleaner aims at errors of tens of metres and more, which are rare and far out in the tail, and leaves
  smaller wobble alone on purpose.
* **Show that the threshold does not matter**: the removals must be the same over a wide range of its values (say `k` from 5
  to 50).  That is what "non-parametric" can mean here.
* **The device's speed is not a clean witness.**  Most files have `enhanced_speed` (or `speed`), probably from the Doppler
  shift, which reflections disturb less than the position.  96% of moving steps are within 0.8–1.25 of the speed, but the
  ratio fades out gradually to about 3 (9,616 steps between 2 and 3 even after stale positions are merged; then 772, 313,
  185 in the bands 3–5, 5–10, over 10): no empty gap.  The device's distance is no witness at all: it is computed from the
  positions (it includes the spike).
* Distance is the right measure, not latitude and longitude apart (a bad fix is a displacement in two dimensions); the quick
  form, L2 on degrees with the longitude multiplied by cos(latitude) once per ride, is enough (`geo` has the projection).

## The design

At import, in Nim, on each stretch's series of positions, before the arrays are written (arrays are never changed, so
cleaning happens before the write; a change of the rules is a re-import).  Positions only: no other channel has shown a need
(the author, 2026-11-12), but the tests are written over a distance function, so another channel would be a small step.

1. **Stale positions** are dropped: identical to the previous position while the steps either side are long (the ride is
   moving).  No threshold.  An identical position while standing still is kept.
2. **A poor first fix**: a large jump in the first seconds of a recording means the positions before it are wrong; they are
   dropped.  The data put these jumps at 1–15 s, with none from there to a minute, so the window has room to spare.
   Check whether the same holds after a long gap in the positions (re-acquiring a fix after a tunnel, or after the device
   wakes).
3. **Spikes and bursts**: each position against a prediction from its neighbours (a robust one: a median, or interpolation
   in time between neighbours), scaled by the ride's own spread (median absolute deviation); a window wide enough for bursts
   of about 20 s.  Aimed at errors of tens of metres and more.  The threshold is shown not to matter (above).
4. **The device's speed**, when the file has it, as a second witness for positions: a step far longer than the speed allows
   supports dropping it.
5. **A jump that does not return**, after the first seconds: the stretch is split there (as a timer gap splits it), so that
   nothing measures distance, climbs or efforts across it; there is no telling which side is wrong.
6. **Drop, not mark** (decided).  A dropped position leaves that second without a position; the other channels of the second
   (heart rate ...) are untouched.  Everything that uses positions works by time, so the gap is bridged by the line between
   the neighbours.  Each removal is counted as a warning (a `WarningKind` per kind above) and shown in the import's report.
7. **What it makes unnecessary**: the workaround that a stretch spreading over more than 5 degrees is not searched for names
   (dev/HISTORY.md, 2026-11-08).  The limit on downloads (class B) stays as a safety net.
8. **Rebuild**: the arrays, `route_cell`, efforts and names all change; `nch db --delete -f`, then import again.

**Not to do**: let a history of bad places change how a ride is cleaned.  A ride's cleaned data would then depend on what was
imported before it, and a rebuild could give different arrays.

## Tests and evidence

* **The five example files** above, copied into the tests (they are the author's own rides), each with what must be dropped
  or split.
* **Injected faults**: spikes, bursts, stale positions, poor first fixes and jumps of known size put into clean real rides;
  measure what is found and what is wrongly removed (the fuzzer's idea).
* **The survey** (stale positions, jumps by size and by time since the start, the ratio to the speed) before and after,
  over the author's files, and the rides that change looked at on the map.
* **Thresholds**: the same removals over a wide range of each.

## Related, for later (TODO.md, features)

* **Times on the map**: the time of a position on hover, or a layer of the raw positions; it is how faults are inspected.
* **Smoothing on the map** only on cleaned data (corner cutting makes loops of zigzags).
* **Places of bad reception**: a count of faults per cell, filled at import from what cleaning dropped, shown as a layer or a
  list.  A report about the data, never an input to cleaning (above).

## Built (2026-11-13)

Steps 1 to 5 of the design are in: `importer/clean.nim` (pure), wired in `extract.nim` before the stretches are worked out, with one
advisory per kind and activity.  Changed from the design while testing against the author's 1,113 bike files: a jump that does not return
splits the stretch only at 100 m or more (27 of 35 first splits were under 100 m; a split would have broken a climb across it), and the
device's speed counts only for steps of 5 s or less.  Result: 18,125 stale positions in 477 activities, 387 spike or burst positions in
73, 6 poor first fixes, 3 splits.  Not built: the survey tool (the import log gives the counts); the arrays (TODO.md).

## Changed after looking at the splits (2026-11-13)

The poor-first-fix window was 15 s, from the survey (jumps within 1 to 15 s, none to a minute).  Two of the three splits left on the
author's bike files were poor first fixes too, at 75 s (`2026-07-22-fun.fit`: 64 slow positions, then a jump of 103 m) and 106 s
(`2016-11-20-sur.fit`: 16 positions, then 366 m).  The window is now 5 minutes (`firstFixS` = 300), and the part before the jump must
be shorter than the rest of the recording (so a ride that goes wrong late does not lose its beginning).  9 activities have a poor
first fix instead of 6; the only split left is `2018-03-11-atr.fit`, a jump of 304 m in 3 s, 46 minutes in, which stays a split.
