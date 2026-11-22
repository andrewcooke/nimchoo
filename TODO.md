# TODO

Open work only, as one list in the order the author chose (2026-11-12).  Finished work is in git and in dev/HISTORY.md (with the
reasoning behind decisions); the reviews are in dev/REVIEW.md (the fourth on top, the others as appendices C, B and A).
When something here is done, delete it (in the same commit).  Design steps are discussed with the author before they start.

## Next: consistency (proposed 2026-11-20; each decision open, to be taken one at a time with the author)

The presentation grew by many small requests, each done where it was asked, so similar things differ between commands.
First cut what exists for one view (A), then make what is left share one helper each (B), each with a test that refuses the
next instance, and write the visual rules down in one place (C).  Every item is open: options, then a recommendation.

### A. Cut

5. **Options for one case** (decided 2026-11-20): `--latest` stays (it will be common); `together` is gone (the summary's
   one U/B column).  Left: the calendar keeps leaving out the months with nothing marked (needed for a calendar like
   Farellones'), but its "N months omitted" warning may go: to look at after B.  `ff`'s `--fitness-scale`,
   `--fatigue-scale` and `--hourly` are an item of their own (below, Features).

### B. Share

### C. The review (done 2026-11-20)

11. **The fourth review's plan** (dev/REVIEW.md, section 5; findings in `dev/review-4/`).  Done: step 1 (robustness) and
    step 2 (the other bugs) except A1, below.  Next after A1: step 3 (parse at the edge, with units in input: section 4,
    D3), then the output helpers, one fact, sentinels, dead code (section 3).

12. **A1: all output through `~"..."`: done** (2026-11-22; dev/REVIEW.md, section 4).  The drawer no longer reads backticks;
    help texts, parse problems, usages, messages and the importer's and namers' lines are `Line`s.  Left, small:
    * the frames' `summary` (map, calendar, climbs, activities: `MapFrame`, `CalendarFrame`) is text, also put in the page's
      JSON; its few backticks (`climbs/mapframes.nim`) are shown as they are (not coloured) until it is a `Line`;
    * `climbs/mapframes.nim:128`, `climbs/imported.nim`, `importer/failure` and similar helpers build strings with backticks
      for the log or for `ImportReport.text`: check on a terminal that nothing shows a backtick that should be a style;
    * the string versions of `failure`, `warn`, `usageError` and `sayDeleted` stay: they take text that is only known at run
      time (an exception's message), which is one colour.

14. **Step 3 of the review: input parsed at the edge, with units** (designed with the author 2026-11-22; dev/REVIEW.md
    sections 3.1 and 4, D3; findings C7, C13, D3, D8, D9, E11).  To be approved by the author before it starts; then a
    cheaper model can build it from this brief, one commit per point, `nimble fmt` and `nimble test` before each.
    * **Readers** (one each, in `geo` or a small package of their own, as the package rules say): a **distance** with its
      unit (`100m`, `1.5km`), a **duration** with its unit (`d h m s`, as `interval` writes them: `60s`, `42d`, `2h30m`),
      both finite and positive (no `nan`, `inf`, `-1`); a **position** is `geo/position` (`LAT,LON`), which must refuse
      `nan` too.  `m` is metres in a distance and minutes in a duration: the option's kind says which.
    * **Units are required.**  A bare number is a fourth outcome of `parseArgs` (beside valid, help and a problem): "valid
      with the unit added", with the corrected arguments.  **One shared helper in `core`** handles it for every command
      (as `usageError` handles a problem): on a terminal it asks, in three styles, `nch activities: --radius 3 has no
      unit; did you mean` (warn), the command line with the default unit added and each argument quoted again (default),
      `[Yn]` (em), Enter meaning yes, and on yes the command runs with the corrected arguments; not on a terminal it fails
      with exit 2 and prints the corrected line.  Default units: km for the rides' distances (`--distance`, `--radius`),
      m for a landmark's size; the durations' as their old units (seconds, days).
    * **The options**: `activities --distance` (its ranges: `40km-`, `10km-50km`, `42km~2km`, `latest~10%`) and `--active`
      (already `d h m s`); `--radius` of `activities` and `climbs`; `models --max-secs` becomes **`--max-gap`**,
      `--fitness-days` **`--fitness-decay`**, `--fatigue-days` **`--fatigue-decay`** (durations); `landmarks --radius`
      becomes **`--size`** (the landmark's own circle: not a search radius), read as a distance.  Heart rate stays bpm
      without a unit, `--zones` in %.
    * **One `--from`/`--near`/`--radius` piece** (C7): the option specs, help, defaults (10km for `--from`, 1km for
      `--near`), the reading of a place's name and the check that `--radius` goes with them, written once and used by
      `activities` and `climbs` (now each has its own copy).  `--all --radius` is refused as `--all --from latest` is (D8).
      `landmarks` uses the readers (its `--near` and `--at` take a place's name, as the conventions say) but not the piece.
    * **The box round a circle** (D9): `activities/criteria.box`/`boxes` (poles and the date line handled) move to `geo`,
      with one metres-a-degree, and `names/suggest.nim` and `names/lookup.nim` use them.
    * **`--port`** (E11): "not given" is not the default port (an `Option`), so `--file --port 62466` is refused as
      `--file --port 8000` is.
    * Then CLAUDE.md ("input never takes a unit for distance, and `m` always means minutes", the option conventions),
      and the help texts: every distance and duration in input carries its unit.

13. **E1 has no test** (dev/REVIEW.md): `tests/map/test_web.nim` starts a real server; add one that resets a connection
    before its reply (SO_LINGER 0) on a page that needs a worker, then checks the server still answers.  It needs the
    host (`localhost:PORT`) and the token as the page's address gives them.

## Tidy left from the reviews

1. **Susceptible climbs: left as they are, on purpose** (decided 2026-11-12; evidence in dev/HISTORY.md "Gates have no direction").  `overPaths`
   now pairs the crossings closest to the climb's length first, which is good enough: of 4,493 efforts 4,411 are right
   (`tools/gatetruth.nim truth`), 28 start late, 33 finish early, 21 are mostly off the line.  The rest are on the **17 of 183 climbs
   whose gate meets the climb's own line elsewhere** (`gatetruth susceptible`; 398 efforts; climbs 62, 147, 144, 145, 172, 118, 155 ...),
   and a direction rule is not safe on them (climb 145's finish sits on a fold).  Not worth more until a user cares enough about a
   climb or an attempt to push for something better, and has an opinion about how: the ideas are to report such climbs in
   `nch climbs`, retire them for a longer nearby climb with clean ends, move or narrow their gates, match the sequence of curves,
   or require progress along the climb (`gatetruth` already does that, for judging).  Look at examples with
   `nch map --frames routes efforts gates`.

## Larger changes (designs not started)

2. **Arrays: what is left.**  Built and measured (2026-11-13, dev/HISTORY.md "The arrays"): the cleaning, the arrays and every reader;
   `coords` and `heartrate` are gone.  Left: (b) a **landmark for Cerro San Cristóbal** (`nch landmarks --add "Cerro San Cristóbal" --at
   -33.4253,-70.6331`), so the 98 rides over it are named after it (dev/NAMING.md says why a landmark and not a rule); the rides
   already named are named again by `nch activities --all --rename`; (c) a **simpler
   `route`**, also stored as a single connected line beside the multi-part one, for the uses where segmentation does not matter (21% of
   routes have several parts and SpatiaLite's resampling returns NULL for them; dev/HISTORY.md, 2026-11-11); (d) the stretches the
   cleaning splits are extra `segment` rows: look at one on the map.
3. **The shape of an activity stored at import** (idea): `names/shape.nim` computes the kind, the furthest distance, the
  turning point and the retrace shares in Nim from the points; storing them as columns of the activity when it is imported
  would make them queryable in SQL, without SQL ever needing the points (it is faster in Nim, dev/HISTORY.md, 2026-11-11).
  Not designed: check first what the naming needs and whether the stored name is enough.
4. **The `sectors` package** (it should find long climbs such as Camino a Farellones, which climb detection splits: dev/HISTORY.md,
   2026-11-17); **the cache manifest**.
5. **The display architecture** (live views, subjects, frames; designed 2026-11-14): `dev/display-arch/plan.md` has the steps, each one done
    only with the author's approval; it replaces the old "Addresses, what is left" (wrapper page, climbs as a layer, the plot command) and
    "`map` criteria of its own".  Steps 0 to 3 and 3c (the fixes from the review, `dev/display-arch/review-after-step-3-findings.md`) are done; step 4 decided no caching and step 5 done (2026-11-16); 6a done (providers draw their frames, D7); 6 done (the climbs subject, 2026-11-18: D8 to D10); next: 7 (FF statistics, after a design note: D5).  Left over from steps 3 and 5: tab completion of the subject of `map` and `calendar` (a positional word:
    `core/complete` knows only options, so it needs the completion framework to learn them).
6. **Large countries and `ensureCells`** (low priority; idea, measured 2026-11-11 on Chile only): a batch of new cells
  unzips and parses the whole country file (Chile: 75-140 ms per batch, 2 s for the whole country; `countriesOfCell` 0.15 ms
  per cell, `missingCells` under 1 ms, both fine).  A cell already loaded is never read again (`coverage`).  The cost is
  batches times file size, so it would only matter for a large file (US about 2 M rows, Russia) with rides scattered over
  many areas; not timed yet.  If it ever does: (a) split the file once per country into one indexed file, rows grouped by
  cell with a table of offsets (recommended; one pass, no partial states); or (b) the author's idea, a quadrant tree
  written to the cache, each read of a cell splitting its file into four around the cell and keeping the smaller files
  (a spatial index built lazily; more generated files to name, make safe against a crash, and delete with `nch cache`).
  Time the largest country first.

## Features and ideas, unordered

* **Lines for the calendar** (the author, 2026-11-20): `nch calendar` drawn with lines, as the tables are (a rule under
  the weekday names, lines between the month, the days and the year?).  To look at with the author.
* **`nch climbs`: simpler, and more** (the author, 2026-11-20): simplified (the list mixes the selected and the
  not-selected: the best of all attempts beside the best of the selected ones, a rank of the selected among all) and
  extended (the best and the most recent attempts).  To design with the author.
* **`ff`'s options** (the author, 2026-11-20: needs a lot of work, as an item of its own): `--fitness-scale`,
  `--fatigue-scale` and `--hourly` are settings of one chart; look at what they are for before deciding what stays.
* **The last line of `nch climbs` with totals** (the author, 2026-11-20): "done: 3 of 184 climbs" could go on as the
  activities' does, with the length and the gain of the climbs listed.
* **A `speed` package: the device's speed stored as a channel** (the author, 2026-11-13; not part of the arrays/cleaning work).  Cleaning
  (`importer/clean.nim`) uses the speed when the file has it (`Coord.speed`, optional) and does not store it; that stays as it is.
  A separate package would store it, as `heartrate` does: an `ImportStep` contributed to the importer (`importStep`) that asks for
  the `enhanced_speed` / `speed` channel and writes it to a table of its own (on its own times: a second can have a speed and no
  position), with whatever queries and uses follow (colour along the route on the map, checking a cleaning decision).  Left out
  (decided 2026-11-17): no use for it yet, and a rebuild costs about 18 s of import, so it can be added when a use appears.
* **`nch packages --points`** is hard to understand (the author, 2026-11-17).  Since 2026-11-18 it is a ruled table (point,
  defined by, added to by, what it is; the types and priorities are in `nch packages NAME`); the author is going through the
  packages soon and may change it again.
* **The log**: level filtering (`--level warn`); the `saved` word is green for every use (low priority).
* **The map**: labels, a legend, landmarks on the map, style rules by
  property (colour by sport or year).
* **`ff`**: a form column (fitness minus fatigue); a switch between days and hours in the page (superseded if the plot command comes first).
* **The selection's style in `nch climbs`**: the `-v` attempts of selected rides have it (done); left, the latest/rank cells
  when the latest attempt is of a selected ride, once display step 6 has said what `nch climbs` lists.  The author also asked
  whether "the selection chooses the climbs, never the attempts" is right; it is built that way.
* **Tags** on activities (by hand: equipment, "bike A"), if wanted: a package that contributes a `--tag` criterion.
* **A calendar of fitness** (dev/HISTORY.md, Task 14): the `nch calendar` grid with the background showing fitness, fatigue or form, each day in thirds.
* **More climb features**: the elevation profile of a climb, the lead/lag comparison, the near-miss report, `exclude`, a way to retire many climbs
  (auto-retire of duplicates was tried and dropped: it retired long climbs into shorter near copies).
* **Per-sport threshold heart rate and models**, if wanted.
* **A terrain model (SRTM)**: if added, smooth its heights (`climbs/profile.smoothed` is there for that).  It would give
  altitude to the 139 rides without any (101 of them in 2019: measured 2026-11-20), which now have no climbs or attempts;
  how the device's altitude and the model's combine (compare, fix, replace) is to be decided then.
* **Versions** (dev/HISTORY.md, Task 11): when the version number changes; tie it to releases and the end of squashing.
* **Tab completion**: zsh (`--install-completion zsh`: its own directory and mechanism), if wanted; `--edit NAME` for the other plural
  commands, and a `--model` of `map`, if they gain them (completion follows the specs).
* **Inspecting positions on the map** (dev/CLEANING.md, "Related"): the time of a position on hover, or a layer of the raw
  positions; smoothing (`smooth_rounds`) only on cleaned data; places of bad reception (faults per cell, from cleaning) as a
  layer or a list, never an input to cleaning.
* **Tests that depend on timing fail now and then under load** (2026-11-18): `tests/util/child/test_child.nim` ("three children
  that take 0.5 s each take about 0.5 s together": 1.36 s against 1.3 s) and `tests/download/test_fetch.nim` (the spinner's
  thread drew one frame, not two).  Each passed when run again.  Give them more slack, or measure what they mean another way.
* **Triggers are not checked by the access model** (the review of 2026-11-14, finding 9; low priority): the authorizer skips every
  statement inside a trigger, so a trigger in a package's fragment could write any table.  Audit the triggers of `climbs` and `model`,
  or check a trigger's writes against the package that made it (the `tv_` counters belong to `db`).
* **A unique index on `effort`** (the review of 2026-11-14, an aside; low priority): working out an activity's climbs again (after its
  `climbs_done` row was deleted by hand) doubled its efforts.  No normal path is known to do that; worth an index if one can.
