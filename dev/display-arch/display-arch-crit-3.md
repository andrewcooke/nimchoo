# A critique of the display architecture, third version (2026-11-13)

A response to `dev/display-arch.md` (the version with the notes on web views and secondary selections, the hash of an
activity's row, and the inverted dependency example), written by the assistant after reading it with the code (`map`,
`ff`, `calendar`, `web`, `selection`), `dev/MAP-LAYERS.md` and the rules on addresses and state in `dev/HISTORY.md`
(2026-11-12) and `TODO.md`.  For discussion; nothing here is agreed.

## The display architecture today

* **Views are commands**: `map` (GeoJSON shown with Leaflet, on the web), `ff` (CSV shown with Observable Plot, on the
  web), `calendar` (in the terminal).  The listings in `activities` and `climbs` are views too, in practice.  `map` and
  `ff` print the path of their data file when run without `--web`.
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
  `map/command.nim`, so `map` depends on `climbs`, `importer`, `geo` and `selection`.  The page decides the look from
  `kind`, in one style file.

## What holds up

1. **The diagnosis.**  The decision that a bookmark is a reproducible snapshot is what produced `state`, `bits`, the
   worker's pinned address, the redirect, and the argument over contradictory approaches.  Dropping it removes the cause,
   not just the symptoms.  These would go: `--selection` and `--state` of `map` and `ff`; `bits.nim` and its fuzzing; the
   worker's pinned address and the server's redirect; the naming of files by a hash of the address; "made again only if
   the state matches".  This is mostly deletion.
2. **Views do not choose data.**  This is clean, and it is how `activities --select` followed by `map` is already used.
   It settles the TODO item "`map` criteria of its own" (2026-11-13), which goes the other way: that item would be dropped.
3. **Frames contributed through extension points.**  This applies the package rules to display.  `map` would no longer
   depend on `climbs` and `importer`; `climbs` would contribute its frames to `map`.  Today's `map` is the "command that
   knows every kind of layer" that the review in `MAP-LAYERS.md` warned about.
4. **Primary and secondary subjects, with secondary selections ignored.**  A frame's inputs are then one selection plus
   the state of the data it shows, which is as simple as it can be and still describe climbs-for-activities.
5. **The inverted dependency example** states the real rule: a provider sits at or above both of its subjects in the
   dependency graph, so "the activities on the selected climbs" is provided by `climbs`.
6. **The cache key in two parts**: the primary subject's selection, as a hash its owner provides, and the state of what
   the frame shows.  Data can change while a selection stays the same (climbs worked out again, new efforts found), so a
   hash of the selection alone would not do; two parts do.
7. **It covers the open TODO items without special cases**:
   * "the general plot command replaces `ff`" is a plot view of the FF subject;
   * "a calendar of fitness" is a calendar view with an FF frame;
   * the elevation profile of a climb and the lead/lag comparison of rides up a climb are plot views of the climbs subject;
   * "climbs become a layer" is a frame.

## What needs more work

1. **No data-only mode departs from an earlier preference.**  Note (1) says a web view always shows a page.  Earlier the
   author preferred generating input files for plotting and mapping elsewhere (and `ff` is documented as "CSV in the
   cache for plotting elsewhere or on standard output").  Dropping the data file is a change of direction, which may be
   intended; if any export is still wanted, it is an option of the view (`--export PATH`, say), not a mode, and since
   bookmarks no longer pin anything, an exported file is also the only way to keep a picture as it was.  Tests lose
   nothing: a frame is a function and is tested as one.
2. **The row hash: a version is simpler than a hash of the content.**  The proposal has a column on each activity's row
   holding a hash of the other columns and the points array, and the selection's hash as the xor of those.  Three
   problems:
   * the arrays are in tables owned by other packages (`track` by `importer`, `heartrate_series` by `heartrate`), and a
     package may write only its own tables, so no one package can keep a hash of all of it up to date;
   * hashing the points costs a pass over every array, to detect a change that cannot happen (the arrays are never
     changed once written);
   * SQLite has no xor aggregate (nor an xor operator), so the combination would be done in Nim.
   Recommended: a `version` on the activity's row, given when the row is written (a counter shared by all rows, or the
   time of the import) and changed by a trigger whenever the row is updated (a name given later, say).  Since the arrays
   are written once, with the row, the version stands for them.  The hash of a set is then the SHA-256 of the sorted
   `(id, version)` pairs, done in SQL (`group_concat` in id order), which is what `keyOf` does today with other inputs.
   A re-import under new cleaning rules gives new rows and new versions, so a cache that survives a rebuild is not
   misled.
3. **The inverted case can be cached.**  The proposal says `climbs` cannot safely cache "the activities on the selected
   climbs", because it is not told when an activity is deleted.  But no provider is told of anything: caching is by key,
   not by notification.  If the owner of a subject offers the hash of **any set** of its items, not just of the
   selection, then `climbs` can find which activities the frame shows (one query, cheap beside making the GeoJSON) and
   key the frame by the climbs selection's hash and `activities`' hash of that set.  A deleted activity changes the set,
   an updated one its version.  The same function covers global frames (the hash of all activities, for a global heat
   map) and the plain case (the hash of the selection is the hash of the set selected).  So the rule could be: **every
   subject's owner exports `hashOf(set)`; a frame's key is made only of such hashes and the provider's own inputs.**
4. **The provider's own inputs need a key, with a test.**  A frame often reads more than its subjects: the climbs frame
   reads names, the heat frame reads `route_cell`.  Those go into the key too, with a test that changes each table the
   provider reads and checks that the key changes (`map` has such a test today).  That test guards against the class of
   bug "an input missing from the cache key", which is the one bug this design can still have.
5. **Global data as a kind of frame.**  "Combines without selection data from all users" means a frame that reads no
   selection at all, such as a global heat map.  Today's heat layer is per selection, so a global one is a new frame, not
   a change to the existing one.  A frame's declaration could say which selection it uses: the primary's, or none.
6. **Where subjects are declared.**  A view has to list the subjects (for its usage, completion and addresses) without
   importing their owners.  That suggests an extension point `subjects` (name, owner, how to get the selection and
   `hashOf`) that the views read.  (A small point: the project already calls them *extension* points, not expansion
   points.)
7. **Who styles a frame.**  If the page holds the style of every kind, the page becomes the hub again.  Better: each
   provider contributes the style template of its frame next to its data, and the page puts them together.
8. **How frames are named and chosen.**  "Views allow the user to select from the available frames" needs four things:
   * **on the command line**: `--frames FRAME...`, plural and separated by spaces, as the option conventions say;
   * **in the address**: `frames=a,b`, separated by commas, as the same conventions say;
   * **defaults**: each provider could mark its frame as shown by default;
   * **names**: unique within a view and subject, so that `nch map climbs --frames routes` means one thing.
9. **The worker** is out of the proposal's scope, but the migration needs an answer: the server cannot import the views
   (only a `package.nim` imports a command), so something has to make the page in a child process.  Recommended: keep
   `nch VIEW --worker` for now, without the pinned address; it already exists.
10. **Two small effects of live addresses:**
    * an import replaces the selection (`importer/after`), so every open map changes on its next reload (consistent with
      the proposal; worth knowing);
    * a page that fetches its frames in separate requests could mix two selections if one changes while it loads.  One
      request per page avoids that.
11. **FF statistics are new work.**  "Various statistics, selectable" is new functionality, not a port of `ff`.  Which
    command chooses them is open.  It deserves a design note of its own.

## A rough order of migration (not agreed)

1. **Delete the pinning.**  Addresses become live (`/map?frames=routes,climbs`); `bits`, `--state`, `--selection`, the
   redirect and the hashed file names go; the worker stays, without the pinned address.  Nothing visible changes except
   what a bookmark means (and, if decided, the data-only mode).
2. **Add the point `subjects` and the activities subject**: the existing selection, the `version` column and its trigger,
   and `hashOf(set)`.
3. **Add a frames point to `map`**, and move the routes and the heat into their owners as providers, and the climbs, gates
   and efforts into `climbs`.  `map` loses those dependencies, and the style is split by frame.  Global frames (a global
   heat map) fit here, as one more provider.
4. **Caching**: measure first (making everything on every request may be fast enough); then caching per provider, keyed
   as in points 2 to 4 above, if it is needed.
5. **FF statistics as a subject** (after their design note), then a selection of climbs (`climbs --select`) and the
   climbs subject, with the inverted frame (the activities on the selected climbs), then `calendar` on frames.

## Questions for the author

1. **Data-only mode**: is the data file gone for good, or is an `--export` option wanted?
2. **The row hash**: is a `version` (point 2) acceptable in place of a hash of the content?
3. **FF statistics**: which command chooses them?
4. **Listings**: are `nch activities` and `nch climbs` views, or part of managing a subject?  Related: `calendar --all`
   chooses data, which the proposal says views should not do.  Should it become a frame ("all activities, with the
   selection marked")?
5. **Default subject**: should `nch map` default to activities, with `nch map climbs` for the other subject?
