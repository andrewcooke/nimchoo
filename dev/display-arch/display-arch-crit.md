# A critique of the display architecture (2026-11-13)

A response to `dev/display-arch.md`, written by the assistant after reading it with the code (`map`, `ff`, `calendar`,
`web`, `selection`), `dev/MAP-LAYERS.md` and the rules on addresses and state in `dev/HISTORY.md` (2026-11-12) and
`TODO.md`.  For discussion; nothing here is agreed.

## The display architecture today

* **Views are commands**: `map` (GeoJSON shown with Leaflet, on the web), `ff` (CSV shown with Observable Plot, on the
  web), `calendar` (in the terminal).  The listings in `activities` and `climbs` are views too, in practice.
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

## What the proposal changes

The central change is that **a bookmark follows the selection instead of pinning data**.  That reverses the 2026-11-12
requirement.  It is deliberate (the proposal calls that machinery "nonsense"), but it is the biggest change here, so it is
said plainly.  These would go:

* `--selection` and `--state` of `map` and `ff`;
* `bits.nim` and its fuzzing;
* the worker's pinned address and the server's redirect to it;
* the naming of files by a hash of the address;
* "made again only if the state matches".

This is mostly deletion, and it is the best part of the proposal.

## What holds up

1. **Views do not choose data.**  This is clean, and it is how `activities --select` followed by `map` is already used.
   It settles the TODO item "`map` criteria of its own" (2026-11-13), which goes the other way: that item would be dropped.
2. **Frames contributed through extension points.**  This applies the package rules to display.  `map` would no longer
   depend on `climbs` and `importer`; `climbs` would contribute its frames to `map`.  Today's `map` is the "command that
   knows every kind of layer" that the review in `MAP-LAYERS.md` warned about.
3. **It covers the open TODO items without special cases**:
   * "the general plot command replaces `ff`" is a plot view of the ff subject;
   * "a calendar of fitness" is a calendar view with an ff frame;
   * the elevation profile of a climb and the lead/lag comparison of rides up a climb are plot views of the climbs subject;
   * "climbs become a layer" is a frame.

## What needs more work

1. **A hash of the selection is not enough as a cache key.**  The data can change while the selection stays the same:
   climbs worked out again or renamed, new efforts found, a cleaning rule changed.  A cache keyed only on the selection
   would then serve stale frames.  A provider's key has to be (the hash of the selection, a key of the data that provider
   reads).  That is today's `stateKey` and its tests ("each table it reads changes the state") moved into each provider, so
   that work is not wasted: it just stops being part of the address.  Alternatively, start with no cache at all and measure.
   Making everything on every request may be fast enough.
2. **Frame providers and the dependency graph.**  A package can provide frames only for subjects whose owner is below it.
   `climbs` can provide a frame for the activities subject, because it already depends on `activities`.  But "the routes
   of the activities that rode the selected climbs" cannot come from `importer` or `activities` (that would be a cycle);
   `climbs` would have to provide it.  Workable, but it should be stated as a rule.
3. **Where subjects are defined.**  A view has to list the subjects (for its usage, completion and addresses) without
   importing their owners.  That suggests an extension point `subjects` (name, owner, how to get the selection and its
   hash) that the views read.  (A small point: the project already calls them *extension* points, not expansion points.)
4. **Who styles a frame.**  If the page holds the style of every kind, the page becomes the hub again.  Better: each
   provider contributes the style template of its frame next to its data, and the page puts them together.
5. **The "selection" of ff is really parameters** (a model, time constants, perhaps a range of dates), not a set of rows.
   That is fine, but "selection" then means "the subject's current state", and something has to set it: `nch ff
   --select ...`, or `models`?
6. **Two small effects of live addresses:**
   * an import replaces the selection (`importer/after`), so every open map changes on its next reload (consistent with
     the proposal; worth knowing);
   * a page that fetches its frames in separate requests could mix two selections if one changes while it loads.  One
     request per page avoids that.

## A rough order of migration (not agreed)

1. **Delete the pinning.**  Addresses become live (`/map?frames=routes,climbs`); `bits`, `--state`, `--selection`, the
   redirect and the hashed file names go.  Nothing visible changes except what a bookmark means.
2. **Add the point `subjects` and the activities subject**, from the existing selection and `contentKey`.
3. **Add a frames point to `map`**, and move the routes and the heat into their owners as providers, and the climbs, gates
   and efforts into `climbs`.  `map` loses those dependencies, and the style is split by frame.
4. **Caching**: measure first; then caching per provider, keyed as in point 1 above, if it is needed.
5. **`ff` becomes a plot view with an ff subject.**  Then a selection of climbs (`climbs --select`) and the climbs subject,
   then `calendar` on frames.

## Questions for the author

1. **Pinned bookmarks**: are they dropped entirely, with the exported GeoJSON or CSV file as the only snapshot?
2. **The ff subject**: is its "selection" a set of parameters, and which command sets it?
3. **Listings**: are `nch activities` and `nch climbs` views, or part of managing a subject?  Related: `calendar --all`
   chooses data, which the proposal says views should not do.  Should it become a frame ("all activities, with the
   selection marked")?
4. **Default subject**: should `nch map` default to activities, with `nch map climbs` for the other subject?
