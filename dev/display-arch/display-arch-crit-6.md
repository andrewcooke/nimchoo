# A critique of the display architecture, sixth version (2026-11-14)

A response to `dev/display-arch/display-arch.md` (the version with the text view, a registry for subjects as a possible
first step, the rules of hashing left to the plan, and "context / all"), written by the assistant after reading it with
the code (`map`, `ff`, `calendar`, `web`, `selection`, `db/access.nim`), `dev/MAP-LAYERS.md` and the rules on addresses
and state in `dev/HISTORY.md` (2026-11-12) and `TODO.md`.  The next step is a plan of migration, so this version says
first whether anything stops it.  Nothing here is agreed.

## Verdict: no deal breakers

Nothing in the architecture conflicts with the package rules, the access model or the way the program is used.  Three
things would have been deal breakers if done the obvious way; each has a fix that the plan will adopt (they are below,
under "Rules the plan will set"):

1. **Keys combined by xor** give the same key to every map of a selection (the selection's key and the key of the
   activities shown are equal, and cancel).  Already settled: the plan uses SHA-256 of the parts in order.
2. **Keys that restart when the database is rebuilt.**  The database is rebuilt from the FIT files at will, and a rebuild
   gives the same ids and, if versions are counters, the same counters, to different data: the cache, which survives a
   rebuild, would then serve stale frames as if they were current.  Every key must include an identity of the database,
   made when it is created.  (This applies to the counter recommended in earlier versions of this review, which missed it.)
3. **Version columns kept by triggers, against the access model.**  Checked in `db/access.nim`: the authorizer does not
   look at what a trigger does ("the database's own business"), and a package may put a trigger on any table it may read.
   So triggers that keep versions up to date need no change to the access model.

Two things must be decided before the plan is written (see "Decisions needed"): how subjects are registered (the
proposal is not yet consistent about it), and what `nch climbs` shows once climbs have a selection of their own.

## The display architecture today

* **Views are commands**: `map` (GeoJSON shown with Leaflet, on the web), `ff` (CSV shown with Observable Plot, on the
  web), `calendar` (in the terminal).  `map` and `ff` write their data file into the cache and print its path; `--web`
  also serves the page.
* **There is one selection**: of activities, per user, in the table `selection`.  Climbs follow it ("the selection
  chooses the climbs").  `ff` ignores it.
* **Addresses are pinned**: a web address carries `selection=BITS` (`selection/bits.nim`, fuzzed) and `state=HASH`, a
  fingerprint of every table the plot reads; the server runs `nch CMD --worker`, whose third line is the pinned address,
  and redirects the browser to it; files are named by proquints of a hash of the address; a file cleaned from the cache
  is made again only when the state still matches, else the address is an error.
* **`map` makes every layer itself**: routes, climbs, heat, gates and efforts are one `Layer` enum, all made in
  `map/command.nim`, so `map` depends on `climbs`, `importer`, `geo` and `selection`.  `calendar` depends on `activities`.
* **The look**: the page is three templates, `map.html`, `map.css` and `map-style.json`, built in and unpacked to the
  cache's `system/templates/`, where they can be edited (an edited file is never overwritten; a deleted one comes back).
  The page fetches the GeoJSON from the server (`/files/NAME`) and draws each feature by its `kind`.

## What holds up

1. **The diagnosis**: the pinned bookmark is what produced `state`, `bits`, the worker's pinned address, the redirect and
   the proquint names.  Dropping it is mostly deletion.
2. **Views do not choose data; commands that manage a selection are not views.**  The TODO item "`map` criteria of its
   own" (2026-11-13) goes the other way and would be dropped.
3. **Views before subjects in the package order**, with frames contributed through extension points: `map` stops knowing
   every kind of layer.
4. **Primary and secondary subjects, with secondary selections ignored.**
5. **Frames keyed by what they show** (the primary selection, the secondary instances, other data, the program, the frame
   itself), so nothing has to be told of a change; the inverted case keyed the same way.
6. **Global data as frames of their own.**
7. **The page by default, `--file` for the files**, and perhaps a text view replacing `--file` later.
8. **Styles belong to their provider**, editable in the cache as now.
9. **"Context / all" as a frame across views, later; `calendar --all` dropped now.**  ("All, with the selection marked"
   changes which data are shown, so it is a frame or a view option that enters the key, not an aesthetic; either works.)
10. **The registry of frame formats, later**: when two views share a format.  It is the existing extension points defined
    per format instead of per view, so starting per view loses nothing.
11. **It covers the open TODO items without special cases**: the general plot command (a plot view of the FF subject),
    the calendar of fitness (a calendar view with an FF frame), the elevation profile and the lead/lag comparison of rides
    up a climb (plot views of the climbs subject), "climbs become a layer" (a frame).

## Decisions needed before the plan

1. **How subjects are registered.**  The section "Selections, Views and URLs" says a subject's package registers "via an
   extension point on the view"; "Package Ordering" calls a registry only for subjects "a reasonable compromise" and leaves
   registries for later.  The plan needs one:
   * (a) **one point, `subjects`** (name, owner, how to get the selection, the key of any set of its items, whether it is
     the default), defined by a small package below the views and read by every view.  A subject is registered once; a
     new view needs no change to the subjects; the default subject (activities) is a mark, not a special case.
   * (b) a point on each view: `activities` then depends on `map`, `calendar` and the plot view, and each new view means
     editing every subject's package.
   * (c) activities before the views, as the default: `map` depends on `activities`, so `activities` and `importer` can no
     longer give it frames, and the routes and the heat go back into `map`.
   Recommended: (a).  It is no bigger than (b), and it is the first step of the later registry rather than something it
   undoes.
2. **What `nch climbs` shows.**  Today it lists the climbs of the selected activities.  With a climbs subject it manages
   the climbs selection, so it would list *that*, and "the climbs of the selected activities" becomes a frame (climbs
   secondary to activities) shown by a view.  What the climbs selection is after an import (the new climbs? unchanged?)
   and how it is first set also need an answer.  This changes what a familiar command prints, so it is the author's call.
   It is needed only for the step that adds the climbs subject (step 6 below), so the plan can start without it.

## Rules the plan will set (keys and caching)

The author left the details of keys to the plan.  These are the rules; they go into the documentation of the package
that defines frames, and the last one is a test every provider has.

1. **Parts are combined by SHA-256 in a fixed order**, never by xor or anything else that can cancel.
2. **Every key includes the database's identity** (a random value made when the database is created and never changed),
   **the program's version**, and **the frame's name** (view, subject, frame).
3. **The data a frame reads are keyed by counters kept by triggers**.  Two grains, to choose in the plan by measurement:
   * (a) **per table**: one counter per table, increased on every insert, update or delete.  A selection's key is then the
     sorted ids plus the counters of the tables the frame reads.  Simple (no column on any row, one trigger set per table);
     the cost is that any change to a table (an import, say) makes every frame that reads it again;
   * (b) **per row**: a version on each row of a subject's table (set on insert, increased on update), and the key of a set
     is the SHA-256 of its (id, version) pairs.  Frames survive changes to rows they do not show; more triggers and columns.
   Recommended: (a), since for one user changes come in batches (an import, a cleaning run) and caching is to be measured
   anyway; (b) where measurement shows needless remaking.
4. **A provider declares the tables its frame reads**, and its key covers them.  The test: build the frame with the
   authorizer recording every table read (`db/access.nim` already sees each one), and check that the declared list holds
   them all.  That catches the class of bug "an input missing from the key" mechanically, instead of by a test per table
   written by hand.
5. **Caching comes after measuring.**  The plan first makes frames on every request; a cache is added for a frame whose
   making is shown to be slow.

## Other points for the plan

1. **Providers are the packages that manage subjects, not the ones beneath them.**  With views before subjects, a
   provider depends on the view.  If `importer` provided the routes, the importer (which almost everything depends on)
   would depend on `map`, `web` and the templating.  Better: `activities` provides the routes and the heat (it may read the
   importer's tables), `climbs` the climbs, gates and efforts.
2. **How frames are named and chosen**: `--frames FRAME...` on the command line and `frames=a,b` in the address (the
   option conventions); each provider marks its frame as shown by default or not; names unique within a view and subject.
   The subject is the view's first argument (`nch map climbs`), activities when it is left out.  Tab completion offers
   the frames of every subject (or of the one typed).
3. **`--file` with several frames**: one file per frame, `--file` printing their paths.  Files named by key pile up in the
   cache; `nch cache` deleting them is enough.
4. **Styling**: each provider ships a style template for each of its frames, unpacked into `system/templates/` and
   editable there; the view's page puts together the styles of the frames it shows.
5. **The worker stays** (the server cannot import the views), without the pinned address and the redirect.
6. **One request per page**: the page's request makes the frames and names them by key in the page, so a selection
   changing while the page loads cannot mix two selections.  An import replaces the selection, so every open map changes
   on its next reload: consistent with live views.
7. **FF statistics are new work** and need a design note of their own (which statistics, what selecting them means, which
   command does it) before their step.

## A rough order of migration (for the plan)

1. **Delete the pinning, and swap the default.**  Addresses become live; `bits`, `--state`, `--selection`, the redirect and
   the proquint names go; the worker stays.  `nch map` serves the page; `nch map --file` makes the files.  `calendar --all`
   goes.
2. **The point `subjects` and the activities subject** (the default), with the database's identity and the counters.
3. **Turn `map` round**: a frames point on `map`; `activities` provides the routes and the heat, `climbs` the climbs, gates
   and efforts, each with its style template.  `map` loses those dependencies.  A global heat map can follow as one more
   provider.
4. **Caching**, where measurement shows it is needed, with the keys of the rules above and the authorizer test.
5. **`calendar` on frames**; then, after their design note, **FF statistics** as a subject with the plot view, and the
   text view taking `ff`'s CSV.
6. **A selection of climbs and the climbs subject** (after decision 2), with the inverted frame (the activities on the
   selected climbs).
7. **Later**: "context / all" across views; the registry of frame formats; perhaps the text view replacing `--file`.

## Questions for the author

1. **Subjects** (decision 1): one `subjects` point read by every view?
2. **`nch climbs`** (decision 2): once climbs have a selection, does it list the selection, and what is that selection
   after an import?  (Not needed until step 6.)
3. **Counters per table or per row** (rule 3): per table first, measured?
