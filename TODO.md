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
5. **Tab completion** (A step 10): `nch __complete` and a bash function; dynamic values from the database.  Design agreed
   2026-11-10 (discussion, not yet built); several commits.  The tab key never prints an error, never creates or changes a
   file, never uses the network, and is fast (budget: under 30 ms per press including the query; `nch packages` starts in
   4.4 ms).
   * **Done (commit 1)**: `OptDoc`, `Completion` and `Arity` are in `core/optdoc.nim`; `CommandDecl.options` (each command's
     spec); `core/complete.nim` (the pure algorithm: commands, options, `ckWords` values, `ckFile`); `nch __complete` and
     `nch completion bash` (`completion.nim`).  Still to do: `Completion` as a variant (`ckNone | ckFile | ckWords(words) |
     ckDynamic(provide)`: a dynamic one cannot exist without its provider; `ckDynamic` still names a `source` and offers nothing).
   * **Providers**: `proc(g: Globals, prefix: string): seq[string] {.raises: [StoreError].}`, next to the option they
     complete (`--climb` beside `resolve` in `climbs/criterion.nim`, through `activities/criteria`; sports in `activities`;
     `--user` via `user`; `--edit/--delete NAME` in each package's params).  No registry of sources, no new extension point
     (if an option ever sits below the data it completes, that package then defines a point).
   * **`__complete`** still needs to parse `--db` and `--user` into the `Globals` it gives the providers (it passes none now).
   * **Guards, structural** (every provider gets the `Globals` `__complete` built): `readOnly` in `Globals`, honoured by
     `openStore(g)`: no create, no WAL, no fragments, no SpatiaLite; a missing file, a lock or a database of another
     version is a `StoreError`, caught in one place, printing nothing.  `offline = true` (check that the offline path writes
     no cache files).  `access` kept, so the table authorizer stays on.  Tests: a missing database path creates nothing; a
     database of another version gives nothing and exit 0; a provider that writes or looks a name up gives nothing and
     writes nothing; no child process is started.
   * **Read-only open**: `db_connector` only binds `sqlite3_open` (no flags, no read-only; URIs are not enabled in the
     system SQLite), so `db` declares `sqlite3_open_v2` itself (`importc`, on `db_connector`'s `DbConn`), about ten lines.
     Alternatives looked at and rejected: `tiny_sqlite` (has `dbRead`, but last updated 2023 and would replace the whole
     `db` layer), `sqlite3_abi` (raw API, but bundles its own SQLite, which would meet SpatiaLite's).  Spike (scratch
     program, the real 472 MB database): a missing file gives rc 14 and creates nothing; open plus the sector query is
     2.5 ms; a write is refused; on a WAL database it still makes `-shm` and `-wal` beside it, and in a directory that
     cannot be written the query fails (so: nothing offered).
   * **Commits still to do**: (2) the read-only open and `readOnly`; (3) the providers (`--edit/--delete NAME` included).
   * **Quoting**: candidates (`Cerro San Luis₄`) are printed whole and bash quotes them (to check with the real list);
     `--climb TEXT...` takes several words: complete the word being typed.
6. *(mechanical)* **One owner per fact** (A §4.1).
7. **Push work into SQL** (A §4.4), measured.
8. **Shrink** (A §4.7) (mechanical, except one cache naming scheme).
9. **Larger changes**: the `sectors` package; per-second data as arrays per activity, with cleaning at import; a
   simplified `route`; the cache manifest.

## Open from before the review

To fit into the plan, or to do after it.  Details in HISTORY.md where noted.

* **Cleaning bad positions at import** (A §3 class B, the part not done): drop or flag impossible fixes (a jump faster
  than any rider, a point far from its neighbours) once, at import, so that every consumer sees clean data.  Needs its own
  design (threshold, drop or flag, effect on stretches, climbs and efforts); it changes stored data.  Until then a stretch
  that spreads over more than 5 degrees is not searched for names (HISTORY.md, 2026-11-08).
* **Naming is slow** (11 s for 1,112 activities: 4.6 s reading 6.2 M `coords` rows as text, 6.2 s in
  `nameActivity`, not broken down; nothing shown meanwhile).  The author wants to go through how naming works
  first.  The arrays (step 9) take most of the reading time away.
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
