## `nch calendar [SUBJECT]`: a subject on a calendar, a row for each month and the days in columns by weekday (weeks start on
## Monday).  The calendar is a view (it knows no subject): the package that manages a subject contributes its frame
## (`calendar/frames`: for the activities, the days a selected activity started on), and the calendar marks those days.  It
## takes no criteria, like `climbs` and `map`: to see a calendar of some activities, select them first (see
## `nch activities --select`).  `--shade NAME` colours the background by a value over time (`calendar/shades`: fitness,
## fatigue and form of the first selected model, the impulse of the selected activities), scaled from the lowest shown to
## the highest; `--detail N` says which months.

import std/[options, sequtils, strformat, strutils, tables, times]
import ../../core/[errors, extension, globals]
import ../fit/time
import ../subject/[subjects, views]
import ../ui/[style]
import ../user/session
import ../util/args/[args, usage]
import ./[calendar, frames, params]
import ../ui/units

{.push raises: [].}

const commandName* = "calendar" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch calendar`, described (for tab completion).
  calendarSpec().docs

const
  synopsis =
    "usage: nch [--db PATH] [--user NAME] calendar [SUBJECT] [--detail N] [--shade NAME]"
  intro = @[
    ~"A subject (by default the activities of the selection: see `nch activities --select`) on a calendar: a row for each month that has a marked day, the days in columns by weekday (weeks start on Monday).  In the selection's colour: a marked day (for the activities, one when an activity started); dimmed: none.  The months either side of a gap are marked (a name in the warning colour, or a * without colour), as are the months that were left out (see `--detail`).  With `--shade NAME` the background of each day shows a value (each third of a day for a curve), by the theme's stops, NAME-0 for the lowest shown to NAME-1 for the highest, with any between (default-0 ... default-1 if the theme has none of its own), and a last line says what and how much."
  ]

func registryLines(
    subjects: seq[Subject], all: seq[CalendarFrame], width: int
): seq[Line] =
  ## The subjects that have a calendar, as a table (from the registry), and which is the default.
  var rows: seq[seq[Line]]
  var default = ""
  for s in subjects:
    if s.isDefault:
      default = s.name
    for f in framesOf(all, s.name):
      rows.add @[plain(s.name), plain(f.summary)]
  if rows.len == 0:
    return
  result = tableLines(@["subject", "what is marked"], rows, width)
  result.add plain("")
  for l in wrap(fmt"The subject is {default} when none is given.", width):
    result.add plain(l)

func shadeLines(shades: seq[CalendarShade], width: int): seq[Line] =
  ## The shades, as a table (from the registry).
  var rows: seq[seq[Line]]
  for s in shades:
    rows.add @[plain(s.name), plain(s.summary)]
  if rows.len > 0:
    result = tableLines(@["shade", "what it shows"], rows, width)

proc usageText*(g: Globals, width: int): seq[Line] =
  ## The usage: the introduction, the options and the subjects that have a calendar, wrapped to `width`.
  usageOf(
    synopsis,
    width,
    intro,
    calendarSpec().docs,
    sections = @[
      (
        "subjects",
        registryLines(
          g.extensions.get(subjectPoint), g.extensions.get(calendarFramePoint), width
        ),
      ),
      ("shades", shadeLines(g.extensions.get(calendarShadePoint), width)),
    ],
  )

type Chosen* = object ## the subject and its frame, and the shade
  subject*: Subject
  frame*: CalendarFrame
  shade*: Option[CalendarShade]

proc choose*(g: Globals, p: Params): Parsed[Chosen] =
  ## The subject the command line asks for and its frame, or what is wrong (the registry says what exists).
  let subject = chooseSubject(g.extensions.get(subjectPoint), p.subject, "a calendar")
  if subject.kind != pkOk:
    return problemWith[Chosen](subject.why)
  let name = subject.params.name
  let frames = framesOf(g.extensions.get(calendarFramePoint), name)
  if frames.len == 0:
    return problemWith[Chosen](~"{name} cannot be shown on a calendar")
  var chosen = Chosen(subject: subject.params, frame: frames[0])
  if p.shade.isSome:
    let shades = g.extensions.get(calendarShadePoint)
    let found = shades.filterIt(it.name == p.shade.get)
    if found.len == 0:
      let names = shades.mapIt(it.name).join(", ")
      return problemWith[Chosen](
        ~"there is no shade '{p.shade.get}' (the shades are {names})"
      )
    chosen.shade = some(found[0])
  parsedOk(chosen)

proc skippedWarning(marks: seq[UnixTime], zone: Timezone): seq[Line] =
  ## The last line of a calendar of the months with data, if it left some out.
  let n = skippedMonths(marks, zone)
  if n > 0:
    let months = counted(n, "month", "months")
    result.add warnLine(
      ~"{months} with nothing marked omitted; `--detail 2` shows them"
    )

proc intervalsOf(
    shade: CalendarShade, months: seq[int], zone: Timezone, now: UnixTime
): tuple[intervals: seq[Interval], keys: seq[seq[int]]] =
  ## What a shade is asked for, for the months shown, and the thirds of days each value colours: a third of each day for a
  ## curve (its value at the end of the third), a day for a total; only what has ended by `now`.
  for m in months:
    let (year, month) = (m div 12, Month(m mod 12 + 1))
    for day in 1 .. getDaysInMonth(month, year):
      let midnight = dateTime(year, month, day, 0, 0, 0, 0, zone)
      let (start, next) = (midnight.toTime.toUnix, (midnight + 1.days).toTime.toUnix)
      let key = dayKey(year, month, day)
      case shade.kind
      of skCurve:
        for third in 0 .. 2:
          let t1 = start + (third + 1) * (next - start) div 3
          if t1 <= int64(now):
            result.intervals.add (start + third * (next - start) div 3, t1)
            result.keys.add @[thirdKey(key, third)]
      of skDaily:
        if next <= int64(now):
          result.intervals.add (start, next)
          result.keys.add @[thirdKey(key, 0), thirdKey(key, 1), thirdKey(key, 2)]

proc lines*(
    st: Session,
    c: Chosen,
    days: seq[CalendarDays],
    p: Params,
    zone: Timezone,
    screen: Screen,
    now: UnixTime,
): seq[Line] {.raises: [StoreError].} =
  ## The calendar of the subject over the days of `days` (`calendar/days`), shaded if asked, and its last lines.
  let made = c.frame.make(st)
  var background: seq[UnixTime]
  for b in days:
    background.add b.make(st)
  let detail = p.detail.get(
    if c.shade.isSome and c.shade.get.kind == skCurve: dtToNow else: dtData
  )
  var shading = none(Shading)
  var after: seq[Line]
  if c.shade.isSome and made.marks.len > 0:
    let shade = c.shade.get
    let (intervals, keys) =
      intervalsOf(shade, monthsShown(made.marks, zone, detail, now), zone, now)
    let got = shade.make(st, intervals)
    for w in got.warnings:
      after.add warnLine(w)
    if got.values.len > 0:
      doAssert got.values.len == intervals.len
      let (lo, hi) = (got.values.min, got.values.max)
      var s = Shading(style: shade.name)
      for k, v in got.values:
        let f = (if hi > lo: (v - lo) / (hi - lo) else: 0.5)
        for key in keys[k]:
          s.fractions[key] = f
      shading = some(s)
      after.add legendLine(s, got.label, lo, hi)
  result = calendarLines(made.marks, background, zone, detail, now, screen, shading)
  result.add made.summary
  result.add after
  if detail == dtData:
    result.add skippedWarning(made.marks, zone)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch calendar ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g, g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch calendar", usageText(g, g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch calendar", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  let chosen = choose(g, p)
  case chosen.kind
  of pkHelp, pkProblem:
    return
      usageError(g, "nch calendar", usageText(g, g.textWidth(osErr)), chosen.problem)
  of pkUnit:
    raiseAssert "choose gives no unit to ask about"
  of pkOk:
    discard
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch calendar", e.msg)
  try:
    let screen = Screen(
      colour: g.colour[osOut],
      width:
        if g.terminal[osOut]:
          some(g.textWidth(osOut))
        else:
          none(int),
    )
    let c = chosen.params
    if c.shade.isSome and not screen.colour:
      return failure(
        g,
        "nch calendar",
        ~"`--shade` is a colour, and this output has none (a pipe, a file, or `NO_COLOR`)",
      )
    if c.shade.isSome and not g.theme.hasShade(c.shade.get.name):
      let name = c.shade.get.name
      return failure(
        g,
        "nch calendar",
        ~"the theme {g.theme.name} has no colours for a shade: give it `default-0` and `default-1` (or `{name}-0` and `{name}-1`; and any stops between, `default-0.5`), each with a bg=#rrggbb (`nch --config` says where the theme is)",
      )
    let stop = stopIfEmpty(g, st, c.subject, c.frame.readsSelection)
    if stop.isSome:
      return stop.get
    for l in lines(
      st,
      chosen.params,
      g.extensions.get(calendarDaysPoint),
      p,
      local(),
      screen,
      UnixTime(getTime().toUnix),
    ):
      g.show(osOut, l)
    exitOk
  except StoreError as e:
    failure(g, "nch calendar", e.msg)
  finally:
    st.close()
