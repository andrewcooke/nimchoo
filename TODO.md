# TODO

Open work only.  Finished work is in git and in HISTORY.md (with the reasoning behind decisions); the review of
2026-11-08 and its plan are in REVIEW.md.  When something here is done, delete it (in the same commit).

## Now: the review plan (REVIEW.md §7)

Design steps are discussed with the author before they start; steps marked *(mechanical)* change nothing the
author sees and can be approved together (REVIEW.md §7).  Letters are the bug classes of REVIEW.md §3.

- [ ] 3. What is left of the bug classes (REVIEW.md §3): the fuzzers of 3.3 (the FIT fuzzer's level 2 with libFuzzer, which
      needs clang; fuzzers for the xlsx and zip readers and the `bits` decoder).  Classes A to L are done
      (HISTORY.md, 2026-11-08).
- [ ] 8. Packages: the design is PACKAGES.md.  Done on 2026-11-09 (8.1 to 8.4): the inventory, `core`, the generated
      registry, the import checker, inferred table ownership, every module a package, the four cycles broken, every
      command a package.  Left: 8.5 the extension points that remain (import steps, on-demand work; and how a later
      package adds criteria to `activities`, see below); 8.6 the access model (SQLite's authorizer: report-only, then
      writes, then reads; the SQL-reads check that is a hand-run text scan now); 8.7 the schema-by-several-orders test, a
      README in each package, the fragments from the registry instead of `modules.nim` (which then goes, with
      `allowLegacy` in the import checker).  Your database must be made again (`nch db --delete -f`): the landmark
      fragment moved into `names`.
- [ ] 9. Options carry their help; parse into variants.
- [ ] 10. Tab completion (dynamic values from the database).
- [ ] 11. *(mechanical)* One owner per fact (REVIEW.md 4.1).
- [ ] 12. Push work into SQL (REVIEW.md 4.4), measured.
- [ ] 13. Shrink (REVIEW.md 4.7) (mechanical, except one cache naming scheme).
- [ ] 14. Larger changes: the `sectors` package; per-second data as arrays per activity, with cleaning at import;
      a simplified `route`; the cache manifest.

## Criteria from other packages (decided 2026-11-09, while splitting `selection`)

`nch activities --climb TEXT` selects activities by the climbs they went up, so the search language has to know the
`effort` table of `climbs`; and `climbs` reads the stored selection.  Until step 5 this is a recorded placeholder: the
search language (`criteria`, `ranges`) lives with the `activities` command, which depends on `climbs`, and the
stored selection (table, address bits) is a small package below both.  That is not extensible: a package added later
(training load from fitness/fatigue, weather, sleep) could not add an option to `activities` without editing the
command.  Two ways out, to be decided at step 5, after living with the packages:

* **Tags**: an activity has any number of tags (arbitrary strings, many to many; the user adds them by hand for
  equipment, "bike A"), and packages may add derived tags (climbs tags an activity with the climbs it went up; a load
  package with "load>100").  The selection language selects on tags and nothing else needs to know who made them.  No
  registry, and a feature in its own right.  Cost: derived tags duplicate what is stored elsewhere (`effort`), so they
  have a source (so that recomputing replaces only its own) and have to be kept in step when a climb is renamed,
  retired or renumbered (`climbs/work.nim` already runs once per activity and could write them in the same
  transaction); and tags cover membership-style criteria, not numeric or spatial ones.
* **A criteria extension point**: a package contributes an option (name, parse, a SQL predicate on `activity a`, help),
  and the command assembles its options from the contributions (needs the generic store in `core` and a field in
  `Globals`, as the import steps will).  Covers numeric criteria too.  Fits step 9 (options carry their help).

Either replaces the direct dependency of `activities` on `climbs`.

## Left over from the packages move (2026-11-09)

* `activitiescmd` imports `modules.nim` for `allImportSteps` (an old module, allowed while `allowLegacy` is on);
  step 5 (import steps as an extension point) removes it, and then `modules.nim` and `allowLegacy` go.
* Commands that write tables of a library themselves, to move into the libraries when the access model is built
  (`nimble`-run report: `python3 sqlrefs.py`, in the session scratchpad; it is a text scan, step 6 makes it exact):
  `userscmd` (`user`, `user_profile`), `activitiescmd` (`selection`); and `delete` (`activity`, `file`: the deletion
  of activities may belong in `importer`), `user` (`user`, which `db` owns).
* A check that the SQL reads of a package match its `depends` is a text scan done by hand so far (a script in the
  session scratchpad of 2026-11-09); make it a test, or let step 8.6 do it exactly.

## Open from before the review

To fit into the plan, or to do after it.  Details in HISTORY.md where noted.

* **Cleaning bad positions at import** (REVIEW.md class B, the part not done): drop or flag impossible fixes (a jump faster
  than any rider, a point far from its neighbours) once, at import, so that every consumer sees clean data.  Needs its own
  design (threshold, drop or flag, effect on stretches, climbs and efforts); it changes stored data.  Until then a stretch
  that spreads over more than 5 degrees is not searched for names (HISTORY.md, 2026-11-08).

* **Naming is slow** (11 s for 1,112 activities: 4.6 s reading 6.2 M `coords` rows as text, 6.2 s in
  `nameActivity`, not broken down; nothing shown meanwhile).  The author wants to go through how naming works
  first.  Steps 7 and 14 (typed reads, arrays) take most of the reading time away.
* **Features for later**: the elevation profile of a climb, the lead/lag comparison, the near-miss report,
  `exclude`, a way to retire many climbs (auto-retire of duplicates was tried and dropped: it retired long climbs
  into shorter near copies).  The "climbs vs sectors" question is answered by the `sectors` package.
* **Blue for the selection in `nch climbs`** (candidates: the `-v` attempts of selected rides; the latest/rank
  cells when the latest attempt is of a selected ride).  The author also asked whether "the selection chooses
  the climbs, never the attempts" is right; it is built that way.
* **The map**: labels, a legend, landmarks on the map, the page's palette from `packages/ui/palette.nim`, style rules by
  property (colour by sport or year), a plot command.
* **`ff`**: a form column (fitness minus fatigue); a switch between days and hours in the page.
* **A calendar of fitness** (HISTORY.md, Task 14): the `activities --calendar` grid with the background showing
  fitness, fatigue or form, each day in thirds.
* **A terrain model (SRTM)**: if added, smooth its heights (`climbs/profile.smoothed` is there for that).
* **Climb numbers**: a name renamed away from and then reused by a new climb can reuse the highest number.
* **Versions** (HISTORY.md, Task 11): when the version number changes; tie it to releases and the end of squashing.
* **Per-sport threshold heart rate and models**, if wanted.
* **The log**: level filtering (`--level warn`); the `saved` word is green for every use (low priority).
* **Light and dark terminal backgrounds** (`NCH_THEME`, else `COLORFGBG`; dim and yellow are poor on white).
