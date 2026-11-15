# The review after step 3: findings (2026-11-14)

The review asked for by `plan.md` and briefed in `review-after-step-3.md`, done in a fresh session.  No code was changed.
State reviewed: `fc7d003`.  `nimble test` passes (0 failures, no compiler warnings).  The checks on real data were made on
a copy of the author's database (1,113 activities) in the scratchpad, since deleted, with a throw-away program that makes
every frame with the authorizer recording.

## Verdict

Steps 0 to 3 are close to the plan and the Nim side holds: `map` imports nothing above it, the counters work and cost
nothing on reads, keys are sound.  The drift is in two places the Nim dependency checks cannot see: **the page script and
`map/lines.nim` still know every kind of data**, and **the climbs frames write to the database**.  Both will matter in
step 4 or step 6.  The real-data check also found one under-declared frame.

## Findings, most important first

1. **`map` still knows every frame, in JavaScript and in `lines.nim`.**  `map/page.html` filters by
   `kind === 'route' | 'climb' | 'heat' | 'effort' | 'gate'` and reads `style.routes`, `style.climbs`, `style.heat`,
   `style.efforts`, `style.gates` by name (lines 32-315).  `map/lines.nim` defines `Route`, `Climb`, `HeatCell`,
   `GateLine` and `EffortLine`, with a `featureCollection(routes, climbs, heat, gates, efforts)`.  This is why `map` still
   depends on `fit` and `geo`.  So the map package doc's "a new subject or frame is a package that contributes, and nothing
   here changes" is true only for Nim.  A new frame (step 6: the selected climbs, the routes of activities on climbs; 3b:
   a global heat map) needs `page.html` and `lines.nim` edited.  `tests/support/testframes.nim` shows that `map` needs
   nothing above it, but the page would not draw that frame's features.  The coupling also runs between frames: the climbs'
   lanes are offset by `style.routes.spread_m`.  That is why `joinedStyle` joins the styles of **every** frame of
   **every** subject, not just those drawn (`map/command.nim:157`), so a broken style of a frame not shown still breaks
   every map.  Style groups also share one namespace: two frames with a group of the same name overwrite each other,
   unchecked.
   Options:
   * (a) **Each provider ships its drawing**: a script template beside its style template, with a small contract
     (`draw(map, features, style, ctx)`, where `ctx` carries what frames share, such as the routes' spread).  `lines.nim`'s
     types move to their providers; `map` keeps the generic GeoJSON helpers or none.
   * (b) **A declarative style**: the page draws lines, polygons and points generically from the style, with named
     behaviours the page offers (`"offset": "lanes"`, `"levels": [...]`).  This is cleaner, but it is a small rendering
     language to design.
   * (c) **Keep it, and say so**: the page is the registry of kinds.  Document that a new frame means editing `map`.
   * Recommended: (a), before step 6.  It is mostly moving code that already exists, and it fixes the style namespace and
     the "all styles" join along the way (the page gets only the drawn frames' styles and scripts, each under its frame's
     name).

2. **The climbs frames write**: `climbs/mapframes.nim:94` `worked` calls `ensureClimbs`, which inserts sectors and
   efforts, from inside `make`, three times per page (`climbs`, `gates`, `efforts`).  A view that writes means:
   * for step 4, a key computed before `make` is stale as soon as `make` writes (the counters of `effort`, `sector` and
     `climbs_done` move);
   * the frames cannot be made in one read transaction (the departure "not one read transaction" cannot be fixed while
     a frame writes);
   * two page loads at once run two `ensureClimbs`.
   Options:
   * (a) **A separate `prepare` step on `MapFrame`** (optional, for the provider), which `map` runs for all chosen frames
     first, then one read transaction for all the `make`s, then the keys.
   * (b) **Frames never work out climbs**: the import does it already.  A frame finding activities not yet worked out says
     so in a note ("run `nch climbs`").
   * Recommended: (b) if the author agrees that the import is the only time climbs are lacking in practice; else (a).
   Either way, both the key (step 4) and the one transaction become possible.

3. **Under-declared tables on real data**: when the climbs are worked out inside the frame (found by deleting
   `climbs_done` for the latest 30 rides of the copy), the `climbs` frame reads **`route_cell`** (the candidate climbs use
   the cells), which `climbTables` (`climbs/mapframes.nim:111`) does not list.  It also reads **`spatial_ref_sys`**,
   SpatiaLite's own table, which the recording should ignore as it ignores `idx_` (`db/access.nim:61`).  The fixture
   tests (`tests/climbs/test_mapframes.nim:110`) never take that path.  With the climbs already worked out, every frame's
   declaration holds, for the selection of one ride and for all 1,113.  If finding 2 goes with (b), the problem goes with
   it, and `climbTables` shrinks to what is read (`activity climbs_done effort sector selection`, plus `track` for the
   efforts).  If not: add `route_cell`, ignore `spatial_ref_sys`, and give the test a ride whose climbs are not yet worked
   out.

4. **"One request per page" is not yet true**: files are named by subject and frame (`map-activities-routes.geojson`), so
   between the worker writing them and the page fetching them, another tab, a reload with other frames, or
   `nch map --file` can overwrite one, and the page then mixes two selections.  Crit-6 point 6 said "names them by key in
   the page".  Recommended for step 4: **name the files by key whether or not a frame is cached**.  It costs a few queries
   (`tablesKey`), and the old files then pile up, which `nch cache` deletes (in the plan already).

5. **A frame with nothing to draw fails the whole map.**  `makeRoutes` raises when no selected activity has a route, so a
   selection of one indoor ride fails `nch map` even if other frames have something.  The plan's risk section said a
   failed frame should not stop the others.  Recommended: an empty frame is a note and an empty collection; only real
   errors (damaged data) raise.  Similarly `prepare` refuses an empty selection before any frame (`map/command.nim:131`),
   which will be wrong for a frame with `readsSelection: false` (3b, the global heat): check only when some chosen frame
   reads the selection.

6. **Frame and subject names are strings that nothing checks across the registry.**  A `MapFrame.subject` with a typo is
   silently never shown, and "unique within the subject" (`map/frames.nim:29`) is not tested.  Add a test over the real
   registry: every frame's subject is a registered subject, frame names are unique per subject, and style groups do not
   collide (or are namespaced, finding 1).

7. **Small rule breaks in code the steps wrote or rewrote**:
   * `map/command.nim:114` `type Prepared` is dead (`prepare` returns a tuple).
   * `map/command.nim:69` `choose` returns `(Chosen, problem: string)` with `""` meaning fine: not "parse, don't validate".
     It could return `Parsed[Chosen]` or an `Option` of the problem.
   * `fmt` rule: the new and rewritten messages use `&` (`map/command.nim`, `activities/mapframes.nim`,
     `climbs/mapframes.nim`, `db/versions.nim:89`).
   * `map` declares `db` in `depends` and uses nothing of it (no SQL, no import).
   * `db/versions.nim:61` puts the table name into the text of an `insert` that could bind it (the triggers' DDL has to
     use text; the insert does not).
   * `activities/mapframes.nim:69`: "1 of the 3 activities have no route".

8. **Stale docs**: `NOTICE:10` says `nch heatmap --web`.  `map/page.html:30` says the numbers are in `map-style.json`
   (they are in each frame's style now).  `map/command.nim:10` says "This module is newer than `subject`" (presumably
   "above").  The grep for `--layers --web --state --selection proquint bits Layer routesKey requestStem stateKey allRows
   stateParam` outside `dev/` finds only these and the tests that check the old options are refused.

9. **The trust model of the triggers is sound for the counters, and has one older gap.**  `db` makes the `tv_` triggers
   with no caller (unchecked), and the authorizer skips every statement inside a trigger (`db/access.nim:66`), so the
   counters need no exception.  But the same skip means a trigger in any package's fragment could write any table
   unchecked (today `climbs` and `model` have triggers; they were not audited here).  Low priority, since there is one
   author: either audit the two, or check a trigger body's writes against the owner of the trigger (the `tv_` ones
   belong to `db`).  `ensureCounters`' "count the `tv_` triggers" check is exact because it intersects with
   `sqlite_master`.  Reads leave every counter unchanged (checked: `nch map --file` and `nch activities` on the copy).

## For step 4 (measured on the copy, all 1,113 selected, `make` alone)

| frame | time | size |
|---|---|---|
| routes | 4.4 s | 16 MB |
| efforts | 1.05 s | 46 MB |
| heat | 0.55 s | 6.4 MB |
| gates | 0.07 s | 73 KB |
| climbs | 0.05 s | 2.7 MB |

The routes of everything are what caching is for, as the baseline said.  The efforts of everything are 46 MB, which is too
much for a page; they are not shown by default and are meant for a few rides.  A warning or a limit may be worth more than
caching them.  `effortsOf` decodes a ride's positions once per effort (`climbs/mapframes.nim:84`): once per activity would
do.

## The departures listed in the brief, judged

* `Subject.selected` and `emptyHint`: fine.  The check should follow `readsSelection` (finding 5).
* Tab completion of the subject: fine to leave for now.  `completeFrames` offers every subject's frames, which is right
  until there are two subjects.
* Not one read transaction: it cannot be fixed while frames write (finding 2); after that, it is a `begin`/`commit` around
  the frames.
* A failing frame fails the request: keep that for real errors, but an empty frame should not count as one (finding 5).
* Serving checks only the selection: fine.
* The calendar's days in blue: fine.
* Step 2 needs no rebuild: agreed with the correction in HISTORY.

## The tests

They mirror the packages.  The worker's error paths are covered (`tests/web/test_handler.nim:128-150`); `ff` serving has
`tests/ff/test_web.nim`.  Gaps: the registry checks (finding 6), a climbs frame with climbs to work out (finding 3), two
frames whose styles share a group, and the page script, which `tools/pagecheck.js` only checks by hand.

## An aside, induced and not a finding

Deleting `climbs_done` rows by hand and working the climbs out again **doubled the efforts** of those rides (58 rows
became 116, 58 distinct): `effort` has no uniqueness on (activity, sector, start).  The normal paths delete efforts with
their activity, so this may never happen in use.  Worth a unique index if any path can re-look at an activity.

## Where the findings went

* `plan.md`: a new **step 3c** (findings 2, 3, 5, 6, 7, 8), before step 4; step 4 names every frame's file by its key
  (finding 4); step 6 starts with the design choice of how frames are drawn (finding 1).
* `TODO.md`: item 5 says step 3c is next; the triggers (finding 9) and the unique index on `effort` (the aside) are under
  "Features and ideas", as low priority.
