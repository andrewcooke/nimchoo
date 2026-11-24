## The inside of an activity, as a subject (`activity`, beside `activities`): its altitude and its channels (heart rate,
## speed, ...) over its own time, offered to `plot/frames` on the axis of one activity.  The things to show are the selected
## activities, one by one (`pickActivities`, the newest first): the page ticks the newest, and overlays those ticked, each
## from its start.  A line breaks at the ride's breaks of the kinds over time (`timeBreaks`: manual, carried, pause, as
## the import stored them in `ride_break`), so that a pause is a gap; not at a blink (noise) nor at a GPS error (nothing
## is missing in time).  A frame is made for each channel of the list (`channels/kinds.nim`), so a channel added there is
## drawn here with no more code.  The speed is drawn in km/h and the distance in km (`shownAs`); the distance is the
## device's, else the distance along the positions, and can be the x axis (`along`): the device's distance does not
## advance while the timer is off, so on that axis every break is a gap of no width.

import std/[math, options, strutils, times]
import ../../core/[errors, extension, ids]
import ../channels/[kinds, stored]
import ../db/statement
import ../fit/time
import ../geo/geo
import ../importer/[describe, stretch, track]
import ../plot/frames
import ../selection/selection
import ../subject/subjects
import ../ui/markup
import ../user/session

{.push raises: [].}

proc pickActivities(st: Session): seq[Pick] {.nimcall, raises: [StoreError].} =
  ## The selected activities, the newest first, each with when it started and what it is called.
  let zone = local()
  for (id, start, place, name) in st.db.query(
    (int64, int64, Option[string], Option[string]),
    """select a.id, a.start_epoch, a.start_place, a.name from activity a
        join activity_selection s on s.activity_id = a.id and s.user_id = :userId
        order by a.start_epoch desc, a.id desc""",
    userId = st.userId,
  ):
    let where = whereText(place.get(""), name.get(""))
    let label =
      dateTimeText(UnixTime(start), zone) & (if where.len > 0: " " & where
      else: "")
    result.add Pick(id: id, start: start, label: label)

proc selected(st: Session): int {.raises: [StoreError].} =
  selectedIds(st).len

const activitySubject* = Subject(
  name: "activity",
  summary: ~"the inside of each selected activity, over its own time (tick them on the page; see `nch activities --select`)",
  isDefault: false,
  selected: selected,
  emptyHint: ~"see `nch activities --select`",
  pick: some[PickList](pickActivities),
)

func breakAt*(points: seq[Point], breaks: seq[Break]): seq[Point] =
  ## The points with a NaN between two that have a break of `timeBreaks` between them (nothing was recorded there), so
  ## that the line breaks.  Both in time order.
  var k = 0
  for i, (t, v) in points:
    if i > 0:
      let before = points[i - 1][0]
      while k < breaks.len and int64(breaks[k].endT) <= before:
        inc k
      var j = k
      while j < breaks.len and int64(breaks[j].startT) < t:
        if breaks[j].kind in timeBreaks:
          result.add (t, NaN)
          break
        inc j
    result.add (t, v)

proc seriesOf(
    st: Session, id: ActivityId, points: seq[Point]
): PlotData {.raises: [StoreError].} =
  if points.len > 0:
    let (_, breaks) = readBreaks(st.db, id)
    result.series.add Series(name: "default", points: breakAt(points, breaks))

proc makeAltitude(
    st: Session, id: ActivityId
): PlotData {.nimcall, raises: [StoreError].} =
  var points: seq[Point]
  for c in readPositions(st.db, id):
    if c.alt.isSome:
      points.add (int64(c.t), c.alt.get)
  seriesOf(st, id, points)

func shownAs*(ch: ChannelKind): tuple[unit: string, factor: float] =
  ## How a channel is drawn: the unit, and what its value (in the channel's own unit) is multiplied by to give it.
  case ch
  of chSpeed:
    ("km/h", 3.6)
  of chDistance:
    ("km", 0.001)
  of chHeartRate, chCadence, chTemperature, chPower:
    (specs[ch].unit, 1.0)

template channelMaker(ch: ChannelKind): MakeActivityPlot =
  proc(st: Session, id: ActivityId): PlotData {.nimcall, raises: [StoreError].} =
    var points: seq[Point]
    let factor = shownAs(ch).factor
    for (t, v) in readChannel(st.db, id, ch):
      points.add (int64(t), v * factor)
    seriesOf(st, id, points)

proc alongPositions*(st: Session, id: ActivityId): seq[Point] {.raises: [StoreError].} =
  ## The distance in metres along the activity's positions (after cleaning), at each of them, adding up within each
  ## stretch of riding and not across a break (a car, a GPS error): for an activity whose device gave no distance.
  var total = 0.0
  for piece in readTrack(st.db, id):
    for i, c in piece:
      if i > 0:
        total += haversine(piece[i - 1].lon, piece[i - 1].lat, c.lon, c.lat)
      result.add (int64(c.t), total)

proc makeDistance(
    st: Session, id: ActivityId
): PlotData {.nimcall, raises: [StoreError].} =
  ## The device's distance, else the distance along the positions (dev/plot-activity.md: the device's is preferred).
  let factor = shownAs(chDistance).factor
  var points: seq[Point]
  for (t, v) in readChannel(st.db, id, chDistance):
    points.add (int64(t), v * factor)
  if points.len == 0:
    for (t, v) in alongPositions(st, id):
      points.add (t, v * factor)
  seriesOf(st, id, points)

proc makers(): array[ChannelKind, MakeActivityPlot] =
  for ch in ChannelKind:
    # (each its own proc: a {.nimcall.} proc cannot hold the channel)
    result[ch] =
      case ch
      of chHeartRate:
        channelMaker(chHeartRate)
      of chCadence:
        channelMaker(chCadence)
      of chTemperature:
        channelMaker(chTemperature)
      of chPower:
        channelMaker(chPower)
      of chSpeed:
        channelMaker(chSpeed)
      of chDistance:
        makeDistance

const shownChannels = {chHeartRate} ## drawn unless told otherwise, with the altitude

func frameName*(ch: ChannelKind): string =
  ## What the user ticks or types: the channel's name as one word ("heartrate").
  specs[ch].name.replace("_", "")

proc contributions*(): seq[Contribution] =
  ## The subject, and its frames: the altitude, then each channel.
  result.add contribute(subjectPoint, activitySubject)
  result.add contribute(
    plotFramePoint,
    PlotFrame(
      subject: activitySubject.name,
      name: "altitude",
      summary: "the altitude of the activity (from its positions, after cleaning)",
      shown: true,
      readsSelection: true,
      tables: @["activity", "ride_break", "track"],
      unit: "m",
      mark: mkLine,
      axis: axActivity,
      makeActivity: makeAltitude,
    ),
  )
  let made = makers()
  for ch in ChannelKind:
    let s = specs[ch]
    let isDistance = ch == chDistance
    result.add contribute(
      plotFramePoint,
      PlotFrame(
        subject: activitySubject.name,
        name: frameName(ch),
        summary:
          "the " & s.title & " of the activity, as the device recorded it" &
          (if isDistance: " (else along its positions); can be the x axis" else: ""),
        shown: ch in shownChannels,
        readsSelection: true,
        tables:
          @["activity", "channel_series", "ride_break"] &
          (if isDistance: @["track"] else: @[]),
        unit: shownAs(ch).unit,
        mark: mkLine,
        axis: axActivity,
        makeActivity: made[ch],
        along: isDistance,
      ),
    )
