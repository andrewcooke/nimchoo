## The routes of the selected activities and the climbs they went up, on a map.
##
## `nch map` makes everything itself: no layer commands, no layer index.  A GeoJSON file in the cache holds the routes and
## climbs (each feature says what it is, in `kind`: route or climb, and nothing about how it looks) and a page (Leaflet) decides
## the look.  `--web` serves the page on localhost (`web`); the address carries the activities: `/map?bits=LIST&check=HASH`
## (see `selection`).
##
## **The page is three templates**, built in and unpacked to the cache's `system/templates/` where the author edits them (never
## overwritten once changed; delete a file to get the built-in one): `map.html` (the page and its script), `map.css` (the look
## of the page) and `map-style.json` (how routes and climbs are drawn).  The css and the style are filled in first with the
## palette's colours as tags (`{{blue}}`), then put into the page.  The look: routes are thin red threads, each offset sideways
## by an amount of its own (`spread_m`); climbs are thick transparent grey lines beside the road, in lanes alternating sides so
## that climbs on the same stretch do not overlap, offset in pixels (recomputed on zoom, simplified first so that hairpins do not
## loop); corner cutting (`smooth_rounds`) rounds the lines.  Offers its page to the server (`web/pages`).

import ../../core/[extension, manifest]
import ../web/request
import ./[command, params]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, pageOf(command.commandName, mapSpec(), "bits"))]

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "climbs", "db", "fit", "hashing", "importer",
    "selection", "templating", "ui", "user", "version", "web",
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
