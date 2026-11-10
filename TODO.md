# TODO

Open work only.  Finished work is in git and in HISTORY.md (with the reasoning behind decisions).  The plan below is
from the second review (REVIEW.md, 2026-11-09); the first review (2026-11-08) is its appendix A, and "A §3" etc. refer
to that.  When something here is done, delete it (in the same commit).

Design steps are discussed with the author before they start; steps marked *(mechanical)* change nothing the author
sees and can be approved together.

## Now: the plan of the second review

1. **Fuzzing** (REVIEW.md §3; the author: before the packages).
   1. Show that the FIT fuzzer finds a bug: a guard of class L removed in a scratch copy must be found with the default
      rounds; record the result in HISTORY.md.  If not, improve the mutator first.
   2. The importer's `readActivities` fuzzed with the same mutations (with and without `heart_rate`); one or two large
      real files with fewer rounds.
   3. Level-1 fuzzers for `decodeBits`, the xlsx and zip readers (damaged `Profile.xlsx`), and `parseTarget`.
   4. Failures saved under `tests/data/fuzz/<target>/`, replayed by a test.
   5. Level 2: libFuzzer harnesses in `tests/fuzz/`, `nimble fuzz TARGET [SECONDS]` (clang, `--panics:on`,
      `-d:useMalloc`, `-fsanitize=fuzzer,address`, and `--gcc-install-dir` set to the GCC that has `libstdc++.so`:
      clang chooses GCC 16, which lacks it).  One hour per target; fix what it finds (a test first), record the rest.
2. *(mechanical)* **Tools** (REVIEW.md §7).
   1. nph: a Claude Code hook that formats a `.nim` file after each edit (`.claude/settings.json`, PostToolUse on Edit
      and Write; the script would be `tools/fmt-hook.sh`, reading the file from the hook's JSON with `jq`).  Blocked
      2026-11-10: the permission classifier refuses me editing my own hooks; the author adds it.
   2. nim doc: `nimble doc` (to a git-ignored `doc/`, no warnings); the RST error in `nch.nim` and the two broken
      links fixed.
   3. Small drift: `cmdname.nim` without `{.push raises: [].}`; `db/sqltext.nim`'s header (the `?` text); PACKAGES.md
      "What is built and what is left".
3. **Packages, second round** (REVIEW.md §5 and §4.1, decided by the author and through `/oppose`).
   1. *(mechanical)* `humanBytes` moves from `download/fetch` to `ui/units`.  Then the commands with no cycle go into
      their packages: `fit`, `climbs`, `landmarks` (into `names`), `models` (into `model`), `cache`, `db`; `log`, `map`
      and `ff` become packages of their own.  The `commands/` group and the `cmd` suffix go; tests move with them; the
      import test keeps "a command module (the module of `CommandDecl.run`, from the registry) is imported only by its
      `package.nim`".
   2. An `Sql` records the packages that wrote its pieces (templates, as the helpers' `packageOfFile`); a read is
      allowed to the runner or any package of the set, a write or a change of definition to the runner alone; a test
      prepares each contributed criterion as its contributor alone (REVIEW.md §4.1).  `db_connector` imported in `db`
      only; `db` re-exports the types it hands out (§4.2).
   3. `user` owns the `user` table: `openStore` only opens and applies fragments; `user/openSession` finds or makes
      the user; commands use it; `importer` and `selection` depend on `user` (§4.3).  `nch users` goes into `user`,
      with the extension point "what a user has" (`importer` contributes the activity count; the FTHR-change note
      becomes generic and `model` contributes nothing).
   4. The extension point "pages the server may run" in `web`; `map` and `ff` contribute; `commandRules` goes.
   5. `nch import PATH...` is a command of `importer` (this reverses CLAUDE.md's "no import command": update "the
      shape of the commands"), with the extension point "after import" (once per import, after the commit; a failure
      is a warning).
   6. Step 4's option type, for the criteria first (an option carries its help, value name and the words it takes;
      usage is generated): needed by the criteria point.
   7. `selection` becomes a library (no command) with the extension point "activity criteria" (an option and
      `resolve(store, user, values)` giving an `Sql` condition and notes, or an error); `climbs` contributes `--climb`.
      New packages: `activities` (`nch activities [CRITERIA] [--select] [--delete] [-v]`; contributes "the new
      activities become the selection" to "after import") and `calendar` (`nch calendar`: the selection or `--all`,
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
