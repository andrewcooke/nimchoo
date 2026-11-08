# TODO

Open work only.  Finished work is in git and in HISTORY.md (with the reasoning behind decisions); the review of
2026-11-08 and its plan are in REVIEW.md.  When something here is done, delete it (in the same commit).

## Now: the review plan (REVIEW.md §7)

Design steps are discussed with the author before they start; steps marked *(mechanical)* change nothing the
author sees and can be approved together (REVIEW.md §7).  Letters are the bug classes of REVIEW.md §3.

- [ ] 3. Fix the bug classes D-H, J-L (the abstraction, a test for the class, the known bugs as first cases).  A, B and C are done
      (HISTORY.md, 2026-11-08).
      Still open from
      3.3: the FIT fuzzer's level 2 (libFuzzer), and fuzzers for the xlsx and zip readers and the `bits` decoder.
- [ ] 4. *(mechanical)* The other reported bugs (REVIEW.md §3.2): confirm with a test, fix the real ones.
- [ ] 5. *(mechanical)* Check the conventions in CLAUDE.md against the code (moved there from the old TODO.md, corrected by hand
      without a full check).
- [ ] 6. *(mechanical)* Dead code (REVIEW.md 4.3, 4.7).
- [ ] 7. Typed database access (evaluate `tiny_sqlite` first); the `fold()` SQL function (I); the query-plan test.
- [ ] 8. Packages (REVIEW.md §6), in its six sub-steps (8.1, 8.3, 8.4, 8.6 mechanical); feature detail moves from CLAUDE.md to each package's doc.
- [ ] 9. Options carry their help; parse into variants.
- [ ] 10. Tab completion (dynamic values from the database).
- [ ] 11. *(mechanical)* One owner per fact (REVIEW.md 4.1).
- [ ] 12. Push work into SQL (REVIEW.md 4.4), measured.
- [ ] 13. Shrink (REVIEW.md 4.7) (mechanical, except one cache naming scheme).
- [ ] 14. Larger changes: the `sectors` package; per-second data as arrays per activity, with cleaning at import;
      a simplified `route`; the cache manifest.

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
* **The map**: labels, a legend, landmarks on the map, the page's palette from `ui/palette.nim`, style rules by
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
