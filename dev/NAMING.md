# Naming activities with namers (design, 2026-11-17; not built)

Decided with the author on 2026-11-17, after an `/oppose` pass.  Nothing here is implemented until the author approves the
plan of steps (at the end), step by step.

## Why

A ride is often all about one big climb, so a ride's name cannot be made apart from the climbs; but climbs matter for
cycling (and running up hills), not for every sport (an indoor swim has no positions at all), so `importer` must not depend on
`climbs`.  A rule in `names` that named rides after hills they rose 100 m to was tried and dropped: that was climb detection
again, done worse (dev/HISTORY.md, 2026-11-17).

## The design

1. **A package `naming`**, above `importer` and `names`, below `climbs` (and `activities`, which reads the names).  It owns the
   names: `activity.name` and `activity.start_place` move to a table of its own (`activity_name`: the activity, the name, the
   start place, the namer that gave it, and the version of the rules), so `importer` only imports.  A rules version means a
   change of rules names every ride again, as `climbs_done` does for climbs.
2. **Naming runs after the import** (`importer/after`), and names **every** activity with no name (not only the new ones: an
   `--offline` run leaves some), and says why it could not (a download that failed), as the import does today.
3. **The point `naming/namers`.**  A namer is a name, a summary and `propose(store, activity, shape) → proposals`.  A proposal is
   **a whole name** (the namer words it) and **a level** from a small scale that `naming` defines and documents, so that namers
   that do not know each other can be weighed: roughly "the author's own" (a landmark), "the point of the ride" (a big climb, a
   destination), "a feature on the way", "a region" (the exact levels to be settled with examples).  The highest level wins; a
   tie goes to the namer listed first.  A namer may say nothing (the cycling namer for a swim).
4. **`naming` computes the shape once** (out-and-back, one-way, loop, local; the turning point and the furthest distance:
   today's `names/shape.nim`) and gives it to every namer, with the wording as a library (`"X and back"`, `"to X"`,
   `"loop via X"`, `"around X"`, `"at X"`), so namers word names the same way without having to.  A namer for a sport with no
   positions (an indoor swim: a name from the place and the distance) words its own.
5. **The generic namer** is in `naming`: places and landmarks, today's rules (`names/activity.nim`) as proposals.  `names`
   stays the library of places (it is below `importer`, so it cannot contribute to a point above it).
6. **The cycling namer** is contributed by `climbs`.  When first asked in a run it works out the climbs (`ensureClimbs`: every
   unlooked-at ride, in order of start time, so the catalogue does not depend on file order; nothing when all are done) and
   names them (`nameClimbs`, which may download), then proposes the ride's **big climb** (category HC, 1 or 2) as "the point of
   the ride".  It proposes nothing from a climb that has no proper name ("unnamed", "near …"): offline, the ride falls back to
   the places.  It writes its own package's tables while proposing; the point's documentation says a namer may, and that
   naming is never run from a view.
7. **Names are stored text.**  A climb renamed later (`nch climbs --edit … --rename`, or a new number) leaves the rides named
   after it stale; `climbs` (above `naming`) asks `naming` to name those rides again after a rename (the rides with an effort on
   that climb whose name came from the cycling namer).
8. **What reads the names**: `activities` (the table, `--names`, `--starts`) and `climbs/attempts.nim` join the new table;
   `importer/describe.nim` stops showing them (`importer` is below `naming`).

## Open, to settle with examples

* Which climb names the ride when there are several big ones: the biggest, or the one at the turning point (no clear answer:
  look at the author's rides).
* The levels of the scale, and how a big climb compares with a landmark and with a destination town.
* The wording of a climb: "Farellones and back", "up Farellones"; and whether the subscript number ("Farellones₂") belongs in
  a ride's name.
* Whether a ride must be named again when a later ride finds a big climb it also went up (the author thinks rarely: mostly
  rides whose files have no altitude).

## A plan of steps (to be approved)

1. `naming` with the table, the point, the generic namer and the after-import step; the names move out of `importer`; the
   readers join the new table.  Visible: none (the same names).  Rebuild: the next squash folds the move.
2. The cycling namer in `climbs`, and the renaming after a climb's rename.  Visible: rides named after their big climb.
   Look at examples before and after, with the author.
3. The squash and the rebuild of the author's database (TODO.md), after these.
