# TODO

Open work only, as one list in the order the author chose (2026-11-12).  Finished work is in git and in HISTORY.md (with the
reasoning behind decisions); the reviews are in REVIEW.md (the third, with the second as its appendix B and the first as A).
When something here is done, delete it (in the same commit).  Design steps are discussed with the author before they start.

## Tidy left from the reviews

1. **BUG: `--offline` gives no names at all, and the empty result is kept** (found 2026-11-12, benchmarking naming: `offline: true` named all
  1,112 activities "with nothing" although every place was already in the database).  Two faults.  (1) `names/lookup.prepare` returns
  `rdNothing` whenever `n.offline`, so offline does not use the places already loaded (`coverage`, `feature`) or the country files in
  the cache: it should mean "no network", and a cell that is loaded should be used.  (2) What offline finds, nothing, is **stored as the
  result**: an activity gets `start_place = ''` and `name = ''` (`importer/001-schema.sql`: `""` means "looked at, nothing to say (or made with
  --offline)"), so it is never named again (`pending` is `name is null`); a climb the same (`climbs/001-schema.sql`: `sector.name = ''`).  That
  is a failure stored as a result, which the rules forbid.  To do: offline uses what is loaded; for a place whose cells are not loaded and
  cannot be fetched, the name stays null (pending) and the command says how many were left (so that the next online run names them); the
  same for climbs; the schema comments say it.  Tests: an offline import with the data loaded names the activity; an offline import without
  them leaves it null, and a later online run names it; the same for a climb.  Repair for databases already damaged: `update activity set
  name = null where name = '' and start_place = ''` is a start (it also frees the 4 genuinely nameless ones to be tried again, harmlessly).
2. **The import does not follow symbolic links** (found 2026-11-12, the importer given a directory of links to `.fit` files said "no
  .fit files found").  `importer/batch.nim` walks a directory with `walkDirRec(arg)`, whose defaults yield only regular files and
  descend only into real directories, so a link to a file or to a directory is skipped without a word.  Follow both
  (`yieldFilter = {pcFile, pcLinkToFile}`, `followFilter = {pcDir, pcLinkToDir}`), with a guard against a loop (a link to a parent
  directory: remember the real path of each directory entered) and the rule that a file reached twice is read once (it is imported
  once anyway: same content, same hash).  A test with a link to a file, a link to a directory and a loop; a broken link is a
  failure that says so, not a silent skip.
3. **`fit/decode.nim`: `emitPlain` and `decodeField` take 12 parameters.**  A context object holds the number, base type, endian
   and `fromBits`, but not `data` (an `openArray` cannot be in an object), so they would still take 8 to 10; mechanical but
   wide, in the hottest functions, to be checked with `nimble csvreport` and a timing.
4. **Cleaning bad positions at import** (A §3 class B, the part not done): drop or flag impossible fixes (a jump faster
  than any rider, a point far from its neighbours) once, at import, so that every consumer sees clean data.  Needs its own
  design (threshold, drop or flag, effect on stretches, climbs and efforts); it changes stored data.  Until then a stretch
  that spreads over more than 5 degrees is not searched for names (HISTORY.md, 2026-11-08).
5. **At the next squash** (then a whole-system review in a fresh session): the legacy steps in fragments (`names/002-country-cells.sql`'s
   `update country set geom = null`, the back-fill in `climbs/002-name-number.sql`).
6. **Susceptible climbs: left as they are, on purpose** (decided 2026-11-12; evidence in HISTORY.md "Gates have no direction").  `overPaths`
   now pairs the crossings closest to the climb's length first, which is good enough: of 4,493 efforts 4,411 are right
   (`tools/gatetruth.nim truth`), 28 start late, 33 finish early, 21 are mostly off the line.  The rest are on the **17 of 183 climbs
   whose gate meets the climb's own line elsewhere** (`gatetruth susceptible`; 398 efforts; climbs 62, 147, 144, 145, 172, 118, 155 ...),
   and a direction rule is not safe on them (climb 145's finish sits on a fold).  Not worth more until a user cares enough about a
   climb or an attempt to push for something better, and has an opinion about how: the ideas are to report such climbs in
   `nch climbs`, retire them for a longer nearby climb with clean ends, move or narrow their gates, match the sequence of curves,
   or require progress along the climb (`gatetruth` already does that, for judging).  Look at examples with
   `nch map --layers routes efforts gates`.

## Larger changes (designs not started)

7. **Per-second data as arrays per activity**, with cleaning at import (item 4).  A **simpler `route`**, also stored as a single
   connected line beside the multi-part one, for the uses where segmentation does not matter (21% of routes have several parts and
   SpatiaLite's resampling returns NULL for them; HISTORY.md, 2026-11-11).
8. **The shape of an activity stored at import** (idea): `names/shape.nim` computes the kind, the furthest distance, the
  turning point and the retrace shares in Nim from the points; storing them as columns of the activity when it is imported
  would make them queryable in SQL, without SQL ever needing the points (it is faster in Nim, HISTORY.md, 2026-11-11).
  Not designed: check first what the naming needs and whether the stored name is enough.
9. **The `sectors` package**; **the cache manifest**.
10. **Addresses, what is left** (the requirements and the rules that stay are in HISTORY.md): the wrapper page (user cache, same name,
    `.html`) is rewritten from the templates in the system cache each time it is served, so an edit of the templates changes every
    bookmark's look (if different looks are wanted, a `style=NAME` parameter picks a named style file); **climbs become a layer** of the
    map of their own, with their own fingerprint, so a change to the climbs does not make an old map's bookmark an error; **the general
    plot command** replaces `ff`, declaring its series through an extension point, each package giving the key of its data.
11. **Large countries and `ensureCells`** (low priority; idea, measured 2026-11-11 on Chile only): a batch of new cells
  unzips and parses the whole country file (Chile: 75-140 ms per batch, 2 s for the whole country; `countriesOfCell` 0.15 ms
  per cell, `missingCells` under 1 ms, both fine).  A cell already loaded is never read again (`coverage`).  The cost is
  batches times file size, so it would only matter for a large file (US about 2 M rows, Russia) with rides scattered over
  many areas; not timed yet.  If it ever does: (a) split the file once per country into one indexed file, rows grouped by
  cell with a table of offsets (recommended; one pass, no partial states); or (b) the author's idea, a quadrant tree
  written to the cache, each read of a cell splitting its file into four around the cell and keeping the smaller files
  (a spatial index built lazily; more generated files to name, make safe against a crash, and delete with `nch cache`).
  Time the largest country first.

## Features and ideas, unordered

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
* **A calendar of fitness** (HISTORY.md, Task 14): the `nch calendar` grid with the background showing fitness, fatigue or form, each day in thirds.
* **More climb features**: the elevation profile of a climb, the lead/lag comparison, the near-miss report, `exclude`, a way to retire many climbs
  (auto-retire of duplicates was tried and dropped: it retired long climbs into shorter near copies).
* **Per-sport threshold heart rate and models**, if wanted.
* **A terrain model (SRTM)**: if added, smooth its heights (`climbs/profile.smoothed` is there for that).
* **Versions** (HISTORY.md, Task 11): when the version number changes; tie it to releases and the end of squashing.
* **Tab completion**: zsh (`--install-completion zsh`: its own directory and mechanism), if wanted; `--edit NAME` for the other plural
  commands, and a `--model` of `map`, if they gain them (completion follows the specs).
