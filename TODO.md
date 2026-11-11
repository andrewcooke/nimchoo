# TODO

Open work only.  Finished work is in git and in HISTORY.md (with the reasoning behind decisions).  The plan below is
from the second review (REVIEW.md, 2026-11-09); the first review (2026-11-08) is its appendix A, and "A §3" etc. refer
to that.  When something here is done, delete it (in the same commit).

Design steps are discussed with the author before they start; steps marked *(mechanical)* change nothing the author
sees and can be approved together.

## Now: the plan of the second review

Steps 1 to 8 are done (HISTORY.md); what was left of them is under "Open from before the review".

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

## Addresses, state and the cache: agreed 2026-11-12; `map` and `ff` are built (HISTORY.md), the rest is not

The author's requirements: a bookmark brings back **that plot**, not one remade; if the cache has been cleaned it is remade
only if it can be remade exactly, else it is an error; an address is also an invocation of a command, and one without a
`state` shows the current database and is bookmarkable.  One convention for every command that has a page (`map`, `ff`, the
general plot command that will replace `ff`).  What is built is in HISTORY.md (2026-11-12): explicit parameters, `--state`,
names by hash, and the server's flow (live, pinned, remade, error).  What is left of the design:

* **The data file is pinned; the look is not.**  The wrapper page (user cache, same name, `.html`) is rewritten from the
  templates in the system cache (`templates/*.html`, `.css`, style JSON, and `libraries.txt`) each time it is served, so an
  edit of the templates changes the look of every bookmark.  The templates are edited by hand and made again if deleted.  If
  different looks are wanted, a `style=NAME` parameter picks a named style file in the system cache.
* **Climbs become a layer** (the author, 2026-11-12): they are in the map's data file now, which was under development when
  the package work interrupted it.  As a layer of their own they have their own data and fingerprint, so a change to the
  climbs does not make an old map's bookmark an error.  Until then, and for any plot that does include them, the
  fingerprint includes them.
* **The general plot command** replaces `ff`: it declares its series through an extension point, each package giving the key
  of its data (its part of the state).
* **The rules that stay** (for every command with a page): the program's version is not part of the state; activities are
  identified by `selection` (ids in order, compressed), additions do not touch a selection, and the state covers the content of
  the selected activities, so deleting one of them, or a rebuild that gives those ids other rides, makes the pinned address an
  error; the basemap tiles come from the web when the page is viewed (the libraries are pinned by integrity hashes, the tiles
  are not); each command has a **test that changes each table it reads and checks that the state changes** (`map` has one; for
  `ff` the key is `model/impulses.inputKey`, tested there).

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
* **Low priority leftovers of the review's steps**:
  * `fit/decode.nim`: `emitPlain` and `decodeField` take 12 parameters.  A context object holds the number, base type, endian
    and `fromBits`, but not `data` (an `openArray` cannot be in an object), so they would still take 8 to 10; mechanical but
    wide, in the hottest functions, to be checked with `nimble csvreport` and a timing;
  * the legacy steps in fragments (`names/002-country-cells.sql`'s `update country set geom = null`, the back-fill in
    `climbs/002-name-number.sql`): at the next squash;
  * tab completion for **zsh** (`--install-completion zsh`: its own directory and mechanism), if wanted; `--edit NAME` for
    the other plural commands, and a `--model` of `map`, if they gain them (completion follows the specs).
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
