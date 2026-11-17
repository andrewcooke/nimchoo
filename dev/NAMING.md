# Naming activities with namers (design, 2026-11-17; not built)

Decided with the author on 2026-11-17, after an `/oppose` pass, then simplified.  Nothing here is implemented until the author
approves each step of the plan at the end.

## Why

A ride is often all about one big climb, so a ride's name cannot be made apart from the climbs; but climbs matter for
cycling (and running up hills), not for every sport (an indoor swim has no positions at all), so `importer` must not depend on
`climbs`.  A rule in `names` that named rides after hills they rose 100 m to was tried and dropped: that was climb detection
again, done worse (dev/HISTORY.md, 2026-11-17).

## The design

1. **A package `naming`**, above `importer` and `names`, below `climbs` and `activities` (which reads the names).  It owns the
   names: `activity.name` and `activity.start_place` move to a table of its own (the activity, the name, the start place), so
   `importer` only imports.
2. **Naming runs after the import** (`importer/after`) and names **every** activity that has no name (not only the new ones:
   an `--offline` run leaves some), and says why it could not (a download that failed), as the import does today.
3. **The point `naming/namers`.**  A namer is a name, a summary, a **precedence** (a number) and
   `propose(store, activity) → Option[name]`: a whole name, worded by the namer, or nothing.  Naming asks the namers in order of
   precedence and **the first that proposes a name wins**; nothing is weighed.  The namers, highest first:
   * **landmarks** (`naming`): the author's own places, as today;
   * **the big climb** (contributed by `climbs`): the ride's climb of category HC, 1 or 2;
   * **places** (`naming`): today's rules from GeoNames (`names/activity.nim`).

   So a big climb beats a town, and a landmark beats both.  A namer may say nothing for a ride it has nothing to say about (the
   big climb, for a swim).
4. **The shape and the wording are a library**, not part of the point: the shape of a ride (out-and-back, one-way, loop,
   local; its turning point: today's `names/shape.nim`) and the forms (`"X and back"`, `"to X"`, `"loop via X"`, `"around X"`,
   `"at X"`), for a namer to use if it needs them.  A namer for a sport with no positions (an indoor swim: the place and the
   distance) words its own.
5. **The big-climb namer**, in `climbs`: when first asked in a run it works out the climbs (`ensureClimbs`: every unlooked-at
   ride, in order of start time, so the catalogue does not depend on file order; nothing when all are done) and names them
   (`nameClimbs`, which may download), then proposes the ride's big climb, worded by its shape.  It proposes nothing from a
   climb with no proper name ("unnamed", "near …"): offline, the ride is named from the places.  (A namer that writes its own
   package's tables while proposing is allowed; naming is never run from a view.)
6. **Names are stored text**, made once.  A rule that changes is applied by the rebuild (about 18 s of import); a climb renamed
   by hand leaves the rides named after it as they were (none are, today; if it ever matters, `climbs` can ask `naming` to name
   those rides again).
7. **What reads the names**: `activities` (the table, `--names`, `--starts`) and `climbs/attempts.nim` read the new table;
   `importer/describe.nim` stops showing them (`importer` is below `naming`).

## Open, to settle with examples (step 2)

* Which climb names the ride when there are several big ones: the biggest, or the one at the turning point (no clear answer:
  look at the author's rides).
* The wording of a climb: "Farellones and back", "up Farellones"; and whether the subscript number ("Farellones₂") belongs in a
  ride's name.

## A plan of steps (each to be approved)

1. `naming` with the table, the point, the landmark and place namers and the after-import step; the names move out of
   `importer`; the readers read the new table.  Visible: none (the same names).  **Done 2026-11-17**: on a copy of the author's
   database, the 1,113 rides got the same names (3.1 s to name them all, against 2.6 s: each namer works out the shape).
   As built: `importer/describe.nim` never read the names (its callers pass them), so it is unchanged; the importer now
   runs the after-import steps on every import, even one that added nothing (each does nothing if it has nothing to do), and a
   step that fails makes the import's exit status 1.
2. The big-climb namer in `climbs`.  Visible: rides named after their big climb.  Look at examples before and after, with the
   author.
3. The squash and the rebuild of the author's database (TODO.md).
