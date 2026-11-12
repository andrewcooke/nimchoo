## The selected activities on a map: their routes, the climbs on them, and where they went most (heat).
##
## `nch map` makes everything itself: no layer commands, no layer index.  `--layers routes,climbs,heat` (default routes,climbs)
## says what is drawn: the layers are a set of the address (`layers=`), named in the file's name, and only what is drawn is an
## input of the state (a change to the climbs does not touch a heat map, and a heat map does not work the climbs out).  A GeoJSON
## file in the cache holds the features (each says what it is, in `kind`: route, climb or heat, and nothing about how it looks)
## and a page (Leaflet) decides the look.  **The heat** is squares of the grid of `geo/cells.nim` from the table `route_cell`
## (`importer`), counted over the selected activities at three levels (cells of about 100 m, 870 m and 7 km: `level`), with
## `visits` (how often) and `rides` (by how many activities); the page shows the level that suits the zoom (the style says from
## which), under the routes, shaded on a log scale.  **Gates and efforts** are for looking at how climbs are matched (`--layers routes,efforts,gates` with a few activities selected):
## `gates` draws the start and finish line of each climb the activities went up (the lines a ride has to cross: `climbs/match.nim`
## `gateLines`, the same gates `overPaths` uses), `efforts` the part of each ride between the stored start and finish time of its
## efforts, thick, with a green dot where it starts and a red one where it finishes; where a ride crosses a gate twice (a
## switchback near it) the dots show which crossing the effort used.  `--web` serves the page on localhost (`web`); the address carries the
## activities: `/map?selection=LIST&layers=LIST&state=HASH` (see `selection`).
##
## **The page is three templates**, built in and unpacked to the cache's `system/templates/` where the author edits them (never
## overwritten once changed; delete a file to get the built-in one): `map.html` (the page and its script), `map.css` (the look
## of the page) and `map-style.json` (how routes, climbs and the heat are drawn).  The css and the style are filled in first with the
## palette's colours as tags (`{{blue}}`), then put into the page.  The look: routes are thin red threads, each offset sideways
## by an amount of its own (`spread_m`); climbs are thick transparent grey lines beside the road, in lanes alternating sides so
## that climbs on the same stretch do not overlap, offset in pixels (recomputed on zoom, simplified first so that hairpins do not
## loop); corner cutting (`smooth_rounds`) rounds the lines.  Offers its page to the server (`web/pages`).

import ../../core/[extension, manifest]
import ../web/request
import ./[command, params]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, pageOf(command.commandName, mapSpec()))]

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "climbs", "db", "fit", "geo", "hashing",
    "importer", "selection", "templating", "ui", "user", "web",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the routes of the selected activities and their climbs, on a map",
      run: command.run,
      options: command.options,
    )
  ],
  contributes: contributions,
)
