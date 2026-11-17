# A plan of migration to the display architecture (2026-11-14)

How to get from today's display (pinned addresses; `map` making every layer itself) to the one in `display-arch.md`
(live views; subjects with selections; frames from providers).  Written by the assistant from the design, its critiques
(`display-arch-crit*.md`, the last with no deal breakers) and the decisions below.  **Nothing is implemented until the
author approves**, step by step.

## The decisions it starts from

* **Live views.**  A view shows the current selection of its subject; a bookmark keeps the look, not the data.  The
  pinning goes (`--selection`, `--state`, `bits`, the redirect, the proquint names).
* **The page by default, `--file` for the files.**  `nch map` serves and opens the page (today's `--web`); `nch map --file`
  writes the files to the cache and prints their paths.
* **A registry of subjects**: one extension point, read by every view, to which the package that manages a subject
  contributes it.  Activities is the default subject.  (The registry of frame formats is later.)
* **Views below subjects** in the package order.  A view defines the point its frames are contributed to; the packages that
  manage subjects (`activities`, `climbs`) provide the frames, not the packages beneath them (`importer`).
* **`nch climbs` becomes like `nch activities`**: it manages a selection of climbs.
* **Keys**: SHA-256 of the parts in a fixed order; every key has the database's identity, the build and the frame's name;
  the data are keyed by **one counter per table**, increased by triggers on insert, update and delete.  A provider
  declares the tables its frame reads.  (Built in step 2; the keys and counters were removed in step 4, 2026-11-16, when
  measurement showed nothing needs caching.  The declared tables stay.)
* **Caching after measuring**: frames are made on every request until a measurement says otherwise.
* `calendar --all` is dropped now; "all, with the selection marked" across views is later.

## What it will look like

* **`subject`**, a new small package (depends on `db`, `hashing`, `user`):
  * the point `subject/subjects`: a `Subject` is a name, a summary, whether it is the default, and `selectionKey(Session)`
    (the key of the current selection: for activities, the SHA-256 of the user and the sorted ids);
  * `keys.nim`: the key of a frame from its parts (`frameKey`), the key of a set of tables (`tablesKey`: their counters),
    the database's identity, the build's identity.
* **`db`** gains, in a fragment, `database_identity` (one row: random, made when the database is created) and
  `table_version` (name, version), and the triggers that keep it (decision D1).
* **Each view** (`map`, `calendar`, later the plot view) depends on `subject`, `web`, `ui`, `cache` and the like, never on a
  data package, and defines its point of frames: `map/frames` holds a `MapFrame` (name, subject, summary, shown by
  default or not, whether it reads the selection, the tables it reads, the GeoJSON it makes, its style template).
* **Providers**: `activities` contributes the activities subject, and the frames `routes` and `heat` (and later a global
  heat map); `climbs` contributes the frames `climbs`, `gates` and `efforts` for activities, and later the climbs subject
  and its frames.
* **Commands**: `nch map [SUBJECT] [--frames FRAME...] [--file]`, `nch calendar [SUBJECT]`.  The address of a page is
  `/map/SUBJECT?frames=a,b` (decision D2).

## For whoever implements this

* **One step at a time, with the author's approval for each** (CLAUDE.md: no switching from discussion to implementation
  without it).  At the end of a step, report what was done and what was measured, and stop.
* **Stop and ask, rather than work round**, when: a measurement is bad (the triggers' cost on imports, step 2); the code
  does not match what this plan says (the plan was written from a reading of the code, and names of functions, files and
  dependencies may be slightly off: check them, and say when one is wrong); a step needs a decision that is not here
  (D4 to D6 are the author's).
* **The measurements of step 0 are taken with today's `./nch`**, before anything changes, on the author's database (ask
  where it is; /tmp is RAM, so at most one copy of the database there).
* **Read first**: `display-arch.md` (the design), `display-arch-crit-6.md` (the last critique: what holds up, the rules
  of keys, why the deal breakers are not), and the `##` documentation of the packages a step touches.
* **Suggest a review after step 3** (the largest step), in a fresh session, before steps 4 to 7: each step can be right
  while the whole drifts.

## The steps

Each step is one or a few commits, each with its tests passing, its documentation updated (the `##` of the packages it
touches, `CLAUDE.md`, `TODO.md`, `dev/HISTORY.md`: grep the names changed), dead code deleted, `nimble fmt`, no compiler
warnings, `./nch` rebuilt with `nimble prod`, pushed.  "Visible" says what the author will see change; "rebuild" whether
the database must be made again.

### Step 0: before starting

* Commit `dev/display-arch/` (the author's design and the critiques).  `CLAUDE.md`, "where things are": add the directory.
* `TODO.md`: one item pointing at this plan; delete the items it replaces ("Addresses, what is left"; "`map` criteria of its
  own").  `dev/MAP-LAYERS.md` is superseded (decision D3).
* **Measure the baseline** (for step 4): the time of `nch map --file` on the author's database, cold and warm, for a few
  selections (one ride, a month, everything) and each layer, and the size of the files.  Recorded in `dev/HISTORY.md`.

### Step 1: live addresses (deletion)

1a. **The pinning goes.**
  * `map`: `--selection`, `--state` and the `Target` variant go; it always draws the selection.  The inputs and the state
    (`inputsOf`, `stateOf`) and their test ("each table it reads changes the state") go: keys come back in step 4 in their
    new form.
  * `ff`: `--state` and the defaults spelled out in the address go.
  * `web`: the redirect to the pinned address, `stateParam` and the worker's third line go; the worker prints the page's
    path and the data's.  The fuzz tests lose the cases about the state.
  * `selection`: `bits.nim`, `ownedIds`, `maxActivityId`, `contentKey`, `keyOf` and their tests (`test_bits`, `test_fuzz`)
    go; its documentation loses the addresses.  `importer/keys.nim` (`routesKey`) goes.
  * `cache`: `requestStem`, `stateKey` go, and the package `text/proquint`, which only they use.
  * Files are named by the command and its options (`map-routes-climbs.geojson`) and made again on every request.
  * Visible: a bookmark shows the current selection; an old bookmark with `state=` is refused (an unknown option).
    Rebuild: no.
1b. **The default swapped.**  `web/webopts.nim`: the page is the default; `--file` (make the files, print their paths)
  replaces `--web`, for `map` and `ff`; `--worker`, `--no-open`, `--port`, `--new-token` stay.  `ff --stdout` stays until
  the text view.  Usage, completion and the help texts follow from the specs.  Visible: `nch map` opens the page.
1c. **`calendar --all` goes** (and the drawing of the selection in blue among all activities).

### Step 2: subjects and keys (nothing visible; the keys were removed in step 4)

* `db`: the fragment with `database_identity` and `table_version`, and the triggers (D1).  **Measure the import** before
  and after (the triggers fire per row, and `route_cell` and `track` take many rows): if the cost is large, say so and
  look at it together before going on.
* `db/access.nim`: a way to record the tables a block of code reads (the authorizer already sees each one), for tests.
* The package `subject`: the point, `frameKey`, `tablesKey`, the database's identity, the build's identity (the compile
  time with the version and commit, so that a rebuild of uncommitted code is a new build).
* `activities` contributes the activities subject (the default).
* Tests: every table any package owns has a counter that changes on insert, update and delete (one test over the list of
  tables in `core/ownership.nim`, so that a new table cannot be missed); two new databases have different identities; a
  key changes with each of its parts; the parts never cancel (a frame whose two parts are equal).
* `nch packages --points` shows the new point.  Rebuild: yes (a new fragment).

### Step 3: `map` on frames

* `map` defines `map/frames`; `nch map [SUBJECT] [--frames FRAME...]` (the subject from the registry, activities when it
  is left out; the frames of that subject, those marked as the default when `--frames` is not given).  One file per frame
  (`map-activities-routes.geojson`), made again on every request; `--file` prints their paths.
* The code moves: `routesOf` and `heatOf` to `activities` (`activities/mapframes.nim`), `climbsOf`, `gatesOf`,
  `effortsOf` to `climbs` (`climbs/mapframes.nim`); what writes GeoJSON features stays in `map/lines.nim` as a library for
  the providers.  `map` loses its dependencies on `climbs`, `importer`, `geo`, `selection`, `fit`, `hashing`.  The tests
  move with the code (`tests/map/test_command.nim` splits).
* **Styles**: `map-style.json` splits into one template per frame, shipped by its provider (`activities-map-routes.json`
  ...), unpacked to `system/templates/` like today's and editable there; the page gets the list of frames (file and style)
  and draws each with its own style.  `map.html` and `map.css` stay with `map`.
* **The address**: `/map/activities?frames=routes,climbs` (D2): `web/request.nim` routes by the first part of the path
  and passes the second as the subject; fuzzed as now.
* **One request per page**: the page's request makes all the frames, so a selection changing while it loads cannot mix two.
* Each provider declares the tables its frame reads; a test makes each frame with the authorizer recording and checks the
  declaration holds every table read.  A test registers a frame from a test-only provider, to show `map` needs nothing of
  the packages above it.
* Completion: `--frames` offers the frames (of the subject typed, if any); the subject offers the registered subjects.
* Visible: `--layers` is `--frames`; the map looks the same.  Rebuild: no.
* 3b (optional, any time after): **a global heat map** frame from `activities` that reads no selection.

### Step 3c: the fixes from the review after step 3

From `review-after-step-3-findings.md` (2026-11-14; the numbers are its findings).  Before step 4, because the keys and the
one read transaction need the first.

* **Frames do not write** (2): the climbs frames stop calling `ensureClimbs` (the import works the climbs out); a frame that
  finds activities whose climbs are not worked out says so in a note.  Then all the frames of a map are made in **one read
  transaction**.  (If the author prefers the map to keep working out climbs: an optional `prepare` on `MapFrame`, run for
  all the chosen frames before the transaction.)
* **The declarations** (3): `climbTables` holds what the frames read (it shrinks once they do not write; else it gains
  `route_cell`), and the recording ignores SpatiaLite's `spatial_ref_sys` as it ignores the `idx_` tables.
* **An empty frame is a note, not a failure** (5): a selection with no routes still draws the other frames; the check that
  the selection is not empty only when a chosen frame reads it.
* **Registry tests** (6): every frame's subject is a registered subject, frame names are unique within a subject, and
  style groups do not collide.
* **The tidy** (7, 8): the dead `Prepared` in `map/command.nim`; `choose` returns a parsed value, not `""` for "fine";
  `fmt` in the new messages; `db` out of `map`'s `depends`; the insert of `db/versions.nim` binds its value; "1 of the 3
  activities have"; `NOTICE` (`nch heatmap --web`), the comment in `page.html` on `map-style.json`, "newer than" in the
  documentation of `map/command.nim`.
* Visible: a map with an empty frame draws the rest.  Rebuild: no.

### Step 4: no caching (decided 2026-11-16)

* Done: routes are simplified with `Simplify`, not `SimplifyPreserveTopology` (the routes of everything: 4.45 s to 0.51 s,
  dev/HISTORY.md).  With that, no frame in use is slow enough to cache.
* **Decided: no cache, and no keys.**  Every frame's file has a fixed name (`map-activities-routes.geojson`) and is overwritten
  on every request, so there is nothing to clean out.  The keyed names (`3d764ec`) were reverted, and the keys of step 2 (the
  counters of tables and their triggers, `database_identity`, `subject/keys`, `Subject.selectionKey`, `nchBuild`) were deleted:
  nothing used them.  Kept: each frame's declared `tables` and the test that checks them (`db/access` recording), as
  documentation, until they feel like dead wood.
* **Accepted**: a page fetches its files after the worker made them, so a second request in between (another tab, a reload
  with other frames, `nch map --file`) can give it one frame of newer data (review finding 4).  For one user this is rare
  and a reload fixes it.
* If caching is ever wanted, see "Later".

### Step 5: `calendar` on frames

* `calendar` defines `calendar/frames` (a mark for each day); `activities` provides the activities frame; `calendar`
  loses its dependency on `activities` (`activities/rows.nim` stays with `activities`).
* Visible: none.  Rebuild: no.
* Done 2026-11-16.  As built: `nch calendar [SUBJECT] [-v]`; a subject has at most one calendar frame (a day is marked or not,
  so two would have nothing to tell them apart), and the frame gives the instants to mark and the last line (the activities':
  "done: 35 activities, ..."), so the calendar knows nothing of activities.  The output is byte for byte the same on the
  author's database; what differs is the usage (the subject, and the subjects that have a calendar) and the empty selection's
  message, now the subject's own.  The subject is not completed by tab (as for `map`).

### Step 6: the climbs subject

* **A design choice first** (review finding 1): the page script (`map/page.html`) and `map/lines.nim` still know every kind
  of frame (route, climb, heat, effort, gate) and read each provider's style by name, so a new frame means editing `map`.
  Options: (a) each provider ships its drawing, a script template beside its style, and `lines.nim`'s types move to the
  providers; (b) a declarative style the page draws generically; (c) keep it and document that a new frame edits `map`.
  **Decided (2026-11-17, D7): (a) for now, with an eye to (b).**  See "6a" below.
* **6a. Providers draw their frames** (before the climbs subject; nothing visible):
  * `map`'s page becomes a host: Leaflet and the tiles, the fetch of each frame's file (one that fails is reported, the rest
    drawn), fitting the view, the line saying what is drawn, and generic helpers (moving a line sideways in metres or pixels,
    the corner cutting, panes for what is drawn underneath).  It calls each frame's `draw(map, features, style, shared)`.
  * A frame ships a script template beside its style (`activities-map-routes.js`), unpacked to `system/templates/` and
    editable there like the others.  The page gets only the drawn frames' styles and scripts, **each under the frame's own
    name** (`activities/routes`), so there is no shared namespace of groups and two frames may use the same group names.
  * Frames that depend on each other say so through `shared`: the routes publish their spread, the climbs read it (with a
    fallback when no routes are drawn).  Frames are drawn in the order of `--frames` (else of contribution).
  * `lines.nim`'s types and writers go to their providers (routes and heat to `activities`; climbs, gates, efforts to
    `climbs`); `map` loses `fit` and `geo`.  A climbs-subject frame may reuse another provider's script and style bundle.
  * **Towards (b)**: the script is optional.  A frame without one is drawn by a generic drawer of `map` from its style alone
    (lines, points or polygons: colour, width, opacity), so a simple new frame needs no JavaScript; when the scripts
    show the same pattern twice, it moves into the helpers or the generic drawer.  (b) is then the generic drawer
    growing until most frames need no script, never a rewrite.
  * Tests: the page with a frame of a test-only provider and its own script (that `map` needs nothing above it, in JS too);
    a frame without a script drawn generically; `tools/pagecheck.js` for the real frames.
  * Done 2026-11-17.  As built: the drawing is a script template holding one function `(features, ctx) => {...}` (the page
    names it after its file, so one drawing can serve several frames); layers go in with `ctx.add(layer, z)` and the page adds
    them in order of `z` (climbs 10, routes 20, efforts 30, gates 40, generic 50; the heat has a pane of its own); a drawing
    returns `{ bounds, rank, caption, update }`; the contract is in `map/frames.nim`.  The page shows the same captions and
    the same view as before on the author's data (`tools/pagecheck.js`, which now takes the worker's output and prints the
    view); what differs: the caption follows the order of `--frames`, climbs alone fit the view to the climbs (before: the
    whole world), and a frame whose drawing fails is reported and the others drawn.
* Decision D4 (decided 2026-11-17, below): `nch climbs` lists the climbs selection; an import makes the climbs of the activities
  it imported the climbs selection.
* A selection of climbs (a table of `climbs`, per user, like `selection`); `nch climbs` with criteria and `--select`, like
  `nch activities`; the climbs subject in the registry.
* Frames for the climbs subject on the map: the selected climbs; the routes of the activities that went up them (the
  inverted case, provided by `climbs`, declaring the activity tables it reads).
* What `nch climbs` lists today (the climbs of the selected activities) becomes a frame (climbs for activities), shown by
  a view.
* Rebuild: yes (a new table).

### Step 7: FF statistics (after a design note)

* A design note first, with the author: which statistics, what selecting them means, which command does it (D5).
* Then: the FF subject; a plot view (`plot`, the point `plot/frames`: series) replacing `ff`'s page; `ff`'s CSV moves to
  `plot --file` or, later, the text view; the calendar of fitness becomes an FF frame on the calendar.

### Later

* "All, with the selection marked" as a frame across views.
* The registry of frame formats, when two views share one (the text view and the calendar; the text view and the plot).
* The text view, perhaps replacing `--file`.
* **Caching frames**, if a frame in use becomes slow (over about a second): the design of step 2 and the old step 4 (keys of
  SHA-256 over the database's identity, the build, the frame's name, the selection's key and per-table counters kept by
  triggers; files named by key; `nch cache` clears them) is in this file's history (`git log -p dev/display-arch/plan.md`)
  and in `display-arch-crit-6.md`.  Also cheaper first: a table of simplified routes made at import (dev/HISTORY.md,
  2026-11-16).

## Decisions

D1 to D4 and D7 are decided; D5 waits for its step (7); D6 is moot (no caching).

* **D1. How the counters' triggers are made.**  (a) Each package writes them in a fragment for each of its tables: three
  triggers per table, about twenty tables, kept in step with the tables by hand.  (b) The `db` package makes them for every
  table in the list of owned tables (`core/ownership.nim`) after it applies fragments, so a new table gets them without
  anyone writing them; they are schema not written in a fragment.  **Decided (2026-11-14): (b)**, by the rule "one fact,
  one place" (the list of tables is the fact).
* **D2. The address of a view of a subject.**  (a) `/map/climbs?frames=...`, mirroring `nch map climbs --frames ...`;
  (b) `/map?subject=climbs&frames=...`, which needs no change to the routing but makes the subject an option in the
  address and not on the command line.  **Decided (2026-11-14): (a).**
* **D3. `dev/MAP-LAYERS.md`.**  Its ideas are set aside or superseded, and its useful finding (names are not identities) is
  settled (`name_n`).  **Decided (2026-11-14): delete it**, with a line in `dev/HISTORY.md`, in step 0.
* **D4. The climbs selection** (step 6): decided 2026-11-17: `nch climbs` with no arguments lists the climbs selection (as
  `nch activities` lists the activities'); an import makes the climbs of the activities it imported the climbs selection
  (as it makes them the activities' selection).
* **D5. FF statistics** (step 7), above.
* **D6. The threshold for caching** (step 4): moot, decided 2026-11-16: nothing is cached.
* **D7. How frames are drawn** (step 6): decided 2026-11-17: each provider ships its drawing (a script beside its style),
  with an optional generic drawer in `map` that may grow into a declarative style (b) later.  Step 6a.

## Risks

* **The triggers' cost on imports** (step 2): measured before going on; a counter on a table that takes millions of rows
  may need another way (the writer increasing it once per batch), which would be a departure from D1 to discuss.
* **The page with several files**: one fetch per frame; a slow or failed frame should not stop the others (the page says
  which failed).
* **Step 3 is the largest**: the code that moves is tested today through `map`; the tests move first, then the code.
