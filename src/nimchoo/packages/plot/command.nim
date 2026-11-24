## `nch plot [SUBJECT]`: a subject over time.  The plot is a view (it knows no subject): the packages that manage a subject
## contribute its frames (`plot/frames`: the fitness, fatigue and form of the selected models, the impulse of the selected
## activities each day ...), each made as a CSV file of its own in the cache directory (`time,series,value`, a row a point),
## and a page draws them in the browser, a panel each.
##
## A subject's frames are over days (made for the period asked for) or over the time of one activity (the `activity`
## subject: made for each of the subject's things that the page ticks, `&activity=ID`, or for every one with `--file`, a
## series each; `--after` and `--before` mean nothing there and are refused).
##
## A plot is a live view: each frame is made again from the data as they are whenever it is shown.  The page is the
## subject's (`/plot/ff`, `plot-ff.html`, with `--after` and `--before` in its address and its name) and lists every frame of
## it; the frames ticked are fetched from the same address with `frame=NAME` (the worker with `--frame`), and the browser
## remembers which are ticked.  The files are named by the subject, the frame and the period (`plot-ff-fitness.csv`);
## `--file` makes those of `--frames`, and says what the frames have to say after them (the latest values).
##
## This module is above `subject`: it reads the registry of subjects and of frames, and nothing of the packages that provide
## them.  Days are the user's timezone's (this computer's).

import std/[options, sequtils, strformat, strutils, times]
import ../cache/cache
import ../util/atomic/atomic
import ../../core/[extension, globals, ids]
import ../../core/errors
import ../subject/[subjects, views]
import ../ui/style
import ../util/args/[args, usage]
import ../web/[pages, view]
import ../user/session
import ./[frames, page, params]

{.push raises: [].}

const commandName* = "plot" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch plot`, described (for tab completion).
  plotSpec().docs

const
  synopsis =
    "usage: nch [--db PATH] [--user NAME] plot [SUBJECT] [--after DAY] [--before DAY] [--file [--frames FRAME...] | --stop | [--start] [--port N] [--new-token]]"
  intro = @[
    ~"Show a subject over time: by default the activities of the selection (see `nch activities --select`); `nch plot ff`, the fitness, fatigue and form of the models selection (see `nch ff`).  What is drawn are the subject's frames, in the table below, each made by the package that knows about it: the page lists them, and you tick the ones to draw, each in a panel of its own (the browser remembers them; at first, those marked *).  On the page the wheel zooms, a drag moves and a double-click shows everything.  It serves the page on localhost and opens it in a browser (one server serves every page, and keeps running after the command returns: `--stop` stops it); with `--file` it makes a CSV file for each frame (those of `--frames`: a row a point, `time,series,value`) in the cache directory instead, prints where, and then what the frames say about the latest values."
  ]
  notes = @[
    ~"A frame is made from the data as they are when it is shown: reload the page to see them as they are now.  Days are this computer's timezone's."
  ]

proc usageText*(g: Globals, width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the subjects with their frames, wrapped to `width`.
  usageOf(
    synopsis,
    width,
    intro,
    plotSpec().docs,
    notes,
    @[
      (
        "subjects and frames",
        frameTable(
          g.extensions.get(subjectPoint), g.extensions.get(plotFramePoint), width
        ),
      )
    ],
  )

type Chosen = object
  subject: Subject
  axis: Axis ## what the subject's frames are over (they share it)
  listed: seq[PlotFrame] ## every frame of the subject
  frames: seq[PlotFrame] ## what `--file` makes, in order

proc choose(g: Globals, p: Params): Parsed[Chosen] =
  ## The subject and frames the command line asks for, or what is wrong with them (the registry says what exists).
  let subject = chooseSubject(g.extensions.get(subjectPoint), p.subject, "a plot")
  if subject.kind != pkOk:
    return problemWith[Chosen](subject.why)
  let all = g.extensions.get(plotFramePoint)
  let frames = chooseFrames(all, subject.params.name, p.frames, "a plot")
  if frames.kind != pkOk:
    return problemWith[Chosen](frames.why)
  let listed = framesOf(all, subject.params.name)
  let axis = listed[0].axis # (chooseFrames refused a subject with none)
  if axis == axActivity and (p.firstDay.isSome or p.lastDay.isSome):
    return problemWith[Chosen](
      ~"`--after` and `--before` are for a plot over days: the frames of {subject.params.name} are over the time of one activity"
    )
  if axis == axActivity and subject.params.pick.isNone:
    return problemWith[Chosen](
      ~"{subject.params.name} cannot be shown one by one, which its frames need"
    )
  parsedOk(
    Chosen(subject: subject.params, axis: axis, listed: listed, frames: frames.params)
  )

proc dayStart(civil: int64, tz: Timezone): int64 =
  ## The instant a calendar date (Unix seconds at its start in UTC) starts in a timezone.
  let d = fromUnix(civil).utc
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, tz).toTime.toUnix

proc civilOf(t: int64, tz: Timezone): int64 =
  ## The date at an instant in a timezone, as Unix seconds at its start in UTC.
  let d = fromUnix(t).inZone(tz)
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, utc()).toTime.toUnix

proc periodOf*(p: Params, now: int64, tz: Timezone): Period =
  ## The period of time the options ask for: from the start of `--after` (else as early as there are data) to the end of the
  ## day before `--before` (else of today), in the timezone.
  let lastDay = p.lastDay.get(civilOf(now, tz))
  Period(
    first: (if p.firstDay.isSome: some(dayStart(p.firstDay.get, tz))
    else: none(int64)),
    last: dayStart(lastDay + 86400, tz),
    now: now,
    zone: tz,
  )

proc dayText(civil: int64): string =
  fromUnix(civil).utc.format("yyyy-MM-dd")

proc periodParts(p: Params): seq[string] =
  ## What the options say about the period, for the names of the files (`from-2026-01-01`, `to-2026-11-22`).
  if p.firstDay.isSome:
    result.add "from-" & dayText(p.firstDay.get)
  if p.lastDay.isSome:
    result.add "to-" & dayText(p.lastDay.get)

proc fileStem(subject: string, frame: Option[string], p: Params): string =
  ## What a file is named: `plot-ff` (the page), `plot-ff-fitness-from-2026-01-01` (a frame), `plot-activity-altitude-123`
  ## (a frame of one activity, for the page).
  var parts = @[commandName, subject]
  if frame.isSome:
    parts.add frame.get
    if p.activity.isSome:
      parts.add $p.activity.get
  (parts & periodParts(p)).join("-")

proc webQuery*(p: Params): string =
  ## What the address of the page says besides the subject: the period asked for (before the defaults are filled in, so that a
  ## page asked for tomorrow is tomorrow's).
  var q: seq[string]
  if p.firstDay.isSome:
    q.add "after=" & dayText(p.firstDay.get)
  if p.lastDay.isSome:
    q.add "before=" & dayText(p.lastDay.get + 86400)
  q.join("&")

proc csvOf*(made: PlotData, tz: Timezone): string =
  ## The CSV of a frame: `time,series,value`, a row a point, the time with its offset (`2026-11-23T00:00:00-03:00`).
  result = "time,series,value\n"
  for s in made.series:
    let name = s.name.replace("\"", "\"\"")
    for (t, v) in s.points:
      let time = fromUnix(t).inZone(tz).format("yyyy-MM-dd'T'HH:mm:sszzz")
      result.add fmt"{time},""{name}"",{v:.4f}" & "\n"

proc ofActivities(
    st: Session, c: Chosen, f: PlotFrame, p: Params
): PlotData {.raises: [StoreError].} =
  ## A frame of one activity, made for the one the page asks for (its series as the frame names them: the page knows which
  ## activity it asked for), or for every one of the subject's (`--file`: each series named by its activity, and by its
  ## own name too unless that is "default").
  let picks = c.subject.pick.get()(st)
  var wanted = picks
  if p.activity.isSome:
    wanted = picks.filterIt(it.id == p.activity.get)
    if wanted.len == 0:
      raiseStore(
        fmt"activity {p.activity.get} is not in the selection of {c.subject.name}"
      )
  for pick in wanted:
    let made = f.makeActivity(st, ActivityId(pick.id))
    for s in made.series:
      let name =
        if p.activity.isSome:
          s.name
        elif s.name == "default":
          pick.label
        else:
          pick.label & ": " & s.name
      result.series.add Series(name: name, points: s.points)
    result.notes.add made.notes
    result.warnings.add made.warnings

proc makeFrames(
    g: Globals, c: Chosen, frames: seq[PlotFrame], p: Params, dir: string
): Made =
  ## Make the file of each frame, from the data as they are now; what the frames say goes after the files.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return Made(status: failure(g, "nch plot", e.msg))
  try:
    let tz = local()
    let period = periodOf(p, getTime().toUnix, tz)
    for f in frames:
      let made =
        case f.axis
        of axDays:
          f.make(st, period)
        of axActivity:
          ofActivities(st, c, f, p)
      for w in made.warnings:
        g.warn w
      let path = cacheFile(dir, fileStem(c.subject.name, some(f.name), p), "csv").get
      writeAtomic(path, csvOf(made, tz))
      result.paths.add path
      result.notes.add made.notes
  except StoreError as e:
    result = Made(status: failure(g, "nch plot", e.msg))
  except IOError, OSError:
    result = Made(status: cannotWrite(g, "nch plot", dir))
  finally:
    st.close()

proc makePage(g: Globals, c: Chosen, p: Params, dir: string): Made =
  ## Make the page: every frame of the subject, those shown by default ticked (it fetches the data of each frame it shows),
  ## and, when the frames are of one activity, the subject's things to tick.
  var picks: seq[Pick]
  if c.axis == axActivity:
    var st: Session
    try:
      st = openSession(g)
    except StoreError as e:
      return Made(status: failure(g, "nch plot", e.msg))
    try:
      picks = c.subject.pick.get()(st)
    except StoreError as e:
      return Made(status: failure(g, "nch plot", e.msg))
    finally:
      st.close()
  try:
    let path = cacheFile(dir, fileStem(c.subject.name, none(string), p), "html").get
    writeAtomic(path, pageHtml(c.listed, c.axis, picks, fmt"Plot of {c.subject.name}"))
    Made(paths: @[path])
  except IOError, OSError:
    Made(status: cannotWrite(g, "nch plot", dir))
  except TemplateError as e:
    Made(status: templateFailure(g, "nch plot", e.msg))

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch plot ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g, g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch plot", usageText(g, g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch plot", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  let chosen = choose(g, p)
  if chosen.kind != pkOk:
    return usageError(g, "nch plot", usageText(g, g.textWidth(osErr)), chosen.problem)
  let c = chosen.params
  runView(
    g,
    p.web,
    View(
      command: commandName,
      address: commandName & "/" & c.subject.name,
      query: webQuery(p),
      nothing: proc(): Option[int] =
        stopIfEmpty(g, c.subject, c.frames.anyIt(it.readsSelection), "nch plot"),
      page: proc(dir: string): Made =
        makePage(g, c, p, dir),
      frame: proc(name, dir: string): Made =
        let one = chooseFrames(c.listed, c.subject.name, @[name], "a plot")
        if one.kind != pkOk:
          return Made(
            status: usageError(g, "nch plot", usageText(g, g.textWidth(osErr)), one.why)
          )
        makeFrames(g, c, one.params, p, dir),
      files: proc(dir: string): Made =
        makeFrames(g, c, c.frames, p, dir),
      frameAsked: p.frame,
    ),
  )
