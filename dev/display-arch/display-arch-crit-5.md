# A critique of the display architecture, fifth version (2026-11-14)

A response to `dev/display-arch.md` (the version split into architecture and implementation details, with a text view,
views before subjects in the package order, a registry of frame formats as later work, and the details of hashes left to
the implementer), written by the assistant after reading it with the code (`map`, `ff`, `calendar`, `web`, `selection`),
`dev/MAP-LAYERS.md` and the rules on addresses and state in `dev/HISTORY.md` (2026-11-12) and `TODO.md`.  For
discussion; nothing here is agreed.

## The display architecture today

* **Views are commands**: `map` (GeoJSON shown with Leaflet, on the web), `ff` (CSV shown with Observable Plot, on the
  web), `calendar` (in the terminal).  `map` and `ff` write their data file into the cache and print its path; `--web`
  also serves the page.
* **There is one selection**: of activities, per user, in the table `selection`.  Climbs follow it ("the selection
  chooses the climbs").  `ff` ignores it.
* **Addresses are pinned**:
  * a web address carries `selection=BITS` (`selection/bits.nim`, fuzzed) and `state=HASH`, a fingerprint of every table
    the plot reads;
  * the server runs `nch CMD --worker`, whose third line is the pinned address, and redirects the browser to it;
  * files are named by proquints of a hash of the address;
  * a file cleaned from the cache is made again only when the state still matches, else the address is an error;
  * the rule behind all of this (2026-11-12): "a bookmark brings back **that plot**".
* **`map` makes every layer itself**: routes, climbs, heat, gates and efforts are one `Layer` enum and are all made in
  `map/command.nim`, so `map` depends on `climbs`, `importer`, `geo` and `selection`.  `calendar` depends on `activities`.
* **The look**: the page is three templates, `map.html`, `map.css` and `map-style.json`, built in and unpacked to the
  cache's `system/templates/`, where they can be edited (an edited file is never overwritten; a deleted one comes back).
  The css and the style are filled with the palette's colours, then put into the page, which fetches the GeoJSON from the
  server (`/files/NAME`) and draws each feature by its `kind`.

## What holds up

1. **The diagnosis.**  The decision that a bookmark is a reproducible snapshot is what produced `state`, `bits`, the
   worker's pinned address, the redirect, and the argument over contradictory approaches.  Dropping it removes the cause,
   not just the symptoms.  These would go: `--selection` and `--state` of `map` and `ff`; `bits.nim` and its fuzzing; the
   worker's pinned address and the server's redirect; the proquint names; "made again only if the state matches".  This is
   mostly deletion.
2. **Views do not choose data, and commands that manage a selection are not views.**  The output of `activities` and
   `climbs` is part of managing state; a text view (lists, CSV) is a separate thing.  It settles the TODO item "`map`
   criteria of its own" (2026-11-13), which goes the other way: that item would be dropped.
3. **Views before subjects in the package order.**  Views are subject-agnostic and low (on `web`, `ui`, `cache`); the data
   packages sit above them as providers.  `map` would no longer depend on `climbs` and `importer`; `climbs` would
   contribute its frames to `map`.  Today's `map` is the "command that knows every kind of layer" that the review in
   `MAP-LAYERS.md` warned about.
4. **The registry of frame formats, later.**  Providers registering frames by format, and views asking for the formats
   they draw, is where the design goes once two views share a format (a calendar and a text view both showing a daily
   sequence; a plot and a text view both showing series).  It needs no new machinery: it is the existing extension points
   (`core/extension.nim`), defined per format by a package below the views instead of by each view.  Moving a point from a
   view to a format package is mechanical, so starting per view loses nothing.  Leaving it for later is right: a general
   format designed before its second user is a guess.
5. **Primary and secondary subjects, with secondary selections ignored.**  A frame's inputs are then one selection plus
   the state of what it shows.
6. **The key of a frame**: made of the keys of what it shows and only what changes it (the primary selection, the
   secondary instances, other data, the program's version), plus a key for the frame itself.  A frame is reused when its
   key is the same, so nothing has to be told of a change.  The inverted case (the activities on the selected climbs,
   provided by `climbs`) is keyed the same way.  The details of hashing are rightly left to the implementer (see point 1
   below for what they must guarantee).
7. **Global data as frames of their own** (a heat map of everyone's activities): such a frame reads no selection, and its
   key is the key of all the data it draws.
8. **The page by default, `--file` for the files.**  The normal use is the page; the files, in the cache and named by a
   prefix and their key, stay available for another tool.
9. **It covers the open TODO items without special cases**:
   * "the general plot command replaces `ff`" is a plot view of the FF subject;
   * "a calendar of fitness" is a calendar view with an FF frame;
   * the elevation profile of a climb and the lead/lag comparison of rides up a climb are plot views of the climbs subject;
   * "climbs become a layer" is a frame.

## What needs more work

1. **What the keys must guarantee, written down as rules.**  With the details left to the implementer, the rules are
   what a test can check, and they belong in the documentation of the package that defines frames:
   * parts are combined so that they never cancel (equal parts must not give a fixed result; xor does, SHA-256 of the
     parts in order does not);
   * the key names the frame (its view, subject and name) and the program's version (decided: "implicitly, this may
     include the program version"; recommended: always, so that a new build never serves a frame made the old way);
   * a row's key changes on every write and never repeats (a counter, or a time with an `autoincrement` rowid);
   * **each provider has a test that changes each table its frame reads and checks that the key changes**.  That test
     guards against the class of bug "an input missing from the key", which is the one bug this design can still have.
2. **Register subjects once, not with each view** (the note "to consider" at the end of the proposal).  With views before
   subjects, a subject's package contributing to a point of each view depends on every view: `activities` on `map`,
   `calendar` and the plot view, and a new view means editing every subject's package.  One point, `subjects` (name,
   owner, how to get the selection, the key of any set of its items), defined by a small package below the views and read
   by all of them, avoids that, and is the first step of the registry above rather than a different design.  Frames stay
   per view until the registry.  Recommended now, because it is as small as the per-view form and is not undone later.
3. **Activities before views: recommended against.**  The variation in which views special-case activities as the
   default makes `map` depend on `activities`, so `activities` (and `importer`, below it) can no longer contribute frames
   to `map`: the routes and the heat would have to be made by `map` itself or by a package above, which is today's
   problem again.  A default subject needs no special case: the `subjects` point can carry it (one subject marked as the
   default, which `nch map` uses when it is not given one).
4. **The text view and `--file` overlap.**  Both give the data rather than a picture: `--file` writes a view's frames to
   the cache for another tool; a text view prints a subject as lists or CSV.  Options: (a) keep both, the text view for
   reading in a terminal and `--file` for tools; (b) the text view replaces `--file` (one way to get the data, with the
   formats other tools read); (c) `--file` replaces the text view.  Recommended: (a) for now, since the text view does not
   exist yet, and decide when it is built; but `ff`'s CSV on standard output is the text view's first case, so it should
   move there rather than into `--file`.
5. **`--file` with several frames.**  A map is several frames, so `--file` makes several files.  Options: (a) one file per
   frame, and `--file` prints their paths (what the cache holds anyway); (b) one merged file per view (easier to open in
   another tool, but a second form to make and name).  Recommended: (a); merging is easy to add if a tool needs it.  Files
   named by key pile up in the cache (a changed key makes a new file, and the old one is never read again); `nch cache`
   deleting them is enough.
6. **Styling: "as now", yes.**  Each provider ships a style template for each of its frames (`climbs` the style of the
   climbs frame), unpacked into `system/templates/` like the map's are now and editable there; the view's page puts
   together the styles of the frames it shows.  Tweaking the look in the page itself is separate and can wait.
7. **How frames are named and chosen.**  "Views allow the user to select from the available frames" needs four things:
   * **on the command line**: `--frames FRAME...`, plural and separated by spaces, as the option conventions say;
   * **in the address**: `frames=a,b`, separated by commas, as the same conventions say;
   * **defaults**: each provider could mark its frame as shown by default;
   * **names**: unique within a view and subject, so that `nch map climbs --frames routes` means one thing.
8. **`calendar --all`** chooses data, which views do not do.  It can become a frame: "all activities, with the selection
   marked", offered by the activities provider to the calendar.
9. **The worker.**  The server cannot import the views (only a `package.nim` imports a command), so something has to make
   the page in a child process.  Recommended: keep `nch VIEW --worker` for now, without the pinned address and the
   redirect: it already exists.
10. **Two small effects of live addresses:**
    * an import replaces the selection (`importer/after`), so every open map changes on its next reload (consistent with
      the proposal; worth knowing);
    * a page that fetches its frames in separate requests could mix two selections if one changes while it loads.  One
      request per page (the frames named by key in the page that request makes) avoids that.
11. **FF statistics are new work.**  "Various statistics, selectable" is new functionality, not a port of `ff`.  Which
    command chooses them is open.  It deserves a design note of its own.

## A rough order of migration (not agreed)

1. **Delete the pinning, and swap the default.**  Addresses become live (`/map?frames=routes,climbs`); `bits`, `--state`,
   `--selection`, the redirect and the proquint names go; the worker stays, without the pinned address.  `nch map` serves
   the page; `nch map --file` makes the files.
2. **Add the point `subjects` and the activities subject** (the default): the existing selection, the rows' keys, and the
   key of any set of activities, with the rules of point 1 above in the package's documentation.
3. **Turn `map` round**: a frames point on `map`; the routes and the heat move into their owners as providers, and the
   climbs, gates and efforts into `climbs`, each with its style template.  `map` loses those dependencies.  A global heat
   map fits here, as one more provider.
4. **Caching**: measure first (making everything on every request may be fast enough); then the keys, with the test each
   provider needs.
5. **`calendar` on frames** (with `--all` as a frame), then **FF statistics as a subject** (after their design note) with
   the plot view, and the text view taking `ff`'s CSV.
6. **A selection of climbs** (`climbs --select`) and the climbs subject, with the inverted frame (the activities on the
   selected climbs).
7. **Later: the registry of frame formats**, when two views share a format.

## Questions for the author

1. **Subjects once** (point 2): one `subjects` point read by every view, now?
2. **The text view and `--file`** (point 4): keep both for now, with `ff`'s CSV going to the text view?
3. **`--file`** (point 5): one file per frame, or one merged file?
4. **FF statistics**: which command chooses them?
