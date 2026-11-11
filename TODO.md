# TODO

Open work only.  Finished work is in git and in HISTORY.md (with the reasoning behind decisions).  The plan below is
from the second review (REVIEW.md, 2026-11-09); the first review (2026-11-08) is its appendix A, and "A §3" etc. refer
to that.  When something here is done, delete it (in the same commit).

Design steps are discussed with the author before they start; steps marked *(mechanical)* change nothing the author
sees and can be approved together.

## Now: the plan of the second review

1. **Fuzzing** (REVIEW.md §3; the author: before the packages).  Done so far: the FIT and importer fuzzers
   (HISTORY.md, 2026-11-10), and `decodeBits`.
   1. Failures saved under `tests/data/fuzz/<target>/` and replayed by a test: done for the importer
      (`tests/importer/test_fuzz.nim`), `bits`, `zip`, `xlsx` and the profile (they replay what is in the directory, which is empty
      except for xlsx; `request` has no saved case: its bugs were fixed with ordinary tests); the FIT target (`tests/data/fuzz/fit/`) needs the same.
   2. Level 2 is built and the one-hour runs were clean (HISTORY.md, 2026-11-10).  Fuzzing is done, apart from a rerun after
      big changes to a reader.
5. **Tab completion** (A step 10): built and working (HISTORY.md, 2026-11-10); what is left:
   * the **offline path** of `nch __complete` should be checked to write no cache files (it sets `offline` and `readOnly`, and
     no provider uses the network, but nothing yet tests that no child process or cache file is made);
   * **zsh** (`--install-completion zsh`: its own directory and mechanism), if wanted;
   * **`--edit NAME`** for the other plural commands if they gain one; a **`--model`** of `map`, if it gets one;
   * candidates that need quoting (`Cerro San Luis₄`) are quoted by the function (`%q`) and the words typed are unquoted; only
     spaces, quotes and backslashes were tried.
8. **Shrink** (A §4.7): done 2026-11-11 are the templating engine (292 to 182 lines), the dispatch of `decode` written once
   (`emitSlot`), plan building written once; the dead code and the housekeeping of §4.7 and §4.8 were already gone.  Left:
   * **one cache naming scheme**: step 8a;
   * (**`bundle/`** stays: the review proposed a plain `--profile PATH` instead, but the page templates in the system
     cache, editable and made again if deleted, are the same mechanism; see "Addresses, state and the cache".)
   * `fit/decode.nim`: `emitPlain` and `decodeField` take 12 parameters (a context object); mechanical but wide, with the
     SDK comparison (`nimble csvreport`) to check it;
   * the legacy steps in fragments (`names/002-country-cells.sql`'s `update country set geom = null`, the back-fill in
     `climbs/002-name-number.sql`): at the next squash.
8a. **`map` and `ff` made consistent** (agreed 2026-11-12; the design is "Addresses, state and the cache" below).  In commits that
   each keep the tests passing, `ff` first (it has no climbs question), then `map`.  Done (2026-11-12): the names `--selection`
   (was `--bits`) and `--state` (was `--check`) in both commands and in addresses, "for urls" in their help.  Decided: `--worker` stays; no collision check anywhere (a name is the hash alone).
   Done (2026-11-12): `cache` names are the command and a hash of the whole request (`fileStem` and `parseStem` are gone), and
   `ff` names its files so, prints the pinned query as the third line of `--worker`, and the server redirects to it.  Left:
   3. `map`: the same, and the collision loop, the request in the file, the in-place rebuild and `nch.inputs` go (`state` covers
      the selected activities' content, their routes and, until they are a layer, the climbs);
   4. the web handler: one `state` pin for every command, and the redirect from a live address;
   5. a test per command that changes each table it reads and checks that the fingerprint changes.
9. **Larger changes**: the `sectors` package; per-second data as arrays per activity, with cleaning at import; a
   simplified `route` (the author's idea: also stored as a **single connected line**, beside the multi-part one, for the
   uses where segmentation does not matter: 21% of routes have several parts and SpatiaLite's resampling returns NULL for
   them; HISTORY.md, 2026-11-11); the cache manifest.

## For the next whole-system review: a question about the design, not a task

Step 7 (push work into SQL) keeps ending the same way: prototype in SQL, measure, Nim wins (overlap excepted; HISTORY.md,
2026-11-11: route shape, features along the route, gate crossings, cells of names, `haversine` in `landmarkAt` and
`featuresAround`).  Each answer is right locally.  The author's worry is that they share a cause, and that the design is in a
**local minimum** that is hard to leave one step at a time:

* The per-second data is **rows of `coords`** (6.2 M, read as text) that Nim reads and turns into points, shapes and
  grids, and TODO step 9 plans to make it **arrays per activity**, which are opaque to SQL.  Both are early choices of data
  representation, and the code since has been written round them (a shape computed in Nim from the points, in flat
  metres; SpatiaLite's geometry functions used one call at a time, where they lose).
* The SQL prototypes so far used SpatiaLite's geometry functions on a query per call.  Untried: set-based SQL over the
  rows (window functions: running distance, the maximum distance from the start and where it is, for all rides in one
  query).  Whether it would win is unknown; it would be undone by step 9 as planned.
* The author does not know the code well enough to judge this, and the assistant that wrote it is too close to it.

**The reviewer's job** is to say whether a larger redesign of how the data are represented (rows or arrays, what is stored
at import, where shape and naming work happens) would give a simpler and faster whole, and if so to **make the case for it**
(the design, what it replaces, a measurement or a prototype of the hardest part, the cost).  If not, to say why the
current shape is right.  "Each step measured fine" is not an answer to this.

## Addresses, state and the cache: agreed 2026-11-12, not built (step 8a)

The author's requirements: a bookmark brings back **that plot**, not one remade; if the cache has been cleaned it is remade
only if it can be remade exactly, else it is an error; an address is also an invocation of a command, and one without a
pin shows the current database and is bookmarkable.  One convention for every command that has a page (`map`, `ff`, the
general plot command that will replace `ff`).

* **Every such command declares** (1) its **explicit parameters** (the options allowed in an address, as now) and (2) a
  **state fingerprint**: a hash of the data the plot is made from, including the content behind the explicit parameters (the
  activities `bits` names) and what the command reads that the address does not spell out.  Each package supplies the key of
  its own data (as `cache.inputsKey` does now, without the code part).  The parameter is called **`state`** (it replaces
  `check` and `--check`, and the `pin` of the web page: `--state HASH` means "only if the data are still those").
* **An address** is `/COMMAND?parameters` (live) or `/COMMAND?parameters&state=HASH` (pinned).  A live address is run on the
  current data; whatever it depended on that the address does not say (the selection, today's date, the zone) is resolved
  into explicit parameters, and the server redirects to the pinned form.  A pinned address whose files exist is served as
  they are (the fingerprint is not even worked out); if they are gone, the fingerprint is worked out now, and if it equals
  `state` the plot is remade and stored, else it is an error that says the data have changed and gives the live address.
  A new plot is a live address with other parameters.
* **File names are not addresses** (too long: a selection is explicit): the name is the command and a hash of the whole
  pinned address (proquint words, 48 bits as now), one-way, which is enough because the address is always at hand.  The
  name has no collision check (decided 2026-11-12: 48 bits is plenty for a cache).  A changed state is a new file; the old one stays (it is the old plot) until `nch cache` clears it.
  The in-place rebuild and `nch.inputs` of `map` go, and so do `ff`'s readable names.
* **The data file is pinned; the look is not.**  The wrapper page (user cache, same name, `.html`) is rewritten from the
  templates in the system cache (`templates/*.html`, `.css`, style JSON, and `libraries.txt`) each time it is served, so an
  edit of the templates changes the look of every bookmark.  The templates are edited by hand and made again if deleted.  If
  different looks are wanted, a `style=NAME` parameter picks a named style file in the system cache.
* **The program's version is not part of the state.**  A plot remade after a new build is the same data and parameters, not
  necessarily the same bytes.
* **Activities are identified by `bits`** (ids in order, compressed).  Additions do not touch a selection; the fingerprint
  covers the content of the selected activities, so deleting one of them, or a rebuild that gives those ids other rides,
  makes the pinned address an error; a rebuild that gives the same activities under the same ids does not.
* **Climbs become a layer** (the author, 2026-11-12): they are in the map's data file now, which was under development when
  the package work interrupted it.  As a layer of their own they have their own data and fingerprint, so a change to the
  climbs does not make an old map's bookmark an error.  Until then, and for any plot that does include them, the
  fingerprint includes them.
* **Limits that stay**: the basemap tiles come from the web when the page is viewed (the libraries are pinned by integrity
  hashes, the tiles are not).
* **Risks and their guards**: a fingerprint that misses an input gives a wrong "exact" remake with no sign of it, so each
  command gets a **test that changes each table it reads and checks that the fingerprint changes** (the class of bug, not the
  instance); 
* **Order of work**: the fingerprint function and its test for `map` (with the climbs question settled first); the name by
  hash and the server's flow (live, pinned, remade, error); `--state`; `ff` onto it; then the general plot command declares
  its series through an extension point, each package giving the key of its data.

## Open from before the review

To fit into the plan, or to do after it.  Details in HISTORY.md where noted.

* **Cleaning bad positions at import** (A §3 class B, the part not done): drop or flag impossible fixes (a jump faster
  than any rider, a point far from its neighbours) once, at import, so that every consumer sees clean data.  Needs its own
  design (threshold, drop or flag, effect on stretches, climbs and efforts); it changes stored data.  Until then a stretch
  that spreads over more than 5 degrees is not searched for names (HISTORY.md, 2026-11-08).
* **Naming is slow** (11 s for 1,112 activities: 4.6 s reading 6.2 M `coords` rows as text, 6.2 s in
  `nameActivity`, not broken down; nothing shown meanwhile).  The author wants to go through how naming works
  first.  The arrays (step 9) take most of the reading time away.
* **The shape of an activity stored at import** (idea): `names/shape.nim` computes the kind, the furthest distance, the
  turning point and the retrace shares in Nim from the points; storing them as columns of the activity when it is imported
  would make them queryable in SQL, without SQL ever needing the points (it is faster in Nim, HISTORY.md, 2026-11-11).
  Not designed: check first what the naming needs and whether the stored name is enough.
* **Large countries and `ensureCells`** (low priority; idea, measured 2026-11-11 on Chile only): a batch of new cells
  unzips and parses the whole country file (Chile: 75-140 ms per batch, 2 s for the whole country; `countriesOfCell` 0.15 ms
  per cell, `missingCells` under 1 ms, both fine).  A cell already loaded is never read again (`coverage`).  The cost is
  batches times file size, so it would only matter for a large file (US about 2 M rows, Russia) with rides scattered over
  many areas; not timed yet.  If it ever does: (a) split the file once per country into one indexed file, rows grouped by
  cell with a table of offsets (recommended; one pass, no partial states); or (b) the author's idea, a quadrant tree
  written to the cache, each read of a cell splitting its file into four around the cell and keeping the smaller files
  (a spatial index built lazily; more generated files to name, make safe against a crash, and delete with `nch cache`).
  Time the largest country first.
* **Tags** on activities (by hand: equipment, "bike A"), if wanted: a package that contributes a `--tag` criterion.
* **Features for later**: the elevation profile of a climb, the lead/lag comparison, the near-miss report,
  `exclude`, a way to retire many climbs (auto-retire of duplicates was tried and dropped: it retired long climbs
  into shorter near copies).  The "climbs vs sectors" question is answered by the `sectors` package.
* **Blue for the selection in `nch climbs`** (candidates: the `-v` attempts of selected rides; the latest/rank
  cells when the latest attempt is of a selected ride).  The author also asked whether "the selection chooses
  the climbs, never the attempts" is right; it is built that way.
* **The map**: labels, a legend, landmarks on the map, the page's palette from `packages/ui/palette.nim`, style rules by
  property (colour by sport or year), a plot command.
* **`ff`**: a form column (fitness minus fatigue); a switch between days and hours in the page.
* **A calendar of fitness** (HISTORY.md, Task 14): the `nch calendar` grid (step 3.7) with the background showing
  fitness, fatigue or form, each day in thirds.
* **A terrain model (SRTM)**: if added, smooth its heights (`climbs/profile.smoothed` is there for that).
* **Climb numbers**: a name renamed away from and then reused by a new climb can reuse the highest number.
* **Versions** (HISTORY.md, Task 11): when the version number changes; tie it to releases and the end of squashing.
* **Per-sport threshold heart rate and models**, if wanted.
* **The log**: level filtering (`--level warn`); the `saved` word is green for every use (low priority).
* **Light and dark terminal backgrounds** (`NCH_THEME`, else `COLORFGBG`; dim and yellow are poor on white).
