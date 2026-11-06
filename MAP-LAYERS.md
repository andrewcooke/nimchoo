# Maps, layers and plots: a design under discussion (2026-11-06)

Status: **ideas only, nothing is built.**  The author wants to think about it first ("this is very new").  Nothing in the
code depends on it.  When a decision is made, move it to TODO.md and AGENTS.md.

**Decision (same day): the layer ideas are set aside.**  `nch map` makes the routes and the climbs itself; the address carries the activities as `bits` and a `check`; file names are proquints of a hash of the request.  See AGENTS.md, "the map and its addresses".  **After the review below the author's view was that the whole thing is too complex for now.**  The most useful
result of the review is a question that stands on its own: climb names are mutable (see "Mutable names" at the end).

## Where things are now

* `nch heatmap` writes the routes of the selected activities as one GeoJSON file in the cache and shows them on a web page
  (Leaflet, `src/nimchoo/heatmap/page.html`).  The GeoJSON holds only geometry and a few properties per route (`id`,
  `start`, `sport`, `distance_m`).
* The "heat" is not in the file.  It is one line in the page: `style: { color: '#c2185b', weight: 2, opacity: 0.25 }`
  (thin, magenta, 25% opaque: where rides overlap the transparent lines add up and glow).
* `--style lines` is the only style; it changes nothing but the cache file name.
* `ff` makes a CSV and a separate chart page (fitness and fatigue).  Plots are a different kind of thing from the map.

## What the author wants (the questions asked)

* Rename `heatmap` to `map` and extend it.
* Mark the climbs on the map; name them; add labels.
* Different lines in different colours.
* Understand how much goes into the GeoJSON and how much elsewhere, given the architecture (layer 1: commands write files;
  layer 2: a simple local server shows them; see AGENTS.md, "display").

## What GeoJSON can and cannot carry

* Any mix of geometries in one file (lines for routes and climbs, points for markers) and any properties.  Climbs have a
  stored route (3D, with altitude) that can be a line feature.
* GeoJSON has **no styling of its own**.  There is a convention, *simplestyle* (`stroke`, `stroke-width`,
  `stroke-opacity`, `marker-color`, `title`), that some other viewers honour (geojson.io and others; not tested here).

## The separation the author prefers (agreed in principle)

* **GeoJSON files are layers carrying logical information, not graphical**: what each feature is (`kind`: route, climb,
  landmark), its name, category, sport, whether it is selected, and so on.  No colours, widths or opacities.
* **The HTML page (Leaflet) renders them**: a style function maps the logical properties to a look (the heat for routes,
  climbs coloured by category, the selection in blue), builds labels (tooltips on hover; permanent labels only when asked
  or zoomed in, since 179 climbs would crowd), and a layer toggle and legend.
* The palette values (`ui/palette.nim`, `hex(blue)` ...) are given to the page template so the colours match the terminal
  (the fitness chart already does this).  The page template is unpacked into the cache's `system/templates/`, so the
  author can restyle without recompiling.
* Cost: opened in another program the files look plain.  If styled exports are ever wanted, an `--export-style` option could
  add simplestyle properties on top.
* Alternative that was set aside: Nim writing colours into the files (simplestyle).  Portable to other viewers, but mixes
  logic and look.

## Who makes the layers (alternatives)

1. **`map` makes everything itself** by calling library functions owned by the modules (routes from the importer, climbs
   from the climbs module, landmarks from the landmark module).  Simple, one command, but `map` knows how every layer is
   made.
2. **Each command makes its own layer** (preferred; it is what AGENTS.md's display section says): `activities --geojson`
   (the routes), `climbs --geojson` (the climbs; same `--name` / `--all` words as the listing), `landmarks --geojson`.
   `map` is then mostly a viewer of layer files, and for the defaults it runs the other commands as separate programs
   (as the server does) and uses the paths they print, which keeps the rule that only the dispatcher imports commands.
   Layers can be mixed and matched, and a GeoJSON file from outside nimchoo could be a layer too.

## The usability problem: the file names

Cache file names encode the options (`heatmap--key-ab12--style-lines.geojson`) and are far too long to type.  Ways round it:

* **Short layer names** for the common case: `nch map` shows the default layers (routes and climbs of the selection);
  `nch map routes climbs landmarks` picks layers by short name (the commands' own names).
* **A "current map" scratchpad** in the database, like the selection: `nch climbs --name farellones --map` adds a layer;
  `nch map` shows the current map; `nch map --clear`.
* **Choosing in the browser**: a layer panel in the page; the server makes layers when ticked.  Most work; later.

## The layer index (the author's proposal, preferred)

Instead of a scratchpad: **an index of all layers in the database.**  The cache is then only a cache: a layer is a
*definition* and its files can be made again if the cache is cleaned.

* A layer record: a short name (typed by the user), the command that makes it and its arguments (canonical form, the same
  string used for cache file names), whether it is shown, its drawing order, its owner (per user, like the selection).
* `nch climbs --name farellones --layer farellones` runs the listing and saves the layer (shown by default).
* A plural command, as the command theory says for types in the database: `nch layers` lists them (shown ones marked);
  `nch layers --edit NAME --show | --hide`; `nch layers --delete NAME -f`.
* `nch map` draws the shown layers.  `routes`, `climbs` and `landmarks` exist from the start, so `nch map` works with no
  setup (routes and climbs of the selection shown by default).
* Needs: one migration (`layer` table), the `layers` command, `--layer NAME` on the layer-producing commands, the page.

## Saving the selection

The index makes it natural to save selections.  Decision so far: **the user never names a selection; only layers are named.**

* When a layer is made from a selection, the database keeps the set of activities it used, as an internal **snapshot**
  linked to the layer.  It is keyed by the selection's existing key (a hash of its activities, `selection/selection.nim`),
  so identical selections share one snapshot; snapshots no layer uses are removed when layers are deleted; deleted
  activities drop out of them.
* A layer is rebuilt from its definition and snapshot, so it comes out the same.
* Alternatives considered for what a saved selection *is*: a **snapshot** of ids (chosen: simple, stable), a **saved
  search** (criteria re-evaluated each time: follows new imports but can change under a layer), or **both**.
* Open: **frozen or live layers.**  A layer made with `--layer NAME` is frozen to the selection at that moment (run the
  command again to replace it); the built-in `routes` and `climbs` layers would follow the current selection and be
  rebuilt when it changes.  The author has not confirmed this split.
* A related idea: `activities --selection NAME`-style searches among a saved selection were discussed when selections were
  to be named; with internal snapshots they are not needed.  `previous` (the selection before) is a one-step history that
  snapshots would make explicit.

## Maps and plots

* A **map layer** is geographic features (GeoJSON) drawn on a map.  A **plot layer** is a series of x/y values (time against
  fitness; distance along a climb against elevation) drawn on axes.  The two cannot share a canvas.
* They can share the **idea**: definitions in the database, rebuildable files in the cache, short names, a list you turn on
  and off, a page that loads the shown layers with a style function and the palette.  The layer record would carry a format
  (GeoJSON or series); two viewers (`map` and a plot command) over one index, each drawing only the layers of its format.
* Plots wanted: the elevation profile of a climb, the lead/lag comparison of rides up a climb (time gap by distance), the
  fitness and fatigue curves (`ff`, which would be adopted later).  Several rides' profiles could be overlaid in one plot,
  each a layer.
* A later idea, not to design for now: a page with a map and a profile linked, so that pointing at the profile highlights
  the place on the map.

## Suggested order, if it goes ahead (not agreed)

1. Rename `heatmap` to `map`; move the look into a style function in the page keyed on `kind` and the other properties
   (nothing changes visibly).
2. `--geojson` on `activities` and `climbs` with logical properties; the climbs layer coloured by category.
3. The layer table, snapshots and the `layers` command; `--layer NAME`.
4. Layer toggle and legend, then labels, then landmarks.
5. Plots later, on the same index.

## Open questions

* One file for all layers or one file per layer?  (One per layer is better for reuse and for other programs; one file is
  simpler.  The layer index assumes one per layer.)
* Frozen or live layers (above).
* How to name layers made without a name (a default from the arguments?).
* Whether the colour logic stays entirely in the page (agreed so far) or an export style is ever added.

# A critical review (2026-11-06)

Written at the author's request, "with a reviewer's hat on", by the same assistant that wrote the ideas above (so it is
marking its own homework).  Two things were checked against the code and data: the server pins the data in the address
(`serve/request.nim`, the `pin` of a rule; `selection/selection.nim` makes the key as a hash of the activities' file
checksums), and the size of the data as GeoJSON: **all 1,108 routes simplified to 5 m: 17.3 MB** (135 MB unsimplified), **the
179 climbs: 1.4 MB**.

## Verdict

The core idea (files carry logical properties; the page decides the look) is sound.  The layer index, the snapshots and the
shared map/plot machinery are a lot of infrastructure for a problem that has not shown up yet, and they conflict with some of
the project's own principles.

## Serious problems

1. **The index brings back hidden state.**  The server pins what a page shows in the address, so a reload shows the same data;
   AGENTS.md's display section already warns that implicit state conflicts with caching.  Shown/hidden flags and live layers
   put the answer in the database: `/map` no longer says what it displays, two browser tabs share (and fight over) the state,
   a bookmark stops meaning anything.
2. **Stored command lines die with every interface change.**  A layer holds "the command and its arguments"; the project's rule
   is no backward compatibility, and the commands were renamed wholesale on the same day this was written.  Stored layers
   would need migrations of command strings, or be thrown away each time.  That is a macro system: a big commitment.
3. **"Rebuild from the definition gives the same result" is false for climbs.**  Snapshots freeze the activities, but climb
   names are not stable: the `(n/m)` numbers are worked out at display time, so new climbs, retiring or renaming change what
   `--name "farellones (2/3)"` means; `--latest` and `previous` are relative.  A layer saved by name silently changes meaning.
   To be reproducible it needs stable climb ids, i.e. a second snapshot (of climbs), which makes problem 1 worse.
4. **Cache invalidation is missing.**  Cache files are keyed by options and the selection key only.  A climbs file does not
   change when climbs are renamed, retired or re-derived; a deleted activity stays in an old routes file.  "Regenerate if the
   file is missing" is not enough: a data version would have to be part of every layer's key.
5. **Frozen and live layers can disagree on one screen**: frozen routes next to live climbs of a different set of rides is a
   misleading picture.
6. **The page becomes a hub that knows every kind of layer.**  The style function must know `route`, `climb`, `landmark` and
   every kind to come: each new layer means editing the page (JavaScript), against "each module is independent"; if a layer
   carries its own style instead, the logical/graphical split is gone.  And it is the most complicated logic in the system in
   the one language the project does not test.
7. **Running commands as subprocesses on page load has hidden costs.**  `climbs --geojson` can trigger `ensureClimbs` (about a
   minute the first time) and name downloads: a page load would wait on that, with no progress and probably a timeout; two
   processes can meet database locks; and the server's security model is a strict allow-list of commands and options taken
   from the address: arguments stored in the database would bypass it or need the same list.

## Medium problems

8. **Plots and maps share an idea, not code.**  A plot is per climb with its own parameters; two viewers over one index is
   speculative generalisation.  It also puts infrastructure ahead of what the author wants (comparing rides up a climb), which
   is a plot, and layers do not help it.
9. **Size and speed are not covered** (the numbers above): the browser fetches, parses and draws that for each layer, and
   nothing simplifies by zoom level.
10. **The command grammar gets cluttered**: `activities` already has select, delete, import and the criteria; `--geojson` (an
    output format) and `--layer NAME` (an action that saves a definition) break "TYPE [which ones] [action]".
11. **"Built-in layers from the start"** needs rows seeded for every user, including later ones (migrations are plain DDL; data
    is inserted from Nim): unanswered.
12. **Smaller claims are untested**: other viewers honouring simplestyle; an outside GeoJSON file as a layer (it has no `kind`:
    the style function needs defaults); line labels need placement logic, and 179 climbs crowd, and `(n/m)` text in names shifts.

## What holds up

* Logical properties in the files, the look in the page (matches the two-layer architecture).
* The content-hash selection key as a stable identity for snapshots.
* One file per layer, if layers exist at all.

## What the review suggests instead

Skip the layer index and the snapshots for now.  Add `--climbs` and a `kind` property to the existing `heatmap`, with a small
style function in the page (about a day with tests).  Short layer names (`nch map routes climbs`) would cover the typing
problem for the common case.  Add an index only when real friction shows (three or more layers; a custom layer worth keeping).
Build the elevation profile and the lead/lag comparison as ordinary plot commands.

Questions the review could not answer: does the author want to keep custom layers at all, or is "the selection plus a few
climbs" enough?  Is the map fast enough with 17 MB of routes in the browser (not tried)?

## Mutable names (the author's reaction: the most useful point)

The review showed that a climb's name, as the user sees and types it, is **not an identity**: `Farellones (2/3)` is made at
display time from the name and the climb's rank by gain among those sharing the name, so finding a new climb, retiring one or
renaming one can change which climb a name means.  Anything that stores or remembers a name (a saved layer, a script, a
note, `--name "farellones (2/3)"` typed last week) can silently point at something else.  The author is "really questioning
mutable names" and thinks something should be done about it whatever happens to the map.  Not yet discussed: what a stable
handle for a climb could be (a short stable id shown with the name; ids that never change and are never reused; a name that
is frozen once given; the numbering made stable by never renumbering), and how `--edit NAME` and `--name` would use it.
