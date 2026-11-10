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
3. **Packages, second round** (REVIEW.md §5 and §4.1, decided by the author and through `/oppose`).
   1. *(mechanical)* Done 2026-11-10 (`humanBytes` to `ui/units`; the eight commands into their packages).  Left of it: the
      `commands/` group and the `cmd` suffix go with `activitiescmd` (step 7); the import test's
      "a command module is imported only by its `package.nim`" still finds the module by its name, `command`: make it ask
      the registry (the module of `CommandDecl.run`).
   2. *(done 2026-11-10: `db_connector` is imported by `db` and `core/fragment.nim` only, checked by a test; `db` exports
      `DbConn`.)*  **Left, to be done just before 7**, when `--climb` is the first real
      contributor: an `Sql` records the packages that wrote its pieces (templates, as the helpers' `packageOfFile`); each
      table access of a read is allowed if the runner or any package of the set may make it, a write or a change of
      definition to the runner alone; a test prepares each contributed criterion as its contributor alone (REVIEW.md §4.1).
   6. Step 4's option type, for the criteria first (an option carries its help, value name and the words it takes;
      usage is generated): needed by the criteria point.
   7. `selection` becomes a library (no command) with the extension point "activity criteria" (an option and
      `resolve(store, user, values)` giving an `Sql` condition and notes, or an error); `climbs` contributes `--climb`.
      New packages: `activities` (`nch activities [CRITERIA] [--select] [--delete] [-v]`; "the new activities become the
      selection" after an import is `selection`'s, since it owns the table) and `calendar` (`nch calendar`: the selection or `--all`,
      no criteria).  `activitiescmd` goes.  Two packages contributing one option name are refused when the registry
      is made (as two commands of one name are).
   8. **`nch packages`**: a command built into `nch.nim` (a package cannot import the registry), its logic a pure
      function in `core` (`core/inventory.nim`, tested).  It shows the packages in dependency order with their
      `depends`, tables, fragments, commands, the extension points each defines and what each contributes (with the
      options a criterion adds); `--dot` writes the dependency graph for Graphviz.  Needs: the registry stamps each
      contribution with the package that made it; a package declares the points it defines in `package.nim`
      (`defines:`), and the registry refuses a contribution to a point nobody defines.  The registry's check for
      duplicate command names knows this one.
   9. Each package's documentation is the `##` comment of its `package.nim`; the registry writes the front page (the
      packages in order, with their first lines); the feature detail of CLAUDE.md moves into them; CLAUDE.md
      ("general structure", "the shape of the commands", the extension-point rule) and PACKAGES.md describe the result.
4. **Options carry their help; parse into variants** (A §7 step 9) for the other commands.  `Opt` gets `help`,
   `metavar` and a completion kind; usage generated; the web options from the same spec; errors as `Option`, not "".
5. **Tab completion** (A step 10): `nch __complete` and a bash function; dynamic values from the database.
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
