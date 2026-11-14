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
  declares the tables its frame reads.
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

### Step 2: subjects and keys (nothing visible)

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

### Step 4: caching, if measurement asks for it

* Measure as in step 0.  Agree a threshold with the author (D6); only frames slower than it are cached.
* A cached frame's file is named by its key: `frameKey(database identity, build, view/subject/frame, the selection's key
  if it reads the selection, tablesKey(its declared tables))`, first 16 hex digits; a file that is there is used.
* `nch cache` deletes the frames (files named by key pile up: a new key makes a new file and the old one is never read).
* Visible: faster, nothing else.  Rebuild: no.

### Step 5: `calendar` on frames

* `calendar` defines `calendar/frames` (a mark for each day); `activities` provides the activities frame; `calendar`
  loses its dependency on `activities` (`activities/rows.nim` stays with `activities`).
* Visible: none.  Rebuild: no.

### Step 6: the climbs subject

* Decision D4 first: what `nch climbs` lists (the climbs selection) and what that selection is after an import and when
  nothing has been selected.
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

## Decisions

D1 to D3 are decided; D4 to D6 wait for their steps (6, 7 and 4).

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
* **D4. The climbs selection** (step 6), above.
* **D5. FF statistics** (step 7), above.
* **D6. The threshold for caching** (step 4): agreed when the measurements are in.

## Risks

* **The triggers' cost on imports** (step 2): measured before going on; a counter on a table that takes millions of rows
  may need another way (the writer increasing it once per batch), which would be a departure from D1 to discuss.
* **The page with several files**: one fetch per frame; a slow or failed frame should not stop the others (the page says
  which failed).
* **Step 3 is the largest**: the code that moves is tested today through `map`; the tests move first, then the code.
