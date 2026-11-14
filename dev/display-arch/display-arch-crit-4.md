# A critique of the display architecture, fourth version (2026-11-13)

A response to `dev/display-arch.md` (the version with subjects registered with views, keys combined by xor, `--file`,
the inverted dependency example with its key, and the notes on global data and frame styling), written by the assistant
after reading it with the code (`map`, `ff`, `calendar`, `web`, `selection`), `dev/MAP-LAYERS.md` and the rules on
addresses and state in `dev/HISTORY.md` (2026-11-12) and `TODO.md`.  For discussion; nothing here is agreed.

## The display architecture today

* **Views are commands**: `map` (GeoJSON shown with Leaflet, on the web), `ff` (CSV shown with Observable Plot, on the
  web), `calendar` (in the terminal).  The listings in `activities` and `climbs` are views too, in practice.  `map` and
  `ff` write their data file into the cache and print its path; `--web` also serves the page.
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
  `map/command.nim`, so `map` depends on `climbs`, `importer`, `geo` and `selection`.
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
2. **Views do not choose data.**  This is clean, and it is how `activities --select` followed by `map` is already used.
   It settles the TODO item "`map` criteria of its own" (2026-11-13), which goes the other way: that item would be dropped.
3. **Frames contributed through extension points.**  This applies the package rules to display.  `map` would no longer
   depend on `climbs` and `importer`; `climbs` would contribute its frames to `map`.  Today's `map` is the "command that
   knows every kind of layer" that the review in `MAP-LAYERS.md` warned about.
4. **Primary and secondary subjects, with secondary selections ignored.**  A frame's inputs are then one selection plus
   the state of what it shows.
5. **The key of a frame made of the keys of what it shows**, and only of what changes it: the primary selection, the
   secondary subjects, any other data drawn.  A frame is reused when its key is the same, so nothing has to be told of a
   change.  The inverted case (the activities on the selected climbs, provided by `climbs`) is keyed the same way.
6. **Global data as frames of their own** (a heat map of everyone's activities): such a frame reads no selection, and its
   key is the key of all the data it draws.
7. **The page by default, `--file` for the files.**  The normal use is the page; the files, in the cache and named by a
   prefix and their key, stay available for another tool.
8. **Styles belong to the provider** and are editable in the cache, as the map's are now (see point 6 below).
9. **It covers the open TODO items without special cases**:
   * "the general plot command replaces `ff`" is a plot view of the FF subject;
   * "a calendar of fitness" is a calendar view with an FF frame;
   * the elevation profile of a climb and the lead/lag comparison of rides up a climb are plot views of the climbs subject;
   * "climbs become a layer" is a frame.

## What needs more work

1. **Combining the parts of a key by xor cancels them out.**  In the ordinary case, a map of the selected activities, the
   primary key is the key of the selection and the key of the activities the frame shows is the key of the same set.
   `x xor x` is zero, so every such frame, whatever is selected, gets the same key, and the cache serves the wrong file.
   The same happens whenever two parts happen to cover the same data.  Parts must be combined by hashing them in order
   (`sha256(part1 & part2 & ...)`), which never cancels.  Within one set xor would work, since the members are distinct,
   but SQLite has neither an xor operator nor an xor aggregate; the SHA-256 of the members' keys in id order
   (`group_concat`) is done in SQL and is what `keyOf` does today.
2. **A key must also say how the frame is made.**  Two things besides the data change a frame:
   * **which frame it is**: the routes and the heat of the same selection have the same data keys.  The file's prefix
     separates them, so the prefix must be part of what is looked up (frame name and subject, say
     `map-activities-routes-KEY.geojson`);
   * **the program**: a new build that draws a frame differently (a new simplification, a property added) would reuse the
     old file.  The rule of 2026-11-12, "the program's version is not part of the state", was for pinned bookmarks (a new
     build must not break a bookmark); with live views it no longer applies.  Options: (a) the program's version in every
     key (automatic; the cache is made again after each build); (b) a format number per provider, bumped by hand (keeps
     the cache across builds, but forgetting to bump it is a silent stale cache, and the project's rule is never to keep
     two things in step by hand).  Recommended: (a), and measure how long remaking costs before considering (b).
3. **Register subjects once, not with each view.**  If each view defines a point for subjects, the package that manages a
   subject contributes to every view: `activities` would depend on `map`, the plot view and `calendar`, and a new view
   would mean editing every subject's package.  Better: **one point, `subjects`** (name, owner, how to get the selection,
   and the key of any set of its items), defined by a small package below the views, which every view reads.  Frames stay
   per view (or per frame type, if two views ever share one).  Either way the direction of the dependencies turns round:
   the views become low packages (on `web`, `ui`, `cache`), and the data packages, as providers, sit above them.
4. **"Last modified": a counter rather than a time.**  The equivalence the proposal notes holds if the value changes on
   every write.  A time can repeat (two writes in one second, a clock set back), and SQLite may reuse the rowid of a
   deleted row (without `autoincrement`), so the pair (rowid, time) could repeat too.  A counter shared by all rows, set
   when a row is written and increased by a trigger on every update, cannot.  The arrays are never changed once written,
   so the version of an activity's row stands for them as well.
5. **`--file` with several frames.**  A map is several frames, so `--file` makes several files.  Options: (a) one file per
   frame, and `--file` prints their paths (what the cache holds anyway); (b) one merged file per view (easier to open in
   another tool, but a second form to make and name).  Recommended: (a); merging is easy to add if a tool needs it.  Files
   named by key pile up in the cache, since a changed key makes a new file and the old one is never read again; `nch
   cache` deleting them is enough.
6. **How styling works, and how it would work.**  Today (above) the look of the map is one style file for every kind.
   Under the proposal each provider ships a style template for each of its frames (`climbs` the style of the climbs
   frame), unpacked into `system/templates/` like the map's are now and editable there; the view's page puts together the
   styles of the frames it shows.  Tweaking the look in the page itself is separate and can wait.
7. **How frames are named and chosen.**  "Views allow the user to select from the available frames" needs four things:
   * **on the command line**: `--frames FRAME...`, plural and separated by spaces, as the option conventions say;
   * **in the address**: `frames=a,b`, separated by commas, as the same conventions say;
   * **defaults**: each provider could mark its frame as shown by default;
   * **names**: unique within a view and subject, so that `nch map climbs --frames routes` means one thing.
8. **The worker.**  The server cannot import the views (only a `package.nim` imports a command), so something has to make
   the page in a child process.  Recommended: keep `nch VIEW --worker` for now, without the pinned address and the
   redirect: it already exists.
9. **Two small effects of live addresses:**
   * an import replaces the selection (`importer/after`), so every open map changes on its next reload (consistent with
     the proposal; worth knowing);
   * a page that fetches its frames in separate requests could mix two selections if one changes while it loads.  One
     request per page (the frames named by key in the page that request makes) avoids that.
10. **FF statistics are new work.**  "Various statistics, selectable" is new functionality, not a port of `ff`.  Which
    command chooses them is open.  It deserves a design note of its own.

## A rough order of migration (not agreed)

1. **Delete the pinning, and swap the default.**  Addresses become live (`/map?frames=routes,climbs`); `bits`, `--state`,
   `--selection`, the redirect and the proquint names go; the worker stays, without the pinned address.  `nch map` serves
   the page; `nch map --file` makes the files.
2. **Add the point `subjects` and the activities subject**: the existing selection, the version counter and its trigger,
   and the key of any set of activities.
3. **Turn the views round**: a frames point on `map`; the routes and the heat move into their owners as providers, and the
   climbs, gates and efforts into `climbs`, each with its style template.  `map` loses those dependencies.  A global heat
   map fits here, as one more provider.
4. **Caching**: measure first (making everything on every request may be fast enough); then keys as in points 1 and 2
   above, with the test each provider needs (change each table it reads, and check that the key changes).
5. **FF statistics as a subject** (after their design note), then a selection of climbs (`climbs --select`) and the
   climbs subject, with the inverted frame (the activities on the selected climbs), then `calendar` on frames.

## Questions for the author

1. **The program in the key**: (a) the program's version, or (b) a format number per provider (point 2)?
2. **`--file`**: one file per frame, or one merged file (point 5)?
3. **FF statistics**: which command chooses them?
4. **Listings**: are `nch activities` and `nch climbs` views, or part of managing a subject?  Related: `calendar --all`
   chooses data, which the proposal says views should not do.  Should it become a frame ("all activities, with the
   selection marked")?
5. **Default subject**: should `nch map` default to activities, with `nch map climbs` for the other subject?
