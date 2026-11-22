## `nch calendar [SUBJECT]`: a subject on a calendar, a row for each month and the days in columns by weekday (weeks start on
## Monday).  The calendar is a view (it knows no subject): the package that manages a subject contributes its frame
## (`calendar/frames`: for the activities, the days a selected activity started on), and the calendar marks those days.  It
## takes no criteria, like `climbs` and `map`: to see a calendar of some activities, select them first (see
## `nch activities --select`).

import std/[options, strformat, strutils, terminal, times]
import ../../core/[errors, extension, globals]
import ../fit/time
import ../subject/subjects
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
  synopsis = "usage: nch [--db PATH] [--user NAME] calendar [SUBJECT] [-v]"
  intro = @[
    ~"A subject (by default the activities of the selection: see `nch activities --select`) on a calendar: a row for each month that has a marked day, the days in columns by weekday (weeks start on Monday).  In the selection's colour: a marked day (for the activities, one when an activity started); dimmed: none.  The months either side of a gap are marked (a name in the warning colour, or a * without colour), as are the months that were left out."
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
      )
    ],
  )

type Chosen* = object ## the subject and its frame
  subject*: Subject
  frame*: CalendarFrame

proc choose*(g: Globals, p: Params): Parsed[Chosen] =
  ## The subject the command line asks for and its frame, or what is wrong (the registry says what exists).
  let all = g.extensions.get(subjectPoint)
  if all.len == 0:
    return problemWith[Chosen](~"no subject can be shown on a calendar")
  let name = p.subject.get(defaultSubject(all).name)
  var names: seq[string]
  var found = none(Subject)
  for s in all:
    names.add s.name
    if s.name == name:
      found = some(s)
  if found.isNone:
    let known = names.join(", ")
    return problemWith[Chosen](~"no subject '{name}' (the subjects are {known})")
  let frames = framesOf(g.extensions.get(calendarFramePoint), name)
  if frames.len == 0:
    return problemWith[Chosen](~"{name} cannot be shown on a calendar")
  parsedOk(Chosen(subject: found.get, frame: frames[0]))

proc skippedWarning(marks: seq[UnixTime], zone: Timezone): seq[Line] =
  ## The last line of a calendar of the months with data, if it left some out.
  let n = skippedMonths(marks, zone)
  if n > 0:
    let months = counted(n, "month", "months")
    result.add warnLine(
      ~"{months} with nothing marked omitted; use `--verbose` to show them"
    )

proc lines*(
    st: Session,
    c: Chosen,
    backgrounds: seq[CalendarBackground],
    p: Params,
    zone: Timezone,
    screen: Screen,
): seq[Line] {.raises: [StoreError].} =
  ## The calendar of the subject over the days of the `backgrounds` (`calendar/background`), and its last lines.
  let made = c.frame.make(st)
  var background: seq[UnixTime]
  for b in backgrounds:
    background.add b.make(st)
  result = calendarLines(made.marks, background, zone, p.verbose, screen)
  result.add made.summary
  if not p.verbose:
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
        if isatty(stdout):
          terminalWidth()
        else:
          0,
    )
    let c = chosen.params
    if c.frame.readsSelection and c.subject.selected(st) == 0:
      g.warn emptyText(c.subject)
      return exitOk
    for l in lines(
      st, chosen.params, g.extensions.get(calendarBackgroundPoint), p, local(), screen
    ):
      g.show(osOut, l)
    exitOk
  except StoreError as e:
    failure(g, "nch calendar", e.msg)
  finally:
    st.close()
