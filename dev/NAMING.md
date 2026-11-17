# Naming activities with namers (tried 2026-11-17, and reverted)

**Read this before trying again.**  The idea: a ride is often all about one big climb, so name rides after their climbs, by
taking naming out of the importer into a package `naming` that asks "namers" (landmarks, the ride's big climb from `climbs`,
places).  Step 1 (the package, the same names) was built (`d69a9fe`) and reverted (`ba513a4`) the same day, because of what
the examples showed:

* **Climb names are poor ride names.**  Of the 124 rides with an effort on a big climb (category HC, 1 or 2; 20 such climbs),
  the author preferred today's names (from the places) for all but one: "Corral Quemado and back" (35 rides) would have been
  "Cometierra₂ and back", "Farellones and back" (31) "Corral Quemado₇ and back", "La Ermita and back" (10) "Cometierra₂ and
  back".  The one better name was "Cuesta de Chacabuco and back" (1 ride).
* **Why**: a climb is named from whatever GeoNames has near its top, or near its middle when nothing is near the top
  (`names/climbpick.nim`), so most of the 20 big climbs are named after sections of town (`PPLX`: Farellones, Corral Quemado,
  Cometierra), localities or hills, some 2 to 5 km from the top.  Only one (Cuesta de Chacabuco) is named from a pass, the kind
  of feature that names a climb as a rider would.  So a namer that used only "good" climb names would have used one; one that
  used names given by hand would need the author to name the climbs first.
* **The case that started it** (Cerro San Cristóbal names none of the 98 rides over its summit: GeoNames has it as `HLL`, which
  no rule ranks, and sections of the town outrank the park) is an exception, and a **landmark** is the tool for it.
* **Before that**, a rule naming a ride after a hill it rose 100 m to reach (by its own altitudes) was tried and dropped:
  climb detection again, done worse; and naming after any summit within 250 m named three English rides after "How Hill".
* Step 1 cost about 0.5 s more to name all 1,113 rides (3.1 s against 2.6 s) and an extension point with no other use.

**What would make it worth trying again**: climbs with good names (named by hand, `nch climbs --edit … --rename`, or a data
source that names climbs as riders do).  Then the plan below, with the namer proposing only climbs named by hand, and the
rides renamed when a climb is renamed, is a few hours' work; the code of step 1 is in `d69a9fe`.

The design as it stood:

### Why

A ride is often all about one big climb, so a ride's name cannot be made apart from the climbs; but climbs matter for
cycling (and running up hills), not for every sport (an indoor swim has no positions at all), so `importer` must not depend on
`climbs`.  A rule in `names` that named rides after hills they rose 100 m to was tried and dropped: that was climb detection
again, done worse (dev/HISTORY.md, 2026-11-17).

### The design

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

### Open, to settle with examples (step 2)

* Which climb names the ride when there are several big ones: the biggest, or the one at the turning point (no clear answer:
  look at the author's rides).
* The wording of a climb: "Farellones and back", "up Farellones"; and whether the subscript number ("Farellones₂") belongs in a
  ride's name.

### A plan of steps

1. `naming` with the table, the point, the landmark and place namers and the after-import step; the names move out of
   `importer`; the readers read the new table.  Visible: none (the same names).
2. The big-climb namer in `climbs`.  Visible: rides named after their big climb.  Look at examples before and after, with the
   author.
3. The squash and the rebuild of the author's database (TODO.md).
