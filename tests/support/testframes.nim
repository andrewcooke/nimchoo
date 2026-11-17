## A subject and some map frames that belong to no package: what the map is tested with, to show that it needs nothing of the
## packages above it (the real ones are tested with their providers: tests/activities/test_mapframes.nim and
## tests/climbs/test_mapframes.nim).

import std/strutils
import nimchoo/core/[errors, extension]
import nimchoo/packages/bundle/unpack
import nimchoo/packages/db/statement
import nimchoo/packages/map/frames
import nimchoo/packages/subject/subjects
import nimchoo/packages/user/session

proc selectedCount(st: Session): int {.raises: [StoreError].} =
  st.db.scalar(
    int, "select count(*) from selection where user_id = :userId", userId = st.userId
  )

proc makeAlpha(st: Session): FrameData {.raises: [StoreError].} =
  ## One point for each activity in the selection.
  var fs: seq[string]
  for i in 0 ..< selectedCount(st):
    fs.add "{\"type\":\"Feature\",\"properties\":{\"kind\":\"alpha\",\"n\":" & $i &
      "},\"geometry\":{\"type\":\"Point\",\"coordinates\":[" & $i & ",0]}}"
  FrameData(
    geojson: "{\"type\":\"FeatureCollection\",\"features\":[" & fs.join(",") & "]}\n",
    notes: @["a note from alpha"],
  )

proc makeBeta(st: Session): FrameData {.raises: [StoreError].} =
  FrameData(geojson: "{\"type\":\"FeatureCollection\",\"features\":[]}\n")

proc makeGlobal(st: Session): FrameData {.raises: [StoreError].} =
  ## A frame that reads no selection.
  FrameData(geojson: "{\"type\":\"FeatureCollection\",\"features\":[]}\n")

proc makeBroken(st: Session): FrameData {.raises: [StoreError].} =
  raiseStore("the broken frame cannot be made")

proc frame(name: string, shown: bool, make: MakeFrame): MapFrame =
  MapFrame(
    subject: "things",
    name: name,
    summary: "the " & name & " frame",
    shown: shown,
    readsSelection: true,
    tables: @["selection"],
    make: make,
    style: Bundle(
      name: "templates/test-map-" & name & ".json",
      data: "{ \"" & name & "\": { \"colour\": \"{{{red}}}\" } }",
    ),
    styleKeys: @[name & ".colour"],
  )

proc globalFrame(): MapFrame =
  result = frame("global", false, makeGlobal)
  result.readsSelection = false
  result.tables = @[]

proc testExtensions*(): Extensions =
  ## The subject `things` (the default) with the frames `alpha` (shown), `beta` and `broken`.
  result.add contribute(
    subjectPoint,
    Subject(
      name: "things",
      summary: "the things",
      isDefault: true,
      selected: selectedCount,
      emptyHint: "select some things",
    ),
  )
  result.add contribute(mapFramePoint, frame("alpha", true, makeAlpha))
  result.add contribute(mapFramePoint, frame("beta", false, makeBeta))
  result.add contribute(mapFramePoint, frame("broken", false, makeBroken))
  result.add contribute(mapFramePoint, globalFrame())
