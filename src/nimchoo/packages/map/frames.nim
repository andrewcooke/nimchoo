## The frames of a map: what the packages that manage a subject contribute for the map to draw.  The map is a view; a frame is a
## layer of data (a GeoJSON file) about a subject, made by the package that knows the subject, so the map needs nothing of the
## packages above it.  This is an extension point of this package (`mapFramePoint`).
##
## A frame says which subject it is a frame of, its name, what it is, whether a map of that subject shows it unless told otherwise,
## whether it reads the selection of the subject, which tables it reads (what it depends on, for a reader and for
## a cache if one is ever wanted; a test checks that the declaration holds every table the frame reads), how to make it (the GeoJSON of the whole
## file, with the notes it has for the user) and how it looks (a template of its own, which the user can edit: `style`).  A frame
## that fails raises `StoreError` with what to say.

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
      ## the user can change it; filled in with the palette's colours first (`{{{red}}}`)
    styleKeys*: seq[string]
      ## the "group.key" that the style must have, which the page reads

const mapFramePoint* = ExtensionPoint[MapFrame](name: "map/frames")
  ## The frames the packages that manage a subject offer the map.

func framesOf*(all: seq[MapFrame], subject: string): seq[MapFrame] =
  ## The frames of a subject, in the order they were contributed.
  for f in all:
    if f.subject == subject:
      result.add f
