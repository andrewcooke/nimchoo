# A critique of the display architecture, second version (2026-11-13)

A response to `dev/display-arch.md` (the version with the motivation, primary and secondary subjects, and the notes on FF
statistics and data ownership), written by the assistant after reading it with the code (`map`, `ff`, `calendar`,
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
4. **Primary and secondary subjects** describe the climbs-for-activities case well.
5. **The cache key in two parts**: the primary subject's selection, as a hash its owner provides, and the secondary
   subject's state, which the provider knows.  Data can change while a selection stays the same (climbs worked out
   again, new efforts found), so a hash of the selection alone would not do; two parts do.
6. **It covers the open TODO items without special cases**:
   * "the general plot command replaces `ff`" is a plot view of the FF subject;
   * "a calendar of fitness" is a calendar view with an FF frame;
   * the elevation profile of a climb and the lead/lag comparison of rides up a climb are plot views of the climbs subject;
   * "climbs become a layer" is a frame.

## What needs more work

1. **What the primary hash must cover.**  It must cover the *content* of the selection, not just which items are in it.
   Today's `contentKey` hashes each file's SHA-256 and session.  That is not enough once derived data change while the
   files stay the same.  For example, a re-import under new cleaning rules gives the same files and the same ids but
   different routes, and the cache is a separate directory, so it survives the rebuild.  Recommended: the owner's hash
   covers the ids plus something that changes whenever that subject's derived data are rewritten, such as the time each
   activity was imported.
2. **"Local knowledge" should be a key, with a test.**  A provider often reads beyond its own subject: the climbs frame
   reads names, the heat frame reads `route_cell`.  So the provider's knowledge of the secondary subject's state should be
   a concrete key it computes, with a test that changes each table the provider reads and checks that the key changes
   (`map` has such a test today).  That test guards against the class of bug "an input missing from the cache key", which
   is the one bug this design can still have.
3. **"Close to the frame's subject" conflicts with the dependency graph.**  Take a map of climbs with the routes of the
   rides that went up them.  The frame shows activities, so the rule in the proposal puts its provider near `activities`
   or `importer`.  But it needs the climbs selection, and `climbs` already depends on `activities`, so that would be a
   cycle.  The provider has to be `climbs`, which is close to the primary subject, not the frame's.  The general rule is
   that a provider sits at or above both of its subjects in the dependency graph.  Better to state that.
4. **What a secondary subject's selection means.**  In "climbs for the selected activities", the climbs selection is
   ignored.  Is that always so, or could a frame use both selections (the selected climbs, limited to the selected
   activities)?  Recommended: never.  That keeps a frame's inputs at one selection plus local state.
5. **Global data is a third kind of frame.**  "Combines without selection data from all users" means a frame that reads no
   selection at all, such as a global heat map.  Its cache key is the provider's key only.  Today's heat layer is per
   selection, so a global one is a new frame rather than a change to the existing one.  A frame's declaration could say
   which selection it uses: the primary's, or none (global).
6. **Where subjects are declared.**  A view has to list the subjects (for its usage, completion and addresses) without
   importing their owners.  That suggests an extension point `subjects` (name, owner, how to get the selection and its
   hash) that the views read.  (A small point: the project already calls them *extension* points, not expansion points.)
7. **Who styles a frame.**  If the page holds the style of every kind, the page becomes the hub again.  Better: each
   provider contributes the style template of its frame next to its data, and the page puts them together.
8. **How frames are named and chosen.**  "Views allow the user to select from the available frames" needs four things:
   * **on the command line**: `--frames FRAME...`, plural and separated by spaces, as the option conventions say;
   * **in the address**: `frames=a,b`, separated by commas, as the same conventions say;
   * **defaults**: each provider could mark its frame as shown by default;
   * **names**: unique within a view and subject, so that `nch map climbs --frames routes` means one thing.
9. **Two small effects of live addresses:**
   * an import replaces the selection (`importer/after`), so every open map changes on its next reload (consistent with
     the proposal; worth knowing);
   * a page that fetches its frames in separate requests could mix two selections if one changes while it loads.  One
     request per page avoids that.
10. **FF statistics are new work.**  "Various statistics, selectable" is new functionality, not a port of `ff`.  Which
    command chooses them is open.  It deserves a design note of its own.

## A rough order of migration (not agreed)

1. **Delete the pinning.**  Addresses become live (`/map?frames=routes,climbs`); `bits`, `--state`, `--selection`, the
   redirect and the hashed file names go.  Nothing visible changes except what a bookmark means.
2. **Add the point `subjects` and the activities subject**, from the existing selection, with the hash of point 1 above.
3. **Add a frames point to `map`**, and move the routes and the heat into their owners as providers, and the climbs, gates
   and efforts into `climbs`.  `map` loses those dependencies, and the style is split by frame.  Global frames (a global
   heat map) fit here, as one more provider.
4. **Caching**: measure first (making everything on every request may be fast enough); then caching per provider, keyed
   as in points 1 and 2 above, if it is needed.
5. **FF statistics as a subject** (after their design note), then a selection of climbs (`climbs --select`) and the
   climbs subject, then `calendar` on frames.

## Questions for the author

1. **Secondary selections**: is a secondary subject's selection always ignored (point 4)?
2. **FF statistics**: which command chooses them?
3. **Listings**: are `nch activities` and `nch climbs` views, or part of managing a subject?  Related: `calendar --all`
   chooses data, which the proposal says views should not do.  Should it become a frame ("all activities, with the
   selection marked")?
4. **Default subject**: should `nch map` default to activities, with `nch map climbs` for the other subject?
