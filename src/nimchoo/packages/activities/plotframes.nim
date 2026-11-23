## The frame of the activities on a plot (`plot/frames`): the impulse of the selected activities each day, worked out with
## the first selected model (by name: the author's choice, 2026-11-23), as bars.  It follows the activity selection, not the
## model's tags.  The impulses that are lacking are worked out first (`model`, in a transaction of its own).

import std/[algorithm, options, strformat, tables]
import ../../core/[errors, extension, line]
import ../db/[statement, store]
import ../model/[calc, curve, impulses, models]
import ../plot/frames
import ../user/session

{.push raises: [].}

proc makeImpulse(
    st: Session, period: Period
): PlotData {.nimcall, raises: [StoreError].} =
  let ms = selectedModels(st.db, st.userId)
  if ms.len == 0:
    result.warnings.add plain(
      "no model is selected, so there is no impulse to show (see `nch models --select`)"
    )
    return
  let m = ms[0]
  if fthrOf(st.db, st.userId).isNone:
    raiseStore(
      fmt"{st.userName} has no FTHR, which the impulses need (set it with `nch users --edit {st.userName} --fthr BPM`)"
    )
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      discard calculateMissing(st.db, st.userId, m)
  )
  var byDay: Table[int64, float] # the start of the day -> the sum of its impulses
  for (t, v) in st.db.query(
    Lump,
    """select i.centre_t, i.value from impulse i
        where i.model_id = :model and i.value > 0
          and i.activity_id in (select activity_id from activity_selection where user_id = :user)""",
    model = m.id,
    user = st.userId,
  ):
    let day = dayStart(civilOf(t, period.zone), period.zone)
    byDay.mgetOrPut(day, 0.0) += v
  var s = Series(name: m.name)
  for d, v in byDay.pairs:
    if period.inPeriod(d):
      s.points.add (d, v)
  s.points.sort()
  result.series.add s

proc contributions*(): seq[Contribution] =
  ## The frame of the activities, offered to the plot.
  @[
    contribute(
      plotFramePoint,
      PlotFrame(
        subject: "activities",
        name: "impulse",
        summary:
          "the impulse of the selected activities each day, by the first selected model",
        shown: true,
        readsSelection: true,
        tables: @[
          "activity", "activity_selection", "activity_tag", "ff_model",
          "ff_model_pattern", "file", "heartrate_series", "impulse", "model_selection",
          "segment", "user_profile",
        ],
        unit: "impulse per day",
        mark: mkBar,
        make: makeImpulse,
      ),
    )
  ]
