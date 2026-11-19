## The frames of a map: what the packages that manage a subject contribute for the map to draw.  The map is a view; a frame is a
## layer of data (a GeoJSON file) about a subject, made by the package that knows the subject, so the map needs nothing of the
## packages above it.  This is an extension point of this package (`mapFramePoint`).
##
## A frame says which subject it is a frame of, its name, what it is, whether a map of that subject shows it unless told otherwise,
## whether it reads the selection of the subject, which tables it reads (what it depends on, for a reader and for
## a cache if one is ever wanted; a test checks that the declaration holds every table the frame reads), how to make it (the GeoJSON of the whole
## file, with the notes it has for the user), how it looks (a template of its own, which the user can edit: `style`) and, if it
## needs more than the map's generic drawing, how it is drawn (`script`).  A frame that fails raises `StoreError` with what to say.
##
## **A drawing** is a script template holding one JavaScript function, `(features, ctx) => { ... }`, called by the page once,
## the first time the frame is shown, with the features of its data (which the page fetches from its own address with
## `?frame=NAME`).  `ctx` has `map` and `L` (Leaflet), `name` (the frame's), `style` (its own, filled in), `common`
## (`map-style.json`), `shared` (an object every drawing of the page sees: the routes put their `routesSpreadM` there, for the
## climbs beside them), `helpers` (`text`, `offsetPath`, `smoothPath`, `simplifyPath`, `metresPerDegree`, `metresPerPixel`,
## `rgb`, `mix`: see `page.html`) and `add(layer, z)`.  **Every layer of the frame goes through `add`**, never onto the map
## directly: the page shows and hides a frame (its box in the list of frames) by putting its layers on the map or taking them
## off, in order of `z` (so what is underneath does not depend on the order frames are shown in: the heat 0, climbs 10, routes
## 20, efforts 30, gates 40; the generic drawing 50); a layer whose content changes with the zoom (the heat's levels) is a group
## whose content `update` changes.  It returns `{ bounds, rank, caption, update }`, each optional: the view is fitted to the
## `bounds` of the frames shown when the page opens with the lowest `rank` that have any (routes 1, the others 2, the heat 3);
## `caption` says what is drawn; `update` is called whenever the frame is shown and on every zoom while it is.  **Without a
## script** the frame is drawn from its style alone: lines, polygons and points in `color`, `weight`, `opacity`, `fill_opacity`
## and `radius` (points), with every property in a popup.

import std/options
import ../../core/[errors, extension]
import ../bundle/unpack
import ../user/session

{.push raises: [].}

type
  FrameData* = object ## What a frame made.
    geojson*: string ## a GeoJSON FeatureCollection, the whole file
    notes*: seq[string]
      ## said to the user, a line each ("worked out the climbs of 3 activities: 2 new climbs")

  MakeFrame* = proc(st: Session): FrameData {.nimcall, raises: [StoreError].}
    ## Make the frame from the data as they are now, for the user of the session.

  MapFrame* = object
    subject*: string ## the subject it is a frame of ("activities")
    name*: string
      ## what the user types after `--frames` ("routes"); unique within the subject
    summary*: string ## one line
    shown*: bool ## drawn when `--frames` is not given
    readsSelection*: bool ## whether it is made from the selection of the subject
    tables*: seq[string] ## the tables it reads
    make*: MakeFrame
    style*: Bundle
      ## how it looks: JSON with the groups the page reads, built in and kept in the cache's `system/templates/`, where
      ## the user can change it (its colours are its own)
    styleKeys*: seq[string]
      ## the keys that the style must have, which the drawing reads ("color", "spread_m")
    libraries*: seq[string]
      ## the libraries its drawing uses besides Leaflet (names in the libraries file, `web/libraries.cdn`:
      ## "leaflet-heat-js"), which the page loads, each with its hash
    script*: Option[Bundle]
      ## how it is drawn: a JavaScript function (see above), built in and kept in the cache's `system/templates/`, where the
      ## user can change it; none: the generic drawing

const mapFramePoint* = ExtensionPoint[MapFrame](name: "map/frames")
  ## The frames the packages that manage a subject offer the map.

func framesOf*(all: seq[MapFrame], subject: string): seq[MapFrame] =
  ## The frames of a subject, in the order they were contributed.
  for f in all:
    if f.subject == subject:
      result.add f
