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
   `nch map --layers routes efforts gates`.

## Larger changes (designs not started)

2. **Arrays: what is left.**  Built and measured (2026-11-13, dev/HISTORY.md "The arrays"): the cleaning, the arrays and every reader;
   `coords` and `heartrate` are gone.  Left: (a) the **rebuild** of the author's database (`nch db --delete -f`, import) and a comparison
   of efforts and names with the old ones, and the rides that changed looked at on the map; (b) at the next squash fold
   `importer/002`/`003` and `heartrate/002`/`003` into the `001`s (the `coords` and `heartrate` tables then never exist); (c) a **simpler
   `route`**, also stored as a single connected line beside the multi-part one, for the uses where segmentation does not matter (21% of
   routes have several parts and SpatiaLite's resampling returns NULL for them; dev/HISTORY.md, 2026-11-11); (d) the stretches the
   cleaning splits are extra `segment` rows: look at one on the map.
3. **The shape of an activity stored at import** (idea): `names/shape.nim` computes the kind, the furthest distance, the
  turning point and the retrace shares in Nim from the points; storing them as columns of the activity when it is imported
  would make them queryable in SQL, without SQL ever needing the points (it is faster in Nim, dev/HISTORY.md, 2026-11-11).
  Not designed: check first what the naming needs and whether the stored name is enough.
4. **The `sectors` package**; **the cache manifest**.
5. **Addresses, what is left** (the requirements and the rules that stay are in dev/HISTORY.md): the wrapper page (user cache, same name,
    `.html`) is rewritten from the templates in the system cache each time it is served, so an edit of the templates changes every
    bookmark's look (if different looks are wanted, a `style=NAME` parameter picks a named style file); **climbs become a layer** of the
    map of their own, with their own fingerprint, so a change to the climbs does not make an old map's bookmark an error; **the general
    plot command** replaces `ff`, declaring its series through an extension point, each package giving the key of its data.
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

* **A `speed` package: the device's speed stored as a channel** (the author, 2026-11-13; not part of the arrays/cleaning work).  Cleaning
  (`importer/clean.nim`) uses the speed when the file has it (`Coord.speed`, optional) and does not store it; that stays as it is.
  A separate package would store it, as `heartrate` does: an `ImportStep` contributed to the importer (`importStep`) that asks for
  the `enhanced_speed` / `speed` channel and writes it to a table of its own (on its own times: a second can have a speed and no
  position), with whatever queries and uses follow (colour along the route on the map, checking a cleaning decision).  Storing it
  has to be decided before the rebuild at the end of the arrays work, because what is not stored then is not there until the
  next re-import.
* **`map` criteria of its own** (the author, 2026-11-13): extra arguments to `nch map` (the criteria `nch activities` takes, say
  `--from`, `--names`, `--climbs`), so that a simple plot does not need `nch activities ... --select` first.  Design questions:
  the same criteria options from one description (`activities/criteria.nim` offers them), what the address carries (the
  criteria, or the resolved `selection` it already has), and what the state fingerprints.
* **Investigate: "Cerro San Cristóbal" and "Parque Metropolitano" are not used to label rides** (the author, 2026-11-13).  Rides on
  that hill are named after other places.  Find out why: which GeoNames features are there and with what feature codes
  (`names/codes.nim` says which codes count and how they rank), whether they are within the search radii for the start, the
  turning point and the places along the route (`names/activity.nim`), and whether a landmark of the author's own (`nch landmarks`)
  would be the answer.  Look at a few of the rides with `nch activities --names` and `nch map` before changing any rule.
* **Climb numbers**: a name renamed away from and then reused by a new climb can reuse the highest number.
* **The log**: level filtering (`--level warn`); the `saved` word is green for every use (low priority).
* **Light and dark terminal backgrounds** (`NCH_THEME`, else `COLORFGBG`; dim and yellow are poor on white).
* **The map**: labels, a legend, landmarks on the map, the page's palette from `packages/ui/palette.nim`, style rules by
  property (colour by sport or year).
* **`ff`**: a form column (fitness minus fatigue); a switch between days and hours in the page (superseded if the plot command comes first).
* **Blue for the selection in `nch climbs`** (candidates: the `-v` attempts of selected rides; the latest/rank
  cells when the latest attempt is of a selected ride).  The author also asked whether "the selection chooses
  the climbs, never the attempts" is right; it is built that way.
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
