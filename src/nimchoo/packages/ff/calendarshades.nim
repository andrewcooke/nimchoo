## The shades of the models on a calendar (`calendar/shades`): the fitness, fatigue and form of the first selected model
## (by name), each at the end of every interval the calendar asks for (three a day), scaled as the model says (`curve`).
## The impulses that are lacking are worked out first.

import std/[options, strformat]
import ../../core/[errors, extension, line]
import ../calendar/frames
import ../user/session
import ./[calc, curve, impulses, models]

{.push raises: [].}

type Which = enum
  wFitness = "fitness"
  wFatigue = "fatigue"
  wForm = "form"

proc makeShade(
    st: Session, intervals: seq[Interval], which: Which
): ShadeData {.raises: [StoreError].} =
  let ms = selectedModels(st.db, st.userId)
  if ms.len == 0:
    result.warnings.add plain(
      fmt"no model is selected, so there is no {which} to show (see `nch ff --select`)"
    )
    return
  let m = ms[0]
  if fthrOf(st.db, st.userId).isNone:
    raiseStore(
      fmt"{st.userName} has no FTHR, which the impulses need (set it with `nch users --edit {st.userName} --fthr BPM`)"
    )
  result.warnings.add ensureImpulses(st, @[m])
  let lumps = userLumps(st.db, st.userId, m)
  var ends: seq[int64]
  for i in intervals:
    ends.add i.t1
  let fit = curveAt(lumps, m.fitnessDays, ends)
  let fat = curveAt(lumps, m.fatigueDays, ends)
  result.label = fmt"{which} of {m.name}"
  for k in 0 ..< ends.len:
    result.values.add(
      case which
      of wFitness:
        m.fitnessScale * fit[k]
      of wFatigue:
        m.fatigueScale * fat[k]
      of wForm:
        m.fitnessScale * fit[k] - m.fatigueScale * fat[k]
    )

proc makeFitness(
    st: Session, intervals: seq[Interval]
): ShadeData {.nimcall, raises: [StoreError].} =
  makeShade(st, intervals, wFitness)

proc makeFatigue(
    st: Session, intervals: seq[Interval]
): ShadeData {.nimcall, raises: [StoreError].} =
  makeShade(st, intervals, wFatigue)

proc makeForm(
    st: Session, intervals: seq[Interval]
): ShadeData {.nimcall, raises: [StoreError].} =
  makeShade(st, intervals, wForm)

const read = @[
  "activity", "activity_tag", "ff_model", "ff_model_pattern", "file", "channel_series",
  "impulse", "model_selection", "ride_break", "user_profile",
]

proc shade(name, summary: string, make: auto): Contribution =
  contribute(
    calendarShadePoint,
    CalendarShade(name: name, summary: summary, kind: skCurve, tables: read, make: make),
  )

proc contributions*(): seq[Contribution] =
  ## The shades of the models, offered to the calendar.
  @[
    shade("fitness", "the fitness of the first selected model, scaled", makeFitness),
    shade("fatigue", "the fatigue of the first selected model, scaled", makeFatigue),
    shade(
      "form",
      "the form of the first selected model: scaled fitness minus scaled fatigue",
      makeForm,
    ),
  ]
