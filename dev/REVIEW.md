# nimchoo: spatial data as cells (third review, 2026-11-11)

Scope.  The question TODO.md left for the next whole-system review: step 7 (push work into SQL) kept ending "prototype in
SQL, measure, Nim wins" (HISTORY.md, 2026-11-11), and the author suspected a local minimum, a better design that needs a
larger change than one step at a time.  Read: HISTORY.md (the step-7 measurements), the schemas of `importer`, `names` and
`climbs`, `names/shape.nim`, `names/activity.nim`, `climbs/match.nim`, `climbs/work.nim`, `geo/geo.nim`.  Prototyped in plain
SQL on a copy of the author's database (1,112 activities, 6.2 M `coords` rows, 15,298 GeoNames features, 183 climbs, 4,493
efforts).  **Nothing in the program has changed**; this is a proposal, with the measurements that support it.

## 1. Summary

There is a better design, and it is not "more SpatiaLite".  **Where a ride went is stored as the cells of a grid it passed
through**, so that spatial questions about places (what is near a route, which rides pass a climb) are joins on integers,
which SQLite does well.  Work that follows the order of a ride in time (its shape, climb detection, the exact gate
crossings) stays in Nim, done once at import on the per-activity arrays, and its results are stored.  This also removes the
conflict in TODO step 9: arrays are opaque to SQL, and with cells SQL no longer needs the samples.

## 2. Why step 7 kept losing

Every fast Nim path is a grid: `shapeOf` puts the route into 50 m cells, the via search uses `RouteGrid` with 2.5 km cells,
the GeoNames features are loaded by 1-degree cells.  Every SQL prototype used SpatiaLite's geometry functions pair by pair
(point-to-line distances, buffers, a query per call; `ST_Intersects` does not use prepared geometries).  So each
measurement compared Nim *with* a grid to SQL *without* one: the grid won, not Nim.  No step tried putting the grid itself
in the database, because each step was the conversion of one function, not a change of what is stored.  That is the local
minimum.

## 3. The prototypes (measured 2026-11-11)

The grid: latitude and longitude, cells 1/1024 of a degree (about 109 m × 91 m at Santiago); a cell is one integer,
`(iy << 32) | ix` with `ix = floor((lon + 180) × 1024)`, `iy = floor((lat + 90) × 1024)`.  Each level halves the cell, so a
coarser cell is a shift of a finer one.  Plain SQLite (SpatiaLite only to read the existing points).

| | Today | With cells |
|---|---|---|
| where the rides went | `coords` 263 MB + `route` 100 MB | `route_cell` (each visit to a cell, with entry and exit times; 685,000 rows) **35 MB** with its index |
| distinct places | | **23,445 cells for all 1,112 rides** (the same roads, again and again) |
| features near each place | worked out for each ride, every time | **once per cell**: 0.59 s for every cell visited, 7 MB; 47,000 rows when only the kinds the rules can choose are kept |
| the via feature of the 560 loop and mixed rides | Nim (part of 6.2 s of naming, after 4.6 s reading `coords`); SpatiaLite 16 to 60 s | **0.68 s in SQL**; the same place as the stored name for 547; the other 13 are near ties (both candidates tens of metres from the route, inside the cell's error of about 70 m) |
| rides over each climb | the box of the climb, then each ride's points read | **0.61 s for all 183 climbs and all rides; every one of the 4,493 stored efforts is inside a candidate pass** (8,723 candidates: the others are rides the other way or with a detour, which the exact test refuses as now), each with the few seconds of the ride to test |
| the shape (loop, out and back ...) | Nim 0.27 s | SQL (cells of 1/2048°, about 50 m) 6.7 s, the same kind for 988 of 1,056 (93.6%; the rest at the out-and-back / mixed line): **SQL loses** |

The last row matters as much as the others: it shows where the line is.  A rule about the order of points (the turning
point, the first third of the way back) is a series algorithm; a rule about places (near, through, shared) is a relation.

Not measured, and no reason to change: the lookups round one point (the start place within 20 km, the destination round the
turning point), which are one indexed query each; Sonnet measured them (HISTORY.md: `featuresAround`, `landmarkAt`).

The queries are in §8, so that the numbers can be made again.

## 4. The design

**Two kinds of work, each where it suits:**

1. **Series** (the order in time matters): the shape and its turning point, climb detection from the elevation, the exact
   gate crossings, the impulses from heart rate.  **Nim, once, at import**, on the per-activity arrays (TODO step 9).  The
   results are stored as facts (the shape's kind, the turning point and its time, the furthest distance, the retraced
   shares), so that nothing reads the samples again to name a ride.
2. **Relations over places** (near, through, shared): the features along a route, the rides over a climb, `--near`, the
   author's landmarks, and later the heat map.  **SQL, on cells.**

**Tables** (names to settle):

* `route_cell(activity_id, cell, t_in, t_out)`, one row per visit (a visit is a run of samples in one cell), `without rowid`,
  with an index on `(cell, activity_id)`; written by Nim at import from the arrays (cheap per ride; the 13 s above is SQL
  over all 6.2 M rows at once).  Owned by `importer`.
* per-cell place tables, made when a cell first appears (or when the names of its region are downloaded): the features
  within 2 km of the cell, with their kind and distance; the landmarks whose radius covers it.  Owned by `names`; they
  refer to cells, not rides.
* the stored shape facts, owned by whoever names activities (§5).
* `route` loses its job as a spatial index; it may become a simplified line for drawing (TODO item 4) or go, the map's
  GeoJSON being made from the arrays.  The climbs keep their geometry (small) and their SpatiaLite overlap tests, which
  already win (HISTORY.md, "Overlap of climbs in SQL").
* the cell id is one function, written once in Nim (`geo`, pure, tested) and registered in SQLite (`db/functions.nim`, as
  `fold` is), so that SQL and Nim cannot compute it differently.

**What it replaces**: reading `coords` to name rides; `RouteGrid`, the via loop over `featuresNear`, `ridesNear` by box,
much of `prepare` and the per-ride feature loading; `coords` itself (by the arrays).

**What it makes cheap** (features, not part of the change): a heat map by cell; "rides through here" as a criterion;
new roads (cells never visited before); explorer squares; **grouping rides by the cells they share** ("your usual loop",
the same name for the same route), a way of classifying rides that the current design has no handle on.

**The grid** (**decided**: plain latitude and longitude; the author: nobody rides near the poles).  The alternatives were H3
or S2, which need a C library loaded into SQLite.  Known limits of the plain grid, accepted: cells narrow towards the poles,
and cells either side of ±180° are not neighbours by arithmetic.

## 5. Decisions to make before building

1. **Where naming lives.**  Today `importer` names each activity (`importer/naming.nim` calls `names/activity.nim`), so
   `importer` depends on `names`.  The via query joins `route_cell` (importer's) with the place tables (names'), so the package
   that runs it must read both.
   * **(a)** Naming moves above `importer`: `names` (or a new package `naming`) depends on `importer`, contributes to "after
     import", and owns the names of activities in a table of its own (`activity` is `importer`'s; today its `name` and
     `start_place` columns are written by `importer` on `names`' behalf).  `names`' place tables stay keyed by cell, so the
     GeoNames part does not need `importer`.
   * **(b)** Naming stays in `importer`, which already depends on `names` and so may read its tables; the query is written in
     `importer`.  Smaller, but the naming rules stay in the package that reads FIT files.
   * **Recommended: (a)**, with the GeoNames library (`names`) and the naming of activities as two packages, so that each
     is one thing.
2. **Levels.**  One level (1/1024°) for everything measured above, coarser ones by shift.  The 50 m tolerance of the
   shape rule is not needed in SQL (the shape stays in Nim).  Recommended: one stored level; add another only for a
   measured reason.
3. **The thresholds in cell terms.**  "Within 2 km of the route" becomes "within 2 km of the centre of a cell the ride
   visited" (an error of about 70 m).  There is no ground truth: judge by the rides that change (13 of 560 for the via).
4. **One rebuild, together with step 9.**  The arrays and `route_cell` are both written at import; doing them together means
   one change of the importer and one rebuild.

## 6. Plan (replaces TODO items 2, 4, 5, 6 of the proposed order; each a discussion first, then steps)

1. The decisions of §5, with the author; `/oppose` on this section.
2. The cell id in `geo` (pure, tested: neighbours, shift to a coarser level, the centre) and registered in SQLite.
3. The per-activity arrays (step 9) and `route_cell`, written at import; `coords` goes.  Measure: size, import time.
4. The shape facts at import (Nim) and stored.
5. The place tables per cell (`names`); naming by SQL on cells, placed as §5.1 decides; `RouteGrid`, the via loop and the
   per-ride feature loading go.  Measure: naming of every ride (today 6.2 s plus 4.6 s reading); list the rides whose name
   changes.
6. Climbs: candidate passes by cells, the exact gate test on the window of the arrays the visits give.  Measure the climbs of
   every ride before and after; the efforts must be the same (or each difference explained).
7. `route`: a simplified line for drawing, or gone; `--near` by cells; the map from the arrays or the simplified line.
8. Then the features of §4 as the author wants them (heat map, new roads, grouping rides).

## 7. What stays as it is

The climbs' geometry and their overlap tests in SpatiaLite; the lookups round one point (start place, destination,
landmarks at a point); the GeoNames loading by 1-degree cells (`coverage`) with the countries; the series algorithms in Nim.

## 8. The prototype queries (SQLite 3.53 with math functions; SpatiaLite loaded to read `X()`, `Y()`)

```sql
-- the visits of every ride to cells of 1/1024 degree (13 s over 6.2 M rows; at import, Nim does it per ride)
create table route_cell (activity_id integer not null, cell integer not null, t_in integer not null, t_out integer not null,
  primary key (activity_id, t_in)) strict, without rowid;
insert into route_cell
with c as (select activity_id, t,
             (cast(floor((lat+90)*1024) as integer) << 32) | cast(floor((lon+180)*1024) as integer) as cell from coords),
r as (select activity_id, t, cell, row_number() over (partition by activity_id order by t)
           - row_number() over (partition by activity_id, cell order by t) as grp from c)
select activity_id, cell, min(t), max(t) from r group by activity_id, cell, grp;
create index route_cell_cell on route_cell(cell, activity_id);
create table ride_cell (activity_id integer not null, cell integer not null, primary key (activity_id, cell)) strict, without rowid;
insert into ride_cell select distinct activity_id, cell from route_cell;

-- features with a coarse cell (1/32 degree, 5 bits up) and the kind the naming rules give them (0: never chosen)
create table feat (id integer primary key, name text, class text, code text, lon real, lat real, coarse integer, kind integer) strict;
insert into feat select id, name, class, code, X(geom), Y(geom),
  (cast(floor((Y(geom)+90)*32) as integer) << 32) | cast(floor((X(geom)+180)*32) as integer), null from feature where geom is not null;
update feat set kind = case when class = 'P' then case when code in ('PPLQ','PPLW','PPLH') then 0 when code = 'PPLX' then 2 else 1 end
  when code in ('PRK','RES','RESA','RESF','RESH','RESN','RESV','RESW') then 3 when code in ('LK','LKS','RSV') then 4
  when code in ('MTS','VAL','VALS','CNYN','HLLS','PLAT','PLN','VLC','DSRT','GRGE') then 5
  when code in ('FRM','FRMS','BDG') then 6 else 0 end;
create index feat_coarse on feat(coarse);

-- every cell visited, with its centre; the useful features within 2 km of it (0.59 s for all, with every kind)
create table cell (cell integer primary key, lon real, lat real, cx integer, cy integer) strict;
insert into cell select cell, ((cell & 0xffffffff) + 0.5)/1024.0 - 180, ((cell >> 32) + 0.5)/1024.0 - 90,
  (cell & 0xffffffff) >> 5, (cell >> 32) >> 5 from (select distinct cell from route_cell);
create table cell_via (cell integer not null, kind integer not null, dist_m real not null, feature integer not null,
  primary key (cell, feature)) strict, without rowid;
insert into cell_via select cell, kind, d, fid from (
  select c.cell, f.id as fid, f.kind,
    111320.0 * sqrt(power(f.lat - c.lat, 2) + power((f.lon - c.lon) * cos(radians(c.lat)), 2)) as d
  from cell c join (select -1 as dx union all select 0 union all select 1)
  join (select -1 as dy union all select 0 union all select 1)
  join feat f on f.coarse = ((c.cy + dy) << 32) | (c.cx + dx) where f.kind > 0) where d <= 2000;

-- the via of the loop and mixed rides (0.16 s + 0.52 s): within 2 km of the route, a third of the furthest distance
-- from the start or more, the first kind that has anything, then the closest
create temp table want as select id, X(start) as slon, Y(start) as slat from activity
  where name like 'loop via %' or name like 'around %';
create temp table far as select w.id, max(111320.0 * sqrt(power(c.lat - w.slat, 2)
    + power((c.lon - w.slon) * cos(radians(w.slat)), 2))) as far_m
  from want w join ride_cell r on r.activity_id = w.id join cell c on c.cell = r.cell group by w.id;
select id, name from (
  select x.id, f.name, row_number() over (partition by x.id order by x.kind, x.d) as n
  from (select r.activity_id as id, cv.feature, cv.kind, min(cv.dist_m) as d
        from want w join ride_cell r on r.activity_id = w.id join cell_via cv on cv.cell = r.cell
        group by r.activity_id, cv.feature) x
  join feat f on f.id = x.feature join want w on w.id = x.id join far on far.id = x.id
  where 111320.0 * sqrt(power(f.lat - w.slat, 2) + power((f.lon - w.slon) * cos(radians(w.slat)), 2)) >= far.far_m / 3)
where n = 1;

-- candidate passes over every climb (0.61 s): visits to the 3 x 3 cells round each gate, consecutive visits near one gate
-- joined, a pass is a start island followed by a finish island
create temp table gate as select id as sector_id,
  (cast(floor((Y(StartPoint(route))+90)*1024) as integer) << 32) | cast(floor((X(StartPoint(route))+180)*1024) as integer) as s,
  (cast(floor((Y(EndPoint(route))+90)*1024) as integer) << 32) | cast(floor((X(EndPoint(route))+180)*1024) as integer) as f
  from sector;
create temp table near as
  select g.sector_id, 0 as which, ((g.s >> 32) + dy) << 32 | ((g.s & 0xffffffff) + dx) as cell from gate g,
    (select -1 as dx union all select 0 union all select 1), (select -1 as dy union all select 0 union all select 1)
  union all
  select g.sector_id, 1, ((g.f >> 32) + dy) << 32 | ((g.f & 0xffffffff) + dx) from gate g,
    (select -1 as dx union all select 0 union all select 1), (select -1 as dy union all select 0 union all select 1);
create index near_cell on near(cell);
create temp table pass as
with v as (select n.sector_id, r.activity_id, n.which, r.t_in, r.t_out,
    row_number() over (partition by n.sector_id, r.activity_id order by r.t_in)
  - row_number() over (partition by n.sector_id, r.activity_id, n.which order by r.t_in) as grp
  from near n join route_cell r on r.cell = n.cell),
island as (select sector_id, activity_id, which, min(t_in) as t_in, max(t_out) as t_out
  from v group by sector_id, activity_id, which, grp),
seq as (select *, lead(which) over w as next_which, lead(t_out) over w as next_out
  from island window w as (partition by sector_id, activity_id order by t_in))
select sector_id, activity_id, t_in as from_t, next_out as to_t from seq where which = 0 and next_which = 1;
```

(The shape prototype, which lost, is not kept: it computed the turning point and the retraced shares from cells of
1/2048 degree with window functions and a table of the way out's cells.)

---

# Appendix B: the second review (2026-11-09)

Its plan is done (HISTORY.md), except what TODO.md still lists.  Section numbers inside it are its own.

Scope.  The state of the plan of the first review (appendix A), with the author's questions: is fuzzing done; is the
access model right; are the command packages a way round the DAG; and tools (a formatter in the build, generated
documentation).  Read: TODO.md, PACKAGES.md, HISTORY.md (the entries since 2026-11-08), every `package.nim`, the fuzzer
(`tests/fit/test_fuzz.nim`, `tests/support/fitmutate.nim`), `core/access.nim`, `core/extension.nim`, `core/manifest.nim`,
`packages/db/access.nim`, `packages/db/sqltext.nim`, `packages/db/store.nim`, the imports of every command package.
Run: `nimble test` (1348 tests, all pass, 50 s, no warnings), `nph --check`, `nim doc --project`, a libFuzzer harness.
Sections 3 to 7 were discussed with the author, and the decisions are theirs (marked **decided**).

### 1. Summary

The first review's plan has gone well.  Steps 1 to 7 (bugs, conventions, dead code, typed database access with named
values) are done and hold up; the package framework (step 8) is built, with a registry, an import checker, inferred
table ownership and, beyond the plan, an access model that SQLite enforces.  Two things are not right yet:

* **Fuzzing** is half done: the FIT fuzzer is good but has never been shown to find a bug, and it fuzzes the reader of
  `nch fit`, not the importer.  The other readers and coverage-guided fuzzing are not started (§3).
* **Command packages** (`packages/commands/*cmd`) are, in two cases out of eleven, a way round the DAG rather than a
  layer: merged back with the packages they manage they would make cycles.  The `cmd` layer goes; commands go back
  into their packages; the cycles become extension points (§5).

The access model is sound and stays, with one addition so that extension points can contribute SQL (§4).

### 2. The plan of the first review: where it stands

| Step | State |
|---|---|
| 1 housekeeping, 2 tests that find bugs | done |
| 3 the bug classes A–L | done, except the fuzzers (§3) |
| 4 the reported bugs, 5 conventions, 6 dead code | done |
| 7 typed database access, values by name, `Sql` | done |
| 8 packages | built (PACKAGES.md); the command layer is revised here (§5); package READMEs wait for the doc tool (§7) |
| 9 options carry their help | not started; part of it is needed earlier now (§5, criteria) |
| 10–14 completion, one owner per fact, SQL, shrink, larger changes | not started |

Small drift found (each is a TODO item):

* 6 files no longer in nph's format (`user/package.nim`, `tests/core/test_registry.nim`, ...): nothing checks it (§7).
* `activitiescmd/cmdname.nim` has no `{.push raises: [].}`.
* `db/sqltext.nim`'s header says short queries use `?`, which is now a compile error.
* PACKAGES.md lists built work under "Left"; TODO.md's step 8 is history.
* `nch.nim`'s doc comment is not valid RST (`*cmd/` opens emphasis), so `nim doc` stops; two broken-link warnings.
* CLAUDE.md is 418 lines, much of it feature detail (the first review's §9.5): it moves to the packages' docs (§7).
* `web/request.nim` `commandRules` names `map` and `ff` and their options: a fact of two higher packages, written
  in a lower one (§5).

### 3. Fuzzing

**What was built is good**: `fitmutate.nim` walks the records and damages what the decoder trusts (field sizes, base
types, counts, record headers, compressed timestamps), then repairs the CRCs so that the damage reaches the decoder;
fixed seed; failing inputs saved.  A run of 84,000 mutations found nothing.  Why it looked unproductive:

* **It has never been shown to find a bug.**  The class L bugs were found by reading and confirmed with tests; the
  fuzzer ran after they were fixed.  Finding nothing means little until it is shown that it would have found them.
* **It fuzzes the wrong consumer.**  It runs `renderInto` (`nch fit`).  The importer's `readActivities`
  (`importer/extract.nim`) is pure and runs on every file imported, and it does the arithmetic on times and positions
  (sessions, timer segments, stretches).  (The first review said "the FIT decoder": its wording.)
* **The other inputs are not fuzzed**: `decodeBits` (from a URL: the most exposed), the xlsx and zip readers, the
  server's `parseTarget`.

#### Level 1 (an ordinary test, in `nimble test`)

1. **Show that it finds a bug**: remove one guard that was added for class L (`isFitTime` before `fitToTime`) in a
   scratch copy, run the fuzzer with its default rounds; it must report the `OverflowDefect`.  Record the result in
   HISTORY.md.  If it does not, improve the mutator (values in `date_time` fields wider than 32 bits) before going on.
2. **The importer**: every mutated file also goes through `readActivities`, with and without the `heart_rate`
   channel; ends in success, a `FitError` or an `ImportError`.  Add one or two large real files (developer fields,
   many message types) with fewer rounds: the 12 KB limit leaves them out.
3. **`decodeBits`**: random strings over the URL-safe alphabet, and damaged valid encodings (bit flips, truncation,
   appended characters, huge run lengths); the result is an error or ids in 1..`maxId`, never a Defect.
4. **xlsx and zip**: damage `Profile.xlsx` in the container (local header sizes, compression method, CRC, central
   directory) and in the inflated XML; the result is a `ProfileError` (or the zip's error).  The GeoNames reader goes
   through the same zip code.
5. **`parseTarget`** (the request path and query, percent-decoded): random and damaged addresses.
6. Every failure found (here or at level 2) is saved under `tests/data/fuzz/<target>/` and a test replays the
   directory, so a fixed bug stays fixed.

#### Level 2 (libFuzzer: coverage-guided, run by hand, not in the tests)

Checked on this machine (2026-11-09): clang 21 works, but it chooses GCC 16, which has no `libstdc++.so` (the
installed `libstdc++-devel` is GCC 15's), so linking fails with `cannot find -lstdc++`.  Passing
`--gcc-install-dir=/usr/lib64/gcc/x86_64-suse-linux/15` to both compile and link fixes it; nothing to install.  A toy
Nim harness then found its planted `IndexDefect` in seconds.

* **A harness per target** in `tests/fuzz/` (`fit_decode`, `fit_import`, `bits`, `xlsx`, `request`): a Nim proc
  `LLVMFuzzerTestOneInput(data: ptr UncheckedArray[byte], len: int): cint {.exportc, cdecl.}` that calls the target and
  treats the expected exceptions as success.  The profile is loaded once (a module-level `let`, which is allowed in a
  test tool), not per input.
* **Build**: `nim c --cc:clang --noMain -d:release --checks:on --panics:on -d:useMalloc` with
  `--passC/--passL:"-fsanitize=fuzzer,address --gcc-install-dir=..."`.  `--panics:on` makes a Defect abort, which
  libFuzzer records as a crash; `-d:useMalloc` lets the address sanitizer see Nim's memory.
* **`nimble fuzz`**: `nimble fuzz TARGET [SECONDS]` builds and runs one harness, corpus in a git-ignored
  `fuzz-corpus/<target>/` seeded from the test files (FIT) or from valid examples (bits, request); crashes are written
  to `tests/data/fuzz/<target>/` (level 1 replays them).  The GCC directory is found by the task (the newest
  `gcc/x86_64-suse-linux/*` that has `libstdc++.so`), not written in.
* **Time box**: one hour per target.  What it finds is fixed (a test first); if nothing, record it in HISTORY.md and
  stop.  Fuzzing is then done, apart from a rerun after big changes to a reader.

### 4. The access model

**Sound; it stays.**  SQLite's authorizer is the database's own mechanism; it checks exact tables, not a scan of text;
it costs nothing per row; the grant is the `depends` that is already declared (one fact); it found about ten real
violations and made the owners do their own writes.  The cascade rule (a cascade's reach is the database's doing) is
subtle but correct and is tested against SQLite.  Three changes:

1. **SQL built by more than one package** (**decided**: option (a)).  A statement is checked as the package of the
   file that runs it.  An extension point that contributes SQL breaks this: `climbs` contributes a `--climb` condition
   on `effort`, and the package that runs the query may not read `effort`.  (`replaceSelection` taking ids rather than
   a query is the same problem met earlier.)  The fix: an `Sql` records the packages whose files wrote its pieces, as
   the helpers already do (`instantiationInfo` and `packageOfFile`, when the program is compiled; nobody writes a
   package's name by hand).  `sqlOf` and the `&` that joins a plain string become templates; `&` of two `Sql` joins
   their sets.  The rule (after `/oppose`):
   * **a read** is allowed if the runner (the file that executes the statement, known as today) or any package of the
     set may make it.  The runner is added explicitly: an `Sql` handed on unchanged does not contain it;
   * **a write or a change of definition** is allowed to the runner alone.  Otherwise a contributed piece in
     `insert into selection select ... where <piece>` would let the runner write the contributor's tables.

   The cost, accepted: in a mixed statement the runner's own pieces could read the contributor's tables unnoticed (a
   mistake-catcher, not a wall).  It is covered on the contributor's side by a test: each contributed criterion, wrapped
   as `select a.id from activity a where <piece>`, is prepared as the contributor alone and must pass.  The alternatives
   were a temporary table of ids written by the contributor, and lists of ids.
2. **Nothing confines the raw library.**  Every statement goes through the checked helpers today (checked by grep), but
   six files outside `db` import `db_connector/db_sqlite` (for `DbConn`).  `db` re-exports the types it hands out, and
   the import checker allows `db_connector` in `db` only.
3. **`db` owns the `user` table** (**decided**: move it).  The reason, from the history: every per-user table hangs off
   `user`, and `openStore` (`db/store.nim`) resolves the current user when it opens the database (it makes the
   `default` user in an empty database, applies `--user`, and keeps the id and name in the `Store`).  The way round:
   `openStore` opens the file and applies fragments, nothing else; the `user` package owns `user` and `user_profile`
   and has `openSession(g): Session` (the store and the user), which does today's lookup; commands call it.  Three
   packages' tables refer to `user` (importer, selection, user) and add it to `depends`.  `db` then knows no domain.

### 5. Commands back into their packages (**decided**, revised after `/oppose`)

#### Diagnosis

The test (the author's): merge each command package with the package whose things it manages and see where a cycle
appears.

| Command | Goes into | Cycle? |
|---|---|---|
| `fit`, `climbs`, `landmarks`, `models`, `cache` | `fit`, `climbs`, `names`, `model`, `cache` | no |
| `db` | `db` | no, once `humanBytes` (a number format, the only thing `nch db` takes from `download`) moves to `ui/units`; then `db` gains only `args`, `confirm` and `ui` |
| `log`, `map`, `ff` | packages of their own: `log`, `map`, `ff` | no: features that own no tables |
| **`activities`** | `importer` | **yes**: needs `selection` and `climbs`, which are above `importer` |
| **`users`** | `user` | **yes**: needs `importer` (counts) and `model` (impulses), above `user` |
| (hidden) | `web/request.nim` | names `map` and `ff` and their options, from below them |

Eight of the eleven were only naming; two (and the server's list) hid a cycle.  The layer "commands above libraries"
let a command know everything above its concept, which is the opposite of extensibility: a later package (training
load, weather) could not add a criterion to `activities` or a line to `users` without editing them.

#### The rules

* **A package may provide commands.**  A **plural** command (`activities`, `climbs`, `users` ...: CLAUDE.md, "the shape
  of the commands") goes with the package that owns its type.  A **singular** command (`map`, `ff`, `log`, `calendar`)
  is a package of its own, unless it is plainly one package's interface (`fit`, `cache`, `db`, `import`).
* **No command hides a cycle.**  When a command would need a package above the one it belongs to, that package
  defines an extension point and the higher package contributes to it.
* **An extension point is made whenever the alternative is a cycle**, even with one contributor.  This replaces
  PACKAGES.md's "a new point is added only when a second real case exists" (that rule guarded against speculative
  design; the aim of adding a package without editing others is the reason now).
* **A low package that grows upward is a smell even without a cycle**: move the misplaced function (as `humanBytes`)
  rather than add the dependency.
* The `commands/` group and the `cmd` suffix go.  Kept: a command module is imported only by its `package.nim`
  (commands are not libraries).  The command module is the one that `CommandDecl.run` comes from, which the registry
  generator knows; the test asks it, not a file-naming convention.

#### Activities: a library and several commands (**decided**)

`activitiescmd` (2,300 lines: criteria and ranges 850, the command 550, table and display 290, live display and log
220, import 175, calendar 145, delete 85) is taken apart by layer:

| Package | What | Depends on (new) |
|---|---|---|
| `importer` | the activity tables; **`nch import PATH...`**; the extension point "after import" | `user` |
| `selection` | **a library, no command**: the stored selection, the map address, the criteria language with the extension point "activity criteria"; turns criteria or the stored selection into activity ids | `importer`, `user` |
| `activities` (new) | `nch activities [CRITERIA] [--select] [--delete] [-v]`: the table, saving the selection, deleting through `importer/remove`; contributes "the new activities become the selection" to "after import" | `selection`, `importer` |
| `calendar` (new) | `nch calendar` (was `activities --calendar`): the selection, or `--all`; no criteria, like `climbs` and `map`.  Later the fitness background (TODO.md) is a direct dependency on `model`, with no point | `selection`, `importer` |
| `climbs`, `map` | as now; contribute `--climb` (`climbs`) | `selection` |

* **`nch import` reverses a rule of CLAUDE.md** ("the shape of the commands": there is no `import`, it is
  `activities --import`); the author chose it.  It also ends the oddity of the log naming `import` (A §3.1 F).
* `--select` and `--delete` stay on `activities` (the grammar of the plural commands).  Criteria belong to
  `activities` alone; the other views take the selection or `--all` (CLAUDE.md, "activity selection").
* "After import" (**decided**): `importer` calls the contributions once per import, after the commit, with the store,
  the user and the new activity ids.  If one fails the import stands and a warning says the selection was not changed.
  Why (the author): in daily use the latest import is the main use, so it should be selected with no extra command.
  (The alternative was a "last import" criterion and no point.)

#### The extension points

| Point | Defined by | Contributed by | Value |
|---|---|---|---|
| activity criteria | `selection` | `climbs` (`--climb`) | see below |
| after import | `importer` | `activities` | a proc (store, user, new ids) |
| what a user has | `user` | `importer` (activities) | a column for `nch users`: a heading and a count for a user |
| pages the server may run | `web` | `map`, `ff` | today's `CommandRule` (name, options, flags, the pinned option) |

* **A criterion** is more than an option and an `Sql`.  `--climb` takes the words up to the next option, resolves them
  against the database ("no climb has 'x' in its name" is an error) and adds notes on what matched.  So a contribution
  is: the option (step 9's `Opt`: name, value name, help, how many words it takes), and `resolve(store, user, values)`
  giving the `Sql` condition on `activity a` (§4.1) and its notes, or an error message.  The completion source is added
  at the completion step.  Contributed conditions are joined with `and`, like the built-in ones.
* **What a user has**: only the activity count comes from above `user`.  The FTHR-change note ("the impulses worked out
  with the old one are deleted") is the doing of `model`'s own trigger, so `nch users` says it generically ("what is
  worked out from the FTHR is worked out again") and `model` contributes nothing.
* Tags (TODO.md) are not needed: if wanted, a package that contributes a `--tag` criterion.

#### Order

1. *(mechanical)* `humanBytes` to `ui/units`; then the commands with no cycle into their packages (the eight of the
   table); the `commands/` group goes; tests move with them; the import test's command rule asks the registry.
2. §4.1 (`Sql` records its packages; reads by the union and the runner, writes by the runner) with the contributor
   test, and §4.2 (`db_connector` in `db` only).
3. `user` owns `user` (§4.3); `users` goes into `user` with "what a user has".
4. "Pages the server may run"; `commandRules` goes.
5. `nch import` in `importer`, with "after import".
6. Step 9's option type (an option carries its help, value name and the words it takes; usage generated), for the
   criteria first.
7. `selection` becomes the library with "activity criteria"; `climbs` contributes `--climb`; the packages
   `activities` and `calendar`; `activitiescmd` goes.
8. Documentation of each package (§7); CLAUDE.md ("general structure", "the shape of the commands") and PACKAGES.md
   describe the result.

### 6. `/oppose` (done 2026-11-09)

Run on §5 and §4.1.  Taken in: the write rule and the contributor test (§4.1); the rule change for extension points
stated; `humanBytes` and the smell of a low package growing upward; singular and plural commands placed by rule; the
command module identified by the registry; the shape of a criterion; `model` out of "what a user has".  The largest
finding, that `selection` would become a misnamed giant holding the whole `activities` command (and the future
fitness calendar would pull `model` into it), led to the split into a library and several commands.  The "after
import" point was kept over a "last import" criterion.

### 7. Tools

#### nph (the formatter)

* `nimble fmt`: `nph src tests tools`.
* `nimble test` runs `nph --check src tests tools` first and stops if a file would change (so drift cannot pass the
  tests; it is quick).
* A Claude Code hook (`.claude/settings.json`, PostToolUse on Edit and Write of a `.nim` file) runs `nph` on the
  file, so that AI-written code is formatted as it is written and the check never fires for that reason.
* **The version is part of the format**: nph's output changes between releases, and the installed one reports
  `prerelease-0-g2cacf6c-dirty`.  Install a tagged release (it has to be built with a matching Nim), write the
  version in `nimchoo.nimble`, and have `nimble fmt` refuse a different one.

#### nim doc (generated documentation)

`nim doc --project --index:on --outdir:doc src/nch.nim` works with this layout: 200 pages in 3 s, the directory tree
of the packages, an index of every exported name.  It stopped on one error (§2) and warned twice.  The least work:

* **A package's documentation is the `##` comment of its `package.nim`** (no separate README): what the package is
  for, what it owns, its rules (the feature detail now in CLAUDE.md moves there).  `nim doc` renders it.
* `nimble doc` writes `doc/` (git-ignored).  The registry generator also writes, as the `##` comment of
  `registry.nim`, the list of packages in dependency order, each with the first line of its comment and a link: the
  front page.
* Doc comments are RST (with Markdown extensions): `*`, `_` and `[...]` in prose need backquotes.  `nimble doc` must
  end without warnings (the warning-free rule), so a broken comment is found when the docs are made; `nimble test`
  could run it too (3 s).

---

# Appendix A: the first review (2026-11-08)

Its plan is TODO.md's history; what it describes as wrong is mostly fixed (§2 above).  Kept for the reasoning.  Section numbers inside it (§3, §7 ...) are its own.

Scope.  First pass, by hand: the dispatcher, the CLI parser, the db layer and every SQL fragment, climbs
(command, params, detect), the activities command and its criteria, the importer pool, the server handler, a
sample of tests, TODO.md's conventions; the import graph and the real database (read-only).  Second pass, by
three subagents: fit/, profile/, xlsx, zip, bundle/; names/, landmark/, download/, the rest of climbs/, geo;
ff/, model/, map/, serve/, templating, cache, ui/.  Their most serious claims were checked by hand; the rest are
marked "reported".  ~18k lines of source; 1159 tests, all passing (`nimble test`, 2026-11-08).

Section 6 (packages) was agreed in discussion with the author afterwards.

### 1. Summary

The code is **competent and careful, but "locally good, globally drifting"**.  Individual functions are clear,
pure where they can be, well commented and well tested; the error discipline (`{.push raises: [].}` everywhere,
checked by the compiler) is stricter than most Nim.  What is weak is the layer above the functions: the same
fact is written in several places that nothing keeps in step, module boundaries no longer match what the
modules do, the database layer stops halfway (typed writes, string reads), work that SQL should do is done in
Nim, and some parts are built bigger than they need to be.  These are the typical results of many small
AI-written increments, each correct, none revisiting the whole.  There are also real bugs (§3), each an instance of a missing abstraction.

### 2. Good

* **Error handling**: four kinds of failure, one mechanism each; `raises` is compiler-checked; commands return
  exit codes and never leak traces for expected errors.
* **Schema**: `strict` tables, `without rowid` where it pays, `on delete cascade` from user down, spatial
  indexes used where it matters.  WAL, `synchronous=normal`, incremental vacuum: all appropriate.
* **Database versions**: numbered SQL fragments per module, checksums, append-only, applied in a transaction,
  squashed at milestones.  Good; it stays (and becomes per package, §6).
* **Pure modules**: `climbs/detect`, `geo`, `shape`, `climbpick`, `match`, `ordinal`, `bits` are small, pure,
  documented and tested.  Distinct types for `FitTime`/`UnixTime` and the ids.
* **The FIT tokenizer** checks every length read from the file before using it, with offsets in the errors.
  Real variant objects where they are used (`Token`, `Event`, `FieldValue`).
* **`download/fetch`** is a model design: network and disk injected, size and free space checked, atomic writes.
* **The web server**: whitelist routing, Host check, token compared in constant time and kept out of logs and
  URLs, CSP, no shell; no path traversal found.
* **The maths**: impulses integrated analytically; storing impulses per hour is the right design.
* **Tests**: real databases in temp dirs, error paths tested, `offline: true` enforced, a structure test.
* **Dependencies**: few and sensible (zippy, db_connector, checksums).

### 3. Bugs, and the missing abstractions behind them

These were found by reading part of the code; there will be more of the same kinds.  Each bug is an instance of
a class, and the class is a missing abstraction (a common idea with no single home).  So the fix is the
abstraction, plus a test that would catch the next instance; the known bugs are its first cases.  The classes
are lettered so that the plan (§7) can refer to them.

#### 3.1 Checked (confirmed in the code)

**A. The structure of an activity's track is left to each consumer.**  `climbs/work.nim:204-233` builds one
profile from every point, though `buildProfile` (profile.nim:76) says its input is one timer segment: a ride
with the timer stopped while the rider is moved (car, train) gets the gap as road (invented climbs, efforts
across the gap; a café stop is harmless).  *Fix:* one loader that returns a track as its segments, so a
consumer cannot ignore them; check the other consumers (impulses, names, map) against it.

**B. Noisy input reaches every consumer, and work grows with it unbounded.**  One bad GPS fix makes a box of
more than 4000 cells, and `names/lookup.nim:66` falls back to `allCountries()`: every country's GeoNames file
is downloaded (~250 zips).  *Fix:* explicit limits wherever work fans out (downloads, cells, sizes), refusing
with a message; later, cleaning at import (outlier positions, impossible jumps) in one place, with the per-activity
arrays.

**C. Queries are not checked against the schema.**  No index on `effort(activity_id)`: deleting activities and
`activity_id in (...)` scan the table.  SQLite does not index foreign keys by itself.  *Fix:* a test that every
foreign-key column has an index (`pragma foreign_key_list`, `index_list`); once queries go through the typed
layer, a test that runs `explain query plan` on them and flags scans of big tables.

**D. Running a child process.**  `serve/server.nim:19-21` reads all of stdout, then all of stderr, then waits
with a timeout: a hung worker is never timed out or killed, and one that fills the stderr pipe deadlocks.  The
server is single-threaded, so one slow `map` blocks every request.  *Fix:* one helper that runs a child (both
outputs read at once, a timeout, kill); the server stops blocking on one request.

**E. Cache keys that do not cover all the inputs.**  `map/command.nim:186-188` reuses an existing file; the
key covers the activities only, so a renamed climb or a changed detector keeps the old map until the cache is
deleted.  `ff` does it right (`inputKey`).  *Fix:* one cache interface: a cached file is keyed by the inputs
its maker declares (the data and the versions of the methods).  It belongs to the cache package (§6) and ties
to the versions of on-demand work.

**F. One fact in several places.**  `commandNames` (cli/common.nim) lists `import` (not a command, but the importer logs under it) and lacked
`landmarks`, so `landmarks` runs are not logged.  *Fix:* the registry (§6); more generally 4.1.

**G. Facts about each FIT base type spread over `case` statements.**  A bool's invalid marker (0xFF) reads as
true (`fit/decode.nim:124-127`); every other type drops invalid values.  *Fix:* one table of base-type facts,
the invalid check applied to every type before it is interpreted.

**H. Limits checked against what a file claims, not what it does.**  `zipbytes.nim:60` checks the declared
size, inflates everything, and compares afterwards.  Low risk (GeoNames, the profile).  *Fix:* the rule that a
limit applies to what is actually read; here, cap the inflated output.

#### 3.2 Reported, not yet checked (confirm each with a test before fixing)

* **I. Text compared in different ways.**  SQL `lower()`/`trim()` are ASCII-only (ordinal.nim, landmarks.nim,
  suggest.nim) and `findShown` uses ASCII `toLower`, while `--name` uses `foldText`: `--name ñuñoa` and `--edit
  Ñuñoa` match differently, and the numbering key can differ from the display key.  *Fix:* one fold function,
  registered in SQLite, used everywhere.
* **J. Failures that become data.**  A route that fails to parse gives an empty path, then stored as "nothing
  near": a parsing bug would mark a climb unnameable for good.  Several `except ValueError: discard` drop bad rows.
  *Fix:* the rule that a failure is never stored as a result (raise, or warn and leave the row undone).
* **K. Writing files.**  `bundle/unpack.nim` and `serve/pages.nim` use a fixed `.part` name (two processes
  clash); `unpack.nim` catches `Exception` (hides bugs).  *Fix:* one atomic-write helper with a unique temporary
  name (one exists in serve: use it everywhere).
* **L. Corrupt input reaching a Defect.**  A huge `date_time` overflows in `fromUnix` when `nch fit` prints it
  (`raises: []` does not cover Defects).  Chained FIT files keep the previous file's timestamp; a 0xFFFFFFFF
  timestamp is accepted; a compressed timestamp with no base aborts the file instead of warning; a component
  scale of 0 is not rejected; duplicate names in the profile silently overwrite.  *Fix:* fuzzing (3.3), then
  each case.
* Geography: `countries.nim ensureCountries` keeps one outline per ISO (`limit 1`), so split or disputed
  countries lose parts; cells near a border are assigned by exact intersection with a generalised 1:50m
  outline, so a neighbour can be missed.  The antimeridian is only half handled (low priority; document it).
* Validators that disagree (F/I again): `validModelName` allows `--`, which `isCacheFileName` rejects, so `ff`
  fails for such a model; the map request uses `bits` as typed, not re-encoded from the ids (two spellings,
  two cache files).
* Smaller: the token cookie has no `Max-Age` (bookmarks stop working when the browser closes, though the docs
  say otherwise); `{{{style}}}` is raw JSON inside `<script>` (a `</script>` in the edited style breaks the
  page); `model/calc.nim:20-23`'s comment understates the hour-bucket error about 10x (0.3%, not 0.03%).

#### 3.3 Finding more

* **Fuzz the FIT decoder**: mutate real FIT files at random; the result must be success or a `FitError`,
  never a Defect.  Cheap, and it tests L directly.  Two levels:
  1. **A mutation loop, as an ordinary test** (first; no installs).  Start from the real FIT files the tests
     already use; flip bits, overwrite bytes, truncate, splice in parts of other files, change the header's size
     and length fields; decode each result.  A fixed random seed, so a failure can be reproduced, and the failing
     input saved.  A few thousand mutations run in seconds, so it sits in `nimble test`.  Its limit: it does not
     know which changes reach new code, so it rarely gets past a correct CRC and a valid definition into the
     field decoding (mutations that also fix up the CRC help).
  2. **Coverage-guided fuzzing (libFuzzer)**, once level 1 stops finding things: Nim built with clang's
     `-fsanitize=fuzzer` (which also brings the address sanitizer), run for minutes or hours as `nimble fuzz`,
     not in the tests; whatever it finds becomes a level-1 regression case.  Needs clang (the author installs
     it); a Nim wrapper package may exist but is unchecked (the libraries rule applies).
  The same approach suits the other readers of input we do not control: the xlsx and zip readers and the
  `bits` decoder of the map address.
* **Invariant checks on real data**, run over the author's database as well as test data: every effort lies
  within one timer segment; every activity's samples are in time order; every climb has a name decision; and so on.
* **Schema tests** (C): an index for every foreign key; no scans of big tables in the program's queries.

### 4. Problems, by pattern

#### 4.1 One fact, several copies

The pattern behind the author's enum question.  Nothing keeps the copies in step, and some have drifted.

* Command names: the `usage` text, the `dispatch` case, `commandNames` (already wrong: §3.1).
* Each command's options: the `Spec`, the hand-written `usage`, the validation code; for the web-able ones also
  `commandRules` (serve/request.nim) and `webQuery`.  Adding an option means editing up to five places.
* `cache/files.nim`: an enum with a doc comment per value **and** a parallel `kindHelp` array.  (`array[Kind,
  string]` checks the count; the keyed form `[ckDownloads: "...", ...]` also checks the order; better still,
  one table of records.)
* `BaseType` facts (size, signedness, invalid marker, name, FIT number by position only) in five `case`
  statements; `baseTypeOf` twice with different meanings; FIT type names compared as strings
  (`"date_time"`) though `TypeKind` has them.
* GeoNames feature codes (PPLQ/PPLW/PPLH, parks, hills) listed separately in `activity.destKind`,
  `activity.startText` and `climbpick.kindOf`: the naming rules can drift apart.
* The same function written several times: three route parsers (`work.parseLineString`, `duplicates.pathOf`,
  `naming.parseRoute`); two `num` helpers (attempts, report) plus `queryNumber` (ff); two or three table
  aligners; the SpatiaLite index sub-query in five places; `shape.nim:94-122` re-implements `geo.RouteGrid`;
  three hex checks; user lookup by name in `openStore`, `user/wipe.findUser`, `selection/command.userIdOf`;
  two near-identical Ctrl-C handlers (`ui/live`, `ui/interrupt`).
* Messages that hard-code the constants they describe ("80%", "25 m" in `duplicateLines`).

#### 4.2 Illegal states are representable

**Bags of booleans.**  `climbs/params.nim`: 14 bools, ~40 lines ruling out combinations by hand, then `run`
re-discovers the action with an `if` chain.  Ten commands have this shape (a `Params` with `problem: string`);
`ff` has a bag of output modes (`stdout`, `worker`, `serve`, `noOpen`...) with a `webProblem` to forbid
combinations.  The idiom (Nim, Rust, Haskell...) is **parse, don't validate**: parse into a variant object with
one branch per action, so an impossible combination cannot exist and `run` is a `case` the compiler checks:

```nim
type
  ClimbChange = enum ccRename, ccAuto, ccRetire, ccUnretire
  ClimbAction = enum caShow, caAll, caDelete, caEdit, caRetired, caDuplicates
  Climbs = object
    case action: ClimbAction
    of caShow:
      names: seq[string]
      verbose, everyone: bool
    of caDelete:
      force: bool
    of caEdit:
      climb: string
      change: ClimbChange
      newName: string     # used only when change is ccRename
    of caAll, caRetired, caDuplicates:
      discard
```

**Sentinels.**  `""` for success in every parser (`args.nim`, all `Params`); `""` for "no name" and for
unknown FIT names; `-1` for "no number" (`FieldValue.number`, `timestampField`); booleans read as `r[2] == "1"`;
a stored start place whose `"near "` prefix is both text and state (`nameFor` tests `startsWith("near ")`).
Use `Option`, enums, or a small `Result`.

#### 4.3 The database layer stops halfway

* `db_connector` returns every value as a string: ~120 `parseInt`/`parseFloat` calls on database values, each
  with its own error handling (many `try/except` exist only for this); NULL arrives as `""`.
* Because reads cannot bind typed values, SQL is built by concatenation with hand quoting
  (`selection/criteria.nim`, `names/countries.nim`...).  Correct today, but it is what every reviewer checks,
  and TODO Task 10 item 6 dropped the fix as "a big change" because `Stmt` cannot read rows.
* `db/statement.nim` already wraps the C API for writes (and has `nextRow`, `blobAt`).  Adding typed column
  readers, a `rows` iterator and a `query` that fills a tuple (with `Option` for NULL) removes both problems.
  Alternative: the `tiny_sqlite` library; evaluate before choosing.
* Routes are read as WKT text (`AsText`) and parsed in Nim; read them as numbers or a blob.
* `bringUpToDate` carries dead paths (legacy checksums, the "older version" column check, `seed_version`,
  `reseed`, `withSeed`, used by nothing).  The fragment mechanism itself is good and stays.
* Accent-insensitive search builds globs like `*[tT]oyo*`; a Nim function registered in SQLite
  (`sqlite3_create_function`, `fold(name) like ?`) is simpler, bindable, and fixes the folding bug in §3.2.
* `InitSpatialMetadata(0, 'WGS84_ONLY')` would load the one coordinate system used, not all WGS84 ones.

#### 4.4 Work that SQL should do

* `climbs/duplicates.nim duplicateGroups` compares every pair of climbs in Nim; the spatial index should give
  the candidate pairs.
* `climbs/attempts.nim summaries`: three queries per climb and the ranking in Nim; one query with
  `rank() over (...)`.  `map/command.nim climbsOf` is also a query per climb.
* `names featuresNear` pulls every feature in a box (streams, farms...) and filters in Nim; filter by class and
  order by distance in SQL.
* `countriesOfCell` inserts row by row without a transaction; one `insert ... select` does it.
* `ensureCells` unzips and parses the whole country file again for each new 1-degree cell.
* `missingCells` and `prepare` run a `count(*)` per cell or per country.

#### 4.5 Sample storage

474 MB for 1112 activities: `coords` 263 MB (6.2 M rows), `route` 101 MB, `heartrate` 100 MB (6.1 M rows).

* The cost is **a row per second**, not the number of tables: `heartrate` is ~16 bytes per reading, mostly the
  repeated `(activity_id, t)` key and its index; the value is one byte.
* Every read of `coords` and `heartrate` is "all of one activity, in time order" (`climbs/work.nim:92`,
  `importer/naming.nim:54`, `model/impulses.nim:26`) or "has it any" (`model/impulses.nim:73,111`,
  `selection/criteria.nim:611,613`).  Nothing filters, sorts or aggregates single samples in SQL.
* So per-second data should be **one row per activity, holding arrays** (§6): heart rate ~6 MB instead of 100,
  read in one go.  The cost: an array is opaque to SQL (nothing needs that today; a package that ever does can
  keep a row table of its own).
* `route` is a second full copy of the positions.  It is needed for the spatial index but may not need every
  point: `ST_Simplify` at ~2-5 m could shrink it a lot without changing a "passes near" answer.  Measure.

#### 4.6 Module boundaries have drifted

* Directories do not match commands: `activities` is in `selection/`, `users` in `user/`.
* Shared code lives in whichever module needed it first: the delete countdown in `user/wipe.nim` (used by
  climbs, landmark, db, cache, delete), the time types in `fit/time.nim` (used by seven directories).
* Directory cycles: `fit ↔ profile` (one thing: merge); `climbs ↔ selection` (only `selection/fold.nim`, a
  leaf, plus `activities` using climbs for `--climb`); `names ↔ landmark` (no file cycle: names uses the
  landmark library, the landmark command uses names).  `activities` is a hub: it imports importer, delete,
  climbs and selection.
* `db/` (said to "know no module") has `command.nim`, importing `cli`, `download`, `user`.
* SQL strings read other modules' tables, which no import shows.

The fix is the package design (§6): declared dependencies, checked, and extension points instead of cycles.

#### 4.7 Built bigger than needed

* `templating.nim` implements Mustache sections, inverted sections, lists and scopes; no template uses them.
  About 60 lines would do (a runtime engine is justified: the templates are edited in the cache).
* Two cache naming schemes (`ff` readable, `map` proquint) and two ways for the server to find the check;
  the proquint collision loop and the request stored in the file are more than 48 bits need.
* `fit/decode.nim decode` is ~180 lines with the plain/unknown dispatch written twice; `emitPlain` and
  `decodeField` take 12 parameters (a context object); plan building is written twice.
* `bundle/` (manifest, hash detection of the author's copy, NOTICE) costs more than the xlsx reader it
  serves; a plain `--profile PATH` might do.  (It is also the seed of the cache manifest, §6.)
* Dead or test-only code: `fit/basetype.decode/RawValues/checkBad`, `Tokenizer.bytes`, `readWorkbook`,
  `climbs/profile.smoothed/filtered`, `Effort.startElev/finishElev/finishDist` (always NaN in use).
* Legacy steps in fragments, for the next squash: `names/002-country-cells.sql`'s `update country set geom =
  null`, the back-fill in `climbs/002-name-number.sql`.  Stale comments (`nch sector`, "(n/m)", heatmap).

#### 4.8 Housekeeping

* A compiled binary is tracked: `tests/delete/test_delete` (the `.gitignore` pattern `/tests/test_*` only
  matches the top level).  `tests/sector/` is an empty leftover.
* (done 2026-11-08: TODO.md is open work, history in HISTORY.md, conventions in CLAUDE.md.)  It was 2,758 lines, mostly history; its "Conventions" and "Code layout" describe commands that no longer
  exist (`import`, `list`, `destroy`, `heatmap`) and "one third-party dependency".  Sonnet reads it as current.
* Long, branchy `run` procs (follows from 4.2).

### 5. The author's questions

**Hand-written CLI parsing.**  Common in Nim, and 224 lines is not the problem; the problem is 4.1/4.2.
`std/parseopt` only tokenises; `cligen` builds the CLI from a proc signature, which fights the "one action per
call" shape; `confutils` (Status) is solid but heavy; `argparse` is Python-like.  For tab completion the
deciding fact is that the useful completions are **dynamic** (climb, user and model names, sports come from the
database), which no library does for you.  So: keep the parser, make the spec the single source (each option
carries its help text and the kind of value it completes), generate `usage` from it, parse into a variant
object, and add a hidden `nch __complete WORDS...` that a small bash/zsh function calls.  With packages (§6) each
package registers its commands and options, so completion reads them from the registry.

On libraries generally: use one when it does something hard and is maintained by an organisation or many
users (zippy, db_connector, checksums qualify); write it yourself when it is small and shapes the program (the
CLI).  The own xlsx reader is justified (runtime `--profile`, nothing suitable in Nim).

**The module model.**  The idea is sound, and the author's aim (a DAG of packages, third-party packages
dropped in) is achievable in Nim: see §6.

**Enum descriptions.**  See 4.1.  Sloppy, as suspected, and checkable by the compiler.

**Nim to JavaScript.**  No, for now.  The page is a template the author edits by hand, Leaflet is JavaScript,
and Nim's JS output is large and harder to debug.  It would pay only if real logic had to be shared between
server and browser.  The page's geometry code (offsets, smoothing, lanes) has no tests: if it grows, move it
to a `map-geometry.js` that can be tested under node.

**Macros.**  None is normal for an application; the 38 templates are used sensibly.  The idiom gaps are
elsewhere (4.2).  Otherwise the style is idiomatic Nim 2 (func/proc split, distinct types, destructors,
`lent`).  The comments are long and plain-English, consistently; much help text is repeated in comments.

**SQLite.**  Used well at the schema level (§2), weak at the access level (4.3, 4.4) and in sample storage
(4.5).  SpatiaLite's many tables are normal.

### 6. Packages (agreed in discussion, 2026-11-08; **superseded by PACKAGES.md, 2026-11-09**: kept for the reasoning)

The aim: packages declare their dependencies; the build enforces a DAG; a package sees a database that already
has the tables of everything it depends on, and calls its dependencies' code directly.  A third party adds a
package by dropping a directory in and rebuilding (source drop-in, as Caddy does).  Rejected: loading shared
libraries at run time (Nim has no stable ABI: fragile, and needs a rebuild anyway) and packages as separate
programs (more complex and slower; no function calls between packages).

#### Framework and packages

* **The framework is minimal**: the `Package` type and the registry, the database handle and the fragment
  mechanism, and the types of the extension points.  Nothing else.  It is the interface packages are written
  against, so it changes carefully.
* **Everything else is a package**, including pure libraries (geo, templating, terminal output, time), the
  web server, the cache, `activities` and the importer.  Small packages, and packages with many dependencies,
  are fine: the cost is a `package.nim` each, which also documents the package.

```nim
# packages/climbs/package.nim
const package* = Package(
  name: "climbs",
  depends: @["sectors", "importer", "names"],
  fragments: @[fragment("001-schema.sql")],
  commands: @[climbsCommand],
)
```

* The registry is generated from the package directories (a macro or a nimble task) and sorted
  topologically; a cycle or a missing dependency fails the build.  It replaces `modules.nim`, `dispatch`,
  `commandNames` and the usage list.
* Tests: a package imports only from itself, the framework and its declared dependencies; the tables named in
  its SQL strings belong to the same set (approximate: table names from the fragments, matched in the code).

#### Extension points

An early package defines an extension point; later packages fill it.  This is how cycles are avoided without
merging packages that should be separate.  Known so far:

* **import steps** (exists: heart rate): eager work on each imported activity;
* **on-demand activity work**: "each activity not yet done by version N of my method".  Today `climbs_done`
  and the impulses' "missing" query each do it by hand.  Derived data then never needs a migration: a change
  of method is a version bump and the work is redone;
* **activity criteria**: climbs adds `--climb` to `activities` (breaks `climbs ↔ selection`);
* **name sources, in priority order**: landmarks first, GeoNames after (breaks `names ↔ landmark`);
* **sector naming**: the package that made a sector says how it is named;
* **what will be deleted**: each package adds its line to the deletion message.

#### Sectors

`sectors` becomes a package: the `sector` and `effort` tables, matching rides against sectors (most of
`match.nim`), retiring, duplicates, the kept numbering of shared names.  `climbs` depends on it: it detects
climbs, inserts them as sectors, and keeps `climb(sector_id, gain_m, gradient, category)` of its own.  A later
package that finds sectors by overlapping activities does the same with its own table.  No package alters
another's table.

#### Samples

Per-second data is stored **per activity, as arrays**: one row per activity in a table per channel (or group of
channels), not one row per second.  Under this rule a table per package costs almost nothing, so pluggability
and efficiency agree:

```sql
create table heartrate (
  activity_id integer primary key references activity(id) on delete cascade,
  t0 integer not null,     -- time of the first reading
  bpm blob not null        -- one byte per second; 0: no reading
) strict;
```

* The importer owns time, position and altitude (one table, arrays per activity; the timer segments with them).
* Other channels belong to the package that wants them, taken from the FIT file by an import step (the
  extension point that exists): heart rate stays a package of its own.
* The spatial queries are unaffected: they use `route` and `activity.start`.
* The encoding (plain fixed-width numbers, or compressed with zippy) is decided by measuring; plain first.
* **Defaults** (an alternative needs a reason, given when it is discussed):
  * **refer to samples by time, never by array index** (an index is tied to one encoding; a time is not);
  * **arrays are immutable once written**: cleaning happens before the write; a change to cleaning is a re-import
    (the cascade takes the derived data) or a version bump of the on-demand work;
  * **what SQL cannot check, a test checks**: the invariant checks (§3.3: every effort within one timer
    segment...), run over the author's database too.  Storing a row of arrays per timer segment, rather than per
    activity, would also let a trigger check that an effort lies inside one: to decide at that step.

#### Cache

A package near the bottom, not framework: packages write to it, the loader does not.  It grows the manifest
`bundle/unpack.nim` keeps today into one for every file (detect and warn of edited files), with an area per
package.

#### Database versions (fragments) with packages

The current mechanism stays, per package (`package/NNN-name.sql`, as recorded now).  Added rules:

* A fragment touches only its own package's tables.  A table rebuild keeps whatever dependents refer to.
* A new database applies fragments in DAG order; an old one gets later fragments of an early package after the
  fragments of packages that depend on it.  **A test builds the database by several valid orders and compares
  the schemas** (tables, columns, indexes, foreign keys): this automates the comparison CLAUDE.md asks for by
  hand before a squash.
* Fragments are for imported and hand-entered data (users, landmarks, names given by hand, models); derived data
  uses the version bump of on-demand work instead.
* A database with fragments from a package this build lacks is refused, naming the package ("this database has
  tables from package X, which this build does not include").  `nch db --drop PACKAGE` can come later.
* Squashing: as now, until anyone else has a database (a release: tie this to the version rules still open
  from Task 11).  After that, if the fragment lists grow long, the route is a per-package **baseline** (a
  squashed `001` for new databases, the old fragments kept for existing ones, the schema test proving both give
  the same result).  Not built now.

### 7. Plan (for Sonnet; each step one or more commits, tests passing, discuss before starting)

Cheap and safe first; each later step is easier because of the earlier ones.  Letters refer to the classes of §3.

**Mechanical or design.**  Steps marked *(mechanical)* change no behaviour or design the author sees: they can be
approved together and done without a discussion each (the tests are the check).  The others need a discussion
before they start.  Mechanical: 1, 2 (writing the tests; what they find is reported), 4 (confirming), 5, 6, 8.1,
8.3, 8.4, 8.6, 11, 13 (except the cache naming scheme).  Design: 3, 7, 8.2, 8.5, 9, 10, 12 (each change is
measured and shown), 14.

**Order.**  Packages (8) come before the options rewrite (9) so that each command is rewritten once, in its final
home.  Nothing new for the author to use appears until about step 10; open features (TODO.md) can go in after step
3 or step 8, not before 3 (they would build on code with known bugs).

1. *(mechanical)* **Housekeeping.**  Untrack `tests/delete/test_delete`, fix `.gitignore` (`/tests/**/test_*` with `!*.nim`),
   remove `tests/sector/`, add `landmarks` to `commandNames` (F; the
   registry replaces it later).
2. *(mechanical)* **Tests that find bugs** (3.3): the FIT fuzzer, the foreign-key index test, the invariant checks (with a way
   to run them over the author's database).  Report what they find before fixing it.
3. **Fix the classes**, each as the abstraction, a test for the class, and the known bugs as its first cases:
   A (the track loader; climbs per segment; check the other consumers), B (limits where work fans out; the
   country fallback), C (the indexes the test asks for), D (the child-process helper; the server), E (the
   cache interface; the map key), G (the base-type table; the bool marker), H (the zip cap), J (no failure
   stored as a result), K (one atomic write), L (what the fuzzer finds).  I waits for step 7.
   The track loader (A) is built over today's `coords`; step 14 changes the storage, and then only the loader
   changes.
4. *(mechanical)* **The other reported bugs (3.2)**: confirm each with a test; fix the real ones, report the rest.
5. *(mechanical)* **Check the conventions** now in CLAUDE.md against the code.  (TODO.md was pruned to open work and its
   history moved to HISTORY.md on 2026-11-08; the conventions moved to CLAUDE.md, corrected by hand.)
6. *(mechanical)* **Dead code**: the dead paths in `bringUpToDate`/`fragment.nim` (not the fragment mechanism), and the dead
   and test-only code of 4.7.
7. **Typed database access.**  First half a day evaluating `tiny_sqlite` against extending `db/statement.nim`;
   report back.  Then typed reads, bound parameters everywhere (SpatiaLite then gets real numbers), one user
   lookup, the registered `fold()` SQL function (I); convert module by module; then the query-plan test (C).
8. **Packages (§6)**:
   1. *(mechanical)* move shared code into packages of its own (time, the delete countdown, text folding, geo...); merge
      `fit` and `profile`;
   2. the framework: `Package`, the generated registry (F), the topological sort; fragments in DAG order; the
      "missing package" refusal (rebuild the database);
   3. *(mechanical)* a `package.nim` in each directory, with the package's own doc (the feature detail now in CLAUDE.md
      moves there); the track loader lands in the importer package, the cache interface in
      the cache package;
   4. *(mechanical)* the import and SQL-table tests;
   5. the extension points, one commit each, each discussed first (on-demand activity work, activity
      criteria, name sources, deletion lines); the cycles go;
   6. *(mechanical)* the schema-by-several-orders test.
9. **Options carry their help; parse into variants.**  `Opt` gets `help`, `metavar` and a completion kind;
   usage is generated from the spec (prose before and after stays hand-written); the web options come from
   the same spec.  `climbs` first, shown to the author, then the others (`ff`'s output mode as an enum).
   Errors as `Option[string]`, not "".
10. **Tab completion**: `nch __complete` and a bash function; commands and options from the registry, dynamic
    values from the database.
11. *(mechanical)* **One owner per fact** (the rest of 4.1): GeoNames codes in one place, the duplicated helpers merged,
    messages built from the constants.
12. **Push work into SQL** (4.4), measuring before and after.
13. *(mechanical, but the cache naming scheme is design)* **Shrink** (4.7): templating to what is used; one cache naming scheme; `decode` dispatch written once.
14. **Larger changes, each discussed first**: the `sectors` split; per-activity arrays for the per-second data, with
    cleaning at import (B; measure size and the import, climbs and map times before and after; then a simplified
    `route`); the
    cache manifest.

### 8. Proposed additions to CLAUDE.md

(Added to CLAUDE.md on 2026-11-08, with changes: "revisit, don't pile on" and "before finishing a step" became
working practice; "a missing abstraction is the bug" and "a failure is never stored as a result" were added.
CLAUDE.md is the current text.)

```markdown
## guidelines for writing code (from the review of 2026-11-08)

* **one fact, one place.**  a list of names, options, kinds or help texts is written once and everything
  else is made from it (a table indexed by an enum, generated usage).  never keep two lists in step by hand.
* **parse, don't validate.**  input (the command line, rows from the database, files) is turned into a type
  that can only hold valid values (variant objects, enums, distinct types, `Option`).  no bags of booleans
  checked afterwards; no "" or -1 meaning "none" or "ok".
* **revisit, don't pile on.**  when a new feature fits badly on what exists, change what exists (within the
  package rules: a package never alters another's tables).  say so in the discussion rather than working round it.
* **packages declare what they use.**  a package imports only its declared dependencies (checked by a test);
  shared code is a package of its own, not part of the module that needed it first.  an early package that
  must be extended offers an extension point rather than importing the later one.
* **let the database do database work.**  values are bound, never put into sql text; rows are read into typed
  tuples or objects; filtering, joining, ranking and spatial search are sql, not loops in nim.
* **delete dead code and stale docs in the same commit** that makes them dead.  TODO.md holds open work only;
  conventions live here and must describe the code as it is.
* **before finishing a step**, check what else refers to what you changed (grep the names): lists, help text,
  docs, tests.
```

### 9. For the author

From the record the work left (CLAUDE.md, TODO.md, the commits, the code), not from the conversations.

1. **Specify what, not how.**  Be exact about what you see (output, behaviour, limits); leave the mechanism open.
   At design points ask Sonnet for two or three options and a recommendation rather than giving it the design.
2. **Review shapes, not lines.**  When a change comes back, look at the new types, signatures, schema and module
   dependencies: that is where drift starts, and it is quicker to read than the code.
3. **Hold whole-system reviews**, like this one, at each milestone (or every several features) and before a
   squash, in a fresh session and ideally another model, so that the reviewer is not anchored on the author's
   reasoning.  Each step can be right while the whole drifts; only a whole-system look catches that.
4. **Give permission to revisit.**  "No past to protect" applies to code too: when a feature fits badly, Sonnet
   should say so and propose changing what exists.
5. **CLAUDE.md for rules, not records.**  It is loaded every session; detailed design of particular features
   (climb subscripts, map styling, cache names) pushes Sonnet towards local consistency over overall design.
   With packages, that detail moves to each package's doc.
6. **TODO.md for open work only.**  History is in git (and HISTORY.md); a stale document is read as current.
7. **Make "done" explicit**: tests (with one for the class of bug), docs updated, dead code deleted, references
   checked.
8. **Ask for evidence**: a measurement, or before-and-after examples where there is no ground truth.

Items 1, 4, 6 and 7 are now in CLAUDE.md as working practice; 3 is there as "suggest a review"; 5 is plan step 8.
