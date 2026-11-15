## The map: a view of a subject, drawn from the frames that the packages managing it contribute.
##
## `nch map [SUBJECT] [--frames FRAME...]`.  The map knows no subject and no kind of data: the point `map/frames` (`frames.nim`) takes
## the frames, each a GeoJSON file about a subject that its provider makes (`activities`: routes and heat; `climbs`: the climbs
## of the activities, their gates and efforts), with a style of its own that the provider ships, so a new subject or frame is a
## package that contributes, and nothing here changes.  `subject/subjects` says which subjects there are.  A GeoJSON file for each
## frame goes in the cache (each feature says what it is, in `kind`, and nothing about how it looks: `map-activities-routes.geojson`) and
## a page (Leaflet) decides the look.  Everything is made again on every request: a map is a live view of the selection, and a
## bookmark (`/map/activities?frames=routes,climbs`) keeps the frames and not the data.  The page is served on localhost (`web`;
## `--file` makes the files only, and prints their paths).
##
## **The page is templates**, built in and unpacked to the cache's `system/templates/` where the author edits them (never
## overwritten once changed; delete a file to get the built-in one): `map.html` (the page and its script), `map.css` (the look
## of the page), `map-style.json` (the corner cutting, `smooth_rounds`) and a style for each frame, shipped by its provider
## (`activities-map-routes.json` ...).  The css and the styles are filled in first with the palette's colours as tags (`{{blue}}`),
## then put into the page.  The look: routes are thin red threads, each offset sideways by an amount of its own (`spread_m`);
## climbs are thick transparent grey lines beside the road, in lanes alternating sides so that climbs on the same stretch do not
## overlap, offset in pixels (recomputed on zoom, simplified first so that hairpins do not loop); corner cutting rounds the lines.
## `lines.nim` writes the features, as a library for the providers.  Offers its page to the server (`web/pages`).

import ../../core/[extension, manifest]
import ../web/request
import ./[command, frames, params]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, pageOf(command.commandName, mapSpec(), isWord))]

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "db", "fit", "geo", "subject", "templating",
    "ui", "user", "web",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "a subject (by default the selected activities) on a map",
      run: command.run,
      options: command.options,
    )
  ],
  defines: @[
    PointDecl(
      name: mapFramePoint.name,
      summary:
        "the frames of a map, contributed by the packages that manage a subject: a GeoJSON file of the subject and its style",
    )
  ],
  contributes: contributions,
)
