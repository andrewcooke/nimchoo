# TODO

Open work only, as one list in the order the author chose (2026-11-12).  Finished work is in git and in dev/HISTORY.md (with the
reasoning behind decisions); the reviews are in dev/REVIEW.md (the third, with the second as its appendix B and the first as A).
When something here is done, delete it (in the same commit).  Design steps are discussed with the author before they start.

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

## Queued by the author (2026-11-18), in order

* Titles in `em` ("package ui  (layer 0)", and other obvious titles).
* The fields at the bottom of `nch packages NAME` as a table, a bar in `hide` between label and value ("added to by" then a row
  of its own, not an indent).
* `web`'s documentation: drop "**One server for every page**" (the text after says it; `**` shows as is).
* `libraries.txt` (web: the libraries the pages load from a CDN) gets a name of its own, as the themes did (`.theme`); not
  `.manifest`, which the cache's record of what was unpacked is already called.
* `nch packages web` says where the cache lives (its documentation, pointing to `nch packages --config` for the directory in
  force).

## Features and ideas, unordered

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
* **A terrain model (SRTM)**: if added, smooth its heights (`climbs/profile.smoothed` is there for that).
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
