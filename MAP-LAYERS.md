# Maps, layers and plots: a design under discussion (2026-11-06)

Status: **ideas only, nothing is built.**  The author wants to think about it first ("this is very new").  Nothing in the
code depends on it.  When a decision is made, move it to TODO.md and AGENTS.md.

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
