## The frames of the models on a plot (`plot/frames`, subject `ff`): the fitness, the fatigue and the form of each selected
## model, a series a model, the first two scaled by the model's scales so that form is their difference
## (`fitness-scale * fitness - fatigue-scale * fatigue`).  Each counts the user's activities whose tags the model chooses,
## all of them (never the activity selection).  The curves are exact, drawn at the end of each day and either side of each
## impulse (`curve.sampleTimes`).  What is lacking is worked out first (the impulses, in a transaction of their own).  With
## `--file` each frame says its latest value for each model, and how it stands among the days before.

import std/[options, strformat, times]
import ../../core/[errors, extension, line]
import ../plot/frames
import ../ui/style
import ../user/session
import ./[calc, curve, impulses, models, stats]

{.push raises: [].}

type Which = enum
  wFitness = "fitness"
  wFatigue = "fatigue"
  wForm = "form"

func valuesOf(m: Model, lumps: seq[Lump], which: Which, times: seq[int64]): seq[float] =
  ## The curve at each time, scaled as the model says.
  let fit = curveAt(lumps, m.fitnessDays, times)
  let fat = curveAt(lumps, m.fatigueDays, times)
  for k in 0 ..< times.len:
    result.add(
      case which
      of wFitness:
        m.fitnessScale * fit[k]
      of wFatigue:
        m.fatigueScale * fat[k]
      of wForm:
        m.fitnessScale * fit[k] - m.fatigueScale * fat[k]
    )

func styleOf(which: Which): StyleName =
  case which
  of wFitness:
    styleName"good"
  of wFatigue:
    styleName"bad"
  of wForm:
    styleName"em"

proc makeCurve(
    st: Session, period: Period, which: Which
): PlotData {.raises: [StoreError].} =
  let ms = selectedModels(st.db, st.userId)
  if fthrOf(st.db, st.userId).isNone:
    raiseStore(
      fmt"{st.userName} has no FTHR, which the impulses need (set it with `nch users --edit {st.userName} --fthr BPM`)"
    )
  result.warnings.add ensureImpulses(st, ms)
  let asOf = min(period.now, period.last)
  let label =
    if asOf == period.now:
      fromUnix(asOf).inZone(period.zone).format("yyyy-MM-dd HH:mm")
    else:
      localDate(asOf - 1, period.zone)
  for m in ms:
    let lumps = userLumps(st.db, st.userId, m)
    if lumps.len == 0:
      result.warnings.add plain(
        fmt"the model {m.name} counts no activity with an impulse"
      )
      continue
    let times = sampleTimes(lumps, period.first, period.last, period.zone)
    let values = valuesOf(m, lumps, which, times)
    var s = Series(name: m.name)
    for k, t in times:
      s.points.add (t, values[k])
    result.series.add s
    # the latest value, against the end of each day before its own
    var standing = none(Standing)
    if lumps[0].t <= asOf:
      let earlier =
        dayEnds(lumps[0].t, civilOf(asOf, period.zone) - secondsPerDay, period.zone)
      let v = valuesOf(m, lumps, which, earlier & @[asOf])
      standing = some(standing(v[^1], v[0 ..^ 2]))
    result.notes.add noteLine(label, m.name, $which, styleOf(which), standing)

proc makeFitness(
    st: Session, period: Period
): PlotData {.nimcall, raises: [StoreError].} =
  makeCurve(st, period, wFitness)

proc makeFatigue(
    st: Session, period: Period
): PlotData {.nimcall, raises: [StoreError].} =
  makeCurve(st, period, wFatigue)

proc makeForm(st: Session, period: Period): PlotData {.nimcall, raises: [StoreError].} =
  makeCurve(st, period, wForm)

const read = @[
  "activity", "activity_tag", "ff_model", "ff_model_pattern", "file", "channel_series",
  "impulse", "model_selection", "ride_break", "user_profile",
]

proc frame(name, summary: string, make: MakePlot): PlotFrame =
  PlotFrame(
    subject: "ff",
    name: name,
    summary: summary,
    shown: true,
    readsSelection: true,
    tables: read,
    unit: name,
    mark: mkLine,
    axis: axDays,
    make: make,
  )

proc contributions*(): seq[Contribution] =
  ## The frames of the models, offered to the plot.
  @[
    contribute(
      plotFramePoint,
      frame("fitness", "the fitness of each selected model, scaled", makeFitness),
    ),
    contribute(
      plotFramePoint,
      frame("fatigue", "the fatigue of each selected model, scaled", makeFatigue),
    ),
    contribute(
      plotFramePoint,
      frame(
        "form", "the form of each selected model: scaled fitness minus scaled fatigue",
        makeForm,
      ),
    ),
  ]
