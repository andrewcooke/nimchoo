# TODO

Open work only, as one list in the order the author chose (2026-11-12).  Finished work is in git and in dev/HISTORY.md (with the
reasoning behind decisions); the reviews are in dev/REVIEW.md (the fourth on top, the others as appendices C, B and A).
When something here is done, delete it (in the same commit).  Design steps are discussed with the author before they start.

## Now: a plot of one activity (dev/plot-activity.md, 2026-11-25)

Step 4 of the note (0 to 3 are done): cadence, temperature and power.  Their frames are there already (one for each
channel of the list), and a run's cadence is its own frame, `steps` (2026-11-26); left: look at them on real data
(the author's runs, `~/fit/run`, are not imported yet).

## Next: consistency (proposed 2026-11-20; each decision open, to be taken one at a time with the author)

The presentation grew by many small requests, each done where it was asked, so similar things differ between commands.
First cut what exists for one view (A: done 2026-11-26), then make what is left share one helper each (B), each with a test that refuses the
next instance, and write the visual rules down in one place (C).  Every item is open: options, then a recommendation.

### B. Share

* **A table is measured as it is drawn** (asked 2026-11-26).  Without colour (a pipe, `NO_COLOR`) a `code` span is drawn
  with its backticks (`line.plainText`), but `line.width` does not count them, so `ruled` puts each code cell two columns
  out (`nch packages | less`, `nch --config`'s variables); `core/line.nim` says this was decided not to matter
  (2026-11-20), and the author now wants it fixed.  The width a line takes depends on whether colour is on, which `ruled`
  is not told: give it that (a flag, or a measuring function from `Globals`) and use the same one where a usage is laid
  out (`util/args/usage.nim`: check which way it measures now), with a test that lays out a table both ways and checks the
  columns line up in what is drawn.

### C. The review (done 2026-11-20)

11. **The fourth review's plan** (dev/REVIEW.md, section 5; findings in `dev/review-4/`).  Done: step 1 (robustness),
    step 2 (the other bugs) and step 3 (parse at the edge, with units in input: 2026-11-22).  Next: the output helpers, one fact, sentinels, dead code (section 3).

12. **A1: all output through `~"..."`: done** (2026-11-22; dev/REVIEW.md, section 4).  The drawer no longer reads backticks;
    help texts, parse problems, usages, messages and the importer's and namers' lines are `Line`s.  Left, small:
    * the frames' `summary` (map, calendar, climbs, activities: `MapFrame`, `CalendarFrame`) is text, also put in the page's
      JSON; its few backticks (`climbs/mapframes.nim`) are shown as they are (not coloured) until it is a `Line`;
    * `climbs/mapframes.nim:128`, `climbs/imported.nim`, `importer/failure` and similar helpers build strings with backticks
      for the log or for `ImportReport.text`: check on a terminal that nothing shows a backtick that should be a style;
    * the string versions of `failure`, `warn`, `usageError` and `sayDeleted` stay: they take text that is only known at run
      time (an exception's message), which is one colour.

21. **Tags** (the author's `dev/tags.md`, with what was decided below it).  Step 1 done (2026-11-23: the `tags` package,
    its table, what a tag is, matching, the `tag` style) and step 2 (`--tags` of `activities`, a criterion of its own:
    `activities` depends on `tags`, which is below it; the tags shown with `-v`, in a column) and step 3 (the sport as a tag at
    import, `sport:cycling:road`; `--sports` and `--sub-sports` gone, `--tags` completes the user's tags) and step 4 (import paths with templates: `{name}`, `{}`, `*`; a template may end at a
    directory, `~/fit/bike/{bike}`; tags only for files imported the first time) and step 5 (`nch tags`).  Left:
    6. later, with `nch efforts`: efforts inherit their activity's tags.

17. **Editable objects** (the author's idea and the design agreed 2026-11-22: `dev/editable-objects.md`): the `editable`
    package, built 2026-11-23 with models its first user (`nch ff`).  Left: `landmarks` (gains `--edit`, delete of what
    is listed, and the first filters beyond `--names`: places and ranges with units) and `users` (the hooks: one default
    user, a new FTHR); if the declaration has to bend for them, it is wrong.

## Tidy left from the reviews

* **The ride of 8 and 10 January 2026** (the author, 2026-11-23): `~/fit/bike/bowman/2026-01-08-tyo.fit` holds 25 minutes on
  8 January (08:33 to 08:58), nothing for 45 hours, then the ride El Toyo and back on 10 January (06:06 to 11:54); it is one
  activity dated the 8th, 51 hours elapsed and 4.6 on the timer, in three stretches.  Check how the import handles it
  (the date it is listed under, its name and distance, what the map and the calendar show) and whether a file like this
  should be one activity or two.
  Looked at 2026-11-26: the Edge was switched off on the 8th without saving (`power_down`) and on again on the 10th
  (`power_up`), so the file has one session and one lap; the 45 h gap is already a `manual` break (`ride_break`), but the
  activity is one (dated the 8th, "El Toyo and back").  It is the only break over 12 h of the 1,117 activities.  Power
  events are no help as a rule (the importer reads only timer events, which is right): of the 1,174 ride, run and walk
  files, 24 have them, mostly after the last record (switched off, saved later) or a lone `power_up` a minute or so into a
  gap (a crash); the four `-clc` files have a power cycle of 0.6 to 1.4 h mid-ride (a visit to the doctor: one ride each).
  Proposed: split a session at a break of any kind longer than 12 h (anything from 7 h to 44 h gives the same answer
  today), each part an activity of its own: `extract.nim` cuts the coordinates, samples, riding and breaks by time; the
  summary (`elapsed_s`, `timer_s`, `distance_m`, `calories`) comes from the session message, for the whole file, so for
  a part it is worked out (calories: none, or shared by timer time?); the key `(file_id, session)` gains a part.  Not
  decided.

* **A FIT file cut off at its end is imported, up to where it stops** (the author, 2026-11-25).  Now any truncated file fails
  as a whole (decided early: dev/HISTORY.md, "a truncated or corrupt FIT file fails as a whole").  A device that stops
  mid-ride (a flat battery) leaves a file whose header says no size (data size 0), with no checksum, cut off in the middle
  of its last message: `../choochoo/data/test/source/other/2018-04-15-09-18-20.fit` (an Edge 1030: 712,012 good bytes,
  then 9 of an 11-byte record) and `other/2018-02-24-10-04-10.fit`.  The tokenizer already yields every token before the
  error.  Proposed (b): when the damage is only at the end (a definition or data message cut short, nothing after it),
  drop it with a warning ("the file ends in the middle of a message: the last N bytes are dropped") and import the rest;
  damage inside a file still fails it whole; general repair stays out of scope.  The fuzz tests keep a damaged file from
  reaching a Defect.

* **The `activity` table: `sport` and `sub_sport` go** (the author, 2026-11-23; left out of the squash of step 0 of
  dev/plot-activity.md, 2026-11-25, as it changes code across several packages: a fragment that drops the columns, or the
  squash after):
  * **`sport` and `sub_sport` go: the sport is the `sport:` tag only** (one fact, which the user can edit for finer
    control, `sport:cycling:gravel`).  What reads them reads the tag, through one helper in `tags` (an activity's sport
    from its tag, the first if there are several, written as now, `cycling/road`): the activities list (its sport column,
    the count by sport on its last line, the transitions of a multisport file, `sport:transition`, in `hide`), the map's
    route popups (`activities/mapframes`, `mapfeatures`, `map-routes.js`), whether an activity is a run
    (`activities/activityframes.isRun`: its cadence is drawn as steps), the attempts of `climbs -v`
    (`climbs/attempts.nim`), and `importer/describe.sportText`.  At import the session's sport goes to the tag directly:
    the import step is given it, as it is given the samples and the labels, instead of reading a column.  The delete
    question's count by sport (`importer/remove.describe`) cannot read a tag (`importer` is below `tags`): it moves to
    `activities`, which asks the question.  Rejected: keeping the columns as "what the file said" (nothing would read
    them; the file itself is that record, read again at a rebuild).

1. **Susceptible climbs: left as they are, on purpose** (decided 2026-11-12; evidence in dev/HISTORY.md "Gates have no direction").  `overPaths`
   now pairs the crossings closest to the climb's length first, which is good enough: of 4,493 efforts 4,411 are right
   (`tools/gatetruth.nim truth`), 28 start late, 33 finish early, 21 are mostly off the line.  The rest are on the **17 of 183 climbs
   whose gate meets the climb's own line elsewhere** (`gatetruth susceptible`; 398 efforts; climbs 62, 147, 144, 145, 172, 118, 155 ...),
   and a direction rule is not safe on them (climb 145's finish sits on a fold).  Not worth more until a user cares enough about a
   climb or an attempt to push for something better, and has an opinion about how: the ideas are to report such climbs in
   `nch climbs`, retire them for a longer nearby climb with clean ends, move or narrow their gates, match the sequence of curves,
   or require progress along the climb (`gatetruth` already does that, for judging).  Look at examples with
   `nch map --frames routes efforts gates`.

7. **Left on purpose from the review** (dev/REVIEW.md; each with its reason):
   * the authorizer's **`caller` ""** (`db/access.nim`: code outside the packages is not checked): by design, though it is not in the
     types;

## Larger changes (designs not started)

2. **Arrays: what is left.**  Built and measured (2026-11-13, dev/HISTORY.md "The arrays"): the cleaning, the arrays and every reader;
   `coords` and `heartrate` are gone.  Left: (b) a **landmark for Cerro San Cristóbal** (`nch landmarks --add "Cerro San Cristóbal" --at
   -33.4253,-70.6331`), so the 98 rides over it are named after it (dev/NAMING.md says why a landmark and not a rule); the rides
   already named are named again by `nch activities --all --rename`; (c) a **simpler
   `route`**, also stored as a single connected line beside the multi-part one, for the uses where segmentation does not matter (21% of
   routes have several parts and SpatiaLite's resampling returns NULL for them; dev/HISTORY.md, 2026-11-11); (d) the stretches the
   cleaning splits are extra `segment` rows: look at one on the map.
3. **The shape of an activity stored at import** (idea): `names/shape.nim` computes the kind, the furthest distance, the
  turning point and the retrace shares in Nim from the points; storing them as columns of the activity when it is imported
  would make them queryable in SQL, without SQL ever needing the points (it is faster in Nim, dev/HISTORY.md, 2026-11-11).
  Not designed: check first what the naming needs and whether the stored name is enough.
4. **The `sectors` package** (it should find long climbs such as Camino a Farellones, which climb detection splits: dev/HISTORY.md,
   2026-11-17); **the cache manifest**.
5. **The display architecture** (live views, subjects, frames; designed 2026-11-14): `dev/display-arch/plan.md` has the steps, each one done
    only with the author's approval; it replaces the old "Addresses, what is left" (wrapper page, climbs as a layer, the plot command) and
    "`map` criteria of its own".  Steps 0 to 3 and 3c (the fixes from the review, `dev/display-arch/review-after-step-3-findings.md`) are done; step 4 decided no caching and step 5 done (2026-11-16); 6a done (providers draw their frames, D7); 6 done (the climbs subject, 2026-11-18: D8 to D10); next: 7 (FF statistics, after a design note: D5).  Left over from steps 3 and 5: tab completion of the subject of `map` and `calendar` (a positional word:
    `core/complete` knows only options, so it needs the completion framework to learn them).
6. **Large countries and `ensureCells`** (low priority; idea, measured 2026-11-11 on Chile only): a batch of new cells
  unzips and parses the whole country file (Chile: 75-140 ms per batch, 2 s for the whole country; `countriesOfCell` 0.15 ms
  per cell, `missingCells` under 1 ms, both fine).  A cell already loaded is never read again (`coverage`).  The cost is
  batches times file size, so it would only matter for a large file (US about 2 M rows, Russia) with rides scattered over
  many areas; not timed yet.  If it ever does: (a) split the file once per country into one indexed file, rows grouped by
  cell with a table of offsets (recommended; one pass, no partial states); or (b) the author's idea, a quadrant tree
  written to the cache, each read of a cell splitting its file into four around the cell and keeping the smaller files
  (a spatial index built lazily; more generated files to name, make safe against a crash, and delete with `nch cache`).
  Time the largest country first.

## Features and ideas, unordered

* **Lines for the calendar** (the author, 2026-11-20): `nch calendar` drawn with lines, as the tables are (a rule under
  the weekday names, lines between the month, the days and the year?).  To look at with the author.
* **`nch climbs`: simpler, and more** (the author, 2026-11-20): simplified (the list mixes the selected and the
  not-selected: the best of all attempts beside the best of the selected ones, a rank of the selected among all) and
  extended (the best and the most recent attempts).  To design with the author.
* **The last line of `nch climbs` with totals** (the author, 2026-11-20): "done: 3 of 184 climbs" could go on as the
  activities' does, with the length and the gain of the climbs listed.
* **`nch packages --points`** is hard to understand (the author, 2026-11-17).  Since 2026-11-18 it is a ruled table (point,
  defined by, added to by, what it is; the types and priorities are in `nch packages NAME`); the author is going through the
  packages soon and may change it again.
* **The log**: level filtering (`--level warn`); the `saved` word is green for every use (low priority).
* **The map**: labels, a legend, landmarks on the map, style rules by
  property (colour by sport or year).
* **The map: a box for each ride, as on the plot** (the author, 2026-11-26): the page lists the selected activities with a
  box each (as `nch plot activity` does, dev/plot-activity.md), and only the ticked rides are drawn.  First tidy the plot's
  page (what to tidy: to discuss with the author), so that the list of rides to tick is one piece the two pages share.
* **`ff`**: a form column (fitness minus fatigue); a switch between days and hours in the page (superseded if the plot command comes first).
* **The selection's style in `nch climbs`**: the `-v` attempts of selected rides have it (done); left, the latest/rank cells
  when the latest attempt is of a selected ride, once display step 6 has said what `nch climbs` lists.  The author also asked
  whether "the selection chooses the climbs, never the attempts" is right; it is built that way.
* **Tags** on activities (by hand: equipment, "bike A"), if wanted: a package that contributes a `--tag` criterion.
* **More climb features**: the elevation profile of a climb, the lead/lag comparison, the near-miss report, `exclude`, a way to retire many climbs
  (auto-retire of duplicates was tried and dropped: it retired long climbs into shorter near copies).
* **Per-sport threshold heart rate and models**, if wanted.
* **A terrain model (SRTM)**: if added, smooth its heights (`climbs/profile.smoothed` is there for that).  It would give
  altitude to the 139 rides without any (101 of them in 2019: measured 2026-11-20), which now have no climbs or attempts;
  how the device's altitude and the model's combine (compare, fix, replace) is to be decided then.
* **Versions** (dev/HISTORY.md, Task 11): when the version number changes; tie it to releases and the end of squashing.
* **Tab completion**: zsh (`--install-completion zsh`: its own directory and mechanism), if wanted; `--edit NAME` for the other plural
  commands, and a `--model` of `map`, if they gain them (completion follows the specs).
* **Inspecting positions on the map** (dev/CLEANING.md, "Related"): the time of a position on hover, or a layer of the raw
  positions; smoothing (`smooth_rounds`) only on cleaned data; places of bad reception (faults per cell, from cleaning) as a
  layer or a list, never an input to cleaning.
* **Tests that depend on timing fail now and then under load** (2026-11-18): `tests/util/child/test_child.nim` ("three children
  that take 0.5 s each take about 0.5 s together": 1.36 s against 1.3 s) and `tests/download/test_fetch.nim` (the spinner's
  thread drew one frame, not two).  Each passed when run again.  Give them more slack, or measure what they mean another way.
* **Triggers are not checked by the access model** (the review of 2026-11-14, finding 9; low priority): the authorizer skips every
  statement inside a trigger, so a trigger in a package's fragment could write any table.  Audit the triggers of `climbs` and `ff`,
  or check a trigger's writes against the package that made it (the `tv_` counters belong to `db`).
* **A unique index on `effort`** (the review of 2026-11-14, an aside; low priority): working out an activity's climbs again (after its
  `climbs_done` row was deleted by hand) doubled its efforts.  No normal path is known to do that; worth an index if one can.
