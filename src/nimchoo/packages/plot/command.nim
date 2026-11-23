## `nch plot [SUBJECT]`: a subject over time.  The plot is a view (it knows no subject): the packages that manage a subject
## contribute its frames (`plot/frames`: the fitness, fatigue and form of the selected models, the impulse of the selected
## activities each day ...), each made as a CSV file of its own in the cache directory (`time,series,value`, a row a point),
## and a page draws them in the browser, a panel each.
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
import ../../core/[extension, globals]
import ../../core/errors
import ../subject/subjects
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
    ~"Show a subject over time: by default the activities of the selection (see `nch activities --select`); `nch plot ff`, the fitness, fatigue and form of the models selection (see `nch ff`).  What is drawn are the subject's frames, in the table below, each made by the package that knows about it: the page lists them, and you tick the ones to draw, each in a panel of its own (the browser remembers them; at first, those marked *).  Drag across a panel to zoom; double-click to zoom out.  It serves the page on localhost and opens it in a browser (one server serves every page, and keeps running after the command returns: `--stop` stops it); with `--file` it makes a CSV file for each frame (those of `--frames`: a row a point, `time,series,value`) in the cache directory instead, prints where, and then what the frames say about the latest values."
  ]
  notes = @[
    ~"A frame is made from the data as they are when it is shown: reload the page to see them as they are now.  Days are this computer's timezone's."
  ]

func registryLines(subjects: seq[Subject], all: seq[PlotFrame], width: int): seq[Line] =
  ## The subjects and their frames, as a table (from the registry), and what the marks mean.
  var rows: seq[seq[Line]]
  var default = ""
  for s in subjects:
    if s.isDefault:
      default = s.name
    for f in framesOf(all, s.name):
      rows.add @[
        plain(s.name), plain(f.name & (if f.shown: "*" else: "")), plain(f.summary)
      ]
  if rows.len == 0:
    return
  result = tableLines(@["subject", "frame", "what it is"], rows, width)
  result.add plain("")
  result.add (
    ~"* drawn when `--frames` is not given; the subject is {default} when none is given."
  ).wrapped(width)

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
        registryLines(
          g.extensions.get(subjectPoint), g.extensions.get(plotFramePoint), width
        ),
      )
    ],
  )

type Chosen = object
  subject: Subject
  listed: seq[PlotFrame] ## every frame of the subject
  frames: seq[PlotFrame] ## what `--file` makes, in order

proc choose(g: Globals, p: Params): Parsed[Chosen] =
  ## The subject and frames the command line asks for, or what is wrong with them (the registry says what exists).
  let all = g.extensions.get(subjectPoint)
  let subject = findSubject(all, p.subject)
  if subject.isNone:
    return problemWith[Chosen](noSubject(all, p.subject, "a plot"))
  let name = subject.get.name
  let mine = framesOf(g.extensions.get(plotFramePoint), name)
  if mine.len == 0:
    return problemWith[Chosen](~"no frame of {name} can be shown on a plot")
  var chosen = Chosen(subject: subject.get, listed: mine)
  if p.frames.len == 0:
    chosen.frames = mine.filterIt(it.shown)
    if chosen.frames.len == 0:
      chosen.frames = mine
    return parsedOk(chosen)
  let names = mine.mapIt(it.name).join(", ")
  for want in p.frames:
    let there = mine.filterIt(it.name == want)
    if there.len == 0:
      return problemWith[Chosen](
        ~"'{want}' is not a frame of {name} (the frames are {names})"
      )
    if there[0] notin chosen.frames:
      chosen.frames.add there[0]
  parsedOk(chosen)

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
  ## What a file is named: `plot-ff` (the page), `plot-ff-fitness-from-2026-01-01` (a frame).
  var parts = @[commandName, subject]
  if frame.isSome:
    parts.add frame.get
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

proc checkSelection(g: Globals, c: Chosen, frames: seq[PlotFrame]): Option[int] =
  ## Whether to stop, and with what status, before serving or making the files: an empty selection (if a frame shown
  ## reads it) is said as a warning and stops with success; none: go on.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return some(failure(g, "nch plot", e.msg))
  try:
    if frames.anyIt(it.readsSelection) and c.subject.selected(st) == 0:
      g.warn emptyText(c.subject)
      return some(exitOk)
    none(int)
  except StoreError as e:
    some(failure(g, "nch plot", e.msg))
  finally:
    st.close()

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
      let made = f.make(st, period)
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
  ## Make the page: every frame of the subject, those shown by default ticked (it fetches the data of each frame it shows).
  try:
    let path = cacheFile(dir, fileStem(c.subject.name, none(string), p), "html").get
    writeAtomic(path, pageHtml(c.listed, fmt"Plot of {c.subject.name}"))
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
        checkSelection(g, c, c.frames),
      page: proc(dir: string): Made =
        makePage(g, c, p, dir),
      frame: proc(name, dir: string): Made =
        let one = c.listed.filterIt(it.name == name)
        if one.len == 0:
          return Made(
            status: usageError(
              g,
              "nch plot",
              usageText(g, g.textWidth(osErr)),
              ~"'{name}' is not a frame of {c.subject.name}",
            )
          )
        makeFrames(g, c, one, p, dir),
      files: proc(dir: string): Made =
        makeFrames(g, c, c.frames, p, dir),
      frameAsked: p.frame,
    ),
  )
