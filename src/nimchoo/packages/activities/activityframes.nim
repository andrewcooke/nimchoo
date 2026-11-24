## The inside of an activity, as a subject (`activity`, beside `activities`): its altitude and its channels (heart rate,
## speed, ...) over its own time, offered to `plot/frames` on the axis of one activity.  The things to show are the selected
## activities, one by one (`pickActivities`, the newest first): the page ticks the newest, and overlays those ticked, each
## from its start.  A line breaks wherever the readings stop for more than `pauseS` (a pause: the device records nothing
## while it is paused), so that a pause is a gap.  (Not at the stretches of `segment`: they join a pause the device made by
## itself, on purpose, for the climbs.)  A frame is made for each channel of the list (`channels/kinds.nim`), so a channel added there is
## drawn here with no more code.

import std/[math, options, strutils, times]
import ../../core/[errors, extension, ids]
import ../channels/[kinds, stored]
import ../db/statement
import ../fit/time
import ../importer/[describe, track]
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

const pauseS* = 15
  ## readings further apart than this are either side of a pause, and the line breaks between them.  **Temporary**: it is
  ## replaced by the pauses the import stores (step 1b of dev/plot-activity.md: `timer_gap`, a pause the device made).  A
  ## device recording every second has no gap while it moves; one on "smart recording" (Garmin's) has gaps of up to about
  ## 10 s (dev/plot-activity.md), which must not break it.

func breakAtPauses*(points: seq[Point]): seq[Point] =
  ## The points with a NaN between two that are more than `pauseS` apart, so that the line breaks across a pause.  In time
  ## order.
  for i, (t, v) in points:
    if i > 0 and t - points[i - 1][0] > pauseS:
      result.add (t, NaN)
    result.add (t, v)

proc seriesOf(points: seq[Point]): PlotData =
  if points.len > 0:
    result.series.add Series(name: "default", points: breakAtPauses(points))

proc makeAltitude(
    st: Session, id: ActivityId
): PlotData {.nimcall, raises: [StoreError].} =
  var points: seq[Point]
  for c in readPositions(st.db, id):
    if c.alt.isSome:
      points.add (int64(c.t), c.alt.get)
  seriesOf(points)

template channelMaker(ch: ChannelKind): MakeActivityPlot =
  proc(st: Session, id: ActivityId): PlotData {.nimcall, raises: [StoreError].} =
    var points: seq[Point]
    for (t, v) in readChannel(st.db, id, ch):
      points.add (int64(t), v)
    seriesOf(points)

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
        channelMaker(chDistance)

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
      tables: @["track"],
      unit: "m",
      mark: mkLine,
      axis: axActivity,
      makeActivity: makeAltitude,
    ),
  )
  let made = makers()
  for ch in ChannelKind:
    let s = specs[ch]
    result.add contribute(
      plotFramePoint,
      PlotFrame(
        subject: activitySubject.name,
        name: frameName(ch),
        summary: "the " & s.title & " of the activity, as the device recorded it",
        shown: ch in shownChannels,
        readsSelection: true,
        tables: @["channel_series"],
        unit: s.unit,
        mark: mkLine,
        axis: axActivity,
        makeActivity: made[ch],
      ),
    )
