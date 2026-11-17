## The map: a view of a subject, drawn from the frames that the packages managing it contribute.
##
## `nch map [SUBJECT]` (with `--file`, `--frames FRAME...` says which files to make).  The map knows no subject and no kind of data: the point `map/frames` (`frames.nim`) takes
## the frames, each a GeoJSON file about a subject that its provider makes (`activities`: routes and heat; `climbs`: the climbs
## of the activities, their gates and efforts), with a style of its own and a drawing (a JavaScript function) that the provider
## ships, so a new subject or frame is a package that contributes, and nothing here changes, in Nim or in the page.  `subject/subjects` says which subjects there are.  A GeoJSON file for each
## frame goes in the cache (each feature says what it is, in `kind`, and nothing about how it looks: `map-activities-routes.geojson`) and
## the frame's drawing, in a page (Leaflet), decides the look.  Everything is made again on every request: a map is a live view of the selection.  The
## page (`/map/activities`) lists the subject's frames, a box each: the ones ticked are fetched (`?frame=NAME`) and drawn, and the
## browser remembers which are ticked (at first: those marked as shown).  The page is served on localhost (`web`;
## `--file` makes the files only, and prints their paths).
##
## **The page is templates**, built in and unpacked to the cache's `system/templates/` where the author edits them (never
## overwritten once changed; delete a file to get the built-in one): `map.html` (the page and its script, which knows no
## frame: it fetches each frame's file, calls the frame's drawing, fits the view and offers the drawings generic helpers),
## `map.css` (the look of the page), `map-style.json` (the corner cutting, `smooth_rounds`) and, for each frame, a style and a
## drawing shipped by its provider (`activities-map-routes.json`, `activities-map-routes.js` ...; a frame with no drawing is
## drawn generically from its style: `frames.nim` has the contract).  The css and the styles are filled in first with the
## palette's colours as tags (`{{blue}}`), then put into the page.  `geojson.nim` writes a file of features, for the providers.
## Offers its page to the server (`web/pages`).

import ../../core/[extension, manifest]
import ../web/request
import ./[command, frames, params]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, pageOf(command.commandName, mapSpec(), isWord))]

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "db", "subject", "templating", "ui", "user",
    "web",
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
