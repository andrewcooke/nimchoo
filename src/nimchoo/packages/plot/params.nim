## The command line of `nch plot`, parsed.  Pure.  `nch plot [SUBJECT]`: the subject is what the plot is of (the default one
## if it is left out); `--after` and `--before` say the span of time, and may be in the page's address
## (`/plot/ff?after=2026-01-01`); `--frames` says which frames `--file` makes, and `--frame` which one the worker makes for
## the page.  Which subjects and frames exist is the registry's to say (`subject/subjects`, `plot/frames`), so the command
## checks the names, not the parser.

import std/[options, strutils, times]
import ../../core/[extension, globals]
import ../util/args/args
import ../subject/subjects
import ../web/[request, webopts]
import ./frames

{.push raises: [].}

const secondsPerDay = 86400'i64

type
  Params* = object
    web*: WebMode ## `--file`, `--worker` and the options of serving
    subject*: Option[string] ## none: the default subject
    firstDay*, lastDay*: Option[int64]
      ## the first and the last day shown (`--after D`: D; `--before D`: the day before D), each a calendar date, as Unix
      ## seconds at its start in UTC (a day of the user's timezone)
    frames*: seq[string]
      ## what `--file` makes, in the order given; none: the frames that are shown unless told otherwise
    frame*: Option[string]
      ## for the page (with `--worker`): make the data of this one frame (`?frame=fitness`)

  Raw = object ## what the options fill in
    help: bool
    subjects: seq[string]
    frames: seq[string]
    frame: string
    firstDay, lastDay: Option[int64]
    web: WebArgs

proc parseDay*(s: string): Option[int64] =
  ## `2018-08-27`, as the start of that day in UTC (the form of `Params.firstDay`).
  if s.len != 10:
    return
  try:
    return some(parse(s, "yyyy-MM-dd", utc()).toTime.toUnix)
  except TimeParseError, ValueError:
    discard

func completeFrames(g: Globals, typed: string): seq[string] {.nimcall, raises: [].} =
  ## The names of the frames that start with what is typed (of every subject: the words before it are not known here).
  for f in g.extensions.get(plotFramePoint):
    if f.name.startsWith(typed) and f.name notin result:
      result.add f.name

proc takeFrames(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  if values.len == 0:
    return refuse(~"`{name}` needs at least one frame")
  for v in values:
    if not isWord(v):
      return refuse(~"'{v}' is not a name of a frame")
  p.frames.add values
  fine

func plotSpec*(): Spec[Raw] =
  ## The options of `nch plot`, with the web options.
  Spec[Raw](
    opts:
      @[
        custom(
          Raw,
          ["--after"],
          true,
          "DAY",
          ~"show from the start of that day, like 2018-08-27 (default: as early as there are data)",
          address = adValue,
          valid = day,
          body = (
            block:
              let d = parseDay(value)
              if d.isNone:
                return refuse(~"`{name}` is a day, like 2018-08-27 (not '{value}')")
              p.firstDay = d
              fine
          ),
        ),
        custom(
          Raw,
          ["--before"],
          true,
          "DAY",
          ~"show up to the start of that day: the day before is the last shown (default: up to the end of today)",
          address = adValue,
          valid = day,
          body = (
            block:
              let d = parseDay(value)
              if d.isNone:
                return refuse(~"`{name}` is a day, like 2018-08-27 (not '{value}')")
              p.lastDay = some(d.get - secondsPerDay)
              fine
          ),
        ),
        listOption[Raw](
          ["--frames"],
          takeFrames,
          "FRAME...",
          ~"with `--file`: the frames to make a file of, separated by spaces (see the table below); default: those marked *.  On the page, tick the frames to draw",
          completion = completesFrom(completeFrames),
          valid = isWord,
        ),
        text(
          Raw,
          ["--frame"],
          frame,
          "FRAME",
          ~"for the page, with `--worker`: make the data of this one frame (the page fetches each frame it shows)",
          address = adValue,
          valid = isWord,
        ),
      ] & webOptions(Raw, web, "the plot", "a CSV file for each frame") &
      @[helpFlag(Raw)],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      takeSubject(p.subjects, arg),
  )

func finish(raw: Raw): Parsed[Params] =
  let mode = webMode(raw.web)
  if mode.kind == pkProblem:
    return problemWith[Params](mode.why)
  if raw.subjects.len > 1:
    return problemWith[Params](tooManySubjects)
  if raw.firstDay.isSome and raw.lastDay.isSome and raw.firstDay.get > raw.lastDay.get:
    return problemWith[Params](~"`--after` is not before `--before`")
  if raw.frame.len > 0 and mode.params.kind != wkWorker:
    return problemWith[Params](~"`--frame` is for the page: it goes with `--worker`")
  if raw.frames.len > 0 and mode.params.kind != wkFile:
    return problemWith[Params](
      ~"`--frames` chooses the files of `--file`: on the page, tick the frames to draw (the browser remembers them)"
    )
  parsedOk(
    Params(
      web: mode.params,
      subject: (if raw.subjects.len == 1: some(raw.subjects[0])
      else: none(string)),
      firstDay: raw.firstDay,
      lastDay: raw.lastDay,
      frames: raw.frames,
      frame: (if raw.frame.len > 0: some(raw.frame) else: none(string)),
    )
  )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `[SUBJECT] [--after DAY] [--before DAY] [--frames FRAME...] [--file | --worker | --stop | --port N --start --new-token]`.
  parseCommand(args, plotSpec(), Raw(web: WebArgs()), finish)
